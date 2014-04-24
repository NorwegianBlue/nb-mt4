//+------------------------------------------------------------------+
//|                                                MQL4 Code Library |
//|                              Copyright © 2010, Timar Investments |
//|                               http://www.timarinvestments.com.au |
//+------------------------------------------------------------------+

/*
Usage: 
  In your MQL4 source, define the following symbols first:
    string pfx="yourprefix";
    #define fontName     "Arial"
    #define boldFontName "Arial Black"
    #define fontSize     8
    
  Then #include this library.
   
Contents:
  [OBJECT UTILITIES]
  void DeleteAllObjectsWithPrefix(string prefix);
  void DeleteAllObjects()                          // uses pfx global
  void DeleteObject(string name)                   // uses pfx global
  void SetLabel(string name, int x, int y, string text, color clr=CLR_NONE, int size=0, string face=fontName)
  void SetLine(string name, double value, color clr, int style, int lineWidth=1)
  void SetText(string name, double x, double y, string text, color clr=CLR_NONE, int size=0, string face=fontName)
  void SetVertLine(string name, double time, color clr, int style, int lineWidth=1)

  [STRING UTILITIES]
  string StringLower(string str)
  string StringUpper(string str)
  void ParseDelimStringDouble(string s,  string delim,  double& result[])
 

  [SYMBOL UTILITIES]
  string PeriodToStr(int period)
  
  [TICKET UTILITIES]
  double GetTicketProfit(int ticket)
  double GetTicketOpenPrice(int ticket)
  bool IsTicketClosed(int ticket)
  bool IsTicketOpen(int ticket)
  bool IsTicketPending(int ticket)  
  void ModifyTicket(int ticket,  double stopPrice,  double profitPrice)
  bool MoveStop(int ticket,  double stopPrice)
  void MoveStopToPrice(int ticket, double newStopPrice, bool overrideSafety = false)

  [STATS]
  
  [RELIABLE ORDER REPLACEMENTS]
  int OrderReliableSend(string symbol, int op, double lotsize, double price, double spread, double stoploss, double takeprofit,
                        string comment, int magic, datetime expiry=0, color clr=CLR_NONE)
  bool OrderReliableModify(int ticket, double price, double stoploss, double takeprofit, datetime expiry=0, color clr=CLR_NONE)

  
  [CALCULATION UTILITIES]
  string GetDollarDisplay(double amount, bool exact=false)
  double GetLotsForRisk(double balance, double riskPercent, double entryPrice, double stopPrice)
  double PipsToPrice(double pips)
  double PointsToPrice(double points)
  int RandomRange(int range)
  
  [INDICATOR UTILITIES]
  double FractionalBB(string symbol, int timeframe, int bandperiod, double banddeviation, int bandshift, int mode, int timebarshift=0)
  
  [WINDOWS UTILITIES]
  bool IsMouseDown()
*/



//+------------------------------------------------------------------+
//| OBJECT UTILITIES                                                 |
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

void DeleteAllObjects()
{
  DeleteAllObjectsWithPrefix(pfx);
}


void DeleteObject(string name)
{
  ObjectDelete(pfx+name);
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
  //ObjectSet(pfx+name, OBJPROP_BACK, true);
}


//+------------------------------------------------------------------+
//| STRING UTILITIES                                                 |
//+------------------------------------------------------------------+

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


string StringUpper(string str)
{ 
  string outstr = "";
  string lower  = "abcdefghijklmnopqrstuvwxyz";
  string upper  = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
  for(int i=0; i<StringLen(str); i++)  {
    int t1 = StringFind(lower,StringSubstr(str,i,1),0);
    if (t1 >=0)  
      outstr = outstr + StringSubstr(upper,t1,1);
    else
      outstr = outstr + StringSubstr(str,i,1);
  }
  return(outstr);
}


void ParseDelimStringDouble(string s,  string delim,  double& result[])
{
  double tmplist[100];
  int cnt=0;
  int pos=0;
  int lastpos;
  string sItem;
  
  lastpos = 0;
  pos = StringFind(s, delim, lastpos);
  while (pos >= 0  &&  cnt < ArraySize(tmplist))
  {
    sItem = StringSubstr(s, lastpos, (pos - lastpos));
    tmplist[cnt] = StrToDouble(sItem);
    cnt++;
    lastpos = pos+1;
    pos = StringFind(s, delim, lastpos);
  }
  
  ArrayResize(result, cnt);
  for (int i=0; i<cnt; i++)
    result[i] = tmplist[i];
}



