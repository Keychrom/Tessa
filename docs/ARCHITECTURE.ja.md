[English](ARCHITECTURE.md) | **日本語**

# アーキテクチャ

Tessa は 3 つのプログラムで構成されます。

1. **`tessa`** — wlroots コンポジタ兼ウィンドウマネージャ。
2. **`tessa-panel`** — 壁紙、タスクバー、ランチャーを担当する Wayland
   クライアント。Tessa は出力ごとに 1 つのパネルプロセスを起動し、各パネルは
   `TESSA_PANEL_OUTPUT` で 1 つの `wl_output` に結び付けられます。
3. **`tessa-ctl`** — 拡張プロトコルの CLI 兼リファレンス実装。拡張はこの
   CLI に限らず、任意のローカルプロセスで構いません。

両者は Unix ストリームソケットで通信します。シェルを別プロセスに置くことで、
パネルがクラッシュしてもコンポジタは落ちず、テキスト/フォント/UI 関連の
コードがコンポジタのホットパスに入りません。カスタマイズモデルと設定
リファレンスは [CUSTOMIZATION.ja.md](CUSTOMIZATION.ja.md) にあります。

## プロセスとプロトコルの構成

```text
                         ┌─────────────────────────────┐
                         │ tessa                        │
                         │  wl_display                  │
  DRM / headless /  ───▶ │  wlr_backend                 │
  ネスト Wayland         │  wlr_renderer / allocator    │
                         │  wlr_scene (global)          │
                         │  xdg-shell                   │
                         │  wlr-layer-shell             │
                         │  xdg-decoration              │
                         │  xdg-activation / cursor-shape│
                         │  text-input-v3 / input-method-v2│
                         │  wlr-screencopy-v1           │
                         │  linux-dmabuf-v1             │
                         │  ext-image-copy-capture-v1   │
                         │  ext-output-image-capture... │
                         │  ext-foreign-toplevel-list   │
                         │  wlr-foreign-toplevel-mgmt   │
                         │  wl_data_device + primary    │
                         │  wlr-data-control-v1         │
                         │  virtual-keyboard-v1         │
                         │  seat / cursor / keyboard    │
                         └──────┬───────────────┬───────┘
                                │               │
             Wayland クライアント│               │ spawn + DISPLAY
             + tessa-panel      │               ▼
                ────────────────┘        xwayland-satellite
                                                │
                                                ▼
                                            X11 アプリ
```

クライアントとパネルには Wayland を使います。コンポジタ↔パネルの制御
チャネルは、あえて独自の Wayland プロトコルにしていません。行ベースの
ソケットプロトコルなら `socat` や `tessa-ctl` で簡単にデバッグでき、任意の
言語から利用でき、バインディングを生成し直す必要もありません。
`events.zig` がイベントプレーンです。イベントの整形、設定フックの実行、
購読クライアントへの配信を担当します。

## シーングラフの順序

すべてのシーンツリーは `wlr_scene.root` の子で、下から上へ次の順です:

```text
tree_bg          壁紙 / background layer、背景矩形のフォールバック
tree_bottom      layer-shell bottom
tree_windows     タイルされたクライアントのフレーム
tree_floating    フローティングクライアントのフレーム
tree_top         タスクバー（layer-shell top）
tree_fullscreen  フルスクリーンクライアントのフレーム
tree_effects     閉じるアニメーションのスナップショット（通常ウィンドウより前面）
tree_overlay     ランチャー（layer-shell overlay）
tree_popup       入力メソッドの候補ポップアップ（ime.zig が作成、最前面）
```

フルスクリーンツリーは意図的に top layer より上にあり、フルスクリーンの
クライアントがバーを覆います。ランチャーオーバーレイはフルスクリーンより
上なので、常に操作できます。IME ポップアップツリーはこれらの後に作成される
ため、候補ウィンドウはランチャーやクライアントより前面に表示されます。

クライアントのフレームは `wlr_scene_tree` で、次を含みます:

- フレームの外側へ広がる半透明の `wlr_scene_rect` シャドウ 3 枚
- サーフェスの背面にある `wlr_scene_rect`（ボーダー/アクセント）
- `wlr_scene_xdg_surface_create` が返す xdg サーフェスツリー

フレームツリーの `node.data` は `Client` を指します。ポインタのヒット
テストは、そのポインタが見つかるまで親ツリーをたどります。xdg サーフェスの
`data` はサーフェスのシーンツリーを指し、ポップアップを正しい位置に
ペアレントできるようにしています。

トップレベルのポップアップはトップレベルのシーンツリーにペアレントされます。
layer-shell のポップアップは、`xdg_popup` 作成時点では xdg の親を持ちません。
`zwlr_layer_surface_v1.get_popup` で親が割り当てられると layer サーフェスの
`new_popup` イベントが発火します。`output.zig` がこのイベントを監視し、
layer サーフェスのツリーの下にポップアップのシーンツリーを作成します。
これによりサードパーティパネルのメニューやドロップダウンが表示されます。

## ウィンドウの動き、閉じるエフェクト、シャドウ

動きはクライアントフレームノードの位置オフセットで実現し、論理的な
`x`/`y` は `Client` に保持したままです。`startOpenAnimation()` は map
直後のウィンドウを縦 18 px ずらし、`startWorkspaceAnimation()` は新しい
ワークスペース上の map 済みウィンドウを進行方向に応じて横 ±54 px
ずらします。`tickAnimations()` が `animation_ms` に対する cubic ease-out
を計算し、`x + off_x`、`y + off_y` をシーンノードへ書き込みます。
`applyFrame` も現在のオフセットを加えるため、遷移中の再レイアウトで
ウィンドウが飛びません。出力のフレームコールバックが時計を進め、
`onOutputFrame` は commit 前にアクティブなアニメーションを更新し、
残っていれば次のフレームを要求します。

`animations = false`、`reduce_motion = true`、`animation_ms = 0` のいずれかで
オフセットを付けません。設定リロード時は新しいジオメトリを適用する前に
アクティブなアニメーションを消去します。

