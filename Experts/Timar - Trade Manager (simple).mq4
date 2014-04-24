//+------------------------------------------------------------------+
//|                               Timar - Trade Manager (simple).mq4 |
//|                              Copyright © 2011, Timar Investments |
//|                               http://www.timarinvestments.com.au |
/*
  Version 6
    - Moved stats display to bottom left
    - Added opaque background to stats display
    - Added MissedByThatMuch aka the "80%" rule

  Version 5
    - Added AutoTicket

  Version 4
    - Added Maximum Relative Adverse Excursion (MRAE).
      This is the maximum move away from MFE.
      e.g. Price moves 
              -10 (MAE=-10)
              +30 (MAE=-10, MFE=+30)
              +10 (MAE=-10, MRAE=-20, MFE+30)
  Version 3
    - Added Maximum Favourable Excursion (MFE) and Maximum Adverse
      Excursion (MAE).  
  Version 2
    - Added ShowCurrency. When false, profit/loss figures are shown in pips.
    - Fixed double (( on loss display.
*/
//+------------------------------------------------------------------+

#property copyright "Copyright © 2011, Timar Investments"
#property link      "http://www.timarinvestments.com.au"

#include <stderror.mqh>
#include <stdlib.mqh>
#include <ptorders.mqh>

//---- input parameters
extern int _VERSION_6=6;
extern bool Active=true;

//extern bool AutoTicket = true;

//extern int Ticket1 = 0; 
//--
extern bool   IncludeSpread = true;

extern double Stop_Pips = 16;

extern double StopToBE_Pips = 10;
extern double LockInAtBE_Pips = 1;

extern double StopToSmall_Pips = 17;
extern double Small_Pips = 5;

extern double StopToHalf_Pips = 32;

extern double MissedByThatMuch_Active_Factor = 0.94;
extern double MissedByThatMuch_SL_Factor = 0.80;

extern string _1 = "__ Display _____________";
extern string CurrencySymbol = "$";
extern bool ShowCurrency = false;
extern color Background = C'24,24,24';
//+------------------------------------------------------------------+
double MFE_pips;
double MFE_$;

double MAE_pips;
double MAE_$;

double MRAE_pips;
double MRAE_$;

int LastTicket1 = 0;

//+------------------------------------------------------------------+
string pfx="tmtmsimple";

#define fontName     "Calibri"
#define boldFontName "Arial Black"
#define fontSize     8

#define NotActiveColor        Red



string GetIndicatorShortName()
{
  return("Timar - Trade Manager (simple) " + Symbol());
}

string GetOrderComment(int magic)
{
  return("TradeManager(simple)");
}



//+------------------------------------------------------------------+
//| expert initialization function                                   |
//+------------------------------------------------------------------+
int init()
{
  DeleteAllObjectsWithPrefix(pfx);
  
  _UpdateComment();
  
  return(0);
}


//+------------------------------------------------------------------+
//| expert deinitialization function                                 |
//+------------------------------------------------------------------+
int deinit()
{
  Comment("");
  DeleteAllObjectsWithPrefix(pfx);
  return(0);
}


//+------------------------------------------------------------------+
//| expert start function                                            |
//+------------------------------------------------------------------+
int start()
{
  _FindRelatedTickets();

  //if (LastTicket1 != Ticket1  &&  Ticket1 != 0)
  //{
  //  _ResetStats();
  //  LastTicket1 = Ticket1;
  //}
  
  _UpdateComment();
  _UpdateObjects();
  
  if (!Active)
    return(0);

  //OrderSelect(Ticket1, SELECT_BY_TICKET);
  //Comment(Ticket1 + " " + OrderType() + " " + OP_SELL);

  if (_IsTradeInMarket())
  {
    _CheckSL();
    _CheckBE();

    _UpdateComment();
    _UpdateObjects();
  }
  
  return(0);
}


