//+------------------------------------------------------------------+
//|  RoundNumber_Alert.mq4                                           |
//|  キリ番（ラウンドナンバー）接近/到達アラートインジケーター        |
//|  機能:                                                            |
//|    - 指定pips間隔のキリ番を自動計算                                |
//|    - キリ番への接近アラート（残り○pips）                          |
//|    - キリ番タッチ/ブレイク時の到達アラート                         |
//|    - チャート上に水平ラインを自動描画                              |
//|    - 同一キリ番への重複アラート抑制                                |
//|    - JPYペア/その他ペアのpip単位を自動判定（3桁/5桁ブローカー対応）|
//+------------------------------------------------------------------+
#property strict
#property copyright "RoundNumber Alert Indicator"
#property version   "1.01"
#property description "現在価格がキリ番に接近/到達したときにアラートを出すインジケーター"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

//--- キリ番の設定 ------------------------------------------------------
input double RNA_IntervalPips    = 50.0;      // キリ番の間隔（pips）例: 10/25/50/100
input double RNA_ApproachPips    = 5.0;       // 接近アラート発動距離（pips）
input int    RNA_LinesAbove      = 5;         // 現在価格から上方向に描画するキリ番の本数
input int    RNA_LinesBelow      = 5;         // 現在価格から下方向に描画するキリ番の本数

//--- アラート方法 -----------------------------------------------------
input bool   RNA_UseAlert        = true;      // ポップアップ+サウンド(Alert関数)を使用するか
input bool   RNA_UseSound        = true;      // 追加で PlaySound を使用するか
input string RNA_SoundApproach   = "alert.wav";   // 接近時のサウンドファイル
input string RNA_SoundTouch      = "alert2.wav";  // 到達時のサウンドファイル
input bool   RNA_UseMail         = false;     // メール通知を送信するか
input bool   RNA_UsePush         = false;     // プッシュ通知を送信するか

//--- ライン描画の設定 -------------------------------------------------
input color  RNA_LineColor       = clrDodgerBlue; // キリ番ラインの色
input int    RNA_LineWidth       = 1;             // キリ番ラインの太さ
input ENUM_LINE_STYLE RNA_LineStyle = STYLE_SOLID; // キリ番ラインのスタイル
input bool   RNA_ShowLabel       = true;          // ライン上に価格ラベルを表示するか
input color  RNA_LabelColor      = clrGray;       // ラベルの色
input int    RNA_LabelFontSize   = 8;             // ラベルのフォントサイズ

//--- 重複アラート抑制 -------------------------------------------------
// 接近/到達で一度鳴った後、価格が「接近距離 + この値(pips)」だけ離れたらリセットして再発動可能にする
input double RNA_ResetBufferPips = 2.0;       // アラートリセット用の追加バッファ（pips）

//--- オブジェクト名プレフィックス（他インジケーターとの重複防止）
#define RNA_PREFIX "RNA_"

//--- 内部変数 ----------------------------------------------------------
double   g_pipSize        = 0.0;   // 1pipあたりの価格値（JPYなら0.01、その他は0.0001）
double   g_intervalPrice  = 0.0;   // キリ番間隔を価格換算した値
double   g_approachPrice  = 0.0;   // 接近判定距離を価格換算した値
double   g_resetBufferPrice = 0.0; // リセットバッファを価格換算した値
int      g_priceDigits    = 5;     // 価格表示桁数

// 直近でアラート済みのキリ番価格（0 = 未発動）
// それぞれ、接近アラート(上から接近/下から接近)、到達アラート を別々に記録する
double   g_lastApproachAboveRN = 0.0; // 上方向のキリ番へ接近中に鳴らしたキリ番価格
double   g_lastApproachBelowRN = 0.0; // 下方向のキリ番へ接近中に鳴らしたキリ番価格
double   g_lastTouchRN         = 0.0; // 到達（タッチ/ブレイク）で鳴らしたキリ番価格

