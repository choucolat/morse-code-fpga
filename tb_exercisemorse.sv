`timescale 1us/1ns

module tb_exercisemorse;
    logic clk;
    logic [1:0] key;
    logic [9:0] sw;
    wire [9:0] arduino_io;
    wire [9:0] ledr;
    wire [7:0] hex0;
    wire [7:0] hex1;
    wire [7:0] hex2;
    wire [7:0] hex3;
    wire [7:0] hex4;
    wire [11:0] decoded_symbol;

    Exercisemorse #(
        .CLK_FREQ_HZ(1_000_000),
        .DEBOUNCE_MS(2),
        .DOT_DASH_MS(10),
        .LONG_PRESS_MS(30),
        .CLICK_GAP_MS(10)
    ) dut (
        .MAX10_CLK1_50(clk),
        .KEY(key),
        .ARDUINO_IO(arduino_io),
        .LEDR(ledr),
        .SW(sw),
        .HEX0(hex0),
        .HEX1(hex1),
        .HEX2(hex2),
        .HEX3(hex3),
        .HEX4(hex4),
        .decoded_symbol(decoded_symbol)
    );

    initial clk = 1'b0;
    always #0.5 clk = ~clk;

    task automatic press_signal(input int hold_ms);
        begin
            key[0] = 1'b0;
            #(hold_ms * 1000);
            key[0] = 1'b1;
            #5000;
        end
    endtask

    task automatic click_control;
        begin
            key[1] = 1'b0;
            #5000;
            key[1] = 1'b1;
            #5000;
        end
    endtask

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_exercisemorse);

        key = 2'b11;
        sw = 10'b0;

        #5000;
        sw[9] = 1'b1;
        #5000;

        // Simulate A: dot, dash, then one control click to finish a character.
        press_signal(5);
        press_signal(15);
        click_control();

        #20000;
        $finish;
    end
endmodule
