//+------------------------------------------------------------------+
//|                                           NB - Trade Tracker.mq4 |
//|                             Copyright © 2011-2014, NorwegianBlue |
/*
  Watches your trades, keeps stats like MAE MFE and logs results into a form convenient
  for importing into spreadsheets.

  - Attach to a chart that receives ticks frequently, such as eur/usd
  
  Version 7
    Support MT4 Build 600+  
  Version 6
    Handle commission by merging it with swap
  Version 5
    Added GuessPointSize
  Version 4
    Added Reset Risk button
    Added "Tick all charts"
*/

// TODO: Handle case when TP is not set
// TODO: Handle case when MaxSL is wrong and we need to reset it.  Delete MaxSL label?
// TODO:   Find the case where MaxSL goes wrong when an at-market order is entered

//+------------------------------------------------------------------+
#property copyright "Copyright © 2011-2014, NorwegianBlue"
#property link      "http://sites.google.com/site/norwegianbluesmt4junkyard"


#include <stderror.mqh>
#include <http51.mqh>
#include <WinUser32.mqh>

extern string _VERSION_7 = "7";

extern string _1 = "__ Output _______";
extern string StateFile = "NBTT_state.csv";
extern string ResultsFile = "NBTT_results.csv";
extern string AppName = "test";

extern string Log_HTTP = ""; //http://forex.plasmatech.com/trade_complete.php?";
extern string Log_HTTP2 = "https://docs.google.com/macros/exec?service=AKfycbzhcc5KZZ6cpaFU9gVQ1q4R9_vx7qqZO7uhn8He&";
extern bool Log_Email = true;
extern string Log_EmailSubject = "Trade Result";

//extern string GoogleUsername = "";
//extern string GooglePassword = "";
//extern string GoogleTablename = "";

extern string _2 = "__ Display _____________";
extern int    MaxOpenTrades = 30;
extern int    MaxClosedTrades = 10;
extern string CurrencySymbol = "$";
extern color  TextColor = White;
extern int    ExtraLineSpacing = 2;
extern color  Background = Black;
extern color  AltBackground = C'32,32,32';

extern int    RefreshIntervalMS = 100;

#define pfx          "nbtt"
#define fontName     "Calibri"
#define boldFontName "Arial Black"
#define fontSize     6

/*
  Layout

  [0]      [1]     [2]       [3]         [4]      [5]      [6]   [7]   [8]      [9]        [10]
  Ticket   Symbol  Hold      MaxRisk(p)  Profit%  Target%  MAE%  MFE%  Profit$  Profit(p)  Comment
  12345678 eurusd  10d59m59s

  
  
  New Layout
  
  [0]      [1]    [2]                  [3]             [4]               [5]           [6]           [7]     [8]       [9]
  Ticket   Symbol Profit               Target          MAE               MFE           Risk          Hold    Comment
  12345678 eurusd (12%) ($10) (10.3p)  200% $300 25p   (12%)($12) (12p)  15% $15 15p   100% $50 50p  10d59m  xxxxx     [Reset Risk]
   
*/

double POINT_FACTOR = 10;  // Use 1 for 4-digit

// Layout
double LXOFFSET = 5;
double LW[9] =        {64,  56,  150, 150, 150, 150, 150, 55, 200};
               // { 0, 64, 120, 170, 220, 270, 330, 380, 430, 480, 535, 560 };
double LX[10];
string LXHEADER[9] =  {"Ticket",  "Symbol",  "Profit", "Target", "MAE", "MFE", "Risk", "Age", "Comment"};
string LXHEADER2[9] = {"_________", "_______", "_______________________", "_______________________", "_______________________", "_______________________", "_______________________", "______", "______________________"};
//string LXHEADER2[11] = {"ggggggggg", "ggggggg", "ggggggggggggggggggggggg", "", "", "ggggggg", "gggggg", "gggggg", "gggggg", "gggggg", "gggggggggggggggggggggg"};

double LYOFFSET = 26;

// Data

bool   IsFull = false;
bool   DisplayDirty[];
int    Ticket[];   // ticket of 0 means slot not used
double MaxSL[];
double MFE_Dlr[];
double MFE_price[];
double MAE_Dlr[];
double MAE_price[];
string CommentStr[];
string DebugStr[];

bool FirstIteration;

