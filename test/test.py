# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import collections
import os
import random

import cocotb
import numpy as np
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, ReadOnly
from PIL import Image

errors = []


def save_png(frame_levels: np.ndarray, path: str):
    """frame_levels holds raw 2-bit-per-channel values (0-3); scale to
    0-255 for a viewable PNG."""
    bytes_frame = (frame_levels.astype(np.uint16) * 85).astype(np.uint8)
    Image.fromarray(bytes_frame, mode="RGB").save(path)


def screenshot_enabled() -> bool:
    """Gated by a plusarg so screen captures don't cost anything on a
    normal run: `make PLUSARGS=+screenshot`."""
    return bool(cocotb.plusargs.get("screenshot"))


def maybe_capture_screenshot(display, tag: str, out_dir: str = "sim_build/screenshots"):
    if not screenshot_enabled() or not display.history:
        return
    os.makedirs(out_dir, exist_ok=True)
    frame, _events = display.history[-1]
    save_png(frame, f"{out_dir}/{tag}.png")


def next_paddle_move(paddle_x: int, ball_x: int, paddle_width: int) -> str:
    """Simple ball-tracking decision: move paddle center toward ball_x.
    Returns 'left', 'right', or 'none'. Doesn't need to know about travel
    limits - both the DUT and ReferenceModel independently enforce those
    regardless of what's commanded. Same algorithm scoped for a potential
    real RTL AI opponent (matches the Project F reference found earlier);
    reused here as the default biased-random stimulus policy."""
    paddle_center = paddle_x + paddle_width // 2
    if ball_x < paddle_center:
        return "left"
    elif ball_x > paddle_center:
        return "right"
    return "none"


def decide_biased_move(ref_model, player: str, follow_prob: float = 0.85) -> tuple:
    """(left, right) for one player for the upcoming frame: track the ball
    with probability follow_prob, else move randomly/idle. Concentrates
    sim time on real collisions while still exploring timing edges a
    hand-written directed test wouldn't think to hit."""
    paddle_x = ref_model.p1_paddle_x if player == "p1" else ref_model.p2_paddle_x
    if random.random() < follow_prob:
        move = next_paddle_move(paddle_x, ref_model.ball_x, ref_model.PADDLE_WIDTH)
    else:
        move = random.choice(["left", "right", "none"])
    return (move == "left", move == "right")


def _to_signed(raw: int, bits: int) -> int:
    """Decode an unsigned raw bit pattern read back from a signed HDL net.
    Robust regardless of whether cocotb's int() already applied sign
    extension - Python's bitwise AND normalizes either representation to
    the same low-order bits before the sign-bit check."""
    raw &= (1 << bits) - 1
    return raw - (1 << bits) if raw & (1 << (bits - 1)) else raw


def decode_uo_out(dut) -> tuple[bool, bool, int, int, int]:
    """Decode dut.uo_out using the Tiny VGA Pmod bit order:
    uo_out = {hsync, B0, G0, R0, vsync, B1, G1, R1}
    Returns (hsync, vsync, r, g, b) with r/g/b as 2-bit ints (0-3)."""
    v = int(dut.uo_out.value)
    hsync = bool((v >> 7) & 1)
    vsync = bool((v >> 3) & 1)
    r = (((v >> 0) & 1) << 1) | ((v >> 4) & 1)  # R1,R0
    g = (((v >> 1) & 1) << 1) | ((v >> 5) & 1)  # G1,G0
    b = (((v >> 2) & 1) << 1) | ((v >> 6) & 1)  # B1,B0
    return hsync, vsync, r, g, b


