# Hardening log

One entry per feature version, recorded at the point it hardens cleanly (timing/DRC/LVS
all clean) and is about to be merged to `main`. This is the persistent record the
`runs/wokwi/final/metrics.json` numbers don't survive on their own - `tt_tool.py --harden`
deletes and recreates `runs/wokwi` on every run, so this file is what actually lets later
steps compare their area/timing delta against the version that came before.

**Workflow**: one branch per feature step (per [rtl-plan.md](rtl-plan.md)). Implement, run
the DV suite, harden, confirm clean, append an entry here, merge to `main`. `main` is
always the last version that both passed DV and hardened cleanly in one tile.

**Reading the numbers**: `PL_TARGET_DENSITY_PCT` is a *target* fed to global placement,
not the final result - actual final utilization is usually higher, since clock buffers,
hold-fix buffers, and tap cells get added by later stages on top of what global placement
originally packed. The "core area used (excl. fill)" / utilization numbers below are the
real post-route figures, not the config target.

---

## v0 — Baseline Pong, SystemVerilog port

**Date**: 2026-08-30
**Branch**: `main`
**Scope**: unmodified `robojan/tt04-pong` gameplay, Verilog → SystemVerilog cleanup pass
(mechanical, `always_comb`/`always_ff`, `logic`, proper `assign` for what were `wire x =
expr` continuous assignments), VGA-Pmod pin-mapping fix, top module renamed to
`tt_um_np523_pong`. No new features yet - this is the checkpoint the rest of the plan
diffs against.

### Timing (`CLOCK_PERIOD` = 20ns / 50MHz, all PVT corners)

| Metric | Value |
|---|---|
| Setup WNS / TNS | 0 / 0 (no violations, every corner) |
| Setup worst slack | +9.31ns (worst corner: max_ss_100C_1v60) to +16.83ns (best corner) |
| Hold WNS / TNS | 0 / 0 (no violations, every corner) |
| Hold worst slack | +0.104ns (worst corner: nom/min_ff_n40C_1v95) |
| Setup-fix buffers inserted | 0 (no setup repair needed - huge margin already) |
| Hold-fix buffers inserted | 56 |
| Worst clock skew (setup / hold) | ±0.256ns |

Comfortable margin at 50MHz against an actual ~25MHz operating target - real headroom
before speed-up/AI/effects logic could threaten timing closure.

### Area

| Metric | Value |
|---|---|
| Die area | 17,954.7 µm² (161.0 × 111.52 µm - the real TT tile boundary) |
| Core area (placeable) | 16,493.3 µm² |
| **Core utilization (real logic, excl. fill)** | **77.3%** |
| **Free / available headroom** | **~22.7% (≈3,743 µm²)** |
| `PL_TARGET_DENSITY_PCT` (config target, not final) | 60 |

### Area breakdown by cell class (µm²)

| Class | Area (µm²) | % of core |
|---|---:|---:|
| Multi-input combinational | 5,893.15 | 35.7% |
| Sequential (flip-flops) | 4,072.66 | 24.7% |
| Fill cells (non-functional, backfills unused space) | 3,743.59 | 22.7% |
| Clock buffers (CTS) | 1,151.10 | 7.0% |
| Timing-repair buffers (hold-fix, see above) | 1,168.62 | 7.1% |
| Tap/decap cells (mandatory, not logic) | 281.52 | 1.7% |
| Inverters | 135.13 | 0.8% |
| Buffers (non-clock, non-repair) | 45.04 | 0.3% |
| Antenna cells | 2.50 | 0.0% |

### Sign-off

| Check | Result |
|---|---|
| Magic DRC | 0 errors |
| Routing DRC (final iteration) | 0 errors |
| LVS | clean (0 device/net/pin/property mismatches) |
| Antenna violations | 0 |
| Illegal overlaps | 0 |
