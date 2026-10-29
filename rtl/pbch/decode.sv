`timescale 1ns/1ps
`default_nettype none

// PBCH(572,512,ell=20,t=4): parent BCH correction plus selector recovery.
module pbch_decode (
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
    wire core_ready;
    wire [7:0] mask_tag, raw_tag;
    wire [9:0] mask_base;
    wire [63:0] correction_mask;
    wire mask_valid, mask_ready;
    wire [2:0] raw_count;
    wire [1:0] raw_status;
    wire raw_valid, raw_ready;

    wire select_start_ready, select_raw_ready;
    wire select_mask_ready, select_result_ready;
    wire [19:0] selector;
    wire selector_valid;

    wire replay_mask_ready, replay_result_ready;
    wire [7:0] replay_message_tag, replay_result_tag;
    wire [63:0] replay_message;
    wire replay_message_first, replay_message_last;
    wire [1:0] replay_message_status, replay_status;
    wire [2:0] replay_message_count, replay_count;
    wire replay_message_valid, replay_message_ready;
    wire replay_result_valid;

    wire admission = (!first || select_start_ready) &&
                     (!last || select_raw_ready);
    wire input_valid = valid && admission;
    wire input_accept = input_valid && core_ready;
    assign ready = core_ready && admission;

    bch_decoder_streaming_mask_parallel_generic #(
        .K(532), .M(10), .T(4), .N(572),
        .INPUT_WIDTH(64), .CHIEN_WIDTH(64),
        .PRIMITIVE_POLYNOMIAL(11'h409), .TAG_BITS(8),
        .SHIFT_WINDOW_BM(1), .CHIEN_RANGE_OPT(1),
        .CHIEN_BALANCED_ROOT_COUNT(1)
    ) correction (
        .clk_i(clk), .rst_ni(reset_n), .chunk_i(codeword),
        .chunk_first_i(first), .chunk_last_i(last), .chunk_tag_i(tag),
        .chunk_valid_i(input_valid), .chunk_ready_o(core_ready),
        .correction_tag_o(mask_tag), .correction_base_o(mask_base),
        .correction_mask_o(correction_mask), .correction_valid_o(mask_valid),
        .correction_ready_i(mask_ready), .result_tag_o(raw_tag),
        .corrected_count_o(raw_count), .status_o(raw_status),
        .result_valid_o(raw_valid), .result_ready_i(raw_ready)
    );

    assign mask_ready = replay_mask_ready && select_mask_ready;
    assign raw_ready = replay_result_ready && select_result_ready;

    bch_message_output_beatmask_generic #(
        .K(512), .R(60), .N(572), .T(4), .WIDTH(64),
        .TAG_BITS(8), .CONTEXTS(2), .DATA_INDEPENDENT_MASK_READY(1)
    ) replay (
        .clk_i(clk), .rst_ni(reset_n), .mask_tag_i(mask_tag),
        .mask_base_i(mask_base), .mask_i(correction_mask),
        .mask_valid_i(mask_valid && select_mask_ready),
        .mask_ready_o(replay_mask_ready), .decoder_result_tag_i(raw_tag),
        .decoder_corrected_count_i(raw_count), .decoder_status_i(raw_status),
        .decoder_result_valid_i(raw_valid && select_result_ready),
        .decoder_result_ready_o(replay_result_ready),
        .reread_request_tag_o(read_tag), .reread_request_valid_o(read_request),
        .reread_request_ready_i(read_request_ready),
        .reread_tag_i(read_data_tag), .reread_data_i(read_data),
        .reread_first_i(read_first), .reread_last_i(read_last),
        .reread_valid_i(read_valid), .reread_ready_o(read_ready),
        .message_tag_o(replay_message_tag), .message_data_o(replay_message),
        .message_first_o(replay_message_first),
        .message_last_o(replay_message_last),
        .message_status_o(replay_message_status),
        .message_corrected_count_o(replay_message_count),
        .message_valid_o(replay_message_valid),
        .message_ready_i(replay_message_ready),
        .result_tag_o(replay_result_tag), .corrected_count_o(replay_count),
        .status_o(replay_status), .result_valid_o(replay_result_valid),
        .result_ready_i(result_ready)
    );

    select_fifo selectors (
        .clk(clk), .reset_n(reset_n), .start_tag(tag),
        .start_valid(input_accept && first), .start_ready(select_start_ready),
        .raw_selector(codeword[63:44]), .raw_valid(input_accept && last),
        .raw_ready(select_raw_ready), .correction_base(mask_base),
        .correction_mask(correction_mask),
        .correction_valid(mask_valid && replay_mask_ready),
        .correction_ready(select_mask_ready), .result_tag(raw_tag),
        .result_valid(raw_valid && replay_result_ready),
        .result_ready(select_result_ready), .lookup_tag(replay_message_tag),
        .selector(selector), .selector_valid(selector_valid),
        .retire(replay_result_valid && result_ready)
    );

    recover output_stage (
        .clk(clk), .reset_n(reset_n), .in_tag(replay_message_tag),
        .in_data(replay_message), .in_first(replay_message_first),
        .in_last(replay_message_last), .in_status(replay_message_status),
        .in_count(replay_message_count), .in_valid(replay_message_valid),
        .in_ready(replay_message_ready), .selector(selector),
        .selector_valid(selector_valid), .out_tag(message_tag),
        .out_data(message), .out_first(message_first), .out_last(message_last),
        .out_status(message_status), .out_count(message_count),
        .out_valid(message_valid), .out_ready(message_ready)
    );

    assign result_tag = replay_result_tag;
    assign corrected_count = replay_count;
    assign status = replay_status;
    assign result_valid = replay_result_valid;
endmodule

`default_nettype wire
