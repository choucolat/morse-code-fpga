
// Here we define the inputs / outputs
module Exercisemorse #(
    parameter int CLK_FREQ_HZ = 50_000_000,
    parameter int DEBOUNCE_MS = 20,
    parameter int DOT_DASH_MS = 1000,
    parameter int LONG_PRESS_MS = 3000,
    parameter int CLICK_GAP_MS = 1000
) (
    input           MAX10_CLK1_50,  // 50 HMz clock
    input  [1:0]    KEY,            // Buttons
    inout  [9:0]    ARDUINO_IO,     // Header pins
    output [9:0]    LEDR,           // LEDs
    input  [9:0]    SW,             // Switches
    output [7:0]    HEX0,           // 7-segment dieplay
    output [7:0]    HEX1,           // 7-segment dieplay
    output [7:0]    HEX2,           // 7-segment dieplay
    output [7:0]    HEX3,           // 7-segment dieplay
    output [7:0]    HEX4,            // 7-segment dieplay
    output logic [11:0] decoded_symbol
//    output logic [4:0] data_seq,    // 5 bits: Dot=0, Dash=1
//    output logic [2:0] data_len,    // 3 bits
//    output logic [2:0] command_out, // 1: Char, 2: Word, 3: Msg, 4: Clear
//    output logic       valid_pulse  // Active high for 1 clock cycle
);
    logic clk;
    logic rst_n;
    logic btn_signal;
    logic btn_control;

    assign clk = MAX10_CLK1_50;
    assign rst_n = SW[9];
    assign btn_signal = ~KEY[0];
    assign btn_control = ~KEY[1];

    logic        valid_pulse;
    logic [2:0]  command_out;
    logic [4:0]  data_seq;
    logic [2:0]  data_len;
    logic        clear_data_len;

    logic uart_ready;
    logic uart_valid;
    logic uart_tx_o;
    logic valid_seen;
    logic [2:0] last_command;

    assign decoded_symbol = {valid_pulse, command_out, data_seq, data_len};
    assign uart_valid     = valid_pulse && uart_ready;
    assign ARDUINO_IO[0]  = uart_tx_o;
    assign ARDUINO_IO[9:1] = 9'bz;

    uart_tx #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE  (115200)
    ) i_uart_tx (
        .clk_i   (clk),
        .rst_ni  (rst_n),
        .data_i  (decoded_symbol),
        .valid_i (uart_valid),
        .ready_o (uart_ready),
        .tx_o    (uart_tx_o)
    );

    // here comes your design...

// --- Morse Input Handler ---
//module morse_input_handler (
//    input  logic clk,           // 200 MHz
//   input  logic rst_n,         // Active low reset
//    input  logic btn_signal,    // Button 1: Dots/Dashes
//    input  logic btn_control,   // Button 2: Control functions
    
    // Interface to Andrina
