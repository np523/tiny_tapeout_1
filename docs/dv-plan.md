# DV plan — class/method/data spec

What we've agreed on for `test/test.py`, broken down to class/method/data-member
granularity so it can be implemented piece by piece. This is the contract each piece
must satisfy — implement against this, then bring it back for review.

## Design decisions locked in this pass

- **Top-level black-box only.** cocotb drives/observes `tt_um_robojan_pong_top`'s pins —
  `uo_out[7:0]`, not separate r/g/b/hsync/vsync signals (those only exist as internal
  wires inside `pong.v`). Every consumer decodes through one shared helper
  (`decode_uo_out`) so the Tiny VGA Pmod bit mapping lives in exactly one place.
- **`ReferenceModel`'s collision resolution is reimplemented geometrically**
  (bounding-box/shape overlap), **not ported from `game_logic.v`'s edge-latch + OR-table.**
  This is deliberate: porting that OR-list would let a mistake in it hide on both sides of
  the comparison. An independently-derived geometric model is what actually gives the
  corner-case coverage bins (below) teeth.
- **Two-tier checking**: cheap per-frame numeric invariant checks (velocity bounds, etc.)
  run every frame; expensive full-frame PNG diffing only runs at checkpoints (after a
  confirmed collision/score event, every N frames during random phases, once per directed
  scenario) — not every single frame.
- **Stimulus is biased-random, not uniform-random**: the default paddle policy tracks the
  ball (reusing the same simple algorithm scoped for the real AI opponent) with a
  deviation probability layered on top, so simulation time concentrates on actual
  collisions rather than mostly missing the ball.
- **Coverage bins replace "run enough and hope"** as the actual closure criterion.

## Helper functions (module-level, no class)

| Function | Signature | Does |
|---|---|---|
| `decode_uo_out` | `(dut) -> (hsync: bool, vsync: bool, r: int, g: int, b: int)` | Decodes `dut.uo_out.value` using the Tiny VGA Pmod bit order: hsync=bit7, vsync=bit3, R1/R0=bits0/4, G1/G0=bits1/5, B1/B0=bits2/6. r/g/b returned as 2-bit ints (0–3). Single source of truth — `vga_checker` and `Display` both call this, never re-derive it. |
| `quantize_to_byte` | `(level: int) -> int` | 2-bit level (0–3) → 0–255 byte (`level * 85`), for PNG output. |
| `save_png` | `(array: np.ndarray, path: str) -> None` | Thin wrapper over `PIL.Image.fromarray(...).save(...)`. |
| `expected_hpos_vpos` | `(cycle_count: int) -> (hpos: int, vpos: int)` | Closed-form VESA 640×480@60 position from a free-running cycle counter (800 clocks/line, 525 lines/frame) — independently derived, never read from the DUT. Used by both `vga_checker` and `Display`. |
| `next_paddle_move` | `(paddle_x: int, ball_x: int, paddle_width: int, speed: int, left_limit: int, right_limit: int) -> Literal["left","right","none"]` | Pure ball-tracking decision function: move toward `ball_x`, capped at `speed`, clamped at limits. Used both as the default biased-random stimulus policy and as the reference behavior if/when the real AI opponent gets scoped into RTL. |

## `vga_checker(dut)` — background coroutine, not a class

Tracks: local `hpos`/`vpos` via `expected_hpos_vpos` and a cycle counter; last-seen
hsync/vsync for edge detection. Every `RisingEdge(dut.clk)` + `ReadOnly()`: decode pins via
`decode_uo_out`, assert hsync/vsync transitions land exactly where the VESA spec says they
should for the current cycle count. On violation: append `(sim_time, description)` to the
shared `errors` list — **does not raise**, since exceptions inside a `start_soon` task
aren't reliably surfaced by the regression manager; the main test explicitly checks
`errors` at the end (and should also poll it periodically for fail-fast, not just at the
very end). Needs a **watchdog**: if waiting on an expected edge that never arrives, fail
with a clear message instead of hanging to the simulator's own timeout.

## `class ReferenceModel` — the golden game-state model

**Data:**
- `ball_state_x`, `ball_state_y: int` — half-pixel signed position (mirrors RTL's
  12-bit/11-bit signed regs)
- `velocity_x`, `velocity_y: int` — signed, range −8..7 (mirrors RTL's 4-bit signed regs)
- `p1_paddle_x`, `p2_paddle_x: int` — left-edge position, 0–639 range
- `p1_lives`, `p2_lives: int` — 0–3
- `game_state: Literal["START","PLAYING"]`
- Constants: `BORDER_WIDTH=8`, `PADDLE_WIDTH=48`, `PADDLE_SEGMENT_WIDTH=8`,
  `PADDLE_NUM_SEGMENTS=6`, `PADDLE_HEIGHT=8`, `PADDLE_Y_P1=456`, `PADDLE_Y_P2=16`,
  `PADDLE_SPEED=1`, `SCREEN_W=640`, `SCREEN_H=480`, plus `INITIAL_BALL_X/Y`,
  `INITIAL_VEL_X/Y` matching `pong.v`'s parameter overrides (not `game_logic.v`'s own
  defaults, which get overridden)
- `BALL_SHAPE`: precomputed 5×5 boolean mask matching the four-lobe diamond in
  `ball_painter.v`'s ASCII art comment

**Methods:**
- `reset() -> None` — power-on-reset values (ball at INITIAL_X/Y, paddles centered,
  lives=3 each, state=START)
- `step_frame(p1_left, p1_right, p1_select, p2_left, p2_right, p2_select) -> list[Event]` —
  advance one frame: FSM transition, geometric collision resolution (ball shape vs.
  border/paddle rects), velocity update, position update, paddle movement + clamping,
  lives/out-of-bounds handling. Returns the events that occurred this frame (which
  paddle/segment hit, which wall/corner case, life lost by which player, endgame reached,
  serve direction) — consumed by `Coverage.mark()`.