void _ResetStats()
{
  if (OrderSelect(LastTicket1, SELECT_BY_TICKET))
  {
    MAE_pips = _GetProfitPips();
    MFE_pips = MAE_pips;
    MRAE_pips = 0;
    MAE_$ = _GetProfit$();
    MFE_$ = MAE_$;
    MRAE_$ = 0;
  }
  else
  {
    MAE_pips = 0;
    MFE_pips = 0;
    MRAE_pips = 0;
    MAE_$ = 0;
    MFE_$ = 0;
    MRAE_$ = 0;
  }
}


void _FindRelatedTickets()
{
  int openTicket = 0;
  for (int i=0; i < OrdersTotal(); i++)
  {
    OrderSelect(i, SELECT_BY_POS);
    if (OrderSymbol() == Symbol() && OrderComment() == "")
    {
      if ((OrderType() == OP_BUY || OrderType() == OP_SELL))
      {
        openTicket = OrderTicket();
        break;
      }
      else
      {
        if (NormalizeDouble(OrderStopLoss(), Digits) == 0.0)
        {
          _CheckSL(OrderTicket());
        }
      }
    }
  }
  
  if (openTicket != 0  &&  LastTicket1 == 0)
  {
    // New ticket opened
    LastTicket1 = openTicket;
    _ResetStats();
  }
  else if (LastTicket1 != 0  &&  openTicket != 0  &&  LastTicket1 != openTicket)
  {
    // New ticket opened
    LastTicket1 = openTicket;
    _ResetStats();
  }
  
  if (LastTicket1 != 0)
  {
    if (!OrderSelect(LastTicket1, SELECT_BY_TICKET, MODE_TRADES) && !OrderSelect(LastTicket1, SELECT_BY_TICKET, MODE_HISTORY))
    {
      LastTicket1 = 0;
    }
  }
}


void _UpdateComment()
{
  //Comment("");
}


string GetPipsDisplay(double pips)
{
  int digits;
  if (pips < -100  ||  pips > 100)
    digits = 0;
  else
    digits = 1;
  
  if (pips < 0)
    return ("(" + DoubleToStr(MathAbs(pips), digits) + "p)");
  else
    return (DoubleToStr(pips, digits) + "p");
}

int col2offs = 40;

