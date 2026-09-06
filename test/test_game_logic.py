# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

"""Unit-level directed tests for game_logic.sv, driven through
tb_game_logic.v (game_logic instantiated alone - no VGA timing chain).

Why this exists alongside the full-system suite in test.py: a full-system
frame costs 800*525 cycles of real pixel scan-out (~90-100s wall clock
here), which caps how many corner cases are reachable in practice. Driving
game_logic directly lets the driver pulse frame_pulse itself, so a frame
costs 2-4 cycles instead of 420,000. That turns "we can afford ~10 frames"
into "we can afford tens of thousands", which is what makes exhaustive
directed corner-case coverage of the state machine, the collision
resolution table, the paddle travel limits, the lives/end-of-game path and
the rally speed-up tiers actually affordable.

This does NOT replace the full-system tests - those are what prove
game_logic integrates correctly with the painters, collision detection and
video timing. These prove game_logic itself is right in the corners the
system-level suite can never reach.

Run:  make -f Makefile.game_logic
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, ReadOnly, NextTimeStep


def to_signed(raw: int, bits: int = 4) -> int:
    """Decode an unsigned raw bit pattern read back from a signed HDL net.
    Python's bitwise AND normalises either representation to the same
    low-order bits before the sign-bit check, so this is correct whether or
    not cocotb already sign-extended."""
    raw &= (1 << bits) - 1
    return raw - (1 << bits) if raw & (1 << (bits - 1)) else raw


class GameLogicUnit:
    """Driver + state accessor for the bare game_logic module.

    Frame model: in the real design, collision signals pulse during active
    video (mid-frame, as the ball/paddle pixels are scanned out) and
    frame_pulse fires once at the very end of the frame. This driver
    reproduces that ordering - assert collision inputs for some cycles,
    deassert, then pulse frame_pulse for exactly one cycle - without the
    420,000 cycles of scan-out in between.
    """

    STATE_START = 0
    STATE_PLAYING = 1

    # Mirrors tb_game_logic.v's parameter overrides (= pong.sv's).
    PADDLE_WIDTH = 24
    BORDER_WIDTH = 8
    INITIAL_BALL_X = 318
    INITIAL_BALL_Y = 338
    INITIAL_VEL_X = 0
    INITIAL_VEL_Y = 2
    INITIAL_PADDLE_X = 320 - PADDLE_WIDTH // 2 - 1  # 307

    # Paddle speed now scales with the same hit_counter tiers as the ball's
    # own speed-up (game_logic.sv: paddle_speed = speed4?TOP:speed3?MID:INIT -
    # note tier 1 (hit_counter 4-7) still maps to INIT, there's no distinct
    # paddle speed for it).
    PADDLE_SPEED_INIT = 2
    PADDLE_MID_SPEED = 3
    PADDLE_TOP_SPEED = 4

    # Paddle travel limits, in the RTL's own halved units (it compares
    # paddle_state_x[9:1], "ignoring the bottom bit to account for the
    # velocity of the paddle"). Note p1 and p2 are ASYMMETRIC in the RTL:
    # p1's left limit has a "-1", p2's does not.
    P1_LEFT_LIMIT = (BORDER_WIDTH >> 1) - 1                     # 3
    P2_LEFT_LIMIT = (BORDER_WIDTH >> 1)                         # 4
    RIGHT_LIMIT = (640 - BORDER_WIDTH - PADDLE_WIDTH) >> 1      # 304

    def __init__(self, dut):
        self.dut = dut
        self.gl = dut.game_logic  # the game_logic instance inside the tb

    async def start(self):
        cocotb.start_soon(Clock(self.dut.clk, 10, units="ns").start())
        self.dut.nRst.value = 0
        self.dut.frame_pulse.value = 0
        self.dut.p1_btn_action.value = 0
        self.dut.p1_btn_left.value = 0
        self.dut.p1_btn_right.value = 0
        self.dut.p2_btn_action.value = 0
        self.dut.p2_btn_left.value = 0
        self.dut.p2_btn_right.value = 0
        self.dut.collision.value = 0
        self.dut.paddle_collision.value = 0
        self.dut.paddle_segment.value = 0
        self.dut.ball_top_col.value = 0
        self.dut.ball_left_col.value = 0
        self.dut.ball_bottom_col.value = 0
        self.dut.ball_right_col.value = 0
        await ClockCycles(self.dut.clk, 5)
        self.dut.nRst.value = 1
        await ClockCycles(self.dut.clk, 2)

    async def frame(self, *, p1_left=0, p1_right=0, p1_action=0,
                    p2_left=0, p2_right=0, p2_action=0,
                    paddle_hit=False, segment=0,
                    top=0, left=0, bottom=0, right=0,
                    collision_cycles=1):
        """Advance exactly one frame.

        collision_cycles models how long the collision inputs stay asserted
        during scan-out. The real system holds them for many cycles (the
        ball/paddle overlap spans multiple pixels across multiple
        scanlines), so tests that care about that use a realistic width.
        """
        self.dut.p1_btn_left.value = int(p1_left)
        self.dut.p1_btn_right.value = int(p1_right)
        self.dut.p1_btn_action.value = int(p1_action)
        self.dut.p2_btn_left.value = int(p2_left)
        self.dut.p2_btn_right.value = int(p2_right)
        self.dut.p2_btn_action.value = int(p2_action)

        any_col = bool(paddle_hit or top or left or bottom or right)
        if any_col:
            # Scan-out phase: collisions detected while drawing.
            self.dut.collision.value = 1
            self.dut.paddle_collision.value = int(bool(paddle_hit))
            self.dut.paddle_segment.value = segment
            self.dut.ball_top_col.value = int(top)
            self.dut.ball_left_col.value = int(left)
            self.dut.ball_bottom_col.value = int(bottom)
            self.dut.ball_right_col.value = int(right)
            await ClockCycles(self.dut.clk, collision_cycles)
            self.dut.collision.value = 0
            self.dut.paddle_collision.value = 0
            self.dut.ball_top_col.value = 0
            self.dut.ball_left_col.value = 0
            self.dut.ball_bottom_col.value = 0
            self.dut.ball_right_col.value = 0
            await ClockCycles(self.dut.clk, 1)

        # End of frame.
        self.dut.frame_pulse.value = 1
        await ClockCycles(self.dut.clk, 1)
        self.dut.frame_pulse.value = 0
        await ClockCycles(self.dut.clk, 1)

    async def state(self) -> dict:
        """Sample all observable + internal state. Uses ReadOnly so values
        are settled (reading .value straight after an edge can return
        pre-NBA values), then NextTimeStep to return to a writable phase
        without consuming a clock cycle."""
        await ReadOnly()
        s = {
            "game_state": int(self.dut.game_state.value),
            "p1_lives": int(self.dut.p1_lives.value),
            "p2_lives": int(self.dut.p2_lives.value),
            "ball_x": int(self.dut.ball_x.value),
            "ball_y": int(self.dut.ball_y.value),
            "p1_paddle_x": int(self.dut.p1_paddle_x.value),
            "p2_paddle_x": int(self.dut.p2_paddle_x.value),
            "oob": int(self.dut.ball_out_of_bounds.value),
            "vx": to_signed(int(self.gl.velocity_x.value)),
            "vy": to_signed(int(self.gl.velocity_y.value)),
            "hit_counter": int(self.gl.hit_counter.value),
            "ball_state_x": int(self.gl.ball_state_x.value),
            "ball_state_y": int(self.gl.ball_state_y.value),
            "speed_tier": int(self.dut.speed_tier.value),
            "paddle_speed": int(self.dut.paddle_speed.value),
        }
        await NextTimeStep()
        return s

    async def force_ball_state_y(self, value: int):
        """Directed corner-case setup: jump the ball to a specific vertical
        position rather than spending frames travelling there. Used for the
        out-of-bounds threshold tests, where the interesting behaviour is
        at exact boundary values (487/488, 499/500)."""
        self.gl.ball_state_y.value = value
        await ClockCycles(self.dut.clk, 1)

    async def serve(self):
        """Reset -> PLAYING, via a real p1 action press."""
        await self.frame(p1_action=1)


# ---------------------------------------------------------------------------
# Reset / state machine
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_reset_state(dut):
    """Every reset value in game_logic, checked explicitly."""
    u = GameLogicUnit(dut)
    await u.start()
    s = await u.state()

    assert s["game_state"] == u.STATE_START, f"game_state should reset to START, got {s['game_state']}"
    assert s["p1_lives"] == 3, f"p1_lives should reset to 3, got {s['p1_lives']}"
    assert s["p2_lives"] == 3, f"p2_lives should reset to 3, got {s['p2_lives']}"
    assert s["ball_x"] == u.INITIAL_BALL_X, f"ball_x reset: expected {u.INITIAL_BALL_X}, got {s['ball_x']}"
    assert s["ball_y"] == u.INITIAL_BALL_Y, f"ball_y reset: expected {u.INITIAL_BALL_Y}, got {s['ball_y']}"
    assert s["p1_paddle_x"] == u.INITIAL_PADDLE_X, f"p1 paddle reset: got {s['p1_paddle_x']}"
    assert s["p2_paddle_x"] == u.INITIAL_PADDLE_X, f"p2 paddle reset: got {s['p2_paddle_x']}"
    assert s["vx"] == u.INITIAL_VEL_X, f"velocity_x reset: expected {u.INITIAL_VEL_X}, got {s['vx']}"
    assert s["vy"] == u.INITIAL_VEL_Y, f"velocity_y reset: expected {u.INITIAL_VEL_Y}, got {s['vy']}"
    assert s["hit_counter"] == 0, f"hit_counter should reset to 0, got {s['hit_counter']}"
    assert s["oob"] == 0, "ball should not be out of bounds at reset"


@cocotb.test()
async def test_start_state_idles_without_action(dut):
    """In START with no action button, velocity is forced to 0 and the ball
    does not move - however many frames pass."""
    u = GameLogicUnit(dut)
    await u.start()
    for _ in range(5):
        await u.frame()
    s = await u.state()
    assert s["game_state"] == u.STATE_START, "should still be in START"
    assert s["vx"] == 0 and s["vy"] == 0, f"velocity should be 0 while idle in START, got ({s['vx']},{s['vy']})"
    assert s["ball_x"] == u.INITIAL_BALL_X and s["ball_y"] == u.INITIAL_BALL_Y, "ball should not move in START"


@cocotb.test()
async def test_serve_from_p1_action(dut):
    """p1 action serves: START -> PLAYING, velocity loaded, and the ball
    advances by that velocity on the SAME frame_pulse (the serve and the
    first position advance are atomic in the RTL - next_velocity is
    combinational from the pre-edge STATE_START, and the same edge that
    moves game_state to PLAYING also applies it to ball_state)."""
    u = GameLogicUnit(dut)
    await u.start()
    await u.frame(p1_action=1)
    s = await u.state()
    assert s["game_state"] == u.STATE_PLAYING, "p1 action should start the game"
    assert s["vx"] == u.INITIAL_VEL_X and s["vy"] == u.INITIAL_VEL_Y, \
        f"serve velocity: expected ({u.INITIAL_VEL_X},{u.INITIAL_VEL_Y}), got ({s['vx']},{s['vy']})"
    assert s["ball_state_y"] == u.INITIAL_BALL_Y * 2 + u.INITIAL_VEL_Y, \
        f"serve should advance the ball atomically, ball_state_y={s['ball_state_y']}"


@cocotb.test()
async def test_serve_from_p2_action(dut):
    """Either player's action button can serve."""
    u = GameLogicUnit(dut)
    await u.start()
    await u.frame(p2_action=1)
    s = await u.state()
    assert s["game_state"] == u.STATE_PLAYING, "p2 action should also start the game"
    assert s["vy"] == u.INITIAL_VEL_Y, f"serve velocity_y: got {s['vy']}"


