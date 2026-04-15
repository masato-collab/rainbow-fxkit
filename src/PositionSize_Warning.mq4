//+------------------------------------------------------------------+
//|  PositionSize_Warning.mq4                                        |
//|  新規ポジション検知時のリスクチェック警告EA                       |
//|  機能: リスク額/残高比率チェック、SL未設定警告、                   |
//|        レバレッジ警告、CSV警告ログ記録                            |
//+------------------------------------------------------------------+
#property strict
#property copyright "Risk Warning EA"
#property version   "1.03"
#property description "新規エントリー時のリスク管理警告ツール"

//--- 警告レベルのしきい値（残高に対する割合 %）
input double PSW_Level1_Pct    = 2.0;   // レベル1(注意/黄)  : 残高の何%超えたら警告
input double PSW_Level2_Pct    = 5.0;   // レベル2(警告/橙)  : 残高の何%超えたら警告
input double PSW_Level3_Pct    = 10.0;  // レベル3(危険/赤)  : 残高の何%超えたら警告

//--- レバレッジ警告のしきい値
input double PSW_MaxLeverage   = 10.0;  // 口座全体の有効レバレッジがこの倍率を超えたら警告

//--- チャート上テキスト表示の設定
input int    PSW_TextDuration  = 30;    // チャート上の警告テキストを表示し続ける秒数
input int    PSW_TextFontSize  = 14;    // 警告テキストのフォントサイズ

//--- CSVログ設定
input string PSW_LogFileName   = "PositionSize_Warning_Log.csv"; // ログファイル名

//--- オブジェクト名プレフィックス（チャートオブジェクト重複防止）
#define PSW_PREFIX "PSW_"

//--- 内部変数
int    g_lastOrderCount = 0;   // 前回のポジション数（増加を検知するため）
string g_warnObjName    = PSW_PREFIX + "WarnText"; // チャートオブジェクト名
datetime g_warnShowTime = 0;   // 警告テキストの表示開始時刻
bool   g_logInitialized = false; // CSVログの初期化フラグ

//+------------------------------------------------------------------+
//| EA初期化                                                          |
//+------------------------------------------------------------------+
int OnInit()
  {
   // 起動時のポジション数を記録
   g_lastOrderCount = CountOpenPositions();

   // CSVログファイルの初期化（ヘッダー書き込み）
   InitLogFile();

   Print("[PSW] PositionSize_Warning EA 起動完了。監視開始。");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| EA終了処理                                                        |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   // チャート上の警告オブジェクトを削除
   DeleteWarnObject();
   Print("[PSW] PositionSize_Warning EA 停止。");
  }

//+------------------------------------------------------------------+
//| ティック処理（メインループ）                                      |
//+------------------------------------------------------------------+
void OnTick()
  {
   // ===== 新規ポジション検知 =====
   int currentCount = CountOpenPositions();

   if(currentCount > g_lastOrderCount)
     {
      // ポジションが増加した → 新規エントリーが発生した
      int newCount = currentCount - g_lastOrderCount;
      Print("[PSW] 新規ポジション検知: ", newCount, "件増加");

      // 最新のポジション(最後にOpenされたもの)を対象にリスクチェック
      CheckLatestPositionRisk();
     }

   g_lastOrderCount = currentCount;

   // ===== 口座全体のレバレッジチェック =====
   CheckAccountLeverage();

   // ===== 警告テキストの自動消去 =====
   if(g_warnShowTime > 0 && TimeCurrent() - g_warnShowTime >= PSW_TextDuration)
     {
      DeleteWarnObject();
      g_warnShowTime = 0;
      ChartRedraw();
     }
  }

//+------------------------------------------------------------------+
//| 現在のオープンポジション数を返す                                  |
//+------------------------------------------------------------------+
int CountOpenPositions()
  {
   int count = 0;
   for(int i = 0; i < OrdersTotal(); i++)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         // ポジション(BUY/SELL)のみカウント。保留中注文は除外
         if(OrderType() == OP_BUY || OrderType() == OP_SELL)
            count++;
        }
     }
   return(count);
  }

