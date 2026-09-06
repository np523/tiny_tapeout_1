`default_nettype none
`timescale 1ns / 1ps

/* Unit-level testbench: instantiates game_logic ALONE - no pong.sv, no VGA
   timing chain, no top-level pin mapping. This is what makes directed
   corner-case testing affordable: the full-system testbench needs 800*525
   cycles of real pixel scan-out to produce one frame_pulse, whereas here
   the cocotb driver pulses frame_pulse directly, so a "frame" costs a
   handful of cycles instead of 420,000.

   Parameters mirror the overrides pong.sv actually instantiates game_logic
   with, NOT game_logic's own defaults (which differ: PADDLE_WIDTH 64 vs 24,
   INITIAL_VEL_X 2 vs 0, etc.) - so unit-level behaviour matches the
   integrated design exactly.
*/
module tb_game_logic ();

  initial begin
    $dumpfile("tb_game_logic.fst");
    $dumpvars(0, tb_game_logic);
    #1;
  end

  reg clk;
  reg nRst;
  reg frame_pulse;
  reg p1_btn_action, p1_btn_left, p1_btn_right;
  reg p2_btn_action, p2_btn_left, p2_btn_right;
  reg collision, paddle_collision;
  reg [2:0] paddle_segment;
  reg ball_top_col, ball_left_col, ball_bottom_col, ball_right_col;

  wire [9:0] ball_x;
  wire [8:0] ball_y;
  wire [9:0] p1_paddle_x;
  wire [9:0] p2_paddle_x;
  wire [1:0] p1_lives;
  wire [1:0] p2_lives;
  wire [0:0] game_state;
  wire ball_out_of_bounds;
  wire [1:0] speed_tier;
  wire [2:0] paddle_speed;

  game_logic #(
      .PADDLE_WIDTH(4 * 6),
      .BORDER_WIDTH(8),
      .INITIAL_BALL_X(10'd320 - 3'd2),
      .INITIAL_BALL_Y(9'd340 - 3'd2),
      .INITIAL_VEL_X(4'sd0),
      .INITIAL_VEL_Y(4'sd2)
  ) game_logic (
      .clk(clk),
      .nRst(nRst),
      .ball_x(ball_x),
      .ball_y(ball_y),
      .p1_paddle_x(p1_paddle_x),
      .p2_paddle_x(p2_paddle_x),
      .p1_lives(p1_lives),
      .p2_lives(p2_lives),
      .frame_pulse(frame_pulse),
      .p1_btn_action(p1_btn_action),
      .p1_btn_left(p1_btn_left),
      .p1_btn_right(p1_btn_right),
      .p2_btn_action(p2_btn_action),
      .p2_btn_left(p2_btn_left),
      .p2_btn_right(p2_btn_right),
      .collision(collision),
      .paddle_collision(paddle_collision),
      .paddle_segment(paddle_segment),
      .ball_top_col(ball_top_col),
      .ball_left_col(ball_left_col),
      .ball_bottom_col(ball_bottom_col),
      .ball_right_col(ball_right_col),
      .game_state(game_state),
      .ball_out_of_bounds(ball_out_of_bounds),
      .speed_tier(speed_tier),
      .paddle_speed(paddle_speed)
  );

endmodule
