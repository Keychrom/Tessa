[English](QUICKSTART.md) | **日本語**

<!-- tessa-site-notice:start -->
> [!NOTE]
> このドキュメントは Web サイトに移植されました。最新版は <https://keychrom.github.io/ja/docs/quickstart/> を参照してください。
<!-- tessa-site-notice:end -->

# クイックスタート

このページでは、Tessa をインストールして最初のセッションを起動するまでを説明します。すべてのオプションと設定キーは[ガイド](GUIDE.ja.md)を参照してください。

Tessa は GNOME や KDE の中で起動するアプリではなく、Wayland セッションそのものです。作業を保存してログアウトしてから始めてください。

## はじめる前に

必要なもの:

- Arch Linux、Ubuntu/Debian（`install.sh` を使用）、または Wayland/DRM のグラフィックス環境が動作する Linux
- ソースビルドの場合は Zig 0.17、wlroots 0.20、scenefx 0.5
- ターミナル（Tessa の既定は `kitty`）
- グラフィカルセッションにアクセスできる一般ユーザー（root で実行しない）

既定ビルドは scenefx を使い、GLES2 が必要です。VM や GLES2 を提供できない GPU では、後述の `-Dscenefx=false` の plain ビルドを使います。

## 1. インストール

### Arch Linux（推奨）

ビルド依存を導入します:

```sh
sudo pacman -Syu --needed base-devel git zig wlroots0.20 scenefx \
  wayland wayland-protocols libxkbcommon libinput pixman libdrm \
  libegl mesa cairo pango glib2 gdk-pixbuf2 noto-fonts-cjk
```

`tessa-git` パッケージをビルドしてインストールします:

```sh
git clone https://github.com/Keychrom/Tessa.git
cd Tessa/packaging/arch
makepkg -si
```

パッケージは `tessa`、`tessa-panel`、`tessa-ctl`、セッションエントリ、設定例、画面共有用ポータルセレクタをインストールします。

#### 推奨パッケージ

ターミナル、出力・スクリーンショット用ツール、画面共有ポータル、セッションユーティリティを導入します:

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

### Ubuntu / Debian（推奨）