void OnInit()
{
  FirstIteration = true;
  
  ArrayResize(DisplayDirty, MaxOpenTrades);
  ArrayResize(Ticket, MaxOpenTrades);
  ArrayResize(MaxSL, MaxOpenTrades);
  ArrayResize(MFE_Dlr, MaxOpenTrades);
  ArrayResize(MFE_price, MaxOpenTrades);
  ArrayResize(MAE_Dlr, MaxOpenTrades);
  ArrayResize(MAE_price, MaxOpenTrades);
  ArrayResize(CommentStr, MaxOpenTrades);
  ArrayResize(DebugStr, MaxOpenTrades);

  ArrayInitialize(Ticket, 0);
  
  for (int i=0; i < ArraySize(CommentStr); i++)
    CommentStr[i] = "";

  LX[0] = 0;
  for (i=0; i < ArraySize(LW); i++)
    LX[i+1] = LX[i] + LW[i];

  _LoadState();

  _CheckForChanges();
  _UpdateDisplay();  
}


void OnDeinit(const int reason)
{
  Comment("");
  DeleteAllObjectsWithPrefix(pfx);
}


void OnTick()
{
  while(!IsStopped())
  {
    RefreshRates();
    _CheckForChanges();
    _CheckButtons();
    _UpdateDisplay();  
    _SaveStatePeriodically();
    
    Sleep(RefreshIntervalMS);
  }
}


bool _IsTicketOpen(int ticket)
{
  if (OrderSelect(ticket, SELECT_BY_TICKET))
    if (OrderCloseTime() == 0)
      return (true);

  return (false);
}


bool _CheckButtonExists(string name)
{
  return (ObjectFind(pfx+name) >= 0);
}


void _CheckButtons()
{
  if (FirstIteration)
    return;
    
  int row=0;
  for (int i=0; i<ArraySize(Ticket); i++)
  {
    if (Ticket[i] != 0)
    {
      if (!_CheckButtonExists("c9r"+(row+2)))
      {
        if (OrderSelect(Ticket[i], SELECT_BY_TICKET))
          MaxSL[i] = OrderStopLoss();
      }
      row++;
    }
  }
}


void _CheckForChanges()
{
  string s = "t:" + OrdersTotal() + "  ";

  int currentTickets[];
  int currentTicketsCount=0;
  ArrayResize(currentTickets, MaxOpenTrades);
   
  int i;
  for (i=0; i<ArraySize(Ticket); i++)
  {
    if (Ticket[i] != 0)
    {
      currentTickets[currentTicketsCount] = Ticket[i];
      currentTicketsCount++;
    }
  }

  int closedTickets[];
  ArrayResize(closedTickets, MaxOpenTrades);
  int closedTicketsCount=0;
  
  for (i=0; i<currentTicketsCount; i++)
  {
    if (!_IsTicketOpen(currentTickets[i]))
    {
      closedTickets[closedTicketsCount] = currentTickets[i];
      closedTicketsCount++;
    }
  }
  
  // -- Log the results of all the closed tickets, and remove the from the Ticket[] array
  for (i=0; i<closedTicketsCount; i++)
    _LogTradeResult(closedTickets[i]);
  
  // -- Find newly opened tickets, and update existing tickets
  int j, k;
  for (i=0; i<OrdersTotal(); i++)
  {
    if (OrderSelect(i, SELECT_BY_POS))
    {
      if (OrderType() == OP_BUY || OrderType() == OP_SELL)
      {
        for (j=0; j<ArraySize(Ticket); j++)
        {
          if (Ticket[j] == OrderTicket())
            break;
        }
        
        if (j < ArraySize(Ticket))
        { // update
          double p;
          if (OrderType() == OP_BUY)
          {
            if (OrderStopLoss() != 0 && MaxSL[j] == 0)
              MaxSL[j] = OrderStopLoss();

            p = _GetClosePrice(OrderTicket());              
            if (MFE_price[j] < p)
              MFE_price[j] = p;
              
            if (MAE_price[j] > p)
              MAE_price[j] = p;
          }
          else
          {
            if (OrderStopLoss() != 0 && MaxSL[j] == 0)
              MaxSL[j] = OrderStopLoss();

            p = _GetClosePrice(OrderTicket());
            if (MFE_price[j] > p)
              MFE_price[j] = p;
              
            if (MAE_price[j] < p)
              MAE_price[j] = p;
          }
          
          p = _GetProfitDlr(OrderTicket());
          if (MFE_Dlr[j] < p)
            MFE_Dlr[j] = p;
            
          if (MAE_Dlr[j] > p)
            MAE_Dlr[j] = p;
        }
        else
        { // new
          for (k = 0; k<ArraySize(Ticket); k++)
          {
            if (Ticket[k] == 0)
              break;
          }
          if (k < ArraySize(Ticket))
          {
            Ticket[k] = OrderTicket();
            MaxSL[k] = OrderStopLoss();
            MFE_Dlr[k] = _GetProfitDlr(OrderTicket());
            MAE_Dlr[k] = MFE_Dlr[k];
            MFE_price[k] = _GetClosePrice(OrderTicket());
            MAE_price[k] = MFE_price[k];
          }
        }
      }
    }
  }
  _SortTickets();
}


