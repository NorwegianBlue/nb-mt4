//+------------------------------------------------------------------+
//|                                           Timar - MadScalper.mq4 |
//|                              Copyright © 2010, Timar Investments |
//|                               http://www.timarinvestments.com.au |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2010, Timar Investments"
#property link      "http://www.timarinvestments.com.au"

//---- input parameters
extern bool Active=true;
extern double SafetyNet$ = 3000;

extern string _1 = "__ Trade Configuration __";


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
//| expert initialization function                                   |
//+------------------------------------------------------------------+
int init()
{
  return(0);
}


//+------------------------------------------------------------------+
//| expert deinitialization function                                 |
//+------------------------------------------------------------------+
int deinit()
{
  return(0);
}


//+------------------------------------------------------------------+
//| expert start function                                            |
//+------------------------------------------------------------------+
int start()
{
  string s = "";
  
  s = s
    + "EMA(14[1]): " + DoubleToStr(_GetEMA14(1), Digits)
    + " EMA(14[3]): " + DoubleToStr(_GetEMA14(3), Digits)
    + "   EMA(50): " + DoubleToStr(_GetEMA50(), Digits)
    + "\n"
    + "Grad.EMA(14): " +  _GetEMA14Gradient()/Point
    + "  Grad.EMA(50): " + _GetEMA50Gradient()/Point;
    
  SetLabel("grad14", 
  
  Comment(s);

  return(0);
}


//+------------------------------------------------------------------+
/*
  EMA-14  
  EMA-50
*/


double _GetEMA14(int time=0)
{
  return (iMA(NULL, 0, 14, 0, MODE_EMA, PRICE_CLOSE, time));
}


double _GetEMA14Gradient(int time1=3, int time0=1)
{
  return ((_GetEMA14(time0) - _GetEMA14(time1)) / (time1 - time0));
}


double _GetEMA50(int time=0)
{
  return (iMA(NULL, 0, 50, 0, MODE_EMA, PRICE_CLOSE, time));
}


double _GetEMA50Gradient(int time1=3, int time0=1)
{
  return ((_GetEMA50(time0) - _GetEMA50(time1)) / (time1 - time0));
}



//+------------------------------------------------------------------+
//| LIBRARY ROUTINES                                                 |
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
    
  double riskPips = priceDifference/Point/10.0;
  
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

