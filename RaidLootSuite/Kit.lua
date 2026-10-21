--[[
    Raid Loot Suite - flat widgets: colours, buttons, check boxes, sliders, drop-downs,
    menus, section titles and the settings page with its side bar
    Author: Saranwrap
]]

local NS = RaidLootSuite
local K = {}
NS.Kit = K

local WHITE8 = "Interface\\Buttons\\WHITE8X8"
local ARROW = "Interface\\ChatFrame\\ChatFrameExpandArrow"

K.C = {
    bg     = { 0.06, 0.06, 0.06, 0.92 },
    panel  = { 0.10, 0.10, 0.10, 1 },
    input  = { 0.04, 0.04, 0.04, 1 },
    border = { 0, 0, 0, 1 },
    button = { 0.10, 0.10, 0.10, 1 },
    accent = { 1, 0.82, 0, 1 },
    sel    = { 0.24, 0.20, 0.06, 1 },
    rule   = { 0.45, 0.45, 0.45, 0.6 },
    danger = { 0.90, 0.30, 0.30, 1 },
}
local C = K.C
K.ACCENT = "|cffffd100"

function K.Backdrop(f, bg, border)
    f:SetBackdrop({ bgFile = WHITE8, edgeFile = WHITE8, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    f:SetBackdropColor(unpack(bg or C.panel))
    f:SetBackdropBorderColor(unpack(border or C.border))
end
local Backdrop = K.Backdrop

function K.Tip(frame, text, title)
    if not text then return end
    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if title then
            GameTooltip:AddLine(title, 1, 1, 1)
            GameTooltip:AddLine(text, 0.8, 0.8, 0.8, true)
        else
            GameTooltip:SetText(text, 1, 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Gold(fs) fs:SetTextColor(C.accent[1], C.accent[2], C.accent[3]) end
K.Gold = Gold

-- flat button: gold text, the selected one lighter with white text
function K.Button(parent, label, w, h, danger)
    local b = CreateFrame("Button", nil, parent)
    b:SetWidth(w); b:SetHeight(h or 22)
    Backdrop(b, C.button)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("CENTER")
    Gold(fs)
    b:SetFontString(fs)
    b:SetText(label)
    b:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(unpack(danger and C.danger or C.accent)) end)
    b:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack(C.border)) end)
    function b:SetSelected(on)
        self:SetBackdropColor(unpack(on and C.sel or C.button))
        if on then fs:SetTextColor(1, 1, 1) else Gold(fs) end
    end
    return b
end

-- gold down arrow on the right of a button that opens a menu
function K.Arrow(b)
    local fs = b:GetFontString()
    if fs then
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", 8, 0)
        fs:SetPoint("RIGHT", -20, 0)
        fs:SetJustifyH("LEFT")
    end
    local a = b:CreateTexture(nil, "OVERLAY")
    a:SetWidth(12); a:SetHeight(12)
    a:SetPoint("RIGHT", -5, 0)
    a:SetTexture(ARROW)
    a:SetTexCoord(0, 1, 1, 1, 0, 0, 1, 0)      -- turned to point down
    a:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
    b.arrow = a
    return a
end

-- a game check box (UICheckButtonTemplate) in the flat look: dark square, gold fill
function K.SkinCheck(cb)
    local name = cb:GetName()
    for _, t in ipairs({ cb:GetNormalTexture(), cb:GetPushedTexture(), cb:GetHighlightTexture(), cb:GetDisabledCheckedTexture() }) do
        if t then t:SetTexture(nil) end
    end
    cb:SetWidth(16); cb:SetHeight(16)
    Backdrop(cb, C.input)
    local fill = cb:CreateTexture(nil, "OVERLAY")
    fill:SetTexture(WHITE8)
    fill:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
    fill:SetPoint("TOPLEFT", 2, -2); fill:SetPoint("BOTTOMRIGHT", -2, 2)
    cb:SetCheckedTexture(fill)
    local text = name and _G[name .. "Text"]
    if text then
        text:ClearAllPoints()
        text:SetPoint("LEFT", cb, "RIGHT", 8, 0)
    end
    cb:HookScript("OnEnter", function(self) self:SetBackdropBorderColor(unpack(C.accent)) end)
    cb:HookScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack(C.border)) end)
    return cb
