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
-- Build per-group top-level options
-- ============================================================

local function BuildGroupArgs(groupName)
    local gConfig = Cooldowns.db.profile.groups[groupName]
    if not gConfig then return {} end

    return {
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

        width = {
            type  = "range",
            name  = "Frame width",
            desc  = "Width of the group display frame in pixels.",
            order = 4,
            min   = 180,
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
            min   = 16,
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

        deleteGroup = {
            type    = "execute",
            name    = "Delete group",
            desc    = "Permanently remove this group and its display frame.",
            order   = 6,
            confirm = true,
            confirmText = "Delete group '" .. groupName .. "'?",
            func    = function()
                Cooldowns:DeleteGroup(groupName)
                NotifyChanged()
            end,
        },

        -- ---- Role filter ----
        roleHeader = {
            type  = "header",
            name  = "Role Filter",
            order = 7,
        },

        roleDesc = {
            type  = "description",
            name  = "Only show cooldowns for players with the selected roles. "
                 .. "Leave all unchecked to show every role.",
            order = 8,
        },

        roleTank = {
            type  = "toggle",
            name  = "Tank",
            order = 9,
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
            order = 10,
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
            order = 11,
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
            order = 12,
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

        -- ---- Spell selection ----
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
    }
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
