//+------------------------------------------------------------------+
//|                                    LotCalculator_Panel.mq4      |
//|  リスク%とSL幅から最適ロットを自動計算するチャート上パネル      |
//|  機能:                                                            |
//|    - チャート上にリスク%・SL幅の編集ボックスを表示                |
//|    - 残高/有効証拠金をベースに最適ロットを計算                    |
//|    - 想定損失額・RR1:1/1:2/1:3の想定利益額を同時表示              |
//|    - ブローカーのロットステップ・最小/最大ロットに自動クリップ    |
//|                                                                   |
//|  注意: 発注機能は持たず、計算結果の表示のみ                       |
//+------------------------------------------------------------------+
#property strict
#property copyright   "LotCalculator_Panel v1.00"
#property description "リスク%とSL幅から最適ロットを自動計算するユーティリティEA"
#property version     "1.00"

//--- 列挙型
enum ENUM_LCP_CORNER
  {
   LCP_CORNER_LEFT_UPPER  = 0,  // 左上
   LCP_CORNER_RIGHT_UPPER = 1,  // 右上
   LCP_CORNER_LEFT_LOWER  = 2,  // 左下
   LCP_CORNER_RIGHT_LOWER = 3   // 右下
  };

enum ENUM_LCP_ROUND
  {
   LCP_ROUND_DOWN = 0, // 切捨(デフォルト)
   LCP_ROUND_NEAR = 1, // 四捨五入
   LCP_ROUND_UP   = 2  // 切上
  };

//--- プレフィックス(オブジェクト名重複防止)
#define LCP_PREFIX "LCP_"

//=======================================================================
//  入力パラメーター
//=======================================================================
input double          LCP_DefaultRiskPct   = 2.0;                  // 初期リスク許容率(%)
input double          LCP_DefaultSLPips    = 20.0;                 // 初期SL幅(pips)
input bool            LCP_BaseOnEquity     = true;                 // 有効証拠金ベース(false=残高)
input ENUM_LCP_ROUND  LCP_RoundingMode     = LCP_ROUND_DOWN;       // ロット丸め方向
input ENUM_LCP_CORNER LCP_PanelCorner      = LCP_CORNER_LEFT_UPPER;// パネル表示位置
input bool            LCP_ShowJPYEquivalent= true;                 // 円換算の損益も表示
input bool            LCP_ShowRRAnalysis   = true;                 // RR 1:1〜1:3 の利益額を表示
input int             LCP_FontSize         = 10;                   // フォントサイズ
input string          LCP_FontName         = "MS ゴシック";         // フォント名(日本語対応)
input int             LCP_PanelPosX        = 20;                   // パネルX余白(px)
input int             LCP_PanelPosY        = 30;                   // パネルY余白(px)
input int             LCP_LineHeight       = 20;                   // 行高(px)
input int             LCP_EditWidth        = 80;                   // 編集ボックス幅(px)
input color           LCP_ColorTitle       = clrAqua;              // タイトル色
input color           LCP_ColorLabel       = clrWhite;             // ラベル色
input color           LCP_ColorValue       = clrLime;              // 計算結果色
input color           LCP_ColorEdit        = clrBlack;             // 編集ボックス文字色
input color           LCP_ColorEditBg      = clrWhite;             // 編集ボックス背景色
input color           LCP_ColorWarn        = clrOrangeRed;         // 警告色(最小ロット未満等)

//=======================================================================
//  内部変数
//=======================================================================
// オブジェクト名
string g_lblTitle      = LCP_PREFIX + "title";
string g_lblBalance    = LCP_PREFIX + "balance";
string g_lblRiskLabel  = LCP_PREFIX + "risk_lbl";
string g_editRisk      = LCP_PREFIX + "risk_edit";
string g_lblSLLabel    = LCP_PREFIX + "sl_lbl";
string g_editSL        = LCP_PREFIX + "sl_edit";
string g_lblSep1       = LCP_PREFIX + "sep1";
string g_lblLotResult  = LCP_PREFIX + "lot";
string g_lblLossResult = LCP_PREFIX + "loss";
string g_lblRR1        = LCP_PREFIX + "rr1";
string g_lblRR2        = LCP_PREFIX + "rr2";
string g_lblRR3        = LCP_PREFIX + "rr3";
string g_lblSep2       = LCP_PREFIX + "sep2";
string g_lblHint       = LCP_PREFIX + "hint";

