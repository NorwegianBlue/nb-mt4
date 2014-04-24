//+------------------------------------------------------------------+
//|                                       NB - Currency Strength.mq4 |
//|                                  Copyright © 2013, NorwegianBlue |
//|           http://sites.google.com/site/norwegianbluesmt4junkyard |
// Ref: http://www.dailyfx.com/forex/education/trading_tips/post_of_the_day/2011/06/15/How_to_Create_a_Trading_Edge_Know_the_Strong_and_the_Weak_Currencies.html
//+------------------------------------------------------------------+
#property copyright "Copyright © 2013, NorwegianBlue"
#property link      "http://sites.google.com/site/norwegianbluesmt4junkyard"

#property indicator_chart_window
//--- input parameters
extern int       MAPeriod=200;

int init()
{
  return(0);
}

int deinit()
{
  return(0);
}


int EXECUTION_RATE_SEC = 60;
datetime NextExecution = 0;


int start()
{
  if (TimeCurrent() < NextExecution)
    return;

  DoProcess();    

  NextExecution = TimeCurrent() + EXECUTION_RATE_SEC;
  return(0);
}
                 // 0      1      2      3      4      5      6      7
string NAMES[] = {"AUD", "CAD", "CHF", "EUR", "GBP", "JPY", "NZD", "USD"};
int STRENGTHS[]= {   0,      0,     0,     0,     0,     0,     0,     0};


string PAIRS[] = {
  "audusd"
  };
 
int PAIR_INDEXES[][2] = {
  0, 7,  // audusd
  
  
  };


void ResetStrengths()
{
  for (int i=0; i<ArraySize(STRENGTHS); i++)
    STRENGTHS[i] = 0;
}


void DoProcess()
{
  ResetStrengths();
  
}


void DrawTable()
{
}