void _UpdateObjects()
{
  if (IsTesting()) 
    return;

  color clr;
  double dProfit;
  if (_IsTradeInMarket())
  {
    bool highlightMFE = false;
    bool highlightMAE = false;
    
    if (_GetProfit$() > MFE_$)
    {
      MFE_$ = _GetProfit$();
      highlightMFE = true;
    }    
    if (_GetProfitPips() > MFE_pips)
      MFE_pips = _GetProfitPips();
      
    if (_GetProfit$() < MAE_$)
    {
      MAE_$ = _GetProfit$();
      highlightMAE = true;
    }
    if (_GetProfitPips() < MAE_pips)
      MAE_pips = _GetProfitPips();
      
    if (_GetProfit$() - MFE_$ < MRAE_$)
      MRAE_$ = _GetProfit$() - MFE_$;
    if (_GetProfitPips() - MFE_pips < MRAE_pips)
      MRAE_pips = _GetProfitPips() - MFE_pips;
  
    if (ShowCurrency)
    {
      dProfit = _GetProfit$();
      if (dProfit >= 0)
      {
        if (highlightMFE)
          clr = Chartreuse;
        else
          clr = Green;
        SetLabel("lProfitTitle", 10,10, "Profit", clr);
        SetLabel("lProfit", 10+col2offs,10, GetDollarDisplay(dProfit), clr);
      }
      else
      {
        if (highlightMAE)
          clr = Yellow;
        else
          clr = Red;
        SetLabel("lProfitTitle", 10,10, "Loss", clr);
        SetLabel("lProfit", 10+col2offs,10, GetDollarDisplay(dProfit), clr);
      }
    }
    else
    {
      dProfit = _GetProfitPips();
      if (dProfit >= 0)
      {
        if (highlightMFE)
          clr = Chartreuse;
        else
          clr = Green;
        SetLabel("lProfitTitle", 10,10, "Profit", clr);
        SetLabel("lProfit", 10+col2offs,10, GetPipsDisplay(dProfit), clr);
      }
      else
      {
        if (highlightMAE)
          clr = Orange;
        else
          clr = Red;
        SetLabel("lProfitTitle", 10,10, "Loss", clr);
        SetLabel("lProfit", 10+col2offs,10, GetPipsDisplay(dProfit), clr);
      }
    }
    _UpdateMAEMFE();    
    ObjectSet(pfx+"lProfitTitle", OBJPROP_CORNER, 2);
    ObjectSet(pfx+"lProfit", OBJPROP_CORNER, 2);
    
    //---
    double dProfitAtStop;
    if (ShowCurrency)
    {
      dProfitAtStop = _GetProfitAtStop$();
      if (dProfitAtStop >= 0)
      {
        clr = Green;
        SetLabel("lProfitAtStopTitle", 10, 10+ (fontSize+1)*1, "@Stop", clr);
      }
      else
      {
        clr = Red;
        SetLabel("lProfitAtStopTitle", 10, 10+ (fontSize+1)*1, "Risk", clr);
      }
      SetLabel("lProfitAtStop", 10+col2offs, 10+ (fontSize+2)*1, GetDollarDisplay(dProfitAtStop), clr);
    }
    else
    {
      dProfitAtStop = _GetPipsAtStop();
      if (dProfitAtStop >= 0)
      {
        clr = Green;
        SetLabel("lProfitAtStopTitle", 10, 10+ (fontSize+2)*1, "@Stop", clr);
      }
      else
      {
        clr = Red;
        SetLabel("lProfitAtStopTitle", 10, 10+ (fontSize+2)*1, "Risk", clr);
      }
      SetLabel("lProfitAtStop", 10+col2offs, 10+ (fontSize+2)*1, GetPipsDisplay(dProfitAtStop), clr);
    }
    ObjectSet(pfx+"lProfitAtStopTitle", OBJPROP_CORNER, 2);
    ObjectSet(pfx+"lProfitAtStop", OBJPROP_CORNER, 2);
    
    _UpdateBackground();
  }
  else if (_IsTradeClosed())
  {
    dProfit = _GetProfit$();
    if (dProfit > 0)
      clr = Green;
    else
      clr = Red;
    if (dProfit > 0)
      SetLabel("lProfit", 10, 10, "Final Profit " + CurrencySymbol + DoubleToStr(dProfit,2), clr);
    else
      SetLabel("lProfit", 10, 10, "Final Loss (" + CurrencySymbol + DoubleToStr(dProfit,2) + ")", clr);
    ObjectSet(pfx+"lProfit", OBJPROP_CORNER, 2);
    DeleteObject("lProfitTitle");

    if (MFE_$ != 0.0)
    {
      SetLabel("lProfitAtStop", 10, 10+ (fontSize+2)*1, "Effeciency " + DoubleToStr((dProfit/MFE_$)*100,0) + "%", clr);
      ObjectSet(pfx+"lProfitAtStop", OBJPROP_CORNER, 2);
    }

    _UpdateBackground();
    _UpdateMAEMFE();
  }
  else
  {
    DeleteObject("lProfitTitle");
    DeleteObject("lProfit");
    DeleteObject("lProfitAtStopTitle");
    DeleteObject("lProfitAtStop");
    DeleteObject("lMAETitle");
    DeleteObject("lMAE");
    DeleteObject("lMRAETitle");
    DeleteObject("lMRAE");
    DeleteObject("lMFETitle");
    DeleteObject("lMFE");
    DeleteAllObjectsWithPrefix(pfx+"bkga");
  }
}


void _UpdateBackground()
{
  for (int i=0; i<5; i++)
    _DrawBackground(10 + (fontSize+2)*i, Background);
}


void _DrawBackground(int y, color clr)
{
  y = y - 2;
  string bkg = "ggggggggg";
  
  SetLabel("bkga"+y, 5, y, bkg, clr, 0, "Webdings");
  ObjectSet(pfx+"bkga"+y, OBJPROP_CORNER, 2);
}