//+------------------------------------------------------------------+
//| SYMBOL UTILITIES                                                 |
//+------------------------------------------------------------------+

string PeriodToStr(int period)
{
  switch (period)
  {
    case PERIOD_MN1: return ("MN1");
    case PERIOD_W1:  return ("W1");
    case PERIOD_D1:  return ("D1");
    case PERIOD_H4:  return ("H4");
    case PERIOD_H1:  return ("H1");
    case PERIOD_M30: return ("M30");
    case PERIOD_M15: return ("M15");
    case PERIOD_M5:  return ("M5");
    case PERIOD_M1:  return ("M1");
    default:         return("M? [" + period + "]");
  }
}



//+------------------------------------------------------------------+
//| TICKET UTILITIES                                                 |
//+------------------------------------------------------------------+

double GetTicketLotSize(int ticket)
{
  if (OrderSelect(ticket, SELECT_BY_TICKET))
    return (OrderLots());
  else
    return (0.0);
}


double GetTicketProfit(int ticket)
{
  if (OrderSelect(ticket, SELECT_BY_TICKET))
    return (OrderProfit() + OrderSwap());
  else
    return (0.0);
}


double GetTicketOpenPrice(int ticket)
{
  if (OrderSelect(ticket, SELECT_BY_TICKET))
    return (OrderOpenPrice());
  else
    return (0.0);
}


bool IsTicketClosed(int ticket)
{
  if (OrderSelect(ticket, SELECT_BY_TICKET))
    return (OrderCloseTime() != 0);
  else
    return (false);
}


bool IsTicketOpen(int ticket)
{
  if (OrderSelect(ticket, SELECT_BY_TICKET))
    return ( (OrderType() == OP_BUY || OrderType() == OP_SELL)
             && (OrderCloseTime() == 0));
  else
    return (false);
}


bool IsTicketPending(int ticket)
{
  if (OrderSelect(ticket, SELECT_BY_TICKET))
  {
    if (OrderCloseTime() == 0)
      return (OrderType() != OP_BUY  &&  OrderType() != OP_SELL);
    else
      return (false);
  }
  else
    return (false);
}



void ModifyTicket(int ticket,  double stopPrice,  double profitPrice)
{
  if (!OrderSelect(ticket, SELECT_BY_TICKET))
    return;

  stopPrice = NormalizeDouble(stopPrice, Digits);
  profitPrice = NormalizeDouble(profitPrice, Digits);
  
  if (OrderStopLoss() == stopPrice  &&  OrderTakeProfit() == profitPrice)
    return;  // try not to bother the server if we don't have to
  
  int retries=3;
  while (retries >= 0)
  {
    if (OrderModify(ticket, OrderOpenPrice(), stopPrice, profitPrice, OrderExpiration()))
      break;
    else
    {
      int err = GetLastError();
      Print("Failed modifying " + ticket + " - " + ErrorDescription(err));
      Print("  sl: ", DoubleToStr(stopPrice, Digits), " tp: ", DoubleToStr(profitPrice, Digits));
    }
    retries--;
    Sleep(250 * (4-retries));
  }
}


#define MINIMUM_STOP_MOVE_POINTS  10
bool MoveStop(int ticket,  double stopPrice)
{
  if (OrderSelect(ticket, SELECT_BY_TICKET))
  {
    // -- Don't move stop against an open trade 
    if (OrderType() == OP_BUY)
    {
      if (OrderStopLoss() != 0  &&  stopPrice < OrderStopLoss())
        return (true);
    }
    else if (OrderType() == OP_SELL)
    {
      if (OrderStopLoss() != 0  &&  stopPrice > OrderStopLoss())
        return (true);
    }   
  
    double diff = MathAbs(OrderStopLoss() - stopPrice);
    double diffPoints = diff / Point;
    
    if (diffPoints < MINIMUM_STOP_MOVE_POINTS)
      return (true);
       
    bool ok = OrderReliableModify(ticket, OrderOpenPrice(), stopPrice, OrderTakeProfit(), 0);
    if (ok)
      return (true);
    else
    {
      Print("OrderModify failed: " + GetLastError());
      return (false);
    }
  }
}


