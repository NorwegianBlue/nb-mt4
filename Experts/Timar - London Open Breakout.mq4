//+------------------------------------------------------------------+
//|                                 Timar - London Open Breakout.mq4 |
//|                              Copyright © 2010, Timar Investments |
//|                               http://www.timarinvestments.com.au |
/*
  Version 10
    Enhance multi-lot options.
    Fixed but with setting T/P on buy orders.
    
  Version 9
    Improve robustness of putting trades on by retrying on subsequent
      ticks if one of the trades faild.
    
  Version 8
    Allows more than one candle to be used to set min/max.

  Version 7
    MinimumEntryCandle_Pips = 0 now works.
    
  Version 6
    Added minimum entry candle pips.
*/
//+------------------------------------------------------------------+
#property copyright "Copyright © 2010, Timar Investments"
#property link      "http://www.timarinvestments.com.au"

#include <stderror.mqh>
#include <stdlib.mqh>
#include <ptutils.mqh>
#include <ptorders.mqh>
#include <fivelots.mqh>

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+

extern int _Version_ = 9;
extern bool Active = true;
int Magic = 0;

extern string _0 = "__ Failsafes ________________";
extern double StopTradingBalance$ = 3000.0;
extern string CommentPrefix = "London";

extern string _1 = "__ Timezone Adjustment _____________";
extern string _11 = "__ 9/0 is Go Markets Aus __";
extern int LondonSession_Hour = 9;  // GO Markets
extern int LondonSession_Min = 0;
extern string _1b = "__ 14/0 is Go Markets Aus __";
extern int NewYorkSession_Hour = 14;
extern int NewYorkSession_Min = 0;

extern color London_Clr = Bisque;
extern color NewYork_Clr = LightCyan;

extern int FridayClosing = 23;    //broker friday closing time

extern int BoxCandles_Count = 1;

extern string _2 = "__ Entry Rules ________________";
extern bool AllowLONG = true;
extern bool AllowSHORT = true;
extern bool OnlyTakeOneTrade = false;
extern bool ReenterIfStopped = true;
extern double MinimumEntryCandle_Pips = 35.0;
extern double ReentryLag_Pips = 10.0;
extern int Entry_Min = 30;   // Entry High/Low determined 
extern double EntryLag_Pips = 2.0;
extern double Risk_Pct = 2.0;
extern double MaxLots = 4.0;
extern double FixedLots = 0.2;
extern double LotsPerTenThousandEquity = 0;

extern string _3 = "__ Exit Rules _________________";
extern string _31= "// When in conflict first rule applies.";

extern bool UseOpposingEntryAsStop = false;
extern int OrderExpiry_Mins = 240;

extern string _32   = "__ Multi-lot Settings _________";
extern string _321 = "__ Strategies 0=All In, 1=Chicken, 2=Graviton __";
extern bool UseMultiLot    = false;
extern int  Multi_Strategy = FVL_STRAT_ALLIN;
extern int  Multi_MaxPositions = 2;
extern double Multi_StopToHalf_PipsFromEntry = 50;

extern string _33 = " __ Fixed Pips __";

extern double LockInPipsAtBE = 1;
extern int Stop_Pips = 20;
extern int StopToBE_Pips = 14;
extern int StopTo10_Pips = 30;
extern int StopToHalf_Pips = 40;

//extern int TP1_Pips = 30;
//extern double TP1_Factor = 0.5;

extern int TP_Pips = 60;


//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+

string pfx="tmlob";

#define fontName     "Calibri"
#define boldFontName "Arial Black"
#define fontSize     8

#define NotActiveColor        Red
#define SqueezeRectangleColor PaleGoldenrod

#define LongColor             Blue
#define ShortColor            Crimson

//+------------------------------------------------------------------+


int BuyTicket = 0;
int SellTicket = 0;

double BreakoutPrice_High = 0.0;
double BreakoutPrice_Low  = 0.0;

bool inLondonOpen = false;
bool inEntryZone = false;
bool inActiveZone = false;


//+------------------------------------------------------------------+

string GetIndicatorShortName()
{
  return("Timar - London Open Breakout " + Symbol());
}

string GetOrderComment(int magic)
{
  return(CommentPrefix + "OpenBreakout");
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
  if (!IsTesting())
    MathSrand(TimeLocal());

  Magic = CalculateMagicHash();
  FVL_init();
  DeleteAllObjects();
  return(0);
}


