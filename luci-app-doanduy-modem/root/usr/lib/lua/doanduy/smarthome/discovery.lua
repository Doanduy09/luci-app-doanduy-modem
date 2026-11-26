-- [VERIFIED-GOLDEN: smarthome-mod-discovery-v250 | 2026-11-26 | DO NOT MODIFY UNLESS TARGETED]
-- Scenario 06 (SmartHome) — Module 4/5: Universal IP Auto-Fingerprint, Fast Batch LAN Scan & Action Sanitizer
local net = require("doanduy.smarthome.net_json")
local store = require("doanduy.smarthome.store")
local cjson = net.cjson
local trim = net.trim
local now_ms = net.now_ms
local http_get_json = net.http_get_json
local http_request_lan = net.http_request_lan
local is_private_lan_ip = net.is_private_lan_ip
local parse_and_validate_lan_target = net.parse_and_validate_lan_target
local is_lan_http_url = net.is_lan_http_url
local tcp_probe_batch = net.tcp_probe_batch
local tcp_send_recv = net.tcp_send_recv
local sniff_tuya_udp = net.sniff_tuya_udp
local tcp_open = net.tcp_open
local is_esp32_host = store.is_esp32_host
local read_lan_tvs = store.read_lan_tvs
local HUB_HTTP = store.HUB_HTTP

-- =============================================================================
-- UNIVERSAL SMART DEVICE AUTO-DISCOVERY, FINGERPRINTING & UNLIMITED ACTIONS
-- =============================================================================

local PROBE_PORTS = { 80, 554, 5555, 6466, 6668, 8000, 8008, 8080, 8081, 8090, 8899, 8990, 55443 }

local ALLOWED_ACTION_KINDS = {
  http_get = true,
  http_post = true,
  tuya_dp = true,
  tcp_send = true,
  udp_send = true,
  open_url = true,
  ping = true,
}

local function decode_json_param(val)
  if type(val) == "table" then return val end
  if type(val) == "string" and val ~= "" then
    local ok, dec = pcall(cjson.decode, val)
    if ok and type(dec) == "table" then return dec end
  end
  return nil
end

local function sanitize_category(cat)
  local s = trim(cat):lower():gsub("[^a-z0-9_%-]", "")
  if s == "" then return "custom" end
  return s
end

local function infer_category_from_text(text, fallback)
  local t = (tostring(text or "")):lower()
  if t:find("alarm") or t:find("siren") or t:find("antitheft") or t:find("security") or t:find("trom") or t:find("chong") or t:find("coi") or t:find("pir") or t:find("motion") or t:find("sos") then
    return "security"
  elseif t:find("cam") or t:find("hikvision") or t:find("dahua") or t:find("ezviz") or t:find("imou") or t:find("tapo") or t:find("onvif") or t:find("nvr") or t:find("ipc") then
    return "camera"
  elseif t:find("light") or t:find("bulb") or t:find("lamp") or t:find("led") or t:find("wled") or t:find("yeelight") or t:find("den") or t:find("dimmer") then
    return "light"
  elseif t:find("plug") or t:find("socket") or t:find("outlet") or t:find("strip") or t:find("ocam") or t:find("relay") or t:find("switch") or t:find("congtac") then
    return "plug"
  elseif t:find("curtain") or t:find("blind") or t:find("shutter") or t:find("cover") or t:find("rem") or t:find("cuacuon") or t:find("cua_cuon") or t:find("gate") then
    return "curtain"
  elseif t:find("lock") or t:find("khoa") or t:find("door") then
    return "lock"
  elseif t:find("sensor") or t:find("temp") or t:find("hum") or t:find("smoke") or t:find("gas") or t:find("leak") then
    return "sensor"
  elseif t:find("pump") or t:find("bom") or t:find("valve") or t:find("water") or t:find("tuoi") then
    return "pump"
  elseif t:find("sound") or t:find("speaker") or t:find("bose") or t:find("jbl") or t:find("sonos") or t:find("audio") or t:find("loa") then
    return "audio"
  elseif t:find("fan") or t:find("quat") then
    return "fan"
  elseif t:find("tv") or t:find("tivi") or t:find("bravia") or t:find("aquos") or t:find("shield") then
    return "tv"
  end
  return fallback or "plug"
end

local function parse_action_dp_val(v)
  if type(v) == "boolean" or type(v) == "number" then return v end
  local s = trim(v)
  if s:lower() == "true" then return true end
  if s:lower() == "false" then return false end
  local n = tonumber(s)
  if n ~= nil then return n end
  return s
end

