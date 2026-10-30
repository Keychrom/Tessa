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
tessa-ctl hello                         # 行プロトコルのバージョン/機能一覧
tessa-ctl config                        # 実効設定とルールを表示
tessa-ctl config-check [file]           # 現在／候補設定を検証
tessa-ctl config-diff file              # 実効設定の差分をプレビュー
tessa-ctl config-edit [file]            # 編集・検証・差分・適用
tessa-ctl perf [--json] [--reset]       # 描画コミットのフレーム時間
tessa-ctl events                        # 全イベントを購読
tessa-ctl events window-focus           # 1 トピックだけ購読
tessa-ctl workspace 3                   # フォーカス中の出力
tessa-ctl workspace 3 HEADLESS-2        # 出力を指定
tessa-ctl spawn foot -T notes
tessa-ctl launcher fire                 # クエリは省略可能
tessa-ctl panel calendar                # パネルのポップオーバーを開閉
tessa-ctl panel clipboard              # クリップボード履歴
tessa-ctl panel screenshot             # 範囲/全画面スクリーンショット UI
tessa-ctl panel media                  # MPRIS メディア操作
tessa-ctl panel tray                   # StatusNotifier トレイ
tessa-ctl panel audio                  # 音量操作
tessa-ctl notify-action 12 reply       # 通知アクションを実行
tessa-ctl panel power HEADLESS-2        # 出力を指定
tessa-ctl layout grid                   # 現在のワークスペースのレイアウトを設定/巡回
tessa-ctl mode resize                   # 入力モードを切り替え
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
ワークスペースの `layout_ws`/`workspace_tuning` 行、`rule <raw>` 行、
`layer_rule <raw>` 行を含みます。主な状態行:

```text
MODE default
OUT HEADLESS-1 3 1 grid
FOCUSED 7
STATUS	weather	Tokyo 18C	
WIN	7	3	1	0	0	foot	notes	HEADLESS-1	40	30	1100	700
LAYER	tessa-bar	HEADLESS-1	2	0.940	12	1
```

`MODE` はアクティブな入力モードです。`OUT` は
`名前 ワークスペース フォーカス レイアウト` です。`WIN` はタブ区切りで、
id、ワークスペース、フォーカス、フローティング、フルスクリーン、エスケープ
された app_id、タイトル、出力名、x、y、幅、高さです。座標とサイズは
コンポジタの論理座標で、ウィンドウを追跡するツール向けに含まれます。
`LAYER` は namespace、出力名、レイヤー番号（`0` background … `3`
overlay）、実効不透明度、実効角丸、実効ブラー（`0`/`1`）です。`PANEL` は
出力名、パネル PID、監視中（`0`/`1`）、通知所有者（`0`/`1`）です。
`STATUS` は後述します。

## JSON スナップショット

ツール向けに、状態と実効設定をバージョン付き JSON でも取得できます。
テキストコマンドもそのまま使えます。

```text
CMD state-json
STATE_JSON
{"schema":1,"active_workspace":1,"mode":"default","outputs":[...],"occupancy":[...],"focused":7,"statuses":[...],"windows":[...]}
END

CMD config-json
CONFIG_JSON
{"schema":1,"errors":0,"terminal":"kitty",...,"layouts":[...],"workspace_tuning":[...],"rules":[...],"hooks":[...],"diagnostics":[]}
END
```

`tessa-ctl state --json` と `tessa-ctl config --json` は JSON 行だけを出力
します。`STATE_JSON` と `CONFIG_JSON` はフレーミング用マーカーで、JSON 本体
ではありません。状態 JSON はアクティブな `mode`、`active_workspace_name`、
9 要素の `workspace_names` 配列を、設定 JSON は `modes` 配列と同じ
`workspace_names` 配列を含みます。行プロトコルには名前付きワークスペースの
`WORKSPACE <n> <name>` 行が追加されます。`schema` は現在 `1` です。未知の
バージョンは拒否してください。

