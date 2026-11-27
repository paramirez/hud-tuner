local _, addon = ...
local L = addon.L
local module = { units = { "player", "target" } }
addon.UnitFrames = module

local frames = {}
local alphaDuringPreview = {}
local curve
local healthColorCurve
local numberFont = "Fonts\\ARIALN.TTF"
local isSecret = issecretvalue or function() return false end
local events = {
    "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER",
    "UNIT_DISPLAYPOWER", "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_CLASSIFICATION_CHANGED", "UNIT_FACTION",
}
local classificationLabels = {
    rare = L.UnitFrameRare, elite = L.UnitFrameElite,
    rareelite = L.UnitFrameRareElite, worldboss = L.UnitFrameBoss,
}
local settings = {
    player = { enabled = "showMinimalPlayerFrame", x = "minimalPlayerX", y = "minimalPlayerY", offset = -172 },
    target = { enabled = "showMinimalTargetFrame", x = "minimalTargetX", y = "minimalTargetY", offset = 172 },
}
local defaults = { colorMode = "auto", fixedColor = "287C85", health = true, power = true,
    amounts = true, percents = true, identity = true, casts = false, swings = false }
local classicPowerColors = {
    MANA = { 0, 0, 1 }, RAGE = { 1, 0, 0 }, FOCUS = { 1, 0.5, 0.25 },
    ENERGY = { 1, 1, 0 }, HAPPINESS = { 1, 0.41, 0.96 },
}

local function RGB(hex)
    return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5), 16) / 255
end

local healthColors = { { RGB("B93B42") }, { RGB("B88524") }, { RGB("2F875E") } }

local function SetHealthPercentageColor(frame, percent)
    if not isSecret(percent) and type(percent) == "number" then
        local progress = math.max(0, math.min(2, percent / 50))
        local lower = math.min(2, math.floor(progress) + 1)
        local from, to = healthColors[lower], healthColors[lower + 1]
        local t = progress - (lower - 1)
        frame.health:SetStatusBarColor(from[1] + (to[1] - from[1]) * t,
            from[2] + (to[2] - from[2]) * t, from[3] + (to[3] - from[3]) * t)
        return
    end

    if C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor and UnitHealthPercent then
        if not healthColorCurve then
            healthColorCurve = C_CurveUtil.CreateColorCurve()
            for index, rgb in ipairs(healthColors) do
                healthColorCurve:AddPoint((index - 1) / 2, CreateColor(rgb[1], rgb[2], rgb[3], 1))
            end
        end
        local color = UnitHealthPercent(frame.unit, true, healthColorCurve)
        if type(color) ~= "nil" then
            frame.health:SetStatusBarColor(color:GetRGB())
            return
        end
    end
    frame.health:SetStatusBarColor(module.FixedColor(frame.db, frame.unit))
end

local function SetFlatColor(bar, r, g, b)
    if isSecret(r) or isSecret(g) or isSecret(b)
        or type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return false end

    local strength = 0.84
    local neutral = 0.30 * (1 - strength)
    bar:SetStatusBarColor(neutral + r * strength, neutral + g * strength, neutral + b * strength)
    return true
end

local function ClassTokenColor(class)
    if isSecret(class) or type(class) ~= "string" then return end
    local color = C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class)
    if color then return color:GetRGB() end
    color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if color then return color.r, color.g, color.b end
end

local function ClassColor(unit)
    local _, class = UnitClass(unit)
    return ClassTokenColor(class)
end

local function ReactionColor(unit)
    if UnitSelectionColor then
        local r, g, b = UnitSelectionColor(unit)
        if not isSecret(r) and not isSecret(g) and not isSecret(b) and type(r) == "number"
            and type(g) == "number" and type(b) == "number" then return r, g, b end
    end
    if not UnitReaction then return end
    local reaction = UnitReaction(unit, "player")
    if isSecret(reaction) or type(reaction) ~= "number" then return end
    if reaction <= 3 then return 1, 0, 0 end
    if reaction == 4 then return 1, 1, 0 end
    return 0, 1, 0
end
local function Dimension(key, default, min, max, auto)
    return { key = key, default = default, min = min, max = max, auto = auto }
end

local function BarDimensions(key, label, defaultHeight, playerOnly)
    return { key = key, label = label, playerOnly = playerOnly, fields = {
        Dimension(key .. "Width", 0, 64, 518, true), Dimension(key .. "Height", defaultHeight, 8, 100),
    } }
