**English** | [日本語](BENCHMARK.ja.md)

<!-- tessa-site-notice:start -->
> [!NOTE]
> This document has been ported to the website. Read the current version at <https://keychrom.github.io/docs/benchmark/>.
<!-- tessa-site-notice:end -->

# Benchmark: wayland-compositor-bench

Tessa was measured with
[wayland-compositor-bench](https://github.com/grigio/wayland-compositor-bench)
v0.6.1 on 2026-11-03. The tool measures the running Wayland session rather than a synthetic
nested compositor, so the figures include Tessa's integrated panel, effects,
and the live desktop configuration.

No single score is produced. Compare individual axes and treat differences
smaller than the reported run-to-run range as noise.

## Environment

| | |
| --- | --- |
| Compositor | Tessa `0.2.5` development tree, scenefx build, blur on |
| Session | Live DRM session on `card1-eDP-1` |
| Display | 1920×1080 @ 59.93 Hz |
| CPU | Intel Core i5-6300U (2 cores / 4 threads) |
| GPU | Intel Skylake-U GT2 (HD Graphics 520), i915, Mesa 26.2.6 |
| Kernel | 7.2.11-arch1-1 |
| Profile | `native` (session as configured) |
| Runs | 3 consecutive runs, all rated **high confidence** |

The benchmark reports the compositor as `tessa-ink` with the panel and
`xdg-desktop-portal` attributed as the modular stack. Battery was charging and
RAPL was unreadable without root, so package/battery power is not reported.
Those are the only failed confidence checks; the benchmark still rated every
run high confidence.

## Results

Medians with `[min–max]` where runs differed by more than 1%.

### Idle session

| RAM MiB | peak MiB | anon MiB | comp PSS MiB | stack PSS MiB | procs | CPU % | comp CPU % | stack CPU % | unrelated CPU % | wakeups/s |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 120 [120–191] | 120 [120–191] | 73 [73–145] | 519 | 521 | 19 | 3.27 | 0.21 [0.17–0.22] | 0.31 [0.26–0.32] | 0.62 [0.61–0.76] | 3 [3–3] |

`comp`/`stack` PSS are the benchmark's attribution, not the compositor's
working set; use the RAM and anon columns for the session footprint.

### Extra toplevels

| ws/window | ws delta MiB | client GPU MiB | comp delta MiB | comp GPU MiB | residual MiB | post-close MiB | windows |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 16.2 [14.8–17.6] | 97 [89–106] | 172 [157–173] | -0.0 [-0.1–2.1] | 34 [34–35] | 34.9 [26.2–35.1] | 0.0 [0.0–0.1] | 6 |

### Frame timing — one animated surface

| fps | cadence Hz | panel % | comp ms/frame | CPU@60 Hz % | comp GPU ms | client GPU ms | p95 ms | dropped | frames |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 59.7 | 59.9 | 99.6 | 2.402 [2.380–2.413] | 14.34 [14.21–14.41] | 0.758 | 11.436 | 17.73 | 1 | 358 |

### Frame timing — animated surface + extra windows

| fps | cadence Hz | panel % | comp ms/frame | CPU@60 Hz % | comp GPU ms | client GPU ms | p95 ms | dropped | frames |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 53.3 [52.8–53.8] | 59.9 | 89.0 [88.1–89.8] | 4.595 [4.562–4.737] | 24.57 [24.22–25.27] | 4.234 | 12.295 | 33.97 | 39 [36–42] | 320 [316–323] |

### During the run

| RAM peak MiB | CPU avg % | CPU peak % |
| --- | --- | --- |
| 276 [271–345] | 13.9 [13.8–15.2] | 100.5 [100.4–104.0] |

### Protocol surface

The scan reports 23 of 31 tracked desktop/protocol features (74.2%), or 30 of
46 when optional tiers are included. One feature is marked stale
(`wp_cursor_shape_manager_v1`). The full per-global list, timeline, and phase
marks are in the raw JSON.

## Raw results

- [Run 1](benchmarks/tessa-native-1.json)
- [Run 2](benchmarks/tessa-native-2.json)
- [Run 3](benchmarks/tessa-native-3.json)

The raw files contain the complete 25 ms RAM/CPU series, 100 ms CPU timeline,
protocol versions, and confidence checks.

## Reproduce

Run inside the logged-in Tessa session:

```sh
wayland-compositor-bench --check
wayland-compositor-bench --run --json results/tessa-native-1.json --label tessa-native
wayland-compositor-bench --run --json results/tessa-native-2.json --label tessa-native
wayland-compositor-bench --run --json results/tessa-native-3.json --label tessa-native
wayland-compositor-bench --report results/
```

The three runs above used the tool's native profile and default 20 s idle,
6 s frame tests, and six extra toplevels. Use `--profile reference` when
comparing across machines or compositor configurations.
