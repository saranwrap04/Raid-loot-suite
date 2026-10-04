--[[
    Raid Loot Suite - Loot session
    Author: Saranwrap

    Soft reserves, MS/OS/SR rolls, loot council voting, the active loot
    queue (with status per item) and automatic winner detection/announces.

    Addon messages (prefix "RLS", fields separated by "~"):
      START~qid~mode~ms~os~sr~link      a roll or council vote starts (sent by the owner)
      COUNCIL~qid~name,name,...          council members for that item
      RESP~qid~MS|OS|SR|PASS             a raider answers (council mode)
      CAND~qid~name~resp~roll~class      owner shares a candidate (so the council sees it)
      VOTE~qid~candidate                 a council member votes ("" = remove vote)
      AWARD~qid~winner~spec              owner awarded the item
      STATUS~qid~STATUS                  owner changed the status (skip, disenchant, ...)
]]

local RLT = RaidLootSuite
local COMM = "RLS"

local time, tonumber, tostring, pairs, ipairs = time, tonumber, tostring, pairs, ipairs
local tinsert, tremove, strlower, format = table.insert, table.remove, string.lower, string.format

RLT.STATUS = {
    PENDING    = { label = "Waiting",       color = "|cffaaaaaa" },
    ROLLING    = { label = "Rolling",       color = "|cff4fc3f7" },
    COUNCIL    = { label = "Council vote",  color = "|cffc77dff" },
    TIE        = { label = "Tie - reroll",  color = "|cffffa040" },
    NOROLLS    = { label = "No rolls",      color = "|cffff7070" },
    AWARDED    = { label = "Awarded",       color = "|cff4cd964" },
    DELIVERED  = { label = "Delivered",     color = "|cff2ecc71" },
    DISENCHANT = { label = "Disenchant",    color = "|cffd2a679" },
    SKIPPED    = { label = "Skipped",       color = "|cff777777" },
}
local ACTIVE = { ROLLING = true, COUNCIL = true }
local FINISHED = { AWARDED = true, DELIVERED = true, DISENCHANT = true, SKIPPED = true }
RLT.FINISHED_STATUS = FINISHED

local RANK = { SR = 3, MS = 2, OS = 1, PASS = 0 }

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function Me() return UnitName("player") end
local function Lower(s) return s and strlower(s) or "" end
local function Trim(s) return s and strtrim(s) or "" end

-- "saranwrap" -> "Saranwrap" (keeps accented letters as typed)
function RLT:NormalizeName(name)
    name = Trim(name)
    if name == "" then return nil end
    name = name:gsub("%-.*$", "") -- drop "-Realm"
    return name:sub(1, 1):upper() .. name:sub(2):lower()
end

-- In a raid/party, or in test mode (fake raiders)
function RLT:IsGrouped()
    return self.testMode or GetNumRaidMembers() > 0 or GetNumPartyMembers() > 0
end

function RLT:GroupChannel()
    if self.testMode then return end -- nothing goes out in test mode
    if GetNumRaidMembers() > 0 then return "RAID" end
    if GetNumPartyMembers() > 0 then return "PARTY" end
end

function RLT:GroupMembers()
    local list = {}
    local n = GetNumRaidMembers()
    if n > 0 then
        for i = 1, n do
            local name = GetRaidRosterInfo(i)
            if name then list[name] = true end
        end
    else
        list[Me()] = true
        for i = 1, GetNumPartyMembers() do
            local name = UnitName("party" .. i)
            if name then list[name] = true end
        end
    end
    if self.testMode then
        list[Me()] = true
        for _, t in ipairs(self.TEST_PLAYERS) do list[t.name] = true end
    end
    return list
end

function RLT:InGroup(name)
    if not name then return false end
    local members = self:GroupMembers()
    if members[name] then return true end
    local ln = Lower(name)
    for m in pairs(members) do if Lower(m) == ln then return true end end
    return false
end

function RLT:IsMasterLooter()
    local method, partyMaster, raidMaster = GetLootMethod()
    if method ~= "master" then return false end
    if GetNumRaidMembers() > 0 and raidMaster then
        return UnitIsUnit("raid" .. raidMaster, "player")
    end
    return partyMaster == 0
end

local function CanRaidWarning()
    return GetNumRaidMembers() > 0 and (IsRaidLeader() or IsRaidOfficer())
end

-- kind: "start" or "result"
function RLT:Announce(text, kind)
    local s = self.db.settings
    local want
    if kind == "start" then want = s.announceStart
    elseif kind == "countdown" then want = s.announceCountdown or s.announceResult
    elseif kind == "drops" then want = s.announceDropsChannel or "RAID"
    else want = s.announceResult end
    local chan
    if self.testMode then
        local where = (want == "NONE") and "only you" or (want == "RAID_WARNING" and "raid warning" or "raid")
        self:Print("|cffffd100[Test - " .. where .. "]|r " .. text)
        return
    end
    if want ~= "NONE" then
        if GetNumRaidMembers() > 0 then
            chan = (want == "RAID_WARNING" and CanRaidWarning()) and "RAID_WARNING" or "RAID"
        elseif GetNumPartyMembers() > 0 then
            chan = "PARTY"
        end
    end
    if chan then
        SendChatMessage(text, chan)
    else
        self:Print(text)
    end
end

