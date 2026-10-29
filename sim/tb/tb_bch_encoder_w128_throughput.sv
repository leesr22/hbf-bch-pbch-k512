`timescale 1ns/1ps
`default_nettype none
module tb_bch_encoder_w128_throughput;
  localparam integer TXNS=4096;
  reg clk=0,rst_n=0;always #1 clk=~clk;
  reg[127:0]message_data;reg message_first,message_last,message_valid;
  reg[7:0]message_tag;wire message_ready;wire[127:0]codeword_data;
  wire[7:0]codeword_valid_bits;wire codeword_first,codeword_last;
  wire[7:0]codeword_tag;wire codeword_valid;reg codeword_ready=1;
  integer cycle=0,txn,beat,completed=0,sum_hii=0,sum_cii=0,max_hii=0,max_cii=0;
  integer accept_cycle[0:TXNS-1],result_cycle[0:TXNS-1];
  always @(posedge clk)begin
    cycle<=cycle+1;
    if(rst_n&&codeword_valid&&codeword_ready&&codeword_last)begin
      result_cycle[completed]=cycle;completed=completed+1;
    end
  end
  paper_bch_encoder_k512_t6_w128 dut(
    .clk_i(clk),.rst_ni(rst_n),.message_data_i(message_data),
    .message_first_i(message_first),.message_last_i(message_last),
    .message_tag_i(message_tag),.message_valid_i(message_valid),
    .message_ready_o(message_ready),.codeword_data_o(codeword_data),
    .codeword_valid_bits_o(codeword_valid_bits),.codeword_first_o(codeword_first),
    .codeword_last_o(codeword_last),.codeword_tag_o(codeword_tag),
    .codeword_valid_o(codeword_valid),.codeword_ready_i(codeword_ready));
  initial begin
    message_data=0;message_first=0;message_last=0;message_tag=0;message_valid=0;
    repeat(5)@(posedge clk);@(negedge clk);rst_n=1;
    for(txn=0;txn<TXNS;txn=txn+1)begin
      for(beat=0;beat<4;beat=beat+1)begin
        @(negedge clk);message_data=txn*4+beat;
        message_first=(beat==0);message_last=(beat==3);message_tag=txn[7:0];message_valid=1;
        do @(posedge clk);while(!message_ready);
        if(beat==0)accept_cycle[txn]=cycle;
      end
    end
    @(negedge clk);message_valid=0;
    while(completed<TXNS)@(posedge clk);
    for(txn=16;txn<TXNS;txn=txn+1)begin
      sum_hii=sum_hii+(accept_cycle[txn]-accept_cycle[txn-1]);
      sum_cii=sum_cii+(result_cycle[txn]-result_cycle[txn-1]);
      if(accept_cycle[txn]-accept_cycle[txn-1]>max_hii)max_hii=accept_cycle[txn]-accept_cycle[txn-1];
      if(result_cycle[txn]-result_cycle[txn-1]>max_cii)max_cii=result_cycle[txn]-result_cycle[txn-1];
    end
    $display("BCH128_THROUGHPUT txns=%0d HII=%0f maxH=%0d CII=%0f maxC=%0d",
      TXNS,$itor(sum_hii)/(TXNS-16),max_hii,$itor(sum_cii)/(TXNS-16),max_cii);
    $finish;
  end
endmodule
`default_nettype wire
