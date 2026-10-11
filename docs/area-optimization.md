# Area Optimization — Notes and Results

Record of the RTL-side area optimization work on the TTSKY26c Pong submission,
written up for reference and interview discussion.

All areas are measured, not estimated: each figure comes from an actual
`stat -liberty` run in Yosys against the sky130 `tt_025C_1v80` corner, via
`scripts/synth_area.sh`. Nothing here is a hand-count of gates.

---

## Headline results

| Metric | Before | After | Δ |
|---|---|---|---|
| Whole design (sum of modules) | 11,889 µm² | 9,594 µm² | **−19%** |
| Core utilization | 105.3% (placement failed) | 91.6% (clean signoff) | **−13.7 pts** |

Per-module, largest first:

| Module | Before | After | Δ |
|---|---|---|---|
| `starfield_painter` (rewrite) | 15,593 µm² | 2,542 µm² | **−84%** |
| `ai_opponent` (rewrite) | 932 µm² | 484 µm² | −48% |
| `lives_painter` (2 → 1 instance) | 1,279 µm² | 722 µm² | −44% |
| `copper_bars_painter` (restructure) | 1,020 µm² | 652 µm² | −36% |
| `paddle_painter` (2 → 1 instance) | 911 µm² | 599 µm² | −34% |
| `video_mux` (layer merge) | 357 µm² | 248 µm² | −31% |

Final signoff: DRC 0, LVS "circuits match uniquely", antenna 0, setup slack
+19.27 ns, hold slack +0.058 ns across all 12 PVT corners.

---

## 1. The LFSR that wasn't randomness

**15,593 → 2,542 µm² (−84%)**

The starfield stored, per star, an LFSR-seeded row (9 bits), a speed tier
(2 bits), and an x-position (10 bits). At 16 stars that is 21 × 16 = 336
flip-flops, plus the LFSR itself and its seeding sequencer — **345 flops**,
which measured as 9,551 µm² of sequential area alone.

The LFSR was seeded with a fixed constant, shifted deterministically, and
stopped after 16 cycles. It therefore produced the *identical* pattern on
every power-up. It was not generating randomness at runtime; it was an
expensive way to store constants. Computing the same values offline and
baking them in as `localparam`s drops that storage to **zero** — a `genvar`
index resolves at elaboration, so `row_of(3)` becomes the literal `9'd341`
before synthesis ever runs.

> An LFSR that runs once at reset and then holds forever is not a random
> number generator. It is a 345-flip-flop ROM with extra steps.

The generalizable skill is distinguishing **runtime entropy** from
**compile-time determinism**. If the sequence is the same on every boot, it
is a constant, and constants are free.

## 2. Algebraic rearrangement to share work

Second half of the same optimization.

With constants baked in, each star's on-screen position is still
`offset + scroll`, where `scroll` advances once per frame. Done naively that
is 16 adders — one per star — sitting in the always-live per-pixel compare
path.

Rearranging the comparison is what makes it cheap:

```
hpos == offset + scroll        →        (hpos − scroll) == offset
```

Now `hpos − scroll` is computed **once per speed tier** (3 subtractors), and
each star compares that shared value against a **constant**. That second part
matters more than it looks: a constant-comparator collapses into a plain AND
tree over `hpos` bits, which is dramatically cheaper than a register-versus-
register comparator.

Worth noting honestly: I first rejected this idea using incorrect algebra,
then caught the error on review. The instinct to re-derive rather than trust
the first pass is the transferable part.

## 3. Architectural instance sharing

| Module | Before (2 instances) | After (1 instance) | Δ |
|---|---|---|---|
| `lives_painter` | 1,279 µm² | 722 µm² | −44% |
| `paddle_painter` | 911 µm² | 599 µm² | −34% |

The P1 and P2 painters are structurally identical, differing only in
constants (their Y position). Critically, their active regions are
**mutually exclusive in time**: P1's lives band sits at row 466, P2's at
row 2 — 464 rows apart. A raster scan is physically incapable of being in
both simultaneously. One instance can therefore serve both, selected by a
single midpoint test (`vpos > 240`).

**The subtlety worth explaining.** `lives_cntr` is loaded during *horizontal
blanking*, which occurs before the next line's `vpos` is valid. A precise
band check (`in_p1_band ? p1_lives : p2_lives`) would load the wrong player's
count on the first row of each band. The coarse midpoint test is stable
across that boundary, which is precisely why it was chosen over the more
obvious formulation.

Both merges were proved **pixel-identical** before acceptance — 1.68M and
2.1M pixel-cycles respectively, across multiple lives values and paddle
positions.

> Resource sharing pays when instances are structurally identical *and*
> temporally mutually exclusive. It is the same principle as time-
> multiplexing, exploited spatially through raster scan order.

## 4. Derive state instead of storing it

**`copper_bars_painter`: 1,020 → 652 µm² (−36%)**

The original held a `scroll` register updated as:

```systemverilog
scroll <= direction_down ? (scroll + speed) : (scroll - speed);
```

That synthesizes a 9-bit adder *and* a 9-bit subtractor *and* a mux, on top of
9 flip-flops.

