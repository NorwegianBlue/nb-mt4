//+------------------------------------------------------------------+
//|                                           NB - Trade Manager.mq4 |
//|                         Copyright © 2011-2012, Timar Investments |
//|                               http://www.timarinvestments.com.au |
/*
  TODO:  
  + Update the SL & TP Bars during Init, not just when the first tick comes in
  + How to stop TP1 getting lost, when you change timeframes?
    > Add a hidden object (visible on no timeframes) that stores the TP1 value in its description Text.  Could also store the root trade ID, and if
      it doesn't match then delete itself.    
  + Show the % & lots to be closed on the bar, and bar title
  + Do something about refreshing the TP & SL levels if the open price changes

  - TODO: Fixed problems when only using one TP
  - TODO: Fixed problems when minimum lot increment is not 0.01 (i.e. xauusd is 0.05)
  - TODO: Changed from "process on tick" to infinite-loop with polling strategy (when mouse down).

  Version 12
    - Changed status block to show %R and pips
    - Changed status block to remove MRAE and replace with Target
    - Added handling for different "point factors" per symbol

  Version 11
    - Added "Next Bar In"
    - Added EnableOCO

  Version 10
    - Added 2nd TP level.  TP1_Pips, TP1_Factor, TP2_Pips
       -> TP on the order is set to the last TP level (TP2).
          Partial close at the TP1 level is handled by the EA (so it has to be running).
    - Fixed manual ticket mode
    - Fixed MissedByThatMuch mode, added MissedByThatMuch_Active_Pips, and now
      applies MissedByThatMuch_SL_Factor using RRed's factor-of-maximum-achieved method,
      instead of the previous factor-of-profit-target method.

  Version 9
    - Fixed TP line sometimes getting set to price 0
    - No longer displays MAE/MRAE/MFE for a trade if that information is not available.
    - No longer displays final profit in $, if ShowCurrency is false.
  
  Version 8
    - Added TP line
    - Fixed pending handling
    
  Version 7
    - Added interactive stop line
    - Added related trade support. Now allows partial close, and will find all related trades.
    
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

#property copyright "Copyright © 2011-2012, NorwegianBlue"
#property link      "http://sites.google.com/site/norwegianbluesmt4junkyard"

#include <stderror.mqh>
#include <stdlib.mqh>
#include <ptorders.mqh>

#define _VERSION_ 13
double POINT_FACTOR = 10.0;

//---- input parameters
extern int _VERSION_13=_VERSION_;
extern bool Active=true;

extern bool AutoTicket = true;
extern int  Ticket1 = 0;
extern bool EnableOCO = false;
//--
extern bool   IncludeSpread = true;

extern double Stop_Pips = 16;

extern double TP1_Pips = 150;
extern double TP1_Factor = 0.50;
extern double TP2_Pips = 100;

extern double StopToBE_Pips = 10;
extern double LockInAtBE_Pips = 1;

extern double StopToSmall_Pips = 17;
extern double Small_Pips = 5;

extern double StopToHalf_Pips = 32;

extern double MissedByThatMuch_Active_Pips = 5;
extern double MissedByThatMuch_Active_Factor = 0;
extern double MissedByThatMuch_SL_Factor = 0.80;

extern string _1 = "__ Display _____________";
extern string CurrencySymbol = "$";
extern bool  ShowCurrency = false;
extern int   LineSpacing    = 13;
extern color Background = C'24,24,24';

extern bool ShowNextBarIn = true;

extern color StopBar_Colour = Red;
extern color TP1Bar_Colour = Blue;
extern color TP2Bar_Colour = RoyalBlue;

extern color ProfitColour = DarkGreen;
extern color ProfitColourHot = LimeGreen;
extern color LossColour = Maroon;
extern color LossColourHot = Red;


extern bool _debug_ = false;

//+------------------------------------------------------------------+
bool StatsAssigned;

double MFE_pips;
double MFE_$;

double MAE_pips;
double MAE_$;

double MRAE_pips;
double MRAE_$;

//int LastTicket1 = 0;

double LastTP1 = 0;
double LastTP2 = 0;
// We don't track last TP1
double LastSL = 0;


//+------------------------------------------------------------------+
string pfx="nbtm";

#define fontName     "Calibri"
#define boldFontName "Arial Black"
#define fontSize     8

#define NotActiveColor        Red


//+------------------------------------------------------------------+
//| Current Trade Details                                            |

#define maxTickets 50

int OpenTicket;
int ClosedTickets[maxTickets], ClosedTicketsCount;
int AllTickets[maxTickets], AllTicketsCount;

bool TradeLong;


//+------------------------------------------------------------------+
string GetIndicatorShortName()
{
  return("NB - Trade Manager " + Symbol());
}

string GetOrderComment(int magic)
{
  return("NBTradeManager");
}



//+------------------------------------------------------------------+
//| expert initialization function                                   |
//+------------------------------------------------------------------+
bool initialising = false;
int init()
{
  initialising = true;
   
  POINT_FACTOR = GuessPointFactor();

  DeleteAllObjectsWithPrefix(pfx);

  _FindAllRelatedTickets();
  _UICheck();
  
  _UpdateComment();
  _UpdateObjects();
  
  return(0);
}


//+------------------------------------------------------------------+
//| expert deinitialization function                                 |
//+------------------------------------------------------------------+
int deinit()
{
  Comment("");
  if (!_IsTicketOpen(OpenTicket))
  {
    LastTP1 = 0;
    LastTP2 = 0;
    DeleteAllObjectsWithPrefix(pfx);
  }
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
  
  if (OpenTicket == 0)
  {
    _FindAllRelatedTickets();
    if (OpenTicket != 0  &&  !initialising)
    {
      // Trade opened
      if (EnableOCO)
        _DoOCO();
    }
  }

  _UpdateComment();
  _UpdateObjects();
  
  if (!Active)
    return(0);

  _DoTradeManagement();

  _UICheck();
  
  if (OpenTicket == 0)
  {
    LastTP1 = 0;
    LastTP2 = 0;
    _SLBarClear();
  }
  
  _UpdateComment();
  _UpdateObjects();
  
  initialising = false;
  
  return(0);
}


bool _IsTicketOpen(int ticket)
{
  if (OrderSelect(ticket, SELECT_BY_TICKET))
    return (OrderCloseTime() == 0);
  else
    return (false);
}


void _DoOCO()
{
  if (!_IsTicketOpen(OpenTicket))
    return;
  
  string openSymbol = OrderSymbol();
  int i = 0;
  while (i < OrdersTotal())
  {
    i++;
    if (OrderSelect(i, SELECT_BY_POS))
    {
      if (OrderSymbol() == openSymbol  &&  OrderType() != OP_BUY  &&  OrderType() != OP_SELL  &&  OrderMagicNumber() == 0)
      {
        OrderReliableClose(OrderTicket(), OrderLots());
        i = 0;
      }
    }
  }
}


void _DoTradeManagement()
{
  if (!_IsTicketOpen(OpenTicket))
  { // ticket was closed, rescan
    _FindAllRelatedTickets();
  }

  if (OpenTicket != 0)
  {
    _CheckSL();
    _CheckBE();

    if (_GetNextTP() == 1  &&  _TPBarGet(1) > 0)
      _CheckTP1();
  }
}


void _ClosePartial(double lots)
{
  if (!OrderSelect(OpenTicket, SELECT_BY_TICKET))
    return;
  
  OrderReliableClose(OpenTicket, lots);
  _FindAllRelatedTickets();
}


void _CheckTP1()
{
  double lots;
  lots = NormalizeDouble(_GetTotalLots() * TP1_Factor, 2);
  // work out based on minimum trade increment
  if (lots <= 0.01)
    lots = 0.01;
  else if (lots > _GetTotalLots())
    lots = _GetTotalLots();
  
  if (TradeLong)
  {
    if (Bid >= _TPBarGet(1))
      _ClosePartial(lots);
  }
  else
  {
    if (Ask <= _TPBarGet(1))
      _ClosePartial(lots);
  }
}


void _ResetStats()
{
  if (OrderSelect(OpenTicket, SELECT_BY_TICKET))
  {
    StatsAssigned = true;
    MAE_pips = _GetProfitPips();
    MFE_pips = MAE_pips;
    MRAE_pips = 0;
    MAE_$ = _GetProfit$();
    MFE_$ = MAE_$;
    MRAE_$ = 0;
  }
  else
  {
    StatsAssigned = false;
    MAE_pips = 0;
    MFE_pips = 0;
    MRAE_pips = 0;
    MAE_$ = 0;
    MFE_$ = 0;
    MRAE_$ = 0;
  }
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
  SetLine("hbSL", price, StopBar_Colour, STYLE_SOLID, 2);
  _SLBarTextRefresh();
}


void _SLBarTextRefresh()
{
  double price;
  double pips;
  string txt;
  if (ObjectFind(pfx+"hbSL")>=0)
  {
    price = _SLBarGet();
    if (TradeLong)
      pips = (_GetCurrentOpenPrice() - price)/Point/POINT_FACTOR;
    else
      pips = (price - _GetCurrentOpenPrice())/Point/POINT_FACTOR;

    txt = "SL " + DoubleToStr(pips, 0) + " pips";
    SetText("lbSL", Time[0] + (Time[0]-Time[1])*3, price, txt, Red);
    ObjectSetText(pfx+"hbSL", txt, 0);
  }
  else
    DeleteObject("lbSL");
  
  if (ObjectFind(pfx+"hbTP1")>=0)
  {
    price = ObjectGet(pfx+"hbTP1", OBJPROP_PRICE1);
    pips = (_Dir()*price - _Dir()*_GetCurrentOpenPrice())/Point/POINT_FACTOR;

    txt = "TP1 " + DoubleToStr(TP1_Factor*100,0) + "%  " + DoubleToStr(pips, 0) + " pips";
    SetText("lbTP1", Time[0] + (Time[0]-Time[1])*3, price, txt, RoyalBlue);
    ObjectSetText(pfx+"hbTP1", txt, 0);
  }
  else
    DeleteObject("lbTP1");

  if (ObjectFind(pfx+"hbTP2")>=0)
  {
    price = ObjectGet(pfx+"hbTP2", OBJPROP_PRICE1);
    pips = (_Dir()*price - _Dir()*_GetCurrentOpenPrice())/Point/POINT_FACTOR;

    txt = "TP2 " + DoubleToStr((1.0-TP1_Factor)*100,0) +"%  " + DoubleToStr(pips, 0) + " pips";
    SetText("lbTP2", Time[0] + (Time[0]-Time[1])*3, price, txt, RoyalBlue);
    ObjectSetText(pfx+"hbTP2", txt, 0);
  }
  else
    DeleteObject("lbTP2");
}


void _SLBarClear()
{
  DeleteObject("hbSL");
  DeleteObject("lbSL");
  DeleteObject("hbTP1");
  DeleteObject("lbTP1");
  DeleteObject("hbTP2");
  DeleteObject("lbTP2");
}


void _TPBarSet(int tpIndex, double price)
{
  SetLine("hbTP"+tpIndex, price, _GetTPBarColour(tpIndex), STYLE_SOLID, 2);
  _SLBarTextRefresh();
}


double _TPBarGet(int tpIndex)
{
  if (ObjectFind(pfx+"hbTP"+tpIndex)<0)
    return (-1.0);
  else
    return (ObjectGet(pfx+"hbTP"+tpIndex, OBJPROP_PRICE1)); 
}


int _GetNextTP()
{
  return (ClosedTicketsCount+1);
}


int _GetMaxTPIndex()
{
  if (TP1_Factor == 0  ||  TP1_Factor >= 1.0)
    return (1);
  else
    return (2);
}


double _Dir()
{
  if (TradeLong)
    return (+1.0);
  else
    return (-1.0);
}


double _GetTPPips(int tpIndex = 0)
{
  if (tpIndex == 2  &&  TP2_Pips != 0)
    return (TP2_Pips);
  else
    return (TP1_Pips);
}


color _GetTPBarColour(int tpIndex = 0)
{
  if (tpIndex == 2)
    return (TP2Bar_Colour);
  else
    return (TP1Bar_Colour);
}



double _GetRecommendedTakeProfit(int tpIndex)
{
  double TP_Pips = _GetTPPips(tpIndex);
  if (OpenTicket != 0  &&  OrderSelect(OpenTicket, SELECT_BY_TICKET))
  {
    // All orders in a set have the same open price
    double TP_Price;
    TP_Price = OrderOpenPrice() + _Dir() * (PipsToPrice(TP_Pips) + _GetSpread$());
    return (TP_Price);
  }
  else
    return (0.0);
}


void _UICheck()
{
  if (IsMouseDown())
    return;

  if (OpenTicket != 0)
  {
    if (!OrderSelect(OpenTicket, SELECT_BY_TICKET))
      return;
      
    double linePrice;

    if (_SLBarGet()<0)
    { // SL bar not present, or deleted so create it.
      
      _SLBarSet(OrderStopLoss());
    }
    else
    {
      linePrice = _SLBarGet();

      // If the trade's stop is different to the last stop we saw, then something else changed the stop so respect that and move our bar
      if (NormalizeDouble(OrderStopLoss(), Digits) != NormalizeDouble(LastSL, Digits))
      {
        LastSL = OrderStopLoss();
        _SLBarSet(LastSL);
      }
      else
      { // check if bar moved, if so move SL
        if (linePrice > 0  &&  NormalizeDouble(linePrice, Digits) != NormalizeDouble(OrderStopLoss(), Digits))
          _MoveStop(OpenTicket, linePrice, true);
      }
    }
    
    // Price Bar
    // TODO: If order hasn't opened yet (i.e. not OP_BUY or OP_SELL)
    //   Then show a yellow price bar which which entry/exit price can bet set
    //   If the price bar is moved, then move the stop & tp if they become invalid, otherwise leave them
    
    // TP bars
    
    if (_GetNextTP() == 2)
    {
      DeleteObject("hbTP1");
      DeleteObject("lbTP1");
    }
    
    if (_GetNextTP() == 1  ||  _GetNextTP() == 2)
    {
      // The TP1 bar can only be set by moving the bar on the chart, so no handling is required to sync the TP on the actual order
      if (_GetNextTP() == 1  &&  ObjectFind(pfx+"hbTP1")<0)
      {
        if (LastTP1 != 0)
          _TPBarSet(1, LastTP1);
        else
          _TPBarSet(1, _GetRecommendedTakeProfit(1));
      }
      else if (_GetNextTP() == 1)
      {
        if (NormalizeDouble(_TPBarGet(1), Digits) != NormalizeDouble(LastTP1, Digits))
          LastTP1 = _TPBarGet(1);
      }
      else
        LastTP1 = 0;
    
      // Do bars for TP2
      if (_TPBarGet(2)<0)
      {
        LastTP2 = OrderTakeProfit();
        if (LastTP2 == 0)
          LastTP2 = _GetRecommendedTakeProfit(2);
        _TPBarSet(2, LastTP2);
        _MoveTakeProfit(OpenTicket, LastTP2);
      }
      else
      {
        linePrice = _TPBarGet(2);
        
        // If the trade's TP is different to the last TP we saw, then something else changed the TP so respect that and move our bar
        if (NormalizeDouble(OrderTakeProfit(), Digits) != NormalizeDouble(LastTP2, Digits))
        {
          LastTP2 = OrderTakeProfit();
          _TPBarSet(2, LastTP2);
        }
        else
        {
          if (linePrice > 0  &&  NormalizeDouble(linePrice, Digits) != NormalizeDouble(OrderTakeProfit(), Digits))
          {
            LastTP2 = linePrice;
            _MoveTakeProfit(OpenTicket, LastTP2);
          }
        }          
      }
    }

    _SLBarTextRefresh();
    
    if (_GetNextTP() > 2)
    {
      LastTP1 = 0;
      LastTP2 = 0;
      DeleteObject("hbTP1");
      DeleteObject("lbTP1");
      DeleteObject("hbTP2");
      DeleteObject("lbTP2");
    }
  }
  else
  {
    DeleteObject("hbTP1");
    DeleteObject("lbTP1");
    DeleteObject("hbTP2");
    DeleteObject("lbTP2");
    DeleteObject("hbSL");
    DeleteObject("lbSL");
  }
}


bool IsCommentFrom(string comment, int& ticket)
{
  ticket = 0;
  int index = StringFind(comment, "from #");
  if (index >= 0)
  {
    ticket = StrToInteger(StringSubstr(comment, index + 6)); //StringLen("from #")));
    return (true);
  }
  else
    return (false);
}


bool IsCommentTo(string comment, int& ticket)
{
  ticket = 0;
  int index = StringFind(comment, "to #");
  if (index >= 0)
  {
    ticket = StrToInteger(StringSubstr(comment, index + 4)); //StringLen("to #")));
    return (true);
  }
  else
    return (false);
}


bool _FindTicketThatReferencesTicket(int referenceMe,  int& referencer)
{
  for (int i=0; i<OrdersHistoryTotal(); i++)
  {
    if (OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
    {
      int ref;
      if (OrderSymbol() == Symbol()  &&  IsCommentTo(OrderComment(), ref))
      {
        if (ref == referenceMe)
        {
          referencer = OrderTicket();
          return (true);
        }
      }
    }
  }
  referencer = 0;
  return (false);
}


int _CompareClosedTickets_ByTicket(int index1, int index2)
{
  if (ClosedTickets[index1] > ClosedTickets[index2])
    return (+1);
  else if (ClosedTickets[index1] < ClosedTickets[index2])
    return (-1);
  else
    return (0);
}


void _SwapClosedTicket(int index1, int index2)
{
  int itemp;  
  itemp = ClosedTickets[index1];
  ClosedTickets[index1] = ClosedTickets[index2];
  ClosedTickets[index2] = itemp;
}


void _SortClosedTickets_ByMostRecent()
{
  // a[0] to a[n-1] is the array to sort
  int iPos;
  int iMin;
 
  // advance the position through the entire array
  //   (could do iPos < n-1 because single element is also min element)
  for (iPos = 0; iPos < ClosedTicketsCount; iPos++)
  {
    // find the min element in the unsorted a[iPos .. n-1]

    // assume the min is the first element
    iMin = iPos;
    // test against all other elements
    for (int i = iPos+1; i < ClosedTicketsCount; i++)
    {
      // if this element is less, then it is the new minimum 
      if (_CompareClosedTickets_ByTicket(i, iMin) < 0)
        // found new minimum; remember its index
        iMin = i;
    }
    
    // iMin is the index of the minimum element. Swap it with the current position
    if ( iMin != iPos )
      _SwapClosedTicket(iPos, iMin);
  }
}


void _FindAllRelatedTickets_Auto()
{
  int i;
  for (i=0; i<OrdersTotal(); i++)
  {
    if (OrderSelect(i, SELECT_BY_POS))
    {
      if (OrderSymbol() == Symbol()  &&  OrderMagicNumber() == 0)
      {
        OpenTicket = OrderTicket();
        TradeLong = (OrderType() == OP_BUY || OrderType() == OP_BUYLIMIT || OrderType() == OP_BUYSTOP);
        break;
      }
    }
  }
  
  _FindAllRelatedTickets_Internal(OpenTicket);
}


void _FindAllRelatedTickets_Internal(int initialTicket)
{
  int linkedTicket = 0;
  bool skipScan = false; // nasty
  if (initialTicket == 0)
  {
    int mostRecentClosedTicket = 0;
    datetime mostRecentClosedTime = 0;
    
    for (int i=0; i<OrdersHistoryTotal(); i++)
      if (OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
        if (OrderSymbol() == Symbol()  &&  OrderCloseTime() > mostRecentClosedTime &&  (OrderType() == OP_BUY  ||  OrderType() == OP_SELL))
        {
          mostRecentClosedTicket = OrderTicket();
          mostRecentClosedTime = OrderCloseTime();
        }

    if (mostRecentClosedTicket == 0)
      return; // No recent orders
  
    OrderSelect(mostRecentClosedTicket, SELECT_BY_TICKET, MODE_HISTORY);
    ClosedTickets[ClosedTicketsCount] = OrderTicket();
    ClosedTicketsCount++;
  }
  else if (OrderSelect(initialTicket, SELECT_BY_TICKET, MODE_HISTORY)  &&  OrderCloseTime() != 0)
  {
    skipScan = true;

    ClosedTickets[ClosedTicketsCount] = initialTicket;
    ClosedTicketsCount++;

    // our initial ticket is a closed ticket
    // need to work our way back to the open ticket (if there is one)
    while (IsCommentTo(OrderComment(), linkedTicket))
    {
      if (OrderSelect(linkedTicket, SELECT_BY_TICKET, MODE_HISTORY)  &&  OrderCloseTime() != 0)
      {
        ClosedTickets[ClosedTicketsCount] = linkedTicket;
        ClosedTicketsCount++;
      }
      else if (OrderSelect(linkedTicket, SELECT_BY_TICKET))
      {
        OpenTicket = linkedTicket;
        break;
      }
    }
  }

  int nextTicket;
  int maxiterations = 10;
  if (!skipScan  &&  IsCommentFrom(OrderComment(), linkedTicket))
  {
    // The ticket has closed parts, let's find them!
    if (OrderSelect(linkedTicket, SELECT_BY_TICKET, MODE_HISTORY))
    {
      ClosedTickets[ClosedTicketsCount] = linkedTicket;
      ClosedTicketsCount++;
      
      while (_FindTicketThatReferencesTicket(linkedTicket, nextTicket) && maxiterations >0)
      {
        ClosedTickets[ClosedTicketsCount] = nextTicket;
        ClosedTicketsCount++;
        linkedTicket = nextTicket;
        maxiterations--;
      }
    }
  }
  
  if (ClosedTicketsCount > 1)
    _SortClosedTickets_ByMostRecent();
  
  AllTicketsCount=0;
  if (OpenTicket != 0)
  {
    AllTickets[AllTicketsCount] = OpenTicket;
    AllTicketsCount++;
  }
  
  for (i=0; i<ClosedTicketsCount; i++)
  {
    AllTickets[AllTicketsCount] = ClosedTickets[i];
    AllTicketsCount++;
  }
}


void _FindAllRelatedTickets()
{
  bool OpenTicketWas0 = OpenTicket == 0;
  
  OpenTicket = 0;
  ClosedTicketsCount = 0;
  
  if (AutoTicket)
    _FindAllRelatedTickets_Auto();
  else
  {
    if (Ticket1 != 0)
      _FindAllRelatedTickets_Internal(Ticket1);
  }
    
  if (OpenTicketWas0  &&  OpenTicket != 0)
    _ResetStats();
}


string _Debug_Tickets()
{
  string s = "OpenTicket " + OpenTicket + " " + GetPipsDisplay(_GetTicketProfitPips(OpenTicket));
  
  if (ClosedTicketsCount > 0)
  {
    s = s + "  ClosedTickets[] = {";
    for (int cti=0; cti<ClosedTicketsCount; cti++)
    {
      if (cti > 0)
        s = s + ", ";
      s = s + ClosedTickets[cti] + " " + GetPipsDisplay(_GetTicketProfitPips(ClosedTickets[cti]));
    }
    s = s + "}";
  }
  else
    s = s + "  ClosedTicketsCount = 0";
    
  s = s + "\nProfit: " + GetDollarDisplay(_GetProfit$()) + "  " + GetPipsDisplay(_GetProfitPips());
  
  if (_IsTradeInMarket())
    s = s + "\n_IsTradeInMarket()=TRUE ";
  else
    s = s + "\n_IsTradeInMarket()=FALSE ";
    
  if (_IsTradeClosed())
    s = s + "  _IsTradeClosed()=TRUE";
  else
    s = s + "  _IsTradeClosed()=FALSE";
    
  return (s);
}


void _UpdateComment()
{
  string s = "NB Trader Manager V" + _VERSION_;
  //if (_IsTradeComplete())
  //  s = s + "  Trade Complete, Profit: " + GetDollarDisplay(_GetTotalProfit$());
  
  if (EnableOCO)
    s = s + "  EnableOCO";
 
  if(_debug_)
  { 
    s = s + "\n" + _Debug_Tickets();  
  
    s = s + "\nNext TP: " + _GetNextTP() + " TP1: " + DoubleToStr(_TPBarGet(1), Digits) + "  TP2: " + DoubleToStr(_TPBarGet(2), Digits) + " LastTP2: " + DoubleToStr(LastTP2, Digits);
    s = s + "\nLastTP1: " + DoubleToStr(LastTP1, Digits);
  }
  
  Comment(s);
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
int col3offs = 100;

color InfoColor = C'33,33,33';
datetime InfoColor_NextChange;

void _UpdateObjects()
{
  if (IsTesting()) 
    return;
    
  if (_IsTradeInMarket() || _IsTradeClosed())
  {
    _UpdateTradeStats();
    _UpdateInfoPanel();
    _UpdateBackground();
  }
  else
  {
    DeleteAllObjectsWithPrefix(pfx+"lInfo");
    DeleteAllObjectsWithPrefix(pfx+"bkg");
  }

  
  _UpdateNextBarIn();
}


int ColorLagSec = 2;

void _UpdateTradeStats()
{
  if (!_IsTradeInMarket())
  {
    if (_IsTradeClosed())
    {
      if (_GetProfit$() > 0)
        InfoColor = ProfitColour;
      else if (_GetProfit$() < 0)
        InfoColor = LossColour;
      else
        InfoColor = C'33,33,33';
    }
    return;
  }
    
  color clr;
  double profit$;
  double profitPips;
  
  profit$ = _GetProfit$();
  profitPips = _GetProfitPips();
  
  double lastMFE$ = MFE_$;
  double lastMFEPips = MFE_pips;
  
  double lastMAE$ = MAE_$;
  double lastMAEPips = MAE_pips;
  
  if (profit$ > MFE_$)
    MFE_$ = profit$;
    
  if (profitPips > MFE_pips)
    MFE_pips = profitPips;
    
  if (profit$ < MAE_$)
    MAE_$ = profit$;

  if (profitPips < MAE_pips)
    MAE_pips = profitPips;
  
  StatsAssigned = true;

  
  if (profit$ > 0)
  {
    if (profit$ > lastMFE$)
    {
      InfoColor = ProfitColourHot;
      InfoColor_NextChange = TimeCurrent() + ColorLagSec;
    }
    else
    {
      if (TimeCurrent() > InfoColor_NextChange)
        InfoColor = ProfitColour;
    }
  }
  else if (profit$ < 0)
  {
    if (profit$ < lastMAE$)
    {
      InfoColor = LossColourHot;
      InfoColor_NextChange = TimeCurrent() + ColorLagSec;
    }
    else
    {
      if (TimeCurrent() > InfoColor_NextChange)
        InfoColor = LossColour;
    }
  }
  else
    InfoColor = DimGray;
}


double _GetTarget$()
{
  return (_GetTargetPips() * POINT_FACTOR * MarketInfo(Symbol(), MODE_TICKVALUE));
}


double _GetTargetPips()
{
  if (ClosedTicketsCount == 0 && OpenTicket == 0) // No pending, no open
    return (0.0);
  else if (ClosedTicketsCount == 0 && OpenTicket != 0) // We either have a pending order, or an open order not yet at TP1
  {
    if (TradeLong)
    {
      if (_TPBarGet(1) > _TPBarGet(2))
        return ( (_TPBarGet(2) - _GetCurrentOpenPrice()) / Point / POINT_FACTOR );
      else
        return (
                 ( 
                   (_TPBarGet(1) - _GetCurrentOpenPrice())*TP1_Factor + (_TPBarGet(2) - _GetCurrentOpenPrice())*(1.0-TP1_Factor)
                 )
                 / Point / POINT_FACTOR
               );
    }
    else
    {
      if (_TPBarGet(1) < _TPBarGet(2))
        return ( (_GetCurrentOpenPrice() - _TPBarGet(2) ) / Point / POINT_FACTOR );
      else
        return ( (
                   (_GetCurrentOpenPrice() - _TPBarGet(1))*TP1_Factor + (_GetCurrentOpenPrice() - _TPBarGet(2))*(1.0-TP1_Factor)
                 )
                 / Point / POINT_FACTOR
               );
    }
  }
  else 
  { // ClosedTicketsCount>0, OpenTicket!=0
    return (0.0);
  }
}


int col2xoffs = 50;
int col3xoffs = 120;

void _UpdateInfoPanel()
{
  for (int i=0; i<5; i++)
  {
    string s1 = "";
    string s2 = "";
    int y = 3+(LineSpacing*(5-i-1));
    
    bool showItem = true;
    
    switch (i)
    {
      // -- MFE
      case 0:
        s1 = "MFE";
        if (StatsAssigned)
        {
          if (ShowCurrency)
            s2 = GetDollarDisplay(MFE_$); //_GetProfitAtPrice$(TicketShortPeriod, MFE_short_price) + _GetProfitAtPrice$(TicketLongPeriod, MFE_long_price));
          else
            s2 = GetPipsDisplay(MFE_pips);
        }
        else
          showItem = false;
        break;
      
      // -- MAE
      case 1:
        s1 = "MAE";
        if (StatsAssigned)
        {
          if (ShowCurrency)
            s2 = GetDollarDisplay(MAE_$); //_GetProfitAtPrice$(TicketShortPeriod, MAE_short_price) + _GetProfitAtPrice$(TicketLongPeriod, MAE_long_price));
          else
            s2 = GetPipsDisplay(MAE_pips);
        }
        else
          showItem = false;
        break;
      
      // -- Target
      case 2:
        if (StatsAssigned && !_IsTradeClosed())
        {
          s1 = "Target";
          if (ShowCurrency)
            s2 = GetDollarDisplay(_GetTarget$());
          else
            s2 = GetPipsDisplay(_GetTargetPips());
        }
        else
          showItem = false;
        break;
      
      // -- Locked
      case 3:
        if (StatsAssigned && !_IsTradeClosed())
        {
          if (ShowCurrency)
          {
            double netLocked$ = _GetProfitAtStop$();
            if (netLocked$ > 0)
              s1 = "Locked";
            else
              s1 = "Risk";
            s2 = GetDollarDisplay(netLocked$);
          }
          else
          {
            double netLockedPips = _GetPipsAtStop();
            if (netLockedPips > 0)
              s1 = "Locked";
            else
              s1 = "Risk";
            s2 = GetPipsDisplay(netLockedPips);
          }
        }
        else
        {
          if (!_IsTradeInMarket() && _IsTradeClosed())
            s1 = "Final";
          else
            showItem = false;
        }
        break;
      
      // -- Profit
      case 4:
        if (_IsTradeInMarket() || _IsTradeClosed())
        {
          if (_GetProfit$() >= 0)
            s1 = "Profit";
          else
            s1 = "Loss";
        
          if (ShowCurrency)
            s2 = GetDollarDisplay(_GetProfit$());
          else
            s2 = GetPipsDisplay(_GetProfitPips());
        }
        else
          showItem = false;
        break;
    }
    
    if (showItem)
    {
      SetLabel("lInfoT"+i, 9, y, s1, White);
      SetLabel("lInfo"+i, col2xoffs, y, s2, White);
      ObjectSet(pfx+"lInfoT"+i, OBJPROP_CORNER, 2);
      ObjectSet(pfx+"lInfo"+i, OBJPROP_CORNER, 2);
    }
    else
    {
      DeleteObject("lInfoT"+i);
      DeleteObject("lInfo"+i);
    }
  }
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


void _UpdateBackground()
{
  for (int i=0; i<5; i++)
    _DrawBackground(2, 2, 3 + LineSpacing*i, InfoColor, "ggggggg");
}


void _DrawBackground(int corner, int x, int y, color clr, string bkg = "ggggggggg")
{
  y = y - 2;
  SetLabel("bkga"+y, 5, y, bkg, clr, 0, "Webdings");
  ObjectSet(pfx+"bkga"+y, OBJPROP_CORNER, corner);
}


void _DeleteMAEMFE()
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


void _UpdateMAEMFE()
{
  color clr;
  if (StatsAssigned)
  {
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
  else
  {
    DeleteObject("lMRAETitle");
    DeleteObject("lMRAE");
    DeleteObject("lMFETitle");
    DeleteObject("lMFE");
    DeleteObject("lMAETitle");
    DeleteObject("lMAE");
  }
}


double _GetCurrentOpenPrice()
{
  if (ClosedTicketsCount > 0)
  {
    if (OrderSelect(ClosedTickets[ClosedTicketsCount-1], SELECT_BY_TICKET, MODE_HISTORY))
      return (OrderOpenPrice());
    else
      return (0.0);
  }
  else if (OpenTicket != 0)
  {
    if (OrderSelect(OpenTicket, SELECT_BY_TICKET)  ||  OrderSelect(OpenTicket, SELECT_BY_TICKET, MODE_HISTORY))
      return (OrderOpenPrice());
    else
      return (0.0);
  }
  else
    return (0.0);
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


double _GetProfit$()
{
  double profit = 0.0;
  if (OpenTicket != 0)
    profit += _GetTicketProfit$(OpenTicket);
  
  for (int i=0; i<ClosedTicketsCount; i++)
    profit += _GetTicketProfit$(ClosedTickets[i]);
  
  return (profit);
}


double _GetTicketProfitPips(int ticket)
{
  double totalLots = _GetTotalLots();
  
  if (!OrderSelect(ticket, SELECT_BY_TICKET))
    if (!OrderSelect(ticket, SELECT_BY_TICKET, MODE_HISTORY))
      return (0.0);
  
  if (OrderCloseTime() == 0)
  {
    if (OrderType() == OP_BUY)
      return (((Bid - OrderOpenPrice()) / Point / POINT_FACTOR) * (OrderLots() / totalLots));
    else if (OrderType() == OP_SELL)
      return (((OrderOpenPrice() - Ask) / Point / POINT_FACTOR) * (OrderLots() / totalLots));
    else
      return (0.0);
  }
  else
  {
    if (OrderType() == OP_BUY)
      return (((OrderClosePrice() - OrderOpenPrice()) / Point / POINT_FACTOR) * (OrderLots() / totalLots));
    else if (OrderType() == OP_SELL)
      return (((OrderOpenPrice() - OrderClosePrice()) / Point / POINT_FACTOR) * (OrderLots() / totalLots));
    else
      return (0.0);
  }
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


double _GetProfitPips()
{
  double total = 0.0;
  if (OpenTicket != 0)
    total += _GetTicketProfitPips(OpenTicket);
  for (int i=0; i<ClosedTicketsCount; i++)
    total += _GetTicketProfitPips(ClosedTickets[i]);
  return (total);
}


double _GetTicketTP(int ticket)
{
  if (OrderSelect(ticket, SELECT_BY_TICKET) || OrderSelect(ticket, SELECT_BY_TICKET, MODE_HISTORY))
    return (OrderTakeProfit());
  else
    return (0.0);
}

double _GetProfitAtStop$()
{
  double profitAtStop$ = 0.0;
  
  if (OpenTicket != 0  &&  OrderSelect(OpenTicket, SELECT_BY_TICKET)  &&  OrderStopLoss() > 0)
  {
    if (TradeLong)
      profitAtStop$ += ((OrderStopLoss() - OrderOpenPrice()) / Point) * MarketInfo(Symbol(), MODE_TICKVALUE) * OrderLots();
    else
      profitAtStop$ += ((OrderOpenPrice() - OrderStopLoss()) / Point) * MarketInfo(Symbol(), MODE_TICKVALUE) * OrderLots();
  }    

  for (int i=0; i<ClosedTicketsCount; i++)
    profitAtStop$ += _GetTicketProfit$(ClosedTickets[i]);

  return (profitAtStop$);
}


double _GetTotalLots()
{
  double total = 0.0;
  
  if (OpenTicket != 0  &&  OrderSelect(OpenTicket, SELECT_BY_TICKET))
    total += OrderLots();
  
  for (int i=0; i<ClosedTicketsCount; i++)
    if (OrderSelect(ClosedTickets[i], SELECT_BY_TICKET, MODE_HISTORY))
      total += OrderLots();
  
  return (total);
}


double _GetPipsAtStop()
{
  double pipsAtStop = 0.0;
  double totalLots = _GetTotalLots();
  
  if (OpenTicket != 0  &&  OrderSelect(OpenTicket, SELECT_BY_TICKET)  &&  OrderStopLoss() > 0)
  {
    if (TradeLong)
      pipsAtStop += ((OrderStopLoss() - OrderOpenPrice())/Point/POINT_FACTOR) * (OrderLots() / totalLots);
    else
      pipsAtStop += ((OrderOpenPrice() - OrderStopLoss())/Point/POINT_FACTOR) * (OrderLots() / totalLots);
  }
  
  for (int i=0; i<ClosedTicketsCount; i++)
    if (OrderSelect(ClosedTickets[i], SELECT_BY_TICKET, MODE_HISTORY))
    {
      if (TradeLong)
        pipsAtStop += ((OrderClosePrice() - OrderOpenPrice())/Point/POINT_FACTOR) * (OrderLots() / totalLots);
      else
        pipsAtStop += ((OrderOpenPrice() - OrderClosePrice())/Point/POINT_FACTOR) * (OrderLots() / totalLots);
    }
  return (pipsAtStop);  
}


double _GetSpread$()
{
  if (IncludeSpread)
    return (Ask-Bid);
  else
    return (0.0);
}


datetime _GetTradeCloseTime()
{
  datetime maxClose = 0;
  if (OpenTicket != 0)
    return (0); 
  
  for (int i=0; i<ClosedTicketsCount; i++)
  {
    if (OrderSelect(ClosedTickets[i], SELECT_BY_TICKET, MODE_HISTORY))
    {
      if (OrderCloseTime() > maxClose)
        maxClose = OrderCloseTime();
    }
  }
  
  return (maxClose);
}


void _CheckSL(int ticket = 0)
{
  if (ticket == 0)
    ticket = OpenTicket;
    
  if (OrderSelect(ticket, SELECT_BY_TICKET))
  {
    if (OrderComment() == ""  &&  NormalizeDouble(OrderStopLoss(), Digits) == 0)
    {
      double sl;
      
      if (TradeLong)
        sl = OrderOpenPrice() - PipsToPrice(Stop_Pips) - _GetSpread$();
      else
        sl = OrderOpenPrice() + PipsToPrice(Stop_Pips) + _GetSpread$();
        
      _MoveStop(ticket, sl);      
    }
    else if (OrderOpenTime() != 0  &&  OrderCloseTime() == 0)
      _DoMissedByThatMuch(ticket);
  }
}


void _CheckBE()
{
  if (!_IsTradeInMarket())
    return;

  int ticket = OpenTicket;
  
  if (TradeLong)
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


bool _IsTradeInMarket()
{
  if (OpenTicket != 0  &&  OrderSelect(OpenTicket, SELECT_BY_TICKET))
    return ((OrderType() == OP_BUY  ||  OrderType() == OP_SELL) && (OrderCloseTime() == 0));
  else
    return (false);
}


bool _IsTradeClosed()
{
  if (OpenTicket != 0)
    if (OrderSelect(OpenTicket, SELECT_BY_TICKET, MODE_HISTORY))
      return (OrderCloseTime() != 0);
    else
      return (true);
  else if (ClosedTicketsCount > 0)
    return (true);
  else
    return (false);
}


bool _MoveTakeProfit(int ticket,  double price)
{
  if (OrderSelect(ticket, SELECT_BY_TICKET))
  {
    bool ok = OrderReliableModify(ticket, OrderOpenPrice(), OrderStopLoss(), price, 0);
    if (ok)
    {
      OrderSelect(ticket, SELECT_BY_TICKET);
      LastTP2 = OrderTakeProfit();
      _TPBarSet(2, LastTP2);
      return (true);
    }
    else
    {
      Print("OrderModify failed: " + GetLastError());
      return (false);
    }
  }
  else
  {
    Print("OrderModify select failed: ticket " + ticket + " not found (" + GetLastError() + ")");
    return (false);
  }
}


#define MINIMUM_STOP_MOVE_POINTS  2
bool _MoveStop(int ticket,  double price,  bool force=false)
{
  int retries=3;
  while (retries != 0)
  {
    if (OrderSelect(ticket, SELECT_BY_TICKET))
    {
      // -- Don't move stop against an open trade 
      if (OrderType() == OP_BUY)
      {
        if (!force && OrderStopLoss() != 0  &&  price < OrderStopLoss())
          return (true);
      }
      else if (OrderType() == OP_SELL)
      {
        if (!force &&  OrderStopLoss() != 0  &&  price > OrderStopLoss())
          return (true);
      }   
    
      double diff = MathAbs(OrderStopLoss() - price);
      double diffPoints = diff / Point;
      
      if (!force &&  diffPoints < MINIMUM_STOP_MOVE_POINTS)
        return (true);
         
      bool ok = OrderReliableModify(ticket, OrderOpenPrice(), price, OrderTakeProfit(), 0);
      if (!ok)
      {
        Print("OrderModify failed: " + GetLastError());
        Print("  stop="+DoubleToStr(price, Digits));
      }
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
  {
    OrderSelect(ticket, SELECT_BY_TICKET);
    LastSL = OrderStopLoss();
    _SLBarSet(LastSL);
    return (true);
  }
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
    
  double riskPips = priceDifference/Point/POINT_FACTOR;
  
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


#define FIVE_DIGIT 10
#define FOUR_DIGIT 1

int GuessPointFactor(string symbol = "")
{
  if (symbol == "")
    symbol = Symbol();
  string lsym = StringLower(symbol);
  
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
  else if (StringFind(lsym,"oil",0) >= 0)
  {
    //if (Digits >= 2)
    //  return (FIVE_DIGIT);
    //else
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


