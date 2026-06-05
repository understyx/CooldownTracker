-- BuffCheck.lua
-- Buff check window that opens automatically when a ready check is initiated.
-- Shows each raid/party member's ready-check response and key WotLK buff status.
--
-- Public API (via ns):
--   ns.InitBuffCheck()       — call once after the DB is ready (from Core.lua OnEnable)
--   ns.ShowBuffCheckWindow() — open / refresh the window manually
--   ns.HideBuffCheckWindow() — close the window
--
-- Event handlers (registered on RaidHelper, called via AceEvent):
--   RaidHelper:OnReadyCheck          — READY_CHECK fires when an RC starts
--   RaidHelper:OnReadyCheckResponse  — READY_CHECK_RESPONSE fires on each player reply
--   RaidHelper:OnReadyCheckConfirm   — READY_CHECK_CONFIRM fires when the RC finishes

local addonName, ns = ...

local RaidHelper  = ns.RaidHelper
local classColors = ns.classColors

-- ============================================================
-- Layout constants
-- ============================================================

local DEFAULT_FONT   = "Fonts\\FRIZQT__.TTF"
local TITLE_H        = 22      -- title-bar height in pixels
local COL_HDR_H      = 16      -- column-label row height in pixels
local DATA_ORIGIN    = TITLE_H + COL_HDR_H   -- y offset where data rows begin
local ROW_H          = 18      -- data row height in pixels
local ROW_PAD        = 1       -- vertical gap between rows
local LEFT_PAD       = 6       -- left padding inside each row
local NAME_W         = 120     -- player name column width
local RC_W           = 55      -- ready-check status column width
local BUFF_W         = 38      -- width of each buff-category column
local WIN_BORDER     = 1       -- outer frame border size
local MAX_WIN_H      = 560     -- window caps here; mouse-wheel scrolls the rest

local flatBackdrop = {
    bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
    tile = false, tileSize = 0, edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
}

-- ============================================================
-- Buff category definitions
-- ============================================================

