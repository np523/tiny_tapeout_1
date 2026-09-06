`timescale 1ns/1ps
module tb_vel;
    reg [1:0] tier; reg [2:0] seg; reg signed [3:0] vx_cur;
    reg signed [3:0] old_vx, new_vx;

    // ORIGINAL: 4 x 6 case table
    always @* begin
        case (tier)
        0: case (seg)
            3'b000: old_vx = -3; 3'b001: old_vx = -2; 3'b010: old_vx = -1;
            3'b011: old_vx =  1; 3'b100: old_vx =  2; 3'b101: old_vx =  3;
            default: old_vx = vx_cur; endcase
        1: case (seg)
            3'b000: old_vx = -4; 3'b001: old_vx = -3; 3'b010: old_vx = -2;
            3'b011: old_vx =  2; 3'b100: old_vx =  3; 3'b101: old_vx =  4;
            default: old_vx = vx_cur; endcase
        2: case (seg)
            3'b000: old_vx = -5; 3'b001: old_vx = -4; 3'b010: old_vx = -3;
            3'b011: old_vx =  3; 3'b100: old_vx =  4; 3'b101: old_vx =  5;
            default: old_vx = vx_cur; endcase
        3: case (seg)
            3'b000: old_vx = -7; 3'b001: old_vx = -6; 3'b010: old_vx = -5;
            3'b011: old_vx =  5; 3'b100: old_vx =  6; 3'b101: old_vx =  7;
            default: old_vx = vx_cur; endcase
        endcase
    end

    // PROPOSED: base magnitude by segment + offset by tier
    wire [2:0] seg_base = (seg < 3) ? (3'd3 - seg) : (seg - 3'd2);
    wire [2:0] tier_off = (tier == 2'd3) ? 3'd4 : {1'b0, tier};
    wire [3:0] mag      = {1'b0, seg_base} + {1'b0, tier_off};
    always @* begin
        if (seg > 5)      new_vx = vx_cur;
        else if (seg < 3) new_vx = -$signed(mag);
        else              new_vx =  $signed(mag);
    end

    integer t, s, v, mm, n;
    initial begin
        mm = 0; n = 0;
        for (t = 0; t < 4; t = t + 1)
          for (s = 0; s < 8; s = s + 1)
            for (v = -8; v < 8; v = v + 1) begin
                tier = t[1:0]; seg = s[2:0]; vx_cur = v[3:0]; #1;
                n = n + 1;
                if (old_vx !== new_vx) begin
                    mm = mm + 1;
                    if (mm <= 8) $display("  MISMATCH tier=%0d seg=%0d vx_cur=%0d: old=%0d new=%0d",
                                          t, s, v, old_vx, new_vx);
                end
            end
        $display("Swept %0d combos (tier 0-3 x seg 0-7 x vx_cur -8..7): %0d mismatches", n, mm);
        if (mm == 0) $display("PASS: bit-exact equivalent including the unreachable seg 6/7 fallback");
        $finish;
    end
endmodule
