#!/usr/bin/lua
-- DOANDUY Auto-Mesh Encrypted Wi-Fi Profile Sync & Config Helper (v2.7.0)
-- Uses pure Lua 5.1 + nixio.bit + nixio.bin + cjson (no external openssl CLI required)

local nixio = require("nixio")
local bit   = nixio.bit
local bin   = nixio.bin
local cjson = require("cjson.safe")

local MESH_UCI        = "doanduy_mesh"
local DEFAULT_KEY     = "DoanduyMesh@2026!Sec"
local ENC_TMP         = "/tmp/mesh_wifi_profile.enc"
local ENC_WWW         = "/www/mesh_wifi_profile.enc"
local PUB_HASH_FILE   = "/tmp/mesh_wifi_pub_hash"
local APP_HASH_FILE   = "/tmp/doanduy_mesh_applied_wifi_hash"
local ORIG_BACKUP     = "/etc/config/doanduy_mesh_orig_wifi.json"

local band, bxor, bor = bit.band, bit.bxor, bit.bor

local function u32(x)
	return x % 4294967296
end

local POW2 = {}
for i = 0, 32 do POW2[i] = 2 ^ i end

local function rotr(x, n)
	x = u32(x)
	local p = POW2[n]
	local lo = x % p
	return math.floor(x / p) + lo * POW2[32 - n]
end

local function rsh(x, n)
	return math.floor(u32(x) / POW2[n])
end

local K = {
	0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
	0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
	0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
	0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
	0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
	0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
	0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
	0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
}

local function be32_str(v)
	v = u32(v)
	return string.char(
		math.floor(v / 16777216) % 256,
		math.floor(v / 65536) % 256,
		math.floor(v / 256) % 256,
		v % 256
	)
end

local function sha256_raw(msg)
	local len = #msg
	local pad_zero = (55 - len) % 64
	local bit_len = len * 8
	local hi = math.floor(bit_len / 4294967296)
	local lo = bit_len % 4294967296
	msg = msg .. "\128" .. string.rep("\0", pad_zero) .. be32_str(hi) .. be32_str(lo)

	local h0, h1, h2, h3 = 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a
	local h4, h5, h6, h7 = 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
	local w = {}

	for off = 1, #msg, 64 do
		for i = 0, 15 do
			local b1, b2, b3, b4 = msg:byte(off + i * 4, off + i * 4 + 3)
			w[i] = ((b1 * 256 + b2) * 256 + b3) * 256 + b4
		end
		for i = 16, 63 do
			local v15 = w[i - 15]
			local v2  = w[i - 2]
			local s0  = bxor(rotr(v15, 7), rotr(v15, 18), rsh(v15, 3))
			local s1  = bxor(rotr(v2, 17), rotr(v2, 19), rsh(v2, 10))
			w[i] = u32(w[i - 16] + u32(s0) + w[i - 7] + u32(s1))
		end
		local a, b, c, d, e, f, g, h = h0, h1, h2, h3, h4, h5, h6, h7
		for i = 0, 63 do
			local S1  = bxor(rotr(e, 6), rotr(e, 11), rotr(e, 25))
			local ch  = bxor(band(e, f), band(0xffffffff - e, g))
			local t1  = u32(h + u32(S1) + u32(ch) + K[i + 1] + w[i])
			local S0  = bxor(rotr(a, 2), rotr(a, 13), rotr(a, 22))
			local maj = bxor(band(a, b), band(a, c), band(b, c))
			local t2  = u32(u32(S0) + u32(maj))
			h = g; g = f; f = e; e = u32(d + t1)
			d = c; c = b; b = a; a = u32(t1 + t2)
		end
		h0 = u32(h0 + a); h1 = u32(h1 + b); h2 = u32(h2 + c); h3 = u32(h3 + d)
		h4 = u32(h4 + e); h5 = u32(h5 + f); h6 = u32(h6 + g); h7 = u32(h7 + h)
	end

	return be32_str(h0) .. be32_str(h1) .. be32_str(h2) .. be32_str(h3)
		.. be32_str(h4) .. be32_str(h5) .. be32_str(h6) .. be32_str(h7)
