--[[
    Raid Loot Suite - Main window
    Author: Saranwrap

    One window with tabs: Loot Session, Soft Reserves, Loot Council, History,
    plus Settings (title bar). The tab pages are the session / soft reserve /
    council / history frames, placed inside this window.
]]

local RLT = RaidLootSuite
local Main = { pages = {}, tabs = {} }
RLT.Main = Main

local MAIN_W, MAIN_H = 820, 560          -- default (and minimum) size
local MAIN_MAX_W, MAIN_MAX_H = 1400, 1000
local BAR_H, TAB_Y = 30, -34             -- title bar height, tab row position
local PAGE_TOP = -28                     -- pages keep their own 30px header space, hidden behind the tabs

local TABS = {
    { key = "session", label = "Loot Session" },
    { key = "sr",      label = "Soft Reserves" },
    { key = "council", label = "Loot Council" },
    { key = "history", label = "History" },
    { key = "loot",    label = "Loot Tables" },
}

local function W() return RLT.W end

local function RemoveSpecial(name)
    for i = #UISpecialFrames, 1, -1 do
        if UISpecialFrames[i] == name then table.remove(UISpecialFrames, i) end
    end
end

-- Puts a stand-alone window inside the main window as a tab page
local function Embed(shell, page, key)
    local name = page:GetName()
    if name then RemoveSpecial(name) end
    page:SetParent(shell)
    page:ClearAllPoints()
    page:SetPoint("TOPLEFT", shell, "TOPLEFT", 0, PAGE_TOP)
    page:SetPoint("BOTTOMRIGHT", shell, "BOTTOMRIGHT", 0, 0)
    page:SetMovable(false)
    page:EnableMouse(false)
    page:SetScript("OnDragStart", nil)
    page:SetScript("OnDragStop", nil)
    page:SetBackdrop(nil)
    if page.bar then page.bar:Hide() end
    if page.grip then page.grip:Hide() end
    page:Hide()
    Main.pages[key] = page
end

