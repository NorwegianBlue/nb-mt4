//+------------------------------------------------------------------+
//|                                         Timar - Flag Trading.mq4 |
//|                              Copyright © 2011, Timar Investments |
//|                               http://www.timarinvestments.com.au |
//+------------------------------------------------------------------+

/*
  v12 (planned)
    - TODO: Link to external application. Send completed trades including in-trade stats like MAE/MFE.    
    - TODO: Status display %-of-risk mode
    - TODO: Fixed status display after trade has closed
    - TODO: Changed 2nd chance entry. If the 1st candle after signal does not enter, the 2nd can enter but the prior candle must
    
  v11
      not be greater than 2.4 pips from the SMA.
    - AutoStop does not apply while mouse is down. This prevents changes to SL/TP while dragging the bar.
    - Updated status display during trade to show profit/target, risk/maxrisk, mae/mfe
    - Added MoveStopToBEFactor. Dotted blue line shows Stop-to-BE price
    - Added ManualTicket
    - Added MaxStop_Pips filter.  If stop is > than MaxStop_Pips then no trade.
    
  v10
    - Added rule. Setup candle must close above MA for longs, below MA for shorts.
    - Updated trade stats block.
    - If timeframe is changed, Auto mode is disabled.
    - Fixed: When trade closed, Auto Stop would always disable.
    - Added h:m:s display to Next bar

  BUG - when in a trade, delete the TP line.   TP goes crazy.  It should reset TP to Risk*RiskFactor.

  TODO - stats display after trade closed not functional  

  TODO - MRAE not implemented
  
  TODO - implement a %-of-target display for the stats block
 
  once you have the trigger bar and it has closed,
  if going long, you enter 1 pip above the high of the trigger bar, if short--1pip below the low of the trigger bar,
  if price doesnt get to that pt on the next candle, 
    then you wait for the next pullback and trigger bar to form, 
    unless the bar after the trigger meets the criteria (distance from sma, cci) for being another trigger(2nd chance trigger--but can only do this once/pullback)

  TODO - for risk show "most extreme" and "current"
         Risk/MaxRisk (21)/(5) pips
  
  TODO - add "deactivate" price
         Yellow bar  
  
  TODO - toggle one shot/continuous mode from button
         use "trend reversal line".
           for long, "if price goes below here, trend is reversed and deactivate"
           for short, "if price goes above here, trend is reversed and deactivate"

        // TODO: Consider case where stop has been moved into profit. What should TP be then? Do we need to remember initial stop?
        // Not intial. Most extreme. If stop moved away from entry, that's the new extreme as that represents maximum risk
 

-- corner=1
[Info / Ticket]        <-- delete to open in manual mode
                           delete to close in manual/auto MODE_ASCEND

[Short] [Long]
[Manual] [Auto] [Off]
[Risk] [Lot]
[1.0][2.0][3.0] etc.   <-- toggles based on risk/lot setting
[One] [Many]           <-- if Auto, take on or many trades

-- corner=3



[MFE/MAE/Profit]       <-- only visible if trade running, or last closed trade found
[Bar remaining]


*/

/*
USAGE
  While looking for a trade;
    - The EA will look for Short or Long trades as specified.
    - In manual mode, the EA will recommend an entry with an alert sound and flashing "ENTER NOW" label.
      Delete the ENTER NOW label to open an order visible to the EA.
      You can of course open an order manually but such an order must be manually managed. The EA will not see it.
    - In auto mode, the EA will open an order as soon as the entry conditions are met.
      If DisableAfterTrade is true, the EA will deactivate after it takes one trade. It is highly
      recommended that you leave DisableAfterTrade true if you are not directly monitoring the EA.


  When a trade is open;
    - You can adjust stop loss by dragging the red bar.
       o Deleting the red bar, will not adjust the stop loss. It will be recreated at the current stop loss level.
         If you want to adjust the stop manually, do that then delete the red stop loss bar. It will be
         repositioned at the actual stop level.
    - You can adjust take profit by dragging the blue bar.
       o You can reset take profit to the recommended level by deleting the blue bar.

    - You can close the trade by deleting the "Ticket: nn" label, or you can close the usual way.
      If you partially cloes an order, the remaining part will be invisible to the EA and must
      be traded manually.    

  Notes
    - The profitability of this system relies on correctly identifying trends.
      The EA makes no attempt to identify the trend, and must be given the trend direction.

    - If the EA is off, you can still manage an open trade.

    - As soon as Account Equity falls below StopTradingEquity$, the EA will switch to manual mode.
      Exiting trades will not be closed, but no new trades will be opened.
*/

#property copyright "Copyright © 2011, NorwegianBlue"
#property link      "Wonderful plumage, the NorwegianBlue"

#include <stderror.mqh>
#include <stdlib.mqh>
#include <ptutils.mqh>
#include <ptorders.mqh>

#define VERSION_STR  "11"

extern string _VERSION_11 = VERSION_STR;
//extern bool Active = true;
extern int ManualTicket = 0;
extern double StopTradingEquity$ = 1000;
extern double OverridePointFactor = 0.0;
extern string _1="] 10=5 digit, 1=4 digit";
extern bool AutoStop = true;
extern double RewardRiskFactor = 1.0;
extern double MaxStop_Pips = 0;

double POINT_FACTOR = 10.0;

extern string _2="";
extern string CommentPrefix = "Flag";
extern double MaxPipsFromMA = 2.4;  // valid on e/u m5.  expand for higher volatility or higher timeframes
extern bool DisableAfterTrade = true;

// TEMPORARY
extern double FixedStopPips = 20.0;

extern string _3="__ Configuration __";
extern string _31="] Delimit lists with pipe char |";
extern string DefLots="0.01|0.05|0.1|1.0|";
//extern string DefRisk="3.0|1.0|2.0|";
extern string DefRisk="0.5|1.0|2.0|3.0|";
extern double NominalBalanceForRisk$ = 0;
extern string _32="]Set to 0 to use actual balance";
extern double MaxLots = 4.0;

extern string _4="__ Trade management ___";
extern double MoveStopToBEFactor = 0.75;

//extern bool UseSimpleTradeManagement = true;
//extern double LockInAtBE_Pips = 1;
//extern double MaxStop_Pips = 25;
//extern double MinStop_Pips = 10;
//extern double StopToBE_Pips = 15;
//extern double StopToSmall_Pips = 30;
//extern double Small_Pips = 10;
//extern double StopToHalf_Pips = 20;
//extern double TakeProfit_Factor = 2.0;

//extern string _5="__ Use last swing trade managment __";
//extern bool UseLastSwingTradeManagement = false;
//extern double MinSwingDistance_Pips = 15;

extern string _6 = "__ Display _____________";
extern string CurrencySymbol = "$";
extern bool ShowRiskPct = true;  // Show status as % of max risk
extern bool ShowCurrency = true;
extern bool ShowNextBarIn = true;
extern int MultiCommentLines = 4;

int Magic = 0;

//+------------------------------------------------------------------+

#define pfx "tft"
#define fontName     "Calibri"
#define boldFontName "Arial Black"
#define fontSize     8

