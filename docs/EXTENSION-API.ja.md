[English](EXTENSION-API.md) | **日本語**

<!-- tessa-site-notice:start -->
> [!NOTE]
> このドキュメントは Web サイトに移植されました。最新版は <https://keychrom.github.io/ja/docs/extension-api/> を参照してください。
<!-- tessa-site-notice:end -->

# 拡張 API v1 安定性契約

この文書は Tessa の監視付き拡張 API の正規契約です。バージョン番号の
正は `src/api.zig` で、以下のプロトコル詳細は 0.2.x 系で凍結します。

## 対象範囲

v1 で安定とみなすもの:

- `$TESSA_IPC` 上の行プロトコル
- 監視付き拡張のマニフェスト、トークン、スコープ、ライフサイクル、監督
- テキスト `EXT` 状態行と実行時 `extensions` JSON 配列
- 拡張関連の設定キーと JSON フィールド
- ライフサイクルイベント名と `arg` ペイロード

対象外:

- `ext-workspace-v1` などの Wayland プロトコル（[ARCHITECTURE.ja.md](ARCHITECTURE.ja.md) を参照）
- パネル描画と内部モジュール interface
- `tessa-ctl` の表示形式（プロトコル本体ではなく参照クライアント）

## バージョン

| 値 | 現在 | 意味 |
| --- | --- | --- |
| `line_protocol` | 1 | 行フレーミング、`HELLO`、コマンド、`STATE`/`END` |
| `extension_api` | 1 | マニフェスト API と監視付き拡張の挙動 |
| `state_schema` | 1 | `state-json` ドキュメント |
| `config_schema` | 1 | `config-json` ドキュメント |

`HELLO` は行プロトコルを交渉し `VERSION` を返します。拡張 API は
マニフェストの `api=` で宣言します。新しい API を要求するマニフェストは
設定エラーです。`tessa_version` は情報用で、判定には個別の API バージョンを
使ってください。

`extension_api = 1` は 0.2.x で凍結します。JSON フィールド、コマンド、
権限名、イベントトピック、エラーコードの追加は可能です。フィールドの削除・
改名、`EXT` 行の並べ替え、既存エラーフレームの変更、トークン意味論の変更は
`extension_api = 2` が必要です。

## トランスポートとハンドシェイク

ソケットは `$TESSA_IPC` または `$XDG_RUNTIME_DIR/tessa.sock`、モード 0600
です。行は LF 区切りの UTF-8、フィールドはタブ区切りです。行バッファの
上限は 8192 バイトです。

```text
HELLO <version> [<token>]
VERSION	1
CAPABILITIES	state,config,events,subscriptions,config-compare,perf,rendering,special,groups,extensions,effects2,shell-modules,shell
EXTENSION	<id>	<permissions>
```

- `HELLO` はスペース区切りでもタブ区切りでも構いません。
- バージョン省略は 1 です。`0` と数値でない値は
  `ERR invalid-version` を返します。
- トークン付き `HELLO` は fail-closed です。認証に失敗した場合、バージョン
  自体が不正でも権限なしの scoped 接続になり、従来の全権限へは戻りません。
- `EXTENSION` はそのハンドシェイクで認証に成功した場合だけ返します。
- トークンなし `HELLO` は従来互換で全権限のままです。これは `tessa-ctl`、
  パネル、既存ツール向けです。監視付き拡張は必ずトークンを使ってください。
- トークン付き `HELLO` は認証前に作られた購読を解除します。認証後に
  改めて購読してください。
- 1 接続が認証できる identity は 1 つです。後から失敗したトークンは
  identity と権限を消します。

## エラー

エラーは `ERR\t<code>[\t<detail>]` です。v1 のコード:

