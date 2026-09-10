module  DPWM_modu_test(
    input  logic clk, rst_n, mode, EN, controlRaiseOrReduce,
    input  logic [9:0] sel, select_which_D,
    output logic duty_ansys
);
    logic [9:0] D_wire, seleSignal_wire;
    logic adderSignal_wire, subtractorSignal_wire, dutyForMos_wire;
    logic baseSignal_wire, immediateSignal_wire, immediateStart_wire;

    tenKindOfClk      u_clk (
			 .D(D_wire),
			 .clk(clk),
			 .rst_n(rst_n)
	 );

    selectDuty        u_duty(
			 .sel(sel),
			 .D(D_wire),
			 .seleSignal(seleSignal_wire),
			 .baseSignal(baseSignal_wire)
	 );

    orGateAdder       u_or  (
			 .seleSignal(seleSignal_wire),
			 .adderSignal(adderSignal_wire)
	 );

    andGateSubtractor u_and (
			 .sel(sel),
			 .seleSignal(seleSignal_wire),
			 .subtractorSignal(subtractorSignal_wire)
	 );

    assign dutyForMos_wire = mode ? subtractorSignal_wire : adderSignal_wire;

	 immediate_react_pulse  u_pulse(
			 .clk(clk), .rst_n(rst_n),
			 .EN(EN),
			 .controlRaiseOrReduce(controlRaiseOrReduce),
			 .dutyForMos(dutyForMos_wire),
			 .D_immediate(D_wire),
			 .select_which_D(select_which_D),
			 .immediateStart(immediateStart_wire),
			 .duty_ansys(immediateSignal_wire)
	 );

    dutyLatch         u_latch(
			 .clk(clk), .rst_n(rst_n),
			 .baseSignal(baseSignal_wire),
			 .immediateStart(immediateStart_wire),
			 .r_sel(immediateSignal_wire),
			 .dutyForMos(duty_ansys)
    );
endmodule

module tenKindOfClk(
	input logic clk,
	input logic rst_n,
	output logic [9:0] D
);
	logic [9:0]clk_counter;

	always_ff@(posedge clk or negedge rst_n)
		if(!rst_n) clk_counter <= '0;
		else clk_counter <= clk_counter + 1'b1;

	// 每條 divider 都先 high，OR 的第一段寬度才會相加
	assign D = ~clk_counter;
endmodule

//============================================================
// 遮罩：sel[i]=1 放行 D[i]；最高選取位元決定基頻
//============================================================
module  selectDuty(
	input logic [9:0] sel,
	input logic [9:0] D,
	output logic [9:0] seleSignal,
	output logic baseSignal
);
	logic [9:0] base_sel;

	assign seleSignal = D & sel;

	// 只保留最高選取位元，給 latch 判斷下一個基頻週期
	// 固定 shift 在 elaboration 展開成接線，不是可變位移器
	generate
		for(genvar i=0; i<10; i=i+1) begin : base_mask
			assign base_sel[i] = sel[i] & ~(|(sel >> (i+1)));
		end
	endgenerate

	assign baseSignal = |(D & base_sel);
endmodule

module orGateAdder(
	input logic [9:0] seleSignal,
	output logic adderSignal
);
	assign adderSignal = |seleSignal;
endmodule

module andGateSubtractor(
	input logic [9:0] sel,
	input logic [9:0] seleSignal,
	output logic subtractorSignal
);
	// 未選取的位元填 1；全部未選取時輸出 0
	assign subtractorSignal = (|sel) & (&(seleSignal | ~sel));
endmodule

//============================================================
// 每個基頻週期只保留第一段 high
// 基頻上升或新的 EN 開放；合成結果 low 後保持 low
//============================================================
module dutyLatch(
    input  logic clk, rst_n,
    input  logic baseSignal,
    input  logic immediateStart,
    input  logic r_sel,
    output logic dutyForMos
);
    logic base_prev;

    always_ff@(posedge clk or negedge rst_n)
        if(!rst_n) base_prev <= 1'b0;
        else       base_prev <= baseSignal;

    // 刻意使用 latch：開放結束後，r_sel 再變 high 不會重新輸出
    always_latch begin
        if(!rst_n)                                  dutyForMos = 1'b0;
        else if((baseSignal && !base_prev) || immediateStart)
                                                    dutyForMos = r_sel;
        else if(!r_sel)                             dutyForMos = 1'b0;
    end
endmodule

module immediate_react_pulse(
    input  logic       clk, rst_n,
    input  logic       EN,
    input  logic       controlRaiseOrReduce,
    input  logic       dutyForMos,
    input  logic [9:0] D_immediate,
    input  logic [9:0] select_which_D,
    output logic       immediateStart,
    output logic       duty_ansys
);
    logic immediate_bit;
    logic EN_prev;

    // controller 在下一個 clk 更新 sel，之後只由 selectDuty 接手
    // EN 保持 high 不重複觸發；新的 EN 前需先取樣到 low
    always_ff@(posedge clk or negedge rst_n)
        if(!rst_n) EN_prev <= 1'b0;
        else       EN_prev <= EN;

    assign immediateStart = rst_n && EN && !EN_prev;
    assign immediate_bit = |(D_immediate & select_which_D);

    always_comb begin
        if(!immediateStart)           duty_ansys = dutyForMos;
        else if(controlRaiseOrReduce) duty_ansys = dutyForMos | immediate_bit;
        else                          duty_ansys = dutyForMos & ~immediate_bit;
    end
endmodule
