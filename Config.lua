-- Config.lua
-- AceConfig/AceConfigDialog options panel for the Cooldowns addon.
--
-- Usage in-game:
--   /cooldowns   or   /cd   → open the options window
--
-- The panel is built dynamically so it reflects the current set of groups
-- and their per-spell selections at all times.

local addonName, ns = ...

local Cooldowns       = ns.Cooldowns
local spellData       = ns.spellData
local classDisplayNames = ns.classDisplayNames
local classOrder        = ns.classOrder

local AceConfig        = LibStub("AceConfig-3.0")
local AceConfigDialog  = LibStub("AceConfigDialog-3.0")
local AceConfigReg     = LibStub("AceConfigRegistry-3.0")

-- ============================================================
-- Helpers
-- ============================================================

-- Force a full rebuild of the options tree (used after add/remove/rename).
local function NotifyChanged()
    AceConfigReg:NotifyChange(addonName)
end

-- Derive a short spell description: "SpellName (Ns)"
local function SpellDesc(spellID, dur)
    local name = Cooldowns:GetSpellDisplayName(spellID)
    if dur then
        if dur >= 60 then
            return string.format("%s (%dm)", name, math.floor(dur / 60))
        else
            return string.format("%s (%ds)", name, dur)
        end
    end
    return name
end

-- ============================================================
-- Build per-group spells sub-tree
-- ============================================================

local function BuildSpellArgs(groupName)
    local args    = {}
    local gConfig = Cooldowns.db.profile.groups[groupName]
    if not gConfig then return args end

    local order = 1

    for _, className in ipairs(classOrder) do
        local classData = spellData[className]
        if classData then
            -- Class heading
            args["heading_" .. className] = {
                type  = "header",
                name  = classDisplayNames[className] or className,
                order = order,
            }
            order = order + 1

            -- Collect spells sorted by their index field.
            local spellList = {}
            for spellID, data in pairs(classData) do
                tinsert(spellList, { id = spellID, data = data })
            end
            table.sort(spellList, function(a, b)
                return (a.data.index or 0) < (b.data.index or 0)
            end)

            for _, entry in ipairs(spellList) do
                local spellID = entry.id
                local data    = entry.data
                local key     = "spell_" .. className .. "_" .. spellID

                args[key] = {
                    type  = "toggle",
                    name  = SpellDesc(spellID, data.dur),
                    order = order,
                    get   = function()
                        local cfg = Cooldowns.db.profile.groups[groupName]
                        return cfg and cfg.enabledSpells
                            and cfg.enabledSpells[spellID] or false
                    end,
                    set   = function(_, val)
                        local cfg = Cooldowns.db.profile.groups[groupName]
                        if cfg then
                            cfg.enabledSpells          = cfg.enabledSpells or {}
                            cfg.enabledSpells[spellID] = val or nil
                        end
                    end,
                }
                order = order + 1
            end
        end
    end

    return args
end

-- ============================================================
-- Role Based Spell Filter – UI state and helpers
-- ============================================================

-- Tracks which spell is currently selected in each group's "Role Based Spell
-- Filter" selector.  Stored as tostring(spellID) to match AceConfig select
-- keys.  This is pure runtime UI state and is not persisted to the DB.
local selectedSpellForRoleFilter = {}   -- [groupName] = tostring(spellID) | nil

-- Ordered role keys and their display labels — shared by the status description
-- and the toggle generation loop.
local ROLE_KEYS   = { "tank", "healer", "melee", "caster" }
local ROLE_LABELS = { tank = "Tank", healer = "Healer", melee = "Melee", caster = "Caster" }

local function GetSelectedSpellRole(groupName, roleKey)
    local sel = selectedSpellForRoleFilter[groupName]
    if not sel then return false end
    local spellID = tonumber(sel)
    if not spellID then return false end
    local cfg = Cooldowns.db.profile.groups[groupName]
    return cfg and cfg.spellRoleFilter
        and cfg.spellRoleFilter[spellID]
        and cfg.spellRoleFilter[spellID][roleKey] or false
end