コンポジタ起点の閉じる操作は `effects.zig` のスナップショット経路を使います。
`requestClose()` は `wlr_xdg_toplevel_send_close` を送る前に、現在の
クライアントバッファを `wlr_buffer_lock` でロックし、ソースボックス、
変換、サーフェスサイズを記録します。この追加ロックは unmap まで `Client`
に保持されるため、アニメーション開始前にクライアントがバッファを再利用
できません。`clientUnmapped()` はロック済みバッファを使って `tree_effects`
配下の一時的なシーンツリーを作成し、シャドウ矩形、輪郭を形成する 4 枚の
ボーダー矩形、`wlr_scene_buffer` を追加します。シーンバッファが独自の参照を
取得してから、クライアント側のロックを解放します。`tick()` が
スナップショットを smoothstep で 92% まで縮小し、`animation_ms` かけて
コンテンツ、ボーダー、シャドウを透明にします。出力のフレームコールバックは
レイアウトアニメーションの後に閉じるエフェクトを更新し、残っていれば次の
フレームを要求します。`tree_effects` はフルスクリーンのクライアントより
前面、ランチャーオーバーレイより背面にあり、セッションロック時は他の
デスクトップツリーと一緒に隠れます。クライアント自身が閉じた場合は unmap
イベントの時点でサーフェスバッファが消えているため、即時に削除されます。

シャドウは上記の事前作成したシーン矩形 3 枚で、`updateShadows()` が
フレームに合わせてサイズを変え、`shadows = false` で無効になります。

## layer-shell のサイズ計算

layer サーフェスは `output.zig` が overlay → top → bottom → background の
順に設定します。排他サーフェスを先に、非排他サーフェスを後に処理します。
`wlr_scene_layer_surface_v1_configure()` がサーフェスのボックスを計算し、
使用可能領域を縮めます。

パネルのバーは既定で高さ 44 px、上端アンカー、上マージン 12 px、
排他ゾーン 44 px です。`bar_height`、`bar_top_margin`、`bar_side_margin` で
変更でき、設定リロード時に値が変わるとバーの layer surface を再作成します。
そのためタイル領域はバー上端 + 高さに `outer_gaps` を加えた位置から
始まります。

`arrangeLayers()` は使用可能領域が変わったときだけタイル済みクライアントを
再配置します。layer の commit/map/unmap と出力作成時に呼ばれます。

各パネルプロセスは明示的な出力オブジェクトを指定して layer サーフェスを
作成するため、バーと壁紙はそれぞれのモニタに配置されます。ランチャーは
フォーカス中の出力のパネルだけがイベントに応答して、その出力の上に
オーバーレイを作成します。新しいトップレベル、出力未指定の layer
サーフェス、キーボードのワークスペース操作には、コンポジタが保持する
フォーカス中の出力が使われます。

キーボード操作可能な layer は map 時にキーボードフォーカスを取得します
（`keyboard_interactive != 0` かつ layer >= top）。unmap 時は、直前に
フォーカスしていたトップレベルへフォーカスを戻します。ランチャーは
`EXCLUSIVE`、バーは `NONE` を要求します。text-input のフォーカスも同じ
遷移に従います。`layout.focusLayer()` と `layout.focusClient()` が
サーフェスの原点を添えて `ime.focusSurface()` を呼ぶため、クライアントの
アクティブな text-input が `enter`/`leave` を受け取ります。

## 入力

`input.zig`:

- seat、cursor、xcursor manager を作成する
- すべてのポインタを `wlr_cursor` にアタッチする
- ユーザー環境と設定（`kb_layout`、`kb_variant`、`kb_options`、`kb_model`、
  `kb_rules`、`repeat_rate`、`repeat_delay`）から XKB キーマップを作成する。
  `Super+R` は再起動せずにキーマップを作り直す
- 物理キーボードがない場合はフォールバックの `wlr_keyboard` を作成し、
  headless セッションでも seat のキーマップと XWayland が動くようにする
- 物理/仮想キーボードをアタッチし、キーボードの出現やキーマップ変更時に
  フォーカスを再送信する
- キーボードイベントをフォーカス中のサーフェスまたはキーバインドへ
  ルーティングする
- 名前付き入力モードをサポートする。モード固有バインドは優先され、
  修飾キーなしでもマッチし、グローバルバインドへフォールバックする。
  未割り当てキーはフォーカス中のクライアントへ渡る。アクティブモードは
  状態と JSON の `MODE`/`mode` で公開される
- クリックでフォーカス、フローティングの移動/リサイズ、ポインタ転送を
  実装する
- `request_set_cursor`、cursor-shape-v1、選択リクエストを処理する
- ゲーム向けに相対ポインタ（`relative-pointer-v1`）の移動量を送信する
- `pointer-gestures-v1` を公開し、設定済みのシェルスワイプを消費し、
  それ以外のスワイプ/ピンチ/ホールドをフォーカス中のクライアントへ転送する
- `wlr-virtual-pointer-v1` を公開する。仮想ポインタも同じカーソルへ
  接続されるため、物理デバイスなしで headless テストからバークリック、
  フォーカス、ドラッグを実行できる
- タッチ/タブレットデバイスをカーソルに接続し、タッチ点をシーンの
  ヒットテスト経由で配送し、tablet-v2 のツール/パッドイベントを転送する
- カーソル移動前に有効な pointer constraint を適用する
- パネルがキーボードフォーカスなしでセレクション変更を監視し、クリップボード
  マネージャーになれるよう `wlr-data-control-v1` を公開する
- キー/ポインタ/タッチ入力時に idle notifier へアクティビティを通知する

入力メソッドがキーボードを grab している間、生のキーイベントと modifier の
変更は、WM のバインドやフォーカス中のクライアントに届く前に
`wlr_input_method_keyboard_grab_v2_set_keyboard` へ転送されます。入力
メソッドはキーマップの専用コピーを受け取り、text-input-v3 経由で何を
確定するかを決めます。

`xdg-activation-v1` のリクエストは、クライアントのワークスペースへ切り替えて
フォーカスします。`xdg-decoration` はサーバーサイドモードで広告され、
GTK や XWayland のクライアントが Tessa のボーダーの上にクライアント
サイドのタイトルバーを描画しないようにします。

キーバインドは正規化した modifier mask（Shift/Ctrl/Alt/Logo）と keysym を
比較します。Shift 付きの数字と Tab では level-0 の keysym も試すため、
レイアウトの Shift 側 keysym に関係なく `Super+Shift+1` と
`Super+Shift+Tab` が動作します。

layer がキーボードフォーカスを持つ間は WM ショートカットをバイパスし、
すべてのキーを layer へ転送します。これによりランチャーで文字入力が
できます。

