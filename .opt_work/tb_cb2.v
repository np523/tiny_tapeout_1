`timescale 1ns/1ps
module tb_cb2;
    reg clk=0, nRst=0, frame_pulse=0, point_scored_pulse=0, game_over_pulse=0;
    reg [8:0] vpos=0;
    wire active; wire [5:0] color;
    cb_simp dut(.clk(clk),.nRst(nRst),.frame_pulse(frame_pulse),
        .point_scored_pulse(point_scored_pulse),.game_over_pulse(game_over_pulse),
        .vpos(vpos),.active(active),.color(color));
    always #1 clk = ~clk;

    integer f, af, i, nblue, nyellow, nother;
    reg [7:0] ph_prev, ph_now;
    reg [5:0] seen [0:63];
    initial begin
        @(negedge clk); nRst=0; @(negedge clk); nRst=1;

        // point-scored: duration + upward direction
        @(negedge clk); point_scored_pulse=1; @(negedge clk); point_scored_pulse=0;
        af=0; ph_prev = dut.scroll;
        for (f=0; f<70; f=f+1) begin
            @(negedge clk); frame_pulse=1; @(negedge clk); frame_pulse=0;
            if (active) af=af+1;
            if (f==0) begin
                ph_now = dut.scroll;
                if (ph_now !== (ph_prev - 8'd8))
                    $display("FAIL up-direction: scroll %0d -> %0d (expected -8)", ph_prev, ph_now);
                else $display("OK: point-scored scroll moves up 8/frame (%0d -> %0d)", ph_prev, ph_now);
            end
        end
        $display("point-scored active %0d frames (expect 60)", af);

        // game-over: duration + downward direction
        @(negedge clk); game_over_pulse=1; @(negedge clk); game_over_pulse=0;
        af=0; ph_prev = dut.scroll;
        for (f=0; f<190; f=f+1) begin
            @(negedge clk); frame_pulse=1; @(negedge clk); frame_pulse=0;
            if (active) af=af+1;
            if (f==0) begin
                ph_now = dut.scroll;
                if (ph_now !== (ph_prev + 8'd1))
                    $display("FAIL down-direction: scroll %0d -> %0d (expected +1)", ph_prev, ph_now);
                else $display("OK: game-over scroll moves down 1/frame (%0d -> %0d)", ph_prev, ph_now);
            end
        end
        $display("game-over active %0d frames (expect 180)", af);

        // colour content: sweep a full 256-row band cycle, count blue vs yellow
        nblue=0; nyellow=0; nother=0;
        for (i=0; i<256; i=i+1) begin
            vpos = i[8:0]; #1;
            if (color[5:4] > color[1:0]) nblue = nblue+1;
            else if (color[1:0] > color[5:4]) nyellow = nyellow+1;
            else nother = nother+1;
        end
        $display("Colour sweep over 256 rows: blue-dominant=%0d  yellow-dominant=%0d  balanced=%0d",
                 nblue, nyellow, nother);
        if (nblue>0 && nyellow>0) $display("PASS: pattern contains both blue and yellow bands");
        else $display("FAIL: pattern is monochrome");
        $finish;
    end
endmodule
