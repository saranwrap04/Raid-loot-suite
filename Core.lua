--[[
    Raid Loot Suite - Core
    Author: Saranwrap
    Client: World of Warcraft 3.3.5a (Interface 30300)

    Records raid boss loot: item, boss, winner, date/time, raid and size.
    Data lives in the SavedVariables file RaidLootSuite.lua, so it
    survives logouts, reloads and game restarts.
]]

local ADDON_NAME = ... -- the addon's folder name (RaidLootSuite, or Raid-loot-suite-main from GitHub)
RaidLootSuite = RaidLootSuite or {}
local RLT = RaidLootSuite
RLT.FOLDER = ADDON_NAME or "RaidLootSuite"
RLT.MEDIA = "Interface\\AddOns\\" .. RLT.FOLDER .. "\\textures\\"

RLT.NAME    = "Raid Loot Suite"
RLT.VERSION = "2.5.0"
RLT.AUTHOR  = "Saranwrap"
RLT.PREFIX  = "|cfffc7a2bRaid Loot Suite|r"
RLT.TRASH   = "Trash"
RLT.UNKNOWN = "Unknown"

local time, date, tonumber, tostring, type = time, date, tonumber, tostring, type
local pairs, ipairs, tinsert, tremove = pairs, ipairs, table.insert, table.remove

local DEFAULTS = {
    minQuality = 4,     -- 2 uncommon, 3 rare, 4 epic, 5 legendary
    onlyInRaid = true,  -- only record inside raid instances
    trackTrash = true,  -- also record drops that cannot be tied to a boss
    announce   = true,  -- chat line each time something is recorded
    bossWindow = 900,   -- seconds after a boss kill during which loot is credited to it
    minimap    = { hide = false, angle = 215 },
    opacity    = 0.95,  -- window background opacity (0.2 - 1)
    window     = { w = 820, h = 530 },
    -- loot session (rolls / soft reserves / council)
    rollTime       = 10,     -- seconds a roll stays open
    msRoll         = 100,    -- /roll 100 = main spec (fixed)
    osRoll         = 99,     -- /roll 99 = off spec (fixed)
    disenchanter   = "",     -- player who gets disenchant items
    autoDisenchant = true,   -- nobody rolled -> give it to the disenchanter
    srPerPlayer    = 1,      -- soft reserves allowed per player
    whisperSR      = true,   -- players can whisper "sr [item]"
    whisperResponses = true, -- players can whisper "ms" / "os" / "pass"
    autoQueue      = true,   -- add items from the loot window to the queue when you are master looter
    autoAward      = true,   -- hand the item out with Master Loot when it's awarded
    countdown      = true,   -- 5-4-3-2-1 countdown in chat at the end of a roll
    announceStart  = "RAID_WARNING", -- RAID_WARNING | RAID | NONE
    announceResult = "RAID",         -- RAID_WARNING | RAID | NONE
    announceCountdown = "RAID",      -- 5-4-3-2-1 countdown: RAID_WARNING | RAID | NONE
    announceDrops  = true,   -- master looter: post the boss loot in raid chat when the corpse is opened
    council        = "",     -- council member names, comma separated
    srOnlyRaid     = false,
    autoSync       = true,   -- sync the loot history with the raid after login / reload  -- Soft Reserves window: only show players in my raid
}

-- Items never worth recording (currencies / disenchant results).
RLT.IGNORED_ITEMS = {
    [40752] = true, -- Emblem of Heroism
    [40753] = true, -- Emblem of Valor
    [45624] = true, -- Emblem of Conquest
    [47241] = true, -- Emblem of Triumph
    [49426] = true, -- Emblem of Frost
    [34057] = true, -- Abyss Crystal
    [43102] = true, -- Frozen Orb
}

local QUALITY_BY_COLOR = {
    ["9d9d9d"] = 0, ["ffffff"] = 1, ["1eff00"] = 2, ["0070dd"] = 3,
    ["a335ee"] = 4, ["ff8000"] = 5, ["e6cc80"] = 6, ["e5cc80"] = 7,
}

---------------------------------------------------------------------------
-- Utilities
---------------------------------------------------------------------------
function RLT:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(self.PREFIX .. ": " .. tostring(msg))
end

local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

