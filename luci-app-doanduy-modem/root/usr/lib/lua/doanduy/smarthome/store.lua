-- [VERIFIED-GOLDEN: smarthome-mod-store-v250 | 2026-11-26 | DO NOT MODIFY UNLESS TARGETED]
-- Scenario 06 (SmartHome) — Module 2/5: Zero-Leak Key Vault (chmod 600), LAN Snapshot & v2 Registry
local net = require("doanduy.smarthome.net_json")
local cjson = net.cjson
local read_file = net.read_file
local write_atomic = net.write_atomic
local trim = net.trim
local url_encode = net.url_encode
local http_get_json = net.http_get_json
local ok_ac, ac_ir = pcall(require, "ac_ir_protocols")

local S06_CFG_FILE  = "/etc/duytv_s06_config.json"
local DEVICES_FILE  = "/etc/config/doanduy_smarthome.json"
local KEYS_FILE     = "/etc/config/doanduy_smarthome_keys.json"
local HUB_DEV_FILE  = "/etc/duytv_lan_devices.json"
local HUB_HTTP      = "http://127.0.0.1:8996"

-- =============================================================================
-- ZERO-LEAK KEY VAULT & LAN SNAPSHOT
-- =============================================================================

local function load_s06_cfg()
  local cfg = {
    ip = "192.168.1.130",
    mac = "20:f1:b2:fa:76:27",
    device_id = "a3fc144d9c06ae63b5bqj0",
    version = "3.5",
    local_key = "",
    control_type = 1,
    ac_brand = "lg2",
    ac_temp = 26,
    ir_codes = {},
  }
  local raw = read_file(S06_CFG_FILE)
  if raw and raw ~= "" then
    local ok, dec = pcall(cjson.decode, raw)
    if ok and type(dec) == "table" then
      for k, v in pairs(dec) do cfg[k] = v end
    end
  end
  if type(cfg.ir_codes) ~= "table" then cfg.ir_codes = {} end
  return cfg
end

local function load_key_vault()
  local raw = read_file(KEYS_FILE)
  if raw and raw ~= "" then
    local ok, dec = pcall(cjson.decode, raw)
    if ok and type(dec) == "table" then return dec end
  end
  return {}
end

local function save_key_vault(kv)
  write_atomic(KEYS_FILE, cjson.encode(kv), "600")
end

local function set_entity_key(entity_id, local_key)
  if not entity_id or entity_id == "" or not local_key or #local_key ~= 16 then return end
  local kv = load_key_vault()
  kv[entity_id] = local_key
  save_key_vault(kv)
end

local function get_entity_key(entity_id, cfg)
  local kv = load_key_vault()
  if kv[entity_id] and #(kv[entity_id]) == 16 then return kv[entity_id] end
  if entity_id == "s06_default" and cfg and #(cfg.local_key or "") == 16 then
    return cfg.local_key
  end
  return ""
end

local function read_lan_hosts()
  local hosts = {}
  local dl = read_file("/tmp/dhcp.leases") or ""
  for line in dl:gmatch("[^\r\n]+") do
    local _, mac, ip, hname = line:match("^(%d+)%s+(%S+)%s+(%S+)%s+(%S+)")
    if ip and mac and ip:match("^192%.168%.%d+%.%d+$") and ip ~= "192.168.1.1" then
      hosts[ip] = { ip = ip, mac = mac:lower(), name = (hname ~= "*") and hname or "", online = false }
    end
  end
  local arp = read_file("/proc/net/arp") or ""
  for line in arp:gmatch("[^\r\n]+") do
    local ip, flags, mac = line:match("^(192%.168%.%d+%.%d+)%s+%S+%s+(%S+)%s+([%x:]+)")
    if ip and mac and mac ~= "00:00:00:00:00:00" and ip ~= "192.168.1.1" then
      local cur = hosts[ip] or { ip = ip, name = "" }
      cur.mac = mac:lower()
      cur.online = (flags == "0x2")
      hosts[ip] = cur
    end
  end
  local np = io.popen("ip -4 neigh show 2>/dev/null")
  if np then
    local nraw = np:read("*a") or ""
    np:close()
    for line in nraw:gmatch("[^\r\n]+") do
      local nip, nmac, nst = line:match("^(192%.168%.%d+%.%d+)%s+dev%s+%S+%s+lladdr%s+([%x:]+)%s+(%u+)")
      if not nip then
        nip, nst = line:match("^(192%.168%.%d+%.%d+)%s+dev%s+%S+%s+(%u+)")
      end
      if nip and nip ~= "192.168.1.1" and nst then
        local cur = hosts[nip] or { ip = nip, mac = "", name = "" }
        if nmac and nmac ~= "" then cur.mac = nmac:lower() end
        cur.neigh_state = nst
        if nst == "REACHABLE" or nst == "DELAY" or nst == "PROBE" or nst == "STALE" then
          cur.online = true
        elseif nst == "FAILED" or nst == "INCOMPLETE" then
          cur.online = false
        end
        hosts[nip] = cur
      end
    end
  end
  return hosts