class ReferenceModel:
    """Independent golden model of game_logic.v's game state, driven one
    frame at a time via step_frame().

    Collision BOUNCE DIRECTION is derived geometrically (AABB overlap +
    minimum-translation-axis heuristic), deliberately NOT ported from
    game_logic.v's hand-written edge-latch + OR-table, so this model can
    actually catch a mistake in that table rather than share it.

    Out-of-bounds detection and paddle limit clamping ARE replicated
    bit-exactly (including the RTL's "[9:1]" rounding quirk and the
    488/500 two's-complement wraparound trick for top-exit detection) -
    these are simple, deliberate arithmetic rather than hand-written
    case-by-case logic, so independent re-derivation doesn't add
    verification value and bit-exact replication is lower risk.

    All constants below are taken from pong.v's parameter OVERRIDES, not
    the sub-modules' own defaults (e.g. PADDLE_WIDTH is 24, not 48/64 -
    verified directly against src/pong.v and src/game_logic.v).
    """

    SCREEN_W = 640
    SCREEN_H = 480
    BORDER_WIDTH = 8
    PADDLE_SEGMENT_WIDTH = 4
    PADDLE_NUM_SEGMENTS = 6
    PADDLE_WIDTH = PADDLE_SEGMENT_WIDTH * PADDLE_NUM_SEGMENTS  # 24
    PADDLE_HEIGHT = 8
    PADDLE_Y_P1 = 456  # bottom paddle
    PADDLE_Y_P2 = 16   # top paddle
    # paddle_speed now scales with the same hit_counter tiers as the ball's
    # own speed-up (game_logic.sv: paddle_speed = speed4?TOP:speed3?MID:INIT -
    # tier 1, hit_counter 4-7, has no distinct value of its own and still
    # maps to INIT). See the paddle_speed property below.
    PADDLE_SPEED_INIT = 2
    PADDLE_MID_SPEED = 3
    PADDLE_TOP_SPEED = 4
    BALL_SIZE = 5  # 5x5 bounding box

    INITIAL_BALL_X = 320 - 2  # 318 (pong.v override)
    INITIAL_BALL_Y = 340 - 2  # 338 (pong.v override)
    INITIAL_VEL_X = 0         # pong.v override
    INITIAL_VEL_Y = 2         # pong.v override
    # INITIAL_PADDLE_X uses game_logic.v's own default expression, but per
    # Verilog parameter elaboration it's evaluated with the OVERRIDDEN
    # PADDLE_WIDTH (24), not game_logic.v's own default (64):
    INITIAL_PADDLE_X = 320 - PADDLE_WIDTH // 2 - 1  # 307

    # Paddle travel limits, replicated bit-exactly including the ">>1"
    # rounding (RTL comment: "ignore the bottom bit to account for the
    # velocity of the paddle") and the asymmetry between p1/p2's left-limit
    # formula (p1 has a "-1", p2 does not - present in game_logic.v as-is).
    _P1_LEFT_LIMIT_VAL = (BORDER_WIDTH >> 1) - 1                        # 3
    _P2_LEFT_LIMIT_VAL = (BORDER_WIDTH >> 1)                            # 4
    _RIGHT_LIMIT_VAL = (SCREEN_W - BORDER_WIDTH - PADDLE_WIDTH) >> 1    # 304

    # Rally speed-up: hit_counter is a 4-bit SATURATING counter (game_logic.sv
    # lines 74-90) incremented on every raw `paddle_collision` pulse - which
    # fires DURING ball-scanning, well before that frame's frame_pulse. The
    # tier-select logic (speed2_en/speed3_en/speed4_en -> speed_factor_x/y)
    # is purely combinational from hit_counter's CURRENT value, and is
    # consumed by the next_velocity_x/y case block at frame_pulse time using
    # `latched_paddle_collision` (latched across the frame, cleared AT
    # frame_pulse). Net effect: by the time a hit's own velocity update is
    # computed, hit_counter has ALREADY incremented for that same hit - so
    # the tier used for a given hit reflects the count INCLUDING that hit,
    # not the count before it. Modeled here as: increment first, then look
    # up tier from the post-increment value (see _resolve_paddle_hit).
    HIT_CNT_WIDTH = 4
    HIT_CNT_MAX = (1 << HIT_CNT_WIDTH) - 1  # 15, saturates (no wrap)
    SPEED2_CNT = 4
    SPEED3_CNT = 8
    SPEED4_CNT = 12

    # Per-tier segment->vx tables, bit-exact copies of the four case(speed_factor_x)
    # branches in game_logic.sv (lines 218-287).
    _SEGMENT_VX_TIERS = {
        0: {0: -3, 1: -2, 2: -1, 3: 1, 4: 2, 5: 3},
        1: {0: -4, 1: -3, 2: -2, 3: 2, 4: 3, 5: 4},
        2: {0: -5, 1: -4, 2: -3, 3: 3, 4: 4, 5: 5},
        3: {0: -7, 1: -6, 2: -5, 3: 5, 4: 6, 5: 7},
    }
    # speed_factor_y per tier (game_logic.sv line 107: speed4?7:speed3?6:speed2?4:2).
    _SPEED_FACTOR_Y = {0: 2, 1: 4, 2: 5, 3: 6}

    def __init__(self):
        self.reset()

    def reset(self):
        self.game_state = "START"
        self.p1_lives = 3
        self.p2_lives = 3
        # Ball position in half-pixel units, matching RTL's ball_state_x/y
        # (signed regs, LSB = half pixel).
        self.ball_state_x = self.INITIAL_BALL_X * 2
        self.ball_state_y = self.INITIAL_BALL_Y * 2
        self.velocity_x = self.INITIAL_VEL_X
        self.velocity_y = self.INITIAL_VEL_Y
        self.p1_paddle_x = self.INITIAL_PADDLE_X
        self.p2_paddle_x = self.INITIAL_PADDLE_X
        self.hit_counter = 0

    @property
    def ball_x(self) -> int:
        return self.ball_state_x >> 1

    @property
    def ball_y(self) -> int:
        return self.ball_state_y >> 1

    @classmethod
    def _tier_for(cls, hit_counter: int) -> int:
        speed2_en = hit_counter >= cls.SPEED2_CNT
        speed3_en = hit_counter >= cls.SPEED3_CNT
        speed4_en = hit_counter >= cls.SPEED4_CNT
        return int(speed2_en) + int(speed3_en) + int(speed4_en)

    @property
    def paddle_speed(self) -> int:
        tier = self._tier_for(self.hit_counter)
        if tier == 3:
            return self.PADDLE_TOP_SPEED
        if tier == 2:
            return self.PADDLE_MID_SPEED
        return self.PADDLE_SPEED_INIT

    def _resolve_paddle_hit(self, segment: int) -> int:
        """One paddle-hit velocity update: bumps hit_counter (saturating),
        then applies the resulting tier's vx (by segment) and vy (magnitude
        from the tier, SIGN FLIPPED relative to the ball's incoming
        velocity_y - matching game_logic.sv line 288's
        `(velocity_y < 0) ? speed_factor_y : -speed_factor_y`, which reverses
        travel direction rather than always forcing negative). Returns the
        tier used, for test assertions."""
        if self.hit_counter < self.HIT_CNT_MAX:
            self.hit_counter += 1
        tier = self._tier_for(self.hit_counter)
        self.velocity_x = self._SEGMENT_VX_TIERS[tier][segment]
        self.velocity_y = (self._SPEED_FACTOR_Y[tier] if self.velocity_y < 0
                            else -self._SPEED_FACTOR_Y[tier])
        return tier

    def velocity_within_safety_bounds(self) -> bool:
        """Tunneling-safety invariant: |v| must stay inside the 4-bit-signed
        range (-8..7) that guarantees the ball can't skip over an 8px-thick
        border/paddle in a single frame. Real check now that rally speed-up
        is non-trivial (tier 3 reaches magnitude 7, right at the ceiling)."""
        return -8 <= self.velocity_x <= 7 and -8 <= self.velocity_y <= 7

    # 5x5 ball bounding box, per ball_painter.v's four-lobe ASCII art
    # (derived directly from its left/right/top/bottom_lobe wire logic):
    _BALL_SHAPE = (
        (0, 1, 1, 1, 0),
        (1, 1, 1, 1, 1),
        (1, 1, 1, 1, 1),
        (1, 1, 1, 1, 1),
        (0, 1, 1, 1, 0),
    )
    _WHITE = (3, 3, 3)
    _BALL_COLOR = (0, 3, 0)  # BBGGRR=001100 -> green
    LIVES_Y_P1 = 474
    LIVES_Y_P2 = 2
    LIVES_HEIGHT = 4
    LIVES_WIDTH = 24
    LIVES_SPACING = 16

    # Both paddle_painter.v's in_paddle_x and ball_painter.v's
    # is_in_ball_line are registered flags set from a single-cycle pulse
    # (hpos==x), so - same registered-comparison-lag mechanism confirmed
    # for vga_timing.v's hsync/vsync - they turn on one cycle AFTER hpos
    # actually equals x. Net effect: both paddles and the ball render one
    # pixel to the right of their x register's nominal value. Y is
    # unaffected for both (paddle_painter's Y-end check uses "+HEIGHT" not
    # "+HEIGHT-1", which cancels the lag; the ball's row-enable depends on
    # vpos, which doesn't change within the single affected cycle).
    # Confirmed by direct full-frame comparison against the DUT, not just
    # derivation - see docs/dv-plan.md.
    _X_RENDER_LAG = 1

    def color_at(self, x: int, y: int) -> tuple:
        """Expected color at a single screen coordinate, applying the same
        border>paddles>ball>lives>background priority as video_mux.v."""
        if x < self.BORDER_WIDTH or x >= self.SCREEN_W - self.BORDER_WIDTH:
            return self._WHITE
        p1x = self.p1_paddle_x + self._X_RENDER_LAG
        p2x = self.p2_paddle_x + self._X_RENDER_LAG
        if (self.PADDLE_Y_P1 <= y < self.PADDLE_Y_P1 + self.PADDLE_HEIGHT and
                p1x <= x < p1x + self.PADDLE_WIDTH):
            return self._WHITE
        if (self.PADDLE_Y_P2 <= y < self.PADDLE_Y_P2 + self.PADDLE_HEIGHT and
                p2x <= x < p2x + self.PADDLE_WIDTH):
            return self._WHITE
        bx = x - (self.ball_x + self._X_RENDER_LAG)
        by = y - self.ball_y
        if 0 <= bx <= 4 and 0 <= by <= 4 and self._BALL_SHAPE[by][bx]:
            return self._BALL_COLOR
        # Lives pips: in_lives_y is checked every cycle against a held
        # vpos (same class of lag as vsync), so only LIVES_HEIGHT-1 rows
        # render fully lit - the last nominal row is dark for all but the
        # first ~2 hpos of that line. Confirmed against the DUT.
        for ly, lives in ((self.LIVES_Y_P1, self.p1_lives), (self.LIVES_Y_P2, self.p2_lives)):
            if ly <= y < ly + self.LIVES_HEIGHT - 1:
                for i in range(lives):
                    start = self.LIVES_SPACING + i * (self.LIVES_SPACING + self.LIVES_WIDTH)
                    if start <= x < start + self.LIVES_WIDTH:
                        return self._WHITE
        return (0, 0, 0)

    def render_frame(self) -> np.ndarray:
        """Full expected frame, drawn lowest-priority-first so later
        writes correctly overwrite earlier ones (background < lives <
        ball < paddles < border, matching video_mux.v's priority order)."""
        frame = np.zeros((self.SCREEN_H, self.SCREEN_W, 3), dtype=np.uint8)
        for ly, lives in ((self.LIVES_Y_P1, self.p1_lives), (self.LIVES_Y_P2, self.p2_lives)):
            for i in range(lives):
                start = self.LIVES_SPACING + i * (self.LIVES_SPACING + self.LIVES_WIDTH)
                frame[ly:ly + self.LIVES_HEIGHT - 1, start:start + self.LIVES_WIDTH] = 3
        for dy in range(5):
            for dx in range(5):
                if self._BALL_SHAPE[dy][dx]:
                    yy = self.ball_y + dy
                    xx = self.ball_x + self._X_RENDER_LAG + dx
                    if 0 <= yy < self.SCREEN_H and 0 <= xx < self.SCREEN_W:
                        frame[yy, xx] = self._BALL_COLOR
        p2x = self.p2_paddle_x + self._X_RENDER_LAG
        p1x = self.p1_paddle_x + self._X_RENDER_LAG
        frame[self.PADDLE_Y_P2:self.PADDLE_Y_P2 + self.PADDLE_HEIGHT,
              p2x:p2x + self.PADDLE_WIDTH] = 3
        frame[self.PADDLE_Y_P1:self.PADDLE_Y_P1 + self.PADDLE_HEIGHT,
              p1x:p1x + self.PADDLE_WIDTH] = 3
        frame[:, 0:self.BORDER_WIDTH] = 3
        frame[:, self.SCREEN_W - self.BORDER_WIDTH:self.SCREEN_W] = 3
        return frame

    def _out_of_bounds_flags(self) -> tuple[bool, bool]:
        # Replicate RTL's 11-bit two's-complement ball_state_y[9:1] slice,
        # including its wraparound trick for top-exit detection.
        masked = self.ball_state_y & ((1 << 11) - 1)
        y9 = (masked >> 1) & 0x1FF
        p2_out = y9 >= 500
        p1_out = (y9 >= 488) and not p2_out
        return p1_out, p2_out

    def _paddle_at_left_limit(self, paddle_x: int, limit_val: int) -> bool:
        return (paddle_x >> 1) == limit_val

    def _paddle_at_right_limit(self, paddle_x: int) -> bool:
        return (paddle_x >> 1) == self._RIGHT_LIMIT_VAL

    def _segment_for_hit(self, paddle_x: int, ball_center_x: int) -> int:
        seg = (ball_center_x - paddle_x) // self.PADDLE_SEGMENT_WIDTH
        return max(0, min(self.PADDLE_NUM_SEGMENTS - 1, seg))

    def _overlap_axis(self, ball_l, ball_r, ball_t, ball_b,
                       rect_l, rect_r, rect_t, rect_b):
        """AABB overlap -> which axis to reverse, via minimum-translation
        heuristic. Returns 'x', 'y', 'both', or None if no overlap."""
        if ball_r < rect_l or ball_l > rect_r or ball_b < rect_t or ball_t > rect_b:
            return None
        overlap_x = min(ball_r, rect_r) - max(ball_l, rect_l)
        overlap_y = min(ball_b, rect_b) - max(ball_t, rect_t)
        if overlap_x < overlap_y:
            return "x"
        elif overlap_y < overlap_x:
            return "y"
        return "both"

    def step_frame(self, p1_left, p1_right, p1_select,
                    p2_left, p2_right, p2_select) -> list:
        """Advance one frame (one frame_pulse). Returns a list of events
        that occurred, for Coverage.mark()."""
        events = []

        if self.game_state == "START":
            if p1_select or p2_select:
                self.game_state = "PLAYING"
                self.velocity_x = self.INITIAL_VEL_X
                self.velocity_y = self.INITIAL_VEL_Y
                events.append(("serve", "down" if self.velocity_y > 0 else "up"))
                # RTL note: next_velocity is combinational, computed from
                # the PRE-edge (still STATE_START) game_state, and the SAME
                # edge that transitions game_state to PLAYING also applies
                # this freshly-computed velocity to ball_state_x/y - serve
                # and the first position advance are atomic in real
                # hardware, not two separate frame_pulses. No collision
                # check needed here: the ball rests centered, nowhere near
                # a wall/paddle, at the moment of serve.
                self.ball_state_x += self.velocity_x
                self.ball_state_y += self.velocity_y
            else:
                self.velocity_x = 0
                self.velocity_y = 0
        else:  # PLAYING
            p1_out, p2_out = self._out_of_bounds_flags()
            if p1_out or p2_out:
                # NB: matches game_logic.v exactly - only the player whose
                # out-of-bounds fired THIS frame has their own life counter
                # reset to 3 on end_of_game. The other player's counter is
                # untouched here even if it's already 0 - it only resets
                # the next time THEY personally lose a point. Asymmetric,
                # but that's what the RTL actually does.
                end_of_game = (self.p1_lives == 0 or self.p2_lives == 0)
                if end_of_game:
                    self.hit_counter = 0  # game_logic.sv line 83: !nRst || end_of_game
                if p1_out:
                    self.p1_lives = 3 if end_of_game else self.p1_lives - 1
                    events.append(("life_lost", "p1"))
                else:
                    self.p2_lives = 3 if end_of_game else self.p2_lives - 1
                    events.append(("life_lost", "p2"))
                if end_of_game:
                    events.append(("endgame", None))
                self.game_state = "START"
                self.ball_state_x = self.INITIAL_BALL_X * 2
                self.ball_state_y = self.INITIAL_BALL_Y * 2
                self.velocity_x = self.INITIAL_VEL_X
                self.velocity_y = self.INITIAL_VEL_Y
                self.p1_paddle_x = self.INITIAL_PADDLE_X
                self.p2_paddle_x = self.INITIAL_PADDLE_X
                return events  # mirrors RTL: OOB reset is mutually exclusive
                                # with button-driven paddle movement this frame

            ball_l, ball_r = self.ball_x, self.ball_x + self.BALL_SIZE - 1
            ball_t, ball_b = self.ball_y, self.ball_y + self.BALL_SIZE - 1
            ball_cx = (ball_l + ball_r) // 2

            paddle_hit_player = None
            for player, py, px in (("p1", self.PADDLE_Y_P1, self.p1_paddle_x),
                                    ("p2", self.PADDLE_Y_P2, self.p2_paddle_x)):
                axis = self._overlap_axis(
                    ball_l, ball_r, ball_t, ball_b,
                    px, px + self.PADDLE_WIDTH - 1, py, py + self.PADDLE_HEIGHT - 1)
                if axis is not None:
                    paddle_hit_player = player
                    break  # ball can't realistically overlap both paddles at once

            border_hit = (ball_l <= self.BORDER_WIDTH - 1 or
                          ball_r >= self.SCREEN_W - self.BORDER_WIDTH)

            if paddle_hit_player is not None:
                px = self.p1_paddle_x if paddle_hit_player == "p1" else self.p2_paddle_x
                segment = self._segment_for_hit(px, ball_cx)
                tier = self._resolve_paddle_hit(segment)
                events.append(("paddle_hit", paddle_hit_player, segment, tier))
            elif border_hit:
                self.velocity_x = -self.velocity_x
                events.append(("wall_hit", "x"))
            # else: no collision, velocity unchanged

            self.ball_state_x += self.velocity_x
            self.ball_state_y += self.velocity_y

        # Paddle movement: every frame, independent of game_state (RTL's
        # paddle always-block isn't gated on game_state at all).
        if p1_left and not p1_right and not self._paddle_at_left_limit(
                self.p1_paddle_x, self._P1_LEFT_LIMIT_VAL):
            self.p1_paddle_x -= self.paddle_speed
            if self._paddle_at_left_limit(self.p1_paddle_x, self._P1_LEFT_LIMIT_VAL):
                events.append(("limit", "p1", "left"))
        elif p1_right and not p1_left and not self._paddle_at_right_limit(self.p1_paddle_x):
            self.p1_paddle_x += self.paddle_speed
            if self._paddle_at_right_limit(self.p1_paddle_x):
                events.append(("limit", "p1", "right"))

        if p2_left and not p2_right and not self._paddle_at_left_limit(
                self.p2_paddle_x, self._P2_LEFT_LIMIT_VAL):
            self.p2_paddle_x -= self.paddle_speed
            if self._paddle_at_left_limit(self.p2_paddle_x, self._P2_LEFT_LIMIT_VAL):
                events.append(("limit", "p2", "left"))
        elif p2_right and not p2_left and not self._paddle_at_right_limit(self.p2_paddle_x):
            self.p2_paddle_x += self.paddle_speed
            if self._paddle_at_right_limit(self.p2_paddle_x):
                events.append(("limit", "p2", "right"))

        return events


