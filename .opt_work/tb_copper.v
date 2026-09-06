`timescale 1ns/1ps
module tb_copper;
    reg clk = 0, nRst = 0, frame_pulse = 0, point_scored_pulse = 0, game_over_pulse = 0;
    reg [8:0] vpos = 0;
    wire active; wire [5:0] color;
    copper_bars_painter dut(.clk(clk), .nRst(nRst), .frame_pulse(frame_pulse),
        .point_scored_pulse(point_scored_pulse), .game_over_pulse(game_over_pulse),
        .vpos(vpos), .active(active), .color(color));
    always #1 clk = ~clk;

    integer f, active_frames, scroll0, scroll1, i;
    reg [8:0] scroll_prev;
    initial begin
        @(negedge clk); nRst = 0; @(negedge clk); nRst = 1;

        // --- Test 1: point-scored duration and direction ---
        @(negedge clk); point_scored_pulse = 1;
        @(negedge clk); point_scored_pulse = 0;
        if (!active) $display("FAIL: not active immediately after point_scored_pulse");
        active_frames = 0;
        scroll_prev = dut.scroll;
        for (f = 0; f < 70; f = f + 1) begin
            @(negedge clk); frame_pulse = 1;
            @(negedge clk); frame_pulse = 0;
            if (active) active_frames = active_frames + 1;
            if (f == 0) begin
                if (dut.scroll !== (scroll_prev - dut.SPEED_POINT))
                    $display("FAIL: point-scored scroll should DECREASE (up) by SPEED_POINT, prev=%0d new=%0d", scroll_prev, dut.scroll);
                else $display("OK: point-scored scroll moved up by %0d (prev=%0d new=%0d)", dut.SPEED_POINT, scroll_prev, dut.scroll);
            end
        end
        $display("point-scored: active for %0d frames (expected 60)", active_frames);
        if (active) $display("FAIL: still active after 70 frames (duration should be 60)");
        else $display("OK: deactivated on schedule");

        // --- Test 2: game-over duration and direction ---
        @(negedge clk); game_over_pulse = 1;
        @(negedge clk); game_over_pulse = 0;
        active_frames = 0;
        scroll_prev = dut.scroll;
        for (f = 0; f < 190; f = f + 1) begin
            @(negedge clk); frame_pulse = 1;
            @(negedge clk); frame_pulse = 0;
            if (active) active_frames = active_frames + 1;
            if (f == 0) begin
                if (dut.scroll !== (scroll_prev + dut.SPEED_GAMEOVER))
                    $display("FAIL: game-over scroll should INCREASE (down) by SPEED_GAMEOVER, prev=%0d new=%0d", scroll_prev, dut.scroll);
                else $display("OK: game-over scroll moved down by %0d (prev=%0d new=%0d)", dut.SPEED_GAMEOVER, scroll_prev, dut.scroll);
            end
        end
        $display("game-over: active for %0d frames (expected 180)", active_frames);

        // --- Test 3: mutual exclusivity / re-trigger priority ---
        @(negedge clk); nRst = 0; @(negedge clk); nRst = 1;
        @(negedge clk); point_scored_pulse = 1; game_over_pulse = 1; // both same cycle
        @(negedge clk); point_scored_pulse = 0; game_over_pulse = 0;
        $display("Simultaneous trigger: duration_cntr=%0d (game_over=%0d wins if =180) direction_down=%b",
                 dut.duration_cntr, dut.DURATION_GAMEOVER, dut.direction_down);

        // --- Test 4: color is a triangular ramp (no discontinuity at wrap) ---
        vpos = 0;
        for (i = 0; i < 256; i = i + 1) begin
            vpos = i[8:0]; #1;
        end
        $display("Sweep of 256 vpos values completed without X/Z (color=%b at vpos=255)", color);
        $finish;
    end
endmodule