local function SetSelectedSpellRole(groupName, roleKey, val)
    local sel = selectedSpellForRoleFilter[groupName]
    if not sel then return end
    local spellID = tonumber(sel)
    if not spellID then return end
    local cfg = Cooldowns.db.profile.groups[groupName]
    if not cfg then return end
    cfg.spellRoleFilter                   = cfg.spellRoleFilter or {}
    cfg.spellRoleFilter[spellID]          = cfg.spellRoleFilter[spellID] or {}
    cfg.spellRoleFilter[spellID][roleKey] = val
    -- Remove the sub-table when all roles are unchecked so nil == no restriction.
    local hasAny = false
    for _, v in pairs(cfg.spellRoleFilter[spellID]) do
        if v then hasAny = true; break end
    end
    if not hasAny then cfg.spellRoleFilter[spellID] = nil end
end

-- ============================================================
-- Build per-group top-level options
-- ============================================================

local function BuildGroupArgs(groupName)
    local gConfig = Cooldowns.db.profile.groups[groupName]
    if not gConfig then return {} end

    local args = {
        -- ---- General settings ----
        generalHeader = {
            type  = "header",
            name  = "General",
            order = 1,
        },

        rename = {
            type  = "input",
            name  = "Group name",
            desc  = "Rename this group (also updates the display header).",
            order = 2,
            get   = function()
                local cfg = Cooldowns.db.profile.groups[groupName]
                return cfg and cfg.name or groupName
            end,
            set   = function(_, newName)
                newName = newName:match("^%s*(.-)%s*$")   -- trim
                if newName == "" or newName == groupName then return end
                if Cooldowns:RenameGroup(groupName, newName) then
                    NotifyChanged()
                else
                    Cooldowns:Print("A group named '" .. newName .. "' already exists.")
                end
            end,
        },

        showReady = {
            type  = "toggle",
            name  = "Show ready cooldowns",
            desc  = "Display rows for cooldowns that are available (not on cooldown).",
            order = 3,
            get   = function()
                local cfg = Cooldowns.db.profile.groups[groupName]
                return cfg and cfg.showReady or false
            end,
            set   = function(_, val)
                local cfg = Cooldowns.db.profile.groups[groupName]
                if cfg then cfg.showReady = val end
            end,
        },

        displayHeader = {
            type  = "header",
            name  = "Display",
            order = 3.1,
        },

        showHeader = {
            type  = "toggle",
            name  = "Show group header",
            desc  = "Show or hide the group name header bar at the top of the frame.",
            order = 3.2,
            get   = function()
                local cfg = Cooldowns.db.profile.groups[groupName]
                -- Default true: header is shown unless explicitly disabled.
                return cfg and cfg.showHeader ~= false
            end,
            set   = function(_, val)
                local cfg = Cooldowns.db.profile.groups[groupName]
                if cfg then cfg.showHeader = val end
            end,
        },

        colorBarByClass = {
            type  = "toggle",
            name  = "Color bar by class",
            desc  = "Tint the cooldown progress bar with the caster's class colour.",
            order = 3.3,
            get   = function()
                local cfg = Cooldowns.db.profile.groups[groupName]
                return cfg and cfg.colorBarByClass or false
            end,
            set   = function(_, val)
                local cfg = Cooldowns.db.profile.groups[groupName]
                if cfg then cfg.colorBarByClass = val end
            end,
        },

        showIcon = {
            type  = "toggle",
            name  = "Show spell icon",
            desc  = "Show the spell or ability icon on each cooldown row.",
            order = 3.4,
            get   = function()
                local cfg = Cooldowns.db.profile.groups[groupName]
                -- Default true: icon is shown unless explicitly disabled.
                return cfg and cfg.showIcon ~= false
            end,
            set   = function(_, val)
                local cfg = Cooldowns.db.profile.groups[groupName]
                if cfg then cfg.showIcon = val end
            end,
        },

        showSpellName = {
            type  = "toggle",
            name  = "Show spell name",
            desc  = "Show the spell or ability name on each cooldown row.",
            order = 3.5,
            get   = function()
                local cfg = Cooldowns.db.profile.groups[groupName]
                -- Default true: spell name is shown unless explicitly disabled.
                return cfg and cfg.showSpellName ~= false
            end,
            set   = function(_, val)
                local cfg = Cooldowns.db.profile.groups[groupName]
                if cfg then cfg.showSpellName = val end
            end,
        },

        width = {
            type  = "range",
            name  = "Frame width",
            desc  = "Width of the group display frame in pixels.",
            order = 4,
            min   = 100,
            max   = 600,
            step  = 10,
            get   = function()
                local cfg = Cooldowns.db.profile.groups[groupName]
                return cfg and cfg.width or 260
            end,
            set   = function(_, val)
                local cfg = Cooldowns.db.profile.groups[groupName]
                if cfg then
                    cfg.width = val
                    ns.UpdateGroupWidth(groupName)
                end
            end,
        },

        rowHeight = {
            type  = "range",
            name  = "Row height",
            desc  = "Height of each cooldown row in pixels.",
            order = 5,
            min   = 10,
            max   = 50,
            step  = 1,
            get   = function()
                local cfg = Cooldowns.db.profile.groups[groupName]
                return cfg and cfg.rowHeight or 26
            end,
            set   = function(_, val)
                local cfg = Cooldowns.db.profile.groups[groupName]
                if cfg then cfg.rowHeight = val end
            end,
        },

        spellGroupSpacing = {
            type  = "range",
            name  = "Spell group spacing",
            desc  = "Extra gap (in pixels) inserted between rows of different spells.",
            order = 6,
            min   = 0,
            max   = 20,
            step  = 1,
            get   = function()
                local cfg = Cooldowns.db.profile.groups[groupName]
                return cfg and cfg.spellGroupSpacing or 4
            end,
            set   = function(_, val)
                local cfg = Cooldowns.db.profile.groups[groupName]
                if cfg then cfg.spellGroupSpacing = val end
            end,
        },

        deleteGroup = {
            type    = "execute",
            name    = "Delete group",
            desc    = "Permanently remove this group and its display frame.",
            order   = 7,
            confirm = true,
            confirmText = "Delete group '" .. groupName .. "'?",
            func    = function()
                Cooldowns:DeleteGroup(groupName)
                NotifyChanged()
            end,
        },

        -- ---- Global Group Role Filter ----
        roleHeader = {
            type  = "header",
            name  = "Global Group Role Filter",
            order = 8,
        },

        roleDesc = {
            type  = "description",
            name  = "Only show cooldowns for players with the selected roles. "
                 .. "Leave all unchecked to show every role. "
                 .. "This filter applies to all spells in this group.",
            order = 9,
        },

        roleTank = {
            type  = "toggle",
            name  = "Tank",
            order = 10,
            get   = function()
                local cfg = Cooldowns.db.profile.groups[groupName]
                return cfg and cfg.roleFilter and cfg.roleFilter["tank"] or false
            end,
            set   = function(_, val)
                local cfg = Cooldowns.db.profile.groups[groupName]
                if cfg then
                    cfg.roleFilter = cfg.roleFilter or {}
                    cfg.roleFilter["tank"] = val or nil
                end
            end,
        },

        roleHealer = {
            type  = "toggle",
            name  = "Healer",
            order = 11,
            get   = function()
                local cfg = Cooldowns.db.profile.groups[groupName]
                return cfg and cfg.roleFilter and cfg.roleFilter["healer"] or false
            end,
            set   = function(_, val)
                local cfg = Cooldowns.db.profile.groups[groupName]
                if cfg then
                    cfg.roleFilter = cfg.roleFilter or {}
                    cfg.roleFilter["healer"] = val or nil
                end
            end,
        },

        roleMelee = {
            type  = "toggle",
            name  = "Melee",
            order = 12,
            get   = function()
                local cfg = Cooldowns.db.profile.groups[groupName]
                return cfg and cfg.roleFilter and cfg.roleFilter["melee"] or false
            end,
            set   = function(_, val)
                local cfg = Cooldowns.db.profile.groups[groupName]
                if cfg then
                    cfg.roleFilter = cfg.roleFilter or {}
                    cfg.roleFilter["melee"] = val or nil
                end
            end,
        },

        roleCaster = {
            type  = "toggle",
            name  = "Caster",
            order = 13,
            get   = function()
                local cfg = Cooldowns.db.profile.groups[groupName]
                return cfg and cfg.roleFilter and cfg.roleFilter["caster"] or false
            end,
            set   = function(_, val)
                local cfg = Cooldowns.db.profile.groups[groupName]
                if cfg then
                    cfg.roleFilter = cfg.roleFilter or {}
                    cfg.roleFilter["caster"] = val or nil
                end
            end,
        },

        -- ---- Tracked Spells ----
        spellsHeader = {
            type  = "header",
            name  = "Tracked Spells",
            order = 20,
        },

        enableAll = {
            type  = "execute",
            name  = "Enable all",
            order = 21,
            func  = function()
                local cfg = Cooldowns.db.profile.groups[groupName]
                if cfg then
                    cfg.enabledSpells = Cooldowns:AllSpellsEnabled()
                end
            end,
        },

        disableAll = {
            type  = "execute",
            name  = "Disable all",
            order = 22,
            func  = function()
                local cfg = Cooldowns.db.profile.groups[groupName]
                if cfg then cfg.enabledSpells = {} end
            end,
        },

        spells = {
            type   = "group",
            name   = "Spells",
            inline = true,
            order  = 30,
            args   = BuildSpellArgs(groupName),
        },

        -- ---- Role Based Spell Filter ----
        roleSpellFilterHeader = {
            type  = "header",
            name  = "Role Based Spell Filter",
            order = 40,
        },

        roleSpellFilterDesc = {
            type  = "description",
            name  = "Restrict individual spells by role. Select a spell from the "
                 .. "dropdown then check which roles should see it.\n"
                 .. "Leave all roles unchecked to show that spell for every role.",
            order = 41,
        },

        roleSpellSelect = {
            type    = "select",
            name    = "Spell",
            desc    = "Select a spell to configure its role restriction.",
            order   = 42,
            -- values: a function so spell names are resolved at dialog-open time.
            values  = function()
                local vals = {}
                for _, className in ipairs(classOrder) do
                    local classData = spellData[className]
                    if classData then
                        local displayClass = classDisplayNames[className] or className
                        for spellID in pairs(classData) do
                            vals[tostring(spellID)] = displayClass .. ": "
                                .. Cooldowns:GetSpellDisplayName(spellID)
                        end
                    end
                end
                return vals
            end,
            -- sorting: maintains the canonical class order and index order within
            -- each class so the dropdown mirrors the Tracked Spells layout.
            sorting = function()
                local sort = {}
                for _, className in ipairs(classOrder) do
                    local classData = spellData[className]
                    if classData then
                        local spellList = {}
                        for spellID, data in pairs(classData) do
                            tinsert(spellList, { id = spellID, data = data })
                        end
                        table.sort(spellList, function(a, b)
                            return (a.data.index or 0) < (b.data.index or 0)
                        end)
                        for _, entry in ipairs(spellList) do
                            tinsert(sort, tostring(entry.id))
                        end
                    end
                end
                return sort
            end,
            get = function()
                return selectedSpellForRoleFilter[groupName]
            end,
            set = function(_, val)
                selectedSpellForRoleFilter[groupName] = val
            end,
        },

        -- Status line shown below the dropdown once a spell is selected.
        roleSpellCurrentInfo = {
            type   = "description",
            order  = 43,
            hidden = function() return not selectedSpellForRoleFilter[groupName] end,
            name   = function()
                local sel = selectedSpellForRoleFilter[groupName]
                if not sel then return "" end
                local spellID = tonumber(sel)
                if not spellID then return "" end
                local cfg = Cooldowns.db.profile.groups[groupName]
                local srf = cfg and cfg.spellRoleFilter
                    and cfg.spellRoleFilter[spellID]
                if not srf then
                    return "|cffffd700"
                        .. Cooldowns:GetSpellDisplayName(spellID)
                        .. "|r: shown for all roles."
                end
                local roles = {}
                for _, rk in ipairs(ROLE_KEYS) do
                    if srf[rk] then
                        tinsert(roles, ROLE_LABELS[rk])
                    end
                end
                if #roles == 0 then
                    return "|cffffd700"
                        .. Cooldowns:GetSpellDisplayName(spellID)
                        .. "|r: shown for all roles."
                end
                return "|cffffd700"
                    .. Cooldowns:GetSpellDisplayName(spellID)
                    .. "|r: shown for " .. table.concat(roles, ", ") .. " only."
            end,
        },
    }

    -- Role toggles for the selected spell — generated via loop to avoid
    -- repeating the get/set logic four times.
    for i, roleKey in ipairs(ROLE_KEYS) do
        local rk = roleKey  -- new local per iteration; explicit capture for clarity
        args["roleSpell_" .. roleKey] = {
            type   = "toggle",
            name   = ROLE_LABELS[roleKey],
            order  = 43 + i,
            hidden = function() return not selectedSpellForRoleFilter[groupName] end,
            get    = function() return GetSelectedSpellRole(groupName, rk) end,
            set    = function(_, val) SetSelectedSpellRole(groupName, rk, val) end,
        }
    end

    -- ---- Target Display ----
    args.targetDisplayHeader = {
        type  = "header",
        name  = "Target Display",
        order = 50,
    }

    args.targetInlineOffsetX = {
        type   = "range",
        name   = "Inline X Offset",
        desc   = "Adjust the horizontal position of the inline target text.",
        order  = 52.5,
        min    = -200,
        max    = 200,
        step   = 1,
        hidden = function()
            local cfg = Cooldowns.db.profile.groups[groupName]
            return not (cfg and cfg.targetDisplay == "inline")
        end,
        get    = function()
            local cfg = Cooldowns.db.profile.groups[groupName]
            return (cfg and cfg.targetInlineOffsetX) or 0
        end,
        set    = function(_, val)
            local cfg = Cooldowns.db.profile.groups[groupName]
            if cfg then cfg.targetInlineOffsetX = val end
        end,
    }

    args.targetDisplayDesc = {
        type  = "description",
        name  = "Show the name of the player a spell was cast on.\n"
             .. "Inline: appended to the spell name on the bar, "
             ..   "coloured with the target's class colour.\n"
             .. "Float: a separate styled badge whose appearance can be "
             ..   "customised below.",
        order = 51,
    }

    args.targetDisplay = {
        type   = "select",
        name   = "Mode",
        desc   = "Choose how (or whether) the cast target is shown.",
        order  = 52,
        values = { none = "None", inline = "Inline", float = "Float" },
        get    = function()
            local cfg = Cooldowns.db.profile.groups[groupName]
            return (cfg and cfg.targetDisplay) or "none"
        end,
        set    = function(_, val)
            local cfg = Cooldowns.db.profile.groups[groupName]
            if cfg then cfg.targetDisplay = val end
        end,
    }

    -- Float sub-settings — only visible when mode == "float".
    local function hiddenUnlessFloat()
        local cfg = Cooldowns.db.profile.groups[groupName]
        return not (cfg and cfg.targetDisplay == "float")
    end

    args.targetFloatHeader = {
        type   = "header",
        name   = "Float Appearance",
        order  = 53,
        hidden = hiddenUnlessFloat,
    }

    args.targetFontSize = {
        type   = "range",
        name   = "Text size",
        desc   = "Font size of the target name in the floating badge.",
        order  = 54,
        min    = 6,
        max    = 20,
        step   = 1,
        hidden = hiddenUnlessFloat,
        get    = function()
            local cfg = Cooldowns.db.profile.groups[groupName]
            return (cfg and cfg.targetFontSize) or 11
        end,
        set    = function(_, val)
            local cfg = Cooldowns.db.profile.groups[groupName]
            if cfg then cfg.targetFontSize = val end
        end,
    }

    args.targetTextColorByClass = {
        type   = "toggle",
        name   = "Color text by target's class",
        desc   = "Use the target player's class colour for the badge text "
              .. "instead of the custom text colour below.",
        order  = 54.5,
        hidden = hiddenUnlessFloat,
        get    = function()
            local cfg = Cooldowns.db.profile.groups[groupName]
            return cfg and cfg.targetTextColorByClass or false
        end,
        set    = function(_, val)
            local cfg = Cooldowns.db.profile.groups[groupName]
            if cfg then cfg.targetTextColorByClass = val end
        end,
    }

    args.targetTextColor = {
        type        = "color",
        name        = "Text color",
        desc        = "Colour of the target name text (ignored when 'Color text by target's class' is enabled).",
        order       = 55,
        hasAlpha    = true,
        hidden      = hiddenUnlessFloat,
        get         = function()
            local cfg = Cooldowns.db.profile.groups[groupName]
            return (cfg and cfg.targetTextR) or 1,
                   (cfg and cfg.targetTextG) or 1,
                   (cfg and cfg.targetTextB) or 1,
                   (cfg and cfg.targetTextA) or 1
        end,
        set         = function(_, r, g, b, a)
            local cfg = Cooldowns.db.profile.groups[groupName]
            if cfg then
                cfg.targetTextR = r
                cfg.targetTextG = g
                cfg.targetTextB = b
                cfg.targetTextA = a
            end
        end,
    }

    args.targetBgColor = {
        type        = "color",
        name        = "Background color",
        desc        = "Background fill colour of the floating badge.",
        order       = 56,
        hasAlpha    = true,
        hidden      = hiddenUnlessFloat,
        get         = function()
            local cfg = Cooldowns.db.profile.groups[groupName]
            return (cfg and cfg.targetBgR) or 0,
                   (cfg and cfg.targetBgG) or 0,
                   (cfg and cfg.targetBgB) or 0,
                   (cfg and cfg.targetBgA) or 0.75
        end,
        set         = function(_, r, g, b, a)
            local cfg = Cooldowns.db.profile.groups[groupName]
            if cfg then
                cfg.targetBgR = r
                cfg.targetBgG = g
                cfg.targetBgB = b
                cfg.targetBgA = a
            end
        end,
    }

    args.targetBgColorByClass = {
        type   = "toggle",
        name   = "Color background by target's class",
        desc   = "Use the target player's class colour for the badge background instead of the custom colour.",
        order  = 56.5,
        hidden = hiddenUnlessFloat,
        get    = function()
            local cfg = Cooldowns.db.profile.groups[groupName]
            return cfg and cfg.targetBgColorByClass or false
        end,
        set    = function(_, val)
            local cfg = Cooldowns.db.profile.groups[groupName]
            if cfg then cfg.targetBgColorByClass = val end
        end,
    }

    args.targetFloatOffsetX = {
        type   = "range",
        name   = "Badge X Offset",
        desc   = "Horizontal offset for the floating badge.",
        order  = 59,
        min    = -200,
        max    = 200,
        step   = 1,
        hidden = hiddenUnlessFloat,
        get    = function()
            local cfg = Cooldowns.db.profile.groups[groupName]
            return (cfg and cfg.targetFloatOffsetX) or 0
        end,
        set    = function(_, val)
            local cfg = Cooldowns.db.profile.groups[groupName]
            if cfg then cfg.targetFloatOffsetX = val end
        end,
    }

    args.targetFloatOffsetY = {
        type   = "range",
        name   = "Badge Y Offset",
        desc   = "Vertical offset for the floating badge.",
        order  = 60,
        min    = -100,
        max    = 100,
        step   = 1,
        hidden = hiddenUnlessFloat,
        get    = function()
            local cfg = Cooldowns.db.profile.groups[groupName]
            return (cfg and cfg.targetFloatOffsetY) or 0
        end,
        set    = function(_, val)
            local cfg = Cooldowns.db.profile.groups[groupName]
            if cfg then cfg.targetFloatOffsetY = val end
        end,
    }

    args.targetBgWidth = {
        type   = "range",
        name   = "Badge width",
        desc   = "Width of the floating badge background in pixels.",
        order  = 57,
        min    = 20,
        max    = 200,
        step   = 2,
        hidden = hiddenUnlessFloat,
        get    = function()
            local cfg = Cooldowns.db.profile.groups[groupName]
            return (cfg and cfg.targetBgWidth) or 90
        end,
        set    = function(_, val)
            local cfg = Cooldowns.db.profile.groups[groupName]
            if cfg then cfg.targetBgWidth = val end
        end,
    }

    args.targetBgHeight = {
        type   = "range",
        name   = "Badge height",
        desc   = "Height of the floating badge background in pixels.",
        order  = 58,
        min    = 8,
        max    = 50,
        step   = 1,
        hidden = hiddenUnlessFloat,
        get    = function()
            local cfg = Cooldowns.db.profile.groups[groupName]
            return (cfg and cfg.targetBgHeight) or 16
        end,
        set    = function(_, val)
            local cfg = Cooldowns.db.profile.groups[groupName]
            if cfg then cfg.targetBgHeight = val end
        end,
    }

    -- ---- Chat Message Templates ----
    args.chatMessagesHeader = {
        type  = "header",
        name  = "Chat Messages",
        order = 70,
    }

    args.chatMessagesDesc = {
        type  = "description",
        name  = "Customize the text sent when clicking a cooldown row.\n"
             .. "Available tokens: %playerName, %spellName, %spellLink, %targetName, %timeLeft\n"
             .. "Conditional text:\n"
             .. "  %condCD(text) — shows only when the spell is on cooldown.\n"
             .. "  %condTarget(text) — shows only when the cast had a specific target.",
        order = 71,
    }

    args.shiftClickTemplate = {
        type  = "input",
        name  = "Shift-Click Template",
        desc  = "Sent to Raid/Party/Say.",
        order = 72,
        width = "full",
        get   = function()
            local cfg = Cooldowns.db.profile.groups[groupName]
            return cfg and cfg.shiftClickTemplate or "%playerName - %spellLink - %condCD(On Cooldown: )%timeLeft %condTarget(- Last Target: %targetName)"
        end,
        set   = function(_, val)
            local cfg = Cooldowns.db.profile.groups[groupName]
            if cfg then cfg.shiftClickTemplate = val end
        end,
    }

    args.altClickTemplate = {
        type  = "input",
        name  = "Alt-Click Template",
        desc  = "Whispered to the player (only works if the spell is Ready).",
        order = 73,
        width = "full",
        get   = function()
            local cfg = Cooldowns.db.profile.groups[groupName]
            return cfg and cfg.altClickTemplate or "Please use %spellName on me"
        end,
        set   = function(_, val)
            local cfg = Cooldowns.db.profile.groups[groupName]
            if cfg then cfg.altClickTemplate = val end
        end,
    }

    return args
