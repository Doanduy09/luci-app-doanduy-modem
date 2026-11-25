-- Pure-Lua Universal AC IR Protocol Synthesizer for Tuya S06 Pro (OpenWrt Lua 5.1)
-- Generates Tuya-native (head, key) timing strings locally with zero cloud or remote learning needed.
-- Bit timings & frame checksums verified against crankyoldgit/IRremoteESP8266.

local nixio = require("nixio")
local bit = nixio.bit

local band, bor, bxor = bit.band, bit.bor, bit.bxor
local lshift, rshift = bit.lshift, bit.rshift
local char, concat = string.char, table.concat

local M = {}

local function clamp(v, lo, hi)
  v = tonumber(v) or lo
  if v < lo then return lo end
  if v > hi then return hi end
  return math.floor(v + 0.5)
end

-- Reverse 8 bits (LSB-first protocols sent inside Tuya MSB-first packed bitfields)
local REV8 = {}
for b = 0, 255 do
  local r = 0
  local x = b
  for i = 0, 7 do
    if band(rshift(x, i), 1) == 1 then
      r = bor(r, lshift(1, 7 - i))
    end
  end
  REV8[b] = r
end

local POPCNT4 = { [0]=0,1,1,2,1,2,2,3,1,2,2,3,2,3,3,4 }
local function popcount8(b)
  b = band(b, 0xff)
  return POPCNT4[rshift(b, 4)] + POPCNT4[band(b, 0x0f)]
end

