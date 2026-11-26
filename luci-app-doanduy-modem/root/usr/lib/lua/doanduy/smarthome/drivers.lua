-- [VERIFIED-GOLDEN: smarthome-mod-drivers-v250 | 2026-11-26 | DO NOT MODIFY UNLESS TARGETED]
-- Scenario 06 (SmartHome) — Module 5/5: Multi-Protocol Execution Drivers (12 Protocols + Unlimited Actions)
local net = require("doanduy.smarthome.net_json")
local store = require("doanduy.smarthome.store")
local catalog = require("doanduy.smarthome.catalog")
local discovery = require("doanduy.smarthome.discovery")

local cjson = net.cjson
local write_atomic = net.write_atomic
local trim = net.trim
local url_encode = net.url_encode
local now_ms = net.now_ms
local http_fetch_raw = net.http_fetch_raw
local http_get_json = net.http_get_json
local http_request_lan = net.http_request_lan
local is_private_lan_ip = net.is_private_lan_ip
local is_lan_http_url = net.is_lan_http_url
local tcp_probe_batch = net.tcp_probe_batch
local tcp_send_recv = net.tcp_send_recv
local udp_send_once = net.udp_send_once

local S06_CFG_FILE = store.S06_CFG_FILE
local HUB_HTTP = store.HUB_HTTP
local load_s06_cfg = store.load_s06_cfg
local load_key_vault = store.load_key_vault
local save_key_vault = store.save_key_vault
local set_entity_key = store.set_entity_key
local get_entity_key = store.get_entity_key
local save_registry = store.save_registry
local find_controller = store.find_controller
local heal_controller_ip = store.heal_controller_ip
local sync_primary_cfg = store.sync_primary_cfg
local read_lan_tvs = store.read_lan_tvs
local build_public_controllers = store.build_public_controllers

local BUILTIN_BY_ID = catalog.BUILTIN_BY_ID
local fetch_irdb_csv_buttons = catalog.fetch_irdb_csv_buttons
local infer_irdb_category = catalog.infer_irdb_category

local decode_json_param = discovery.decode_json_param
local sanitize_category = discovery.sanitize_category
local sanitize_action_item = discovery.sanitize_action_item
local sanitize_actions = discovery.sanitize_actions
local build_default_actions_for_category = discovery.build_default_actions_for_category

local ok_tuya, tuya_v35 = pcall(require, "tuya_v35_local")
local ok_ac, ac_ir = pcall(require, "ac_ir_protocols")

local function save_hub_config(params, reg)
  local _res = nil
  local function out_json(t) _res = t end
  ;(function()
    local ip = trim(params.ip)
    local mac = trim(params.mac):lower()
    local did = trim(params.device_id)
    local lk = trim(params.local_key)
    local ct = tonumber(params.control_type)
    local patch = {}
    if ip:match("^%d+%.%d+%.%d+%.%d+$") then patch.ip = ip end
    if mac:match("^[%x:]+$") then patch.mac = mac end
    if did ~= "" then patch.device_id = did end
    if lk ~= "" then
      if #lk ~= 16 then out_json({ ok = false, message = "Local Key Tuya phải đủ đúng 16 ký tự" }); return end
      patch.local_key = lk
      set_entity_key("s06_default", lk)
    end
    if ct and (ct == 1 or ct == 2) then patch.control_type = ct end
    sync_primary_cfg(patch)
    local c0 = find_controller(reg, "s06_default")
    if c0 then
      if patch.ip then c0.ip = patch.ip end
      if patch.mac then c0.mac = patch.mac end
      if patch.device_id then c0.device_id = patch.device_id end
      if patch.control_type then c0.control_type = patch.control_type end
      save_registry(reg)
    end
    out_json({ ok = true, message = "Đã lưu cấu hình S06 Pro (chmod 600)" })

  end)()
  return _res
end