end

-- a game slider (OptionsSliderTemplate) in the flat look
function K.SkinSlider(s)
    local name = s:GetName()
    s:SetBackdrop(nil)
    Backdrop(s, C.input)
    s:SetHeight(10)
    local th = s:CreateTexture(nil, "OVERLAY")
    th:SetTexture(WHITE8)
    th:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
    th:SetWidth(10); th:SetHeight(12)
    s:SetThumbTexture(th)
    if name then
        local t, lo, hi = _G[name .. "Text"], _G[name .. "Low"], _G[name .. "High"]
        if t then t:SetFontObject("GameFontNormal"); Gold(t); t:ClearAllPoints(); t:SetPoint("BOTTOM", s, "TOP", 0, 5) end
        if lo then lo:SetFontObject("GameFontHighlightSmall"); lo:ClearAllPoints(); lo:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 2, -5) end
        if hi then hi:SetFontObject("GameFontHighlightSmall"); hi:ClearAllPoints(); hi:SetPoint("TOPRIGHT", s, "BOTTOMRIGHT", -2, -5) end
    end
    return s
end

---------------------------------------------------------------------------
-- Menus: { text, isTitle, notCheckable, checked, disabled, func, keepShownOnClick,
--          hasArrow + menuList (a sub-menu), tooltipTitle, tooltipText }
---------------------------------------------------------------------------
local levels, catcher = {}, nil
local ROW = 20

local function CloseFrom(level)
    for i = level, #levels do if levels[i] then levels[i]:Hide() end end
end
function K.CloseMenus() CloseFrom(1) end

local function Level(n)
    if levels[n] then return levels[n] end
    if not catcher then
        catcher = CreateFrame("Button", nil, UIParent)
        catcher:SetAllPoints(UIParent)
        catcher:SetFrameStrata("FULLSCREEN")
        catcher:RegisterForClicks("AnyUp")
        catcher:Hide()
        catcher:SetScript("OnClick", function() CloseFrom(1) end)
    end
    local m = CreateFrame("Frame", (n == 1) and (tostring(NS.MENU_NAME or "FlatMenu") .. "1") or nil, UIParent)
    m:SetFrameStrata("FULLSCREEN_DIALOG")
    m:SetFrameLevel(10 + n * 5)
    m:SetClampedToScreen(true)
    m:EnableMouse(true)
    Backdrop(m, C.panel)
    m:Hide()
    m.rows = {}
    m.level = n
    m:SetScript("OnHide", function(self)
        CloseFrom(self.level + 1)
        if self.level == 1 then catcher:Hide(); K.menuAnchor = nil end
    end)
    if n == 1 and m:GetName() then tinsert(UISpecialFrames, m:GetName()) end
    levels[n] = m
    return m
end

