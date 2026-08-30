`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/07/2023 09:48:35 PM
// Design Name: 
// Module Name: vga_timing
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


module vga_timing(
    input logic clk,
    input logic nRst,
    output logic hsync,
    output logic hactive,
    output logic [9:0] hpos,
    output logic vsync,
    output logic vactive,
    output logic [8:0] vpos,
    output logic active,
    output logic line_pulse,
    output logic frame_pulse
    );
    
    
    logic [9:0] hor_counter;
    logic hor_at_end;
    assign hor_at_end = hor_counter == 10'd799;
    always_ff @(posedge clk or negedge nRst)
    begin
        if(!nRst) begin
            hor_counter <= 10'b0;
        end else begin
            if(hor_at_end) begin
                hor_counter <= 10'b0;            
            end else begin
                hor_counter <= hor_counter + 1'b1;
            end
        end
    end
    
    logic [9:0] vert_counter;
    logic vert_at_end;
    assign vert_at_end = vert_counter == 10'd524;
    always_ff @(posedge clk or negedge nRst)
    begin
        if(!nRst) begin
            vert_counter <= 10'b0;
        end else begin
            if(hor_at_end) begin
                if(vert_at_end) begin
                    vert_counter <= 10'b0;
                end else begin
                    vert_counter <= vert_counter + 1'b1;
                end            
            end
        end
    end

    logic hsync_start;
    assign hsync_start = hor_counter == 10'd656;
    logic hsync_end;
    assign hsync_end = hor_counter == 10'd752;
    always_ff @(posedge clk or negedge nRst)
    begin
        if(!nRst) begin
            hsync <= 1'b1;
        end else begin
            if(hsync_start) begin
                hsync <= 1'b0;
            end else if(hsync_end) begin
                hsync <= 1'b1;
            end
        end
    end

    logic hactive_end;
    assign hactive_end = hor_counter == 10'd639;
    always_ff @(posedge clk or negedge nRst)
    begin
        if(!nRst) begin
            hactive <= 1'b1;
        end else begin
            if(hor_at_end) begin
                hactive <= 1'b1;
            end else if(hactive_end) begin
                hactive <= 1'b0;
            end
        end
    end

    logic vsync_start;
    assign vsync_start = vert_counter == 10'd490;
    logic vsync_end;
    assign vsync_end = vert_counter == 10'd492;
    always_ff @(posedge clk or negedge nRst)
    begin
        if(!nRst) begin
            vsync <= 1'b1;
        end else begin
            if(vsync_start) begin
                vsync <= 1'b0;
            end else if(vsync_end) begin
                vsync <= 1'b1;
            end
        end
    end

    logic vactive_end;
    assign vactive_end = vert_counter == 10'd479;
    always_ff @(posedge clk or negedge nRst)
    begin
        if(!nRst) begin
            vactive <= 1'b1;
        end else begin
            if(vert_at_end && hor_at_end) begin
                vactive <= 1'b1;
            end else if(vactive_end && hor_at_end) begin
                vactive <= 1'b0;
            end
        end
    end


    
    assign line_pulse = hor_at_end;
    assign frame_pulse = vert_at_end && line_pulse; // Make sure that the pulse is only one clock cycle wide
    assign hpos = hor_counter;
    assign vpos = vert_counter[8:0];
    assign active = hactive && vactive;
    
endmodule