local function save_controller(params, reg, lan_hosts)
  local _res = nil
  local function out_json(t) _res = t end
  ;(function()
    local cid = trim(params.id)
    local kind = trim(params.kind)
    if kind == "" then kind = "tuya_ir" end
    local name = trim(params.name)
    local room = trim(params.room)
    local ip = trim(params.ip)
    local mac = trim(params.mac):lower()
    local did = trim(params.device_id)
    local lk = trim(params.local_key)
    local ct = tonumber(params.control_type) or 1
    if lk ~= "" and #lk ~= 16 then
      out_json({ ok = false, message = "Local Key Tuya phải đủ đúng 16 ký tự" })
      return
    end
    if cid == "" then
      cid = ((kind == "esp32_voice") and "esp32_" or "s06_") .. tostring(os.time()) .. "_" .. tostring(#(reg.controllers or {}) + 1)
    end
    local existing = nil
    for _, c in ipairs(reg.controllers or {}) do if c.id == cid then existing = c; break end end
    if existing then
      if name ~= "" then existing.name = name end
      if room ~= "" then existing.room = room end
      if ip:match("^%d+%.%d+%.%d+%.%d+$") then existing.ip = ip end
      if mac ~= "" then existing.mac = mac end
      if did ~= "" then existing.device_id = did end
      existing.control_type = ct
    else
      if not ip:match("^%d+%.%d+%.%d+%.%d+$") then
        out_json({ ok = false, message = "Cần nhập địa chỉ IP LAN hợp lệ" })
        return
      end
      reg.controllers[#reg.controllers + 1] = {
        id = cid,
        kind = kind,
        name = (name ~= "") and name or ((kind == "esp32_voice") and "Mạch Giọng Nói ESP32" or "Cục Hồng Ngoại S06"),
        room = (room ~= "") and room or "Phòng khách",
        ip = ip,
        mac = mac,
        device_id = did,
        control_type = ct,
      }
    end
    if lk ~= "" then set_entity_key(cid, lk) end
    if cid == "s06_default" then
      local patch = {}
      if ip:match("^%d+%.%d+%.%d+%.%d+$") then patch.ip = ip end
      if mac ~= "" then patch.mac = mac end
      if did ~= "" then patch.device_id = did end
      if lk ~= "" then patch.local_key = lk end
      patch.control_type = ct
      sync_primary_cfg(patch)
    end
    save_registry(reg)
    local ctrls = build_public_controllers(reg, load_s06_cfg(), lan_hosts, false)
    out_json({ ok = true, message = "Đã lưu bộ điều khiển!", controllers = ctrls })

  end)()
  return _res
end

local function remove_controller(params, reg)
  local _res = nil
  local function out_json(t) _res = t end
  ;(function()
    local cid = trim(params.id)
    if cid == "s06_default" then
      out_json({ ok = false, message = "Không thể xóa cục S06 Pro mặc định" })
      return
    end
    local kept, removed = {}, false
    for _, c in ipairs(reg.controllers or {}) do
      if c.id == cid then removed = true else kept[#kept + 1] = c end
    end
    reg.controllers = kept
    save_registry(reg)
    out_json({ ok = removed, message = removed and "Đã xóa bộ điều khiển" or "Không tìm thấy" })

  end)()
  return _res
end

local function add_device(params, reg)
  local _res = nil
  local function out_json(t) _res = t end
  ;(function()
    local drv = trim(params.driver)
    local cid = trim(params.catalog_id)
    local ipath = trim(params.irdb_path)
    local ctrl_id = trim(params.controller_id)
    if ctrl_id == "" then ctrl_id = "s06_default" end
    local custom_name = trim(params.name)
    local room = trim(params.room)
    if room == "" then room = "Phòng khách" end
    local cat_slug = sanitize_category(params.category)
    local cat_label = trim(params.category_label):sub(1, 48)
    local raw_acts = decode_json_param(params.actions) or decode_json_param(params.actions_json)
    local clean_acts = sanitize_actions(raw_acts)
    local raw_caps = decode_json_param(params.capabilities) or decode_json_param(params.capabilities_json)
    local clean_caps = {}
    if type(raw_caps) == "table" then
      for _, c in ipairs(raw_caps) do
        local cs = trim(c):gsub("[^a-zA-Z0-9_%-]", "")
        if cs ~= "" then clean_caps[#clean_caps + 1] = cs end
      end
    end
    local raw_meta = decode_json_param(params.meta) or decode_json_param(params.meta_json) or {}
    local p_port = tonumber(params.port)
    if p_port and (p_port < 1 or p_port > 65535) then p_port = nil end
    local new_dev

    if drv == "tuya_switch" then
      local ip = trim(params.ip)
      local did = trim(params.device_id)
      local lk = trim(params.local_key)
      local dp = trim(params.dp)
      if dp == "" then dp = "1" end
      local cat = (params.category and trim(params.category) ~= "") and cat_slug or "light"
      if not is_private_lan_ip(ip, false) or did == "" or #lk ~= 16 then
        out_json({ ok = false, message = "Thiết bị Tuya Wi-Fi cần IP LAN hợp lệ, Device ID và Local Key đúng 16 ký tự!" })
        return
      end
      local uid = "tsw_" .. tostring(os.time()) .. "_" .. tostring(#(reg.devices or {}) + 1)
      set_entity_key(uid, lk)
      new_dev = {
        id = uid, driver = "tuya_switch", type = "switch",
        name = (custom_name ~= "") and custom_name or ("Công tắc Tuya (" .. ip .. ")"),
        room = room, category = cat, category_label = (cat_label ~= "" and cat_label or nil),
        brand = "Tuya Wi-Fi",
        ip = ip, mac = trim(params.mac):lower(), device_id = did, dp = dp,
        has_key = true, state = { on = false }, buttons = {}, actions = clean_acts,
      }
    elseif drv == "http_relay" then
      local on_url = trim(params.on_url)
      local off_url = trim(params.off_url)
      local cat = (params.category and trim(params.category) ~= "") and cat_slug or "light"
      if not is_lan_http_url(on_url) or (off_url ~= "" and not is_lan_http_url(off_url)) then
        out_json({ ok = false, message = "URL Relay chỉ chấp nhận địa chỉ mạng LAN nội bộ (http://192.168.x.x/... hoặc 10.x/172.16.x)" })
        return
      end
      local uid = "hrel_" .. tostring(os.time()) .. "_" .. tostring(#(reg.devices or {}) + 1)
      new_dev = {
        id = uid, driver = "http_relay", type = "switch",
        name = (custom_name ~= "") and custom_name or "Công tắc HTTP Relay LAN",
        room = room, category = cat, category_label = (cat_label ~= "" and cat_label or nil),
        brand = "HTTP / Tasmota / ESP32",
        on_url = on_url, off_url = (off_url ~= "") and off_url or on_url,
        state = { on = false }, buttons = {}, actions = clean_acts,
      }
    elseif drv == "tasmota" or drv == "shelly" or drv == "wled" or drv == "yeelight" or drv == "sonoff_diy" then
      local ip = trim(params.ip)
      if not is_private_lan_ip(ip, false) then
        out_json({ ok = false, message = "Cần nhập địa chỉ IP LAN hợp lệ (192.168.x.x / 10.x / 172.16-31.x)" })
        return
      end
      local default_ports = { tasmota = 80, shelly = 80, wled = 80, sonoff_diy = 8081, yeelight = 55443 }
      local use_port = (p_port and p_port > 0) and math.floor(p_port) or default_ports[drv]
      local cat = (params.category and trim(params.category) ~= "") and cat_slug or ((drv == "wled" or drv == "yeelight") and "light" or "plug")
      local def_caps = (#clean_caps > 0) and clean_caps or (((drv == "wled" or drv == "yeelight") and { "power", "brightness" }) or { "power" })
      local brand_map = { tasmota = "Tasmota Wi-Fi", shelly = "Shelly LAN", wled = "WLED", yeelight = "Yeelight", sonoff_diy = "Sonoff DIY" }
      local uid = drv .. "_" .. tostring(os.time()) .. "_" .. tostring(#(reg.devices or {}) + 1)
      new_dev = {
        id = uid, driver = drv, type = "switch",
        name = (custom_name ~= "") and custom_name or (brand_map[drv] .. " (" .. ip .. ")"),
        room = room, category = cat, category_label = (cat_label ~= "" and cat_label or nil),
        brand = brand_map[drv],
        ip = ip, mac = trim(params.mac):lower(), port = use_port,
        shelly_gen = (drv == "shelly") and (tonumber(params.shelly_gen) or tonumber(raw_meta.shelly_gen) or 1) or nil,
        channels = tonumber(params.channels) or tonumber(raw_meta.channels) or 1,
        web_url = is_lan_http_url(trim(params.web_url)) and trim(params.web_url) or (is_lan_http_url(raw_meta.web_url) and raw_meta.web_url or nil),
        capabilities = def_caps,
        state = { on = false, brightness = 100 },
        buttons = {},
        actions = clean_acts,
      }
    elseif drv == "camera_lan" or drv == "smart_actions" then
      local ip = trim(params.ip)
      if ip ~= "" and not is_private_lan_ip(ip, false) then
        out_json({ ok = false, message = "IP LAN thiết bị không hợp lệ (đã chặn localhost/IP công cộng/Router)" })
        return
      end
      if ip == "" and #clean_acts == 0 then
        out_json({ ok = false, message = "Cần nhập IP LAN hoặc ít nhất 1 nút lệnh LAN hợp lệ" })
        return
      end
      local cat = (params.category and trim(params.category) ~= "") and cat_slug or ((drv == "camera_lan") and "camera" or "custom")
      if #clean_acts == 0 and ip ~= "" then
        clean_acts = build_default_actions_for_category(cat, ip, p_port or 80)
      end
      local web_u = trim(params.web_url)
      if web_u == "" and type(raw_meta.web_url) == "string" then web_u = raw_meta.web_url end
      if web_u ~= "" and not is_lan_http_url(web_u) then web_u = "" end
      if web_u == "" and ip ~= "" then web_u = "http://" .. ip .. ((p_port and p_port ~= 80) and (":" .. tostring(p_port)) or "") .. "/" end
      local rtsp_u = trim(params.rtsp_url)
      if rtsp_u == "" and type(raw_meta.rtsp_url) == "string" then rtsp_u = raw_meta.rtsp_url end
      if rtsp_u == "" and drv == "camera_lan" and ip ~= "" then rtsp_u = "rtsp://" .. ip .. ":554/" end
      local uid = ((drv == "camera_lan") and "cam_" or "smart_") .. tostring(os.time()) .. "_" .. tostring(#(reg.devices or {}) + 1)
      new_dev = {
        id = uid, driver = drv, type = drv,
        name = (custom_name ~= "") and custom_name or ((drv == "camera_lan") and ("Camera IP (" .. ip .. ")") or ("Thiết bị (" .. (ip ~= "" and ip or "LAN") .. ")")),
        room = room, category = cat, category_label = (cat_label ~= "" and cat_label or nil),
        brand = (drv == "camera_lan") and "Camera IP LAN" or "Thiết Bị Thông Minh LAN",
        ip = ip, mac = trim(params.mac):lower(), port = p_port,
        web_url = (web_u ~= "") and web_u or nil,
        rtsp_url = (rtsp_u ~= "") and rtsp_u or nil,
        capabilities = (#clean_caps > 0) and clean_caps or ((drv == "camera_lan") and { "web_ui", "rtsp", "ping", "actions" } or { "actions", "ping" }),
        state = (cat == "security") and { alarm_mode = "disarmed", on = false } or { on = false },
        buttons = {},
        actions = clean_acts,
      }
    elseif drv == "android_tv" then
      local tv_id = trim(params.tv_id)
      local ip = trim(params.ip)
      local tv_found = nil
      for _, t in ipairs(read_lan_tvs()) do
        if (tv_id ~= "" and t.id == tv_id) or (ip ~= "" and t.ip == ip) then tv_found = t; break end
      end
      if not tv_found then
        if not is_private_lan_ip(ip, false) then
          out_json({ ok = false, message = "Không tìm thấy TV LAN id: " .. tv_id })
          return
        end
        tv_found = { id = (tv_id ~= "") and tv_id or ("tv_" .. ip:gsub("%.", "_")), name = (custom_name ~= "") and custom_name or ("Android TV (" .. ip .. ")"), brand = "Android TV", ip = ip }
      end
      local uid = "atv_" .. tv_found.id
      for _, d in ipairs(reg.devices or {}) do
        if d.id == uid then out_json({ ok = false, message = tv_found.name .. " đã có sẵn trong danh sách!" }); return end
      end
      new_dev = {
        id = uid, driver = "android_tv", type = "android_tv",
        name = (custom_name ~= "") and custom_name or tv_found.name,
        room = room, category = "tv", brand = tv_found.brand or "Android TV",
        ip = tv_found.ip, tv_id = tv_found.id, buttons = {}, actions = clean_acts,
      }
    elseif cid ~= "" and BUILTIN_BY_ID[cid] then
      local it = BUILTIN_BY_ID[cid]
      local did = cid .. "_" .. tostring(os.time()) .. "_" .. tostring(#(reg.devices or {}) + 1)
      if it.type == "ac" then
        new_dev = {
          id = did, driver = "tuya_ir_ac", type = "ac", controller_id = ctrl_id,
          name = (custom_name ~= "") and custom_name or it.name,
          room = room, category = "ac", brand = it.brand,
          brand_label = ok_ac and ac_ir.get_brand_info(it.brand).label or it.brand,
          source = "builtin",
          state = { power = false, temp = 26, mode = "cool", fan = "auto", swing = false },
          buttons = {},
        }
        if ctrl_id == "s06_default" then sync_primary_cfg({ ac_brand = it.brand }) end
      else
        local btns = {}
        for _, b in ipairs(it.buttons or {}) do
          btns[#btns + 1] = { id = b.id, label = b.label, proto = b.proto, dev = b.dev, sub = b.sub, fn = b.fn }
        end
        new_dev = {
          id = did, driver = it.driver or "tuya_ir_remote", type = it.type, controller_id = ctrl_id,
          name = (custom_name ~= "") and custom_name or it.name,
          room = room, category = it.category, brand = it.brand,
          source = "builtin", buttons = btns,
        }
      end
    elseif ipath ~= "" then
      local btns, err = fetch_irdb_csv_buttons(ipath)
      if not btns then
        out_json({ ok = false, message = "Không thêm được từ IRDB: " .. tostring(err) })
        return
      end
      local b_brand, b_cat = ipath:match("^([^/]+)/([^/]+)/")
      local did = "irdb_" .. tostring(os.time()) .. "_" .. tostring(#(reg.devices or {}) + 1)
      new_dev = {
        id = did, driver = "tuya_ir_remote", type = "ir_remote", controller_id = ctrl_id,
        name = (custom_name ~= "") and custom_name or ((b_brand or "IR") .. " " .. (b_cat or "Remote"):gsub("_", " ")),
        room = room, category = infer_irdb_category(b_cat),
        brand = b_brand or "IRDB", source = "irdb", irdb_path = ipath, buttons = btns,
      }
    else
      out_json({ ok = false, message = "Thiếu thông tin thiết bị cần thêm" })
      return
    end

    reg.devices[#reg.devices + 1] = new_dev
    save_registry(reg)
    out_json({ ok = true, message = "Đã thêm: " .. new_dev.name, device = new_dev, devices = reg.devices })

  end)()
  return _res
end

local function remove_device(params, reg)
  local _res = nil
  local function out_json(t) _res = t end
  ;(function()
    local did = trim(params.id)
    local kept, removed = {}, false
    for _, d in ipairs(reg.devices or {}) do
      if d.id == did then removed = true else kept[#kept + 1] = d end
    end
    reg.devices = kept
    save_registry(reg)
    local kv = load_key_vault()
    if kv[did] then kv[did] = nil; save_key_vault(kv) end
    out_json({ ok = removed, message = removed and "Đã xóa thiết bị" or "Không tìm thấy thiết bị", devices = kept })

  end)()
  return _res
end

local function save_device_action(params, reg)
  local _res = nil
  local function out_json(t) _res = t end
  ;(function()
    local did = trim(params.id)
    local target = nil
    for _, d in ipairs(reg.devices or {}) do if d.id == did then target = d; break end end
    if not target then out_json({ ok = false, message = "Không tìm thấy thiết bị" }); return end
    local act_tbl = {
      id = trim(params.action_id),
      label = trim(params.label),
      icon = trim(params.icon),
      kind = trim(params.kind),
      url = trim(params.url),
      body = params.body,
      ip = (trim(params.ip) ~= "") and trim(params.ip) or (target.ip or ""),
      port = tonumber(params.port) or 0,
      payload = params.payload,
      dp = trim(params.dp),
      dp_val = params.dp_val,
      style = trim(params.style),
    }
    target.actions = target.actions or {}
    local clean = sanitize_action_item(act_tbl, #target.actions + 1)
    if not clean then
      out_json({ ok = false, message = "Lệnh không hợp lệ (cần tên nút, URL LAN hoặc IP/Port LAN hợp lệ)" })
      return
    end
    local updated = false
    for i, a in ipairs(target.actions) do
      if a.id == clean.id then target.actions[i] = clean; updated = true; break end
    end
    if not updated then target.actions[#target.actions + 1] = clean end
    save_registry(reg)
    out_json({ ok = true, message = "Đã lưu nút lệnh [" .. clean.label .. "]", device = target })

  end)()
  return _res
end

local function remove_device_action(params, reg)
  local _res = nil
  local function out_json(t) _res = t end
  ;(function()
    local did = trim(params.id)
    local aid = trim(params.action_id)
    local target = nil
    for _, d in ipairs(reg.devices or {}) do if d.id == did then target = d; break end end
    if not target then out_json({ ok = false, message = "Không tìm thấy thiết bị" }); return end
    local kept, removed = {}, false
    for _, a in ipairs(target.actions or {}) do
      if a.id == aid then removed = true else kept[#kept + 1] = a end
    end
    target.actions = kept
    save_registry(reg)
    out_json({ ok = removed, message = removed and "Đã xóa nút lệnh" or "Không tìm thấy nút lệnh", device = target })

  end)()
  return _res
end

local function control_device(params, reg, lan_hosts, cfg)
  local _res = nil
  local function out_json(t) _res = t end
  ;(function()
    local did = trim(params.id)
    local op = trim(params.op)
    local val = trim(params.value)
    local btn_id = trim(params.button)
    local dry = (params.dry_run == true)

    local target = nil
    for _, d in ipairs(reg.devices or {}) do if d.id == did then target = d; break end end
    if not target then out_json({ ok = false, message = "Không tìm thấy thiết bị" }); return end
    local drv = target.driver or ((target.type == "ac") and "tuya_ir_ac" or "tuya_ir_remote")

    local function check_device_online(dev_ip)
      local t0 = now_ms()
      if not is_private_lan_ip(dev_ip, false) then return false, 0 end
      local plist = { 80, 554, 6668, 8008, 8080, 8081, 8990, 55443 }
      if dev_ip == target.ip and target.port and tonumber(target.port) then
        table.insert(plist, 1, tonumber(target.port))
      end
      local tgts = {}
      for _, p in ipairs(plist) do tgts[#tgts + 1] = { ip = dev_ip, port = p } end
      local om = tcp_probe_batch(tgts, 550)
      local is_up = (om[dev_ip] and next(om[dev_ip]) ~= nil) or (lan_hosts[dev_ip] and lan_hosts[dev_ip].online == true)
      return is_up and true or false, math.max(1, now_ms() - t0)
    end

    local function execute_custom_action(act)
      if not act then return false, "Không tìm thấy nút lệnh" end
      if act.kind == "ping" then
        local pip = (act.ip and act.ip ~= "") and act.ip or (target.ip or "")
        if dry then return true, target.name .. " → Đang hoạt động (Dry-Run)" end
        local up, ms = check_device_online(pip)
        target.state = target.state or {}
        target.state.online = up
        save_registry(reg)
        return true, up and ("🟢 " .. target.name .. " đang TRỰC TUYẾN (" .. tostring(ms) .. "ms)") or ("🔴 " .. target.name .. " chưa phản hồi (" .. pip .. ")")
      elseif act.kind == "http_get" then
        if not is_lan_http_url(act.url) then return false, "URL LAN không hợp lệ" end
        if not dry then
          local _, herr = http_request_lan("GET", act.url, nil, 3, 16384)
          if herr then return false, herr end
        end
        return true, target.name .. " → Đã chạy [" .. act.label .. "]"
      elseif act.kind == "http_post" then
        if not is_lan_http_url(act.url) then return false, "URL LAN không hợp lệ" end
        if not dry then
          local _, herr = http_request_lan("POST", act.url, act.body or "", 3, 16384)
          if herr then return false, herr end
        end
        return true, target.name .. " → Đã gửi POST [" .. act.label .. "]"
      elseif act.kind == "tuya_dp" then
        local lkey = get_entity_key(target.id, cfg)
        if not dry and (not ok_tuya or #lkey ~= 16) then return false, "Thiết bị Tuya chưa đủ Local Key 16 ký tự" end
        if not dry then
          local ok_t, terr = tuya_v35.set_dps(target.ip, target.device_id, lkey, { [tostring(act.dp or "1")] = act.dp_val }, 3)
          if not ok_t then return false, "Lỗi Tuya: " .. tostring(terr) end
        end
        return true, target.name .. " → Đã kích hoạt [" .. act.label .. "]"
      elseif act.kind == "tcp_send" then
        if not dry then
          local _, terr = tcp_send_recv(act.ip, act.port, act.payload or "", 400)
          if terr then return false, "Lỗi TCP: " .. tostring(terr) end
        end
        return true, target.name .. " → Đã gửi TCP [" .. act.label .. "]"
      elseif act.kind == "udp_send" then
        if not dry then
          local ok_u, uerr = udp_send_once(act.ip, act.port, act.payload or "")
          if not ok_u then return false, "Lỗi UDP: " .. tostring(uerr) end
        end
        return true, target.name .. " → Đã gửi UDP [" .. act.label .. "]"
      elseif act.kind == "open_url" then
        return true, "Mở trang: " .. tostring(act.url)
      end
      return false, "Loại lệnh chưa hỗ trợ: " .. tostring(act.kind)
    end

    if op == "action" and btn_id ~= "" then
      local found_act = nil
      for _, a in ipairs(target.actions or {}) do if a.id == btn_id then found_act = a; break end end
      local ok_a, msg_a = execute_custom_action(found_act)
      if ok_a then
        target.state = target.state or {}
        if btn_id == "arm" then target.state.alarm_mode = "armed"; target.state.on = true
        elseif btn_id == "disarm" then target.state.alarm_mode = "disarmed"; target.state.on = false
        elseif btn_id == "sos" then target.state.alarm_mode = "sos"; target.state.on = true
        elseif btn_id == "on" then target.state.on = true
        elseif btn_id == "off" then target.state.on = false end
        save_registry(reg)
      end
      out_json({ ok = ok_a, dry_run = dry, device = target, message = msg_a })
      return
    end

    if drv == "tasmota" then
      local st = target.state or { on = false, brightness = 100 }
      local ch = (tonumber(btn_id) and tonumber(btn_id) >= 2) and tostring(math.floor(tonumber(btn_id))) or ""
      local base = "http://" .. target.ip .. ((target.port and tonumber(target.port) ~= 80) and (":" .. tostring(target.port)) or "")
      local msg_txt
      if op == "brightness" then
        local bri = math.min(100, math.max(1, math.floor(tonumber(val) or 100)))
        if not dry then http_request_lan("GET", base .. "/cm?cmnd=Dimmer%20" .. tostring(bri), nil, 3, 8192) end
        st.brightness = bri; st.on = true
        msg_txt = target.name .. " → Độ sáng " .. tostring(bri) .. "%"
      else
        local nxt = (op == "on") and true or ((op == "off") and false or (not st.on))
        local cm = nxt and ("Power" .. ch .. "%20On") or ("Power" .. ch .. "%20Off")
        if not dry then http_request_lan("GET", base .. "/cm?cmnd=" .. cm, nil, 3, 8192) end
        st.on = nxt
        msg_txt = target.name .. (nxt and " → ĐÃ BẬT" or " → ĐÃ TẮT")
      end
      target.state = st; save_registry(reg)
      out_json({ ok = true, dry_run = dry, device = target, message = msg_txt })

    elseif drv == "shelly" then
      local st = target.state or { on = false, brightness = 100 }
      local gen = tonumber(target.shelly_gen) or 1
      local ch = math.max(0, math.floor(tonumber(btn_id) or 0))
      local base = "http://" .. target.ip .. ((target.port and tonumber(target.port) ~= 80) and (":" .. tostring(target.port)) or "")
      local url, msg_txt
      if op == "brightness" then
        local bri = math.min(100, math.max(1, math.floor(tonumber(val) or 100)))
        url = (gen >= 2)
          and (base .. "/rpc/Light.Set?id=" .. tostring(ch) .. "&on=true&brightness=" .. tostring(bri))
          or (base .. "/light/" .. tostring(ch) .. "?turn=on&brightness=" .. tostring(bri))
        st.brightness = bri; st.on = true
        msg_txt = target.name .. " → Độ sáng " .. tostring(bri) .. "%"
      else
        local nxt = (op == "on") and true or ((op == "off") and false or (not st.on))
        url = (gen >= 2)
          and (base .. "/rpc/Switch.Set?id=" .. tostring(ch) .. "&on=" .. (nxt and "true" or "false"))
          or (base .. "/relay/" .. tostring(ch) .. "?turn=" .. (nxt and "on" or "off"))
        st.on = nxt
        msg_txt = target.name .. (nxt and " → ĐÃ BẬT" or " → ĐÃ TẮT")
      end
      if not dry then http_request_lan("GET", url, nil, 3, 8192) end
      target.state = st; save_registry(reg)
      out_json({ ok = true, dry_run = dry, device = target, message = msg_txt })

    elseif drv == "wled" then
      local st = target.state or { on = false, brightness = 100 }
      local base = "http://" .. target.ip .. ((target.port and tonumber(target.port) ~= 80) and (":" .. tostring(target.port)) or "")
      local payload_tbl, msg_txt
      if op == "brightness" then
        local pct = math.min(100, math.max(1, math.floor(tonumber(val) or 100)))
        local bri255 = math.max(1, math.floor(pct * 255 / 100))
        payload_tbl = { on = true, bri = bri255 }
        st.brightness = pct; st.on = true
        msg_txt = target.name .. " → Độ sáng " .. tostring(pct) .. "%"
      else
        local nxt = (op == "on") and true or ((op == "off") and false or (not st.on))
        payload_tbl = { on = nxt }
        st.on = nxt
        msg_txt = target.name .. (nxt and " → ĐÃ BẬT" or " → ĐÃ TẮT")
      end
      if not dry then http_request_lan("POST", base .. "/json/state", cjson.encode(payload_tbl), 3, 8192) end
      target.state = st; save_registry(reg)
      out_json({ ok = true, dry_run = dry, device = target, message = msg_txt })

    elseif drv == "yeelight" then
      local st = target.state or { on = false, brightness = 100 }
      local rpc_line, msg_txt
      if op == "brightness" then
        local pct = math.min(100, math.max(1, math.floor(tonumber(val) or 100)))
        rpc_line = string.format('{"id":1,"method":"set_bright","params":[%d,"smooth",300]}\r\n', pct)
        st.brightness = pct; st.on = true
        msg_txt = target.name .. " → Độ sáng " .. tostring(pct) .. "%"
      else
        local nxt = (op == "on") and true or ((op == "off") and false or (not st.on))
        rpc_line = string.format('{"id":1,"method":"set_power","params":["%s","smooth",300]}\r\n', nxt and "on" or "off")
        st.on = nxt
        msg_txt = target.name .. (nxt and " → ĐÃ BẬT" or " → ĐÃ TẮT")
      end
      local ok_y, yerr = true, nil
      if not dry then ok_y, yerr = tcp_send_recv(target.ip, target.port or 55443, rpc_line, 400) end
      if ok_y == nil then
        out_json({ ok = false, message = "Lỗi Yeelight: " .. tostring(yerr) .. " (Hãy bật LAN Control trong app Yeelight)" })
        return
      end
      target.state = st; save_registry(reg)
      out_json({ ok = true, dry_run = dry, device = target, message = msg_txt })

    elseif drv == "sonoff_diy" then
      local st = target.state or { on = false }
      local nxt = (op == "on") and true or ((op == "off") and false or (not st.on))
      local url = "http://" .. target.ip .. ":" .. tostring(target.port or 8081) .. "/zeroconf/switch"
      local body = string.format('{"deviceid":"","data":{"switch":"%s"}}', nxt and "on" or "off")
      if not dry then http_request_lan("POST", url, body, 3, 8192) end
      st.on = nxt; target.state = st; save_registry(reg)
      out_json({ ok = true, dry_run = dry, device = target, message = target.name .. (nxt and " → ĐÃ BẬT" or " → ĐÃ TẮT") })

    elseif drv == "camera_lan" or drv == "smart_actions" then
      local st = target.state or { on = false }
      if op == "ping" then
        if dry then
          out_json({ ok = true, dry_run = true, device = target, message = target.name .. " → Online (Dry-Run)" })
          return
        end
        local up, ms = check_device_online(target.ip or "")
        st.online = up; target.state = st; save_registry(reg)
        out_json({ ok = true, device = target, message = up and ("🟢 " .. target.name .. " đang TRỰC TUYẾN (" .. tostring(ms) .. "ms)") or ("🔴 " .. target.name .. " mất kết nối") })
        return
      end
      local want_id = (btn_id ~= "" and btn_id) or op
      local found_act = nil
      for _, a in ipairs(target.actions or {}) do if a.id == want_id then found_act = a; break end end
      if found_act then
        local ok_a, msg_a = execute_custom_action(found_act)
        if ok_a then
          if op == "arm" then st.alarm_mode = "armed"; st.on = true
          elseif op == "disarm" then st.alarm_mode = "disarmed"; st.on = false
          elseif op == "sos" then st.alarm_mode = "sos"; st.on = true
          elseif op == "on" then st.on = true
          elseif op == "off" then st.on = false end
          target.state = st; save_registry(reg)
        end
        out_json({ ok = ok_a, dry_run = dry, device = target, message = msg_a })
      elseif op == "arm" or op == "disarm" or op == "sos" or op == "on" or op == "off" then
        if op == "arm" then st.alarm_mode = "armed"; st.on = true
        elseif op == "disarm" then st.alarm_mode = "disarmed"; st.on = false
        elseif op == "sos" then st.alarm_mode = "sos"; st.on = true
        elseif op == "on" then st.on = true
        elseif op == "off" then st.on = false end
        target.state = st; save_registry(reg)
        out_json({ ok = true, dry_run = dry, device = target, message = target.name .. " → Đã chuyển trạng thái (chưa gắn URL lệnh riêng — bấm '➕ Thêm Lệnh' để gắn link/lệnh thật)" })
      else
        out_json({ ok = false, message = "Chưa có lệnh phù hợp cho thao tác [" .. tostring(want_id) .. "]" })
      end

    elseif drv == "tuya_switch" then
      local st = target.state or { on = false }
      local nxt = (op == "on") and true or ((op == "off") and false or (not st.on))
      local dp = tostring(target.dp or "1")
      local lkey = get_entity_key(target.id, cfg)
      if not dry and (not ok_tuya or #lkey ~= 16) then
        out_json({ ok = false, message = "Công tắc Tuya chưa đủ Local Key 16 ký tự" })
        return
      end
      local ok, err = true, nil
      if not dry then
        ok, err = tuya_v35.set_dps(target.ip, target.device_id, lkey, { [dp] = nxt }, 3)
      end
      if ok then st.on = nxt; target.state = st; save_registry(reg) end
      out_json({ ok = ok and true or false, dry_run = dry, device = target, message = ok and (target.name .. (nxt and " → ĐÃ BẬT" or " → ĐÃ TẮT")) or ("Lỗi Tuya Switch: " .. tostring(err)) })

    elseif drv == "http_relay" then
      local st = target.state or { on = false }
      local nxt = (op == "on") and true or ((op == "off") and false or (not st.on))
      local u = nxt and target.on_url or (target.off_url or target.on_url)
      if not is_lan_http_url(u) then out_json({ ok = false, message = "URL Relay LAN không hợp lệ" }); return end
      if not dry then
        http_fetch_raw(u, 3)
      end
      st.on = nxt; target.state = st; save_registry(reg)
      out_json({ ok = true, dry_run = dry, device = target, message = target.name .. (nxt and " → ĐÃ BẬT" or " → ĐÃ TẮT") })

    elseif drv == "android_tv" then
      local ok_call = false
      if dry then
        ok_call = true
      elseif op == "cmd" and val ~= "" then
        local r = http_get_json(HUB_HTTP .. "/command?text=" .. url_encode(val) .. "&device=" .. url_encode(target.tv_id or ""), 4)
        ok_call = (type(r) == "table" and r.status == "ok")
      elseif op == "key" and btn_id ~= "" then
        local r = http_get_json(HUB_HTTP .. "/remote_key?key=" .. url_encode(btn_id) .. "&device=" .. url_encode(target.tv_id or ""), 4)
        ok_call = (type(r) == "table" and r.status == "ok")
      end
      out_json({ ok = ok_call, dry_run = dry, device = target, message = ok_call and ("Đã gửi lệnh tới " .. target.name) or ("TV hoặc Voice Hub chưa phản hồi") })

    elseif drv == "tuya_ir_ac" and ok_ac then
      local ctrl = find_controller(reg, target.controller_id or "s06_default")
      local hip, hdid, hlkey, hct = heal_controller_ip(ctrl or { id="s06_default", ip=cfg.ip, mac=cfg.mac, device_id=cfg.device_id, control_type=cfg.control_type }, lan_hosts, cfg)
      if not dry and (not ok_tuya or #hlkey ~= 16) then
        out_json({ ok = false, message = "Cục S06 chưa có Local Key 16 ký tự" })
        return
      end
      local st = target.state or { power = false, temp = 26, mode = "cool", fan = "auto", swing = false }
      local prev_pwr = st.power and true or false
      local enc_op = "set"
      if op == "on" then st.power = true; enc_op = "on"
      elseif op == "off" then st.power = false; enc_op = "off"
      elseif op == "temp_up" then st.temp = math.min(30, (tonumber(st.temp) or 26) + 1); st.power = true
      elseif op == "temp_down" then st.temp = math.max(16, (tonumber(st.temp) or 26) - 1); st.power = true
      elseif op == "set_temp" then st.temp = math.min(30, math.max(16, tonumber(val) or 26)); st.power = true
      elseif op == "mode" and val ~= "" then st.mode = val; st.power = true
      elseif op == "fan" and val ~= "" then st.fan = val; st.power = true; enc_op = "fan"
      elseif op == "swing" then st.swing = not (st.swing and true or false); st.power = true; enc_op = "swing"
      elseif op == "next_variant" then
        target.brand = ac_ir.next_variant(target.brand)
        target.brand_label = ac_ir.get_brand_info(target.brand).label
        target.state = st
        save_registry(reg)
        if (target.controller_id or "s06_default") == "s06_default" then sync_primary_cfg({ ac_brand = target.brand }) end
        out_json({ ok = true, message = "Đã đổi mã sang: " .. target.brand_label, device = target })
        return
      end
      st.was_on = prev_pwr
      local pkt = ac_ir.encode(target.brand or "lg2", st, enc_op)
      if not pkt then out_json({ ok = false, message = "Lỗi mã hóa AC brand: " .. tostring(target.brand) }); return end
      local ok, err = true, nil
      if not dry then
        ok, err = tuya_v35.send_head_key(hip, hdid, hlkey, pkt.head, pkt.key, hct)
      end
      if ok then
        target.state = st
        save_registry(reg)
        if (target.controller_id or "s06_default") == "s06_default" then
          sync_primary_cfg({ ac_brand = target.brand, ac_temp = st.temp, ac_mode = st.mode, ac_fan = st.fan, ac_power = st.power, ac_swing = st.swing })
        end
      end
      out_json({
        ok = ok and true or false, dry_run = dry, protocol = pkt.protocol, head_len = #pkt.head, key_len = #pkt.key,
        message = ok and ("Đã gửi " .. target.name .. " (" .. tostring(st.temp) .. "°C • " .. tostring(st.mode) .. ")") or ("Lỗi S06: " .. tostring(err)),
        device = target,
      })

    else
      local ctrl = find_controller(reg, target.controller_id or "s06_default")
      local hip, hdid, hlkey, hct = heal_controller_ip(ctrl or { id="s06_default", ip=cfg.ip, mac=cfg.mac, device_id=cfg.device_id, control_type=cfg.control_type }, lan_hosts, cfg)
      if not dry and (not ok_tuya or #hlkey ~= 16) then
        out_json({ ok = false, message = "Cục S06 chưa có Local Key 16 ký tự" })
        return
      end
      local b_found = nil
      for _, b in ipairs(target.buttons or {}) do if b.id == btn_id then b_found = b; break end end
      if not b_found then out_json({ ok = false, message = "Không tìm thấy nút: " .. btn_id }); return end
      if b_found.base64 and b_found.base64 ~= "" then
        local ok, err = true, nil
        if not dry then ok, err = tuya_v35.send_ir(hip, hdid, hlkey, b_found.base64, hct) end
        out_json({ ok = ok and true or false, dry_run = dry, mode = "learned", message = ok and ("Đã bấm [" .. b_found.label .. "] (Mã đã học)") or ("Lỗi S06: " .. tostring(err)) })
      elseif b_found.proto and ok_ac and ac_ir.supports_generic(b_found.proto) then
        local pkt = ac_ir.encode_generic(b_found.proto, b_found.dev, b_found.sub, b_found.fn)
        if not pkt then out_json({ ok = false, message = "Lỗi encode " .. tostring(b_found.proto) }); return end
        local ok, err = true, nil
        if not dry then ok, err = tuya_v35.send_head_key(hip, hdid, hlkey, pkt.head, pkt.key, hct) end
        out_json({ ok = ok and true or false, dry_run = dry, mode = pkt.protocol, head_len = #pkt.head, key_len = #pkt.key, message = ok and ("Đã bấm [" .. b_found.label .. "] (" .. pkt.protocol .. ")") or ("Lỗi S06: " .. tostring(err)) })
      else
        out_json({ ok = false, need_learn = true, message = "Nút [" .. b_found.label .. "] chưa có mã IR — bật Chế độ Học Phím rồi bấm nút này!" })
      end
    end

  end)()
  return _res
end

local function learn_button(params, reg, lan_hosts, cfg)
  local _res = nil
  local function out_json(t) _res = t end
  ;(function()
    local did = trim(params.id)
    local btn_id = trim(params.button)
    local btn_label = trim(params.label)
    local target = nil
    for _, d in ipairs(reg.devices or {}) do if d.id == did then target = d; break end end
    if not target then out_json({ ok = false, message = "Không tìm thấy thiết bị" }); return end
    local ctrl = find_controller(reg, target.controller_id or "s06_default")
    local hip, hdid, hlkey, hct = heal_controller_ip(ctrl or { id="s06_default", ip=cfg.ip, mac=cfg.mac, device_id=cfg.device_id, control_type=cfg.control_type }, lan_hosts, cfg)
    if not ok_tuya or #hlkey ~= 16 then
      out_json({ ok = false, message = "Cục S06 chưa có Local Key 16 ký tự" })
      return
    end
    if btn_id == "" then btn_id = "custom_" .. tostring(os.time()) end
    local code = tuya_v35.learn_ir(hip, hdid, hlkey, 12, hct)
    if not code then
      out_json({ ok = false, message = "Hết 12s chưa nhận tín hiệu remote. Hãy chĩa sát vào S06 Pro và thử lại." })
      return
    end
    target.buttons = target.buttons or {}
    local updated = false
    for _, b in ipairs(target.buttons) do
      if b.id == btn_id then
        b.base64 = code
        if btn_label ~= "" then b.label = btn_label end
        updated = true; break
      end
    end
    if not updated then
      target.buttons[#target.buttons + 1] = { id = btn_id, label = (btn_label ~= "") and btn_label or btn_id, base64 = code }
    end
    save_registry(reg)
    if target.category == "fan" then
      local voice_map = { power = "fan_power", speed_up = "fan_speed_up", speed_down = "fan_speed_down", swing = "fan_swing", timer = "fan_timer" }
      local vk = voice_map[btn_id]
      if vk then
        local fresh = load_s06_cfg()
        fresh.ir_codes[vk] = code
        write_atomic(S06_CFG_FILE, cjson.encode(fresh), "600")
      end
    end
    out_json({ ok = true, message = "Đã học xong nút [" .. ((btn_label ~= "") and btn_label or btn_id) .. "]!", device = target })
  end)()
  return _res
end

return {
  save_hub_config = save_hub_config,
  save_controller = save_controller,
  remove_controller = remove_controller,
  add_device = add_device,
  remove_device = remove_device,
  save_device_action = save_device_action,
  remove_device_action = remove_device_action,
  control_device = control_device,
  learn_button = learn_button,
}
-- [/VERIFIED-GOLDEN]
