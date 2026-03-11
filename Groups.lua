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
local ROW_H        = 26     -- height of one cooldown row
local ROW_PAD      = 1      -- vertical gap between rows
local MIN_W        = 180    -- minimum group frame width
local DEFAULT_W    = 260

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
-- Row pool factory
-- ============================================================

LibFramePool:CreatePool(POOL_KEY, function(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_H)

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
    local ICON_SIZE = ROW_H - 4
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

    return row
end)

-- ============================================================
-- Helpers
-- ============================================================

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

local function UpdateRow(row, data, rowWidth)
    -- Icon
    row.icon:SetTexture(data.icon)

    -- Player name with class colour
    local cc = classColors[data.className] or { 1, 1, 1 }
    row.nameText:SetText(data.srcName)
    row.nameText:SetTextColor(cc[1], cc[2], cc[3])

    -- Spell name
    row.spellText:SetText(Cooldowns:GetSpellDisplayName(data.spellID))

    -- Timer
    row.timerText:SetText(FormatTime(data.timeLeft))

    -- Progress bar
    if data.timeLeft > 0 and data.dur > 0 then
        local pct = data.timeLeft / data.dur
        local w   = math.max(1, (rowWidth or row:GetWidth()) * pct)
        row.bar:SetWidth(w)
        row.bar:SetVertexColor(0.18, 0.56, 1.00, 0.45)
    else
        -- Ready — show a faint green full bar
        row.bar:SetWidth(rowWidth or row:GetWidth())
        row.bar:SetVertexColor(0.10, 0.70, 0.15, 0.30)
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

    local frameW   = frame:GetWidth()
    local cooldowns = Cooldowns:GetActiveCooldowns(gConfig.enabledSpells or {})

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
        r:SetWidth(frameW)
        tinsert(frame.activeRows, r)
    end

    -- Update content and layout.
    for i, cd in ipairs(rows) do
        local row = frame.activeRows[i]
        row:SetWidth(frameW)
        UpdateRow(row, cd, frameW)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame, "TOPLEFT",
            0, -(HEADER_H + (i - 1) * (ROW_H + ROW_PAD)))
        row:Show()
    end

    -- Resize the container to exactly fit its rows.
    local totalH = HEADER_H + #rows * (ROW_H + ROW_PAD)
    frame:SetHeight(math.max(HEADER_H + 4, totalH))
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
