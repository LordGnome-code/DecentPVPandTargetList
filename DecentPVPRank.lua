-- DecentPVPRank: original Forever PvP tracker. No external libraries required.
local addonName = ...
local FACTION_ID, HONOR_ID = 2800, 1792
local db, character, window, settings, mini, minimapButton
local current, lastError, pendingMatch
local session = { points = 0, honor = 0, matches = 0, wins = 0 }
local themes = { Horde = { .82, .16, .19 }, Alliance = { .16, .42, .88 } }
local refresh, applyTheme, openSettings
local selectedTab = "Rank Points"
local historyPage = 1
local selectTab
local extraBars = {}
local trackerChecks = {}
local syncTrackers
local syncingTrackers
local appliedBlizzardStyle
local embeddedMode, embeddedParent = false, nil
local function resizeExtraBars()
    for key, b in pairs(extraBars) do
        local size = db.extraSizes[key]
        b:SetScale(1)
        b:SetSize(size.width, size.height)
        b.label:SetScale(math.min(1, size.height / 18))
        b.label:SetWidth((size.width - 8) / math.min(1, size.height / 18))
    end
end
local RP_SOURCES = "HOW TO EARN RANK POINTS\nComplete battlegrounds and PvP quests that list Rank Points as a reward. Complete the PvP season journey's weekly tasks for additional RP. Highlighted battlegrounds give bonus RP during their holiday week.\n\nJoin battlegrounds through the game's PvP queue or a battlemaster; check your quest rewards and season journey for tasks. Rank gains stop at the current weekly ceiling."
local HONOR_SOURCES = "HOW TO EARN HONOR\nDefeat enemy players in PvP, complete battlegrounds, and turn in PvP quests that award Honor. The PvP season journey's weekly tasks also grant Honor. Highlighted battlegrounds award increased Honor during their holiday week.\n\nQueue for a battleground or take part in world PvP. Check quest rewards for Honor awards. Spend Honor at PvP vendors before the wallet cap is reached."
local function message(text)
    print("|cffa070ffDecent PvP Rank:|r " .. text)
end
local function readable(value)
    return not issecretvalue or not issecretvalue(value)
end
local function number(value)
    if readable(value) and type(value) == "number" then return value end
end
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok and readable(value) then return value end
end
local function totalFor(rank)
    if not rank then return nil end
    return number(call(C_MajorFactions and C_MajorFactions.GetTotalReputationForRenownLevel, FACTION_ID, rank))
end
local function title(rank)
    if rank == 0 then return PVP_RANK_0_NAME or "Unranked" end
    local first = Enum and Enum.PvPRanks and Enum.PvPRanks.Rank_1
    if first and GetText then
        local key = "PVP_RANK_" .. (first + rank - 1) .. "_" .. (UnitFactionGroup("player") == "Alliance" and 1 or 0)
        return GetText(key, UnitSex("player")) or ("Rank " .. rank)
    end
    return "Rank " .. rank
end
local function fmt(value)
    return value and tostring(math.floor(value)) or "?"
end
local function duration(seconds)
    if not seconds then return "Unknown" end
    return string.format("%dh %02dm", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
end
local function read()
    local p = call(C_MajorFactions and C_MajorFactions.GetMajorFactionProgressionInfo, FACTION_ID)
    if not p then return nil end
    local rank, points, threshold = number(p.renownLevel), number(p.renownReputationEarned), number(p.renownLevelThreshold)
    local maxRank, capRank = number(p.maxLevel), number(p.currentWeekProgressiveMaxLevel)
    if not rank or not points or not threshold or not maxRank then return nil end
    local base = totalFor(rank)
    if not base then return nil end
    local h = call(C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo, HONOR_ID)
    local capped = call(C_MajorFactions and C_MajorFactions.IsWeeklyRenownCapped, FACTION_ID)
    return {
        rank = rank, points = points, threshold = threshold, maxRank = maxRank,
        total = base + points, cap = totalFor(capRank), capRank = capRank,
        honor = h and number(h.quantity), honorCap = h and number(h.maxQuantity),
        capped = readable(capped) and capped == true,
        week = number(p.weekNumber), season = number(call(GetCurrentArenaSeason)),
    }
end
local function text(parent, x, y, value, font)
    local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    label:SetPoint("TOPLEFT", x, y)
    label:SetText(value or "")
    label:SetJustifyH("LEFT")
    return label
end
local function button(parent, x, y, width, label, action)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 24)
    b:SetPoint("TOPLEFT", x, y)
    b:SetText(label)
    b:SetScript("OnClick", action)
    return b
end
local function tooltip(frame, heading, body)
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(heading, 1, .82, 0)
        local content = type(body) == "function" and body() or body
        GameTooltip:AddLine(content or "No data available yet.", .9, .9, .9, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame:HookScript("OnHide", function(self)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    return frame
end
local function metric(parent, y, label, description)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", 0, y)
    row:SetSize(530, 26)
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(1, 1, 1, .035)
    text(row, 8, -7, label, "GameFontHighlightSmall")
    row.value = text(row, 215, -7, "--", "GameFontNormalSmall")
    row.value:SetWidth(305); row.value:SetJustifyH("RIGHT")
    tooltip(row, label, description)
    return row.value, row
end
local function panel(name, width, height)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetSize(width, height)
    f:SetPoint("CENTER")
    f:SetClampedToScreen(true)
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    -- Keep native window art opaque even where the artwork has transparent pixels.
    f.opaqueFill = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    f.opaqueFill:SetPoint("TOPLEFT", 8, -8)
    f.opaqueFill:SetPoint("BOTTOMRIGHT", -8, 8)
    f.opaqueFill:SetColorTexture(.035, .035, .035, 1)
    f.opaqueFill:Hide()
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if not db.locked then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relative, x, y = self:GetPoint()
        db.positions[name] = { point, relative, x, y }
    end)
    local pos = db.positions[name]
    if pos then f:ClearAllPoints(); f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) end
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -3, -3)
    f.close = close
    table.insert(UISpecialFrames, name)
    return f
end
local function bar(parent, y)
    local b = CreateFrame("StatusBar", nil, parent)
    b:SetPoint("TOPLEFT", 20, y)
    b:SetSize(parent:GetWidth() - 40, 23)
    b:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    b:SetMinMaxValues(0, 1)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(.025, .025, .035, .9)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.label:SetPoint("CENTER")
    return b
end
local function setBar(b, value, maximum, label)
    b:SetMinMaxValues(0, maximum and maximum > 0 and maximum or 1)
    b:SetValue(value or 0)
    b.label:SetText(label)
