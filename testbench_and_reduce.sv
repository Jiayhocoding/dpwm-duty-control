`timescale 1ns/1ps
module tb_and_reduce;
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
    initial begin $dumpfile("wave_and_reduce.vcd"); $dumpvars(0, tb_and_reduce); end

    wire [9:0] D = dut.D_wire;
    wire [9:0] count = dut.u_clk.clk_counter;
    wire D5 = D[5];
    wire D2 = D[2];
    wire raw_and = D5 & D2;
    wire immediate_reduce = D5 & ~D2;

    // 模擬 controller：下一個 clk 將 D2 加入 AND 路徑的 sel
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
        clk=0; rst_n=0; mode=1; EN=0; controlRaiseOrReduce=0;
        select_which_D=10'b0000000100;
        #2; check(0, "reset");
        #10; rst_n=1;

        // AND 單選 D5，先觀察原本 high 32 clk / low 32 clk
        for(integer n=1; n<64; n=n+1) begin
            at_count(n);
            check(n < 32, "original D5 pulse");
        end

        // D5、D2 都 high 時觸發 reduce；EN 之後維持 high
        at_count(72); check(1, "high before immediate reduce");
        #1; EN=1;
        #1; check(0, "immediate AND NOT D2 before next clk");
        if(sel !== 10'b0000100000) $fatal(1, "sel changed before controller clk");
        @(posedge clk); #1;
        if(sel !== 10'b0000100100) $fatal(1, "controller did not update sel");
        if(dut.immediateStart_wire !== 1'b0) $fatal(1, "immediate did not hand off");
        check(0, "handoff must keep the ended pulse low");

        // 同一週期後面的 AND high 全部擋掉
        for(integer n=74; n<128; n=n+1) begin
            at_count(n);
            check(0, "latch blocks later AND pulses");
        end

        // D5 & D2 第一段 high 為 4 clk，不是 32-4 clk
        // 基頻仍為 D5：每 64 clk 只輸出 high 4 clk / low 60 clk
        at_count(128);
        repeat(4) begin
            high_count=0;
            for(integer n=0; n<64; n=n+1) begin
                check(n < 4, "AND reduced width and no later pulses");
                if(duty_ansys) high_count=high_count+1;
                @(posedge clk); #1;
            end
            if(high_count != 4) $fatal(1, "AND pulse width is not 4 clk");
            $display("D5 AND D2 period: high=%0d clk, low=%0d clk", high_count, 64-high_count);
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
