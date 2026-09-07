`timescale 1ns/1ps
module tb_cbfix;
    reg clk=0, nRst=0, frame_pulse=0, point_scored_pulse=0, game_over_pulse=0;
    reg [8:0] vpos=0;
    wire active; wire [5:0] color;
    cb_fix dut(.clk(clk),.nRst(nRst),.frame_pulse(frame_pulse),
        .point_scored_pulse(point_scored_pulse),.game_over_pulse(game_over_pulse),
        .vpos(vpos),.active(active),.color(color));
    always #1 clk = ~clk;
    integer i, adjacent_dupes, distinct;
    reg [5:0] band [0:7];
    reg [5:0] prev;
    initial begin
        @(negedge clk); nRst=0; @(negedge clk); nRst=1;
        // sample the colour of each of the 8 bands (32 rows apart)
        for (i=0; i<8; i=i+1) begin
            vpos = i*32; #1;
            band[i] = color;
            $display("band %0d (vpos %0d): B=%0d G=%0d R=%0d", i, i*32, color[5:4], color[3:2], color[1:0]);
        end
        adjacent_dupes = 0;
        for (i=0; i<8; i=i+1) begin
            prev = (i==0) ? band[7] : band[i-1];
            if (band[i] === prev) adjacent_dupes = adjacent_dupes + 1;
        end
        distinct = 0;
        for (i=0; i<8; i=i+1) begin
            if (band[i] !== band[(i+1)%8] && band[i] !== band[(i+2)%8] &&
                band[i] !== band[(i+3)%8]) distinct = distinct + 1;
        end
        $display("Adjacent duplicate bands (incl. wrap): %0d", adjacent_dupes);
        if (adjacent_dupes == 0) $display("PASS: no two neighbouring bands are identical");
        else $display("FAIL: still has doubled bands");
        $finish;
    end
endmodule