@cocotb.test()
async def test_ball_travels_each_frame(dut):
    """With no collisions, the ball advances by exactly velocity each
    frame_pulse and velocity is unchanged."""
    u = GameLogicUnit(dut)
    await u.start()
    await u.serve()
    s0 = await u.state()
    for i in range(10):
        before = await u.state()
        await u.frame()
        after = await u.state()
        assert after["ball_state_y"] == before["ball_state_y"] + before["vy"], \
            f"frame {i}: ball_state_y {before['ball_state_y']} + vy {before['vy']} != {after['ball_state_y']}"
        assert after["vy"] == before["vy"], f"frame {i}: velocity changed with no collision"
    assert s0["game_state"] == u.STATE_PLAYING


# ---------------------------------------------------------------------------
# Collision resolution
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_paddle_hit_all_segments_tier0(dut):
    """Every paddle segment 0-5 maps to the correct base-tier vx.

    Each iteration re-resets so hit_counter starts at 0 and the hit lands in
    tier 0 - segment->vx is what's under test here, not the tier logic.
    """
    expected_vx = {0: -3, 1: -2, 2: -1, 3: 1, 4: 2, 5: 3}
    for segment, want_vx in expected_vx.items():
        u = GameLogicUnit(dut)
        await u.start()
        await u.serve()
        await u.frame(paddle_hit=True, segment=segment)
        s = await u.state()
        assert s["vx"] == want_vx, \
            f"segment {segment}: expected vx={want_vx}, got {s['vx']}"


