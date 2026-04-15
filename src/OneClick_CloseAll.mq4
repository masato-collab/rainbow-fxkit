//+------------------------------------------------------------------+
//|                                         OneClick_CloseAll.mq4   |
//|  ワンクリックで全ポジション/買い/売り/利益/損失を決済する       |
//|  ユーティリティEA                                                 |
//|  機能:                                                            |
//|    - チャート上に5種類の決済ボタンを配置                          |
//|    - 全決済 / 買いのみ / 売りのみ / 利益のみ / 損失のみ           |
//|    - 決済前に確認ダイアログを表示(誤操作防止)                     |
//|    - シンボル絞り込み・マジック番号フィルタに対応                 |
//|    - 決済失敗時の自動リトライ                                     |
//|    - 現在のポジション数/合計損益を常時表示                        |
//+------------------------------------------------------------------+
#property strict
#property copyright   "OneClick_CloseAll v1.00"
#property description "ワンクリックで一括決済するユーティリティEA"
#property version     "1.00"

//--- 表示コーナー列挙
enum ENUM_OCA_CORNER
  {
   OCA_CORNER_LEFT_UPPER  = 0, // 左上
   OCA_CORNER_RIGHT_UPPER = 1, // 右上
   OCA_CORNER_LEFT_LOWER  = 2, // 左下
   OCA_CORNER_RIGHT_LOWER = 3  // 右下
  };

//--- 決済種別
enum ENUM_OCA_CLOSE_MODE
  {
   OCA_CLOSE_ALL        = 0, // 全決済
   OCA_CLOSE_BUY_ONLY   = 1, // 買いのみ
   OCA_CLOSE_SELL_ONLY  = 2, // 売りのみ
   OCA_CLOSE_PROFIT     = 3, // 利益ポジのみ
   OCA_CLOSE_LOSS       = 4  // 損失ポジのみ
  };

//--- プレフィックス
#define OCA_PREFIX "OCA_"

//=======================================================================
//  入力パラメーター
//=======================================================================
input bool             OCA_CurrentSymbolOnly = true;                   // 自通貨ペアのみ対象
input int              OCA_FilterMagic       = 0;                     // 対象マジック番号(0=全て)
input bool             OCA_ConfirmBeforeClose= true;                  // 決済前に確認ダイアログ
input ENUM_OCA_CORNER  OCA_PanelCorner       = OCA_CORNER_RIGHT_LOWER;// パネル位置
input int              OCA_ButtonWidth       = 140;                   // ボタン幅(px)
input int              OCA_ButtonHeight      = 24;                    // ボタン高(px)
input int              OCA_Slippage          = 10;                    // 許容スリッページ(point)
input int              OCA_MaxRetry          = 3;                     // 決済失敗時のリトライ回数
input int              OCA_RetryDelayMs      = 500;                   // リトライ間隔(ms)
input int              OCA_FontSize          = 10;                    // フォントサイズ
input string           OCA_FontName          = "MS ゴシック";          // フォント名(日本語対応)
input int              OCA_PanelMargin       = 10;                    // パネル余白(px)
input int              OCA_SpacingY          = 4;                     // ボタン間スペース(px)
input color            OCA_ColorTitle        = clrAqua;               // タイトル色
input color            OCA_ColorStatus       = clrWhite;              // ステータス色

//=======================================================================
//  オブジェクト名(定数)
//=======================================================================
string g_lblTitle   = OCA_PREFIX + "lbl_title";
string g_lblStatus1 = OCA_PREFIX + "lbl_status1";
string g_lblStatus2 = OCA_PREFIX + "lbl_status2";
string g_btnAll     = OCA_PREFIX + "btn_all";
string g_btnBuy     = OCA_PREFIX + "btn_buy";
string g_btnSell    = OCA_PREFIX + "btn_sell";
string g_btnProfit  = OCA_PREFIX + "btn_profit";
string g_btnLoss    = OCA_PREFIX + "btn_loss";

//=======================================================================
//  ユーティリティ
//=======================================================================
ENUM_BASE_CORNER OCA_GetCorner()
  {
   if(OCA_PanelCorner == OCA_CORNER_LEFT_UPPER)  return CORNER_LEFT_UPPER;
   if(OCA_PanelCorner == OCA_CORNER_RIGHT_UPPER) return CORNER_RIGHT_UPPER;
   if(OCA_PanelCorner == OCA_CORNER_LEFT_LOWER)  return CORNER_LEFT_LOWER;
   return CORNER_RIGHT_LOWER;
  }

