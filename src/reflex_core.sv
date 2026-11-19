/**************************************************************
* Filename: reflex_core.sv
* Description: REFLEX engine without tinytapeout pin wrapper
* 
*
* Author: Supreet Gulavani (sgsupreetgulavani@gmail.com)
* Revision Date: 11/19/2026
**************************************************************/

`default_nettype none

module reflex_core(
  	input  logic            clk,
    input  logic            rst_n,

    input  logic            tck,
    input  logic            tms,
    input  logic            tdi,
    output logic            tdo,
    output logic            evt,
    output logic            err_any,

    input  logic    [12:0]  pins_in,      // {in[4:0], uio[7:0]}
    output logic    [12:0]  out_val,      // {out[4:0], uio[7:0]}
    output logic    [7:0]   out_oe,
    output logic    [7:0]   cfg_od
);

// host <-> engine
logic        run, init, step, go_evt, srst;
logic [7:0]  cfg_init_oe, cfg_match, cfg_mask;
logic [12:0] cfg_init_val;
logic        cfg_msb_first;
logic        h_mem_wen, h_mem_ren;
logic [7:0]  h_mem_addr;
logic [63:0] h_mem_din;
logic        const_we;
logic [3:0]  const_addr;
logic [15:0] const_wdata, const_rdata;
logic        tx_push, rx_pop;
logic [7:0]  tx_wdata;
logic [8:0]  rx_rdata;

// sequencer
logic [5:0]  state, nxt_state;
logic [1:0]  phase;
logic        active, armed, exec;
logic        fetch_ren;
logic [7:0]  fetch_addr;
logic [3:0]  cache_we;

// memory
logic        mem_ren, mem_wen;
logic [7:0]  mem_addr;
logic [63:0] mem_dout;

// rules
logic        fire;
logic [1:0]  fire_idx;
logic [63:15] act;
logic [12:0] snap;

// io
logic [12:0] pin_sync;
logic [28:0] seen;
logic        overrun;

// timers
logic [15:0] now, meas;
logic [7:0]  cval_lo;
logic [1:0]  tmr_evt, tmr_clr;
logic        run_a, run_b;

// data
logic        bit_pre, bit_post, bit_smp, alt;
logic        cntz, mtch, txne;
logic [7:0]  sr, cnt;
logic        tx_empty, tx_full, rx_empty, rx_full;
logic        err_tx_ovf, err_tx_unf, err_rx_ovf;

// ------------------------------------------------- action field decode
logic [3:0] a_p1_ch, a_p2_ch, a_smp_src, a_tmr_op, a_const_idx;
logic [2:0] a_p1_op, a_p2_op, a_data_op;
logic [1:0] a_cnt_op, a_alt_cond;
logic [5:0] a_next, a_next_alt;
logic       a_f_event, a_f_error, a_f_halt, a_f_alt_only;

assign a_p1_ch      = act[18:15];
assign a_p1_op      = act[21:19];
assign a_p2_ch      = act[25:22];
assign a_p2_op      = act[28:26];
assign a_data_op    = act[31:29];
assign a_smp_src    = act[35:32];
assign a_cnt_op     = act[37:36];
assign a_tmr_op     = act[41:38];
assign a_const_idx  = act[45:42];
assign a_next       = act[51:46];
assign a_next_alt   = act[57:52];
assign a_alt_cond   = act[59:58];
assign a_f_event    = act[60];
assign a_f_error    = act[61];
assign a_f_halt     = act[62];
assign a_f_alt_only = act[63];

assign nxt_state = alt ? a_next_alt : a_next;

logic flags_en, evt_set, err_rule, halt_req;
assign flags_en = exec & (alt | ~a_f_alt_only);
assign evt_set  = flags_en & a_f_event;
assign err_rule = flags_en & a_f_error;
assign halt_req = flags_en & a_f_halt;

// ------------------------------------------------------ rule memory port
assign mem_wen  = h_mem_wen;
assign mem_ren  = h_mem_ren | fetch_ren;
assign mem_addr = (h_mem_wen | h_mem_ren) ? h_mem_addr : fetch_addr;

reflex_mem u_mem (
	.clk (clk),
	.ren (mem_ren),
	.wen (mem_wen),
	.addr(mem_addr),
	.din (h_mem_din),
	.dout(mem_dout)
);

`ifdef FORMAL_NO_HOST
// Proof builds cut the host port out: every signal it drives may take any
// value in any cycle. What is proven then holds for every possible host.
(* anyseq *) logic [191:0] f_host;
assign {tdo, evt, err_any, run, init, step, go_evt, srst, cfg_od, cfg_init_oe,
		cfg_init_val, cfg_msb_first, cfg_match, cfg_mask, h_mem_wen, h_mem_ren,
		h_mem_addr, h_mem_din, const_we, const_addr, const_wdata, tx_push, tx_wdata,
		rx_pop} = f_host[158:0];