local Open
local function Fill(m, list)
    local width = 140
    for i, e in ipairs(list) do
        local r = m.rows[i]
        if not r then
            r = CreateFrame("Button", nil, m)
            r:SetHeight(ROW)
            r:SetPoint("TOPLEFT", 2, -2 - (i - 1) * ROW)
            r:SetPoint("RIGHT", -2, 0)
            r.hl = r:CreateTexture(nil, "HIGHLIGHT")
            r.hl:SetAllPoints()
            r.hl:SetTexture(WHITE8)
            r.hl:SetGradientAlpha("HORIZONTAL", C.accent[1], C.accent[2], C.accent[3], 0.45, C.accent[1], C.accent[2], C.accent[3], 0)
            r.box = CreateFrame("Frame", nil, r)
            r.box:SetWidth(12); r.box:SetHeight(12)
            r.box:SetPoint("LEFT", 6, 0)
            Backdrop(r.box, C.input)
            r.fill = r.box:CreateTexture(nil, "OVERLAY")
            r.fill:SetTexture(WHITE8)
            r.fill:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
            r.fill:SetPoint("TOPLEFT", 2, -2); r.fill:SetPoint("BOTTOMRIGHT", -2, 2)
            r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            r.text:SetJustifyH("LEFT")
            r.sub = r:CreateTexture(nil, "OVERLAY")
            r.sub:SetWidth(10); r.sub:SetHeight(10)
            r.sub:SetPoint("RIGHT", -4, 0)
            r.sub:SetTexture(ARROW)
            r.sub:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
            m.rows[i] = r
        end
        local check = not (e.notCheckable or e.isTitle)
        r.text:ClearAllPoints()
        r.text:SetPoint("LEFT", check and 24 or 8, 0)
        r.text:SetText(e.text or "")
        if e.isTitle then
            r.text:SetFontObject("GameFontNormalSmall"); Gold(r.text)
        elseif e.disabled then
            r.text:SetFontObject("GameFontHighlight"); r.text:SetTextColor(0.45, 0.45, 0.45)
        else
            r.text:SetFontObject("GameFontHighlight"); r.text:SetTextColor(1, 1, 1)
        end
        r:EnableMouse(not e.isTitle)
        if e.isTitle or e.disabled then r.hl:Hide() else r.hl:Show() end
        if check then r.box:Show(); if e.checked then r.fill:Show() else r.fill:Hide() end else r.box:Hide() end
        if e.hasArrow and e.menuList and not e.disabled then r.sub:Show() else r.sub:Hide() end
        r:SetScript("OnEnter", function(self)
            CloseFrom(m.level + 1)
            if e.hasArrow and e.menuList and not e.disabled then Open(e.menuList, self, m.level + 1) end
            if e.tooltipTitle or e.tooltipText then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if e.tooltipTitle then GameTooltip:AddLine(e.tooltipTitle, 1, 1, 1) end
                if e.tooltipText then GameTooltip:AddLine(e.tooltipText, 0.8, 0.8, 0.8, true) end
                GameTooltip:Show()
            end
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r:SetScript("OnClick", function()
            if e.disabled or e.isTitle then return end
            if e.hasArrow and e.menuList and not e.func then return end
            if e.func then e.func(r, e.arg1, e.arg2) end
            if e.keepShownOnClick then
                if check then e.checked = not e.checked; if e.checked then r.fill:Show() else r.fill:Hide() end end
            else
                CloseFrom(1)
            end
        end)
        r:Show()
        width = math.max(width, r.text:GetStringWidth() + (check and 36 or 20) + (e.hasArrow and 14 or 0))
    end
    for i = #list + 1, #m.rows do m.rows[i]:Hide() end
    m:SetWidth(width)
    m:SetHeight(#list * ROW + 4)
end

Open = function(list, anchor, level)
    local m = Level(level)
    Fill(m, list)
    m:ClearAllPoints()
    if level > 1 then
        m:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 2, 2)
    elseif anchor and anchor ~= "cursor" and anchor.GetBottom then
        local bottom = (anchor:GetBottom() or 0) * anchor:GetEffectiveScale() / UIParent:GetEffectiveScale()
        if bottom < m:GetHeight() + 10 then m:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 2)
        else m:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2) end
    else
        local x, y = GetCursorPosition()
        local s = UIParent:GetEffectiveScale()
        m:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s, y / s)
    end
    m:Show()
end

-- a second click on the same button closes the menu
function K.ShowMenu(list, anchor)
    local m = Level(1)
    if m:IsShown() and K.menuAnchor == (anchor or "cursor") then CloseFrom(1) return end
    CloseFrom(1)
    Open(list, anchor, 1)
    catcher:Show()
    K.menuAnchor = anchor or "cursor"
end

---------------------------------------------------------------------------
-- Controls of the settings page (each has .refresh)
---------------------------------------------------------------------------
function K.Check(parent, label, get, set, tip, desc)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(20)
    local box = CreateFrame("Frame", nil, b)
    box:SetWidth(16); box:SetHeight(16)
    box:SetPoint("LEFT", 0, 0)
    Backdrop(box, C.input)
    local fill = box:CreateTexture(nil, "OVERLAY")
    fill:SetTexture(WHITE8)
    fill:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
    fill:SetPoint("TOPLEFT", 2, -2); fill:SetPoint("BOTTOMRIGHT", -2, 2)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", box, "RIGHT", 8, 0)
    fs:SetJustifyH("LEFT")
    fs:SetText(label)
    b:SetWidth(24 + fs:GetStringWidth() + 4)
    if desc then
        local d = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        d:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -3)
        d:SetWidth(210)
        d:SetJustifyH("LEFT")
        d:SetText(desc)
        b.desc = d
    end
    b.refresh = function()
        if get() then fill:Show() else fill:Hide() end
        local on = b.enabledFunc == nil or b.enabledFunc()
        b.on = on
        fs:SetTextColor(on and 1 or 0.5, on and 1 or 0.5, on and 1 or 0.5)
    end
    b:SetScript("OnClick", function()
        if b.on == false then return end
        set(not get())
        if b.changed then b.changed() end
    end)
    b:SetScript("OnEnter", function() box:SetBackdropBorderColor(unpack(C.accent)) end)
    b:SetScript("OnLeave", function() box:SetBackdropBorderColor(unpack(C.border)) end)
    K.Tip(b, tip)
    return b