end
local function toggle(f) f:SetShown(not f:IsShown()) end
local function applyLayout()
    if appliedBlizzardStyle == db.blizzardUI and not embeddedMode then return end
    appliedBlizzardStyle = db.blizzardUI
    local classic = db.blizzardUI
    for _, f in ipairs({ window, settings, mini }) do
        f:SetBackdrop(classic and {
            bgFile = "Interface\\FrameGeneral\\UI-Background-Rock",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 64, edgeSize = 32,
            insets = { left = 8, right = 8, top = 8, bottom = 8 },
        } or {
            bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2,
        })
        f.opaqueFill:SetShown(classic)
    end
    if embeddedMode and embeddedParent then
        local scale = math.max(.5, tonumber(db.scale) or 1)
        window:SetScale(scale)
        window:SetSize(embeddedParent:GetWidth() / scale, embeddedParent:GetHeight() / scale)
    else
        window:SetHeight(classic and 548 or 530)
    end
    window.headerArt:SetShown(classic and not embeddedMode)
    window.title:ClearAllPoints()
    if classic then window.title:SetPoint("TOP", window, "TOP", 0, -14)
    else window.title:SetPoint("TOPLEFT", 20, -17) end
    window.inset:ClearAllPoints()
    window.inset:SetPoint("TOPLEFT", 12, classic and -146 or -176)
    window.inset:SetSize(546, 306)
    window.inset:SetShown(not embeddedMode)
    window.inset:SetBackdrop(classic and {
        bgFile = "Interface\\FrameGeneral\\UI-Background-Marble", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 64, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 },
    } or { bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    local tabNames = window.subTabOrder or { "Rank Points", "Honor", "Matches", "Info" }
    local tabWidth = #tabNames > 4 and 100 or 125
    local tabGap = #tabNames > 4 and 7 or 10
    local firstTabX = math.max(10, (window:GetWidth() - (#tabNames * tabWidth + (#tabNames - 1) * tabGap)) / 2)
    for i, name in ipairs(tabNames) do
        local tab = window.tabs[name]
        tab:ClearAllPoints()
        local tabY = embeddedMode and -(window:GetHeight() - 40) or (classic and -450 or -148)
        tab:SetPoint("TOPLEFT", window, "TOPLEFT", firstTabX + (i - 1) * (tabWidth + tabGap), tabY)
        tab:SetSize(tabWidth, classic and 32 or 30)
        tab:SetBackdrop(not classic and {
            bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1,
        } or nil)
        tab:GetHighlightTexture():SetAlpha(classic and 0 or .06)
        tab:GetFontString():ClearAllPoints()
        tab:GetFontString():SetPoint("CENTER", tab, "CENTER", 0, 0)
        tab.join:ClearAllPoints()
        tab.join:SetPoint(classic and "TOPLEFT" or "BOTTOMLEFT", tab, classic and "TOPLEFT" or "BOTTOMLEFT", 1, 0)
        window.pages[name]:ClearAllPoints()
        local pageTop = classic and -160 or -190
        window.pages[name]:SetPoint("TOPLEFT", window, "TOPLEFT", 20, pageTop)
        if embeddedMode then
            window.pages[name]:SetSize(window:GetWidth() - 40, math.max(280, window:GetHeight() - 280))
        else
            window.pages[name]:SetSize(530, 280)
        end
    end
    window.footer:ClearAllPoints(); window.footer:SetPoint("TOPLEFT", 20, classic and -517 or -496)
    window.footer:SetShown(not embeddedMode)
    window.miniButton:ClearAllPoints()
    window.miniButton:SetPoint("TOPLEFT", 450, embeddedMode and -(window:GetHeight() - 92) or (classic and -509 or -488))
    window.miniButton:SetShown(not embeddedMode)
end
applyTheme = function()
    local color = db.color or themes[UnitFactionGroup("player")] or themes.Alliance
    applyLayout()
    for _, f in ipairs({ window, settings, mini }) do
        if f then
            if embeddedMode and f == window then
                f:SetBackdrop(nil)
                f.opaqueFill:Hide()
            elseif db.blizzardUI then
                f:SetBackdropColor(1, 1, 1, 1)
                f:SetBackdropBorderColor(1, 1, 1, 1)
            else
                f:SetBackdropColor(color[1] * .15 + .025, color[2] * .15 + .025, color[3] * .15 + .025, .96)
                f:SetBackdropBorderColor(color[1], color[2], color[3], 1)
            end
            if not (embeddedMode and f == window) then f:SetScale(db.scale) end
        end
    end
    for _, b in ipairs({ window.rankBar, mini.rankBar, extraBars.rp }) do
        b:SetStatusBarColor(color[1], color[2], color[3])
    end
    resizeExtraBars()
    window.title:SetTextColor(db.blizzardUI and 1 or .95, db.blizzardUI and .82 or .82, db.blizzardUI and 0 or .5)
    if embeddedMode then
        window.inset:Hide()
    elseif db.blizzardUI then
        window.inset:SetBackdropColor(1, 1, 1, 1)
        window.inset:SetBackdropBorderColor(.75, .75, .75, 1)
    else
        window.inset:SetBackdropColor(color[1] * .09 + .025, color[2] * .09 + .025, color[3] * .09 + .025, .98)
        window.inset:SetBackdropBorderColor(color[1], color[2], color[3], .8)
    end
    for name, tab in pairs(window.tabs) do
        local active = name == selectedTab
        if db.blizzardUI then
            tab:GetFontString():SetPoint("CENTER", tab, "CENTER", 0, active and -3 or 2)
            tab:GetFontString():SetTextColor(1, active and 1 or .82, active and 1 or 0)
        else
            tab:SetBackdropColor(active and color[1] * .22 + .04 or .035,
                active and color[2] * .22 + .04 or .035, active and color[3] * .22 + .04 or .04, 1)
            tab:SetBackdropBorderColor(active and color[1] or .25, active and color[2] or .25, active and color[3] or .28, 1)
            tab:GetFontString():SetTextColor(active and 1 or .7, active and .92 or .7, active and .72 or .7)
        end
        for _, texture in ipairs(tab.nativeActive) do
            texture:SetShown(db.blizzardUI and active)
            texture:SetVertexColor(.85 + color[1] * .15, .85 + color[2] * .15, .85 + color[3] * .15)
        end
        for _, texture in ipairs(tab.nativeInactive) do texture:SetShown(db.blizzardUI and not active) end
        for _, texture in ipairs(tab.nativeHighlight) do texture:SetShown(db.blizzardUI and not active) end
        tab.join:SetColorTexture(color[1] * .09 + .025, color[2] * .09 + .025, color[3] * .09 + .025, 1)
        tab.join:SetShown(active and not db.blizzardUI)
        tab.activeMark:SetColorTexture(color[1], color[2], color[3], 1)
        tab.activeMark:SetShown(active and not db.blizzardUI)
    end
end
local function averages()
    local points, seconds, count = 0, 0, 0
    for _, m in ipairs(character.history) do
        -- Exclude cap-truncated samples from rank estimates.
        if m.points and m.points > 0 and not m.capped then
            points, seconds, count = points + m.points, seconds + m.seconds, count + 1
        end
    end
    if count > 0 then return points / count, seconds / count, count end
end
local function mapRates()
    local maps = {}
    for _, m in ipairs(character.history) do
        local entry = maps[m.map] or { name = m.map, games = 0, wins = 0, points = 0, seconds = 0, samples = 0 }
        maps[m.map] = entry
        entry.games = entry.games + 1
        if m.result == "Win" then entry.wins = entry.wins + 1 end
        if m.points and m.points > 0 and not m.capped then
            entry.points = entry.points + m.points
            entry.seconds = entry.seconds + m.seconds
            entry.samples = entry.samples + 1
        end
    end
    local list = {}
    for _, entry in pairs(maps) do table.insert(list, entry) end
    table.sort(list, function(a, b)
        local rateA = a.seconds > 0 and a.points / a.seconds or 0
        local rateB = b.seconds > 0 and b.points / b.seconds or 0
        if rateA == rateB then return a.name < b.name end
        return rateA > rateB
    end)
    return list
end
local function render()
    applyTheme()
    window.footer:SetText(InCombatLockdown() and "Combat: showing last available data"
        or "Hover bars, rows and ? for details. Drag the border to move.")
    if not current then
        window.status:SetText("Waiting for rank data...")
        return
    end
    local s = current
    window.status:SetText(string.format("Rank %d  -  %s", s.rank, title(s.rank)))
    window.badge:SetAtlas(s.rank > 0 and ("UI-Character-Info-Honor-Icon-" .. s.rank)
        or ("UI-Character-Info-Honor-Icon-" .. (UnitFactionGroup("player") or "Alliance")))
    local rankText = s.rank >= s.maxRank and "Maximum rank reached"
        or ("Rank Points   " .. fmt(s.points) .. " / " .. fmt(s.threshold))
    setBar(window.rankBar, s.points, s.threshold, rankText)
    setBar(mini.rankBar, s.points, s.threshold, "R" .. s.rank .. "   " .. fmt(s.points) .. " / " .. fmt(s.threshold) .. " RP")
    setBar(extraBars.rp, s.points, s.threshold, "R" .. s.rank .. "   " .. fmt(s.points) .. " / " .. fmt(s.threshold) .. " RP")
    for _, b in ipairs({ window.honorBar, mini.honorBar, extraBars.honor }) do
        setBar(b, s.honor, s.honorCap, "Honor   " .. fmt(s.honor) .. " / " .. fmt(s.honorCap))
    end
    local ratio = s.honor and s.honorCap and s.honorCap > 0 and s.honor / s.honorCap or 0
    for _, b in ipairs({ window.honorBar, mini.honorBar, extraBars.honor }) do
        b:SetStatusBarColor(ratio >= 1 and .95 or 1, ratio >= .9 and .35 or .72, .12)
    end
    local maximumTarget = math.max(1, s.maxRank)
    local target = math.max(1, math.min(db.target, maximumTarget))
    -- Keep the saved value aligned with the displayed target before stepping it.
    db.target = target
    local targetTotal = totalFor(target)
    local remaining = targetTotal and math.max(0, targetTotal - s.total)
    local avg, seconds, samples = averages()
    local games = remaining and avg and math.ceil(remaining / avg)
    window.rank.target:SetText(target .. " - " .. title(target))
    window.rank.minusButton:SetEnabled(target > 1)
    window.rank.plusButton:SetEnabled(target < maximumTarget)
    window.rank.remaining:SetText(fmt(remaining) .. " RP")
    window.rank.ceiling:SetText(s.capped and "CAPPED this week"
        or (s.cap and fmt(math.max(0, s.cap - s.total)) .. " RP to ceiling" or "Unknown"))
    window.rank.estimate:SetText(remaining == 0 and "Target reached"
        or (games and games .. " BGs / ~" .. duration(games * seconds) or "Waiting for completed BGs"))
    window.rank.rate:SetText(avg and (fmt(avg) .. " RP/BG | " .. fmt(avg / seconds * 3600) .. " RP/h") or "No usable samples yet")
    window.rank.note:SetText(targetTotal and s.cap and targetTotal > s.cap
        and "Target exceeds this week's ceiling." or ((samples or 0) .. " usable matches. Estimates exclude queue time."))
    local rates = mapRates()
    for i, row in ipairs(window.mapRows) do
        local m = rates[i]
        row.data = m
        row.name:SetText(m and m.name or (i == 1 and "Complete a BG to build estimates." or ""))
        row.wins:SetText(m and string.format("%d%%", m.wins / m.games * 100) or "")
        row.rate:SetText(m and m.samples > 0 and fmt(m.points / m.samples) or (m and "--" or ""))
        row.games:SetText(m and m.samples > 0 and remaining and fmt(math.ceil(remaining / (m.points / m.samples))) or (m and "--" or ""))
    end
    window.honor.wallet:SetText(fmt(s.honor) .. " / " .. fmt(s.honorCap))
    window.honor.room:SetText(s.honor and s.honorCap and fmt(math.max(0, s.honorCap - s.honor)) or "Unknown")
    window.honor.session:SetText("+" .. fmt(session.honor))
    window.honor.warning:SetText(ratio >= 1 and "Full - spend Honor" or (ratio >= .9 and "Nearly full" or "Room to earn Honor"))
    window.honor.matches:SetText(session.matches .. " BGs / " .. session.wins .. " wins")
    window.honor.rp:SetText("+" .. fmt(session.points))
    local count = #character.history
    local pages = math.max(1, math.ceil(count / 9))
    historyPage = math.min(historyPage, pages)
    for i, row in ipairs(window.matchRows) do
        local m = character.history[count - (historyPage - 1) * 9 - i + 1]
        row.data = m
        row.name:SetText(m and m.map or (count == 0 and i == 1 and "No completed battlegrounds yet." or ""))
        row.wins:SetText(m and m.result or "")
        row.rate:SetText(m and ("+" .. fmt(m.points)) or "")
        row.games:SetText(m and duration(m.seconds) or "")
    end
    window.historyPage:SetText("Page " .. historyPage .. " / " .. pages .. "  |  " .. count .. " matches")
    window.historyPrevious:SetEnabled(historyPage > 1)
    window.historyNext:SetEnabled(historyPage < pages)
    window.info.season:SetText(fmt(s.total) .. " RP")
    window.info.ceiling:SetText("Rank " .. fmt(s.capRank) .. " / " .. fmt(s.cap) .. " RP")
    window.info.week:SetText(fmt(s.week))
    window.info.reset:SetText(duration(number(call(C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset))))
    local rewards = call(C_MajorFactions and C_MajorFactions.GetRenownRewardsForLevel, FACTION_ID, math.min(s.rank + 1, s.maxRank))
    local descriptions = {}
    for _, reward in ipairs(rewards or {}) do
        if readable(reward.description) and reward.description then table.insert(descriptions, reward.description) end
    end
    window.rewardText = s.rank >= s.maxRank and "All ranks complete."
        or (#descriptions > 0 and table.concat(descriptions, "\n\n") or "See Character > PvP for rank rewards.")
    window.reward:SetText(window.rewardText)
    window.rewardScrollContent:SetHeight(math.max(115, window.reward:GetStringHeight() + 8))
    if db.alerts and ratio >= .9 and not character.honorWarned then
        message("Honor wallet is nearly full. Spend Honor before it overflows.")
        character.honorWarned = true
    elseif ratio < .85 then character.honorWarned = false end
    if db.alerts and s.capped and not character.capWarned then
        message("Weekly rank ceiling reached.")
        character.capWarned = true
    elseif not s.capped then character.capWarned = false end
end

local function updateMatch()
    local _, instanceType = IsInInstance()
    if instanceType == "pvp" and not character.active and current then
        character.active = { start = GetServerTime(), total = current.total, season = current.season,
            map = GetInstanceInfo() or "Battleground", capped = current.capped }
    end
    local active = character.active
    if not active then return end
    if instanceType == "pvp" then
        local winner = number(call(GetBattlefieldWinner))
        if winner and not active.result then
            local ownFaction = number(call(GetBattlefieldArenaFaction))
            if ownFaction == nil then ownFaction = UnitFactionGroup("player") == "Horde" and 0 or 1 end
            active.result = winner == ownFaction and "Win" or "Loss"
            active.finish = GetServerTime()
            pendingMatch = GetTime() + 3
        end
    elseif not active.result then
        character.active = nil -- Abandoned or joined without observing a result.
    else
        pendingMatch = pendingMatch or GetTime() + 3
    end
    if active.result and current and pendingMatch and GetTime() >= pendingMatch then
        if active.season == current.season and current.total >= active.total then
            local earned = current.total - active.total
            table.insert(character.history, { map = active.map, result = active.result,
                points = earned, seconds = math.max(1, active.finish - active.start),
                capped = active.capped or current.capped })
            if #character.history > 100 then table.remove(character.history, 1) end
            session.matches = session.matches + 1
            if active.result == "Win" then session.wins = session.wins + 1 end
        end
        -- Keep a sentinel until leaving to avoid recording the same scoreboard twice.
        character.active, pendingMatch = nil, nil
        character.finishedInstance = instanceType == "pvp"
    end
    if instanceType ~= "pvp" then character.finishedInstance = nil end
end
refresh = function()
    -- Restricted values are never inspected during combat. Keep the last readable snapshot.
    if InCombatLockdown() then
        window.footer:SetText("Combat: showing last available data")
        return
    end
    local ok, result = pcall(read)
    if not ok then lastError = tostring(result); return end
    if result then
        if current and current.season == result.season then
            session.points = session.points + math.max(0, result.total - current.total)
            if result.honor and current.honor then session.honor = session.honor + math.max(0, result.honor - current.honor) end
        end
        current = result
        character.snapshot = result
    end
    if not character.finishedInstance then updateMatch()
    else
        local _, kind = IsInInstance()
        if kind ~= "pvp" then character.finishedInstance = nil end
    end
    render()
end
local function colorPicker()
    local c = db.color or themes[UnitFactionGroup("player")] or themes.Alliance
    local previous = db.color and { unpack(db.color) }
    ColorPickerFrame:SetupColorPickerAndShow({
        r = c[1], g = c[2], b = c[3], hasOpacity = false,
        swatchFunc = function()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            db.color = { r, g, b }; applyTheme()
        end,
        cancelFunc = function() db.color = previous; applyTheme() end,
    })
end
local function checkbox(parent, y, label, key)
    local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    c:SetPoint("TOPLEFT", 18, y)
    text(parent, 54, y - 8, label)
    c:SetScript("OnShow", function(self) self:SetChecked(db[key]) end)
    c:SetScript("OnClick", function(self)
        db[key] = self:GetChecked()
        if key == "extraMini" and db.extraMini then
            db.mini, db.extraRP, db.extraHonor = true, true, true
        elseif (key == "extraRP" or key == "extraHonor") and db[key] then
            -- Restoring one bar must not depend on two other hidden visibility settings.
            db.mini, db.extraMini = true, true
        end
        if (key == "mini" or key == "extraMini") and db.mini and not db.extraRP and not db.extraHonor then
            db.extraRP, db.extraHonor = true, true
        end
        syncTrackers()
        if minimapButton then minimapButton:SetShown(db.minimap) end
        if key == "blizzardUI" then
            applyTheme()
            if DPTL_SetBlizzardLayout then DPTL_SetBlizzardLayout(db.blizzardUI) end
        end
    end)
    trackerChecks[key] = c
    return c
end
syncTrackers = function()
    syncingTrackers = true
    mini:SetShown(db.mini and not db.extraMini)
    extraBars.rp:SetShown(db.mini and db.extraMini and db.extraRP)
    extraBars.honor:SetShown(db.mini and db.extraMini and db.extraHonor)
    syncingTrackers = false
    for key, check in pairs(trackerChecks) do check:SetChecked(db[key]) end
end
local function sizeInput(parent, x, y, barKey, dimension, minimum, maximum)
    local input = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    input:SetPoint("TOPLEFT", x, y); input:SetSize(65, 24)
    input:SetAutoFocus(false); input:SetNumeric(true); input:SetMaxLetters(3)
    input:SetNumber(db.extraSizes[barKey][dimension])
    local function save(self)
        local value = tonumber(self:GetText())
        if value then db.extraSizes[barKey][dimension] = math.floor(math.max(minimum, math.min(maximum, value))) end
        self:SetNumber(db.extraSizes[barKey][dimension])
        resizeExtraBars()
    end
    input:SetScript("OnEnterPressed", function(self) save(self); self:ClearFocus() end)
    input:SetScript("OnEditFocusLost", save)
    input:SetScript("OnEscapePressed", function(self)
        self:SetNumber(db.extraSizes[barKey][dimension]); self:ClearFocus()
    end)
    tooltip(input, "Extra-mini " .. dimension,
        "Enter a value from " .. minimum .. " to " .. maximum .. " pixels and press Enter. Each bar has its own size, saved across reloads. Window scale does not change these bars.")
end
local function standaloneBar(name, key, offset)
    -- A StatusBar only: no backdrop, empty-track texture, or surrounding panel.
    local b = CreateFrame("StatusBar", name, UIParent)
    b:SetSize(280, 18)
    b:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    b:SetMinMaxValues(0, 1); b:SetValue(0)
    b:SetFrameStrata("MEDIUM")
    b:SetClampedToScreen(true); b:EnableMouse(true); b:SetMovable(true)
    b:RegisterForDrag("LeftButton")
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.label:SetPoint("CENTER"); b.label:SetShadowOffset(1, -1)
    b.label:SetText(key == "extraRP" and "Rank Points - waiting for data" or "Honor - waiting for data")
    local pos = db.positions[name]
    if pos then b:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else b:SetPoint("TOP", UIParent, "TOP", 0, offset) end
    b:SetScript("OnDragStart", function(self)
        if not db.locked then self.dragging = true; GameTooltip:Hide(); self:StartMoving() end
    end)
    b:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if not self.dragging then return end
        self.dragging = nil; self.lastDrag = GetTime()
        local point, _, relative, x, y = self:GetPoint()
        db.positions[name] = { point, relative, x, y }
    end)
    local close = CreateFrame("Button", nil, b)
    close:SetSize(18, 18); close:SetPoint("LEFT", b, "RIGHT", 2, 0)
    local label = close:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER"); label:SetText("x"); close:SetFontString(label)
    close:SetScript("OnClick", function() db[key] = false; syncTrackers() end)
    tooltip(close, "Close " .. (key == "extraRP" and "RP" or "Honor") .. " bar",
        "Hide only this bar. Restore it in Settings using Show extra-mini RP/Honor bar. Its saved position is kept.")
    b.close = close
    return b
end
local function buildMinimapButton()
    if not Minimap then return end
    local b = CreateFrame("Button", "DecentPVPRankMinimapButton", Minimap)
    minimapButton = b
    b:SetSize(32, 32)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(22, 22); icon:SetPoint("CENTER", 0, 1)
    icon:SetAtlas("UI-Character-Info-Honor-Icon-Horde")
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(54, 54); border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local function position()
        local angle = math.rad(db.minimapAngle)
        b:ClearAllPoints()
        b:SetPoint("CENTER", Minimap, "CENTER",
            math.cos(angle) * (Minimap:GetWidth() / 2 + 8),
            math.sin(angle) * (Minimap:GetHeight() / 2 + 8))
    end
    b:SetScript("OnDragStart", function(self)
        if db.locked then return end
        GameTooltip:Hide()
        self:SetScript("OnUpdate", function()
            local x, y = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            local centerX, centerY = Minimap:GetCenter()
            if not centerX or not centerY then return end
            db.minimapAngle = math.deg(math.atan2(y / scale - centerY, x / scale - centerX))
            position()
        end)
    end)
    b:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self.lastDrag = GetTime()
    end)
    b:SetScript("OnClick", function(self, mouse)
        if self.lastDrag and GetTime() - self.lastDrag < .15 then return end
        if mouse == "RightButton" then openSettings()
        elseif embeddedMode and DPTL_TogglePVP then DPTL_TogglePVP()
        else toggle(window) end
    end)
    tooltip(b, "Decent PvP Rank", function()
        return (current and ("Rank " .. current.rank .. " - " .. title(current.rank)
            .. "\nHonor: " .. fmt(current.honor) .. " / " .. fmt(current.honorCap) .. "\n\n") or "")
            .. (embeddedMode and "Left-click: open DecentPVP.\n" or "Left-click: toggle rank window.\n")
            .. "Right-click: settings.\nDrag: move around the minimap (when unlocked).\nHide with /dpr minimap or in Settings."
    end)
    Minimap:HookScript("OnSizeChanged", position)
    position()
    b:SetShown(db.minimap)
end
local function tableRow(parent, y)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", 0, y); row:SetSize(530, 22)
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(1, 1, 1, .025)
    row.name = text(row, 8, -5, "", "GameFontHighlightSmall")
    row.name:SetWidth(258)
    row.wins = text(row, 270, -5, "", "GameFontHighlightSmall"); row.wins:SetWidth(70)
    row.rate = text(row, 345, -5, "", "GameFontHighlightSmall"); row.rate:SetWidth(78)
    row.games = text(row, 435, -5, "", "GameFontHighlightSmall"); row.games:SetWidth(90)
    return row
end
local function nativeTabArt(tab, active, highlight)
    -- The same three-piece atlases used by Blizzard's PanelTabButtonTemplate.
    local prefix = active and "uiframe-activetab" or "uiframe-tab"
    local layer = highlight and "HIGHLIGHT" or "BACKGROUND"
    local left = tab:CreateTexture(nil, layer)
    local middle = tab:CreateTexture(nil, layer)
    local right = tab:CreateTexture(nil, layer)
    left:SetAtlas(prefix .. "-left", true)
    middle:SetAtlas("_" .. prefix .. "-center", true)
    right:SetAtlas(prefix .. "-right", true)
    left:SetPoint("TOPLEFT", tab, "TOPLEFT", active and -1 or -3, 0)
    right:SetPoint("TOPRIGHT", tab, "TOPRIGHT", active and 8 or 7, 0)
    middle:SetPoint("TOPLEFT", left, "TOPRIGHT")
    middle:SetPoint("TOPRIGHT", right, "TOPLEFT")
    middle:SetHorizTile(true)
    local textures = { left, middle, right }
    for _, texture in ipairs(textures) do
        if highlight then texture:SetBlendMode("ADD"); texture:SetAlpha(.4) end
        texture:Hide()
    end
    return textures
end
local function build()
    window = panel("DecentPVPRankWindow", 570, 530)
    window.headerArt = window:CreateTexture(nil, "BACKGROUND")
    window.headerArt:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    window.headerArt:SetSize(300, 64); window.headerArt:SetPoint("TOP", 0, 12)
    window.title = text(window, 20, -17, "DECENT PVP RANK", "GameFontNormalLarge")
    window.helpButton = tooltip(button(window, 420, -12, 28, "?", function()
        if selectedTab ~= "Info" then selectTab("Info") end
    end), "How to use Decent PvP Rank",
        "Rank Points: plan a target and compare your battleground rates.\n\nHonor: track your wallet and session gains.\n\nMatches: browse recorded results.\n\nInfo: weekly ceiling, reset and next rewards.\n\nGuild Kills: daily, weekly and lifetime guild rankings.")
    window.settingsButton = tooltip(button(window, 455, -12, 73, "Settings", function() openSettings() end),
        "Appearance and settings", "Choose a custom color, restore faction colors, lock positions, resize windows or toggle alerts.")
    window.badge = window:CreateTexture(nil, "ARTWORK")
    window.badge:SetSize(28, 28); window.badge:SetPoint("TOPLEFT", 20, -43)
    window.status = text(window, 58, -51, "Waiting for rank data...", "GameFontHighlight")
    window.status:SetWidth(470)
    window.rankBar, window.honorBar = bar(window, -80), bar(window, -108)
    window.inset = CreateFrame("Frame", nil, window, "BackdropTemplate")
    window.inset:SetFrameLevel(window:GetFrameLevel() + 1)
    window.tabs, window.pages = {}, {}
    window.subTabOrder = { "Rank Points", "Honor", "Matches", "Info" }
    if type(DPTL_BuildGuildKillsPage) == "function" then
        table.insert(window.subTabOrder, "Guild Kills")
    end
    for i, name in ipairs(window.subTabOrder) do
        local tabName = name
        local page = CreateFrame("Frame", nil, window)
        page:SetPoint("TOPLEFT", 20, -190); page:SetSize(530, 280)
        page:SetFrameLevel(window:GetFrameLevel() + 2)
        window.pages[name] = page
        local tab = CreateFrame("Button", nil, window, "BackdropTemplate")
        tab:SetPoint("TOPLEFT", 20 + (i - 1) * 135, -148); tab:SetSize(125, 30)
        tab:SetFrameLevel(window:GetFrameLevel() + 3)
        tab:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        local label = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("CENTER"); tab:SetFontString(label); tab:SetText(name)
        tab:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
        tab:GetHighlightTexture():SetVertexColor(1, 1, 1, 1)
        tab:GetHighlightTexture():SetAlpha(.06)
        tab.nativeActive = nativeTabArt(tab, true)
        tab.nativeInactive = nativeTabArt(tab, false)
        tab.nativeHighlight = nativeTabArt(tab, false, true)
        tab:SetScript("OnClick", function() selectTab(tabName) end)
        tab.join = tab:CreateTexture(nil, "OVERLAY"); tab.join:SetSize(123, 3)
        tab.activeMark = tab:CreateTexture(nil, "OVERLAY")
        tab.activeMark:SetPoint("TOPLEFT", 1, -1); tab.activeMark:SetSize(123, 2)
        window.tabs[name] = tab
        local descriptions = {
            ["Rank Points"] = "Target rank, points remaining and battleground estimates learned from your history.",
            Honor = "Honor held, room before the wallet cap, and this session's gains.",
            Matches = "Browse up to 100 recorded battlegrounds, newest first. Hover a result for sample details.",
            Info = "Season progress, the weekly rank ceiling, reset timer and next-rank rewards.",
            ["Guild Kills"] = "Daily, weekly and lifetime guild honorable-kill rankings.",
        }
        tooltip(tab, name, descriptions[name])
    end
    selectTab = function(name)
        selectedTab = name
        for tabName, page in pairs(window.pages) do page:SetShown(tabName == name) end
        if name == "Guild Kills" and type(DPTL_BuildGuildKillsPage) == "function" then
            DPTL_BuildGuildKillsPage(window.pages[name])
        end
        applyTheme()
    end
    local rank = window.pages["Rank Points"]
    window.rank = {}
    local targetValue, targetRow = metric(rank, 0, "Target rank", "Your personal rank goal. Use - / + to change it. The planner compares its cumulative Rank Point requirement to your season total.")
    window.rank.target = targetValue
    -- Leave space for target controls without overlapping the value.
    window.rank.target:SetWidth(225)
    -- Children of the hover row always receive clicks above its tooltip hit area.
    window.rank.minusButton = tooltip(button(targetRow, 450, -1, 32, "-", function()
        local maximum = math.max(1, current and current.maxRank or 14)
        db.target = math.max(1, math.min(db.target, maximum) - 1)
        render()
    end),
        "Lower target rank", "Choose the previous rank as your planning goal.")
    window.rank.plusButton = tooltip(button(targetRow, 490, -1, 32, "+", function()
        local maximum = math.max(1, current and current.maxRank or 14)
        db.target = math.min(maximum, math.max(1, db.target) + 1)
        render()
    end),
        "Raise target rank", "Choose the next rank as your planning goal.")
    window.rank.minusButton:SetFrameLevel(targetRow:GetFrameLevel() + 1)
    window.rank.plusButton:SetFrameLevel(targetRow:GetFrameLevel() + 1)
    window.rank.remaining = metric(rank, -29, "Points to target", "Target rank's total RP requirement minus your season RP. Zero means you already reached the target.")
    window.rank.ceiling = metric(rank, -58, "Weekly ceiling", "The maximum season-total RP currently available. This is not a separate weekly-earned allowance. Further ranks open as the season progresses.")
    window.rank.estimate = metric(rank, -87, "Estimated games / time", "Points remaining divided by average RP from usable matches, rounded up. Time uses observed match durations and excludes queues. Capped and zero-RP matches are excluded. Small samples and bonus events can skew estimates.")
    window.rank.rate = metric(rank, -116, "Your observed pace", "Average RP per usable BG and RP per hour of observed match time. Uses up to 100 stored matches across maps; queues are excluded.")
    window.rank.note = text(rank, 8, -148, "", "GameFontDisableSmall")
    text(rank, 8, -173, "BATTLEGROUND", "GameFontNormalSmall")
    text(rank, 270, -173, "WIN %", "GameFontNormalSmall")
    text(rank, 345, -173, "RP / BG", "GameFontNormalSmall")
    text(rank, 435, -173, "BGs LEFT", "GameFontNormalSmall")
    window.mapRows = {}
    for i = 1, 4 do
        local row = tableRow(rank, -191 - (i - 1) * 22)
        tooltip(row, "Battleground estimates", function()
            local m = row.data
            if not m then return "Complete battlegrounds to build per-map estimates. The four maps with the highest observed RP per hour appear here." end
            return m.name .. "\n\n" .. m.games .. " recorded games; " .. m.wins .. " wins.\n"
                .. m.samples .. " usable RP samples.\n\nWin rate includes all recorded results. RP/BG and BGs left exclude capped and zero-RP samples. Games left is for your selected target. Rows are sorted by RP per hour, excluding queues."
        end)
        window.mapRows[i] = row
    end
    local honor = window.pages.Honor
    window.honor = {
        wallet = metric(honor, 0, "Honor wallet", "Honor currently held versus the game's wallet cap. Honor is a spendable currency, separate from Rank Points."),
        room = metric(honor, -34, "Room before cap", "How much more Honor you can hold. Spend Honor before the wallet fills; additional Honor may be wasted."),
        warning = metric(honor, -68, "Wallet status", "Orange indicates at least 90% full; red indicates full. With alerts enabled, a chat warning fires near the cap and rearms after dropping below 85%."),
        session = metric(honor, -102, "Session Honor gained", "Sum of positive wallet changes observed this login or since New session. Spending between updates can hide gains. This does not measure Honor lost to the cap."),
        matches = metric(honor, -136, "Session battlegrounds", "Completed BGs and wins recorded this session. Abandoned games without an observed result are not included."),
        rp = metric(honor, -170, "Session Rank Points", "Positive changes in season RP observed this session, including gains outside BGs. Resets on login, /reload or New session."),
    }
    tooltip(button(honor, 8, -220, 140, "New session", function()
        session = { points = 0, honor = 0, matches = 0, wins = 0 }; render()
    end), "Reset session counters", "Start fresh session counters. Saved match history and learned estimates are retained.")
    text(honor, 8, -256, "Honor is for purchases; Rank Points advance your rank.", "GameFontDisableSmall")
    local matches = window.pages.Matches
    text(matches, 8, 0, "BATTLEGROUND", "GameFontNormalSmall")
    text(matches, 270, 0, "RESULT", "GameFontNormalSmall")
    text(matches, 345, 0, "RP", "GameFontNormalSmall")
    text(matches, 435, 0, "TIME", "GameFontNormalSmall")
    window.matchRows = {}
    for i = 1, 9 do
        local row = tableRow(matches, -23 - (i - 1) * 23)
        tooltip(row, "Recorded battleground", function()
            local m = row.data
            if not m then return "Results appear after a BG finishes and readable Rank Points become available." end
            return m.map .. " - " .. m.result .. "\n\nRank Points: +" .. fmt(m.points)
                .. "\nObserved match time: " .. duration(m.seconds)
                .. "\nEstimate sample: " .. (m.capped and "Excluded (rank cap)" or (m.points and m.points > 0 and "Included" or "Excluded (no RP)"))
                .. "\n\nTime begins when the addon observes entry. Joining late records only the observed portion. Delayed rewards or quest turn-ins can affect recorded RP."
        end)
        window.matchRows[i] = row
    end
    window.historyPrevious = tooltip(button(matches, 8, -243, 70, "Prev", function() historyPage = math.max(1, historyPage - 1); render() end),
        "Newer results", "Go to the previous page of battleground results.")
    window.historyNext = tooltip(button(matches, 450, -243, 70, "Next", function() historyPage = historyPage + 1; render() end),
        "Older results", "Go to the next page of battleground results.")
    window.historyPage = text(matches, 100, -250, "", "GameFontHighlightSmall")
    local info = window.pages.Info
    window.info = {
        season = metric(info, 0, "Season Rank Points", "Total RP toward ranks this season: completed rank thresholds plus progress within your current rank."),
        ceiling = metric(info, -31, "Current weekly ceiling", "The game's highest available rank this week and its cumulative RP requirement. Unknown means the client has not supplied the data."),
        week = metric(info, -62, "Season week", "The season week reported by the game. This addon does not guess a future cap schedule."),
        reset = metric(info, -93, "Next weekly reset", "Countdown from the client's weekly reset API, displayed in hours and minutes. The timer refreshes every two seconds outside combat."),
    }
    text(info, 8, -135, "NEXT RANK REWARDS", "GameFontNormalSmall")
    local rewards = CreateFrame("ScrollFrame", nil, info, "UIPanelScrollFrameTemplate")
    rewards:SetPoint("TOPLEFT", 8, -157); rewards:SetSize(492, 115)
    local content = CreateFrame("Frame", nil, rewards)
    content:SetSize(488, 1); rewards:SetScrollChild(content)
    window.reward = text(content, 0, 0, "", "GameFontHighlightSmall")
    window.reward:SetWidth(480); window.reward:SetWordWrap(true)
    window.rewardScrollContent = content
    window.footer = text(window, 20, -496, "", "GameFontDisableSmall")
    window.footer:SetWidth(400)
    window.miniButton = tooltip(button(window, 450, -488, 100, "Mini bars", function()
        db.mini = not db.mini
        if db.mini and not db.extraRP and not db.extraHonor then db.extraRP, db.extraHonor = true, true end
        syncTrackers()
    end), "Toggle trackers", "Show or hide the configured mini tracker. Choose Extra mini in Settings for two independent borderless bars.")
    mini = panel("DecentPVPRankMini", 340, 104)
    text(mini, 20, -12, "DECENT PVP", "GameFontNormalSmall")
    mini.rankBar, mini.honorBar = bar(mini, -36), bar(mini, -66)
    extraBars.rp = standaloneBar("DecentPVPRankExtraRP", "extraRP", -100)
    extraBars.honor = standaloneBar("DecentPVPRankExtraHonor", "extraHonor", -128)
    local function rankHelp()
        local progress = current and ("Rank " .. current.rank .. " - " .. title(current.rank)
            .. "\nCurrent rank: " .. fmt(current.points) .. " / " .. fmt(current.threshold) .. " RP"
            .. "\nSeason total: " .. fmt(current.total) .. " RP"
            .. "\nWeekly ceiling: " .. fmt(current.cap) .. " RP") or "Waiting for readable rank data. Updates pause in combat."
        return progress
            .. "\n\nRank Points advance your rank. This bar shows progress within the current rank, not your weekly earnings."
            .. "\n\n" .. RP_SOURCES
            .. "\n\nLeft-click: Rank Points details. Right-click: settings."
    end
    local function honorHelp()
        return "Honor is a spendable wallet currency, separate from Rank Points. Orange means nearly full (90%); red means full."
            .. "\n\nCurrent Honor: " .. fmt(current and current.honor) .. " / " .. fmt(current and current.honorCap)
            .. "\n\n" .. HONOR_SOURCES
            .. "\n\nLeft-click: Honor details. Right-click: settings."
    end
    for _, entry in ipairs({
        { window.rankBar, "Rank Points", rankHelp }, { mini.rankBar, "Rank Points", rankHelp },
        { window.honorBar, "Honor", honorHelp }, { mini.honorBar, "Honor", honorHelp },
        { extraBars.rp, "Rank Points", rankHelp }, { extraBars.honor, "Honor", honorHelp },
    }) do
        local frame, tabName = entry[1], entry[2]
        local help = entry[3]
        tooltip(frame, tabName, function()
            return help() .. ((frame == extraBars.rp or frame == extraBars.honor)
                and "\n\nDrag this bar to move it when unlocked. Click x to hide only this bar; restore it in Settings." or "")
        end)
        frame:SetScript("OnMouseUp", function(self, mouse)
            if self.dragging or (self.lastDrag and GetTime() - self.lastDrag < .15) then return end
            if mouse == "RightButton" then openSettings()
            elseif mouse == "LeftButton" then
                selectTab(tabName)
                if embeddedMode and DPTL_OpenPVP then DPTL_OpenPVP() else window:Show() end
            end
        end)
    end

    settings = panel("DecentPVPRankSettings", 390, 622)
    text(settings, 20, -20, "Decent PvP Rank - Settings", "GameFontNormalLarge")
    text(settings, 20, -61, "Faction theme: Horde red / Alliance blue")
    tooltip(button(settings, 20, -90, 150, "Choose color", colorPicker),
        "Custom accent color", "Change the window tint, border, rank bars and selected tab. Cancel restores your previous color. Honor bars retain their warning colors.")
    tooltip(button(settings, 180, -90, 180, "Use faction color", function() db.color = nil; applyTheme() end),
        "Restore faction theme", "Automatically use red for Horde or blue for Alliance. Removes the custom color override.")
    tooltip(checkbox(settings, -130, "Lock window positions", "locked"),
        "Lock positions", "Prevent dragging the main window, settings window, all tracker bars and minimap icon.")
    tooltip(checkbox(settings, -164, "Honor and rank cap alerts", "alerts"),
        "Cap alerts", "Show a chat warning when Honor reaches 90% of the wallet cap or the weekly rank ceiling is reached.")
    tooltip(checkbox(settings, -198, "Show mini tracker", "mini"),
        "Show trackers", "Show the framed mini tracker or, with Extra mini enabled, your independent bars. Re-enabling this restores both bars if both were closed.")
    tooltip(checkbox(settings, -232, "Extra mini (independent bars)", "extraMini"),
        "Extra mini", "Replace the framed mini tracker with separate RP and Honor bars. They have no background or border, move independently, and each has its own x to close. Enabling this also shows trackers.")
    tooltip(checkbox(settings, -266, "Show extra-mini RP bar", "extraRP"),
        "Independent RP bar", "Show the RP bar and enable Extra mini automatically. Closing the RP bar does not close Honor.")
    tooltip(checkbox(settings, -300, "Show extra-mini Honor bar", "extraHonor"),
        "Independent Honor bar", "Show the Honor bar and enable Extra mini automatically. Closing Honor does not close the RP bar.")
    tooltip(checkbox(settings, -334, "Show minimap icon", "minimap"),
        "Horde minimap icon", "Left-click for the rank window, right-click for settings. Drag the icon around the minimap when positions are unlocked.")
    tooltip(checkbox(settings, -368, "Use Blizzard-style UI", "blizzardUI"),
        "Blizzard-style layout", "Use the game's opaque rock window fill, marble inset, decorative frame, title header and native tab artwork. Faction/custom colors remain on progress bars and subtly tint the selected tab. Turn off to restore the compact layout.")
    text(settings, 20, -415, "EXTRA MINI SIZE (pixels; Enter to apply)", "GameFontNormalSmall")
    text(settings, 20, -450, "RP width", "GameFontHighlightSmall")
    sizeInput(settings, 100, -441, "rp", "width", 80, 600)
    text(settings, 200, -450, "Height", "GameFontHighlightSmall")
    sizeInput(settings, 270, -441, "rp", "height", 12, 40)
    text(settings, 20, -484, "Honor width", "GameFontHighlightSmall")
    sizeInput(settings, 100, -475, "honor", "width", 80, 600)
    text(settings, 200, -484, "Height", "GameFontHighlightSmall")
    sizeInput(settings, 270, -475, "honor", "height", 12, 40)
    tooltip(button(settings, 20, -511, 210, "Show extra bars", function()
        db.extraMini, db.mini, db.extraRP, db.extraHonor = true, true, true, true
        syncTrackers(); refresh()
    end), "Show both independent bars", "Enable Extra mini and restore both bars, even if they were previously closed. They contain only progress fill and text; no panel, backdrop or border.")
    tooltip(button(settings, 20, -548, 100, "Scale -", function() db.scale = math.max(.7, db.scale - .1); applyTheme() end),
        "Smaller interface", "Reduce window scale. Extra-mini bar sizes are controlled separately above. Minimum: 70%.")
    tooltip(button(settings, 130, -548, 100, "Scale +", function() db.scale = math.min(1.6, db.scale + .1); applyTheme() end),
        "Larger interface", "Increase window scale. Extra-mini bar sizes are controlled separately above. Maximum: 160%.")
    tooltip(button(settings, 20, -585, 210, "Reset window positions", function()
        db.positions = {}
        for _, f in ipairs({ window, settings, mini }) do f:ClearAllPoints(); f:SetPoint("CENTER") end
        mini:ClearAllPoints(); mini:SetPoint("TOP", UIParent, "TOP", 0, -100)
        extraBars.rp:ClearAllPoints(); extraBars.rp:SetPoint("TOP", UIParent, "TOP", 0, -100)
        extraBars.honor:ClearAllPoints(); extraBars.honor:SetPoint("TOP", UIParent, "TOP", 0, -128)
    end), "Reset positions", "Center the main and settings windows and return all tracker bars to the top of the screen. Saved window and bar positions are cleared; visibility choices are kept.")
    settings:Hide()
    mini.close:SetScript("OnClick", function() db.mini = false; syncTrackers() end)
    mini:SetScript("OnHide", function(self)
        -- Parent/UI visibility changes are not a request to disable standalone bars.
        if not syncingTrackers and not db.extraMini and not self:IsShown() then
            db.mini = false; syncTrackers()
        end
    end)
    syncTrackers()
    if not db.positions.DecentPVPRankMini then mini:ClearAllPoints(); mini:SetPoint("TOP", UIParent, "TOP", 0, -100) end
    window:SetShown(db.visible)
    window:SetScript("OnShow", function()
        if not embeddedMode then db.visible = true end
        refresh()
    end)
    window:SetScript("OnHide", function()
        if not embeddedMode then db.visible = false end
    end)
    selectTab(selectedTab)
    applyTheme()
    buildMinimapButton()
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local page = CreateFrame("Frame")
        text(page, 20, -20, "Decent PvP Rank", "GameFontNormalLarge")
        button(page, 20, -60, 200, "Open color and display settings", function() openSettings() end)
        local category = Settings.RegisterCanvasLayoutCategory(page, "Decent PvP Rank")
        Settings.RegisterAddOnCategory(category)
    end
end
openSettings = function() settings:Show(); applyTheme() end

function DecentPVPRank_EmbedInto(parent)
    if not window or not parent then return false end
    embeddedMode, embeddedParent = true, parent
    window:SetParent(parent)
    window:SetFrameStrata(parent:GetFrameStrata())
    window:SetFrameLevel(parent:GetFrameLevel() + 1)
    window:SetMovable(false)
    window:RegisterForDrag()
    window:SetScript("OnDragStart", nil)
    window:ClearAllPoints()
    window:SetPoint("CENTER", parent, "CENTER")
    window.close:Hide()
    window.headerArt:Hide()
    window.title:Hide()
    window.helpButton:Hide()
    window.settingsButton:Hide()
    window.inset:Hide()
    window.footer:Hide()
    window.miniButton:Hide()
    for i = #UISpecialFrames, 1, -1 do
        if UISpecialFrames[i] == "DecentPVPRankWindow" then table.remove(UISpecialFrames, i) end
    end
    applyTheme()
    return true
end

function DecentPVPRank_SetEmbeddedVisible(shown)
    if embeddedMode and window then window:SetShown(shown and true or false) end
end

function DecentPVPRank_ResizeEmbedded()
    if embeddedMode then applyTheme() end
end

function DecentPVPRank_SetBlizzardUI(enabled)
    enabled = enabled and true or false
    if db and db.blizzardUI ~= enabled then
        db.blizzardUI = enabled
        appliedBlizzardStyle = nil
        applyTheme()
    end
end

function DecentPVPRank_OpenSettings()
    if openSettings then openSettings() end
end

function DecentPVPRank_RefreshGuildKills()
    if embeddedMode and selectedTab == "Guild Kills" and window.pages["Guild Kills"]
        and type(DPTL_BuildGuildKillsPage) == "function" then
        DPTL_BuildGuildKillsPage(window.pages["Guild Kills"])
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name ~= addonName then return end
        DecentPVPRankDB = DecentPVPRankDB or {}
        db = DecentPVPRankDB
        db.positions, db.characters = db.positions or {}, db.characters or {}
        if db.alerts == nil then db.alerts = true end
        if db.visible == nil then db.visible = true end
        if db.minimap == nil then db.minimap = true end
        if db.extraMini == nil then db.extraMini = false end
        if db.extraRP == nil then db.extraRP = true end
        if db.extraHonor == nil then db.extraHonor = true end
        if db.blizzardUI == nil then db.blizzardUI = false end
        db.extraSizes = db.extraSizes or {}
        for _, key in ipairs({ "rp", "honor" }) do
            local size = db.extraSizes[key] or {}
            size.width = math.floor(math.max(80, math.min(600, tonumber(size.width) or 280)))
            size.height = math.floor(math.max(12, math.min(40, tonumber(size.height) or 18)))
            db.extraSizes[key] = size
        end
        if not db.extraVisibilityVersion then
            if db.extraMini then
                db.mini = true
                if not db.extraRP and not db.extraHonor then db.extraRP, db.extraHonor = true, true end
            end
            db.extraVisibilityVersion = 1
        end
        db.minimapAngle = db.minimapAngle or 225
        db.scale, db.target = db.scale or 1, db.target or 14
        db.target = math.max(1, math.min(14, math.floor(tonumber(db.target) or 14)))
        local key = UnitGUID("player") or (UnitName("player") .. "-" .. GetRealmName())
        db.characters[key] = db.characters[key] or { history = {} }
        character = db.characters[key]
        build()
        for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "UPDATE_FACTION",
            "MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "CURRENCY_DISPLAY_UPDATE", "UPDATE_BATTLEFIELD_STATUS",
            "UPDATE_BATTLEFIELD_SCORE" }) do events:RegisterEvent(ev) end
        C_Timer.NewTicker(2, refresh)
        SLASH_DECENTPVPRANK1, SLASH_DECENTPVPRANK2 = "/dpr", "/decentrank"
        SlashCmdList.DECENTPVPRANK = function(input)
            local command, arg = input:lower():match("^(%S*)%s*(.-)$")
            if command == "settings" or command == "config" then openSettings()
            elseif command == "mini" then
                db.mini = not db.mini
                if db.mini and not db.extraRP and not db.extraHonor then db.extraRP, db.extraHonor = true, true end
                syncTrackers()
            elseif command == "extra" then
                db.extraMini = not db.extraMini
                db.mini = true
                if not db.extraRP and not db.extraHonor then db.extraRP, db.extraHonor = true, true end
                syncTrackers()
            elseif command == "minimap" then
                db.minimap = not db.minimap
                if minimapButton then minimapButton:SetShown(db.minimap) end
            elseif command == "lock" then db.locked = not db.locked; message(db.locked and "Positions locked." or "Positions unlocked.")
            elseif command == "target" then
                local target = tonumber(arg)
                if target and target == math.floor(target) and target >= 1 and target <= (current and current.maxRank or 14) then
                    db.target = target; refresh()
                else message("Usage: /dpr target 1-14") end
            elseif command == "debug" then
                message("Interface " .. select(4, GetBuildInfo()) .. "; faction 2800; Honor currency " .. HONOR_ID)
                message("Rank " .. fmt(current and current.rank) .. "; total " .. fmt(current and current.total)
                    .. "; weekly ceiling " .. fmt(current and current.cap) .. "; last error: " .. (lastError or "none"))
            elseif command == "" then
                if embeddedMode and DPTL_TogglePVP then DPTL_TogglePVP() else toggle(window) end
            else message("/dpr | settings | mini | extra | minimap | lock | target 1-14 | debug") end
        end
        refresh()
    else refresh() end
end)