end

local function to_hex(s)
	return (s:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end

local function hmac_sha256(key, msg)
	if #key > 64 then key = sha256_raw(key) end
	if #key < 64 then key = key .. string.rep("\0", 64 - #key) end
	local ipad, opad = {}, {}
	for i = 1, 64 do
		local kb = key:byte(i)
		ipad[i] = string.char(bxor(kb, 0x36))
		opad[i] = string.char(bxor(kb, 0x5c))
	end
	return sha256_raw(table.concat(opad) .. sha256_raw(table.concat(ipad) .. msg))
end

local function sha256_ctr(enc_key, nonce16, data)
	local out = {}
	local n = #data
	local blk = 0
	local pos = 1
	while pos <= n do
		local ks = sha256_raw(enc_key .. nonce16 .. be32_str(blk))
		local chunk_end = math.min(pos + 31, n)
		local buf = {}
		for i = pos, chunk_end do
			local kb = ks:byte(i - pos + 1)
			buf[#buf + 1] = string.char(bxor(data:byte(i), kb))
		end
		out[#out + 1] = table.concat(buf)
		blk = blk + 1
		pos = chunk_end + 1
	end
	return table.concat(out)
end

local function ct_eq(a, b)
	if type(a) ~= "string" or type(b) ~= "string" or #a ~= #b then return false end
	local diff = 0
	for i = 1, #a do
		diff = bor(diff, bxor(a:byte(i), b:byte(i)))
	end
	return diff == 0
end

local function rand16()
	local f = io.open("/dev/urandom", "rb")
	if f then
		local r = f:read(16)
		f:close()
		if r and #r == 16 then return r end
	end
	math.randomseed(os.time() + math.floor((os.clock() or 0) * 100000))
	local up = ""
	local uf = io.open("/proc/uptime", "r")
	if uf then up = uf:read("*a") or ""; uf:close() end
	return sha256_raw(tostring(os.time()) .. "|" .. up .. "|" .. tostring(math.random())):sub(1, 16)
end

local function shq(s)
	return "'" .. tostring(s or ""):gsub("'", "'\\''") .. "'"
end

local function trim(s)
	return tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function exec_read(cmd)
	local p = io.popen(cmd, "r")
	if not p then return "" end
	local out = p:read("*a") or ""
	p:close()
	return out
end

local function read_file(path)
	local f = io.open(path, "rb")
	if not f then return nil end
	local c = f:read("*a")
	f:close()
	return c
end

local function write_atomic(path, content)
	local tmp = path .. ".tmp"
	local f = io.open(tmp, "wb")
	if not f then return false end
	f:write(content)
	f:close()
	os.rename(tmp, path)
	return true
end

local function uci_get(k)
	local v = exec_read("/sbin/uci -q get " .. shq(k) .. " 2>/dev/null")
	return trim(v)
end

local function get_mesh_secret()
	local k = uci_get(MESH_UCI .. ".mesh.key")
	if k == "" then k = DEFAULT_KEY end
	return sha256_raw(k .. "|DOANDUY_WIFI_ENC_V1"), sha256_raw(k .. "|DOANDUY_WIFI_MAC_V1")
end

local SKIP_IFACES = {
	mesh_backhaul_ap = true,
	mesh_sta = true,
	mesh_80211s = true,
	mesh_backhaul = true,
	mesh0 = true,
	mesh1 = true
}

local function parse_wireless()
	local raw = exec_read("/sbin/uci show wireless 2>/dev/null")
	local sections = {}
	local order = {}
	for line in raw:gmatch("[^\r\n]+") do
		local sec, stype = line:match("^wireless%.([^.=]+)=([%w_-]+)$")
		if sec and stype then
			if not sections[sec] then
				sections[sec] = { _name = sec, _type = stype }
				order[#order + 1] = sec
			else
				sections[sec]._type = stype
			end
		else
			local sname, opt, val = line:match("^wireless%.([^.=]+)%.([^=]+)=(.*)$")
			if sname and opt then
				if not sections[sname] then
					sections[sname] = { _name = sname }
					order[#order + 1] = sname
				end
				local unq = val:match("^'(.*)'$")
				if unq ~= nil then
					val = unq:gsub("'\\''", "'")
				end
				sections[sname][opt] = val
			end
		end
	end

	local radios, aps = {}, {}
	for _, name in ipairs(order) do
		local s = sections[name]
		if s._type == "wifi-device" then
			radios[name] = s
		elseif s._type == "wifi-iface" and s.mode == "ap" and not SKIP_IFACES[name] then
			if s.disabled ~= "1" then
				local r = s.device and radios[s.device]
				local b = (r and r.band) or ""
				local grp = (b == "2g") and "2g" or ((b == "5g" or b == "6g") and "5g" or "")
				if grp == "" then
					if name:match("radio0") then grp = "2g" else grp = "5g" end
				end
				s._group = grp
				aps[#aps + 1] = s
			end
		end
	end
	return radios, aps
end

local function normalize_enc(enc, key)
	enc = trim(enc)
	if enc == "none" or (enc == "" and trim(key) == "") then
		return "none"
	end
	if trim(key) == "" then return "none" end
	if enc == "psk2" or enc == "psk-mixed" or enc == "sae-mixed" or enc == "sae" or enc == "psk" then
		return enc
	end
	if enc:match("^psk2") then return "psk2" end
	if enc:match("^psk%-mixed") then return "psk-mixed" end
	return "psk2"
end

local function has_wpa3_support()
	local out = exec_read("iwinfo 2>/dev/null; hostapd -v 2>&1")
	-- Safe default on OpenWrt 23/24/25 with wpad-mbedtls/openssl: support sae if wpad built with SAE
	local wpad = exec_read("opkg list-installed wpad* 2>/dev/null; apk info 2>/dev/null | grep -i wpad")
	if wpad:match("mini") or wpad:match("basic") then return false end
	return true
end

local function get_local_profile()
	local _, aps = parse_wireless()
	local p2, p5
	for _, ap in ipairs(aps) do
		if ap._group == "2g" and not p2 then
			p2 = { ssid = ap.ssid or "", enc = normalize_enc(ap.encryption, ap.key), key = ap.key or "" }
		elseif ap._group == "5g" and not p5 then
			p5 = { ssid = ap.ssid or "", enc = normalize_enc(ap.encryption, ap.key), key = ap.key or "" }
		end
	end
	if not p2 and p5 then p2 = { ssid = p5.ssid, enc = p5.enc, key = p5.key } end
	if not p5 and p2 then p5 = { ssid = p2.ssid, enc = p2.enc, key = p2.key } end
	if not p2 then p2 = { ssid = "DOANDUY_2.4G", enc = "none", key = "" } end
	if not p5 then p5 = { ssid = "DOANDUY_5G", enc = "none", key = "" } end
	return {
		ssid_2g = p2.ssid, enc_2g = p2.enc, key_2g = p2.key,
		ssid_5g = p5.ssid, enc_5g = p5.enc, key_5g = p5.key
	}
end

local function profile_hash(prof)
	local canon = table.concat({
		tostring(prof.ssid_2g or ""), tostring(prof.enc_2g or ""), tostring(prof.key_2g or ""),
		tostring(prof.ssid_5g or ""), tostring(prof.enc_5g or ""), tostring(prof.key_5g or "")
	}, "\031")
	return to_hex(sha256_raw(canon)):sub(1, 16)
end

local function backup_orig_wifi_once()
	if nixio.fs.stat(ORIG_BACKUP) then return end
	local prof = get_local_profile()
	local js = cjson.encode(prof)
	if js then
		os.execute("mkdir -p /etc/config 2>/dev/null")
		write_atomic(ORIG_BACKUP, js .. "\n")
	end
end

local function apply_profile_to_local(prof)
	local _, aps = parse_wireless()
	local cmds = {}
	local wpa3_ok = has_wpa3_support()

	for _, ap in ipairs(aps) do
		local t_ssid, t_enc, t_key
		if ap._group == "2g" then
			t_ssid, t_enc, t_key = prof.ssid_2g, prof.enc_2g, prof.key_2g
		else
			t_ssid, t_enc, t_key = prof.ssid_5g, prof.enc_5g, prof.key_5g
		end
		if t_ssid and t_ssid ~= "" then
			t_enc = normalize_enc(t_enc, t_key)
			if not wpa3_ok and (t_enc == "sae" or t_enc == "sae-mixed") then
				t_enc = "psk2"
			end
			if t_enc == "none" then t_key = "" end

			if (ap.ssid or "") ~= t_ssid then
				cmds[#cmds + 1] = "/sbin/uci -q set " .. shq("wireless." .. ap._name .. ".ssid=" .. t_ssid)
			end
			if (ap.encryption or "") ~= t_enc then
				cmds[#cmds + 1] = "/sbin/uci -q set " .. shq("wireless." .. ap._name .. ".encryption=" .. t_enc)
			end
			if t_enc == "none" then
				if (ap.key or "") ~= "" then
					cmds[#cmds + 1] = "/sbin/uci -q delete " .. shq("wireless." .. ap._name .. ".key")
				end
			else
				if (ap.key or "") ~= t_key then
					cmds[#cmds + 1] = "/sbin/uci -q set " .. shq("wireless." .. ap._name .. ".key=" .. t_key)
				end
			end
		end
	end

	if #cmds == 0 then return false end
	cmds[#cmds + 1] = "/sbin/uci -q commit wireless"
	os.execute(table.concat(cmds, " && "))
	return true
end

local function encrypt_profile(prof)
	local enc_key, mac_key = get_mesh_secret()
	local plain = cjson.encode(prof)
	local nonce = rand16()
	local ct    = sha256_ctr(enc_key, nonce, plain)
	local mac   = to_hex(hmac_sha256(mac_key, nonce .. ct))
	return cjson.encode({
		v     = 1,
		hash  = profile_hash(prof),
		nonce = bin.b64encode(nonce),
		ct    = bin.b64encode(ct),
		mac   = mac
	})
end

local function decrypt_profile(raw_json)
	local env = cjson.decode(raw_json or "")
	if type(env) ~= "table" or env.v ~= 1 or not env.nonce or not env.ct or not env.mac then
		return nil, "invalid_envelope"
	end
	local nonce = bin.b64decode(env.nonce)
	local ct    = bin.b64decode(env.ct)
	if not nonce or #nonce ~= 16 or not ct or #ct == 0 then
		return nil, "invalid_b64"
	end
	local enc_key, mac_key = get_mesh_secret()
	local expected_mac = to_hex(hmac_sha256(mac_key, nonce .. ct))
	if not ct_eq(expected_mac, tostring(env.mac)) then
		return nil, "hmac_mismatch"
	end
	local plain = sha256_ctr(enc_key, nonce, ct)
	local prof  = cjson.decode(plain)
	if type(prof) ~= "table" or not prof.ssid_2g then
		return nil, "invalid_payload"
	end
	return prof, env.hash or profile_hash(prof)
end

local function cmd_selftest()
	local digest = to_hex(sha256_raw("abc"))
	if digest ~= "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" then
		io.stderr:write("SHA256 mismatch: " .. digest .. "\n")
		os.exit(1)
	end
	local sample = {
		ssid_2g = "TPT Lam", enc_2g = "psk2", key_2g = "SecretPass@2026",
		ssid_5g = "TPT Lam 5G", enc_5g = "psk2", key_5g = "SecretPass@2026"
	}
	local env_json = encrypt_profile(sample)
	if env_json:find("SecretPass@2026", 1, true) or env_json:find("TPT Lam", 1, true) then
		io.stderr:write("Plaintext leaked in ciphertext\n")
		os.exit(1)
	end
	local dec, h = decrypt_profile(env_json)
	if not dec or dec.ssid_2g ~= sample.ssid_2g or dec.key_5g ~= sample.key_5g or not h then
		io.stderr:write("Decrypt mismatch\n")
		os.exit(1)
	end
	local env = cjson.decode(env_json)
	env.mac = ("0"):rep(64)
	local bad = decrypt_profile(cjson.encode(env))
	if bad ~= nil then
		io.stderr:write("Tamper check failed\n")
		os.exit(1)
	end
	print("OK")
end

local function ensure_www_symlink()
	if not nixio.fs.stat(ENC_WWW) and nixio.fs.stat(ENC_TMP) then
		os.execute("ln -sf " .. shq(ENC_TMP) .. " " .. shq(ENC_WWW) .. " 2>/dev/null")
	end
end

local function cmd_publish()
	local prof = get_local_profile()
	local h = profile_hash(prof)
	local prev = trim(read_file(PUB_HASH_FILE) or "")
	if prev ~= h or not nixio.fs.stat(ENC_TMP) then
		local enc = encrypt_profile(prof)
		if enc then
			write_atomic(ENC_TMP, enc)
			write_atomic(PUB_HASH_FILE, h)
		end
	end
	ensure_www_symlink()
	print(h)
end

local function cmd_sync(master_ip, expected_hash)
	local sync_mode = uci_get(MESH_UCI .. ".mesh.wifi_sync_mode")
	if sync_mode == "" then sync_mode = "master" end

	if sync_mode == "custom" then
		local s2 = uci_get(MESH_UCI .. ".mesh.custom_ssid_2g")
		local s5 = uci_get(MESH_UCI .. ".mesh.custom_ssid_5g")
		local en = uci_get(MESH_UCI .. ".mesh.custom_encryption")
		local ky = uci_get(MESH_UCI .. ".mesh.custom_key")
		if s2 == "" and s5 ~= "" then s2 = s5 end
		if s5 == "" and s2 ~= "" then s5 = s2 end
		if s2 ~= "" then
			local changed = apply_profile_to_local({
				ssid_2g = s2, enc_2g = en ~= "" and en or "psk2", key_2g = ky,
				ssid_5g = s5, enc_5g = en ~= "" and en or "psk2", key_5g = ky
			})
			os.exit(changed and 2 or 0)
		end
		os.exit(0)
	end

	-- Master sync mode
	master_ip = trim(master_ip)
	if master_ip == "" then os.exit(1) end
	expected_hash = trim(expected_hash)
	local app_hash = trim(read_file(APP_HASH_FILE) or "")
	local cur_prof = get_local_profile()
	local cur_h = profile_hash(cur_prof)
	if expected_hash ~= "" and app_hash == expected_hash and cur_h == expected_hash then
		os.exit(0)
	end

	local url = "http://" .. master_ip .. "/mesh_wifi_profile.enc"
	local raw = exec_read("uclient-fetch -q -T 2 -O - " .. shq(url) .. " 2>/dev/null")
	if raw == "" then
		raw = exec_read("curl -fsSL --max-time 2 " .. shq(url) .. " 2>/dev/null")
	end
	if raw == "" then os.exit(1) end

	local prof, h = decrypt_profile(raw)
	if not prof then os.exit(1) end

	backup_orig_wifi_once()
	local changed = apply_profile_to_local(prof)
	write_atomic(APP_HASH_FILE, h)
	os.exit(changed and 2 or 0)
end

local function cmd_summary()
	local sync_mode = uci_get(MESH_UCI .. ".mesh.wifi_sync_mode")
	if sync_mode == "" then sync_mode = "master" end
	local prof = get_local_profile()
	local h = profile_hash(prof)
	local pub_h = trim(read_file(PUB_HASH_FILE) or "")
	local app_h = trim(read_file(APP_HASH_FILE) or "")
	local enc = prof.enc_5g ~= "" and prof.enc_5g or prof.enc_2g
	local has_key = (prof.key_5g ~= "" or prof.key_2g ~= "")
	print(cjson.encode({
		sync_mode = sync_mode,
		ssid_2g   = prof.ssid_2g,
		ssid_5g   = prof.ssid_5g,
		encryption = enc,
		has_key   = has_key,
		wifi_hash = h,
		synced    = (sync_mode == "master" and (app_h == h or pub_h == h))
	}))
end

local function cmd_set_wifi()
	local raw = io.read("*a") or ""
	local req = cjson.decode(raw)
	if type(req) ~= "table" then
		print(cjson.encode({ success = false, message = "Dữ liệu không hợp lệ" }))
		return
	end

	os.execute("mkdir -p /etc/config /tmp 2>/dev/null; touch /etc/config/" .. MESH_UCI)
	if uci_get(MESH_UCI .. ".mesh") == "" then
		os.execute("/sbin/uci -q set " .. MESH_UCI .. ".mesh=mesh && /sbin/uci -q commit " .. MESH_UCI)
	end

	local mode = trim(req.sync_mode)
	if mode == "master" then
		os.execute("/sbin/uci -q set " .. MESH_UCI .. ".mesh.wifi_sync_mode=master && /sbin/uci -q commit " .. MESH_UCI)
		os.remove(APP_HASH_FILE)
		print(cjson.encode({
			success   = true,
			sync_mode = "master",
			reload    = false,
			message   = "Đã bật chế độ đồng bộ Wi-Fi tự động theo Router Chính!"
		}))
		return
	end

	if mode ~= "custom" then
		print(cjson.encode({ success = false, message = "Chế độ đồng bộ không hợp lệ" }))
		return
	end

	local s2 = trim(req.ssid_2g):gsub("[\r\n]", "")
	local s5 = trim(req.ssid_5g):gsub("[\r\n]", "")
	if s2 == "" and s5 ~= "" then s2 = s5 end
	if s5 == "" and s2 ~= "" then s5 = s2 end
	if #s2 < 1 or #s2 > 32 or #s5 < 1 or #s5 > 32 then
		print(cjson.encode({ success = false, message = "Tên Wi-Fi (SSID) phải từ 1 đến 32 ký tự!" }))
		return
	end

	local enc = normalize_enc(req.encryption or "psk2", req.key ~= "" and req.key or "keep")
	local key = tostring(req.key or ""):gsub("[\r\n]", "")
	if enc == "none" or trim(req.encryption) == "none" then
		enc = "none"
		key = ""
	else
		if key == "" and req.keep_key ~= false then
			key = uci_get(MESH_UCI .. ".mesh.custom_key")
			if key == "" then
				local cur = get_local_profile()
				key = (cur.key_5g ~= "" and cur.key_5g) or cur.key_2g
			end
		end
		if #key < 8 or #key > 63 then
			print(cjson.encode({ success = false, message = "Mật khẩu Wi-Fi phải từ 8 đến 63 ký tự!" }))
			return
		end
	end

	local cmds = {
		"/sbin/uci -q set " .. MESH_UCI .. ".mesh.wifi_sync_mode=custom",
		"/sbin/uci -q set " .. shq(MESH_UCI .. ".mesh.custom_ssid_2g=" .. s2),
		"/sbin/uci -q set " .. shq(MESH_UCI .. ".mesh.custom_ssid_5g=" .. s5),
		"/sbin/uci -q set " .. shq(MESH_UCI .. ".mesh.custom_encryption=" .. enc),
		"/sbin/uci -q set " .. shq(MESH_UCI .. ".mesh.custom_key=" .. key),
		"/sbin/uci -q commit " .. MESH_UCI
	}
	os.execute(table.concat(cmds, " && "))

	local changed = apply_profile_to_local({
		ssid_2g = s2, enc_2g = enc, key_2g = key,
		ssid_5g = s5, enc_5g = enc, key_5g = key
	})
	os.remove(PUB_HASH_FILE)

	print(cjson.encode({
		success   = true,
		sync_mode = "custom",
		changed   = changed,
		reload    = changed,
		message   = "Đã lưu và áp dụng Wi-Fi tùy chỉnh (" .. s2 .. " / " .. s5 .. ")!"
	}))
end

local action = arg[1] or "summary"
if action == "selftest" then
	cmd_selftest()
elseif action == "publish" then
	cmd_publish()
elseif action == "sync" then
	cmd_sync(arg[2], arg[3])
elseif action == "summary" then
	cmd_summary()
elseif action == "set_wifi" then
	cmd_set_wifi()
else
	io.stderr:write("Unknown action: " .. tostring(action) .. "\n")
	os.exit(1)
end
