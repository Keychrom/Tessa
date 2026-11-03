**English** | [日本語](EXTENSION-API.ja.md)

<!-- tessa-site-notice:start -->
> [!NOTE]
> This document has been ported to the website. Read the current version at <https://keychrom.github.io/docs/extension-api/>.
<!-- tessa-site-notice:end -->

# Extension API v1 stability contract

This document is the canonical contract for Tessa's supervised extension API.
`src/api.zig` is the source of truth for version numbers; the protocol details
below are frozen for the 0.2.x line.

## Scope

Stable in v1:

- the line protocol on `$TESSA_IPC`
- supervised extension manifests, tokens, scopes, lifecycle, and supervision
- the text `EXT` state line and the runtime `extensions` JSON array
- the extension-related config keys and JSON fields
- the lifecycle event names and their `arg` payload

Not covered here:

- `ext-workspace-v1` and other Wayland protocols (see
  [ARCHITECTURE.md](ARCHITECTURE.md))
- panel drawing and internal module interfaces
- `tessa-ctl` presentation details, which are a reference client rather than
  the protocol itself

## Versions

| Value | Current | Meaning |
| --- | --- | --- |
| `line_protocol` | 1 | line framing, `HELLO`, commands, `STATE`/`END` |
| `extension_api` | 1 | manifest API and supervised extension behavior |
| `state_schema` | 1 | `state-json` document |
| `config_schema` | 1 | `config-json` document |

`HELLO` negotiates the line protocol and returns `VERSION`. The extension API is
declared per manifest with `api=`. A manifest requiring a newer API is a config
error. `tessa_version` is informational; use the individual API versions.

`extension_api = 1` is frozen for 0.2.x. Additive JSON fields, commands,
permission names, event topics, and error codes may be added. Removing or
renaming a field, reordering the `EXT` line, changing an existing error frame,
or changing token semantics requires `extension_api = 2`.

## Transport and handshake

The socket is `$TESSA_IPC`, or `$XDG_RUNTIME_DIR/tessa.sock`, mode 0600. Lines
are LF-delimited UTF-8. Fields are tab-separated. The maximum line buffer is
8192 bytes.

```text
HELLO <version> [<token>]
VERSION	1
CAPABILITIES	state,config,events,subscriptions,config-compare,perf,rendering,special,groups,extensions,effects2,shell-modules
EXTENSION	<id>	<permissions>
```

- `HELLO` may use spaces or tabs.
- A missing version means 1. `0` and non-numeric versions return
  `ERR invalid-version`.
- A token-bearing `HELLO` is fail-closed: if authentication fails, the
  connection is scoped with no permissions, even when the version itself is
  invalid. It never falls back to legacy full access.
- `EXTENSION` is sent only when this handshake authenticated successfully.
- A tokenless `HELLO` is legacy behavior: the client keeps full access. This is
  for `tessa-ctl`, the panel, and existing tools. A supervised extension must
  use its token.
- Token-bearing `HELLO` clears any subscriptions made before authentication.
  Re-subscribe after authenticating.
- A connection may authenticate at most one identity; a later failed token
  clears the identity and permissions.

## Errors

Errors use `ERR\t<code>[\t<detail>]`. V1 codes:

| Code | Meaning | Connection after the error |
| --- | --- | --- |
| `invalid-version` | `HELLO` version is 0 or not numeric | fail-closed if a token was present |
| `unauthorized` | token is unknown or the extension is not running/ready | no permissions |
| `forbidden` | command requires a scope the client does not have | unchanged |
| `busy` | IPC connection limit reached | connection closed |
| `unknown-command` | scoped client sent an unknown command | unchanged |
| `bad-argument` | a recognized command had invalid arguments | unchanged |
| `unknown-extension` | `extension-enable` named a missing id | unchanged |

`forbidden` is `ERR\tforbidden\t<command>`. Unknown commands are reported only
to scoped clients so legacy tools that probe commands are not disturbed.

JSON-RPC uses `-32001 forbidden` for scope denials, `-32700` for parse errors,
`-32600` for invalid requests, and `-32601` for unknown methods. JSON-RPC clients
must send the line `HELLO` first if they need an extension identity; there is no
separate JSON token parameter in v1.

## Tokens

- A supervised extension receives `TESSA_EXTENSION_ID`,
  `TESSA_EXTENSION_TOKEN`, `TESSA_EXTENSION_API`, and
  `TESSA_EXTENSION_PERMISSIONS`.
- The token is 32 lowercase hex characters and is regenerated on every
  supervised start, including crash restarts and disable/enable cycles.
  Tokens are not written to config or the JSON API.
- Stopping, disabling, crashing, or reloading an extension revokes its
  authenticated connections: scopes are cleared and subscriptions are dropped.
  The old token is rejected while the extension is stopped and after a new
  process starts.
- Multiple connections may use the same live token. Revocation applies to all
  of them.
- Scopes are cooperative, not a sandbox. Extensions run as the compositor's
  user and can read the token or socket directly. Token rotation and revocation
  prevent stale connections from continuing after the supervisor has stopped
  the process; they do not defend against a malicious same-user process.

## Lifecycle and supervision

