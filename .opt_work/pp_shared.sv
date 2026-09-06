`timescale 1ns / 1ps
module pp_shared #(
    parameter PADDLE_COLOR = 6'b111111,
    parameter PADDLE_SEGMENT_WIDTH = 8,
    parameter PADDLE_NUM_SEGMENTS = 6,
    parameter PADDLE_HEIGHT = 9'd8,
    parameter P1_PADDLE_Y = 9'd456,
    parameter P2_PADDLE_Y = 9'd16
) (
    input logic clk,
    input logic nRst,
    output logic in_p1_paddle,
    output logic in_p2_paddle,
    output logic [5:0] color,
    input logic [9:0] hpos,
    input logic [8:0] vpos,
    input logic [9:0] p1_x,
    input logic [9:0] p2_x,
    output logic [2:0] paddle_segment
    );

    logic in_paddle_x;
    logic [2:0] paddle_segment_x;
    logic [2:0] paddle_segment_cnt;
    logic use_p1;
    logic [9:0] active_x;
    logic paddle_x_start;
    logic paddle_segment_end;
    logic paddle_x_end;

    // The two paddles sit in opposite halves of the frame, so a single
    // midpoint test selects the active one, stable for the whole scanline.
    assign use_p1 = (vpos > 9'd240);
    assign active_x = use_p1 ? p1_x : p2_x;
    assign paddle_x_start = hpos == active_x;
    assign paddle_segment_end = paddle_segment_x == PADDLE_SEGMENT_WIDTH - 1;
    assign paddle_x_end = paddle_segment_end && paddle_segment_cnt == PADDLE_NUM_SEGMENTS - 1;
    assign paddle_segment = paddle_segment_cnt;

    always_ff @(posedge clk or negedge nRst)
    begin
        if(!nRst) begin
            paddle_segment_x <= 0;
        end else begin
            if(in_paddle_x && !paddle_segment_end) begin
                paddle_segment_x <= paddle_segment_x + 1'b1;
            end else begin
                paddle_segment_x <= 0;
            end
        end
    end

    always_ff @(posedge clk or negedge nRst)
    begin
        if(!nRst) begin
            paddle_segment_cnt <= 0;
        end else begin
            if(paddle_x_end) begin
                paddle_segment_cnt <= 0;
            end else if(paddle_segment_end) begin
                paddle_segment_cnt <= paddle_segment_cnt + 1'b1;
            end
        end
    end

    always_ff @(posedge clk or negedge nRst)
    begin
        if(!nRst) begin
            in_paddle_x <= 0;
        end else begin
            if(paddle_x_start) begin
                in_paddle_x <= 1;
            end else if(paddle_x_end) begin
                in_paddle_x <= 0;
            end
        end
    end

    logic in_p1_y;
    logic in_p2_y;
    always_ff @(posedge clk or negedge nRst)
    begin
        if(!nRst) begin
            in_p1_y <= 0;
            in_p2_y <= 0;
        end else begin
            if(vpos == P1_PADDLE_Y)                     in_p1_y <= 1;
            else if(vpos == P1_PADDLE_Y + PADDLE_HEIGHT) in_p1_y <= 0;
            if(vpos == P2_PADDLE_Y)                     in_p2_y <= 1;
            else if(vpos == P2_PADDLE_Y + PADDLE_HEIGHT) in_p2_y <= 0;
        end
    end

    assign color = PADDLE_COLOR;
    assign in_p1_paddle = in_paddle_x && in_p1_y;
    assign in_p2_paddle = in_paddle_x && in_p2_y;
endmodule
