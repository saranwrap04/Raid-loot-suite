--[[
    Raid Loot Suite - Interface
    Author: Saranwrap
]]

local RLT = RaidLootSuite

local ROW_H = 20
local FRAME_W, FRAME_H = 820, 530
local MIN_W, MIN_H = 820, 400
local MAX_W, MAX_H = 1800, 1200

-- flat dark style: dark backdrop, black borders, orange accent
local C = {
    bg       = { 0.06, 0.06, 0.06, 0.92 },
    panel    = { 0.10, 0.10, 0.10, 1 },
    border   = { 0, 0, 0, 1 },
    button   = { 0.10, 0.10, 0.10, 1 },
    accent   = { 0.99, 0.48, 0.17, 1 },
    muted    = { 0.55, 0.55, 0.60 },
    danger   = { 0.90, 0.30, 0.30, 1 },
    title    = { 0.10, 0.10, 0.10, 1 },
    header   = { 0.13, 0.13, 0.13, 1 },
    sel      = { 0.45, 0.22, 0.08, 1 },
}
RLT.ACCENT = "|cfffc7a2b"


local RAID_ABBREV = {
    ["Icecrown Citadel"] = "ICC", ["Trial of the Crusader"] = "ToC",
    ["Trial of the Grand Crusader"] = "ToGC", ["Naxxramas"] = "Naxx",
    ["The Obsidian Sanctum"] = "OS", ["The Eye of Eternity"] = "EoE",
    ["Vault of Archavon"] = "VoA", ["The Ruby Sanctum"] = "RS",
    ["Onyxia's Lair"] = "Onyxia", ["Ulduar"] = "Ulduar",
}

local PERIODS = {
    { key = "all",   label = "All time" },
    { key = "today", label = "Today" },
    { key = "7",     label = "Last 7 days",  seconds = 7 * 86400 },
    { key = "30",    label = "Last 30 days", seconds = 30 * 86400 },
}

local QUALITY_NAMES = { [2] = "Uncommon", [3] = "Rare", [4] = "Epic", [5] = "Legendary" }

local UI = {
    view = {}, rows = {},
    search = "", raidFilter = nil, period = PERIODS[1],
    sortKey = "ts", sortAsc = false,
}
RLT.UI = UI

---------------------------------------------------------------------------
-- Widget helpers
---------------------------------------------------------------------------
local function Size(f, w, h) f:SetWidth(w); f:SetHeight(h) end

local function Backdrop(f, bg, border)
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    f:SetBackdropColor(unpack(bg))
    f:SetBackdropBorderColor(unpack(border or C.border))
end

local function Text(parent, font, layer)
    return parent:CreateFontString(nil, layer or "OVERLAY", font or "GameFontHighlightSmall")
end

local function FlatButton(parent, label, w, h, danger)
    local b = CreateFrame("Button", nil, parent)
    Size(b, w, h or 22)
    Backdrop(b, C.button)
    local fs = Text(b)
    fs:SetPoint("CENTER")
    b:SetFontString(fs)
    b:SetText(label)
    local hover = danger and C.danger or C.accent
    b:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(hover))
        if self.tip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.tip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(C.border))
        GameTooltip:Hide()
    end)
    b:SetScript("OnMouseDown", function(self) self:GetFontString():SetPoint("CENTER", 1, -1) end)
    b:SetScript("OnMouseUp", function(self) self:GetFontString():SetPoint("CENTER", 0, 0) end)
    return b
end

local menuFrame = CreateFrame("Frame", "RaidLootSuiteMenu", UIParent, "UIDropDownMenuTemplate")
local function ShowMenu(menu, anchor)
    if anchor then
        EasyMenu(menu, menuFrame, anchor, 0, 0, "MENU")
    else
        EasyMenu(menu, menuFrame, "cursor", 0, 0, "MENU")
    end
end

local QUALITY_HEX = {
    [0] = "|cff9d9d9d", [1] = "|cffffffff", [2] = "|cff1eff00", [3] = "|cff0070dd",
    [4] = "|cffa335ee", [5] = "|cffff8000", [6] = "|cffe6cc80", [7] = "|cffe6cc80",
}
local function QualityHex(q)
    return QUALITY_HEX[q or 1] or "|cffffffff"
end

