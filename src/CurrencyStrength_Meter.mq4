//+------------------------------------------------------------------+
//|                                  CurrencyStrength_Meter.mq4      |
//|  8通貨の相対強弱をリアルタイム計測してランキング表示             |
//|  機能:                                                            |
//|    - 指定ペアの価格変化率から各通貨の強弱スコアを算出             |
//|    - USD/EUR/JPY/GBP/AUD/NZD/CAD/CHF の8通貨を比較               |
//|    - ランキング+バーで可視化                                     |
//|    - タイムフレーム・集計期間を変更可能                           |
//+------------------------------------------------------------------+
#property strict
#property copyright   "CurrencyStrength_Meter v1.00"
#property description "8通貨の相対強弱をリアルタイム計測するインジケーター"
#property version     "1.00"
#property indicator_chart_window
#property indicator_buffers 0

//--- 定数
#define CSM_MAX_CURRENCIES 8
#define CSM_MAX_PAIRS      32
#define CSM_PREFIX         "CSM_"

//--- 列挙
enum ENUM_CSM_CORNER
  {
   CSM_CORNER_LEFT_UPPER  = 0, // 左上
   CSM_CORNER_RIGHT_UPPER = 1, // 右上
   CSM_CORNER_LEFT_LOWER  = 2, // 左下
   CSM_CORNER_RIGHT_LOWER = 3  // 右下
  };

//=======================================================================
//  入力パラメーター
//=======================================================================
input string           CSM_Currencies = "USD,EUR,JPY,GBP,AUD,NZD,CAD,CHF";     // 計測対象通貨(カンマ区切り)
input string           CSM_Pairs      = "EURUSD,GBPUSD,AUDUSD,NZDUSD,USDJPY,USDCHF,USDCAD,EURJPY,GBPJPY,AUDJPY,NZDJPY,EURGBP,EURAUD,EURNZD,EURCAD,EURCHF,GBPAUD,GBPNZD,GBPCAD,GBPCHF,AUDNZD,AUDCAD,AUDCHF,NZDCAD,NZDCHF,CADCHF,CADJPY,CHFJPY"; // 分析対象ペア
input ENUM_TIMEFRAMES  CSM_Timeframe  = PERIOD_H1;                              // 計測する時間足
input int              CSM_Period     = 24;                                    // 変化率計算の期間(本数)
input int              CSM_RecalcSeconds = 30;                                 // 再計算間隔(秒)
input ENUM_CSM_CORNER  CSM_DisplayCorner = CSM_CORNER_LEFT_UPPER;              // 表示コーナー
input int              CSM_PosX       = 10;                                    // 表示X余白
input int              CSM_PosY       = 20;                                    // 表示Y余白
input int              CSM_LineHeight = 18;                                    // 行高
input int              CSM_BarWidth   = 100;                                   // 強弱バー最大幅(px)
input color            CSM_ColorTitle = clrAqua;                               // タイトル色
input color            CSM_ColorStrong= clrLime;                               // 最強通貨の色
input color            CSM_ColorWeak  = clrTomato;                             // 最弱通貨の色
input color            CSM_ColorMid   = clrWhite;                              // 中間色
input int              CSM_FontSize   = 10;                                    // フォントサイズ
input string           CSM_FontName   = "MS ゴシック";                          // フォント名(日本語対応)

//=======================================================================
//  内部変数
//=======================================================================
string g_currencies[CSM_MAX_CURRENCIES];     // 通貨コード配列
int    g_currencyCount = 0;

string g_pairs[CSM_MAX_PAIRS];               // 分析ペア配列
int    g_pairCount = 0;

// スコア管理(ソート用にインデックス付き)
double g_score[CSM_MAX_CURRENCIES];          // 強弱スコア(%)
int    g_sortedIdx[CSM_MAX_CURRENCIES];      // 降順ソート後のインデックス

string g_lblTitle = CSM_PREFIX + "title";
string g_lblRow[CSM_MAX_CURRENCIES];         // 各通貨の表示ラベル
string g_lblBar[CSM_MAX_CURRENCIES];         // 各通貨の強弱バー(OBJ_RECTANGLE_LABEL)

