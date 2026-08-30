# RTL implementation plan

Locked scope, implementation order, and exact per-feature RTL changes, now that the DV
harness (`test/test.py`, see [dv-plan.md](dv-plan.md)) is built and validated against the
unmodified base. Companion to [design-spec.md](design-spec.md) and
[module-reference.md](module-reference.md).

## Locked scope

- **Discrete rally speed-up** — ball speeds up in capped levels across a rally.
- **AI opponent** — 1-bit mode select; AI controls P2 (top), P1 (bottom) stays human.
- **Visual effects**, all game-state-driven (no new input pins, no timers):
  - Scanline darkening (always on).
  - Color-cycling ball/paddles (live/unlatched: active whenever either player is at
    exactly 1 life).
  - Background: starfield (default) → XOR/plasma (latched, on a score that isn't
    game-over) → copper bars (latched, on game-over). Starfield also covers the very
    first pre-game wait (no score has happened yet, so plasma hasn't triggered).
- **Verilog → SystemVerilog cleanup** — mechanical syntax pass, no behavior change.
- **Clock gating on the AI logic when in 2P mode** — PD-phase exploration, not a
  functional RTL feature; the RTL just needs to expose a clean enable signal for it.

## Area constraint: one tile only

Locked decision, tighter than the original handoff's "buy 2-3 tiles for headroom" — this
project stays inside a single TT tile (~167×108µm). This is the main reason hardening now
happens **after every step, not just once at the end**: if a step doesn't fit, the fix is
to cut that step (per the project's own "cut features before cutting verification" rule)
while it's still cheap to cut, not discover it after the full feature set is already
built and verified. `src/config.json` already carries the density/clock-period knobs
(`PL_TARGET_DENSITY_PCT`, `CLOCK_PERIOD`, resizer margins) this will lean on.

## Implementation order and why

1. **SV cleanup first.** Mechanical, zero behavioral risk, and doing it before any
   feature branches means there's exactly one clean diff to eyeball (syntax only), not a
   diff tangled up with real logic changes. Bonus: `always_comb` forces blocking
   assignment, which removes the need for the `-Wno-COMBDLY` Verilator suppression
   already sitting in `test/Makefile` — a nice concrete confirmation the cleanup did what
   it was supposed to. **First hardening run happens here** — establishes the true
   baseline area/utilization for the unmodified design in this exact flow, before any
   feature adds a single gate.
2. **Rally speed-up.** Smallest, most isolated change (one file, one existing hook
   point), and the DV harness already has the golden-model muscle memory for `game_logic`
   changes from building the base tests. **Harden, compare area delta against the Step 1
   baseline.**
3. **AI opponent + mode select.** Self-contained new module, touches the top-level pin
   map (one new input bit) and a mux in front of `game_logic`'s P2 button inputs -
   doesn't touch `game_logic` internals at all. **Harden, compare delta.** This is the
   step most worth watching closely for area — it's the biggest single functional
   addition (a new module, not just a re-keyed LUT).
4. **Visual effects state machine.** Depends on stable `game_state`/lives semantics from
   steps 2-3 being settled (speed-up doesn't change those semantics, but doing this last
   means the state machine is built once against a final, not-still-changing base). Three
   background generators (starfield/plasma/copper) is real added area too - **harden,
   compare delta**, and this is the step most likely to need trimming (e.g. drop to two
   background effects, or a smaller starfield count) if the tile is tight by this point.
5. **Clock gating** — a hardening-phase (LibreLane) exploration once step 3's RTL exists,
   evaluated in the Step 3 and final hardening passes rather than as its own RTL step.

Every step ends with (a) a full re-run of the three existing DV tests, extended as noted
per step, and (b) a hardening run (`tt_tool.py --harden` or equivalent) checked for: does
it still fit in one tile, and did timing/DRC/LVS stay clean. Both gates before moving to
the next step - a functional pass with no area/timing check is not a complete checkpoint
here, given the one-tile constraint.

## Step 1 — SV cleanup

Mechanical only, across all 11 files: `reg`/`wire` → `logic`; `always @(posedge clk or
negedge nRst)` → `always_ff @(posedge clk or negedge nRst)`; `always @(*)` → `always_comb`.
No interfaces, no behavioral change. Verified by re-running `test_timing_and_capture`,
`test_serve_and_ball_motion`, `test_biased_random_play` bit-identical to their current
passing results - any difference is unambiguously a translation bug.

After this lands: remove `-Wno-COMBDLY` from `test/Makefile` and confirm the build still
compiles clean (proves the `always_comb` conversion actually fixed the underlying
blocking/non-blocking issue, not just silenced the warning).

## Step 2 — Discrete rally speed-up

**New state** (`game_logic.v` / `.sv`): `logic [1:0] speed_level;` - increments on each
**paddle** hit (not wall hits), saturating at max (3); resets to 0 on serve/out-of-bounds,
alongside the existing velocity reset.

**Changed logic**: the existing `case(latched_paddle_segment)` block that sets
`next_velocity_x` gets re-keyed on `(speed_level, latched_paddle_segment)` instead of
segment alone - a small LUT (still no multiplier - table lookup or shift). `next_velocity_y`'s
magnitude scales the same way (currently just sign-flipped; make the magnitude
`VY_MAG[speed_level]`).

**Hard invariant, unchanged from the original design-spec**: every reachable `|vx|,|vy|`
must stay `<=7` (inside the 4-bit-signed range) - this is what keeps the ball
tunneling-safe through paddles/border (8px thick, ball moves `<=3.5px/frame` at the
range's edge). Never widen the velocity registers to accommodate a higher speed level.

**DV extension**:
- `ReferenceModel` gets matching `speed_level` state + re-keyed LUT.
- `velocity_within_safety_bounds()` (currently a stub) becomes a real per-frame invariant
  check - already wired into `Scoreboard.check_invariants()`, so no new plumbing needed,
  just real logic.
- `Coverage` gets `speed_level_reached[0..3]` bins.
- New directed check: force `speed_level` to max, verify every paddle-hit velocity stays
  within the safe range (the coverage-bin equivalent of the original no-tunneling test
  from design-spec.md).

## Step 3 — AI opponent + mode select

**New pin**: `ui_in[0]` = mode select. `0` = two human players (today's behavior,
unchanged). `1` = P1 human, P2 AI-controlled.

**New module**: `ai_paddle` - combinational ball-tracking decision (the same
`next_paddle_move` algorithm already used as the DV harness's biased-random-driver
stimulus policy, and the one found in the Project F FPGA Pong reference): compare
`ball_x` to the AI paddle's center, output `ai_left`/`ai_right`. No new pins needed to
feed it - `ball_x` and `p2_paddle_x` are already routed inside `pong.v`.

**Mux, in `pong.v`, in front of `game_logic`'s P2 button inputs**:
```verilog
wire mode_select = ui_in[0];
wire p2_left_final  = mode_select ? ai_left  : p2_btn_left;
wire p2_right_final = mode_select ? ai_right : p2_btn_right;
```
`game_logic.v` itself is untouched - this is a drop-in replacement for P2's input
*source*, exactly the low-risk hook point identified back in the original module
walkthrough.

**Clock gating hook**: `ai_paddle`'s own registers (if it ends up needing any beyond
pure combinational logic) should be gated by `mode_select` - e.g.
`if (mode_select) ai_state <= next_ai_state;` - a clean enable pattern that's amenable to
either manual clock-gate-cell instantiation or automatic inference during LibreLane's
synthesis optimization. Decide manual-vs-automatic at hardening time (Step 5), not now.

**DV extension**:
- `PaddleDriver`/test flow gets a `mode_select` bit to drive.
- `ReferenceModel.step_frame()` gains a `mode_select` parameter: when set, P2's
  left/right args are ignored and replaced by `next_paddle_move(p2_paddle_x, ball_x,
  PADDLE_WIDTH)` internally - literally the same function already imported, just called
  from inside the model instead of from the test's stimulus layer.
- New tests: 1P mode reaches real paddle-hit events without any P2 button driving at all
  (proves the AI is actually moving the paddle); 2P mode behaves bit-identical to today
  when `mode_select=0` (regression check that the mux didn't disturb the human path).

## Step 4 — Visual effects state machine

**Scanline darkening** (pixel-stage, in `video_mux.v`'s output or a thin wrapper):
```verilog
assign out_final = vpos[0] ? (out >> 1) : out;
```

**Color-cycling ball/paddles** (live, unlatched level check):
```verilog
wire tension = (p1_lives == 2'd1) || (p2_lives == 2'd1);
```
When `tension` is high, `ball_color`/`p1_paddle_color`/`p2_paddle_color` index into a
small palette by a frame counter instead of their fixed constants; otherwise unchanged
(green ball, white paddles, as today).

**Background selection - two new 1-bit latches**, set/cleared off signals `game_logic.v`
already computes:
```verilog
// life_lost fires the same frame ball_out_of_bounds triggers in STATE_PLAYING
wire life_lost_event = ball_out_of_bounds && (game_state == STATE_PLAYING);

always @(posedge clk or negedge nRst) begin
    if (!nRst) begin
        just_scored <= 0;
        game_over_flag <= 0;
    end else if (frame_pulse) begin
        if (life_lost_event && end_of_game) begin
            game_over_flag <= 1;
            just_scored <= 0;
        end else if (life_lost_event) begin  // scored, not game over
            just_scored <= 1;
        end else if (game_state == STATE_START && (p1_btn_action || p2_btn_action)) begin
            // next serve clears both - "until game starts again"
            just_scored <= 0;
            game_over_flag <= 0;
        end
    end
end

wire [1:0] bg_select = game_over_flag ? COPPER_BARS :
                        just_scored   ? PLASMA :
                                        STARFIELD;
```
`end_of_game` already exists as an internal wire in `game_logic.v` (currently only used
to decide the lives reset-to-3 behavior) - needs to be exposed as an output for this mux
to consume, or the background-effects module needs to be instantiated inside
`game_logic.v` itself rather than alongside it. Decide placement when writing the actual
diff - functionally equivalent either way.

**Three background generator sub-blocks**, wired into `video_mux.v`'s currently-hardcoded
`background = 6'b000000` input:
- **Starfield**: ~24 star registers, each `(x, y)` with `x` decrementing/wrapping once
  per frame, `y` fixed from an LFSR seed at reset. Draws a lit pixel where
  `(hpos,vpos)==(star.x,star.y)` for any star.
- **XOR/plasma**: `LUT[(hpos[3:0] ^ vpos[3:0]) + frame_counter[3:0]]`, small 16-entry
  palette.
- **Copper bars**: `LUT[(vpos[6:3]) + frame_counter[?:?]]` (~8-entry palette, band height
  8px), matches the earlier preview artifact's approach.

All three are pixel-stage only, driven purely by `(hpos, vpos, frame_counter)` plus the
two latch bits - **structurally incapable of affecting collision/gameplay**, same
guarantee as the original design-spec's reasoning for why visual effects are low-risk.

**DV extension**:
- `ReferenceModel` gains `just_scored`/`game_over_flag` state, updated in `step_frame()`
  using the same trigger logic as the RTL above (mirrored, not geometrically
  re-derived - these are simple latches, not hand-written collision logic, so bit-exact
  replication is the right call, same reasoning already applied to out-of-bounds/limits).
- `render_frame()`/`color_at()` gain the three background-pattern functions (can port
  directly from the earlier preview artifact's JS implementation - same math, Python) and
  the tension-gated color-cycling logic.
- New `Coverage` bins: `background_starfield_shown`, `background_plasma_shown`,
  `background_copper_shown`, `tension_active`.
- New directed scenario: drive a life-lost event that is NOT game-over, confirm plasma
  latches and clears on next serve; drive a genuine game-over, confirm copper bars
  latches and clears on next serve; force a player to 1 life, confirm color-cycling
  activates.

## Step 5 — Clock gating (PD-phase, not RTL-functional)

Once Step 3's `ai_paddle` module exists with a clear `mode_select`-gated enable: at
hardening time, either let LibreLane/Yosys infer clock gating automatically from the
enable pattern (a standard synthesis optimization), or manually instantiate a Sky130
clock-gate cell (e.g. `sky130_fd_sc_hd__dlclkp`) keyed by `mode_select`. Compare area/
power reports both ways if time allows - genuinely useful, bounded PD-stage learning,
doesn't gate anything else in the plan.

## Pin budget after all steps

- `ui_in[0]` - mode select (1P AI / 2P human) - **new**.
- `ui_in[1]` - still free.
- `ui_in[2:4]` - P2 left/right/select (select unused in 1P mode, AI doesn't serve for P2).
- `ui_in[5:7]` - P1 left/right/select - unchanged.
- `uo_out[7:0]` - VGA, unchanged.
- `uio_out[1:3]` - hblank/vblank/sound - unchanged (sound not being cut per earlier
  discussion; area headroom was never actually tight enough to require it).

## Verification checkpoint property

Same principle as the original project timeline: after each step, all three existing DV
tests must pass before moving to the next step, and the previous step's tests must still
pass unchanged (regression) - a genuine "submittable state at every step" property,
mirrored from the project-level plan down to the RTL-step level. **Now extended to area:**
a step isn't done until it also hardens cleanly inside the one-tile budget - a functional
pass alone no longer counts as a complete checkpoint, since the whole point of hardening
every step (rather than once at the end) is catching a budget problem while the step that
caused it is still the last thing changed, not buried under three more steps of RTL.
