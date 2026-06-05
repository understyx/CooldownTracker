-- Notification.lua
-- Shows an on-screen overlay when another player requests a cooldown from you
-- (via Alt+Click on your cooldown bar in their RaidHelper window).
--
-- Public API exposed on ns:
--   ns.InitNotification()                          — call once after DB is ready
--   ns.ShowCooldownNotification(sender, spellID)   — display the notification

local addonName, ns = ...

local RaidHelper  = ns.RaidHelper
local LibEditmode = LibStub("LibEditmode-1.0")

-- ============================================================
-- Constants
-- ============================================================

local NOTIF_MIN_W   = 200
local NOTIF_MIN_H   = 50
local NOTIF_PAD_X   = 20   -- horizontal text padding
local NOTIF_PAD_Y   = 16   -- vertical text padding
local DEFAULT_FONT  = "Fonts\\FRIZQT__.TTF"

local flatBackdrop = {
    bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
    tile = false, tileSize = 0, edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
}

-- ============================================================
-- Module state
-- ============================================================

local notifFrame   -- the overlay Frame
local hideTimer    -- pending AceTimer handle for auto-hide

-- ============================================================
-- Frame creation
-- ============================================================

function ns.InitNotification()
    if notifFrame then return end

    local cfg = RaidHelper.db.profile.notification

    notifFrame = CreateFrame("Frame", "RaidHelperNotification", UIParent)
    notifFrame:SetWidth(NOTIF_MIN_W)
    notifFrame:SetHeight(NOTIF_MIN_H)
    notifFrame:SetClampedToScreen(true)
    notifFrame:SetFrameStrata("HIGH")
    notifFrame:SetBackdrop(flatBackdrop)
    notifFrame:SetBackdropColor(0, 0, 0, 0.82)
    notifFrame:SetBackdropBorderColor(0.80, 0.60, 0, 1)
    notifFrame:Hide()

    -- Restore saved position.
    if cfg.anchorPoint then
        notifFrame:SetPoint(cfg.anchorPoint, UIParent, cfg.relPoint or "CENTER",
            cfg.x or 0, cfg.y or 0)
    else
        notifFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    end

    -- Main text label.
    local text = notifFrame:CreateFontString(nil, "OVERLAY")
    text:SetFont(DEFAULT_FONT, cfg.fontSize or 22, "OUTLINE")
    text:SetPoint("CENTER", notifFrame, "CENTER", 0, 0)
    text:SetJustifyH("CENTER")
    text:SetJustifyV("MIDDLE")
    text:SetWordWrap(true)
    text:SetWidth(NOTIF_MIN_W - NOTIF_PAD_X)
    text:SetTextColor(1, 0.82, 0, 1)
    notifFrame.text = text

    -- Register with LibEditmode so the player can reposition it.
    LibEditmode:Register(notifFrame, {
        label     = "RaidHelper: Cooldown Notification",
        addonName = addonName,
        syncSize  = true,
        onMove    = function(point, _relTo, relPoint, x, y)
            local c = RaidHelper.db.profile.notification
            c.anchorPoint = point
            c.relPoint    = relPoint
            c.x           = x
            c.y           = y
        end,
    })
end

-- ============================================================
-- Public: show the notification
-- ============================================================

--- Display a cooldown-request notification.
--- @param sender    string  — name of the player who sent the request
--- @param spellID   number  — spell being requested
function ns.ShowCooldownNotification(sender, spellID)
    local cfg = RaidHelper.db.profile.notification
    if not cfg or not cfg.enabled then return end
    if not notifFrame then return end

    -- Cancel any running hide timer.
    if hideTimer then
        RaidHelper:CancelTimer(hideTimer)
        hideTimer = nil
    end

    -- Refresh font size (the user may have changed it in Config).
    notifFrame.text:SetFont(DEFAULT_FONT, cfg.fontSize or 22, "OUTLINE")

    -- Build display text.
    local spellName = RaidHelper:GetSpellDisplayName(spellID)
                   or ("Spell " .. tostring(spellID))
    notifFrame.text:SetText(sender .. "\nrequests " .. spellName .. "!")

    -- Resize frame to fit the text.
    local tw = notifFrame.text:GetStringWidth()  + NOTIF_PAD_X
    local th = notifFrame.text:GetStringHeight() + NOTIF_PAD_Y
    notifFrame:SetWidth(math.max(NOTIF_MIN_W, tw))
    notifFrame:SetHeight(math.max(NOTIF_MIN_H, th))
    -- Keep the text width in sync so wrapping stays correct.
    notifFrame.text:SetWidth(math.max(NOTIF_MIN_W, tw) - NOTIF_PAD_X)

    notifFrame:Show()

    -- Schedule auto-hide.
    hideTimer = RaidHelper:ScheduleTimer(function()
        notifFrame:Hide()
        hideTimer = nil
    end, cfg.duration or 5)
end
