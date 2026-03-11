-- Core.lua
-- Main addon backbone: event handling, roster management, cooldown state.
--
-- Public API (via ns.Cooldowns):
--   Cooldowns:GetActiveCooldowns(enabledSpells[, roleFilter])  → sorted list of cooldown entries
--   Cooldowns:GetSpellDisplayName(spellID)                     → localized spell name (cached)
--   ns.OpenConfig()                                            → opens the AceConfigDialog

local addonName, ns = ...

local Cooldowns = LibStub("AceAddon-3.0"):NewAddon(
    addonName,
    "AceConsole-3.0",
    "AceEvent-3.0",
    "AceTimer-3.0"
)
ns.Cooldowns = Cooldowns

-- ============================================================
-- Locals
-- ============================================================

local spellData    = ns.spellData
local GetTime      = GetTime
local GetUnitName  = GetUnitName
local UnitClass    = UnitClass
local UnitInRaid   = UnitInRaid
local UnitInParty  = UnitInParty
local GetNumRaidMembers  = GetNumRaidMembers
local GetNumPartyMembers = GetNumPartyMembers
local GetSpellInfo = GetSpellInfo
local pairs, ipairs, tinsert, tremove = pairs, ipairs, tinsert, tremove

-- LibGroupTalents provides GetUnitRole("raid1") → "tank"/"healer"/"melee"/"caster".
-- The `true` flag makes LibStub return nil instead of erroring if not present.
local LGT = LibStub and LibStub("LibGroupTalents-1.0", true)

-- ============================================================
-- AceDB defaults
-- ============================================================

local defaults = {
    profile = {
        -- Ordered list of group names (controls display order).
        groupOrder = {},
        -- groups[name] = { name, showReady, iconSize, width, enabledSpells={[spellID]=bool} }
        -- showReady defaults to true so bars are visible from the start (ready state).
        groups     = {},
    },
}

-- ============================================================
-- Runtime state (not persisted between sessions)
-- ============================================================

-- roster[unitName] = { class = "CLASSNAME", unitID = "raidN" }
local roster = {}

-- cdState[unitName][spellID] = { dur, expTime, destName, pendingDestName }
local cdState = {}

-- Spell name / icon caches (lazy populated).
local spellNameCache = {}
local spellIconCache = {}

-- Localized Rebirth spell name — needed for UNIT_SPELLCAST_SUCCEEDED.
local locRebirth

-- Spell ID of the Shaman lust ability that is NOT available to the player's
-- faction.  Set in OnEnable once UnitFactionGroup is available.
-- Declared here (before SeedUnitCooldowns) so the function can close over it.
local excludedShaman

-- ============================================================
-- Helpers
-- ============================================================

local function GetOrCreateUnitState(unitName)
    if not cdState[unitName] then
        cdState[unitName] = {}
    end
    return cdState[unitName]
end

local function RecordCast(srcName, spellID, destName)
    local entry = roster[srcName]
    if not entry then return end
    local data = spellData[entry.class] and spellData[entry.class][spellID]
    if not data then return end
    local state = GetOrCreateUnitState(srcName)
    state[spellID]          = state[spellID] or {}
    state[spellID].dur      = data.dur
    state[spellID].expTime  = GetTime() + data.dur
    state[spellID].destName = destName
end

local function IterateGroupMembers()
    local t = {}
    if UnitInRaid("player") then
        for i = 1, GetNumRaidMembers() do
            tinsert(t, "raid" .. i)
        end
    else
        tinsert(t, "player")
        for i = 1, GetNumPartyMembers() do
            tinsert(t, "party" .. i)
        end
    end
    return t
end

local function SeedUnitCooldowns(unitName, className)
    local classData = spellData[className]
    if not classData then return end
    local state = GetOrCreateUnitState(unitName)
    for spellID, data in pairs(classData) do
        -- Skip the opposing faction's lust spell once the faction is known.
        if spellID ~= excludedShaman then
            if not state[spellID] then
                -- Seed a "ready" entry so a bar exists immediately.
                -- expTime = 0 is truthy in Lua; timeLeft = 0 - now (large negative) → "Ready".
                state[spellID] = { dur = data.dur, expTime = 0 }
            end
        end
    end
end

local function AddUnit(unitID)
    local _, className = UnitClass(unitID)
    local unitName     = GetUnitName(unitID)
    if not className or not unitName or unitName == UNKNOWNOBJECT then return end
    roster[unitName] = { class = className, unitID = unitID }
    SeedUnitCooldowns(unitName, className)
end

local function RemoveUnit(unitName)
    roster[unitName] = nil
    cdState[unitName] = nil   -- Remove their cooldowns so they no longer appear.
end

local function RefreshRoster()
    local current = {}
    for _, unitID in ipairs(IterateGroupMembers()) do
        local _, className = UnitClass(unitID)
        local unitName     = GetUnitName(unitID)
        if className and unitName and unitName ~= UNKNOWNOBJECT then
            current[unitName] = true
            if not roster[unitName] then
                AddUnit(unitID)
            else
                -- Keep unitID up-to-date (it can change on zone-in) and
                -- ensure all spells are seeded (handles late excludedShaman init).
                roster[unitName].unitID = unitID
                SeedUnitCooldowns(unitName, className)
            end
        end
    end
    -- Remove players who left the group.
    for unitName in pairs(roster) do
        if not current[unitName] then
            RemoveUnit(unitName)
        end
    end
