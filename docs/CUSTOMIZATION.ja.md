[English](CUSTOMIZATION.md) | **日本語**

# カスタマイズ

Tessa は JavaScript/TypeScript ランタイムやネイティブプラグイン VM を
組み込まずに、高いカスタマイズ性を目指しています。カスタマイズは 3 層です。

1. **宣言的な設定** — キーバインド、ウィンドウルール、レイアウト調整、
   配色、include、ライブリロード。
2. **プロセス拡張** — フック、構造化イベント、ステータス、ランチャー、
   `tessa-ctl` が使う Unix ソケット IPC。
3. **外部ポリシーエンジン用プロトコル** — 常駐レイアウトヘルパー
   プロトコルは利用可能です。次段階として、より豊富なエフェクト制御を
   追加します。任意の言語のポリシーエンジンを、コンポジタ内にコードを
   ロードせず動かせる設計です。

フラットな `key = value` 形式は意図的です。パーサを小さく保ち、位置依存の
include を可能にし、`tessa-ctl config` で実効値と解析済みルールを確認できます。

## ウィンドウルール

1 行が 1 ルールです。マッチ条件とアクションを `;` で区切ります。

```ini
window-rule = app-id=pavucontrol; float=true
window-rule = title=Picture-in-Picture; float=true; position=40,40
window-rule = app-id=firefox; workspace=2
window-rule = title=GIMP*; float=false
window-rule = match=app ~ "^firefox$" && title !~ "Private|Incognito"; workspace=2
window-rule = title=Chat*; border-active=#4cc9f0; border-inactive=#1b2a41
window-rule = app-id=mpv; opacity=0.9; border-width=0; corner-radius=0
window-rule = title=Picture-in-Picture; opacity=0.85; corner-radius=14; blur=true
```

マッチ条件:

| キー | 意味 |
| --- | --- |
| `app-id`、`app_id`、`class` | xdg アプリケーション ID |
| `title` | ウィンドウタイトル |
| `output`、`monitor` | 出力名 |
| `match`、`expr` | POSIX 拡張正規表現を使う真偽値式 |

式のフィールドは `app` / `app-id` / `class`、`title`、`output` /
`monitor` です。演算子は `==`、`!=`、`~`、`!~`、`&&` / `and`、`||` / `or`、
`!` / `not`、括弧です。空白を含む値は引用符で囲めます。単純なマッチ条件と
`match` は AND で結合されます。不正な式や正規表現はファイル名／行番号付きの
設定エラーになります。

パターンはシェル風の `*` と `?` を使えます。大文字小文字は区別されます。

```ini
window-rule = title=*Picture-in-Picture*; float=true
window-rule = app-id=org.example.*; workspace=3
```

アクション:

| キー | 意味 |
| --- | --- |
| `float=true/false` | フローティング/タイルで開く |
| `tile=true/false` | `float` の反対 |
| `fullscreen=true/false` | フルスクリーンで開く |
| `workspace=1..9` | ワークスペースへ割り当て |
| `size=WxH` | フローティングサイズ（例: `size=900x600`） |
| `width=N`、`height=N` | 片軸だけ指定するフローティングサイズ |
| `position=X,Y` | フローティング位置 |
| `border-active=#RRGGBB` | ウィンドウ別フォーカスボーダー |
| `border-inactive=#RRGGBB` | ウィンドウ別非フォーカスボーダー |
| `opacity=0.0..1.0` | ウィンドウと装飾の不透明度 |
| `corner-radius=0..64` | ウィンドウ別の角丸（`rounding` も可） |
| `blur=true/false` | ウィンドウ別の背景ブラー |
| `shadow=true/false` | ウィンドウ別の影 |
| `border-width=0..16` | ウィンドウ別ボーダー幅。`0` で非表示 |

同じルールで `float=false` を指定しない限り、`size` と `position` は
フローティングを暗黙に有効にします。不正な式や正規表現はファイル名／行番号
付きの設定エラーになります。ボーダー色、不透明度、角丸、ボーダー幅、影の
状態は閉じるスナップショットにも使われます。`corner-radius` と `blur` は
`-Dscenefx=true` ビルドが必要で、それ以外は全ビルドで動作します。

ルールはファイル順に評価され、後のルールが前のルールを上書きできます。
構造アクション（`float`、`workspace`、`size`、`position`、`fullscreen`）は
ウィンドウのマップ時と、`Super+R` / `tessa-ctl dispatch reload` による
再読み込み時に評価されます。装飾アクション（`border-*`、`opacity`、
`corner-radius`、`blur`、`shadow`、`border-width`）は、タイトルまたは
app-id が変わった時点でも即座に再評価されます。

値に空白を含める場合は引用符で囲めます。フラット形式では値の中の `;` は
使えません。

## レイヤールール

バー、通知デーモン、壁紙プロバイダなどのレイヤーシェルクライアントは
`layer-rule` で設定します。

```ini
layer-rule = namespace=tessa-bar; opacity=0.94; corner-radius=12; blur=true
layer-rule = namespace=tessa-notifications; layer=overlay; opacity=1; blur=false
layer-rule = namespace=my-wallpaper; layer=background; opacity=1; blur=false
```

| 節 | 意味 |
| --- | --- |
| `namespace=` / `ns=` | レイヤー namespace のパターン |
| `output=` / `monitor=` | 出力名のパターン |
| `layer=` | `background`、`bottom`、`top`、`overlay`、または `0..3` |
| `opacity=0.0..1.0` | レイヤーサーフェスの不透明度 |
| `corner-radius=0..64` | レイヤーサーフェスの角丸 |
| `blur=true/false` | 背景ブラーの上書き |