@cocotb.test()
async def test_paddle_hit_reverses_vy_both_directions(dut):
    """A paddle hit reverses vertical direction rather than always forcing
    one sign - checked for a ball arriving downward and upward."""
    u = GameLogicUnit(dut)
    await u.start()
    await u.serve()  # serve gives vy = +2 (downward)
    s_before = await u.state()
    assert s_before["vy"] > 0, "setup: expected a downward-moving ball after serve"
    await u.frame(paddle_hit=True, segment=3)
    s = await u.state()
    assert s["vy"] < 0, f"downward ball should bounce upward, got vy={s['vy']}"

    # Now the ball is moving up; the next hit must send it back down.
    await u.frame(paddle_hit=True, segment=3)
    s2 = await u.state()
    assert s2["vy"] > 0, f"upward ball should bounce downward, got vy={s2['vy']}"


@cocotb.test()
async def test_paddle_segment_out_of_range_holds_velocity(dut):
    """paddle_segment is 3 bits but only 6 segments exist. The unreachable
    encodings 110/111 must fall through to 'velocity unchanged' (the
    default arm that stops Yosys inferring a latch), not corrupt vx."""
    for segment in (6, 7):
        u = GameLogicUnit(dut)
        await u.start()
        await u.serve()
        await u.frame(paddle_hit=True, segment=3)  # get a known non-zero vx
        before = await u.state()
        await u.frame(paddle_hit=True, segment=segment)
        after = await u.state()
        assert after["vx"] == before["vx"], \
            f"segment {segment} should hold vx at {before['vx']}, got {after['vx']}"