end

-- =============================================================================
-- MULTI-CONTROLLER & MULTI-PROTOCOL STORE (v2, auto-migrates v1 cleanly)
-- =============================================================================

local function is_esp32_host(h)
  if type(h) ~= "table" then return false end
  local hn = (h.name or ""):lower()
  local mac = (h.mac or ""):lower()
  if hn:find("esp32", 1, true) then return true end
  if mac:match("^3c:0f:02:") then return true end
  return false
end

local function build_default_registry(cfg, lan_hosts)
  local br = cfg.ac_brand or "lg2"
  local label = (ok_ac and ac_ir.get_brand_info(br).label) or "LG Inverter (Chuẩn mới LG2)"
  local ctrls = {
    {
      id = "s06_default",
      kind = "tuya_ir",
      name = "Cục Hồng Ngoại S06 Pro",
      room = "Phòng ngủ",
      ip = cfg.ip or "192.168.1.130",
      mac = (cfg.mac or ""):lower(),
      device_id = cfg.device_id or "a3fc144d9c06ae63b5bqj0",
      control_type = tonumber(cfg.control_type) or 1,
      is_default = true,
    }
  }
  local esp_idx = 0
  for ip, h in pairs(lan_hosts) do
    if is_esp32_host(h) then
      esp_idx = esp_idx + 1
      local suf = (h.mac or ""):gsub(":", ""):sub(-6):upper()
      ctrls[#ctrls + 1] = {
        id = "esp32_" .. suf:lower(),
        kind = "esp32_voice",
        name = "Mạch Giọng Nói ESP32-C3 #" .. tostring(esp_idx) .. ((suf ~= "") and (" (" .. suf .. ")") or ""),
        room = (esp_idx == 1) and "Phòng ngủ" or "Phòng khách",
        ip = ip,
        mac = h.mac,
        port = 8995,
      }
    end
  end
  local devs = {
    {
      id = "ac_default_1",
      driver = "tuya_ir_ac",
      type = "ac",
      controller_id = "s06_default",
      name = "Máy lạnh " .. trim(label:match("^([^%(]+)") or "LG Inverter"),
      room = "Phòng ngủ",
      category = "ac",
      brand = br,
      brand_label = label,
      source = "builtin",
      state = {
        power = cfg.ac_power and true or false,
        temp = tonumber(cfg.ac_temp) or 26,
        mode = cfg.ac_mode or "cool",
        fan = cfg.ac_fan or "auto",
        swing = cfg.ac_swing and true or false,
      },
      buttons = {},
    }
  }
  return { version = 2, controllers = ctrls, devices = devs }
end

local function load_registry(cfg, lan_hosts)
  local raw = read_file(DEVICES_FILE)
  local kv = load_key_vault()
  if raw and raw ~= "" then
    local ok, dec = pcall(cjson.decode, raw)
    if ok and type(dec) == "table" and type(dec.devices) == "table" then
      local changed = false
      if type(dec.controllers) ~= "table" or #dec.controllers == 0 then
        local def = build_default_registry(cfg, lan_hosts)
        dec.controllers = def.controllers
        dec.version = 2
        changed = true
      end
      -- Auto-discover any new ESP32 voice pucks not yet registered
      local known_macs = {}
      for _, c in ipairs(dec.controllers) do
        if c.mac and c.mac ~= "" then known_macs[c.mac:lower()] = true end
      end
      for ip, h in pairs(lan_hosts) do
        if is_esp32_host(h) and h.mac ~= "" and not known_macs[h.mac:lower()] then
          known_macs[h.mac:lower()] = true
          local suf = h.mac:gsub(":", ""):sub(-6):upper()
          dec.controllers[#dec.controllers + 1] = {
            id = "esp32_" .. suf:lower(),
            kind = "esp32_voice",
            name = "Mạch Giọng Nói ESP32-C3 (" .. suf .. ")",
            room = "Phòng khách",
            ip = ip,
            mac = h.mac,
          }
          changed = true
        end
      end
      for _, d in ipairs(dec.devices) do
        d.name = trim(d.name)
        if not d.driver then
          d.driver = (d.type == "ac") and "tuya_ir_ac" or "tuya_ir_remote"
          changed = true
        end
        if (d.driver == "tuya_ir_ac" or d.driver == "tuya_ir_remote" or d.driver == "custom_ir") and not d.controller_id then
          d.controller_id = "s06_default"
          changed = true
        end
        if d.local_key and d.local_key ~= "" then
          set_entity_key(d.id, d.local_key)
          d.local_key = nil
          changed = true
        end
      end
      if changed then write_atomic(DEVICES_FILE, cjson.encode(dec), "600") end
      return dec
    end
  end
  local seeded = build_default_registry(cfg, lan_hosts)
  if #(cfg.local_key or "") == 16 and not kv["s06_default"] then
    set_entity_key("s06_default", cfg.local_key)
  end
  write_atomic(DEVICES_FILE, cjson.encode(seeded), "600")
  return seeded