// 現在の入力値
double g_currentRiskPct;
double g_currentSLPips;

//=======================================================================
//  ユーティリティ
//=======================================================================

//+------------------------------------------------------------------+
//| pip単位を自動判定(JPYペア3桁/その他5桁で Point*10)                |
//+------------------------------------------------------------------+
double LCP_DetectPipSize()
  {
   int digits = (int)MarketInfo(Symbol(), MODE_DIGITS);
   if(digits == 3 || digits == 5) return Point * 10.0;
   return Point;
  }

//+------------------------------------------------------------------+
//| ロットを最小ロット・ステップ・最大ロットに丸める                  |
//+------------------------------------------------------------------+
double LCP_NormalizeLot(const double lots)
  {
   double step   = MarketInfo(Symbol(), MODE_LOTSTEP);
   double minLot = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot = MarketInfo(Symbol(), MODE_MAXLOT);
   if(step <= 0.0) step = 0.01;

   double result = lots;
   if(LCP_RoundingMode == LCP_ROUND_DOWN)
      result = MathFloor(lots / step) * step;
   else if(LCP_RoundingMode == LCP_ROUND_UP)
      result = MathCeil(lots / step)  * step;
   else
      result = MathRound(lots / step) * step;

   if(result < minLot) result = minLot;
   if(result > maxLot) result = maxLot;
   return NormalizeDouble(result, 2);
  }

//+------------------------------------------------------------------+
//| 1ロットあたりのpip価値(口座通貨)を返す                            |
//+------------------------------------------------------------------+
double LCP_PipValuePerLot()
  {
   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize  = MarketInfo(Symbol(), MODE_TICKSIZE);
   double pipSize   = LCP_DetectPipSize();
   if(tickSize <= 0.0 || pipSize <= 0.0) return 0.0;
   return tickValue * (pipSize / tickSize);
  }

//+------------------------------------------------------------------+
//| 口座通貨での金額を表示用文字列に(3桁カンマ区切り)                 |
//+------------------------------------------------------------------+
string LCP_FormatMoney(const double amount, const string currency)
  {
   string signStr = (amount < 0.0) ? "-" : "";
   double absAmt  = MathAbs(amount);
   // 整数部を文字列化(DoubleToString の第2引数=0 で小数点以下なし)
   string intPart = DoubleToString(MathRound(absAmt), 0);
   // 右から3桁ごとにカンマ挿入
   int    n       = StringLen(intPart);
   string body    = "";
   for(int i = 0; i < n; i++)
     {
      int fromRight = n - i;
      if(i > 0 && (fromRight % 3 == 0))
         body = body + ",";
      body = body + StringSubstr(intPart, i, 1);
     }
   return signStr + body + " " + currency;
  }

//+------------------------------------------------------------------+
//| 文字列を double に変換(失敗時 0)                                  |
//+------------------------------------------------------------------+
double LCP_StrToDouble(const string s)
  {
   string trimmed = s;
   StringTrimLeft(trimmed);
   StringTrimRight(trimmed);
   if(StringLen(trimmed) == 0) return 0.0;
   return StringToDouble(trimmed);
  }

//=======================================================================
//  オブジェクト生成ヘルパー
//=======================================================================
ENUM_BASE_CORNER LCP_Corner()
  {
   if(LCP_PanelCorner == LCP_CORNER_LEFT_UPPER)  return CORNER_LEFT_UPPER;
   if(LCP_PanelCorner == LCP_CORNER_RIGHT_UPPER) return CORNER_RIGHT_UPPER;
   if(LCP_PanelCorner == LCP_CORNER_LEFT_LOWER)  return CORNER_LEFT_LOWER;
   return CORNER_RIGHT_LOWER;
  }