function RLT:Whisper(to, text)
    if self:IsTestPlayer(to) then
        self:Print("|cffffd100[Test - whisper to " .. to .. "]|r " .. text)
    else
        SendChatMessage("[RLS] " .. text, "WHISPER", nil, to)
    end
end

function RLT:SendComm(...)
    local chan = self:GroupChannel()
    if not chan then return end
    SendAddonMessage(COMM, table.concat({ ... }, "~"), chan)
end

-- Addon messages are limited to 255 characters: long name lists go out in parts
-- ("SR:a,b,c" then "SR+:d,e,f" which the receivers append).
function RLT:SendNameList(qid, kind, list)
    local chunk, first = {}, true
    local function flush()
        self:SendComm("COUNCIL", qid, kind .. (first and ":" or "+:") .. table.concat(chunk, ","))
        chunk, first = {}, false
    end
    local len = 0
    for _, n in ipairs(list) do
        if len + #n + 1 > 180 and #chunk > 0 then flush(); len = 0 end
        chunk[#chunk + 1] = n
        len = len + #n + 1
    end
    flush()
end

local function Split(msg)
    local t = {}
    for field in (msg .. "~"):gmatch("(.-)~") do t[#t + 1] = field end
    return t
end

---------------------------------------------------------------------------
-- Soft reserves
---------------------------------------------------------------------------
local function SRMatches(sr, itemID, itemName)
    if itemID and sr.itemID then return sr.itemID == itemID end
    return itemName and sr.itemName and Lower(sr.itemName) == Lower(itemName)
end

-- Turns an item link, ID or name into itemID, itemName, itemLink (as far as the client knows it).
function RLT:ResolveItem(text)
    text = Trim(text)
    if text == "" then return end
    local link = text:match("|c%x+|Hitem:.-|h.-|h|r")
    if link then
        local id, name = self:ParseLink(link)
        return id, name, link
    end
    local id = tonumber(text) or tonumber(text:match("item=(%d+)") or "")
    if id then
        local name, ilink = GetItemInfo(id)
        return id, name, ilink
    end
    text = text:gsub("^%[(.*)%]$", "%1")
    local name, ilink = GetItemInfo(text)
    if ilink then return tonumber(ilink:match("item:(%d+)")), name, ilink end
    return nil, text, nil
end

function RLT:CountSR(player)
    local n, lp = 0, Lower(player)
    for _, sr in ipairs(self.db.softres) do
        if Lower(sr.player) == lp then n = n + 1 end
    end
    return n
end

-- Returns the new entry, or nil + reason
-- "Death Knight" / "deathknight" -> "DEATHKNIGHT"
local function ClassFile(text)
    if not text or text == "" then return nil end
    local c = strupper((text:gsub("[%s_%-]", "")))
    if RAID_CLASS_COLORS and RAID_CLASS_COLORS[c] then return c end
end
RLT.ClassFile = ClassFile

function RLT:AddSR(player, itemID, itemName, ignoreLimit, class)
    player = self:NormalizeName(player)
    if not player then return nil, "no player name" end
    if not itemID and (not itemName or itemName == "") then return nil, "no item" end
    for _, sr in ipairs(self.db.softres) do
        if Lower(sr.player) == Lower(player) and SRMatches(sr, itemID, itemName) then
            return nil, player .. " already reserved that item"
        end
    end
    if not ignoreLimit and self:CountSR(player) >= self.db.settings.srPerPlayer then
        return nil, player .. " already has " .. self.db.settings.srPerPlayer .. " soft reserve(s)"
    end
    local sr = { player = player, itemID = itemID, itemName = itemName, ts = time(), class = ClassFile(class) }
    tinsert(self.db.softres, sr)
    self:SessionChanged()
    return sr
end

function RLT:UpdateSR(index, player, itemID, itemName)
    local sr = self.db.softres[index]
    if not sr then return nil, "entry not found" end
    player = self:NormalizeName(player)
    if not player then return nil, "no player name" end
    if not itemID and (not itemName or itemName == "") then return nil, "no item" end
    sr.player, sr.itemID, sr.itemName = player, itemID, itemName
    self:SessionChanged()
    return sr
end

function RLT:RemoveSR(index)
    if self.db.softres[index] then tremove(self.db.softres, index); self:SessionChanged() end
end

function RLT:ClearSR()
    wipe(self.db.softres)
    self:SessionChanged()
end

-- Names that soft reserved this item (only players in the group, unless solo)
function RLT:GetSRs(itemID, itemName, onlyGroup)
    local list, seen = {}, {}
    local inGroup = self:IsGrouped()
    for _, sr in ipairs(self.db.softres) do
        if SRMatches(sr, itemID, itemName) and not seen[Lower(sr.player)] then
            if not onlyGroup or not inGroup or self:InGroup(sr.player) then
                seen[Lower(sr.player)] = true
                list[#list + 1] = sr.player
            end
        end
    end
    table.sort(list)
    return list
end

-- softres.it CSV (Item,ItemId,From,Name,Class,Spec,Note,Plus,Date), any CSV/TSV with a
-- player + item column, or simple lines "Player: [item]" / "Player - Item" / "Player, 12345".
local SR_PLAYER = { name = true, player = true, character = true, char = true, joueur = true, nom = true }
local SR_ITEMID = { itemid = true, ["item id"] = true, id = true }
local SR_ITEM = { item = true, ["item name"] = true, itemname = true, objet = true, loot = true }
local SR_CLASS = { class = true, classe = true }

local function SplitCells(line, delim)
    local cells, i, len = {}, 1, #line
    while i <= len + 1 do
        if line:sub(i, i) == '"' then
            local buf, j = {}, i + 1
            while j <= len do
                local ch = line:sub(j, j)
                if ch == '"' then
                    if line:sub(j + 1, j + 1) == '"' then buf[#buf + 1] = '"'; j = j + 2 else j = j + 1; break end
                else buf[#buf + 1] = ch; j = j + 1 end
            end
            cells[#cells + 1] = table.concat(buf)
            local nd = line:find(delim, j, true)
            if not nd then break end
            i = nd + 1
        else
            local nd = line:find(delim, i, true)
            if nd then cells[#cells + 1] = line:sub(i, nd - 1); i = nd + 1
            else cells[#cells + 1] = line:sub(i); break end
        end
    end
    for k, v in ipairs(cells) do cells[k] = Trim(v) end
    return cells
end

-- Returns added, duplicates, failed
function RLT:ImportSR(text, replace)
    text = (text or ""):gsub("^\239\187\191", ""):gsub("\r\n", "\n"):gsub("\r", "\n")
    local lines = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do
        line = Trim(line)
        if line ~= "" then lines[#lines + 1] = line end
    end
    if replace then wipe(self.db.softres) end
    local added, dupes, failed = 0, 0, 0
    local function add(player, idText, nameText, class)
        local id = tonumber(idText or "")
        local name = Trim(nameText or "")
        if not id and name ~= "" then
            local rid, rname = self:ResolveItem(name)
            id, name = rid, rname or name
        elseif id and name == "" then
            name = GetItemInfo(id) or ("item " .. id)
        end
        local ok = self:AddSR(player, id, name, true, class)
        if ok then added = added + 1 else dupes = dupes + 1 end
    end
    if #lines == 0 then return 0, 0, 0 end

    local first = lines[1]
    local delim = first:find("\t", 1, true) and "\t" or (first:find(";", 1, true) and ";" or ",")
    local header = SplitCells(first, delim)
    local pc, ic, nc, cc
    for i, h in ipairs(header) do
        local k = Lower(h)
        if SR_CLASS[k] and not cc then cc = i end
        if SR_PLAYER[k] and not pc then pc = i end
        if SR_ITEMID[k] and not ic then ic = i end
        if SR_ITEM[k] and not nc then nc = i end
    end
    if pc and (ic or nc) then
        for li = 2, #lines do
            local c = SplitCells(lines[li], delim)
            if c[pc] and c[pc] ~= "" and ((ic and c[ic] and c[ic] ~= "") or (nc and c[nc] and c[nc] ~= "")) then
                add(c[pc], ic and c[ic], nc and c[nc], cc and c[cc])
            else
                failed = failed + 1
            end
        end
    else
        for _, line in ipairs(lines) do
            -- softres.it rows without the header line: Item,ItemId,From,Name,Class,Spec,Note,Plus,Date
            local c = SplitCells(line, delim)
            if #c >= 4 and tonumber(c[2]) and c[4] ~= "" and not tonumber(c[4]) then
                add(c[4], c[2], c[1], c[5])
            else
            local player, item = line:match("^([^:%-,%s][^:,]-)%s*[:,%-]%s*(.+)$")
            if not player then player, item = line:match("^(%S+)%s+(.+)$") end
            if player and item then
                local link = item:match("|c%x+|Hitem:.-|h.-|h|r")
                local id = tonumber(item) or (link and tonumber(link:match("item:(%d+)")))
                local name = link and link:match("|h%[(.-)%]|h") or (not tonumber(item) and item:gsub("^%[(.*)%]$", "%1")) or nil
                add(player, id, name)
            else
                failed = failed + 1
            end
            end
        end
    end
    self:SessionChanged()
    return added, dupes, failed
end

-- Posts the soft reserve list to raid chat, one line per item.
function RLT:AnnounceSRs()
    local byItem, order = {}, {}
    for _, sr in ipairs(self.db.softres) do
        local key = sr.itemID or Lower(sr.itemName)
        if not byItem[key] then
            byItem[key] = { sr = sr, names = {} }
            order[#order + 1] = key
        end
        tinsert(byItem[key].names, sr.player)
    end
    if #order == 0 then self:Print("No soft reserves to announce."); return end
    for _, key in ipairs(order) do
        local g = byItem[key]
        local item = g.sr.itemID and select(2, GetItemInfo(g.sr.itemID)) or ("[" .. (g.sr.itemName or "?") .. "]")
        self:Announce("SR " .. item .. ": " .. table.concat(g.names, ", "), "result")
    end
end

---------------------------------------------------------------------------
-- Queue
---------------------------------------------------------------------------
function RLT:SessionChanged()
    if self.OnSessionChanged then self:OnSessionChanged() end
end

function RLT:GetQueueItem(qid)
    for i, item in ipairs(self.db.queue) do
        if item.qid == qid then return item, i end
    end
end

function RLT:GetActiveItem()
    for _, item in ipairs(self.db.queue) do
        if item.owner == Me() and ACTIVE[item.status] then return item end
    end
end

function RLT:AddToQueue(link, boss)
    local id, name, quality = self:ParseLink(link)
    if not id then return end
    self.db.nextQid = (self.db.nextQid or 0) + 1
    local item = {
        qid = Me() .. "-" .. time() .. "-" .. self.db.nextQid,
        link = link, itemID = id, name = name, quality = quality,
        boss = boss or self:ResolveBoss() or self.UNKNOWN,
        status = "PENDING", owner = Me(), ts = time(),
        cands = {}, votes = {},
    }
    tinsert(self.db.queue, item)
    self:SessionChanged()
    return item
end

function RLT:RemoveFromQueue(qid)
    local item, i = self:GetQueueItem(qid)
    if not item then return end
    tremove(self.db.queue, i)
    self:SessionChanged()
end

function RLT:ClearFinished()
    for i = #self.db.queue, 1, -1 do
        local item = self.db.queue[i]
        if FINISHED[item.status] or item.remote then tremove(self.db.queue, i) end
    end
    self:SessionChanged()
end

local function SetCand(item, name, fields)
    item.cands = item.cands or {}
    local c = item.cands[name]
    if not c then
        c = { name = name, class = RLT:GetClassForName(name) }
        item.cands[name] = c
    end
    for k, v in pairs(fields) do c[k] = v end
    return c
end

local function ShareCand(item, c)
    RLT:SendComm("CAND", item.qid, c.name, c.resp or "", c.roll or "", c.class or "")
end

---------------------------------------------------------------------------
-- Starting a roll / council vote
---------------------------------------------------------------------------
local function SRText(item)
    if item.srs and #item.srs > 0 then return table.concat(item.srs, ", ") end
end

function RLT:StartRoll(qid, restrict, restrictResp)
    local item = self:GetQueueItem(qid)
    if not item or item.owner ~= Me() then return end
    local active = self:GetActiveItem()
    if active and active ~= item then self:Print("Finish the current item first: " .. active.link); return end
    local s = self.db.settings

    item.mode = "roll"
    item.status = "ROLLING"
    item.cands, item.votes = {}, {}
    item.restrict = restrict
    item.restrictResp = restrict and restrictResp or nil
    item.winner, item.winSpec, item.winRoll = nil, nil, nil
    item.srs = self:GetSRs(item.itemID, item.name, true)
    item.srMode = (not restrict) and #item.srs > 0
    item.duration = s.rollTime
    item.endsAt = time() + s.rollTime
    item.lastCount = nil

    if item.srMode and #item.srs == 1 then
        self:Award(qid, item.srs[1], "SR", nil, "only soft reserve")
        return
    end

    local srFlag = item.srMode and "1" or "0"
    self:SendComm("START", qid, "roll", s.msRoll, s.osRoll, srFlag, item.link)
    if restrict then
        self:SendNameList(qid, "R", restrict)
        self:Announce(format("Reroll %s: %s - /roll %d (%ds)", item.link, table.concat(restrict, ", "), s.msRoll, s.rollTime), "start")
    elseif item.srMode then
        self:SendNameList(qid, "SR", item.srs)
        self:Announce(format("SR roll %s: %s - /roll %d (%ds)", item.link, SRText(item), s.msRoll, s.rollTime), "start")
    else
        self:Announce(format("Roll %s - MS /roll %d, OS /roll %d (%ds)", item.link, s.msRoll, s.osRoll, s.rollTime), "start")
    end
    self:SessionChanged()
end

-- Roll timer in seconds (5-120). Used by the next roll.
RLT.ROLL_TIME_MIN, RLT.ROLL_TIME_MAX = 5, 120
function RLT:SetRollTime(v)
    v = tonumber(v)
    if not v then return end
    v = math.floor(math.max(self.ROLL_TIME_MIN, math.min(self.ROLL_TIME_MAX, v)) + 0.5)
    self.db.settings.rollTime = v
    if self.OnRollTimeChanged then self:OnRollTimeChanged() end
    return v
end

function RLT:StartCouncil(qid)
    local item = self:GetQueueItem(qid)
    if not item or item.owner ~= Me() then return end
    local active = self:GetActiveItem()
    if active and active ~= item then self:Print("Finish the current item first: " .. active.link); return end
    local s = self.db.settings

    item.mode = "council"
    item.status = "COUNCIL"
    item.cands, item.votes = {}, {}
    item.restrict = nil
    item.winner, item.winSpec, item.winRoll = nil, nil, nil
    item.srs = self:GetSRs(item.itemID, item.name, true)
    item.srMode = false
    item.endsAt = nil
    item.council = self:GetCouncil()

    self:SendComm("START", qid, "council", s.msRoll, s.osRoll, "0", item.link)
    self:SendNameList(qid, "C", item.council)
    local srs = SRText(item)
    self:Announce(format("Council %s - whisper me MS / OS%s (or /roll %d MS, /roll %d OS)",
        item.link, srs and (" | SR: " .. srs) or "", s.msRoll, s.osRoll), "start")
    -- soft reservers are listed as candidates right away
    for _, name in ipairs(item.srs) do ShareCand(item, SetCand(item, name, { resp = "SR" })) end
    self:SessionChanged()
end

-- Council member names from the settings (always includes you)
function RLT:GetCouncil()
    local list, seen = {}, {}
    local function add(n)
        n = self:NormalizeName(n)
        if n and not seen[Lower(n)] then seen[Lower(n)] = true; list[#list + 1] = n end
    end
    add(Me())
    for n in (self.db.settings.council or ""):gmatch("[^,%s]+") do add(n) end
    return list
end

-- Council members chosen by the loot master (saved), without you
function RLT:GetCouncilPicks()
    local list = self:GetCouncil()
    tremove(list, 1)
    return list
end

function RLT:IsCouncilPick(name)
    if not name then return false end
    if Lower(name) == Lower(Me()) then return true end
    for _, n in ipairs(self:GetCouncilPicks()) do if Lower(n) == Lower(name) then return true end end
    return false
end

function RLT:SetCouncilPicks(list)
    self.db.settings.council = table.concat(list, ", ")
    -- a council vote in progress uses the new list right away
    for _, item in ipairs(self.db.queue) do
        if item.owner == Me() and item.status == "COUNCIL" then
            item.council = self:GetCouncil()
            self:SendNameList(item.qid, "C", item.council)
        end
    end
    self:SessionChanged()
end

function RLT:SetCouncilMember(name, on)
    name = self:NormalizeName(name)
    if not name or Lower(name) == Lower(Me()) then return end
    local list = {}
    for _, n in ipairs(self:GetCouncilPicks()) do
        if Lower(n) ~= Lower(name) then list[#list + 1] = n end
    end
    if on then list[#list + 1] = name end
    self:SetCouncilPicks(list)
end

function RLT:IsCouncil(item, name)
    if not item or not name then return false end
    if Lower(item.owner) == Lower(name) then return true end
    for _, n in ipairs(item.council or {}) do if Lower(n) == Lower(name) then return true end end
    return false
end

---------------------------------------------------------------------------
-- Ending, winner detection, awarding
---------------------------------------------------------------------------
function RLT:SortedCands(item)
    local list = {}
    for _, c in pairs(item.cands or {}) do list[#list + 1] = c end
    local votes = self:CountVotes(item)
    table.sort(list, function(a, b)
        if item.mode == "council" then
            local va, vb = votes[a.name] or 0, votes[b.name] or 0
            if va ~= vb then return va > vb end
        end
        local ra, rb = RANK[a.resp or ""] or -1, RANK[b.resp or ""] or -1
        if ra ~= rb then return ra > rb end
        local xa, xb = a.roll or 0, b.roll or 0
        if xa ~= xb then return xa > xb end
        return a.name < b.name
    end)
    return list
end

function RLT:CountVotes(item)
    local count = {}
    for voter, cand in pairs(item.votes or {}) do
        if cand and cand ~= "" then count[cand] = (count[cand] or 0) + 1 end
    end
    return count
end

-- Ends the roll and works out the winner (highest SR > MS > OS roll).
function RLT:FinishRoll(qid)
    local item = self:GetQueueItem(qid)
    if not item or item.owner ~= Me() or item.status ~= "ROLLING" then return end
    local list = {}
    for _, c in pairs(item.cands) do
        if c.roll and c.resp ~= "PASS" then list[#list + 1] = c end
    end
    table.sort(list, function(a, b)
        local ra, rb = RANK[a.resp] or 0, RANK[b.resp] or 0
        if ra ~= rb then return ra > rb end
        return a.roll > b.roll
    end)
    if #list == 0 then
        item.endsAt = nil
        if self.db.settings.autoDisenchant and self:GetDisenchanter() then
            self:Announce("No rolls for " .. item.link .. ".", "result")
            self:SetItemStatus(qid, "DISENCHANT")
            return
        end
        item.status = "NOROLLS"
        self:Announce("No rolls for " .. item.link .. ".", "result")
        self:SendComm("STATUS", qid, "NOROLLS")
        self:SessionChanged()
        return
    end
    local top = list[1]
    local tied = { top.name }
    for i = 2, #list do
        if list[i].resp == top.resp and list[i].roll == top.roll then tied[#tied + 1] = list[i].name end
    end
    if #tied > 1 then
        item.status = "TIE"
        self:Announce(format("Tie on %s (%s %d): %s - reroll!", item.link, top.resp, top.roll, table.concat(tied, ", ")), "result")
        self:SendComm("STATUS", qid, "TIE")
        self:SessionChanged()
        self:StartRoll(qid, tied, top.resp)
        return
    end
    self:Award(qid, top.name, top.resp, top.roll)
end

-- Hands the item out with Master Loot if the loot window is open (returns true on success).
function RLT:GiveMasterLoot(item, winner)
    if item.test or not self:IsMasterLooter() or GetNumLootItems() == 0 then return false end
    for slot = 1, GetNumLootItems() do
        local link = GetLootSlotLink(slot)
        if link and tonumber(link:match("item:(%d+)")) == item.itemID then
            for i = 1, 40 do
                local cand = GetMasterLootCandidate(i)
                if cand and Lower(cand) == Lower(winner) then
                    GiveMasterLoot(slot, i)
                    return true
                end
            end
        end
    end
    return false
end

-- Records the item in the loot history (fills the drop seen in the loot window if there is one).
function RLT:RecordAward(item, winner, spec, note)
    local now = time()
    local entries = self.db.entries
    local function fill(e)
        e.pending, e.delivered = nil, nil
        e.winner, e.class, e.spec, e.awarded = winner, self:GetClassForName(winner), spec, true
        e.note, e.qid = note, item.qid
        if item.test then e.test = true; e.note = (note and (note .. " - ") or "") .. "test" end
        self:NotifyChanged()
        return e
    end
    -- the item was already awarded once (changed winner / disenchanted after all)
    for i = #entries, 1, -1 do
        if entries[i].qid == item.qid then return fill(entries[i]) end
    end
    for i = #entries, 1, -1 do
        local e = entries[i]
        if now - (e.ts or 0) > 3600 then break end
        if e.pending and e.itemID == item.itemID then return fill(e) end
    end
    local e = self:AddEntry({
        itemLink = item.link, itemID = item.itemID, itemName = item.name, quality = item.quality,
        boss = item.boss, winner = winner, class = self:GetClassForName(winner),
        spec = spec, note = note, awarded = true,
    })
    if e then
        e.qid = item.qid
        if item.test then e.test = true; e.note = (note and (note .. " - ") or "") .. "test" end
    end
    return e
end

function RLT:Award(qid, winner, spec, roll, reason)
    local item = self:GetQueueItem(qid)
    if not item or item.owner ~= Me() or not winner then return end
    item.status = "AWARDED"
    item.winner, item.winSpec, item.winRoll = winner, spec, roll
    item.endsAt = nil
    item.awardedAt = time()
    local how = spec and spec ~= "" and spec or nil
    if roll then how = (how and (how .. " ") or "") .. roll end
    if reason then how = (how and (how .. ", ") or "") .. reason end
    if item.mode == "council" and not reason then how = (how and (how .. ", ") or "") .. "council" end
    self:Announce(format("%s goes to %s%s", item.link, winner, how and (" (" .. how .. ")") or ""), "result")
    self:SendComm("AWARD", qid, winner, spec or "")
    local note = item.mode == "council" and "Council" or (roll and ("Roll " .. roll)) or reason
    if spec == "MS" or spec == "OS" or spec == "SR" then
        self:RecordAward(item, winner, spec, note)
    else
        self:RecordAward(item, winner, nil, note)
    end
    if self.db.settings.autoAward and self:GiveMasterLoot(item, winner) then
        self:Print(item.link .. " given to " .. winner .. " with Master Loot.")
    end
    self:SessionChanged()
end

-- The designated disenchanter (Settings), or nil
function RLT:GetDisenchanter()
    local n = self:NormalizeName(self.db.settings.disenchanter or "")
    return n
end

function RLT:SetItemStatus(qid, status)
    local item = self:GetQueueItem(qid)
    if not item or item.owner ~= Me() then return end
    item.status = status
    item.endsAt = nil
    if status == "DISENCHANT" then
        -- goes to the designated disenchanter (Settings), saved as "DE" in the history
        local de = self:GetDisenchanter()
        item.winner, item.winSpec, item.winRoll = de or "Disenchanted", "DE", nil
        self:Announce(item.link .. " will be disenchanted" .. (de and (" by " .. de) or "") .. ".", "result")
        self:RecordAward(item, de or "Disenchanted", "DE", "Disenchant")
        if de and self.db.settings.autoAward and self:GiveMasterLoot(item, de) then
            self:Print(item.link .. " given to " .. de .. " (disenchanter) with Master Loot.")
        end
    elseif status == "SKIPPED" then
        self:Print(item.link .. " skipped.")
    elseif status == "PENDING" then
        item.cands, item.votes = {}, {}
    end
    self:SendComm("STATUS", qid, status)
    self:SessionChanged()
end

function RLT:Vote(qid, candidate)
    local item = self:GetQueueItem(qid)
    if not item or item.status ~= "COUNCIL" then return end
    if not self:IsCouncil(item, Me()) then self:Print("You are not on the loot council for this item."); return end
    item.votes = item.votes or {}
    if item.votes[Me()] == candidate then candidate = "" end -- click again to take your vote back
    item.votes[Me()] = candidate
    self:SendComm("VOTE", qid, candidate)
    self:SessionChanged()
end

-- Player answers a council call from the popup
function RLT:Respond(qid, resp)
    local item = self:GetQueueItem(qid)
    if not item then return end
    if item.owner == Me() then
        local c = SetCand(item, Me(), { resp = resp })
        ShareCand(item, c)
        self:SessionChanged()
    else
        self:SendComm("RESP", qid, resp)
    end
end

-- Called by Core when "<player> receives loot: [item]" is seen
function RLT:OnItemReceived(who, itemID)
    for _, item in ipairs(self.db.queue) do
        if item.status == "DISENCHANT" and item.itemID == itemID and item.winner and Lower(item.winner) == Lower(who) and not item.deliveredAt then
            item.deliveredAt = time()
            self:SessionChanged()
            return
        end
        if item.status == "AWARDED" and item.itemID == itemID and Lower(item.winner) == Lower(who) then
            item.status = "DELIVERED"
            item.deliveredAt = time()
            if item.owner == Me() then self:SendComm("STATUS", item.qid, "DELIVERED") end
            self:SessionChanged()
            return
        end
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local rollPattern, rollOrder

-- "<player> rolls 87 (1-100)"
function RLT:CHAT_MSG_SYSTEM(msg)
    if not rollPattern then return end
    local caps = { msg:match(rollPattern) }
    if not caps[1] then return end
    local args = {}
    for k, v in ipairs(caps) do args[rollOrder[k]] = v end
    local who, roll, low, high = args[1], tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
    if not who or not roll or low ~= 1 then return end

    local item = self:GetActiveItem()
    if not item then return end
    local s = self.db.settings
    local resp
    if high == s.msRoll then resp = "MS" elseif high == s.osRoll then resp = "OS" else return end
    if self:IsGrouped() and not self:InGroup(who) then return end

    item.cands = item.cands or {}
    local existing = item.cands[who]
    if item.mode == "roll" then
        if existing and existing.roll then return end -- only the first roll counts
        if item.restrict then
            local ok = false
            for _, n in ipairs(item.restrict) do if Lower(n) == Lower(who) then ok = true end end
            if not ok then return end
        elseif item.srMode then
            local ok = false
            for _, n in ipairs(item.srs) do if Lower(n) == Lower(who) then ok = true end end
            if not ok or resp ~= "MS" then return end
            resp = "SR"
        end
        -- a reroll keeps the spec the tie was on, whichever range is rolled
        if item.restrict and item.restrictResp then resp = item.restrictResp end
    else
        if existing and existing.roll then return end
        if existing and existing.resp and existing.resp ~= "PASS" then resp = existing.resp end
    end
    local c = SetCand(item, who, { resp = resp, roll = roll })
    ShareCand(item, c)
    self:SessionChanged()
end

local RESPONSES = {
    ms = "MS", main = "MS", need = "MS", mainspec = "MS", ["+1"] = "MS",
    os = "OS", off = "OS", greed = "OS", offspec = "OS", ["+2"] = "OS",
    pass = "PASS",
}

function RLT:CHAT_MSG_WHISPER(msg, sender)
    if not self.db then return end
    local s = self.db.settings
    local text = Trim(msg)
    local first, rest = text:match("^(%S+)%s*(.*)$")
    first = Lower(first)

    if first == "sr" and s.whisperSR then
        rest = Trim(rest)
        local reply
        if rest == "" then
            local mine = {}
            for _, sr in ipairs(self.db.softres) do
                if Lower(sr.player) == Lower(sender) then mine[#mine + 1] = sr.itemName or ("item " .. tostring(sr.itemID)) end
            end
            reply = #mine > 0 and ("Your soft reserve(s): " .. table.concat(mine, ", ")) or "You have no soft reserve. Whisper: sr [item]"
        elseif Lower(rest) == "clear" or Lower(rest) == "remove" then
            for i = #self.db.softres, 1, -1 do
                if Lower(self.db.softres[i].player) == Lower(sender) then tremove(self.db.softres, i) end
            end
            self:SessionChanged()
            reply = "Your soft reserves were removed."
        else
            local id, name = self:ResolveItem(rest)
            local ok, err = self:AddSR(sender, id, name)
            reply = ok and ("Soft reserve saved: " .. (name or rest)) or ("Not saved: " .. tostring(err))
        end
        self:Whisper(sender, reply)
        return
    end

    local resp = RESPONSES[first]
    if resp and s.whisperResponses then
        local item = self:GetActiveItem()
        if item and item.mode == "council" then
            local c = SetCand(item, sender, { resp = resp })
            ShareCand(item, c)
            self:Whisper(sender, "Got it: " .. resp .. " for " .. item.link)
            self:SessionChanged()
        end
    end
end

function RLT:CHAT_MSG_ADDON(prefix, msg, channel, sender)
    if prefix ~= COMM or not msg or sender == Me() then return end
    local f = Split(msg)
    local cmd, qid = f[1], f[2]
    if not qid then return end
    local item = self:GetQueueItem(qid)

    if cmd == "START" then
        local link = f[7]
        if not link or not link:find("|Hitem:") then return end
        if not item then
            local id, name, quality = self:ParseLink(link)
            item = { qid = qid, link = link, itemID = id, name = name, quality = quality, owner = sender,
                     remote = true, ts = time(), boss = "", cands = {}, votes = {} }
            tinsert(self.db.queue, item)
        end
        item.mode = f[3]
        item.status = (f[3] == "council") and "COUNCIL" or "ROLLING"
        item.msRoll, item.osRoll = tonumber(f[4]) or 100, tonumber(f[5]) or 99
        item.srMode = f[6] == "1"
        item.cands, item.votes, item.winner = {}, {}, nil
        item.srs, item.restrict, item.council = {}, nil, nil
        self:SessionChanged()
        if self.ShowLootPopup then self:ShowLootPopup(item) end
    elseif not item then
        return
    elseif cmd == "COUNCIL" then
        local kind, more, names = (f[3] or ""):match("^(%a+)(%+?):(.*)$")
        local key = (kind == "C" and "council") or (kind == "SR" and "srs") or (kind == "R" and "restrict")
        if not key then return end
        local list = (more == "+" and item[key]) or {}
        for n in (names or ""):gmatch("[^,]+") do list[#list + 1] = n end
        item[key] = list
        self:SessionChanged()
        if self.ShowLootPopup then self:ShowLootPopup(item) end
    elseif cmd == "RESP" then
        if item.owner ~= Me() or item.status ~= "COUNCIL" then return end
        local resp = f[3]
        if not RANK[resp] then return end
        local c = SetCand(item, sender, { resp = resp })
        ShareCand(item, c)
        self:SessionChanged()
    elseif cmd == "CAND" then
        if Lower(item.owner) ~= Lower(sender) then return end
        local c = SetCand(item, f[3], { resp = f[4] ~= "" and f[4] or nil, roll = tonumber(f[5] or "") })
        if f[6] and f[6] ~= "" then c.class = f[6] end
        self:SessionChanged()
    elseif cmd == "VOTE" then
        if not self:IsCouncil(item, sender) then return end
        item.votes = item.votes or {}
        item.votes[sender] = f[3] or ""
        self:SessionChanged()
    elseif cmd == "AWARD" then
        if Lower(item.owner) ~= Lower(sender) then return end
        item.status = "AWARDED"
        item.winner, item.winSpec = f[3], f[4] ~= "" and f[4] or nil
        self:SessionChanged()
        if self.HideLootPopup then self:HideLootPopup(item) end
    elseif cmd == "STATUS" then
        if Lower(item.owner) ~= Lower(sender) or not RLT.STATUS[f[3] or ""] then return end
        item.status = f[3]
        self:SessionChanged()
        if not ACTIVE[item.status] and self.HideLootPopup then self:HideLootPopup(item) end
    end
end

-- Adds the loot window's items to the queue when you are the master looter.
local queuedSources = {}
-- "Loot from <Boss>: [a] [b] ..." in raid chat, split so each line stays under the chat limit
function RLT:AnnounceDrops(boss, links)
    if #links == 0 then return end
    local head = "Loot from " .. (boss or "?") .. ": "
    local line = head
    for _, link in ipairs(links) do
        if #line + #link + 1 > 250 and line ~= head then
            self:Announce(line, "drops")
            line = head
        end
        line = line .. link .. " "
    end
    self:Announce(line, "drops")
end

function RLT:OnLootOpenedSession()
    local s = self.db.settings
    if not (s.autoQueue or s.announceDrops) or not self:IsMasterLooter() then return end
    local key, boss
    if UnitExists("target") and UnitIsDead("target") and not UnitIsPlayer("target") then
        key = UnitGUID("target")
        boss = self.IsBossUnit("target") and UnitName("target") or self.TRASH
    else
        boss = self:ResolveBoss() or self.UNKNOWN
        key = "chest:" .. boss .. ":" .. (GetRealZoneText() or "")
    end
    if queuedSources[key] then return end
    queuedSources[key] = true
    local added, links = 0, {}
    for slot = 1, GetNumLootItems() do
        if LootSlotIsItem(slot) then
            local link = GetLootSlotLink(slot)
            local _, _, _, quality = GetLootSlotInfo(slot)
            local id = link and tonumber(link:match("item:(%d+)"))
            if id and not self.IGNORED_ITEMS[id] and (quality or 0) >= s.minQuality then
                links[#links + 1] = link
                if s.autoQueue then
                    self:AddToQueue(link, boss)
                    added = added + 1
                end
            end
        end
    end
    if s.announceDrops and boss ~= self.TRASH then self:AnnounceDrops(boss, links) end
    if added > 0 then
        self:Print(added .. " item(s) added to the loot queue.")
        if self.ShowSession then self:ShowSession() end
    end
end

---------------------------------------------------------------------------
-- Timer (roll countdown)
---------------------------------------------------------------------------
local ticker = CreateFrame("Frame")
local acc = 0
ticker:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc < 0.25 then return end
    acc = 0
    if not RLT.db then return end
    local item = RLT:GetActiveItem()
    if not item or item.status ~= "ROLLING" or not item.endsAt then return end
    local left = math.ceil(item.endsAt - time())
    -- countdown in chat: "[item] ends in 5", then 4, 3, 2, 1
    if RLT.db.settings.countdown and left <= 5 and left > 0 and (item.duration or 20) > 5
        and (not item.lastCount or left < item.lastCount) then
        local first = not item.lastCount
        item.lastCount = left
        RLT:Announce(first and ("Roll for " .. item.link .. " ends in " .. left) or tostring(left), "countdown")
    end
    if left <= 0 then RLT:FinishRoll(item.qid) end
    if RLT.OnSessionTick then RLT:OnSessionTick() end
end)

function RLT:InitSession()
    local db = self.db
    db.queue = db.queue or {}
    db.softres = db.softres or {}
    db.nextQid = db.nextQid or 0
    -- rolls/votes in progress can't survive a reload
    for i = #db.queue, 1, -1 do
        local item = db.queue[i]
        if item.remote or item.test then
            tremove(db.queue, i)
        elseif ACTIVE[item.status] or item.status == "TIE" then
            item.status = "PENDING"
            item.endsAt = nil
        end
    end
    -- repair soft reserves imported from softres.it rows without a header (v2.0 beta):
    -- player = item name, itemName = "itemID,Boss,Player,Class,..."
    for _, sr in ipairs(db.softres) do
        if not sr.itemID and sr.itemName then
            local id, _, player, class = sr.itemName:match("^(%d+),([^,]*),([^,]+),([^,]*)")
            if id then
                sr.itemID, sr.itemName = tonumber(id), sr.player
                sr.player = self:NormalizeName(player) or player
                sr.class = self.ClassFile(class)
            end
        end
    end
    -- leftovers from test mode (council picks, test reserves and fake raiders' whispers)
    if self.GetTestClass then
        local keep = {}
        for _, n in ipairs(self:GetCouncilPicks()) do
            if not self:GetTestClass(n) then keep[#keep + 1] = n end
        end
        db.settings.council = table.concat(keep, ", ")
    end
    for i = #db.softres, 1, -1 do
        local sr = db.softres[i]
        if sr.test or (self.GetTestClass and self:GetTestClass(sr.player)) then tremove(db.softres, i) end
    end
    if type(RANDOM_ROLL_RESULT) == "string" then
        rollPattern, rollOrder = self.BuildPattern(RANDOM_ROLL_RESULT)
    end
end