@cocotb.test()
async def test_wall_bounce_top_and_bottom(dut):
    """Top/bottom wall collision negates vy and leaves vx alone."""
    for label, flags in (("top", {"top": 1}), ("bottom", {"bottom": 1})):
        u = GameLogicUnit(dut)
        await u.start()
        await u.serve()
        await u.frame(paddle_hit=True, segment=5)  # give vx a known non-zero value
        before = await u.state()
        await u.frame(**flags)
        after = await u.state()
        assert after["vy"] == -before["vy"], \
            f"{label} bounce: vy should negate {before['vy']} -> {-before['vy']}, got {after['vy']}"
        assert after["vx"] == before["vx"], \
            f"{label} bounce: vx should be unchanged at {before['vx']}, got {after['vx']}"


@cocotb.test()
async def test_wall_bounce_left_and_right(dut):
    """Left/right wall collision negates vx and leaves vy alone."""
    for label, flags in (("left", {"left": 1}), ("right", {"right": 1})):
        u = GameLogicUnit(dut)
        await u.start()
        await u.serve()
        await u.frame(paddle_hit=True, segment=5)  # non-zero vx to negate
        before = await u.state()
        await u.frame(**flags)
        after = await u.state()
        assert after["vx"] == -before["vx"], \
            f"{label} bounce: vx should negate {before['vx']} -> {-before['vx']}, got {after['vx']}"
        assert after["vy"] == before["vy"], \
            f"{label} bounce: vy should be unchanged at {before['vy']}, got {after['vy']}"


@cocotb.test()
async def test_paddle_hit_takes_priority_over_wall(dut):
    """The RTL checks latched_paddle_collision BEFORE the wall OR-tables, so
    a simultaneous paddle+wall collision resolves as a paddle hit."""
    u = GameLogicUnit(dut)
    await u.start()
    await u.serve()
    await u.frame(paddle_hit=True, segment=0, top=1)
    s = await u.state()
    assert s["vx"] == -3, f"paddle hit should win over the wall table, expected vx=-3, got {s['vx']}"


# ---------------------------------------------------------------------------
# Out of bounds / lives / end of game
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_oob_p1_threshold(dut):
    """p1 loses a life when ball_state_y[10:1] reaches 488 - and not at 487."""
    u = GameLogicUnit(dut)
    await u.start()
    await u.serve()

    await u.force_ball_state_y(487 * 2)
    s = await u.state()
    assert s["oob"] == 0, "487 should NOT be out of bounds"

    await u.force_ball_state_y(488 * 2)
    s = await u.state()
    assert s["oob"] == 1, "488 should be out of bounds"

    await u.frame()
    s = await u.state()
    assert s["p1_lives"] == 2, f"p1 should lose a life, got {s['p1_lives']}"
    assert s["p2_lives"] == 3, f"p2 lives should be untouched, got {s['p2_lives']}"
    assert s["game_state"] == u.STATE_START, "should return to START after a point"
    assert s["ball_x"] == u.INITIAL_BALL_X and s["ball_y"] == u.INITIAL_BALL_Y, "ball should reset"
    assert s["p1_paddle_x"] == u.INITIAL_PADDLE_X, "p1 paddle should reset"
    assert s["p2_paddle_x"] == u.INITIAL_PADDLE_X, "p2 paddle should reset"