#define MD_OFF   0
#define MD_LONG  1
#define MD_SHORT 2

int ActiveMode =  MD_OFF;


#define AM_MANUAL 0
#define AM_AUTO   1

int AutoMode = AM_MANUAL;


#define STATUS_X 5
#define STATUS_Y 20


#define BTNOFF_X   5
#define BTNLONG_X  40
#define BTNSHORT_X 75

#define BTN_Y 40

#define AMAUTO_X   5
#define AMMANUAL_X 40
#define AM_Y  60



#define LOT_Y  100
#define LOT_X  5
#define LOT_DX 22

double LOT[] = { 0.01, 0.05, 0.1, 1.0 };
int SELECTED_LOT = 0;


#define BTNLOTRISK_Y 80
#define BTNLOTS_X 5
#define BTNRISK_X 40

#define USE_LOTS  0
#define USE_RISK  1

int LotsOrRisk = USE_RISK;


#define RISK_Y 100
#define RISK_X 10
#define RISK_DX 25

#define RISKLOTS_Y 120
#define RISKLOTS_X 5

double RISK[] = {0.5, 1.0, 2.0, 3.0};
int SELECTED_RISK = 0;

#define BTNAUTOSTOP_X 5
#define BTNAUTOSTOP_Y 140

#define CLEAR_X 5
#define CLEAR_Y 150

#define BARREMAINING_X 5
#define BARREMAINING_Y 1
#define BARREMAINING_CORNER 3

string comment[];


//+------------------------------------------------------------------+
double MFE_pips;
double MFE_$;

double MAE_pips;
double MAE_$;


//+------------------------------------------------------------------+
int Ticket;

bool NewBar = false;
datetime LastBar = 0;
bool NeedRedraw;

int LastPeriod;
double LastTP = 0;
double LastSL = 0;
double MaxSL = 0;



//+------------------------------------------------------------------+
string GetIndicatorShortName()
{
  return("Timar - Flag Trading " + VERSION_STR + " " + Symbol());
}

string GetOrderComment(int magic)
{
  return(CommentPrefix + " v" + VERSION_STR + " " + PeriodToStr(Period()));
}

int CalculateMagicHash()
{
  string s = "" + Symbol() + GetIndicatorShortName() + Period();
  
  int hash = 0;
  int c;
  for (int i=0; i < StringLen(s); i++)
  {
    c = StringGetChar(s, i);
    hash = c + (hash * 64) + (hash * 65536) - hash;
  }
  return (MathAbs(hash / 65536));
}

int MaxSoundFrequency_Sec = 300000; // 300*1000 ms
int LastSound = 0;

void _Alert(string sound = "alert.wav")
{
  if (!IsTesting())
  {
    if (GetTickCount() - LastSound  >  MaxSoundFrequency_Sec)
    { 
      LastSound = GetTickCount();   
      PlaySound(sound);
    }
  }
}



//+------------------------------------------------------------------+
//| expert initialization function                                   |
//+------------------------------------------------------------------+
int init()
{
  LastPeriod = Period();
  
  if (OverridePointFactor != 0)
    POINT_FACTOR = OverridePointFactor;
  else
    POINT_FACTOR = GuessPointFactor();
  
  DeleteAllObjectsWithPrefix(pfx);
  Magic = CalculateMagicHash();
  
	ArrayResize( comment, MultiCommentLines );
	MultiCommentClear();
	
	string title =  "Flag Trading V" + VERSION_STR;
	if (POINT_FACTOR == 10)
	  title = title + " - (5 digit)";
	else
	  title = title + " - (4 digit)";
  MultiComment(title);

  ParseDelimStringDouble(DefLots, "|", LOT);
  ParseDelimStringDouble(DefRisk, "|", RISK);

  Ticket = _FindOpenTicket(Magic);
  if (Ticket != 0)
  {
    MaxSL = OrderStopLoss();
    MultiComment("Order " + Ticket + " already open");
  }
  else if (ManualTicket > 0)
  {
    Ticket = ManualTicket;
    if (OrderSelect(Ticket, MODE_TRADES))
    {
      
    }
    else
      MultiComment("ManualTicket " + ManualTicket + " not an open trade.");
  }

  _Redraw();

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
  if (Time[0] != LastBar)
  {
    LastBar = Time[0];
    NewBar = true;
  }
  else
    NewBar = false;
    
  if (Magic == 0)
    Magic = CalculateMagicHash();

  _UpdateFlashToggle();

  if (LastPeriod != Period())
    _SetMode(MD_OFF);
    
  int newTicket = _FindOpenTicket(Magic);
  if (newTicket == 0  &&  Ticket != 0) // Ticket has closed
  {
    string sResult = "Order " + Ticket + " closed ";
    if (OrderSelect(Ticket, MODE_HISTORY))
    {
      double profit = OrderProfit() + OrderSwap();
      if (profit > 0)
        sResult = sResult + " for profit ";
      else
        sResult = sResult + " for loss ";
      sResult = sResult + GetDollarDisplay(profit);
    }
    MultiComment(sResult);

    if (DisableAfterTrade)
      _SetMode(MD_OFF);

    _SLBarClear();
    DeleteObject("hbTL");
    DeleteObject("hbDeactivate");
    DeleteObject("hbBE");

    Ticket = 0;    
    _Redraw();
  }
  Ticket = newTicket;
  
  if (AccountEquity() < StopTradingEquity$)
  {
    AutoMode = AM_MANUAL;    
    NeedRedraw = true;
  }
  
  _UICheck();

  if (!_InTrade()  &&  AutoMode == AM_AUTO)
  {
    string reason;
    if (_IsEntryBar(reason, 0))
      _EnterNow();
  }

  _ApplyAutoStop();
  
  if (_InTrade())
    _ManageTrade();
  
  _UpdateObjects();
  
  return(0);
}


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


int _FindOpenTicket(int magic)
{
  for (int i=0; i<OrdersTotal(); i++)
    if (OrderSelect(i, SELECT_BY_POS))
    {
      if (OrderType() == OP_BUY  ||  OrderType() == OP_SELL)
      {
        if (OrderCloseTime() == 0  &&  OrderMagicNumber() == magic)
          return (OrderTicket());
      }
    }
  return (0);
}