## タッチ、タブレット、ジェスチャ、pointer constraints

`gestures.zig` は `wlr_cursor` の libinput スワイプ/ピンチ/ホールド信号を
監視し、`pointer-gestures-v1` グローバルを作成します。layer がキーボード
フォーカスを持たず、指の本数が `gesture_fingers` と一致するスワイプは
シェルが消費します。横移動が `gesture_workspace_threshold` を超えると
`layout.switchWorkspaceOnOutput()` でワークスペースを切り替え、上方向が
`gesture_launcher_threshold` を超えるとランチャーイベントを発行します。
それ以外のジェスチャ、および `gestures = false` の場合は
`wlr_pointer_gestures_v1_send_*` でクライアントへ転送します。

`touch.zig` は `wlr_cursor` の touch down/motion/up/cancel/frame を処理
します。デバイスの正規化座標を
`wlr_cursor_absolute_to_layout_coords()` でレイアウト座標へ変換し、
シーンをヒットテストして `wlr_seat_touch_notify_*` で送ります。
タップされたクライアントはフォーカスし、キーボード操作可能な layer は
layer としてフォーカスします。既存タッチ点の移動は
`scene_util.surfaceOrigin()` を使ってサーフェスローカル座標に変換するため、
点がサーフェス外へ出ても座標が壊れません。タッチデバイスを追跡し、
存在するときだけ seat が `WL_SEAT_CAPABILITY_TOUCH` を広告します。
パネルも同じバー/オーバーレイのヒット矩形でタッチを受け付けます。

`tablet.zig` は `wlr_tablet_manager_v2`、デバイスごとの
`wlr_tablet_v2_tablet`、ツールごとの遅延生成される
`wlr_tablet_v2_tablet_tool` 状態を作成します。axis イベントでカーソルを
移動し、tablet-v2 の proximity を確立して、motion、pressure、distance、
tilt、rotation、slider、wheel を転送します。tip とツールボタンは
tablet-v2 対応サーフェスでは tablet イベントを送り、非対応なら左右の
ポインタボタンとしてフォールバックします。パッドのボタン、リング、
ストリップ、モード変更はフォーカス中のサーフェスへ送ります。
`scene_util.zig` はタッチ/タブレット/constraints が共有する
サーフェス/クライアント/layer 検索とサーフェス原点計算を提供します。

`constraints.zig` は `wlr_pointer_constraints_v1` を所有します。新しい
constraint は set_region/destroy リスナー付きで追跡し、
`layout.focusClient()` と `layout.focusLayer()` が
`constraints.focusSurface()` を呼ぶことで、新しくフォーカスされた
サーフェスの constraint を有効化し、以前のものを無効化します。
locked pointer は relative-pointer イベントを送った後に相対移動量を
ゼロにし、confined pointer はサーフェスローカルのリージョンに対して
`wlr_region_confine()` を実行します。有効化時とリージョン変更時には
必要ならカーソルをリージョン内へワープし、locked pointer のカーソル
ヒントは無効化時に適用します。設定リロード時は
`pointer_constraints = false` なら無効化し、そうでなければフォーカス中の
サーフェスを再評価します。

## 入力メソッド

`ime.zig` は `zwp_text_input_v3` と `zwp_input_method_v2` のコンポジタ側を
実装します:

- クライアントの text-input オブジェクトごとに `TextInput` ラッパーを持ち、
  enable/commit/disable と現在の周辺テキスト、カーソル矩形を追跡する
- `focusSurface()` が `enter`/`leave` を送り、フォーカス中のクライアントの
  状態で入力メソッドを activate/deactivate する
- 入力メソッドの `commit` を、プリエディット/確定/削除のリクエストから
  text-input-v3 のイベントへ変換し、`done` を送る
- `grab_keyboard` をフォーカス中の seat キーボードから転送し、入力メソッドの
  切断時に grab を解放する
- 入力メソッドのポップアップサーフェスを `tree_popup` のシーンノードとして
  扱い、text-input のカーソル矩形から配置する（出力端でクランプ）

入力メソッドの状態は、text-input の `active_features` マスクに関係なく
送信します。Fcitx5 はカーソル矩形を渡す前の enable commit で状態を送るため、
`active_features` だけに頼ると候補ポップアップが原点に固定されてしまいました。
そのためコンポジタは、最新の確定済みカーソル矩形が非ゼロならそれを使います。

## XWayland

Tessa は wlroots のプロセス内 XWayland ではなく、バックエンド起動後に
`xwayland-satellite` を spawn します。satellite が X サーバを所有して XWM を
実行し、X11 ウィンドウを xdg-shell トップレベルとして Tessa に見せるため、
既存のタイル、ワークスペース、フォーカス、タスクバーのコードがそのまま
X11 アプリを扱えます。

重要な点:

- satellite の起動前にフォールバックキーボードが存在する必要があります。
  Xwayland 24.x は起動時に親 seat のキーマップから自分のキーマップを
  コンパイルします。キーボードがないと
  `XKB: Failed to compile keymap` で失敗します。
- spawn した子プロセスでは `SIGCHLD` を `SIG_DFL` に戻します。Tessa は
  自分の子プロセスのために `SIGCHLD` を無視していますが、その設定を継承
  すると Xwayland の xkbcomp ヘルパーの wait が失敗し、キーマップの
  コンパイルが中断されます。
- `DISPLAY` は `/tmp/.X11-unix/X<n>` と `/tmp/.X<n>-lock` を走査して最初の
  空きディスプレイを選び、Tessa の環境へエクスポートします。spawn した
  クライアントはすべてこれを継承します。
- `xim.zig` はクライアント起動前に `XMODIFIERS=@im=<xim_server>` を設定
  します。`xim_start` が設定されている場合はタイマーで選択した X ソケット
  の出現を監視し、出現後にだけ XIM サーバを起動します。これにより
  ディスプレイ準備前の起動を避けます。XIM 自体は X11 のクライアント/
  サーバプロトコルであり、Tessa はプロキシせず、環境と起動順だけを
  提供します。
- `xdg-decoration` はサーバーサイドで処理します。これがないと satellite は
  クライアントサイドの装飾にフォールバックし、独自のタイトルバーを
  描画します。

## 出力管理

