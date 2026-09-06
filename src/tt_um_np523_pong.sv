`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/07/2023 07:53:38 PM
// Design Name: 
// Module Name: robojan_top
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


module tt_um_np523_pong (
    input logic  [7:0] ui_in,    // Dedicated inputs - connected to the input switches
    output logic  [7:0] uo_out,   // Dedicated outputs - connected to the 7 segment display
    input logic  [7:0] uio_in,   // IOs: Bidirectional Input path
    output logic  [7:0] uio_out,  // IOs: Bidirectional Output path
    output logic  [7:0] uio_oe,   // IOs: Bidirectional Enable path (active high: 0=input, 1=output)
    input logic        ena,      // will go high when the design is enabled
    input logic        clk,      // clock
    input logic        rst_n     // reset_n - low to reset
);
    
    logic vblank;
    logic hblank;
    logic [1:0] vga_r;
    logic [1:0] vga_g;
    logic [1:0] vga_b;
    logic vga_hsync;
    logic vga_vsync;
    pong pong(
        .clk(clk),
        .nRst(rst_n),
        .en(ena),
        .btn_p1_left_pin(ui_in[5]),
        .btn_p1_right_pin(ui_in[6]),
        .btn_p1_select_pin(ui_in[7]),
        .btn_p2_left_pin(ui_in[2]),
        .btn_p2_right_pin(ui_in[3]),
        .btn_p2_select_pin(ui_in[4]),
        .vga_r(vga_r),
        .vga_g(vga_g),
        .vga_b(vga_b),
        .vga_hsync(vga_hsync),
        .vga_vsync(vga_vsync),
        .vblank(vblank),
        .hblank(hblank),
        .ai_mode_select(ui_in[0])
    );

    // Standard Tiny VGA Pmod pinout: uo_out = {hsync, B0, G0, R0, vsync, B1, G1, R1}
    assign uo_out = {vga_hsync, vga_b[0], vga_g[0], vga_r[0], vga_vsync, vga_b[1], vga_g[1], vga_r[1]};

    assign uio_oe = {5'b0, 1'b1, 1'b1, 1'b0};
    assign uio_out = {5'b0, vblank, hblank, 1'b0};
    
endmodule