end

local sliderN = 0
function K.Slider(parent, label, w, lo, hi, step, get, set, fmt)
    sliderN = sliderN + 1
    fmt = fmt or function(v) return tostring(v) end
    local f = CreateFrame("Frame", nil, parent)
    f:SetWidth(w); f:SetHeight(50)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, 0)
    title:SetText(label)
    Gold(title)
    local s = CreateFrame("Slider", tostring(NS.MENU_NAME or "Flat") .. "Slider" .. sliderN, f)
    s:SetOrientation("HORIZONTAL")
    s:SetHeight(10)
    s:SetPoint("TOPLEFT", 0, -16); s:SetPoint("TOPRIGHT", 0, -16)
    Backdrop(s, C.input)
    local th = s:CreateTexture(nil, "OVERLAY")
    th:SetTexture(WHITE8)
    th:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
    th:SetWidth(10); th:SetHeight(12)
    s:SetThumbTexture(th)
    s:SetMinMaxValues(lo, hi)
    s:SetValueStep(step)
    local lof = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lof:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 2, -6); lof:SetText(fmt(lo))
    local hif = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hif:SetPoint("TOPRIGHT", s, "BOTTOMRIGHT", -2, -6); hif:SetText(fmt(hi))
    local box = CreateFrame("EditBox", nil, f)
    box:SetWidth(70); box:SetHeight(18)
    box:SetPoint("TOP", s, "BOTTOM", 0, -3)
    box:SetAutoFocus(false)
    box:SetFontObject("GameFontHighlightSmall")
    box:SetJustifyH("CENTER")
    Backdrop(box, C.input)
    local function round(v) return math.floor(v / step + 0.5) * step end
    local function show(v) box:SetText(fmt(v)) end
    f.refresh = function()
        f.busy = true
        local v = get() or lo
        s:SetValue(v); show(v)
        f.busy = nil
    end
    local function apply(v)
        v = round(math.max(lo, math.min(hi, v)))
        set(v); show(v)
        if f.changed then f.changed() end
    end
    s:SetScript("OnValueChanged", function(_, v) if not f.busy then apply(v) end end)
    s:EnableMouseWheel(true)
    s:SetScript("OnMouseWheel", function(self, d) self:SetValue(self:GetValue() + d * step) end)
    box:SetScript("OnEnterPressed", function(self)
        local t = (self:GetText() or ""):gsub("[%%s]", "")
        local v = tonumber(t)
        if v then
            if fmt(1):find("%%") and hi <= 2 and v > hi then v = v / 100 end
            f.busy = true; s:SetValue(round(math.max(lo, math.min(hi, v)))); f.busy = nil
            apply(v)
        end
        self:ClearFocus()
    end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus(); f.refresh() end)
    box:SetScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(unpack(C.accent)); self:HighlightText() end)
    box:SetScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(unpack(C.border)) end)
    return f
end