`output.zig` が `wlr-output-manager-v1` を作成し、実際のレイアウト位置で
ヘッド一覧を更新します。`wlr-randr --output ... --mode/--pos/--scale/
--transform` を利用できます。apply リクエストは `wlr_backend_test` で
アトミックに検証して commit し、設定ヘッドの状態から出力レイアウトを更新
します。layer の配置を再計算し、位置をクライアントへ再通知します。

apply が成功したとき、および実行中にレイアウトを明示的に選んだときに、
現在の出力セットを `outputs.conf`（既定は
`$XDG_CONFIG_HOME/tessa/outputs.conf`）へアトミックに保存します。`output`
行には名前、ピクセルモード、リフレッシュ、レイアウト位置、スケール、変換が
入ります。続く `layout` 行は実行中の上書きだけを
`layout OUTPUT WORKSPACE MODE` 形式で保存し、設定の既定値は書きません。
`new_output` では一致する出力設定をシーン出力追加前に適用し、位置は保存
されたボックスから決めます。保存モードの適用に失敗した場合は優先モード/
headless 既定へフォールバックします。その後、一致する出力の保存済み
レイアウトが設定の初期値を置き換え、そのワークスペースを上書き済みに
します。不正・欠損エントリは無視されます。ファイルはモード 0600 で、
起動時には書き換えず、設定が変わったときだけ更新します。出力の `enabled`
状態はまだ永続化しません。出力電源管理プロトコルは別で、`idle.zig` が
処理します。

## フラクショナルスケーリング

`main.zig` はシェルのグローバルより先に `wp_fractional_scale_manager_v1` を
作成します。`wlr_scene_surface` はサーフェスのプライマリ出力が変わった
時点で、フラクショナルスケールと優先整数バッファスケールをすでに通知します。
Tessa はさらに各 `wlr_output.events.commit` を監視し、
`WLR_OUTPUT_STATE_SCALE` が変わったときにシーングラフを走査します。
`primary_output` がその出力である各シーンサーフェスに対して
`wlr_fractional_scale_v1_notify_scale()` と
`wlr_surface_set_preferred_buffer_scale(ceil(scale))` を呼びます。これにより
`wlr-randr --scale 1.25` が、新規クライアントだけでなく既に map 済みの
クライアントにも反映されます。

フラクショナル対応クライアントは正確なスケールで描画します。非対応
クライアントは整数の切り上げ値を使い、シーンレンダラーがダウンサンプル
します。パネルは別クライアントで、Cairo の整数バッファスケールとして
切り上げ値を引き続き使います。XWayland のスケーリングは
`xwayland-satellite` に委譲し、同じフラクショナルスケールを利用します。
`tests/fractional-scale.sh` はコンパイルしたクライアントで 1.0 → 1.5 →
2.0 の通知経路を検証します。

## セッションロック

`lock.zig` が `ext-session-lock-v1` を実装します。新しいロックを受け取ると:

- 通常のデスクトップのシーンツリー（`bg`、layer、ウィンドウ、エフェクト、
  オーバーレイ、IME ポップアップ）を隠し、全出力にブランクフレームを
  commit する
- キーボード/ポインタフォーカスをクリアし、text-input を非アクティブ化する
- ロックサーフェスごとに `tree_lock` へシーンサーフェスを作成する。
  `tree_lock` は他のすべてのツリーより後に作成されるため、デスクトップより
  前面に描画される
- ロックサーフェスにキーボード/ポインタフォーカスを与え、ロック中は仮想
  キーボードのイベントを無視する。これによりクライアントが
  `virtual-keyboard-v1` 経由でパスワードを入力することはできない
- デスクトップが隠れてから `locked` を送る

`unlock_and_destroy` ではリスナーを外しますが、ロックリソースの破棄は
クライアントのリクエストに任せます。unlock シグナルから
`wlr_session_lock_v1_destroy` を呼ぶと、wlroots の `lock_destroy` の
アサーションに再帰的に入ってしまいました。ロック中にクライアントが
切断した場合、Tessa は放棄されたロックを記録し、通常クライアントを露出
させずセッションを終了します。

## idle と出力電源

`idle.zig` が `ext-idle-notify-v1`、`idle-inhibit-v1`、
`wlr-output-power-management-v1` のグローバルを作成します。入力イベントは
`wlr_idle_notifier_v1_notify_activity` を呼びます。可視の inhibitor を数え、
inhibitor が存在する間またはセッションロック中は
`wlr_idle_notifier_v1_set_inhibited(true)` を送ります。出力電源リクエストは
出力状態の enabled フラグを設定して commit します。これにより `wlopm` が
動作します。タイマーとポリシーはコンポジタの外に置き、swayidle が駆動する
想定です。

## タイルとワークスペース

`layout.zig` が状態遷移を管理します:

- 各出力が `active_ws`、ワークスペースごとの `ws_layouts[]` と
  `layout_overridden[]`、`last_focused[]` を持ちます。ワークスペースと
  レイアウト選択はモニタごとに独立し、`Super+1`…`9` はピン留めがない限り
  フォーカス中の出力に適用されます。
- `workspace_pin = OUTPUT WORKSPACE` はワークスペース番号をモニタに結び付け
  ます。`switchWorkspaceOnOutput` はピンを検索し、キー、ジェスチャ、IPC、
  バー、foreign activation のすべての切り替え経路をその出力へリダイレクト
  します。出力が存在しないピンは無視されます。`moveToWorkspace` は移動先
  ワークスペースが別出力にピン留めされている場合、クライアントの出力を
  変更し、フローティングジオメトリを出力原点間で移動させ、両方の
  `last_focused[]` を更新して両出力を再配置します。`CMD move-workspace <n>`
  は同じ経路を自動化に公開します。
- **master**: 1 つのマスター領域（比率、デフォルト 0.58）と縦スタック。
- **mosaic**: 再帰的なスパイラル。残りの各ウィンドウが現在の矩形の 62% を
  取り、方向が左 → 上 → 右 → 下と回転します。最後のウィンドウが中央を
  取ります。最大 8 ウィンドウまでスパイラルを使いますが、配置前に各
  スライスがタイルを 160 論理ピクセル以上に保てるか確認し、保てない場合は
  重なりや極端に細いタイルを作らず、ワークスペース全体をグリッド配置に
  切り替えます。9 枚以上は最初からマスター/スタックです。
