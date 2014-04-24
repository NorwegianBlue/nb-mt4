//+------------------------------------------------------------------+
//|                                            NB - 60mm scalper.mq4 |
//|                    Copyright © 2012, NorwegianBlue & 60minuteman |
//|           http://sites.google.com/site/norwegianbluesmt4junkyard |
//+------------------------------------------------------------------+

//1. price above below 50sma long short respectively
//2. have to have 4 candles from the recent high retrace
//3. set up candle closes in trend dirction
//4. enter if next candle trades higher
//5. 1/1 move to b.e
//6. 2/1 take profit


#property copyright "Copyright © 2012, NorwegianBlue & 60minuteman"
#property link      "http://sites.google.com/site/norwegianbluesmt4junkyard"

#include <stderror.mqh>
#include <stdlib.mqh>
#include <ptorders.mqh>
#include <winuser32.mqh>
#include <nbpointfactor.mqh>


int Magic = 0;
double POINT_FACTOR = 10.0;

int SecondsPerDay = 86400;
int SecondsPerHour = 3600;

#define _VERSION_  1

//---- input parameters
extern int _VERSION_1 = _VERSION_;
extern bool Active = true;
double StopTrading$ = 100;
extern double NominalBalanceForRisk$ = 5000;

extern bool OnlyTakeOneTrade = false;
extern int DisableAfterLoss_Hours = 0;

extern int  HourStart = 0;      // It is valid to start at hour 22 and end at hour 5.  
extern int  HourStop =  0;



extern double MissedByThatMuch_Active_Pips = 0;
extern double MissedByThatMuch_Active_Factor = 0.90;
extern double MissedByThatMuch_SL_Factor = 0.80;

extern double MoveStopToBE_Factor = 0.50;
extern double LockInAtBE_Pips = 2.0;

extern double Fixed_Lots = 0;
extern double Risk_Pct = 2.0;
extern double Max_Lots = 1.0;

extern double EnterOnRetrace_Factor = 0.50;
extern double EntryLag_Pips = 1.0;
extern bool   IncludeSpreadInLag = true;
bool   EngulfingCanStraddleSMA = true;
extern double TP_Factor = 2;

string _2 = "__ Display (0=TL, 1=TR, 2=BL, 3=BR) __";
//extern int    DisplayCorner  = 2;
extern bool   ShowComment = true;
extern bool   ShowNextBarIn = true;
string CurrencySymbol = "$";
bool   ShowCurrency   = true;
int    LineSpacing    = 13;
//extern color  BackgroundColor = Black;


#define CORNER_TOPLEFT 0
#define CORNER_TOPRIGHT 1
#define CORNER_BOTTOMLEFT 2
#define CORNER_BOTTOMRIGHT 3


string pfx="nb60s";

#define fontName     "Calibri"
#define boldFontName "Arial Black"
#define fontSize     8


int Ticket;
bool TradeLong;
bool IsTicketOpen;


//+------------------------------------------------------------------+
//| EA meta info

string GetIndicatorShortName()
{
  return("NB - 60mm Scalper " + Symbol());
}

string GetOrderComment(int magic)
{
  return("NB60S." + PeriodToStr(Period()));
}

string _Suffix()
{
  return ("");
}

int CalculateMagicHash()
{
  string s = "" + Period() + GetIndicatorShortName();
  
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

  POINT_FACTOR = GuessPointFactor();

  Magic = CalculateMagicHash();
  
  _FindOpenTickets();

  return (0);
}


//+------------------------------------------------------------------+
//| expert deinitialization function                                 |
//+------------------------------------------------------------------+
int deinit()
{
  DeleteAllObjectsWithPrefix(pfx);
  return(0);
}



//+------------------------------------------------------------------+
//| expert start function                                            |
//+------------------------------------------------------------------+
int LastFlash;
bool LastToggle;

void _UpdateFlashToggle()
{
  if (GetTickCount() > LastFlash + 250)  // 250ms
  {
    LastToggle = !LastToggle;
    LastFlash = GetTickCount();
  }
}


