`timescale 1ns/1ps
module tb_lp;
    reg clk = 0, nRst = 0;
    reg [9:0] hpos = 0; reg [8:0] vpos = 0; reg hactive = 1;
    reg [1:0] p1_lives = 3, p2_lives = 2;
    always #1 clk = ~clk;

    // VGA-timing replica (identical stimulus to both DUTs)
    always @(posedge clk) begin
        if (hpos == 799) begin
            hpos <= 0;
            vpos <= (vpos == 524) ? 9'd0 : vpos + 1'b1;
        end else hpos <= hpos + 1'b1;
        if (hpos == 639) hactive <= 0;
        else if (hpos == 799) hactive <= 1;
    end

    wire o1_in, o2_in, sh_in;
    wire [5:0] o1_c, o2_c, sh_c;
    lp_orig #(.LIVES_Y(9'd466)) p1(.clk(clk),.nRst(nRst),.in_lives(o1_in),.color(o1_c),
        .hactive(hactive),.hpos(hpos),.vpos(vpos),.lives(p1_lives));
    lp_orig #(.LIVES_Y(9'd2))   p2(.clk(clk),.nRst(nRst),.in_lives(o2_in),.color(o2_c),
        .hactive(hactive),.hpos(hpos),.vpos(vpos),.lives(p2_lives));
    lp_shared sh(.clk(clk),.nRst(nRst),.in_lives(sh_in),.color(sh_c),
        .hactive(hactive),.hpos(hpos),.vpos(vpos),.p1_lives(p1_lives),.p2_lives(p2_lives));

    wire orig_in = o1_in || o2_in;
    integer mism, checked, combo, f;
    initial begin
        mism = 0; checked = 0;
        @(negedge clk); nRst = 0; @(negedge clk); nRst = 1;
        for (combo = 0; combo < 4; combo = combo + 1) begin
            case (combo)
                0: begin p1_lives = 3; p2_lives = 3; end
                1: begin p1_lives = 2; p2_lives = 0; end
                2: begin p1_lives = 1; p2_lives = 3; end
                3: begin p1_lives = 0; p2_lives = 1; end
            endcase
            // one settle frame, then one compared frame
            repeat (420000) @(posedge clk);
            for (f = 0; f < 420000; f = f + 1) begin
                @(posedge clk); #0.1;
                checked = checked + 1;
                if (orig_in !== sh_in) begin
                    mism = mism + 1;
                    if (mism <= 5) $display("  MISMATCH combo=%0d vpos=%0d hpos=%0d: orig=%b shared=%b",
                                            combo, vpos, hpos, orig_in, sh_in);
                end
            end
        end
        $display("Compared %0d pixel-cycles across 4 lives combos: %0d mismatches", checked, mism);
        if (mism == 0) $display("PASS: shared instance is pixel-identical to the two originals");
        else $display("FAIL");
        $finish;
    end
endmodule
