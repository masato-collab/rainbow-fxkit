//+------------------------------------------------------------------+
//|                                         VisualSLTP_Tool.mq4     |
//|  エントリー/SL/TPの3本のラインをチャートにドラッグ配置できる    |
//|  ユーティリティEA                                                 |
//|  機能:                                                            |
//|    - Entry / SL / TP の3本をチャート上にHLINE配置・ドラッグ可能  |
//|    - ライン移動ごとにpips/想定損益/RR比を即座に再計算表示        |
//|    - BUY/SELL切替ボタン                                           |
//|    - 既存ポジションにSL/TPを一括適用するボタン(マジック番号対応) |
//|    - 利益/損失エリアをチャートに塗りつぶし表示                    |
//+------------------------------------------------------------------+
#property strict
#property copyright   "VisualSLTP_Tool v1.00"
#property description "エントリー/SL/TPラインをビジュアル配置するユーティリティEA"
#property version     "1.00"

//--- 列挙型
enum ENUM_VST_DIR
  {
   VST_DIR_BUY  = 0, // 買い(BUY)
   VST_DIR_SELL = 1  // 売り(SELL)
  };

//--- プレフィックス(オブジェクト名重複防止)
#define VST_PREFIX "VST_"

//=======================================================================
//  入力パラメーター
//=======================================================================
input double        VST_DefaultLots          = 0.10;              // 試算ロット(初期値)
input ENUM_VST_DIR  VST_Direction            = VST_DIR_BUY;       // 起動時の方向
input int           VST_MagicNumber          = 0;                 // 適用対象マジック番号(0=自シンボル全ポジション)
input color         VST_EntryColor           = clrYellow;         // エントリーライン色
input color         VST_SLColor              = clrTomato;         // SLライン色
input color         VST_TPColor              = clrMediumSeaGreen; // TPライン色
input bool          VST_FillProfitArea       = true;              // 利益/損失エリア塗りつぶし
input color         VST_FillProfitColor      = clrDarkGreen;      // 利益エリア色
input color         VST_FillLossColor        = clrMaroon;         // 損失エリア色
input int           VST_LineWidth            = 2;                 // ライン幅
input int           VST_FontSize             = 10;                // フォントサイズ
input string        VST_FontName             = "MS ゴシック";      // フォント名(日本語対応)
input int           VST_PanelPosX            = 20;                // パネルX余白(px)
input int           VST_PanelPosY            = 30;                // パネルY余白(px)
input color         VST_PanelTextColor       = clrWhite;          // パネル文字色
input color         VST_PanelTitleColor      = clrAqua;           // パネルタイトル色
input int           VST_LineHeight           = 20;                // パネル行高(px)

//=======================================================================
//  オブジェクト名(定数)
//=======================================================================
string g_lnEntry = VST_PREFIX + "line_entry";
string g_lnSL    = VST_PREFIX + "line_sl";
string g_lnTP    = VST_PREFIX + "line_tp";
string g_rectPL  = VST_PREFIX + "rect_profit"; // 利益エリア
string g_rectSL  = VST_PREFIX + "rect_loss";   // 損失エリア

string g_lblTitle  = VST_PREFIX + "lbl_title";
string g_lblDir    = VST_PREFIX + "lbl_dir";
string g_lblEntry  = VST_PREFIX + "lbl_entry";
string g_lblSL     = VST_PREFIX + "lbl_sl";
string g_lblTP     = VST_PREFIX + "lbl_tp";
string g_lblSLPips = VST_PREFIX + "lbl_slpips";
string g_lblTPPips = VST_PREFIX + "lbl_tppips";
string g_lblLoss   = VST_PREFIX + "lbl_loss";
string g_lblProfit = VST_PREFIX + "lbl_profit";
string g_lblRR     = VST_PREFIX + "lbl_rr";
string g_btnFlip   = VST_PREFIX + "btn_flip";
string g_btnApply  = VST_PREFIX + "btn_apply";

//=======================================================================
//  内部変数
//=======================================================================
ENUM_VST_DIR g_direction; // 現在の方向

//=======================================================================
//  ユーティリティ
//=======================================================================

