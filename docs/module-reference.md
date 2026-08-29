# Module reference — base design (robojan/tt04-pong, as copied into `src/`)

11 modules. Everything is synchronous to one clock (`clk`), asynchronous active-low
reset (`nRst`). Read this bottom-up: `vga_timing` → painters → `video_mux` →
`game_logic` → `pong` (glue) → `tt_um_robojan_pong_top` (chip pins).

## `tt_um_robojan_pong_top.v` — chip I/O boundary

The literal top-level module the TT harness instantiates. Its only job is pin mapping —
it contains zero game logic itself.

- Instantiates a single `pong` module.
- **Input mapping:** `ui_in[2]`→P2 left, `ui_in[3]`→P2 right, `ui_in[4]`→P2 select,
  `ui_in[5]`→P1 left, `ui_in[6]`→P1 right, `ui_in[7]`→P1 select. **`ui_in[0]` and
  `ui_in[1]` are unused** — this is your free real estate for a 2P/AI mode-select switch.
- **Output mapping:** `uo_out[0]`=hsync, `[1]`=vsync, `[3:2]`=vga_r, `[5:4]`=vga_g,
  `[7:6]`=vga_b (2-bit-per-channel VGA, 6 bits of color total).
- **Bidirectional (`uio`) mapping:** `uio_oe = 8'b0000_1110` (bits 1,2,3 driven as
  outputs; rest are inputs, unused). `uio_out[1]`=hblank, `[2]`=vblank, `[3]`=sound.
  These three are chip *outputs* even though `uio` is nominally bidirectional — useful
  bring-up test points once silicon arrives (you can watch blanking/audio on a scope
  without needing the VGA signal itself).
- `ena`/`clk`/`rst_n` pass straight through as `en`/`clk`/`nRst`.

## `pong.v` — structural glue (the "top of the design," one level below chip pins)

No state of its own. Wires together every other module and defines the two crucial
derived signals: **collision** and **video mux selection**.

Instantiates, in order:
1. **6× `synchronizer`** — one per button (`p1/p2 × left/right/select`). 2-FF metastability
   sync from raw `ui_in` pins to internal logic.
2. **1× `vga_timing`** — the pixel/line/frame clock for everything downstream.
3. **1× `video_mux`** — final per-pixel color selection.
4. **1× `border_painter`**.
5. **1× `ball_painter`**.
6. **2× `paddle_painter`** — `p1_paddle_painter` (`PADDLE_Y=456`, bottom of screen) and
   `p2_paddle_painter` (`PADDLE_Y=16`, top of screen). This is where "two-player already
   exists" lives structurally — two fully independent instances, own `_x` position input,
   own `paddle_segment` output.
7. **2× `lives_painter`** — `p1_lives_painter` (`LIVES_Y=474`, bottom) and
   `p2_lives_painter` (`LIVES_Y=2`, top).
8. **1× `sound_gen`**.
9. **1× `game_logic`** — the only module with actual gameplay state (ball/paddle
   position, lives, game FSM).

**Collision derivation** (the architectural trick that makes this design easy to extend):
```verilog
wire wall_collision      = draw_border     && draw_ball;
wire p1_paddle_collision  = draw_p1_paddle  && draw_ball;
wire p2_paddle_collision  = draw_p2_paddle  && draw_ball;
wire paddle_collision     = p1_paddle_collision || p2_paddle_collision;
wire [2:0] paddle_segment = p1_paddle_collision ? p1_paddle_segment : p2_paddle_segment;
wire collision            = wall_collision || paddle_collision;
```
Collision isn't computed from coordinates — it falls out for free from two painters both
asserting "I own this pixel" on the same clock. Any new object you add just needs its own
`draw_xxx && draw_ball` term ORed into `collision` (and, if it should bounce like a wall
rather than a paddle, keep it out of the `paddle_collision`/`paddle_segment` path).

`video_mux` inputs are wired here too — every painter's `color`/`draw_en` pair feeds in,
plus a hardcoded `background = 6'b000000` (black).

Data flow summary: `vga_timing` gives every painter `(hpos, vpos)` each cycle → each
painter independently decides "is this pixel mine?" (`draw_en`) and what color →
`video_mux` picks a winner by fixed priority → `game_logic` watches the *same* draw_en
signals to detect collisions and update ball/paddle state once per frame.

