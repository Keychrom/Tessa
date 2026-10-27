**日本語** | [English](GUIDE.md)

# Tessa セットアップ & カスタマイズ完全ガイド

このガイドは、現在の Tessa ツリーで使えるセットアップ方法とカスタマイズ
項目を一か所にまとめたものです。対象は 0.6 以降の未実装項目を除く、
0.5 ロードマップまでの実装です。

Tessa は **wlroots ベースのコンポジタ本体 `tessa`**、**タスクバー／
ランチャー／壁紙を担当する `tessa-panel`**、**自動化用の `tessa-ctl`** の
3 プロセス構成です。Waybar、Rofi、wofi などの外部シェルは不要です。

- コンポジタ: `zig-out/bin/tessa`
- パネル: `zig-out/bin/tessa-panel`（出力ごとに 1 プロセス）
- CLI: `zig-out/bin/tessa-ctl`

設定はフラットな `key = value` 形式です。設定の再読み込みは `Super+R`、
診断は `tessa-ctl config-check`、実効値の確認は `tessa-ctl config` で行います。

---

## 1. 必要環境

### 必須

- Linux（開発・検証は Ubuntu 26.04）
- Zig **0.16.0**
- wlroots **0.19** 開発ファイル
- Wayland、wayland-protocols、xkbcommon、pixman、libdrm、libinput、
  libseat、libudev、EGL/GLES
- Cairo、Pango、GLib/GIO（パネルと通知用）
- フォント: Inter、JetBrains Mono、Noto Sans CJK JP など
- ターミナル: 既定は `kitty`。`terminal = foot` などで変更可能

Ubuntu 26.04 の例:

```sh
sudo apt install build-essential pkg-config git \
  libwayland-dev wayland-protocols libwlroots-0.19-dev \
  libxkbcommon-dev libpixman-1-dev libdrm-dev libinput-dev \
  libseat-dev libudev-dev libegl-dev libgles2-mesa-dev \
  libcairo2-dev libpango1.0-dev libglib2.0-dev libfontconfig1-dev \
  fonts-inter fonts-jetbrains-mono fonts-noto-cjk \
  xwayland xauth xterm fcitx5 fcitx5-mozc
```

wlroots を `/usr/local` に自前ビルドした場合は、`.pc` と共有ライブラリが
見えることを確認してください。