//+------------------------------------------------------------------+
//| pip単位の自動判定                                                 |
//+------------------------------------------------------------------+
double VST_DetectPipSize()
  {
   int digits = (int)MarketInfo(Symbol(), MODE_DIGITS);
   if(digits == 3 || digits == 5) return Point * 10.0;
   return Point;
  }

//+------------------------------------------------------------------+
//| 1ロットあたりのpip価値(口座通貨)                                  |
//+------------------------------------------------------------------+
double VST_PipValuePerLot()
  {
   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize  = MarketInfo(Symbol(), MODE_TICKSIZE);
   double pipSize   = VST_DetectPipSize();
   if(tickSize <= 0.0 || pipSize <= 0.0) return 0.0;
   return tickValue * (pipSize / tickSize);
  }

//+------------------------------------------------------------------+
//| 金額を3桁カンマ区切り文字列に                                     |
//+------------------------------------------------------------------+
string VST_FormatMoney(const double amount, const string currency)
  {
   string signStr = (amount < 0.0) ? "-" : "";
   double absAmt  = MathAbs(amount);
   string intPart = DoubleToString(MathRound(absAmt), 0);
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

//=======================================================================
//  オブジェクト生成ヘルパー
//=======================================================================
bool VST_CreateHLine(const string name, const double price, const color clr)
  {
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   if(!ObjectCreate(0, name, OBJ_HLINE, 0, 0, price))
     {
      PrintFormat("[VST] HLINE作成失敗 name=%s err=%d", name, GetLastError());
      return false;
     }
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,      VST_LineWidth);
   ObjectSetInteger(0, name, OBJPROP_STYLE,      STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_BACK,       false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);   // ドラッグ可能
   ObjectSetInteger(0, name, OBJPROP_SELECTED,   false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     false);
   return true;
  }

bool VST_CreateLabel(const string name, const int x, const int y,
                     const string text, const color clr)
  {
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0))
     {
      PrintFormat("[VST] ラベル作成失敗 name=%s err=%d", name, GetLastError());
      return false;
     }
   ObjectSetInteger(0, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   VST_FontSize);
   ObjectSetString(0,  name, OBJPROP_FONT,       VST_FontName);
   ObjectSetString(0,  name, OBJPROP_TEXT,       text);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
   return true;
  }

bool VST_CreateButton(const string name, const int x, const int y,
                      const int w, const int h, const string text,
                      const color txtClr, const color bgClr)
  {
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   if(!ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0))
     {
      PrintFormat("[VST] ボタン作成失敗 name=%s err=%d", name, GetLastError());
      return false;
     }
   ObjectSetInteger(0, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,      w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,      h);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   VST_FontSize);
   ObjectSetString(0,  name, OBJPROP_FONT,       VST_FontName);
   ObjectSetString(0,  name, OBJPROP_TEXT,       text);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      txtClr);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,    bgClr);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrDimGray);
   ObjectSetInteger(0, name, OBJPROP_STATE,      false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
   return true;
  }

bool VST_CreateRect(const string name, const datetime t1, const double p1,
                    const datetime t2, const double p2, const color clr)
  {
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   if(!ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2))
     {
      PrintFormat("[VST] Rectangle作成失敗 name=%s err=%d", name, GetLastError());
      return false;
     }
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,      1);
   ObjectSetInteger(0, name, OBJPROP_STYLE,      STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_FILL,       true);
   ObjectSetInteger(0, name, OBJPROP_BACK,       true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
   return true;
  }

void VST_DeleteOne(const string name)
  {
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
  }

void VST_DeleteAllObjects()
  {
   VST_DeleteOne(g_lnEntry); VST_DeleteOne(g_lnSL);    VST_DeleteOne(g_lnTP);
   VST_DeleteOne(g_rectPL);  VST_DeleteOne(g_rectSL);
   VST_DeleteOne(g_lblTitle);VST_DeleteOne(g_lblDir);  VST_DeleteOne(g_lblEntry);
   VST_DeleteOne(g_lblSL);   VST_DeleteOne(g_lblTP);   VST_DeleteOne(g_lblSLPips);
   VST_DeleteOne(g_lblTPPips);VST_DeleteOne(g_lblLoss);VST_DeleteOne(g_lblProfit);
   VST_DeleteOne(g_lblRR);   VST_DeleteOne(g_btnFlip); VST_DeleteOne(g_btnApply);
  }

