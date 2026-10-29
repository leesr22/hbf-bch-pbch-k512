`default_nettype none
`timescale 1ns/1ps

// One-phase inversionless BM with fixed-index discrepancy operands.  A shifted
// syndrome history replaces T copies of syndromes[iteration-index] muxing.
module bch_berlekamp_massey_inversionless_shift_generic #(
    parameter integer M=11, parameter integer T=10,
    parameter [M:0] PRIMITIVE_POLYNOMIAL=12'h805,
    parameter integer FIELD_ORDER=(1<<M)-1,
    parameter integer DEGREE_BITS=(T<2)?1:$clog2(T+1),
    parameter integer ITERATION_BITS=(2*T<2)?1:$clog2(2*T),
    parameter integer LENGTH_BITS=$clog2(4*T+2)
) (
    input wire clk_i,input wire rst_ni,input wire [(2*T*M)-1:0] syndromes_i,
    input wire start_i,output reg [((T+1)*M)-1:0] locator_o,
    output reg [DEGREE_BITS-1:0] locator_degree_o,output reg done_o,
    output wire busy_o
);
    `include "rtl/lib/gf.svh"
    reg [M-1:0] syndrome_window_q[0:T];
    reg [M-1:0] syndrome_future_q[0:2*T-2];
    reg [M-1:0] lambda_q[0:T],auxiliary_q[0:T],gamma_q;
    reg signed [LENGTH_BITS-1:0] length_state_q;
    reg [DEGREE_BITS-1:0] degree_q;
    reg [ITERATION_BITS-1:0] iteration_q;
    reg busy_q;
    reg [M-1:0] discrepancy,lambda_work[0:T],lambda_old[0:T];
    reg [DEGREE_BITS-1:0] degree_work;
    integer index;
    assign busy_o=busy_q;

    always @(posedge clk_i or negedge rst_ni) begin
        if(!rst_ni) begin
            locator_o<=0;locator_degree_o<=0;done_o<=0;gamma_q<=0;
            length_state_q<=0;degree_q<=0;iteration_q<=0;busy_q<=0;
            for(index=0;index<=T;index=index+1) begin
                syndrome_window_q[index]<=0;lambda_q[index]<=0;auxiliary_q[index]<=0;
            end
            for(index=0;index<2*T-1;index=index+1) syndrome_future_q[index]<=0;
        end else begin
            done_o<=0;
            if(start_i&&!busy_q) begin
                syndrome_window_q[0]<=syndromes_i[0+:M];
                for(index=1;index<=T;index=index+1) syndrome_window_q[index]<=0;
                for(index=0;index<2*T-1;index=index+1)
                    syndrome_future_q[index]<=syndromes_i[(index+1)*M+:M];
                for(index=0;index<=T;index=index+1) begin
                    lambda_q[index]<=(index==0)?{{(M-1){1'b0}},1'b1}:0;
                    auxiliary_q[index]<=(index==0)?{{(M-1){1'b0}},1'b1}:0;
                end
                gamma_q<={{(M-1){1'b0}},1'b1};length_state_q<=0;
                degree_q<=0;iteration_q<=0;busy_q<=1;
            end else if(busy_q) begin
                discrepancy=0;
                for(index=0;index<=T;index=index+1)
                    discrepancy=discrepancy^bch_gf_multiply_generic(
                        lambda_q[index],syndrome_window_q[index]);
                for(index=0;index<=T;index=index+1) begin
                    lambda_old[index]=lambda_q[index];
                    lambda_work[index]=bch_gf_multiply_generic(gamma_q,lambda_q[index]);
                    if(index>0) lambda_work[index]=lambda_work[index]^
                        bch_gf_multiply_generic(discrepancy,auxiliary_q[index-1]);
                    lambda_q[index]<=lambda_work[index];
                end
                degree_work=degree_q;
                if((discrepancy==0)||(length_state_q<0)) begin
                    auxiliary_q[0]<=0;
                    for(index=1;index<=T;index=index+1)
                        auxiliary_q[index]<=auxiliary_q[index-1];
                    length_state_q<=length_state_q+1;
                end else begin
                    for(index=0;index<=T;index=index+1)
                        auxiliary_q[index]<=lambda_old[index];
                    length_state_q<=-1-length_state_q;gamma_q<=discrepancy;
                    degree_work=iteration_q+1-degree_q;degree_q<=degree_work;
                end
                for(index=T;index>0;index=index-1)
                    syndrome_window_q[index]<=syndrome_window_q[index-1];
                syndrome_window_q[0]<=syndrome_future_q[0];
                for(index=0;index<2*T-2;index=index+1)
                    syndrome_future_q[index]<=syndrome_future_q[index+1];
                syndrome_future_q[2*T-2]<=0;
                if(iteration_q==(2*T-1)) begin
                    for(index=0;index<=T;index=index+1)
                        locator_o[index*M+:M]<=lambda_work[index];
                    locator_degree_o<=degree_work;busy_q<=0;done_o<=1;
                end else iteration_q<=iteration_q+1;
            end
        end
    end
endmodule
`default_nettype wire
