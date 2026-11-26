-- [VERIFIED-GOLDEN: part4-tuya-v35-local | 2026-11-26 | DO NOT MODIFY UNLESS TARGETED]
-- Pure-Lua Tuya Protocol v3.5 Local LAN Client for OpenWrt (Lua 5.1 + nixio + cjson)
-- Implements AES-128-GCM, SHA-256, HMAC-SHA256, v3.5 session negotiation (6699/9966),
-- and S06 Pro Universal IR send/learn/status on TCP 6668 with zero external binaries.

local nixio = require("nixio")
local bit = nixio.bit
local cjson = require("cjson")

local band, bor, bxor = bit.band, bit.bor, bit.bxor
local lshift, rshift = bit.lshift, bit.rshift
local byte, char, sub, concat = string.byte, string.char, string.sub, table.concat

local M = {}

local PREFIX_6699 = "\0\0\102\153" -- 0x00006699
local SUFFIX_6699 = "\0\0\153\102" -- 0x00009966
local VERSION_HDR_35 = "3.5" .. string.rep("\0", 12)

M.CMD_SESS_KEY_NEG_START  = 3
M.CMD_SESS_KEY_NEG_RESP   = 4
M.CMD_SESS_KEY_NEG_FINISH = 5
M.CMD_STATUS              = 8
M.CMD_HEART_BEAT          = 9
M.CMD_CONTROL_NEW         = 13
M.CMD_DP_QUERY_NEW        = 16

local NO_PROTOCOL_HEADER = {
  [3] = true, [4] = true, [5] = true, [9] = true,
  [10] = true, [16] = true, [18] = true, [64] = true,
}

-- =============================================================================
-- 32-BIT ARITHMETIC HELPERS (Immune to signed int32 overflow in LuaBitOp)
-- =============================================================================

local function ror32(x, n)
  local low_mask = lshift(1, n) - 1
  return bor(rshift(band(x, 0xffffffff), n), lshift(band(x, low_mask), 32 - n))
end

local function add32(a, b)
  return band(a + b, 0xffffffff)
end

local function u32_to_be(v)
  return char(
    band(rshift(v, 24), 0xff),
    band(rshift(v, 16), 0xff),
    band(rshift(v, 8), 0xff),
    band(v, 0xff)
  )
end

local function be_to_u32(s, pos)
  local b0, b1, b2, b3 = byte(s, pos, pos + 3)
  return ((b0 * 256 + b1) * 256 + b2) * 256 + b3
end

local function be_to_u32_bits(s, pos)
  local b0, b1, b2, b3 = byte(s, pos, pos + 3)
  return bor(lshift(b0, 24), lshift(b1, 16), lshift(b2, 8), b3)
end

local function u16_to_be(v)
  return char(band(rshift(v, 8), 0xff), band(v, 0xff))
end

local function rand_bytes(n)
  local f = io.open("/dev/urandom", "rb")
  if f then
    local d = f:read(n)
    f:close()
    if d and #d == n then return d end
  end
  math.randomseed(os.time() + math.floor(os.clock() * 100000))
  local out = {}
  for i = 1, n do out[i] = char(math.random(0, 255)) end
  return concat(out)
end

function M.to_hex(s)
  local out = {}
  for i = 1, #s do
    out[i] = string.format("%02x", byte(s, i))
  end
  return concat(out)
end

-- =============================================================================
-- SHA-256 & HMAC-SHA256
-- =============================================================================

local SHA256_K = {
  0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
  0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
  0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
  0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
  0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
  0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
  0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
  0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
}

