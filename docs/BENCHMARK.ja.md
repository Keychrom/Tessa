[English](BENCHMARK.md) | **日本語**

<!-- tessa-site-notice:start -->
> [!NOTE]
> このドキュメントは Web サイトに移植されました。最新版は <https://keychrom.github.io/ja/docs/benchmark/> を参照してください。
<!-- tessa-site-notice:end -->

# ベンチマーク: wayland-compositor-bench

Tessa を
[wayland-compositor-bench](https://github.com/grigio/wayland-compositor-bench)
v0.6.1 で 2026-11-03 に計測しました。合成したネスト Compositor ではなく、実際にログイン
している Wayland セッションを測るツールなので、Tessa の統合パネル、エフェクト、
実際のデスクトップ設定を含む数値です。

単一スコアは出力されません。軸ごとに比較し、実行間のばらつき範囲より小さい
差はノイズとして扱ってください。

## 環境

| | |
| --- | --- |
| Compositor | Tessa `0.2.5` 開発ツリー、scenefx ビルド、blur 有効 |
| セッション | `card1-eDP-1` 上の実 DRM セッション |
| ディスプレイ | 1920×1080 @ 59.93 Hz |
| CPU | Intel Core i5-6300U（2 コア / 4 スレッド） |
| GPU | Intel Skylake-U GT2（HD Graphics 520）、i915、Mesa 26.2.6 |
| カーネル | 7.2.11-arch1-1 |
| プロファイル | `native`（設定済みのセッションをそのまま計測） |
| 実行回数 | 連続 3 回、すべて **high confidence** |

Compositor は `tessa-ink` として検出され、パネルと
`xdg-desktop-portal` が modular stack として集計されています。バッテリーが
充電中で、RAPL は root なしでは読めなかったため、package/battery 電力は
未計測です。失敗した confidence チェックはこの 2 点だけで、実行自体はすべて
high confidence と判定されています。

## 結果

実行間の差が 1% を超えた項目は `[最小–最大]` 付きの中央値です。

### アイドル時

| RAM MiB | ピーク MiB | anon MiB | comp PSS MiB | stack PSS MiB | プロセス数 | CPU % | comp CPU % | stack CPU % | その他 CPU % | wakeups/s |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 120 [120–191] | 120 [120–191] | 73 [73–145] | 519 | 521 | 19 | 3.27 | 0.21 [0.17–0.22] | 0.31 [0.26–0.32] | 0.62 [0.61–0.76] | 3 [3–3] |

`comp`/`stack` PSS はツールの帰属計算であり、Compositor のワーキングセット
そのものではありません。セッションのメモリ量は RAM と anon 列で見てください。

### 追加トップレベル

| ws/ウィンドウ | ws 増分 MiB | クライアント GPU MiB | comp 増分 MiB | comp GPU MiB | 残存 MiB | クローズ後 MiB | ウィンドウ数 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 16.2 [14.8–17.6] | 97 [89–106] | 172 [157–173] | -0.0 [-0.1–2.1] | 34 [34–35] | 34.9 [26.2–35.1] | 0.0 [0.0–0.1] | 6 |

### フレーム時間 — アニメーション 1 面

| fps | cadence Hz | panel % | comp ms/frame | CPU@60 Hz % | comp GPU ms | client GPU ms | p95 ms | dropped | frames |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 59.7 | 59.9 | 99.6 | 2.402 [2.380–2.413] | 14.34 [14.21–14.41] | 0.758 | 11.436 | 17.73 | 1 | 358 |

### フレーム時間 — アニメーション + 追加ウィンドウ

| fps | cadence Hz | panel % | comp ms/frame | CPU@60 Hz % | comp GPU ms | client GPU ms | p95 ms | dropped | frames |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 53.3 [52.8–53.8] | 59.9 | 89.0 [88.1–89.8] | 4.595 [4.562–4.737] | 24.57 [24.22–25.27] | 4.234 | 12.295 | 33.97 | 39 [36–42] | 320 [316–323] |

### 実行中

| RAM ピーク MiB | CPU 平均 % | CPU ピーク % |
| --- | --- | --- |
| 276 [271–345] | 13.9 [13.8–15.2] | 100.5 [100.4–104.0] |

### プロトコル

追跡対象のデスクトップ/プロトコル機能は 31 中 23（74.2%）、任意ティアを
含めると 46 中 30 です。1 件（`wp_cursor_shape_manager_v1`）が stale と
判定されています。グローバルごとの一覧、タイムライン、フェーズマーカーは
生 JSON に含まれます。

## 生データ

- [Run 1](benchmarks/tessa-native-1.json)
- [Run 2](benchmarks/tessa-native-2.json)
- [Run 3](benchmarks/tessa-native-3.json)

生 JSON には 25 ms 間隔の RAM/CPU 系列、100 ms の CPU タイムライン、
プロトコルバージョン、confidence チェックがすべて入っています。

## 再現方法

ログイン中の Tessa セッション内で実行します:

```sh
wayland-compositor-bench --check
wayland-compositor-bench --run --json results/tessa-native-1.json --label tessa-native
wayland-compositor-bench --run --json results/tessa-native-2.json --label tessa-native
wayland-compositor-bench --run --json results/tessa-native-3.json --label tessa-native
wayland-compositor-bench --report results/
```

上の 3 回は native プロファイル、既定の 20 秒アイドル、6 秒フレームテスト、
追加トップレベル 6 個で実行しました。マシンや Compositor 設定をまたいで
比較する場合は `--profile reference` を使ってください。