//+------------------------------------------------------------------+
//| 決済種別の日本語ラベル                                            |
//+------------------------------------------------------------------+
string OCA_ModeLabel(const ENUM_OCA_CLOSE_MODE mode)
  {
   if(mode == OCA_CLOSE_ALL)        return "全決済";
   if(mode == OCA_CLOSE_BUY_ONLY)   return "買いポジのみ";
   if(mode == OCA_CLOSE_SELL_ONLY)  return "売りポジのみ";
   if(mode == OCA_CLOSE_PROFIT)     return "利益ポジのみ";
   if(mode == OCA_CLOSE_LOSS)       return "損失ポジのみ";
   return "?";
  }

//+------------------------------------------------------------------+
//| 指定ポジションが条件にマッチするか判定                            |
//+------------------------------------------------------------------+
bool OCA_MatchesFilter(const ENUM_OCA_CLOSE_MODE mode)
  {
   if(OCA_CurrentSymbolOnly && OrderSymbol() != Symbol()) return false;
   if(OCA_FilterMagic != 0 && OrderMagicNumber() != OCA_FilterMagic) return false;
   int type = OrderType();
   if(type != OP_BUY && type != OP_SELL) return false;

   if(mode == OCA_CLOSE_ALL)       return true;
   if(mode == OCA_CLOSE_BUY_ONLY)  return (type == OP_BUY);
   if(mode == OCA_CLOSE_SELL_ONLY) return (type == OP_SELL);

   double pnl = OrderProfit() + OrderSwap() + OrderCommission();
   if(mode == OCA_CLOSE_PROFIT)    return (pnl > 0.0);
   if(mode == OCA_CLOSE_LOSS)      return (pnl < 0.0);
   return false;
  }

//+------------------------------------------------------------------+
//| 金額を3桁カンマ区切り文字列に                                     |
//+------------------------------------------------------------------+
string OCA_FormatMoney(const double amount, const string currency)
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

//+------------------------------------------------------------------+
//| 現在のポジション集計                                              |
//| outCount: 対象件数, outPnL: 合計損益                              |
//+------------------------------------------------------------------+
void OCA_Summary(int &outCount, double &outPnL)
  {
   outCount = 0;
   outPnL   = 0.0;
   int total = OrdersTotal();
   for(int i = 0; i < total; i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OCA_CurrentSymbolOnly && OrderSymbol() != Symbol()) continue;
      if(OCA_FilterMagic != 0 && OrderMagicNumber() != OCA_FilterMagic) continue;
      int type = OrderType();
      if(type != OP_BUY && type != OP_SELL) continue;

      outCount++;
      outPnL += OrderProfit() + OrderSwap() + OrderCommission();
     }
  }

//=======================================================================
//  オブジェクト生成
//=======================================================================
bool OCA_CreateLabel(const string name, const int x, const int y,
                     const string text, const color clr)
  {
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0))
     {
      PrintFormat("[OCA] ラベル作成失敗 name=%s err=%d", name, GetLastError());
      return false;
     }
   ObjectSetInteger(0, name, OBJPROP_CORNER,     OCA_GetCorner());
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   OCA_FontSize);
   ObjectSetString(0,  name, OBJPROP_FONT,       OCA_FontName);
   ObjectSetString(0,  name, OBJPROP_TEXT,       text);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);

   // 右寄せコーナーならアンカー右寄せ
   if(OCA_PanelCorner == OCA_CORNER_RIGHT_UPPER ||
      OCA_PanelCorner == OCA_CORNER_RIGHT_LOWER)
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);

   return true;
  }

bool OCA_CreateButton(const string name, const int x, const int y,
                      const int w, const int h, const string text,
                      const color txtClr, const color bgClr)
  {
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   if(!ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0))
     {
      PrintFormat("[OCA] ボタン作成失敗 name=%s err=%d", name, GetLastError());
      return false;
     }
   ObjectSetInteger(0, name, OBJPROP_CORNER,     OCA_GetCorner());
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,      w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,      h);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   OCA_FontSize);
   ObjectSetString(0,  name, OBJPROP_FONT,       OCA_FontName);
   ObjectSetString(0,  name, OBJPROP_TEXT,       text);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      txtClr);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,    bgClr);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrDimGray);
   ObjectSetInteger(0, name, OBJPROP_STATE,      false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
   return true;
  }

