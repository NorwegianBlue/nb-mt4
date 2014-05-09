//+------------------------------------------------------------------+
//|                                        Timar - SnR AutoLabel.mq4 |
//|                              Copyright © 2011, Timar Investments |
//|                               http://www.timarinvestments.com.au |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2011-14, Timar Investments"
#property link      "http://www.timarinvestments.com.au"

#property indicator_chart_window

extern color M15_Color = Gray;
extern int M15_Style = STYLE_DOT;
extern int M15_Width = 1;

extern color H1_Color = Green;
extern int H1_Style = STYLE_DOT;
extern int H1_Width = 1;

extern color H4_Color = Lime;
extern int H4_Style = STYLE_DOT;
extern int H4_Width = 1;

extern color D1_Color = Lime;
extern int D1_Style = STYLE_SOLID;
extern int D1_Width = 1;

extern color W1_Color = White;
extern int W1_Style = STYLE_SOLID;
extern int W1_Width = 1;

extern color MN1_Color = Red;
extern int MN1_Style = STYLE_SOLID;
extern int MN1_Width = 2;


//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int init()
{
  ChartSetInteger(ChartID(), CHART_EVENT_OBJECT_CREATE, true);
  return(INIT_SUCCEEDED);
}


//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
int deinit()
{
  return(0);
}


//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
void Refresh()
{
  for (int objidx=0; objidx<ObjectsTotal(); objidx++)
  {
    string name = ObjectName(objidx);
    if (ObjectType(name) == OBJ_HLINE)
    {
      string desc = ObjectDescription(name);
      if (desc == "")
        ObjectSetText(name, PeriodToStr(Period()));
      desc = StringTrimLeft(ObjectDescription(name));
      if (desc == "MN1")
      {
        ObjectSet(name, OBJPROP_COLOR, MN1_Color);
        ObjectSet(name, OBJPROP_STYLE, MN1_Style);
        ObjectSet(name, OBJPROP_WIDTH, MN1_Width);
        ObjectSet(name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
      }
      else if (desc == "W1")
      {
        ObjectSet(name, OBJPROP_COLOR, W1_Color);
        ObjectSet(name, OBJPROP_STYLE, W1_Style);
        ObjectSet(name, OBJPROP_WIDTH, W1_Width);
        ObjectSet(name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
      }
      else if (desc == "D1")
      {
        ObjectSet(name, OBJPROP_COLOR, D1_Color);
        ObjectSet(name, OBJPROP_STYLE, D1_Style);
        ObjectSet(name, OBJPROP_WIDTH, D1_Width);
        ObjectSet(name, OBJPROP_TIMEFRAMES, OBJ_PERIOD_M1 + OBJ_PERIOD_M5 + OBJ_PERIOD_M15 + OBJ_PERIOD_M30 + OBJ_PERIOD_H1 + OBJ_PERIOD_H4 + OBJ_PERIOD_D1);
      }
      else if (desc == "H4")
      {
        ObjectSet(name, OBJPROP_COLOR, H4_Color);
        ObjectSet(name, OBJPROP_STYLE, H4_Style);
        ObjectSet(name, OBJPROP_WIDTH, H4_Width);
        ObjectSet(name, OBJPROP_TIMEFRAMES, OBJ_PERIOD_M1 + OBJ_PERIOD_M5 + OBJ_PERIOD_M15 + OBJ_PERIOD_M30 + OBJ_PERIOD_H1 + OBJ_PERIOD_H4);
      }
      else if (desc == "H1")
      {
        ObjectSet(name, OBJPROP_COLOR, H1_Color);
        ObjectSet(name, OBJPROP_STYLE, H1_Style);
        ObjectSet(name, OBJPROP_WIDTH, H1_Width);
        ObjectSet(name, OBJPROP_TIMEFRAMES, OBJ_PERIOD_M1 + OBJ_PERIOD_M5 + OBJ_PERIOD_M15 + OBJ_PERIOD_M30 + OBJ_PERIOD_H1);        
      }
      else if (desc == "M15"  ||  desc == "M5"  || desc == "M1")
      {
        ObjectSet(name, OBJPROP_COLOR, M15_Color);
        ObjectSet(name, OBJPROP_STYLE, M15_Style);
        ObjectSet(name, OBJPROP_WIDTH, M15_Width);
        ObjectSet(name, OBJPROP_TIMEFRAMES, OBJ_PERIOD_M1 + OBJ_PERIOD_M5 + OBJ_PERIOD_M15 + OBJ_PERIOD_M30 + OBJ_PERIOD_H1);        
      }
    }
  }
}


void OnChartEvent(const int id,         // Event ID
                  const long& lparam,   // Parameter of type long event
                  const double& dparam, // Parameter of type double event
                  const string& sparam  // Parameter of type string events
  )
{
  Refresh();
}

int start()
{
  return (0);
}

//+------------------------------------------------------------------+

string PeriodToStr(int period)
{
  switch (period)
  {
    case PERIOD_MN1: return ("    MN1");
    case PERIOD_W1:  return ("  W1");
    case PERIOD_D1:  return ("D1");
    case PERIOD_H4:  return ("  H4");
    case PERIOD_H1:  return ("    H1");
    case PERIOD_M30: return ("  M30");
    case PERIOD_M15: return ("M15");
    case PERIOD_M5:  return ("  M5");
    case PERIOD_M1:  return ("M1");
    default:         return("M? [" + period + "]");
  }
}

