# Tiny Tapeout Pong — Project Context

This document is background for a Claude Code session. The goal of that session is to
clone/review a reference Pong repo and turn it into a concrete, scoped spec for my own
Tiny Tapeout submission. Read this fully before proposing a spec — the constraints here
(especially time budget and "no bugs allowed") should shape every recommendation.

## What Tiny Tapeout is, and why I'm doing this

Tiny Tapeout is a shared-die educational ASIC program: many people's small digital
designs get muxed onto one chip and fabricated together (Sky130 process). I signed up
for the tier that includes getting the physical chip back, which also means I own
post-silicon bring-up myself (no validation is done for me).

- **Shuttle**: TTSKY26c
- **Submission deadline**: September 7, 2026 (hard close)
- **Target internal deadline**: September 3–4, 2026 (leaving ~3 days buffer for CI/precheck
  failures before the real deadline — first-pass hardening/precheck failures are normal,
  not a sign something is wrong)
- **Two intro classes**: in the week of July 14–20, 2026

## My actual goal with this project

The specific value I'm after is the part of the chip flow I *don't* already get from my
day job: physical design (RTL → GDS) and post-silicon bring-up on real fabricated
silicon. I already do RTL design, verification (UVM, CDC, fault injection), and FPGA
emulation professionally — Tiny Tapeout's unique value to me is closing the PD +
bring-up gap, not re-teaching me RTL or verification.

Resume/portfolio framing: "took a chip through design, verification, PD, tapeout, and
post-silicon validation" — a complete-flow story, not a partial one.

## Team size decision (already made)

Solo, or at most one collaborator working as a genuine peer (not role-siloed). I
explicitly rejected a large team with divided roles (design/verif/PD split across
~5 people) because:
- It dilutes the "I own the full flow" story that's the actual point of doing this.
- Coordination overhead isn't worth it given the real time budget (below).

## Time budget — please treat this as a hard constraint, not a soft target

- Full-time day job (~8hr days), ~2–3 hrs spare on weeknights total (not just for this).
- Weekends are nominally free but often have ~5hr commitments.
- **Realistic sustainable budget: ~8–11 hours/week**, in sessions of roughly 1–2 hours,
  2–3 times per week. Not large daily blocks.
- Other priorities competing for the same hours, in priority order: (1) BitByBit /
  Packetflow project — **highest priority, not to be displaced by this**, (2) day job,
  (3) this Tiny Tapeout project, (4) mesh ear project — lowest priority. Job applications
  will start opening in a few weeks, which will further compress available time in the
  back half of this project.
- Implication: front-load anything novel/risky (toolchain bring-up, HDL decision) into
  the first 2 weeks while bandwidth is highest. Later weeks should be small, well-defined,
  chunkable tasks (writing individual tests, iterating hardening) — not open-ended
  exploration.

## Non-negotiable quality bar

**I will not accept a design with bugs.** This is a real chip; there's no re-run. This is
the single biggest factor behind every scoping decision below — every choice favors
provably-correct, exhaustively-testable, low-novelty-risk logic over anything clever or
compute-heavy. This also means: verification and hardening time must never be cut to make
room for extra features. If time runs short, cut features (two-player, retro effects)
before cutting verification depth or hardening iteration time.

## Project decision: two-player Pong, adapted from an existing reference

Rejected alternatives and why (for context on my reasoning, not to revisit):
- **FPGA-as-accelerator link**: interesting but adds real interconnect/CDC risk and
  scope for uncertain payoff; dropped once I realized the on-board RP2040 gives a
  self-contained host for free.
- **Fractal visualiser (Mandelbrot)**: rejected primarily on visual-payoff grounds — the
  time-per-pixel budget on Tiny Tapeout (~66.5MHz project clock max, no framebuffer)
  forces either very few iterations or very chunky blocks; not worth the multiplier/
  timing-closure risk for a mediocre-looking result given the "no bugs" bar.
  A serial fixed-point complex MAC is real design risk I don't want to carry here.
- **Flappy Bird**: looked simpler at first glance but the continuous gravity-driven
  motion + scrolling/regenerating obstacle field is actually *more* state and edge
  cases than Pong, not less.