- **grid**: バランスの取れた行/列（`ceil(sqrt(n))` 列）。最終行が不完全な
  場合は中央寄せします。
- **columns**: 等幅・全高のカラム。
- `Super+T` はフォーカス中の出力・ワークスペースのレイアウトを
  マスター → モザイク → グリッド → カラムの順に巡回します。
  `set-layout <name>` は `master`、`mosaic`/`spiral`、`grid`、
  `columns`/`column`、`custom` を受け付けます。明示的に選んだ実行中のレイアウトは
  出力/ワークスペースごとに保持して `outputs.conf` に保存します。設定の
  `layout_N` は保存済み・実行中の上書きがないワークスペースの初期値だけを
  設定します。設定の再読み込みでは、既存出力の上書きしていないワークス
  ペースを更新し、上書き済みのものは維持します。変更時は workspace と
  output を含む `layout-change` を発行します。
- ワークスペース別の `workspace-rule` が gaps、外周 gaps、マスター比率を
  `arrangeOutput` に渡します。実行中の `Super+Ctrl+H/L` はアクティブ
  ワークスペースの比率を現在のセッション向けに変更します。
- `layout_helper.zig` は `socketpair` で接続した常駐子プロセスを管理します。
  `custom` レイアウトはタブ区切りのリクエスト（`LAYOUT`、`AREA`、`WINDOW`、
  `END`）を送り、`RECT` 行を読みます。応答は poll のタイムアウト付きです。
  クラッシュ、タイムアウト、不正な応答、ID 不一致では子プロセスを停止し、
  その配置だけマスターへフォールバックします。コマンド変更時には再起動し、
  終了時に停止します。
- `rules.zig` はマップ時にメタデータが揃った後で宣言的ウィンドウルールを
  評価し、設定再読み込み時には既存ウィンドウにも再評価します。マッチ対象は
  app-id、タイトル、出力で、小さな `*`/`?` ワイルドカードマッチャを使います。
  アクションはフローティング/フルスクリーン状態、ワークスペース、
  フローティングジオメトリを設定します。ルールによる移動はワークスペース
  ごとのフォーカス履歴を更新し、再読み込み経路は配置後に
  `ensureVisibleFocus` を呼ぶため、キーボードフォーカスが隠れたウィンドウに
  残りません。
- ワークスペースは 1〜9 です。ワークスペースのウィンドウはフレームの
  シーンノードを無効化して隠します。隠れたワークスペースもパネルには
  占有状況を報告します。
- フローティングウィンドウは `tree_floating` にあり、使用可能領域の
  55% × 60% で中央に配置されます。`Super+Alt+H/J/K/L` はフォーカス中の
  フローティングウィンドウを左上固定でリサイズします。サイズは 160×120
  （または xdg-shell の最小サイズ）と出力範囲内にクランプされます。
- フルスクリーンはバー領域を含む出力全体と、フルスクリーンのシーンツリーを
  使います。
- 方向指定のバインドでは空間的にフォーカスし、同じ出力に候補がなければ
  隣接する出力へフォーカスが移ります。入れ替えは clients 配列内の位置を
  交換して行い、タイル順序が変わります。移動先に同じ出力の候補がない場合、
  ウィンドウは隣接出力へ転送されます。

タイル領域は、出力の使用可能領域（バーの排他ゾーン適用後）から
`outer_gaps` を引いたものです。ウィンドウ間の隙間は `gaps` です。ボーダーは
各フレームの矩形に含まれます。

## 設定と診断

`config.zig` は `key = value` ファイルと位置依存の include を、元のファイル
パスと行番号を追跡しながら解析します。数値、真偽値、色、レイアウト名、
バインド、フック、ウィンドウルール、include 先を検証します。問題は
`Server.config_issues` に保存され、`CMD config` の
`diagnostic error path:line: message` 行として公開されます。

リロード時は解析前に以前の `Config` をスナップショットします。新しい
ファイルにエラーがあればスナップショットを復元し、キーマップの再読み込み、
ウィンドウルールやレイアウトの適用を行いません。これにより失敗した
`Super+R` は何も変更しません。診断は残るため、
`tessa-ctl config-check` で理由を確認できます。初回起動は寛容で、既定値と
有効な行を使って起動しますが、診断は同様に報告します。

`json_snapshot.zig` がスキーマバージョン付きの `state-json` と
`config-json` スナップショットを組み立てます。転送は従来の行ベースの
コマンドプロトコルを使い、JSON は `STATE_JSON`/`CONFIG_JSON` と `END` の
間に送るため、既存クライアントに影響しません。

## IPC

ソケット: `$XDG_RUNTIME_DIR/tessa.sock`（または `$TESSA_IPC`）、モード 0600。

新しい接続は購読するまで何も受け取りません。パネルは
`CMD subscribe all` を送り、以降は変更のたびに完全な状態スナップショットを
受け取ります:

```text
STATE
ACTIVE 1
OUT eDP-1 1 1 master
OUT HDMI-A-1 2 0 mosaic
OCC 1 2
OCC 2 0
...
FOCUSED 7
STATUS\tweather\tTokyo 18C\t
WIN\t7\t1\t1\t0\t0\tkitty\tnotes\teDP-1\t40\t30\t1100\t700
WIN\t8\t1\t0\t0\t0\tfoot\tshell\teDP-1\t1200\t560\t640\t480
END
```

`OUT` 行は出力名、アクティブワークスペース、フォーカス中かどうか、現在の
レイアウト名を示します。`WIN` のフィールドはタブ区切りです: `WIN`、id、
workspace、focused、floating、fullscreen、app_id、title、出力名、x、y、
幅、高さ。座標とサイズはコンポジタの論理座標です。`STATUS` は id、
テキスト、任意のクリックコマンドです。文字列フィールドではバックスラッシュ、タブ、
CR、LF がエスケープされます。各パネルは `WIN` と `OUT` を自分の出力で
フィルタし、ワークスペースの占有状況をローカルで再計算します。ステータスは
全出力で共有されます。

購読とパネル → コンポジタのコマンド:

```text
CMD subscribe state|events|all
CMD state
CMD workspace <1..9> [output]
CMD move-workspace <1..9>
CMD focus <id>
CMD close <id>
CMD spawn <shell command>
CMD launcher [query]
CMD panel <calendar|power|clipboard|screenshot|media|tray|audio> [output]
CMD layout [name] [output]
CMD resize <dx> <dy>
CMD config
CMD reload
CMD float <id>
CMD status <id> <text>            (タブ区切り形式は --exec に対応)
CMD quit
```

