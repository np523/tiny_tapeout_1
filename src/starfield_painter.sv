`timescale 1ns / 1ps
module starfield_painter #(
    parameter [5:0] STAR_COLOR = 6'b001111
)(
    input logic clk,
    input logic nRst,
    input logic frame_pulse,
    input logic [9:0] hpos,
    input logic [8:0] vpos,
    output logic [5:0] color
);

    localparam int NUM_STARS = 16;
    localparam logic [9:0] SCREEN_W = 10'd640;

    localparam logic [9:0] SPEED = 10'd1;

    function automatic logic [8:0] row_of(input integer idx);
        case (idx)
            0:  row_of = 9'd53;
            1:  row_of = 9'd187;
            2:  row_of = 9'd22;
            3:  row_of = 9'd341;
            4:  row_of = 9'd268;
            5:  row_of = 9'd119;
            6:  row_of = 9'd76;
            7:  row_of = 9'd428;
            8:  row_of = 9'd203;
            9:  row_of = 9'd9;
            10: row_of = 9'd305;
            11: row_of = 9'd151;
            12: row_of = 9'd462;
            13: row_of = 9'd88;
            14: row_of = 9'd384;
            default: row_of = 9'd241;
        endcase
    endfunction

    function automatic logic [9:0] offset_of(input integer idx);
        case (idx)
            0:  offset_of = 10'd512;
            1:  offset_of = 10'd88;
            2:  offset_of = 10'd301;
            3:  offset_of = 10'd605;
            4:  offset_of = 10'd154;
            5:  offset_of = 10'd423;
            6:  offset_of = 10'd37;
            7:  offset_of = 10'd566;
            8:  offset_of = 10'd240;
            9:  offset_of = 10'd469;
            10: offset_of = 10'd112;
            11: offset_of = 10'd338;
            12: offset_of = 10'd621;
            13: offset_of = 10'd195;
            14: offset_of = 10'd77;
            default: offset_of = 10'd390;
        endcase
    endfunction

    logic [9:0] scroll;

    always_ff @(posedge clk or negedge nRst) begin
        if (!nRst) begin
            scroll <= 10'd0;
        end else if (frame_pulse) begin
            scroll <= (scroll >= SPEED) ? scroll - SPEED : scroll + SCREEN_W - SPEED;
        end
    end

    logic [9:0] rel;
    assign rel = (hpos >= scroll) ? (hpos - scroll) : (hpos - scroll + SCREEN_W);

    logic [NUM_STARS-1:0] star_active;
    genvar g;
    generate
        for (g = 0; g < NUM_STARS; g = g + 1) begin : star_cmp
            if (g < 12) begin : big_star
                assign star_active[g] = ((vpos >> 1) == (row_of(g) >> 1))
                                     && ((rel >> 1) == (offset_of(g) >> 1));
            end else begin : small_star
                assign star_active[g] = (vpos == row_of(g)) && (rel == offset_of(g));
            end
        end
    endgenerate

    assign color = (|star_active) ? STAR_COLOR : 6'b000000;

endmodule
