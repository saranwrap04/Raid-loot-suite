--[[
    Raid Loot Suite - Loot session windows
    Author: Saranwrap

    - Loot Session window: queue + current item (rolls / council votes) + session settings
    - Soft Reserves window: list, add / edit / delete, softres.it import, announce
    - Loot popup: shown to raiders when a roll or council vote starts
]]

local RLT = RaidLootSuite
local SUI = { queueRows = {}, candRows = {}, srRows = {} }
RLT.SUI = SUI

-- rows are created up to the MAX, the window size decides how many are shown
local Q_MAX, Q_ROW_H = 30, 30
local C_MAX, C_ROW_H = 40, 20
local SESSION_W, SESSION_H = 760, 500       -- default / minimum size
local SESSION_MAX_W, SESSION_MAX_H = 1400, 1000
local S_MAX, S_ROW_H = 40, 22
local SR_W, SR_H = 700, 520
local K_MAX, K_ROW_H = 40, 22
local K_W, K_H = 360, 478

local RESP_COLOR = { SR = "|cffc77dff", MS = "|cff4cd964", OS = "|cffffa040", PASS = "|cff777777" }
local CHANNEL_NAMES = { RAID_WARNING = "Raid Warning", RAID = "Raid", NONE = "Off (only me)" }
local CHANNEL_NEXT = { RAID_WARNING = "RAID", RAID = "NONE", NONE = "RAID_WARNING" }

local function W() return RLT.W end
-- an item can be rolled / voted when it is waiting (or nobody rolled / it was skipped)
local CAN_START = { PENDING = true, NOROLLS = true, SKIPPED = true }
local function Me() return UnitName("player") end

local function StatusText(status)
    local st = RLT.STATUS[status or "PENDING"] or RLT.STATUS.PENDING
    return st.color .. st.label .. "|r"
end

local function ItemText(item)
    return W().QualityHex(item.quality) .. (item.name or "?") .. "|r"
end

---------------------------------------------------------------------------
-- Shift-click item links into our edit boxes
---------------------------------------------------------------------------
local linkBoxes = {}
local function RegisterLinkBox(eb) linkBoxes[#linkBoxes + 1] = eb end
do
    local orig = ChatEdit_InsertLink
    if orig then
        ChatEdit_InsertLink = function(text, ...)
            for _, eb in ipairs(linkBoxes) do
                if eb:IsVisible() and eb:HasFocus() then
                    eb:Insert(text)
                    return true
                end
            end
            return orig(text, ...)
        end
    end
end

local function EditBox(parent, w, placeholder)
    local w_ = W()
    local eb = CreateFrame("EditBox", nil, parent)
    w_.Size(eb, w, 22)
    w_.Backdrop(eb, w_.C.panel)
    eb:SetFontObject(ChatFontNormal)
    eb:SetTextInsets(6, 6, 0, 0)
    eb:SetAutoFocus(false)
    local ph = w_.Text(eb, "GameFontDisableSmall")
    ph:SetPoint("LEFT", 6, 0)
    ph:SetText(placeholder or "")
    eb.placeholder = ph
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(unpack(w_.C.accent)) end)
    eb:SetScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(unpack(w_.C.border)) end)
    eb:SetScript("OnTextChanged", function(self)
        if (self:GetText() or "") == "" then ph:Show() else ph:Hide() end
    end)
    return eb
end

local function Window(name, title, w, h, navKey)
    local w_ = W()
    local f = CreateFrame("Frame", name, UIParent)
    w_.Size(f, w, h)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    w_.Backdrop(f, w_.C.bg)
    w_.AddPanel(f, w_.C.bg)
    f:Hide()
    tinsert(UISpecialFrames, name)

    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    bar:SetHeight(30)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(unpack(w_.C.title))
    local line = bar:CreateTexture(nil, "BORDER")
    line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT"); line:SetHeight(1)
    line:SetTexture(w_.C.accent[1], w_.C.accent[2], w_.C.accent[3], 0.6)
    local t = w_.Text(bar, "GameFontNormalLarge")
    t:SetPoint("LEFT", 10, 0)
    t:SetText(title)
    t:SetTextColor(1, 1, 1)
    f.title = t
    local close = w_.FlatButton(bar, "X", 22, 20, true)
    close:SetPoint("RIGHT", -6, 0)
    close:SetScript("OnClick", function() f:Hide() end)
    f.bar, f.navLeft = bar, close
    return f
end