| コード | 意味 | エラー後の接続 |
| --- | --- | --- |
| `invalid-version` | `HELLO` のバージョンが 0 または非数値 | トークン付きなら権限なし |
| `unauthorized` | トークンが不明、または拡張が running/ready でない | 権限なし |
| `forbidden` | コマンドに必要なスコープがない | 変更なし |
| `busy` | IPC 接続上限 | 接続を閉じる |
| `unknown-command` | scoped クライアントが未知コマンドを送った | 変更なし |
| `bad-argument` | 既知コマンドの引数が不正 | 変更なし |
| `unknown-extension` | `extension-enable` の ID が存在しない | 変更なし |

`forbidden` は `ERR\tforbidden\t<command>` です。未知コマンドのエラーは
scoped クライアントにだけ返し、コマンド探索をする従来ツールを乱しません。

JSON-RPC はスコープ拒否に `-32001 forbidden`、パースエラーに `-32700`、
不正リクエストに `-32600`、未知メソッドに `-32601` を使います。JSON-RPC で
拡張 identity が必要な場合は、先に同じ接続で行 `HELLO` を送ってください。
v1 に JSON 用のトークンパラメータはありません。

## トークン

- 監視付き拡張には `TESSA_EXTENSION_ID`、`TESSA_EXTENSION_TOKEN`、
  `TESSA_EXTENSION_API`、`TESSA_EXTENSION_PERMISSIONS` が渡されます。
- トークンは 32 文字の小文字 hex で、監視付きの起動ごと（クラッシュ再起動、
  disable/enable を含む）に再生成されます。設定や JSON API には出ません。
- 停止、無効化、クラッシュ、reload のとき、その拡張の認証済み接続は
  失効します。スコープを消し、購読を解除します。停止中の旧トークンと、
  新しいプロセス起動後の旧トークンは拒否されます。
- 同じ有効トークンで複数接続を認証できます。失効はそのすべてに適用されます。
- スコープは協調的なガードレールで、サンドボックスではありません。拡張は
  コンポジタと同じユーザーで動き、トークンやソケットを直接読めます。
  トークン回転と失効は、監督が停止した後に古い接続が操作を続けるのを防ぎ
  ますが、悪意ある同一ユーザープロセスは防げません。

## ライフサイクルと監督

| 状態 | 意味 |
| --- | --- |
| `disabled` | `enabled=false` |
| `blocked` | `requires` 依存が `ready` でない |
| `stopped` | `extension-enable off` で明示停止 |
| `starting` | 予約済み。現在は出力されない |
| `running` | プロセス起動済み、トークン未認証 |
| `ready` | トークン認証済み（`EXTENSION` 送信済み） |
| `failed` | 終了、起動失敗、ready timeout |

`running` は健全ではありません。健全性は `ready=1` で判定してください。

`extension_ready_timeout`（ミリ秒、既定 `10000`、`0` で無効）は各起動に
適用されます。時間内に認証しないプロセスは kill され、`failed`、
`last_error = "ready timeout"` となり、通常のバックオフで再起動します。
有効時の範囲は `1000..60000` にクランプされます。

失敗後の再起動バックオフは 1 秒、2 秒、4 秒、8 秒です。10 秒以上動作した
プロセスは終了時に失敗回数をリセットします。一時的な失敗は JSON の
`failures` と `next_restart_ms` で確認できます。

## 依存関係

- `requires=a,b` は各依存が `ready` になるまで起動を止めます。
- `after=a,b` は起動順だけを制御します。
- 同じ依存リスト内の重複、`requires` と `after` の両方への指定、自己依存、
  未知 ID、循環は設定エラーです。
- 監督はトポロジカル順に起動します。依存が後から失敗しても、起動済みの
  依存元は停止しません。次回の起動試行時に再度 `requires` を確認します。
- 上限は拡張 16 個、マニフェストあたり依存 8 個、ID 32 バイト、トークン
  32 バイトです。

## 権限とコマンド

既定は `read,status` です。

