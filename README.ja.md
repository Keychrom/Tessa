[English](README.md) | **日本語**

# Tessa

wlroots の上に Zig で実装した、静かなタイル型 Wayland デスクトップです。

Tessa はコンポジタであり、小さなシェルでもあります。フローティングタスクバー、
検索できるランチャー、壁紙、タイルレイアウト、ワークスペース、ウィンドウの
ボーダーまで、すべてこのリポジトリに含まれています。Waybar / Rofi / wofi は
必要ありません。

![Tessa のモザイクレイアウト](docs/images/mosaic.png)

![Tessa のランチャー](docs/images/launcher.png)

上のスクリーンショットは headless 開発セッションで、ターミナルに foot を使って
撮影したものです。

## 状態

MVP（`0.1.0`）ですが、日常的に使えるレベルまで中核機能は実装されています。

- Zig による wlroots 0.19 コンポジタ（DRM / headless / ネストした Wayland
  バックエンドを wlroots が自動判定）
- xdg-shell トップレベル、layer-shell、data-device と primary-selection
  （クリップボード）、xdg-activation、xdg-decoration、cursor-shape-v1、
  wlr-screencopy（grim が動作）
- マスター/スタック、Tessa 独自の「モザイク」スパイラル、グリッド、
  等幅カラムの各レイアウト。ワークスペースごとのレイアウト/隙間/マスター
  比率、マスター列の数、モザイク比率/最小サイズ、グリッド列数も設定可能
  （`Super+T` で巡回）。実行中に選んだレイアウトは再起動後も復元され、
  設定の再読み込みは上書きしていないワークスペースだけを更新
- app-id/タイトル/出力でマッチする宣言的ウィンドウルール。フローティング、
  ワークスペース、フルスクリーン、サイズ、位置を指定可能
- 独自タイルアルゴリズム向けの外部レイアウトヘルパープロトコル。
  タイムアウト、プロセス再起動、内蔵レイアウトへのフォールバック付き
- 行番号付きの設定診断、失敗時に旧設定を維持するトランザクショナルな
  リロード、外部ツール向けのバージョン付き JSON 状態/設定スナップショット
- 名前付き入力モードと、モード固有のキーバインド（`enter-mode`）
- バーの高さ、上下左右のマージン、バー背景色/前景色を設定可能
- 出力ごとに 9 ワークスペース、フローティング、フルスクリーン、クリックで
  フォーカス
- マルチモニタ対応: 各出力にバー/壁紙と独立したアクティブワークスペースを
  持ち、パネルも出力ごとに自動起動。`wlr-randr` による出力管理、設定の
  永続化、整数倍の HiDPI パネルバッファスケーリングに対応
- 外部プロセス向け拡張 API: イベント購読、設定フック、バーへのカスタム
  ステータス、ランチャー項目、自動化クライアント `tessa-ctl`
- ゲームやポインタルック向けの `relative-pointer-v1`
- サードパーティクライアントの layer-shell ポップアップ（パネルのメニューや
  ドロップダウン）
- `ext-session-lock-v1` によるセッションロック。`ext-idle-notify-v1`、
  `idle-inhibit-v1`、出力電源管理にも対応し、swayidle や wlopm と連携可能
- 設定ファイルでキーボードレイアウト/バリアント/オプションとキーリピートを
  設定可能。`Super+R` で再読み込み
- text-input-v3 + input-method-v2 による IME リレーと入力ポップアップの配置。
  Fcitx5 + Mozc でランチャーおよび Wayland クライアントへの日本語入力を
  headless 環境で確認済み
- `xwayland-satellite` による XWayland。ルートレス X11 アプリを通常の Tessa
  トップレベルとして管理し、起動したアプリへ `DISPLAY` を継承
- Zig + Cairo/Pango による統合パネル
  - 墨と朱の壁紙
  - ワークスペースピル、ウィンドウチップ、時計、CPU/RAM を表示する
    フローティングタスクバー
  - キーボード操作と IME 入力に対応した検索型ランチャー
  - 月間カレンダーの時計ポップアップと、ロック/サスペンド/再起動/電源オフの
    コマンドを設定できる電源メニュー
  - `Super+V` で開き、クリックまたはキーボードで貼り付けられるメモリ上だけの
    クリップボード履歴
  - `wlr-screencopy` を使った範囲/全画面スクリーンショット UI（PNG 保存）
  - `org.freedesktop.Notifications` サービスと、置換・閉じる・期限切れに
    対応したプレーンテキストのトースト通知
  - バッテリーとデフォルトルートのネットワーク表示
  - MPRIS メディアチップと操作（`Super+M`）
- 状態/イベントを明示的に購読する行ベース IPC と `tessa-ctl` CLI
- include とイベントフックに対応した行ベース設定ファイル

