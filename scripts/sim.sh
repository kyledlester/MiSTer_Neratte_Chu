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
CORE="rtl/nrc/nrc_clocks.sv rtl/nrc/nrc_video_timing.sv rtl/nrc/nrc_sdram_arb.sv rtl/nrc/nrc_loader.sv rtl/nrc/nrc_cpu.sv rtl/nrc/nrc_irq.sv rtl/nrc/nrc_inputs.sv rtl/nrc/nrc_spriteram.sv rtl/nrc/nrc_palette.sv rtl/nrc/nrc_sound.sv rtl/nrc/nrc_st0016.sv rtl/nrc/nrc_render.sv rtl/nrc/nrc_framebuffer.sv rtl/nrc/nrc_overlay.sv"

# test -> "top vhdl-files sv-files"
spec() {
  case "$1" in
    m0)  echo "m0_timing_tb|| rtl/nrc/nrc_clocks.sv rtl/nrc/nrc_video_timing.sv sim/tb/m0_timing_tb.sv" ;;
    m2)  echo "m2_loader_tb|| rtl/nrc/nrc_sdram_arb.sv rtl/nrc/nrc_loader.sv build/sim/sdram_sim.sv sim/models/sdr_sdram_model.sv sim/tb/m2_loader_tb.sv" ;;
    m3)  echo "m3_cpu_tb|$T80| $CORE rtl/nrc/nrc_core.sv sim/tb/m3_cpu_tb.sv" ;;
    m6)  echo "m6_system_tb|$T80| $CORE rtl/nrc/nrc_core.sv sim/tb/m6_system_tb.sv" ;;
    m9)  echo "m9_video_tb|$T80| $CORE rtl/nrc/nrc_core.sv sim/tb/m9_video_tb.sv" ;;
    m8)  echo "m8_palette_tb|| rtl/nrc/nrc_palette.sv sim/tb/m8_palette_tb.sv" ;;
    m10) echo "m10_render_tb|| rtl/nrc/nrc_render.sv rtl/nrc/nrc_framebuffer.sv rtl/nrc/nrc_spriteram.sv sim/tb/m10_render_tb.sv" ;;
    m15) echo "m15_sound_tb|| rtl/nrc/nrc_sound.sv sim/tb/m15_sound_tb.sv" ;;
    *) echo "" ;;
  esac
}

# ModelSim 10.5b rejects a few idioms of the vendored sdram.sv (see rtl/vendor/README.md);
# simulate a mechanically edited copy.
mk_sdram_sim() {
  python scripts/mk_sdram_sim.py build/sim/sdram_sim.sv
}

run() {
  t=$1; shift
  s=$(spec "$t")
  [ -z "$s" ] && { echo "unknown test $t"; return 2; }
  top=${s%%|*}; rest=${s#*|}; vhd=${rest%%|*}; sv=${rest#*|}
  lib=build/sim/lib_$t
  rm -rf "$lib"; "$MS/vlib.exe" "$lib" >/dev/null
  mk_sdram_sim
  log=build/sim/$t.log
  : > "$log"
  if [ -n "$vhd" ]; then "$MS/vcom.exe" -2008 -quiet -work "$lib" $vhd >> "$log" 2>&1 || { echo "FAIL $t: vcom (see $log)"; tail -20 "$log"; return 1; }; fi
  "$MS/vlog.exe" -sv -quiet -work "$lib" ${VLOGDEFS:-} +incdir+sim/tb $sv >> "$log" 2>&1 || { echo "FAIL $t: vlog (see $log)"; grep -E "Error|error" "$log" | head -20; return 1; }
  "$MS/vsim.exe" -c -L altera_mf_ver -L altera_ver -lib "$lib" "$top" "$@" -do 'run -all; quit -f' >> "$log" 2>&1
  r=$(grep -E "^# (PASS|FAIL) " "$log" | tail -1 | sed 's/^# //')
  if [ -z "$r" ]; then echo "FAIL $t: no verdict (see $log)"; grep -E "Error|Fatal" "$log" | head -10; return 1; fi
  echo "$r"
  case "$r" in PASS*) return 0 ;; *) return 1 ;; esac
}