- **Snake**: rejected — growing-body state and self-collision are meaningfully harder
  to verify exhaustively than Pong/Breakout.
- **Breakout**: genuinely viable (silicon-proven reference exists — see below), but
  two-player Pong was chosen as slightly lower risk given the brick-grid state adds
  more combinations on top of the same ball/paddle physics.
- **Chisel** (used by one reference repo): decided against learning it for this project.
  Rationale: this project's value is in verif/PD/bring-up, not the source HDL; I'm
  already fluent in SystemVerilog; spending scarce hours decoding an unfamiliar
  generator framework under this timeline is the wrong tradeoff. (Chisel remains
  interesting for other, lower-stakes contexts — not in scope here.)

### Reference repos identified (start here)

- `tjarker/tiny-tapeout-pong` — Chisel, submitted TT06, VGA output, ball, paddles, score
  display, **autopilot mode for both paddles**. Not being adapted directly (Chisel), but
  worth reading for design structure — the existence of independent autopilot per paddle
  suggests two paddles may already exist as independently-controllable state, which
  should be checked before assuming two-player needs to be built from scratch.
- Tiny Tapeout TT04 chip datasheet / project repo (`TinyTapeout/tinytapeout-04`) lists
  both **"Pong" [project 178]** and **"Tiny Breakout" [project 98]** — silicon-proven,
  Verilog. **This is the preferred starting point** since it avoids the Chisel→SV
  translation question entirely.
- Official tool: **VGA Playground** (`vga-playground.com`) — browser-based Verilog + VGA
  simulator (Verilator-backed), supports loading any TT-structured repo directly via
  `?repo=<github-url>`. Use this first to see the reference run before touching code.

### Decided approach

1. Fork/adapt the **Verilog** Pong reference (not Chisel).
2. Get the **unmodified** reference running end-to-end through my own repo/toolchain
   first (sim + local hardening), with zero design changes — this validates the toolchain
   itself before any design risk is introduced, and is a legitimate fallback checkpoint on
   its own if time runs out later.
3. Only after that's confirmed working: do a mechanical Verilog → SystemVerilog cleanup
   pass (`logic` instead of `reg`/`wire`, `always_ff`/`always_comb`, etc.), verified against
   the original as a golden reference — syntax cleanup only, not a rewrite, done *after*
   correctness is established so any bug found during this pass is unambiguously a
   translation bug.
4. Then add the scoped feature list (below).
5. First 15 minutes of actual repo work: check whether two-player is already supported
   (look for two independent paddle-position registers, and how many `ui_in` bits are
   already wired to paddle control vs. unused/mode-select in `info.yaml`/top-level ports).
   If autopilot-per-paddle implies independent paddle state already exists, two-player may
   be a bit-mapping change, not new logic.

### Scoped feature list (this is the ceiling — do not add beyond this without deliberately re-scoping)

- **Two-player controls**: up/down per paddle = 4 bits total, fits easily in the 8
  available `ui_in` pins (VGA output via the Tiny VGA Pmod consumes all 8 `uo_out` pins:
  R1/G1/B1/vsync/R0/G0/B0/hsync). Optionally, paddle input can be driven from a keyboard
  script over the on-board RP2040's USB MicroPython REPL instead of physical
  switches/buttons — no new hardware needed, and the same input-driving code can double
  as part of the test/bring-up harness.
- **Retro visual effects** (all deliberately chosen to be free of multipliers and to only
  ever execute when the VGA beam is in "empty space," so they cannot introduce
  gameplay/collision bugs):
  - **Scanline darkening** (always include — essentially free): halve brightness on
    alternating lines (`if (y[0]) color = color >> 1`) for a CRT feel.
  - **One "real" background effect**, pick one:
    - *Copper bars*: background color indexed from a small palette by upper bits of `y`,
      animated by adding a slow frame counter before lookup.
    - *XOR/plasma pattern*: background color from `LUT[x[3:0] ^ y[3:0] + frame_counter]`.
    - *Starfield*: ~16–32 stars, each a single x-register decrementing/wrapping per frame,
      fixed y from LFSR at reset.
  - **Color-cycling on ball/paddles**: rotate through a small palette indexed by frame
    counter instead of a static color — cheap, reuses the existing color output stage.
