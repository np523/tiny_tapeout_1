`timescale 1ns/1ps
module tb_pp;
    reg clk = 0, nRst = 0;
    reg [9:0] hpos = 0; reg [8:0] vpos = 0;
    reg [9:0] p1_x = 300, p2_x = 100;
    always #1 clk = ~clk;
    always @(posedge clk) begin
        if (hpos == 799) begin
            hpos <= 0; vpos <= (vpos == 524) ? 9'd0 : vpos + 1'b1;
        end else hpos <= hpos + 1'b1;
    end

    wire o1_in, o2_in, sh1_in, sh2_in;
    wire [5:0] o1_c, o2_c, sh_c;
    wire [2:0] o1_seg, o2_seg, sh_seg;
    pp_orig #(.PADDLE_SEGMENT_WIDTH(4),.PADDLE_NUM_SEGMENTS(6),.PADDLE_Y(9'd456)) u1(
        .clk(clk),.nRst(nRst),.in_paddle(o1_in),.color(o1_c),.hpos(hpos),.vpos(vpos),
        .x(p1_x),.paddle_segment(o1_seg));
    pp_orig #(.PADDLE_SEGMENT_WIDTH(4),.PADDLE_NUM_SEGMENTS(6),.PADDLE_Y(9'd16)) u2(
        .clk(clk),.nRst(nRst),.in_paddle(o2_in),.color(o2_c),.hpos(hpos),.vpos(vpos),
        .x(p2_x),.paddle_segment(o2_seg));
    pp_shared #(.PADDLE_SEGMENT_WIDTH(4),.PADDLE_NUM_SEGMENTS(6),
                .P1_PADDLE_Y(9'd456),.P2_PADDLE_Y(9'd16)) sh(
        .clk(clk),.nRst(nRst),.in_p1_paddle(sh1_in),.in_p2_paddle(sh2_in),.color(sh_c),
        .hpos(hpos),.vpos(vpos),.p1_x(p1_x),.p2_x(p2_x),.paddle_segment(sh_seg));

    integer mism, seg_mism, checked, combo, f;
    initial begin
        mism = 0; seg_mism = 0; checked = 0;
        @(negedge clk); nRst = 0; @(negedge clk); nRst = 1;
        for (combo = 0; combo < 5; combo = combo + 1) begin
            case (combo)
                0: begin p1_x = 300; p2_x = 100; end
                1: begin p1_x = 7;   p2_x = 608; end
                2: begin p1_x = 608; p2_x = 9;   end
                3: begin p1_x = 320; p2_x = 320; end
                4: begin p1_x = 100; p2_x = 500; end
            endcase
            repeat (420000) @(posedge clk);
            for (f = 0; f < 420000; f = f + 1) begin
                @(posedge clk); #0.1;
                checked = checked + 1;
                if (o1_in !== sh1_in || o2_in !== sh2_in) begin
                    mism = mism + 1;
                    if (mism <= 5) $display("  EN MISMATCH combo=%0d vpos=%0d hpos=%0d: o1=%b/%b o2=%b/%b",
                                            combo, vpos, hpos, o1_in, sh1_in, o2_in, sh2_in);
                end
                // segment only matters while that paddle is actually being drawn
                if (o1_in && (o1_seg !== sh_seg)) seg_mism = seg_mism + 1;
                if (o2_in && (o2_seg !== sh_seg)) seg_mism = seg_mism + 1;
            end
        end
        $display("Compared %0d pixel-cycles across 5 paddle-position combos", checked);
        $display("  enable mismatches: %0d", mism);
        $display("  segment mismatches (while drawing): %0d", seg_mism);
        if (mism == 0 && seg_mism == 0) $display("PASS: shared paddle painter is pixel- and segment-identical");
        else $display("FAIL");
        $finish;
    end
endmodule
