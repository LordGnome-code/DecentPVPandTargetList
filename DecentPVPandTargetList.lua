-- Decent PvP and Target List: WoW Forever (modern client) compatible.
local ADDON, ns = ...
local PREFIX = "DPTL2"
local MAX_TARGETS = 3
local RACES = { "Human", "Orc", "Dwarf", "Night Elf", "Undead", "Tauren", "Gnome", "Troll", "Blood Elf", "Draenei" }
local CLASSES = { "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Death Knight", "Shaman", "Mage", "Warlock", "Monk", "Druid", "Demon Hunter", "Evoker" }
local DB_DEFAULTS = { kills = {}, targets = {}, nextId = 1, layout = "normal", pendingStats = false, pendingTargets = {}, windowWidth = 590, windowHeight = 480 }
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
local function thisWeek() return date("%Y%W") end
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
    if not guildReady() then return false, "Join a guild first." end
    if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then
        return false, "This client does not expose guild addon messaging."
    end
    local restriction = chatRestrictionReason()
    if restriction then return false, "Guild message blocked before sending: " .. restriction .. "." end
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

local ui = { rows = {}, tab = "kills" }
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
local function row(text, y)
    return label(ui.body, text, 6, y, 510)
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
    local bodyWidth = math.max(546, ui.body:GetWidth())
    local bodyHeight = math.max(361, ui.body:GetHeight())
    if ui.tab ~= "targets" and ui.targetScroll then ui.targetScroll:Hide() end
    if ui.tab == "kills" then
        label(ui.body, "Guild rankings — credited honorable kills are tracked automatically.", 6, 0, bodyWidth - 12)
        local categories = { { "Daily", 1 }, { "Weekly", 2 }, { "All time", 3 } }
        local columnWidth = (bodyWidth - 12) / 3
        for column, category in ipairs(categories) do
            local x = 6 + (column - 1) * columnWidth
            local header = label(ui.body, category[1] .. " top 10", x, -26, columnWidth - 8)
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
                label(ui.body, string.format("%2d. %-16s %d", i,
                    string.sub(list[i].name, 1, 16), list[i].value), x, -48 - (i - 1) * 23, columnWidth - 8)
            end
        end
        local toolsY = -bodyHeight + 75
        label(ui.body, "Add a missed kill manually (optional victim name).", 6, toolsY, bodyWidth - 12)
        ui.victimBox = edit(ui.body, "Defeated player (optional)", 6, toolsY - 21, 175)
        button(ui.body, "Record kill", 195, toolsY - 21, 96, function()
            if InCombatLockdown and InCombatLockdown() then
                info("Record kills after combat ends."); return
            end
            recordKill(ui.victimBox:GetText())
            local ok, err = shareStats()
            refresh()
            if ok then info("Kill recorded and guild stats shared.") else info("Kill recorded locally. " .. err) end
        end)
        button(ui.body, "Share stats", 302, toolsY - 21, 96, function()
            local ok, err = shareStats()
            if ok then info("Guild stats shared.") else info(err) end
        end)
    elseif ui.tab == "targets" then
        row("Guild targets — only the creator can remove their entries.", 0)
        local targets = {}
        for _, t in pairs(DPTL_DB.targets) do table.insert(targets, t) end
        table.sort(targets, function(a, b) return (a.created or 0) > (b.created or 0) end)
        local listTop = -25
        local formTop = -bodyHeight + 211
        local contentWidth = math.max(470, bodyWidth - 40)
        if not ui.targetScroll then
            ui.targetScroll = CreateFrame("ScrollFrame", "DPTLTargetScroll", ui.body, "UIPanelScrollFrameTemplate")
            ui.targetContent = CreateFrame("Frame", nil, ui.targetScroll)
            ui.targetScroll:SetScrollChild(ui.targetContent)
        end
        ui.targetScroll:ClearAllPoints()
        ui.targetScroll:SetPoint("TOPLEFT", ui.body, "TOPLEFT", 2, listTop)
        ui.targetScroll:SetPoint("BOTTOMRIGHT", ui.body, "TOPRIGHT", -24, formTop - 10)
        ui.targetScroll:Show()
        for _, old in ipairs(ui.targetRows or {}) do old:Hide(); old:SetParent(nil) end
        ui.targetRows = {}
        for index, target in ipairs(targets) do
            local y = -((index - 1) * 48)
            local rowFrame = CreateFrame("Frame", nil, ui.targetContent)
            rowFrame:SetSize(contentWidth, 44); rowFrame:SetPoint("TOPLEFT", ui.targetContent, "TOPLEFT", 0, y)
            local raceIcon = rowFrame:CreateTexture(nil, "ARTWORK")
            raceIcon:SetSize(28, 28); raceIcon:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", 0, -2)
            raceIcon:SetTexture(racePortrait(target.race) or "Interface\\Icons\\INV_Misc_QuestionMark")
            local classIcon = rowFrame:CreateTexture(nil, "ARTWORK")
            classIcon:SetSize(28, 28); classIcon:SetPoint("TOPLEFT", raceIcon, "TOPRIGHT", 3, 0)
            local atlas = target.class and ("class-icon-" .. string.lower(target.class:gsub(" ", "")))
            if atlas and classIcon.SetAtlas then classIcon:SetAtlas(atlas) else classIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark") end
            local reward = target.reward
            if reward == "" then reward = string.format("%sg %ss %sc", target.gold, target.silver, target.copper) end
            local details = rowFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            details:SetPoint("TOPLEFT", classIcon, "TOPRIGHT", 7, 0)
            details:SetWidth(contentWidth - 154); details:SetJustifyH("LEFT")
            details:SetText(string.format("%s (%s %s) | %s\nSubmitted by %s | Reward: %s | Proof: %s",
                target.name, target.race or "?", target.class or "?", date("%b %d", target.created or time()),
                target.owner or "Unknown", reward, target.proof or ""))
            if target.owner == playerName() then
                local remove = button(rowFrame, "Remove", contentWidth - 72, -8, 64, function()
                    local key = targetKey(target.owner, target.id)
                    if DPTL_DB.pendingTargets[key] then
                        DPTL_DB.pendingTargets[key] = nil
                        DPTL_DB.targets[key] = nil
                        info("Pending target removed locally; it was not shared.")
                    else
                        local ok, err = sendGuild(table.concat({ "D", target.id }, "|"))
                        if not ok then info(err); return end
                        DPTL_DB.targets[key] = nil
                    end
                    refresh()
                end)
                table.insert(ui.targetRows, remove)
            end
            table.insert(ui.targetRows, rowFrame)
        end
        ui.targetContent:SetSize(contentWidth, math.max(1, #targets * 48))
        ui.targetScroll:SetVerticalScroll(0)
        local y = formTop
        if not guildReady() then row("Join a guild to share targets and rankings.", y); y = y - 24 end
        if ownedTargetCount(playerName()) >= MAX_TARGETS then
            row("You have reached the limit of 3 active targets.", y)
        else
            label(ui.body, "Create target", 6, y, 100); y = y - 22
            ui.enemy = edit(ui.body, "Enemy player", 6, y, 130)
            ui.targetRace = dropdown(ui.body, "Race", RACES, 148, y, 130, RACES[1])
            ui.targetClass = dropdown(ui.body, "Class", CLASSES, 292, y, 130, CLASSES[1])
            local fieldsY = y - 58
            ui.gold = edit(ui.body, "Gold", 6, fieldsY, 48)
            ui.silver = edit(ui.body, "Silver", 62, fieldsY, 48)
            ui.copper = edit(ui.body, "Copper", 118, fieldsY, 48)
            ui.reward = edit(ui.body, "Or reward text", 174, fieldsY, 145)
            ui.proof = edit(ui.body, "Proof required", 328, fieldsY, 150)
            button(ui.body, "Create", 6, fieldsY - 52, 90, function()
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
                    info("Target saved locally; guild sharing is pending. " .. err)
                end
                refresh()
            end)
        end
    else
        if ui.targetScroll then ui.targetScroll:Hide() end
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
    if ui.settingsButton then
        ui.settingsButton:SetAlpha(ui.tab == "settings" and 1 or 0.82)
    end
end

local function buildUI()
    if ui.frame then return end
    local f = CreateFrame("Frame", "DPTLMainFrame", UIParent, "BackdropTemplate")
    ui.frame = f
    local savedWidth = math.max(590, math.min(1100, tonumber(DPTL_DB.windowWidth) or 590))
    local savedHeight = math.max(480, math.min(900, tonumber(DPTL_DB.windowHeight) or 480))
    f:SetSize(savedWidth, savedHeight); f:SetPoint("CENTER"); f:SetMovable(true); f:SetResizable(true)
    if f.SetResizeBounds then f:SetResizeBounds(590, 480, 1100, 900)
    else f:SetMinResize(590, 480); f:SetMaxResize(1100, 900) end
    f:SetClampedToScreen(true)
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
    local settingsButton = CreateFrame("Button", nil, f)
    settingsButton:SetSize(24, 24)
    settingsButton:SetPoint("RIGHT", close, "LEFT", -2, 0)
    settingsButton:SetFrameLevel(f:GetFrameLevel() + 5)
    settingsButton:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
    settingsButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    settingsButton:SetScript("OnClick", function()
        if ui.tab == "settings" then
            selectTab(ui.previousTab or "kills")
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
        refresh()
    end)
    ui.resizeGrip = resizeGrip
    refresh()
    styleFrame()
end

local function onAddonMessage(prefix, message, channel, sender)
    if prefix ~= PREFIX or channel ~= "GUILD" or not sender then return end
    if isPlayerSender(sender) then return end
    sender = string.gsub(sender, "%-.*$", "")
    local p = split(message)
    if p[1] == "S" and #p >= 6 then
        local rec = DPTL_DB.kills[sender] or { daily = {}, weekly = {} }
        rec.daily = { [p[2]] = toNumber(p[4]) }
        rec.weekly = { [p[3]] = toNumber(p[5]) }
        rec.total = toNumber(p[6]); rec.receivedAt = time()
        DPTL_DB.kills[sender] = rec
        if ui.tab == "kills" then refresh() end
    elseif p[1] == "T" and #p >= 11 then
        local id = tonumber(p[2])
        if id and ownedTargetCount(sender) < MAX_TARGETS then
            local t = { id = id, owner = sender, name = p[3], gold = p[4], silver = p[5],
                copper = p[6], reward = p[7], proof = p[8], created = tonumber(p[9]) or time(),
                race = p[10], class = p[11] }
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
        migratePlayerIdentity()
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
        sharePendingTargets()
    end
end)

-- WoW Forever's Addon Compartment entry is also collected by IconBag.
function DPTL_AddonCompartmentClick()
    if not ui.frame then buildUI() end
    if ui.frame:IsShown() then ui.frame:Hide() else refresh(); ui.frame:Show() end
end