-- Each entry defines one column in the buff check window.
--   key          : unique identifier (matches profile DB key)
--   label        : short column header shown in the UI (≤ 6 chars)
--   spellIDs     : WotLK 3.3.5 buff-aura spell IDs for this category.
--                  Resolved to localized names via GetSpellInfo at init time.
--   iconSpellID  : spell ID whose icon texture is displayed in the cell when the
--                  buff is present (falls back to spellIDs[1] if omitted).
--   wellFedPattern: if true, also matches any buff whose name contains "Well Fed"
--                  (handles the many different food-buff spell IDs in WotLK).
local BUFF_DEFS = {
    {
        key         = "flask",
        label       = "Flask",
        iconSpellID = 57527,   -- Flask of the Frost Wyrm
        spellIDs = {
            57527,  -- Flask of the Frost Wyrm
            57529,  -- Flask of Endless Rage
            57528,  -- Flask of Stoneblood
            57530,  -- Flask of Pure Mojo
            62380, 62381, 62382, 62383,  -- Flask of the North (4 stat variants)
            17627,  -- Flask of Chromatic Resistance
            17628,  -- Flask of Distilled Wisdom
            17629,  -- Flask of Supreme Power
            17626,  -- Flask of the Titans
            42735,  -- Flask of Chromatic Wonder
            47499,  -- Flask of Fortification
            47500,  -- Flask of Relentless Assault
            47501,  -- Flask of Blinding Light
            47502,  -- Flask of Mighty Restoration
        },
    },
    {
        key            = "food",
        label          = "Food",
        iconSpellID    = 57399,   -- Fish Feast
        wellFedPattern = true,   -- catch any "Well Fed" buff not in the list below
        spellIDs       = {
            -- Fish Feast (three stat variants)
            57399, 57332, 57329,
            -- Common WotLK individual food buffs
            46689,          -- Firecracker Salmon
            46682,          -- Poached Northern Sculpin
            57334,          -- Dragonfin Fillet
            45619, 57358, 57356, 45618,   -- Tender Shoveltusk / Snapper Extreme / Imperial Manta / Rhino Dogs
            43771, 43730, 43722,          -- Cuttlesteak / Smoked Salmon / Worm Supreme
            57360, 57301, 57308,          -- Very Burnt Worg / Black Jelly / Spiced Worm Burger
            35270, 33254, 25696,          -- misc older / TBC-era food buffs that still appear
        },
    },
    {
        key         = "fort",
        label       = "Stam",
        iconSpellID = 48162,   -- Prayer of Fortitude Rank 3
        spellIDs = {
            48162,   -- Prayer of Fortitude (Rank 3 — group)
            48161,   -- Power Word: Fortitude (Rank 7 — single)
            21562,   -- Prayer of Fortitude (Rank 2)
            10937,   -- Prayer of Fortitude (Rank 1)
             1243,   -- Power Word: Fortitude (Rank 1)
        },
    },
    {
        key         = "spirit",
        label       = "Spi",
        iconSpellID = 48074,   -- Prayer of Spirit Rank 2
        spellIDs = {
            48074,   -- Prayer of Spirit (Rank 2 — group, WotLK)
            27681,   -- Prayer of Spirit (Rank 1)
            25312,   -- Divine Spirit (Rank 5)
            27841,   -- Divine Spirit (Rank 4)
            14819,   -- Divine Spirit (Rank 3)
            14818,   -- Divine Spirit (Rank 2)
            14752,   -- Divine Spirit (Rank 1)
        },
    },
    {
        key         = "ai",
        label       = "Int",
        iconSpellID = 42995,   -- Arcane Brilliance Rank 2
        spellIDs = {
            42995,   -- Arcane Brilliance (Rank 2 — group)
            27127,   -- Arcane Intellect (Rank 6 — single)
            23028,   -- Arcane Brilliance (Rank 1)
             1459,   -- Arcane Intellect (Rank 1)
        },
    },
    {
        key         = "kings",
        label       = "Kings",
        iconSpellID = 25898,   -- Greater Blessing of Kings
        spellIDs = {
            20217,   -- Blessing of Kings (single)
            25898,   -- Greater Blessing of Kings (group)
        },
    },
    {
        key         = "motw",
        label       = "MotW",
        iconSpellID = 26990,   -- Gift of the Wild Rank 3
        spellIDs = {
            48469,   -- Mark of the Wild (Rank 8)
            26990,   -- Gift of the Wild (Rank 3 — group)
             1126,   -- Mark of the Wild (Rank 1)
            21849,   -- Gift of the Wild (Rank 1)
        },
    },
    {
        key         = "wisdom",
        label       = "Wisd",
        iconSpellID = 48936,   -- Greater Blessing of Wisdom Rank 2
        spellIDs = {
            48936,   -- Greater Blessing of Wisdom (Rank 2 — group, WotLK)
            48932,   -- Blessing of Wisdom (Rank 6 — single, WotLK)
            25290,   -- Greater Blessing of Wisdom (Rank 1)
            27142,   -- Blessing of Wisdom (Rank 5)
            19853,   -- Blessing of Wisdom (Rank 4)
            19852,   -- Blessing of Wisdom (Rank 3)
            19850,   -- Blessing of Wisdom (Rank 2)
            19742,   -- Blessing of Wisdom (Rank 1)
        },
    },
    {
        key         = "might",
        label       = "Might",
        iconSpellID = 48933,   -- Greater Blessing of Might Rank 2
        spellIDs = {
            48933,   -- Greater Blessing of Might (Rank 2 — group, WotLK)
            48931,   -- Blessing of Might (Rank 8 — single, WotLK)
            48930,   -- Blessing of Might (Rank 7)
            25782,   -- Greater Blessing of Might (Rank 1)
            27140,   -- Blessing of Might (Rank 6)
            25916,   -- Blessing of Might (Rank 5)
            25291,   -- Blessing of Might (Rank 4)
            19835,   -- Blessing of Might (Rank 3)
            19834,   -- Blessing of Might (Rank 2)
            19740,   -- Blessing of Might (Rank 1)
        },
    },
    {
        key         = "ap",
        label       = "AP",
        iconSpellID = 57623,   -- Horn of Winter Rank 2
        spellIDs = {
            57623,   -- Horn of Winter (Rank 2 — WotLK max, Death Knight)
            57330,   -- Horn of Winter (Rank 1)
             2048,   -- Battle Shout (Rank 8 — WotLK max, Warrior)
            25289,   -- Battle Shout (Rank 7)
            11551,   -- Battle Shout (Rank 6)
            11550,   -- Battle Shout (Rank 5)
            11549,   -- Battle Shout (Rank 4)
             6192,   -- Battle Shout (Rank 3)
             5242,   -- Battle Shout (Rank 2)
             6673,   -- Battle Shout (Rank 1)
        },
    },
    {
        key         = "hp",
        label       = "HP",
        iconSpellID = 469,     -- Commanding Shout
        spellIDs = {
            64380,   -- Commanding Shout (Rank 7 — WotLK max, Warrior)
            25202,   -- Commanding Shout (Rank 6)
            11556,   -- Commanding Shout (Rank 5)
            11555,   -- Commanding Shout (Rank 4)
            11554,   -- Commanding Shout (Rank 3)
             6190,   -- Commanding Shout (Rank 2)
              469,   -- Commanding Shout (Rank 1)
            11767,   -- Blood Pact (Rank 5 — Warlock Imp, WotLK max)
            11766,   -- Blood Pact (Rank 4)
             7805,   -- Blood Pact (Rank 3)
             7804,   -- Blood Pact (Rank 2)
             6307,   -- Blood Pact (Rank 1)
        },
    },
}

