local RTC = {}
local BUTTON_NAMES = {
    up = "RTC_UpButton",
    down = "RTC_DownButton",
    left = "RTC_LeftButton",
    right = "RTC_RightButton",
    self = "RTC_SelfButton",
}

local BUTTON_ORDER = { "up", "down", "left", "right", "self" }
local EVENT_FRAME = CreateFrame("Frame")

local db
local buttons = {}
local nodes = {}
local unitToIndex = {}
local pendingRefresh = false
local lastBuildReason = "not built"
local rebuildToken = 0
local layoutHooked = false
local eventLog = {}

_G.BINDING_HEADER_RAIDTARGETCURSOR = "Raid Target Cursor"
_G["BINDING_NAME_CLICK RTC_UpButton:LeftButton"] = "Raid Cursor Up"
_G["BINDING_NAME_CLICK RTC_DownButton:LeftButton"] = "Raid Cursor Down"
_G["BINDING_NAME_CLICK RTC_LeftButton:LeftButton"] = "Raid Cursor Left"
_G["BINDING_NAME_CLICK RTC_RightButton:LeftButton"] = "Raid Cursor Right"
_G["BINDING_NAME_CLICK RTC_SelfButton:LeftButton"] = "Raid Cursor Self / Reset"

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffRTC|r " .. message)
end

local function Debug(message)
    if db and db.debug then
        Print(message)
    end
end

