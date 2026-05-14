module uart_tx #(
    parameter int CLK_FREQ_HZ = 50_000_000,
    parameter int BAUD_RATE   = 115200
) (
    input  logic       clk_i,
    input  logic       rst_ni,
    input  logic [11:0] data_i,
    input  logic       valid_i,
    output logic       ready_o,
    output logic       tx_o
);
 
    localparam int BAUD_DIV = CLK_FREQ_HZ / BAUD_RATE;

    typedef enum logic [1:0] {
        IDLE,
        START,
        DATA,
        STOP
    } state_t;

    state_t state_q, state_d;

    logic [$clog2(BAUD_DIV)-1:0] baud_cnt_q, baud_cnt_d;
    logic [3:0] bit_cnt_q, bit_cnt_d;
    logic [11:0] shift_q, shift_d;
    logic tx_d;

    assign ready_o = (state_q == IDLE);

    always_comb begin
        state_d    = state_q;
        baud_cnt_d = baud_cnt_q;
        bit_cnt_d  = bit_cnt_q;
        shift_d    = shift_q;
        tx_d       = tx_o;

        case (state_q)
            IDLE: begin
                tx_d       = 1'b1;
                baud_cnt_d = '0;
                bit_cnt_d  = '0;

                if (valid_i) begin
                    shift_d = data_i;
                    state_d = START;
                end
            end

            START: begin
                tx_d = 1'b0;

                if (baud_cnt_q == BAUD_DIV - 1) begin
                    baud_cnt_d = '0;
                    state_d    = DATA;
                end else begin
                    baud_cnt_d = baud_cnt_q + 1;
                end
            end

            DATA: begin
                tx_d = shift_q[0];

                if (baud_cnt_q == BAUD_DIV - 1) begin
                    baud_cnt_d = '0;
                    shift_d    = {1'b0, shift_q[11:1]};

                    if (bit_cnt_q == 4'd11) begin
                        bit_cnt_d = '0;
                        state_d   = STOP;
                    end else begin
                        bit_cnt_d = bit_cnt_q + 1;
                    end
                end else begin
                    baud_cnt_d = baud_cnt_q + 1;
                end
            end

            STOP: begin
                tx_d = 1'b1;

                if (baud_cnt_q == BAUD_DIV - 1) begin
                    baud_cnt_d = '0;
                    state_d    = IDLE;
                end else begin
                    baud_cnt_d = baud_cnt_q + 1;
                end
            end

            default: begin
                state_d = IDLE;
                tx_d    = 1'b1;
            end
        endcase
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q    <= IDLE;
            baud_cnt_q <= '0;
            bit_cnt_q  <= '0;
            shift_q    <= '0;
            tx_o       <= 1'b1;
        end else begin
            state_q    <= state_d;
            baud_cnt_q <= baud_cnt_d;
            bit_cnt_q  <= bit_cnt_d;
            shift_q    <= shift_d;
            tx_o       <= tx_d;
        end
    end

endmodule