| スコープ | コマンド / 配信 |
| --- | --- |
| `read` | `state`、`state-json`、`config`、`config-json`、`config-compare`、`perf`、`perf-json`、`rendering`、`rendering-json`、`subscribe state` |
| `events` | `subscribe events`、イベント配信 |
| `status` | `status`、タブ区切り `CMD<TAB>status` |
| `window` | `focus`、`close`、`urgent`、`float`、`swap`、`reorder`、`resize`、グループ系 |
| `workspace` | `workspace`、`move-workspace`、special/scratchpad 系 |
| `layout` | `layout`、カラム系、`window-move` |
| `spawn` | `spawn` |
| `panel` | `launcher`、`panel`、`notification-action` |
| `control` | `reload`、`quit`、`mode`、`perf-reset` |
| `extensions` | `extensions`、`extensions-json`、`extension-enable` |

`subscribe all` は `read` と `events` の両方が必要です。必要なスコープがない
scoped クライアントは `ERR forbidden subscribe` を受け取り、購読状態は
変わりません。

## テキストと JSON スキーマ

テキスト `EXT` 行はスペース区切りの 8 フィールドで凍結します:

```text
EXT <id> <state> <api> <pid> <ready> <restarts> <enabled> <permissions>
```

`pid` は未起動時 `-1` です。`permissions` はカンマ区切りのスコープ一覧です。
診断フィールドをこの行へ追加せず、JSON を使ってください。

`state --json`、`extensions-json`、`tessa-ctl extensions --json` の
`extensions` 配列は次のキーを持ちます:

| キー | 型 | 内容 |
| --- | --- | --- |
| `id` | string | マニフェスト ID |
| `state` | string | 上記の状態 |
| `api` | number | マニフェスト API |
| `pid` | number | 未起動時 `-1` |
| `ready` | bool | トークン認証済み |
| `restarts` | number | 初回以降の監視付き起動回数 |
| `enabled` | bool | 実行時の有効状態 |
| `permissions` | string | カンマ区切りスコープ |
| `requires`、`after` | string 配列 | 依存 ID |
| `last_error` | string | 正常時は空。最大 128 バイト |
| `failures` | number | 連続失敗回数 |
| `next_restart_ms` | number | 残りバックオフ。なければ 0 |

`config --json` はさらに `extension_ready_timeout` を含みます。実行時の診断は
設定マニフェストには含まれません。

利用側は未知の JSON キーを無視してください。提供側はキーを追加できますが、
schema 1 内で既存キーの削除・改名・並べ替えはできません。`config --json` は
設定上の `enabled`、実行時配列は `extension-enable` 後のセッション状態を
示します。

## イベント

ライフサイクルイベントは `extension-start`、`extension-ready`、
`extension-failed`、`extension-stop` です。各イベントは `arg=<拡張 ID>` だけを
持ち、拡張固有の追加フィールドはありません。イベントはベストエフォートで、
`events` スコープで購読したクライアントにだけ届きます。
`extension-failed` は起動失敗、プロセス終了、ready timeout を含みます。
理由は JSON の `last_error` を確認してください。

## 変更時チェックリスト

拡張の挙動を変える場合:

1. `extension_api = 1` の追加変更か破壊的変更かを決める。
2. `src/api.zig`、`src/config.zig`、`src/extension_manager.zig`、
   `src/ipc.zig`、`src/json_snapshot.zig` を同時に更新する。
3. `config/config.example`、`docs/EXTENDING.*`、`docs/GUIDE.*`、この文書を
   更新する。
4. `tests/extension-api.sh` を追加・拡張し、`EXT` の 8 フィールドを維持する。
5. 拡張、IPC、JSON、fuzz、smoke テストを実行する。

## 適合テスト

- `tests/extension-api.sh`: ハンドシェイク、スコープ、fail-closed HELLO、
  購読リセット、失効、トークン回転、ready timeout、起動順、依存重複、
  JSON 診断。
- `tests/extensions.sh`: マニフェスト検証、ライフサイクル、enable/disable。
- `tests/ipc-version.sh`、`tests/json-ipc.sh`、`tests/json-rpc.sh`:
  プロトコルのフレーミングと JSON スキーマ。
- `tests/fuzz-parsers.sh`: 不正なマニフェストと IPC 行。
