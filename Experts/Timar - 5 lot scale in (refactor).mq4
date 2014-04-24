//+------------------------------------------------------------------+
//|                                       Timar - 5 lot scale in.mq4 |
//|                              Copyright © 2010, Timar Investments |
//|                               http://www.timarinvestments.com.au |
//
// This refacor is an attempt to move the trade management out into a 
//  reusable include file.
//
// The idea here is that you make a manual entry, or place 
// a single stop or limit order manually. Enter the ticket number of
// that order in the InitialTicket field.
//
// The expert will scale in and out of the trade as it progresses,
// until all lots are closed. It will then deactivate.
//
// Lot size is taken from the InitialTicket.
// All subsequent lots will be the same size.
// Total lots in could then be Lots(InitialTicket) * 5.
// Make sure you have sufficient margin.
//
//
// Rules
//  [LotsIn = 1]
//  Let Ticket(1) = InitialTicket
//  When Ticket(1) is PipTarget(15pips) ahead
//    Move Ticket(1) stop to break even
//    Enter Ticket(2) with S/L set to -PipTarget (i.e. same as Ticket(1) entry)
//    LotsIn = 2
//
//  [LotsIn = 2]
//  When Ticket(2) is PipTarget(15pips) ahead
//    Move Ticket(2) stop to break even
//    Move Ticket(1) stop to Ticket(1) + PipTarget (i.e. same as Ticket(2) entry, capturing 1xPipTarget Profit)
//    Move Ticket(1) take profit to + 2xPipTarget
//    Enter Ticket(3) with S/L set to -PipTarget
//    LotsIn = 3
//
//  [LotsIn = 3]
//  If price moves against us, we let the stops be hit and break even.
//  When price reaches Ticket(1) entry + 2xPipTarget (30 pips)
//    Ticket(1) will hit take profit and close
// 
//  ...
//
// Price	Lot	Entry	Stop	Risk
// Lots = 1				
// 100 #1 100  80 -20
//                -20
// Lots = 2 (Price+20)
// 120 #1 100 100   0
// 120 #2 120 100 -20
//                -20
// Lots = 3	(Price+40)			
// 140 #1 100 120  20
// 140 #2 120 120   0
// 140 #3 140 120 -20
//                  0
//Lots = 4 (Price+60)
// 160 #1 100 140  40
// 160 #2 120 140  20
// 160 #3 140 140   0
// 160 #4 160 140 -20
//                 40
// Lots = 5 (Price+80)
// 180 #1 100 160  60
// 180 #2 120 160  40
// 180 #3 140 160  20
// 180 #4 160 160   0
// 180 #5 180 160 -20
//                100
//
// Usage Notes
//   EA attempts to keep stop and takeprofit valid for every open ticket.
//   This way, nothing too bad will happen if we lose power, computer or internet (PCI).
//   If InitialTicket has no stop loss then a stoploss/takeprofit will be assigned to it.
//     Initial SL will be PipTarget, Initial TP will be 2xPipTarget (had trouble setting inital TP if it is current price is beyond it. just setting sl for now).
//
// Implementation Notes
//   Since we aren't partly closing and orders, finding the orders
//   related to our instance is as easy as finding all orders
//   with the specified magic number that were opened after the InitialTicket.
//
// Alternate Strategy
//   This strategy eliminates risk faster, at the cost of getting the 2nd lot on later
//   (leading to 40% less profit by the time the 5th lot is on, but a 50% reduction in pips to 0 risk)
//
//   Lots = 1
//   100 #1 100 80 -20
//                 -20
//
//   Lots = 1 (Price +20)
//   120 #1 100 100   0
//                    0
//
//   Lots = 2 (Price +40)
//   140 #1 100 120 +20
//   140 #2 140 120 -20
//                    0
//
//   Lots = 3&4 (Price +60)
//   160 #1 100 140 +40
//   160 #2 140 140   0
//   160 #3 160 140 -20
//   160 #4 160 140 -20
//                    0
//
//   Lots = 5 (Price +80)
//   180 #1 100 160 +60
//   180 #2 140 160 +20
//   180 #3 160 160   0
//   180 #4 160 160   0
//   180 #5 180 160 -20
//                  +60
//
//+------------------------------------------------------------------+

