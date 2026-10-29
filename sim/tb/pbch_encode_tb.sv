`timescale 1ns/1ps
`default_nettype none

module pbch_encode_tb;
    localparam VECTORS = 64;
    localparam MAX_ROWS = 2048;

    reg clk = 0;
    reg reset_n = 0;
    always #1 clk = ~clk;

    reg [511:0] messages [0:VECTORS-1];
    reg [9:0] defect_counts [0:VECTORS-1];
    reg [9:0] defect_positions [0:MAX_ROWS-1];
    reg [571:0] expected_codeword [0:VECTORS-1];
    reg [19:0] expected_selector [0:VECTORS-1];
    reg [4:0] expected_rank [0:VECTORS-1];
    reg [1:0] expected_status [0:VECTORS-1];

    reg [63:0] message_data;
    reg message_first, message_last, message_valid;
    reg [7:0] message_tag;
    reg [9:0] defect_count;
    wire message_ready;
    wire [7:0] defect_tag;
    wire defect_tag_valid;
    reg [9:0] defect_position;
    reg defect_forced, defect_message_bit, defect_valid;
    wire defect_ready;
    wire [7:0] read_request_tag;
    wire read_request_valid;
    reg read_request_ready = 1;
    reg [7:0] read_tag;
    reg [63:0] read_data;
    reg read_first, read_last, read_valid;
    wire read_ready;
    wire [63:0] codeword_data;
    wire [6:0] codeword_valid_bits;
    wire codeword_first, codeword_last;
    wire [7:0] codeword_tag;
    wire codeword_valid;
    reg codeword_ready = 1;
    wire [19:0] selector;
    wire [4:0] mask_rank;
    wire [1:0] mask_status;

    pbch_encode_gauss dut (.*);

    `undef HBF_PAPER_PBCH_K512_E20_CONSTANTS_SVH
    `include "rtl/generated/constants.svh"

    function automatic [571:0] mask_word;
        input [19:0] value;
        reg [571:0] result;
        reg [63:0] final_beat;
        integer b;
        begin
            result = 0;
            for (b = 0; b < 8; b = b + 1)
                result[571-b*64-:64] = pbch_codeword_mask_beat(b, value);
            final_beat = pbch_codeword_mask_beat(8, value);
            result[59:0] = final_beat[63:4];
            mask_word = result;
        end
    endfunction

    integer vector_index, beat, defect_index, row_cursor, errors;
    reg [571:0] captured;
    reg [571:0] expected_for_selector;

    task send_message;
        input integer index;
        begin
            for (beat = 0; beat < 8; beat = beat + 1) begin
                @(negedge clk);
                message_data = messages[index][511-beat*64-:64];
                message_first = beat == 0;
                message_last = beat == 7;
                message_tag = index;
                defect_count = defect_counts[index];
                message_valid = 1;
                do @(posedge clk); while (!message_ready);
                @(negedge clk);
                message_valid = 0;
            end
        end
    endtask

    task send_defects;
        input integer index;
        begin
            while (!defect_tag_valid) @(posedge clk);
            if (defect_tag != index) $fatal(1, "defect tag mismatch");
            for (defect_index = 0; defect_index < defect_counts[index];
                 defect_index = defect_index + 1) begin
                @(negedge clk);
                defect_position = defect_positions[row_cursor];
                defect_forced = 0;
                defect_message_bit = (defect_position >= 60) ?
                    messages[index][defect_position-60] : 1'b0;
                defect_valid = 1;
                do @(posedge clk); while (!defect_ready);
                @(negedge clk);
                defect_valid = 0;
                row_cursor = row_cursor + 1;
            end
        end
    endtask

    task serve_read;
        input integer index;
        integer read_beat;
        begin
            // The request is a normal ready/valid transfer.  Observe it on
            // the preceding falling edge so a continuously-ready cache does
            // not miss the one-cycle request in the testbench scheduler.
            while (!read_request_valid) @(negedge clk);
            if (read_request_tag != index) $fatal(1, "read request tag mismatch");
            @(posedge clk);
            for (read_beat = 0; read_beat < 8; read_beat = read_beat + 1) begin
                @(negedge clk);
                read_tag = index;
                read_data = messages[index][511-read_beat*64-:64];
                read_first = read_beat == 0;
                read_last = read_beat == 7;
                read_valid = 1;
                do @(posedge clk); while (!read_ready);
                @(negedge clk);
                read_valid = 0;
            end
        end
    endtask

    task collect_codeword;
        input integer index;
        integer output_beat_index;
        begin
            captured = 0;
            output_beat_index = 0;
            while (output_beat_index < 9) begin
                @(posedge clk);
                if (codeword_valid && codeword_ready) begin
                    if (codeword_tag != index) $fatal(1, "output tag mismatch");
                    if (output_beat_index < 8)
                        captured[571-output_beat_index*64-:64] = codeword_data;
                    else
                        captured[59:0] = codeword_data[63:4];
                    output_beat_index = output_beat_index + 1;
                end
            end
        end
    endtask

    initial begin
        $readmemh("sim/vectors/message.mem", messages);
        $readmemh("sim/vectors/defect_count.mem", defect_counts);
        $readmemh("sim/vectors/defect_position.mem", defect_positions);
        $readmemh("sim/vectors/encoder_codeword.mem", expected_codeword);
        $readmemh("sim/vectors/encoder_selector.mem", expected_selector);
        $readmemh("sim/vectors/encoder_rank.mem", expected_rank);
        $readmemh("sim/vectors/encoder_mask_status.mem", expected_status);
        message_data = 0;
        message_first = 0;
        message_last = 0;
        message_tag = 0;
        defect_count = 0;
        message_valid = 0;
        defect_position = 0;
        defect_forced = 0;
        defect_message_bit = 0;
        defect_valid = 0;
        read_tag = 0;
        read_data = 0;
        read_first = 0;
        read_last = 0;
        read_valid = 0;
        row_cursor = 0;
        errors = 0;
        repeat (5) @(posedge clk);
        @(negedge clk);
        reset_n = 1;

        for (vector_index = 0; vector_index < VECTORS;
             vector_index = vector_index + 1) begin
            send_message(vector_index);
            send_defects(vector_index);
            fork
                serve_read(vector_index);
                collect_codeword(vector_index);
            join

            expected_for_selector = expected_codeword[vector_index] ^
                mask_word(expected_selector[vector_index]) ^ mask_word(selector);
            if (captured !== expected_for_selector) begin
                $display("codeword mismatch vector=%0d", vector_index);
                errors = errors + 1;
            end
`ifndef TABLE
            if (selector !== expected_selector[vector_index] ||
                mask_rank !== expected_rank[vector_index] ||
                mask_status !== expected_status[vector_index]) begin
                $display("metadata mismatch vector=%0d", vector_index);
                errors = errors + 1;
            end
`else
`endif
        end
        if (errors) $fatal(1, "PBCH encoder failures=%0d", errors);
        $display("PASS PBCH encoder vectors=%0d rows=%0d", VECTORS, row_cursor);
        $finish;
    end

    initial begin
`ifdef TABLE
        #20000000;
`else
        #100000;
`endif
        $display("DEBUG vector=%0d state=%0d/%0d capture=%0b solve=%0b output=%0b beat=%0d",
            vector_index, dut.core.state[0], dut.core.state[1],
            dut.core.capture_busy, dut.core.solve_busy, dut.core.output_busy,
            dut.core.output_beat);
        $fatal(1, "PBCH encoder timeout vector=%0d", vector_index);
    end
endmodule

`default_nettype wire
