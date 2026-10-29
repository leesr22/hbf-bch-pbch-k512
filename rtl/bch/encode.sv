`timescale 1ns/1ps
`default_nettype none

// BCH(572,512,t=6), 128-bit datapath.
module bch_encode (
    input wire clk, input wire reset_n,
    input wire [127:0] message, input wire first, input wire last,
    input wire [7:0] tag, input wire valid, output wire ready,
    output wire [127:0] codeword, output wire [7:0] valid_bits,
    output wire codeword_first, output wire codeword_last,
    output wire [7:0] codeword_tag, output wire codeword_valid,
    input wire codeword_ready
);
    bch_encoder_codeword_stream_single_state_generic #(
        .K(512), .R(60), .WIDTH(128),
        .GENERATOR(61'h1b642bb95045c4ad)
    ) core (
        .clk_i(clk), .rst_ni(reset_n), .message_data_i(message),
        .message_first_i(first), .message_last_i(last), .message_tag_i(tag),
        .message_valid_i(valid), .message_ready_o(ready),
        .codeword_data_o(codeword), .codeword_valid_bits_o(valid_bits),
        .codeword_first_o(codeword_first), .codeword_last_o(codeword_last),
        .codeword_tag_o(codeword_tag), .codeword_valid_o(codeword_valid),
        .codeword_ready_i(codeword_ready)
    );
endmodule

`default_nettype wire
