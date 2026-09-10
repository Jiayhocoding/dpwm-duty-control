`timescale 1ns/1ps
module tb;
    logic clk, rst_n, mode, EN, controlRaiseOrReduce;
    logic [9:0] sel, select_which_D;
    logic duty_ansys;
    logic EN_prev;
    integer checks=0;
    integer high_count=0;

    DPWM_modu_test dut(.clk(clk), .rst_n(rst_n), .mode(mode),
        .EN(EN), .controlRaiseOrReduce(controlRaiseOrReduce),
        .sel(sel), .select_which_D(select_which_D), .duty_ansys(duty_ansys));

    always #5 clk = ~clk;
    initial begin $dumpfile("wave.vcd"); $dumpvars(0, tb); end

    wire [9:0] D = dut.D_wire;
    wire [9:0] count = dut.u_clk.clk_counter;
    wire D5 = D[5];
    wire D2 = D[2];
    wire raw_or = D5 | D2;

    // 模擬 controller：EN 後第一個 clk 將 D2 加入 selectDuty 的 sel
    always_ff@(posedge clk or negedge rst_n)
        if(!rst_n) begin
            EN_prev <= 1'b0;
            sel     <= 10'b0000100000;
        end else begin
            EN_prev <= EN;
            if(EN && !EN_prev) sel <= sel | select_which_D;
        end

    task automatic check(input logic expected, input string message);
        if(duty_ansys !== expected)
            $fatal(1, "%s: count=%0d expected=%b actual=%b", message, count, expected, duty_ansys);
        checks=checks+1;
    endtask

    task automatic at_count(input integer value);
        wait(count == value);
        #1;
    endtask

    initial begin
        clk=0; rst_n=0; mode=0; EN=0; controlRaiseOrReduce=1;
        select_which_D=10'b0000000100;
        #2; check(0, "reset");
        #10; rst_n=1;

        // 先觀察原本 D5 的 high / low
        at_count(1); check(1, "original D5 high");
        at_count(32); check(0, "original D5 low");

        // D5 low、D2 high 時 EN 非同步拉高，此後不再改動 EN
        at_count(40);
        #1; EN=1;
        #1; check(1, "immediate OR before next clk");
        if(sel !== 10'b0000100000) $fatal(1, "sel changed before controller clk");
        @(posedge clk); #1;
        if(sel !== 10'b0000100100) $fatal(1, "controller did not update sel");
        if(dut.immediateStart_wire !== 1'b0) $fatal(1, "immediate did not hand off");
        check(1, "selectDuty handoff without a gap");
        at_count(44); check(0, "immediate pulse first low");
        at_count(48); check(0, "block later D2 high");

        // 下一個完整週期開始：high 32+4=36 clk，low 28 clk
        at_count(64);
        repeat(4) begin
            high_count=0;
            for(integer n=0; n<64; n=n+1) begin
                check(n < 36, "D5 plus D2 width and no later pulses");
                if(duty_ansys) high_count=high_count+1;
                @(posedge clk); #1;
            end
            if(high_count != 36) $fatal(1, "pulse width is not 36 clk");
            $display("D5 period: high=%0d clk, low=%0d clk", high_count, 64-high_count);
        end

        if(EN !== 1'b1) $fatal(1, "EN must stay high");
        $display("PASS: %0d output checks", checks);
        $finish;
    end

    initial begin
        #20000;
        $fatal(1, "simulation timeout");
    end
endmodule
