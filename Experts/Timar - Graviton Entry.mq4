//+------------------------------------------------------------------+
//|                                       Timar - Graviton Entry.mq4 |
//|                              Copyright © 2010, Timar Investments |
//|                               http://www.timarinvestments.com.au |
//
// This EA follows Graviton's entry rules in an attempt to get a cheap
// entry into a position.
//
// OPERATION
// =========
// Open an order in the desired trade direction, price and position size.
// You can open at market, or with a stop/limit order.
// Enter the ticket number into the "InitialTicket" parameter.
//
// 
// EntryTrigger
//  BUY case.  _ActualEntryPrice 
//   - If price is below entry, set a "lastTickBelowEntry" flag.
//   - On next tick, if price is now entry candidate set "EntryTrigger" to true.
//   
//
//+------------------------------------------------------------------+

#property copyright "Copyright © 2010, Timar Investments"
#property link      "http://www.timarinvestments.com.au"

#include <stdlib.mqh>
#include <stderror.mqh>
#include <ptorders.mqh>


// extern int InitialTicket

extern bool ImmediateEntry = false;

extern bool InteractivePriceBar = false;

extern double EntryPrice = 0.0;
double _ActualEntryPrice = 0;
extern string EntryDirection = "";  // long or short

extern datetime ExpiryTime = 0;
extern double   Lots = 0.4;

int Magic = 0;

extern string _2="__ Limits _____";
//extern int MaxLosses = 2;
//extern int MaxRetries = 5;
//extern int MaxRetryMinutes = 60;  // Try for this many minutes after the first entry

extern string _3="__ Trade Rules ______";

extern bool   LowerTimeframeStochsMustAgree = true;
extern double EntrySlack_Pips = 10.0;   // If price moves beyond entry up to this far, then entries are still ok

extern bool   IncludeSpread = true;
extern double MaximumAdverseExcursion_Pips = 12.0;   // Position will be closed at this point

extern double LockInAtBE_Pips = 1;
extern double Stop_Pips = 25;
extern double StopToBE_Pips = 15;
extern double StopToSmall_Pips = 30;
extern double Small_Pips = 10;
extern double StopToHalf_Pips = 40;
extern double TakeProfit_Pips = 80;

bool EntryTriggerSet = false;
int LastTickRelativeToEntry = 0;


//int Tickets[100];
//int TicketCount;

int OpenTicket;

#define STATUS_TIME_EXPIRED      -1
#define STATUS_INVALID_INPUT      0
#define STATUS_WAITING_FOR_PRICE  1
#define STATUS_READY_TO_ENTER     2
#define STATUS_IN_MARKET          3

int TradeDirection;  // OP_BUY or OP_SELL

#define pfx "ge"

#define fontName     "Calibri"
#define boldFontName "Arial Black"
#define fontSize     8

#define Object_EntryName "EntryPrice"

//+------------------------------------------------------------------+
string GetIndicatorShortName()
{
  return("Timar - Graviton Entry " + Symbol());
}

string GetOrderComment(int magic)
{
  return("GravitonEntry " + magic);
}

int CalculateMagicHash()
{
  string s = "" + Symbol() + GetIndicatorShortName() + TerminalPath();
  
  int hash = 0;
  int c;
  for (int i=0; i < StringLen(s); i++)
  {
    c = StringGetChar(s, i);
    hash = c + (hash * 64) + (hash * 65536) - hash;
  }
  return (MathAbs(hash / 65536));
}


//+------------------------------------------------------------------+
//| expert initialization function                                   |
//+------------------------------------------------------------------+
int init()
{
  Magic = CalculateMagicHash();
  return(0);
}


//+------------------------------------------------------------------+
//| expert deinitialization function                                 |
//+------------------------------------------------------------------+
int deinit()
{
  DeleteAllObjects();
  return(0);
}


