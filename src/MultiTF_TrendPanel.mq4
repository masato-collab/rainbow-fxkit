//+------------------------------------------------------------------+
//|  MultiTF_TrendPanel.mq4                                          |
//|  複数時間足トレンド方向パネル表示インジケーター                          |
//|  対象時間足: M5, M15, H1, H4, D1, W1                              |
//+------------------------------------------------------------------+
#property strict
#property copyright   "MultiTF_TrendPanel v1.01"
#property version     "1.01"
#property description "複数時間足のトレンド方向を一覧表示するインジケーター"
#property indicator_chart_window
#property indicator_plots 0

//--- オブジェクト名プレフィックス（他インジと重複を避ける）
#define PREFIX "MTFTP_"

//=== 表示設定 ===
input ENUM_BASE_CORNER InpCorner     = CORNER_LEFT_UPPER; // パネル表示位置
input int              InpXOffset    = 10;              // X方向オフセット(px)
input int              InpYOffset    = 20;              // Y方向オフセット(px)
input int              InpFontSize   = 10;              // フォントサイズ
input color            InpBgColor    = C'30,30,30';     // 背景色
input color            InpTextColor  = clrWhite;        // 文字色（デフォルト）
input color            InpUpColor    = clrLimeGreen;    // 上昇トレンド文字色
input color            InpDownColor  = clrTomato;       // 下降トレンド文字色
input color            InpRangeColor = clrGray;         // レンジ文字色

//=== 時間足ON/OFF ===
input bool InpUseM5  = true;  // M5  使用
input bool InpUseM15 = true;  // M15 使用
input bool InpUseH1  = true;  // H1  使用
input bool InpUseH4  = true;  // H4  使用
input bool InpUseD1  = true;  // D1  使用
input bool InpUseW1  = true;  // W1  使用

//=== トレンド判定方式 ===
enum ENUM_TREND_METHOD
{
   METHOD_A_SLOPE,   // 方式A: MAの傾き
   METHOD_B_PRICE,   // 方式B: 価格とMAの位置関係
   METHOD_C_CROSS    // 方式C: 短期MAと長期MAのクロス状態
};
input ENUM_TREND_METHOD InpMethod       = METHOD_B_PRICE; // トレンド判定方式
input int               InpMaPeriod     = 20;             // MA期間（方式A/B用）
input int               InpMaFastPeriod = 10;             // 短期MA期間（方式C用）
input int               InpMaSlowPeriod = 30;             // 長期MA期間（方式C用）
input ENUM_MA_METHOD    InpMaMethod     = MODE_EMA;       // MA種類(SMA/EMA等)
input int               InpSlopeShift   = 3;              // 方式A: 傾き計算バー数

//=== アラート設定 ===
input bool InpAlertEnabled   = true;  // アラート有効
input int  InpAlertThreshold = 5;     // アラート閾値(一致足数/6)
input bool InpAlertOnce      = true;  // 同方向アラートを1回のみ発報

//=== 内部定数 ===
#define TF_COUNT 6
#define TREND_UP    1
#define TREND_DOWN -1
#define TREND_RANGE 0

//--- 時間足定義
int    g_tf[TF_COUNT]   = {PERIOD_M5, PERIOD_M15, PERIOD_H1, PERIOD_H4, PERIOD_D1, PERIOD_W1};
string g_tfName[TF_COUNT] = {"M5 ", "M15", "H1 ", "H4 ", "D1 ", "W1 "};
bool   g_tfUse[TF_COUNT];

//--- アラート管理
int    g_lastAlertUpCount   = -1;
int    g_lastAlertDownCount = -1;
datetime g_lastBarTime = 0;

//--- 行数カウント（ON足の数に応じて動的に変わる）
int g_rowCount = 0;