-- Returns itemID, name, quality from an item link (works even if the item is not cached).
function RLT:ParseLink(link)
    if not link then return end
    local id = tonumber(link:match("item:(%d+)"))
    local name = link:match("|h%[(.-)%]|h")
    local color = link:match("|c%x%x(%x%x%x%x%x%x)")
    local quality = color and QUALITY_BY_COLOR[color:lower()]
    local gName, _, gQuality = GetItemInfo(link)
    return id, gName or name, gQuality or quality
end

function RLT:GetItemIcon(itemID)
    if not itemID then return "Interface\\Icons\\INV_Misc_QuestionMark" end
    local icon = GetItemIcon and GetItemIcon(itemID)
    if not icon then icon = select(10, GetItemInfo(itemID)) end
    return icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- Class file name ("PALADIN", ...) for a group member, used for colouring.
function RLT:GetClassForName(name)
    if not name then return end
    if name == UnitName("player") then return select(2, UnitClass("player")) end
    if self.testMode and self.GetTestClass and self:GetTestClass(name) then return self:GetTestClass(name) end
    local n = GetNumRaidMembers()
    if n > 0 then
        for i = 1, n do
            local rName, _, _, _, _, classFile = GetRaidRosterInfo(i)
            if rName == name then return classFile end
        end
    else
        for i = 1, GetNumPartyMembers() do
            local unit = "party" .. i
            if UnitName(unit) == name then return select(2, UnitClass(unit)) end
        end
    end
    -- class given by a soft reserve import (players not in the group)
    local ln = strlower(name)
    for _, sr in ipairs(self.db and self.db.softres or {}) do
        if sr.class and strlower(sr.player) == ln then return sr.class end
    end
end

-- Current instance name and size/difficulty label ("25 H", "10 N").
function RLT:GetRaidContext()
    local _, instType = IsInInstance()
    local zone = GetRealZoneText() or GetZoneText() or "?"
    local diff = ""
    if instType == "raid" then
        local name, _, diffIdx, _, maxPlayers, dynDiff, isDynamic = GetInstanceInfo()
        if name and name ~= "" then zone = name end
        diffIdx = diffIdx or 1
        local size = (maxPlayers and maxPlayers > 0) and maxPlayers
                     or ((diffIdx == 1 or diffIdx == 3) and 10 or 25)
        local heroic = (diffIdx == 3 or diffIdx == 4) or (isDynamic and dynDiff == 1)
        diff = size .. (heroic and " H" or " N")
    end
    return zone, diff
end

function RLT:ShouldTrack()
    if not self.db then return false end
    if self.db.settings.onlyInRaid then
        local _, instType = IsInInstance()
        return instType == "raid"
    end
    return true
end

---------------------------------------------------------------------------
-- Boss detection (locale independent: uses unit classification, not names)
---------------------------------------------------------------------------
local bossCache = {}  -- GUID -> boss name
local lastKill        -- { name, t }
local lastEngaged     -- { name, t }

local function IsBossUnit(unit)
    if not UnitExists(unit) or UnitIsPlayer(unit) or UnitPlayerControlled(unit) then return false end
    return UnitClassification(unit) == "worldboss" or UnitLevel(unit) == -1
end
RLT.IsBossUnit = IsBossUnit

local function ScanUnit(unit)
    if IsBossUnit(unit) then
        local guid, name = UnitGUID(unit), UnitName(unit)
        if guid and name then
            bossCache[guid] = name
            if UnitAffectingCombat(unit) then
                lastEngaged = { name = name, t = time() }
            end
        end
    end
end

local SCAN_UNITS = { "target", "focus", "mouseover", "boss1", "boss2", "boss3", "boss4" }
local function CombatScan()
    for _, u in ipairs(SCAN_UNITS) do ScanUnit(u) end
    local n = GetNumRaidMembers()
    if n > 0 then
        for i = 1, n do ScanUnit("raid" .. i .. "target") end
    else
        for i = 1, GetNumPartyMembers() do ScanUnit("party" .. i .. "target") end
    end
end

-- Best guess of which boss the current loot belongs to.
function RLT:ResolveBoss()
    local now, win = time(), self.db.settings.bossWindow
    if lastKill and now - lastKill.t <= win then return lastKill.name end
    -- Encounters where the boss does not die (Gunship, Valithria, Ulduar keepers...)
    if lastEngaged and now - lastEngaged.t <= win then return lastEngaged.name end
    return nil
