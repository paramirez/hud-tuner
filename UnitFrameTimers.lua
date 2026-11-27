local _, addon = ...
local L = addon.L
local timers = {}
addon.UnitTimers = timers

local isSecret = issecretvalue or function() return false end
local castColor = { 0x18 / 255, 0x85 / 255, 0x9B / 255 }
local channelColor = { 0x32 / 255, 0x85 / 255, 0x68 / 255 }
local swingColor = { 0x76 / 255, 0x58 / 255, 0xAD / 255 }
local spellEvents = {
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
}

local function CastTick(bar)
    local now = GetTime() * 1000
    bar:SetValue(now)
    if not isSecret(bar.ends) and now >= bar.ends then
        bar:Hide()
        return
    end
    if not isSecret(bar.ends) then
        bar.percent:SetFormattedText("%.1f s", (bar.ends - now) / 1000)
    elseif bar.duration then
        local ok, remaining = pcall(bar.duration.GetRemainingDuration, bar.duration)
        if ok and type(remaining) == "number" then
            bar.percent:SetFormattedText("%.1f s", remaining)
        else
            bar.duration = nil
        end
    end
end

local function SwingTick(bar)
    if UnitCanAttack then
        local attackable = UnitCanAttack("player", "target")
        if not isSecret(attackable) and not attackable then
            bar:Hide()
            return
        end
    end
    local remaining = bar.interval - (GetTime() - bar.started) % bar.interval
    bar:SetValue(remaining)
    bar.percent:SetFormattedText("~%.1f s", remaining)
end

function timers.Build(frame, addBar, layout)
    frame.castBar = addBar(frame)
    frame.swingBar = addBar(frame)
    frame.castBar:Hide()
    frame.swingBar:Hide()
    frame.swingBar:SetStatusBarColor(unpack(swingColor))
    frame.swingBar.amount:SetText(L.UnitFrameSwingLabel)
    local cast = frame.castBar
    cast.channelFill = cast:CreateTexture(nil, "ARTWORK")
    cast.channelFill:SetColorTexture(unpack(channelColor))
    cast.channelFill:SetPoint("TOPLEFT")
    cast.channelFill:SetPoint("BOTTOMRIGHT", cast:GetStatusBarTexture(), "BOTTOMLEFT")
    cast.channelFill:Hide()
    for _, bar in ipairs({ frame.castBar, frame.swingBar }) do
        bar:HookScript("OnShow", function() layout(frame) end)
        bar:HookScript("OnHide", function() layout(frame) end)
        bar.amount:SetPoint("RIGHT", bar.percent, "LEFT", -6, 0)
        bar.amount:SetJustifyH("LEFT")
    end
end

function timers.Register(listener, unit)
    for _, event in ipairs(spellEvents) do listener:RegisterUnitEvent(event, unit) end
    if unit == "player" then
        listener:RegisterEvent("PLAYER_ENTER_COMBAT")
        listener:RegisterEvent("PLAYER_LEAVE_COMBAT")
        listener:RegisterEvent("PLAYER_REGEN_ENABLED")
        listener:RegisterEvent("PLAYER_TARGET_CHANGED")
        listener:RegisterUnitEvent("UNIT_ATTACK_SPEED", "player")
    end
end

local function RefreshCast(frame)
    local bar, unit = frame.castBar, frame.unit
    if not frame.options.casts then bar:Hide(); return end
    local name, label, _, starts, ends = UnitCastingInfo(unit)
    local channel = type(name) == "nil"
    if channel then name, label, _, starts, ends = UnitChannelInfo(unit) end
    if type(name) == "nil" or type(starts) ~= "number" or type(ends) ~= "number" then
        bar:Hide()
        return
    end
    bar.ends = ends
    bar.duration = nil
    if isSecret(ends) then
        local getDuration = channel and UnitChannelDuration or UnitCastingDuration
        if getDuration then
            local ok, duration = pcall(getDuration, unit)
            if ok then bar.duration = duration end
        end
    end
    bar:SetMinMaxValues(starts, ends)
    bar:SetReverseFill(channel)
    bar.channelFill:SetShown(channel)
    if channel then bar:SetStatusBarColor(0, 0, 0, 0)
    else bar:SetStatusBarColor(unpack(castColor)) end
    if type(label) == "nil" then label = name end
    bar.amount:SetText(label)
    bar.percent:SetText("")
    bar:SetScript("OnUpdate", CastTick)
    bar:Show()
    CastTick(bar)
end

local function RefreshSwing(frame, event)
    local bar = frame.swingBar
    if event == "PLAYER_LEAVE_COMBAT" or event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_ENTERING_WORLD" then
        bar.started = nil
    elseif event == "PLAYER_ENTER_COMBAT" then
        bar.started = GetTime()
        bar.interval = nil
    end
    if not frame.options.swings or not bar.started then bar:Hide(); return end
    local speed = UnitAttackSpeed("player")
    if isSecret(speed) or type(speed) ~= "number" or speed <= 0 then bar:Hide(); return end
    if speed ~= bar.interval then
        local now = GetTime()
        if bar.interval then
            local progress = ((now - bar.started) % bar.interval) / bar.interval
            bar.started = now - progress * speed
        end
        bar.interval = speed
        bar:SetMinMaxValues(0, speed)
    end
    bar:SetScript("OnUpdate", SwingTick)
    bar:Show()
    SwingTick(bar)
end

function timers.Update(frame, event, full)
    if full or (event and event:find("^UNIT_SPELLCAST_")) then RefreshCast(frame) end
    if frame.unit == "player" and (full or event == "UNIT_ATTACK_SPEED"
        or event == "PLAYER_ENTER_COMBAT" or event == "PLAYER_LEAVE_COMBAT" or event == "PLAYER_REGEN_ENABLED") then
        RefreshSwing(frame, event)
    end
end

function timers.Stop(frame)
    frame.castBar:Hide()
    frame.swingBar:Hide()
    frame.swingBar.started = nil
end

function timers.Preview(frame)
    local cast, swing = frame.castBar, frame.swingBar
    cast:SetStatusBarColor(unpack(castColor))
    cast:SetMinMaxValues(0, 1)
    cast:SetValue(0.62)
    cast.amount:SetText(L.UnitFrameCastLabel)
    cast.percent:SetText("0.8 s")
    cast:SetShown(frame.options.casts)
    swing:SetMinMaxValues(0, 1)
    swing:SetValue(0.45)
    swing.percent:SetText("~1.2 s")
    swing:SetShown(frame.unit == "player" and frame.options.swings)
end