//+------------------------------------------------------------------+
//| 初期化                                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- 使用フラグ配列を設定
   g_tfUse[0] = InpUseM5;
   g_tfUse[1] = InpUseM15;
   g_tfUse[2] = InpUseH1;
   g_tfUse[3] = InpUseH4;
   g_tfUse[4] = InpUseD1;
   g_tfUse[5] = InpUseW1;

   //--- パラメーター検証
   if(InpMaPeriod < 2)
   {
      Alert(PREFIX + "エラー: MA期間は2以上にしてください");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpMethod == METHOD_C_CROSS && InpMaFastPeriod >= InpMaSlowPeriod)
   {
      Alert(PREFIX + "エラー: 方式C: 短期MA期間 < 長期MA期間にしてください");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpAlertThreshold < 1 || InpAlertThreshold > TF_COUNT)
   {
      Alert(PREFIX + "エラー: アラート閾値は1～6の範囲で指定してください");
      return INIT_PARAMETERS_INCORRECT;
   }

   //--- 有効足数をカウント
   g_rowCount = 0;
   for(int i = 0; i < TF_COUNT; i++)
      if(g_tfUse[i]) g_rowCount++;

   //--- 初回描画
   DrawPanel();

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| 終了処理 — 作成した全オブジェクトを削除                               |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   DeleteAllObjects();
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| メイン計算 — 新バー確定時のみ更新（軽量化）                            |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double   &open[],
                const double   &high[],
                const double   &low[],
                const double   &close[],
                const long     &tick_volume[],
                const long     &volume[],
                const int      &spread[])
{
   //--- 新バー確定チェック（現在足のOpenTime変化で判断）
   datetime currentBarTime = time[rates_total - 1];
   if(currentBarTime == g_lastBarTime && prev_calculated > 0)
      return rates_total; // 同バー内は再計算しない

   g_lastBarTime = currentBarTime;

   //--- パネル再描画
   DrawPanel();

   return rates_total;
}

//+------------------------------------------------------------------+
//| トレンド判定 — 指定時間足のトレンド方向を返す                          |
//|  戻り値: TREND_UP(1), TREND_DOWN(-1), TREND_RANGE(0)              |
//+------------------------------------------------------------------+
int GetTrend(int tf)
{
   int trend = TREND_RANGE;

   if(InpMethod == METHOD_A_SLOPE)
   {
      //--- 方式A: MAの傾き判定
      //    現在バーのMAと InpSlopeShift バー前のMAを比較
      double maNow  = iMA(NULL, tf, InpMaPeriod, 0, InpMaMethod, PRICE_CLOSE, 1);
      double maPast = iMA(NULL, tf, InpMaPeriod, 0, InpMaMethod, PRICE_CLOSE, 1 + InpSlopeShift);

      int err = GetLastError();
      if(err != 0)
      {
         Print(PREFIX + "GetTrend iMA Error(方式A tf=", tf, "): ", err);
         return TREND_RANGE;
      }

      if(maNow > maPast)       trend = TREND_UP;
      else if(maNow < maPast)  trend = TREND_DOWN;
      else                     trend = TREND_RANGE;
   }
   else if(InpMethod == METHOD_B_PRICE)
   {
      //--- 方式B: 価格とMAの位置関係
      //    直近確定バー(index=1)の終値とMAを比較
      double price = iClose(NULL, tf, 1);
      double ma    = iMA(NULL, tf, InpMaPeriod, 0, InpMaMethod, PRICE_CLOSE, 1);

      int err = GetLastError();
      if(err != 0)
      {
         Print(PREFIX + "GetTrend iMA Error(方式B tf=", tf, "): ", err);
         return TREND_RANGE;
      }

      double point = MarketInfo(Symbol(), MODE_POINT);
      double threshold = point * 5; // わずかな差はレンジと判定

      if(price > ma + threshold)       trend = TREND_UP;
      else if(price < ma - threshold)  trend = TREND_DOWN;
      else                             trend = TREND_RANGE;
   }
   else if(InpMethod == METHOD_C_CROSS)
   {
      //--- 方式C: 短期MA vs 長期MAのクロス状態
      double maFast = iMA(NULL, tf, InpMaFastPeriod, 0, InpMaMethod, PRICE_CLOSE, 1);
      double maSlow = iMA(NULL, tf, InpMaSlowPeriod, 0, InpMaMethod, PRICE_CLOSE, 1);

      int err = GetLastError();
      if(err != 0)
      {
         Print(PREFIX + "GetTrend iMA Error(方式C tf=", tf, "): ", err);
         return TREND_RANGE;
      }

      double point = MarketInfo(Symbol(), MODE_POINT);
      double threshold = point * 5;

      if(maFast > maSlow + threshold)       trend = TREND_UP;
      else if(maFast < maSlow - threshold)  trend = TREND_DOWN;
      else                                  trend = TREND_RANGE;
   }

   return trend;
}

