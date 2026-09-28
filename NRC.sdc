# Neratte Chu (ST-0016) MiSTer core -- core timing constraints (sys/sys_top.sdc covers the framework).
# One core clock: clk_sys = 100.227 MHz from rtl/nrc/nrc_pll.sv. Every other rate is a clock
# enable of clk_sys (rtl/nrc/nrc_clocks.sv).
derive_pll_clocks

# ---------------------------------------------------------------------------
# SDRAM pins (rtl/vendor/sdram.sv, clocked by clk_sys). Values as in the owner's hardware-proven
# NA-1 (100 MHz) and NB-1 cores. The controller launches address/command/write data on clk_sys's
# rising edge; altddio_out drives SDRAM_CLK as an inverted copy of clk_sys.
set nrc_core_clock_pin [get_pins -compatibility_mode {*|pll|pll_inst|altera_pll_i|*|divclk}]
create_generated_clock -name SDRAM_CLK -source $nrc_core_clock_pin \
    -divide_by 1 -invert [get_ports {SDRAM_CLK}]

set_input_delay -max -clock SDRAM_CLK 6.4 [get_ports {SDRAM_DQ[*]}]
set_input_delay -min -clock SDRAM_CLK 3.7 [get_ports {SDRAM_DQ[*]}]

# Read capture on the second clk_sys edge after the launching SDRAM_CLK edge (CL=2 data_ready_delay).
set_multicycle_path -setup 2 -from [get_clocks {SDRAM_CLK}] \
    -to [get_clocks {*|pll|pll_inst|altera_pll_i|*|divclk}]

set nrc_sdram_outputs [get_ports {
    SDRAM_A[*] SDRAM_BA[*]
    SDRAM_nCS SDRAM_nWE SDRAM_nRAS SDRAM_nCAS
    SDRAM_DQMH SDRAM_DQML SDRAM_DQ[*]
}]
set_output_delay -max -clock SDRAM_CLK 1.6 $nrc_sdram_outputs
set_output_delay -min -clock SDRAM_CLK -0.9 $nrc_sdram_outputs

# ---------------------------------------------------------------------------
# T80 kernel (rtl/vendor/t80 inside rtl/nrc/nrc_cpu.sv). Every T80 register is enabled by CEN =
# ce_cpu, and nrc_clocks never asserts ce_cpu on two edges closer than MIN_GAP = 3 clk_sys cycles
# (checked by sim/tb/m0_timing_tb.sv: "ce_cpu min gap"). T80 -> T80 paths therefore have 3 cycles.
# Paths into the kernel (DI, INT_n, NMI_n) and out of it (A, DO, strobes) stay single-cycle.
# If MIN_GAP changes in nrc_clocks.sv, change these numbers with it.
set nrc_t80 [get_keepers -nocase {*|nrc_cpu:cpu|T80:u0|*}]
set_multicycle_path -setup 3 -from $nrc_t80 -to $nrc_t80
set_multicycle_path -hold  2 -from $nrc_t80 -to $nrc_t80

derive_clock_uncertainty