logic _unused_host;
assign _unused_host = &{1'b0, tck, tms, tdi, halt_req, evt_set, err_rule, overrun,
						const_rdata, rx_rdata, state, tx_full, rx_empty, rx_full, cnt,
						sr, now, err_tx_ovf, err_tx_unf, err_rx_ovf, f_host[191:159]};
`else
reflex_host u_host (
	.clk          (clk),
	.rst_n        (rst_n),
	.tck          (tck),
	.tms          (tms),
	.tdi          (tdi),
	.tdo          (tdo),
	.run          (run),
	.init         (init),
	.step         (step),
	.go_evt       (go_evt),
	.srst         (srst),
	.halt_req     (halt_req),
	.cfg_od       (cfg_od),
	.cfg_init_oe  (cfg_init_oe),
	.cfg_init_val (cfg_init_val),
	.cfg_msb_first(cfg_msb_first),
	.cfg_match    (cfg_match),
	.cfg_mask     (cfg_mask),
	.mem_wen      (h_mem_wen),
	.mem_ren      (h_mem_ren),
	.mem_addr     (h_mem_addr),
	.mem_din      (h_mem_din),
	.mem_dout     (mem_dout),
	.const_we     (const_we),
	.const_addr   (const_addr),
	.const_wdata  (const_wdata),
	.const_rdata  (const_rdata),
	.tx_push      (tx_push),
	.tx_wdata     (tx_wdata),
	.rx_pop       (rx_pop),
	.rx_rdata     (rx_rdata),
	.state        (state),
	.phase        (phase),
	.tx_empty     (tx_empty),
	.tx_full      (tx_full),
	.rx_empty     (rx_empty),
	.rx_full      (rx_full),
	.cnt          (cnt),
	.sr           (sr),
	.now          (now),
	.meas         (meas),
	.err_set      ({err_rx_ovf, err_tx_unf, err_tx_ovf, overrun, err_rule}),
	.evt_set      (evt_set),
	.evt          (evt),
	.err_any      (err_any)
);
`endif

reflex_seq u_seq (
	.clk       (clk),
	.rst_n     (rst_n),
	.run       (run),
	.init      (init),
	.step      (step),
	.fire      (fire),
	.nxt_state (nxt_state),
	.state     (state),
	.phase     (phase),
	.active    (active),
	.armed     (armed),
	.exec      (exec),
	.fetch_ren (fetch_ren),
	.fetch_addr(fetch_addr),
	.cache_we  (cache_we)
);

reflex_rules u_rules (
	.clk     (clk),
	.rst_n   (rst_n),
	.mem_dout(mem_dout),
	.cache_we(cache_we),
	.armed   (armed),
	.seen    (seen),
	.pin_sync   (pin_sync),
	.run_a   (run_a),
	.run_b   (run_b),
	.cntz    (cntz),
	.mtch    (mtch),
	.txne    (txne),
	.fire    (fire),
	.fire_idx(fire_idx),
	.act     (act),
	.snap    (snap)
`ifdef FORMAL
	,
	.f_cache0(f_cache0)
`endif
);