//+------------------------------------------------------------------+
//| 最新のポジションに対してリスクチェックを行う                      |
//+------------------------------------------------------------------+
void CheckLatestPositionRisk()
  {
   double balance     = AccountBalance(); // 口座残高
   double latestOpenTime = 0;
   int    targetTicket = -1;

   // 最も直近にオープンされたポジションを探す
   for(int i = 0; i < OrdersTotal(); i++)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         if(OrderType() == OP_BUY || OrderType() == OP_SELL)
           {
            if((double)OrderOpenTime() >= latestOpenTime)
              {
               latestOpenTime = (double)OrderOpenTime();
               targetTicket   = OrderTicket();
              }
           }
        }
     }

   if(targetTicket < 0)
     {
      Print("[PSW] リスクチェック対象ポジションが見つかりません。");
      return;
     }

   // 対象ポジションを選択してリスク計算
   if(!OrderSelect(targetTicket, SELECT_BY_TICKET, MODE_TRADES))
     {
      int err = GetLastError();
      Print("[PSW] OrderSelect エラー: ", err);
      return;
     }

   double lots       = OrderLots();
   double openPrice  = OrderOpenPrice();
   double slPrice    = OrderStopLoss();
   string sym        = OrderSymbol();
   int    orderType  = OrderType();
   int    ticket     = OrderTicket();

   // --- SL未設定チェック ---
   if(slPrice == 0.0)
     {
      string slMsg = StringFormat(
         "【SL未設定】%s (#%d) SL未指定",
         sym, ticket
      );
      ShowChartWarning(slMsg, clrOrange, "SL_WARN");
      Alert(slMsg);
      PlaySound("alert.wav");
      WriteLog("SL未設定警告", sym, ticket, lots, 0.0, 0.0, slMsg);
      Print("[PSW] ", slMsg);
     }

   // --- リスク額の計算 ---
   double riskAmount = 0.0;

   if(slPrice > 0.0)
     {
      // SLが設定されている場合: ロット × SL幅(pips) × pip値 でリスク額を計算
      double slPips    = 0.0;
      double point     = MarketInfo(sym, MODE_POINT);
      double tickValue = MarketInfo(sym, MODE_TICKVALUE); // 1 tick あたりの損益金額
      double tickSize  = MarketInfo(sym, MODE_TICKSIZE);  // 最小価格変動幅

      if(orderType == OP_BUY)
         slPips = (openPrice - slPrice) / point;
      else
         slPips = (slPrice - openPrice) / point;

      if(slPips < 0) slPips = 0; // 逆方向SL（念のため）

      // リスク額 = ロット数 × ロットサイズ(通貨単位) × SL幅 × pip値 / tickSize
      double lotSize = MarketInfo(sym, MODE_LOTSIZE); // 通常 100,000
      riskAmount = lots * (slPips * point / tickSize) * tickValue * lotSize / lotSize;
      // 簡略版: tick単位での損失 = スプレッド幅(ticks) × tickValue × lots
      riskAmount = lots * (slPips * point / tickSize) * tickValue;
     }
   else
     {
      // SL未設定の場合: 証拠金をリスク額の代替として使用（最悪ケース推定）
      // MQL4では MarketInfo(MODE_MARGINREQUIRED) で1ロットあたりの必要証拠金を取得
      double marginPerLot = MarketInfo(sym, MODE_MARGINREQUIRED);
      double margin       = marginPerLot * lots;
      if(margin <= 0.0)
         margin = AccountMargin(); // 取得失敗時は口座全体の使用証拠金を代用
      riskAmount = margin;
     }

   // --- 残高比率の計算 ---
   double riskPct = 0.0;
   if(balance > 0.0)
      riskPct = (riskAmount / balance) * 100.0;

   // --- 警告レベル判定と通知 ---
   string warnMsg = "";
   color  warnColor = clrWhite;
   int    warnLevel = 0;

   if(riskPct > PSW_Level3_Pct)
     {
      warnLevel = 3;
      warnColor = clrRed;
      warnMsg = StringFormat(
         "【危険】%s %.2flot 残高比%.1f%% (#%d)",
         sym, lots, riskPct, ticket
      );
     }
   else if(riskPct > PSW_Level2_Pct)
     {
      warnLevel = 2;
      warnColor = clrOrange;
      warnMsg = StringFormat(
         "【警告】%s %.2flot 残高比%.1f%% (#%d)",
         sym, lots, riskPct, ticket
      );
     }
   else if(riskPct > PSW_Level1_Pct)
     {
      warnLevel = 1;
      warnColor = clrYellow;
      warnMsg = StringFormat(
         "【注意】%s %.2flot 残高比%.1f%% (#%d)",
         sym, lots, riskPct, ticket
      );
     }

   if(warnLevel > 0)
     {
      // チャートテキスト表示
      ShowChartWarning(warnMsg, warnColor, "RISK_WARN");

      // ポップアップアラート
      Alert(warnMsg);

      // レベル別音声アラート
      switch(warnLevel)
        {
         case 1: PlaySound("alert.wav");  break; // 注意: 標準アラート音
         case 2: PlaySound("alert2.wav"); break; // 警告: やや強い音
         case 3: PlaySound("stops.wav");  break; // 危険: 最も強い音
        }

      // CSVログ記録
      WriteLog(
         StringFormat("リスク警告Lv%d", warnLevel),
         sym, ticket, lots, riskAmount, riskPct, warnMsg
      );

      Print("[PSW] ", warnMsg);
     }
   else
     {
      Print(StringFormat(
         "[PSW] チケット#%d %s リスク比率:%.1f%% — 警告なし",
         ticket, sym, riskPct
      ));
     }
  }