int start()
{
  _UpdateFlashToggle();

  if (Bars < 50)
    return(0);
    
  if (Magic == 0)
    Magic = CalculateMagicHash();
  
  if (_IsInTrade())
  {
    _DoTradeManagement();
  }
  
  if (!_IsInTrade())
  {
    string reason;
    int entry = _DoCheckForEntry(reason);
    if (entry >= 0)
      _DoEntry(entry);
  }

  if (!IsTesting() || IsVisualMode())
  {
    _UpdateComment();
    _UpdateObjects();
  }
  
  return(0);
}


double _GetProfitAsTPFactor()
{
  if (OrderSelect(Ticket, SELECT_BY_TICKET)  &&  OrderTakeProfit() > 0)
  {
    if (OrderType() == OP_BUY)
      return ((Bid - OrderOpenPrice()) / (OrderTakeProfit() - OrderOpenPrice()));
    else if (OrderType() == OP_SELL)
      return ((OrderOpenPrice() - Ask) / (OrderOpenPrice() - OrderTakeProfit()));
    else
      return (-1.0);
  }
  else
    return (-1.0);
}


void _UpdateComment()
{
  if (!ShowComment)
    return;
    
  string s = "V" + _VERSION_ + "  ";
  if (Ticket != 0)
  {
    s = s + "Profit Factor: " + DoubleToStr(_GetProfitAsTPFactor(), 2) + "  ";
    s = s + "Risk: " + DoubleToStr(_GetProfitAtStop(), Digits);
  }
  
  if (EnterOnRetrace_Factor > 0)
    s = s + "  Retrace Mode: " + DoubleToStr(EnterOnRetrace_Factor, 2);
  else
    s = s + "  Breakout Mode: " + _GetBriefPipsDisplay(EntryLag_Pips);

  //s = s + "  PPH(0,1)=" + DoubleToStr(_SMA_PipsPerHour(0,1), 5);
  //s = s + "  PPH(0,3)=" + DoubleToStr(_SMA_PipsPerHour(0,3), 5);
  //s = s + "  PPH(0,5)=" + DoubleToStr(_SMA_PipsPerHour(0,5), 5);

  Comment(s);
}


int STATUS_X = 5;
int STATUS_Y = 22;

void _UpdateObjects()
{
  if (_IsInTrade())
  {
    if (TradeLong)
      SetLabel("lblInTrade", STATUS_X,STATUS_Y, "LONG OPEN", White);
    else
      SetLabel("lblInTrade", STATUS_X,STATUS_Y, "SHORT OPEN", White);

    _UpdateTradeStats();
  }
  else
  {
    string reason = "";
    _DoCheckForEntry(reason);
    SetLabel("lblInTrade", STATUS_X,STATUS_Y, reason, White);
  }

  _DrawBackground(CORNER_TOPLEFT,  STATUS_X-2, STATUS_Y, Black, "gggggggggggg");


  if (_IsInTrade() || _IsTradeComplete())
  {    
    _UpdateInfoPanel();
    _UpdateBackground();
  }
  else
  {
    DeleteAllObjectsWithPrefix(pfx+"lInfo");
    DeleteAllObjectsWithPrefix(pfx+"lBackground");
  }
  
  _UpdateNextBarIn();
}


#define BARREMAINING_X 5
#define BARREMAINING_Y 1
#define BARREMAINING_CORNER 3

void _UpdateNextBarIn()
{
  if (ShowNextBarIn)
  {
    color clr;
    int periodSeconds = Period() * 60;
    int candleStart = Time[0];
    
    int remainingSeconds = (candleStart + periodSeconds) - TimeCurrent();
    if (remainingSeconds < 30)
    {
      if (LastToggle)
        clr = Red;
      else
        clr = White;
    }
    else
      clr = Gray;
    
    int remainingMinutes = remainingSeconds / 60;
    int remainingHours = remainingMinutes / 60;
    remainingSeconds = remainingSeconds - (remainingMinutes * 60);
    remainingMinutes = remainingMinutes - (remainingHours * 60);
    
    string s = "Next bar ";
    if (remainingHours > 0)
      s = s + remainingHours + "h ";
    s = s + remainingMinutes + "m " + remainingSeconds + "s";
    
    SetLabel("nextBarIn", BARREMAINING_X, BARREMAINING_Y, s, clr);
    ObjectSet(pfx+"nextBarIn", OBJPROP_CORNER, BARREMAINING_CORNER);
  }
  else
    DeleteObject("nextBarIn");
}


