[English](DEVELOPMENT.md) | **日本語**

# 開発

Tessa は SSH 越しの headless Linux マシンだけで開発できます。コンポジタも
パネルも普通の Wayland プログラムなので、`grim` で headless 出力を撮影して
見た目をすぐ確認できます。仮想キーボード（`wtype`）と Fcitx5 を使えば、
物理ディスプレイなしでキーボードや IME の経路もテストできます。

## ビルド

```sh
chmod +x scripts/*.sh scripts/tessa-session
./scripts/build.sh -Doptimize=ReleaseSafe
```

デバッグビルド:

```sh
./scripts/build.sh
```

必要なものはメイン README にまとめています。要点は Zig 0.16、wlroots 0.19、
Wayland、xkbcommon、pixman、DRM/input/seat の開発ヘッダー、Cairo、Pango、
フォントです。X11 をテストする場合は `xwayland-satellite` も `PATH` に
入れてください。

ライブラリの確認:

```sh
pkg-config --modversion wlroots-0.19
ldconfig -p | grep wlroots
fc-list | grep -i -E 'Inter|JetBrains|Noto Sans CJK'
```

## headless セッション

ターミナル 1:

```sh
./scripts/run-headless.sh
```

`/tmp/tessa-headless` を作成し、pixman レンダラーを強制して
`zig-out/bin` からパネルを起動します。出力は 1920×1080 の headless
ディスプレイ `HEADLESS-1` です。

ターミナル 2:

```sh
# 画面を撮影
./scripts/screenshot.sh /tmp/tessa.png

# セッション内でターミナルを起動
printf 'CMD spawn foot -T notes\n' \
  | socat - UNIX-CONNECT:/tmp/tessa-headless/tessa.sock

# master <-> mosaic
printf 'CMD layout\n' \
  | socat - UNIX-CONNECT:/tmp/tessa-headless/tessa.sock

# ランチャー（クエリ付きでもよい）
printf 'CMD launcher\n' \
  | socat - UNIX-CONNECT:/tmp/tessa-headless/tessa.sock
printf 'CMD launcher ter\n' \
  | socat - UNIX-CONNECT:/tmp/tessa-headless/tessa.sock

# ワークスペース切り替え / ウィンドウへフォーカス
printf 'CMD workspace 2\n' \
  | socat - UNIX-CONNECT:/tmp/tessa-headless/tessa.sock
```

headless バックエンドには物理入力デバイスがないため、Tessa は標準 XKB
キーマップを持つフォールバックキーボードを作成します。これによりパネル、
IME、XWayland が正しく起動できます。キーボード入力は virtual-keyboard
プロトコル経由で注入します:

```sh
export XDG_RUNTIME_DIR=/tmp/tessa-headless
export WAYLAND_DISPLAY=wayland-0

printf 'CMD launcher\n' | socat - UNIX-CONNECT:/tmp/tessa-headless/tessa.sock
wtype "foot"
wtype -k Return
```

`wtype` は現在キーボードフォーカスを持つサーフェスへ入力します。

`tessa-ctl` でセッションを操作できます。ビルド出力を `PATH` に入れ、
`XDG_RUNTIME_DIR` を揃えてください。

```sh
export PATH="$PWD/zig-out/bin:$PATH"
export XDG_RUNTIME_DIR=/tmp/tessa-headless

tessa-ctl state
tessa-ctl spawn foot -T notes
tessa-ctl dispatch layout
tessa-ctl launcher ter
tessa-ctl status demo "hello from an extension"
tessa-ctl events window-focus
```

`tessa-ctl status --clear` でエントリを削除できます。`tessa-ctl events` は
購読後にだけイベントを受け取るので、常駐スクリプトとして安全に使えます。

### IME テスト

セッション内で Fcitx5 を起動し、Mozc を選択してランチャーに入力します:

```sh
printf 'CMD spawn fcitx5\n' \
  | socat - UNIX-CONNECT:/tmp/tessa-headless/tessa.sock
printf 'CMD launcher\n' \
  | socat - UNIX-CONNECT:/tmp/tessa-headless/tessa.sock

wtype "nihongo"      # プリエディット
wtype -k space       # 変換
wtype -k Return      # 確定
grim -o HEADLESS-1 /tmp/ime.png
```

実際の Fcitx 設定に触れたくない場合は、`mozc` を選択した
`fcitx5/profile` を含む一時ディレクトリを `XDG_CONFIG_HOME` に指定して
ください。候補ポップアップは入力メソッドのポップアップサーフェスとして
検索欄の下に描画されます。

### XWayland テスト

`xwayland-satellite` が `PATH` にある（または `TESSA_XWAYLAND_BIN` を設定
した）状態で、Tessa は空いているディスプレイを自動選択し `DISPLAY` を
エクスポートします。きれいなマシンでは通常 `:0` です。

```sh
printf 'CMD spawn xeyes\n' \
  | socat - UNIX-CONNECT:/tmp/tessa-headless/tessa.sock
printf 'CMD spawn xclock\n' \
  | socat - UNIX-CONNECT:/tmp/tessa-headless/tessa.sock
sleep 2
DISPLAY=:0 xdpyinfo | head
grim -o HEADLESS-1 /tmp/xwayland.png
printf 'STATE\n' \
  | socat - UNIX-CONNECT:/tmp/tessa-headless/tessa.sock
```

