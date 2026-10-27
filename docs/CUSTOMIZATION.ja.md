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
```

マッチ条件:

| キー | 意味 |
| --- | --- |
| `app-id`、`app_id`、`class` | xdg アプリケーション ID |
| `title` | ウィンドウタイトル |
| `output`、`monitor` | 出力名 |

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

同じルールで `float=false` を指定しない限り、`size` と `position` は
フローティングを暗黙に有効にします。ルールはファイル順に評価され、後の
ルールが前のルールを上書きできます。ウィンドウのマップ時と、`Super+R` /
`tessa-ctl dispatch reload` による再読み込み時に、既存ウィンドウにも
再適用されます。マップ後のタイトル変更だけでは、次の再読み込みまで
ルールは再評価されません。

値に空白を含める場合は引用符で囲めます。フラット形式では値の中の `;` は
使えません。

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

`output-rule` は 1 つのモニタのレイアウト調整を上書きします。`ws=` を付けると
そのワークスペースだけに限定できます:

```ini
output-rule = output=HDMI-A-1; layout=grid; gaps=8; outer-gaps=12
output-rule = output=HDMI-A-1; ws=2; layout=master; master-ratio=0.62
```

| 句 | 意味 |
| --- | --- |
| `output=` / `monitor=` | 出力名パターン（必須。`*` と `?` が使える） |
| `ws=1..9` | 任意。省略すると全ワークスペース |
| `layout=master/mosaic/grid/columns/custom` | レイアウトのシード |
| `gaps=N`、`outer-gaps=N` | タイル間隔と外周間隔 |
| `master-ratio=0.15..0.9`、`master-count=1..8` | マスター調整 |
| `mosaic-ratio=0.25..0.85`、`mosaic-min-size=N` | モザイク調整 |
| `grid-columns=0..8` | グリッド固定列数。`0` は自動 |

ルールはファイル順に適用されます。優先順位は、グローバル既定 <
出力ルール（全ワークスペース） < `workspace-rule` < `ws=` 付き出力ルール
です。実行中のレイアウト選択はシードより優先され、永続化されます。

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

モザイクは設定された最小タイルを維持できない場合、重なりや極端に細い
タイルを作らず、ワークスペース全体をグリッドに切り替えます。

## 外部レイアウトヘルパー

独自タイルは常駐ヘルパープロセスで実装します。`layout = custom` を選び、
`layout_helper` にコマンドを指定します。`Super+T` の巡回に含めたい場合は
明示的にバインドしてください。

```ini
layout = custom
layout_helper = python3 ~/.config/tessa/layout.py
layout_helper_timeout = 100
bind = SUPER+SHIFT+T set-layout custom
```

Tessa は使用可能領域とタイル対象ウィンドウをタブ区切りで送り、ウィンドウごと
の矩形を受け取ります。以下の `	` は実際のタブ文字を表します。

```text
LAYOUT	1
OUTPUT	HEADLESS-1
AREA	0	0	1920	1080
OUTER_GAP	16
GAP	10
BORDER	2
SCALE	1.000
TRANSFORM	0
COUNT	2
WINDOW	7	foot	notes
WINDOW	8	kitty	shell
END
```

ヘルパーの応答:

```text
RECT	7	16	16	940	1048
RECT	8	966	16	938	1048
END
```

座標はコンポジタの絶対論理座標です。矩形の幅・高さはボーダーを含むフレーム
サイズです。フローティングとフルスクリーンのウィンドウは送られません。
応答にはリクエスト内の全ウィンドウに対して過不足なく 1 つずつ矩形を返し、
未知の ID を含めてはいけません。配置を拒否する場合は `RECT` の代わりに
`ERR` を返します。

ヘルパーは必要になったときに起動され、レイアウト変更をまたいで保持され、
全出力で共有されます。`layout_helper` の変更時または失敗後に再起動します。
コマンド未設定、タイムアウト、クラッシュ、不正な応答、矩形不足の場合は、
その配置だけマスターへフォールバックします。同じコマンドは失敗から 1 秒後に
再試行します。1 リクエストの対象は最大 64 タイルです。タイムアウトの既定値は
100 ms で、10〜1000 ms の範囲です。

`stdout` はプロトコル専用です。診断は `stderr` に書いてください。コマンドは
フックと同様、`/bin/sh` 経由でユーザー権限で実行されます。最小の実例は
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
別レイアウト/調整値、ルール、フック、診断を含みます。ワイヤ形式の詳細は
[EXTENDING.ja.md](EXTENDING.ja.md) にあります。

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
| `animation_ms` | 再生時間（ミリ秒、0〜1000、既定 160） |
| `reduce_motion` | `animations` に関係なく動きを無効化（既定 `false`） |
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

## モーション、シャドウ、壁紙

ウィンドウは map 時に小さな縦オフセットからスライドインし、ワークスペース
切り替えでは新しいワークスペースが横方向から入ります。どちらも
`animation_ms` の cubic ease-out です。キーバインド、バーのチップ、IPC、
他のクライアントなどコンポジタ経由で閉じたウィンドウは、サーフェスを
キャプチャして同じ再生時間の smoothstep でスナップショットを
スケール/フェードします。クライアント自身が閉じた場合はバッファが既に
消えているため即時に消えます。`reduce_motion = true` は他の設定を変えずに
動きだけを無効化します。`animation_ms = 0` と `animations = false` も同じ
効果です。ポップオーバーのアニメーションはパネル側で別に制御します。

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

- 出力別のレイアウト/隙間ルール（ワークスペース別は実装済み）。
- 出力別のヘルパーインスタンス、非同期/差分更新、プロトコルバージョン
  交渉（現在のヘルパーは単一プロセスで、配置ごとに上限付きの要求/応答を
  行います）。
- 正規表現/論理式によるウィンドウルールと、ルール別のボーダー/背景色。
- キーバインドのシーケンスとリーダーキー（名前付き入力モードは実装済み）。
- 設定によるイベント→アクションルールと出力別テーマロール。
- ウィンドウ移動、ワークスペース切り替え、ボーダー、シェル向けの設定可能な
  アニメーションとシェーダー/エフェクトフック。
- 既存の診断と JSON スナップショットを使った、差分プレビュー付きの
  対話型設定エディタ/チェッカー。
- サーフェス別のフォント・配色ロール、壁紙アート、交換可能なシェル
  サーフェス（バーの高さ・マージンは実装済み）。

ロードマップは [ROADMAP.ja.md](ROADMAP.ja.md) にあります。
TypeScript/TSX 設定ランタイムは今後も非目標です。ShojiWM 的なコンポジションに
対する Tessa の答えは、JS VM を埋め込むことではなく、プロセスプロトコルと
宣言的ルールの組み合わせです。
