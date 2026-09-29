-- Neratte Chu: per-frame renderer workload (MAME 0.289), for the in-vblank render feasibility study.
-- At every frame end walks the ST-0016 sprite list exactly like draw_sprites and records:
--   entries, subs, tiles (all), vtiles (tiles with >= 1 pixel inside the clip), vpix (in-clip pixel
--   writes, i.e. framebuffer read-modify-writes), plus tilemap tiles when a layer is enabled.
-- Output: "<frame> <entries> <subs> <tiles> <vtiles> <vpix> <tmtiles>" per frame to NRC_OUT.
-- Env: NRC_OUT (file), NRC_FRAMES (stop), NRC_PLAY (1 = coin/start then random inputs from frame 2000)
local M = manager.machine
local spr = M.memory.shares[":maincpu:spriteram"]
local iosp = M.devices[":maincpu"].spaces["io"]
local out = io.open(assert(os.getenv("NRC_OUT")), "w")
local END = tonumber(os.getenv("NRC_FRAMES") or "3000")
local PLAY = os.getenv("NRC_PLAY") == "1"
local vregs = {}
for i = 0, 255 do vregs[i] = 0 end
TAP = iosp:install_write_tap(0x00, 0xff, "rc", function(o, d) vregs[o & 0xff] = d end)

local function s10(v) if v >= 0x200 then return v - 0x400 end return v end
local function b(a) return spr:read_u8(a) end
-- in-clip extent of an 8-wide run starting at p (u16 arithmetic, x wrap -512 if > 327)
local function xcount(p)
  local n = 0
  for k = 0, 7 do
    local d = (p + k) & 0xffff
    if d > 327 then d = (d - 512) & 0xffff end
    if d >= 8 and d <= 327 then n = n + 1 end
  end
  return n
end
local function ycount(p)
  local n = 0
  for k = 0, 7 do local d = (p + k) & 0xffff; if d <= 239 then n = n + 1 end end
  return n
end

local function cost()
  local entries, subs, tiles, vtiles, vpix, tmt = 0, 0, 0, 0, 0, 0
  for j = 0, 0x38, 8 do if vregs[j + 1] ~= 0 then tmt = tmt + 40 * 29 end end
  for i = 0, 0xfff8, 8 do
    if (b(i + 3) & 0x80) ~= 0 then break end
    entries = entries + 1
    local x = s10(b(i + 4) + ((b(i + 5) & 3) << 8))
    local y = s10(b(i + 6) + ((b(i + 7) & 3) << 8))
    local si = ((b(i + 1) & 0x0f) >> 1) * 4 + 0x40
    x = x + s10((vregs[si] + 256 * vregs[si + 1]) & 0x3ff)
    y = y + s10((vregs[si + 2] + 256 * vregs[si + 3]) & 0x3ff)
    local use = (b(i + 1) & 0x10) ~= 0
    local gw, gh = (b(i + 5) >> 2) & 3, (b(i + 7) >> 2) & 3
    local off = (b(i + 2) + 256 * b(i + 3)) * 8
    local len = b(i) + 1 + 256 * (b(i + 1) & 1)
    if off < 0x10000 then
      for _ = 1, len do
        subs = subs + 1
        local sx = b(off + 4) + ((b(off + 5) & 1) << 8) + x
        local sy = b(off + 6) + ((b(off + 7) & 1) << 8) + y
        local lx, ly = gw, gh
        if use then lx, ly = (b(off + 5) >> 2) & 3, (b(off + 7) >> 2) & 3 end
        for c = 0, (1 << lx) - 1 do
          local xc = xcount(sx + c * 8)
          for r = 0, (1 << ly) - 1 do
            tiles = tiles + 1
            local p = xc * ycount(sy + r * 8 + 8)
            if p > 0 then vtiles = vtiles + 1; vpix = vpix + p end
          end
        end
        off = off + 8
        if off >= 0x10000 then break end
      end
    end
  end
  return entries, subs, tiles, vtiles, vpix, tmt
end

local function press(port, mask, on)
  for _, f in pairs(M.ioport.ports[":" .. port].fields) do
    if f.mask == mask then f:set_value(on and 1 or 0) end
  end
end
local frame = 0
local rng = 12345
local function rnd(n) rng = (rng * 1103515245 + 12345) % 2147483648; return rng % n end
local held = {}
emu.register_frame_done(function()
  out:write(string.format("%d %d %d %d %d %d %d\n", frame, cost()))
  frame = frame + 1
  if PLAY then
    if frame == 2000 or frame == 2400 then press("SYSTEM", 0x01, true) end
    if frame == 2006 or frame == 2406 then press("SYSTEM", 0x01, false) end
    if frame == 2100 or frame == 2500 then press("P1", 0x80, true) end
    if frame == 2106 or frame == 2506 then press("P1", 0x80, false) end
    if frame > 2600 and frame % 8 == 0 then
      for _, m in ipairs({0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40}) do press("P1", m, false) end
      press("P1", ({0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40})[rnd(7) + 1], true)
      if rnd(400) == 0 then press("SYSTEM", 0x01, true) end
      if rnd(400) == 1 then press("SYSTEM", 0x01, false); press("P1", 0x80, true) end
      if rnd(50) == 0 then press("P1", 0x80, false) end
    end
  end
  if frame >= END then out:close(); M:exit() end
end)
