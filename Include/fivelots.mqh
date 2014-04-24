// Version 2
//+------------------------------------------------------------------+
//|                                                     fivelots.mqh |
//|                              Copyright © 2010, Timar Investments |
//|                               http://www.timarinvestments.com.au |
/*
   TODO:
     Add FVL_FirstPipTarget         Pip target required before adding 2nd lot.   
     Add FVL_SubsequentPipTarget    Pip target required before adding 3rd and subsequent lots.   

   If FVL_InitialTicket has a Take Profit target, then all
   additional lots will be given the same target.
   
   FVL_MaxPositions can be 0 in which case total lots are limited by the
   length of the FVL_Tickets array (20). Be aware, you will probably
   run out of margin before a large lot limit is reached.

  
*/
//+------------------------------------------------------------------+

//+-- Configuration -- must be initialised --------------------------+
bool FVL_IsTradeLong;
int FVL_InitialTicket;  // TODO: we can work this out. It's the ticket with the earliest OpenTime, with CloseTime=0 and our magic number
int FVL_Magic;
string FVL_OrderCommentPrefix;
double FVL_PipTarget;
bool FVL_UseDoubleInitialStop = false;
bool FVL_CloseAllTickets = false;
int FVL_MaxPositions = 5;

double FVL_StopToHalf_PipsFromEntry = 0;   // If set, aggregate stop is set to 1/2 aggregate pips won when (aggregate pips won / lots) >= this value

#define FVL_STRAT_ALLIN    0
#define FVL_STRAT_CHICKEN  1
#define FVL_STRAT_GRAVITON 2

int FVL_Strategy = FVL_STRAT_ALLIN;



// just trying these out
double FVL_LockInPipsAtBE = 0;


#define GV_AllIn "FVL-allin"

//+-- Globals -------------------------------------------------------+
int FVL_Tickets[20];      // sorted by ticket#
int FVL_TicketsCount=0;


//+------------------------------------------------------------------+

int FVL_init()
{
  GlobalVariableDel(GV_AllIn);
  FVL_FindAllRelatedTickets();
}


int FVL_deinit()
{
}


static int LastTicket = 0;
bool TicketFirstTime = false;


int FVL_start()
{
  FVL_FindAllRelatedTickets();
  FVL_ValidateInitialStopLoss();

  // You can use the TicketFirstTime variable to do "first time" logging
  if (LastTicket != FVL_InitialTicket)
  {
    TicketFirstTime = true;
    LastTicket = FVL_InitialTicket;
  }
  else
    TicketFirstTime = false;

  if (FVL_IsTradeOpen())
  {
    if (FVL_CloseAllTickets)
      FVL_CloseAllTickets();
    else
      FVL_ScaleIn();
  }
}



//+------------------------------------------------------------------+


void FVL_CloseAllTickets()
{
  double closePrice = FVL_GetCurrentClosePrice();
  for (int i=0; i < FVL_TicketsCount; i++)
    FVL_CloseTicket(closePrice, FVL_Tickets[i]);
}


void FVL_CloseTicket(double closePrice, int ticket)
{
  OrderReliableClose(ticket, OrderLots(), closePrice, MarketInfo(Symbol(), MODE_SPREAD));
}


string FVL_Comment_Tickets()
{
  string sTickets="";
  for (int iticket = 0; iticket < FVL_TicketsCount; iticket++)
  {
    if (iticket != 0)
      sTickets = sTickets + " ";
      
    if (FVL_IsTicketClosed(FVL_Tickets[iticket]))
      sTickets = sTickets + "(" + FVL_Tickets[iticket] + ")";
    else
      sTickets = sTickets + FVL_Tickets[iticket];
  }
  if (sTickets == "")
    return ("No input ticket");
  else
    return ("Tickets: " + sTickets);
}


int FVL_dir()
{
  if (FVL_IsTradeLong)
    return (+1);
  else
    return (-1);
}


