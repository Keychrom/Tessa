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
- マスター/スタックレイアウトと、Tessa 独自の「モザイク」スパイラル
  レイアウト（`Super+T`）
- 9 ワークスペース、フローティング、フルスクリーン、クリックでフォーカス
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
- コンポジタとパネル間のシンプルな行ベース IPC
- 行ベースの設定ファイル

Ubuntu 26.04、Zig 0.16.0、wlroots 0.19.2 でビルド・動作確認しています。
確認は主に headless の pixman バックエンドで、`grim`、`wtype`、Fcitx5 +
Mozc、`xwayland-satellite` 経由の X11 クライアントを使用しました。
**DRM/tty と実際のキーボード・マウスでの検証は、まだ実機で行う必要があります。**
[既知の制限](#既知の制限)も参照してください。

## なぜもう 1 つのタイル型 WM なのか

Tessa の目的は Hyprland を機能で上回ることではありません。より小さく、
まとまりのあるデスクトップを目指しています。

- **統合されたシェル。** バー、ランチャー、壁紙、タイル配置が 1 つの
  プロジェクトにまとまっています。色と挙動が統一されているのは、それが
  同じコードだからです。
- **違うレイアウト。** マスター/スタックに加えて、渦巻き状の「テセラ」
  モザイクレイアウト（`Super+T`）があります。Tessa という名前は tessellation
  （タイル張り）に由来します。
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
- パネル用の Cairo / Pango 開発ファイル
- フォント: Inter、JetBrains Mono、Noto Sans CJK JP などの CJK フォント
- 任意: [`xwayland-satellite`](https://github.com/Supreeeme/xwayland-satellite)
  （X11 アプリ用。`xwayland = true` で自動起動）
- 任意: Fcitx5 + Mozc（または `zwp_input_method_v2` を実装した他の IME）

Ubuntu 26.04 の場合:

```sh
sudo apt install build-essential pkg-config git \
  libwayland-dev wayland-protocols libwlroots-0.19-dev \
  libxkbcommon-dev libpixman-1-dev libdrm-dev libinput-dev \
  libseat-dev libudev-dev libegl-dev libgles2-mesa-dev \
  libcairo2-dev libpango1.0-dev libfontconfig1-dev \
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
- `zig-out/bin/tessa-panel` — シェルパネル（Tessa が自動起動）

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
`tessa-panel` を起動するので、`zig-out/bin` を通すか、バイナリをインストール
してください。デフォルトのターミナルは `kitty` です。インストールするか、
設定で `terminal = foot` に変更してください。

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
[docs/DEVELOPMENT.ja.md](docs/DEVELOPMENT.ja.md) を参照してください。

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

## キーバインド

| バインド | 動作 |
| --- | --- |
| `Super+Return` | ターミナル（設定の `terminal`） |
| `Super+D` | ランチャー |
| `Super+T` | マスター ↔ モザイクレイアウト切り替え |
| `Super+Q` | フォーカス中のウィンドウを閉じる |
| `Super+Shift+E` | Tessa を終了 |
| `Super+R` | 設定を再読み込み |
| `Super+1` … `Super+9` | ワークスペースを切り替え |
| `Super+Shift+1` … `Super+Shift+9` | ウィンドウをワークスペースへ移動 |
| `Super+H/J/K/L` | 左/下/上/右のウィンドウへフォーカス |
| `Super+Shift+H/J/K/L` | その方向のウィンドウと入れ替え |
| `Super+Space` | フローティング切り替え |
| `Super+F` | フルスクリーン切り替え |
| `Super+Escape` | セッションをロック（`swaylock` を実行。要インストール） |
| `Super+Tab` / `Super+Shift+Tab` | ウィンドウを巡回 |
| `Super+Ctrl+H/L` | マスター領域の比率を縮小/拡大 |

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
- ランチャー内では入力で検索、`Up`/`Down`、`Enter`、`Esc`、または行の
  クリックで操作します。

## 設定

サンプルをコピーします:

```sh
mkdir -p ~/.config/tessa
cp config/config.example ~/.config/tessa/config
```

形式は `key = value` です。`#` で始まる行はコメントです。実行中に `Super+R`
で設定を再読み込みできます。主なキー:

| キー | 意味 |
| --- | --- |
| `terminal` | `Super+Return` と `Terminal=true` の desktop アプリで使うコマンド |
| `gaps` | タイルウィンドウ間の隙間 |
| `outer_gaps` | タイル領域の外周の隙間 |
| `border_width` | アクティブ/非アクティブの枠の太さ |
| `master_ratio` | マスター領域の比率（0.15–0.9） |
| `layout` | `master` または `mosaic` |
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
`focus-next`、`focus-prev`、`launcher`、`reload`、`ratio`、`toggle-layout`。

## 仕組み

- [docs/ARCHITECTURE.ja.md](docs/ARCHITECTURE.ja.md) — コンポーネント、
  シーングラフ、IPC、layer-shell のサイズ計算、パネル描画
- [docs/ROADMAP.ja.md](docs/ROADMAP.ja.md) — 未実装の機能と今後の予定
- [docs/DEVELOPMENT.ja.md](docs/DEVELOPMENT.ja.md) — SSH / headless 開発
  ワークフロー

概要:

```text
tessa (wlroots コンポジタ, Zig)
  ├─ backend: DRM / headless / ネストした Wayland
  ├─ wlr_scene: 壁紙 < layer background < ウィンドウ < floating < トップバー
  │              < fullscreen < ランチャーオーバーレイ
  ├─ マスター/スタック + モザイクタイル、9 ワークスペース、フローティング、
  │  フルスクリーン
  └─ IPC: $XDG_RUNTIME_DIR/tessa.sock
                 ▲
tessa-panel (Wayland クライアント, Zig + Cairo/Pango)
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
WIN\t1\t1\t1\t0\t0\tkitty\tnotes
END

CMD workspace 3
CMD focus 4
CMD close 4
CMD spawn kitty
CMD launcher [query]
CMD layout
CMD float <id>
CMD quit
```

IPC ソケットは `$XDG_RUNTIME_DIR` 以下にモード `0600` で作成されます。

## 既知の制限

重要な未対応・未検証項目です。

- **DRM / キーボード / マウスは実機で未検証。** 開発は headless バックエンドで
  `wtype` / Fcitx5 とソフトウェアレンダリングを使って行っています。実際の
  ポインタ操作と DRM モード設定は、物理環境でのテストが必要です。
- **パネルは 1 枚のみ。** バーと壁紙は最初の出力に作成されます。複数出力でも
  ウィンドウはタイルされますが、アクティブワークスペースとバーは共有です。
- **ロック画面の検証は基本的な範囲。** `ext-session-lock-v1` を実装し、
  最小限のロッククライアントで確認していますが、実際の swaylock/PAM 環境は
  物理セッションで追加検証が必要です。ロック中にロッククライアントが
  消えた場合、Tessa は黙ってアンロックせずセッションを終了します。
- **idle のタイミングは外部ツール任せ。** Tessa は idle 通知、inhibitor、
  出力電源管理を提供します。自動ブランクやロックには `swayidle` / `wlopm`
  などを別途起動してください。
- **スケールは 1 固定。** HiDPI の出力スケールは設定できません。X11
  クライアントもスケーリングされません。
- **IME のカバー範囲。** Wayland の text-input-v3 クライアントとパネルは
  Fcitx5 + Mozc で確認済みです。X11/XIM の入力メソッド、特殊なレイアウトの
  デッドキー、スクロール中の入力ポップアップ再配置は未確認です。
- **XWayland には `xwayland-satellite` が必要。** Tessa には同梱されません。
  ない場合、X11 アプリは起動しません。Wayland クライアントには影響しません。
- **ポータル、画面共有、ガンマ、出力設定 UI は未実装。**
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
