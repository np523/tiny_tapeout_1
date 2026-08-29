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


module game_logic 
#(
    parameter INITIAL_BALL_X = 10'd320 - 3'd2,
    parameter INITIAL_BALL_Y = 9'd452 - 3'd2,
    parameter INITIAL_VEL_X = 4'sd2,
    parameter INITIAL_VEL_Y = -4'sd2,
    parameter PADDLE_SPEED = 1,
    parameter PADDLE_WIDTH = 64,
    parameter INITIAL_PADDLE_X = 10'd320 - PADDLE_WIDTH / 2 - 1,
    parameter BORDER_WIDTH = 8
)(
    input clk,
    input nRst,
    output [9:0] ball_x,
    output [8:0] ball_y,
    output [9:0] p1_paddle_x,
    output [9:0] p2_paddle_x,
    output reg [1:0] p1_lives,
    output reg [1:0] p2_lives,
    input frame_pulse,
    input p1_btn_action,
    input p1_btn_left,
    input p1_btn_right,
    input p2_btn_action,
    input p2_btn_left,
    input p2_btn_right,
    input collision,
    input paddle_collision,
    input [2:0] paddle_segment,
    input ball_top_col,
    input ball_left_col,
    input ball_bottom_col,
    input ball_right_col,
    output reg [0:0] game_state,
    output wire ball_out_of_bounds
);

    wire p1_paddle_is_at_left_limit;
    wire p1_paddle_is_at_right_limit;
    wire p2_paddle_is_at_left_limit;
    wire p2_paddle_is_at_right_limit;
    wire p1_out_of_lives = p1_lives == 2'd0;
    wire p2_out_of_lives = p2_lives == 2'd0;
    wire end_of_game = (p1_out_of_lives || p2_out_of_lives) && ball_out_of_bounds;
    wire ball_out_of_bounds_p1;
    wire ball_out_of_bounds_p2;

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
                        end else if(ball_out_of_bounds_p2) begin
                            game_state <= STATE_START;                        
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
    reg latched_ball_top_collision;
    reg latched_ball_bottom_collision;
    reg latched_ball_left_collision;
    reg latched_ball_right_collision;
    reg latched_paddle_collision;
    reg [2:0] latched_paddle_segment;
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

    reg signed [3:0] velocity_x;
    reg signed [3:0] velocity_y;
    reg signed [11:0] ball_state_x;
    reg signed [10:0] ball_state_y;
    assign ball_out_of_bounds_p2 = ball_state_y[10:1] >= 9'd500;
    assign ball_out_of_bounds_p1 = ball_state_y[10:1] >= 9'd488 && !ball_out_of_bounds_p2;
    assign ball_out_of_bounds = ball_out_of_bounds_p1 || ball_out_of_bounds_p2;

    reg signed [3:0] next_velocity_x;
    reg signed [3:0] next_velocity_y;
    always @(*)
    begin
        case(game_state)
            STATE_START: begin
                if (p1_btn_action || p2_btn_action) begin
                    next_velocity_x <= INITIAL_VEL_X;
                    next_velocity_y <= INITIAL_VEL_Y;
                end else begin
                    next_velocity_x <= 0;
                    next_velocity_y <= 0;
                end
            end
            STATE_PLAYING: begin
                if(ball_out_of_bounds) begin
                    next_velocity_x <= INITIAL_VEL_X;
                    next_velocity_y <= INITIAL_VEL_Y;
                end else if (latched_paddle_collision) begin
                    case(latched_paddle_segment)
                        3'b000: next_velocity_x <= -3;
                        3'b001: next_velocity_x <= -2;
                        3'b010: next_velocity_x <= -1;
                        3'b011: next_velocity_x <= 1;
                        3'b100: next_velocity_x <= 2;
                        3'b101: next_velocity_x <= 3;
                    endcase
                    next_velocity_y <= -velocity_y;
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
                    next_velocity_x <= velocity_x;
                    next_velocity_y <= -velocity_y;
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
                    next_velocity_x <= -velocity_x;
                    next_velocity_y <= velocity_y;
                end else begin
                    next_velocity_x <= velocity_x;
                    next_velocity_y <= velocity_y;
                end
            end
        endcase
    end

    always @(posedge clk or negedge nRst)
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
    reg [9:0] p1_paddle_state_x;
    // Ignore the bottom bit to account for the velocity of the paddle
    assign p1_paddle_is_at_left_limit = p1_paddle_state_x[9:1] == (BORDER_WIDTH >> 1) - 1;
    assign p1_paddle_is_at_right_limit = p1_paddle_state_x[9:1] == (640 - BORDER_WIDTH - PADDLE_WIDTH) >> 1;
    always @(posedge clk or negedge nRst)
    begin
        if(!nRst) begin
            p1_paddle_state_x <= INITIAL_PADDLE_X;
        end else begin
            if(frame_pulse) begin
                if(ball_out_of_bounds) begin
                    p1_paddle_state_x <= INITIAL_PADDLE_X;
                end else if (p1_btn_left && !p1_paddle_is_at_left_limit) begin
                    p1_paddle_state_x <= p1_paddle_state_x - PADDLE_SPEED;
                end else if (p1_btn_right && !p1_paddle_is_at_right_limit) begin
                    p1_paddle_state_x <= p1_paddle_state_x + PADDLE_SPEED;
                end
            end
        end
    end
    
    assign p1_paddle_x = p1_paddle_state_x;

    reg [9:0] p2_paddle_state_x;
    // Ignore the bottom bit to account for the velocity of the paddle
    assign p2_paddle_is_at_left_limit = p2_paddle_state_x[9:1] == BORDER_WIDTH >> 1;
    assign p2_paddle_is_at_right_limit = p2_paddle_state_x[9:1] == (640 - BORDER_WIDTH - PADDLE_WIDTH) >> 1;
    always @(posedge clk or negedge nRst)
    begin
        if(!nRst) begin
            p2_paddle_state_x <= INITIAL_PADDLE_X;
        end else begin
            if(frame_pulse) begin
                if(ball_out_of_bounds) begin
                    p2_paddle_state_x <= INITIAL_PADDLE_X;
                end else if (p2_btn_left && !p2_paddle_is_at_left_limit) begin
                    p2_paddle_state_x <= p2_paddle_state_x - PADDLE_SPEED;
                end else if (p2_btn_right && !p2_paddle_is_at_right_limit) begin
                    p2_paddle_state_x <= p2_paddle_state_x + PADDLE_SPEED;
                end
            end
        end
    end
    
    assign p2_paddle_x = p2_paddle_state_x;

endmodule
