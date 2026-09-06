`timescale 1ns / 1ps
module cb_base #(
    parameter DURATION_POINT    = 8'd60,
    parameter DURATION_GAMEOVER = 8'd180,
    parameter SPEED_POINT       = 3'd6,
    parameter SPEED_GAMEOVER    = 3'd1
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

    logic [7:0] duration_cntr;
    logic direction_down;

    assign active = (duration_cntr != 0);

    always_ff @(posedge clk or negedge nRst) begin
        if (!nRst) begin
            duration_cntr <= 8'd0;
            direction_down <= 1'b0;
        end else if (game_over_pulse) begin
            duration_cntr <= DURATION_GAMEOVER;
            direction_down <= 1'b1;
        end else if (point_scored_pulse) begin
            duration_cntr <= DURATION_POINT;
            direction_down <= 1'b0;
        end else if (frame_pulse && active) begin
            duration_cntr <= duration_cntr - 1'b1;
        end
    end

    logic [8:0] scroll;
    logic [2:0] speed;
    assign speed = direction_down ? SPEED_GAMEOVER : SPEED_POINT;

    always_ff @(posedge clk or negedge nRst) begin
        if (!nRst) begin
            scroll <= 9'd0;
        end else if (frame_pulse && active) begin
            scroll <= direction_down ? (scroll + speed) : (scroll - speed);
        end
    end

    logic [9:0] band_phase;
    logic [2:0] palette_idx;
    logic [1:0] level;
    logic [1:0] level_blue;

    assign band_phase = vpos + scroll;
    assign palette_idx = band_phase[7:5];
    assign level = palette_idx[2] ? ~palette_idx[1:0] : palette_idx[1:0];
    assign level_blue = palette_idx[2] ? palette_idx[1:0] : ~palette_idx[1:0];
    assign color = {level_blue, level, level};

endmodule
