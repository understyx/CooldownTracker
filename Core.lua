-- Core.lua
-- Main addon backbone: event handling, roster management, cooldown state.
--
-- Public API (via ns.Cooldowns):
--   Cooldowns:GetActiveCooldowns(enabledSpells[, roleFilter[, spellRoleFilter]])
--       → sorted list of cooldown entries, grouped by spellID
--   Cooldowns:GetSpellDisplayName(spellID)  → localized spell name (cached)
--   ns.OpenConfig()                         → opens the AceConfigDialog
--
-- Talent handling strategy:
--   Common spells (tReq = nil/false) are seeded immediately when a player
--   joins so bars appear right away.
--   Talent-required spells (tReq = true) are seeded only after
--   LibGroupTalents-1.0 fires LibGroupTalents_Update, confirming the player
--   has been inspected and the specific talent has points allocated.
--   Duration reductions (minus = true) are applied at cast-time via
--   ComputeCooldownDuration using live LGT talent-point data.

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
    global = {
        -- Runtime cooldown state persisted so /reload does not lose active CDs.
        -- Entries: cdStateDB[unitName][spellID] = { dur, expireAt, destName }
        -- expireAt is a Unix timestamp (time()) so it survives GetTime() resetting.
        cdStateDB = {},
    },
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

-- roster[unitName] = { class = "CLASSNAME", unitID = "raidN", guid = "0x..." }
local roster = {}

-- cdState[unitName][spellID] = { dur, expTime, destName, pendingDestName }
-- This table is pre-populated from db.global.cdStateDB on the first RefreshRoster
-- after a /reload so active cooldowns survive the session restart.
local cdState = {}

-- Guards the one-time restore so we only overlay saved state on the first
-- RefreshRoster call after an initialisation, not on every subsequent refresh.
local cdStateRestored = false

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

--- Returns the talent-adjusted cooldown duration for a spell.
--- Applies 'minus' talent point reductions when LibGroupTalents data is available.
--- Falls back to the base duration if LGT is unavailable or talent data is missing.
local function ComputeCooldownDuration(unitID, classData, spellID)
    local data = classData and classData[spellID]
    if not data then return 0 end
    local dur = data.dur
    if data.minus and LGT and unitID and data.minusTabIndex then
        for i = 1, #data.minusTabIndex do
            local _, _, _, _, pts = LGT:GetTalentInfo(
                unitID, data.minusTabIndex[i], data.minusTalentIndex[i])
            if pts and pts > 0 then
                dur = dur - pts * data.minusPerPoint[i]
            end
        end
    end
    return math.max(1, dur)
end

local function RecordCast(srcName, spellID, destName)
    local entry = roster[srcName]
    if not entry then return end
    local data = spellData[entry.class] and spellData[entry.class][spellID]
    if not data then return end
    local state = GetOrCreateUnitState(srcName)
    local dur   = ComputeCooldownDuration(entry.unitID, spellData[entry.class], spellID)
    state[spellID]          = state[spellID] or {}
    state[spellID].dur      = dur
    state[spellID].expTime  = GetTime() + dur
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

--- Seeds cooldown entries for a single unit.
---
--- Strategy:
---   • Common spells (tReq = nil/false): seeded immediately; the bar shows
---     "Ready" from the start regardless of talent data.
---   • Talent-required spells (tReq = true): only seeded once LibGroupTalents
---     has received and confirmed the unit's talent data.  Until then the bar
---     is simply absent.  When LGT fires LibGroupTalents_Update the
---     ReseedAfterTalentChange path calls this function again and seeds any
---     talents that are now confirmed.
---
--- Existing entries (e.g. an active cooldown) are never overwritten.
local function SeedUnitCooldowns(unitName, className, unitID)
    local classData = spellData[className]
    if not classData then return end
    local state = GetOrCreateUnitState(unitName)

    for spellID, data in pairs(classData) do
        if spellID ~= excludedShaman then
            if not data.tReq then
                -- Common spell — always seed if not already present.
                if not state[spellID] then
                    state[spellID] = { dur = data.dur, expTime = 0 }
                end
            elseif unitID and LGT then
                -- Talent-required spell — only seed once LGT confirms the data.
                -- GetUnitTalents returns nil when talents haven't arrived yet.
                -- For the local "player" unit the Blizzard API is always available,
                -- so we skip the nil-check and go straight to GetTalentInfo.
                -- unitID is guaranteed non-nil by the outer `elseif unitID` guard.
                local talentsKnown = UnitIsUnit(unitID, "player")
                    or LGT:GetUnitTalents(unitID) ~= nil

                if talentsKnown then
                    local _, _, _, _, pts = LGT:GetTalentInfo(
                        unitID, data.tabIndex, data.talentIndex)
                    if (pts or 0) > 0 and not state[spellID] then
                        state[spellID] = { dur = data.dur, expTime = 0 }
                    end
                end
                -- If talentsKnown is false we do nothing; the bar will appear
                -- once LibGroupTalents_Update fires for this unit.
            end
        end
    end