end

local function save_registry(reg)
  write_atomic(DEVICES_FILE, cjson.encode({ version = 2, controllers = reg.controllers or {}, devices = reg.devices or {} }), "600")
end

local function find_controller(reg, cid)
  for _, c in ipairs(reg.controllers or {}) do
    if c.id == cid then return c end
  end
  return (reg.controllers or {})[1]
end

local function heal_controller_ip(ctrl, lan_hosts, cfg)
  local tgt_mac = trim(ctrl.mac or ""):lower()
  if tgt_mac ~= "" then
    for ip, h in pairs(lan_hosts) do
      if (h.mac or ""):lower() == tgt_mac then
        ctrl.ip = ip
        break
      end
    end
  end
  local lkey = get_entity_key(ctrl.id, cfg)
  return ctrl.ip, ctrl.device_id, lkey, tonumber(ctrl.control_type) or 1
end

-- =============================================================================
-- VOICE HUB SYNC & PUBLIC VIEW SANITIZER (Zero-Leak)
-- =============================================================================

local function sync_primary_cfg(patch)
  local cfg = load_s06_cfg()
  for k, v in pairs(patch) do cfg[k] = v end
  write_atomic(S06_CFG_FILE, cjson.encode(cfg), "600")
  if patch.ac_brand then
    http_get_json(HUB_HTTP .. "/s06/brand?brand=" .. url_encode(patch.ac_brand), 2)
  end
end