-- Tuya build_head(headtype=2: '@' bit_mark, '#' zero_space, '$' one_space, '%' hdr_mark, '^' hdr_space, '&' gap, ...)
local function build_head(freq_khz, timings_us)
  local freq_x100 = math.floor(freq_khz * 100 + 0.5)
  local time_base = 100000.0 / freq_x100
  local parts = { string.format("%02X%04X0000000000%02X", 2, freq_x100, #timings_us) }
  for _, us in ipairs(timings_us) do
    parts[#parts + 1] = string.format("%04X", math.floor(us / time_base + 0.5))
  end
  return concat(parts)
end

local function pack_bytes(bytes, lsb_first)
  local out = {}
  local n = #bytes
  local idx = 1
  -- Split into chunks of at most 30 bytes (240 bits <= 255 bit limit)
  while idx <= n do
    local stop = math.min(n, idx + 29)
    local cnt = stop - idx + 1
    out[#out + 1] = string.format("00%02X", cnt * 8)
    for i = idx, stop do
      local b = band(bytes[i], 0xff)
      if lsb_first then b = REV8[b] end
      out[#out + 1] = string.format("%02X", b)
    end
    idx = stop + 1
  end
  return concat(out)
end

local function pack_u32_msb(val, nbits)
  local pad = (8 - (nbits % 8)) % 8
  local shifted = val * (2 ^ pad)
  local nbytes = math.floor((nbits + pad) / 8)
  local out = { string.format("00%02X", nbits) }
  for i = nbytes - 1, 0, -1 do
    local b = math.floor(shifted / (256 ^ i)) % 256
    out[#out + 1] = string.format("%02X", b)
  end
  return concat(out)
end

-- =============================================================================
-- BRAND DEFINITIONS & ALIASES
-- =============================================================================

M.BRANDS = {
  { id = "lg2",        label = "LG Inverter (Chuẩn mới LG2)", aliases = {"lg", "lg2", "lg inverter", "dual inverter", "lờ gi", "eo gi"} },
  { id = "lg",         label = "LG Đời Cũ (Classic 6711A)",  aliases = {"lg cũ", "lg classic", "lg 6711"} },
  { id = "daikin",     label = "Daikin (ARC433 / Inverter)", aliases = {"daikin", "đai kin", "đại kim", "dai kin", "đai kim"} },
  { id = "panasonic",  label = "Panasonic (Inverter)",       aliases = {"panasonic", "pana", "pa na", "pa na so nic"} },
  { id = "casper",     label = "Casper / TCL (TCL112)",      aliases = {"casper", "cát pơ", "cáp pơ", "cat po", "tcl"} },
  { id = "toshiba",    label = "Toshiba (RAS Inverter)",     aliases = {"toshiba", "tô si ba", "to si ba", "tô shi ba"} },
  { id = "gree",       label = "Gree (YAW1F / YBOFB)",       aliases = {"gree", "gờ ri", "gờ ria"} },
  { id = "midea",      label = "Midea / Funiki / Aqua / Nagakawa", aliases = {"midea", "mi đe a", "coolix", "funiki", "fu ni ki", "aqua", "comfee", "nagakawa", "na ga ka oa", "reetech"} },
  { id = "mitsubishi", label = "Mitsubishi Electric",        aliases = {"mitsubishi", "mít su", "mít xu", "mit su"} },
  { id = "samsung",    label = "Samsung (Inverter)",         aliases = {"samsung", "sam sung", "xam xung"} },
  { id = "sharp",      label = "Sharp (Plasmacluster)",      aliases = {"sharp", "sáp", "sắp"} },
  { id = "manual",     label = "Tự học phím (Thủ công)",     aliases = {"thủ công", "manual", "tự học"} },
}

local BRAND_VARIANTS = {
  lg2 = {"lg2", "lg"},
  lg = {"lg", "lg2"},
  casper = {"casper", "midea"},
  midea = {"midea", "casper"},
}

local BRAND_BY_ID = {}
for _, b in ipairs(M.BRANDS) do BRAND_BY_ID[b.id] = b end

function M.get_brand_info(brand_id)
  return BRAND_BY_ID[brand_id or "lg2"] or BRAND_BY_ID["lg2"]
end

function M.next_variant(brand_id)
  local list = BRAND_VARIANTS[brand_id]
  if list and #list >= 2 then
    for i, id in ipairs(list) do
      if id == brand_id then
        return list[(i % #list) + 1]
      end
    end
  end
  return brand_id or "lg2"
end

function M.resolve_brand(text_lower)
  local t = " " .. (text_lower or "") .. " "
  local best_id, best_len = nil, 0
  for _, b in ipairs(M.BRANDS) do
    for _, al in ipairs(b.aliases) do
      local pat = " " .. al .. " "
      if (t:find(pat, 1, true) or text_lower:find(al, 1, true)) and #al > best_len then
        best_id = b.id
        best_len = #al
      end
    end
  end
  return best_id
end

-- =============================================================================
-- PER-PROTOCOL ENCODERS
-- =============================================================================

local function lg_calc_checksum(raw28_no_sum)
  -- sumNibbles(state >> 4, 4)
  local v = math.floor(raw28_no_sum / 16)
  local s = 0
  for _ = 1, 4 do
    s = s + (v % 16)
    v = math.floor(v / 16)
  end
  return s % 16
end

local function encode_lg(state, op, is_lg2)
  local timings = is_lg2 and {480, 550, 1600, 3200, 9900, 39750} or {550, 550, 1600, 8500, 4250, 39750}
  local head = build_head(38, timings)
  local raw28
  if op == "off" then
    raw28 = 0x88C0051
  elseif op == "swing" then
    raw28 = state.swing and 0x8813149 or 0x881315A
  else
    local modes = { cool = 0, dry = 1, fan = 2, auto = 3, heat = 4 }
    local fans  = { low = 1, med = 2, high = 4, auto = 5 }
    local mode = modes[state.mode or "cool"] or 0
    local fan  = fans[state.fan or "auto"] or 5
    local temp = clamp(state.temp or 26, 16, 30) - 15
    -- Bits: Sign(8)=0x88 [27..20] | Power(2)=0 [19..18] | pad(3)=0 [17..15] | Mode(3) [14..12] | Temp(4) [11..8] | Fan(4) [7..4] | Sum(4) [3..0]
    local hi = 0x88 * 1048576 + mode * 4096 + temp * 256 + fan * 16
    raw28 = hi + lg_calc_checksum(hi)
  end
  local key = "01%^" .. pack_u32_msb(raw28, 28) .. "@&"
  return { head = head, key = key, protocol = is_lg2 and "LG2" or "LG", raw = string.format("0x%07X", raw28) }
end

local function sum_mod256(bytes, from_idx, to_idx)
  local s = 0
  for i = from_idx, to_idx do s = s + bytes[i] end
  return band(s, 0xff)
end

local function encode_daikin(state, op)
  local head = build_head(38, {428, 428, 1280, 3650, 1623, 29428})
  local s1 = {0x11, 0xDA, 0x27, 0x00, 0xC5, 0x00, 0x00, 0x00}
  s1[8] = sum_mod256(s1, 1, 7)
  local s2 = {0x11, 0xDA, 0x27, 0x00, 0x42, 0x00, 0x00, 0x00}
  s2[8] = sum_mod256(s2, 1, 7)

  local modes = { auto = 0, dry = 2, cool = 3, heat = 4, fan = 6 }
  local fans  = { low = 3, med = 5, high = 7, auto = 10 }
  local pwr   = (op ~= "off" and state.power ~= false) and 1 or 0
  local mode  = modes[state.mode or "cool"] or 3
  local fan   = fans[state.fan or "auto"] or 10
  local temp  = clamp(state.temp or 26, 10, 32)
  local sw    = state.swing and 0x0F or 0x00

  local s3 = {
    0x11, 0xDA, 0x27, 0x00, 0x00,
    bor(0x08, lshift(mode, 4), pwr),
    band(temp * 2, 0xff),
    0x00,
    bor(lshift(fan, 4), sw),
    0x00, 0x00, 0x06, 0x60, 0x00, 0x00, 0xC0, 0x00, 0x00, 0x00
  }
  s3[19] = sum_mod256(s3, 1, 18)
  -- 5 zero preamble bits + gap + sec1 + gap + sec2 + gap + sec3 + gap
  local key = "01" .. "@#@#@#@#@#" .. "@&"
    .. "%^" .. pack_bytes(s1, true) .. "@&"
    .. "%^" .. pack_bytes(s2, true) .. "@&"
    .. "%^" .. pack_bytes(s3, true) .. "@&"
  return { head = head, key = key, protocol = "DAIKIN" }
end

local function encode_panasonic(state, op)
  local head = build_head(36.7, {432, 432, 1296, 3456, 1728, 10000})
  local s = {
    0x02, 0x20, 0xE0, 0x04, 0x00, 0x00, 0x00, 0x06,
    0x02, 0x20, 0xE0, 0x04, 0x00, 0x00, 0x00, 0x80,
    0x00, 0x00, 0x00, 0x0E, 0xE0, 0x00, 0x00, 0x81,
    0x00, 0x00, 0x00
  }
  local modes = { auto = 0, dry = 2, cool = 3, heat = 4, fan = 6 }
  local fans  = { low = 1, med = 2, high = 4, auto = 7 }
  local pwr   = (op ~= "off" and state.power ~= false) and 1 or 0
  local mode  = modes[state.mode or "cool"] or 3
  local fan   = (fans[state.fan or "auto"] or 7) + 3
  local temp  = (mode == 6) and 27 or clamp(state.temp or 26, 16, 30)
  local sw    = state.swing and 0x0F or 0x03

  s[14] = bor(lshift(mode, 4), pwr) -- remote_state[13]
  s[15] = lshift(temp, 1)           -- remote_state[14]
  s[17] = bor(lshift(fan, 4), sw)   -- remote_state[16]
  s[27] = band(0xF4 + sum_mod256(s, 1, 26), 0xff)

  local sec1, sec2 = {}, {}
  for i = 1, 8 do sec1[i] = s[i] end
  for i = 9, 27 do sec2[#sec2 + 1] = s[i] end
  local key = "01%^" .. pack_bytes(sec1, true) .. "@&%^" .. pack_bytes(sec2, true) .. "@&"
  return { head = head, key = key, protocol = "PANASONIC" }
end

local function encode_casper(state, op)
  local head = build_head(38, {500, 325, 1050, 3000, 1650, 15000})
  local modes = { heat = 1, dry = 2, cool = 3, fan = 7, auto = 8 }
  local fans  = { auto = 0, low = 2, med = 3, high = 5 }
  local pwr   = (op ~= "off" and state.power ~= false) and 0x04 or 0x00
  local mode  = modes[state.mode or "cool"] or 3
  local fan   = fans[state.fan or "auto"] or 0
  local temp  = clamp(state.temp or 26, 16, 31)
  local sw    = state.swing and lshift(7, 3) or 0
  local s = {
    0x23, 0xCB, 0x26, 0x01, 0x00,
    bor(0x20, pwr),
    mode,
    31 - temp,
    bor(fan, sw),
    0x00, 0x00, 0x00, 0x00, 0x00
  }
  s[14] = sum_mod256(s, 1, 13)
  local key = "01%^" .. pack_bytes(s, true) .. "@&"
  return { head = head, key = key, protocol = "TCL112AC" }
end

local function encode_toshiba(state, op)
  local head = build_head(38, {580, 490, 1600, 4400, 4300, 7400})
  local modes = { auto = 0, cool = 1, dry = 2, heat = 3, fan = 4 }
  local fans  = { auto = 0, low = 2, med = 4, high = 6 }
  local is_off = (op == "off" or state.power == false)
  local mode = is_off and 7 or (modes[state.mode or "cool"] or 1)
  local fan  = fans[state.fan or "auto"] or 0
  local temp = clamp(state.temp or 26, 17, 30) - 17
  local sw   = state.swing and 1 or 2
  local b5 = bor(lshift(temp, 4), sw)
  local b6 = bor(lshift(fan, 5), mode)
  local s = {0xF2, 0x0D, 0x03, 0xFC, 0x01, b5, b6, 0x00, 0x00}
  local x = 0
  for i = 1, 8 do x = bxor(x, s[i]) end
  s[9] = band(x, 0xff)
  local key = "02%^" .. pack_bytes(s, false) .. "@&"
  return { head = head, key = key, protocol = "TOSHIBA_AC" }
end

local function encode_gree(state, op)
  local head = build_head(38, {620, 540, 1600, 9000, 4500, 19980})
  local modes = { auto = 0, cool = 1, dry = 2, fan = 3, heat = 4 }
  local fans  = { auto = 0, low = 1, med = 2, high = 3 }
  local pwr   = (op ~= "off" and state.power ~= false)
  local mode  = modes[state.mode or "cool"] or 1
  local fan   = (mode == 2) and 1 or (fans[state.fan or "auto"] or 0)
  local temp  = (mode == 0) and 25 or clamp(state.temp or 26, 16, 30)
  local sw_auto = state.swing and 1 or 0
  local s = {
    bor(mode, pwr and 0x08 or 0x00, lshift(fan, 4), sw_auto == 1 and 0x40 or 0x00),
    temp - 16,
    bor(0x20, pwr and 0x40 or 0x00), -- Light=1, ModelA=pwr
    0x50,                            -- unknown1=5
    sw_auto,                         -- SwingV = Auto(1)/Last(0)
    0x20,                            -- unknown2=4
    0x00,
    0x00
  }
  local csum = (10 + band(s[1], 0xf) + band(s[2], 0xf) + band(s[3], 0xf) + band(s[4], 0xf)
              + rshift(s[5], 4) + rshift(s[6], 4) + rshift(s[7], 4)) % 16
  s[8] = lshift(csum, 4)
  local blk1 = {s[1], s[2], s[3], s[4]}
  local blk2 = {s[5], s[6], s[7], s[8]}
  -- Block 1 (4B) + 3-bit footer 0b010 LSB-first (@#@$@#) + bitmark+gap (@&) + Block 2 (4B) + bitmark+gap (@&)
  local key = "01%^" .. pack_bytes(blk1, true) .. "@#@$@#@" .. "&" .. pack_bytes(blk2, true) .. "@&"
  return { head = head, key = key, protocol = "GREE" }
end

local COOLIX_TEMP_MAP = {
  [17]=0x0, [18]=0x1, [19]=0x3, [20]=0x2, [21]=0x6, [22]=0x7, [23]=0x5,
  [24]=0x4, [25]=0xC, [26]=0xD, [27]=0x9, [28]=0x8, [29]=0xA, [30]=0xB,
}

local function encode_midea(state, op)
  local head = build_head(38, {552, 552, 1656, 4692, 4416, 5244})
  local b0, b1, b2 = 0xB2, 0xBF, 0xD0
  if op == "off" then
    b0, b1, b2 = 0xB2, 0x7B, 0xE0
  elseif op == "swing" then
    b0, b1, b2 = 0xB2, 0x6B, 0xE0
  else
    local modes = { cool = 0, dry = 1, auto = 2, heat = 3, fan = 1 }
    local fans  = { low = 4, med = 2, high = 1, auto = 5 }
    local mname = state.mode or "cool"
    local mode  = modes[mname] or 0
    local fan   = (mname == "auto" or mname == "dry") and 0 or (fans[state.fan or "auto"] or 5)
    local tcode = (mname == "fan") and 0x0E or COOLIX_TEMP_MAP[clamp(state.temp or 26, 17, 30)]
    b0 = 0xB2
    b1 = bor(lshift(fan, 5), 0x1F)
    b2 = bor(lshift(tcode, 4), lshift(mode, 2))
  end
  local bytes = {b0, bxor(b0, 0xff), b1, bxor(b1, 0xff), b2, bxor(b2, 0xff)}
  local key = "02%^" .. pack_bytes(bytes, false) .. "@&"
  return { head = head, key = key, protocol = "COOLIX" }
end

local function encode_mitsubishi(state, op)
  local head = build_head(38, {450, 420, 1300, 3400, 1750, 15500})
  local modes = { heat = 1, dry = 2, cool = 3, auto = 4, fan = 7 }
  local b8_map = { heat = 0x30, dry = 0x32, cool = 0x36, auto = 0x30, fan = 0x37 }
  local fans = { auto = 0, low = 1, med = 2, high = 4 }
  local mname = state.mode or "cool"
  local pwr = (op ~= "off" and state.power ~= false) and 0x20 or 0x00
  local temp = clamp(state.temp or 26, 16, 31) - 16
  local fan_name = state.fan or "auto"
  local fan = fans[fan_name] or 0
  local fan_auto = (fan_name == "auto") and 0x80 or 0x00
  local vane = state.swing and 7 or 0
  local s = {
    0x23, 0xCB, 0x26, 0x01, 0x00,
    pwr,
    lshift(modes[mname] or 3, 3),
    temp,
    b8_map[mname] or 0x36,
    bor(fan, lshift(vane, 3), 0x40, fan_auto),
    0x67, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
  }
  s[18] = sum_mod256(s, 1, 17)
  local key = "02%^" .. pack_bytes(s, true) .. "@&"
  return { head = head, key = key, protocol = "MITSUBISHI_AC" }
end

local function samsung_fix_section_csum(s, off)
  local sum = popcount8(s[off])
    + popcount8(band(s[off + 1], 0x0f))
    + popcount8(rshift(s[off + 2], 4))
    + popcount8(s[off + 3]) + popcount8(s[off + 4]) + popcount8(s[off + 5]) + popcount8(s[off + 6])
  local c = bxor(band(sum, 0xff), 0xff)
  s[off + 1] = bor(band(s[off + 1], 0x0f), lshift(band(c, 0x0f), 4))
  s[off + 2] = bor(band(s[off + 2], 0xf0), band(rshift(c, 4), 0x0f))
end

local function encode_samsung(state, op)
  local head = build_head(38, {586, 436, 1432, 3086, 8864, 2886, 690, 17844})
  local pwr = (op ~= "off" and state.power ~= false)
  local modes = { auto = 0, cool = 1, dry = 2, fan = 3, heat = 4 }
  local fans  = { auto = 0, low = 2, med = 4, high = 5 }
  local mode = modes[state.mode or "cool"] or 1
  local fan  = (mode == 0) and 6 or (fans[state.fan or "auto"] or 0)
  local temp = clamp(state.temp or 26, 16, 30) - 16
  local sw   = state.swing and 2 or 7
  local pbits = pwr and 0x30 or 0x00

  local s = {
    0x02, 0x92, 0x0F, 0x00, 0x00, 0x00, bor(0xC0, pbits),
    0x01, 0x02, bor(0x8E, lshift(sw, 4)), 0x71, lshift(temp, 4),
    bor(0x01, lshift(fan, 1), lshift(mode, 4)),
    bor(0xC0, pbits)
  }
  samsung_fix_section_csum(s, 1)
  samsung_fix_section_csum(s, 8)
  local sec1, sec2 = {}, {}
  for i = 1, 7 do sec1[i] = s[i] end
  for i = 8, 14 do sec2[#sec2 + 1] = s[i] end
  local key = "01*(" .. "%^" .. pack_bytes(sec1, true) .. "@&%^" .. pack_bytes(sec2, true) .. "@&"
  return { head = head, key = key, protocol = "SAMSUNG_AC" }
end

local function encode_sharp(state, op)
  local head = build_head(38, {470, 500, 1400, 3800, 1900, 15000})
  local modes = { auto = 0, fan = 0, heat = 1, cool = 2, dry = 3 }
  local fans  = { auto = 2, med = 3, low = 4, high = 5 }
  local mname = state.mode or "cool"
  local mode = modes[mname] or 2
  local fan  = fans[state.fan or "auto"] or 2
  local temp = clamp(state.temp or 26, 15, 30)
  local b4 = (mname == "auto" or mname == "dry") and 0x00 or bor(0xC0, temp - 15)
  local pwr_sp, spec = 0, 0x04
  if op == "off" then
    pwr_sp = 2; spec = 0x00
  elseif op == "on" then
    pwr_sp = state.was_on and 3 or 1; spec = 0x00
  elseif op == "swing" then
    spec = 0x06
  elseif op == "fan" then
    spec = 0x05
  end
  local sw = state.swing and 7 or 2
  local s = {
    0xAA, 0x5A, 0xCF, 0x10,
    b4,
    bor(lshift(pwr_sp, 4), 0x01),
    bor(mode, lshift(fan, 4)),
    0x00,
    bor(sw, 0x08),
    0x80,
    spec,
    0xE0,
    0x01
  }
  local x = 0
  for i = 1, 12 do x = bxor(x, s[i]) end
  x = bxor(x, 0x01)
  local nib = band(bxor(x, rshift(x, 4)), 0x0f)
  s[13] = bor(lshift(nib, 4), 0x01)
  local key = "01%^" .. pack_bytes(s, true) .. "@&"
  return { head = head, key = key, protocol = "SHARP_AC" }
end

local ENCODERS = {
  lg2        = function(st, op) return encode_lg(st, op, true) end,
  lg         = function(st, op) return encode_lg(st, op, false) end,
  daikin     = encode_daikin,
  panasonic  = encode_panasonic,
  casper     = encode_casper,
  toshiba    = encode_toshiba,
  gree       = encode_gree,
  midea      = encode_midea,
  mitsubishi = encode_mitsubishi,
  samsung    = encode_samsung,
  sharp      = encode_sharp,
}

function M.is_auto_brand(brand_id)
  return ENCODERS[brand_id or ""] ~= nil
end

function M.encode(brand_id, state, op)
  local enc = ENCODERS[brand_id or ""]
  if not enc then return nil, "manual_or_unknown_brand" end
  local pkt = enc(state or {}, op or "set")
  local info = M.get_brand_info(brand_id)
  pkt.brand = info.id
  pkt.label = info.label
  return pkt
end

-- =============================================================================
-- UNIVERSAL NON-AC IR ENCODERS (NEC1/2, NECx1/2, Samsung32, Sony12/15/20, RC5)
-- =============================================================================

local GENERIC_PROTOS = {
  nec = true, nec1 = true, nec2 = true,
  necx1 = true, necx2 = true, samsung = true, samsung32 = true,
  sony12 = true, sony15 = true, sony20 = true, rc5 = true,
}

function M.supports_generic(proto)
  return GENERIC_PROTOS[(tostring(proto or "")):lower()] == true
end

function M.encode_generic(proto, dev, subdev, func)
  local p = (tostring(proto or "")):lower()
  dev = tonumber(dev) or 0
  subdev = (subdev ~= nil and subdev ~= "" and tonumber(subdev)) or -1
  func = tonumber(func) or 0

  if p == "nec" or p == "nec1" or p == "nec2" then
    local head = build_head(38, {560, 560, 1690, 9000, 4500, 40000})
    local b0 = band(dev, 0xff)
    local b1 = (subdev >= 0) and band(subdev, 0xff) or bxor(b0, 0xff)
    local b2 = band(func, 0xff)
    local b3 = bxor(b2, 0xff)
    local key = "01%^" .. pack_bytes({b0, b1, b2, b3}, true) .. "@&"
    return { head = head, key = key, protocol = proto }
  elseif p == "necx1" or p == "necx2" or p == "samsung" or p == "samsung32" then
    local head = build_head(38, {560, 560, 1690, 4500, 4500, 40000})
    local b0 = band(dev, 0xff)
    local b1 = (subdev >= 0) and band(subdev, 0xff) or b0
    local b2 = band(func, 0xff)
    local b3 = bxor(b2, 0xff)
    local key = "01%^" .. pack_bytes({b0, b1, b2, b3}, true) .. "@&"
    return { head = head, key = key, protocol = proto }
  elseif p == "sony12" or p == "sony15" or p == "sony20" then
    -- '@' = 600, '#' = 1200, '$' = 2400, '%' = 25000
    local head = build_head(40, {600, 1200, 2400, 25000})
    local seq = { "$@" }
    local function push_lsb(val, nbits)
      for i = 0, nbits - 1 do
        local b = band(rshift(val, i), 1)
        seq[#seq + 1] = (b == 1) and "#@" or "@@"
      end
    end
    push_lsb(band(func, 0x7f), 7)
    if p == "sony15" then
      push_lsb(band(dev, 0xff), 8)
    else
      push_lsb(band(dev, 0x1f), 5)
      if p == "sony20" then
        push_lsb(band(math.max(0, subdev), 0xff), 8)
      end
    end
    local raw = concat(seq)
    local key = "03" .. raw:sub(1, #raw - 1) .. "%"
    return { head = head, key = key, protocol = proto }
  elseif p == "rc5" then
    -- 14 bits: S1=1, S2=1, Toggle=0, Addr(5 MSB), Cmd(6 MSB)
    -- Manchester bit 0 = [mark 889, space 889], bit 1 = [space 889, mark 889]
    local bits = {1, 1, 0}
    for i = 4, 0, -1 do bits[#bits + 1] = band(rshift(band(dev, 0x1f), i), 1) end
    for i = 5, 0, -1 do bits[#bits + 1] = band(rshift(band(func, 0x3f), i), 1) end
    local half = {}
    for _, b in ipairs(bits) do
      if b == 1 then
        half[#half + 1] = 0; half[#half + 1] = 1
      else
        half[#half + 1] = 1; half[#half + 1] = 0
      end
    end
    -- Drop leading zero half-bit so IR pulse train begins with mark
    local start_idx = (half[1] == 0) and 2 or 1
    local runs = {}
    local cur = half[start_idx]
    local len = 1
    for i = start_idx + 1, #half do
      if half[i] == cur then
        len = len + 1
      else
        runs[#runs + 1] = { level = cur, units = len }
        cur = half[i]; len = 1
      end
    end
    runs[#runs + 1] = { level = cur, units = len }
    if runs[#runs].level == 1 then
      runs[#runs + 1] = { level = 0, units = 0 } -- append final frame gap space
    end
    -- '@' = 889, '#' = 1778, '$' = 25000
    local head = build_head(36, {889, 1778, 25000})
    local out = { "02" }
    for i = 1, #runs do
      if i == #runs then
        out[#out + 1] = "$"
      else
        out[#out + 1] = (runs[i].units == 2) and "#" or "@"
      end
    end
    return { head = head, key = concat(out), protocol = proto }
  end
  return nil, "unsupported_protocol:" .. tostring(proto)
end

return M
