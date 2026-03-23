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
    "AceTimer-3.0",
    "AceComm-3.0",
    "AceSerializer-3.0"
)
ns.Cooldowns = Cooldowns

-- ============================================================
-- Locals
-- ============================================================

local spellData         = ns.spellData
local itemSpellAliases  = ns.itemSpellAliases or {}
local itemTrinketIDs    = ns.itemTrinketIDs   or {}
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
    local classData  = spellData[entry.class]
    local classEntry = classData and classData[spellID]
    local itemEntry  = spellData["ITEMS"] and spellData["ITEMS"][spellID]
    local data = classEntry or itemEntry
    if not data then return end
    local state = GetOrCreateUnitState(srcName)
    local dur
    if classEntry then
        dur = ComputeCooldownDuration(entry.unitID, classData, spellID)
    else
        dur = itemEntry.dur   -- these item cooldowns are fixed and unaffected by talents
    end
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

local CHEST_SLOT = 5

--- Helper to check if the WoW 3.3.5 inspect cache is actually loaded.
--- If the cache is empty/expired, GetInventoryItemID returns nil.
--- By checking a slot almost universally worn (Chest), we prevent false wipes.
local function IsInspectCacheValid(unitID)
    if UnitIsUnit(unitID, "player") then return true end
    return GetInventoryItemID(unitID, CHEST_SLOT) ~= nil
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
---   • Item spells (spellData["ITEMS"]): seeded for every player immediately,
---     since any raid member can equip these items.  Bars start "Ready" and
---     activate the first time the item is used.
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

    -- Seed item spells only for players confirmed to have the trinket equipped.
    -- Bars are NOT pre-seeded here; they are created on demand by either:
    --   • CheckUnitTrinkets (equipped-item scan via inspect / inventory event)
    --   • RecordCast (first observed use — creates the bar on cooldown)
end

--- Seed a single item-spell entry in the ready state for a unit.
--- Called when the player is confirmed to have the trinket equipped.
--- A no-op if the entry already exists (active cooldown must not be overwritten).
local function SeedItemSpellForUnit(unitName, canonSpellID)
    local itemData = spellData["ITEMS"]
    local data = itemData and itemData[canonSpellID]
    if not data then return end
    local state = GetOrCreateUnitState(unitName)
    if not state[canonSpellID] then
        state[canonSpellID] = { dur = data.dur, expTime = 0 }
    end
end

-- Inventory slots for upper and lower trinket respectively.
local TRINKET_SLOT_1 = 13
local TRINKET_SLOT_2 = 14

--- Check a unit's equipped trinket slots and seed item-spell bars for any
--- tracked trinkets found.  Uses the WoW inspect cache for remote players
--- (valid during and immediately after a LibGroupTalents inspect cycle) and
--- the direct player inventory for the local player at all times.
local function CheckUnitTrinkets(unitName, unitID)
    if not IsInspectCacheValid(unitID) then return end 

    local itemData = spellData["ITEMS"]
    if not itemData then return end
    for canonSpellID in pairs(itemData) do
        local trinketIDs = itemTrinketIDs[canonSpellID]
        if trinketIDs then
            local state = cdState[unitName]
            -- Only seed if the bar is not already tracked.
            if not (state and state[canonSpellID]) then
                for _, slot in ipairs({ TRINKET_SLOT_1, TRINKET_SLOT_2 }) do
                    local equipped = GetInventoryItemID(unitID, slot)
                    if equipped then
                        for _, knownID in ipairs(trinketIDs) do
                            if equipped == knownID then
                                SeedItemSpellForUnit(unitName, canonSpellID)
                                break
                            end
                        end
                    end
                end
            end
        end
    end
end