void _DrawBackground(int corner, int x, int y, color clr, string bkg = "ggggggggg")
{
  y = y - 2;
  SetLabel("bkga"+y, 5, y, bkg, clr, 0, "Webdings");
  ObjectSet(pfx+"bkga"+y, OBJPROP_CORNER, corner);
}


bool _FindOpenTickets()
{
  Ticket = 0;
  IsTicketOpen = false;
  
  for (int i=0; i<OrdersTotal(); i++)
    if (OrderSelect(i, SELECT_BY_POS))
    {
      if (OrderCloseTime() == 0  &&  OrderMagicNumber() == Magic)
      {
        Ticket = OrderTicket();
        TradeLong = (OrderType() == OP_BUY || OrderType() == OP_BUYLIMIT || OrderType() == OP_BUYSTOP);
        IsTicketOpen = true;
        break;
      }
    }
    
  if (!IsTicketOpen)
  {
    // Find the ticket in the history
    for (i=0; i<OrdersHistoryTotal(); i++)
      if (OrderSelect(i, SELECT_BY_POS, MODE_HISTORY) && OrderCloseTime()!=0 && OrderMagicNumber() == Magic && (OrderType() == OP_BUY || OrderType() == OP_SELL))
      {
        Ticket = OrderTicket();
        TradeLong = (OrderType() == OP_BUY || OrderType() == OP_BUYLIMIT || OrderType() == OP_BUYSTOP);
        IsTicketOpen = false;
        break;
      }
  }
    
  _ResetStats();   
  return (Ticket != 0);
}


void _UpdateInfoPanel()
{
}


void _UpdateBackground()
{
}


void _UpdateTradeStats()
{
}


void _ResetStats()
{
}


double _GetSpread()
{
  return (Ask-Bid);
}


double _MA(int bar=0)
{
  return (iMA(NULL, 0, 50, 0, MODE_SMA, PRICE_CLOSE, bar));
}


bool _GoLong(int bar=0)
{
  return (Bid > _MA(bar));
}


bool _GoShort(int bar=0)
{
  return (Bid < _MA(bar));
}


bool _LongAllowed(int bar=0)
{
  return (High[bar] > _MA(bar));
}


bool _ShortAllowed(int bar=0)
{
  return (Low[bar] < _MA(bar));
}


int _BarDirection(int bar)
{
  double open = Open[bar];
  double close = Close[bar];
  
  if (open < close)
    return (+1);
  else if (open > close)
    return (-1);
  else
    return (0);
}


bool _IsEngulfing(int bar=0)
{
  int direction = _BarDirection(bar+1);
  
  if (direction >= 0  &&  Close[bar] <= Open[bar+1])
    return (true);
  else if (direction <= 0  &&  Close[bar] >= Open[bar+1])
    return (true);
  else
    return (false);
}

int MinimumRetraceBars = 3;

bool _IsSignal(int bar=0)
{
  // if we are above sma50 and the prior candle was bull then
  // if there are at least 4 down candles before the prior onethen
  //  this is a signal candle
  int i;
  
  if (Bid < _MA(bar)) // Looking for shorts
  {
    if (_BarDirection(bar) < 0)  // prior candle was short
    {
      for (i=0; i<MinimumRetraceBars; i++)
        if (_BarDirection(bar+i+1) <= 0)
          return (false);    
    
      return (true);
    }
  }
  else                // Looking for longs
  {
    if (_BarDirection(bar) > 0)  // prior candle was long
    {
      for (i=0; i<MinimumRetraceBars; i++)
        if (_BarDirection(bar+i+1) >= 0)
          return (false);

      return (true);
    }
  }
  return (false);
}