local function sanitize_action_item(a, idx)
  if type(a) ~= "table" then return nil end
  local kind = trim(a.kind or a.type):lower()
  if kind == "http" then
    local m = trim(a.method):upper()
    kind = (m == "POST") and "http_post" or "http_get"
  end
  if not ALLOWED_ACTION_KINDS[kind] then return nil end
  local label = trim(a.label):sub(1, 64)
  if label == "" then return nil end
  local aid = trim(a.id):gsub("[^a-zA-Z0-9_%-]", "")
  if aid == "" then aid = "act_" .. tostring(os.time()) .. "_" .. tostring(idx or 1) end
  local item = {
    id = aid,
    label = label,
    icon = trim(a.icon):sub(1, 8),
    kind = kind,
    style = trim(a.style):sub(1, 24),
  }
  if kind == "http_get" or kind == "http_post" or kind == "open_url" then
    local u = trim(a.url)
    if not is_lan_http_url(u) then return nil end
    item.url = u
    if kind == "http_post" then
      item.body = tostring(a.body or ""):sub(1, 2048)
    end
  elseif kind == "tuya_dp" then
    local dp = trim(a.dp):gsub("[^a-zA-Z0-9_%-]", "")
    if dp == "" then dp = "1" end
    item.dp = dp
    item.dp_val = parse_action_dp_val(a.dp_val)
  elseif kind == "tcp_send" or kind == "udp_send" then
    local tip = trim(a.ip)
    local tport = tonumber(a.port)
    if not is_private_lan_ip(tip, false) or not tport or tport < 1 or tport > 65535 then return nil end
    item.ip = tip
    item.port = math.floor(tport)
    item.payload = tostring(a.payload or ""):sub(1, 1024)
  end
  return item
end

