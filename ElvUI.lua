-- ElvUI.lua
-- ElvUI Party/Raid Unit Frame Integration for RaidHelper.
-- Displays icons of ready and active cooldowns directly on ElvUI frames.
-- Ready cooldowns display as standard icons, while active cooldowns
-- glow and display with a cooldown swipe.

local addonName, ns = ...
local RaidHelper = ns.RaidHelper
local spellData = ns.spellData

local CreateFrame = CreateFrame
local GetTime = GetTime
local UnitClass = UnitClass
local GetUnitName = GetUnitName
local ipairs, pairs, select, table = ipairs, pairs, select, table

local activeContainers = {}
local iconCache = {}

-- Lazy-load and cache the correct icon (trinket item texture or spell icon)
local function GetSpellIcon(spellID)
    if iconCache[spellID] then
        return iconCache[spellID]
    end
    local icon
    local trinketIDs = ns.itemTrinketIDs and ns.itemTrinketIDs[spellID]
    if trinketIDs then
        icon = select(10, GetItemInfo(trinketIDs[1]))
    end
    if not icon then
        icon = select(3, GetSpellInfo(spellID))
    end
    if icon then
        iconCache[spellID] = icon
    end
    return icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- Helper to create individual icon frames
local function CreateIconFrame(parent)
    local f = CreateFrame("Frame", nil, parent)

    -- Black border background
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", -1, 1)
    bg:SetPoint("BOTTOMRIGHT", 1, -1)
    bg:SetTexture(0, 0, 0, 1)
    f.bg = bg

    -- Zoomed icon texture to match ElvUI pixel-perfect border look
    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.texture = tex

    -- Cooldown swipe overlay
    local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetReverse(true)
    f.cooldown = cd

    -- Glowing border overlay
    local glow = f:CreateTexture(nil, "OVERLAY")
    glow:SetPoint("TOPLEFT", -3, 3)
    glow:SetPoint("BOTTOMRIGHT", 3, -3)
    glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    glow:SetBlendMode("ADD")
    f.glow = glow

    return f
end