double _PriceLag()
{
  double result = PipsToPrice(EntryLag_Pips);
  if (IncludeSpreadInLag)
    result = result + (Ask-Bid);
}


double _SMA_PipsPerHour(int firstBar,  int lastBar)
{
  double firstMA = _MA(firstBar);
  double secondMA = _MA(lastBar);
  double hours = (Time[firstBar]  - Time[lastBar]) / (60*60); // 60*60 = seconds in an hour
  
  return (((firstMA - secondMA) / hours) / Point / POINT_FACTOR);
}



datetime Debug_LastPauseTime = 0; 
bool Debug_NoMorePause = false;


int _DoCheckForEntry(string& reason)
{
  int result = -1;
  
  if (!Active)
  {
    reason = "NOT ACTIVE";
    return (-1);
  }
  
  string timeLeft;
  if (!_IsTimeAllowed(timeLeft))
  {
    reason = "TIMEOUT " + timeLeft;
    return (-1);
  }
  
  if (IsVisualMode() && !Debug_NoMorePause)
  {
    if (_IsSignal(1) && Time[0] > Debug_LastPauseTime)
    {
      WindowRedraw();
      Debug_LastPauseTime = Time[0];
      if (MessageBoxA(0, "Signal detected " + TimeToStr(Time[0]) + "\n\nPause at next?", "EA Pause", MB_YESNO + MB_TOPMOST) == IDNO)
        Debug_NoMorePause = true;
    }
  }
  
  if (_IsSignal())
  {
    reason = "ENTRY NEXT BAR";
    return (-1);
  }
  
  if (_IsSignal(1))
  {
    if (IsVisualMode() && !Debug_NoMorePause && Time[0] > Debug_LastPauseTime)
    {
      WindowRedraw();
      Debug_LastPauseTime = Time[0];
      if (MessageBoxA(0, "Signal last candle, entry this candle.\n\nPause at next?", "EA Pause", MB_YESNO + MB_TOPMOST) == IDNO)
        Debug_NoMorePause = true;
    }

    if (_LongAllowed(1))
    {
      if (Bid > High[1] + _GetSpread())
      {
        reason = "GO LONG NOW";
        return (OP_BUY);
      }
      else
      {
        reason = "Waiting for LONG this candle";
        return (-1);
      }
    }
    
    if (_ShortAllowed(1))
    {
      if (Bid < Low[1] - _GetSpread())
      {
        reason = "GO SHORT NOW";
        return (OP_SELL);
      }
      else
      {
        reason = "Waiting for SHORT this candle";
        return (-1);
      }
    }
  }
  
  if (result >= 0)
  {
    if (Ticket != 0  &&  !IsTicketOpen) // we have a closed trade
    {
      if (OrderSelect(Ticket, SELECT_BY_TICKET, MODE_HISTORY))
      {
        if (OrderCloseTime() + (Time[0] - Time[1]) > Time[0])
        {
          reason = "Trade closed this candle, wait for next";
          return (-1);
        }
      }
    }
    return (result);
  }
  else
  {
    reason = "WAITING for Signal";
    return (-1);
  }
}


