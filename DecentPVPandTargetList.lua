-- Decent PvP and Target List: WoW Forever / Wrath-era API compatible.
local ADDON, ns = ...
local PREFIX = "DPTL1"
local SYNC_SECONDS = 300
local MAX_TARGETS = 3
local DB_DEFAULTS = { kills = {}, targets = {}, nextId = 1, layout = "normal" }

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
local function sendGuild(msg)
    if guildReady() and SendAddonMessage then SendAddonMessage(PREFIX, msg, "GUILD") end
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
        DPTL_DB.kills[name] = { total = 0, daily = {}, weekly = {}, sentAt = 0 }
    end
    return DPTL_DB.kills[name]
end

local function counts(rec)
    return toNumber(rec.daily and rec.daily[today()]),
        toNumber(rec.weekly and rec.weekly[thisWeek()]), toNumber(rec.total)
end

local function syncStats(force)
    if not guildReady() then return end
    local rec, now = ownStats(), time()
    if force or now - (rec.sentAt or 0) >= SYNC_SECONDS then
        local d, w, a = counts(rec)
        sendGuild(table.concat({ "S", today(), thisWeek(), d, w, a }, "|"))
        rec.sentAt = now
    end
end

local function recordKill()
    local rec = ownStats()
    local d, w = today(), thisWeek()
    rec.total = toNumber(rec.total) + 1
    rec.daily[d] = toNumber(rec.daily[d]) + 1
    rec.weekly[w] = toNumber(rec.weekly[w]) + 1
    for key in pairs(rec.daily) do if key ~= d then rec.daily[key] = nil end end
    for key in pairs(rec.weekly) do if key ~= w then rec.weekly[key] = nil end end
    rec.sentAt = 0
end

local function targetKey(owner, id) return owner .. ":" .. tostring(id) end
local function ownedTargetCount(owner)
    local count = 0
    for _, t in pairs(DPTL_DB.targets) do if t.owner == owner then count = count + 1 end end
    return count
end

local function broadcastTarget(t)
    sendGuild(table.concat({ "T", t.id, safe(t.name, 35), safe(t.gold, 8), safe(t.silver, 4),
        safe(t.copper, 4), safe(t.reward, 40), safe(t.proof, 40), t.created }, "|"))
end

local root = CreateFrame("Frame")
root:RegisterEvent("ADDON_LOADED")
root:RegisterEvent("PLAYER_LOGIN")
root:RegisterEvent("CHAT_MSG_ADDON")
root:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

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

local function styleFrame()
    if not ui.frame then return end
    if DPTL_DB.layout == "blizzlike" then
        ui.frame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true,
            tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
    else
        ui.frame:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true,
            tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        ui.frame:SetBackdropColor(0.035, 0.055, 0.08, 0.97)
    end
end

local function refresh()
    clearRows()
    if ui.tab == "kills" then
        label(ui.body, "Guild rankings — members share snapshots every five minutes.", 6, 0, 510)
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
                    DPTL_DB.targets[targetKey(t.owner, t.id)] = nil
                    sendGuild(table.concat({ "D", t.id }, "|"))
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
                DPTL_DB.targets[targetKey(t.owner, id)] = t
                broadcastTarget(t); refresh()
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
        button(ui.body, "Sync now", 6, -68, 90, function()
            syncStats(true); info("Guild stats sent.")
        end)
        row("PvP kills are counted from combat log hostile player deaths caused by you.", -108)
        row("Guild data syncs only while logged in and in a guild.", -132)
    end
end

local function buildUI()
    if ui.frame then return end
    local f = CreateFrame("Frame", "DPTLMainFrame", UIParent)
    ui.frame = f; f:SetSize(560, 430); f:SetPoint("CENTER"); f:SetMovable(true)
    f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    f:Hide(); styleFrame()
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -14); title:SetText("Decent PvP & Target List")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)
    button(f, "Kill Rankings", 16, -40, 110, function() ui.tab = "kills"; refresh() end)
    button(f, "Guild Targets", 132, -40, 110, function() ui.tab = "targets"; refresh() end)
    button(f, "Settings", 248, -40, 90, function() ui.tab = "settings"; refresh() end)
    ui.body = CreateFrame("Frame", nil, f)
    ui.body:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -72)
    ui.body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 14)
    refresh()
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
    elseif event == "PLAYER_LOGIN" then
        if RegisterAddonMessagePrefix then RegisterAddonMessagePrefix(PREFIX) end
        buildUI()
        SLASH_DPTL1 = "/dptl"
        SLASH_DPTL2 = "/targetlist"
        SlashCmdList.DPTL = function()
            if ui.frame:IsShown() then ui.frame:Hide() else refresh(); ui.frame:Show() end
        end
        syncStats(true)
        self.elapsed = 0
        self:SetScript("OnUpdate", function(frame, elapsed)
            frame.elapsed = frame.elapsed + elapsed
            if frame.elapsed >= 30 then frame.elapsed = 0; syncStats(false) end
        end)
    elseif event == "CHAT_MSG_ADDON" then
        onAddonMessage(...)
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        -- Wrath 3.3.5 combat-log payload: timestamp, event, source GUID/name/flags,
        -- then destination GUID/name/flags (Retail adds fields this client lacks).
        local _, subevent, sourceGUID, _, _, _, destName, destFlags = ...
        if subevent == "UNIT_DIED" and sourceGUID == UnitGUID("player") and destName
            and bit and bit.band(destFlags or 0, 0x00000400) ~= 0
            and bit.band(destFlags or 0, 0x00000100) ~= 0
            and bit.band(destFlags or 0, 0x00000040) ~= 0 then
            recordKill()
            if ui.tab == "kills" then refresh() end
            syncStats(false)
        end
    end
end)