int _CompareTickets_ByTicket(int index1, int index2)
{
  if (Ticket[index1] > Ticket[index2])
    return (+1);
  else if (Ticket[index1] < Ticket[index2])
    return (-1);
  else
    return (0);
}


void _SwapTicket(int index1, int index2)
{
  int itemp;
  double dtemp;
  string stemp;
  
  itemp = Ticket[index1];
  Ticket[index1] = Ticket[index2];
  Ticket[index2] = itemp;
  
  dtemp = MaxSL[index1];
  MaxSL[index1] = MaxSL[index2];
  MaxSL[index2] = dtemp;
  
  dtemp = MFE_Dlr[index1];
  MFE_Dlr[index1] = MFE_Dlr[index2];
  MFE_Dlr[index2] = dtemp;
  
  dtemp = MAE_Dlr[index1];
  MAE_Dlr[index1] = MAE_Dlr[index2];
  MAE_Dlr[index2] = dtemp;
  
  dtemp = MFE_price[index1];
  MFE_price[index1] = MFE_price[index2];
  MFE_price[index2] = dtemp;
  
  dtemp = MAE_price[index1];
  MAE_price[index1] = MAE_price[index2];
  MAE_price[index2] = dtemp;
  
  stemp = CommentStr[index1];
  CommentStr[index1] = CommentStr[index2];
  CommentStr[index2] = stemp;
  
  stemp = DebugStr[index1];
  DebugStr[index1] = DebugStr[index2];
  DebugStr[index2] = stemp;
}


void _SortTickets()
{
  /* a[0] to a[n-1] is the array to sort */
  int iPos;
  int iMin;
 
  /* advance the position through the entire array */
  /*   (could do iPos < n-1 because single element is also min element) */
  for (iPos = 0; iPos < ArraySize(Ticket); iPos++)
  {
    /* find the min element in the unsorted a[iPos .. n-1] */

    /* assume the min is the first element */
    iMin = iPos;
    /* test against all other elements */
    for (int i = iPos+1; i < ArraySize(Ticket); i++)
    {
      /* if this element is less, then it is the new minimum */  
      if (_CompareTickets_ByTicket(i, iMin) < 0)
        /* found new minimum; remember its index */
        iMin = i;
    }
    
    /* iMin is the index of the minimum element. Swap it with the current position */
    if ( iMin != iPos )
      _SwapTicket(iPos, iMin);
  }
}



double OTF(int orderType)
{
  if (orderType == OP_BUY || orderType == OP_BUYSTOP || orderType == OP_BUYLIMIT)
    return (+1.0);
  else
    return (-1.0);
}


double SafeDiv(double num, double div)
{
  if (div == 0)
    return (0.0);
  else
    return (num/div);
}