[Ubuntu / Debian インストーラー](https://keychrom.github.io/ja/docs/install-script/) を使います。現在の `0.2.5` ツリーをインストールし、Zig 0.17、wlroots 0.20、scenefx 0.5、不足している Wayland ライブラリを `/opt/tessa` にビルドします。システムの Wayland ライブラリは置き換えません。

```sh
git clone https://github.com/Keychrom/Tessa.git
cd Tessa
./install.sh --check
./install.sh
```

既定ではターミナル、フォント、fcitx5 + Mozc、ポータル、PipeWire も導入します。これらを入れない場合は `--minimal`、scenefx のエフェクトなしでビルドする場合は `--plain` を使います。インストーラーは試験的なため、実行前に[テスト状況](https://keychrom.github.io/ja/docs/install-script/)を確認してください。

### NixOS

リポジトリは NixOS モジュールを含む flake です:

```nix
inputs.tessa.url = "github:Keychrom/Tessa";

modules = [
  tessa.nixosModules.default
  {
    programs.tessa.enable = true;
    services.displayManager.sddm.enable = true;
  }
];
```

完全な VM の例、pixman 専用 VM 向けの `tessa-plain`、モジュールの
オプションは
[NixOS パッケージングガイド](https://github.com/Keychrom/Tessa/blob/main/packaging/nix/README.ja.md)
を参照してください。

### Tessa Linux ISO

Calamares と日本語入力を設定済みの Arch ベースのライブ/インストーラーイメージは
[Tessa Linux ISO](https://keychrom.github.io/ja/docs/install-iso/) から
ビルドできます。

### その他のディストリビューション

[ソースからビルド](GUIDE.ja.md#24-ソースからビルド開発向け)を参照してください。既定ビルドには Zig 0.17、wlroots 0.20、scenefx 0.5 が必要です。plain wlroots シーンにする場合は `-Dscenefx=false` を付けます。

## 2. Tessa を起動する

現在のデスクトップからログアウトし、ログイン画面で **Tessa** を選びます（GDM、SDDM、greetd、LightDM など）。

最初に TTY から試す場合は、テキストコンソールにログインして次を実行します:

```sh
tessa
```

Tessa は出力ごとにパネルプロセスを自動起動します。`tessa-panel` を自分で起動しないでください。終了は `Super+Shift+E` です。

## 3. 最初のキー操作

`Super` は Windows キーまたは Command キーです。

| キー | 動作 |
| --- | --- |
| `Super+Return` | ターミナル（`kitty`）を開く |
| `Super+D` | ランチャーを開く |
| `Super+Q` | フォーカス中のウィンドウを閉じる |
| `Super+1` … `Super+9` | ワークスペースを切り替える |
| `Super+Shift+1` … `9` | ウィンドウをワークスペースへ移動する |
| `Super+H/J/K/L` | 左/下/上/右へフォーカス |
| `Super+Space` | フローティングを切り替える |
| `Super+F` | フルスクリーンを切り替える |
| `Alt+Tab` | MRU ウィンドウスイッチャー（全出力・全ワークスペース） |
| `Super+Shift+Tab` | Scene デッキを開く |
| `Super+R` | 設定を再読み込みする |
| `Super+Shift+E` | Tessa を終了する |

ウィンドウをクリックするとフォーカスできます。バーのチップをクリックするとそのウィンドウへフォーカスし、バーの上でスクロールするとワークスペースを切り替えられます。完全な一覧は[既定キーバインド](GUIDE.ja.md#7-既定キーバインドとマウス)を参照してください。

## 4. 自分好みに設定する

設定ファイルがなくても Tessa は動作します。設定例から始める場合:

```sh
mkdir -p ~/.config/tessa
# Arch パッケージ / .deb
cp /usr/share/tessa/config.example ~/.config/tessa/config
cp /usr/share/tessa/panel.example ~/.config/tessa/panel.conf
# Ubuntu / Debian の ./install.sh（既定 PREFIX=/opt/tessa）
# cp /opt/tessa/share/tessa/config.example ~/.config/tessa/config
# cp /opt/tessa/share/tessa/panel.example ~/.config/tessa/panel.conf
```

ソースツリーでは `config/config.example` と `config/panel.example` を使います。
`config` はコンポジタの動作と共有テーマ、`panel.conf` はバー、ランチャー、
ポップオーバー、壁紙、パネルのフォント/色、ブランドロゴ
（`logo_text`/`logo_icon`）、コントロールセンター、パネル用コマンドの設定です。
`config` に残した Panel 設定も互換性のため動作します。

どちらかのファイルを編集したら `Super+R` で再読み込みします。確認:

```sh
tessa-ctl config-check
tessa-panel --check
tessa --check-config ~/.config/tessa/config
```

最初に変えることが多いのは `terminal = foot`、`font`、壁紙色、`bind =` の行です。ウィンドウルール、レイアウト、エフェクト、パネル、キーの全一覧は[カスタマイズ](CUSTOMIZATION.ja.md)を参照してください。

## 5. 必要に応じた追加設定

- **X11 アプリケーション:** `xwayland-satellite` を `PATH` に導入するか、`TESSA_XWAYLAND_BIN` に絶対パスを設定します（AUR では `xwayland-satellite-git`）。
- **日本語入力:** `fcitx5` と `fcitx5-mozc` を導入し、設定に `startup = fcitx5 -d` を追加します。X11 クライアントも使う場合は `xim = true` と `xim_server = fcitx` を設定し、`startup` で起動していない場合だけ `xim_start = fcitx5 -d` を追加します。
- **画面共有:** `xdg-desktop-portal`、`xdg-desktop-portal-wlr`、PipeWire を導入します。パッケージ版セッションではポータルセレクタもインストールされます。

## うまくいかないとき

- **`Super+Return` でターミナルが開かない:** `kitty` を導入するか、`terminal` をインストール済みのターミナルに変更してください。
- **「Failed to create renderer」で終了する:** 既定の scenefx ビルドは GLES2 が必要です。`-Dscenefx=false` で plain ビルドを作り、`WLR_RENDERER=pixman tessa` で起動してください。
- **X11 アプリケーションが起動しない:** `xwayland-satellite` を導入してください。
- **角丸やブラーが出ない:** `tessa-ctl config | grep scenefx` を確認します。`scenefx 0` なら、実行中のバイナリは `-Dscenefx=false` でビルドされています。
- **動作が重い:** 設定で `blur = false`、`shadows = false`、`animations = false` にして `Super+R` を押してください。ブラーが最も重いエフェクトです。詳しくは[描画・ゲーム機能](RENDERING.ja.md)を参照してください。
- **設定が読み込まれない:** `tessa --check-config` を実行し、ファイル名とパスを確認してください。
- **パネル設定が反映されない:** `panel.conf` を `config` の隣に置くか `TESSA_PANEL_CONFIG` を設定し、`tessa-panel --check` と `tessa-ctl config-check` を実行してください。`panel.conf` の構文エラーはコンポジタの設定検証も失敗させます。
- **Scene デッキが空:** `tessa-ctl scene reload` を実行してください。Scene は `~/.config/tessa/scenes` または `TESSA_SCENE_DIR` にあります。
- **音声入力デバイスが出ない:** デバイス選択には `wpctl` または `pactl` が必要です。`volume_*` のカスタムコマンドは出力側だけを上書きします。
- **解決しない:** [トラブルシューティング](GUIDE.ja.md#15-トラブルシューティング)を見るか、[GitHub](https://github.com/Keychrom/Tessa/issues) で Issue を作成してください。

## 次に読むもの

- [セットアップ & カスタマイズガイド](GUIDE.ja.md)
- [カスタマイズリファレンス](CUSTOMIZATION.ja.md)
- [描画・ゲーム機能](RENDERING.ja.md)
- [拡張を作る](EXTENDING.ja.md)
- [Extension API v1](EXTENSION-API.ja.md)
