-- Groups.lua
-- Manages the in-game display frames for each cooldown group.
--
-- Each group is a movable overlay frame containing a vertical list of
-- cooldown rows.  Rows are created / recycled via LibFramePool-1.0.
-- Frames are registered with LibEditmode-1.0 so they can be repositioned
-- by the user via /cd lock (toggle edit mode).
--
-- Public functions exposed on ns:
--   ns.InitGroups()            — call once after DB is ready
--   ns.CreateGroupFrame(name)  — create display frame for a new group
--   ns.DestroyGroupFrame(name) — hide and unregister a group's frame
--   ns.ToggleEditMode()        — enter / leave layout-edit mode

local addonName, ns = ...

-- Core.lua is listed before Groups.lua in the .toc file, so ns.Cooldowns is
-- guaranteed to be set by the time this file executes at load time.
local Cooldowns    = ns.Cooldowns
local LibFramePool = LibStub("LibFramePool-1.0")
local LibEditmode  = LibStub("LibEditmode-1.0")
local classColors  = ns.classColors

-- ============================================================
-- Constants / layout metrics
-- ============================================================

local POOL_KEY     = "Cooldowns_Row"
local HEADER_H     = 22     -- header strip height (px)
local DEFAULT_ROW_H = 26    -- fallback row height when not configured
local ROW_PAD      = 1      -- vertical gap between rows
local MIN_W        = 100    -- minimum group frame width
local DEFAULT_W    = 260
local MIN_ROW_H    = 10     -- minimum configurable row height
local MAX_ROW_H    = 50     -- maximum configurable row height
local BAR_ALPHA    = 0.45   -- alpha for all active/ready progress bars

-- ============================================================
-- Flat backdrop (shared with Skin.lua style)
-- ============================================================

local flatBackdrop = {
    bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
    tile = false, tileSize = 0, edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
}

-- ============================================================
-- Time formatting helpers
-- ============================================================

-- Plain-text version used in chat messages (no colour codes).
local function FormatTimeChat(seconds)
    if seconds <= 0 then return "Ready" end
    if seconds < 10 then
        return string.format("%.1fs", seconds)
    elseif seconds < 60 then
        return string.format("%.0fs", seconds)
    elseif seconds < 3600 then
        return string.format("%dm%02ds", math.floor(seconds / 60), seconds % 60)
    else
        return string.format("%dh%02dm",
            math.floor(seconds / 3600), math.floor((seconds % 3600) / 60))
    end
end

-- Apply chat message template tokens.
-- Tokens: %playerName %spellName %targetName %timeLeft
--   %condCD(text) — replaced with "text" when on cooldown, removed when ready.
local function FormatChatMessage(template, data)
    local spellName  = Cooldowns:GetSpellChatName(data.spellID)
    local timeStr    = FormatTimeChat(data.timeLeft)
    local spellLink
    if data.isItem then
        -- Core.lua already handles looking up the item link for trinkets
        spellLink = Cooldowns:GetSpellChatName(data.spellID)
    else
        -- WoW API generates the clickable spell link
        spellLink = GetSpellLink(data.spellID) or spellName
    end
    local targetName = data.destName or ""
    local hasTarget  = (data.destName and data.destName ~= "")
    local msg = template
    msg = msg:gsub("%%playerName", data.srcName)
    msg = msg:gsub("%%spellName",  spellName)
    msg = msg:gsub("%%spellLink",  spellLink)
    msg = msg:gsub("%%targetName", targetName)
    msg = msg:gsub("%%timeLeft",   timeStr)
    if data.timeLeft > 0 then
        -- on cooldown: replace %condCD(text) with the inner text
        msg = msg:gsub("%%condCD%((.-)%)", "%1")
    else
        -- ready: remove the entire %condCD(...) token
        msg = msg:gsub("%%condCD%((.-)%)", "")
    end

    if hasTarget then
        msg = msg:gsub("%%condTarget%((.-)%)", "%1")
    else
        msg = msg:gsub("%%condTarget%((.-)%)", "")
    end
    return msg
end

-- Colour-coded version used in the on-screen timer column.
local function FormatTime(seconds)
    if seconds <= 0 then
        return "|cff22ff22Ready|r"
    elseif seconds < 10 then
        return string.format("|cffff3030%.1fs|r",  seconds)
    elseif seconds < 60 then
        return string.format("|cffffd700%.0fs|r",  seconds)
    elseif seconds < 3600 then
        return string.format("|cffffffff%dm%02ds|r",
            math.floor(seconds / 60), seconds % 60)
    else
        return string.format("|cffffffff%dh%02dm|r",
            math.floor(seconds / 3600), math.floor((seconds % 3600) / 60))
    end