`STATE` の出力に `XEyes` と `XClock` が通常のウィンドウとして並べば成功です。
`xev` と `wtype` で X11 クライアントへのキーイベント到達も確認できますが、
wtype は独自の小さなキーマップをインストールするため、実際の文字入力の
テストには物理キーボードの方が適しています。

### ロックと idle のテスト

コンポジタは `ext-session-lock-v1`、`ext-idle-notify-v1`、
`idle-inhibit-v1`、出力電源管理を公開します。テスト用クライアントを
インストールします:

```sh
sudo apt install swaylock swayidle wlopm
```

セッション内で `swaylock -f` を実行するか、`Super+Escape` を押します。
デスクトップ全体がロックサーフェスに置き換わり、ロック後に作成した仮想
キーボードからは入力できないことを確認してください。ロック中にロック
クライアントを kill した場合、Tessa はデスクトップを露出せず終了する
必要があります。idle は `swayidle -w timeout 5 'swaylock -f'` で確認でき、
操作でロックが延期されること、`idle-inhibit-v1` を持つクライアントが
ある間はロックされないことを確認します。

## 拡張と統合テスト

headless スモークテストは、設定 include、フック、一時ランタイムを使って
コンポジタを起動し、ワークスペース変更、ステータス設定/削除、設定
再読み込み、イベント購読、IPC の半クローズ処理、`foot` があればウィンドウの
生成/フォーカス/終了イベントを確認します。

```sh
./scripts/build.sh
sh tests/smoke.sh
```

`TESSA_CTL_DEBUG=1 tessa-ctl events` は受信したイベント行を stderr に表示
します。API とフック環境は [EXTENDING.ja.md](EXTENDING.ja.md) を参照して
ください。

## デバッグログ

```sh
# wlroots のデバッグログ、Tessa のログ、IME/ポップアップの診断
TESSA_DEBUG=1 ./scripts/run-headless.sh

# パネル状態のスナップショット（アクティブワークスペース、ウィンドウ数）
TESSA_PANEL_DEBUG=1 ./scripts/run-headless.sh

# テストクライアントの完全な Wayland プロトコルログ
WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR=/tmp/tessa-headless \
  WAYLAND_DEBUG=1 foot -T debug
```

環境変数による上書き:

- `TESSA_IPC=/path/to/socket`
- `TESSA_CONFIG=/path/to/config`
- `TESSA_NO_PANEL=1`
- `TESSA_PANEL_BIN=/path/to/tessa-panel`
- `TESSA_NO_XWAYLAND=1`
- `TESSA_XWAYLAND_BIN=/path/to/xwayland-satellite`
- `TESSA_DEBUG=1`
- `TESSA_PANEL_DEBUG=1`

## 実機 TTY

DRM と libinput を使う場合は、マシンの**アクティブな仮想ターミナル**で
Tessa を実行してください。コンポジタは DRM master と seat へのアクセスが
必要です。無関係な SSH セッションから起動しても、使えるハードウェア
セッションにはなりません。

```sh
cd /path/to/Tessa
PATH="$PWD/zig-out/bin:$PATH" ./zig-out/bin/tessa
```

パネルは `PATH` から自動起動されます。`scripts/install-session.sh` で
インストールした場合、セッションのエントリーポイントが自分自身の
ディレクトリを `PATH` の先頭に追加するので、両方のバイナリが見つかります。

## 反復作業のヒント

- パネルは起動時に色/フォント/ターミナル設定を読み込みます。`Super+R` は
  コンポジタの設定とキーバインドを再読み込みします。シェルのパレット変更は
  パネルを再起動して反映してください。
- SSH 越しでは `pkill -x tessa` と `pkill -x tessa-panel` を使う方が安全です。
  `pkill -f tessa` は SSH のリモートコマンドライン自体にマッチして、
  セッションを殺してしまうことがあります。
- headless 出力名は安定しています: `grim -o HEADLESS-1`。
- Zig の translate-c は Pango/GLib のヘッダーを処理できません。テキスト
  描画は `panel/text.c` にあり、Pango を `@cImport` に入れないでください。
- layer-shell の `EXCLUSIVE` は enum 値の `1` です。`2` は `ON_DEMAND`。
- `ReleaseSafe` では C インポートに `_FORTIFY_SOURCE=0` が必要です。2 つの
  `c.zig` ですでに設定されています。
- Xwayland 24.x は起動時に親 seat のキーマップを必要とします。キーボードが
  ないと `XKB: Failed to compile keymap` で失敗します。`input.zig` の
  フォールバックキーボードはこのためにあります。
- 子プロセスを exec する前に `SIGCHLD` を `SIG_DFL` に戻してください。Tessa は
  自分の子プロセスのために `SIGCHLD` を無視しているので、そのまま継承すると
  ヘルパーの起動と待機が壊れます（Xwayland の xkbcomp もこれに該当します）。
- `wlr_xdg_toplevel_decoration_v1_set_mode()` は xdg サーフェスの初回 commit
  前に configure をスケジュールしてはいけません。未初期化なら
  `scheduled_mode` を設定し、初期化後にモードを適用してください。
