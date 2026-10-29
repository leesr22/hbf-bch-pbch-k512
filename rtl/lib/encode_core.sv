`default_nettype none
`timescale 1ns/1ps

// Area-optimized systematic streaming encoder.
//
// The baseline keeps separate R-bit remainder and parity-shift registers even
// though their lifetimes do not overlap.  This variant reuses remainder_q for
// parity serialization.  The external protocol, end-to-end II, and generated
// codeword are intentionally identical to bch_encoder_codeword_stream_generic.
module bch_encoder_codeword_stream_single_state_generic #(
    parameter integer K = 1024,
    parameter integer R = 110,
    parameter integer WIDTH = 64,
    parameter integer TAG_BITS = 8,
    parameter [R:0] GENERATOR = 111'h504d1d2ebb0f1d7efcbf489ed547,
    parameter integer MESSAGE_BEATS = K / WIDTH,
    parameter integer PARITY_BEATS = (R + WIDTH - 1) / WIDTH,
    parameter integer MESSAGE_COUNT_BITS = (MESSAGE_BEATS < 2) ? 1 : $clog2(MESSAGE_BEATS),
    parameter integer PARITY_COUNT_BITS = (PARITY_BEATS < 2) ? 1 : $clog2(PARITY_BEATS),
    parameter integer VALID_BITS_WIDTH = $clog2(WIDTH+1)
) (
    input wire clk_i, input wire rst_ni,
    input wire [WIDTH-1:0] message_data_i,
    input wire message_first_i, input wire message_last_i,
    input wire [TAG_BITS-1:0] message_tag_i,
    input wire message_valid_i, output wire message_ready_o,
    output wire [WIDTH-1:0] codeword_data_o,
    output wire [VALID_BITS_WIDTH-1:0] codeword_valid_bits_o,
    output wire codeword_first_o, output wire codeword_last_o,
    output wire [TAG_BITS-1:0] codeword_tag_o,
    output wire codeword_valid_o, input wire codeword_ready_i
);
    localparam integer LAST_PARITY_BITS = (R % WIDTH == 0) ? WIDTH : R % WIDTH;
    localparam S_MESSAGE = 1'b0, S_PARITY = 1'b1;
    reg state_q;
    reg [R-1:0] remainder_q;
    reg [MESSAGE_COUNT_BITS-1:0] message_count_q;
    reg [PARITY_COUNT_BITS-1:0] parity_count_q;
    reg [TAG_BITS-1:0] active_tag_q;
    reg [R-1:0] remainder_work;
    reg feedback;
    wire [WIDTH-1:0] parity_data;
    integer lane;

    generate
        if (R >= WIDTH) begin : g_full_width_parity
            assign parity_data = remainder_q[R-1 -: WIDTH];
        end else begin : g_short_parity
            assign parity_data = {{(WIDTH-R){1'b0}}, remainder_q} << (WIDTH-R);
        end
    endgenerate

    assign message_ready_o = (state_q == S_MESSAGE) && codeword_ready_i;
    assign codeword_valid_o = (state_q == S_MESSAGE) ? message_valid_i : 1'b1;
    assign codeword_data_o = (state_q == S_MESSAGE) ? message_data_i : parity_data;
    assign codeword_first_o = (state_q == S_MESSAGE) && (message_count_q == 0);
    assign codeword_last_o = (state_q == S_PARITY) && (parity_count_q == PARITY_BEATS-1);
    assign codeword_tag_o = (state_q == S_MESSAGE) ? message_tag_i : active_tag_q;
    assign codeword_valid_bits_o = codeword_last_o ? LAST_PARITY_BITS : WIDTH;

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q <= S_MESSAGE;
            remainder_q <= 0;
            message_count_q <= 0;
            parity_count_q <= 0;
            active_tag_q <= 0;
        end else begin
            if (state_q == S_MESSAGE && message_valid_i && message_ready_o) begin
                remainder_work = (message_count_q == 0) ? 0 : remainder_q;
                for (lane = 0; lane < WIDTH; lane = lane + 1) begin
                    feedback = message_data_i[WIDTH-1-lane] ^ remainder_work[R-1];
                    remainder_work = remainder_work << 1;
                    if (feedback) remainder_work = remainder_work ^ GENERATOR[R-1:0];
                end
                remainder_q <= remainder_work;
                if (message_count_q == 0) active_tag_q <= message_tag_i;
                if (message_count_q == MESSAGE_BEATS-1) begin
                    message_count_q <= 0;
                    parity_count_q <= 0;
                    state_q <= S_PARITY;
                end else begin
                    message_count_q <= message_count_q + 1'b1;
                end
            end else if (state_q == S_PARITY && codeword_ready_i) begin
                if (R >= WIDTH) remainder_q <= remainder_q << WIDTH;
                if (parity_count_q == PARITY_BEATS-1) begin
                    parity_count_q <= 0;
                    state_q <= S_MESSAGE;
                end else begin
                    parity_count_q <= parity_count_q + 1'b1;
                end
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (K % WIDTH != 0) $fatal(1, "K must be divisible by WIDTH");
        if (R < 1) $fatal(1, "R must be positive");
    end
    always @(posedge clk_i) begin
        if (rst_ni && state_q == S_MESSAGE && message_valid_i && message_ready_o) begin
            if ((message_count_q == 0) != message_first_i)
                $fatal(1, "message first marker mismatch");
            if ((message_count_q == MESSAGE_BEATS-1) != message_last_i)
                $fatal(1, "message last marker mismatch");
        end
    end
`endif
endmodule

`default_nettype wire