//+------------------------------------------------------------------+
//| 口座全体の有効レバレッジをチェックする                            |
//+------------------------------------------------------------------+
void CheckAccountLeverage()
  {
   double balance  = AccountBalance();
   double equity   = AccountEquity();
   double margin   = AccountMargin(); // 現在使用中の証拠金合計

   if(balance <= 0.0 || margin <= 0.0) return;

   // 有効レバレッジ = 保有ポジションの想定元本合計 / 純資産(Equity)
   // 近似値: 使用証拠金 × 口座レバレッジ / Equity
   int    acctLeverage    = (int)AccountInfoInteger(ACCOUNT_LEVERAGE);
   double positionNotional = margin * acctLeverage; // 想定元本合計(近似)
   double effectiveLeverage = 0.0;

   if(equity > 0.0)
      effectiveLeverage = positionNotional / equity;

   if(effectiveLeverage > PSW_MaxLeverage)
     {
      string levMsg = StringFormat(
         "【レバ警告】有効レバ%.1f倍 (上限%.1f倍)",
         effectiveLeverage, PSW_MaxLeverage
      );

      // 同じ警告を連続で出さないよう、チャートオブジェクトが既存でなければ表示
      if(ObjectFind(0, PSW_PREFIX + "LEV_WARN") < 0)
        {
         ShowChartWarning(levMsg, clrMagenta, "LEV_WARN");
         Alert(levMsg);
         PlaySound("alert2.wav");
         WriteLog("レバレッジ警告", AccountCurrency(), 0, 0.0, 0.0, effectiveLeverage, levMsg);
         Print("[PSW] ", levMsg);
        }
     }
   else
     {
      // レバレッジが正常範囲に戻ったらオブジェクト削除
      if(ObjectFind(0, PSW_PREFIX + "LEV_WARN") >= 0)
         ObjectDelete(0, PSW_PREFIX + "LEV_WARN");
     }
  }

