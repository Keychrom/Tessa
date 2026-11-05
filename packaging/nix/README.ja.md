# NixOS で Tessa を使う

このリポジトリは flake として、パッケージと NixOS モジュールを提供します。
モジュールはコンポジタ、Wayland セッション、XDG ポータル、任意の
XWayland サテライトをインストールし、SDDM/GDM/greetd のセッション一覧に
Tessa を登録します。

## パッケージ

```sh
nix build github:Keychrom/Tessa
./result/bin/tessa --help
```

チェックアウトから:

```sh
nix build .#tessa
```

2つのバリアントがあります:

- `packages.tessa`（既定）: scenefx 0.5 による角丸・ブラー・影を使います。
  EGL/GLES2 が動作する GPU が必要です。
- `packages.tessa-plain`: `-Dscenefx=false` でビルドし、pixman の
  ソフトウェア描画で動きます。3D アクセラレーションのない VM では
  `environment.sessionVariables.WLR_RENDERER = "pixman";` と組み合わせて
  使ってください。

パッケージは nixpkgs の Zig 0.17、wlroots 0.20、scenefx 0.5 を使います。
`translate-c`/`arocc` は固定したリビジョンから Zig のローカル `zig-pkg` に
コピーするため、サンドボックス内でネットワークアクセスは不要です。
`build.zig.zon` の依存を更新した場合は `package.nix` の URL、リビジョン、
ハッシュ、ディレクトリ名も更新してください。

## NixOS モジュール

flake を input に追加し、モジュールを import します:

```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.tessa.url = "github:Keychrom/Tessa";

  outputs = { self, nixpkgs, tessa, ... }: {
    nixosConfigurations.tessa-vm = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        tessa.nixosModules.default
        {
          programs.tessa.enable = true;

          # グラフィカルログインにはディスプレイマネージャが必要です。
          services.displayManager.sddm.enable = true;

          programs.tessa.extraPackages = with nixpkgs.legacyPackages.x86_64-linux; [
            foot
            fuzzel
            grim
            slurp
            fcitx5
            fcitx5-mozc
          ];

          # 任意: Tessa の設定を直接書く。
          # programs.tessa.config = ''
          #   panel = true
          #   panel_renderer = gpu
          #   wallpaper_animation = auto
          # '';
        }
      ];
    };
  };
}
```

ビルドして切り替えます:

```sh
sudo nixos-rebuild switch --flake .#tessa-vm
```

ログイン画面で **Tessa** を選んでください。モジュールは
`programs.tessa.defaultSession = false` にしない限り
`services.displayManager.defaultSession = "tessa"` を設定します。

### オプション

| オプション | 既定値 | 説明 |
| --- | --- | --- |
| `programs.tessa.enable` | `false` | Tessa と Wayland セッションを導入 |
| `programs.tessa.package` | `callPackage ./package.nix` | 使用するパッケージ |
| `programs.tessa.configFile` | `null` | `/etc/tessa/config` に置く設定ファイル |
| `programs.tessa.config` | `null` | インライン設定（`configFile` と排他） |
| `programs.tessa.extraPackages` | `[ ]` | ターミナル、ランチャー、IME、ツール |
| `programs.tessa.xwayland` | `true` | X11 用に `xwayland-satellite` を追加 |
| `programs.tessa.portals` | `true` | スクリーンショット/画面共有用の wlr ポータル |
| `programs.tessa.defaultSession` | `true` | ディスプレイマネージャの既定セッションにする |
| `programs.tessa.networkmanager` | `false` | コントロールセンターの Wi-Fi 用に NetworkManager を有効化 |
| `programs.tessa.bluetooth` | `false` | コントロールセンターの Bluetooth 用に BlueZ を有効化 |
| `programs.tessa.powerProfiles` | `false` | 電源プロファイル用に power-profiles-daemon を有効化 |

モジュールは polkit、D-Bus、`hardware.graphics` も有効にします。
NetworkManager、Bluetooth、power-profiles-daemon はすべての Tessa 環境で
使うとは限らないため opt-in です。有効にすると対応する NixOS サービスも
有効になります。サービスが無い場合、コントロールセンターは該当セクションを
利用不可として表示するので、Tessa パッケージを変えずに後から有効化できます。

## 最小のテスト VM

3D アクセラレーションのない VM 向けの完全な例です。flake の
`tessa-plain` を使います:

```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.tessa.url = "github:Keychrom/Tessa";

  outputs = { self, nixpkgs, tessa, ... }: {
    nixosConfigurations.tessa-vm = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        tessa.nixosModules.default
        {
          programs.tessa.enable = true;
          programs.tessa.package =
            tessa.packages.x86_64-linux.tessa-plain;
          programs.tessa.extraPackages = with nixpkgs.legacyPackages.x86_64-linux; [
            foot
            grim
          ];

          services.displayManager.sddm.enable = true;

          # 3D アクセラレーションがないと SDDM の Wayland グリーターが
          # 失敗することがあるため、VM では X11 グリーターを使う。
          services.displayManager.sddm.wayland.enable = false;
          services.xserver.enable = true;

          # テスト VM 専用: Tessa セッションへ自動ログイン。
          services.displayManager.autoLogin.enable = true;
          services.displayManager.autoLogin.user = "suiren";

          # vmwgfx/VirtualBox（3D なし）。
          environment.sessionVariables.WLR_RENDERER = "pixman";
        }
      ];
    };
  };
}
```

NixOS 26.05 の vmwgfx VM で、パッケージ、モジュール、SDDM セッション、
キーボード入力、パネル、ランチャーまで確認済みです。この GPU では
`tessa-plain` と `WLR_RENDERER=pixman` が必要です。scenefx ビルドは 3D
アクセラレーションなしでは GLES2 コンテキストを作れません。実機では既定の
`tessa` パッケージを使ってください。

## 注意

- Tessa は `$TESSA_CONFIG`、`$XDG_CONFIG_HOME/tessa/config`、
  `~/.config/tessa/config` の順に読みます。モジュールの
  `configFile`/`config` は `/etc/tessa/config` を使い、システム全体に
  `TESSA_CONFIG` を設定します。
- nixpkgs に `xwayland-satellite` がある場合は自動で追加されます。ない場合は
  `extraPackages` に別の XWayland パッケージを追加してください。
- パッケージは `/share/wayland-sessions/tessa.desktop`、
  `/share/tessa/config.example`、
  `/share/xdg-desktop-portal/portals/tessa.portal` をインストールします。
- ウィンドウシェーダーは既定で有効です。無効化するには
  `TESSA_SHADER_DISABLE=1` を設定するか、`-Dshaders=false` でビルドします。
