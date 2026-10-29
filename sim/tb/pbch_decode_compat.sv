`timescale 1ns/1ps
`default_nettype none

// Port-name adapter used only to reuse the established regression testbench.
module paper_pbch_decoder_k512_e20_w64_decoupled_pipe2 (
    input wire clk_i, input wire rst_ni,
    input wire [63:0] codeword_data_i,
    input wire codeword_first_i, input wire codeword_last_i,
    input wire [7:0] codeword_tag_i, input wire codeword_valid_i,
    output wire codeword_ready_o,
    output wire [7:0] reread_request_tag_o,
    output wire reread_request_valid_o, input wire reread_request_ready_i,
    input wire [7:0] reread_tag_i, input wire [63:0] reread_data_i,
    input wire reread_first_i, input wire reread_last_i,
    input wire reread_valid_i, output wire reread_ready_o,
    output wire [7:0] message_tag_o, output wire [63:0] message_data_o,
    output wire message_first_o, output wire message_last_o,
    output wire [1:0] message_status_o,
    output wire [2:0] message_corrected_count_o,
    output wire message_valid_o, input wire message_ready_i,
    output wire [7:0] result_tag_o, output wire [2:0] corrected_count_o,
    output wire [1:0] status_o, output wire result_valid_o,
    input wire result_ready_i
);
    pbch_decode dut (
        .clk(clk_i), .reset_n(rst_ni), .codeword(codeword_data_i),
        .first(codeword_first_i), .last(codeword_last_i), .tag(codeword_tag_i),
        .valid(codeword_valid_i), .ready(codeword_ready_o),
        .read_tag(reread_request_tag_o), .read_request(reread_request_valid_o),
        .read_request_ready(reread_request_ready_i), .read_data_tag(reread_tag_i),
        .read_data(reread_data_i), .read_first(reread_first_i),
        .read_last(reread_last_i), .read_valid(reread_valid_i),
        .read_ready(reread_ready_o), .message_tag(message_tag_o),
        .message(message_data_o), .message_first(message_first_o),
        .message_last(message_last_o), .message_status(message_status_o),
        .message_count(message_corrected_count_o), .message_valid(message_valid_o),
        .message_ready(message_ready_i), .result_tag(result_tag_o),
        .corrected_count(corrected_count_o), .status(status_o),
        .result_valid(result_valid_o), .result_ready(result_ready_i)
    );
endmodule

`default_nettype wire