end

local barDimensions = {
    BarDimensions("health", L.UnitFrameHealthLabel, 20),
    BarDimensions("power", L.UnitFramePowerLabel, 16),
    BarDimensions("castBar", L.UnitFrameCastLabel, 16),
    BarDimensions("swingBar", L.UnitFrameSwingLabel, 13, true),
}
for _, bar in ipairs(barDimensions) do defaults[bar.key .. "Text"] = "inherit" end
module.dimensionGroups = {
    { title = L.UnitFrameOverallSize, columns = { L.UnitFrameWidth, L.UnitFrameMinHeight }, rows = {
        { fields = { Dimension("width", 232, 100, 520), Dimension("height", 55, 26, 260) } },
    } },
    { title = L.UnitFrameBarSizes, columns = { L.UnitFrameWidth, L.UnitFrameHeight }, rows = barDimensions },
    { title = L.UnitFrameSpacingAndText, rows = {
        { label = L.UnitFrameBarGap, fields = { Dimension("gap", 1, 0, 24) } },
        { label = L.UnitFrameFontSize, fields = { Dimension("fontSize", 12, 8, 22) } },
    } },
}

local dimensionByKey = {}
for _, group in ipairs(module.dimensionGroups) do
    for _, row in ipairs(group.rows) do
        for _, field in ipairs(row.fields) do
            dimensionByKey[field.key] = field
            defaults[field.key] = field.default
        end
    end
end

module.profileSettings = {}
local function OptionKey(unit, property) return "minimal_" .. unit .. "_" .. property end
for _, unit in ipairs(module.units) do
    for property in pairs(defaults) do
        table.insert(module.profileSettings, OptionKey(unit, property))
    end
end

function module.GetOption(db, unit, property)
    local value = db[OptionKey(unit, property)]
    local default = defaults[property]
    if type(value) ~= type(default) then return default end
    local dimension = dimensionByKey[property]
    if dimension then
        if value ~= value or math.abs(value) == math.huge then return default end
        value = math.floor(value + 0.5)
        if dimension.auto and value <= 0 then return 0 end
        return math.max(dimension.min, math.min(dimension.max, value))
    end
    if property == "fixedColor" and not value:match("^%x%x%x%x%x%x$") then return default end
    if property == "colorMode" and value ~= "auto" and value ~= "reaction" and value ~= "fixed" and value ~= "health" then
        return default
    end
    return value
end

function module.SetOption(db, unit, property, value)
    db[OptionKey(unit, property)] = value
end

function module.GetTextMode(db, unit, bar)
    local mode = module.GetOption(db, unit, bar .. "Text")
    if mode == "none" or mode == "amount" or mode == "percent" or mode == "both" then return mode end
    if bar == "castBar" or bar == "swingBar" then return "both" end
    local amount = module.GetOption(db, unit, "amounts")
    local percent = module.GetOption(db, unit, "percents")
    if amount then return percent and "both" or "amount" end
    return percent and "percent" or "none"
end

function module.ResetDimensions(db, unit)
    for property in pairs(dimensionByKey) do db[OptionKey(unit, property)] = nil end
end

function module.FixedColor(db, unit)
    return RGB(module.GetOption(db, unit, "fixedColor"))
end

local function SetHealthColor(frame)
    local mode, unit = frame.options.colorMode, frame.unit
    if mode == "auto" then
        local player = unit == "player" or UnitIsPlayer(unit)
        if not isSecret(player) and player and SetFlatColor(frame.health, ClassColor(unit)) then return end
    end
    if mode ~= "fixed" and SetFlatColor(frame.health, ReactionColor(unit)) then return end
    frame.health:SetStatusBarColor(module.FixedColor(frame.db, unit))
end

local function AddText(parent, size)
    local label = parent:CreateFontString(nil, "OVERLAY")
    label:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
    label:SetTextColor(RGB("EFF2F5"))
    label:SetWordWrap(false)
    return label
end

local function AddBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    local background = bar:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(RGB("171C21"))
    bar.amount, bar.percent = AddText(bar, 12), AddText(bar, 12)
    bar.amount:SetPoint("LEFT", 6, 0)
    bar.percent:SetPoint("RIGHT", -6, 0)
    return bar
end

