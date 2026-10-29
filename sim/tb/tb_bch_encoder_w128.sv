`timescale 1ns/1ps
`default_nettype none
module tb_bch_encoder_w128;
  localparam integer VECTORS=64;
  reg clk=0,rst_n=0;always #1 clk=~clk;
  reg[511:0]messages[0:VECTORS-1];reg[571:0]expected[0:VECTORS-1];
  reg[127:0]message_data;reg message_first,message_last,message_valid;
  reg[7:0]message_tag;wire message_ready;wire[127:0]codeword_data;
  wire[7:0]codeword_valid_bits;wire codeword_first,codeword_last;
  wire[7:0]codeword_tag;wire codeword_valid;reg codeword_ready=1;
  integer vi,beat,out_beat,errors;reg[571:0]captured;
  paper_bch_encoder_k512_t6_w128 dut(
    .clk_i(clk),.rst_ni(rst_n),.message_data_i(message_data),
    .message_first_i(message_first),.message_last_i(message_last),
    .message_tag_i(message_tag),.message_valid_i(message_valid),
    .message_ready_o(message_ready),.codeword_data_o(codeword_data),
    .codeword_valid_bits_o(codeword_valid_bits),.codeword_first_o(codeword_first),
    .codeword_last_o(codeword_last),.codeword_tag_o(codeword_tag),
    .codeword_valid_o(codeword_valid),.codeword_ready_i(codeword_ready));
  initial begin
    $readmemh("sim/vectors/message.mem",messages);
    $readmemh("sim/vectors/baseline_codeword.mem",expected);
    message_data=0;message_first=0;message_last=0;message_tag=0;message_valid=0;errors=0;
    repeat(5)@(posedge clk);@(negedge clk);rst_n=1;
    for(vi=0;vi<VECTORS;vi=vi+1)begin
      captured=0;out_beat=0;
      for(beat=0;beat<4;beat=beat+1)begin
        @(negedge clk);message_data=messages[vi][511-beat*128-:128];
        message_first=(beat==0);message_last=(beat==3);message_tag=vi;message_valid=1;
        do begin @(posedge clk);
          if(codeword_valid&&codeword_ready)begin
            captured[571-out_beat*128-:128]=codeword_data;out_beat=out_beat+1;
          end
        end while(!message_ready);
      end
      @(negedge clk);message_valid=0;
      while(out_beat<5)begin
        @(posedge clk);
        if(codeword_valid&&codeword_ready)begin
          captured[59:0]=codeword_data[127:68];out_beat=out_beat+1;
        end
      end
      if(captured!==expected[vi])begin
        $display("BCH128 mismatch vi=%0d",vi);errors=errors+1;
      end
    end
    if(errors)$fatal(1,"BCH128 failures=%0d",errors);
    $display("PASS fair BCH t6 W128 vectors=%0d",VECTORS);$finish;
  end
endmodule
`default_nettype wire
