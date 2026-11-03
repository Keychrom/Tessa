[English](RENDERING.md) | **日本語**

<!-- tessa-site-notice:start -->
> [!NOTE]
> このドキュメントは Web サイトに移植されました。最新版は <https://keychrom.github.io/ja/docs/rendering/> を参照してください。
<!-- tessa-site-notice:end -->

# 描画・ゲーム機能

Tessa は upstream wlroots 0.20 の API を使って、direct scanout、tearing、
explicit sync、出力別の描画統計を提供します。HDR は本ドキュメントで調査結果を
まとめていますが、まだ実装していません。

## 状態の確認

```sh
tessa-ctl rendering
tessa-ctl rendering --json
tessa-ctl perf
tessa-ctl perf --json
tessa-ctl perf --watch=2
```

`rendering` は静的な能力と出力別の scanout カウンタを表示します。`perf` は
フレーム時間のサンプルと、同じ出力別カウンタをローリングウィンドウで表示
します。どちらもポーリングして安全で、`--json` はスクリプトやダッシュボード
向けです。

実機 DRM セッションでは `drm_fd >= 0`、renderer が timeline に対応していれば
`explicit_sync_active 1` になります。headless pixman は状態機械のテストには
使えますが、`backend_drm_fd -1`、`color_management 0` のままです。

## Direct scanout

wlroots のシーンコンポジタは、render list がちょうど 1 エントリのときだけ
クライアントの DMA-BUF を表示コントローラへ直接渡せます。通常の Tessa の
シーンには背景矩形、壁紙/背景 layer、バー、ボーダー、影、blur node、他の
ウィンドウがあるため、direct scanout にはフルスクリーン専用のモードが必要です。

次の条件を満たすフルスクリーンクライアントがあるとき:

- 出力全体を覆い、不透明度が 1
- tint のアルファが 0
- アクティブワークスペースで可視、アニメーション中でない
- 内容バッファを持つ

`src/render.zig` が単一エントリを妨げるコンポジタ所有のノードを退避します:

- `out.bg_rect` と background/bottom/top layer の layer-shell サーフェス
- その出力の他の可視クライアントのフレーム
- 対象クライアントの scenefx blur node

overlay layer、入力メソッドのポップアップ、閉じるアニメーションの
スナップショット、通知はフルスクリーンより上に残します。これらが見えている
間は render list が複数になり、wlroots は通常のコンポジションへ戻ります。
デスクトップの見た目は正しく、そのフレームだけ scanout されないだけです。
フルスクリーンを解除する、対象を unmap する、破棄すると、背景、mapped な
layer ツリー、可視クライアントのフレーム、blur 状態を復元します。

設定:

```ini
direct_scanout = true   # 既定
```

`direct_scanout = false` で状態機械全体を無効化できます。実行中に変更でき、
次のコミットでシーンノードが復元または退避されます。

制約:

- クライアントは出力全体を覆う単一バッファが必要です。subsurface が多い
  アプリはコンポジションへ戻ります。scanout 中は背景を隠すため、不透明な
  内容を強く推奨します。
- `wlr_buffer_is_opaque()` は多くの DMA-BUF で false negative を返すため、
  Tessa はこの結果だけで scanout を拒否しません。シーンが plane format を
  検証し、バックエンドがコミットを拒否すれば自動的にフォールバックします。
- カーソルはハードウェアカーソルとして使える必要があります。ソフトウェア
  カーソルへのフォールバックは scanout を妨げる場合があります。
- scanout 対象では scenefx のブラーと角丸を無効化します。シーンの他の部分の
  エフェクトは維持されます。

### 成功したか確認する

`tessa-ctl rendering` の出力:

```text
OUTPUT eDP-1 1920x1080 scanout_active=1 scanout_frames=123 \
  zero_copy=120 tearing_requests=0 tearing_failures=0
```

- `scanout_active`: 単一エントリモードに入っている
- `scanout_frames`: `direct_scanout == true` の
  `wlr_scene_buffer` output sample 数
- `zero_copy`: `WLR_OUTPUT_PRESENT_ZERO_COPY` 付きの present 数。DRM では
  コンポジションが省略された最も直接的な証拠

