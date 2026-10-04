--[[
    Raid Loot Suite - Test mode
    Author: Saranwrap

    Try the loot session alone: fake raiders, soft reserves and rolls.
    Nothing is sent to chat or to other players, Master Loot is not used
    and nothing is written to the loot history. Leaving test mode removes
    every test item and test soft reserve.
]]

local RLT = RaidLootSuite
local format, random, floor = string.format, math.random, math.floor
local tinsert, tremove = table.insert, table.remove

RLT.TEST_PLAYERS = {
    { name = "Tanktest",  class = "WARRIOR" },
    { name = "Healtest",  class = "PRIEST" },
    { name = "Magetest",  class = "MAGE" },
    { name = "Roguetest", class = "ROGUE" },
    { name = "Hunttest",  class = "HUNTER" },
    { name = "Dktest",    class = "DEATHKNIGHT" },
}
local TEST_CLASS = {}
for _, t in ipairs(RLT.TEST_PLAYERS) do TEST_CLASS[strlower(t.name)] = t.class end

local function Me() return UnitName("player") end

function RLT:IsTestPlayer(name)
    return self.testMode and name and TEST_CLASS[strlower(name)] ~= nil
end

function RLT:GetTestClass(name)
    return name and TEST_CLASS[strlower(name)]
end

local function TestPrint(text) RLT:Print("|cffffd100[Test]|r " .. text) end