bool LCP_CreateLabel(const string name, const int x, const int y,
                     const string text, const color clr)
  {
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0))
     {
      PrintFormat("[LCP] ラベル作成失敗 name=%s err=%d", name, GetLastError());
      return false;
     }
   ObjectSetInteger(0, name, OBJPROP_CORNER,     LCP_Corner());
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   LCP_FontSize);
   ObjectSetString(0,  name, OBJPROP_FONT,       LCP_FontName);
   ObjectSetString(0,  name, OBJPROP_TEXT,       text);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
   return true;
  }

bool LCP_CreateEdit(const string name, const int x, const int y,
                    const int w, const int h, const string text)
  {
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   if(!ObjectCreate(0, name, OBJ_EDIT, 0, 0, 0))
     {
      PrintFormat("[LCP] 編集ボックス作成失敗 name=%s err=%d", name, GetLastError());
      return false;
     }
   ObjectSetInteger(0, name, OBJPROP_CORNER,     LCP_Corner());
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,      w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,      h);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   LCP_FontSize);
   ObjectSetString(0,  name, OBJPROP_FONT,       LCP_FontName);
   ObjectSetString(0,  name, OBJPROP_TEXT,       text);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      LCP_ColorEdit);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,    LCP_ColorEditBg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrDimGray);
   ObjectSetInteger(0, name, OBJPROP_ALIGN,      ALIGN_CENTER);
   ObjectSetInteger(0, name, OBJPROP_READONLY,   0);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
   return true;
  }

