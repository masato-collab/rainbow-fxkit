//+------------------------------------------------------------------+
//|                              CorrelationMatrix_Monitor.mq4       |
//|  主要通貨ペア間の相関係数をマトリクス表示するインジケーター       |
//|  機能:                                                            |
//|    - 指定ペア間の相関係数(Pearson)を計算して NxN 行列で表示       |
//|    - 相関の強弱に応じてセル色を変化(正=緑/逆=赤/弱=灰)            |
//|    - 長期/短期相関の差分が閾値超でダイバージェンスアラート        |
//|    - 1分ごとに再計算、各ペアはリターン系列から計算                |
//+------------------------------------------------------------------+
#property strict
#property copyright   "CorrelationMatrix_Monitor v1.00"
#property description "主要通貨ペアの相関をリアルタイム可視化するインジケーター"
#property version     "1.00"
#property indicator_chart_window
#property indicator_buffers 0

//--- 定数
#define CMM_MAX_PAIRS   8      // 最大監視ペア数(計算量制限のため)
#define CMM_PREFIX      "CMM_" // オブジェクト名プレフィックス

//--- 表示コーナー列挙
enum ENUM_CMM_CORNER
  {
   CMM_CORNER_LEFT_UPPER  = 0, // 左上
   CMM_CORNER_RIGHT_UPPER = 1, // 右上
   CMM_CORNER_LEFT_LOWER  = 2, // 左下
   CMM_CORNER_RIGHT_LOWER = 3  // 右下
  };

//=======================================================================
//  入力パラメーター
//=======================================================================
input string           CMM_Pairs           = "EURUSD,GBPUSD,USDJPY,AUDUSD,USDCHF,USDCAD"; // 監視対象ペア(カンマ区切り, 最大8)
input int              CMM_Period          = 100;               // 相関計算期間(本数)
input ENUM_TIMEFRAMES  CMM_Timeframe       = PERIOD_H1;         // 計算に使う時間足
input double           CMM_AlertThreshold  = 0.3;               // 長期/短期相関差がこの値を超えたら警報
input bool             CMM_UseAlert        = true;              // ダイバージェンスアラート
input int              CMM_RecalcSeconds   = 60;                // 再計算間隔(秒)
input ENUM_CMM_CORNER  CMM_DisplayCorner   = CMM_CORNER_LEFT_UPPER; // マトリクス表示位置
input color            CMM_ColorPositive   = clrLimeGreen;      // 正相関色(強)
input color            CMM_ColorNegative   = clrTomato;         // 逆相関色(強)
input color            CMM_ColorNeutral    = clrSilver;         // 弱相関色
input color            CMM_ColorHeader     = clrAqua;           // ヘッダー色
input color            CMM_ColorDiagonal   = clrDimGray;        // 対角線色(自分自身)
input int              CMM_FontSize        = 9;                 // フォントサイズ
input string           CMM_FontName        = "MS ゴシック";     // フォント名(日本語対応)
input int              CMM_PosX            = 10;                // 表示X余白(px)
input int              CMM_PosY            = 20;                // 表示Y余白(px)
input int              CMM_CellWidth       = 70;                // 1セル幅(px)
input int              CMM_CellHeight      = 18;                // 1セル高(px)

//=======================================================================
//  内部変数
//=======================================================================
string g_pairs[CMM_MAX_PAIRS];        // 監視ペア名配列
int    g_pairCount = 0;               // 有効ペア数
double g_corrLong [CMM_MAX_PAIRS][CMM_MAX_PAIRS]; // 長期相関
double g_corrShort[CMM_MAX_PAIRS][CMM_MAX_PAIRS]; // 短期相関(長期の1/4期間)
bool   g_divergenceAlerted[CMM_MAX_PAIRS][CMM_MAX_PAIRS]; // ダイバージェンス発報済み

string g_lblTitle;                    // タイトルラベル

//=======================================================================
//  ユーティリティ
//=======================================================================