--- Remove item-spell bars for trinkets the unit no longer has equipped.
--- Only removes bars in the "Ready" state (expTime ≤ now); active cooldowns
--- are kept because we know with certainty the player had the item at cast time.
local function PruneItemBarsForUnit(unitName, unitID)
    local state = cdState[unitName]
    if not state then return end
    local itemData = spellData["ITEMS"]
    if not itemData then return end

    -- CRITICAL: Do not delete bars if the cache is just empty
    if not IsInspectCacheValid(unitID) then return end 

    local now = GetTime()
    for canonSpellID in pairs(itemData) do
        local info = state[canonSpellID]
        if info and info.expTime and info.expTime <= now then
            local trinketIDs = itemTrinketIDs[canonSpellID]
            if trinketIDs then
                local stillEquipped = false
                for _, slot in ipairs({ TRINKET_SLOT_1, TRINKET_SLOT_2 }) do
                    local equipped = GetInventoryItemID(unitID, slot)
                    if equipped then
                        for _, knownID in ipairs(trinketIDs) do
                            if equipped == knownID then
                                stillEquipped = true
                                break
                            end
                        end
                    end
                    if stillEquipped then break end
                end
                if not stillEquipped then
                    state[canonSpellID] = nil
                end
            end
        end
    end
end

--- Periodically prune and re-seed tracked trinket bars for every player in the
--- roster.  Handles the case where a remote player swapped trinkets between
--- LibGroupTalents inspect cycles.
local function RecheckAllTrinkets()
    for unitName, entry in pairs(roster) do
        PruneItemBarsForUnit(unitName, entry.unitID)
        CheckUnitTrinkets(unitName, entry.unitID)
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
    -- For the local player the inventory API is always available; check trinket
    -- slots immediately.  Remote players are handled when LGT fires after inspect.
    if UnitIsUnit(unitID, "player") then
        CheckUnitTrinkets(unitName, unitID)
    end
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
                            if entry.expireAt then
                                local remaining = entry.expireAt - wallNow
                                if remaining > 0 then
                                    -- Create the state entry if absent (e.g. item bars
                                    -- that are no longer pre-seeded but were active
                                    -- before the /reload).
                                    if not state[spellID] then
                                        state[spellID] = { dur = entry.dur, expTime = 0 }
                                    end
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
    Cooldowns:BroadcastTrinkets()
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

    -- Translate heroic item spell IDs to their canonical (normal) counterpart
    -- before looking up spell data so both versions share one cooldown bar.
    local canonSpellID = itemSpellAliases[spellID] or spellID

    local data = classData[canonSpellID]
             or (spellData["ITEMS"] and spellData["ITEMS"][canonSpellID])
    if not data then return end

    if subEvent == "SPELL_CAST_SUCCESS" then
        -- Tricks of the Trade (57934) and Misdirection (34477): the
        -- cooldown starts when the aura on the target expires, not when the
        -- spell is cast.  Buffer the destination name here.
        if canonSpellID == 57934 or canonSpellID == 34477 then
            local state = GetOrCreateUnitState(srcName)
            state[canonSpellID]                  = state[canonSpellID] or {}
            state[canonSpellID].pendingDestName  = destName
        else
            RecordCast(srcName, canonSpellID, destName)
            self:BroadcastCooldown(canonSpellID, srcName, destName)
        end

    elseif subEvent == "SPELL_AURA_REMOVED"
        and (canonSpellID == 57934 or canonSpellID == 34477) then
        -- Aura fell off — the cooldown starts now.
        local state   = GetOrCreateUnitState(srcName)
        local pending = state[canonSpellID] and state[canonSpellID].pendingDestName
        local target  = pending or destName
        RecordCast(srcName, canonSpellID, target)
        self:BroadcastCooldown(canonSpellID, srcName, target)

    elseif subEvent == "SPELL_RESURRECT"
        or ((subEvent == "SPELL_AURA_APPLIED" or subEvent == "SPELL_AURA_REFRESH")
            and canonSpellID == 47883) then
        -- Soulstone Resurrection (47883): triggered on AURA or RESURRECT.
        RecordCast(srcName, canonSpellID, destName)
        self:BroadcastCooldown(canonSpellID, srcName, destName)

    elseif (subEvent == "SPELL_AURA_APPLIED" or subEvent == "SPELL_AURA_REFRESH")
        and canonSpellID == 66233 then
        -- Ardent Defender (66233) is a passive paladin talent that procs and
        -- prevents death.  It fires as a self-applied aura rather than a cast,
        -- so we detect the cooldown via SPELL_AURA_APPLIED instead of CAST_SUCCESS.
        RecordCast(srcName, canonSpellID, srcName)
        self:BroadcastCooldown(canonSpellID, srcName, nil)
    end
