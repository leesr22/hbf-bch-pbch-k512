`default_nettype none
`timescale 1ns/1ps

// Phase-2 architecture variant with independently parameterized input/syndrome
// stream width and Chien/mask width.  The syndrome block consumes the external
// width directly; a future gearbox can separate W_in from W_syn if measurement
// shows that such buffering is useful.
module bch_decoder_streaming_mask_parallel_generic #(
    parameter integer K = 1024,
    parameter integer M = 11,
    parameter integer T = 10,
    parameter integer N = 1134,
    parameter integer INPUT_WIDTH = 64,
    parameter integer CHIEN_WIDTH = 64,
    parameter [M:0] PRIMITIVE_POLYNOMIAL = 12'h805,
    parameter integer TAG_BITS = 8,
    parameter integer TWO_PHASE_BM = 0,
    parameter integer TWO_PHASE_SHIFT_WINDOW_BM = 0,
    parameter integer SHIFT_WINDOW_BM = 0,
    parameter integer CHIEN_RANGE_OPT = 0,
    parameter integer CHIEN_BALANCED_ROOT_COUNT = 0,
    parameter integer POSITION_BITS = (N < 2) ? 1 : $clog2(N),
    parameter integer COUNT_BITS = $clog2(T+2),
    parameter integer DEGREE_BITS = (T < 2) ? 1 : $clog2(T+1)
) (
    input  wire                         clk_i,
    input  wire                         rst_ni,
    input  wire [INPUT_WIDTH-1:0]       chunk_i,
    input  wire                         chunk_first_i,
    input  wire                         chunk_last_i,
    input  wire [TAG_BITS-1:0]          chunk_tag_i,
    input  wire                         chunk_valid_i,
    output wire                         chunk_ready_o,
    output wire [TAG_BITS-1:0]          correction_tag_o,
    output wire [POSITION_BITS-1:0]     correction_base_o,
    output wire [CHIEN_WIDTH-1:0]       correction_mask_o,
    output wire                         correction_valid_o,
    input  wire                         correction_ready_i,
    output wire [TAG_BITS-1:0]          result_tag_o,
    output wire [COUNT_BITS-1:0]        corrected_count_o,
    output wire [1:0]                   status_o,
    output wire                         result_valid_o,
    input  wire                         result_ready_i
);
    localparam [1:0] STATUS_NO_ERROR = 0;
    localparam [1:0] STATUS_CORRECTED = 1;
    localparam [1:0] STATUS_DETECTED_FAILURE = 2;

    wire chunk_accept = chunk_valid_i && chunk_ready_o;
    wire [(2*T*M)-1:0] syndromes;
    wire syndrome_done;
    reg [TAG_BITS-1:0] input_tag_q;
    reg syndrome_slot_valid_q;
    reg syndrome_slot_zero_q;
    reg [TAG_BITS-1:0] syndrome_tag_q;

    wire [((T+1)*M)-1:0] locator;
    wire [DEGREE_BITS-1:0] locator_degree;
    wire bm_done;
    wire bm_busy;
    reg [TAG_BITS-1:0] bm_tag_q;
    reg locator_slot_valid_q;
    reg [DEGREE_BITS-1:0] locator_degree_slot_q;
    reg [TAG_BITS-1:0] locator_tag_q;

    wire [COUNT_BITS-1:0] chien_root_count;
    wire chien_overflow;
    wire chien_done;
    wire chien_busy;
    reg [TAG_BITS-1:0] chien_tag_q;
    reg [DEGREE_BITS-1:0] chien_degree_q;

    reg result_pending_q;
    reg [TAG_BITS-1:0] pending_tag_q;
    reg [COUNT_BITS-1:0] pending_count_q;
    reg [1:0] pending_status_q;
    reg result_valid_q;
    reg [TAG_BITS-1:0] result_tag_q;
    reg [COUNT_BITS-1:0] result_count_q;
    reg [1:0] result_status_q;

    wire output_available = !result_valid_q || result_ready_i;
    wire pending_emit = result_pending_q && output_available;
    wire noerror_emit = syndrome_slot_valid_q && syndrome_slot_zero_q &&
        !result_pending_q && output_available;
    // A BM result produced on this edge reserves the one-entry locator slot.
    // Do not launch the next BM concurrently if the current Chien job is too
    // slow to consume that result first (notably I64/C32).
    wire bm_start = syndrome_slot_valid_q && !syndrome_slot_zero_q &&
        !bm_busy && !locator_slot_valid_q && !(bm_done && chien_busy);
    wire chien_start = locator_slot_valid_q && !chien_busy && !result_pending_q;

    assign chunk_ready_o = !syndrome_slot_valid_q && !syndrome_done;
    assign correction_tag_o = chien_tag_q;
    assign result_tag_o = result_tag_q;
    assign corrected_count_o = result_count_q;
    assign status_o = result_status_q;
    assign result_valid_o = result_valid_q;

    bch_syndrome_streaming_odd_linear_parallel_generic #(
        .M(M), .T(T), .N(N), .DATA_WIDTH(INPUT_WIDTH),
        .PRIMITIVE_POLYNOMIAL(PRIMITIVE_POLYNOMIAL)
    ) u_syndrome (
        .clk_i(clk_i), .rst_ni(rst_ni), .chunk_i(chunk_i),
        .first_i(chunk_first_i), .last_i(chunk_last_i), .valid_i(chunk_accept),
        .syndromes_o(syndromes), .done_o(syndrome_done)
    );

    generate
        if (TWO_PHASE_SHIFT_WINDOW_BM != 0) begin : g_two_phase_shift_window_bm
            bch_berlekamp_massey_inversionless_2phase_shift_generic #(
                .M(M), .T(T), .PRIMITIVE_POLYNOMIAL(PRIMITIVE_POLYNOMIAL)
            ) u_bm (
                .clk_i(clk_i), .rst_ni(rst_ni), .syndromes_i(syndromes), .start_i(bm_start),
                .locator_o(locator), .locator_degree_o(locator_degree),
                .done_o(bm_done), .busy_o(bm_busy)
            );
        end else if (SHIFT_WINDOW_BM != 0) begin : g_shift_window_bm
            bch_berlekamp_massey_inversionless_shift_generic #(
                .M(M), .T(T), .PRIMITIVE_POLYNOMIAL(PRIMITIVE_POLYNOMIAL)
            ) u_bm (
                .clk_i(clk_i), .rst_ni(rst_ni), .syndromes_i(syndromes), .start_i(bm_start),
                .locator_o(locator), .locator_degree_o(locator_degree),
                .done_o(bm_done), .busy_o(bm_busy)
            );
        end else if (TWO_PHASE_BM != 0) begin : g_two_phase_bm
            bch_berlekamp_massey_inversionless_2phase_generic #(
                .M(M), .T(T), .PRIMITIVE_POLYNOMIAL(PRIMITIVE_POLYNOMIAL)
            ) u_bm (
                .clk_i(clk_i), .rst_ni(rst_ni), .syndromes_i(syndromes), .start_i(bm_start),
                .locator_o(locator), .locator_degree_o(locator_degree),
                .done_o(bm_done), .busy_o(bm_busy)
            );
        end else begin : g_one_phase_bm
            bch_berlekamp_massey_inversionless_generic #(
                .M(M), .T(T), .PRIMITIVE_POLYNOMIAL(PRIMITIVE_POLYNOMIAL)
            ) u_bm (
                .clk_i(clk_i), .rst_ni(rst_ni), .syndromes_i(syndromes), .start_i(bm_start),
                .locator_o(locator), .locator_degree_o(locator_degree),
                .done_o(bm_done), .busy_o(bm_busy)
            );
        end
    endgenerate

    bch_chien_mask_stream_parallel_generic #(
        .M(M), .T(T), .N(N), .CHIEN_WIDTH(CHIEN_WIDTH),
        .RANGE_MASK_OPT(CHIEN_RANGE_OPT),
        .BALANCED_ROOT_COUNT(CHIEN_BALANCED_ROOT_COUNT),
        .PRIMITIVE_POLYNOMIAL(PRIMITIVE_POLYNOMIAL)
    ) u_chien (
        .clk_i(clk_i), .rst_ni(rst_ni), .locator_i(locator), .start_i(chien_start),
        .correction_base_o(correction_base_o), .correction_mask_o(correction_mask_o),
        .correction_valid_o(correction_valid_o), .correction_ready_i(correction_ready_i),
        .root_count_o(chien_root_count), .root_overflow_o(chien_overflow),
        .done_o(chien_done), .busy_o(chien_busy)
    );

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            input_tag_q <= 0;
            syndrome_slot_valid_q <= 0;
            syndrome_slot_zero_q <= 0;
            syndrome_tag_q <= 0;
            bm_tag_q <= 0;
            locator_slot_valid_q <= 0;
            locator_degree_slot_q <= 0;
            locator_tag_q <= 0;
            chien_tag_q <= 0;
            chien_degree_q <= 0;
            result_pending_q <= 0;
            pending_tag_q <= 0;
            pending_count_q <= 0;
            pending_status_q <= STATUS_NO_ERROR;
            result_valid_q <= 0;
            result_tag_q <= 0;
            result_count_q <= 0;
            result_status_q <= STATUS_NO_ERROR;
        end else begin
            if (result_valid_q && result_ready_i) result_valid_q <= 0;
            if (chunk_accept && chunk_first_i) input_tag_q <= chunk_tag_i;

            if (pending_emit) begin
                result_pending_q <= 0;
                result_valid_q <= 1;
                result_tag_q <= pending_tag_q;
                result_count_q <= pending_count_q;
                result_status_q <= pending_status_q;
            end else if (noerror_emit) begin
                syndrome_slot_valid_q <= 0;
                result_valid_q <= 1;
                result_tag_q <= syndrome_tag_q;
                result_count_q <= 0;
                result_status_q <= STATUS_NO_ERROR;
            end

            // BM admission is independent of result-port retirement.  The
            // 64-bit pipeline can retire an older Chien result on the exact
            // cycle a new BM context starts.
            if (bm_start) begin
                syndrome_slot_valid_q <= 0;
                bm_tag_q <= syndrome_tag_q;
            end

            // Consume before produce: if BM starts in the same cycle that the
            // next syndrome finishes, the newly produced syndrome must remain
            // in the one-entry slot.
            if (syndrome_done) begin
                syndrome_slot_valid_q <= 1;
                syndrome_slot_zero_q <= (syndromes == 0);
                syndrome_tag_q <= input_tag_q;
            end

            if (chien_start) begin
                locator_slot_valid_q <= 0;
                chien_tag_q <= locator_tag_q;
                chien_degree_q <= locator_degree_slot_q;
            end
            // Likewise preserve a new BM result when Chien consumes the prior
            // locator on the same edge.
            if (bm_done) begin
                locator_slot_valid_q <= 1;
                locator_degree_slot_q <= locator_degree;
                locator_tag_q <= bm_tag_q;
            end
            if (chien_done) begin
                result_pending_q <= 1;
                pending_tag_q <= chien_tag_q;
                pending_count_q <= chien_root_count;
                pending_status_q <= (!chien_overflow && (chien_root_count == chien_degree_q) &&
                    (chien_degree_q != 0) && (chien_degree_q <= T))
                    ? STATUS_CORRECTED : STATUS_DETECTED_FAILURE;
            end
        end
    end
endmodule

`default_nettype wire
