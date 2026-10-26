[English](EXTENDING.md) | **日本語**

# Tessa を拡張する

Tessa はプラグイン VM や JavaScript 設定ランタイムを意図的に持っていません。
拡張はコンポジタの Unix ソケット API を話す通常のプロセスです。コアを小さく
保ち、任意の言語で拡張でき、信頼できないコードをコンポジタ本体へ読み込まずに
済みます。

ソケットは `$XDG_RUNTIME_DIR` 以下（通常 `tessa.sock`）にモード `0600` で
作成されます。同じユーザーは、ターミナルで実行するのと同じ権限で API から
コマンドを実行できます。

![外部ステータスとカスタムランチャー項目](images/extensions.png)

## tessa-ctl

`tessa-ctl` はリファレンス実装のクライアントで、`tessa` と `tessa-panel` と
同じ場所にインストールされます。

```sh
tessa-ctl state                         # スナップショットを 1 回表示
tessa-ctl config                        # 実効設定とルールを表示
tessa-ctl events                        # 全イベントを購読
tessa-ctl events window-focus           # 1 トピックだけ購読
tessa-ctl workspace 3                   # フォーカス中の出力
tessa-ctl workspace 3 HEADLESS-2        # 出力を指定
tessa-ctl spawn foot -T notes
tessa-ctl launcher fire                 # クエリは省略可能
tessa-ctl layout grid                   # 現在のワークスペースのレイアウトを設定/巡回
tessa-ctl resize 40 30                  # フォーカス中のフローティングウィンドウを拡大
tessa-ctl dispatch reload               # 任意のコンポジタコマンド
tessa-ctl quit
```

`dispatch` は先頭に `CMD` を付け、残りをコンポジタコマンドとして送ります。
ソケットパスは `$TESSA_IPC`、なければ
`$XDG_RUNTIME_DIR/tessa.sock` です。

## 状態と購読

接続直後は何も送られません。パネルは次のように購読します。

```text
CMD subscribe all
```

その他のクライアントは用途に応じて選べます。

```text
CMD subscribe state     # スナップショットのみ
CMD subscribe events    # イベントのみ
CMD state               # 購読せずスナップショットを要求
```

スナップショットは行指向で、`END` で終わります。`STATE` から新しい
スナップショットが始まり、パネルは毎回バー全体を再構築します。`CONFIG` は
`tessa-ctl config` が使う別の要求/応答スナップショットで、実効設定、各
ワークスペースの `layout_ws`/`workspace_tuning` 行、`rule <raw>` 行を
含みます。主な状態行:

```text
OUT HEADLESS-1 3 1 grid
FOCUSED 7
STATUS	weather	Tokyo 18C	
WIN	7	3	1	0	0	foot	notes	HEADLESS-1	40	30	1100	700
```

`OUT` は `名前 ワークスペース フォーカス レイアウト` です。`WIN` はタブ区切りで、
id、ワークスペース、フォーカス、フローティング、フルスクリーン、エスケープ
された app_id、タイトル、出力名、x、y、幅、高さです。座標とサイズは
コンポジタの論理座標で、ウィンドウを追跡するツール向けに含まれます。
`STATUS` は後述します。

## イベント

イベントは key/value のレコードです。フィールドはタブ区切りで、値は
バックスラッシュ、タブ、改行、CR をエスケープします。最初の 2 フィールドは
必ず `EVENT` とトピック名です。

```text
EVENT	window-focus	id=7	previous=0	ws=3	app=foot	title=notes	output=HEADLESS-1
EVENT	workspace-change	ws=4	previous-ws=3	output=HEADLESS-1
EVENT	launcher	arg=fire	output=HEADLESS-1
```

該当しないフィールドは省略されます。`id` / `previous` はウィンドウ ID、
`ws` / `previous-ws` はワークスペース番号、`app`、`title`、`output`、`arg`
は文字列です。`window-focus` の `id=0` はフォーカス解除を意味し、`previous`
にはフォーカスを失ったウィンドウが入ります。

| トピック | タイミング | 主なフィールド |
| --- | --- | --- |
| `startup` | バックエンド起動・XWayland 起動後 | — |
| `shutdown` | イベントループ終了前 | — |
| `window-open` | トップレベルがマップされた | id, ws, app, title, output |
| `window-close` | マップ済みトップレベルが破棄された | id, ws, app, title, output |
| `window-focus` | ウィンドウフォーカス変更/解除 | id, previous, ws, app, title, output |
| `workspace-change` | 出力のワークスペース変更 | ws, previous-ws, output |
| `window-moved` | ウィンドウを別ワークスペースへ移動 | id, ws, previous-ws, app, title, output |
| `layout-change` | ワークスペースのレイアウト変更 | ws, output, arg |
| `config-reload` | 設定の再読み込み成功 | — |
| `launcher` | ランチャー要求 | arg（クエリ）, output |
| `output-added` | 出力初期化 | output, arg（ジオメトリ） |
| `output-removed` | 出力削除 | output, arg（ジオメトリ） |