local function BarTop(options)
    return options.identity and options.fontSize + 5 or 1
end

local function LayoutBars(frame)
    local options = frame.options
    if not options then return end
    local top = BarTop(options)
    for _, spec in ipairs(barDimensions) do
        local bar = frame[spec.key]
        if bar:IsShown() then
            if bar.layoutTop ~= top then
                bar:SetPoint("TOP", frame, "TOP", 0, -top)
                bar.layoutTop = top
            end
            top = top + bar:GetHeight() + options.gap
        end
    end
end

local function ApplyDimensions(frame, options, unit)
    local enabled = { health = options.health, power = options.power, castBar = options.casts,
        swingBar = unit == "player" and options.swings }
    local height = BarTop(options)
    local availableWidth = options.width - 2
    for _, spec in ipairs(barDimensions) do
        local width = options[spec.fields[1].key]
        local barHeight = options[spec.fields[2].key]
        frame[spec.key]:SetSize(width == 0 and availableWidth or math.min(width, availableWidth), barHeight)
        if enabled[spec.key] then height = height + barHeight + options.gap end
    end
    frame:SetSize(options.width, math.max(options.height, height - options.gap + 1))
end

local function BuildAppearance(frame)
    frame.name, frame.info = AddText(frame, 12), AddText(frame, 11)
    frame.info:SetPoint("TOPRIGHT", -3, -1)
    frame.info:SetTextColor(RGB("BCC5CE"))
    frame.name:SetPoint("TOPLEFT", 3, -1)
    frame.name:SetPoint("RIGHT", frame.info, "LEFT", -8, 0)
    frame.name:SetJustifyH("LEFT")
    frame.health = AddBar(frame)
    frame.health:SetStatusBarColor(RGB(defaults.fixedColor))
    frame.power = AddBar(frame)
    addon.UnitTimers.Build(frame, AddBar, LayoutBars)
end

local function ApplyAppearance(frame, db, unit, sampleProperty, sampleCast)
    frame.options = {}
    for property in pairs(defaults) do frame.options[property] = module.GetOption(db, unit, property) end
    if sampleProperty then frame.options[sampleProperty] = true end
    if sampleCast then frame.options.casts = true end
    frame.db, frame.unit = db, unit
    frame.name:SetShown(frame.options.identity)
    frame.info:SetShown(frame.options.identity)
    local options = frame.options
    frame.health:SetShown(options.health)
    ApplyDimensions(frame, options, unit)
    frame.name:SetFont(UNIT_NAME_FONT or STANDARD_TEXT_FONT, options.fontSize, "OUTLINE")
    frame.info:SetFont(STANDARD_TEXT_FONT, options.fontSize - 1, "OUTLINE")
    for _, spec in ipairs(barDimensions) do
        local key = spec.key
        local bar = frame[key]
        local fontSize = math.max(7, math.min(options.fontSize, bar:GetHeight() - 2))
        local amountFont = (key == "health" or key == "power") and numberFont or STANDARD_TEXT_FONT
        if not bar.amount:SetFont(amountFont, fontSize, "OUTLINE") then
            bar.amount:SetFont(STANDARD_TEXT_FONT, fontSize, "OUTLINE")
        end
        if not bar.percent:SetFont(numberFont, fontSize, "OUTLINE") then
            bar.percent:SetFont(STANDARD_TEXT_FONT, fontSize, "OUTLINE")
        end
        local mode = module.GetTextMode(db, unit, key)
        local amount = mode == "amount" or mode == "both"
        local percent = mode == "percent" or mode == "both"
        bar.amount:SetShown(amount)
        bar.percent:SetShown(percent)
        bar.percent:ClearAllPoints()
        if amount then
            bar.percent:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
        else
            bar.percent:SetPoint("CENTER", bar, "CENTER", 0, 0)
        end
        if percent and amount then
            bar.amount:SetPoint("RIGHT", bar.percent, "LEFT", -5, 0)
        else
            bar.amount:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
        end
        bar.amount:SetJustifyH("LEFT")
    end
    LayoutBars(frame)
end

local function SetValues(bar, value, maximum, percent)
    local barMaximum = maximum
    if not isSecret(maximum) and maximum == 0 then barMaximum = 1 end
    bar:SetMinMaxValues(0, barMaximum)
    bar:SetValue(value)
    bar.amount:SetFormattedText("%d / %d", value, maximum)
    if type(percent) == "number" then
        bar.percent:SetFormattedText("%.0f%%", percent)
    else
        bar.percent:SetText("")
    end