後の一致が優先されます。ルールがない場合の不透明度は `1`、角丸は `0`、
ブラーは top／overlay レイヤーだけグローバル設定に従います。レイヤールールは
map 時と設定リロード時に適用されます。実効値は `tessa-ctl state` /
`state --json`、解析済みルールは `tessa-ctl config` / `config --json` で
確認できます。不透明度は全ビルド、角丸とブラーは `-Dscenefx=true` ビルドで
有効です。

## レイアウト調整

| キー | 既定値 | 意味 |
| --- | --- | --- |
| `gaps` | `10` | タイル間の隙間 |
| `outer_gaps` | `16` | タイル領域の外周 |
| `master_ratio` | `0.58` | マスター列の幅比率 |
| `master_count` | `1` | マスター列に縦積みするウィンドウ数 |
| `mosaic_ratio` | `0.62` | モザイクのスライス比率 |
| `mosaic_min_size` | `160` | モザイクがグリッドへ切り替える最小タイル |
| `grid_columns` | `0` | グリッドの固定列数。`0` は `ceil(sqrt(n))` |
| `layout` | `master` | 既定レイアウト |
| `layout_1` … `layout_9` | 継承 | ワークスペースごとの初期レイアウト |

実行中のレイアウトは出力・ワークスペースごとに保持され、`outputs.conf` に
保存されます。設定の再読み込みは、実行中の上書きがないワークスペースだけを
更新します。`layout_N` は保存済み・実行中の選択がないワークスペースの
初期値だけを設定します。

`workspace-rule` はワークスペースごとにレイアウトと間隔を上書きします。

```ini
workspace-rule = ws=2; layout=grid; gaps=4; outer-gaps=8; master-ratio=0.65
```

| 句 | 意味 |
| --- | --- |
| `ws=1..9` | 対象ワークスペース（必須） |
| `layout=master/mosaic/grid/columns/custom` | 初期レイアウトのシード |
| `gaps=N` | このワークスペースのタイル間隔 |
| `outer-gaps=N` | このワークスペースの外周間隔 |
| `master-ratio=0.15..0.9` | このワークスペースのマスター列幅 |
| `master-count=1..8`、`mosaic-ratio`、`mosaic-min-size`、`grid-columns` | 追加の調整 |
| `profile=NAME` | 名前付きプロファイルを先に適用 |

`output-rule` は 1 つのモニタのレイアウト調整を上書きします。コネクタ名または
EDID 情報でモニタを指定し、`ws=` を付けるとそのワークスペースだけに限定できます:

```ini
output-rule = output=HDMI-A-1; layout=grid; gaps=8; outer-gaps=12
output-rule = output=HDMI-A-1; ws=2; layout=master; master-ratio=0.62
output-rule = make=Dell Inc.; model=DELL*; adaptive-sync=on
output-rule = serial=ABC123; adaptive-sync=off
```

| 句 | 意味 |
| --- | --- |
| `output=` / `monitor=` | コネクタ名パターン |
| `make=` / `vendor=` | EDID メーカーパターン |
| `model=` | EDID モデルパターン |
| `serial=` / `edid-serial=` | EDID シリアルパターン |
| `ws=1..9` | 任意。省略すると全ワークスペース |
| `layout=master/mosaic/grid/columns/custom` | レイアウトのシード |
| `gaps=N`、`outer-gaps=N` | タイル間隔と外周間隔 |
| `master-ratio=0.15..0.9`、`master-count=1..8` | マスター調整 |
| `mosaic-ratio=0.25..0.85`、`mosaic-min-size=N` | モザイク調整 |
| `grid-columns=0..8` | グリッド固定列数。`0` は自動 |
| `profile=NAME` | 名前付きプロファイルを先に適用 |
| `adaptive-sync=true/false` / `vrr=` | この出力で VRR を要求 |

`output`、`make`、`model`、`serial` のうち少なくとも 1 つのマッチ条件が
必要です。複数指定した場合は、指定した項目がすべて一致しなければなりません。
`*` と `?` が使えるため、ドック接続や再起動でコネクタ名が変わっても同じ
モニタにルールを適用できます。

出力ルールはテーマキーも受け付けます: `accent`、`bg`、`border-active`、
`border-inactive`、`panel-bg`、`panel-fg`、`bg-top`、`bg-bottom`、
`bar-height`、`bar-top-margin`、`bar-side-margin`。パネルも自分の出力に
一致するルールを読むため、モニタ別の色と寸法が一致します。ハイフンと
アンダースコアはどちらも使えます。

`adaptive-sync` は `ws=` のないルールにのみ適用されます。Tessa は出力が
adaptive sync に対応しているか確認し、コミット結果をログに出力します。
ルールを削除すると、Tessa がポリシーを適用する前の状態に戻します。VRR に
対応したモードやコネクタが必要なモニタもあるため、有効化しても効果がない
場合は Tessa のログを確認してください。

ルールはファイル順に適用されます。優先順位は、グローバル既定 <
出力ルール（全ワークスペース） < `workspace-rule` < `ws=` 付き出力ルール
です。実行中のレイアウト選択はシードより優先され、永続化されます。

名前付きプロファイルはレイアウト/チューニングをまとめます:

```ini
profile = compact; gaps=0; outer-gaps=0; master-ratio=0.5; master-count=2
profile = grid3; layout=grid; grid-columns=3; gaps=6; outer-gaps=2
output-rule = output=DP-1; profile=compact; gaps=4
workspace-rule = ws=2; profile=grid3
```

プロファイルは参照するルールの前後どちらでも宣言できます。ルール内の明示
キーがプロファイルより優先されます。プロファイルはレイアウト/間隔のみで、
テーマは含みません。存在しないプロファイルは設定エラーになり、リロードは
拒否されます。

`Super+Ctrl+H/L` は現在のセッションでアクティブな出力/ワークスペースの
比率を変更し、設定再読み込みで設定値に戻ります。

