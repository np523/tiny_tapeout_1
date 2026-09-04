# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

"""Exhaustive, pure-Python check of ReferenceModel's rally speed-up logic
(no cocotb, no simulator - runs in well under a second). This is Plan A of
the speed-up verification: prove the (corrected) oracle is internally
consistent and bit-exact against game_logic.sv's hit_counter/speed_factor_x/
speed_factor_y logic, BEFORE trusting it as the reference for a targeted
white-box DUT test (Plan B).

Run directly: `python3 test_speedup_model.py` (prints PASS/FAIL, exits
nonzero on any failure) - deliberately not pytest-based so it has zero
dependencies beyond the stdlib and ReferenceModel itself.
"""

import sys

from test import ReferenceModel

FAILURES = []


def check(condition: bool, msg: str):
    if not condition:
        FAILURES.append(msg)


def tier_for_reference(hit_counter: int) -> int:
    """Independent re-derivation of the tier boundary logic (NOT calling
    ReferenceModel._tier_for) so this test doesn't just check the model
    against itself."""
    t = 0
    if hit_counter >= ReferenceModel.SPEED2_CNT:
        t = 1
    if hit_counter >= ReferenceModel.SPEED3_CNT:
        t = 2
    if hit_counter >= ReferenceModel.SPEED4_CNT:
        t = 3
    return t


def test_tier_boundaries_exhaustive():
    """Sweep every hit_counter value 0..15 (the full 4-bit range, including
    above the highest real threshold) and confirm the tier classification
    matches an independently-derived expectation."""
    for hc in range(16):
        expected_tier = tier_for_reference(hc)
        actual_tier = ReferenceModel._tier_for(hc)
        check(actual_tier == expected_tier,
              f"hit_counter={hc}: expected tier {expected_tier}, got {actual_tier}")


def test_saturation_no_wrap():
    """hit_counter must saturate at 15, never wrap to 0."""
    m = ReferenceModel()
    m.game_state = "PLAYING"
    m.hit_counter = ReferenceModel.HIT_CNT_MAX
    for _ in range(5):
        m._resolve_paddle_hit(segment=3)
        check(m.hit_counter == ReferenceModel.HIT_CNT_MAX,
              f"hit_counter should saturate at {ReferenceModel.HIT_CNT_MAX}, got {m.hit_counter}")


def test_transition_hits_land_on_correct_tier():
    """The specific hit that CROSSES each threshold (hit_counter 3->4,
    7->8, 11->12) must itself already be evaluated at the NEW (post-
    increment) tier - this is the exact ordering game_logic.sv implements
    (hit_counter increments earlier in the frame than the velocity
    case-block that consumes it), and the exact thing a naive
    pre-increment model would get wrong."""
    transitions = [
        (3, 0, 1),   # hit_counter 3 -> 4: pre-hit tier 0, this hit lands in tier 1
        (7, 1, 2),   # 7 -> 8: pre-hit tier 1, this hit lands in tier 2
        (11, 2, 3),  # 11 -> 12: pre-hit tier 2, this hit lands in tier 3
    ]
    for pre_hc, pre_tier, post_tier in transitions:
        m = ReferenceModel()
        m.game_state = "PLAYING"
        m.hit_counter = pre_hc
        check(ReferenceModel._tier_for(pre_hc) == pre_tier,
              f"setup error: hit_counter={pre_hc} should pre-classify as tier {pre_tier}")
        tier_used = m._resolve_paddle_hit(segment=3)
        check(m.hit_counter == pre_hc + 1,
              f"hit_counter should be {pre_hc + 1} after one hit, got {m.hit_counter}")
        check(tier_used == post_tier,
              f"hit_counter {pre_hc}->{pre_hc+1}: expected the crossing hit itself "
              f"to use tier {post_tier}, got tier {tier_used}")


def test_segment_vx_tables_exhaustive():
    """Every (tier, segment) combination's vx must match game_logic.sv's
    four case(speed_factor_x) blocks (lines 218-287), bit-exact, and every
    magnitude must respect the tunneling-safety ceiling."""
    expected = {
        0: {0: -3, 1: -2, 2: -1, 3: 1, 4: 2, 5: 3},
        1: {0: -4, 1: -3, 2: -2, 3: 2, 4: 3, 5: 4},
        2: {0: -5, 1: -4, 2: -3, 3: 3, 4: 4, 5: 5},
        3: {0: -7, 1: -6, 2: -5, 3: 5, 4: 6, 5: 7},
    }
    for tier in range(4):
        for segment in range(6):
            m = ReferenceModel()
            m.game_state = "PLAYING"
            m.velocity_y = 2  # arbitrary nonzero, sign checked separately
            # Drive hit_counter to exactly the value that lands THIS hit in `tier`.
            target_hc = {0: 0, 1: ReferenceModel.SPEED2_CNT - 1,
                         2: ReferenceModel.SPEED3_CNT - 1,
                         3: ReferenceModel.SPEED4_CNT - 1}[tier]
            m.hit_counter = target_hc
            tier_used = m._resolve_paddle_hit(segment)
            check(tier_used == tier,
                  f"setup error driving tier {tier} via hit_counter={target_hc}")
            check(m.velocity_x == expected[tier][segment],
                  f"tier {tier} segment {segment}: expected vx={expected[tier][segment]}, "
                  f"got {m.velocity_x}")
            check(-8 <= m.velocity_x <= 7,
                  f"tier {tier} segment {segment}: vx={m.velocity_x} outside safe 4-bit range")