def expected_hpos_vpos(cycle_count: int) -> tuple[int, int]:
    """Closed-form VESA 640x480@60 position from a free-running cycle
    counter, zeroed at reset release. Independently derived from the spec
    (800 clocks/line, 525 lines/frame) - never read from the DUT."""
    hpos = cycle_count % 800
    vpos = (cycle_count // 800) % 525
    return hpos, vpos


def expected_hsync_vsync(cycle_count: int) -> tuple[bool, bool]:
    """hsync/vsync are REGISTERED outputs in vga_timing.v, computed from
    hor_counter/vert_counter's value as of the PREVIOUS cycle (their
    hsync_start/vsync_start conditions are checked using the pre-edge
    counter value, one cycle before hpos/vpos reflect the post-edge
    result) - so they lag hpos/vpos by exactly one cycle.

    hactive/vactive do NOT have this lag: their comparison thresholds are
    deliberately hor_counter==639 / vert_counter==479 (N-1, not N), which
    lines up their registered update with the counter's own simultaneous
    increment to the boundary value. hsync/vsync use the boundary value
    directly (656, 490), so they don't get that cancellation - confirmed
    both by tracing the RTL and by direct simulation."""
    prev_hpos, prev_vpos = expected_hpos_vpos(max(cycle_count - 1, 0))
    hsync = not (656 <= prev_hpos <= 751)
    vsync = not (490 <= prev_vpos <= 491)
    return hsync, vsync


async def vga_checker(dut):
    """Background timing checker (start_soon = fork/join_none). Tracks its
    own spec-derived cycle counter and asserts the DUT's real hsync/vsync
    match what the VESA spec predicts, every cycle. Reports into the
    shared `errors` list rather than raising - an exception inside a
    start_soon task isn't reliably surfaced by the regression manager, so
    the main test explicitly checks `errors` instead. No separate watchdog
    needed here: this is a per-cycle comparison against a counter that
    advances every RisingEdge, so it can't hang waiting on anything.
    Start this AFTER reset is released so its cycle counter aligns with
    the DUT's hor_counter/vert_counter (frozen at 0 during reset)."""
    cycle = 0
    while True:
        # Sample BEFORE waiting: hor_counter holds 0 continuously through
        # reset and only becomes 1 on the first post-reset clock edge, so
        # sampling immediately (no edge consumed yet) is what correctly
        # captures cycle 0 == hor_counter 0. Caller must await one
        # ReadOnly() after releasing reset, before start_soon'ing this, so
        # the reset-release write has settled.
        hsync, vsync, _, _, _ = decode_uo_out(dut)
        exp_hsync, exp_vsync = expected_hsync_vsync(cycle)
        if hsync != exp_hsync:
            errors.append((cycle, f"hsync mismatch: expected {exp_hsync}, got {hsync}"))
        if vsync != exp_vsync:
            errors.append((cycle, f"vsync mismatch: expected {exp_vsync}, got {vsync}"))
        cycle += 1
        await RisingEdge(dut.clk)
        await ReadOnly()


class PaddleDriver:
    """Mechanical ui_in pin control only - no decisions about what to
    press, just how. Bit mapping verified against tt_um_robojan_pong_top.v."""
    P1_LEFT, P1_RIGHT, P1_SELECT = 5, 6, 7
    P2_LEFT, P2_RIGHT, P2_SELECT = 2, 3, 4
    _BITS = {
        ("p1", "left"): P1_LEFT, ("p1", "right"): P1_RIGHT, ("p1", "select"): P1_SELECT,
        ("p2", "left"): P2_LEFT, ("p2", "right"): P2_RIGHT, ("p2", "select"): P2_SELECT,
    }

    def __init__(self, dut):
        self.dut = dut
        self._state = 0  # shadow of ui_in, since we only ever write the whole byte

    def set_button(self, player: str, button: str, value: bool):
        bit = self._BITS[(player, button)]
        if value:
            self._state |= (1 << bit)
        else:
            self._state &= ~(1 << bit)
        self.dut.ui_in.value = self._state

    def release_all(self):
        self._state = 0
        self.dut.ui_in.value = self._state

    async def pulse_select(self, player: str, hold_cycles: int = 4):
        self.set_button(player, "select", True)
        await ClockCycles(self.dut.clk, hold_cycles)
        self.set_button(player, "select", False)


class Display:
    """Monitor - pure capture, no judgment (compare/verdict logic lives in
    Scoreboard). Builds a frame buffer from the DUT's pins using a
    spec-derived hpos/vpos, independent of DUT internals. Keeps a small
    ring buffer of recently-completed frames + their event logs for
    pre-failure context."""

    def __init__(self, history_len: int = 4):
        self.frame_buffer = np.zeros((480, 640, 3), dtype=np.uint8)
        self.history = collections.deque(maxlen=history_len)
        self.completed_frames = 0
        self._cycle = 0
        self._event_log = []

    def log_event(self, event):
        self._event_log.append((self._cycle, event))

    async def consume(self, dut):
        # Sample-before-wait, same reasoning as vga_checker above: cycle 0
        # must correspond to hor_counter 0, sampled with zero edges
        # consumed since reset release settled.
        while True:
            _, _, r, g, b = decode_uo_out(dut)
            hpos, vpos = expected_hpos_vpos(self._cycle)
            if hpos < 640 and vpos < 480:
                self.frame_buffer[vpos, hpos] = (r, g, b)
            if hpos == 799 and vpos == 479:
                self.history.append((self.frame_buffer.copy(), list(self._event_log)))
                self.completed_frames += 1
                self._event_log = []
                self.frame_buffer = np.zeros((480, 640, 3), dtype=np.uint8)
            self._cycle += 1
            await RisingEdge(dut.clk)
            await ReadOnly()

    def get_current_frame(self) -> np.ndarray:
        return self.frame_buffer


class Scoreboard:
    """Compare + verdict + failure dump. Takes an already-captured actual
    frame (e.g. from display.history) rather than reaching into Display
    itself, so the comparison has no dependency on cross-task timing."""

    def __init__(self, display: Display, ref_model: ReferenceModel,
                 out_dir: str = "sim_build/failures"):
        self.display = display
        self.ref_model = ref_model
        self.fail_count = 0
        self.out_dir = out_dir

    def check_frame(self, actual_frame: np.ndarray, frame_index: int, reason: str = "",
                     expected: np.ndarray = None) -> bool:
        """`expected` must be an explicit snapshot the caller controls (see
        the frame/step correspondence note on test_serve_and_ball_motion) -
        defaults to ref_model's CURRENT state only as a convenience for
        simple cases with no pending step_frame() call."""
        if expected is None:
            expected = self.ref_model.render_frame()
        if np.array_equal(actual_frame, expected):
            return True
        self.fail_count += 1
        self.dump_failure(actual_frame, expected, frame_index, reason)
        return False

    def check_invariants(self) -> bool:
        """Cheap per-frame numeric checks, run every frame unlike the
        (comparatively expensive) full-frame check_frame(). Currently just
        the velocity safety bound; becomes meaningful once discrete rally
        speed-up lands (right now it's trivially always true)."""
        if not self.ref_model.velocity_within_safety_bounds():
            errors.append(("velocity_out_of_bounds",
                            self.ref_model.velocity_x, self.ref_model.velocity_y))
            return False
        return True

    def dump_failure(self, actual: np.ndarray, expected: np.ndarray,
                      frame_index: int, reason: str):
        os.makedirs(self.out_dir, exist_ok=True)
        tag = f"frame{frame_index:04d}" + (f"_{reason}" if reason else "")
        save_png(actual, f"{self.out_dir}/{tag}_actual.png")
        save_png(expected, f"{self.out_dir}/{tag}_expected.png")
        diff_mask = np.any(actual != expected, axis=-1)
        diff_img = (actual.astype(np.uint16) // 2).astype(np.uint8)
        diff_img[diff_mask] = [255, 0, 255]
        save_png(diff_img, f"{self.out_dir}/{tag}_diff.png")
        for i, (hist_frame, hist_events) in enumerate(self.display.history):
            save_png(hist_frame, f"{self.out_dir}/{tag}_history{i}.png")


class Coverage:
    """Bins mirror the observable event vocabulary ReferenceModel.step_frame()
    returns - deliberately NOT the RTL's internal OR-table case names,
    since the model's collision resolution is independently (geometrically)
    derived rather than ported, so there's no clean 1:1 mapping to those
    anyway. This replaces "run enough random play and hope" with a
    checkable closure criterion."""

    def __init__(self):
        self.bins = {
            "p1_segment_hit": [False] * 6,
            "p2_segment_hit": [False] * 6,
            "speed_tier_hit": [False] * 4,
            "p1_limit_left": False, "p1_limit_right": False,
            "p2_limit_left": False, "p2_limit_right": False,
            "p1_life_lost": False, "p2_life_lost": False,
            "endgame": False,
            "serve_up": False, "serve_down": False,
            "wall_hit": False,
        }

    def mark(self, event: tuple):
        kind = event[0]
        if kind == "paddle_hit":
            _, player, segment, tier = event
            self.bins[f"{player}_segment_hit"][segment] = True
            self.bins["speed_tier_hit"][tier] = True
        elif kind == "wall_hit":
            self.bins["wall_hit"] = True
        elif kind == "life_lost":
            _, player = event
            self.bins[f"{player}_life_lost"] = True
        elif kind == "limit":
            _, player, side = event
            self.bins[f"{player}_limit_{side}"] = True
        elif kind == "endgame":
            self.bins["endgame"] = True
        elif kind == "serve":
            _, direction = event
            self.bins[f"serve_{direction}"] = True

    def mark_all(self, events: list):
        for ev in events:
            self.mark(ev)

    def report(self) -> dict:
        flat = {}
        for k, v in self.bins.items():
            if isinstance(v, list):
                for i, hit in enumerate(v):
                    flat[f"{k}[{i}]"] = hit
            else:
                flat[k] = v
        return flat

    def summary_str(self) -> str:
        flat = self.report()
        hit = sum(1 for v in flat.values() if v)
        missing = [k for k, v in flat.items() if not v]
        return f"{hit}/{len(flat)} bins hit. Missing: {missing}"


@cocotb.test()
async def test_timing_and_capture(dut):
    """First real integration milestone: run past one full frame, confirm
    vga_checker sees zero timing violations, and sanity-check the captured
    frame (border should be solid white at the expected columns)."""
    dut._log.info("Start")

    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())

    dut._log.info("Reset")
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ReadOnly()  # let the reset-release write settle before sampling

    # Start the checker/monitor AFTER reset so their spec-derived cycle
    # counters align with the DUT's hor_counter/vert_counter (frozen at 0
    # during reset).
    cocotb.start_soon(vga_checker(dut))
    display = Display()
    cocotb.start_soon(display.consume(dut))

    # Run past one full frame (800 * 525 cycles) plus a margin.
    await ClockCycles(dut.clk, 800 * 525 + 100)

    assert not errors, f"{len(errors)} timing violations, first: {errors[:3]}"
    assert display.completed_frames >= 1, "no complete frame was captured"

    frame = display.history[-1][0]
    dut._log.info(f"Captured {display.completed_frames} frame(s)")

    # Border sanity check: solid white (2-bit level 3 per channel, frame
    # buffer stores raw levels not bytes) at columns [0:8) and [632:640),
    # black everywhere else in a row clear of paddles/lives (row 240, the
    # vertical middle, is clear of both).
    row = frame[240]
    assert (row[0:8] == 3).all(), f"left border not white: {row[0:8]}"
    assert (row[632:640] == 3).all(), f"right border not white: {row[632:640]}"
    assert (row[8:632] == 0).all(), "expected black between the borders on row 240"

    dut._log.info("Border sanity check passed")


FRAME_CYCLES = 800 * 525


@cocotb.test()
async def test_serve_and_ball_motion(dut):
    """First real content-correctness check: full-frame comparison of the
    DUT's actual rendered picture against ReferenceModel's independent
    prediction, across a serve.

    Frame/step correspondence (empirically confirmed, not just derived -
    see docs/dv-plan.md): frame_pulse fires once per 800*525-cycle span,
    at vpos==524 (vertical blanking, past the 480 visible lines).
    Display's own completion marker is vpos==479, which happens BEFORE
    that same span's frame_pulse. Net effect: a display completion right
    after wait W reflects state from the move applied before wait W-1, NOT
    the move applied before wait W (whose real frame_pulse hasn't fired
    within a completed capture yet). So: **compare each completion against
    a ReferenceModel snapshot taken BEFORE the most recent step_frame()
    call**, not the just-updated state. `prev_snapshot` below is exactly
    that saved snapshot, advanced one step behind the live model.

    Driving buttons and calling ref_model.step_frame() are kept strictly
    sequential in this test (not a separate background task) specifically
    to avoid any cross-task ordering ambiguity around that boundary."""
    dut._log.info("Start")

    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())

    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ReadOnly()

    cocotb.start_soon(vga_checker(dut))
    display = Display()
    cocotb.start_soon(display.consume(dut))

    ref_model = ReferenceModel()
    driver = PaddleDriver(dut)
    scoreboard = Scoreboard(display, ref_model)
    prev_snapshot = ref_model.render_frame()  # reset state, 0 moves applied

    # --- frame 0: reset state, matches the initial snapshot ---
    await ClockCycles(dut.clk, FRAME_CYCLES)
    assert not errors, f"{len(errors)} timing violations, first: {errors[:3]}"
    assert scoreboard.check_frame(display.history[-1][0], 0, "reset_state", prev_snapshot), \
        "frame 0 (reset state) did not match ReferenceModel"
    dut._log.info("frame 0 (reset state) matched")

    # --- serve: press P1 select. The captured frame after THIS wait still
    # reflects prev_snapshot (pre-serve) - the serve's own effect only
    # shows up starting the NEXT completion. ---
    driver.set_button("p1", "select", True)
    ref_model.step_frame(0, 0, 1, 0, 0, 0)
    await ClockCycles(dut.clk, FRAME_CYCLES)
    driver.set_button("p1", "select", False)
    assert not errors, f"{len(errors)} timing violations, first: {errors[:3]}"
    assert scoreboard.check_frame(display.history[-1][0], 1, "pre_serve_effect", prev_snapshot), \
        "frame 1 did not match the pre-serve snapshot"
    dut._log.info("frame 1 matched (still pre-serve effect, as expected)")
    prev_snapshot = ref_model.render_frame()  # now includes serve's atomic effect

    # --- a few more idle frames of straight travel ---
    for i in range(3):
        ref_model.step_frame(0, 0, 0, 0, 0, 0)
        await ClockCycles(dut.clk, FRAME_CYCLES)
        assert not errors, f"{len(errors)} timing violations, first: {errors[:3]}"
        assert scoreboard.check_frame(display.history[-1][0], 2 + i, f"travel_{i}", prev_snapshot), \
            f"frame {2+i} (travel) did not match ReferenceModel"
        dut._log.info(f"frame {2+i} matched (reflects state through the PREVIOUS move)")
        prev_snapshot = ref_model.render_frame()

    dut._log.info(f"ALL FRAMES MATCHED. Scoreboard fail_count={scoreboard.fail_count}")


