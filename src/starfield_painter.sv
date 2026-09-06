module starfield_painter #(
    parameter NUM_STARS = 16,
    parameter MAX_HPOS = 10'd639,
    parameter [5:0] STAR_COLOR = 6'b001111
)(
    input logic clk,
    input logic nRst,
    input logic frame_pulse,
    input logic [9:0] hpos,
    input logic [8:0] vpos,
    output logic [5:0] color
);

    function automatic logic [2:0] speed_val(input logic [1:0] tier);
        case (tier)
            2'b00: speed_val = 3'd1;
            2'b01: speed_val = 3'd2;
            default: speed_val = 3'd4;
        endcase
    endfunction

    logic [8:0] star_row [0:NUM_STARS-1];
    logic [1:0] star_speed_sel [0:NUM_STARS-1];
    logic [9:0] star_x [0:NUM_STARS-1];

    logic [4:0] seed_idx;
    logic seeding_done;
    logic [15:0] lfsr;
    assign seeding_done = (seed_idx == NUM_STARS);

    always_ff @(posedge clk or negedge nRst) begin
        if (!nRst) begin
            lfsr <= 16'hACE1;
            seed_idx <= 5'd0;
        end else if (!seeding_done) begin
            star_row[seed_idx] <= lfsr[8:0];
            star_speed_sel[seed_idx] <= lfsr[10:9];
            lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
            seed_idx <= seed_idx + 1'b1;
        end
    end

    integer i;
    always_ff @(posedge clk or negedge nRst) begin
        if (!nRst) begin
            for (i = 0; i < NUM_STARS; i = i + 1) begin
                star_x[i] <= i * (MAX_HPOS / NUM_STARS);
            end
        end else if (frame_pulse) begin
            for (i = 0; i < NUM_STARS; i = i + 1) begin
                if (star_x[i] >= speed_val(star_speed_sel[i])) begin
                    star_x[i] <= star_x[i] - speed_val(star_speed_sel[i]);
                end else begin
                    star_x[i] <= star_x[i] + (MAX_HPOS + 10'd1) - speed_val(star_speed_sel[i]);
                end
            end
        end
    end

    logic [NUM_STARS-1:0] star_active;
    genvar g;
    generate
        for (g = 0; g < NUM_STARS; g = g + 1) begin : star_cmp
            assign star_active[g] = (vpos == star_row[g]) && (hpos == star_x[g]);
        end
    endgenerate

    assign color = (|star_active) ? STAR_COLOR : 6'b000000;

endmodule
