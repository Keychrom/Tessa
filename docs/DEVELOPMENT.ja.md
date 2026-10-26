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

### HiDPI と出力設定の永続化テスト

2 倍スケールを設定してパネルを撮影します。1920x1080 モードではバーが物理
88 px になり、文字が鮮明なままであることを確認できます。

```sh
wlr-randr --output HEADLESS-1 --scale 2
grim -o HEADLESS-1 /tmp/hidpi.png
```

`wlr-randr` の apply は `~/.config/tessa/outputs.conf`（または
`$XDG_CONFIG_HOME/tessa/outputs.conf`）も更新します。保存先は
`TESSA_OUTPUT_CONFIG` または設定キー `output_config` で変更できます。
自己完結の headless テストもあります。

```sh
WLR_RANDR=/path/to/wlr-randr sh tests/output-persistence.sh
```

このテストは 1280x720 のカスタムモード、スケール 2、位置 40,30 を適用し、
設定ファイルを確認して実行中レイアウトを設定してから再起動し、
モード/スケール/位置とレイアウトの復元を検証します。2 倍時のランチャーは
同じ 760x620 デザインをフィットさせるため、ヒット矩形と IME カーソルも
見た目のスケーリングに追従します。

### レイアウトテスト

セッション内で複数のターミナルを起動し、`tessa-ctl`（または `Super+T`）で
レイアウトを巡回・設定します。

```sh
for n in one two three four; do tessa-ctl spawn foot -T "layout-$n"; done
tessa-ctl layout grid
./scripts/screenshot.sh /tmp/grid.png
tessa-ctl layout columns
./scripts/screenshot.sh /tmp/columns.png
tessa-ctl layout mosaic
```

`tests/layout-geometry.sh` は 8 ウィンドウを起動してモザイクを選び、
タイルが重ならないこと、すべて 160×160 以上であることを検証します。

`tessa-ctl state` の `OUT` 行の末尾に現在のレイアウト名が出ます。ワークスペース
ごとの初期レイアウトは `layout_1` … `layout_9` で設定します。実行中の変更は
出力・ワークスペースごとに保持され、`outputs.conf` の `layout` 行として保存
され、次回起動時に復元されます。設定の再読み込みは実行中の上書きがない
ワークスペースだけを更新します。`Super+Alt+H/J/K/L` または
`tessa-ctl resize <dx> <dy>` でフォーカス中のフローティングウィンドウを
最小 160×120 でリサイズできます。

### ルールとカスタマイズのテスト

`tests/customization.sh` は専用の headless セッションを起動し、`foot` の
ウィンドウにフローティング、ワークスペース、フルスクリーン、サイズ、位置の
ルールを適用します。`tessa-ctl config` を確認し、ルールファイルを書き換えて
再読み込みした後、既存ウィンドウが再評価されることも検証します。
`tests/layout-geometry.sh` は `master_count`、`grid_columns`、ワークスペース別の
隙間/マスター比率の調整値も確認します。

```sh
sh tests/customization.sh
sh tests/layout-geometry.sh
```

### レイアウトヘルパーのテスト

`tests/layout-helper.sh` は `layout = custom` でコンポジタを起動し、小さな
Python ヘルパーに既知の矩形を返させてジオメトリを検証します。壊れた
ヘルパーへ切り替えてマスターレイアウトへのフォールバックを確認し、元の
ヘルパーへ戻して再読み込み後の再起動も検証します。

```sh
sh tests/layout-helper.sh
```

### 設定検証と JSON のテスト

`tests/config-validation.sh` は未知キー、不正値、壊れたルール、存在しない
include を含む設定を書き、報告される行番号を確認します。さらに、リロードが
以前の設定を維持すること、ファイルを直すまで
`tessa-ctl config-check` が失敗することを検証します。

`tests/json-ipc.sh` は `state --json` と `config --json` を Python で解析し、
スキーマバージョン 1 とウィンドウジオメトリを確認します。拒否された
リロードの JSON 診断も検証します。

```sh
sh tests/config-validation.sh
sh tests/json-ipc.sh
```

### 入力モードのテスト

`tests/modes.sh` は `resize` モードを定義し、`tessa-ctl mode` で入ってから
修飾キーなしの `l`/`Escape` を `wtype` で送ります。モード固有バインドが
消費され、default モードへ戻った後は通常キーがクライアントへ渡ることを
確認します。

```sh
sh tests/modes.sh
```

### パネルテーマのテスト

`tests/panel-theme.sh` は実際のパネルをカスタムのバー高さ、マージン、配色で
起動し、起動ログを確認します。その後ジオメトリを変更してリロードし、
パネルを落とさずにバーの layer surface が新しいサイズで再作成されることを
検証します。

```sh
sh tests/panel-theme.sh
```

### パネルポップオーバーのテスト

`tests/panel-popovers.sh` はコンポジタとパネルを起動し、`panel` IPC
イベント経由でカレンダーを開き、`wtype` で月を移動して Escape で閉じる
ことを確認します。続いて電源メニューを開き、Suspend を選んで、設定した
`power_suspend` コマンドだけが実行され、再起動/電源オフは実行されないことを
検証します。

```sh
sh tests/panel-popovers.sh
```

### クリップボード履歴のテスト

`tests/clipboard.sh` は 2 つの文字列を `wl-copy` でコピーし、`wtype` で
`Super+V` を送って履歴を開きます。古い項目を選び、`wl-paste` でパネルが
新しいセレクションソースになったことを確認します。その後 3 つ目の文字列を
コピーし、IPC 経由で履歴を開き直して最新項目が復元されることも検証します。

```sh
sh tests/clipboard.sh
```

パネルは `wlr-data-control-v1` 経由でセレクションを監視します。通常の
`wl_data_device` のセレクションイベントはフォーカス中のクライアントにしか
届かないため、バー側の通常 data device では履歴を集められません。

### スクリーンショットのテスト

`tests/screenshot.sh` は一時的な `screenshot_dir` を設定し、IPC 経由で
スクリーンショット UI を開きます。`Enter` で全画面を保存し、生成された
ファイルが 1920×1080 の PNG であることを確認します。`Esc` でキャンセルした
場合にファイルが増えないこと、既定の `Super+Shift+S` で UI が開くことも
検証します。

```sh
sh tests/screenshot.sh
```

自動テストは全画面撮影を対象にしています。範囲ドラッグは通常のポインタ
経路を使うため、実機のポインタか virtual-pointer を使ったテストが別途
必要です。

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
コンポジタを起動し、ワークスペース変更、レイアウトの永続化、実行中の上書き
を保った設定再読み込みの反映、ステータス設定/削除、イベント購読、IPC の
半クローズ処理、フローティングのキーボードリサイズ、`foot` があれば
ウィンドウの生成/フォーカス/終了イベントを確認します。

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
- `TESSA_PANEL_OUTPUT=<出力名>`（出力ごとのパネルで自動設定）
- `TESSA_OUTPUT_CONFIG=/path/to/outputs.conf`
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

- パネル設定を変更したら `Super+R` を押してください。パネルは
  `config-reload` を受けて配色、バーのジオメトリ、フォント、ターミナル、
  ランチャー項目、電源コマンドを読み直します。ジオメトリ変更時はバーの
  layer surface を再作成します。
- クリップボード履歴はコンポジタの `wlr-data-control-v1` に依存します。
  `wl_data_device` のセレクションイベントはフォーカス中のクライアントに
  しか届かないため、パネルの data-control デバイスを通常インターフェースに
  置き換えないでください。
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
