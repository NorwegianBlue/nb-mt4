//+------------------------------------------------------------------+
//|                                                NB - H4 Power.mq4 |
//|                                  Copyright © 2013, NorwegianBlue |
//|           http://sites.google.com/site/norwegianbluesmt4junkyard |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2013, NorwegianBlue"
#property link      "http://sites.google.com/site/norwegianbluesmt4junkyard"

#property indicator_chart_window

//+------------------------------------------------------------------+

#define pfx "h4p"
#define fontName     "Calibri"
#define boldFontName "Arial Black"
#define fontSize     8


int corner = 0;

int init()
{
  DeleteAllObjectsWithPrefix(pfx);
  return(0);
}

int deinit()
{
  DeleteAllObjectsWithPrefix(pfx);
  return(0);
}

int start()
{
  int counted_bars=IndicatorCounted();
      
  _UpdateObjects();
  
  return(0);
}


bool _UpBar(int period, int offset)
{
  if (iClose(NULL, period, offset) >= iOpen(NULL, period, offset))
    return (true);
  else
    return (false);
}

bool _DownBar(int period, int offset)
{
  if (iClose(NULL, period, offset) <= iOpen(NULL, period, offset))
    return (true);
  else
    return (false);
}


#define ENGULF_NONE 0
#define ENGULF_SHORT 1
#define ENGULF_SHORTx2 2
#define ENGULF_LONG 3
#define ENGULF_LONGx2 4

int _CalcEngulf(int period)
{
  if (_UpBar(period, 2)  &&  iClose(NULL, period, 1) < iOpen(NULL, period, 2))
    return (ENGULF_SHORT);
  else if (_DownBar(period, 2)  &&  iClose(NULL, period, 1) > iOpen(NULL, period, 2))
    return (ENGULF_LONG);
  
  if (_UpBar(period, 3)  &&  iClose(NULL, period, 1) < iOpen(NULL, period, 3)  &&  iClose(NULL, period, 1) < iClose(NULL, period,  2))
    return (ENGULF_SHORTx2);
  else if (_DownBar(period, 3)  &&  iClose(NULL, period, 1) > iOpen(NULL, period, 3)  &&  iClose(NULL, period, 1) > iClose(NULL, period, 2))
    return (ENGULF_LONGx2);
  
  return (ENGULF_NONE);
}


color _EngulfColor(int engulf)
{
  switch (engulf)
  {
    case ENGULF_SHORT:
    case ENGULF_SHORTx2:
      return (Red);
      
    case ENGULF_LONG:
    case ENGULF_LONGx2:
      return (Green);
      
    default:
      return (Gray);
  }
}


void _EngulfInfo(int period, color& clr, string& text)
{
  int engulf = _CalcEngulf(period);
  clr = _EngulfColor(engulf);
  
  text = "";
  switch (engulf)
  {
    case ENGULF_SHORTx2:
      text = "x2";
    case ENGULF_SHORT:
      clr = OrangeRed;
      break;
      
    case ENGULF_LONGx2:
      text = "x2";
    case ENGULF_LONG:
      clr = Lime;
      break;
      
    default:
      clr = Gray;
  }
}


void _UpdateObjects()
{
  int x = 15;
  int y = 20;
  int liney = 12;
  
  if (corner == 3)
  {
    y = y + liney*3;
    liney = liney * (-1);
  }
  
  color clr;
  string text;
  _EngulfInfo(PERIOD_H4, clr, text);  
  SetLabel("h41", corner, x, y, "H4 engulf" + text, clr);
  y += liney;
  
  _EngulfInfo(PERIOD_M15, clr, text);
    SetLabel("m15title", corner, x, y, "M15 engulf" + text, clr);
  y += liney;
  
  _EngulfInfo(PERIOD_M5, clr, text);
  SetLabel("m5title", corner, x, y, "M5 engulf" + text, clr);
  y += liney;
}



//-----------------------------------------------------------------
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

