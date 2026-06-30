// uart_tb.v
// Testbench for UART TX + RX (loopback configuration)
// Tests:
//   1. Multiple data bytes (0x00, 0xFF, 0xAA, 0x55, 0x3F, random)
//   2. Parity checking (EVEN mode)
//   3. Frame error injection (corrupted stop bit)
//
// Run with: iverilog -o uart_sim uart_tb.v uart_tx.v uart_rx.v
//           vvp uart_sim
//           gtkwave uart_tb.vcd

`timescale 1ns/10ps
`include "uart_tx.v"
`include "uart_rx.v"

module uart_tb;

    // -------------------------------------------------------
    // Parameters: 25 MHz clock, 115200 baud
    // -------------------------------------------------------
    localparam CLK_PERIOD_NS = 40;
    localparam CLKS_PER_BIT  = 217;
    localparam PARITY_MODE   = 1; // EVEN parity for this test

    reg clk;
    reg rst_n;
    reg tx_start;
    reg [7:0] tx_data;

    wire tx_active, tx_serial, tx_done;
    wire rx_dv, frame_error, parity_error;
    wire [7:0] rx_byte;
    wire uart_line;

    // -------------------------------------------------------
    // Error injection control
    // -------------------------------------------------------
    reg inject_frame_error;
    reg force_line;
    reg force_value;

    // Loopback: TX serial drives RX serial directly,
    // unless error injection forces the line
    assign uart_line = force_line ? force_value :
                        (tx_active ? tx_serial : 1'b1);

    // -------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------
    uart_tx #(
        .CLKS_PER_BIT (CLKS_PER_BIT),
        .PARITY_MODE  (PARITY_MODE)
    ) tx_inst (
        .clk        (clk),
        .rst_n      (rst_n),
        .tx_start   (tx_start),
        .tx_data    (tx_data),
        .tx_active  (tx_active),
        .tx_serial  (tx_serial),
        .tx_done    (tx_done)
    );

    uart_rx #(
        .CLKS_PER_BIT (CLKS_PER_BIT),
        .PARITY_MODE  (PARITY_MODE)
    ) rx_inst (
        .clk          (clk),
        .rst_n        (rst_n),
        .rx_serial    (uart_line),
        .rx_dv        (rx_dv),
        .rx_byte      (rx_byte),
        .frame_error  (frame_error),
        .parity_error (parity_error)
    );

    // -------------------------------------------------------
    // Clock generation
    // -------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD_NS/2) clk = ~clk;

    // -------------------------------------------------------
    // VCD dump
    // -------------------------------------------------------
    initial begin
        $dumpfile("uart_tb.vcd");
        $dumpvars(0, uart_tb);
    end

    // -------------------------------------------------------
    // Test tracking
    // -------------------------------------------------------
    integer pass_count;
    integer fail_count;

    // -------------------------------------------------------
    // Task: send one byte and check received byte matches
    // -------------------------------------------------------
    task send_byte;
        input [127:0] test_name;
        input [7:0]   byte_to_send;
        begin
            inject_frame_error = 0;
            force_line          = 0;

            @(posedge clk);
            tx_data  = byte_to_send;
            tx_start = 1'b1;
            @(posedge clk);
            tx_start = 1'b0;

            // wait for rx_dv to pulse (received)
            wait (rx_dv == 1'b1);
            @(posedge clk); // let signals settle

            if (rx_byte == byte_to_send && !frame_error && !parity_error) begin
                $display("  PASS | %s | sent=0x%02X received=0x%02X",
                          test_name, byte_to_send, rx_byte);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL | %s | sent=0x%02X received=0x%02X frame_err=%b parity_err=%b",
                          test_name, byte_to_send, rx_byte, frame_error, parity_error);
                fail_count = fail_count + 1;
            end

            // wait for tx_done and a little settle time before next test
            wait (tx_done == 1'b1);
            repeat (5) @(posedge clk);
        end
    endtask

    // -------------------------------------------------------
    // Main test sequence
    // -------------------------------------------------------
    initial begin
        pass_count = 0;
        fail_count = 0;
        rst_n      = 0;
        tx_start   = 0;
        tx_data    = 0;
        inject_frame_error = 0;
        force_line  = 0;
        force_value = 0;

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);

        $display("\n--- UART TX/RX Loopback Tests (EVEN parity) ---");
        send_byte("Byte 0x00", 8'h00);
        send_byte("Byte 0xFF", 8'hFF);
        send_byte("Byte 0xAA", 8'hAA);
        send_byte("Byte 0x55", 8'h55);
        send_byte("Byte 0x3F", 8'h3F);
        send_byte("Byte 0x7E", 8'h7E);

        // ---- Frame error injection test ----
        $display("\n--- Frame Error Injection Test ---");
        @(posedge clk);
        tx_data  = 8'hA5;
        tx_start = 1'b1;
        @(posedge clk);
        tx_start = 1'b0;

        // Wait until we're near the stop bit, then force line low
        // (corrupting what should be a high stop bit)
        repeat (CLKS_PER_BIT * 10) @(posedge clk); // approx into stop bit region
        force_line  = 1'b1;
        force_value = 1'b0; // force stop bit region low -> frame error

        wait (rx_dv == 1'b1);
        @(posedge clk);
        if (frame_error) begin
            $display("  PASS | Frame error correctly detected on corrupted stop bit");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL | Frame error not detected");
            fail_count = fail_count + 1;
        end
        force_line = 1'b0;
        wait (tx_done == 1'b1);
        repeat (5) @(posedge clk);

        // ---- Summary ----
        $display("\n=============================");
        $display("  RESULTS: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("=============================\n");

        $finish;
    end

    // -------------------------------------------------------
    // Timeout watchdog
    // -------------------------------------------------------
    initial begin
        #2000000;
        $display("TIMEOUT: simulation exceeded limit");
        $finish;
    end

endmodule