## `vga_timing.v` — the master timing generator (no dependencies, feeds everyone)

Standard 640×480@60Hz VGA CRT-style timing via two free-running counters.

- `hor_counter` (0..799, wraps): position within one scanline (800 clocks/line at pixel
  clock = one line including horizontal blanking).
- `vert_counter` (0..524, wraps): which scanline (525 lines/frame including vertical
  blanking), increments once per `hor_counter` wrap.
- Derives `hsync`/`vsync` pulses at the standard front/sync/back-porch offsets
  (hsync low during 656–752; vsync low during 490–492).
- `hactive`/`vactive`: true during the visible 640×480 region; `active = hactive && vactive`
  is "currently drawing a real pixel, not blanking."
- **`hpos`/`vpos`**: the raw counters, exported as the coordinate system every painter
  consumes. `hpos` ∈ [0,639] valid range when active, `vpos` ∈ [0,479].
- **`line_pulse`** = `hor_at_end`: one-cycle pulse at the end of every line (800 clocks).
  Used by anything that needs a "once per scanline" tick (e.g. `sound_gen`).
- **`frame_pulse`** = end of line AND end of frame: one-cycle pulse once every ~525×800
  clocks. **This is the game's heartbeat** — `game_logic` only updates ball/paddle
  position and lives on this pulse, i.e. once per video frame (60Hz), not every clock.

## `synchronizer.v` — generic 2-flop input synchronizer

Trivial, parametrized (`WIDTH`, `DEFAULT_VALUE`) double-flop synchronizer: `in → reg1 →
reg2 → out`, 2-cycle latency. Used 6× in `pong.v`, once per raw button input, to avoid
metastability from the async `ui_in` pins. No debounce logic — a mechanical switch bounce
would currently be seen as real presses; not addressed anywhere in this design.

## `ball_painter.v` — draws the ball, AND reports which edge was hit

The most structurally clever module — it does double duty as both a painter and a
collision-*direction* sensor.

- Inputs: the ball's *authoritative* position `(x, y)` from `game_logic` (10-bit x, 9-bit
  y, full-pixel), plus the current scan position `(hpos, vpos)`.
- Internally re-derives a local `(ball_x, ball_y)` 3-bit counter pair that free-runs 0..4
  once the scan position matches the ball's `(x,y)`, tracing out a 5×5 pixel diamond
  shape (see the ASCII art in the file — corners of the 5×5 box are cut to make a round
  ball, only the "lobe" regions are lit).
- `in_ball` = OR of four "lobe" regions (left/right/top/bottom) — the actual pixel
  footprint drawn on screen.
- **`in_ball_top/left/bottom/right`**: four separate single-bit outputs, each true only on
  the *specific edge pixel* of the ball's bounding box (e.g. `in_ball_top = y0 && !x3` —
  the top row, excluding the corner). These do **not** depend on what the ball is
  overlapping — they're pure "which part of my own body is being scanned right now."
  `game_logic` ANDs these with `collision` (is *anything* solid here) to figure out which
  side of the ball made contact, which then drives the bounce direction.
- No `nRst`-gated color/output register — `color` is a constant parameter
  (`BALL_COLOR = 6'b001100`, i.e. green — bits are `BBGGRR`).

## `border_painter.v` — draws left/right screen borders, purely combinational

Simplest module in the design — no clock, no state, single `assign`.

- `BORDER_WIDTH=8` (power of 2, so a bit-slice trick works): `in_border` is true when the
  top bits of `hpos` match either the left edge (`hpos[9:3]==0`) or the right edge
  (`hpos[9:3]==632>>3`). Because `632 = 640-8`, this draws two solid 8px-wide vertical
  bars at the screen edges.
- **No top/bottom border** — this game is bounded only left/right; top/bottom are where
  the ball exits (scored point / life lost), consistent with it being a *vertical* Pong
  (paddles at top and bottom, ball travels primarily up/down).
- Color: constant white (`6'b111111`).

## `paddle_painter.v` — draws one paddle, and reports which of 6 segments was hit