end

local function GetPercent(unit, value, maximum, power)
    if not isSecret(value) and not isSecret(maximum) then
        if maximum > 0 then return value * 100 / maximum end
        return
    end
    if not curve and C_CurveUtil and C_CurveUtil.CreateCurve then
        curve = C_CurveUtil.CreateCurve()
        curve:AddPoint(0, 0)
        curve:AddPoint(1, 100)
    end
    if not curve then return end
    if power and UnitPowerPercent then return UnitPowerPercent(unit, nil, false, curve) end
    if not power and UnitHealthPercent then return UnitHealthPercent(unit, true, curve) end
end

local function SetPowerColor(bar, token)
    if not isSecret(token) then
        local color = PowerBarColor and PowerBarColor[token]
        if color and SetFlatColor(bar, color.r, color.g, color.b) then return end
        local fallback = classicPowerColors[token]
        if fallback then SetFlatColor(bar, unpack(fallback)); return end
    end
    bar:SetStatusBarColor(RGB("526676"))
end

local function SetIdentity(frame, level, classification)
    local levelText = ""
    if not isSecret(level) and type(level) == "number" then
        if level > 0 then levelText = tostring(level) end
        if level < 0 then levelText = "??" end
    end
    local special = not isSecret(classification) and classificationLabels[classification]
    if special then
        frame.info:SetText(levelText == "" and special or levelText .. " · " .. special)
    else
        frame.info:SetText(levelText)
    end
end

local function Update(frame, event)
    if not frame.active or not frame:IsShown() then return end
    local unit = frame.unit
    local full = not event or event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_ENTERING_WORLD"
    if frame.options.health then
        local colorByHealth = frame.options.colorMode == "health"
        if not colorByHealth and (full or event == "UNIT_FACTION" or event == "UNIT_NAME_UPDATE") then
            SetHealthColor(frame)
        end
        if full or event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
            local value, maximum = UnitHealth(unit), UnitHealthMax(unit)
            local percent = GetPercent(unit, value, maximum, false)
            SetValues(frame.health, value, maximum, percent)
            if colorByHealth then SetHealthPercentageColor(frame, percent) end
        end
    end
    if full or event == "UNIT_POWER_FREQUENT" or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
        local maximum = UnitPowerMax(unit)
        local hasPower = frame.options.power and (isSecret(maximum) or maximum > 0)
        frame.power:SetShown(hasPower)
        LayoutBars(frame)
        if hasPower then
            local value = UnitPower(unit)
            local _, powerToken = UnitPowerType(unit)
            SetPowerColor(frame.power, powerToken)
            SetValues(frame.power, value, maximum, GetPercent(unit, value, maximum, true))
        end
    end
    if full or event == "UNIT_NAME_UPDATE" or event == "UNIT_LEVEL" or event == "PLAYER_LEVEL_UP"
        or event == "UNIT_CLASSIFICATION_CHANGED" then
        if unit == "target" then frame.name:SetText(UnitName(unit)) end
        SetIdentity(frame, UnitLevel(unit), unit == "target" and UnitClassification(unit))
    end
    addon.UnitTimers.Update(frame, event, full)
end

local function CreateUnitFrame(unit)
    local name = unit == "player" and "HUDTunerMinimalPlayer" or "HUDTunerMinimalTarget"
    local frame = CreateFrame("Button", name, UIParent, "SecureUnitButtonTemplate")
    frame:Hide()
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(20)
    frame:SetClampedToScreen(true)
    frame.unit = unit
    frame:SetAttribute("unit", unit)
    frame:SetAttribute("*type1", "target")
    frame:SetAttribute("*type2", "togglemenu")
    frame:RegisterForClicks("AnyUp")
    BuildAppearance(frame)
    frame:HookScript("OnShow", function(self) Update(self) end)
    frame:HookScript("OnHide", addon.UnitTimers.Stop)
    local listener = CreateFrame("Frame")
    for _, event in ipairs(events) do listener:RegisterUnitEvent(event, unit) end
    listener:RegisterEvent("PLAYER_ENTERING_WORLD")
    listener:RegisterEvent(unit == "target" and "PLAYER_TARGET_CHANGED" or "PLAYER_LEVEL_UP")
    addon.UnitTimers.Register(listener, unit)
    listener:SetScript("OnEvent", function(_, event) Update(frame, event) end)
    frames[unit] = frame
    return frame