local function sanitize_actions(raw_actions)
  local out = {}
  if type(raw_actions) ~= "table" then return out end
  for idx, a in ipairs(raw_actions) do
    local s = sanitize_action_item(a, idx)
    if s then out[#out + 1] = s end
  end
  return out
end

local function build_default_actions_for_category(cat, ip, http_port)
  local base = "http://" .. ip .. ((http_port and http_port ~= 80) and (":" .. tostring(http_port)) or "")
  if cat == "security" then
    return {
      { id = "arm",    label = "Bật Chống Trộm", icon = "🛡️", kind = "http_get", url = base .. "/arm", style = "success" },
      { id = "disarm", label = "Tắt Báo Động",   icon = "🔓", kind = "http_get", url = base .. "/disarm", style = "neutral" },
      { id = "sos",    label = "Hú Còi SOS",     icon = "🚨", kind = "http_get", url = base .. "/sos", style = "danger" },
      { id = "ping",   label = "Kiểm Tra Online", icon = "🩺", kind = "ping", style = "info" },
    }
  elseif cat == "curtain" then
    return {
      { id = "open",  label = "Mở Ra",    icon = "🪟", kind = "http_get", url = base .. "/open", style = "success" },
      { id = "stop",  label = "Dừng Lại", icon = "⏸️", kind = "http_get", url = base .. "/stop", style = "neutral" },
      { id = "close", label = "Đóng Lại", icon = "🔒", kind = "http_get", url = base .. "/close", style = "danger" },
    }
  elseif cat == "lock" then
    return {
      { id = "unlock", label = "Mở Khóa", icon = "🔓", kind = "http_get", url = base .. "/unlock", style = "success" },
      { id = "lock",   label = "Khóa Lại", icon = "🔐", kind = "http_get", url = base .. "/lock", style = "danger" },
      { id = "ping",   label = "Kiểm Tra", icon = "🩺", kind = "ping", style = "info" },
    }
  elseif cat == "camera" then
    return {
      { id = "web",  label = "Mở Trang Camera", icon = "🌐", kind = "open_url", url = base .. "/", style = "info" },
      { id = "ping", label = "Kiểm Tra Online", icon = "🩺", kind = "ping", style = "success" },
    }
  elseif cat == "sensor" then
    return {
      { id = "ping", label = "Đọc / Kiểm Tra Online", icon = "🩺", kind = "ping", style = "info" },
      { id = "web",  label = "Mở Trang Cảm Biến",     icon = "🌐", kind = "open_url", url = base .. "/", style = "neutral" },
    }
  end
  return {
    { id = "on",   label = "Bật", icon = "⚡", kind = "http_get", url = base .. "/on", style = "success" },
    { id = "off",  label = "Tắt", icon = "🛑", kind = "http_get", url = base .. "/off", style = "danger" },
    { id = "ping", label = "Kiểm Tra Online", icon = "🩺", kind = "ping", style = "info" },
  }
end

local function is_ip_or_mac_registered(reg, ip, mac)
  local lm = (mac or ""):lower()
  for _, c in ipairs(reg.controllers or {}) do
    if (ip ~= "" and c.ip == ip) or (lm ~= "" and (c.mac or ""):lower() == lm) then
      return true, "controller", c.name
    end
  end
  for _, d in ipairs(reg.devices or {}) do
    if (ip ~= "" and d.ip == ip) or (lm ~= "" and (d.mac or ""):lower() == lm) then
      return true, "device", d.name
    end
  end
  return false, nil, nil
end

local function fingerprint_ip(ip, hint_port, open_ports_set, lan_hosts, lan_tvs, voice_st, tuya_udp_map, reg)
  local host_entry = lan_hosts[ip] or {}
  local hname = trim(host_entry.name)
  local hmac = trim(host_entry.mac):lower()
  local online = (host_entry.online == true)
  local ports_list = {}
  local pset = open_ports_set or {}
  for p, is_open in pairs(pset) do
    if is_open then
      ports_list[#ports_list + 1] = p
      online = true
    end
  end
  table.sort(ports_list)
  local already, reg_kind, reg_name = is_ip_or_mac_registered(reg, ip, hmac)

  local profile = {
    ip = ip,
    mac = hmac,
    hostname = hname,
    online = online,
    open_ports = ports_list,
    already_added = already,
    registered_kind = reg_kind or "",
    registered_name = reg_name or "",
    target_type = "device",
    confidence = "generic",
    brand = "LAN / Tùy biến",
    suggested_room = "Phòng khách",
    needs_fields = {},
    capabilities = { "actions", "ping" },
    meta = { web_url = "http://" .. ip .. ((hint_port and hint_port ~= 80) and (":" .. tostring(hint_port)) or "") .. "/" },
  }

  -- 1. ESP32 Voice Puck
  local vc = (type(voice_st) == "table" and type(voice_st.esp32_clients) == "table") and voice_st.esp32_clients[ip] or nil
  if is_esp32_host(host_entry) or vc ~= nil then
    local suf = (hmac ~= "" and hmac:gsub(":", ""):sub(-6):upper()) or ip:match("%.(%d+)$") or "ESP32"
    profile.target_type = "controller"
    profile.confidence = "high"
    profile.detected_kind = "Mạch Giọng Nói ESP32-C3 (" .. suf .. ")"
    profile.suggested_driver = "esp32_voice"
    profile.suggested_category = "other"
    profile.suggested_name = (hname ~= "") and ("Mạch Giọng Nói " .. hname) or ("Mạch Giọng Nói ESP32-C3 (" .. suf .. ")")
    profile.suggested_room = "Phòng ngủ"
    profile.brand = "DOANDUY ESP32-C3"
    profile.what_it_can_do = "Thu âm & ra lệnh giọng nói trực tiếp cho Voice Hub OpenWrt qua UDP 8995 (điều khiển TV, máy lạnh, đèn, quạt bằng tiếng Việt)."
    profile.capabilities = { "voice_mic", "udp_8995" }
    profile.suggested_actions = {}
    return profile
  end

  -- 2. Android TV / DuyTV LAN
  local matched_tv = nil
  for _, tv in ipairs(lan_tvs or {}) do
    if tv.ip == ip then matched_tv = tv; break end
  end
  if matched_tv or pset[8990] or (pset[5555] and pset[6466]) or hname:lower():find("shield") or hname:lower():find("aquos") or hname:lower():find("bravia") then
    profile.confidence = "high"
    profile.detected_kind = matched_tv and ("Android TV — " .. matched_tv.name) or "Android TV / Google TV (LAN)"
    profile.suggested_driver = "android_tv"
    profile.suggested_category = "tv"
    profile.suggested_name = matched_tv and matched_tv.name or ((hname ~= "") and hname or ("Android TV (" .. ip .. ")"))
    profile.brand = (matched_tv and matched_tv.brand) or "Android TV"
    profile.what_it_can_do = "Mở YouTube, mở DuyTV, chỉnh âm lượng +/-, điều hướng Home/Back, bật hoặc đưa TV về chế độ ngủ ngay từ giao diện Router & Giọng nói."
    profile.capabilities = { "tv_remote", "voice_cmd" }
    profile.meta.tv_id = matched_tv and matched_tv.id or ("tv_" .. ip:gsub("%.", "_"))
    profile.suggested_actions = {}
    return profile
  end

  -- 3. Known Controller S06 Pro (by registry/cfg IP or MAC)
  for _, c in ipairs(reg.controllers or {}) do
    if c.kind == "tuya_ir" and ((c.ip == ip) or (hmac ~= "" and (c.mac or ""):lower() == hmac)) then
      profile.target_type = "controller"
      profile.confidence = "high"
      profile.detected_kind = "Cục Hồng Ngoại Tuya S06 Pro"
      profile.suggested_driver = "tuya_ir"
      profile.suggested_category = "ac"
      profile.suggested_name = c.name or "Cục Hồng Ngoại S06 Pro"
      profile.suggested_room = c.room or "Phòng ngủ"
      profile.brand = "Tuya S06 IR"
      profile.meta.device_id = c.device_id or ""
      profile.what_it_can_do = "Cục phát hồng ngoại trung tâm: điều khiển máy lạnh 11 hãng không cần học remote, TV, Quạt, Loa Soundbar & đọc nhiệt độ/độ ẩm phòng."
      profile.capabilities = { "ir_tx", "ir_learn", "temp_humidity" }
      profile.suggested_actions = {}
      return profile
    end
  end

  -- 4. Google Cast / Smart Soundbar / Speaker (port 8008 / 8090)
  if pset[8008] or pset[8090] then
    local info = pset[8008] and http_get_json("http://" .. ip .. ":8008/setup/eureka_info", 2) or nil
    local cast_name = (type(info) == "table" and trim(info.name or info.ssid)) or hname
    local inf_cat = infer_category_from_text(cast_name .. " " .. hname, "audio")
    profile.confidence = "high"
    profile.detected_kind = (inf_cat == "tv") and "Thiết bị TV / Google Cast" or "Loa / Soundbar Thông Minh LAN"
    profile.suggested_driver = "smart_actions"
    profile.suggested_category = inf_cat
    profile.suggested_name = (cast_name ~= "") and cast_name or ("Loa / Cast (" .. ip .. ")")
    profile.brand = (cast_name:lower():find("bose")) and "Bose" or "Google Cast / Audio"
    profile.what_it_can_do = "Theo dõi trạng thái trực tuyến của loa/Soundbar, mở nhanh cổng cấu hình nội bộ và gắn thêm nút điều khiển HTTP/TCP hoặc hồng ngoại tùy ý."
    profile.capabilities = { "actions", "ping" }
    local web_p = pset[80] and 80 or (pset[8090] and 8090 or 8008)
    profile.meta.web_url = "http://" .. ip .. ((web_p ~= 80) and (":" .. tostring(web_p)) or "") .. "/"
    profile.suggested_actions = {
      { id = "ping", label = "Kiểm Tra Kết Nối", icon = "🩺", kind = "ping", style = "info" },
      { id = "web",  label = "Mở Giao Diện Thiết Bị", icon = "🌐", kind = "open_url", url = profile.meta.web_url, style = "neutral" },
    }
    return profile
  end

  -- 4b. Fast-path IP Camera when RTSP 554 / ONVIF 8899 is open (skip 4 redundant HTTP probes)
  if pset[554] or pset[8899] or (pset[8000] and infer_category_from_text(hname, "other") == "camera") then
    profile.confidence = "high"
    profile.detected_kind = "Camera An Ninh IP (RTSP/ONVIF)"
    profile.suggested_driver = "camera_lan"
    profile.suggested_category = "camera"
    profile.suggested_name = (hname ~= "" and hname or ("Camera An Ninh (" .. ip .. ")"))
    profile.brand = "Camera IP / ONVIF"
    profile.meta.web_url = "http://" .. ip .. "/"
    profile.meta.rtsp_url = "rtsp://" .. ip .. ":554/"
    profile.what_it_can_do = "Mở nhanh giao diện xem Camera trên LAN, sao chép link luồng RTSP, kiểm tra Camera đang bật hay mất kết nối và gắn thêm nút bật còi/PTZ."
    profile.capabilities = { "web_ui", "rtsp", "ping", "actions" }
    profile.suggested_actions = build_default_actions_for_category("camera", ip, 80)
    return profile
  end

  -- 5. Active HTTP Probes (hint_port, 80, 8080, 8081)
  local http_ports = {}
  local seen_hp = {}
  local function add_hp(p) if p and not seen_hp[p] then seen_hp[p] = true; http_ports[#http_ports + 1] = p end end
  if hint_port and hint_port ~= 554 and hint_port ~= 55443 and hint_port ~= 6668 and hint_port ~= 8081 then add_hp(hint_port) end
  if pset[80] then add_hp(80) end
  if pset[8080] then add_hp(8080) end
  if pset[8000] then add_hp(8000) end

  for _, hp in ipairs(http_ports) do
    local base = "http://" .. ip .. ((hp ~= 80) and (":" .. tostring(hp)) or "")
    -- 5a. WLED
    local wled = http_get_json(base .. "/json/info", 2)
    if type(wled) == "table" and wled.ver and type(wled.leds) == "table" then
      local wname = trim(wled.name)
      profile.confidence = "high"
      profile.detected_kind = "Đèn LED Thông Minh WLED"
      profile.suggested_driver = "wled"
      profile.suggested_category = "light"
      profile.suggested_name = (wname ~= "") and wname or ("Đèn WLED (" .. ip .. ")")
      profile.brand = "WLED v" .. tostring(wled.ver)
      profile.meta.port = hp
      profile.meta.led_count = tonumber(wled.leds.count) or 0
      profile.meta.web_url = base .. "/"
      profile.what_it_can_do = "Bật/Tắt đèn ngay lập tức, kéo thanh chỉnh độ sáng 1–100%, mở trang hiệu ứng RGBW trực tiếp trên WLED."
      profile.capabilities = { "power", "brightness" }
      profile.suggested_actions = {
        { id = "web", label = "Mở Trang WLED", icon = "🎨", kind = "open_url", url = base .. "/", style = "info" },
      }
      return profile
    end

    -- 5b. Shelly Gen1 / Gen2 / Gen3
    local sh = http_get_json(base .. "/shelly", 2)
    if type(sh) == "table" and sh.mac and (sh.gen ~= nil or sh.type ~= nil or sh.model ~= nil) then
      local gen = tonumber(sh.gen) or 1
      local model = trim(sh.model or sh.type or "Shelly")
      local sname = trim(sh.name or model)
      local inf_cat = infer_category_from_text(model .. " " .. sname .. " " .. hname, "plug")
      if model:upper():find("DIMMER") or model:upper():find("BULB") or model:upper():find("RGBW") then inf_cat = "light"
      elseif model:upper():find("PLUG") then inf_cat = "plug"
      elseif model:upper():find("2PM") or model:upper():find("2%.5") then inf_cat = infer_category_from_text(sname .. " " .. hname, "plug") end
      profile.confidence = "high"
      profile.detected_kind = "Thiết bị Shelly Gen" .. tostring(gen) .. " (" .. model .. ")"
      profile.suggested_driver = "shelly"
      profile.suggested_category = inf_cat
      profile.suggested_name = (sname ~= "") and ("Shelly " .. sname) or ("Shelly " .. model)
      profile.brand = "Shelly Gen" .. tostring(gen)
      profile.meta.port = hp
      profile.meta.shelly_gen = gen
      profile.meta.model = model
      profile.meta.web_url = base .. "/"
      profile.what_it_can_do = "Bật/Tắt tải qua mạng LAN không cần đám mây (Shelly RPC Gen" .. tostring(gen) .. "), phản hồi trạng thái tức thì và mở giao diện cấu hình."
      profile.capabilities = (inf_cat == "light" and model:upper():find("DIMMER")) and { "power", "brightness" } or { "power" }
      profile.suggested_actions = {
        { id = "web", label = "Mở Trang Shelly", icon = "🌐", kind = "open_url", url = base .. "/", style = "info" },
      }
      return profile
    end

    -- 5c. Tasmota
    local tsm = http_get_json(base .. "/cm?cmnd=Status%200", 2)
    if type(tsm) == "table" and type(tsm.Status) == "table" and (tsm.StatusSTS ~= nil or tsm.StatusNET ~= nil) then
      local fname = (type(tsm.Status.FriendlyName) == "table" and trim(tsm.Status.FriendlyName[1])) or trim(tsm.Status.DeviceName)
      local ch_cnt = 1
      local sts = type(tsm.StatusSTS) == "table" and tsm.StatusSTS or {}
      for ch = 2, 4 do
        if sts["POWER" .. tostring(ch)] ~= nil then ch_cnt = ch end
      end
      local has_dim = (sts.Dimmer ~= nil)
      local inf_cat = infer_category_from_text((fname or "") .. " " .. hname, has_dim and "light" or "plug")
      profile.confidence = "high"
      profile.detected_kind = "Thiết bị Tasmota (" .. tostring(ch_cnt) .. " kênh)"
      profile.suggested_driver = "tasmota"
      profile.suggested_category = inf_cat
      profile.suggested_name = (fname ~= "") and fname or ("Tasmota (" .. ip .. ")")
      profile.brand = "Tasmota Wi-Fi"
      profile.meta.port = hp
      profile.meta.channels = ch_cnt
      profile.meta.has_dimmer = has_dim
      profile.meta.web_url = base .. "/"
      profile.what_it_can_do = (inf_cat == "security")
        and "Bật/Tắt hệ thống bảo vệ hoặc hú còi báo động qua Tasmota LAN + tùy chỉnh kịch bản lệnh bất kỳ."
        or ("Bật/Tắt " .. tostring(ch_cnt) .. " kênh công tắc qua LAN nội bộ" .. (has_dim and ", kéo thanh độ sáng 1–100%" or "") .. ", mở giao diện Tasmota.")
      profile.capabilities = has_dim and { "power", "brightness" } or { "power" }
      local acts = {
        { id = "web", label = "Mở Trang Tasmota", icon = "🌐", kind = "open_url", url = base .. "/", style = "info" },
      }
      if ch_cnt > 1 then
        for ch = 1, ch_cnt do
          acts[#acts + 1] = {
            id = "ch" .. tostring(ch) .. "_toggle",
            label = "Đảo Kênh " .. tostring(ch),
            icon = "🔁",
            kind = "http_get",
            url = base .. "/cm?cmnd=Power" .. tostring(ch) .. "%20Toggle",
            style = "neutral",
          }
        end
      end
      profile.suggested_actions = acts
      return profile
    end

    -- 5d. Generic HTTP body (ESPHome, Alarm/Anti-Theft, Camera Web, Generic IoT Web)
    local root_html = http_request_lan("GET", base .. "/", nil, 2, 4096)
    if root_html ~= "" then
      local low_html = root_html:lower()
      local title = trim(root_html:match("<title[^>]*>([^<]+)</title>") or "")
      local hint_txt = title .. " " .. hname .. " " .. low_html:sub(1, 2048)
      local inf_cat = infer_category_from_text(hint_txt, "custom")

      if low_html:find("esphome", 1, true) then
        profile.confidence = "high"
        profile.detected_kind = "Thiết bị ESPHome LAN"
        profile.suggested_driver = "smart_actions"
        profile.suggested_category = (inf_cat ~= "custom") and inf_cat or "sensor"
        profile.suggested_name = (title ~= "" and title or (hname ~= "" and hname or ("ESPHome (" .. ip .. ")")))
        profile.brand = "ESPHome"
        profile.meta.port = hp
        profile.meta.web_url = base .. "/"
        profile.what_it_can_do = "Kết nối trực tiếp giao diện ESPHome nội bộ, kiểm tra hoạt động và gắn thêm nút điều khiển HTTP POST/GET tùy ý (đèn, rơ-le, cảm biến, chống trộm)."
        profile.suggested_actions = build_default_actions_for_category(profile.suggested_category, ip, hp)
        return profile
      elseif inf_cat == "security" then
        profile.confidence = "medium"
        profile.detected_kind = "Thiết bị Chống Trộm / Báo Động LAN"
        profile.suggested_driver = "smart_actions"
        profile.suggested_category = "security"
        profile.suggested_name = (title ~= "" and title or (hname ~= "" and hname or ("Chống Trộm (" .. ip .. ")")))
        profile.brand = "An Ninh / Báo Động LAN"
        profile.meta.port = hp
        profile.meta.web_url = base .. "/"
        profile.what_it_can_do = "Bật bảo vệ (Arm), Tắt báo động (Disarm), kích hoạt hú còi khẩn cấp (SOS) và theo dõi trực tuyến thiết bị chống trộm."
        profile.capabilities = { "arm", "disarm", "sos", "ping" }
        profile.suggested_actions = build_default_actions_for_category("security", ip, hp)
        return profile
      elseif pset[554] or pset[8000] or pset[8899] or inf_cat == "camera" then
        profile.confidence = "high"
        profile.detected_kind = "Camera An Ninh IP (LAN)"
        profile.suggested_driver = "camera_lan"
        profile.suggested_category = "camera"
        profile.suggested_name = (title ~= "" and title or (hname ~= "" and hname or ("Camera IP (" .. ip .. ")")))
        profile.brand = "Camera IP / ONVIF"
        profile.meta.port = hp
        profile.meta.web_url = base .. "/"
        profile.meta.rtsp_url = "rtsp://" .. ip .. ":554/"
        profile.what_it_can_do = "Mở nhanh giao diện xem Camera trên LAN, sao chép link luồng RTSP, kiểm tra Camera đang bật hay mất kết nối và gắn thêm nút bật còi/PTZ."
        profile.capabilities = { "web_ui", "rtsp", "ping", "actions" }
        profile.suggested_actions = build_default_actions_for_category("camera", ip, hp)
        return profile
      else
        profile.confidence = "medium"
        profile.detected_kind = (title ~= "") and ("Thiết bị Web LAN: " .. title:sub(1, 36)) or "Thiết bị Web / IoT LAN (Cổng HTTP " .. tostring(hp) .. ")"
        profile.suggested_driver = "smart_actions"
        profile.suggested_category = inf_cat
        profile.suggested_name = (title ~= "" and title:sub(1, 48)) or ((hname ~= "" and hname or ("Thiết bị IoT (" .. ip .. ")")))
        profile.brand = "HTTP / IoT LAN"
        profile.meta.port = hp
        profile.meta.web_url = base .. "/"
        profile.what_it_can_do = "Tạo thẻ điều khiển không giới hạn nút lệnh (Bật/Tắt/HTTP/TCP/Mở trang Web). Bạn có thể chọn loại thiết bị bất kỳ và đổi đường dẫn lệnh theo ý muốn."
        profile.suggested_actions = build_default_actions_for_category(inf_cat, ip, hp)
        return profile
      end
    end
  end

  -- 5e. Sonoff DIY (port 8081)
  if pset[8081] then
    local sres = http_request_lan("POST", "http://" .. ip .. ":8081/zeroconf/info", '{"deviceid":"","data":{}}', 2, 8192)
    if sres and sres:find('"error":0', 1, true) then
      profile.confidence = "high"
      profile.detected_kind = "Công Tắc / Ổ Cắm Sonoff DIY (Port 8081)"
      profile.suggested_driver = "sonoff_diy"
      profile.suggested_category = infer_category_from_text(hname, "plug")
      profile.suggested_name = (hname ~= "" and hname or ("Sonoff DIY (" .. ip .. ")"))
      profile.brand = "Sonoff DIY"
      profile.meta.port = 8081
      profile.what_it_can_do = "Bật/Tắt tức thì qua giao thức Sonoff DIY cục bộ trên cổng 8081 không cần Internet."
      profile.capabilities = { "power" }
      profile.suggested_actions = {}
      return profile
    end
  end

  -- 6. Yeelight Wi-Fi Bulb/Light (port 55443)
  if pset[55443] then
    local yres = tcp_send_recv(ip, 55443, '{"id":1,"method":"get_prop","params":["power","bright","name"]}\r\n', 600)
    profile.confidence = (yres and yres:find("result", 1, true)) and "high" or "medium"
    profile.detected_kind = "Đèn Thông Minh Yeelight Wi-Fi"
    profile.suggested_driver = "yeelight"
    profile.suggested_category = "light"
    profile.suggested_name = (hname ~= "" and hname or ("Đèn Yeelight (" .. ip .. ")"))
    profile.brand = "Yeelight"
    profile.meta.port = 55443
    profile.what_it_can_do = "Bật/Tắt đèn tức thì và kéo thanh chỉnh độ sáng 1–100% trực tiếp qua TCP cổng 55443."
    profile.capabilities = { "power", "brightness" }
    profile.suggested_actions = {}
    return profile
  end

  -- 7. Camera by RTSP/ONVIF Port or Hostname (even when port 80 is closed)
  local cam_hint = infer_category_from_text(hname, "other")
  if pset[554] or pset[8000] or pset[8899] or cam_hint == "camera" then
    profile.confidence = pset[554] and "high" or "medium"
    profile.detected_kind = "Camera An Ninh IP (RTSP/ONVIF)"
    profile.suggested_driver = "camera_lan"
    profile.suggested_category = "camera"
    profile.suggested_name = (hname ~= "" and hname or ("Camera An Ninh (" .. ip .. ")"))
    profile.brand = "Camera IP"
    profile.meta.rtsp_url = "rtsp://" .. ip .. ":554/"
    profile.what_it_can_do = "Giám sát trạng thái trực tuyến Camera trên mạng nhà, mở Web quản trị Camera và sao chép nhanh địa chỉ luồng RTSP."
    profile.capabilities = { "web_ui", "rtsp", "ping", "actions" }
    profile.suggested_actions = build_default_actions_for_category("camera", ip, 80)
    return profile
  end

  -- 8. Tuya Local (TCP 6668, UDP 6666/6667, or lwip hostname)
  local tudp = tuya_udp_map and tuya_udp_map[ip] or nil
  if pset[6668] or tudp or hname:lower():find("^lwip") then
    local tuya_cat = infer_category_from_text(hname, "plug")
    if tuya_cat == "other" then tuya_cat = "plug" end
    profile.confidence = (pset[6668] or tudp) and "high" or "medium"
    profile.detected_kind = "Thiết bị Tuya Smart LAN (Port 6668 / v3.5)"
    profile.suggested_driver = "tuya_switch"
    profile.suggested_category = tuya_cat
    profile.suggested_name = (hname ~= "" and not hname:lower():find("^lwip")) and hname or ("Thiết bị Tuya (" .. ip .. ")")
    profile.brand = "Tuya Wi-Fi Local"
    profile.needs_fields = { "device_id", "local_key", "dp" }
    profile.meta.tuya_device_id = (tudp and tudp.gwId) or ""
    profile.meta.tuya_version = (tudp and tudp.version) or "3.5"
    profile.what_it_can_do = "Điều khiển trực tiếp thiết bị Tuya (Đèn, Ổ cắm, Công tắc nhiều nút, Báo động, Rèm...) qua LAN siêu nhanh; chỉ cần điền Device ID & Local Key 16 ký tự (hoặc chuyển sang Cục S06 nếu là bộ phát hồng ngoại)."
    profile.capabilities = { "power", "tuya_dp", "actions" }
    profile.suggested_actions = {}
    return profile
  end

  -- 9. Universal Fallback (ANY IP — Unlimited Categories & Custom Actions)
  local fallback_cat = infer_category_from_text(hname, "custom")
  profile.confidence = "generic"
  profile.detected_kind = "Thiết bị Thông Minh / Tự Định Nghĩa (Không Giới Hạn)"
  profile.suggested_driver = "smart_actions"
  profile.suggested_category = fallback_cat
  profile.suggested_name = (hname ~= "" and hname or ("Thiết bị Thông Minh (" .. ip .. ")"))
  profile.brand = "LAN / Tùy biến vô hạn"
  profile.what_it_can_do = "Chưa có chữ ký tự động riêng — bạn vẫn có thể chọn BẤT KỲ loại nào (Đèn, Ổ cắm, Chống trộm, Cảm biến, Rèm, Khóa, hoặc Tự đặt tên mới) và gắn vô hạn nút lệnh HTTP / Tuya DP / TCP / UDP ngay lập tức."
  profile.suggested_actions = build_default_actions_for_category(fallback_cat, ip, hint_port or 80)
  return profile
end


local function scan_hubs(cfg, lan_hosts)
  local _res = nil
  local function out_json(t) _res = t end
  ;(function()
    if cfg.ip and cfg.ip ~= "" and not lan_hosts[cfg.ip] then
      lan_hosts[cfg.ip] = { ip = cfg.ip, mac = (cfg.mac or ""):lower(), name = "S06 Pro", online = true }
    end
    local tuya_devs, esp_nodes = {}, {}
    for ip, h in pairs(lan_hosts) do
      local hn = (h.name or ""):lower()
      if hn:find("esp32", 1, true) then
        esp_nodes[#esp_nodes + 1] = {
          ip = ip, mac = h.mac or "", name = h.name, kind = "esp32_voice",
          online = h.online and true or false,
        }
      elseif tcp_open(ip, 6668, 200) then
        tuya_devs[#tuya_devs + 1] = {
          ip = ip, mac = h.mac or "", kind = "tuya_ir",
          name = (h.name and h.name ~= "") and h.name or ("Tuya LAN (" .. ip .. ")"),
          is_current = (ip == cfg.ip),
        }
      end
    end
    out_json({
      ok = true,
      hubs = tuya_devs,
      tuya_devices = tuya_devs,
      esp32_nodes = esp_nodes,
      lan_tvs = read_lan_tvs(),
    })

  end)()
  return _res
end

local function probe_ip(params, reg, lan_hosts)
  local _res = nil
  local function out_json(t) _res = t end
  ;(function()
    local target_ip, hint_port, _, perr = parse_and_validate_lan_target(params.ip)
    if not target_ip then
      out_json({ ok = false, message = perr })
      return
    end
    local targets = {}
    local seen_p = {}
    if hint_port then
      seen_p[hint_port] = true
      targets[#targets + 1] = { ip = target_ip, port = hint_port }
    end
    for _, p in ipairs(PROBE_PORTS) do
      if not seen_p[p] then
        seen_p[p] = true
        targets[#targets + 1] = { ip = target_ip, port = p }
      end
    end
    local open_map = tcp_probe_batch(targets, 650)
    local pset = open_map[target_ip] or {}
    local has_http = (pset[80] or pset[8080] or pset[8008] or (hint_port and pset[hint_port])) and true or false
    local tuya_udp = (not has_http and (pset[6668] or not next(pset))) and sniff_tuya_udp(450) or {}
    local lan_tvs = read_lan_tvs()
    local voice_st = http_get_json(HUB_HTTP .. "/status", 1)
    local profile = fingerprint_ip(target_ip, hint_port, pset, lan_hosts, lan_tvs, voice_st, tuya_udp, reg)
    out_json({ ok = true, profile = profile })

  end)()
  return _res
end

local function scan_lan_smart_devices(reg, lan_hosts)
  local _res = nil
  local function out_json(t) _res = t end
  ;(function()
    local t0 = now_ms()
    local lan_tvs = read_lan_tvs()
    local voice_st = http_get_json(HUB_HTTP .. "/status", 1)
    local tuya_udp = sniff_tuya_udp(450)
    local cand_map, cand_ips = {}, {}
    local function add_cand(ip)
      if is_private_lan_ip(ip, false) and not cand_map[ip] then
        cand_map[ip] = true
        cand_ips[#cand_ips + 1] = ip
      end
    end
    for ip, h in pairs(lan_hosts) do
      if h.online or (h.name and h.name ~= "") or tuya_udp[ip] then add_cand(ip) end
    end
    for _, tv in ipairs(lan_tvs) do add_cand(tv.ip) end
    for _, c in ipairs(reg.controllers or {}) do add_cand(c.ip) end
    for ip, _ in pairs(tuya_udp) do add_cand(ip) end

    local scan_ports = { 80, 554, 5555, 6466, 6668, 8008, 8080, 8081, 8090, 8990, 55443 }
    local targets = {}
    for idx = 1, math.min(#cand_ips, 36) do
      local ip = cand_ips[idx]
      for _, p in ipairs(scan_ports) do
        targets[#targets + 1] = { ip = ip, port = p }
      end
    end
    local open_map = tcp_probe_batch(targets, 700)
    local profiles = {}
    local conf_rank = { high = 3, medium = 2, generic = 1 }
    for idx = 1, math.min(#cand_ips, 36) do
      local ip = cand_ips[idx]
      local h = lan_hosts[ip] or {}
      local pset = open_map[ip] or {}
      local hcat = infer_category_from_text(h.name or "", "none")
      local is_registered = is_ip_or_mac_registered(reg, ip, h.mac)
      if next(pset) or tuya_udp[ip] or is_esp32_host(h) or is_registered or hcat == "camera" or hcat == "security" then
        profiles[#profiles + 1] = fingerprint_ip(ip, nil, pset, lan_hosts, lan_tvs, voice_st, tuya_udp, reg)
      end
    end
    table.sort(profiles, function(a, b)
      local ra, rb = conf_rank[a.confidence] or 0, conf_rank[b.confidence] or 0
      if ra ~= rb then return ra > rb end
      if (a.online and not b.online) then return true end
      if (b.online and not a.online) then return false end
      return tostring(a.ip) < tostring(b.ip)
    end)
    out_json({
      ok = true,
      devices = profiles,
      total_lan_hosts = #cand_ips,
      scanned_ms = math.max(1, now_ms() - t0),
    })

  end)()
  return _res
end

return {
  PROBE_PORTS = PROBE_PORTS,
  ALLOWED_ACTION_KINDS = ALLOWED_ACTION_KINDS,
  decode_json_param = decode_json_param,
  sanitize_category = sanitize_category,
  infer_category_from_text = infer_category_from_text,
  parse_action_dp_val = parse_action_dp_val,
  sanitize_action_item = sanitize_action_item,
  sanitize_actions = sanitize_actions,
  build_default_actions_for_category = build_default_actions_for_category,
  is_ip_or_mac_registered = is_ip_or_mac_registered,
  fingerprint_ip = fingerprint_ip,
  scan_hubs = scan_hubs,
  probe_ip = probe_ip,
  scan_lan_smart_devices = scan_lan_smart_devices,
}
-- [/VERIFIED-GOLDEN]