int _DoCheckForEntry_engulf(string& reason)
{
  int result = -1;
  
  if (!Active)
  {
    reason = "NOT ACTIVE";
    return (-1);
  }
  
  string timeLeft;
  if (!_IsTimeAllowed(timeLeft))
  {
    reason = "TIMEOUT " + timeLeft;
    return (-1);
  }
  
  if (IsVisualMode() && !Debug_NoMorePause)
  {
    if (_IsEngulfing() && Time[0] > Debug_LastPauseTime)
    {
      Debug_LastPauseTime = Time[0];
      if (MessageBoxA(0, "Engulfing detected " + TimeToStr(Time[0]) + "\n\nPause at next?", "EA Pause", MB_YESNO + MB_TOPMOST) == IDNO)
        Debug_NoMorePause = true;
    }
  }

  if (_IsEngulfing())
  {
    if (_LongAllowed(0)  &&  _BarDirection(0) < 0)
      reason = "No short engulfing above SMA ²";
    else if (_ShortAllowed(0)  &&  _BarDirection(0) > 0)
      reason = "No long engulfing bdlow SMA ²";
    else
      reason = "ENTRY NEXT BAR";
    return(-1);
  }
  
  int bar1Dir = _BarDirection(1);
  if (_IsEngulfing(1))
  {
    if (IsVisualMode() && !Debug_NoMorePause && Time[0] > Debug_LastPauseTime)
    {
      Debug_LastPauseTime = Time[0];
      if (MessageBoxA(0, "Engulfing last candle, entry this candle.\n\nPause at next?", "EA Pause", MB_YESNO + MB_TOPMOST) == IDNO)
        Debug_NoMorePause = true;
    }
    
    if (_LongAllowed(1) && _ShortAllowed(1) &&!EngulfingCanStraddleSMA)
    {
      reason = "EngulfingCanStraddleSMA = false";
      return (-1);
    }

    if (_LongAllowed(1))
    {
      if (bar1Dir < 0)
      {
        reason = "No short engulfing above SMA";
        return (-1);
      }
      
      /*
      if (EnterOnRetrace_Factor > 0)
      {
        if (Bid < (Low[1] + (High[1] - Low[1])*EnterOnRetrace_Factor)
        {
          reason = "GO LONG NOW";
          result = OP_BUY;
        }
        else
        {
        }
      }
      else
        if (Bid > High[1] + _PriceLag())
        {
          reason = "GO LONG NOW";
          result = OP_BUY;
        }
      else 
      */
      if (Bid < Low[1] - _PriceLag())
      {
        reason = "No Short above SMA";
        return (-1);
      }
      else
      {
        reason = "Waiting for LONG this candle";
        return (-1);
      }
    }
    else if (_ShortAllowed(1))
    {
      if (bar1Dir > 0)
      {
        reason = "No long enuglfing below SMA";
        return (-1);
      }
        
      if (Bid > High[1] + _PriceLag())
      {
        reason = "No Long below SMA";
        return (-1);
      }
      else if (Bid < Low[1] - _PriceLag())
      {
        reason = "GO SHORT NOW";
        result = OP_SELL;
      }
      else
      {
        reason = "Waiting for SHORT this candle";
        return (-1);
      }
    }
  }
  
  if (result >= 0)
  {
    if (Ticket != 0  &&  !IsTicketOpen) // we have a closed trade
    {
      if (OrderSelect(Ticket, SELECT_BY_TICKET, MODE_HISTORY))
      {
        if (OrderCloseTime() + (Time[0] - Time[1]) > Time[0])
        {
          reason = "Trade closed this candle, wait for next";
          return (-1);
        }
      }
    }
    return (result);
  }
  else
  {
    reason = "WAITING for Engulfing";
    return (-1);
  }
}


double _GetLots(double riskPoints)
{
  if (Fixed_Lots == 0)
  {
    double risk$;
    if (NominalBalanceForRisk$ == 0)
      risk$ = AccountBalance();
    else
      risk$ = NominalBalanceForRisk$;
    risk$ = risk$ * (Risk_Pct/100.0);
    double lotSize = SafeDiv(risk$, riskPoints) / MarketInfo(Symbol(), MODE_TICKVALUE);
    lotSize = MathMin(lotSize, Max_Lots);
    return (MathMax(lotSize, 0.01));
  }
  else
    return (Fixed_Lots);
}


