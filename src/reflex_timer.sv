/**************************************************************
* Filename: reflex_timer.sv
* Description: Timer A, B, constant table, interval capture
* 
*
* Author: Supreet Gulavani (sgsupreetgulavani@gmail.com)
* Revision Date: 11/19/2026
**************************************************************/

`default_nettype none

module reflex_timer (
	input  logic        clk,
	input  logic        rst_n,

	input  logic        init,
	input  logic        exec,
	input  logic [3:0]  tmr_op,
	input  logic [3:0]  const_idx,

	// constant table, host side
	input  logic        const_we,
	input  logic [3:0]  const_addr,
	input  logic [15:0] const_wdata,
	output logic [15:0] const_rdata,

	output logic [7:0]  cval_lo,      // const[const_idx][7:0], for the data path
	output logic [1:0]  tmr_evt,      // {B, A} live expiry event
	output logic [1:0]  tmr_clr,      // {B, A} reloaded or stopped this cycle
	output logic        run_a,
	output logic        run_b,
	output logic [15:0] now,
	output logic [15:0] meas
);

localparam logic [3:0] T_A_CONST = 4'd1, T_B_CONST = 4'd2, T_A_MEAS = 4'd3, T_A_MEAS_HALF = 4'd4, T_A_MEAS_DBL = 4'd5, T_B_MEAS = 4'd6,
				T_B_MEAS_HALF = 4'd7, T_B_MEAS_DBL = 4'd8, T_CAPTURE = 4'd9, T_CAPTURE_A_CONST = 4'd10, T_CAPTURE_B_CONST = 4'd11,
				T_STOP_A = 4'd12, T_STOP_B = 4'd13;

logic [15:0] const_tab[0:15];
logic [15:0] t_a, t_b, stamp;

integer i;
always_ff @(posedge clk) begin
	if (!rst_n) begin
		for (i = 0; i < 16; i = i + 1) const_tab[i] <= 16'd0;
		end else if (const_we) begin
			const_tab[const_addr] <= const_wdata;
		end
end

logic [15:0] cval;
assign cval        = const_tab[const_idx];
assign cval_lo     = cval[7:0];
assign const_rdata = const_tab[const_addr];

// ------------------------------------------------------------ op decode
logic        ld_a, ld_b, stop_a, stop_b, capture;
logic [15:0] ld_val_a, ld_val_b;
logic [15:0] meas_dbl;

assign meas_dbl = meas[15] ? 16'hFFFF : {meas[14:0], 1'b0};

always_comb begin
	ld_a     = 1'b0;
	ld_b     = 1'b0;
	stop_a   = 1'b0;
	stop_b   = 1'b0;
	capture  = 1'b0;
	ld_val_a = cval;
	ld_val_b = cval;
	if (exec) begin
		case (tmr_op)
			T_A_CONST:         ld_a = 1'b1;
			T_B_CONST:         ld_b = 1'b1;
			T_A_MEAS:          begin ld_a = 1'b1; ld_val_a = meas; end
			T_A_MEAS_HALF:     begin ld_a = 1'b1; ld_val_a = {1'b0, meas[15:1]}; end
			T_A_MEAS_DBL:      begin ld_a = 1'b1; ld_val_a = meas_dbl; end
			T_B_MEAS:          begin ld_b = 1'b1; ld_val_b = meas; end
			T_B_MEAS_HALF:     begin ld_b = 1'b1; ld_val_b = {1'b0, meas[15:1]}; end
			T_B_MEAS_DBL:      begin ld_b = 1'b1; ld_val_b = meas_dbl; end
			T_CAPTURE:         capture = 1'b1;
			T_CAPTURE_A_CONST: begin capture = 1'b1; ld_a = 1'b1; end
			T_CAPTURE_B_CONST: begin capture = 1'b1; ld_b = 1'b1; end
			T_STOP_A:          stop_a = 1'b1;
			T_STOP_B:          stop_b = 1'b1;
			default: ;
		endcase
	end
end

logic low_a, low_b;
assign low_a   = (t_a <= 16'd2);
assign low_b   = (t_b <= 16'd2);
assign tmr_evt = {run_b & low_b, run_a & low_a};
assign tmr_clr = {ld_b | stop_b, ld_a | stop_a};

always_ff @(posedge clk) begin
	if (!rst_n) begin
		t_a   <= 16'd0;
		t_b   <= 16'd0;
		run_a <= 1'b0;
		run_b <= 1'b0;
		now   <= 16'd0;
		stamp <= 16'd0;
		meas  <= 16'd0;
	end else begin
		now <= now + 16'd1;
		if (capture) begin
			meas  <= now - stamp;
			stamp <= now;
		end

		if (ld_a) begin
			t_a   <= ld_val_a;
			run_a <= 1'b1;
		end else if (stop_a) begin
			run_a <= 1'b0;
		end else if (run_a) begin
			if (low_a) run_a <= 1'b0;
			else t_a <= t_a - 16'd1;
		end

		if (ld_b) begin
			t_b   <= ld_val_b;
			run_b <= 1'b1;
		end else if (stop_b) begin
			run_b <= 1'b0;
		end else if (run_b) begin
			if (low_b) run_b <= 1'b0;
			else t_b <= t_b - 16'd1;
		end

		if (init) begin
			run_a <= 1'b0;
			run_b <= 1'b0;
		end
	end
end

endmodule
