`timescale 1ns/1ps
`default_nettype none

// BCH(572,512,t=6): syndrome -> BM -> Chien -> source reread.
module bch_decode (
    input wire clk, input wire reset_n,
    input wire [63:0] codeword, input wire first, input wire last,
    input wire [7:0] tag, input wire valid, output wire ready,
    output wire [7:0] read_tag, output wire read_request,
    input wire read_request_ready,
    input wire [7:0] read_data_tag, input wire [63:0] read_data,
    input wire read_first, input wire read_last, input wire read_valid,
    output wire read_ready,
    output wire [7:0] message_tag, output wire [63:0] message,
    output wire message_first, output wire message_last,
    output wire [1:0] message_status, output wire [2:0] message_count,
    output wire message_valid, input wire message_ready,
    output wire [7:0] result_tag, output wire [2:0] corrected_count,
    output wire [1:0] status, output wire result_valid,
    input wire result_ready
);
    bch_decoder_message_stream_generic #(
        .K(512), .M(10), .T(6), .R(60), .N(572), .WIDTH(64),
        .PRIMITIVE_POLYNOMIAL(11'h409), .SHIFT_WINDOW_BM(1),
        .BEAT_MASK_OUTPUT(1), .CHIEN_RANGE_OPT(1),
        .CHIEN_BALANCED_ROOT_COUNT(1)
    ) core (
        .clk_i(clk), .rst_ni(reset_n), .codeword_data_i(codeword),
        .codeword_first_i(first), .codeword_last_i(last),
        .codeword_tag_i(tag), .codeword_valid_i(valid),
        .codeword_ready_o(ready), .reread_request_tag_o(read_tag),
        .reread_request_valid_o(read_request),
        .reread_request_ready_i(read_request_ready),
        .reread_tag_i(read_data_tag), .reread_data_i(read_data),
        .reread_first_i(read_first), .reread_last_i(read_last),
        .reread_valid_i(read_valid), .reread_ready_o(read_ready),
        .message_tag_o(message_tag), .message_data_o(message),
        .message_first_o(message_first), .message_last_o(message_last),
        .message_status_o(message_status),
        .message_corrected_count_o(message_count),
        .message_valid_o(message_valid), .message_ready_i(message_ready),
        .result_tag_o(result_tag), .corrected_count_o(corrected_count),
        .status_o(status), .result_valid_o(result_valid),
        .result_ready_i(result_ready)
    );
endmodule

`default_nettype wire