-- Total window width derived from column layout.
local WIN_W = WIN_BORDER * 2 + LEFT_PAD + NAME_W + RC_W + #BUFF_DEFS * BUFF_W + LEFT_PAD

-- ============================================================
-- Module-level state
-- ============================================================

local bcFrame       -- the main window Frame
local contentFrame  -- ScrollFrame child that rows are parented to
local scrollFrame   -- the ScrollFrame that wraps contentFrame
local rowPool = {}  -- { [i] = rowFrame } — reusable row frames

-- buffNames[catKey] = { [spellName] = true }
-- Built once at init via GetSpellInfo so buff checks are locale-aware.
local buffNames = {}

-- AceTimer handle for the auto-close timer (set on READY_CHECK_CONFIRM).
local autoCloseTimer = nil

-- ============================================================
-- Buff-name lookup set builder
-- ============================================================

local function BuildBuffNameSets()
    for _, def in ipairs(BUFF_DEFS) do
        local set = {}
        for _, sid in ipairs(def.spellIDs) do
            local name = GetSpellInfo(sid)
            if name then set[name] = true end
        end
        buffNames[def.key] = set
        -- Resolve the icon texture once at init so UpdateWindow can use it.
        local iconSID = def.iconSpellID or def.spellIDs[1]
        if iconSID then
            def.iconTexture = select(3, GetSpellInfo(iconSID))
        end
    end
end

-- ============================================================
-- Buff detection
-- ============================================================

-- Returns { [catKey] = true } for every buff category the unit currently has.
-- Only the categories that are enabled in the current profile are tested.
local function ScanUnitBuffs(unitID, enabledCols)
    local found = {}
    local i = 1
    while true do
        local name = UnitBuff(unitID, i)
        if not name then break end
        for _, def in ipairs(BUFF_DEFS) do
            local key = def.key
            if enabledCols[key] and not found[key] then
                local set = buffNames[key]
                if set and set[name] then
                    found[key] = true
                elseif def.wellFedPattern and name:find("Well Fed") then
                    found[key] = true
                end
            end
        end
        i = i + 1
    end
    return found
end

-- ============================================================
-- Ready-check status helpers
-- ============================================================

local RC_READY    = "|TInterface\\RaidFrame\\ReadyCheck-Ready:16:16|t"
local RC_NOTREADY = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:16:16|t"
local RC_WAITING  = "|TInterface\\RaidFrame\\ReadyCheck-Waiting:16:16|t"

local function GetRCText(unitID)
    local s = GetReadyCheckStatus(unitID)
    if     s == "ready"    then return RC_READY
    elseif s == "notready" then return RC_NOTREADY
    elseif s == "waiting"  then return RC_WAITING
    else                        return ""
    end
end

-- ============================================================
-- Row frame factory
-- ============================================================

