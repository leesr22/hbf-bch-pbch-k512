`default_nettype none
`timescale 1ns/1ps

// Width-parameterized direct parallel Chien reference.  This intentionally
// preserves the baseline arithmetic so the area/II cost of widening can be
// measured before applying multiplier-sharing transformations.
module bch_chien_mask_stream_parallel_generic #(
    parameter integer M = 11,
    parameter integer T = 10,
    parameter integer N = 1134,
    parameter integer CHIEN_WIDTH = 64,
    parameter integer RANGE_MASK_OPT = 0,
    parameter integer BALANCED_ROOT_COUNT = 0,
    parameter [M:0] PRIMITIVE_POLYNOMIAL = 12'h805,
    parameter integer FIELD_ORDER = (1 << M) - 1,
    parameter integer POSITION_BITS = (N < 2) ? 1 : $clog2(N),
    parameter integer COUNT_BITS = $clog2(T+2),
    parameter integer BATCH_COUNT_BITS = $clog2(CHIEN_WIDTH+1),
    parameter integer GROUP_SIZE = 8,
    parameter integer GROUP_COUNT = (CHIEN_WIDTH+GROUP_SIZE-1)/GROUP_SIZE,
    parameter integer GROUP_COUNT_BITS = $clog2(GROUP_SIZE+1)
) (
    input  wire                         clk_i,
    input  wire                         rst_ni,
    input  wire [((T+1)*M)-1:0]         locator_i,
    input  wire                         start_i,
    output wire [POSITION_BITS-1:0]     correction_base_o,
    output wire [CHIEN_WIDTH-1:0]       correction_mask_o,
    output wire                         correction_valid_o,
    input  wire                         correction_ready_i,
    output reg  [COUNT_BITS-1:0]        root_count_o,
    output reg                          root_overflow_o,
    output reg                          done_o,
    output wire                         busy_o
);
    `include "rtl/lib/gf.svh"

    reg [M-1:0] terms_q [0:T];
    wire [M-1:0] lane_terms [0:CHIEN_WIDTH-1][0:T];
    wire [M-1:0] lane_values [0:CHIEN_WIDTH-1];
    wire [M-1:0] advanced_terms [0:T];
    wire [CHIEN_WIDTH-1:0] lane_roots;
    reg [BATCH_COUNT_BITS-1:0] batch_count;
    reg [GROUP_COUNT_BITS-1:0] group_count [0:GROUP_COUNT-1];
    wire [COUNT_BITS+BATCH_COUNT_BITS:0] total_count = root_count_o + batch_count;
    reg [POSITION_BITS-1:0] base_position_q;
    reg busy_q;
    localparam integer LAST_VALID_LANES = N % CHIEN_WIDTH;
    wire final_window = ((base_position_q + CHIEN_WIDTH) >= N);
    integer coefficient;
    integer count_lane;
    integer count_group;
    integer group_lane;

    genvar lane;
    genvar generated_coefficient;
    generate
        for (lane = 0; lane < CHIEN_WIDTH; lane = lane + 1) begin : g_lane
            for (generated_coefficient = 0; generated_coefficient <= T;
                 generated_coefficient = generated_coefficient + 1) begin : g_coefficient
                localparam [M-1:0] FACTOR =
                    bch_alpha_power_generic(-lane * generated_coefficient);
                assign lane_terms[lane][generated_coefficient] =
                    bch_gf_multiply_generic(terms_q[generated_coefficient], FACTOR);
            end
            reg [M-1:0] value;
            integer reduce_index;
            always @* begin
                value = 0;
                for (reduce_index = 0; reduce_index <= T; reduce_index = reduce_index + 1)
                    value = value ^ lane_terms[lane][reduce_index];
            end
            assign lane_values[lane] = value;
            if (RANGE_MASK_OPT != 0) begin : g_shared_range_mask
                // base_position_q is CHIEN_WIDTH-aligned.  Only the final
                // window can contain invalid lanes, so share one window
                // comparator and let constant propagation remove invalid
                // lanes instead of building WIDTH base+lane comparators.
                if (LAST_VALID_LANES == 0) begin : g_full_final_window
                    assign lane_roots[lane] = (value == 0);
                end else begin : g_partial_final_window
                    assign lane_roots[lane] = (value == 0) &&
                        (!final_window || (lane < LAST_VALID_LANES));
                end
            end else begin : g_reference_range_check
                assign lane_roots[lane] =
                    ((base_position_q + lane) < N) && (value == 0);
            end
        end
        for (generated_coefficient = 0; generated_coefficient <= T;
             generated_coefficient = generated_coefficient + 1) begin : g_advance
            localparam [M-1:0] FACTOR =
                bch_alpha_power_generic(-CHIEN_WIDTH * generated_coefficient);
            assign advanced_terms[generated_coefficient] =
                bch_gf_multiply_generic(terms_q[generated_coefficient], FACTOR);
        end
    endgenerate

    always @* begin
        batch_count = 0;
        for (count_group = 0; count_group < GROUP_COUNT; count_group = count_group + 1)
            group_count[count_group] = 0;
        if (BALANCED_ROOT_COUNT != 0) begin
            // Bound the longest explicit addition chain to GROUP_SIZE lanes
            // plus GROUP_COUNT partial sums instead of CHIEN_WIDTH lanes.
            // This is a timing-oriented structural variant; default behavior
            // remains bit-for-bit identical for controlled PPA comparison.
            for (count_group = 0; count_group < GROUP_COUNT; count_group = count_group + 1)
                for (group_lane = 0; group_lane < GROUP_SIZE; group_lane = group_lane + 1)
                    if ((count_group*GROUP_SIZE + group_lane) < CHIEN_WIDTH)
                        group_count[count_group] = group_count[count_group] +
                            lane_roots[count_group*GROUP_SIZE + group_lane];
            for (count_group = 0; count_group < GROUP_COUNT; count_group = count_group + 1)
                batch_count = batch_count + group_count[count_group];
        end else begin
            for (count_lane = 0; count_lane < CHIEN_WIDTH; count_lane = count_lane + 1)
                batch_count = batch_count + lane_roots[count_lane];
        end
    end

    assign correction_base_o = base_position_q;
    assign correction_mask_o = lane_roots;
    assign correction_valid_o = busy_q;
    assign busy_o = busy_q;

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            root_count_o <= 0;
            root_overflow_o <= 0;
            done_o <= 0;
            base_position_q <= 0;
            busy_q <= 0;
            for (coefficient = 0; coefficient <= T; coefficient = coefficient + 1)
                terms_q[coefficient] <= 0;
        end else begin
            done_o <= 0;
            if (start_i && !busy_q) begin
                root_count_o <= 0;
                root_overflow_o <= 0;
                base_position_q <= 0;
                busy_q <= 1;
                for (coefficient = 0; coefficient <= T; coefficient = coefficient + 1)
                    terms_q[coefficient] <= locator_i[coefficient*M +: M];
            end else if (busy_q && correction_ready_i) begin
                if (total_count > T) begin
                    root_count_o <= T+1;
                    root_overflow_o <= 1;
                end else begin
                    root_count_o <= total_count[COUNT_BITS-1:0];
                end
                for (coefficient = 0; coefficient <= T; coefficient = coefficient + 1)
                    terms_q[coefficient] <= advanced_terms[coefficient];
                if (final_window) begin
                    busy_q <= 0;
                    done_o <= 1;
                    base_position_q <= 0;
                end else begin
                    base_position_q <= base_position_q + CHIEN_WIDTH;
                end
            end
        end
    end
endmodule

`default_nettype wire