void _UpdateDisplay()
{
  FirstIteration = false;
  
  int row = 0;
  int col = 0;
  for (col = 0; col < ArraySize(LXHEADER); col++)
  {
    SetLabel("lxhead"+col, 0, _GetX(col), _GetY(0), LXHEADER[col], TextColor, 8);
    ObjectSetInteger(0, "lxhead"+col, OBJPROP_ZORDER, 1);

    SetLabel("lxhead2"+col,0, _GetX(col), _GetY(1) -5, LXHEADER2[col], TextColor, 8);
    ObjectSetInteger(0, "lxhead2"+col, OBJPROP_ZORDER, 1);
  }
  
  _DrawBackground(_GetY(1), Background);
  _DrawBackground(_GetY(0), Background);
  
  color clr;
  row = 2;
  for (int i=0; i < ArraySize(Ticket); i++)
  {
    if (Ticket[i] != 0)
    {
      if (!OrderSelect(Ticket[i], SELECT_BY_TICKET))
        continue;
      int otf = OTF(OrderType());
      double closePrice = _GetClosePrice(Ticket[i]);     
      int y = _GetY(row);
      string s = "";

      double pointFactor = GuessPointFactor(OrderSymbol());
      //printf("pointFactor: %f", pointFactor);
      //printf("MarketInfo(OrderSymbol(), MODE_POINT): %f", MarketInfo(OrderSymbol(), MODE_POINT));
      //printf("OrderOpenPrice(): %f", OrderOpenPrice());

      double riskPips;
      double stopPct;
      double profitPct;
      double targetPct;
      double profitPips = _GetProfitPips(OrderTicket());
      double MAE_pips = (otf*MAE_price[i] - otf*OrderOpenPrice())/MarketInfo(OrderSymbol(), MODE_POINT)/pointFactor;
      double MFE_pips = (otf*MFE_price[i] - otf*OrderOpenPrice())/MarketInfo(OrderSymbol(), MODE_POINT)/pointFactor;
      double MAEPct;
      double MFEPct;

      if (MaxSL[i] == 0)
      {
        riskPips = 0;
        stopPct = 0;
        profitPct = 0;
        targetPct = 0;
        MAEPct = 0;
        MFEPct = 0;
      }
      else
      {
        riskPips = (otf*OrderOpenPrice() - otf*MaxSL[i])/MarketInfo(OrderSymbol(), MODE_POINT)/pointFactor;
        stopPct = SafeDiv(-_GetPipsAtPrice(OrderTicket(), OrderStopLoss()), riskPips);        
        profitPct = SafeDiv(profitPips, (-_GetPipsAtPrice(OrderTicket(), MaxSL[i])));
        targetPct = SafeDiv(_GetPipsAtPrice(OrderTicket(), OrderTakeProfit()), (-_GetPipsAtPrice(OrderTicket(), MaxSL[i])));
        MAEPct = SafeDiv(MAE_pips, riskPips);
        MFEPct = SafeDiv(MFE_pips, riskPips);
      }
      
      if (_GetProfitDlr(Ticket[i]) >= 0)
      {
        if (profitPips+0.1 >= MFE_pips)
          clr = LawnGreen;
        else
          clr = Green;
      }
      else
      {
        if (profitPips-0.1 <= MAE_pips)
          clr = Red;
        else
          clr = OrangeRed;
      }
      
      SetLabel("c0r"+row, 0, _GetX(0), y, Ticket[i], clr);

      int subcolx = 50;
            
      s = StringLower(OrderSymbol());
      if (OrderType() == OP_BUY)
        s = s + " L";
      else
        s = s + " S";
      SetLabel("c1r"+row, 0, _GetX(1), y, s, clr);

      if (MaxSL[i] == 0)
        s = "NA";
      else
        s = _GetBriefPctDisplay(profitPct);
      SetLabel("c2ar"+row, 0, _GetX(2), y, s, clr);
      SetLabel("c2br"+row, 0, _GetX(2)+subcolx, y, _GetBriefDollarDisplay(_GetProfitDlr(Ticket[i])), clr);
      SetLabel("c2cr"+row, 0, _GetX(2)+2*subcolx, y, _GetBriefPipsDisplay(_GetProfitPips(Ticket[i])), clr);


      // -- Target
      if (OrderTakeProfit() == 0.0)
      {
        SetLabel("c3ar"+row, 0, _GetX(3), y, "no profit target", clr);
        DeleteObject("c3br"+row);
        DeleteObject("c3cr"+row);
      }
      else
      {      
        if (MaxSL[i] == 0)
          SetLabel("c3ar"+row, 0, _GetX(3), y, "NA", clr);
        else
          SetLabel("c3ar"+row, 0, _GetX(3), y, _GetBriefPctDisplay(targetPct), clr);
        
        SetLabel("c3br"+row, 0, _GetX(3)+subcolx, y, _GetBriefDollarDisplay(_GetProfitAtPriceDlr(OrderTicket(), OrderTakeProfit())), clr);
        SetLabel("c3cr"+row, 0, _GetX(3)+2*subcolx, y, _GetBriefPipsDisplay(_GetPipsAtPrice(OrderTicket(), OrderTakeProfit())), clr);
      }


      // -- MAE              
      if (MaxSL[i] == 0)
        SetLabel("c4ar"+row, 0, _GetX(4), y, "NA", clr);
      else
        SetLabel("c4ar"+row, 0, _GetX(4), y, _GetBriefPctDisplay(MAEPct), clr);
      SetLabel("c4br"+row, 0, _GetX(4)+subcolx, y, _GetBriefDollarDisplay(_GetProfitAtPriceDlr(OrderTicket(), MAE_price[i])), clr);
      SetLabel("c4cr"+row, 0, _GetX(4)+2*subcolx, y, _GetBriefPipsDisplay(_GetPipsAtPrice(OrderTicket(), MAE_price[i])), clr);
      
            
      // -- MFE
      if (MaxSL[i] == 0)
        SetLabel("c5ar"+row, 0, _GetX(5), y, "NA", clr);
      else
        SetLabel("c5ar"+row, 0, _GetX(5), y, _GetBriefPctDisplay(MFEPct), clr);       
      SetLabel("c5br"+row, 0, _GetX(5)+subcolx, y, _GetBriefDollarDisplay(_GetProfitAtPriceDlr(OrderTicket(), MFE_price[i])), clr);
      SetLabel("c5cr"+row, 0, _GetX(5)+2*subcolx, y, _GetBriefPipsDisplay(_GetPipsAtPrice(OrderTicket(), MFE_price[i])), clr);
      
      
      // -- Risk
      if (OrderStopLoss() == 0.0)
      {
        SetLabel("c6ar"+row, 0, _GetX(6), y, "NO STOP SET", clr);
        DeleteObject("c6br"+row);
        DeleteObject("c6cr"+row);
      }
      else
      {
        SetLabel("c6ar"+row, 0, _GetX(6), y, _GetBriefPctDisplay(stopPct), clr);
        SetLabel("c6br"+row, 0, _GetX(6)+subcolx, y, _GetBriefDollarDisplay(-_GetProfitAtPriceDlr(OrderTicket(), OrderStopLoss())), clr);
        SetLabel("c6cr"+row, 0, _GetX(6)+2*subcolx, y, _GetBriefPipsDisplay(-_GetPipsAtPrice(OrderTicket(), OrderStopLoss())), clr);
      }
      
      SetLabel("c7r"+row, 0, _GetX(7), y, _GetAge(OrderOpenTime(), OrderCloseTime()), clr);
      SetLabel("c8r"+row, 0, _GetX(8), y, CommentStr[i] + " | " + OrderComment() + "  " + DebugStr[i], clr);
      
      SetLabel("c9r"+row, 0, _GetX(9), y, "[Reset Risk]", TextColor);
      
      if ((row % 2) == 0)
        _DrawBackground(y-1, AltBackground);
      else
        _DrawBackground(y-1, Background);
      
      row++;
    }
  }
  
  for ( ; row < ArraySize(Ticket); row++)
  {
    for (col = 0; col < ArraySize(LXHEADER); col++)
    {
      if (col >= 2 && col <= 6)
      {
        DeleteObject("c"+col+"ar"+row);
        DeleteObject("c"+col+"br"+row);
        DeleteObject("c"+col+"cr"+row);
      }
      else
        DeleteObject("c"+col+"r"+row);
    }
  }
}


