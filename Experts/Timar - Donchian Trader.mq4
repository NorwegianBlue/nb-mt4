//+------------------------------------------------------------------+
//|                                         NB - Donchian Trader.mq4 |
//|                             Copyright © 2011-2012, NorwegianBlue |
//|                               http://www.timarinvestments.com.au |
/*
  Version next TBA
    DT_MaxTotalRisk         = 0 means no global maximum risk
    DT_MaxTotalLots         = 0 means no global maximum lots
    DT_MaxLosses            If >0, when DT_Losses reaches DT_MaxLosses all EAs will become inactive.
    (DT_Losses)
    DT_NominalBalance

    Added Risk_Pct, NominalBalance
    Added DT_RiskPct and DT_NominalBalance

  Version 7
    Added RiskOffPerLoss_Factor
    Added RiskOnPerWin_Factor


  Version 6 tba
    Added DT_HourStart, DT_HourEnd global variable overrides.  Set to -ve value to disable
    Added countdown to TIMEOUT message
    Added profit target to info panel
    Added StopTrading$
    Added DisableAfterLoss_Hours
    Added TP1Price_Factor
    Changed MoveStopToBE_Factor default to 0.7
    High intensity color on info panel when MFE or MAE is made, now stays visible for a minimum of 2 seconds, not just 1 tick.

  Version 5 9/11/2011
    Added MoveStopToBEFactor   - When price reaches this factor of StopLoss, move stop to break even.
                                 0 deactivates.
                                 Override with DT_MoveStopToBEFactor global variable

  Version 4 7/11/2011
    Added global variable overrides
      DT_MaxTotalTickets      = 0 means no global maximum positions
    Moved status to left, added background color

  Version 3 2/11/2011
  Added global variable overrides
    DT_FixedLots            0 means no global fixed lots
    DT_Active               1=active  0=not active
                            While DT_Active = 0, no new trades will be taken.
                            Existing positions will be managed normally.

  Version 2  26/10/2011
  Added rule;
    If price gets within x% of target, set stop to y%

  Version 1  24/10/2011  
  Started
  
+--------------------------------------------------------------------+
  
  This EA provides part of Robert Carter's Donchian Channel strategy.


+--------------------------------------------------------------------+

  Rules

  When Donchian-4 high hits Donchian-24 high
    -
    
  When Donchian-4 low hits Donchain-24 low
    -
  
  Enter when price exceeds 20 period moving average.
  Set stop to 2xN
  Add extra lots at 1/2N, move stop to 2xN away from last lot entry.
  Max 4 lots
*/
//+------------------------------------------------------------------+

#property copyright "Copyright © 2011-2012, NorwegianBlue"
#property link      "http://sites.google.com/site/norwegianbluesmt4junkyard"

#include <stderror.mqh>
#include <stdlib.mqh>
#include <ptorders.mqh>

int Magic = 0;
double POINT_FACTOR = 10.0;

int SecondsPerDay = 86400;
int SecondsPerHour = 3600;


#define _VERSION_  7

//---- input parameters
extern int _VERSION_7 = _VERSION_;
extern bool Active = true;
extern double StopTrading$ = 1000;
//extern double NominalBalance$ = 1000;

extern bool OnlyTakeOneTrade = false;
extern int DisableAfterLoss_Hours = 8;
// TODO: extern bool OnlyTakeOneLoss = true;

extern int  HourStart = 6;      // It is valid to start at hour 22 and end at hour 5.  
extern int  HourStop = 16;

extern double TP1Price_Factor = 0.50;  // used instead of the DonchainPeriod_Short
extern int DonchianPeriod_Short = 4;
extern int DonchianPeriod_Long = 24;

extern double Spread_Pips = 0.0;   // use this for spread calculations

extern double OMGStop_Pips = 40.0;

extern double MissedByThatMuch_Active_Factor = 0.94;
extern double MissedByThatMuch_SL_Factor = 0.80;      // TODO: change this to "x% of the move, not x% of the TP"

extern double MoveStopToBE_Factor = 0.70;

extern double Fixed_Lots = 0.01;
extern double Risk_Pct = 2.0;

extern double LongTrailStart_Pips = 50; // After Short is closed, and Long is at BE, and Long is this much in profit
extern double LongTrailFactor = 0.5;    // ... set stop to profit pips * LongTrailFactor.

 int LimitCurrExposure_Count = 1;  // Looks at all open Donchian trades, and prevents more than this many exposures to a currency
                                         // E.g if EUR/USD is open, then USD/CHF can't be,  but GBP/CHF could
                                         // 0 to deactivate
                                         
extern double RiskOffPerLoss_Factor     = 0.5;   // half position size after each loss
extern double MinRiskOff_Factor         = 0.25;  // minimum 1/4 position
extern double RiskOnPerWin_Factor       = 0.5;   // 50% increase in position after each win
extern double MaxRiskOn_Factor          = 5.0;   // maximum 5x position
extern bool   ResetRiskOnSequenceOnLoss = true;                                       
extern bool   ResetRiskOnSequenceOnMax  = false;
//--
extern int InitWinSequence_Count = 0;


extern string _2 = "__ Display (0=TL, 1=TR, 2=BL, 3=BR) __";
//extern int    DisplayCorner  = 2;
extern string CurrencySymbol = "$";
extern bool   ShowCurrency   = true;
extern int    LineSpacing    = 13;
//extern color  BackgroundColor = Black;



#define CORNER_TOPLEFT 0
#define CORNER_TOPRIGHT 1
#define CORNER_BOTTOMLEFT 2
#define CORNER_BOTTOMRIGHT 3