//+------------------------------------------------------------------+
//| カンマ区切り文字列を配列に分割                                    |
//+------------------------------------------------------------------+
int CMM_SplitPairs(const string src, string &out[])
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
         if(StringLen(token) > 0 && count < CMM_MAX_PAIRS)
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
//| Pearson相関係数を計算                                             |
//| sym1/sym2: 通貨ペア名, tf: 時間足, period: 計算本数              |
//| 戻り値: true=成功(result に相関を格納), false=データ不足          |
//+------------------------------------------------------------------+
bool CMM_CalcCorrelation(const string sym1, const string sym2,
                         const ENUM_TIMEFRAMES tf, const int period,
                         double &result)
  {
   result = 0.0;
   if(period < 3) return false;

   // period+1本の終値から period 本のリターンを計算
   double rets1[];
   double rets2[];
   ArrayResize(rets1, period);
   ArrayResize(rets2, period);

   for(int i = 0; i < period; i++)
     {
      double c1_cur  = iClose(sym1, tf, i);
      double c1_prev = iClose(sym1, tf, i + 1);
      double c2_cur  = iClose(sym2, tf, i);
      double c2_prev = iClose(sym2, tf, i + 1);

      if(c1_cur <= 0.0 || c1_prev <= 0.0 ||
         c2_cur <= 0.0 || c2_prev <= 0.0)
        {
         // データ不足(履歴未取得の可能性) — iClose=0 時は
         // 気配値表示で該当ペアを「全て表示」する必要あり
         int err = GetLastError();
         if(err != 0)
            PrintFormat("[CMM] iClose失敗 sym=%s/%s err=%d", sym1, sym2, err);
         return false;
        }
      rets1[i] = (c1_cur  - c1_prev) / c1_prev;
      rets2[i] = (c2_cur  - c2_prev) / c2_prev;
     }

   // 平均
   double mean1 = 0.0;
   double mean2 = 0.0;
   for(int i = 0; i < period; i++)
     {
      mean1 += rets1[i];
      mean2 += rets2[i];
     }
   mean1 /= period;
   mean2 /= period;

   // 共分散と分散
   double sumXY = 0.0;
   double sumXX = 0.0;
   double sumYY = 0.0;
   for(int i = 0; i < period; i++)
     {
      double dx = rets1[i] - mean1;
      double dy = rets2[i] - mean2;
      sumXY += dx * dy;
      sumXX += dx * dx;
      sumYY += dy * dy;
     }

   double denom = MathSqrt(sumXX * sumYY);
   if(denom <= 0.0) return false;

   result = sumXY / denom;
   if(result > 1.0)  result = 1.0;
   if(result < -1.0) result = -1.0;
   return true;
  }

//+------------------------------------------------------------------+
//| 相関値に応じた色を返す                                            |
//+------------------------------------------------------------------+
color CMM_ColorFromCorr(const double r)
  {
   double abs_r = MathAbs(r);
   if(abs_r < 0.3) return CMM_ColorNeutral;
   if(r > 0.0) return CMM_ColorPositive;
   return CMM_ColorNegative;
  }

//=======================================================================
//  オブジェクト操作
//=======================================================================
ENUM_BASE_CORNER CMM_GetCorner()
  {
   if(CMM_DisplayCorner == CMM_CORNER_LEFT_UPPER)  return CORNER_LEFT_UPPER;
   if(CMM_DisplayCorner == CMM_CORNER_RIGHT_UPPER) return CORNER_RIGHT_UPPER;
   if(CMM_DisplayCorner == CMM_CORNER_LEFT_LOWER)  return CORNER_LEFT_LOWER;
   return CORNER_RIGHT_LOWER;
  }

bool CMM_CreateLabel(const string name, const int x, const int y,
                     const string text, const color clr)
  {
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0))
     {
      PrintFormat("[CMM] ラベル作成失敗 name=%s err=%d", name, GetLastError());
      return false;
     }
   ObjectSetInteger(0, name, OBJPROP_CORNER,     CMM_GetCorner());
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   CMM_FontSize);
   ObjectSetString(0,  name, OBJPROP_FONT,       CMM_FontName);
   ObjectSetString(0,  name, OBJPROP_TEXT,       text);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
   return true;
  }

