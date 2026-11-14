-- Decent PvP and Target List: WoW Forever (modern client) compatible.
local ADDON, ns = ...
local PREFIX = "DPTL1"
local MAX_TARGETS = 3
local DB_DEFAULTS = { kills = {}, targets = {}, nextId = 1, layout = "normal", pendingStats = false }
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

local function playerName() return UnitName("player") or "Unknown" end
local function today() return date("%Y%m%d") end
local function thisWeek() return date("%Y%W") end
local function safe(s, max)
    s = tostring(s or "")
    s = string.gsub(s, "[|\r\n]", " ")
    return string.sub(s, 1, max or 48)
end
local function guildReady() return IsInGuild and IsInGuild() end
local function chatRestricted()
    if InCombatLockdown and InCombatLockdown() then return true end
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then return true end
    if C_ChatInfo and C_ChatInfo.AreOutgoingAddonChatMessagesRestricted
        and C_ChatInfo.AreOutgoingAddonChatMessagesRestricted() then return true end
    return false
end

local function sendGuild(msg)
    if not guildReady() then return false, "Join a guild first." end
    if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then
        return false, "This client does not expose guild addon messaging."
    end
    if chatRestricted() then
        return false, "The game currently restricts addon messages. Try again later or outside this instance."
    end
    -- Automatic reports are deferred until the client leaves combat and permits addon messages.
    local called, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, "GUILD")
    if not called then return false, "The client blocked guild sharing." end
    if Enum and Enum.SendAddonMessageResult and result
        and result ~= Enum.SendAddonMessageResult.Success then
        return false, "The game did not accept the guild message (result " .. tostring(result) .. ")."
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
    if not DPTL_DB.pendingStats or chatRestricted() then return end
    local ok = shareStats()
    if ok then DPTL_DB.pendingStats = false end
end

local function recordKill(victim)
    local rec = ownStats()
    local d, w = today(), thisWeek()
    rec.total = toNumber(rec.total) + 1
    rec.daily[d] = toNumber(rec.daily[d]) + 1
    rec.weekly[w] = toNumber(rec.weekly[w]) + 1
    for key in pairs(rec.daily) do if key ~= d then rec.daily[key] = nil end end
    for key in pairs(rec.weekly) do if key ~= w then rec.weekly[key] = nil end end
    rec.lastVictim = safe(victim, 35)
    rec.lastKill = time()
    syncLifetimeKills()
end

local function targetKey(owner, id) return owner .. ":" .. tostring(id) end
local function ownedTargetCount(owner)
    local count = 0
    for _, t in pairs(DPTL_DB.targets) do if t.owner == owner then count = count + 1 end end
    return count
end

local function broadcastTarget(t)
    return sendGuild(table.concat({ "T", t.id, safe(t.name, 35), safe(t.gold, 8), safe(t.silver, 4),
        safe(t.copper, 4), safe(t.reward, 40), safe(t.proof, 40), t.created }, "|"))
end

local root = CreateFrame("Frame")
root:RegisterEvent("ADDON_LOADED")
root:RegisterEvent("PLAYER_LOGIN")
root:RegisterEvent("CHAT_MSG_ADDON")
root:RegisterEvent("PLAYER_PVP_KILLS_CHANGED")
root:RegisterEvent("PLAYER_REGEN_ENABLED")

local ui = { rows = {}, tab = "kills" }
local function info(text)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff62c5ffDPTL:|r " .. text) end
end

local function clearRows()
    for _, row in ipairs(ui.rows) do row:Hide(); row:SetParent(nil) end
    ui.rows = {}
end
local function label(parent, text, x, y, width, font)
    local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetWidth(width or 500)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    return fs
end
local function row(text, y)
    local fs = label(ui.body, text, 6, y, 510)
    table.insert(ui.rows, fs)
    return fs
end
local function button(parent, text, x, y, width, action)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 24); b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    b:SetText(text); b:SetScript("OnClick", action)
    return b
end
local function edit(parent, title, x, y, width)
    label(parent, title, x, y, width)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(width, 22); box:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 19)
    box:SetAutoFocus(false); box:SetMaxLetters(48)
    return box
end

local refresh
local function styleFrame()
    if not ui.frame then return end
    local faction = UnitFactionGroup and UnitFactionGroup("player") or "Alliance"
    local accent = factionThemes[faction] or factionThemes.Alliance
    local blizzard = DPTL_DB.layout == "blizzlike"
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
        ui.title:SetTextColor(0.96, 0.9, 0.82)
    end
    for name, tab in pairs(ui.tabs or {}) do
        local active = name == ui.tab
        if blizzard then
            tab:SetBackdrop(nil)
            tab.text:SetTextColor(1, active and 1 or 0.78, active and 1 or 0.5)
            tab.active:SetShown(active)
        else
            tab:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
            tab:SetBackdropColor(active and accent[1] * 0.22 + 0.04 or 0.035,
                active and accent[2] * 0.22 + 0.04 or 0.035,
                active and accent[3] * 0.22 + 0.04 or 0.04, 1)
            tab:SetBackdropBorderColor(active and accent[1] or 0.25,
                active and accent[2] or 0.25, active and accent[3] or 0.28, 1)
            tab.text:SetTextColor(active and 1 or 0.7, active and 0.92 or 0.7, active and 0.72 or 0.7)
            tab.active:SetShown(false)
        end
    end
