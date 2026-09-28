-- Neratte Chu state dumps for the video/audio reference models (MAME 0.289).
-- At each requested frame (after that frame's screen update) writes:
--   f<N>_spr.bin   sprite RAM, 64 KiB
--   f<N>_pal.bin   palette RAM, 2 KiB
--   f<N>_vreg.bin  I/O register shadow 0x00-0xff (reconstructed from write taps)
--   f<N>_cha.bin   character RAM, 2 MiB (only when NRC_CHA=1)
--   and a MAME snapshot (needs -video other than none, -snapshot_directory).
-- Output contains ROM-derived data: keep it outside the repository.
--
-- Env:
--   NRC_OUT     output directory (required, must exist)
--   NRC_AT      comma list of frames to dump (e.g. "300,600,1200")
--   NRC_CHA     comma list of frames at which to also dump character RAM (slow)
--   NRC_COIN / NRC_START  frames at which to pulse COIN1 / START1 (0 = never)
--   NRC_INPUTS  optional input script: "frame:port:mask:0|1,..." (e.g. "2300:P1:0x10:1")
local M = manager.machine
local cpu = M.devices[":maincpu"]
local iosp = cpu.spaces["io"]
local fmt = string.format
local OUT = assert(os.getenv("NRC_OUT"), "NRC_OUT not set")
local cha_at = {}
for n in string.gmatch(os.getenv("NRC_CHA") or "", "%d+") do cha_at[tonumber(n)] = true end
local COIN = tonumber(os.getenv("NRC_COIN") or "0")
local START = tonumber(os.getenv("NRC_START") or "0")
local at, last = {}, 0
for n in string.gmatch(os.getenv("NRC_AT") or "600", "%d+") do
  at[tonumber(n)] = true; if tonumber(n) > last then last = tonumber(n) end
end
local inputs = {}
for fr, port, mask, v in string.gmatch(os.getenv("NRC_INPUTS") or "", "(%d+):(%w+):(%w+):(%d)") do
  inputs[#inputs + 1] = {tonumber(fr), port, tonumber(mask), v == "1"}
end

local vregs = {}
for i = 0, 255 do vregs[i] = 0 end
TAP_IOW = iosp:install_write_tap(0x00, 0xff, "nrc_iow", function(offset, data, mask)
  vregs[offset & 0xff] = data
end)

local function share(name)
  local s = M.memory.shares[":maincpu:" .. name]
  assert(s, "no share " .. name)
  return s
end
local function dump(sh, fname, len)
  local f = io.open(OUT .. "/" .. fname, "wb")
  local t = {}
  for i = 0, len - 1 do
    t[#t + 1] = string.char(sh:read_u8(i))
    if #t == 4096 then f:write(table.concat(t)); t = {} end
  end
  f:write(table.concat(t)); f:close()
end
local function press(port, mask, on)
  local p = M.ioport.ports[":" .. port]
  for _, fld in pairs(p.fields) do
    if fld.mask == mask then fld:set_value(on and 1 or 0) end
  end
end

-- Windowed runs: nratechu is MACHINE_NO_COCKTAIL; the warning screen pauses emulation.
-- Seed the cfg dir with scripts/mame/seed_cfg.sh and use an -inipath ui.ini with
-- skip_warnings 1 (docs/MAME_REFERENCE.md).

local frame = 0
emu.register_frame_done(function()
  if at[frame] then
    dump(share("spriteram"), fmt("f%d_spr.bin", frame), 0x10000)
    dump(share("paletteram"), fmt("f%d_pal.bin", frame), 0x800)
    if cha_at[frame] then dump(share("charam"), fmt("f%d_cha.bin", frame), 0x200000) end
    local f = io.open(OUT .. fmt("/f%d_vreg.bin", frame), "wb")
    for i = 0, 255 do f:write(string.char(vregs[i])) end
    f:close()
    M.video:snapshot()
  end
  frame = frame + 1
  if COIN > 0 then
    if frame == COIN then press("SYSTEM", 0x01, true) end
    if frame == COIN + 6 then press("SYSTEM", 0x01, false) end
  end
  if START > 0 then
    if frame == START then press("P1", 0x80, true) end
    if frame == START + 6 then press("P1", 0x80, false) end
  end
  for _, e in ipairs(inputs) do
    if e[1] == frame then press(e[2], e[3], e[4]) end
  end
  if frame > last then
    print("NRC dump done at frame " .. frame)
    M:exit()
  end
end)
