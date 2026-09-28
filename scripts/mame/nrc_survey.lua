-- Neratte Chu (nratechu) M1 survey: characterise how the game uses the ST-0016.
-- MAME 0.289. Output stays outside the repository (it contains ROM-derived data).
--
-- Env:
--   NRC_OUT     output directory (required, must exist)
--   NRC_FRAMES  frame at which to stop (default 1800)
--   NRC_COIN    frame at which to pulse COIN1 (default 0 = never)
--   NRC_START   frame at which to pulse START1 (default 0 = never)
--
-- Run:
--   mame.exe nratechu -rompath roms -cfg_directory <tmp> -nvram_directory <tmp>
--     -video none -sound none -nothrottle -skip_gameinfo
--     -autoboot_script scripts/mame/nrc_survey.lua
--
-- Produces in NRC_OUT:
--   io_w.txt     every I/O port write  "F<frame> L<vline> <pc> <port> <data>"
--   io_r.txt     first 64 reads of each I/O port, plus per-frame counts in summary
--   dma.txt      every character DMA: src dst len (bytes) + first/last dest
--   snd_w.txt    every sound register write ($E900-$E9FF)
--   mem_odd.txt  accesses to unmapped windows ($E880-$E8FF, $EC20-$EFFF)
--   summary.txt  per-frame counters: sprite/palette/charram/sound writes, NMI/IRQ,
--                sprite-write vline histogram (8 buckets of 48 lines)
--   charam.txt   final charram coverage map (which 4 KiB pages were ever written)
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["regs"]
local iosp = cpu.spaces["io"]
local cha = cpu.spaces["charam"]
local scr = M.screens[":screen"]
local fmt = string.format
local OUT = assert(os.getenv("NRC_OUT"), "NRC_OUT not set")
local END = tonumber(os.getenv("NRC_FRAMES") or "1800")
local COIN = tonumber(os.getenv("NRC_COIN") or "0")
local START = tonumber(os.getenv("NRC_START") or "0")

local function open(n) local f = io.open(OUT .. "/" .. n, "w"); f:setvbuf("full", 1 << 20); return f end
local iow, ior, dmaf, sndf, oddf, sumf = open("io_w.txt"), open("io_r.txt"), open("dma.txt"), open("snd_w.txt"), open("mem_odd.txt"), open("summary.txt")

local FRAME_T = 1.0 / 60.0
local LINE_T = FRAME_T / 384.0
local function vline()
  local rem = scr:time_until_pos(0, 0)
  local l = math.floor((FRAME_T - rem) / LINE_T + 0.5)
  if l >= 384 then l = l - 384 end
  return l
end
local function pc() return cpu.state["PC"].value end

local frame = 0
local c = {}
local function bump(k, n) c[k] = (c[k] or 0) + (n or 1) end
local vregs = {}
for i = 0, 255 do vregs[i] = 0 end
local rdseen = {}

-- I/O
TAP_IOW = iosp:install_write_tap(0x00, 0xff, "nrc_iow", function(offset, data, mask)
  local p = offset & 0xff
  vregs[p] = data
  iow:write(fmt("F%d L%d %04x %02x %02x\n", frame, vline(), pc(), p, data))
  bump("iow")
  if p == 0xa8 and (data & 0x20) ~= 0 then
    local src = (vregs[0xa0] | (vregs[0xa1] << 8) | (vregs[0xa2] << 16)) << 1
    local dst = (vregs[0xa3] | (vregs[0xa4] << 8) | (vregs[0xa5] << 16)) << 1
    local len = ((vregs[0xa6] | (vregs[0xa7] << 8) | ((data & 0x1f) << 16)) + 1) << 1
    dmaf:write(fmt("F%d L%d %04x src=%06x dst=%06x len=%06x dstend=%06x a8=%02x\n", frame, vline(), pc(), src, dst, len, dst + len - 1, data))
    bump("dma"); bump("dmabytes", len)
  end
end)
TAP_IOR = iosp:install_read_tap(0x00, 0xff, "nrc_ior", function(offset, data, mask)
  local p = offset & 0xff
  bump("ior" .. fmt("%02x", p))
  local n = rdseen[p] or 0
  if n < 64 then
    rdseen[p] = n + 1
    ior:write(fmt("F%d L%d %04x %02x %02x\n", frame, vline(), pc(), p, data))
  end
end)

