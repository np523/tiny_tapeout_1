`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/07/2023 07:53:38 PM
// Design Name: 
// Module Name: pong
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


module pong
#(    
    parameter PADDLE_SEGMENT_WIDTH = 4,
    parameter PADDLE_NUM_SEGMENTS = 6,
    parameter BORDER_WIDTH = 8, // Must be a power of 2
    parameter INITIAL_BALL_X = 10'd320 - 3'd2,
    parameter INITIAL_BALL_Y = 9'd340 - 3'd2,
    parameter INITIAL_VEL_X = 4'sd0,
    parameter INITIAL_VEL_Y = 4'sd2
)(
    input clk,
    input nRst,
    input en,
    input btn_p1_left_pin,
    input btn_p1_right_pin,
    input btn_p1_select_pin,
    input btn_p2_left_pin,
    input btn_p2_right_pin,
    input btn_p2_select_pin,
    output [1:0] vga_r,
    output [1:0] vga_g,
    output [1:0] vga_b,
    output vga_hsync,
    output vga_vsync,
    output vblank,
    output hblank,
    output sound_out
    );

    // Synchronize the inputs
    wire p1_btn_left;
    wire p1_btn_right;
    wire p1_btn_select;
    wire p2_btn_left;
    wire p2_btn_right;
    wire p2_btn_select;
    synchronizer p1_btn_left_sync(clk, nRst, btn_p1_left_pin, p1_btn_left);
    synchronizer p1_btn_right_sync(clk, nRst, btn_p1_right_pin, p1_btn_right);
    synchronizer p1_btn_select_sync(clk, nRst, btn_p1_select_pin, p1_btn_select);
    synchronizer p2_btn_left_sync(clk, nRst, btn_p2_left_pin, p2_btn_left);
    synchronizer p2_btn_right_sync(clk, nRst, btn_p2_right_pin, p2_btn_right);
    synchronizer p2_btn_select_sync(clk, nRst, btn_p2_select_pin, p2_btn_select);
    
    // Generate the VGA timing
    wire vga_hactive;
    wire [9:0] vga_hpos;
    wire vga_vactive;
    wire [8:0] vga_vpos;
    wire vga_line_pulse;
    wire vga_frame_pulse;
    wire vga_active;
    vga_timing vga_timing(
        .clk(clk),
        .nRst(nRst),
        .hsync(vga_hsync),
        .hactive(vga_hactive),
        .hpos(vga_hpos),
        .vsync(vga_vsync),
        .vactive(vga_vactive),
        .vpos(vga_vpos),
        .active(vga_active),
        .line_pulse(vga_line_pulse),
        .frame_pulse(vga_frame_pulse)
    );
    assign vblank = !vga_vactive;
    assign hblank = !vga_hactive;
    
    // Video mux
    wire [5:0] video_out;
    wire [5:0] border_color;
    wire draw_border;
    wire [5:0] ball_color;
    wire draw_ball;
    wire [5:0] p1_paddle_color;
    wire draw_p1_paddle;
    wire [5:0] p2_paddle_color;
    wire draw_p2_paddle;
    wire [5:0] p1_lives_color;
    wire draw_p1_lives;
    wire [5:0] p2_lives_color;
    wire draw_p2_lives;
    video_mux video_mux(
        .out(video_out),
        .in_frame(vga_active),
        .background(6'b000000),
        .border(border_color),
        .border_en(draw_border),
        .ball(ball_color),
        .ball_en(draw_ball),
        .p1_paddle(p1_paddle_color),
        .p1_paddle_en(draw_p1_paddle),
        .p2_paddle(p2_paddle_color),
        .p2_paddle_en(draw_p2_paddle),
        .p1_lives(p1_lives_color),
        .p1_lives_en(draw_p1_lives),
        .p2_lives(p2_lives_color),
        .p2_lives_en(draw_p2_lives)
    );
    assign vga_r = video_out[1:0];
    assign vga_g = video_out[3:2];
    assign vga_b = video_out[5:4];
    
    // Border generator
    border_painter #(
        .BORDER_WIDTH(BORDER_WIDTH)
    ) border (
        .in_border(draw_border),
        .color(border_color),
        .hpos(vga_hpos),
        .vpos(vga_vpos)
    );
    
    // Ball painter
    wire [9:0]ball_x;
    wire [8:0]ball_y;
    wire ball_top_en;
    wire ball_left_en;
    wire ball_bottom_en;
    wire ball_right_en;
    ball_painter ball_painter(
        .clk(clk),
        .nRst(nRst),
        .in_ball(draw_ball),
        .in_ball_top(ball_top_en),
        .in_ball_left(ball_left_en),
        .in_ball_bottom(ball_bottom_en),
        .in_ball_right(ball_right_en),
        .color(ball_color),
        .x(ball_x),
        .y(ball_y),
        .hpos(vga_hpos),
        .vpos(vga_vpos),
        .line_pulse(vga_line_pulse),
        .display_active(vga_active)
    );
    
    // Paddle painter
    wire [9:0] p1_paddle_x;
    wire [2:0] p1_paddle_segment;
    paddle_painter #(
        .PADDLE_Y(9'd456),
        .PADDLE_SEGMENT_WIDTH(PADDLE_SEGMENT_WIDTH),
        .PADDLE_NUM_SEGMENTS(PADDLE_NUM_SEGMENTS)
    ) p1_paddle_painter(
        .clk(clk),
        .nRst(nRst),
        .in_paddle(draw_p1_paddle),
        .color(p1_paddle_color),
        .x(p1_paddle_x),
        .hpos(vga_hpos),
        .vpos(vga_vpos),
        .paddle_segment(p1_paddle_segment)
    );
    wire [9:0] p2_paddle_x;
    wire [2:0] p2_paddle_segment;
    paddle_painter #(
        .PADDLE_Y('d16),
        .PADDLE_SEGMENT_WIDTH(PADDLE_SEGMENT_WIDTH),
        .PADDLE_NUM_SEGMENTS(PADDLE_NUM_SEGMENTS)
    ) p2_paddle_painter(
        .clk(clk),
        .nRst(nRst),
        .in_paddle(draw_p2_paddle),
        .color(p2_paddle_color),
        .x(p2_paddle_x),
        .hpos(vga_hpos),
        .vpos(vga_vpos),
        .paddle_segment(p2_paddle_segment)
    );
    
    // Collisions
    wire wall_collision = draw_border && draw_ball;
    wire p1_paddle_collision = draw_p1_paddle && draw_ball;
    wire p2_paddle_collision = draw_p2_paddle && draw_ball;
    wire paddle_collision = p1_paddle_collision || p2_paddle_collision;
    wire [2:0] paddle_segment = p1_paddle_collision ? p1_paddle_segment : p2_paddle_segment;
    wire collision = wall_collision || paddle_collision;

    // Lives painter
    wire [1:0] p1_lives;
    lives_painter #(
        .LIVES_Y(474)
    ) p1_lives_painter(
        .clk(clk),
        .nRst(nRst),
        .in_lives(draw_p1_lives),
        .color(p1_lives_color),
        .hactive(vga_hactive),
        .hpos(vga_hpos),
        .vpos(vga_vpos),
        .lives(p1_lives)
    );
    wire [1:0] p2_lives;
    lives_painter #(
        .LIVES_Y(2)
    ) p2_lives_painter(
        .clk(clk),
        .nRst(nRst),
        .in_lives(draw_p2_lives),
        .color(p2_lives_color),
        .hactive(vga_hactive),
        .hpos(vga_hpos),
        .vpos(vga_vpos),
        .lives(p2_lives)
    );

    // Sound generator
    sound_gen sound_gen(
        .clk(clk),
        .nRst(nRst),
        .sound(sound_out),
        .line_pulse(vga_line_pulse),
        .frame_pulse(vga_frame_pulse),
        .high_beep(collision),
        .low_beep(ball_out_of_bounds)
    );
    
    // Game logic
    wire [0:0] game_state;
    wire ball_out_of_bounds;
    game_logic #(
        .PADDLE_WIDTH(PADDLE_SEGMENT_WIDTH * PADDLE_NUM_SEGMENTS),
        .BORDER_WIDTH(BORDER_WIDTH),
        .INITIAL_BALL_X(INITIAL_BALL_X),
        .INITIAL_BALL_Y(INITIAL_BALL_Y),
        .INITIAL_VEL_X(INITIAL_VEL_X),
        .INITIAL_VEL_Y(INITIAL_VEL_Y)
    ) game_logic(
        .clk(clk),
        .nRst(nRst),
        .ball_x(ball_x),
        .ball_y(ball_y),
        .p1_paddle_x(p1_paddle_x),
        .p2_paddle_x(p2_paddle_x),
        .p1_lives(p1_lives),
        .p2_lives(p2_lives),
        .frame_pulse(vga_frame_pulse),
        .p1_btn_action(p1_btn_select),
        .p1_btn_left(p1_btn_left),
        .p1_btn_right(p1_btn_right),
        .p2_btn_action(p2_btn_select),
        .p2_btn_left(p2_btn_left),
        .p2_btn_right(p2_btn_right),
        .collision(collision),
        .paddle_collision(paddle_collision),
        .paddle_segment(paddle_segment),
        .ball_top_col(ball_top_en),
        .ball_left_col(ball_left_en),
        .ball_bottom_col(ball_bottom_en),
        .ball_right_col(ball_right_en),
        .game_state(game_state),
        .ball_out_of_bounds(ball_out_of_bounds)
    );
    
endmodule
