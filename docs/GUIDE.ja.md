**日本語** | [English](GUIDE.md)

<!-- tessa-site-notice:start -->
> [!NOTE]
> このドキュメントは Web サイトに移植されました。最新版は <https://keychrom.github.io/ja/docs/guide/> を参照してください。
<!-- tessa-site-notice:end -->

# Tessa セットアップ & カスタマイズ完全ガイド

> **Tessa を初めて使う場合** は[クイックスタート](QUICKSTART.ja.md)から始めてください。インストール、最初の起動、基本のキー操作をまとめています。

このガイドは、現在の Tessa ツリーで使えるセットアップ方法とカスタマイズ
項目を一か所にまとめたものです。0.7 ロードマップまでの実装を対象にし、
special ワークスペース、シェル v2、エフェクトヘルパー、性能計測、対話型
設定エディタも含みます。

Tessa は **wlroots ベースのコンポジタ本体 `tessa`**、**タスクバー／
ランチャー／壁紙を担当する `tessa-panel`**、**自動化用の `tessa-ctl`** の
3 プロセス構成です。Waybar、Rofi、wofi などの外部シェルは不要です。

- コンポジタ: `/usr/bin/tessa`（ソースビルドでは `zig-out/bin/tessa`）
- パネル: `/usr/bin/tessa-panel`（出力ごとに 1 プロセス）
- CLI: `/usr/bin/tessa-ctl`

設定はフラットな `key = value` 形式です。設定の再読み込みは `Super+R`、
診断は `tessa-ctl config-check`、実効値の確認は `tessa-ctl config` で行います。

---

## 1. 必要環境

### 必須

Ubuntu / Debian で通常利用する場合は、2.1 節の `install.sh` を使います。
Arch Linux では 2.2 節の PKGBUILD を使います。実行時
ライブラリはパッケージマネージャーが導入します。以下の Zig / wlroots 開発
環境はソースビルドとパッケージビルド時だけ必要です。

- Linux（開発・検証は Ubuntu 26.04）
- Zig **0.17.0**
- wlroots **0.20** 開発ファイル
- Wayland、wayland-protocols 1.47 以降、xkbcommon、pixman、libdrm、libinput、
  seat/udev、EGL/GLES
- Cairo、Pango、GLib/GIO、gdk-pixbuf（パネル、通知、MPRIS アートワーク用）
- フォント: Inter、JetBrains Mono、Noto Sans CJK JP など
- ターミナル: 既定は `kitty`。`terminal = foot` などで変更可能

Ubuntu 26.04 の例（ディストリビューションの Zig が古い場合は上流の Zig 0.17
を導入してください）:

```sh
sudo apt install build-essential pkg-config git \
  libwayland-dev wayland-protocols \
  libxkbcommon-dev libpixman-1-dev libdrm-dev libinput-dev \
  libseat-dev libudev-dev libegl-dev libgles2-mesa-dev \
  libcairo2-dev libpango1.0-dev libglib2.0-dev libfontconfig1-dev \
  fonts-inter fonts-jetbrains-mono fonts-noto-cjk \
  xwayland xauth xterm fcitx5 fcitx5-mozc
```

Ubuntu 26.04 の wlroots は 0.19 で、0.20 は提供されていません。2.1 節の
インストーラーは wlroots 0.20 と scenefx 0.5 を `/opt/tessa` にビルドする
ため、完全なツールチェーンが必要な場合はそちらを使ってください。

Arch Linux の公式 `zig`（0.17）と `wlroots0.20` はこのツリーと一致します。
2.2 節に従って導入してください。

wlroots を `/usr/local` に自前ビルドした場合は、`.pc` と共有ライブラリが
見えることを確認してください。

```sh
pkg-config --modversion wlroots-0.20
ldconfig -p | grep wlroots
```

### 任意

- `xwayland-satellite`: X11 アプリ。`xwayland = true` のとき自動起動
- `wlr-randr`: 出力モード、位置、スケール、変換の実行時変更
- `grim`: スクリーンショットのテストや手動取得
- `wtype`: キーボード注入によるテスト
- `swaylock`: セッションロック（既定の `Super+Escape`）
- `swayidle`、`wlopm`: idle と出力電源管理
- `wpctl`（PipeWire）、`pactl`（PulseAudio）、`amixer`（ALSA）: 音量
- `xdg-desktop-portal`、`xdg-desktop-portal-wlr`、PipeWire: 画面共有
- Fcitx5 + Mozc: Wayland IME と XIM
- scenefx **0.5**: 既定の角丸と背景ブラー用（`-Dscenefx=false` で無効化）

---

## 2. インストールまたはビルド

### 2.1 Ubuntu / Debian インストーラー