#include <codesite.mqh>
#include <ptutils.mqh>
#include <stdlib.mqh>
#include <fivelots.mqh>

#property copyright "Copyright © 2010, Timar Investments"
#property link      "http://www.timarinvestments.com.au"

//---- input parameters
extern bool      Active=true;

extern string    _0="__ In Trade Actions __";
extern bool      CloseAllTickets=false;
extern double    SetAllStops=0.0;

extern string    _1="__ Configuration _____";
extern double    StopTradingBalance$ = 3000.0;  // no entries while equity < this
extern int       InitialTicket = 0; //0;
extern int       PipTarget = 20;
extern double    Risk_Pct = 2.0;
//extern double    MaxLots  = 0.5;       // takes precedence over Risk_Pct

extern string    _2="____ Strategy __________";
extern string    _2a="__ 0=All In,  1=Chicken,  2=Graviton __";
extern int       Strategy = FVL_STRAT_CHICKEN;
extern bool      UseDoubleInitialStop = false;

extern int       MaxLots = 5;
extern double    StopToHalf_Pips = 50;

/*
  "All In" strategy enters at both.
  Graviton's strategy enters at 1st, but not 2nd.
  "Risk Minimiser" strategy does not enter at 1st.
*/

extern string _x = "__ Display _____________";
extern string CurrencySymbol = "$";
extern bool ShowCurrency = false;

//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+

string pfx="sin5l";

#define fontName     "Calibri"
#define boldFontName "Arial Black"
#define fontSize     8


#define NotActiveColor  Red

#define OrderCommentPrefix "5-Lot"

//+------------------------------------------------------------------+
string GetIndicatorShortName()
{
  return("Timar - 5 lot scale in " + Symbol());
}


int CalculateMagicHash()
{
  string s = "" + Symbol() + GetIndicatorShortName();
  
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
  FVL_Magic = CalculateMagicHash();
  FVL_InitialTicket = InitialTicket;
  FVL_IsTradeLong = _IsTradeLong();
  FVL_OrderCommentPrefix = OrderCommentPrefix;
  FVL_PipTarget = PipTarget;
  FVL_UseDoubleInitialStop = UseDoubleInitialStop;
  FVL_CloseAllTickets = CloseAllTickets;
  FVL_StopToHalf_PipsFromEntry = StopToHalf_Pips;
  FVL_MaxPositions = MaxLots;

  FVL_init();

  IndicatorShortName(GetIndicatorShortName());
  DeleteAllObjectsWithPrefix(pfx);

  _ObjectsUpdate();
  Comment(_GetCommentString());

  return(0);
}


//+------------------------------------------------------------------+
//| expert deinitialization function                                 |
//+------------------------------------------------------------------+
int deinit()
{
  FVL_deinit();
  
  DeleteAllObjectsWithPrefix(pfx);
  return(0);
}


//+------------------------------------------------------------------+
//| expert start function                                            |
//+------------------------------------------------------------------+
int start()
{
  if (IsTesting()  &&  InitialTicket == 0)
  {
    RefreshRates();
    InitialTicket = OrderSend(Symbol(), OP_SELLLIMIT, 2.5, 1430.00, 0, 0,0,"Initial",CalculateMagicHash());
    Log(csmGreen, "InitialTicket " + InitialTicket);
    if (InitialTicket > 0)
    {
      OrderSelect(InitialTicket, SELECT_BY_TICKET);
      OrderModify(InitialTicket, OrderOpenPrice(), 1435.00, 1390.00, 0,0);
      // OrderModify(InitialTicket, OrderOpenPrice(), 1386.00, 1500.00, 0,0);
    }
    else
      Print("Order failed: " + ErrorDescription(GetLastError()));
      
    FVL_InitialTicket = InitialTicket;
    FVL_IsTradeLong = _IsTradeLong();
    FVL_PipTarget = PipTarget;
    FVL_init();      
  }

  FVL_IsTradeLong = _IsTradeLong();
  if (FVL_Magic == 0)
    FVL_Magic = CalculateMagicHash();
  FVL_PipTarget = PipTarget;
  FVL_UseDoubleInitialStop = UseDoubleInitialStop;
  FVL_CloseAllTickets = CloseAllTickets;
  FVL_Strategy = Strategy;
    
  FVL_start();
  
  _ObjectsUpdate();
  
  Comment(_GetCommentString());
  return(0);
}


