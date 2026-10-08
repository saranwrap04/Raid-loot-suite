--[[
    Raid Loot Suite - Loot history sync
    Author: Saranwrap

    "Sync" (History tab) asks the raid for the loot it recorded, so drops you
    missed (disconnected, too far away, reloaded) are filled in.

    Addon messages (prefix "RLSH", fields separated by "~"):
      REQ~since                 to RAID/PARTY: who has loot recorded since <since>?
      HAVE~count~now            whisper back: I have <count> entries (+ my clock)
      SEND~since                whisper: please send me your entries since <since>
      E~itemID~q~name~winner~class~boss~zone~diff~ts~spec~note
      END~count                 done
    Only two players (the ones with the most entries) are asked to send, to
    keep the traffic low. Messages are sent a few per second.
]]

local RLT = RaidLootSuite
local PREFIX = "RLSH"
local SYNC_DAYS = 7          -- how far back a sync looks
local MATCH_WINDOW = 900     -- same item + same winner within 15 min = same drop
local SEND_RATE = 0.12       -- seconds between two messages

local tinsert, tremove, time, tonumber, tostring = table.insert, table.remove, time, tonumber, tostring

local function Me() return UnitName("player") end
local function Clean(s) return (tostring(s or ""):gsub("~", "-"):gsub("|", "")) end

---------------------------------------------------------------------------
-- Throttled sender
---------------------------------------------------------------------------
local outbox = {}
local sender = CreateFrame("Frame")
local wait = 0
sender:SetScript("OnUpdate", function(_, elapsed)
    if #outbox == 0 then return end
    wait = wait - elapsed
    if wait > 0 then return end
    wait = SEND_RATE
    local m = tremove(outbox, 1)
    SendAddonMessage(PREFIX, m.msg, m.chan, m.target)
end)

