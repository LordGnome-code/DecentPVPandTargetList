-- Decent PvP and Target List: WoW Forever (modern client) compatible.
local ADDON, ns = ...
local PREFIX = "DPTL2"
local MAX_TARGETS = 3
local RACES = { "Human", "Orc", "Dwarf", "Night Elf", "Undead", "Tauren", "Gnome", "Troll", "Blood Elf", "Draenei" }
local CLASSES = { "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Death Knight", "Shaman", "Mage", "Warlock", "Monk", "Druid", "Demon Hunter", "Evoker" }
local DB_DEFAULTS = { kills = {}, targets = {}, targetKills = {}, nextId = 1, layout = "modernblizz", pendingStats = false, pendingTargets = {}, windowWidth = 760, windowHeight = 700 }
local factionThemes = {
    Horde = { 0.82, 0.16, 0.19 },
    Alliance = { 0.16, 0.42, 0.88 },
}

local function fillDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            fillDefaults(dst[k], v)
        elseif dst[k] == nil then dst[k] = v end
    end
end

local function playerName()
    local first, last
    if UnitFullName then first, last = UnitFullName("player") end
    local realm = GetRealmName and GetRealmName()
    if first and last and last ~= "" and last ~= realm then
        return first .. " " .. last
    end
    return UnitName("player") or first or "Unknown"
end

local function isPlayerSender(sender)
    if type(sender) ~= "string" then return false end
    local short = UnitName("player")
    local full = playerName()
    if sender == short or sender == full then return true end
    local withoutRealm = string.gsub(sender, "%-.*$", "")
    return withoutRealm == short or withoutRealm == full
end
local function today() return date("%Y%m%d") end
local function currentWeekStart()
    local now = GetServerTime and GetServerTime() or time()
    local resetFn = C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset
    if type(resetFn) == "function" then
        local ok, remaining = pcall(resetFn)
        if ok and type(remaining) == "number" and (not issecretvalue or not issecretvalue(remaining)) and remaining >= 0 then
            return now + remaining - 604800
        end
    end
    -- Forever's weekly reset is Tuesday. Use UTC for a stable key across clients.
    local weekday = tonumber(date("!%w", now)) or 0
    return now - ((weekday - 2) % 7) * 86400
end
local function thisWeek() return date("!%Y%W", currentWeekStart()) end
local function weekKeyAt(timestamp, start)
    start = start or currentWeekStart()
    local weeksFromCurrent = math.floor((timestamp - start) / 604800)
    return date("!%Y%W", start + weeksFromCurrent * 604800)
end
local function safe(s, max)
    s = tostring(s or "")
    s = string.gsub(s, "[|\r\n]", " ")
    return string.sub(s, 1, max or 48)
end
local function guildReady() return IsInGuild and IsInGuild() end
local function checkRestriction(name, fn)
    if type(fn) ~= "function" then return false end
    local ok, restricted = pcall(fn)
    if not ok then return true, name .. " check errored: " .. tostring(restricted) end
    if restricted then return true, name .. " returned true" end
    return false
end

local function chatRestrictionReason()
    -- This is the specific lockdown signal used by Forever guild-sync addons.
    -- AreOutgoingAddonChatMessagesRestricted() can be true independently of
    -- this state, so let SendAddonMessage report whether this send is accepted.
    local restricted, reason = checkRestriction("C_ChatInfo.InChatMessagingLockdown()",
        C_ChatInfo and C_ChatInfo.InChatMessagingLockdown)
    if restricted then return reason end
    return nil
end

local function sendResultName(result)
    local values = Enum and Enum.SendAddonMessageResult
    if type(values) == "table" then
        for name, value in pairs(values) do
            if value == result then return name end
        end
    end
    return tostring(result)
end

local function sendGuild(msg)
    if not guildReady() then return false, "Join a guild before sharing targets or rankings." end
    if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then
        return false, "This client does not expose addon messaging."
    end
    local restriction = chatRestrictionReason()
    if restriction then return false, "Addon message blocked before sending: " .. restriction .. "." end
    -- Automatic reports are deferred until the client leaves combat and permits addon messages.
    local called, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, "GUILD")
    if not called then return false, "C_ChatInfo.SendAddonMessage errored: " .. tostring(result) end
    if Enum and Enum.SendAddonMessageResult and result
        and result ~= Enum.SendAddonMessageResult.Success then
        return false, "C_ChatInfo.SendAddonMessage returned " .. sendResultName(result) .. " (" .. tostring(result) .. ")."
    end
    return true
end
local function split(msg)
    local out = {}
    for value in string.gmatch(msg .. "|", "(.-)|") do table.insert(out, value) end
    return out
end
local function toNumber(value) return tonumber(value) or 0 end

local function ownStats()
    local name = playerName()
    if not DPTL_DB.kills[name] then
        DPTL_DB.kills[name] = { total = 0, lifetime = nil, daily = {}, weekly = {} }
    end
    return DPTL_DB.kills[name]
end

local function lifetimeHonorableKills()
    if not GetPVPLifetimeStats then return nil end
    local ok, lifetime = pcall(GetPVPLifetimeStats)
    if ok and type(lifetime) == "number" then return lifetime end
    return nil
end

local function syncLifetimeKills()
    local total = lifetimeHonorableKills()
    if total == nil then return false end
    ownStats().lifetime = total
    return true
end

local function counts(rec)
    return toNumber(rec.daily and rec.daily[today()]),
        toNumber(rec.weekly and rec.weekly[thisWeek()]),
        toNumber(rec.lifetime ~= nil and rec.lifetime or rec.total)
end

local function shareStats()
    syncLifetimeKills()
    local rec = ownStats()
    local d, w, a = counts(rec)
    return sendGuild(table.concat({ "S", today(), thisWeek(), d, w, a }, "|"))
end

local function sharePendingStats()
    if not DPTL_DB.pendingStats or chatRestrictionReason() then return end
    local ok = shareStats()
    if ok then DPTL_DB.pendingStats = false end
end

local function recordKill()
    local rec = ownStats()
    local d, w = today(), thisWeek()
    rec.total = toNumber(rec.total) + 1
    rec.daily[d] = toNumber(rec.daily[d]) + 1
    rec.weekly[w] = toNumber(rec.weekly[w]) + 1
    for key in pairs(rec.daily) do if key ~= d then rec.daily[key] = nil end end
    for key in pairs(rec.weekly) do if key ~= w then rec.weekly[key] = nil end end
    syncLifetimeKills()