```sh
pkg-config --modversion wlroots-0.19
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
- scenefx **0.4.1**: 角丸と背景ブラーを使う場合のみ

---

## 2. ビルド

リポジトリのルートで実行します。

```sh
chmod +x scripts/*.sh scripts/tessa-session
./scripts/build.sh
```

リリースビルド:

```sh
./scripts/build.sh -Doptimize=ReleaseSafe
```

生成物:

- `zig-out/bin/tessa`
- `zig-out/bin/tessa-panel`
- `zig-out/bin/tessa-ctl`

テストを実行する場合:

```sh
sh tests/smoke.sh
sh tests/animations.sh
sh tests/output-rules.sh
```

全テストは `sh tests/*.sh` で実行できます。テストは不足している任意依存
（`foot`、`grim`、`wlr-randr`、PipeWire、D-Bus など）に応じてスキップ
します。`tests/effects.sh` は scenefx ビルドでのみ実行されます。

### scenefx ビルド（角丸・背景ブラー）

既定ビルドは upstream wlroots の scene を使い、pixman と GL の両方で動作
します。角丸と背景ブラーを使う場合は scenefx 0.4.1 を導入し、次のように
ビルドします。

```sh
./scripts/build.sh -Doptimize=ReleaseSafe -Dscenefx=true
```

このバイナリは scenefx の GLES2 レンダラーを使うため、
`WLR_RENDERER=pixman` は使えません。scenefx を `/usr/local` 以外へ入れた
場合は、ビルド時と実行時に pkg-config／ライブラリパスを設定してください。

```sh
export PKG_CONFIG_PATH=$HOME/.local/lib/x86_64-linux-gnu/pkgconfig:$PKG_CONFIG_PATH
export LD_LIBRARY_PATH=$HOME/.local/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH
./scripts/build.sh -Dscenefx=true
```

`corner_radius`、`blur` などは既定ビルドでも読み込まれますが、視覚効果は
ありません。

---

## 3. 起動とインストール

### 3.1 TTY から直接起動

物理コンソール（SSH ではなく、ログイン中の TTY）で実行します。

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

```sh
# ~/.local 以下へ
./scripts/install-session.sh

# システム全体へ（sudo）
sudo PREFIX=/usr/local ./scripts/install-session.sh
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
[`packaging/README.md`](../packaging/README.md) を参照してください。

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
- 値に空白を含める場合は引用符で囲める
- フラット形式のため、値の中に `;` は書けない

再読み込みと診断:

```sh
tessa-ctl config                 # 実効設定と解析済みルール
tessa-ctl config --json          # schema 1 の JSON
tessa-ctl config-check           # エラー時は非ゼロ終了
tessa-ctl dispatch reload        # Super+R と同じ
```

エラーのあるリロードは拒否され、以前の設定が維持されます。診断には
ファイル名と行番号が付きます。

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
| `layout` | `master` | 既定レイアウト。`master`、`mosaic`、`grid`、`columns`、`custom` |
| `layout_1` … `layout_9` | 継承 | 保存済み・実行中の上書きがないワークスペースの初期レイアウト |
| `layout_helper` | 空 | `custom` 用の常駐ヘルパーコマンド |
| `layout_helper_timeout` | `100` | ヘルパー応答タイムアウト（10〜1000 ms） |
| `output_config` | `~/.config/tessa/outputs.conf` | 出力設定とレイアウト上書きの保存先 |
| `workspace_pin` | — | `OUTPUT WORKSPACE` でワークスペースを出力に固定。複数行可 |
| `workspace-rule` | — | ワークスペース別のレイアウト／間隔ルール |
| `output-rule` | — | 出力別（任意でワークスペース別）のレイアウト／間隔／テーマルール |
| `profile` | — | 出力／ワークスペースルールから参照する名前付きプロファイル |
| `window-rule` | — | ウィンドウのマッチルール |
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
| `shadows` | `true` | ウィンドウの多層シャドウ |
| `corner_radius` | `10` | 角丸半径（0〜64。scenefx ビルドのみ有効） |
| `blur` | `true` | 半透明サーフェスの背景ブラー（scenefx ビルドのみ） |
| `blur_radius` | `6` | ブラー半径（1〜32） |
| `blur_passes` | `3` | ブラーのパス数（1〜5） |

`animations = false`、`reduce_motion = true`、`animation_ms = 0` のいずれかで
動きを無効化できます。

### 6.3 パネル・シェル

| キー | 既定値 | 内容 |
| --- | --- | --- |
| `panel` / `autostart_panel` | `true` | `tessa-panel` を出力ごとに自動起動 |
| `bar_height` | `44` | バーの高さ（32〜96） |
| `bar_top_margin` | `12` | 上端からの距離（0〜64） |
| `bar_side_margin` | `16` | 左右マージン（0〜128） |
| `panel_bg` | `#0e1320` | バー背景色 |
| `panel_fg` | `#eef2f8` | バー主要テキスト色 |
| `launcher_entry` | — | ランチャー項目 `名前 \| コマンド`。複数行可 |
| `power_lock` | `loginctl lock-session` | 電源メニューの Lock |
| `power_suspend` | `systemctl suspend` | Suspend |
| `power_reboot` | `systemctl reboot` | Reboot |
| `power_off` | `systemctl poweroff` | Power Off |
| `screenshot_dir` | `~/Pictures/Screenshots` | PNG 保存先 |
| `volume_status` | 空 | 音量表示コマンド。空なら `wpctl`/`pactl`/`amixer` を自動検出 |
| `volume_up` | 空 | 音量上げコマンド |
| `volume_down` | 空 | 音量下げコマンド |
| `volume_mute` | 空 | ミュート切り替えコマンド |

`bar_height` などを変更すると、設定リロード時にバーの layer surface が
作り直され、予約領域も更新されます。

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

`Super+R` でキーマップも再構築されます。

### 6.5 X11・IME

| キー | 既定値 | 内容 |
| --- | --- | --- |
| `xwayland` | `true` | `xwayland-satellite` を起動し `DISPLAY` を設定 |
| `xwayland_display` | `auto` | `auto` または `:0` など |
| `xim` | `true` | `XMODIFIERS` を X11 クライアントへ設定 |
| `xim_server` | `fcitx` | XIM サーバ名 |
| `xim_start` | 空 | X ディスプレイ出現後に起動するコマンド |

### 6.6 イベント・自動化

| キー | 内容 |
| --- | --- |
| `startup` | 起動時に 1 回実行するコマンド |
| `hook` | `<event> <command>` 形式のイベントフック。複数可 |
| `event-rule` | 条件付きイベント→コマンドルール。8.7 節参照 |
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
| `Super+T` | master → mosaic → grid → columns を巡回 |
| `Super+Q` | フォーカス中のウィンドウを閉じる |
| `Super+Shift+E` | Tessa を終了 |
| `Super+R` | 設定再読み込み |
| `Super+1` … `Super+9` | ワークスペース切り替え |
| `Super+Shift+1` … `9` | ウィンドウをワークスペースへ移動 |
| `Super+H/J/K/L` | 左/下/上/右へフォーカス |
| `Super+Shift+H/J/K/L` | その方向と入れ替え。なければ隣接出力へ移動 |
| `Super+Space` | フローティング切り替え |
| `Super+F` | フルスクリーン切り替え |
| `Super+Escape` | `spawn swaylock` |
| `Super+Tab` / `Super+Shift+Tab` | ウィンドウ巡回 |
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
`focus`、`move`、`toggle-float`、`toggle-fullscreen`、`focus-next`、
`focus-prev`、`launcher`、`clipboard`、`screenshot`、`media`、`tray`、
`audio`、`reload`、`ratio`、`toggle-layout`、`set-layout`、
`resize-width`、`resize-height`、`enter-mode`。

### マウス

- ウィンドウをクリックでフォーカス
- バーのウィンドウチップをクリックでフォーカス、右クリックで閉じる
- バー上でスクロールしてワークスペースを巡回
- `Super+左ドラッグ` でフローティング移動
- `Super+右ドラッグ` でフローティングリサイズ
- クライアント側タイトルバーのドラッグもフローティングで利用可能
- `TESSA` マークのクリックでランチャー、右クリックで電源メニュー
- 時計のクリックでカレンダー

---

## 8. レイアウトとルール

### 8.1 組み込みレイアウト

- **master**: master 領域 + 縦スタック。`master_ratio`、`master_count`
- **mosaic**: 再帰スパイラル。最大 8 ウィンドウ。最小サイズを割ると
  **grid** にフォールバック
- **grid**: `ceil(sqrt(n))` 列。最終行は中央寄せ。`grid_columns` で固定可
- **columns**: 等幅全高カラム
- **custom**: 外部レイアウトヘルパー

`Super+T` は 4 つの組み込みレイアウトを巡回します。`custom` は巡回に
含まれないため、`set-layout custom` などで明示的に選びます。`layout_N` は
保存済み・実行中の上書きがないワークスペースの初期値です。実行中に選んだ
レイアウトは `outputs.conf` に保存されます。

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
- `profile=NAME`: 名前付きプロファイルを適用

### 8.3 `output-rule`

```ini
output-rule = output=HDMI-A-1; layout=grid; gaps=8; outer-gaps=12
output-rule = output=HDMI-A-1; ws=2; layout=master; master-ratio=0.62
output-rule = output=HDMI-A-1; profile=compact; gaps=4
output-rule = output=HEADLESS-*; accent=#8fd3ff; bg=#0c1118
output-rule = output=HEADLESS-*; border-active=#8fd3ff; border-inactive=#243040
output-rule = output=HEADLESS-*; panel-bg=#111827; panel-fg=#eef2f8
output-rule = output=HEADLESS-*; wallpaper-top=#162038; wallpaper-bottom=#070a12
output-rule = output=HEADLESS-*; bar-height=52; bar-top-margin=8; bar-side-margin=20
```

レイアウト／チューニング:

- `output=` / `monitor=`: 必須。`*` と `?` が使える
- `ws=1..9`: 省略時は全ワークスペース
- `layout=...`
- `gaps=N`、`outer-gaps=N`
- `master-ratio=0.15..0.9`、`master-count=1..8`
- `mosaic-ratio=0.25..0.85`、`mosaic-min-size=80..600`
- `grid-columns=0..8`
- `profile=NAME`: 明示キーの前に名前付きプロファイルを適用

テーマ（全ワークスペースのみ）:

- `accent=#RRGGBB`、`bg=#RRGGBB`
- `border-active=#RRGGBB`、`border-inactive=#RRGGBB`
- `panel-bg=#RRGGBB`、`panel-fg=#RRGGBB`
- `bg-top=#RRGGBB`、`bg-bottom=#RRGGBB`
- `bar-height=32..96`、`bar-top-margin=0..64`、`bar-side-margin=0..128`

コンポジタが出力の背景とボーダー色を適用し、パネルも同じ出力向けルールを
読み直すため、バーの高さ、マージン、壁紙、パネル色が一致します。`ws=` を
指定したルールではテーマ項目を無視します。

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
| `workspace=1..9` | ワークスペース指定 |
| `size=WxH` | フローティングサイズ |
| `width=N`、`height=N` | 片軸のみ |
| `position=X,Y` | フローティング位置 |
| `border-active=#RRGGBB` | ウィンドウ別フォーカスボーダー |
| `border-inactive=#RRGGBB` | ウィンドウ別非フォーカスボーダー |

パターンは `*`／`?`、大文字小文字は区別されます。単純キーと `match` は
AND で結合されます。ルールはファイル順で、後のルールが優先され、ボーダー
色も同じ規則です。不正な式や正規表現はファイル名／行番号付きで報告され、
リロードは拒否されます。マップ時と設定リロード時に評価されますが、マップ
後のタイトル変更だけでは再評価されません。ボーダー色は閉じるスナップ
ショットにも使われます。

### 8.5 外部レイアウトヘルパー

```ini
layout = custom
layout_helper = python3 ~/.config/tessa/layout.py
layout_helper_timeout = 100
bind = SUPER+SHIFT+T set-layout custom
```

ヘルパーは常駐プロセスです。タブ区切りで `LAYOUT`、`OUTPUT`、`AREA`、
`OUTER_GAP`、`GAP`、`BORDER`、`SCALE`、`TRANSFORM`、`COUNT`、`WINDOW`、
`END` を送り、各ウィンドウについて `RECT id x y w h` と `END` を受け取り
ます。座標は絶対論理座標、幅と高さはボーダーを含むフレームサイズです。

応答のタイムアウト、クラッシュ、不正応答、ID 不一致、矩形不足時は、その
配置だけ master へフォールバックします。1 秒後に同じヘルパーを再試行します。
`stdout` はプロトコル専用なので、診断は `stderr` へ書きます。

完全な例は `examples/layout-cascade.py` と
[CUSTOMIZATION.ja.md](CUSTOMIZATION.ja.md#外部レイアウトヘルパー) を参照して
ください。

### 8.6 ワークスペース固定

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

### 8.7 イベントルール

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

### 9.4 出力故障時

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

### 10.2 バーとフォント

```ini
bar_height = 44
bar_top_margin = 12
bar_side_margin = 16
panel_bg = #0e1320
panel_fg = #eef2f8
font = Inter
```

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
`wallpaper.top`、`wallpaper.bottom` です。ロールは直接キーの後に適用される
ため、`accent`、`border_active`、`border_inactive`、`bg` と対応するパネル
キーより優先されます。一致する `output-rule` のテーマは、その出力に限り
グローバルロールも上書きします。

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
reduce_motion = false
reduce_motion_animations = fade
reduce_motion_fade_ms = 120
```

- 開く: 縦 18 px から cubic ease-out
- ワークスペース: 方向に応じて横 ±54 px から cubic ease-out
- 閉じる: コンポジタ起点の close ではウィンドウバッファを保持し、
  移動が有効なら 92% まで縮小しながらフェード
- 種類別の時間が `animation_ms` を上書きします。`-1` で継承
- クライアント自身が閉じた場合は unmap 時点でバッファがなくなるため即時
- `reduce_motion = true` は開く／ワークスペースの移動を無効化
- `reduce_motion_animations = fade` は縮小や移動をせず、閉じるフェードだけを
  `reduce_motion_fade_ms` の間実行
- `reduce_motion_animations = none`（既定）は close エフェクトも無効
- 時間は 0〜1000 ms で、`0` はそのアニメーションを無効化

アニメーションの開始／完了は `animation-start`、`animation-done`、
`close-animation-start`、`close-animation-done` イベントで取得できます。

### 10.5 scenefx 角丸・ブラー

`-Dscenefx=true` ビルドのみ:

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
- 既定ビルドではキーは受理されるが見た目は変わらない

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

### 11.2 入力モード

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

### 11.3 ジェスチャ

```ini
gestures = true
gesture_fingers = 3
gesture_workspace_threshold = 400
gesture_launcher_threshold = 300
```

既定では 3 本指の横スワイプでワークスペース、上スワイプでランチャーです。
それ以外の指の本数や pinch/hold はフォーカス中のクライアントへ転送されます。

### 11.4 タッチ・タブレット

```ini
touch = true
tablet = true
pointer_constraints = true
```

タッチはパネル UI も含めて処理されます。tablet-v2 は圧力、tilt、rotation、
ツールボタン、リング、ストリップに対応します。pointer-constraints-v1 は
フォーカスに応じて locked/confined を有効化します。

### 11.5 IME / XIM

Wayland IME は `text-input-v3` と `input-method-v2` で中継されます。
Fcitx5 + Mozc でのランチャー入力が検証済みです。

X11 は `XMODIFIERS` を設定し、必要なら `xim_start` で XIM サーバを起動します。

```ini
xim = true
xim_server = fcitx
xim_start = fcitx5 -d
```

`xim_start` は X ディスプレイのソケットが現れてから実行されます。

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

### 12.7 音量

```ini
volume_status = wpctl get-volume @DEFAULT_AUDIO_SINK@
volume_up = wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+
volume_down = wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
volume_mute = wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
```

空欄なら `wpctl`、`pactl`、`amixer` を順に自動検出します。

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
tessa-ctl config
tessa-ctl events [topic]
tessa-ctl workspace 3 [output]
tessa-ctl spawn foot -T notes
tessa-ctl launcher fire
tessa-ctl panel calendar
tessa-ctl layout grid
tessa-ctl mode resize
tessa-ctl resize 40 30
tessa-ctl dispatch reload
tessa-ctl quit
```

生の IPC コマンド:

```text
CMD subscribe state|events|all
CMD state
CMD state-json
CMD config
CMD config-json
CMD workspace <1..9> [output]
CMD move-workspace <1..9>
CMD focus <id>
CMD close <id>
CMD spawn <shell command>
CMD launcher [query]
CMD panel <calendar|power|clipboard|screenshot|media|tray|audio> [output]
CMD layout [name] [output]
CMD resize <dx> <dy>
CMD float <id>
CMD status <id> <text> [--exec command]
CMD reload
CMD notification-action <id> <key>
CMD quit
```

接続直後は何も届きません。`CMD subscribe ...` が必要です。`STATE` は
`END` までで 1 スナップショットです。

`OUT` は `name workspace focused layout`、`WIN` はタブ区切りで
`id, workspace, focused, floating, fullscreen, app_id, title, output, x, y, w, h`
です。

### 13.2 JSON と JSON-RPC

- `state --json`: `schema: 1`、出力、占有、フォーカス、ステータス、ウィンドウ
- `config --json`: 実効設定、`layouts`、`workspace_tuning`、`rules`、
  `output_rules`、`hooks`、`event_rules`、`profiles`、`theme_roles`、
  `diagnostics`
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
`protocol: "tessa-jsonrpc"`、`version: 1`、`line_protocol: 1` と、
`state`、`config`、`events`、`subscriptions`、`request-ids` の
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
| `window-moved` | WS 移動 | id, ws, previous-ws, app, title, output |
| `layout-change` | レイアウト変更 | ws, output, arg |
| `mode-change` | 入力モード変更 | arg |
| `config-reload` | 設定再読み込み成功 | — |
| `launcher` | ランチャー要求 | arg, output |
| `panel` | パネル要求 | arg, output |
| `notification-action` | 通知アクション | id, arg |
| `output-added` | 出力追加 | output, arg |
| `output-removed` | 出力削除 | output, arg |
| `animation-start` | 開く/WS スライド開始 | id, ws, output, arg (`open`/`workspace`) |
| `animation-done` | 開く/WS スライド完了 | id, ws, output, arg |
| `close-animation-start` | 閉じるスナップショット開始 | id, ws, output, arg (`close`) |
| `close-animation-done` | 閉じるスナップショット完了 | id, ws, output, arg |

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

### 13.6 ランチャー項目

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

### X11 アプリが起動しない

- `xwayland-satellite` が `PATH` にあるか
- `TESSA_XWAYLAND_BIN` のパス
- `xwayland = true`
- `DISPLAY` が Tessa の子プロセスへ渡っているか
- `TESSA_NO_XWAYLAND` が設定されていないか

`xwayland-satellite` が見つからない場合でも Wayland クライアントと
パネルは動作します。

### IME が効かない

- `zwp_input_method_v2` 対応の IME（Fcitx5 など）が起動しているか
- `XMODIFIERS=@im=fcitx` が X11 クライアントへ渡っているか
- `xim_start` を使う場合、X ディスプレイの出現後に起動しているか
- Fcitx5 を二重起動していないか

### 画面共有できない

- `xdg-desktop-portal`、`xdg-desktop-portal-wlr`、PipeWire
- `tessa.portal` の配置
- xdpw の `chooser_type` と `output_name`
- `XDG_CURRENT_DESKTOP=Tessa`

### 角丸・ブラーが出ない

- `-Dscenefx=true` でビルドしたか
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

- **物理 DRM / libinput は実機検証が未完了**。開発は headless pixman、
  `wtype`、Fcitx5、`xwayland-satellite` が中心です。実際の DRM モード設定、
  物理キーボード／マウス／タッチパッドの最終確認が必要です。
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
- **角丸・ブラーはオプトイン**。scenefx 0.4.1 と GLES2 が必要で、pixman
  レンダラーは使えません。
- **ウィンドウ効果はシンプル**。角丸・ブラーは scenefx ビルドのみ。閉じる
  アニメーションはコンポジタ起点の close のみで、クライアント自身の close は
  即時です。
- **プロファイルはレイアウト／チューニングのみ**。出力別の色やパネル寸法は
  `output-rule` のテーマキーを直接使います。
- **ウィンドウルールはタイトル変更で再評価されません**。次回の設定リロード
  まで反映されません。
- **レイアウトヘルパーは同期実行で全出力共有のまま**。出力別インスタンス、
  非同期/差分更新、ヘルパー v2 メタデータは未実装です。
- **JSON-RPC は読み取りとイベント購読のみ**。変更操作は行コマンドを使います。
- **差分プレビュー付きの設定エディタは未実装**です。
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
