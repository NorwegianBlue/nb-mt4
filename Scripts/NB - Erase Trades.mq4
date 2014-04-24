//+------------------------------------------------------------------+
//|                                            NB - Erase Trades.mq4 |
//|                                  Copyright © 2011, NorwegianBlue |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2011, NorwegianBlue"
#property link      ""

int start()
{
  // Looking for Trendline and Arrows that have a "Name" staring with "#"
  for (int i=ObjectsTotal()-1; i>=0; i--)
  {
    string name = ObjectName(i);
    if (name != ""  &&  StringGetChar(name, 0) == '#'  &&  (ObjectType(name) == OBJ_TREND  || ObjectType(name) == OBJ_ARROW))
      ObjectDelete(name);
  }

  return (0);
}