//+------------------------------------------------------------------+
//| expert deinitialization function                                 |
//+------------------------------------------------------------------+
int deinit()
{
  FVL_deinit();
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

  _FindAllRelatedTickets();
  _UpdateObjects();

  inLondonOpen = (Hour()==LondonSession_Hour && Minute()<Entry_Min);
  inEntryZone = (Hour()==LondonSession_Hour && Minute()>=Entry_Min);
  
  inActiveZone = (TimeHour(TimeCurrent())>=LondonSession_Hour  &&  TimeCurrent() < _GetCurrentLondonOpen() + OrderExpiry_Mins) && !inLondonOpen;  
  //               && (TimeCurrent() < _GetCurrentLondonOpen() + OrderExpiry_Mins);
    
  if (inEntryZone || (ReenterIfStopped && inActiveZone))
  {
    double value;
    int count = 1;
    int bar = iBarShift(Symbol(), PERIOD_M30, _GetCurrentLondonOpen());
    
    BreakoutPrice_High = iHigh(Symbol(), PERIOD_M30, bar) + PipsToPrice(EntryLag_Pips);
    BreakoutPrice_Low = iLow(Symbol(), PERIOD_M30, bar) - PipsToPrice(EntryLag_Pips);
    while (count < BoxCandles_Count)
    {
      value = iHigh(Symbol(), PERIOD_M30, bar+count) + PipsToPrice(EntryLag_Pips);
      if (value > BreakoutPrice_High)
        BreakoutPrice_High = value;
      
      value = iLow(Symbol(), PERIOD_M30, bar+count) - PipsToPrice(EntryLag_Pips);
      if (value < BreakoutPrice_Low)
        BreakoutPrice_Low = value;

      count++;
    }
    
    SetLine("high", BreakoutPrice_High, Blue, STYLE_SOLID, 2);
    SetLine("low", BreakoutPrice_Low, Red, STYLE_SOLID, 2);
  }

  if (inEntryZone && (BuyTicket==0 || SellTicket==0))
  {
    if (MinimumEntryCandle_Pips == 0  ||  PriceToPips(BreakoutPrice_High - BreakoutPrice_Low) >= MinimumEntryCandle_Pips)
    {
      _PlaceOrders(BuyTicket==0, SellTicket==0);
      _FindAllRelatedTickets();
    }
  }
  else
  {
    if (OnlyTakeOneTrade)
    {
      if (BuyTicket != 0  &&  SellTicket == 0)
      {
        OrderDelete(BuyTicket);
        BuyTicket = 0;
      }
      else if (BuyTicket == 0  &&  SellTicket != 0)
      {
        OrderDelete(SellTicket);
        SellTicket = 0;
      }

      if (_IsTicketInMarket(BuyTicket) && SellTicket != 0)
      {
        OrderDelete(SellTicket);
        SellTicket = 0;
      }
      else if (_IsTicketInMarket(SellTicket) && BuyTicket != 0)
      {
        OrderDelete(BuyTicket);
        BuyTicket = 0;
      }
    }
    
    if (ReenterIfStopped  &&  inActiveZone  &&  (BuyTicket != 0 || SellTicket != 0))
    {
      if (BuyTicket == 0)
      {
        if (Ask < (BreakoutPrice_High - PipsToPrice(ReentryLag_Pips)))
        {
          _PlaceOrders(true, false);
          _FindAllRelatedTickets();
        }
      }
      
      if (SellTicket == 0)
      {
        if (Bid > (BreakoutPrice_Low + PipsToPrice(ReentryLag_Pips)))
        {
          _PlaceOrders(false, true);
          _FindAllRelatedTickets();
        }
      }
    }
  }
  
  if (UseMultiLot)
  {
    bool closed = false;
    
    FVL_InitialTicket = 0;
    if (_IsTicketInMarket(BuyTicket))
    {
      FVL_InitialTicket = BuyTicket;
      FVL_IsTradeLong = true;
    }
    else if (_IsTicketInMarket(SellTicket))
    {
      FVL_InitialTicket = SellTicket;
      FVL_IsTradeLong = false;
    }

    if (FVL_InitialTicket != 0)
    {
      static int ProcessingMultilot = 0;
      
      FVL_Magic = Magic;
      FVL_LockInPipsAtBE = LockInPipsAtBE;
      FVL_Strategy = Multi_Strategy;
      FVL_MaxPositions = Multi_MaxPositions;

      if (ProcessingMultilot != FVL_InitialTicket)
      {
        //Log(0, "Processing Multilot " + FVL_InitialTicket);
        ProcessingMultilot = FVL_InitialTicket;
        FVL_init();
      }

      if (FVL_GetProfitAtStop$() < 0)
        _CheckBE(FVL_InitialTicket);
        
      if (Stop_Pips > 0)
        FVL_PipTarget = Stop_Pips;
      else
        FVL_PipTarget = 30;
      
      FVL_StopToHalf_PipsFromEntry = Multi_StopToHalf_PipsFromEntry;
      
      FVL_start();
    }
  }
  else
  {
    if (_IsTicketInMarket(BuyTicket))
    {
      _CheckBE(BuyTicket);
      _CheckTP1(BuyTicket);
    }
 
    if (_IsTicketInMarket(SellTicket))
    {
      _CheckBE(SellTicket);
      _CheckTP1(SellTicket);
    }
  }
 
  string s = "";
  if (inLondonOpen)
    s = s + "[In London Open] ";
  if (inEntryZone)
    s = s + "[In Entry Zone] ";
    
  if (inActiveZone)
    s = s + "[In Active Zone] ";
  
  if (_AreOrdersPlaced())
  {
    s = s +
      "\nOrders placed: long " + BuyTicket + "  short " + SellTicket;
  }

  if (s != "")
    Comment(s);
      
  //Setup orders
  //if(Hour()==LondonSession_Hour  &&  Minute()>=LondonSession_Min && Minute()< (LondonSession_Min + 10) )
  //{
  //  //
  //}

  return(0);
}


