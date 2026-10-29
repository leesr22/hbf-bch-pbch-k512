`timescale 1ns/1ps
`default_nettype none

// Ordered selector state.  BCH correction and result streams are in input
// order, so no associative tag scan is required.
module select_fifo #(
    parameter INPUTS = 3,
    parameter DONE = 2
) (
    input wire clk, input wire reset_n,
    input wire [7:0] start_tag, input wire start_valid,
    output wire start_ready,
    input wire [19:0] raw_selector, input wire raw_valid,
    output wire raw_ready,
    input wire [9:0] correction_base, input wire [63:0] correction_mask,
    input wire correction_valid, output wire correction_ready,
    input wire [7:0] result_tag, input wire result_valid,
    output wire result_ready,
    input wire [7:0] lookup_tag,
    output wire [19:0] selector, output wire selector_valid,
    input wire retire
);
    localparam IW = (INPUTS < 2) ? 1 : $clog2(INPUTS);
    localparam DW = (DONE < 2) ? 1 : $clog2(DONE);
    localparam ICW = $clog2(INPUTS+1);
    localparam DCW = $clog2(DONE+1);

    reg [7:0] in_tag [0:INPUTS-1];
    reg [19:0] raw [0:INPUTS-1];
    reg [19:0] fix [0:INPUTS-1];
    reg [IW-1:0] in_head, in_tail, capture;
    reg [ICW-1:0] in_count;

    reg [7:0] done_tag [0:DONE-1];
    reg [19:0] done_selector [0:DONE-1];
    reg [DW-1:0] done_head, done_tail;
    reg [DCW-1:0] done_count;

    wire [19:0] selector_error = (correction_base == 0) ?
                                 correction_mask[59:40] : 0;
    wire correction_accept = correction_valid && correction_ready;
    wire result_accept = result_valid && result_ready;

    assign start_ready = in_count < INPUTS;
    assign raw_ready = in_count != 0;
    assign correction_ready = in_count != 0;
    assign result_ready = (in_count != 0) && (done_count < DONE);
    assign selector = done_selector[done_head];
    assign selector_valid = (done_count != 0) &&
                            (done_tag[done_head] == lookup_tag);

    function automatic [IW-1:0] next_in(input [IW-1:0] value);
        next_in = (value == INPUTS-1) ? 0 : value + 1'b1;
    endfunction
    function automatic [DW-1:0] next_done(input [DW-1:0] value);
        next_done = (value == DONE-1) ? 0 : value + 1'b1;
    endfunction

    integer i;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            in_head <= 0; in_tail <= 0; capture <= 0; in_count <= 0;
            done_head <= 0; done_tail <= 0; done_count <= 0;
            for (i=0; i<INPUTS; i=i+1) begin
                in_tag[i] <= 0; raw[i] <= 0; fix[i] <= 0;
            end
            for (i=0; i<DONE; i=i+1) begin
                done_tag[i] <= 0; done_selector[i] <= 0;
            end
        end else begin
            if (start_valid && start_ready) begin
                in_tag[in_tail] <= start_tag;
                raw[in_tail] <= 0;
                fix[in_tail] <= 0;
                capture <= in_tail;
                in_tail <= next_in(in_tail);
            end
            if (raw_valid && raw_ready) raw[capture] <= raw_selector;
            if (correction_accept)
                fix[in_head] <= fix[in_head] ^ selector_error;
            if (result_accept) begin
                done_tag[done_tail] <= result_tag;
                done_selector[done_tail] <= raw[in_head] ^ fix[in_head] ^
                    (correction_accept ? selector_error : 0);
                done_tail <= next_done(done_tail);
                in_head <= next_in(in_head);
            end
            case ({start_valid && start_ready, result_accept})
                2'b10: in_count <= in_count + 1'b1;
                2'b01: in_count <= in_count - 1'b1;
                default: in_count <= in_count;
            endcase
            if (retire) done_head <= next_done(done_head);
            case ({result_accept, retire})
                2'b10: done_count <= done_count + 1'b1;
                2'b01: done_count <= done_count - 1'b1;
                default: done_count <= done_count;
            endcase
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk) if (reset_n) begin
        if (raw_valid && raw_ready && in_tag[capture] != start_tag && start_valid)
            $fatal(1, "overlapping codeword capture");
        if (result_valid && result_ready && in_tag[in_head] != result_tag)
            $fatal(1, "result order mismatch");
        if (retire && done_count == 0) $fatal(1, "selector queue underflow");
    end
`endif
endmodule

`default_nettype wire