イベントは `CMD subscribe events` または `CMD subscribe all` で購読した
クライアントにだけ届きます。ベストエフォート配信です。読み取りが遅れて
ソケットバッファが埋まったクライアントは、コンポジタをブロックせず切断
されます。

## フック

任意のイベントからシェルコマンドを起動できます。同じイベントに複数のフックを
登録できます。

```ini
startup = fcitx5 -d
hook = window-open notify-send "Window opened" "$TESSA_TITLE"
hook = workspace-change ~/.config/tessa/workspace.sh
hook = config-reload ~/.config/tessa/reload-shell.sh
```

フックプロセスはコンポジタの環境（`TESSA_IPC`、`WAYLAND_DISPLAY`、
XWayland 有効時の `DISPLAY` など）を継承し、さらに次を受け取ります。

| 変数 | 意味 |
| --- | --- |
| `TESSA_EVENT` | トピック名 |
| `TESSA_WINDOW_ID` | `id` フィールド |
| `TESSA_PREVIOUS_ID` | `previous` フィールド |
| `TESSA_WORKSPACE` | `ws` フィールド |
| `TESSA_PREVIOUS_WORKSPACE` | `previous-ws` フィールド |
| `TESSA_APP_ID` | `app` フィールド |
| `TESSA_TITLE` | `title` フィールド |
| `TESSA_OUTPUT` | `output` フィールド |
| `TESSA_ARG` | `arg` フィールド |
| `TESSA_FOCUSED_ID` | 現在のフォーカス ID（なければ `0`） |
| `TESSA_ACTIVE_WORKSPACE` | フォーカス出力のアクティブワークスペース |
| `TESSA_FOCUSED_OUTPUT` | フォーカス出力名 |

フックは投げっぱなしで並行に実行されます。順序保証はなく、フックが状態を
変えると次のイベントを発生させることがあります。コマンドはセッション
ユーザーの全権限を持ちます。

## ステータスエントリ

プロセスはバーへ短いテキストを公開できます。

```sh
tessa-ctl status weather "Tokyo 18C"
tessa-ctl status weather "Tokyo 18C" --exec "weather-app"
tessa-ctl status weather --clear
```

id は安定しており、同じ id を更新すると位置を変えずにテキストだけが
置き換わります。エントリは全出力で共有されます。最大 8 件で、満杯の状態で
新しい id が来ると最も古いものが追い出されます。テキストは 159 バイトまで
保存され、表示時には幅に合わせて切り詰められます。クリックコマンドを指定
すると、そのエントリのクリックで `CMD spawn <コマンド>` がコンポジタへ
送られます。id だけ指定して空文字にすると削除されます。

意図的にテキスト専用 API であり、画像/アイコンのプロトコルではありません。
拡張はタイマーまたはイベントに応じてテキストを更新します。

## 外部レイアウトヘルパー

独自のタイルアルゴリズムには `layout = custom` と `layout_helper` を設定します。
Tessa はヘルパープロセスを保持し、使用可能領域、ウィンドウ ID、app-id/
タイトルと、返されたフレーム矩形をタブ区切りで交換します。プロトコル全体、
タイムアウト、フォールバックの仕様は
[CUSTOMIZATION.ja.md](CUSTOMIZATION.ja.md#外部レイアウトヘルパー) にあります。

## ランチャー項目と include

パネルのランチャーは通常の `.desktop` ファイルを走査します。加えて、設定から
直接コマンドを追加できます。

```ini
launcher_entry = Notes | foot -e nvim ~/notes.md
launcher_entry = Lock screen | swaylock
```

名前は通常のランチャー検索の対象になり、`|` の後ろのコマンドが `/bin/sh`
経由で実行されます。コンポジタが `config-reload` を発行するとパネルも設定を
読み直すため、`Super+R` で両方が更新されます。

設定ファイルは別ファイルを include できます。

```ini
include = /home/you/.config/tessa/keybindings.conf
include = /home/you/.config/tessa/launcher-entries.conf
```

相対パスは include 元のファイルの隣として解決されます。include の深さは
8 段までです。循環 include を作らないでください。

## サンプル

[`examples/active-window.sh`](../examples/active-window.sh) は
`window-focus` を購読し、フォーカス中のタイトルを `active` ステータスとして
表示します。Tessa 内で起動したターミナルから実行してください。

```sh
sh examples/active-window.sh
```

## 拡張のテスト

リポジトリには自己完結した headless テストがあります。

```sh
./scripts/build.sh
sh tests/smoke.sh
```

設定 include、startup / workspace-change / config-reload フック、イベント
ストリーム、ステータスの設定と削除、IPC の半クローズ処理、`foot` が
インストールされていればウィンドウの生成・フォーカス・終了イベントを確認
します。`TESSA_CTL_DEBUG=1 tessa-ctl events` は受信行を stderr に表示します。

## 現在の制限

プロトコルは行ベースで、まだ JSON ではありません。明示的なプロトコル
バージョン、拡張間の順序制御、サンドボックス、投げっぱなしコマンドの ACK は
ありません。ステータスはテキストのみです。将来のリリースで JSON フレーミング
とバージョニングを追加しても、スクリプトによる拡張モデルは維持できます。
