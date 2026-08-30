`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/09/2023 11:04:48 AM
// Design Name: 
// Module Name: border_generator
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


module border_painter
#(
    parameter BORDER_WIDTH = 8
)(
    output logic in_border,
    output logic [5:0] color,
    input logic [9:0] hpos,
    input logic [8:0] vpos
);
    
    //                          BBGGRR
    localparam BORDER_COLOR = 6'b111111;
    localparam BORDER_LEFT = 10'd0;
    localparam BORDER_RIGHT = 10'd632;
    localparam BORDER_TOP = 9'd0;
    localparam BORDER_BIT_WIDTH = $clog2(BORDER_WIDTH);
    
    assign color = BORDER_COLOR;
    assign in_border = hpos[9:BORDER_BIT_WIDTH] == BORDER_LEFT[9:BORDER_BIT_WIDTH] || 
        hpos[9:BORDER_BIT_WIDTH] == BORDER_RIGHT[9:BORDER_BIT_WIDTH];
endmodule
