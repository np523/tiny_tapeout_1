`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/09/2023 11:43:48 AM
// Design Name: 
// Module Name: ball_drawer
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


module bp_simp(
    input logic clk,
    input logic nRst,
    output logic in_ball,
    output logic in_ball_top,
    output logic in_ball_bottom,
    output logic in_ball_left,
    output logic in_ball_right,
    output logic [5:0] color,
    input logic [9:0] x,
    input logic [8:0] y,
    input logic [9:0] hpos,
    input logic [8:0] vpos,
    input logic line_pulse,
    input logic display_active
    );
        
    // Pixel ball positions:
    //      0 1   2 3
    //    T T T T T T R
    // 0  L   X X X   R
    // 1  L X X X X X R
    //    L X X X X X R 
    // 2  L X X X X X R
    // 3  L   X X X   R
    //    L B B B B B B
    
    // Pixel ball positions:
    //   0 1   2 3
    // 0   X X X  
    // 1 X X X X X
    //   X X X X X
    // 2 X X X X X
    // 3   X X X
    
    // Pixel ball colision regions:
    //   0 1   2 3
    // 0 T T T T R  
    // 1 L       R
    //   L       R
    // 2 L       R
    // 3 L B B B B

    //                        BBGGRR
    parameter BALL_COLOR = 6'b001100;
    
    logic is_ball_line_start;
    logic is_ball_start;

    
    logic x0;
    logic x3;
    logic y0;
    logic y3;

    logic gt_x0;
    logic gt_x1;
    logic lt_x2;
    logic lt_x3;
    logic gt_y0;
    logic gt_y1;
    logic lt_y2;
    logic lt_y3;

    logic is_ball_line_end;
    logic is_ball_rows_end;

    assign is_ball_line_start = x == hpos;
    assign is_ball_start = display_active && is_ball_line_start && y == vpos;

    logic [2:0] ball_x;
    logic [2:0] ball_y;
    logic is_in_ball_line;
    logic is_in_ball_rows;
    
    assign x0 = ball_x == 0 && is_in_ball_line;
    assign x3 = ball_x == 4 && is_in_ball_line;
    assign y0 = ball_y == 0 && is_in_ball_rows;
    assign y3 = ball_y == 4 && is_in_ball_rows;

    assign gt_x0 = is_in_ball_line;
    assign gt_x1 = is_in_ball_line && !x0;
    assign lt_x2 = is_in_ball_line && !x3;
    assign lt_x3 = is_in_ball_line;
    assign gt_y0 = is_in_ball_rows;
    assign gt_y1 = is_in_ball_rows && !y0;
    assign lt_y2 = is_in_ball_rows && !y3;
    assign lt_y3 = is_in_ball_rows;

    assign is_ball_line_end = x3;
    assign is_ball_rows_end = y3;

    // Latch that enables the ball x counter
    always_ff @(posedge clk or negedge nRst)
    begin
        if(!nRst) begin
            is_in_ball_line <= 0;
        end else begin
            if(is_ball_line_start) begin
                is_in_ball_line <= 1;
            end else if(is_ball_line_end) begin
                is_in_ball_line <= 0;
            end
        end
    end
    
    // Ball x counter
    always_ff @(posedge clk or negedge nRst)
    begin
        if(!nRst) begin
            ball_x <= 0;
        end else begin
            if(is_in_ball_line) begin
                ball_x <= ball_x + 1'b1;
            end else begin
                ball_x <= 0;
            end
        end
    end

    // Latch that enables the ball y counter
    always_ff @(posedge clk or negedge nRst)
    begin
        if(!nRst) begin
            is_in_ball_rows <= 0;
        end else begin
            if(is_ball_start) begin
                is_in_ball_rows <= 1;
            end else if(is_ball_rows_end && line_pulse) begin
                is_in_ball_rows <= 0;
            end
        end
    end

    // Ball y counter
    always_ff @(posedge clk or negedge nRst)
    begin
        if(!nRst) begin
            ball_y <= 0;
        end else begin
            if(line_pulse) begin
                if(is_in_ball_rows) begin
                    ball_y <= ball_y + 1'b1;
                end else begin
                    ball_y <= 0;
                end
            end
        end
    end 
    
    // Ball area: inside the 5x5 box, minus the four cut corners
    assign in_ball = is_in_ball_line && is_in_ball_rows && !((x0 || x3) && (y0 || y3));

    // Ball collision regions
    assign in_ball_top = y0 && !x3;
    assign in_ball_left = x0 && !y0;
    assign in_ball_bottom = y3 && !x0;
    assign in_ball_right = x3 && !y3;
    
    assign color = BALL_COLOR;
endmodule
