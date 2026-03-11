CLEU:SPELL_CAST_SUCCESS:SPELL_AURA_APPLIED:SPELL_AURA_REFRESH:SPELL_AURA_REMOVED:SPELL_RESURRECT, UNIT_SPELLCAST_SUCCEEDED, UNIT_HEALTH, RAID_ROSTER_UPDATE, PARTY_MEMBERS_CHANGED, MERFIN_RAID_CDS,  PLAYER_LOGOUT,  WA_INIT

function(event, ...)
local backend = aura_env

if event == "OPTIONS" then
    if WeakAuras.IsOptionsOpen() and backend.initialized then
        backend.initialized = false
        end

        elseif event == "WA_INIT" then
            backend.initialized = true
            backend.OnInit()

            elseif event == "MERFIN_RAID_CDS" then
                local subEvent, frontend = ...
                if subEvent == "FRONTEND_REGISTER" then
                    backend.RegisterFrontend(frontend)
                    end

                    elseif backend.initialized then
                        if event == "COMBAT_LOG_EVENT_UNFILTERED" then
                            backend.OnCLEUF(...)
                            elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
                                backend.OnUSS(...)
                                elseif event == "UNIT_HEALTH" then
                                    backend.OnUnitHealthChange(...)
                                    elseif event == "RAID_ROSTER_UPDATE"
                                        or ( event == "PARTY_MEMBERS_CHANGED" and not UnitInRaid("player") ) then
                                        backend.OnRosterUpdate()
                                        elseif event == "PLAYER_LOGOUT" then
                                            backend.OnLogout()
                                            end
                                            end

                                            end

                                            local GetUnitName, UnitClass, UnitExists, UnitIsConnected, UnitIsDeadOrGhost = GetUnitName, UnitClass, UnitExists, UnitIsConnected, UnitIsDeadOrGhost
                                            local UnitInRaid, UnitInParty = UnitInRaid, UnitInParty
                                            local GetNumRaidMembers, GetRaidRosterInfo = GetNumRaidMembers, GetRaidRosterInfo
                                            local GetTime, time = GetTime, time
                                            local pairs, substr, stformat = pairs, string.sub, string.format

                                            local spellData = {
                                                ["DEATHKNIGHT"] = {
                                                    -- Anti-Magic Shell
                                                    [48707] = {
                                                        ["dur"] = 45,
                                                        ["index"] = 1,
                                                    },

                                                    -- Anti-Magic Zone
                                                    [51052] = {
                                                        ["tReq"] = true,
                                                        ["tabIndex"] = 3,
                                                        ["talentIndex"] = 22,
                                                        ["dur"] = 120,
                                                        ["index"] = 2,
                                                        ["castableOnOthers"] = true,
                                                    },

                                                    -- Hysteria
                                                    [49016] = {
                                                        ["tReq"] = true,
                                                        ["tabIndex"] = 1,
                                                        ["talentIndex"] = 19,
                                                        ["dur"] = 180,
                                                        ["index"] = 3,
                                                        ["castableOnOthers"] = true,
                                                    },

                                                    -- Icebound Fortitude
                                                    [48792] = {
                                                        ["dur"] = 120,
                                                        ["index"] = 4,
                                                    },

                                                    -- Mark of Blood
                                                    [49005] = {
                                                        ["tReq"] = true,
                                                        ["tabIndex"] = 1,
                                                        ["talentIndex"] = 15,
                                                        ["dur"] = 180,
                                                        ["index"] = 5,
                                                    },

                                                    -- Rune Tap
                                                    [48982] = {
                                                        ["tReq"] = true,
                                                        ["tabIndex"] = 1,
                                                        ["talentIndex"] = 7,
                                                        ["dur"] = 60,
                                                        ["minus"] = true,
                                                        ["minusTabIndex"] = { 1 },
                                                        ["minusTalentIndex"] = { 10 },
                                                        ["minusPerPoint"] = { 10 },
                                                        ["index"] = 6,
                                                    },

                                                    -- Vampiric Blood
                                                    [55233] = {
                                                        ["tReq"] = true,
                                                        ["tabIndex"] = 1,
                                                        ["talentIndex"] = 23,
                                                        ["dur"] = 60,
                                                        ["index"] = 7,
                                                    },

                                                    -- Army of the Dead
                                                    [42650] = {
                                                        ["dur"] = 600,
                                                        ["minus"] = true,
                                                        ["minusTabIndex"] = { 3 },
                                                        ["minusTalentIndex"] = { 13 },
                                                        ["minusPerPoint"] = { 120 },
                                                        ["index"] = 8,
                                                    },

                                                    -- Blood Tap
                                                    [45529] = {
                                                        ["dur"] = 60,
                                                        ["index"] = 9
                                                    }
                                                },

                                                ["DRUID"] = {
                                                    -- Innervate
                                                    [29166] = {
                                                        ["dur"] = 180,
                                                        ["index"] = 1,
                                                        ["castableOnOthers"] = true,
                                                    },

                                                    -- Rebirth
                                                    [48477] = {
                                                        ["dur"] = 600,
                                                        ["index"] = 2,
                                                        ["castableOnOthers"] = true,
                                                    },

                                                    -- Tranquility
                                                    [48447] = {
                                                        ["dur"] = 480,
                                                        ["index"] = 3,
                                                        ["castableOnOthers"] = true,
                                                    },

                                                    -- Barkskin
                                                    [22812] = {
                                                        ["dur"] = 60,
                                                        ["index"] = 4,
                                                    },

                                                    -- Survival Instincts
                                                    [61336] = {
                                                        ["tReq"] = true,
                                                        ["tabIndex"] = 2,
                                                        ["talentIndex"] = 7,
                                                        ["dur"] = 180,
                                                        ["index"] = 5,
                                                    },

                                                    -- Frenzied Regeneration
                                                    [22842] = {
                                                        ["dur"] = 180,
                                                        ["index"] = 6,
                                                    },
                                                },

                                                ["HUNTER"] = {
                                                    -- Deterrence
                                                    [19263] = {
                                                        ["dur"] = 60,
                                                        ["index"] = 1,
                                                    },

                                                    -- Misdirection
                                                    [34477] = {
                                                        ["dur"] = 30,
                                                        ["index"] = 2,
                                                        ["castableOnOthers"] = true,
                                                    },

                                                    -- Master's Call
                                                    [53271] = {
                                                        ["dur"] = 60,
                                                        ["index"] = 3,
                                                        ["castableOnOthers"] = true,
                                                    },

                                                    -- Readiness
                                                    [23989] = {
                                                        ["dur"] = 180,
                                                        ["index"] = 4,
                                                    },
                                                },

                                                ["MAGE"] = {
                                                    -- Ice Block
                                                    [45438] = {
                                                        ["dur"] = 300,
                                                        ["index"] = 1,
                                                    },

                                                    -- Invisibility
                                                    [66] = {
                                                        ["dur"] = 180,
                                                        ["index"] = 2,
                                                    },
                                                },

                                                ["PALADIN"] = {
                                                    -- Aura Mastery
                                                    [31821] = {
                                                        ["tReq"] = true,
                                                        ["tabIndex"] = 1,
                                                        ["talentIndex"] = 6,
                                                        ["dur"] = 120,
                                                        ["index"] = 1,
                                                        ["castableOnOthers"] = true,
                                                    },

                                                    -- Divine Protection
                                                    [498] = {
                                                        ["dur"] = 180,
                                                        ["minus"] = true,
                                                        ["minusTabIndex"] = { 2 },
                                                        ["minusTalentIndex"] = { 14 },
                                                        ["minusPerPoint"] = { 30 },
                                                        ["index"] = 2,
                                                    },

                                                    -- Divine Sacrifice
                                                    [64205] = {
                                                        ["tReq"] = true,
                                                        ["tabIndex"] = 2,
                                                        ["talentIndex"] = 6,
                                                        ["dur"] = 120,
                                                        ["index"] = 3,
                                                        ["castableOnOthers"] = true,
                                                    },

                                                    -- Divine Shield
                                                    [642] = {
                                                        ["dur"] = 300,
                                                        ["minus"] = true,
                                                        ["minusTabIndex"] = { 2 },
                                                        ["minusTalentIndex"] = { 14 },
                                                        ["minusPerPoint"] = { 30 },
                                                        ["index"] = 4,
                                                    },

                                                    -- Lay on Hands
                                                    [48788] = {
                                                        ["dur"] = 900,
                                                        ["minus"] = true,
                                                        ["minusTabIndex"] = { 1 },
                                                        ["minusTalentIndex"] = { 8 },
                                                        ["minusPerPoint"] = { 120 },
                                                        ["index"] = 5,
                                                        ["castableOnOthers"] = true,
                                                    },

                                                    -- Hand of Freedom
                                                    [1044] = {
                                                        ["dur"] = 25,
                                                        ["index"] = 6,
                                                        ["castableOnOthers"] = true,
                                                    },

                                                    -- Hand of Protection
                                                    [10278] = {
                                                        ["dur"] = 300,
                                                        ["minus"] = true,
                                                        ["minusTabIndex"] = { 2 },
                                                        ["minusTalentIndex"] = { 4 },
                                                        ["minusPerPoint"] = { 60 },
                                                        ["index"] = 7,
                                                        ["castableOnOthers"] = true,
                                                    },

                                                    -- Hand of Sacrifice
                                                    [6940] = {
                                                        ["dur"] = 120,
                                                        ["index"] = 8,
                                                        ["castableOnOthers"] = true,
                                                    },

                                                    -- Hand of Salvation
                                                    [1038] = {
                                                        ["dur"] = 120,
                                                        ["index"] = 9,
                                                        ["castableOnOthers"] = true,
                                                    },

                                                    -- Hammer of Justice
                                                    [10308] = {
                                                        ["dur"] = 60,
                                                        ["minus"] = true,
                                                        ["minusTabIndex"] = {2, 2},
                                                        ["minusTalentIndex"] = {10, 25},
                                                        ["minusPerPoint"] = {10, 5},
                                                        ["index"] = 10,
                                                    },

                                                    -- Holy Wrath
                                                    [48817] = {
                                                        ["dur"] = 30,
                                                        ["index"] = 11,
                                                    },

                                                    -- Divine Plea
                                                    [54428] = {
                                                        ["dur"] = 60,
                                                        ["index"] = 12
                                                    },

                                                    -- Argent Defender
                                                    [66233] = {
                                                        ["tReq"] = true,
                                                        ["tabIndex"] = 2,
                                                        ["talentIndex"] = 18,
                                                        ["dur"] = 120,
                                                        ["index"] = 13,
                                                    },
                                                },

                                                ["PRIEST"] = {
                                                    -- Divine Hymn
                                                    [64843] = {
                                                        ["dur"] = 480,
                                                        ["index"] = 1,
                                                        ["castableOnOthers"] = true,
                                                    },

                                                    -- Fear Ward
                                                    [6346] = {
                                                        ["dur"] = 180,
                                                        ["index"] = 2,
                                                        ["castableOnOthers"] = true,
                                                    },

                                                    -- Guardian Spirit
                                                    [47788] = {
                                                        ["tReq"] = true,
                                                        ["tabIndex"] = 2,
                                                        ["talentIndex"] = 27,
                                                        ["dur"] = 180,
                                                        ["index"] = 3,
                                                        ["castableOnOthers"] = true,
                                                    },

                                                    -- Hymn of Hope
                                                    [64901] = {
                                                        ["dur"] = 360,
                                                        ["index"] = 4,
                                                        ["castableOnOthers"] = true,
                                                    },

                                                    -- Pain Suppression
                                                    [33206] = {
                                                        ["tReq"] = true,
                                                        ["tabIndex"] = 1,
                                                        ["talentIndex"] = 25,
                                                        ["dur"] = 180,
                                                        ["minus"] = true,
                                                        ["minusTabIndex"] = { 1 },
                                                        ["minusTalentIndex"] = { 23 },
                                                        ["minusPerPoint"] = { 18 },
                                                        ["index"] = 5,
                                                        ["castableOnOthers"] = true,
                                                    },

                                                    -- Power Infusion
                                                    [10060] = {
                                                        ["tReq"] = true,
                                                        ["tabIndex"] = 1,
                                                        ["talentIndex"] = 19,
                                                        ["dur"] = 120,
                                                        ["minus"] = true,
                                                        ["minusTabIndex"] = { 1 },
                                                        ["minusTalentIndex"] = { 23 },
                                                        ["minusPerPoint"] = { 12 },
                                                        ["index"] = 6,
                                                        ["castableOnOthers"] = true,
                                                    },
                                                },

                                                ["ROGUE"] = {
                                                    -- Cloak of Shadows
                                                    [31224] = {
                                                        ["dur"] = 90,
                                                        ["minus"] = true,
                                                        ["minusTabIndex"] = { 3 },
                                                        ["minusTalentIndex"] = { 7 },
                                                        ["minusPerPoint"] = { 15 },
                                                        ["index"] = 1,
                                                    },

                                                    -- Evasion
                                                    [26669] = {
                                                        ["dur"] = 180,
                                                        ["minus"] = true,
                                                        ["minusTabIndex"] = { 2 },
                                                        ["minusTalentIndex"] = { 7 },
                                                        ["minusPerPoint"] = { 30 },
                                                        ["index"] = 2,
                                                    },

                                                    -- Tricks of the Trade
                                                    [57934] = {
                                                        ["dur"] = 30,
                                                        ["minus"] = true,
                                                        ["minusTabIndex"] = { 3 },
                                                        ["minusTalentIndex"] = { 26 },
                                                        ["minusPerPoint"] = { 5 },
                                                        ["index"] = 3,
                                                        ["castableOnOthers"] = true,
                                                    },

                                                    -- Vanish
                                                    [26889] = {
                                                        ["dur"] = 180,
                                                        ["minus"] = true,
                                                        ["minusTabIndex"] = { 3 },
                                                        ["minusTalentIndex"] = { 7 },
                                                        ["minusPerPoint"] = { 30 },
                                                        ["index"] = 4,
                                                    },
                                                },

                                                ["SHAMAN"] = {
                                                    -- Bloodlust (Horde)
                                                    [2825] = {
                                                        ["dur"] = 300,
                                                        ["index"] = 1,
                                                        ["castableOnOthers"] = true,
                                                    },

                                                    -- Heroism (Alliance)
                                                    [32182] = {
                                                        ["dur"] = 300,
                                                        ["index"] = 2,
                                                        ["castableOnOthers"] = true,
                                                    },

                                                    -- Mana Tide Totem
                                                    [16190] = {
                                                        ["tReq"] = true,
                                                        ["tabIndex"] = 3,
                                                        ["talentIndex"] = 17,
                                                        ["dur"] = 300,
                                                        ["index"] = 3,
                                                        ["castableOnOthers"] = true,
                                                    },

                                                    -- Reincarnation
                                                    [21169] = {
                                                        ["dur"] = 1800,
                                                        ["minus"] = true,
                                                        ["minusTabIndex"] = { 3 },
                                                        ["minusTalentIndex"] = { 3 },
                                                        ["minusPerPoint"] = { 420 },
                                                        ["index"] = 4,
                                                    },

                                                    -- Shamanistic Rage
                                                    [30823] = {
                                                        ["tReq"] = true,
                                                        ["tabIndex"] = 2,
                                                        ["talentIndex"] = 26,
                                                        ["dur"] = 60,
                                                        ["index"] = 5,
                                                    }
                                                },

                                                ["WARLOCK"] = {
                                                    -- Soulstone Resurrection
                                                    [47883] = {
                                                        ["dur"] = 900,
                                                        ["index"] = 1,
                                                        ["castableOnOthers"] = true,
                                                    },

                                                    -- Soulshatter
                                                    [29858] = {
                                                        ["dur"] = 180,
                                                        ["index"] = 2,
                                                    },
                                                },

                                                ["WARRIOR"] = {
                                                    -- Enraged Regeneration
                                                    [55694] = {
                                                        ["dur"] = 180,
                                                        ["index"] = 1,
                                                    },

                                                    -- Last Stand
                                                    [12975] = {
                                                        ["tReq"] = true,
                                                        ["tabIndex"] = 3,
                                                        ["talentIndex"] = 6,
                                                        ["dur"] = 180,
                                                        ["index"] = 2,
                                                    },

                                                    -- Shield Block
                                                    [2565] = {
                                                        ["dur"] = 60,
                                                        ["minus"] = true,
                                                        ["minusTabIndex"] = { 3 },
                                                        ["minusTalentIndex"] = { 8 },
                                                        ["minusPerPoint"] = { 10 },
                                                        ["index"] = 3,
                                                    },

                                                    -- Shield Wall
                                                    [871] = {
                                                        ["dur"] = 300,
                                                        ["minus"] = true,
                                                        ["minusTabIndex"] = { 3 },
                                                        ["minusTalentIndex"] = { 8 },
                                                        ["minusPerPoint"] = { 13 },
                                                        ["index"] = 4,
                                                    },
                                                },
                                            }

                                            local locRebirth = GetSpellInfo(48477)

                                            if ( UnitFactionGroup("player") == "Horde" ) then
                                                spellData["SHAMAN"][32182] = nil
                                                else
                                                    spellData["SHAMAN"][2825] = nil
                                                    end

                                                    local classOrder = {
                                                        ["WARRIOR"] = 1, ["PALADIN"] = 2, ["HUNTER"] = 3, ["ROGUE"] = 4, ["PRIEST"] = 5,
                                                        ["DEATHKNIGHT"] = 6, ["SHAMAN"] = 7, ["MAGE"] = 8, ["WARLOCK"] = 9, ["DRUID"] = 10,
                                                    }

                                                    local roles = { ["caster"] = 1, ["melee"] = 1, ["tank"] = 2, ["healer"] = 3 }

                                                    local function LoadDB()
                                                    WeakAurasSaved["displays"][aura_env.id].db = WeakAurasSaved["displays"][aura_env.id].db or { roster = {} }
                                                    return WeakAurasSaved["displays"][aura_env.id].db
                                                    end

                                                    local backend = aura_env
                                                    local roster, registeredCD, spellIconCache = {}, {}, {}
                                                    local db = LoadDB()
                                                    local oldNumMembers

                                                    local function CheckUnitRole(unitID)
                                                    local roleName = backend.libGT:GetUnitRole(unitID)
                                                    return roleName and roles[roleName] or UNKNOWNOBJECT
                                                    end

                                                    local function CheckUnitConnection(unitID)
                                                    if ( unitID and UnitIsConnected(unitID) ) then return true else return false end
                                                        end

                                                        local function CheckUnitDeadOrGhost(unitID)
                                                        if ( unitID and UnitIsDeadOrGhost(unitID) ) then return true else return false end
                                                            end

                                                            local function CheckUnitSubGroup(unitName)
                                                            local _, instanceType = GetInstanceInfo()
                                                            if ( not UnitInRaid("player") or instanceType == "pvp" ) then return 1 end

                                                                for i = 1, GetNumRaidMembers() do
                                                                    local uName = GetUnitName(stformat("raid%d", i))
                                                                    local _,_, subGroup = GetRaidRosterInfo(i)
                                                                    if ( uName == unitName ) then
                                                                        return subGroup
                                                                        end
                                                                        end
                                                                        end

                                                                        local function RemoveCooldownInfo(uName, spellID)
                                                                        db.roster[uName].cds[spellID] = nil
                                                                        end

                                                                        local function ModifyDuration(uName, spellID, dur)
                                                                        local unitData = db.roster[uName]
                                                                        unitData.cds[spellID] = unitData.cds[spellID] or {}
                                                                        unitData.cds[spellID].dur = dur
                                                                        end

                                                                        local function AddUnitInfo(cName, unitID, uName)
                                                                        db.roster[uName] = db.roster[uName] or {}
                                                                        local unitData = db.roster[uName]
                                                                        unitData = unitData or {}
                                                                        unitData.className = cName
                                                                        unitData.role = CheckUnitRole(unitID)
                                                                        unitData.connected = CheckUnitConnection(unitID)
                                                                        unitData.dead = CheckUnitDeadOrGhost(unitID)
                                                                        unitData.subGroup = CheckUnitSubGroup(uName)
                                                                        unitData.cds = unitData.cds or {}
                                                                        end

                                                                        local function GetTalentRankInfo(unitID, tab, talent)
                                                                        return select(5, backend.libGT:GetTalentInfo(unitID, tab, talent))
                                                                        end

                                                                        local function GetCDMinus(data, unitID)
                                                                        local minus = 0
                                                                        if ( not data.minus ) then return minus end
                                                                            for i = 1, #data.minusTabIndex do
                                                                                local tMinus = GetTalentRankInfo(unitID, data.minusTabIndex[i], data.minusTalentIndex[i]) * data.minusPerPoint[i]
                                                                                minus = minus + tMinus
                                                                                end
                                                                                return minus
                                                                                end

                                                                                local function CheckTalentCD(unitID, uName, spellID)
                                                                                local className = db.roster[uName].className
                                                                                local data = spellData[className][spellID]
                                                                                local update = ""
                                                                                if ( not data.tReq or GetTalentRankInfo(unitID, data.tabIndex, data.talentIndex) ~= 0 ) then
                                                                                    local dur = data.dur - GetCDMinus(data, unitID)
                                                                                    if ( not db.roster[uName].cds[spellID] ) then
                                                                                        ModifyDuration(uName, spellID, dur)
                                                                                        update = "UNIT_COOLDOWN_ADD"
                                                                                        elseif ( db.roster[uName].cds[spellID].dur ~= dur ) then
                                                                                            ModifyDuration(uName, spellID, dur)
                                                                                            update = "UNIT_COOLDOWN_UPDATE"
                                                                                            end
                                                                                            elseif ( data.tReq and db.roster[uName].cds[spellID] ) then
                                                                                                RemoveCooldownInfo(uName, spellID)
                                                                                                update = "UNIT_COOLDOWN_REMOVE"
                                                                                                end

                                                                                                return update
                                                                                                end

                                                                                                local function AddUnitCD(cName, unitID, uName, spellID)
                                                                                                local data = spellData[cName][spellID]
                                                                                                if ( not data.tReq ) then
                                                                                                    ModifyDuration(uName, spellID, data.dur)
                                                                                                    end
                                                                                                    if ( data.tReq or data.minus ) then
                                                                                                        if ( backend.libGT and backend.libGT:GetUnitTalents(unitID) ) then
                                                                                                            CheckTalentCD(unitID, uName, spellID)
                                                                                                            end
                                                                                                            end
                                                                                                            end

                                                                                                            local function AddUnit(cName, uName, unitID)
                                                                                                            roster = roster or {}
                                                                                                            roster[cName] = roster[cName] or {}
                                                                                                            roster[cName][uName] = unitID
                                                                                                            if ( registeredCD[cName] ) then
                                                                                                                AddUnitInfo(cName, unitID, uName)
                                                                                                                for spellID in pairs(registeredCD[cName]) do
                                                                                                                    AddUnitCD(cName, unitID, uName, spellID)
                                                                                                                    end
                                                                                                                    WeakAuras.ScanEvents("MERFIN_RAID_CDS", "UNIT_ADD", uName)
                                                                                                                    end
                                                                                                                    end

                                                                                                                    local function RemoveUnit(cName, uName)

                                                                                                                    if ( roster[cName] ) then
                                                                                                                        roster[cName][uName] = nil
                                                                                                                        end

                                                                                                                        db.roster[uName] = nil
                                                                                                                        WeakAuras.ScanEvents("MERFIN_RAID_CDS", "UNIT_REMOVE", uName)
                                                                                                                        end

                                                                                                                        local function AddNewMembers()
                                                                                                                        for unitID in WA_IterateGroupMembers() do
                                                                                                                            local _, cName = UnitClass(unitID)
                                                                                                                            local uName = GetUnitName(unitID)
                                                                                                                            if ( cName and uName and uName ~= UNKNOWNOBJECT ) then
                                                                                                                                if ( not roster[cName] or not roster[cName][uName] ) then
                                                                                                                                    AddUnit(cName, uName, unitID)
                                                                                                                                    elseif unitID ~= roster[cName][uName] then
                                                                                                                                        roster[cName][uName] = unitID
                                                                                                                                        end
                                                                                                                                        end
                                                                                                                                        end
                                                                                                                                        end

                                                                                                                                        local function RemoveLeftMembers()
                                                                                                                                        for cName, cData in pairs(roster) do
                                                                                                                                            for uName in pairs(cData) do
                                                                                                                                                if ( uName ~= UNKNOWNOBJECT and uName ~= WeakAuras.me
                                                                                                                                                    and not UnitInRaid(uName) and not UnitInParty(uName) ) then
                                                                                                                                                    RemoveUnit(cName, uName)
                                                                                                                                                    end
                                                                                                                                                    end
                                                                                                                                                    end
                                                                                                                                                    end

                                                                                                                                                    local function RefreshConnection()
                                                                                                                                                    for cName, cData in pairs(roster) do
                                                                                                                                                        for uName, unitID in pairs(cData) do
                                                                                                                                                            if ( db.roster[uName] ) then
                                                                                                                                                                local curConnection = CheckUnitConnection(unitID)
                                                                                                                                                                if ( curConnection ~= db.roster[uName].connected ) then
                                                                                                                                                                    db.roster[uName].connected = curConnection
                                                                                                                                                                    WeakAuras.ScanEvents("MERFIN_RAID_CDS", "UNIT_CONDITION_OFFLINE", uName)
                                                                                                                                                                    end
                                                                                                                                                                    end
                                                                                                                                                                    end
                                                                                                                                                                    end
                                                                                                                                                                    end

                                                                                                                                                                    local function RefreshSubGroups()
                                                                                                                                                                    local _, instanceType = GetInstanceInfo()
                                                                                                                                                                    if ( not UnitInRaid("player") or instanceType == "pvp" ) then return 1 end
                                                                                                                                                                        for i = 1, GetNumRaidMembers() do
                                                                                                                                                                            local uName = GetUnitName(stformat("raid%d", i))
                                                                                                                                                                            local _,_, newGroup = GetRaidRosterInfo(i)
                                                                                                                                                                            if ( db.roster[uName] ) then
                                                                                                                                                                                if ( newGroup ~= db.roster[uName].subGroup ) then
                                                                                                                                                                                    db.roster[uName].subGroup = newGroup
                                                                                                                                                                                    WeakAuras.ScanEvents("MERFIN_RAID_CDS", "UNIT_CONDITION_SUBGROUP", uName, newGroup)
                                                                                                                                                                                    end
                                                                                                                                                                                    end
                                                                                                                                                                                    end
                                                                                                                                                                                    end

                                                                                                                                                                                    local function RefreshRoster()
                                                                                                                                                                                    RemoveLeftMembers()
                                                                                                                                                                                    AddNewMembers()
                                                                                                                                                                                    end

                                                                                                                                                                                    function backend.OnRosterUpdate()
                                                                                                                                                                                    RefreshRoster()
                                                                                                                                                                                    RefreshSubGroups()
                                                                                                                                                                                    WeakAuras.timer:ScheduleTimer(RefreshConnection, 0.5)
                                                                                                                                                                                    end

                                                                                                                                                                                    function backend.OnUnitHealthChange(unitID)
                                                                                                                                                                                    local unitName = UnitExists(unitID) and GetUnitName(unitID) or ""
                                                                                                                                                                                    if ( db.roster[unitName] ) then
                                                                                                                                                                                        local curDead = CheckUnitDeadOrGhost(unitID)
                                                                                                                                                                                        if ( curDead ~= db.roster[unitName].dead ) then
                                                                                                                                                                                            db.roster[unitName].dead = curDead
                                                                                                                                                                                            WeakAuras.ScanEvents("MERFIN_RAID_CDS", "UNIT_CONDITION_DEAD", unitName)
                                                                                                                                                                                            end
                                                                                                                                                                                            end
                                                                                                                                                                                            end

                                                                                                                                                                                            local function UnitCooldownChange(srcName, spellID, destName)
                                                                                                                                                                                            local data = db.roster[srcName].cds[spellID]
                                                                                                                                                                                            data.expTime = GetTime() + data.dur
                                                                                                                                                                                            data.expTimeOS = time() + data.dur
                                                                                                                                                                                            data.destName = destName
                                                                                                                                                                                            WeakAuras.ScanEvents("MERFIN_RAID_CDS", "UNIT_COOLDOWN_CHANGED", srcName, spellID)
                                                                                                                                                                                            end

                                                                                                                                                                                            function backend.OnCLEUF(_, subEvent,_, srcName, _,_, destName,_, spellID)
                                                                                                                                                                                            if ( not db.roster[srcName] ) then return end

                                                                                                                                                                                                if ( spellID == 23989 ) then
                                                                                                                                                                                                    if ( db.roster[srcName].cds[34477] ) then
                                                                                                                                                                                                        local data = db.roster[srcName].cds[34477]
                                                                                                                                                                                                        data.expTime = GetTime()
                                                                                                                                                                                                        data.expTimeOS = time()
                                                                                                                                                                                                        WeakAuras.ScanEvents("MERFIN_RAID_CDS", "UNIT_COOLDOWN_CHANGED", srcName, 34477)
                                                                                                                                                                                                        end
                                                                                                                                                                                                        end

                                                                                                                                                                                                        if ( not db.roster[srcName].cds[spellID] ) then return end

                                                                                                                                                                                                            if ( subEvent == "SPELL_CAST_SUCCESS" ) then
                                                                                                                                                                                                                if ( spellID == 57934 or spellID == 34477 ) then
                                                                                                                                                                                                                    db.roster[srcName].cds[spellID].destName = destName
                                                                                                                                                                                                                    else
                                                                                                                                                                                                                        UnitCooldownChange(srcName, spellID, destName)
                                                                                                                                                                                                                        end

                                                                                                                                                                                                                        elseif ( subEvent == "SPELL_AURA_REMOVED" and (spellID == 57934 or spellID == 34477) ) then
                                                                                                                                                                                                                            UnitCooldownChange(srcName, spellID, db.roster[srcName].cds[spellID].destName)

                                                                                                                                                                                                                            elseif ( subEvent == "SPELL_RESURRECT" or
                                                                                                                                                                                                                                ( (subEvent == "SPELL_AURA_APPLIED" or subEvent == "SPELL_AURA_REFRESH") and spellID == 47883 ) ) then
                                                                                                                                                                                                                                UnitCooldownChange(srcName, spellID, destName)
                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                function backend.OnUSS(unitID, spellName)
                                                                                                                                                                                                                                if spellName == locRebirth then
                                                                                                                                                                                                                                    local uName = GetUnitName(unitID)
                                                                                                                                                                                                                                    if db.roster[uName] and db.roster[uName].cds[48477] then
                                                                                                                                                                                                                                        UnitCooldownChange(uName, 48477, "Unknown")
                                                                                                                                                                                                                                        end
                                                                                                                                                                                                                                        end
                                                                                                                                                                                                                                        end

                                                                                                                                                                                                                                        function backend.OnLogout()
                                                                                                                                                                                                                                        for uName, uData in pairs(db.roster) do
                                                                                                                                                                                                                                            if ( not roster[uData.className] or not roster[uData.className][uName] ) then
                                                                                                                                                                                                                                                RemoveUnit(uData.className, uName)
                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                local function RefreshValues()
                                                                                                                                                                                                                                                roster = {}
                                                                                                                                                                                                                                                registeredCD = {}
                                                                                                                                                                                                                                                spellIconCache = {}
                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                local function OnTalentUpdate(unitID)
                                                                                                                                                                                                                                                local uName = GetUnitName(unitID)
                                                                                                                                                                                                                                                if ( db.roster[uName] ) then
                                                                                                                                                                                                                                                    local cName = db.roster[uName].className
                                                                                                                                                                                                                                                    if ( not registeredCD[cName] ) then return end
                                                                                                                                                                                                                                                        for spellID in pairs(registeredCD[cName]) do
                                                                                                                                                                                                                                                            local data = spellData[cName][spellID]
                                                                                                                                                                                                                                                            if ( data.tReq or data.minus ) then
                                                                                                                                                                                                                                                                local update = CheckTalentCD(unitID, uName, spellID)
                                                                                                                                                                                                                                                                if ( update ~= "" ) then
                                                                                                                                                                                                                                                                WeakAuras.ScanEvents("MERFIN_RAID_CDS", update, uName, spellID)
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                local function OnRoleChange(unitID, newRole)
                                                                                                                                                                                                                                                                local unitName = GetUnitName(unitID)
                                                                                                                                                                                                                                                                if ( db.roster[unitName] ) then
                                                                                                                                                                                                                                                                if ( db.roster[unitName].role ~= newRole ) then
                                                                                                                                                                                                                                                                db.roster[unitName].role = CheckUnitRole(unitID)
                                                                                                                                                                                                                                                                WeakAuras.ScanEvents("MERFIN_RAID_CDS", "UNIT_CONDITION_ROLE", unitName)
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                local function LibGroupTalents_Init()
                                                                                                                                                                                                                                                                backend.libGT = LibStub:GetLibrary("LibGroupTalents-1.0", true)

                                                                                                                                                                                                                                                                if ( not backend.libGT ) then
                                                                                                                                                                                                                                                                local loaded, reason = LoadAddOn("LibGroupTalents-1.0")
                                                                                                                                                                                                                                                                backend.libGT = LibStub:GetLibrary("LibGroupTalents-1.0", true)
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                if ( backend.libGT ) then

                                                                                                                                                                                                                                                                function backend:LibGroupTalents_Update(e, guid, unitID, newSpec, n1, n2, n3)
                                                                                                                                                                                                                                                                WeakAuras.timer:ScheduleTimer(OnTalentUpdate, 0.5, unitID)
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                function backend:LibGroupTalents_RoleChange(e, guid, unitID, newRole, oldRole)
                                                                                                                                                                                                                                                                WeakAuras.timer:ScheduleTimer(OnRoleChange, 0.5, unitID, newRole)
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                backend.libGT.RegisterCallback(backend, "LibGroupTalents_Update")
                                                                                                                                                                                                                                                                backend.libGT.RegisterCallback(backend, "LibGroupTalents_RoleChange")

                                                                                                                                                                                                                                                                return true
                                                                                                                                                                                                                                                                else
                                                                                                                                                                                                                                                                DEFAULT_CHAT_FRAME:AddMessage(
                                                                                                                                                                                                                                                                "|cff69ccf0MerfinRaidCooldowns - WA|r couldn't find LibGroupTalents-1.0. Download the lib to display talent required cooldowns.")
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                local function RegisterCD(cName, spellID)
                                                                                                                                                                                                                                                                registeredCD = registeredCD or {}
                                                                                                                                                                                                                                                                registeredCD[cName] = registeredCD[cName] or {}
                                                                                                                                                                                                                                                                registeredCD[cName][spellID] = true

                                                                                                                                                                                                                                                                for className, classData in pairs(roster) do
                                                                                                                                                                                                                                                                if ( className == cName ) then
                                                                                                                                                                                                                                                                for uName in pairs(classData) do
                                                                                                                                                                                                                                                                local unitID = roster[cName][uName]
                                                                                                                                                                                                                                                                AddUnitInfo(cName, unitID, uName)
                                                                                                                                                                                                                                                                AddUnitCD(cName, unitID, uName, spellID)
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                local function IsRegisteredCD(cName, spellID)
                                                                                                                                                                                                                                                                return registeredCD and registeredCD[cName] and registeredCD[cName][spellID]
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                local function SetFrontendConfig(frontend)
                                                                                                                                                                                                                                                                frontend.cds = {}
                                                                                                                                                                                                                                                                for cName, cData in pairs(frontend.config.cds) do
                                                                                                                                                                                                                                                                for spellID, enabled in pairs(cData) do
                                                                                                                                                                                                                                                                local spellID = tonumber(spellID)
                                                                                                                                                                                                                                                                if ( spellData[cName][spellID] and enabled ) then
                                                                                                                                                                                                                                                                frontend.cds[cName] = frontend.cds[cName] or {}
                                                                                                                                                                                                                                                                frontend.cds[cName][spellID] = true
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                frontend.advanced = {}
                                                                                                                                                                                                                                                                for _, data in pairs(frontend.config.advanced.display) do
                                                                                                                                                                                                                                                                local spellID = tonumber(data.spellID)
                                                                                                                                                                                                                                                                frontend.advanced[spellID] = {
                                                                                                                                                                                                                                                                [1] = data["dps"],
                                                                                                                                                                                                                                                                [2] = data["tank"],
                                                                                                                                                                                                                                                                [3] = data["healer"]
                                                                                                                                                                                                                                                                }
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                function backend.RegisterFrontend(frontend)
                                                                                                                                                                                                                                                                SetFrontendConfig(frontend)
                                                                                                                                                                                                                                                                for cName, cData in pairs(frontend.cds) do
                                                                                                                                                                                                                                                                for spellID in pairs(cData) do
                                                                                                                                                                                                                                                                if (  not IsRegisteredCD(cName, spellID) ) then
                                                                                                                                                                                                                                                                RegisterCD(cName, spellID)
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                WeakAuras.ScanEvents("MERFIN_RAID_CDS", "FRONTEND_REG_FINISH", frontend.id, backend)
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                function backend.OnInit()
                                                                                                                                                                                                                                                                if ( LibGroupTalents_Init() ) then
                                                                                                                                                                                                                                                                RefreshValues()
                                                                                                                                                                                                                                                                AddNewMembers()
                                                                                                                                                                                                                                                                WeakAuras.ScanEvents("MERFIN_RAID_CDS", "BACKEND_INITIALIZED")
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                --> Frontend

                                                                                                                                                                                                                                                                local function RemoveFrame(allstates, stateName)
                                                                                                                                                                                                                                                                allstates[stateName] = {
                                                                                                                                                                                                                                                                show = false,
                                                                                                                                                                                                                                                                changed = true
                                                                                                                                                                                                                                                                }
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                local function RemoveUnitFrames(allstates, unitName)
                                                                                                                                                                                                                                                                local updated = false
                                                                                                                                                                                                                                                                for stateName, state in pairs(allstates) do
                                                                                                                                                                                                                                                                if ( state.srcName == unitName ) then
                                                                                                                                                                                                                                                                RemoveFrame(allstates, stateName)
                                                                                                                                                                                                                                                                updated = true
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                return updated
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                local function SetAutohide(frontend)
                                                                                                                                                                                                                                                                if ( not frontend.config.display.showReady ) then
                                                                                                                                                                                                                                                                return true
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                local function SetExpirationTime(cdData)
                                                                                                                                                                                                                                                                if ( cdData.expTimeOS and cdData.expTimeOS > time() ) then
                                                                                                                                                                                                                                                                return cdData.expTime
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                return GetTime()
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                local function IsCooldownEligible(frontend, unitData, spellID)
                                                                                                                                                                                                                                                                local checkReady = frontend.config.display.showReady
                                                                                                                                                                                                                                                                or ( unitData.cds[spellID].expTimeOS and time() < unitData.cds[spellID].expTimeOS )

                                                                                                                                                                                                                                                                local checkRole = not frontend.advanced[spellID]
                                                                                                                                                                                                                                                                or frontend.advanced[spellID][unitData.role]

                                                                                                                                                                                                                                                                return checkReady and checkRole
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                local function IsUnitEligible(allstates, frontend, uName)
                                                                                                                                                                                                                                                                local checkDead = frontend.config.display.showDead
                                                                                                                                                                                                                                                                or not db.roster[uName].dead

                                                                                                                                                                                                                                                                local checkOffline = frontend.config.display.showOffline
                                                                                                                                                                                                                                                                or db.roster[uName].connected

                                                                                                                                                                                                                                                                local checkGroup = frontend.config.display.raidSubGroups
                                                                                                                                                                                                                                                                >=  db.roster[uName].subGroup

                                                                                                                                                                                                                                                                return checkDead and checkOffline and checkGroup
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                local function GetSpellIconCache(spellID)
                                                                                                                                                                                                                                                                if spellID and spellIconCache[spellID] then
                                                                                                                                                                                                                                                                return spellIconCache[spellID]
                                                                                                                                                                                                                                                                else
                                                                                                                                                                                                                                                                local icon = select(3, GetSpellInfo(spellID))
                                                                                                                                                                                                                                                                spellIconCache[spellID] = icon
                                                                                                                                                                                                                                                                return icon
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                local function CreateFrame(allstates, frontend, uName, spellID)
                                                                                                                                                                                                                                                                local unitData = db.roster[uName]
                                                                                                                                                                                                                                                                local cdData = unitData.cds[spellID]
                                                                                                                                                                                                                                                                local stateName = stformat("%s%d", uName, spellID)
                                                                                                                                                                                                                                                                if ( IsCooldownEligible(frontend, unitData, spellID) ) then
                                                                                                                                                                                                                                                                allstates[stateName] = {
                                                                                                                                                                                                                                                                -- Default:
                                                                                                                                                                                                                                                                progressType = "timed",
                                                                                                                                                                                                                                                                duration = cdData.dur,
                                                                                                                                                                                                                                                                expirationTime = SetExpirationTime(cdData),
                                                                                                                                                                                                                                                                icon = GetSpellIconCache(spellID),
                                                                                                                                                                                                                                                                show = true,
                                                                                                                                                                                                                                                                changed = true,
                                                                                                                                                                                                                                                                autoHide = SetAutohide(frontend),

                                                                                                                                                                                                                                                                -- Custom:
                                                                                                                                                                                                                                                                spellID = spellID,
                                                                                                                                                                                                                                                                srcName = uName,
                                                                                                                                                                                                                                                                className = unitData.className,
                                                                                                                                                                                                                                                                role = unitData.role,
                                                                                                                                                                                                                                                                dead = unitData.dead,
                                                                                                                                                                                                                                                                subGroup = unitData.subGroup,
                                                                                                                                                                                                                                                                connected = unitData.connected,
                                                                                                                                                                                                                                                                destName = cdData.destName,
                                                                                                                                                                                                                                                                castableOnOthers = spellData[unitData.className][spellID].castableOnOthers,

                                                                                                                                                                                                                                                                -- Sort:
                                                                                                                                                                                                                                                                classIndex = classOrder[unitData.className],
                                                                                                                                                                                                                                                                spellIndex = spellData[unitData.className][spellID].index,

                                                                                                                                                                                                                                                                -- Links:
                                                                                                                                                                                                                                                                backend = backend
                                                                                                                                                                                                                                                                }
                                                                                                                                                                                                                                                                return true
                                                                                                                                                                                                                                                                elseif allstates[stateName] then
                                                                                                                                                                                                                                                                RemoveFrame(allstates, stateName)
                                                                                                                                                                                                                                                                return true
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                local function CreateUnitFrames(allstates, frontend, uName)
                                                                                                                                                                                                                                                                local updated = false
                                                                                                                                                                                                                                                                local cName = db.roster[uName].className
                                                                                                                                                                                                                                                                for spellID, data in pairs(db.roster[uName].cds) do
                                                                                                                                                                                                                                                                if ( frontend.cds[cName][spellID] ) then
                                                                                                                                                                                                                                                                local stateName = stformat("%s%d", uName, spellID)
                                                                                                                                                                                                                                                                if ( CreateFrame(allstates, frontend, uName, spellID) ) then
                                                                                                                                                                                                                                                                updated = true
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                return updated
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                local function UnitConditionChange(allstates, uName, conditionName)
                                                                                                                                                                                                                                                                local updated = false
                                                                                                                                                                                                                                                                for _, state in pairs(allstates) do
                                                                                                                                                                                                                                                                if ( state.srcName == uName ) then
                                                                                                                                                                                                                                                                state[conditionName] = db.roster[uName][conditionName]
                                                                                                                                                                                                                                                                state.changed = true
                                                                                                                                                                                                                                                                updated = true
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                return updated
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                function backend.OnEvent(allstates, frontend, ...)

                                                                                                                                                                                                                                                                local subEvent, uName = ...
                                                                                                                                                                                                                                                                if ( not subEvent or substr(subEvent, 0, 5) ~= "UNIT_" ) then return end

                                                                                                                                                                                                                                                                if ( subEvent == "UNIT_REMOVE" ) then
                                                                                                                                                                                                                                                                return RemoveUnitFrames(allstates, uName)
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                local className = db.roster[uName].className
                                                                                                                                                                                                                                                                if ( not frontend.cds[className] ) then return end

                                                                                                                                                                                                                                                                if ( subEvent == "UNIT_ADD" ) then
                                                                                                                                                                                                                                                                if ( IsUnitEligible(allstates, frontend, uName) ) then
                                                                                                                                                                                                                                                                return CreateUnitFrames(allstates, frontend, uName)
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                elseif ( substr(subEvent, 0, 14) == "UNIT_CONDITION" ) then
                                                                                                                                                                                                                                                                local update = false
                                                                                                                                                                                                                                                                if ( subEvent == "UNIT_CONDITION_DEAD" ) then
                                                                                                                                                                                                                                                                update = UnitConditionChange(allstates, uName, "dead")
                                                                                                                                                                                                                                                                elseif ( subEvent == "UNIT_CONDITION_OFFLINE" ) then
                                                                                                                                                                                                                                                                update = UnitConditionChange(allstates, uName, "connected")
                                                                                                                                                                                                                                                                elseif ( subEvent == "UNIT_CONDITION_SUBGROUP" ) then
                                                                                                                                                                                                                                                                update = UnitConditionChange(allstates, uName, "subGroup")
                                                                                                                                                                                                                                                                elseif ( subEvent == "UNIT_CONDITION_ROLE" ) then
                                                                                                                                                                                                                                                                update = UnitConditionChange(allstates, uName, "role")
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                if ( IsUnitEligible(allstates, frontend, uName) ) then
                                                                                                                                                                                                                                                                CreateUnitFrames(allstates, frontend, uName)
                                                                                                                                                                                                                                                                else
                                                                                                                                                                                                                                                                RemoveUnitFrames(allstates, uName)
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                return true

                                                                                                                                                                                                                                                                elseif ( substr(subEvent, 0, 13) == "UNIT_COOLDOWN" ) then

                                                                                                                                                                                                                                                                local _,_, spellID = ...
                                                                                                                                                                                                                                                                if ( not frontend.cds[className][spellID] ) then return end
                                                                                                                                                                                                                                                                local stateName = stformat("%s%d", uName, spellID)

                                                                                                                                                                                                                                                                if ( subEvent == "UNIT_COOLDOWN_ADD" ) then
                                                                                                                                                                                                                                                                if ( IsUnitEligible(allstates, frontend, uName) ) then
                                                                                                                                                                                                                                                                return CreateFrame(allstates, frontend, uName, spellID)
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                elseif ( subEvent == "UNIT_COOLDOWN_REMOVE" ) then
                                                                                                                                                                                                                                                                if ( allstates[stateName] ) then
                                                                                                                                                                                                                                                                RemoveFrame(allstates, stateName)
                                                                                                                                                                                                                                                                return true
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                elseif ( subEvent == "UNIT_COOLDOWN_UPDATE" ) then
                                                                                                                                                                                                                                                                if ( allstates[stateName] ) then
                                                                                                                                                                                                                                                                allstates[stateName].duration = db.roster[uName].cds[spellID].dur
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                elseif ( subEvent == "UNIT_COOLDOWN_CHANGED" ) then
                                                                                                                                                                                                                                                                if ( allstates[stateName] ) then
                                                                                                                                                                                                                                                                allstates[stateName].expirationTime = db.roster[uName].cds[spellID].expTime
                                                                                                                                                                                                                                                                allstates[stateName].destName = db.roster[uName].cds[spellID].destName
                                                                                                                                                                                                                                                                allstates[stateName].changed = true
                                                                                                                                                                                                                                                                else
                                                                                                                                                                                                                                                                CreateFrame(allstates, frontend, uName, spellID)
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                return IsUnitEligible(allstates, frontend, uName)
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                function backend.StartUpFrontend(allstates, frontend)

                                                                                                                                                                                                                                                                frontend.OnEvent = backend.OnEvent
                                                                                                                                                                                                                                                                frontend.SortElements = backend.SortElements
                                                                                                                                                                                                                                                                frontend.SetBarClassColor = backend.SetBarClassColor

                                                                                                                                                                                                                                                                local updated = false

                                                                                                                                                                                                                                                                for cName, cData in pairs(roster) do
                                                                                                                                                                                                                                                                if ( frontend.cds[cName] ) then
                                                                                                                                                                                                                                                                for uName in pairs(cData) do
                                                                                                                                                                                                                                                                if ( IsUnitEligible(allstates, frontend, uName) ) then
                                                                                                                                                                                                                                                                if ( CreateUnitFrames(allstates, frontend, uName) ) then
                                                                                                                                                                                                                                                                updated = true
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                return updated
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                function backend.SetBarClassColor(frontend, region)
                                                                                                                                                                                                                                                                local class = aura_env.state.className
                                                                                                                                                                                                                                                                local c = RAID_CLASS_COLORS[class]
                                                                                                                                                                                                                                                                if ( c ) then
                                                                                                                                                                                                                                                                region:Color(c.r, c.g, c.b, c.a)
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                function backend.SortElements(prev, next)
                                                                                                                                                                                                                                                                local stateA = prev.region.state
                                                                                                                                                                                                                                                                local stateB = next.region.state

                                                                                                                                                                                                                                                                if ( stateA.classIndex == stateB.classIndex ) then
                                                                                                                                                                                                                                                                return stateA.spellIndex < stateB.spellIndex
                                                                                                                                                                                                                                                                else
                                                                                                                                                                                                                                                                return stateA.classIndex < stateB.classIndex
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end