ワークスペースをモニタに固定すると、そのショートカットで常に該当モニタへ
切り替わります:

```ini
workspace_pin = eDP-1 1
workspace_pin = HDMI-A-1 3
```

キーボード、ジェスチャ、IPC、バーからのピン留めワークスペースへの切り替えは
その出力へリダイレクトされます。`Super+Shift+<n>` はフォーカス中の
ウィンドウをそのワークスペースへ移動し、別出力にピン留めされている場合は
ウィンドウの出力も変更します。出力が存在しない間はピンが無視されます。
`tessa-ctl workspace <n> <output>` で出力を指定してもピンが優先されます。

ワークスペースにはバー表示とコマンド用の名前も付けられます:

```ini
workspace-name = 2 Code
workspace-name = 3 Chat
bind = SUPER+2 workspace Code
bind = SUPER+SHIFT+2 move-to-workspace Code
window-rule = app-id=org.mozilla.firefox; workspace=Chat
```

名前はグローバルで一意な 1 トークン（空白なし、数字のみ不可）です。設定全体を
読み終えてから解決するため、宣言順は自由です。バーのピルには名前が表示され
（長い名前は短縮）、`tessa-ctl workspace Code` と
`tessa-ctl dispatch move-workspace Code` が同じ別名を使えます。ウィンドウの
内部表現は従来どおり数値なので、モード、ピン、ジェスチャ、永続化はそのまま
動きます。ウィンドウルールの `workspace=` は数値と名前のどちらも受け付けます。

各出力には非表示のフローティングスクラッチパッドがあります:

```ini
window-rule = app-id=org.example.notes; scratchpad=true
# window-rule = app-id=org.example.notes; workspace=special
bind = SUPER+grave toggle-scratchpad
bind = SUPER+SHIFT+grave move-to-scratchpad
```

`toggle-scratchpad` はフォーカス中出力のスクラッチパッドを表示／非表示し、
表示時は最初のウィンドウへフォーカスします。`move-to-scratchpad` は
フォーカス中ウィンドウをスクラッチパッドへ送り、スクラッチパッド上では通常
タイルへ戻します。ワークスペース切り替えでスクラッチパッドは隠れます。
番号付きワークスペースではなくフローティングのオーバーレイなので、
ワークスペース占有数や `Super+1..9` には影響しません。

ウィンドウグループはワークスペースのタイルウィンドウを 1 つのタブ付き
タイルにまとめます:

```ini
bind = SUPER+SHIFT+g toggle-group
bind = SUPER+ALT+g group-add
bind = SUPER+ALT+SHIFT+g group-remove
```

`toggle-group` はアクティブワークスペースのタイルウィンドウをグループ化し、
メンバーにフォーカスがあるときはグループ全体を解除します。グループ中は
表示中のメンバーだけが見え、`Super+Tab` / `Super+Shift+Tab` は別タイルでは
なくタブを巡回します。`group-add` はフォーカス中ウィンドウを同じ
ワークスペースのグループへ追加し、`group-remove` はグループから外します。
グループは実行時状態で永続化されず、メンバーを別ワークスペースや
スクラッチパッドへ移動すると外れます。IPC では `toggle-group`、
`group-next`、`group-prev`、`group-add`、`group-remove` が使えます。

モザイクは設定された最小タイルを維持できない場合、重なりや極端に細い
タイルを作らず、ワークスペース全体をグリッドに切り替えます。

## 外部レイアウトヘルパー

独自タイルは出力ごとの常駐ヘルパープロセスで実装します。`layout = custom`
を選び、`layout_helper` にコマンドを指定します。`Super+T` の巡回に含めたい
場合は明示的にバインドしてください。

```ini
layout = custom
layout_helper = python3 ~/.config/tessa/layout.py
layout_helper_timeout = 100
bind = SUPER+SHIFT+T set-layout custom
```

Tessa は最初に `HELLO<TAB>2` を送り、その後は使用可能領域とタイル対象
ウィンドウを非同期リクエストで送ります。応答待ちでコンポジタが停止することは
ありません。ヘルパーが `VERSION<TAB>2` を通知した後のリクエストは次のように
なります（`	` は実際のタブ文字です）。

```text
HELLO	2
LAYOUT	2
OUTPUT	HEADLESS-1
AREA	0	0	1920	1080
OUTER_GAP	16
GAP	10
BORDER	2
SCALE	1.000
TRANSFORM	0
COUNT	2
WINDOW	7	foot	notes	1	0
WINDOW	8	kitty	shell	0	1
END
```

`WINDOW` の最後の 2 フィールドは `focused` と `urgent`（`1` または `0`）です。
緊急度はスクリプトから `tessa-ctl dispatch urgent <id> on`（`off` で解除）で
設定でき、フォーカスすると解除されます。状態 JSON では `"urgent"` として
公開されます。

ヘルパーの応答:

```text
VERSION	2
RECT	7	16	16	940	1048
RECT	8	966	16	938	1048
END
```

`VERSION	2` は省略可能です。省略するとプロトコル 1 とみなします。未知の行を
無視する旧ヘルパーはそのまま使えます。最初のリクエストはプロトコル 1 の
3 フィールド形式の `WINDOW` で、`VERSION	2` を通知した後のリクエストから
focused/urgent フィールドが追加されます。座標は
コンポジタの絶対論理座標です。矩形の幅・高さはボーダーを含むフレームサイズ
です。フローティングとフルスクリーンのウィンドウは送られません。応答には
リクエスト内の全ウィンドウに対して過不足なく 1 つずつ矩形を返し、未知の ID
を含めてはいけません。配置を拒否する場合は `RECT` の代わりに `ERR` を返します。

