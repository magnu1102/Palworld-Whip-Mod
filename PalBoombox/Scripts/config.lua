-- PalBoombox configuration
-- Edit values below, then restart the game (or hot-reload mods with Ctrl+R in the UE4SS console).

local config = {
    -- Opens the unified Pal Tools control panel for both the whip and boombox.
    MenuKey = "F6",

    -- Show a one-time in-game hint explaining how to open the control panel.
    ShowWelcomeHint = true,

    -- Key that places / picks up the boombox at your current position.
    -- Full list of key names: https://docs.ue4ss.com/lua-api/table-definitions/key.html
    PlaceKey = "F9",

    -- Key that switches to the next track (works while placed or not).
    NextTrackKey = "F10",

    -- Opens a Windows file picker over the game. Select one or more MP3,
    -- WAV, or WMA files; they are copied into PalBoombox\music and become
    -- available without restarting the game.
    AddMusicKey = "F11",

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
    -- the same track from the same spot. Music files are matched by filename,
    -- so custom songs must exist in everyone's music folder.
    ShareWithOtherPlayers = true,

    -- EXPERIMENTAL: spawn Palworld's own 1970s radio prop at the boombox spot.
    -- Keep this false. Actor spawning currently causes an access-violation
    -- crash in UE4SS on the July 2026 Palworld build. The synchronized spatial
    -- audio works without the visual prop. This new option deliberately does
    -- not honor the older SpawnMarker setting, keeping upgraded installs safe.
    ExperimentalWorldMarker = false,

    -- Advanced appearance controls. These defaults use assets already shipped
    -- with Palworld, so no custom cooked .pak is required.
    MarkerClass = "/Script/Engine.StaticMeshActor",
    MarkerMesh = "/Game/Pal/Model/Prop/Furniture/Furnitures_Of_The_70s/SM_Radio_02.SM_Radio_02",
    MarkerScale = 1.0,

    -- Player positions are measured at capsule centre. This drops the radio
    -- roughly 90 cm so it rests on the floor instead of floating at waist height.
    MarkerZOffset = -90.0,
}

return config