def test_vy_sign_flips_both_directions():
    """The specific bug class this whole exercise exists to catch: vy must
    REVERSE relative to the ball's incoming direction (paddle bounce), not
    always go negative. Checked at every tier, for both a ball arriving
    moving up (vy<0, should bounce to +magnitude) and moving down (vy>=0,
    should bounce to -magnitude), and for both paddles (P1/bottom hits a
    downward-moving ball in normal play, P2/top hits an upward-moving one -
    this test doesn't assume which paddle sees which sign, it just checks
    both signs land correctly regardless of which paddle triggered it)."""
    expected_mag = {0: 2, 1: 4, 2: 6, 3: 7}
    for tier in range(4):
        target_hc = {0: 0, 1: ReferenceModel.SPEED2_CNT - 1,
                     2: ReferenceModel.SPEED3_CNT - 1,
                     3: ReferenceModel.SPEED4_CNT - 1}[tier]
        for incoming_vy, expected_vy in ((-3, expected_mag[tier]), (3, -expected_mag[tier])):
            m = ReferenceModel()
            m.game_state = "PLAYING"
            m.velocity_y = incoming_vy
            m.hit_counter = target_hc
            m._resolve_paddle_hit(segment=0)
            check(m.velocity_y == expected_vy,
                  f"tier {tier}, incoming vy={incoming_vy}: expected bounced vy={expected_vy}, "
                  f"got {m.velocity_y}")
            check(-8 <= m.velocity_y <= 7,
                  f"tier {tier}: vy={m.velocity_y} outside safe 4-bit range")


def test_end_of_game_resets_hit_counter():
    """game_logic.sv line 83: hit_counter resets on `!nRst || end_of_game`,
    NOT on every point/serve - persists across rallies within a game,
    only clears when the game itself ends (matches the actual committed
    RTL, not the original rtl-plan.md draft which specified per-point
    reset)."""
    m = ReferenceModel()
    m.game_state = "PLAYING"
    m.hit_counter = 9
    # end_of_game fires when the player who JUST lost the point was
    # ALREADY at 0 lives (game_logic.sv: end_of_game checks p1_out_of_lives
    # BEFORE this frame's decrement, i.e. p1_lives==0 already).
    m.p1_lives = 0
    m.p1_paddle_x = m.INITIAL_PADDLE_X
    m.p2_paddle_x = m.INITIAL_PADDLE_X
    # Force a p1-out-of-bounds condition that also ends the game.
    m.ball_state_y = 489 * 2  # matches "p1_out" threshold (>=488, <500)
    events = m.step_frame(0, 0, 0, 0, 0, 0)
    check(("endgame", None) in events, f"expected an endgame event, got {events}")
    check(m.hit_counter == 0, f"hit_counter should reset to 0 on end_of_game, got {m.hit_counter}")

    # Sanity: an ordinary (non-endgame) point loss must NOT reset it.
    m2 = ReferenceModel()
    m2.game_state = "PLAYING"
    m2.hit_counter = 9
    m2.p1_lives = 3
    m2.p1_paddle_x = m2.INITIAL_PADDLE_X
    m2.p2_paddle_x = m2.INITIAL_PADDLE_X
    m2.ball_state_y = 489 * 2
    events2 = m2.step_frame(0, 0, 0, 0, 0, 0)
    check(("endgame", None) not in events2, f"did not expect an endgame event, got {events2}")
    check(m2.hit_counter == 9, f"hit_counter should NOT reset on an ordinary point loss, got {m2.hit_counter}")


def main():
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_") and callable(v)]
    for t in tests:
        t()
    if FAILURES:
        print(f"FAILED: {len(FAILURES)} check(s) failed:")
        for f in FAILURES:
            print(f"  - {f}")
        sys.exit(1)
    else:
        print(f"PASS: all exhaustive speed-up model checks passed ({len(tests)} test functions).")
        sys.exit(0)


if __name__ == "__main__":
    main()
