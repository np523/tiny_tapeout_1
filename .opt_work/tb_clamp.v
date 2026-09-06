`timescale 1ns/1ps
module tb_clamp;
    reg [9:0] x; reg [2:0] speed;
    localparam LEFT_P1 = 7, LEFT_P2 = 9, RIGHT = 608;

    // ORIGINAL
    wire [9:0] old_l1 = (x > LEFT_P1 + speed) ? x - speed : LEFT_P1;
    wire [9:0] old_l2 = (x > LEFT_P2 + speed) ? x - speed : LEFT_P2;
    wire [9:0] old_r  = (x < RIGHT - speed)   ? x + speed : RIGHT;
    // PROPOSED
    wire [9:0] xm = x - speed;
    wire [9:0] xp = x + speed;
    wire [9:0] new_l1 = (xm > LEFT_P1) ? xm : LEFT_P1;
    wire [9:0] new_l2 = (xm > LEFT_P2) ? xm : LEFT_P2;
    wire [9:0] new_r  = (xp < RIGHT)   ? xp : RIGHT;

    integer i, s, all_mm, reach_mm, reach_n;
    initial begin
        all_mm = 0; reach_mm = 0; reach_n = 0;
        for (i = 0; i < 1024; i = i + 1) begin
            for (s = 0; s < 8; s = s + 1) begin
                x = i[9:0]; speed = s[2:0]; #1;
                if (old_l1 !== new_l1 || old_l2 !== new_l2 || old_r !== new_r) begin
                    all_mm = all_mm + 1;
                    // reachable state space: paddle always clamped in [LEFT_P1, RIGHT],
                    // paddle_speed only ever takes 2, 3 or 4
                    if (i >= LEFT_P1 && i <= RIGHT && (s == 2 || s == 3 || s == 4)) begin
                        reach_mm = reach_mm + 1;
                        if (reach_mm <= 5)
                          $display("  REACHABLE MISMATCH x=%0d speed=%0d: l1 %0d/%0d l2 %0d/%0d r %0d/%0d",
                                   i, s, old_l1, new_l1, old_l2, new_l2, old_r, new_r);
                    end
                end
                if (i >= LEFT_P1 && i <= RIGHT && (s == 2 || s == 3 || s == 4)) reach_n = reach_n + 1;
            end
        end
        $display("Full sweep (1024 x 8 = 8192 combos): %0d mismatches", all_mm);
        $display("Reachable subset (x in [7,608], speed in {2,3,4}, %0d combos): %0d mismatches", reach_n, reach_mm);
        if (reach_mm == 0) $display("PASS: equivalent over the entire reachable state space");
        else $display("FAIL: not equivalent where it matters");
        $finish;
    end
endmodule
