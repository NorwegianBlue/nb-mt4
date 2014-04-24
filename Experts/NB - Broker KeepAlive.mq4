//+------------------------------------------------------------------+
//|                                        NB - Broker KeepAlive.mq4 |
//|                             Copyright © 2011-2012, NorwegianBlue |
//|           http://sites.google.com/site/norwegianbluesmt4junkyard |

/*
  Keeps the connection to the broker alive by changing the properties of a pending 
  order every 20 seconds.
*/

#property copyright "Copyright © 2011-2012, NorwegianBlue"
#property link      "http://sites.google.com/site/norwegianbluesmt4junkyard"


extern bool Active = true;
extern int UpdateInterval_Seconds = 20;
extern int Magic = 8173;

int Ticket;

void init()
{
}

void deinit()
{
}

datetime NextUpdate;
int Toggles = 1;
int LastLagMS;

void start()
{
  if (!Active)
  {
    Comment("Not Active");
    return;
  }
  else
  {
    if (LastLagMS != 0)
      Comment("Latency: " + LastLagMS +  " ms");
  }
  
  if (TimeCurrent() < NextUpdate)
    return;
  
  if (Ticket == 0)
  {
    _FindTicket();
  
    if (Ticket == 0)
      _OpenTicket();
  }
  else
    _TickleTicket();
  
  if (LastLagMS != 0)
    Comment("Latency: " + LastLagMS +  " ms");
  
  NextUpdate = TimeCurrent() + UpdateInterval_Seconds;
  Toggles++;
}


void _FindTicket()
{
  for (int i=0; i<OrdersTotal(); i++)
    if (OrderSelect(i, SELECT_BY_POS))
      if (OrderMagicNumber() == Magic   &&  OrderSymbol() == Symbol())
      {
        Ticket = OrderTicket();
        break;
      }
}


void _TickleTicket()
{
  if (!OrderSelect(Ticket, SELECT_BY_TICKET))
  {
    Ticket = 0;
    _FindTicket();
    if (Ticket == 0)
      _OpenTicket();
  }
  else
  {
    int startTime = GetTickCount();
    OrderModify(Ticket,  Point + Point*(Toggles % 2), 0, 0, 0);
    LastLagMS = GetTickCount() - startTime;
  }
}


void _OpenTicket()
{
  int startTime = GetTickCount();
  Ticket = OrderSend(Symbol(), OP_BUYLIMIT, 0.01, Point, Point, 0.0, 0.0, "Broker KeepAlive", Magic);
  LastLagMS = GetTickCount() - startTime;
}

