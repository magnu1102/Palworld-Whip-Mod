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

    ------------------------------------------------------------------
    -- Whip item (requires the PalWhipItem PalSchema mod to be installed)
    ------------------------------------------------------------------

    -- What you need before the whip key works:
    --   "equipped"  - the crafted Pal Whip must be in your hands
    --   "inventory" - it just has to be somewhere in your inventory
    --   "none"      - pure hotkey mode (e.g. if you skip PalSchema)
    ItemRequirement = "equipped",

    -- Static item id of the whip. Must match the id in
    -- PalWhipItem/items/palwhip.json.
    WhipItemId = "PalWhip",

    ------------------------------------------------------------------
    -- Sound
    ------------------------------------------------------------------

    -- Play a sound when the whip cracks.
    PlaySound = true,

    -- Row name from the game's SoundID data table (DT_SoundID). If set,
    -- this is tried first via PalSoundUtility.PlaySoundByActor.
    -- Leave empty to use SoundEventPatterns below instead.
    SoundID = "",

    -- Exact name of a loaded AkAudioEvent (Wwise sound event) to play.
    -- Press the SoundDumpKey in-game to print all loaded event names to
    -- the UE4SS console, then paste your favorite here.
    SoundEventName = "",

    -- If SoundID and SoundEventName are empty, the first loaded
    -- AkAudioEvent whose name contains one of these (case-insensitive)
    -- patterns is used. Patterns are tried in order.
    SoundEventPatterns = { "whip", "attack_hit", "melee", "swing", "decide" },

    -- Debug key: dumps all loaded AkAudioEvent names to the UE4SS console
    -- so you can pick a SoundEventName. Set to "" to disable.
    SoundDumpKey = "F8",
}

return config
