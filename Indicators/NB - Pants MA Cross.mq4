//+------------------------------------------------------------------+
//|                                          NB - Pants MA Cross.mq4 |
//|                                                        Version 1 |
//|                                  Copyright © 2013, NorwegianBlue |
//|           http://sites.google.com/site/norwegianbluesmt4junkyard |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2013, NorwegianBlue"
#property link      "http://sites.google.com/site/norwegianbluesmt4junkyard"

#property indicator_chart_window
#property indicator_buffers 4
#property indicator_color1 Aqua
#property indicator_color2 Yellow
#property indicator_color3 Aqua
#property indicator_color4 Yellow
#property indicator_style1 STYLE_SOLID
#property indicator_style2 STYLE_SOLID
#property indicator_style3 STYLE_SOLID
#property indicator_style4 STYLE_SOLID
#property indicator_width3 2
#property indicator_width4 2

//--- input parameters
extern int       LWMA_Fast_Period=9;
extern int       LWMA_Slow_Period=14;
extern int       SMA_Short=0;
extern int       SMA_Long=0;


//--- buffers
double LWMAFast[];
double LWMASlow[];
double SMAShort[];
double SMALong[];

int init()
{
  IndicatorBuffers(7);
  SetIndexStyle(0,DRAW_LINE);
  SetIndexBuffer(0,LWMAFast);
  SetIndexStyle(1,DRAW_LINE);
  SetIndexBuffer(1,LWMASlow);
  SetIndexStyle(2,DRAW_LINE);
  SetIndexBuffer(2,SMAShort);
  SetIndexStyle(3,DRAW_LINE);
  SetIndexBuffer(3,SMALong);
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
      LWMAFast[i] = iMA(NULL, 0, LWMA_Fast_Period, 0, MODE_LWMA, PRICE_CLOSE, i);
      if (LWMAFast[i] <= 0)
        LWMAFast[i] = EMPTY_VALUE;
      LWMASlow[i] = iMA(NULL, 0, LWMA_Slow_Period, 0, MODE_LWMA, PRICE_CLOSE, i);
      if (LWMASlow[i] <= 0)
        LWMASlow[i] = EMPTY_VALUE;
      
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