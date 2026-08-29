`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/09/2023 10:06:41 AM
// Design Name: 
// Module Name: video_mux
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


module video_mux(
    output reg [5:0] out,
    input in_frame,
    input [5:0] background,
    input [5:0] border,
    input border_en,
    input [5:0] ball,
    input ball_en,
    input [5:0] p1_paddle,
    input p1_paddle_en,
    input [5:0] p1_lives,
    input p1_lives_en,
    input [5:0] p2_paddle,
    input p2_paddle_en,
    input [5:0] p2_lives,
    input p2_lives_en
    );
    
    always @(*)
    begin
        if (!in_frame) begin // In blanking. Output black to give the screen something to calibrate on. 
            out <= 6'b000000;
        end else if (border_en) begin
            out <= border;
        end else if (p1_paddle_en) begin
            out <= p1_paddle;
        end else if (p2_paddle_en) begin
            out <= p2_paddle;
        end else if (ball_en) begin
            out <= ball;
        end else if (p1_lives_en) begin
            out <= p1_lives;
        end else if (p2_lives_en) begin
            out <= p2_lives;
        end else begin
            out <= background;
        end
    end
endmodule