end

local function migrateWeeklyBuckets()
    local oldWeek, currentWeek = date("%Y%W"), thisWeek()
    for _, rec in pairs(DPTL_DB.kills or {}) do
        rec.weekly = rec.weekly or {}
        local current = rec.weekly[currentWeek]
        if current == nil then current = rec.weekly[oldWeek] end
        rec.weekly = current ~= nil and { [currentWeek] = current } or {}
    end
end

local function targetKey(owner, id) return owner .. ":" .. tostring(id) end

local function rewardCopper(gold, silver, copper)
    return (toNumber(gold) * 10000) + (toNumber(silver) * 100) + toNumber(copper)
end

local function formatMoney(copper)
    copper = math.max(0, math.floor(toNumber(copper)))
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local coins = copper % 100
    return string.format("%dg %ds %dc", gold, silver, coins)
end

local function migratePlayerIdentity()
    local short, full = UnitName("player"), playerName()
    if not short or not full or short == full then return end

    local oldRec = DPTL_DB.kills[short]
    if oldRec then
        local current = DPTL_DB.kills[full]
        if not current then
            DPTL_DB.kills[full] = oldRec
        else
            current.daily, current.weekly = current.daily or {}, current.weekly or {}
            for key, value in pairs(oldRec.daily or {}) do
                if toNumber(value) > toNumber(current.daily[key]) then current.daily[key] = value end
            end
            for key, value in pairs(oldRec.weekly or {}) do
                if toNumber(value) > toNumber(current.weekly[key]) then current.weekly[key] = value end
            end
            current.total = math.max(toNumber(current.total), toNumber(oldRec.total))
            if oldRec.lifetime ~= nil then
                current.lifetime = math.max(toNumber(current.lifetime), toNumber(oldRec.lifetime))
            end
            if toNumber(oldRec.lastKill) > toNumber(current.lastKill) then
                current.lastKill, current.lastVictim = oldRec.lastKill, oldRec.lastVictim
            end
        end
        DPTL_DB.kills[short] = nil
    end

    local targets, pending = {}, {}
    for oldKey, target in pairs(DPTL_DB.targets) do
        if target.owner == short then target.owner = full end
        local key = targetKey(target.owner, target.id)
        if not targets[key] then targets[key] = target end
        if DPTL_DB.pendingTargets[oldKey] then pending[key] = true end
    end
    DPTL_DB.targets, DPTL_DB.pendingTargets = targets, pending
end

local function ownedTargetCount(owner)
    local count = 0
    for _, t in pairs(DPTL_DB.targets) do if t.owner == owner then count = count + 1 end end
    return count
end

local function broadcastTarget(t)
    return sendGuild(table.concat({ "T", t.id, safe(t.name, 35), safe(t.gold, 8), safe(t.silver, 4),
        safe(t.copper, 4), safe(t.reward, 40), safe(t.proof, 40), t.created,
        safe(t.race, 20), safe(t.class, 20) }, "|"))
end

local function sharePendingTargets()
    if not DPTL_DB or chatRestrictionReason() then return end
    for key in pairs(DPTL_DB.pendingTargets or {}) do
        local target = DPTL_DB.targets[key]
        if not target then
            DPTL_DB.pendingTargets[key] = nil
        else
            local ok = broadcastTarget(target)
            if ok then DPTL_DB.pendingTargets[key] = nil else break end
        end
    end
end

local root = CreateFrame("Frame")
root:RegisterEvent("ADDON_LOADED")
root:RegisterEvent("PLAYER_LOGIN")
root:RegisterEvent("CHAT_MSG_ADDON")
root:RegisterEvent("PLAYER_PVP_KILLS_CHANGED")
root:RegisterEvent("PLAYER_REGEN_ENABLED")

local ui = { rows = {}, tab = "pvp", targetPage = "active" }
local function info(text)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff62c5ffDPTL:|r " .. text) end
end

local function track(widget)
    table.insert(ui.rows, widget)
    return widget
end

local function clearRows()
    for _, widget in ipairs(ui.rows) do
        if widget and widget.Hide then widget:Hide() end
        if widget and widget.SetParent then widget:SetParent(nil) end
    end
    ui.rows = {}
end
local function label(parent, text, x, y, width, font)
    local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetWidth(width or 500)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    return track(fs)
end
local function centeredLabel(parent, text, y, width, font)
    local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlightSmall")
    fs:SetPoint("TOP", parent, "TOP", 0, y)
    fs:SetWidth(width or parent:GetWidth())
    fs:SetJustifyH("CENTER")
    fs:SetText(text)
    return track(fs)
end
local function settingButton(parent, text, x, y, width, action)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 24); b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    b:SetText(text); b:SetScript("OnClick", action)
    return track(b)
end
local function row(text, y)
    local fs = ui.body:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    fs:SetPoint("TOP", ui.body, "TOP", 0, y)
    fs:SetWidth(math.max(300, ui.body:GetWidth() - 12))
    fs:SetJustifyH("CENTER")
    fs:SetText(text)
    return track(fs)
end
local function button(parent, text, x, y, width, action)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 24); b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    b:SetText(text); b:SetScript("OnClick", action)
    return track(b)
end
local function edit(parent, title, x, y, width)
    label(parent, title, x, y, width)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(width, 22); box:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 19)
    box:SetAutoFocus(false); box:SetMaxLetters(48)
    return track(box)
end

