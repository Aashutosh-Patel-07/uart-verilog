// uart_rx.v
// UART Receiver with optional parity checking and frame error detection
//
// Frame format matches uart_tx.v: 1 start bit + 8 data bits + parity (optional) + 1 stop bit
// Improvements over baseline reference designs:
//   - Configurable parity checking (NONE, EVEN, ODD)
//   - Frame error detection: flags if stop bit is not high (malformed frame)
//   - Parity error detection: flags if received parity doesn't match expected
//   - Mid-bit sampling technique retained (samples at bit centre to avoid jitter)
//
// Set CLKS_PER_BIT = clock_freq / baud_rate

module uart_rx #(
    parameter CLKS_PER_BIT = 217,
    parameter PARITY_MODE  = 0    // 0 = NONE, 1 = EVEN, 2 = ODD
)(
    input            clk,
    input            rst_n,
    input            rx_serial,
    output reg       rx_dv,        // data valid: pulses high for 1 cycle on successful receive
    output reg [7:0] rx_byte,      // received byte
    output reg       frame_error,  // pulses high if stop bit was not high
    output reg       parity_error  // pulses high if parity check failed
);

    localparam IDLE       = 3'b000;
    localparam START_BIT  = 3'b001;
    localparam DATA_BITS  = 3'b010;
    localparam PARITY_BIT = 3'b011;
    localparam STOP_BIT   = 3'b100;
    localparam CLEANUP    = 3'b101;

    reg [2:0]                       state;
    reg [$clog2(CLKS_PER_BIT)-1:0]  clk_count;
    reg [2:0]                       bit_index;
    reg [7:0]                       data_reg;
    reg                              received_parity;

    wire expected_parity = (PARITY_MODE == 2) ? ~(^data_reg) : (^data_reg);
    // EVEN mode: expected_parity = XOR of data bits
    // ODD  mode: expected_parity = complement of XOR of data bits

    always @(posedge clk) begin
        if (!rst_n) begin
            state           <= IDLE;
            clk_count       <= 0;
            bit_index       <= 0;
            data_reg        <= 0;
            rx_dv           <= 1'b0;
            rx_byte         <= 0;
            frame_error     <= 1'b0;
            parity_error    <= 1'b0;
            received_parity <= 1'b0;
        end else begin
            rx_dv         <= 1'b0; // default low, pulses in CLEANUP
            frame_error   <= 1'b0;
            parity_error  <= 1'b0;

            case (state)

                // -----------------------------------------------
                IDLE: begin
                    clk_count <= 0;
                    bit_index <= 0;
                    if (rx_serial == 1'b0) // start bit detected
                        state <= START_BIT;
                    else
                        state <= IDLE;
                end

                // -----------------------------------------------
                // Sample at the middle of the start bit to confirm
                // it's a real start bit (avoids glitches)
                START_BIT: begin
                    if (clk_count == (CLKS_PER_BIT - 1) / 2) begin
                        if (rx_serial == 1'b0) begin
                            clk_count <= 0;
                            state     <= DATA_BITS;
                        end else begin
                            state <= IDLE; // false start bit, glitch
                        end
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                // -----------------------------------------------
                DATA_BITS: begin
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count <= 0;
                        data_reg[bit_index] <= rx_serial;
                        if (bit_index < 7) begin
                            bit_index <= bit_index + 1;
                        end else begin
                            bit_index <= 0;
                            state <= (PARITY_MODE == 0) ? STOP_BIT : PARITY_BIT;
                        end
                    end
                end

                // -----------------------------------------------
                PARITY_BIT: begin
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count       <= 0;
                        received_parity <= rx_serial;
                        state           <= STOP_BIT;
                    end
                end

                // -----------------------------------------------
                STOP_BIT: begin
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count <= 0;
                        rx_byte   <= data_reg;
                        rx_dv     <= 1'b1;

                        // Frame error: stop bit should be high
                        if (rx_serial != 1'b1)
                            frame_error <= 1'b1;

                        // Parity error: only checked if parity mode enabled
                        if (PARITY_MODE != 0 && received_parity != expected_parity)
                            parity_error <= 1'b1;

                        state <= CLEANUP;
                    end
                end

                // -----------------------------------------------
                CLEANUP: begin
                    state <= IDLE;
                end

                default: state <= IDLE;

            endcase
        end
    end

endmodule
