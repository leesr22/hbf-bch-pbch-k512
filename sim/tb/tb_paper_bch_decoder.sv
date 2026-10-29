`timescale 1ns/1ps
`default_nettype none
module tb_paper_bch_decoder;
  localparam integer VECTORS=64;
  reg clk=0,rst_n=0;always #1 clk=~clk;
  reg[571:0]received[0:VECTORS-1];reg[511:0]expected_message[0:VECTORS-1];
  reg[1:0]expected_status[0:VECTORS-1];reg[2:0]expected_weight[0:VECTORS-1];
  reg[63:0]codeword_data;reg codeword_first,codeword_last;reg[7:0]codeword_tag;
  reg codeword_valid;wire codeword_ready;wire[7:0]reread_request_tag;
  wire reread_request_valid;reg reread_request_ready=1;reg[7:0]reread_tag;
  reg[63:0]reread_data;reg reread_first,reread_last,reread_valid;wire reread_ready;
  wire[7:0]message_tag;wire[63:0]message_data;wire message_first,message_last;
  wire[1:0]message_status;wire[2:0]message_count;wire message_valid;reg message_ready=1;
  wire[7:0]result_tag;wire[2:0]corrected_count;wire[1:0]status;wire result_valid;
  reg result_ready=1;integer vi,beat,errors;reg[511:0]captured;
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
  initial begin
    $readmemh("sim/vectors/baseline_received.mem",received);
    $readmemh("sim/vectors/message.mem",expected_message);
    $readmemh("sim/vectors/baseline_status.mem",expected_status);
    $readmemh("sim/vectors/baseline_weight.mem",expected_weight);
    codeword_data=0;codeword_first=0;codeword_last=0;codeword_tag=0;codeword_valid=0;
    reread_tag=0;reread_data=0;reread_first=0;reread_last=0;reread_valid=0;errors=0;
    repeat(5)@(posedge clk);@(negedge clk);rst_n=1;
    for(vi=0;vi<VECTORS;vi=vi+1)begin
      for(beat=0;beat<9;beat=beat+1)begin
        @(negedge clk);codeword_data=(beat<8)?received[vi][571-beat*64-:64]:{received[vi][59:0],4'b0};
        codeword_first=(beat==0);codeword_last=(beat==8);codeword_tag=vi;codeword_valid=1;
        do @(posedge clk);while(!codeword_ready);@(negedge clk);codeword_valid=0;
      end
      captured=0;while(!reread_request_valid)@(posedge clk);@(posedge clk);
      for(beat=0;beat<8;beat=beat+1)begin
        @(negedge clk);reread_tag=vi;reread_data=received[vi][571-beat*64-:64];
        reread_first=(beat==0);reread_last=(beat==7);reread_valid=1;
        do @(posedge clk);while(!reread_ready);
        if(message_valid)captured[511-beat*64-:64]=message_data;
        @(negedge clk);reread_valid=0;
      end
      while(!result_valid)@(posedge clk);
      if(captured!==expected_message[vi]||status!==expected_status[vi]||
         corrected_count!==expected_weight[vi])begin
        $display("BCH DEC mismatch vi=%0d status=%0d count=%0d",vi,status,corrected_count);errors=errors+1;
      end
      @(posedge clk);
    end
    if(errors)$fatal(1,"BCH decoder failures=%0d",errors);
    $display("PASS paper BCH t6 decoder vectors=%0d",VECTORS);$finish;
  end
endmodule
`default_nettype wire