N_RANDOM_FRAMES = 8
FULL_CHECK_EVERY = 3  # expensive full-frame diff only at checkpoints


@cocotb.test()
async def test_biased_random_play(dut):
    """Coverage-driven random play: both paddles track the ball with
    deviation probability (decide_biased_move), for N_RANDOM_FRAMES real
    frames after serve. Cheap per-frame invariant checks run every frame;
    expensive full-frame diffs only at checkpoints. vga_checker is
    deliberately NOT run here - it's already been proven exhaustively
    (vga_timing.v takes no game-state inputs at all, so one full-period
    check is exhaustive by construction, not a sample) - dropping it here
    cuts real per-cycle overhead for this longer run.

    Two screenshots are captured if run with `make PLUSARGS=+screenshot`:
    reset state and a mid-play frame.

    NB on coverage completeness: each real DUT frame costs ~100s wall
    clock in this environment (cocotb/VPI per-cycle overhead, not
    Verilator itself), so N_RANDOM_FRAMES here is deliberately modest -
    enough to prove the mechanism (driver decisions + model stepping +
    coverage marking + scoreboard all working together against real
    hardware), not enough to guarantee every coverage bin gets hit. Full
    closure (all 6 segments x 2 paddles, every limit, endgame, etc.) would
    need a much longer run - straightforward to extend, just costs
    proportionally more wall-clock time to actually execute."""
    dut._log.info("Start")

    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())

    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ReadOnly()

    display = Display()
    cocotb.start_soon(display.consume(dut))

    ref_model = ReferenceModel()
    driver = PaddleDriver(dut)
    scoreboard = Scoreboard(display, ref_model)
    coverage = Coverage()
    # See test_serve_and_ball_motion's docstring: a completed capture
    # always reflects the model state from BEFORE the most recently
    # applied step_frame() call, not the just-updated one.
    prev_snapshot = ref_model.render_frame()

    await ClockCycles(dut.clk, FRAME_CYCLES)  # frame 0: reset state
    maybe_capture_screenshot(display, "reset_state")

    driver.set_button("p1", "select", True)
    events = ref_model.step_frame(0, 0, 1, 0, 0, 0)
    coverage.mark_all(events)
    await ClockCycles(dut.clk, FRAME_CYCLES)
    driver.set_button("p1", "select", False)
    assert scoreboard.check_invariants()
    assert scoreboard.check_frame(display.history[-1][0], 1, "pre_serve_effect", prev_snapshot)
    prev_snapshot = ref_model.render_frame()
    dut._log.info(f"post-serve matched: ball at ({ref_model.ball_x},{ref_model.ball_y})")

    for i in range(N_RANDOM_FRAMES):
        p1_left, p1_right = decide_biased_move(ref_model, "p1")
        p2_left, p2_right = decide_biased_move(ref_model, "p2")
        driver.set_button("p1", "left", p1_left)
        driver.set_button("p1", "right", p1_right)
        driver.set_button("p2", "left", p2_left)
        driver.set_button("p2", "right", p2_right)

        events = ref_model.step_frame(p1_left, p1_right, 0, p2_left, p2_right, 0)
        coverage.mark_all(events)
        await ClockCycles(dut.clk, FRAME_CYCLES)

        assert scoreboard.check_invariants(), f"invariant violated at random frame {i}"
        if i == N_RANDOM_FRAMES // 2:
            maybe_capture_screenshot(display, "mid_random_play")
        if i % FULL_CHECK_EVERY == 0:
            assert scoreboard.check_frame(display.history[-1][0], 2 + i, f"random_{i}", prev_snapshot), \
                f"random-play frame {i} did not match ReferenceModel"
        prev_snapshot = ref_model.render_frame()
        if events:
            dut._log.info(f"random frame {i}: events={events} ball=({ref_model.ball_x},{ref_model.ball_y})")

    dut._log.info(f"Random play done. Scoreboard fail_count={scoreboard.fail_count}")
    dut._log.info(f"Coverage: {coverage.summary_str()}")
    assert scoreboard.fail_count == 0


