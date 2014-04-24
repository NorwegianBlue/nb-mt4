//+------------------------------------------------------------------+
//|                                       NB - Lot Size for Risk.mq4 |
//|                                  Copyright © 2012, NorwegianBlue |
//|           http://sites.google.com/site/norwegianbluesmt4junkyard |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2012, NorwegianBlue"
#property link      "http://sites.google.com/site/norwegianbluesmt4junkyard"

#property show_inputs 


extern double Risk_Pct = 2.0;
extern double Risk_Pips = 18.0;


double AcBal()
{
  double bal = 0.0;
  if (GlobalVariableCheck("NBLotSize_NominalAccount$"))
    bal = GlobalVariableGet("NBLotSize_NominalAccount$");
  else
    GlobalVariableSet("NBLotSize_NominalAccount$", 0);
  
  if (bal == 0)
    bal = AccountBalance();
  
  return (bal);
}

double POINT_FACTOR = 10.0;


int start()
{
  POINT_FACTOR = GuessPointFactor();
  
  double risk$ = AcBal() * (Risk_Pct/100.0);
  double lotSize = (risk$ / (Risk_Pips*POINT_FACTOR)) / MarketInfo(Symbol(), MODE_TICKVALUE);

  Alert(Symbol() + " " + DoubleToStr(lotSize, 2) + " lots  (AcBal. $" + DoubleToStr(AcBal(),0) + ", Risk " + DoubleToStr(Risk_Pct, 1) + "%, Stop " + DoubleToStr(Risk_Pips, 1) + " pips)");
   
  return(0);
}


#define FIVE_DIGIT 10
#define FOUR_DIGIT 1

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