local refresh
local function styleFrame()
    if not ui.frame then return end
    local faction = UnitFactionGroup and UnitFactionGroup("player") or "Alliance"
    local accent = factionThemes[faction] or factionThemes.Alliance
    local blizzard = DPTL_DB.layout == "blizzlike"
    local forge = DPTL_DB.layout == "modernblizz"
    if blizzard then
        ui.frame:SetBackdrop({ bgFile = "Interface\\FrameGeneral\\UI-Background-Rock",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true,
            tileSize = 64, edgeSize = 32, insets = { left = 8, right = 8, top = 8, bottom = 8 } })
        ui.frame:SetBackdropColor(1, 1, 1, 1)
        ui.frame:SetBackdropBorderColor(1, 1, 1, 1)
        ui.inset:SetBackdrop({ bgFile = "Interface\\FrameGeneral\\UI-Background-Marble",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true,
            tileSize = 64, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        ui.inset:SetBackdropColor(1, 1, 1, 1)
        ui.inset:SetBackdropBorderColor(0.72, 0.72, 0.72, 1)
        ui.headerArt:Show()
        ui.title:SetTextColor(1, 0.82, 0)
        ui.title:SetParent(ui.frame)
        ui.title:ClearAllPoints()
        ui.title:SetPoint("TOP", ui.frame, "TOP", 0, -17)
        ui.titleBar:Hide()
    elseif forge then
        ui.frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
        ui.frame:SetBackdropColor(0.035, 0.032, 0.028, 0.99)
        ui.frame:SetBackdropBorderColor(0.62, 0.43, 0.22, 0.95)
        ui.inset:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        ui.inset:SetBackdropColor(0.075, 0.068, 0.058, 0.99)
        ui.inset:SetBackdropBorderColor(0.34, 0.27, 0.19, 0.95)
        ui.headerArt:Hide()
        ui.titleBar:Show()
        ui.title:SetParent(ui.titleBar)
        ui.title:ClearAllPoints()
        ui.title:SetPoint("CENTER", ui.titleBar, "CENTER", 0, 0)
        ui.title:SetTextColor(0.91, 0.78, 0.55)
    else
        ui.frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
        ui.frame:SetBackdropColor(accent[1] * 0.15 + 0.025, accent[2] * 0.15 + 0.025,
            accent[3] * 0.15 + 0.025, 0.97)
        ui.frame:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1)
        ui.inset:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        ui.inset:SetBackdropColor(accent[1] * 0.09 + 0.025, accent[2] * 0.09 + 0.025,
            accent[3] * 0.09 + 0.025, 0.98)
        ui.inset:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.8)
        ui.headerArt:Hide()
        ui.titleBar:Hide()
        ui.title:SetParent(ui.frame)
        ui.title:ClearAllPoints()
        ui.title:SetPoint("TOP", ui.frame, "TOP", 0, -17)
        ui.title:SetTextColor(0.96, 0.9, 0.82)
    end
    for name, tab in pairs(ui.tabs or {}) do
        local active = name == ui.tab
        if blizzard then
            tab:SetBackdrop(nil)
            tab.text:SetTextColor(1, active and 1 or 0.78, active and 1 or 0.5)
            tab.active:SetShown(active)
        else
            local tabAccent = forge and { 0.62, 0.43, 0.22 } or accent
            tab:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
            tab:SetBackdropColor(active and tabAccent[1] * 0.22 + 0.04 or 0.035,
                active and tabAccent[2] * 0.22 + 0.04 or 0.035,
                active and tabAccent[3] * 0.22 + 0.04 or 0.04, 1)
            tab:SetBackdropBorderColor(active and tabAccent[1] or 0.25,
                active and tabAccent[2] or 0.25, active and tabAccent[3] or 0.28, 1)
            tab.text:SetTextColor(active and 1 or (forge and 0.91 or 0.7),
                active and (forge and 0.82 or 0.92) or (forge and 0.74 or 0.7),
                active and (forge and 0.64 or 0.72) or (forge and 0.56 or 0.7))
            tab.active:SetShown(false)
        end
    end
    for name, tab in pairs(ui.targetSubTabs or {}) do
        local active = name == ui.targetPage
        if blizzard then
            tab:SetBackdrop(nil)
            tab.label:SetTextColor(1, active and 1 or 0.78, active and 1 or 0.5)
            tab.active:SetShown(active)
        else
            local tabAccent = forge and { 0.62, 0.43, 0.22 } or accent
            tab:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
            tab:SetBackdropColor(active and tabAccent[1] * 0.22 + 0.04 or 0.035,
                active and tabAccent[2] * 0.22 + 0.04 or 0.035, active and tabAccent[3] * 0.22 + 0.04 or 0.04, 1)
            tab:SetBackdropBorderColor(active and tabAccent[1] or 0.25, active and tabAccent[2] or 0.25,
                active and tabAccent[3] or 0.28, 1)
            tab.label:SetTextColor(active and 1 or (forge and 0.91 or 0.7),
                active and (forge and 0.82 or 0.92) or (forge and 0.74 or 0.7),
                active and (forge and 0.64 or 0.72) or (forge and 0.56 or 0.7))
            tab.active:Hide()
        end
    end
end

local function selectTab(name)
    if name ~= "settings" then ui.previousTab = name end
    ui.tab = name
    -- The tracker options are a separate frame. Keep them scoped to the host
    -- Settings tab so they cannot linger over PvP or Target List pages.
    if name ~= "settings" and DecentPVPRank_CloseSettings then
        DecentPVPRank_CloseSettings()
    end
    if DecentPVPRank_SetEmbeddedVisible then DecentPVPRank_SetEmbeddedVisible(name == "pvp") end
    refresh()
    styleFrame()
    if name == "pvp" and DecentPVPRank_RefreshGuildKills then DecentPVPRank_RefreshGuildKills() end
end

local function selectTargetPage(name)
    ui.targetPage = name
    refresh()
    styleFrame()
end

