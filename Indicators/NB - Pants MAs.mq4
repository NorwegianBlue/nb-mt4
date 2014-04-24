//+------------------------------------------------------------------+
//|                                               NB - Pants MAs.mq4 |
//|                                                        Version 2 |
//|                                  Copyright © 2012, NorwegianBlue |
//|           http://sites.google.com/site/norwegianbluesmt4junkyard |
//|                                                                  |
//| Version 2                                                        |
//|   Better handling of MAs where there is insufficient data to     |
//|   to calculate the point                                         |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2012, NorwegianBlue"
#property link      "http://sites.google.com/site/norwegianbluesmt4junkyard"

#property indicator_chart_window
#property indicator_buffers 7
#property indicator_color1 Maroon
#property indicator_color2 Maroon
#property indicator_color3 MediumSeaGreen
#property indicator_color4 MediumSeaGreen
#property indicator_color5 DeepSkyBlue
#property indicator_color6 Aqua
#property indicator_color7 Yellow
#property indicator_style1 STYLE_DOT
#property indicator_style2 STYLE_DOT
#property indicator_style3 STYLE_DOT
#property indicator_style4 STYLE_DOT
#property indicator_style5 STYLE_SOLID
#property indicator_style6 STYLE_SOLID
#property indicator_style7 STYLE_SOLID
#property indicator_width6 2
#property indicator_width7 2

//--- input parameters
extern int       LWMA_Fast_Period=2;
extern int       LWMA_Slow_Period=4;
extern int       EMA_Period=14;
extern int       SMA_Short=0;
extern int       SMA_Long=0;


//--- buffers
double LWMAFastHigh[];
double LWMAFastLow[];
double LWMASlowHigh[];
double LWMASlowLow[];
double EMA[];
double SMAShort[];
double SMALong[];

int init()
{
  IndicatorBuffers(7);
  SetIndexStyle(0,DRAW_LINE);
  SetIndexBuffer(0,LWMAFastHigh);
  SetIndexStyle(1,DRAW_LINE);
  SetIndexBuffer(1,LWMAFastLow);
  SetIndexStyle(2,DRAW_LINE);
  SetIndexBuffer(2,LWMASlowHigh);
  SetIndexStyle(3,DRAW_LINE);
  SetIndexBuffer(3,LWMASlowLow);
  SetIndexStyle(4,DRAW_LINE);
  SetIndexBuffer(4,EMA);
  SetIndexStyle(5,DRAW_LINE);
  SetIndexBuffer(5,SMAShort);
  SetIndexStyle(6,DRAW_LINE);
  SetIndexBuffer(6,SMALong);
  return(0);
}


int deinit()
{
  return(0);
}


int start()
{
   int counted_bars=IndicatorCounted();
   if (counted_bars>0) counted_bars--;
   int limit=Bars-counted_bars;

   for(int i=0; i<limit; i++)
   {
      LWMAFastHigh[i] = iMA(NULL, 0, LWMA_Fast_Period, 0, MODE_LWMA, PRICE_HIGH, i);
      LWMAFastLow[i]  = iMA(NULL, 0, LWMA_Fast_Period, 0, MODE_LWMA, PRICE_LOW,  i);
      
      LWMASlowHigh[i] = iMA(NULL, 0, LWMA_Slow_Period, 0, MODE_LWMA, PRICE_HIGH, i);
      LWMASlowLow[i]  = iMA(NULL, 0, LWMA_Slow_Period, 0, MODE_LWMA, PRICE_LOW,  i);
      
      EMA[i] = iMA(NULL, 0, EMA_Period, 0, MODE_EMA, PRICE_CLOSE, i);
      if (EMA[i] <= 0)
        EMA[i] = EMPTY_VALUE;
      
      SMAShort[i] = iMA(NULL, 0, SMA_Short, 0, MODE_SMA, PRICE_CLOSE, i);
      if (SMAShort[i] <= 0)
        SMAShort[i] = EMPTY_VALUE;
      
      SMALong[i]  = iMA(NULL, 0, SMA_Long,  0, MODE_SMA, PRICE_CLOSE, i);
      if (SMALong[i] <= 0)
        SMALong[i] = EMPTY_VALUE;
   }

  return(0);
}

//+------------------------------------------------------------------+