int _FindOldestOpenTicket(int magic)
{
  int result = 0;
  int resultTime = TimeCurrent()+1;  
  
  for (int i=0; i<OrdersTotal(); i++)
    if (OrderSelect(i, SELECT_BY_POS))
    {
      if (OrderType() == OP_BUY  ||  OrderType() == OP_SELL)
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


int _FindLastClosedTicket(int magic)
{
  // TODO
  return (0);
}


bool _InTrade()
{
  return (Ticket != 0);
}


bool _IsTradeLong()
{
  if (OrderSelect(Ticket, SELECT_BY_TICKET))
    return (OrderType() == OP_BUY  ||  OrderType() == OP_BUYLIMIT  ||  OrderType() == OP_BUYSTOP);
  else
    return (ActiveMode == MD_LONG);
}


bool _IsTradeInMarket()
{
  if (OrderSelect(Ticket, SELECT_BY_TICKET))
    return ((OrderType() == OP_BUY  ||  OrderType() == OP_SELL) && (OrderCloseTime() == 0));
  else
    return (false);
}


bool _IsTradeClosed()
{
  if (OrderSelect(Ticket, SELECT_BY_TICKET))
    return (OrderCloseTime() != 0);
  else
    return (false);
}


bool _IsTradeBEOrBetter()
{
  bool isLong = _IsTradeLong();
  if (OrderSelect(Ticket, SELECT_BY_TICKET))
  {
    if (isLong)
      return (OrderStopLoss() >= OrderOpenPrice());
    else
      return (OrderStopLoss() <= OrderOpenPrice());
  }    
  else
    return (false);
}


color _BtnColor(bool isActive)
{
  if (isActive)
    return (Magenta);
  else
    return (White);
}


void _InitAutoMode()
{
  SetLabel("btnAuto", 1, AMAUTO_X, AM_Y, "[Auto]", _BtnColor(AutoMode == AM_AUTO));
  SetLabel("btnManual", 1, AMMANUAL_X, AM_Y, "[Manual]", _BtnColor(AutoMode == AM_MANUAL));
}


void _InitButtons()
{
  color clr;
  
  SetLabel("btnOff", 1, BTNOFF_X, BTN_Y, "[Off]", _BtnColor(ActiveMode == MD_OFF));
  SetLabel("btnLong", 1, BTNLONG_X, BTN_Y, "[Long]", _BtnColor(ActiveMode == MD_LONG));
  SetLabel("btnShort", 1, BTNSHORT_X, BTN_Y, "[Short]", _BtnColor(ActiveMode == MD_SHORT));
  
  //SetLabel("btnClearComment", CLEAR_X, CLEAR_Y, "[Clear]", White);
  //ObjectSet(pfx+"btnClearComment", OBJPROP_CORNER, 1);
  
  SetLabel("btnUseLot", 1, BTNLOTS_X, BTNLOTRISK_Y, "[Lots]", _BtnColor(LotsOrRisk == USE_LOTS));
  SetLabel("btnUseRisk", 1, BTNRISK_X, BTNLOTRISK_Y, "[Risk]", _BtnColor(LotsOrRisk == USE_RISK));
  
  if (_InTrade())
    DeleteObject("btnAutoStop");
  else
    SetLabel("btnAutoStop", 1, BTNAUTOSTOP_X, BTNAUTOSTOP_Y, "[Auto Stop]", _BtnColor(AutoStop));
}


string _LotToStr(double lot)
{
  if (lot < 0.1)
    return (DoubleToStr(lot, 2));
  else
    return (DoubleToStr(lot, 1));
}


string _RiskToStr(double risk)
{
  return (DoubleToStr(risk, 1)+"%");
}


int _LotX(int pos)
{
  return (LOT_X + LOT_DX*(ArraySize(LOT)-pos-1));
}


int _RiskX(int pos)
{
  return (RISK_X + RISK_DX*(ArraySize(RISK)-pos-1));
}


void _InitLot()
{
  DeleteAllObjectsWithPrefix(pfx+"btnRisk");
    for (int i=0; i<ArraySize(LOT); i++)
    SetLabel("btnLot"+i, 1, _LotX(i), LOT_Y, _LotToStr(LOT[i]), _BtnColor(SELECTED_LOT == i), 8);
}


void _InitRisk()
{
  DeleteAllObjectsWithPrefix(pfx+"btnLot");
  for (int i=0; i<ArraySize(LOT); i++)
    SetLabel("btnRisk"+i, 1, _RiskX(i), RISK_Y, _RiskToStr(RISK[i]), _BtnColor(SELECTED_RISK == i), 8);
}


bool _ButtonClicked(string name, int xpos, int ypos)
{
  return (ObjectGet(pfx+name, OBJPROP_XDISTANCE) != xpos  ||  ObjectGet(pfx+name, OBJPROP_YDISTANCE) != ypos); 
}


double _SLBarGet()
{
  if (ObjectFind(pfx+"hbSL")<0)
    return (-1.0);
  else
    return (ObjectGet(pfx+"hbSL", OBJPROP_PRICE1));
}


void _SLBarSet(double price)
{
  if (NormalizeDouble(price, Digits) != NormalizeDouble(_SLBarGet(), Digits))
  {
    SetLine("hbSL", price, Red, STYLE_SOLID, 2);
    _SLBarTextRefresh();
  }
}


void _TPBarSet(double price)
{
  SetLine("hbTP", price, Blue, STYLE_SOLID, 2);
  _SLBarTextRefresh();
}


void _SLBarTextRefresh()
{
  double price;
  double pips;
  if (ObjectFind(pfx+"hbSL")>=0)
  {
    price = _SLBarGet();
    if (_IsTradeLong())
      pips = (_GetCurrentOpenPrice() - price)/Point/POINT_FACTOR;
    else
      pips = (price - _GetCurrentOpenPrice())/Point/POINT_FACTOR;

    SetText("lbSL", Time[0] + (Time[0]-Time[1])*3, price, "SL " + DoubleToStr(pips, 0) + " pips", Red);
  }
  else
    DeleteObject("lbSL");
  
  if (ObjectFind(pfx+"hbTP")>=0)
  {
    price = ObjectGet(pfx+"hbTP", OBJPROP_PRICE1);
    if (_IsTradeLong())
      pips = (price - _GetCurrentOpenPrice())/Point/POINT_FACTOR;
    else
      pips = (_GetCurrentOpenPrice() - price)/Point/POINT_FACTOR;

    SetText("lbTP", Time[0] + (Time[0]-Time[1])*3, price, "TP " + DoubleToStr(pips, 0) + " pips", RoyalBlue);
  }
  else
    DeleteObject("lbTP");
}


void _SLBarClear()
{
  DeleteObject("hbSL");
  DeleteObject("lbSL");
}


void _UICheck()
{
  int i;
  color clrSL, clrTP;
  
  if (IsMouseDown())
    return;
    
  // CHECK FOR USER INTERACTION
  if (_ButtonClicked("btnOff", BTNOFF_X, BTN_Y))
  {
    MultiComment("Deactivated");
    DeleteObject("btnOff");
    _SLBarClear();
    DeleteObject("hbDeactivate");

    _SetMode(MD_OFF);
    NeedRedraw = true;
  }
  else if (_ButtonClicked("btnLong", BTNLONG_X, BTN_Y))
  {
    MultiComment("Now looking for Longs");
    DeleteObject("btnLong");
    _SLBarClear();
    DeleteObject("hbTP");
    DeleteObject("lbTP");
    DeleteObject("hbDeactivate");
    _SetMode(MD_LONG);
    NeedRedraw = true;
  }
  else if (_ButtonClicked("btnShort", BTNSHORT_X, BTN_Y))
  {
    MultiComment("Now looking for Shorts");
    DeleteObject("btnShort");
    _SLBarClear();
    DeleteObject("hbTP");
    DeleteObject("lbTP");
    DeleteObject("hbDeactivate");
    _SetMode(MD_SHORT);
    NeedRedraw = true;
  }

  // -- Check Auto/Manual mode
  if (_ButtonClicked("btnAuto", AMAUTO_X, AM_Y))
  {
    MultiComment("Auto mode");
    DeleteObject("btnAuto");
    AutoMode = AM_AUTO;
    NeedRedraw = true;
  }
  else if (_ButtonClicked("btnManual", AMMANUAL_X, AM_Y))
  {  
    MultiComment("Manual mode");
    DeleteObject("btnManual");
    AutoMode = AM_MANUAL;
    NeedRedraw = true;
  }
  
  // -- Check for Clear Multicomment
  //if (_ButtonClicked("btnClearComment", CLEAR_X, CLEAR_Y))
  // {
  //   MultiCommentClear();
  //   ObjectDelete(pfx+"btnClearComment");
  //   NeedRedraw = true;
  // }
  
  
  if (_ButtonClicked("btnUseLot", BTNLOTS_X, BTNLOTRISK_Y))
  {
    MultiComment("Fixed lots mode");
    DeleteObject("btnUseLot");
    LotsOrRisk = USE_LOTS;
    NeedRedraw = true;
  }
  else if (_ButtonClicked("btnUseRisk", BTNRISK_X, BTNLOTRISK_Y))
  {
     MultiComment("Risk mode");
     DeleteObject("btnUseRisk");
     LotsOrRisk = USE_RISK;
     NeedRedraw = true;
  }   

  // -- Check LOT buttons
  if (LotsOrRisk == USE_LOTS)
  {
    for (i=0; i<ArraySize(LOT); i++)
    {
      if (_ButtonClicked("btnLot"+i, _LotX(i), LOT_Y))
      {
        MultiComment("Lot size now " + _LotToStr(LOT[i]));
        SELECTED_LOT = i;
        DeleteObject("btnLot"+i);
        NeedRedraw = true;
        break;
      }
    }
  }
  else
  {
    for (i=0; i<ArraySize(RISK); i++)
    {
      if (_ButtonClicked("btnRisk"+i, _RiskX(i), RISK_Y))
      {
        MultiComment("Risk now " + _RiskToStr(RISK[i]));
        SELECTED_RISK = i;
        DeleteObject("btnRisk"+i);
        NeedRedraw = true;
        break;
      }
    }
  }
  
  if (!_InTrade()  &&  _ButtonClicked("btnAutoStop", BTNAUTOSTOP_X, BTNAUTOSTOP_Y))
  {
    AutoStop = !AutoStop;
    if (AutoStop)
      MultiComment("AutoStop ON");
    else
      MultiComment("AutoStop OFF");
    DeleteObject("btnAutoStop");
    NeedRedraw = true;
  }
  
  // Check SL & TP Bars
  if (_InTrade()  ||  ActiveMode != MD_OFF)
  {
    double linePrice;
    clrSL = Red;
    clrTP = Blue;
  
    if (_SLBarGet()<0)
    { // SL bar not present, or deleted so create it.
      _SLBarSet(_GetTradeStop());
    }
    else
    {
      linePrice = _SLBarGet();
      if (_InTrade())
      {
        // If the trade's stop is different to the last stop we saw, then something else changed the stop so respect that and move our bar
        if (NormalizeDouble(_GetTradeStop(), Digits) != NormalizeDouble(LastSL, Digits))
        {
          LastSL = _GetTradeStop();
          _SLBarSet(LastSL);
        }
        else
        { // check if bar moved, if so move SL
          if (linePrice > 0  &&  NormalizeDouble(linePrice, Digits) != NormalizeDouble(_GetTradeStop(), Digits))
            _MoveStopWithComment(Ticket, linePrice, true);
        }
      }
    }
   
    // TP bar.  Only show if in trade.  If in trade, check for movement and set TP based on that.
    if (_InTrade())
    {
      if (ObjectFind(pfx+"hbTP")<0)
      {
        // TODO: Consider case where stop has been moved into profit. What should TP be then? Do we need to remember initial stop?
        // Not intial. Most extreme. If stop moved away from entry, that's the new extreme as that represents maximum risk
        _TPBarSet(_GetRecommendedTakeProfit());
      }
      else
      {
        linePrice = ObjectGet(pfx+"hbTP", OBJPROP_PRICE1);
        if (_InTrade())
        { 
          // If the trade's TP is different to the last TP we saw, then something else changed the TP so respect that and move our bar
          if (NormalizeDouble(_GetTradeTakeProfit(), Digits) != NormalizeDouble(LastTP, Digits))
          {
            LastTP = _GetTradeTakeProfit();
            _TPBarSet(LastTP);
          }
          else
          { // check if bar moved, if so move TP
            if (linePrice > 0  &&  NormalizeDouble(linePrice, Digits) != NormalizeDouble(_GetTradeTakeProfit(), Digits))
              _MoveTakeProfitWithComment(Ticket, linePrice);
          }
        }
      }
    }
    else 
    {
      DeleteObject("hbTP");
      DeleteObject("lbTP");
    }
  }
  else
  {
    _SLBarClear();
    DeleteObject("hbTP");
    DeleteObject("lbTP");
  }
  
  
  // If Manual mode, and ENTER NOW displayed, if it was pressed then enter
  string reason;
  if (!_InTrade()  &&  AutoMode == AM_MANUAL  &&  _IsEntryBar(reason, 0)  &&  _ButtonClicked("entry", STATUS_X, STATUS_Y))
  {
    MultiComment("Opening position");
    DeleteObject("entry");
    NeedRedraw = true;
    _EnterNow();
  }
  else
  {
    if (_InTrade()  &&  _ButtonClicked("entry", STATUS_X, STATUS_Y))
    {
      MultiComment("Manual close order " + Ticket);
      DeleteObject("entry");
      _CloseTicket(Ticket);
      NeedRedraw = true;
    }
  }

  if (NeedRedraw)
    _Redraw();
}


void _Redraw()
{
  _InitButtons();
  _InitAutoMode();
  if (LotsOrRisk == USE_LOTS)
    _InitLot();
  else
    _InitRisk();
  
  _UpdateObjects();
  NeedRedraw = false;
}


void _SetMode(int mode)
{
  if (ActiveMode != mode)
  {
    NeedRedraw = true;
    ActiveMode = mode;
  }
}


void _ApplyAutoStop()
{
  /*
    When going short;
      If CCI(1) > 50
        move stop to High[1]+spread
      
      If High[0]+spread > stop
        move stop to High[0]+spread
  */
  if (IsMouseDown() || !AutoStop || _InTrade() || ActiveMode == MD_OFF)
    return;
  
  double linePrice = _SLBarGet();
  double spread = Ask-Bid;

  if (linePrice > 0)
  {
    if (_IsTradeLong())
    {
      if (NewBar && _CCI(1) < -50 && _CCI(2) > -50) // just crossed over to -50
        _SLBarSet(MathMin(Low[0]-spread, Low[1]-spread));
      else if (Low[0]-spread < linePrice)
        _SLBarSet(Low[0]-spread);
    }
    else
    {
      if (NewBar && _CCI(1) > 50 && _CCI(2) < 50) // just crossed over to +50
        _SLBarSet(MathMax(High[1]+spread, High[0]+spread));
      else if (High[0]+spread > linePrice)
        _SLBarSet(High[0]+spread);
    }
  }
}


void _UpdateObjects()
{
  color clr;
  string txt;
  if (_InTrade())
  {
    txt = "[Close Order " + Ticket + "]";
    SetLabel("entry", 1, STATUS_X, STATUS_Y, txt, White);
    SetLabel("lots", 1, RISKLOTS_X, RISKLOTS_Y, "Lots: " + DoubleToStr(_GetTradeLots(), 2), Gray);
    
    double bePrice = _GetBEPrice();
    if (bePrice > 0)
      SetLine("hbBE", _GetBEPrice(), Blue, STYLE_DOT);
    else
      DeleteObject("hbBE");
    
    _UpdateStats();    
  }
  else
  {
    string reason;
    if (_IsEntryBar(reason, 0))
    {
      if (LastToggle)
        clr = White;
      else
        clr = Green;
        
      txt = "[ENTER NOW]";
      _Alert();
    }
    else
    {
      clr = Gray;
      txt = reason;
    }
    
    SetLabel("entry", 1, STATUS_X, STATUS_Y, txt, clr);

    if (ActiveMode != MD_OFF)
      SetLabel("lots", 1, RISKLOTS_X, RISKLOTS_Y, "Lots: " + DoubleToStr(_CalculateLots(), 2), Gray);
    else
      DeleteObject("lots");
  }
  
  _SLBarTextRefresh();
  
  _UpdateNextBarIn();
}


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
    
    SetLabel("nextBarIn", BARREMAINING_CORNER, BARREMAINING_X, BARREMAINING_Y, s, clr);
  }
  else
    DeleteObject("nextBarIn");
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


#define STATS_X   5
#define STATS_Y  15
#define STATS_FONT_SIZE 8
#define STATS_LINE_HEIGHT 13

/*
  [Profit/Loss]         +3
  [Risk] / [MaxRisk]    +2
  [ToTarget]            +1
  [MAE / MRAE / MFE]    +0
*/

void _UpdateStats()
{
  double dProfit;
  if (_IsTradeInMarket())
  {
    if (_GetProfit$() > MFE_$)
      MFE_$ = _GetProfit$();
    if (_GetProfitPips() > MFE_pips)
      MFE_pips = _GetProfitPips();
      
    if (_GetProfit$() < MAE_$)
      MAE_$ = _GetProfit$();
    if (_GetProfitPips() < MAE_pips)
      MAE_pips = _GetProfitPips(); 

    color clr;
    dProfit = _GetProfit$();
    if (dProfit >= 0)
      clr = Green;
    else
      clr = Red;
  
    string sProfit;
    string sTarget;
    
    if (ShowCurrency)
    {
      sProfit = GetDollarDisplay(dProfit);
      sTarget = GetDollarDisplay(_GetProfitAtPrice$(_GetTradeTakeProfit()));
      SetLabel("lProfit", 3, STATS_X,STATS_Y + STATS_LINE_HEIGHT*2,
        "Profit " + sProfit + " / " + sTarget, clr, STATS_FONT_SIZE);
    }
    else
    {
      sProfit = _GetBriefPipsDisplay(dProfit);
      sTarget = _GetBriefPipsDisplay(_GetPipsAtPrice(_GetTradeTakeProfit()));
      SetLabel("lProfit", 3, STATS_X,STATS_Y + STATS_LINE_HEIGHT*2,
        "Profit " + sProfit + "p / " + sTarget + "p", clr, STATS_FONT_SIZE);      
    }
    
    _UpdateMAEMFE(clr);
    
    //---
    double dProfitAtStop;
    string sRisk;
    string sMaxRisk;
    if (ShowCurrency)
    {
      dProfitAtStop = _GetProfitAtStop$();
      sRisk = _GetBriefDollarDisplay(dProfitAtStop);
      sMaxRisk = _GetBriefDollarDisplay(_GetProfitAtPrice$(MaxSL));
      SetLabel("lProfitAtStop", 3, STATS_X, STATS_Y+ STATS_LINE_HEIGHT*1, "Risk/Max " + sRisk + " / " + sMaxRisk, clr, STATS_FONT_SIZE);
    }
    else
    {
      dProfitAtStop = _GetPipsAtStop();
      sRisk = _GetBriefPipsDisplay(dProfitAtStop);
      sMaxRisk = _GetBriefPipsDisplay(_GetPipsAtPrice(MaxSL));
      SetLabel("lProfitAtStop", 3, STATS_X, STATS_Y+ STATS_LINE_HEIGHT*1, "Risk/Max " + sRisk + " / " + sMaxRisk + " p", clr, STATS_FONT_SIZE);
    }
  }
  else if (_IsTradeClosed())
  {
    //if (dProfit > 0)
    //  SetLabel("lProfit", 3, STATS_X, STATS_Y, "Final Profit " + CurrencySymbol + DoubleToStr(dProfit,2), Green, STATS_FONT_SIZE);
    //else
    //  SetLabel("lProfit", 3, STATS_X, STATS_Y, "Final Loss (" + CurrencySymbol + DoubleToStr(dProfit,2) + ")", Red, STATS_FONT_SIZE);
    //DeleteObject("lProfitAtStop");
    //
    //_UpdateMAEMFE();
  }
  else
    _DeleteStats();
}


void _DeleteStats()
{
  DeleteObject("lProfit");
  DeleteObject("lProfitAtStop");
  DeleteObject("lMAE");
  DeleteObject("lMFE");
}


void _ResetStats()
{
  MFE_$ = 0;
  MAE_$ = 0;
  MFE_pips = 0;
  MAE_pips = 0;
}


void _UpdateMAEMFE(color clr)
{
  string s = "MAE/MFE ";
  if (ShowCurrency)
  {
    s = s + _GetBriefDollarDisplay(MAE_$) + " / ";
    s = s + _GetBriefDollarDisplay(MFE_$);
  }
  else
  {
    s = s + _GetBriefPipsDisplay(MAE_pips) + " / ";
    s = s + _GetBriefPipsDisplay(MFE_pips) + " p";
  }
  SetLabel("lMAEMFE", 3, STATS_X,STATS_Y, s, clr, STATS_FONT_SIZE);
}


double _GetProfit$()
{
  double total=0.0;
  if (OrderSelect(Ticket, SELECT_BY_TICKET))
    total += OrderProfit() + OrderSwap();    
  return (total);
}


double _GetProfitPips()
{
  double total=0.0;
  if (OrderSelect(Ticket, SELECT_BY_TICKET))
  {
    if (OrderType() == OP_BUY)
      total += (Bid - OrderOpenPrice()) / Point / POINT_FACTOR;
    else
      total += (OrderOpenPrice() - Ask) / Point / POINT_FACTOR;
  }
  return (total);
}


double _GetProfitAtPrice$(double price)
{
  double profitAt$ = 0.0;
  bool isLong = _IsTradeLong();
  double closePrice;
  if (isLong)
    closePrice = Bid;
  else
    closePrice = Ask;

  int tickets[1];
  tickets[0] = Ticket;
  
  for (int i = 0;  i < ArraySize(tickets);  i++)
  {
    if (OrderSelect(tickets[i], SELECT_BY_TICKET))
    {
      if (OrderStopLoss() > 0)
      {
        if (isLong)
          profitAt$ += ((price - OrderOpenPrice()) / Point) * MarketInfo(Symbol(), MODE_TICKVALUE) * OrderLots();
        else
          profitAt$ += ((OrderOpenPrice() - price) / Point) * MarketInfo(Symbol(), MODE_TICKVALUE) * OrderLots();
      }    
    }
  }
  return (profitAt$);
}


double _GetProfitAtStop$()
{
  return (_GetProfitAtPrice$(_GetTradeStop()));
}


double _GetPipsAtPrice(double price)
{
  double pipsAt = 0.0;
  bool isLong = _IsTradeLong();
  
  int tickets[1];
  tickets[0] = Ticket;
    
  for (int i = 0; i < ArraySize(tickets); i++)
  {
    if (OrderSelect(tickets[i], SELECT_BY_TICKET))
      if (OrderStopLoss() > 0)
      {
        if (isLong)
          pipsAt += (price - OrderOpenPrice())/Point/POINT_FACTOR;
        else
          pipsAt += (OrderOpenPrice() - price)/Point/POINT_FACTOR;
      }
  }
  return (pipsAt);
}


double _GetPipsAtStop()
{
  return (_GetPipsAtPrice(_GetTradeStop()));
}


double _GetCurrentOpenPrice()
{
  if (OrderSelect(Ticket, SELECT_BY_TICKET))
    return (OrderOpenPrice());
  else
  {
    if (_IsTradeLong())
      return (Ask);
    else
      return (Bid);
  }
}


double _GetCurrentClosePrice()
{
  if (_IsTradeLong())
    return (Bid);
  else
    return (Ask);
}


double _GetTradeLots()
{
  if (Ticket != 0)
  {
    OrderSelect(Ticket, SELECT_BY_TICKET);
    return (OrderLots());
  }
  else
  {
    return (_CalculateLots());      
  }
}


double _GetTradeStop()
{
  if (Ticket != 0)
  {
    if (OrderSelect(Ticket, SELECT_BY_TICKET))
      return (OrderStopLoss());
    else
      return (-1.0);
  }
  else
  {
    double linePrice = _SLBarGet();
    if (linePrice > 0)
      return (linePrice);
    else
    {
      double candidatePrice;
      if (_IsTradeLong())
      {
        _FindRecentLow(candidatePrice);
        candidatePrice = candidatePrice - (Ask-Bid);
      }
      else
      {
        _FindRecentHigh(candidatePrice);
        candidatePrice = candidatePrice + (Ask-Bid);
      }
      return (candidatePrice);
    }
  }
}


double _GetTradeEntry()
{
  if (OrderSelect(Ticket, SELECT_BY_TICKET))
    return (OrderOpenPrice());
  else
    return (-1.0);
}


int _dir()
{
  if (_IsTradeLong())
    return (+1);
  else
    return (-1);
}


double _GetTradeTakeProfit()
{
  if (Ticket != 0)
  {
    if (OrderSelect(Ticket, SELECT_BY_TICKET))
      return (OrderTakeProfit());
    else
      return (_GetRecommendedTakeProfit());
  }
  else
    return (-1.0);
}


double _GetRecommendedTakeProfit()
{
  double price = _GetCurrentOpenPrice();
  double sl;
  if (_InTrade())
    sl = MaxSL;
  else
    sl = _GetTradeStop();

  if (_IsTradeLong())
    return (price + (price - sl) * RewardRiskFactor);
  else
    return (price - (sl - price) * RewardRiskFactor);
}


double _GetEffectiveEquity()
{
  if (NominalBalanceForRisk$ > 0)
    return (NominalBalanceForRisk$);
  else
    return (AccountEquity());
}


double _CalculateLots()
{
  if (LotsOrRisk == USE_LOTS)
    return (LOT[SELECTED_LOT]);
  else
  {
    double riskFactor = RISK[SELECTED_RISK] / 100.0;
  
    double risk$ = _GetEffectiveEquity() * riskFactor;
    double riskPips;
  
    if (_IsTradeLong())
      riskPips = (_GetCurrentOpenPrice() - _GetTradeStop())/Point/POINT_FACTOR;
    else
      riskPips = (_GetTradeStop() - _GetCurrentOpenPrice())/Point/POINT_FACTOR;

    double lotSize = (risk$ / riskPips) / ((MarketInfo(Symbol(), MODE_TICKVALUE)*POINT_FACTOR));
    if (MaxLots > 0  &&  lotSize > MaxLots)
      lotSize = MaxLots;
      
    return (MathMax(lotSize, 0.01));
  }
}


double _GetBEPrice()
{
  if (MoveStopToBEFactor > 0.0 && MoveStopToBEFactor < 1.0)
  {
    if (!OrderSelect(Ticket, SELECT_BY_TICKET))
      return (0.0);

    if (OrderTakeProfit() == 0.0)
      return (0.0);
    
    if (OrderType() == OP_BUY || OrderType() == OP_BUYLIMIT || OrderType() == OP_BUYSTOP)
      return (OrderOpenPrice() + (OrderTakeProfit() - OrderOpenPrice()) * MoveStopToBEFactor);
    else
      return (OrderOpenPrice() - (OrderOpenPrice() - OrderTakeProfit()) * MoveStopToBEFactor);
  }
  else
    return (0.0);
}


void _ManageTrade()
{
  if (!_InTrade())
    return;
    
  if (!_IsTradeBEOrBetter()  &&  MoveStopToBEFactor > 0.0  &&  MoveStopToBEFactor < 1.0)
  {    
    double closePrice = _GetCurrentClosePrice();
    double bePrice = _GetBEPrice();
    bool isLong = _IsTradeLong();
    bool moveStop = false;
    
    if (bePrice > 0.0)
    {
      if (isLong && closePrice > bePrice)
        moveStop = true;
      else if (!isLong && closePrice < bePrice)
        moveStop = true;
    }
    
    if (moveStop)
    {
      _SLBarClear();
      _MoveStopWithComment(Ticket, _GetTradeEntry(), false);
    }
  }
}


void _EnterNow()
{
  double price = _GetCurrentOpenPrice();
  double lots = _GetTradeLots();
  
  double tp;
  double sl;
  
  int op;
  if (ActiveMode == MD_LONG)
    op = OP_BUY;
  else if (ActiveMode == MD_SHORT)
    op = OP_SELL;
  else
    return;
        
  tp = _GetRecommendedTakeProfit();
  if (op == OP_BUY)
    sl = _GetTradeStop() - (Ask-Bid);
  else
    sl = _GetTradeStop() + (Ask-Bid);
  _SLBarClear();
  
  _ResetStats();

  int ticket = OrderReliableSend(Symbol(), op, lots, price, MarketInfo(Symbol(), MODE_SPREAD), 0, 0, GetOrderComment(Magic), Magic, 0);
  if (ticket > 0)
  {
    OrderSelect(ticket, SELECT_BY_TICKET);    
    if (!OrderReliableModify(ticket, OrderOpenPrice(), NormalizeDouble(sl, Digits), NormalizeDouble(tp, Digits), OrderExpiration()))
      MultiComment("ERROR - Failed setting sell stoploss " + ErrorDescription(GetLastError()));
    else
      MultiComment("Opened order " + ticket);
      
    Ticket = ticket;
    LastSL = sl;
    MaxSL = sl;
    
    _InitButtons();
  }
}


void _CloseTicket(int ticket, double lots=0.0)
{
  if (!OrderSelect(ticket, SELECT_BY_TICKET))
    return;
    
  if (lots <= 0)
    lots = OrderLots();

  if (OrderReliableClose(ticket, lots, _GetCurrentClosePrice(), Ask-Bid))
    MultiComment("Closed ticket " + ticket);
  else
    MultiComment("Close failed");
}


bool _MoveStopWithComment(int ticket,  double price,  bool overrideFailsafe=false)
{
  double diffPips;
  if (_IsTradeLong())
  {
    if (price >= Bid)
      return (false);
    diffPips = (_GetCurrentOpenPrice() - price) / Point / POINT_FACTOR;
  }
  else
  {
    if (price <= Ask)
      return (false);
    diffPips = (price - _GetCurrentOpenPrice()) / Point / POINT_FACTOR;
  }
  
  MultiComment("SL set " + DoubleToStr(price, Digits) + " (" + DoubleToStr(diffPips, 1) + "  pips)");
  
  return (_MoveStop(ticket, price, overrideFailsafe));
}


#define MINIMUM_STOP_MOVE_POINTS  10
bool _MoveStop(int ticket,  double price,  bool overrideFailsafe=false)
{
  if (OrderSelect(ticket, SELECT_BY_TICKET))
  {
    // -- Don't move stop against an open trade 
    if (!overrideFailsafe)
    {
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
    }
  
    double diff = MathAbs(OrderStopLoss() - price);
    double diffPoints = diff / Point;
    
    //if (!overrideFailsafe && diffPoints < (MINIMUM_STOP_MOVE_POINTS / (1.0*POINT_FACTOR)))
    //  return (true);
    
    bool ok = OrderReliableModify(ticket, OrderOpenPrice(), price, OrderTakeProfit(), 0);
    if (ok)
    {
      LastSL = price;
      if (_IsTradeLong())
      {
        if (price < MaxSL)
          MaxSL = price;
      }
      else
      {
        if (price > MaxSL)
          MaxSL = price;
      }
      return (true);
    }
    else
    {
      MultiComment("OrderModify failed: " + GetLastError());
      return (false);
    }
  }
  else
  {
    Print("OrderModify select failed: ticket " + ticket + " not found (" + GetLastError() + ")");
    return (false);
  }
}


bool _MoveTakeProfitWithComment(int ticket,  double price)
{
  double diffPips;
  if (_IsTradeLong())
  {
    if (price < Ask)
      return (false);
    diffPips = (price - _GetCurrentOpenPrice()) / Point / POINT_FACTOR;
  }
  else
  {
    if (price > Bid)
      return (false);
    diffPips = (_GetCurrentOpenPrice() - price) / Point / POINT_FACTOR;
  }
  
  MultiComment("TP set " + DoubleToStr(price, Digits) + " (" + DoubleToStr(diffPips, 1) + "  pips)");
  
  return (_MoveTakeProfit(ticket, price));
}


bool _MoveTakeProfit(int ticket,  double price)
{
  if (OrderSelect(ticket, SELECT_BY_TICKET))
  {
    bool ok = OrderReliableModify(ticket, OrderOpenPrice(), OrderStopLoss(), price, 0);
    if (ok)
    {
      LastTP = price;
      return (true);
    }
    else
    {
      MultiComment("OrderModify failed: " + GetLastError());
      return (false);
    }
  }
  else
  {
    MultiComment("OrderModify select failed: ticket " + ticket + " not found (" + GetLastError() + ")");
    return (false);
  }
}


int _FindRecentHigh(double& high)
{
  double extremeValue = High[0];
  int extremeBar = 0;
  
  for (int i=1; i<10; i++)
  {
    if (High[i] > extremeValue  &&  High[i] > High[i-1]  &&  High[i] > High[i+1])
    {
      extremeValue = High[i];
      extremeBar = i;
    }   
  }
  
  high = extremeValue;
  return (extremeBar);
}


int _FindRecentLow(double& low)
{
  double extremeValue = Low[0];
  int extremeBar = 0;
  
  for (int i=0; i<10; i++)
  {
    if (Low[i] < extremeValue  &&  Low[i] < Low[i-1]  &&  Low[i] < Low[i+1])
    {
      extremeValue = Low[i];
      extremeBar = i;
    }
  }

  low = extremeValue;  
  return (extremeBar); 
}


int _NextSwingBar(int startHere, bool& isLong)
{
  for (int i=startHere+1; i<Bars; i++)
  {
    if (High[i] > High[i+1]  &&  High[i] > High[i-1])
    {
      isLong = true;
      return (i);
    }
    else if (Low[i] < Low[i+1]  && Low[i] < Low[i-1])
    {
      isLong = false;
      return (i);
    }
  }
}


#define CCI_SENSITIVITY 50
#define APERIOD 8
#define MaxLookback 20

double _CCI(int bar=0)
{
  return (iCCI(NULL,0,APERIOD,PRICE_TYPICAL,bar));
}

double _MA(int bar=0)
{
  return (iMA(NULL,0,10,0,MODE_SMA,PRICE_MEDIAN,bar));
}


bool _IsEntryBar(string& reason, int bar)
{
  /*
    If we're going long...
      If 2 candles back CCI was < 0,
        If from candle 2..n, before CCI was >50 it was <-50
          If 1 candle back CCI was +50, and this candle CCI +50  CCI Valid
      If this candle comes within 25 pippets of SMA(10) 
      ---
      
  [S][^x][^x]
  
  [S] is the first bar.CCI > 50 since a prior bar.CCI < 50
  [^x] is a candidate entry.
  
  Rules
    [S] must be Bar[1] or Bar[2]

    For long
      [^x] Ask must be >= High[S]+1pip
      Ask must be > SMA
      
    For short
      [^x] Bid must be <= Low[S]-1pip
      Bid must be < SMA
    
    [S].Low must be <= SMA+2.4pips
    [S].High must be >= SMA-2.4pips

  If S earlier than Bar[2] then entry=MISSED
  If S = 0 then entry=WAIT for signal completion
  */

  reason = "";
  bool result = true;
  int i;
  int signalBar;
  double entryPrice = _GetCurrentOpenPrice();
  double limitPrice;
  double stopPips;
  
  if (ActiveMode == MD_OFF)
  {
    reason = "Off";
    result = false;
  }
  else if (ActiveMode == MD_LONG)
  {
    if (Ask < _MA(bar))
    {
      reason = "Price < SMA";
      result = false;
    }
    
    // find most recent bar with CCI <-50
    i=bar;
    while (result)
    {
      if (i == bar+MaxLookback)
      {
        reason = "No retrace";
        result = false;
      }
      else if (_CCI(i) <= -50)
        break;
        
      i++;
    }
    
    // from here, find the first candle with CCI >50 (the signal candle)
    while (result && i>bar)
    {
      if (i == bar)
      {
        reason = "Retrace not complete";
        result = false;
      }
      else if (_CCI(i) >= 50)
        break;
      
      i--;
    }
    signalBar = i;

    if (result && signalBar > 0)
    {
      if (Close[signalBar] < _MA(signalBar))
      {
        reason = "Signal closed below MA";
        result = false;
      }
    }
    
    if (result)
    { // Check if signal candle too far from MA
      limitPrice = _MA(bar) + (MaxPipsFromMA*Point*POINT_FACTOR);
      if (Low[signalBar] > limitPrice)
      {
        reason = "Too far from MA " + DoubleToStr((Low[signalBar]-limitPrice)/Point/POINT_FACTOR, 1) + "p";
        result = false;
      }
    }
    
    if (result && signalBar > bar+2)
    {
      reason = "Missed entry";
      result = false;
    }
    
    if (result && signalBar == bar)
    {
      reason = "Retrace not complete";
      result = false;
    }
    
    if (result)
    { 
      if (_CCI(bar) >= 50)
      {
        if (Ask > High[signalBar] + (1*Point*POINT_FACTOR))
        {
          // Entry found
        }
        else
        {
          reason = "Price < signal bar high";
          result = false;
        }
      }
      else
      {
        reason = "CCI not >= 50";
        result = false;
      }
    }

    if (result  &&  MaxStop_Pips > 0)
    {
      stopPips = (_GetTradeStop() - entryPrice)/Point/POINT_FACTOR;
      if (stopPips > MaxStop_Pips)
      {
        reason = "Stop " + DoubleToStr(stopPips,0) + "p > max " + DoubleToStr(MaxStop_Pips,0) + "p";
        result = false;
      }
    }
  }
  else if (ActiveMode == MD_SHORT)
  {
    if (Bid > _MA(bar))
    {
      reason = "Price > SMA";
      result = false;
    }
    
    // find most recent bar with CCI >50
    i=bar;
    while (result)
    {
      if (i == bar+MaxLookback)
      {
        reason = "No retrace";
        result = false;
      }
      else if (_CCI(i) >= 50)
        break;
        
      i++;
    }
    
    // from here, find the first candle with CCI <-50. This is the signal candle.
    while (result && i>bar)
    {
      if (i == bar)
      {
        reason = "Retrace not complete";
        result = false;
      }
      else if (_CCI(i) <= -50)
        break;
      
      i--;
    }
    signalBar = i;

    if (result && signalBar > 0)
    {
      if (Close[signalBar] > _MA(signalBar))
      {
        reason = "Signal closed above MA";
        result = false;
      }
    }
    
    if (result)
    { // Check if signal candle too far from MA
      limitPrice = _MA(bar) - (MaxPipsFromMA*Point*POINT_FACTOR);
      if (High[signalBar] < limitPrice)
      {
        reason = "Too far from MA " + DoubleToStr((limitPrice - High[signalBar])/Point/POINT_FACTOR, 1) + "p";
        result = false;
      }
    }
       
    if (result && signalBar > bar+2)
    {
      reason = "Missed entry";
      result = false;
    }
    
    if (result && signalBar == bar)
    {
      reason = "Retrace not complete";
      result = false;
    }
    
    if (result)
    { 
      if (_CCI(0) <= -50)
      {
        if (Bid < Low[signalBar] - (1*Point*POINT_FACTOR))
        {
          // Entry found
        }
        else
        {
          reason = "Price > signal bar low";
          result = false;
        }
      }
      else
      {
        reason = "CCI not <= -50";
        result = false;
      }
    }
    
    if (result  &&  MaxStop_Pips > 0)
    {
      stopPips = (entryPrice - _GetTradeStop())/Point/POINT_FACTOR;
      if (stopPips > MaxStop_Pips)
      {
        reason = "Stop " + DoubleToStr(stopPips,0) + "p > max " + DoubleToStr(MaxStop_Pips,0) + "p";
        result = false;
      }
    }
  }
  
  return (result);
}


string GetCommentHeader()
{
  string s = Symbol() 
	  + "  Spread: " + DoubleToStr((Ask-Bid)/Point/POINT_FACTOR,1) + " pips";
	
  if (NominalBalanceForRisk$ > 0)
    s = s + "  Nominal Balance: " + GetDollarDisplay(NominalBalanceForRisk$);
  
	if (MoveStopToBEFactor > 0  && MoveStopToBEFactor < 1.0)
    s = s + "  MoveStopToBEFactor: " + DoubleToStr(MoveStopToBEFactor, 2);
    
  if (NormalizeDouble(RewardRiskFactor, 1) != NormalizeDouble(1.0, 1))
    s = s + "  RewardRiskFactor: " + DoubleToStr(RewardRiskFactor, 1);
  

  if (IsTesting())
    s = s + "  Equity: " + GetDollarDisplay(AccountEquity());
  
  s = s + "\n";
  
  return (s);
}


void MultiComment( string text )
{
  string multi = GetCommentHeader();
	for ( int i = MultiCommentLines-1; i > 0; i -- )
	{
		comment[i] = comment[i-1];
	}
	comment[0] = TimeToStr( CurTime(), TIME_DATE | TIME_SECONDS ) + "  -  " + text + "\n";
	for ( i = 0; i < MultiCommentLines; i ++ )
	{
		multi = multi + comment[i];
	}

	Comment(multi);
}


void MultiCommentClear()
{
  for (int i=0; i<MultiCommentLines; i++)
    comment[i] = "";
  Comment(GetCommentHeader());  
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


void SetLabel(string name, int corner, int x, int y, string text, color clr=CLR_NONE, int size=0, string face=fontName)
{
  int windowNumber = 0;
  
  if (ObjectFind(pfx+name) < 0)
    ObjectCreate(pfx+name, OBJ_LABEL, windowNumber, 0,0);
 
  ObjectSet(pfx+name, OBJPROP_XDISTANCE, x);
  ObjectSet(pfx+name, OBJPROP_YDISTANCE, y);
  ObjectSetText(pfx+name, text, size, face, clr);
  
  ObjectSet(pfx+name, OBJPROP_CORNER, corner);
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


double PipsToPrice(double pips)
{
  return (pips * POINT_FACTOR * Point);
}


double PriceToPips(double price)
{
  return (price / Point / POINT_FACTOR);
}


void ParseDelimStringDouble(string s,  string delim,  double& result[])
{
  double tmplist[100];
  int cnt=0;
  int pos=0;
  int lastpos;
  string sItem;
  
  lastpos = 0;
  pos = StringFind(s, delim, lastpos);
  while (pos >= 0  &&  cnt < ArraySize(tmplist))
  {
    sItem = StringSubstr(s, lastpos, (pos - lastpos));
    tmplist[cnt] = StrToDouble(sItem);
    cnt++;
    lastpos = pos+1;
    pos = StringFind(s, delim, lastpos);
  }
  
  ArrayResize(result, cnt);
  for (int i=0; i<cnt; i++)
    result[i] = tmplist[i];
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

