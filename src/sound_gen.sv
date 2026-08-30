

module sound_gen #(
    parameter SOUND_DIVIDER = 5,
    parameter HIGH_LENGTH = 3,
    parameter LOW_LENGTH = 6
) (
    input logic  clk,
    input logic  nRst,
    output logic sound,
    input logic  line_pulse,
    input logic  frame_pulse,
    input logic  low_beep,
    input logic  high_beep
);


logic [SOUND_DIVIDER:0] sound_counter;
logic high_beep_wave;
assign high_beep_wave = sound_counter[SOUND_DIVIDER - 1];
logic low_beep_wave;
assign low_beep_wave = sound_counter[SOUND_DIVIDER];

logic high_en;
logic low_en;
assign sound = ((high_en & high_beep_wave) ^ (low_beep_wave & low_en)) && (high_en || low_en);

always_ff @(posedge line_pulse or negedge nRst)
begin
    if(!nRst) begin
        sound_counter <= 0;
    end else begin
        sound_counter <= sound_counter + 1'b1;
    end
end

logic [2:0] high_counter;
logic high_at_end;
assign high_at_end = high_counter == HIGH_LENGTH;
always_ff @(posedge clk or negedge nRst)
begin
    if(!nRst) begin
        high_counter <= 0;
        high_en <= 0;
    end else begin
        if(frame_pulse) begin
            if(high_at_end) begin
                high_counter <= 0;
                high_en <= high_beep;
            end else if(high_en) begin
                high_counter <= high_counter + 1'b1;
            end
        end else if(high_beep) begin
            high_en <= 1'b1;
            high_counter <= 0;
        end
    end
end

logic [2:0] low_counter;
logic low_at_end;
assign low_at_end = low_counter == LOW_LENGTH;
always_ff @(posedge clk or negedge nRst)
begin
    if(!nRst) begin
        low_counter <= 0;
        low_en <= 0;
    end else begin
        if(frame_pulse) begin
            if(low_at_end) begin
                low_counter <= 0;
                low_en <= low_beep;
            end else if(low_en) begin
                low_counter <= low_counter + 1'b1;
            end
        end else if(low_beep) begin
            low_en <= 1'b1;
            low_counter <= 0;
        end
    end
end

endmodule
