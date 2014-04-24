//+---------------------------------------------------------------------+
//|                                                   nbpointfactor.mqh |
//|                                     Copyright © 2012, NorwegianBlue |
//|             http://sites.google.com/site/norwegianbluesmt4junkyard/ |
//|                                                                     |
//| Calculates what factor to apply to prices to turn them into pips.   |
//|                                                                     |
//| Usage:                                                              |
//|   Call PFLoadPointFactors() in your init() method                   |
//|                                                                     |
//|   Call PFGetPointFactor(string symbol = "") to obtain the           |
//|   Factor need to turn a price into pips.                            |
//|                                                                     |
//| Configuration:                                                      |
//|   A file "nb-point-factors.csv" can be placed in the experts/files  |
//|   directory. It is a comma-delimited csv file, where each record is |
//|   a search symbol, followed by a factor.                            |
//+---------------------------------------------------------------------+

#define POINT_FACTOR_FILENAME "nb-point-factors.csv"


string _PFStringLower(string str)
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

string debug = "";


string PFSymbols[];
double PFFactors[]; 

void PFLoadPointFactors()
{
  int entryCount = 0;
  int handle = FileOpen(POINT_FACTOR_FILENAME, FILE_CSV | FILE_READ, ","); 
  
  string symbol;
  double factor;
  
  if (handle > 0)
  {
    // Count the entries
    while (!FileIsEnding(handle) &&  entryCount < 50)
    {
      symbol = FileReadString(handle);
      if (symbol != "")
      {
        factor = FileReadNumber(handle);
        entryCount++;
      }
      else
        while (!FileIsLineEnding(handle))
          FileReadString(handle);
    }
    
    ArrayResize(PFSymbols, entryCount);
    ArrayResize(PFFactors, entryCount);
    
    // Read the entries
    FileSeek(handle, 0, SEEK_SET);
    entryCount = 0;
    while (!FileIsEnding(handle)  &&  entryCount < ArraySize(PFSymbols))
    {
      symbol = _PFStringLower(FileReadString(handle));
      if (symbol != "")
      {
        PFSymbols[entryCount] = symbol;
        PFFactors[entryCount] = FileReadNumber(handle);
        entryCount++;
      }
      else
        while (!FileIsLineEnding(handle))
          FileReadString(handle);
    }
    FileClose(handle);
  }
}


bool _PFLookupPointFactor(string symbol, double& pf)
{
  string lsym = _PFStringLower(symbol);
  for (int i=0; i<ArraySize(PFSymbols); i++)
  {
    if (StringFind(lsym, PFSymbols[i], 0) >= 0)
    {
      pf = PFFactors[i];
      return (true);
    }
  }
  return (false);
}




double PFGetPointFactor(string symbol = "")
{
  if (symbol == "")
    symbol = Symbol();  
  double result;
  string lsym = _PFStringLower(symbol);
  if (_PFLookupPointFactor(lsym, result))
    return (result);  
  
  if (StringFind(lsym,"xau",0) >= 0)
  {
    if (Digits >= 2)
      return (10.0);
    else
      return (1.0);
  }
  else if (StringFind(lsym,"xag",0) >= 0)
  {
    if (Digits >= 3)
      return (10.0);
    else
      return (1.0);
  }
  else if (StringFind(lsym,"jpy",0) >= 0)
  {
    if (Digits >= 3)
      return (10.0);
    else
      return (1.0);
  }
  else if (StringFind(lsym,"oil",0) >= 0)
  {
    if (Digits >= 3)
      return (10.0);
    else
      return (1.0);
  }
  else
  {
    if (Digits >= 5)
      return (10.0);
    else
      return (1.0);
  }
}

