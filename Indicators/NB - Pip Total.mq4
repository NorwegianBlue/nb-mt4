//+------------------------------------------------------------------+
//|                                               NB - Pip Total.mq4 |
//|                             Copyright © 2011-2012, NorwegianBlue |
//|           http://sites.google.com/site/norwegianbluesmt4junkyard |
//|                                                                  |
//| Version 2                                                        |
//|   Added support for raw pips calculation when NominalLotSize     |
//|   is 0.                                                          |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2011-2012, NorwegianBlue"
#property link      "http://sites.google.com/site/norwegianbluesmt4junkyard"

#property indicator_chart_window

extern int    _VERSION=2;
extern string _1=" ] Set nominal size to 0 to calculate raw pips";
extern double NominalLotSize = 0.0;


void OnInit()
{
}


void OnDeinit()
{
}


int OnCalculate(const int rates_total,      // size of input time series
                const int prev_calculated,  // bars handled in previous call
                const datetime& time[],     // Time
                const double& open[],       // Open
                const double& high[],       // High
                const double& low[],        // Low
                const double& close[],      // Close
                const long& tick_volume[],  // Tick Volume
                const long& volume[],       // Real Volume
                const int& spread[])        // Spread
{
  double profit_ = 0.0;
  double profitPips = 0.0;
  double winPips = 0.0;
  double losePips = 0.0;
  double riskPips = 0.0;
  double targetPips = 0.0;
  int closedCount = ClosedTrades(profit_, winPips, losePips, riskPips, targetPips);
  string s =
    "Closed: " + closedCount + "  $" + DoubleToStr(profit_, 2) + "  " + DoubleToStr(winPips+losePips, 0) + " (" + DoubleToStr(winPips,0) + "W " + DoubleToStr(MathAbs(losePips),0)+ "L) pips";
    
  riskPips = 0.0;
  targetPips = 0.0;
  int openCount = OpenTrades(profit_, winPips, losePips, riskPips, targetPips);
  s = s +
    "   Open: " + openCount + "  $" + DoubleToStr(profit_, 2) + "  " + DoubleToStr(winPips+losePips, 0) + " (" + DoubleToStr(winPips,0) + "W " + DoubleToStr(MathAbs(losePips),0)+ "L) pips";
  
  s = s +
    "  Risk: " + DoubleToStr(riskPips, 0) + " pips";
    
  s = s +
    "  Target: " + DoubleToStr(targetPips, 0) + " pips";
  
  Comment(s);
  
  return (0);
}


int CalcTrades(int mode,  double& profit_, double& winPips, double& losePips, double& riskPips, double& targetPips)
{
  int count;
  int hstTotal;
  if (mode == MODE_HISTORY)
    hstTotal = OrdersHistoryTotal();
  else
    hstTotal = OrdersTotal();
  
  profit_ = 0.0;
  winPips = 0.0;
  losePips = 0.0;
  riskPips = 0.0;
  targetPips = 0.0;
  double pips;
  for (int i=0; i<hstTotal; i++)
  {
    if (OrderSelect(i, SELECT_BY_POS, mode))
    {
      if (OrderType() == OP_BUY  ||  OrderType() == OP_SELL)
      {
        count++;
        profit_ = profit_ + OrderProfit() + OrderSwap();
        
        double diff, riskdiff, targetdiff;
        if (OrderType() == OP_BUY)
        {
          diff = OrderClosePrice() - OrderOpenPrice();
          if (OrderStopLoss() > 0)
            riskdiff = -(OrderStopLoss() - OrderOpenPrice());
          if (OrderTakeProfit() > 0)
            targetdiff = OrderTakeProfit() - OrderOpenPrice();
        }
        else
        {
          diff = OrderOpenPrice() - OrderClosePrice();
          if (OrderStopLoss() > 0)
            riskdiff = -(OrderOpenPrice() - OrderStopLoss());
          if (OrderTakeProfit() > 0)
            targetdiff = OrderOpenPrice() - OrderTakeProfit();
        }
        
        double pointFactor = GuessPointFactor(OrderSymbol());
        
        if (NominalLotSize > 0)
        {
          pips = ((diff / MarketInfo(OrderSymbol(), MODE_POINT)) / pointFactor) * (OrderLots() / NominalLotSize);
          riskPips += ((riskdiff / MarketInfo(OrderSymbol(), MODE_POINT)) / pointFactor) * (OrderLots() / NominalLotSize);
          targetPips += ((targetdiff / MarketInfo(OrderSymbol(), MODE_POINT)) / pointFactor) * (OrderLots() / NominalLotSize);
        }
        else
        {
          pips = ((diff / MarketInfo(OrderSymbol(), MODE_POINT)) / pointFactor);
          riskPips += ((riskdiff / MarketInfo(OrderSymbol(), MODE_POINT)) / pointFactor);
          targetPips += ((targetdiff / MarketInfo(OrderSymbol(), MODE_POINT)) / pointFactor);
        }
          
        if (pips > 0)
          winPips = winPips + pips;
        else
          losePips = losePips + pips;
      }
    }
  }
  
  return (count);
}


int ClosedTrades(double& profit_, double& winPips, double& losePips, double& riskPips, double& targetPips)
{
  return (CalcTrades(MODE_HISTORY, profit_, winPips, losePips, riskPips, targetPips));
}


int OpenTrades(double& profit_, double& winPips, double& losePips, double& riskPips, double& targetPips)
{
  return (CalcTrades(MODE_OPEN, profit_, winPips, losePips, riskPips, targetPips));
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
    return (1000);
  }
  else if (StringFind(lsym,"dax",0) >= 0)
  {
    return (1000);
  }
  else
  {
    if (Digits >= 5)
      return (FIVE_DIGIT);
    else
      return (FOUR_DIGIT);
  }
}