-- PalWhip configuration
-- Edit values below, then restart the game (or hot-reload mods with Ctrl+R in the UE4SS console).

local config = {
    -- Key that cracks the whip. Any UE4SS key name works: "F7", "G", "K", "NUM_ONE", ...
    -- Full list: https://docs.ue4ss.com/lua-api/table-definitions/key.html
    WhipKey = "F7",

    -- Radius around the player in which pals are whipped back to normal.
    -- Unreal units are centimeters: 9000 = 90 m (roughly a whole base).
    -- Set to 0 to affect every loaded pal regardless of distance.
    Range = 9000.0,

    -- Only affect pals that have an owner (i.e. your caught pals / base workers).
    -- Set to false to also affect wild pals in range.
    OwnedOnly = true,

    -- What the whip fixes:
    CureSickness  = true,  -- Depression, Ulcer, Sprain, Fracture, Weakness, Cold, ...
    RestoreSanity = true,  -- SAN back to 100
    HealHP        = true,  -- HP back to full (also un-incapacitates)
    FillStomach   = false, -- also refill hunger (off by default; feed your pals!)

    -- Seconds between whip cracks (prevents accidental spam).
    Cooldown = 1.0,

    -- Show an in-game system chat message with the result.
    Announce = true,
}

return config
