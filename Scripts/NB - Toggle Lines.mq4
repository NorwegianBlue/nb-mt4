//+------------------------------------------------------------------+
//|                                            NB - Toggle Lines.mq4 |
//|                                  Copyright © 2012, NorwegianBlue |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2012, NorwegianBlue"
#property link      ""


bool HasSavedDetails(string lineName)
{
  return (StringFind(ObjectDescription(lineName), "@@") >= 0);
}


void SaveLineDetails(string lineName)
{
  string desc = ObjectDescription(lineName) + "@@";
  
  int timeframes = (int) ObjectGet(lineName, OBJPROP_TIMEFRAMES);
  ObjectSetText(lineName, desc + timeframes);
  ObjectSet(lineName, OBJPROP_TIMEFRAMES, -1);
}


void RestoreLineDetails(string lineName)
{
  int pos = StringFind(ObjectDescription(lineName), "@@");
  if (pos >= 0)
  {
    int timeframes = StrToInteger(StringSubstr(ObjectDescription(lineName), pos+2));
    ObjectSet(lineName, OBJPROP_TIMEFRAMES, timeframes);    
    if (pos == 0)
      ObjectSetText(lineName, "");
    else
      ObjectSetText(lineName, StringSubstr(ObjectDescription(lineName), 0, pos));
  }
}


bool IsTypeOk(string name)
{
  int type = ObjectType(name);
  return (type != OBJ_TEXT  &&  type != OBJ_LABEL);
}


int start()
{
  bool anyWithoutDetails = false;

  // If all lines have saved details, and none don't have saved details, then restore all lines
  // Otherwise, save the details for the lines that don't have details saved already.
  // Details are saved in the object description.
  
  int objidx;  
  string name;
  
  for (objidx=0; objidx<ObjectsTotal() && !anyWithoutDetails; objidx++)
  {
    name = ObjectName(objidx);
    if (IsTypeOk(name))
      anyWithoutDetails = !HasSavedDetails(name);
  }
  
  if (anyWithoutDetails)
  { // Save
    for (objidx=0; objidx<ObjectsTotal(); objidx++)
    {
      name = ObjectName(objidx);
      if (IsTypeOk(name) && !HasSavedDetails(name))
        SaveLineDetails(name);
    }
  }
  else
  { // Restore
    for (objidx=0; objidx<ObjectsTotal(); objidx++)
    {
      RestoreLineDetails(ObjectName(objidx));
    }
  }

  return(0);
}