出力ごとに独立したプロセスと矩形キャッシュを持ちます。レイアウト、フォーカス、
緊急度が変わるとリクエストを送ります。応答待ちの間は以前の矩形を維持し、
その間の変更は次のリクエストにまとめられます。最初の成功応答までは内蔵
レイアウトを使います。コマンド未設定、タイムアウト、クラッシュ、不正な応答、
矩形不足の場合は、その出力だけマスターへフォールバックし、同じコマンドを
1 秒後に再試行します。`layout_helper` を変更すると再起動し、同じコマンドの
設定リロードではプロセスを維持します。

1 リクエストの対象は最大 64 タイルです。タイムアウトの既定値は 100 ms で、
10〜1000 ms の範囲です。`stdout` はプロトコル専用です。診断は `stderr` に
書いてください。コマンドはフックと同様、`/bin/sh` 経由でユーザー権限で実行
されます。最小の実例は
[`examples/layout-cascade.py`](../examples/layout-cascade.py) にあります。

## 入力モード

モードはバインドをまとめ、`enter-mode` アクションで入ります。

```ini
mode = resize
bind = h resize-width -30
bind = l resize-width 30
bind = Escape enter-mode default

mode = default
bind = SUPER+SHIFT+r enter-mode resize
```

`mode = <名前>` は次の `mode` 行まで、後続の `bind` の解析コンテキストを
切り替えます。名前には英数字、`_`、`-` を使えます。include から戻ると
呼び出し元のモードに復元されます。

モード内のバインドは修飾キーなしでもマッチします。グローバル（default）
バインドは引き続き有効で、どのバインドにも一致しないキーはフォーカス中の
クライアントへ渡ります。これにより、別のコンポジタを用意せずにモーダルな
リサイズ、ナビゲーション、ランチャー風キーマップを作れます。
`tessa-ctl mode <名前>` でスクリプトから切り替えられ、アクティブモードは
`tessa-ctl state` の `MODE <名前>`、状態 JSON の `"mode"`、設定 JSON の
`"modes"`、`mode-change` イベントで公開されます。

リーダーキーとモード別タイムアウトも使えます:

```ini
leader = SUPER+SPACE
leader_timeout = 1000

mode = leader
bind = f spawn firefox
bind = t spawn kitty
bind = Escape enter-mode default

mode = resize
mode_timeout = 300
bind = h resize-width -30
bind = l resize-width 30
```

既定モードでリーダーを押すと `leader` モードに入ります。一致するバインドは
1 アクション実行後に既定モードへ戻り、別モードへ入るアクションはそのモードを
維持します。もう一度リーダーを押す、`Escape`、`leader_timeout` 経過で終了
します。`leader_timeout = 0` は無期限です。`mode_timeout` はそのモード節に
適用され、経過後 `default` に戻ります。`0` で無効化します。

## イベントルール

イベントルールはライフサイクルイベントを式で絞り込み、シェルコマンドを
実行します:

```ini
event-rule = window-open; match=app ~ "^firefox$" && ws == "2"; run=notify-send "Firefox" "ワークスペース 2"
event-rule = window-open; match=id ~ "^[0-9]+$" && title == "Mail"; run=touch ~/.local/state/mail
event-rule = workspace-change; match=ws == "3"; run=~/bin/on-workspace-3
```

最初の節がイベント名です（`event=` でも指定可）。`match` / `expr` は任意で、
`run` / `command` は必須です。式では `event`、`ws`、`id` も文字列として
参照できます。コマンドにはフックと同じ環境変数
（`TESSA_EVENT`、`TESSA_WINDOW_ID`、`TESSA_WORKSPACE`、`TESSA_TITLE`、
`TESSA_OUTPUT`、`TESSA_ARG` など）が渡されます。一致したイベントルールは
設定順に、無条件 `hook` より先に実行されます。フックと同様に `/bin/sh -c`
とセッションユーザーの権限で動きます。

## 検証と JSON

設定はファイル名と行番号を追跡して解析します。未知のキー、不正な数値/
真偽値/色、壊れたルール、存在しない include は黙って無視せず報告します。

```sh
tessa-ctl config-check
```

`Super+R` / `tessa-ctl dispatch reload` はエラーのある設定を拒否し、以前の
設定を維持します。`tessa-ctl config` は実効値に加えて
`diagnostic error <path>:<line>: <message>` 行を表示します。エラーが残って
いる間、`config-check` は非ゼロで終了します。

ツール向けに、両スナップショットはスキーマバージョン付きの JSON でも取得
できます。

```sh
tessa-ctl state --json
tessa-ctl config --json
```

状態 JSON は `schema: 1`、出力、占有状況、フォーカス ID、ステータス、
ウィンドウのジオメトリを含みます。設定 JSON はスカラー設定、ワークスペース
別レイアウト/調整値、ルール、フック、イベントルール、プロファイル、
テーマロール、診断を含みます。ワイヤ形式の詳細は
[EXTENDING.ja.md](EXTENDING.ja.md) にあります。

同じソケットで JSON-RPC 2.0 の読み取りとイベント購読もできます:

```sh
tessa-ctl rpc '{"jsonrpc":"2.0","id":1,"method":"hello"}'
tessa-ctl rpc '{"jsonrpc":"2.0","id":7,"method":"state"}'
tessa-ctl rpc '{"jsonrpc":"2.0","id":"cfg","method":"config"}'
```

`hello` はケイパビリティ（`state`、`config`、`events`、`subscriptions`、
`request-ids`、プロトコルバージョン 1）を返します。`subscribe` は
`params.subscription` にリクエスト ID を持つ JSON 通知としてイベントを
配信します。変更操作は行コマンドを使います。

## デバイス別入力とカーソル

libinput 設定は繰り返し可能な `input`（または `input-rule`）行で指定します。
デバイス種別やワイルドカード名でマッチし、ファイル順にマージされます:

```ini
input = type=touchpad; tap=true; tap-drag=true; natural-scroll=true
input = type=touchpad; name=*Precision*; accel-profile=flat; accel-speed=-0.3
input = type=mouse; name=*Mouse*; natural-scroll=false; scroll-method=button; scroll-button=275
input = type=touchpad; dwt=false; click-method=clickfinger
input = type=pointer; left-handed=true
```

| 句 | 意味 |
| --- | --- |
| `type=any/keyboard/pointer/touchpad/mouse/touch/tablet/tablet-pad/switch` | デバイス種別。既定は `any` |
| `name=` / `device=` | libinput デバイス名パターン。`*` と `?` が使える |
| `tap=`、`tap-drag=`、`tap-drag-lock=` | タッチパッドのタップ動作 |
| `natural-scroll=`、`left-handed=`、`middle-emulation=` | スクロール方向・左右・中ボタンエミュレーション |
| `dwt=` / `disable-while-typing=` | キー入力中のタッチパッド無効化 |
| `accel-profile=adaptive/flat`、`accel-speed=-1.0..1.0` | ポインタ加速 |
| `scroll-method=none/two-finger/edge/button/circular` | スクロール方式 |
| `scroll-button=1..767` | `scroll-method=button` で使う evdev ボタン |
| `click-method=none/button-areas/clickfinger` | タッチパッドのクリック方式 |
| `tap-button-map=lrm/lmr`、`clickfinger-button-map=lrm/lmr` | ボタン順 |

タップに対応するポインタはタッチパッド、それ以外はマウスとして分類します。
タッチパッド専用の句はマウスでは無視され、デバイスが対応しないポインタ句も
スキップされます。Tessa はルールを適用する前にデバイスの元の libinput 状態を
記録するため、設定リロードで上書きを削除すると元の状態に戻ります。デバイス名は
`libinput list-devices` で確認できます。

カーソルの見た目は 2 つのグローバルキーで指定します:

```ini
cursor_theme = Adwaita
cursor_size = 24
```

`cursor_theme` は Xcursor テーマ名で、空ならシステム既定です。`cursor_size` は
16〜96 論理 px に丸められます。リロードで両方即座に反映されます。テーマの
読み込みに失敗した場合は警告をログに出し、以前のカーソルを維持します。

## 入力、ジェスチャ、XIM

| キー | 意味 |
| --- | --- |
| `gestures` | コンポジタのスワイプジェスチャを有効化（既定 `true`） |
| `gesture_fingers` | シェルスワイプの指の本数、2〜5（既定 3） |
| `gesture_workspace_threshold` | ワークスペース切り替えに必要な横移動量（既定 400） |
| `gesture_launcher_threshold` | ランチャーを開く上方向の移動量（既定 300） |
| `touch` | タッチ入力デバイスを受け付ける（既定 `true`） |
| `tablet` | tablet-v2 のツール/パッドを有効化（既定 `true`） |
| `pointer_constraints` | `pointer-constraints-v1` を有効化（既定 `true`） |
| `xim` | X11 クライアント向けに `XMODIFIERS` を設定（既定 `true`） |
| `xim_server` | XIM サーバ名。空なら変数を設定しない（既定 `fcitx`） |
| `xim_start` | X ディスプレイ出現後に起動する任意の XIM サーバコマンド |

キーボードフォーカスを持つ layer サーフェスが開いていないとき、
`gesture_fingers` 本ちょうどのスワイプをシェルが処理します。左スワイプで
次のワークスペース、右スワイプで前のワークスペース、上スワイプで
ランチャーを開きます。`gestures = false` にすると全ジェスチャを
クライアントへ転送します。指の本数が異なるスワイプ、ピンチ、ホールドは
常に `pointer-gestures-v1` でフォーカス中のクライアントへ送られます。
しきい値は 20〜1000 の範囲で調整でき、小さいほど早く反応します。

タッチデバイスは共有カーソルに接続され、シーンのヒットテスト経由で
配送されます。クライアントをタップするとフォーカスし、パネルはタッチを
直接受け付けます。tablet-v2 のツールには proximity、tip、筆圧、距離、
傾き、回転、スライダー、ホイール、ボタンを配送し、tablet-v2 非対応の
サーフェスではポインタクリックとしてフォールバックします。タブレット
パッドのボタン、リング、ストリップ、モード変更はキーボードフォーカス中の
サーフェスへ送られます。

pointer constraints はサーフェスがキーボードフォーカスを得たときに
有効化され、フォーカス変更で無効化されます。locked pointer はカーソル
移動を止めつつ、相対移動をクライアントへ届けます。confined pointer は
制約リージョン内に移動を制限します。制約を無視するには
`pointer_constraints = false` を設定します。

X11 の入力メソッド向けに、Tessa は XWayland の起動後に
`XMODIFIERS=@im=<xim_server>` をエクスポートします。`xim_start` は任意で、
X ソケットができてから起動するため、Fcitx がディスプレイ準備前に立ち上がる
問題を避けられます:

```ini
xim = true
xim_server = fcitx
xim_start = fcitx5 -d
```

Fcitx や IBus を `startup` から起動している場合は `xim_start` を空にして
ください。XIM 設定はコンポジタ起動時に適用されるため、変更後は Tessa を
再起動します。別の入力メソッド基盤が `XMODIFIERS` を管理する場合は
`xim = false` にします。

## 外観