`CMD config` は `CONFIG` マーカー、実効設定の `key value` 行、各
ワークスペースの `layout_ws` と `workspace_tuning` 行、解析済みウィンドウ
ルールの `rule <raw>` 行、`diagnostic` 行、`END` を返します。
`tessa-ctl config` の出力であり、コントロールパネルやデバッグ向けです。
`CMD state-json` と `CMD config-json` は、ツール向けのスキーマバージョン付き
JSON スナップショットを返します。

`CMD workspace <n> <output>` は指定したモニタのワークスペースを変更します。
output を省略したキーボード操作ではフォーカス中の出力が使われます。
`CMD layout` は巡回、`CMD layout <name>` はフォーカス中の出力へ設定、末尾に
output を付けると別モニタを対象にします。
`CMD launcher [query]` はフォーカス中の出力を含む構造化ランチャーイベントを
発行し、一致するパネルだけがランチャーを開きます。`CMD panel
calendar|power|clipboard|screenshot|media` も同様に、要求したポップオーバーと
対象出力を持つ `panel` イベントを発行します。状態のブロードキャストは Wayland イベントループの idle source で
まとめられ、状態購読者にだけ届きます。イベントもイベント購読者にだけ送られます。

## 拡張プレーン

拡張 API は意図的にプロセスベースで、プロセス内プラグイン VM はありません。
`event_names.zig` が公開トピックを定義し、`events.zig` が
`EVENT\t<topic>\tkey=value...` 形式のレコードを組み立て、購読クライアントへ
配信し、一致する設定フックを `TESSA_*` 環境変数付きで起動します。配信は
ベストエフォートで、コンポジタをブロックしません。ソケットバッファが
埋まったクライアントは切断されます。

`ipc.zig` がステータスエントリと状態スナップショットを管理します。
ステータス更新は通常のコマンドで、最大 8 件、以降の全スナップショットに
含まれます。`tessa-ctl` はプロトコルの実例であり、シェルスクリプトから
便利に使えます。完全なスキーマと例は
[EXTENDING.ja.md](EXTENDING.ja.md) にあります。

## パネル

`panel/model.zig` が状態、設定、時計、CPU/RAM サンプリング、検索結果を
保持します。`panel/draw.zig` に Cairo 描画があります。`panel/main.zig` が
Wayland クライアント、IPC、入力コールバック、アニメーション、poll ループを
所有します。Tessa は出力ごとに 1 つのパネルを起動します。各パネルは
`wl_output` をバインドし、`TESSA_PANEL_OUTPUT` で対象出力を選び、
layer-shell にその出力を渡します。状態行は対象出力でフィルタされるため、
各バーにはそのモニタのアクティブワークスペースとウィンドウだけが表示
されます。対象出力がない場合は最初の出力にフォールバックします。

### サーフェス

- **background**: layer background、全端アンカー、排他ゾーン -1、空の入力
  領域。configure ごとに壁紙を 1 回描画します。`bg` から導出した、または
  明示した `bg_top`/`bg_bottom` による縦グラデーションに、任意のアクセント
  アート（`wallpaper_art`）を加えます。
- **bar**: layer top、上/左/右アンカー、設定可能な高さ（`bar_height`、
  既定 44）、上下左右マージン、高さと同じ排他ゾーン。ジオメトリ変更時は
  サーフェスを再作成。メニュー、時計、ワークスペースピル、ウィンドウチップ、
  拡張ステータスのヒット矩形は描画ごとに再計算されます。パネルは
  `config-reload` を受けると自分の設定とアプリ一覧を読み直します。
- 全パネルサーフェスは対象 `wl_output` のスケールに追従します。バッファは
  `論理サイズ * scale` で確保し、描画時に Cairo をスケールします。ヒット
  矩形と IME 矩形は論理座標のままです。760x620 のランチャーデザインは論理
  サーフェスへ均一にフィットされ、同じ変換を描画・ヒットテスト・IME カーソル
  矩形に使います。
- **overlay**: 必要時に作成、layer overlay、全端アンカー、排他ゾーン -1、
  キーボード EXCLUSIVE。全面透明/ARGB サーフェスです。モードに応じて中央の
  ランチャー、時計の下のカレンダー、`TESSA` マークの下の電源メニュー、
  中央のクリップボード履歴、またはスクリーンショットの選択サーフェスを
  描画します。暗い背景とパネルを同じサーフェスに描くため、パネルの外側を
  クリックすると閉じられます。ポップオーバーの
  ヒット矩形はパネル原点を加えたローカル座標で、電源メニューと
  クリップボード履歴ではキーボードが `Up`/`Down`/`Enter` 操作に切り替わります。ポップオーバーを開くと `panel` イベントが発行され、
  パネルプロセスが `launcher` イベントと同様に処理します。

overlay は 150 ms でフェード/スケールします。フェードアウト後にだけ
破棄され、layer サーフェスが破棄されるとコンポジタがトップレベルの
フォーカスを復元します。ランチャーだけが text-input-v3 を有効にし、
それ以外のオーバーレイでは無効にします。

### パネルの text-input

ランチャーは開くときに seat 用の `zwp_text_input_v3` オブジェクトを作成
します。`enter` 時に content type、周辺テキスト、変更理由、検索カーソルの
矩形を送って commit します。プリエディット文字列はアクセント色で
挿入位置に下線付きで描画され、確定文字列は検索語に追加され、
delete-surrounding リクエストも適用されます。Fcitx がキーボードを grab
している間は、コンポジタがパネルではなく入力メソッドへキーを転送するため、
確定した IME テキストがパネルの生キーフォールバックで二重に入力されません。

パネルの `wl_keyboard` キーマップは
`xkb_keymap_new_from_buffer(..., size, XKB_KEYMAP_FORMAT_TEXT_V1,
XKB_KEYMAP_COMPILE_NO_FLAGS)` で読み込みます。`xkb_keymap_new_from_string`
の flags 引数に size を渡していたため、xkbcommon がすべてのキーマップを
拒否し、キーイベントは届いているのに生の文字入力が黙って無効になっていました。

### クリップボード履歴

