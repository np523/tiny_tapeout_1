

module lives_painter #(
    //                          BBGGRR
    parameter LIVES_COLOR = 6'b111111,
    parameter LIVES_WIDTH = 24,
    parameter LIVES_HEIGHT = 9'd4,
    parameter LIVES_Y =  9'd474,
    parameter SPACING = 16
) (
    input clk,
    input nRst,
    output in_lives,
    output [5:0] color,
    input hactive,
    input [9:0] hpos,
    input [8:0] vpos,
    input [1:0] lives
    );
    
    reg [4:0] lives_x;
    reg [1:0] lives_cntr;
    reg in_lives_row;
    reg in_lives_y;
    wire at_x_end = lives_x == 0;
    wire at_lives_end = lives_cntr == 0;
    wire at_lives_y_start = vpos == LIVES_Y;
    wire at_lives_y_end = vpos == LIVES_Y + LIVES_HEIGHT - 1;

    assign in_lives = in_lives_row && in_lives_y;
    assign color = LIVES_COLOR;

    // horizontal counters
    always @(posedge clk or negedge nRst)
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

    always @(posedge clk or negedge nRst)
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