-- drop-down: gold label above, dark box with the choice on the right and a gold arrow
function K.Dropdown(parent, w, getOptions, get, set, label)
    local b = CreateFrame("Button", nil, parent)
    b:SetWidth(w); b:SetHeight(22)
    Backdrop(b, C.input)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", 8, 0); fs:SetPoint("RIGHT", -26, 0)
    fs:SetJustifyH("RIGHT")
    b:SetFontString(fs)
    local ab = CreateFrame("Frame", nil, b)
    ab:SetWidth(20); ab:SetHeight(20)
    ab:SetPoint("RIGHT", -1, 0)
    Backdrop(ab, C.button)
    local a = ab:CreateTexture(nil, "OVERLAY")
    a:SetWidth(14); a:SetHeight(14)
    a:SetPoint("CENTER")
    a:SetTexture(ARROW)
    a:SetTexCoord(0, 1, 1, 1, 0, 0, 1, 0)
    a:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
    if label then
        local t = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        t:SetPoint("BOTTOMLEFT", b, "TOPLEFT", 2, 3)
        t:SetText(label)
        Gold(t)
    end
    b.refresh = function()
        for _, o in ipairs(getOptions()) do if o[1] == get() then b:SetText(o[2]) return end end
        b:SetText("")
    end
    b:SetScript("OnClick", function(self)
        local list = {}
        for _, o in ipairs(getOptions()) do
            list[#list + 1] = { text = o[2], checked = o[1] == get(),
                func = function() set(o[1]); b.refresh(); if b.changed then b.changed() end end }
        end
        K.ShowMenu(list, self)
    end)
    b:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(unpack(C.accent)) end)
    b:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack(C.border)) end)
    b:SetScript("OnHide", function() if K.menuAnchor == b then K.CloseMenus() end end)
    return b
end

function K.Section(parent, text, w)
    local f = CreateFrame("Frame", nil, parent)
    f:SetWidth(w); f:SetHeight(16)
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("CENTER")
    fs:SetText(text)
    Gold(fs)
    for _, side in ipairs({ "LEFT", "RIGHT" }) do
        local l = f:CreateTexture(nil, "ARTWORK")
        l:SetHeight(1)
        l:SetTexture(C.rule[1], C.rule[2], C.rule[3], C.rule[4])
        if side == "LEFT" then l:SetPoint("LEFT"); l:SetPoint("RIGHT", fs, "LEFT", -8, 0)
        else l:SetPoint("RIGHT"); l:SetPoint("LEFT", fs, "RIGHT", 8, 0) end
    end
    f.text = fs
    return f
end

function K.SideButton(parent, label, w)
    local b = CreateFrame("Button", nil, parent)
    b:SetWidth(w); b:SetHeight(22)
    local glow = b:CreateTexture(nil, "BACKGROUND")
    glow:SetAllPoints()
    glow:SetTexture(WHITE8)
    glow:SetGradientAlpha("HORIZONTAL", C.accent[1], C.accent[2], C.accent[3], 0.55, C.accent[1], C.accent[2], C.accent[3], 0)
    glow:Hide()
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture(WHITE8)
    hl:SetGradientAlpha("HORIZONTAL", 1, 1, 1, 0.12, 1, 1, 1, 0)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("LEFT", 10, 0)
    b:SetFontString(fs)
    b:SetText(label)
    function b:SetSelected(on)
        if on then glow:Show(); fs:SetTextColor(1, 1, 1) else glow:Hide(); Gold(fs) end
    end
    b:SetSelected(false)
    return b
end

