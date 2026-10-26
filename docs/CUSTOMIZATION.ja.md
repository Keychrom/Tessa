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

## 外観

| キー | 意味 |
| --- | --- |
| `accent` | ボーダー、パネル、ランチャーのアクセント |
| `bg` | 壁紙/背景色 |
| `border_active` | フォーカス中ボーダー色。空なら `accent` |
| `border_inactive` | 非フォーカス時ボーダー色 |
| `border_width` | ボーダー幅（論理ピクセル） |
| `font` | パネル/ランチャーのフォント |

パネルは `config-reload` を受け取ると `accent`、`bg`、`font`、ランチャー
項目を読み直します。パネルの高さ・マージンと、コンポジタから独立した
テーマファイルは今後追加します。

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
`focus-next`、`focus-prev`、`launcher`、`reload`、`ratio`、
`toggle-layout`、`set-layout`、`resize-width`、`resize-height` です。

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
- 出力別のヘルパーインスタンスと差分レイアウト更新（現在のヘルパーは
  単一プロセスで、配置ごとに 1 回の要求/応答を行います）。
- ウィンドウ移動、ワークスペース切り替え、ボーダー、シェル向けの設定可能な
  アニメーションとシェーダー/エフェクトフック。
- 行番号付きの設定検証と、サードパーティ製コントロールパネル向けの JSON
  状態/設定出力。
- パネルの高さ・マージン、独立した配色ロール、交換可能なシェルサーフェス。

ロードマップは [ROADMAP.ja.md](ROADMAP.ja.md) にあります。
TypeScript/TSX 設定ランタイムは今後も非目標です。ShojiWM 的なコンポジションに
対する Tessa の答えは、JS VM を埋め込むことではなく、プロセスプロトコルと
宣言的ルールの組み合わせです。