@cocotb.test()
async def test_oob_p2_threshold(dut):
    """p2 loses a life at >= 500, which also takes priority over the p1
    condition (p1's is gated on !p2_out)."""
    u = GameLogicUnit(dut)
    await u.start()
    await u.serve()

    await u.force_ball_state_y(499 * 2)
    s = await u.state()
    assert s["oob"] == 1, "499 is past 488, so it is out of bounds (as p1's)"

    await u.force_ball_state_y(500 * 2)
    await u.frame()
    s = await u.state()
    assert s["p2_lives"] == 2, f"p2 should lose the life at >=500, got {s['p2_lives']}"
    assert s["p1_lives"] == 3, f"p1 lives should be untouched, got {s['p1_lives']}"


@cocotb.test()
async def test_lives_count_down_to_zero(dut):
    """Three successive p1 points take p1 from 3 to 0."""
    u = GameLogicUnit(dut)
    await u.start()
    for expected in (2, 1, 0):
        await u.serve()
        await u.force_ball_state_y(488 * 2)
        await u.frame()
        s = await u.state()
        assert s["p1_lives"] == expected, f"expected p1_lives={expected}, got {s['p1_lives']}"


@cocotb.test()
async def test_end_of_game_resets_lives_and_hit_counter(dut):
    """Once a player is at 0 lives, their next concession is end_of_game:
    lives reload to 3 and hit_counter clears."""
    u = GameLogicUnit(dut)
    await u.start()
    for _ in range(3):  # drain p1 to zero
        await u.serve()
        await u.force_ball_state_y(488 * 2)
        await u.frame()
    s = await u.state()
    assert s["p1_lives"] == 0, f"setup: expected p1 at 0 lives, got {s['p1_lives']}"

    # Build up some rally count, then concede again -> end of game.
    await u.serve()
    await u.frame(paddle_hit=True, segment=2)
    mid = await u.state()
    assert mid["hit_counter"] > 0, "setup: expected a non-zero hit_counter before end of game"

    await u.force_ball_state_y(488 * 2)
    await u.frame()
    s = await u.state()
    assert s["p1_lives"] == 3, f"end of game should reload p1 lives to 3, got {s['p1_lives']}"
    assert s["hit_counter"] == 0, f"end of game should clear hit_counter, got {s['hit_counter']}"
    assert s["game_state"] == u.STATE_START, "end of game should return to START"


# ---------------------------------------------------------------------------
# Paddle movement and travel limits
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_paddle_movement_directions(dut):
    """Each paddle moves by the current paddle_speed in the commanded
    direction - PADDLE_SPEED_INIT (tier 0, right after serve) here."""
    u = GameLogicUnit(dut)
    await u.start()
    await u.serve()
    base = await u.state()
    assert base["paddle_speed"] == u.PADDLE_SPEED_INIT, \
        f"setup: expected tier-0 paddle_speed={u.PADDLE_SPEED_INIT}, got {base['paddle_speed']}"

    await u.frame(p1_left=1)
    s = await u.state()
    assert s["p1_paddle_x"] == base["p1_paddle_x"] - u.PADDLE_SPEED_INIT, f"p1 left: got {s['p1_paddle_x']}"

    await u.frame(p1_right=1)
    s = await u.state()
    assert s["p1_paddle_x"] == base["p1_paddle_x"], f"p1 right should return it: got {s['p1_paddle_x']}"

    await u.frame(p2_left=1)
    s = await u.state()
    assert s["p2_paddle_x"] == base["p2_paddle_x"] - u.PADDLE_SPEED_INIT, f"p2 left: got {s['p2_paddle_x']}"

    await u.frame(p2_right=1)
    s = await u.state()
    assert s["p2_paddle_x"] == base["p2_paddle_x"], f"p2 right should return it: got {s['p2_paddle_x']}"


@cocotb.test()
async def test_paddle_both_buttons_left_wins(dut):
    """Left is checked first in the RTL's if/else chain, so pressing both
    moves left."""
    u = GameLogicUnit(dut)
    await u.start()
    await u.serve()
    before = await u.state()
    await u.frame(p1_left=1, p1_right=1)
    after = await u.state()
    assert after["p1_paddle_x"] == before["p1_paddle_x"] - before["paddle_speed"], \
        f"both buttons should move left, got {after['p1_paddle_x']} from {before['p1_paddle_x']}"