//+------------------------------------------------------------------+
//| expert start function                                            |
//+------------------------------------------------------------------+
int start()
{
  if (Magic == 0)
    Magic = CalculateMagicHash();
   
  _FindAllTickets();
  
  if (_IsTradeInMarket())
  {
    int ticket = _GetTicketInMarket();
    OrderSelect(ticket, SELECT_BY_TICKET);
    TradeDirection = OrderType();
    //TradeType = OrderType();
    
    _CheckSL(ticket);
    _CheckBE(ticket);
    //_CheckClose(ticket);
  }
  else  // Still waiting to enter
  {
    if (StringUpper(StringSubstr(EntryDirection,0,1)) == "L")
      TradeDirection = OP_BUY;
    else if (StringUpper(StringSubstr(EntryDirection,0,1)) == "S")
      TradeDirection = OP_SELL;
    else
    {
      Comment("ERROR: EntryDirection must be \"LONG\" or \"SHORT\" was \"" + EntryDirection + "\"");
      return (0);
    }
    
    _UpdatePrice();
    if (_ActualEntryPrice != 0  &&  TimeCurrent() < ExpiryTime)
    {
      _CheckEnter();
    }
  }
  
  _UpdateComment();
  _UpdateObjects();

  return(0);
}


int _GetTradeType()
{
  if (_IsTradeInMarket())
  {
    OrderSelect(OpenTicket, SELECT_BY_TICKET);
    return (OrderType());
  }
  else
  {
    double price = _GetCurrentOpenPrice();
    if (TradeDirection == OP_BUY)
    {
      if (_ActualEntryPrice < price)
        return (OP_BUYLIMIT);
      else
        return (OP_BUYSTOP);
    }
    else
    {
      if (_ActualEntryPrice > price)
        return (OP_SELLLIMIT);
      else
        return (OP_SELLSTOP);
    }
  }
}


void _UpdateComment()
{
  string s =
    GetIndicatorShortName() 
    + " " + PeriodToStr(Period())
    + "  Spread: " + DoubleToStr(MarketInfo(Symbol(), MODE_SPREAD)/10, 1) + " pips"
    + "  Swap L/S: $" + DoubleToStr(MarketInfo(Symbol(), MODE_SWAPLONG),2) + "/$" + DoubleToStr(MarketInfo(Symbol(), MODE_SWAPSHORT),2);
    
  if (IsMouseDown())
    s = s + " [MouseDown]";
    
  s = s + 
    "\nEntry Price: " + DoubleToStr(_ActualEntryPrice, Digits); 
  
  if (TimeCurrent() >= ExpiryTime)
    s = s + "\nEntry Time EXPIRED " + TimeToStr(ExpiryTime);
  
  Comment(s); 
}


void _UpdateObjects()
{
  int y = 15;
    
  color clr;
  if (TradeDirection == OP_BUY)
    clr = Blue;
  else
    clr = Red;
  
  int dir;
  //TradeType = _GetTradeType();
  //if (TradeType == OP_BUYLIMIT || TradeType == OP_SELLSTOP)
  //  dir = -1;
  //else if (TradeType == OP_SELLLIMIT || TradeType == OP_BUYSTOP)
  //  dir = +1;
  //else
  //  dir = 0;
  
  //if (dir == 0)
  //{
  //  DeleteObject("entrySlackHigh");
  //  DeleteObject("entrySlackLow");
  //}
  //else
  //{
    SetLine("entrySlackHigh", _ActualEntryPrice + PipsToPrice(EntrySlack_Pips), clr, STYLE_DOT);
    SetLine("entrySlackLow",  _ActualEntryPrice - PipsToPrice(EntrySlack_Pips), clr, STYLE_DOT);
  //}
  
  // -- STATUS --------------------------------------------
  string stmp;
  if (_IsTradeInMarket())
    stmp = "Ticket OPEN: " + OpenTicket;
  else if (TimeCurrent() >= ExpiryTime)
    stmp = "Entry Time EXPIRED";
  else if (EntryTriggerSet)
    stmp = "READY to enter";
  else if (_ActualEntryPrice == 0)
    stmp = "NO ENTRY price";
  else
    stmp = "WAITING for price";
  SetLabel("status", 15, y, stmp, Black);
  ObjectSet(pfx+"status", OBJPROP_CORNER, 1);
  y += fontSize + 5;
  
  
  dir = _GetLowerTimeframeStochDir();
  if (dir < 0)       { stmp = "Stochs: DOWN";  clr = Red;   }
  else if (dir > 0)  { stmp = "Stochs: UP";    clr = Blue;  }
  else               { stmp = "Stochs: Mixed"; clr = Black; }
  
  SetLabel("stochs", 15, y, stmp, clr);
  ObjectSet(pfx+"stochs", OBJPROP_CORNER, 1);
  y += fontSize + 3;
  
  // ------------------------------------------------------
  //switch (_GetTradeType())
  //{
  //  case OP_BUY:       stmp = "OP_BUY";        clr = Blue; break;
  //  case OP_BUYLIMIT:  stmp = "OP_BUYLIMIT";   clr = Blue; break;
  //  case OP_BUYSTOP:   stmp = "OP_BUYSTOP";    clr = Blue; break;
  //  case OP_SELL:      stmp = "OP_SELL";       clr = Red;  break;
  //  case OP_SELLLIMIT: stmp = "OP_SELLLIMIT";  clr = Red;  break;
  //  case OP_SELLSTOP:  stmp = "OP_SELLSTOP";   clr = Red;  break;
  //  default:           stmp = "TradeType: Unknown"; clr = Black; break;
  // }
  //SetLabel("tradetype", 15, y, "TradeType: " + stmp, clr);
  //ObjectSet(pfx+"tradetype", OBJPROP_CORNER, 1);
  //y += fontSize + 3;

  // ------------------------------------------------------
  stmp = "";
  if (EntryTriggerSet)
    stmp = stmp + " [EntryTrigger]";
    
  if (_IsPriceWithinEntryRange(_GetCurrentOpenPrice()))
    stmp = stmp + " [WithinEntryRange]";
    
  if (ImmediateEntry)
    stmp = stmp + " [ImmediateEntry]";
    
  SetLabel("flags", 15, y, stmp, Black);
  ObjectSet(pfx+"flags", OBJPROP_CORNER, 1);
  y += fontSize + 3;
}