Ubuntu 26.04、Zig 0.16.0、wlroots 0.19.2 でビルド・動作確認しています。
確認は主に headless の pixman バックエンドで、`grim`、`wtype`、Fcitx5 +
Mozc、`xwayland-satellite` 経由の X11 クライアントを使用しました。2 出力の
headless 環境で、出力ごとのワークスペース/パネル、両出力のセッションロック、
`wlr-randr` による出力管理も確認しています。イベントフック、イベント
ストリーム、カスタムステータス、カスタムランチャー項目、設定再読み込みは
`tests/smoke.sh`、`tests/output-persistence.sh`、パネルのスクリーンショットで
確認しました。ワークスペースごとの master/mosaic/grid/columns レイアウト、
2 倍 HiDPI パネル、再起動後の出力モード/位置/スケール/レイアウト復元も
`tests/smoke.sh`、`tests/output-persistence.sh`、`tests/layout-geometry.sh`、
`tests/customization.sh`、`tests/layout-helper.sh`、`tests/config-validation.sh`、
`tests/json-ipc.sh`、`tests/modes.sh`、`tests/panel-theme.sh`、
`tests/panel-popovers.sh`、`tests/clipboard.sh`、`tests/screenshot.sh`、
`tests/notifications.sh`、`tests/system-status.sh`、`tests/media.sh` で
検証しています。
**DRM/tty と実際のキーボード・マウスでの検証は、まだ実機で行う必要があります。**
[既知の制限](#既知の制限)も参照してください。

## なぜもう 1 つのタイル型 WM なのか

Tessa の目的は Hyprland を機能で上回ることではありません。より小さく、
まとまりのあるデスクトップを目指しています。

- **統合されたシェル。** バー、ランチャー、壁紙、タイル配置が 1 つの
  プロジェクトにまとまっています。色と挙動が統一されているのは、それが
  同じコードだからです。
- **違うレイアウト。** マスター/スタックに加えて、渦巻き状の「テセラ」
  モザイク、均等グリッド、等幅カラムがあります（`Super+T` で巡回）。Tessa
  という名前は tessellation（タイル張り）に由来します。
- **墨絵の視覚言語。** 藍色の紙、墨だまり、朱色の太陽、粒子、ガラスのような
  フローティングバー。一般的なステータスバーにテーマを載せただけのものでは
  ありません。
- **小さく直接的な実装。** Zig + wlroots、Pango 用の小さな C シム、行ベースの
  設定、行ベースの IPC。余計なレイヤーをできるだけ挟みません。
- **JavaScript / TypeScript ランタイムなし。** ShojiWM のようにシェルを TSX
  で自由に書くのではなく、固定された小さなシェルと設定を持ちます。ピクセル
  単位で UI をプログラムしたいなら ShojiWM、アニメーション・ブラー・巨大な
  プラグインエコシステムが欲しいなら Hyprland の方が適しています。Tessa は
  「静かで統合されていて、Zig で Hack できるコンポジタ」という niche に
  位置します。

ターミナルをゼロから実装することは意図的に避けています。デフォルトは
**kitty** です。foot が好みなら設定で `terminal = foot` にしてください。

## ビルド

必要なもの:

- Zig **0.16.0**（Ubuntu 26.04 の `zig` パッケージは 0.14 なので不足です）
- wlroots **0.19** の開発ファイル（`pkg-config --modversion wlroots-0.19`
  で見つかること）
- Wayland、xkbcommon、pixman、libdrm、libinput、libseat、libudev、EGL/GLES
- パネルと通知用の Cairo / Pango / GLib (GIO) 開発ファイル
- フォント: Inter、JetBrains Mono、Noto Sans CJK JP などの CJK フォント
- 任意: [`xwayland-satellite`](https://github.com/Supreeeme/xwayland-satellite)
  （X11 アプリ用。`xwayland = true` で自動起動）
- 任意: Fcitx5 + Mozc（または `zwp_input_method_v2` を実装した他の IME）
- 任意: 実行中の出力モード/位置/スケール変更用の `wlr-randr`
- 任意: デスクトップ通知用の D-Bus セッション bus

配布用パッケージ定義は `packaging/` と `debian/` にあります。
`packaging/arch/PKGBUILD` と debhelper 用 `debian/` が、コンポジタ、パネル、
CLI、セッションファイル、設定例をインストールします。詳細は
[packaging/README.md](packaging/README.md) を参照してください。

Ubuntu 26.04 の場合:

```sh
sudo apt install build-essential pkg-config git \
  libwayland-dev wayland-protocols libwlroots-0.19-dev \
  libxkbcommon-dev libpixman-1-dev libdrm-dev libinput-dev \
  libseat-dev libudev-dev libegl-dev libgles2-mesa-dev \
  libcairo2-dev libpango1.0-dev libglib2.0-dev libfontconfig1-dev \
  fonts-inter fonts-jetbrains-mono fonts-noto-cjk \
  xwayland xauth xterm fcitx5 fcitx5-mozc
```

`xwayland-satellite` はすべてのディストリビューションにパッケージされている
わけではありません。`PATH` の通った場所（例:
`~/.local/bin/xwayland-satellite`）にインストールするか、
`TESSA_XWAYLAND_BIN` に絶対パスを設定してください。Tessa は wlroots 内蔵の
XWayland ではなく satellite を使います。satellite がルートレス X11
ウィンドウを通常の xdg-shell トップレベルとしてコンポジタに渡します。

wlroots 0.19 を `/usr/local` 以下にソースからインストールした場合は、
`.pc` ファイルと共有ライブラリが見つかることを確認してください:

```sh
pkg-config --modversion wlroots-0.19
ldconfig -p | grep wlroots
```

ビルド:

```sh
chmod +x scripts/*.sh scripts/tessa-session   # 実行権限が失われている場合
./scripts/build.sh -Doptimize=ReleaseSafe
```

生成されるもの:

- `zig-out/bin/tessa` — コンポジタ
- `zig-out/bin/tessa-panel` — シェルパネル（出力ごとに 1 プロセス、Tessa が自動起動）
- `zig-out/bin/tessa-ctl` — スクリプト/拡張向けの状態・イベント・自動化クライアント

生成済みの Wayland プロトコルヘッダーは `protocol/` にコミットされているので、
wlroots 側に `xdg-shell-protocol.h` がなくてもビルドできます。

## 実行

### TTY から（最初のテストに推奨）

SSH 越しではなく、対象マシンのコンソールにログインし、アクティブな仮想
ターミナルから実行します:

```sh
cd /path/to/Tessa
PATH="$PWD/zig-out/bin:$PATH" ./zig-out/bin/tessa
```

wlroots が DRM バックエンドと libinput を自動検出します。Tessa は `PATH` から
出力ごとに 1 つずつ `tessa-panel` を起動するので、`zig-out/bin` を通すか、
バイナリをインストールしてください。デフォルトのターミナルは `kitty` です。
インストールするか、設定で `terminal = foot` に変更してください。

### ディスプレイマネージャ / セッションファイル

```sh
# ~/.local にインストール
./scripts/install-session.sh

# システム全体にインストール
sudo PREFIX=/usr/local ./scripts/install-session.sh
```

ログアウトし、GDM / SDDM / greetd で **Tessa** を選択してください。セッション
ファイルは `tessa-session` を実行し、自分自身のディレクトリを `PATH` の先頭に
追加してから `tessa` を起動します。

### SSH 越しの headless 開発

開発で使っている headless ワークフローです。まずコンポジタを起動します:

```sh
./scripts/run-headless.sh
```

別のシェルでスクリーンショットを撮ります:

```sh
./scripts/screenshot.sh /tmp/tessa.png
```

headless バックエンドには物理入力デバイスがないため、Tessa は標準 XKB
キーマップを持つフォールバックキーボードを作成します。これによりパネル、
IME、XWayland が正しく起動できます。マウスや状態変更は IPC、キーボード入力は
`wtype` で注入します:

```sh
XDG_RUNTIME_DIR=/tmp/tessa-headless WAYLAND_DISPLAY=wayland-0 \
  wtype "foot"
XDG_RUNTIME_DIR=/tmp/tessa-headless WAYLAND_DISPLAY=wayland-0 \
  wtype -k Return
```

`wtype` は virtual-keyboard プロトコルで接続し、現在キーボードフォーカスを
持つサーフェスへ入力します。TTY なしで IME やパネルのキーボード経路を
テストするときにも使います。

headless ワークフローの詳細は
[docs/DEVELOPMENT.ja.md](docs/DEVELOPMENT.ja.md)、拡張 API は
[docs/EXTENDING.ja.md](docs/EXTENDING.ja.md) を参照してください。

## 入力メソッド（IME）

![ランチャーでの日本語プリエディットと Fcitx5 の候補](docs/images/ime.png)

Tessa は `zwp_text_input_v3`（クライアント側）と `zwp_input_method_v2`
（入力メソッド側）を実装し、フォーカス、周辺テキスト、カーソル矩形、
プリエディット、確定文字列、削除をリレーします。入力メソッドのポップアップ
サーフェス（候補ウィンドウ）はテキストカーソルの下に配置され、画面端では
クランプされます。

**Fcitx5 + Mozc** で動作確認しています:

```sh
sudo apt install fcitx5 fcitx5-mozc
```

Tessa セッション内で Fcitx5 を起動してください（`TESSA_STARTUP` や
コンポジタの spawn コマンドなど）。Wayland ネイティブのクライアントでは
`GTK_IM_MODULE` / `QT_IM_MODULE` を設定する必要はありません。これらは
Wayland の text-input プロトコルを使うためです。X11 クライアントで IME を
使う場合は、Fcitx の XIM モジュールを別途インストール・設定してください。
XIM は Wayland の text-input 経路の外側です。

`Super+D` でランチャーを開いて入力すると、プリエディットが検索欄に描画され、
その下に Fcitx の候補ポップアップが表示されます。`Enter` で選択を確定し、
確定した文字列がランチャーの検索語に追加されます。

## X11 アプリケーション

![xwayland-satellite 経由で動く xeyes と xclock](docs/images/xwayland.png)

Tessa は Wayland ソケットの準備後に `xwayland-satellite` を起動し、選んだ
ディスプレイを `DISPLAY` としてエクスポートします。X11 アプリケーションは
ルートレスで動作し、各 X11 トップレベルは通常の Tessa ウィンドウとして
タイル、ワークスペース、フォーカス、タスクバーに参加します。Tessa は
`xdg-decoration` をサーバーサイドモードで広告するため、satellite は独自の
タイトルバーを描画しません。代わりに Tessa のアクセントカラーのボーダーが
使われます。

デフォルトではディスプレイを自動選択します（`xwayland_display = auto`）。
`:0` から順に、ソケットが存在しないディスプレイを選びます。必要なら `:1`
などの明示的な値を設定してください。XWayland を無効にするには
`xwayland = false` または `TESSA_NO_XWAYLAND=1` を使います。satellite が
`PATH` の外にある場合は
`TESSA_XWAYLAND_BIN=/path/to/xwayland-satellite` を設定してください。

X11 アプリケーションはスケール 1 で描画されます。フラクショナルスケーリング
と XWayland の XSETTINGS 連携はまだ実装されていません。

## ロックと idle

Tessa は `ext-session-lock-v1`、`ext-idle-notify-v1`、`idle-inhibit-v1` を
実装しています。ロッククライアントと idle デーモンは別のプログラムです:

```sh
sudo apt install swaylock swayidle
```

デフォルトでは `Super+Escape` が `swaylock` を起動します。別のロッカーを
使う場合は `bind = SUPER+Escape spawn <command>` で変更してください。ロック中は
通常のデスクトップのシーンツリーが隠れ、仮想キーボードからの入力は無視され、
ロックサーフェスがキーボード/ポインタフォーカスを受け取ります。ロック
クライアントがロック中に終了した場合、Tessa はデスクトップを露出させず
セッションを終了します。

`swayidle` と `wlopm` を組み合わせると、idle 時のロックと DPMS を自動化
できます:

```sh
sudo apt install wlopm
swayidle -w \
  timeout 300 'swaylock -f' \
  timeout 600 'wlopm --off "*"' \
  resume 'wlopm --on "*"'
```

idle 通知と inhibitor は動作し、動画プレイヤーなどは `idle-inhibit-v1` で
idle を抑制できます。Tessa は出力電源管理プロトコルも実装しているため、
`wlopm` で出力をオフ/オンできます。

## マルチモニタ

![独立したバーとワークスペースを持つ 2 つの headless 出力](docs/images/multi-monitor.png)

各出力に独立した壁紙、バー、アクティブワークスペースがあります。
`Super+1` … `Super+9` はフォーカス中の出力のワークスペースを変更します。
バーをクリック/スクロールすると、そのモニタのワークスペースを変更し、
その出力へフォーカスします。ランチャーはフォーカス中の出力に開き、新しい
ウィンドウもそこに配置されます。`Super+Shift+H/J/K/L` はまず同じ出力内で
入れ替え、その方向にウィンドウがない場合はフォーカス中のウィンドウを隣の
モニタへ移動します。

Tessa は `TESSA_PANEL_OUTPUT=<name>` を設定して、出力ごとに 1 つの
`tessa-panel` を自動起動します。自動起動を無効にした場合（`panel = false`
または `TESSA_NO_PANEL=1`）は、出力ごとに手動で起動してください:

```sh
TESSA_PANEL_OUTPUT=HEADLESS-1 tessa-panel
```

出力のモード、位置、スケール、変換は `wlr-randr` で変更できます。Tessa は
`wlr-output-management-unstable-v1` を実装しています。適用した設定は
`$XDG_CONFIG_HOME/tessa/outputs.conf`（または
`~/.config/tessa/outputs.conf`）に保存され、出力が再び現れたときに復元
されます。保存先はメイン設定の `output_config` または
`TESSA_OUTPUT_CONFIG` で変更できます。パネルは `wl_output` のスケールに
追従するため、整数倍の HiDPI でもバーとランチャーが鮮明に描画されます。
フラクショナルスケールでは出力スケールの切り上げ値を整数バッファスケール
として使い、X11 クライアントはスケール 1 のままです。

## 拡張

![外部ステータスとカスタムランチャー項目](docs/images/extensions.png)

Tessa はプラグイン VM を埋め込みません。拡張はコンポジタの Unix ソケット API
を話す通常のプロセスで、任意の言語で書けます。`tessa-ctl` が状態
スナップショット、構造化イベント、ステータス、コマンド操作を公開します。

```sh
tessa-ctl state
tessa-ctl state --json
tessa-ctl config
tessa-ctl config --json
tessa-ctl config-check
tessa-ctl events window-focus
tessa-ctl status weather "Tokyo 18C"
tessa-ctl layout grid
tessa-ctl dispatch reload
```

`state --json` と `config --json` はツール向けのスキーマバージョン付き
スナップショットを返します。`config-check` はファイル名/行番号付きの診断を
表示し、読み込み済み設定にエラーがある間は非ゼロで終了します。設定から
ログイン時のコマンド起動やイベントへの反応もできます。

```ini
startup = fcitx5 -d
hook = window-open notify-send "Window opened" "$TESSA_TITLE"
launcher_entry = Notes | foot -e nvim ~/notes.md
include = /home/you/.config/tessa/launcher-entries.conf
```

パネルは最大 8 件の拡張ステータスを表示し、クリック時にコマンドを実行できます。
イベントスキーマ、フックの環境変数、ステータス API の詳細は
[docs/EXTENDING.ja.md](docs/EXTENDING.ja.md) にあります。

## キーバインド

| バインド | 動作 |
| --- | --- |
| `Super+Return` | ターミナル（設定の `terminal`） |
| `Super+D` | ランチャー |
| `Super+V` | クリップボード履歴 |
| `Super+Shift+S` | 範囲/全画面スクリーンショット |
| `Super+M` | MPRIS メディア操作 |
| `Super+T` | マスター → モザイク → グリッド → カラムを巡回 |
| `Super+Q` | フォーカス中のウィンドウを閉じる |
| `Super+Shift+E` | Tessa を終了 |
| `Super+R` | 設定を再読み込み |
| `Super+1` … `Super+9` | ワークスペースを切り替え |
| `Super+Shift+1` … `Super+Shift+9` | ウィンドウをワークスペースへ移動 |
| `Super+H/J/K/L` | 左/下/上/右のウィンドウへフォーカス |
| `Super+Shift+H/J/K/L` | その方向のウィンドウと入れ替え。ない場合は隣の出力へ移動 |
| `Super+Space` | フローティング切り替え |
| `Super+F` | フルスクリーン切り替え |
| `Super+Escape` | セッションをロック（`swaylock` を実行。要インストール） |
| `Super+Tab` / `Super+Shift+Tab` | ウィンドウを巡回 |
| `Super+Ctrl+H/L` | マスター領域の比率を縮小/拡大 |
| `Super+Alt+H/L` | フローティングウィンドウの幅を縮小/拡大 |
| `Super+Alt+J/K` | フローティングウィンドウの高さを拡大/縮小 |

マウス:

- ウィンドウをクリックするとフォーカスします。タスクバーのチップをクリック
  するとそのウィンドウへフォーカスします。
- タスクバーのチップを右クリックするとそのウィンドウを閉じます。
- バーの上でスクロールするとワークスペースを巡回します。
- `Super+左ドラッグ` でフローティングウィンドウを移動、`Super+右ドラッグ` で
  リサイズします。
- クライアントサイドのタイトルバードラッグもフローティングウィンドウでは
  使えます。
- 花びら/`TESSA` のマークをクリックするか、`Super+D` でランチャーを開きます。
- `TESSA` マークを右クリックすると電源メニュー、時計をクリックすると
  カレンダーが開きます。`tessa-ctl panel calendar|power|clipboard` でも
  開けます。
- ランチャー内では入力で検索、`Up`/`Down`、`Enter`、`Esc`、または行の
  クリックで操作します。
- カレンダーでは `Left`/`Right` または矢印ボタンで月を移動し、`Home` で
  今日に戻ります。電源メニューでは `Up`/`Down`、`Enter`、`Esc`、または
  クリックで操作します。
- `Super+V` でクリップボード履歴が開きます。`Up`/`Down` と `Enter`、
  またはクリックで選んだ項目をクリップボードへ戻せます。履歴は最大 8 件、
  各 16 KiB までのテキストで、メモリ上にのみ保持します。
- `Super+Shift+S` でスクリーンショット UI が開きます。ドラッグで範囲選択、
  クリックで全画面、`Enter` でも全画面を保存し、`Esc` でキャンセルします。
  PNG は `screenshot_dir`（既定 `~/Pictures/Screenshots`）へ保存されます。
- MPRIS プレイヤーが動いているとバーにメディアチップが表示されます。
  クリックまたは `Super+M` で前へ/再生・一時停止/次へを操作できます。
  キーボードでは `Space`、`Left`、`Right` も使えます。

## 設定

サンプルをコピーします:

```sh
mkdir -p ~/.config/tessa
cp config/config.example ~/.config/tessa/config
```

形式は `key = value` です。`#` で始まる行はコメントです。実行中に `Super+R`
で設定を再読み込みできます。エラーのあるリロードは拒否され、以前の設定が
維持されます。`tessa-ctl config-check` で診断を確認できます。主なキー:

| キー | 意味 |
| --- | --- |
| `terminal` | `Super+Return` と `Terminal=true` の desktop アプリで使うコマンド |
| `gaps` | タイルウィンドウ間の隙間 |
| `outer_gaps` | タイル領域の外周の隙間 |
| `border_width` | アクティブ/非アクティブの枠の太さ |
| `master_ratio` | マスター領域の比率（0.15–0.9） |
| `master_count` | マスター列に縦積みするウィンドウ数 |
| `mosaic_ratio` | モザイクのスライス比率（0.25–0.85） |
| `mosaic_min_size` | グリッドへ切り替える前の最小モザイクタイル |
| `grid_columns` | グリッドの固定列数。`0` は `ceil(sqrt(n))` |
| `layout_helper` | 常駐外部レイアウトヘルパーのコマンド |
| `layout_helper_timeout` | ヘルパー応答のタイムアウト（ミリ秒、10–1000） |
| `layout` | 既定レイアウト: `master`、`mosaic`、`grid`、`columns`、`custom` |
| `layout_1` … `layout_9` | 保存済みの上書きがないワークスペースの初期レイアウト |
| `panel` | `tessa-panel` を自動起動 |
| `xwayland` | `xwayland-satellite` を起動し `DISPLAY` をエクスポート |
| `xwayland_display` | `auto`、または `:0` などの明示的なディスプレイ |
| `kb_layout` | XKB レイアウト（例: `us`、`us,de`） |
| `kb_variant` | XKB バリアント（任意） |
| `kb_options` | XKB オプション（例: `grp:alt_shift_toggle`） |
| `kb_model` | XKB モデル（任意） |
| `kb_rules` | XKB ルールファイル（任意） |
| `repeat_rate` | キーリピートの速度（回/秒） |
| `repeat_delay` | キーリピート開始までの待ち時間（ミリ秒） |
| `accent` | ボーダー、バー、ランチャーのアクセント色 |
| `bg` | 壁紙のベース背景色 |
| `font` | パネルの UI フォントファミリー |
| `include` | 別の設定ファイルを読み込む |
| `startup` | 起動時に 1 回実行するコマンド |
| `hook` | コンポジタイベントで実行するコマンド |
| `launcher_entry` | ランチャー項目を追加（`名前 \| コマンド`） |
| `output_config` | 出力モード/位置/スケール/変換とレイアウト上書きの保存先 |
| `bar_height` | バーの高さ（32〜96 論理ピクセル） |
| `bar_top_margin` | バーの上端からの距離（0〜64） |
| `bar_side_margin` | バーの左右マージン（0〜128） |
| `panel_bg` | バーの背景色 |
| `panel_fg` | バーの主要テキスト色 |
| `power_lock` | 電源メニューのロックで実行するコマンド |
| `power_suspend` | サスペンドのコマンド（既定 `systemctl suspend`） |
| `power_reboot` | 再起動のコマンド（既定 `systemctl reboot`） |
| `power_off` | 電源オフのコマンド（既定 `systemctl poweroff`） |
| `screenshot_dir` | スクリーンショット PNG の保存先（既定 `~/Pictures/Screenshots`） |
| `border_active` | フォーカス中ボーダー色（既定は `accent`） |
| `border_inactive` | 非フォーカス時ボーダー色 |
| `window-rule` | 宣言的ルール。詳細はカスタマイズガイド参照 |
| `workspace-rule` | ワークスペース別のレイアウト、隙間、マスター比率 |
| `mode` | 後続の `bind` が属する名前付き入力モードを開始 |

追加のバインドには XKB keysym 名を使います:

```ini
bind = SUPER+Return terminal
bind = SUPER+1 workspace 1
bind = SUPER+SHIFT+1 move-to-workspace 1
bind = SUPER+h focus left
bind = SUPER+SHIFT+h move left
bind = SUPER+ctrl+h ratio -0.03
```

利用可能なアクション: `terminal`、`spawn`、`close`、`quit`、`workspace`、
`move-to-workspace`、`focus`、`move`、`toggle-float`、`toggle-fullscreen`、
`focus-next`、`focus-prev`、`launcher`、`reload`、`ratio`、`toggle-layout`、
`set-layout`、`resize-width`、`resize-height`、`enter-mode`。

`Super+T` はフォーカス中のワークスペースのレイアウトを 4 種類巡回します。
実行中に選んだレイアウトは出力・ワークスペースごとに保持され、
`outputs.conf` に保存されます。`layout_N` は保存済み・実行中の上書きがない
ワークスペースの初期値だけを設定します。設定の再読み込みでは、上書きして
いないワークスペースだけが更新され、実行中の選択は維持されます。
`resize-width` と `resize-height` はフォーカス中のフローティングウィンドウを
ピクセル単位の差分でリサイズします。

ウィンドウルールは 1 行 1 ルールです。app-id、タイトル、出力を `*`/`?` の
パターンでマッチし、アクションを順に適用します。

```ini
window-rule = app-id=pavucontrol; float=true
window-rule = title=Picture-in-Picture; float=true; position=40,40
window-rule = app-id=firefox; workspace=2
window-rule = title=GIMP*; float=false
```

ルールはウィンドウのマップ時と設定再読み込み時に評価されます。
`tessa-ctl config` で実効設定と解析済みルールを確認できます。完全な
リファレンスは [docs/CUSTOMIZATION.ja.md](docs/CUSTOMIZATION.ja.md) にあります。

入力モードはバインドをまとめ、`enter-mode` で有効化します。

```ini
mode = resize
bind = h resize-width -30
bind = l resize-width 30
bind = Escape enter-mode default

mode = default
bind = SUPER+SHIFT+r enter-mode resize
```

モード中は Super なしでもそのモードのバインドがマッチします。グローバル
バインドは引き続き有効で、未割り当てのキーはフォーカス中のクライアントへ
渡ります。スクリプトからは `tessa-ctl mode resize` で切り替えられます。
アクティブモードは `tessa-ctl state` の `MODE <name>` に出ます。

ワークスペース別の調整も同じ `key=value; ...` 形式です。

```ini
workspace-rule = ws=2; layout=grid; gaps=4; outer-gaps=8; master-ratio=0.65
```

`layout = custom` でカスタムタイルを選べます。Tessa は設定されたヘルパーを
1 回起動して保持し、アクティブなタイルウィンドウと使用可能領域を送り、
フレーム矩形を受け取ります。`Super+T` の巡回には含まれないため、使う場合は
明示的にバインドしてください。

```ini
layout = custom
layout_helper = python3 ~/.config/tessa/layout.py
layout_helper_timeout = 100
bind = SUPER+SHIFT+T set-layout custom
```

タイムアウト、クラッシュ、不正な応答、矩形不足の場合は、その配置だけ
マスターへフォールバックします。プロトコルは
[docs/CUSTOMIZATION.ja.md](docs/CUSTOMIZATION.ja.md#外部レイアウトヘルパー)
にあります。

## 仕組み

- [docs/CUSTOMIZATION.ja.md](docs/CUSTOMIZATION.ja.md) — ウィンドウルール、
  レイアウト調整、外観、カスタマイズモデル
- [docs/ARCHITECTURE.ja.md](docs/ARCHITECTURE.ja.md) — コンポーネント、
  シーングラフ、IPC、layer-shell のサイズ計算、パネル描画
- [docs/ROADMAP.ja.md](docs/ROADMAP.ja.md) — 未実装の機能と今後の予定
- [docs/DEVELOPMENT.ja.md](docs/DEVELOPMENT.ja.md) — SSH / headless 開発
  ワークフロー
- [docs/EXTENDING.ja.md](docs/EXTENDING.ja.md) — イベント、フック、
  ステータス、`tessa-ctl` による拡張

概要:

```text
tessa (wlroots コンポジタ, Zig)
  ├─ backend: DRM / headless / ネストした Wayland
  ├─ wlr_scene: 壁紙 < layer background < ウィンドウ < floating < トップバー
  │              < fullscreen < ランチャーオーバーレイ
  ├─ マスター/スタック + モザイク + グリッド + カラム、9 ワークスペース、
  │  フローティング、フルスクリーン
  └─ IPC: $XDG_RUNTIME_DIR/tessa.sock
                 ▲
tessa-panel × 出力数 (Wayland クライアント, Zig + Cairo/Pango)
  ├─ background layer（墨と太陽の壁紙）
  ├─ top layer（フローティングタスクバー）
  └─ overlay layer（ランチャー、排他的キーボード）
```

パネルはサーフェスごとに 3 枚の `wl_shm` バッファを使い、Cairo で描画し、
テキストは `panel/text.c` の小さな C シム（Pango）経由でレンダリングします。
コンポジタとパネルは意図的に単純な行プロトコルで通信します:

```text
STATE
ACTIVE 1
OCC 1 2
...
WIN\t1\t1\t1\t0\t0\tkitty\tnotes\teDP-1\t40\t30\t1100\t700
END

CMD workspace 3 eDP-1
CMD focus 4
CMD close 4
CMD spawn kitty
CMD launcher [query]
CMD layout [name] [output]
CMD resize <dx> <dy>
CMD float <id>
CMD quit
```

IPC ソケットは `$XDG_RUNTIME_DIR` 以下にモード `0600` で作成されます。

## 既知の制限

重要な未対応・未検証項目です。

- **DRM / キーボード / マウスは実機で未検証。** 開発は headless バックエンドで
  `wtype` / Fcitx5 とソフトウェアレンダリングを使って行っています。実際の
  ポインタ操作と DRM モード設定は、物理環境でのテストが必要です。
- **フラクショナルスケーリングは部分的。** パネルは整数の Wayland バッファ
  スケールを使い、X11 クライアントはスケール 1 で描画されます。整数倍の
  HiDPI は動作しますが、フラクショナルなデスクトップスケーリングには専用の
  対応が必要です。
- **出力の無効化は永続化されません。** `wlr-randr --off` は実行中のみ有効で、
  保存された出力エントリは次回起動時にその出力を有効化します。
- **パネルは出力ごとに 1 プロセス。** バーが独立し、クラッシュの影響も
  そのモニタだけに収まりますが、単一のマルチサーフェスパネルよりメモリを
  使います。
- **ロック画面の検証は基本的な範囲。** `ext-session-lock-v1` を実装し、
  最小限のロッククライアントで確認していますが、実際の swaylock/PAM 環境は
  物理セッションで追加検証が必要です。ロック中にロッククライアントが
  消えた場合、Tessa は黙ってアンロックせずセッションを終了します。
- **idle のタイミングは外部ツール任せ。** Tessa は idle 通知、inhibitor、
  出力電源管理を提供します。自動ブランクやロックには `swayidle` / `wlopm`
  などを別途起動してください。
- **クリップボード履歴はテキストのみ・メモリ上のみ。** 最大 8 件、各 16 KiB
  まで保持し、ディスクには書き込みません。`wlr-data-control-v1` はセッション
  内のクライアントへ公開されるため、信頼されたアプリはキーボードフォーカス
  なしでセレクションを読めます。セッション内アプリを信頼できる前提で使って
  ください。
- **通知は意図的に最小限。** パネルが `org.freedesktop.Notifications` を所有し、
  プレーンテキストのトースト表示、置換、閉じる、期限切れに対応します。
  アクション、マークアップ、アイコン検索は未対応です。また D-Bus 名を所有
  したパネルの出力にだけ表示され、出力間ルーティングは今後の課題です。
- **システム/メディア表示は基本機能のみ。** バッテリーは
  `/sys/class/power_supply`、ネットワークはデフォルトルートと `operstate` を
  使います。トレイと音量操作はまだ未対応です。MPRIS は最初に見つかった
  プレイヤーを操作し、アルバムアートは表示しません。
- **IME のカバー範囲。** Wayland の text-input-v3 クライアントとパネルは
  Fcitx5 + Mozc で確認済みです。X11/XIM の入力メソッド、特殊なレイアウトの
  デッドキー、スクロール中の入力ポップアップ再配置は未確認です。
- **XWayland には `xwayland-satellite` が必要。** Tessa には同梱されません。
  ない場合、X11 アプリは起動しません。Wayland クライアントには影響しません。
- **ポータル、画面共有、ガンマ、出力設定 UI は未実装。**
- **拡張は信頼されたローカルプロセス。** セッションユーザーの全権限で動き、
  サンドボックスはありません。状態/設定スナップショットはバージョン付き JSON
  ですが、コマンド/イベントは引き続き行ベースで、JSON-RPC のリクエスト/
  バージョン交渉は未対応です。ステータスは短い文字列 8 件までです。
- layer-shell とキーボードフォーカスは wlroots 0.19 の unstable API を
  使っています。パッケージング時は wlroots のバージョンを固定してください。
- ランチャーは `.desktop` ファイルを走査します。インストールされている
  アプリが少ないと一覧も短くなります。アイコンテーマはまだ使わず、文字の
  モノグラムタイルを表示します。

## ライセンス

Tessa は **MIT License** で公開されています。[LICENSE](LICENSE) を参照して
ください。

## クレジット

wlroots と tinywl の例をイベントループ構造の参考にして、このプロジェクト用に
ゼロから実装しました。シェルの描画には Cairo/Pango を使っています。Pango を
C シムに隔離しているのは、Zig 0.16 の translate-c が GLib の `_Pragma`
非推奨マクロを処理できないためです。テスト用ターミナルは foot、デフォルトの
ターミナルは kitty です。