//+------------------------------------------------------------------+
// Global vars
string GV_FixedLots = "DT_FixedLots";
string GV_Active = "DT_Active";
string GV_MaxTotalRiskFactor = "DT_MaxTotalRiskFactor";
string GV_MaxTotalLots = "DT_MaxTotalLots";
string GV_MaxTotalTickets = "DT_MaxTotalTickets";
string GV_MoveStopToBEFactor = "DT_MoveStopToBEFactor";
string GV_HourStart = "DT_HourStart";
string GV_HourStop = "DT_HourStop";

//+------------------------------------------------------------------+
string pfx="tmrcdc";

#define fontName     "Calibri"
#define boldFontName "Arial Black"
#define fontSize     8

int TicketShortPeriod;
int TicketLongPeriod;

bool IsTicketShortOpen;
bool IsTicketLongOpen;

bool TradeLong;

bool   SymbolParseOk;
string SymbolTop;
int    SymbolTopIndex;
string SymbolBottom;
int    SymbolBottomIndex;

int WinSequence_Count = 0;
bool WinSequence_Max = false;

//+------------------------------------------------------------------+
//| Key values


// Reduces risk after losses twice as fast as it increases risk after profits
/*
double _GetEffectiveBalance$()
{
  if (AccountBalance() >= NominalBalance$)
    return (NominalBalance$);
  else
    return (MathMax(0, NominalBalance$ - 2.0*(NominalBalance$ - AccountBalance())));
}
*/

/*
double _GetRisk$()
{
  return (_GetEffectiveBalance$() * (Risk_Pct/100.0));
}
*/


double _High(int period, int start=0)
{
  return (iHigh(NULL, 0, iHighest(NULL, 0, MODE_HIGH, period, start)));
}


double _Low(int period, int start=0)
{
  return (iLow(NULL, 0, iLowest(NULL, 0, MODE_LOW, period, start)));
}




//+------------------------------------------------------------------+
//| EA meta info

string GetIndicatorShortName()
{
  return("Timar - Donchian Trader " + Symbol());
}

string GetOrderComment(int magic)
{
  return("Donchian");
}

string _ShortSuffix()
{
  return (":" + DonchianPeriod_Short);
}