end

---------------------------------------------------------------------------
-- Loot message parsing (built from the client's own localized strings)
---------------------------------------------------------------------------
local MAGIC = "[%(%)%.%+%-%*%?%[%]%^%$]"

-- Turns a printf-style global string into a Lua pattern.
-- Returns the pattern and the argument index of each capture (handles %1$s).
function RLT.BuildPattern(fmt)
    local out, order, n, i, len = {}, {}, 0, 1, #fmt
    while i <= len do
        local c = fmt:sub(i, i)
        if c == "%" then
            local idx, typ, nexti = fmt:match("^%%(%d)%$([sd])()", i)
            if idx then
                n = n + 1; order[n] = tonumber(idx)
                out[#out + 1] = (typ == "d") and "(%d+)" or "(.+)"
                i = nexti
            else
                local t = fmt:sub(i + 1, i + 1)
                if t == "s" or t == "d" then
                    n = n + 1; order[n] = n
                    out[#out + 1] = (t == "d") and "(%d+)" or "(.+)"
                    i = i + 2
                elseif t == "%" then
                    out[#out + 1] = "%%"; i = i + 2
                else
                    out[#out + 1] = "%%"; i = i + 1
                end
            end
        else
            out[#out + 1] = c:find(MAGIC) and ("%" .. c) or c
            i = i + 1
        end
    end
    return "^" .. table.concat(out) .. "$", order
end

local LOOT_PATTERNS = {}
local function AddLootPattern(fmt, isSelf)
    if type(fmt) ~= "string" then return end
    local p, o = RLT.BuildPattern(fmt)
    tinsert(LOOT_PATTERNS, { pattern = p, order = o, isSelf = isSelf })
end

function RLT:BuildLootPatterns()
    wipe(LOOT_PATTERNS)
    -- "multiple" variants first so "x2" is not swallowed by the single pattern
    AddLootPattern(LOOT_ITEM_SELF_MULTIPLE, true)  -- You receive loot: %sx%d.
    AddLootPattern(LOOT_ITEM_MULTIPLE, false)      -- %s receives loot: %sx%d.
    AddLootPattern(LOOT_ITEM_SELF, true)           -- You receive loot: %s.
    AddLootPattern(LOOT_ITEM, false)               -- %s receives loot: %s.
end

-- Returns winner, itemLink (or nil if the message is not a loot message).
function RLT:ParseLootMessage(msg)
    for _, lp in ipairs(LOOT_PATTERNS) do
        local caps = { msg:match(lp.pattern) }
        if caps[1] then
            local args = {}
            for k, v in ipairs(caps) do args[lp.order[k]] = v end
            local who, itemStr
            if lp.isSelf then
                who, itemStr = UnitName("player"), args[1]
            else
                who, itemStr = args[1], args[2]
            end
            local link = itemStr and itemStr:match("|c%x+|Hitem:.-|h.-|h|r")
            if link then return who, link end
        end
    end
end

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------
function RLT:NotifyChanged()
    if self.OnDataChanged then self:OnDataChanged() end
end

function RLT:AddEntry(e)
    local db = self.db
    e.id = db.nextId
    db.nextId = db.nextId + 1
    e.ts = e.ts or time()
    if not e.zone then e.zone, e.diff = self:GetRaidContext() end
    e.recorder = e.recorder or UnitName("player")
    tinsert(db.entries, e)
    if db.settings.announce and e.winner then
        self:Print(string.format("%s -> %s |cff888888(%s)|r", e.itemLink, e.winner, e.boss or "?"))
    end
    self:NotifyChanged()
    return e
end

function RLT:GetEntryById(id)
    for i, e in ipairs(self.db.entries) do
        if e.id == id then return e, i end
    end
end

function RLT:DeleteEntry(id)
    local _, i = self:GetEntryById(id)
    if i then tremove(self.db.entries, i); self:NotifyChanged() end
end

function RLT:ClearAll()
    wipe(self.db.entries)
    self:NotifyChanged()
    self:Print("All loot history deleted.")
end

---------------------------------------------------------------------------
-- Recording
---------------------------------------------------------------------------
local openedSources = {} -- loot sources already read this session
local trashSeen = {}     -- itemID -> count of trash drops seen in a loot window (not recorded)

-- The looter (master looter or whoever opens the corpse/chest) sees every item that dropped.
function RLT:LOOT_OPENED()
    if self.OnLootOpenedSession then self:OnLootOpenedSession() end
    if not self:ShouldTrack() then return end
    local s = self.db.settings
    local boss, key, isTrash

    if UnitExists("target") and UnitIsDead("target") and not UnitIsPlayer("target") then
        key = UnitGUID("target")
        if bossCache[key] or IsBossUnit("target") then
            boss = UnitName("target")
        else
            isTrash = true
        end
    else
        boss = self:ResolveBoss() -- chest encounters
        if boss then
            local zone, diff = self:GetRaidContext()
            key = "chest:" .. boss .. ":" .. zone .. ":" .. diff
        end
    end

    if not key then return end
    if openedSources[key] then return end
    if isTrash then boss = self.TRASH end

    local found = false
    for slot = 1, GetNumLootItems() do
        if LootSlotIsItem(slot) then
            local link = GetLootSlotLink(slot)
            local _, _, qty, quality = GetLootSlotInfo(slot)
            local id, name, q = self:ParseLink(link)
            quality = quality or q
            if id and isTrash and not s.trackTrash then
                -- remember it so the matching chat message is not credited to the last boss
                if (quality or 0) >= s.minQuality then trashSeen[id] = (trashSeen[id] or 0) + 1 end
                found = true
            elseif id and not self.IGNORED_ITEMS[id] and (quality or 0) >= s.minQuality then
                self:AddEntry({
                    itemLink = link, itemID = id, itemName = name, quality = quality,
                    boss = boss, pending = true,
                })
                found = true
            end
        end
    end
    if found then openedSources[key] = true end
end

-- Everybody in the group sees "<player> receives loot: [item]."
function RLT:CHAT_MSG_LOOT(msg)
    if not self:ShouldTrack() then return end
    local who, link = self:ParseLootMessage(msg)
    if not who then return end
    local id, name, quality = self:ParseLink(link)
    if not id or self.IGNORED_ITEMS[id] or (quality or 0) < self.db.settings.minQuality then return end

    local now = time()
    local entries = self.db.entries
    if self.OnItemReceived then self:OnItemReceived(who, id) end
    -- An item awarded through the loot session is now actually in the winner's bags
    for i = #entries, 1, -1 do
        local e = entries[i]
        if now - (e.ts or 0) > 3600 then break end
        if e.awarded and not e.delivered and e.itemID == id and (e.winner == who or e.winner == "Disenchanted") then
            e.delivered = now
            self:NotifyChanged()
            return
        end
    end
    -- Assign the winner to a drop already seen in the loot window
    for i = #entries, 1, -1 do
        local e = entries[i]
        if now - (e.ts or 0) > 3600 then break end
        if e.pending and e.itemID == id then
            e.pending = nil
            e.winner = who
            e.class = self:GetClassForName(who)
            e.awardedTs = now
            if self.db.settings.announce then
                self:Print(string.format("%s -> %s |cff888888(%s)|r", e.itemLink, who, e.boss or "?"))
            end
            self:NotifyChanged()
            return
        end
    end

    if trashSeen[id] and trashSeen[id] > 0 then
        trashSeen[id] = trashSeen[id] - 1
        return
    end

    local boss = self:ResolveBoss()
    if not boss then
        if not self.db.settings.trackTrash then return end
        boss = self.TRASH
    end
    self:AddEntry({
        itemLink = link, itemID = id, itemName = name, quality = quality,
        boss = boss, winner = who, class = self:GetClassForName(who),
    })
end

function RLT:COMBAT_LOG_EVENT_UNFILTERED(_, subEvent, _, _, _, dstGUID, dstName)
    if subEvent == "UNIT_DIED" and dstGUID and bossCache[dstGUID] then
        lastKill = { name = bossCache[dstGUID] or dstName, t = time() }
        lastEngaged = nil
    end
end

-- group changed: refresh "in raid" colours, council picker, SR lists
function RLT:RAID_ROSTER_UPDATE()
    if self.OnSessionChanged then self:OnSessionChanged() end
    -- joined a raid after logging in: one automatic history sync
    if self.PLAYER_ENTERING_WORLD and not self.autoSynced then self:PLAYER_ENTERING_WORLD() end
end
RLT.PARTY_MEMBERS_CHANGED = RLT.RAID_ROSTER_UPDATE

function RLT:PLAYER_TARGET_CHANGED() ScanUnit("target") end
function RLT:UPDATE_MOUSEOVER_UNIT() ScanUnit("mouseover") end
function RLT:UNIT_TARGET(unit) if unit then ScanUnit(unit .. "target") end end

local scanFrame = CreateFrame("Frame")
local scanElapsed = 0
local function OnScanUpdate(_, elapsed)
    scanElapsed = scanElapsed + elapsed
    if scanElapsed >= 1 then
        scanElapsed = 0
        CombatScan()
    end
end
function RLT:PLAYER_REGEN_DISABLED() CombatScan(); scanFrame:SetScript("OnUpdate", OnScanUpdate) end
function RLT:PLAYER_REGEN_ENABLED() scanFrame:SetScript("OnUpdate", nil) end

---------------------------------------------------------------------------
-- Export
---------------------------------------------------------------------------
local function CSV(s)
    s = tostring(s or "")
    if s:find('[,"\n]') then s = '"' .. (s:gsub('"', '""')) .. '"' end
    return s
end

local function WowheadURL(id) return id and ("https://www.wowhead.com/wotlk/item=" .. tostring(id)) or "" end

-- entries: array (any order); fmt: "csv" | "text" | "discord"
function RLT:BuildExport(entries, fmt)
    local list = {}
    for _, e in ipairs(entries) do list[#list + 1] = e end
    table.sort(list, function(a, b)
        if a.ts == b.ts then return a.id < b.id end
        return a.ts < b.ts
    end)

    local lines = {}
    -- "MS, LC": the tag + how it was awarded (LC = loot council, SR = soft reserve)
    local function Tag(e)
        local m = e.method and not (e.method == "SR" and e.spec == "SR") and e.method or nil
        if e.spec and m then return e.spec .. ", " .. m end
        return e.spec or m
    end
    if fmt == "csv" then
        lines[1] = "Date,Time,Raid,Size,Boss,Item,ItemID,Winner,Class,MS/OS,Note,Wowhead,Awarded by"
        for _, e in ipairs(list) do
            lines[#lines + 1] = table.concat({
                CSV(date("%Y-%m-%d", e.ts)), CSV(date("%H:%M:%S", e.ts)), CSV(e.zone), CSV(e.diff),
                CSV(e.boss), CSV(e.itemName), CSV(e.itemID or ""), CSV(e.winner or "Pending"),
                CSV(e.class or ""), CSV(e.spec or ""), CSV(e.note or ""), CSV(WowheadURL(e.itemID)),
                CSV(e.method == "LC" and "Loot council" or (e.method == "SR" and "Soft reserve") or ""),
            }, ",")
        end
    elseif fmt == "discord" then
        local lastGroup, lastBoss
        for _, e in ipairs(list) do
            local group = (e.zone or "?") .. " " .. (e.diff or "") .. " - " .. date("%Y-%m-%d", e.ts)
            if group ~= lastGroup then
                if lastGroup then lines[#lines + 1] = "" end
                lines[#lines + 1] = "**" .. group .. "**"
                lastGroup, lastBoss = group, nil
            end
            if e.boss ~= lastBoss then
                lines[#lines + 1] = "__" .. (e.boss or "?") .. "__"
                lastBoss = e.boss
            end
            local itemTxt = e.itemID and string.format("[%s](<%s>)", e.itemName or "?", WowheadURL(e.itemID)) or (e.itemName or "?")
            lines[#lines + 1] = string.format("- %s -> %s%s%s", itemTxt,
                e.winner or "Pending", Tag(e) and (" **(" .. Tag(e) .. ")**") or "", e.note and (" - _" .. e.note .. "_") or "")
        end
    else -- text
        for _, e in ipairs(list) do
            lines[#lines + 1] = string.format("[%s] %s %s | %s | %s -> %s%s%s",
                date("%Y-%m-%d %H:%M", e.ts), e.zone or "?", e.diff or "", e.boss or "?",
                e.itemName or "?", e.winner or "Pending",
                Tag(e) and (" (" .. Tag(e) .. ")") or "", e.note and (" - " .. e.note) or "")
        end
    end
    return table.concat(lines, "\n"), #list
end

---------------------------------------------------------------------------
-- Init / events
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    local handler = RLT[event]
    if handler then handler(RLT, ...) end
end)
eventFrame:RegisterEvent("ADDON_LOADED")

function RLT:ADDON_LOADED(name)
    if name ~= ADDON_NAME then return end
    eventFrame:UnregisterEvent("ADDON_LOADED")

    -- Older saved data (RaidLootTrackerDB): take over the history if it was carried over
    if (type(RaidLootSuiteDB) ~= "table" or not RaidLootSuiteDB.entries) and type(RaidLootTrackerDB) == "table" then
        RaidLootSuiteDB = RaidLootTrackerDB
        self.migrated = true
    end
    RaidLootTrackerDB = nil
    RaidLootSuiteDB = RaidLootSuiteDB or {}
    local db = RaidLootSuiteDB
    db.entries = db.entries or {}
    db.settings = db.settings or {}
    db.nextId = db.nextId or 1
    CopyDefaults(DEFAULTS, db.settings)
    -- v1.2: "Record trash drops" is now on by default (also for existing installs)
    if (db.settingsVersion or 1) < 2 then
        db.settings.trackTrash = true
        db.settingsVersion = 2
    end
    -- v2.2: rolls are always /roll 100 (MS) and /roll 99 (OS)
    db.settings.msRoll, db.settings.osRoll = 100, 99
    -- v2.0: roll timer default is now 10 seconds
    if db.settingsVersion < 3 then
        if db.settings.rollTime == 20 then db.settings.rollTime = 10 end
        db.settingsVersion = 3
    end
    -- keep ids unique even if the file was edited by hand
    for _, e in ipairs(db.entries) do
        if not e.id or e.id >= db.nextId then
            e.id = e.id or db.nextId
            db.nextId = e.id + 1
        end
    end
    self.db = db

    self:BuildLootPatterns()

    for _, ev in ipairs({ "CHAT_MSG_LOOT", "LOOT_OPENED", "COMBAT_LOG_EVENT_UNFILTERED",
                          "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "UNIT_TARGET",
                          "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_LOGOUT",
                          "CHAT_MSG_SYSTEM", "CHAT_MSG_WHISPER", "CHAT_MSG_ADDON",
                          "RAID_ROSTER_UPDATE", "PARTY_MEMBERS_CHANGED", "PLAYER_ENTERING_WORLD" }) do
        eventFrame:RegisterEvent(ev)
    end

    if self.InitSession then self:InitSession() end
    if self.InitUI then self:InitUI() end
    if self.InitSessionUI then self:InitSessionUI() end
    if self.InitLootUI then self:InitLootUI() end
    if self.InitMain then
        self:InitMain()
    else
        self:Print("|cffff7070Some files did not load (Main.lua). Reinstall the addon with all the files from the same download.|r")
    end
    if self.migrated then self:Print("Your previous loot history was carried over (" .. #db.entries .. " items).") end
end

-- A CSV copy is written into the SavedVariables file on logout,
-- so the data can be pulled out of the game without logging in.
function RLT:PLAYER_LOGOUT()
    if not self.db then return end
    local text = self:BuildExport(self.db.entries, "csv")
    local lines = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
    self.db.csvExport = lines
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
SLASH_RAIDLOOTSUITE1 = "/rls"
SLASH_RAIDLOOTSUITE2 = "/raidloot"
SlashCmdList["RAIDLOOTSUITE"] = function(msg)
    msg = strtrim(msg or "")
    local cmd = (msg:match("^(%S+)") or ""):lower()

    if cmd == "" or cmd == "show" then
        if RLT.ToggleMain then RLT:ToggleMain() end
    elseif cmd == "session" or cmd == "loot" then
        RLT:ToggleSession()
    elseif cmd == "history" then
        RLT:ToggleUI()
    elseif cmd == "export" then
        RLT:ShowExport()
    elseif cmd == "import" then
        RLT:ShowImport()
    elseif cmd == "options" or cmd == "config" then
        RLT:ShowOptions()
    elseif cmd == "minimap" then
        RLT.db.settings.minimap.hide = not RLT.db.settings.minimap.hide
        RLT:UpdateMinimapButton()
    elseif cmd == "clear" then
        StaticPopup_Show("RLT_CONFIRM_CLEAR")
    elseif cmd == "add" then
        -- /rls add [Item Link] PlayerName [Boss name]
        local link, rest = msg:match("^%S+%s+(|c%x+|Hitem:.-|h.-|h|r)%s*(.*)$")
        if not link then
            RLT:Print("Usage: /rls add [shift-click item] PlayerName [MS|OS] [Boss name]")
            return
        end
        local who, boss = rest:match("^(%S+)%s*(.*)$")
        local spec
        if boss then
            local first, after = boss:match("^(%S+)%s*(.*)$")
            if first and (first:upper() == "MS" or first:upper() == "OS") then spec, boss = first:upper(), after end
        end
        local id, name, quality = RLT:ParseLink(link)
        RLT:AddEntry({
            itemLink = link, itemID = id, itemName = name, quality = quality,
            winner = who or UnitName("player"), class = RLT:GetClassForName(who),
            boss = (boss and boss ~= "") and boss or RLT:ResolveBoss() or RLT.UNKNOWN,
            manual = true, spec = spec,
        })
    elseif cmd == "tables" or cmd == "drops" then
        if RLT.ShowLootTables then RLT:ShowLootTables() end
    elseif cmd == "council" then
        RLT:ToggleCouncil()
    elseif cmd == "sr" then
        RLT:ToggleSR()
    elseif cmd == "timer" or cmd == "time" then
        local v = RLT:SetRollTime(msg:match("^%S+%s+(%d+)"))
        if v then
            RLT:Print("Roll timer: " .. v .. " seconds.")
        else
            RLT:Print("Usage: /rls timer <seconds>  (" .. RLT.ROLL_TIME_MIN .. "-" .. RLT.ROLL_TIME_MAX .. ", now " .. RLT.db.settings.rollTime .. ")")
        end
    elseif cmd == "queue" then
        local link = msg:match("(|c%x+|Hitem:.-|h.-|h|r)")
        if link then
            RLT:AddToQueue(link)
            RLT:ShowSession()
        else
            RLT:Print("Usage: /rls queue [shift-click item]")
        end
    elseif cmd == "test" then
        RLT:ToggleTest()
    elseif cmd == "sync" then
        RLT:StartSync()
    elseif cmd == "testentry" then
        RLT:AddEntry({
            itemLink = "|cffff8000|Hitem:49623:0:0:0:0:0:0:0:80|h[Shadowmourne]|h|r",
            itemID = 49623, itemName = "Shadowmourne", quality = 5,
            boss = "Test Boss", winner = UnitName("player"),
            class = select(2, UnitClass("player")), zone = "Test", diff = "25 H",
        })
    else
        RLT:Print("Commands:")
        RLT:Print("  /rls - open / close the main window")
        RLT:Print("  /rls session - Loot Session tab (queue, rolls, council)")
        RLT:Print("  /rls history - loot history")
        RLT:Print("  /rls sr - soft reserves")
        RLT:Print("  /rls council - choose the loot council members")
        RLT:Print("  /rls tables - loot tables of every raid (10 / 25 / heroic, drop chances)")
        RLT:Print("  /rls queue [item] - add an item to the loot queue")
        RLT:Print("  /rls timer <seconds> - roll timer (5-120)")
        RLT:Print("  /rls sync - get the loot history recorded by the raid")
        RLT:Print("  /rls export - export window")
        RLT:Print("  /rls import - import history from Excel / CSV / text")
        RLT:Print("  /rls options - settings")
        RLT:Print("  /rls add [item] Player [MS|OS] [Boss] - add an entry by hand")
        RLT:Print("  /rls minimap - show / hide the minimap button")
        RLT:Print("  /rls test - test mode on / off (fake raiders, soft reserves and rolls)")
        RLT:Print("  /rls testentry - add a sample entry to the history")
        RLT:Print("  /rls clear - delete all history")
    end
end