@cocotb.test()
async def test_paddle_left_limits_are_asymmetric(dut):
    """p1 and p2 have genuinely different left limits in the RTL (p1's
    formula has a '-1', p2's does not), so they stop at different pixels.
    Driven naturally all the way to the wall - ~300 frames, which is
    affordable here but would be ~8 hours through the full-system bench."""
    u = GameLogicUnit(dut)
    await u.start()
    # Deliberately NOT serving: paddle movement isn't gated on game_state, and
    # staying in START keeps the ball parked so it can't go out of bounds
    # mid-sweep (an OOB frame resets both paddles to centre).
    for _ in range(320):
        await u.frame(p1_left=1, p2_left=1)
    s = await u.state()
    assert (s["p1_paddle_x"] >> 1) == u.P1_LEFT_LIMIT, \
        f"p1 should stop at halved limit {u.P1_LEFT_LIMIT}, got {s['p1_paddle_x'] >> 1} (x={s['p1_paddle_x']})"
    assert (s["p2_paddle_x"] >> 1) == u.P2_LEFT_LIMIT, \
        f"p2 should stop at halved limit {u.P2_LEFT_LIMIT}, got {s['p2_paddle_x'] >> 1} (x={s['p2_paddle_x']})"
    assert s["p1_paddle_x"] != s["p2_paddle_x"], \
        "p1 and p2 left limits are asymmetric in the RTL and should differ"


@cocotb.test()
async def test_paddle_right_limits(dut):
    """Both paddles stop at the same right-hand limit."""
    u = GameLogicUnit(dut)
    await u.start()
    # See test_paddle_left_limits_are_asymmetric: no serve, so the parked ball
    # can't trigger an OOB paddle reset mid-sweep.
    for _ in range(320):
        await u.frame(p1_right=1, p2_right=1)
    s = await u.state()
    assert (s["p1_paddle_x"] >> 1) == u.RIGHT_LIMIT, \
        f"p1 right limit: expected halved {u.RIGHT_LIMIT}, got {s['p1_paddle_x'] >> 1}"
    assert (s["p2_paddle_x"] >> 1) == u.RIGHT_LIMIT, \
        f"p2 right limit: expected halved {u.RIGHT_LIMIT}, got {s['p2_paddle_x'] >> 1}"


@cocotb.test()
async def test_paddle_reset_beats_movement_on_oob(dut):
    """On an out-of-bounds frame the paddles snap back to their initial
    position even if a movement button is held that same frame (the RTL
    checks ball_out_of_bounds first in the if/else chain)."""
    u = GameLogicUnit(dut)
    await u.start()
    await u.serve()
    for _ in range(10):
        await u.frame(p1_left=1)
    moved = await u.state()
    assert moved["p1_paddle_x"] != u.INITIAL_PADDLE_X, "setup: paddle should have moved"

    await u.force_ball_state_y(488 * 2)
    await u.frame(p1_left=1)
    s = await u.state()
    assert s["p1_paddle_x"] == u.INITIAL_PADDLE_X, \
        f"paddle should reset on OOB despite the held button, got {s['p1_paddle_x']}"


@cocotb.test()
async def test_paddle_speed_scales_with_tier(dut):
    """paddle_speed/speed_tier must track the same hit_counter thresholds as
    the ball's own speed tiers, and the paddle's actual per-frame
    displacement must match paddle_speed exactly at each one. Tier 1
    (hit_counter 4-7) has no distinct paddle speed of its own - it still
    maps to PADDLE_SPEED_INIT, matching game_logic.sv's
    speed4?TOP:speed3?MID:INIT."""
    expected = {
        0: (0, GameLogicUnit.PADDLE_SPEED_INIT),
        4: (1, GameLogicUnit.PADDLE_SPEED_INIT),
        8: (2, GameLogicUnit.PADDLE_MID_SPEED),
        12: (3, GameLogicUnit.PADDLE_TOP_SPEED),
    }
    u = GameLogicUnit(dut)
    await u.start()
    await u.serve()

    for target_hits in sorted(expected):
        while (await u.state())["hit_counter"] < target_hits:
            await u.frame(paddle_hit=True, segment=3)
        want_tier, want_speed = expected[target_hits]
        s = await u.state()
        assert s["speed_tier"] == want_tier, \
            f"hit_counter={s['hit_counter']}: expected speed_tier={want_tier}, got {s['speed_tier']}"
        assert s["paddle_speed"] == want_speed, \
            f"hit_counter={s['hit_counter']}: expected paddle_speed={want_speed}, got {s['paddle_speed']}"

        before = await u.state()
        await u.frame(p1_left=1)
        after = await u.state()
        moved = before["p1_paddle_x"] - after["p1_paddle_x"]
        assert moved == want_speed, \
            f"at paddle_speed={want_speed}, one left press should move {want_speed}px, moved {moved}"


