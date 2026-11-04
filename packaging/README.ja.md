[English](README.md) | **日本語**

# Tessa のパッケージング

Tessa は Zig 0.17 を必要とし、wlroots 0.20 ABI にリンクします。既定ビルドは scenefx 0.5 も使用します。ディストリビューション向けパッケージではこれらを固定する必要があります。ソースビルドは `build.zig` で `wlroots-0.20` を明示的に参照します。

## Arch Linux

Arch の公式リポジトリは Zig 0.17 を `zig`、wlroots 0.20 を `wlroots0.20`、scenefx 0.5 を `scenefx` として提供しており、このツリーと一致します。ビルド依存関係をインストールします:

```sh
sudo pacman -Syu --needed base-devel git zig wlroots0.20 scenefx \
  wayland wayland-protocols libxkbcommon libinput pixman libdrm \
  libegl mesa cairo pango glib2
```

次に `tessa-git` パッケージをビルドします:

```sh
git clone https://github.com/Keychrom/Tessa.git
cd Tessa/packaging/arch
makepkg -si
```

PKGBUILD は `depends=('wlroots0.20' ...)` と `makedepends=('git' 'zig')` を宣言し、ビルド手順で `scripts/build.sh` を呼び出します。このスクリプトは Zig 0.17.x を必要とします。

インストールされるもの:

- `/usr/bin/tessa`、`/usr/bin/tessa-panel`、`/usr/bin/tessa-ctl`
- `/usr/bin/tessa-session`
- `/usr/share/wayland-sessions/tessa.desktop`
- `/usr/share/tessa/config.example`
- `/usr/share/xdg-desktop-portal/portals/tessa.portal`
- man ページとドキュメント（`/usr/share` 以下）

PKGBUILD は `scenefx` に依存し、既定で角丸と背景ブラーを有効にします。plain wlroots シーンにする場合は、ソースチェックアウトを `-Dscenefx=false` でビルドします。`xwayland-satellite` は任意で、AUR の `xwayland-satellite-git` から入手できます。これがないと X11 アプリケーションは起動しません。`kitty`/`foot` はユーザーの選択です。画面共有にはさらに `xdg-desktop-portal`、`xdg-desktop-portal-wlr`、PipeWire が必要です。インストールされる `tessa.portal` は、`XDG_CURRENT_DESKTOP=Tessa` のときに Screenshot と ScreenCast のポータルを wlr バックエンドへ振り分けます。シングルモニタの場合は `~/.config/xdg-desktop-portal-wlr/config` を次のように設定します:

```ini
[screencast]
chooser_type=none
output_name=HDMI-A-1
```

## Debian / Ubuntu

通常のインストールには
[Ubuntu / Debian インストーラー](https://keychrom.github.io/ja/docs/install-script/)
を使ってください。ここから先は、下流パッケージング向けの旧 `.deb` ビルド手順です。

リポジトリルートの `debian/` ディレクトリは debhelper と Zig を使用します。`debian/control` に記載された開発パッケージが入ったマシンでビルドします:

```sh
sudo apt install debhelper dpkg-dev fakeroot
ZIG="$HOME/.local/zig-0.17.0/zig" ./scripts/build-deb.sh
sudo apt install ./dist/tessa_<version>_<arch>.deb
```

> **0.2.4 が最後の `.deb` リリースになる予定です。** これは Zig 0.16 と wlroots 0.19 を対象にした最後のパッケージです。現在のソースツリー（`0.2.5`）は Zig 0.17、wlroots 0.20、scenefx 0.5 を対象としており、Debian の定義は下流のパッケージング用に残していますが、新しいバイナリリリースは予定していません。

Debian ビルドは `-Dscenefx=false` を渡します。Ubuntu 26.04 には scenefx 0.5 の開発パッケージがないため、`.deb` は角丸と背景ブラーのない plain wlroots シーンを使用します。

このスクリプトは `dpkg-buildpackage -b -us -uc -d` を実行し、`.deb`、`.buildinfo`、`.changes` を `dist/` に集めてパッケージのメタデータを表示します。`-d` は宣言されたビルド依存関係のチェックを省略します。Ubuntu 26.04 は古い Zig を同梱しているためです。代わりに、スクリプトが指定された Zig のバージョンが 0.17.x であることを検証します。

パッケージは同じバイナリ、セッションエントリ、設定例、ポータルセレクタをインストールします。wlroots 0.20 の開発ファイルと、リンク時に使う `wlroots-0.20` の pkg-config 名がコンポジタの ABI を固定します。

Zig 0.17 が必要です。ディストリビューションが古い Zig を同梱している場合は、上流の 0.17 ツールチェーンをインストールし、ビルド前に `ZIG=...` で指定してください。最初のパッケージ監査には `lintian dist/*.deb` を実行します。

手動で `/usr/local` にインストールした環境へ `.deb` をインストールしないでください。置き換える意図がない限り、両者は同じバイナリとセッションエントリを別のプレフィックスへコピーします。

## 手動インストール

開発用またはユーザーローカルへのインストールには次を使います:

```sh
./scripts/install-session.sh
```

既定では `~/.local` 以下へインストールします。システム全体へインストールする場合は `PREFIX=/usr/local` と `sudo` を使用できます。