void _UpdateMAEMFE()
{
  color clr;
  if (ShowCurrency)
  {
    if (MFE_$ >= 0)
      clr = Green;
    else
      clr = Red;
    SetLabel("lMFETitle", 10,(fontSize+2)*3, "MFE", clr);
    SetLabel("lMFE", 10 + col2offs,(fontSize+2)*3, GetDollarDisplay(MFE_$), clr);

    if (MAE_$ >= 0)
      clr = Green;
    else
      clr = Red;
    SetLabel("lMAETitle", 10,(fontSize+2)*5, "MAE", clr);
    SetLabel("lMAE", 10 + col2offs,(fontSize+2)*5, GetDollarDisplay(MAE_$), clr);
    
    if (MRAE_$ >= 0)
      clr = Green;
    else
      clr = Red;
    SetLabel("lMRAETitle", 10,(fontSize+2)*4, "MRAE", clr);
    SetLabel("lMRAE", 10 + col2offs,(fontSize+2)*4, GetDollarDisplay(MRAE_$), clr);
  }
  else
  {
    if (MFE_pips >= 0)
      clr = Green;
    else
      clr = Red;
    SetLabel("lMFETitle", 10,(fontSize+2)*3, "MFE", clr);
    SetLabel("lMFE", 10+col2offs,(fontSize+2)*3, GetPipsDisplay(MFE_pips), clr);
    
    if (MAE_pips >= 0)
      clr = Green;
    else
      clr = Red;
    SetLabel("lMAETitle", 10,(fontSize+2)*5, "MAE", clr);
    SetLabel("lMAE", 10+col2offs,(fontSize+2)*5, GetPipsDisplay(MAE_pips), clr);

    if (MRAE_pips >= 0)
      clr = Green;
    else
      clr = Red;
    SetLabel("lMRAETitle", 10,(fontSize+2)*4, "MRAE", clr);
    SetLabel("lMRAE", 10+col2offs,(fontSize+2)*4, GetPipsDisplay(MRAE_pips), clr);
  }
  ObjectSet(pfx+"lMFETitle", OBJPROP_CORNER, 2);
  ObjectSet(pfx+"lMAETitle", OBJPROP_CORNER, 2);
  ObjectSet(pfx+"lMRAETitle", OBJPROP_CORNER, 2);
  ObjectSet(pfx+"lMFE", OBJPROP_CORNER, 2);
  ObjectSet(pfx+"lMAE", OBJPROP_CORNER, 2);
  ObjectSet(pfx+"lMRAE", OBJPROP_CORNER, 2);
}


double _GetProfit$()
{
  double total=0.0;
  if (OrderSelect(LastTicket1, SELECT_BY_TICKET))
    total += OrderProfit() + OrderSwap();    
  return (total);
}


double _GetProfitPips()
{
  double total=0.0;
  if (OrderSelect(LastTicket1, SELECT_BY_TICKET))
  {
    if (OrderType() == OP_BUY)
      total += (Bid - OrderOpenPrice()) / Point / 10;
    else
      total += (OrderOpenPrice() - Ask) / Point / 10;
  }
  return (total);
}


