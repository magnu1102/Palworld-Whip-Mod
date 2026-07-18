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

    ------------------------------------------------------------------
    -- Multiplayer
    ------------------------------------------------------------------

    -- Share your boombox with other players via tagged in-game chat
    -- messages ("[BBX] ..."). Everyone who has this mod installed hears
    -- the same track from the same spot and sees the marker. Music files
    -- are matched by filename, so custom songs must exist in everyone's
    -- music folder.
    ShareWithOtherPlayers = true,

    -- Spawn a small treasure chest at the boombox spot. When you are the
    -- host this is a replicated actor, so even players without the boombox
    -- mod can see it. A local marker is used if network spawning is unavailable.
    SpawnMarker = true,

    -- Blueprint class used for the marker. Any loaded actor class path
    -- works; the default is a loot-free treasure chest visual.
    -- MarkerClass = "/Game/Pal/Blueprint/MapObject/Object/TreasureBox/Visual/BP_TreasureBoxVisual_Grade01.BP_TreasureBoxVisual_Grade01_C",
}

return config