-- memory
local sprhist = {}
TAP_SPR = mem:install_write_tap(0xc000, 0xdfff, "nrc_spr", function(offset, data, mask)
  bump("sprw")
  local b = vline() // 48
  sprhist[b] = (sprhist[b] or 0) + 1
end)
TAP_PAL = mem:install_write_tap(0xea00, 0xebff, "nrc_pal", function(offset, data, mask)
  bump("palw")
  local b = vline() // 48
  bump("palh" .. b)
end)
TAP_CHW = mem:install_write_tap(0xec00, 0xec1f, "nrc_chw", function(offset, data, mask) bump("chww") end)
TAP_CHR = mem:install_read_tap(0xec00, 0xec1f, "nrc_chr", function(offset, data, mask) bump("chwr") end)
TAP_SND = mem:install_write_tap(0xe900, 0xe9ff, "nrc_snd", function(offset, data, mask)
  sndf:write(fmt("F%d L%d %04x %02x %02x\n", frame, vline(), pc(), offset & 0xff, data))
  bump("sndw")
end)
TAP_SNDR = mem:install_read_tap(0xe900, 0xe9ff, "nrc_sndr", function(offset, data, mask) bump("sndr") end)
local function odd(rw)
  return function(offset, data, mask)
    bump("odd" .. rw)
    oddf:write(fmt("F%d L%d %04x %s %04x %02x\n", frame, vline(), pc(), rw, offset, data))
  end
end
TAP_ODDR1 = mem:install_read_tap(0xe880, 0xe8ff, "nrc_o1r", odd("r"))
TAP_ODDW1 = mem:install_write_tap(0xe880, 0xe8ff, "nrc_o1w", odd("w"))
TAP_ODDR2 = mem:install_read_tap(0xec20, 0xefff, "nrc_o2r", odd("r"))
TAP_ODDW2 = mem:install_write_tap(0xec20, 0xefff, "nrc_o2w", odd("w"))
TAP_BANKR = mem:install_read_tap(0x8000, 0xbfff, "nrc_bkr", function(offset, data, mask) bump("bankr") end)

-- charram coverage (all writers: DMA and CPU window)
local chpages = {}
TAP_CHA = cha:install_write_tap(0x000000, 0x1fffff, "nrc_cha", function(offset, data, mask)
  chpages[offset >> 12] = true
end)

-- interrupt entry: count fetches of the vectors
TAP_VEC = mem:install_read_tap(0x0038, 0x0038, "nrc_irq", function(offset, data, mask)
  if pc() == 0x38 then bump("irq") end
end)
TAP_NMI = mem:install_read_tap(0x0066, 0x0066, "nrc_nmi", function(offset, data, mask)
  if pc() == 0x66 then bump("nmi"); bump("nmiL" .. (vline())) end
end)

local fields = {"P1", "P2", "SYSTEM"}
local function press(port, mask, on)
  local p = M.ioport.ports[":" .. port]
  for _, f in pairs(p.fields) do
    if f.mask == mask then f:set_value(on and 1 or 0) end
  end
end

emu.register_frame_done(function()
  local keys = {}
  for k in pairs(c) do keys[#keys + 1] = k end
  table.sort(keys)
  local s = {}
  for _, k in ipairs(keys) do s[#s + 1] = k .. "=" .. c[k] end
  local h = {}
  for b = 0, 7 do h[#h + 1] = tostring(sprhist[b] or 0) end
  sumf:write(fmt("F%d %s sprhist=%s\n", frame, table.concat(s, " "), table.concat(h, ",")))
  c = {}; sprhist = {}
  frame = frame + 1
  if COIN > 0 then
    if frame == COIN then press("SYSTEM", 0x01, true) end
    if frame == COIN + 6 then press("SYSTEM", 0x01, false) end
  end
  if START > 0 then
    if frame == START then press("P1", 0x80, true) end
    if frame == START + 6 then press("P1", 0x80, false) end
  end
  if frame == END then
    local cf = open("charam.txt")
    local n = 0
    for p = 0, 511 do if chpages[p] then cf:write(fmt("%06x\n", p << 12)); n = n + 1 end end
    cf:write(fmt("# %d of 512 4KiB pages written\n", n))
    cf:close()
    for _, f in ipairs({iow, ior, dmaf, sndf, oddf, sumf}) do f:close() end
    print("NRC survey done at frame " .. frame)
    M:exit()
  end
end)