パネルは通常の `wl_data_device` ではなく
`zwlr_data_control_manager_v1` を使います。wlroots は通常のセレクション
イベントをフォーカス中のクライアントにしか送らないため、バープロセスでは
フォーカスを得た瞬間の現在値しか見えません。data-control デバイスなら
フォーカスなしですべてのセレクション変更を受け取り、シリアルなしで
セレクションを設定できます。

履歴は一意なテキスト 8 件（各 16 KiB）をメモリに保持します。オファーごとに
優先度の高いテキスト MIME を選び、ノンブロッキングパイプでデータを要求して
メインの poll ループで読み切ります。項目を選ぶと data-control ソースへ
コピーし、UTF-8 と従来のテキスト MIME を提供して seat のセレクションに
設定します。この新しいセレクションもパネル自身にオファーとして戻ってきますが、
昇格済みの項目との重複を除外してフィードバックループを防ぎます。内容は
ディスクにもログにも書き出しません。

### スクリーンショット

パネルは `zwlr_screencopy_manager_v1` のバージョン 1 をバインドします。
撮影要求は対象 `wl_output` のフレームを作成し、`buffer` イベントで通知される
形式、物理サイズ、ストライドに合わせて `wl_shm` バッファを確保して `copy` を
送り、`ready` を待ちます。オーバーレイを開くのは `ready` の後なので、選択 UI
や暗いレイヤーが撮影画像に写ることはありません。

オーバーレイは出力全体を暗くし、Cairo の `CLEAR` 演算子で選択矩形をくり抜き
ます。ポインタの押下/移動/解放で範囲を追跡し、ドラッグなしのクリックまたは
`Enter` で全画面、`Esc` と右クリックでキャンセルします。取得済みバッファは
物理座標（論理選択範囲 × 出力スケール）でクロップされ、Cairo のイメージ
サーフェスから PNG として保存されます。既定の保存先は
`~/Pictures/Screenshots` で、`screenshot_dir` により変更でき、不足している
親ディレクトリも作成します。

### 通知

パネルは GIO をリンクし、小さな C シム `panel/notifications.c` が専用の
GLib スレッド上でセッション bus の `org.freedesktop.Notifications` を所有
します。シムは `Notify`、`CloseNotification`、`GetCapabilities`、
`GetServerInformation` を実装し、`NotificationClosed` と `ActionInvoked` を
発行します。通知は socketpair 上のフレーム化バイナリプロトコルで Zig の
イベントループへ渡し、パネルからの閉じる/期限切れ/アクションは GLib
メインコンテキストへの呼び出しで戻すため、D-Bus アクセスはすべて GDBus
スレッド上に留まります。

各通知レコードは ID、タイムアウト、app/summary/body、最大 4 個の
アクション、任意のアイコン名/パス、プリマルチプライ済みネイティブ ARGB32 の
画面アイコンを持ちます。`Notify` は `actions` 配列と `image-data` /
`image_path` / `icon-name` ヒントを解析し、`image-data` は 64×64 までに
制限して行単位でコピーし、アルファをプリマルチプライします。

Zig 側は最大 4 件を保持し、ID による置換、期限切れ、`tessa-notifications`
という右上の layer サーフェスへの描画を行います。アクションボタンがある
場合はトーストの高さが増えます。カード本体のクリックは `default`
アクション、ボタンは `ActionInvoked`、× は閉じる操作になります。本文は
Pango マークアップとして解析できればマークアップ描画し、失敗時は
プレーンテキストへフォールバックします。アイコンは一般的な XDG アイコン
パスから読み込み、なければモノグラムを表示します。D-Bus 名を所有する
パネルがフォーカス中の出力にトーストサーフェスを描画し、フォーカス移動時は
サーフェスを作り直すため、単一の D-Bus 所有者のまま通知がアクティブな
モニターへ追従します。

### システム表示とメディア

バッテリーとネットワークは `panel/model.zig` で 5 秒ごとに取得します。
バッテリーは `/sys/class/power_supply/*/type=Battery`、`capacity`、`status`、
ネットワークは `/proc/net/route` のデフォルトルートと `/sys/class/net` の
インターフェース状態を使います。`wireless` 属性があれば Wi-Fi と表示します。
どちらも読み取り専用のインジケーターで、幅に余裕があるときバーの右側に
表示されます。

`panel/media.c` は 2 つ目の GIO スレッドを動かします。セッション bus 上の
`org.mpris.MediaPlayer2.*` を定期的に探し、最初のプレイヤーの
`org.mpris.MediaPlayer2.Player` に `Properties.GetAll` を送り、再生状態、
曲名、アーティスト、プレイヤー名をフレーム化ソケットでパネルへ渡します。
再生/一時停止、次へ、前へは `g_main_context_invoke` 経由で MPRIS メソッド
呼び出しとして送ります。`Super+M` またはバーのチップで中央のコントロール
ポップオーバーを開きます。アルバムアートやプレイヤー固有のメニューは
取得しません。

### StatusNotifier トレイ

`panel/tray.c` は専用の GIO スレッドでセッション bus 上の
`org.kde.StatusNotifierWatcher` を所有します。`RegisterStatusNotifierItem`、
`RegisterStatusNotifierHost`、watcher プロパティ、登録シグナルを実装します。
登録された項目は 1 秒ごとに `Properties.GetAll` で取得し、`Title`、`Status`、
`IconName`、`IconPixmap` を通知/メディアと同じフレーム化ソケットでパネルへ
送ります。

`IconPixmap` はネットワークバイトオーダーの ARGB32 を並べた `a(iiay)` です。
パネルは Cairo ネイティブの ARGB32 に変換するか、`IconName` を一般的な
PNG アイコンテーマのパスから読み込みます。アクティベートとセカンダリ
アクティベートは GDBus スレッドへ戻します。バーに各項目を描画し、左クリックで
アクティベート、右クリックまたは `Super+Shift+T` でキーボード操作できる
トレイポップオーバーを開きます。DBusMenu は未実装のため、コンテキスト
メニューは提供しません。

### 音量

`panel/audio.c` はワーカースレッドで `wpctl`（PipeWire）、`pactl`
（PulseAudio）、`amixer`（ALSA）を検出するか、パネル設定のコマンドを使います。
1 秒ごとにミキサーを取得してパーセントとミュート状態を解析し、コンパクトな
状態レコードをパネルへ送ります。音量上げ/下げ/ミュートは GIO スレッドへ
渡して非同期に実行し、その後再取得します。パネルはバー表示と
`Super+Shift+A` のポップオーバーを描画します。