end

-- ============================================================
-- Event handlers
-- ============================================================

-- COMBAT_LOG_EVENT_UNFILTERED (WoTLK 3.3.5 payload):
--   timestamp, subevent, sourceGUID, sourceName, sourceFlags,
--   destGUID, destName, destFlags, spellID, spellName, spellSchool, ...
function Cooldowns:OnCLEUF(event,
        timestamp, subEvent,
        sourceGUID, srcName, sourceFlags,
        destGUID,   destName, destFlags,
        spellID)

    if not roster[srcName] then return end

    local className = roster[srcName].class
    local classData = spellData[className]
    if not classData then return end

    -- Hunter: Readiness (23989) resets the Misdirection (34477) cooldown.
    if spellID == 23989 then
        local state = GetOrCreateUnitState(srcName)
        if state[34477] then
            state[34477].expTime = GetTime()
        end
    end

    local data = classData[spellID]
    if not data then return end

    if subEvent == "SPELL_CAST_SUCCESS" then
        -- Tricks of the Trade (57934) and Misdirection (34477): the
        -- cooldown starts when the aura on the target expires, not when the
        -- spell is cast.  Buffer the destination name here.
        if spellID == 57934 or spellID == 34477 then
            local state = GetOrCreateUnitState(srcName)
            state[spellID]                  = state[spellID] or {}
            state[spellID].pendingDestName  = destName
        else
            RecordCast(srcName, spellID, destName)
        end

    elseif subEvent == "SPELL_AURA_REMOVED"
        and (spellID == 57934 or spellID == 34477) then
        -- Aura fell off — the cooldown starts now.
        local state   = GetOrCreateUnitState(srcName)
        local pending = state[spellID] and state[spellID].pendingDestName
        RecordCast(srcName, spellID, pending or destName)

    elseif subEvent == "SPELL_RESURRECT"
        or ((subEvent == "SPELL_AURA_APPLIED" or subEvent == "SPELL_AURA_REFRESH")
            and spellID == 47883) then
        -- Soulstone Resurrection (47883): triggered on AURA or RESURRECT.
        RecordCast(srcName, spellID, destName)
    end
end

-- UNIT_SPELLCAST_SUCCEEDED fires for Rebirth (48477) to avoid relying on
-- CLEU which triggers before the target is actually rezzed.
function Cooldowns:OnUSS(event, unitID, spellName)
    if spellName == locRebirth then
        local unitName = GetUnitName(unitID)
        if unitName and roster[unitName] then
            RecordCast(unitName, 48477, "Unknown")
        end
    end
end

function Cooldowns:OnRosterUpdate()
    self:ScheduleTimer(RefreshRoster, 0.5)
end

function Cooldowns:OnPlayerEnteringWorld()
    self:ScheduleTimer(RefreshRoster, 1)
end

-- ============================================================
-- Public API
-- ============================================================

--- Returns a sorted list of cooldown entries whose spellID appears in
--- `enabledSpells`.  Each entry is a plain table:
---   { srcName, spellID, timeLeft, dur, destName, icon, className }
--- Sorted: active cooldowns (timeLeft > 0) first, ascending by time left;
--- then ready spells (timeLeft <= 0) after.
---
--- Optional `roleFilter` table: keys are role names (e.g. "tank", "healer",
--- "melee", "caster"), values are true to include that role.  If the table
--- is nil or empty every role is shown.  Roles are resolved via
--- LibGroupTalents-1.0; units whose role cannot be determined are always
--- included (fail-open).
function Cooldowns:GetActiveCooldowns(enabledSpells, roleFilter)
    local result = {}
    local now    = GetTime()

    -- Pre-compute whether any role filter is active.
    local hasRoleFilter = false
    if roleFilter then
        for _, v in pairs(roleFilter) do
            if v then hasRoleFilter = true; break end
        end
    end

    for unitName, state in pairs(cdState) do
        -- Role filter: skip units whose role is not selected.
        local includeUnit = true
        if hasRoleFilter then
            local rEntry = roster[unitName]
            if rEntry and LGT then
                local role = LGT:GetUnitRole(rEntry.unitID)
                if role and not roleFilter[role] then
                    includeUnit = false
                end
                -- If role is nil (not yet resolved by LGT), fail-open and include.
            end
        end

        if includeUnit then
            for spellID, info in pairs(state) do
                if enabledSpells[spellID] and info.expTime then
                    local timeLeft = info.expTime - now
                    if not spellIconCache[spellID] then
                        spellIconCache[spellID] = select(3, GetSpellInfo(spellID))
                    end
                    local className = roster[unitName] and roster[unitName].class or ""
                    tinsert(result, {
                        srcName   = unitName,
                        spellID   = spellID,
                        timeLeft  = timeLeft,
                        dur       = info.dur,
                        destName  = info.destName,
                        icon      = spellIconCache[spellID],
                        className = className,
                    })
                end
            end
        end
    end

    table.sort(result, function(a, b)
        local aActive = a.timeLeft > 0
        local bActive = b.timeLeft > 0
        if aActive ~= bActive then return aActive end
        -- Both on cooldown: sort ascending by time remaining.
        if aActive then return a.timeLeft < b.timeLeft end
        -- Both ready: stable sort by player name then spellID for consistent ordering.
        if a.srcName ~= b.srcName then return a.srcName < b.srcName end
        return a.spellID < b.spellID
    end)

    return result