void CMM_UpdateLabel(const string name, const string text, const color clr)
  {
   if(ObjectFind(0, name) < 0) return;
   ObjectSetString(0,  name, OBJPROP_TEXT,  text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
  }

//+------------------------------------------------------------------+
//| 自インジケーターが作成した全オブジェクトを削除                    |
//+------------------------------------------------------------------+
void CMM_DeleteAllObjects()
  {
   int total = ObjectsTotal();
   for(int i = total - 1; i >= 0; i--)
     {
      string name = ObjectName(i);
      if(StringFind(name, CMM_PREFIX) == 0)
         ObjectDelete(0, name);
     }
  }

//+------------------------------------------------------------------+
//| マトリクスのセル/ヘッダーをすべて作成                             |
//+------------------------------------------------------------------+
void CMM_BuildMatrix()
  {
   CMM_DeleteAllObjects();

   int x0 = CMM_PosX;
   int y0 = CMM_PosY;

   // タイトル
   g_lblTitle = CMM_PREFIX + "title";
   string timeframeStr = EnumToString(CMM_Timeframe);
   string title = StringFormat("=== 相関マトリクス (%s, %d本) ===",
                               timeframeStr, CMM_Period);
   CMM_CreateLabel(g_lblTitle, x0, y0, title, CMM_ColorHeader);

   int headerY = y0 + CMM_CellHeight + 2;
   int rowStartY = headerY + CMM_CellHeight;
   int rowHeaderX = x0;
   int cellStartX = x0 + CMM_CellWidth;

   // 列ヘッダー(ペア名)
   for(int c = 0; c < g_pairCount; c++)
     {
      string name = CMM_PREFIX + "colhdr_" + IntegerToString(c);
      CMM_CreateLabel(name, cellStartX + c * CMM_CellWidth, headerY,
                       g_pairs[c], CMM_ColorHeader);
     }

   // 行ヘッダー + セル
   for(int r = 0; r < g_pairCount; r++)
     {
      // 行ヘッダー
      string rowHdrName = CMM_PREFIX + "rowhdr_" + IntegerToString(r);
      CMM_CreateLabel(rowHdrName, rowHeaderX, rowStartY + r * CMM_CellHeight,
                       g_pairs[r], CMM_ColorHeader);

      // セル
      for(int c = 0; c < g_pairCount; c++)
        {
         string cellName = CMM_PREFIX + "cell_" +
                           IntegerToString(r) + "_" + IntegerToString(c);
         CMM_CreateLabel(cellName,
                          cellStartX + c * CMM_CellWidth,
                          rowStartY  + r * CMM_CellHeight,
                          "-", CMM_ColorNeutral);
        }
     }
  }

//=======================================================================
//  相関計算&表示更新
//=======================================================================
void CMM_UpdateMatrix()
  {
   // 対角線(自分自身)は常に 1.0
   // 非対角は iClose から計算
   for(int r = 0; r < g_pairCount; r++)
     {
      for(int c = 0; c < g_pairCount; c++)
        {
         string cellName = CMM_PREFIX + "cell_" +
                           IntegerToString(r) + "_" + IntegerToString(c);

         if(r == c)
           {
            CMM_UpdateLabel(cellName, " - ", CMM_ColorDiagonal);
            g_corrLong[r][c]  = 1.0;
            g_corrShort[r][c] = 1.0;
            continue;
           }

         // 長期相関
         double rLong = 0.0;
         bool   okL   = CMM_CalcCorrelation(g_pairs[r], g_pairs[c],
                                             CMM_Timeframe, CMM_Period, rLong);
         // 短期相関(1/4期間, 最小5)
         int shortP = CMM_Period / 4;
         if(shortP < 5) shortP = 5;
         double rShort = 0.0;
         bool   okS    = CMM_CalcCorrelation(g_pairs[r], g_pairs[c],
                                              CMM_Timeframe, shortP, rShort);

         if(!okL)
           {
            CMM_UpdateLabel(cellName, "N/A", CMM_ColorNeutral);
            g_corrLong[r][c]  = 0.0;
            g_corrShort[r][c] = 0.0;
            continue;
           }

         g_corrLong[r][c] = rLong;
         if(okS) g_corrShort[r][c] = rShort;

         // 表示: "+0.85" 形式
         string txt = StringFormat("%+.2f", rLong);
         CMM_UpdateLabel(cellName, txt, CMM_ColorFromCorr(rLong));

         // ダイバージェンス判定(r < c のみ、重複発報防止)
         if(CMM_UseAlert && okS && r < c)
           {
            double diff = MathAbs(rLong - rShort);
            if(diff >= CMM_AlertThreshold)
              {
               if(!g_divergenceAlerted[r][c])
                 {
                  string msg = StringFormat(
                     "[CMM] ダイバージェンス %s/%s 長期%+.2f→短期%+.2f (差%.2f)",
                     g_pairs[r], g_pairs[c], rLong, rShort, diff);
                  Alert(msg);
                  g_divergenceAlerted[r][c] = true;
                 }
              }
            else
              {
               // 差が半分以下に落ち着いたらリセット
               if(diff < CMM_AlertThreshold * 0.5)
                  g_divergenceAlerted[r][c] = false;
              }
           }
        }
     }

   ChartRedraw(0);
  }

//=======================================================================
//  MQL4 必須コールバック
//=======================================================================
int OnInit()
  {
   // ペア配列初期化
   ArrayResize(g_pairs, CMM_MAX_PAIRS);
   for(int i = 0; i < CMM_MAX_PAIRS; i++) g_pairs[i] = "";

   g_pairCount = CMM_SplitPairs(CMM_Pairs, g_pairs);
   if(g_pairCount < 2)
     {
      Print("[CMM] 監視ペアは2つ以上指定してください。現在=", g_pairCount);
      return INIT_PARAMETERS_INCORRECT;
     }

   // フラグ配列初期化
   for(int r = 0; r < CMM_MAX_PAIRS; r++)
      for(int c = 0; c < CMM_MAX_PAIRS; c++)
        {
         g_corrLong[r][c]          = 0.0;
         g_corrShort[r][c]         = 0.0;
         g_divergenceAlerted[r][c] = false;
        }

   // マトリクス生成
   CMM_BuildMatrix();

   // 初回計算
   CMM_UpdateMatrix();

   // 再計算タイマー
   if(!EventSetTimer(CMM_RecalcSeconds))
     {
      PrintFormat("[CMM] EventSetTimer失敗 err=%d", GetLastError());
      return INIT_FAILED;
     }

   PrintFormat("[CMM] 起動完了 ペア数=%d 期間=%d", g_pairCount, CMM_Period);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   CMM_DeleteAllObjects();
   ChartRedraw(0);
   PrintFormat("[CMM] 終了 reason=%d", reason);
  }

void OnTimer()
  {
   CMM_UpdateMatrix();
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
