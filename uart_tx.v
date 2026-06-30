// uart_tx.v
// UART Transmitter with optional parity bit support
//
// Frame format: 1 start bit + 8 data bits + 1 parity bit (optional) + 1 stop bit
// Improvements over baseline reference designs:
//   - Configurable parity (NONE, EVEN, ODD) via parameter
//   - Cleaner state encoding using localparam
//   - Synchronous active-low reset
//
// Set CLKS_PER_BIT = clock_freq / baud_rate
// Example: 25 MHz clock, 115200 baud -> CLKS_PER_BIT = 217

module uart_tx #(
    parameter CLKS_PER_BIT = 217,
    parameter PARITY_MODE  = 0    // 0 = NONE, 1 = EVEN, 2 = ODD
)(
    input            clk,
    input            rst_n,        // active-low synchronous reset
    input            tx_start,     // pulse high for 1 cycle to start transmission
    input  [7:0]     tx_data,      // byte to transmit
    output reg       tx_active,    // high while transmission in progress
    output reg       tx_serial,    // serial output line
    output reg       tx_done       // pulses high for 1 cycle when done
);

    // -------------------------------------------------------
    // State encoding
    // -------------------------------------------------------
    localparam IDLE       = 3'b000;
    localparam START_BIT  = 3'b001;
    localparam DATA_BITS  = 3'b010;
    localparam PARITY_BIT = 3'b011;
    localparam STOP_BIT   = 3'b100;

    reg [2:0]                       state;
    reg [$clog2(CLKS_PER_BIT)-1:0]  clk_count;
    reg [2:0]                       bit_index;
    reg [7:0]                       data_reg;
    reg                              parity_bit;

    // -------------------------------------------------------
    // Compute parity (combinational, registered when loading data)
    // EVEN parity: parity_bit makes total 1s count even
    // ODD  parity: parity_bit makes total 1s count odd
    // -------------------------------------------------------
    wire parity_calc = ^tx_data; // XOR reduction = parity of data bits (1 if odd number of 1s)

    always @(posedge clk) begin
        if (!rst_n) begin
            state      <= IDLE;
            tx_active  <= 1'b0;
            tx_serial  <= 1'b1;
            tx_done    <= 1'b0;
            clk_count  <= 0;
            bit_index  <= 0;
            data_reg   <= 0;
            parity_bit <= 0;
        end else begin
            tx_done <= 1'b0; // default: pulse only in STOP_BIT completion

            case (state)

                // -----------------------------------------------
                IDLE: begin
                    tx_serial <= 1'b1;  // idle line is high
                    clk_count <= 0;
                    bit_index <= 0;
                    if (tx_start) begin
                        tx_active  <= 1'b1;
                        data_reg   <= tx_data;
                        // EVEN parity: parity_bit = parity_calc
                        // ODD  parity: parity_bit = ~parity_calc
                        parity_bit <= (PARITY_MODE == 2) ? ~parity_calc : parity_calc;
                        state      <= START_BIT;
                    end
                end

                // -----------------------------------------------
                START_BIT: begin
                    tx_serial <= 1'b0; // start bit = 0
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count <= 0;
                        state     <= DATA_BITS;
                    end
                end

                // -----------------------------------------------
                DATA_BITS: begin
                    tx_serial <= data_reg[bit_index];
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count <= 0;
                        if (bit_index < 7) begin
                            bit_index <= bit_index + 1;
                        end else begin
                            bit_index <= 0;
                            // skip parity state entirely if PARITY_MODE = NONE
                            state <= (PARITY_MODE == 0) ? STOP_BIT : PARITY_BIT;
                        end
                    end
                end

                // -----------------------------------------------
                PARITY_BIT: begin
                    tx_serial <= parity_bit;
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count <= 0;
                        state     <= STOP_BIT;
                    end
                end

                // -----------------------------------------------
                STOP_BIT: begin
                    tx_serial <= 1'b1; // stop bit = 1
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count <= 0;
                        tx_done   <= 1'b1;
                        tx_active <= 1'b0;
                        state     <= IDLE;
                    end
                end

                default: state <= IDLE;

            endcase
        end
    end

endmodule
