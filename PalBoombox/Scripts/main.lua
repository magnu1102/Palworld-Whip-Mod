-- PalBoombox
--
-- A completed Field Boombox is a real Palworld build object registered by
-- PalSchema. Palworld owns placement preview, collision, replication, saving,
-- and dismantling. This Lua layer only discovers that replicated object and
-- feeds its numeric position to the hidden spatial-audio companion.
--
-- Multiplayer playback is deterministic: every client uses the same bundled
-- playlist metadata and UTC clock. There are no chat telegrams, custom actor
-- spawns, retained UObject references, or external control windows.

local UEHelpers = require("UEHelpers")

local okConfig, config = pcall(require, "config")
if not okConfig or type(config) ~= "table" then config = {} end

local function clamp(value, low, high)
    value = tonumber(value) or low
    return math.max(low, math.min(high, value))
end

local VOLUME_DOWN_KEY = config.VolumeDownKey or "F5"
local VOLUME_UP_KEY = config.VolumeUpKey or "F6"
local PAUSE_KEY = config.PauseKey or "F8"
-- Releases before the native-building rewrite used F10 for Next Track. UE4SS
-- now owns F10 for its console, and upgrades intentionally preserve config.lua,
-- so migrate only that known legacy value while respecting other custom keys.
local NEXT_TRACK_KEY = config.NextTrackKey
if NEXT_TRACK_KEY == nil or NEXT_TRACK_KEY == "F10" then NEXT_TRACK_KEY = "F9" end
local VOLUME_STEP = clamp(config.VolumeStep or 0.25, 0.05, 1.0)
local MAX_VOLUME = clamp(config.MaxVolume or 3.0, 1.0, 3.0)
local masterVolume = clamp(config.MasterVolume or 1.5, 0.0, MAX_VOLUME)
local REF_DISTANCE = math.max(1.0, tonumber(config.RefDistance) or 800.0)
local MAX_DISTANCE = math.max(REF_DISTANCE + 1.0, tonumber(config.MaxDistance) or 8000.0)
-- With a smoothstep base, exponents above 0.5 retain a zero-slope endpoint.
-- Clamp old/custom settings accordingly so the outer edge cannot become a
-- sudden audible cutoff again.
local FADE_EXPONENT = clamp(config.FadeExponent or 0.65, 0.55, 2.0)
local PAN_STRENGTH = clamp(config.PanStrength or 0.8, 0.0, 1.0)
local AUTO_START = config.AutoStartCompanion ~= false
local SHOW_FEEDBACK = config.ShowControlFeedback ~= false
local DEBUG_LOGGING = config.DebugLogging == true
local SHARED_CLOCK = config.SharedClockSync ~= false

local BUILD_OBJECT_ID = "PalBoombox"
local SCAN_INTERVAL = 1
local RESYNC_INTERVAL = 15
local DRIFT_TOLERANCE = 4.0

local basePath = nil
local playlist = nil
local playlistDuration = 0.0
local stationClockOffset = 0.0
local stationPaused = false
local stationPausedCursor = 0.0
local localClockOrigin = os.time()
local stateSequence = 0
local seekSequence = 0
local lastCompanionStart = 0
local lastScanEpoch = 0
local lastResyncEpoch = 0
local currentRadio = nil
local currentTrack = nil
local currentSeek = 0.0
local forceSeek = false
local lastWrittenPlaying = nil
local reportedErrors = {}
local trackPresence = {}

local function debugLog(message)
    if DEBUG_LOGGING then
        print(string.format("[PalBoombox] %s\n", tostring(message)))
    end
end

local function reportOnce(key, message)
    if reportedErrors[key] then return end
    reportedErrors[key] = true
    print(string.format("[PalBoombox] ERROR: %s\n", tostring(message)))
end

local function tryGet(fn)
    local ok, value = pcall(fn)
    if ok then return value end
    return nil
end

local function getPawn()
    local controller = tryGet(function() return UEHelpers.GetPlayerController() end)
    if not controller or not tryGet(function() return controller:IsValid() end) then return nil end
    local pawn = tryGet(function() return controller.Pawn end)
    if pawn and tryGet(function() return pawn:IsValid() end) then
        return pawn, controller
    end
    return nil
end

local function notify(text)
    if not SHOW_FEEDBACK then return end
    local pawn = getPawn()
    if not pawn then return end
    pcall(function()
        local utility = StaticFindObject("/Script/Pal.Default__PalUtility")
        if utility and utility:IsValid() then
            local ok = pcall(function() utility:SendSystemAnnounce(pawn, text) end)
            if not ok then utility:SendSystemAnnounce(pawn, FText(text)) end
        end
    end)
end

-- -------------------------------------------------------------------------
-- Companion IPC
-- -------------------------------------------------------------------------

