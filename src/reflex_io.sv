/**************************************************************
* Filename: reflex_io.sv
* Description: Pin front end and back end
* 
*
* Author: Supreet Gulavani (sgsupreetgulavani@gmail.com)
* Revision Date: 11/17/2026
**************************************************************/

`default_nettype none

module reflex_io (
    input   logic           clk,
    input   logic           rst_n,

    input   logic   [12:0]  pins_in,

    input   logic           active,             // engine running 
    input   logic           armed,              // match enabler this cycle
    input   logic           init,               // program start/restart
    input   logic   [1:0]   tmr_evt,            // live timer expiry
    input   logic           go_evt,             // live host GO
    input   logic   [1:0]   tmr_clr,            // timer stopped/reloaded

    output  logic   [12:0]  pin_sync,          // synchronized pin level
    output  logic   [28:0]  seen,               // event visible to matcher
    output  logic           overrun,            // event was lost

    input   logic           exec,               // action cycle
    // pin actions of executing rule (ch, op)
    input   logic   [3:0]   p1_ch,
    input   logic   [2:0]   p1_op,
    input   logic   [3:0]   p2_ch,
    input   logic   [2:0]   p2_op,
    input   logic           bit_pre,            // data bit before data op
    input   logic           bit_post,           // data bit after data op
    input   logic           bit_smp,            // sampled bit

    input   logic   [7:0]   cfg_od,             // open drain set
    input   logic   [7:0]   cfg_init_oe,        // idle enables
    input   logic   [12:0]  cfg_init_val,       // idle values

    output  logic   [12:0]  out_val,            // o/p flops
    output  logic   [7:0]   out_oe              // o/p enable flops - bidirectional channel 
);

localparam logic [2:0] P_NONE = 0, P_LOW = 1, P_HIGH = 2, P_RELEASE = 3, P_TOGGLE = 4, P_DATA = 5, P_NEXT = 6, P_SAMPLE = 7;


// INPUTS
logic [12:0] s1, s2, prev;      // synchronizer stage s1, s2 (safe level), s2 one cycle ago
logic [28:0] pend, live;        // events

always_ff @(posedge clk) begin
    if(!rst_n) begin
        s1 <= 13'd0;
        s2 <= 13'd0;
        prev <= 13'd0;
    end else begin
        s1 <= pins_in;
        s2 <= s1;
        prev <= s2;
    end
end

assign pin_sync = s2;
assign live = {go_evt, tmr_evt, ~s2 & prev, s2 & ~prev};
assign seen = live | pend;

assign overrun = active & ~armed & (|(pend & live));

always_ff @(posedge clk) begin
    if(!rst_n) begin
        pend <= 29'd0;
    end else if (init || active || armed) begin
        pend <= 29'd0;
    end else begin
        pend <= (pend | live) &~{1'b0, tmr_clr, 26'd0};
    end
end


// OUTPUTS
logic p1_bit, p2_bit;
logic p1_en, p2_en;

always_comb begin
    p1_bit = 1'b0;
    case(p1_op)
        P_LOW:      
            p1_bit = 1'b0;
        P_HIGH:     
            p1_bit = 1'b1;
        P_DATA:     
            p1_bit = bit_pre;
        P_NEXT:     
            p1_bit = bit_post;
        P_SAMPLE:   
            p1_bit = bit_smp;
        default:    
            p1_bit = 1'b0;
    endcase
    p2_bit = 1'b0;
    case(p2_op)
        P_LOW:      
            p2_bit = 1'b0;
        P_HIGH:     
            p2_bit = 1'b1;
        P_DATA:     
            p2_bit = bit_pre;
        P_NEXT:     
            p2_bit = bit_post;
        P_SAMPLE:   
            p2_bit = bit_smp;
        default:    
            p2_bit = 1'b0;
    endcase
end
    
assign p2_en = exec && (p2_op != P_NONE);
// if both actions name same channel, action 2 wins
assign p1_en = exec && (p1_op != P_NONE) && !(p2_en && (p1_ch == p2_ch));

genvar c;   // channel number 
generate
    for(c = 0; c < 13; c++) begin 
        logic hit, hit1, hit2;
        logic [2:0] op;
        logic b;

        assign hit1 = p1_en && (p1_ch == c);
        assign hit2 = p2_en && (p2_ch == c);
        assign hit  = hit1 | hit2;  
        assign op   = hit2 ? p2_op : p1_op;
        assign b    = hit2 ? p2_bit : p1_bit;

        if (c < 8) begin : g_bidir
            always_ff @(posedge clk) begin
                if (!rst_n) begin
                    out_val[c] <= 1'b0;
                    out_oe[c]  <= 1'b0;
                end else if (init) begin
                    out_val[c] <= cfg_init_val[c];
                    out_oe[c]  <= cfg_init_oe[c];
                end else if (hit) begin
                    if (cfg_od[c]) begin
                        // open drain: the only choices are "pull low" and "let go"
                        case (op)
                            P_RELEASE: out_oe[c] <= 1'b0;
                            P_TOGGLE:  out_oe[c] <= ~out_oe[c];
                            default:   out_oe[c] <= ~b;
                        endcase
                    end else begin
                        case (op)
                            P_RELEASE: out_oe[c] <= 1'b0;
                            P_TOGGLE: begin
                                out_val[c] <= ~out_val[c];
                                out_oe[c]  <= 1'b1;
                            end
                            default: begin
                                out_val[c] <= b;
                                out_oe[c]  <= 1'b1;
                            end
                        endcase
                    end
                end
            end
        end else begin
            always_ff @(posedge clk) begin
                if (!rst_n) begin
                    out_val[c] <= 1'b0;
                end else if (init) begin
                    out_val[c] <= cfg_init_val[c];
                end else if (hit) begin
                    case (op)
                        P_RELEASE: out_val[c] <= out_val[c];
                        P_TOGGLE:  out_val[c] <= ~out_val[c];
                        default:   out_val[c] <= b;
                    endcase
                end
            end
        end
    end   
endgenerate

`ifdef FORMAL
  // ---- lemmas owned by this module (see formal/README.md) ----
    logic [3:0]  f_cnt;
    logic [12:0] f_in1, f_in2, f_in3;
    always_ff @(posedge clk) begin
        if (!rst_n) f_cnt <= 4'd0;
        else if (f_cnt != 4'd15) f_cnt <= f_cnt + 4'd1;
            f_in1 <= pins_in;
            f_in2 <= f_in1;
            f_in3 <= f_in2;
        end

    logic [28:0] f_seen_q;
    logic        f_hold_q;      // last cycle: active, not armed, no init
    logic [1:0]  f_clr_q;
    always_ff @(posedge clk) begin
        f_seen_q <= seen;
        f_hold_q <= rst_n & active & ~armed & ~init;            f_clr_q  <= tmr_clr;
    end

    always_ff @(posedge clk) begin
        if (rst_n && f_cnt >= 4'd3) begin
        // synchronizer is exactly two flops; edge detect uses the third
        assert (s2 == f_in2);
        assert (prev == f_in3);
        // what the matcher reads as a level is the synchronized value too
        assert (pin_s == f_in2);
        end
        if (rst_n && f_cnt >= 4'd1 && f_hold_q) begin
        // NO LOST EVENTS: anything visible in a cycle where the engine could
        // not act is still visible in the next cycle. (A timer event is
         // dropped only when that same timer is reloaded or stopped.)
        assert ((f_seen_q[25:0] & ~seen[25:0]) == 26'd0);
        assert (!(f_seen_q[26] && !f_clr_q[0]) || seen[26]);
        assert (!(f_seen_q[27] && !f_clr_q[1]) || seen[27]);
        assert (!f_seen_q[28] || seen[28]);
        end
    end

    // OPEN DRAIN / ACTION STAGE: one cycle after an action, the named channel
    // shows it. f_ch is an arbitrary channel chosen by the solver.
    (* anyconst *) logic [3:0] f_ch;
    logic       f_h1, f_h2, f_hit, f_b;
    logic [2:0] f_op;
    assign f_h1  = p1_en && (p1_ch == f_ch);
    assign f_h2  = p2_en && (p2_ch == f_ch);
    assign f_hit = (f_h1 | f_h2) && (f_ch < 4'd13);
    assign f_op  = f_h2 ? p2_op : p1_op;
    assign f_b   = f_h2 ? p2_bit : p1_bit;

    logic       f_act_q, f_od_q, f_oe_q, f_val_q;
    logic [2:0] f_op_q;
    logic       f_bit_q;
    always_ff @(posedge clk) begin
        f_act_q <= rst_n & ~init & f_hit;
        f_op_q  <= f_op;
        f_bit_q <= f_b;
        f_od_q  <= (f_ch < 4'd8) ? cfg_od[f_ch[2:0]] : 1'b0;
        f_oe_q  <= (f_ch < 4'd8) ? out_oe[f_ch[2:0]] : 1'b1;
        f_val_q <= out_val[f_ch];
    end
    always_ff @(posedge clk) begin
        assume (f_ch < 4'd13);
        if (rst_n && f_cnt >= 4'd1 && f_act_q) begin
            if (f_ch < 4'd8) begin
                if (f_od_q) begin
                    case (f_op_q)
                        P_RELEASE: assert (!out_oe[f_ch[2:0]]);
                        P_TOGGLE:  assert (out_oe[f_ch[2:0]] == !f_oe_q);
                        default:   assert (out_oe[f_ch[2:0]] == !f_bit_q);
                    endcase
                end else begin
                    case (f_op_q)
                        P_RELEASE: assert (!out_oe[f_ch[2:0]]);
                        P_TOGGLE:  assert (out_oe[f_ch[2:0]] && out_val[f_ch] == !f_val_q);
                        default:   assert (out_oe[f_ch[2:0]] && out_val[f_ch] == f_bit_q);
                    endcase
                end
            end else begin
                case (f_op_q)
                    P_RELEASE: assert (out_val[f_ch] == f_val_q);
                    P_TOGGLE:  assert (out_val[f_ch] == !f_val_q);
                    default:   assert (out_val[f_ch] == f_bit_q);
                endcase
            end
        end
        // RESET: the cycle after reset every output is released and low
        if (rst_n && f_cnt == 4'd0) begin
            assert (out_oe == 8'd0);
            assert (out_val == 13'd0);
            assert (pend == 29'd0);
        end
    end
`endif


endmodule