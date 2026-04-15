//+------------------------------------------------------------------+
//|                                        JPTime_MarketClock.mq4   |
//|           日本時間・マーケットセッション表示インジケーター           |
//|   サーバー時間/JST/東京・ロンドン・NY市場の状態をチャートに常時表示  |
//+------------------------------------------------------------------+
#property strict
#property copyright   "JPTime_MarketClock v1.11"
#property description "サーバー時間とJST、各市場のセッション状態を表示するインジケーター(DST自動判定版)"
#property version     "1.11"
#property indicator_chart_window
#property indicator_buffers 0

//--- オブジェクト名プレフィックス（他インジケーターとの重複防止）
#define LBL_TITLE   "JPMC_title"
#define LBL_SERVER  "JPMC_server"
#define LBL_JST     "JPMC_jst"
#define LBL_SEP     "JPMC_sep"
#define LBL_TOKYO   "JPMC_tokyo"
#define LBL_LONDON  "JPMC_london"
#define LBL_NY      "JPMC_ny"

//=======================================================================
//  入力パラメーター
//=======================================================================
input int    InpFontSize          = 10;          // フォントサイズ (px)
input string InpFontName          = "MS ゴシック"; // フォント名 ※日本語対応の等幅フォント推奨
input color  InpColorOpen         = clrLime;     // オープン中の文字色
input color  InpColorClose        = clrGray;     // クローズ中の文字色
input color  InpColorTime         = clrWhite;    // 時刻表示の文字色
input color  InpColorTitle        = clrAqua;     // タイトル行の文字色
input int    InpPosX              = 10;          // X位置 (左端からpx)
input int    InpPosY              = 20;          // Y位置 (上端からpx)
input int    InpLineHeight        = 20;          // 行間 (px)
input int    InpBrokerWinterUTC   = 2;           // ブローカーの冬時間UTCオフセット(時) ※EETなら2
input bool   InpBrokerFollowsEUDST= true;        // ブローカーがEU夏時間に追従する(true=自動+1時間)

//--- 一括削除用のラベル名配列
string g_labelNames[7];

//=======================================================================
//  夏時間（DST）判定関数
//=======================================================================

//+------------------------------------------------------------------+
//| 指定した年月の "N番目の日曜日" を UTC 00:00 の datetime で返す     |
//+------------------------------------------------------------------+
datetime NthSunday(const int year, const int month, const int n)
{
   datetime firstDay = StrToTime(StringFormat("%04d.%02d.01 00:00", year, month));
   int      dow      = TimeDayOfWeek(firstDay); // 0=日曜
   int      firstSunDay = (dow == 0) ? 1 : (8 - dow);
   int      targetDay   = firstSunDay + (n - 1) * 7;
   return firstDay + (targetDay - 1) * 86400;
}

//+------------------------------------------------------------------+
//| 指定した年月の "最終日曜日" を UTC 00:00 の datetime で返す        |
//+------------------------------------------------------------------+
datetime LastSunday(const int year, const int month)
{
   int nm = month + 1;
   int ny = year;
   if(nm > 12) { nm = 1; ny++; }

   datetime lastDay = StrToTime(StringFormat("%04d.%02d.01 00:00", ny, nm)) - 86400;
   int      dow     = TimeDayOfWeek(lastDay);
   return lastDay - dow * 86400;
}

//+------------------------------------------------------------------+
//| EU夏時間(BST/CEST/EEST)が有効かを判定する                         |
//| 有効期間: 3月最終日曜 01:00 UTC ～ 10月最終日曜 01:00 UTC          |
//+------------------------------------------------------------------+
bool IsEUDST(const datetime utcTime)
{
   int      y        = TimeYear(utcTime);
   datetime dstStart = LastSunday(y, 3)  + 3600;
   datetime dstEnd   = LastSunday(y, 10) + 3600;
   return (utcTime >= dstStart && utcTime < dstEnd);
}

//+------------------------------------------------------------------+
//| 米国夏時間(EDT)が有効かを判定する                                  |
//| 有効期間: 3月第2日曜 07:00 UTC ～ 11月第1日曜 06:00 UTC            |
//+------------------------------------------------------------------+
bool IsUSDST(const datetime utcTime)
{
   int      y        = TimeYear(utcTime);
   datetime dstStart = NthSunday(y, 3,  2) + 7 * 3600;
   datetime dstEnd   = NthSunday(y, 11, 1) + 6 * 3600;
   return (utcTime >= dstStart && utcTime < dstEnd);
}