local function resolveBasePath()
    if basePath then return basePath end
    local candidates = {
        "ue4ss/Mods/PalBoombox/",
        "Pal/Binaries/Win64/ue4ss/Mods/PalBoombox/",
        "Mods/PalBoombox/",
    }
    for _, candidate in ipairs(candidates) do
        local probe = io.open(candidate .. "companion/boombox_companion.ps1", "r")
        if probe then
            probe:close()
            basePath = candidate
            return basePath
        end
    end
    reportOnce("base_path", "could not locate the installed PalBoombox folder")
    return nil
end

local function writeState(fields)
    local base = resolveBasePath()
    if not base then return false end

    stateSequence = stateSequence + 1
    local lines = { "seq=" .. tostring(stateSequence) }
    local keys = {}
    for key in pairs(fields) do table.insert(keys, key) end
    table.sort(keys)
    for _, key in ipairs(keys) do
        table.insert(lines, string.format("%s=%s", key, tostring(fields[key])))
    end
    -- The companion accepts a snapshot only when these two values match. A
    -- concurrent read of a partially rewritten file therefore keeps using
    -- the previous complete state instead of briefly stopping or misplaying.
    table.insert(lines, "commit=" .. tostring(stateSequence))

    local file = io.open(base .. "ipc/state.txt", "w")
    if not file then
        reportOnce("state_write", "could not write the audio state file")
        return false
    end
    file:write(table.concat(lines, "\n"))
    file:close()
    return true
end

local function readCompanionStatus()
    local base = resolveBasePath()
    if not base then return nil end
    local file = io.open(base .. "ipc/companion.txt", "r")
    if not file then return nil end
    local status = {}
    for line in file:lines() do
        local key, value = line:match("^([%w_]+)=(.*)$")
        if key == "alive" then status.alive = tonumber(value) end
        if key == "current" then status.current = value end
        if key == "pos" then status.pos = tonumber(value) end
    end
    file:close()
    if not status.alive or os.time() - status.alive >= 8 then return nil end
    return status
end

local function startCompanion()
    if not AUTO_START then return end
    local base = resolveBasePath()
    if not base then return end
    local now = os.time()
    if now - lastCompanionStart < 15 then return end
    lastCompanionStart = now
    local launcher = (base .. "companion/launch_hidden.vbs"):gsub("/", "\\")
    os.execute(string.format('wscript.exe //B //NoLogo "%s"', launcher))
end

local function ensureCompanion()
    local status = readCompanionStatus()
    if status then return status end
    startCompanion()
    return nil
end

local function loadSavedVolume()
    local base = resolveBasePath()
    if not base then return end
    local file = io.open(base .. "ipc/volume.txt", "r")
    if not file then return end
    local saved = tonumber(file:read("*l"))
    file:close()
    if saved then masterVolume = clamp(saved, 0.0, MAX_VOLUME) end
end

local function saveVolume()
    local base = resolveBasePath()
    if not base then return end
    local file = io.open(base .. "ipc/volume.txt", "w")
    if file then
        file:write(string.format("%.2f", masterVolume))
        file:close()
    end
end

-- -------------------------------------------------------------------------
-- Deterministic shared playlist
-- -------------------------------------------------------------------------

local function loadPlaylist()
    if playlist then return #playlist > 0 end
    playlist = {}
    playlistDuration = 0.0
    local base = resolveBasePath()
    if not base then return false end
    local file = io.open(base .. "shared_playlist.txt", "r")
    if not file then
        reportOnce("playlist", "shared_playlist.txt is missing; reinstall the current release")
        return false
    end
    for line in file:lines() do
        local durationText, filename = line:match("^([%d%.]+)|(.+)$")
        local duration = tonumber(durationText)
        if duration and duration > 1 and filename and filename ~= "" then
            table.insert(playlist, {
                duration = duration,
                filename = filename:gsub("\r$", ""),
            })
            playlistDuration = playlistDuration + duration
        end
    end
    file:close()
    if #playlist == 0 or playlistDuration <= 0 then
        reportOnce("playlist_empty", "the shared playlist contains no valid tracks")
        return false
    end
    return true
end

local function stationCursor(epoch)
    if not loadPlaylist() then return nil end
    local clock = SHARED_CLOCK and epoch or (epoch - localClockOrigin)
    if stationPaused then return stationPausedCursor % playlistDuration end
    return (clock + stationClockOffset) % playlistDuration
end

local function trackAtCursor(cursor)
    if not playlist or #playlist == 0 then return nil end
    for index, entry in ipairs(playlist) do
        if cursor < entry.duration then return entry, cursor, index end
        cursor = cursor - entry.duration
    end
    return playlist[1], 0.0, 1
end

