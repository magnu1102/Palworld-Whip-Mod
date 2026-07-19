-- PalWhip - crack the whip and get your base pals back to work.
-- Cures sickness (Depression, Ulcer, Sprain, Fracture, Weakness, Cold...),
-- restores sanity, and optionally heals HP / hunger for all of your pals
-- around you when you press the whip key.
--
-- UE4SS Lua mod. Runs on the host / single player.

local UEHelpers = require("UEHelpers")

local ok_cfg, config = pcall(require, "config")
if not ok_cfg or type(config) ~= "table" then
    config = {}
end

-- Defaults in case config.lua is missing or partially edited.
local WHIP_KEY      = config.WhipKey       or "F7"
local RANGE         = math.max(0.0, tonumber(config.Range) or 9000.0)
local OWNED_ONLY    = (config.OwnedOnly    ~= false)
local CURE_SICKNESS = (config.CureSickness ~= false)
local RESTORE_SAN   = (config.RestoreSanity ~= false)
local HEAL_HP       = (config.HealHP       ~= false)
local FILL_STOMACH  = (config.FillStomach  == true)
local COOLDOWN      = math.max(0.0, tonumber(config.Cooldown) or 1.0)
local ANNOUNCE      = (config.Announce     ~= false)
-- "equipped": whip must be in your hands | "inventory": just carried | "none": no item needed
local ITEM_REQUIREMENT = config.ItemRequirement or "equipped"
if config.RequireWhipItem == false then ITEM_REQUIREMENT = "none" end
local WHIP_ITEM_ID  = config.WhipItemId    or "PalWhip"
local PLAY_SOUND    = (config.PlaySound    ~= false)
local SOUND_ID      = config.SoundID       or ""
local SOUND_EVENT   = config.SoundEventName or ""
local SOUND_PATTERNS = config.SoundEventPatterns or { "whip", "attack_hit", "melee", "swing", "decide" }
if type(SOUND_PATTERNS) ~= "table" then
    SOUND_PATTERNS = { "whip", "attack_hit", "melee", "swing", "decide" }
end
local SOUND_DUMP_KEY = config.SoundDumpKey or "F8"

local DEBUG         = (config.Debug        == true)
local DEBUG_LOGGING = (config.DebugLogging == true)

local lastCrack = 0.0
local cachedSoundEvent = nil
local warnedNoSound = false

local function log(msg)
    if DEBUG_LOGGING then
        print(string.format("[PalWhip] %s\n", tostring(msg)))
    end
end

-- Safe field read: returns nil instead of erroring when a property is missing.
local function tryGet(fn)
    local ok, value = pcall(fn)
    if ok then return value end
    return nil
end

local function guidIsZero(guid)
    if guid == nil then return true end
    local a = tryGet(function() return guid.A end)
    local b = tryGet(function() return guid.B end)
    local c = tryGet(function() return guid.C end)
    local d = tryGet(function() return guid.D end)
    return (a or 0) == 0 and (b or 0) == 0 and (c or 0) == 0 and (d or 0) == 0
end

local function announce(context, text)
    if not ANNOUNCE then return end
    pcall(function()
        local PalUtility = StaticFindObject("/Script/Pal.Default__PalUtility")
        if PalUtility and PalUtility:IsValid() then
            -- Plain Lua strings auto-convert to FString; fall back to FText
            -- in case the signature differs on this game version.
            local ok = pcall(function() PalUtility:SendSystemAnnounce(context, text) end)
            if not ok then
                PalUtility:SendSystemAnnounce(context, FText(text))
            end
        end
    end)
end

-- Returns true/false, or nil if the equipped-weapon API is unavailable.
local function isWhipEquipped(pawn)
    local ok, result = pcall(function()
        local shooter = pawn.ShooterComponent
        if not shooter or not shooter:IsValid() then return nil end
        local weapon = shooter:GetHasWeapon()
        if not weapon or not weapon:IsValid() then return false end
        return weapon.ownItemID.StaticId:ToString() == WHIP_ITEM_ID
    end)
    if ok then return result end
    return nil
end

-- Returns true/false, or nil if the inventory API is unavailable.
local function isWhipInInventory(pawn)
    local ok, count = pcall(function()
        local PalUtility = StaticFindObject("/Script/Pal.Default__PalUtility")
        local inv = PalUtility:GetLocalInventoryData(pawn)
        if inv and inv:IsValid() then
            return inv:CountItemNum(FName(WHIP_ITEM_ID))
        end
        return nil
    end)
    if ok and count ~= nil then return count > 0 end
    return nil
end