end

-- UNIT_SPELLCAST_SUCCEEDED fires for Rebirth (48477) to avoid relying on
-- CLEU which triggers before the target is actually rezzed.
function Cooldowns:OnUSS(event, unitID, spellName)
    if spellName == locRebirth then
        local unitName = GetUnitName(unitID)
        if unitName and roster[unitName] then
            RecordCast(unitName, 48477, "Unknown")
            self:BroadcastCooldown(48477, unitName, nil)
        end
    end
end

function Cooldowns:OnRosterUpdate()
    self:ScheduleTimer(RefreshRoster, 0.5)
end

--- Fires when the local player's inventory changes (e.g. equipping a trinket).
--- Re-scans trinket slots so newly-equipped items immediately get a bar, and
--- prunes any bars whose trinket was just removed.
function Cooldowns:OnUnitInventoryChanged(event, unitID)
    if not unitID or not UnitIsUnit(unitID, "player") then return end
    local unitName = UnitName("player")
    if unitName and roster[unitName] then
        PruneItemBarsForUnit(unitName, unitID)
        CheckUnitTrinkets(unitName, unitID)
        
        -- Broadcast the change so other players' addons pick it up instantly
        self:BroadcastTrinkets()
    end
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
            -- LGT just finished inspecting this player; the inspect cache is
            -- still valid here, so prune stale trinket bars then re-seed.
            PruneItemBarsForUnit(unitName, entry.unitID)
            CheckUnitTrinkets(unitName, entry.unitID)
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
--- has not yet been determined default to "melee" (DPS) so unscanned players
--- do not bleed into tank- or healer-only groups.
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
        -- Units whose role LGT has not yet resolved default to "melee" (DPS),
        -- which is the sane default: unscanned players don't accidentally appear
        -- in tank-only or healer-only filter groups.
        local includeUnit = true
        if hasRoleFilter then
            local rEntry = roster[unitName]
            if rEntry and LGT then
                local role = LGT:GetUnitRole(rEntry.unitID) or "melee"
                if not roleFilter[role] then
                    includeUnit = false
                end
            end
        end

        if includeUnit then
            for spellID, info in pairs(state) do
                if enabledSpells[spellID] and info.expTime then
                    -- Per-spell role filter: if this spell has role restrictions,
                    -- only include the caster when their role matches.
                    -- Unknown roles again default to "melee" (DPS).
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
                                local role = LGT:GetUnitRole(rEntry.unitID) or "melee"
                                if not srf[role] then
                                    includeSpell = false
                                end
                            end
                        end
                    end

                    if includeSpell then
                        local timeLeft = info.expTime - now
                        -- Issue 1: clear the cast target once the cooldown expires
                        -- so inline/float labels disappear on the "Ready" bar.
                        if timeLeft <= 0 and info.destName then
                            info.destName = nil
                        end
                        if not spellIconCache[spellID] then
                            -- For item trinket spells, prefer the item icon so the
                            -- bar shows the trinket artwork rather than the effect icon.
                            local trinketIDs = itemTrinketIDs[spellID]
                            if trinketIDs then
                                local itemTex = select(10, GetItemInfo(trinketIDs[1]))
                                spellIconCache[spellID] = itemTex
                                    or select(3, GetSpellInfo(spellID))
                            else
                                spellIconCache[spellID] = select(3, GetSpellInfo(spellID))
                            end
                        end
                        local className = roster[unitName] and roster[unitName].class or ""
                        local isItem    = spellData["ITEMS"] and spellData["ITEMS"][spellID] ~= nil
                        -- Item spells are placed in their own group at the bottom by
                        -- pretending their className is "~~ITEMS" (sorts after all real
                        -- class names because "~" > "Z" in ASCII).
                        if isItem then className = "~~ITEMS" end
                        -- Resolve the target's class for colour coding.
                        -- Check roster first (target is usually in the same group),
                        -- then fall back to nil (displays in white).
                        local destClass = nil
                        if info.destName then
                            local destEntry = roster[info.destName]
                            destClass = destEntry and destEntry.class
                        end
                        tinsert(result, {
                            srcName   = unitName,
                            spellID   = spellID,
                            timeLeft  = timeLeft,
                            dur       = info.dur,
                            destName  = info.destName,
                            destClass = destClass,
                            icon      = spellIconCache[spellID],
                            className = className,
                            classColor = roster[unitName] and roster[unitName].class or "",
                            isItem    = isItem,
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

--- Returns a chat-ready name for a spell.
--- For tracked trinkets this is the item link (e.g. [Goblin Turbo-Trike Key]);
--- for all other spells this falls back to the localized spell name.
function Cooldowns:GetSpellChatName(spellID)
    local trinketIDs = itemTrinketIDs[spellID]
    if trinketIDs then
        local link = select(2, GetItemInfo(trinketIDs[1]))
        if link then return link end
    end
    return self:GetSpellDisplayName(spellID)
end

-- ============================================================
-- HomeCheck inter-addon comm sync
-- ============================================================

-- Comm channel prefix used by HomeCheck for addon-to-addon messaging.
local HOMECHECK_PREFIX = "HomeCheck"


function Cooldowns:BroadcastTrinkets()
    local channel
    if GetNumRaidMembers() > 0 then
        channel = "RAID"
    elseif GetNumPartyMembers() > 0 then
        channel = "PARTY"
    else
        return -- solo play
    end
    
    local t1 = GetInventoryItemID("player", 13) or 0
    local t2 = GetInventoryItemID("player", 14) or 0
    
    -- Send a specific "TRINKETS" payload
    local msg = self:Serialize("TRINKETS", UnitName("player"), t1, t2)
    self:SendCommMessage(HOMECHECK_PREFIX, msg, channel)
end

--- Broadcast a detected cooldown to the raid using the HomeCheck protocol.
--- Only fires when in a group; silently does nothing in solo play.
function Cooldowns:BroadcastCooldown(spellID, playerName, target)
    local channel
    if GetNumRaidMembers() > 0 then
        channel = "RAID"
    elseif GetNumPartyMembers() > 0 then
        channel = "PARTY"
    else
        return  -- solo play — nothing to broadcast
    end
    local msg = self:Serialize(spellID, playerName, target or "")
    self:SendCommMessage(HOMECHECK_PREFIX, msg, channel)
end

local function ApplySyncedCooldown(playerName, spellID, CDLeft, target)
    if not spellID or not playerName then return end
    if not roster[playerName] then return end -- Ignore players not in our group

    spellID = tonumber(spellID)
    if not spellID then return end

    -- Resolve aliases (e.g., Heroic vs Normal trinkets)
    spellID = itemSpellAliases[spellID] or spellID

    -- Ensure we actually track this spell for their class (or items)
    local entry = roster[playerName]
    local classData = spellData[entry.class]
    local data = (classData and classData[spellID]) or (spellData["ITEMS"] and spellData["ITEMS"][spellID])
    if not data then return end

    target = (target ~= "" and target) or nil

    if CDLeft == nil or CDLeft == true then
        -- We only received a cast event, treat it as a fresh cast
        RecordCast(playerName, spellID, target)
    else
        CDLeft = tonumber(CDLeft)
        if not CDLeft then return end
        
        local state = GetOrCreateUnitState(playerName)
        state[spellID] = state[spellID] or {}
        
        if CDLeft <= 0 then
            -- The remote addon is explicitly telling us the spell is ready
            state[spellID].dur      = state[spellID].dur or data.dur
            state[spellID].expTime  = 0
            state[spellID].destName = nil
        else
            -- The remote addon is syncing an active cooldown timer
            local computedDur = (classData and classData[spellID]) 
                and ComputeCooldownDuration(entry.unitID, classData, spellID) 
                or data.dur
            
            -- Set the duration to whichever is larger to ensure the progress bar renders correctly
            state[spellID].dur      = math.max(computedDur, CDLeft)
            state[spellID].expTime  = GetTime() + CDLeft
            state[spellID].destName = target or state[spellID].destName
        end
    end
end


local inspectRoster = {}
local inspectIndex  = 1

--- Aggressively but safely asks the server for PUGs' gear data.
--- Limited to 1 player per tick to avoid breaking GearScore/LGT.
local function PoliteInspectTick()
    if InCombatLockdown() then return end

    wipe(inspectRoster)
    for _, entry in pairs(roster) do
        if not UnitIsUnit(entry.unitID, "player") then
            tinsert(inspectRoster, entry.unitID)
        end
    end

    if #inspectRoster == 0 then return end

    inspectIndex = inspectIndex > #inspectRoster and 1 or inspectIndex
    local targetUnit = inspectRoster[inspectIndex]
    inspectIndex = inspectIndex + 1

    -- CheckInteractDistance index 1 = Inspect Range (28 yards)
    if CanInspect(targetUnit) and CheckInteractDistance(targetUnit, 1) then
        NotifyInspect(targetUnit)
    end
end

--- Catches our own NotifyInspects, as well as those from GS/LGT.
function Cooldowns:OnInspectReady(event)
    -- In 3.3.5, this event doesn't pass the unit name. We just sweep the 
    -- roster and update anyone whose cache happens to be valid right now.
    for unitName, entry in pairs(roster) do
        if IsInspectCacheValid(entry.unitID) then
            PruneItemBarsForUnit(unitName, entry.unitID)
            CheckUnitTrinkets(unitName, entry.unitID)
        end
    end
end

--- Receive inter-addon communication from our own addon and others (oRA3, BLT, etc.)
function Cooldowns:OnCommReceived(prefix, message, distribution, sender)
    -- Ignore our own broadcasts
    if sender == UnitName("player") then return end

    local spellID, playerName, CDLeft, target

    if prefix == "HomeCheck" then
        -- Our native addon comms
        local ok, arg1, arg2, arg3, arg4 = self:Deserialize(message)
        if not ok then return end
        
        if arg1 == "TRINKETS" then
            -- Trinket sync payload: "TRINKETS", playerName, item1, item2
            local syncPlayerName, t1, t2 = arg2, arg3, arg4
            if roster[syncPlayerName] then
                local state = GetOrCreateUnitState(syncPlayerName)
                local itemData = spellData["ITEMS"]
                if not itemData then return end
                
                -- Prune active "Ready" bars first
                for canonSpellID, info in pairs(state) do
                    if info.expTime and info.expTime <= GetTime() and itemTrinketIDs[canonSpellID] then
                        state[canonSpellID] = nil
                    end
                end
                
                -- Seed newly broadcasted items
                local equipped = { t1, t2 }
                for canonSpellID in pairs(itemData) do
                    local trinketIDs = itemTrinketIDs[canonSpellID]
                    if trinketIDs then
                        for _, eqID in ipairs(equipped) do
                            for _, knownID in ipairs(trinketIDs) do
                                if eqID == knownID then
                                    SeedItemSpellForUnit(syncPlayerName, canonSpellID)
                                end
                            end
                        end
                    end
                end
            end
            return -- Done handling TRINKETS
        else
            -- Native cooldown cast payload: spellID, playerName, target
            spellID, playerName, target = tonumber(arg1), arg2, arg3
        end

    elseif prefix == "oRA3" then
        local ok, messageType, sid, cdl, tgt = self:Deserialize(message)
        if not ok or type(messageType) ~= "string" or messageType ~= "Cooldown" then return end
        spellID, CDLeft, target = sid, cdl, tgt

    elseif prefix == "BLT" then
        if not string.find(message, ":") then return end
        local messageType, payload = strsplit(":", message)
        if messageType ~= "CD" or not payload or not string.find(payload, ";") then return end
        local pName, _, sid, tgt = strsplit(";", payload)
        playerName, spellID, target = pName, sid, tgt

    elseif prefix == "oRA" or prefix == "CTRA" then
        local sid, cdl = select(3, message:find("CD (%d) (%d+)"))
        spellID, CDLeft = tonumber(sid), tonumber(cdl)
        -- oRA 1/2/3/4 legacy mappings
        if spellID == 1 then spellID = 48477      -- Rebirth
        elseif spellID == 2 then spellID = 21169  -- Reincarnation
        elseif spellID == 3 then spellID = 47883  -- Soulstone Resurrection
        elseif spellID == 4 then spellID = 19752  -- Divine Intervention
        end

    elseif prefix == "RCD2" then
        spellID, CDLeft = select(3, message:find("(%d+) (%d+)"))

    elseif prefix == "FRCD3S" then
        spellID, playerName, CDLeft, target = select(3, message:find("(%d+)(%a+)(%d+)(%a*)"))

    elseif prefix == "FRCD3" then
        -- This specific addon sends multiple cooldowns at once for the sender
        playerName = tostring(sender)
        if not roster[playerName] then return end

        for w in string.gmatch(message, "([^,]*),") do
            local sid, cdl = select(3, w:find("(%d+)-(%d+)"))
            ApplySyncedCooldown(playerName, sid, cdl, nil)
        end
        return -- Loop handled all updates
    end

    -- If we didn't extract a spellID from any known prefix, bail out
    if not spellID then return end

    -- Default fallback: if the payload didn't specify a player, assume it was the sender
    playerName = playerName and tostring(playerName) or sender

    -- Apply the extracted state
    ApplySyncedCooldown(playerName, spellID, CDLeft, target)
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
        showHeader        = true,
        showIcon          = true,
        showSpellName     = true,
        colorBarByClass   = false,
        enabledSpells     = self:AllSpellsEnabled(),
        roleFilter        = {},
        spellRoleFilter   = {},
        -- Target display ("none" / "inline" / "float").
        targetDisplay         = "none",
        -- Inline target label offset.
        targetInlineOffsetX   = 0,
        -- Floating target badge appearance.
        targetFontSize        = 11,
        targetTextColorByClass = false,
        targetTextR           = 1.0,
        targetTextG           = 1.0,
        targetTextB           = 1.0,
        targetTextA           = 1.0,
        targetBgColorByClass  = false,
        targetBgR             = 0.0,
        targetBgG             = 0.0,
        targetBgB             = 0.0,
        targetBgA             = 0.75,
        targetBgWidth         = 90,
        targetBgHeight        = 16,
        targetFloatOffsetX    = 0,
        targetFloatOffsetY    = 0,
        -- Chat message templates.
        -- Supported tokens: %playerName %spellName %targetName %timeLeft
        --   %condCD(text)  — "text" printed only when spell is on cooldown.
        shiftClickTemplate    = "%playerName - %spellLink - %condCD(On Cooldown: )%timeLeft %condTarget(- Last Target: %targetName)",
        altClickTemplate      = "Please use %spellName on me",
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
    self.db = LibStub("AceDB-3.0"):New("CooldownsDB", defaults, "Global")

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
            -- Target display defaults.
            targetDisplay         = "none",
            targetInlineOffsetX   = 0,
            targetFontSize        = 11,
            targetTextColorByClass = false,
            targetTextR           = 1.0,
            targetTextG           = 1.0,
            targetTextB           = 1.0,
            targetTextA           = 1.0,
            targetBgColorByClass  = false,
            targetBgR             = 0.0,
            targetBgG             = 0.0,
            targetBgB             = 0.0,
            targetBgA             = 0.75,
            targetBgWidth         = 90,
            targetBgHeight        = 16,
            targetFloatOffsetX    = 0,
            targetFloatOffsetY    = 0,
            shiftClickTemplate    = "%playerName - %spellLink - %condCD(On Cooldown: )%timeLeft %condTarget(- Last Target: %targetName)",
            altClickTemplate      = "Please use %spellName on me",
        }
        tinsert(self.db.profile.groupOrder, groupName)
    end
end

function Cooldowns:OnEnable()
    locRebirth = GetSpellInfo(48477)
    self:RegisterEvent("INSPECT_TALENT_READY", "OnInspectReady")
    -- Record which faction-specific Shaman spell should be excluded from
    -- the default enabled set (Bloodlust for Alliance, Heroism for Horde).
    -- We do NOT mutate spellData so the table stays consistent for all callers.
    local faction = UnitFactionGroup("player")
    if faction == "Horde" then
        excludedShaman = 32182   -- Heroism: not available to Horde
    else
        excludedShaman = 2825    -- Bloodlust: not available to Alliance
    end
    self:ScheduleRepeatingTimer(PoliteInspectTick, 5) -- Actively ping 1 player every 5 seconds to hunt for PUG trinkets

    -- Migrate enabledSpells: ensure every spell currently in spellData is
    -- present in each group's enabledSpells table.  This silently adds newly
    -- introduced spells (e.g. items added in a later version) to pre-existing
    -- saved profiles without resetting user choices for other spells.
    local allSpells = self:AllSpellsEnabled()
    for _, groupCfg in pairs(self.db.profile.groups) do
        groupCfg.enabledSpells = groupCfg.enabledSpells or {}
        for spellID in pairs(allSpells) do
            if groupCfg.enabledSpells[spellID] == nil then
                groupCfg.enabledSpells[spellID] = true
            end
        end
    end

    -- Register the HomeCheck comm prefix for inter-addon cooldown sync.
    self:RegisterComm(HOMECHECK_PREFIX, "OnCommReceived")
    self:RegisterComm("oRA3",           "OnCommReceived")
    self:RegisterComm("BLT",            "OnCommReceived")
    self:RegisterComm("oRA",            "OnCommReceived")
    self:RegisterComm("CTRA",           "OnCommReceived")
    self:RegisterComm("RCD2",           "OnCommReceived")
    self:RegisterComm("FRCD3S",         "OnCommReceived")
    self:RegisterComm("FRCD3",          "OnCommReceived")

    self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", "OnCLEUF")
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED",    "OnUSS")
    self:RegisterEvent("RAID_ROSTER_UPDATE",          "OnRosterUpdate")
    self:RegisterEvent("PARTY_MEMBERS_CHANGED",       "OnRosterUpdate")
    self:RegisterEvent("PLAYER_ENTERING_WORLD",       "OnPlayerEnteringWorld")
    self:RegisterEvent("PLAYER_LOGOUT",               "OnPlayerLogout")
    -- PLAYER_LEAVING_WORLD fires on /reload (and zone changes), whereas
    -- PLAYER_LOGOUT does NOT fire on /reload.  Saving here ensures the
    -- cdState is persisted before the Lua environment is torn down.
    self:RegisterEvent("PLAYER_LEAVING_WORLD",        "OnPlayerLogout")
    -- Re-check trinket slots whenever the local player's inventory changes
    -- (e.g. they swap in a tracked trinket during a session).
    self:RegisterEvent("UNIT_INVENTORY_CHANGED",      "OnUnitInventoryChanged")

    -- Subscribe to LibGroupTalents talent-received / respec events so we can
    -- seed talent-required spell bars once each player's talents are confirmed.
    if LGT then
        LGT.RegisterCallback(Cooldowns, "LibGroupTalents_Update", "OnTalentUpdate")
    end

    self:RegisterChatCommand("cooldowns", "OpenConfig")
    self:RegisterChatCommand("cd",        "OpenConfig")

    -- Periodically prune/re-seed trinket bars in case remote players swap items
    -- between LibGroupTalents inspect cycles.
    self:ScheduleRepeatingTimer(RecheckAllTrinkets, 30)

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