void MoveStopToPrice_old(int ticket, double newStopPrice, bool overrideSafety = false)
{
  if (OrderSelect(ticket, SELECT_BY_TICKET))
  {
    // Never move stop away from price
    if (OrderType() == OP_BUY  ||  OrderType() == OP_BUYSTOP  ||  OrderType() == OP_BUYLIMIT)
    {
      if (overrideSafety  ||  newStopPrice > OrderStopLoss())
        _ModifyTicket(ticket, newStopPrice, OrderTakeProfit());
    }
    else
    {
      if (overrideSafety  ||  newStopPrice < OrderStopLoss())
        _ModifyTicket(ticket, newStopPrice, OrderTakeProfit());
    }
  }
}



//+------------------------------------------------------------------+
//| STATISTICS                                                       |
//+------------------------------------------------------------------+

void _LogTradeComplete(
  string app,
  int ticket,
  int orderType,
  datetime opentime,
  datetime closetime,
  string symbol,
  double openprice,
  double closeprice,
  double swap,
  double maxsl,
  double mae_price,
  double mfe_price,
  string ordercomment,
  string extracomment)
{
  string url = "http://forex.plasmatech.com/trade_complete.php?";
  int httpStatus[1];

  int digits = MarketInfo(symbol, MODE_DIGITS);
  string sopenprice = openprice;
  string scloseprice = closeprice;
  string smaxsl = maxsl;
  string smae_price = mae_price;
  string smfe_price = mfe_price;
  if (digits > 0)
  {
    sopenprice = DoubleToStr(openprice, digits);
    scloseprice = DoubleToStr(closeprice, digits);
    smaxsl = DoubleToStr(maxsl, digits);
    smae_price = DoubleToStr(mae_price, digits);
    smfe_price = DoubleToStr(mfe_price, digits);
  }
  
  url = url
    + "ticket=" + ticket
    + "&orderType=" + orderType
    + "&app=" + URLEncode(app)
    + "&opentime=" + opentime
    + "&closetime=" + closetime
    + "&symbol=" + symbol
    + "&openprice=" + sopenprice
    + "&closeprice=" + scloseprice
    + "&swap=" + swap
    + "&maxsl=" + smaxsl
    + "&mae_price=" + smae_price
    + "&mfe_price=" + smfe_price
    + "&ordercomment=" + URLEncode(ordercomment)
    + "&extracomment=" + URLEncode(extracomment)
    ;
  
  string result = httpGET(url, httpStatus);
  
  return (httpStatus[0] == 200);
}


//+------------------------------------------------------------------+
//| ORDER RELIABLE UTILLITIES                                        |
//+------------------------------------------------------------------+

int OrderReliableSend(string symbol, int op, double lotsize, double price, double spread, double stoploss, double takeprofit,
                      string comment, int magic, datetime expiry=0, color clr=CLR_NONE)
{
  int retries = 3;
  int ticket;
  int err;
  while (retries > 0)
  {
    ticket = OrderSend(symbol, op, lotsize, price, spread, 0, 0, comment, magic, 0, clr);
    err = GetLastError();
    
    if (ticket != 0  &&  err == ERR_NO_ERROR)
      break;      
    
    switch(ticket)
    {
      case ERR_SERVER_BUSY:
      case ERR_TOO_FREQUENT_REQUESTS:
      case ERR_NO_CONNECTION:
      case ERR_INVALID_PRICE:
      case ERR_OFF_QUOTES:
      case ERR_BROKER_BUSY:
      case ERR_TRADE_CONTEXT_BUSY:
        OrderReliableSleep(250 + RandomRange(1000));
        retries--;
        break;
      
      case ERR_PRICE_CHANGED:
      case ERR_REQUOTE:
        RefreshRates();
        break;
      
      default: 
        OrderReliableSleep(100 + RandomRange(250));
        retries--;
        break;
    }
  }
  
  if (retries == 0)
    return (0);
    
  // OrderReliableModify(ticket, price, stoploss, takeprofit, expiry, clr);
  
  return (ticket);
}