void _UpdatePrice()
{
  bool mouseDown = InteractivePriceBar && IsMouseDown();
  color clr;
  if (TradeDirection == OP_BUY)
    clr = Blue;
  else
    clr = Red;
    
  if (mouseDown && ObjectFind(Object_EntryName) >= 0)
  {
    if (_ActualEntryPrice != ObjectGet(Object_EntryName, OBJPROP_PRICE1))
    {
      _ActualEntryPrice = ObjectGet(Object_EntryName, OBJPROP_PRICE1);
      EntryTriggerSet = false;
      LastTickRelativeToEntry = 0;
    }
  }
  else
  {
    if (InteractivePriceBar && ObjectFind(Object_EntryName) >= 0)
    {
      if (ObjectGet(Object_EntryName, OBJPROP_PRICE1)  == 0)
        ObjectDelete(Object_EntryName);
      else
      {
        if (ObjectGet(Object_EntryName, OBJPROP_PRICE1)  !=  _ActualEntryPrice)
        {
          EntryTriggerSet = false;
          LastTickRelativeToEntry = 0;
        }
        _ActualEntryPrice = ObjectGet(Object_EntryName, OBJPROP_PRICE1);
      }
    }
    else
    {
      _ActualEntryPrice = EntryPrice;
      if (EntryPrice != 0)
      {
        ObjectCreate(Object_EntryName, OBJ_HLINE, 0, 0, _ActualEntryPrice,0);    
        ObjectSet(Object_EntryName, OBJPROP_STYLE, STYLE_SOLID);
        ObjectSet(Object_EntryName, OBJPROP_WIDTH, 2);     
        ObjectSetText(Object_EntryName, "entry price");
      }
      else
        ObjectDelete(Object_EntryName);
    }
  }
  if (ObjectFind(Object_EntryName) >= 0)
    ObjectSet(Object_EntryName, OBJPROP_COLOR, clr);
}


void _CheckSL(int ticket)
{
  if (OrderSelect(ticket, SELECT_BY_TICKET))
  {
    if (NormalizeDouble(OrderStopLoss(), Digits) == 0)
    {
      double sl;
      
      if (TradeDirection == OP_BUY)
        sl = OrderOpenPrice() - PipsToPrice(Stop_Pips) - _GetSpread$();
      else
        sl = OrderOpenPrice() + PipsToPrice(Stop_Pips) + _GetSpread$();
        
      _MoveStop(ticket, sl);      
    }
  }
}