通常のインストールには
[Ubuntu / Debian インストーラー](https://keychrom.github.io/ja/docs/install-script/)
を使います。現在の `0.2.5` ツリー、Zig 0.17、wlroots 0.20、scenefx 0.5、
不足している Wayland ライブラリを `/opt/tessa` にビルドし、ディストリビューションの
Wayland ライブラリは置き換えません。

```sh
git clone https://github.com/Keychrom/Tessa.git
cd Tessa
./install.sh --check
./install.sh
```

インストーラーが配置するもの:

- `/opt/tessa/bin/tessa`、`tessa-panel`、`tessa-ctl`
- `/opt/tessa/bin/tessa-session`
- 上記 4 コマンドの `/usr/local/bin` ラッパー
- `/usr/share/wayland-sessions/tessa.desktop`
- `/usr/share/xdg-desktop-portal/portals/tessa.portal`
- 設定例と Vermilion Ink テーマ

既定ではターミナル、フォント、fcitx5 + Mozc、ポータル、PipeWire も導入します。
これらを入れない場合は `--minimal`、scenefx のエフェクトなしでビルドする場合は
`--plain` を使います。インストーラーは試験的なため、実行前に
[テスト状況](https://keychrom.github.io/ja/docs/install-script/)を確認してください。

ログアウトし、GDM / SDDM / greetd などのセッション選択で **Tessa** を選びます。
セッションエントリがインストール済みのコンポジタとパネルを直接起動します。
3.2 節のソース用セッションインストーラーは開発時だけ必要です。

インストールの確認:

```sh
tessa-ctl config-check
command -v tessa tessa-panel tessa-ctl
```

以前 `/usr/local` に手動インストールした Tessa がある場合は、どちらか一方に
揃えてください。インストーラーは既存の手動インストールが使う
`/usr/local/bin` のラッパーとセッションエントリを置き換えます。

### 2.2 NixOS

リポジトリはパッケージと NixOS モジュールを含む flake です。モジュールは
コンポジタ、セッションエントリ、ポータル、任意の XWayland サテライトを
導入します:

```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.tessa.url = "github:Keychrom/Tessa";

  outputs = { self, nixpkgs, tessa, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        tessa.nixosModules.default
        {
          programs.tessa.enable = true;
          services.displayManager.sddm.enable = true;
          programs.tessa.extraPackages = with pkgs; [ foot grim ];
        }
      ];
    };
  };
}
```

`nix build github:Keychrom/Tessa` で既定の scenefx パッケージをビルドできます。
3D アクセラレーションのない VM では
`tessa.packages.x86_64-linux.tessa-plain` を使い、
`environment.sessionVariables.WLR_RENDERER = "pixman";` を設定してください。
モジュールのオプション、自動ログイン、VM の完全な設定例はリポジトリの
`packaging/nix/README.ja.md` にあります。

### 2.3 Arch Linux

Arch の公式リポジトリは `zig` 0.17、`wlroots0.20`（0.20 系）、`scenefx`
0.5 を提供しており、このツリーと一致します。ビルド依存を導入してください:

```sh
sudo pacman -Syu --needed base-devel git zig wlroots0.20 scenefx \
  wayland wayland-protocols libxkbcommon libinput pixman libdrm \
  libegl mesa cairo pango glib2
```

続いて Tessa を PKGBUILD からビルドします:

```sh
git clone https://github.com/Keychrom/Tessa.git
cd Tessa/packaging/arch
makepkg -si
```

`tessa-git` はバイナリ、セッションエントリ、設定例、ポータル設定、
man ページ、ドキュメントを `/usr` 以下へ導入します。

確認:

```sh
tessa-ctl config-check
command -v tessa tessa-panel tessa-ctl
```

#### 推奨パッケージ

ターミナル、出力・スクリーンショット用ツール、画面共有ポータル、
セッションユーティリティ、日本語入力環境を導入します:

```sh
sudo pacman -S --needed foot kitty wlr-randr grim swaylock swayidle wlopm \
  dbus xdg-desktop-portal xdg-desktop-portal-wlr pipewire \
  fcitx5 fcitx5-mozc
```

X11 アプリケーションを使う場合は、AUR の `xwayland-satellite-git` を導入します:

```sh
git clone https://aur.archlinux.org/xwayland-satellite-git.git
cd xwayland-satellite-git
makepkg -si
```

AUR ヘルパーを使う場合:

```sh
paru -S foot kitty wlr-randr grim swaylock swayidle wlopm dbus \
  xdg-desktop-portal xdg-desktop-portal-wlr pipewire \
  fcitx5 fcitx5-mozc xwayland-satellite-git
```

PKGBUILD は `scenefx` に依存し、既定で角丸とブラーを有効にします。
plain wlroots シーンでビルドする場合はソースビルドに
`-Dscenefx=false` を渡します。0.2.4 の Arch パッケージは
0.16/0.19 の AUR ツールチェーンで実機確認しています。0.2.5 の PKGBUILD は
公式の `zig` と `wlroots0.20` で Arch Linux 実機にビルド・インストールし、
headless スイート全 78 テストスクリプトが plain／scenefx の両構成で成功しています。
`makepkg` が ABI や依存関係のエラーを出した場合は、`zig version` が 0.17.x、
`pkg-config --modversion wlroots-0.20` が 0.20.x を返すことを確認して
ください。

### 2.4 ソースからビルド（開発向け）

リポジトリのルートで実行します。

```sh
chmod +x scripts/*.sh scripts/tessa-session
./scripts/build.sh
```

リリースビルド:

```sh
./scripts/build.sh -Doptimize=ReleaseSafe
```

`scripts/build.sh` は Zig 0.17.x を要求します。
`ZIG=/path/to/zig` で明示指定できます。Arch では公式の `zig` が対象です。

生成物:

- `zig-out/bin/tessa`
- `zig-out/bin/tessa-panel`
- `zig-out/bin/tessa-ctl`

テストを実行する場合:

```sh
sh tests/smoke.sh
sh tests/animations.sh
sh tests/output-rules.sh
sh tests/config-watch.sh
```

全テストは `sh tests/*.sh` で実行できます。テストは不足している任意依存
（`foot`、`grim`、`wlr-randr`、PipeWire、D-Bus など）に応じてスキップ
します。`tests/effects.sh` は scenefx ビルドでのみ実行されます。

### scenefx ビルド（角丸・背景ブラー）

既定ビルドは scenefx 0.5 の GLES2 レンダラーを使い、角丸と背景ブラーを
有効にします。scenefx 0.5 を導入して、通常どおりビルドします。

```sh
./scripts/build.sh -Doptimize=ReleaseSafe
```

pixman と GL の両方で動作する plain wlroots シーンにする場合は、
scenefx を明示的に無効にします。

```sh
./scripts/build.sh -Doptimize=ReleaseSafe -Dscenefx=false
```

scenefx を `/usr/local` 以外へ入れた場合は、ビルド時と実行時に
pkg-config／ライブラリパスを設定してください。

```sh
export PKG_CONFIG_PATH=$HOME/.local/lib/x86_64-linux-gnu/pkgconfig:$PKG_CONFIG_PATH
export LD_LIBRARY_PATH=$HOME/.local/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH
./scripts/build.sh -Dscenefx=true
```

`corner_radius`、`blur` などは `-Dscenefx=false` ビルドでも読み込まれますが、
視覚効果はありません。

### パネルのビルド

既定ビルドにはシェルパネル `tessa-panel` が含まれます。コンポジタと
`tessa-ctl` だけをビルド・インストールする場合は、パネルを無効にします:

```sh
./scripts/build.sh -Doptimize=ReleaseSafe -Dpanel=false
```

パネルが使う Cairo、Pango、GdkPixbuf、GIO のビルド依存も不要になります。
代わりに外部の layer-shell バーやランチャーを起動してください。内蔵パネル、
ランチャー、通知、トレイ、壁紙は利用できず、設定の `panel = true` は無視
されます。既定値は `-Dpanel=true` のままです。

片方だけをビルドする場合は、名前付きステップを使います:

```sh
./scripts/build.sh panel       # tessa-panel のみ
./scripts/build.sh compositor  # tessa のみ
```

パネルは実行時に Tessa の IPC ソケットを必要とします。別コンポジタで使う
場合は、次の互換ブリッジを使います。

### Hyprland / Niri で Tessa Panel を動かす

`tools/tessa-panel-compat.py` は Python 3 標準ライブラリだけで動く互換
ブリッジです。Hyprland/Niri の状態をパネル向けの `WIN`/`OUT`/`FOCUSED` IPC
行に変換し、出力ごとに `tessa-panel` を起動します。パネルからの `spawn`、
`workspace`、`focus`、`close` はホスト側のコマンドに変換します。

パネルをビルドし、Hyprland/Niri セッション内でブリッジを起動します:

```sh
./scripts/build.sh panel
python3 tools/tessa-panel-compat.py
```

パッケージ版では `tessa-panel-compat` が `PATH` に入ります。`tools/` の
パスではなくこちらを使ってください。ブリッジは
`HYPRLAND_INSTANCE_SIGNATURE` または `NIRI_SOCKET` から自動判定します。
明示する場合は `--compositor hyprland` / `--compositor niri` を付けます。

`$XDG_RUNTIME_DIR/tessa.sock` で待ち受け（`--socket` または `TESSA_IPC` で
変更可）、`TESSA_PANEL_OUTPUT` と出力の make/model/serial を設定してパネルを
起動します。終了したパネルは再起動します。通知とシステムサービスの
オーナーは最初の出力だけに割り当てます。

ランチャーとスイッチャーはコンポジタのキーバインドから開けます:

```ini
# Hyprland
bind = SUPER, Space, exec, tessa-panel-compat --send launcher
bind = ALT, Tab, exec, tessa-panel-compat --send switcher
bind = ALT SHIFT, Tab, exec, tessa-panel-compat --send switcher-prev
```

Niri では `binds` から `tessa-panel-compat --send launcher` や
`tessa-panel-compat --send switcher` を起動してください。ほかのビューは
`--send control`、`--send wifi`、`--send bluetooth`、`--send notifications`、
`--send calendar` で開けます。

パネルは通常の Tessa 設定（`panel_modules`、`bar_layout`、テーマ、フォント
など）を読みます。別ファイルを使う場合は起動前に `TESSA_CONFIG` を設定して
ください。`tessa-panel` が `PATH` にない場合は
`--panel /path/to/tessa-panel` を指定します。

現在の制限:

- バーはワークスペース 1〜9 のみ。Hyprland の特殊/名前付きワークスペースや、
  範囲外の動的な Niri ワークスペースは変換されません。
- Tessa 拡張、status エントリ、`tessa-ctl` 自動化は使えません。ブリッジに
  拡張ホストはありません。設定エディタなど `tessa-ctl` を呼ぶ操作は動かない
  ので、設定ファイルを直接編集してください。
- ウィンドウスイッチャーは wlr-screencopy のクロップかモノグラムに
  フォールバックします。ライブのウィンドウごとキャプチャには、ホスト側の
  ext キャプチャプロトコルが必要です。
- ブラーと角丸はコンポジタ側の機能です。Hyprland/Niri は Tessa の scenefx
  エフェクトをパネルサーフェスへ適用しません。
- パネルの電源メニューの「終了」は無視されます。ログアウトはホスト側の
  コンポジタから行ってください。
- Alt+Tab は押して開く方式で、ホールドして巡回する方式ではありません。
  Tab/矢印で選択し、Enter で確定、Escape でキャンセルします。
- 起動前に mako/dunst などの通知デーモンと、他のトレイ実装を停止して
  ください。同じ D-Bus 名を取り合います。

パネルを起動せずに変換結果を確認できます:

```sh
python3 tools/tessa-panel-compat.py --print-state
python3 tools/tessa-panel-compat.py --no-spawn --verbose
```

`--print-state` はパネルが受け取る状態をそのまま出力するので、出力名、
ワークスペース、ウィンドウ ID の対応を確認するのに便利です。

---

## 3. 起動とインストール

### 3.1 TTY から直接起動

物理コンソール（SSH ではなく、ログイン中の TTY）で実行します。
パッケージ版なら:

```sh
tessa
```

ソースビルドなら:

```sh
cd /path/to/Tessa
PATH="$PWD/zig-out/bin:$PATH" ./zig-out/bin/tessa
```

wlroots が DRM バックエンドと libinput を自動検出します。パネルは
`PATH` 上の `tessa-panel` を出力ごとに自動起動します。

DRM バックエンドは logind/seat のアクティブセッションと入力デバイスへの
アクセス権が必要です。root で直接起動するのではなく、通常ユーザーで
ログインした TTY から実行してください。SSH セッションからは DRM を
使えないため、headless またはネストした Wayland を使ってください。

終了は `Super+Shift+E` または `tessa-ctl quit` です。

### 3.2 ディスプレイマネージャー用セッション

Ubuntu / Debian インストーラーと Arch の `tessa-git` はセッションエントリを
導入済みです。この手順はソースビルドから実行する場合だけ使います:

```sh
# ~/.local 以下へ
./scripts/install-session.sh

# システム全体へ（sudo）
sudo PREFIX=/usr/local ./scripts/install-session.sh
```

scenefx なしの plain ビルドにする場合は、どちらかのコマンドに
`-Dscenefx=false` を追加します（GPU が GLES2 を提供できない場合など）。

```sh
./scripts/install-session.sh -Dscenefx=false
```

インストーラーは次を配置します。

- `tessa`、`tessa-panel`、`tessa-ctl`
- `tessa-session`
- `wayland-sessions/tessa.desktop`
- `xdg-desktop-portal/portals/tessa.portal`

ログアウト後、GDM/SDDM/greetd などのセッション選択で **Tessa** を選びます。
`tessa-session` は自分のディレクトリを `PATH` の先頭へ追加し、
`XDG_CURRENT_DESKTOP=Tessa` などを設定して `tessa` を起動します。

ディストリビューション向けのパッケージ定義は `packaging/arch/PKGBUILD` と
`debian/` にあります。インストール内容と依存関係は
[`packaging/README.ja.md`](../packaging/README.ja.md) を参照してください。

### 3.3 headless 開発

SSH 上で動かす場合の開発用スクリプトです。

```sh
./scripts/run-headless.sh
```

別のシェルで:

```sh
./scripts/screenshot.sh /tmp/tessa.png
```

`run-headless.sh` は次を設定します。

- `XDG_RUNTIME_DIR=/tmp/tessa-headless`（`TESSA_RUNTIME_DIR` で変更可）
- `WLR_BACKENDS=headless`
- `WLR_RENDERER=pixman`
- `WLR_HEADLESS_OUTPUTS=1`（環境変数で変更可）
- `PATH` に `zig-out/bin`

headless で複数出力を試す場合:

```sh
WLR_HEADLESS_OUTPUTS=2 ./scripts/run-headless.sh
```

### 3.4 ネストした Wayland

既存の Wayland セッション内でウィンドウとして試す場合は、wlroots の
Wayland バックエンドを使えます。

```sh
WLR_BACKENDS=wayland WLR_RENDERER=gles2 \
  PATH="$PWD/zig-out/bin:$PATH" ./zig-out/bin/tessa
```

### 3.5 XWayland / X11 アプリ

Tessa は wlroots 内蔵 XWayland ではなく、外部の
[`xwayland-satellite`](https://github.com/Supreeeme/xwayland-satellite) を
使います。`PATH` に置くか、`TESSA_XWAYLAND_BIN` で絶対パスを指定します。

```sh
xwayland = true
xwayland_display = auto
```

`auto` は `/tmp/.X11-unix/X<n>` と `/tmp/.X<n>-lock` を調べ、最初の空き
ディスプレイを選びます。明示するなら `:1` などです。
`TESSA_NO_XWAYLAND=1` で無効化できます。

XIM を使う場合:

```sh
xim = true
xim_server = fcitx
# X ディスプレイの出現後に起動する場合
xim_start = fcitx5 -d
```

`XMODIFIERS=@im=fcitx` が X11 クライアントへ渡されます。Fcitx5 などが
既に起動している場合は `xim_start` を空にしてください。

### 3.6 画面共有ポータル

`install-session.sh` が `tessa.portal` をインストールします。手動なら
`packaging/portal/tessa.portal` を
`/usr/share/xdg-desktop-portal/portals/` へ配置します。

必要なもの:

- `xdg-desktop-portal`
- `xdg-desktop-portal-wlr`
- PipeWire

xdpw の設定例（1 出力）:

```ini
# ~/.config/xdg-desktop-portal-wlr/config
[screencast]
chooser_type=none
output_name=HEADLESS-1
```

ポータルサービスは systemd のユーザーマネージャから D-Bus 起動されるため、
コンポジタが子プロセス向けに設定した環境変数をそのままでは受け取りません。
`tessa-session` は Wayland ソケットの生成後に次を実行して登録します:

```sh
systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP \
  XDG_SESSION_TYPE XDG_SESSION_DESKTOP
systemctl --user try-restart xdg-desktop-portal
```

この登録がないとポータルは `xdg-desktop-portal-wlr` を起動せず、Discord や
Chromium 系ブラウザ、OBS では共有できる画面が 1 つも表示されません。TTY から
`tessa` を直接起動する場合も同じコマンドが必要です。`chooser_type` を設定
しない場合、xdpw は利用可能な chooser（`slurp`、`wmenu`、`wofi`、`rofi`、
`bemenu`、`mew`、`fuzzel`）を順に試し、どれもなければ任意の出力を使います。

---

## 4. 環境変数

| 変数 | 意味 |
| --- | --- |
| `TESSA_CONFIG` | 設定ファイルのパス。既定は `$XDG_CONFIG_HOME/tessa/config` または `~/.config/tessa/config` |
| `TESSA_IPC` | IPC ソケットのパス。既定は `$XDG_RUNTIME_DIR/tessa.sock` |
| `TESSA_OUTPUT_CONFIG` | 出力設定／レイアウト上書きの保存先。既定は `$XDG_CONFIG_HOME/tessa/outputs.conf` |
| `TESSA_DEBUG` | Tessa と wlroots のデバッグログを有効化 |
| `TESSA_PANEL_DEBUG` | パネルのデバッグログ |
| `TESSA_CTL_DEBUG` | `tessa-ctl` のデバッグログ |
| `TESSA_NO_PANEL` | パネルの自動起動を無効化 |
| `TESSA_PANEL_BIN` | 起動するパネルのパスを上書き |
| `TESSA_PANEL_OUTPUT` | 手動起動したパネルが担当する出力名 |
| `TESSA_NO_XWAYLAND` | XWayland 起動を無効化 |
| `TESSA_ALLOW_LINUX_DMABUF` | vmwgfx で自動無効になる linux-dmabuf を強制的に有効化 |
| `TESSA_XWAYLAND_BIN` | `xwayland-satellite` のパス |
| `TESSA_SOCKET_NAME` | Wayland ソケット名を明示（通常は自動） |
| `TESSA_STARTUP` | 起動時に実行するコマンド（設定の `startup` 推奨） |
| `WLR_BACKENDS` | `drm`、`headless`、`wayland` など |
| `WLR_RENDERER` | `gles2` または `pixman`（scenefx ビルドでは GLES2 固定） |
| `WLR_HEADLESS_OUTPUTS` | headless 出力数 |
| `TESSA_RUNTIME_DIR` | `run-headless.sh` / `screenshot.sh` 用のランタイムディレクトリ |

---

## 5. 設定の基本

設定例をコピーします。

```sh
mkdir -p ~/.config/tessa
cp config/config.example ~/.config/tessa/config
```

形式:

- `key = value`
- `#` で始まる行はコメント
- `include = path` で別ファイルを読み込み（相対パスはインクルード元基準）
- include の深さは最大 8
- フラット値はそのまま扱われ、前後の空白だけが除去されます。引用符は外されません
- ルール/拡張の clause では引用符を使えます。フラット値の中に `;` は書けません

再読み込みと診断:

```sh
tessa --check-config [file]      # オフライン検証。エラー時は非ゼロ終了
tessa-ctl config                 # 実効設定と解析済みルール
tessa-ctl config --json          # schema 1 の JSON
tessa-ctl config-check           # エラー時は非ゼロ終了
tessa-ctl dispatch reload        # Super+R と同じ
```

`tessa --check-config` はコンポジタを起動せず、一時的なパーサ状態に設定を
読み込みます。ファイル名と行番号付きの診断を出力するため、エディタ、CI、
ログイン前の TTY からも使えます。エラーのあるリロードは拒否され、以前の
設定が維持されます。診断にはファイル名と行番号が付きます。

Tessa は設定ディレクトリも監視します。メイン設定と同ディレクトリ内の
`.conf` include をアトミックに保存すると、短いデバウンス後に自動で
再読み込みされます。`Super+R` / `tessa-ctl dispatch reload` も引き続き使えます。
不正な編集は拒否され、以前の設定が維持されます。

---

## 6. 設定キー一覧

### 6.1 基本・レイアウト

| キー | 既定値 | 内容 |
| --- | --- | --- |
| `terminal` | `kitty` | `Super+Return` と `Terminal=true` で使うコマンド |
| `gaps` | `10` | タイル間の隙間 |
| `outer_gaps` | `16` | タイル領域の外周 |
| `border_width` | `2` | ウィンドウ枠の太さ（0〜16） |
| `master_ratio` | `0.58` | master の幅比率（0.15〜0.9） |
| `master_count` | `1` | master 列に積むウィンドウ数（1〜8） |
| `mosaic_ratio` | `0.62` | mosaic のスライス比率（0.25〜0.85） |
| `mosaic_min_size` | `160` | mosaic が grid に切り替わる最小タイル（80〜600） |
| `grid_columns` | `0` | grid の固定列数。`0` は自動（最大 8） |
| `layout` | `master` | 既定レイアウト。`master`、`mosaic`、`grid`、`columns`、`scrolling`、`monocle`、`stacking`、`custom` |
| `layout_cycle` | `master,mosaic,grid,columns` | `Super+T` で巡回するレイアウトのカンマ区切り |
| `default_column_width` | `50%` | Scrolling のカラム幅（`50%`、`0.5`、固定 `640`） |
| `column_width_presets` | `33.333%,50%,66.667%` | `column-width-cycle` で巡回するプリセット |
| `center_focused_column` | `never` | Scrolling のフォーカススクロール。`never`、`always`、`on-overflow` |
| `animation_view_ms` | `180` | Scrolling viewport のアニメーション時間 |
| `animation_view_curve` | `ease-out-cubic` | Scrolling viewport のカーブ |
| `layout_1` … `layout_9` | 継承 | 保存済み・実行中の上書きがないワークスペースの初期レイアウト |
| `layout_helper` | 空 | 出力ごとに 1 つ起動する非同期カスタムレイアウトヘルパー |
| `layout_helper_timeout` | `100` | ヘルパー応答タイムアウト（10〜1000 ms） |
| `effect_helper` | 空 | ウィンドウ別の視覚効果を返す常駐ヘルパープロセス |
| `effect_helper_timeout` | `200` | エフェクトヘルパー応答タイムアウト（20〜2000 ms） |
| `extension_ready_timeout` | `10000` | 監視付き拡張の token 認証待ち時間（ms）。`0` で無効、1000〜60000 |
| `frame_time_budget` | `16` | 描画コミットの予算（ms）。超過フレームを `tessa-ctl perf` が数える |
| `direct_scanout` | `true` | 不透明なフルスクリーンクライアントでコンポジタのノードを隠し、wlroots の直接スキャンアウトを可能にする |
| `tearing` | `off` | `off`、`fullscreen`、`force`。いずれもクライアントの async ヒントが必要 |
| `explicit_sync` | `true` | renderer/backend の timeline と DRM fd がある場合に `linux-drm-syncobj-v1` を公開。変更には再起動が必要 |
| `output_config` | `~/.config/tessa/outputs.conf` | 出力設定とレイアウト上書きの保存先 |
| `workspace_pin` | — | `OUTPUT WORKSPACE` でワークスペースを出力に固定。複数行可 |
| `workspace-name` | — | `WORKSPACE NAME` の表示名／コマンド別名。複数行可 |
| `special-workspace` | — | 名前付き special（非表示オーバーレイ）ワークスペースを宣言。複数行可 |
| `workspace-rule` | — | ワークスペース別のレイアウト／間隔ルール |
| `output-rule` | — | コネクタ名または EDID で一致させる出力別レイアウト／間隔／テーマ／VRR ルール |
| `input` / `input-rule` | — | デバイス別 libinput ポリシー。複数行可 |
| `profile` | — | 出力／ワークスペースルールから参照する名前付きプロファイル |
| `window-rule` | — | ウィンドウのマッチルール |
| `layer-rule` | — | レイヤーシェルのマッチルール |
| `theme-role` | — | アクセント、ボーダー、壁紙、パネル用の意味論的カラー |
| `mode` | `default` | 以降の `bind` を入れる名前付き入力モード |
| `bind` | — | キーバインドを追加・上書き |
| `include` | — | 別設定ファイルの読み込み |

### 6.2 見た目・アニメーション

| キー | 既定値 | 内容 |
| --- | --- | --- |
| `accent` | `#e2684f` | ボーダー、バー、ランチャーのアクセント色 |
| `bg` | `#0a0f1a` | 壁紙のベース色 |
| `bg_top` | 未指定 | 壁紙グラデーション上端。未指定は `bg` から導出 |
| `bg_bottom` | 未指定 | 壁紙グラデーション下端 |
| `wallpaper_art` | `true` | インク／太陽／水面などの装飾を描く |
| `wallpaper_art_opacity` | `0.55` | 装飾の不透明度（`0.0` で無効、`1.0` で最大）。半透明サーフェスの背後でも主張を抑える |
| `wallpaper_image` | 空 | PNG 壁紙のパス（絶対パスまたは `~/...`）。グラデーション／装飾を置換 |
| `wallpaper_shader` | 空 | バイナリ PPM（P6）フレームを出力するコマンド。画像より優先 |
| `wallpaper_fit` | `cover` | 画像の合わせ方: `cover`、`contain`、`stretch` |
| `border_active` | 空 | フォーカス中ボーダー。空なら `accent` |
| `border_inactive` | `#293347` | 非フォーカスボーダー |
| `font` | `Inter` | パネルの UI フォント |
| `animations` | `true` | ウィンドウ開閉・ワークスペース遷移を有効化 |
| `reduce_motion` | `false` | 移動アニメーションを止める |
| `reduce_motion_animations` | `none` | `none`、または閉じるフェードのみの `fade` |
| `reduce_motion_fade_ms` | `120` | 視差効果低減フェードの時間 |
| `animation_ms` | `160` | 既定のアニメーション時間（0〜1000 ms） |
| `animation_open_ms` | 継承 | 開くアニメーション時間（`-1` で継承） |
| `animation_workspace_ms` | 継承 | ワークスペース遷移の時間（`-1` で継承） |
| `animation_close_ms` | 継承 | 閉じるエフェクトの時間（`-1` で継承） |
| `animation_curve` | `ease-out-cubic` | 開く/ワークスペースの共通カーブ |
| `animation_open_curve` | 継承 | 開くアニメーションのカーブ |
| `animation_workspace_curve` | 継承 | ワークスペース遷移のカーブ |
| `animation_close_curve` | `smoothstep` | 閉じるエフェクトのカーブ |
| `bezier` | — | 名前付き cubic-bezier: `name, x1, y1, x2, y2` |
| `spring` | — | 名前付きスプリング: `name, damping, frequency` |
| `animation_open_x` / `_y` | `0` / `18` | 開くアニメーションの開始オフセット px |
| `animation_workspace_offset` | `54` | ワークスペース遷移の開始オフセット px |
| `animation_close_scale` | `0.92` | 閉じるスナップショットの最終スケール（0〜1） |
| `animation_close_fade` | `true` | 閉じるスナップショットをフェードする |
| `shadows` | `true` | ウィンドウの多層シャドウ |
| `corner_radius` | `10` | 角丸半径（0〜64。scenefx ビルドのみ有効） |
| `blur` | `true` | 半透明サーフェスの背景ブラー（scenefx ビルドのみ） |
| `blur_radius` | `6` | ブラー半径（1〜32） |
| `blur_passes` | `3` | ブラーのパス数（1〜5） |

`animations = false`、`reduce_motion = true`、`animation_ms = 0` のいずれかで
動きを無効化できます。パネルのランチャーはフェードと拡大で開き、結果行を
短い間隔でずらして表示し、選択マーカーを滑らかに移動させます。

### 6.3 パネル・シェル

| キー | 既定値 | 内容 |
| --- | --- | --- |
| `panel` / `autostart_panel` | `true` | `tessa-panel` を出力ごとに自動起動 |
| `bar_height` | `44` | バーの太さ／高さ（32〜96） |
| `bar_position` | `top` | バーの位置: `top`、`bottom`、`left`、`right` |
| `panel_style` | `classic` | `classic` は個別ポップオーバー、`unified` は統合コントロールパネル |
| `control_features` | `all` | コントロールパネルの機能（CSV、`all`、`none`） |
| `window_switcher` | `snapshot` | Alt+Tab スイッチャー: `snapshot`（ライブプレビュー）、`icons`、`off` |
| `control_action` | - | カスタムクイックアクション `ラベル \| コマンド`（複数可） |
| `bar_top_margin` | `12` | 選んだ端からの距離（0〜64） |
| `bar_side_margin` | `16` | バーに沿った余白。上下バーでは左右、左右バーでは上下（0〜128） |
| `logo_text` | `TESSA` | 上下バーのブランド文字列。空ならマークのみ |
| `logo_icon` | 空 | 五弁マークの代わりに描く PNG（絶対または `~/...`）。読み込めない場合はマークへフォールバック |
| `panel_bg` | `#0e131d` | `panel.background` と各サーフェス既定値の基底背景色 |
| `panel_fg` | `#edf2fa` | `panel.foreground` と各サーフェス既定値の基底前景色 |
| `panel_modules` | 全部 | 有効にするパネル要素: `background`、`bar`、`launcher`、`popovers`、`notifications`、`toasts`、`tray`、`media`、`audio`。`all`/`none` も可 |
| `bar_layout` | 全モジュール | カンマ／空白区切りのモジュール一覧。右側クラスタの表示と順序を決定 |
| `bar-font`、`launcher-font`、`popover-font`、`toast-font` | `font` | サーフェス別フォント |
| `bar-fg`、`launcher-fg`、`popover-fg`、`toast-fg` | `panel_fg` | サーフェス別前景色 |
| `bar-bg`、`launcher-bg`、`popover-bg`、`toast-bg` | `panel_bg` | サーフェス別背景色 |
| `launcher_entry` | — | ランチャー項目 `名前 \| コマンド`。複数行可 |
| `launcher_style` | `centered` | ランチャーの配置: `centered`（Wofi 風の中央表示）または `start`（バー端に合わせた Windows 風メニュー） |
| `panel_renderer` | `cairo` | 背景レンダラー: `cairo` または `gpu`（EGL/GLES2。利用できなければ Cairo へ自動フォールバック） |
| `overlay_renderer` | `cairo` | ランチャー／ポップオーバー: `cairo` または `gpu`（Cairo 内容をテクスチャ化し GPU で拡大／フェード） |
| `wallpaper_engine` | `cairo` | `panel_renderer = gpu` 時の壁紙: `cairo`（テクスチャ）または `procedural`（GPU が Vermilion Ink を生成） |
| `wallpaper_animation` | `off` | GPU 壁紙の動き: `off`、`on`、または `auto`（バッテリー駆動と `wallpaper_idle_pause` 経過後に停止） |
| `wallpaper_idle_pause` | `120` | 無入力で `auto` が停止するまでの秒数。`0` で無効 |
| `wallpaper_fps` | `30` | GPU 壁紙のフレームレート（1〜120） |
| `power_lock` | `loginctl lock-session` | 電源メニューの Lock |
| `power_suspend` | `systemctl suspend` | Suspend |
| `power_reboot` | `systemctl reboot` | Reboot |
| `power_off` | `systemctl poweroff` | Power Off |
| `screenshot_dir` | `~/Pictures/Screenshots` | PNG 保存先 |
| `volume_status` | 空 | 音量表示コマンド。空なら `wpctl`/`pactl`/`amixer` を自動検出 |
| `volume_up` | 空 | 音量上げコマンド |
| `volume_down` | 空 | 音量下げコマンド |
| `volume_mute` | 空 | ミュート切り替えコマンド |

`control_features` には `wifi`、`bluetooth`、`focus`、`notifications`、
`media`、`volume`、`brightness`、`power_profile`、`battery`、`quick_actions`、
`tray`、`calendar`、`power` をカンマ、空白、または `|` 区切りで指定します。
`control_action` は最大 4 件まで繰り返せます。

`window_switcher = snapshot`（既定）は全出力・全ワークスペースの
ウィンドウをライブでプレビューします。`icons` はアプリのモノグラムだけ、
`off` はスイッチャーを無効にします。詳細は
[ウィンドウスイッチャー](#ウィンドウスイッチャー) を参照してください。

`bar_height` や `bar_position` を変更すると、設定リロード時にバーの layer
surface が作り直され、予約領域も更新されます。`left`/`right` では縦長の
バーになり、ワークスペースとウィンドウチップが上から、ステータス
モジュールが下から積み上がります。ランチャーとポップオーバーも選んだ端に
合わせて表示されます。

`panel_renderer = gpu` の既定 `wallpaper_engine = cairo` は壁紙の見た目を
Cairo のまま保ちます。パネルが一度だけ Cairo で描いてテクスチャとして
アップロードし、EGL/GLES2 のシェーダーが任意の水面／インクの動きを加えます。
`wallpaper_engine = procedural` はグラデーション、インク、太陽、水面を
シェーダーで直接生成し、小さなコーナーマークだけをアップロードします。
パレット変更は 300ms でクロスフェードします。`wallpaper_image` と
`wallpaper_shader` はテクスチャ経路を使います。`wallpaper_animation = auto` はバッテリー駆動時、
`wallpaper_idle_pause` 秒間入力がないとき、フルスクリーンウィンドウ表示中に
停止します。`on` はバッテリーとアイドル判定を無視しますが、フルスクリーンと
オーバーレイ表示中は停止します。コンポジタへ提示できるクライアント側 EGL/GLES
スタックが必要です。Mesa の llvmpipe ならヘッドレス pixman セッションでも動作
します。EGL/GLES がない、ドライバーが壊れている、バッファをインポートできない
コンポジタでは理由をログに出して Cairo へ自動フォールバックします。
`TESSA_GPU_DISABLE=1` で強制的に Cairo にできます。`-Dgpu=false` でビルドすると
EGL/GLES 依存自体を外せます。

### 6.4 入力・ジェスチャ

| キー | 既定値 | 内容 |
| --- | --- | --- |
| `kb_layout` | 環境依存 | XKB レイアウト（例 `us,de`） |
| `kb_variant` | 空 | XKB バリアント |
| `kb_options` | 空 | XKB オプション（例 `grp:alt_shift_toggle`） |
| `kb_model` | 空 | XKB モデル |
| `kb_rules` | 空 | XKB ルール |
| `repeat_rate` | `25` | キーリピート速度 |
| `repeat_delay` | `600` | リピート開始までの ms |
| `leader` | 未指定 | `SUPER+SPACE` などのリーダーキーコード |
| `leader_timeout` | `1000` | リーダーモードのタイムアウト（ms）。`0` で無期限 |
| `mode_timeout` | `0` | 現在の名前付きモードのタイムアウト（ms） |
| `gestures` | `true` | タッチパッドジェスチャ |
| `gesture_fingers` | `3` | ワークスペース／ランチャー用の指の本数（2〜5） |
| `gesture_workspace_threshold` | `400` | 横スワイプの閾値（20〜1000） |
| `gesture_launcher_threshold` | `300` | 上スワイプの閾値（20〜1000） |
| `touch` | `true` | タッチ入力を受け付ける |
| `tablet` | `true` | tablet-v2 のツール／パッド |
| `pointer_constraints` | `true` | `pointer-constraints-v1` |
| `cursor_theme` | システム既定 | Xcursor テーマ名。空ならシステム既定 |
| `cursor_size` | `24` | カーソルサイズ（論理 px、16〜96） |
| `input` / `input-rule` | — | デバイス別 libinput ルール。複数行可 |

`input` ルールは 11 節で説明します。カーソルテーマとサイズはリロードで即時
反映され、存在しないテーマを指定した場合は以前のカーソルを維持します。

`Super+R` でキーマップも再構築されます。

### 6.5 X11・IME

| キー | 既定値 | 内容 |
| --- | --- | --- |
| `xwayland` | `true` | `xwayland-satellite` を起動し `DISPLAY` を設定 |
| `xwayland_display` | `auto` | `auto` または `:0` など |
| `xim` | `true` | `XMODIFIERS` を X11 クライアントへ設定 |
| `xim_server` | `fcitx` | XIM サーバ名 |
| `xim_start` | 空 | X ディスプレイ出現後に起動するコマンド |
| `linux_dmabuf` | `true` | `zwp_linux_dmabuf_v1` を公開。vmwgfx では自動無効 |

### 6.6 イベント・自動化

| キー | 内容 |
| --- | --- |
| `startup` | 起動時に 1 回実行するコマンド |
| `hook` | `<event> <command>` 形式のイベントフック。複数可 |
| `event-rule` | 条件付きイベント→コマンドルール。8.8 節参照 |
| `include` | 設定の分割 |

利用可能なイベントは「13. 拡張 API」の表を参照してください。

---

## 7. 既定キーバインドとマウス

### キーボード

| バインド | 動作 |
| --- | --- |
| `Super+Return` | ターミナル |
| `Super+D` | ランチャー |
| `Super+V` | クリップボード履歴 |
| `Super+Shift+S` | スクリーンショット UI |
| `Super+M` | MPRIS メディア |
| `Super+Shift+T` | トレイ |
| `Super+Shift+A` | 音量 |
| `Super+T` | `layout_cycle` を巡回（既定は従来の 4 レイアウト） |
| `Super+Q` | フォーカス中のウィンドウを閉じる |
| `Super+Shift+E` | Tessa を終了 |
| `Super+R` | 設定再読み込み |
| `Super+1` … `Super+9` | ワークスペース切り替え |
| `Super+Shift+1` … `9` | ウィンドウをワークスペースへ移動 |
| `Super+H/J/K/L` | 左/下/上/右へフォーカス |
| `Super`+左ドラッグ | タイルを並べ替え（Scrolling ではカラム挿入） |
| `Super`+ホイール | Scrolling の viewport をスクロール |
| `Super+Shift+H/J/K/L` | その方向と入れ替え。なければ隣接出力へ移動 |
| `Super+Space` | フローティング切り替え |
| `Super+F` | フルスクリーン切り替え |
| `Super+grave` | スクラッチパッド表示切り替え |
| `Super+Shift+grave` | フォーカス中ウィンドウをスクラッチパッドへ移動／復帰 |
| `Super+Shift+G` | ワークスペースのタイルウィンドウをグループ化／解除 |
| `Super+Escape` | `spawn swaylock` |
| `Super+Tab` / `Super+Page_Up` | ウィンドウ巡回。グループのフォーカス中はタブ巡回 |
| `Super+Shift+Tab` | Scene デッキを開く |
| `Alt+Tab` / `Alt+Shift+Tab` | MRU 順のウィンドウスイッチャー。Alt を押したまま選択し、解放で確定 |
| `Super+Ctrl+H/L` | master 比率を縮小/拡大 |
| `Super+Alt+H/L` | フローティング幅を縮小/拡大 |
| `Super+Alt+J/K` | フローティング高さを増減 |

キー名は XKB keysym 名です。`Super`、`Logo`、`Win` は同じ修飾キーとして
扱われます。

```ini
bind = SUPER+Return terminal
bind = SUPER+d launcher
bind = SUPER+1 workspace 1
bind = SUPER+SHIFT+1 move-to-workspace 1
bind = SUPER+h focus left
bind = SUPER+SHIFT+h move left
bind = SUPER+ctrl+h ratio -0.03
bind = SUPER+SHIFT+r enter-mode resize
```

利用可能なアクション:

`terminal`、`spawn`、`close`、`quit`、`workspace`、`move-to-workspace`、
`focus`、`move`、`toggle-float`、`toggle-fullscreen`、
`toggle-scratchpad`、`move-to-scratchpad`、`special`/`toggle-special`、
`move-to-special`、`toggle-group`、`group-next`、
`group-prev`、`group-add`、`group-remove`、`focus-next`、
`focus-prev`、`launcher`、`clipboard`、`screenshot`、`media`、`tray`、
`audio`、`window-switcher`、`scene-switcher`、`reload`、`ratio`、`toggle-layout`、`set-layout`、
`resize-width`、`resize-height`、`focus-column-*`、`move-column-*`、
`move-window-up/down`、`consume-window`、`expel-window`、
`column-width-cycle`、`column-width-cycle-back`、`column-width-set`、
`column-width-maximize`、`center-column`、`enter-mode`。

### マウス

- ウィンドウをクリックでフォーカス
- バーのウィンドウチップをクリックでフォーカス、右クリックで閉じる
- バー上でスクロールしてワークスペースを巡回
- `Super+左ドラッグ` でフローティング移動、タイルは並べ替え
- `Super+右ドラッグ` でフローティングリサイズ
- Scrolling では `Super+ホイール` で viewport をスクロール
- クライアント側タイトルバーのドラッグもフローティングで利用可能
- `TESSA` マークのクリックでランチャー、右クリックで電源メニュー
- 時計のクリックでカレンダー

---

## 8. レイアウトとルール

### 8.1 組み込みレイアウト

- **master**: master 領域 + 縦スタック。`master_ratio`、`master_count`
- **mosaic**（`spiral`）: 再帰スパイラル。最大 8 ウィンドウ。最小サイズを
  割ると **grid**、9 枚以上では **master** にフォールバック
- **grid**: `ceil(sqrt(n))` 列。最終行は中央寄せ。`grid_columns` で固定可
- **columns**（`column`）: 等幅全高カラム
- **scrolling**（`scroll`、`scroller`）: Niri 風の横カラム列
- **monocle**: フォーカス中のタイルがワークスペース全体を占有
- **stacking**（`deck`）: マスター領域 + 重ねたスタックカード
- **custom**（`helper`）: 外部レイアウトヘルパー

`Super+T` は組み込みレイアウトを巡回します。既定の巡回は従来の 4 モードで、
新しいモードは `layout_cycle` に明示的に追加します。`custom` は既定の巡回に
含まれないため、`set-layout custom` などで明示的に選びます。`layout_N` は
保存済み・実行中の上書きがないワークスペースの初期値です。実行中に選んだ
レイアウトは `outputs.conf` に保存されます。

### 8.1.1 Scrolling、monocle、stacking

- **scrolling**: Niri 風の横カラム。新しいウィンドウはフォーカス中のカラムの
  隣に追加されます。カラムは比率または固定幅で、`consume` で複数窓を
  縦に積めます。
- **monocle**: フォーカス中のタイルだけが usable 領域全体を占め、他のタイルは
  フォーカスするまで隠れます。
- **stacking**（別名 `deck`）: 先頭 `master_count` 窓を master 領域に置き、
  残りを右の stack 領域に重ねます。フォーカス中のカードが最前面です。

Scrolling の設定:

```ini
layout = scrolling
default_column_width = 50%       # 50%、0.5、固定幅 640
column_width_presets = 33.333%,50%,66.667%
center_focused_column = never    # never, always, on-overflow
animation_view_ms = 180
layout_cycle = master,scrolling,monocle,stacking
```

Scrolling では `focus left/right` と `move left/right` がカラム操作、
`focus up/down` と `move up/down` がカラム内の窓操作になります。明示的な
アクションは `focus-column-*`、`move-column-*`、`move-window-up/down`、
`consume-window`、`expel-window`、`column-width-cycle`、
`column-width-cycle-back`、`column-width-set`、`column-width-maximize`、
`center-column` です。

`consume-window` は右カラムのアクティブ窓を現在のカラム末尾へ追加します。
`expel-window` は現在のカラムの最下段窓を右へ新しいカラムとして出します。
グループ化された窓はタブ付き 1 カラムとして扱い、グループが絡む
consume/expel は拒否します。

`swap` と `reorder` はフラットなタイル順が対象で、Scrolling の
ワークスペースでは拒否されます。代わりに `column-move`、
`move-window-*`、タイルのドラッグを使ってください。

カラムの順序・幅・viewport はセッション状態です。Scrolling を離れるときに
カラム順を通常のタイル順へ flatten するため、次のレイアウトでも順序は
維持されますが、複数窓カラムとカラム幅は再度 Scrolling を選んでも復元
されません。レイアウトモード自体は通常どおり永続化されます。

`layout_cycle` はカンマ区切りのレイアウト名です。既定は
`master,mosaic,grid,columns` で、`scrolling`、`monocle`、`stacking` を
追加すると `Super+T` で巡回できます。

### 8.2 `workspace-rule`

```ini
workspace-rule = ws=2; layout=grid; gaps=4; outer-gaps=8; master-ratio=0.65
```

- `ws=1..9`: 必須
- `layout=...`
- `gaps=N`、`outer-gaps=N`
- `master-ratio=0.15..0.9`、`master-count=1..8`
- `mosaic-ratio=0.25..0.85`、`mosaic-min-size=80..600`
- `grid-columns=0..8`
- `default-column-width=50%|0.5|640`
- `center-focused-column=never|always|on-overflow`
- `profile=NAME`: 名前付きプロファイルを適用

### 8.3 `output-rule`

```ini
output-rule = output=HDMI-A-1; layout=grid; gaps=8; outer-gaps=12
output-rule = output=HDMI-A-1; ws=2; layout=master; master-ratio=0.62
output-rule = output=HDMI-A-1; profile=compact; gaps=4
output-rule = output=HEADLESS-*; accent=#8fd3ff; bg=#0c1118
output-rule = output=HEADLESS-*; border-active=#8fd3ff; border-inactive=#243040
output-rule = output=HEADLESS-*; panel-bg=#111827; panel-fg=#eef2f8
output-rule = output=HEADLESS-*; bg-top=#162038; bg-bottom=#070a12
output-rule = output=HEADLESS-*; bar-height=52; bar-top-margin=8; bar-side-margin=20
output-rule = make=Dell Inc.; model=DELL*; adaptive-sync=on
output-rule = serial=ABC123; adaptive-sync=off
```

マッチ条件:

- `output=` / `monitor=`: コネクタ名（例 `HDMI-A-1`）
- `make=` / `vendor=`: EDID のメーカー文字列
- `model=`: EDID のモデル文字列
- `serial=` / `edid-serial=`: EDID のシリアル番号
- 上記は任意に組み合わせ可能。少なくとも 1 つ必要で、指定した項目は
  すべて一致しなければなりません。`*` と `?` のワイルドカードが使えます。

レイアウト／チューニング（`ws=` で 1 ワークスペースに限定可能）:

- `ws=1..9`: 省略時は全ワークスペース
- `layout=...`
- `gaps=N`、`outer-gaps=N`
- `master-ratio=0.15..0.9`、`master-count=1..8`
- `mosaic-ratio=0.25..0.85`、`mosaic-min-size=80..600`
- `grid-columns=0..8`
- `default-column-width=50%|0.5|640`
- `center-focused-column=never|always|on-overflow`
- `profile=NAME`: 明示キーの前に名前付きプロファイルを適用

テーマ（全ワークスペースのみ）:

- `accent=#RRGGBB`、`bg=#RRGGBB`
- `border-active=#RRGGBB`、`border-inactive=#RRGGBB`
- `panel-bg=#RRGGBB`、`panel-fg=#RRGGBB`
- `bg-top=#RRGGBB`、`bg-bottom=#RRGGBB`
- `bar-height=0..200`、`bar-top-margin=0..128`、`bar-side-margin=0..256`。
  パネル実行時に 32〜96、0〜64、0〜128 へ clamp されます

出力ポリシー（全ワークスペースのみ）:

- `adaptive-sync=on|off` / `vrr=on|off`: 一致した出力で VRR を要求します。
  Tessa は即座にコミットし、結果をログに出力します。adaptive sync 非対応の
  出力では無視されます。ルールを削除すると、Tessa がポリシーを適用する前の
  状態に戻します（通常の起動時既定はオフ）。

コンポジタが出力の背景とボーダー色を適用し、パネルも同じ出力向けルールを
読み直すため、バーの高さ、マージン、壁紙、パネル色が一致します。`ws=` を
指定したルールではテーマと adaptive sync の項目を無視します。

#### 名前付きプロファイル

```ini
profile = compact; gaps=0; outer-gaps=0; master-ratio=0.5; master-count=2
profile = grid3; layout=grid; grid-columns=3; gaps=6; outer-gaps=2
output-rule = output=DP-1; profile=compact; gaps=4
workspace-rule = ws=2; profile=grid3
```

プロファイルは参照するルールの前後どちらでも宣言できます。ルール内の明示
キーがプロファイルより優先されます。プロファイルはレイアウトと間隔のみを
扱い、テーマは `output-rule` に直接書きます。存在しないプロファイルを参照
すると設定エラーになり、リロードは拒否されます。ワークスペース側では
`layout`、`gaps`、`outer-gaps`、`master-ratio`、`master-count`、
`mosaic-ratio`、`mosaic-min-size`、`grid-columns` を指定できます。

優先順位:

```text
グローバル既定
  < output-rule（全ワークスペース）
  < workspace-rule
  < output-rule（ws= 指定）
  < 実行中の layout 選択
```

`Super+Ctrl+H/L` の比率変更は、その出力／ワークスペースの実行時値として
現在のセッションに適用されます。設定リロードで設定値に戻ります。

### 8.4 `window-rule`

```ini
window-rule = app-id=pavucontrol; float=true
window-rule = title=*Picture-in-Picture*; float=true; position=40,40
window-rule = app-id=firefox; workspace=2
window-rule = app-id=org.example.*; fullscreen=true
window-rule = match=app ~ "^firefox$" && title !~ "Private|Incognito"; workspace=2
window-rule = match=(class == "foot" || class == "Alacritty") && output ~ "^DP-"; float=true
window-rule = title=Chat*; border-active=#4cc9f0; border-inactive=#1b2a41
window-rule = app-id=mpv; opacity=0.9; corner-radius=0; border-width=0
window-rule = title=Picture-in-Picture; opacity=0.85; corner-radius=14; blur=true
```

マッチ:

| キー | 内容 |
| --- | --- |
| `app-id`、`app_id`、`class` | xdg app-id |
| `title` | タイトル |
| `output`、`monitor` | 出力名 |
| `match`、`expr` | POSIX ERE 正規表現を使う真偽値式 |

式のフィールドは `app` / `app-id` / `class`、`title`、`output` /
`monitor` です。演算子は `==`、`!=`、`~`（正規表現一致）、`!~`（不一致）、
`&&` / `and`、`||` / `or`、`!` / `not`、括弧です。空白を含む値は引用符で
囲めます。正規表現は POSIX 拡張構文で、大文字小文字を区別します。

アクション:

| キー | 内容 |
| --- | --- |
| `float=true/false` | フローティング／タイル |
| `tile=true/false` | `float` の反対 |
| `fullscreen=true/false` | フルスクリーン |
| `workspace=1..9\|name` | ワークスペース指定 |
| `workspace=special` | スクラッチパッドへ（`scratchpad=true` の別名） |
| `workspace=special:NAME` | 宣言済み special ワークスペースへ |
| `special=NAME` | 宣言済み special ワークスペースへ（短縮形） |
| `scratchpad=true/false` | 非表示フローティングのスクラッチパッド割り当て |
| `size=WxH` | フローティングサイズ |
| `width=N`、`height=N` | 片軸のみ |
| `position=X,Y` | フローティング位置 |
| `border-active=#RRGGBB` | ウィンドウ別フォーカスボーダー |
| `border-inactive=#RRGGBB` | ウィンドウ別非フォーカスボーダー |
| `opacity=0.0..1.0` | ウィンドウと装飾の不透明度 |
| `corner-radius=0..64` | ウィンドウ別の角丸（`rounding` も可） |
| `blur=true/false` | ウィンドウ別の背景ブラー |
| `shadow=true/false` | ウィンドウ別の影 |
| `tearing=true/false` | `tearing` が `fullscreen`/`force` のとき、このクライアントの async tearing を許可（グローバルが `off` でも明示的に有効化可能） |
| `border-width=0..16` | ウィンドウ別ボーダー幅。`0` で非表示 |
| `tint=#RRGGBBAA` | コンテンツ上の半透明カラー。`none` で解除 |
| `shader=NAME` | オフスクリーン GPU エフェクト: `mono`、`crt`、`vignette`、`pixelate`、`wave`。`none` で解除 |
| `shader-strength=0.0..1.0` | エフェクトの強さ（既定 `1.0`） |
| `shader-param=N` | エフェクト用パラメータ。現在は pixelate のブロックサイズ（既定 `8`） |
| `animation=true/false` | そのウィンドウのモーションを有効／無効化 |
| `animation-ms=N` | 基本アニメーション時間の上書き（0〜1000） |
| `animation-open-ms`、`animation-workspace-ms`、`animation-close-ms` | 種類別の時間上書き |
| `animation-curve=NAME` | 開く／ワークスペースのカーブ上書き |
| `animation-open-curve`、`animation-workspace-curve`、`animation-close-curve` | 種類別のカーブ上書き |

パターンは `*`／`?`、大文字小文字は区別されます。単純キーと `match` は
AND で結合されます。ルールはファイル順で、後のルールが優先され、ボーダー
色や表示効果も同じ規則です。不正な式や正規表現はファイル名／行番号付きで
報告され、リロードは拒否されます。構造アクション（`float`、
`workspace`、`size`、`position`、`fullscreen`）はマップ時と設定リロード
時に評価されます。装飾アクション（`border-*`、`opacity`、
`corner-radius`、`blur`、`shadow`、`border-width`）は、タイトルまたは
app-id が変わった時点でも即座に再評価されます。モーション系キー
（`animation*`）も同じパスで再評価され、次回の遷移から適用されます。
色、ボーダー幅、不透明度、角丸、影の状態は閉じるスナップショットにも
引き継がれます。`corner-radius` と `blur` は scenefx ビルド（既定。
`-Dscenefx=false` で無効）が必要です。不透明度、影、ボーダー幅は全ビルドで
動作します。

ウィンドウシェーダーは専用の surfaceless EGL/GLES2 コンテキストで実行し、
ウィンドウ内容をオフスクリーンのエフェクトテクスチャに置き換えます。
コンポジタが描くボーダー、影、アニメーションは通常経路のままです。
ルールはオプトインで、次回のコンテンツ commit から適用されます。
`TESSA_SHADER_DISABLE=1` または `-Dshaders=false` ビルドで設定を変えずに
無効化できます。閉じるアニメーションはフィルタなしのスナップショットを
使い、DMA-BUF または共有メモリをインポートできる必要があります。
未対応フォーマットではそのウィンドウだけ通常表示にフォールバックします。
詳細と制限は [描画・ゲーム機能](rendering.md) を参照してください。

### 8.5 `layer-rule`

レイヤーシェル（バー、通知、壁紙プロバイダなど `zwlr_layer_shell_v1` を
使うクライアント）は専用のルール一覧で設定します。

```ini
layer-rule = namespace=tessa-bar; opacity=0.94; corner-radius=12; blur=true
layer-rule = namespace=tessa-notifications; layer=top; opacity=1; blur=false
layer-rule = namespace=my-wallpaper; layer=background; opacity=1; blur=false
```

マッチ:

| キー | 内容 |
| --- | --- |
| `namespace`、`ns` | レイヤーの namespace（`*`／`?` 可） |
| `output`、`monitor` | 出力名（`*`／`?` 可） |
| `layer` | `background`、`bottom`、`top`、`overlay`、または `0..3` |

アクション:

| キー | 内容 |
| --- | --- |
| `opacity=0.0..1.0` | レイヤーサーフェスの不透明度 |
| `corner-radius=0..64` | レイヤーサーフェスの角丸（`rounding` も可） |
| `blur=true/false` | 背景ブラーの上書き |

レイヤールールはファイル順で評価され、後の一致が優先されます。ルールが
ない場合の不透明度は `1`、ブラーは top／overlay レイヤーでグローバルの
`blur` に従います（background／bottom はブラーなし）。角丸の既定値は `0`
です。パネルのサーフェスは `tessa-bar`、`tessa-overlay`（ランチャー、
カレンダー、電源、クリップボード、メディア、トレイ、音量、スクリーンショット、
拡張一覧のポップオーバー）、`tessa-notifications`（トースト）の namespace を使います。
`layer=top` のルールはバーとトースト、`tessa-overlay` は overlay レイヤーに
適用されます。`Super+R`／設定リロードで再適用されます。`corner-radius` と
`blur` は scenefx ビルド（既定。`-Dscenefx=false` で無効）が必要です。
`tessa-ctl state` と
`tessa-ctl state --json` で実効値、`tessa-ctl config`／`config --json` で
解析済みルールを確認できます。

### 8.6 外部レイアウトヘルパー

```ini
layout = custom
layout_helper = python3 ~/.config/tessa/layout.py
layout_helper_timeout = 100
bind = SUPER+SHIFT+T set-layout custom
```

Tessa は出力ごとに 1 つのヘルパーを起動し、リクエストを非同期で送ります。
応答待ちでコンポジタが停止することはありません。`HELLO 2` を通知し、
タブ区切りの `LAYOUT\t2`、`OUTPUT`、`AREA`、`OUTER_GAP`、`GAP`、`BORDER`、
`SCALE`、`TRANSFORM`、`COUNT`、`WINDOW` 行を `END` まで送ります。
プロトコル 2 のヘルパーは `VERSION 2` を返し、それ以降の `WINDOW` は id、
app-id、タイトル、focused、urgent を持ちます。最初のリクエストはプロトコル 1
の 3 フィールド形式です。応答は任意の `VERSION 2`、タブ区切りの
`RECT\tid\tx\ty\tw\th` 行、`END` です。座標は
絶対論理座標、幅と高さはボーダーを含むフレームサイズです。`HELLO` や
バージョン行を無視する旧ヘルパーもそのまま動作します。

応答待ちの間は以前の矩形を維持し、最初の応答までは内蔵レイアウトを使います。
タイムアウト、クラッシュ、不正応答、ID 不一致、矩形不足時は、その出力だけ
master へフォールバックします。再試行は専用タイマーではなく、1 秒後の次回
リクエスト時に行われます。`stdout` はプロトコル専用
なので、診断は `stderr` へ書きます。緊急度は
`tessa-ctl dispatch urgent <id> on|off` で設定できます。詳細は
[CUSTOMIZATION.ja.md](CUSTOMIZATION.ja.md#外部レイアウトヘルパー) を参照して
ください。

### 8.7 ワークスペース固定

```ini
workspace_pin = eDP-1 1
workspace_pin = HDMI-A-1 3
```

- キー、ジェスチャ、IPC、バー、foreign activation の切り替えが固定先へ
  リダイレクトされます
- `Super+Shift+<n>` / `CMD move-workspace <n>` でウィンドウを固定先の出力へ
  移動できます
- 出力が存在しない間はピンが無視されます
- 同じワークスペースに複数のピンを書いた場合、後の設定が優先されます

#### 名前付きワークスペース

ワークスペース 1〜9 にグローバルな名前を付けられます:

```ini
workspace-name = 2 Code
workspace-name = 3 Chat
bind = SUPER+2 workspace Code
bind = SUPER+SHIFT+2 move-to-workspace Code
window-rule = app-id=org.mozilla.firefox; workspace=Chat
```

名前は空白を含まない 1 トークンで、数字だけの名前は使えず、重複もできません。
設定全体を読み終えてから解決するため、`workspace-name` を参照する bind や
ルールより後に書いてもかまいません。バーのピルには名前が表示され（長い名前は
短縮）、`tessa-ctl workspace Code`、`CMD move-workspace Code`、ウィンドウルールの
`workspace=` が名前を受け付けます。数値インデックスも引き続き使えます。名前は
表示とコマンドの別名で、内部的には従来どおり数値ワークスペースに所属し、すべての
出力で同じ番号に対応します。

#### スクラッチパッド

スクラッチパッドは出力ごとの非表示フローティングオーバーレイです:

```ini
window-rule = app-id=org.example.notes; scratchpad=true
bind = SUPER+grave toggle-scratchpad
bind = SUPER+SHIFT+grave move-to-scratchpad
```

`Super+grave` でフォーカス中出力のスクラッチパッドを表示／非表示し、表示時は
最初のウィンドウへフォーカスします。`Super+Shift+grave` はフォーカス中の
ウィンドウをスクラッチパッドへ移動し、スクラッチパッド上では通常タイルへ
戻します。ウィンドウルールでは `scratchpad=true` または
`workspace=special` を使えます。ワークスペースを切り替えるとスクラッチパッドは
隠れます。スクラッチパッドのウィンドウはフローティングで、ワークスペースの
占有数には数えず、閉じている間はバーにも表示されません。IPC では
`CMD toggle-scratchpad` と `CMD move-to-scratchpad` が使えます。

#### Special ワークスペース

名前付き special ワークスペースは一度宣言すると、出力ごとの非表示
オーバーレイとして使えます。スクラッチパッドとは別で、タイル／フローティング
の両方のウィンドウを置けます:

```ini
special-workspace = notes
special-workspace = tools
window-rule = app-id=org.example.notes; special=notes; size=520x360
bind = SUPER+ALT+n special notes
bind = SUPER+ALT+SHIFT+n move-to-special notes
```

ルールでは `workspace=special:tools` も同等です。表示切替は
`tessa-ctl special tools`、フォーカス中ウィンドウの移動は
`tessa-ctl move-to-special tools` で行えます。special 表示中は同じ出力の
通常ワークスペースのウィンドウが隠れ、再度切り替えると通常の表示に戻り、
最初の可視ウィンドウへフォーカスします。special のウィンドウはワークスペース
占有数に含めません。

#### ウィンドウグループ

`Super+Shift+G` はアクティブワークスペースのタイルウィンドウを 1 つの
タブ付きタイルにまとめ、フォーカス中のメンバーを表示します。グループの
フォーカス中は `Super+Tab` / `Super+Shift+Tab` がタブの巡回になります。
バーには表示中のメンバーだけが出ます。グループ化されたウィンドウで再度
`Super+Shift+G` を押すとグループ全体を解除します。

```ini
bind = SUPER+ALT+g group-add
bind = SUPER+ALT+SHIFT+g group-remove
```

`group-add` はフォーカス中のタイルウィンドウを同じワークスペースの既存
グループへ追加し、`group-remove` はグループから外して通常のタイルに戻します。
別ワークスペースやスクラッチパッドへ移動したメンバーはグループから外れます。
グループは実行時状態で、再起動をまたいで保存されません。IPC では
`toggle-group`、`group-next`、`group-prev`、`group-add`、`group-remove` が
使えます。

### 8.8 イベントルール

ライフサイクルイベントが式に一致したときコマンドを実行します:

```ini
event-rule = window-open; match=app ~ "^firefox$" && ws == "2"; run=notify-send "Firefox" "ワークスペース 2 で起動"
event-rule = window-open; match=title == "Mail" && id ~ "^[0-9]+$"; run=touch ~/.local/state/mail-opened
event-rule = workspace-change; match=ws == "3"; run=~/bin/on-workspace-3
```

イベント名は最初の節、または `event=<name>` で指定します。`match` / `expr`
は省略可能で、省略時はそのイベントの全発生で実行します。`run` / `command`
は必須です。ウィンドウルールと同じ真偽値・正規表現構文を使い、追加で
`event`、`ws`、`id` を参照できます。数値も文字列として比較します
（`ws == "3"`）。

コマンドには通常のフック環境（`TESSA_EVENT`、`TESSA_WINDOW_ID`、
`TESSA_WORKSPACE`、`TESSA_TITLE`、`TESSA_OUTPUT`、`TESSA_ARG` など）が
渡されます。一致したルールは設定順に並び、無条件 `hook` より先に実行され
ます。フックと同様に `/bin/sh -c` とセッションユーザーの権限で動きます。

### 8.9 常駐エフェクトヘルパー

```ini
effect_helper = python3 ~/.config/tessa/effects.py
effect_helper_timeout = 200
```

エフェクトヘルパーは全出力で 1 つの常駐プロセスです。現在のプロトコルは
v2 で、`VERSION 1` を返すヘルパーは従来の位置引数形式のまま動作します。

```text
HELLO\t2
EFFECT\t2
WINDOW\t<id>\t<app-id>\t<title>\t<output>\t<ws>\t<focused>\t<urgent>\t<fullscreen>\t<floating>\t<visible>\t<opacity>\t<radius>\t<blur>\t<shadow>\t<border-width>\t<x>\t<y>\t<w>\t<h>\t[<tint>]
...
END
```

`tint` は v2 交渉後のリクエストだけ末尾に付きます。応答は key=value 形式
です:

```text
VERSION\t2
WINDOW\t<id>\topacity=0.9\tradius=16\tblur=on\tshadow=off\tborder-width=2\ttint=#ff8844aa\topen-ms=240\topen-curve=spring-soft
END
```

v2 の各フィールドは任意で、省略した項目はルール値を使います。`tint` は
`#RRGGBBAA` または `none`、アニメーションは `-1`〜`1000` ms と
`bezier`/`spring` で登録したカーブ名を受け付けます。応答に含まれない
ウィンドウは上書きを解除します。ID、範囲、カーブ名を検証し、タイムアウト、
クラッシュ、不正な応答では全上書きを破棄します。再試行は専用タイマーではなく、
1 秒後の次回 refresh 時に行われます。
stdout はプロトコル専用です。詳細は
[EXTENDING.ja.md](EXTENDING.ja.md#エフェクトヘルパープロトコル) を参照して
ください。このプロトコルはコンポジタ内へコードを注入しません。

---

## 9. マルチモニタと出力

### 9.1 基本

- 出力ごとに独立した壁紙、バー、9 ワークスペース
- パネルは出力ごとに 1 プロセス
- `Super+1` … `9` はフォーカス中の出力に適用
- ワークスペース固定で対象出力を固定可能
- `Super+Shift+H/J/K/L` で隣接出力へ移動

### 9.2 `wlr-randr`

```sh
wlr-randr
wlr-randr --output HDMI-A-1 --mode 2560x1440@144
wlr-randr --output HDMI-A-1 --pos 1920,0
wlr-randr --output eDP-1 --scale 1.5
wlr-randr --output eDP-1 --transform 90
```

左と中央のように明示的に配置する場合は、論理レイアウト座標で位置を指定します
（コネクタ名は `wlr-randr` の表示に合わせてください）:

```sh
wlr-randr --output DP-1 --pos 0,0
wlr-randr --output HDMI-A-1 --pos 2560,0
```

設定は `outputs.conf` に保存され、次回起動時に復元されます。保存先は
`output_config` または `TESSA_OUTPUT_CONFIG` で変更できます。ファイルは
モード 0600 です。出力の無効化状態は保存されません。

### 9.3 スケーリング

- 整数スケール: パネルも整数倍バッファで描画
- フラクショナル: `wp_fractional_scale_v1` 対応クライアントには正確な
  スケールを通知。実行中の `wlr-randr --scale` 変更も再通知
- 非対応クライアントは切り上げ整数スケール
- パネルは Cairo の整数切り上げバッファスケールを使うため、1.5 倍などでは
  ダウンサンプルされる
- XWayland は `xwayland-satellite` の対応に依存
- XWayland の実機検証は未実施

### 9.4 外部バーとランチャー

Tessa Panel が既定です（`panel = true`）。別デスクトップの layer-shell バーや
ランチャーを使う場合は、統合パネルを無効にして `startup` から起動します:

```ini
panel = false
startup = waybar
```

`panel = false` にすると Tessa の壁紙、通知、内蔵ランチャーも無効になります。
Tessa Panel の一部だけを残す場合は `panel = true` のまま
`panel_modules` を指定します:

```ini
# Waybar にバーを任せ、Tessa のランチャーと通知は残す
panel = true
panel_modules = launcher,notifications,toasts
startup = waybar
```

`panel_modules` は `background`（`wallpaper`）、`bar`、`launcher`、
`popovers`（`popover`）、`notifications`（`notification`）、`toasts`
（`toast`）、`tray`、`media`、`audio`（`volume`）を受け付けます
（`all`/`none` も可）。キー名は `panel-modules` も使えます。マスクが変わると
スーパーバイザがパネルを再起動します。
Tessa のバーと外部バーを同じ辺に置くと両方の予約領域が使われ、デスクトップが
狭くなるため、どちらかを無効にしてください。`tessa-ctl shell` で、Tessa Panel が
所有しているロールと、存在する外部レイヤーシェルを確認できます。
`tests/external-shell.sh` は Waybar と Wofi、`tests/shell-coexistence.sh` は
Quickshell と Noctalia がインストールされている場合の共存を検証します。

Waybar 0.15 は layer-shell を直接使い、標準のワークスペース/
トップレベルプロトコルを利用できます:

```jsonc
{
  "layer": "top",
  "position": "top",
  "height": 34,
  "modules-left": ["ext/workspaces"],
  "modules-center": ["wlr/taskbar"]
}
```

Tessa は出力ごとに 1 つの `ext-workspace-v1` グループと 9 個の
ワークスペースを公開します。名前は `workspace-name`（未設定なら `1`…`9`）、
active/urgent 状態はライブ更新され、ワークスペースを activate するとその
出力が切り替わります。Tessa のワークスペース数は固定なので、公開する
capability は workspace の `activate` だけです。
`wlr-foreign-toplevel-management` はウィンドウが出力間を移動したときも
追従します。

Wofi などの layer-shell ランチャーは Tessa 固有の設定なしで動作します。
内蔵ランチャーのキーバインドを置き換える例:

```ini
bind = SUPER+D spawn wofi --show drun
```

フルスクリーンより前面に置きたい場合は Wofi の layer を `overlay` にして
ください。Quickshell の `PanelWindow` は layer-shell を使い、
`Quickshell.WindowManager` は ext-workspace、`ToplevelManager` は
foreign-toplevel を読みます。`focusable: true` のパネルは `ON_DEMAND`
キーボードフォーカスを要求し、クリック時にフォーカスされます。

Tessa Panel と外部バーを同じ辺に置くと両方が領域を予約します。片方を無効に
してください。tray は 1 つの `org.kde.StatusNotifierWatcher` を奪い合うため、
埋まるのは 1 つだけです。Waybar の minimize/maximize 要求は Tessa に
対応状態がないため no-op です。

### 9.5 出力故障時

出力が消えると、クライアントは残った先頭の出力へ移動します。最後の出力が
消えた場合は Tessa が終了します。

---

## 10. 見た目・テーマ

### 10.1 色と壁紙

```ini
accent = #e2684f
bg = #0a0f1a
bg_top = #162038
bg_bottom = #070a12
wallpaper_art = true
```

`bg_top`／`bg_bottom` を省略すると `bg` からグラデーションを導出します。
`wallpaper_art = false` で装飾を消した単純なグラデーションになります。

PNG 画像を壁紙にできます:

```ini
wallpaper_image = ~/Pictures/wallpaper.png
wallpaper_fit = cover
```

`wallpaper_image` は絶対パスまたは先頭が `~/` のパスを受け付けます。パネルは
Cairo で PNG を読み込み、設定リロード時に再読み込みします。`wallpaper_fit`
は `cover`（全体を埋めて切り抜き、既定）、`contain`（`bg` 色でレターボックス）、
`stretch`（縦横比を無視）です。画像がない場合は上のグラデーション／装飾を
使います。読み込みに失敗した場合はログを出してグラデーションへ戻ります。

コマンドで手続き的な壁紙を描画できます:

```ini
wallpaper_shader = ~/.config/tessa/sunset.sh
wallpaper_fit = stretch
```

コマンドはバイナリ PPM のヘッダ（`P6`、幅、高さ、最大値 `255`）に続けて
空白 1 バイトと `幅 * 高さ * 3` バイトの RGB を出力します。設定の読み込み／
リロード時に実行し、次のリロードまでフレームを保持します。画像より優先され
ます。同期実行なので描画時間は短くしてください。

### 10.2 バーとフォント

```ini
bar_height = 44
bar_top_margin = 12
bar_side_margin = 16
logo_text = TESSA
logo_icon = ~/Pictures/tessa-mark.png
panel_bg = #0e1320
panel_fg = #eef2f8
font = Inter
bar_layout = logo,workspaces,chips,clock,media,stats,volume,network,battery,tray,status
bar_font = Inter
launcher_font = Inter
popover_font = Inter
toast_font = Inter
bar_fg = #eef2f8
bar_bg = #0e1320
```

`bar_layout` は表示するモジュールと右側クラスタの右→左順（先頭が右端）を指定します。
`logo`（`mark`）、`workspaces`（`workspace`）、`chips`（`title`/`windows`）、
`clock`（`date`）、`battery`、`network`、`volume`（`audio`）、
`stats`（`cpu`/`memory`）、`media`、`tray`、`status` を認識し、未知の名前は
無視します。ロゴ、ワークスペースピル、ウィンドウチップの位置は固定です。
`bar-font`、`launcher-font`、`popover-font`、`toast-font` は `font` へ
フォールバックします。`*-fg`／`*-bg` はサーフェス別の色を上書きします。
`panel_bg`／`panel_fg` は `panel.background`／`panel.foreground` ロールと
各サーフェス既定値の基底で、バー自体の色は `bar-bg`／`bar-fg`（または
テーマロール）です。右側クラスタは幅に応じて battery ≤900、tray ≤980、
network ≤1000、volume ≤1080、stats ≤1180、media ≤1250 で非表示になります。
ウィンドウチップは最大 6 件です。`+N` バッジは 6 件の上限より前に幅不足で
省略した分だけを数えるため、上限を超えたウィンドウが必ず数えられるわけでは
ありません。

`logo_text` は `TESSA` の文字列を、`logo_icon` は五弁マークを PNG 画像に
置き換えます。アイコンは 28 px のボタン内の 22 px ボックスへ、縦横比を保って
収まります。`logo_text` を空にするとアイコン／マークのみ、`logo_icon` が空か
読み込めない場合は組み込みのマークになります。長い文字列はワークスペース
ピルと重ならないよう `..` で短縮されます。左右バーにはラベル領域がないため、
アイコンまたはマークのみを表示します。どちらも設定リロードで反映されます。

CJK テキストには `font` の後にロケールに応じたフォールバック
（日本語なら `Noto Sans CJK JP`、`Noto Sans JP`、`Source Han Sans JP`、
`IPAGothic`、`TakaoPGothic`）を追加します。日本語のリストを明示することで、
共有漢字が fontconfig の選択により韓国語字形になるのを防ぎます。CJK が
豆腐（□）になる場合は Arch の `noto-fonts-cjk`、Debian/Ubuntu の
`fonts-noto-cjk`、NixOS の `noto-fonts-cjk-sans` を導入してください。

意味論的テーマロールを使うと、1 つの値をコンポジタとパネルで共有できます:

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

対応ロールは `accent`、`window.border.active`、`window.border.inactive`、
`window.background`、`panel.background`、`panel.foreground`、
`bar.background`、`bar.foreground`、`launcher.background`、
`launcher.foreground`、`popover.background`、`popover.foreground`、
`toast.background`、`toast.foreground`、`wallpaper.top`、`wallpaper.bottom`
です。ロールは直接キーの後に適用されるため、`accent`、`border_active`、
`border_inactive`、`bg` と対応するパネルキーより優先されます。
`panel.background`／`panel.foreground` は明示されていないサーフェス別の
背景／前景色にも反映されます。一致する `output-rule` のテーマは、その出力に
限りグローバルロールも上書きします。

### 10.3 ボーダーとシャドウ

```ini
border_width = 2
border_active = #e2684f
border_inactive = #293347
shadows = true
```

`border_active` が空なら `accent` が使われます。フルスクリーン時は
ボーダーと角丸を描きません。

### 10.4 アニメーション

```ini
animations = true
animation_ms = 160
animation_open_ms = 160
animation_workspace_ms = 220
animation_close_ms = 180
animation_curve = ease-out-cubic
animation_open_curve = ease-out-quint
animation_workspace_curve = ease-in-out-cubic
animation_close_curve = smoothstep
bezier = snap, 0.16, 1.0, 0.3, 1.0
spring = bounce, 0.35, 1.4
animation_open_x = 0
animation_open_y = 18
animation_workspace_offset = 54
animation_close_scale = 0.92
animation_close_fade = true
reduce_motion = false
reduce_motion_animations = fade
reduce_motion_fade_ms = 120
```

- 組み込みカーブ: `linear`、`ease-out-cubic`、`ease-in-out-cubic`、
  `ease-out-quint`、`ease-in-out-quint`、`smoothstep`、`overshoot`、
  `spring`、`spring-soft`、`spring-bouncy`
- `bezier = name, x1, y1, x2, y2` で独自 cubic-bezier を定義
- `spring = name, damping, frequency` で正規化スプリングを定義。
  `damping` は 0.05〜2、`frequency` は 0.25〜4（アニメーション中の振動数）。
  減衰が小さいほどオーバーシュートし、終端は必ず 1 になります
- 開く: 設定した x/y オフセット（既定 0/18 px）から開くカーブで移動
- ワークスペース: 設定した ±オフセット（既定 54 px）から遷移
- 閉じる: バッファを保持して `animation_close_scale` まで縮小し、
  必要なら閉じるカーブでフェード
- 種類別の時間が `animation_ms` を上書きします。`-1` で継承
- クライアント自身が閉じた場合は unmap 時点でバッファがなくなるため即時
- `reduce_motion = true` は開く／ワークスペースの移動を無効化
- `reduce_motion_animations = fade` は縮小や移動をせず、閉じるフェードだけを
  `reduce_motion_fade_ms` の間実行
- `reduce_motion_animations = none`（既定）は close エフェクトも無効
- 時間は 0〜1000 ms で、`0` はそのアニメーションを無効化

ウィンドウルールでウィンドウ単位のモーションを上書きできます。

```ini
window-rule = app-id=kitty; animation=false
window-rule = title=Picture-in-Picture; animation-ms=260; animation-curve=spring-soft; animation-close-ms=180; animation-close-curve=bounce
```

| ルールキー | 内容 |
| --- | --- |
| `animation=true/false` | そのウィンドウの全モーションを有効／無効化 |
| `animation-ms=N` | 基本時間の上書き（0〜1000） |
| `animation-open-ms`、`animation-workspace-ms`、`animation-close-ms` | 種類別の時間上書き |
| `animation-curve=NAME` | 開く／ワークスペースのカーブ上書き |
| `animation-open-curve`、`animation-workspace-curve`、`animation-close-curve` | 種類別のカーブ上書き |

`animation-curve` は開く／ワークスペースに適用され、閉じる場合は
`animation-close-curve`（未指定ならグローバルの閉じるカーブ）を使います。
これらの上書きは他の装飾系ウィンドウルールと同じパスで再評価されます。
グローバルの `animations = false` と `reduce_motion = true` が常に優先です。

アニメーションの開始／完了は `animation-start`、`animation-done`、
`close-animation-start`、`close-animation-done` イベントで取得できます。

### 10.5 scenefx 角丸・ブラー

scenefx ビルド（既定）のみ:

```ini
corner_radius = 10
blur = true
blur_radius = 6
blur_passes = 3
```

- `corner_radius` はクライアント内容、ボーダー、シャドウに適用
- `blur` は半透明クライアントと top/overlay/popup レイヤーに適用
- 不透明なウィンドウではブラーは見えない
- このビルドは GLES2 必須で pixman では動かない
- `-Dscenefx=false` ビルドではキーは受理されるが見た目は変わらない

---

## 11. 入力

### 11.1 キーボード

```ini
kb_layout = us,de
kb_variant =
kb_options = grp:alt_shift_toggle
kb_model =
kb_rules =
repeat_rate = 25
repeat_delay = 600
```

`Super+R` でキーマップを再構築します。`kb_*` が空の場合は環境の XKB
設定を使います。

### 11.2 カーソル

```ini
cursor_theme = Adwaita
cursor_size = 24
```

テーマは Xcursor 名で、`XCURSOR_THEME`、`XCURSOR_PATH`、
`$XDG_DATA_HOME/icons`、`/usr/share/icons` の通常の検索パスを使います。
`cursor_theme` が空ならシステム既定です。`cursor_size` は 16〜96 論理 px
に丸められます。設定リロードでカーソルマネージャを即座に作り直します。新しい
テーマを読み込めない場合は警告をログに出し、ポインタが見えなくなるのを避ける
ため以前のカーソルを維持します。

### 11.3 デバイス別入力ポリシー

libinput の設定は繰り返し可能な `input`（または `input-rule`）行で指定します。
ルールは実デバイスごとにマッチし、ファイル順にマージされます。同じ項目は
後のルールが上書きします:

```ini
input = type=touchpad; tap=true; tap-drag=true; natural-scroll=true
input = type=touchpad; name=*Precision*; accel-profile=flat; accel-speed=-0.3
input = type=mouse; name=*Mouse*; natural-scroll=false; scroll-method=button; scroll-button=275
input = type=touchpad; dwt=false; click-method=clickfinger
input = type=pointer; left-handed=true
```

マッチ条件:

| キー | 内容 |
| --- | --- |
| `type=` / `device-type=` / `kind=` | `any`、`keyboard`、`pointer`、`touchpad`、`mouse`、`touch`、`tablet`、`tablet-pad`、`switch`。既定は `any` |
| `name=` / `device=` | libinput のデバイス名。`*` と `?` が使える。省略時は全デバイス |

設定項目:

| キー | 対象 | 値 |
| --- | --- | --- |
| `tap=` | タッチパッド | `true`/`false` |
| `tap-drag=` | タッチパッド | `true`/`false` |
| `tap-drag-lock=` | タッチパッド | `true`/`false` |
| `natural-scroll=` | ポインタ／タッチパッド | `true`/`false` |
| `left-handed=` | ポインタ | `true`/`false` |
| `middle-emulation=` | ポインタ | `true`/`false` |
| `dwt=` / `disable-while-typing=` | タッチパッド | `true`/`false` |
| `accel-profile=` | ポインタ | `adaptive` または `flat` |
| `accel-speed=` | ポインタ | `-1.0`〜`1.0` |
| `scroll-method=` | ポインタ／タッチパッド | `none`、`two-finger`、`edge`、`button`、`circular` |
| `scroll-button=` | ポインタ | evdev ボタンコード `1`〜`767` |
| `click-method=` | タッチパッド | `none`、`button-areas`、`clickfinger` |
| `tap-button-map=` | タッチパッド | `lrm` または `lmr` |
| `clickfinger-button-map=` | タッチパッド | `lrm` または `lmr` |

種別判定には libinput を使います。タップ対応のポインタはタッチパッド、
それ以外はマウスとして扱います。タッチパッド専用項目はマウスには影響せず、
その逆も同様です。設定はデバイス追加時と設定リロード時に適用されます。
Tessa はデバイスの元の libinput 状態を記録するため、ルールを削除すると以前の
上書きを残さず元の状態へ戻ります。設定できるのは libinput デバイスだけで、
仮想デバイスや別バックエンドのデバイスには干渉しません。

ヘッドレステストでは設定の解析と JSON 出力を検証できますが、タップやスクロール
の実動作は検証できません。実機では `libinput list-devices` で正確なデバイス名
を確認してください。

### 11.4 入力モード

```ini
mode = resize
bind = h resize-width -30
bind = l resize-width 30
bind = Escape enter-mode default
mode = default
bind = SUPER+SHIFT+r enter-mode resize
```

モード内のバインドは修飾キーなしでマッチします。モード固有のバインドが
グローバルより優先されます。`Enter` などは XKB keysym 名です。モード節の
中で `mode_timeout = 300` を設定すると、一致するキーがないまま 300 ms
経過した時点で `default` に戻ります。

リーダーキーコードは `leader` モードへ入ります:

```ini
leader = SUPER+SPACE
leader_timeout = 1000

mode = leader
bind = f spawn firefox
bind = t spawn kitty
bind = Escape enter-mode default
```

リーダーは既定モードでのみ認識されます。もう一度リーダーを押す、
`Escape` にバインドする、または `leader_timeout` 経過で終了します。
リーダーモードのバインドが一致すると 1 アクション実行後に既定モードへ
戻ります。アクションが別モードへ入る場合はそのモードを維持します。
`leader_timeout = 0` は明示的に終了するまで維持します。

### 11.5 ジェスチャ

```ini
gestures = true
gesture_fingers = 3
gesture_workspace_threshold = 400
gesture_launcher_threshold = 300
```

既定では 3 本指の横スワイプでワークスペース、上スワイプでランチャーです。
それ以外の指の本数や pinch/hold はフォーカス中のクライアントへ転送されます。

### 11.6 タッチ・タブレット

```ini
touch = true
tablet = true
pointer_constraints = true
```

タッチはパネル UI も含めて処理されます。tablet-v2 は圧力、tilt、rotation、
ツールボタン、リング、ストリップに対応します。pointer-constraints-v1 は
フォーカスに応じて locked/confined を有効化します。

### 11.7 IME / XIM

Wayland IME は `text-input-v3` と `input-method-v2` で中継されます。
Fcitx5 + Mozc でのランチャー入力が検証済みです。

X11 は `XMODIFIERS` を設定し、必要なら `xim_start` で XIM サーバを起動します。

```ini
xim = true
xim_server = fcitx
xim_start = fcitx5 -d
```

`xim_start` は X ディスプレイのソケットが現れてから実行されます。

Fcitx5 は実行中キーボードグラブを保持します。Tessa は入力メソッドの仮想
キーボード出力をフォーカス中のクライアントへ戻します。`text-input-v3` を
使わないクライアント（Firefox など）も含みます。仮想キーボードの作成・破棄時に
キーボードフォーカスを再入力しないため、text-input の enable/activate ループは
発生しません。

---

## 12. シェル機能

### 12.1 ランチャー

- `Super+D`、バーの `TESSA` マーク、または `tessa-ctl launcher`
- 通常の `.desktop` を検索
- 入力で絞り込み、`Up`/`Down`、`Enter`、`Esc`、クリック
- IME 入力対応
- `launcher_entry = Name | command` で独自項目を追加
- 設定リロードでランチャー項目も更新

### 12.2 クリップボード履歴

- `Super+V` またはバーから開く
- 最大 8 件、各 16 KiB、テキストのみ、メモリ上のみ
- 選択でクリップボードへ戻す

`wlr-data-control-v1` をセッションへ公開しているため、同じユーザーの
信頼されたクライアントはフォーカスなしでセレクションを読めます。セッション
内アプリは信頼できる前提で使ってください。

### 12.3 スクリーンショット

- `Super+Shift+S`
- ドラッグで範囲、クリックまたは `Enter` で出力全体
- `Esc`／右クリックでキャンセル
- フォーカス中の出力を `wlr-screencopy` で取得
- PNG を `screenshot_dir` に保存

### 12.4 カレンダー・電源

- 時計クリックで月間カレンダー
- `Left`/`Right`、矢印、ホイールで月移動、`Home` で今日
- `TESSA` マーク右クリックで電源メニュー
- `Up`/`Down`、`Enter`、`Esc`、クリック
- Lock/Suspend/Reboot/Power Off のコマンドを設定可能

### コントロールパネル

`panel_style = classic`（既定）は、時計・音量・メディア・トレイ・Wi-Fi・
Bluetooth の個別ポップオーバーを維持します。`panel_style = unified` ではバーに
Controls ボタンが追加され、バーの各ポップオーバー入口が1つのコントロールパネルに
まとまります。

- Wi-Fi: NetworkManager のスキャン、電波強度、WPA2/WPA3-PSK・オープン、
  隠しSSID、保存済み接続、接続/切断/忘れる、ラジオON/OFF
- Bluetooth: BlueZ のアダプタ電源、探索、デバイス一覧、ペアリング/接続/
  切断/忘れる、バッテリー残量、確認・パスキー入力
- Focus（通知の一時停止）、通知履歴（50件）、クリア、アクション
- 音量・輝度スライダー、電源プロファイル（power-profiles-daemon）
- メディアカード（ローカルの `file://` ジャケット、進行バー、クリックシーク）
- THEME ページ。6種類のフルパレット、アクセント、ベーストーン、リセット。
  パネル・ウィンドウ枠・壁紙をまとめて変更
- バッテリー、ロック/サスペンド/再起動/電源OFF、スクリーンショット、
  クリップボード、設定、最大4件の `control_action`

`control_features` で機能単位に表示を切り替えられます（例:
`control_features = wifi, bluetooth, volume, notifications`）。classic では
同じキーが Wi-Fi/Bluetooth ポップオーバーと Bluetooth インジケータを制御します。
unified では時計がカレンダー、トレイがトレイビュー、電源メニューが電源ビューを
開きます。IPC からは次のように開けます:

```sh
tessa-ctl panel control
tessa-ctl panel wifi
tessa-ctl panel bluetooth
tessa-ctl panel notifications
tessa-ctl panel theme
```

THEME ページは unified モードで使えます。メイン設定の隣に
`theme-colors.conf` を書き、コンポジタへ再読み込みを要求するため、パネル・
ウィンドウ枠・壁紙が同時に変わります。このファイルはメイン設定と `theme`
パッケージより後に読み込まれます。`RESET` はファイルを削除して設定済みの
パレットへ戻します。フルパレットを選ぶと各サーフェスの背景・前景も保存され、
アクセント行とベース行は現在のパレットの片方だけを変更します。

Wi-Fi はシステムの NetworkManager D-Bus API を使います。WPA2/WPA3-PSK、
オープン、隠しSSID に対応し、802.1X/EAP・VPN・キャプティブポータルは対象外です。
Bluetooth は BlueZ を直接使い、ペアリングエージェントはプライマリパネルだけが
登録します（セカンダリ出力ではペアリング不可）。通知履歴はメモリ内で、
通知オーナーのパネルだけに表示されます。

輝度は `/sys/class/backlight` と logind の `SetBrightness` を使い、バックライトが
ない環境ではスライダーを隠します。電源プロファイルには
power-profiles-daemon が必要です。NetworkManager、BlueZ、
power-profiles-daemon、logind は任意の実行時サービスで、ない場合は
「利用不可」表示になりパネル自体は継続します。

### ウィンドウスイッチャー

`Alt+Tab` で、**全出力・全ワークスペース**のウィンドウを最近使った順に
表示します。`Tab` / `Shift+Tab`、矢印キー、ホイールで選択を移動し、`Enter`、
クリック、または Alt の解放で確定します。`Esc` はキャンセルです。
`Alt+Shift+Tab` は反対側から始まります。別のワークスペースや出力の
ウィンドウを確定すると、その場所へ切り替えてフォーカスします。名前付き
特殊ワークスペースも復元します。スクラッチパッドのウィンドウは対象外です。
既定のキーは `window-switcher` アクションで変更できます:

```
bind = ALT+Tab window-switcher
bind = ALT+Shift+Tab window-switcher prev
```

`window_switcher` で表示方法を選びます:

- `snapshot`（既定）: 各ウィンドウを専用のオフスクリーン GPU シーンへ
  ライブ描画し、サブサーフェスも含めて `ext-image-copy-capture` で
  パネルへ転送します。ウィンドウのダメージに応じて更新され、長辺 512 px
  に制限されるため、4K や fractional scale でもフル解像度の読み戻しは
  発生しません。フローティングや非表示ワークスペースのウィンドウも
  プレビューされます。各カードにはプレビューのぼかし背景を描きます。
- `icons`: キャプチャせず、アプリのモノグラムだけを表示します。
- `off`: スイッチャーを無効化します（キーは何もしません）。

直近 12 ウィンドウまで保持します。`ext-foreign-toplevel-list-v1`、
`ext-image-capture-source-v1`、`ext-image-copy-capture-v1` が必要ですが、
Tessa が提供します。利用できない場合は、出力を 1 回キャプチャして
ウィンドウ矩形で切り出す方式にフォールバックします。IPC からは
`tessa-ctl panel switcher` で開けます。

### Scene

Scene は再利用できるワークスペースのテンプレートです。レイアウト、レイアウト
調整値、そこに置くウィンドウ/アプリを保存し、後から適用したり Scene デッキから
切り替えたりできます。

```sh
tessa-ctl scene save coding        # フォーカス中の WS を保存
tessa-ctl scene activate coding    # 保存した WS へ切り替えて適用
tessa-ctl scene apply coding 2     # テンプレートを WS 2 に適用
tessa-ctl scene list
tessa-ctl scene delete coding
tessa-ctl scene clear              # 現在の WS の Scene 調整を解除
tessa-ctl scene reload             # 外部編集したファイルを再走査
```

`Super+Shift+Tab` で Scene デッキを開きます。`Tab` / `Shift+Tab`、矢印、
ホイールで選択し、`Enter`、クリック、`Space` で適用、`Esc` で閉じます。
カードには Scene 名、WS、レイアウト、アプリ数/ライブ数、最大4枚の
ライブプレビューが表示されます。

Scene ファイルは `~/.config/tessa/scenes/<name>.scene` に保存されます
（メイン設定の隣。`TESSA_SCENE_DIR` で変更可能）。プレーンテキストなので
手編集できます:

```ini
name = coding
workspace = 3
layout = master
gaps = 10
outer_gaps = 18
master_ratio = 0.62
master_count = 1
mosaic_ratio = 0.64
mosaic_min_size = 180
grid_columns = 0
column_width = 50%
center_focused_column = never

[app]
command = kitty
app_id = kitty
title = ~/src/tessa
floating = false
```

Scene はテーマと壁紙も持てます:

```ini
[theme]
accent = #7aa2f7
bg = #070b14
border_active = #7aa2f7
border_inactive = #26324a
panel_bg = #0e1626
panel_fg = #e8eefc
bg_top = #16233f
bg_bottom = #060810

[wallpaper]
image = ~/Pictures/Wallpapers/indigo.png
fit = cover
art = false
```

Scene がワークスペースで有効な間は、その出力/ワークスペースでアクセント、
ウィンドウ背景、枠色が使われます。その出力のパネルも Scene のバー/ランチャー/
ポップオーバー/トースト色と壁紙画像へ切り替わります。Scene のない WS へ移動
すると上書きを解除し、基本設定/出力テーマへ戻ります。別出力はそれぞれの
アクティブ Scene を保ちます。`[theme]`/`[wallpaper]` のない Scene は基本の
色と壁紙を変更しません。

保存時は有効なレイアウト調整値、現在の視覚トークン、設定中の壁紙、各
ウィンドウのコマンドラインを記録します。別 Scene の適用中に保存すると、
その Scene の視覚トークンと壁紙を引き継ぎます。
`/proc/<pid>/cmdline` から取得します。これによりネイティブ Wayland アプリは
再起動できます。XWayland（`xwayland-satellite` 経由）のウィンドウは
ウィンドウ単位の PID がないため、`app_id`/`title` のみ保存され、自動再起動は
できません。コマンドはシェルクォートされた argv として 0600 のファイルに
保存されます。引数に機密情報を含む Scene ファイルは公開しないでください。

適用は**非破壊**です。対象ワークスペースに既にあるウィンドウは残し、Scene の
アプリのうち存在しないものだけを起動します。そのため別 Scene のウィンドウと
同じ WS に混在できます。きれいに切り替えたい場合は別の WS を使ってください。
新しく map されたアプリは Scene の WS へ割り当てられます。

### 12.5 通知

パネルが `org.freedesktop.Notifications` を所有します。

- 置換、閉じる、期限切れ
- アクションボタン、`default` アクション
- `image-data`、`image-path`、`icon-name`
- Pango マークアップ
- フォーカス中の出力へトーストをルーティング
- 通知アクションは `tessa-ctl notify-action <id> <key>` でも実行可能

Pango の範囲を超える HTML、通知音、通知ごとの出力固定は未対応です。

### 12.6 バー表示

- ワークスペースピル
- ウィンドウチップ（クリックでフォーカス、右クリックで閉じる）
- CPU/RAM
- 時計・カレンダー
- バッテリー
- デフォルトルートのネットワーク状態
- MPRIS メディア（最初のプレイヤー、アルバムアートなし）
- StatusNotifier トレイ（DBusMenu なし）
- 音量（`wpctl`/`pactl`/`amixer`）
- 最大 8 件のカスタムステータス

パネルはコンポジタに監視されます。Tessa は Linux の pidfd でパネルプロセスを
追跡し、クラッシュ時は上限付き指数バックオフ（1 秒から倍増、最大 8 秒。
10 秒以上安定すると失敗回数がリセットされ、初回は 500 ms の場合もあります）で
再起動します。通知所有者のパネルは再起動後もその役割を維持します。意図的な
終了や出力の取り外しでは再起動しません。`tests/panel-recovery.sh` で検証して
います。

### 12.7 音量

```ini
volume_status = wpctl get-volume @DEFAULT_AUDIO_SINK@
volume_up = wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+
volume_down = wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
volume_mute = wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
```

空欄なら `wpctl`、`pactl`、`amixer` を順に自動検出します。

オーディオカードには `OUTPUT` と `INPUT` のタブがあります。各タブに現在の
音量、ミュート、シンク/ソースの一覧を表示し、デバイスをクリックすると既定の
出力先・入力先に切り替えます。入力音量とミュートは
`@DEFAULT_AUDIO_SOURCE@`（amixer は `Capture`）を使います。`Tab` でタブ、
`Up`/`Down` で選択中の音量、`m` でミュート、`d` で既定デバイスを切り替え
ます。unified では `panel audio` とコントロールセンターの SOUND カードが
同じ画面を開きます。デバイス選択には `wpctl` または `pactl` が必要です。
独自の `volume_*` コマンドは出力側のみを上書きします。

### 12.8 ロック・idle

- `ext-session-lock-v1` 実装
- 既定の `Super+Escape` は `swaylock`
- lock 中はデスクトップツリーを隠し、仮想キーボード入力を無視
- lock クライアントが消えた場合はセッションを終了
- idle タイミングは `swayidle` など外部に任せる
- `idle-inhibit-v1`、`ext-idle-notify-v1`、`wlr-output-power-management-v1` を公開
- `wlopm` で出力のオン／オフ

例:

```sh
swayidle -w \
  timeout 300 'swaylock -f' \
  timeout 600 'wlopm --off "*"' \
  resume 'wlopm --on "*"'
```

### 12.9 画面共有

`tessa.portal` を配置し、`xdg-desktop-portal-wlr` と PipeWire を起動します。
Screenshot/ScreenCast は `XDG_CURRENT_DESKTOP=Tessa` で wlr バックエンドへ
ルーティングされます。

---

## 13. 拡張 API

### 13.1 IPC

ソケットは `$TESSA_IPC`、または `$XDG_RUNTIME_DIR/tessa.sock`。モードは
0600 で、同じユーザーなら任意のプロセスから利用できます。

`tessa-ctl` の主なコマンド:

```sh
tessa-ctl state
tessa-ctl hello
tessa-ctl extensions [--json]
tessa-ctl extension-enable weather off
tessa-ctl config
tessa-ctl config-check [file]
tessa-ctl config-diff file
tessa-ctl config-edit [file]
tessa-ctl perf [--json] [--reset]
tessa-ctl perf --watch=2
tessa-ctl rendering [--json]
tessa-ctl events [topic]
tessa-ctl workspace 3 [output]
tessa-ctl special notes
tessa-ctl move-to-special notes
tessa-ctl spawn foot -T notes
tessa-ctl launcher fire
tessa-ctl panel calendar
tessa-ctl panel extensions
tessa-ctl layout grid
tessa-ctl column-focus right
tessa-ctl column-move left
tessa-ctl column-width cycle
tessa-ctl consume
tessa-ctl expel
tessa-ctl window-move down
tessa-ctl swap 3 7
tessa-ctl reorder 7 before 3
tessa-ctl mode resize
tessa-ctl resize 40 30
tessa-ctl dispatch reload
tessa-ctl quit
```

`config-check <file>` は候補ファイルを適用せず検証します。`config-diff` は
候補を一時的に読み込み、診断とコンポジタの実効設定の差分を表示します
（パネル専用設定やコメントは差分に出ません）。`config-edit` は実行中設定を
一時ファイルへコピーして `$VISUAL`／`$EDITOR` を開き、検証と差分を表示して
から、確認後に書き戻してリロードします。パネル設定やコメントだけが変わった
場合も保存・リロードを確認します。

`perf` は描画コミット時間（`avg_us`、`p50_us`、`p95_us`、`max_us`、
予算超過フレーム数、scenefx の有無）を表示します。予算は
`frame_time_budget` です。`--json` には `outputs` 配列が含まれ、テキスト
出力には出力ごとの `OUTPUT` 行が追加されます。出力別の `presented`、
`zero_copy`、`vsync`、`missed`、`scanout`、`tearing`、`tearing_fail` を
確認できます。`perf --watch[=秒]` は指定間隔（既定 1 秒）で繰り返します。
`--reset` はグローバルと出力別の両方をリセットします。

`rendering [--json]` は direct scanout、tearing、`wp-tearing-control-v1`、
`linux-drm-syncobj-v1`、renderer/backend の timeline、出力色変換、
scenefx、DRM fd、出力別の scanout/zero-copy/tearing カウンタを表示します。
実機 DRM で直接スキャンアウトが起きたかは `zero_copy` と `scanout_frames`
で確認してください。headless は状態遷移のみで、実際の scanout は行いません。
HDR の color management はまだ公開しておらず、`color_management 0` が
正常です。理由と将来の要件は [RENDERING.ja.md](RENDERING.ja.md) にあります。

トラブルシュート時は次のように無効化できます:

```ini
direct_scanout = false
tearing = off
explicit_sync = false   # コンポジタの再起動が必要
```

生の IPC コマンド:

```text
HELLO <version> [<extension-token>]
CMD subscribe state|events|all
CMD state
CMD state-json
CMD config
CMD config-json
CMD extensions
CMD extensions-json
CMD extension-enable <id> on|off
CMD config-compare <path>
CMD perf
CMD perf-json
CMD perf-reset
CMD rendering
CMD rendering-json
CMD workspace <1..9|name> [output]
CMD move-workspace <1..9|name>
CMD toggle-scratchpad
CMD move-to-scratchpad
CMD special <name>
CMD move-to-special <name>
CMD toggle-group
CMD group-next
CMD group-prev
CMD group-add
CMD group-remove
CMD focus <id>
CMD close <id>
CMD spawn <shell command>
CMD launcher [query]
CMD panel <calendar|power|clipboard|screenshot|media|tray|audio|extensions> [output]
CMD layout [name] [output]
CMD column-focus <left|right|first|last>
CMD column-move <left|right|first|last>
CMD column-width <set|cycle|cycle-back|maximize|center> [value]
CMD column-consume
CMD column-expel
CMD window-move <up|down>
CMD swap <id> <id>
CMD reorder <id> <before|after> <target-id>
CMD resize <dx> <dy>
CMD float <id>
CMD status <id> <text>          (クリックコマンドはタブ区切り)
CMD reload
CMD notification-action <id> <key>
CMD quit
```

`HELLO <version> [<token>]` は省略可能で、最初に送れます。Tessa は
`VERSION\t1` とタブ区切りの `CAPABILITIES` 行を返し、接続を維持します。
ケイパビリティには `extensions`、`effects2`、`shell-modules` が含まれます。
未知の新しいバージョンは 1 にネゴシエートし、数値でない場合は
`ERR\tinvalid-version` を返します。監視付き拡張は
`TESSA_EXTENSION_TOKEN` を付け、Tessa はケイパビリティ行の後に
`EXTENSION\t<id>\t<permissions>` を返します。不正 token は
`ERR\tunauthorized` です。トークンを含む不正な `HELLO` は fail-closed で、
権限を持ちません。トークン付きハンドシェイクは認証前の購読を解除するため、
認証後に再購読してください。scoped クライアントの未知コマンドは
`ERR\tunknown-command\t<command>` です。HELLO なしでコマンドを送る従来
クライアント
（line protocol 0）も互換で、全権限のままです。`tessa-ctl hello` で
ネゴシエート結果を表示できます。

接続直後は何も届きません。`CMD subscribe ...` が必要です。`STATE` は
`END` までで 1 スナップショットです。

`OUT` は `name workspace focused layout`、`WIN` はタブ区切りで
`id, workspace, focused, floating, fullscreen, app_id, title, output, x, y, w, h, scratchpad, visible, group-id, group-active, on-screen, column, tile`
です。末尾 3 つは Scrolling 用の情報で、他のレイアウトでも常に出力されます。
`on-screen` はスクロール viewport 内、または Monocle/Stacking で実際に表示
されている場合に 1、`column` は所属カラム ID（なければ 0）、`tile` は
カラム内の 0 始まりの位置です。
`PANEL` は内蔵パネル監視の
`output, pid, supervised, notify-owner` です。同じスナップショットには
次の行も含まれます:

```
ACTIVE <workspace>
WORKSPACE <n> <name>
MODE <name>
SPECIAL <output> <name>
OCC <workspace> <count>
FOCUSED <window-id>
STATUS<TAB><id><TAB><text><TAB><click-command>
LAYER<TAB><namespace><TAB><output><TAB><layer><TAB><opacity><TAB><radius><TAB><blur>
```

`LAYER` は map 済みの layer-shell サーフェス（`tessa-background`、`tessa-bar`、
`tessa-overlay`、`tessa-notifications`、または外部の namespace）を報告します。
`layer` は 0=background、1=bottom、2=top、3=overlay です。`STATUS` と
`LAYER` はテキストに空白を含められるようタブ区切りです。生の行クライアントは
`CMD<TAB>status<TAB><id><TAB><text><TAB><command>` でクリックコマンドを
設定でき、`tessa-ctl status ... --exec <command>` はこの形式を使います。

Scrolling の出力では、さらにカラムごとに `VIEW` 1 行と `COL` 1 行が
出力されます。カラム番号は 0 始まり、座標はピクセルです。

```
VIEW <output> <workspace> <offset> <content-width> <viewport-width> <column-count> <focus-index>
COL  <output> <workspace> <index> <x> <width> <focused> <maximized> <tabbed> <window-count>
```

`offset` はカラム列の水平スクロール位置、`x` はオフセット適用後の画面上の
位置、`tabbed` はグループをタブ表示しているカラムであることを示します。

`EXT` 行は監視対象の拡張機能を表します:
`EXT <id> <state> <api> <pid> <ready> <restarts> <enabled> <permissions>`。
状態は `disabled`、`blocked`、`stopped`、`starting`、`running`、`ready`、
`failed` で、`starting` は予約済みで現在は出力されません。`ready` は拡張が
token で認証したことを示し、認証前は `running` のままです。

### 13.2 JSON と JSON-RPC

- `state --json`: `schema: 1` に加えて `tessa`、`line_protocol`、
  `extension_api`、`layout_api`、`effect_api`、出力、占有、フォーカス、
  ステータス、ウィンドウ、レイヤー、`extensions` 配列。ウィンドウには
  `tint`、`animation` 上書きオブジェクト、`tearing`、`on_screen`、`column`、
  `tile` が含まれます（テキスト `WIN` 行には含まれません）。
- `config --json`: `schema: 1` と同じ API バージョン、実効設定、`layouts` と
  `layout_cycle`、`workspace_tuning`、`rules`、`output_rules`、`hooks`、
  `event_rules`、`profiles`、`theme_roles`、`panel_modules`、
  `animation_view_ms`/`_curve`、拡張マニフェスト、`diagnostics`
- 未知の schema は拒否する前提で扱う

同じソケットで、1 行の JSON オブジェクトによる JSON-RPC 2.0 リクエストを
受け付けます:

```sh
tessa-ctl rpc '{"jsonrpc":"2.0","id":1,"method":"hello"}'
tessa-ctl rpc '{"jsonrpc":"2.0","id":7,"method":"state"}'
tessa-ctl rpc '{"jsonrpc":"2.0","id":"cfg","method":"config"}'
tessa-ctl rpc '{"jsonrpc":"2.0","id":"sub-1","method":"subscribe"}'
```

メソッドは `hello` / `capabilities`、`ping`、`state`、`config`、`subscribe`、
`unsubscribe` です。応答はリクエストの `id` をそのまま返します。`hello` は
`protocol: "tessa-jsonrpc"`、`version: 1`、`line_protocol: 1`、`tessa`、
`extension_api`、`layout_api`、`effect_api` と、`state`、`config`、
`events`、`subscriptions`、`request-ids`、`extensions`、`effects2` の
ケイパビリティを返します。エラーは標準の JSON-RPC コード
（`-32700` パースエラー、`-32601` 未知メソッド）を使います。

`subscribe` 後、ライフサイクルイベントは通知として届きます:

```json
{"jsonrpc":"2.0","method":"event","params":{"name":"workspace-change","ws":2,"previous-ws":1,"output":"eDP-1","subscription":"sub-1"}}
```

既存クライアント向けの行イベントはそのまま残り、JSON-RPC 購読者は同じ
フィールドを JSON 通知で受け取ります。

### 13.3 イベント

イベントは `EVENT\t<topic>\tkey=value...` 形式です。購読者だけにベスト
エフォートで配信され、詰まったクライアントは切断されます。

| トピック | タイミング | 主なフィールド |
| --- | --- | --- |
| `startup` | 起動完了 | — |
| `shutdown` | 終了 | — |
| `window-open` | map | id, ws, app, title, output |
| `window-close` | 破棄 | id, ws, app, title, output |
| `window-focus` | フォーカス変更/解除 | id, previous, ws, app, title, output |
| `workspace-change` | 出力の WS 変更 | ws, previous-ws, output |
| `special-change` | スペシャル WS の表示/非表示、移動 | ws, output, arg（名前。復帰時は省略） |
| `window-moved` | WS 移動 | id, ws, previous-ws, app, title, output |
| `layout-change` | レイアウト変更 | ws, output, arg |
| `mode-change` | 入力モード変更 | arg |
| `config-reload` | 設定再読み込み成功 | — |
| `launcher` | ランチャー要求 | arg, output |
| `panel` | パネル要求 | arg, output |
| `notification-action` | 通知アクション | id, action |
| `output-added` | 出力追加 | output, arg |
| `output-removed` | 出力削除 | output, arg |
| `animation-start` | 開く/WS スライド開始 | id, ws, output, arg (`open`/`workspace`) |
| `animation-done` | 開く/WS スライド完了 | id, ws, output, arg |
| `close-animation-start` | 閉じるスナップショット開始 | id, ws, output, arg (`close`) |
| `close-animation-done` | 閉じるスナップショット完了 | id, ws, output, arg |
| `extension-start` | 拡張プロセス開始 | arg（拡張 ID） |
| `extension-ready` | 拡張が token で認証 | arg |
| `extension-failed` | 拡張が異常終了 | arg |
| `extension-stop` | 拡張を明示的に停止 | arg |

### 13.4 フック

```ini
hook = window-open notify-send "Window opened" "$TESSA_TITLE"
hook = animation-done echo "$TESSA_ARG $TESSA_WINDOW_ID" >> ~/.cache/tessa-anim.log
```

フックは `/bin/sh` 経由、ユーザー権限で非同期実行されます。同一イベントに
複数指定できますが順序保証はありません。

環境変数:

| 変数 | 内容 |
| --- | --- |
| `TESSA_EVENT` | イベント名 |
| `TESSA_WINDOW_ID` | id |
| `TESSA_PREVIOUS_ID` | previous |
| `TESSA_WORKSPACE` | ws |
| `TESSA_PREVIOUS_WORKSPACE` | previous-ws |
| `TESSA_APP_ID` | app |
| `TESSA_TITLE` | title |
| `TESSA_OUTPUT` | output |
| `TESSA_ARG` | arg |
| `TESSA_FOCUSED_ID` | フォーカス中 id（なければ 0） |
| `TESSA_ACTIVE_WORKSPACE` | アクティブ WS |
| `TESSA_FOCUSED_OUTPUT` | フォーカス出力 |

### 13.5 ステータス

```sh
tessa-ctl status weather "Tokyo 18C"
tessa-ctl status weather "Tokyo 18C" --exec "weather-app"
tessa-ctl status weather --clear
```

id は安定で、同じ id は上書きされます。最大 8 件、159 バイトまで、全出力
共通です。クリックコマンドは `CMD spawn` 相当です。

### 13.6 監視付き拡張機能

拡張は設定で宣言する監視プロセスです。通常のクライアントと同じ IPC
ソケットを使います。

```ini
extension = id=weather; command=weatherd; api=1; permissions=read,status
extension = id=theme; command=tessa-theme; api=1; requires=weather; after=weather
```

`api` はコンポジタが対応する値（現在 1）でなければなりません。
`permissions` は `read`、`events`、`status`、`window`、`workspace`、
`layout`、`spawn`、`panel`、`control`、`extensions` のカンマ区切りで、
`all`/`none` も使えます。既定は `read,status` です。`requires` と `after`
は依存 ID で、未知 ID、重複、自己依存、循環は設定エラーになります。
`requires` は依存先が `ready` になるまで待ち、`after` は起動順だけを
制御します。スーパーバイザは pidfd で終了を検知し、指数バックオフ
（1 秒、2 秒、4 秒、以降 8 秒）で再起動します。
子には `TESSA_EXTENSION_ID`、`TESSA_EXTENSION_TOKEN`、
`TESSA_EXTENSION_API`、`TESSA_EXTENSION_PERMISSIONS` が渡されます。
`extension_ready_timeout`（既定 10000 ms、`0` で無効）は、認証しない
プロセスを停止します。トークンは起動ごとに再生成され、停止・無効化・
クラッシュ・reload で認証済み接続が失効します。

拡張はコマンド送信前に自分の token を通知します:

```text
HELLO 1 $TESSA_EXTENSION_TOKEN
VERSION 1
CAPABILITIES ...
EXTENSION weather read,status
```

権限外のコマンドには `ERR forbidden <command>` を返します。scoped 拡張の
未知コマンドは `ERR unknown-command <command>` です。トークンを含む不正な
`HELLO` は fail-closed で、全権限には戻りません。これは
サンドボックスではなく協調的なスコープ制御です。同じユーザーのプロセスは
token やソケットを直接読めます。token を送らない既存クライアント
（`tessa-panel`、`tessa-ctl`）は従来どおり全権限です。

`CMD extensions` と `CMD extensions-json` で実行状態を取得できます。
JSON の `extensions` 配列には `last_error`、`failures`、`next_restart_ms` も
含まれます。`CMD extension-enable <id> on|off` は現在のセッションだけ
変更します。
パネルの拡張一覧は `tessa-ctl panel extensions` で開き、Enter で選択項目を
有効／無効にします。完全な互換性契約は
[EXTENSION-API.ja.md](EXTENSION-API.ja.md) にあります。

### 13.7 ランチャー項目

```ini
launcher_entry = Notes | foot -e nvim ~/notes.md
launcher_entry = Lock screen | swaylock
```

通常の `.desktop` も検索対象です。`|` の前が表示名、後ろが `/bin/sh`
経由のコマンドです。

---

## 14. 設定例

### 14.1 最小構成

```ini
terminal = foot
panel = true
xwayland = true
animations = true
```

### 14.2 2 モニタ・固定ワークスペース

```ini
terminal = foot
gaps = 8
outer_gaps = 12
layout = master

workspace_pin = eDP-1 1
workspace_pin = HDMI-A-1 3

output-rule = output=eDP-1; layout=master; master-ratio=0.6
output-rule = output=HDMI-A-1; layout=grid; gaps=15; outer-gaps=20
output-rule = output=HDMI-A-1; ws=3; layout=columns; gaps=6

window-rule = app-id=pavucontrol; float=true; size=800x600
window-rule = title=Picture-in-Picture; float=true; position=1300,80
```

### 14.3 見た目重視

```ini
accent = #e2684f
bg_top = #162038
bg_bottom = #070a12
wallpaper_art = true

bar_height = 46
bar_top_margin = 12
bar_side_margin = 18
panel_bg = #0d1422
panel_fg = #f1f4fa
font = JetBrains Mono

border_width = 2
border_active = #e2684f
border_inactive = #293347
shadows = true
animation_ms = 220
corner_radius = 14
blur = true
blur_radius = 8
blur_passes = 3

hook = animation-done echo "$TESSA_ARG $TESSA_WINDOW_ID" >> ~/.cache/tessa-anim.log
hook = close-animation-done echo "closed $TESSA_WINDOW_ID" >> ~/.cache/tessa-anim.log
```

### 14.4 自動化

```ini
startup = fcitx5 -d
startup = ~/.config/tessa/layout-cascade.py &
hook = workspace-change ~/.config/tessa/on-workspace.sh
hook = window-open [ "$TESSA_APP_ID" = firefox ] && echo "$TESSA_TITLE"

bind = SUPER+SHIFT+r enter-mode resize
mode = resize
bind = h resize-width -30
bind = l resize-width 30
bind = Escape enter-mode default
mode = default
```

---

## 15. トラブルシューティング

### DRM で起動できない／画面が真っ暗

- TTY から通常ユーザーで起動しているか
- logind/seat のアクティブセッションか
- 入力デバイスへのアクセス権があるか
- root で直接起動していないか
- SSH 上なら `WLR_BACKENDS=headless` かネストした Wayland を使う
- GPU がなく Pixman で試す場合は `WLR_RENDERER=pixman`

### 設定が反映されない／再読み込みが失敗する

```sh
tessa-ctl config-check
tessa-ctl config
```

エラーのあるリロードは拒否されます。`config-check` は最後に読み込まれた
設定を検査するので、編集後に `reload` を実行してから確認してください。

### Arch のビルドで Zig / wlroots が違うと言われる

Tessa は Zig 0.17 と wlroots 0.20 を要求します。どちらも Arch 公式の
`zig` と `wlroots0.20` で提供されています。2.2 節の PKGBUILD でビルドして
ください。

```sh
zig version
pkg-config --modversion wlroots-0.20
```

1 つ目が `0.17.x`、2 つ目が `0.20.x` を返す必要があります。pkg-config が
`/usr/local` を拾っている場合は、ビルド環境からそのパスを外すか、
`PKG_CONFIG_PATH` を公式インストール先へ向けてください。

### Arch の Debug ビルドが R_X86_64_PC64 で失敗する

```text
fatal linker error: unhandled relocation type R_X86_64_PC64
note: in .../Scrt1.o:.sframe
```

古い Zig のセルフホストリンカーは、Arch の glibc 2.43 / GCC 16 が
`Scrt1.o` に入れる `.sframe` のリロケーションを処理できませんでした。
現在の `build.zig` は 3 つの実行ファイルすべてで LLVM/LLD を強制している
ため、このツリーでは発生しません。古いクローンでは
`-Doptimize=ReleaseSafe`（LLVM/LLD を使用）で回避するか、各実行ファイルに
`use_llvm = true` と `use_lld = true` を設定してください。

### パネルが出ない

- `PATH` に `tessa-panel` があるか
- `panel = true` か
- `TESSA_NO_PANEL` が設定されていないか
- `TESSA_PANEL_BIN` のパス
- `TESSA_PANEL_DEBUG=1` でログを確認

手動起動:

```sh
TESSA_PANEL_OUTPUT=HEADLESS-1 tessa-panel
```

### カーソルが見えない

Tessa 0.1.0 はクライアントがカーソル形状を要求するまでデフォルトカーソルを
設定していなかったため、壁紙やバーの上でポインタが見えないことがありました。
0.2.0 は起動時にデフォルトカーソルを設定します。0.2.2 はさらに、クライアントが
カーソルをクリアした後にパネルや壁紙などの layer surface へポインタが入った
時点で既定カーソルを復元します。wlroots は出力追加時にカーソル画像を適用する
ため、`wlr_cursor_warp_closest` や出力初期化後の手動再設定は不要です。

最小構成ではXcursorテーマも導入してください:

```sh
sudo apt install xcursor-themes
# モダンなテーマを使う場合
sudo apt install adwaita-icon-theme
```

`tessa` パッケージは `xcursor-themes` に依存するようになりました。古いテーマに
は `default` が無く `left_ptr` だけのものがありますが、Tessa 0.2.3 は
`default`、`left_ptr`、`arrow` の順で利用可能な名前を選び、ログに出します。
設定した `cursor_theme` を読み込めない場合は警告をログに出し、システムカーソル
へフォールバックします。`~/.local/state/tessa/tessa.log` またはコンポジタの
出力を確認してください。

仮想マシンでは DRM のハードウェアカーソルプレーンが透明になることがあります。
Tessa 0.2.3 は vmwgfx、vboxvideo、bochs、qxl、cirrus、virtio_gpu を検出すると、
直接起動した場合でも `WLR_NO_HARDWARE_CURSORS=1` を自動設定します。
`tessa-session` は他の VM も `systemd-detect-virt` で検出して設定します。
手動で指定する場合は次を使ってください:

```sh
WLR_NO_HARDWARE_CURSORS=1 tessa
```

### ターミナルが起動しない

既定のターミナルは `kitty` ですが、旧パッケージでは `Suggests` 扱いで自動
インストールされませんでした。ターミナルを導入してください:

```sh
sudo apt install kitty
# 3D アクセラレーションのない VM では foot が確実です
sudo apt install foot
```

Tessa 0.2.3 は既定ターミナルが見つからない場合、`foot`、`kitty`、
`alacritty`、`wezterm`、`xterm` の順で解決し、使用したコマンドをログに
出します。明示的に設定した `terminal = ...` は置き換えません。Kitty は
EGL/GL が必要なので、GPU のない VM では `foot` を使うか
`terminal = foot` を設定してください。コンポジタの起動失敗と決めつけず、
ターミナル自身のstderrとTessaのログを確認してください。

### Kitty が一瞬表示されて終了する

ウィンドウが map された直後に消える場合、多くの場合は Tessa が unmap
したのではなく、Kitty 本体または Kitty 内のシェルが終了しています。同じ
セッション内の `foot` から確認してください:

```sh
tessa-ctl spawn foot
WAYLAND_DEBUG=1 kitty
```

- **Tessa のログに `new toplevel` が無い:** コマンドが接続していません。
  `terminal`、`PATH`、ランチャー項目を確認してください。
- **`new toplevel` の後にウィンドウが消える:** Kitty が終了しています。
  Kitty の出力で EGL、GBM、DBus、シェル起動のエラーを確認してください。
  3D の動かない VM では `foot` を使ってください。
  `LIBGL_ALWAYS_SOFTWARE=1` は Mesa のソフトウェア EGL が入っている場合だけ
  有効です。
- **`importing the supplied dmabufs failed` / Broken pipe が vmwgfx で出る:**
  vmwgfx の linux-dmabuf 不具合で、Kitty の問題ではありません。Tessa 0.2.3 は
  vmwgfx で `linux-dmabuf-v1` を無効にし、クライアントを `wl_shm` に
  フォールバックさせます。再検証する場合だけ
  `TESSA_ALLOW_LINUX_DMABUF=1` を設定してください。
- **`Terminal=true` のデスクトップエントリがコマンド終了直後に閉じる:**
  これは仕様です。Tessa は `terminal sh -c '<command>'` として起動するため、
  一瞬で終わるコマンドはターミナルも一瞬で終了します。`kitty.desktop` は
  `Terminal=false` です。

### X11 アプリが起動しない

- `xwayland-satellite` が `PATH` にあるか
- `TESSA_XWAYLAND_BIN` のパス
- `xwayland = true`
- `TESSA_NO_XWAYLAND` が設定されていないか
- ログに `xwayland: '...' not found; X11 apps disabled` が出ていないか
- ログに `xwayland: connected on :N` が出ているか。Tessa 0.2.3 はこの後に
  初めて `DISPLAY` を設定します

サテライトを起動できない場合に架空の `DISPLAY` を設定しないため、X11
アプリは存在しないサーバーへ接続するのではなく、明確に失敗します。
`XMODIFIERS` も X ディスプレイが準備できて `xim = true` の場合だけ設定します。
XWayland が有効な場合、`startup` フックと `TESSA_STARTUP` は準備後に実行される
ため、`fcitx5 -d` などは X 環境を受け取ります。サテライトが無い場合は即座に
実行されます。

### IME が効かない

- `zwp_input_method_v2` 対応の IME（Fcitx5 など）が起動しているか
- `XMODIFIERS=@im=fcitx` が X11 クライアントへ渡っているか
- `xim_start` を使う場合、X ディスプレイの出現後に起動しているか
- Fcitx5 を二重起動していないか
- XWayland を無効にしている場合、X ディスプレイが無いため `XMODIFIERS` は
  意図的に設定されません
- Fcitx5 起動後に Firefox などのキー入力が止まる場合は、ログに
  `virtual keyboard added` / `input method grabbed keyboard` が繰り返し
  出ていないか確認してください。現在のビルドはこの text-input フォーカス
  ループを避けます。更新後はセッションを再起動してください。

### 外部バー/ランチャーが動かない

- サーフェスが存在するか確認: `tessa-ctl state | grep LAYER` に namespace
  （`waybar` や `wofi` など）が出るか
- Tessa Panel と外部バーを同じ辺にアンカーしている場合、両方が領域を予約
  します。外部バーだけにするなら `panel = false` にしてください
- Waybar 0.14 以降は `ext/workspaces` を使います。旧 `wlr/workspaces` は
  削除されています。`wlr/taskbar` は `wlr-foreign-toplevel-management` が
  必要で、Tessa はこれを提供します
- Wofi は既定で layer-shell を使います。`--normal-window` も動作しますが、
  キーボードフォーカスは通常トップレベルのフォーカス規則に依存します。
  layer モードを推奨します
- `EXCLUSIVE` キーボードを要求する layer は map 時にフォーカスされ、
  `ON_DEMAND` はクリック時にフォーカスされます。キーボード対話を要求しない
  クライアントはキー入力を受け取れません
- Tessa Panel、Waybar、Quickshell は
  `org.kde.StatusNotifierWatcher` を奪い合い、tray が埋まるのは 1 つだけです

### 画面共有できない

- `xdg-desktop-portal`、`xdg-desktop-portal-wlr`、PipeWire
- `tessa.portal` の配置
- xdpw の `chooser_type` と `output_name`
- `XDG_CURRENT_DESKTOP=Tessa`

### 角丸・ブラーが出ない

- `-Dscenefx=false` でビルドしていないか（scenefx が既定）
- `tessa-ctl config` の `scenefx 1`
- 実行時に scenefx の共有ライブラリが見えているか
- scenefx ビルドでは `WLR_RENDERER=pixman` を使っていないか
- ブラーは不透明ウィンドウでは見えない

### 出力設定が戻る

- `TESSA_OUTPUT_CONFIG` のパス
- `outputs.conf` の権限と内容
- 出力名が再起動後も同じか
- 出力の `enabled` 状態は保存されない

### headless で確認したい

```sh
./scripts/run-headless.sh
# 別シェル
export PATH="$PWD/zig-out/bin:$PATH"
export XDG_RUNTIME_DIR=/tmp/tessa-headless
tessa-ctl state
./scripts/screenshot.sh /tmp/tessa.png
```

### ログ

```sh
TESSA_DEBUG=1 ./zig-out/bin/tessa
TESSA_PANEL_DEBUG=1 tessa-panel
TESSA_CTL_DEBUG=1 tessa-ctl state
```

---

## 16. 既知の制限

- **物理 DRM/libinput は Arch Linux 実機で確認済みですが、デバイス固有の
  未検証領域があります。** ディスプレイマネージャー経由を含む通常セッション、
  DRM 出力、キーボード、マウス、IME、XWayland クライアントを 0.2.4 で実際に
  確認しています。0.2.5 は Arch Linux 実機で Zig 0.17 / wlroots 0.20 /
  scenefx 0.5 の headless スイート全 78 テストスクリプトが plain／scenefx の両構成で
  成功しており、ポータルの ScreenCast、トレイ、通知、ポインタ操作も含みます。
  新しいツールチェーンでの実 DRM/libinput セッション検証は未実施です。
  タッチパッドのデバイス別チューニング、VRR/Adaptive Sync のコミット、
  特殊なマルチ GPU／モニター構成は、対応する実機での追加確認が必要です。
- **Arch パッケージは公式ツールチェーンを使用**。PKGBUILD は公式の `zig`
  0.17、`wlroots0.20`、`scenefx` を前提とし、エフェクトビルドが既定です。
  `makepkg` が失敗した場合は、トラブルシューティングにある
  コンパイラと pkg-config のバージョンを添えて報告してください。
- **フラクショナルスケーリングは部分的**。Wayland の対応クライアントには
  正確なスケールを通知しますが、パネルは整数 Cairo バッファでダウンサンプル
  され、非対応クライアントは切り上げスケールです。XWayland は
  `xwayland-satellite` 依存で未検証です。
- **出力の無効化は永続化されない**。`wlr-randr --off` は実行中のみです。
- **パネルは出力ごとに 1 プロセス**。独立動作とクラッシュ分離の代わりに
  メモリ使用量が増えます。
- **ロック画面の検証は最小限**。`ext-session-lock-v1` は実装済みですが、
  swaylock/PAM の実環境テストは未完了です。
- **idle は外部依存**。`swayidle`、`wlopm` などが必要です。
- **クリップボード履歴はテキストのみ・メモリのみ**。最大 8 件、各 16 KiB。
- **通知は基本機能のみ**。Pango の範囲外 HTML、通知音、通知ごとの出力固定は
  未対応です。
- **トレイにメニューなし**。StatusNotifier の登録、アイコン、アクティベート、
  ステータス、削除には対応しますが DBusMenu は未対応です。
- **メディアは最初の MPRIS プレイヤーのみ**。アルバムアートなし。
- **システム表示は基本のみ**。バッテリーは `/sys/class/power_supply`、
  ネットワークはデフォルトルートと `operstate`。
- **角丸・ブラーは既定の scenefx ビルドに含まれる**。scenefx 0.5 と GLES2 が
  必要で、pixman レンダラーを使う場合は `-Dscenefx=false` で無効にします。
- **ウィンドウ効果はシンプル**。角丸・ブラーは scenefx ビルド（既定）のみ。
  閉じる
  アニメーションはコンポジタ起点の close のみで、クライアント自身の close は
  即時です。
- **プロファイルはレイアウト／チューニングのみ**。出力別の色やパネル寸法は
  `output-rule` のテーマキーを直接使います。
- **構造系のウィンドウルールは map か再読込が必要**。装飾系（色、不透明度、
  角丸、ブラー、影、ボーダー幅）はタイトル/app-id 変更で即時再評価されますが、
  `float`、`workspace`、`size`、`position`、`fullscreen` はメタデータ変更では
  再適用されません。
- **レイアウトヘルパーの応答は完成したスナップショットです**。出力別の
  非同期ヘルパー、フォーカス／緊急度メタデータ、バージョンネゴシエーションは
  実装済みですが、矩形の部分ストリーミング更新は未実装です。
- **JSON-RPC は読み取りとイベント購読のみ**。変更操作は行コマンドを使います。
- **設定編集は端末ベース**。コンポジタ起動中に
  `tessa-ctl config-check FILE`、`config-diff FILE`、`config-edit` で検証、
  実効設定の差分プレビュー、確認付きの適用／リロードができます。
  `config-edit` は `$VISUAL`／`$EDITOR` を使い、専用 GUI エディタはありません。
  検証と差分プレビューにはコンポジタの起動が必要です。
- 出力の `enabled` 状態、通知の出力固定、カスタム通知音などは未対応です。

---

## 17. 関連ドキュメント

- [README.ja.md](../README.ja.md) — 概要、ビルド、スクリーンショット、
  既定キーバインド
- [CUSTOMIZATION.ja.md](CUSTOMIZATION.ja.md) — ルール、レイアウト、
  テーマ、パネル、ヘルパープロトコルの詳細
- [EXTENDING.ja.md](EXTENDING.ja.md) — IPC、イベント、フック、JSON、
  ステータス、拡張例
- [ARCHITECTURE.ja.md](ARCHITECTURE.ja.md) — シーングラフ、IPC、入力、
  レンダリング、パネル内部
- [ROADMAP.ja.md](ROADMAP.ja.md) — 実装済み／未実装の項目
- [DEVELOPMENT.ja.md](DEVELOPMENT.ja.md) — headless 開発、テスト、
  スクリーンショット、XWayland/IME の検証