reflex_io u_io (
	.clk         (clk),
	.rst_n       (rst_n),
	.pins_in     (pins_in),
	.active      (active),
	.armed       (armed),
	.init        (init),
	.tmr_evt     (tmr_evt),
	.go_evt      (go_evt),
	.tmr_clr     (tmr_clr),
	.pin_sync       (pin_sync),
	.seen        (seen),
	.overrun     (overrun),
	.exec        (exec),
	.p1_ch       (a_p1_ch),
	.p1_op       (a_p1_op),
	.p2_ch       (a_p2_ch),
	.p2_op       (a_p2_op),
	.bit_pre     (bit_pre),
	.bit_post    (bit_post),
	.bit_smp     (bit_smp),
	.cfg_od      (cfg_od),
	.cfg_init_oe (cfg_init_oe),
	.cfg_init_val(cfg_init_val),
	.out_val     (out_val),
	.out_oe      (out_oe)
);

reflex_timer u_timer (
	.clk        (clk),
	.rst_n      (rst_n),
	.init       (init),
	.exec       (exec),
	.tmr_op     (a_tmr_op),
	.const_idx  (a_const_idx),
	.const_we   (const_we),
	.const_addr (const_addr),
	.const_wdata(const_wdata),
	.const_rdata(const_rdata),
	.cval_lo    (cval_lo),
	.tmr_evt    (tmr_evt),
	.tmr_clr    (tmr_clr),
	.run_a      (run_a),
	.run_b      (run_b),
	.now        (now),
	.meas       (meas)
);

reflex_data u_data (
	.clk          (clk),
	.rst_n        (rst_n),
	.init         (init),
	.srst         (srst),
	.exec         (exec),
	.data_op      (a_data_op),
	.smp_src      (a_smp_src),
	.cnt_op       (a_cnt_op),
	.alt_cond     (a_alt_cond),
	.snap         (snap),
	.cval         (cval_lo),
	.meas         (meas[7:0]),
	.cfg_msb_first(cfg_msb_first),
	.cfg_match    (cfg_match),
	.cfg_mask     (cfg_mask),
	.tx_push      (tx_push),
	.tx_wdata     (tx_wdata),
	.rx_pop       (rx_pop),
	.rx_rdata     (rx_rdata),
	.bit_pre      (bit_pre),
	.bit_post     (bit_post),
	.bit_smp      (bit_smp),
	.alt          (alt),
	.cntz         (cntz),
	.mtch         (mtch),
	.txne         (txne),
	.sr           (sr),
	.cnt          (cnt),
	.tx_empty     (tx_empty),
	.tx_full      (tx_full),
	.rx_empty     (rx_empty),
	.rx_full      (rx_full),
	.err_tx_ovf   (err_tx_ovf),
	.err_tx_unf   (err_tx_unf),
	.err_rx_ovf   (err_rx_ovf)
);

