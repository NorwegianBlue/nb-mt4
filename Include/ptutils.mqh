#import "ptutils.dll"
  void CopyTextToClipboard(string text);
  void DebugLog(string text);
  void DebugLog2(int msgType, string text);
  
  // read/write INI files
#import

void Log(int msgType, string message)
{
  DebugLog2(msgType, message);
}  