headless では `zero_copy` は増えないため、`scanout_active` で確認します。

## Tearing

Tearing は `wp-tearing-control-v1` を使います。フルスクリーンというだけで
有効になることはありません。クライアントが async presentation hint を設定し、
コンポジタ側でも許可されている必要があります。

```ini
tearing = off         # 既定: async page flip を要求しない
tearing = fullscreen  # async hint のあるフルスクリーンクライアント
tearing = force       # async hint のある任意のクライアント（上級者向け）
```

グローバルが `off` のまま、ウィンドウ単位で有効化できます:

```ini
window-rule = app-id=gamescope; tearing=true
window-rule = app-id=mpv; tearing=off
```

コミット経路はシーン状態を構築し、`state.tearing_page_flip` を設定し、
`wlr_output_test_state()` で検証してからコミットします。ドライバーが async
flip を拒否した場合はフラグを戻し、`tearing_failures` を増やして通常の
page flip を行います。実際のコミットが失敗した場合もログを残し、次フレームで
通常 flip を再試行します。

Intel i915 の一部設定を含め、async flip を拒否するドライバーがあります。
これは想定内で、tearing は保証ではなくヒントです。`tessa-ctl rendering` の
`tearing_requests` と `tearing_failures` でカーネル/ディスプレイが受理したかを
確認できます。全フレームでtearingが見える可能性があるため、既定は off です。

## Explicit sync

次の条件がすべて真のとき、Tessa はクライアント接続前に
`wlr_linux_drm_syncobj_manager_v1_create()` を生成します:

- `explicit_sync = true`（既定）
- `renderer.features.timeline`
- `backend.features.timeline`
- backend の DRM fd がある（`wlr_backend_get_drm_fd() >= 0`）。syncobj manager には利用可能なら renderer の DRM fd を使う

wlroots のシーングラフが acquire/release timeline を自動的に扱うため、Tessa に
サーフェス単位のフェンス処理は不要です。scenefx/GLES2 ビルドは timeline 対応を
報告しない場合があり、headless とネストしたバックエンドは意図的に対象外です。

`tessa-ctl rendering` の表示:

```text
explicit_sync 1
explicit_sync_active 1
renderer_timeline 1
backend_timeline 1
```

`explicit_sync` は要求設定、`explicit_sync_active` は実際の manager 状態です。
プロトコル global はクライアント接続前に作るため、設定変更にはコンポジタの
再起動が必要です。timeline を広告しても扱いが壊れているドライバーでは
`explicit_sync = false` で回避できます。

## 性能計測

コミットされた出力フレームごとに、アニメーション/scanout 更新前から
`wlr_output_commit_state()` 成功までのフレームハンドラ時間
（`layout.tickAnimations`、`effects.tick`、`render.refreshScanout`、
scene state build、commit）を次へ記録します:

- `Server.perf`（全出力の集計）
- `Output.perf`（出力別のローリングサンプル）

先に `wlr_scene_output_needs_frame()` を確認し、
`wlr_scene_output_commit()` と同じ早期終了条件にしているため、描画不要の
フレームはレンダーとして数えません。静止画面ではリフレッシュごとに 1 サンプル
増えるのではなく、安定したフレーム数になります。

出力別カウンタ:

| カウンタ | 取得元 | 意味 |
| --- | --- | --- |
| `presented` | `wlr_output.events.present` | 完了した present |
| `zero_copy` | `WLR_OUTPUT_PRESENT_ZERO_COPY` | コンポジションを省略した present |
| `vsync` | `WLR_OUTPUT_PRESENT_VSYNC` | vsync された present |
| `missed` | present `seq` の欠番 | 逃した出力シーケンス |
| `scanout_frames` | `output_sample.direct_scanout` | scanout でサンプルされたクライアントバッファ |
| `tearing_requests` | test-commit 成功 | async flip を試行 |
| `tearing_failures` | test/commit 拒否 | 通常 flip へフォールバック |