end

--- Called when LibGroupTalents confirms (or changes) a unit's talent data.
--- Wipes all talent-required spell entries for the unit then re-seeds them
--- using the now-known talent state.  Non-talent spells are untouched.
local function ReseedAfterTalentChange(unitName, className, unitID)
    local classData = spellData[className]
    if not classData then return end
    local state = cdState[unitName]
    if not state then return end

    for spellID, data in pairs(classData) do
        if data.tReq then
            state[spellID] = nil   -- remove stale entry; re-add below if still valid
        end
    end

    SeedUnitCooldowns(unitName, className, unitID)
end

local function AddUnit(unitID)
    local _, className = UnitClass(unitID)
    local unitName     = GetUnitName(unitID)
    if not className or not unitName or unitName == UNKNOWNOBJECT then return end
    roster[unitName] = { class = className, unitID = unitID, guid = UnitGUID(unitID) }
    SeedUnitCooldowns(unitName, className, unitID)
end

local function RemoveUnit(unitName)
    roster[unitName] = nil
    -- Wipe cooldown state immediately so departed players' bars disappear.
    cdState[unitName] = nil
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
                -- Keep unitID / guid up-to-date (can change on zone-in) and
                -- seed any spells not yet present (common spells always; talent
                -- spells if LGT already has this unit's talent data).
                roster[unitName].unitID = unitID
                roster[unitName].guid  = UnitGUID(unitID)
                SeedUnitCooldowns(unitName, className, unitID)
            end
        end
    end
    -- Remove players who left the group.
    for unitName in pairs(roster) do
        if not current[unitName] then
            RemoveUnit(unitName)
        end
    end
    -- On the first refresh after a /reload, overlay saved expiry times onto the
    -- freshly-seeded cdState entries (only for units now confirmed in the roster).
    if not cdStateRestored then
        cdStateRestored = true
        local db = Cooldowns.db.global.cdStateDB
        if db then
            local now     = GetTime()
            local wallNow = time()
            for unitName in pairs(roster) do
                local saved = db[unitName]
                if saved then
                    local state = cdState[unitName]
                    if state then
                        for spellID, entry in pairs(saved) do
                            if state[spellID] and entry.expireAt then
                                local remaining = entry.expireAt - wallNow
                                if remaining > 0 then
                                    -- Cooldown still active — restore expiry and metadata.
                                    state[spellID].dur      = entry.dur
                                    state[spellID].destName = entry.destName
                                    state[spellID].expTime  = now + remaining
                                end
                                -- remaining <= 0: cooldown expired during the reload gap;
                                -- leave the seeded ready state (expTime = 0) as-is.
                            end
                        end
                    end
                end
            end
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

--- Persist the current cdState to SavedVariables so a /reload can restore it.
--- expireAt is stored as a Unix timestamp (time()) to survive GetTime() resetting.
--- Only active (not yet expired) cooldowns are saved; ready spells are re-seeded
--- at expTime = 0 automatically and need no persistence.
function Cooldowns:OnPlayerLogout()
    local now     = GetTime()
    local wallNow = time()
    local saved   = {}
    for unitName, state in pairs(cdState) do
        local unitSaved = {}
        for spellID, info in pairs(state) do
            if info.expTime ~= nil then
                local remaining = info.expTime - now
                if remaining > 0 then
                    unitSaved[spellID] = {
                        dur      = info.dur,
                        expireAt = wallNow + remaining,
                        destName = info.destName,
                    }
                end
            end
        end
        if next(unitSaved) then
            saved[unitName] = unitSaved
        end
    end
    self.db.global.cdStateDB = saved
end

--- LibGroupTalents_Update fires when a unit's talent data is first received
--- (initial inspection) or when it changes (respec / dual-spec swap).
--- We use it to seed talent-required spells that were deliberately skipped
--- until the talent state was confirmed.
function Cooldowns:OnTalentUpdate(event, guid)
    -- Find the roster entry that matches this GUID.
    for unitName, entry in pairs(roster) do
        if entry.guid == guid then
            ReseedAfterTalentChange(unitName, entry.class, entry.unitID)
            return
        end
    end
end

-- ============================================================
-- Public API
-- ============================================================

--- Returns a sorted list of cooldown entries whose spellID appears in
--- `enabledSpells`.  Each entry is a plain table:
---   { srcName, spellID, timeLeft, dur, destName, icon, className }
---
--- Sorted by spellID so the same spell from multiple players is grouped
--- together.  Within each spell group, active cooldowns (timeLeft > 0) come
--- first sorted by time remaining (soonest first); ready spells follow sorted
--- by player name for a stable display order.
---
--- Optional `roleFilter` table: keys are role names ("tank", "healer",
--- "melee", "caster"), values are true to include.  If nil/empty every role
--- is shown.  Roles are resolved via LibGroupTalents-1.0; units whose role
--- cannot be determined are always included (fail-open).
---
--- Optional `spellRoleFilter` table: spellRoleFilter[spellID] = { tank=true,
--- ... }.  When set for a spell, only players whose role appears in the table
--- have that spell shown.  An absent or empty sub-table means no restriction.
function Cooldowns:GetActiveCooldowns(enabledSpells, roleFilter, spellRoleFilter)
    local result = {}
    local now    = GetTime()

    -- Pre-compute whether any unit-level role filter is active.
    local hasRoleFilter = false
    if roleFilter then
        for _, v in pairs(roleFilter) do
            if v then hasRoleFilter = true; break end
        end
    end

    for unitName, state in pairs(cdState) do
        -- Unit-level role filter: skip units whose role is not selected.
        local includeUnit = true
        if hasRoleFilter then
            local rEntry = roster[unitName]
            if rEntry and LGT then
                local role = LGT:GetUnitRole(rEntry.unitID)
                if role and not roleFilter[role] then
                    includeUnit = false
                end
                -- role == nil means LGT hasn't resolved this unit yet; fail-open.
            end
        end

        if includeUnit then
            for spellID, info in pairs(state) do
                if enabledSpells[spellID] and info.expTime then
                    -- Per-spell role filter: if this spell has role restrictions,
                    -- only include the caster when their role matches.
                    local includeSpell = true
                    local srf = spellRoleFilter and spellRoleFilter[spellID]
                    if srf then
                        local hasSpellRestriction = false
                        for _, v in pairs(srf) do
                            if v then hasSpellRestriction = true; break end
                        end
                        if hasSpellRestriction then
                            local rEntry = roster[unitName]
                            if rEntry and LGT then
                                local role = LGT:GetUnitRole(rEntry.unitID)
                                if role and not srf[role] then
                                    includeSpell = false
                                end
                                -- role == nil → fail-open, include.
                            end
                        end
                    end

                    if includeSpell then
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
    end

    -- Sort: primary by class, secondary by spellID, then active rows first,
    -- then by time remaining (soonest first) / player name.
    table.sort(result, function(a, b)
        -- Primary: group by class so all cooldowns of the same class sit together.
        if a.className ~= b.className then return a.className < b.className end
        -- Secondary: within a class, group by spellID.
        if a.spellID ~= b.spellID then return a.spellID < b.spellID end
        -- Same class and spell: active cooldowns before ready ones.
        local aActive = a.timeLeft > 0
        local bActive = b.timeLeft > 0
        if aActive ~= bActive then return aActive end
        -- Both on cooldown: soonest expiry first.
        if aActive then return a.timeLeft < b.timeLeft end
        -- Both ready: stable sort by player name.
        return a.srcName < b.srcName
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
        name              = name,
        showReady         = true,
        iconSize          = 24,
        rowHeight         = 26,
        spellGroupSpacing = 4,
        width             = 260,
        enabledSpells     = self:AllSpellsEnabled(),
        roleFilter        = {},
        spellRoleFilter   = {},
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
            name              = groupName,
            showReady         = true,
            iconSize          = 24,
            rowHeight         = 26,
            spellGroupSpacing = 4,
            width             = 260,
            enabledSpells     = self:AllSpellsEnabled(),
            roleFilter        = {},
            spellRoleFilter   = {},
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
    self:RegisterEvent("PLAYER_LOGOUT",               "OnPlayerLogout")

    -- Subscribe to LibGroupTalents talent-received / respec events so we can
    -- seed talent-required spell bars once each player's talents are confirmed.
    if LGT then
        LGT.RegisterCallback(Cooldowns, "LibGroupTalents_Update", "OnTalentUpdate")
    end

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
