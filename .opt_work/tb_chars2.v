`timescale 1ns/1ps
module tb_chars2;
    reg [9:0] x; reg [2:0] speed;
    localparam LEFT_P1 = 7, LEFT_P2 = 9, RIGHT = 608;
    wire [9:0] old_l1 = (x > LEFT_P1 + speed) ? x - speed : LEFT_P1;
    wire [9:0] old_l2 = (x > LEFT_P2 + speed) ? x - speed : LEFT_P2;
    wire [9:0] old_r  = (x < RIGHT - speed)   ? x + speed : RIGHT;
    wire [9:0] xm = x - speed, xp = x + speed;
    wire [9:0] new_l1 = (xm > LEFT_P1) ? xm : LEFT_P1;
    wire [9:0] new_l2 = (xm > LEFT_P2) ? xm : LEFT_P2;
    wire [9:0] new_r  = (xp < RIGHT)   ? xp : RIGHT;
    integer i, s, in_range, low, high;
    initial begin
        in_range = 0; low = 0; high = 0;
        for (i = 0; i < 1024; i = i + 1) for (s = 0; s < 8; s = s + 1) begin
            x = i[9:0]; speed = s[2:0]; #1;
            if (old_l1 !== new_l1 || old_l2 !== new_l2 || old_r !== new_r) begin
                if (i >= 7 && i <= 608) in_range = in_range + 1;
                else if (i < 7) low = low + 1;
                else high = high + 1;
            end
        end
        $display("Mismatches with x inside reachable [7..608], ANY speed 0-7: %0d", in_range);
        $display("Mismatches at x < 7 (subtract underflow):   %0d", low);
        $display("Mismatches at x > 608 (add overflow):       %0d", high);
        $finish;
    end
endmodule