//    output logic [4:0] data_seq,    // 5 bits: Dot=0, Dash=1
//    output logic [2:0] data_len,    // 3 bits
//    output logic [2:0] command_out, // 1: Char, 2: Word, 3: Msg, 4: Clear
//    output logic       valid_pulse  // Active high for 1 clock cycle
//);

    // Constants
    localparam logic [2:0] CMD_NONE  = 3'd0;
    localparam logic [2:0] CMD_CHAR  = 3'd1;
    localparam logic [2:0] CMD_WORD  = 3'd2;
    localparam logic [2:0] CMD_MSG   = 3'd3;
    localparam logic [2:0] CMD_CLEAR = 3'd4;

    // --- 1. PRESCALER (1ms Tick for 200MHz) ---
    logic [15:0] prescale_cnt;
    logic        tick_1ms;
    
    assign tick_1ms = (prescale_cnt == CLK_FREQ_HZ / 1000 - 1);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) prescale_cnt <= 16'd0;
        else        prescale_cnt <= tick_1ms ? 16'd0 : prescale_cnt + 16'd1;
    end

    // --- 2. DEBOUNCING ---
    logic s_btn, c_btn;
    debounce #(.DEBOUNCE_MS(DEBOUNCE_MS)) db_signal (.clk(clk), .btn_in(btn_signal),  .tick(tick_1ms), .btn_out(s_btn));
    debounce #(.DEBOUNCE_MS(DEBOUNCE_MS)) db_ctrl   (.clk(clk), .btn_in(btn_control), .tick(tick_1ms), .btn_out(c_btn));

    assign LEDR[0] = btn_signal;
    assign LEDR[1] = s_btn;
    assign LEDR[2] = btn_control;
    assign LEDR[3] = c_btn;
    assign LEDR[4:8] = data_seq;
    assign LEDR[9] = valid_seen;

    assign HEX0 = seven_seg(data_len);
    assign HEX1 = seven_seg(last_command);
    assign HEX2 = 8'hff;
    assign HEX3 = 8'hff;
    assign HEX4 = 8'hff;

    // --- 3. BUTTON 1: DOTS (0) & DASHES (1) ---
    logic [9:0] s_timer; 
    logic       s_btn_prev; 
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_seq   <= 5'b0;
            data_len   <= 3'b0;
            s_timer    <= 10'd0;
            s_btn_prev <= 1'b0;
        end else begin
            s_btn_prev <= s_btn;
            
            if (clear_data_len) begin
                data_seq <= 5'b0;
                data_len <= 3'b0;
            end else if (s_btn) begin 
                if (tick_1ms && s_timer < 10'd1001) s_timer <= s_timer + 10'd1;
            end else if (s_btn_prev && !s_btn) begin // Falling edge (Release)
                // Shift in: Dash (1) if held >= 1s, else Dot (0)
                data_seq <= {data_seq[3:0], (s_timer >= DOT_DASH_MS)};
                data_len <= data_len + 3'd1;
                s_timer  <= 10'd0;
            end
        end
    end

    // --- 4. BUTTON 2: CONTROL FSM ---
    typedef enum logic [1:0] {
        C_IDLE  = 2'd0,
        C_PRESS = 2'd1,
        C_WAIT  = 2'd2
    } state_t;

    state_t    c_state;
    logic [1:0] click_count;
    logic [11:0] c_timer;
    logic        c_btn_prev;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            c_state      <= C_IDLE;
            click_count  <= 2'd0;
            command_out  <= CMD_NONE;
            valid_pulse  <= 1'b0;
            valid_seen   <= 1'b0;
            last_command <= CMD_NONE;
            clear_data_len <= 1'b0;
            c_btn_prev   <= 1'b0;
            c_timer      <= 12'd0;
        end else begin
            c_btn_prev  <= c_btn;
            valid_pulse <= 1'b0; // Default pulse state
            command_out <= CMD_NONE;
            clear_data_len <= 1'b0;

            case (c_state)
                C_IDLE: begin
                    if (c_btn && !c_btn_prev) begin // Rising edge
                        c_timer <= 12'd0;
                        c_state <= C_PRESS;
                    end
                end

                C_PRESS: begin
                    if (tick_1ms) c_timer <= c_timer + 12'd1;
                    
                    if (c_timer >= LONG_PRESS_MS) begin // Long Press
                        command_out <= CMD_CLEAR;
                        valid_pulse <= 1'b1;
                        valid_seen  <= 1'b0;
                        last_command <= CMD_CLEAR;
                        clear_data_len <= 1'b1;
                        click_count <= 2'd0;
                        c_state     <= C_IDLE;
                    end else if (!c_btn) begin // Released
                        click_count <= click_count + 2'd1;
                        c_timer     <= 12'd0;
                        c_state     <= C_WAIT;
                    end
                end

                C_WAIT: begin
                    if (tick_1ms) c_timer <= c_timer + 12'd1;
                    
                    if (c_btn && !c_btn_prev) begin // Clicked again
                        c_state <= C_PRESS;
                        c_timer <= 12'd0;
                    end else if (c_timer > CLICK_GAP_MS) begin // Gap Timeout
                        valid_pulse <= 1'b1;
                        valid_seen  <= 1'b1;
                        case (click_count)
                            2'd1: begin
                                command_out  <= CMD_CHAR;
                                last_command <= CMD_CHAR;
                            end
                            2'd2: begin
                                command_out  <= CMD_WORD;
                                last_command <= CMD_WORD;
                            end
                            2'd3: begin
                                command_out  <= CMD_MSG;
                                last_command <= CMD_MSG;
                            end
                            default: begin
                                command_out  <= CMD_NONE;
                                last_command <= CMD_NONE;
                            end
                        endcase
                        
                        click_count <= 2'd0;
                        // Reset internal buffer if a character was just finalized
                        if (click_count == 2'd1) clear_data_len <= 1'b1; 
                        
                        c_state <= C_IDLE;
                    end
                end
                
                default: c_state <= C_IDLE;
            endcase
        end
    end

    function automatic logic [7:0] seven_seg(input logic [3:0] value);
        case (value)
            4'h0: seven_seg = 8'b1100_0000;
            4'h1: seven_seg = 8'b1111_1001;
            4'h2: seven_seg = 8'b1010_0100;
            4'h3: seven_seg = 8'b1011_0000;
            4'h4: seven_seg = 8'b1001_1001;
            4'h5: seven_seg = 8'b1001_0010;
            4'h6: seven_seg = 8'b1000_0010;
            4'h7: seven_seg = 8'b1111_1000;
            4'h8: seven_seg = 8'b1000_0000;
            4'h9: seven_seg = 8'b1001_0000;
            default: seven_seg = 8'b1111_1111;
        endcase
    endfunction
endmodule

// --- DEBOUNCE MODULE ---
module debounce #(
    parameter int DEBOUNCE_MS = 20
) (
    input  logic clk,
    input  logic btn_in,
    input  logic tick,
    output logic btn_out
);
    logic [1:0] sync;
    logic [4:0] count; 

    always_ff @(posedge clk) begin
        sync <= {sync[0], btn_in}; // 2-stage synchronizer
        
        if (tick) begin
            if (sync[1] == btn_out) begin
                count <= 5'd0;
            end else begin
                count <= count + 5'd1;
                if (count == DEBOUNCE_MS) begin
                    btn_out <= sync[1];
                end
            end
        end
    end
endmodule