| キー | 意味 |
| --- | --- |
| `accent` | ボーダー、パネル、ランチャーのアクセント |
| `bg` | 壁紙/背景色 |
| `border_active` | フォーカス中ボーダー色。空なら `accent` |
| `border_inactive` | 非フォーカス時ボーダー色 |
| `border_width` | ボーダー幅（論理ピクセル） |
| `font` | パネル/ランチャーのフォント |
| `bar_height` | バーの高さ（32〜96 論理ピクセル） |
| `bar_top_margin` | 上端からの距離（0〜64） |
| `bar_side_margin` | 左右マージン（0〜128） |
| `panel_bg` | バーの背景色 |
| `panel_fg` | バーの主要テキスト色 |
| `bg_top` | 壁紙グラデーションの上端色。未指定なら `bg` から導出 |
| `bg_bottom` | 壁紙グラデーションの下端色。未指定なら `bg` から導出 |
| `wallpaper_art` | 装飾用の壁紙アートを描画（既定 `true`） |
| `animations` | ウィンドウを開く/閉じる/ワークスペース切り替えをアニメーション（既定 `true`） |
| `animation_ms` | 既定の再生時間（ミリ秒、0〜1000、既定 160） |
| `animation_open_ms`、`animation_workspace_ms`、`animation_close_ms` | 種類別の再生時間。`-1` で継承（既定 `-1`） |
| `reduce_motion` | 移動アニメーションを無効化（既定 `false`） |
| `reduce_motion_animations` | `none`、または閉じるフェードのみの `fade`（既定 `none`） |
| `reduce_motion_fade_ms` | 視差効果低減時の閉じるフェード時間（既定 `120`） |
| `shadows` | レイヤー化したウィンドウシャドウを描画（既定 `true`） |
| `corner_radius` | ウィンドウの角丸半径（論理ピクセル、0〜64、既定 `10`。scenefx ビルド） |
| `blur` | 半透明クライアントとシェルレイヤーの背景ブラー（既定 `true`。scenefx ビルド） |
| `blur_radius` | ブラー半径（1〜32、既定 `6`） |
| `blur_passes` | ブラー品質のパス数（1〜5、既定 `3`） |
| `power_lock` | 電源メニューのロック用コマンド（既定 `loginctl lock-session`） |
| `power_suspend` | サスペンド用コマンド（既定 `systemctl suspend`） |
| `power_reboot` | 再起動用コマンド（既定 `systemctl reboot`） |
| `power_off` | 電源オフ用コマンド（既定 `systemctl poweroff`） |
| `screenshot_dir` | スクリーンショット PNG の保存先（既定 `~/Pictures/Screenshots`） |
| `volume_status` | 任意の状態コマンド（パーセントを出力）。空なら `wpctl`/`pactl`/`amixer` を自動検出 |
| `volume_up` | 任意の音量上げコマンド上書き |
| `volume_down` | 任意の音量下げコマンド上書き |
| `volume_mute` | 任意のミュート切り替えコマンド上書き |

パネルは `config-reload` を受け取ると配色、ランチャー項目、バーの
ジオメトリ、電源コマンドを読み直します。高さやマージンが変わった場合は
バーの layer surface を再作成するため、予約領域も即座に更新されます。
`bg_top`、`bg_bottom`、`wallpaper_art` は再起動なしで背景を描き直します。
別ファイルのテーマは今後追加します。

コンポジタとパネルで共有する意味論的カラー:

```ini
theme-role = accent = #e2684f
theme-role = window.border.active = #8fd3ff
theme-role = window.border.inactive = #243040
theme-role = window.background = #0a0f1a
theme-role = panel.background = #0e1320
theme-role = panel.foreground = #eef2f8
theme-role = wallpaper.top = #162038
theme-role = wallpaper.bottom = #070a12
```

ロールは直接キーの後に適用されて上書きし、一致する出力別テーマルールは
その出力でさらに優先されます。パネルも同じロールを読みます。

## モーション、シャドウ、壁紙

ウィンドウは map 時に設定可能なオフセットからスライドインし、ワークスペース
切り替えでは新しいワークスペースが横方向から入ります。どちらも名前付き
cubic-bezier またはスプリングカーブ（組み込み、`bezier = name, x1, y1, x2, y2`、
`spring = name, damping, frequency`）を使い、種類別の再生時間
（`animation_open_ms` / `animation_workspace_ms`、未指定は `animation_ms`）で
再生します。キーバインド、バーのチップ、IPC、他のクライアントなど
コンポジタ経由で閉じたウィンドウは、サーフェスをキャプチャして
`animation_close_curve` と `animation_close_ms` でスナップショットを
スケール/フェードします。クライアント自身が閉じた場合はバッファが既に
消えているため即時に消えます。`reduce_motion = true` は開く/WS の移動だけを
無効化します。`animation_ms = 0` と `animations = false` は全体を無効化
します。視差効果低減時は `reduce_motion_animations = fade` で縮小/移動なしの
閉じるフェードだけを残し、`none` で close エフェクトも無効にします。
ポップオーバーのアニメーションはパネル側で別に制御します。

ウィンドウルールで個別のウィンドウだけ無効化したり、時間やカーブを
上書きできます。

```ini
spring = bounce, 0.35, 1.4
window-rule = app-id=kitty; animation=false
window-rule = title=Picture-in-Picture; animation-ms=260; animation-curve=spring-soft; animation-close-ms=180; animation-close-curve=bounce
```

`animation-curve` は開く／ワークスペース、`animation-close-curve` は閉じる
遷移に使います。スプリングの減衰は 0.05〜2、振動数は 0.25〜4 で、減衰が
小さいほどオーバーシュートし、終端は必ず 1 になります。

シャドウは各クライアントフレーム背後の半透明シーン矩形 3 枚です。
ボーダーのジオメトリに追従し、`shadows = false` で無効になります。

`-Dscenefx=true` でビルドした場合、`corner_radius` がクライアントの
コンテンツ、ボーダー、シャドウ層を角丸にします。フルスクリーン
ウィンドウは四角のままです。`blur` は半透明ウィンドウと top/overlay/
popup レイヤーサーフェスの背景を、`blur_radius` と `blur_passes` の
設定でぼかします。どちらも設定再読み込みで即座に反映されます。既定の
wlroots シーンビルドでもキーは受け付けますが、視覚効果はありません。

