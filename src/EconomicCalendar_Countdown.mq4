//+------------------------------------------------------------------+
//|                              EconomicCalendar_Countdown.mq4      |
//|  次回の重要経済指標までの残り時間をチャートに常時表示する         |
//|  機能:                                                            |
//|    - CSV(datetime_jst,currency,name,importance)を読み込み         |
//|    - 対象通貨・重要度でフィルタリング                             |
//|    - 直近5件を重要度別の色でカウントダウン表示                    |
//|    - 指定分前にアラート(ポップアップ/プッシュ)を発動              |
//|    - EU夏時間を自動判定してブローカー時刻→JSTに正しく変換         |
//+------------------------------------------------------------------+
#property strict
#property copyright   "EconomicCalendar_Countdown v1.00"
#property description "次回の重要経済指標までの残り時間を常時表示するインジケーター"
#property version     "1.00"
#property indicator_chart_window
#property indicator_buffers 0

//--- 定数
#define ECC_MAX_EVENTS   500         // CSV最大行数(メモリ上限)
#define ECC_SHOW_LINES   5           // 画面に表示する件数
#define ECC_PREFIX       "ECC_"      // オブジェクト名プレフィックス

//--- 表示コーナー列挙
enum ENUM_ECC_CORNER
  {
   ECC_CORNER_LEFT_UPPER  = 0,  // 左上
   ECC_CORNER_RIGHT_UPPER = 1,  // 右上
   ECC_CORNER_LEFT_LOWER  = 2,  // 左下
   ECC_CORNER_RIGHT_LOWER = 3   // 右下
  };

//=======================================================================
//  入力パラメーター
//=======================================================================
input string           ECC_CsvFileName       = "economic_calendar.csv"; // CSVファイル名 (MQL4\Files配下)
input string           ECC_FilterCurrencies  = "USD,EUR,JPY";           // 表示対象通貨(カンマ区切り)
input int              ECC_MinImportance     = 2;                       // 表示する最低重要度 (1=低 / 2=中 / 3=高)
input int              ECC_AlertMinutesBefore= 15;                      // 何分前にアラート発動するか
input bool             ECC_UseAlert          = true;                    // ポップアップ+サウンドを使用
input bool             ECC_UsePush           = false;                   // プッシュ通知を使用
input ENUM_ECC_CORNER  ECC_DisplayCorner     = ECC_CORNER_RIGHT_UPPER;  // 表示コーナー
input color            ECC_ColorHigh         = clrOrangeRed;            // 重要度★★★の文字色
input color            ECC_ColorMid          = clrGold;                 // 重要度★★の文字色
input color            ECC_ColorLow          = clrSilver;               // 重要度★の文字色
input color            ECC_ColorTitle        = clrAqua;                 // タイトル行の色
input color            ECC_ColorTime         = clrWhite;                // 現在時刻行の色
input int              ECC_FontSize          = 10;                      // フォントサイズ(px)
input string           ECC_FontName          = "MS ゴシック";           // フォント名(日本語対応)
input int              ECC_PosX              = 10;                      // 表示のX余白(px)
input int              ECC_PosY              = 20;                      // 表示のY余白(px)
input int              ECC_LineHeight        = 18;                      // 行間(px)
input int              ECC_BrokerWinterUTC   = 2;                       // ブローカー冬時間UTCオフセット(時) EETなら2
input bool             ECC_BrokerFollowsEUDST= true;                    // EU夏時間に自動追従(+1時間)

//=======================================================================
//  内部変数
//=======================================================================
datetime g_eventTime[ECC_MAX_EVENTS];        // イベント時刻(JST)
string   g_eventCurrency[ECC_MAX_EVENTS];    // 通貨コード
string   g_eventName[ECC_MAX_EVENTS];        // 指標名
int      g_eventImp[ECC_MAX_EVENTS];         // 重要度 1-3
bool     g_eventAlerted[ECC_MAX_EVENTS];     // アラート発動済みフラグ
int      g_eventCount = 0;                   // 読み込み済み件数

