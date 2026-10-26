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
コードがコンポジタのホットパスに入りません。

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
                         │  wl_data_device + primary    │
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
tree_overlay     ランチャー（layer-shell overlay）
tree_popup       入力メソッドの候補ポップアップ（ime.zig が作成、最前面）
```

フルスクリーンツリーは意図的に top layer より上にあり、フルスクリーンの
クライアントがバーを覆います。ランチャーオーバーレイはフルスクリーンより
上なので、常に操作できます。IME ポップアップツリーはこれらの後に作成される
ため、候補ウィンドウはランチャーやクライアントより前面に表示されます。

クライアントのフレームは `wlr_scene_tree` で、次を含みます:

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

## layer-shell のサイズ計算

layer サーフェスは `output.zig` が overlay → top → bottom → background の
順に設定します。排他サーフェスを先に、非排他サーフェスを後に処理します。
`wlr_scene_layer_surface_v1_configure()` がサーフェスのボックスを計算し、
使用可能領域を縮めます。

パネルのバーは高さ 44 px、上端アンカー、上マージン 12 px、排他ゾーン
44 px です。そのためタイル領域は 56 px に `outer_gaps` を加えた位置から
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
- クリックでフォーカス、フローティングの移動/リサイズ、ポインタ転送を
  実装する
- `request_set_cursor`、cursor-shape-v1、選択リクエストを処理する
- ゲーム向けに相対ポインタ（`relative-pointer-v1`）の移動量を送信する
- キー/ポインタ入力時に idle notifier へアクティビティを通知する

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
- `xdg-decoration` はサーバーサイドで処理します。これがないと satellite は
  クライアントサイドの装飾にフォールバックし、独自のタイトルバーを
  描画します。

## 出力管理

`output.zig` が `wlr-output-manager-v1` を作成し、実際のレイアウト位置で
ヘッド一覧を更新します。`wlr-randr --output ... --mode/--pos/--scale` を
利用できます。apply リクエストは `wlr_backend_test` でアトミックに検証して
commit し、設定ヘッドの状態から出力レイアウトを更新します。layer の配置を
再計算し、位置をクライアントへ再通知します。出力設定は再起動をまたいで
保存されません。出力電源管理プロトコルは別で、`idle.zig` が処理します。

## セッションロック

`lock.zig` が `ext-session-lock-v1` を実装します。新しいロックを受け取ると:

- 通常のデスクトップのシーンツリー（`bg`、layer、ウィンドウ、オーバーレイ、
  IME ポップアップ）を隠し、全出力にブランクフレームを commit する
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

- 各出力が `active_ws` と `last_focused[]` を持ちます。ワークスペースは
  モニタごとに独立し、`Super+1`…`9` はフォーカス中の出力に適用されます。
- **master**: 1 つのマスター領域（比率、デフォルト 0.58）と縦スタック。
- **mosaic**: 再帰的なスパイラル。残りの各ウィンドウが現在の矩形の 62% を
  取り、方向が左 → 上 → 右 → 下と回転します。最後のウィンドウが中央を
  取ります。最大 8 ウィンドウまでスパイラルを使い、それ以降は
  マスター/スタックにフォールバックします。
- ワークスペースは 1〜9 です。ワークスペースのウィンドウはフレームの
  シーンノードを無効化して隠します。隠れたワークスペースもパネルには
  占有状況を報告します。
- フローティングウィンドウは `tree_floating` にあり、使用可能領域の
  55% × 60% で中央に配置されます。
- フルスクリーンはバー領域を含む出力全体と、フルスクリーンのシーンツリーを
  使います。
- 方向指定のバインドでは空間的にフォーカスし、同じ出力に候補がなければ
  隣接する出力へフォーカスが移ります。入れ替えは clients 配列内の位置を
  交換して行い、タイル順序が変わります。移動先に同じ出力の候補がない場合、
  ウィンドウは隣接出力へ転送されます。

タイル領域は、出力の使用可能領域（バーの排他ゾーン適用後）から
`outer_gaps` を引いたものです。ウィンドウ間の隙間は `gaps` です。ボーダーは
各フレームの矩形に含まれます。

## IPC

ソケット: `$XDG_RUNTIME_DIR/tessa.sock`（または `$TESSA_IPC`）、モード 0600。

新しい接続は購読するまで何も受け取りません。パネルは
`CMD subscribe all` を送り、以降は変更のたびに完全な状態スナップショットを
受け取ります:

```text
STATE
ACTIVE 1
OUT eDP-1 1 1
OUT HDMI-A-1 2 0
OCC 1 2
OCC 2 0
...
FOCUSED 7
STATUS\tweather\tTokyo 18C\t
WIN\t7\t1\t1\t0\t0\tkitty\tnotes\teDP-1
WIN\t8\t1\t0\t0\t0\tfoot\tshell\teDP-1
END
```

`OUT` 行は出力名、アクティブワークスペース、フォーカス中かどうかを示します。
`WIN` のフィールドはタブ区切りです: `WIN`、id、workspace、focused、
floating、fullscreen、app_id、title、出力名。`STATUS` は id、テキスト、
任意のクリックコマンドです。文字列フィールドではバックスラッシュ、タブ、
CR、LF がエスケープされます。各パネルは `WIN` と `OUT` を自分の出力で
フィルタし、ワークスペースの占有状況をローカルで再計算します。ステータスは
全出力で共有されます。

購読とパネル → コンポジタのコマンド:

```text
CMD subscribe state|events|all
CMD state
CMD workspace <1..9> [output]
CMD focus <id>
CMD close <id>
CMD spawn <shell command>
CMD launcher [query]
CMD layout
CMD reload
CMD float <id>
CMD status <id> <text>            (タブ区切り形式は --exec に対応)
CMD quit
```

`CMD workspace <n> <output>` は指定したモニタのワークスペースを変更します。
output を省略したキーボード操作ではフォーカス中の出力が使われます。
`CMD launcher [query]` はフォーカス中の出力を含む構造化ランチャーイベントを
発行し、一致するパネルだけがランチャーを開きます。状態のブロードキャストは
Wayland イベントループの idle source でまとめられ、状態購読者にだけ届きます。
イベントもイベント購読者にだけ送られます。

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
  領域。configure ごとに壁紙を 1 回描画します。
- **bar**: layer top、上/左/右アンカー、高さ 44 px、マージン 12/16 px、
  排他ゾーン 44。メニュー、ワークスペースピル、ウィンドウチップ、拡張
  ステータスのヒット矩形は描画ごとに再計算されます。パネルは
  `config-reload` を受けると自分の設定とアプリ一覧を読み直します。
- **launcher**: 必要時に作成、layer overlay、全端アンカー、排他ゾーン -1、
  キーボード EXCLUSIVE。全面透明/ARGB サーフェスで、暗い背景と中央の
  パネルを描画します。パネルの外側をクリックすると閉じられます。

ランチャーは 150 ms でフェード/スケールします。フェードアウト後にだけ
破棄され、layer サーフェスが破棄されるとコンポジタがトップレベルの
フォーカスを復元します。

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

シングルスレッドで、Wayland display の fd と IPC fd を `poll()` します。
タイマー（1 秒の時計、2 秒の CPU/RAM、500 ms のカーソル点滅、16 ms の
アニメーション）は poll タイムアウトで実装しています。
`wl_display_prepare_read`/`read_events` を使って libwayland 内でブロック
しないようにしています。

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
- `cursor-shape-v1-protocol.h` — `wlr_cursor_shape_v1.h` が必要とする

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