フレーム時間（`frames`、`samples`、`avg_us`、`p50_us`、`p95_us`、`max_us`、
`last_us`、`budget_ms`、`over_budget`）はトップレベルで従来の意味を保ち、
`outputs[]` にも出力別で入ります。`frame_time_budget` は超過判定のしきい値です。
`tessa-ctl perf` はさらに top-level の `effect_applies`、`effect_skips`、
`blur_nodes` を返します（`outputs[]` には入りません）。ローリング窓なのは
フレーム時間サンプル（4096 フレーム）だけで、イベント/エフェクトカウンタは
`perf --reset` まで累積します。

## HDR / color management の調査

今回の変更で HDR は**実装していません**。`wp-color-management-v1` global は
公開せず、`tessa-ctl rendering` は `color_management 0` を返します。

wlroots 0.20 が提供するもの:

- `wp-color-management-v1` version 2。パラメトリックな image description、
  mastering display metadata、piece-wise sRGB transfer function を含む
- `wlr_color_manager_v1_create()` と、render intent / transfer function /
  primaries の広告
- `wlr_output_state` の output image description と post-blending color
  transform（`WLR_OUTPUT_STATE_IMAGE_DESCRIPTION`、
  `WLR_OUTPUT_STATE_COLOR_TRANSFORM`）
- コネクタとドライバーが対応していれば、DRM の PQ/BT.2020 系 HDR metadata

Tessa の現在の描画経路で足りないもの:

- Tessa は GLES2（`wlr_renderer_autocreate()`）または scenefx の GLES2
  renderer を使います。`renderer.features.output_color_transform` は通常
  false で、HDR 出力を作れません。Sway の HDR10 対応も Vulkan renderer が
  前提です。
- wlroots は tone mapping を提供しません。SDR コンテンツを HDR 出力へどう
  写すか、SDR white level をどうするか、HDR コンテンツを SDR 出力へどう
  写すかはコンポジタのポリシーです。ポリシーなしでプロトコルを広告すると
  色が破綻します。
- scenefx のブラー/角丸は GLES2 専用で、Vulkan の色パイプラインと両立しません。
- 出力ごとの HDR/SDR ポリシー、EDID primaries の取り回し、HDR 非対応
  コネクタでのフォールバックがありません。

将来の実装手順:

1. オプションの Vulkan renderer 経路を追加し、color management の対応を
   `output_color_transform` に条件付ける。
2. EDID/コネクタ特性から HDR 対応出力を検出し、出力別の
   `hdr = off|auto|on` ポリシーを用意する。
3. renderer と DRM が実際に出力できる transfer function / primaries だけを
   広告し、`tessa-ctl rendering` に表示する。
4. 既定で有効化する前に SDR white / tone mapping と HDR→SDR 変換を実装する。
5. HDR テストパターンと実機 HDR ディスプレイで検証し、機能 off の SDR
   セッションを変えない。

それまでは HDR クライアントは SDR でネゴシエートし、
`color_management 0` が正しい状態です。

## ドライバー検証チェックリスト

headless ではなく実機 DRM で実行します:

1. `tessa-ctl rendering` で `drm_fd`、`backend_drm_fd`、`renderer_timeline`、
   `backend_timeline`、`explicit_sync_active`、`output_color_transform` を
   記録する。
2. 不透明なクライアント（`kitty --start-as=fullscreen`、`foot -F`、ゲーム）を
   フルスクリーンにし、`scanout_active=1`、`scanout_frames` の増加、
   `zero_copy` の増加を確認する。
3. `tests/tearing.sh` または async hint を設定するゲームを実行し、
   `tearing_requests` と `tearing_failures` を記録する。失敗が増えても
   デスクトップが安定していれば、ドライバーの正常なフォールバックであり
   コンポジタのクラッシュではない。
4. Vulkan/GL ゲームを実行し、journal に `linux-drm-syncobj` や timeline の
   エラーがないこと、`explicit_sync_active` を確認する。
5. `direct_scanout=false`、`tearing=off`、`explicit_sync=false` でも確認する。
6. Intel i915、AMD、NVIDIA、vmwgfx が利用できる環境で試し、結果をロードマップ
   の検証マトリクスへ記録する。
