Config = Config or {}

Config.Debugging = false

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
    MinigameDifficulty = 0.6
}

Config['traditional'] = {
    Zones = {
         {
            type = 'box',
            coords = vector3(-1428.8, -1579.74, 0.8),
            length = 10.0,
            width = 5.0,
            heading = 45.0,
            minZ = 0.8 - 5,
            maxZ = 0.8 + 5
        },
    },
    RodItem = "fishingrod",
    BaitItem = "fishbait",
    Time = 15000,
    MinigameDifficulty = 0.5,
}

Config['deepsea'] = {
    Zones = {
        {
            type = 'circle',
            coords = vector3(-1972.73, -1417.85, 6.33),
            radius = 200.0,
            minZ = -50.0,
            maxZ = 50.0
        },
    },
    RodItem = nil,
    BaitItem = "fishbait",
    Time = 20000,
    MinigameDifficulty = 0.7,
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
        }
    },
}

Config.Items = {
    create = true, -- Set this to true to enable item registration
    list = {
        {
            name = 'fishingrod',
            label = 'Fishing Rod',
            weight = 50,
            type = 'item',
            ammotype = nil,
            image = 'fishingrod.png',
            unique = false,
            usable = true,
            shouldClose = true,
            description = ''
        },{
            name = 'shovel',
            label = 'Shovel',
            weight = 50,
            type = 'item',
            ammotype = nil,
            image = 'shovel.png',
            unique = false,
            usable = true,
            shouldClose = true,
            description = ''
        },{
            name = 'fishbait',
            label = 'Fishing Bait',
            weight = 50,
            type = 'item',
            ammotype = nil,
            image = 'fishbait.png',
            unique = false,
            usable = false,
            shouldClose = false,
            description = ''
        },
        -- Add more item definitions here, following the same structure!
        {
            name = 'hardclam',
            label = 'Chowder Clam',
            weight = 25,
            type = 'item',
            ammotype = nil,
            image = 'fish.png',
            unique = false,
            usable = false,
            shouldClose = false,
            description = ''
        },{
            name = 'softclam',
            label = 'Steamer Clam',
            weight = 25,
            type = 'item',
            ammotype = nil,
            image = 'fish.png',
            unique = false,
            usable = false,
            shouldClose = false,
            description = ''
        },{
            name = 'razor',
            label = 'Razor Clam',
            weight = 25,
            type = 'item',
            ammotype = nil,
            image = 'fish.png',
            unique = false,
            usable = false,
            shouldClose = false,
            description = ''
        },{
            name = 'manila',
            label = 'Manila Clam',
            weight = 25,
            type = 'item',
            ammotype = nil,
            image = 'fish.png',
            unique = false,
            usable = false,
            shouldClose = false,
            description = ''
        },{
            name = 'surfclam',
            label = 'Atlantic Surf Clam',
            weight = 25,
            type = 'item',
            ammotype = nil,
            image = 'fish.png',
            unique = false,
            usable = false,
            shouldClose = false,
            description = ''
        },
        -----------
        {
            name = 'salmon',
            label = 'tlantic Salmon',
            weight = 250,
            type = 'item',
            ammotype = nil,
            image = 'fish.png',
            unique = false,
            usable = false,
            shouldClose = false,
            description = ''
        },{
            name = 'trout',
            label = 'Rainbow Trout',
            weight = 250,
            type = 'item',
            ammotype = nil,
            image = 'fish.png',
            unique = false,
            usable = false,
            shouldClose = false,
            description = ''
        },{
            name = 'euroeel',
            label = 'European Eel',
            weight = 250,
            type = 'item',
            ammotype = nil,
            image = 'fish.png',
            unique = false,
            usable = false,
            shouldClose = false,
            description = ''
        },{
            name = 'flounder',
            label = 'Starry Flounder',
            weight = 250,
            type = 'item',
            ammotype = nil,
            image = 'fish.png',
            unique = false,
            usable = false,
            shouldClose = false,
            description = ''
        },{
            name = 'bass',
            label = 'Striped Bass',
            weight = 250,
            type = 'item',
            ammotype = nil,
            image = 'fish.png',
            unique = false,
            usable = false,
            shouldClose = false,
            description = ''
        },
        -----------
        {
            name = 'tuna',
            label = 'Bluefin Tuna',
            weight = 750,
            type = 'item',
            ammotype = nil,
            image = 'fish.png',
            unique = false,
            usable = false,
            shouldClose = false,
            description = ''
        },{
            name = 'marlin',
            label = 'Blue Marlin',
            weight = 750,
            type = 'item',
            ammotype = nil,
            image = 'fish.png',
            unique = false,
            usable = false,
            shouldClose = false,
            description = ''
        },{
            name = 'swordfish',
            label = 'Swordfish',
            weight = 750,
            type = 'item',
            ammotype = nil,
            image = 'fish.png',
            unique = false,
            usable = false,
            shouldClose = false,
            description = ''
        },{
            name = 'grouper',
            label = 'Grouper',
            weight = 750,
            type = 'item',
            ammotype = nil,
            image = 'fish.png',
            unique = false,
            usable = false,
            shouldClose = false,
            description = ''
        },{
            name = 'snapper',
            label = 'Red Snapper',
            weight = 750,
            type = 'item',
            ammotype = nil,
            image = 'fish.png',
            unique = false,
            usable = false,
            shouldClose = false,
            description = ''
        },
    }
}