local function AddEventLog(message)
    local timestamp = GetTime and GetTime() or 0
    eventLog[#eventLog + 1] = string.format("%.1f %s", timestamp, message)

    while #eventLog > 30 do
        table.remove(eventLog, 1)
    end

    if db then
        db.eventLog = eventLog
    end
end

local function IsSupportedUnit(unit)
    return unit == "player" or string.match(unit, "^party%d+$") or string.match(unit, "^raid%d+$")
end

local function UnitFromFrame(frame)
    if not frame or (frame.IsForbidden and frame:IsForbidden()) then
        return nil
    end

    local unit = frame.displayedUnit or frame.unit

    if not unit and frame.GetAttribute then
        unit = frame:GetAttribute("unit")
    end

    if type(unit) ~= "string" or not IsSupportedUnit(unit) then
        return nil
    end

    if UnitExists(unit) and UnitIsFriend("player", unit) then
        return unit
    end

    return nil
end

local AddCandidate

local function LooksLikeBlizzardGroupFrame(frame)
    if not frame or type(frame.GetName) ~= "function" then
        return false
    end

    local name = frame:GetName()
    if type(name) ~= "string" then
        return false
    end

    return string.match(name, "^CompactRaidFrame%d+$")
        or string.match(name, "^CompactRaidGroup%d+Member%d+$")
        or string.match(name, "^CompactPartyFrameMember%d+$")
        or string.match(name, "^CompactPartyFrame%.MemberFrame%d+$")
        or string.match(name, "^CompactRaidFrameContainer%.MemberFrame%d+$")
        or string.match(name, "^PartyMemberFrame%d+$")
        or string.match(name, "^PartyFrame%.MemberFrame%d+$")
end

local function ScanChildren(candidatesByUnit, seenFrames, parent)
    if not parent or not parent.GetChildren then
        return
    end

    for i = 1, select("#", parent:GetChildren()) do
        local child = select(i, parent:GetChildren())
        AddCandidate(candidatesByUnit, seenFrames, child)
        ScanChildren(candidatesByUnit, seenFrames, child)
    end
end

AddCandidate = function(candidatesByUnit, seenFrames, frame)
    if not frame or seenFrames[frame] then
        return
    end
    seenFrames[frame] = true

    if not LooksLikeBlizzardGroupFrame(frame) then
        return
    end

    if not frame.IsShown or not frame:IsShown() or (frame.IsVisible and not frame:IsVisible()) or not frame.GetCenter then
        return
    end

    local unit = UnitFromFrame(frame)
    if not unit then
        return
    end

    local x, y = frame:GetCenter()
    if not x or not y then
        return
    end

    local width = frame:GetWidth() or 1
    local height = frame:GetHeight() or 1
    if width <= 1 or height <= 1 then
        return
    end

    local existing = candidatesByUnit[unit]
    if existing then
        local existingArea = existing.width * existing.height
        local newArea = width * height
        if newArea <= existingArea then
            return
        end
    end

    local candidate = {
        unit = unit,
        frame = frame,
        x = x,
        y = y,
        width = width,
        height = height,
    }

    candidatesByUnit[unit] = candidate
end

local function ScanFrames()
    local candidatesByUnit = {}
    local seenFrames = {}

    for i = 1, 40 do
        AddCandidate(candidatesByUnit, seenFrames, _G["CompactRaidFrame" .. i])
    end

    for group = 1, 8 do
        for member = 1, 5 do
            AddCandidate(candidatesByUnit, seenFrames, _G["CompactRaidGroup" .. group .. "Member" .. member])
        end
    end

    for i = 1, 5 do
        AddCandidate(candidatesByUnit, seenFrames, _G["CompactPartyFrameMember" .. i])
        AddCandidate(candidatesByUnit, seenFrames, _G["CompactPartyFrame.MemberFrame" .. i])
        AddCandidate(candidatesByUnit, seenFrames, _G["CompactRaidFrameContainer.MemberFrame" .. i])
        AddCandidate(candidatesByUnit, seenFrames, _G["PartyMemberFrame" .. i])
        AddCandidate(candidatesByUnit, seenFrames, _G["PartyFrame.MemberFrame" .. i])
    end

    ScanChildren(candidatesByUnit, seenFrames, _G.CompactPartyFrame)
    ScanChildren(candidatesByUnit, seenFrames, _G.CompactRaidFrameContainer)
    ScanChildren(candidatesByUnit, seenFrames, _G.PartyFrame)

    if not next(candidatesByUnit) then
        local frame = EnumerateFrames()
        while frame do
            AddCandidate(candidatesByUnit, seenFrames, frame)
            frame = EnumerateFrames(frame)
        end
    end

    local candidates = {}
    for _, candidate in pairs(candidatesByUnit) do
        candidates[#candidates + 1] = candidate
    end

    table.sort(candidates, function(a, b)
        if math.abs(a.y - b.y) > 2 then
            return a.y > b.y
        end
        return a.x < b.x
    end)

    return candidates
end

local function BuildRows(candidates)
    local rows = {}
    local averageHeight = 36

    if #candidates > 0 then
        local total = 0
        for _, candidate in ipairs(candidates) do
            total = total + candidate.height
        end
        averageHeight = total / #candidates
    end

    local threshold = math.max(10, averageHeight * 0.5)

    for _, candidate in ipairs(candidates) do
        local row = rows[#rows]

        if not row or math.abs(row.y - candidate.y) > threshold then
            row = { y = candidate.y, items = {} }
            rows[#rows + 1] = row
        else
            row.y = ((row.y * #row.items) + candidate.y) / (#row.items + 1)
        end

        row.items[#row.items + 1] = candidate
    end

    for _, row in ipairs(rows) do
        table.sort(row.items, function(a, b)
            return a.x < b.x
        end)
    end

    return rows
end

local function ClosestByX(row, x)
    local bestIndex = nil
    local bestDistance = nil

    for index, node in ipairs(row.items) do
        local distance = math.abs(node.x - x)
        if not bestDistance or distance < bestDistance then
            bestDistance = distance
            bestIndex = index
        end
    end

    return bestIndex
end

local function BuildGrid(candidates)
    local rows = BuildRows(candidates)
    local result = {}

    for rowIndex, row in ipairs(rows) do
        for colIndex, item in ipairs(row.items) do
            local node = {
                index = #result + 1,
                row = rowIndex,
                col = colIndex,
                unit = item.unit,
                frame = item.frame,
                x = item.x,
                y = item.y,
                width = item.width,
                height = item.height,
            }
            item.index = node.index
            result[#result + 1] = node
        end
    end

    for _, node in ipairs(result) do
        local row = rows[node.row]
        local up = node.index
        local down = node.index
        local left = node.index
        local right = node.index

        if node.col > 1 then
            left = row.items[node.col - 1].index
        end

        if node.col < #row.items then
            right = row.items[node.col + 1].index
        end

        if rows[node.row - 1] then
            local col = ClosestByX(rows[node.row - 1], node.x)
            up = rows[node.row - 1].items[col].index
        end

        if rows[node.row + 1] then
            local col = ClosestByX(rows[node.row + 1], node.x)
            down = rows[node.row + 1].items[col].index
        end

        node.up = up
        node.down = down
        node.left = left
        node.right = right
    end

    return result
end

local function ForEachButton(callback)
    for _, key in ipairs(BUTTON_ORDER) do
        callback(buttons[key], key)
    end
end

local function CreateSecureCore()
    if next(buttons) then
        return
    end

    local clickType = GetCVarBool("ActionButtonUseKeyDown") and "AnyDown" or "AnyUp"

    for _, key in ipairs(BUTTON_ORDER) do
        local button = CreateFrame("Button", BUTTON_NAMES[key], UIParent, "SecureActionButtonTemplate")
        button:RegisterForClicks(clickType)
        button:SetAttribute("type", "target")
        button:SetAttribute("unit", key == "self" and "player" or "none")
        button:SetAttribute("dir", key)
        buttons[key] = button
    end

    ForEachButton(function(button)
        button:SetAttribute("relatedCount", #BUTTON_ORDER)
        for index, key in ipairs(BUTTON_ORDER) do
            SecureHandlerSetFrameRef(button, "related" .. index, buttons[key])
        end
    end)

    local setIndex = [[
        local index = ...
        local count = self:GetAttribute("relatedCount") or 0
        for i = 1, count do
            local button = self:GetFrameRef("related" .. i)
            if button then
                button:SetAttribute("currentIndex", index)
            end
        end
    ]]

    local onClick = [[
        local dir = self:GetAttribute("dir")
        local maxIndex = self:GetAttribute("maxIndex") or 0
        local index = self:GetAttribute("currentIndex") or 1
        local unit = "none"

        if dir == "self" then
            unit = "player"
            local selfIndex = self:GetAttribute("selfIndex")
            if selfIndex then
                index = selfIndex
            end
        elseif maxIndex > 0 then
            local nextIndex = self:GetAttribute(dir .. "-" .. index)
            if not nextIndex or nextIndex < 1 or nextIndex > maxIndex then
                nextIndex = index
            end

            index = nextIndex
            unit = self:GetAttribute("unit-" .. index) or "none"
        end

        self:RunAttribute("setIndex", index)
        self:SetAttribute("unit", unit)
    ]]

    ForEachButton(function(button)
        button:SetAttribute("setIndex", setIndex)
        SecureHandlerWrapScript(button, "OnClick", button, onClick)
    end)
end

local function ClearSecureMap(button)
    local previousMax = button:GetAttribute("maxIndex") or 0

    for index = 1, previousMax do
        button:SetAttribute("unit-" .. index, nil)
        button:SetAttribute("up-" .. index, nil)
        button:SetAttribute("down-" .. index, nil)
        button:SetAttribute("left-" .. index, nil)
        button:SetAttribute("right-" .. index, nil)
    end

    button:SetAttribute("maxIndex", 0)
    button:SetAttribute("selfIndex", nil)
end

local function PublishSecureMap()
    if InCombatLockdown() then
        pendingRefresh = true
        Debug("rebuild deferred until combat ends")
        return false
    end

    ForEachButton(function(button)
        ClearSecureMap(button)
        button:SetAttribute("maxIndex", #nodes)
        button:SetAttribute("currentIndex", math.min(button:GetAttribute("currentIndex") or 1, math.max(#nodes, 1)))

        for _, node in ipairs(nodes) do
            button:SetAttribute("unit-" .. node.index, node.unit)
            button:SetAttribute("up-" .. node.index, node.up)
            button:SetAttribute("down-" .. node.index, node.down)
            button:SetAttribute("left-" .. node.index, node.left)
            button:SetAttribute("right-" .. node.index, node.right)

            if node.unit == "player" then
                button:SetAttribute("selfIndex", node.index)
            end
        end
    end)

    return true
end

function RTC:Rebuild(reason)
    AddEventLog("rebuild " .. tostring(reason))

    if InCombatLockdown() then
        pendingRefresh = true
        lastBuildReason = "pending: " .. (reason or "combat lockdown")
        if reason == "slash rebuild" then
            Print("rebuild queued until combat ends")
        else
            Debug(lastBuildReason)
        end
        return
    end

    local candidates = ScanFrames()
    nodes = BuildGrid(candidates)
    unitToIndex = {}

    for _, node in ipairs(nodes) do
        unitToIndex[node.unit] = node.index
    end

    PublishSecureMap()
    lastBuildReason = reason or "manual"
    pendingRefresh = false

    if #nodes == 0 then
        Debug("no visible Blizzard raid/party frames found")
        AddEventLog("mapped 0 frames")
    else
        Debug(string.format("mapped %d visible frame(s)", #nodes))
        AddEventLog(string.format("mapped %d frames", #nodes))
    end

end

local function ScheduleRebuild(reason, delay)
    rebuildToken = rebuildToken + 1
    local token = rebuildToken

    C_Timer.After(delay or 0.25, function()
        if token == rebuildToken then
            RTC:Rebuild(reason)
        end
    end)
end

local function ScheduleRebuildBurst(reason, delays)
    rebuildToken = rebuildToken + 1
    local token = rebuildToken

    for _, delay in ipairs(delays) do
        C_Timer.After(delay, function()
            if token == rebuildToken then
                RTC:Rebuild(reason)
            end
        end)
    end
end

local function HookBlizzardLayout()
    if layoutHooked then
        return
    end

    local function RequestLayoutRebuild()
        ScheduleRebuild("Blizzard layout update", 0.05)
    end

    if CompactRaidFrameContainer_LayoutFrames then
        hooksecurefunc("CompactRaidFrameContainer_LayoutFrames", RequestLayoutRebuild)
        layoutHooked = true
    end

    if CompactRaidFrameContainer_OnSizeChanged then
        hooksecurefunc("CompactRaidFrameContainer_OnSizeChanged", RequestLayoutRebuild)
        layoutHooked = true
    end
end

function RTC:SyncTarget()
    if InCombatLockdown() or not UnitExists("target") then
        return
    end

    for unit, index in pairs(unitToIndex) do
        if UnitIsUnit("target", unit) then
            ForEachButton(function(button)
                button:SetAttribute("currentIndex", index)
            end)
            return
        end
    end
end

function RTC:Status()
    if lastBuildReason == "not built" and not InCombatLockdown() then
        self:Rebuild("status auto rebuild")
    end

    local index = buttons.up and buttons.up:GetAttribute("currentIndex") or 1
    local node = index and nodes[index]
    local unit = node and node.unit or "none"
    local combat = InCombatLockdown() and "yes" or "no"
    local pending = pendingRefresh and "yes" or "no"
    local maxIndex = buttons.up and buttons.up:GetAttribute("maxIndex") or 0

    Print(string.format("frames=%d secureMax=%s currentIndex=%s unit=%s combat=%s pendingRefresh=%s lastBuild=%s",
        #nodes,
        tostring(maxIndex),
        tostring(index),
        unit,
        combat,
        pending,
        lastBuildReason
    ))
end

function RTC:Dump()
    if lastBuildReason == "not built" and not InCombatLockdown() then
        self:Rebuild("dump auto rebuild")
    end

    self:Status()

    if #nodes == 0 then
        Print("map is empty; show Blizzard party/raid frames, then run /rtc rebuild")
        return
    end

    for _, node in ipairs(nodes) do
        Print(string.format("%02d %s row=%d col=%d up=%d down=%d left=%d right=%d",
            node.index,
            node.unit,
            node.row,
            node.col,
            node.up,
            node.down,
            node.left,
            node.right
        ))
    end

    Print("out of combat test: /click RTC_RightButton or /click RTC_DownButton")
end

function RTC:Frames()
    local printed = 0
    local seenFrames = {}

    local function PrintFrame(frame)
        if printed >= 30 or not frame or seenFrames[frame] or not LooksLikeBlizzardGroupFrame(frame) then
            return
        end
        seenFrames[frame] = true

        local name = frame.GetName and frame:GetName() or "unnamed"
        local unit = frame.displayedUnit or frame.unit
        if not unit and frame.GetAttribute then
            unit = frame:GetAttribute("unit")
        end

        local shown = frame.IsShown and frame:IsShown() and "shown" or "hidden"
        local visible = frame.IsVisible and frame:IsVisible() and "visible" or "not-visible"
        local x, y = nil, nil
        if frame.GetCenter then
            x, y = frame:GetCenter()
        end

        local width = frame.GetWidth and frame:GetWidth() or 0
        local height = frame.GetHeight and frame:GetHeight() or 0

        printed = printed + 1
        Print(string.format("%02d %s unit=%s %s/%s x=%s y=%s size=%.0fx%.0f",
            printed,
            name,
            tostring(unit),
            shown,
            visible,
            tostring(x and math.floor(x + 0.5) or nil),
            tostring(y and math.floor(y + 0.5) or nil),
            width,
            height
        ))
    end

    for i = 1, 40 do
        PrintFrame(_G["CompactRaidFrame" .. i])
    end

    for group = 1, 8 do
        for member = 1, 5 do
            PrintFrame(_G["CompactRaidGroup" .. group .. "Member" .. member])
        end
    end

    local frame = EnumerateFrames()
    while frame and printed < 30 do
        PrintFrame(frame)
        frame = EnumerateFrames(frame)
    end

    if printed == 0 then
        Print("no Blizzard raid/party frame-like objects found")
    elseif printed == 30 then
        Print("frame debug capped at 30 results")
    end
end

function RTC:Events()
    if #eventLog == 0 then
        Print("event log is empty")
        return
    end

    for _, entry in ipairs(eventLog) do
        Print(entry)
    end
end

local function SlashCommand(input)
    input = string.match(string.lower(input or ""), "^%s*(.-)%s*$")
    AddEventLog("slash " .. (input ~= "" and input or "status"))

    if input == "rebuild" then
        if not next(buttons) then
            CreateSecureCore()
        end
        RTC:Rebuild("slash rebuild")
        RTC:Status()
    elseif input == "status" or input == "" then
        RTC:Status()
    elseif input == "dump" then
        RTC:Dump()
    elseif input == "frames" then
        RTC:Frames()
    elseif input == "events" then
        RTC:Events()
    elseif input == "reset" then
        if InCombatLockdown() then
            Print("Use the Raid Cursor Self / Reset binding in combat.")
        else
            ForEachButton(function(button)
                local index = button:GetAttribute("selfIndex") or 1
                button:SetAttribute("currentIndex", index)
            end)
            Print("cursor reset to player frame when available; self binding always targets player")
        end
    elseif input == "debug" then
        db.debug = not db.debug
        Print("debug " .. (db.debug and "on" or "off"))
    elseif input == "show" or input == "hide" or input == "lock" or input == "unlock" then
        Print("visual overlay was removed; RTC now only changes hard target")
    else
        Print("commands: /rtc rebuild, /rtc status, /rtc dump, /rtc frames, /rtc events, /rtc reset, /rtc debug")
    end
end

SLASH_RAIDTARGETCURSOR1 = "/rtc"
SlashCmdList.RAIDTARGETCURSOR = SlashCommand

local function OnEvent(_, event)
    AddEventLog("event " .. tostring(event))

    if event == "PLAYER_LOGIN" then
        RaidTargetCursorDB = RaidTargetCursorDB or {}
        db = RaidTargetCursorDB
        db.debug = db.debug or false
        db.eventLog = eventLog

        CreateSecureCore()
        HookBlizzardLayout()

        ScheduleRebuild("login", 0.5)
    elseif event == "PLAYER_ENTERING_WORLD" then
        HookBlizzardLayout()
        ScheduleRebuildBurst("entering world", { 0.5, 1.5, 3.0 })
    elseif event == "GROUP_ROSTER_UPDATE" or event == "RAID_ROSTER_UPDATE" then
        ScheduleRebuildBurst(event, { 0.35, 1.0 })
    elseif event == "PVP_MATCH_STATE_CHANGED" then
        HookBlizzardLayout()
        ScheduleRebuildBurst(event, { 0.25, 1.0, 3.0 })
    elseif event == "PLAYER_REGEN_DISABLED" then
        Debug("combat lockdown active")
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingRefresh then
            RTC:Rebuild("leaving combat")
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        RTC:SyncTarget()
    end
end

EVENT_FRAME:RegisterEvent("PLAYER_LOGIN")
EVENT_FRAME:RegisterEvent("PLAYER_ENTERING_WORLD")
EVENT_FRAME:RegisterEvent("GROUP_ROSTER_UPDATE")
EVENT_FRAME:RegisterEvent("PLAYER_REGEN_DISABLED")
EVENT_FRAME:RegisterEvent("PLAYER_REGEN_ENABLED")
EVENT_FRAME:RegisterEvent("PLAYER_TARGET_CHANGED")
pcall(EVENT_FRAME.RegisterEvent, EVENT_FRAME, "RAID_ROSTER_UPDATE")
pcall(EVENT_FRAME.RegisterEvent, EVENT_FRAME, "PVP_MATCH_STATE_CHANGED")

EVENT_FRAME:SetScript("OnEvent", OnEvent)