One instance per player (2 total, differ only in `PADDLE_Y` parameter: bottom=456,
top=16).

- Inputs: `x` = paddle's current left-edge position (10-bit, from `game_logic`),
  `(hpos, vpos)` = scan position.
- **Two independent state machines**, X and Y, ANDed together (`in_paddle = in_paddle_x &&
  in_paddle_y`):
  - Y: simple latch, `vpos == PADDLE_Y` sets it, `vpos == PADDLE_Y + PADDLE_HEIGHT(8)`
    clears it — an 8px-tall horizontal band.
  - X: the paddle is divided into `PADDLE_NUM_SEGMENTS=6` segments of
    `PADDLE_SEGMENT_WIDTH=8` px each (48px paddle total). Two nested counters:
    `paddle_segment_x` counts 0..7 within a segment, `paddle_segment_cnt` counts 0..5
    across segments. **`paddle_segment` output = which of the 6 segments is currently
    being scanned** — this is what lets `game_logic` implement "ball bounces at a
    different angle depending on where on the paddle it lands," *without* the paddle
    painter knowing anything about the ball.
- Color: constant white.

## `lives_painter.v` — draws a row of "pips" indicating remaining lives (0–3)

One instance per player (top=`LIVES_Y=2`, bottom=`LIVES_Y=474`).

- Input `lives` (2-bit, from `game_logic`, 0–3).
- Renders up to 3 blocks (`LIVES_WIDTH=24` px each) spaced `SPACING=16` px apart,
  left-to-right, redrawing the count fresh every scanline (state resets on `!hactive`,
  i.e. at the start of each new line) — so this module has no persistent memory across
  frames, it just recomputes "am I in a lit pip" purely from `hpos` position and the
  current `lives` value every single line.
