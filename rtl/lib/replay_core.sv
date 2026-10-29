`default_nettype none
`timescale 1ns/1ps

// Transactional message replay with beat-aligned correction metadata.
//
// A Chien WIDTH-bit window is aligned to absolute BCH positions.  Because the
// systematic message is replayed in the opposite direction and R is not
// necessarily WIDTH-aligned, one Chien window can overlap at most two message
// beats.  Convert that window once at collection time and retain only the
// resulting (message beat, message mask) pairs.  Replay then needs T beat
// comparisons and WIDTH-bit XORs instead of WIDTH*T subtract/range/variable
// bit-select networks.  At most T nonzero pairs are possible for <=T errors.
module bch_message_output_beatmask_generic #(
    parameter integer K = 1024,
    parameter integer R = 110,
    parameter integer N = K + R,
    parameter integer T = 10,
    parameter integer WIDTH = 64,
    parameter integer TAG_BITS = 8,
    parameter integer CONTEXTS = 2,
    parameter integer DATA_INDEPENDENT_MASK_READY = 0,
    parameter integer POSITION_BITS = (N < 2) ? 1 : $clog2(N),
    parameter integer COUNT_BITS = $clog2(T+2),
    parameter integer ENTRY_BITS = (T < 2) ? 1 : $clog2(T+1),
    parameter integer CONTEXT_BITS = (CONTEXTS < 2) ? 1 : $clog2(CONTEXTS),
    parameter integer QUEUE_BITS = $clog2(CONTEXTS+1),
    parameter integer BEATS = K / WIDTH,
    parameter integer LANE_BITS = (WIDTH < 2) ? 1 : $clog2(WIDTH),
    parameter integer BEAT_BITS = (BEATS < 2) ? 1 : $clog2(BEATS),
    parameter integer CHIEN_REMAINDER = (N-1) % WIDTH,
    parameter integer PRIMARY_SHIFT = WIDTH-1-CHIEN_REMAINDER
) (
    input wire clk_i, input wire rst_ni,
    input wire [TAG_BITS-1:0] mask_tag_i,
    input wire [POSITION_BITS-1:0] mask_base_i,
    input wire [WIDTH-1:0] mask_i,
    input wire mask_valid_i, output wire mask_ready_o,
    input wire [TAG_BITS-1:0] decoder_result_tag_i,
    input wire [COUNT_BITS-1:0] decoder_corrected_count_i,
    input wire [1:0] decoder_status_i,
    input wire decoder_result_valid_i, output wire decoder_result_ready_o,
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
    localparam [2:0] S_IDLE = 0, S_REQUEST = 1, S_STREAM = 2, S_RESULT = 3;

    reg context_valid_q [0:CONTEXTS-1];
    reg context_closed_q [0:CONTEXTS-1];
    reg [TAG_BITS-1:0] context_tag_q [0:CONTEXTS-1];
    reg [ENTRY_BITS-1:0] entry_count_q [0:CONTEXTS-1];
    reg [COUNT_BITS-1:0] result_count_q [0:CONTEXTS-1];
    reg [1:0] result_status_q [0:CONTEXTS-1];
    reg [BEAT_BITS-1:0] beat_q [0:CONTEXTS*T-1];
    reg [WIDTH-1:0] mask_q [0:CONTEXTS*T-1];
    reg [CONTEXT_BITS-1:0] result_fifo_q [0:CONTEXTS-1];
    reg [CONTEXT_BITS-1:0] fifo_write_q, fifo_read_q;
    reg [QUEUE_BITS-1:0] fifo_count_q;
    reg [BEAT_BITS-1:0] read_beat_q;
    reg [2:0] state_q;

    reg mask_match_found, free_found, result_match_found;
    reg [CONTEXT_BITS-1:0] mask_match_index, free_index, result_match_index;
    integer scan;
    always @(*) begin
        mask_match_found = 0; mask_match_index = 0;
        free_found = 0; free_index = 0;
        result_match_found = 0; result_match_index = 0;
        for (scan = 0; scan < CONTEXTS; scan = scan + 1) begin
            if (context_valid_q[scan] && !context_closed_q[scan] &&
                context_tag_q[scan] == mask_tag_i && !mask_match_found) begin
                mask_match_found = 1; mask_match_index = scan[CONTEXT_BITS-1:0];
            end
            if (!context_valid_q[scan] && !free_found) begin
                free_found = 1; free_index = scan[CONTEXT_BITS-1:0];
            end
            if (context_valid_q[scan] && !context_closed_q[scan] &&
                context_tag_q[scan] == decoder_result_tag_i &&
                !result_match_found) begin
                result_match_found = 1; result_match_index = scan[CONTEXT_BITS-1:0];
            end
        end
    end

    // base is WIDTH-aligned, so (N-1-base) always has the same remainder.
    // The primary portion maps lanes 0..CHIEN_REMAINDER to beat q; the
    // secondary portion maps the remaining lanes to beat q-1.
    wire [POSITION_BITS-1:0] primary_beat_full =
        (N-1-mask_base_i) >> LANE_BITS;
    wire [WIDTH-1:0] primary_mask = mask_i << PRIMARY_SHIFT;
    wire [WIDTH-1:0] secondary_mask = mask_i >> (CHIEN_REMAINDER+1);
    wire primary_valid = (primary_beat_full < BEATS) && (|primary_mask);
    wire secondary_valid = (primary_beat_full != 0) &&
        ((primary_beat_full-1) < BEATS) && (|secondary_mask);
    wire nonzero_message_mask = primary_valid || secondary_valid;

    wire result_needs_free = decoder_result_valid_i && !result_match_found;
    wire mask_context_available = mask_match_found ||
        (free_found && !result_needs_free);
    // The baseline bypasses storage for zero/non-message masks, but that
    // makes Chien root data part of the ready path back to the Chien state
    // registers.  The data-independent variant is deliberately conservative:
    // it may stall a zero mask when both contexts are occupied, but can never
    // accept a mask that lacks safe transactional storage.
    assign mask_ready_o = (DATA_INDEPENDENT_MASK_READY != 0) ?
        mask_context_available : (!nonzero_message_mask || mask_context_available);
    assign decoder_result_ready_o = (fifo_count_q < CONTEXTS) &&
        (result_match_found || free_found);

    wire [CONTEXT_BITS-1:0] head_context = result_fifo_q[fifo_read_q];
    wire [CONTEXT_BITS-1:0] result_context = result_match_found ?
        result_match_index : free_index;
    wire mask_accept = mask_valid_i && mask_ready_o && nonzero_message_mask;
    wire decoder_result_accept = decoder_result_valid_i && decoder_result_ready_o;
    wire result_accept = result_valid_o && result_ready_i;

    assign reread_request_tag_o = context_tag_q[head_context];
    assign reread_request_valid_o = state_q == S_REQUEST;
    assign reread_ready_o = (state_q == S_STREAM) && message_ready_i &&
        (reread_tag_i == context_tag_q[head_context]);

    reg [WIDTH-1:0] correction_mask;
    integer replay_entry;
    always @(*) begin
        correction_mask = 0;
        for (replay_entry = 0; replay_entry < T; replay_entry = replay_entry + 1)
            if ((replay_entry < entry_count_q[head_context]) &&
                (beat_q[head_context*T + replay_entry] == read_beat_q))
                correction_mask = correction_mask ^
                    mask_q[head_context*T + replay_entry];
    end

    assign message_tag_o = context_tag_q[head_context];
    assign message_data_o = reread_data_i ^ correction_mask;
    assign message_first_o = read_beat_q == 0;
    assign message_last_o = read_beat_q == BEATS-1;
    assign message_status_o = result_status_q[head_context];
    assign message_corrected_count_o = result_count_q[head_context];
    assign message_valid_o = (state_q == S_STREAM) && reread_valid_i &&
        (reread_tag_i == context_tag_q[head_context]);
    assign result_tag_o = context_tag_q[head_context];
    assign corrected_count_o = result_count_q[head_context];
    assign status_o = result_status_q[head_context];
    assign result_valid_o = state_q == S_RESULT;

    integer index;
    integer starting_count;
    integer collected_count;
    integer storage_base;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            fifo_write_q <= 0; fifo_read_q <= 0; fifo_count_q <= 0;
            read_beat_q <= 0; state_q <= S_IDLE;
            for (index = 0; index < CONTEXTS; index = index + 1) begin
                context_valid_q[index] <= 0; context_closed_q[index] <= 0;
                context_tag_q[index] <= 0; entry_count_q[index] <= 0;
                result_count_q[index] <= 0; result_status_q[index] <= 0;
                result_fifo_q[index] <= 0;
            end
            for (index = 0; index < CONTEXTS*T; index = index + 1) begin
                beat_q[index] <= 0;
                mask_q[index] <= 0;
            end
        end else begin
            if (mask_accept) begin
                starting_count = mask_match_found ?
                    entry_count_q[mask_match_index] : 0;
                storage_base = (mask_match_found ? mask_match_index : free_index) * T;
                collected_count = 0;
                if (primary_valid) begin
                    if (starting_count < T) begin
                        beat_q[storage_base + starting_count] <=
                            primary_beat_full[BEAT_BITS-1:0];
                        mask_q[storage_base + starting_count] <= primary_mask;
                    end
                    collected_count = 1;
                end
                if (secondary_valid) begin
                    if ((starting_count + collected_count) < T) begin
                        beat_q[storage_base + starting_count + collected_count] <=
                            primary_beat_full[BEAT_BITS-1:0] - 1'b1;
                        mask_q[storage_base + starting_count + collected_count] <=
                            secondary_mask;
                    end
                    collected_count = collected_count + 1;
                end
                if (mask_match_found) begin
                    if ((starting_count + collected_count) >= T)
                        entry_count_q[mask_match_index] <= T;
                    else
                        entry_count_q[mask_match_index] <=
                            starting_count + collected_count;
                end else begin
                    context_valid_q[free_index] <= 1;
                    context_closed_q[free_index] <= 0;
                    context_tag_q[free_index] <= mask_tag_i;
                    entry_count_q[free_index] <= collected_count;
                end
            end

            if (decoder_result_accept) begin
                context_valid_q[result_context] <= 1;
                context_closed_q[result_context] <= 1;
                context_tag_q[result_context] <= decoder_result_tag_i;
                result_count_q[result_context] <= decoder_corrected_count_i;
                result_status_q[result_context] <= decoder_status_i;
                if (!result_match_found) entry_count_q[result_context] <= 0;
                result_fifo_q[fifo_write_q] <= result_context;
                fifo_write_q <= (fifo_write_q == CONTEXTS-1) ?
                    0 : fifo_write_q + 1'b1;
            end
            if (result_accept) begin
                context_valid_q[head_context] <= 0;
                context_closed_q[head_context] <= 0;
                entry_count_q[head_context] <= 0;
                fifo_read_q <= (fifo_read_q == CONTEXTS-1) ?
                    0 : fifo_read_q + 1'b1;
            end
            case ({decoder_result_accept, result_accept})
                2'b10: fifo_count_q <= fifo_count_q + 1'b1;
                2'b01: fifo_count_q <= fifo_count_q - 1'b1;
                default: fifo_count_q <= fifo_count_q;
            endcase
            case (state_q)
                S_IDLE: begin
                    read_beat_q <= 0;
                    if (fifo_count_q != 0)
                        state_q <= (result_status_q[head_context] == 2) ?
                            S_RESULT : S_REQUEST;
                end
                S_REQUEST: if (reread_request_valid_o && reread_request_ready_i)
                    state_q <= S_STREAM;
                S_STREAM: if (message_valid_o && message_ready_i) begin
                    if (read_beat_q == BEATS-1) begin
                        read_beat_q <= 0; state_q <= S_RESULT;
                    end else read_beat_q <= read_beat_q + 1'b1;
                end
                S_RESULT: if (result_accept) state_q <= S_IDLE;
                default: state_q <= S_IDLE;
            endcase
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (K % WIDTH != 0) $fatal(1, "K must be divisible by WIDTH");
        if (N != K + R) $fatal(1, "N must equal K+R");
        if (CONTEXTS != 2) $fatal(1, "validated for two contexts");
        if ((1 << LANE_BITS) != WIDTH) $fatal(1, "WIDTH must be a power of two");
    end
`endif
endmodule

`default_nettype wire