@cocotb.test()
async def test_paddle_limits_no_overshoot_at_every_speed(dut):
    """The paddle-limit clamp must land EXACTLY on the true boundary and
    never overshoot or underflow/wrap, at every paddle_speed tier (2, 3, 4).
    This is the exact defect class that made the AI paddle wrap around the
    left edge and reappear on the right at top speed.

    hit_counter is forced directly (white-box) rather than earned through
    simulated hits, and the ball is deliberately never served (game_state
    stays START) - paddle movement isn't gated on game_state at all, and
    parking the ball means it can never go out of bounds mid-sweep and
    reset both paddles back to centre (same technique as
    test_paddle_left_limits_are_asymmetric/test_paddle_right_limits).
    """
    RIGHT_LIMIT_RAW = 640 - GameLogicUnit.BORDER_WIDTH - GameLogicUnit.PADDLE_WIDTH
    P1_LEFT_LIMIT_RAW = 2 * ((GameLogicUnit.BORDER_WIDTH >> 1) - 1) + 1
    P2_LEFT_LIMIT_RAW = 2 * (GameLogicUnit.BORDER_WIDTH >> 1) + 1

    speed_for_hits = {
        0: GameLogicUnit.PADDLE_SPEED_INIT,
        8: GameLogicUnit.PADDLE_MID_SPEED,
        12: GameLogicUnit.PADDLE_TOP_SPEED,
    }

    for target_hits, want_speed in speed_for_hits.items():
        u = GameLogicUnit(dut)
        await u.start()
        u.gl.hit_counter.value = target_hits
        await ClockCycles(dut.clk, 1)
        s = await u.state()
        assert s["paddle_speed"] == want_speed, \
            f"setup: forcing hit_counter={target_hits} should give paddle_speed={want_speed}, got {s['paddle_speed']}"

        for _ in range(200):
            await u.frame(p1_left=1, p2_left=1)
        s = await u.state()
        assert s["p1_paddle_x"] == P1_LEFT_LIMIT_RAW, \
            f"p1 left @ speed={want_speed}: expected {P1_LEFT_LIMIT_RAW}, got {s['p1_paddle_x']}"
        assert s["p2_paddle_x"] == P2_LEFT_LIMIT_RAW, \
            f"p2 left @ speed={want_speed}: expected {P2_LEFT_LIMIT_RAW}, got {s['p2_paddle_x']}"
        assert s["p1_paddle_x"] < 100 and s["p2_paddle_x"] < 100, \
            f"possible wraparound on left sweep: p1={s['p1_paddle_x']} p2={s['p2_paddle_x']}"

        for _ in range(400):
            await u.frame(p1_right=1, p2_right=1)
        s = await u.state()
        assert s["p1_paddle_x"] == RIGHT_LIMIT_RAW, \
            f"p1 right @ speed={want_speed}: expected {RIGHT_LIMIT_RAW}, got {s['p1_paddle_x']}"
        assert s["p2_paddle_x"] == RIGHT_LIMIT_RAW, \
            f"p2 right @ speed={want_speed}: expected {RIGHT_LIMIT_RAW}, got {s['p2_paddle_x']}"


# ---------------------------------------------------------------------------
# Rally speed-up
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_hit_counter_increments_once_per_hit(dut):
    """One paddle hit must advance hit_counter by exactly one.

    NB collision_cycles=20 models what the integrated design actually does:
    paddle_collision is `draw_paddle && draw_ball`, a per-pixel signal that
    stays asserted for the whole ball/paddle pixel overlap (several pixels
    across several scanlines), not a single-cycle pulse.
    """
    u = GameLogicUnit(dut)
    await u.start()
    await u.serve()
    for expected in (1, 2, 3):
        await u.frame(paddle_hit=True, segment=3, collision_cycles=20)
        s = await u.state()
        assert s["hit_counter"] == expected, \
            f"expected hit_counter={expected} after {expected} hit(s), got {s['hit_counter']}"


@cocotb.test()
async def test_speed_tiers_by_natural_rally(dut):
    """Play a real rally and confirm the speed tiers engage at the right hit
    counts: tier 0 (|vy|=2) below 4 hits, tier 1 (4) at 4, tier 2 (5) at 8,
    tier 3 (6) at 12."""
    expected_vy_mag = {1: 2, 2: 2, 3: 2, 4: 4, 5: 4, 6: 4, 7: 4,
                       8: 5, 9: 5, 10: 5, 11: 5, 12: 6, 13: 6}
    u = GameLogicUnit(dut)
    await u.start()
    await u.serve()
    for hit in range(1, 14):
        await u.frame(paddle_hit=True, segment=3)
        s = await u.state()
        assert s["hit_counter"] == hit, \
            f"hit {hit}: hit_counter should be {hit}, got {s['hit_counter']}"
        assert abs(s["vy"]) == expected_vy_mag[hit], \
            f"hit {hit} (hit_counter={s['hit_counter']}): expected |vy|={expected_vy_mag[hit]}, got {abs(s['vy'])}"