double _GetLots_old(int direction)
{
  if (Fixed_Lots == 0)
  {
    double risk$;
    if (NominalBalanceForRisk$ == 0)
      risk$ = AccountBalance();
    else
      risk$ = NominalBalanceForRisk$;
    risk$ = risk$ * (Risk_Pct/100.0);
    
    double riskPips;
  
    if (direction == OP_BUY)
      riskPips = (High[1] + _GetSpread() - _GetStop(direction))/Point/POINT_FACTOR;
    else
      riskPips = (_GetStop(direction) - Low[1] - _GetSpread())/Point/POINT_FACTOR;

    double lotSize = (SafeDiv(risk$, riskPips)) / ((MarketInfo(Symbol(), MODE_TICKVALUE)*POINT_FACTOR));
    //if (MaxLots > 0  &&  lotSize > MaxLots)
    //  lotSize = MaxLots;
      
    return (MathMax(lotSize, 0.01));
  }
  else
    return (Fixed_Lots);
}


double _GetStop(int direction)
{
  double result;
  if (direction == OP_BUY)
  {
    result = Low[0] - _GetSpread();
  }
  else
  {
    result = High[0] + _GetSpread();
  }
  return (result);
}


int _DoEntry(int direction)
{
  Ticket = 0;
  IsTicketOpen = 0;
  _ResetStats();

  //string symbol, int op, double lotsize, double price, double spread, double stoploss, double takeprofit,
  //string comment, int magic, datetime expiry=0, color clr=CLR_NONE)
  int dir;
  double price, tp_shortperiod, tp_longperiod, tp, sl, risk;
  if (direction == OP_BUY)
  {
    dir = +1;
    price = Ask;
    sl = Low[1] - _GetSpread();
    tp = price + (price - sl) * TP_Factor;
    risk = (price - sl) / Point;
  }
  else if (direction == OP_SELL)
  {
    dir = -1;
    price = Bid;
    sl = High[1] + _GetSpread();
    tp = price - (sl - price) * TP_Factor;
    risk = (sl - price) / Point;
  }
  else
    return (0);
    
  double lots = _GetLots(risk);
  Ticket = OrderReliableSend(Symbol(), direction, lots, price, Ask-Bid, sl, tp, GetOrderComment(Magic), Magic);
  
  IsTicketOpen = (Ticket != 0);
  TradeLong = (direction == OP_BUY);
}


double _GetProfitAtStop()
{
  double profitAtStop = 0.0;
  
  if (Ticket != 0  &&  OrderSelect(Ticket, SELECT_BY_TICKET)  &&  OrderStopLoss() > 0)
  {
    if (TradeLong)
      profitAtStop += (OrderStopLoss() - OrderOpenPrice());
    else
      profitAtStop += (OrderOpenPrice() - OrderStopLoss());
  }    

  return (profitAtStop);
}


void _DoTradeManagement()
{
  if (Ticket == 0)
    return;
    
  if (IsTicketOpen && !_IsTicketOpen(Ticket))
  {
    // Ticket has closed
    IsTicketOpen = false;
    return;
  } 
  

  if (MoveStopToBE_Factor > 0  &&  _GetProfitAtStop() < 0)
  {
    double profitFactor = _GetProfitAsTPFactor();
    if (profitFactor >= MoveStopToBE_Factor)
      _MoveStopToBE(Ticket);
  }
   
  // -- Check each open ticket for MissedByThatMuch effect
  if (IsTicketOpen)
    _DoMissedByThatMuch(Ticket);
}


