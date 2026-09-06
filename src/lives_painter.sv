`timescale 1ns / 1ps


module lives_painter #(
    //                          BBGGRR
    parameter LIVES_COLOR = 6'b000011,
    parameter LIVES_WIDTH = 16,
    parameter LIVES_HEIGHT = 9'd14,
    parameter LIVES_Y =  9'd440,
    parameter SPACING = 16
) (
    input logic clk,
    input logic nRst,
    output logic in_lives,
    output logic [5:0] color,
    input logic hactive,
    input logic[9:0] hpos,
    input logic[8:0] vpos,
    input logic[1:0] lives
    );
 
    
    function automatic logic [15:0] heart_row(input logic [3:0] r);
        case (r)
            4'd0:  heart_row = 16'b0001110000111000;
            4'd1:  heart_row = 16'b0011111001111100;
            4'd2:  heart_row = 16'b0111111111111110;
            4'd3:  heart_row = 16'b1111111111111111;
            4'd4:  heart_row = 16'b1111111111111111;
            4'd5:  heart_row = 16'b1111111111111111;
            4'd6:  heart_row = 16'b1111111111111111;
            4'd7:  heart_row = 16'b0111111111111110;
            4'd8:  heart_row = 16'b0011111111111100;
            4'd9:  heart_row = 16'b0001111111111000;
            4'd10: heart_row = 16'b0000111111110000;
            4'd11: heart_row = 16'b0000011111100000;
            4'd12: heart_row = 16'b0000001111000000;
            4'd13: heart_row = 16'b0000000110000000;
            default: heart_row = 16'b0;
        endcase
    endfunction
    
    logic [4:0] lives_x;
    logic [1:0] lives_cntr;
    logic in_lives_row;
    logic in_lives_y;
    logic at_x_end;
    logic at_lives_end;
    logic at_lives_y_start;
    logic at_lives_y_end;
    logic [3:0] row_idx;
    logic [15:0] row_bits;

    assign at_x_end = (lives_x == 0);
    assign at_lives_end = (lives_cntr == 0);
    assign at_lives_y_start = (vpos == LIVES_Y);
    assign at_lives_y_end = (vpos == LIVES_Y + LIVES_HEIGHT);
    assign row_idx = in_lives_y ? (vpos - LIVES_Y) : 4'd0;
    assign row_bits = heart_row(row_idx);

    assign in_lives = in_lives_row && in_lives_y && row_bits[lives_x[3:0]];
    assign color = LIVES_COLOR;

    // horizontal counters
    always_ff @(posedge clk or negedge nRst)
    begin
        if(!nRst) begin
            lives_x <= SPACING - 1;
            in_lives_row <= 0;
            lives_cntr <= 0;
        end else begin
            if(!hactive) begin
                lives_x <= SPACING - 1;
                in_lives_row <= 0;
                lives_cntr <= lives;
            end else if(at_x_end) begin
                lives_x <= in_lives_row ? SPACING - 1 : LIVES_WIDTH - 1;
                in_lives_row <= !in_lives_row && !at_lives_end;
            end else begin
                lives_x <= lives_x - 1'b1;
            end
            if(at_x_end && in_lives_row && !at_lives_end) begin
                lives_cntr <= lives_cntr - 1'b1;
            end
        end
    end

    always_ff @(posedge clk or negedge nRst)
    begin
        if(!nRst) begin
            in_lives_y <= 0;
        end else begin
            if(at_lives_y_start) begin
                in_lives_y <= 1;
            end else if(at_lives_y_end) begin
                in_lives_y <= 0;
            end
        end
    end

endmodule
