# 🌈 Rainbow Project — FX初心者お守りツールパック

FX初心者が遠回りしないための「お守りツール」を無料配布する静的サイトです。
GitHub Pages でホストし、zip配布は GitHub Releases を利用します。

**配布ページ(本番):** `https://masato-collab.github.io/rainbow-fxkit/`

---

## ✨ プロジェクトの想い

小学校までしか学校に行けなかったシングルマザーが、FXで人生を立て直した経験から、
「もっと早く知りたかったこと」「誰かが教えてくれたら救われたこと」を
10の小さなツールに込めてお届けします。

虹の7色のように、たくさんの可能性を一人でも多くの方に。

---

## 📦 収録ツール（全10種）

| # | カラー | ツール名 | 種別 |
|:-:|:-:|:--|:--|
| 01 | 🔴 コーラル | JPTime_MarketClock | インジケーター |
| 02 | 🟠 オレンジ | RoundNumber_Alert | インジケーター |
| 03 | 🟡 イエロー | EconomicCalendar_Countdown | インジケーター |
| 04 | 🟢 ライトグリーン | LotCalculator_Panel | ユーティリティEA |
| 05 | 🟢 ミント | CorrelationMatrix_Monitor | インジケーター |
| 06 | 🔵 スカイブルー | VisualSLTP_Tool | ユーティリティEA |
| 07 | 🔵 ブルー | OneClick_CloseAll | ユーティリティEA |
| 08 | 🟣 パープル | PositionSize_Warning | EA |
| 09 | 🟣 ピンクパープル | MultiTF_TrendPanel | インジケーター |
| 10 | 🌸 ローズ | CurrencyStrength_Meter | インジケーター |

---

## 🗂️ ディレクトリ構造

```
rainbow-fxkit/
├─ index.html              # メイン配布ページ
├─ about.html              # プロジェクトについて
├─ disclaimer.html         # 免責事項
├─ 404.html
├─ docs/                   # 仕様書ページ
│  ├─ index.html
│  └─ tool-01-jptime.html 〜 tool-10-strength.html
├─ assets/                 # ロゴ・画像
│  ├─ logo.svg
│  ├─ favicon.svg
│  └─ og-image.svg
├─ css/style.css
├─ js/script.js
├─ README.md
└─ .gitignore
```

---

## 🚀 ローカルで確認する

```bash
cd rainbow-fxkit
python3 -m http.server 8000
# → http://localhost:8000 を開く
```

依存は Google Fonts のみ。ビルド不要の Vanilla HTML/CSS/JS です。

---

## 📥 ダウンロードリンクの仕組み

各zipは GitHub Releases の `latest` タグから配布します。
リンク形式:

```
https://github.com/masato-collab/rainbow-fxkit/releases/latest/download/{filename}.zip
```

`/latest/` を使っているため、新バージョンをリリースしてもサイト側のリンク修正は不要です。

### Releases へのアップロード手順

1. GitHubリポジトリの `Releases` → `Draft a new release`
2. タグを作成（例: `v1.0.0`）
3. 以下11ファイルをアップロード:
   - `FXKit_All.zip`（全部入り）
   - `JPTime_MarketClock.zip`
   - `RoundNumber_Alert.zip`
   - `EconomicCalendar_Countdown.zip`
   - `LotCalculator_Panel.zip`
   - `CorrelationMatrix_Monitor.zip`
   - `VisualSLTP_Tool.zip`
   - `OneClick_CloseAll.zip`
   - `PositionSize_Warning.zip`
   - `MultiTF_TrendPanel.zip`
   - `CurrencyStrength_Meter.zip`
4. `Publish release`

---

## 🌐 GitHub Pages の有効化

1. リポジトリの `Settings` → `Pages`
2. `Source` で `Deploy from a branch` を選択
3. `Branch` を `main` / `(root)` に設定して `Save`
4. 数分後に `https://masato-collab.github.io/rainbow-fxkit/` で公開される

---

## 🔧 GitHub ID の一括置換

公開前に、サイト内プレースホルダー `masato-collab` を実アカウント名に置換してください。

```bash
# macOS / Linux
grep -rl 'masato-collab' . | xargs sed -i '' 's/masato-collab/your-actual-id/g'

# Windows (PowerShell)
Get-ChildItem -Recurse -File | ForEach-Object {
  (Get-Content $_.FullName) -replace 'masato-collab','your-actual-id' | Set-Content $_.FullName
}
```

---

## ⚠️ 免責事項

本ツールはあくまでトレード補助を目的とした無償ツールです。
ツール使用による投資判断・損益は全て利用者の自己責任となります。
詳細は `disclaimer.html` をご確認ください。

---

## 📄 ライセンス

個人利用・商用利用・改変・再配布いずれも自由です。
著作権表示の削除のみご遠慮ください。

---

© Rainbow Project. All rights reserved.
