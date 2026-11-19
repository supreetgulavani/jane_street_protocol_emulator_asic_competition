/**************************************************************
* Filename: reflex_mem.sv
* Description:	Rule memory 256x64 bit synchronus read 
*  				The read data output is registered inside the memory (synchronous read) and
*				goes only into the rule cache flops, never towards a pin.
* 
*
* Author: Supreet Gulavani (sgsupreetgulavani@gmail.com)
* Revision Date: 11/19/2026
**************************************************************/

`default_nettype none

module reflex_mem (
    input  logic        clk,
    input  logic        ren,
    input  logic        wen,
    input  logic [7:0]  addr,
    input  logic [63:0] din,
    output logic [63:0] dout
);

// default build : behavioral memory (sim, formal, yosys area checks)
// REFLEX_USE_IHP_SRAM to instantiate the IHP macro
// RM_IHPSG13_1P_256x64_c2_bm_bist for hardening

`ifdef REFLEX_USE_IHP_SRAM

RM_IHPSG13_1P_256x64_c2_bm_bist u_sram (
	.A_CLK      (clk),
	.A_MEN      (ren | wen),
	.A_WEN      (wen),
	.A_REN      (ren & ~wen),
	.A_ADDR     (addr),
	.A_DIN      (din),
	.A_DLY      (1'b1),
	.A_DOUT     (dout),
	.A_BM       ({64{1'b1}}),
	.A_BIST_CLK (1'b0),
	.A_BIST_EN  (1'b0),
	.A_BIST_MEN (1'b0),
	.A_BIST_WEN (1'b0),
	.A_BIST_REN (1'b0),
	.A_BIST_ADDR(8'd0),
	.A_BIST_DIN (64'd0),
	.A_BIST_BM  (64'd0)
);

`elsif FORMAL

  // Proofs must hold for every possible program, so the memory is replaced
  // by "any 64-bit word on every read". Whatever is proven here is proven
  // for all rule memory contents at once.
  (* anyseq *) logic [63:0] f_any_word;
  always_ff @(posedge clk) begin
    if (ren && !wen) dout <= f_any_word;
  end
  logic _unused;
  assign _unused = &{1'b0, addr, din};

`else

  logic [63:0] mem[0:255];

  always_ff @(posedge clk) begin
    if (wen) begin
      mem[addr] <= din;
    end else if (ren) begin
      dout <= mem[addr];
    end
  end

`endif

endmodule
