//+------------------------------------------------------------------+
//|                                           NB - H4 Power Aide.mq4 |
//|                                  Copyright © 2013, NorwegianBlue |
//|           http://sites.google.com/site/norwegianbluesmt4junkyard |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2013, NorwegianBlue"
#property link      "http://sites.google.com/site/norwegianbluesmt4junkyard"

/*
  [EA STATUS]
  [W1] [D1] [H4] [M15]
  
  [Active] [NextH4] [STOP]
  
  [Risk]
  

  A summary of engulfs
    [W1] [D1] [H4] [M15]
  Red = short,  Green = long,  Grey = none
  If a double-bar engulf, use *
  
  [Active]
  When active, the EA will take engulfing trades off M15 in the direction of 
  Only 1 trade will be open at a time.
  No more than MaxTradesPerH4 will be taken per H4.
  Active will be reset on H4 closes.
  
  [NextH4]
  When set, the EA will activate on the next H4 if this H4 engulfs.
  If this H4 fails to engulf, NextH4 will turn off.
  
  
  
  
*/

#include <stderror.mqh>
#include <stdlib.mqh>
#include <ptutils.mqh>
#include <ptorders.mqh>

#define VERSION_STR  "1"


extern string _VERSION_1 = VERSION_STR;
#define DEF_DEFLOTS "0.01|0.05|0.1|1.0|"
#define DEF_DEFRISK "0.5|1.0|2.0|3.0|"
#define DEF_REWARDRISKFACTOR   2.0
#define DEF_MOVESTOPTOBEFACTOR 0.5

extern int MaxTradesPerH4 = 3;
extern bool DoubleBarEngulfAllowed = true;
extern double OverridePointFactor = 0.0;
extern double RewardRiskFactor = DEF_REWARDRISKFACTOR;
extern double MinStop_Pips = 9;
extern double EntryLag_Pips = 1.0;
//extern bool   IncludeSpreadInLag = true;

extern string _2="";
extern string CommentPrefix = "nb60ca";

// TEMPORARY
extern double FixedStopPips = 20.0;

extern string _3="__ Configuration __";
extern string _31="] Delimit lists with pipe char |";
extern string DefLots=DEF_DEFLOTS;
//extern string DefRisk="3.0|1.0|2.0|";
extern string DefRisk=DEF_DEFRISK;
extern double NominalBalanceForRisk$ = 0;
extern string _32="]Set to 0 to use actual balance";
extern double MaxLots = 4.0;

extern string _4="__ Trade management ___";
extern double MoveStopToBEFactor = DEF_MOVESTOPTOBEFACTOR;

extern string _6 = "__ Display _____________";
extern string CurrencySymbol = "$";
extern bool ShowRiskPct = true;  // Show status as % of max risk
extern bool ShowCurrency = true;
extern bool ShowNextBarIn = true;
extern int MultiCommentLines = 6;
extern int CommentDelay = 60; //secs

int Magic = 0;

//+------------------------------------------------------------------+
#define pfx "h4pa"
#define fontName     "Calibri"
#define boldFontName "Arial Black"
#define fontSize     8

//+------------------------------------------------------------------+
#define MD_OFF    0
#define MD_ACTIVE 1
#define MD_NEXTH4 2

int ActiveMode =  MD_OFF;

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


#define H4REMAINING_X 5
#define H4REMAINING_Y 20
#define H4REMAINING_CORNER 3

#define BARREMAINING_X 5
#define BARREMAINING_Y 1
#define BARREMAINING_CORNER 3


//+------------------------------------------------------------------+
//| expert initialization function                                   |
//+------------------------------------------------------------------+
int init()
{
  DeleteAllObjectsWithPrefix(pfx);
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
  int corner = 1;
    
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