//+------------------------------------------------------------------+
//| pip単位の自動判定                                                |
//|   3桁/5桁ブローカー(=JPYペア3桁、その他5桁)の場合は Point*10     |
//|   2桁/4桁ブローカーの場合は Point                                |
//+------------------------------------------------------------------+
double DetectPipSize()
  {
   int digits = (int)MarketInfo(Symbol(), MODE_DIGITS);
   g_priceDigits = digits;
   if(digits == 3 || digits == 5)
      return(Point * 10.0);
   return(Point);
  }

//+------------------------------------------------------------------+
//| インジケーター初期化                                              |
//+------------------------------------------------------------------+
int OnInit()
  {
   // pip単位の自動判定
   g_pipSize = DetectPipSize();
   if(g_pipSize <= 0.0)
     {
      Print("[RNA] pipSize の判定に失敗しました。Point=", Point, " Digits=", Digits);
      return(INIT_FAILED);
     }

   // 入力値の簡易検証
   if(RNA_IntervalPips <= 0.0)
     {
      Print("[RNA] RNA_IntervalPips は正の値を指定してください。現在値=", RNA_IntervalPips);
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(RNA_ApproachPips < 0.0)
     {
      Print("[RNA] RNA_ApproachPips は0以上を指定してください。現在値=", RNA_ApproachPips);
      return(INIT_PARAMETERS_INCORRECT);
     }

   // pips→価格換算
   g_intervalPrice    = RNA_IntervalPips    * g_pipSize;
   g_approachPrice    = RNA_ApproachPips    * g_pipSize;
   g_resetBufferPrice = RNA_ResetBufferPips * g_pipSize;

   // 起動時にチャート上の古いオブジェクトを削除（プレフィックスで識別）
   RemoveAllRNAObjects();

   // 起動時点でラインを描画
   RedrawRoundNumberLines();

   PrintFormat("[RNA] 起動完了。Symbol=%s Digits=%d pipSize=%.*f Interval=%.1fpips Approach=%.1fpips",
               Symbol(), g_priceDigits, g_priceDigits, g_pipSize,
               RNA_IntervalPips, RNA_ApproachPips);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| インジケーター終了処理                                            |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   // チャートから自インジケーターが描画したオブジェクトを全て削除
   RemoveAllRNAObjects();
   Print("[RNA] 終了。チャートオブジェクトを削除しました。理由コード=", reason);
  }

//+------------------------------------------------------------------+
//| OnCalculate: ティック毎に呼ばれる                                 |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   // 現在価格（Bid基準。必要に応じて Ask/中値などに変更可能）
   double price = Bid;
   if(price <= 0.0)
      return(rates_total);

   // ラインの再描画（価格帯が大きく動いたときも追従）
   RedrawRoundNumberLines();

   // アラート判定
   CheckApproachAndTouch(price);

   return(rates_total);
  }

//+------------------------------------------------------------------+
//| 現在価格から最も近い下側のキリ番を返す                            |
//|   例: 間隔50pips, 価格1.2337 → 1.2300                            |
//+------------------------------------------------------------------+
double NearestLowerRoundNumber(double price)
  {
   if(g_intervalPrice <= 0.0)
      return(0.0);
   double n = MathFloor(price / g_intervalPrice);
   return(NormalizeDouble(n * g_intervalPrice, g_priceDigits));
  }