//+------------------------------------------------------------------+
//| チャート上に警告テキストを表示する                                |
//| objSuffix: オブジェクト名のサフィックス("RISK_WARN"等)           |
//+------------------------------------------------------------------+
void ShowChartWarning(string message, color textColor, string objSuffix)
  {
   string objName = PSW_PREFIX + objSuffix;

   // 種別ごとにY座標をズラす(重なり防止)
   int yPos = 50;
   if(objSuffix == "RISK_WARN") yPos = 50;
   else if(objSuffix == "SL_WARN")  yPos = 50 + (PSW_TextFontSize * 2 + 8);
   else if(objSuffix == "LEV_WARN") yPos = 50 + (PSW_TextFontSize * 2 + 8) * 2;

   // 既存オブジェクトがあれば削除して再作成
   if(ObjectFind(0, objName) >= 0)
      ObjectDelete(0, objName);

   // テキストオブジェクト作成
   if(!ObjectCreate(0, objName, OBJ_LABEL, 0, 0, 0))
     {
      int err = GetLastError();
      Print("[PSW] ObjectCreate エラー: ", err);
      return;
     }

   ObjectSetInteger(0, objName, OBJPROP_CORNER,    CORNER_LEFT_UPPER); // 左上基準
   ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, 20);                // 左端から20px
   ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, yPos);              // 種別ごとに異なるY位置
   ObjectSetInteger(0, objName, OBJPROP_COLOR,     textColor);
   ObjectSetInteger(0, objName, OBJPROP_FONTSIZE,  PSW_TextFontSize);
   ObjectSetString( 0, objName, OBJPROP_FONT,      "MS ゴシック");
   ObjectSetString( 0, objName, OBJPROP_TEXT,      message);
   ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);

   g_warnShowTime = TimeCurrent();
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| チャート上の警告テキストオブジェクトを削除する                    |
//+------------------------------------------------------------------+
void DeleteWarnObject()
  {
   // RISK_WARN, SL_WARN, LEV_WARN 各オブジェクトを削除
   string suffixes[] = {"RISK_WARN", "SL_WARN", "LEV_WARN"};
   for(int i = 0; i < ArraySize(suffixes); i++)
     {
      string objName = PSW_PREFIX + suffixes[i];
      if(ObjectFind(0, objName) >= 0)
         ObjectDelete(0, objName);
     }
  }

//+------------------------------------------------------------------+
//| CSVログファイルを初期化する（ヘッダー行を書き込む）              |
//+------------------------------------------------------------------+
void InitLogFile()
  {
   // ログファイルが存在しない場合のみヘッダーを書き込む
   int handle = FileOpen(PSW_LogFileName, FILE_READ | FILE_CSV);
   if(handle == INVALID_HANDLE)
     {
      // ファイルが存在しない → 新規作成してヘッダーを書く
      handle = FileOpen(PSW_LogFileName, FILE_WRITE | FILE_CSV | FILE_ANSI);
      if(handle == INVALID_HANDLE)
        {
         int err = GetLastError();
         Print("[PSW] ログファイル作成エラー: ", err);
         return;
        }
      // CSVヘッダー
      FileWrite(handle,
         "日時",
         "警告種別",
         "通貨ペア",
         "チケット番号",
         "ロット数",
         "リスク額",
         "残高比率(%)",
         "メッセージ"
      );
      FileClose(handle);
      g_logInitialized = true;
      Print("[PSW] ログファイルを新規作成しました: ", PSW_LogFileName);
     }
   else
     {
      FileClose(handle);
      g_logInitialized = true;
      Print("[PSW] 既存ログファイルに追記します: ", PSW_LogFileName);
     }
  }

//+------------------------------------------------------------------+
//| 警告内容をCSVファイルに追記する                                   |
//+------------------------------------------------------------------+
void WriteLog(string warnType, string symbol, int ticket,
              double lots, double riskAmount, double riskPct,
              string message)
  {
   if(!g_logInitialized) return;

   int handle = FileOpen(PSW_LogFileName, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(handle == INVALID_HANDLE)
     {
      int err = GetLastError();
      Print("[PSW] ログファイルオープンエラー: ", err);
      return;
     }

   // ファイル末尾に移動して追記
   FileSeek(handle, 0, SEEK_END);

   string dt = TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES | TIME_SECONDS);

   FileWrite(handle,
      dt,
      warnType,
      symbol,
      (ticket > 0 ? IntegerToString(ticket) : "-"),
      (lots > 0.0 ? DoubleToString(lots, 2) : "-"),
      (riskAmount > 0.0 ? DoubleToString(riskAmount, 2) : "-"),
      (riskPct > 0.0 ? DoubleToString(riskPct, 2) : "-"),
      message
   );

   FileClose(handle);
  }

//+------------------------------------------------------------------+
//| EOF                                                               |
//+------------------------------------------------------------------+