-- Applies the ItemRequirement gate. Returns true (whip allowed) or
-- false plus a message for the player.
local function whipGatePassed(pawn)
    if ITEM_REQUIREMENT == "none" then return true end

    if ITEM_REQUIREMENT == "equipped" then
        local equipped = isWhipEquipped(pawn)
        if equipped == true then return true end
        if equipped == false then
            return false, "Equip your Pal Whip first, then crack it!"
        end
        -- API unavailable: degrade to the inventory check.
        log("Equipped-weapon check unavailable, falling back to inventory check")
    end

    local carried = isWhipInInventory(pawn)
    if carried == false then
        return false, "You need a Pal Whip in your inventory to crack the whip!"
    end
    if carried == nil then
        -- Both checks unavailable (API renamed by a patch, or the
        -- PalSchema item is missing): don't lock the player out.
        log("Could not check for the whip item, allowing whip anyway")
    end
    return true
end

-- Finds a loaded Wwise sound event matching SoundEventName / SoundEventPatterns.
local function findSoundEvent()
    if cachedSoundEvent and cachedSoundEvent:IsValid() then
        return cachedSoundEvent
    end
    cachedSoundEvent = nil
    local ok, events = pcall(function() return FindAllOf("AkAudioEvent") end)
    if not ok or not events then return nil end

    local wanted = string.lower(SOUND_EVENT)
    for _, pattern in ipairs(wanted ~= "" and { wanted } or SOUND_PATTERNS) do
        pattern = string.lower(pattern)
        for _, ev in ipairs(events) do
            if ev and ev:IsValid() then
                local name = string.lower(ev:GetFName():ToString())
                if (wanted ~= "" and name == pattern) or (wanted == "" and string.find(name, pattern, 1, true)) then
                    cachedSoundEvent = ev
                    log(string.format("Using sound event '%s'", ev:GetFName():ToString()))
                    return ev
                end
            end
        end
    end
    return nil
end

local function playCrackSound(pawn)
    if not PLAY_SOUND then return end
    local PalSound = StaticFindObject("/Script/Pal.Default__PalSoundUtility")
    if not PalSound or not PalSound:IsValid() then return end

    -- 1) Explicit SoundID row from DT_SoundID, if configured.
    if SOUND_ID ~= "" then
        local ok = pcall(function()
            PalSound:PlaySoundByActor(pawn, { Key = FName(SOUND_ID) }, { FadeInTime = 0 })
        end)
        if ok then return end
        log(string.format("PlaySoundByActor failed for SoundID '%s', trying sound events", SOUND_ID))
    end

    -- 2) Loaded Wwise event by name/pattern.
    local ev = findSoundEvent()
    if ev then
        local ok = pcall(function() PalSound:PlayAkEventSoundByActor(pawn, ev) end)
        if not ok then
            cachedSoundEvent = nil
            log("PlayAkEventSoundByActor failed for the selected event")
        end
    elseif not warnedNoSound then
        warnedNoSound = true
        log(string.format("No sound event matched (press %s to list available events, then set SoundEventName in config.lua)", SOUND_DUMP_KEY))
    end
end

