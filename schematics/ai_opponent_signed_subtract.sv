module ai_proposed #(
    parameter PADDLE_WIDTH = 24,
    parameter PADDLE_OFFSET = PADDLE_WIDTH/2,
    parameter BALL_WIDTH = 5,
    parameter BALL_OFFSET = BALL_WIDTH/2
)(
    input logic clk,
    input logic nRst,
    input logic [9:0] ball_x,
    input logic [9:0] paddle_2_x,
    input logic [2:0] paddle_speed,
    output logic move_left,
    output logic move_right
);
logic signed [11:0] diff;
logic [2:0] deadband;
assign diff = $signed({2'b0, paddle_2_x}) - $signed({2'b0, ball_x})
              + (PADDLE_OFFSET - BALL_OFFSET);
always_comb begin
    case(paddle_speed)
        3'd2: deadband = 3'd1;
        3'd3: deadband = 3'd1;
        3'd4: deadband = 3'd2;
        default: deadband = 3'd1;
    endcase
end
always_comb begin
    if(~nRst) begin
        move_left = 0;
        move_right = 0;
    end else begin
        if(diff > $signed({1'b0, deadband}))
            {move_left, move_right} = 2'b10;
        else if(diff < -$signed({1'b0, deadband}))
            {move_left, move_right} = 2'b01;
        else
            {move_left, move_right} = 2'b00;
    end
end
endmodule