bool OrderReliableModify(int ticket, double price, double stoploss, double takeprofit, datetime expiry=0, color clr=CLR_NONE)
{
  int retries = 3;
  bool result;
  
  while (retries > 0)
  {
    result = OrderModify(ticket, price, stoploss, takeprofit, expiry, clr);
    int err = GetLastError();
    if (result || err == ERR_NO_RESULT)
      break;

    if (!result)
    {   
      switch(ticket)
      {
        case ERR_SERVER_BUSY:
        case ERR_TOO_FREQUENT_REQUESTS:
        case ERR_NO_CONNECTION:
        case ERR_INVALID_PRICE:
        case ERR_OFF_QUOTES:
        case ERR_BROKER_BUSY:
        case ERR_TRADE_CONTEXT_BUSY:
          OrderReliableSleep(250 + RandomRange(1000));
          retries--;
          break;

        case ERR_PRICE_CHANGED:
        case ERR_REQUOTE:
          RefreshRates();
          break;

        default: 
          OrderReliableSleep(100 + RandomRange(250));
          retries--;
      }
    }
  }
  
  return (retries != 0);
}


bool OrderReliableClose(int ticket, double lots, double price, double spread, color clr = CLR_NONE) 
{
  int retries = 3;
  bool result;
  
  while (retries > 0)
  {
    if (!IsTradeAllowed())
    {
      OrderReliableSleep(250 + RandomRange(1000));
      retries--;
      continue;
    }
    
    result = OrderClose(ticket, lots, price, spread, clr);
    int err = GetLastError();
    if (result || err == ERR_NO_RESULT)
      break;

    if (!result)
    {   
      switch(ticket)
      {
        case ERR_SERVER_BUSY:
        case ERR_TOO_FREQUENT_REQUESTS:
        case ERR_NO_CONNECTION:
        case ERR_INVALID_PRICE:
        case ERR_OFF_QUOTES:
        case ERR_BROKER_BUSY:
        case ERR_TRADE_CONTEXT_BUSY:
          OrderReliableSleep(250 + RandomRange(1000));
          retries--;
          break;

        case ERR_PRICE_CHANGED:
        case ERR_REQUOTE:
          RefreshRates();
          break;

        default: 
          OrderReliableSleep(100 + RandomRange(250));
          retries--;
      }
    }
  }

  return (retries != 0);
}


void OrderReliableSleep(int ms)
{
  if (!IsTesting())
    Sleep(ms);
}



//+------------------------------------------------------------------+
//| CALCULATION UTILITIES                                            |
//+------------------------------------------------------------------+

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
    
  double riskPoints = priceDifference/Point;
  
  double lotSize = (risk$ / riskPoints) / (MarketInfo(Symbol(), MODE_TICKVALUE));

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


int RandomRange(int range)
{
  return ((MathRand()/32767.0)*range);
}



//+------------------------------------------------------------------+
//| INDICATOR UTILITIES                                              |
//+------------------------------------------------------------------+

double FractionalBB(string symbol, int timeframe, int bandperiod, double banddeviation, int bandshift, int mode, int timebarshift=0)
{
  /*
     The iBands() function only takes integer deviations.
     This function provides fraction deviations.
  */
  int factor;
  switch (mode)
  {
    case MODE_SMA:    factor = 0; break;
    case MODE_UPPER:  factor = 1; break;
    case MODE_LOWER:  factor = -1; break;
    default:          return (0.0);
  }
  
  double midbb = iMA(symbol, timeframe, bandperiod, 0, MODE_SMA, PRICE_CLOSE, timebarshift);
  double deviation, sum, oldval, newres;

  sum=0.0;
  k = timebarshift + BollingerPeriod-1;
  oldval = midbb;
  while(k >= timebarshift)
  {
    newres = Close[k] - oldval;
    sum += newres*newres;     
    k--;
  }
  deviation = banddeviation * MathSqrt(sum / BollingerPeriod);;

  return (midbb + factor*deviation);
}



//+------------------------------------------------------------------+
//| WINDOWS UTILITIES                                                |
//+------------------------------------------------------------------+

#import "user32.dll"
   int GetKeyState(int virtKey);
#import

#define VK_LBUTTON  1
#define VK_MBUTTON  4
#define VK_RBUTTON  2

bool IsMouseDown()
{
  return (GetKeyState(VK_RBUTTON) >= 0x8000  ||  GetKeyState(VK_LBUTTON) >= 0x8000 );
}