end

local function selectTab(name)
    if name ~= "settings" then ui.previousTab = name end
    ui.tab = name
    refresh()
    styleFrame()
end

refresh = function()
    clearRows()
    if ui.tab == "kills" then
        label(ui.body, "Guild rankings — credited honorable kills are tracked automatically.", 6, 0, 510)
        local categories = { { "Daily", 1 }, { "Weekly", 2 }, { "All time", 3 } }
        for column, category in ipairs(categories) do
            local x = 6 + (column - 1) * 174
            local header = label(ui.body, category[1] .. " top 10", x, -26, 166)
            table.insert(ui.rows, header)
            local list = {}
            for name, rec in pairs(DPTL_DB.kills) do
                local d, w, a = counts(rec)
                table.insert(list, { name = name, value = category[2] == 1 and d or (category[2] == 2 and w or a) })
            end
            table.sort(list, function(a, b)
                if a.value == b.value then return a.name < b.name end
                return a.value > b.value
            end)
            for i = 1, math.min(10, #list) do
                local entry = label(ui.body, string.format("%2d. %-16s %d", i,
                    string.sub(list[i].name, 1, 16), list[i].value), x, -48 - (i - 1) * 23, 166)
                table.insert(ui.rows, entry)
            end
        end
        label(ui.body, "Add a missed kill manually (optional victim name).", 6, -286, 510)
        ui.victimBox = edit(ui.body, "Defeated player (optional)", 6, -307, 175)
        button(ui.body, "Record kill", 195, -307, 96, function()
            if InCombatLockdown and InCombatLockdown() then
                info("Record kills after combat ends."); return
            end
            recordKill(ui.victimBox:GetText())
            local ok, err = shareStats()
            refresh()
            if ok then info("Kill recorded and guild stats shared.") else info("Kill recorded locally. " .. err) end
        end)
        button(ui.body, "Share stats", 302, -307, 96, function()
            local ok, err = shareStats()
            if ok then info("Guild stats shared.") else info(err) end
        end)
    elseif ui.tab == "targets" then
        row("Guild targets — only the creator can remove their entries.", 0)
        local targets, y = {}, -23
        for _, t in pairs(DPTL_DB.targets) do table.insert(targets, t) end
        table.sort(targets, function(a, b) return (a.created or 0) > (b.created or 0) end)
        for _, t in ipairs(targets) do
            local reward = t.reward
            if reward == "" then reward = string.format("%sg %ss %sc", t.gold, t.silver, t.copper) end
            row(string.format("%s | %s | %s | Proof: %s | By: %s", t.name,
                date("%b %d", t.created or time()), reward, t.proof, t.owner), y)
            y = y - 24
            if t.owner == playerName() then
                local remove = button(ui.body, "Remove", 432, y + 22, 64, function()
                    local ok, err = sendGuild(table.concat({ "D", t.id }, "|"))
                    if not ok then info(err); return end
                    DPTL_DB.targets[targetKey(t.owner, t.id)] = nil
                    refresh()
                end)
                table.insert(ui.rows, remove)
            end
            y = y - 5
        end
        if not guildReady() then row("Join a guild to share targets and rankings.", y); y = y - 24 end
        if ownedTargetCount(playerName()) >= MAX_TARGETS then
            row("You have reached the limit of 3 active targets.", y)
        else
            label(ui.body, "Create target", 6, y, 100); y = y - 22
            ui.enemy = edit(ui.body, "Enemy player", 6, y, 130)
            ui.gold = edit(ui.body, "Gold", 146, y, 48)
            ui.silver = edit(ui.body, "Silver", 202, y, 48)
            ui.copper = edit(ui.body, "Copper", 258, y, 48)
            ui.reward = edit(ui.body, "Or reward text", 314, y, 100)
            ui.proof = edit(ui.body, "Proof required", 422, y, 100)
            button(ui.body, "Create", 6, y - 52, 90, function()
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
                local t = { id = id, owner = playerName(), name = name, gold = gold, silver = silver,
                    copper = copper, reward = reward, proof = proof, created = time() }
                local ok, err = broadcastTarget(t)
                if not ok then info(err); return end
                DPTL_DB.targets[targetKey(t.owner, id)] = t
                refresh()
            end)
        end
    else
        row("Choose a window appearance:", 0)
        button(ui.body, "Normal layout", 6, -30, 115, function()
            DPTL_DB.layout = "normal"; styleFrame()
        end)
        button(ui.body, "Blizzard-like", 130, -30, 115, function()
            DPTL_DB.layout = "blizzlike"; styleFrame()
        end)
        button(ui.body, "Share stats", 6, -68, 100, function()
            local ok, err = shareStats()
            if ok then info("Guild stats shared.") else info(err) end
        end)
        row("Honorable kill credit is detected automatically; victim names may not be provided by Forever.", -108)
        row("Guild reports are shared automatically when addon messaging is allowed, after combat if needed.", -132)
    end
end

local function buildUI()
    if ui.frame then return end
    local f = CreateFrame("Frame", "DPTLMainFrame", UIParent, "BackdropTemplate")
    ui.frame = f; f:SetSize(590, 480); f:SetPoint("CENTER"); f:SetMovable(true)
    f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    f:Hide()
    ui.headerArt = f:CreateTexture(nil, "BACKGROUND")
    ui.headerArt:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    ui.headerArt:SetSize(300, 64)
    ui.headerArt:SetPoint("TOP", f, "TOP", 0, 12)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -17); title:SetText("DECENT PVP & TARGET LIST")
    ui.title = title
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)
    local settingsButton = button(f, "Settings", 468, -12, 82, function()
        if ui.tab == "settings" then selectTab(ui.previousTab or "kills") else selectTab("settings") end
    end)
    ui.settingsButton = settingsButton
    ui.tabs = {}
    for i, tabName in ipairs({ "kills", "targets" }) do
        local displayName = tabName == "kills" and "Kill Rankings" or "Guild Targets"
        local tab = CreateFrame("Button", nil, f, "BackdropTemplate")
        tab:SetSize(150, 30)
        tab:SetPoint("TOPLEFT", f, "TOPLEFT", 20 + (i - 1) * 156, -51)
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
    ui.body = CreateFrame("Frame", nil, f)
    ui.inset = CreateFrame("Frame", nil, f, "BackdropTemplate")
    ui.inset:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -87)
    ui.inset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
    ui.body:SetPoint("TOPLEFT", ui.inset, "TOPLEFT", 10, -10)
    ui.body:SetPoint("BOTTOMRIGHT", ui.inset, "BOTTOMRIGHT", -10, 10)
    refresh()
    styleFrame()