壁紙は縦グラデーションです。`bg_top` と `bg_bottom` で既定値を上書き
でき、片方だけの指定も可能です。装飾（アクセントのウォッシュ、インクの
しみ、太陽、テッセレーション）は `wallpaper_art = true` のときだけ
描画されます。

## カレンダーと電源メニュー

時計をクリックすると月間カレンダーが開きます。`Left`/`Right`、矢印ボタン、
スクロールホイールで月を移動し、`Home` で今日に戻ります。電源メニューは
`TESSA` マークの右クリックで開き、ロック、サスペンド、再起動、電源オフ、
Tessa の終了を選べます。最初の 4 項目は上の `power_*` コマンドを実行します。
`Up`/`Down` と `Enter` でも操作でき、ポップオーバーの外側をクリックすると
閉じます。

拡張プロセスから開閉することもできます:

```sh
tessa-ctl panel calendar
tessa-ctl panel power
tessa-ctl panel power DP-1
```

ポップオーバーを開くと `panel` イベントが `arg=calendar` または
`arg=power` と出力名付きで発行されるため、フックからシェルの状態を監視・
操作できます。

## クリップボード履歴

`Super+V` でクリップボード履歴を開きます。`tessa-ctl panel clipboard` でも
開けます。パネルはコンポジタの `wlr-data-control-v1` グローバルを使い、
キーボードフォーカスなしでセレクションの変更を監視します。履歴は重複を除いた
最新 8 件のテキスト（各 16 KiB まで）をメモリ上にだけ保持し、ディスクには
書き込みません。項目を選ぶと先頭へ移動し、パネルが新しいセレクション
ソースになるため、通常の貼り付け操作でどのアプリにも貼れます。

`clipboard` はキーバインドアクションとしても使えます:

```ini
bind = SUPER+v clipboard
bind = SUPER+SHIFT+v clipboard
```

## スクリーンショット

`Super+Shift+S`（または `tessa-ctl panel screenshot`）で、フォーカス中の出力を
`wlr-screencopy` でキャプチャします。ドラッグで範囲選択、クリックで全画面、
`Enter` でも全画面を保存し、`Esc` または右クリックでキャンセルします。
パネルはオーバーレイ上に選択範囲を描画し、暗くした領域から選択部分を
くり抜いて、ドラッグ中は物理ピクセルサイズを表示します。

PNG は `screenshot_dir` に保存されます:

```ini
screenshot_dir = ~/Pictures/Screenshots
```

これが既定値で、必要ならサブディレクトリも作成します。ファイル名は
`tessa-YYYYMMDD-HHMMSS-mmm.png` です。キャプチャはオーバーレイを表示する前に
行うため、選択 UI や暗いレイヤーは写りません。バーは出力の一部なので、
バーより下を範囲選択しない限り含まれます。`screenshot` はキーバインド
アクションとしても使えます:

```ini
bind = SUPER+SHIFT+s screenshot
```

## システム表示とメディア

`/sys/class/power_supply` にバッテリーがある場合、バーに残量を表示し、充電中は
塗りつぶし色を変えます。ネットワーク表示は `/proc/net/route` のデフォルト
ルートと `/sys/class/net` のインターフェース状態を読み、`wireless` 属性が
あれば `Wi-Fi`、なければ `LAN` と表示します。どちらも 5 秒ごとに更新され、
設定は不要です。

Tessa はセッション bus 上の MPRIS を監視します。最初に見つかったプレイヤーの
曲名と再生状態がバーのチップに表示されます。チップのクリック、`Super+M`、
`tessa-ctl panel media` で前へ/再生・一時停止/次へのコントロールを開けます。
ポップオーバー内では `Space` で再生/一時停止、`Left`/`Right` で曲を移動します。
メタデータは読み取り専用で、アルバムアートは表示しません。`media` は
キーバインドアクションとしても使えます:

```ini
bind = SUPER+M media
bind = SUPER+SHIFT+m media
```

## StatusNotifier トレイ

パネルは `org.kde.StatusNotifierWatcher` を所有し、登録されたトレイ項目を
ホストします。`IconPixmap` または `IconName` のアイコンがバーに表示されます。
左クリックでアクティベート、右クリックまたは `Super+Shift+T` で項目名と
ステータスのポップオーバーを開きます。`Up`/`Down` で選択、`Enter` で
アクティベート、`Esc` で閉じます。次のコマンドでも開けます:

```sh
tessa-ctl panel tray
```

`tray` はキーバインドアクションとしても使えます:

```ini
bind = SUPER+SHIFT+t tray
```

DBusMenu のコンテキストメニューとセカンダリアクティベートは未実装です。
別の watcher が D-Bus 名を所有している場合、トレイサービスは失敗をログに
残し、パネルの他の機能は動作を続けます。

## 音量

`wpctl`、`pactl`、`amixer` のいずれかが利用できる場合、パネルは既定の出力
音量をバーに表示します。クリックまたは `Super+Shift+A` で音量ポップオーバーを
開きます。`Up`/`Down` で音量、`m` でミュート、`Esc` で閉じます。
`tessa-ctl panel audio` でも開け、`audio` はキーバインドアクションです:

```ini
bind = SUPER+SHIFT+a audio
```

既定のコマンド:

- PipeWire: `wpctl get-volume @DEFAULT_AUDIO_SINK@`、
  `wpctl set-volume ... 5%+/-`、`wpctl set-mute ... toggle`
- PulseAudio: `pactl get-sink-volume`、`pactl set-sink-volume`、
  `pactl set-sink-mute`
