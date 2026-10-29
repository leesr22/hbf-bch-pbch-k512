`default_nettype none
`timescale 1ns/1ps

// Width-parameterized closed-form odd-syndrome transform.  The input word is
// MSB-first; unused bits in the final word occupy the low lanes.
module bch_syndrome_streaming_odd_linear_parallel_generic #(
    parameter integer M = 11,
    parameter integer T = 10,
    parameter integer N = 1134,
    parameter integer DATA_WIDTH = 64,
    parameter [M:0] PRIMITIVE_POLYNOMIAL = 12'h805,
    parameter integer FIELD_ORDER = (1 << M) - 1,
    parameter integer LAST_BITS = (N % DATA_WIDTH == 0) ? DATA_WIDTH : (N % DATA_WIDTH)
) (
    input  wire                       clk_i,
    input  wire                       rst_ni,
    input  wire [DATA_WIDTH-1:0]      chunk_i,
    input  wire                       first_i,
    input  wire                       last_i,
    input  wire                       valid_i,
    output wire [(2*T*M)-1:0]         syndromes_o,
    output reg                        done_o
);
    `include "rtl/lib/gf.svh"

    reg [M-1:0] odd_syndrome_q [0:T-1];
    reg [M-1:0] odd_syndrome_work [0:T-1];
    integer odd_index;
    integer lane;

    function automatic integer bch_trailing_zeros(input integer value);
        integer work;
        integer count;
        begin
            work = value;
            count = 0;
            while (((work & 1) == 0) && (count < M)) begin
                work = work >> 1;
                count = count + 1;
            end
            bch_trailing_zeros = count;
        end
    endfunction

    function automatic [M-1:0] bch_gf_square_generic(input [M-1:0] value);
        reg [(2*M)-2:0] expanded;
        integer bit_index;
        integer reduce_index;
        integer primitive_index;
        begin
            expanded = 0;
            for (bit_index = 0; bit_index < M; bit_index = bit_index + 1)
                expanded[2*bit_index] = value[bit_index];
            for (reduce_index = (2*M)-2; reduce_index >= M;
                 reduce_index = reduce_index - 1) begin
                if (expanded[reduce_index]) begin
                    expanded[reduce_index] = 0;
                    for (primitive_index = 0; primitive_index < M;
                         primitive_index = primitive_index + 1)
                        if (PRIMITIVE_POLYNOMIAL[primitive_index])
                            expanded[reduce_index-M+primitive_index] =
                                expanded[reduce_index-M+primitive_index] ^ 1'b1;
                end
            end
            bch_gf_square_generic = expanded[M-1:0];
        end
    endfunction

    function automatic [M-1:0] bch_repeated_square(
        input [M-1:0] value,
        input integer count
    );
        reg [M-1:0] work;
        integer square_index;
        begin
            work = value;
            for (square_index = 0; square_index < count;
                 square_index = square_index + 1)
                work = bch_gf_square_generic(work);
            bch_repeated_square = work;
        end
    endfunction

    genvar packed_index;
    generate
        for (packed_index = 1; packed_index <= 2*T;
             packed_index = packed_index + 1) begin : g_pack
            localparam integer SQUARE_COUNT = bch_trailing_zeros(packed_index);
            localparam integer ODD_EXPONENT = packed_index >> SQUARE_COUNT;
            localparam integer ODD_INDEX = (ODD_EXPONENT - 1) / 2;
            assign syndromes_o[(packed_index-1)*M +: M] =
                bch_repeated_square(odd_syndrome_q[ODD_INDEX], SQUARE_COUNT);
        end
    endgenerate

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            done_o <= 0;
            for (odd_index = 0; odd_index < T; odd_index = odd_index + 1)
                odd_syndrome_q[odd_index] <= 0;
        end else begin
            done_o <= 0;
            if (valid_i) begin
                for (odd_index = 0; odd_index < T; odd_index = odd_index + 1) begin
                    if (last_i) begin
                        odd_syndrome_work[odd_index] = bch_gf_multiply_generic(
                            first_i ? 0 : odd_syndrome_q[odd_index],
                            bch_alpha_power_generic((2*odd_index+1)*LAST_BITS));
                        for (lane = 0; lane < LAST_BITS; lane = lane + 1)
                            if (chunk_i[DATA_WIDTH-1-lane])
                                odd_syndrome_work[odd_index] =
                                    odd_syndrome_work[odd_index] ^
                                    bch_alpha_power_generic(
                                        (2*odd_index+1)*(LAST_BITS-1-lane));
                    end else begin
                        odd_syndrome_work[odd_index] = bch_gf_multiply_generic(
                            first_i ? 0 : odd_syndrome_q[odd_index],
                            bch_alpha_power_generic((2*odd_index+1)*DATA_WIDTH));
                        for (lane = 0; lane < DATA_WIDTH; lane = lane + 1)
                            if (chunk_i[DATA_WIDTH-1-lane])
                                odd_syndrome_work[odd_index] =
                                    odd_syndrome_work[odd_index] ^
                                    bch_alpha_power_generic(
                                        (2*odd_index+1)*(DATA_WIDTH-1-lane));
                    end
                    odd_syndrome_q[odd_index] <= odd_syndrome_work[odd_index];
                end
                if (last_i) done_o <= 1;
            end
        end
    end
endmodule

`default_nettype wire