//=======================================================================
//  ライン&塗りつぶしの更新
//=======================================================================

//+------------------------------------------------------------------+
//| 現在のライン価格を取得                                            |
//+------------------------------------------------------------------+
double VST_GetLinePrice(const string name)
  {
   if(ObjectFind(0, name) < 0) return 0.0;
   return ObjectGetDouble(0, name, OBJPROP_PRICE);
  }

//+------------------------------------------------------------------+
//| 利益/損失エリアの矩形を更新                                       |
//+------------------------------------------------------------------+
void VST_UpdateRects()
  {
   if(!VST_FillProfitArea)
     {
      VST_DeleteOne(g_rectPL);
      VST_DeleteOne(g_rectSL);
      return;
     }

   double entry = VST_GetLinePrice(g_lnEntry);
   double sl    = VST_GetLinePrice(g_lnSL);
   double tp    = VST_GetLinePrice(g_lnTP);
   if(entry <= 0.0 || sl <= 0.0 || tp <= 0.0) return;

   // 時間範囲: 過去30本 ～ 未来30本 を網羅
   int      periodSec = PeriodSeconds();
   datetime t1 = TimeCurrent() - 30 * periodSec;
   datetime t2 = TimeCurrent() + 30 * periodSec;

   // 利益エリア(Entry ↔ TP)
   if(ObjectFind(0, g_rectPL) < 0)
      VST_CreateRect(g_rectPL, t1, entry, t2, tp, VST_FillProfitColor);
   else
     {
      ObjectSetInteger(0, g_rectPL, OBJPROP_TIME,  0, t1);
      ObjectSetDouble (0, g_rectPL, OBJPROP_PRICE, 0, entry);
      ObjectSetInteger(0, g_rectPL, OBJPROP_TIME,  1, t2);
      ObjectSetDouble (0, g_rectPL, OBJPROP_PRICE, 1, tp);
      ObjectSetInteger(0, g_rectPL, OBJPROP_COLOR, VST_FillProfitColor);
     }

   // 損失エリア(Entry ↔ SL)
   if(ObjectFind(0, g_rectSL) < 0)
      VST_CreateRect(g_rectSL, t1, entry, t2, sl, VST_FillLossColor);
   else
     {
      ObjectSetInteger(0, g_rectSL, OBJPROP_TIME,  0, t1);
      ObjectSetDouble (0, g_rectSL, OBJPROP_PRICE, 0, entry);
      ObjectSetInteger(0, g_rectSL, OBJPROP_TIME,  1, t2);
      ObjectSetDouble (0, g_rectSL, OBJPROP_PRICE, 1, sl);
      ObjectSetInteger(0, g_rectSL, OBJPROP_COLOR, VST_FillLossColor);
     }
  }