//+------------------------------------------------------------------+
//| Trade Management                                                 |
//+------------------------------------------------------------------+

double _GetTotalProfit()
{
  double total=0.0;
  
  total += FVL_GetTotalProfit$();
    
  return (total);
}


bool _IsActive()
{
  return ((Active  &&  (AccountEquity() > StopTradingBalance$)) || IsTesting());
}


bool _IsTradeClosed()
{
  if (FVL_TicketsCount > 0)
  {
    for (int i=0; i < FVL_TicketsCount; i++)
      if (!IsTicketClosed(FVL_Tickets[i]))
        return (false);
    return (true);
  }
  else
    return (false);
}


bool _IsTradeOpen()
{
  if (FVL_TicketsCount >= 0)
    return (IsTicketOpen(FVL_Tickets[0]));
  else
    return (false);
}


bool _IsTradePending()
{
  if (FVL_TicketsCount == 1)
    return (IsTicketPending(FVL_Tickets[0]));
  else
    return (false);
}


bool _IsTradeLong()
{
  if (FVL_InitialTicket != 0)
  {
    if (OrderSelect(FVL_InitialTicket, SELECT_BY_TICKET))
      return (OrderType() == OP_BUY  ||  OrderType() == OP_BUYLIMIT  ||  OrderType() == OP_BUYSTOP);
    else
      return (true);  // gotta return something
  }  
  else
    return (true);    // gotta return something
}


//+------------------------------------------------------------------+
//| Comment Functions                                                |
//+------------------------------------------------------------------+

string _GetCommentString()
{
  if (IsTesting())
    return("");
    
  string s = "";
  
  s = s + "\n" + FVL_Comment_Tickets();
    
  if (FVL_TicketsCount > 0)
  {
    s = s + "\n";
    
    if (_IsTradeLong())
      s = s + "LONG trade";
    else
      s = s + "SHORT trade";
    
    s = s + "  Total Lots: " + DoubleToStr(FVL_GetTotalLots(), 2);
  }
  
  s = s + "\nRisk Target " + DoubleToStr(Risk_Pct, 1) + "% " 
    + GetDollarDisplay(_GetRisk$()) 
    + "  Pip Target " + PipTarget 
    + "  Lots for Risk " + DoubleToStr(GetLotsForRisk(AccountEquity(), Risk_Pct, 0, PipsToPrice(PipTarget)),2);
  
  double atr = iATR(Symbol(), Period(), 14, 0);
    
  s = s 
    + "\nATR: " + DoubleToStr(atr, Digits-1) +  " " + DoubleToStr(atr/Point/10, 1) + " pips"
    + "  2x(ATR): " + DoubleToStr(2*atr/Point/10, 1) + " pips";
  
  return(_GetCommentHeader() + s);
}


string _GetCommentHeader()
{
  string header = 
    GetIndicatorShortName() 
    + " " + PeriodToStr(Period())
    //+ "  Magic: " + Magic
    + "  Spread: " + DoubleToStr(MarketInfo(Symbol(), MODE_SPREAD)/10, 1) + " pips"
    + "  Swap L/S: $" + DoubleToStr(MarketInfo(Symbol(), MODE_SWAPLONG),2) + "/$" + DoubleToStr(MarketInfo(Symbol(), MODE_SWAPSHORT),2)
    + "  SafetyNet: " + GetDollarDisplay(StopTradingBalance$);

  return(header);
}


//+------------------------------------------------------------------+
//| Object Functions                                                 |
//+------------------------------------------------------------------+