-- Resize grip in the bottom-right corner. Size is saved in settings.windows[key];
-- double-click the grip to go back to the default size. onLayout(f) runs on every size change.
local MakeResizable
function MakeResizable(f, key, minW, minH, maxW, maxH, onLayout)
    local w_ = W()
    local saved = RLT.db.settings.windows and RLT.db.settings.windows[key]
    if saved then
        f:SetWidth(math.min(maxW, math.max(minW, saved.w or minW)))
        f:SetHeight(math.min(maxH, math.max(minH, saved.h or minH)))
    end
    f:SetResizable(true)
    f:SetMinResize(minW, minH)
    f:SetMaxResize(maxW, maxH)
    local grip = CreateFrame("Button", nil, f)
    w_.Size(grip, 16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel(f:GetFrameLevel() + 30)
    local dots = {}
    for i, pt in ipairs({ { 0, 0 }, { 5, 0 }, { 10, 0 }, { 5, 5 }, { 10, 5 }, { 10, 10 } }) do
        local d = grip:CreateTexture(nil, "OVERLAY")
        w_.Size(d, 3, 3)
        d:SetPoint("BOTTOMLEFT", grip, "BOTTOMLEFT", pt[1] + 1, pt[2] + 1)
        d:SetTexture(0.55, 0.55, 0.6, 0.9)
        dots[i] = d
    end
    local function Tint(r, g, b) for _, d in ipairs(dots) do d:SetTexture(r, g, b, 0.9) end end
    grip:SetScript("OnEnter", function(b)
        Tint(w_.C.accent[1], w_.C.accent[2], w_.C.accent[3])
        GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Drag to resize")
        GameTooltip:AddLine("Double-click: default size", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function() Tint(0.55, 0.55, 0.6); GameTooltip:Hide() end)
    grip:SetScript("OnMouseDown", function(_, button) if button == "LeftButton" then f:StartSizing("BOTTOMRIGHT") end end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        local s = RLT.db.settings
        s.windows = s.windows or {}
        s.windows[key] = { w = math.floor(f:GetWidth() + 0.5), h = math.floor(f:GetHeight() + 0.5) }
        onLayout(f)
    end)
    grip:SetScript("OnDoubleClick", function()
        f:SetWidth(minW); f:SetHeight(minH)
        local s = RLT.db.settings
        if s.windows then s.windows[key] = nil end
        onLayout(f)
    end)
    f:SetScript("OnSizeChanged", function() onLayout(f) end)
    f.grip = grip
    return grip
end

local function Checkbox(parent, name, label, x, y, key)
    local cb = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    W().Size(cb, 24, 24)
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    _G[name .. "Text"]:SetText(label)
    _G[name .. "Text"]:SetFontObject("GameFontHighlightSmall")
    cb:SetScript("OnShow", function(self) self:SetChecked(RLT.db.settings[key]) end)
    cb:SetScript("OnClick", function(self) RLT.db.settings[key] = self:GetChecked() and true or false end)
    return cb
end

SUI.Window = function(...) return Window(...) end
SUI.MakeResizable = function(...) return MakeResizable(...) end

---------------------------------------------------------------------------
-- Loot Session window
---------------------------------------------------------------------------
-- "Give to" submenu: Group 1..8 > players (party: one group)
function SUI:GiveToMenu(item)
    local groups = {}
    local n = GetNumRaidMembers()
    if n > 0 then
        for i = 1, n do
            local name, _, sub = GetRaidRosterInfo(i)
            if name then
                sub = sub or 1
                groups[sub] = groups[sub] or {}
                tinsert(groups[sub], name)
            end
        end
    else
        groups[1] = { Me() }
        for i = 1, GetNumPartyMembers() do
            local name = UnitName("party" .. i)
            if name then tinsert(groups[1], name) end
        end
    end
    if RLT.testMode then
        for i, t in ipairs(RLT.TEST_PLAYERS) do
            local g = (n > 0) and 8 or (i <= 4 and 1 or 2)
            groups[g] = groups[g] or {}
            tinsert(groups[g], t.name)
        end
    end
    local menu = {}
    for g = 1, 8 do
        local list = groups[g]
        if list and #list > 0 then
            table.sort(list)
            local sub = {}
            for _, name in ipairs(list) do
                sub[#sub + 1] = {
                    text = W().ClassColored(name, RLT:GetClassForName(name)), notCheckable = true,
                    func = function()
                        CloseDropDownMenus()
                        local c = item.cands and item.cands[name]
                        RLT:Award(item.qid, name, c and c.resp ~= "PASS" and c.resp or nil, nil, "given by the loot master")
                    end,
                }
            end
            menu[#menu + 1] = { text = "Group " .. g, notCheckable = true, hasArrow = true, menuList = sub }
        end
    end
    if #menu == 0 then menu[1] = { text = "Nobody in your group", notCheckable = true, disabled = true } end
    return menu
end

local function QueueMenu(item)
    local mine = item.owner == Me()
    local active = item.status == "ROLLING" or item.status == "COUNCIL"
    local menu = { { text = item.name or "?", isTitle = true, notCheckable = true } }
    local function add(text, fn, ok)
        if ok then menu[#menu + 1] = { text = text, notCheckable = true, func = fn } end
    end
    add("Start roll", function() RLT:StartRoll(item.qid) end, mine and CAN_START[item.status])
    add("Start council vote", function() RLT:StartCouncil(item.qid) end, mine and CAN_START[item.status])
    add("End roll now", function() RLT:FinishRoll(item.qid) end, mine and item.status == "ROLLING")
    add("Disenchant", function() RLT:SetItemStatus(item.qid, "DISENCHANT") end, mine and item.status ~= "DELIVERED")
    add("Skip", function() RLT:SetItemStatus(item.qid, "SKIPPED") end, mine and item.status ~= "DELIVERED")
    add("Back to waiting", function() RLT:SetItemStatus(item.qid, "PENDING") end, mine and not active and item.status ~= "PENDING")
    add("Link in chat", function() ChatEdit_InsertLink(item.link) end, true)
    if mine and item.status ~= "DELIVERED" then
        menu[#menu + 1] = { text = "Give to", notCheckable = true, hasArrow = true, menuList = SUI:GiveToMenu(item) }
    end
    add("|cffff7070Remove from queue|r", function() RLT:RemoveFromQueue(item.qid) end, true)
    menu[#menu + 1] = { text = "Close", notCheckable = true, func = function() end }
    W().ShowMenu(menu)
end

local function QueueRow_OnClick(self, button)
    if not self.item then return end
    if IsShiftKeyDown() then ChatEdit_InsertLink(self.item.link); return end
    SUI.selected = self.item.qid
    SUI.selectedCand = nil
    SUI:Refresh()
    if button == "RightButton" then QueueMenu(self.item) end
end

local function QueueRow_OnEnter(self)
    if not self.item then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(self.item.link)
    GameTooltip:Show()
end

local function CreateQueueRow(parent, i)
    local w_ = W()
    local row = CreateFrame("Button", nil, parent)
    w_.Size(row, 262, Q_ROW_H)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 1, -1 - (i - 1) * Q_ROW_H)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture(w_.C.accent[1], w_.C.accent[2], w_.C.accent[3], 0.12)
    local sel = row:CreateTexture(nil, "BACKGROUND")
    sel:SetAllPoints()
    sel:SetTexture(w_.C.accent[1], w_.C.accent[2], w_.C.accent[3], 0.2)
    sel:Hide()
    row.sel = sel
    local icon = row:CreateTexture(nil, "ARTWORK")
    w_.Size(icon, 24, 24)
    icon:SetPoint("LEFT", 4, 0)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.icon = icon
    local name = w_.Text(row, "GameFontHighlightSmall")
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 6, 0)
    name:SetWidth(222)
    name:SetHeight(13)
    name:SetJustifyH("LEFT")
    row.nameFS = name
    local status = w_.Text(row, "GameFontDisableSmall")
    status:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 6, 0)
    status:SetWidth(222)
    status:SetHeight(12)
    status:SetJustifyH("LEFT")
    row.statusFS = status
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", QueueRow_OnClick)
    row:SetScript("OnEnter", QueueRow_OnEnter)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function AwardCand(name)
    local item = RLT:GetQueueItem(SUI.selected)
    if not item or not name then return end
    local c = item.cands and item.cands[name]
    RLT:Award(item.qid, name, c and c.resp ~= "PASS" and c.resp or nil, c and c.roll)
end

local function CandRow_OnClick(self, button)
    if not self.cand then return end
    SUI.selectedCand = self.cand.name
    SUI:Refresh()
    local item = RLT:GetQueueItem(SUI.selected)
    if button == "RightButton" and item and item.owner == Me() then
        local name = self.cand.name
        W().ShowMenu({
            { text = name, isTitle = true, notCheckable = true },
            { text = "Award " .. (item.name or "item") .. " to " .. name, notCheckable = true, func = function() AwardCand(name) end },
            { text = "Close", notCheckable = true, func = function() end },
        })
    end
end

local function CreateCandRow(parent, i)
    local w_ = W()
    local row = CreateFrame("Button", nil, parent)
    w_.Size(row, 440, C_ROW_H)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 1, -1 - (i - 1) * C_ROW_H)
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(1, 1, 1, (i % 2 == 0) and 0.03 or 0)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture(w_.C.accent[1], w_.C.accent[2], w_.C.accent[3], 0.12)
    local sel = row:CreateTexture(nil, "BORDER")
    sel:SetAllPoints()
    sel:SetTexture(w_.C.accent[1], w_.C.accent[2], w_.C.accent[3], 0.22)
    sel:Hide()
    row.sel = sel
    row.cols = {}
    for c, spec in ipairs({ { 8, 140 }, { 152, 70 }, { 226, 50 }, { 280, 70 } }) do
        local fs = w_.Text(row, "GameFontHighlightSmall")
        fs:SetPoint("LEFT", row, "LEFT", spec[1], 0)
        fs:SetWidth(spec[2])
        fs:SetHeight(C_ROW_H)
        fs:SetJustifyH("LEFT")
        row.cols[c] = fs
    end
    local vote = w_.FlatButton(row, "Vote", 60, 16)
    vote:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    vote:SetScript("OnClick", function()
        if row.cand and SUI.selected then RLT:Vote(SUI.selected, row.cand.name) end
    end)
    row.vote = vote
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", CandRow_OnClick)
    row:SetScript("OnEnter", function(self)
        if not self.cand then return end
        local item = RLT:GetQueueItem(SUI.selected)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.cand.name)
        if item and item.votes then
            local voters = {}
            for voter, cand in pairs(item.votes) do if cand == self.cand.name then voters[#voters + 1] = voter end end
            if #voters > 0 then GameTooltip:AddLine("Votes: " .. table.concat(voters, ", "), 1, 1, 1, true) end
        end
        GameTooltip:AddLine("Click to select, then Award. Right-click: award now.", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

function SUI:CreateSession()
    local w_ = W()
    local f = Window("RaidLootSuiteSession", "Loot Session", 760, 500, "session")
    self.frame = f
    local by = w_.Text(f, "GameFontDisableSmall")
    by:SetPoint("LEFT", f.title, "RIGHT", 8, -1)
    by:SetText("")
    self.subtitle = by
    local help = w_.FlatButton(f, "?", 20, 20)
    help:SetPoint("RIGHT", f.navLeft, "LEFT", -6, 0)
    self.helpBtn = help
    help:SetScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("How it works")
        for _, l in ipairs({
            "1. Items arrive in the queue (boss loot as master looter, or shift-click one into the box).",
            "2. Select an item, press Roll (SR / MS / OS) or Council.",
            "3. Rolls end by themselves after the timer: the winner is announced and gets the item.",
            "4. Council: raiders answer, council members vote, you select a player and press Award.",
            " ",
            "Right-click an item in the queue or a player in the list for quick actions.",
            "Hover any item in the game to see who soft reserved it.",
            "Test mode lets you try everything alone with fake raiders.",
        }) do GameTooltip:AddLine(l, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    help:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Left: queue
    local qTitle = w_.Text(f, "GameFontNormal")
    qTitle:SetPoint("TOPLEFT", 12, -40)
    qTitle:SetText("Loot queue")
    qTitle:SetTextColor(unpack(w_.C.accent))

    local add = EditBox(f, 210, "Shift-click an item to add")
    add:SetPoint("TOPLEFT", 12, -60)
    RegisterLinkBox(add)
    local addBtn = w_.FlatButton(f, "Add", 52, 22)
    addBtn:SetPoint("LEFT", add, "RIGHT", 4, 0)
    local function DoAdd()
        local link = (add:GetText() or ""):match("|c%x+|Hitem:.-|h.-|h|r")
        if not link then
            local _, _, ilink = RLT:ResolveItem(add:GetText())
            link = ilink
        end
        if link then
            local item = RLT:AddToQueue(link)
            SUI.selected = item and item.qid or SUI.selected
            add:SetText("")
            add:ClearFocus()
        else
            RLT:Print("Shift-click an item (or type an item ID) to add it to the queue.")
        end
    end
    addBtn:SetScript("OnClick", DoAdd)
    add:SetScript("OnEnterPressed", DoAdd)

    local list = CreateFrame("Frame", nil, f)
    list:SetPoint("TOPLEFT", 12, -88)
    list:SetPoint("BOTTOMLEFT", 12, 72)
    list:SetWidth(266)
    w_.Backdrop(list, w_.C.panel)
    w_.AddPanel(list, w_.C.panel)
    self.qList = list
    for i = 1, Q_MAX do self.queueRows[i] = CreateQueueRow(list, i) end
    local qScroll = CreateFrame("ScrollFrame", "RaidLootSuiteQueueScroll", list, "FauxScrollFrameTemplate")
    qScroll:SetPoint("TOPLEFT", 0, -1)
    qScroll:SetPoint("BOTTOMRIGHT", -2, 1)
    qScroll:SetScript("OnVerticalScroll", function(s, offset)
        FauxScrollFrame_OnVerticalScroll(s, offset, Q_ROW_H, function() SUI:Refresh() end)
    end)
    self.qScroll = qScroll
    local qEmpty = w_.Text(list, "GameFontDisableSmall")
    qEmpty:SetPoint("CENTER")
    qEmpty:SetWidth(230)
    qEmpty:SetText("Queue is empty.\nAs master looter, opening the boss loot adds items here. You can also shift-click any item into the box above.")
    self.qEmpty = qEmpty

    local clearBtn = w_.FlatButton(f, "Clear finished", 130, 22)
    clearBtn:SetPoint("BOTTOMLEFT", 12, 44)
    clearBtn.tip = "Remove awarded, delivered, disenchanted and skipped items from the queue."
    clearBtn:SetScript("OnClick", function() RLT:ClearFinished() end)

    -- Right: current item
    local panel = CreateFrame("Frame", nil, f)
    panel:SetPoint("TOPLEFT", 292, -40)
    panel:SetPoint("BOTTOMRIGHT", -12, 44)
    self.panel = panel

    local icon = panel:CreateTexture(nil, "ARTWORK")
    w_.Size(icon, 36, 36)
    icon:SetPoint("TOPLEFT", 0, 0)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    self.icon = icon
    local iconBtn = CreateFrame("Button", nil, panel)
    iconBtn:SetAllPoints(icon)
    iconBtn:SetScript("OnEnter", function(b)
        local item = RLT:GetQueueItem(SUI.selected)
        if item then GameTooltip:SetOwner(b, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink(item.link); GameTooltip:Show() end
    end)
    iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local name = w_.Text(panel, "GameFontNormalLarge")
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -1)
    name:SetWidth(300)
    name:SetJustifyH("LEFT")
    self.itemName = name

    -- Roll timer (top right of the panel)
    local tSuffix = w_.Text(panel, "GameFontHighlightSmall")
    tSuffix:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -4)
    tSuffix:SetText("sec")
    local tBox = EditBox(panel, 40, "")
    tBox:SetPoint("RIGHT", tSuffix, "LEFT", -4, 0)
    tBox:SetNumeric(true)
    tBox:SetMaxLetters(3)
    tBox:SetJustifyH("CENTER")
    local tLabel = w_.Text(panel, "GameFontHighlightSmall")
    tLabel:SetPoint("RIGHT", tBox, "LEFT", -6, 0)
    tLabel:SetText("Roll timer:")
    local function ApplyTimer(eb)
        local v = RLT:SetRollTime(eb:GetText())
        eb:SetText(tostring(v or RLT.db.settings.rollTime))
        eb:ClearFocus()
    end
    tBox:SetScript("OnEnterPressed", ApplyTimer)
    tBox:SetScript("OnEditFocusLost", function(eb)
        eb:SetBackdropBorderColor(unpack(w_.C.border))
        if tonumber(eb:GetText() or "") ~= RLT.db.settings.rollTime then ApplyTimer(eb) end
    end)
    tBox:SetScript("OnShow", function(eb) eb:SetText(tostring(RLT.db.settings.rollTime)) end)
    tBox.tip = "Seconds a roll stays open (" .. RLT.ROLL_TIME_MIN .. "-" .. RLT.ROLL_TIME_MAX .. "). Press Enter. Used by the next roll."
    tBox:SetScript("OnEnter", function(eb)
        GameTooltip:SetOwner(eb, "ANCHOR_TOP"); GameTooltip:SetText(eb.tip, 1, 1, 1, 1, true); GameTooltip:Show()
    end)
    tBox:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.timerBox = tBox
    local sub = w_.Text(panel, "GameFontHighlightSmall")
    sub:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 8, 1)
    sub:SetWidth(300)
    sub:SetJustifyH("LEFT")
    self.itemSub = sub

    local buttons = {
        { key = "roll",    label = "Roll",       w = 56, tip = "Start a roll: SR'ers only if the item is soft reserved, otherwise MS / OS. The winner is picked automatically when the timer ends." },
        { key = "council", label = "Council",    w = 66, tip = "Start a loot council vote. Raiders whisper MS / OS (or use the popup); council members vote; you award." },
        { key = "stop",    label = "End now",    w = 64, tip = "End the roll now and pick the winner." },
        { key = "award",   label = "Award",      w = 58, tip = "Give the item to the selected player." },
        { key = "de",      label = "Disenchant", w = 78, tip = "Give it to the disenchanter set in Settings (Master Loot if the loot window is open) and save it as DE in the history." },
        { key = "skip",    label = "Skip",       w = 46, tip = "Skip this item." },
        { key = "remove",  label = "Remove",     w = 58, tip = "Remove the item from the queue.", danger = true },
    }
    self.btn = {}
    local prev
    for _, b in ipairs(buttons) do
        local btn = w_.FlatButton(panel, b.label, b.w, 22, b.danger)
        if prev then btn:SetPoint("LEFT", prev, "RIGHT", 4, 0) else btn:SetPoint("TOPLEFT", 0, -46) end
        btn.tip = b.tip
        self.btn[b.key] = btn
        prev = btn
    end
    self.btn.roll:SetScript("OnClick", function() RLT:StartRoll(SUI.selected) end)
    self.btn.council:SetScript("OnClick", function() RLT:StartCouncil(SUI.selected) end)
    self.btn.stop:SetScript("OnClick", function()
        local item = RLT:GetQueueItem(SUI.selected)
        if item and item.status == "ROLLING" then RLT:FinishRoll(item.qid) end
    end)
    self.btn.award:SetScript("OnClick", function()
        local item = RLT:GetQueueItem(SUI.selected)
        if not item then return end
        if not SUI.selectedCand then RLT:Print("Select a player in the list first."); return end
        AwardCand(SUI.selectedCand)
    end)
    self.btn.de:SetScript("OnClick", function() RLT:SetItemStatus(SUI.selected, "DISENCHANT") end)
    self.btn.skip:SetScript("OnClick", function() RLT:SetItemStatus(SUI.selected, "SKIPPED") end)
    self.btn.remove:SetScript("OnClick", function() RLT:RemoveFromQueue(SUI.selected); SUI.selected = nil end)

    local info = w_.Text(panel, "GameFontHighlightSmall")
    info:SetPoint("TOPLEFT", 0, -76)
    info:SetWidth(440)
    info:SetJustifyH("LEFT")
    self.info = info

    local header = CreateFrame("Frame", nil, panel)
    header:SetPoint("TOPLEFT", 0, -112)
    header:SetPoint("TOPRIGHT", -22, -112)
    header:SetHeight(20)
    w_.Backdrop(header, w_.C.header)
    for _, h in ipairs({ { 9, "Player" }, { 153, "Response" }, { 227, "Roll" }, { 281, "Votes" } }) do
        local fs = w_.Text(header, "GameFontNormalSmall")
        fs:SetPoint("LEFT", h[1], 0)
        fs:SetText(h[2])
    end
    local cList = CreateFrame("Frame", nil, panel)
    cList:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    cList:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -22, 4)
    self.cList = cList
    w_.Backdrop(cList, w_.C.panel)
    w_.AddPanel(cList, w_.C.panel)
    for i = 1, C_MAX do self.candRows[i] = CreateCandRow(cList, i) end
    local cScroll = CreateFrame("ScrollFrame", "RaidLootSuiteCandScroll", cList, "FauxScrollFrameTemplate")
    cScroll:SetPoint("TOPLEFT", 0, -1)
    cScroll:SetPoint("BOTTOMRIGHT", -2, 1)
    cScroll:SetScript("OnVerticalScroll", function(s, offset)
        FauxScrollFrame_OnVerticalScroll(s, offset, C_ROW_H, function() SUI:Refresh() end)
    end)
    self.cScroll = cScroll
    local cEmpty = w_.Text(cList, "GameFontDisableSmall")
    cEmpty:SetPoint("CENTER")
    cEmpty:SetWidth(400)
    self.cEmpty = cEmpty

    -- Footer
    local status = w_.Text(f, "GameFontDisableSmall")
    status:SetPoint("BOTTOMRIGHT", -14, 17)
    self.status = status

    self:CreateSettings(f)

    -- Resize grip (size from the previous version is kept)
    local st = RLT.db.settings
    if st.sessionWindow then
        st.windows = st.windows or {}
        st.windows.session = st.windows.session or st.sessionWindow
        st.sessionWindow = nil
    end
    MakeResizable(f, "session", SESSION_W, SESSION_H, SESSION_MAX_W, SESSION_MAX_H, function() SUI:Layout() end)
    f:SetScript("OnShow", function() SUI:Layout() end)
end

function SUI:CreateSettings(f)
    local w_ = W()
    local o = CreateFrame("Frame", nil, f)
    o:SetPoint("TOPLEFT", 12, -36)
    o:SetPoint("BOTTOMRIGHT", -12, 42)
    w_.Backdrop(o, w_.C.bg)
    o:SetFrameLevel(f:GetFrameLevel() + 20)
    o:EnableMouse(true)
    o:Hide()
    self.settings = o
    local s = function() return RLT.db.settings end

    local title = w_.Text(o, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("Session settings")
    title:SetTextColor(unpack(w_.C.accent))

    local testBtn = w_.FlatButton(o, "Test mode", 110, 24)
    testBtn:SetPoint("TOPRIGHT", -12, -8)
    testBtn.tip = "Try rolls, soft reserves and council alone: fake raiders answer, nothing is sent to chat. Awards go in the history as \"Test Boss\". (/rls test)"
    testBtn:SetScript("OnClick", function() RLT:ToggleTest() end)
    self.testBtn = testBtn
    local testInfo = w_.Text(o, "GameFontDisableSmall")
    testInfo:SetPoint("RIGHT", testBtn, "LEFT", -10, 0)
    testInfo:SetText("Try the loot session alone, with fake raiders:")

    -- Roll timer
    local slider = CreateFrame("Slider", "RLSRollTimeSlider", o, "OptionsSliderTemplate")
    w_.Size(slider, 220, 17)
    slider:SetPoint("TOPLEFT", 20, -58)
    slider:SetMinMaxValues(RLT.ROLL_TIME_MIN, RLT.ROLL_TIME_MAX)
    slider:SetValueStep(1)
    _G.RLSRollTimeSliderLow:SetText(RLT.ROLL_TIME_MIN .. "s")
    _G.RLSRollTimeSliderHigh:SetText(RLT.ROLL_TIME_MAX .. "s")
    _G.RLSRollTimeSliderText:SetFontObject("GameFontHighlightSmall")
    slider:SetScript("OnShow", function(self) self:SetValue(s().rollTime) end)
    slider:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v + 0.5)
        if v ~= s().rollTime then RLT:SetRollTime(v) end
        _G.RLSRollTimeSliderText:SetText("Roll timer: " .. v .. " seconds")
    end)

    -- Roll values are fixed
    local rolls = w_.Text(o, "GameFontHighlightSmall")
    rolls:SetPoint("TOPLEFT", 20, -100)
    rolls:SetText("Rolls:  |cff4cd964MS = /roll 100|r    |cffffa040OS = /roll 99|r    |cffc77dffSR = /roll 100|r")

    local srLabel = w_.Text(o, "GameFontHighlightSmall")
    srLabel:SetPoint("TOPLEFT", 20, -158)
    srLabel:SetText("Soft reserves per player:")
    local srBtn = w_.FlatButton(o, "", 40, 20)
    srBtn:SetPoint("LEFT", srLabel, "RIGHT", 8, 0)
    srBtn:SetScript("OnShow", function(self) self:SetText(tostring(s().srPerPlayer)) end)
    srBtn:SetScript("OnClick", function(self)
        s().srPerPlayer = (s().srPerPlayer % 3) + 1
        self:SetText(tostring(s().srPerPlayer))
    end)

    local function ChannelButton(label, y, key)
        local l = w_.Text(o, "GameFontHighlightSmall")
        l:SetPoint("TOPLEFT", 20, y)
        l:SetText(label)
        local b = w_.FlatButton(o, "", 120, 20)
        b:SetPoint("LEFT", l, "RIGHT", 8, 0)
        b:SetScript("OnShow", function(self) self:SetText(CHANNEL_NAMES[s()[key]] or "?") end)
        b:SetScript("OnClick", function(self)
            s()[key] = CHANNEL_NEXT[s()[key]] or "RAID"
            self:SetText(CHANNEL_NAMES[s()[key]])
        end)
    end
    ChannelButton("Announce roll start in:", -188, "announceStart")
    ChannelButton("Announce winners in:", -216, "announceResult")
    ChannelButton("Countdown (5, 4, 3, 2, 1) in:", -244, "announceCountdown")

    -- Right column: checkboxes
    Checkbox(o, "RLSOptAutoQueue", "Add boss loot to the queue when I'm master looter", 360, -50, "autoQueue")
    Checkbox(o, "RLSOptAutoAward", "Give the item with Master Loot when it's awarded", 360, -78, "autoAward")
    Checkbox(o, "RLSOptCountdown", "Count down 5, 4, 3, 2, 1 in chat at the end of a roll", 360, -106, "countdown")
    Checkbox(o, "RLSOptWhisperSR", "Players can whisper me \"sr [item]\"", 360, -134, "whisperSR")
    Checkbox(o, "RLSOptWhisperResp", "Players can whisper me MS / OS / pass (council)", 360, -162, "whisperResponses")
    Checkbox(o, "RLSOptAnnounceDrops", "Post the boss loot in raid chat when I loot the boss (master looter)", 360, -190, "announceDrops")

    -- Designated disenchanter
    local deLabel = w_.Text(o, "GameFontHighlightSmall")
    deLabel:SetPoint("TOPLEFT", 366, -226)
    deLabel:SetText("Disenchanter:")
    local deBox = EditBox(o, 130, "Player name")
    deBox:SetPoint("LEFT", deLabel, "RIGHT", 8, 0)
    deBox:SetScript("OnShow", function(self) self:SetText(s().disenchanter or "") end)
    deBox:SetScript("OnTextChanged", function(self)
        s().disenchanter = strtrim(self:GetText() or "")
        if s().disenchanter == "" then self.placeholder:Show() else self.placeholder:Hide() end
    end)
    deBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    local deTarget = w_.FlatButton(o, "Use target", 80, 20)
    deTarget:SetPoint("LEFT", deBox, "RIGHT", 6, 0)
    deTarget.tip = "Set your current target as the disenchanter."
    deTarget:SetScript("OnClick", function()
        if UnitExists("target") and UnitIsPlayer("target") then deBox:SetText(UnitName("target")) end
    end)
    Checkbox(o, "RLSOptAutoDE", "Nobody rolls: give the item to the disenchanter", 360, -250, "autoDisenchant")

    local cl = w_.Text(o, "GameFontNormal")
    cl:SetPoint("TOPLEFT", 20, -282)
    cl:SetText("Loot council")
    cl:SetTextColor(unpack(w_.C.accent))
    local pick = w_.FlatButton(o, "Choose council members", 170, 22)
    pick:SetPoint("TOPLEFT", 20, -302)
    pick.tip = "Pick who can vote in a council: tick raid members, or add a name. You are always on it."
    pick:SetScript("OnClick", function() RLT:ShowCouncil() end)
    local summary = w_.Text(o, "GameFontHighlightSmall")
    summary:SetPoint("LEFT", pick, "RIGHT", 10, 0)
    summary:SetWidth(500)
    summary:SetJustifyH("LEFT")
    self.councilSummary = summary
    o:SetScript("OnShow", function() SUI:RefreshCouncilSummary() end)

    local help = w_.Text(o, "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", 20, -336)
    help:SetWidth(690)
    help:SetJustifyH("LEFT")
    help:SetText("Rolls: an item soft reserved by players in the raid is rolled among those players only (one SR'er = they win). " ..
        "Otherwise /roll MS beats /roll OS, highest roll wins, ties reroll automatically.\n" ..
        "Council: raiders answer with the popup (if they have Raid Loot Suite) or by whispering you MS / OS / pass. " ..
        "Council members need Raid Loot Suite to see candidates and vote; you award.")
end

function SUI:CouncilText()
    local names = {}
    for _, n in ipairs(RLT:GetCouncil()) do
        names[#names + 1] = W().ClassColored(n, RLT:GetClassForName(n))
    end
    return names
end

function SUI:RefreshCouncilSummary()
    local names = self:CouncilText()
    if self.councilSummary then
        self.councilSummary:SetText("|cff999999" .. #names .. " member(s):|r " .. table.concat(names, ", "))
    end
    if self.councilBtn then self.councilBtn:SetText("Council (" .. #names .. ")") end
end

-- Fits rows / column widths to the current window size
function SUI:RefreshTestButton()
    if not self.testBtn then return end
    if RLT.testMode then
        self.subtitle:SetText("|cffffd100TEST MODE - fake raiders, nothing is sent to chat|r")
        self.testBtn:SetText("Stop test")
        self.testBtn:SetBackdropBorderColor(1, 0.82, 0, 1)
    else
        self.subtitle:SetText("")
        self.testBtn:SetText("Test mode")
        self.testBtn:SetBackdropBorderColor(unpack(W().C.border))
    end
end

function SUI:Layout()
    local f = self.frame
    if not f then return end
    local w, h = f:GetWidth() or SESSION_W, f:GetHeight() or SESSION_H
    -- queue list: from y -88 to 72 above the bottom
    self.qRows = math.max(1, math.min(Q_MAX, math.floor((h - 88 - 72 - 2) / Q_ROW_H)))
    -- right panel: x 292 .. w-12, candidate list from y -(40+112+22) to 48 above the bottom
    local panelW = w - 292 - 12
    local listW = panelW - 22
    self.cRows = math.max(1, math.min(C_MAX, math.floor((h - 40 - 134 - 48 - 2) / C_ROW_H)))
    for _, row in ipairs(self.candRows) do row:SetWidth(listW - 4) end
    self.info:SetWidth(panelW)
    self.itemName:SetWidth(math.max(200, panelW - 150))
    self.itemSub:SetWidth(math.max(200, panelW - 150))
    self.cEmpty:SetWidth(listW - 40)
    self:Refresh()
end

-- Session settings now live in the Settings tab of the main window (Main.lua)
function SUI:SetSettingsShown(show)
    if show then RLT:ShowTab("settings", "session") end
end

function SUI:Refresh()
    if not self.frame or not self.frame:IsShown() then return end
    local w_ = W()
    local queue = RLT.db.queue
    if self.timerBox and not self.timerBox:HasFocus() then self.timerBox:SetText(tostring(RLT.db.settings.rollTime)) end
    self:RefreshTestButton()

    -- keep a valid selection
    if not RLT:GetQueueItem(self.selected or "") then
        local active = RLT:GetActiveItem()
        self.selected = active and active.qid or (queue[1] and queue[1].qid) or nil
    end

    local Q_ROWS, C_ROWS = self.qRows or 11, self.cRows or 10
    FauxScrollFrame_Update(self.qScroll, #queue, Q_ROWS, Q_ROW_H)
    local offset = FauxScrollFrame_GetOffset(self.qScroll)
    for i = 1, Q_MAX do
        local row = self.queueRows[i]
        local item = i <= Q_ROWS and queue[offset + i]
        if item then
            row.item = item
            row.icon:SetTexture(RLT:GetItemIcon(item.itemID))
            row.nameFS:SetText(ItemText(item))
            local extra = ""
            if item.winner then extra = " - " .. w_.ClassColored(item.winner, RLT:GetClassForName(item.winner)) end
            if item.status == "ROLLING" and item.endsAt then extra = " - " .. math.max(0, item.endsAt - time()) .. "s" end
            if item.remote then extra = extra .. " |cff777777(" .. item.owner .. ")|r" end
            if not RLT.FINISHED_STATUS[item.status] then
                local srs = RLT:GetSRs(item.itemID, item.name, true)
                if #srs > 0 then extra = extra .. "  |cffc77dffSR: " .. table.concat(srs, ", ") .. "|r" end
            end
            row.statusFS:SetText(StatusText(item.status) .. extra)
            if item.qid == self.selected then row.sel:Show() else row.sel:Hide() end
            row:Show()
        else
            row.item = nil
            row:Hide()
        end
    end
    if #queue == 0 then self.qEmpty:Show() else self.qEmpty:Hide() end

    local item = RLT:GetQueueItem(self.selected or "")
    local mine = item and item.owner == Me()
    local active = item and (item.status == "ROLLING" or item.status == "COUNCIL")
    local function enable(b, on) if on then b:Enable() else b:Disable() end end
    -- FlatButton draws "disabled" as the selected style; use alpha for unavailable buttons instead
    for key, b in pairs(self.btn) do
        local on
        if key == "roll" or key == "council" then on = mine and CAN_START[item.status]
        elseif key == "stop" then on = mine and item.status == "ROLLING"
        elseif key == "award" then on = mine and item.status ~= "DELIVERED"
        elseif key == "de" or key == "skip" then on = mine and item.status ~= "DELIVERED"
        elseif key == "remove" then on = item ~= nil end
        b:SetAlpha(on and 1 or 0.35)
        if on then b:Enable() else b:Disable(); b:SetBackdropColor(unpack(w_.C.button)); b:SetBackdropBorderColor(unpack(w_.C.border)) end
    end

    if not item then
        self.icon:SetTexture(nil)
        self.itemName:SetText("|cff777777No item selected|r")
        self.itemSub:SetText("")
        self.info:SetText("")
    else
        self.icon:SetTexture(RLT:GetItemIcon(item.itemID))
        self.itemName:SetText(ItemText(item))
        local sub = StatusText(item.status)
        if item.boss and item.boss ~= "" then sub = sub .. "  |cff888888" .. item.boss .. "|r" end
        if item.remote then sub = sub .. "  |cff888888run by " .. item.owner .. "|r" end
        self.itemSub:SetText(sub)
        local info = {}
        if item.testLabel and not item.winner then info[#info + 1] = "|cffffd100Test:|r " .. item.testLabel end
        local srs = (item.srs and #item.srs > 0) and item.srs or RLT:GetSRs(item.itemID, item.name, true)
        if #srs > 0 then info[#info + 1] = "|cffc77dffSoft reserved by:|r " .. table.concat(srs, ", ") end
        if item.status == "ROLLING" and item.endsAt then
            info[#info + 1] = RLT.ACCENT .. math.max(0, item.endsAt - time()) .. " seconds left|r" ..
                (item.srMode and "  (SR'ers only)" or "") .. (item.restrict and ("  (reroll: " .. table.concat(item.restrict, ", ") .. ")") or "")
        elseif item.status == "COUNCIL" then
            info[#info + 1] = "|cffc77dffCouncil:|r " .. table.concat(item.council or {}, ", ")
        end
        if item.winner then
            info[#info + 1] = "|cff4cd964Winner:|r " .. w_.ClassColored(item.winner, RLT:GetClassForName(item.winner)) ..
                (item.winSpec and (" (" .. item.winSpec .. (item.winRoll and (" " .. item.winRoll) or "") .. ")") or "")
        end
        self.info:SetText(table.concat(info, "\n"))
    end

    local cands = item and RLT:SortedCands(item) or {}
    local votes = item and RLT:CountVotes(item) or {}
    local canVote = item and item.status == "COUNCIL" and RLT:IsCouncil(item, Me())
    FauxScrollFrame_Update(self.cScroll, #cands, C_ROWS, C_ROW_H)
    local coff = FauxScrollFrame_GetOffset(self.cScroll)
    for i = 1, C_MAX do
        local row = self.candRows[i]
        local c = i <= C_ROWS and cands[coff + i]
        if c then
            row.cand = c
            row.cols[1]:SetText(w_.ClassColored(c.name, c.class or RLT:GetClassForName(c.name)))
            row.cols[2]:SetText(c.resp and ((RESP_COLOR[c.resp] or "") .. c.resp .. "|r") or "|cff777777-|r")
            row.cols[3]:SetText(c.roll and tostring(c.roll) or "|cff777777-|r")
            row.cols[4]:SetText((votes[c.name] or 0) > 0 and tostring(votes[c.name]) or "|cff777777-|r")
            if c.name == self.selectedCand then row.sel:Show() else row.sel:Hide() end
            if canVote then
                row.vote:Show()
                local mineVote = item.votes and item.votes[Me()] == c.name
                row.vote:SetText(mineVote and "Voted" or "Vote")
                row.vote:SetBackdropColor(unpack(mineVote and w_.C.accent or w_.C.button))
            else
                row.vote:Hide()
            end
            row:Show()
        else
            row.cand = nil
            row:Hide()
        end
    end
    if #cands == 0 then
        self.cEmpty:SetText(item and (item.status == "ROLLING" and "Waiting for rolls..." or
            item.status == "COUNCIL" and "Waiting for responses (popup, whisper MS / OS, or /roll)..." or
            "Start a Roll or a Council vote for this item.") or "")
        self.cEmpty:Show()
    else
        self.cEmpty:Hide()
    end

    local pending, done = 0, 0
    for _, q in ipairs(queue) do if RLT.FINISHED_STATUS[q.status] then done = done + 1 else pending = pending + 1 end end
    self.status:SetText(pending .. " waiting / " .. done .. " done / " .. #RLT.db.softres .. " SR")
    self:RefreshCouncilSummary()
end

---------------------------------------------------------------------------
-- Soft Reserves window
---------------------------------------------------------------------------
-- Three views of the same list:
--   By item   one row per item: who reserved it, queue status / winner
--   By player one row per player: their reserves (x / limit)
--   Edit list one row per reserve: click to edit, x to delete
local SR_VIEWS = {
    { key = "item",   label = "By item",   cols = { "Item", "Reserved by" } },
    { key = "player", label = "By player", cols = { "Player", "Soft reserves" } },
    { key = "list",   label = "Edit list", cols = { "Player", "Item" } },
}

local function SRItemName(sr)
    local name, _, q
    if sr.itemID then name, _, q = GetItemInfo(sr.itemID) end
    return name or sr.itemName or ("item " .. tostring(sr.itemID)), q or 4
end

local function SRItemLink(sr)
    return sr.itemID and select(2, GetItemInfo(sr.itemID)) or nil
end

-- Latest queue item for this itemID (to show Rolling / Won by ...)
local function QueueInfo(itemID)
    if not itemID then return end
    local found
    for _, q in ipairs(RLT.db.queue) do if q.itemID == itemID then found = q end end
    return found
end

local function PlayerText(name)
    local w_ = W()
    if not RLT:IsGrouped() or RLT:InGroup(name) then
        return w_.ClassColored(name, RLT:GetClassForName(name))
    end
    return "|cff777777" .. name .. "|r"
end

local function WonBy(itemID, name)
    for _, q in ipairs(RLT.db.queue) do
        if q.itemID == itemID and q.winner and strlower(q.winner) == strlower(name)
            and (q.status == "AWARDED" or q.status == "DELIVERED") then return true end
    end
end

function SUI:BuildSRRows()
    local view = self.srView or "item"
    local search = strlower(strtrim(self.srSearch and self.srSearch:GetText() or ""))
    local onlyRaid = RLT.db.settings.srOnlyRaid and RLT:IsGrouped()
    local rows = {}
    local function visible(sr)
        if onlyRaid and not RLT:InGroup(sr.player) then return false end
        if search == "" then return true end
        return strlower(sr.player):find(search, 1, true) or strlower(SRItemName(sr)):find(search, 1, true)
    end
    if view == "list" then
        for i, sr in ipairs(RLT.db.softres) do
            if visible(sr) then rows[#rows + 1] = { kind = "sr", index = i, sr = sr } end
        end
    elseif view == "item" then
        local byKey = {}
        for i, sr in ipairs(RLT.db.softres) do
            if visible(sr) then
                local key = sr.itemID or strlower(sr.itemName or "?")
                local r = byKey[key]
                if not r then
                    r = { kind = "item", sr = sr, players = {}, indexes = {} }
                    byKey[key] = r
                    rows[#rows + 1] = r
                end
                r.players[#r.players + 1] = sr.player
                r.indexes[#r.indexes + 1] = i
            end
        end
        table.sort(rows, function(a, b)
            if #a.players ~= #b.players then return #a.players > #b.players end
            return SRItemName(a.sr) < SRItemName(b.sr)
        end)
    else
        local byName = {}
        for i, sr in ipairs(RLT.db.softres) do
            if visible(sr) then
                local key = strlower(sr.player)
                local r = byName[key]
                if not r then
                    r = { kind = "player", name = sr.player, srs = {}, indexes = {} }
                    byName[key] = r
                    rows[#rows + 1] = r
                end
                r.srs[#r.srs + 1] = sr
                r.indexes[#r.indexes + 1] = i
            end
        end
        table.sort(rows, function(a, b) return a.name < b.name end)
    end
    return rows
end

local function SRMenu(r)
    local menu = {}
    if r.kind == "item" then
        local link = SRItemLink(r.sr)
        menu[#menu + 1] = { text = SRItemName(r.sr), isTitle = true, notCheckable = true }
        if link then
            menu[#menu + 1] = { text = "Add to loot queue", notCheckable = true, func = function()
                local item = RLT:AddToQueue(link)
                if item then SUI.selected = item.qid end
                RLT:ShowSession()
            end }
        end
        menu[#menu + 1] = { text = "Add a player for this item", notCheckable = true, func = function()
            SUI.srEdit = nil; SUI.srSave:SetText("Add")
            SUI.srItem:SetText(link or SRItemName(r.sr)); SUI.srPlayer:SetText(""); SUI.srPlayer:SetFocus()
        end }
        for k, name in ipairs(r.players) do
            local idx = r.indexes[k]
            menu[#menu + 1] = { text = "|cffff7070Remove|r " .. name, notCheckable = true, func = function() RLT:RemoveSR(idx) end }
        end
    elseif r.kind == "player" then
        menu[#menu + 1] = { text = r.name, isTitle = true, notCheckable = true }
        menu[#menu + 1] = { text = "Add a reserve for this player", notCheckable = true, func = function()
            SUI.srEdit = nil; SUI.srSave:SetText("Add")
            SUI.srPlayer:SetText(r.name); SUI.srItem:SetText(""); SUI.srItem:SetFocus()
        end }
        for k, sr in ipairs(r.srs) do
            local idx = r.indexes[k]
            menu[#menu + 1] = { text = "|cffff7070Remove|r " .. SRItemName(sr), notCheckable = true, func = function() RLT:RemoveSR(idx) end }
        end
        if #r.indexes > 1 then
            menu[#menu + 1] = { text = "|cffff7070Remove all|r", notCheckable = true, func = function()
                for k = #r.indexes, 1, -1 do RLT:RemoveSR(r.indexes[k]) end
            end }
        end
    else
        return
    end
    menu[#menu + 1] = { text = "Close", notCheckable = true, func = function() end }
    W().ShowMenu(menu)
end

local function SRRow_OnClick(self, button)
    local r = self.data
    if not r then return end
    if button == "RightButton" then SRMenu(r); return end
    if IsShiftKeyDown() and r.sr and SRItemLink(r.sr) then
        ChatEdit_InsertLink(SRItemLink(r.sr)); return
    end
    if r.kind == "sr" then
        SUI.srEdit = r.index
        SUI.srPlayer:SetText(r.sr.player or "")
        SUI.srItem:SetText(SRItemLink(r.sr) or (r.sr.itemName or ""))
        SUI.srSave:SetText("Save")
    elseif r.kind == "item" then
        SUI.srEdit = nil; SUI.srSave:SetText("Add")
        SUI.srItem:SetText(SRItemLink(r.sr) or SRItemName(r.sr))
        SUI.srPlayer:SetText(""); SUI.srPlayer:SetFocus()
    else
        SUI.srEdit = nil; SUI.srSave:SetText("Add")
        SUI.srPlayer:SetText(r.name); SUI.srItem:SetText(""); SUI.srItem:SetFocus()
    end
    SUI:RefreshSR()
end

local function SRRow_OnEnter(self)
    local r = self.data
    if not r then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if r.kind == "player" then
        GameTooltip:AddLine(r.name)
        for _, sr in ipairs(r.srs) do
            local name, q = SRItemName(sr)
            GameTooltip:AddLine(W().QualityHex(q) .. name .. "|r" .. (WonBy(sr.itemID, r.name) and "  |cff4cd964won|r" or ""))
        end
    elseif r.sr.itemID then
        GameTooltip:SetHyperlink("item:" .. r.sr.itemID)
    else
        GameTooltip:AddLine(SRItemName(r.sr))
    end
    local hint = (r.kind == "sr") and "Click: edit   x: delete" or "Click: add to it   Right-click: options"
    GameTooltip:AddLine(hint .. "   Shift-click: link", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

function SUI:CreateSR()
    local w_ = W()
    local f = Window("RaidLootSuiteSR", "Soft Reserves", SR_W, SR_H, "sr")
    self.srFrame = f

    -- Add / edit
    local player = EditBox(f, 140, "Player name")
    player:SetPoint("TOPLEFT", 12, -42)
    local itemBox = EditBox(f, 300, "Item: shift-click it, or type its ID / exact name")
    itemBox:SetPoint("LEFT", player, "RIGHT", 6, 0)
    RegisterLinkBox(itemBox)
    self.srPlayer, self.srItem = player, itemBox
    local save = w_.FlatButton(f, "Add", 70, 22)
    save:SetPoint("LEFT", itemBox, "RIGHT", 6, 0)
    save.tip = "Add the soft reserve (or save your changes when editing a row)."
    self.srSave = save
    local new = w_.FlatButton(f, "Clear", 60, 22)
    new:SetPoint("LEFT", save, "RIGHT", 6, 0)
    new.tip = "Empty the boxes / stop editing."
    local function ResetEdit()
        SUI.srEdit = nil
        player:SetText(""); itemBox:SetText("")
        save:SetText("Add")
        SUI:RefreshSR()
    end
    new:SetScript("OnClick", ResetEdit)
    local function DoSave()
        local id, name = RLT:ResolveItem(itemBox:GetText())
        local ok, err
        if SUI.srEdit then
            ok, err = RLT:UpdateSR(SUI.srEdit, player:GetText(), id, name)
        else
            ok, err = RLT:AddSR(player:GetText(), id, name, true)
        end
        if ok then
            if not id then RLT:Print("Saved as \"" .. tostring(name) .. "\". Tip: shift-click the item so it is matched by its ID.") end
            ResetEdit()
        else
            RLT:Print("Soft reserve not saved: " .. tostring(err))
        end
    end
    save:SetScript("OnClick", DoSave)
    itemBox:SetScript("OnEnterPressed", DoSave)
    player:SetScript("OnEnterPressed", function() itemBox:SetFocus() end)
    player:SetScript("OnTabPressed", function() itemBox:SetFocus() end)

    -- View tabs, search, filter
    self.srTabs = {}
    local prev
    for _, v in ipairs(SR_VIEWS) do
        local b = w_.FlatButton(f, v.label, 84, 22)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", 12, -72) end
        b:SetScript("OnClick", function() SUI.srView = v.key; SUI.srEdit = nil; save:SetText("Add"); SUI:RefreshSR() end)
        self.srTabs[v.key] = b
        prev = b
    end
    local search = EditBox(f, 190, "Search player or item")
    search:SetPoint("LEFT", prev, "RIGHT", 12, 0)
    search:SetScript("OnTextChanged", function(eb)
        if (eb:GetText() or "") == "" then eb.placeholder:Show() else eb.placeholder:Hide() end
        SUI:RefreshSR()
    end)
    search:SetScript("OnEnterPressed", function(eb) eb:ClearFocus() end)
    self.srSearch = search
    local onlyRaid = CreateFrame("CheckButton", "RLSSROnlyRaid", f, "UICheckButtonTemplate")
    w_.Size(onlyRaid, 22, 22)
    onlyRaid:SetPoint("LEFT", search, "RIGHT", 8, 0)
    _G.RLSSROnlyRaidText:SetText("Only my raid")
    _G.RLSSROnlyRaidText:SetFontObject("GameFontHighlightSmall")
    onlyRaid:SetScript("OnShow", function(cb) cb:SetChecked(RLT.db.settings.srOnlyRaid) end)
    onlyRaid:SetScript("OnClick", function(cb) RLT.db.settings.srOnlyRaid = cb:GetChecked() and true or false; SUI:RefreshSR() end)
    self.srOnlyRaid = onlyRaid

    -- Header + list
    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", 12, -102)
    header:SetPoint("TOPRIGHT", -12, -102)
    header:SetHeight(20)
    w_.Backdrop(header, w_.C.header)
    local h1 = w_.Text(header, "GameFontNormalSmall"); h1:SetPoint("LEFT", 9, 0)
    local h2 = w_.Text(header, "GameFontNormalSmall"); h2:SetPoint("LEFT", 236, 0)
    local h3 = w_.Text(header, "GameFontNormalSmall"); h3:SetPoint("RIGHT", -34, 0)
    h3:SetText("Status")
    self.srHead = { h1, h2 }

    local list = CreateFrame("Frame", nil, f)
    list:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    list:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -2)
    list:SetPoint("BOTTOM", f, "BOTTOM", 0, 44)
    self.srList = list
    w_.Backdrop(list, w_.C.panel)
    w_.AddPanel(list, w_.C.panel)
    for i = 1, S_MAX do
        local row = CreateFrame("Button", nil, list)
        w_.Size(row, 648, S_ROW_H)
        row:SetPoint("TOPLEFT", 1, -1 - (i - 1) * S_ROW_H)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local stripe = row:CreateTexture(nil, "BACKGROUND")
        stripe:SetAllPoints()
        stripe:SetTexture(1, 1, 1, (i % 2 == 0) and 0.03 or 0)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetTexture(w_.C.accent[1], w_.C.accent[2], w_.C.accent[3], 0.12)
        local sel = row:CreateTexture(nil, "BORDER")
        sel:SetAllPoints()
        sel:SetTexture(w_.C.accent[1], w_.C.accent[2], w_.C.accent[3], 0.22)
        sel:Hide()
        row.sel = sel
        local icon1 = row:CreateTexture(nil, "ARTWORK")
        w_.Size(icon1, 16, 16); icon1:SetPoint("LEFT", 8, 0); icon1:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        local c1 = w_.Text(row, "GameFontHighlightSmall")
        c1:SetHeight(S_ROW_H); c1:SetJustifyH("LEFT")
        local icon2 = row:CreateTexture(nil, "ARTWORK")
        w_.Size(icon2, 16, 16); icon2:SetPoint("LEFT", 235, 0); icon2:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        local c2 = w_.Text(row, "GameFontHighlightSmall")
        c2:SetHeight(S_ROW_H); c2:SetJustifyH("LEFT")
        local c3 = w_.Text(row, "GameFontHighlightSmall")
        c3:SetPoint("RIGHT", -30, 0); c3:SetWidth(120); c3:SetHeight(S_ROW_H); c3:SetJustifyH("RIGHT")
        local del = w_.FlatButton(row, "x", 20, 16, true)
        del:SetPoint("RIGHT", -6, 0)
        del.tip = "Delete this soft reserve"
        del:SetScript("OnClick", function()
            local r = row.data
            if r and r.kind == "sr" then
                if SUI.srEdit == r.index then SUI.srEdit = nil; save:SetText("Add") end
                RLT:RemoveSR(r.index)
            end
        end)
        row.icon1, row.icon2, row.c1, row.c2, row.c3, row.del = icon1, icon2, c1, c2, c3, del
        row:SetScript("OnClick", SRRow_OnClick)
        row:SetScript("OnEnter", SRRow_OnEnter)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        self.srRows[i] = row
    end
    local sScroll = CreateFrame("ScrollFrame", "RaidLootSuiteSRScroll", list, "FauxScrollFrameTemplate")
    sScroll:SetPoint("TOPLEFT", 0, -1)
    sScroll:SetPoint("BOTTOMRIGHT", -28, 1)
    sScroll:SetScript("OnVerticalScroll", function(s, offset)
        FauxScrollFrame_OnVerticalScroll(s, offset, S_ROW_H, function() SUI:RefreshSR() end)
    end)
    self.sScroll = sScroll
    local sEmpty = w_.Text(list, "GameFontDisableSmall")
    sEmpty:SetPoint("CENTER")
    sEmpty:SetWidth(560)
    self.sEmpty = sEmpty

    -- Footer
    local import = w_.FlatButton(f, "Import (softres.it)", 140, 24)
    import:SetPoint("BOTTOMLEFT", 12, 10)
    import.tip = "Paste a softres.it CSV export, or one reserve per line."
    import:SetScript("OnClick", function() SUI:ShowSRImport() end)
    local announce = w_.FlatButton(f, "Announce", 90, 24)
    announce:SetPoint("LEFT", import, "RIGHT", 8, 0)
    announce.tip = "Post the soft reserve list in raid chat, one line per item."
    announce:SetScript("OnClick", function() RLT:AnnounceSRs() end)
    local fake = w_.FlatButton(f, "Fake whisper", 100, 24)
    fake:SetPoint("LEFT", announce, "RIGHT", 8, 0)
    fake.tip = "Test mode: Roguetest whispers you, one step per click:\n1. sr [item]  2. sr (check)  3. sr [other item] (limit)  4. sr clear"
    fake:SetScript("OnClick", function() RLT:FakeWhisperSR() end)
    self.srFake = fake
    local clear = w_.FlatButton(f, "Clear all", 90, 24, true)
    clear:SetPoint("BOTTOMRIGHT", -12, 10)
    clear:SetScript("OnClick", function() StaticPopup_Show("RLS_CONFIRM_CLEAR_SR") end)
    local count = w_.Text(f, "GameFontDisableSmall")
    count:SetPoint("RIGHT", clear, "LEFT", -12, 0)
    self.srCount = count

    -- Import box
    local imp = CreateFrame("Frame", nil, f)
    imp:SetPoint("TOPLEFT", 12, -36)
    imp:SetPoint("BOTTOMRIGHT", -12, 42)
    w_.Backdrop(imp, w_.C.bg)
    imp:SetFrameLevel(f:GetFrameLevel() + 20)
    imp:EnableMouse(true)
    imp:Hide()
    self.srImport = imp
    local ih = w_.Text(imp, "GameFontHighlightSmall")
    ih:SetPoint("TOPLEFT", 8, -8)
    ih:SetWidth(656)
    ih:SetJustifyH("LEFT")
    ih:SetText("On softres.it, open your raid and export it as CSV, then paste it below (Ctrl+V).\n" ..
        "Also accepted: one reserve per line, like  |cffccccccPlayer: [item]|r  or  |cffccccccPlayer, 49623|r.")
    local box = CreateFrame("Frame", nil, imp)
    box:SetPoint("TOPLEFT", 8, -44)
    box:SetPoint("BOTTOMRIGHT", -8, 36)
    w_.Backdrop(box, w_.C.panel)
    local scroll = CreateFrame("ScrollFrame", "RaidLootSuiteSRImportScroll", box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    local eb = CreateFrame("EditBox", nil, scroll)
    eb:SetMultiLine(true)
    eb:SetMaxLetters(0)
    eb:SetAutoFocus(false)
    eb:SetFontObject(ChatFontNormal)
    w_.Size(eb, 610, 280)
    self.srImportBox, self.srImportFrame = eb, box
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scroll:SetScrollChild(eb)
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function() eb:SetFocus() end)
    local replace = CreateFrame("CheckButton", "RLSSRReplace", imp, "UICheckButtonTemplate")
    w_.Size(replace, 22, 22)
    replace:SetPoint("BOTTOMLEFT", 6, 6)
    _G.RLSSRReplaceText:SetText("Replace the current list")
    _G.RLSSRReplaceText:SetFontObject("GameFontHighlightSmall")
    local go = w_.FlatButton(imp, "Import", 90, 22)
    go:SetPoint("BOTTOMRIGHT", -8, 8)
    go:SetScript("OnClick", function()
        local added, dupes, failed = RLT:ImportSR(eb:GetText(), replace:GetChecked())
        RLT:Print(string.format("Soft reserves: %d added, %d already there, %d unreadable.", added, dupes, failed))
        if added > 0 then eb:SetText(""); imp:Hide() end
        SUI:RefreshSR()
    end)
    local cancel = w_.FlatButton(imp, "Cancel", 80, 22)
    cancel:SetPoint("RIGHT", go, "LEFT", -6, 0)
    cancel:SetScript("OnClick", function() imp:Hide() end)

    MakeResizable(f, "sr", SR_W, SR_H, 1400, 1000, function() SUI:LayoutSR() end)
    f:SetScript("OnShow", function() SUI:LayoutSR() end)
end

function SUI:LayoutSR()
    local f = self.srFrame
    if not f then return end
    local w, h = f:GetWidth() or SR_W, f:GetHeight() or SR_H
    -- list: from y -124 to 44 above the bottom, scroll bar takes 28
    self.srRowsShown = math.max(1, math.min(S_MAX, math.floor((h - 124 - 44 - 2) / S_ROW_H)))
    local rowW = w - 24 - 28
    self.srRowW = rowW
    for _, row in ipairs(self.srRows) do row:SetWidth(rowW) end
    self.srImportBox:SetWidth(w - 24 - 16 - 38)
    self.srImportBox:SetHeight(math.max(100, h - 36 - 42 - 44 - 36 - 16))
    self.sEmpty:SetWidth(rowW - 60)
    self:RefreshSR()
end

function SUI:ShowSRImport()
    self.srImport:Show()
end

function SUI:RefreshSR()
    if not self.srFrame or not self.srFrame:IsShown() then return end
    local w_ = W()
    local view = self.srView or "item"
    for key, b in pairs(self.srTabs) do
        b:SetBackdropColor(unpack(key == view and w_.C.sel or w_.C.button))
    end
    for _, v in ipairs(SR_VIEWS) do
        if v.key == view then self.srHead[1]:SetText(v.cols[1]); self.srHead[2]:SetText(v.cols[2]) end
    end
    if RLT.testMode then self.srFake:Show() else self.srFake:Hide() end

    local rows = self:BuildSRRows()
    local S_ROWS = self.srRowsShown or 14
    -- item / player text gets the room left between column 2 and the status column
    local c2w = math.max(150, (self.srRowW or 648) - 256 - 158)
    FauxScrollFrame_Update(self.sScroll, #rows, S_ROWS, S_ROW_H)
    local offset = FauxScrollFrame_GetOffset(self.sScroll)
    local limit = RLT.db.settings.srPerPlayer
    for i = 1, S_MAX do
        local row = self.srRows[i]
        local r = i <= S_ROWS and rows[offset + i] or nil
        row.data = r
        if r then
            row.del:Hide(); row.sel:Hide(); row.c3:SetText("")
            if r.kind == "item" then
                local name, q = SRItemName(r.sr)
                row.icon1:SetTexture(RLT:GetItemIcon(r.sr.itemID)); row.icon1:Show()
                row.c1:SetPoint("LEFT", 28, 0); row.c1:SetWidth(196)
                row.c1:SetText(w_.QualityHex(q) .. name .. "|r")
                row.icon2:Hide()
                row.c2:SetPoint("LEFT", 236, 0); row.c2:SetWidth(c2w + 19)
                local names = {}
                for _, n in ipairs(r.players) do
                    names[#names + 1] = PlayerText(n) .. (WonBy(r.sr.itemID, n) and " |cff4cd964(won)|r" or "")
                end
                row.c2:SetText("|cffc77dff" .. #r.players .. "|r  " .. table.concat(names, ", "))
                local qi = QueueInfo(r.sr.itemID)
                if qi then
                    local st = RLT.STATUS[qi.status] or RLT.STATUS.PENDING
                    row.c3:SetText(qi.winner and ("|cff4cd964Won by|r " .. PlayerText(qi.winner)) or (st.color .. st.label .. "|r"))
                end
            elseif r.kind == "player" then
                row.icon1:Hide()
                row.c1:SetPoint("LEFT", 8, 0); row.c1:SetWidth(216)
                local n = #r.srs
                local over = n > limit and "|cffffa040" or "|cff999999"
                row.c1:SetText(PlayerText(r.name) .. "  " .. over .. n .. "/" .. limit .. "|r")
                row.icon2:SetTexture(RLT:GetItemIcon(r.srs[1].itemID)); row.icon2:Show()
                row.c2:SetPoint("LEFT", 256, 0); row.c2:SetWidth(c2w)
                local items = {}
                for _, sr in ipairs(r.srs) do
                    local name, q = SRItemName(sr)
                    items[#items + 1] = w_.QualityHex(q) .. name .. "|r" .. (WonBy(sr.itemID, r.name) and " |cff4cd964(won)|r" or "")
                end
                row.c2:SetText(table.concat(items, ", "))
                if RLT:IsGrouped() and not RLT:InGroup(r.name) then row.c3:SetText("|cff777777not in raid|r") end
            else
                local sr = r.sr
                row.icon1:Hide()
                row.c1:SetPoint("LEFT", 8, 0); row.c1:SetWidth(216)
                row.c1:SetText(PlayerText(sr.player))
                row.icon2:SetTexture(RLT:GetItemIcon(sr.itemID)); row.icon2:Show()
                row.c2:SetPoint("LEFT", 256, 0); row.c2:SetWidth(c2w)
                local name, q = SRItemName(sr)
                row.c2:SetText(w_.QualityHex(q) .. name .. "|r")
                if sr.test then row.c3:SetText("|cffffd100test|r")
                elseif not sr.itemID then row.c3:SetText("|cffffa040name only|r") end
                row.del:Show()
                if SUI.srEdit == r.index then row.sel:Show() end
            end
            row:Show()
        else
            row:Hide()
        end
    end

    local total = #RLT.db.softres
    if #rows == 0 then
        self.sEmpty:SetText(total == 0 and
            "No soft reserves yet.\nImport them from softres.it, add them above, or let players whisper you \"sr [item]\".\nWant to try it first? Settings > \"Test mode\" (or /rls test)."
            or "Nothing matches the search / filter.")
        self.sEmpty:Show()
    else
        self.sEmpty:Hide()
    end
    local players, items = {}, {}
    for _, sr in ipairs(RLT.db.softres) do
        players[strlower(sr.player)] = true
        items[sr.itemID or strlower(sr.itemName or "?")] = true
    end
    local np, ni = 0, 0
    for _ in pairs(players) do np = np + 1 end
    for _ in pairs(items) do ni = ni + 1 end
    self.srCount:SetText(total .. " reserves  /  " .. np .. " players  /  " .. ni .. " items")
end

StaticPopupDialogs["RLS_CONFIRM_CLEAR_SR"] = {
    text = "Raid Loot Suite:\nDelete ALL soft reserves?",
    button1 = YES, button2 = NO,
    OnAccept = function() RLT:ClearSR() end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, showAlert = 1,
}

---------------------------------------------------------------------------
-- Loot popup for raiders
---------------------------------------------------------------------------
function SUI:CreatePopup()
    local w_ = W()
    local p = CreateFrame("Frame", "RaidLootSuitePopup", UIParent)
    w_.Size(p, 300, 104)
    p:SetPoint("TOP", 0, -140)
    p:SetFrameStrata("DIALOG")
    p:SetClampedToScreen(true)
    p:SetMovable(true)
    p:EnableMouse(true)
    p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", p.StartMoving)
    p:SetScript("OnDragStop", p.StopMovingOrSizing)
    w_.Backdrop(p, w_.C.bg, w_.C.accent)
    p:Hide()
    self.popup = p
    local icon = p:CreateTexture(nil, "ARTWORK")
    w_.Size(icon, 36, 36)
    icon:SetPoint("TOPLEFT", 10, -10)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    p.icon = icon
    local iconBtn = CreateFrame("Button", nil, p)
    iconBtn:SetAllPoints(icon)
    iconBtn:SetScript("OnEnter", function(b)
        if p.item then GameTooltip:SetOwner(b, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink(p.item.link); GameTooltip:Show() end
    end)
    iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local name = w_.Text(p, "GameFontNormal")
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -1)
    name:SetWidth(236)
    name:SetJustifyH("LEFT")
    p.nameFS = name
    local mode = w_.Text(p, "GameFontHighlightSmall")
    mode:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 8, 1)
    mode:SetWidth(236)
    mode:SetJustifyH("LEFT")
    p.modeFS = mode
    local close = w_.FlatButton(p, "x", 18, 16, true)
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() p:Hide() end)

    local b1 = w_.FlatButton(p, "MS", 86, 24)
    b1:SetPoint("BOTTOMLEFT", 10, 10)
    local b2 = w_.FlatButton(p, "OS", 86, 24)
    b2:SetPoint("LEFT", b1, "RIGHT", 6, 0)
    local b3 = w_.FlatButton(p, "Pass", 86, 24)
    b3:SetPoint("LEFT", b2, "RIGHT", 6, 0)
    p.b1, p.b2, p.b3 = b1, b2, b3
    local function Act(kind)
        local item = p.item
        if not item then return end
        if item.mode == "roll" then
            if kind == "MS" or kind == "SR" then RandomRoll(1, 100)
            elseif kind == "OS" then RandomRoll(1, 99) end
        else
            -- council: send the answer, and roll too (MS / SR = /roll 100, OS = /roll 99)
            RLT:Respond(item.qid, kind)
            if kind == "MS" or kind == "SR" then RandomRoll(1, 100)
            elseif kind == "OS" then RandomRoll(1, 99) end
        end
        p:Hide()
    end
    b1:SetScript("OnClick", function(self) Act(self.kind) end)
    b2:SetScript("OnClick", function() Act("OS") end)
    b3:SetScript("OnClick", function() Act("PASS") end)
end

function RLT:ShowLootPopup(item)
    local p = SUI.popup
    if not p or not item or (item.owner == Me() and not RLT.testMode) then return end
    if item.status ~= "ROLLING" and item.status ~= "COUNCIL" then return end
    p.item = item
    p.icon:SetTexture(RLT:GetItemIcon(item.itemID))
    p.nameFS:SetText(ItemText(item))
    local amSR, restricted = false, false
    for _, n in ipairs(item.srs or {}) do if string.lower(n) == string.lower(Me()) then amSR = true end end
    if item.restrict then
        restricted = true
        for _, n in ipairs(item.restrict) do if string.lower(n) == string.lower(Me()) then restricted = false end end
    end
    p.b1.kind = "MS"
    p.b1:SetText("MS")
    p.b1:Show(); p.b2:Show()
    if item.mode == "roll" then
        if restricted then
            p.modeFS:SetText("Reroll between " .. table.concat(item.restrict, ", "))
            p.b1:Hide(); p.b2:Hide()
        elseif item.srMode then
            p.modeFS:SetText(amSR and "|cffc77dffYou soft reserved this - roll!|r" or "|cffc77dffSoft reserved - SR'ers roll only|r")
            p.b1.kind = "SR"
            p.b1:SetText("SR roll")
            p.b2:Hide()
            if not amSR then p.b1:Hide() end
        else
            p.modeFS:SetText("Roll: MS /roll 100, OS /roll 99")
        end
    else
        p.modeFS:SetText("Loot council - choose your answer")
        if amSR then p.b1.kind = "SR"; p.b1:SetText("SR") end
    end
    p:Show()
end

function RLT:HideLootPopup(item)
    local p = SUI.popup
    if p and p:IsShown() and (not item or p.item == item) then p:Hide() end
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Loot council picker (the loot master decides who votes)
---------------------------------------------------------------------------

-- you, then group members (A-Z), then saved members who are not in the group
function SUI:CouncilRows()
    local rows, seen = {}, {}
    local me = Me()
    rows[1] = { name = me, me = true, inGroup = true }
    seen[strlower(me)] = true
    local ranks = {}
    for i = 1, GetNumRaidMembers() do
        local name, rank = GetRaidRosterInfo(i)
        if name then ranks[name] = rank end
    end
    local members = {}
    for name in pairs(RLT:GroupMembers()) do
        if not seen[strlower(name)] then members[#members + 1] = name; seen[strlower(name)] = true end
    end
    table.sort(members)
    for _, name in ipairs(members) do
        rows[#rows + 1] = { name = name, inGroup = true, rank = ranks[name] }
    end
    for _, name in ipairs(RLT:GetCouncilPicks()) do
        if not seen[strlower(name)] then
            seen[strlower(name)] = true
            rows[#rows + 1] = { name = name, inGroup = false }
        end
    end
    return rows
end

function SUI:CreateCouncil()
    local w_ = W()
    local f = Window("RaidLootSuiteCouncil", "Loot Council", K_W, K_H, "none")
    self.councilFrame = f
    local intro = w_.Text(f, "GameFontHighlightSmall")
    intro:SetPoint("TOPLEFT", 12, -40)
    intro:SetWidth(336)
    intro:SetJustifyH("LEFT")
    intro:SetText("Tick who can vote in a council. You are always on it.\nChanges apply right away, also to a vote in progress.")

    local lead = w_.FlatButton(f, "Leader + assists", 130, 22)
    lead:SetPoint("TOPLEFT", 12, -72)
    lead.tip = "Put the raid leader and every assistant on the council."
    lead:SetScript("OnClick", function()
        local picks = RLT:GetCouncilPicks()
        for i = 1, GetNumRaidMembers() do
            local name, rank = GetRaidRosterInfo(i)
            if name and (rank or 0) >= 1 and name ~= Me() then picks[#picks + 1] = name end
        end
        local list, seen = {}, {}
        for _, n in ipairs(picks) do
            if not seen[strlower(n)] then seen[strlower(n)] = true; list[#list + 1] = n end
        end
        RLT:SetCouncilPicks(list)
    end)
    local none = w_.FlatButton(f, "Only me", 80, 22)
    none:SetPoint("LEFT", lead, "RIGHT", 6, 0)
    none.tip = "Remove everybody else from the council."
    none:SetScript("OnClick", function() RLT:SetCouncilPicks({}) end)

    local list = CreateFrame("Frame", nil, f)
    list:SetPoint("TOPLEFT", 12, -100)
    list:SetPoint("BOTTOMRIGHT", -12, 44)
    self.councilList = list
    w_.Backdrop(list, w_.C.panel)
    w_.AddPanel(list, w_.C.panel)
    self.councilRows = {}
    for i = 1, K_MAX do
        local row = CreateFrame("Button", nil, list)
        w_.Size(row, 308, K_ROW_H)
        row:SetPoint("TOPLEFT", 1, -1 - (i - 1) * K_ROW_H)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetTexture(w_.C.accent[1], w_.C.accent[2], w_.C.accent[3], 0.12)
        local box = CreateFrame("Frame", nil, row)
        w_.Size(box, 14, 14)
        box:SetPoint("LEFT", 8, 0)
        w_.Backdrop(box, w_.C.button)
        local check = box:CreateTexture(nil, "OVERLAY")
        w_.Size(check, 20, 20)
        check:SetPoint("CENTER", 1, 0)
        check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        local name = w_.Text(row, "GameFontHighlightSmall")
        name:SetPoint("LEFT", 30, 0)
        name:SetWidth(170); name:SetJustifyH("LEFT")
        local note = w_.Text(row, "GameFontDisableSmall")
        note:SetPoint("RIGHT", -6, 0)
        note:SetWidth(110); note:SetJustifyH("RIGHT")
        row.check, row.nameFS, row.note = check, name, note
        row:SetScript("OnClick", function(r)
            if not r.data or r.data.me then return end
            RLT:SetCouncilMember(r.data.name, not RLT:IsCouncilPick(r.data.name))
        end)
        self.councilRows[i] = row
    end
    local scroll = CreateFrame("ScrollFrame", "RaidLootSuiteCouncilScroll", list, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -1)
    scroll:SetPoint("BOTTOMRIGHT", -26, 1)
    scroll:SetScript("OnVerticalScroll", function(sf, offset)
        FauxScrollFrame_OnVerticalScroll(sf, offset, K_ROW_H, function() SUI:RefreshCouncil() end)
    end)
    self.councilScroll = scroll

    local add = EditBox(f, 250, "Add a name (not in the raid yet)")
    add:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 12)
    local addBtn = w_.FlatButton(f, "Add", 80, 22)
    addBtn:SetPoint("LEFT", add, "RIGHT", 6, 0)
    local function DoAdd()
        local n = strtrim(add:GetText() or "")
        if n ~= "" then RLT:SetCouncilMember(n, true) end
        add:SetText(""); add:ClearFocus()
    end
    addBtn:SetScript("OnClick", DoAdd)
    add:SetScript("OnEnterPressed", DoAdd)

    self.councilIntro = intro
    MakeResizable(f, "council", K_W, K_H, 900, 1000, function() SUI:LayoutCouncil() end)
    f:SetScript("OnShow", function() SUI:LayoutCouncil() end)
end

function SUI:LayoutCouncil()
    local f = self.councilFrame
    if not f then return end
    local w, h = f:GetWidth() or K_W, f:GetHeight() or K_H
    self.councilRowsShown = math.max(1, math.min(K_MAX, math.floor((h - 100 - 44 - 2) / K_ROW_H)))
    local rowW = w - 24 - 28
    for _, row in ipairs(self.councilRows) do
        row:SetWidth(rowW)
        row.nameFS:SetWidth(math.max(120, rowW - 150))
    end
    self.councilIntro:SetWidth(w - 24)
    self:RefreshCouncil()
end

function SUI:RefreshCouncil()
    if not self.councilFrame or not self.councilFrame:IsShown() then return end
    local w_ = W()
    local rows = self:CouncilRows()
    local K_ROWS = self.councilRowsShown or 14
    FauxScrollFrame_Update(self.councilScroll, #rows, K_ROWS, K_ROW_H)
    local offset = FauxScrollFrame_GetOffset(self.councilScroll)
    for i = 1, K_MAX do
        local row = self.councilRows[i]
        local r = i <= K_ROWS and rows[offset + i] or nil
        row.data = r
        if r then
            local on = r.me or RLT:IsCouncilPick(r.name)
            if on then row.check:Show() else row.check:Hide() end
            row.nameFS:SetText(r.inGroup and w_.ClassColored(r.name, RLT:GetClassForName(r.name)) or ("|cff999999" .. r.name .. "|r"))
            local note = ""
            if r.me then note = "you (always)"
            elseif not r.inGroup then note = "not in group"
            elseif r.rank == 2 then note = "raid leader"
            elseif r.rank == 1 then note = "assist" end
            row.note:SetText(note)
            row:Show()
        else
            row:Hide()
        end
    end
end

-- "Soft reserved by: ..." on every item tooltip
local function AddSRToTooltip(tt)
    if not RLT.db or not tt.GetItem then return end
    local name, link = tt:GetItem()
    local id = link and tonumber(link:match("item:(%d+)"))
    if not id then return end
    local names = RLT:GetSRs(id, name, false)
    if #names == 0 then return end
    local shown = {}
    for _, n in ipairs(names) do
        shown[#shown + 1] = (RLT:IsGrouped() and not RLT:InGroup(n)) and ("|cff777777" .. n .. "|r") or n
    end
    tt:AddLine("|cffc77dffSoft reserved (" .. #names .. "):|r " .. table.concat(shown, ", "), 1, 1, 1, true)
    tt:Show()
end

function RLT:InitSessionUI()
    SUI:CreateSession()
    SUI:CreateSR()
    SUI:CreatePopup()
    SUI:CreateCouncil()
    for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
        if tt and tt.HookScript then tt:HookScript("OnTooltipSetItem", AddSRToTooltip) end
    end
    local wui = RLT.W and RLT.W.UI
    if wui and wui.ApplyOpacity then wui:ApplyOpacity() end
end

function RLT:OnSessionChanged()
    SUI:RefreshTestButton()
    SUI:Refresh()
    SUI:RefreshSR()
    SUI:RefreshCouncil()
    SUI:RefreshCouncilSummary()
end

function RLT:OnRollTimeChanged()
    local s = self.db.settings
    if SUI.timerBox and not SUI.timerBox:HasFocus() then SUI.timerBox:SetText(tostring(s.rollTime)) end
    local sl = _G.RLSRollTimeSlider
    if sl and math.abs((sl:GetValue() or 0) - s.rollTime) >= 1 then sl:SetValue(s.rollTime) end
end

function RLT:OnSessionTick()
    SUI:Refresh()
end