void _DoMissedByThatMuch(int ticket)
{
  double mbtmActivatePrice = 0.0;
  
  if (OrderSelect(ticket, SELECT_BY_TICKET) && OrderTakeProfit() > 0.0)
  {
    if (MissedByThatMuch_Active_Pips > 0)
    {
      if (OrderType() == OP_BUY) // closing a buy, is a sell, so use Bid
      {
        mbtmActivatePrice = OrderTakeProfit() - PipsToPrice(MissedByThatMuch_Active_Pips);
        if (Bid > mbtmActivatePrice)
          _MoveStop(ticket, OrderOpenPrice() + (Bid-OrderOpenPrice())*MissedByThatMuch_SL_Factor);
      }
      else if (OrderType() == OP_SELL)
      {
        mbtmActivatePrice = OrderTakeProfit() + PipsToPrice(MissedByThatMuch_Active_Pips);
        if (Ask < mbtmActivatePrice)
          _MoveStop(ticket, OrderOpenPrice() - (OrderOpenPrice() - Ask)*MissedByThatMuch_SL_Factor);
      }
    }
    else if (MissedByThatMuch_Active_Factor > 0)
    {
      if (OrderType() == OP_BUY)
      {
        mbtmActivatePrice = OrderOpenPrice() + (OrderTakeProfit() - OrderOpenPrice())*MissedByThatMuch_Active_Factor;
        if (Bid > mbtmActivatePrice)
          _MoveStop(ticket, OrderOpenPrice() + (Bid-OrderOpenPrice())*MissedByThatMuch_SL_Factor);
      }
      else if (OrderType() == OP_SELL)
      {
        mbtmActivatePrice = OrderOpenPrice() - (OrderOpenPrice() - OrderTakeProfit())*MissedByThatMuch_Active_Factor;
        if (Ask < mbtmActivatePrice)
          _MoveStop(ticket, OrderOpenPrice() - (OrderOpenPrice() - Ask)*MissedByThatMuch_SL_Factor);
      }
    }
  }
}


bool _IsTimeAllowed(string& timeRemaining)
{
  double hstart = HourStart;
  double hstop = HourStop;
  bool result;
  
  datetime startOfToday = TimeCurrent() - (TimeCurrent() % SecondsPerDay);
  datetime timeStart = startOfToday + (hstart * SecondsPerHour);
  
  if (hstart == hstop)
    result = true;
  else if (hstart < hstop)  // e.g.  from 2 - 5 means start at 2 stop at 5
    result = (Hour() >= hstart  &&  Hour() < hstop);
  else  // e.g. from 22 to 4
    result = (Hour() >= hstart  ||  Hour() < hstop);

  if (!result)
    timeRemaining = _GetAge(TimeCurrent(), timeStart);
  return (result);
}


bool _IsInTrade()
{
  return ((Ticket != 0)  &&  (IsTicketOpen));
}


// -- We had a trade, but it's over.  Use to display close info
bool _IsTradeComplete()
{
  return ((Ticket != 0)  &&  !IsTicketOpen);
}


bool _IsTicketOpen(int ticket)
{
  if (OrderSelect(ticket, SELECT_BY_TICKET))
    return (OrderCloseTime() == 0);
  else
    return (false);
}


bool _IsTradeLong()
{
  return (TradeLong);
}


double _GetTicketProfit$(int ticket)
{
  if (OrderSelect(ticket, SELECT_BY_TICKET))
    return (OrderProfit() + OrderSwap());
  else if (OrderSelect(ticket, SELECT_BY_TICKET, MODE_HISTORY))
    return (OrderProfit() + OrderSwap());
  else
    return (0.0);
}


double _GetTotalProfit$()
{
  return (_GetTicketProfit$(Ticket));
}


double _GetTotalProfitPips()
{
  return (_GetTicketProfitPips(Ticket));
}


double _GetTicketProfitPips(int ticket)
{
  if (!OrderSelect(ticket, SELECT_BY_TICKET))
    if (!OrderSelect(ticket, SELECT_BY_TICKET, MODE_HISTORY))
      return (0.0);
   
  if (OrderCloseTime() == 0)
  {
    if (OrderType() == OP_BUY)
      return ((Bid - OrderOpenPrice())/MarketInfo(OrderSymbol(), MODE_POINT)/POINT_FACTOR);
    else if (OrderType() == OP_SELL)
      return ((OrderOpenPrice() - Ask)/MarketInfo(OrderSymbol(), MODE_POINT)/POINT_FACTOR);
    else
      return (0.0);
  }
  else
  {
    if (OrderType() == OP_BUY)
      return ((OrderClosePrice() - OrderOpenPrice())/MarketInfo(OrderSymbol(), MODE_POINT)/POINT_FACTOR);
    else if (OrderType() == OP_SELL)
      return ((OrderOpenPrice() - OrderClosePrice())/MarketInfo(OrderSymbol(), MODE_POINT)/POINT_FACTOR);
    else
      return (0.0);
  } 
}


