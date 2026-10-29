`timescale 1ns/1ps
`default_nettype none

// Complete k=512, ell=20 PBCH encoder.
//
// The page cache owns the original 512-bit message.  This block keeps only
// parity, masking metadata and tags.  During defect processing the cache
// supplies message_bit; during retirement it supplies the eight message
// beats again.  No message-sized scratch array is hidden in this module.
module pbch_encode #(
    parameter integer TAG_BITS = 8
) (
    input  wire                  clk,
    input  wire                  reset_n,

    input  wire [63:0]           message_data,
    input  wire                  message_first,
    input  wire                  message_last,
    input  wire [TAG_BITS-1:0]   message_tag,
    input  wire [9:0]            defect_count,
    input  wire                  message_valid,
    output wire                  message_ready,

    // Ordered defect stream for defect_tag.  message_bit is the original
    // cached message bit for positions 60..571 and is ignored otherwise.
    output wire [TAG_BITS-1:0]   defect_tag,
    output wire                  defect_tag_valid,
    input  wire [9:0]            defect_position,
    input  wire                  defect_forced,
    input  wire                  defect_message_bit,
    input  wire                  defect_valid,
    output wire                  defect_ready,

    // Sequential reread of the original message after the selector is known.
    output wire [TAG_BITS-1:0]   read_request_tag,
    output wire                  read_request_valid,
    input  wire                  read_request_ready,
    input  wire [TAG_BITS-1:0]   read_tag,
    input  wire [63:0]           read_data,
    input  wire                  read_first,
    input  wire                  read_last,
    input  wire                  read_valid,
    output wire                  read_ready,

    output wire [63:0]           codeword_data,
    output wire [6:0]            codeword_valid_bits,
    output wire                  codeword_first,
    output wire                  codeword_last,
    output wire [TAG_BITS-1:0]   codeword_tag,
    output wire                  codeword_valid,
    input  wire                  codeword_ready,

    output wire [19:0]           selector,
    output wire [4:0]            mask_rank,
    output wire [1:0]            mask_status
);
    `undef HBF_PAPER_PBCH_K512_E20_CONSTANTS_SVH
    `include "rtl/generated/constants.svh"

    localparam [2:0] FREE = 0, CAPTURE = 1, WAIT_SOLVER = 2,
                     SOLVING = 3, WAIT_OUTPUT = 4, OUTPUT = 5;

    reg [2:0] state [0:1];
    reg [39:0] parity [0:1];
    reg [TAG_BITS-1:0] tag [0:1];
    reg [9:0] defects [0:1];
    reg [15:0] order [0:1];
    reg [19:0] select [0:1];
    reg [4:0] rank [0:1];
    reg [1:0] status [0:1];

    reg capture_busy, capture_slot;
    reg [2:0] capture_beat;
    reg solve_busy, solve_slot;
    reg [9:0] rows_seen;
    reg output_busy, output_slot;
    reg [3:0] output_beat;
    reg [15:0] next_order;

    function automatic [39:0] parity64;
        input [39:0] old;
        input [63:0] data;
        reg [39:0] work;
        reg feedback;
        integer bit_index;
        begin
            work = old;
            for (bit_index = 0; bit_index < 64; bit_index = bit_index + 1) begin
                feedback = data[63-bit_index] ^ work[39];
                work = work << 1;
                if (feedback) work = work ^ PBCH_PARENT_GENERATOR[39:0];
            end
            parity64 = work;
        end
    endfunction

    function automatic [39:0] parity20zero;
        input [39:0] old;
        reg [39:0] work;
        reg feedback;
        integer bit_index;
        begin
            work = old;
            for (bit_index = 0; bit_index < 20; bit_index = bit_index + 1) begin
                feedback = work[39];
                work = work << 1;
                if (feedback) work = work ^ PBCH_PARENT_GENERATOR[39:0];
            end
            parity20zero = work;
        end
    endfunction

    wire free_slot = (state[0] == FREE) ? 1'b0 : 1'b1;
    wire free_valid = (state[0] == FREE) || (state[1] == FREE);
    assign message_ready = capture_busy || free_valid;

    reg solve_pick_valid, solve_pick;
    always @* begin
        solve_pick_valid = 1'b0;
        solve_pick = 1'b0;
        if (state[0] == WAIT_SOLVER && state[1] == WAIT_SOLVER) begin
            solve_pick_valid = 1'b1;
            solve_pick = (order[1] < order[0]);
        end else if (state[0] == WAIT_SOLVER) begin
            solve_pick_valid = 1'b1;
            solve_pick = 1'b0;
        end else if (state[1] == WAIT_SOLVER) begin
            solve_pick_valid = 1'b1;
            solve_pick = 1'b1;
        end
    end

    reg output_pick_valid, output_pick;
    always @* begin
        output_pick_valid = 1'b0;
        output_pick = 1'b0;
        if (state[0] == WAIT_OUTPUT && state[1] == WAIT_OUTPUT) begin
            output_pick_valid = 1'b1;
            output_pick = (order[1] < order[0]);
        end else if (state[0] == WAIT_OUTPUT) begin
            output_pick_valid = 1'b1;
            output_pick = 1'b0;
        end else if (state[1] == WAIT_OUTPUT) begin
            output_pick_valid = 1'b1;
            output_pick = 1'b1;
        end
    end

    wire solver_start = !solve_busy && solve_pick_valid;
    wire solver_start_ready;
    wire solver_row_ready;
    wire solver_done;
    wire [19:0] solver_selector;
    wire [4:0] solver_rank;
    wire solver_full;
    wire solver_row_valid = solve_busy && defect_valid;

    reg base_bit;
    always @* begin
        base_bit = 1'b0;
        if (defect_position < 40)
            base_bit = parity[solve_slot][defect_position[5:0]];
        else if (defect_position >= 60 && defect_position < 572)
            base_bit = defect_message_bit;
    end

    mask_gauss solver (
        .clk(clk), .reset_n(reset_n), .start(solver_start),
        .defects(defects[solve_pick]), .start_ready(solver_start_ready),
        .row(pbch_equation_row(defect_position)),
        .rhs(defect_forced ^ base_bit), .row_valid(solver_row_valid),
        .row_ready(solver_row_ready), .selector(solver_selector),
        .rank(solver_rank), .full_mask(solver_full), .done(solver_done),
        .done_ready(1'b1)
    );

    assign defect_tag = tag[solve_slot];
    assign defect_tag_valid = solve_busy;
    assign defect_ready = solve_busy && solver_row_ready;

    assign read_request_tag = tag[output_pick];
    assign read_request_valid = !output_busy && output_pick_valid;

    wire message_phase = output_beat < 8;
    assign codeword_valid = output_busy && (message_phase ? read_valid : 1'b1);
    assign read_ready = output_busy && message_phase && codeword_ready;
    assign codeword_first = output_beat == 0;
    assign codeword_last = output_beat == 8;
    assign codeword_valid_bits = codeword_last ? 7'd60 : 7'd64;
    assign codeword_tag = tag[output_slot];
    assign selector = select[output_slot];
    assign mask_rank = rank[output_slot];
    assign mask_status = status[output_slot];
    assign codeword_data = message_phase ?
        (read_data ^ pbch_codeword_mask_beat(output_beat, select[output_slot])) :
        ({20'b0, parity[output_slot], 4'b0} ^
         pbch_codeword_mask_beat(8, select[output_slot]));

    integer slot;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            for (slot = 0; slot < 2; slot = slot + 1) begin
                state[slot] <= FREE;
                parity[slot] <= 0;
                tag[slot] <= 0;
                defects[slot] <= 0;
                order[slot] <= 0;
                select[slot] <= 0;
                rank[slot] <= 0;
                status[slot] <= 0;
            end
            capture_busy <= 0;
            capture_slot <= 0;
            capture_beat <= 0;
            solve_busy <= 0;
            solve_slot <= 0;
            rows_seen <= 0;
            output_busy <= 0;
            output_slot <= 0;
            output_beat <= 0;
            next_order <= 0;
        end else begin
            if (message_valid && message_ready) begin
                if (!capture_busy) begin
                    capture_busy <= 1'b1;
                    capture_slot <= free_slot;
                    capture_beat <= 1;
                    state[free_slot] <= CAPTURE;
                    parity[free_slot] <= parity64(40'b0, message_data);
                    tag[free_slot] <= message_tag;
                    defects[free_slot] <= defect_count;
                    order[free_slot] <= next_order;
                    next_order <= next_order + 1'b1;
                end else if (capture_beat == 7) begin
                    parity[capture_slot] <= parity20zero(
                        parity64(parity[capture_slot], message_data));
                    state[capture_slot] <= WAIT_SOLVER;
                    capture_busy <= 1'b0;
                    capture_beat <= 0;
                end else begin
                    parity[capture_slot] <= parity64(parity[capture_slot], message_data);
                    capture_beat <= capture_beat + 1'b1;
                end
            end

            if (solver_start && solver_start_ready) begin
                solve_busy <= 1'b1;
                solve_slot <= solve_pick;
                rows_seen <= 0;
                state[solve_pick] <= SOLVING;
            end
            if (solver_row_valid && solver_row_ready)
                rows_seen <= rows_seen + 1'b1;
            if (solver_done) begin
                select[solve_slot] <= solver_selector;
                rank[solve_slot] <= solver_rank;
                status[solve_slot] <= !solver_full ? 2'd2 :
                                      (solver_rank == 20 ? 2'd0 : 2'd1);
                state[solve_slot] <= WAIT_OUTPUT;
                solve_busy <= 1'b0;
            end

            if (read_request_valid && read_request_ready) begin
                output_busy <= 1'b1;
                output_slot <= output_pick;
                output_beat <= 0;
                state[output_pick] <= OUTPUT;
            end else if (codeword_valid && codeword_ready) begin
                if (output_beat == 8) begin
                    state[output_slot] <= FREE;
                    output_busy <= 1'b0;
                    output_beat <= 0;
                end else begin
                    output_beat <= output_beat + 1'b1;
                end
            end
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk) if (reset_n) begin
        if (message_valid && message_ready) begin
            if (!capture_busy && !message_first)
                $fatal(1, "message_first missing");
            if (capture_busy && ((capture_beat == 7) != message_last))
                $fatal(1, "message_last mismatch");
        end
        if (read_valid && read_ready) begin
            if (read_tag != tag[output_slot]) $fatal(1, "source tag mismatch");
            if ((output_beat == 0) != read_first) $fatal(1, "source first mismatch");
            if ((output_beat == 7) != read_last) $fatal(1, "source last mismatch");
        end
    end
`endif
endmodule

module pbch_encode_gauss (input wire clk, reset_n,
    input wire [63:0] message_data, input wire message_first, message_last,
    input wire [7:0] message_tag, input wire [9:0] defect_count,
    input wire message_valid, output wire message_ready,
    output wire [7:0] defect_tag, output wire defect_tag_valid,
    input wire [9:0] defect_position, input wire defect_forced, defect_message_bit,
    input wire defect_valid, output wire defect_ready,
    output wire [7:0] read_request_tag, output wire read_request_valid,
    input wire read_request_ready, input wire [7:0] read_tag,
    input wire [63:0] read_data, input wire read_first, read_last, read_valid,
    output wire read_ready, output wire [63:0] codeword_data,
    output wire [6:0] codeword_valid_bits, output wire codeword_first, codeword_last,
    output wire [7:0] codeword_tag, output wire codeword_valid,
    input wire codeword_ready, output wire [19:0] selector,
    output wire [4:0] mask_rank, output wire [1:0] mask_status);
    pbch_encode core (.*);
endmodule

`default_nettype wire