end

-- ============================================================
-- Root options table (built dynamically)
-- ============================================================

local newGroupName = ""   -- staging name for the "New group" input

local function BuildOptions()
    local args = {

        -- ---- Top-level controls ----
        newGroupName = {
            type    = "input",
            name    = "New group name",
            desc    = "Enter a name then click 'Add group'.",
            order   = 1,
            get     = function() return newGroupName end,
            set     = function(_, val) newGroupName = val end,
        },

        addGroup = {
            type  = "execute",
            name  = "Add group",
            order = 2,
            func  = function()
                local name = newGroupName:match("^%s*(.-)%s*$")
                if name == "" then
                    Cooldowns:Print("Please enter a group name first.")
                    return
                end
                if Cooldowns:CreateGroup(name) then
                    newGroupName = ""
                    NotifyChanged()
                else
                    Cooldowns:Print("A group named '" .. name .. "' already exists.")
                end
            end,
        },

        editModeToggle = {
            type  = "execute",
            name  = "Toggle edit mode",
            desc  = "Enter / exit frame-positioning mode. Drag the highlighted\n"
                 .. "overlays to reposition your groups.",
            order = 3,
            func  = function()
                ns.ToggleEditMode()
            end,
        },

        groupsSep = {
            type  = "header",
            name  = "Groups",
            order = 10,
        },
    }

    -- One sub-group entry per configured group.
    local order = 11
    for _, groupName in ipairs(Cooldowns.db.profile.groupOrder) do
        if Cooldowns.db.profile.groups[groupName] then
            args["group_" .. groupName] = {
                type  = "group",
                name  = groupName,
                order = order,
                args  = BuildGroupArgs(groupName),
            }
            order = order + 1
        end
    end

    return {
        type  = "group",
        name  = "Cooldowns",
        args  = args,
    }
end

-- ============================================================
-- Registration & slash command
-- ============================================================

-- We register the options lazily (on first open) so that the DB is ready.
local optionsRegistered = false

local function EnsureRegistered()
    if optionsRegistered then return end
    optionsRegistered = true

    -- Register with AceConfig using a function so the tree is rebuilt each
    -- time the dialog calls back to retrieve options.
    AceConfig:RegisterOptionsTable(addonName, BuildOptions)
    AceConfigDialog:AddToBlizOptions(addonName, "Cooldowns")
end

--- Opens the floating AceConfigDialog for this addon.
function ns.OpenConfigDialog()
    EnsureRegistered()
    -- Rebuild the tree each time to reflect any group changes.
    AceConfig:RegisterOptionsTable(addonName, BuildOptions)
    AceConfigDialog:Open(addonName)
end
