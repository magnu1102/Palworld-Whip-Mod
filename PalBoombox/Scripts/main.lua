-- PalBoombox - a placeable boombox with spatial audio sea shanties and
-- multiplayer sync. The in-world marker is disabled because native actor
-- spawning is unsafe on the current Palworld/UE4SS build.
--
-- Place (default F9): the boombox is set down where you stand and a tagged
-- chat message tells every other player's mod to start the same track at the
-- same position. No native actor is spawned by this release.
-- Pick up (F9 again) removes it for everyone. F10 = next track.
--
-- Audio plays through a local companion process (see companion/) on each
-- machine, so every player who wants to HEAR it needs this mod installed.
-- Sync telegrams travel through the in-game chat as "[BBX] ..." messages.

local UEHelpers = require("UEHelpers")

local ok_cfg, config = pcall(require, "config")
if not ok_cfg or type(config) ~= "table" then config = {} end

local function clamp(value, low, high)
    value = tonumber(value) or low
    return math.max(low, math.min(high, value))
end

local PLACE_KEY      = config.PlaceKey       or "F9"
local NEXT_KEY       = config.NextTrackKey   or "F10"
local ADD_MUSIC_KEY  = config.AddMusicKey    or "F11"
local MENU_KEY       = config.MenuKey        or "F6"
local SHOW_WELCOME   = (config.ShowWelcomeHint ~= false)
local REQUIRE_ITEM   = (config.RequireItem   ~= false)
local ITEM_ID        = config.ItemId         or "PalBoombox"
local masterVolume   = clamp(config.MasterVolume or 0.8, 0.0, 2.0)
local REF_DIST       = math.max(1.0, tonumber(config.RefDistance) or 800.0)
local MAX_DIST       = math.max(REF_DIST + 1.0, tonumber(config.MaxDistance) or 8000.0)
local PAN_STRENGTH   = clamp(config.PanStrength or 0.8, 0.0, 1.0)
local AUTO_START     = (config.AutoStartCompanion ~= false)
local ANNOUNCE       = (config.Announce      ~= false)
local SHARE          = (config.ShareWithOtherPlayers ~= false)

local TAG = "[BBX]"

-- Session token identifies the boombox owner and lets us ignore our own echo.
math.randomseed(os.time() + math.floor(os.clock() * 1000))
local TOKEN = string.format("%d_%05d", os.time(), math.random(0, 99999))

-- Active boombox (one shared instance; last event wins)
local active = nil   -- { x, y, z, track, epoch, own (bool) }
local trackIndex = 1
local tracks = {}
local seq = 0
local seekSeq = 0
local pendingSeek = 0
local loopRunning = false
local basePath = nil
local lastCompanionStart = 0
local warnedNoCompanion = false
local importPending = false

local function log(msg)
    print(string.format("[PalBoombox] %s\n", tostring(msg)))
end

local function tryGet(fn)
    local ok, value = pcall(fn)
    if ok then return value end
    return nil
end

local function announce(context, text)
    if ANNOUNCE then
        pcall(function()
            local PalUtility = StaticFindObject("/Script/Pal.Default__PalUtility")
            if PalUtility and PalUtility:IsValid() then
                local ok = pcall(function() PalUtility:SendSystemAnnounce(context, text) end)
                if not ok then PalUtility:SendSystemAnnounce(context, FText(text)) end
            end
        end)
    end
    log(text)
end

-- ---------------------------------------------------------------------------
-- File IPC with the audio companion
-- ---------------------------------------------------------------------------

local function resolveBasePath()
    if basePath then return basePath end
    local candidates = {
        "ue4ss/Mods/PalBoombox/",
        "Pal/Binaries/Win64/ue4ss/Mods/PalBoombox/",
        "Mods/PalBoombox/",
    }
    for _, candidate in ipairs(candidates) do
        local f = io.open(candidate .. "companion/boombox_companion.ps1", "r")
        if f then
            f:close()
            basePath = candidate
            log("Mod folder resolved to " .. candidate)
            return basePath
        end
    end
    log("WARNING: could not locate the PalBoombox folder from the game's working directory")
    return nil
end

local function writeState(fields)
    local base = resolveBasePath()
    if not base then return end
    seq = seq + 1
    fields.seq = seq
    local lines = {}
    for k, v in pairs(fields) do
        table.insert(lines, string.format("%s=%s", k, tostring(v)))
    end
    local f = io.open(base .. "ipc/state.txt", "w")
    if f then
        f:write(table.concat(lines, "\n"))
        f:close()
    end
