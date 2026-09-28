#!/bin/sh
# Neratte Chu core -- simulation runner (ModelSim-Intel FPGA Starter 10.5b, Quartus 17.0 install).
# Usage: scripts/sim.sh <test> [plusargs...]     e.g. scripts/sim.sh m0
#        scripts/sim.sh all                       run the regression list
# Each bench prints "PASS <NAME>: ..." or "FAIL <NAME>: ..."; the runner greps for it.
# Logs: build/sim/<test>.log
set -u
MS=${MODELSIM:-/c/intelFPGA_lite/17.0/modelsim_ase/win32aloem}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT" || exit 1
mkdir -p build/sim

T80="rtl/vendor/t80/T80_Pack.vhd rtl/vendor/t80/T80_ALU.vhd rtl/vendor/t80/T80_Reg.vhd rtl/vendor/t80/T80_MCode.vhd rtl/vendor/t80/T80.vhd"
CORE="rtl/nrc/nrc_clocks.sv rtl/nrc/nrc_video_timing.sv rtl/nrc/nrc_sdram_arb.sv rtl/nrc/nrc_loader.sv rtl/nrc/nrc_cpu.sv rtl/nrc/nrc_irq.sv rtl/nrc/nrc_inputs.sv rtl/nrc/nrc_spriteram.sv rtl/nrc/nrc_palette.sv rtl/nrc/nrc_sound.sv rtl/nrc/nrc_st0016.sv rtl/nrc/nrc_render.sv rtl/nrc/nrc_framebuffer.sv"

# test -> "top vhdl-files sv-files"
spec() {
  case "$1" in
    m0)  echo "m0_timing_tb|| rtl/nrc/nrc_clocks.sv rtl/nrc/nrc_video_timing.sv sim/tb/m0_timing_tb.sv" ;;
    m2)  echo "m2_loader_tb|| rtl/nrc/nrc_sdram_arb.sv rtl/nrc/nrc_loader.sv build/sim/sdram_sim.sv sim/models/sdr_sdram_model.sv sim/tb/m2_loader_tb.sv" ;;
    m3)  echo "m3_cpu_tb|$T80| $CORE sim/tb/m3_cpu_tb.sv" ;;
    m8)  echo "m8_palette_tb|| rtl/nrc/nrc_palette.sv sim/tb/m8_palette_tb.sv" ;;
    m10) echo "m10_render_tb|| rtl/nrc/nrc_render.sv rtl/nrc/nrc_framebuffer.sv rtl/nrc/nrc_spriteram.sv sim/tb/m10_render_tb.sv" ;;
    m15) echo "m15_sound_tb|| rtl/nrc/nrc_sound.sv sim/tb/m15_sound_tb.sv" ;;
    *) echo "" ;;
  esac
}

# ModelSim 10.5b rejects a few idioms of the vendored sdram.sv (see rtl/vendor/README.md);
# simulate a mechanically edited copy.
mk_sdram_sim() {
  sed -e 's/inout  reg \[15:0\] SDRAM_DQ/inout  wire [15:0] SDRAM_DQ/' rtl/vendor/sdram.sv > build/sim/sdram_sim.sv
}

run() {
  t=$1; shift
  s=$(spec "$t")
  [ -z "$s" ] && { echo "unknown test $t"; return 2; }
  top=${s%%|*}; rest=${s#*|}; vhd=${rest%%|*}; sv=${rest#*|}
  lib=build/sim/lib_$t
  rm -rf "$lib"; "$MS/vlib.exe" "$lib" >/dev/null
  [ "$t" = m2 ] && mk_sdram_sim
  log=build/sim/$t.log
  : > "$log"
  if [ -n "$vhd" ]; then "$MS/vcom.exe" -2008 -quiet -work "$lib" $vhd >> "$log" 2>&1 || { echo "FAIL $t: vcom (see $log)"; tail -20 "$log"; return 1; }; fi
  "$MS/vlog.exe" -sv -quiet -work "$lib" +incdir+sim/tb $sv >> "$log" 2>&1 || { echo "FAIL $t: vlog (see $log)"; grep -E "Error|error" "$log" | head -20; return 1; }
  "$MS/vsim.exe" -c -lib "$lib" "$top" "$@" -do 'run -all; quit -f' >> "$log" 2>&1
  r=$(grep -E "^# (PASS|FAIL) " "$log" | tail -1 | sed 's/^# //')
  if [ -z "$r" ]; then echo "FAIL $t: no verdict (see $log)"; grep -E "Error|Fatal" "$log" | head -10; return 1; fi
  echo "$r"
  case "$r" in PASS*) return 0 ;; *) return 1 ;; esac
}

if [ "${1:-}" = all ]; then
  fails=0
  for t in m0 m2 m3 m8 m10 m15; do run "$t" || fails=$((fails+1)); done
  echo "REGRESSION: $fails failing"
  exit $fails
fi
run "$@"