string _GetSummary(double pct, double Dlr, double pips,  bool hideZero = true)
{
  string s = "";
  if (!hideZero  ||  pct != 0.0)
    s = s + _GetBriefPctDisplay(pct);
  
  if (!hideZero  ||  Dlr != 0.0)
  {
    if (s != "")
      s = s + " ";
    s = s + _GetBriefDollarDisplay(Dlr);
  }
  
  if (!hideZero  ||  pips != 0.0)
  {
    if (s != "")
      s = s + " ";
    s = s + _GetBriefPipsDisplay(pips);
  }
  
  return (s);
}


void _DrawBackground(int y, color clr)
{
  string bkg = "gggggggggggggggggggggggggggggggggggggggggggggggggggggg";
  
  //if (ObjectFind(pfa+"bkga"+y) < 0)
  //  ObjectCreate(pfx+"bkga"+y, OBJ_RECTANGLE_LABEL, 0, 
  //SetLabel("bkga"+y, 0, 0, y, bkg, clr, 0, "Webdings");
  //SetLabel("bkgb"+y, 0, 400, y, bkg, clr, 0, "Webdings");
}


string _GetAge(datetime startTime, datetime endTime)
{
  string s;
  int elapsedSeconds;
  if (endTime == 0)
    elapsedSeconds = TimeCurrent() - startTime;
  else
    elapsedSeconds = endTime - OrderOpenTime();
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


double _GetClosePrice(int ticket)
{
  if (OrderSelect(ticket, SELECT_BY_TICKET))
  {
    if (OrderCloseTime() == 0)
    {
      if (OrderType() == OP_BUY)
        return (MarketInfo(OrderSymbol(), MODE_BID));
      else
        return (MarketInfo(OrderSymbol(), MODE_ASK));
    }
    else
      return (OrderClosePrice());
  }
  else
    return (MarketInfo(OrderSymbol(), MODE_BID));
}


double _GetProfitDlr(int ticket)
{
  double total=0.0;
  if (OrderSelect(ticket, SELECT_BY_TICKET))
    total += OrderProfit() + OrderSwap() + OrderCommission();
  return (total);
}


double _GetProfitAtPriceDlr(int ticket, double price)
{
  if (OrderSelect(ticket, SELECT_BY_TICKET))
  {
    if (OrderType() == OP_BUY)
      return ((price - OrderOpenPrice()) / MarketInfo(OrderSymbol(), MODE_POINT) * MarketInfo(OrderSymbol(), MODE_TICKVALUE) * OrderLots());
    else
      return ((OrderOpenPrice() - price) / MarketInfo(OrderSymbol(), MODE_POINT) * MarketInfo(OrderSymbol(), MODE_TICKVALUE) * OrderLots());
  }
  else
    return (0.0);
}


double _GetProfitPips(int ticket)
{
  if (OrderSelect(ticket, SELECT_BY_TICKET))
  {
    double pointFactor = GuessPointFactor(OrderSymbol());
  
    if (OrderCloseTime() == 0)
    {
      if (OrderType() == OP_BUY)
        return ((MarketInfo(OrderSymbol(), MODE_BID) - OrderOpenPrice()) / MarketInfo(OrderSymbol(), MODE_POINT) / pointFactor);
      else
        return ((OrderOpenPrice() - MarketInfo(OrderSymbol(), MODE_ASK)) / MarketInfo(OrderSymbol(), MODE_POINT) / pointFactor);
    }
    else
    {
      if (OrderType() == OP_BUY)
        return ((OrderClosePrice() - OrderOpenPrice()) / MarketInfo(OrderSymbol(), MODE_POINT) / pointFactor);
      else
        return ((OrderOpenPrice() - OrderClosePrice()) / MarketInfo(OrderSymbol(), MODE_POINT) / pointFactor);
    }
  }
  else
    return (0.0);
}


double _GetPipsAtPrice(int ticket, double price)
{
  double pipsAt = 0.0;
  if (OrderSelect(ticket, SELECT_BY_TICKET))
  {
    double pointFactor = GuessPointFactor(OrderSymbol());
    if (OrderType() == OP_BUY)
      return ((price - OrderOpenPrice()) / MarketInfo(OrderSymbol(), MODE_POINT) / pointFactor);
    else
      return ((OrderOpenPrice() - price) / MarketInfo(OrderSymbol(), MODE_POINT) / pointFactor);
  }
  else
    return (0.0);
}


int _GetX(int column)
{
  if (column >= ArraySize(LX))
    return (-1);
  else
    return (LXOFFSET + LX[column]);
}


int _GetY(int row)
{
  return (LYOFFSET + row * (fontSize + 4 + ExtraLineSpacing));
}


string _GetBriefPctDisplay(double factor)
{
  double pct = factor * 100.0;
  string result = "";
  
  if (MathAbs(pct) < 10 && MathAbs(pct) > 0.1)
    result = DoubleToStr(pct, 1) + "%";
  else
    result = DoubleToStr(pct, 0) + "%";

  if (factor < 0)
    return ("(" + result + ")");
  else
    return (result);
}


string _GetBriefPipsDisplay(double pips)
{
  int digits;
  if (pips < -10  ||  pips > 10)
    digits = 0;
  else
    digits = 1;
  
  if (pips < 0)
    return ("(" + DoubleToStr(MathAbs(pips), digits) + "p)");
  else
    return (DoubleToStr(pips, digits)+"p");
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


void FileSkipLine(int handle)
{ // doesn't seem to work
  while (!FileIsLineEnding(handle) && !FileIsEnding(handle))
    FileReadString(handle);
}


void _LoadState()
{
  int err;
  int handle = 0;
  int retries = 3;
  while (handle <= 0 && retries > 0)
  {
    if (handle < 0)
    {
      err = GetLastError();
      if (err == ERR_WRONG_FILE_NAME || err == ERR_INVALID_FUNCTION_PARAMVALUE)
        break;
    }
    retries--;
    handle = FileOpen(StateFile, FILE_CSV|FILE_READ, ';');
    if (handle < 0)
      Sleep(250 + (3-retries)*250);
  }

  int nextIndex = 0;  
  if (handle > 0)
  {
    while (nextIndex < ArraySize(Ticket))
    {
      DebugStr[nextIndex] = "";
      
      GetLastError();
      Ticket[nextIndex] = FileReadNumber(handle);
      MaxSL[nextIndex] = FileReadNumber(handle);
      MAE_price[nextIndex] = FileReadNumber(handle);
      MFE_price[nextIndex] = FileReadNumber(handle);
      CommentStr[nextIndex] = FileReadString(handle);

      err = GetLastError();
      if (StringLen(CommentStr[nextIndex]) > 2)
        CommentStr[nextIndex] = StringSubstr(CommentStr[nextIndex], 1, StringLen(CommentStr[nextIndex])-2);
      else
        CommentStr[nextIndex] = "";
      nextIndex++;
      
      if (err != 0)
      {
        DebugStr[nextIndex] = DebugStr[nextIndex] + " err: "  + err;
        break;
      }
    }
  }
  FileClose(handle);
}


#define SAVE_INTERVAL_SEC 15
datetime nextSave = 0;
void _SaveStatePeriodically()
{
  if (TimeCurrent() > nextSave)
  {
    nextSave = TimeCurrent() + SAVE_INTERVAL_SEC;
    _SaveState();
  }
}


void _SaveState()
{
  int err;
  int handle = 0;
  int retries = 3;
  while (handle <= 0 && retries > 0)
  {
    if (handle < 0)
    {
      err = GetLastError();
      if (err == ERR_WRONG_FILE_NAME || err == ERR_INVALID_FUNCTION_PARAMVALUE)
        break;
    }
    retries--;
    handle = FileOpen(StateFile, FILE_CSV|FILE_WRITE, ';');
    if (handle < 0)
      Sleep(250 + (3-retries)*250);
  }

  if (handle > 0)
  {
    // globals
//    FileWrite(handle, "");
    
    // header
//    FileWrite(handle, "Ticket", "MaxSL", "MAEprice", "MFEprice", "Comment");
    
    // items
    for (int i=0; i<ArraySize(Ticket); i++)
    {
      if (Ticket[i] != 0)
      {
        FileWrite(handle,
          Ticket[i],
          MaxSL[i],
          MAE_price[i],
          MFE_price[i],
          "\""+CommentStr[i]+"\""
        );
      }
    }
        
    FileClose(handle);
  }
}


bool _LogTradeComplete(
  string app,
  int ticket,
  int orderType,
  datetime opentime,
  datetime closetime,
  string symbol,
  double openprice,
  double closeprice,
  double profit,
  double lots,
  double swap,
  double maxsl,
  double mae_price,
  double mfe_price,
  string ordercomment,
  string extracomment)
{
  string url = "";
  int httpStatus[1];

  symbol = StringLower(symbol);

  string sOrderType;
  if (orderType == OP_SELL)
    sOrderType = "sell";
  else if (orderType == OP_BUY)
    sOrderType = "buy";
  else
    sOrderType = "" + orderType;
  
  url = url
    + "ticket=" + ticket
    + "&app=" + URLEncode(app)
    + "&symbol=" + symbol
    + "&orderType=" + sOrderType
    + "&profit=" + _GetBriefDollarDisplay(profit, true)
    + "&opentime=" + TimeToStr(opentime, TIME_DATE|TIME_MINUTES|TIME_SECONDS)
    + "&closetime=" + TimeToStr(opentime, TIME_DATE|TIME_MINUTES|TIME_SECONDS)
    + "&age=" + _GetAge(opentime, closetime)
    + "&openprice=" + openprice
    + "&closeprice=" + closeprice
    + "&lots=" + DoubleToStr(lots, 2)
    + "&swap=" + swap
    + "&maxsl=" + maxsl
    + "&mae_price=" + mae_price
    + "&mfe_price=" + mfe_price
    + "&ordercomment=" + URLEncode(ordercomment)
    + "&extracomment=" + URLEncode(extracomment)
    ;
  
  string result;
  if (Log_HTTP != "")
    result = httpGET(Log_HTTP + url, httpStatus);
  
  if (Log_HTTP2 != "")
    result = httpGET(Log_HTTP2 + url, httpStatus);
  
  if (Log_Email)
  {
    string mail = ""
      + "ticket=" + ticket
      + "\napp=" + app
      + "\nsymbol=" + symbol
      + "\norderType=" + sOrderType
      + "\nprofit=" + _GetBriefDollarDisplay(profit, true)
      + "\nopentime=" + TimeToStr(opentime, TIME_DATE|TIME_MINUTES|TIME_SECONDS)
      + "\nclosetime=" + TimeToStr(opentime, TIME_DATE|TIME_MINUTES|TIME_SECONDS)
      + "\nage=" + _GetAge(opentime, closetime)
      + "\nopenprice=" + openprice
      + "\ncloseprice=" + closeprice
      + "\nlots=" + DoubleToStr(lots, 2)
      + "\nswap=" + swap
      + "\nmaxsl=" + maxsl
      + "\nmae_price=" + mae_price
      + "\nmfe_price=" + mfe_price
      + "\nordercomment=" + ordercomment
      + "\nextracomment=" + extracomment
      ;    
  
    SendMail(Log_EmailSubject, mail);
  }
  
  return (httpStatus[0] == 200);
}


void _LogTradeResult(int ticket)
{
  if (!OrderSelect(ticket, SELECT_BY_TICKET, MODE_HISTORY))
    return;

  for (int idx=0; idx<ArraySize(Ticket); idx++)
    if (Ticket[idx] == ticket)
      break;

  if (idx >= ArraySize(Ticket))
    return;    

  double pointFactor = GuessPointFactor(OrderSymbol());

  double maxRiskPips;
  if (OrderType() == OP_BUY)
    maxRiskPips = (OrderOpenPrice() - MaxSL[idx])/MarketInfo(OrderSymbol(), MODE_POINT)/pointFactor;
  else
    maxRiskPips = (MaxSL[idx] - OrderOpenPrice())/MarketInfo(OrderSymbol(), MODE_POINT)/pointFactor;
  
  double profitPips;
  double MFE_Pips;
  double MAE_Pips;
  if (OrderType() == OP_BUY)
  {
    MFE_Pips = (MFE_price[idx] - OrderOpenPrice())/MarketInfo(OrderSymbol(), MODE_POINT)/pointFactor;
    MAE_Pips = (MAE_price[idx] - OrderOpenPrice())/MarketInfo(OrderSymbol(), MODE_POINT)/pointFactor;
    profitPips = (OrderClosePrice() - OrderOpenPrice())/MarketInfo(OrderSymbol(), MODE_POINT)/pointFactor;
  }
  else
  {
    MFE_Pips = (OrderOpenPrice() - MFE_price[idx])/MarketInfo(OrderSymbol(), MODE_POINT)/pointFactor;
    MAE_Pips = (OrderOpenPrice() - MAE_price[idx])/MarketInfo(OrderSymbol(), MODE_POINT)/pointFactor;
    profitPips = (OrderOpenPrice() - OrderClosePrice())/MarketInfo(OrderSymbol(), MODE_POINT)/pointFactor;
  }
    
  double rewardRiskPct = 0;
  if (maxRiskPips != 0)
    rewardRiskPct = profitPips / maxRiskPips;
    
  double efficiencyPct;
  if (MFE_Pips != 0)
    efficiencyPct = profitPips / MFE_Pips;

  double heatPct;
  if (maxRiskPips != 0)
    heatPct = MathAbs(MAE_Pips / maxRiskPips);

  _LogTradeComplete(
    AppName,
    OrderTicket(),
    OrderType(),
    OrderOpenTime(),
    OrderCloseTime(),
    OrderSymbol(),
    OrderOpenPrice(),
    OrderClosePrice(),
    OrderProfit(),
    OrderLots(),
    OrderSwap() + OrderCommission(),
    MaxSL[idx],
    MAE_price[idx],
    MFE_price[idx],
    OrderComment(),
    CommentStr[idx]
    );

  Ticket[idx] = 0;
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


void SetLabel(string name, int corner, int x, int y, string text, color clr=NULL, int size=0, string face=fontName)
{
  if (text == "")
    return;
    
  int windowNumber;
  if (corner > 10)
  {
    windowNumber = 1;
    corner = corner - 10;
  }
  else
    windowNumber = 0;
  
  if (ObjectFind(pfx+name) < 0)
    ObjectCreate(pfx+name, OBJ_LABEL, windowNumber, 0,0);
 
  ObjectSetInteger(0, pfx+name, OBJPROP_CORNER, corner);

  ObjectSet(pfx+name, OBJPROP_XDISTANCE, x);
  ObjectSet(pfx+name, OBJPROP_YDISTANCE, y);
  ObjectSetText(pfx+name, text, size, face, clr);
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

double GuessPointFactor(string symbol = "")
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
    return (FOUR_DIGIT);
  }
  else if (StringFind(lsym,"sp500",0) >= 0)
  {
    return (10);
  }
  else if (StringFind(lsym,"dax30",0) >= 0)
  {
    return (100);
  }
  else
  {
    if (Digits >= 5)
      return (FIVE_DIGIT);
    else
      return (FOUR_DIGIT);
  }
}

