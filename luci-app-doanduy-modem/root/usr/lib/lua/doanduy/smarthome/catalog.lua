-- [VERIFIED-GOLDEN: smarthome-mod-catalog-v250 | 2026-11-26 | DO NOT MODIFY UNLESS TARGETED]
-- Scenario 06 (SmartHome) — Module 3/5: Built-in 11 AC Brands, IR Presets & Online IRDB 3200+ Catalog
local net = require("doanduy.smarthome.net_json")
local store = require("doanduy.smarthome.store")
local read_file = net.read_file
local write_atomic = net.write_atomic
local trim = net.trim
local url_encode = net.url_encode
local http_fetch_raw = net.http_fetch_raw
local find_controller = store.find_controller
local heal_controller_ip = store.heal_controller_ip
local ok_tuya, tuya_v35 = pcall(require, "tuya_v35_local")
local ok_ac, ac_ir = pcall(require, "ac_ir_protocols")

local IRDB_CACHE = "/tmp/irdb_index.txt"

-- =============================================================================
-- BUILTIN CATALOG (11 AC Brands + TV, Fan, Audio, Custom IR)
-- =============================================================================

local function build_catalog()
  local cat = {}
  if ok_ac then
    for _, b in ipairs(ac_ir.BRANDS) do
      if b.id ~= "manual" then
        cat[#cat + 1] = {
          id = "ac_" .. b.id,
          source = "builtin",
          category = "ac",
          driver = "tuya_ir_ac",
          type = "ac",
          brand = b.id,
          name = "Máy lạnh " .. b.label,
          subtitle = "Tự động 100% (16–30°C, chế độ, gió, đảo gió) — Không cần học remote",
          search = ("may lanh dieu hoa ac " .. b.id .. " " .. b.label .. " " .. table.concat(b.aliases or {}, " ")):lower(),
        }
      end
    end
  end

  local ir_presets = {
    {
      id = "tv_lg", category = "tv", brand = "LG", name = "Tivi LG (WebOS / Smart TV)",
      subtitle = "NEC1 • Nguồn, Âm lượng, Kênh, Home, Back, Điều hướng",
      search = "tivi tv lg webos nec1 remote",
      buttons = {
        { id="power", label="Nguồn", proto="NEC1", dev=4, sub=-1, fn=8 },
        { id="vol_up", label="Âm +", proto="NEC1", dev=4, sub=-1, fn=2 },
        { id="vol_down", label="Âm -", proto="NEC1", dev=4, sub=-1, fn=3 },
        { id="mute", label="Tắt tiếng", proto="NEC1", dev=4, sub=-1, fn=9 },
        { id="ch_up", label="Kênh +", proto="NEC1", dev=4, sub=-1, fn=0 },
        { id="ch_down", label="Kênh -", proto="NEC1", dev=4, sub=-1, fn=1 },
        { id="input", label="Ngõ vào", proto="NEC1", dev=4, sub=-1, fn=11 },
        { id="home", label="Home", proto="NEC1", dev=4, sub=-1, fn=67 },
        { id="up", label="▲", proto="NEC1", dev=4, sub=-1, fn=64 },
        { id="down", label="▼", proto="NEC1", dev=4, sub=-1, fn=65 },
        { id="left", label="◀", proto="NEC1", dev=4, sub=-1, fn=7 },
        { id="right", label="▶", proto="NEC1", dev=4, sub=-1, fn=6 },
        { id="ok", label="OK", proto="NEC1", dev=4, sub=-1, fn=68 },
        { id="back", label="Back", proto="NEC1", dev=4, sub=-1, fn=40 },
      },
    },
    {
      id = "tv_samsung", category = "tv", brand = "Samsung", name = "Tivi Samsung (Tizen / Crystal / QLED)",
      subtitle = "NECx2 • Nguồn, Âm lượng, Kênh, Home, Back, Điều hướng",
      search = "tivi tv samsung tizen qled crystal necx2 remote",
      buttons = {
        { id="power", label="Nguồn", proto="NECx2", dev=7, sub=7, fn=2 },
        { id="vol_up", label="Âm +", proto="NECx2", dev=7, sub=7, fn=7 },
        { id="vol_down", label="Âm -", proto="NECx2", dev=7, sub=7, fn=11 },
        { id="mute", label="Tắt tiếng", proto="NECx2", dev=7, sub=7, fn=15 },
        { id="ch_up", label="Kênh +", proto="NECx2", dev=7, sub=7, fn=18 },
        { id="ch_down", label="Kênh -", proto="NECx2", dev=7, sub=7, fn=16 },
        { id="input", label="Source", proto="NECx2", dev=7, sub=7, fn=1 },
        { id="home", label="Home", proto="NECx2", dev=7, sub=7, fn=121 },
        { id="up", label="▲", proto="NECx2", dev=7, sub=7, fn=96 },
        { id="down", label="▼", proto="NECx2", dev=7, sub=7, fn=97 },
        { id="left", label="◀", proto="NECx2", dev=7, sub=7, fn=101 },
        { id="right", label="▶", proto="NECx2", dev=7, sub=7, fn=98 },
        { id="ok", label="OK", proto="NECx2", dev=7, sub=7, fn=104 },
        { id="back", label="Back", proto="NECx2", dev=7, sub=7, fn=88 },
      },
    },
    {
      id = "tv_sony", category = "tv", brand = "Sony", name = "Tivi Sony (Bravia / Android TV)",
      subtitle = "Sony12 • Nguồn, Âm lượng, Kênh, Ngõ vào",
      search = "tivi tv sony bravia android sony12",
      buttons = {
        { id="power", label="Nguồn", proto="Sony12", dev=1, sub=-1, fn=21 },
        { id="vol_up", label="Âm +", proto="Sony12", dev=1, sub=-1, fn=18 },
        { id="vol_down", label="Âm -", proto="Sony12", dev=1, sub=-1, fn=19 },
        { id="mute", label="Tắt tiếng", proto="Sony12", dev=1, sub=-1, fn=20 },
        { id="ch_up", label="Kênh +", proto="Sony12", dev=1, sub=-1, fn=16 },
        { id="ch_down", label="Kênh -", proto="Sony12", dev=1, sub=-1, fn=17 },
        { id="input", label="Input", proto="Sony12", dev=1, sub=-1, fn=37 },
      },
    },
    {
      id = "tv_toshiba", category = "tv", brand = "Toshiba", name = "Tivi Toshiba (NEC1 64)",
      subtitle = "NEC1 • Nguồn, Âm lượng, Kênh, Input",
      search = "tivi tv toshiba nec1",
      buttons = {
        { id="power", label="Nguồn", proto="NEC1", dev=64, sub=-1, fn=18 },
        { id="vol_up", label="Âm +", proto="NEC1", dev=64, sub=-1, fn=26 },
        { id="vol_down", label="Âm -", proto="NEC1", dev=64, sub=-1, fn=30 },
        { id="mute", label="Tắt tiếng", proto="NEC1", dev=64, sub=-1, fn=16 },
        { id="ch_up", label="Kênh +", proto="NEC1", dev=64, sub=-1, fn=27 },
        { id="ch_down", label="Kênh -", proto="NEC1", dev=64, sub=-1, fn=31 },
        { id="input", label="Input", proto="NEC1", dev=64, sub=-1, fn=15 },
      },
    },
    {
      id = "fan_mitsubishi", category = "fan", brand = "Mitsubishi", name = "Quạt Mitsubishi Electric (Cây / Treo / Trần)",
      subtitle = "Bộ nút quạt chuẩn + Hỗ trợ bấm Học 1 chạm S06 Pro & Voice ESP32",
      search = "quat fan mitsubishi mit su cay treo tran",
      buttons = {
        { id="power", label="Bật / Tắt Quạt", proto="NEC1", dev=224, sub=-1, fn=1 },
        { id="speed_up", label="Tăng gió (+)", proto="NEC1", dev=224, sub=-1, fn=2 },
        { id="speed_down", label="Giảm gió (-)", proto="NEC1", dev=224, sub=-1, fn=3 },
        { id="swing", label="Đảo gió (Swing)", proto="NEC1", dev=224, sub=-1, fn=4 },
        { id="timer", label="Hẹn giờ", proto="NEC1", dev=224, sub=-1, fn=5 },
        { id="rhythm", label="Gió tự nhiên", proto="NEC1", dev=224, sub=-1, fn=6 },
      },
    },
    {
      id = "fan_panasonic", category = "fan", brand = "Panasonic", name = "Quạt Panasonic / KDK (Cây / Trần)",
      subtitle = "Đồng bộ lệnh giọng nói ESP32-C3 (Bấm Học bằng S06 Pro 1 lần)",
      search = "quat fan panasonic kdk cay tran",
      buttons = {
        { id="power", label="Bật / Tắt Quạt" },
        { id="speed_up", label="Tăng gió (+)" },
        { id="speed_down", label="Giảm gió (-)" },
        { id="swing", label="Đảo gió" },
        { id="timer", label="Hẹn giờ" },
      },
    },
    {
      id = "fan_senko", category = "fan", brand = "Senko / Asia / Toshiba / Hatari", name = "Quạt Senko / Asia / Toshiba / Hatari / Xiaomi",
      subtitle = "Đồng bộ lệnh giọng nói ESP32-C3 (Bấm Học bằng S06 Pro 1 lần)",
      search = "quat fan senko asia hatari toshiba xiaomi kangaru vinawind dung treo",
      buttons = {
        { id="power", label="Bật / Tắt Quạt" },
        { id="speed_up", label="Tốc độ / Mạnh (+)" },
        { id="speed_down", label="Giảm gió (-)" },
        { id="swing", label="Đảo / Túc năng" },
        { id="timer", label="Hẹn giờ" },
      },
    },
    {
      id = "audio_sony", category = "audio", brand = "Sony", name = "Loa / Soundbar / Amply Sony",
      subtitle = "Sony12 • Nguồn, Âm lượng +, Âm lượng -, Tắt tiếng",
      search = "loa soundbar amply sony audio sony12",
      buttons = {
        { id="power", label="Nguồn", proto="Sony12", dev=16, sub=-1, fn=21 },
        { id="vol_up", label="Âm +", proto="Sony12", dev=16, sub=-1, fn=18 },
        { id="vol_down", label="Âm -", proto="Sony12", dev=16, sub=-1, fn=19 },
        { id="mute", label="Tắt tiếng", proto="Sony12", dev=16, sub=-1, fn=20 },
      },
    },
    {
      id = "audio_lg_samsung", category = "audio", brand = "LG / Samsung", name = "Loa Soundbar LG / Samsung / JBL",
      subtitle = "NEC1/NECx2 + Hỗ trợ Học phím linh hoạt S06 Pro",
      search = "loa soundbar lg samsung jbl karaoke",
      buttons = {
        { id="power", label="Nguồn", proto="NEC1", dev=4, sub=-1, fn=8 },
        { id="vol_up", label="Âm +", proto="NEC1", dev=4, sub=-1, fn=2 },
        { id="vol_down", label="Âm -", proto="NEC1", dev=4, sub=-1, fn=3 },
        { id="mute", label="Tắt tiếng", proto="NEC1", dev=4, sub=-1, fn=9 },
        { id="input", label="Bluetooth / Input" },
      },
    },
    {
      id = "custom_ir", category = "other", brand = "Tự định nghĩa", name = "Thiết Bị Hồng Ngoại Bất Kỳ (Đèn / Rèm / Đầu Thu / Lọc Khí)",
      subtitle = "Tạo thẻ điều khiển riêng & học phím 1 chạm từ remote thật qua S06 Pro",
      search = "khac thiet bi den rem may loc khong khi dau thu custom",
      driver = "custom_ir", type = "custom_ir",
      buttons = {
        { id="power", label="Bật / Tắt" },
        { id="mode", label="Chế độ" },
        { id="up", label="Tăng (+)" },
        { id="down", label="Giảm (-)" },
      },
    },
  }

  for _, item in ipairs(ir_presets) do
    item.source = "builtin"
    item.type = item.type or "ir_remote"
    item.driver = item.driver or "tuya_ir_remote"
    cat[#cat + 1] = item
  end
  return cat
end

local BUILTIN_CATALOG = build_catalog()
local BUILTIN_BY_ID = {}
for _, it in ipairs(BUILTIN_CATALOG) do BUILTIN_BY_ID[it.id] = it end

-- =============================================================================
-- ONLINE PROBONOPD/IRDB CATALOG
-- =============================================================================

local function ensure_irdb_index()
  local raw = read_file(IRDB_CACHE)
  if raw and #raw > 1000 then return raw end
  raw = http_fetch_raw("https://cdn.jsdelivr.net/gh/probonopd/irdb@master/codes/index", 6)
  if #raw > 1000 then
    write_atomic(IRDB_CACHE, raw, "644")
    return raw
  end
  return nil
end

local function is_valid_irdb_path(path)
  if type(path) ~= "string" or path == "" then return false end
  if path:find("%.%.", 1, true) then return false end
  return path:match("^[A-Za-z0-9_. ,/+%-]+%.csv$") ~= nil
end

local function fetch_irdb_csv_buttons(irdb_path)
  if not is_valid_irdb_path(irdb_path) then return nil, "invalid_irdb_path" end
  local url = "https://cdn.jsdelivr.net/gh/probonopd/irdb@master/codes/" .. url_encode(irdb_path)
  local csv = http_fetch_raw(url, 6)
  if csv == "" or not csv:find("functionname", 1, true) then return nil, "empty_or_invalid_csv" end

  local seen_sig = {}
  local all = {}
  for line in csv:gmatch("[^\r\n]+") do
    if not line:match("^functionname,") then
      local fname, proto, dev, sub, fn = line:match("^([^,]+),([^,]+),([%-]?%d+),([%-]?%d+),([%-]?%d+)")
      if fname and proto and ok_ac and ac_ir.supports_generic(proto) then
        local sig = proto .. ":" .. dev .. ":" .. sub .. ":" .. fn
        if not seen_sig[sig] then
          seen_sig[sig] = true
          all[#all + 1] = {
            id = "btn_" .. tostring(#all + 1),
            label = trim(fname),
            proto = trim(proto),
            dev = tonumber(dev),
            sub = tonumber(sub),
            fn = tonumber(fn),
          }
        end
      end
    end
  end
  if #all == 0 then return nil, "no_supported_protocol_buttons" end

  local prio_pats = {"power","standby","vol","mute","channel","ch%+","ch%-","input","source","menu","ok","select","enter","up","down","left","right","back","exit","play","pause","speed","swing","timer"}
  local chosen = {}
  local used = {}
  for _, pat in ipairs(prio_pats) do
    for idx, b in ipairs(all) do
      if not used[idx] and b.label:lower():find(pat) then
        used[idx] = true; chosen[#chosen + 1] = b
        if #chosen >= 24 then break end
      end
    end
    if #chosen >= 24 then break end
  end
  for idx, b in ipairs(all) do
    if #chosen >= 24 then break end
    if not used[idx] then chosen[#chosen + 1] = b end
  end
  for idx, b in ipairs(chosen) do
    local ll = b.label:lower()
    if ll:find("power") and not ll:find("off") then b.id = "power"
    elseif ll:find("vol.*%+") or ll == "vol+" then b.id = "vol_up"
    elseif ll:find("vol.*%-") or ll == "vol-" then b.id = "vol_down"
    elseif ll:find("mute") then b.id = "mute"
    else b.id = "k_" .. tostring(idx) end
  end
  return chosen
end

local function infer_irdb_category(cat_str)
  local c = (cat_str or ""):lower()
  if c:find("tv") or c:find("tele") or c:find("projector") then return "tv" end
  if c:find("fan") then return "fan" end
  if c:find("audio") or c:find("amp") or c:find("receiver") or c:find("sound") or c:find("speaker") or c:find("cd") then return "audio" end
  if c:find("air") or c:find("ac") then return "ac" end
  return "other"
end


local function search_catalog(params)
  local _res = nil
  local function out_json(t) _res = t end
  ;(function()
    local q = trim(params.query or ""):lower()
    local cat_filter = trim(params.category or "all"):lower()
    local include_online = (params.include_online == true or cat_filter == "irdb")
    local tokens = {}
    for tok in q:gmatch("%S+") do tokens[#tokens + 1] = tok end

    local results = {}
    if cat_filter ~= "irdb" then
      for _, it in ipairs(BUILTIN_CATALOG) do
        if cat_filter == "all" or it.category == cat_filter then
          local match = true
          for _, tk in ipairs(tokens) do
            if not it.search:find(tk, 1, true) and not it.name:lower():find(tk, 1, true) then
              match = false; break
            end
          end
          if match then
            results[#results + 1] = {
              id = it.id, source = "builtin", category = it.category,
              driver = it.driver, type = it.type, brand = it.brand,
              name = it.name, subtitle = it.subtitle,
              button_count = it.buttons and #it.buttons or nil,
            }
          end
        end
      end
    end

    if include_online or (#tokens > 0 and #results < 5) then
      local idx = ensure_irdb_index()
      if idx then
        local online_cnt = 0
        for line in idx:gmatch("[^\r\n]+") do
          local low = line:lower()
          local match = true
          for _, tk in ipairs(tokens) do
            if not low:find(tk, 1, true) then match = false; break end
          end
          if match then
            local b_brand, b_cat, b_model = line:match("^([^/]+)/([^/]+)/(.+)%.csv$")
            if b_brand and b_cat then
              local inferred = infer_irdb_category(b_cat)
              if cat_filter == "all" or cat_filter == "irdb" or inferred == cat_filter then
                results[#results + 1] = {
                  id = "irdb:" .. line, irdb_path = line, source = "irdb",
                  category = inferred, driver = "tuya_ir_remote", type = "ir_remote",
                  brand = b_brand, name = b_brand .. " — " .. b_cat:gsub("_", " "),
                  subtitle = "Kho Online IRDB (" .. (b_model or "") .. ")",
                }
                online_cnt = online_cnt + 1
                if online_cnt >= 25 or #results >= 40 then break end
              end
            end
          end
        end
      end
    end
    out_json({ ok = true, results = results, online_cached = (read_file(IRDB_CACHE) ~= nil) })

  end)()
  return _res
end

local function test_catalog_item(params, reg, lan_hosts, cfg)
  local _res = nil
  local function out_json(t) _res = t end
  ;(function()
    local cid = trim(params.catalog_id)
    local ipath = trim(params.irdb_path)
    local ctrl_id = trim(params.controller_id)
    if ctrl_id == "" then ctrl_id = "s06_default" end
    local dry = (params.dry_run == true)
    local pkt, label_tested

    if cid ~= "" and BUILTIN_BY_ID[cid] then
      local item = BUILTIN_BY_ID[cid]
      if item.type == "ac" and ok_ac then
        pkt = ac_ir.encode(item.brand, { power = true, temp = 26, mode = "cool", fan = "auto", swing = false }, "on")
        label_tested = item.name .. " (Bật 26°C)"
      elseif item.buttons then
        for _, b in ipairs(item.buttons) do
          if b.proto and ok_ac and ac_ir.supports_generic(b.proto) then
            pkt = ac_ir.encode_generic(b.proto, b.dev, b.sub, b.fn)
            label_tested = item.name .. " — " .. b.label
            break
          end
        end
      end
    elseif ipath ~= "" then
      local btns, err = fetch_irdb_csv_buttons(ipath)
      if not btns then
        out_json({ ok = false, message = "Không tải được hoặc chưa hỗ trợ chuẩn IR file này: " .. tostring(err) })
        return
      end
      pkt = ac_ir.encode_generic(btns[1].proto, btns[1].dev, btns[1].sub, btns[1].fn)
      label_tested = ipath .. " — " .. btns[1].label
    end

    if not pkt then
      out_json({ ok = false, message = "Mẫu này dùng Học phím — hãy Thêm rồi bấm Học từng nút bằng remote thật!" })
      return
    end
    if dry then
      out_json({ ok = true, dry_run = true, tested = label_tested, protocol = pkt.protocol, head_len = #pkt.head, key_len = #pkt.key })
      return
    end
    local ctrl = find_controller(reg, ctrl_id)
    if not ctrl then out_json({ ok = false, message = "Không tìm thấy cục phát S06" }); return end
    local hip, hdid, hlkey, hct = heal_controller_ip(ctrl, lan_hosts, cfg)
    if not ok_tuya or #hlkey ~= 16 then
      out_json({ ok = false, message = "Cục phát [" .. ctrl.name .. "] chưa có Local Key 16 ký tự" })
      return
    end
    local ok, err = tuya_v35.send_head_key(hip, hdid, hlkey, pkt.head, pkt.key, hct)
    out_json({ ok = ok and true or false, message = ok and ("Đã bắn thử [" .. label_tested .. "] qua " .. ctrl.name .. "!") or ("Lỗi gửi: " .. tostring(err)) })

  end)()
  return _res
end

return {
  BUILTIN_CATALOG = BUILTIN_CATALOG,
  BUILTIN_BY_ID = BUILTIN_BY_ID,
  ensure_irdb_index = ensure_irdb_index,
  is_valid_irdb_path = is_valid_irdb_path,
  fetch_irdb_csv_buttons = fetch_irdb_csv_buttons,
  infer_irdb_category = infer_irdb_category,
  search_catalog = search_catalog,
  test_catalog_item = test_catalog_item,
}
-- [/VERIFIED-GOLDEN]
