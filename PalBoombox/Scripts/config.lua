-- PalBoombox configuration
-- Edit values below, then restart the game (or hot-reload mods with Ctrl+R in the UE4SS console).

local config = {
    -- Key that places / picks up the boombox at your current position.
    -- Full list of key names: https://docs.ue4ss.com/lua-api/table-definitions/key.html
    PlaceKey = "F9",

    -- Key that switches to the next track (works while placed or not).
    NextTrackKey = "F10",

    -- Require the crafted Boombox item in your inventory to place it.
    -- (Needs the PalBoomboxItem PalSchema mod.) Set false for hotkey-only mode.
    RequireItem = true,
    ItemId = "PalBoombox",

    -- Overall loudness (0..1).
    MasterVolume = 0.8,

    -- Distance (cm) at which the music starts to fade. 800 = 8 m.
    RefDistance = 800.0,

    -- Distance (cm) beyond which the boombox is inaudible. 8000 = 80 m.
    MaxDistance = 8000.0,

    -- How strongly the sound pans left/right as you turn (0 = mono, 1 = full).
    PanStrength = 0.8,

    -- Automatically start the audio companion (a small hidden PowerShell
    -- process next to this mod) when you place the boombox.
    AutoStartCompanion = true,

    -- Show in-game chat messages for place/pickup/track changes.
    Announce = true,
}

return config