-- Returns a new row frame parented to `parent`.
-- The frame's sub-elements (nameText, rcText, buffCells[]) have NO
-- data set — UpdateRow populates them on each refresh.
local function CreateRowFrame(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_H)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    bg:SetVertexColor(0.08, 0.08, 0.08, 0.6)
    row.bg = bg

    local nameText = row:CreateFontString(nil, "OVERLAY")
    nameText:SetFont(DEFAULT_FONT, 11, "")
    nameText:SetPoint("LEFT", row, "LEFT", LEFT_PAD, 0)
    nameText:SetWidth(NAME_W)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    row.nameText = nameText

    local rcText = row:CreateFontString(nil, "OVERLAY")
    rcText:SetFont(DEFAULT_FONT, 11, "")
    rcText:SetPoint("LEFT", nameText, "RIGHT", 0, 0)
    rcText:SetWidth(RC_W)
    rcText:SetJustifyH("CENTER")
    row.rcText = rcText

    -- One icon texture per buff category (visibility driven by enabledCols).
    row.buffCells = {}
    local prev = rcText
    for colIdx = 1, #BUFF_DEFS do
        local cellFrame = CreateFrame("Frame", nil, row)
        cellFrame:SetPoint("LEFT", prev, "RIGHT", 0, 0)
        cellFrame:SetWidth(BUFF_W)
        cellFrame:SetHeight(ROW_H)

        local icon = cellFrame:CreateTexture(nil, "OVERLAY")
        icon:SetSize(16, 16)
        icon:SetPoint("CENTER", cellFrame, "CENTER", 0, 0)
        icon:Hide()

        cellFrame.icon = icon
        row.buffCells[colIdx] = cellFrame
        prev = cellFrame
    end

    return row
end

-- ============================================================
-- Window update
-- ============================================================

-- Rebuild the window contents from the current group / raid roster.
local function UpdateWindow()
    if not bcFrame or not bcFrame:IsShown() then return end

    local cfg         = RaidHelper.db.profile.buffCheck
    local enabledCols = cfg.columns or {}

    -- Collect all group members (unitID + name).
    local members = {}
    if GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            local uid  = "raid" .. i
            local name = GetUnitName(uid)
            if name and name ~= UNKNOWNOBJECT then
                tinsert(members, { unitID = uid, name = name })
            end
        end
    else
        local pname = UnitName("player")
        if pname then tinsert(members, { unitID = "player", name = pname }) end
        for i = 1, GetNumPartyMembers() do
            local uid  = "party" .. i
            local name = GetUnitName(uid)
            if name and name ~= UNKNOWNOBJECT then
                tinsert(members, { unitID = uid, name = name })
            end
        end
    end

    -- Stable alphabetical sort by name.
    table.sort(members, function(a, b) return a.name < b.name end)

    local innerW     = WIN_W - WIN_BORDER * 2
    local totalRowH  = #members * (ROW_H + ROW_PAD)
    local yOff       = 0   -- relative to contentFrame

    -- Grow the row pool on demand.
    while #rowPool < #members do
        tinsert(rowPool, CreateRowFrame(contentFrame))
    end

    -- Update and position visible rows.
    for i, m in ipairs(members) do
        local row = rowPool[i]
        row:SetWidth(innerW)

        -- Alternating row shading.
        if (i % 2 == 0) then
            row.bg:SetVertexColor(0.10, 0.10, 0.10, 0.6)
        else
            row.bg:SetVertexColor(0.06, 0.06, 0.06, 0.6)
        end

        -- Player name coloured by class.
        local _, className = UnitClass(m.unitID)
        local cc = classColors[className] or { 1, 1, 1 }
        row.nameText:SetTextColor(cc[1], cc[2], cc[3])
        row.nameText:SetText(m.name)

        -- Ready-check status.
        row.rcText:SetText(GetRCText(m.unitID))

        -- Buff cells.
        local found = ScanUnitBuffs(m.unitID, enabledCols)
        for colIdx, def in ipairs(BUFF_DEFS) do
            local cell = row.buffCells[colIdx]
            if enabledCols[def.key] ~= false then
                if found[def.key] and def.iconTexture then
                    cell.icon:SetTexture(def.iconTexture)
                    cell.icon:Show()
                else
                    cell.icon:Hide()
                end
                cell:Show()
            else
                cell.icon:Hide()
                cell:Hide()
            end
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, -yOff)
        row:Show()

        yOff = yOff + ROW_H + ROW_PAD
    end

    -- Hide surplus rows from a previous call.
    for i = #members + 1, #rowPool do
        rowPool[i]:Hide()
    end

    -- Resize the virtual content frame so the ScrollFrame knows the full extent.
    contentFrame:SetHeight(math.max(totalRowH, 1))

    -- Resize the window: cap at MAX_WIN_H so it stays on screen.
    local dataH  = math.min(totalRowH, MAX_WIN_H - DATA_ORIGIN - WIN_BORDER)
    local newWinH = DATA_ORIGIN + dataH + WIN_BORDER
    bcFrame:SetHeight(newWinH)