end

-- ============================================================
-- Row pool factory
-- ============================================================

LibFramePool:CreatePool(POOL_KEY, function(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(DEFAULT_ROW_H)
    row:RegisterForClicks("LeftButtonUp")

    -- Row background
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    bg:SetVertexColor(0.10, 0.10, 0.10, 0.75)
    row.bg = bg

    -- Cooldown progress bar (fills from left, shrinks to zero)
    local bar = row:CreateTexture(nil, "BORDER")
    bar:SetPoint("TOPLEFT",    row, "TOPLEFT",    0,  0)
    bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0,  0)
    bar:SetWidth(1)
    bar:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    bar:SetVertexColor(0.18, 0.56, 1.00, 0.45)
    row.bar = bar

    -- Spell icon
    local ICON_SIZE = DEFAULT_ROW_H - 4
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("LEFT", row, "LEFT", 2, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon = icon

    -- Player name (class-coloured)
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameText:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    nameText:SetWidth(86)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    row.nameText = nameText

    -- Spell name
    local spellText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    spellText:SetPoint("LEFT", nameText, "RIGHT", 3, 0)
    spellText:SetWidth(80)
    spellText:SetJustifyH("LEFT")
    spellText:SetWordWrap(false)
    spellText:SetTextColor(0.85, 0.85, 0.85)
    row.spellText = spellText

    -- Timer text (right-aligned)
    local timerText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    timerText:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    timerText:SetWidth(52)
    timerText:SetJustifyH("RIGHT")
    row.timerText = timerText

    -- Inline target name: appears between spell text and the timer.
    -- Shown only when targetDisplay == "inline" and a destName is available.
    local destInlineText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    destInlineText:SetPoint("LEFT", timerText, "LEFT", -96, 0)
    destInlineText:SetWidth(92)
    destInlineText:SetJustifyH("LEFT")
    destInlineText:SetWordWrap(false)
    destInlineText:Hide()
    row.destInlineText = destInlineText

    -- Floating target badge: a small styled frame for "float" mode.
    -- Configurable background colour, text size, and text colour.
    local floatFrame = CreateFrame("Frame", nil, row)
    floatFrame:SetFrameLevel(row:GetFrameLevel() + 2)
    floatFrame:SetBackdrop(flatBackdrop)
    floatFrame:SetBackdropColor(0, 0, 0, 0.75)
    floatFrame:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    floatFrame:Hide()
    row.destFloatFrame = floatFrame

    local floatText = floatFrame:CreateFontString(nil, "OVERLAY")
    floatText:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    floatText:SetAllPoints(floatFrame)
    floatText:SetJustifyH("CENTER")
    floatText:SetJustifyV("MIDDLE")
    floatText:SetWordWrap(false)
    row.destFloatText = floatText

    -- Click-to-chat:
    --   Shift+Click  → raid/party/say: [name] - [spell] - [state]
    --   Alt+Click    → whisper player: "Please use [spell] on me"
    --                  (only when the spell is Ready)
    row:SetScript("OnClick", function(self, button)
        if button ~= "LeftButton" then return end
        local data = self._cdData
        if not data then return end
        -- Ignore clicks while in layout-edit mode so they don't fight the mover.
        if LibEditmode:IsEditModeActive(addonName) then return end

        -- Resolve the group config for this row's parent frame.
        local gName   = self:GetParent() and self:GetParent()._groupName
        local gConfig = gName and Cooldowns.db.profile.groups[gName]

        if IsShiftKeyDown() then
            local tmpl = (gConfig and gConfig.shiftClickTemplate)
                      or "%playerName - %spellLink - %condCD(On Cooldown: )%timeLeft %condTarget(- Last Target: %targetName)"
            local msg = FormatChatMessage(tmpl, data)
            local channel
            if GetNumRaidMembers() > 0 then
                channel = "RAID"
            elseif GetNumPartyMembers() > 0 then
                channel = "PARTY"
            else
                channel = "SAY"
            end
            SendChatMessage(msg, channel)
        elseif IsAltKeyDown() then
            -- Only whisper when the spell is actually ready.
            if data.timeLeft <= 0 then
                local tmpl = (gConfig and gConfig.altClickTemplate)
                          or "Please use %spellName on me"
                local msg = FormatChatMessage(tmpl, data)
                SendChatMessage(msg, "WHISPER", nil, data.srcName)
            end
        end
    end)

    return row
end)

-- ============================================================
-- Helpers
-- ============================================================

local function UpdateRow(row, data, rowWidth, gConfig)
    -- Store a reference so click handlers can access it.
    row._cdData = data

    local targetMode = gConfig and gConfig.targetDisplay or "none"
    local hasTarget  = data.destName and data.destName ~= ""

    -- Icon: show or hide based on config (default: show).
    if gConfig and gConfig.showIcon ~= false then
        row.icon:Show()
        row.icon:SetTexture(data.icon)
        -- Restore default anchor (right of icon).
        row.nameText:ClearAllPoints()
        row.nameText:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    else
        row.icon:Hide()
        -- Re-anchor nameText flush to the row's left edge when icon is absent.
        row.nameText:ClearAllPoints()
        row.nameText:SetPoint("LEFT", row, "LEFT", 2, 0)
    end

    -- Player name with class colour
    local cc = classColors[data.className] or { 1, 1, 1 }
    row.nameText:SetText(data.srcName)
    row.nameText:SetTextColor(cc[1], cc[2], cc[3])

    -- Spell name: show or hide based on config (default: show).
    if gConfig and gConfig.showSpellName ~= false then
        row.spellText:Show()
        row.spellText:SetText(Cooldowns:GetSpellDisplayName(data.spellID))
    else
        row.spellText:Hide()
    end

    -- ---- Inline target display ----
    -- Shows "-> TargetName" in the target's class colour between the spell
    -- text and the timer.  Re-uses the same font as the player name text.
    if targetMode == "inline" and hasTarget then
        local dc = classColors[data.destClass] or { 1, 1, 1 }
        row.destInlineText:SetText("-> " .. data.destName)
        row.destInlineText:SetTextColor(dc[1], dc[2], dc[3])
        -- Reposition with configurable X offset (default -96 from timer right).
        local inlineOffX = gConfig and (gConfig.targetInlineOffsetX or 0) or 0
        row.destInlineText:ClearAllPoints()
        row.destInlineText:SetPoint("LEFT", row.timerText, "LEFT", -96 + inlineOffX, 0)
        row.destInlineText:Show()
    else
        row.destInlineText:Hide()
    end

    -- ---- Floating target badge ----
    if targetMode == "float" and hasTarget then
        local fFrame = row.destFloatFrame
        local fText  = row.destFloatText

        -- Apply configurable appearance.
        local bgW  = math.max(20, gConfig.targetBgWidth  or 90)
        local bgH  = math.max(8,  gConfig.targetBgHeight or 16)
        fFrame:SetSize(bgW, bgH)

        -- Background colour: class colour when enabled, otherwise user-configured.
        local bgR, bgG, bgB, bgA
        if gConfig.targetBgColorByClass and data.destClass then
            local dc = classColors[data.destClass] or { 0, 0, 0 }
            bgR, bgG, bgB = dc[1], dc[2], dc[3]
            bgA = gConfig.targetBgA or 0.75
        else
            bgR = gConfig.targetBgR or 0
            bgG = gConfig.targetBgG or 0
            bgB = gConfig.targetBgB or 0
            bgA = gConfig.targetBgA or 0.75
        end
        fFrame:SetBackdropColor(bgR, bgG, bgB, bgA)

        fText:SetFont("Fonts\\FRIZQT__.TTF",
            math.max(6, gConfig.targetFontSize or 11), "")
        -- Text colour: class colour when enabled, otherwise user-configured.
        local tR, tG, tB, tA
        if gConfig.targetTextColorByClass and data.destClass then
            local dc = classColors[data.destClass] or { 1, 1, 1 }
            tR, tG, tB, tA = dc[1], dc[2], dc[3], 1
        else
            tR = gConfig.targetTextR or 1
            tG = gConfig.targetTextG or 1
            tB = gConfig.targetTextB or 1
            tA = gConfig.targetTextA or 1
        end
        fText:SetTextColor(tR, tG, tB, tA)
        fText:SetText(data.destName)

        -- Position: sitting just left of the timer text with configurable offsets.
        local floatOffX = gConfig.targetFloatOffsetX or 0
        local floatOffY = gConfig.targetFloatOffsetY or 0
        fFrame:ClearAllPoints()
        fFrame:SetPoint("RIGHT", row.timerText, "LEFT", -4 + floatOffX, floatOffY)

        fFrame:Show()
    else
        row.destFloatFrame:Hide()
    end

    -- Timer
    row.timerText:SetText(FormatTime(data.timeLeft))

    -- Progress bar: fills from left as cooldown elapses.
    -- pct represents how much of the cooldown has passed (0 = just cast, 1 = ready).
    local colorByClass = gConfig and gConfig.colorBarByClass
    if data.timeLeft > 0 and data.dur > 0 then
        local pct = 1 - (data.timeLeft / data.dur)
        local w   = math.max(1, (rowWidth or row:GetWidth()) * pct)
        row.bar:SetWidth(w)
        -- Bar colour: class colour when colorBarByClass is enabled, else default blue.
        if colorByClass then
            row.bar:SetVertexColor(cc[1], cc[2], cc[3], BAR_ALPHA)
        else
            row.bar:SetVertexColor(0.18, 0.56, 1.00, BAR_ALPHA)
        end
    else
        -- Ready — full bar.
        row.bar:SetWidth(rowWidth or row:GetWidth())
        if colorByClass then
            row.bar:SetVertexColor(cc[1], cc[2], cc[3], BAR_ALPHA)
        else
            row.bar:SetVertexColor(0.10, 0.70, 0.15, 0.30)
        end
    end
end

-- ============================================================
-- Per-group frame management
-- ============================================================

local groupFrames = {}   -- groupName -> frame

local function OnGroupUpdate(frame, elapsed)
    frame._updateTimer = (frame._updateTimer or 0) + elapsed
    if frame._updateTimer < 0.1 then return end
    frame._updateTimer = 0

    local gName   = frame._groupName
    local gConfig = Cooldowns.db.profile.groups[gName]
    if not gConfig then return end

    -- Show / hide the group header based on config (default: show).
    local showHeader = gConfig.showHeader ~= false
    if frame.headerBG then
        if showHeader then frame.headerBG:Show() else frame.headerBG:Hide() end
    end
    if frame.label then
        if showHeader then frame.label:Show() else frame.label:Hide() end
    end

    -- Clamp row height to valid range.
    local rowH = math.max(MIN_ROW_H, math.min(MAX_ROW_H,
        gConfig.rowHeight or DEFAULT_ROW_H))

    local spellGroupSpacing = math.max(0, gConfig.spellGroupSpacing or 4)

    local frameW   = frame:GetWidth()
    local cooldowns = Cooldowns:GetActiveCooldowns(
        gConfig.enabledSpells or {},
        gConfig.roleFilter,
        gConfig.spellRoleFilter)

    -- Filter out "ready" entries when showReady is disabled.
    local rows = {}
    for _, cd in ipairs(cooldowns) do
        if gConfig.showReady or cd.timeLeft > 0 then
            tinsert(rows, cd)
        end
    end

    -- Release surplus row frames back to the pool.
    while #frame.activeRows > #rows do
        local r = tremove(frame.activeRows)
        LibFramePool:Release(r)
    end

    -- Acquire row frames for new entries.
    while #frame.activeRows < #rows do
        local r = LibFramePool:Acquire(POOL_KEY, frame)
        -- Acquire internally calls Show(), but the row has no anchor points yet.
        -- Hide it immediately so it is never rendered in an unpositioned state;
        -- the layout loop below will Show() it after SetPoint() is called.
        r:Hide()
        r:SetWidth(frameW)
        tinsert(frame.activeRows, r)
    end

    -- Update content and layout.
    -- yOffset tracks the top-edge of the next row.  When the header is visible
    -- rows start just below it; when hidden they start at the very top.
    local yOffset = showHeader and HEADER_H or 0
    for i, cd in ipairs(rows) do
        local row = frame.activeRows[i]
        -- Insert configurable spacing between class groups or between spell groups
        -- within the same class.
        if i > 1 and (cd.className ~= rows[i - 1].className
                   or cd.spellID  ~= rows[i - 1].spellID) then
            yOffset = yOffset + spellGroupSpacing
        end
        row:SetWidth(frameW)
        row:SetHeight(rowH)
        -- Resize the icon proportionally.
        row.icon:SetSize(rowH - 4, rowH - 4)
        UpdateRow(row, cd, frameW, gConfig)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -yOffset)
        row:Show()
        yOffset = yOffset + rowH + ROW_PAD
    end

    -- Resize the container to exactly fit its rows plus all inter-group gaps.
    frame:SetHeight(math.max((showHeader and HEADER_H or 0) + 4, yOffset))