end

local function onAddonMessage(prefix, message, channel, sender)
    if prefix ~= PREFIX or channel ~= "GUILD" or not sender then return end
    sender = string.gsub(sender, "%-.*$", "")
    if sender == playerName() then return end
    local p = split(message)
    if p[1] == "S" and #p >= 6 then
        local rec = DPTL_DB.kills[sender] or { daily = {}, weekly = {} }
        rec.daily = { [p[2]] = toNumber(p[4]) }
        rec.weekly = { [p[3]] = toNumber(p[5]) }
        rec.total = toNumber(p[6]); rec.receivedAt = time()
        DPTL_DB.kills[sender] = rec
        if ui.tab == "kills" then refresh() end
    elseif p[1] == "T" and #p >= 9 then
        local id = tonumber(p[2])
        if id and ownedTargetCount(sender) < MAX_TARGETS then
            local t = { id = id, owner = sender, name = p[3], gold = p[4], silver = p[5],
                copper = p[6], reward = p[7], proof = p[8], created = tonumber(p[9]) or time() }
            DPTL_DB.targets[targetKey(sender, id)] = t
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
        ownStats()
        syncLifetimeKills()
    elseif event == "PLAYER_LOGIN" then
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
    elseif event == "CHAT_MSG_ADDON" then
        onAddonMessage(...)
    elseif event == "PLAYER_PVP_KILLS_CHANGED" then
        -- This event represents the player's own honorable kill credit. Forever may
        -- withhold the victim name, so only store a name if the event's unit token resolves safely.
        local unitTarget = ...
        local victim
        if type(unitTarget) == "string" then
            local ok, name = pcall(UnitName, unitTarget)
            if ok and type(name) == "string" and name ~= "" then victim = name end
        end
        recordKill(victim or "")
        syncLifetimeKills()
        DPTL_DB.pendingStats = true
        if ui.tab == "kills" then refresh() end
        sharePendingStats()
    elseif event == "PLAYER_REGEN_ENABLED" then
        sharePendingStats()
    end
end)

-- WoW Forever's Addon Compartment entry is also collected by IconBag.
function DPTL_AddonCompartmentClick()
    if not ui.frame then buildUI() end
    if ui.frame:IsShown() then ui.frame:Hide() else refresh(); ui.frame:Show() end
end
