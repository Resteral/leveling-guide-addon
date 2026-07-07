-- CoALevelGuide_LootTables.lua
-- A mock database of NPC drops for the Conquest of Azeroth Leveling Guide

-- Map: NPC ID -> Array of drops
-- Each drop has an `id` (Item ID) and `chance` (Drop percentage)
CoALevelGuide_LootTables = {
    -- 69: Timber Wolf (Elwynn)
    [69] = {
        { id = 2589, chance = 15 }, -- Linen Cloth
        { id = 2098, chance = 40 }, -- Ruined Pelt
        { id = 769, chance = 5 },   -- Chunk of Boar Meat (Testing)
    },
    -- 113: Boar (Elwynn/Durotar)
    [113] = {
        { id = 769, chance = 45 },  -- Chunk of Boar Meat
        { id = 2098, chance = 20 }, -- Ruined Pelt
    },
    -- 114: Defias Thug (Elwynn)
    [114] = {
        { id = 2589, chance = 35 }, -- Linen Cloth
        { id = 2592, chance = 5 },  -- Wool Cloth
        { id = 118, chance = 10 },  -- Minor Healing Potion
    },
    -- 3110: Felstalker (Testing Felsworn)
    [3110] = {
        { id = 4862, chance = 20 }, -- Glowing Scorpid Blood
    },
    -- Mock common target
    [1] = {
        { id = 19019, chance = 100 }, -- Thunderfury (For fun)
    }
}