local function scheduledTrack(epoch)
    local cursor = stationCursor(epoch)
    if cursor == nil then return nil end
    return trackAtCursor(cursor)
end

local function playlistStart(index)
    if index <= 1 then return 0.0 end
    local cursor = 0.0
    for current = 1, index - 1 do
        cursor = cursor + playlist[current].duration
    end
    return cursor
end

local function trackExists(filename)
    if trackPresence[filename] ~= nil then return trackPresence[filename] end
    local base = resolveBasePath()
    if not base then return false end
    local file = io.open(base .. "music/" .. filename, "rb")
    if not file then
        trackPresence[filename] = false
        return false
    end
    file:close()
    trackPresence[filename] = true
    return true
end

-- -------------------------------------------------------------------------
-- Replicated build-object discovery
-- -------------------------------------------------------------------------

local function getBuildObjectId(actor)
    return tryGet(function() return actor.BuildObjectId:ToString() end)
end

local function findNearestRadio(playerLocation)
    -- Use the stable native base class and filter by the replicated row ID.
    -- Blueprint-generated class lookup varies between UE4SS builds, while
    -- PalBuildObject is part of the game's reflected native API.
    local candidates = tryGet(function() return FindAllOf("PalBuildObject") end)
    if type(candidates) ~= "table" then return nil end

    local nearest = nil
    local nearestSquared = math.huge
    for _, actor in ipairs(candidates) do
        local valid = tryGet(function() return actor:IsValid() end)
        if valid and getBuildObjectId(actor) == BUILD_OBJECT_ID then
            local available = tryGet(function() return actor:IsAvailable() end)
            if available ~= false then
                local location = tryGet(function() return actor:K2_GetActorLocation() end)
                if location then
                    local dx = location.X - playerLocation.X
                    local dy = location.Y - playerLocation.Y
                    local dz = location.Z - playerLocation.Z
                    local distanceSquared = dx * dx + dy * dy + dz * dz
                    if distanceSquared < nearestSquared then
                        nearestSquared = distanceSquared
                        -- Store only plain numbers. A UObject reference can become
                        -- invalid between ticks when an object is dismantled.
                        nearest = { x = location.X, y = location.Y, z = location.Z }
                    end
                end
            end
        end
    end
    return nearest
end

local function listenerYaw(pawn, controller)
    local yaw = tryGet(function()
        return controller.PlayerCameraManager:GetCameraRotation().Yaw
    end)
    if yaw == nil then yaw = tryGet(function() return pawn:K2_GetActorRotation().Yaw end) end
    return yaw or 0.0
end

local function stopPlayback()
    currentRadio = nil
    currentTrack = nil
    if lastWrittenPlaying ~= false then
        writeState({ playing = 0 })
        lastWrittenPlaying = false
    end
end

local function circularDifference(a, b, duration)
    local difference = math.abs(a - b)
    if duration and duration > 0 then difference = math.min(difference, duration - difference) end
    return difference
end

local function playbackTick()
    local pawn, controller = getPawn()
    if not pawn then
        stopPlayback()
        return false
    end

    local playerLocation = tryGet(function() return pawn:K2_GetActorLocation() end)
    if not playerLocation then
        stopPlayback()
        return false
    end

    local now = os.time()
    if now - lastScanEpoch >= SCAN_INTERVAL then
        lastScanEpoch = now
        currentRadio = findNearestRadio(playerLocation)
    end
    if not currentRadio then
        stopPlayback()
        return false
    end

    local entry, scheduledSeek = scheduledTrack(now)
    if not entry then
        stopPlayback()
        return false
    end
    if not trackExists(entry.filename) then
        reportOnce("missing_" .. entry.filename,
            "bundled track is missing: " .. entry.filename .. "; reinstall the current release")
        stopPlayback()
        return false
    end

    local companion = ensureCompanion()
    local needsSeek = forceSeek or currentTrack ~= entry.filename
    if needsSeek then
        currentTrack = entry.filename
        currentSeek = scheduledSeek
        seekSequence = seekSequence + 1
        lastResyncEpoch = now
        forceSeek = false
    elseif not stationPaused and now - lastResyncEpoch >= RESYNC_INTERVAL then
        lastResyncEpoch = now
        if not companion or companion.current ~= entry.filename or
            circularDifference(companion.pos or -9999, scheduledSeek, entry.duration) > DRIFT_TOLERANCE then
            currentSeek = scheduledSeek
            seekSequence = seekSequence + 1
        end
    end

    local dx = currentRadio.x - playerLocation.X
    local dy = currentRadio.y - playerLocation.Y
    local dz = currentRadio.z - playerLocation.Z
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)

    local volume = 0.0
    if distance <= REF_DISTANCE then
        volume = masterVolume
    elseif distance < MAX_DISTANCE then
        -- Smoothstep gives both ends a zero slope: the signal leaves the full-
        -- volume near field without a kink and approaches silence gradually.
        -- Applying the configurable exponent after smoothstep retains a broad
        -- outdoor field without the old linear curve's loud final metres.
        local progress = clamp(
            (distance - REF_DISTANCE) / (MAX_DISTANCE - REF_DISTANCE), 0.0, 1.0)
        local smoothProgress = progress * progress * (3.0 - 2.0 * progress)
        local fade = 1.0 - smoothProgress
        volume = masterVolume * fade ^ FADE_EXPONENT
    end

    local balance = 0.0
    if distance > 50 then
        local relativeAngle = math.rad(math.deg(math.atan(dy, dx)) - listenerYaw(pawn, controller))
        balance = math.sin(relativeAngle) * PAN_STRENGTH
        volume = volume * (0.85 + 0.15 * math.cos(relativeAngle))
    end

    writeState({
        playing = stationPaused and 0 or 1,
        track = currentTrack,
        volume = string.format("%.3f", clamp(volume, 0.0, MAX_VOLUME)),
        balance = string.format("%.3f", clamp(balance, -1.0, 1.0)),
        seek = string.format("%.3f", currentSeek),
        seekseq = seekSequence,
    })
    lastWrittenPlaying = not stationPaused
    return false
