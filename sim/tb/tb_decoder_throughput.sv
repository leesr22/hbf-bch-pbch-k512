`timescale 1ns/1ps
`default_nettype none
module tb_decoder_throughput;
  localparam integer TXNS=128;
  reg clk=0,rst_n=0;always #1 clk=~clk;
  reg[571:0]pbch_received[0:63],bch_received[0:63];
  reg[571:0]work_word;
  reg[63:0]codeword_data;reg codeword_first,codeword_last;reg[7:0]codeword_tag;
  reg codeword_valid;wire codeword_ready;
  wire[7:0]reread_request_tag;wire reread_request_valid;reg reread_request_ready=1;
  reg[7:0]reread_tag;reg[63:0]reread_data;reg reread_first,reread_last,reread_valid;
  wire reread_ready;wire[7:0]message_tag;wire[63:0]message_data;
  wire message_first,message_last;wire[1:0]message_status;wire[2:0]message_count;
  wire message_valid;reg message_ready=1;wire[7:0]result_tag;wire[2:0]corrected_count;
  wire[1:0]status;wire result_valid;reg result_ready=1;
  integer cycle=0,txn,beat,completed=0;integer accept_cycle[0:TXNS-1];
  integer result_cycle[0:TXNS-1];integer sum_hii=0,sum_cii=0,max_hii=0,max_cii=0;
  always @(posedge clk)cycle<=cycle+1;
`ifdef PBCH_MODE
`ifdef DECOUPLED
`ifdef PIPE_OUTPUT2
  paper_pbch_decoder_k512_e20_w64_decoupled_pipe2 dut(.clk_i(clk),.rst_ni(rst_n),
`elsif PIPE_OUTPUT
  paper_pbch_decoder_k512_e20_w64_decoupled_pipe dut(.clk_i(clk),.rst_ni(rst_n),
`else
  paper_pbch_decoder_k512_e20_w64_decoupled dut(.clk_i(clk),.rst_ni(rst_n),
`endif
    .codeword_data_i(codeword_data),.codeword_first_i(codeword_first),
    .codeword_last_i(codeword_last),.codeword_tag_i(codeword_tag),
    .codeword_valid_i(codeword_valid),.codeword_ready_o(codeword_ready),
    .reread_request_tag_o(reread_request_tag),.reread_request_valid_o(reread_request_valid),
    .reread_request_ready_i(reread_request_ready),.reread_tag_i(reread_tag),
    .reread_data_i(reread_data),.reread_first_i(reread_first),.reread_last_i(reread_last),
    .reread_valid_i(reread_valid),.reread_ready_o(reread_ready),.message_tag_o(message_tag),
    .message_data_o(message_data),.message_first_o(message_first),.message_last_o(message_last),
    .message_status_o(message_status),.message_corrected_count_o(message_count),
    .message_valid_o(message_valid),.message_ready_i(message_ready),.result_tag_o(result_tag),
    .corrected_count_o(corrected_count),.status_o(status),.result_valid_o(result_valid),
    .result_ready_i(result_ready));
