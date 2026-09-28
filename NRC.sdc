# Neratte Chu (ST-0016) MiSTer core -- core timing constraints (sys/sys_top.sdc covers the framework).
# One core clock: clk_sys = 100.227 MHz from rtl/nrc/nrc_pll.sv. Every other rate is a
# clock enable of clk_sys (rtl/nrc/nrc_clocks.sv).
derive_pll_clocks
derive_clock_uncertainty
