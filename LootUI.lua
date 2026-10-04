--[[
    Raid Loot Suite - Loot Tables tab
    Author: Saranwrap

    Every Wrath raid boss, its loot in 10 / 25 (and heroic) with drop chances,
    trash epics and patterns. Data: LootData.lua.
]]

local RLT = RaidLootSuite
local LUI = { bossRows = {}, itemRows = {}, cache = {} }
RLT.LUI = LUI

local B_MAX, B_ROW_H = 40, 22
local I_MAX, I_ROW_H = 40, 22
local MODE_LABEL = { ["10"] = "10", ["25"] = "25", ["10H"] = "10 HC", ["25H"] = "25 HC" }

local function W() return RLT.W end
local function Data() return RaidLootSuite_LootData end

-- "45100:4.4:h:13,..." -> { {id=, pct=, hm=, src=}, ... }
local function Parse(str)
    local list = {}
    for entry in (str or ""):gmatch("[^,]+") do
        local id, pct, hm, src = entry:match("^(%d+):([%d%.]+):?(%a*):?(%d*)$")
        if id then
            list[#list + 1] = { id = tonumber(id), pct = tonumber(pct), hm = hm == "h", src = tonumber(src) }
        end
    end
    return list
end

function LUI:GetLoot(raidIdx, bossIdx, mode)
    local key = raidIdx .. ":" .. bossIdx .. ":" .. mode
    if not self.cache[key] then
        local boss = Data().raids[raidIdx].bosses[bossIdx]
        self.cache[key] = Parse(boss.loot and boss.loot[mode])
    end
    return self.cache[key]
end

local function ItemInfo(id)
    local d = Data().items[id]
    local name, link, q = GetItemInfo(id)
    q = q or (d and d[2]) or 4
    name = name or (d and d[1]) or ("item " .. id)
    if not link then
        link = W().QualityHex(q) .. "|Hitem:" .. id .. ":0:0:0:0:0:0:0:0|h[" .. name .. "]|h|r"
    end
    return name, link, q, d and d[3] or "", d and d[4] or 0, d and d[5]
end
RLT.LootItemInfo = ItemInfo

-- " A" (Alliance only, blue) / " H" (Horde only, red) after the item name
local FACTION_TAG = { A = " |cff4a9effA|r", H = " |cffff4a4aH|r" }
local function FactionTag(f) return FACTION_TAG[f or ""] or "" end
RLT.LootFactionTag = FactionTag

-- column sorting (click a column header)
local SORT_DEFAULT_DESC = { ilvl = true, pct = true }
local function SortRows(rows, key, desc)
    if not key then return end
    local function val(r)
        local name, _, _, typ, ilvl = ItemInfo(r.id)
        if key == "name" then return strlower(name)
        elseif key == "type" then return strlower(typ)
        elseif key == "ilvl" then return ilvl
        else return r.pct end
    end
    for i, r in ipairs(rows) do r._k, r._i = val(r), i end
    table.sort(rows, function(a, b)
        if a._k ~= b._k then
            if desc then return a._k > b._k else return a._k < b._k end
        end
        return a._i < b._i
    end)
end

local function PctText(p)
    if p >= 100 then return "|cff4cd964100%|r" end
    local c = p >= 20 and "|cffffffff" or (p >= 5 and "|cffcccccc" or "|cff999999")
    return c .. p .. "%|r"
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function ItemMenu(r)
    local _, link = ItemInfo(r.id)
    W().ShowMenu({
        { text = (ItemInfo(r.id)), isTitle = true, notCheckable = true },
        { text = "Link in chat", notCheckable = true, func = function() ChatEdit_InsertLink(link) end },
        { text = "Add to loot queue", notCheckable = true, func = function()
            local item = RLT:AddToQueue(link)
            if item and RLT.SUI then RLT.SUI.selected = item.qid end
            RLT:ShowSession()
        end },
        { text = "Add a soft reserve for this item", notCheckable = true, func = function()
            RLT:ShowSR()
            local SUI = RLT.SUI
            SUI.srEdit = nil; SUI.srSave:SetText("Add")
            SUI.srItem:SetText(link); SUI.srPlayer:SetText(""); SUI.srPlayer:SetFocus()
        end },
        { text = "Close", notCheckable = true, func = function() end },
    })
end

local function CreateItemRow(parent, i)
    local w_ = W()
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(I_ROW_H)
    row:SetPoint("TOPLEFT", 1, -1 - (i - 1) * I_ROW_H)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local stripe = row:CreateTexture(nil, "BACKGROUND")
    stripe:SetAllPoints()
    stripe:SetTexture(1, 1, 1, (i % 2 == 0) and 0.03 or 0)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture(w_.C.accent[1], w_.C.accent[2], w_.C.accent[3], 0.12)
    local icon = row:CreateTexture(nil, "ARTWORK")
    w_.Size(icon, 18, 18)
    icon:SetPoint("LEFT", 6, 0)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local name = w_.Text(row, "GameFontHighlightSmall")
    name:SetPoint("LEFT", 30, 0); name:SetHeight(I_ROW_H); name:SetJustifyH("LEFT")
    local typ = w_.Text(row, "GameFontDisableSmall")
    typ:SetHeight(I_ROW_H); typ:SetJustifyH("LEFT")
    local ilvl = w_.Text(row, "GameFontHighlightSmall")
    ilvl:SetWidth(34); ilvl:SetHeight(I_ROW_H); ilvl:SetJustifyH("RIGHT")
    local pct = w_.Text(row, "GameFontHighlightSmall")
    pct:SetPoint("RIGHT", -8, 0); pct:SetWidth(56); pct:SetHeight(I_ROW_H); pct:SetJustifyH("RIGHT")
    ilvl:SetPoint("RIGHT", pct, "LEFT", -10, 0)
    row.icon, row.nameFS, row.typeFS, row.ilvlFS, row.pctFS = icon, name, typ, ilvl, pct

    row:SetScript("OnClick", function(self, button)
        local r = self.data
        if not r then return end
        local _, link = ItemInfo(r.id)
        if button == "RightButton" then ItemMenu(r); return end
        if IsControlKeyDown() and DressUpItemLink then DressUpItemLink(link); return end
        if IsShiftKeyDown() then ChatEdit_InsertLink(link) end
    end)
    row:SetScript("OnEnter", function(self)
        local r = self.data
        if not r then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink("item:" .. r.id)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Drop chance: " .. r.pct .. "%" .. (r.hm and "  (hard mode)" or ""), 1, 0.82, 0)
        if r.where then GameTooltip:AddLine("From: " .. r.where, 1, 1, 1) end
        local fac = select(6, ItemInfo(r.id))
        if fac == "A" then GameTooltip:AddLine("Alliance only", 0.29, 0.62, 1)
        elseif fac == "H" then GameTooltip:AddLine("Horde only", 1, 0.29, 0.29) end
        GameTooltip:AddLine("Shift-click: link   Ctrl-click: try on   Right-click: options", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function CreateBossRow(parent, i)
    local w_ = W()
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(B_ROW_H)
    row:SetPoint("TOPLEFT", 1, -1 - (i - 1) * B_ROW_H)
    row:SetPoint("RIGHT", parent, "RIGHT", -1, 0)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture(w_.C.accent[1], w_.C.accent[2], w_.C.accent[3], 0.12)
    local sel = row:CreateTexture(nil, "BACKGROUND")
    sel:SetAllPoints()
    sel:SetTexture(w_.C.accent[1], w_.C.accent[2], w_.C.accent[3], 0.22)
    sel:Hide()
    row.sel = sel
    local fs = w_.Text(row, "GameFontHighlightSmall")
    fs:SetPoint("LEFT", 8, 0); fs:SetPoint("RIGHT", -6, 0); fs:SetHeight(B_ROW_H); fs:SetJustifyH("LEFT")
    row.fs = fs
    row:SetScript("OnClick", function(self)
        if not self.index then return end
        LUI.boss = self.index
        LUI.search:SetText("")
        LUI.search:ClearFocus()
        FauxScrollFrame_SetOffset(LUI.iScroll, 0)
        LUI:Refresh()
    end)
    return row
end

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------
function LUI:Create()
    local w_ = W()
    local f = RLT.SUI.Window("RaidLootSuiteLoot", "Loot Tables", 820, 532, "none")
    self.frame = f
    f.grip = false -- resized with the main window
    local s = RLT.db.settings
    self.raid = math.min(s.lootRaid or 1, #Data().raids)
    self.mode = s.lootMode or "10"
    self.boss = 1

    -- Raid picker + mode buttons + search
    local raidBtn = w_.FlatButton(f, "", 210, 22)
    raidBtn:SetPoint("TOPLEFT", 12, -40)
    raidBtn:SetScript("OnClick", function(b)
        local menu = { { text = "Raid", isTitle = true, notCheckable = true } }
        for i, r in ipairs(Data().raids) do
            menu[#menu + 1] = { text = r.name, checked = (i == LUI.raid), func = function() LUI:SetRaid(i) end }
        end
        w_.ShowMenu(menu, b)
    end)
    self.raidBtn = raidBtn
    self.modeBtns = {}
    local prev = raidBtn
    for _, m in ipairs({ "10", "25", "10H", "25H" }) do
        local b = w_.FlatButton(f, MODE_LABEL[m], m:find("H") and 60 or 44, 22)
        b:SetPoint("LEFT", prev, "RIGHT", 4, 0)
        b:SetScript("OnClick", function() LUI:SetMode(m) end)
        self.modeBtns[m] = b
        prev = b
    end
    local search = CreateFrame("EditBox", nil, f)
    w_.Size(search, 200, 22)
    search:SetPoint("LEFT", prev, "RIGHT", 12, 0)
    w_.Backdrop(search, w_.C.panel)
    search:SetFontObject(ChatFontNormal)
    search:SetTextInsets(6, 6, 0, 0)
    search:SetAutoFocus(false)
    local ph = w_.Text(search, "GameFontDisableSmall")
    ph:SetPoint("LEFT", 6, 0)
    ph:SetText("Search this raid (item or type)")
    search:SetScript("OnEscapePressed", function(eb) eb:SetText(""); eb:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(eb) eb:ClearFocus() end)
    search:SetScript("OnTextChanged", function(eb)
        if (eb:GetText() or "") == "" then ph:Show() else ph:Hide() end
        FauxScrollFrame_SetOffset(LUI.iScroll, 0)
        LUI:Refresh()
    end)
    self.search = search

    -- Boss list (left)
    local bList = CreateFrame("Frame", nil, f)
    bList:SetPoint("TOPLEFT", 12, -70)
    bList:SetPoint("BOTTOMLEFT", 12, 30)
    bList:SetWidth(210)
    w_.Backdrop(bList, w_.C.panel)
    w_.AddPanel(bList, w_.C.panel)
    for i = 1, B_MAX do self.bossRows[i] = CreateBossRow(bList, i) end
    local bScroll = CreateFrame("ScrollFrame", "RaidLootSuiteLootBossScroll", bList, "FauxScrollFrameTemplate")
    bScroll:SetPoint("TOPLEFT", 0, -1)
    bScroll:SetPoint("BOTTOMRIGHT", -2, 1)
    bScroll:SetScript("OnVerticalScroll", function(sf, offset)
        FauxScrollFrame_OnVerticalScroll(sf, offset, B_ROW_H, function() LUI:Refresh() end)
    end)
    self.bList, self.bScroll = bList, bScroll

    -- Item list (right)
    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", bList, "TOPRIGHT", 26, 0)
    header:SetPoint("RIGHT", f, "RIGHT", -34, 0)
    header:SetHeight(20)
    w_.Backdrop(header, { 0.10, 0.10, 0.14, 1 })
    -- clickable column headers: click to sort, click again to reverse
    self.headers = {}
    local function Head(key, label, justify)
        local b = CreateFrame("Button", nil, header)
        b:SetHeight(20)
        local fs = w_.Text(b, "GameFontNormalSmall")
        fs:SetAllPoints(b)
        fs:SetJustifyH(justify)
        b.fs, b.label, b.key = fs, label, key
        b:SetScript("OnClick", function()
            if LUI.sortKey == key then
                LUI.sortDesc = not LUI.sortDesc
            else
                LUI.sortKey, LUI.sortDesc = key, SORT_DEFAULT_DESC[key] or false
            end
            LUI:Refresh()
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Sort by " .. label)
            GameTooltip:AddLine("Click again to reverse.", 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        self.headers[key] = b
        return b
    end
    local h1 = Head("name", "Item", "LEFT"); h1:SetPoint("LEFT", 9, 0); h1:SetWidth(200)
    local h2 = Head("type", "Type", "LEFT"); h2:SetWidth(150)
    local h4 = Head("pct", "Chance", "RIGHT"); h4:SetPoint("RIGHT", -10, 0); h4:SetWidth(60)
    local h3 = Head("ilvl", "iLvl", "RIGHT"); h3:SetPoint("RIGHT", h4, "LEFT", -6, 0); h3:SetWidth(44)
    self.typeHeader = h2
    self.nameHeader = h1
    local iList = CreateFrame("Frame", nil, f)
    iList:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    iList:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -34, 30)
    w_.Backdrop(iList, w_.C.panel)
    w_.AddPanel(iList, w_.C.panel)
    for i = 1, I_MAX do self.itemRows[i] = CreateItemRow(iList, i) end
    local iScroll = CreateFrame("ScrollFrame", "RaidLootSuiteLootItemScroll", iList, "FauxScrollFrameTemplate")
    iScroll:SetPoint("TOPLEFT", 0, -1)
    iScroll:SetPoint("BOTTOMRIGHT", -2, 1)
    iScroll:SetScript("OnVerticalScroll", function(sf, offset)
        FauxScrollFrame_OnVerticalScroll(sf, offset, I_ROW_H, function() LUI:Refresh() end)
    end)
    self.iList, self.iScroll = iList, iScroll
    local empty = w_.Text(iList, "GameFontDisableSmall")
    empty:SetPoint("CENTER")
    self.empty = empty

    local foot = w_.Text(f, "GameFontDisableSmall")
    foot:SetPoint("BOTTOMLEFT", 14, 10)
    foot:SetPoint("RIGHT", f, "RIGHT", -30, 0)
    foot:SetJustifyH("LEFT")
    foot:SetText("Chances from the AzerothCore database (the server can differ).  HM = hard mode,  " ..
        "|cff4a9effA|r / |cffff4a4aH|r = Alliance / Horde only.  Click a column title to sort.")
    self.foot = foot

    f:SetScript("OnSizeChanged", function() LUI:Layout() end)
    f:SetScript("OnShow", function() LUI:Layout() end)
end

function LUI:Layout()
    local f = self.frame
    local w, h = f:GetWidth() or 820, f:GetHeight() or 532
    self.bRows = math.max(1, math.min(B_MAX, math.floor((h - 70 - 30 - 2) / B_ROW_H)))
    self.iRows = math.max(1, math.min(I_MAX, math.floor((h - 92 - 30 - 2) / I_ROW_H)))
    local listW = w - 12 - 210 - 26 - 34
    self.rowW = listW - 4
    for _, row in ipairs(self.itemRows) do
        row:SetWidth(self.rowW)
        local nameW = math.floor((self.rowW - 30 - 110) * 0.55)
        row.nameFS:SetWidth(nameW)
        row.typeFS:ClearAllPoints()
        row.typeFS:SetPoint("LEFT", 30 + nameW + 8, 0)
        row.typeFS:SetWidth(self.rowW - 30 - nameW - 8 - 110)
    end
    local nameW = math.floor((self.rowW - 30 - 110) * 0.55)
    self.typeHeader:ClearAllPoints()
    self.typeHeader:SetPoint("LEFT", 30 + nameW + 9, 0)
    self.typeHeader:SetWidth(math.max(60, self.rowW - 30 - nameW - 8 - 110))
    self.nameHeader:SetWidth(nameW + 20)
    self.empty:SetWidth(listW - 40)
    self:Refresh()
end

function LUI:SetRaid(i)
    self.raid = i
    self.boss = 1
    RLT.db.settings.lootRaid = i
    local modes = Data().raids[i].modes
    local ok = false
    for _, m in ipairs(modes) do if m == self.mode then ok = true end end
    if not ok then self.mode = modes[1] end
    FauxScrollFrame_SetOffset(self.bScroll, 0)
    FauxScrollFrame_SetOffset(self.iScroll, 0)
    self:Refresh()
end

function LUI:SetMode(m)
    self.mode = m
    RLT.db.settings.lootMode = m
    self:Refresh()
end

-- rows to show: the selected boss, or search results across the raid
function LUI:BuildRows()
    local raid = Data().raids[self.raid]
    local text = strlower(strtrim(self.search:GetText() or ""))
    local rows = {}
    local function add(bi, r)
        local boss = raid.bosses[bi]
        local where
        if r.src then
            where = (r.src == 0) and "Trash mobs" or (raid.bosses[r.src] and raid.bosses[r.src].name)
        elseif text ~= "" then
            where = boss.name
        end
        rows[#rows + 1] = { id = r.id, pct = r.pct, hm = r.hm, where = where }
    end
    if text == "" then
        for _, r in ipairs(self:GetLoot(self.raid, self.boss, self.mode)) do add(self.boss, r) end
    else
        local seen = {}
        for bi, boss in ipairs(raid.bosses) do
            if not boss.patterns then
                for _, r in ipairs(self:GetLoot(self.raid, bi, self.mode)) do
                    local name, _, _, typ = ItemInfo(r.id)
                    local key = r.id .. ":" .. bi
                    if not seen[key] and (strlower(name):find(text, 1, true) or strlower(typ):find(text, 1, true)) then
                        seen[key] = true
                        add(bi, r)
                    end
                end
            end
        end
    end
    SortRows(rows, self.sortKey, self.sortDesc)
    return rows
end

function LUI:Refresh()
    local f = self.frame
    if not f or not f:IsShown() then return end
    local w_ = W()
    local raid = Data().raids[self.raid]
    self.raidBtn:SetText(raid.name)
    local avail = {}
    for _, m in ipairs(raid.modes) do avail[m] = true end
    for m, b in pairs(self.modeBtns) do
        if avail[m] then b:Show() else b:Hide() end
        b:SetBackdropColor(unpack(m == self.mode and { 0.12, 0.32, 0.42, 1 } or w_.C.button))
    end

    -- bosses
    local bRows = self.bRows or 18
    FauxScrollFrame_Update(self.bScroll, #raid.bosses, bRows, B_ROW_H)
    local boff = FauxScrollFrame_GetOffset(self.bScroll)
    for i = 1, B_MAX do
        local row = self.bossRows[i]
        local idx = boff + i
        local boss = i <= bRows and raid.bosses[idx]
        if boss then
            row.index = idx
            local special = boss.patterns or boss.name == "Trash mobs"
            row.fs:SetText((special and "|cffc77dff" or "") .. boss.name .. (special and "|r" or ""))
            if idx == self.boss then row.sel:Show() else row.sel:Hide() end
            row:Show()
        else
            row.index = nil
            row:Hide()
        end
    end

    -- column headers (the sorted one is white with an arrow)
    for key, b in pairs(self.headers) do
        if key == self.sortKey then
            b.fs:SetText("|cffffffff" .. b.label .. (self.sortDesc and " v" or " ^") .. "|r")
        else
            b.fs:SetText(b.label)
        end
    end

    -- items
    local rows = self:BuildRows()
    local iRows = self.iRows or 18
    FauxScrollFrame_Update(self.iScroll, #rows, iRows, I_ROW_H)
    local ioff = FauxScrollFrame_GetOffset(self.iScroll)
    for i = 1, I_MAX do
        local row = self.itemRows[i]
        local r = i <= iRows and rows[ioff + i] or nil
        row.data = r
        if r then
            local name, _, q, typ, ilvl, fac = ItemInfo(r.id)
            row.icon:SetTexture(RLT:GetItemIcon(r.id))
            local srs = RLT:GetSRs(r.id, name, false)
            row.nameFS:SetText(w_.QualityHex(q) .. name .. "|r" .. FactionTag(fac) .. (r.hm and " |cffff8040HM|r" or "") ..
                (#srs > 0 and (" |cffc77dffSR " .. #srs .. "|r") or ""))
            row.typeFS:SetText(typ .. (r.where and ("  |cff888888- " .. r.where .. "|r") or ""))
            row.ilvlFS:SetText(ilvl > 0 and tostring(ilvl) or "")
            row.pctFS:SetText(PctText(r.pct))
            row:Show()
        else
            row:Hide()
        end
    end
    local boss = raid.bosses[self.boss]
    if #rows == 0 then
        local t = strtrim(self.search:GetText() or "")
        self.empty:SetText(t ~= "" and "Nothing found in this raid / mode." or
            (boss and boss.note) or ("No loot listed for " .. (boss and boss.name or "?") .. " in " .. MODE_LABEL[self.mode] .. "."))
        self.empty:Show()
    else
        self.empty:Hide()
    end
end

function RLT:InitLootUI()
    if not Data() then return end
    LUI:Create()
end
