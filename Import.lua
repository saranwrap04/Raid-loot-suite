--[[
    Raid Loot Suite - Import
    Author: Saranwrap

    Accepts pasted text in any of these shapes:
      * rows copied from Excel / Google Sheets (tab separated), with or without a header row
      * CSV content (comma or semicolon separated, quotes supported)
      * the "Plain text" export of this addon
      * the "Discord" export of this addon
      * simple lines:  Item -> Player   or   Boss | Item -> Player MS
]]

local RLT = RaidLootSuite
local strtrim, tonumber, tostring = strtrim, tonumber, tostring

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function Trim(s) return s and strtrim(s) or nil end
local function Blank(s) return s == nil or s == "" end

local function StripItemName(s)
    s = Trim(s or "")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", "")
    s = s:gsub("^%[(.*)%]$", "%1")
    return Trim(s)
end

local VALID_CLASS = {
    WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, PRIEST = true,
    DEATHKNIGHT = true, SHAMAN = true, MAGE = true, WARLOCK = true, DRUID = true,
}

local function NormalizeSpec(s)
    s = (s or ""):upper():gsub("%s", "")
    if s == "MS" or s == "MAINSPEC" or s == "MAIN" then return "MS" end
    if s == "OS" or s == "OFFSPEC" or s == "OFF" then return "OS" end
    if s == "SR" or s == "SOFTRESERVE" or s == "SOFTRES" then return "SR" end
    if s == "DE" or s == "DISENCHANT" or s == "DISENCHANTED" then return "DE" end
end