void LCP_UpdateLabel(const string name, const string text, const color clr)
  {
   if(ObjectFind(0, name) < 0) return;
   ObjectSetString(0,  name, OBJPROP_TEXT,  text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
  }

void LCP_DeleteOne(const string name)
  {
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
  }

void LCP_DeleteAllObjects()
  {
   LCP_DeleteOne(g_lblTitle);
   LCP_DeleteOne(g_lblBalance);
   LCP_DeleteOne(g_lblRiskLabel);
   LCP_DeleteOne(g_editRisk);
   LCP_DeleteOne(g_lblSLLabel);
   LCP_DeleteOne(g_editSL);
   LCP_DeleteOne(g_lblSep1);
   LCP_DeleteOne(g_lblLotResult);
   LCP_DeleteOne(g_lblLossResult);
   LCP_DeleteOne(g_lblRR1);
   LCP_DeleteOne(g_lblRR2);
   LCP_DeleteOne(g_lblRR3);
   LCP_DeleteOne(g_lblSep2);
   LCP_DeleteOne(g_lblHint);
  }

//=======================================================================
//  計算ロジック
//=======================================================================

//+------------------------------------------------------------------+
//| 現在の入力値から最適ロットと損益見込みを計算してパネル更新        |
//+------------------------------------------------------------------+
void LCP_Recalculate()
  {
   // 現在の残高/有効証拠金
   double base      = LCP_BaseOnEquity ? AccountEquity() : AccountBalance();
   string accCurr   = AccountCurrency();

   // ベース金額の表示
   string baseLabel = LCP_BaseOnEquity ? "有効証拠金" : "残高";
   LCP_UpdateLabel(g_lblBalance,
                   StringFormat("%s: %s", baseLabel, LCP_FormatMoney(base, accCurr)),
                   LCP_ColorLabel);

   // 入力値検証
   if(g_currentRiskPct <= 0.0 || g_currentRiskPct > 100.0)
     {
      LCP_UpdateLabel(g_lblLotResult,  "リスク%が不正です",  LCP_ColorWarn);
      LCP_UpdateLabel(g_lblLossResult, "",                   LCP_ColorLabel);
      LCP_UpdateLabel(g_lblRR1,        "",                   LCP_ColorLabel);
      LCP_UpdateLabel(g_lblRR2,        "",                   LCP_ColorLabel);
      LCP_UpdateLabel(g_lblRR3,        "",                   LCP_ColorLabel);
      return;
     }
   if(g_currentSLPips <= 0.0)
     {
      LCP_UpdateLabel(g_lblLotResult,  "SL幅が不正です",     LCP_ColorWarn);
      LCP_UpdateLabel(g_lblLossResult, "",                   LCP_ColorLabel);
      LCP_UpdateLabel(g_lblRR1,        "",                   LCP_ColorLabel);
      LCP_UpdateLabel(g_lblRR2,        "",                   LCP_ColorLabel);
      LCP_UpdateLabel(g_lblRR3,        "",                   LCP_ColorLabel);
      return;
     }

   // 許容リスク金額
   double riskAmount = base * g_currentRiskPct / 100.0;

   // 1ロットあたりpip価値
   double pipValuePerLot = LCP_PipValuePerLot();
   if(pipValuePerLot <= 0.0)
     {
      LCP_UpdateLabel(g_lblLotResult, "pip価値取得失敗(銘柄を確認)", LCP_ColorWarn);
      return;
     }

   // 1ロットあたりのSL損失(口座通貨)
   double lossPerLot = pipValuePerLot * g_currentSLPips;
   if(lossPerLot <= 0.0)
     {
      LCP_UpdateLabel(g_lblLotResult, "計算失敗", LCP_ColorWarn);
      return;
     }

   // 最適ロット(生値) → 正規化
   double rawLot  = riskAmount / lossPerLot;
   double finalLot= LCP_NormalizeLot(rawLot);

   // 丸め後の実際の損失額
   double actualLoss = finalLot * lossPerLot;

   // ロット結果表示
   double minLot = MarketInfo(Symbol(), MODE_MINLOT);
   color  lotClr = (rawLot < minLot) ? LCP_ColorWarn : LCP_ColorValue;
   string lotNote= (rawLot < minLot) ? " (最小未満→切上)" : "";
   LCP_UpdateLabel(g_lblLotResult,
                   StringFormat("ロット: %.2f%s", finalLot, lotNote),
                   lotClr);

   // 損失表示
   LCP_UpdateLabel(g_lblLossResult,
                   StringFormat("想定損失: %s", LCP_FormatMoney(actualLoss, accCurr)),
                   LCP_ColorLabel);

   // RR分析
   if(LCP_ShowRRAnalysis)
     {
      LCP_UpdateLabel(g_lblRR1,
                      StringFormat("RR 1:1  利益: %s", LCP_FormatMoney(actualLoss * 1.0, accCurr)),
                      LCP_ColorLabel);
      LCP_UpdateLabel(g_lblRR2,
                      StringFormat("RR 1:2  利益: %s", LCP_FormatMoney(actualLoss * 2.0, accCurr)),
                      LCP_ColorLabel);
      LCP_UpdateLabel(g_lblRR3,
                      StringFormat("RR 1:3  利益: %s", LCP_FormatMoney(actualLoss * 3.0, accCurr)),
                      LCP_ColorLabel);
     }
   else
     {
      LCP_UpdateLabel(g_lblRR1, "", LCP_ColorLabel);
      LCP_UpdateLabel(g_lblRR2, "", LCP_ColorLabel);
      LCP_UpdateLabel(g_lblRR3, "", LCP_ColorLabel);
     }

   ChartRedraw(0);
  }

//=======================================================================
//  MQL4 必須コールバック
//=======================================================================
int OnInit()
  {
   // 初期値セット
   g_currentRiskPct = LCP_DefaultRiskPct;
   g_currentSLPips  = LCP_DefaultSLPips;

   // 既存オブジェクトを削除
   LCP_DeleteAllObjects();

   // パネル生成
   int x = LCP_PanelPosX;
   int y = LCP_PanelPosY;
   int h = LCP_LineHeight;
   int editH = h - 2;

   if(!LCP_CreateLabel(g_lblTitle, x, y, "=== ロット計算機 ===", LCP_ColorTitle)) return INIT_FAILED;
   y += h;

   if(!LCP_CreateLabel(g_lblBalance, x, y, "", LCP_ColorLabel)) return INIT_FAILED;
   y += h;

   if(!LCP_CreateLabel(g_lblRiskLabel, x, y, "リスク(%):", LCP_ColorLabel)) return INIT_FAILED;
   if(!LCP_CreateEdit (g_editRisk,     x + 110, y, LCP_EditWidth, editH,
                       DoubleToString(g_currentRiskPct, 2))) return INIT_FAILED;
   y += h;

   if(!LCP_CreateLabel(g_lblSLLabel, x, y, "SL幅 (pips):", LCP_ColorLabel)) return INIT_FAILED;
   if(!LCP_CreateEdit (g_editSL,     x + 110, y, LCP_EditWidth, editH,
                       DoubleToString(g_currentSLPips, 1))) return INIT_FAILED;
   y += h;

   if(!LCP_CreateLabel(g_lblSep1, x, y, "--------------------------------", LCP_ColorLabel)) return INIT_FAILED;
   y += h;

   if(!LCP_CreateLabel(g_lblLotResult,  x, y, "", LCP_ColorValue)) return INIT_FAILED; y += h;
   if(!LCP_CreateLabel(g_lblLossResult, x, y, "", LCP_ColorLabel)) return INIT_FAILED; y += h;
   if(!LCP_CreateLabel(g_lblRR1,        x, y, "", LCP_ColorLabel)) return INIT_FAILED; y += h;
   if(!LCP_CreateLabel(g_lblRR2,        x, y, "", LCP_ColorLabel)) return INIT_FAILED; y += h;
   if(!LCP_CreateLabel(g_lblRR3,        x, y, "", LCP_ColorLabel)) return INIT_FAILED; y += h;

   if(!LCP_CreateLabel(g_lblSep2, x, y, "--------------------------------", LCP_ColorLabel)) return INIT_FAILED;
   y += h;
   if(!LCP_CreateLabel(g_lblHint, x, y, "※ 数値変更→Enter で再計算", LCP_ColorLabel)) return INIT_FAILED;

   // 初回計算
   LCP_Recalculate();

   PrintFormat("[LCP] 起動完了 Symbol=%s Base=%s", Symbol(),
               LCP_BaseOnEquity ? "Equity" : "Balance");
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   LCP_DeleteAllObjects();
   ChartRedraw(0);
   PrintFormat("[LCP] 終了 reason=%d", reason);
  }

//+------------------------------------------------------------------+
//| ティック毎に残高・有効証拠金が変わる可能性があるため再計算        |
//+------------------------------------------------------------------+
void OnTick()
  {
   LCP_Recalculate();
  }

//+------------------------------------------------------------------+
//| 編集ボックスの値が変更された時                                    |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long   &lparam,
                  const double &dparam,
                  const string &sparam)
  {
   if(id != CHARTEVENT_OBJECT_ENDEDIT) return;

   if(sparam == g_editRisk)
     {
      double v = LCP_StrToDouble(ObjectGetString(0, g_editRisk, OBJPROP_TEXT));
      g_currentRiskPct = v;
      // 正規化してボックスに書き戻し
      ObjectSetString(0, g_editRisk, OBJPROP_TEXT, DoubleToString(v, 2));
     }
   else if(sparam == g_editSL)
     {
      double v = LCP_StrToDouble(ObjectGetString(0, g_editSL, OBJPROP_TEXT));
      g_currentSLPips = v;
      ObjectSetString(0, g_editSL, OBJPROP_TEXT, DoubleToString(v, 1));
     }
   else
      return;

   LCP_Recalculate();
  }
//+------------------------------------------------------------------+