void OCA_DeleteOne(const string name)
  {
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
  }

void OCA_DeleteAll()
  {
   OCA_DeleteOne(g_lblTitle);
   OCA_DeleteOne(g_lblStatus1);
   OCA_DeleteOne(g_lblStatus2);
   OCA_DeleteOne(g_btnAll);
   OCA_DeleteOne(g_btnBuy);
   OCA_DeleteOne(g_btnSell);
   OCA_DeleteOne(g_btnProfit);
   OCA_DeleteOne(g_btnLoss);
  }

//=======================================================================
//  決済処理
//=======================================================================

//+------------------------------------------------------------------+
//| 1件のポジションを決済(リトライ付き)                               |
//+------------------------------------------------------------------+
bool OCA_CloseOne(const int ticket)
  {
   int errCode = 0;
   for(int attempt = 1; attempt <= OCA_MaxRetry; attempt++)
     {
      if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
        {
         errCode = GetLastError();
         PrintFormat("[OCA] ticket=%d OrderSelect失敗 err=%d", ticket, errCode);
         return false;
        }

      double closePrice = 0.0;
      int    type       = OrderType();
      if(type == OP_BUY)       closePrice = MarketInfo(OrderSymbol(), MODE_BID);
      else if(type == OP_SELL) closePrice = MarketInfo(OrderSymbol(), MODE_ASK);
      else
         return false;

      if(OrderClose(ticket, OrderLots(), closePrice, OCA_Slippage, clrNONE))
         return true;

      errCode = GetLastError();
      PrintFormat("[OCA] ticket=%d OrderClose失敗 try=%d/%d err=%d",
                  ticket, attempt, OCA_MaxRetry, errCode);

      // 即座にリトライしない
      if(attempt < OCA_MaxRetry)
         Sleep(OCA_RetryDelayMs);

      // 価格取得し直し
      RefreshRates();
     }
   return false;
  }

//+------------------------------------------------------------------+
//| 条件にマッチする全ポジションを決済                                |
//+------------------------------------------------------------------+
void OCA_ExecuteClose(const ENUM_OCA_CLOSE_MODE mode)
  {
   // 対象ticketを先に収集(決済中にインデックスが変わるため)
   int tickets[];
   ArrayResize(tickets, 0);

   int total = OrdersTotal();
   for(int i = 0; i < total; i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!OCA_MatchesFilter(mode)) continue;
      int n = ArraySize(tickets);
      ArrayResize(tickets, n + 1);
      tickets[n] = OrderTicket();
     }

   int target = ArraySize(tickets);
   if(target == 0)
     {
      Alert(StringFormat("[OCA] 対象ポジションがありません (%s)",
                         OCA_ModeLabel(mode)));
      return;
     }

   // 確認ダイアログ
   if(OCA_ConfirmBeforeClose)
     {
      string q = StringFormat("%s を %d件決済します。よろしいですか?",
                              OCA_ModeLabel(mode), target);
      int ret = MessageBox(q, "OneClick CloseAll", MB_YESNO | MB_ICONQUESTION);
      if(ret != IDYES) return;
     }

   // 決済実行
   int success = 0;
   int failed  = 0;
   for(int i = 0; i < target; i++)
     {
      if(OCA_CloseOne(tickets[i])) success++;
      else                         failed++;
     }

   string msg = StringFormat("[OCA] 決済結果: 成功=%d 失敗=%d (%s)",
                             success, failed, OCA_ModeLabel(mode));
   Alert(msg);
   Print(msg);
  }