@cocotb.test()
async def test_hit_counter_saturates(dut):
    """hit_counter is 4 bits and must saturate at 15, never wrap to 0 (a
    wrap would drop the ball back to base speed mid-rally)."""
    u = GameLogicUnit(dut)
    await u.start()
    await u.serve()
    for _ in range(20):
        await u.frame(paddle_hit=True, segment=3)
    s = await u.state()
    assert s["hit_counter"] == 15, f"hit_counter should saturate at 15, got {s['hit_counter']}"
    assert abs(s["vy"]) == 6, f"should still be at top tier, got |vy|={abs(s['vy'])}"


@cocotb.test()
async def test_speed_persists_across_points(dut):
    """hit_counter deliberately survives a lost point (it only clears on
    end_of_game), so the rally speed carries across serves within a game."""
    u = GameLogicUnit(dut)
    await u.start()
    await u.serve()
    for _ in range(5):
        await u.frame(paddle_hit=True, segment=3)
    before = await u.state()
    assert before["hit_counter"] == 5, f"setup: got {before['hit_counter']}"

    await u.force_ball_state_y(488 * 2)
    await u.frame()
    s = await u.state()
    assert s["p1_lives"] == 2, "setup: expected a lost point"
    assert s["hit_counter"] == 5, \
        f"hit_counter should survive an ordinary point loss, got {s['hit_counter']}"


# ---------------------------------------------------------------------------
# Gameplay-level reproduction
# ---------------------------------------------------------------------------

# Geometry mirrored from pong.sv's painter instantiations. Approximate at the
# pixel-edge level (the painters have a one-cycle render lag the full-system
# bench models exactly), but faithful enough to reproduce gameplay behaviour -
# which is what this test is for.
P1_PADDLE_Y = 456
P2_PADDLE_Y = 16
PADDLE_HEIGHT = 8
BALL_SIZE = 5
SCREEN_W = 640
BORDER_W = 8

# The real paddle_collision is `draw_paddle && draw_ball`, a per-pixel signal
# asserted for the whole ball/paddle pixel overlap - several pixels across
# several scanlines, NOT a single-cycle pulse.
REALISTIC_COLLISION_CYCLES = 20


def _overlaps_paddle(ball_x, ball_y, paddle_x, paddle_y):
    """Does the ball's bounding box overlap this paddle's?"""
    v = (ball_y + BALL_SIZE - 1) >= paddle_y and ball_y <= (paddle_y + PADDLE_HEIGHT - 1)
    h = (ball_x + BALL_SIZE - 1) >= paddle_x and ball_x <= (paddle_x + GameLogicUnit.PADDLE_WIDTH - 1)
    return v and h


@cocotb.test()
async def test_ball_does_not_pass_through_a_perfectly_placed_paddle(dut):
    """Gameplay-level reproduction of the fall-through seen on hardware.

    Both paddles are modelled as PERFECT trackers - always horizontally
    centred on the ball - and collision inputs are driven from the DUT's own
    reported ball position each frame, with the realistic multi-cycle
    collision width the integrated design actually produces. Under those
    conditions neither player can ever legitimately lose a life: any life
    lost means the ball passed straight through a paddle that was in
    exactly the right place.
    """
    u = GameLogicUnit(dut)
    await u.start()
    await u.serve()

    for frame_no in range(400):
        s = await u.state()

        if s["p1_lives"] != 3 or s["p2_lives"] != 3:
            raise AssertionError(
                f"frame {frame_no}: ball passed through a perfectly-placed paddle "
                f"(p1_lives={s['p1_lives']}, p2_lives={s['p2_lives']}) - "
                f"ball=({s['ball_x']},{s['ball_y']}) v=({s['vx']},{s['vy']}) "
                f"hit_counter={s['hit_counter']}"
            )

        ball_x, ball_y = s["ball_x"], s["ball_y"]
        # Perfect defence: centre each paddle under the ball.
        paddle_x = max(0, ball_x + BALL_SIZE // 2 - u.PADDLE_WIDTH // 2)

        hit_p1 = _overlaps_paddle(ball_x, ball_y, paddle_x, P1_PADDLE_Y)
        hit_p2 = _overlaps_paddle(ball_x, ball_y, paddle_x, P2_PADDLE_Y)
        paddle_hit = hit_p1 or hit_p2
        # Ball centred on the paddle lands in the middle segments.
        segment = 3 if s["vx"] >= 0 else 2

        # Side borders.
        left_col = ball_x <= BORDER_W - 1
        right_col = (ball_x + BALL_SIZE - 1) >= SCREEN_W - BORDER_W

        await u.frame(
            paddle_hit=paddle_hit,
            segment=segment,
            left=int(left_col and not paddle_hit),
            right=int(right_col and not paddle_hit),
            collision_cycles=REALISTIC_COLLISION_CYCLES if paddle_hit else 1,
        )