local function dropdown(parent, title, values, x, y, width, initial, changed)
    label(parent, title, x, y, width)
    local menu = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
    menu:SetPoint("TOPLEFT", parent, "TOPLEFT", x - 16, y - 18)
    UIDropDownMenu_SetWidth(menu, width)
    UIDropDownMenu_SetText(menu, initial or values[1])
    UIDropDownMenu_Initialize(menu, function(self, level)
        for _, value in ipairs(values) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = value
            info.checked = UIDropDownMenu_GetText(menu) == value
            info.func = function()
                UIDropDownMenu_SetText(menu, value)
                if changed then changed(value) end
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    return track(menu)
end

local function racePortrait(race)
    local textures = {
        Human = "achievement_character_human_male", Orc = "achievement_character_orc_male",
        Dwarf = "achievement_character_dwarf_male", ["Night Elf"] = "achievement_character_nightelf_male",
        Undead = "achievement_character_scourge_male", Tauren = "achievement_character_tauren_male",
        Gnome = "achievement_character_gnome_male", Troll = "achievement_character_troll_male",
        ["Blood Elf"] = "achievement_character_bloodelf_male", Draenei = "achievement_character_draenei_male",
    }
    return race and textures[race] and ("Interface\\Icons\\" .. textures[race])
end

refresh = function()
    clearRows()
    local measuredWidth, measuredHeight = ui.body:GetWidth(), ui.body:GetHeight()
    local bodyWidth = math.max(300, measuredWidth > 0 and measuredWidth or (DPTL_DB.windowWidth - 48))
    local bodyHeight = math.max(220, measuredHeight > 0 and measuredHeight or (DPTL_DB.windowHeight - 120))
    for _, tab in pairs(ui.targetSubTabs or {}) do tab:SetShown(ui.tab == "targets") end
    if ui.tab ~= "targets" or ui.targetPage ~= "kills" then
        for _, widget in ipairs(ui.body.dptlTargetWidgets or {}) do widget:Hide(); widget:SetParent(nil) end
        ui.body.dptlTargetWidgets = {}
    end
    if ui.tab ~= "targets" and ui.targetScroll then ui.targetScroll:Hide() end
    if ui.tab == "pvp" then
        if ui.targetScroll then ui.targetScroll:Hide() end
    elseif ui.tab == "targets" then
        if ui.targetPage == "kills" then
            if ui.targetScroll then ui.targetScroll:Hide() end
            DPTL_BuildTargetKillsPage(ui.body)
        else
        row("Guild targets — only the creator can remove their entries.", 0)
        local targets = {}
        for _, t in pairs(DPTL_DB.targets) do table.insert(targets, t) end
        table.sort(targets, function(a, b) return (a.created or 0) > (b.created or 0) end)
        local listTop = -25
        local formTop = -bodyHeight + 195
        local contentWidth = math.max(310, math.min(bodyWidth - 36, 660))
        local contentLeft = (bodyWidth - contentWidth) / 2
        if not ui.targetScroll then
            ui.targetScroll = CreateFrame("ScrollFrame", "DPTLTargetScroll", ui.body, "UIPanelScrollFrameTemplate")
            ui.targetContent = CreateFrame("Frame", nil, ui.targetScroll)
            ui.targetScroll:SetScrollChild(ui.targetContent)
        end
        ui.targetScroll:ClearAllPoints()
        ui.targetScroll:SetPoint("TOPLEFT", ui.body, "TOPLEFT", contentLeft, listTop - 22)
        ui.targetScroll:SetPoint("BOTTOMLEFT", ui.body, "TOPLEFT", contentLeft, formTop - 10)
        ui.targetScroll:SetWidth(contentWidth)
        ui.targetScroll:Show()
        for _, old in ipairs(ui.targetRows or {}) do old:Hide(); old:SetParent(nil) end
        ui.targetRows = {}
        for index, target in ipairs(targets) do
            local targetRecord = target
            local y = -((index - 1) * 70)
            local rowFrame = CreateFrame("Frame", nil, ui.targetContent)
            rowFrame:SetSize(contentWidth, 66); rowFrame:SetPoint("TOPLEFT", ui.targetContent, "TOPLEFT", 0, y)
            local raceIcon = rowFrame:CreateTexture(nil, "ARTWORK")
            raceIcon:SetSize(28, 28); raceIcon:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", 0, -2)
            raceIcon:SetTexture(racePortrait(target.race) or "Interface\\Icons\\INV_Misc_QuestionMark")
            local classIcon = rowFrame:CreateTexture(nil, "ARTWORK")
            classIcon:SetSize(28, 28); classIcon:SetPoint("TOPLEFT", raceIcon, "TOPRIGHT", 3, 0)
            local atlas = target.class and ("class-icon-" .. string.lower(target.class:gsub(" ", "")))
            if atlas and classIcon.SetAtlas then classIcon:SetAtlas(atlas) else classIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark") end
            local reward = target.reward
            if reward == "" then
            reward = string.format("%s |TInterface\\MoneyFrame\\UI-GoldIcon:12:12:0:0|t   %s |TInterface\\MoneyFrame\\UI-SilverIcon:12:12:0:0|t   %s |TInterface\\MoneyFrame\\UI-CopperIcon:12:12:0:0|t",
                    target.gold, target.silver, target.copper)
            end
            local details = rowFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            details:SetPoint("TOPLEFT", classIcon, "TOPRIGHT", 7, 0)
            details:SetWidth(math.max(100, contentWidth - 260)); details:SetJustifyH("LEFT")
            details:SetText(string.format("%s (%s %s) | %s\nSubmitted by %s | Reward: %s | Proof: %s",
                target.name, target.race or "?", target.class or "?", date("%b %d", target.created or time()),
                target.owner or "Unknown", reward, target.proof or ""))
            local creditedName = CreateFrame("EditBox", nil, rowFrame, "InputBoxTemplate")
            creditedName:SetSize(98, 20); creditedName:SetPoint("TOPRIGHT", rowFrame, "TOPRIGHT", -4, -2)
            creditedName:SetAutoFocus(false); creditedName:SetMaxLetters(48); creditedName:SetText(playerName())
            creditedName:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("Name to credit for this target elimination")
                GameTooltip:Show()
            end)
            creditedName:SetScript("OnLeave", function() GameTooltip:Hide() end)
            local report = button(rowFrame, "Record & remove", contentWidth - 112, -28, 106, function()
                local killer = safe(creditedName:GetText(), 48)
                if killer == "" then info("Enter the name to credit for this target kill."); return end
                local key = targetKey(targetRecord.owner, targetRecord.id)
                if DPTL_DB.targetKills[key] then info("This target kill was already recorded."); return end
                local payload = table.concat({ "K", safe(targetRecord.owner, 48), targetRecord.id, safe(targetRecord.name, 35), killer,
                    safe(targetRecord.gold, 8), safe(targetRecord.silver, 4), safe(targetRecord.copper, 4), safe(targetRecord.reward, 40), time() }, "|")
                local ok, err = sendGuild(payload)
                if not ok then info("Target kill was not shared: " .. err); return end
                DPTL_DB.targetKills[key] = { owner = targetRecord.owner, id = targetRecord.id, target = targetRecord.name,
                    creditedTo = killer, gold = targetRecord.gold, silver = targetRecord.silver, copper = targetRecord.copper,
                    reward = targetRecord.reward, killedAt = time(), reporter = playerName() }
                DPTL_DB.pendingTargets[key] = nil; DPTL_DB.targets[key] = nil
                local rewardText = targetRecord.reward or ""
                info("Target kill credited to " .. killer .. "; reward " .. (rewardText ~= "" and rewardText or formatMoney(rewardCopper(targetRecord.gold, targetRecord.silver, targetRecord.copper))) .. ".")
                refresh()
            end)
            table.insert(ui.targetRows, creditedName)
            table.insert(ui.targetRows, report)
            if target.owner == playerName() then
                local remove = button(rowFrame, "Cancel", contentWidth - 190, -28, 72, function()
                    local key = targetKey(targetRecord.owner, targetRecord.id)
                    if DPTL_DB.pendingTargets[key] then
                        DPTL_DB.pendingTargets[key] = nil
                        DPTL_DB.targets[key] = nil
                        info("Pending target removed locally; it was not shared.")
                    else
                        local ok, err = sendGuild(table.concat({ "D", targetRecord.id }, "|"))
                        if not ok then info(err); return end
                        DPTL_DB.targets[key] = nil
                    end
                    refresh()
                end)
                table.insert(ui.targetRows, remove)
            end
            table.insert(ui.targetRows, rowFrame)
        end
        ui.targetContent:SetSize(contentWidth, math.max(1, #targets * 70))
        ui.targetScroll:SetVerticalScroll(0)
        local y = formTop
        local formWidth = math.min(478, bodyWidth - 16)
        if not guildReady() then centeredLabel(ui.body, "Join a guild to share targets and rankings.", y, formWidth); y = y - 24 end
        if ownedTargetCount(playerName()) >= MAX_TARGETS then
            centeredLabel(ui.body, "You have reached the limit of 3 active targets.", y, formWidth)
        else
            centeredLabel(ui.body, "Create target", y, formWidth, "GameFontNormal"); y = y - 22
            local compact = formWidth < 430
            local enemyW, raceW, classW = compact and 96 or 124, compact and 96 or 124, compact and 96 or 124
            local gap = compact and 6 or 10
            local groupW = enemyW + raceW + classW + gap * 2
            local firstX = (bodyWidth - groupW) / 2
            ui.enemy = edit(ui.body, "Enemy player", firstX, y, enemyW)
            ui.targetRace = dropdown(ui.body, "Race", RACES, firstX + enemyW + gap, y, raceW, RACES[1])
            ui.targetClass = dropdown(ui.body, "Class", CLASSES, firstX + enemyW + gap + raceW + gap, y, classW, CLASSES[1])
            local fieldsY = y - 58
            local coinW, rewardW, proofW = compact and 40 or 48, compact and 92 or 130, compact and 104 or 140
            local fieldGap = 5
            local fieldsW = coinW * 3 + rewardW + proofW + fieldGap * 4
            local fieldsX = (bodyWidth - fieldsW) / 2
            ui.gold = edit(ui.body, "Gold", fieldsX, fieldsY, coinW)
            ui.silver = edit(ui.body, "Silver", fieldsX + coinW + fieldGap, fieldsY, coinW)
            ui.copper = edit(ui.body, "Copper", fieldsX + (coinW + fieldGap) * 2, fieldsY, coinW)
            ui.reward = edit(ui.body, "Or reward text", fieldsX + (coinW + fieldGap) * 3, fieldsY, rewardW)
            ui.proof = edit(ui.body, "Proof required", fieldsX + (coinW + fieldGap) * 3 + rewardW + fieldGap, fieldsY, proofW)
            button(ui.body, "Create", fieldsX, fieldsY - 52, 90, function()
                local name = safe(ui.enemy:GetText(), 35)
                local gold, silver, copper = safe(ui.gold:GetText(), 8), safe(ui.silver:GetText(), 4), safe(ui.copper:GetText(), 4)
                local reward, proof = safe(ui.reward:GetText(), 40), safe(ui.proof:GetText(), 40)
                if name == "" or proof == "" then info("Enter an enemy player and proof requirement."); return end
                if (gold ~= "" and not string.match(gold, "^%d+$"))
                    or (silver ~= "" and not string.match(silver, "^%d+$"))
                    or (copper ~= "" and not string.match(copper, "^%d+$")) then
                    info("Coin amounts must be whole numbers."); return
                end
                if reward == "" and (gold == "" and silver == "" and copper == "") then
                    info("Enter a coin amount or reward text."); return
                end
                local id = DPTL_DB.nextId
                DPTL_DB.nextId = id + 1
                local t = { id = id, owner = playerName(), name = name,
                    race = UIDropDownMenu_GetText(ui.targetRace), class = UIDropDownMenu_GetText(ui.targetClass),
                    gold = gold, silver = silver, copper = copper, reward = reward, proof = proof, created = time() }
                local key = targetKey(t.owner, id)
                DPTL_DB.targets[key] = t
                local ok, err = broadcastTarget(t)
                if ok then
                    DPTL_DB.pendingTargets[key] = nil
                    info("Target created and shared with your guild.")
                else
                    DPTL_DB.pendingTargets[key] = true
                    info("Target saved locally; sharing is pending. " .. err)
                end
                refresh()
            end)
        end
        end
    else
        if ui.targetScroll then ui.targetScroll:Hide() end
        local settingsLeft = (bodyWidth - 340) / 2
        centeredLabel(ui.body, "Choose a window appearance:", 0, bodyWidth)
        settingButton(ui.body, "Normal", settingsLeft, -30, 100, function()
            DPTL_SetLayout("normal")
        end)
        settingButton(ui.body, "Blizzard-like", settingsLeft + 112, -30, 106, function()
            DPTL_SetLayout("blizzlike")
        end)
        settingButton(ui.body, "Modern-blizz", settingsLeft + 230, -30, 110, function()
            DPTL_SetLayout("modernblizz")
        end)
        settingButton(ui.body, "Share stats", settingsLeft, -68, 100, function()
            local ok, err = shareStats()
            if ok then info("Stats shared with your guild.") else info(err) end
        end)
        settingButton(ui.body, "DecentPVP tracker settings", settingsLeft, -105, 200, function()
            if DecentPVPRank_OpenSettings then DecentPVPRank_OpenSettings() end
        end)
        centeredLabel(ui.body, "Reports share with guild members when addon messages are permitted.", -138, bodyWidth)
        centeredLabel(ui.body, "Honorable kill credit is tracked automatically; Forever may not provide victim names.", -162, bodyWidth)
    end
    if ui.settingsButton then
        ui.settingsButton:SetAlpha(ui.tab == "settings" and 1 or 0.82)
    end
end

function DPTL_SetLayout(layout)
    if layout == "forge" then layout = "modernblizz" end
    if layout ~= "normal" and layout ~= "blizzlike" and layout ~= "modernblizz" then layout = "modernblizz" end
    DPTL_DB.layout = layout
    styleFrame()
    if DecentPVPRank_SetBlizzardUI then DecentPVPRank_SetBlizzardUI(layout == "blizzlike") end
    if DecentPVPRank_SetForgeUI then DecentPVPRank_SetForgeUI(layout == "modernblizz") end
end

function DPTL_SetBlizzardLayout(enabled)
    DPTL_SetLayout(enabled and "blizzlike" or "normal")
end

function DPTL_OpenPVP()
    if not ui.frame then return end
    ui.frame:Show()
    selectTab("pvp")
end

function DPTL_TogglePVP()
    if not ui.frame then return end
    if ui.frame:IsShown() and ui.tab == "pvp" then ui.frame:Hide()
    else ui.frame:Show(); selectTab("pvp") end
end

function DPTL_BuildGuildKillsPage(parent)
    if not parent then return end
    for _, widget in ipairs(parent.dptlWidgets or {}) do widget:Hide(); widget:SetParent(nil) end
    parent.dptlWidgets = {}
    local function add(widget) table.insert(parent.dptlWidgets, widget); return widget end
    local width = math.max(300, parent:GetWidth())
    local pageHeight = math.max(280, parent:GetHeight())
    local rowStep = math.max(19, (pageHeight - 130) / 9)
    local columns = { { "Daily", 1 }, { "Weekly", 2 }, { "All time", 3 } }
    local colWidth = (width - 16) / 3
    for col, category in ipairs(columns) do
        local x = 4 + (col - 1) * colWidth
        local header = add(parent:CreateFontString(nil, "ARTWORK", "GameFontNormal"))
        header:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -4); header:SetWidth(colWidth - 6)
        header:SetText(category[1] .. " top 10")
        local ranking = {}
        for name, rec in pairs(DPTL_DB.kills) do
            local d, w, a = counts(rec)
            table.insert(ranking, { name = name, value = category[2] == 1 and d or (category[2] == 2 and w or a) })
        end
        table.sort(ranking, function(a, b) if a.value == b.value then return a.name < b.name end return a.value > b.value end)
        for i = 1, 10 do
            local line = add(parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"))
            line:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -28 - (i - 1) * rowStep)
            line:SetWidth(colWidth - 6); line:SetJustifyH("LEFT")
            if ranking[i] then line:SetText(string.format("%2d. %s  %d", i, ranking[i].name, ranking[i].value))
            else line:SetText(string.format("%2d. —", i)) end
        end
    end
    local note = add(parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"))
    note:SetPoint("BOTTOM", parent, "BOTTOM", 0, 60); note:SetWidth(width - 12); note:SetJustifyH("CENTER")
    note:SetText("Honorable kills are tracked automatically by the game.")
    local share = add(CreateFrame("Button", nil, parent, "UIPanelButtonTemplate"))
    share:SetSize(100, 24); share:SetPoint("BOTTOM", parent, "BOTTOM", 0, 26); share:SetText("Share stats")
    share:SetScript("OnClick", function()
        local ok, err = shareStats()
        if ok then info("Stats shared.") else info(err) end
    end)
end

function DPTL_BuildTargetKillsPage(parent)
    if not parent then return end
    for _, widget in ipairs(parent.dptlTargetWidgets or {}) do widget:Hide(); widget:SetParent(nil) end
    parent.dptlTargetWidgets = {}
    local function add(widget) table.insert(parent.dptlTargetWidgets, widget); return widget end
    local width = math.max(300, parent:GetWidth())
    local pageHeight = math.max(280, parent:GetHeight())
    local panelWidth = math.min(680, width - 12)
    local left = (width - panelWidth) / 2
    local weekStart = currentWeekStart()
    local columns = { { "Daily", 1 }, { "Weekly", 2 }, { "All time", 3 } }
    local columnWidth = panelWidth / 3
    local rowStep = math.max(20, (pageHeight - 110) / 9)
    for col, category in ipairs(columns) do
        local x = left + (col - 1) * columnWidth
        local aggregates, totalMoney, totalKills = {}, 0, 0
        for _, entry in pairs(DPTL_DB.targetKills or {}) do
            local killedAt = toNumber(entry.killedAt)
            local day = date("%Y%m%d", killedAt)
            local week = weekKeyAt(killedAt, weekStart)
            local include = category[2] == 3 or (category[2] == 1 and day == today()) or (category[2] == 2 and week == thisWeek())
            if include then
                local name = entry.creditedTo or "Unknown"
                local aggregate = aggregates[name] or { kills = 0, money = 0 }
                aggregate.kills = aggregate.kills + 1
                aggregate.money = aggregate.money + rewardCopper(entry.gold, entry.silver, entry.copper)
                aggregates[name] = aggregate
                totalMoney = totalMoney + rewardCopper(entry.gold, entry.silver, entry.copper)
                totalKills = totalKills + 1
            end
        end
        local ranking = {}
        for name, values in pairs(aggregates) do
            table.insert(ranking, { name = name, kills = values.kills, money = values.money })
        end
        table.sort(ranking, function(a, b)
            if a.kills ~= b.kills then return a.kills > b.kills end
            if a.money ~= b.money then return a.money > b.money end
            return a.name < b.name
        end)
        local heading = add(parent:CreateFontString(nil, "ARTWORK", "GameFontNormal"))
        heading:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 4, -4)
        heading:SetWidth(columnWidth - 8); heading:SetJustifyH("CENTER")
        heading:SetText(category[1] .. " target kills")
        local total = add(parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"))
        total:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 4, -24)
        total:SetWidth(columnWidth - 8); total:SetJustifyH("CENTER")
        total:SetText(string.format("%d kills | earned %s", totalKills, formatMoney(totalMoney)))
        for i = 1, 10 do
            local line = add(parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"))
            line:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 6, -48 - (i - 1) * rowStep)
            line:SetWidth(columnWidth - 12); line:SetJustifyH("LEFT")
            if ranking[i] then
                line:SetText(string.format("%2d. %s — %d | %s", i, ranking[i].name, ranking[i].kills, formatMoney(ranking[i].money)))
            else line:SetText("") end
        end
    end
    local note = add(parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall"))
    note:SetPoint("BOTTOM", parent, "BOTTOM", 0, 40)
    note:SetText("A target kill is credited once when a member submits the report.")
end

local function buildUI()
    if ui.frame then return end
    local f = CreateFrame("Frame", "DPTLMainFrame", UIParent, "BackdropTemplate")
    ui.frame = f
    local savedWidth = math.max(450, math.min(1300, tonumber(DPTL_DB.windowWidth) or 760))
    local savedHeight = math.max(410, math.min(1000, tonumber(DPTL_DB.windowHeight) or 700))
    f:SetSize(savedWidth, savedHeight); f:SetPoint("CENTER"); f:SetMovable(true); f:SetResizable(true)
    if f.SetResizeBounds then f:SetResizeBounds(450, 410, 1300, 1000)
    else f:SetMinResize(450, 410); f:SetMaxResize(1300, 1000) end
    f:SetClampedToScreen(true)
    f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    f:HookScript("OnHide", function()
        if DecentPVPRank_CloseSettings then DecentPVPRank_CloseSettings() end
    end)
    f:Hide()
    ui.headerArt = f:CreateTexture(nil, "BACKGROUND")
    ui.headerArt:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    ui.headerArt:SetSize(300, 64)
    ui.headerArt:SetPoint("TOP", f, "TOP", 0, 12)
    ui.titleBar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    ui.titleBar:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -7)
    ui.titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -7)
    ui.titleBar:SetHeight(30)
    ui.titleBar:SetFrameLevel(f:GetFrameLevel() + 1)
    ui.titleBar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    ui.titleBar:SetBackdropColor(0.10, 0.088, 0.071, 1)
    ui.titleBar:SetBackdropBorderColor(0.39, 0.30, 0.20, 1)
    ui.titleBar:Hide()
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", f, "TOP", 0, -17); title:SetText("DECENT PVP & TARGET LIST")
    ui.title = title
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)
    local settingsButton = CreateFrame("Button", nil, f)
    settingsButton:SetSize(24, 24)
    settingsButton:SetPoint("RIGHT", close, "LEFT", -2, 0)
    settingsButton:SetFrameLevel(f:GetFrameLevel() + 5)
    settingsButton:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
    settingsButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    settingsButton:SetScript("OnClick", function()
        if ui.tab == "settings" then
            selectTab(ui.previousTab or "pvp")
        else
            ui.previousTab = ui.tab
            selectTab("settings")
        end
    end)
    settingsButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Settings")
        GameTooltip:Show()
    end)
    settingsButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ui.settingsButton = settingsButton
    close:SetFrameLevel(f:GetFrameLevel() + 6)
    settingsButton:SetFrameLevel(f:GetFrameLevel() + 6)
    ui.tabs = {}
    for i, tabName in ipairs({ "pvp", "targets" }) do
        local displayName = tabName == "pvp" and "DecentPVP" or "Guild Targets"
        local tab = CreateFrame("Button", nil, f, "BackdropTemplate")
        tab:SetSize(150, 30)
        tab:SetFrameLevel(f:GetFrameLevel() + 2)
        tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        tab.text:SetPoint("CENTER")
        tab.text:SetText(displayName)
        tab:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
        tab:GetHighlightTexture():SetAlpha(0.06)
        tab.active = tab:CreateTexture(nil, "OVERLAY")
        tab.active:SetColorTexture(1, 1, 1, 0.9)
        tab.active:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 2, 1)
        tab.active:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -2, 1)
        tab.active:SetHeight(2)
        tab:SetScript("OnClick", function() selectTab(tabName) end)
        ui.tabs[tabName] = tab
    end
    local function layoutTopTabs()
        local width = math.min(150, (f:GetWidth() - 54) / 2)
        local gap = 8
        for i, tabName in ipairs({ "pvp", "targets" }) do
            local tab = ui.tabs[tabName]
            tab:SetSize(width, 30)
            tab:ClearAllPoints()
            tab:SetPoint("TOP", f, "TOP", (i - 1.5) * (width + gap), -51)
        end
    end
    f:HookScript("OnSizeChanged", layoutTopTabs)
    layoutTopTabs()
    ui.body = CreateFrame("Frame", nil, f)
    ui.inset = CreateFrame("Frame", nil, f, "BackdropTemplate")
    ui.inset:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -87)
    ui.inset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
    local function layoutBodyContent()
        local availableWidth = ui.inset:GetWidth() - 20
        local availableHeight = ui.inset:GetHeight() - 20
        if availableWidth < 1 then availableWidth = f:GetWidth() - 44 end
        if availableHeight < 1 then availableHeight = f:GetHeight() - 119 end
        local scale = math.min(1.6, availableWidth / 716, availableHeight / 581)
        scale = math.max(0.4, scale)
        ui.body:ClearAllPoints()
        ui.body:SetSize(716, 581)
        ui.body:SetScale(scale)
        ui.body:SetPoint("CENTER", ui.inset, "CENTER")
    end
    layoutBodyContent()
    f:HookScript("OnSizeChanged", layoutBodyContent)
    if DecentPVPRank_EmbedInto then
        DecentPVPRank_EmbedInto(ui.body)
        if DecentPVPRank_SetForgeUI then DecentPVPRank_SetForgeUI(DPTL_DB.layout == "modernblizz") end
        if DecentPVPRank_SetBlizzardUI then DecentPVPRank_SetBlizzardUI(DPTL_DB.layout == "blizzlike") end
        if DecentPVPRank_SetEmbeddedVisible then DecentPVPRank_SetEmbeddedVisible(ui.tab == "pvp") end
    end
    ui.targetSubTabs = {}
    for i, entry in ipairs({ { "active", "Active Targets" }, { "kills", "Target Kills" } }) do
        local name, caption = entry[1], entry[2]
        local tab = CreateFrame("Button", nil, ui.body, "BackdropTemplate")
        tab:SetSize(132, 27)
        tab:SetPoint("BOTTOM", ui.body, "BOTTOM", (i == 1 and -68 or 68), 3)
        tab:SetFrameLevel(ui.body:GetFrameLevel() + 10)
        tab.label = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        tab.label:SetPoint("CENTER"); tab.label:SetText(caption)
        tab.active = tab:CreateTexture(nil, "OVERLAY")
        tab.active:SetColorTexture(1, 1, 1, 0.9)
        tab.active:SetPoint("BOTTOMLEFT", 2, 1); tab.active:SetPoint("BOTTOMRIGHT", -2, 1); tab.active:SetHeight(2)
        tab:SetScript("OnClick", function() selectTargetPage(name) end)
        ui.targetSubTabs[name] = tab
    end
    local resizeGrip = CreateFrame("Button", nil, f)
    resizeGrip:SetSize(16, 16)
    resizeGrip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -5, 5)
    resizeGrip:SetFrameLevel(f:GetFrameLevel() + 10)
    resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeGrip:SetScript("OnMouseDown", function(_, mouseButton)
        if mouseButton == "LeftButton" then f:StartSizing("BOTTOMRIGHT") end
    end)
    resizeGrip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        local width, height = f:GetSize()
        DPTL_DB.windowWidth, DPTL_DB.windowHeight = math.floor(width + 0.5), math.floor(height + 0.5)
        layoutBodyContent()
        refresh()
        if DecentPVPRank_ResizeEmbedded then DecentPVPRank_ResizeEmbedded() end
    end)
    ui.resizeGrip = resizeGrip
    refresh()
    styleFrame()
