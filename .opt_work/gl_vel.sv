`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/09/2023 07:48:32 PM
// Design Name: 
// Module Name: ball_logic
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


module gl_vel 
#(
    parameter INITIAL_BALL_X = 10'd320 - 3'd2,
    parameter INITIAL_BALL_Y = 9'd452 - 3'd2,
    parameter INITIAL_VEL_X = 4'sd2,
    parameter INITIAL_VEL_Y = -4'sd2,
    parameter PADDLE_SPEED_INIT = 2,
    parameter PADDLE_MID_SPEED = 3,
    parameter PADDLE_TOP_SPEED = 4,
    parameter PADDLE_WIDTH = 64,
    parameter INITIAL_PADDLE_X = 10'd320 - PADDLE_WIDTH / 2 - 1,
    parameter BORDER_WIDTH = 8,
    parameter HIT_CNT_WIDTH = 4, 
    parameter SPEED2_CNT = 4, 
    parameter SPEED3_CNT = 8, 
    parameter SPEED4_CNT = 12,
    parameter TOP_SPEED_Y = 6, 
    parameter SPEED_3_Y = 5,
    parameter SPEED_2_Y = 4,
    parameter INIT_SPEED_Y = 2
)(
    input logic  clk,
    input logic  nRst,
    output logic   [9:0] ball_x,
    output logic   [8:0] ball_y,
    output logic   [9:0] p1_paddle_x,
    output logic   [9:0] p2_paddle_x,
    output logic [1:0] p1_lives,
    output logic [1:0] p2_lives,
    input logic  frame_pulse,
    input logic  p1_btn_action,
    input logic  p1_btn_left,
    input logic  p1_btn_right,
    input logic  p2_btn_action,
    input logic  p2_btn_left,
    input logic  p2_btn_right,
    input logic  collision,
    input logic  paddle_collision,
    input logic  [2:0] paddle_segment,
    input logic  ball_top_col,
    input logic  ball_left_col,
    input logic  ball_bottom_col,
    input logic  ball_right_col,
    output logic [0:0] game_state,
    output logic ball_out_of_bounds,
    output logic [1:0] speed_tier,
    output logic [2:0] paddle_speed
);

    logic p1_out_of_lives;
    logic p2_out_of_lives;
    logic end_of_game;
    logic ball_out_of_bounds_p1;
    logic ball_out_of_bounds_p2;

    logic [3:0] hit_counter;
    logic speed2_en;
    logic speed3_en;
    logic speed4_en;
    logic speed2;
    logic speed3;
    logic speed4;

    assign speed2_en = (hit_counter >= SPEED2_CNT);
    assign speed3_en = (hit_counter >= SPEED3_CNT);
    assign speed4_en = (hit_counter >= SPEED4_CNT);

    logic [1:0] speed_factor_x;

    assign speed_factor_x = speed2_en + speed3_en + speed4_en;
    assign speed_tier = speed_factor_x;

    assign speed2 = (speed2_en && ~speed3_en);
    assign speed3 = (speed3_en && ~speed4_en);
    assign speed4 = speed4_en;

    logic [2:0] speed_factor_y;

    always_comb begin
        speed_factor_y = speed4 ? TOP_SPEED_Y : speed3 ? SPEED_3_Y : speed2 ? SPEED_2_Y : INIT_SPEED_Y;
    end

    always_comb begin
        paddle_speed = speed4 ? PADDLE_TOP_SPEED : speed3 ? PADDLE_MID_SPEED : PADDLE_SPEED_INIT;
    end


    assign p1_out_of_lives = p1_lives == 2'd0;
    assign p2_out_of_lives = p2_lives == 2'd0;
    assign end_of_game = (p1_out_of_lives || p2_out_of_lives) && ball_out_of_bounds;

    /////////////////////////////////////////////
    // Game state
    /////////////////////////////////////////////
    localparam STATE_START = 0;
    localparam STATE_PLAYING = 1;
    always @(posedge clk or negedge nRst)
    begin
        if(!nRst) begin
            game_state <= STATE_START;
            p1_lives <= 2'd3;
            p2_lives <= 2'd3;
        end else begin
            if(frame_pulse) begin
                case(game_state)
                    STATE_START: begin
                        if (p1_btn_action || p2_btn_action) begin
                            game_state <= STATE_PLAYING;
                        end
                    end
                    STATE_PLAYING: begin
                        if(ball_out_of_bounds_p1) begin
                            game_state <= STATE_START;
                            p1_lives <= end_of_game ? 2'd3 : p1_lives - 1'b1;
                            p2_lives <= end_of_game ? 2'd3 : p2_lives;
                        end else if(ball_out_of_bounds_p2) begin
                            game_state <= STATE_START;
                            p1_lives <= end_of_game ? 2'd3 : p1_lives;                        
                            p2_lives <= end_of_game ? 2'd3 : p2_lives - 1'b1;
                        end
                    end
                endcase
            end
        end
    end




    /////////////////////////////////////////////
    // Ball logic
    /////////////////////////////////////////////
    // Latched collisions
    // Collisions are evaluated at the end of the frame but we keep track of collisions during the drawing.
    logic latched_ball_top_collision;
    logic latched_ball_bottom_collision;
    logic latched_ball_left_collision;
    logic latched_ball_right_collision;
    logic latched_paddle_collision;
    logic [2:0] latched_paddle_segment;
    always @(posedge clk or negedge nRst)
    begin
        if(!nRst) begin
            latched_ball_top_collision <= 1'b0;
            latched_ball_bottom_collision <= 1'b0;
            latched_ball_left_collision <= 1'b0;
            latched_ball_right_collision <= 1'b0;
            latched_paddle_collision <= 1'b0;
            latched_paddle_segment <= 3'b0;
        end else begin
            if (frame_pulse) begin
                latched_ball_top_collision <= 1'b0;
                latched_ball_bottom_collision <= 1'b0;
                latched_ball_left_collision <= 1'b0;
                latched_ball_right_collision <= 1'b0;
                latched_paddle_collision <= 1'b0;
                latched_paddle_segment <= 3'b0;
            end else if(collision) begin
                latched_ball_top_collision <= latched_ball_top_collision | ball_top_col;
                latched_ball_bottom_collision <= latched_ball_bottom_collision | ball_bottom_col;
                latched_ball_left_collision <= latched_ball_left_collision | ball_left_col;
                latched_ball_right_collision <= latched_ball_right_collision | ball_right_col;
                latched_paddle_collision <= latched_paddle_collision | paddle_collision;
            end
            if(paddle_collision) begin
                latched_paddle_segment <= paddle_segment;
            end
        end
    end

     always_ff @(posedge clk or negedge nRst) begin
        if(!nRst) begin
            hit_counter <= '0;
        end else begin
            if(end_of_game) begin
                hit_counter <= '0;
            end else if(collision && paddle_collision && !latched_paddle_collision) begin
                hit_counter <= (hit_counter == '1) ? hit_counter : hit_counter + 1'b1;
            end
        end
    end

    logic signed [3:0] velocity_x;
    logic signed [3:0] velocity_y;
    logic signed [11:0] ball_state_x;
    logic signed [10:0] ball_state_y;
    assign ball_out_of_bounds_p2 = ball_state_y[10:1] >= 500;
    assign ball_out_of_bounds_p1 = ball_state_y[10:1] >= 488 && !ball_out_of_bounds_p2;
    assign ball_out_of_bounds = ball_out_of_bounds_p1 || ball_out_of_bounds_p2;

    logic signed [3:0] next_velocity_x;
    logic signed [3:0] next_velocity_y;

    logic [2:0] seg_base;
    logic [2:0] tier_off;
    logic [3:0] vx_magnitude;
    assign seg_base = (latched_paddle_segment < 3) ? (3'd3 - latched_paddle_segment)
                                                   : (latched_paddle_segment - 3'd2);
    assign tier_off = (speed_factor_x == 2'd3) ? 3'd4 : {1'b0, speed_factor_x};
    assign vx_magnitude = {1'b0, seg_base} + {1'b0, tier_off};
    always_comb begin
        case(game_state)
            STATE_START: begin
                if (p1_btn_action || p2_btn_action) begin
                    next_velocity_x = INITIAL_VEL_X;
                    next_velocity_y = INITIAL_VEL_Y;
                end else begin
                    next_velocity_x = 0;
                    next_velocity_y = 0;
                end
            end
            STATE_PLAYING: begin
                if(ball_out_of_bounds) begin
                    next_velocity_x = INITIAL_VEL_X;
                    next_velocity_y = INITIAL_VEL_Y;
                end else if (latched_paddle_collision) begin
                    if(latched_paddle_segment > 5) begin
                        next_velocity_x = velocity_x;
                    end else if (latched_paddle_segment < 3) begin
                        next_velocity_x = -$signed(vx_magnitude);
                    end else begin
                        next_velocity_x = $signed(vx_magnitude);
                    end
                    next_velocity_y = (velocity_y < 0) ? speed_factor_y : -speed_factor_y;

                end else if (
                    (!latched_ball_left_collision &&  latched_ball_top_collision && !latched_ball_right_collision && !latched_ball_bottom_collision) || // Top collisions
                    ( latched_ball_left_collision &&  latched_ball_top_collision &&  latched_ball_right_collision && !latched_ball_bottom_collision) ||
                    ( latched_ball_left_collision &&  latched_ball_top_collision && !latched_ball_right_collision && !latched_ball_bottom_collision) ||
                    (!latched_ball_left_collision &&  latched_ball_top_collision &&  latched_ball_right_collision && !latched_ball_bottom_collision) ||
                    (!latched_ball_left_collision && !latched_ball_top_collision && !latched_ball_right_collision &&  latched_ball_bottom_collision) || // Bottom collisions
                    ( latched_ball_left_collision && !latched_ball_top_collision &&  latched_ball_right_collision &&  latched_ball_bottom_collision) ||
                    ( latched_ball_left_collision && !latched_ball_top_collision && !latched_ball_right_collision &&  latched_ball_bottom_collision) ||
                    (!latched_ball_left_collision && !latched_ball_top_collision &&  latched_ball_right_collision &&  latched_ball_bottom_collision)
                ) begin
                    next_velocity_x = velocity_x;
                    next_velocity_y = -velocity_y;
                end else if (
                    // This contains duplicates from the top and bottom collisions, This is fine and will be optimized away.
                    (!latched_ball_left_collision && !latched_ball_top_collision &&  latched_ball_right_collision && !latched_ball_bottom_collision) || // Right collisions
                    (!latched_ball_left_collision &&  latched_ball_top_collision &&  latched_ball_right_collision &&  latched_ball_bottom_collision) ||
                    (!latched_ball_left_collision && !latched_ball_top_collision &&  latched_ball_right_collision &&  latched_ball_bottom_collision) ||
                    (!latched_ball_left_collision &&  latched_ball_top_collision &&  latched_ball_right_collision && !latched_ball_bottom_collision) ||
                    ( latched_ball_left_collision && !latched_ball_top_collision && !latched_ball_right_collision && !latched_ball_bottom_collision) || // Left collisions
                    ( latched_ball_left_collision &&  latched_ball_top_collision && !latched_ball_right_collision &&  latched_ball_bottom_collision) ||
                    ( latched_ball_left_collision && !latched_ball_top_collision && !latched_ball_right_collision &&  latched_ball_bottom_collision) ||
                    ( latched_ball_left_collision &&  latched_ball_top_collision && !latched_ball_right_collision && !latched_ball_bottom_collision)
                ) begin
                    next_velocity_x = -velocity_x;
                    next_velocity_y = velocity_y;
                end else begin
                    next_velocity_x = velocity_x;
                    next_velocity_y = velocity_y;
                end
            end
        endcase
    end

    always_ff @(posedge clk or negedge nRst)
    begin
        if(!nRst) begin
            ball_state_x <= {INITIAL_BALL_X, 1'b0};
            ball_state_y <= {INITIAL_BALL_Y, 1'b0};
            velocity_x <= INITIAL_VEL_X;
            velocity_y <= INITIAL_VEL_Y;
        end else begin
            if(frame_pulse) begin
                velocity_x <= next_velocity_x;
                velocity_y <= next_velocity_y;
                if(ball_out_of_bounds) begin
                    ball_state_x <= {INITIAL_BALL_X, 1'b0};
                    ball_state_y <= {INITIAL_BALL_Y, 1'b0};
                end else begin
                    ball_state_x <= ball_state_x + next_velocity_x;
                    ball_state_y <= ball_state_y + next_velocity_y;
                end
            end
        end
    end
    
    assign ball_x = ball_state_x[10:1];
    assign ball_y = ball_state_y[9:1];

    /////////////////////////////////////////////
    // Paddle logic
    /////////////////////////////////////////////    
    localparam P1_LEFT_LIMIT_RAW = 2 * ((BORDER_WIDTH >> 1) - 1) + 1;
    localparam P2_LEFT_LIMIT_RAW = 2 * (BORDER_WIDTH >> 1) + 1;
    localparam RIGHT_LIMIT_RAW = (640 - BORDER_WIDTH - PADDLE_WIDTH);

    logic [9:0] p1_paddle_state_x;
    always_ff @(posedge clk or negedge nRst)
    begin
        if(!nRst) begin
            p1_paddle_state_x <= INITIAL_PADDLE_X;
        end else begin
            if(frame_pulse) begin
                if(ball_out_of_bounds) begin
                    p1_paddle_state_x <= INITIAL_PADDLE_X;
                end else if (p1_btn_left) begin
                    p1_paddle_state_x <= (p1_paddle_state_x > P1_LEFT_LIMIT_RAW + paddle_speed)
                                         ? p1_paddle_state_x - paddle_speed
                                         : P1_LEFT_LIMIT_RAW;
                end else if (p1_btn_right) begin
                    p1_paddle_state_x <= (p1_paddle_state_x < RIGHT_LIMIT_RAW - paddle_speed)
                                         ? p1_paddle_state_x + paddle_speed
                                         : RIGHT_LIMIT_RAW;
                end
            end
        end
    end

    assign p1_paddle_x = p1_paddle_state_x;

    logic [9:0] p2_paddle_state_x;
    always_ff @(posedge clk or negedge nRst)
    begin
        if(!nRst) begin
            p2_paddle_state_x <= INITIAL_PADDLE_X;
        end else begin
            if(frame_pulse) begin
                if(ball_out_of_bounds) begin
                    p2_paddle_state_x <= INITIAL_PADDLE_X;
                end else if (p2_btn_left) begin
                    p2_paddle_state_x <= (p2_paddle_state_x > P2_LEFT_LIMIT_RAW + paddle_speed)
                                         ? p2_paddle_state_x - paddle_speed
                                         : P2_LEFT_LIMIT_RAW;
                end else if (p2_btn_right) begin
                    p2_paddle_state_x <= (p2_paddle_state_x < RIGHT_LIMIT_RAW - paddle_speed)
                                         ? p2_paddle_state_x + paddle_speed
                                         : RIGHT_LIMIT_RAW;
                end
            end
        end
    end

    assign p2_paddle_x = p2_paddle_state_x;

endmodule
