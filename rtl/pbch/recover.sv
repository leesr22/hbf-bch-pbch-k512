`timescale 1ns/1ps
`default_nettype none

// Two elastic stages: capture selector/tag, then apply the fixed mask XOR.
module recover (
    input wire clk, input wire reset_n,
    input wire [7:0] in_tag, input wire [63:0] in_data,
    input wire in_first, input wire in_last,
    input wire [1:0] in_status, input wire [2:0] in_count,
    input wire in_valid, output wire in_ready,
    input wire [19:0] selector, input wire selector_valid,
    output wire [7:0] out_tag, output wire [63:0] out_data,
    output wire out_first, output wire out_last,
    output wire [1:0] out_status, output wire [2:0] out_count,
    output wire out_valid, input wire out_ready
);
    `undef HBF_PAPER_PBCH_K512_E20_CONSTANTS_SVH
    `include "rtl/generated/constants.svh"

    reg s1_valid, s2_valid;
    reg [7:0] s1_tag, s2_tag;
    reg [63:0] s1_data, s2_data;
    reg [19:0] s1_selector;
    reg [2:0] beat, s1_beat, s1_count, s2_count;
    reg s1_first, s1_last, s2_first, s2_last;
    reg [1:0] s1_status, s2_status;
    wire s2_ready = !s2_valid || out_ready;
    wire s1_ready = !s1_valid || s2_ready;

    assign in_ready = s1_ready && selector_valid;
    assign out_tag = s2_tag;
    assign out_data = s2_data;
    assign out_first = s2_first;
    assign out_last = s2_last;
    assign out_status = s2_status;
    assign out_count = s2_count;
    assign out_valid = s2_valid;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            s1_valid <= 0; s2_valid <= 0; beat <= 0;
            s1_tag <= 0; s2_tag <= 0; s1_data <= 0; s2_data <= 0;
            s1_selector <= 0; s1_beat <= 0; s1_count <= 0; s2_count <= 0;
            s1_first <= 0; s1_last <= 0; s2_first <= 0; s2_last <= 0;
            s1_status <= 0; s2_status <= 0;
        end else begin
            if (s2_ready) begin
                s2_valid <= s1_valid;
                if (s1_valid) begin
                    s2_tag <= s1_tag;
                    s2_data <= s1_data ^
                        pbch_payload_mask_beat({1'b0,s1_beat},s1_selector);
                    s2_first <= s1_first; s2_last <= s1_last;
                    s2_status <= s1_status; s2_count <= s1_count;
                end
            end
            if (s1_ready) begin
                s1_valid <= in_valid && selector_valid;
                if (in_valid && selector_valid) begin
                    s1_tag <= in_tag; s1_data <= in_data;
                    s1_selector <= selector; s1_beat <= beat;
                    s1_first <= in_first; s1_last <= in_last;
                    s1_status <= in_status; s1_count <= in_count;
                end
            end
            if (in_valid && in_ready)
                beat <= in_last ? 0 : beat + 1'b1;
        end
    end
endmodule

`default_nettype wire