end

-- ============================================================
-- Public API
-- ============================================================

--- Initialise the buff check window and register READY_CHECK events.
--- Called once from Core.lua OnEnable, after the DB has been set up.
function ns.InitBuffCheck()
    if bcFrame then return end

    BuildBuffNameSets()

    local cfg = RaidHelper.db.profile.buffCheck

    -- ---- Outer window frame ----
    bcFrame = CreateFrame("Frame", "RaidHelperBuffCheck", UIParent)
    bcFrame:SetWidth(WIN_W)
    bcFrame:SetHeight(DATA_ORIGIN + 4)
    bcFrame:SetClampedToScreen(true)
    bcFrame:SetFrameStrata("HIGH")
    bcFrame:SetMovable(true)
    bcFrame:EnableMouse(true)
    bcFrame:RegisterForDrag("LeftButton")

    bcFrame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    bcFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Persist the new position so it survives reloads.
        local point, _, relPoint, x, y = self:GetPoint()
        local c = RaidHelper.db.profile.buffCheck
        c.anchorPoint = point
        c.relPoint    = relPoint
        c.x           = x
        c.y           = y
    end)

    bcFrame:SetBackdrop(flatBackdrop)
    bcFrame:SetBackdropColor(0.06, 0.06, 0.06, 0.92)
    bcFrame:SetBackdropBorderColor(0.22, 0.22, 0.22, 1)

    -- ---- Title bar ----
    local titleBG = bcFrame:CreateTexture(nil, "ARTWORK")
    titleBG:SetPoint("TOPLEFT",  bcFrame, "TOPLEFT",  WIN_BORDER, -WIN_BORDER)
    titleBG:SetPoint("TOPRIGHT", bcFrame, "TOPRIGHT", -WIN_BORDER, -WIN_BORDER)
    titleBG:SetHeight(TITLE_H - 2)
    titleBG:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    titleBG:SetVertexColor(0.10, 0.10, 0.10, 1)

    local titleText = bcFrame:CreateFontString(nil, "OVERLAY")
    titleText:SetFont(DEFAULT_FONT, 12, "OUTLINE")
    titleText:SetPoint("LEFT",  bcFrame, "TOPLEFT",  LEFT_PAD, -(TITLE_H / 2))
    titleText:SetPoint("RIGHT", bcFrame, "TOPRIGHT", -24, -(TITLE_H / 2))
    titleText:SetJustifyH("LEFT")
    titleText:SetText("|cffffd700Buff Check|r")

    -- ---- Close button ----
    local closeBtn = CreateFrame("Button", nil, bcFrame, "UIPanelCloseButton")
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("TOPRIGHT", bcFrame, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function()
        -- Cancel any pending auto-close when the user dismisses manually.
        if autoCloseTimer then
            RaidHelper:CancelTimer(autoCloseTimer)
            autoCloseTimer = nil
        end
        bcFrame:Hide()
    end)

    -- ---- Column header row ----
    local hdr = CreateFrame("Frame", nil, bcFrame)
    hdr:SetPoint("TOPLEFT",  bcFrame, "TOPLEFT",  WIN_BORDER, -TITLE_H)
    hdr:SetPoint("TOPRIGHT", bcFrame, "TOPRIGHT", -WIN_BORDER, -TITLE_H)
    hdr:SetHeight(COL_HDR_H)

    local hdrBg = hdr:CreateTexture(nil, "BACKGROUND")
    hdrBg:SetAllPoints()
    hdrBg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    hdrBg:SetVertexColor(0.12, 0.12, 0.12, 0.9)

    local hName = hdr:CreateFontString(nil, "OVERLAY")
    hName:SetFont(DEFAULT_FONT, 10, "OUTLINE")
    hName:SetPoint("LEFT", hdr, "LEFT", LEFT_PAD, 0)
    hName:SetWidth(NAME_W)
    hName:SetJustifyH("LEFT")
    hName:SetTextColor(0.7, 0.7, 0.7)
    hName:SetText("Player")

    local hRC = hdr:CreateFontString(nil, "OVERLAY")
    hRC:SetFont(DEFAULT_FONT, 10, "OUTLINE")
    hRC:SetPoint("LEFT", hName, "RIGHT", 0, 0)
    hRC:SetWidth(RC_W)
    hRC:SetJustifyH("CENTER")
    hRC:SetTextColor(0.7, 0.7, 0.7)
    hRC:SetText("Ready")

    local prevHdr = hRC
    for _, def in ipairs(BUFF_DEFS) do
        local hCell = hdr:CreateFontString(nil, "OVERLAY")
        hCell:SetFont(DEFAULT_FONT, 10, "OUTLINE")
        hCell:SetPoint("LEFT", prevHdr, "RIGHT", 0, 0)
        hCell:SetWidth(BUFF_W)
        hCell:SetJustifyH("CENTER")
        hCell:SetTextColor(0.7, 0.7, 0.7)
        hCell:SetText(def.label)
        prevHdr = hCell
    end

    -- ---- ScrollFrame + content frame ----
    scrollFrame = CreateFrame("ScrollFrame", "RaidHelperBuffCheckScroll", bcFrame)
    scrollFrame:SetPoint("TOPLEFT",     bcFrame, "TOPLEFT",     WIN_BORDER, -DATA_ORIGIN)
    scrollFrame:SetPoint("BOTTOMRIGHT", bcFrame, "BOTTOMRIGHT", -WIN_BORDER, WIN_BORDER)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local step    = (ROW_H + ROW_PAD) * 3
        local current = self:GetVerticalScroll()
        local maxVal  = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(0, math.min(maxVal, current - delta * step)))
    end)

    contentFrame = CreateFrame("Frame", nil, scrollFrame)
    contentFrame:SetWidth(WIN_W - WIN_BORDER * 2)
    contentFrame:SetHeight(1)   -- will be updated by UpdateWindow
    scrollFrame:SetScrollChild(contentFrame)

    -- ---- OnUpdate: refresh at 0.5 s intervals while visible ----
    bcFrame:SetScript("OnUpdate", function(self, elapsed)
        self._t = (self._t or 0) + elapsed
        if self._t >= 0.5 then
            self._t = 0
            UpdateWindow()
        end
    end)

    -- ---- Restore saved position ----
    if cfg.anchorPoint then
        bcFrame:SetPoint(cfg.anchorPoint, UIParent, cfg.relPoint or "CENTER",
            cfg.x or 0, cfg.y or 0)
    else
        bcFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end

    bcFrame:Hide()

    -- ---- Register READY_CHECK events on the RaidHelper object ----
    RaidHelper:RegisterEvent("READY_CHECK",          "OnReadyCheck")
    RaidHelper:RegisterEvent("READY_CHECK_RESPONSE", "OnReadyCheckResponse")
    RaidHelper:RegisterEvent("READY_CHECK_CONFIRM",  "OnReadyCheckConfirm")
