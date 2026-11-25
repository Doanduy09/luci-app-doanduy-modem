#!/usr/bin/lua
-- DOANDUY 5G PCIe AT & SMS Engine (Raw POSIX WWAN FD + QMI WMS + PDU/UTF-8)
local nixio = require("nixio")

-- Ensure exclusive access against modem_lock_run (/var/lock/modem_at.lock)
if os.getenv("_AT_FLOCKED") ~= "1" and os.getenv("_MODEM_AT_LOCKED") ~= "1" and nixio.fs.access("/usr/bin/modem_lock_run") then
    local qargs = {}
    for i = 0, #arg do
        qargs[#qargs + 1] = "'" .. tostring(arg[i]):gsub("'", "'\\''") .. "'"
    end
    local rc = os.execute("_AT_FLOCKED=1 exec /usr/bin/modem_lock_run /usr/bin/lua " .. table.concat(qargs, " "))
    os.exit((rc == 0 or rc == true) and 0 or 1)
end

local bit = nixio.bit
local band, bor, lshift, rshift = bit.band, bit.bor, bit.lshift, bit.rshift

local function find_at_port(preferred)
    if preferred and #preferred > 0 and nixio.fs.stat(preferred, "type") == "chr" then
        return preferred
    end
    for _, p in ipairs({"/dev/wwan0at0", "/dev/mhi_DUN", "/dev/wwan1at0"}) do
        if nixio.fs.stat(p, "type") == "chr" then return p end
    end
    return nil
end

local function open_at_fd(port)
    local fd = nixio.open(port, nixio.open_flags("rdwr", "nonblock"))
    if not fd then return nil end
    -- Drain any stale bytes already queued in kernel buffer
    for _ = 1, 8 do
        local d = fd:read(4096)
        if not d or #d == 0 then break end
    end
    return fd
end

local function read_raw_until(fd, timeout_ms, wait_prompt)
    timeout_ms = timeout_ms or 2500
    local buf = {}
    local fds = {{fd = fd, events = nixio.poll_flags("in")}}
    local elapsed = 0
    local step_ms = 120
    while elapsed < timeout_ms do
        local ready = nixio.poll(fds, step_ms)
        if ready and ready > 0 then
            local chunk = fd:read(4096)
            if chunk and #chunk > 0 then
                buf[#buf + 1] = chunk
                local full = table.concat(buf)
                if wait_prompt and full:find(">") then return full end
                if full:match("\r?\nOK\r?\n?$") or full:match("^OK\r?\n?$")
                   or full:find("\nERROR") or full:find("\rERROR")
                   or full:find("+CME ERROR") or full:find("+CMS ERROR") then
                    return full
                end
            end
        end
        elapsed = elapsed + step_ms
    end
    return table.concat(buf)
end

local function send_raw_at(fd, cmd, timeout_ms, wait_prompt)
    if not fd:write(cmd .. "\r") then return "" end
    return read_raw_until(fd, timeout_ms, wait_prompt)
end

-- GSM-7 default alphabet + common extension subset to UTF-8
local GSM7_BASIC = {
    [0]="@",[1]="£",[2]="$",[3]="¥",[4]="è",[5]="é",[6]="ù",[7]="ì",
    [8]="ò",[9]="Ç",[10]="\n",[11]="Ø",[12]="ø",[13]="\r",[14]="Å",[15]="å",
    [16]="Δ",[17]="_",[18]="Φ",[19]="Γ",[20]="Λ",[21]="Ω",[22]="Π",[23]="Ψ",
    [24]="Σ",[25]="Θ",[26]="Ξ",[27]="",[28]="Æ",[29]="æ",[30]="ß",[31]="É",
    [32]=" ",[33]="!",[34]="\"",[35]="#",[36]="¤",[37]="%",[38]="&",[39]="'",
    [40]="(",[41]=")",[42]="*",[43]="+",[44]=",",[45]="-",[46]=".",[47]="/",
    [58]=":",[59]=";",[60]="<",[61]="=",[62]=">",[63]="?",[64]="¡",
    [91]="Ä",[92]="Ö",[93]="Ñ",[94]="Ü",[95]="§",[96]="¿",
    [123]="ä",[124]="ö",[125]="ñ",[126]="ü",[127]="à"
}
local GSM7_EXT = {
    [10]="\f",[20]="^",[40]="{",[41]="}",[47]="\\",[60]="[",[61]="~",[62]="]",[64]="|",[101]="€"
}

local function codepoint_utf8(cp)
    if cp < 0x80 then return string.char(cp)
    elseif cp < 0x800 then return string.char(0xC0 + math.floor(cp / 64), 0x80 + (cp % 64))
    elseif cp < 0x10000 then
        return string.char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor((cp % 4096) / 64), 0x80 + (cp % 64))
    end
    return ""
end

local function ucs2_to_utf8(hex)
    if not hex or #hex < 4 then return hex or "" end
    local res = {}
    for i = 1, #hex - 3, 4 do
        local cp = tonumber(hex:sub(i, i + 3), 16)
        if cp and cp > 0 then res[#res + 1] = codepoint_utf8(cp) end
    end
    return table.concat(res)
end

local function unpack_gsm7(bytes, start_byte_idx, total_septets, skip_septets)
    local out = {}
    local esc = false
    for s = skip_septets, total_septets - 1 do
        local bit_pos = s * 7
        local b_idx = start_byte_idx + math.floor(bit_pos / 8)
        local b_off = bit_pos % 8
        local b1 = bytes[b_idx] or 0
        local b2 = bytes[b_idx + 1] or 0
        local val = band(rshift(b1, b_off), 0x7F)
        if b_off > 1 then
            val = band(bor(val, lshift(b2, 8 - b_off)), 0x7F)
        end
        if esc then
            out[#out + 1] = GSM7_EXT[val] or ""
            esc = false
        elseif val == 27 then
            esc = true
        else
            out[#out + 1] = GSM7_BASIC[val] or string.char(val)
        end
    end
    return table.concat(out)
end

local function swap_nibbles(bytes, idx, count)
    local res = {}
    for i = 0, count - 1 do
        local b = bytes[idx + i] or 0
        local lo = band(b, 0x0F)
        local hi = rshift(b, 4)
        res[#res + 1] = string.format("%x", lo)
        if hi ~= 0x0F then res[#res + 1] = string.format("%x", hi) end
    end
    return table.concat(res)
end

local function decode_pdu(idx, storage, hex)
    local bytes = {}
    for h in hex:gmatch("%x%x") do bytes[#bytes + 1] = tonumber(h, 16) end
    if #bytes < 10 then return nil end

    local pos = 1
    local sca_len = bytes[pos]; pos = pos + 1 + sca_len
    if pos > #bytes then return nil end

    local pdu_type = bytes[pos]; pos = pos + 1
    local mti = band(pdu_type, 0x03)
    if mti ~= 0 then return nil end -- only parse SMS-DELIVER inbox entries

    local udhi = band(pdu_type, 0x40) ~= 0
    local oa_len = bytes[pos] or 0; pos = pos + 1
    local oa_type = bytes[pos] or 0x81; pos = pos + 1
    local oa_bytes = math.ceil(oa_len / 2)
    local sender
    if band(oa_type, 0x70) == 0x50 then
        local oa_septets = math.floor((oa_len * 4) / 7)
        sender = unpack_gsm7(bytes, pos, oa_septets, 0)
    else
        sender = swap_nibbles(bytes, pos, oa_bytes)
        if band(oa_type, 0x70) == 0x10 and #sender > 0 then sender = "+" .. sender end
    end
    pos = pos + oa_bytes

    pos = pos + 1 -- PID
    local dcs = bytes[pos] or 0; pos = pos + 1

    local scts = {}
    for i = 0, 5 do
        local b = bytes[pos + i] or 0
        scts[i + 1] = string.format("%d%d", band(b, 0x0F), rshift(b, 4))
    end
    pos = pos + 7
    local timestamp = string.format("20%s/%s/%s %s:%s:%s", scts[1], scts[2], scts[3], scts[4], scts[5], scts[6])

    local udl = bytes[pos] or 0; pos = pos + 1
    local alphabet = 0
    if band(dcs, 0xC0) == 0x00 or band(dcs, 0xF0) == 0xF0 then
        local enc = band(dcs, 0x0C)
        if enc == 0x04 then alphabet = 1
        elseif enc == 0x08 then alphabet = 2 end
    end

    local ref, part, parts = nil, nil, nil
    local udhl = 0
    if udhi and pos <= #bytes then
        udhl = bytes[pos] or 0
        local p_ie = pos + 1
        local p_end = math.min(#bytes, pos + udhl)
        while p_ie + 1 <= p_end do
            local iei = bytes[p_ie]
            local ielen = bytes[p_ie + 1] or 0
            if iei == 0x00 and ielen == 3 and p_ie + 4 <= p_end then
                ref = bytes[p_ie + 2]
                parts = bytes[p_ie + 3]
                part = bytes[p_ie + 4]
            elseif iei == 0x08 and ielen == 4 and p_ie + 5 <= p_end then
                ref = bor(lshift(bytes[p_ie + 2], 8), bytes[p_ie + 3])
                parts = bytes[p_ie + 4]
                part = bytes[p_ie + 5]
            end
            p_ie = p_ie + 2 + ielen
        end
    end

    local body = ""
    if alphabet == 0 then
        local skip = udhi and math.ceil((udhl + 1) * 8 / 7) or 0
        body = unpack_gsm7(bytes, pos, udl, skip)
    elseif alphabet == 2 then
        local start_u = udhi and (pos + 1 + udhl) or pos
        local uhex = {}
        for i = start_u, #bytes do uhex[#uhex + 1] = string.format("%02X", bytes[i]) end
        body = ucs2_to_utf8(table.concat(uhex))
    else
        local start_u = udhi and (pos + 1 + udhl) or pos
        local raw = {}
        for i = start_u, #bytes do raw[#raw + 1] = string.char(bytes[i]) end
        body = table.concat(raw)
    end

    return {
        id = tonumber(idx),
        storage = storage,
        sender = (#sender > 0) and sender or "Tong Dai",
        timestamp = timestamp,
        body = body,
        ref = ref,
        part = part,
        parts = parts
    }
end

local function write_inbox_json(final_list)
    table.sort(final_list, function(a, b)
        return (a.timestamp or "") > (b.timestamp or "")
    end)
    local formatted = {}
    for _, m in ipairs(final_list) do
        local st_label = (m.storage == "sim" or m.storage == "SM") and "[ THẺ SIM (SM) ]" or "[ ROUTER (ME) ]"
        table.insert(formatted, string.format("%s\nMSG: %d\nFrom: %s\nDate/Time: %s\n%s",
            st_label, m.id or 1, m.sender or "?", m.timestamp or "", m.body or ""))
    end
    local out_f = io.open("/tmp/sms_inbox.json", "w")
    if out_f then
        if #formatted > 0 then
            local combined = table.concat(formatted, "\n\n")
            local esc = combined:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\r', ''):gsub('\n', '\\n')
            out_f:write('"' .. esc .. '"')
        else
            out_f:write('"Hộp thư trống hoặc chưa có tin nhắn mới."')
        end
        out_f:close()
    end
    return formatted
end

local function group_and_save(raw_messages)
    local grouped, final_list = {}, {}
    for _, msg in ipairs(raw_messages) do
        if msg.ref and msg.parts and msg.parts > 1 then
            local key = (msg.storage or "") .. "_" .. (msg.sender or "") .. "_" .. tostring(msg.ref)
            if not grouped[key] then
                grouped[key] = { id = msg.id, storage = msg.storage or "me", sender = msg.sender, timestamp = msg.timestamp, parts = {}, ids = {} }
            end
            grouped[key].parts[msg.part or 1] = msg.body
            grouped[key].ids[#grouped[key].ids + 1] = msg.id
        else
            table.insert(final_list, msg)
        end
    end
    for _, g in pairs(grouped) do
        local full_body = {}
        for i = 1, 16 do
            if g.parts[i] then full_body[#full_body + 1] = g.parts[i] end
        end
        table.insert(final_list, {
            id = g.ids[1] or g.id or 1,
            storage = g.storage,
            sender = g.sender,
            timestamp = g.timestamp,
            body = table.concat(full_body)
        })
    end
    return write_inbox_json(final_list)
end

local function read_qmi_sms()
    local dev = "/dev/wwan0qmi0"
    if not nixio.fs.stat(dev) then dev = "/dev/cdc-wdm0" end
    os.execute("killall -STOP quectel-CM-M quectel-CM 2>/dev/null")
    local raw_messages = {}
    local ok, err = pcall(function()
        for _, st in ipairs({"me", "sim"}) do
            local h = io.popen(string.format("uqmi -s -t 2500 -d %s --storage %s --list-messages 2>/dev/null", dev, st))
            if h then
                local out = (h:read("*a") or ""):gsub("[%[%]\r\n%s]+", "")
                h:close()
                for id in out:gmatch("%d+") do
                    local h_msg = io.popen(string.format("uqmi -s -t 2000 -d %s --storage %s --get-message %s 2>/dev/null", dev, st, id))
                    if h_msg then
                        local json_str = h_msg:read("*a") or ""
                        h_msg:close()
                        if json_str:find('"sender"') then
                            local sender = json_str:match('"sender"%s*:%s*"([^"]*)"') or "Tong Dai"
                            local ts = json_str:match('"timestamp"%s*:%s*"([^"]*)"') or ""
                            local text = json_str:match('"text"%s*:%s*"([^"]*)"')
                            local ucs2 = json_str:match('"ucs%-2"%s*:%s*"([^"]*)"')
                            local ref = json_str:match('"concat_ref"%s*:%s*(%d+)')
                            local part = json_str:match('"concat_part"%s*:%s*(%d+)')
                            local parts = json_str:match('"concat_parts"%s*:%s*(%d+)')
                            local body = ""
                            if ucs2 and #ucs2 > 0 then body = ucs2_to_utf8(ucs2)
                            elseif text then body = text:gsub("\\n", "\n"):gsub("\\r", ""):gsub('\\"', '"'):gsub("\\\\", "\\") end
                            table.insert(raw_messages, {
                                id = tonumber(id), storage = st, sender = sender:gsub("@", ""),
                                timestamp = ts, body = body,
                                ref = ref and tonumber(ref) or nil,
                                part = part and tonumber(part) or nil,
                                parts = parts and tonumber(parts) or nil
                            })
                        end
                    end
                end
            end
        end
    end)
    os.execute("killall -CONT quectel-CM-M quectel-CM 2>/dev/null")
    if ok then group_and_save(raw_messages) end
end

local function read_at_sms(port)
    local fd = open_at_fd(port)
    if not fd then
        write_inbox_json({})
        return false
    end
    send_raw_at(fd, "ATE0", 1200)
    send_raw_at(fd, "AT+CMGF=0", 1200)
    local raw_messages = {}
    for _, st in ipairs({"ME", "SM"}) do
        local cpms = send_raw_at(fd, string.format('AT+CPMS="%s","%s","%s"', st, st, st), 1500)
        if cpms:find("OK") or cpms:find("+CPMS:") then
            local cmgl = send_raw_at(fd, "AT+CMGL=4", 5000)
            local lines = {}
            for line in cmgl:gmatch("[^\r\n]+") do lines[#lines + 1] = line end
            for i = 1, #lines do
                local idx = lines[i]:match("^%+CMGL:%s*(%d+)")
                if idx and lines[i + 1] and lines[i + 1]:match("^[0-9A-Fa-f]+$") then
                    local decoded = decode_pdu(idx, st, lines[i + 1])
                    if decoded then raw_messages[#raw_messages + 1] = decoded end
                end
            end
        end
    end
    fd:close()
    group_and_save(raw_messages)
    return true
end

local function encode_utf8_to_ucs2_hex(s)
    local hex, i, len = {}, 1, #s
    while i <= len do
        local b1 = s:byte(i)
        local cp = b1
        if b1 >= 0xF0 and i + 3 <= len then
            local b2, b3, b4 = s:byte(i + 1, i + 3)
            cp = bor(lshift(band(b1, 0x07), 18), lshift(band(b2, 0x3F), 12), lshift(band(b3, 0x3F), 6), band(b4, 0x3F))
            i = i + 4
        elseif b1 >= 0xE0 and i + 2 <= len then
            local b2, b3 = s:byte(i + 1, i + 2)
            cp = bor(lshift(band(b1, 0x0F), 12), lshift(band(b2, 0x3F), 6), band(b3, 0x3F))
            i = i + 3
        elseif b1 >= 0xC0 and i + 1 <= len then
            local b2 = s:byte(i + 1)
            cp = bor(lshift(band(b1, 0x1F), 6), band(b2, 0x3F))
            i = i + 2
        else
            i = i + 1
        end
        if cp <= 0xFFFF then hex[#hex + 1] = string.format("%04X", cp) end
    end
    return table.concat(hex)
end

local function encode_tbcd(number)
    local clean = number:gsub("^%+", "")
    local digits = {}
    for c in clean:gmatch("%d") do digits[#digits + 1] = c end
    if #digits % 2 == 1 then digits[#digits + 1] = "F" end
    local out = {}
    for i = 1, #digits, 2 do
        out[#out + 1] = digits[i + 1] .. digits[i]
    end
    return #clean, (number:sub(1, 1) == "+" and "91" or "81"), table.concat(out)
end

local function send_at_sms(port, dest, msg)
    if not dest or #dest == 0 or not msg or #msg == 0 then return false end
    local fd = open_at_fd(port)
    if not fd then return false end
    local is_ascii = not msg:find("[\128-\255]")
    local ok = false
    if is_ascii then
        send_raw_at(fd, "AT+CMGF=1", 1200)
        send_raw_at(fd, 'AT+CSCS="GSM"', 1200)
        local p_resp = send_raw_at(fd, string.format('AT+CMGS="%s"', dest), 3000, true)
        if p_resp:find(">") then
            fd:write(msg .. "\26")
            local res = read_raw_until(fd, 8000)
            ok = (res:find("OK") ~= nil or res:find("+CMGS:") ~= nil)
        end
    else
        send_raw_at(fd, "AT+CMGF=0", 1200)
        local da_len, da_type, da_hex = encode_tbcd(dest)
        local ucs2 = encode_utf8_to_ucs2_hex(msg)
        local udl = math.floor(#ucs2 / 2)
        if udl > 140 then udl = 140; ucs2 = ucs2:sub(1, 280) end
        local pdu = string.format("001100%02X%s%s0008AA%02X%s", da_len, da_type, da_hex, udl, ucs2)
        local tpdu_len = math.floor((#pdu - 2) / 2)
        local p_resp = send_raw_at(fd, string.format("AT+CMGS=%d", tpdu_len), 3000, true)
        if p_resp:find(">") then
            fd:write(pdu .. "\26")
            local res = read_raw_until(fd, 8000)
            ok = (res:find("OK") ~= nil or res:find("+CMGS:") ~= nil)
        end
    end
    fd:close()
    return ok
end

-- Parse CLI arguments
local mode = "read"
local port_arg, at_cmd, sms_dest, sms_body, del_indices, del_storage
local i = 1
while i <= #arg do
    local a = arg[i]
    if a == "-p" or a == "-d" then port_arg = arg[i + 1]; i = i + 2
    elseif a == "--at" then mode = "at"; at_cmd = arg[i + 1]; i = i + 2
    elseif a == "--send" then mode = "send"; sms_dest = arg[i + 1]; sms_body = arg[i + 2]; i = i + 3
    elseif a == "--delete" then
        mode = "delete"
        del_indices = arg[i + 1]
        if arg[i + 2] and arg[i + 2]:sub(1, 1) ~= "-" then
            del_storage = arg[i + 2]
            i = i + 3
        else
            del_storage = "ME"
            i = i + 2
        end
    elseif a == "--delete-all" then mode = "delete_all"; i = i + 1
    elseif a == "--read" then mode = "read"; i = i + 1
    else i = i + 1 end
end

local at_port = find_at_port(port_arg)

if mode == "at" then
    if not at_port or not at_cmd then os.exit(1) end
    local fd = open_at_fd(at_port)
    if not fd then os.exit(1) end
    local resp = send_raw_at(fd, at_cmd, 3000)
    fd:close()
    resp = (resp or ""):gsub("\r", "")
    if #resp > 0 then
        io.write(resp)
        if resp:sub(-1) ~= "\n" then io.write("\n") end
        os.exit(0)
    end
    os.exit(1)
elseif mode == "send" then
    if not at_port then os.exit(1) end
    os.exit(send_at_sms(at_port, sms_dest, sms_body) and 0 or 1)
elseif mode == "delete" then
    if not at_port or not del_indices then os.exit(1) end
    local fd = open_at_fd(at_port)
    if not fd then os.exit(1) end
    local st = (del_storage == "SM" or del_storage == "sim") and "SM" or "ME"
    send_raw_at(fd, string.format('AT+CPMS="%s","%s","%s"', st, st, st), 1500)
    for idx in del_indices:gmatch("%d+") do
        send_raw_at(fd, "AT+CMGD=" .. idx, 2000)
    end
    fd:close()
    os.exit(0)
elseif mode == "delete_all" then
    if not at_port then os.exit(1) end
    local fd = open_at_fd(at_port)
    if not fd then os.exit(1) end
    for _, st in ipairs({"ME", "SM"}) do
        send_raw_at(fd, string.format('AT+CPMS="%s","%s","%s"', st, st, st), 1500)
        send_raw_at(fd, "AT+CMGD=1,4", 3000)
    end
    fd:close()
    write_inbox_json({})
    os.exit(0)
else
    if nixio.fs.stat("/dev/wwan0qmi0", "type") == "chr" or nixio.fs.stat("/dev/cdc-wdm0", "type") == "chr" then
        read_qmi_sms()
    elseif at_port then
        read_at_sms(at_port)
    else
        write_inbox_json({})
    end
end
