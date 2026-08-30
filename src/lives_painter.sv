

module lives_painter #(
    //                          BBGGRR
    parameter LIVES_COLOR = 6'b111111,
    parameter LIVES_WIDTH = 24,
    parameter LIVES_HEIGHT = 9'd4,
    parameter LIVES_Y =  9'd474,
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
    
    logic [4:0] lives_x;
    logic [1:0] lives_cntr;
    logic in_lives_row;
    logic in_lives_y;
    logic at_x_end;
    logic at_lives_end;
    logic at_lives_y_start;
    logic at_lives_y_end;
    
    assign at_x_end = (lives_x == 0);
    assign at_lives_end = (lives_cntr == 0);
    assign at_lives_y_start = (vpos == LIVES_Y);
    assign at_lives_y_end = (vpos == LIVES_Y + LIVES_HEIGHT - 1);

    assign in_lives = in_lives_row && in_lives_y;
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
