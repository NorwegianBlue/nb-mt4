//+------------------------------------------------------------------+
//|                                                    nbwininet.mqh |
//|                                    Copyright 2014, NorwegianBlue |
//+------------------------------------------------------------------+
#property copyright "Copyright 2014, NorwegianBlue"
#property link      " "
#property strict

#import  "Wininet.dll"
   int InternetOpenW(string, int, string, string, int);
   int InternetConnectW(int, string, int, string, string, int, int, int); 
   int HttpOpenRequestW(int, string, string, int, string, int, string, int); 
   int InternetOpenUrlW(int, string, string, int, int, int);
   int InternetReadFile(int, uchar&[], int, int& OneInt[]);
   int InternetCloseHandle(int); 
#import "ntdll.dll"
   int  RtlGetLastWin32Error();
#import


string httpGET(string URL, int& status)
{
   int HttpOpen = InternetOpenW(" ", 0, " "," ",0 ); 
   if (HttpOpen == 0)
   {
     status = RtlGetLastWin32Error();
     return "";
   }
   
   int HttpRequest = InternetOpenUrlW(HttpOpen,URL, NULL, 0, 0, 0);
   if (HttpRequest == 0)
   {
     status = RtlGetLastWin32Error();
     return "";
   }
   
   int read[1];
   uchar buffer[2048];
   string result = "";
 
   while (true)
   {
      InternetReadFile(HttpRequest, buffer, ArraySize(buffer), read);
      if (read[0] > 0)
        result = result + CharArrayToString(buffer, 0, read[0]);
      else
        break;
   } 
   
   if (HttpRequest > 0) InternetCloseHandle(HttpRequest); 
   if (HttpOpen > 0) InternetCloseHandle(HttpOpen);
   
   status = 200;
   return result;
}


string URLEncode(string toCode) {
  int max = StringLen(toCode);

  string RetStr = "";
  for(int i=0;i<max;i++) {
    string c = StringSubstr(toCode,i,1);
    int  asc = StringGetChar(c, 0);

    if((asc > 47 && asc < 58) || (asc > 64 && asc < 91) || (asc > 96 && asc < 123)) 
      RetStr = StringConcatenate(RetStr,c);
    else if (asc == 32)
      RetStr = StringConcatenate(RetStr,"+");
    else {
      RetStr = StringConcatenate(RetStr,"%",hex(asc));
    }
  }
  return (RetStr);
}


string hex(int i) {
   static string h =  "0123456789ABCDEF";
   string ret="";
   int a = i % 16;
   int b = (i-a)/16;
   if (b>15) ret = StringConcatenate(hex(b), StringSubstr(h,a,1));
   else      ret = StringConcatenate(StringSubstr(h, b ,1), StringSubstr(h,a,1));
   
   return (ret);
}