//+------------------------------------------------------------------+
//| キリ番ラインをチャートに描画（現在価格の上下 N 本ずつ）           |
//+------------------------------------------------------------------+
void RedrawRoundNumberLines()
  {
   double base = NearestLowerRoundNumber(Bid);
   if(base <= 0.0)
      return;

   // 描画範囲: base-LinesBelow*interval 〜 base+(LinesAbove+1)*interval
   int totalLines = RNA_LinesAbove + RNA_LinesBelow + 2;

   // 一旦既存のラインオブジェクトを削除して作り直す（軽量・確実）
   RemoveAllRNAObjects();

   for(int i = -RNA_LinesBelow; i <= RNA_LinesAbove + 1; i++)
     {
      double rn = NormalizeDouble(base + i * g_intervalPrice, g_priceDigits);
      if(rn <= 0.0) continue;

      string lineName = StringFormat("%sLINE_%s", RNA_PREFIX, DoubleToString(rn, g_priceDigits));
      if(ObjectFind(lineName) < 0)
        {
         if(!ObjectCreate(0, lineName, OBJ_HLINE, 0, 0, rn))
           {
            int err = GetLastError();
            PrintFormat("[RNA] HLINE作成失敗 name=%s err=%d", lineName, err);
            continue;
           }
        }
      ObjectSetInteger(0, lineName, OBJPROP_COLOR, RNA_LineColor);
      ObjectSetInteger(0, lineName, OBJPROP_WIDTH, RNA_LineWidth);
      ObjectSetInteger(0, lineName, OBJPROP_STYLE, RNA_LineStyle);
      ObjectSetInteger(0, lineName, OBJPROP_BACK, true);       // ローソク足より背面
      ObjectSetInteger(0, lineName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, lineName, OBJPROP_HIDDEN, true);

      // ラベル表示
      if(RNA_ShowLabel)
        {
         string labelName = StringFormat("%sLABEL_%s", RNA_PREFIX, DoubleToString(rn, g_priceDigits));
         if(ObjectFind(labelName) < 0)
           {
            if(!ObjectCreate(0, labelName, OBJ_TEXT, 0, TimeCurrent(), rn))
              {
               int err = GetLastError();
               PrintFormat("[RNA] LABEL作成失敗 name=%s err=%d", labelName, err);
               continue;
              }
           }
         ObjectSetString(0, labelName, OBJPROP_TEXT, DoubleToString(rn, g_priceDigits));
         ObjectSetInteger(0, labelName, OBJPROP_COLOR, RNA_LabelColor);
         ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, RNA_LabelFontSize);
         ObjectSetInteger(0, labelName, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, labelName, OBJPROP_HIDDEN, true);
         // テキスト位置は最新バー近くに寄せる
         ObjectSetInteger(0, labelName, OBJPROP_TIME, TimeCurrent());
         ObjectSetDouble(0, labelName, OBJPROP_PRICE, rn);
        }
     }
  }

//+------------------------------------------------------------------+
//| 接近/到達アラート判定                                             |
//+------------------------------------------------------------------+
void CheckApproachAndTouch(double price)
  {
   // 最寄りの下側/上側キリ番を計算
   double lowerRN = NearestLowerRoundNumber(price);
   double upperRN = NormalizeDouble(lowerRN + g_intervalPrice, g_priceDigits);

   // --- 接近アラート（下から上側キリ番へ接近） ---
   //     価格が upperRN - ApproachPips 以上、かつ upperRN 未満のとき発動
   double distToUpper = upperRN - price;
   if(distToUpper > 0.0 && distToUpper <= g_approachPrice)
     {
      // 同じキリ番に対して未発動ならアラート
      if(MathAbs(g_lastApproachAboveRN - upperRN) > g_pipSize * 0.5)
        {
         FireAlert(true, upperRN, distToUpper, price);
         g_lastApproachAboveRN = upperRN;
        }
     }
   else
     {
      // 接近距離＋バッファより遠く離れたらリセット
      if(g_lastApproachAboveRN > 0.0)
        {
         double resetDist = g_approachPrice + g_resetBufferPrice;
         if(MathAbs(g_lastApproachAboveRN - price) > resetDist)
            g_lastApproachAboveRN = 0.0;
        }
     }

   // --- 接近アラート（上から下側キリ番へ接近） ---
   double distToLower = price - lowerRN;
   if(distToLower >= 0.0 && distToLower <= g_approachPrice)
     {
      if(MathAbs(g_lastApproachBelowRN - lowerRN) > g_pipSize * 0.5)
        {
         FireAlert(true, lowerRN, distToLower, price);
         g_lastApproachBelowRN = lowerRN;
        }
     }
   else
     {
      if(g_lastApproachBelowRN > 0.0)
        {
         double resetDist = g_approachPrice + g_resetBufferPrice;
         if(MathAbs(price - g_lastApproachBelowRN) > resetDist)
            g_lastApproachBelowRN = 0.0;
        }
     }

   // --- 到達アラート（キリ番タッチ/ブレイク） ---
   //     価格から見て、距離が 0.5pip 未満のキリ番があれば「到達」と判定
   double touchTolerance = g_pipSize * 0.5;
   double nearestRN = (distToUpper < distToLower) ? upperRN : lowerRN;
   double nearestDist = MathMin(distToUpper, distToLower);

   if(nearestDist <= touchTolerance)
     {
      if(MathAbs(g_lastTouchRN - nearestRN) > g_pipSize * 0.5)
        {
         FireAlert(false, nearestRN, 0.0, price);
         g_lastTouchRN = nearestRN;
        }
     }
   else
     {
      if(g_lastTouchRN > 0.0)
        {
         // 価格が resetBuffer 以上離れたらリセット
         if(MathAbs(g_lastTouchRN - price) > (touchTolerance + g_resetBufferPrice))
            g_lastTouchRN = 0.0;
        }
     }
  }