void _ObjectsUpdate()
{
  if (IsTesting())
    return;
  
  if (!_IsActive())
  {
    if (AccountEquity() <= StopTradingBalance$)
      SetLabelCentered("notactive", -6, "NOT ACTIVE - Safety Net Activated", NotActiveColor, 18, boldFontName);
    else
      SetLabelCentered("notactive", -4, "NOT ACTIVE", NotActiveColor, 18, boldFontName);
  }
  else if (CloseAllTickets)
    SetLabelCentered("notactive", -4, "Close All Tickets", Red, 18, boldFontName);
  else
    DeleteObject("notactive");
  
  SetLabel("magic", 5,5, "Magic# " + FVL_Magic, Blue);
  ObjectSet(pfx+"magic", OBJPROP_CORNER, 2);
  
  // -- Profit ------------------------------------------------------- 
  if (_IsTradeOpen() || _IsTradeClosed())
  {
    double dProfit = _GetTotalProfit();
    
    string sfinal = "";
    if (_IsTradeClosed())
      sfinal = "Final ";
    
    if (dProfit >= 0)
      SetLabel("lProfit", 10, 10, sfinal + "Profit $" + DoubleToStr(dProfit,2), Green);
    else
      SetLabel("lProfit", 10, 10, sfinal + "Loss ($" + DoubleToStr(dProfit,2) + ")", Red);
    ObjectSet(pfx+"lProfit", OBJPROP_CORNER, 3);
  }
  
  // -- Profit at stop ----------------------------------------------- 
  if (_IsTradeOpen() || _IsTradePending())
  {
    double dProfitAtStop = FVL_GetProfitAtStop$();
    if (dProfitAtStop >= 0)
      SetLabel("lProfitAtStop", 10, 10+ (fontSize*1)+2, "Profit at stop " + GetDollarDisplay(dProfitAtStop), Green);
    else
      SetLabel("lProfitAtStop", 10, 10+ (fontSize*1)+2, "Risk at stop " + GetDollarDisplay(dProfitAtStop), Red);
      
    ObjectSet(pfx+"lProfitAtStop", OBJPROP_CORNER, 3);
  }
  else
    DeleteObject("lProfitAtStop"); 
  
  // -- Trade status -------------------------------------------------
  if (FVL_TicketsCount > 0  &&  _IsTradeOpen())
    _ObjectSetStatus("OPEN: Tickets " + FVL_TicketsCount, Green);
  else if (FVL_TicketsCount > 0  &&  _IsTradePending())
    _ObjectSetStatus("PENDING: Ticket " + FVL_Tickets[0], Black);
  else if (FVL_TicketsCount > 0  &&  _IsTradeClosed())
    _ObjectSetStatus("CLOSED", Black);
  else
    _ObjectSetStatus("");
    
  // -- Strategy -----------------------------------------------------
  if (Strategy == FVL_STRAT_CHICKEN)
    _ObjectSetStrategy("Strategy: Chicken");
  else if (Strategy == FVL_STRAT_GRAVITON)
    _ObjectSetStrategy("Strategy: Graviton");
  else
    _ObjectSetStrategy("Strategy: All In");
    
  // -- Target Levels ------------------------------------------------
  if (_IsTradeOpen())
  {
    int t;
    int dir = FVL_dir();
    if (Strategy == FVL_STRAT_CHICKEN)
    {
      for (t=1; t<=MaxLots-2; t++)
        SetLine("l"+t, FVL_GetTicketOpenPrice(FVL_Tickets[0]) + dir*PipsToPrice(FVL_GetExpectedEntryPipsByPos(t)), Purple, STYLE_SOLID, 1);
      for (; t<=10; t++)
        DeleteObject("l"+t);
    }
    else
    {
      for (t=1; t<=MaxLots-1; t++)
        SetLine("l"+t, FVL_GetTicketOpenPrice(FVL_Tickets[0]) + dir*PipsToPrice(FVL_GetExpectedEntryPipsByPos(t)), Purple, STYLE_SOLID, 1);
      for (; t<=10; t++)
        DeleteObject("l"+t);
    }
  }
  else
  {
    for (t=1; t<=10; t++)
      DeleteObject("l"+t);
  }
}


