// Neratte Chu (Seta ST-0016) MiSTer core -- system PLL.
// SPDX-License-Identifier: GPL-3.0-or-later
//
// One fractional-N PLL: 50 MHz board clock -> clk_sys = 100.227273 MHz.
//
// 100.227273 MHz = 42.954545 MHz x 7/3 = 14 x 7.159091 MHz. The ST-0016 PCB carries two
// crystals, 48 MHz (CPU: 48/6 = 8 MHz in MAME) and 42.9545 MHz (12 x NTSC colour burst).
// The game's own CRT register table (ROM $8020, written to ports $60-$7B) programs an
// H total of 455 and a V total of 262, i.e. NTSC 15.734 kHz / 60.05 Hz with a
// 42.9545/6 = 7.159 MHz dot clock. clk_sys is chosen so that the dot clock is an exact
// /14 enable (no pixel jitter on native/analog output); the 8 MHz CPU clock is a
// fractional (average-exact) enable. See docs/ARCHITECTURE.md section "Clocks".
//
// HIERARCHY IS LOAD-BEARING: sys/sys_top.sdc places the core clock in its own clock group
// only if it matches *|pll|pll_inst|altera_pll_i|*[*].*|divclk, so emu instantiates this
// module as "pll" (same shape as a MegaWizard MiSTer PLL; pattern taken from the owner's
// NB-1 core).
module nrc_pll (
    input  wire refclk,   // CLK_50M
    input  wire rst,
    output wire clk_sys,  // 100.227273 MHz
    output wire locked
);
    nrc_pll_core pll_inst (
        .refclk(refclk),
        .rst(rst),
        .clk_sys(clk_sys),
        .locked(locked)
    );
endmodule

module nrc_pll_core (
    input  wire refclk,
    input  wire rst,
    output wire clk_sys,
    output wire locked
);
    wire [0:0] clocks;

    altera_pll #(
        .fractional_vco_multiplier("true"),
        .reference_clock_frequency("50.0 MHz"),
        .operation_mode("direct"),
        .number_of_clocks(1),
        .output_clock_frequency0("100.227272 MHz"),
        .phase_shift0("0 ps"),
        .duty_cycle0(50),
        .pll_type("General"),
        .pll_subtype("General")
    ) altera_pll_i (
        .refclk(refclk),
        .rst(rst),
        .outclk(clocks),
        .locked(locked),
        .fboutclk(),
        .fbclk(1'b0)
    );

    assign clk_sys = clocks[0];
endmodule