string   g_labelTitle  = ECC_PREFIX + "title";
string   g_labelTime   = ECC_PREFIX + "time";
string   g_labelSep    = ECC_PREFIX + "sep";
string   g_labelLine[ECC_SHOW_LINES];        // 各イベント行

//=======================================================================
//  DST判定関数
//=======================================================================

//+------------------------------------------------------------------+
//| 指定した年月の "最終日曜日" を UTC 00:00 の datetime で返す        |
//+------------------------------------------------------------------+
datetime ECC_LastSunday(const int year, const int month)
  {
   int nm = month + 1;
   int ny = year;
   if(nm > 12) { nm = 1; ny++; }
   datetime lastDay = StrToTime(StringFormat("%04d.%02d.01 00:00", ny, nm)) - 86400;
   int      dow     = TimeDayOfWeek(lastDay);
   return lastDay - dow * 86400;
  }

//+------------------------------------------------------------------+
//| EU夏時間が有効かを判定(3月最終日曜01:00UTC～10月最終日曜01:00UTC) |
//+------------------------------------------------------------------+
bool ECC_IsEUDST(const datetime utcTime)
  {
   int      y        = TimeYear(utcTime);
   datetime dstStart = ECC_LastSunday(y, 3)  + 3600;
   datetime dstEnd   = ECC_LastSunday(y, 10) + 3600;
   return (utcTime >= dstStart && utcTime < dstEnd);
  }

//+------------------------------------------------------------------+
//| 現在のブローカーUTCオフセット(DST考慮)                             |
//+------------------------------------------------------------------+
int ECC_GetBrokerUTCOffset(const datetime serverTime)
  {
   int offset = ECC_BrokerWinterUTC;
   if(!ECC_BrokerFollowsEUDST) return offset;
   datetime approxUTC = serverTime - offset * 3600;
   if(ECC_IsEUDST(approxUTC)) offset += 1;
   return offset;
  }

//+------------------------------------------------------------------+
//| 現在のJSTを返す                                                   |
//+------------------------------------------------------------------+
datetime ECC_GetJSTNow()
  {
   datetime serverTime = TimeCurrent();
   int      brokerUTC  = ECC_GetBrokerUTCOffset(serverTime);
   datetime utcTime    = serverTime - brokerUTC * 3600;
   return utcTime + 9 * 3600;
  }

//=======================================================================
//  文字列ユーティリティ
//=======================================================================

//+------------------------------------------------------------------+
//| カンマ区切り文字列を配列に分割して返す(要素数を戻り値で返す)      |
//+------------------------------------------------------------------+
int ECC_SplitCSVString(const string src, string &out[])
  {
   ArrayResize(out, 0);
   int start = 0;
   int len   = StringLen(src);
   for(int i = 0; i <= len; i++)
     {
      if(i == len || StringGetChar(src, i) == ',')
        {
         string token = StringSubstr(src, start, i - start);
         StringTrimLeft(token);
         StringTrimRight(token);
         if(StringLen(token) > 0)
           {
            int n = ArraySize(out);
            ArrayResize(out, n + 1);
            out[n] = token;
           }
         start = i + 1;
        }
     }
   return ArraySize(out);
  }

//+------------------------------------------------------------------+
//| 通貨がフィルタ対象かを判定                                         |
//+------------------------------------------------------------------+
bool ECC_IsCurrencyAccepted(const string currency, const string &filters[])
  {
   int n = ArraySize(filters);
   if(n == 0) return true; // 空=全許可
   for(int i = 0; i < n; i++)
      if(StringCompare(currency, filters[i], false) == 0) return true;
   return false;
  }