//=======================================================================
//  ユーティリティ
//=======================================================================

//+------------------------------------------------------------------+
//| カンマ区切り文字列を配列に分割                                    |
//+------------------------------------------------------------------+
int CSM_SplitCSV(const string src, string &out[], const int maxItems)
  {
   int count = 0;
   int start = 0;
   int len   = StringLen(src);
   for(int i = 0; i <= len; i++)
     {
      if(i == len || StringGetChar(src, i) == ',')
        {
         string token = StringSubstr(src, start, i - start);
         StringTrimLeft(token);
         StringTrimRight(token);
         if(StringLen(token) > 0 && count < maxItems)
           {
            out[count] = token;
            count++;
           }
         start = i + 1;
        }
     }
   return count;
  }

//+------------------------------------------------------------------+
//| 通貨コードのインデックスを返す(見つからなければ -1)               |
//+------------------------------------------------------------------+
int CSM_FindCurrencyIdx(const string code)
  {
   for(int i = 0; i < g_currencyCount; i++)
      if(g_currencies[i] == code) return i;
   return -1;
  }

//+------------------------------------------------------------------+
//| ペア名から base/quote 通貨のインデックスを取得                    |
//| 成功=true, 両方が計測対象内にある                                 |
//+------------------------------------------------------------------+
bool CSM_ExtractPairCurrencies(const string pair, int &baseIdx, int &quoteIdx)
  {
   if(StringLen(pair) < 6) return false;
   string baseCur  = StringSubstr(pair, 0, 3);
   string quoteCur = StringSubstr(pair, 3, 3);
   baseIdx  = CSM_FindCurrencyIdx(baseCur);
   quoteIdx = CSM_FindCurrencyIdx(quoteCur);
   return (baseIdx >= 0 && quoteIdx >= 0);
  }

//+------------------------------------------------------------------+
//| スコアに応じた色を返す(ランクで線形補間)                          |
//+------------------------------------------------------------------+
color CSM_ColorByRank(const int rank)
  {
   if(g_currencyCount <= 1) return CSM_ColorMid;
   // rank 0=最強, g_currencyCount-1=最弱
   double r = (double)rank / (double)(g_currencyCount - 1);
   if(r < 0.34) return CSM_ColorStrong;
   if(r < 0.67) return CSM_ColorMid;
   return CSM_ColorWeak;
  }

//=======================================================================
//  スコア計算
//=======================================================================

//+------------------------------------------------------------------+
//| 全ペアの変化率から各通貨の強弱スコアを計算                        |
//+------------------------------------------------------------------+
void CSM_CalculateScores()
  {
   double sum[CSM_MAX_CURRENCIES];
   int    cnt[CSM_MAX_CURRENCIES];
   ArrayInitialize(sum, 0.0);
   ArrayInitialize(cnt, 0);

   for(int p = 0; p < g_pairCount; p++)
     {
      int baseIdx, quoteIdx;
      if(!CSM_ExtractPairCurrencies(g_pairs[p], baseIdx, quoteIdx))
         continue;

      // N本前と現在の終値を取得
      double priceNow  = iClose(g_pairs[p], CSM_Timeframe, 0);
      double pricePast = iClose(g_pairs[p], CSM_Timeframe, CSM_Period);
      if(priceNow <= 0.0 || pricePast <= 0.0)
         continue; // ヒストリー未取得

      double changePct = (priceNow - pricePast) / pricePast * 100.0;

      // 基軸通貨はそのまま加算、決済通貨は符号反転
      sum[baseIdx]  += changePct;
      cnt[baseIdx]++;
      sum[quoteIdx] -= changePct;
      cnt[quoteIdx]++;
     }

   // 平均化してスコア確定
   for(int i = 0; i < g_currencyCount; i++)
     {
      if(cnt[i] > 0) g_score[i] = sum[i] / cnt[i];
      else           g_score[i] = 0.0;
     }
  }