# m10: RTL renderer vs golden model on MAME dumps (NRC_DUMP dir, frames NRC_FRAMES)
m10() {
  d=${NRC_DUMP:-C:/Users/klest/NRC_research/cap/dump1}
  fails=0
  for f in ${NRC_FRAMES:-2600}; do
    cha=$(python -c "import sys; sys.path.insert(0,'scripts/research'); import st0016_ref as r; print(r.find_cha('$d',$f))")
    run m10 "+SPR=$d/f${f}_spr.bin" "+VREG=$d/f${f}_vreg.bin" "+CHA=$cha" "+OUT=build/sim/m10_f$f.bin" >/dev/null || { echo "FAIL M10 frame $f: sim"; fails=$((fails+1)); continue; }
    grep "RENDER STATS" build/sim/m10.log | sed 's/^# //'
    r=$(python scripts/research/st0016_ref.py "$d" "$f" --cha "$cha" --cmpidx "build/sim/m10_f$f.bin" | tail -1)
    echo "frame $f: $r"
    case "$r" in *PASS*) ;; *) fails=$((fails+1)) ;; esac
  done
  if [ $fails = 0 ]; then echo "PASS M10 RENDER: frames ${NRC_FRAMES:-2600}"; else echo "FAIL M10 RENDER: $fails frame(s)"; fi
  return $fails
}

# m3: RTL write stream vs MAME boot write stream (NRC_MAXW writes; NRC_TURBO=1 for a 3x CPU)
m3() {
  ext=${NRC_EXTROM:-C:/Users/klest/NRC_research/romx/extrom.bin}
  ref=${NRC_WREF:-C:/Users/klest/NRC_research/cap/writes_boot.txt}
  VLOGDEFS=""; [ "${NRC_TURBO:-0}" = 1 ] && VLOGDEFS="+define+TURBO"
  run m3 "+EXTROM=$ext" "+LOG=build/sim/m3_writes.txt" "+MAXW=${NRC_MAXW:-20000}" "+FRAMES=${NRC_SIMFRAMES:-0}" || return 1
  python scripts/research/cmp_writes.py "$ref" build/sim/m3_writes.txt
}

# m15: RTL sound engine vs the Python MAME-master model on a captured in-game register stream
m15() {
  c=C:/Users/klest/NRC_research/cap
  n=${NRC_SAMPLES:-20000}
  run m15 "+CHA=$c/dump2/f2300_cha.bin" "+STIM=$c/snd_2300.stim" "+N=$n" "+OUT=build/sim/m15_rtl.txt" >/dev/null || { echo "FAIL M15 SOUND: sim"; return 1; }
  python scripts/research/st0016_snd_ref.py run $c/dump2/f2300_cha.bin $c/snd_2300.stim $n build/sim/m15_model.txt
  python scripts/research/st0016_snd_ref.py cmp build/sim/m15_model.txt build/sim/m15_rtl.txt
}

if [ "${1:-}" = m10 ]; then m10; exit $?; fi
if [ "${1:-}" = m15 ]; then m15; exit $?; fi
if [ "${1:-}" = m3 ]; then m3; exit $?; fi
if [ "${1:-}" = all ]; then
  fails=0
  for t in m0 m2 m8 m9; do run "$t" || fails=$((fails+1)); done
  m15 || fails=$((fails+1))
  m3 || fails=$((fails+1))
  m10 || fails=$((fails+1))
  NRC_DUMP=C:/Users/klest/NRC_research/cap/svc NRC_FRAMES=300 m10 || fails=$((fails+1))
  echo "REGRESSION: $fails failing"
  exit $fails
fi
run "$@"
