-- Neratte Chu: CPU write stream from reset (MAME 0.289) for RTL differential tests (M3/M4).
-- Logs every Z80 memory write and I/O write, in program order:
--   "M aaaa dd"  memory write
--   "O pp dd"    I/O write
--   "F n"        marker at each frame end (MAME frame_done, i.e. its vblank/render instant)
-- plus "R pp dd" for I/O reads of ports that feed back into control flow (00/01 random,
-- C0-C3 inputs) so the RTL bench can replay the same values.
-- Env: NRC_OUT (file path), NRC_MAXW (max logged writes, default 300000), NRC_FRAMES (stop, default 400)
local M = manager.machine
local cpu = M.devices[":maincpu"]
local mem = cpu.spaces["regs"]
local iosp = cpu.spaces["io"]
local fmt = string.format
local out = io.open(assert(os.getenv("NRC_OUT")), "w")
out:setvbuf("full", 1 << 20)
local MAXW = tonumber(os.getenv("NRC_MAXW") or "300000")
local END = tonumber(os.getenv("NRC_FRAMES") or "400")
local n = 0
local frame = 0
local function done()
  out:write(fmt("E %d %d\n", frame, n)); out:close()
  print("NRC writes done: frame " .. frame .. " writes " .. n)
  M:exit()
end
TAP_MW = mem:install_write_tap(0x0000, 0xffff, "nrc_mw", function(offset, data, mask)
  if n < MAXW then out:write(fmt("M %04x %02x\n", offset, data)); n = n + 1 end
end)
TAP_OW = iosp:install_write_tap(0x00, 0xff, "nrc_ow", function(offset, data, mask)
  if n < MAXW then out:write(fmt("O %02x %02x\n", offset & 0xff, data)); n = n + 1 end
end)
TAP_OR = iosp:install_read_tap(0x00, 0xff, "nrc_or", function(offset, data, mask)
  local p = offset & 0xff
  if n < MAXW and (p <= 1 or (p >= 0xc0 and p <= 0xc3)) then out:write(fmt("R %02x %02x\n", p, data)) end
end)
emu.register_frame_done(function()
  frame = frame + 1
  out:write(fmt("F %d\n", frame))
  if n >= MAXW or frame >= END then done() end
end)
