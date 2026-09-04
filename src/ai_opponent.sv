module ai_opponent #(
    parameter [4:0] PADDLE_WIDTH = 24, 
    parameter [3:0] PADDLE_OFFSET = PADDLE_WIDTH/2,
    parameter [2:0] BALL_WIDTH = 5, 
    parameter [1:0] BALL_OFFSET = BALL_WIDTH/2
)(
    input logic clk,
    input logic nRst, 
    input logic [9:0] ball_x, 
    input logic [9:0] paddle_2_x, 
    
    output logic move_left,
    output logic move_right
);

logic [9:0] ball_pos;
logic [9:0] paddle_pos;

assign ball_pos = ball_x + BALL_OFFSET; // approx compensate for width of paddle
assign paddle_pos = paddle_2_x + PADDLE_OFFSET;

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