//+------------------------------------------------------------------+
//| 秒数を "HH:MM:SS" にフォーマット                                   |
//+------------------------------------------------------------------+
string ECC_FormatHMS(const int totalSec)
  {
   int s = (totalSec < 0) ? 0 : totalSec;
   return StringFormat("%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60);
  }

//+------------------------------------------------------------------+
//| datetime を "MM/DD HH:MM" にフォーマット                           |
//+------------------------------------------------------------------+
string ECC_FormatMDHM(const datetime t)
  {
   return StringFormat("%02d/%02d %02d:%02d",
                       TimeMonth(t), TimeDay(t), TimeHour(t), TimeMinute(t));
  }

//=======================================================================
//  CSV読み込み
//=======================================================================

//+------------------------------------------------------------------+
//| CSVを読み込んでイベント配列を構築                                  |
//| 戻り値: 読み込み成功イベント数(失敗時は0)                          |
//+------------------------------------------------------------------+
int ECC_LoadCSV(const string fileName)
  {
   g_eventCount = 0;

   // Files フォルダから読み込み(FILE_COMMON ではなく通常の terminal/MQL4/Files)
   int handle = FileOpen(fileName,
                         FILE_READ | FILE_CSV | FILE_ANSI,
                         ',');
   if(handle == INVALID_HANDLE)
     {
      int err = GetLastError();
      PrintFormat("[ECC] CSV読み込み失敗: file=%s err=%d (MQL4/Files フォルダに配置してください)",
                  fileName, err);
      return 0;
     }

   // 1行目はヘッダーとして読み捨て
   bool isFirstRow = true;

   while(!FileIsEnding(handle))
     {
      string col1 = FileReadString(handle); // datetime_jst
      if(FileIsEnding(handle) && StringLen(col1) == 0) break;

      string col2 = FileReadString(handle); // currency
      string col3 = FileReadString(handle); // name
      string col4 = FileReadString(handle); // importance

      if(isFirstRow) { isFirstRow = false; continue; }

      if(StringLen(col1) == 0) continue;

      datetime t = StrToTime(col1);
      if(t == 0) continue;

      int imp = (int)StringToInteger(col4);
      if(imp < 1) imp = 1;
      if(imp > 3) imp = 3;

      if(g_eventCount >= ECC_MAX_EVENTS)
        {
         PrintFormat("[ECC] イベント数が上限(%d)に達したため残りは無視します", ECC_MAX_EVENTS);
         break;
        }

      g_eventTime[g_eventCount]     = t;
      g_eventCurrency[g_eventCount] = col2;
      g_eventName[g_eventCount]     = col3;
      g_eventImp[g_eventCount]      = imp;
      g_eventAlerted[g_eventCount]  = false;
      g_eventCount++;
     }

   FileClose(handle);

   // 時刻昇順ソート(単純選択ソート: N<=500なので十分)
   for(int i = 0; i < g_eventCount - 1; i++)
     {
      int minIdx = i;
      for(int j = i + 1; j < g_eventCount; j++)
         if(g_eventTime[j] < g_eventTime[minIdx]) minIdx = j;
      if(minIdx != i) ECC_SwapEvent(i, minIdx);
     }

   PrintFormat("[ECC] CSV読み込み完了: %d 件", g_eventCount);
   return g_eventCount;
  }

//+------------------------------------------------------------------+
//| イベント配列の要素を入れ替え                                      |
//+------------------------------------------------------------------+
void ECC_SwapEvent(const int a, const int b)
  {
   datetime tt = g_eventTime[a];     g_eventTime[a]     = g_eventTime[b];     g_eventTime[b]     = tt;
   string   sc = g_eventCurrency[a]; g_eventCurrency[a] = g_eventCurrency[b]; g_eventCurrency[b] = sc;
   string   sn = g_eventName[a];     g_eventName[a]     = g_eventName[b];     g_eventName[b]     = sn;
   int      ii = g_eventImp[a];      g_eventImp[a]      = g_eventImp[b];      g_eventImp[b]      = ii;
   bool     bb = g_eventAlerted[a];  g_eventAlerted[a]  = g_eventAlerted[b];  g_eventAlerted[b]  = bb;
  }

//=======================================================================
//  ラベル操作
//=======================================================================
int ECC_GetMT4Corner(const ENUM_ECC_CORNER c)
  {
   if(c == ECC_CORNER_LEFT_UPPER)  return CORNER_LEFT_UPPER;
   if(c == ECC_CORNER_RIGHT_UPPER) return CORNER_RIGHT_UPPER;
   if(c == ECC_CORNER_LEFT_LOWER)  return CORNER_LEFT_LOWER;
   return CORNER_RIGHT_LOWER;
  }

bool ECC_CreateLabel(const string name, const int x, const int y,
                     const string text, const color clr)
  {
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);

   if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0))
     {
      int err = GetLastError();
      PrintFormat("[ECC] ラベル作成失敗 name=%s err=%d", name, err);
      return false;
     }
   ObjectSetInteger(0, name, OBJPROP_CORNER,     ECC_GetMT4Corner(ECC_DisplayCorner));
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   ECC_FontSize);
   ObjectSetString(0,  name, OBJPROP_FONT,       ECC_FontName);
   ObjectSetString(0,  name, OBJPROP_TEXT,       text);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);

   // 右寄せコーナーの場合はアンカーも右寄せに
   if(ECC_DisplayCorner == ECC_CORNER_RIGHT_UPPER ||
      ECC_DisplayCorner == ECC_CORNER_RIGHT_LOWER)
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);

   return true;
  }

