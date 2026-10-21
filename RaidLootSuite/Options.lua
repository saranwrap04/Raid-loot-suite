--[[
    Raid Loot Suite - Settings page (title bar > Settings)
    Author: Saranwrap

    Side bar of categories on the left, the options of the chosen one on the right.
]]

local RLT = RaidLootSuite
local Options = {}
RLT.Options = Options

local CHANNELS = { { "RAID_WARNING", "Raid Warning" }, { "RAID", "Raid chat" }, { "NONE", "Off (only me)" } }
local QUALITY = { { 2, "|cff1eff00Uncommon|r" }, { 3, "|cff0070ddRare|r" }, { 4, "|cffa335eeEpic|r" }, { 5, "|cffff8000Legendary|r" } }
local OLD_KEYS = { session = "rolls" }     -- older names of the categories

local function S() return RLT.db.settings end
local function opt(key) return function() return S()[key] end, function(v) S()[key] = v end end
local function pct(v) return math.floor(v * 100 + 0.5) .. "%" end

function Options:Build(parent)
    local K = RLT.Kit
    local A = K.ACCENT
    local cats = {
        { group = "Loot session" },
        { "rolls", "Rolls", "Rolls", "How long rolls stay open, and what players roll.", build = function(p)
            p:Section(1, "Rolls")
            p:Slider(1, "Roll timer", RLT.ROLL_TIME_MIN, RLT.ROLL_TIME_MAX, 1,
                function() return S().rollTime end, function(v) RLT:SetRollTime(v) end,
                function(v) return v .. " s" end)
            p:Check(1, "Count down 5, 4, 3, 2, 1 at the end of a roll", opt("countdown"))
            p:Text(1, "|cff4cd964MS = /roll 100|r     |cffffa040OS = /roll 99|r     |cffc77dffSR = /roll 100|r", 24)
            p:Section(2, "Soft reserves")
            p:Dropdown(2, "Soft reserves per player", { { 1, "1" }, { 2, "2" }, { 3, "3" } }, opt("srPerPlayer"))
            p:Check(2, "Players can whisper me \"sr [item]\"", opt("whisperSR"))
            p:Section(2, "Try it")
            local tb = p:Button(2, "Test mode", function() RLT:ToggleTest() end,
                "Try rolls, soft reserves and council alone: fake raiders answer, nothing is sent to chat. " ..
                "Awards go in the history as \"Test Boss\". (/rls test)")
            RLT.SUI.testBtn = tb
            p:Text(1, "An item soft reserved by players in the raid is rolled among those players only " ..
                "(one SR'er = they win). Otherwise MS beats OS, the highest roll wins, ties reroll by themselves.", 60,
                "GameFontDisableSmall")
        end },
        { "chat", "Announcements", "Announcements", "Where the loot session posts in chat.", build = function(p)
            p:Section(1, "Channels")
            p:Dropdown(1, "Roll start", CHANNELS, opt("announceStart"))
            p:Dropdown(1, "Winners", CHANNELS, opt("announceResult"))
            p:Dropdown(1, "Countdown (5, 4, 3, 2, 1)", CHANNELS, opt("announceCountdown"))
            p:Section(2, "Boss loot")
            p:Check(2, "Post the boss loot in raid chat", opt("announceDrops"),
                "When you loot the boss as master looter.")
        end },
        { "ml", "Master looter", "Master looter", "What happens when you are the master looter.", build = function(p)
            p:Section(1, "Queue and award")
            p:Check(1, "Add boss loot to the queue", opt("autoQueue"), "When you are master looter and open the boss's loot.")
            p:Check(1, "Give the item with Master Loot when it's awarded", opt("autoAward"))
            p:Section(2, "Disenchanter")
            local box = RLT.SUI.EditBox(p, 160, "Player name")
            p:Skip(2, 4)
            box:SetPoint("TOPLEFT", p, "TOP", 8, p:Y(2))
            p:Skip(2, 30)
            box:SetScript("OnTextChanged", function(self)
                S().disenchanter = strtrim(self:GetText() or "")
                if S().disenchanter == "" then self.placeholder:Show() else self.placeholder:Hide() end
            end)
            box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
            box.refresh = function() if not box:HasFocus() then box:SetText(S().disenchanter or "") end end
            p:Track(box)
            local tgt = K.Button(p, "Use target", 74, 22)
            tgt:SetPoint("LEFT", box, "RIGHT", 6, 0)
            K.Tip(tgt, "Set your current target as the disenchanter.")
            tgt:SetScript("OnClick", function()
                if UnitExists("target") and UnitIsPlayer("target") then box:SetText(UnitName("target")) end
            end)
            p:Check(2, "Nobody rolls: give it to the disenchanter", opt("autoDisenchant"))
        end },
        { "council", "Loot council", "Loot council", "Who votes, and how raiders answer.", build = function(p)
            p:Section(1, "Members")
            p:Button(1, "Choose council members", function() RLT:ShowCouncil() end,
                "Pick who can vote in a council: tick raid members, or add a name. You are always on it.")
            local sum = p:Text(1, "", 60)
            RLT.SUI.councilSummary = sum
            p:Section(2, "Answers")
            p:Check(2, "Players can whisper me MS / OS / pass", opt("whisperResponses"))
            local help = p:Text(1, "Raiders answer with the popup (if they have Raid Loot Suite) or by whispering you " ..
                "MS / OS / pass. Council members need Raid Loot Suite to see the candidates and vote; you award.", 60,
                "GameFontDisableSmall")
            help.wide()
        end },
        { group = "History" },
        { "history", "Recording", "Recording", "What the loot history records.", build = function(p)
            p:Section(1, "Loot")
            p:Dropdown(1, "Minimum item quality", QUALITY, opt("minQuality"))
            p:Check(1, "Only record inside raid instances", opt("onlyInRaid"), "Ignore loot in dungeons and the open world.")
            p:Check(1, "Record trash drops", opt("trackTrash"), "Saved with the boss name \"Trash\".")
            p:Section(2, "Chat and sync")
            p:Check(2, "Chat message when loot is recorded", opt("announce"),
                "Prints \"[Item] -> Player (Boss)\" in your chat frame (only you see it).")
            p:Check(2, "Auto sync", opt("autoSync"),
                "After a login / reload, or when you join a raid: fills in drops you missed while disconnected. " ..
                "The Sync button in the History always works.")
        end },
        { group = "Raid Loot Suite" },
        { "window", "Window", "Window", "How the window looks.", build = function(p)
            p:Section(1, "Look")
            p:Slider(1, "Window opacity", 0.2, 1, 0.05, function() return S().opacity end,
                function(v) S().opacity = v; RLT.W.UI:ApplyOpacity() end, pct)
            p:Check(1, "Minimap button", function() return not S().minimap.hide end,
                function(v) S().minimap.hide = not v; RLT:UpdateMinimapButton() end,
                "Left-click: open / close. Right-click: menu. Drag it around the minimap.")
            p:Section(2, "Size")
            p:Text(2, "Drag the bottom right corner of the window to resize it. Double-click the corner: default size.", 40,
                "GameFontDisableSmall")
        end },
        { "about", "Commands and links", "Commands and links", "Raid Loot Suite " .. RLT.VERSION .. " by " .. RLT.AUTHOR .. ".", build = function(p)
            local sec = p:Section(1, "Commands"); sec.wide()
            local t = p:Text(1, A .. "/rls|r  open / close     " .. A .. "/rls test|r  test mode     " ..
                A .. "/rls timer <seconds>|r  roll timer     " .. A .. "/rls help|r  every command", 30, "GameFontHighlight")
            t.wide()
            local sec2 = p:Section(1, "Saved data"); sec2.wide()
            local d = p:Text(1, "WTF\\Account\\<ACCOUNT>\\SavedVariables\\RaidLootSuite.lua, written when you log out or /reload.", 26,
                "GameFontHighlightSmall")
            d.wide()
            local sec3 = p:Section(1, "Links (click a box, Ctrl+A then Ctrl+C)"); sec3.wide()
            local function Link(url, icon)
                local lead = p:CreateTexture(nil, "ARTWORK")
                lead:SetWidth(16); lead:SetHeight(16)
                lead:SetTexture(RLT.MEDIA .. icon)
                lead:SetPoint("TOPLEFT", p, "TOPLEFT", 18, p:Y(1))
                local box = CreateFrame("EditBox", nil, p)
                box:SetPoint("LEFT", lead, "RIGHT", 8, 0)
                box:SetWidth(360); box:SetHeight(16)
                box:SetFontObject(GameFontHighlightSmall)
                box:SetAutoFocus(false)
                box:SetText(url)
                box:SetCursorPosition(0)
                box:SetScript("OnTextChanged", function(self, user) if user then self:SetText(url) end end)
                box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
                box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
                p:Skip(1, 24)
            end
            Link("https://github.com/saranwrap04/Raid-loot-suite", "github")
            Link("https://warperia.com/addon-wotlk/raid-loot-suite/", "warperia")
        end },
    }
    local set = K.Settings(parent, cats, "v" .. RLT.VERSION .. "  -  " .. RLT.AUTHOR)
    set.onRefresh = function()
        if RLT.SUI.RefreshCouncilSummary then RLT.SUI:RefreshCouncilSummary() end
        if RLT.SUI.RefreshTestButton then RLT.SUI:RefreshTestButton() end
    end
    local show = set.Show
    set.Show = function(self, key) return show(self, OLD_KEYS[key] or key) end
    parent:SetScript("OnShow", function() set:Show(set.current or set.first) end)
    return set
end
