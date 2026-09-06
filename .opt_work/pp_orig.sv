`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/09/2023 11:43:48 AM
// Design Name: 
// Module Name: paddle_drawer
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module pp_orig #(
    //                          BBGGRR
    parameter PADDLE_COLOR = 6'b111111,
    parameter PADDLE_SEGMENT_WIDTH = 8,
    parameter PADDLE_NUM_SEGMENTS = 6, 
    parameter PADDLE_HEIGHT = 9'd8,
    parameter PADDLE_Y =  9'd456
) (
    input logic clk,
    input logic nRst,
    output logic in_paddle,
    output logic [5:0] color,
    input logic [9:0] hpos,
    input logic [8:0] vpos,
    input logic [9:0] x,
    output logic [2:0] paddle_segment
    );
    
    logic in_paddle_x;
    logic [2:0] paddle_segment_x;
    logic [2:0] paddle_segment_cnt;
    logic paddle_x_start;
    assign paddle_x_start = hpos == x;
    logic paddle_segment_end;
    assign paddle_segment_end = paddle_segment_x == PADDLE_SEGMENT_WIDTH - 1;
    logic paddle_x_end;
    assign paddle_x_end = paddle_segment_end && paddle_segment_cnt == PADDLE_NUM_SEGMENTS - 1;
    assign paddle_segment = paddle_segment_cnt;

    // Paddle segment position counter
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

    // Paddle segment counter
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

    // Are we in the paddle?
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

    logic in_paddle_y;
    logic in_paddle_y_start;
    assign in_paddle_y_start = vpos == PADDLE_Y;
    logic in_paddle_y_end;
    assign in_paddle_y_end = vpos == PADDLE_Y + PADDLE_HEIGHT;
    always_ff @(posedge clk or negedge nRst)
    begin
        if(!nRst) begin
            in_paddle_y <= 0;
        end else begin
            if(in_paddle_y_start) begin
                in_paddle_y <= 1;
            end else if(in_paddle_y_end) begin
                in_paddle_y <= 0;
            end
        end
    end

    assign color = PADDLE_COLOR;
    assign in_paddle = in_paddle_x && in_paddle_y;
endmodule