double _GetProfitAtStop$()
{
  double profitAtStop$ = 0.0;
  bool isLong = _IsTradeLong();
  double closePrice;
  if (isLong)
    closePrice = Bid;
  else
    closePrice = Ask;

  int tickets[1];
  tickets[0] = LastTicket1;
  
  for (int i = 0;  i < ArraySize(tickets);  i++)
  {
    if (OrderSelect(tickets[i], SELECT_BY_TICKET))
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

double _GetPipsAtStop()
{
  double pipsAtStop = 0.0;
  bool isLong = _IsTradeLong();
  
  int tickets[1];
  tickets[0] = LastTicket1;
    
  for (int i = 0; i < ArraySize(tickets); i++)
  {
    if (OrderSelect(tickets[i], SELECT_BY_TICKET))
      if (OrderStopLoss() > 0)
      {
        if (isLong)
          pipsAtStop += (OrderStopLoss() - OrderOpenPrice())/Point/BrokerFactor();
        else
          pipsAtStop += (OrderOpenPrice() - OrderStopLoss())/Point/BrokerFactor();
      }
  }
  return (pipsAtStop);
}


double _GetSpread$()
{
  if (IncludeSpread)
    return (PointsToPrice(MarketInfo(Symbol(), MODE_SPREAD)));
  else
    return (0.0);
}


void _CheckSL(int ticket = 0)
{
  if (ticket == 0)
    ticket = LastTicket1;
    
  if (OrderSelect(ticket, SELECT_BY_TICKET))
  {
    if (OrderComment() == ""  &&  NormalizeDouble(OrderStopLoss(), Digits) == 0)
    {
      double sl;
      
      if (_IsTradeLong(ticket))
        sl = OrderOpenPrice() - PipsToPrice(Stop_Pips) - _GetSpread$();
      else
        sl = OrderOpenPrice() + PipsToPrice(Stop_Pips) + _GetSpread$();
        
      _MoveStop(ticket, sl);      
    }
  }
  else if (OrderOpenTime() != 0  &&  OrderCloseTime() == 0)
    _DoMissedByThatMuch(ticket);
}


void _CheckBE()
{
  int ticket = LastTicket1;
  
  if (_IsTradeLong())
  {
    if (StopToHalf_Pips != 0  &&  Bid > OrderOpenPrice() + PipsToPrice(StopToHalf_Pips))
      _MoveStop(ticket, OrderOpenPrice() + (Bid - OrderOpenPrice())/2);
    else
    if (StopToSmall_Pips != 0  &&  Bid > OrderOpenPrice() + PipsToPrice(StopToSmall_Pips))
      _MoveStop(ticket, OrderOpenPrice() + PipsToPrice(Small_Pips));
    else
    if (Bid > OrderOpenPrice() + PipsToPrice(StopToBE_Pips))
      _MoveStop(ticket, OrderOpenPrice() + PipsToPrice(LockInAtBE_Pips));
  }
  else
  {
    if (StopToHalf_Pips != 0  &&  Ask < OrderOpenPrice() - PipsToPrice(StopToHalf_Pips))
      _MoveStop(ticket, OrderOpenPrice() - (OrderOpenPrice() - Ask)/2);
    else
    if (StopToSmall_Pips != 0  &&  Ask < OrderOpenPrice() - PipsToPrice(StopToSmall_Pips))
      _MoveStop(ticket, OrderOpenPrice() - PipsToPrice(Small_Pips));
    else
    if (Ask < OrderOpenPrice() - PipsToPrice(StopToBE_Pips))
      _MoveStop(ticket, OrderOpenPrice() - PipsToPrice(LockInAtBE_Pips));
  }
}


void _DoMissedByThatMuch(int ticket)
{
  double mbtmFactor = -1.0;
  double mbtmPrice = 0.0;
  if (OrderSelect(ticket, SELECT_BY_TICKET))
  {
    if (OrderTakeProfit() > 0.0)
    {
      if (OrderType() == OP_BUY)
      {
        mbtmFactor = (Bid - OrderOpenPrice()) / (OrderTakeProfit() - OrderOpenPrice());
        mbtmPrice = OrderOpenPrice() + (OrderTakeProfit() - OrderOpenPrice()) * MissedByThatMuch_SL_Factor;
      }
      else if (OrderType() == OP_SELL)
      {
        mbtmFactor = (OrderOpenPrice() - Ask) / (OrderOpenPrice() - OrderTakeProfit());     
        mbtmPrice = OrderOpenPrice() - (OrderOpenPrice() - OrderTakeProfit()) * MissedByThatMuch_SL_Factor;
      }
    }
    
    if (MissedByThatMuch_Active_Factor > 0  &&  mbtmFactor >= MissedByThatMuch_Active_Factor)
      _MoveStop(ticket, mbtmPrice);
  }
}


bool _IsTradeInMarket()
{
  if (OrderSelect(LastTicket1, SELECT_BY_TICKET))
    return ((OrderType() == OP_BUY  ||  OrderType() == OP_SELL) && (OrderCloseTime() == 0));
  else
    return (false);
}


bool _IsTradeClosed()
{
  if (OrderSelect(LastTicket1, SELECT_BY_TICKET, MODE_HISTORY))
    return (OrderCloseTime() != 0);
  else
    return (false);
}


bool _IsTradeLong(int ticket = 0)
{
  if (ticket == 0)
    ticket = LastTicket1;
    
  if (OrderSelect(ticket, SELECT_BY_TICKET))
  {
    return (OrderType() == OP_BUY   ||  OrderType() == OP_BUYLIMIT  ||  OrderType() == OP_BUYSTOP);
  }
  else
    return (true); // gotta return something
}


#define MINIMUM_STOP_MOVE_POINTS  10
bool _MoveStop(int ticket,  double price)
{
  int retries=3;
  while (retries != 0)
  {
    if (OrderSelect(ticket, SELECT_BY_TICKET))
    {
      // -- Don't move stop against an open trade 
      if (OrderType() == OP_BUY)
      {
        if (OrderStopLoss() != 0  &&  price < OrderStopLoss())
          return (true);
      }
      else if (OrderType() == OP_SELL)
      {
        if (OrderStopLoss() != 0  &&  price > OrderStopLoss())
          return (true);
      }   
    
      double diff = MathAbs(OrderStopLoss() - price);
      double diffPoints = diff / Point;
      
      if (diffPoints < MINIMUM_STOP_MOVE_POINTS)
        return (true);
         
      bool ok = OrderReliableModify(ticket, OrderOpenPrice(), price, OrderTakeProfit(), 0);
      if (!ok)
        Print("OrderModify failed: " + GetLastError());
      else
        break;
      retries--;
    }
    else
    {
      Print("OrderModify select failed: ticket " + ticket + " not found (" + GetLastError() + ")");
      return (false);
    }
  }
  
  if (retries == 0)
    return (false);
  else
    return (true);
}



//+------------------------------------------------------------------+
void DeleteObject(string name)
{
  ObjectDelete(pfx+name);
}


void DeleteAllObjectsWithPrefix(string prefix)
{
  for(int i = ObjectsTotal() - 1; i >= 0; i--)
  {
    string label = ObjectName(i);
    if(StringSubstr(label, 0, StringLen(prefix)) == prefix)
      ObjectDelete(label);   
  }
}


double GetLotsForRisk(double balance, double riskPercent, double entryPrice, double stopPrice)
{
  double priceDifference = MathAbs(entryPrice - stopPrice);
  double risk$ = balance * (riskPercent / 100.0);
    
  double riskPips = priceDifference/Point/BrokerFactor();
  
  double lotSize = (risk$ / riskPips) / ((MarketInfo(Symbol(), MODE_TICKVALUE)*10.0));

  return (lotSize);
}


double PipsToPrice(double pips)
{
  return (pips*10 * Point);
}


double PointsToPrice(double points)
{
  return (points * Point);
}


void SetLabel(string name, int x, int y, string text, color clr=CLR_NONE, int size=0, string face=fontName)
{
  int windowNumber = 0;
  
  if (ObjectFind(pfx+name) < 0)
    ObjectCreate(pfx+name, OBJ_LABEL, windowNumber, 0,0);
 
  ObjectSet(pfx+name, OBJPROP_XDISTANCE, x);
  ObjectSet(pfx+name, OBJPROP_YDISTANCE, y);
  ObjectSetText(pfx+name, text, size, face, clr);
}


string GetDollarDisplay(double amount, bool exact=false)
{
  int digits = 2;
  if (!exact)
  {
    if (amount < -100  ||  amount > 100)
      digits = 0;
    else
      digits = 2;
  }

  if (amount < 0)
    return ("(" + CurrencySymbol + DoubleToStr(MathAbs(amount), digits) + ")");
  else
    return (CurrencySymbol + DoubleToStr(amount, digits));
}


double BrokerFactor()
{
  return (10.0);
}