end

local function onAddonMessage(prefix, message, channel, sender)
    if prefix ~= PREFIX or (channel ~= "GUILD" and channel ~= "PARTY" and channel ~= "RAID") or not sender then return end
    if isPlayerSender(sender) then return end
    sender = string.gsub(sender, "%-.*$", "")
    local p = split(message)
    if p[1] == "S" and #p >= 6 then
        local rec = DPTL_DB.kills[sender] or { daily = {}, weekly = {} }
        rec.daily = { [p[2]] = toNumber(p[4]) }
        rec.weekly = { [p[3]] = toNumber(p[5]) }
        rec.total = toNumber(p[6]); rec.receivedAt = time()
        DPTL_DB.kills[sender] = rec
        if DecentPVPRank_RefreshGuildKills then DecentPVPRank_RefreshGuildKills() end
    elseif p[1] == "T" and #p >= 11 then
        local id = tonumber(p[2])
        if id and (DPTL_DB.targets[targetKey(sender, id)] or ownedTargetCount(sender) < MAX_TARGETS) then
            local t = { id = id, owner = sender, name = p[3], gold = p[4], silver = p[5],
                copper = p[6], reward = p[7], proof = p[8], created = tonumber(p[9]) or time(),
                race = p[10], class = p[11] }
            DPTL_DB.targets[targetKey(sender, id)] = t
            if ui.tab == "targets" then refresh() end
        end
    elseif p[1] == "K" and #p >= 10 then
        local owner, id = p[2], tonumber(p[3])
        local key = id and targetKey(owner, id)
        if key and not DPTL_DB.targetKills[key] then
            DPTL_DB.targetKills[key] = { owner = owner, id = id, target = p[4], creditedTo = p[5],
                gold = p[6], silver = p[7], copper = p[8], reward = p[9],
                killedAt = tonumber(p[10]) or time(), reporter = sender }
            DPTL_DB.targets[key] = nil
            DPTL_DB.pendingTargets[key] = nil
            if ui.tab == "targets" then refresh() end
        end
    elseif p[1] == "D" and #p >= 2 then
        local id = tonumber(p[2])
        local t = id and DPTL_DB.targets[targetKey(sender, id)]
        -- Sender identity is taken from the guild addon-message event; only owner deletes apply.
        if t and t.owner == sender then
            DPTL_DB.targets[targetKey(sender, id)] = nil
            if ui.tab == "targets" then refresh() end
        end
    end