But `scroll` is a pure linear function of elapsed frames, so it can be derived
from the frame counter and the register deleted outright:

- **down**: `frame_cntr` — free
- **up**: `~(frame_cntr << 3)` — since `~(8k)` decreases by 8 as `k` rises

The `~x` versus `−x` discrepancy is a constant off-by-one, which in a
*repeating* pattern is just a phase shift — visually undetectable. The speed
was deliberately chosen as 8 (a power of two) so the multiply became a free
shift.

Two principles: **don't store what you can derive**, and **choose constants
that make the arithmetic free**.

## 5. Know when your modulus is arbitrary

Mod-640 wrapping is expensive — 640 isn't a power of two, so it needs a
compare, a conditional add, and a mux.

For the copper bars, the scroll value is an **abstract phase**, not a physical
screen coordinate. So a 9-bit counter was allowed to wrap naturally at 512,
and wraparound became **free** from ordinary binary truncation.

> If the modulus is a physical coordinate, you are stuck with it. If it is an
> internal phase, pick a power of two.

---

## Three optimizations that were measured and rejected

The most instructive results were the failures.

### Paddle clamp hoisting — **+100 µm², rejected**

Hoisting `x − speed` and `x + speed` out of the mutually-exclusive
`btn_left` / `btn_right` branches into continuous assigns looked like textbook
common-subexpression elimination. It measured **worse**.

The reason: because the branches are mutually exclusive, Yosys's `share` pass
was *already* reusing one adder between them. Hoisting forced both units to
exist unconditionally, every cycle.

> Manual CSE can actively defeat the tool's resource sharing, because the tool
> already exploits mutual exclusion within an always block.

### Velocity table restructure — **−36 µm² (0.8%), marginal**

The 4×6 velocity case table (24 entries) looked like an obvious target and was
restructured as `base_magnitude[segment] + tier_offset[tier]`, verified
bit-exact across all 512 input combinations. It barely moved the needle: it is
a 5-input → 4-output function, and ABC already synthesizes those near
optimally.

### Ball-painter lobe reduction — **−5 µm², noise**

The four-term lobe OR reduces algebraically to "inside the 5×5 box AND not a
cut corner". Bit-exact across the full 256-state space. ABC had already found
the same form.

### What the three have in common

> I was wrong three times running about expression-level optimization inside
> terse modules. Every genuine win came from architecture — removing duplicate
> *instances* and eliminating state that did not need to exist. The
> synthesizer beats you at Boolean minimization; it cannot restructure your
> design.

---

## Methodology

Every candidate change followed the same loop:

1. Identify the exact logic in question
2. Write the replacement
3. **Prove equivalence** by exhaustive or near-exhaustive simulation
4. **Measure** synthesized area
5. Accept only if it actually saves area — otherwise revert

Equivalence evidence gathered:

- **Paddle clamp**: swept all 8,192 (x, speed) combinations. Zero mismatches
  in the reachable space. The 56 out-of-range mismatches were characterized
  precisely — subtract-underflow at x < 7 and add-overflow at x > 608 — and
  both are unreachable *because that same logic is what clamps x into
  [7, 608]*.
- **Velocity table**: all 512 (tier, segment, velocity) combinations,
  bit-exact, including the unreachable segment 6/7 fallback path.
- **Shared painters**: millions of pixel-cycles, pixel- and segment-identical
  against the two-instance original.
- **Starfield wrap arithmetic**: 700 frames verified for correct leftward
  motion and clean 0 → 639 wraparound.

Step 4 is what caught all three wrong hypotheses above. Step 3 is what made it
safe to be aggressive.

---

## Constraint-side work (PnR, not RTL)

Included for completeness — this sits alongside the RTL work rather than
within it.

| Constraint | Default | Used | Rationale |
|---|---|---|---|
| `PL_TARGET_DENSITY_PCT` | 60 | 80 | 60 was unsatisfiable at this utilization (`GPL-0302`) |
| `CLOCK_PERIOD` | 20 ns | 40 ns | Design runs at 25.175 MHz; 20 ns over-constrained it 2× |
| `PL_RESIZER_HOLD_SLACK_MARGIN` | 0.1 | 0.05 | 43 hold buffers were being inserted to gain 0.129 ns when the actual violation was 0.029 ns |

The hold-margin reduction was the only change carrying genuine silicon risk,
since hold violations are fatal rather than merely slow. It was validated by
signoff STA reporting positive hold slack across all 12 PVT corners, tightest
at +58 ps on the fast corner (`ff_n40C_1v95`) — which is where hold is
theoretically worst.

A useful distinction surfaced here: **hold timing is frequency-independent**.
Relaxing `CLOCK_PERIOD` fixed setup entirely (`RSZ-0098 No setup violations
found`) but could not touch the hold buffers, because hold is a race between
data-path delay and clock skew, not a function of the clock period.

---

## Reproducing the measurements

```bash
scripts/synth_area.sh src/<module>.sv [top_module_name]
```

Runs a standalone, flattened synthesis of one module against the sky130
`tt_025C_1v80` liberty inside the LibreLane container, and prints the
`stat -liberty` report. Accepts paths relative to either the current directory
or the repo root.
