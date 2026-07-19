-- PalBoombox configuration
-- Edit values below, then restart the game (or hot-reload mods with Ctrl+R in the UE4SS console).

local config = {
    -- The boombox itself is placed through Palworld's native build menu.
    -- Playback and local listening controls. F8/F9 are intentionally kept
    -- away from the F10 console binding installed by UE4SS.
    -- Full key list: https://docs.ue4ss.com/lua-api/table-definitions/key.html
    VolumeDownKey = "F5",
    VolumeUpKey = "F6",
    PauseKey = "F8",
    NextTrackKey = "F9",
    VolumeStep = 0.25,

    -- Overall loudness (0..3). Values above 1 use layered playback to provide
    -- actual gain instead of being silently capped by WPF MediaPlayer.
    MasterVolume = 1.5,
    MaxVolume = 3.0,

    -- Full-volume radius in cm. Music now remains at full listening volume
    -- inside this radius, then fades smoothly instead of dropping immediately.
    RefDistance = 800.0,

    -- Distance (cm) beyond which the boombox is inaudible. 8000 = 80 m.
    MaxDistance = 8000.0,

    -- Shape applied after the smooth outer-distance taper. Values below 1 keep
    -- the mid field audible; smoothstep still makes the final approach to
    -- silence gradual instead of falling off a volume cliff.
    FadeExponent = 0.65,

    -- How strongly the sound pans left/right as you turn (0 = mono, 1 = full).
    PanStrength = 0.8,

    -- Automatically start the hidden audio companion when a completed Field
    -- Boombox is present in the replicated world.
    AutoStartCompanion = true,

    -- Show one concise in-game confirmation for an explicit volume-key press.
    -- Runtime status, world scans, and synchronization never print to chat.
    ShowControlFeedback = true,

    -- UE4SS console diagnostics are disabled by default. Enable only while
    -- troubleshooting; normal operation remains silent.
    DebugLogging = false,

    ------------------------------------------------------------------
    -- Multiplayer
    ------------------------------------------------------------------

    -- All clients derive the same bundled track and playback position from UTC
    -- time. No hidden chat messages or unsafe actor-spawn calls are used.
    SharedClockSync = true,
}

return config