// fire_idx is only used inside reflex_rules; exported for debug/formal
logic _unused;
assign _unused = &{1'b0, fire_idx};

`ifdef FORMAL
logic [63:0] f_cache0;

// every proof starts from reset
initial assume (!rst_n);

// The proofs cut the host port out (formal/*.sby): run, init, step, go,
// FIFO traffic and memory writes are all free to do anything in any cycle.
// The one thing assumed about the host is that it does not rewrite the
// open-drain configuration while the engine is running.
logic [7:0] f_od_q;
always_ff @(posedge clk) begin
	f_od_q <= cfg_od;
	if (rst_n && f_age != 4'd0) assume (cfg_od == f_od_q);
end

// ===================================================================
// HEADLINE: fixed 4-cycle reaction, end to end, for ANY program.
//
// Rule memory contents are unconstrained, so this holds for every rule
// set. Take any input pin f_p and any output channel f_c. Whenever
//   - the engine is armed in cycle t,
//   - rule 0 of the current state is "on <pin f_p> rise: drive <f_c> 1"
//     (any other fields, any other rules),
//   - the pin was low at the clock edge 3 back and high at the edge 2 back
//     (that is: its rising edge was first sampled 2 edges ago),
// then two cycles later the output flop of channel f_c is high.
// Sampling edge + 3 more edges = 4 clock edges, never 3, never 5.
// The same is proven for "drive 0" and for a falling edge.
// ===================================================================
(* anyconst *) logic [3:0] f_p;
(* anyconst *) logic [3:0] f_c;
(* anyconst *) logic       f_fall;     // trigger on fall instead of rise
(* anyconst *) logic       f_low;      // drive 0 instead of 1

logic [3:0]  f_age;
logic [12:0] f_pin1, f_pin2, f_pin3;
always_ff @(posedge clk) begin
	if (!rst_n) f_age <= 4'd0;
	else if (f_age != 4'd15) f_age <= f_age + 4'd1;
	f_pin1 <= pins_in;
	f_pin2 <= f_pin1;
	f_pin3 <= f_pin2;
end

logic f_rule_ok, f_edge, f_trig;
assign f_rule_ok = (f_cache0[4:0] == 5'd16 + {1'b0, f_p})        // src = pin f_p
				&& (f_cache0[6:5] == {1'b0, f_fall})            // rise / fall
				&& !f_cache0[7] && (f_cache0[14:13] == 2'd0)    // no conditions
				&& (f_cache0[18:15] == f_c)                     // pin action 1
				&& (f_cache0[21:19] == (f_low ? 3'd1 : 3'd2))
				&& ((f_cache0[28:26] == 3'd0) || (f_cache0[25:22] != f_c));
assign f_edge = f_fall ? (!f_pin2[f_p] && f_pin3[f_p]) : (f_pin2[f_p] && !f_pin3[f_p]);
assign f_trig = rst_n && (f_age >= 4'd4) && armed && f_rule_ok && f_edge;

logic f_t1, f_t2, f_i1, f_i2;
logic f_val_t, f_oe_t, f_init_t;
always_ff @(posedge clk) begin
	f_val_t <= out_val[f_c];
	f_oe_t  <= out_oe[f_c[2:0]];
	f_init_t <= init;
	f_t1 <= f_trig;
	f_t2 <= f_t1 & rst_n;
	f_i1 <= init;                 // a host restart during the reaction voids it
	f_i2 <= f_i1 | init;
end

always_ff @(posedge clk) begin
	assume (f_p < 4'd13);
	assume (f_c < 4'd13);
	if (rst_n && f_t2 && !f_i2 && !f_i1) begin
	if (f_c >= 4'd8) begin
		assert (out_val[f_c] == !f_low);
	end else if (cfg_od[f_c[2:0]]) begin
		assert (out_oe[f_c[2:0]] == f_low);          // open drain: low or let go
	end else begin
		assert (out_oe[f_c[2:0]] && out_val[f_c] == !f_low);
	end
	end
	// the trigger above always fires rule 0
	if (f_trig) assert (fire && fire_idx == 2'd0);
	// ... and not one cycle sooner: in the cycle after the trigger the
	// channel still holds the value it had in the trigger cycle. Together
	// with the assertion above this pins the reaction to exactly 4 edges.
	if (rst_n && f_t1 && !f_init_t) begin
	if (f_c >= 4'd8) assert (out_val[f_c] == f_val_t);
	else             assert (out_oe[f_c[2:0]] == f_oe_t && out_val[f_c] == f_val_t);
	end
end

// Non-vacuity. Built only for the 'reach' task, which must FAIL: the solver
// has to produce a trace from reset in which the headline trigger really
// happens and its response is really checked. If this assertion could not
// be violated, the latency proof above would be proving nothing.
`ifdef FORMAL_REACH
always_ff @(posedge clk) begin
	assert (!(rst_n && f_t2 && !f_i2 && !f_i1));
end
`endif
`endif

endmodule