void _CheckClose()
{
  //
}


void _CheckBE(int ticket)
{
  if (StopToBE_Pips == 0  ||  !OrderSelect(ticket, SELECT_BY_TICKET))
    return;
  
  bool orderLong; 
  switch (OrderType())
  {
    case OP_BUY:  orderLong = true;  break;
    case OP_SELL: orderLong = false; break;
    default:      return;
  }
  
  double targetprice;
  if (orderLong)
  {
    if (StopToHalf_Pips != 0  &&  Bid > OrderOpenPrice() + PipsToPrice(StopToHalf_Pips))
      _MoveStop(ticket, OrderOpenPrice() + (Bid - OrderOpenPrice())/2);
    else
    if (StopTo10_Pips != 0  &&  Bid > OrderOpenPrice() + PipsToPrice(StopTo10_Pips))
      _MoveStop(ticket, OrderOpenPrice() + PipsToPrice(10));
    else
    if (Bid > OrderOpenPrice() + PipsToPrice(StopToBE_Pips))
      _MoveStop(ticket, OrderOpenPrice() + PipsToPrice(LockInPipsAtBE));
  }
  else
  {
    if (StopToHalf_Pips != 0  &&  Ask < OrderOpenPrice() - PipsToPrice(StopToHalf_Pips))
      _MoveStop(ticket, OrderOpenPrice() - (OrderOpenPrice() - Ask)/2);
    else
    if (StopTo10_Pips != 0  &&  Ask < OrderOpenPrice() - PipsToPrice(StopTo10_Pips))
      _MoveStop(ticket, OrderOpenPrice() - PipsToPrice(10));
    else
    if (Ask < OrderOpenPrice() - PipsToPrice(StopToBE_Pips))
      _MoveStop(ticket, OrderOpenPrice() - PipsToPrice(LockInPipsAtBE));
  }
}


void _CheckTP1(int ticket)
{


}