- **Explicitly out of scope**: framebuffer/memory macro, any multiplier-based effect,
  custom RP2040 firmware beyond the optional keyboard-paddle bridge, external FPGA link,
  brick/grid state (that's the Breakout path, not this one), anything not on this list.

## Hardware constraints to keep in mind

- Project clock: RP2040-generated, tunable 1 Hz – 66.5 MHz; VGA needs ~25 MHz pixel clock,
  comfortably inside range. Real designs tend to stay well under the ceiling since TT pad
  drivers are on the soft side.
- I/O: 24 pins total — `ui_in[7:0]`, `uo_out[7:0]`, `uio[7:0]` (bidirectional). VGA (Tiny
  VGA Pmod) uses all of `uo_out`. Paddle controls fit in `ui_in`.
- Area: buy 2–3 tiles rather than optimizing to fit exactly 1 — TT tile area is cheap and
  this avoids late-stage squeezing if the design ends up slightly bigger than expected
  (two-player scoreboard + effect logic will want the headroom).
- Demo board (for context, not necessarily used directly): RP2040 MCU, USB-C, 8 DIP
  switches, one 7-segment digit, status LEDs, PMOD headers for `ui_in`/`uo_out`/`uio`
  individually. Need to separately source a **Tiny VGA Pmod** for actual monitor output.

## Verification approach

- cocotb-based, consistent with my existing verification background.
- Build/reuse a golden reference model before modifying anything (mirrors how I already
  work — bit-accurate reference first, RTL checked against it).
- Exhaustively test the bounded state space: wall bounces, paddle-edge collisions,
  simultaneous events, both paddles' boundary conditions. The whole point of choosing
  Pong over more complex options was that this state space is small enough to actually
  achieve this.
- Reuse cocotb tests as the post-silicon bring-up script later, via TT's hardware-in-the-
  loop firmware SDK (tests written now should be usable near-as-is against real silicon
  once it arrives).

## Rough timeline (flex as needed, but preserve the checkpoint property below)

| Week | Dates (2026) | Focus |
|---|---|---|
| 1 | Jul 14–20 | Two classes. Load reference into VGA Playground. Confirm Verilog fork decision. Check existing two-player support. |
| 2 | Jul 21–27 | Unmodified reference running end-to-end through own repo/toolchain (sim + local hardening), no design changes yet. |
| 3 | Jul 28–Aug 3 | Mechanical Verilog → SystemVerilog cleanup pass, re-verified against original. |
| 4 | Aug 4–10 | Add two-player controls + one retro background effect. |
| 5 | Aug 11–17 | Full verification pass: directed + randomized cocotb tests, boundary cases. |
| 6 | Aug 18–24 | Local hardening iteration (OpenLane). Budget real time — first-pass congestion/timing/DRC issues are normal. |
| 7 | Aug 25–31 | Post-hardening re-verification if time allows, polish `info.yaml`/docs. |
| 8 | Sep 1–4 | Submit (internal deadline, ~3 days before the real Sept 7 close). |

**Important property to preserve**: at the end of every week, there should be a
submittable state, even if later weeks slip. Week 2 alone (unmodified reference, own
verif/PD) is already a complete, honest, submittable tapeout on its own. Week 4 onward is
where it becomes distinctly mine. If time gets eaten by higher-priority work, the project
should degrade gracefully along this table rather than collapse.

## What I want from this Claude Code session

1. Clone the chosen reference repo (TT04 Verilog Pong, `tinytapeout-04` project 178 —
   confirm exact path/module first) and walk through its structure with me.
2. Help verify: does two-player paddle control already exist as independent state?
3. Produce a concrete, file-level spec for the changes in the "scoped feature list" above
   — what modules/signals need to change, where the retro effect logic should live
   (should not touch ball/paddle collision logic at all), and a matching cocotb test plan
   — grounded in what's actually in the repo, not abstract.
4. Flag early if anything in the scoped feature list looks riskier than expected once
   the actual code is visible (e.g. if `uio` pin allocation is trickier than assumed) —
   surface it rather than quietly working around it.