`else
  paper_pbch_decoder_k512_e20_w64 dut(.clk_i(clk),.rst_ni(rst_n),
    .codeword_data_i(codeword_data),.codeword_first_i(codeword_first),
    .codeword_last_i(codeword_last),.codeword_tag_i(codeword_tag),
    .codeword_valid_i(codeword_valid),.codeword_ready_o(codeword_ready),
    .reread_request_tag_o(reread_request_tag),.reread_request_valid_o(reread_request_valid),
    .reread_request_ready_i(reread_request_ready),.reread_tag_i(reread_tag),
    .reread_data_i(reread_data),.reread_first_i(reread_first),.reread_last_i(reread_last),
    .reread_valid_i(reread_valid),.reread_ready_o(reread_ready),.message_tag_o(message_tag),
    .message_data_o(message_data),.message_first_o(message_first),.message_last_o(message_last),
    .message_status_o(message_status),.message_corrected_count_o(message_count),
    .message_valid_o(message_valid),.message_ready_i(message_ready),.result_tag_o(result_tag),
    .corrected_count_o(corrected_count),.status_o(status),.result_valid_o(result_valid),
    .result_ready_i(result_ready));
`endif
`else
  paper_bch_decoder_k512_t6_w64 dut(.clk_i(clk),.rst_ni(rst_n),
    .codeword_data_i(codeword_data),.codeword_first_i(codeword_first),
    .codeword_last_i(codeword_last),.codeword_tag_i(codeword_tag),
    .codeword_valid_i(codeword_valid),.codeword_ready_o(codeword_ready),
    .reread_request_tag_o(reread_request_tag),.reread_request_valid_o(reread_request_valid),
    .reread_request_ready_i(reread_request_ready),.reread_tag_i(reread_tag),
    .reread_data_i(reread_data),.reread_first_i(reread_first),.reread_last_i(reread_last),
    .reread_valid_i(reread_valid),.reread_ready_o(reread_ready),.message_tag_o(message_tag),
    .message_data_o(message_data),.message_first_o(message_first),.message_last_o(message_last),
    .message_status_o(message_status),.message_corrected_count_o(message_count),
    .message_valid_o(message_valid),.message_ready_i(message_ready),.result_tag_o(result_tag),
    .corrected_count_o(corrected_count),.status_o(status),.result_valid_o(result_valid),
    .result_ready_i(result_ready));
`endif

  initial begin
    $readmemh("sim/vectors/decoder_received.mem",pbch_received);
    $readmemh("sim/vectors/baseline_received.mem",bch_received);
`ifdef PBCH_MODE
    work_word=pbch_received[4];
`else
    work_word=bch_received[6];
`endif
    codeword_data=0;codeword_first=0;codeword_last=0;codeword_tag=0;codeword_valid=0;
    reread_tag=0;reread_data=0;reread_first=0;reread_last=0;reread_valid=0;
    repeat(5)@(posedge clk);@(negedge clk);rst_n=1;
    for(txn=0;txn<TXNS;txn=txn+1)begin
      for(beat=0;beat<9;beat=beat+1)begin
        @(negedge clk);
        codeword_data=(beat<8)?work_word[571-beat*64-:64]:{work_word[59:0],4'b0};
        codeword_first=(beat==0);codeword_last=(beat==8);codeword_tag=txn;codeword_valid=1;
        do @(posedge clk);while(!codeword_ready);
        if(beat==0)accept_cycle[txn]=cycle;
      end
      @(negedge clk);codeword_valid=0;
    end
  end

  initial begin: reread_driver
    integer rbeat;reg[7:0]rtag;
    wait(rst_n);
    forever begin
      while(!reread_request_valid)@(posedge clk);
      rtag=reread_request_tag;@(posedge clk);
      for(rbeat=0;rbeat<8;rbeat=rbeat+1)begin
        @(negedge clk);reread_tag=rtag;
        reread_data=work_word[571-rbeat*64-:64];
        reread_first=(rbeat==0);reread_last=(rbeat==7);reread_valid=1;
        do @(posedge clk);while(!reread_ready);
      end
      @(negedge clk);reread_valid=0;
    end
  end

  always @(posedge clk)if(rst_n&&result_valid&&result_ready)begin
    result_cycle[completed]=cycle;completed=completed+1;
    if(completed==TXNS)begin
      for(txn=16;txn<TXNS;txn=txn+1)begin
        sum_hii=sum_hii+(accept_cycle[txn]-accept_cycle[txn-1]);
        sum_cii=sum_cii+(result_cycle[txn]-result_cycle[txn-1]);
        if(accept_cycle[txn]-accept_cycle[txn-1]>max_hii)
          max_hii=accept_cycle[txn]-accept_cycle[txn-1];
        if(result_cycle[txn]-result_cycle[txn-1]>max_cii)
          max_cii=result_cycle[txn]-result_cycle[txn-1];
      end
      $display("THROUGHPUT txns=%0d steady_hii=%0f max_hii=%0d steady_cii=%0f max_cii=%0d elapsed=%0d",
        TXNS,$itor(sum_hii)/(TXNS-16),max_hii,$itor(sum_cii)/(TXNS-16),max_cii,
        result_cycle[TXNS-1]-accept_cycle[0]);
      $finish;
    end
  end
  initial begin #2000000;$fatal(1,"throughput timeout completed=%0d",completed);end
endmodule
`default_nettype wire