---------------------------------------------------------------------------
-- Small scheduler (fake raiders answer after a few seconds)
---------------------------------------------------------------------------
local timers = {}
local function After(delay, fn) timers[#timers + 1] = { at = GetTime() + delay, fn = fn } end

local timerFrame = CreateFrame("Frame")
timerFrame:SetScript("OnUpdate", function()
    if #timers == 0 then return end
    local now = GetTime()
    for i = #timers, 1, -1 do
        local t = timers[i]
        if now >= t.at then
            tremove(timers, i)
            t.fn()
        end
    end
end)

---------------------------------------------------------------------------
-- Test items: taken from your own gear / bags so they always show properly
---------------------------------------------------------------------------
local function CollectItems(want)
    local list, seen = {}, {}
    local function add(link)
        local id = link and tonumber(link:match("item:(%d+)"))
        if id and not seen[id] and #list < want then
            seen[id] = true
            list[#list + 1] = link
        end
    end
    for _, slot in ipairs({ 16, 1, 5, 7, 3, 10, 6, 8, 15, 2, 11, 13, 9, 17, 18, 12, 14 }) do
        add(GetInventoryItemLink("player", slot))
    end
    for bag = 0, 4 do
        for slot = 1, (GetContainerNumSlots(bag) or 0) do
            add(GetContainerItemLink(bag, slot))
        end
    end
    return list
end

---------------------------------------------------------------------------
-- Start / stop
---------------------------------------------------------------------------
function RLT:StartTest()
    if self.testMode then return end
    local items = CollectItems(4)
    if #items == 0 then
        self:Print("Test mode needs at least one item equipped or in your bags.")
        return
    end
    self.testMode = true
    self.testWhisperStep = 0

    local function queue(link, label)
        local item = self:AddToQueue(link, "Test Boss")
        item.test = true
        item.testLabel = label
        return item
    end
    local function sr(player, link)
        local id, name = self:ParseLink(link)
        local e = self:AddSR(player, id, name, true)
        if e then e.test = true end
    end
    local me = Me()

    -- 1: soft reserved by you + 2 fake raiders -> SR roll
    local first = queue(items[1], "SR roll: you, Tanktest and Magetest reserved it")
    sr(me, items[1]); sr("Tanktest", items[1]); sr("Magetest", items[1])
    -- 2: soft reserved by one raider -> automatic win
    if items[2] then queue(items[2], "One soft reserve (Healtest): Roll gives it to them right away"); sr("Healtest", items[2]) end
    -- 3: nobody reserved it -> MS / OS roll
    if items[3] then queue(items[3], "No soft reserve: MS / OS roll, use the popup to roll") end
    -- 4: loot council
    if items[4] then queue(items[4], "Try Council: fake raiders answer, the fake raiders you put on the council vote") end

    -- two fake raiders on the loot council (removed again when the test stops)
    self:SetCouncilMember("Tanktest", true)
    self:SetCouncilMember("Healtest", true)

    -- what the raid sees when you loot the boss
    if self.db.settings.announceDrops then
        local links = {}
        for _, item in ipairs(self.db.queue) do if item.test then links[#links + 1] = item.link end end
        self:AnnounceDrops("Test Boss", links)
    end

    if self.SUI then self.SUI.selected = first.qid end
    self:SessionChanged()
    if self.ShowSession then self:ShowSession() end
    TestPrint("Test mode ON. Fake raiders: Tanktest, Healtest, Magetest, Roguetest, Hunttest, Dktest.")
    TestPrint("Nothing is sent to chat and Master Loot is not used. Awards go into the loot history as \"Test Boss\".")
    TestPrint("Select an item and press Roll or Council. In Soft Reserves, \"Fake whisper\" tests the whisper commands.")
end

function RLT:StopTest()
    if not self.testMode then return end
    wipe(timers)
    for i = #self.db.queue, 1, -1 do
        if self.db.queue[i].test then tremove(self.db.queue, i) end
    end
    for i = #self.db.softres, 1, -1 do
        local sr = self.db.softres[i]
        if sr.test or TEST_CLASS[strlower(sr.player or "")] then tremove(self.db.softres, i) end
    end
    local keep = {}
    for _, n in ipairs(self:GetCouncilPicks()) do
        if not TEST_CLASS[strlower(n)] then keep[#keep + 1] = n end
    end
    self.db.settings.council = table.concat(keep, ", ")
    self.testMode = false
    if self.HideLootPopup then self:HideLootPopup() end
    self:SessionChanged()
    TestPrint("Test mode OFF. Test items, test soft reserves and fake council members were removed.")
    local n = 0
    for _, e in ipairs(self.db.entries) do if e.test then n = n + 1 end end
    if n > 0 then StaticPopup_Show("RLS_TEST_HISTORY", n) end
end

function RLT:RemoveTestEntries()
    for i = #self.db.entries, 1, -1 do
        if self.db.entries[i].test then tremove(self.db.entries, i) end
    end
    self:NotifyChanged()
    TestPrint("Test entries removed from the loot history.")
end

StaticPopupDialogs["RLS_TEST_HISTORY"] = {
    text = "Raid Loot Suite:\nTest mode put %d item(s) in the loot history (boss \"Test Boss\").\nRemove them?",
    button1 = "Remove", button2 = "Keep",
    OnAccept = function() RLT:RemoveTestEntries() end,
    timeout = 0, whileDead = 1, hideOnEscape = 1,
}

function RLT:ToggleTest()
    if self.testMode then self:StopTest() else self:StartTest() end
end

---------------------------------------------------------------------------
-- Fake raiders
---------------------------------------------------------------------------
local function Listed(list, name)
    for _, n in ipairs(list or {}) do if strlower(n) == strlower(name) then return true end end
end

local function FakeRolls(item)
    local s = RLT.db.settings
    local span = math.max(2, (item.duration or s.rollTime) - 3)
    for _, t in ipairs(RLT.TEST_PLAYERS) do
        local max
        if item.restrict then
            if Listed(item.restrict, t.name) then max = s.msRoll end
        elseif item.srMode then
            if Listed(item.srs, t.name) then max = s.msRoll end
        else
            local r = random()
            if r < 0.5 then max = s.msRoll elseif r < 0.8 then max = s.osRoll end
        end
        if max then
            local qid, name = item.qid, t.name
            After(1 + random() * span, function()
                local it = RLT:GetQueueItem(qid)
                if it and it.status == "ROLLING" then
                    RLT:CHAT_MSG_SYSTEM(format(RANDOM_ROLL_RESULT, name, random(1, max), 1, max))
                end
            end)
        end
    end
end

local function FakeCouncil(item)
    local qid = item.qid
    -- fake raiders you picked for the council vote too
    local voters = {}
    for _, n in ipairs(item.council or {}) do
        if RLT:GetTestClass(n) then voters[#voters + 1] = n end
    end
    if #voters == 0 then
        TestPrint("Tip: pick some fake raiders as council members (\"Council\" button) to see them vote.")
    end
    local answers = { "ms", "ms", "os", "pass" }
    for _, t in ipairs(RLT.TEST_PLAYERS) do
        local name = t.name
        local word = Listed(item.srs, name) and "ms" or answers[random(1, #answers)]
        After(1 + random() * 3, function()
            local it = RLT:GetQueueItem(qid)
            if not it or it.status ~= "COUNCIL" then return end
            if RLT.db.settings.whisperResponses then
                RLT:CHAT_MSG_WHISPER(word, name)
            else
                RLT:CHAT_MSG_ADDON("RLS", "RESP~" .. qid .. "~" .. strupper(word), "RAID", name)
            end
        end)
    end
    for _, voter in ipairs(voters) do
        After(5 + random() * 3, function()
            local it = RLT:GetQueueItem(qid)
            if not it or it.status ~= "COUNCIL" then return end
            local pool = {}
            for name, c in pairs(it.cands or {}) do if c.resp ~= "PASS" then pool[#pool + 1] = name end end
            if #pool > 0 then
                RLT:CHAT_MSG_ADDON("RLS", "VOTE~" .. qid .. "~" .. pool[random(1, #pool)], "RAID", voter)
            end
        end)
    end
end

-- Hook the session so fake raiders react in test mode
local origStartRoll, origStartCouncil = RLT.StartRoll, RLT.StartCouncil
local origAward, origSetStatus = RLT.Award, RLT.SetItemStatus

function RLT:StartRoll(qid, ...)
    origStartRoll(self, qid, ...)
    local item = self:GetQueueItem(qid)
    if self.testMode and item and item.status == "ROLLING" then
        FakeRolls(item)
        if self.ShowLootPopup then self:ShowLootPopup(item) end
    end
end

function RLT:StartCouncil(qid, ...)
    origStartCouncil(self, qid, ...)
    local item = self:GetQueueItem(qid)
    if self.testMode and item and item.status == "COUNCIL" then
        FakeCouncil(item)
        self:SessionChanged()
        if self.ShowLootPopup then self:ShowLootPopup(item) end
    end
end

function RLT:Award(qid, winner, ...)
    origAward(self, qid, winner, ...)
    local item = self:GetQueueItem(qid)
    if not self.testMode or not item or item.status ~= "AWARDED" then return end
    if self.HideLootPopup then self:HideLootPopup(item) end
    if item.test then
        TestPrint(item.link .. " -> " .. winner .. ": saved in the loot history (Master Loot is skipped in test mode).")
        local id, who, qid = item.itemID, item.winner, item.qid
        After(2, function()
            TestPrint(who .. " receives loot: " .. item.link)
            RLT:OnItemReceived(who, id)
            for _, e in ipairs(RLT.db.entries) do
                if e.qid == qid and not e.delivered then e.delivered = time(); RLT:NotifyChanged() end
            end
        end)
    end
end

function RLT:SetItemStatus(qid, status, ...)
    origSetStatus(self, qid, status, ...)
    if self.testMode and self.HideLootPopup then
        local item = self:GetQueueItem(qid)
        if item and item.status ~= "ROLLING" and item.status ~= "COUNCIL" then self:HideLootPopup(item) end
    end
end

-- A fake raider whispers you, one step per click:
-- "sr [item]" -> "sr" (check) -> "sr [other item]" (limit) -> "sr clear"
function RLT:FakeWhisperSR()
    if not self.testMode then
        self:Print("Start test mode first (Settings > \"Test mode\", or /rls test).")
        return
    end
    local links = {}
    for _, item in ipairs(self.db.queue) do if item.test then links[#links + 1] = item.link end end
    if #links == 0 then return end
    local who = "Roguetest"
    self.testWhisperStep = (self.testWhisperStep or 0) % 4 + 1
    local step = self.testWhisperStep
    local msg
    if step == 1 then msg = "sr " .. links[#links]
    elseif step == 2 then msg = "sr"
    elseif step == 3 then msg = "sr " .. links[1]
    else msg = "sr clear" end
    TestPrint(who .. " whispers you: " .. msg)
    if not self.db.settings.whisperSR then
        TestPrint("\"Players can whisper me sr [item]\" is off in Session settings, so this is ignored.")
        return
    end
    self:CHAT_MSG_WHISPER(msg, who)
end
