//+------------------------------------------------------------------+
//|                                       NB - Currency Exposure.mq4 |
//|                                  Copyright © 2013, NorwegianBlue |
//|           http://sites.google.com/site/norwegianbluesmt4junkyard |
// Calculate exposure to underlying currencies
//+------------------------------------------------------------------+
#property copyright "Copyright © 2013, NorwegianBlue"
#property link      "http://sites.google.com/site/norwegianbluesmt4junkyard"

#property indicator_chart_window
//--- input parameters
extern bool IncludeDepositCurrency = false;  // You are technically exposed to your deposit currency, but for retail traders this is usually not a concern
extern string NamePrefix = "";
extern string NameSuffix = "";

                 // 0      1      2      3      4      5      6      7      8      9
string NAMES[] = {"aud", "cad", "chf", "eur", "gbp", "jpy", "nzd", "usd", "xag", "xau"};
double NETSIZE[];
double NETSIZE_IN_DEPOSIT[];
 
int PAIR_INDEXES[][2] = {
  0, 7,  // audusd
  
  
  };


int init()
{
  ArrayResize(NETSIZE, ArraySize(NAMES));
  ArrayResize(NETSIZE_IN_DEPOSIT, ArraySize(NAMES));
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


void DoProcess()
{
  ArrayInitialize(NETSIZE, 0.0);
  ArrayInitialize(NETSIZE_IN_DEPOSIT, 0.0);
  
  for (int i=0; i<OrdersTotal(); i++)
  {
    if (OrderSelect(i, SELECT_BY_POS)  
        &&  (OrderType() == OP_BUY || OrderType() == OP_SELL)  
        &&  IsForex(OrderSymbol())
    {
      string tidyName = TidyPairName(OrderSymbol());
      int numIdx = CurrencyNameToIndex(NumeratorCurrency(tidyName));
      int denomIdx = CurrencyNameToIndex(NumeratorCurrency(tidyName));
      
      if (OrderType == OP_BUY)
      {
        NETSIZE[numIdx] += OrderLots(); // <-- factor required
        NETSIZE[denomIdx] -= OrderLots();
      }
      else // OP_SELL
      {
        NETSIZE[numIdx] -= OrderLots();  // <-- factor required
        NETSIZE[denomIdx] += OrderLots();
      }
    }
  }
}


bool IsForex(string name)
{
  string cname = StringLower(name);
  
  if (cname == "dax30"  ||  cname == "cl-oil"  ||  cname == "spi200"  ||  cname == "dj30"  ||  cname == "sp500")
    return (false);
  else
    return (true);
}



string TidyPairName(string untidyName)
{
  string result = untidyName;
  if (NamePrefix != ""   &&  StringSubstr(result, 0, StringLen(NamePrefix)) == NamePrefix)
  {
    result = StringSubstr(result, StringLen(NamePrefix));
  }
  
  if (NameSuffix != ""   &&  StringSubstr(result, StringLen(result) - StringLen(NameSuffix) -1) == NameSuffix)
  {
    result = StringSubstr(result, StringLen(result) - StringLen(NameSuffix));
  }
    
  // TODO: Trim non-ascii chars
  
  return (StringLower(result));
}


string NumeratorCurrency(string pair)
{
  return (StringSubstr(pair, 0, 3));
}


string DenominatorCurrency(string pair)
{
  return (StringSubstr(pair, 3));
}


int CurrencyNameToIndex(string name)
{
  for (int i=0; i<ArraySize(NAMES); i++)
    if (NAMES[i] == name)
      return (i);
  return (-1);
}


void DrawTable()
{
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