//=======================================================================
//  パネル情報の更新
//=======================================================================
void OCA_UpdateStatus()
  {
   int    count;
   double pnl;
   OCA_Summary(count, pnl);

   string target = OCA_CurrentSymbolOnly ? Symbol() : "全通貨";
   string magic  = (OCA_FilterMagic == 0) ? "全" : IntegerToString(OCA_FilterMagic);

   ObjectSetString(0, g_lblStatus1, OBJPROP_TEXT,
                   StringFormat("対象: %s / Magic: %s", target, magic));

   color pnlClr = (pnl > 0.0) ? clrLime : ((pnl < 0.0) ? clrTomato : OCA_ColorStatus);
   ObjectSetString(0, g_lblStatus2, OBJPROP_TEXT,
                   StringFormat("%d 件 / 合計 %s",
                                count, OCA_FormatMoney(pnl, AccountCurrency())));
   ObjectSetInteger(0, g_lblStatus2, OBJPROP_COLOR, pnlClr);

   ChartRedraw(0);
  }

//=======================================================================
//  パネル構築
//=======================================================================
void OCA_BuildPanel()
  {
   OCA_DeleteAll();

   int margin = OCA_PanelMargin;
   int btnH   = OCA_ButtonHeight;
   int btnW   = OCA_ButtonWidth;
   int step   = btnH + OCA_SpacingY;

   // Y座標はコーナーによって積み上げ方向が変わるため、ボタン5+ラベル3を下から積む想定
   // 右下/左下コーナー: Y値が大きいほど上に積まれる
   // 右上/左上コーナー: Y値が大きいほど下に積まれる
   // シンプルに上から順に並べる(どのコーナーでも上下反転せず同じレイアウト)

   int x = margin;
   int y = margin;

   OCA_CreateLabel(g_lblTitle, x, y, "=== 一括決済 ===", OCA_ColorTitle);
   y += step;

   OCA_CreateLabel(g_lblStatus1, x, y, "", OCA_ColorStatus);
   y += step;

   OCA_CreateLabel(g_lblStatus2, x, y, "", OCA_ColorStatus);
   y += step + 2;

   OCA_CreateButton(g_btnAll,    x, y, btnW, btnH, "全決済",        clrWhite, clrCrimson);      y += step;
   OCA_CreateButton(g_btnBuy,    x, y, btnW, btnH, "買いのみ決済",   clrWhite, clrRoyalBlue);    y += step;
   OCA_CreateButton(g_btnSell,   x, y, btnW, btnH, "売りのみ決済",   clrWhite, clrDarkOrange);   y += step;
   OCA_CreateButton(g_btnProfit, x, y, btnW, btnH, "利益ポジ決済",   clrBlack, clrLimeGreen);    y += step;
   OCA_CreateButton(g_btnLoss,   x, y, btnW, btnH, "損失ポジ決済",   clrWhite, clrMaroon);
  }

//=======================================================================
//  MQL4 必須コールバック
//=======================================================================
int OnInit()
  {
   OCA_BuildPanel();
   OCA_UpdateStatus();

   PrintFormat("[OCA] 起動完了 symbol_only=%s magic=%d confirm=%s",
               OCA_CurrentSymbolOnly ? "true" : "false",
               OCA_FilterMagic,
               OCA_ConfirmBeforeClose ? "true" : "false");
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   OCA_DeleteAll();
   ChartRedraw(0);
   PrintFormat("[OCA] 終了 reason=%d", reason);
  }

void OnTick()
  {
   OCA_UpdateStatus();
  }

//+------------------------------------------------------------------+
//| ボタンクリックイベント                                            |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long   &lparam,
                  const double &dparam,
                  const string &sparam)
  {
   if(id != CHARTEVENT_OBJECT_CLICK) return;

   ENUM_OCA_CLOSE_MODE mode = OCA_CLOSE_ALL;
   bool handled = true;

   if(sparam == g_btnAll)         mode = OCA_CLOSE_ALL;
   else if(sparam == g_btnBuy)    mode = OCA_CLOSE_BUY_ONLY;
   else if(sparam == g_btnSell)   mode = OCA_CLOSE_SELL_ONLY;
   else if(sparam == g_btnProfit) mode = OCA_CLOSE_PROFIT;
   else if(sparam == g_btnLoss)   mode = OCA_CLOSE_LOSS;
   else handled = false;

   if(!handled) return;

   // ボタン状態を戻す
   ObjectSetInteger(0, sparam, OBJPROP_STATE, false);

   OCA_ExecuteClose(mode);
   OCA_UpdateStatus();
  }
//+------------------------------------------------------------------+