string _LongSuffix()
{
  return (":" + DonchianPeriod_Long);
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

bool IsTradeCommentOurs(string comment)
{
  return (StringSubstr(OrderComment(), 0, 9) == "Donchian:"); 
}

int CountTicketsAcrossAllPairs()
{
  int c=0;
  for (int i=0; i < OrdersTotal(); i++)
  {
    if (OrderSelect(i, SELECT_BY_POS))
    {
      if (IsTradeCommentOurs(OrderComment()))
        c++;
    }
  }
  return (c);
}



//+------------------------------------------------------------------+
//| Global Vars

bool _GVActive()
{
  if (!GlobalVariableCheck(GV_Active))
  {
    GlobalVariableSet(GV_Active, 1);
    return (true);
  }
  else
    return (GlobalVariableGet(GV_Active) != 0.0);
}


bool _GVFixedLots(double& globalFixedLots)
{
  if (GlobalVariableCheck(GV_FixedLots))
  {
    double value = GlobalVariableGet(GV_FixedLots);
    if (value == 0.0)
      return (false);
    else
    {
      globalFixedLots = value;
      return (true);
    }
  }
  else
  {
    GlobalVariableSet(GV_FixedLots, 0.0);
    return (false);
  }
}


int _GVMaxTotalTickets()
{
  if (!GlobalVariableCheck(GV_MaxTotalTickets))
    GlobalVariableSet(GV_MaxTotalTickets, 0);

  return (GlobalVariableGet(GV_MaxTotalTickets));
}


bool _GVMoveStopToBEFactor(double& moveStopToBEFactor)
{
  if (!GlobalVariableCheck(GV_MoveStopToBEFactor))
    GlobalVariableSet(GV_MoveStopToBEFactor, 0);
  double value = GlobalVariableGet(GV_MoveStopToBEFactor);
  if (value > 0)
  {
    moveStopToBEFactor = value;
    return (true);
  }
  else
    return (false);
}


int _GVHourStart()
{
  if (!GlobalVariableCheck(GV_HourStart))
    GlobalVariableSet(GV_HourStart, -1);
  double value = GlobalVariableGet(GV_HourStart);
  if (value >= 0)
    return (value);
  else
    return (HourStart);
}


int _GVHourStop()
{
  if (!GlobalVariableCheck(GV_HourStop))
    GlobalVariableSet(GV_HourStop, -1);
  double value = GlobalVariableGet(GV_HourStop);
  if (value >= 0)
    return (value);
  else
    return (HourStop);
}



//+------------------------------------------------------------------+
//| expert initialization function                                   |
//+------------------------------------------------------------------+
int init()
{
  WinSequence_Count = InitWinSequence_Count;
  
  if (!IsTesting())
    MathSrand(TimeLocal());

  POINT_FACTOR = GuessPointFactor();

  Magic = CalculateMagicHash();
  
  _FindOpenTickets();

  SymbolParseOk = _ParseSymbol(Symbol(), SymbolTop, SymbolBottom);
  SymbolTopIndex = _FindCurrIdx(SymbolTop);
  SymbolBottomIndex = _FindCurrIdx(SymbolBottom);  

  return(0);
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
int start()
{
  if (Magic == 0)
    Magic = CalculateMagicHash();
  
  // Probably only want to calculate exposure every second or so
  _CalculateExposure();
  
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
  
  if (!IsTesting())
  {
    _UpdateComment();
    _UpdateObjects();
  }
  
  return(0);
}


void _UpdateComment()
{
  string s = "V" + _VERSION_ + "  ";


 
  if (SymbolParseOk)
    s = s + "Parse " + SymbolTop + "," + SymbolTopIndex + " " + SymbolBottom + "," + SymbolBottomIndex;
  else
    s = s + "Parse failure " + SymbolTop + " " + SymbolBottom + "  ";
   
  s = s + "Spread: " + DoubleToStr((Ask-Bid)/Point/POINT_FACTOR, 1) + "p";
  
  
  if (!Active || !_GVActive())
    s = s + "  INACTIVE";
  
  s = s + "  Lots: ";
  double lots;
  bool override = _GVFixedLots(lots);
  lots = _GetLots();
  if (lots < 0.1)
    s = s + DoubleToStr(lots,2);
  else
    s = s + DoubleToStr(lots,1);
  if (override)
    s = s + " (override)";
  
  double befactor = MoveStopToBE_Factor;
  override = _GVMoveStopToBEFactor(befactor);
  if (befactor > 0)
    s = s + "  MoveStopToBE_Factor " + DoubleToStr(befactor,2);
  if (override)
    s = s + " (override)";
  
  if (_IsInTrade())
  {
    /*
    string ticket;
    if (IsTicketShortOpen)
      ticket = "" + TicketShortPeriod;
    else
      ticket = "[" + TicketShortPeriod + "]";
    s = s + "  Ticket(" + DonchianPeriod_Short + "): " + ticket + " " + _GetBriefDollarDisplay(_GetTicketProfit$(TicketShortPeriod));
    
    if (IsTicketLongOpen)
      ticket = "" + TicketLongPeriod;
    else
      ticket = "[" + TicketLongPeriod + "]";
    s = s + "  Ticket(" + DonchianPeriod_Long + "): " + ticket + " " + _GetBriefDollarDisplay(_GetTicketProfit$(TicketLongPeriod));
    */
    s = s + "\n";
  }
  else if (_IsTradeComplete())
  {
    s = s + "\nTrade Complete: " + _GetBriefDollarDisplay(_GetTicketProfit$(TicketShortPeriod)+_GetTicketProfit$(TicketLongPeriod)) + "  ";
  }
  else
    s = s + "\nShort@: " + DoubleToStr(_GetEntryPriceShort(), Digits) + "  Long@: " + DoubleToStr(_GetEntryPriceLong(), Digits) + "  ";
  
  s = s + "Total Risk: " + _GetBriefDollarDisplay(_GetTotalDNCRisk$());

  double win$;
  double loss$;
  _GetHistoryWinLoss$(24, win$, loss$);
  s = s + "  Win(24): " + _GetBriefDollarDisplay(win$) + " Loss(24): " + _GetBriefDollarDisplay(loss$);
  
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

  _DrawBackground(CORNER_TOPLEFT,  STATUS_X-2, STATUS_Y, Black, "ggggggg");


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
}


/*
  [Profit/Loss]       +3
  [Target]            +1
  [MFE]               +2
  [MAE]               +0
*/

color InfoColor;
datetime InfoColor_NextChange;

double MFE_short_$;
double MFE_long_$;
double MFE_short_price;
double MFE_long_price;

double MAE_short_$;
double MAE_long_$;
double MAE_short_price;
double MAE_long_price;


void _ResetStats()
{
  MFE_short_$ = 0;
  MFE_long_$ = 0;
  MFE_short_price = 0;
  MFE_long_price = 0;
  
  MAE_short_$ = 0;
  MAE_long_$ = 0;
  MAE_long_price = 0;
  MAE_short_price = 0;

  bool isLong;
  if (OrderSelect(TicketShortPeriod, SELECT_BY_TICKET) || OrderSelect(TicketShortPeriod, SELECT_BY_TICKET, MODE_HISTORY))
  {
    if (OrderCloseTime() == 0)
    {
      isLong = (OrderType() == OP_BUY || OrderType() == OP_BUYLIMIT || OrderType() == OP_BUYSTOP);
      if (isLong)
      {
        MAE_short_price = Bid;
        MFE_short_price = Bid;
      }
      else
      {
        MAE_short_price = Ask;
        MFE_short_price = Ask;
      }
      MFE_short_$ = _GetProfitAtPrice$(TicketShortPeriod, MFE_short_price);
      MAE_short_$ = MFE_short_$;
    }
    else
    {
      MAE_short_price = OrderOpenPrice();
      MFE_short_price = OrderOpenPrice();
      MFE_short_$ = OrderProfit() + OrderSwap();
      MAE_short_$ = MFE_short_$;
    }
  }
  
  if (OrderSelect(TicketLongPeriod, SELECT_BY_TICKET) || OrderSelect(TicketLongPeriod, SELECT_BY_TICKET, MODE_HISTORY))
  {
    if (OrderCloseTime() == 0)
    {
      isLong = (OrderType() == OP_BUY || OrderType() == OP_BUYLIMIT || OrderType() == OP_BUYSTOP);
      if (isLong)
      {
        MAE_long_price = Bid;
        MFE_long_price = Bid;
      }
      else
      {
        MAE_long_price = Ask;
        MFE_long_price = Ask;
      }
      MFE_long_$ = _GetProfitAtPrice$(TicketLongPeriod, MFE_long_price);
      MAE_long_$ = MFE_long_$;
    }
    else
    {
      MAE_long_price = OrderOpenPrice();
      MFE_long_price = OrderOpenPrice();
      MFE_long_$ = OrderProfit() + OrderSwap();
      MAE_long_$ = MFE_long_$;
    }
  }
}


int ColorLagSec = 2;

void _UpdateTradeStats()
{
  if (!_IsInTrade())
    return;
  
  double lastMFE = MFE_short_$ + MFE_long_$;
  double lastMAE = MAE_short_$ + MAE_long_$;
  
  double ticketProfit$ = _GetTicketProfit$(TicketShortPeriod);
  if (ticketProfit$ > MFE_short_$)
    MFE_short_$ = ticketProfit$;
  else if (ticketProfit$ < MAE_short_$)
    MAE_short_$ = ticketProfit$;
    
  ticketProfit$ =  _GetTicketProfit$(TicketLongPeriod);
  if (ticketProfit$ > MFE_long_$)
    MFE_long_$ = ticketProfit$;
  else if (ticketProfit$ < MAE_long_$)
    MAE_long_$ = ticketProfit$;
        

  double total$ = _GetTotalProfit$();
  if (total$ > 0)
  {
    if ((MFE_short_$ + MFE_long_$) > lastMFE)
    {
      InfoColor = LimeGreen;
      InfoColor_NextChange = TimeCurrent() + ColorLagSec;
    }
    else
    {
      if (TimeCurrent() > InfoColor_NextChange)
        InfoColor = DarkGreen;
    }
  }
  else if (total$ < 0)
  {
    if ((MAE_short_$ + MAE_long_$) < lastMAE)
    {
      InfoColor = Red;
      InfoColor_NextChange = TimeCurrent() + ColorLagSec;
    }
    else
    {
      if (TimeCurrent() > InfoColor_NextChange)
        InfoColor = Maroon;
    }
  }
  else
    InfoColor = DimGray;

  
  if (_IsTradeLong())
  {
    if (IsTicketShortOpen  &&  Bid > MFE_short_price)
      MFE_short_price = Bid;
    
    if (IsTicketLongOpen  &&  Bid > MFE_long_price)
      MFE_long_price = Bid;
  }
  else
  {
    if (IsTicketShortOpen  &&  Ask < MFE_short_price)
      MFE_short_price = Ask;
      
    if (IsTicketLongOpen  &&  Ask < MFE_long_price)
      MFE_long_price = Ask;
  } 
}


double _GetProfitAtStop$(int ticket)
{
  if (OrderSelect(ticket, SELECT_BY_TICKET))
  {
    if (OrderCloseTime() == 0)
    {
      if (OrderStopLoss() > 0)
        return (_GetProfitAtPrice$(ticket, OrderStopLoss()));
      else
        return (0.0);
    }      
    else
      return (OrderProfit() + OrderSwap());
  }
  else if (OrderSelect(ticket, SELECT_BY_TICKET, MODE_HISTORY))
    return (OrderProfit() + OrderSwap());
  else
    return (0.0);
}


double _GetProfitAtPrice$(int ticket, double price)
{
  if (OrderSelect(ticket, SELECT_BY_TICKET) || OrderSelect(ticket, SELECT_BY_TICKET, MODE_HISTORY))
  {
    if (OrderType() == OP_BUY)
      return ((price - OrderOpenPrice()) / MarketInfo(OrderSymbol(), MODE_POINT) * MarketInfo(OrderSymbol(), MODE_TICKVALUE) * OrderLots());
    else
      return ((OrderOpenPrice() - price) / MarketInfo(OrderSymbol(), MODE_POINT) * MarketInfo(OrderSymbol(), MODE_TICKVALUE) * OrderLots());
  }
  else
    return (0.0);
}


double _GetProfitAtStopPips(int ticket)
{
  return (0.0);
}


double _GetProfitAtPricePips(int ticket, double price)
{
  double pipsAt = 0.0;
  if (OrderSelect(ticket, SELECT_BY_TICKET) || OrderSelect(ticket, SELECT_BY_TICKET, MODE_HISTORY))
  {
    if (OrderType() == OP_BUY)
      return ((price - OrderOpenPrice()) / MarketInfo(OrderSymbol(), MODE_POINT) / POINT_FACTOR);
    else
      return ((OrderOpenPrice() - price) / MarketInfo(OrderSymbol(), MODE_POINT) / POINT_FACTOR);
  }
  else
    return (0.0);
}


double _GetTicketTP(int ticket)
{
  if (OrderSelect(ticket, SELECT_BY_TICKET) || OrderSelect(ticket, SELECT_BY_TICKET, MODE_HISTORY))
    return (OrderTakeProfit());
  else
    return (0.0);
}



int col2xoffs = 50;

void _UpdateInfoPanel()
{
  for (int i=0; i<5; i++)
  {
    string s1 = "";
    string s2 = "";
    int y = 3+(LineSpacing*(5-i-1));
    
    switch (i)
    {
      // -- MFE
      case 0:
        s1 = "MFE";
        if (ShowCurrency)
          s2 = GetDollarDisplay(MFE_short_$ + MFE_long_$); //_GetProfitAtPrice$(TicketShortPeriod, MFE_short_price) + _GetProfitAtPrice$(TicketLongPeriod, MFE_long_price));
        else
          s2 = GetPipsDisplay(_GetProfitAtPricePips(TicketShortPeriod, MFE_short_price) + _GetProfitAtPricePips(TicketLongPeriod, MFE_long_price));
        break;
      
      // -- MAE
      case 1:
        s1 = "MAE";
        if (ShowCurrency)
          s2 = GetDollarDisplay(MAE_short_$ + MAE_long_$); //_GetProfitAtPrice$(TicketShortPeriod, MAE_short_price) + _GetProfitAtPrice$(TicketLongPeriod, MAE_long_price));
        else
          s2 = GetPipsDisplay(_GetProfitAtPricePips(TicketShortPeriod, MAE_short_price) + _GetProfitAtPricePips(TicketLongPeriod, MAE_long_price));
        break;
      
      // -- Target
      case 2:
        s1 = "Target";
        if (ShowCurrency)
          s2 = GetDollarDisplay(_GetProfitAtPrice$(TicketShortPeriod, _GetTicketTP(TicketShortPeriod)) + _GetProfitAtPrice$(TicketLongPeriod, _GetTicketTP(TicketLongPeriod)));
        else
          s2 = GetPipsDisplay(_GetProfitAtPricePips(TicketShortPeriod, _GetTicketTP(TicketShortPeriod)) + _GetProfitAtPricePips(TicketLongPeriod, _GetTicketTP(TicketLongPeriod)));
        break;
      
      // -- Locked
      case 3:
        if (ShowCurrency)
        {
          double netLocked$ = _GetProfitAtStop$(TicketShortPeriod) + _GetProfitAtStop$(TicketLongPeriod);
          if (netLocked$ > 0)
            s1 = "Locked";
          else
            s1 = "Risk";
          s2 = GetDollarDisplay(netLocked$);
        }
        else
        {
          double netLockedPips = _GetProfitAtStopPips(TicketShortPeriod) + _GetProfitAtStopPips(TicketLongPeriod);
          if (netLockedPips > 0)
            s1 = "Locked";
          else
            s1 = "Risk";
          s2 = GetPipsDisplay(netLockedPips);
        }
        break;
      
      // -- Profit
      case 4:
        if (_GetTotalProfit$() >= 0)
          s1 = "Profit";
        else
          s1 = "Loss";
        
        if (ShowCurrency)
          s2 = GetDollarDisplay(_GetTotalProfit$());
        else
          s2 = GetPipsDisplay(_GetTotalProfitPips());
        break;
    }
    
    SetLabel("linfoT"+i, 7, y, s1, White);
    SetLabel("lInfo"+i, col2xoffs, y, s2, White);
    ObjectSet(pfx+"lInfoT"+i, OBJPROP_CORNER, CORNER_BOTTOMLEFT);
    ObjectSet(pfx+"lInfo"+i, OBJPROP_CORNER, CORNER_BOTTOMLEFT);
  }
}


void _UpdateBackground()
{
  for (int i=0; i<5; i++)
    _DrawBackground(CORNER_BOTTOMLEFT, 2, 3 + LineSpacing*i, InfoColor, "ggggggg");
}


void _DrawBackground(int corner, int x, int y, color clr, string bkg = "ggggggggg")
{
  y = y - 2;
  SetLabel("bkga"+y, 5, y, bkg, clr, 0, "Webdings");
  ObjectSet(pfx+"bkga"+y, OBJPROP_CORNER, corner);
}


bool _FindOpenTickets()
{
  TicketLongPeriod = 0;
  TicketShortPeriod = 0;
  IsTicketShortOpen = false;
  IsTicketLongOpen = false;

  for (int i=0; i<OrdersTotal(); i++)
    if (OrderSelect(i, SELECT_BY_POS))
    {
      if (OrderCloseTime() == 0  &&  OrderMagicNumber() == Magic)
      {
        if (StringFind(OrderComment(), _ShortSuffix()) > 0)
        {
          TicketShortPeriod = OrderTicket();
          TradeLong = (OrderType() == OP_BUY || OrderType() == OP_BUYLIMIT || OrderType() == OP_BUYSTOP);
          IsTicketShortOpen = true;
          continue;
        }
        
        if (StringFind(OrderComment(), _LongSuffix()) > 0)
        {
          TicketLongPeriod = OrderTicket();
          TradeLong = (OrderType() == OP_BUY || OrderType() == OP_BUYLIMIT || OrderType() == OP_BUYSTOP);
          IsTicketLongOpen = true;
        }
      }
    }
    
  if (IsTicketLongOpen && !IsTicketShortOpen)
  {
    // Find the short ticket in the history
    for (i=0; i<OrdersHistoryTotal(); i++)
      if (OrderSelect(i, SELECT_BY_POS, MODE_HISTORY) && OrderCloseTime()!=0 && OrderMagicNumber() == Magic)
      {
        if (StringFind(OrderComment(), _ShortSuffix()) > 0)
        {
          // just find the first one
          TicketShortPeriod = OrderTicket();
          break;
        }
      }
  }
    
  _ResetStats();   
  return ((TicketShortPeriod != 0) || (TicketLongPeriod != 0));
}


double _GetSpread()
{
  if (Spread_Pips > 0)
    return (Spread_Pips*Point*POINT_FACTOR);
  else
    return (Ask-Bid);
}


double _GetEntryPriceShort()
{
  return (_High(DonchianPeriod_Long, 1) - _GetSpread());
}


double _GetEntryPriceLong()
{
  return (_Low(DonchianPeriod_Long, 1) + _GetSpread());
}


void _GetHistoryWinLossCount(int hours, int& wins, int& losses)
{
  double cutoff = TimeCurrent() - (SecondsPerHour*hours);
  wins=0;
  losses=0;
  int total = OrdersHistoryTotal();
  for (int i=0; i<total; i++)
  {
    if (OrderSelect(i, SELECT_BY_POS, MODE_HISTORY) && (OrderCloseTime() >= cutoff) && IsTradeCommentOurs(OrderComment()))
    {
      if ((OrderProfit() + OrderSwap()) > 0)
        wins++;
      else if ((OrderProfit() + OrderSwap()) < 0)
        losses++;
    }
  }
}


void _GetHistoryWinLoss$(int hours, double& win$, double& loss$)
{
  double cutoff = TimeCurrent() - (SecondsPerHour*hours);
  win$=0;
  loss$=0;
  int total = OrdersHistoryTotal();
  for (int i=0; i<total; i++)
  {
    if (OrderSelect(i, SELECT_BY_POS, MODE_HISTORY) && (OrderCloseTime() >= cutoff) && IsTradeCommentOurs(OrderComment()))
    {
      if ((OrderProfit() + OrderSwap()) > 0)
        win$ = win$ + OrderProfit() + OrderSwap();
      else if ((OrderProfit() + OrderSwap()) < 0)
        loss$ = loss$ + OrderProfit() + OrderSwap();
    }
  }
}


void _GetOpenWinLoss$(double& win$, double& loss$)
{
  win$=0;
  loss$=0;
  int total=OrdersTotal();
  for (int i=0; i<total; i++)
  {
    if (OrderSelect(i, SELECT_BY_POS) && (OrderOpenTime() > 0) && IsTradeCommentOurs(OrderComment()))
    {
      if ((OrderProfit() + OrderSwap()) > 0)
        win$ = win$ + OrderProfit() + OrderSwap();
      else if ((OrderProfit() + OrderSwap()) < 0)
        loss$ = loss$ + OrderProfit() + OrderSwap();
    }
  }
}


double _GetTotalDNCRisk$()
{
  // Returns the current $ at risk across all Donchian trades (trades located via comment inspection)
  double total$ = 0;
  int total=OrdersTotal();
  for (int i=0; i<total; i++)
  {
    if (OrderSelect(i, SELECT_BY_POS) && (OrderOpenTime() > 0) && (OrderType() == OP_BUY || OrderType() == OP_SELL))
      if (IsTradeCommentOurs(OrderComment()))
        total$ = total$ +  _GetProfitAtStop$(OrderTicket());
  }
  return (total$);
}


double _GetTotalRisk$()
{
  // Returns the current $ risk across all trades
  double total$ = 0;
  int total=OrdersTotal();
  for (int i=0; i<total; i++)
  {
    if (OrderSelect(i, SELECT_BY_POS) && (OrderOpenTime() > 0) && (OrderType() == OP_BUY || OrderType() == OP_SELL))
      total$ = _GetProfitAtStop$(OrderTicket());
  }
  return (total$);
}


string sTooManyTickets(int max)
{
  return ("# tickets (>" + max + ")");
}


datetime _GetTradeCloseTime()
{
  if (TicketLongPeriod != 0)
  {
    if (OrderSelect(TicketLongPeriod, SELECT_BY_TICKET, MODE_HISTORY))
      return (OrderCloseTime());
    else
      return (-1);
  }
  else
    return (-1);
}


int _DoCheckForEntry(string& reason)
{
  if (!Active || !_GVActive())
  {
    reason = "INACTIVE";
    return (-1);
  }
  
  if (!IsConnected() && !IsTesting())
  {
    reason = "DISCONNECTED";
    return (-1);
  }
  if (AccountBalance() <= StopTrading$)
  {
    reason = "Minimum Balance";
    return (-1);
  }
  
  
  if (_IsTradeComplete()  &&  DisableAfterLoss_Hours > 0  &&  _GetTotalProfit$() < 0)
  {
    datetime closeTime = _GetTradeCloseTime();
    if (closeTime > 0)
    {
      if (TimeCurrent() < closeTime + SecondsPerHour*DisableAfterLoss_Hours)
      {
        reason = "Too soon after loss";
        return (-1);
      }
    }
  }  
  
  
  bool tooManyTickets = false;
  int cntMax = _GVMaxTotalTickets();
  if (cntMax > 0)
  {
    if (CountTicketsAcrossAllPairs() > cntMax-2)  //-1 because we will open 2 tickets
      tooManyTickets = true;
  }

  string timeLeft;
  if (OnlyTakeOneTrade  &&  _IsTradeComplete())
  {
    reason = "One trade taken";
    return (-1);
  }
  else if (_IsTimeAllowed(timeLeft))
  {
    if (Bid > _GetEntryPriceShort())
    {
      if (tooManyTickets)
      {
        reason = "SELL " + sTooManyTickets(cntMax);
        return (-1);
      }
      else
      {
        reason = "SELL VALID";
        return (OP_SELL);
      }
    }
    else if (Ask < _GetEntryPriceLong())
    {
      if (tooManyTickets)
      {
        reason = "BUY " + sTooManyTickets(cntMax);
        return (-1);
      }
      else
      {
        reason = "BUY VALID";
        return (OP_BUY);
      }
    }
    else
    {
      reason = "WAITING";
      if (tooManyTickets)
        reason = reason + " " + sTooManyTickets(cntMax);
      return (-1);
    }
  }
  else
  {
    reason = "TIME OUT " + timeLeft;
    return (-1);
  }
}


double _GetLotFactor()
{
  double factor = 1.0;
  int i;
  if (WinSequence_Count > 0  &&  RiskOnPerWin_Factor > 0)
  {
    for (i=0; i<WinSequence_Count; i++)
      factor = factor + factor*RiskOnPerWin_Factor;
    if (factor > MaxRiskOn_Factor)
    {
      factor = MaxRiskOn_Factor;
      WinSequence_Max = true;
    }
    else
      WinSequence_Max = false;
  }
  else if (WinSequence_Count < 0  &&  RiskOffPerLoss_Factor > 0)
  {
    for (i=0; i>WinSequence_Count; i--)
      factor = factor * RiskOffPerLoss_Factor;
    if (factor < MinRiskOff_Factor)
    {
      factor = MinRiskOff_Factor;
      WinSequence_Max = true;
    }
    else
      WinSequence_Max = false;
  }
  return (factor);
}


double _GetLots()
{
  double result;
  if (!_GVFixedLots(result))
    result = Fixed_Lots;
  
  return (result * _GetLotFactor());
}



int _DoEntry(int direction)
{
  TicketShortPeriod = 0;
  TicketLongPeriod = 0;
  _ResetStats();

  //string symbol, int op, double lotsize, double price, double spread, double stoploss, double takeprofit,
  //string comment, int magic, datetime expiry=0, color clr=CLR_NONE)
  int dir;
  double price, tp_shortperiod, tp_longperiod;
  if (direction == OP_BUY)
  {
    dir = +1;
    price = Ask;
    tp_longperiod = _High(DonchianPeriod_Long) - _GetSpread();
    if (TP1Price_Factor > 0)
      tp_shortperiod = price + (tp_longperiod - price) * TP1Price_Factor;
    else
      tp_shortperiod = _High(DonchianPeriod_Short) - _GetSpread();
  }
  else if (direction == OP_SELL)
  {
    dir = -1;
    price = Bid;
    tp_longperiod = _Low(DonchianPeriod_Long) + _GetSpread();
    if (TP1Price_Factor > 0)
      tp_shortperiod = price - (price - tp_longperiod) * TP1Price_Factor;
    else
      tp_shortperiod = _Low(DonchianPeriod_Short) + _GetSpread();
  }
  else
    return (0);
    
  Print("Entering " + Symbol() + " spread = " + DoubleToStr(Ask-Bid, Digits));  
  double stop = price - dir*(OMGStop_Pips*Point*POINT_FACTOR);
  
  Print("WinSequence_Count=", WinSequence_Count, "  _GetLotFactor()=", _GetLotFactor());
  double lots = _GetLots();
    
  TicketShortPeriod = OrderReliableSend(Symbol(), direction, lots, price, Ask-Bid, stop, tp_shortperiod, GetOrderComment(Magic) + _ShortSuffix(), Magic);
  TicketLongPeriod = OrderReliableSend(Symbol(), direction, lots, price, Ask-Bid, stop, tp_longperiod, GetOrderComment(Magic) + _LongSuffix(), Magic);

  IsTicketShortOpen = TicketShortPeriod != 0;
  IsTicketLongOpen = TicketLongPeriod != 0;
  
  TradeLong = (direction == OP_BUY);
}


double _OrderOpenPrice()
{
  double total = 0.0;
  int count = 0;
  
  if (IsTicketLongOpen  &&  OrderSelect(TicketLongPeriod, SELECT_BY_TICKET))
  {
    total += OrderOpenPrice();
    count++;
  }
  
  if (IsTicketShortOpen  &&  OrderSelect(TicketShortPeriod, SELECT_BY_TICKET))
  {
    total += OrderOpenPrice();
    count++;
  }
  
  
  if (count > 0)
    return (total / count);
  else 
    return (0.0);
}


void _DoTradeManagement()
{
  if (TicketShortPeriod == 0  &&  TicketLongPeriod == 0)
    return;
  
  // -- Check if we should bail
  if (_IsTradeLong())
  {
    if (_Low(DonchianPeriod_Long) > _OrderOpenPrice())
      _CloseAllTickets();
  }
  else
  {
    if (_High(DonchianPeriod_Long) < _OrderOpenPrice())
      _CloseAllTickets();
  }
    
  // -- Check if tickets have closed, and do any necessary processing    
  if (IsTicketShortOpen && !_IsTicketOpen(TicketShortPeriod))
  {  // short period ticket has closed
    IsTicketShortOpen = false;
    
    if (_IsTicketOpen(TicketLongPeriod))
      _MoveStopToBE(TicketLongPeriod);
  }
  
  if (!_IsTicketOpen(TicketLongPeriod))
    IsTicketLongOpen = false;
  
  // -- Check for early move to be
  if (IsTicketShortOpen && IsTicketLongOpen)
  {
    double befactor;
    if (!_GVMoveStopToBEFactor(befactor))
      befactor = MoveStopToBE_Factor;
      
    if (befactor > 0)
    {
      _StopToBEIfPips(TicketShortPeriod, OMGStop_Pips * befactor);
      _StopToBEIfPips(TicketLongPeriod, OMGStop_Pips * befactor);
    }
  }
  else if (!IsTicketShortOpen && !IsTicketLongOpen)  // Trade has just closed
  {
    bool wasMax = WinSequence_Max;
    double lotFactor = _GetLotFactor();
    double winpips = _GetTotalProfitPips();
    if (winpips > 10)
    {
      if (lotFactor < MaxRiskOn_Factor)
        WinSequence_Count++;
      else if (wasMax  &&  ResetRiskOnSequenceOnMax)
        WinSequence_Count = 0;
    }
    else if (winpips < 0)
    {
      if (ResetRiskOnSequenceOnLoss && WinSequence_Count > 0)
        WinSequence_Count = 0;
      else if (lotFactor > MinRiskOff_Factor)
        WinSequence_Count--;
    }
  }
  
  // -- Apply trailing stop on long period ticket
  if (!IsTicketShortOpen  &&  IsTicketLongOpen  &&  LongTrailStart_Pips > 0  &&  LongTrailFactor > 0.0)
    _TrailStop(TicketLongPeriod, LongTrailStart_Pips, LongTrailFactor);
    
  // -- Check each open ticket for MissedByThatMuch effect
  if (IsTicketShortOpen)
    _DoMissedByThatMuch(TicketShortPeriod);
  if (IsTicketLongOpen)
    _DoMissedByThatMuch(TicketLongPeriod);
}


void _DoMissedByThatMuch(int ticket)
{
  if (MissedByThatMuch_Active_Factor <= 0)
    return;

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
    
    if (mbtmFactor >= MissedByThatMuch_Active_Factor)
      _MoveStop(ticket, mbtmPrice);
  }
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


void _TrailStop(int ticket, double startTrail_Pips, double trailFactor)
{
  double profitPips = _GetTicketProfitPips(ticket);
  if (profitPips > startTrail_Pips)
    _SetStopPips(ticket, profitPips * trailFactor);
}


void _StopToBEIfPips(int ticket, double targetPips)
{
  double profitPips = _GetTicketProfitPips(ticket);
  if (profitPips >= targetPips)
    _MoveStopToBE(ticket);
}


void _SetStopPips(int ticket, double stopPips)
{
  if (!OrderSelect(ticket, SELECT_BY_TICKET)  &&  stopPips > 0.0)
    return;
    
  double stopPrice;
  if (OrderType() == OP_BUY)
    stopPrice = Bid - stopPips*MarketInfo(OrderSymbol(), MODE_POINT)*POINT_FACTOR;
  else if (OrderType() == OP_SELL)
    stopPrice = Ask + stopPips*MarketInfo(OrderSymbol(), MODE_POINT)*POINT_FACTOR;
  else
    return;
    
  _MoveStop(ticket, stopPrice);
}




bool _IsTimeAllowed(string& timeRemaining)
{
  double hstart = _GVHourStart();
  double hstop = _GVHourStop();
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
  return ( (TicketShortPeriod != 0 || TicketLongPeriod != 0)  &&  (IsTicketShortOpen || IsTicketLongOpen));
}


// -- We had a trade, but it's over.  Use to display close info
bool _IsTradeComplete()
{
  return ((TicketShortPeriod != 0 || TicketLongPeriod != 0)  &&  !IsTicketShortOpen  &&  !IsTicketLongOpen);
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
  return (_GetTicketProfit$(TicketShortPeriod) + _GetTicketProfit$(TicketLongPeriod));
}


double _GetTotalProfitPips()
{
  return (_GetTicketProfitPips(TicketShortPeriod) + _GetTicketProfitPips(TicketLongPeriod));
}


void _CloseAllTickets()
{
  if (IsTicketShortOpen)
  {
    OrderReliableClose(TicketShortPeriod);
    IsTicketShortOpen = false;
  }

  if (IsTicketLongOpen)
  {
    OrderReliableClose(TicketLongPeriod);
    IsTicketLongOpen = false;
  }
}


void _MoveStopToBE(int ticket)
{
  if (OrderSelect(ticket, SELECT_BY_TICKET))
  {
    if (OrderType() == OP_BUY)
      _MoveStop(ticket, OrderOpenPrice() + 1.0*Point*POINT_FACTOR);
    else
      _MoveStop(ticket, OrderOpenPrice() - 1.0*Point*POINT_FACTOR);
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
//| Library Functions                                                |
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
  return (pips*10 * Point);
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


string Currencies[]       = { "aud", "cad", "chf", "eur", "gbp", "jpy", "nzd", "sgd", "usd", "xag", "xag" };
int    CurrExposureCount[] ={ 0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0     };
int    CurrExposureStrong[]={ 0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0     };
int    CurrExposureWeak[]  ={ 0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0     };
double CurrExposure$[]    = { 0.0,   0.0,   0.0,   0.0,   0.0,   0.0,   0.0,   0.0,   0.0,   0.0,   0.0   };

bool _ParseSymbol(string symbol, string& top, string& bottom)
{
  // Symbols can be of the form;
  //    eur/usd
  //    eurusd
  //    fxeurusd
  //    eurusdm
  
  int lastFoundIdx = -1;
  bottom = symbol;
  
  symbol = StringLower(symbol);
  for (int i=0; i < ArraySize(Currencies); i++)
  {
    int found = StringFind(symbol, Currencies[i]);
    if (found >= 0)
    {
      if (lastFoundIdx >= 0)
      {
        if (found > lastFoundIdx)
        {
          bottom = Currencies[i];
          top = StringSubstr(symbol, lastFoundIdx, 3);
        }
        else
        {
          bottom = StringSubstr(symbol, lastFoundIdx, 3);
          top = Currencies[i];
        }
        return (true);
      }
      else
        lastFoundIdx = found;
    }
  }
  return (false);
}


int _FindCurrIdx(string curr)
{
  for (int i=0; i < ArraySize(Currencies); i++)
    if (Currencies[i] == curr)
      return (i);
  return (-1);
}


void _GetExposure(double& topStrong$, double& topWeak$, double& bottomStrong$, double& bottomWeak$)
{

}


void _CalculateExposure()
{
  for (int curridx=0; curridx < ArraySize(Currencies); curridx++)
  {
    CurrExposureCount[curridx] = 0;
    CurrExposureStrong[curridx] = 0;
    CurrExposureWeak[curridx] = 0;
    CurrExposure$[curridx] = 0;
  }
  
  string curtop, curbottom;
  
  for (int orderidx=0; orderidx < OrdersTotal(); orderidx++)
  {
    if (OrderSelect(orderidx, SELECT_BY_POS) && (OrderOpenTime() > 0) && (OrderType() == OP_BUY || OrderType() == OP_SELL))
      if (IsTradeCommentOurs(OrderComment()))
      {
        _ParseSymbol(OrderSymbol(), curtop, curbottom);
        int idx = _FindCurrIdx(curtop);
        if (idx >= 0)
        {
          CurrExposureCount[idx] = CurrExposureCount[idx] + 1;
          CurrExposure$[idx] = _GetProfitAtStop$(OrderTicket());
          if (OrderType() == OP_BUY)
            CurrExposureStrong[idx] = CurrExposureStrong[idx] + 1;
          else if (OrderType() == OP_SELL)
            CurrExposureWeak[idx] = CurrExposureWeak[idx] + 1;
        }
        
        idx = _FindCurrIdx(curbottom);
        if (idx >= 0)
        {
          CurrExposureCount[idx] = CurrExposureCount[idx] + 1;
          CurrExposure$[idx] = _GetProfitAtStop$(OrderTicket());
          if (OrderType() == OP_BUY)
            CurrExposureWeak[idx] = CurrExposureWeak[idx] + 1;
          else if (OrderType() == OP_SELL)
            CurrExposureStrong[idx] = CurrExposureStrong[idx] + 1;
        }
      }
  }
}