void ECC_UpdateLabel(const string name, const string text, const color clr)
  {
   if(ObjectFind(0, name) < 0) return;
   ObjectSetString(0,  name, OBJPROP_TEXT,  text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
  }

void ECC_DeleteAllLabels()
  {
   if(ObjectFind(0, g_labelTitle) >= 0) ObjectDelete(0, g_labelTitle);
   if(ObjectFind(0, g_labelTime)  >= 0) ObjectDelete(0, g_labelTime);
   if(ObjectFind(0, g_labelSep)   >= 0) ObjectDelete(0, g_labelSep);
   for(int i = 0; i < ECC_SHOW_LINES; i++)
      if(ObjectFind(0, g_labelLine[i]) >= 0) ObjectDelete(0, g_labelLine[i]);
  }

color ECC_ColorByImp(const int imp)
  {
   if(imp >= 3) return ECC_ColorHigh;
   if(imp == 2) return ECC_ColorMid;
   return ECC_ColorLow;
  }

string ECC_StarsByImp(const int imp)
  {
   if(imp >= 3) return "★★★";
   if(imp == 2) return "★★ ";
   return "★  ";
  }

//=======================================================================
//  表示更新(メイン処理)
//=======================================================================
void ECC_UpdateDisplay()
  {
   datetime jstNow = ECC_GetJSTNow();

   // フィルタ通貨リスト
   string filters[];
   ECC_SplitCSVString(ECC_FilterCurrencies, filters);

   // タイトル行
   ECC_UpdateLabel(g_labelTitle, "=== 経済指標カウントダウン ===", ECC_ColorTitle);

   // 現在時刻行
   ECC_UpdateLabel(g_labelTime,
                   StringFormat("JST %s", TimeToString(jstNow, TIME_DATE | TIME_SECONDS)),
                   ECC_ColorTime);

   // セパレーター
   ECC_UpdateLabel(g_labelSep, "------------------------------", ECC_ColorLow);

   // 直近の該当イベントを走査してリストアップ
   int  shown = 0;

   for(int i = 0; i < g_eventCount && shown < ECC_SHOW_LINES; i++)
     {
      if(g_eventTime[i] < jstNow) continue;                             // 過去は除外
      if(g_eventImp[i] < ECC_MinImportance) continue;                   // 重要度フィルタ
      if(!ECC_IsCurrencyAccepted(g_eventCurrency[i], filters)) continue;// 通貨フィルタ

      int remainSec = (int)(g_eventTime[i] - jstNow);

      string line = StringFormat("%s [%s] %s %s  残 %s",
                                 ECC_StarsByImp(g_eventImp[i]),
                                 g_eventCurrency[i],
                                 ECC_FormatMDHM(g_eventTime[i]),
                                 g_eventName[i],
                                 ECC_FormatHMS(remainSec));

      ECC_UpdateLabel(g_labelLine[shown], line, ECC_ColorByImp(g_eventImp[i]));

      // 直前アラート判定(1件目のみ)
      if(shown == 0)
        {
         int thresholdSec = ECC_AlertMinutesBefore * 60;
         if(!g_eventAlerted[i] && remainSec > 0 && remainSec <= thresholdSec)
           {
            ECC_FireAlert(i, remainSec);
            g_eventAlerted[i] = true;
           }
        }
      shown++;
     }

   // 表示しない行はクリア
   for(int k = shown; k < ECC_SHOW_LINES; k++)
      ECC_UpdateLabel(g_labelLine[k], "", ECC_ColorLow);

   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| アラート発動                                                      |
//+------------------------------------------------------------------+
void ECC_FireAlert(const int idx, const int remainSec)
  {
   string msg = StringFormat("[ECC] %s %s %s まで %d分 (発表 %s)",
                             ECC_StarsByImp(g_eventImp[idx]),
                             g_eventCurrency[idx],
                             g_eventName[idx],
                             remainSec / 60,
                             ECC_FormatMDHM(g_eventTime[idx]));

   if(ECC_UseAlert)
      Alert(msg);
   else
      Print(msg);

   if(ECC_UsePush)
     {
      if(!SendNotification(msg))
        {
         int err = GetLastError();
         PrintFormat("[ECC] SendNotification失敗 err=%d", err);
        }
     }
  }

//=======================================================================
//  MQL4 必須コールバック
//=======================================================================
int OnInit()
  {
   // ラベル名を初期化
   for(int i = 0; i < ECC_SHOW_LINES; i++)
      g_labelLine[i] = ECC_PREFIX + "line_" + IntegerToString(i);

   // 古いオブジェクトを一掃
   ECC_DeleteAllLabels();

   // CSV読み込み
   int loaded = ECC_LoadCSV(ECC_CsvFileName);
   if(loaded == 0)
     {
      Print("[ECC] 有効なイベントがありません。CSVの配置と内容を確認してください。");
      // CSV失敗でもラベル自体は表示する(エラーメッセージ表示用)
     }

   // ラベル生成
   int x = ECC_PosX;
   int y = ECC_PosY;

   if(!ECC_CreateLabel(g_labelTitle, x, y, "=== 経済指標カウントダウン ===", ECC_ColorTitle))
      return INIT_FAILED;
   y += ECC_LineHeight;

   if(!ECC_CreateLabel(g_labelTime, x, y, "", ECC_ColorTime))
      return INIT_FAILED;
   y += ECC_LineHeight;

   if(!ECC_CreateLabel(g_labelSep, x, y, "------------------------------", ECC_ColorLow))
      return INIT_FAILED;
   y += ECC_LineHeight;

   for(int i = 0; i < ECC_SHOW_LINES; i++)
     {
      if(!ECC_CreateLabel(g_labelLine[i], x, y, "", ECC_ColorLow))
         return INIT_FAILED;
      y += ECC_LineHeight;
     }

   // 1秒タイマーで更新
   if(!EventSetTimer(1))
     {
      PrintFormat("[ECC] EventSetTimer失敗 err=%d", GetLastError());
      return INIT_FAILED;
     }

   // 初回表示
   ECC_UpdateDisplay();

   PrintFormat("[ECC] 起動完了。 イベント=%d 件 / Filter=%s / MinImp=%d",
               g_eventCount, ECC_FilterCurrencies, ECC_MinImportance);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   ECC_DeleteAllLabels();
   ChartRedraw(0);
   PrintFormat("[ECC] 終了 (reason=%d)", reason);
  }

void OnTimer()
  {
   ECC_UpdateDisplay();
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
   ECC_UpdateDisplay();
   return rates_total;
  }
//+------------------------------------------------------------------+