void FVL_FindAllRelatedTickets()
{
  /*
    Start with the input tickets
    Find these tickets
    If the ticket is closed, check that it was opened after the initial ticket. If it was, we take a stab that it was one of ours.
    Partially closed tickets have a comemnt added to the closed portion and the new open portion
    Use this comment to find the linked tickets
  */

  FVL_TicketsCount = 0;
  if (FVL_InitialTicket == 0)
    return;
  
  FVL_Tickets[0] = FVL_InitialTicket;
  FVL_TicketsCount++;
  
  if (!OrderSelect(FVL_InitialTicket, SELECT_BY_TICKET))
    return;
    
  int initialTicketOpenTime = OrderOpenTime();
   
  int i;
  int total = OrdersTotal();
  for (i=0; i < total; i++)
  {
    if (OrderSelect(i, SELECT_BY_POS))
    {
      if (OrderMagicNumber() == FVL_Magic  &&  OrderOpenTime() > initialTicketOpenTime)
      {
        FVL_Tickets[FVL_TicketsCount] = OrderTicket();
        FVL_TicketsCount++;
      }
    }
  }
  
  total = OrdersHistoryTotal();
  for (i=0; i < total; i++)
  {
    if (OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
    {
      if (OrderMagicNumber() == FVL_Magic) //  && OrderOpenTime() > initialTicketOpenTime)
      {
        if (StringSubstr(OrderComment(), 0, StringLen(FVL_OrderCommentPrefix)) == FVL_OrderCommentPrefix)
        {
          int idx = StringFind(OrderComment(), ":");
          if (idx >= 0)
          {
            if (StrToInteger(StringSubstr(OrderComment(), idx+1)) == FVL_InitialTicket)
            {
              FVL_Tickets[FVL_TicketsCount] = OrderTicket();
              FVL_TicketsCount++;
            }
          }
        }
      }
    }
  }
  
  FVL_SortTicketsByTicketNumber();
}


double FVL_GetCurrentClosePrice()
{
  if (FVL_IsTradeLong)
    return (Bid);
  else
    return (Ask);
}


double FVL_GetCurrentOpenPrice()
{
  if (FVL_IsTradeLong)
    return (Ask);
  else
    return (Bid);
}


string FVL_GetOrderComment()
{
  return (FVL_OrderCommentPrefix + " #" + FVL_Magic + " :" + FVL_InitialTicket);
}


double FVL_GetExpectedEntryPipsByPos(int ticketpos)
{
  switch (FVL_Strategy)
  {
    case FVL_STRAT_CHICKEN:
      return ((ticketpos+1) * FVL_PipTarget);
    
    case FVL_STRAT_GRAVITON:
    {
      if (ticketpos < 2)
        return (ticketpos * FVL_PipTarget);
      else
        return ((ticketpos+1) * FVL_PipTarget);
    }
    
    default: // allin
      return (ticketpos * FVL_PipTarget);
  }
}


double FVL_GetTicketLotSize(int ticket)
{
  if (OrderSelect(ticket, SELECT_BY_TICKET))
    return (OrderLots());
  else
    return (0.0);
}


double FVL_GetProfitAtStopPips()
{
  double total = 0.0;
  
  for (int i=0; i < FVL_TicketsCount; i++)
  {
    OrderSelect(FVL_Tickets[i], SELECT_BY_TICKET);
    if (FVL_IsTradeLong)
      total += (OrderStopLoss() - OrderOpenPrice())/Point/10;
    else
      total += (OrderOpenPrice() - OrderStopLoss())/Point/10;    
  }
  
  return (total);
}


double FVL_GetProfitAtStop$()
{
  double profitAtStop$ = 0.0;
  double closePrice = FVL_GetCurrentClosePrice();
  bool isLong = FVL_IsTradeLong;

  for (int i = 0;  i < FVL_TicketsCount;  i++)
  {
    if (OrderSelect(FVL_Tickets[i], SELECT_BY_TICKET))
    {
      if (OrderStopLoss() > 0)
      {
        if (isLong)
          profitAtStop$ += ((OrderStopLoss() - OrderOpenPrice()) / Point) * MarketInfo(Symbol(), MODE_TICKVALUE) * OrderLots();
        else
          profitAtStop$ += ((OrderOpenPrice() - OrderStopLoss()) / Point) * MarketInfo(Symbol(), MODE_TICKVALUE) * OrderLots();
      }    
    }
  }

  return (profitAtStop$);
}


double FVL_GetTicketProfit(int ticket)
{
  if (OrderSelect(ticket, SELECT_BY_TICKET))
    return (OrderProfit() + OrderSwap());
  else
    return (0.0);
}


double FVL_GetTicketOpenPrice(int ticket)
{
  if (OrderSelect(ticket, SELECT_BY_TICKET))
    return (OrderOpenPrice());
  else
    return (0.0);
}


double FVL_GetTotalLots()
{
  double lots = 0.0;
  for (int i=0;  i < FVL_TicketsCount;  i++)
    if (OrderSelect(FVL_Tickets[i], SELECT_BY_TICKET))
      lots += OrderLots();
  return (lots);
}


double FVL_GetTotalProfit$()
{  
  double total = 0.0;
  for (int i=0; i < FVL_TicketsCount; i++)
    total += FVL_GetTicketProfit(FVL_Tickets[i]);
  return (total);
}


double FVL_GetTotalProfitPips()
{
  double price = FVL_GetCurrentClosePrice();
  int dir = FVL_dir();
  double total = 0.0;
  for (int i=0; i < FVL_TicketsCount; i++)
  {
    OrderSelect(FVL_Tickets[i], SELECT_BY_TICKET);
    if (FVL_IsTradeLong)
      total += (price - OrderOpenPrice())/Point/10;
    else
      total += (OrderOpenPrice() - price)/Point/10;
  }
  return (total);
}


double FVL_InitialTicketEntryPrice()
{
  if (OrderSelect(FVL_InitialTicket, SELECT_BY_TICKET))
    return (OrderOpenPrice());
  else
    return (0.0);
}


bool FVL_IsPipTargetReached(double piptarget)
{
  if (FVL_IsTradeLong)
    return (FVL_GetCurrentClosePrice() > FVL_InitialTicketEntryPrice() + FVL_PipsToPrice(piptarget));
  else
    return (FVL_GetCurrentClosePrice() < FVL_InitialTicketEntryPrice() - FVL_PipsToPrice(piptarget));
}


bool FVL_IsTicketClosed(int ticket)
{
  if (OrderSelect(ticket, SELECT_BY_TICKET))
    return (OrderCloseTime() != 0);
  else
    return (false);
}


bool FVL_IsTicketOpen(int ticket)
{
  if (OrderSelect(ticket, SELECT_BY_TICKET))
    return ( (OrderType() == OP_BUY || OrderType() == OP_SELL)
             && (OrderCloseTime() == 0));
  else
    return (false);
}


bool FVL_IsTradeOpen()
{
  return (FVL_IsTicketOpen(FVL_InitialTicket));
}


#define MINIMUM_STOP_MOVE_POINTS  10

void FVL_ModifyTicket(int ticket,  double sl,  double tp)
{
  if (!OrderSelect(ticket, SELECT_BY_TICKET))
    return;

  bool isLong = (OrderType() == OP_BUY || OrderType() == OP_BUYLIMIT || OrderType() == OP_BUYSTOP);
  int dir;
  if (isLong) dir=+1; else dir=-1;

  sl = NormalizeDouble(sl, Digits);
  tp = NormalizeDouble(tp, Digits);
  
  double diff;
  double diffPoints;
  
  if (sl != 0  &&  OrderStopLoss()!=0)
  {
    diff = MathAbs(OrderStopLoss() - sl);
    diffPoints = diff / Point;
    if (diffPoints < MINIMUM_STOP_MOVE_POINTS)
      sl = OrderStopLoss(); // try not to bother the server if we don't have to
  }
  
  if (tp != 0  &&  OrderTakeProfit()!=0)
  {  
    diff = MathAbs(OrderTakeProfit() - tp);
    diffPoints = diff / Point;  
    if (diffPoints < MINIMUM_STOP_MOVE_POINTS)
      tp = OrderTakeProfit();
  }
  
  if (sl == OrderStopLoss()  &&  tp == OrderTakeProfit())
    return;
    
  int retries=3;
  while (retries >= 0)
  {
    if (OrderReliableModify(ticket, OrderOpenPrice(), sl, tp, OrderExpiration()))
      break;
    else
    {
      int err = GetLastError();
      Print("Failed modifying " + ticket + " - " + ErrorDescription(err));
      OrderSelect(ticket, SELECT_BY_TICKET);
      Print("  sl: ", DoubleToStr(OrderStopLoss(), Digits), " tp: ", DoubleToStr(OrderTakeProfit(), Digits));
      Print("  newsl: ", DoubleToStr(sl, Digits), " newtp: ", DoubleToStr(tp, Digits));
    }
    retries--;
    Sleep(250 * (4-retries));
  }
}


void FVL_MoveStopToPrice(int ticket, double newStopPrice, bool overrideSafety = false)
{
  if (OrderSelect(ticket, SELECT_BY_TICKET))
  {
    // Never move stop away from price
    if (OrderType() == OP_BUY  ||  OrderType() == OP_BUYSTOP  ||  OrderType() == OP_BUYLIMIT)
    {
      if (overrideSafety  ||  newStopPrice > OrderStopLoss())
        FVL_ModifyTicket(ticket, newStopPrice, OrderTakeProfit());
    }
    else
    {
      if (overrideSafety  ||  newStopPrice < OrderStopLoss())
        FVL_ModifyTicket(ticket, newStopPrice, OrderTakeProfit());
    }
  }
}


int FVL_OpenTicket(double stopPrice = 0.0)
{
  OrderSelect(FVL_InitialTicket, SELECT_BY_TICKET);
  double tp = OrderTakeProfit();

  double price = FVL_GetCurrentOpenPrice();
    
  int op;
  if (FVL_IsTradeLong)
  {
    op = OP_BUY;
    if (stopPrice == 0.0)
      stopPrice = price - FVL_PipsToPrice(FVL_PipTarget);
    if (tp == 0)
      tp = price + FVL_PipsToPrice(FVL_PipTarget*2);
  }
  else
  {
    op = OP_SELL;
    if (stopPrice == 0.0)
      stopPrice = price + FVL_PipsToPrice(FVL_PipTarget);
    if (tp == 0)
      tp = price - FVL_PipsToPrice(FVL_PipTarget*2);
  }
  
  int ticket = OrderReliableSend(Symbol(), 
                                 op,
                                 FVL_GetTicketLotSize(FVL_InitialTicket), 
                                 NormalizeDouble(price, Digits),
                                 MarketInfo(Symbol(), MODE_SPREAD), 
                                 0, 0,  // Go Markets rejects new orders that have SL/TP set
                                 FVL_GetOrderComment(),
                                 FVL_Magic);
  if (ticket > 0)
    FVL_ModifyTicket(ticket, stopPrice, tp);
  else
  {
    Print("Order failed: " + ErrorDescription(GetLastError()));
    Print("  > lotsize: ", FVL_GetTicketLotSize(FVL_InitialTicket), " price: ", price, " stopPrice: ", stopPrice, " takeprofit: ", tp, " magic: ", FVL_Magic);
  }
  
  return (ticket);
}


double FVL_PipsToPrice(double pips)
{
  return (pips*10 * Point);
}


// Keep take-profit levels at 2xPipTarget, just in case we have a Power, Computer or Internet problem.
void FVL_SetAllTakeProfitLevels()
{
  return;
  if (IsTesting())
    return;
    
  double dir = FVL_dir();
  for (int i=0; i < FVL_TicketsCount; i++)
  {
    if (OrderSelect(FVL_Tickets[i], SELECT_BY_TICKET))
      if (OrderCloseTime() == 0)
      {
        // never move the TP level towards the stop
        double tp = FVL_GetCurrentClosePrice() + dir * FVL_PipsToPrice(FVL_PipTarget*2);
        if (OrderType() == OP_BUY)
        {
         if (tp < OrderTakeProfit())
           tp = 0.0;
        }
        else
        {
          if (OrderTakeProfit() > tp)
            tp = 0.0;
        }
        
        FVL_ModifyTicket(FVL_Tickets[i], OrderStopLoss(), FVL_GetCurrentClosePrice() + dir * FVL_PipsToPrice(FVL_PipTarget*2));
      }
  }
}


void FVL_ScaleIn()
{
  switch (FVL_Strategy)
  {
    case FVL_STRAT_CHICKEN:
      FVL_ScaleIn_Chicken();
      break;
      
    case FVL_STRAT_GRAVITON:
      FVL_ScaleIn_Graviton();
      break;
      
    default: // allin
      FVL_ScaleIn_AllIn();
      break;
  }
}


void FVL_ScaleIn_AllIn()
{
  double initPrice = FVL_InitialTicketEntryPrice();
  double priceTarget;
  double sl;
  bool islong;
    
  switch (FVL_TicketsCount)
  {
    case 0:
    {
      return;
      break;
    }
      
    case 1:
    {
      if (FVL_MaxPositions >= 2)
      {
        if (FVL_IsPipTargetReached(FVL_PipTarget))
        {
          // 120 #1 100 100   0
          // 120 #2 120 100 -20
        
          priceTarget = FVL_GetTicketOpenPrice(FVL_Tickets[0]) + FVL_dir()*FVL_PipsToPrice(FVL_LockInPipsAtBE);
          FVL_MoveStopToPrice(FVL_Tickets[0], priceTarget);
          FVL_Tickets[1] = FVL_OpenTicket(priceTarget);

          if (FVL_Tickets[1] > 0)
            FVL_TicketsCount++;
          
          FVL_SetAllTakeProfitLevels();
        }
        break;
      }
      // fallthrough
    }
      
    case 2:
    {
      if (FVL_MaxPositions >= 3)
      {
        if (FVL_IsPipTargetReached(FVL_PipTarget * 2))
        {
          // 140 #1 100 120  20
          // 140 #2 120 120   0
          // 140 #3 140 120 -20
        
          priceTarget = FVL_GetTicketOpenPrice(FVL_Tickets[1]) + FVL_dir()*FVL_PipsToPrice(FVL_LockInPipsAtBE);
          FVL_MoveStopToPrice(FVL_Tickets[0], priceTarget);
          FVL_MoveStopToPrice(FVL_Tickets[1], priceTarget);
          FVL_Tickets[2] = FVL_OpenTicket(priceTarget);
          if (FVL_Tickets[2] > 0)
            FVL_TicketsCount++;
          
          FVL_SetAllTakeProfitLevels();
        }
        //else
        //  FVL_TrailStops(FVL_PipTarget + FVL_LockInPipsAtBE);
        break;
      }
      // fallthrough
    }    
    
    case 3:
    {
      if (FVL_MaxPositions >= 4)
      {
        if (FVL_IsPipTargetReached(FVL_PipTarget * 3))
        {
          // 160 #1 100 140  40
          // 160 #2 120 140  20
          // 160 #3 140 140   0
          // 160 #4 160 140 -20
          priceTarget = FVL_GetTicketOpenPrice(FVL_Tickets[2]) + FVL_dir()*FVL_PipsToPrice(FVL_LockInPipsAtBE);
          FVL_MoveStopToPrice(FVL_Tickets[0], priceTarget);
          FVL_MoveStopToPrice(FVL_Tickets[1], priceTarget);
          FVL_MoveStopToPrice(FVL_Tickets[2], priceTarget);
          FVL_Tickets[3] = FVL_OpenTicket(priceTarget);
          if (FVL_Tickets[3] > 0)
            FVL_TicketsCount++;

          FVL_SetAllTakeProfitLevels();
        }
        //else
        //  FVL_TrailStops(FVL_PipTarget + FVL_LockInPipsAtBE);
      
        break;
      }
      // fallthrough
    }
    
    case 4:
    {
      if (FVL_MaxPositions >= 5)
      {
        if (FVL_IsPipTargetReached(FVL_PipTarget * 4))
        {
          // 180 #1 100 160  60
          // 180 #2 120 160  40
          // 180 #3 140 160  20
          // 180 #4 160 160   0
          // 180 #5 180 160 -20
          GlobalVariableSet(GV_AllIn, GlobalVariableGet(GV_AllIn)+1);    
    
          priceTarget = FVL_GetTicketOpenPrice(FVL_Tickets[3]) + FVL_dir()*FVL_PipsToPrice(FVL_LockInPipsAtBE);
          FVL_MoveStopToPrice(FVL_Tickets[0], priceTarget);
          FVL_MoveStopToPrice(FVL_Tickets[1], priceTarget);
          FVL_MoveStopToPrice(FVL_Tickets[2], priceTarget);
          FVL_MoveStopToPrice(FVL_Tickets[3], priceTarget);
          FVL_Tickets[4] = FVL_OpenTicket(priceTarget);
          if (FVL_Tickets[4] > 0)
            FVL_TicketsCount++;
          
          FVL_SetAllTakeProfitLevels();
        }
        //else
        //  FVL_TrailStops(FVL_PipTarget + FVL_LockInPipsAtBE);
        break;
      }
      // fallthrough
    }
    
    /*
    default:
    {      
      // Once we have 5 lots in, we trail all the stops    
      // NOTE: Moving stops to the most recent swing high/low seems to keep you in long trends longer
      // [STOP WIDENING RULE]
      //  For each 2 pips price moves in our favor beyond the STOP price of the 5th lot,
      //  we move the stops by 1 pip. The stop price of the 5th lot is the entry price
      //  of the 4th lot.
      //
      // Long case:
      // Let E5 be entry of 5th lot
      // Let CP be current close price
      // div = islong ? +1 : -1
      // E5Stop <-- E5 - PipTarget
      // NewStop <-- E5Stop + div * (div*CurrentPrice - div*E5Entry)
      // if NewStop < E5Stop don't use it
      
      int dir = FVL_dir();
      OrderSelect(FVL_Tickets[3], SELECT_BY_TICKET);
      double t4entry = OrderOpenPrice();
      double pricediff = dir*t4entry - dir*FVL_GetCurrentClosePrice();
      double stopdiff = pricediff * 0.50;
      
      double newstop = t4entry + dir*stopdiff;
      for (int i=0;  i < FVL_TicketsCount;  i++)
        FVL_MoveStopToPrice(FVL_Tickets[i], newstop);
     
      FVL_SetAllTakeProfitLevels();
      break;
    }
    */
    
    default:
    {
      double pipsPerLot = FVL_GetTotalProfitPips() / FVL_TicketsCount;
      
      // -- Calculate breakeven price --
      double breakEvenPrice = FVL_BreakevenPrice();
      int dir = FVL_dir();
      
      if (pipsPerLot > FVL_StopToHalf_PipsFromEntry)
      {
        double newstop = breakEvenPrice + FVL_dir()*(pipsPerLot/2.0)*Point*10;
        for (int i=0; i<FVL_TicketsCount; i++)
          FVL_MoveStopToPrice(FVL_Tickets[i], newstop);
      }

      break;
    }
  }
}


double FVL_BreakevenPrice()
{
  if (FVL_TicketsCount > 0)
  {
    double be = 0.0;
    for (int i=0; i<FVL_TicketsCount; i++)
    {
      OrderSelect(FVL_Tickets[i], SELECT_BY_TICKET);
      be += OrderOpenPrice();
    }
    be = be / FVL_TicketsCount;

    return (be);
  }
  else
    return (0.0);
}


void FVL_ScaleIn_Chicken()
{
  double initPrice = FVL_InitialTicketEntryPrice();
  double priceTarget;
  double sl;
  bool islong;
  int tradedir = FVL_dir();
  
    
  switch (FVL_TicketsCount)
  {
    case 0:
    {
      return;
      break;
    }
    
    case 1:
    {
      //   Putting on lot 2
      //   140 #1 100 120 +20
      //   140 #2 140 120 -20
      //                    0
      if (FVL_IsPipTargetReached(FVL_GetExpectedEntryPipsByPos(FVL_TicketsCount)))
      {
        priceTarget = initPrice + tradedir*FVL_PipsToPrice(FVL_PipTarget + FVL_LockInPipsAtBE);
        FVL_SetStops(priceTarget);
        FVL_Tickets[1] = FVL_OpenTicket(priceTarget);
        if (FVL_Tickets[1] > 0)
          FVL_TicketsCount++;
          
        FVL_SetAllTakeProfitLevels();
      }
      else
      {
        // Trail the stop on the first lot as well - this is the "Chicken" strategy after all.
        if (FVL_GetProfitAtStop$() < 0.0)
          FVL_TrailStops(FVL_PipTarget);
      }
      break;
    }
    
    case 2:
    {
      //   Putting on lot 3 at +60
      //   160 #1 100 140 +40
      //   160 #2 140 140   0
      //   160 #3 160 140 -20
      //                  +20
      if (FVL_IsPipTargetReached(FVL_GetExpectedEntryPipsByPos(FVL_TicketsCount)))
      {
        priceTarget = FVL_GetTicketOpenPrice(FVL_Tickets[1]) + tradedir*FVL_PipsToPrice(FVL_LockInPipsAtBE);
        FVL_SetStops(priceTarget);
        FVL_Tickets[2] = FVL_OpenTicket(priceTarget);
        if (FVL_Tickets[2] > 0)
          FVL_TicketsCount++;

        //FVL_Tickets[3] = FVL_OpenTicket(priceTarget);
        //if (FVL_Tickets[3] > 0)
        //  FVL_TicketsCount++;

        //FVL_Tickets[4] = FVL_OpenTicket(priceTarget);
        //if (FVL_Tickets[4] > 0)
        //  FVL_TicketsCount++;
          
        FVL_SetAllTakeProfitLevels();
      }
      else
      {
        if (FVL_GetProfitAtStop$() < 0.0)
          FVL_TrailStops(FVL_PipTarget);
      }
      break;
    }
    
    case 3:
    {
      //   Putting on lots 4&5
      //   180 #1 100 160 +60
      //   180 #2 140 160 +20
      //   180 #3 160 160  +0
      //   180 #4 180 160 -20 <- added
      //   180 #5 180 160 -20 <- added
      //                  +40
      if (FVL_IsPipTargetReached(FVL_GetExpectedEntryPipsByPos(FVL_TicketsCount)))
      {
        GlobalVariableSet(GV_AllIn, GlobalVariableGet(GV_AllIn)+1);    
        priceTarget = FVL_GetTicketOpenPrice(FVL_Tickets[2]) + tradedir*FVL_PipsToPrice(FVL_LockInPipsAtBE);
        FVL_SetStops(priceTarget);
        FVL_Tickets[3] = FVL_OpenTicket(priceTarget);
        FVL_Tickets[4] = FVL_OpenTicket(priceTarget);
        if (FVL_Tickets[3] > 0)
          FVL_TicketsCount++;
        if (FVL_Tickets[4] > 0)
          FVL_TicketsCount++;
          
        FVL_SetAllTakeProfitLevels();
      }
      else
        FVL_TrailStops(FVL_PipTarget);
      break;
    }
    
    default:
    {
      //  For each 2 pips price moves in our favor beyond the STOP price of the 5th lot,
      //  we move the stops by 1 pip. The stop price of the 5th lot is the entry price
      //  of the *3rd* lot.
      FVL_TrailStops(FVL_PipTarget*2);
      
/*
      OrderSelect(FVL_Tickets[3], SELECT_BY_TICKET);
      double t4entry = OrderOpenPrice();
      double pricediff = tradedir*t4entry - tradedir*FVL_GetCurrentClosePrice();
      double stopdiff = pricediff * 0.50;
      
      double newstop = t4entry + tradedir*stopdiff;
      for (int i=0;  i < FVL_TicketsCount;  i++)
        FVL_MoveStopToPrice(FVL_Tickets[i], newstop);
*/
     
      FVL_SetAllTakeProfitLevels();
      break;
    }
  }
}


void FVL_ScaleIn_Graviton()
{
  double initPrice = FVL_InitialTicketEntryPrice();
  double priceTarget;
  double sl;
  bool islong;
  int tradedir = FVL_dir();
  
    
  switch (FVL_TicketsCount)
  {
    case 0:
    {
      return;
      break;
    }
    
    case 1:
    {
      //   Putting on lot 2
      //   120 #0 100 100  +0
      //   120 #1 120 100 -20
      //                  -20
      if (FVL_IsPipTargetReached(FVL_GetExpectedEntryPipsByPos(FVL_TicketsCount)))
      {
        // 120 #1 100 100   0
        // 120 #2 120 100 -20       
        priceTarget = FVL_GetTicketOpenPrice(FVL_Tickets[0]) + FVL_dir()*FVL_PipsToPrice(FVL_LockInPipsAtBE);
        FVL_MoveStopToPrice(FVL_Tickets[0], priceTarget);
        FVL_Tickets[1] = FVL_OpenTicket(priceTarget);
        if (FVL_Tickets[1] > 0)
          FVL_TicketsCount++;
          
        FVL_SetAllTakeProfitLevels();
      }
      break;
    }
    
    case 2:
    {
      //   Moving stops at +40
      //   140 #0 100 120 +20
      //   140 #1 120 120   0
      //                  +20
      //   Putting on lot 3 at +60
      //   160 #0 100 140 +40
      //   160 #1 120 140 +20
      //   160 #2 160 140 -20
      //                  +40
      if (FVL_IsPipTargetReached(FVL_GetExpectedEntryPipsByPos(FVL_TicketsCount)))  //+60
      {
        priceTarget = FVL_GetTicketOpenPrice(FVL_Tickets[1]) + tradedir*FVL_PipsToPrice(FVL_PipTarget + FVL_LockInPipsAtBE);
        FVL_SetStops(priceTarget);
        FVL_Tickets[2] = FVL_OpenTicket(priceTarget);
        if (FVL_Tickets[2] > 0)
          FVL_TicketsCount++;
          
        FVL_SetAllTakeProfitLevels();
      }
      else
        FVL_TrailStops(FVL_PipTarget + FVL_LockInPipsAtBE);
      break;
    }
    
    case 3:
    {
      if (FVL_IsPipTargetReached(FVL_GetExpectedEntryPipsByPos(FVL_TicketsCount))) //+80
      {
        // 180 #0 100 160  60
        // 180 #1 120 160  40
        // 180 #2 160 160   0
        // 180 #3 180 160 -20
        //                +80
        priceTarget = FVL_GetTicketOpenPrice(FVL_Tickets[2]) + FVL_dir()*FVL_PipsToPrice(FVL_LockInPipsAtBE);
        FVL_SetStops(priceTarget);
        FVL_Tickets[3] = FVL_OpenTicket(priceTarget);
        if (FVL_Tickets[3] > 0)
          FVL_TicketsCount++;

        FVL_SetAllTakeProfitLevels();
      }
      else
        FVL_TrailStops(FVL_PipTarget + FVL_LockInPipsAtBE);
      break;
    }

    case 4:
    {
      if (FVL_IsPipTargetReached(FVL_GetExpectedEntryPipsByPos(FVL_TicketsCount))) //+100
      {
        // 200 #0 100 180  80
        // 200 #1 120 180  60
        // 200 #2 160 180  20
        // 200 #3 180 180   0
        // 200 #4 200 180 -20
        //               +140
        GlobalVariableSet(GV_AllIn, GlobalVariableGet(GV_AllIn)+1);    
    
        priceTarget = FVL_GetTicketOpenPrice(FVL_Tickets[3]) + FVL_dir()*FVL_PipsToPrice(FVL_LockInPipsAtBE);
        FVL_SetStops(priceTarget);
        FVL_Tickets[4] = FVL_OpenTicket(priceTarget);
        if (FVL_Tickets[4] > 0)
          FVL_TicketsCount++;
          
        FVL_SetAllTakeProfitLevels();
      }
      else
        FVL_TrailStops(FVL_PipTarget + FVL_LockInPipsAtBE);
      break;
    }
    
    default:
    {
      OrderSelect(FVL_Tickets[3], SELECT_BY_TICKET);
      double t4entry = OrderOpenPrice();
      double pricediff = tradedir*t4entry - tradedir*FVL_GetCurrentClosePrice();
      double stopdiff = pricediff * 0.50;
      
      double newstop = t4entry + tradedir*stopdiff;
      for (int i=0;  i < FVL_TicketsCount;  i++)
        FVL_MoveStopToPrice(FVL_Tickets[i], newstop);
     
      FVL_SetAllTakeProfitLevels();
      break;
    }
  }
}


void FVL_SetStops(double stopprice)
{
  for (int i=0; i < FVL_TicketsCount; i++)
    FVL_MoveStopToPrice(FVL_Tickets[i], stopprice);
}


void FVL_SortTicketsByTicketNumber()
{
  // We assume that ticket numbers only increase.
  // Therefore, a higher number is newer.
  // We want oldest tickets first.
  
  for (int i=0;  i < FVL_TicketsCount-1;  i++)
  {
    int lowestIndex = i;
    for (int j=i+1;  j < FVL_TicketsCount;  j++)
    {
      if (FVL_Tickets[j] < FVL_Tickets[lowestIndex])
        lowestIndex = j;
    }
    
    if (lowestIndex != i)
    {
      int swapTicket = FVL_Tickets[lowestIndex];
      FVL_Tickets[lowestIndex] = FVL_Tickets[i];
      FVL_Tickets[i] = swapTicket;
    }
  }
}


void FVL_TrailStops(double pips)
{
  FVL_SetStops(FVL_GetCurrentClosePrice() -  FVL_dir()*FVL_PipsToPrice(pips));
}


void FVL_ValidateInitialStopLoss()
{
  double sl = 0.0;
  double tp = 0.0;
  double dir = FVL_dir();
    
  if (OrderSelect(FVL_InitialTicket, SELECT_BY_TICKET))
  {
    if (OrderStopLoss() == 0)   // stop not set!
    {
      if (FVL_UseDoubleInitialStop)
        sl = OrderOpenPrice() - dir*(FVL_PipsToPrice(FVL_PipTarget*2) + MarketInfo(Symbol(), MODE_SPREAD)*Point);
      else
        sl = OrderOpenPrice() - dir*(FVL_PipsToPrice(FVL_PipTarget) + MarketInfo(Symbol(), MODE_SPREAD)*Point);
        
      if (OrderTakeProfit() == 0)
        tp = OrderOpenPrice() + dir*FVL_PipsToPrice(FVL_PipTarget*2);
      else
        tp = OrderTakeProfit();
        
      if (IsTesting())
        tp = 0;
    
      FVL_ModifyTicket(OrderTicket(), sl, tp);
    }
  }  
}