//+------------------------------------------------------------------+
//| g_sortedIdx をスコア降順に並べる(単純選択ソート)                  |
//+------------------------------------------------------------------+
void CSM_SortByScore()
  {
   for(int i = 0; i < g_currencyCount; i++) g_sortedIdx[i] = i;

   for(int i = 0; i < g_currencyCount - 1; i++)
     {
      int maxIdx = i;
      for(int j = i + 1; j < g_currencyCount; j++)
        {
         if(g_score[g_sortedIdx[j]] > g_score[g_sortedIdx[maxIdx]])
            maxIdx = j;
        }
      if(maxIdx != i)
        {
         int tmp = g_sortedIdx[i];
         g_sortedIdx[i] = g_sortedIdx[maxIdx];
         g_sortedIdx[maxIdx] = tmp;
        }
     }
  }

//=======================================================================
//  オブジェクト操作
//=======================================================================
ENUM_BASE_CORNER CSM_GetCorner()
  {
   if(CSM_DisplayCorner == CSM_CORNER_LEFT_UPPER)  return CORNER_LEFT_UPPER;
   if(CSM_DisplayCorner == CSM_CORNER_RIGHT_UPPER) return CORNER_RIGHT_UPPER;
   if(CSM_DisplayCorner == CSM_CORNER_LEFT_LOWER)  return CORNER_LEFT_LOWER;
   return CORNER_RIGHT_LOWER;
  }

bool CSM_CreateLabel(const string name, const int x, const int y,
                     const string text, const color clr)
  {
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0))
     {
      PrintFormat("[CSM] ラベル作成失敗 name=%s err=%d", name, GetLastError());
      return false;
     }
   ObjectSetInteger(0, name, OBJPROP_CORNER,     CSM_GetCorner());
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   CSM_FontSize);
   ObjectSetString(0,  name, OBJPROP_FONT,       CSM_FontName);
   ObjectSetString(0,  name, OBJPROP_TEXT,       text);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
   return true;
  }

bool CSM_CreateRectLabel(const string name, const int x, const int y,
                         const int w, const int h, const color clr)
  {
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   if(!ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0))
     {
      PrintFormat("[CSM] 矩形作成失敗 name=%s err=%d", name, GetLastError());
      return false;
     }
   ObjectSetInteger(0, name, OBJPROP_CORNER,      CSM_GetCorner());
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,   x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,   y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,       w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,       h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,     clr);
   ObjectSetInteger(0, name, OBJPROP_COLOR,       clr);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_BACK,        false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,  false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,      true);
   return true;
  }