---------------------------------------------------------------------------
-- Settings page: side bar of categories, a page per category in two columns
-- cats: { { group = "Name" }, { key, label, title, help, build = function(page) end }, ... }
---------------------------------------------------------------------------
function K.Settings(parent, cats, version)
    local S = { pages = {}, side = {}, controls = {} }
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT", 8, -8)
    bar:SetPoint("BOTTOMLEFT", 8, 8)
    bar:SetWidth(176)
    Backdrop(bar, C.panel)
    local content = CreateFrame("Frame", nil, parent)
    content:SetPoint("TOPLEFT", bar, "TOPRIGHT", 6, 0)
    content:SetPoint("BOTTOMRIGHT", -8, 8)
    Backdrop(content, C.panel)
    S.bar, S.content = bar, content

    function S:Refresh()
        for _, c in ipairs(self.controls) do c.refresh() end
        if self.onRefresh then self.onRefresh() end
    end
    function S:Show(key)
        if not self.pages[key] then key = self.first end
        self.current = key
        for k, p in pairs(self.pages) do if k == key then p:Show() else p:Hide() end end
        for k, b in pairs(self.side) do b:SetSelected(k == key) end
        self:Refresh()
    end

    local y = -8
    for _, cat in ipairs(cats) do
        if cat.group then
            local g = bar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            g:SetPoint("TOPLEFT", 10, y - 6)
            g:SetText(string.upper(cat.group))
            y = y - 22
        else
            local key = cat[1]
            local b = K.SideButton(bar, cat[2], 172)
            b:SetPoint("TOPLEFT", 2, y)
            b:SetScript("OnClick", function() S:Show(key) end)
            S.side[key] = b
            y = y - 22
            S.first = S.first or key
            local p = CreateFrame("Frame", nil, content)
            p:SetAllPoints()
            p:Hide()
            S.pages[key] = p
            local t = K.Section(p, cat[3], 10)
            t:SetPoint("TOPLEFT", 10, -10); t:SetPoint("TOPRIGHT", -10, -10)
            local h = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            h:SetPoint("TOPLEFT", 16, -32); h:SetPoint("RIGHT", p, "RIGHT", -16, 0)
            h:SetJustifyH("LEFT")
            h:SetText(cat[4] or "")
            -- two columns, each with its own y
            local Y = { -62, -62 }
            local function place(w, col, h2)
                col = col or 1
                w:SetPoint("TOPLEFT", p, "TOPLEFT", col == 2 and 0 or 16, Y[col])
                if col == 2 then w.col2 = true; w:ClearAllPoints(); w:SetPoint("TOPLEFT", p, "TOP", 8, Y[col]) end
                Y[col] = Y[col] - h2
                return w
            end
            local function track(c) c.changed = c.changed or function() S:Refresh(); if S.onChange then S.onChange() end end; S.controls[#S.controls + 1] = c; return c end
            p.Check = function(_, col, label, get, set, tip, desc, enabledFunc)
                local c = track(K.Check(p, label, get, set, tip, desc))
                c.enabledFunc = enabledFunc
                return place(c, col, desc and 46 or 26)
            end
            p.Slider = function(_, col, label, lo, hi, step, get, set, fmt)
                Y[col or 1] = Y[col or 1] - 2
                return place(track(K.Slider(p, label, 210, lo, hi, step, get, set, fmt)), col, 58)
            end
            p.Dropdown = function(_, col, label, opts, get, set, tip)
                Y[col or 1] = Y[col or 1] - 16
                local d = track(K.Dropdown(p, 210, type(opts) == "function" and opts or function() return opts end, get, set, label))
                K.Tip(d, tip)
                return place(d, col, 34)
            end
            p.Button = function(_, col, label, onClick, tip, w)
                local b2 = K.Button(p, label, w or 210, 22)
                b2:SetScript("OnClick", onClick)
                K.Tip(b2, tip)
                return place(b2, col, 28)
            end
            p.Section = function(_, col, text)
                Y[col or 1] = Y[col or 1] - 6
                local s2 = K.Section(p, text, 10)
                place(s2, col, 28)
                if s2.col2 then s2:SetPoint("RIGHT", p, "RIGHT", -16, 0) else s2:SetPoint("RIGHT", p, "CENTER", -8, 0) end
                s2.wide = function() s2:SetPoint("RIGHT", p, "RIGHT", -16, 0) end
                return s2
            end
            p.Text = function(_, col, text, h2, font)
                local t2 = p:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
                t2:SetJustifyH("LEFT")
                t2:SetText(text)
                place(t2, col, h2 or 20)
                -- a width of its own (two anchors do not make a 3.3.5 font string wrap): half the page, or all of it
                p.texts = p.texts or {}
                p.texts[#p.texts + 1] = t2
                t2.wide = function() t2.isWide = true; p.Fit() end
                p.Fit()
                return t2
            end
            p.Fit = function()
                local w = p:GetWidth()
                if not w or w < 100 then w = 600 end
                for _, t3 in ipairs(p.texts or {}) do
                    t3:SetWidth(math.floor(t3.isWide and (w - 32) or (w / 2 - 24)))
                end
            end
            p:SetScript("OnSizeChanged", function() p.Fit() end)
            p:HookScript("OnShow", function() p.Fit() end)
            p.Skip = function(_, col, h2) Y[col or 1] = Y[col or 1] - h2 end
            p.Y = function(_, col) return Y[col or 1] end
            p.Track = function(_, c) return track(c) end
            if cat.build then cat.build(p) end
        end
    end
    if version then
        local v = bar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        v:SetPoint("BOTTOMLEFT", 10, 8)
        v:SetText(version)
    end
    return S
end