-- Splits one delimited line, honouring "quoted, cells" and "" escapes.
local function SplitDelimited(line, delim)
    local cells, i, len = {}, 1, #line
    while i <= len + 1 do
        local c = line:sub(i, i)
        if c == '"' then
            local buf, j = {}, i + 1
            while j <= len do
                local ch = line:sub(j, j)
                if ch == '"' then
                    if line:sub(j + 1, j + 1) == '"' then buf[#buf + 1] = '"'; j = j + 2
                    else j = j + 1; break end
                else
                    buf[#buf + 1] = ch; j = j + 1
                end
            end
            -- skip anything until the next delimiter
            local nextDelim = line:find(delim, j, true)
            cells[#cells + 1] = table.concat(buf)
            if not nextDelim then break end
            i = nextDelim + 1
        else
            local nextDelim = line:find(delim, i, true)
            if nextDelim then
                cells[#cells + 1] = line:sub(i, nextDelim - 1)
                i = nextDelim + 1
            else
                cells[#cells + 1] = line:sub(i)
                break
            end
        end
    end
    for k, v in ipairs(cells) do cells[k] = Trim(v) end
    return cells
end

---------------------------------------------------------------------------
-- Dates
---------------------------------------------------------------------------
-- Accepts 2026-10-01, 2026/10/01, 01/10/2026 (day first unless impossible),
-- Excel serial numbers, 18:53, 18:53:00, 6:53 PM.
function RLT:ParseDateTime(dateStr, timeStr)
    local s = Trim((dateStr or "") .. " " .. (timeStr or "")) or ""
    if s == "" then return nil end

    local serial = tonumber(dateStr or "")
    if serial and serial > 30000 and serial < 80000 then
        local t = date("!*t", math.floor((serial - 25569) * 86400 + 0.5))
        t.isdst = nil -- let the client decide summer time
        local ok, ts = pcall(time, t)
        if ok then return ts end
    end

    local y, m, d = s:match("(%d%d%d%d)[%-/%.](%d%d?)[%-/%.](%d%d?)")
    if not y then
        local a, b
        a, b, y = s:match("(%d%d?)[/%.%-](%d%d?)[/%.%-](%d%d%d%d)")
        if a then
            a, b = tonumber(a), tonumber(b)
            if a > 12 then d, m = a, b
            elseif b > 12 then m, d = a, b
            else d, m = a, b end
        end
    end
    if not y then return nil end

    local h, mi, se = s:match("(%d%d?):(%d%d):?(%d?%d?)")
    h, mi, se = tonumber(h) or 12, tonumber(mi) or 0, tonumber(se) or 0
    local low = s:lower()
    if low:find("%dpm") or low:find("%spm") then if h < 12 then h = h + 12 end
    elseif (low:find("%dam") or low:find("%sam")) and h == 12 then h = 0 end

    local ok, ts = pcall(time, { year = tonumber(y), month = tonumber(m), day = tonumber(d),
                                 hour = h, min = mi, sec = se })
    if ok then return ts end
end

---------------------------------------------------------------------------
-- Item links
---------------------------------------------------------------------------
function RLT:MakeItemLink(id, name)
    if id then
        local _, link, q = GetItemInfo(id)
        if link then return link, q end
        return string.format("|cffa335ee|Hitem:%d:0:0:0:0:0:0:0:0|h[%s]|h|r", id, name or ("item " .. id)), nil
    elseif name and name ~= "" then
        local _, link, q = GetItemInfo(name)
        if link then return link, q end
    end
end

-- Imported items may not be in the client cache yet; fill in the real link/quality later.
function RLT:RefreshItemInfo(e)
    if e.itemID and (not e.quality or e.linkGuessed) then
        local name, link, q = GetItemInfo(e.itemID)
        if link then
            e.itemLink, e.quality, e.itemName, e.linkGuessed = link, q, name, nil
        end
    end
end

---------------------------------------------------------------------------
-- Row -> entry
---------------------------------------------------------------------------
local function BuildEntry(r)
    local name = StripItemName(r.item)
    local id = tonumber(r.itemid or "") or (r.wowhead and tonumber(r.wowhead:match("item=(%d+)")))
    if Blank(name) and not id then return nil end

    local link, quality = RLT:MakeItemLink(id, name)
    if not id and link then id = tonumber(link:match("item:(%d+)")) end

    local winner = Trim(r.winner)
    if Blank(winner) or winner:lower() == "pending" or winner == "Pending..." then winner = nil end

    local ts = r.ts or RLT:ParseDateTime(r.date, r.time)

    local class = r.class and r.class:upper():gsub("%s", "")
    if class and not VALID_CLASS[class] then class = nil end

    local note = Trim(r.note)
    return {
        ts = ts or time(),
        itemName = (not Blank(name)) and name or ("item " .. tostring(id)),
        itemID = id,
        itemLink = link,
        linkGuessed = (link and quality == nil) or nil,
        quality = quality,
        boss = (not Blank(r.boss)) and Trim(r.boss) or RLT.UNKNOWN,
        winner = winner,
        pending = (winner == nil) or nil,
        class = class,
        zone = (not Blank(r.zone)) and Trim(r.zone) or "Imported",
        diff = Trim(r.diff) or "",
        spec = NormalizeSpec(r.spec),
        note = (not Blank(note)) and note or nil,
        imported = true,
        recorder = "Import",
    }
end

-- "Player (MS) - note" / "Player **(OS)** - _note_" / "Player MS note"
local function ParseWinnerPart(rest)
    rest = Trim((rest or ""):gsub("%*%*", ""):gsub("_", " ")) or ""
    local winner = rest:match("^(%S+)")
    local after = Trim(rest:sub((winner and #winner or 0) + 1)) or ""
    local spec
    local s1 = after:match("^%((%a%a)%)") or after:match("^(%a%a)%f[%A]")
    if s1 and NormalizeSpec(s1) then
        spec = NormalizeSpec(s1)
        after = Trim(after:gsub("^%(?%a%a%)?", "", 1)) or ""
    end
    local note = Trim(after:gsub("^%-%s*", "", 1))
    return winner, spec, (not Blank(note)) and note or nil
end

local function SplitRaid(raid)
    raid = Trim(raid or "") or ""
    local zone, diff = raid:match("^(.-)%s+(%d%d? ?[NHnh])$")
    if zone then return zone, diff:upper():gsub("(%d)([NH])", "%1 %2") end
    return raid, ""
end

---------------------------------------------------------------------------
-- Parsers
---------------------------------------------------------------------------
local HEADER_ALIASES = {
    ["date"] = "date", ["day"] = "date", ["jour"] = "date",
    ["time"] = "time", ["heure"] = "time",
    ["date / time"] = "datetime", ["date/time"] = "datetime", ["datetime"] = "datetime", ["date et heure"] = "datetime",
    ["raid"] = "zone", ["zone"] = "zone", ["instance"] = "zone",
    ["size"] = "diff", ["difficulty"] = "diff", ["diff"] = "diff", ["taille"] = "diff", ["difficulté"] = "diff",
    ["boss"] = "boss",
    ["item"] = "item", ["item name"] = "item", ["objet"] = "item", ["loot"] = "item", ["butin"] = "item",
    ["itemid"] = "itemid", ["item id"] = "itemid", ["id"] = "itemid",
    ["winner"] = "winner", ["player"] = "winner", ["name"] = "winner", ["joueur"] = "winner",
    ["gagnant"] = "winner", ["looter"] = "winner",
    ["class"] = "class", ["classe"] = "class",
    ["ms/os"] = "spec", ["ms / os"] = "spec", ["msos"] = "spec", ["spec"] = "spec", ["type"] = "spec",
    ["note"] = "note", ["notes"] = "note", ["comment"] = "note", ["commentaire"] = "note",
    ["wowhead"] = "wowhead", ["link"] = "wowhead", ["url"] = "wowhead", ["lien"] = "wowhead",
}
-- Column order of this addon's CSV export, used when there is no header row.
local DEFAULT_ORDER = { "date", "time", "zone", "diff", "boss", "item", "itemid", "winner", "class", "spec", "note", "wowhead" }

local function ParseDelimited(lines, delim)
    local out, failed = {}, 0
    local first = SplitDelimited(lines[1], delim)
    local map, known = {}, 0
    for i, cell in ipairs(first) do
        local key = HEADER_ALIASES[(cell or ""):lower()]
        if key then map[i] = key; known = known + 1 end
    end
    local startLine = 2
    if known < 2 then
        map = {}
        for i, k in ipairs(DEFAULT_ORDER) do map[i] = k end
        startLine = 1
    end
    for li = startLine, #lines do
        local cells = SplitDelimited(lines[li], delim)
        local r = {}
        for i, key in pairs(map) do r[key] = cells[i] end
        if r.datetime and not r.date then r.date = r.datetime end
        local e = BuildEntry(r)
        if e then out[#out + 1] = e else failed = failed + 1 end
    end
    return out, failed
end

-- "[2026-10-01 18:53] Icecrown Citadel 25 H | Lord Marrowgar | Item -> Player (MS) - note"
-- also "Boss | Item -> Player" and "Item -> Player"
local function ParseTextLine(line)
    local left, right = line:match("^(.-)%s*%->%s*(.*)$")
    if not left then return nil end
    local r = {}
    local stamp, rest = left:match("^%[([^%]]+)%]%s*(.*)$")
    if stamp and stamp:find("%d") and not stamp:find("|H") then
        r.date, left = stamp, rest
    end
    local parts = {}
    for p in (left .. "|"):gmatch("(.-)|") do parts[#parts + 1] = Trim(p) end
    -- item names never contain "|", so the last part is the item
    r.item = parts[#parts]
    if #parts >= 2 then r.boss = parts[#parts - 1] end
    if #parts >= 3 then r.zone, r.diff = SplitRaid(table.concat(parts, " ", 1, #parts - 2)) end
    r.winner, r.spec, r.note = ParseWinnerPart(right)
    return BuildEntry(r)
end

local function ParseText(lines)
    local out, failed = {}, 0
    for _, line in ipairs(lines) do
        local e = ParseTextLine(line)
        if e then out[#out + 1] = e else failed = failed + 1 end
    end
    return out, failed
end

-- **Icecrown Citadel 25 H - 2026-10-01** / __Boss__ / - [Item](<url>) -> Player **(MS)** - _note_
local function ParseDiscord(lines)
    local out, failed = {}, 0
    local zone, diff, day, boss
    for _, line in ipairs(lines) do
        local group = line:match("^%*%*(.-)%*%*$")
        local bossLine = line:match("^__(.-)__$")
        if group then
            local raid, d = group:match("^(.-)%s+%-%s+(%d%d%d%d%-%d%d%-%d%d)$")
            zone, diff = SplitRaid(raid or group)
            day = d
        elseif bossLine then
            boss = bossLine
        else
            local body = line:gsub("^[%-%*]%s*", "")
            local item, url, rest = body:match("^%[(.-)%]%(<?(.-)>?%)%s*%->%s*(.*)$")
            if not item then item, rest = body:match("^(.-)%s*%->%s*(.*)$") end
            if item then
                local r = { item = item, wowhead = url, boss = boss, zone = zone, diff = diff, date = day }
                r.winner, r.spec, r.note = ParseWinnerPart(rest)
                local e = BuildEntry(r)
                if e then out[#out + 1] = e else failed = failed + 1 end
            else
                failed = failed + 1
            end
        end
    end
    return out, failed
end

local function CountChar(s, ch)
    local _, n = s:gsub(ch, "")
    return n
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------
local function DedupeKey(e)
    return table.concat({ date("%Y-%m-%d", e.ts), (e.itemName or ""):lower(),
                          (e.winner or ""):lower(), (e.boss or ""):lower() }, "\001")
end

-- Returns added, duplicates, failed, formatName
function RLT:ImportText(text)
    text = (text or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
    local lines = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do
        line = Trim(line)
        if line ~= "" then lines[#lines + 1] = line end
    end
    if #lines == 0 then return 0, 0, 0, "empty" end

    local entries, failed, fmt
    local first = lines[1]
    local isDiscord = false
    for _, l in ipairs(lines) do
        if l:match("^%*%*.-%*%*$") or l:match("^__.-__$") then isDiscord = true; break end
    end

    if isDiscord then
        entries, failed = ParseDiscord(lines); fmt = "Discord"
    elseif first:find("\t", 1, true) then
        entries, failed = ParseDelimited(lines, "\t"); fmt = "Excel (tab)"
    elseif first:find("->", 1, true) then
        entries, failed = ParseText(lines); fmt = "Plain text"
    elseif CountChar(first, ";") >= 2 and CountChar(first, ";") >= CountChar(first, ",") then
        entries, failed = ParseDelimited(lines, ";"); fmt = "CSV (;)"
    elseif CountChar(first, ",") >= 2 then
        entries, failed = ParseDelimited(lines, ","); fmt = "CSV (,)"
    else
        entries, failed = ParseText(lines); fmt = "Plain text"
    end

    -- skip rows that already exist (same day + item + winner + boss)
    local existing = {}
    for _, e in ipairs(self.db.entries) do
        local k = DedupeKey(e)
        existing[k] = (existing[k] or 0) + 1
    end
    local added, dupes = 0, 0
    for _, e in ipairs(entries) do
        local k = DedupeKey(e)
        if (existing[k] or 0) > 0 then
            existing[k] = existing[k] - 1
            dupes = dupes + 1
        else
            e.id = self.db.nextId
            self.db.nextId = self.db.nextId + 1
            table.insert(self.db.entries, e)
            added = added + 1
        end
    end
    if added > 0 then
        table.sort(self.db.entries, function(a, b)
            if a.ts == b.ts then return a.id < b.id end
            return a.ts < b.ts
        end)
        self:NotifyChanged()
    end
    return added, dupes, failed, fmt
end
