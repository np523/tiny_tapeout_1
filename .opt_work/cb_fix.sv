`timescale 1ns / 1ps
module cb_fix #(
    parameter [7:0] DURATION_POINT    = 8'd60,
    parameter [7:0] DURATION_GAMEOVER = 8'd180
)(
    input logic clk,
    input logic nRst,
    input logic frame_pulse,
    input logic point_scored_pulse,
    input logic game_over_pulse,
    input logic [8:0] vpos,
    output logic active,
    output logic [5:0] color
);

    logic [7:0] frame_cntr;
    logic running;
    logic direction_down;
    logic [7:0] last_frame;

    assign active = running;
    assign last_frame = direction_down ? (DURATION_GAMEOVER - 8'd1) : (DURATION_POINT - 8'd1);

    always_ff @(posedge clk or negedge nRst) begin
        if (!nRst) begin
            frame_cntr <= 8'd0;
            running <= 1'b0;
            direction_down <= 1'b0;
        end else if (game_over_pulse) begin
            frame_cntr <= 8'd0;
            running <= 1'b1;
            direction_down <= 1'b1;
        end else if (point_scored_pulse) begin
            frame_cntr <= 8'd0;
            running <= 1'b1;
            direction_down <= 1'b0;
        end else if (frame_pulse && running) begin
            frame_cntr <= frame_cntr + 1'b1;
            if (frame_cntr == last_frame) running <= 1'b0;
        end
    end

    // Scroll is a pure function of elapsed frames, so it needs no register
    // and no adder of its own:
    //   down: +1 px/frame -> frame_cntr itself
    //   up:   -8 px/frame -> ~(frame_cntr << 3), since ~(8k) falls by 8 as k rises
    //   (the off-by-one of ~x vs -x is a constant phase shift, invisible here)
    logic [7:0] scroll;
    assign scroll = direction_down ? frame_cntr : ~{frame_cntr[4:0], 3'b000};

    logic [7:0] band_phase;
    logic [2:0] palette_idx;
    logic [2:0] palette_idx_blue;
    logic [1:0] level;
    logic [1:0] level_blue;

    assign band_phase = vpos[7:0] + scroll;
    assign palette_idx = band_phase[7:5];
    // Blue runs the same triangle phase-shifted by 2 rather than exactly
    // complemented, so the two channels turn around at different bands.
    // Complementing made both peak/trough on the same band, producing a
    // double-height yellow band and a double-height blue band.
    assign palette_idx_blue = palette_idx + 3'd2;
    assign level = palette_idx[2] ? ~palette_idx[1:0] : palette_idx[1:0];
    assign level_blue = palette_idx_blue[2] ? ~palette_idx_blue[1:0] : palette_idx_blue[1:0];
    assign color = {level_blue, level, level};

endmodule