void _CloseAllTickets()
{
  if (IsTicketOpen)
  {
    OrderReliableClose(Ticket);
    IsTicketOpen = false;
  }
}


void _MoveStopToBE(int ticket)
{
  if (OrderSelect(ticket, SELECT_BY_TICKET))
  {
    if (OrderType() == OP_BUY)
      _MoveStop(ticket, OrderOpenPrice() + LockInAtBE_Pips*Point*POINT_FACTOR);
    else
      _MoveStop(ticket, OrderOpenPrice() - LockInAtBE_Pips*Point*POINT_FACTOR);
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


string _GetBriefPipsDisplay(double pips)
{
  int digits;
  if (pips < -10  ||  pips > 10)
    digits = 0;
  else
    digits = 1;
  
  if (pips < 0)
    return ("(" + DoubleToStr(MathAbs(pips), digits) + ")");
  else
    return (DoubleToStr(pips, digits));
}


string _GetBriefDollarDisplay(double amount, bool exact=false)
{
  int digits = 2;
  if (!exact)
  {
    if (amount < -10  ||  amount > 10)
      digits = 0;
    else
      digits = 2;
  }

  if (amount < 0)
    return ("(" + CurrencySymbol + DoubleToStr(MathAbs(amount), digits) + ")");
  else
    return (CurrencySymbol + DoubleToStr(amount, digits));
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


double PipsToPrice(double pips)
{
  return (pips*POINT_FACTOR * Point);
}


double PointsToPrice(double points)
{
  return (points * Point);
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
    return ("(" + DoubleToStr(MathAbs(pips), digits) + "p)");
  else
    return (DoubleToStr(pips, digits) + "p");
}


string StringLower(string str)
{
  string outstr = "";
  string lower  = "abcdefghijklmnopqrstuvwxyz";
  string upper  = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
  for(int i=0; i<StringLen(str); i++)
  {
    int t1 = StringFind(upper,StringSubstr(str,i,1),0);
    if (t1 >=0)  
      outstr = outstr + StringSubstr(lower,t1,1);
    else
      outstr = outstr + StringSubstr(str,i,1);
  }
  return(outstr);
}



#define FIVE_DIGIT 10
#define FOUR_DIGIT 1

int GuessPointFactor()
{
  string lsym = StringLower(Symbol());
  
  if (StringFind(lsym,"xau",0) >= 0)
  {
    if (Digits >= 2)
      return (FIVE_DIGIT);
    else
      return (FOUR_DIGIT);
  }
  else if (StringFind(lsym,"xag",0) >= 0)
  {
    if (Digits >= 3)
      return (FIVE_DIGIT);
    else
      return (FOUR_DIGIT);
  }
  else if (StringFind(lsym,"jpy",0) >= 0)
  {
    if (Digits >= 3)
      return (FIVE_DIGIT);
    else
      return (FOUR_DIGIT);
  }
  else
  {
    if (Digits >= 5)
      return (FIVE_DIGIT);
    else
      return (FOUR_DIGIT);
  }
}


string _GetAge(datetime startTime, datetime endTime)
{
  string s;
  int elapsedSeconds;
  elapsedSeconds = endTime - startTime;
  int elapsedMinutes = elapsedSeconds / 60;
  int elapsedHours   = elapsedMinutes / 60;
  int elapsedDays    = elapsedHours / 24;

  elapsedHours = elapsedHours % 24;
  elapsedMinutes = elapsedMinutes % 60;
  elapsedSeconds = elapsedSeconds % 60;

  if (elapsedDays > 0)
    s = elapsedDays + "d" + elapsedHours + "h";
  else if (elapsedHours > 0)
    s = elapsedHours + "h" + elapsedMinutes + "m";
  else
    s = elapsedMinutes + "m" + elapsedSeconds + "s";
  return (s);
}


double SafeDiv(double num, double div)
{
  if (div == 0)
    return (0.0);
  else
    return (num/div);
}