- `color_at(x: int, y: int) -> tuple[int,int,int]` — expected 2-bit-per-channel color at a
  single screen coordinate for current state, applying border>paddles>ball>lives>background
  priority. Cheap point-check building block.
- `render_frame() -> np.ndarray[480,640,3]` — full expected frame via `color_at` (or a
  vectorized equivalent) for full-frame diffing.
- `velocity_within_safety_bounds() -> bool` — stub now (always True until speed-up
  lands); becomes the cheap per-frame invariant check once discrete rally speed-up is
  implemented (velocity must stay inside the tunneling-safe 4-bit range).

## `class PaddleDriver` — mechanical pin control only

**Data:** `dut` reference; bit-position constants
(`P1_LEFT=5, P1_RIGHT=6, P1_SELECT=7, P2_LEFT=2, P2_RIGHT=3, P2_SELECT=4`).

**Methods:**
- `set_button(player: Literal["p1","p2"], button: Literal["left","right","select"], value: bool) -> None`
- `release_all() -> None`
- `pulse_select(player) -> None` (async) — press select, hold a few cycles, release;
  convenience for serving/starting.

No decision logic lives here — it only knows *how* to press, never *whether* to.

## Stimulus policies — standalone coroutines, not classes

- `directed_sequence(driver: PaddleDriver, steps: list[...]) -> None` (async) — runs an
  explicit list of directed button states for known scenarios (each paddle segment, each
  wall-corner case, both limit clamps, both out-of-bounds sides, endgame, both serve
  directions).
- `biased_random_driver(driver: PaddleDriver, ref_model: ReferenceModel, player, follow_prob=0.85) -> None`
  (async, runs forever until cancelled) — each frame boundary, calls `next_paddle_move`
  against the *current ball position*, applies it with probability `follow_prob`, else
  picks randomly/idles. One instance per player.

## `class Display` — monitor (pure capture, no judgment)

**Data:**
- `frame_buffer: np.ndarray` — frame currently being filled
- `hpos`, `vpos: int` — write position, from `expected_hpos_vpos`, independent of DUT
  internals
- `history: collections.deque(maxlen=4)` — recently completed frames + their event logs,
  for pre-failure context
- `completed_frames: int`

**Methods:**
- `consume(dut) -> None` (async, forever) — each clock: decode via `decode_uo_out`, write
  into `frame_buffer[vpos][hpos]`, advance position; on frame complete, push
  `(frame, events)` into `history`, start a new buffer.
- `get_current_frame() -> np.ndarray`
- `log_event(event) -> None` — external callers (driver, ref model) can annotate the
  current frame's event log.

## `class Scoreboard` — compare + verdict + failure dump

**Data:** `display: Display`, `ref_model: ReferenceModel`, `fail_count: int`

**Methods:**
- `check_frame(frame_index: int) -> bool` — full-frame diff (`display` vs.
  `ref_model.render_frame()`) at checkpoints only. On mismatch → `dump_failure`.
- `check_invariants() -> None` — cheap per-frame numeric asserts (e.g.
  `velocity_within_safety_bounds`); appends to `errors` on violation. Runs every frame —
  this is the high-frequency check, `check_frame` is the low-frequency one.
- `dump_failure(reason: str, frame_index: int) -> None` — writes `actual.png`,
  `expected.png`, `diff.png` (mismatched pixels highlighted) for the failing frame, plus a
  contact-sheet of `display.history`'s prior frames and their event logs. Filename encodes
  the reason (`frame0142_p1_paddle_collision_mismatch.png`), not a bare counter.

## `class Coverage`

**Data:** dict of bins — `p1_segment_hit`/`p2_segment_hit` (6 bools each),
`wall_corner_case` (one bin per enumerated case in `game_logic.v`'s corner-collision
OR-list), `p1_limit_left/right`/`p2_limit_left/right`, `p1_life_lost`/`p2_life_lost`,
`endgame_both_out`, `serve_up`/`serve_down`.

**Methods:**
- `mark(event_name: str, sub_key=None) -> None` — called by `Scoreboard`/test flow when an
  event is *confirmed* (matched against actual DUT behavior), not merely attempted.
- `report() -> dict` — hit/miss summary, printed at test end.

## Top-level `@cocotb.test()` flow

1. Seed RNG from `os.environ.get("SEED")` if set, else random — log whichever it is, for
   reproducibility.
2. Start clock, `start_soon(vga_checker(dut))`.
3. Instantiate `Display`, `ReferenceModel`, `PaddleDriver`, `Scoreboard(display, ref_model)`,
   `Coverage`. `start_soon(display.consume(dut))`.
4. Reset sequence; `ref_model.reset()`.
5. Sanity-check the first captured frame against `ref_model.render_frame()` explicitly and
   log it — a one-time "trust the oracle" check before relying on it for everything else.
6. Directed phase: `directed_sequence` scenarios, stepping `ref_model` in lockstep,
   `scoreboard.check_invariants()` every frame, `check_frame()` at checkpoints,
   `coverage.mark()` on confirmed events.
7. Randomized phase: `start_soon(biased_random_driver(...))` for both players, run N
   frames, same per-frame checking.
8. `assert not errors`; `coverage.report()` (and assert full coverage in strict/CI mode).

## Open item for later

Once discrete rally speed-up lands in RTL, `ReferenceModel` needs a matching
`speed_level` state + re-keyed velocity LUT, and `velocity_within_safety_bounds()` becomes
a real (not stub) check — this is the natural point the model extends, per the earlier
design-spec.md discussion on regression reuse.