local function dumpSoundEvents()
    local ok, events = pcall(function() return FindAllOf("AkAudioEvent") end)
    if not ok or not events then
        log("No AkAudioEvent objects loaded yet - enter a world first")
        return
    end
    local names = {}
    for _, ev in ipairs(events) do
        if ev and ev:IsValid() then
            table.insert(names, ev:GetFName():ToString())
        end
    end
    table.sort(names)
    log(string.format("---- %d loaded sound events ----", #names))
    for _, name in ipairs(names) do
        print(string.format("[PalWhip]   %s\n", name))
    end
    log("Set SoundEventName in config.lua to one of the names above")
end

-- Returns the individual character parameter object for a pal actor, or nil.
local function getParam(pal)
    return tryGet(function()
        local comp = pal.CharacterParameterComponent
        if comp and comp:IsValid() then
            local param = comp.IndividualParameter
            if param and param:IsValid() then
                return param
            end
        end
        return nil
    end)
end

-- Applies the whip to one pal. Returns true if anything was fixed.
local function whipPal(param)
    local touched = false
    local save = tryGet(function() return param.SaveParameter end)
    if save == nil then return false end

    if CURE_SICKNESS then
        local sick = tryGet(function() return save.WorkerSick end)
        if sick ~= nil and sick ~= 0 then
            pcall(function() save.WorkerSick = 0 end) -- EPalBaseCampWorkerSickType::None
            touched = true
        end
    end

    if RESTORE_SAN then
        local san = tryGet(function() return save.SanityValue end)
        if san ~= nil and san < 100.0 then
            -- Prefer the game's setter so runtime state stays consistent,
            -- fall back to writing the save field directly.
            local usedSetter = pcall(function() param:SetSanityValue(100.0) end)
            if not usedSetter then
                pcall(function() save.SanityValue = 100.0 end)
            end
            touched = true
        end
    end

    if HEAL_HP then
        pcall(function()
            local maxHp = param:GetMaxHP()
            if save.HP.Value < maxHp.Value then
                save.HP.Value = maxHp.Value
                touched = true
            end
        end)
    end

    if FILL_STOMACH then
        pcall(function()
            local maxStomach = save.MaxFullStomach
            if maxStomach and maxStomach > 0 and save.FullStomach < maxStomach then
                save.FullStomach = maxStomach
                touched = true
            end
        end)
    end

    return touched
end

local function crackWhip()
    local now = os.clock()
    if now - lastCrack < COOLDOWN then return end
    lastCrack = now

    local pc = UEHelpers.GetPlayerController()
    if not pc or not pc:IsValid() then
        log("No player controller found (not in game yet?)")
        return
    end
    local pawn = tryGet(function() return pc.Pawn end)
    if not pawn or not pawn:IsValid() then
        log("No player pawn found")
        return
    end

    local gateOk, gateMsg = whipGatePassed(pawn)
    if not gateOk then
        announce(pawn, gateMsg)
        return
    end

    playCrackSound(pawn)

    local ploc = tryGet(function() return pawn:K2_GetActorLocation() end)
    local rangeSq = RANGE > 0 and (RANGE * RANGE) or nil

    local pals = tryGet(function() return FindAllOf("PalCharacter") end) or {}
    local cured, seen = 0, 0

    for _, pal in ipairs(pals) do
        if pal and pal:IsValid() and pal ~= pawn then
            local param = getParam(pal)
            if param then
                local save = tryGet(function() return param.SaveParameter end)
                local isPlayer = save and tryGet(function() return save.IsPlayer end)
                if save and isPlayer ~= true then
                    -- Ownership filter: skip wild pals unless configured otherwise.
                    local ownedOk = true
                    if OWNED_ONLY then
                        local owner = tryGet(function() return save.OwnerPlayerUId end)
                        ownedOk = not guidIsZero(owner)
                    end

                    -- Range filter.
                    local rangeOk = true
                    if rangeSq and ploc then
                        local loc = tryGet(function() return pal:K2_GetActorLocation() end)
                        if loc then
                            local dx, dy, dz = loc.X - ploc.X, loc.Y - ploc.Y, loc.Z - ploc.Z
                            rangeOk = (dx * dx + dy * dy + dz * dz) <= rangeSq
                        end
                    end

                    if ownedOk and rangeOk then
                        seen = seen + 1
                        if DEBUG and seen <= 40 then
                            local save2 = tryGet(function() return param.SaveParameter end)
                            local cid   = tryGet(function() return save2.CharacterID:ToString() end) or "?"
                            local san   = tryGet(function() return save2.SanityValue end)
                            local sick  = tryGet(function() return save2.WorkerSick end)
                            local hp    = tryGet(function() return save2.HP.Value end)
                            local maxhp = tryGet(function() return param:GetMaxHP().Value end)
                            local food  = tryGet(function() return save2.FullStomach end)
                            local mfood = tryGet(function() return save2.MaxFullStomach end)
                            local phys  = tryGet(function() return save2.PhysicalHealth end)
                            log(string.format(
                                "PAL %-24s san=%-8s sick=%-6s phys=%-6s hp=%s/%s food=%s/%s",
                                cid, tostring(san), tostring(sick), tostring(phys),
                                tostring(hp), tostring(maxhp),
                                food and string.format("%.0f", food) or "nil",
                                mfood and string.format("%.0f", mfood) or "nil"))
                        end
                        if whipPal(param) then
                            cured = cured + 1
                        end
                    end
                end
            end
        end
    end

    if cured > 0 then
        announce(pawn, string.format("*CRACK* %d pal(s) snapped back to normal. Back to work!", cured))
    else
        announce(pawn, string.format("*CRACK* %d pal(s) in range - all already working hard.", seen))
    end
end

-- Register the whip key.
local keyEnum = Key[WHIP_KEY]
if keyEnum == nil then
    log(string.format("Unknown key '%s' in config.lua, falling back to F7", tostring(WHIP_KEY)))
    keyEnum = Key.F7
    WHIP_KEY = "F7"
end

RegisterKeyBind(keyEnum, {}, function()
    ExecuteInGameThread(crackWhip)
end)

if SOUND_DUMP_KEY ~= "" and Key[SOUND_DUMP_KEY] then
    RegisterKeyBind(Key[SOUND_DUMP_KEY], {}, function()
        ExecuteInGameThread(dumpSoundEvents)
    end)
end

log(string.format("Loaded. Press %s to crack the whip (range %.0f, owned-only: %s, item requirement: %s).",
    WHIP_KEY, RANGE, tostring(OWNED_ONLY), ITEM_REQUIREMENT))
