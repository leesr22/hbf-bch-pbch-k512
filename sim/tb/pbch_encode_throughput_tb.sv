`timescale 1ns/1ps
`default_nettype none

module pbch_encode_throughput_tb;
`ifdef U0
    localparam U = 0;
`elsif U1
    localparam U = 1;
`elsif U20
    localparam U = 20;
`elsif U36
    localparam U = 36;
`else
    localparam U = 4;
`endif
    localparam TXNS = 128;

    reg clk = 0;
    reg reset_n = 0;
    always #1 clk = ~clk;

    reg [511:0] cache [0:TXNS-1];
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

    integer cycle, accepted, completed, previous_completion;
    integer max_hii, max_cii, max_latency;
    integer accept_cycle [0:TXNS-1];
    integer completion_cycle [0:TXNS-1];
    integer i, b;
    real mean_cii;

    always @(posedge clk) begin
        if (!reset_n) cycle <= 0;
        else cycle <= cycle + 1;
        if (reset_n && message_valid && message_ready && message_first) begin
            accept_cycle[message_tag] = cycle;
            if (accepted > 0 && cycle - accept_cycle[message_tag-1] > max_hii)
                max_hii = cycle - accept_cycle[message_tag-1];
            accepted = accepted + 1;
        end
        if (reset_n && codeword_valid && codeword_ready && codeword_last) begin
            completion_cycle[codeword_tag] = cycle;
            if (completed > 0 && cycle - previous_completion > max_cii)
                max_cii = cycle - previous_completion;
            if (cycle - accept_cycle[codeword_tag] > max_latency)
                max_latency = cycle - accept_cycle[codeword_tag];
            previous_completion = cycle;
            completed = completed + 1;
        end
    end

    initial begin : message_driver
        integer tx_local, beat_local;
        wait (reset_n);
        for (tx_local = 0; tx_local < TXNS; tx_local = tx_local + 1) begin
            for (beat_local = 0; beat_local < 8; beat_local = beat_local + 1) begin
                @(negedge clk);
                message_data = cache[tx_local][511-beat_local*64-:64];
                message_first = beat_local == 0;
                message_last = beat_local == 7;
                message_tag = tx_local;
                defect_count = U;
                message_valid = 1;
                do @(posedge clk); while (!message_ready);
            end
        end
        @(negedge clk);
        message_valid = 0;
    end

    initial begin : defect_driver
        integer tx_local, row_local, position_local;
        wait (reset_n);
        for (tx_local = 0; tx_local < TXNS; tx_local = tx_local + 1) begin
            while (!(defect_tag_valid && defect_tag == tx_local)) @(negedge clk);
            for (row_local = 0; row_local < U; row_local = row_local + 1) begin
                position_local = (tx_local * 7 + row_local * 53) % 572;
                @(negedge clk);
                defect_position = position_local;
                defect_forced = 0;
                defect_message_bit = position_local >= 60 ?
                    cache[tx_local][position_local-60] : 0;
                defect_valid = 1;
                do @(posedge clk); while (!defect_ready);
            end
            @(negedge clk);
            defect_valid = 0;
        end
    end

    initial begin : cache_driver
        integer tx_local, beat_local;
        wait (reset_n);
        for (tx_local = 0; tx_local < TXNS; tx_local = tx_local + 1) begin
            while (!read_request_valid) @(negedge clk);
            if (read_request_tag != tx_local) $fatal(1, "cache order mismatch");
            @(posedge clk);
            for (beat_local = 0; beat_local < 8; beat_local = beat_local + 1) begin
                @(negedge clk);
                read_tag = tx_local;
                read_data = cache[tx_local][511-beat_local*64-:64];
                read_first = beat_local == 0;
                read_last = beat_local == 7;
                read_valid = 1;
                do @(posedge clk); while (!read_ready);
            end
            @(negedge clk);
            read_valid = 0;
        end
    end

    initial begin
        for (i = 0; i < TXNS; i = i + 1)
            cache[i] = {16{i[7:0], (i*17+3), (i*29+5), (i*43+7)}};
        message_data = 0;
        message_first = 0;
        message_last = 0;
        message_tag = 0;
        defect_count = U;
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
        cycle = 0;
        accepted = 0;
        completed = 0;
        previous_completion = 0;
        max_hii = 0;
        max_cii = 0;
        max_latency = 0;
        repeat (5) @(posedge clk);
        @(negedge clk);
        reset_n = 1;
        wait (completed == TXNS);
        mean_cii = (completion_cycle[TXNS-1] - completion_cycle[0]) * 1.0 /
                   (TXNS - 1);
        $display("THROUGHPUT method=%0d U=%0d txns=%0d mean_cii=%f max_cii=%0d max_hii=%0d max_latency=%0d elapsed=%0d",
            0, U, TXNS, mean_cii, max_cii, max_hii,
            max_latency, completion_cycle[TXNS-1] - accept_cycle[0]);
        $finish;
    end

    initial begin
`ifdef TABLE
        #100000000;
`else
        #1000000;
`endif
        $fatal(1, "throughput timeout completed=%0d", completed);
    end
endmodule

`default_nettype wire