//=======================================================================
//  パネル情報更新
//=======================================================================
void VST_UpdatePanel()
  {
   double entry = VST_GetLinePrice(g_lnEntry);
   double sl    = VST_GetLinePrice(g_lnSL);
   double tp    = VST_GetLinePrice(g_lnTP);
   double pip   = VST_DetectPipSize();
   int    dig   = (int)MarketInfo(Symbol(), MODE_DIGITS);

   string dirStr = (g_direction == VST_DIR_BUY) ? "BUY (買い)" : "SELL (売り)";
   color  dirClr = (g_direction == VST_DIR_BUY) ? clrLime : clrOrange;
   ObjectSetString(0, g_lblDir, OBJPROP_TEXT, "方向: " + dirStr);
   ObjectSetInteger(0, g_lblDir, OBJPROP_COLOR, dirClr);

   ObjectSetString(0, g_lblEntry, OBJPROP_TEXT,
                   StringFormat("Entry : %s", DoubleToString(entry, dig)));
   ObjectSetString(0, g_lblSL, OBJPROP_TEXT,
                   StringFormat("SL    : %s", DoubleToString(sl, dig)));
   ObjectSetString(0, g_lblTP, OBJPROP_TEXT,
                   StringFormat("TP    : %s", DoubleToString(tp, dig)));

   // pips計算
   double slPips = (pip > 0.0) ? MathAbs(entry - sl) / pip : 0.0;
   double tpPips = (pip > 0.0) ? MathAbs(entry - tp) / pip : 0.0;
   ObjectSetString(0, g_lblSLPips, OBJPROP_TEXT,
                   StringFormat("SL幅  : %.1f pips", slPips));
   ObjectSetString(0, g_lblTPPips, OBJPROP_TEXT,
                   StringFormat("TP幅  : %.1f pips", tpPips));

   // 損益試算
   double pipValue = VST_PipValuePerLot();
   double lossAmt  = pipValue * slPips * VST_DefaultLots;
   double profAmt  = pipValue * tpPips * VST_DefaultLots;
   string accCurr  = AccountCurrency();

   ObjectSetString(0, g_lblLoss, OBJPROP_TEXT,
                   StringFormat("想定損失(%.2flot): %s",
                                VST_DefaultLots, VST_FormatMoney(lossAmt, accCurr)));
   ObjectSetString(0, g_lblProfit, OBJPROP_TEXT,
                   StringFormat("想定利益(%.2flot): %s",
                                VST_DefaultLots, VST_FormatMoney(profAmt, accCurr)));

   // RR比
   string rrStr;
   if(slPips > 0.0)
      rrStr = StringFormat("RR 1:%.2f", tpPips / slPips);
   else
      rrStr = "RR : SL幅0で計算不可";
   ObjectSetString(0, g_lblRR, OBJPROP_TEXT, rrStr);

   ChartRedraw(0);
  }

//=======================================================================
//  既存ポジションへの適用
//=======================================================================
void VST_ApplyToPositions()
  {
   double sl = VST_GetLinePrice(g_lnSL);
   double tp = VST_GetLinePrice(g_lnTP);
   if(sl <= 0.0 || tp <= 0.0)
     {
      Alert("[VST] SL/TPラインが無効です");
      return;
     }

   int total     = OrdersTotal();
   int modified  = 0;
   int skipped   = 0;
   int failed    = 0;

   for(int i = 0; i < total; i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) { skipped++; continue; }
      if(VST_MagicNumber != 0 && OrderMagicNumber() != VST_MagicNumber)
        { skipped++; continue; }
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) { skipped++; continue; }

      double newSL = NormalizeDouble(sl, (int)MarketInfo(Symbol(), MODE_DIGITS));
      double newTP = NormalizeDouble(tp, (int)MarketInfo(Symbol(), MODE_DIGITS));

      if(!OrderModify(OrderTicket(), OrderOpenPrice(), newSL, newTP, 0, clrNONE))
        {
         int err = GetLastError();
         PrintFormat("[VST] OrderModify失敗 ticket=%d err=%d", OrderTicket(), err);
         failed++;
        }
      else
         modified++;
     }

   string msg = StringFormat("[VST] 適用結果: 成功=%d スキップ=%d 失敗=%d",
                             modified, skipped, failed);
   Alert(msg);
   Print(msg);
  }

//+------------------------------------------------------------------+
//| BUY/SELL を切り替えてSL/TPラインを自動入れ替え                    |
//+------------------------------------------------------------------+
void VST_FlipDirection()
  {
   g_direction = (g_direction == VST_DIR_BUY) ? VST_DIR_SELL : VST_DIR_BUY;

   // SLとTPの位置を入れ替え
   double sl = VST_GetLinePrice(g_lnSL);
   double tp = VST_GetLinePrice(g_lnTP);
   ObjectSetDouble(0, g_lnSL, OBJPROP_PRICE, tp);
   ObjectSetDouble(0, g_lnTP, OBJPROP_PRICE, sl);

   // ボタン状態も戻す
   ObjectSetInteger(0, g_btnFlip, OBJPROP_STATE, false);

   VST_UpdatePanel();
   VST_UpdateRects();
  }

