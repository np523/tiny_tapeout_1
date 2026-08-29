# Design Spec — Two-Player Pong + Discrete Rally Speed-Up

Grounded in the actual `robojan/tt04-pong` source. This is the concrete plan the handoff
asked for: what the base gives us, what changes, and the matching cocotb test plan.
Companion to [handoff.md](handoff.md).

## Base design (robojan/tt04-pong) — as-is facts

- Complete **two-player vertical Pong**, 1×1 tile, silicon-proven on TT04. Verilog.
- **Two-player already exists** — nothing to build. Two independent `paddle_painter`
  instances: P2 top (`PADDLE_Y=16`), P1 bottom (`PADDLE_Y=456`); independent `_x`
  registers, independent lives. 3 buttons each on `ui_in[2:7]`. `ui_in[0]`/`ui_in[1]` free.
- Docs call it "breakout" and mention blocks — that text is copy-pasted from the author's
  *separate* breakout repo. **This repo has no brick logic.** Ignore the block wording.
- Module map:
  - `vga_timing.v` — 640×480 timing; `hpos/vpos/active/line_pulse/frame_pulse`.
  - `*_painter.v` (border, ball, paddle×2, lives×2) — given `(hpos,vpos)`+state, emit
    `draw_en`+color for their element.
  - `video_mux.v` — fixed priority: border > paddles > ball > lives > background.
  - `game_logic.v` — ball fixed-point physics, paddle positions, lives, game state.
  - `sound_gen.v`, `synchronizer.v` — beeps; 2-FF input sync.

### Collision architecture (the reason changes are low-risk)

Collision is **painter overlap**, not geometry math:
```verilog
wire wall_collision   = draw_border   && draw_ball;
wire p1_paddle_collision = draw_p1_paddle && draw_ball;
```
The ball painter separately reports which edge of the *ball's own bounding box* a pixel is
on (`in_ball_top/left/bottom/right`), independent of what was hit. `game_logic` latches
those edge bits whenever `collision` fires during the frame, then a truth table flips
`vx`/`vy` at `frame_pulse`. Adding a new bounce source = OR a term into `collision`; the
physics resolution is untouched.

### Key numbers (bound the safe design)

- Ball moves `velocity/2` px per frame — `ball_state_*` is half-pixel fixed point,
  `ball_x = ball_state_x[10:1]`.
- Velocity is **signed 4-bit** → range −8..+7 → **max 3.5 px/frame**.
- Paddles and border are **8 px thick**; ball is 5 px.
- **Safety-by-construction:** 3.5 px/frame < 8 px thickness ⇒ the ball cannot tunnel
  through a paddle/border **as long as the velocity registers are never widened past
  4-bit signed.** This is the single invariant that keeps speed-up provably bug-free.

## Change 1 — Verilog → SystemVerilog cleanup (mechanical, do first, after sim is green)

Syntax only, verified against the original as golden reference. `reg`/`wire` → `logic`;
`always @(posedge clk ...)` → `always_ff`; `always @(*)` → `always_comb`. No interfaces, no
behavioral changes. iverilog needs `-g2012`; Yosys/LibreLane accept it. Any diff in sim
output after this pass is unambiguously a translation bug.

## Change 2 — Discrete rally speed-up (the novel feature)

Ball speeds up in **discrete, capped levels** as a rally continues; resets on a point.
Lives entirely in `game_logic.v` — no new module, no change to the painter/mux/collision
layers.

### New state (all bounded)
- `reg [1:0] speed_level;` — 0..3 (or 0..N, small).
- Increment on each **paddle** hit (not wall hits), saturating at max level.
- Reset to 0 on `ball_out_of_bounds` / new serve (alongside the existing velocity reset).

### Velocity mapping (combinational LUT, no multiplier)
Extend the existing `next_velocity` block:
- Paddle hit: `next_velocity_x` = LUT(`latched_paddle_segment`, `speed_level`);
  `next_velocity_y` = signed-negate of current `velocity_y` but with magnitude
  `VY_MAG[speed_level]` (i.e. `velocity_y < 0 ? +VY_MAG : −VY_MAG`).
- Wall bounce: unchanged — negates the component, preserving the (already-elevated)
  magnitude.
- **Hard cap:** choose LUT values so every reachable `|vx|,|vy| ≤ 6` (≤3 px/frame, inside
  the 4-bit safe envelope with margin). Never widen the velocity regs.

### Why this meets the no-bugs bar
- State space is *finite and small*: `level × segment × vy-sign` — fully enumerable.
- No multiplier (LUT/shift), no unbounded accumulation, no per-frame clamp needed.
- Tunneling impossible by the 4-bit invariant above.

## Change 3 (optional, free polish) — retro video effects

Pixel-stage only, in `video_mux.v` — **cannot** affect gameplay/collision.
- **Scanline darkening:** `if (vpos[0]) out <= out >> 1;` (halve alt lines).
- **Color-cycled ball:** rotate ball color through a small palette by a frame counter.
Include only if time allows; they add bring-up demo pop with zero physics risk.

## Pin / area / timing notes

- Pins: base uses `ui_in[2:7]` (6 buttons). Speed-up needs **no new inputs**. `ui_in[0]`,
  `ui_in[1]` remain free (future mode select). VGA uses all `uo_out`; `uio` carries
  hblank/vblank/sound as in base.
- Area/timing: speed-up adds a 2-bit reg + a small combinational LUT inside logic already
  clocked at pixel rate — negligible area, no new timing path. Buy 2–3 tiles per handoff.

## cocotb test plan

**Golden model first** (Python, bit-accurate): reimplement ball physics + speed-up LUT +
level state machine. Compare RTL `ball_x/ball_y/velocity/speed_level` every frame over
randomized play. Mirrors the reference-first workflow.

Directed / property tests:
1. **Level machine:** increments exactly once per paddle hit; saturates at max; resets to 0
   on point loss and on new serve. Velocity resets to INITIAL on serve.
2. **No-tunneling (the safety test):** force `speed_level = max`, launch ball at max speed
   straight at each paddle and each border from each direction → assert the collision is
   always registered and the ball reverses (never passes through). Repeat at paddle x
   limits.
3. **Angle mapping:** for each `speed_level`, each paddle `segment` produces the expected
   `(vx,vy)` from the LUT; sign of `vy` always flips on paddle hit.
4. **Range invariant (exhaustive):** enumerate `level × segment × vy-sign`; assert every
   resulting `|vx|,|vy| ≤ cap` — proves the 4-bit safety envelope holds by test, not just
   by argument.
5. **Corner / multi-edge:** ball into a wall corner (multiple edge bits latch same frame) at
   max speed → bounce is well-defined, ball not stuck, no double-bounce.
6. **Regression vs base:** with speed-up disabled (level forced 0), behavior is bit-identical
   to the original — protects against the SV-cleanup pass and the feature both.

Reuse these near-as-is as the post-silicon bring-up script via TT's HIL firmware SDK.

## Roadmap (preserves the "submittable every week" property)

1. Port unmodified robojan/tt04-pong into this repo; cocotb sim green; local hardening runs.
   *(Submittable checkpoint on its own — but it's someone else's design; not yet ours.)*
2. SV cleanup pass, re-verified bit-identical against original. *(Now it's our source.)*
3. Add discrete rally speed-up + golden model + tests 1–6. *(Now it's distinctly ours.)*
4. Optional retro effects if time allows.
5. Hardening iteration (OpenLane), post-hardening re-verify, docs/`info.yaml`, submit.
