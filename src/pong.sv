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
    parameter INITIAL_BALL_X = 10'd320 - 10'd2,
    parameter INITIAL_BALL_Y = 9'd340 - 9'd2,
    parameter INITIAL_VEL_X = 4'sd0,
    parameter INITIAL_VEL_Y = 4'sd2,
    parameter P2_LIVES_OFFSET = 2, 
    parameter P1_LIVES_OFFSET = 466
)(
    input logic clk,
    input logic nRst,
    input logic en,
    input logic btn_p1_left_pin,
    input logic btn_p1_right_pin,
    input logic btn_p1_select_pin,
    input logic btn_p2_left_pin,
    input logic btn_p2_right_pin,
    input logic btn_p2_select_pin,
    input logic ai_mode_select,
    output logic  [1:0] vga_r,
    output logic  [1:0] vga_g,
    output logic  [1:0] vga_b,
    output logic  vga_hsync,
    output logic  vga_vsync,
    output logic  vblank,
    output logic  hblank
    );

    
    // Synchronize the inputs
    logic p1_btn_left;
    logic p1_btn_right;
    logic p1_btn_select;
    logic p2_btn_left;
    logic p2_btn_right;
    logic p2_btn_select;
    synchronizer p1_btn_left_sync(clk, nRst, btn_p1_left_pin, p1_btn_left);
    synchronizer p1_btn_right_sync(clk, nRst, btn_p1_right_pin, p1_btn_right);
    synchronizer p1_btn_select_sync(clk, nRst, btn_p1_select_pin, p1_btn_select);
    synchronizer p2_btn_left_sync(clk, nRst, btn_p2_left_pin, p2_btn_left);
    synchronizer p2_btn_right_sync(clk, nRst, btn_p2_right_pin, p2_btn_right);
    synchronizer p2_btn_select_sync(clk, nRst, btn_p2_select_pin, p2_btn_select);
    
    // Generate the VGA timing
    logic vga_hactive;
    logic [9:0] vga_hpos;
    logic vga_vactive;
    logic [8:0] vga_vpos;
    logic vga_line_pulse;
    logic vga_frame_pulse;
    logic vga_active;
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
    logic [5:0] video_out;
    logic [5:0] border_color;
    logic draw_border;
    logic [5:0] ball_color;
    logic draw_ball;
    logic [5:0] paddle_color;
    logic draw_p1_paddle;
    logic draw_p2_paddle;
    logic [5:0] lives_color;
    logic draw_lives;
    logic [5:0] copper_color;
    logic draw_copper;
    logic [5:0] starfield_color;
    video_mux video_mux(
        .out(video_out),
        .in_frame(vga_active),
        .background(starfield_color),
        .border(border_color),
        .border_en(draw_border),
        .ball(ball_color),
        .ball_en(draw_ball),
        .paddle(paddle_color),
        .paddle_en(draw_p1_paddle || draw_p2_paddle),
        .lives(lives_color),
        .lives_en(draw_lives),
        .copper(copper_color),
        .copper_en(draw_copper)
    );
    assign vga_r = video_out[1:0];
    assign vga_g = video_out[3:2];
    assign vga_b = video_out[5:4];
    
    // Starfield background
    starfield_painter starfield_painter(
        .clk(clk),
        .nRst(nRst),
        .frame_pulse(vga_frame_pulse),
        .hpos(vga_hpos),
        .vpos(vga_vpos),
        .color(starfield_color)
    );

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
    logic [9:0]ball_x;
    logic [8:0]ball_y;
    logic ball_top_en;
    logic ball_left_en;
    logic ball_bottom_en;
    logic ball_right_en;
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
    
    // Paddle painter (one shared instance - the two paddles sit in opposite
    // halves of the frame, so they are never active on the same scanline)
    logic [9:0] p1_paddle_x;
    logic [9:0] p2_paddle_x;
    logic [2:0] paddle_segment;
    paddle_painter #(
        .P1_PADDLE_Y(9'd456),
        .P2_PADDLE_Y('d16),
        .PADDLE_SEGMENT_WIDTH(PADDLE_SEGMENT_WIDTH),
        .PADDLE_NUM_SEGMENTS(PADDLE_NUM_SEGMENTS)
    ) paddle_painter (
        .clk(clk),
        .nRst(nRst),
        .in_p1_paddle(draw_p1_paddle),
        .in_p2_paddle(draw_p2_paddle),
        .color(paddle_color),
        .p1_x(p1_paddle_x),
        .p2_x(p2_paddle_x),
        .hpos(vga_hpos),
        .vpos(vga_vpos),
        .paddle_segment(paddle_segment)
    );

    logic wall_collision;
    logic p1_paddle_collision;
    logic p2_paddle_collision;
    logic paddle_collision;
    logic collision;
    assign wall_collision = draw_border && draw_ball;
    assign p1_paddle_collision = draw_p1_paddle && draw_ball;
    assign p2_paddle_collision = draw_p2_paddle && draw_ball;
    assign paddle_collision = p1_paddle_collision || p2_paddle_collision;
    assign collision = wall_collision || paddle_collision;

    // Lives painter (one shared instance - the two bands are 464 rows apart,
    // so they are never active on the same scanline)
    logic [1:0] p1_lives;
    logic [1:0] p2_lives;
    lives_painter #(
        .P1_LIVES_Y(P1_LIVES_OFFSET),
        .P2_LIVES_Y(P2_LIVES_OFFSET)
    ) lives_painter (
        .clk(clk),
        .nRst(nRst),
        .in_lives(draw_lives),
        .color(lives_color),
        .hactive(vga_hactive),
        .hpos(vga_hpos),
        .vpos(vga_vpos),
        .p1_lives(p1_lives),
        .p2_lives(p2_lives)
    );

    
    // Game logic
    logic [0:0] game_state;
    logic ball_out_of_bounds;
    logic p2_btn_left_real;
    logic p2_btn_right_real;
    logic [1:0] speed_tier;
    logic [2:0] paddle_speed;
    logic ai_move_left;
    logic ai_move_right;
    logic end_of_game;

    logic ball_out_of_bounds_prev;
    logic point_scored_pulse;
    logic game_over_pulse;
    always_ff @(posedge clk or negedge nRst) begin
        if(!nRst) begin
            ball_out_of_bounds_prev <= 1'b0;
        end else begin
            ball_out_of_bounds_prev <= ball_out_of_bounds;
        end
    end
    assign point_scored_pulse = ball_out_of_bounds && !ball_out_of_bounds_prev && !end_of_game;
    assign game_over_pulse = ball_out_of_bounds && !ball_out_of_bounds_prev && end_of_game;

    assign p2_btn_left_real = ai_mode_select ? ai_move_left : p2_btn_left;
    assign p2_btn_right_real = ai_mode_select ? ai_move_right : p2_btn_right;

    game_logic #(
        .PADDLE_WIDTH(PADDLE_SEGMENT_WIDTH * PADDLE_NUM_SEGMENTS),
        .BORDER_WIDTH(BORDER_WIDTH),
        .INITIAL_BALL_X(INITIAL_BALL_X),
        .INITIAL_BALL_Y(INITIAL_BALL_Y),
        .INITIAL_VEL_X(INITIAL_VEL_X),
        .INITIAL_VEL_Y(INITIAL_VEL_Y)
    ) game_logic (
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
        .p2_btn_left(p2_btn_left_real),
        .p2_btn_right(p2_btn_right_real),
        .collision(collision),
        .paddle_collision(paddle_collision),
        .paddle_segment(paddle_segment),
        .ball_top_col(ball_top_en),
        .ball_left_col(ball_left_en),
        .ball_bottom_col(ball_bottom_en),
        .ball_right_col(ball_right_en),
        .game_state(game_state),
        .ball_out_of_bounds(ball_out_of_bounds),
        .speed_tier(speed_tier),
        .paddle_speed(paddle_speed),
        .end_of_game(end_of_game)
    );

    // Copper bars disabled in this reduced-congestion variant: the painter is
    // tied off so synthesis removes it entirely, along with video_mux's
    // copper branch.
    assign draw_copper = 1'b0;
    assign copper_color = 6'b000000;

    ai_opponent #(
        .PADDLE_WIDTH(PADDLE_SEGMENT_WIDTH * PADDLE_NUM_SEGMENTS)
    ) ai_opponent (
        .clk(clk),
        .nRst(nRst),
        .ball_x(ball_x),
        .paddle_2_x(p2_paddle_x),
        .paddle_speed(paddle_speed),
        .move_left(ai_move_left),
        .move_right(ai_move_right)
    );
    
endmodule
