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

実行中のレイアウト選択はシードより優先され、永続化されます。
`Super+Ctrl+H/L` は現在のセッションでアクティブワークスペースの比率を
変更し、設定再読み込みで設定値に戻ります。

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
| `power_lock` | 電源メニューのロック用コマンド（既定 `loginctl lock-session`） |
| `power_suspend` | サスペンド用コマンド（既定 `systemctl suspend`） |
| `power_reboot` | 再起動用コマンド（既定 `systemctl reboot`） |
| `power_off` | 電源オフ用コマンド（既定 `systemctl poweroff`） |
| `screenshot_dir` | スクリーンショット PNG の保存先（既定 `~/Pictures/Screenshots`） |

パネルは `config-reload` を受け取ると配色、ランチャー項目、バーの
ジオメトリ、電源コマンドを読み直します。高さやマージンが変わった場合は
バーの layer surface を再作成するため、予約領域も即座に更新されます。
別ファイルのテーマと壁紙アートの制御は今後追加します。

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

## 通知

パネルはセッション bus 上で `org.freedesktop.Notifications` D-Bus サービスを
実装しているため、別の通知デーモンなしでアプリから利用できます。最大 4 件の
プレーンテキストのトーストがバーの下に積み重なります。通知 ID による置換、
タイムアウト（`0` は手動で閉じるまで保持）、`CloseNotification`、クリックで
閉じる操作に対応します。閉じた場合はアプリへ `NotificationClosed` を送ります。
期限付きの通知は自動で消え、対応するシグナルを発行します。

広告する capability は `body` と `persistence` です。マークアップ、アクション、
アイコン検索は未実装です。別の通知デーモンが既に動いている場合、Tessa は
bus 名を取得できず、通知はそのデーモンに任せます。bus 名を所有できるパネルは
1 つだけなので、マルチモニタではそのパネルの出力に通知が表示されます。

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
`reload`、`ratio`、`toggle-layout`、`set-layout`、`resize-width`、
`resize-height` です。

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