end

function ns.CreateGroupFrame(groupName)
    if groupFrames[groupName] then return groupFrames[groupName] end

    local gConfig = Cooldowns.db.profile.groups[groupName]
    if not gConfig then return end

    local w = math.max(MIN_W, gConfig.width or DEFAULT_W)

    local frame = CreateFrame("Frame",
        "CooldownsGroup_" .. groupName:gsub("%s", "_"),
        UIParent)
    frame:SetWidth(w)
    frame:SetHeight(HEADER_H + 4)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("MEDIUM")

    -- Restore saved position (always use CENTER-relative for portability).
    if gConfig.anchorPoint then
        frame:SetPoint(gConfig.anchorPoint, UIParent, gConfig.relPoint or "CENTER",
            gConfig.x or 0, gConfig.y or 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end

    -- Backdrop
    frame:SetBackdrop(flatBackdrop)
    frame:SetBackdropColor(0.06, 0.06, 0.06, 0.88)
    frame:SetBackdropBorderColor(0.22, 0.22, 0.22, 1)

    -- Header bar
    local headerBG = frame:CreateTexture(nil, "ARTWORK")
    headerBG:SetPoint("TOPLEFT",  frame, "TOPLEFT",  1, -1)
    headerBG:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    headerBG:SetHeight(HEADER_H - 2)
    headerBG:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    headerBG:SetVertexColor(0.10, 0.10, 0.10, 1)
    frame.headerBG = headerBG

    -- Group name label
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT",  frame, "TOPLEFT",  5, -(HEADER_H / 2))
    label:SetPoint("RIGHT", frame, "TOPRIGHT", -5, -(HEADER_H / 2))
    label:SetJustifyH("LEFT")
    label:SetText(groupName)
    label:SetTextColor(1, 0.82, 0, 1)
    frame.label = label

    frame.activeRows  = {}
    frame._groupName  = groupName
    frame._updateTimer = 0

    frame:SetScript("OnUpdate", OnGroupUpdate)

    -- Register with LibEditmode so the frame can be repositioned.
    -- addonName scopes the edit-mode toggle to only our frames; syncSize
    -- ensures the drag-handle overlay is sized to match the group frame.
    LibEditmode:Register(frame, {
        label     = "Cooldowns: " .. groupName,
        addonName = addonName,
        syncSize  = true,
        onMove    = function(point, _relTo, relPoint, x, y)
            -- Save the new position into the profile DB.
            local cfg = Cooldowns.db.profile.groups[groupName]
            if cfg then
                cfg.anchorPoint = point
                cfg.relPoint    = relPoint
                cfg.x           = x
                cfg.y           = y
            end
        end,
    })

    groupFrames[groupName] = frame
    return frame
end

function ns.DestroyGroupFrame(groupName)
    local frame = groupFrames[groupName]
    if not frame then return end

    -- Release all active rows.
    for _, row in ipairs(frame.activeRows) do
        LibFramePool:Release(row)
    end
    frame.activeRows = {}

    -- Unregister from LibEditmode.
    LibEditmode:Unregister(frame)

    frame:SetScript("OnUpdate", nil)
    frame:Hide()
    groupFrames[groupName] = nil
end

--- Initialise display frames for every group in the saved profile.
function ns.InitGroups()
    for _, groupName in ipairs(Cooldowns.db.profile.groupOrder) do
        if Cooldowns.db.profile.groups[groupName] then
            ns.CreateGroupFrame(groupName)
        end
    end
end

--- Update the header label of a group frame (e.g. after rename).
function ns.UpdateGroupLabel(groupName)
    local frame = groupFrames[groupName]
    if frame and frame.label then
        frame.label:SetText(groupName)
    end
end

--- Resize all rows in a group when the user changes the width setting.
function ns.UpdateGroupWidth(groupName)
    local frame = groupFrames[groupName]
    if not frame then return end
    local cfg = Cooldowns.db.profile.groups[groupName]
    if not cfg then return end
    local w = math.max(MIN_W, cfg.width or DEFAULT_W)
    frame:SetWidth(w)
    for _, row in ipairs(frame.activeRows) do
        row:SetWidth(w)
    end
end

--- Toggle layout-edit mode for all Cooldowns group frames.
function ns.ToggleEditMode()
    LibEditmode:ToggleEditMode(addonName)
end
