-- Player faction/rank annotations for the shared unit tooltip.
local annotations = setmetatable({}, { __mode = "k" })
local pending = setmetatable({}, { __mode = "k" })
local hookedElvUI

local function readable(value)
    return not issecretvalue or not issecretvalue(value)
end

local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok and readable(value) then return value end
    return nil
end

local function rankTitle(rank, faction, unit)
    if rank == 0 then return PVP_RANK_0_NAME or "Unranked" end
    local first = Enum and Enum.PvPRanks and Enum.PvPRanks.Rank_1
    if not first then return nil end
    return safe(GetText, "PVP_RANK_" .. (first + rank - 1) .. "_"
        .. (faction == "Alliance" and 1 or 0), safe(UnitSex, unit) or 2)
end

local function rankInfo(unit, faction)
    -- Only the player's own major-faction progression is available through this API.
    if safe(UnitIsUnit, unit, "player") == true then
        local p = safe(C_MajorFactions and C_MajorFactions.GetMajorFactionProgressionInfo, 2800)
        local rank = p and p.renownLevel
        if readable(rank) and type(rank) == "number" and rank >= 0 and rank <= 14 then
            return rank, rankTitle(rank, faction, unit)
        end
    end

    -- Capability checked: this legacy API is absent on some Forever builds.
    local raw = safe(UnitPVPRank, unit)
    if type(raw) == "number" then
        if type(GetPVPRankInfo) == "function" then
            local ok, name, rank = pcall(GetPVPRankInfo, raw, unit)
            if ok and readable(rank) and type(rank) == "number" and rank >= 0 and rank <= 14 then
                return rank, readable(name) and name or rankTitle(rank, faction, unit)
            end
        else
            local first = Enum and Enum.PvPRanks and Enum.PvPRanks.Rank_1
            if first then
                local rank = raw == 0 and 0 or raw - first + 1
                if rank >= 0 and rank <= 14 then return rank, rankTitle(rank, faction, unit) end
            end
        end
    end

    -- A selected PvP title is evidence of that title, not proof of current-season rank.
    local decorated, name = safe(UnitPVPName, unit), safe(UnitName, unit)
    if type(decorated) == "string" and type(name) == "string" and decorated ~= name then
        for rank = 14, 1, -1 do
            local title = rankTitle(rank, faction, unit)
            if type(title) == "string" and title ~= "" then
                local prefix, suffix = title .. " ", ", " .. title
                if decorated:sub(1, #prefix) == prefix or decorated:sub(-#suffix) == suffix then
                    return rank, title, true
                end
            end
        end
    end
end

local function plain(text)
    return text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        :gsub("|T.-|t", ""):gsub("|A.-|a", ""):match("^%s*(.-)%s*$")
end

local function decorate(tt, hintUnit)
    if not tt or safe(tt.IsForbidden, tt) == true or safe(tt.IsShown, tt) ~= true then return end
    local ok, _, unit = pcall(tt.GetUnit, tt)
    if not ok or not readable(unit) then return end
    unit = unit or hintUnit
    if type(unit) ~= "string" or safe(UnitIsPlayer, unit) ~= true then return end
    local factionOK, faction, localized = pcall(UnitFactionGroup, unit)
    if not factionOK or not readable(faction) or not readable(localized)
        or (faction ~= "Horde" and faction ~= "Alliance") then return end
    localized = localized or (faction == "Horde" and FACTION_HORDE or FACTION_ALLIANCE) or faction
    local rank, title, fromTitle = rankInfo(unit, faction)
    -- Use the requested civilian label when no readable rank is supplied.
    local detail = "Unranked Civilian"
    if rank then
        detail = rank == 0 and "Unranked Civilian" or ("Rank " .. rank .. (title and " - " .. title or ""))
        if fromTitle then detail = detail .. " (title)" end
    end
    local suffix = "  |cffffd100" .. detail .. "|r"
    local tooltipName = safe(tt.GetName, tt)
    local count = safe(tt.NumLines, tt)
    if type(tooltipName) ~= "string" or type(count) ~= "number" then return end
    local previous = annotations[tt]
    for i = 2, count do
        local line = _G[tooltipName .. "TextLeft" .. i]
        local value = line and safe(line.GetText, line)
        if type(value) == "string" then
            local stripped = plain(value)
            local existing = previous and value == previous.rendered
            if existing or stripped == localized or stripped == faction then
                local base = existing and previous.base or value
                local rendered = base .. suffix
                if value ~= rendered then
                    line:SetText(rendered)
                    line:Show()
                    annotations[tt] = { base = base, rendered = rendered }
                    tt:Show() -- Recalculate width for the longer faction line.
                end
                return
            end
        end
    end
    -- Tooltip customizations can hide faction text. Supply one combined row in that case.
    local rendered = localized .. suffix
    tt:AddLine(rendered, .8, .8, .8)
    annotations[tt] = { base = localized, rendered = rendered }
    tt:Show()
end

local function update(tt, unit)
    -- Restriction checks inside the callback prevent inspecting secret unit/text values.
    pcall(decorate, tt, unit)
end

local function queueUpdate(tt)
    if not tt or pending[tt] or not C_Timer or not C_Timer.After then return end
    pending[tt] = true
    C_Timer.After(0, function()
        pending[tt] = nil
        update(tt) -- Resolve the tooltip's current unit; never retain a mouseover token.
    end)
end

local function hookElvUI()
    if hookedElvUI or type(ElvUI) ~= "table" then return end
    local engine = ElvUI[1]
    local module = engine and safe(engine.GetModule, engine, "Tooltip", true)
    if not module or type(module.SetUnitInfo) ~= "function" then return end
    hooksecurefunc(module, "SetUnitInfo", function(_, tt, unit)
        update(tt, unit)
        queueUpdate(tt)
    end)
    hookedElvUI = true
end

if GameTooltip then
    GameTooltip:HookScript("OnTooltipCleared", function(tt) annotations[tt] = nil end)
    GameTooltip:HookScript("OnShow", function(tt) queueUpdate(tt) end)
    local typeUnit = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and typeUnit then
        TooltipDataProcessor.AddTooltipPostCall(typeUnit, function(tt)
            if tt == GameTooltip then update(tt); queueUpdate(tt) end
        end)
    elseif safe(GameTooltip.HasScript, GameTooltip, "OnTooltipSetUnit") == true then
        GameTooltip:HookScript("OnTooltipSetUnit", function(tt) update(tt); queueUpdate(tt) end)
    end
    hookElvUI()
    local events = CreateFrame("Frame")
    events:RegisterEvent("ADDON_LOADED")
    events:RegisterEvent("PLAYER_LOGIN")
    events:SetScript("OnEvent", function() hookElvUI() end)
end
