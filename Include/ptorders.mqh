//+------------------------------------------------------------------+
//|                                          Reliable Order Handling |
//|                              Copyright © 2010, Timar Investments |
//|                               http://www.timarinvestments.com.au |
//+-----------------------------------------------------------------+

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
    
    Print("OrderReliableSend: retries remaining ", retries, "  error: " + ErrorDescription(err));
    if (IsTesting())
      return (0);

    switch(err)
    {
      case ERR_SERVER_BUSY:
      case ERR_TOO_FREQUENT_REQUESTS:
      case ERR_NO_CONNECTION:
      case ERR_INVALID_PRICE:
      case ERR_OFF_QUOTES:
      case ERR_BROKER_BUSY:
      case ERR_TRADE_CONTEXT_BUSY:
        OrderReliableSleep(250 + OrderReliableRandomRange(1000));
        retries--;
        break;
      
      case ERR_PRICE_CHANGED:
      case ERR_REQUOTE:
        RefreshRates();
        break;
      
      default: 
        OrderReliableSleep(100 + OrderReliableRandomRange(250));
        retries--;
        break;
    }
  }
  
  if (retries == 0)
    return (0);
    
  if (!OrderReliableModify(ticket, price, stoploss, takeprofit, expiry, clr))
    Print("Initial call to OrderReliableModify() failed");
  
  return (ticket);
}


bool OrderReliableClose(int ticket, double lots = 0, double price = 0, double spread = 0, color clr = CLR_NONE) 
{
  int retries = 5;
  bool result;
  
  if (!OrderSelect(ticket, SELECT_BY_TICKET))
    return (false);
    
  if (lots == 0)
    lots = OrderLots();
    
  if (price == 0)
  {
    if (OrderType() == OP_BUY)
      price = Bid;
    else
      price = Ask;
  }
  
  if (spread == 0)
    spread = Ask-Bid;
  
  while (retries > 0)
  {
    if (!IsTradeAllowed())
    {
      OrderReliableSleep(250 + OrderReliableRandomRange(1000));
      retries--;
      continue;
    }
    
    result = OrderClose(ticket, lots, price, spread, clr);
    int err = GetLastError();
    if (result || err == ERR_NO_RESULT)
      break;
      
    if (IsTesting())
      return (false);

    if (!result)
    {   
      Print("OrderReliableClose: retries remaining ", retries, "  error: " + ErrorDescription(err));
      switch(err)
      {
        case ERR_SERVER_BUSY:
        case ERR_TOO_FREQUENT_REQUESTS:
        case ERR_NO_CONNECTION:
        case ERR_INVALID_PRICE:
        case ERR_OFF_QUOTES:
        case ERR_BROKER_BUSY:
        case ERR_TRADE_CONTEXT_BUSY:
          OrderReliableSleep(250 + OrderReliableRandomRange(1000));
          retries--;
          break;

        case ERR_PRICE_CHANGED:
        case ERR_REQUOTE:
          RefreshRates();
          break;

        default: 
          OrderReliableSleep(100 + OrderReliableRandomRange(250));
          retries--;
      }
    }
  }

  return (retries != 0);
}


bool OrderReliableModify(int ticket, double price, double stoploss, double takeprofit, datetime expiry=0, color clr=CLR_NONE)
{
  int retries = 5;
  bool result;
  
  while (retries > 0)
  {
    result = OrderModify(ticket, price, stoploss, takeprofit, expiry, clr);
    int err = GetLastError();
    if (result || err == ERR_NO_RESULT)
      return (true);

    if (IsTesting())
      return (false);

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
          OrderReliableSleep(250 + OrderReliableRandomRange(1000));
          retries--;
          break;

        case ERR_PRICE_CHANGED:
        case ERR_REQUOTE:
          RefreshRates();
          break;
          
        case ERR_INVALID_PRICE:
        case ERR_INVALID_STOPS:
        case ERR_INVALID_TRADE_VOLUME:
          return (false);
          break;
          

        default: 
          OrderReliableSleep(100 + OrderReliableRandomRange(250));
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


int OrderReliableRandomRange(int range)
{
  return ((MathRand()/32767.0)*range);
}