//+------------------------------------------------------------------+
//| パネル全体を描画                                                    |
//+------------------------------------------------------------------+
void DrawPanel()
{
   //--- 各時間足のトレンドを取得
   int trends[TF_COUNT];
   ArrayInitialize(trends, TREND_RANGE); // 事前初期化(strict mode 警告回避)
   int upCount   = 0;
   int downCount = 0;
   int enabledCount = 0;

   for(int i = 0; i < TF_COUNT; i++)
   {
      if(!g_tfUse[i]) { trends[i] = TREND_RANGE; continue; }
      trends[i] = GetTrend(g_tf[i]);
      enabledCount++;
      if(trends[i] == TREND_UP)   upCount++;
      if(trends[i] == TREND_DOWN) downCount++;
   }

   //--- 行間ピクセル
   int lineH = InpFontSize + 6;
   int totalRows = g_rowCount + 2; // 時間足行 + ヘッダー + 一致度行

   //--- 背景矩形
   DrawBackground(totalRows, lineH);

   //--- ヘッダー行
   int row = 0;
   DrawLabel("HDR", "== MultiTF Trend Panel ==", row, lineH, InpTextColor);
   row++;

   //--- 各時間足行
   for(int i = 0; i < TF_COUNT; i++)
   {
      if(!g_tfUse[i]) continue;

      string mark, dir;
      color  col;

      if(trends[i] == TREND_UP)
      {
         mark = "[UP]  "; dir = "Uptrend  "; col = InpUpColor;
      }
      else if(trends[i] == TREND_DOWN)
      {
         mark = "[DN]  "; dir = "Downtrend"; col = InpDownColor;
      }
      else
      {
         mark = "[--]  "; dir = "Range    "; col = InpRangeColor;
      }

      string arrow = (trends[i] == TREND_UP) ? "↑" : (trends[i] == TREND_DOWN) ? "↓" : "→";
      string label = StringFormat("%s: %s %s %s", g_tfName[i], mark, arrow, dir);
      DrawLabel("TF" + IntegerToString(i), label, row, lineH, col);
      row++;
   }

   //--- 一致度サマリー行
   string summaryText = BuildSummaryText(upCount, downCount, enabledCount);
   color  summaryColor = GetSummaryColor(upCount, downCount, enabledCount);
   DrawLabel("SUM", summaryText, row, lineH, summaryColor);

   //--- アラートチェック
   if(InpAlertEnabled)
      CheckAlert(upCount, downCount, enabledCount);

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| 背景矩形を描画                                                      |
//+------------------------------------------------------------------+
void DrawBackground(int totalRows, int lineH)
{
   string name = PREFIX + "BG";
   int    w    = 220;
   int    h    = totalRows * lineH + 8;

   if(ObjectFind(0, name) < 0)
   {
      if(!ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0))
      {
         Print(PREFIX + "背景作成エラー: ", GetLastError());
         return;
      }
   }
   ObjectSetInteger(0, name, OBJPROP_CORNER,    InpCorner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, InpXOffset - 4);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, InpYOffset - 4);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,     w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,     h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,   InpBgColor);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clrDimGray);
   ObjectSetInteger(0, name, OBJPROP_BACK,      false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| テキストラベルを描画（行番号ベースでY座標を自動計算）                    |
//+------------------------------------------------------------------+
void DrawLabel(string id, string text, int row, int lineH, color col)
{
   string name = PREFIX + "LBL_" + id;
   int    yPos = InpYOffset + row * lineH;

   if(ObjectFind(0, name) < 0)
   {
      if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0))
      {
         Print(PREFIX + "ラベル作成エラー(", id, "): ", GetLastError());
         return;
      }
   }
   ObjectSetInteger(0, name, OBJPROP_CORNER,    InpCorner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, InpXOffset);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, yPos);
   ObjectSetString (0, name, OBJPROP_TEXT,      text);
   ObjectSetString (0, name, OBJPROP_FONT,      "MS ゴシック");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  InpFontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     col);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_BACK,      false);
}

