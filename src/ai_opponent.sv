module ai_opponent #(
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

localparam int BIAS = 1024;
localparam int CENTRE_ADJ = PADDLE_OFFSET - BALL_OFFSET;

logic [11:0] biased_diff;
logic [11:0] left_thresh;
logic [11:0] right_thresh;

assign biased_diff = (paddle_2_x + (BIAS + CENTRE_ADJ)) - ball_x;

always_comb begin
    case(paddle_speed)
        3'd4: begin
            left_thresh  = BIAS + 2;
            right_thresh = BIAS - 2;
        end
        default: begin
            left_thresh  = BIAS + 1;
            right_thresh = BIAS - 1;
        end
    endcase
end

always_comb begin
    if(~nRst) begin
        move_left = 0;
        move_right = 0;
    end else if (biased_diff > left_thresh) begin
        {move_left, move_right} = 2'b10;
    end else if (biased_diff < right_thresh) begin
        {move_left, move_right} = 2'b01;
    end else begin
        {move_left, move_right} = 2'b00;
    end
end

endmodule
