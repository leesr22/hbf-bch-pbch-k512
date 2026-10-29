`timescale 1ns/1ps
`default_nettype none

// Incremental Gaussian elimination for the fixed ell=20 PBCH mode.
// One equation is accepted, reduced against the pivot basis, and then the
// next equation is requested.  Only 20 pivot rows are stored.
module mask_gauss (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        start,
    input  wire [9:0]  defects,
    output wire        start_ready,
    input  wire [19:0] row,
    input  wire        rhs,
    input  wire        row_valid,
    output wire        row_ready,
    output wire [19:0] selector,
    output wire [4:0]  rank,
    output wire        full_mask,
    output wire        done,
    input  wire        done_ready
);
    localparam IDLE = 3'd0;
    localparam LOAD = 3'd1;
    localparam REDUCE = 3'd2;
    localparam SOLVE = 3'd3;
    localparam RESULT = 3'd4;

    reg [2:0] state;
    reg [9:0] left;
    reg [4:0] rank_q;
    reg inconsistent;
    reg [19:0] pivot_valid;
    reg [19:0] pivot_row [0:19];
    reg          pivot_rhs [0:19];
    reg [19:0] work_row_q;
    reg          work_rhs_q;
    reg [19:0] selector_q;

    reg [19:0] reduced_row;
    reg reduced_rhs;
    reg insert;
    reg [4:0] insert_column;
    integer column;
    always @* begin
        reduced_row = work_row_q;
        reduced_rhs = work_rhs_q;
        insert = 1'b0;
        insert_column = 0;
        for (column = 19; column >= 0; column = column - 1) begin
            if (!insert && reduced_row[column]) begin
                if (pivot_valid[column]) begin
                    reduced_row = reduced_row ^ pivot_row[column];
                    reduced_rhs = reduced_rhs ^ pivot_rhs[column];
                end else begin
                    insert = 1'b1;
                    insert_column = column[4:0];
                end
            end
        end
    end

    reg [19:0] solved;
    always @* begin
        solved = 20'b0;
        for (column = 0; column < 20; column = column + 1) begin
            if (pivot_valid[column])
                solved[column] = pivot_rhs[column] ^
                    ^(pivot_row[column] & solved);
        end
    end

    assign start_ready = (state == IDLE);
    assign row_ready = (state == LOAD);
    assign selector = selector_q;
    assign rank = rank_q;
    assign full_mask = !inconsistent;
    assign done = (state == RESULT);

    integer i;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= IDLE;
            left <= 0;
            rank_q <= 0;
            inconsistent <= 0;
            pivot_valid <= 0;
            work_row_q <= 0;
            work_rhs_q <= 0;
            selector_q <= 0;
            for (i = 0; i < 20; i = i + 1) begin
                pivot_row[i] <= 0;
                pivot_rhs[i] <= 0;
            end
        end else begin
            case (state)
                IDLE: if (start) begin
                    left <= defects;
                    rank_q <= 0;
                    inconsistent <= 0;
                    pivot_valid <= 0;
                    selector_q <= 0;
                    state <= (defects == 0) ? RESULT : LOAD;
                end

                LOAD: if (row_valid) begin
                    work_row_q <= row;
                    work_rhs_q <= rhs;
                    left <= left - 1'b1;
                    state <= REDUCE;
                end

                REDUCE: begin
                    if (insert) begin
                        pivot_valid[insert_column] <= 1'b1;
                        pivot_row[insert_column] <= reduced_row;
                        pivot_rhs[insert_column] <= reduced_rhs;
                        rank_q <= rank_q + 1'b1;
                    end else if (reduced_rhs) begin
                        // 0=1: retain the earlier constraints and leave this
                        // defect unmasked, matching physical-order fallback.
                        inconsistent <= 1'b1;
                    end
                    state <= (left == 0) ? SOLVE : LOAD;
                end

                SOLVE: begin
                    selector_q <= solved;
                    state <= RESULT;
                end

                RESULT: if (done_ready) state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
endmodule

`default_nettype wire