#define TEN_MINUTES 600
void _PlaceOrders(bool placeBuy = true,  bool placeSell = true)
{
  placeBuy = placeBuy && AllowLONG;
  placeSell = placeSell && AllowSHORT;

  double buyprice, sellprice, tp=0.0, sl;
  double spread$ = Ask-Bid;
  int buyop, sellop;
  double lotSize;
  
  datetime expiry;
  if (OrderExpiry_Mins != 0)
    expiry = _GetCurrentLondonOpen() + OrderExpiry_Mins*60;
  else
    expiry = 0;
    
  if (TimeCurrent() + TEN_MINUTES > expiry)   // orders cannot expire within 10 minutes
    expiry = 0;

  // -- Buy Order --
  if (Ask > BreakoutPrice_High)
  {
    buyprice = Ask;
    buyop = OP_BUY;
  }
  else
  {
    buyprice = BreakoutPrice_High;
    buyop = OP_BUYSTOP;
  }
  
  // -- Sell Order --
  if (Bid < BreakoutPrice_Low)
  {
    sellprice = Bid;
    sellop = OP_SELL;
  }
  else
  {
    sellprice = BreakoutPrice_Low;
    sellop = OP_SELLSTOP;
  }

  // -- BUY ORDER --
  if (UseOpposingEntryAsStop)
    sl = sellprice;
  else
  {
    sl = buyprice - PipsToPrice(Stop_Pips);
    if (sl < sellprice)
      sl = sellprice;
  }

  if (FixedLots == 0)
    if (Risk_Pct == 0)
      lotSize = NormalizeDouble((AccountBalance() / 10000) * LotsPerTenThousandEquity, 2);
    else
      lotSize = MathMin(GetLotsForRisk(AccountEquity(), Risk_Pct, buyprice, sl), MaxLots);
  else
    lotSize = FixedLots;
  
  if (TP_Pips != 0)
    tp = buyprice + PipsToPrice(TP_Pips);
    
  if (placeBuy)
  {
    BuyTicket = OrderReliableSend(Symbol(), buyop, lotSize, buyprice, spread$, 0, 0, GetOrderComment(Magic), Magic, 0);
    if (BuyTicket > 0)
    {
      OrderSelect(BuyTicket, SELECT_BY_TICKET);    
      if (!OrderReliableModify(BuyTicket, OrderOpenPrice(), NormalizeDouble(sl, Digits), NormalizeDouble(tp, Digits), expiry))
      {
        Print("Failed setting buy stoploss ", ErrorDescription(GetLastError()));
        Print("  > lotsize: ", lotSize, " price: ", buyprice, " sl: ", sl, " expiry: ", TimeToStr(expiry) );
      }
    }
  }
  
  // -- SELL ORDER --
  if (UseOpposingEntryAsStop)
    sl = buyprice;
  else
  {
    sl = sellprice + PipsToPrice(Stop_Pips);
    if (sl > buyprice)
      sl = buyprice;
  }
    
  if (FixedLots == 0)
    if (Risk_Pct == 0)
      lotSize = NormalizeDouble((AccountBalance() / 10000) * LotsPerTenThousandEquity, 2);
    else
      lotSize = MathMin(GetLotsForRisk(AccountEquity(), Risk_Pct, sellprice, sl), MaxLots);
  else
    lotSize = FixedLots;

  if (TP_Pips != 0)
    tp = sellprice - PipsToPrice(TP_Pips);

  if (placeSell)
  {
    SellTicket = OrderReliableSend(Symbol(), sellop, lotSize, sellprice, spread$, 0, 0, GetOrderComment(Magic), Magic, 0);
    if (SellTicket > 0)
    {
      OrderSelect(SellTicket, SELECT_BY_TICKET);    
      if (!OrderReliableModify(SellTicket, OrderOpenPrice(), NormalizeDouble(sl, Digits), NormalizeDouble(tp, Digits), expiry))
      {
        Print("Failed setting sell stoploss ", ErrorDescription(GetLastError()));
        Print("  > lotsize: ", lotSize, " price: ", sellprice, " sl: ", sl, " expiry: ", TimeToStr(expiry) );
      }
    }
  }
}