//+------------------------------------------------------------------+
//| 現在のブローカーUTCオフセットを返す                                |
//| 冬時間 = InpBrokerWinterUTC                                       |
//| EU夏時間中かつ InpBrokerFollowsEUDST=true なら +1                  |
//+------------------------------------------------------------------+
int GetBrokerUTCOffset(const datetime serverTime)
{
   int offset = InpBrokerWinterUTC;
   if(!InpBrokerFollowsEUDST) return offset;

   // 仮のUTCを計算してEU DST判定に使う（差1時間あっても判定境界から離れていればOK）
   datetime approxUTC = serverTime - offset * 3600;
   if(IsEUDST(approxUTC)) offset += 1;
   return offset;
}

//=======================================================================
//  ラベル操作ヘルパー関数
//=======================================================================
bool CreateLabel(const string name, const int x, const int y,
                 const string text, const color clr)
{
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);

   if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0))
   {
      int err = GetLastError();
      Print("[JPMC] ラベル作成失敗: name=", name, " error=", err);
      return false;
   }

   ObjectSetInteger(0, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   InpFontSize);
   ObjectSetString(0,  name, OBJPROP_FONT,       InpFontName);
   ObjectSetString(0,  name, OBJPROP_TEXT,       text);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
   return true;
}

void UpdateLabel(const string name, const string text, const color clr)
{
   if(ObjectFind(0, name) < 0) return;
   ObjectSetString(0,  name, OBJPROP_TEXT,  text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

void DeleteAllLabels()
{
   for(int i = 0; i < ArraySize(g_labelNames); i++)
   {
      if(ObjectFind(0, g_labelNames[i]) >= 0)
         ObjectDelete(0, g_labelNames[i]);
   }
}

//=======================================================================
//  セッション状態計算
//=======================================================================
void GetSessionStatus(const int utcSec, const int openSec, const int closeSec,
                      bool &isOpen, int &remaining)
{
   if(utcSec >= openSec && utcSec < closeSec)
   {
      isOpen    = true;
      remaining = closeSec - utcSec;
   }
   else
   {
      isOpen = false;
      if(utcSec < openSec)
         remaining = openSec - utcSec;
      else
         remaining = (86400 - utcSec) + openSec;
   }
}

//=======================================================================
//  フォーマット関数
//=======================================================================
string FormatTimeHMS(const datetime t)
{
   return StringFormat("%02d:%02d:%02d", TimeHour(t), TimeMinute(t), TimeSeconds(t));
}

string FormatHHMM(const int totalSec)
{
   int s = (totalSec < 0) ? 0 : totalSec;
   return StringFormat("%02d:%02d", s / 3600, (s % 3600) / 60);
}

//=======================================================================
//  表示更新（メイン処理）
//=======================================================================
void UpdateDisplay()
{
   //--- 時刻の取得と変換 ─────────────────────────────────────────
   datetime serverTime = TimeCurrent();
   int      brokerUTC  = GetBrokerUTCOffset(serverTime);         // DST自動判定済みオフセット
   datetime utcTime    = serverTime - brokerUTC * 3600;          // UTCに変換
   datetime jstTime    = utcTime    + 9 * 3600;                  // JST(UTC+9)

   // UTCの"今日の00:00:00からの経過秒数"（long演算で安全に）
   long utcSecLong = ((long)utcTime) % 86400;
   if(utcSecLong < 0) utcSecLong += 86400;                       // 念のため
   int  utcSec     = (int)utcSecLong;

   //--- DST判定 ─────────────────────────────────────────────────
   bool euDST = IsEUDST(utcTime);
   bool usDST = IsUSDST(utcTime);

   //--- 各市場のセッション時間（UTC秒）──────────────────────────
   // 【東京】9:00-15:00 JST = 00:00-06:00 UTC
   int tokyoOpnSec = 0;
   int tokyoClsSec = 21600;

   // 【ロンドン】BST(+1)時: 07-16 UTC / GMT(+0)時: 08-17 UTC
   int londonOpnSec = euDST ? (7  * 3600) : (8  * 3600);
   int londonClsSec = euDST ? (16 * 3600) : (17 * 3600);

   // 【NY】EDT(-4)時: 12-21 UTC / EST(-5)時: 13-22 UTC
   int nyOpnSec = usDST ? (12 * 3600) : (13 * 3600);
   int nyClsSec = usDST ? (21 * 3600) : (22 * 3600);

   //--- 各セッション状態判定 ────────────────────────────────────
   bool tokyoIsOpen,  londonIsOpen,  nyIsOpen;
   int  tokyoRemain,  londonRemain,  nyRemain;

   GetSessionStatus(utcSec, tokyoOpnSec,  tokyoClsSec,  tokyoIsOpen,  tokyoRemain);
   GetSessionStatus(utcSec, londonOpnSec, londonClsSec, londonIsOpen, londonRemain);
   GetSessionStatus(utcSec, nyOpnSec,     nyClsSec,     nyIsOpen,     nyRemain);

   //--- 表示用テキスト組み立て ──────────────────────────────────
   string dstStr = StringFormat("%s/%s",
                                 euDST ? "EU夏" : "EU冬",
                                 usDST ? "US夏" : "US冬");

   string tokyoLine = StringFormat("東京   [%s] %s %s",
      tokyoIsOpen  ? "OPEN " : "CLOSE",
      tokyoIsOpen  ? "残" : "後",
      FormatHHMM(tokyoRemain));

   string londonLine = StringFormat("London [%s] %s %s (%s)",
      londonIsOpen ? "OPEN " : "CLOSE",
      londonIsOpen ? "残" : "後",
      FormatHHMM(londonRemain),
      euDST ? "BST" : "GMT");

   string nyLine = StringFormat("NY     [%s] %s %s (%s)",
      nyIsOpen     ? "OPEN " : "CLOSE",
      nyIsOpen     ? "残" : "後",
      FormatHHMM(nyRemain),
      usDST ? "EDT" : "EST");

   //--- ラベル更新 ──────────────────────────────────────────────
   UpdateLabel(LBL_TITLE,
               "=== Market Clock ===",
               InpColorTitle);

   UpdateLabel(LBL_SERVER,
               StringFormat("Server : %s (UTC%+d)",
                             FormatTimeHMS(serverTime), brokerUTC),
               InpColorTime);

   UpdateLabel(LBL_JST,
               StringFormat("JST    : %s [%s]",
                             FormatTimeHMS(jstTime), dstStr),
               InpColorTime);

   UpdateLabel(LBL_SEP,
               "--------------------",
               InpColorClose);

   UpdateLabel(LBL_TOKYO,  tokyoLine,  tokyoIsOpen  ? InpColorOpen : InpColorClose);
   UpdateLabel(LBL_LONDON, londonLine, londonIsOpen ? InpColorOpen : InpColorClose);
   UpdateLabel(LBL_NY,     nyLine,     nyIsOpen     ? InpColorOpen : InpColorClose);

   ChartRedraw(0);
}

//=======================================================================
//  MQL4 必須コールバック
//=======================================================================
int OnInit()
{
   g_labelNames[0] = LBL_TITLE;
   g_labelNames[1] = LBL_SERVER;
   g_labelNames[2] = LBL_JST;
   g_labelNames[3] = LBL_SEP;
   g_labelNames[4] = LBL_TOKYO;
   g_labelNames[5] = LBL_LONDON;
   g_labelNames[6] = LBL_NY;

   DeleteAllLabels();

   int y = InpPosY;
   int x = InpPosX;

   if(!CreateLabel(LBL_TITLE,  x, y, "", InpColorTitle))  return INIT_FAILED; y += InpLineHeight;
   if(!CreateLabel(LBL_SERVER, x, y, "", InpColorTime))   return INIT_FAILED; y += InpLineHeight;
   if(!CreateLabel(LBL_JST,    x, y, "", InpColorTime))   return INIT_FAILED; y += InpLineHeight;
   if(!CreateLabel(LBL_SEP,    x, y, "", InpColorClose))  return INIT_FAILED; y += InpLineHeight;
   if(!CreateLabel(LBL_TOKYO,  x, y, "", InpColorClose))  return INIT_FAILED; y += InpLineHeight;
   if(!CreateLabel(LBL_LONDON, x, y, "", InpColorClose))  return INIT_FAILED; y += InpLineHeight;
   if(!CreateLabel(LBL_NY,     x, y, "", InpColorClose))  return INIT_FAILED;

   if(!EventSetTimer(1))
   {
      Print("[JPMC] EventSetTimer 失敗 error=", GetLastError());
      return INIT_FAILED;
   }

   UpdateDisplay();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   DeleteAllLabels();
   ChartRedraw(0);
}

void OnTimer()
{
   UpdateDisplay();
}

int OnCalculate(const int      rates_total,
                const int      prev_calculated,
                const datetime &time[],
                const double   &open[],
                const double   &high[],
                const double   &low[],
                const double   &close[],
                const long     &tick_volume[],
                const long     &volume[],
                const int      &spread[])
{
   UpdateDisplay();
   return rates_total;
}
//+------------------------------------------------------------------+