local function read_lan_tvs()
  local tvs = {}
  local raw = read_file(HUB_DEV_FILE)
  if raw and raw ~= "" then
    local ok, dec = pcall(cjson.decode, raw)
    if ok and type(dec) == "table" then
      for _, tv in ipairs(dec) do
        tvs[#tvs + 1] = { id = tv.id, name = tv.name, brand = tv.brand, ip = tv.ip }
      end
    end
  end
  return tvs
end

local function build_public_controllers(reg, cfg, lan_hosts, probe_primary)
  local kv = load_key_vault()
  local hub_st = probe_primary and http_get_json(HUB_HTTP .. "/s06/status?probe=1", 2) or nil
  local voice_st = probe_primary and http_get_json(HUB_HTTP .. "/status", 2) or nil
  local now_s = (type(voice_st) == "table" and tonumber(voice_st.now_s)) or os.time()
  if type(voice_st) == "table" and type(voice_st.esp32_clients) == "table" then
    local known_ips, known_macs = {}, {}
    for _, c in ipairs(reg.controllers or {}) do
      if c.ip and c.ip ~= "" then known_ips[c.ip] = true end
      if c.mac and c.mac ~= "" then known_macs[c.mac:lower()] = true end
    end
    local added = false
    for vip, _ in pairs(voice_st.esp32_clients) do
      local he = lan_hosts[vip]
      local vmac = (he and he.mac or ""):lower()
      if not known_ips[vip] and (vmac == "" or not known_macs[vmac]) then
        local suf = (vmac ~= "" and vmac:gsub(":", ""):sub(-6):upper()) or vip:match("%.(%d+)$") or "UDP"
        reg.controllers[#reg.controllers + 1] = {
          id = "esp32_" .. suf:lower(),
          kind = "esp32_voice",
          name = "Mạch Giọng Nói ESP32-C3 (" .. suf .. ")",
          room = "Phòng ngủ",
          ip = vip,
          mac = vmac,
          port = 8995,
        }
        known_ips[vip] = true
        if vmac ~= "" then known_macs[vmac] = true end
        added = true
      end
    end
    if added then save_registry(reg) end
  end
  local out = {}
  for _, c in ipairs(reg.controllers or {}) do
    local ip = c.ip or ""
    local mac = (c.mac or ""):lower()
    local h_entry = (ip ~= "" and lan_hosts[ip]) or nil
    if not h_entry and mac ~= "" then
      for hip, h in pairs(lan_hosts) do
        if (h.mac or ""):lower() == mac then ip = hip; h_entry = h; break end
      end
    elseif h_entry and mac ~= "" and (h_entry.mac or "") ~= "" and h_entry.mac:lower() ~= mac then
      for hip, h in pairs(lan_hosts) do
        if (h.mac or ""):lower() == mac then ip = hip; h_entry = h; break end
      end
    end
    local has_key = (kv[c.id] and #kv[c.id] == 16) or (c.id == "s06_default" and #(cfg.local_key or "") == 16)
    local item = {
      id = c.id,
      kind = c.kind or "tuya_ir",
      name = c.name or c.id,
      room = c.room or "Phòng khách",
      ip = ip,
      mac = mac,
      device_id = c.device_id or "",
      control_type = tonumber(c.control_type) or 1,
      has_key = has_key and true or false,
      online = (h_entry and h_entry.online) and true or false,
      live_ok = (h_entry and h_entry.online) and true or false,
      is_default = c.is_default and true or false,
    }
    if item.kind == "esp32_voice" then
      local vc = (type(voice_st) == "table" and type(voice_st.esp32_clients) == "table" and ip ~= "") and voice_st.esp32_clients[ip] or nil
      local ago = (vc and tonumber(vc.last_seen_s) and tonumber(vc.last_seen_s) > 0) and math.max(0, now_s - tonumber(vc.last_seen_s)) or nil
      local voice_active = (ago ~= nil and ago <= 180)
      item.voice_active = voice_active
      item.online = voice_active or item.online
      item.live_ok = item.online
      item.last_seen_ago_s = ago
      item.pings = vc and tonumber(vc.pings) or 0
      item.packets = vc and tonumber(vc.packets) or 0
      item.last_text = (vc and type(vc.last_text) == "string") and vc.last_text or ""
      if voice_active then
        item.status_label = "Đang hoạt động • Đang nghe"
      elseif item.online then
        item.status_label = "Đang hoạt động • Wi-Fi LAN OK"
      else
        item.status_label = "Ngắt kết nối / Tắt nguồn"
      end
    else
      if c.id == "s06_default" and type(hub_st) == "table" and hub_st.ip then
        item.ip = hub_st.ip
        item.live_ok = hub_st.live_ok and true or false
        item.online = item.live_ok or item.online
        item.ac_brand = hub_st.ac_brand
        if type(hub_st.dps) == "table" then
          local t = tonumber(hub_st.dps["101"] or hub_st.dps["1"])
          local hum = tonumber(hub_st.dps["102"] or hub_st.dps["2"])
          if t then item.temp_c = tonumber(string.format("%.1f", (t > 80) and (t / 10.0) or t)) end
          if hum then item.humidity = math.floor(hum) end
        end
      end
      item.status_label = item.live_ok and "Đang hoạt động • LAN OK" or (item.online and "Đã kết nối Wi-Fi" or "Ngắt kết nối")
    end
    out[#out + 1] = item
  end
  return out, (type(voice_st) == "table" or type(hub_st) == "table"), voice_st
end

return {
  S06_CFG_FILE = S06_CFG_FILE,
  DEVICES_FILE = DEVICES_FILE,
  KEYS_FILE = KEYS_FILE,
  HUB_DEV_FILE = HUB_DEV_FILE,
  HUB_HTTP = HUB_HTTP,
  load_s06_cfg = load_s06_cfg,
  load_key_vault = load_key_vault,
  save_key_vault = save_key_vault,
  set_entity_key = set_entity_key,
  get_entity_key = get_entity_key,
  read_lan_hosts = read_lan_hosts,
  is_esp32_host = is_esp32_host,
  build_default_registry = build_default_registry,
  load_registry = load_registry,
  save_registry = save_registry,
  find_controller = find_controller,
  heal_controller_ip = heal_controller_ip,
  sync_primary_cfg = sync_primary_cfg,
  read_lan_tvs = read_lan_tvs,
  build_public_controllers = build_public_controllers,
}
-- [/VERIFIED-GOLDEN]