| State | Meaning |
| --- | --- |
| `disabled` | `enabled=false` |
| `blocked` | a `requires` dependency is not `ready` |
| `stopped` | stopped deliberately with `extension-enable off` |
| `starting` | reserved; not currently emitted |
| `running` | process started, token not yet authenticated |
| `ready` | token authenticated (`EXTENSION` was sent) |
| `failed` | process exited, failed to start, or missed the ready timeout |

`running` is not healthy. Health is `ready=1`; use it for readiness checks.

`extension_ready_timeout` (milliseconds, default `10000`, `0` disables) applies
to each start. A process that does not authenticate in time is killed, marked
`failed`, given `last_error = "ready timeout"`, and restarted through the normal
backoff. Values outside `1000..60000` are clamped when the timeout is enabled.

Restart backoff after a failure is 1 s, 2 s, 4 s, then 8 s. A process that ran
for at least 10 seconds resets the failure counter on exit. Transient failures
are visible as `failures` and `next_restart_ms` in JSON.

## Dependencies

- `requires=a,b` blocks startup until each dependency is `ready`.
- `after=a,b` controls startup order only.
- Duplicate ids in one dependency list, an id in both `requires` and `after`,
  self-dependency, unknown ids, and cycles are config errors.
- The supervisor starts in topological order. If a dependency later fails, an
  already-running dependent is not stopped; the requirement is checked again on
  its next start attempt.
- The maximum is 16 extensions, 8 dependencies per manifest, 32 bytes per id,
  and 32 bytes per token.

## Permissions and commands

Default: `read,status`.

| Scope | Commands / delivery |
| --- | --- |
| `read` | `state`, `state-json`, `config`, `config-json`, `config-compare`, `perf`, `perf-json`, `rendering`, `rendering-json`, `subscribe state` |
| `events` | `subscribe events`, event delivery |
| `status` | `status`, tab-separated `CMD<TAB>status` |
| `window` | `focus`, `close`, `urgent`, `float`, `swap`, `reorder`, `resize`, group commands |
| `workspace` | `workspace`, `move-workspace`, special/scratchpad commands |
| `layout` | `layout`, column and window-move commands |
| `spawn` | `spawn` |
| `panel` | `launcher`, `panel`, `notification-action` |
| `control` | `reload`, `quit`, `mode`, `perf-reset` |
| `extensions` | `extensions`, `extensions-json`, `extension-enable` |

`subscribe all` requires both `read` and `events`. A scoped client without the
needed scope receives `ERR forbidden subscribe` and no subscription is changed.

## Text and JSON schemas

The text `EXT` line is frozen at exactly eight space-separated fields:

```text
EXT <id> <state> <api> <pid> <ready> <restarts> <enabled> <permissions>
```

`pid` is `-1` when not running. `permissions` is a comma-separated scope list.
Do not append diagnostic fields to this line; use JSON.

`state --json`, `extensions-json`, and `tessa-ctl extensions --json` expose an
`extensions` array with these keys:

| Key | Type | Notes |
| --- | --- | --- |
| `id` | string | manifest id |
| `state` | string | state table above |
| `api` | number | manifest API |
| `pid` | number | `-1` when not running |
| `ready` | bool | token authenticated |
| `restarts` | number | supervised starts after the first |
| `enabled` | bool | runtime enable state |
| `permissions` | string | comma-separated scopes |
| `requires`, `after` | string arrays | dependency ids |
| `last_error` | string | empty when healthy; up to 128 bytes |
| `failures` | number | consecutive failures |
| `next_restart_ms` | number | remaining backoff delay, 0 when none |

`config --json` additionally exposes `extension_ready_timeout`. Runtime
diagnostics are not part of the config manifest.

Consumers must ignore unknown JSON keys. Producers may add keys but must not
remove, rename, or reorder existing keys within schema 1. `config --json` shows
the configured `enabled` value; the runtime array shows the session state after
`extension-enable`.

## Events

Lifecycle topics are `extension-start`, `extension-ready`, `extension-failed`,
and `extension-stop`. Each carries `arg=<extension id>` and no other extension
fields. Events are best-effort and are delivered only to clients subscribed to
events with the `events` scope. `extension-failed` covers start failures,
process exits, and ready timeouts; inspect `last_error` in JSON for the reason.

## Change checklist

When changing extension behavior:

1. Decide whether it is additive under `extension_api = 1` or breaking.
2. Update `src/api.zig`, `src/config.zig`, `src/extension_manager.zig`,
   `src/ipc.zig`, and `src/json_snapshot.zig` together.
3. Update `config/config.example`, `docs/EXTENDING.*`, `docs/GUIDE.*`, and this
   document.
4. Add or extend `tests/extension-api.sh` and keep the eight-field `EXT` line
   unchanged.
5. Run the extension, IPC, JSON, fuzz, and smoke tests.

## Conformance tests

- `tests/extension-api.sh`: handshake, scopes, fail-closed HELLO, subscription
  reset, revocation, token rotation, ready timeout, ordering, duplicate
  dependencies, JSON diagnostics.
- `tests/extensions.sh`: manifest validation, lifecycle, enable/disable.
- `tests/ipc-version.sh`, `tests/json-ipc.sh`, `tests/json-rpc.sh`: protocol
  framing and JSON schemas.
- `tests/fuzz-parsers.sh`: malformed manifests and IPC lines.
