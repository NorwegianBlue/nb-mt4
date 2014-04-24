//+------------------------------------------------------------------+
//|                                           NB - Trade Manager.mq4 |
//|                         Copyright © 2011-2012, Timar Investments |
//|                               http://www.timarinvestments.com.au |
/*
  Version 10
    - Added 2 profit targets

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

#define _VERSION_ 10
double POINT_FACTOR = 10.0;

//---- input parameters
extern int _VERSION_10=_VERSION_;
extern bool Active=true;

extern bool AutoTicket = true;
extern int  Ticket1 = 0; 
//--
extern bool   IncludeSpread = true;

extern double TP1_Pips = 15;
extern double TP1_Factor = 0.50;

extern double TP2_Pips = 50;

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
bool StatsAssigned;

double MFE_pips;
double MFE_$;

double MAE_pips;
double MAE_$;

double MRAE_pips;
double MRAE_$;

//int LastTicket1 = 0;

double LastTP = 0;
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
int init()
{
  DeleteAllObjectsWithPrefix(pfx);

  _FindAllRelatedTickets();
  
  POINT_FACTOR = GuessPointFactor();
  
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
  if (OpenTicket == 0)
    _FindAllRelatedTickets();

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

  //_ApplyAutoStop();

  _DoTradeManagement();

  _UICheck();
  
  if (OpenTicket == 0)
    _SLBarClear();  
  
  _UpdateComment();
  _UpdateObjects();
  
  return(0);
}


bool _IsTicketOpen(int ticket)
{
  if (OrderSelect(ticket, SELECT_BY_TICKET))
    return (OrderCloseTime() == 0);
  else
    return (false);
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
  SetLine("hbSL", price, Red, STYLE_SOLID, 2);
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
  
  if (ObjectFind(pfx+"hbTP")>=0)
  {
    price = ObjectGet(pfx+"hbTP", OBJPROP_PRICE1);
    if (TradeLong)
      pips = (price - _GetCurrentOpenPrice())/Point/POINT_FACTOR;
    else
      pips = (_GetCurrentOpenPrice() - price)/Point/POINT_FACTOR;

    txt = "TP " + DoubleToStr(pips, 0) + " pips";
    SetText("lbTP", Time[0] + (Time[0]-Time[1])*3, price, txt, RoyalBlue);
    ObjectSetText(pfx+"hbTP", txt, 0);
  }
  else
    DeleteObject("lbTP");
}


void _SLBarClear()
{
  DeleteObject("hbSL");
  DeleteObject("lbSL");
  DeleteObject("hbTP");
  DeleteObject("lbTP");
}



void _TPBarSet(double price)
{
  SetLine("hbTP", price, Blue, STYLE_SOLID, 2);
  _SLBarTextRefresh();
}



double _GetRecommendedTakeProfit()
{
  double TP_Pips = Stop_Pips*2;
  
  if (OpenTicket != 0  &&  OrderSelect(OpenTicket, SELECT_BY_TICKET))
  {
    double TP_Price;
    if (TradeLong)
      TP_Price = OrderOpenPrice() + PipsToPrice(TP_Pips) + _GetSpread$();
    else
      TP_Price = OrderOpenPrice() - PipsToPrice(TP_Pips) - _GetSpread$();
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
    
    // TP bar.  Only show if in trade.  If in trade, check for movement and set TP based on that.
    if (OpenTicket != 0)
    {
      if (ObjectFind(pfx+"hbTP")<0)
      {
        // TODO: Consider case where stop has been moved into profit. What should TP be then? Do we need to remember initial stop?
        // Not intial. Most extreme. If stop moved away from entry, that's the new extreme as that represents maximum risk
        if (OrderTakeProfit() > 0)
        {
          LastTP = OrderTakeProfit();
          _TPBarSet(LastTP);
        }
        else
        {
          LastTP = _GetRecommendedTakeProfit();
          _TPBarSet(LastTP);
          _MoveTakeProfit(OpenTicket, LastTP);
        }
      }
      else
      {
        linePrice = ObjectGet(pfx+"hbTP", OBJPROP_PRICE1);
        // If the trade's TP is different to the last TP we saw, then something else changed the TP so respect that and move our bar
        if (NormalizeDouble(OrderTakeProfit(), Digits) != NormalizeDouble(LastTP, Digits))
        {
          if (OrderTakeProfit() > 0)
          {
            LastTP = OrderTakeProfit();
            _TPBarSet(LastTP);
          }
          else
          {
            LastTP = _GetRecommendedTakeProfit();
            _TPBarSet(LastTP);
            _MoveTakeProfit(OpenTicket, LastTP);
          }
        }
        else
        { // check if bar moved, if so move TP
          if (linePrice > 0  &&  NormalizeDouble(linePrice, Digits) != NormalizeDouble(OrderTakeProfit(), Digits))
            _MoveTakeProfit(OpenTicket, linePrice);
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
    DeleteObject("hbTP");
    DeleteObject("lbTP");
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
      if (OrderSymbol() == Symbol())
      {
        OpenTicket = OrderTicket();
        TradeLong = (OrderType() == OP_BUY || OrderType() == OP_BUYLIMIT || OrderType() == OP_BUYSTOP);
        break;
      }
    }
  } 

  if (OpenTicket == 0)
  {
    int mostRecentClosedTicket = 0;
    datetime mostRecentClosedTime = 0;
    
    for (i=0; i<OrdersHistoryTotal(); i++)
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

  int linkedTicket, nextTicket;
  int maxiterations = 10;
  if (IsCommentFrom(OrderComment(), linkedTicket))
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


void _FindAllRelatedTickets_Manual()
{
  if (Ticket1 == 0)
    return;
    
  // TODO:
}


void _FindAllRelatedTickets()
{
  bool OpenTicketWas0 = OpenTicket == 0;
  
  OpenTicket = 0;
  ClosedTicketsCount = 0;
  
  if (AutoTicket)
    _FindAllRelatedTickets_Auto();
  else
    _FindAllRelatedTickets_Manual();
    
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
    
  return (s);
}


void _UpdateComment()
{
  string s = "NB Trader Manager V" + _VERSION_;
  //if (_IsTradeComplete())
  //  s = s + "  Trade Complete, Profit: " + GetDollarDisplay(_GetTotalProfit$());
  
  //s = s + "\n" + _Debug_Tickets();  
  
  s = s + "  TP1 Factor: " + DoubleToStr(TP1_Factor, 2);
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
    StatsAssigned = true;
    
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
  else if (OpenTicket == 0  &&  ClosedTicketsCount > 0)
  {
    if (ShowCurrency)
    {
      dProfit = _GetProfit$();
      if (dProfit > 0)
        clr = Green;
      else if (dProfit < 0)
        clr = Red;
      else
        clr = White;
      if (dProfit > 0)
        SetLabel("lProfit", 10, 10, "Final Profit " + CurrencySymbol + DoubleToStr(dProfit,2), clr);
      else if (dProfit < 0)
        SetLabel("lProfit", 10, 10, "Final Loss (" + CurrencySymbol + DoubleToStr(dProfit,2) + ")", clr);
      else
        SetLabel("lProfit", 20, 10, "Break even", clr);
    }
    else
    {
      dProfit = _GetProfitPips();
      if (dProfit > 0)
        clr = Green;
      else if (dProfit < 0)
        clr = Red;
      else
        clr = White;
      if (dProfit > 0)
        SetLabel("lProfit", 10, 10, "Final Profit " + GetPipsDisplay(dProfit), clr);
      else if (dProfit < 0)
        SetLabel("lProfit", 10, 10, "Final Loss " + GetPipsDisplay(dProfit), clr);
      else
        SetLabel("lProfit", 20, 10, "Break even", clr);
    }

    ObjectSet(pfx+"lProfit", OBJPROP_CORNER, 2);
    DeleteObject("lProfitTitle");

    if (MFE_$ != 0.0)
    {
      DeleteObject("lProfitAtStopTitle");
      //SetLabel("lProfitAtStop", 10, 10+ (fontSize+2)*1, "Efficiency " + DoubleToStr((dProfit/MFE_$)*100,0) + "%", clr);
      //ObjectSet(pfx+"lProfitAtStop", OBJPROP_CORNER, 2);
    }

    _UpdateBackground();
    _UpdateMAEMFE();
  }
  else
  {
    _DeleteMAEMFE();
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


double _GetProfitPips()
{
  double total = 0.0;
  if (OpenTicket != 0)
    total += _GetTicketProfitPips(OpenTicket);
  for (int i=0; i<ClosedTicketsCount; i++)
    total += _GetTicketProfitPips(ClosedTickets[i]);
  return (total);
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
  }
  else if (OrderOpenTime() != 0  &&  OrderCloseTime() == 0)
    _DoMissedByThatMuch(ticket);
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
  else
    return (true);
}


bool _MoveTakeProfit(int ticket,  double price)
{
  if (OrderSelect(ticket, SELECT_BY_TICKET))
  {
    bool ok = OrderReliableModify(ticket, OrderOpenPrice(), OrderStopLoss(), price, 0);
    if (ok)
    {
      OrderSelect(ticket, SELECT_BY_TICKET);
      LastTP = OrderTakeProfit();
      _TPBarSet(LastTP);
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


#define MINIMUM_STOP_MOVE_POINTS  10
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