- `lives_cntr` decrements once per pip-worth of horizontal distance; once it hits 0,
  remaining horizontal space (up to 3 pips' worth) draws nothing → visually, `lives` pips
  lit out of a fixed 3-pip-wide slot.

## `sound_gen.v` — two-tone square-wave beeper

Not part of the video path at all — separate concern, feeds the `sound` output pin only.

- Two independent square-wave generators sharing one counter (`sound_counter`, clocked on
  `line_pulse` — i.e. it advances once per scanline, not once per pixel clock, giving an
  audible-range tone from a very slow "clock"): bit `[SOUND_DIVIDER-1]` → high tone, bit
  `[SOUND_DIVIDER]` → low tone (one octave lower, being one bit further up).
- `high_beep`/`low_beep` are pulse inputs from `game_logic`: `high_beep` = wired to
  `collision` (any bounce → short high beep), `low_beep` = wired to `ball_out_of_bounds`
  (point lost → short low beep).
- Each tone has its own enable + duration counter (`HIGH_LENGTH=3` / `LOW_LENGTH=6`
  frame-pulses long), so a beep is a short burst, not a held tone.
- Output: XOR of the two active waveforms, gated by "is either enabled" — lets both beeps
  overlap without simple OR clipping, though in practice they're triggered by
  mutually-exclusive events within a frame.

## `video_mux.v` — fixed-priority pixel selector (purely combinational)

Takes every painter's `(color, draw_en)` pair and picks one winner per pixel via
if/elif priority (first match wins), in this order:
**blanking (black) > border > p1_paddle > p2_paddle > ball > p1_lives > p2_lives >
background (black).**

Notable: **paddles draw over the ball**, and **border draws over everything**. This
matters if you ever add an object that should appear *behind* the ball (or in front of
it) — you must insert its priority tier at the right point in this if/elif chain, not
just add it independently.

## `game_logic.v` — the only stateful gameplay module; everything else is either timing or paint

This is where all real state lives: ball position/velocity, both paddle positions, both
lives counts, and the game FSM. Everything else in the design is a pure function of state
this module owns (plus `hpos`/`vpos`).

**Game FSM** (`game_state`, 1 bit): `STATE_START` (waiting for either player's `select`
button) → `STATE_PLAYING`. On serve, ball resets to center-ish
(`INITIAL_BALL_X/Y`), velocity resets to `(INITIAL_VEL_X=0, INITIAL_VEL_Y=±2)` — i.e.
serves travel straight up or down, no horizontal component initially.

**Collision latching**: because collisions are detected *during* the frame draw (as the
beam scans over the ball), but the game state should only update *once* per frame, the
four edge signals (`ball_top/left/bottom/right_col`) and `paddle_collision`/
`paddle_segment` get OR'd into "latched" registers throughout the frame, then consumed —
and cleared — exactly at `frame_pulse`. This is the pattern to understand before touching
any of this: **"latch during draw, resolve once at frame boundary"** is used everywhere
gameplay state changes.

**Ball physics** (fixed-point, half-pixel precision — note the `{value, 1'b0}` initial
loads and `[10:1]`/`[9:1]` output slices):
- `ball_state_x` (12-bit signed), `ball_state_y` (11-bit signed): position in half-pixel
  units. `ball_x`/`ball_y` outputs are the integer part (`>>1`).
- `velocity_x`/`velocity_y` (4-bit signed each, so range −8..+7, i.e. max 3.5 px/frame):
  updated once per `frame_pulse` via a big combinational `next_velocity` case block:
  - Ball out of bounds → reset to serve velocity.
  - Paddle hit → `vx` set from a **fixed 6-entry LUT keyed on which paddle segment was
    hit** (segment 0→−3 ... segment 5→+3, i.e. edge hits deflect sharply, center hits
    deflect less), `vy` flips sign (bounces back toward the other player). *This is the
    hook point for the rally-speed-up feature you're planning* — you'd key this LUT on
    `(segment, speed_level)` instead of `segment` alone.
  - Wall hit (border or ball corner cases with no paddle involved): a long OR'd list of
    which edge-bit combinations mean "reflect vertically" vs "reflect horizontally" — this
    encodes ball-corner-hits-wall-corner logic explicitly, worth reading closely before
    modifying, since it's the part with the most enumerated cases.
  - No collision → velocity unchanged.
- Position updates unconditionally every `frame_pulse`: `ball_state_x += next_velocity_x`
  (note: uses *next* velocity, not current — so direction changes apply to movement in
  the same frame the bounce is detected).

**Out-of-bounds / scoring**: `ball_out_of_bounds_p2 = ball_y >= 500` (bottom exit, P2
concedes a life since P2's paddle is at top... actually check sign carefully — see below),
`ball_out_of_bounds_p1 = ball_y >= 488 && !p2's condition` (checked first since 488 < 500,
narrower band). On out-of-bounds at `frame_pulse`, the losing player's life count
decrements (or, if both already had lives, the game ends and both reset to 3 — this reset-
on-endgame behavior is slightly unusual, worth a directed test).

**Paddle logic**: each paddle is an independent 10-bit position register
(`p1_paddle_state_x`, `p2_paddle_state_x`), moved ±`PADDLE_SPEED(1)` px/frame on
`btn_left`/`btn_right`, clamped at `is_at_left_limit`/`is_at_right_limit` (derived from
`BORDER_WIDTH` and `640 - BORDER_WIDTH - PADDLE_WIDTH`). Paddle resets to
`INITIAL_PADDLE_X` (screen-centered) whenever the ball goes out of bounds (i.e. every new
serve, both paddles re-center — no "serve from where you last were").

## Where your planned features actually hook in

| Feature | Where it goes | What it touches |
|---|---|---|
| Rally speed-up | `game_logic.v`, `next_velocity` block, paddle-hit case | New `speed_level` reg + re-key the existing segment→vx LUT on `(segment,level)`; no other module changes |
| AI opponent | New logic feeding `p1_btn_left`/`p1_btn_right` (or p2's) instead of the synchronized button, muxed on a new `ui_in[0]`/`[1]` mode-select bit in `pong.v`/top | Doesn't touch `game_logic`'s internals at all — it's a drop-in replacement for the *input source*, which is exactly why it's low-risk |
| AI clock-gating when 2P selected | Wherever the AI control logic lives, gate its clock (or just its state-update enable) with the mode-select bit | New, standalone — good, bounded, PD-stage exercise |
| Retro visual effects (scanline, color-cycle) | `video_mux.v` output stage, or a new tiny module feeding into it | Pixel-stage only, doesn't touch `game_logic` or collision at all |