状態のウィンドウには `id`、`workspace`、`focused`、`floating`、
`fullscreen`、`urgent`、`scratchpad`、`visible`、`group`、`group_active`、
`app_id`、`title`、`output`、`x`、`y`、`width`、`height` と、実効装飾値
`opacity`、`border_width`、`corner_radius`、`blur`、`shadow` が入ります。
テキストの `WIN` 行は末尾にスクラッチパッド、可視状態、グループ ID、
グループアクティブのフラグを持ちます。`layers` 配列にはマップ済み
レイヤーサーフェスの `namespace`、`output`、`layer`、`opacity`、
`corner_radius`、`blur` が入ります。`tessa-ctl dispatch urgent <id> on|off`
でレイアウトヘルパーへ送る緊急度を切り替えられます。`CMD workspace` と
`CMD move-workspace` は数値のほかにワークスペース名も受け付けます。
グループ操作は `CMD toggle-group`、`CMD group-next`、`CMD group-prev`、
`CMD group-add`、`CMD group-remove` です。設定の
`diagnostics` は `severity`、`path`、`line`、`message` を持ちます。設定 JSON
は `event_rules`、`profiles`、`theme_roles`、`output_rules`、`layer_rules`、
`input_rules`、各件数、`cursor_theme`、`cursor_size` も出力します。ルール配列
の各要素は現在、検証済みの `raw` 文字列を含みます。`curves` の各要素は
`kind`（`bezier` または `spring`）を持ち、bezier は `points`、spring は
`damping` と `frequency` を含みます。

## JSON-RPC

同じソケットで、1 行の JSON オブジェクトによる JSON-RPC 2.0 リクエストを
受け付けます。行プロトコルも残り、同じ接続でどちらも使えます。

```json
{"jsonrpc":"2.0","id":1,"method":"hello"}
{"jsonrpc":"2.0","id":7,"method":"state"}
{"jsonrpc":"2.0","id":"cfg","method":"config"}
{"jsonrpc":"2.0","id":"sub-1","method":"subscribe"}
```

応答は `{"jsonrpc":"2.0","id":<リクエスト ID>,"result":...}` で、エラーは
標準 JSON-RPC コードです。メソッドは `hello` / `capabilities`、`ping`、
`state`、`config`、`subscribe`、`unsubscribe` です。`hello` は
`protocol: "tessa-jsonrpc"`、`version: 1`、`line_protocol: 1` と、
`state`、`config`、`events`、`subscriptions`、`request-ids` の
ケイパビリティを返します。

`subscribe` 後、ライフサイクルイベントは通知として届きます:

```json
{"jsonrpc":"2.0","method":"event","params":{"name":"window-open","id":7,"ws":1,"app":"foot","title":"notes","output":"eDP-1","subscription":"sub-1"}}
```

`subscription` はシリアライズされたリクエスト ID です。イベントはベスト
エフォートで、遅いクライアントはコンポジタを止めずに切断されます。変更操作は
引き続き行コマンドを使います。

テキストの `CMD config` にも、次の形式で診断が含まれます。

```text
diagnostic error /home/you/.config/tessa/config:12: unknown key 'widht'
```

エラーのあるリロードは拒否され、以前の設定が維持されます。
`tessa-ctl config-check` は診断を表示し、エラーが残っている間は非ゼロで
終了します。直近に読み込まれた、または拒否された設定を検査するため、
編集後はリロードしてから実行してください。

## イベント

イベントは key/value のレコードです。フィールドはタブ区切りで、値は
バックスラッシュ、タブ、改行、CR をエスケープします。最初の 2 フィールドは
必ず `EVENT` とトピック名です。