void _CheckBE(int ticket)
{
  if (TradeDirection == OP_BUY)
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


void _CheckClose(int ticket)
{
  if (!OrderSelect(ticket, SELECT_BY_TICKET))
    return;
    
  double profitpips = PriceToPips(_dir()*_GetCurrentClosePrice() - _dir()*OrderOpenPrice());
  
  if (profitpips <= MaximumAdverseExcursion_Pips)
  {
    _CloseTicket(ticket);
    EntryTriggerSet = true;
    return;
  }
  
  if (profitpips >= StopToBE_Pips)
  {
    EntryTriggerSet = false;
    _MoveStopToBE(ticket);
  }
}


int _GetPriceRelativeToEntry(double price)
{
  if (price > _ActualEntryPrice)
    return (+1);
  else if (price < _ActualEntryPrice)
    return (-1);
  else  
    return (0);
}


void _CheckEnter()
{
  if (_IsMaxRetries() || IsMouseDown())
    return;

  if (EntryTriggerSet  &&  !_IsPriceWithinEntryRange(_GetCurrentOpenPrice()))
    EntryTriggerSet = false;

  int tickRelativeToEntry = _GetPriceRelativeToEntry(_GetCurrentOpenPrice());
  
  if (!EntryTriggerSet)
  {
    if ((LastTickRelativeToEntry < 0  &&  tickRelativeToEntry > 0)
     || (LastTickRelativeToEntry > 0  &&  tickRelativeToEntry < 0))
    {
      EntryTriggerSet = true;
    }
  }
  LastTickRelativeToEntry = tickRelativeToEntry;


  if (ImmediateEntry)
    EntryTriggerSet = true;
    

  if (EntryTriggerSet)
  {
    if ((TradeDirection == OP_BUY  &&  _GetLowerTimeframeStochDir() > 0)
     || (TradeDirection == OP_SELL &&  _GetLowerTimeframeStochDir() < 0))
    {
      if (_IsPriceWithinEntryRange(_GetCurrentOpenPrice()))
        _EnterNow();
    }
  }
}


bool _IsPriceWithinEntryRange(double price)
{
  double high = _ActualEntryPrice + PipsToPrice(EntrySlack_Pips) + _GetSpread$();
  double low =  _ActualEntryPrice - PipsToPrice(EntrySlack_Pips) - _GetSpread$();
  
  return (low <= price  &&  high >= price);
}


void _EnterNow()
{
  double price = _GetCurrentOpenPrice();
  double lots = _GetTradeLots();
  
  double tp;
  double sl;
  
  int op = TradeDirection;
  if (op == OP_BUY)
  {
    sl = price - PipsToPrice(Stop_Pips) - _GetSpread$();
    if (TakeProfit_Pips != 0)
      tp = price + PipsToPrice(TakeProfit_Pips);
  }
  else
  {
    sl = price + PipsToPrice(Stop_Pips) + _GetSpread$();
    if (TakeProfit_Pips != 0)
      tp = price - PipsToPrice(TakeProfit_Pips);
  }

  int ticket = OrderReliableSend(Symbol(), op, lots, price, MarketInfo(Symbol(), MODE_SPREAD), 0, 0, GetOrderComment(Magic), Magic, 0);
  if (ticket > 0)
  {
    OrderSelect(ticket, SELECT_BY_TICKET);    
    if (!OrderReliableModify(ticket, OrderOpenPrice(), NormalizeDouble(sl, Digits), NormalizeDouble(tp, Digits), OrderExpiration()))
    {
      Print("Failed setting sell stoploss ", ErrorDescription(GetLastError()));
      Print("  > lotsize: ", lots, " price: ", price, " sl: ", sl, " magic: ", Magic);      
    }
  }
}


int _dir()
{
  if (TradeDirection == OP_BUY)
    return (+1);
  else
    return (-1);
}


bool _IsTradeExpired()
{
  return (ExpiryTime != 0  &&  TimeCurrent() >= ExpiryTime);
}


bool _IsTradeLong()
{
  return (TradeDirection == OP_BUY);
}


bool _IsTicketClosed(int ticket)
{
  if (OrderSelect(ticket, SELECT_BY_TICKET))
    return (OrderCloseTime() != 0);
  else
    return (false);
}


bool _IsMaxRetries()
{
  return (false);
  //return (TicketCount > MaxRetries);  // InitialTicket=1, each subsequent entry+1.  So MaxRetries=5 is TicketCount 1+5=6. i.e. >5
}


double _GetCurrentClosePrice()
{
  if (_IsTradeLong())
    return (Bid);
  else
    return (Ask);
}


double _GetCurrentOpenPrice()
{
  if (_IsTradeLong())
    return (Ask);
  else
    return (Bid);
}


double _GetEntryPrice()
{
  if (_IsTradeInMarket())
  {
    if (OrderSelect(OpenTicket, SELECT_BY_TICKET))
      return (OrderOpenPrice());
  }
  else
    return (_ActualEntryPrice);
}


int _GetStochSignal(string pair, int period)
{
  double signal = iStochastic(pair, period, 8, 3, 3, MODE_SMA, 0, MODE_SIGNAL, 0);
  double main = iStochastic(pair, period, 8, 3, 3, MODE_SMA, 0, MODE_MAIN, 0);
  
  if (main > signal)
    return (+1);
  else if (main < signal)
    return (-1);
  else
    return (0);  
}


int _GetLowerTimeframeStochDir()
{
  int m1dir  = _GetStochSignal(Symbol(), PERIOD_M1);
  int m5dir  = _GetStochSignal(Symbol(), PERIOD_M5);
  int m15dir = _GetStochSignal(Symbol(), PERIOD_M15);
  
  if (m1dir < 0  &&  m5dir < 0  &&  m15dir < 0)
    return (-1);
  else if (m1dir > 0  &&  m5dir > 0  &&  m15dir > 0)
    return (+1);
  else
    return (0);
}


bool _IsPriceHit(double price)
{
  if (_IsTradeLong())
    return (_GetCurrentOpenPrice() >= price);
  else
    return (_GetCurrentOpenPrice() <= price);
}


double _GetTradeLots()
{
  if (OpenTicket != 0)
  {
    OrderSelect(OpenTicket, SELECT_BY_TICKET);
    return (OrderLots());
  }
  else
    return (Lots);
}


/*
double _GetTradeTakeProfit()
{
  if (OrderSelect(InitialTicket, SELECT_BY_TICKET))
    return (OrderTakeProfit());
  else
    return (0.0);
}


double _GetTradeStopLoss()
{
  if (OrderSelect(InitialTicket, SELECT_BY_TICKET))
    return (OrderStopLoss());
  else
   return (0.0);
}
*/


int _FindFirstOpenMagicTicket(int magic)
{  
  for (int i=0; i<OrdersTotal(); i++)
    if (OrderSelect(i, SELECT_BY_POS))
    {
      if (OrderCloseTime() == 0  &&  OrderMagicNumber() == magic)
        return (OrderTicket());
    }
  return (0);
}


void _FindAllTickets()
{
  OpenTicket = _FindFirstOpenMagicTicket(Magic);
  if (OpenTicket == 0)
    return;
  
  /*
  TicketCount = 0;
  
  if (!OrderSelect(InitialTicket, SELECT_BY_TICKET))
    return;
    
  datetime initialTicketTime = OrderOpenTime();
    
  Tickets[TicketCount] = InitialTicket;
  TicketCount++;
  
  for (int i=0; i<OrdersHistoryTotal(); i++)
  {
    if (OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
    {
      if (OrderOpenTime() > initialTicketTime  &&  OrderMagicNumber() == Magic  &&  OrderTicket() != InitialTicket)
      {
        Tickets[TicketCount] = OrderTicket();
        TicketCount++;
      }
    }
  }
  
  for (i=0; i<OrdersTotal(); i++)
  {
    if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
    {
      if (OrderOpenTime() > initialTicketTime  &&  OrderMagicNumber() == Magic  &&  OrderTicket() != InitialTicket)
      {
        Tickets[TicketCount] = OrderTicket();
        TicketCount++;
      }
    }
  }
  
  _SortTicketsByTimeDescending();
  
  OpenTicket = _GetTicketInMarket();
  */
}


// Sort by time is easy.  Later orders will have a higher ID!
/*
void _SortTicketsByTimeDescending()
{
  int i,j;
  int lowestIndex;
  bool ascending = false;
  for (i=0;  i < TicketCount-1;  i++)
  {
    lowestIndex = i;
    for (j=i+1;  j < TicketCount;  j++)
    {
      if (ascending &&  Tickets[j] < Tickets[lowestIndex])
        lowestIndex = j;
      else if (!ascending  &&  Tickets[j] > Tickets[lowestIndex])
        lowestIndex = j;
    }

    if (lowestIndex != i)
    {
      int swap = Tickets[lowestIndex];
      Tickets[lowestIndex] = Tickets[i];
      Tickets[i] = swap;
    }
  }
}
*/


bool _IsTicketInMarket(int ticket)
{
  if (OrderSelect(ticket, SELECT_BY_TICKET))
    return (OrderType() == OP_BUY  ||  OrderType() == OP_SELL);
  else
    return (false);
}


bool _IsTradeInMarket()
{
  return (_GetTicketInMarket()!=0);
}


int _GetTicketInMarket()
{
  return (OpenTicket);
}


void _CloseTicket(int ticket, double lots=0.0)
{
  int retries=3;
  while (retries > 0)
  {    
    if (!OrderSelect(ticket, SELECT_BY_TICKET))
      return;
      
    if (lots <= 0)
      lots = OrderLots();
          
    if (OrderClose(ticket, lots, _GetCurrentClosePrice(), MarketInfo(Symbol(), MODE_SPREAD)))
    {
      //FindAllRelatedTickets();
      //DoSendMailClosed(ticket, lots);
      break;
    }
    else 
      Print("Close ticket " + ticket + " failed, retrying: " + ErrorDescription(GetLastError()));
      
    if (GetLastError() >= 4000) // software error
      break;
    
    retries--;
    Sleep(250);
  }    
}


void _MoveStopToBE(int ticket)
{
  if (OrderSelect(ticket, SELECT_BY_TICKET))
    _MoveStop(ticket, OrderOpenPrice() + _dir()*PipsToPrice(LockInAtBE_Pips));
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


double _GetSpread$()
{
  if (IncludeSpread)
    return (MarketInfo(Symbol(), MODE_SPREAD)*Point);
  else
    return (0.0);
}



//+------------------------------------------------------------------+


void DeleteAllObjectsWithPrefix(string prefix)
{
  for(int i = ObjectsTotal() - 1; i >= 0; i--)
  {
    string label = ObjectName(i);
    if(StringSubstr(label, 0, StringLen(prefix)) == prefix)
      ObjectDelete(label);   
  }
}


void DeleteAllObjects()
{
  DeleteAllObjectsWithPrefix(pfx);
}


void DeleteObject(string name)
{
  ObjectDelete(pfx+name);
}


#import "user32.dll"
   int GetKeyState(int virtKey);
#import

#define VK_LBUTTON  1
#define VK_MBUTTON  4
#define VK_RBUTTON  2

bool IsMouseDown()
{
  return (GetKeyState(VK_RBUTTON) >= 0x8000  ||  GetKeyState(VK_LBUTTON) >= 0x8000 );
}


double PipsToPrice(double pips)
{
  return (pips*10 * Point);
}


double PriceToPips(double price)
{
  return (price / Point / 10);
}


double PointsToPrice(double points)
{
  return (points * Point);
}


string StringUpper(string str)
{ 
  string outstr = "";
  string lower  = "abcdefghijklmnopqrstuvwxyz";
  string upper  = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
  for(int i=0; i<StringLen(str); i++)  {
    int t1 = StringFind(lower,StringSubstr(str,i,1),0);
    if (t1 >=0)  
      outstr = outstr + StringSubstr(upper,t1,1);
    else
      outstr = outstr + StringSubstr(str,i,1);
  }
  return(outstr);
}


void _SetLine(string name, double value, color clr, int style, int lineWidth, int lineType)
{
  int windowNumber = 0; // WindowFind(GetIndicatorShortName());
  
  if (ObjectFind(pfx+name) < 0)
  {
    if (lineType == OBJ_VLINE)
      ObjectCreate(pfx+name, lineType, windowNumber, value,0,0);    
    else
      ObjectCreate(pfx+name, lineType, windowNumber, 0,value,0);
    
    ObjectSet(pfx+name, OBJPROP_STYLE, style);
    ObjectSet(pfx+name, OBJPROP_WIDTH, lineWidth);
  }
  else
  {
    if (lineType == OBJ_VLINE)
      ObjectSet(pfx+name, OBJPROP_TIME1, value);
    else    
      ObjectSet(pfx+name, OBJPROP_PRICE1, value);
  }
  ObjectSet(pfx+name, OBJPROP_COLOR, clr);
}


void SetLine(string name, double value, color clr, int style, int lineWidth=1)
{
  _SetLine(name, value, clr, style, lineWidth, OBJ_HLINE);
}


void SetVertLine(string name, double time, color clr, int style, int lineWidth=1)
{
  _SetLine(name, time, clr, style, lineWidth, OBJ_VLINE);
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


string PeriodToStr(int period)
{
  switch (period)
  {
    case PERIOD_MN1: return ("MN1");
    case PERIOD_W1:  return ("W1");
    case PERIOD_D1:  return ("D1");
    case PERIOD_H4:  return ("H4");
    case PERIOD_H1:  return ("H1");
    case PERIOD_M30: return ("M30");
    case PERIOD_M15: return ("M15");
    case PERIOD_M5:  return ("M5");
    case PERIOD_M1:  return ("M1");
    default:         return("M? [" + period + "]");
  }
}

