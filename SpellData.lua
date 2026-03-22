-- SpellData.lua
-- Spell database for the Cooldowns addon.
-- Extracted and adapted from the WeakAuras backend in Cooldowns.lua.
--
-- Fields per spell entry:
--   dur            (number)  Base cooldown duration in seconds.
--   index          (number)  Display sort order within the class.
--   tReq           (bool)    Spell requires a talent to be available.
--   tabIndex       (number)  Talent tree tab (1-3) for tReq / minus checks.
--   talentIndex    (number)  Index within the talent tab.
--   minus          (bool)    A talent reduces the base cooldown.
--   minusTabIndex  (table)   Talent tab indices for the reduction.
--   minusTalentIndex (table) Talent indices within those tabs.
--   minusPerPoint  (table)   Seconds reduced per talent point, parallel to above.
--   castableOnOthers (bool)  Spell can target another player.

local _, ns = ...

ns.spellData = {

    -- ===== DEATH KNIGHT =====
    ["DEATHKNIGHT"] = {
        -- Anti-Magic Shell
        [48707] = { dur = 45,   index = 1 },
        -- Anti-Magic Zone
        [51052] = { dur = 120,  index = 2,
                    tReq = true, tabIndex = 3, talentIndex = 22,
                    castableOnOthers = true },
        -- Hysteria
        [49016] = { dur = 180,  index = 3,
                    tReq = true, tabIndex = 1, talentIndex = 19,
                    castableOnOthers = true },
        -- Icebound Fortitude
        [48792] = { dur = 120,  index = 4 },
        -- Mark of Blood
        [49005] = { dur = 180,  index = 5,
                    tReq = true, tabIndex = 1, talentIndex = 15 },
        -- Rune Tap
        [48982] = { dur = 60,   index = 6,
                    tReq = true, tabIndex = 1, talentIndex = 7,
                    minus = true,
                    minusTabIndex = { 1 }, minusTalentIndex = { 10 }, minusPerPoint = { 10 } },
        -- Vampiric Blood
        [55233] = { dur = 60,   index = 7,
                    tReq = true, tabIndex = 1, talentIndex = 23 },
        -- Army of the Dead
        [42650] = { dur = 600,  index = 8,
                    minus = true,
                    minusTabIndex = { 3 }, minusTalentIndex = { 13 }, minusPerPoint = { 120 } },
        -- Blood Tap
        [45529] = { dur = 60,   index = 9 },
    },

    -- ===== DRUID =====
    ["DRUID"] = {
        -- Innervate
        [29166] = { dur = 180, index = 1, castableOnOthers = true },
        -- Rebirth
        [48477] = { dur = 600, index = 2, castableOnOthers = true },
        -- Tranquility
        [48447] = { dur = 480, index = 3, castableOnOthers = true },
        -- Barkskin
        [22812] = { dur = 60,  index = 4 },
        -- Survival Instincts
        [61336] = { dur = 180, index = 5,
                    tReq = true, tabIndex = 2, talentIndex = 7 },
        -- Frenzied Regeneration
        [22842] = { dur = 180, index = 6 },
    },

    -- ===== HUNTER =====
    ["HUNTER"] = {
        -- Deterrence
        [19263] = { dur = 60,  index = 1 },
        -- Misdirection
        [34477] = { dur = 30,  index = 2, castableOnOthers = true },
        -- Master's Call
        [53271] = { dur = 60,  index = 3, castableOnOthers = true },
        -- Readiness
        [23989] = { dur = 180, index = 4 },
    },

    -- ===== MAGE =====
    ["MAGE"] = {
        -- Ice Block
        [45438] = { dur = 300, index = 1 },
        -- Invisibility
        [66]    = { dur = 180, index = 2 },
    },

    -- ===== PALADIN =====
    ["PALADIN"] = {
        -- Aura Mastery
        [31821] = { dur = 120, index = 1,
                    tReq = true, tabIndex = 1, talentIndex = 6,
                    castableOnOthers = true },
        -- Divine Protection
        [498]   = { dur = 180, index = 2,
                    minus = true,
                    minusTabIndex = { 2 }, minusTalentIndex = { 14 }, minusPerPoint = { 30 } },
        -- Divine Sacrifice
        [64205] = { dur = 120, index = 3,
                    tReq = true, tabIndex = 2, talentIndex = 6,
                    castableOnOthers = true },
        -- Divine Shield
        [642]   = { dur = 300, index = 4,
                    minus = true,
                    minusTabIndex = { 2 }, minusTalentIndex = { 14 }, minusPerPoint = { 30 } },
        -- Lay on Hands
        [48788] = { dur = 1200, index = 5,
                    minus = true,
                    minusTabIndex = { 1 }, minusTalentIndex = { 8 }, minusPerPoint = { 120 },
                    castableOnOthers = true },
        -- Hand of Freedom
        [1044]  = { dur = 25,  index = 6, castableOnOthers = true },
        -- Hand of Protection
        [10278] = { dur = 300, index = 7,
                    minus = true,
                    minusTabIndex = { 2 }, minusTalentIndex = { 4 }, minusPerPoint = { 60 },
                    castableOnOthers = true },
        -- Hand of Sacrifice
        [6940]  = { dur = 120, index = 8, castableOnOthers = true },
        -- Hand of Salvation
        [1038]  = { dur = 120, index = 9, castableOnOthers = true },
        -- Hammer of Justice
        [10308] = { dur = 60,  index = 10,
                    minus = true,
                    minusTabIndex = { 2, 2 }, minusTalentIndex = { 10, 25 }, minusPerPoint = { 10, 5 } },
        -- Holy Wrath
        [48817] = { dur = 30,  index = 11 },
        -- Divine Plea
        [54428] = { dur = 60,  index = 12 },
        -- Ardent Defender
        [66233] = { dur = 120, index = 13,
                    tReq = true, tabIndex = 2, talentIndex = 18 },
    },

    -- ===== PRIEST =====
    ["PRIEST"] = {
        -- Divine Hymn
        [64843] = { dur = 480, index = 1, castableOnOthers = true },
        -- Fear Ward
        [6346]  = { dur = 180, index = 2, castableOnOthers = true },
        -- Guardian Spirit
        [47788] = { dur = 180, index = 3,
                    tReq = true, tabIndex = 2, talentIndex = 27,
                    castableOnOthers = true },
        -- Hymn of Hope
        [64901] = { dur = 360, index = 4, castableOnOthers = true },
        -- Pain Suppression
        [33206] = { dur = 180, index = 5,
                    tReq = true, tabIndex = 1, talentIndex = 25,
                    minus = true,
                    minusTabIndex = { 1 }, minusTalentIndex = { 23 }, minusPerPoint = { 18 },
                    castableOnOthers = true },
        -- Power Infusion
        [10060] = { dur = 120, index = 6,
                    tReq = true, tabIndex = 1, talentIndex = 19,
                    minus = true,
                    minusTabIndex = { 1 }, minusTalentIndex = { 23 }, minusPerPoint = { 12 },
                    castableOnOthers = true },
    },

    -- ===== ROGUE =====
    ["ROGUE"] = {
        -- Cloak of Shadows
        [31224] = { dur = 90,  index = 1,
                    minus = true,
                    minusTabIndex = { 3 }, minusTalentIndex = { 7 }, minusPerPoint = { 15 } },
        -- Evasion
        [26669] = { dur = 180, index = 2,
                    minus = true,
                    minusTabIndex = { 2 }, minusTalentIndex = { 7 }, minusPerPoint = { 30 } },
        -- Tricks of the Trade
        [57934] = { dur = 30,  index = 3,
                    minus = true,
                    minusTabIndex = { 3 }, minusTalentIndex = { 26 }, minusPerPoint = { 5 },
                    castableOnOthers = true },
        -- Vanish
        [26889] = { dur = 180, index = 4,
                    minus = true,
                    minusTabIndex = { 3 }, minusTalentIndex = { 7 }, minusPerPoint = { 30 } },
    },

    -- ===== SHAMAN =====
    ["SHAMAN"] = {
        -- Bloodlust (Horde)
        [2825]  = { dur = 300,  index = 1, castableOnOthers = true },
        -- Heroism (Alliance)
        [32182] = { dur = 300,  index = 2, castableOnOthers = true },
        -- Mana Tide Totem
        [16190] = { dur = 300,  index = 3,
                    tReq = true, tabIndex = 3, talentIndex = 17,
                    castableOnOthers = true },
        -- Reincarnation
        [21169] = { dur = 1800, index = 4,
                    minus = true,
                    minusTabIndex = { 3 }, minusTalentIndex = { 3 }, minusPerPoint = { 420 } },
        -- Shamanistic Rage
        [30823] = { dur = 60,   index = 5,
                    tReq = true, tabIndex = 2, talentIndex = 26 },
    },

    -- ===== WARLOCK =====
    ["WARLOCK"] = {
        -- Soulstone Resurrection
        [47883] = { dur = 900, index = 1, castableOnOthers = true },
        -- Soulshatter
        [29858] = { dur = 180, index = 2 },
    },

    -- ===== WARRIOR =====
    ["WARRIOR"] = {
        -- Enraged Regeneration
        [55694] = { dur = 180, index = 1 },
        -- Last Stand
        [12975] = { dur = 180, index = 2,
                    tReq = true, tabIndex = 3, talentIndex = 6 },
        -- Shield Block
        [2565]  = { dur = 60,  index = 3,
                    minus = true,
                    minusTabIndex = { 3 }, minusTalentIndex = { 8 }, minusPerPoint = { 10 } },
        -- Shield Wall
        [871]   = { dur = 300, index = 4,
                    minus = true,
                    minusTabIndex = { 3 }, minusTalentIndex = { 8 }, minusPerPoint = { 13 } },
    },

    -- ===== ITEMS =====
    -- Item cooldowns tracked by their on-use spell ID (canonical = normal version).
    -- Heroic variants that fire a different spell ID are aliased to the canonical
    -- entry via ns.itemSpellAliases so both versions share a single cooldown bar.
    ["ITEMS"] = {
        -- Glowing Twilight Scale (Ruby Sanctum, all versions — 2 min cooldown)
        -- Normal spell: 75490  Heroic spell: 75495 → aliased to 75490
        [75490] = { dur = 120, index = 1 },
        -- Sindragosa's Flawless Fang (ICC, all versions — 1 min cooldown)
        -- Normal spell: 71635  Heroic spell: 71638 → aliased to 71635
        [71635] = { dur = 60,  index = 2 },
    },
}