void _ObjectSetStatus(string status, color clr=Black)
{
  if (status == "")
    DeleteObject("status");
  else
  { 
    SetLabel("status", 10, 13, status, clr);
    ObjectSet(pfx+"status", OBJPROP_CORNER, 1);
  }    
}


void _ObjectSetStrategy(string strategy)
{
  if (strategy == "")
    DeleteObject("strat");
  else
  {
    SetLabel("strat", 10, 13 + fontSize*1 +2, strategy, Black);
    ObjectSet(pfx+"strat", OBJPROP_CORNER, 1);
  }
}


double _GetRisk$()
{
  return (AccountEquity() * (Risk_Pct/100));
}


//+------------------------------------------------------------------+
//| Library functions                                                |
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

void DeleteObject(string name)
{
  ObjectDelete(pfx+name);
}


double GetLotsForRisk(double balance, double riskPercent, double entryPrice, double stopPrice)
{
  double priceDifference = MathAbs(entryPrice - stopPrice);
  double risk$ = balance * (riskPercent / 100.0);
  
  double riskPips = priceDifference/Point/10.0;
  
  double lotSize = (risk$ / riskPips) / ((MarketInfo(Symbol(), MODE_TICKVALUE)*10.0));

  return (lotSize);
}


bool IsTicketClosed(int ticket)
{
  if (OrderSelect(ticket, SELECT_BY_TICKET))
    return (OrderCloseTime() != 0);
  else
    return (false);
}


bool IsTicketOpen(int ticket)
{
  if (OrderSelect(ticket, SELECT_BY_TICKET))
    return ( (OrderType() == OP_BUY || OrderType() == OP_SELL)
             && (OrderCloseTime() == 0));
  else
    return (false);
}


bool IsTicketPending(int ticket)
{
  if (OrderSelect(ticket, SELECT_BY_TICKET))
  {
    if (OrderCloseTime() == 0)
      return (OrderType() != OP_BUY  &&  OrderType() != OP_SELL);
    else
      return (false);
  }
  else
    return (false);
}


void SetLine(string name, double value, color clr, int style, int lineWidth=1)
{
  int windowNumber = 0; // WindowFind(GetIndicatorShortName());
  
  if (ObjectFind(pfx+name) < 0)
    ObjectCreate(pfx+name, OBJ_HLINE, windowNumber, value,0,0);

  ObjectSet(pfx+name, OBJPROP_COLOR, clr);
  ObjectSet(pfx+name, OBJPROP_STYLE, style);
  ObjectSet(pfx+name, OBJPROP_WIDTH, lineWidth);
  ObjectSet(pfx+name, OBJPROP_PRICE1, value);
}


void SetText(string name, double x, double y, string text, color clr=CLR_NONE, int size=0, string face=fontName)
{
  int windowNumber = 0;
  
  if (size == 0)
    size = fontSize;
  
  if (ObjectFind(pfx+name) < 0)
    ObjectCreate(pfx+name, OBJ_TEXT, windowNumber, x, y);
  else
    ObjectMove(pfx+name, 0, x, y);
  
  ObjectSetText(pfx+name, text, size, face, clr);
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


void SetLabelCentered(string name, int xoffset, string text, color clr=CLR_NONE, int size=0, string face=fontName)
{
  int windowNumber = 0;
  
  if (size == 0)
    size = fontSize;
    
  int cxi = (WindowBarsPerChart() / 2) + xoffset;  
  double cy = (WindowPriceMin() + WindowPriceMax()) / 2;
  
  SetText(name, Time[cxi], cy, text, clr, size, face);
  //ObjectSet(pfx+name, OBJPROP_BACK, true);
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


string GetPipsDisplay(double pips)
{
  int digits;
  if (pips < -100  ||  pips > 100)
    digits = 0;
  else
    digits = 1;
  
  if (pips < 0)
    return ("(" + DoubleToStr(MathAbs(pips), digits) + " pips)");
  else
    return (DoubleToStr(pips, digits) + " pips");
}


double PipsToPrice(double pips)
{
  return (pips*10 * Point);
}