end

-- -------------------------------------------------------------------------
-- Local controls
-- -------------------------------------------------------------------------

local function displayTrackName(filename)
    return (tostring(filename or "Music"):gsub("%.[^%.]+$", ""))
end

local function stationBaseClock(epoch)
    return SHARED_CLOCK and epoch or (epoch - localClockOrigin)
end

local function toggleStationPause()
    if not currentRadio or not loadPlaylist() then return end
    local now = os.time()
    if stationPaused then
        stationClockOffset = (stationPausedCursor - stationBaseClock(now)) % playlistDuration
        stationPaused = false
        forceSeek = true
        notify("Field Boombox resumed")
    else
        stationPausedCursor = stationCursor(now) or 0.0
        stationPaused = true
        forceSeek = true
        notify("Field Boombox paused")
    end
end

local function nextStationTrack()
    if not currentRadio or not loadPlaylist() then return end
    local now = os.time()
    local cursor = stationCursor(now)
    local _, _, currentIndex = trackAtCursor(cursor or 0.0)
    local nextIndex = (currentIndex % #playlist) + 1
    local nextCursor = playlistStart(nextIndex)

    stationClockOffset = (nextCursor - stationBaseClock(now)) % playlistDuration
    stationPausedCursor = nextCursor
    stationPaused = false
    forceSeek = true
    notify("Now playing: " .. displayTrackName(playlist[nextIndex].filename))
end

local function setVolume(delta)
    local previous = masterVolume
    masterVolume = clamp(masterVolume + delta, 0.0, MAX_VOLUME)
    saveVolume()
    if math.abs(masterVolume - previous) < 0.001 then
        notify(string.format("Boombox listening volume: %d%% (limit)",
            math.floor(masterVolume * 100 + 0.5)))
    else
        notify(string.format("Boombox listening volume: %d%%",
            math.floor(masterVolume * 100 + 0.5)))
    end
end

local function registerKey(keyName, fallback, callback)
    local key = Key[keyName]
    if key == nil then
        reportOnce("key_" .. tostring(keyName),
            string.format("unknown key '%s'; using %s", tostring(keyName), fallback))
        key = Key[fallback]
    end
    RegisterKeyBind(key, {}, callback)
end

loadSavedVolume()
loadPlaylist()

registerKey(VOLUME_DOWN_KEY, "F5", function()
    ExecuteInGameThread(function() setVolume(-VOLUME_STEP) end)
end)
registerKey(VOLUME_UP_KEY, "F6", function()
    ExecuteInGameThread(function() setVolume(VOLUME_STEP) end)
end)
registerKey(PAUSE_KEY, "F8", function()
    ExecuteInGameThread(toggleStationPause)
end)
registerKey(NEXT_TRACK_KEY, "F9", function()
    ExecuteInGameThread(nextStationTrack)
end)

-- LoopAsync itself runs outside Unreal's game thread. Every UObject lookup and
-- method call is marshalled back to the game thread, and at most one tick may
-- be queued at a time. This avoids the cross-thread UObject access that made
-- earlier builds vulnerable to native access violations.
local tickQueued = false
LoopAsync(100, function()
    if not tickQueued then
        tickQueued = true
        ExecuteInGameThread(function()
            local ok, err = pcall(playbackTick)
            tickQueued = false
            if not ok then reportOnce("playback_tick", "playback tick failed: " .. tostring(err)) end
        end)
    end
    return false
end)
debugLog("loaded: native build discovery and deterministic shared playback active")