### ポータルと画面共有

コンポジタは `zwlr_screencopy_manager_v1`、DRM fd があるレンダラーでは
linux-dmabuf、`ext-output-image-capture-source-manager-v1`、
`ext-image-copy-capture-v1`、`ext-foreign-toplevel-list-v1`、
`zwlr_foreign_toplevel_manager_v1` を公開します。これらは
`xdg-desktop-portal-wlr`（xdpw）がソースを列挙し、フレームを PipeWire
ストリームへコピーするためのコンポジタ側プロトコルです。

`packaging/portal/tessa.portal` は `XDG_CURRENT_DESKTOP=Tessa` のときに
wlr バックエンドを選びます。セッション環境変数は `main.zig` と
`scripts/tessa-session` が設定します。xdpw は screencopy + dmabuf 経路か、
新しい image-copy-capture + 共有メモリ経路を使えます。テストハーネスは
プライベートな PipeWire デーモン、xdg-desktop-portal、xdpw を起動し、
CreateSession/SelectSources/Start/OpenPipeWireRemote を実行して、有効な
ストリームノードとリモート fd を確認します。

### バッファと描画

各サーフェスは 3 枚の `wl_shm` ARGB8888 バッファを保持します。
`wl_buffer.release` リスナーがバッファを空きにし、3 枚とも使用中なら再描画を
延期して poll タイムアウトを 0 にします。バッファは configure のリサイズ時に
作り直されます。

Cairo が角丸矩形、グラデーション、墨だまり、太陽、粒子、バー、ランチャーを
描画します。テキストは Pango の小さな C API である `panel/text.c` 経由で
描画します。このシムが必要なのは、Zig 0.16 の translate-c が GLib の
`_Pragma` ベースの非推奨マクロで失敗するためです。Zig 側は `cairo.h` と
`text.h` だけを含み、Pango/GLib は含みません。

アプリ一覧は XDG データディレクトリ内の `.desktop` ファイルから取得します。
`Name[ja]`/`Comment[ja]` があれば優先します。検索は名前、id、コメントに対する
スコア付きの大文字小文字無視マッチです。ランチャーはアイコンテーマを
読み込まず、モノグラムタイルを表示します。

### イベントループ

シングルスレッドで、Wayland display の fd、IPC fd、クリップボードパイプ、
通知/メディア/トレイ/音量サービスの socketpair を `poll()` します。タイマー
（1 秒の時計、2 秒の CPU/RAM、500 ms のカーソル点滅、16 ms の
アニメーション）は poll タイムアウトで実装しています。
`wl_display_prepare_read`/`read_events` を使って libwayland 内でブロック
しないようにしています。D-Bus とコマンド実行はワーカースレッドで行い、
コンポジタと向き合うパネルループを止めません。

## ビルドと生成プロトコル

`build.zig` がコンポジタ、パネル、`tessa-ctl` をビルドします。コンポジタの
C インポートは `WLR_USE_UNSTABLE` 付きの wlroots 0.19 を含みます。パネルは
layer-shell 用の生成済みクライアントプロトコル C をコンパイルします（これは
推移的に xdg-shell の `xdg_popup_interface` を必要とします）。`tessa-ctl` は
libc とソケットヘッダーだけをリンクします。

`protocol/` 以下の生成済みヘッダー/C はコミットされています:

- `xdg-shell-protocol.h` — wlroots ヘッダー用
- `wlr-layer-shell-unstable-v1-protocol.h` — wlroots ヘッダー用
- `layer-shell-client-protocol.h/.c` — パネル用
- `xdg-shell-client-protocol.h/.c` — パネル/実行時シンボル
- `text-input-client-protocol.h/.c` — パネルの text-input-v3 クライアント用
- `wlr-data-control-unstable-v1-client-protocol.h/.c` — パネルの
  クリップボード履歴用
- `wlr-screencopy-unstable-v1-client-protocol.h/.c` — パネルの
  スクリーンショット用
- `ext-image-copy-capture-v1-protocol.h` — wlroots キャプチャヘッダー用
- `ext-image-capture-source-v1-protocol.h` — wlroots キャプチャヘッダー用
- `cursor-shape-v1-protocol.h` — `wlr_cursor_shape_v1.h` が必要とする
- `pointer-constraints-unstable-v1-protocol.h` —
  `wlr_pointer_constraints_v1.h` が必要とする
- `tablet-v2-protocol.h` — `wlr_tablet_v2.h` が必要とする

## 障害時の動作

- パネルの切断はコンポジタが後始末します。パネルは IPC の EOF で終了します。
- 遅いイベント/状態購読者はイベントループを止めずに切断されます。フックは
  独立したシェルプロセスで動くため、フックの失敗はコンポジタに影響しません。
- パネルがクラッシュしてもコンポジタは生存します。`tessa-panel` を手動で
  再起動してください。
- 出力が取り外されると、クライアントは残っている最初の出力へ移動します。
  最後の出力が取り外されるとコンポジタは終了します。
- 無効なアプリ/desktop エントリはスキップされ、無効な設定値はクランプ
  されます。
- `xwayland-satellite` がない場合、子プロセスの exec が失敗し、Tessa は
  動作を続けます。X11 クライアントはエクスポートされた `DISPLAY` に接続
  できませんが、Wayland クライアントとパネルには影響しません。
- 入力メソッドが接続されていなくても text-input の enter は追跡され、
  クライアントは生のキーボード入力にフォールバックします。パネルは IME を
  必須としません。
- layer-shell のポップアップは所有する layer サーフェスの下に描画されます。
  ポップアップ作成後、`get_popup` で layer と関連付けられる前に描画された
  ポップアップは無視されます。
- 各パネルプロセスは担当出力が消えると終了します（バーの layer サーフェスが
  閉じられます）。他のモニタのパネルはそのまま残ります。
- コンポジタ終了時は `shutdown.zig` がグローバル/出力ごと/キーボードごとの
  リスナーを `wl_display_destroy` 前に外します。wlroots はこれらのシグナル
  リストが空であることを assert するため、xdg-shell のリスナーを残すと終了時に
  プロセスが abort していました。