//+------------------------------------------------------------------+
//| アラート発火                                                     |
//|   isApproach=true  : 接近アラート                                |
//|   isApproach=false : 到達(タッチ/ブレイク)アラート               |
//+------------------------------------------------------------------+
void FireAlert(bool isApproach, double rnPrice, double distPrice, double currentPrice)
  {
   string symbol = Symbol();
   double distPips = distPrice / g_pipSize;

   string title = isApproach ? "キリ番接近" : "キリ番到達";
   string msg;
   if(isApproach)
      msg = StringFormat("[RNA] %s %s キリ番 %.*f まで残り %.1f pips (現在値 %.*f)",
                         symbol, title, g_priceDigits, rnPrice, distPips,
                         g_priceDigits, currentPrice);
   else
      msg = StringFormat("[RNA] %s %s キリ番 %.*f をタッチ/ブレイク (現在値 %.*f)",
                         symbol, title, g_priceDigits, rnPrice,
                         g_priceDigits, currentPrice);

   // ポップアップ+サウンド
   if(RNA_UseAlert)
      Alert(msg);
   else
      Print(msg);

   // 追加サウンド
   if(RNA_UseSound)
     {
      string snd = isApproach ? RNA_SoundApproach : RNA_SoundTouch;
      if(StringLen(snd) > 0)
        {
         if(!PlaySound(snd))
           {
            int err = GetLastError();
            PrintFormat("[RNA] PlaySound失敗 file=%s err=%d", snd, err);
           }
        }
     }

   // メール通知
   if(RNA_UseMail)
     {
      if(!SendMail(title + " " + symbol, msg))
        {
         int err = GetLastError();
         PrintFormat("[RNA] SendMail失敗 err=%d", err);
        }
     }

   // プッシュ通知
   if(RNA_UsePush)
     {
      if(!SendNotification(msg))
        {
         int err = GetLastError();
         PrintFormat("[RNA] SendNotification失敗 err=%d", err);
        }
     }
  }

//+------------------------------------------------------------------+
//| 自インジケーターが作成した全オブジェクトを削除                    |
//+------------------------------------------------------------------+
void RemoveAllRNAObjects()
  {
   int total = ObjectsTotal();
   for(int i = total - 1; i >= 0; i--)
     {
      string name = ObjectName(i);
      if(StringFind(name, RNA_PREFIX) == 0)
        {
         if(!ObjectDelete(name))
           {
            int err = GetLastError();
            PrintFormat("[RNA] ObjectDelete失敗 name=%s err=%d", name, err);
           }
        }
     }
  }
//+------------------------------------------------------------------+
