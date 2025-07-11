Config = Config or {}

Config.Debugging = false

-- [[ Clamming Zones ]] --
Config['clamming'] = {
    Zones = {
        { 
            type = 'poly',
            points = {
                vector2(-1406.37, -1577.14),
                vector2(-1355.71, -1553.26),
                vector2(-1275.5, -1667.78),
                vector2(-1328.14, -1733.09)
            },
            minZ = -10.0,
            maxZ = 1000.0
        },
    },
    RodItem = "shovel",
    Time = 10000,
}

-- [[ Traditional Fishing Zones ]] --
Config['traditional'] = {
    RodItem = "fishingrod",
    BaitItem = "fishbait",
    Time = 15000,
}

-- [[ Deep Sea Fishing Zones ]] --
Config['deepsea'] = {
    NetItem = 'fishingnet', -- name for the boat fishing net
    PotItem = 'fishingpot', -- name for the boat crabbing pot
    BaitItem = "fishbait",
    Time = 20000,
    BoatModel = "reefer",
    AnchoredThreshold = 0.2,
    BoatProximity = 15.0,
}

-- [[ Global Options ]] --
Config.FishTypes = {
    ['clamming'] = {
        CatchChance = 0.7, -- Global chance of catching something (0.0 to 1.0)
        Fish = {
            'hardclam', -- Chowder Clam
            'softclam', -- Steamer Clam
            'razor',-- Razor Clam
            'manila', -- Manila Clam
            'surfclam', -- Atlantic Surf Clam
        }
    },
    ['traditional'] = {
        CatchChance = 0.7, -- Global chance of catching something (0.0 to 1.0)
        Fish = {
            'salmon', -- Atlantic Salmon
            'trout',-- Rainbow Trout
            'euroeel',-- European Eel
            'flounder', -- Starry Flounder
            'bass', -- Striped Bass
        }
    },
    ['deepsea'] = {
        CatchChance = 0.7, -- Global chance of catching something (0.0 to 1.0)
        Fish = {
            'tuna',-- Bluefin Tuna
            'marlin',-- Blue Marlin
            'swordfish', -- Swordfish
            'grouper', -- Grouper
            'snapper', -- Red Snapper
        },
        Crustacean = {
            'crab',
            'shrimp',
            'lobster',
        }
    },
}