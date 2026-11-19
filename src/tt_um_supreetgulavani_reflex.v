/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */
/**************************************************************
* Filename: tt_um_supreetgulavani_reflex.sv
* Description: Tiny Tapeout top level
* Pin map
*   ui_in[0]   TCK   host clock
*   ui_in[1]   TMS   host frame select (active low)
*   ui_in[2]   TDI   host data in
*   ui_in[7:3] in[4:0]   protocol inputs
*   uo_out[0]  TDO   host data out
*   uo_out[1]  EVT   event flag to host
*   uo_out[2]  ERROR any sticky error
*   uo_out[7:3] out[4:0] protocol outputs
*   uio[7:0]   8 bidirectional channels, push-pull or open-drain
*
* Open drain is enforced here in hardware: an open-drain channel's output
* value is forced to 0 so the pad can only pull low or float.
*
* Author: Supreet Gulavani (sgsupreetgulavani@gmail.com)
* Revision Date: 11/19/2026
**************************************************************/

`default_nettype none


module tt_um_supreetgulavani_reflex (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

wire        tdo, evt, err_any;
wire [12:0] out_val;
wire [7:0]  out_oe;
wire [7:0]  cfg_od;

reflex_core u_core (
	.clk    (clk),
	.rst_n  (rst_n),
	.tck    (ui_in[0]),
	.tms    (ui_in[1]),
	.tdi    (ui_in[2]),
	.tdo    (tdo),
	.evt    (evt),
	.err_any(err_any),
	.pins_in({ui_in[7:3], uio_in}),
	.out_val(out_val),
	.out_oe (out_oe),
	.cfg_od (cfg_od)
);

assign uo_out  = {out_val[12:8], err_any, evt, tdo};
assign uio_out = out_val[7:0] & ~cfg_od;
assign uio_oe  = out_oe;

wire _unused = &{ena, 1'b0};

endmodule