local function Send(msg, chan, target)
    tinsert(outbox, { msg = msg:sub(1, 250 - #PREFIX), chan = chan, target = target })
end

---------------------------------------------------------------------------
-- Requesting
---------------------------------------------------------------------------
local sync -- the sync in progress: { since, offers = {name = {count, offset}}, asked = {}, added, filled, done }

local timer = CreateFrame("Frame")
timer:Hide()
local timerLeft, timerFn = 0, nil
timer:SetScript("OnUpdate", function(self, elapsed)
    timerLeft = timerLeft - elapsed
    if timerLeft <= 0 then
        self:Hide()
        local fn = timerFn
        timerFn = nil
        if fn then fn() end
    end
end)
local function After(sec, fn) timerLeft, timerFn = sec, fn; timer:Show() end

function RLT:SyncStatus(text)
    self.syncText = text
    if self.OnDataChanged then self:OnDataChanged() end
end

function RLT:StartSync(quiet)
    local chan = (GetNumRaidMembers() > 0 and "RAID") or (GetNumPartyMembers() > 0 and "PARTY")
    if not chan then
        if not quiet then self:Print("Sync: you need to be in a raid or party.") end
        return
    end
    if sync and not sync.done then
        if not quiet then self:Print("Sync: already running.") end
        return
    end
    sync = { since = time() - SYNC_DAYS * 86400, offers = {}, asked = {}, added = 0, filled = 0, quiet = quiet }
    Send("REQ~" .. sync.since, chan)
    if not quiet then self:Print("Sync: asking the raid for its loot history...") end
    self:SyncStatus("Sync: asking the raid...")
    After(3, function() RLT:PickSyncSources() end)
end

-- After 3 seconds: ask the 2 players with the most entries to send them
function RLT:PickSyncSources()
    if not sync then return end
    local list = {}
    for name, o in pairs(sync.offers) do if o.count > 0 then list[#list + 1] = name end end
    table.sort(list, function(a, b) return sync.offers[a].count > sync.offers[b].count end)
    if #list == 0 then
        sync.done = true
        if not sync.quiet then self:Print("Sync: nobody else in the group has Raid Loot Suite entries to share.") end
        self:SyncStatus(nil)
        return
    end
    for i = 1, math.min(2, #list) do
        sync.asked[list[i]] = true
        Send("SEND~" .. sync.since, "WHISPER", list[i])
    end
    self:SyncStatus("Sync: receiving from " .. table.concat({ list[1], list[2] }, ", ") .. "...")
    -- safety net: finish even if an END never arrives
    After(90, function() RLT:FinishSync() end)
end

function RLT:FinishSync()
    if not sync or sync.done then return end
    sync.done = true
    local msg = "Sync done: " .. sync.added .. " new item(s)" ..
        (sync.filled > 0 and (", " .. sync.filled .. " winner(s) filled in") or "") .. "."
    if not sync.quiet or sync.added + sync.filled > 0 then self:Print(msg) end
    self:SyncStatus(nil)
end

---------------------------------------------------------------------------
-- Merging one received entry
---------------------------------------------------------------------------
local function QualityColor(q)
    local hex = { [2] = "ff1eff00", [3] = "ff0070dd", [4] = "ffa335ee", [5] = "ffff8000" }
    return "|c" .. (hex[q] or "ffa335ee")
end

function RLT:MergeSyncedEntry(e, from)
    local lw = strlower(e.winner)
    for _, x in ipairs(self.db.entries) do
        if x.itemID == e.itemID and math.abs((x.ts or 0) - e.ts) <= MATCH_WINDOW then
            if x.winner and strlower(x.winner) == lw then
                -- already have it: take the spec / note if ours has none
                if not x.spec and e.spec then x.spec = e.spec end
                if not x.note and e.note then x.note = e.note end
                if not x.method and e.method then x.method = e.method end
                return "dupe"
            end
            if not x.winner then
                -- a drop we saw in the loot window but never saw who got it
                x.winner, x.class, x.pending = e.winner, e.class, nil
                x.spec = x.spec or e.spec
                x.note = x.note or e.note
                x.method = x.method or e.method
                x.synced = from
                return "filled"
            end
        end
    end
    local _, link = GetItemInfo(e.itemID)
    self:AddEntryQuiet({
        itemLink = link or (QualityColor(e.quality) .. "|Hitem:" .. e.itemID .. ":0:0:0:0:0:0:0:80|h[" .. e.itemName .. "]|h|r"),
        itemID = e.itemID, itemName = e.itemName, quality = e.quality,
        winner = e.winner, class = e.class, boss = e.boss or RLT.UNKNOWN, zone = e.zone or "?", diff = e.diff or "",
        ts = e.ts, spec = e.spec, note = e.note, method = e.method, recorder = from, synced = from,
    })
    return "added"
end

-- AddEntry without the chat line (a sync can bring many items)
function RLT:AddEntryQuiet(e)
    local saved = self.db.settings.announce
    self.db.settings.announce = false
    local r = self:AddEntry(e)
    self.db.settings.announce = saved
    -- keep the list sorted by time
    table.sort(self.db.entries, function(a, b) return (a.ts or 0) < (b.ts or 0) end)
    return r
end

---------------------------------------------------------------------------
-- Messages
---------------------------------------------------------------------------
local function Split(msg)
    local t = {}
    for field in (msg .. "~"):gmatch("(.-)~") do t[#t + 1] = field end
    return t
end

local function EntriesSince(since)
    local list = {}
    for _, e in ipairs(RLT.db.entries) do
        -- e.noSync: unticked in the History (Sync column): never shared
        if e.winner and e.itemID and (e.ts or 0) >= since and not e.test and not e.noSync then list[#list + 1] = e end
    end
    return list
end

function RLT:OnSyncMessage(msg, channel, sender)
    if not msg or sender == Me() then return end
    local f = Split(msg)
    local cmd = f[1]
    if cmd == "REQ" then
        local since = tonumber(f[2]) or 0
        local n = #EntriesSince(since)
        if n > 0 then Send("HAVE~" .. n .. "~" .. time(), "WHISPER", sender) end
    elseif cmd == "HAVE" then
        if not sync or sync.done then return end
        -- their clock vs ours, so their times line up with ours
        sync.offers[sender] = { count = tonumber(f[2]) or 0, offset = time() - (tonumber(f[3]) or time()) }
    elseif cmd == "SEND" then
        local list = EntriesSince(tonumber(f[2]) or 0)
        for _, e in ipairs(list) do
            Send(table.concat({ "E", e.itemID, e.quality or 4, Clean(e.itemName), Clean(e.winner), Clean(e.class),
                Clean(e.boss), Clean(e.zone), Clean(e.diff), e.ts or 0, Clean(e.spec), Clean(e.note):sub(1, 60),
                Clean(e.method) }, "~"),
                "WHISPER", sender)
        end
        Send("END~" .. #list, "WHISPER", sender)
    elseif cmd == "E" then
        if not sync or sync.done or not sync.asked[sender] then return end
        local offer = sync.offers[sender] or { offset = 0 }
        local function opt(v) return (v and v ~= "") and v or nil end
        local e = {
            itemID = tonumber(f[2]), quality = tonumber(f[3]) or 4, itemName = f[4], winner = f[5],
            class = opt(f[6]), boss = opt(f[7]), zone = opt(f[8]), diff = opt(f[9]),
            ts = (tonumber(f[10]) or 0) + (offer.offset or 0), spec = opt(f[11]), note = opt(f[12]),
            method = opt(f[13]),
        }
        if not e.itemID or not e.winner or e.winner == "" then return end
        local r = self:MergeSyncedEntry(e, sender)
        if r == "added" then sync.added = sync.added + 1 elseif r == "filled" then sync.filled = sync.filled + 1 end
        self:NotifyChanged()
    elseif cmd == "END" then
        if not sync or sync.done or not sync.asked[sender] then return end
        sync.asked[sender] = "done"
        for _, v in pairs(sync.asked) do if v ~= "done" then return end end
        self:FinishSync()
    end
end

-- Route our prefix to the sync code, everything else to the loot session
local origAddon = RLT.CHAT_MSG_ADDON
function RLT:CHAT_MSG_ADDON(prefix, msg, channel, sender)
    if prefix == PREFIX then
        if self.db then self:OnSyncMessage(msg, channel, sender) end
        return
    end
    if origAddon then return origAddon(self, prefix, msg, channel, sender) end
end

-- Auto sync once when you log in / reload inside a raid group
function RLT:PLAYER_ENTERING_WORLD()
    if not self.db or not self.db.settings.autoSync or self.autoSynced then return end
    if GetNumRaidMembers() == 0 then return end
    self.autoSynced = true
    After(10, function() RLT:StartSync(true) end)
end