-- Human-readable class names for the options UI.
ns.classDisplayNames = {
    ["DEATHKNIGHT"] = "Death Knight",
    ["DRUID"]       = "Druid",
    ["HUNTER"]      = "Hunter",
    ["MAGE"]        = "Mage",
    ["PALADIN"]     = "Paladin",
    ["PRIEST"]      = "Priest",
    ["ROGUE"]       = "Rogue",
    ["SHAMAN"]      = "Shaman",
    ["WARLOCK"]     = "Warlock",
    ["WARRIOR"]     = "Warrior",
    ["ITEMS"]       = "Items",
}

-- Canonical display order for classes in the options UI.
ns.classOrder = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
    "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "DRUID",
    "ITEMS",
}

-- Class colours (r, g, b) matching in-game class colours.
ns.classColors = {
    ["WARRIOR"]     = { 0.78, 0.61, 0.43 },
    ["PALADIN"]     = { 0.96, 0.55, 0.73 },
    ["HUNTER"]      = { 0.67, 0.83, 0.45 },
    ["ROGUE"]       = { 1.00, 0.96, 0.41 },
    ["PRIEST"]      = { 1.00, 1.00, 1.00 },
    ["DEATHKNIGHT"] = { 0.77, 0.12, 0.23 },
    ["SHAMAN"]      = { 0.00, 0.44, 0.87 },
    ["MAGE"]        = { 0.41, 0.80, 0.94 },
    ["WARLOCK"]     = { 0.58, 0.51, 0.79 },
    ["DRUID"]       = { 1.00, 0.49, 0.04 },
    ["ITEMS"]       = { 1.00, 0.82, 0.00 },
}

-- Spell IDs for heroic item variants that differ from the normal-version spell ID,
-- aliased to their canonical (normal) counterpart in spellData["ITEMS"] so both
-- versions share a single cooldown bar.
ns.itemSpellAliases = {
    [75495] = 75490,   -- Glowing Twilight Scale (Heroic → Normal)
    [71638] = 71635,   -- Sindragosa's Flawless Fang (Heroic → Normal)
}
