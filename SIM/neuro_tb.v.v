`timescale 1ns / 1ps

module tb_tt_um_neuron;

    reg  [7:0] ui_in;
    wire [7:0] uo_out;
    reg  [7:0] uio_in;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;
    reg        ena;
    reg        clk;
    reg        rst_n;

    wire busy = uio_out[0];
    wire done = uio_out[1];

    tt_um_neuron dut (
        .ui_in   (ui_in),
        .uo_out  (uo_out),
        .uio_in  (uio_in),
        .uio_out (uio_out),
        .uio_oe  (uio_oe),
        .ena     (ena),
        .clk     (clk),
        .rst_n   (rst_n)
    );

    initial clk = 0;
    always #10 clk = ~clk; // 20ns period

    // Address map mirrors RTL: 0-3=w0..w3, 4=bias, 5-8=in0..in3
    // Values passed as plain integers; converted to raw 6-bit two's
    // complement bit patterns before driving ui_in (no signed types
    // touch the DUT interface at all).
    task write_reg(input [3:0] address, input integer value);
        begin
            @(posedge clk);
            uio_in[3:0] = address;
            ui_in       = value[5:0]; // lower 6 bits = two's complement pattern
            uio_in[4]   = 1'b1;       // wr_en
            @(posedge clk);
            uio_in[4]   = 1'b0;
        end
    endtask

    task run_mac(output [7:0] out_val);
        begin
            uio_in[5] = 1'b1; // start
            @(posedge clk);
            wait (done == 1'b1);
            @(posedge clk); // sample after done settles
            out_val = uo_out;
            uio_in[5] = 1'b0;
            wait (done == 1'b0);
        end
    endtask

    reg [7:0] result;
    integer expected;

    initial begin
        $dumpfile("tb_tt_um_neuron.vcd");
        $dumpvars(0, tb_tt_um_neuron);

        ui_in  = 8'h00;
        uio_in = 8'h00;
        ena    = 1'b1;
        rst_n  = 1'b0;

        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        $display("[%0t] POST-RESET uo_out=%0d uio_out=%b", $time, uo_out, uio_out);

        // -----------------------------------------------------------
        // Scenario 1: simple positive MAC, no saturation
        // w = [1,2,3,4], in = [1,1,1,1], bias = 0
        // expected = 1+2+3+4+0 = 10
        // -----------------------------------------------------------
        $display("[%0t] Scenario 1: basic positive MAC", $time);
        write_reg(4'd0, 1);   // w0
        write_reg(4'd1, 2);   // w1
        write_reg(4'd2, 3);   // w2
        write_reg(4'd3, 4);   // w3
        write_reg(4'd4, 0);   // bias
        write_reg(4'd5, 1);   // in0
        write_reg(4'd6, 1);   // in1
        write_reg(4'd7, 1);   // in2
        write_reg(4'd8, 1);   // in3

        run_mac(result);
        expected = 10;
        if (result == expected[7:0])
            $display("[%0t] PASS: result=%0d expected=%0d", $time, result, expected);
        else
            $display("[%0t] ERROR: result=%0d expected=%0d", $time, result, expected);

        // -----------------------------------------------------------
        // Scenario 2: negative accumulation -> ReLU clamps to 0
        // w = [-5,-5,-5,-5] (two's complement: 64-5=59), in = [1,1,1,1]
        // bias = 0 -> sum = -20 -> ReLU 0
        // -----------------------------------------------------------
        $display("[%0t] Scenario 2: ReLU clamp on negative sum", $time);
        write_reg(4'd0, 64-5);
        write_reg(4'd1, 64-5);
        write_reg(4'd2, 64-5);
        write_reg(4'd3, 64-5);
        write_reg(4'd4, 0);
        // inputs remain [1,1,1,1] from scenario 1

        run_mac(result);
        if (result == 8'd0)
            $display("[%0t] PASS: ReLU correctly clamped negative sum to 0", $time);
        else
            $display("[%0t] ERROR: expected 0, got %0d", $time, result);

        // -----------------------------------------------------------
        // Scenario 3: large positive sum -> saturate at 255
        // w = [31,31,31,31] (max 6-bit signed), in = [4,4,4,4], bias=31
        // products = 31*4 = 124 each -> sum = 496 + 31 = 527 -> sat 255
        // -----------------------------------------------------------
        $display("[%0t] Scenario 3: positive saturation at 255", $time);
        write_reg(4'd0, 31);
        write_reg(4'd1, 31);
        write_reg(4'd2, 31);
        write_reg(4'd3, 31);
        write_reg(4'd4, 31);
        write_reg(4'd5, 4);
        write_reg(4'd6, 4);
        write_reg(4'd7, 4);
        write_reg(4'd8, 4);

        run_mac(result);
        if (result == 8'd255)
            $display("[%0t] PASS: correctly saturated to 255", $time);
        else
            $display("[%0t] ERROR: expected 255, got %0d", $time, result);

        // -----------------------------------------------------------
        // Scenario 4: mixed signed weights/inputs, exact mid-range value
        // w = [3,-2,4,-1], in = [10,5,2,3], bias=-5
        // sum = 30 -10 +8 -3 -5 = 20
        // -----------------------------------------------------------
        $display("[%0t] Scenario 4: mixed signed MAC", $time);
        write_reg(4'd0, 3);
        write_reg(4'd1, 64-2);
        write_reg(4'd2, 4);
        write_reg(4'd3, 64-1);
        write_reg(4'd4, 64-5);
        write_reg(4'd5, 10);
        write_reg(4'd6, 5);
        write_reg(4'd7, 2);
        write_reg(4'd8, 3);

        run_mac(result);
        expected = 20;
        if (result == expected[7:0])
            $display("[%0t] PASS: result=%0d expected=%0d", $time, result, expected);
        else
            $display("[%0t] ERROR: result=%0d expected=%0d", $time, result, expected);

        // -----------------------------------------------------------
        // Scenario 5: minimum 6-bit signed value edge case (-32)
        // w = [-32,0,0,0], in = [1,0,0,0], bias = 0 -> sum = -32 -> ReLU 0
        // -----------------------------------------------------------
        $display("[%0t] Scenario 5: minimum 6-bit signed value edge case", $time);
        write_reg(4'd0, 64-32);
        write_reg(4'd1, 0);
        write_reg(4'd2, 0);
        write_reg(4'd3, 0);
        write_reg(4'd4, 0);
        write_reg(4'd5, 1);
        write_reg(4'd6, 0);
        write_reg(4'd7, 0);
        write_reg(4'd8, 0);

        run_mac(result);
        if (result == 8'd0)
            $display("[%0t] PASS: min-value product handled correctly, ReLU->0", $time);
        else
            $display("[%0t] ERROR: expected 0, got %0d", $time, result);

        // -----------------------------------------------------------
        // Scenario 6: busy flag sanity check during computation
        // -----------------------------------------------------------
        $display("[%0t] Scenario 6: busy flag timing", $time);
        uio_in[5] = 1'b1; // start
        @(posedge clk);
        #1;
        if (busy)
            $display("[%0t] PASS: busy asserted during MAC sequence", $time);
        else
            $display("[%0t] ERROR: busy not asserted after start", $time);
        wait (done == 1'b1);
        #1;
        if (!busy)
            $display("[%0t] PASS: busy deasserted once done", $time);
        else
            $display("[%0t] ERROR: busy still asserted at done", $time);
        uio_in[5] = 1'b0;
        wait (done == 1'b0);

        repeat (5) @(posedge clk);
        $display("[%0t] Test sequence complete", $time);
        $finish;
    end

endmodule