//=======================================================================
//  MQL4 必須コールバック
//=======================================================================
int OnInit()
  {
   g_direction = VST_Direction;

   VST_DeleteAllObjects();

   // ライン初期位置: BUY の場合 Entry=Bid, SL=-200pts, TP=+400pts
   double bid = Bid;
   double pip = VST_DetectPipSize();
   double slOffset = 20.0 * pip;
   double tpOffset = 40.0 * pip;

   double entry = bid;
   double sl    = (g_direction == VST_DIR_BUY) ? bid - slOffset : bid + slOffset;
   double tp    = (g_direction == VST_DIR_BUY) ? bid + tpOffset : bid - tpOffset;

   if(!VST_CreateHLine(g_lnEntry, entry, VST_EntryColor)) return INIT_FAILED;
   if(!VST_CreateHLine(g_lnSL,    sl,    VST_SLColor))    return INIT_FAILED;
   if(!VST_CreateHLine(g_lnTP,    tp,    VST_TPColor))    return INIT_FAILED;

   // パネル
   int x = VST_PanelPosX;
   int y = VST_PanelPosY;
   int h = VST_LineHeight;

   if(!VST_CreateLabel(g_lblTitle, x, y, "=== Visual SL/TP ===", VST_PanelTitleColor)) return INIT_FAILED; y += h;
   if(!VST_CreateLabel(g_lblDir,    x, y, "", VST_PanelTextColor)) return INIT_FAILED; y += h;
   if(!VST_CreateLabel(g_lblEntry,  x, y, "", VST_PanelTextColor)) return INIT_FAILED; y += h;
   if(!VST_CreateLabel(g_lblSL,     x, y, "", VST_PanelTextColor)) return INIT_FAILED; y += h;
   if(!VST_CreateLabel(g_lblTP,     x, y, "", VST_PanelTextColor)) return INIT_FAILED; y += h;
   if(!VST_CreateLabel(g_lblSLPips, x, y, "", VST_PanelTextColor)) return INIT_FAILED; y += h;
   if(!VST_CreateLabel(g_lblTPPips, x, y, "", VST_PanelTextColor)) return INIT_FAILED; y += h;
   if(!VST_CreateLabel(g_lblLoss,   x, y, "", VST_PanelTextColor)) return INIT_FAILED; y += h;
   if(!VST_CreateLabel(g_lblProfit, x, y, "", VST_PanelTextColor)) return INIT_FAILED; y += h;
   if(!VST_CreateLabel(g_lblRR,     x, y, "", VST_PanelTextColor)) return INIT_FAILED; y += h;

   // ボタン
   if(!VST_CreateButton(g_btnFlip, x, y, 160, h - 2, "方向 BUY/SELL 切替",
                         clrBlack, clrGold)) return INIT_FAILED;
   y += h;
   if(!VST_CreateButton(g_btnApply, x, y, 160, h - 2, "既存ポジションに適用",
                         clrWhite, clrMediumBlue)) return INIT_FAILED;

   VST_UpdateRects();
   VST_UpdatePanel();

   PrintFormat("[VST] 起動完了 Direction=%s Symbol=%s",
               (g_direction == VST_DIR_BUY) ? "BUY" : "SELL", Symbol());
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   VST_DeleteAllObjects();
   ChartRedraw(0);
   PrintFormat("[VST] 終了 reason=%d", reason);
  }

void OnTick()
  {
   VST_UpdatePanel();
  }

//+------------------------------------------------------------------+
//| チャートイベント処理                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long   &lparam,
                  const double &dparam,
                  const string &sparam)
  {
   // ラインドラッグ完了時
   if(id == CHARTEVENT_OBJECT_DRAG)
     {
      if(sparam == g_lnEntry || sparam == g_lnSL || sparam == g_lnTP)
        {
         VST_UpdatePanel();
         VST_UpdateRects();
        }
      return;
     }

   // ボタンクリック
   if(id == CHARTEVENT_OBJECT_CLICK)
     {
      if(sparam == g_btnFlip)
        {
         VST_FlipDirection();
        }
      else if(sparam == g_btnApply)
        {
         VST_ApplyToPositions();
         ObjectSetInteger(0, g_btnApply, OBJPROP_STATE, false);
        }
      return;
     }
  }
//+------------------------------------------------------------------+