void _MoveStopToBE(int ticket)
{
  if (OrderSelect(ticket, SELECT_BY_TICKET))
  {
    if (OrderType() == OP_BUY || OrderType() == OP_BUYLIMIT || OrderType() == OP_BUYSTOP)
      _MoveStop(ticket, OrderOpenPrice() + PipsToPrice(LockInPipsAtBE));
    else    
      _MoveStop(ticket, OrderOpenPrice() - PipsToPrice(LockInPipsAtBE));
  }
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
      if (OrderStopLoss() != 0  &&  OrderType() == OP_BUY)
      {
        if (price < OrderStopLoss())
          return (true);
      }
      else if (OrderStopLoss() != 0  &&  OrderType() == OP_SELL)
      {
        if (price > OrderStopLoss())
          return (true);
      }   
    
      double diff = MathAbs(OrderStopLoss() - price);
      double diffPoints = diff / Point;
      
      if (diffPoints < MINIMUM_STOP_MOVE_POINTS)
        return (true);
         
      bool ok = OrderModify(ticket, OrderOpenPrice(), price, OrderTakeProfit(), 0);
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


void _FindAllRelatedTickets()
{
  BuyTicket = _FindOldestOpenMagicTicketLong(Magic);
  SellTicket = _FindOldestOpenMagicTicketShort(Magic);
}


int _FindOldestOpenMagicTicketLong(int magic)
{
  int result = 0;
  int resultTime = TimeCurrent()+1;  
  
  for (int i=0; i<OrdersTotal(); i++)
    if (OrderSelect(i, SELECT_BY_POS))
    {
      if (OrderType() == OP_BUY  ||  OrderType() == OP_BUYLIMIT  ||  OrderType() == OP_BUYSTOP)
      {
        if (OrderCloseTime() == 0  &&  OrderMagicNumber() == magic)
        {
          if (OrderOpenTime() < resultTime)
          {
            result = OrderTicket();
            resultTime = OrderOpenTime();
          }
        }
      }
    }
  return (result);
}


int _FindOldestOpenMagicTicketShort(int magic)
{
  int result = 0;
  int resultTime = TimeCurrent()+1;  
  
  for (int i=0; i<OrdersTotal(); i++)
    if (OrderSelect(i, SELECT_BY_POS))
    {
      if (OrderType() == OP_SELL  ||  OrderType() == OP_SELLLIMIT  ||  OrderType() == OP_SELLSTOP)
      {
        if (OrderCloseTime() == 0  &&  OrderMagicNumber() == magic)
        {
          if (OrderOpenTime() < resultTime)
          {
            result = OrderTicket();
            resultTime = OrderOpenTime();
          }
        }
      }
    }
  return (result);
}


bool _AreOrdersPlaced()
{
  return (BuyTicket != 0  ||  SellTicket != 0);
}


bool _IsActive()
{
  return (Active  &&  AccountEquity() > StopTradingBalance$);
}


bool _IsIdle()
{
  return (!_AreOrdersPlaced()  &&  !inLondonOpen  && !inEntryZone); // && !_InTrade());
}


bool _IsTicketOpen(int ticket)
{
  if (OrderSelect(ticket, SELECT_BY_TICKET))
    return (OrderCloseTime() == 0);
  else
    return (false);
}


bool _IsTicketInMarket(int ticket)
{
  if (OrderSelect(ticket, SELECT_BY_TICKET))
    return (OrderCloseTime() == 0  &&  (OrderType()==OP_BUY || OrderType()==OP_SELL));
  else
    return (false);
}


#define OneDay  86400   // minutes in a day

datetime lastUpdate = 0;

void _UpdateObjects()
{
  if (IsTesting())
    return;
    
  if (TimeCurrent() > (lastUpdate + 60))
  {
    lastUpdate = TimeCurrent();

    int sessionLength = 60*60*8;

    datetime london  = _GetPreviousLondonOpen();
    datetime newyork = _GetPreviousNewYorkOpen();
    for (int i=0;  i<2; i++)
    {
      SetRectangle("londonOpen"+i, london, WindowPriceMax()*2, london+sessionLength, 0, London_Clr);
      SetRectangle("newYorkOpen"+i, newyork, WindowPriceMax()*2, newyork+sessionLength, 0, NewYork_Clr);
    
      london += OneDay;
      newyork += OneDay;
    }
  }
}


datetime _GetCurrentLondonOpen()
{
  datetime dt = TimeCurrent();
  return (StrToTime(""+TimeYear(dt)+"."+TimeMonth(dt)+"."+TimeDay(dt)+" "+LondonSession_Hour+":"+LondonSession_Min));
}


datetime _GetPreviousLondonOpen()
{
  datetime dt = TimeCurrent() - OneDay;
    
  int Y = TimeYear(dt);
  int M = TimeMonth(dt);
  int D = TimeDay(dt);
  
  return (StrToTime(""+Y+"."+M+"."+D+" "+LondonSession_Hour+":"+LondonSession_Min));
}


datetime _GetPreviousNewYorkOpen()
{
  datetime dt = TimeCurrent() - OneDay;

  int Y = TimeYear(dt);
  int M = TimeMonth(dt);
  int D = TimeDay(dt);
  
  return (StrToTime(""+Y+"."+M+"."+D+" "+NewYorkSession_Hour+":"+NewYorkSession_Min));
} 


int _GetExpiryTime()
{
  return (TimeCurrent() + OrderExpiry_Mins);
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


void SetRectangle(string name, double time1, double price1, double time2, double price2, color clr)
{
  int windowNumber = 0;
  
  if (ObjectFind(pfx+name) <0)
    ObjectCreate(pfx+name, OBJ_RECTANGLE, windowNumber, time1, price1, time2, price2);
    
  ObjectSet(pfx+name, OBJPROP_COLOR, clr);
  ObjectSet(pfx+name, OBJPROP_PRICE1, price1);
  ObjectSet(pfx+name, OBJPROP_TIME1, time1);  
  ObjectSet(pfx+name, OBJPROP_PRICE2, price2);
  ObjectSet(pfx+name, OBJPROP_TIME2, time2);
  ObjectSet(pfx+name, OBJPROP_BACK, true);
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
    return ("($" + DoubleToStr(MathAbs(amount), digits) + ")");
  else
    return ("$" + DoubleToStr(amount, digits));
}


double GetLotsForRisk(double balance, double riskPercent, double entryPrice, double stopPrice)
{
  double priceDifference = MathAbs(entryPrice - stopPrice);
  double risk$ = balance * (riskPercent / 100.0);
    
  double riskPoints = priceDifference/Point;
  
  double lotSize = (risk$ / riskPoints) / (MarketInfo(Symbol(), MODE_TICKVALUE));

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


double PriceToPips(double price)
{
  return (price / Point / 10);
}


int RandomRange(int range)
{
  return ((MathRand()/32767.0)*range);
}


void SetArrow(string name, double time, double price, color clr, int symbol)
{
  int windowNumber = 0; // WindowFind(GetIndicatorShortName());
  if (ObjectFind(pfx+name) < 0)
    ObjectCreate(pfx+name, OBJ_ARROW, windowNumber, time, price);

  ObjectSet(pfx+name, OBJPROP_COLOR, clr);
  ObjectSet(pfx+name, OBJPROP_ARROWCODE, symbol);
  ObjectSet(pfx+name, OBJPROP_PRICE1, price);
  ObjectSet(pfx+name, OBJPROP_TIME1, time);
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
    
    ObjectSet(pfx+name, OBJPROP_COLOR, clr);
    ObjectSet(pfx+name, OBJPROP_STYLE, style);
    ObjectSet(pfx+name, OBJPROP_WIDTH, lineWidth);
  }
  else
  {
    if (lineType == OBJ_VLINE)
      ObjectSet(pfx+name, OBJPROP_TIME1, value);
    else    
      ObjectSet(pfx+name, OBJPROP_PRICE1, value);
    ObjectSet(pfx+name, OBJPROP_COLOR, clr);
  }
}


void SetLine(string name, double value, color clr, int style, int lineWidth=1)
{
  _SetLine(name, value, clr, style, lineWidth, OBJ_HLINE);
}


void SetVertLine(string name, double time, color clr, int style, int lineWidth=1)
{
  _SetLine(name, time, clr, style, lineWidth, OBJ_VLINE);
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
}


void DeleteAllObjects()
{
  DeleteAllObjectsWithPrefix(pfx);
}


void DeleteObject(string name)
{
  ObjectDelete(pfx+name);
}


bool IsBEApplied(int ticket)
{ 
  if (OrderSelect(ticket, SELECT_BY_TICKET))
  {
    if (OrderType() == OP_BUY)
    {
      if (NormalizeDouble(OrderStopLoss(), Digits) < NormalizeDouble(OrderOpenPrice(), Digits))
        return (false);
    }
    else
    {
      if (NormalizeDouble(OrderStopLoss(), Digits) > NormalizeDouble(OrderOpenPrice(), Digits))
        return (false);
    }
  }
  return (true);
}


bool IsTicketClosed(int ticket)
{
  if (OrderSelect(ticket, SELECT_BY_TICKET))
    return (OrderCloseTime() != 0);
  else
    return (false);
}