- ALSA: `amixer get Master`、`amixer sset Master ...`

パネル設定で個別に上書きできます。カスタム状態コマンドはパーセントを出力し、
`MUTED`/`[off]` を含められます。カスタムコマンドは `/bin/sh -c` で実行します:

```ini
volume_status = ~/.local/bin/my-volume-status
volume_up = ~/.local/bin/my-volume up
volume_down = ~/.local/bin/my-volume down
volume_mute = ~/.local/bin/my-volume mute
```

## 画面共有とポータル

コンポジタは `xdg-desktop-portal-wlr` が必要とする
`zwlr_screencopy_manager_v1`、レンダラーが対応していれば linux-dmabuf、
`ext-output-image-capture-source-manager-v1`、`ext-image-copy-capture-v1`、
2 種類の foreign-toplevel リストを公開します。リポジトリには
`packaging/portal/tessa.portal` があり、システムパッケージでは
`/usr/share/xdg-desktop-portal/portals/` にインストールされます。
`XDG_CURRENT_DESKTOP=Tessa` のときに wlr バックエンドを選びます。

`xdg-desktop-portal`、`xdg-desktop-portal-wlr`、PipeWire サーバーを
インストールしてください。xdpw の自動選択を使わない場合は出力を指定します:

```ini
# ~/.config/xdg-desktop-portal-wlr/config
[screencast]
chooser_type = none
output_name = HDMI-A-1
max_fps = 30
```

モニターの画面共有は `tests/portal.sh` で端から端まで確認しています。
ウィンドウ単位のソースはポータルバックエンドの image-capture-source
プロトコル対応に依存し、Tessa は現在出力キャプチャソースを公開しています。

## 通知

パネルはセッション bus 上で `org.freedesktop.Notifications` D-Bus サービスを
実装しているため、別の通知デーモンなしでアプリから利用できます。最大 4 件の
トーストがバーの下に積み重なります。通知 ID による置換、タイムアウト
（`0` は手動で閉じるまで保持）、`CloseNotification`、クリックで閉じる操作に
対応します。期限付きの通知は自動で消え、対応するシグナルを発行します。

広告する capability は `actions`、`body`、`body-markup`、`icon-static`、
`persistence` です:

- **アクション。** `default` 以外のアクションはトースト下部のボタンに
  なります。クリックすると `ActionInvoked` を発行して通知を閉じます。
  `default` アクションはカード本体のクリックで発火します。拡張から
  `tessa-ctl notify-action <id> <key>` で呼ぶこともできます。
- **アイコン。** `image-data`/`image_data`、`image-path`/`image_path`、
  `icon-name` ヒント、`app_icon` 引数に対応します。PNG アイコンは通常の
  XDG アイコンディレクトリから検索し、見つからない場合は色付きの
  モノグラムを表示します。
- **マークアップ。** 本文は Pango マークアップとして描画します
  （太字、斜体、下線、span、リンク）。解析できない場合はプレーンテキスト
  として表示します。
- **ルーティング。** 新しいトーストはフォーカス中の出力に表示されます。
  表示中にフォーカスが移ると、スタックも新しい出力へ移動します。
  D-Bus 名を所有するパネルが選択した出力に描画するため、アクションも
  そのまま動作します。

別の通知デーモンが既に動いている場合、Tessa は bus 名を取得できず、通知は
そのデーモンに任せます。通知音と Pango が対応しない HTML は未実装です。

動作確認:

```sh
gdbus call --session --dest org.freedesktop.Notifications \
  --object-path /org/freedesktop/Notifications \
  --method org.freedesktop.Notifications.Notify \
  test-app 0 "" "ビルド完了" "すべてのターゲットが最新です" "[]" "{}" 5000
```

## キーとコマンド

既定のキーバインドは [../README.ja.md](../README.ja.md#キーバインド) を
参照してください。追加バインドには XKB keysym 名を使います。

```ini
bind = SUPER+Return terminal
bind = SUPER+g set-layout grid
bind = SUPER+ALT+Left resize-width -30
bind = SUPER+ALT+Right resize-width 30
```

利用可能なアクションは `spawn`、`terminal`、`close`、`quit`、`workspace`、
`move-to-workspace`、`focus`、`move`、`toggle-float`、`toggle-fullscreen`、
`focus-next`、`focus-prev`、`launcher`、`clipboard`、`screenshot`、`media`、
`tray`、`audio`、`reload`、`ratio`、`toggle-layout`、`set-layout`、
`resize-width`、`resize-height` です。

## ライブ確認と自動化

`tessa-ctl config` は解析済みルールと調整値を含む実効設定を表示します。

```sh
tessa-ctl config
tessa-ctl state
tessa-ctl events window-open
```

フックはイベントストリームと同じ構造化フィールドを受け取ります。ステータス、
カスタムランチャー項目、実行中レイアウト変更、ウィンドウリサイズはすべて
IPC から操作できます。プロトコルの詳細は
[EXTENDING.ja.md](EXTENDING.ja.md) にあります。

## 今後のカスタマイズ

- ウィンドウ移動、ワークスペース切り替え、ボーダー、シェル向けの
  シェーダー/エフェクトフック。
- 既存の診断と JSON スナップショットを使った、差分プレビュー付きの
  対話型設定エディタ/チェッカー。
- サーフェス別のフォント・配色ロール、壁紙アート、交換可能なシェル
  サーフェス（バーの高さ・マージン、出力別色、テーマロールは実装済み）。

ロードマップは [ROADMAP.ja.md](ROADMAP.ja.md) にあります。
TypeScript/TSX 設定ランタイムは今後も非目標です。ShojiWM 的なコンポジションに
対する Tessa の答えは、JS VM を埋め込むことではなく、プロセスプロトコルと
宣言的ルールの組み合わせです。