end

function module.Position(unit, db)
    local setting = settings[unit]
    local x, y = db[setting.x], db[setting.y]
    if type(x) ~= "number" or x ~= x or math.abs(x) == math.huge then x = setting.offset end
    if type(y) ~= "number" or y ~= y or math.abs(y) == math.huge then y = -175 end
    return x, y
end

function module.SavePosition(unit, db, x, y)
    local setting = settings[unit]
    db[setting.x], db[setting.y] = x, y
end

function module.Apply(db, editing)
    if InCombatLockdown() then return end
    for _, unit in ipairs(module.units) do
        local enable = db[settings[unit].enabled] == true and not editing
        local frame = frames[unit]
        if enable and not frame then frame = CreateUnitFrame(unit) end
        if frame then
            if enable then
                ApplyAppearance(frame, db, unit)
                local x, y = module.Position(unit, db)
                if x ~= frame.offsetX or y ~= frame.offsetY then
                    frame:ClearAllPoints()
                    frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
                    frame.offsetX, frame.offsetY = x, y
                end
            end
            if enable ~= frame.active then
                frame.active = enable
                if enable then
                    RegisterUnitWatch(frame)
                else
                    UnregisterUnitWatch(frame)
                    frame:Hide()
                end
            end
            if enable then Update(frame) end
        end
    end
end

function module.IsActive(unit)
    return frames[unit] ~= nil and frames[unit].active == true
end

function module.SetPreviewing(previewing)
    for _, unit in ipairs(module.units) do
        local frame = frames[unit]
        if module.IsActive(unit) and previewing and alphaDuringPreview[unit] == nil then
            alphaDuringPreview[unit] = frame:GetAlpha()
            frame:SetAlpha(0)
        elseif not previewing and alphaDuringPreview[unit] ~= nil then
            frame:SetAlpha(alphaDuringPreview[unit])
            alphaDuringPreview[unit] = nil
        end
    end
end

local previewProperties = { health = "health", power = "power", castBar = "casts", swingBar = "swings" }

function module.BuildPreview(frame, unit, db, selectedBar, sample)
    if not frame.health then BuildAppearance(frame) end
    local property = previewProperties[selectedBar]
    local sampleProperty = property and not module.GetOption(db, unit, property) and property or nil
    local kind = sample and sample.kind
    ApplyAppearance(frame, db, unit, sampleProperty, kind == "cast")
    local mage = unit == "target" and kind == "mage"
    local npc = unit == "target" and (kind == "npc" or kind == "cast")
    frame.name:SetText(mage and L.UnitFrameSampleMage or npc and L.UnitFrameSampleNPC
        or (unit == "player" and L.UnitFramePlayer or L.UnitFrameTarget))
    SetIdentity(frame, unit == "player" and 40 or 41, unit == "target" and not mage and "elite")
    if frame.options.colorMode == "health" then
        local percent = sample and sample.percent or 50
        SetValues(frame.health, percent * 24, 2400, percent)
        SetHealthPercentageColor(frame, percent)
    elseif frame.options.colorMode == "fixed" then
        frame.health:SetStatusBarColor(module.FixedColor(db, unit))
    elseif unit == "player" then
        SetHealthColor(frame)
    elseif not (mage and frame.options.colorMode == "auto" and SetFlatColor(frame.health, ClassTokenColor("MAGE"))) then
        if mage then SetFlatColor(frame.health, 0, 1, 0)
        else SetFlatColor(frame.health, 1, 0, 0) end
    end
    if frame.options.colorMode ~= "health" then SetValues(frame.health, 2251, 2389, 94) end
    frame.power:SetShown(frame.options.power)
    if unit == "player" then
        local _, playerPower = UnitPowerType("player")
        SetPowerColor(frame.power, playerPower)
    else
        SetPowerColor(frame.power, "MANA")
    end
    SetValues(frame.power, 61, 100, 61)
    addon.UnitTimers.Preview(frame)
    if kind == "cast" then frame.castBar.amount:SetText(L.UnitFrameSampleSpell) end
    LayoutBars(frame)
    return sampleProperty ~= nil
end
