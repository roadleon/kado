# Kado 仕様

画面の角に常駐する、Mac 用の小さな Claude チャット。公開版の名前は Kado。手元の版は local/ の設定で「ミニクロ」として作る。ちょっとした質問をサクッと聞くための道具。

## 動き

- 画面の右下に丸いボタン（バブル）が常に最前面で浮かぶ。ドラッグで好きな位置へ動かせ、位置は覚える。
- バブルをクリック、または `⌃⌥M`（Control + Option + M）でチャット窓を開閉する。`Esc` で閉じる。
- メニューバーにアイコンを置く。Dock には出さない。バブルの右クリック（Control + クリック）でも同じメニューを出す（メニューバーのアイコンはカメラの切り欠きに隠れることがあるため）。
  - メニュー：開く／閉じる、新しい会話、モデル（Haiku・Sonnet・Opus）、ログイン時に起動、バブルを表示、終了
- 入力欄は Enter で送信、Shift + Enter で改行。日本語変換中の Enter では送信しない。
- 答えは流れるように表示する。Markdown（太字・リスト・見出し・コード）を整えて表示し、コードと回答にはコピーボタンを付ける。
- 回答中は「止める」ボタンで中断できる。
- 外から URL で操作できる：`kado://toggle`（スキームは brand で決まる）・`open`・`close`・`new`・`ask?q=`。`ask` は入力欄に入れるだけで、送信はしない（ウェブページなどから勝手に質問を送らせないため）。
- 30分使わずに窓を閉じたままなら、裏の claude を止めてメモリを空ける。
- 画面の文字は日本語と英語。使う人の言語設定の先頭が日本語なら日本語、それ以外は英語（`L10n`）。答えは質問と同じ言語で返す（指示文は英語）。

## Claude とのつなぎ方

- 手元の Claude Code CLI（`claude -p`）を裏で起動し、会話のあいだ起動したままにする（stream-json 入出力）。APIキーは使わず、Claude のサブスクの枠で動く。
- 起動オプション：`--model haiku --effort medium --tools WebSearch,WebFetch --allowedTools WebSearch WebFetch --strict-mcp-config --safe-mode --no-session-persistence --system-prompt ...`
  - 道具はウェブ検索（WebSearch）とページの読み込み（WebFetch）だけ。ファイル操作・コマンド実行・MCP・CLAUDE.md・フックは読み込まない。会話の記録は残さない。
  - 調べ物の質問では検索してから答え、最後に出典のリンクを付ける。検索中は「ウェブを検索しています」と表示する。
- 起動するのはアプリ専用のフォルダ（`~/Library/Application Support/<名前>`）。環境変数は最小限に絞る。
- 「新しい会話」でプロセスを作り直す。次の質問に備えて、あらかじめ起動しておく。
- `claude` の場所は `~/.local/bin`・`/opt/homebrew/bin`・`/usr/local/bin` の順に探し、無ければログインシェルで探す。
- ログインが切れているときは、`claude auth login` を案内する。

## 見た目

- 色：アクセントは brand で決める（公開版は藍 `#4C5BD4`）。背景はシステムの半透明素材で、ライト／ダークの両方に対応する。
- 文字：システムフォント 13pt。コードは等幅 12pt。
- チャット窓：幅 380 × 高さ 540、角丸 14。バブルの近くに開く。
- 絵文字は使わない。

## 名前と見た目

- 名前・色・記号・アイコン・バンドルID・URL スキームは、コードに書かず `brand/public.env` に置く。build.sh が Info.plist に書き込み、アプリは `Brand` から読む。
- `local/brand.env`（Git に載せない）があれば、そちらを使う。手元のアプリを公開版と違う見た目にするため。`BRAND=public` で公開版を強制できる。
- アイコンは tools/make_icon.swift で描く。SF Symbols はアプリのアイコンに使えない決まりなので使わない（画面の中の記号には使ってよい）。
- 公開版は Claude 公式と見分けがつく名前と色にする（「Claude」を名前に入れない、Claude のテラコッタ色を使わない）。

## ビルド

- Swift Package（Xcode プロジェクト不要）。`./build.sh` で `build/<名前>.app` を作り、`./build.sh install` で `~/Applications` に入れる。
- macOS 14 以降。