//+------------------------------------------------------------------+
//| 一致度サマリーテキストを生成                                          |
//+------------------------------------------------------------------+
string BuildSummaryText(int upCount, int downCount, int enabledCount)
{
   string text;
   if(upCount >= downCount && upCount > 0)
      text = StringFormat("↑ %d/%d 上昇一致", upCount, enabledCount);
   else if(downCount > upCount && downCount > 0)
      text = StringFormat("↓ %d/%d 下降一致", downCount, enabledCount);
   else
      text = StringFormat("→ %d/%d レンジ/混在", enabledCount - upCount - downCount, enabledCount);

   //--- 強度コメント付加
   int dominantCount = MathMax(upCount, downCount);
   if(enabledCount > 0)
   {
      double ratio = (double)dominantCount / enabledCount;
      if(ratio >= 1.0)         text += " [最強]";
      else if(ratio >= 0.833)  text += " [強]";
      else if(ratio >= 0.667)  text += " [中]";
      else                     text += " [弱]";
   }
   return text;
}

//+------------------------------------------------------------------+
//| 一致度に応じたサマリー色を返す                                        |
//+------------------------------------------------------------------+
color GetSummaryColor(int upCount, int downCount, int enabledCount)
{
   int dominantCount = MathMax(upCount, downCount);
   if(enabledCount == 0) return InpRangeColor;

   double ratio = (double)dominantCount / enabledCount;

   if(upCount >= downCount)
   {
      if(ratio >= 0.667) return InpUpColor;
      return InpRangeColor;
   }
   else
   {
      if(ratio >= 0.667) return InpDownColor;
      return InpRangeColor;
   }
}

//+------------------------------------------------------------------+
//| アラートチェック                                                    |
//+------------------------------------------------------------------+
void CheckAlert(int upCount, int downCount, int enabledCount)
{
   //--- 上昇アラート
   if(upCount >= InpAlertThreshold)
   {
      bool shouldAlert = !InpAlertOnce || (upCount != g_lastAlertUpCount);
      if(shouldAlert)
      {
         string msg = StringFormat("[MultiTF] %s: %d/%d 足が上昇トレンド一致！",
                                   Symbol(), upCount, enabledCount);
         Alert(msg);
         g_lastAlertUpCount   = upCount;
         g_lastAlertDownCount = -1; // 反対方向リセット
      }
   }

   //--- 下降アラート
   if(downCount >= InpAlertThreshold)
   {
      bool shouldAlert = !InpAlertOnce || (downCount != g_lastAlertDownCount);
      if(shouldAlert)
      {
         string msg = StringFormat("[MultiTF] %s: %d/%d 足が下降トレンド一致！",
                                   Symbol(), downCount, enabledCount);
         Alert(msg);
         g_lastAlertDownCount = downCount;
         g_lastAlertUpCount   = -1;
      }
   }
}

//+------------------------------------------------------------------+
//| プレフィックスつき全オブジェクトを削除                                  |
//+------------------------------------------------------------------+
void DeleteAllObjects()
{
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, -1, -1);
      if(StringFind(name, PREFIX) == 0)
      {
         if(!ObjectDelete(0, name))
            Print(PREFIX + "オブジェクト削除エラー(", name, "): ", GetLastError());
      }
   }
}
//+------------------------------------------------------------------+
