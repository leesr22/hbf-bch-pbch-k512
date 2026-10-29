`default_nettype none
`timescale 1ns/1ps

// End-to-end decoder boundary: received codeword stream -> corrected message
// stream. The original codeword remains in the external page cache and is
// reread only after the BCH result is final.
module bch_decoder_message_stream_generic #(
    parameter integer K = 1024,
    parameter integer M = 11,
    parameter integer T = 10,
    parameter integer R = 110,
    parameter integer N = K + R,
    parameter integer WIDTH = 64,
    parameter [M:0] PRIMITIVE_POLYNOMIAL = 12'h805,
    parameter integer TAG_BITS = 8,
    parameter integer TWO_PHASE_BM = 0,
    parameter integer TWO_PHASE_SHIFT_WINDOW_BM = 0,
    parameter integer SHIFT_WINDOW_BM = 0,
    parameter integer CHIEN_RANGE_OPT = 0,
    parameter integer CHIEN_BALANCED_ROOT_COUNT = 0,
    parameter integer POSITION_OUTPUT = 0,
    parameter integer COMPACT_POSITION_REPLAY = 0,
    parameter integer BEAT_MASK_OUTPUT = 0,
    parameter integer BEAT_MASK_DATA_INDEPENDENT_READY = 0,
    parameter integer SERIAL_POSITION_OUTPUT = 0,
    parameter integer OUTPUT_CONTEXTS = 2,
    parameter integer POSITION_BITS = (N < 2) ? 1 : $clog2(N),
    parameter integer COUNT_BITS = $clog2(T+2)
) (
    input wire clk_i, input wire rst_ni,
    input wire [WIDTH-1:0] codeword_data_i,
    input wire codeword_first_i, input wire codeword_last_i,
    input wire [TAG_BITS-1:0] codeword_tag_i,
    input wire codeword_valid_i, output wire codeword_ready_o,

    output wire [TAG_BITS-1:0] reread_request_tag_o,
    output wire reread_request_valid_o, input wire reread_request_ready_i,
    input wire [TAG_BITS-1:0] reread_tag_i,
    input wire [WIDTH-1:0] reread_data_i,
    input wire reread_first_i, input wire reread_last_i,
    input wire reread_valid_i, output wire reread_ready_o,

    output wire [TAG_BITS-1:0] message_tag_o,
    output wire [WIDTH-1:0] message_data_o,
    output wire message_first_o, output wire message_last_o,
    output wire [1:0] message_status_o,
    output wire [COUNT_BITS-1:0] message_corrected_count_o,
    output wire message_valid_o, input wire message_ready_i,

    output wire [TAG_BITS-1:0] result_tag_o,
    output wire [COUNT_BITS-1:0] corrected_count_o,
    output wire [1:0] status_o,
    output wire result_valid_o, input wire result_ready_i
);
    wire [TAG_BITS-1:0] mask_tag, raw_result_tag;
    wire [POSITION_BITS-1:0] mask_base;
    wire [WIDTH-1:0] mask;
    wire mask_valid, mask_ready;
    wire [COUNT_BITS-1:0] raw_result_count;
    wire [1:0] raw_status;
    wire raw_result_valid, raw_result_ready;

    bch_decoder_streaming_mask_parallel_generic #(
        .K(K), .M(M), .T(T), .N(N), .INPUT_WIDTH(WIDTH),
        .CHIEN_WIDTH(WIDTH), .PRIMITIVE_POLYNOMIAL(PRIMITIVE_POLYNOMIAL),
        .TAG_BITS(TAG_BITS), .TWO_PHASE_BM(TWO_PHASE_BM),
        .TWO_PHASE_SHIFT_WINDOW_BM(TWO_PHASE_SHIFT_WINDOW_BM),
        .SHIFT_WINDOW_BM(SHIFT_WINDOW_BM),
        .CHIEN_RANGE_OPT(CHIEN_RANGE_OPT),
        .CHIEN_BALANCED_ROOT_COUNT(CHIEN_BALANCED_ROOT_COUNT)
    ) u_core (
        .clk_i(clk_i), .rst_ni(rst_ni), .chunk_i(codeword_data_i),
        .chunk_first_i(codeword_first_i), .chunk_last_i(codeword_last_i),
        .chunk_tag_i(codeword_tag_i), .chunk_valid_i(codeword_valid_i),
        .chunk_ready_o(codeword_ready_o), .correction_tag_o(mask_tag),
        .correction_base_o(mask_base), .correction_mask_o(mask),
        .correction_valid_o(mask_valid), .correction_ready_i(mask_ready),
        .result_tag_o(raw_result_tag), .corrected_count_o(raw_result_count),
        .status_o(raw_status), .result_valid_o(raw_result_valid),
        .result_ready_i(raw_result_ready)
    );

    generate if (SERIAL_POSITION_OUTPUT != 0) begin : g_serial_position_output
    bch_message_output_serial_positions_generic #(
        .K(K), .R(R), .N(N), .T(T), .WIDTH(WIDTH), .TAG_BITS(TAG_BITS),
        .CONTEXTS(OUTPUT_CONTEXTS)
    ) u_message_output (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .mask_tag_i(mask_tag), .mask_base_i(mask_base), .mask_i(mask),
        .mask_valid_i(mask_valid), .mask_ready_o(mask_ready),
        .decoder_result_tag_i(raw_result_tag),
        .decoder_corrected_count_i(raw_result_count),
        .decoder_status_i(raw_status), .decoder_result_valid_i(raw_result_valid),
        .decoder_result_ready_o(raw_result_ready),
        .reread_request_tag_o(reread_request_tag_o),
        .reread_request_valid_o(reread_request_valid_o),
        .reread_request_ready_i(reread_request_ready_i),
        .reread_tag_i(reread_tag_i), .reread_data_i(reread_data_i),
        .reread_first_i(reread_first_i), .reread_last_i(reread_last_i),
        .reread_valid_i(reread_valid_i), .reread_ready_o(reread_ready_o),
        .message_tag_o(message_tag_o), .message_data_o(message_data_o),
        .message_first_o(message_first_o), .message_last_o(message_last_o),
        .message_status_o(message_status_o),
        .message_corrected_count_o(message_corrected_count_o),
        .message_valid_o(message_valid_o), .message_ready_i(message_ready_i),
        .result_tag_o(result_tag_o), .corrected_count_o(corrected_count_o),
        .status_o(status_o), .result_valid_o(result_valid_o),
        .result_ready_i(result_ready_i)
    );
    end else if (BEAT_MASK_OUTPUT != 0) begin : g_beat_mask_output
    bch_message_output_beatmask_generic #(
        .K(K), .R(R), .N(N), .T(T), .WIDTH(WIDTH), .TAG_BITS(TAG_BITS),
        .CONTEXTS(OUTPUT_CONTEXTS),
        .DATA_INDEPENDENT_MASK_READY(BEAT_MASK_DATA_INDEPENDENT_READY)
    ) u_message_output (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .mask_tag_i(mask_tag), .mask_base_i(mask_base), .mask_i(mask),
        .mask_valid_i(mask_valid), .mask_ready_o(mask_ready),
        .decoder_result_tag_i(raw_result_tag),
        .decoder_corrected_count_i(raw_result_count),
        .decoder_status_i(raw_status), .decoder_result_valid_i(raw_result_valid),
        .decoder_result_ready_o(raw_result_ready),
        .reread_request_tag_o(reread_request_tag_o),
        .reread_request_valid_o(reread_request_valid_o),
        .reread_request_ready_i(reread_request_ready_i),
        .reread_tag_i(reread_tag_i), .reread_data_i(reread_data_i),
        .reread_first_i(reread_first_i), .reread_last_i(reread_last_i),
        .reread_valid_i(reread_valid_i), .reread_ready_o(reread_ready_o),
        .message_tag_o(message_tag_o), .message_data_o(message_data_o),
        .message_first_o(message_first_o), .message_last_o(message_last_o),
        .message_status_o(message_status_o),
        .message_corrected_count_o(message_corrected_count_o),
        .message_valid_o(message_valid_o), .message_ready_i(message_ready_i),
        .result_tag_o(result_tag_o), .corrected_count_o(corrected_count_o),
        .status_o(status_o), .result_valid_o(result_valid_o),
        .result_ready_i(result_ready_i)
    );
    end else if (POSITION_OUTPUT != 0) begin : g_position_output
    bch_message_output_positions_generic #(
        .K(K), .R(R), .N(N), .T(T), .WIDTH(WIDTH), .TAG_BITS(TAG_BITS),
        .CONTEXTS(OUTPUT_CONTEXTS),
        .COMPACT_REPLAY(COMPACT_POSITION_REPLAY)
    ) u_message_output (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .mask_tag_i(mask_tag), .mask_base_i(mask_base), .mask_i(mask),
        .mask_valid_i(mask_valid), .mask_ready_o(mask_ready),
        .decoder_result_tag_i(raw_result_tag),
        .decoder_corrected_count_i(raw_result_count),
        .decoder_status_i(raw_status), .decoder_result_valid_i(raw_result_valid),
        .decoder_result_ready_o(raw_result_ready),
        .reread_request_tag_o(reread_request_tag_o),
        .reread_request_valid_o(reread_request_valid_o),
        .reread_request_ready_i(reread_request_ready_i),
        .reread_tag_i(reread_tag_i), .reread_data_i(reread_data_i),
        .reread_first_i(reread_first_i), .reread_last_i(reread_last_i),
        .reread_valid_i(reread_valid_i), .reread_ready_o(reread_ready_o),
        .message_tag_o(message_tag_o), .message_data_o(message_data_o),
        .message_first_o(message_first_o), .message_last_o(message_last_o),
        .message_status_o(message_status_o),
        .message_corrected_count_o(message_corrected_count_o),
        .message_valid_o(message_valid_o), .message_ready_i(message_ready_i),
        .result_tag_o(result_tag_o), .corrected_count_o(corrected_count_o),
        .status_o(status_o), .result_valid_o(result_valid_o),
        .result_ready_i(result_ready_i)
    );
    end else begin : g_sparse_mask_output
    bch_message_output_sparse_generic #(
        .K(K), .R(R), .N(N), .T(T), .WIDTH(WIDTH), .TAG_BITS(TAG_BITS),
        .CONTEXTS(OUTPUT_CONTEXTS)
    ) u_message_output (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .mask_tag_i(mask_tag), .mask_base_i(mask_base), .mask_i(mask),
        .mask_valid_i(mask_valid), .mask_ready_o(mask_ready),
        .decoder_result_tag_i(raw_result_tag),
        .decoder_corrected_count_i(raw_result_count),
        .decoder_status_i(raw_status), .decoder_result_valid_i(raw_result_valid),
        .decoder_result_ready_o(raw_result_ready),
        .reread_request_tag_o(reread_request_tag_o),
        .reread_request_valid_o(reread_request_valid_o),
        .reread_request_ready_i(reread_request_ready_i),
        .reread_tag_i(reread_tag_i), .reread_data_i(reread_data_i),
        .reread_first_i(reread_first_i), .reread_last_i(reread_last_i),
        .reread_valid_i(reread_valid_i), .reread_ready_o(reread_ready_o),
        .message_tag_o(message_tag_o), .message_data_o(message_data_o),
        .message_first_o(message_first_o), .message_last_o(message_last_o),
        .message_status_o(message_status_o),
        .message_corrected_count_o(message_corrected_count_o),
        .message_valid_o(message_valid_o), .message_ready_i(message_ready_i),
        .result_tag_o(result_tag_o), .corrected_count_o(corrected_count_o),
        .status_o(status_o), .result_valid_o(result_valid_o),
        .result_ready_i(result_ready_i)
    );
    end endgenerate
endmodule

`default_nettype wire
