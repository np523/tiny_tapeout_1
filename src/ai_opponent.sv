module ai_opponent #(
    parameter PADDLE_WIDTH = 24,
    parameter PADDLE_OFFSET = PADDLE_WIDTH/2,
    parameter BALL_WIDTH = 5,
    parameter BALL_OFFSET = BALL_WIDTH/2,
    parameter PADDLE_SPEED_INIT = 2
)(
    input logic clk,
    input logic nRst,
    input logic [9:0] ball_x,
    input logic [9:0] paddle_2_x,
    input logic [2:0] paddle_speed,

    output logic move_left,
    output logic move_right
);

logic [9:0] ball_pos;
logic [9:0] paddle_pos;
logic [1:0] vel_shift;

always_comb begin

    case(paddle_speed) 

    2 : vel_shift = 1;

    3: vel_shift = 2; 

    4: vel_shift = 3;

    default: vel_shift = 0;

    endcase
end 

assign ball_pos = (ball_x + BALL_OFFSET) >> vel_shift;
assign paddle_pos = (paddle_2_x + PADDLE_OFFSET) >> vel_shift;

always_comb begin
    if(~nRst) begin
        move_left = 0;
        move_right = 0;
    end else begin
        if(paddle_pos > ball_pos)
            {move_left, move_right} = 2'b10;
        else if(paddle_pos < ball_pos)
            {move_left, move_right} = 2'b01;
        else {move_left, move_right} = 2'b00;
    end
end

endmodule