end

--- Cached localized spell name.
function Cooldowns:GetSpellDisplayName(spellID)
    if not spellNameCache[spellID] then
        spellNameCache[spellID] = GetSpellInfo(spellID) or ("Spell " .. spellID)
    end
    return spellNameCache[spellID]
end

-- ============================================================
-- Group management helpers (used by Config.lua)
-- ============================================================

--- Build the default enabledSpells table (all spells enabled).
--- The opposing faction's Shaman lust spell is excluded when the faction
--- is known (i.e. after OnEnable has run).
function Cooldowns:AllSpellsEnabled()
    local t = {}
    for _, classData in pairs(spellData) do
        for spellID in pairs(classData) do
            if spellID ~= excludedShaman then
                t[spellID] = true
            end
        end
    end
    return t
end

--- Create a new group with the given name.
--- Returns false if a group with that name already exists.
function Cooldowns:CreateGroup(name)
    if self.db.profile.groups[name] then return false end
    self.db.profile.groups[name] = {
        name         = name,
        showReady    = true,
        iconSize     = 24,
        rowHeight    = 26,
        width        = 260,
        enabledSpells = self:AllSpellsEnabled(),
        roleFilter   = {},
    }
    tinsert(self.db.profile.groupOrder, name)
    if ns.CreateGroupFrame then
        ns.CreateGroupFrame(name)
    end
    return true
end

--- Delete an existing group.
function Cooldowns:DeleteGroup(name)
    if not self.db.profile.groups[name] then return end
    self.db.profile.groups[name] = nil
    for i, v in ipairs(self.db.profile.groupOrder) do
        if v == name then
            tremove(self.db.profile.groupOrder, i)
            break
        end
    end
    if ns.DestroyGroupFrame then
        ns.DestroyGroupFrame(name)
    end
end

--- Rename a group (name is also the key — creates a new entry, copies config).
function Cooldowns:RenameGroup(oldName, newName)
    if oldName == newName then return true end
    if self.db.profile.groups[newName] then return false end
    local cfg = self.db.profile.groups[oldName]
    if not cfg then return false end
    cfg.name                          = newName
    self.db.profile.groups[newName]   = cfg
    self.db.profile.groups[oldName]   = nil
    for i, v in ipairs(self.db.profile.groupOrder) do
        if v == oldName then
            self.db.profile.groupOrder[i] = newName
            break
        end
    end
    if ns.DestroyGroupFrame then ns.DestroyGroupFrame(oldName) end
    if ns.CreateGroupFrame  then ns.CreateGroupFrame(newName)  end
    return true
end

-- ============================================================
-- Lifecycle
-- ============================================================

function Cooldowns:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("CooldownsDB", defaults, true)

    -- Bootstrap: create one default group if the profile is brand new.
    if #self.db.profile.groupOrder == 0 then
        local groupName = "Raid Cooldowns"
        self.db.profile.groups[groupName] = {
            name          = groupName,
            showReady     = true,
            iconSize      = 24,
            rowHeight     = 26,
            width         = 260,
            enabledSpells = self:AllSpellsEnabled(),
            roleFilter    = {},
        }
        tinsert(self.db.profile.groupOrder, groupName)
    end
end

function Cooldowns:OnEnable()
    locRebirth = GetSpellInfo(48477)

    -- Record which faction-specific Shaman spell should be excluded from
    -- the default enabled set (Bloodlust for Alliance, Heroism for Horde).
    -- We do NOT mutate spellData so the table stays consistent for all callers.
    local faction = UnitFactionGroup("player")
    if faction == "Horde" then
        excludedShaman = 32182   -- Heroism: not available to Horde
    else
        excludedShaman = 2825    -- Bloodlust: not available to Alliance
    end

    self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", "OnCLEUF")
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED",    "OnUSS")
    self:RegisterEvent("RAID_ROSTER_UPDATE",          "OnRosterUpdate")
    self:RegisterEvent("PARTY_MEMBERS_CHANGED",       "OnRosterUpdate")
    self:RegisterEvent("PLAYER_ENTERING_WORLD",       "OnPlayerEnteringWorld")

    self:RegisterChatCommand("cooldowns", "OpenConfig")
    self:RegisterChatCommand("cd",        "OpenConfig")

    -- Initialise the group display frames (defined in Groups.lua).
    if ns.InitGroups then ns.InitGroups() end

    -- Seed the roster with whoever is already in the group.
    RefreshRoster()
end

function Cooldowns:OpenConfig()
    if ns.OpenConfigDialog then
        ns.OpenConfigDialog()
    end
end