@cocotb.test()
async def test_speedup_tier_transitions(dut):
    """White-box: force game_logic's hit_counter/velocity_y/
    latched_paddle_collision/latched_paddle_segment registers directly,
    timed to land one cycle before a real frame_pulse edge, and confirm the
    resulting velocity_x/velocity_y/hit_counter match ReferenceModel's
    prediction - at each of the three tier-transition boundaries (3->4,
    7->8, 11->12), for both an incoming-up and incoming-down ball.

    Deliberate, scoped break from black-box discipline: justified
    specifically for validating an internal counter's threshold behavior,
    which the rest of the (black-box, pixel-level) DV suite has no
    practical way to exercise without thousands of real frames of earning
    hits through actual rallying (~75-100s/frame here, so ~12 real frames
    for this whole test vs. ~2,800+ for a naturally-played equivalent).

    Timing: vga_timing.sv's frame_pulse = (hor_counter==799 &&
    vert_counter==524), i.e. exactly cycle FRAME_CYCLES-1 of every
    reset-aligned FRAME_CYCLES window. Running FRAME_CYCLES-1 cycles from a
    known-aligned start, forcing state, then stepping exactly one more edge
    lands precisely on the one edge that consumes the forced values -
    before any real driving logic (collision detection, the latch-clear
    block) gets a chance to intervene. ball_state_y is force-held in-bounds
    each time so the ball_out_of_bounds branch can't preempt the paddle-hit
    branch in game_logic.sv's next_velocity_x/y case block.

    hit_counter is forced DIRECTLY to each tier-boundary value (4, 8, 12)
    rather than to the pre-boundary value with an expected real increment:
    hit_counter only increments from `paddle_collision`, a game_logic
    MODULE INPUT PORT continuously driven by the real collision-detection
    logic elsewhere in pong.sv - forcing a continuously-driven port from
    cocotb is unreliable under Verilator (the real driver can win the race
    every delta cycle), unlike forcing an internal register such as
    hit_counter itself or latched_paddle_collision, which have no other
    driver on the cycle we care about. The increment arithmetic itself
    (`hit_counter + 1`) is trivial and already independently verified in
    test_speedup_model.py; this test's job is specifically the
    tier-selection combinational logic and the sign-fix, which only depend
    on hit_counter's VALUE, not on how it got there.
    """
    dut._log.info("Start")
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1

    gl = dut.user_project.pong.game_logic

    # Get to STATE_PLAYING via a real serve (not forced) - avoids fighting
    # game_state's own driving logic and matches how every other test enters
    # play.
    driver = PaddleDriver(dut)
    driver.set_button("p1", "select", True)
    await ClockCycles(dut.clk, FRAME_CYCLES)
    driver.set_button("p1", "select", False)
    await ReadOnly()
    assert int(gl.game_state.value) == 1, "expected STATE_PLAYING after serve"

    boundary_hcs = [ReferenceModel.SPEED2_CNT, ReferenceModel.SPEED3_CNT, ReferenceModel.SPEED4_CNT]
    segment = 0  # fixed; all (tier, segment) combinations already checked
                 # exhaustively in test_speedup_model.py - this test's job is
                 # only to confirm the REAL RTL's threshold/ordering/sign
                 # behavior, not to re-sweep segments.

    for target_hc in boundary_hcs:
        expected_tier = ReferenceModel._tier_for(target_hc)
        for incoming_vy in (-3, 3):
            # Run to exactly one cycle before the next frame_pulse edge.
            await ClockCycles(dut.clk, FRAME_CYCLES - 1)

            # Force state right before the frame_pulse edge.
            gl.hit_counter.value = target_hc
            gl.velocity_y.value = incoming_vy & 0xF
            gl.latched_paddle_collision.value = 1
            gl.latched_paddle_segment.value = segment
            gl.ball_state_y.value = ReferenceModel.INITIAL_BALL_Y * 2  # safely in-bounds

            await ClockCycles(dut.clk, 1)  # the frame_pulse edge itself
            await ReadOnly()

            actual_hit_counter = int(gl.hit_counter.value)
            actual_vx = _to_signed(int(gl.velocity_x.value), 4)
            actual_vy = _to_signed(int(gl.velocity_y.value), 4)

            expected_vx = ReferenceModel._SEGMENT_VX_TIERS[expected_tier][segment]
            expected_vy = (ReferenceModel._SPEED_FACTOR_Y[expected_tier] if incoming_vy < 0
                           else -ReferenceModel._SPEED_FACTOR_Y[expected_tier])

            # hit_counter isn't expected to change here (no real paddle_collision
            # pulse was driven) - this just confirms our force actually stuck.
            assert actual_hit_counter == target_hc, \
                f"hit_counter force didn't hold: expected {target_hc}, DUT has {actual_hit_counter}"
            assert actual_vx == expected_vx, \
                (f"tier {expected_tier} (hit_counter={target_hc}) segment {segment}: "
                 f"DUT vx={actual_vx}, expected vx={expected_vx}")
            assert actual_vy == expected_vy, \
                (f"tier {expected_tier} (hit_counter={target_hc}) incoming_vy={incoming_vy}: "
                 f"DUT vy={actual_vy}, expected vy={expected_vy}")
            dut._log.info(
                f"hit_counter={target_hc} (tier {expected_tier}), incoming_vy={incoming_vy}: "
                f"vx={actual_vx} vy={actual_vy} - matched expectation"
            )

    dut._log.info("All speed-tier transition checks matched the ReferenceModel")