MERFIN_RAID_CDS

                                                                                                                                                                                                                                                                function(allstates, event, ...)
                                                                                                                                                                                                                                                                local frontend = aura_env

                                                                                                                                                                                                                                                                if event == "OPTIONS" then
                                                                                                                                                                                                                                                                return frontend.OnInit()

                                                                                                                                                                                                                                                                elseif event == "MERFIN_RAID_CDS" then
                                                                                                                                                                                                                                                                local subEvent, frontendID, backend = ...
                                                                                                                                                                                                                                                                if subEvent == "FRONTEND_REG_FINISH" and frontendID == frontend.id then
                                                                                                                                                                                                                                                                return backend.StartUpFrontend(allstates, frontend)
                                                                                                                                                                                                                                                                elseif subEvent == "BACKEND_INITIALIZED" then
                                                                                                                                                                                                                                                                frontend.OnInit()
                                                                                                                                                                                                                                                                elseif frontend.OnEvent then
                                                                                                                                                                                                                                                                return frontend.OnEvent(allstates, frontend, ...)
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                {
                                                                                                                                                                                                                                                                expirationTime = true,
                                                                                                                                                                                                                                                                duration = true,

                                                                                                                                                                                                                                                                className = {
                                                                                                                                                                                                                                                                display = "Class",
                                                                                                                                                                                                                                                                type = "string"
                                                                                                                                                                                                                                                                },

                                                                                                                                                                                                                                                                connected = {
                                                                                                                                                                                                                                                                display = "Online",
                                                                                                                                                                                                                                                                type = "bool"
                                                                                                                                                                                                                                                                },

                                                                                                                                                                                                                                                                dead = {
                                                                                                                                                                                                                                                                display = "Dead or Ghost",
                                                                                                                                                                                                                                                                type = "bool"
                                                                                                                                                                                                                                                                },

                                                                                                                                                                                                                                                                role = {
                                                                                                                                                                                                                                                                display = "Unit Role",
                                                                                                                                                                                                                                                                type = "select",
                                                                                                                                                                                                                                                                values = {
                                                                                                                                                                                                                                                                [1] = "DPS",
                                                                                                                                                                                                                                                                [2] = "Tank",
                                                                                                                                                                                                                                                                [3] = "Healer"
                                                                                                                                                                                                                                                                }
                                                                                                                                                                                                                                                                },
                                                                                                                                                                                                                                                                }


                                                                                                                                                                                                                                                                local frontend = aura_env

                                                                                                                                                                                                                                                                function frontend.OnInit()
                                                                                                                                                                                                                                                                WeakAuras.ScanEvents("MERFIN_RAID_CDS", "FRONTEND_REGISTER", frontend)
                                                                                                                                                                                                                                                                end
