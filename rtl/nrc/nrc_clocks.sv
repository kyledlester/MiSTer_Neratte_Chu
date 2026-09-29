// Neratte Chu (Seta ST-0016) MiSTer core -- clock enables.
// SPDX-License-Identifier: GPL-3.0-or-later
//
// clk_sys = 2205/22 MHz (100.227273 MHz, see nrc_pll.sv).
//   ce_pix : clk_sys / 14 = 7.159091 MHz, exact.
//   tick8  : nominal 8 MHz CPU time base = 48 MHz / 6 (MAME), fractional: 176/2205 of clk_sys.
//   ce_snd : tick8 / 128 = 62.5 kHz (MAME st0016 stream rate = clock / 128), from the
//            nominal time base so the sample rate never jitters with CPU stalls.
//   ce_cpu : the Z80 clock enable. One "credit" is earned per tick8; a credit is spent
//            by one ce_cpu pulse whenever the CPU is not stalled (SDRAM wait) and at least
//            MIN_GAP clk_sys cycles have passed since the previous pulse. A stalled CPU
//            therefore catches up afterwards, and over any window longer than a stall the
//            CPU executes exactly 8,000,000 T-states per second. [IMPLEMENTATION-DECISION]
//            Credits above CREDIT_MAX are dropped and counted (lost_credits) - that would
//            mean the CPU fell permanently behind real time; it is a diagnostic, expected 0.
module nrc_clocks #(
    parameter int MIN_GAP    = 3,
    parameter int CREDIT_MAX = 255,
    parameter int NUM        = 176,     // tick8 = NUM/DEN of clk_sys (simulation may speed up the CPU)
    parameter int DEN        = 2205
) (
    input  logic        clk,
    input  logic        rst,
    input  logic        cpu_stall,      // hold ce_cpu (SDRAM access pending)
    input  logic        turbo,          // simulation only: earn a CPU credit every clock (tie 0)
    output logic        ce_pix,
    output logic        tick8,
    output logic        ce_snd,
    output logic        ce_cpu,
    output logic  [7:0] credits,
    output logic [15:0] lost_credits
);

    logic [3:0]  pdiv;
    logic [11:0] acc;
    logic [6:0]  sdiv;
    logic [1:0]  gap;

    always_ff @(posedge clk) begin
        ce_pix <= 1'b0;
        tick8  <= 1'b0;
        ce_snd <= 1'b0;
        ce_cpu <= 1'b0;
        if (rst) begin
            pdiv <= '0; acc <= '0; sdiv <= '0; gap <= '0;
            credits <= '0; lost_credits <= '0;
        end else begin
            logic earn, spend;
            pdiv <= (pdiv == 4'd13) ? 4'd0 : pdiv + 4'd1;
            if (pdiv == 4'd13) ce_pix <= 1'b1;

            earn = 1'b0;
            if (turbo) begin
                earn = (credits < 8'd4);
            end else if (acc + NUM >= DEN) begin
                acc  <= acc + NUM - DEN;
                earn = 1'b1;
                tick8 <= 1'b1;
                sdiv <= sdiv + 7'd1;
                if (sdiv == 7'd127) ce_snd <= 1'b1;
            end else begin
                acc <= acc + NUM;
            end

            if (gap != 0) gap <= gap - 2'd1;
            spend = (credits != 0) && !cpu_stall && (gap == 0);
            if (spend) begin
                ce_cpu <= 1'b1;
                gap    <= 2'(MIN_GAP - 1);
            end
            case ({earn, spend})
                2'b10: if (credits == 8'(CREDIT_MAX)) lost_credits <= lost_credits + 16'd1;
                       else credits <= credits + 8'd1;
                2'b01: credits <= credits - 8'd1;
                default: ;
            endcase
        end
    end
endmodule