void CSM_UpdateLabel(const string name, const string text, const color clr)
  {
   if(ObjectFind(0, name) < 0) return;
   ObjectSetString(0,  name, OBJPROP_TEXT,  text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
  }

//+------------------------------------------------------------------+
//| 全オブジェクトを削除                                              |
//+------------------------------------------------------------------+
void CSM_DeleteAllObjects()
  {
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
     {
      string name = ObjectName(0, i, -1, -1);
      if(StringFind(name, CSM_PREFIX) == 0)
         ObjectDelete(0, name);
     }
  }

//=======================================================================
//  表示構築
//=======================================================================
void CSM_BuildPanel()
  {
   CSM_DeleteAllObjects();

   int x = CSM_PosX;
   int y = CSM_PosY;

   // タイトル
   string timeframeStr = EnumToString(CSM_Timeframe);
   string title = StringFormat("== 通貨強弱 (%s, %d本) ==", timeframeStr, CSM_Period);
   CSM_CreateLabel(g_lblTitle, x, y, title, CSM_ColorTitle);
   y += CSM_LineHeight;

   // 各通貨の行(テキスト + バー矩形)
   for(int i = 0; i < g_currencyCount; i++)
     {
      g_lblRow[i] = CSM_PREFIX + "row_" + IntegerToString(i);
      g_lblBar[i] = CSM_PREFIX + "bar_" + IntegerToString(i);

      CSM_CreateLabel(g_lblRow[i], x, y, "", CSM_ColorMid);
      // バー: テキスト右側に配置
      CSM_CreateRectLabel(g_lblBar[i], x + 150, y + 3, 1, CSM_LineHeight - 6, CSM_ColorMid);
      y += CSM_LineHeight;
     }
  }

//=======================================================================
//  表示更新
//=======================================================================
void CSM_UpdateDisplay()
  {
   CSM_CalculateScores();
   CSM_SortByScore();

   // 強弱幅を計算(バーの長さ正規化用)
   double maxAbs = 0.0;
   for(int i = 0; i < g_currencyCount; i++)
     {
      double a = MathAbs(g_score[i]);
      if(a > maxAbs) maxAbs = a;
     }
   if(maxAbs < 0.01) maxAbs = 0.01;

   for(int rank = 0; rank < g_currencyCount; rank++)
     {
      int    idx   = g_sortedIdx[rank];
      double score = g_score[idx];
      color  clr   = CSM_ColorByRank(rank);

      string marker = "";
      if(rank == 0)                       marker = " ← 最強";
      if(rank == g_currencyCount - 1)     marker = " ← 最弱";

      string txt = StringFormat("%d. %s  %+.3f%%%s",
                                rank + 1, g_currencies[idx], score, marker);
      CSM_UpdateLabel(g_lblRow[rank], txt, clr);

      // バーの長さをスコアの絶対値に比例させる
      int barLen = (int)(MathAbs(score) / maxAbs * CSM_BarWidth);
      if(barLen < 1) barLen = 1;
      ObjectSetInteger(0, g_lblBar[rank], OBJPROP_XSIZE, barLen);
      ObjectSetInteger(0, g_lblBar[rank], OBJPROP_BGCOLOR, clr);
      ObjectSetInteger(0, g_lblBar[rank], OBJPROP_COLOR, clr);
     }

   ChartRedraw(0);
  }

//=======================================================================
//  MQL4 必須コールバック
//=======================================================================
int OnInit()
  {
   // 通貨配列初期化
   for(int i = 0; i < CSM_MAX_CURRENCIES; i++) g_currencies[i] = "";
   g_currencyCount = CSM_SplitCSV(CSM_Currencies, g_currencies, CSM_MAX_CURRENCIES);
   if(g_currencyCount < 2)
     {
      Print("[CSM] 通貨は2つ以上指定してください 現在=", g_currencyCount);
      return INIT_PARAMETERS_INCORRECT;
     }

   // ペア配列初期化
   for(int i = 0; i < CSM_MAX_PAIRS; i++) g_pairs[i] = "";
   g_pairCount = CSM_SplitCSV(CSM_Pairs, g_pairs, CSM_MAX_PAIRS);
   if(g_pairCount < 1)
     {
      Print("[CSM] ペアは1つ以上指定してください 現在=", g_pairCount);
      return INIT_PARAMETERS_INCORRECT;
     }

   // スコア配列初期化
   ArrayInitialize(g_score,     0.0);
   ArrayInitialize(g_sortedIdx, 0);

   // パネル生成
   CSM_BuildPanel();

   // 初回計算
   CSM_UpdateDisplay();

   // 定期更新タイマー
   if(!EventSetTimer(CSM_RecalcSeconds))
     {
      PrintFormat("[CSM] EventSetTimer失敗 err=%d", GetLastError());
      return INIT_FAILED;
     }

   PrintFormat("[CSM] 起動完了 通貨=%d ペア=%d TF=%s 期間=%d",
               g_currencyCount, g_pairCount,
               EnumToString(CSM_Timeframe), CSM_Period);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   CSM_DeleteAllObjects();
   ChartRedraw(0);
   PrintFormat("[CSM] 終了 reason=%d", reason);
  }

void OnTimer()
  {
   CSM_UpdateDisplay();
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
   // OnTimerで定期更新するためOnCalculateは何もしない
   return rates_total;
  }
//+------------------------------------------------------------------+
