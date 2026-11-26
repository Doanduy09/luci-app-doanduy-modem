-- [VERIFIED-GOLDEN: smarthome-mod-net-json-v250 | 2026-11-26 | DO NOT MODIFY UNLESS TARGETED]
-- Scenario 06 (SmartHome) — Module 1/5: 3-Tier JSON Adapter, SSRF Guard & Pure-Nixio HTTP/TCP/UDP Transport
local cjson
do
  local ok_cj, mod_cj = pcall(require, "cjson")
  if ok_cj and mod_cj then
    cjson = mod_cj
  else
    local ok_lj, mod_lj = pcall(require, "luci.jsonc")
    if ok_lj and mod_lj and mod_lj.parse and mod_lj.stringify then
      cjson = { decode = mod_lj.parse, encode = mod_lj.stringify }
    else
      local esc_map = { ['"']='\\"', ['\\']='\\\\', ['\b']='\\b', ['\f']='\\f', ['\n']='\\n', ['\r']='\\r', ['\t']='\\t' }
      local unesc_map = { ['"']='"', ['\\']='\\', ['/']='/', b='\b', f='\f', n='\n', r='\r', t='\t' }
      local function utf8_from_cp(cp)
        if cp < 0x80 then return string.char(cp)
        elseif cp < 0x800 then
          return string.char(0xC0 + math.floor(cp / 64), 0x80 + (cp % 64))
        else
          return string.char(0xE0 + math.floor(cp / 4096), 0x80 + (math.floor(cp / 64) % 64), 0x80 + (cp % 64))
        end
      end
      local function enc_val(v)
        local tv = type(v)
        if v == nil then return "null"
        elseif tv == "boolean" then return v and "true" or "false"
        elseif tv == "number" then
          if v ~= v or v == math.huge or v == -math.huge then return "0" end
          return tostring(v)
        elseif tv == "string" then
          return '"' .. v:gsub('[%z\1-\31"\\]', function(c) return esc_map[c] or string.format("\\u%04x", string.byte(c)) end) .. '"'
        elseif tv == "table" then
          local is_arr, max_k, cnt = true, 0, 0
          for k, _ in pairs(v) do
            cnt = cnt + 1
            if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then is_arr = false; break end
            if k > max_k then max_k = k end
          end
          if cnt == 0 then return "{}" end
          if is_arr and max_k == cnt then
            local parts = {}
            for i = 1, cnt do parts[i] = enc_val(v[i]) end
            return "[" .. table.concat(parts, ",") .. "]"
          end
          local parts = {}
          for k, val in pairs(v) do
            if type(k) == "string" or type(k) == "number" then
              parts[#parts + 1] = enc_val(tostring(k)) .. ":" .. enc_val(val)
            end
          end
          return "{" .. table.concat(parts, ",") .. "}"
        end
        return "null"
      end
      local function dec_str(s)
        local pos, len = 1, #s
        local function skip_ws()
          local _, e = s:find("^[ \t\r\n]+", pos)
          if e then pos = e + 1 end
        end
        local parse_val
        local function parse_string()
          pos = pos + 1
          local out = {}
          while pos <= len do
            local ch = s:sub(pos, pos)
            if ch == '"' then pos = pos + 1; return table.concat(out) end
            if ch == '\\' then
              local nx = s:sub(pos + 1, pos + 1)
              if nx == 'u' then
                local hex = s:sub(pos + 2, pos + 5)
                local cp = tonumber(hex, 16) or 63
                out[#out + 1] = utf8_from_cp(cp)
                pos = pos + 6
              else
                out[#out + 1] = unesc_map[nx] or nx
                pos = pos + 2
              end
            else
              local nxt_q = s:find('["\\]', pos)
              if nxt_q then
                out[#out + 1] = s:sub(pos, nxt_q - 1)
                pos = nxt_q
              else
                error("unterminated_string")
              end
            end
          end
          error("unterminated_string")
        end
        parse_val = function()
          skip_ws()
          local ch = s:sub(pos, pos)
          if ch == '"' then return parse_string()
          elseif ch == '{' then
            pos = pos + 1; skip_ws()
            local obj = {}
            if s:sub(pos, pos) == '}' then pos = pos + 1; return obj end
            while pos <= len do
              skip_ws()
              local k = parse_string()
              skip_ws()
              assert(s:sub(pos, pos) == ':', "expected_colon")
              pos = pos + 1
              obj[k] = parse_val()
              skip_ws()
              local sep = s:sub(pos, pos)
              if sep == '}' then pos = pos + 1; return obj end
              assert(sep == ',', "expected_comma")
              pos = pos + 1
            end
          elseif ch == '[' then
            pos = pos + 1; skip_ws()
            local arr, idx = {}, 1
            if s:sub(pos, pos) == ']' then pos = pos + 1; return arr end
            while pos <= len do
              arr[idx] = parse_val(); idx = idx + 1
              skip_ws()
              local sep = s:sub(pos, pos)
              if sep == ']' then pos = pos + 1; return arr end
              assert(sep == ',', "expected_array_comma")
              pos = pos + 1
            end
          elseif s:sub(pos, pos + 3) == "true" then pos = pos + 4; return true
          elseif s:sub(pos, pos + 4) == "false" then pos = pos + 5; return false
          elseif s:sub(pos, pos + 3) == "null" then pos = pos + 4; return nil
          else
            local _, ne, num_s = s:find("^([%-]?%d+%.?%d*[eE]?[%+%-]?%d*)", pos)
            if ne and tonumber(num_s) then pos = ne + 1; return tonumber(num_s) end
            error("invalid_json_token")
          end
        end
        local res = parse_val()
        return res
      end
      cjson = { encode = enc_val, decode = dec_str }
    end
  end
end
local nixio = require("nixio")
local ok_tuya, tuya_v35 = pcall(require, "tuya_v35_local")
local ok_ac, ac_ir = pcall(require, "ac_ir_protocols")

local S06_CFG_FILE  = "/etc/duytv_s06_config.json"
local DEVICES_FILE  = "/etc/config/doanduy_smarthome.json"
local KEYS_FILE     = "/etc/config/doanduy_smarthome_keys.json"
local HUB_DEV_FILE  = "/etc/duytv_lan_devices.json"
local IRDB_CACHE    = "/tmp/irdb_index.txt"
local HUB_HTTP      = "http://127.0.0.1:8996"

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local d = f:read("*a")
  f:close()
  return d
end

local function write_atomic(path, content, mode)
  local dir = path:match("^(.+)/[^/]+$")
  if dir then os.execute("mkdir -p '" .. dir:gsub("'", "'\\''") .. "' >/dev/null 2>&1") end
  local tmp = path .. ".tmp"
  local f = assert(io.open(tmp, "wb"))
  f:write(content)
  f:close()
  os.rename(tmp, path)
  if mode then os.execute("chmod " .. mode .. " '" .. path:gsub("'", "'\\''") .. "' >/dev/null 2>&1") end
end

local function trim(s)
  return (tostring(s or "")):gsub("^%s+", ""):gsub("%s+$", "")
end

local function sh_quote(s)
  return "'" .. tostring(s or ""):gsub("'", "'\\''") .. "'"
end

local function url_encode(s)
  return (tostring(s or "")):gsub("([^%w%-%._~ /])", function(c)
    return string.format("%%%02X", string.byte(c))
  end):gsub(" ", "%%20")
end

-- [VERIFIED-GOLDEN: smarthome-http-fallback | 2026-11-26 | DO NOT MODIFY UNLESS TARGETED]
local function http_fetch_raw(url, timeout_s)
  local tm = tonumber(timeout_s) or 3
  local q = sh_quote(url)
  local cmd = string.format(
    "if command -v curl >/dev/null 2>&1; then curl -4 -sSL --connect-timeout 2 -m %d %s 2>/dev/null; " ..
    "elif command -v uclient-fetch >/dev/null 2>&1; then timeout %d uclient-fetch -q -T %d -O - %s 2>/dev/null; " ..
    "elif command -v wget >/dev/null 2>&1; then timeout %d wget -q -T %d -O - %s 2>/dev/null; fi",
    tm, q, tm + 2, tm, q, tm + 2, tm, q
  )
  local p = io.popen(cmd)
  if not p then return "" end
  local raw = p:read("*a") or ""
  p:close()
  return raw
end
-- [/VERIFIED-GOLDEN]

local function nixio_http_request(method, url, body, timeout_ms, max_bytes)
  local hostport, path = url:match("^http://([^/%?#]+)(.*)$")
  if not hostport then return nil, "not_plain_http" end
  local host, port_s = hostport:match("^([^:]+):(%d+)$")
  local port = 80
  if host then
    port = tonumber(port_s) or 80
  else
    host = hostport
  end
  if path == "" then path = "/" end
  local m = (type(method) == "string" and method:upper() == "POST") and "POST" or "GET"
  local payload = (type(body) == "string") and body or ""
  local mx = tonumber(max_bytes) or 32768
  local tm_ms = tonumber(timeout_ms) or 1800

  local s = nixio.socket("inet", "stream")
  if not s then return nil, "socket_failed" end
  s:setblocking(false)
  local t_end = (nixio.gettimeofday and (function() local a,b=nixio.gettimeofday(); return a*1000+math.floor(b/1000) end)() or (os.time()*1000)) + tm_ms
  local function rem_ms()
    if nixio.gettimeofday then
      local a, b = nixio.gettimeofday()
      return math.max(0, t_end - (a * 1000 + math.floor(b / 1000)))
    end
    return math.max(0, t_end - os.time() * 1000)
  end

  local ok = s:connect(host, port)
  if not ok then
    local fds = {{ fd = s, events = nixio.poll_flags("out") }}
    local rc = nixio.poll(fds, math.min(1000, math.max(150, rem_ms())))
    if not rc or rc <= 0 or (fds[1].revents or 0) <= 0 or s:getopt("socket", "error") ~= 0 then
      s:close()
      return nil, "connect_failed"
    end
  end

  local hdrs = {
    string.format("%s %s HTTP/1.0", m, path),
    "Host: " .. hostport,
    "User-Agent: DoanDuy-SmartHome/2.4.6",
    "Accept: */*",
    "Connection: close",
  }
  if m == "POST" or #payload > 0 then
    local ct = (payload:match("^%s*[%[{]") ~= nil) and "application/json" or "text/plain"
    hdrs[#hdrs + 1] = "Content-Type: " .. ct
    hdrs[#hdrs + 1] = "Content-Length: " .. tostring(#payload)
  end
  local req_pkt = table.concat(hdrs, "\r\n") .. "\r\n\r\n" .. payload
  local sent = 0
  while sent < #req_pkt do
    local w = s:send(req_pkt:sub(sent + 1))
    if w and w > 0 then
      sent = sent + w
    else
      local wfds = {{ fd = s, events = nixio.poll_flags("out") }}
      if (nixio.poll(wfds, math.max(50, rem_ms())) or 0) <= 0 then break end
    end
  end

  local chunks, total = {}, 0
  local rfds = {{ fd = s, events = nixio.poll_flags("in") }}
  while total < mx + 4096 do
    local rwait = rem_ms()
    if rwait <= 0 then break end
    local rc = nixio.poll(rfds, rwait)
    if not rc or rc <= 0 then break end
    local chunk = s:recv(4096)
    if chunk and #chunk > 0 then
      chunks[#chunks + 1] = chunk
      total = total + #chunk
    elseif chunk == "" then
      break
    end
  end
  s:close()
  local full = table.concat(chunks)
  if full == "" then return "", nil end
  local sep = full:find("\r\n\r\n", 1, true)
  local resp_body = sep and full:sub(sep + 4) or full
  if #resp_body > mx then resp_body = resp_body:sub(1, mx) end
  return resp_body, nil
end

local function http_get_json(url, timeout_s)
  if type(url) == "string" and url:match("^http://") then
    local nraw, nerr = nixio_http_request("GET", url, nil, math.floor((tonumber(timeout_s) or 1.2) * 1000), 32768)
    if nraw ~= nil then
      if nraw == "" then return nil end
      local ok, dec = pcall(cjson.decode, nraw)
      return ok and dec or nil
    end
    if nerr == "connect_failed" then return nil end
  end
  local raw = http_fetch_raw(url, timeout_s or 3)
  if raw == "" then return nil end
  local ok, dec = pcall(cjson.decode, raw)
  return ok and dec or nil
end

local _ROUTER_LAN_IPS = nil
local function get_router_lan_ips()
  if _ROUTER_LAN_IPS then return _ROUTER_LAN_IPS end
  local ips = { ["192.168.1.1"] = true }
  local p = io.popen("ip -4 -o addr show dev br-lan 2>/dev/null")
  if p then
    local raw = p:read("*a") or ""
    p:close()
    for ip in raw:gmatch("inet%s+(%d+%.%d+%.%d+%.%d+)/") do
      ips[ip] = true
    end
  end
  local uip = io.popen("uci -q get network.lan.ipaddr 2>/dev/null")
  if uip then
    local raw = trim(uip:read("*a") or "")
    uip:close()
    local ip = raw:match("^(%d+%.%d+%.%d+%.%d+)$")
    if ip then ips[ip] = true end
  end
  _ROUTER_LAN_IPS = ips
  return ips
end

local function is_private_lan_ip(ip, allow_router_ip)
  if type(ip) ~= "string" then return false end
  local a, b, c, d = ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
  if not a then return false end
  a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
  if not a or a > 255 or b > 255 or c > 255 or d > 255 then return false end
  if a == 0 or a == 127 or a >= 224 then return false end
  if a == 169 and b == 254 then return false end
  local is_rfc1918 = (a == 10) or (a == 192 and b == 168) or (a == 172 and b >= 16 and b <= 31)
  if not is_rfc1918 then return false end
  if not allow_router_ip and get_router_lan_ips()[ip] then return false end
  return true
end

local function parse_and_validate_lan_target(raw_input)
  local s = trim(raw_input)
  if s == "" then
    return nil, nil, nil, "Vui lòng nhập địa chỉ IP LAN (VD: 192.168.1.50)"
  end
  if s:find("[%s%c]") then
    return nil, nil, nil, "Địa chỉ IP không được chứa khoảng trắng hoặc ký tự điều khiển"
  end
  local scheme = s:match("^([%a%d%+%-%.]+)://")
  if scheme then
    local sl = scheme:lower()
    if sl ~= "http" and sl ~= "https" then
      return nil, nil, nil, "Chỉ hỗ trợ IP LAN hoặc URL http/https"
    end
    s = s:sub(#scheme + 4)
  end
  if s:find("@", 1, true) then
    return nil, nil, nil, "URL không hợp lệ"
  end
  local hostport, path = s:match("^([^/%?#]+)(.*)$")
  if not hostport then hostport = s; path = "" end
  local host, port_s = hostport:match("^([^:]+):(%d+)$")
  local port = nil
  if host then
    port = tonumber(port_s)
    if not port or port < 1 or port > 65535 then
      return nil, nil, nil, "Cổng (Port) không hợp lệ (1-65535)"
    end
  else
    if hostport:find(":", 1, true) then
      return nil, nil, nil, "Địa chỉ IP hoặc cổng không hợp lệ"
    end
    host = hostport
  end
  if not is_private_lan_ip(host, false) then
    return nil, nil, nil, "Chỉ chấp nhận IP mạng LAN nội bộ (192.168.x.x / 10.x.x.x / 172.16-31.x.x); đã chặn localhost / IP công cộng / Router"
  end
  return host, port, path or "", nil
end

local function is_lan_http_url(url)
  if type(url) ~= "string" or url == "" then return false end
  if url:find("[%s%c]") then return false end
  local scheme, rest = url:match("^(https?)://(.+)$")
  if not scheme or not rest then return false end
  local hostport = rest:match("^([^/%?#]+)")
  if not hostport or hostport:find("@", 1, true) then return false end
  local host, port_s = hostport:match("^([^:]+):(%d+)$")
  if host then
    local p = tonumber(port_s)
    if not p or p < 1 or p > 65535 then return false end
  else
    if hostport:find(":", 1, true) then return false end
    host = hostport
  end
  return is_private_lan_ip(host, false)
end

local function now_ms()
  if nixio.gettimeofday then
    local sec, usec = nixio.gettimeofday()
    return (sec * 1000) + math.floor(usec / 1000)
  end
  return os.time() * 1000
end

local function http_request_lan(method, url, body, timeout_s, max_bytes)
  if not is_lan_http_url(url) then
    return "", "blocked_non_lan_url"
  end
  local tm = tonumber(timeout_s) or 2
  local mx = tonumber(max_bytes) or 32768
  local m = (type(method) == "string" and method:upper() == "POST") and "POST" or "GET"
  if url:match("^http://") then
    local nraw, nerr = nixio_http_request(m, url, body, tm * 1000, mx)
    if nraw ~= nil then return nraw, nil end
    return "", nerr
  end
  local q = sh_quote(url)
  local tmp_body = nil
  local cmd
  if m == "POST" or (type(body) == "string" and body ~= "") then
    local payload = tostring(body or "")
    tmp_body = string.format("/tmp/.dd_sh_%d_%d.req", nixio.getpid and nixio.getpid() or 1, os.time())
    local bf = io.open(tmp_body, "wb")
    if bf then
      bf:write(payload)
      bf:close()
    end
    local ct = (payload:match("^%s*[%[{]") ~= nil) and "application/json" or "text/plain"
    cmd = string.format(
      "curl -4 -sS --max-filesize %d --connect-timeout 1 -m %d -X POST -H %s --data-binary @%s %s 2>/dev/null",
      mx, tm, sh_quote("Content-Type: " .. ct), sh_quote(tmp_body), q
    )
  else
    cmd = string.format(
      "if command -v curl >/dev/null 2>&1; then curl -4 -sSL --max-filesize %d --connect-timeout 1 -m %d %s 2>/dev/null; " ..
      "elif command -v uclient-fetch >/dev/null 2>&1; then timeout %d uclient-fetch -q -T %d -O - %s 2>/dev/null | head -c %d; " ..
      "elif command -v wget >/dev/null 2>&1; then timeout %d wget -q -T %d -O - %s 2>/dev/null | head -c %d; fi",
      mx, tm, q, tm + 1, tm, q, mx, tm + 1, tm, q, mx
    )
  end
  local p = io.popen(cmd)
  local raw = ""
  if p then
    raw = p:read("*a") or ""
    p:close()
  end
  if tmp_body then os.remove(tmp_body) end
  if #raw > mx then raw = raw:sub(1, mx) end
  return raw, nil
end

local function tcp_probe_batch(targets, timeout_ms)
  local open_map = {}
  local chunk_sz = 48
  local poll_out = nixio.poll_flags("out")
  local max_ms = tonumber(timeout_ms) or 700
  local idx = 1
  while idx <= #targets do
    local active = {}
    local stop_idx = math.min(#targets, idx + chunk_sz - 1)
    for j = idx, stop_idx do
      local t = targets[j]
      local s = nixio.socket("inet", "stream")
      if s then
        s:setblocking(false)
        local ok, errno = s:connect(t.ip, t.port)
        if ok then
          open_map[t.ip] = open_map[t.ip] or {}
          open_map[t.ip][t.port] = true
          s:close()
        elseif errno == nil or errno == 115 or errno == 11 then
          active[#active + 1] = { fd = s, events = poll_out, ip = t.ip, port = t.port }
        else
          s:close()
        end
      end
    end
    local deadline = now_ms() + max_ms
    while #active > 0 do
      local rem = deadline - now_ms()
      if rem <= 0 then break end
      local rc = nixio.poll(active, rem)
      if not rc or rc <= 0 then break end
      local next_active = {}
      for _, f in ipairs(active) do
        if (f.revents or 0) > 0 then
          local err = f.fd:getopt("socket", "error")
          if err == 0 then
            open_map[f.ip] = open_map[f.ip] or {}
            open_map[f.ip][f.port] = true
          end
          f.fd:close()
        else
          next_active[#next_active + 1] = f
        end
      end
      active = next_active
    end
    for _, f in ipairs(active) do pcall(function() f.fd:close() end) end
    idx = stop_idx + 1
  end
  return open_map
end

local function tcp_send_recv(ip, port, payload, wait_ms)
  if not is_private_lan_ip(ip, false) then return nil, "invalid_ip" end
  port = tonumber(port)
  if not port or port < 1 or port > 65535 then return nil, "invalid_port" end
  local s = nixio.socket("inet", "stream")
  if not s then return nil, "socket_failed" end
  s:setblocking(false)
  local ok = s:connect(ip, port)
  if not ok then
    local fds = {{ fd = s, events = nixio.poll_flags("out") }}
    local rc = nixio.poll(fds, 1200)
    if not rc or rc <= 0 or (fds[1].revents or 0) <= 0 or s:getopt("socket", "error") ~= 0 then
      s:close()
      return nil, "connect_timeout"
    end
  end
  if payload and payload ~= "" then s:send(payload) end
  local in_fds = {{ fd = s, events = nixio.poll_flags("in") }}
  local r2 = nixio.poll(in_fds, tonumber(wait_ms) or 500)
  local out = ""
  if r2 and r2 > 0 then
    out = s:recv(4096) or ""
  end
  s:close()
  return out, nil
end

local function udp_send_once(ip, port, payload)
  if not is_private_lan_ip(ip, false) then return false, "invalid_ip" end
  port = tonumber(port)
  if not port or port < 1 or port > 65535 then return false, "invalid_port" end
  local s = nixio.socket("inet", "dgram")
  if not s then return false, "socket_failed" end
  pcall(function() s:sendto(tostring(payload or ""), ip, port) end)
  s:close()
  return true, nil
end

local function sniff_tuya_udp(wait_ms)
  local found = {}
  local fds = {}
  for _, port in ipairs({ 6666, 6667 }) do
    local s = nixio.socket("inet", "dgram")
    if s then
      local ok = pcall(function()
        s:setopt("socket", "reuseaddr", 1)
        s:setopt("socket", "broadcast", 1)
        s:bind(nil, port)
        s:setblocking(false)
      end)
      if ok then
        fds[#fds + 1] = { fd = s, events = nixio.poll_flags("in"), port = port }
      else
        pcall(function() s:close() end)
      end
    end
  end
  if #fds == 0 then return found end
  local deadline = now_ms() + (tonumber(wait_ms) or 500)
  while true do
    local rem = deadline - now_ms()
    if rem <= 0 then break end
    local rc = nixio.poll(fds, rem)
    if not rc or rc <= 0 then break end
    for _, f in ipairs(fds) do
      if (f.revents or 0) > 0 then
        local d, sip = f.fd:recvfrom(2048)
        if d and sip and is_private_lan_ip(sip, false) then
          local js = d:match("(%b{})")
          local parsed = nil
          if js then
            local okj, dec = pcall(cjson.decode, js)
            if okj and type(dec) == "table" and dec.gwId then parsed = dec end
          end
          found[sip] = {
            port = f.port,
            gwId = parsed and tostring(parsed.gwId or "") or "",
            version = parsed and tostring(parsed.version or "") or ((f.port == 6667) and "3.3+" or "3.1"),
            productKey = parsed and tostring(parsed.productKey or "") or "",
          }
        end
      end
    end
  end
  for _, f in ipairs(fds) do pcall(function() f.fd:close() end) end
  return found
end

local function tcp_open(ip, port, timeout_ms)
  local res = tcp_probe_batch({{ ip = ip, port = port }}, timeout_ms or 180)
  return (res[ip] and res[ip][port]) and true or false
end

return {
  cjson = cjson,
  nixio = nixio,
  read_file = read_file,
  write_atomic = write_atomic,
  trim = trim,
  sh_quote = sh_quote,
  url_encode = url_encode,
  http_fetch_raw = http_fetch_raw,
  nixio_http_request = nixio_http_request,
  http_get_json = http_get_json,
  get_router_lan_ips = get_router_lan_ips,
  is_private_lan_ip = is_private_lan_ip,
  parse_and_validate_lan_target = parse_and_validate_lan_target,
  is_lan_http_url = is_lan_http_url,
  now_ms = now_ms,
  http_request_lan = http_request_lan,
  tcp_probe_batch = tcp_probe_batch,
  tcp_send_recv = tcp_send_recv,
  udp_send_once = udp_send_once,
  sniff_tuya_udp = sniff_tuya_udp,
  tcp_open = tcp_open,
}
-- [/VERIFIED-GOLDEN]