local function sha256(msg)
  local bit_len = #msg * 8
  msg = msg .. "\128"
  local pad = (56 - (#msg % 64)) % 64
  if pad > 0 then msg = msg .. string.rep("\0", pad) end
  local hi = math.floor(bit_len / 4294967296)
  local lo = bit_len % 4294967296
  msg = msg .. char(
    band(rshift(hi, 24), 0xff), band(rshift(hi, 16), 0xff), band(rshift(hi, 8), 0xff), band(hi, 0xff),
    math.floor(lo / 16777216) % 256, math.floor(lo / 65536) % 256, math.floor(lo / 256) % 256, lo % 256
  )

  local h0,h1,h2,h3 = 0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a
  local h4,h5,h6,h7 = 0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19
  local w = {}

  for off = 1, #msg, 64 do
    for i = 0, 15 do
      w[i] = be_to_u32_bits(msg, off + i * 4)
    end
    for i = 16, 63 do
      local w15 = w[i - 15]
      local w2  = w[i - 2]
      local s0 = bxor(ror32(w15, 7), ror32(w15, 18), rshift(w15, 3))
      local s1 = bxor(ror32(w2, 17), ror32(w2, 19), rshift(w2, 10))
      w[i] = add32(add32(w[i - 16], s0), add32(w[i - 7], s1))
    end
    local a,b,c,d,e,f,g,h = h0,h1,h2,h3,h4,h5,h6,h7
    for i = 0, 63 do
      local S1 = bxor(ror32(e, 6), ror32(e, 11), ror32(e, 25))
      local ch = bxor(band(e, f), band(bxor(e, 0xffffffff), g))
      local temp1 = add32(add32(add32(h, S1), add32(ch, SHA256_K[i + 1])), w[i])
      local S0 = bxor(ror32(a, 2), ror32(a, 13), ror32(a, 22))
      local maj = bxor(band(a, b), band(a, c), band(b, c))
      local temp2 = add32(S0, maj)
      h = g; g = f; f = e; e = add32(d, temp1)
      d = c; c = b; b = a; a = add32(temp1, temp2)
    end
    h0 = add32(h0, a); h1 = add32(h1, b); h2 = add32(h2, c); h3 = add32(h3, d)
    h4 = add32(h4, e); h5 = add32(h5, f); h6 = add32(h6, g); h7 = add32(h7, h)
  end

  return u32_to_be(h0) .. u32_to_be(h1) .. u32_to_be(h2) .. u32_to_be(h3)
      .. u32_to_be(h4) .. u32_to_be(h5) .. u32_to_be(h6) .. u32_to_be(h7)
end

local function hmac_sha256(key, msg)
  if #key > 64 then key = sha256(key) end
  if #key < 64 then key = key .. string.rep("\0", 64 - #key) end
  local ok_t, ik_t = {}, {}
  for i = 1, 64 do
    local kb = byte(key, i)
    ok_t[i] = char(bxor(kb, 0x5c))
    ik_t[i] = char(bxor(kb, 0x36))
  end
  return sha256(concat(ok_t) .. sha256(concat(ik_t) .. msg))
end

-- =============================================================================
-- AES-128 BLOCK ENCRYPTION & AES-128-GCM (NIST SP 800-38D)
-- =============================================================================

local SBOX = {
  [0]=0x63,0x7c,0x77,0x7b,0xf2,0x6b,0x6f,0xc5,0x30,0x01,0x67,0x2b,0xfe,0xd7,0xab,0x76,
  0xca,0x82,0xc9,0x7d,0xfa,0x59,0x47,0xf0,0xad,0xd4,0xa2,0xaf,0x9c,0xa4,0x72,0xc0,
  0xb7,0xfd,0x93,0x26,0x36,0x3f,0xf7,0xcc,0x34,0xa5,0xe5,0xf1,0x71,0xd8,0x31,0x15,
  0x04,0xc7,0x23,0xc3,0x18,0x96,0x05,0x9a,0x07,0x12,0x80,0xe2,0xeb,0x27,0xb2,0x75,
  0x09,0x83,0x2c,0x1a,0x1b,0x6e,0x5a,0xa0,0x52,0x3b,0xd6,0xb3,0x29,0xe3,0x2f,0x84,
  0x53,0xd1,0x00,0xed,0x20,0xfc,0xb1,0x5b,0x6a,0xcb,0xbe,0x39,0x4a,0x4c,0x58,0xcf,
  0xd0,0xef,0xaa,0xfb,0x43,0x4d,0x33,0x85,0x45,0xf9,0x02,0x7f,0x50,0x3c,0x9f,0xa8,
  0x51,0xa3,0x40,0x8f,0x92,0x9d,0x38,0xf5,0xbc,0xb6,0xda,0x21,0x10,0xff,0xf3,0xd2,
  0xcd,0x0c,0x13,0xec,0x5f,0x97,0x44,0x17,0xc4,0xa7,0x7e,0x3d,0x64,0x5d,0x19,0x73,
  0x60,0x81,0x4f,0xdc,0x22,0x2a,0x90,0x88,0x46,0xee,0xb8,0x14,0xde,0x5e,0x0b,0xdb,
  0xe0,0x32,0x3a,0x0a,0x49,0x06,0x24,0x5c,0xc2,0xd3,0xac,0x62,0x91,0x95,0xe4,0x79,
  0xe7,0xc8,0x37,0x6d,0x8d,0xd5,0x4e,0xa9,0x6c,0x56,0xf4,0xea,0x65,0x7a,0xae,0x08,
  0xba,0x78,0x25,0x2e,0x1c,0xa6,0xb4,0xc6,0xe8,0xdd,0x74,0x1f,0x4b,0xbd,0x8b,0x8a,
  0x70,0x3e,0xb5,0x66,0x48,0x03,0xf6,0x0e,0x61,0x35,0x57,0xb9,0x86,0xc1,0x1d,0x9e,
  0xe1,0xf8,0x98,0x11,0x69,0xd9,0x8e,0x94,0x9b,0x1e,0x87,0xe9,0xce,0x55,0x28,0xdf,
  0x8c,0xa1,0x89,0x0d,0xbf,0xe6,0x42,0x68,0x41,0x99,0x2d,0x0f,0xb0,0x54,0xbb,0x16
}
local RCON = { 0x01,0x02,0x04,0x08,0x10,0x20,0x40,0x80,0x1b,0x36 }

local function xtime(b)
  b = lshift(b, 1)
  if b >= 256 then b = bxor(b, 0x11b) end
  return b
end

local function aes128_expand_key(key)
  assert(#key == 16, "AES-128 key must be 16 bytes")
  local rk = {}
  for i = 1, 16 do rk[i] = byte(key, i) end
  for r = 1, 10 do
    local base = (r - 1) * 16
    local t0 = bxor(SBOX[rk[base + 14]], RCON[r])
    local t1 = SBOX[rk[base + 15]]
    local t2 = SBOX[rk[base + 16]]
    local t3 = SBOX[rk[base + 13]]
    rk[base + 17] = bxor(rk[base + 1], t0)
    rk[base + 18] = bxor(rk[base + 2], t1)
    rk[base + 19] = bxor(rk[base + 3], t2)
    rk[base + 20] = bxor(rk[base + 4], t3)
    for col = 1, 3 do
      local o = base + 16 + col * 4
      local p = o - 16
      local q = o - 4
      rk[o + 1] = bxor(rk[p + 1], rk[q + 1])
      rk[o + 2] = bxor(rk[p + 2], rk[q + 2])
      rk[o + 3] = bxor(rk[p + 3], rk[q + 3])
      rk[o + 4] = bxor(rk[p + 4], rk[q + 4])
    end
  end
  return rk
end

local function aes128_encrypt_block(rk, blk)
  local s0,s1,s2,s3, s4,s5,s6,s7, s8,s9,s10,s11, s12,s13,s14,s15 = byte(blk, 1, 16)
  s0=bxor(s0,rk[1]); s1=bxor(s1,rk[2]); s2=bxor(s2,rk[3]); s3=bxor(s3,rk[4])
  s4=bxor(s4,rk[5]); s5=bxor(s5,rk[6]); s6=bxor(s6,rk[7]); s7=bxor(s7,rk[8])
  s8=bxor(s8,rk[9]); s9=bxor(s9,rk[10]); s10=bxor(s10,rk[11]); s11=bxor(s11,rk[12])
  s12=bxor(s12,rk[13]); s13=bxor(s13,rk[14]); s14=bxor(s14,rk[15]); s15=bxor(s15,rk[16])

  for r = 1, 10 do
    local b0,b1,b2,b3 = SBOX[s0], SBOX[s5], SBOX[s10], SBOX[s15]
    local b4,b5,b6,b7 = SBOX[s4], SBOX[s9], SBOX[s14], SBOX[s3]
    local b8,b9,b10,b11 = SBOX[s8], SBOX[s13], SBOX[s2], SBOX[s7]
    local b12,b13,b14,b15 = SBOX[s12], SBOX[s1], SBOX[s6], SBOX[s11]
    local ko = r * 16
    if r < 10 then
      local t, u
      t = bxor(b0,b1,b2,b3); u = b0
      s0 = bxor(b0, xtime(bxor(b0,b1)), t, rk[ko+1])
      s1 = bxor(b1, xtime(bxor(b1,b2)), t, rk[ko+2])
      s2 = bxor(b2, xtime(bxor(b2,b3)), t, rk[ko+3])
      s3 = bxor(b3, xtime(bxor(b3,u)),  t, rk[ko+4])

      t = bxor(b4,b5,b6,b7); u = b4
      s4 = bxor(b4, xtime(bxor(b4,b5)), t, rk[ko+5])
      s5 = bxor(b5, xtime(bxor(b5,b6)), t, rk[ko+6])
      s6 = bxor(b6, xtime(bxor(b6,b7)), t, rk[ko+7])
      s7 = bxor(b7, xtime(bxor(b7,u)),  t, rk[ko+8])

      t = bxor(b8,b9,b10,b11); u = b8
      s8  = bxor(b8,  xtime(bxor(b8,b9)),   t, rk[ko+9])
      s9  = bxor(b9,  xtime(bxor(b9,b10)),  t, rk[ko+10])
      s10 = bxor(b10, xtime(bxor(b10,b11)), t, rk[ko+11])
      s11 = bxor(b11, xtime(bxor(b11,u)),   t, rk[ko+12])

      t = bxor(b12,b13,b14,b15); u = b12
      s12 = bxor(b12, xtime(bxor(b12,b13)), t, rk[ko+13])
      s13 = bxor(b13, xtime(bxor(b13,b14)), t, rk[ko+14])
      s14 = bxor(b14, xtime(bxor(b14,b15)), t, rk[ko+15])
      s15 = bxor(b15, xtime(bxor(b15,u)),   t, rk[ko+16])
    else
      s0=bxor(b0,rk[ko+1]); s1=bxor(b1,rk[ko+2]); s2=bxor(b2,rk[ko+3]); s3=bxor(b3,rk[ko+4])
      s4=bxor(b4,rk[ko+5]); s5=bxor(b5,rk[ko+6]); s6=bxor(b6,rk[ko+7]); s7=bxor(b7,rk[ko+8])
      s8=bxor(b8,rk[ko+9]); s9=bxor(b9,rk[ko+10]); s10=bxor(b10,rk[ko+11]); s11=bxor(b11,rk[ko+12])
      s12=bxor(b12,rk[ko+13]); s13=bxor(b13,rk[ko+14]); s14=bxor(b14,rk[ko+15]); s15=bxor(b15,rk[ko+16])
    end
  end
  return char(s0,s1,s2,s3, s4,s5,s6,s7, s8,s9,s10,s11, s12,s13,s14,s15)
end

local function xor_bytes(a, b)
  local n = math.min(#a, #b)
  local out = {}
  for i = 1, n do
    out[i] = char(bxor(byte(a, i), byte(b, i)))
  end
  return concat(out)
end

-- GF(2^128) multiplication on 16-byte big-endian blocks (4 x u32 words)
local function gf128_mul(X, Y)
  local z0,z1,z2,z3 = 0, 0, 0, 0
  local v0,v1,v2,v3 = be_to_u32_bits(Y,1), be_to_u32_bits(Y,5), be_to_u32_bits(Y,9), be_to_u32_bits(Y,13)
  for bi = 1, 16 do
    local xb = byte(X, bi)
    for bit_idx = 7, 0, -1 do
      if band(rshift(xb, bit_idx), 1) == 1 then
        z0 = bxor(z0, v0); z1 = bxor(z1, v1); z2 = bxor(z2, v2); z3 = bxor(z3, v3)
      end
      local lsb = band(v3, 1)
      v3 = bor(rshift(v3, 1), lshift(band(v2, 1), 31))
      v2 = bor(rshift(v2, 1), lshift(band(v1, 1), 31))
      v1 = bor(rshift(v1, 1), lshift(band(v0, 1), 31))
      v0 = rshift(v0, 1)
      if lsb == 1 then
        v0 = bxor(v0, 0xe1000000)
      end
    end
  end
  return u32_to_be(z0) .. u32_to_be(z1) .. u32_to_be(z2) .. u32_to_be(z3)
end

local function ghash(H, aad, ct)
  local function pad16(s)
    local rem = #s % 16
    if rem == 0 then return s end
    return s .. string.rep("\0", 16 - rem)
  end
  local function u64_bits_be(byte_len)
    local bits = byte_len * 8
    local hi = math.floor(bits / 4294967296)
    local lo = bits % 4294967296
    return char(
      band(rshift(hi, 24), 0xff), band(rshift(hi, 16), 0xff), band(rshift(hi, 8), 0xff), band(hi, 0xff),
      math.floor(lo / 16777216) % 256, math.floor(lo / 65536) % 256, math.floor(lo / 256) % 256, lo % 256
    )
  end
  local buf = pad16(aad) .. pad16(ct) .. u64_bits_be(#aad) .. u64_bits_be(#ct)
  local y = string.rep("\0", 16)
  for i = 1, #buf, 16 do
    y = gf128_mul(xor_bytes(y, sub(buf, i, i + 15)), H)
  end
  return y
end

local function inc32(blk)
  local c = { byte(blk, 1, 16) }
  for i = 16, 13, -1 do
    c[i] = (c[i] + 1) % 256
    if c[i] ~= 0 then break end
  end
  return char(unpack(c))
end

local function gctr(rk, icb, input)
  if #input == 0 then return "" end
  local cb = icb
  local out = {}
  for i = 1, #input, 16 do
    local chunk = sub(input, i, i + 15)
    local ks = aes128_encrypt_block(rk, cb)
    out[#out + 1] = xor_bytes(chunk, ks)
    cb = inc32(cb)
  end
  return concat(out)
end

function M.aes128_gcm_encrypt(key, iv, plaintext, aad)
  assert(#iv == 12, "IV must be 12 bytes")
  aad = aad or ""
  local rk = aes128_expand_key(key)
  local H = aes128_encrypt_block(rk, string.rep("\0", 16))
  local J0 = iv .. "\0\0\0\1"
  local ct = gctr(rk, inc32(J0), plaintext)
  local S = ghash(H, aad, ct)
  local tag = xor_bytes(S, aes128_encrypt_block(rk, J0))
  return ct, tag
end

function M.aes128_gcm_decrypt(key, iv, ciphertext, aad, expected_tag)
  assert(#iv == 12, "IV must be 12 bytes")
  aad = aad or ""
  local rk = aes128_expand_key(key)
  local H = aes128_encrypt_block(rk, string.rep("\0", 16))
  local J0 = iv .. "\0\0\0\1"
  local S = ghash(H, aad, ciphertext)
  local calc_tag = xor_bytes(S, aes128_encrypt_block(rk, J0))
  if calc_tag ~= expected_tag then
    return nil, "gcm_tag_mismatch"
  end
  return gctr(rk, inc32(J0), ciphertext)
end

M.sha256 = sha256
M.hmac_sha256 = hmac_sha256

-- =============================================================================
-- TUYA v3.5 PACK / UNPACK & SESSION KEY NEGOTIATION
-- =============================================================================

function M.derive_session_key(real_key, local_nonce, remote_nonce)
  local x = xor_bytes(local_nonce, remote_nonce)
  local ct = M.aes128_gcm_encrypt(real_key, sub(local_nonce, 1, 12), x, "")
  return ct
end

function M.pack_v35(key, seqno, cmd, payload, iv)
  iv = iv or rand_bytes(12)
  local body = payload or ""
  if not NO_PROTOCOL_HEADER[cmd] then
    body = VERSION_HDR_35 .. body
  end
  local msg_len = #body + 28 -- 12 iv + 16 tag (no retcode outbound, matching TinyTuya)
  local hdr14 = "\0\0" .. u32_to_be(seqno) .. u32_to_be(cmd) .. u32_to_be(msg_len)
  local ct, tag = M.aes128_gcm_encrypt(key, iv, body, hdr14)
  return PREFIX_6699 .. hdr14 .. iv .. ct .. tag .. SUFFIX_6699
end

function M.unpack_v35(key, frame)
  if #frame < 50 or sub(frame, 1, 4) ~= PREFIX_6699 then
    return nil, "bad_prefix"
  end
  local hdr14 = sub(frame, 5, 18)
  local seqno = be_to_u32(frame, 7)
  local cmd = be_to_u32(frame, 11)
  local msg_len = be_to_u32(frame, 15)
  local total_len = 18 + msg_len + 4
  if #frame < total_len or msg_len < 28 then
    return nil, "incomplete_frame"
  end
  local inner = sub(frame, 19, 18 + msg_len)
  local iv = sub(inner, 1, 12)
  local tag = sub(inner, #inner - 15, #inner)
  local ct = sub(inner, 13, #inner - 16)
  local pt, err = M.aes128_gcm_decrypt(key, iv, ct, hdr14, tag)
  if not pt then return nil, err end
  local retcode = 0
  if #pt >= 4 and cmd ~= M.CMD_SESS_KEY_NEG_RESP then
    if sub(pt, 1, 1) ~= "{" and sub(pt, 1, 3) ~= "3.5" then
      retcode = be_to_u32(pt, 1)
      pt = sub(pt, 5)
    end
  elseif #pt >= 52 and cmd == M.CMD_SESS_KEY_NEG_RESP then
    retcode = be_to_u32(pt, 1)
    pt = sub(pt, 5)
  end
  return { seqno = seqno, cmd = cmd, retcode = retcode, payload = pt }
end

local function recv_exact(sock, n, deadline_s)
  local chunks = {}
  local got = 0
  while got < n do
    if os.time() > deadline_s then return nil, "timeout" end
    local d = sock:recv(n - got)
    if d and #d > 0 then
      chunks[#chunks + 1] = d
      got = got + #d
    elseif d == "" then
      return nil, "closed"
    else
      nixio.nanosleep(0, 20000000) -- 20ms
    end
  end
  return concat(chunks)
end

local function recv_v35_frame(sock, key, timeout_s)
  local deadline = os.time() + (timeout_s or 3)
  local hdr, err = recv_exact(sock, 18, deadline)
  if not hdr then return nil, err end
  if sub(hdr, 1, 4) ~= PREFIX_6699 then
    return nil, "invalid_magic"
  end
  local msg_len = be_to_u32(hdr, 15)
  if msg_len < 28 or msg_len > 65536 then
    return nil, "bad_len"
  end
  local rest, rerr = recv_exact(sock, msg_len + 4, deadline)
  if not rest then return nil, rerr end
  return M.unpack_v35(key, hdr .. rest)
end

function M.connect(ip, dev_id, local_key, timeout_s)
  if not local_key or #local_key ~= 16 then
    return nil, "local_key_must_be_16_bytes"
  end
  timeout_s = timeout_s or 3
  local sock, err = nixio.connect(ip, 6668)
  if not sock then
    return nil, "tcp_connect_failed: " .. tostring(err)
  end
  pcall(function() sock:setopt("socket", "rcvtimeo", timeout_s, 0) end)
  pcall(function() sock:setopt("socket", "sndtimeo", timeout_s, 0) end)
  pcall(function() sock:setopt("tcp", "nodelay", 1) end)

  local seqno = 1
  local local_nonce = rand_bytes(16)
  local step1 = M.pack_v35(local_key, seqno, M.CMD_SESS_KEY_NEG_START, local_nonce)
  seqno = seqno + 1
  sock:send(step1)

  local resp, rerr = recv_v35_frame(sock, local_key, timeout_s)
  if not resp then
    sock:close()
    return nil, "handshake_step2_failed: " .. tostring(rerr)
  end
  if resp.cmd ~= M.CMD_SESS_KEY_NEG_RESP or #resp.payload < 48 then
    sock:close()
    return nil, "handshake_bad_resp_cmd_" .. tostring(resp.cmd)
  end

  local remote_nonce = sub(resp.payload, 1, 16)
  local remote_hmac = sub(resp.payload, 17, 48)
  if hmac_sha256(local_key, local_nonce) ~= remote_hmac then
    sock:close()
    return nil, "handshake_hmac_mismatch"
  end

  local step3_payload = hmac_sha256(local_key, remote_nonce)
  local step3 = M.pack_v35(local_key, seqno, M.CMD_SESS_KEY_NEG_FINISH, step3_payload)
  seqno = seqno + 1
  sock:send(step3)

  local sess_key = M.derive_session_key(local_key, local_nonce, remote_nonce)
  return {
    sock = sock,
    ip = ip,
    dev_id = dev_id,
    sess_key = sess_key,
    seqno = seqno,
  }
end

local function send_cmd(ctx, cmd, json_str)
  local pkt = M.pack_v35(ctx.sess_key, ctx.seqno, cmd, json_str)
  ctx.seqno = ctx.seqno + 1
  ctx.sock:send(pkt)
end

local function recv_dps(ctx, timeout_s)
  local deadline = os.time() + (timeout_s or 3)
  while os.time() <= deadline do
    local msg, err = recv_v35_frame(ctx.sock, ctx.sess_key, math.max(1, deadline - os.time()))
    if not msg then return nil, err end
    if msg.payload and #msg.payload > 0 then
      local js = msg.payload
      if sub(js, 1, 3) == "3.5" and #js >= 15 then
        js = sub(js, 16)
      end
      local ok, dec = pcall(cjson.decode, js)
      if ok and type(dec) == "table" then
        if type(dec.dps) == "table" then return dec.dps, msg end
        if type(dec.data) == "table" and type(dec.data.dps) == "table" then
          return dec.data.dps, msg
        end
        return {}, msg
      end
    end
  end
  return nil, "timeout"
end

function M.status(ip, dev_id, local_key, timeout_s)
  local ctx, err = M.connect(ip, dev_id, local_key, timeout_s)
  if not ctx then return nil, err end
  send_cmd(ctx, M.CMD_DP_QUERY_NEW, "{}")
  local dps, derr = recv_dps(ctx, timeout_s or 2)
  ctx.sock:close()
  return dps, derr
end

local function build_control_json(dps_tbl)
  local parts = {}
  for k, v in pairs(dps_tbl) do
    parts[#parts + 1] = cjson.encode(tostring(k)) .. ":" .. cjson.encode(v)
  end
  return string.format('{"protocol":5,"t":%d,"data":{"dps":{%s}}}', os.time(), concat(parts, ","))
end

function M.set_dps(ip, dev_id, local_key, dps_tbl, timeout_s)
  if type(dps_tbl) ~= "table" then return false, "invalid_dps" end
  local ctx, err = M.connect(ip, dev_id, local_key, timeout_s or 3)
  if not ctx then return false, err end
  send_cmd(ctx, M.CMD_CONTROL_NEW, build_control_json(dps_tbl))
  local dps, derr = recv_dps(ctx, 1)
  ctx.sock:close()
  return true, dps or derr
end

function M.detect_control_type(ip, dev_id, local_key)
  local ctx, err = M.connect(ip, dev_id, local_key, 3)
  if not ctx then return 0, err end
  -- Exit any pending study mode on both DP schemas cleanly
  send_cmd(ctx, M.CMD_CONTROL_NEW, build_control_json({ ["201"] = '{"control":"study_exit"}' }))
  nixio.nanosleep(0, 80000000)
  send_cmd(ctx, M.CMD_CONTROL_NEW, build_control_json({ ["1"] = "study_exit" }))
  nixio.nanosleep(0, 80000000)
  send_cmd(ctx, M.CMD_DP_QUERY_NEW, "{}")
  local dps = recv_dps(ctx, 2)
  local ct = 0
  if type(dps) == "table" then
    if dps["201"] ~= nil or dps["202"] ~= nil then ct = 1
    elseif dps["1"] ~= nil or dps["2"] ~= nil then ct = 2 end
  end
  ctx.sock:close()
  return ct
end

function M.send_ir(ip, dev_id, local_key, base64_code, control_type)
  if not base64_code or base64_code == "" then
    return false, "empty_ir_code"
  end
  control_type = tonumber(control_type) or 0
  if control_type == 0 then
    control_type = M.detect_control_type(ip, dev_id, local_key)
    if control_type == 0 then control_type = 1 end
  end
  local ctx, err = M.connect(ip, dev_id, local_key, 3)
  if not ctx then return false, err end
  local payload_json
  if control_type == 1 then
    local inner = string.format('{"control":"send_ir","type":0,"head":"","key1":"1%s"}', base64_code)
    payload_json = build_control_json({ ["201"] = inner })
  else
    payload_json = string.format(
      '{"protocol":5,"t":%d,"data":{"dps":{"1":"study_key","13":0,"7":%s}}}',
      os.time(), cjson.encode(base64_code)
    )
  end
  send_cmd(ctx, M.CMD_CONTROL_NEW, payload_json)
  recv_dps(ctx, 1)
  ctx.sock:close()
  return true, control_type
end

function M.send_head_key(ip, dev_id, local_key, head, key, control_type)
  if not head or head == "" or not key or key == "" then
    return false, "empty_head_key"
  end
  control_type = tonumber(control_type) or 0
  if control_type == 0 then
    control_type = M.detect_control_type(ip, dev_id, local_key)
    if control_type == 0 then control_type = 1 end
  end
  local ctx, err = M.connect(ip, dev_id, local_key, 3)
  if not ctx then return false, err end
  local payload_json
  if control_type == 1 then
    local inner = string.format(
      '{"control":"send_ir","type":0,"head":%s,"key1":%s}',
      cjson.encode(head), cjson.encode("0" .. key)
    )
    payload_json = build_control_json({ ["201"] = inner })
  else
    payload_json = string.format(
      '{"protocol":5,"t":%d,"data":{"dps":{"1":"send_ir","13":0,"3":%s,"4":%s}}}',
      os.time(), cjson.encode(head), cjson.encode(key)
    )
  end
  send_cmd(ctx, M.CMD_CONTROL_NEW, payload_json)
  recv_dps(ctx, 1)
  ctx.sock:close()
  return true, control_type
end

function M.learn_ir(ip, dev_id, local_key, timeout_s, control_type)
  timeout_s = timeout_s or 12
  control_type = tonumber(control_type) or 0
  if control_type == 0 then
    control_type = M.detect_control_type(ip, dev_id, local_key)
    if control_type == 0 then control_type = 1 end
  end
  local ctx, err = M.connect(ip, dev_id, local_key, 3)
  if not ctx then return nil, err end

  local function send_study(mode)
    if control_type == 1 then
      send_cmd(ctx, M.CMD_CONTROL_NEW, build_control_json({ ["201"] = string.format('{"control":"%s"}', mode) }))
    else
      send_cmd(ctx, M.CMD_CONTROL_NEW, build_control_json({ ["1"] = mode }))
    end
  end

  send_study("study_exit")
  nixio.nanosleep(0, 150000000)
  send_study("study")

  local learned = nil
  local deadline = os.time() + timeout_s
  while os.time() <= deadline do
    local dps = recv_dps(ctx, 2)
    if type(dps) == "table" then
      local code = (control_type == 1) and dps["202"] or dps["2"]
      if type(code) == "string" and #code >= 8 then
        learned = code
        break
      end
      -- Auto-detect schema flip if device answered on the other DP schema
      if type(dps["202"]) == "string" and #dps["202"] >= 8 then
        learned = dps["202"]; control_type = 1; break
      elseif type(dps["2"]) == "string" and #dps["2"] >= 8 then
        learned = dps["2"]; control_type = 2; break
      end
    end
  end

  pcall(function() send_study("study_exit") end)
  ctx.sock:close()
  if not learned then
    return nil, "learn_timeout"
  end
  return learned, control_type
end

return M
-- [/VERIFIED-GOLDEN]
