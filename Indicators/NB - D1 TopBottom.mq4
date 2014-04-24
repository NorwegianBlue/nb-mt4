//+------------------------------------------------------------------+
//|                                            NB - D1 TopBottom.mq4 |
//|                                  Copyright © 2012, NorwegianBlue |
//|           http://sites.google.com/site/norwegianbluesmt4junkyard |
//+------------------------------------------------------------------+

#property copyright "Copyright © 2012, NorwegianBlue"
#property link      "http://sites.google.com/site/norwegianbluesmt4junkyard"

#property indicator_chart_window

extern string _VERSION_1="1";
extern int NumberOfDays = 10;
extern color Top_Color = C'48,0,0';
extern color Bottom_Color = C'0,36,0';

//+------------------------------------------------------------------+
string pfx="nbd1x";

int init()
{
  return(0);
}


int deinit()
{
  DeleteAllObjectsWithPrefix(pfx);
  return(0);
}


#define ONE_DAY 86400

void DrawRectangle(int dayBar)
{
  datetime t = iTime(NULL, PERIOD_D1, dayBar);
  SetRectangle("top"+dayBar,
    t, iMA(Symbol(), PERIOD_D1, 2, 0, MODE_LWMA, PRICE_HIGH, dayBar),
    t+ONE_DAY, iMA(Symbol(), PERIOD_D1, 4, 0, MODE_LWMA, PRICE_HIGH, dayBar),
    Top_Color);
  
  SetRectangle("bottom"+dayBar,
    t, iMA(Symbol(), PERIOD_D1, 2, 0, MODE_LWMA, PRICE_LOW, dayBar),
    t+ONE_DAY, iMA(Symbol(), PERIOD_D1, 4, 0, MODE_LWMA, PRICE_LOW, dayBar),
   Bottom_Color);
}


int start()
{
  for (int i=0; i<NumberOfDays; i++)
    DrawRectangle(i);
  
  return(0);
}


void SetRectangle(string name, double time1, double price1, double time2, double price2, color clr)
{
  int windowNumber = 0;
  
  if (ObjectFind(pfx+name) <0)
    ObjectCreate(pfx+name, OBJ_RECTANGLE, windowNumber, time1, price1, time2, price2);
    
  ObjectSet(pfx+name, OBJPROP_COLOR, clr);
  ObjectSet(pfx+name, OBJPROP_PRICE1, MathMin(price1, price2));
  ObjectSet(pfx+name, OBJPROP_TIME1, time1);  
  ObjectSet(pfx+name, OBJPROP_PRICE2, MathMax(price1, price2));
  ObjectSet(pfx+name, OBJPROP_TIME2, time2);
  ObjectSet(pfx+name, OBJPROP_BACK, true);
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