```text
EVENT	window-focus	id=7	previous=0	ws=3	app=foot	title=notes	output=HEADLESS-1
EVENT	workspace-change	ws=4	previous-ws=3	output=HEADLESS-1
EVENT	launcher	arg=fire	output=HEADLESS-1
EVENT	panel	arg=calendar	output=HEADLESS-1
EVENT	panel	arg=clipboard	output=HEADLESS-1
EVENT	panel	arg=screenshot	output=HEADLESS-1
EVENT	panel	arg=media	output=HEADLESS-1
EVENT	panel	arg=tray	output=HEADLESS-1
EVENT	panel	arg=audio	output=HEADLESS-1
EVENT	notification-action	id=12	action=reply
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
| `mode-change` | アクティブ入力モードの変更 | arg（モード名） |
| `config-reload` | 設定の再読み込み成功 | — |
| `launcher` | ランチャー要求 | arg（クエリ）, output |
| `panel` | パネルのポップオーバー要求 | arg（`calendar`、`power`、`clipboard`、`screenshot`、`media`、`tray`、`audio`）, output |
| `notification-action` | IPC 経由の通知アクション要求 | id, action（アクションキー） |
| `output-added` | 出力初期化 | output, arg（ジオメトリ） |
| `output-removed` | 出力削除 | output, arg（ジオメトリ） |
| `animation-start` | ウィンドウ表示/ワークスペーススライド開始 | id, ws, output, arg（`open` / `workspace`） |
| `animation-done` | ウィンドウ表示/ワークスペーススライド完了 | id, ws, output, arg（`open` / `workspace`） |
| `close-animation-start` | コンポジタ起点の終了スナップショット開始 | id, ws, output, arg（`close`） |
| `close-animation-done` | 終了スナップショットのフェード完了 | id, ws, output, arg（`close`） |

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

## イベントルール

`event-rule` は条件付きフックです。ウィンドウルールと同じ真偽値／POSIX
正規表現の式を使い、追加で `event`、`ws`、`id` を参照できます:

```ini
event-rule = window-open; match=app ~ "^firefox$" && ws == "2"; run=notify-send "Firefox" "workspace 2"
event-rule = workspace-change; match=ws == "3"; run=~/bin/on-workspace-3
```

最初の節がイベント名（`event=` でも可）、`match`/`expr` は任意、
`run`/`command` は必須です。一致したルールは設定順に、無条件 `hook` より
先に実行され、同じ `TESSA_*` 環境を受け取ります。`tessa-ctl config` は
`event_rule_count` と解析済みルールを表示します。

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

## エフェクトヘルパープロトコル

`effect_helper` はコンポジタごとに 1 つの常駐プロセスを起動します。ウィンドウの
メタデータ、フォーカス、ジオメトリ、ルール適用後の見た目が変わるたびに、
タブ区切りの完全なスナップショットを送ります:

```text
HELLO\t1
EFFECT\t1
WINDOW\t<id>\t<app-id>\t<title>\t<output>\t<ws>\t<focused>\t<urgent>\t<fullscreen>\t<floating>\t<visible>\t<opacity>\t<corner-radius>\t<blur>\t<shadow>\t<border-width>\t<x>\t<y>\t<w>\t<h>
...
END
```

`focused`、`urgent`、`fullscreen`、`floating`、`visible` は `0`/`1`。
`opacity`、角丸、ボーダー幅はルール適用後の値、`blur`/`shadow` は `on`、
`off`、`unset` です。応答:

```text
VERSION\t1
WINDOW\t<id>\t<opacity>\t<corner-radius>\t<blur>\t<shadow>\t<border-width>
...
END
```

上書きはウィンドウごとに任意です。Tessa はリクエスト内の ID、重複、範囲
（opacity 0〜1、角丸 0〜64、ボーダー幅 0〜16）を検証します。応答にない
ウィンドウはルール適用値へ戻ります。タイムアウト、クラッシュ、未知の ID、
不正なモード、`END` 欠落では全上書きを破棄し、1 秒後に再試行します。
stdout はプロトコル専用で、診断は stderr に出してください。リクエストは
合流され、応答待ちの間は最新状態だけが次に送られます。

最小例:

```python
#!/usr/bin/env python3
import sys

while True:
    lines = []
    while True:
        line = sys.stdin.readline()
        if not line:
            raise SystemExit(0)
        line = line.rstrip("\n")
        if line == "END":
            break
        lines.append(line.split("\t"))
    out = ["VERSION\t1"]
    for fields in lines:
        if fields[0] != "WINDOW":
            continue
        window_id, app_id, title = fields[1], fields[2], fields[3]
        if app_id == "org.example.notes" or "notes" in title.lower():
            out.append(f"WINDOW\t{window_id}\t0.92\t18\toff\toff\t3")
    out.append("END")
    sys.stdout.write("\n".join(out) + "\n")
    sys.stdout.flush()
```

```ini
effect_helper = python3 ~/.config/tessa/effects.py
effect_helper_timeout = 200
```

ヘルパーはコンポジタと同じ権限で動き、サンドボックスはありません。調整
できるのは宣言済みの視覚プロパティだけで、コンポジタ内へのシェーダー注入や
コード実行はできません。`tests/effect-helper.sh` が上書きと解除を検証します。

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

JSON スナップショットは `schema: 1` でバージョン管理しています。JSON-RPC は
読み取り、リクエスト ID、ケイパビリティ交渉、JSON イベント購読を提供します
が、変更操作は行コマンドを使います。拡張間の順序制御、サンドボックス、
投げっぱなしコマンドの ACK はありません。ステータスはテキストのみです。
レイアウトヘルパーの応答は完成したスナップショットで、矩形の部分
ストリーミング更新には対応していません。