function Main:Create()
    local w_ = W()
    local C = w_.C
    local f = CreateFrame("Frame", "RaidLootSuiteMain", UIParent)
    w_.Size(f, MAIN_W, MAIN_H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    w_.Backdrop(f, C.bg)
    w_.AddPanel(f, C.bg)
    f:Hide()
    tinsert(UISpecialFrames, "RaidLootSuiteMain")
    self.frame = f

    -- Title bar: name, version, author | ? | Settings | X
    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    bar:SetHeight(BAR_H)
    bar:SetFrameLevel(f:GetFrameLevel() + 40)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(unpack(C.title))
    w_.UI.titleBg = bg -- follows the opacity setting
    local line = bar:CreateTexture(nil, "BORDER")
    line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT"); line:SetHeight(1)
    line:SetTexture(C.accent[1], C.accent[2], C.accent[3], 0.6)
    local icon = bar:CreateTexture(nil, "ARTWORK")
    w_.Size(icon, 24, 24)
    icon:SetPoint("LEFT", 6, 0)
    icon:SetTexture(RLT.MEDIA .. "logo")
    w_.Size(icon, 22, 22)
    local title = w_.Text(bar, "GameFontNormalLarge")
    title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    title:SetText(RLT.NAME)
    title:SetTextColor(1, 1, 1)
    local by = w_.Text(bar, "GameFontDisableSmall")
    by:SetPoint("LEFT", title, "RIGHT", 8, -1)
    by:SetText("v" .. RLT.VERSION .. "  -  by " .. RLT.AUTHOR)
    self.byText = by

    local close = w_.FlatButton(bar, "X", 22, 20, true)
    close:SetPoint("RIGHT", -6, 0)
    close:SetScript("OnClick", function() f:Hide() end)
    local settings = w_.FlatButton(bar, "Settings", 90, 20)
    settings:SetPoint("RIGHT", close, "LEFT", -6, 0)
    settings.tip = "Loot session settings, history and window settings."
    settings:SetScript("OnClick", function()
        if Main.current == "settings" then RLT:ShowTab(Main.lastPage or "session") else RLT:ShowTab("settings") end
    end)
    self.settingsBtn = settings
    self.bar = bar

    -- Tabs
    local prev
    for _, t in ipairs(TABS) do
        local b = w_.FlatButton(f, t.label, 120, 24)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", 10, TAB_Y) end
        b:SetFrameLevel(f:GetFrameLevel() + 40)
        b:SetScript("OnClick", function() RLT:ShowTab(t.key) end)
        self.tabs[t.key] = b
        prev = b
    end

    -- Settings page: side bar of categories (Options.lua), under the tab row
    local sp = CreateFrame("Frame", nil, f)
    sp:SetPoint("TOPLEFT", 0, TAB_Y - 26)
    sp:SetPoint("BOTTOMRIGHT", 0, 0)
    sp:SetFrameLevel(f:GetFrameLevel() + 30)
    sp:EnableMouse(true)
    sp:Hide()
    self.settingsPage = sp

    RLT.SUI.MakeResizable(f, "main", MAIN_W, MAIN_H, MAIN_MAX_W, MAIN_MAX_H, function() end)
    f.grip:SetFrameLevel(f:GetFrameLevel() + 60)
end

function Main:EmbedPages()
    local f, SUI, UI = self.frame, RLT.SUI, W().UI
    Embed(f, SUI.frame, "session")
    Embed(f, SUI.srFrame, "sr")
    Embed(f, SUI.councilFrame, "council")
    Embed(f, UI.frame, "history")
    if RLT.LUI and RLT.LUI.frame then Embed(f, RLT.LUI.frame, "loot") end

    -- the test mode banner and the "?" help button move to the main title bar
    SUI.subtitle:SetParent(self.bar)
    SUI.subtitle:ClearAllPoints()
    SUI.subtitle:SetPoint("LEFT", self.byText, "RIGHT", 14, 0)
    SUI.helpBtn:SetParent(self.bar)
    SUI.helpBtn:ClearAllPoints()
    SUI.helpBtn:SetPoint("RIGHT", self.settingsBtn, "LEFT", -6, 0)

    -- settings: one page with a side bar of categories
    self.settings = RLT.Options:Build(self.settingsPage)
end

function Main:ShowSettingsPage(which)
    which = which or self.settingsWhich
    self.settingsWhich = which
    self.settings:Show(which or self.settings.current or self.settings.first)
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------
-- key: "session", "sr", "council", "history" or "settings" (sub: "session" / "history")
function RLT:ShowTab(key, sub)
    local f = Main.frame
    if not f then return end
    local C = W().C
    key = key or Main.lastPage or "session"
    if key ~= "settings" and not Main.pages[key] then key = "session" end
    f:Show()
    for k, page in pairs(Main.pages) do
        if k ~= key then page:Hide() end
    end
    if key == "settings" then
        Main.settingsPage:Show()
        Main:ShowSettingsPage(sub)
    else
        Main.settingsPage:Hide()
        Main.pages[key]:Show()
        Main.lastPage = key
        self.db.settings.lastTab = key
    end
    Main.current = key
    for k, b in pairs(Main.tabs) do b:SetSelected(k == key) end
    Main.settingsBtn:SetText(key == "settings" and "Back" or "Settings")
    Main.settingsBtn:SetSelected(key == "settings")
end

local function Toggle(key)
    local f = Main.frame
    if not f then return end
    if f:IsShown() and Main.current == key then f:Hide() else RLT:ShowTab(key) end
end

function RLT:ToggleMain()
    if Main.frame:IsShown() then Main.frame:Hide() else self:ShowTab(self.db.settings.lastTab or "session") end
end
function RLT:ShowSession()   self:ShowTab("session") end
function RLT:ToggleSession() Toggle("session") end
function RLT:ShowSR()        self:ShowTab("sr") end
function RLT:ToggleSR()      Toggle("sr") end
function RLT:ShowCouncil()   self:ShowTab("council") end
function RLT:ToggleCouncil() Toggle("council") end
function RLT:ShowUI()        self:ShowTab("history") end
function RLT:ToggleUI()      Toggle("history") end
function RLT:ShowLootTables() self:ShowTab("loot") end
function RLT:ShowOptions()   self:ShowTab("settings") end

function RLT:InitMain()
    Main:Create()
    Main:EmbedPages()
    W().UI:ApplyOpacity()
end