end

root:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name ~= ADDON then return end
        if type(DPTL_DB) ~= "table" then DPTL_DB = {} end
        fillDefaults(DPTL_DB, DB_DEFAULTS)
        -- Existing saved layouts remain the player's choice; new installations default to Modern-blizz.
        if DPTL_DB.layout == "forge" then DPTL_DB.layout = "modernblizz" end
        DPTL_DB.shareChannel = nil
        DPTL_DB.fontScale = nil
        ownStats()
        syncLifetimeKills()
    elseif event == "PLAYER_LOGIN" then
        migratePlayerIdentity()
        migrateWeeklyBuckets()
        syncLifetimeKills()
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
        end
        buildUI()
        SLASH_DPTL1 = "/dptl"
        SLASH_DPTL2 = "/targetlist"
        SlashCmdList.DPTL = function()
            if ui.frame:IsShown() then ui.frame:Hide() else refresh(); ui.frame:Show() end
        end
        sharePendingStats()
        sharePendingTargets()
        if C_Timer and C_Timer.NewTicker then
            C_Timer.NewTicker(30, function()
                sharePendingStats()
                sharePendingTargets()
            end)
        end
    elseif event == "CHAT_MSG_ADDON" then
        onAddonMessage(...)
    elseif event == "PLAYER_PVP_KILLS_CHANGED" then
        -- Track the count from the game's honorable-kill event; target names are not required.
        recordKill()
        syncLifetimeKills()
        DPTL_DB.pendingStats = true
        if DecentPVPRank_RefreshGuildKills then DecentPVPRank_RefreshGuildKills() end
        sharePendingStats()
    elseif event == "PLAYER_REGEN_ENABLED" then
        sharePendingStats()
        sharePendingTargets()
    end
end)

-- WoW Forever's Addon Compartment entry is also collected by IconBag.
function DPTL_AddonCompartmentClick()
    if not ui.frame then buildUI() end
    if ui.frame:IsShown() then ui.frame:Hide() else refresh(); ui.frame:Show() end
end