local function ClassColored(name, class)
    if not name then return "|cff777777Pending...|r" end
    local c = class and RAID_CLASS_COLORS[class]
    if c then
        return string.format("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, name)
    end
    return name
end

local function RaidLabel(e)
    local z = RAID_ABBREV[e.zone or ""] or e.zone or "?"
    if e.diff and e.diff ~= "" then z = z .. " " .. e.diff end
    return z
end

---------------------------------------------------------------------------
-- Popups
---------------------------------------------------------------------------
local function PopupEditBox(dialog) return _G[dialog:GetName() .. "EditBox"] end

local function ApplyEdit(dialog)
    local d = dialog.data
    if not d then return end
    local e = RLT:GetEntryById(d.id)
    if not e then return end
    local value = strtrim(PopupEditBox(dialog):GetText() or "")
    RLT:MarkEdited(e)
    if d.field == "winner" then
        if value == "" then
            e.winner, e.class, e.pending = nil, nil, true
        else
            e.winner, e.pending = value, nil
            e.class = RLT:GetClassForName(value) or e.class
        end
    elseif d.field == "note" then
        e.note = (value ~= "") and value or nil
    elseif value ~= "" then
        e[d.field] = value
    end
    RLT:NotifyChanged()
end

StaticPopupDialogs["RLT_EDIT_FIELD"] = {
    text = "%s", button1 = ACCEPT, button2 = CANCEL,
    hasEditBox = 1, maxLetters = 120,
    OnAccept = function(self) ApplyEdit(self) end,
    EditBoxOnEnterPressed = function(self) ApplyEdit(self:GetParent()); self:GetParent():Hide() end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, exclusive = 1,
}

StaticPopupDialogs["RLT_CONFIRM_CLEAR"] = {
    text = "Raid Loot Suite:\nDelete ALL recorded loot? This cannot be undone.",
    button1 = YES, button2 = NO,
    OnAccept = function() RLT:ClearAll() end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, showAlert = 1,
}

-- Delete part of the history: one confirmation popup for every kind of delete
StaticPopupDialogs["RLT_CONFIRM_DELETE"] = {
    text = "Raid Loot Suite:\nDelete %s?\nThis cannot be undone.",
    button1 = YES, button2 = NO,
    OnAccept = function(self)
        local d = self.data
        if not d then return end
        local n = RLT:DeleteWhere(d.test)
        RLT:Print(string.format("Deleted %d %s (%s).", n, n == 1 and "entry" or "entries", d.what))
    end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, showAlert = 1,
}

local function ConfirmDelete(what, test)
    local n = RLT:CountWhere(test)
    if n == 0 then RLT:Print("Nothing to delete (" .. what .. ").") return end
    local label = string.format("%d %s: %s", n, n == 1 and "entry" or "entries", what)
    local dialog = StaticPopup_Show("RLT_CONFIRM_DELETE", label)
    if dialog then dialog.data = { test = test, what = what } end
end

---------------------------------------------------------------------------
-- MS / OS tag + free note
---------------------------------------------------------------------------
local SPEC_ORDER = { [""] = "MS", MS = "OS", OS = "SR", SR = "DE", DE = "" }   -- click cycle: none -> MS -> OS -> SR -> DE -> none
local SPEC_STYLE = {
    MS = { text = "|cff4cd964MS|r", bg = { 0.10, 0.28, 0.14, 1 }, border = { 0.30, 0.85, 0.40, 1 } },
    OS = { text = "|cffffa040OS|r", bg = { 0.32, 0.20, 0.06, 1 }, border = { 1.00, 0.63, 0.25, 1 } },
    SR = { text = "|cffc77dffSR|r", bg = { 0.24, 0.12, 0.32, 1 }, border = { 0.78, 0.49, 1.00, 1 } },
    DE = { text = "|cffd2a679DE|r", bg = { 0.26, 0.20, 0.12, 1 }, border = { 0.82, 0.65, 0.47, 1 } },
}

local function SetSpec(e, spec)
    if spec == "" then spec = nil end
    RLT:MarkEdited(e)
    e.spec = spec
    RLT:NotifyChanged()
end

-- how it was awarded, shown after MS / OS: LC = loot council, SR = soft reserve
local METHOD_TEXT = { LC = "|cff4fc3f7LC|r", SR = "|cffc77dffSR|r" }
local function MethodSuffix(e)
    local m = e.method
    if not m or (m == "SR" and e.spec == "SR") then return nil end   -- "SR SR" says nothing more
    return METHOD_TEXT[m]
end
local function SetMethod(e, m)
    RLT:MarkEdited(e)
    e.method = (e.method ~= m) and m or nil
    RLT:NotifyChanged()
end

local function EditField(e, field, label)
    local dialog = StaticPopup_Show("RLT_EDIT_FIELD", label)
    if dialog then
        dialog.data = { id = e.id, field = field }
        local eb = PopupEditBox(dialog)
        eb:SetText(e[field] or "")
        eb:SetFocus()
        eb:HighlightText()
    end
end

---------------------------------------------------------------------------
-- View (filter + sort)
---------------------------------------------------------------------------
local function SortCompare(a, b)
    local k = UI.sortKey
    local va, vb
    if k == "ts" then
        va, vb = a.ts or 0, b.ts or 0
    elseif k == "sync" then
        va, vb = a.noSync and 1 or 0, b.noSync and 1 or 0
    elseif k == "spec" then
        va, vb = (a.spec or "") .. " " .. (a.method or ""), (b.spec or "") .. " " .. (b.method or "")
    else
        va, vb = tostring(a[k] or ""):lower(), tostring(b[k] or ""):lower()
    end
    if va == vb then
        if UI.sortAsc then return a.id < b.id else return a.id > b.id end
    end
    if UI.sortAsc then return va < vb else return va > vb end
end

-- true when e passes the History filters (search, raid, period)
function UI:MatchesFilters(e)
    if self.raidFilter and e.zone ~= self.raidFilter then return false end
    local p = self.period
    if p.key == "today" and date("%Y-%m-%d", e.ts) ~= date("%Y-%m-%d") then return false end
    if p.seconds and time() - e.ts > p.seconds then return false end
    local q = self.search:lower()
    if q ~= "" then
        local hay = ((e.itemName or "") .. "\001" .. (e.boss or "") .. "\001" ..
                     (e.winner or "") .. "\001" .. (e.zone or "") .. "\001" ..
                     (e.spec or "") .. "\001" .. (e.method or "") .. "\001" .. (e.note or "")):lower()
        if not hay:find(q, 1, true) then return false end
    end
    return true
end

function UI:BuildView()
    local view = wipe(self.view)
    for _, e in ipairs(RLT.db.entries) do
        if self:MatchesFilters(e) then view[#view + 1] = e end
    end
    table.sort(view, SortCompare)
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
-- Columns in display order. "w" is the width at the minimum window size;
-- "grow" is the share of any extra width the column gets when the window is wider.
local COLUMNS = {
    { key = "sync",     label = "|TInterface\\Buttons\\UI-CheckBox-Check:14:14|t", w = 18, grow = 0,
      tip = "Sync: ticked drops are shared when other raid members sync. Untick a drop to keep it out of syncs." },
    { key = "ts",       label = "Date / Time", w = 108, grow = 0 },
    { key = "itemName", label = "Item",        w = 200, grow = 0.45 },
    { key = "boss",     label = "Boss",        w = 140, grow = 0.25 },
    { key = "winner",   label = "Winner",      w = 108, grow = 0.15 },
    { key = "spec",     label = "MS/OS",       w = 74,  grow = 0 },
    { key = "zone",     label = "Raid",        w = 85,  grow = 0.15 },
}
local COL_GAP, COL_START = 4, 8
local BASE_ROW_W = 768

local function ComputeColumns(rowW)
    local extra = math.max(0, rowW - BASE_ROW_W)
    local x = COL_START
    for _, col in ipairs(COLUMNS) do
        col.cw = math.floor(col.w + extra * col.grow)
        col.cx = x
        x = x + col.cw + COL_GAP
    end
end

local function Row_OnEnter(self)
    local e = self.entry
    if not e then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if e.itemLink then
        GameTooltip:SetHyperlink(e.itemLink)
    else
        GameTooltip:AddLine(e.itemName or "?", 1, 1, 1)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Boss", e.boss or "?", 0.6, 0.6, 0.6, 1, 1, 1)
    GameTooltip:AddDoubleLine("Winner", e.winner or "Pending", 0.6, 0.6, 0.6, 1, 1, 1)
    GameTooltip:AddDoubleLine("Raid", (e.zone or "?") .. " " .. (e.diff or ""), 0.6, 0.6, 0.6, 1, 1, 1)
    GameTooltip:AddDoubleLine("Date", date("%Y-%m-%d %H:%M:%S", e.ts), 0.6, 0.6, 0.6, 1, 1, 1)
    GameTooltip:AddDoubleLine("MS / OS", e.spec or "-", 0.6, 0.6, 0.6, 1, 1, 1)
    if e.method then
        GameTooltip:AddDoubleLine("Awarded by", e.method == "LC" and "Loot council" or "Soft reserve", 0.6, 0.6, 0.6, 1, 1, 1)
    end
    if e.noSync then GameTooltip:AddLine("Not shared in syncs", 1, 0.5, 0.5) end
    if e.note then
        GameTooltip:AddLine("Note: " .. e.note, 1, 0.82, 0, true)
    end
    if e.recorder then
        GameTooltip:AddDoubleLine("Recorded by", e.recorder, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
    end
    GameTooltip:AddLine("Shift-click: link  |  Ctrl-click: preview  |  Right-click: edit", 0.4, 0.75, 1)
    GameTooltip:Show()
end

local function Row_OnClick(self, button)
    local e = self.entry
    if not e then return end
    if button == "RightButton" then
        ShowMenu({
            { text = e.itemName or "Item", isTitle = true, notCheckable = true },
            { text = "Edit winner", notCheckable = true, func = function() EditField(e, "winner", "Winner for " .. (e.itemName or "item") .. ":") end },
            { text = "Edit boss", notCheckable = true, func = function() EditField(e, "boss", "Boss name:") end },
            { text = "|cff4cd964Mark as MS|r (main spec)", checked = e.spec == "MS", func = function() SetSpec(e, "MS") end },
            { text = "|cffffa040Mark as OS|r (off spec)", checked = e.spec == "OS", func = function() SetSpec(e, "OS") end },
            { text = "|cffc77dffMark as SR|r (soft reserve)", checked = e.spec == "SR", func = function() SetSpec(e, "SR") end },
            { text = "|cffd2a679Mark as DE|r (disenchanted)", checked = e.spec == "DE", func = function() SetSpec(e, "DE") end },
            { text = "Clear MS / OS", notCheckable = true, func = function() SetSpec(e, "") end },
            { text = "|cff4fc3f7Awarded by loot council|r (LC)", checked = e.method == "LC", func = function() SetMethod(e, "LC") end },
            { text = "|cffc77dffAwarded to a soft reserve|r (SR)", checked = e.method == "SR", func = function() SetMethod(e, "SR") end },
            { text = "Share in syncs", checked = not e.noSync, func = function() e.noSync = (not e.noSync) or nil; RLT:NotifyChanged() end },
            { text = e.note and "Edit note" or "Add note", notCheckable = true, func = function() EditField(e, "note", "Note for " .. (e.itemName or "item") .. ":") end },
            { text = "Link in chat", notCheckable = true, disabled = not e.itemLink, func = function() if e.itemLink then ChatEdit_InsertLink(e.itemLink) end end },
            { text = "|cffff5555Delete entry|r", notCheckable = true, func = function() RLT:DeleteEntry(e.id) end },
            { text = CANCEL, notCheckable = true, func = function() end },
        })
    elseif IsShiftKeyDown() then
        if e.itemLink then ChatEdit_InsertLink(e.itemLink) end
    elseif IsControlKeyDown() then
        if e.itemLink then DressUpItemLink(e.itemLink) end
    end
end

local function CreateRow(parent, i)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 1, -1 - (i - 1) * ROW_H)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(1, 1, 1, (i % 2 == 0) and 0.03 or 0)

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture(C.accent[1], C.accent[2], C.accent[3], 0.12)

    row.cols = {}
    for _, col in ipairs(COLUMNS) do
        if col.key == "sync" then
            -- ticked = shared when others sync (default); unticked = kept out of syncs
            local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            Size(cb, 18, 18)
            cb:SetHitRectInsets(0, 0, 0, 0)
            cb:SetScript("OnClick", function(self)
                local e = row.entry
                if not e then return end
                e.noSync = (not self:GetChecked()) or nil
                RLT:NotifyChanged()
            end)
            cb:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine("Sync")
                GameTooltip:AddLine("Ticked: this drop is shared when other raid members sync.", 1, 1, 1, true)
                GameTooltip:AddLine("Unticked: it stays only in your history.", 1, 1, 1, true)
                GameTooltip:Show()
            end)
            cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row.syncBox = cb
        elseif col.key == "spec" then
            -- clickable MS / OS tag (+ LC / SR: how it was awarded)
            local tag = CreateFrame("Button", nil, row)
            Size(tag, 56, 16)
            Backdrop(tag, C.button)
            tag:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            local tfs = Text(tag, "GameFontHighlightSmall")
            tfs:SetPoint("CENTER")
            tag.fs = tfs
            local noteIcon = Text(row, "GameFontNormalSmall")
            noteIcon:SetPoint("LEFT", tag, "RIGHT", 4, 0)
            row.noteIcon = noteIcon
            tag:SetScript("OnClick", function(_, button)
                local e = row.entry
                if not e then return end
                if button == "RightButton" then
                    EditField(e, "note", "Note for " .. (e.itemName or "item") .. ":")
                else
                    SetSpec(e, SPEC_ORDER[e.spec or ""])
                end
            end)
            tag:SetScript("OnEnter", function(self)
                local e = row.entry
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine("MS / OS")
                GameTooltip:AddLine("Left-click: none > MS > OS > SR > DE", 1, 1, 1)
                GameTooltip:AddLine("Right-click: add / edit a note", 1, 1, 1)
                GameTooltip:AddLine("LC = awarded by loot council, SR = awarded to a soft reserve", 0.7, 0.7, 0.7, true)
                if e and e.method then
                    GameTooltip:AddLine("Awarded by: " .. (e.method == "LC" and "loot council" or "soft reserve"), 1, 0.82, 0)
                end
                if e and e.note then GameTooltip:AddLine(" "); GameTooltip:AddLine("Note: " .. e.note, 1, 0.82, 0, true) end
                GameTooltip:Show()
            end)
            tag:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row.tag = tag
        else
            local fs = Text(row, "GameFontHighlightSmall")
            fs:SetJustifyH("LEFT")
            fs:SetHeight(ROW_H)
            row.cols[col.key] = fs
            if col.key == "itemName" then
                local icon = row:CreateTexture(nil, "ARTWORK")
                Size(icon, 16, 16)
                icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                row.icon = icon
            end
        end
    end
    row.cols.ts:SetTextColor(unpack(C.muted))
    row.cols.zone:SetTextColor(0.8, 0.8, 0.85)

    row:SetScript("OnEnter", Row_OnEnter)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", Row_OnClick)
    return row
end

-- Places the cells of one row according to the current column sizes.
local function LayoutRow(row, rowW)
    row:SetWidth(rowW)
    for _, col in ipairs(COLUMNS) do
        if col.key == "sync" then
            row.syncBox:ClearAllPoints()
            row.syncBox:SetPoint("LEFT", row, "LEFT", col.cx - 2, 0)
        elseif col.key == "spec" then
            row.tag:ClearAllPoints()
            row.tag:SetPoint("LEFT", row, "LEFT", col.cx, 0)
        elseif col.key == "itemName" then
            row.icon:ClearAllPoints()
            row.icon:SetPoint("LEFT", row, "LEFT", col.cx, 0)
            local fs = row.cols.itemName
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", row, "LEFT", col.cx + 21, 0)
            fs:SetWidth(col.cw - 21)
        else
            local fs = row.cols[col.key]
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", row, "LEFT", col.cx, 0)
            fs:SetWidth(col.cw)
        end
    end
end

-- Called whenever the window size changes.
function UI:Layout()
    if not self.list then return end
    local listW, listH = self.list:GetWidth(), self.list:GetHeight()
    if not listW or listW <= 0 then return end
    local rowW = math.floor(listW - 32)
    ComputeColumns(rowW)

    for _, h in ipairs(self.headers) do
        local col = h.col
        h:ClearAllPoints()
        h:SetPoint("LEFT", self.header, "LEFT", col.cx + 1, 0)
        Size(h, col.cw, 22)
    end

    self.numRows = math.max(1, math.floor((listH - 2) / ROW_H))
    for i = 1, self.numRows do
        if not self.rows[i] then self.rows[i] = CreateRow(self.rowHolder, i) end
        LayoutRow(self.rows[i], rowW)
    end
    for i = self.numRows + 1, #self.rows do self.rows[i]:Hide() end
    self:UpdateRows()
end

function UI:UpdateRows()
    if not self.numRows then return end
    local view = self.view
    FauxScrollFrame_Update(self.scroll, #view, self.numRows, ROW_H)
    local offset = FauxScrollFrame_GetOffset(self.scroll)
    for i = 1, self.numRows do
        local row = self.rows[i]
        local e = view[offset + i]
        if e then
            RLT:RefreshItemInfo(e)
            row.entry = e
            row.cols.ts:SetText(date("%Y-%m-%d %H:%M", e.ts))
            row.icon:SetTexture(RLT:GetItemIcon(e.itemID))
            row.cols.itemName:SetText(QualityHex(e.quality) .. (e.itemName or "?") .. "|r")
            row.cols.boss:SetText(e.boss or "?")
            row.cols.winner:SetText(ClassColored(e.winner, e.class))
            row.cols.zone:SetText(RaidLabel(e))
            row.syncBox:SetChecked(not e.noSync)
            local st = SPEC_STYLE[e.spec or ""]
            local suffix = MethodSuffix(e)
            if st then
                row.tag.fs:SetText(st.text .. (suffix and (" " .. suffix) or ""))
                row.tag:SetBackdropColor(unpack(st.bg))
                row.tag:SetBackdropBorderColor(unpack(st.border))
            elseif suffix then
                row.tag.fs:SetText(suffix)
                row.tag:SetBackdropColor(unpack(C.button))
                row.tag:SetBackdropBorderColor(unpack(C.border))
            else
                row.tag.fs:SetText("|cff555555--|r")
                row.tag:SetBackdropColor(unpack(C.button))
                row.tag:SetBackdropBorderColor(unpack(C.border))
            end
            row.noteIcon:SetText(e.note and "*" or "")
            row:Show()
        else
            row.entry = nil
            row:Hide()
        end
    end
    self.empty:SetShown(#view == 0 and not (self.options and self.options:IsShown()))
end

---------------------------------------------------------------------------
-- Header / toolbar
---------------------------------------------------------------------------
function UI:UpdateHeaders()
    for _, h in ipairs(self.headers) do
        local active = h.key == self.sortKey
        local label = h.label
        if active then label = label .. (self.sortAsc and "  ^" or "  v") end
        h.fs:SetText(label)
        if active then h.fs:SetTextColor(unpack(C.accent)) else h.fs:SetTextColor(0.85, 0.85, 0.9) end
    end
end

function UI:UpdateFilterButtons()
    self.raidBtn:SetText("Raid: " .. (self.raidFilter and (RAID_ABBREV[self.raidFilter] or self.raidFilter) or "All"))
    self.periodBtn:SetText("Period: " .. self.period.label)
end

function UI:Refresh()
    if not self.frame then return end
    self:BuildView()
    self:UpdateHeaders()
    self:UpdateFilterButtons()
    self:UpdateRows()
    local total = #RLT.db.entries
    if #self.view == total then
        self.status:SetText(total .. (total == 1 and " item recorded" or " items recorded"))
    else
        self.status:SetText(#self.view .. " shown  /  " .. total .. " total")
    end
    if RLT.syncText then self.status:SetText(RLT.ACCENT .. RLT.syncText .. "|r") end
end

function RLT:OnDataChanged()
    if UI.frame and UI.frame:IsShown() then UI:Refresh() end
    if UI.exportFrame and UI.exportFrame:IsShown() then UI:FillExport() end
end

local function RaidMenu()
    local seen, zones = {}, {}
    for _, e in ipairs(RLT.db.entries) do
        if e.zone and not seen[e.zone] then seen[e.zone] = true; zones[#zones + 1] = e.zone end
    end
    table.sort(zones)
    local menu = {
        { text = "Raid", isTitle = true, notCheckable = true },
        { text = "All raids", checked = UI.raidFilter == nil, func = function() UI.raidFilter = nil; UI:Refresh() end },
    }
    for _, z in ipairs(zones) do
        menu[#menu + 1] = { text = z, checked = UI.raidFilter == z, func = function() UI.raidFilter = z; UI:Refresh() end }
    end
    return menu
end

local function PeriodMenu()
    local menu = { { text = "Period", isTitle = true, notCheckable = true } }
    for _, p in ipairs(PERIODS) do
        menu[#menu + 1] = { text = p.label, checked = UI.period == p, func = function() UI.period = p; UI:Refresh() end }
    end
    return menu
end

-- "Delete..." menu: by raid, raid night, day, age, or what the filters show
local function DayOf(e) return date("%Y-%m-%d", e.ts or 0) end

local function DeleteMenu()
    local entries = RLT.db.entries
    local zones, zoneCount = {}, {}
    local nights, nightCount, nightZone, nightDiff, nightDay = {}, {}, {}, {}, {}
    local days, dayCount = {}, {}
    local pending, test = 0, 0
    for _, e in ipairs(entries) do
        local z = e.zone or "?"
        if not zoneCount[z] then zones[#zones + 1] = z end
        zoneCount[z] = (zoneCount[z] or 0) + 1

        local nk = z .. "\001" .. (e.diff or "") .. "\001" .. DayOf(e)
        if not nightCount[nk] then
            nights[#nights + 1] = nk
            nightZone[nk], nightDiff[nk], nightDay[nk] = e.zone, e.diff or "", DayOf(e)
        end
        nightCount[nk] = (nightCount[nk] or 0) + 1

        local d = DayOf(e)
        if not dayCount[d] then days[#days + 1] = d end
        dayCount[d] = (dayCount[d] or 0) + 1

        if not e.winner then pending = pending + 1 end
        if e.boss == "Test Boss" then test = test + 1 end
    end
    table.sort(zones)
    table.sort(days, function(a, b) return a > b end)
    table.sort(nights, function(a, b)
        if nightDay[a] ~= nightDay[b] then return nightDay[a] > nightDay[b] end
        return a < b
    end)

    local function Count(n) return " |cff888888(" .. n .. ")|r" end
    local MAX_ROWS = 25   -- keep the sub-menus on screen

    local byRaid = {}
    for _, z in ipairs(zones) do
        byRaid[#byRaid + 1] = { text = z .. Count(zoneCount[z]), notCheckable = true, func = function()
            CloseDropDownMenus()
            ConfirmDelete("every drop in " .. z, function(e) return (e.zone or "?") == z end)
        end }
    end

    local byNight = {}
    for i, nk in ipairs(nights) do
        if i > MAX_ROWS then break end
        local z, df, d = nightZone[nk], nightDiff[nk], nightDay[nk]
        local label = RaidLabel({ zone = z, diff = df }) .. "  " .. d
        byNight[#byNight + 1] = { text = label .. Count(nightCount[nk]), notCheckable = true, func = function()
            CloseDropDownMenus()
            ConfirmDelete(label, function(e) return e.zone == z and (e.diff or "") == df and DayOf(e) == d end)
        end }
    end

    local byDay = {}
    for i, d in ipairs(days) do
        if i > MAX_ROWS then break end
        byDay[#byDay + 1] = { text = d .. Count(dayCount[d]), notCheckable = true, func = function()
            CloseDropDownMenus()
            ConfirmDelete("every drop of " .. d, function(e) return DayOf(e) == d end)
        end }
    end

    local olderThan = {}
    for _, n in ipairs({ 7, 14, 30, 60, 90, 180, 365 }) do
        local limit = time() - n * 86400
        local c = RLT:CountWhere(function(e) return (e.ts or 0) < limit end)
        olderThan[#olderThan + 1] = { text = n .. " days" .. Count(c), notCheckable = true, disabled = c == 0, func = function()
            CloseDropDownMenus()
            ConfirmDelete("drops older than " .. n .. " days", function(e) return (e.ts or 0) < limit end)
        end }
    end

    local nDup = 0
    for _ in pairs(RLT:FindDuplicates()) do nDup = nDup + 1 end

    local shown = #UI.view
    local filtered = UI.raidFilter or UI.period.key ~= "all" or UI.search ~= ""
    local menu = {
        { text = "Delete", isTitle = true, notCheckable = true },
        { text = "What the filters show" .. Count(shown), notCheckable = true, disabled = not filtered or shown == 0,
          tooltipTitle = "What the filters show", tooltipText = "Every row now in the list (search, Raid and Period filters).",
          tooltipOnButton = 1, func = function()
            CloseDropDownMenus()
            ConfirmDelete("the rows shown with the current filters", function(e) return UI:MatchesFilters(e) end)
        end },
        { text = "By raid", notCheckable = true, hasArrow = #byRaid > 0, disabled = #byRaid == 0, menuList = byRaid },
        { text = "By raid night", notCheckable = true, hasArrow = #byNight > 0, disabled = #byNight == 0, menuList = byNight },
        { text = "By day", notCheckable = true, hasArrow = #byDay > 0, disabled = #byDay == 0, menuList = byDay },
        { text = "Older than", notCheckable = true, hasArrow = true, menuList = olderThan },
        { text = "Duplicates" .. Count(nDup), notCheckable = true, disabled = nDup == 0,
          tooltipTitle = "Duplicates", tooltipText = "The same drop recorded twice (same item, same winner or first winner, within 15 minutes). The copy changed last is kept.",
          tooltipOnButton = 1, func = function()
            CloseDropDownMenus()
            local dup = RLT:FindDuplicates()
            ConfirmDelete("duplicate copies of a drop", function(e) return dup[e] end)
        end },
        { text = "Pending (no winner)" .. Count(pending), notCheckable = true, disabled = pending == 0, func = function()
            CloseDropDownMenus()
            ConfirmDelete("pending drops (no winner)", function(e) return not e.winner end)
        end },
        { text = "Test mode entries" .. Count(test), notCheckable = true, disabled = test == 0, func = function()
            CloseDropDownMenus()
            ConfirmDelete("test mode entries", function(e) return e.boss == "Test Boss" end)
        end },
        { text = "|cffff5555Everything|r" .. Count(#entries), notCheckable = true, disabled = #entries == 0, func = function()
            CloseDropDownMenus()
            StaticPopup_Show("RLT_CONFIRM_CLEAR")
        end },
    }
    return menu
end

function UI:ShowDeleteMenu()
    ShowMenu(DeleteMenu(), self.deleteBtn)
end

---------------------------------------------------------------------------
-- Options panel
---------------------------------------------------------------------------
local function CheckBox(parent, name, label, desc, y, getter, setter)
    local cb = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    Size(cb, 24, 24)
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, y)
    _G[name .. "Text"]:SetText(label)
    _G[name .. "Text"]:SetFontObject("GameFontHighlight")
    local d = Text(parent, "GameFontDisableSmall")
    d:SetPoint("TOPLEFT", cb, "BOTTOMLEFT", 28, 4)
    d:SetWidth(350)           -- stays left of the right column; long text wraps
    d:SetJustifyH("LEFT")
    d:SetText(desc)
    cb:SetScript("OnShow", function(self) self:SetChecked(getter()) end)
    cb:SetScript("OnClick", function(self) setter(self:GetChecked() and true or false) end)
    return cb
end

function UI:CreateOptions(parent)
    -- No background of its own: it sits on the list panel, whose rows are hidden while it is open.
    local o = CreateFrame("Frame", nil, parent)
    o:SetAllPoints(self.list)
    o:SetFrameLevel(self.list:GetFrameLevel() + 10)
    o:EnableMouse(true)
    o:Hide()

    local title = Text(o, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 20, -16)
    title:SetText("History & window")
    title:SetTextColor(unpack(C.accent))

    local s = RLT.db.settings

    -- Left column
    local qLabel = Text(o, "GameFontHighlight")
    qLabel:SetPoint("TOPLEFT", 24, -56)
    qLabel:SetText("Minimum item quality:")
    local qBtn = FlatButton(o, "", 130, 22)
    qBtn:SetPoint("LEFT", qLabel, "RIGHT", 12, 0)
    local function UpdateQ()
        qBtn:SetText(QualityHex(s.minQuality) .. (QUALITY_NAMES[s.minQuality] or "?") .. "|r")
    end
    qBtn:SetScript("OnShow", UpdateQ)
    qBtn:SetScript("OnClick", function(self)
        local menu = { { text = "Minimum quality", isTitle = true, notCheckable = true } }
        for q = 2, 5 do
            menu[#menu + 1] = {
                text = QualityHex(q) .. QUALITY_NAMES[q] .. "|r", checked = s.minQuality == q,
                func = function() s.minQuality = q; UpdateQ() end,
            }
        end
        ShowMenu(menu, self)
    end)

    CheckBox(o, "RLTOptRaidOnly", "Only record inside raid instances",
        "Ignore loot in dungeons and the open world.", -90,
        function() return s.onlyInRaid end, function(v) s.onlyInRaid = v end)
    CheckBox(o, "RLTOptTrash", "Record trash drops",
        "Items that cannot be tied to a boss are saved with the boss name \"Trash\".", -135,
        function() return s.trackTrash end, function(v) s.trackTrash = v end)
    CheckBox(o, "RLTOptAnnounce", "Chat message when loot is recorded",
        "Prints \"[Item] -> Player (Boss)\" in your chat frame (only you see it).", -180,
        function() return s.announce end, function(v) s.announce = v end)
    CheckBox(o, "RLTOptMinimap", "Show minimap button",
        "Drag the button to move it around the minimap.", -225,
        function() return not s.minimap.hide end,
        function(v) s.minimap.hide = not v; RLT:UpdateMinimapButton() end)
    CheckBox(o, "RLTOptAutoSync", "Auto sync (after a login / reload, or when you join a raid)",
        "Fills in drops you missed while disconnected. The Sync button in the History always works.", -270,
        function() return s.autoSync end, function(v) s.autoSync = v end)

    -- Right column: opacity slider
    local slider = CreateFrame("Slider", "RLTOptOpacity", o, "OptionsSliderTemplate")
    Size(slider, 240, 17)
    slider:SetPoint("TOPLEFT", o, "TOPLEFT", 440, -72)
    slider:SetMinMaxValues(0.2, 1)
    slider:SetValueStep(0.05)
    _G["RLTOptOpacityLow"]:SetText("20%")
    _G["RLTOptOpacityHigh"]:SetText("100%")
    local sliderText = _G["RLTOptOpacityText"]
    sliderText:SetFontObject("GameFontHighlight")
    local function UpdateSliderText()
        sliderText:SetText(string.format("Window opacity: %d%%", math.floor(s.opacity * 100 + 0.5)))
    end
    slider:SetScript("OnShow", function(self) self:SetValue(s.opacity); UpdateSliderText() end)
    slider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value * 20 + 0.5) / 20 -- snap to 5%
        if value < 0.2 then value = 0.2 elseif value > 1 then value = 1 end
        s.opacity = value
        UpdateSliderText()
        UI:ApplyOpacity()
    end)
    local sDesc = Text(o, "GameFontDisableSmall")
    sDesc:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -16)
    sDesc:SetText("Background transparency. Text and icons stay fully visible.")

    local info = Text(o, "GameFontDisableSmall")
    info:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -50)
    info:SetWidth(300)
    info:SetJustifyH("LEFT")
    info:SetText("Drag the bottom-right corner of the window to resize it.\n\n" ..
                 "Your history is saved in\nWTF\\Account\\<ACCOUNT>\\SavedVariables\\RaidLootSuite.lua\n" ..
                 "It is written when you log out or /reload.\n\nRaid Loot Suite v" .. RLT.VERSION .. " by " .. RLT.AUTHOR .. ".")

    -- Links: icon + the URL in a read-only box (click it, Ctrl+A, Ctrl+C)
    local linkLabel = Text(o, "GameFontNormal")
    linkLabel:SetPoint("TOPLEFT", info, "BOTTOMLEFT", 0, -18)
    linkLabel:SetText("Links (click a box, Ctrl+A then Ctrl+C to copy)")
    local function LinkBox(anchor, url, icon)
        local lead = o:CreateTexture(nil, "ARTWORK")
        Size(lead, 16, 16)
        lead:SetTexture(RLT.MEDIA .. icon)
        lead:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10)
        local box = CreateFrame("EditBox", nil, o)
        box:SetPoint("LEFT", lead, "RIGHT", 8, 0)
        Size(box, 300, 16)
        box:SetFontObject(GameFontHighlightSmall)
        box:SetAutoFocus(false)
        box:SetText(url)
        box:SetCursorPosition(0)
        box:SetScript("OnTextChanged", function(self, userInput) if userInput then self:SetText(url) end end)
        box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        return lead
    end
    local gh = LinkBox(linkLabel, "https://github.com/saranwrap04/Raid-loot-suite", "github")
    LinkBox(gh, "https://warperia.com/addon-wotlk/raid-loot-suite/", "warperia")

    self.options = o
end

function UI:SetOptionsShown(show)
    if show then
        self.options:Show()
        self.rowHolder:Hide()
        self.scroll:Hide()
        self.empty:Hide()
    else
        self.options:Hide()
        self.rowHolder:Show()
        self.scroll:Show()
        self:UpdateRows()
    end
    if self.optionsBtn then self.optionsBtn:SetText(show and "Back to list" or "Settings") end
end

-- Applies the opacity setting to every window background.
function UI:ApplyOpacity()
    local a = RLT.db.settings.opacity or 0.95
    for _, p in ipairs(self.panels or {}) do
        local f, col = p[1], p[2]
        if f.SetBackdropColor then
            f:SetBackdropColor(col[1], col[2], col[3], (col[4] or 1) * a)
        end
    end
    if self.titleBg then self.titleBg:SetTexture(C.title[1], C.title[2], C.title[3], a) end
end

local function AddPanel(f, col)
    UI.panels = UI.panels or {}
    UI.panels[#UI.panels + 1] = { f, col }
end

---------------------------------------------------------------------------
-- Main window
---------------------------------------------------------------------------
function UI:Create()
    local s = RLT.db.settings
    local f = CreateFrame("Frame", "RaidLootSuiteFrame", UIParent)
    Size(f, math.max(MIN_W, s.window.w or FRAME_W), math.max(MIN_H, s.window.h or FRAME_H))
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:SetResizable(true)
    f:SetMinResize(MIN_W, MIN_H)
    f:SetMaxResize(MAX_W, MAX_H)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    Backdrop(f, C.bg)
    AddPanel(f, C.bg)
    f:Hide()
    tinsert(UISpecialFrames, "RaidLootSuiteFrame")
    self.frame = f

    -- Title bar
    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    bar:SetHeight(30)
    local barBg = bar:CreateTexture(nil, "BACKGROUND")
    barBg:SetAllPoints()
    barBg:SetTexture(unpack(C.title))
    self.titleBg = barBg
    local line = bar:CreateTexture(nil, "BORDER")
    line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT"); line:SetHeight(1)
    line:SetTexture(C.accent[1], C.accent[2], C.accent[3], 0.6)

    local icon = bar:CreateTexture(nil, "ARTWORK")
    Size(icon, 24, 24)
    icon:SetPoint("LEFT", 6, 0)
    icon:SetTexture(RLT.MEDIA .. "logo")

    local title = Text(bar, "GameFontNormalLarge")
    title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    title:SetText("Raid Loot Suite")
    title:SetTextColor(1, 1, 1)
    local by = Text(bar, "GameFontDisableSmall")
    by:SetPoint("LEFT", title, "RIGHT", 8, -1)
    by:SetText("by " .. RLT.AUTHOR .. "  -  v" .. RLT.VERSION)

    local close = FlatButton(bar, "X", 22, 20, true)
    close:SetPoint("RIGHT", -6, 0)
    close:SetScript("OnClick", function() f:Hide() end)
    f.bar = bar

    -- Toolbar
    local search = CreateFrame("EditBox", nil, f)
    Size(search, 230, 22)
    search:SetPoint("TOPLEFT", 10, -40)
    Backdrop(search, C.panel)
    AddPanel(search, C.panel)
    search:SetFontObject(ChatFontNormal)
    search:SetTextInsets(8, 8, 0, 0)
    search:SetAutoFocus(false)
    local ph = Text(search, "GameFontDisableSmall")
    ph:SetPoint("LEFT", 8, 0)
    ph:SetText("Search item, boss, player, note...")
    search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(unpack(C.accent)) end)
    search:SetScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(unpack(C.border)) end)
    search:SetScript("OnTextChanged", function(self)
        local t = self:GetText() or ""
        if t == "" then ph:Show() else ph:Hide() end
        UI.search = t
        UI:Refresh()
    end)

    self.raidBtn = FlatButton(f, "Raid: All", 170, 22)
    self.raidBtn:SetPoint("LEFT", search, "RIGHT", 8, 0)
    self.raidBtn:SetScript("OnClick", function(b) ShowMenu(RaidMenu(), b) end)

    self.periodBtn = FlatButton(f, "Period: All time", 150, 22)
    self.periodBtn:SetPoint("LEFT", self.raidBtn, "RIGHT", 8, 0)
    self.periodBtn:SetScript("OnClick", function(b) ShowMenu(PeriodMenu(), b) end)

    local reset = FlatButton(f, "Reset filters", 100, 22)
    reset:SetPoint("LEFT", self.periodBtn, "RIGHT", 8, 0)
    reset:SetScript("OnClick", function()
        UI.raidFilter, UI.period = nil, PERIODS[1]
        search:SetText("")
        search:ClearFocus()
        UI:Refresh()
    end)

    -- Column headers
    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", 10, -70)
    header:SetPoint("TOPRIGHT", -10, -70)
    header:SetHeight(22)
    local headerCol = C.header
    Backdrop(header, headerCol)
    AddPanel(header, headerCol)
    self.header = header
    self.headers = {}
    for _, col in ipairs(COLUMNS) do
        local h = CreateFrame("Button", nil, header)
        Size(h, col.w, 22)
        local fs = Text(h, "GameFontNormalSmall")
        fs:SetPoint("LEFT")
        h.fs, h.key, h.label, h.col = fs, col.key, col.label, col
        if col.tip then
            h:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(col.tip, 1, 1, 1, 1, true)
                GameTooltip:Show()
            end)
            h:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        h:SetScript("OnClick", function()
            if UI.sortKey == col.key then
                UI.sortAsc = not UI.sortAsc
            else
                UI.sortKey = col.key
                UI.sortAsc = col.key ~= "ts"
            end
            UI:Refresh()
        end)
        self.headers[#self.headers + 1] = h
    end

    -- List (fills the space between header and footer)
    local list = CreateFrame("Frame", nil, f)
    list:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    list:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 44)
    Backdrop(list, C.panel)
    AddPanel(list, C.panel)
    self.list = list

    local holder = CreateFrame("Frame", nil, list)
    holder:SetAllPoints(list)
    self.rowHolder = holder

    local scroll = CreateFrame("ScrollFrame", "RaidLootSuiteScroll", list, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -1)
    scroll:SetPoint("BOTTOMRIGHT", -26, 1)
    scroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, function() UI:UpdateRows() end)
    end)
    self.scroll = scroll

    local empty = Text(list, "GameFontDisable")
    empty:SetPoint("CENTER")
    empty:SetText("No loot to show yet.\nKill a raid boss, import a list, or type /rls testentry to add a sample entry.")
    empty.SetShown = function(self, show) if show then self:Show() else self:Hide() end end
    self.empty = empty

    -- Footer
    local export = FlatButton(f, "Export", 90, 24)
    export:SetPoint("BOTTOMLEFT", 10, 10)
    export.tip = "Export the rows currently shown (CSV for Excel / Google Sheets, plain text, or Discord)."
    export:SetScript("OnClick", function() RLT:ShowExport() end)

    local import = FlatButton(f, "Import", 90, 24)
    import:SetPoint("LEFT", export, "RIGHT", 8, 0)
    import.tip = "Paste rows from Excel / Google Sheets, a CSV file, or a text / Discord export."
    import:SetScript("OnClick", function() RLT:ShowImport() end)


    local clear = FlatButton(f, "Delete...", 110, 24, true)
    clear:SetPoint("BOTTOMRIGHT", -24, 10)
    clear.tip = "Delete part of the history: by raid, raid night, day or age, the rows the filters show, pending or test entries, or everything."
    clear:SetScript("OnClick", function() UI:ShowDeleteMenu() end)
    self.deleteBtn = clear

    self.status = Text(f, "GameFontDisableSmall")
    local sync = FlatButton(f, "Sync", 80, 24)
    sync:SetPoint("LEFT", import, "RIGHT", 8, 0)
    sync.tip = "Get the loot other raid members recorded (last 7 days), so drops you missed while disconnected or too far away are filled in. They need Raid Loot Suite too."
    sync:SetScript("OnClick", function() RLT:StartSync() end)
    self.syncBtn = sync
    self.status:SetPoint("LEFT", sync, "RIGHT", 14, 0)

    -- Resize grip (bottom-right corner)
    local grip = CreateFrame("Button", nil, f)
    f.grip = grip
    Size(grip, 16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel(f:GetFrameLevel() + 20)
    grip.dots = {}
    -- three-step staircase of small squares
    for i, p in ipairs({ { 0, 0 }, { 5, 0 }, { 10, 0 }, { 5, 5 }, { 10, 5 }, { 10, 10 } }) do
        local d = grip:CreateTexture(nil, "OVERLAY")
        Size(d, 3, 3)
        d:SetPoint("BOTTOMLEFT", grip, "BOTTOMLEFT", p[1] + 1, p[2] + 1)
        d:SetTexture(0.55, 0.55, 0.6, 0.9)
        grip.dots[i] = d
    end
    local function TintGrip(r, g, b) for _, d in ipairs(grip.dots) do d:SetTexture(r, g, b, 0.9) end end
    grip:SetScript("OnEnter", function() TintGrip(C.accent[1], C.accent[2], C.accent[3]) end)
    grip:SetScript("OnLeave", function() TintGrip(0.55, 0.55, 0.6) end)
    grip:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then f:StartSizing("BOTTOMRIGHT") end
    end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        s.window.w, s.window.h = math.floor(f:GetWidth() + 0.5), math.floor(f:GetHeight() + 0.5)
        UI:Layout()
    end)

    self:CreateOptions(f)

    f:SetScript("OnSizeChanged", function() UI:Layout() end)
    f:SetScript("OnShow", function() UI:Layout(); UI:Refresh() end)
    self:ApplyOpacity()
end

---------------------------------------------------------------------------
-- Export window
---------------------------------------------------------------------------
function UI:FillExport()
    local text, n = RLT:BuildExport(self.frame and self.view or RLT.db.entries, self.exportFormat)
    self.exportBox:SetText(text)
    self.exportBox:HighlightText()
    self.exportBox:SetCursorPosition(0)
    self.exportInfo:SetText(n .. " entries  -  click in the box, press Ctrl+C, then paste into Excel, Google Sheets or Discord.")
    for fmt, b in pairs(self.formatBtns) do
        if fmt == self.exportFormat then b:SetBackdropColor(unpack(C.sel)) else b:SetBackdropColor(unpack(C.button)) end
    end
end

function UI:CreateExport()
    local f = CreateFrame("Frame", "RaidLootSuiteExport", UIParent)
    Size(f, 660, 440)
    f:SetPoint("CENTER", 0, 20)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    Backdrop(f, C.bg)
    AddPanel(f, C.bg)
    f:Hide()
    tinsert(UISpecialFrames, "RaidLootSuiteExport")
    self.exportFrame = f
    self.exportFormat = "csv"

    local title = Text(f, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("Export loot")
    title:SetTextColor(1, 1, 1)

    local close = FlatButton(f, "X", 22, 20, true)
    close:SetPoint("TOPRIGHT", -6, -6)
    close:SetScript("OnClick", function() f:Hide() end)

    self.formatBtns = {}
    local prev
    for _, fmt in ipairs({ { "csv", "CSV (Excel)" }, { "text", "Plain text" }, { "discord", "Discord" } }) do
        local b = FlatButton(f, fmt[2], 110, 22)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 6, 0) else b:SetPoint("TOPLEFT", 12, -38) end
        b:SetScript("OnClick", function() UI.exportFormat = fmt[1]; UI:FillExport() end)
        self.formatBtns[fmt[1]] = b
        prev = b
    end

    local selectAll = FlatButton(f, "Select all", 100, 22)
    selectAll:SetPoint("TOPRIGHT", -12, -38)
    selectAll:SetScript("OnClick", function() UI.exportBox:SetFocus(); UI.exportBox:HighlightText() end)

    local box = CreateFrame("Frame", nil, f)
    box:SetPoint("TOPLEFT", 12, -68)
    box:SetPoint("BOTTOMRIGHT", -12, 34)
    Backdrop(box, C.panel)
    AddPanel(box, C.panel)

    local scroll = CreateFrame("ScrollFrame", "RaidLootSuiteExportScroll", box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)

    local eb = CreateFrame("EditBox", nil, scroll)
    eb:SetMultiLine(true)
    eb:SetMaxLetters(0)
    eb:SetAutoFocus(false)
    eb:SetFontObject(ChatFontNormal)
    Size(eb, 590, 320)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); f:Hide() end)
    eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    if ScrollingEdit_OnCursorChanged then
        eb:SetScript("OnCursorChanged", ScrollingEdit_OnCursorChanged)
        eb:SetScript("OnUpdate", function(self, elapsed) ScrollingEdit_OnUpdate(self, elapsed, scroll) end)
    end
    scroll:SetScrollChild(eb)
    self.exportBox = eb

    self.exportInfo = Text(f, "GameFontDisableSmall")
    self.exportInfo:SetPoint("BOTTOMLEFT", 14, 13)

    f:SetScript("OnShow", function() UI:FillExport() end)
end

---------------------------------------------------------------------------
-- Import window
---------------------------------------------------------------------------
function UI:CreateImport()
    local f = CreateFrame("Frame", "RaidLootSuiteImport", UIParent)
    Size(f, 660, 460)
    f:SetPoint("CENTER", 0, 20)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    Backdrop(f, C.bg)
    AddPanel(f, C.bg)
    f:Hide()
    tinsert(UISpecialFrames, "RaidLootSuiteImport")
    self.importFrame = f

    local title = Text(f, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("Import loot")
    title:SetTextColor(1, 1, 1)

    local close = FlatButton(f, "X", 22, 20, true)
    close:SetPoint("TOPRIGHT", -6, -6)
    close:SetScript("OnClick", function() f:Hide() end)

    local help = Text(f, "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", 12, -36)
    help:SetWidth(636)
    help:SetJustifyH("LEFT")
    help:SetText("Paste below with " .. RLT.ACCENT .. "Ctrl+V|r, then click Import. Accepted:\n" ..
        "|cff888888-|r Cells copied from Excel / Google Sheets (keep the header row: Date, Time, Raid, Boss, Item, Winner, MS/OS, Note...)\n" ..
        "|cff888888-|r CSV content (comma or semicolon), or this addon's Plain text / Discord export\n" ..
        "|cff888888-|r Simple lines:  |cffccccccItem -> Player|r   or   |cffccccccBoss | Item -> Player MS|r\n" ..
        "Rows that are already in your history (same day, item, winner and boss) are skipped.")

    local box = CreateFrame("Frame", nil, f)
    box:SetPoint("TOPLEFT", 12, -110)
    box:SetPoint("BOTTOMRIGHT", -12, 44)
    Backdrop(box, C.panel)
    AddPanel(box, C.panel)

    local scroll = CreateFrame("ScrollFrame", "RaidLootSuiteImportScroll", box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)

    local eb = CreateFrame("EditBox", nil, scroll)
    eb:SetMultiLine(true)
    eb:SetMaxLetters(0)
    eb:SetAutoFocus(false)
    eb:SetFontObject(ChatFontNormal)
    Size(eb, 590, 280)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    if ScrollingEdit_OnCursorChanged then
        eb:SetScript("OnCursorChanged", ScrollingEdit_OnCursorChanged)
        eb:SetScript("OnUpdate", function(self, elapsed) ScrollingEdit_OnUpdate(self, elapsed, scroll) end)
    end
    scroll:SetScrollChild(eb)
    self.importBox = eb

    -- clicking anywhere in the box focuses the edit box
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function() eb:SetFocus() end)

    local result = Text(f, "GameFontHighlightSmall")
    result:SetPoint("BOTTOMLEFT", 14, 17)
    result:SetWidth(380)
    result:SetJustifyH("LEFT")
    self.importResult = result

    local doImport = FlatButton(f, "Import", 100, 24)
    doImport:SetPoint("BOTTOMRIGHT", -12, 10)
    doImport:SetScript("OnClick", function()
        local added, dupes, failed, fmt = RLT:ImportText(eb:GetText())
        if fmt == "empty" then
            result:SetText("|cffff7070Nothing to import - paste your rows in the box first.|r")
            return
        end
        local msg = string.format("|cff4cd964%d added|r   |cffaaaaaa%d already present|r", added, dupes)
        if failed > 0 then msg = msg .. string.format("   |cffff7070%d unreadable|r", failed) end
        result:SetText(msg .. "   |cff666666(" .. fmt .. ")|r")
        if added > 0 then
            RLT:Print(string.format("Imported %d entries (%s).", added, fmt))
            eb:SetText("")
        end
    end)

    local clearBtn = FlatButton(f, "Clear", 80, 24)
    clearBtn:SetPoint("RIGHT", doImport, "LEFT", -8, 0)
    clearBtn:SetScript("OnClick", function() eb:SetText(""); result:SetText(""); eb:SetFocus() end)

    f:SetScript("OnShow", function() result:SetText(""); eb:SetFocus() end)
end

---------------------------------------------------------------------------
-- Minimap button
---------------------------------------------------------------------------
local function PositionMinimapButton(b)
    local angle = math.rad(RLT.db.settings.minimap.angle or 215)
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * 80, math.sin(angle) * 80)
end

function UI:CreateMinimapButton()
    local b = CreateFrame("Button", "RaidLootSuiteMinimapButton", Minimap)
    Size(b, 31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- dark round background + Raid Loot Suite logo (textures\minimap.tga, 64x64 with transparency)
    local background = b:CreateTexture(nil, "BACKGROUND")
    Size(background, 20, 20)
    background:SetPoint("TOPLEFT", 7, -5)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    local icon = b:CreateTexture(nil, "ARTWORK")
    Size(icon, 21, 21)
    icon:SetPoint("TOPLEFT", 6, -5)
    icon:SetTexture(RLT.MEDIA .. "minimap")

    local border = b:CreateTexture(nil, "OVERLAY")
    Size(border, 53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            ShowMenu({
                { text = "Raid Loot Suite", isTitle = true, notCheckable = true },
                { text = "Loot History", notCheckable = true, func = function() RLT:ShowUI() end },
                { text = "Loot Session", notCheckable = true, func = function() RLT:ShowSession() end },
                { text = "Soft Reserves", notCheckable = true, func = function() RLT:ShowSR() end },
                { text = "Loot Council members", notCheckable = true, func = function() RLT:ShowCouncil() end },
                { text = "Settings", notCheckable = true, func = function() RLT:ShowOptions() end },
                { text = RLT.testMode and "Stop test mode" or "Test mode", notCheckable = true, func = function() RLT:ToggleTest() end },
                { text = "Close", notCheckable = true, func = function() end },
            })
        elseif IsShiftKeyDown() then
            RLT:ToggleUI()
        else
            if RLT.ToggleMain then RLT:ToggleMain() elseif RLT.ToggleUI then RLT:ToggleUI() end
        end
    end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function(s)
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            px, py = px / scale, py / scale
            RLT.db.settings.minimap.angle = math.deg(math.atan2(py - my, px - mx))
            PositionMinimapButton(s)
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Raid Loot Suite")
        GameTooltip:AddLine(#RLT.db.entries .. " items recorded", 1, 1, 1)
        if RLT.db.queue then
            local waiting = 0
            for _, q in ipairs(RLT.db.queue) do if not RLT.FINISHED_STATUS[q.status] then waiting = waiting + 1 end end
            GameTooltip:AddLine(waiting .. " in the loot queue, " .. #RLT.db.softres .. " soft reserves", 1, 1, 1)
        end
        if RLT.testMode then GameTooltip:AddLine("Test mode is on", 1, 0.82, 0) end
        GameTooltip:AddLine("Left-click: open / close", 0.6, 0.6, 0.6)
        GameTooltip:AddLine("Shift-click: loot history", 0.6, 0.6, 0.6)
        GameTooltip:AddLine("Right-click: menu (soft reserves, settings, test mode)", 0.6, 0.6, 0.6)
        GameTooltip:AddLine("Drag: move", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.minimapBtn = b
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------
function RLT:InitUI()
    UI:Create()
    UI:CreateExport()
    UI:CreateImport()
    UI:CreateMinimapButton()
    UI:ApplyOpacity()
    self:UpdateMinimapButton()
end

function RLT:UpdateMinimapButton()
    local b = UI.minimapBtn
    if not b then return end
    if self.db.settings.minimap.hide then
        b:Hide()
    else
        PositionMinimapButton(b)
        b:Show()
    end
end

function RLT:ShowExport()
    if not UI.frame:IsShown() then UI:BuildView() end
    UI.exportFrame:Show()
    UI:FillExport()
end

function RLT:ShowImport()
    UI.importFrame:Show()
end

-- Shared widgets for the loot session windows (SessionUI.lua)
RLT.W = {
    C = C, Size = Size, Backdrop = Backdrop, Text = Text, FlatButton = FlatButton,
    ShowMenu = ShowMenu, QualityHex = QualityHex, ClassColored = ClassColored,
    AddPanel = AddPanel, RaidLabel = RaidLabel, UI = UI,
}