end

local function readCompanion()
    local base = resolveBasePath()
    if not base then return false end
    local f = io.open(base .. "ipc/companion.txt", "r")
    if not f then return false end
    local alive = 0
    local found = {}
    for line in f:lines() do
        local k, v = line:match("^([%w_]+)=(.*)$")
        if k == "alive" then alive = tonumber(v) or 0 end
        if k == "track" then table.insert(found, v) end
    end
    f:close()
    local companionAlive = (os.time() - alive) < 8
    if companionAlive then tracks = found end
    return companionAlive
end

local function startCompanion()
    local base = resolveBasePath()
    if not base then return end
    local now = os.time()
    if now - lastCompanionStart < 15 then return end
    lastCompanionStart = now
    local script = (base .. "companion/boombox_companion.ps1"):gsub("/", "\\")
    log("Starting audio companion...")
    os.execute(string.format(
        'start "" /min powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%s"',
        script))
end

local function ensureCompanion()
    if readCompanion() then return true end
    if AUTO_START then startCompanion() end
    return false
end

local function readKeyValueFile(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local values = {}
    for line in f:lines() do
        local k, v = line:match("^([%w_]+)=(.*)$")
        if k then values[k] = v end
    end
    f:close()
    return values
end

local function hasTrack(name)
    for _, t in ipairs(tracks) do
        if t == name then return true end
    end
    return false
end

local function loadSavedVolume()
    local base = resolveBasePath()
    if not base then return end
    local f = io.open(base .. "ipc/volume.txt", "r")
    if not f then return end
    local saved = tonumber(f:read("*l"))
    f:close()
    if saved then masterVolume = clamp(saved, 0.0, 2.0) end
end

local function saveVolume()
    local base = resolveBasePath()
    if not base then return end
    local f = io.open(base .. "ipc/volume.txt", "w")
    if f then
        f:write(string.format("%.2f", masterVolume))
        f:close()
    end
end

-- ---------------------------------------------------------------------------
-- Game queries
-- ---------------------------------------------------------------------------

local function getPawn()
    local pc = UEHelpers.GetPlayerController()
    if not pc or not pc:IsValid() then return nil end
    local pawn = tryGet(function() return pc.Pawn end)
    if pawn and pawn:IsValid() then return pawn, pc end
    return nil
end

local function hasBoomboxItem(pawn)
    if not REQUIRE_ITEM then return true end
    local ok, count = pcall(function()
        local PalUtility = StaticFindObject("/Script/Pal.Default__PalUtility")
        local inv = PalUtility:GetLocalInventoryData(pawn)
        if inv and inv:IsValid() then
            return inv:CountItemNum(FName(ITEM_ID))
        end
        return nil
    end)
    if ok and count ~= nil then return count > 0 end
    log("Could not check inventory for the Boombox item, allowing anyway")
    return true
end

local function getListenerYaw(pawn, pc)
    local yaw = tryGet(function()
        return pc.PlayerCameraManager:GetCameraRotation().Yaw
    end)
    if yaw == nil then
        yaw = tryGet(function() return pawn:K2_GetActorRotation().Yaw end)
    end
    return yaw or 0.0
end

local function prettyTrackName(file)
    local name = file:gsub("%.%w+$", ""):gsub("_", " ")
    return (name:gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
end

local function encodeField(value)
    return (tostring(value):gsub("([^%w%._%-])", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local function decodeField(value)
    return (value:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

-- ---------------------------------------------------------------------------
-- Playback control (drives the local companion)
-- ---------------------------------------------------------------------------

local function spatialTick()
    local a = active
    if not a then return true end -- stops the loop

    local pawn, pc = getPawn()
    if not pawn then return false end

    local loc = tryGet(function() return pawn:K2_GetActorLocation() end)
    if not loc then return false end

    local dx = a.x - loc.X
    local dy = a.y - loc.Y
    local dz = a.z - loc.Z
    local dist = math.sqrt(dx * dx + dy * dy + dz * dz)

    local volume = 0.0
    if dist < MAX_DIST then
        volume = masterVolume / (1.0 + (dist / REF_DIST) ^ 2)
        volume = volume * (1.0 - dist / MAX_DIST) ^ 0.3
    end

    local balance = 0.0
    if dist > 50 then
        local yaw = getListenerYaw(pawn, pc)
        local rel = math.rad(math.deg(math.atan(dy, dx)) - yaw)
        balance = math.sin(rel) * PAN_STRENGTH
        volume = volume * (0.85 + 0.15 * math.cos(rel))
    end

    writeState({
        playing = 1,
        track = a.track,
        volume = string.format("%.3f", volume),
        balance = string.format("%.3f", balance),
        seek = pendingSeek,
        seekseq = seekSeq,
    })
    return false
end

local function startPlayback(entry)
    active = entry
    pendingSeek = math.max(0, os.time() - (entry.epoch or os.time()))
    seekSeq = seekSeq + 1
    ensureCompanion()
    if not loopRunning then
        loopRunning = true
        LoopAsync(100, function()
            local stop = spatialTick()
            if stop then loopRunning = false end
            return stop
        end)
    end
end

local function stopPlayback()
    active = nil
    writeState({ playing = 0 })
end

-- ---------------------------------------------------------------------------
-- Chat telegrams (multiplayer sync)
-- ---------------------------------------------------------------------------

local function sendTelegram(body)
    if not SHARE then return end
    local msg = string.format("%s %s %s", TAG, TOKEN, body)
    local _, pc = getPawn()
    if not pc then return end
    local sent = pcall(function()
        -- EPalChatCategory::Global = 1
        pc.PlayerState:EnterChat(FText(msg), 1)
    end)
    if not sent then
        log("Could not send sync telegram (chat API unavailable) - boombox stays local")
    end
end

local function handleTelegram(sender, text)
    local token, body = text:match("^%[BBX%]%s+([%w_]+)%s+(.*)$")
    if not token then return end
    if token == TOKEN then return end -- our own echo

    local pawn = getPawn()

    local x, y, z, encodedTrack, epoch, markerMode =
        body:match("^P (%-?%d+) (%-?%d+) (%-?%d+) (%S+) (%d+) ([RLN])$")
    if x then
        local track = decodeField(encodedTrack)
        log(string.format("Sync: %s placed a boombox (%s)", sender or "?", track))
        readCompanion()
        local incomingEpoch = tonumber(epoch) or 0
        if active then
            local currentEpoch = tonumber(active.epoch) or 0
            local incomingWins = incomingEpoch > currentEpoch
                or (incomingEpoch == currentEpoch
                    and tostring(token) > tostring(active.token or ""))
            if not incomingWins then
                log("Ignoring an older boombox sync event")
                return
            end
        end
        if not hasTrack(track) then
            if pawn then
                announce(pawn, string.format(
                    "%s is playing '%s' but you don't have that file in PalBoombox\\music!",
                    sender or "Someone", prettyTrackName(track)))
            end
            return
        end
        startPlayback({
            x = tonumber(x), y = tonumber(y), z = tonumber(z),
            track = track, epoch = tonumber(epoch), own = false, token = token,
        })
        if pawn then
            announce(pawn, string.format("%s cranks up the boombox: %s",
                sender or "Someone", prettyTrackName(track)))
        end
        return
    end

    if body == "S" then
        log(string.format("Sync: %s stopped the boombox", sender or "?"))
        if active and not active.own and active.token == token then
            stopPlayback()
            if pawn then announce(pawn, "The boombox falls silent.") end
        end
        return
    end
end

-- Fires on every machine: on the host when the server broadcasts, and on
-- clients when the multicast arrives.
local chatHookOk = pcall(function()
    RegisterHook("/Script/Pal.PalGameStateInGame:BroadcastChatMessage", function(self, ChatMessage)
        local ok, err = pcall(function()
            local msg = ChatMessage:get()
            local text = msg.Message:ToString()
            if text:sub(1, #TAG) == TAG then
                local sender = tryGet(function() return msg.Sender:ToString() end)
                ExecuteInGameThread(function()
                    handleTelegram(sender, text)
                end)
            end
        end)
        if not ok then log("Chat hook error: " .. tostring(err)) end
    end)
end)
if chatHookOk then
    log("Chat sync hook installed")
else
    log("WARNING: could not hook chat - multiplayer sync disabled on this machine")
end

-- ---------------------------------------------------------------------------
-- Key handlers
-- ---------------------------------------------------------------------------

local function toggleBoombox()
    local pawn = getPawn()
    if not pawn then
        log("No player pawn found (not in game yet?)")
        return
    end

    if active and active.own then
        stopPlayback()
        sendTelegram("S")
        announce(pawn, "Boombox picked up. The sea falls silent.")
        return
    end

    if not hasBoomboxItem(pawn) then
        announce(pawn, "You need a Boombox in your inventory to set one down!")
        return
    end

    ensureCompanion()
    if #tracks == 0 then readCompanion() end
    if #tracks == 0 then
        if not warnedNoCompanion then
            warnedNoCompanion = true
            announce(pawn, "Boombox: audio companion is starting, try again in a few seconds...")
        else
            announce(pawn, "Boombox: no tracks found (is the companion running and the music folder populated?)")
        end
        return
    end

    local loc = tryGet(function() return pawn:K2_GetActorLocation() end)
    if not loc then return end

    if trackIndex > #tracks then trackIndex = 1 end
    local track = tracks[trackIndex]
    local epoch = math.max(os.time(), active and (tonumber(active.epoch) or 0) + 1 or 0)

    startPlayback({
        x = loc.X, y = loc.Y, z = loc.Z, track = track,
        epoch = epoch, own = true, token = TOKEN,
    })
    log("Placement: local spatial playback started")
    sendTelegram(string.format("P %d %d %d %s %d %s",
        math.floor(loc.X), math.floor(loc.Y), math.floor(loc.Z),
        encodeField(track), epoch, "N"))
    log("Placement: multiplayer sync event sent")

    announce(pawn, string.format("Boombox set down - now playing: %s", prettyTrackName(track)))
end

local function nextTrack()
    readCompanion()
    if #tracks == 0 then
        log("No tracks available yet")
        return
    end
    trackIndex = (trackIndex % #tracks) + 1
    local pawn = getPawn()

    if active and active.own then
        -- Re-place in spirit: same spot, new track, fresh epoch, tell everyone.
        active.track = tracks[trackIndex]
        active.epoch = math.max(os.time(), (tonumber(active.epoch) or 0) + 1)
        pendingSeek = 0
        seekSeq = seekSeq + 1
        sendTelegram(string.format("P %d %d %d %s %d %s",
            math.floor(active.x), math.floor(active.y), math.floor(active.z),
            encodeField(active.track), active.epoch, "N"))
        if pawn then
            announce(pawn, "Now playing: " .. prettyTrackName(active.track))
        end
    else
        if pawn then
            announce(pawn, "Next up: " .. prettyTrackName(tracks[trackIndex]))
        end
    end
end

local function addMusic()
    local pawn = getPawn()
    if not pawn then
        log("No player pawn found (not in game yet?)")
        return
    end
    if importPending then
        announce(pawn, "The music picker is already open.")
        return
    end

    local base = resolveBasePath()
    if not base then
        announce(pawn, "Could not find the PalBoombox folder.")
        return
    end

    local requestId = string.format("%s_%d", TOKEN, math.floor(os.clock() * 1000))
    local resultPath = base .. "ipc/import_result.txt"
    local script = (base .. "companion/import_music.ps1"):gsub("/", "\\")
    os.remove(resultPath)
    importPending = true
    ensureCompanion()

    os.execute(string.format(
        'start "" powershell -STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%s" -RequestId "%s"',
        script, requestId))
    announce(pawn, "Music picker opened - select one or more MP3, WAV, or WMA files.")

    local waitedMs = 0
    LoopAsync(250, function()
        waitedMs = waitedMs + 250
        local result = readKeyValueFile(resultPath)
        if result and result.request == requestId then
            importPending = false
            os.remove(resultPath)
            ExecuteInGameThread(function()
                if result.status == "imported" then
                    -- The companion refreshes its advertised track list every
                    -- two seconds, so wait for that heartbeat before reading it.
                    ExecuteWithDelay(2250, function()
                        readCompanion()
                        ExecuteInGameThread(function()
                            local currentPawn = getPawn()
                            if currentPawn then
                                announce(currentPawn, string.format(
                                    "Added %d track(s) to the boombox. Press %s to choose one.",
                                    tonumber(result.count) or 0, NEXT_KEY))
                            end
                        end)
                    end)
                elseif result.status == "cancelled" then
                    announce(pawn, "Music import cancelled.")
                elseif result.status == "unchanged" then
                    announce(pawn, "That music is already in the boombox folder.")
                else
                    announce(pawn, "Could not import music: " .. (result.message or "unknown error"))
                end
            end)
            return true
        end
        if waitedMs >= 300000 then
            importPending = false
            ExecuteInGameThread(function()
                local currentPawn = getPawn()
                if currentPawn then announce(currentPawn, "Music picker timed out.") end
            end)
            return true
        end
        return false
    end)
end

local function cleanKeyArg(value)
    return tostring(value):gsub('["\r\n]', "")
end

local function openControlPanel()
    local base = resolveBasePath()
    local pawn = getPawn()
    if not base then
        if pawn then announce(pawn, "Could not find the Pal Tools control panel.") end
        return
    end
    local script = (base .. "companion/control_panel.ps1"):gsub("/", "\\")
    os.execute(string.format(
        'start "" powershell -STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%s" -WhipKey "%s" -PlaceKey "%s" -NextKey "%s" -AddMusicKey "%s"',
        script, cleanKeyArg("F7"), cleanKeyArg(PLACE_KEY),
        cleanKeyArg(NEXT_KEY), cleanKeyArg(ADD_MUSIC_KEY)))
end

local function changeVolume(delta)
    local previousVolume = masterVolume
    masterVolume = clamp(masterVolume + delta, 0.0, 2.0)
    if math.abs(masterVolume - previousVolume) < 0.001 then
        local pawn = getPawn()
        if pawn then
            local limit = delta > 0 and "maximum" or "minimum"
            announce(pawn, string.format("Boombox listening volume is already at %s (%d%%).",
                limit, math.floor(masterVolume * 100 + 0.5)))
        end
        return
    end
    saveVolume()
    local pawn = getPawn()
    if pawn then
        announce(pawn, string.format("Boombox listening volume: %d%%",
            math.floor(masterVolume * 100 + 0.5)))
    end
end

local function startControlPanelCommands()
    local base = resolveBasePath()
    if not base then return end
    local commandPath = base .. "ipc/menu_command.txt"
    local initial = readKeyValueFile(commandPath)
    local lastSeq = initial and initial.seq or nil

    LoopAsync(150, function()
        local message = readKeyValueFile(commandPath)
        if message and message.seq and message.seq ~= lastSeq then
            lastSeq = message.seq
            ExecuteInGameThread(function()
                if message.command == "boombox_toggle" then
                    toggleBoombox()
                elseif message.command == "boombox_next" then
                    nextTrack()
                elseif message.command == "music_add" then
                    addMusic()
                elseif message.command == "volume_down" then
                    changeVolume(-0.1)
                elseif message.command == "volume_up" then
                    changeVolume(0.1)
                end
            end)
        end
        return false
    end)
end

local function scheduleWelcomeHint()
    if not SHOW_WELCOME then return end
    local base = resolveBasePath()
    if not base then return end
    local seenPath = base .. "ipc/welcome_seen.txt"
    local seen = io.open(seenPath, "r")
    if seen then seen:close(); return end

    LoopAsync(1000, function()
        local pawn = getPawn()
        if not pawn then return false end
        local f = io.open(seenPath, "w")
        if f then f:write("1"); f:close() end
        ExecuteInGameThread(function()
            local currentPawn = getPawn()
            if currentPawn then
                announce(currentPawn, string.format(
                    "Pal Tools ready! Press %s for Whip and Boombox controls.", MENU_KEY))
            end
        end)
        return true
    end)
end

-- ---------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------

local function bind(keyName, fallback, fn)
    local key = Key[keyName]
    if key == nil then
        log(string.format("Unknown key '%s', falling back to %s", tostring(keyName), fallback))
        key = Key[fallback]
    end
    RegisterKeyBind(key, {}, function()
        ExecuteInGameThread(fn)
    end)
end

bind(PLACE_KEY, "F9", toggleBoombox)
bind(NEXT_KEY, "F10", nextTrack)
bind(ADD_MUSIC_KEY, "F11", addMusic)
bind(MENU_KEY, "F6", openControlPanel)

loadSavedVolume()
startControlPanelCommands()
scheduleWelcomeHint()

writeState({ playing = 0 })

log(string.format("Loaded. %s opens Pal Tools; %s places/picks up, %s switches tracks, %s adds music. Sync: %s, marker: disabled.",
    MENU_KEY, PLACE_KEY, NEXT_KEY, ADD_MUSIC_KEY, tostring(SHARE)))