-- Update function for a frame's integration container
local function Container_Update(self)
    local db = RaidHelper.db.profile.elvui
    if not db or not db.enabled then
        self:Hide()
        return
    end

    local parent = self:GetParent()
    if not parent or not parent:IsShown() then
        self:Hide()
        return
    end

    local unit = parent.unit or parent:GetAttribute("unit")
    if not unit then
        self:Hide()
        return
    end

    local unitName = GetUnitName(unit, true)
    if not unitName or unitName == UNKNOWNOBJECT then
        self:Hide()
        return
    end

    local cooldowns = RaidHelper:GetUnitCooldowns(unitName)
    if not cooldowns then
        self:Hide()
        return
    end

    -- Query unit class for sorting
    local _, class = UnitClass(unit)
    if not class then
        self:Hide()
        return
    end

    -- Collect and filter eligible cooldowns
    local list = {}
    local now = GetTime()
    local mode = db.displayMode or "always"
    for spellID, info in pairs(cooldowns) do
        if db.enabledSpells[spellID] then
            local timeLeft = info.expTime and (info.expTime - now) or 0
            local isActive = timeLeft > 0

            local show = false
            if mode == "always" then
                show = true
            elseif mode == "ready" and not isActive then
                show = true
            elseif mode == "active" and isActive then
                show = true
            end

            if show then
                local index = 99
                if spellData[class] and spellData[class][spellID] then
                    index = spellData[class][spellID].index or 99
                elseif spellData["ITEMS"] and spellData["ITEMS"][spellID] then
                    index = spellData["ITEMS"][spellID].index or 99
                end

                table.insert(list, {
                    spellID = spellID,
                    isActive = isActive,
                    timeLeft = timeLeft,
                    dur = info.dur,
                    index = index,
                    icon = GetSpellIcon(spellID)
                })
            end
        end
    end

    if #list == 0 then
        self:Hide()
        return
    end

    -- Sort: Active (glowing) first, then stable by index
    table.sort(list, function(a, b)
        if a.isActive ~= b.isActive then
            return a.isActive
        end
        return a.index < b.index
    end)

    -- Cap by maxIcons setting
    local maxIcons = db.maxIcons or 5
    local numIcons = math.min(#list, maxIcons)

    if numIcons == 0 then
        self:Hide()
        return
    end

    self:Show()

    -- Apply user-configured anchor and offsets
    self:ClearAllPoints()
    self:SetPoint(db.anchorPoint, parent, db.anchorPoint, db.xOffset, db.yOffset)

    -- Apply user-configured frame strata and frame level
    if db.frameStrata then
        self:SetFrameStrata(db.frameStrata)
    end
    if db.frameLevel then
        self:SetFrameLevel(db.frameLevel)
    end

    local isHorizontal = db.orientation == "Horizontal"
    local size = db.iconSize or 18
    local spacing = db.spacing or 2

    -- Adjust container size to enclose visible icons exactly
    if isHorizontal then
        self:SetWidth(size * numIcons + spacing * (numIcons - 1))
        self:SetHeight(size)
    else
        self:SetHeight(size * numIcons + spacing * (numIcons - 1))
        self:SetWidth(size)
    end

    -- Calculate pulsing glow alpha (cycles between 0.5 and 1.0)
    local pulse = 0.75 + 0.25 * math.sin(GetTime() * 5)
    local gc = db.glowColor or { 1, 0.85, 0, 1 }

    -- Update and display icons
    for i = 1, numIcons do
        local item = list[i]
        local iconFrame = self.icons[i]
        if not iconFrame then
            iconFrame = CreateIconFrame(self)
            self.icons[i] = iconFrame
        end

        iconFrame:SetSize(size, size)
        iconFrame.texture:SetTexture(item.icon)

        iconFrame:ClearAllPoints()
        if i == 1 then
            if isHorizontal then
                iconFrame:SetPoint("LEFT", self, "LEFT", 0, 0)
            else
                iconFrame:SetPoint("TOP", self, "TOP", 0, 0)
            end
        else
            if isHorizontal then
                iconFrame:SetPoint("LEFT", self.icons[i - 1], "RIGHT", spacing, 0)
            else
                iconFrame:SetPoint("TOP", self.icons[i - 1], "BOTTOM", 0, -spacing)
            end
        end

        if item.isActive then
            -- Cooldown is active: show countdown swipe and a glowing border
            iconFrame.cooldown:SetCooldown(now - (item.dur - item.timeLeft), item.dur)
            iconFrame.cooldown:Show()

            iconFrame.glow:SetVertexColor(gc[1], gc[2], gc[3], gc[4] or 1)
            iconFrame.glow:SetAlpha(pulse)
            iconFrame.glow:Show()
        else
            -- Cooldown is ready: simple icon display (no glow/swipe)
            iconFrame.cooldown:Hide()
            iconFrame.glow:Hide()
        end

        iconFrame:Show()
    end

    -- Recycle unused icon frames
    for i = numIcons + 1, #self.icons do
        self.icons[i]:Hide()
    end
end

local function Container_OnUpdate(self, elapsed)
    self.timer = (self.timer or 0) + elapsed
    if self.timer < 0.1 then return end
    self.timer = 0
    Container_Update(self)
end

-- Scan all ElvUI unit frames and attach the cooldown container frame
local function ScanElvUIFrames()
    if not _G.ElvUF or not _G.ElvUF.objects then return end

    local db = RaidHelper.db.profile.elvui
    if not db or not db.enabled then
        -- Hide all containers if integration is disabled
        for _, container in ipairs(activeContainers) do
            container:Hide()
        end
        return
    end

    for _, frame in ipairs(_G.ElvUF.objects) do
        local name = frame:GetName()
        if name and (name:find("^ElvUF_Party") or name:find("^ElvUF_Raid")) then
            -- Exclude pet and target frames
            local isPetOrTarget = name:find("pet") or name:find("Target")
            if not isPetOrTarget and not frame.RaidHelperContainer then
                local container = CreateFrame("Frame", nil, frame)
                container.icons = {}
                container:SetScript("OnUpdate", Container_OnUpdate)
                container.Update = Container_Update

                frame.RaidHelperContainer = container
                table.insert(activeContainers, container)
            end
        end
    end
end

-- Public initializer called by Core.lua OnEnable
function ns.InitElvUI()
    if not _G.ElvUI and not _G.ElvUF then return end

    -- Perform initial scan
    ScanElvUIFrames()

    -- Start periodic scan to hook any dynamically spawned or reloaded unit frames
    RaidHelper:ScheduleRepeatingTimer(ScanElvUIFrames, 2)
end