end

--- Open (or refresh) the buff check window.
function ns.ShowBuffCheckWindow()
    if not bcFrame then return end
    local cfg = RaidHelper.db.profile.buffCheck
    if cfg and cfg.enabled == false then return end
    UpdateWindow()
    bcFrame:Show()
end

--- Close the buff check window.
function ns.HideBuffCheckWindow()
    if bcFrame then bcFrame:Hide() end
end

-- ============================================================
-- Event handlers (defined on RaidHelper; registered in InitBuffCheck)
-- ============================================================

--- Fires when a ready check is initiated.
function RaidHelper:OnReadyCheck(event)
    -- Cancel any pending auto-close from a previous RC.
    if autoCloseTimer then
        self:CancelTimer(autoCloseTimer)
        autoCloseTimer = nil
    end
    local cfg = self.db.profile.buffCheck
    if cfg and cfg.enabled ~= false and cfg.autoShow ~= false then
        ns.ShowBuffCheckWindow()
    end
end

--- Fires whenever a single player submits their ready-check response.
--- The 0.5 s OnUpdate timer will pick up the new GetReadyCheckStatus value
--- automatically, so no explicit action is needed here.
function RaidHelper:OnReadyCheckResponse(event)
    -- Intentionally empty — handled by the polling timer in UpdateWindow.
end

--- Fires when the ready check concludes (all answered or the timer expired).
function RaidHelper:OnReadyCheckConfirm(event)
    -- One immediate update to capture the final state.
    UpdateWindow()

    local cfg = self.db.profile.buffCheck
    if cfg and cfg.enabled ~= false and cfg.autoClose ~= false then
        local delay = cfg.autoCloseDuration or 10
        autoCloseTimer = self:ScheduleTimer(function()
            ns.HideBuffCheckWindow()
            autoCloseTimer = nil
        end, delay)
    end
end
