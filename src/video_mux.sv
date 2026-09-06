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
    output logic [5:0] out,
    input logic in_frame,
    input logic [5:0] background,
    input logic [5:0] border,
    input logic border_en,
    input logic [5:0] ball,
    input logic ball_en,
    input logic [5:0] paddle,
    input logic paddle_en,
    input logic [5:0] lives,
    input logic lives_en,
    input logic [5:0] copper,
    input logic copper_en
    );
    
    always_comb begin
        if (!in_frame) begin // In blanking. Output black to give the screen something to calibrate on.
            out = 6'b000000;
        end else if (copper_en) begin
            out = copper;
        end else if (border_en) begin
            out = border;
        end else if (paddle_en) begin
            out = paddle;
        end else if (ball_en) begin
            out = ball;
        end else if (lives_en) begin
            out = lives;
        end else begin
            out = background;
        end
    end
endmodule
