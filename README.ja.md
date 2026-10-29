# Kado

Mac の画面の角に常駐する、小さなチャットです。丸いボタン（バブル）を押すか `⌃⌥M` で開き、ちょっとした質問をして答えをもらったら、すぐ作業に戻れます。

Kado は、すでに入れている [Claude Code](https://code.claude.com) を裏で使います。APIキーは要らず、あなたの Claude のサブスクで動きます。

![Kado](docs/screenshot.png)

[English](README.md)

> **Kado は個人のプロジェクトです。Anthropic が作ったものではなく、Anthropic と提携も承認もしていません。**「Claude」と「Claude Code」は Anthropic の商標です。

## 必要なもの

- macOS 14 以降
- [Claude Code](https://code.claude.com/docs/ja/setup) を入れて、Claude Code が使えるプラン（Pro・Max・Team・Enterprise）でログインしていること。無料プランでは Claude Code は使えません（[Claude の料金](https://claude.com/pricing)）
- ソースからビルドするための Swift 6（Xcode またはコマンドラインツール）

## 入れ方

1. Claude Code にログインしておく（まだなら一度だけ）

   ```bash
   claude auth login
   ```

2. ビルドして入れる（`~/Applications/Kado.app` に入り、起動します）

   ```bash
   git clone https://github.com/roadleon/kado.git
   cd kado
   ./build.sh install
   ```

3. 毎回自動で起動したいときは、バブルを右クリックして「ログイン時に起動」をオンにする

## 使い方

| 操作 | 方法 |
|---|---|
| 開く／閉じる | バブルをクリック、または `⌃⌥M` |
| 閉じる | `Esc` または `⌘W` |
| 送信／改行 | `Enter`／`Shift + Enter`（日本語の変換中の Enter では送信しません） |
| 新しい会話 | 見出しのペンのボタン、または `⌘N` |
| 画像を添付する | `⌘V` で貼り付け、チャット窓にドラッグ＆ドロップ、または撮影ボタン（カメラの記号）で画面の一部を撮る。1回の質問に4枚まで |
| 回答を止める | 回答中は送信ボタンが止めるボタンに変わります |
| モデルを変える | 見出しのモデル名を押して選ぶ（会話は新しくなります） |
| バブルを動かす | ドラッグ。位置は覚えます |
| メニュー（モデル・ログイン時に起動・終了など） | バブルを右クリック、またはメニューバーのアイコン |
| バブルを消してしまったとき | Spotlight や Finder から Kado をもう一度開くと戻ります |

最新の情報が要る質問では、ウェブで調べてから答え、最後に出典のリンクを付けます。数秒〜20秒ほどかかります。

大きな画像は、長い辺が1568ピクセルになるまで縮めてから送ります（Claude はそれより大きい画像も内部で縮めるので、答えの質は変わりません）。画像つきの質問は、文字だけの質問より利用枠を多く使います。撮影ボタンを初めて使うとき、macOS が Kado の「画面収録」の許可を求めます。

30分使わずに窓を閉じたままにしておくと、裏の Claude Code を止めてメモリを空けます（次の質問は新しい会話になります）。

### 外からの操作

Raycast やショートカット.app から、次の URL で操作できます。

- `kado://toggle`・`kado://open`・`kado://close`
- `kado://new` 新しい会話
- `kado://ask?q=質問` 質問を入力欄に入れる（URL エンコードする）。送信はしないので、Enter を押してください。ウェブページなどから勝手に質問を送らせないためです。

## 仕組み

- `claude -p` を stream-json の入出力で起動したままにし、会話を流し込みます。2問目以降は起動待ちがありません。
- Claude Code に使わせる道具は、ウェブ検索（WebSearch）とページの読み込み（WebFetch）だけです。ファイル操作・コマンド実行、MCP、`CLAUDE.md`、フックは読み込みません。会話の記録も残しません。
- Kado は Claude のログイン情報を読みも保存もしません。ログインは Claude Code が Anthropic の手順で行い、Kado は改変していない `claude` コマンドとやりとりするだけです。
- 既定のモデルは Haiku（エフォート medium）。Sonnet・Opus はエフォート low で動きます。質問は Claude Code の利用枠を消費し、利用には [Anthropic の規約](https://code.claude.com/docs/ja/legal-and-compliance)が適用されます。
- `claude` は `~/.local/bin`・`/opt/homebrew/bin`・`/usr/local/bin` の順に探し、無ければログインシェルで探します。別の場所にあるときは次のように指定します。

  ```bash
  defaults write io.github.roadleon.kado claudePath /path/to/claude
  ```

## 名前と見た目を変える

名前・色・メニューバーの記号・アイコン・バンドルID・URL スキームは `brand/public.env` で決まります。自分用に見た目を変えたいときは、同じ項目を書いた `local/brand.env` を置いてください（`local/` は Git に載りません）。`local/brand.env` があっても公開版で作りたいときは、次のようにします。

```bash
BRAND=public ./build.sh
```

## ライセンス

[MIT](LICENSE)
