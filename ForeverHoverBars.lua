local addonName, addon = ...
local L = addon.L
local unitFrames = addon.UnitFrames
local addonTitle = "HUD Tuner"
local technicalCyan = { 0, 0xB4 / 255, 0xD8 / 255, 1 }

local function Notify(message)
    print(addonTitle .. ": " .. message)
end

local controller = CreateFrame("Frame")
local bars, panel = {}
local RefreshGroupUI
local hudEditor
local CreateOptions

local function ToggleOptions()
    if hudEditor and hudEditor:IsShown() then
        hudEditor:Hide()
        return
    end
    if not panel then CreateOptions() end
    panel:SetShown(not panel:IsShown())
end

local hoverValues = { fadeIn = 0.25, fadeOut = 0.5, hideDelay = 0.3, minAlpha = 0 }
local names = {
    "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight",
    "MultiBarRight", "MultiBarLeft", "MultiBar5", "MultiBar6", "MultiBar7",
    "PetActionBar", "StanceBar", "BagsBar", "MicroMenu",
}
local labels = {}
for index = 1, 8 do
    labels[index] = L.ActionBar:format(index)
end
labels[9], labels[10], labels[11], labels[12] = L.PetBar, L.StanceBar, L.BagsBar, L.MicroMenu
local db
local minimapButton

local function PositionMinimapButton()
    if not minimapButton or not Minimap then return end
    local angle = math.rad(db.minimapButtonAngle or 225)
    local radius = Minimap:GetWidth() / 2 + 2
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER",
        math.cos(angle) * radius, math.sin(angle) * radius)
end
local function UpdateMinimapButton()
    if not minimapButton then return end
    minimapButton:SetShown(db.showMinimapButton ~= false)
end
local function CreateMinimapButton()
    if minimapButton or not Minimap then return end
    minimapButton = CreateFrame("Button", "ForeverHoverBarsMinimapButton", Minimap)
    minimapButton:SetSize(32, 32)
    minimapButton:SetFrameStrata("MEDIUM")
    minimapButton:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    minimapButton:SetClampedToScreen(true)
    minimapButton:EnableMouse(true)
    minimapButton:RegisterForClicks("LeftButtonUp")
    minimapButton:RegisterForDrag("LeftButton")
    minimapButton.icon = minimapButton:CreateTexture(nil, "ARTWORK")
    minimapButton.icon:SetSize(20, 20)
    minimapButton.icon:SetPoint("CENTER")
    minimapButton.icon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
    minimapButton.border = minimapButton:CreateTexture(nil, "OVERLAY")
    minimapButton.border:SetSize(54, 54)
    -- Blizzard's tracking border includes transparent padding and is aligned
    -- to the button's top-left, not centered on the 32px button frame.
    minimapButton.border:SetPoint("TOPLEFT", minimapButton, "TOPLEFT", 0, 0)
    minimapButton.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    minimapButton.border:SetAlpha(0.82)
    minimapButton:SetScript("OnEnter", function(self)
        self.icon:SetVertexColor(1, 0.88, 0.62, 1)
        self.border:SetAlpha(1)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(addonTitle)
        GameTooltip:AddLine(L.MinimapClick, 1, 1, 1)
        GameTooltip:AddLine(L.MinimapDrag, 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    minimapButton:SetScript("OnLeave", function(self)
        self.icon:SetVertexColor(1, 1, 1, 1)
        self.border:SetAlpha(0.82)
        GameTooltip_Hide()
    end)
    minimapButton:SetScript("OnClick", function(self, button)
        if button ~= "LeftButton" then return end
        if self.ignoreNextClick then
            self.ignoreNextClick = false
            return
        end
        ToggleOptions()
    end)
    minimapButton:SetScript("OnDragStart", function(self)
        self.dragging = true
        self.moved = false
    end)
    minimapButton:SetScript("OnDragStop", function(self)
        self.dragging = false
        self.ignoreNextClick = self.moved
    end)
    minimapButton:SetScript("OnUpdate", function(self)
        if not self.dragging then return end
        local cursorX, cursorY = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        local centerX, centerY = Minimap:GetCenter()
        cursorX, cursorY = cursorX / scale, cursorY / scale
        db.minimapButtonAngle = math.deg(math.atan2(cursorY - centerY, cursorX - centerX))
        self.moved = true
        PositionMinimapButton()
    end)
    PositionMinimapButton()
    UpdateMinimapButton()
end
local performance, performanceMoving
local performanceMetrics = { "showFPS", "showHome", "showWorld" }

local function PositionPerformance()
    local scale = performance:GetEffectiveScale() / UIParent:GetEffectiveScale()
    performance:ClearAllPoints()
    if db.performanceX and db.performanceY then
        performance:SetPoint("CENTER", UIParent, "BOTTOMLEFT",
            db.performanceX / scale, db.performanceY / scale)
    else
        performance:SetPoint("TOP", UIParent, "TOP", 0, -20 / scale)
    end
end

local function SavePerformancePosition(self)
    if not self.dragging then return end
    self:StopMovingOrSizing()
    self.dragging = false
    local x, y = self:GetCenter()
    if x and y then
        local scale = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
        db.performanceX, db.performanceY = x * scale, y * scale
    end
    PositionPerformance()
end

local function SamplePerformance()
    local parts = {}
    if db.showFPS then
        parts[#parts + 1] = string.format("%.0f FPS", GetFramerate())
    end
    if db.showHome or db.showWorld then
        local _, _, home, world = GetNetStats()
        if db.showHome then parts[#parts + 1] = string.format(L.HomeLatency, home) end
        if db.showWorld then parts[#parts + 1] = string.format(L.WorldLatency, world) end
    end
    performance.label:SetText(#parts > 0 and table.concat(parts, "  |  ") or L.DragDisplay)
    performance:SetWidth(math.max(58, performance.label:GetStringWidth() + 14))
end

local function UpdatePerformance()
    local visible = performanceMoving
        or (db.showPerformance and (db.showFPS or db.showHome or db.showWorld))
    performance:EnableMouse(performanceMoving == true)
    performance.bg:SetColorTexture(0.071, 0.082, 0.094, performanceMoving and 0.96 or 0.84)
    performance:SetShown(visible and true or false)
    if visible then SamplePerformance() end
end

local function TogglePerformanceMover()
    if performanceMoving then SavePerformancePosition(performance) end
    performanceMoving = not performanceMoving
    UpdatePerformance()
    if performanceMoving then
        Notify(L.MovePerformanceHelp)
    end
end

local function ResetPerformancePosition()
    SavePerformancePosition(performance)
    db.performanceX, db.performanceY = nil, nil
    PositionPerformance()
end

local function CreatePerformance()
    performance = CreateFrame("Frame", nil, UIParent)
    performance:SetSize(58, 20)
    performance:SetScale(db.performanceScale)
    performance:SetFrameStrata("MEDIUM")
    performance:SetMovable(true)
    performance:SetClampedToScreen(true)
    performance:RegisterForDrag("LeftButton")
    performance.bg = performance:CreateTexture(nil, "BACKGROUND")
    performance.bg:SetAllPoints()
    performance.label = performance:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    performance.label:SetPoint("CENTER")
    performance:SetScript("OnDragStart", function(self)
        if not performanceMoving then return end
        self:StartMoving()
        self.dragging = true
    end)
    performance:SetScript("OnDragStop", SavePerformancePosition)
    performance:SetScript("OnMouseUp", function(_, button)
        if performanceMoving and button == "RightButton" then TogglePerformanceMover() end
    end)
    local sinceSample = 0
    performance:SetScript("OnUpdate", function(_, elapsed)
        sinceSample = sinceSample + elapsed
        if sinceSample < 1 then return end
        sinceSample = 0
        SamplePerformance()
    end)
    PositionPerformance()
    UpdatePerformance()
end

local function Fade(state, target, elapsed)
    local alpha = state.frame:GetAlpha()
    if alpha == target then return end
    local duration = target > alpha and db.fadeIn or db.fadeOut
    -- Constant speed: respond immediately, including when reversing midway.
    -- The duration describes the full visible-to-minimum opacity range.
    local distance = math.max(0.001, 1 - db.minAlpha)
    local step = duration == 0 and 1 or elapsed * distance / duration
    if target > alpha then
        alpha = math.min(target, alpha + step)
    else
        alpha = math.max(target, alpha - step)
    end
    state.frame:SetAlpha(alpha)
end
local function DiscoverBars()
    for _, name in ipairs(names) do
        local bar = _G[name]
        if bar and not bars[name] then
            bars[name] = { frame = bar, originalAlpha = bar:GetAlpha(), lastHover = GetTime() }
        end
    end
end
local function Hovered(bar)
    if bar:IsMouseOver() then return true end
    if bar.popup and bar.popup:IsShown() and bar.popup:IsMouseOver() then return true end
    if bar.popup and bar.popup:IsShown() then
        for _, child in ipairs({ bar.popup:GetChildren() }) do
            if child:IsShown() and child:IsMouseOver() then return true end
        end
    end
    for _, button in ipairs(bar.actionButtons or {}) do
        if button:IsShown() and button:IsMouseOver() then return true end
    end
    for _, child in ipairs({ bar:GetChildren() }) do
        if child:IsShown() and child:IsMouseOver() then return true end
    end
    return false
end
local groupPolicies = {
    { key = "hover", label = L.ShowOnHover },
    { key = "alwaysVisible", label = L.AlwaysVisible },
    { key = "alwaysHidden", label = L.AlwaysHidden },
    { key = "hideInCombat", label = L.HideInCombat },
}
local validGroupPolicies = {}
for _, policy in ipairs(groupPolicies) do validGroupPolicies[policy.key] = true end

local function IsValidGroupID(groupID)
    return type(groupID) == "number" and groupID % 1 == 0 and groupID >= 1 and groupID <= 8
end

local function FirstAvailableGroupID()
    for groupID = 1, 8 do
        if not db.groups[groupID] then return groupID end
    end
end

local function CreateGroup()
    local groupID = FirstAvailableGroupID()
    if not groupID then return end
    db.groups[groupID] = "hover"
    return groupID
end

local function GroupForBar(name)
    return db.barGroups[name]
end

local function GroupDisplayName(id)
    return db.groupNames[id] or L.GroupName:format(id)
end

local function CleanGroupName(name)
    if type(name) ~= "string" or #name > 128 or name:find("[%c|]") then return end
    local trimmed = name:match("^%s*(.-)%s*$")
    if trimmed ~= "" then return trimmed end
end

local function InitializeGroups()
    if type(db.groups) ~= "table" then db.groups = {} end
    if type(db.barGroups) ~= "table" then db.barGroups = {} end

    for groupID, policy in pairs(db.groups) do
        if not IsValidGroupID(groupID) then
            db.groups[groupID] = nil
        elseif not validGroupPolicies[policy] then
            db.groups[groupID] = "hover"
        end
    end

    if type(db.groupNames) ~= "table" then db.groupNames = {} end
    for id, name in pairs(db.groupNames) do
        db.groupNames[id] = db.groups[id] and CleanGroupName(name) or nil
    end

    local validBars = {}
    for _, name in ipairs(names) do validBars[name] = true end
    for name, groupID in pairs(db.barGroups) do
        if not validBars[name] or not IsValidGroupID(groupID) or not db.groups[groupID] then
            db.barGroups[name] = nil
        end
    end
end

local function GroupPolicyText(policyKey)
    for _, policy in ipairs(groupPolicies) do
        if policy.key == policyKey then return policy.label end
    end
    return L.ShowOnHover
end
local profileTables = { "groups", "groupNames", "barGroups" }
local profileSettings = {
    "enabled", "showMinimapButton", "minimapButtonAngle",
    "hideNativePlayerFrame", "hideNativeTargetFrame",
    "showMinimalPlayerFrame", "showMinimalTargetFrame",
    "minimalPlayerX", "minimalPlayerY", "minimalTargetX", "minimalTargetY",
    "hideBlizzardQuestTracker", "showPerformance", "showFPS", "showHome",
    "showWorld", "performanceScale", "performanceX", "performanceY",
}
for _, key in ipairs(unitFrames.profileSettings) do table.insert(profileSettings, key) end
local profileKey

local function CopyMap(source)
    local result = {}
    if type(source) == "table" then
        for key, value in pairs(source) do result[key] = value end
    end
    return result
end

local function CopyProfile(source, destination)
    for _, key in ipairs(profileSettings) do destination[key] = source[key] end
    for _, key in ipairs(profileTables) do destination[key] = CopyMap(source[key]) end
    return destination
end

local function SaveCharacterProfile()
    if db and profileKey then
        HUDTunerCharacterProfiles[profileKey] = CopyProfile(db, {})
    end
end

local mutedUnitFrames = {}
local unitFrameAlphaHooks = {}
local unitFramesEditModeHooked
local unitFrameAppearancePending

local function KeepUnitFrameMuted(frame)
    local state = mutedUnitFrames[frame]
    if not state or state.applying then return end

    state.alpha = frame:GetAlpha()
    state.applying = true
    frame:SetAlpha(0)
    state.applying = false
end

local function SetNativeUnitFrameHidden(frame, hidden)
    if not frame then return end
    local state = mutedUnitFrames[frame]
    if hidden and not state then
        if not unitFrameAlphaHooks[frame] then
            hooksecurefunc(frame, "SetAlpha", KeepUnitFrameMuted)
            unitFrameAlphaHooks[frame] = true
        end
        mutedUnitFrames[frame] = {}
        KeepUnitFrameMuted(frame)
    elseif not hidden and state then
        mutedUnitFrames[frame] = nil
        frame:SetAlpha(state.alpha)
    end
end

local function ApplyNativeUnitFrameOptions(_, appearanceChanged)
    if not db then return end
    local editMode = EditModeManagerFrame
    if editMode and not unitFramesEditModeHooked
        and (db.hideNativePlayerFrame or db.hideNativeTargetFrame
            or db.showMinimalPlayerFrame or db.showMinimalTargetFrame) then
        unitFramesEditModeHooked = true
        editMode:HookScript("OnShow", ApplyNativeUnitFrameOptions)
        editMode:HookScript("OnHide", ApplyNativeUnitFrameOptions)
    end

    local editing = editMode and editMode:IsShown()
    local inCombat = InCombatLockdown()
    unitFrameAppearancePending = inCombat and (unitFrameAppearancePending or appearanceChanged == true)
    unitFrames.Apply(db, editing)
    SetNativeUnitFrameHidden(PlayerFrame,
        (db.hideNativePlayerFrame == true or unitFrames.IsActive("player")) and not editing)
    SetNativeUnitFrameHidden(TargetFrame,
        (db.hideNativeTargetFrame == true or unitFrames.IsActive("target")) and not editing)
    if panel and panel.unitFramesStatus then
        local pending = unitFrameAppearancePending or (inCombat and (
            (db.showMinimalPlayerFrame == true) ~= unitFrames.IsActive("player")
            or (db.showMinimalTargetFrame == true) ~= unitFrames.IsActive("target"))) or false
        panel.unitFramesStatus:SetShown(pending)
        local action = panel.unitFramePendingAction
        if pending then
            panel.unitFramesStatus:SetText(action and L.UnitFramePendingAction:format(action) or L.AfterCombat)
        else
            panel.unitFramePendingAction = nil
        end
        if panel.RefreshUnitFrameStates then panel.RefreshUnitFrameStates() end
        if panel.RefreshUnitFramePreview then panel.RefreshUnitFramePreview() end
    end
end

local questTrackerHooked
local questTrackerHidden
local questTrackerAlpha

local questTrackerPending
local function ApplyQuestTrackerVisibility()
    local tracker = ObjectiveTrackerFrame
    if not db or not tracker then return end

    local hide = db.hideBlizzardQuestTracker
    local locked = InCombatLockdown() and tracker:IsProtected()
    questTrackerPending = locked and ((hide and tracker:IsShown()) or (not hide and questTrackerHidden))
    if panel and panel.questTrackerStatus then
        panel.questTrackerStatus:SetShown(questTrackerPending and true or false)
    end
    if hide and not questTrackerHooked then
        questTrackerHooked = true
        tracker:HookScript("OnShow", ApplyQuestTrackerVisibility)
    end

    if hide and locked and tracker:IsShown() then
        if questTrackerAlpha == nil then questTrackerAlpha = tracker:GetAlpha() end
        tracker:SetAlpha(0)
        return
    end

    if questTrackerAlpha ~= nil then
        if tracker:GetAlpha() == 0 then tracker:SetAlpha(questTrackerAlpha) end
        questTrackerAlpha = nil
    end

    if locked then return end
    if hide and tracker:IsShown() then
        questTrackerHidden = true
        tracker:Hide()
    elseif not hide and questTrackerHidden then
        questTrackerHidden = nil
        tracker:Show()
    end
end

CreateOptions = function()
    local RefreshAll
    local width = math.min(900, UIParent:GetWidth() - 32)
    local height = math.min(490, UIParent:GetHeight() - 32)
    local colors = {
        window = { 0x12 / 255, 0x15 / 255, 0x18 / 255, 0.93 },
        card = { 0x1E / 255, 0x23 / 255, 0x29 / 255, 0.94 },
        row = { 0x1E / 255, 0x23 / 255, 0x29 / 255, 1 },
        border = { 0.22, 0.26, 0.30, 1 },
        accent = technicalCyan,
        text = { 0.91, 0.93, 0.97, 1 },
        muted = { 0.67, 0.72, 0.80, 1 },
        selected = { 0.075, 0.185, 0.225, 1 },
        activeGroupBar = { 0.055, 0.155, 0.185, 1 },
        otherGroup = { 0.145, 0.20, 0.235, 1 },
        danger = { 0.96, 0.56, 0.52, 1 },
        clear = { 0, 0, 0, 0 },
    }
    panel = CreateFrame("Frame", "ForeverHoverBarsOptions", UIParent)
    panel:SetSize(width, height)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:SetMovable(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)

    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(unpack(colors.window))
    local function AddRule(parent, point, relativePoint, x, y, width, height, r, g, b, a)
        local rule = parent:CreateTexture(nil, "BORDER")
        rule:SetPoint(point, parent, relativePoint, x, y)
        rule:SetSize(width, height)
        rule:SetColorTexture(r, g, b, a or 1)
        return rule
    end
    AddRule(panel, "TOPLEFT", "TOPLEFT", 0, 0, width, 2, unpack(colors.accent))
    AddRule(panel, "TOPLEFT", "TOPLEFT", 0, 0, 1, height, unpack(colors.border))
    AddRule(panel, "TOPRIGHT", "TOPRIGHT", 0, 0, 1, height, unpack(colors.border))
    AddRule(panel, "BOTTOMLEFT", "BOTTOMLEFT", 0, 0, width, 1, unpack(colors.border))

    local function ColorTexture(owner, layer, color)
        local texture = owner:CreateTexture(nil, layer)
        texture:SetAllPoints()
        texture:SetColorTexture(unpack(color))
        return texture
    end

    local function AddHoverBorder(button)
        local edges = {
            { "TOPLEFT", "TOPRIGHT", true },
            { "BOTTOMLEFT", "BOTTOMRIGHT", true },
            { "TOPLEFT", "BOTTOMLEFT", false },
            { "TOPRIGHT", "BOTTOMRIGHT", false },
        }
        for _, edge in ipairs(edges) do
            local line = button:CreateTexture(nil, "HIGHLIGHT")
            line:SetPoint(edge[1])
            line:SetPoint(edge[2])
            if edge[3] then line:SetHeight(1) else line:SetWidth(1) end
            line:SetColorTexture(unpack(colors.accent))
        end
    end

    local function AddButton(parent, text, kind, leftAligned)
        local button = CreateFrame("Button", nil, parent)
        local background = kind == "primary" and colors.selected
            or (kind == "quiet" or kind == "danger") and colors.clear or colors.row
        button.bg = ColorTexture(button, "BACKGROUND", background)
        AddHoverBorder(button)
        button:SetPushedTexture(ColorTexture(button, "ARTWORK", { 0, 0, 0, 0.22 }))
        local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("TOPLEFT", 10, 0)
        label:SetPoint("BOTTOMRIGHT", -10, 0)
        label:SetJustifyH(leftAligned and "LEFT" or "CENTER")
        label:SetJustifyV("MIDDLE")
        label:SetTextColor(unpack(kind == "primary" and colors.accent or colors.text))
        label:SetText(text)
        button.label = label
        if kind == "danger" then
            label:SetTextColor(unpack(colors.muted))
            button:SetScript("OnEnter", function() label:SetTextColor(unpack(colors.danger)) end)
            button:SetScript("OnLeave", function() label:SetTextColor(unpack(colors.muted)) end)
        end
        return button
    end

    local function AddSelectionRow(parent, text)
        local button = AddButton(parent, text, "quiet", true)
        button.activeMark = AddRule(button, "TOPLEFT", "TOPLEFT", 0, -3, 2, 24,
            unpack(colors.accent))
        button.activeMark:Hide()
        return button
    end

    local function SetSelected(button, selected)
        button.bg:SetColorTexture(unpack(selected and colors.selected or colors.clear))
        button.label:SetTextColor(unpack(selected and colors.accent or colors.muted))
        button.activeMark:SetShown(selected)
    end

    local function AddCheckbox(parent)
        local check = CreateFrame("CheckButton", nil, parent)
        check:SetSize(16, 16)
        ColorTexture(check, "BACKGROUND", colors.border)
        local inset = ColorTexture(check, "BORDER", colors.card)
        inset:ClearAllPoints()
        inset:SetPoint("TOPLEFT", 1, -1)
        inset:SetPoint("BOTTOMRIGHT", -1, 1)
        check:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
        local tick = check:GetCheckedTexture()
        tick:SetAllPoints()
        tick:SetDesaturated(true)
        tick:SetVertexColor(unpack(technicalCyan))
        AddHoverBorder(check)
        return check
    end

    local header = CreateFrame("Frame", nil, panel)
    header:SetPoint("TOPLEFT", 16, -2)
    header:SetPoint("TOPRIGHT", -16, -2)
    header:SetHeight(48)
    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT")
    title:SetText(addonTitle)
    title:SetTextColor(unpack(colors.accent))
    AddRule(header, "BOTTOMLEFT", "BOTTOMLEFT", 0, 0, width - 32, 1, unpack(colors.row))

    local close = AddButton(header, "×", "quiet")
    close:SetSize(36, 28)
    close:SetPoint("RIGHT")
    close:SetScript("OnClick", function() panel:Hide() end)

    local enabled = AddCheckbox(header)
    enabled:SetPoint("RIGHT", close, "LEFT", -6, 0)
    local enabledLabel = header:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    enabledLabel:SetPoint("RIGHT", enabled, "LEFT", -8, 0)
    enabledLabel:SetText(L.VisibilityEnabled)
    enabledLabel:SetTextColor(unpack(colors.muted))
    enabled:SetScript("OnClick", function(self)
        db.enabled = self:GetChecked() and true or false
    end)
    panel.enabled = enabled

    local editHud = AddButton(header, L.EditHUD, "primary")
    editHud:SetSize(100, 28)
    editHud:SetPoint("RIGHT", enabledLabel, "LEFT", -14, 0)

    hudEditor = CreateFrame("Frame", "HUDTunerLayoutEditor", UIParent)
    hudEditor:SetAllPoints(UIParent)
    hudEditor:SetFrameStrata("DIALOG")
    hudEditor:EnableMouse(false)
    hudEditor:Hide()

    local function MakeGuide()
        local line = hudEditor:CreateTexture(nil, "BACKGROUND")
        line:SetColorTexture(technicalCyan[1], technicalCyan[2], technicalCyan[3], 0.66)
        line:SetAlpha(0.42)
        return line
    end
    local centerVertical, centerHorizontal = MakeGuide(), MakeGuide()
    centerVertical:SetWidth(1)
    centerVertical:SetPoint("TOP")
    centerVertical:SetPoint("BOTTOM")
    centerHorizontal:SetHeight(1)
    centerHorizontal:SetPoint("LEFT")
    centerHorizontal:SetPoint("RIGHT")

    local function CenterInParent(frame)
        if not frame then return end
        local x, y = frame:GetCenter()
        if not x or not y then return end
        local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
        return x * scale, y * scale
    end

    local function SnapPosition(x, y)
        local centerX, centerY = UIParent:GetWidth() / 2, UIParent:GetHeight() / 2
        return math.abs(x - centerX) < 10 and centerX or nil,
            math.abs(y - centerY) < 10 and centerY or nil
    end

    local function PositionMover(mover, x, y)
        local halfWidth, halfHeight = mover:GetWidth() / 2, mover:GetHeight() / 2
        x = math.max(halfWidth, math.min(UIParent:GetWidth() - halfWidth, x))
        y = math.max(halfHeight, math.min(UIParent:GetHeight() - halfHeight, y))
        mover:ClearAllPoints()
        mover:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    end

    local function ShowSnapGuides(mover)
        local x, y = CenterInParent(mover)
        if not x then return end
        local snapX, snapY = SnapPosition(x, y)
        centerVertical:SetAlpha(snapX and 1 or 0.42)
        centerHorizontal:SetAlpha(snapY and 1 or 0.42)
    end

    local function StopLayoutDrag(mover, keepPosition)
        if not mover.dragging then return end
        mover:StopMovingOrSizing()
        mover:SetScript("OnUpdate", nil)
        mover.dragging = nil
        centerVertical:SetAlpha(0.42)
        centerHorizontal:SetAlpha(0.42)
        if not keepPosition then return end
        local x, y = CenterInParent(mover)
        if x then
            local snapX, snapY = SnapPosition(x, y)
            PositionMover(mover, snapX or x, snapY or y)
            mover.changed = true
        end
    end

    local function LayoutBox(background)
        local frame = CreateFrame("Frame", nil, hudEditor, "BackdropTemplate")
        frame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        frame:SetBackdropColor(unpack(background))
        frame:SetBackdropBorderColor(unpack(colors.border))
        frame:EnableMouse(true)
        return frame
    end

    local mover = CreateFrame("Frame", nil, hudEditor, "BackdropTemplate")
    mover:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    mover:SetBackdropBorderColor(technicalCyan[1], technicalCyan[2], technicalCyan[3], 0.8)
    mover:EnableMouse(true)
    mover:SetMovable(true)
    mover:SetClampedToScreen(true)
    mover:RegisterForDrag("LeftButton")

    local moverLabel = mover:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    moverLabel:SetText(L.PerformanceLayout)
    moverLabel:SetTextColor(0.78, 0.78, 0.78)
    moverLabel:SetShadowColor(0, 0, 0, 0)
    moverLabel:SetPoint("TOP", mover, "BOTTOM", 0, -4)

    local sample = mover:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sample:SetPoint("CENTER")
    sample:SetAlpha(0.70)
    local originalPerformanceAlpha

    mover:SetScript("OnDragStart", function(self)
        self:StartMoving()
        self.dragging = true
        self:SetScript("OnUpdate", ShowSnapGuides)
    end)
    mover:SetScript("OnDragStop", function(self) StopLayoutDrag(self, true) end)

    local unitMovers = {}
    local function UnitMover()
        local preview = CreateFrame("Frame", nil, hudEditor)
        preview:EnableMouse(true)
        preview:SetMovable(true)
        preview:SetClampedToScreen(true)
        preview:RegisterForDrag("LeftButton")
        preview:SetScript("OnDragStart", mover:GetScript("OnDragStart"))
        preview:SetScript("OnDragStop", mover:GetScript("OnDragStop"))
        return preview
    end

    local editToolbar = LayoutBox(colors.window)
    editToolbar:SetFrameLevel(hudEditor:GetFrameLevel() + 5)
    editToolbar:SetSize(math.min(440, width), 100)
    editToolbar:SetPoint("TOP", 0, -62)
    editToolbar:SetMovable(true)
    editToolbar:SetClampedToScreen(true)
    editToolbar:RegisterForDrag("LeftButton")
    editToolbar:SetScript("OnDragStart", editToolbar.StartMoving)
    editToolbar:SetScript("OnDragStop", editToolbar.StopMovingOrSizing)
    editToolbar:SetScript("OnHide", editToolbar.StopMovingOrSizing)
    local editTitle = editToolbar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    editTitle:SetPoint("TOP", 0, -10)
    editTitle:SetText(L.EditHUD)
    editTitle:SetTextColor(unpack(colors.accent))
    local editHelp = editToolbar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    editHelp:SetPoint("TOPLEFT", 12, -36)
    editHelp:SetPoint("TOPRIGHT", -12, -36)
    editHelp:SetText(L.EditHUDHelp)
    editHelp:SetTextColor(unpack(colors.muted))

    local function CanEditHUD()
        if InCombatLockdown() then
            Notify(L.EditHUDOutOfCombat)
            return false
        end
        if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
            Notify(L.ExitEditMode)
            return false
        end
        return true
    end

    editHud:SetScript("OnClick", function()
        if not CanEditHUD() then return end
        if performanceMoving then
            Notify(L.ClosePositionControls)
            return
        end
        local screenWidth, screenHeight = UIParent:GetWidth(), UIParent:GetHeight()
        local x, y = db.performanceX, db.performanceY
        if not x or not y then x, y = CenterInParent(performance) end
        local scale = performance and performance:GetEffectiveScale() / UIParent:GetEffectiveScale()
            or db.performanceScale or 1
        local previewWidth = (performance and performance:GetWidth() or 58) * scale
        local previewHeight = (performance and performance:GetHeight() or 20) * scale
        mover:SetSize(previewWidth, previewHeight)
        if performance then
            local font, fontSize, flags = performance.label:GetFont()
            if font and fontSize then sample:SetFont(font, fontSize * scale, flags) end
            sample:SetText(performance:IsShown() and performance.label:GetText() or "")
            originalPerformanceAlpha = performance:GetAlpha()
            performance:SetAlpha(0)
        else
            sample:SetText("")
        end
        PositionMover(mover, x or screenWidth / 2, y or screenHeight - 20 - previewHeight / 2)
        mover.changed = nil
        for _, unit in ipairs(unitFrames.units) do
            if unitFrames.IsActive(unit) then
                local preview = unitMovers[unit] or UnitMover()
                unitMovers[unit] = preview
                unitFrames.BuildPreview(preview, unit, db)
                local dx, dy = unitFrames.Position(unit, db)
                PositionMover(preview, screenWidth / 2 + dx, screenHeight / 2 + dy)
                preview.changed = nil
                preview:Show()
            end
        end
        unitFrames.SetPreviewing(true)
        panel:Hide()
        hudEditor:Show()
    end)

    local cancelLayout = AddButton(editToolbar, L.Cancel, "quiet")
    cancelLayout:SetSize(94, 28)
    cancelLayout:SetPoint("BOTTOMRIGHT", -108, 9)
    cancelLayout:SetScript("OnClick", function() hudEditor:Hide() end)

    local saveLayout = AddButton(editToolbar, L.Save, "primary")
    saveLayout:SetSize(94, 28)
    saveLayout:SetPoint("BOTTOMRIGHT", -10, 9)
    saveLayout:SetScript("OnClick", function()
        if not CanEditHUD() then
            hudEditor:Hide()
            return
        end
        StopLayoutDrag(mover, true)
        if mover.changed then
            local x, y = CenterInParent(mover)
            if x then
                db.performanceX, db.performanceY = x, y
                if performance then PositionPerformance() end
            end
        end
        for unit, preview in pairs(unitMovers) do
            StopLayoutDrag(preview, true)
            if preview:IsShown() and preview.changed then
                local x, y = CenterInParent(preview)
                if x and y then
                    unitFrames.SavePosition(unit, db, x - UIParent:GetWidth() / 2,
                        y - UIParent:GetHeight() / 2)
                end
            end
        end
        ApplyNativeUnitFrameOptions()
        hudEditor:Hide()
    end)
    hudEditor:SetScript("OnHide", function(self)
        if self:IsShown() then self:Hide() end
        StopLayoutDrag(mover, false)
        for _, preview in pairs(unitMovers) do
            StopLayoutDrag(preview, false)
            preview:Hide()
        end
        unitFrames.SetPreviewing(false)
        if performance and originalPerformanceAlpha ~= nil then
            performance:SetAlpha(originalPerformanceAlpha)
            originalPerformanceAlpha = nil
        end
        if not InCombatLockdown() and not (EditModeManagerFrame and EditModeManagerFrame:IsShown()) then
            panel:Show()
        end
    end)
    table.insert(UISpecialFrames, "HUDTunerLayoutEditor")

    local body = CreateFrame("Frame", nil, panel)
    body:SetPoint("TOPLEFT", 16, -64)
    body:SetPoint("BOTTOMRIGHT", -16, 16)
    local navigation = CreateFrame("Frame", nil, body)
    navigation:SetPoint("TOPLEFT")
    navigation:SetPoint("BOTTOMLEFT")
    local navigationWidth = width < 660 and 112 or 124
    navigation:SetWidth(navigationWidth)
    local divider = body:CreateTexture(nil, "BORDER")
    divider:SetPoint("TOPLEFT", navigation, "TOPRIGHT", 8, 0)
    divider:SetPoint("BOTTOMLEFT", navigation, "BOTTOMRIGHT", 8, 0)
    divider:SetWidth(1)
    divider:SetColorTexture(unpack(colors.row))

    local scroll = CreateFrame("ScrollFrame", "ForeverHoverBarsOptionsScroll",
        body, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", navigation, "TOPRIGHT", 18, 0)
    scroll:SetPoint("BOTTOMRIGHT", -22, 0)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local step = math.max(30, self:GetHeight() * 0.15)
        local maximum = self:GetVerticalScrollRange() or 0
        self:SetVerticalScroll(math.max(0, math.min(maximum,
            (self:GetVerticalScroll() or 0) - delta * step)))
    end)
    local scrollBar = scroll.ScrollBar or _G[scroll:GetName() .. "ScrollBar"]
    local function UpdateScrollBar()
        if scrollBar then scrollBar:SetShown(scroll:GetVerticalScrollRange() > 0) end
    end
    scroll:HookScript("OnScrollRangeChanged", UpdateScrollBar)
    scroll:HookScript("OnShow", UpdateScrollBar)

    local pageOrder = {
        { id = "bars", label = L.BarsAndGroups },
        { id = "unitFrames", label = L.NativeUnitFrames },
        { id = "quickAccess", label = L.QuickAccess },
        { id = "quests", label = L.Quests },
        { id = "profiles", label = L.Profiles },
        { id = "performance", label = L.Performance },
    }
    local pages, navButtons = {}, {}
    for index, item in ipairs(pageOrder) do
        local page = CreateFrame("Frame", nil, content)
        page:SetPoint("TOPLEFT")
        page:SetWidth(1)
        page:SetHeight(1)
        page:Hide()
        pages[item.id] = page

        local button = AddSelectionRow(navigation, item.label)
        button:SetHeight(30)
        button:SetPoint("TOPLEFT", 0, -(index - 1) * 36)
        button:SetPoint("RIGHT")
        navButtons[item.id] = button
    end
    scroll:SetScript("OnSizeChanged", function(self, newWidth)
        content:SetWidth(newWidth)
        for _, page in pairs(pages) do page:SetWidth(newWidth) end
    end)
    local initialContentWidth = width - navigationWidth - 72
    content:SetWidth(initialContentWidth)
    for _, page in pairs(pages) do page:SetWidth(initialContentWidth) end

    local function AddHeading(page, y, text, description)
        local heading = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        heading:SetPoint("TOPLEFT", 4, -y)
        heading:SetText(text)
        heading:SetTextColor(unpack(colors.text))
        local detail = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        detail:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -5)
        detail:SetPoint("RIGHT", page, "RIGHT", -8, 0)
        detail:SetJustifyH("LEFT")
        detail:SetText(description or "")
        detail:SetTextColor(unpack(colors.muted))
        return y + 48
    end
    local function AddRowLabel(page, y, text, detail)
        local label = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("TOPLEFT", 8, -y)
        label:SetText(text)
        if detail then
            local hint = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            hint:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -3)
            hint:SetText(detail)
            return y + 46
        end
        return y + 34
    end
    local function AddCheck(page, y, text, getValue, setValue)
        local check = AddCheckbox(page)
        check:SetPoint("TOPLEFT", 4, -y)
        local label = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT", check, "RIGHT", 8, 0)
        label:SetText(text)
        check:SetHitRectInsets(-4, -(label:GetStringWidth() or 0) - 12, -5, -5)
        check:SetScript("OnClick", function(self)
            setValue(self:GetChecked() and true or false)
        end)
        check.Refresh = function() check:SetChecked(getValue() and true or false) end
        return y + 32, check
    end
    local function CreateMenuItem(text, checked, callback, keepOpen)
        local info = UIDropDownMenu_CreateInfo()
        info.text = text
        info.checked = checked
        info.keepShownOnClick = keepOpen
        info.func = callback
        UIDropDownMenu_AddButton(info)
    end
    local function SetPage(pageID)
        for id, page in pairs(pages) do
            page:SetShown(id == pageID)
            SetSelected(navButtons[id], id == pageID)
        end
        local page = pages[pageID]
        content:SetHeight(page.contentHeight or 400)
        scroll:SetVerticalScroll(0)
        UpdateScrollBar()
    end
    for _, item in ipairs(pageOrder) do
        local pageID = item.id
        navButtons[pageID]:SetScript("OnClick", function() SetPage(pageID) end)
    end

    local barPage = pages.bars
    barPage.contentHeight = AddHeading(barPage, 8, L.BarsAndGroups,
        L.GroupsHelp)

    local y
    local quickAccessPage = pages.quickAccess
    y = AddHeading(quickAccessPage, 8, L.QuickAccess, L.QuickAccessHelp)
    local minimapButtonCheck
    y, minimapButtonCheck = AddCheck(quickAccessPage, y, L.ShowMinimapButton,
        function() return db.showMinimapButton end, function(value)
            db.showMinimapButton = value
            UpdateMinimapButton()
        end)
    panel.minimapButtonCheck = minimapButtonCheck
    quickAccessPage.contentHeight = y + 30

    local unitFramesPage = pages.unitFrames
    local refreshFrameProperties = {}

    local function BuildFrameSettings()
        local modes = { { "auto", L.UnitFrameColorAuto }, { "health", L.UnitFrameColorHealth },
            { "reaction", L.UnitFrameColorReaction }, { "fixed", L.UnitFrameColorFixed } }
        local dropdown = CreateFrame("Frame", nil, unitFramesPage, "UIDropDownMenuTemplate")
        dropdown:Hide()

        local function CloseFrameDropdown()
            if UIDROPDOWNMENU_OPEN_MENU == dropdown then CloseDropDownMenus() end
        end

        local function Caption(parent, label, x, top)
            local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            text:SetPoint("TOPLEFT", x, -top)
            text:SetText(label)
            return text
        end

        local function ApplySetting(label)
            panel.unitFramePendingAction = label
            ApplyNativeUnitFrameOptions(nil, true)
        end

        local function Menu(button, items, getValue, setValue)
            local arrow = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            arrow:SetPoint("RIGHT", -8, 0)
            arrow:SetText("v")
            arrow:SetTextColor(unpack(colors.muted))
            button.label:SetPoint("BOTTOMRIGHT", -21, 0)
            local function Refresh()
                local value = getValue()
                for _, item in ipairs(items) do
                    if item[1] == value then button.label:SetText(item[2]); return end
                end
            end
            button:SetScript("OnClick", function(self)
                UIDropDownMenu_Initialize(dropdown, function()
                    for _, item in ipairs(items) do
                        local key, label = unpack(item)
                        CreateMenuItem(label, getValue() == key, function()
                            setValue(key)
                            Refresh()
                        end)
                    end
                end)
                ToggleDropDownMenu(1, nil, dropdown, self, 0, 0)
            end)
            table.insert(refreshFrameProperties, Refresh)
        end

        local function BuildHealthColor(section, unit, y)
            local function Get(property) return unitFrames.GetOption(db, unit, property) end
            local function Set(property, value)
                unitFrames.SetOption(db, unit, property, value)
                ApplySetting(L.UnitFrameHealthColor)
            end
            Caption(section, L.UnitFrameHealthColor, 12, y)
            y = y + 32
            local mode = AddButton(section, "", nil, true)
            mode:SetSize(144, 28)
            mode:SetPoint("TOPLEFT", 12, -y + 14)
            local fixed = AddButton(section, L.UnitFramePickColor, "quiet")
            fixed:SetSize(99, 28)
            fixed:SetPoint("LEFT", mode, "RIGHT", 8, 0)
            local chip = fixed:CreateTexture(nil, "ARTWORK")
            chip:SetSize(12, 12)
            chip:SetPoint("LEFT", 7, 0)
            fixed.label:ClearAllPoints()
            fixed.label:SetPoint("LEFT", chip, "RIGHT", 4, 0)

            local function RefreshSwatch()
                fixed:SetShown(Get("colorMode") == "fixed")
                chip:SetColorTexture(unitFrames.FixedColor(db, unit))
            end
            table.insert(refreshFrameProperties, RefreshSwatch)
            Menu(mode, modes, function() return Get("colorMode") end, function(value)
                Set("colorMode", value)
                RefreshSwatch()
            end)
            fixed:SetScript("OnClick", function()
                local r, g, b = unitFrames.FixedColor(db, unit)
                local previous = Get("fixedColor")
                local opening = true
                ColorPickerFrame:SetupColorPickerAndShow({ r = r, g = g, b = b, hasOpacity = false,
                    swatchFunc = function()
                        if opening then return end
                        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                        Set("fixedColor", ("%02X%02X%02X"):format(math.floor(nr * 255 + 0.5),
                            math.floor(ng * 255 + 0.5), math.floor(nb * 255 + 0.5)))
                        RefreshSwatch()
                    end,
                    cancelFunc = function()
                        Set("fixedColor", previous)
                        RefreshSwatch()
                    end,
                })
                opening = false
            end)

            return y + 24
        end

        local function BuildProperties(section, unit)
            local y = AddRowLabel(section, 8, L.UnitFrameInformation)
            local check
            y, check = AddCheck(section, y, L.UnitFrameShowIdentity, function()
                return unitFrames.GetOption(db, unit, "identity")
            end, function(value)
                unitFrames.SetOption(db, unit, "identity", value)
                ApplySetting(L.UnitFrameShowIdentity)
            end)
            table.insert(refreshFrameProperties, check.Refresh)
            return y
        end

        local barSettings = {
            health = { property = "health" },
            power = { property = "power" },
            castBar = { property = "casts", timer = true },
            swingBar = { property = "swings", timer = true },
        }
        local function BuildBarOptions(pane, unit, key, y)
            local bar = barSettings[key]
            if not bar then return y end

            local check
            y, check = AddCheck(pane, y, L.UnitFrameBarVisible, function()
                return unitFrames.GetOption(db, unit, bar.property)
            end, function(value)
                unitFrames.SetOption(db, unit, bar.property, value)
                ApplySetting(L.UnitFrameBarVisible)
            end)
            table.insert(refreshFrameProperties, check.Refresh)
            if key == "health" then y = BuildHealthColor(pane, unit, y) end
            if key == "swingBar" then
                local hint = Caption(pane, L.UnitFrameSwingDetails, 12, y)
                hint:SetPoint("RIGHT", pane, "RIGHT", -12, 0)
                hint:SetJustifyH("LEFT")
                hint:SetTextColor(unpack(colors.muted))
                y = y + 38
            end

            Caption(pane, L.UnitFrameTextFormat, 12, y)
            local selector = AddButton(pane, "", nil, true)
            selector:SetSize(185, 28)
            selector:SetPoint("TOPLEFT", 12, -y - 18)
            Menu(selector, {
                { "none", L.UnitFrameTextNone },
                { "percent", bar.timer and L.UnitFrameTextTime or L.UnitFrameShowPercents },
                { "amount", bar.timer and L.UnitFrameTextName or L.UnitFrameShowAmounts },
                { "both", L.UnitFrameTextBoth },
            }, function()
                return unitFrames.GetTextMode(db, unit, key)
            end, function(value)
                unitFrames.SetOption(db, unit, key .. "Text", value)
                ApplySetting(L.UnitFrameTextFormat)
            end)
            return y + 58
        end

        local function BuildDimensions(section, unit, contentTop)
            local targets = {}
            for _, group in ipairs(unitFrames.dimensionGroups) do
                if group.columns then
                    for _, row in ipairs(group.rows) do
                        if not row.playerOnly or unit == "player" then
                            targets[#targets + 1] = {
                                key = row.key or "frame", label = row.label or group.title,
                                fields = row.fields, labels = group.columns,
                            }
                        end
                    end
                else
                    local fields, labels = {}, {}
                    for _, row in ipairs(group.rows) do
                        fields[#fields + 1] = row.fields[1]
                        labels[#labels + 1] = row.label
                    end
                    targets[#targets + 1] = { key = "text", label = group.title, fields = fields, labels = labels }
                end
            end

            local tabs, panes, refreshes = {}, {}, {}
            local selected = "frame"
            local reset
            local function SizeSection()
                local height = math.max(11 + #targets * 28, panes[selected]:GetHeight() + 6)
                reset:SetPoint("TOPLEFT", 4, -height - 8)
                section.contentHeight = contentTop + height + 42
                if section:IsVisible() then
                    content:SetHeight(section.contentHeight)
                    UpdateScrollBar()
                end
            end
            function section.SelectedBar() return selected end
            local function Select(key)
                selected = key
                for id, tab in pairs(tabs) do
                    SetSelected(tab, id == key)
                    panes[id]:SetShown(id == key)
                end
                for _, refresh in ipairs(refreshes) do refresh() end
                SizeSection()
                panel.RefreshUnitFramePreview()
            end
            section.SelectBar = Select

            local function Control(pane, field, label, y)
                local valueLabel = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                valueLabel:SetPoint("TOPRIGHT", -12, -y)
                Caption(pane, label, 12, y)

                local slider = CreateFrame("Slider", nil, pane)
                slider:SetOrientation("HORIZONTAL")
                slider:SetPoint("TOPLEFT", 45, -y - 19)
                slider:SetPoint("TOPRIGHT", -45, -y - 19)
                slider:SetHeight(24)
                slider:EnableMouse(true)
                slider:SetMinMaxValues(field.min, field.max)
                slider:SetValueStep(1)
                slider:SetObeyStepOnDrag(true)
                slider:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
                local thumb = slider:GetThumbTexture()
                thumb:SetSize(10, 14)
                thumb:SetVertexColor(unpack(colors.accent))
                local track = slider:CreateTexture(nil, "BACKGROUND")
                track:SetPoint("LEFT")
                track:SetPoint("RIGHT")
                track:SetHeight(4)
                track:SetColorTexture(unpack(colors.border))
                local fill = slider:CreateTexture(nil, "BORDER")
                fill:SetPoint("LEFT", track, "LEFT")
                fill:SetPoint("RIGHT", thumb, "CENTER")
                fill:SetHeight(4)
                fill:SetColorTexture(unpack(colors.accent))

                local decrease = AddButton(pane, L.UnitFrameDecrease)
                local increase = AddButton(pane, L.UnitFrameIncrease)
                decrease:SetSize(25, 24)
                increase:SetSize(25, 24)
                decrease:SetPoint("RIGHT", slider, "LEFT", -7, 0)
                increase:SetPoint("LEFT", slider, "RIGHT", 7, 0)

                local function Maximum()
                    if field.auto then return math.min(field.max, unitFrames.GetOption(db, unit, "width") - 2) end
                    return field.max
                end
                local refreshing, manual, autoCheck
                local function Refresh(reset)
                    if reset then manual = nil end
                    refreshing = true
                    local stored = unitFrames.GetOption(db, unit, field.key)
                    local limit = Maximum()
                    local auto = field.auto == true and stored == 0
                    local value = auto and limit or math.min(stored, limit)
                    slider:SetMinMaxValues(field.min, limit)
                    slider:SetValue(value)
                    slider:EnableMouse(not auto)
                    slider:SetAlpha(auto and 0.45 or 1)
                    decrease:SetEnabled(not auto and value > field.min)
                    increase:SetEnabled(not auto and value < limit)
                    decrease:SetAlpha(not auto and value > field.min and 1 or 0.45)
                    increase:SetAlpha(not auto and value < limit and 1 or 0.45)
                    valueLabel:SetText(auto and L.UnitFrameAutoValue:format(value) or tostring(value))
                    if autoCheck then autoCheck.Refresh() end
                    refreshing = false
                end
                local function Change(value)
                    if not refreshing and value ~= unitFrames.GetOption(db, unit, field.key) then
                        unitFrames.SetOption(db, unit, field.key, value)
                        -- Updating the frame width also changes the limits of its individual bars.
                        if field.key == "width" then
                            for _, refresh in ipairs(refreshes) do refresh() end
                        else
                            Refresh()
                        end
                        ApplySetting(label)
                    end
                end

                slider:SetScript("OnValueChanged", function(_, value) Change(math.floor(value + 0.5)) end)
                local function Nudge(step)
                    local stored = unitFrames.GetOption(db, unit, field.key)
                    if field.auto and stored == 0 then return end
                    local value = math.min(stored, Maximum())
                    Change(math.max(field.min, math.min(Maximum(), value + step)))
                end
                decrease:SetScript("OnClick", function() Nudge(-1) end)
                increase:SetScript("OnClick", function() Nudge(1) end)
                if field.auto then
                    local tail
                    tail, autoCheck = AddCheck(pane, y + 54, L.UnitFrameAutoWidth, function()
                        return unitFrames.GetOption(db, unit, field.key) == 0
                    end, function(auto)
                        if auto then
                            manual = unitFrames.GetOption(db, unit, field.key)
                            Change(0)
                        else
                            Change(math.min(manual or Maximum(), Maximum()))
                        end
                    end)
                    y = tail - 8
                else
                    y = y + 62
                end
                refreshes[#refreshes + 1] = Refresh
                table.insert(refreshFrameProperties, Refresh)
                return y
            end

            for index, target in ipairs(targets) do
                local key = target.key
                local tab = AddSelectionRow(section, target.label)
                tab:SetSize(136, 26)
                tab.activeMark:SetHeight(20)
                tab:SetPoint("TOPLEFT", 4, -8 - (index - 1) * 28)
                tab:SetScript("OnClick", function() Select(key) end)
                tabs[key] = tab

                local pane = CreateFrame("Frame", nil, section)
                pane:SetPoint("TOPLEFT", 150, -6)
                pane:SetPoint("TOPRIGHT", -6, -6)
                ColorTexture(pane, "BACKGROUND", colors.card)
                panes[key] = pane
                local y = BuildBarOptions(pane, unit, key, 12)
                for fieldIndex, field in ipairs(target.fields) do
                    y = Control(pane, field, target.labels[fieldIndex], y)
                end
                if key == "frame" then
                    local hint = Caption(pane, L.UnitFrameDimensionsHelp, 12, y)
                    hint:SetPoint("RIGHT", pane, "RIGHT", -12, 0)
                    hint:SetJustifyH("LEFT")
                    hint:SetTextColor(unpack(colors.muted))
                    y = y + 31
                end
                pane:SetHeight(y)
                pane:SetShown(key == selected)
                SetSelected(tab, key == selected)
            end

            reset = AddButton(section, L.UnitFrameResetDimensions, "quiet")
            reset:SetSize(174, 26)
            reset:SetScript("OnClick", function()
                unitFrames.ResetDimensions(db, unit)
                for _, refresh in ipairs(refreshes) do refresh(true) end
                ApplySetting(L.UnitFrameResetDimensions)
            end)
            SizeSection()
        end

        AddHeading(unitFramesPage, 8, L.NativeUnitFrames, L.NativeUnitFramesHelp)
        local unitTabs, sectionTabs, unitViews = {}, {}, {}
        local RefreshSection
        local selectedUnit = db.showMinimalTargetFrame and not db.showMinimalPlayerFrame and "target" or "player"
        local selectedSection = "properties"
        local unitKeys = { player = "showMinimalPlayerFrame", target = "showMinimalTargetFrame" }
        local sectionTop, blizzardTop = 270, 119
        local samples = { player = { kind = "idle", percent = 50 }, target = { kind = "npc", percent = 50 } }

        local function NewSection(top)
            local section = CreateFrame("Frame", nil, unitFramesPage)
            section:SetPoint("TOPLEFT", 0, -top)
            section:SetPoint("RIGHT")
            section:SetHeight(1)
            return section
        end

        local pending = Caption(unitFramesPage, L.AfterCombat, 6, 92)
        pending:SetTextColor(unpack(colors.accent))
        pending:SetShown(unitFrameAppearancePending == true)
        panel.unitFramesStatus = pending

        local unitHeader = NewSection(blizzardTop)
        local _, compactCheck = AddCheck(unitHeader, 0, L.UseCompactFrame, function()
            return db[unitKeys[selectedUnit]]
        end, function(value)
            db[unitKeys[selectedUnit]] = value
            panel.unitFramePendingAction = L.UseCompactFrame
            ApplyNativeUnitFrameOptions()
        end)
        table.insert(refreshFrameProperties, compactCheck.Refresh)

        local previewCard = CreateFrame("Frame", nil, unitHeader)
        previewCard:SetPoint("TOPLEFT", 4, -29)
        previewCard:SetPoint("RIGHT", -6, 0)
        previewCard:SetHeight(83)
        ColorTexture(previewCard, "BACKGROUND", colors.card)
        local previewLabel = Caption(previewCard, L.UnitFramePreview, 10, 7)
        previewLabel:SetTextColor(unpack(colors.muted))
        local preview = CreateFrame("Frame", nil, previewCard)
        preview:SetPoint("CENTER", previewCard, "CENTER", 0, -7)
        local previewOutline = CreateFrame("Frame", nil, preview, "BackdropTemplate")
        previewOutline:SetFrameLevel(preview:GetFrameLevel() + 8)
        previewOutline:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        previewOutline:SetBackdropBorderColor(unpack(colors.accent))
        previewOutline:Hide()
        local place = AddButton(previewCard, L.UnitFramePlace, "quiet")
        place:SetSize(118, 23)
        place:SetPoint("TOPRIGHT", -5, -2)
        place:SetScript("OnClick", function() editHud:GetScript("OnClick")(editHud) end)

        local sampleMenus = {}
        for _, unitID in ipairs(unitFrames.units) do
            local unit = unitID
            local menu = AddButton(unitHeader, "", nil, true)
            menu:SetSize(148, 24)
            menu:SetPoint("TOPLEFT", 4, -119)
            local options = unit == "player" and {
                { "idle", L.UnitFrameSampleIdle }, { "cast", L.UnitFrameSampleCast },
            } or {
                { "npc", L.UnitFrameSampleHostile }, { "mage", L.UnitFrameSampleMageOption }, { "cast", L.UnitFrameSampleCast },
            }
            Menu(menu, options, function() return samples[unit].kind end, function(kind)
                samples[unit].kind = kind
                panel.RefreshUnitFramePreview()
            end)
            sampleMenus[unit] = menu
        end
        local sampleHealth = CreateFrame("Slider", nil, unitHeader, "OptionsSliderTemplate")
        sampleHealth:SetWidth(105)
        sampleHealth:SetPoint("TOPRIGHT", -9, -122)
        sampleHealth:SetMinMaxValues(0, 100)
        sampleHealth:SetValueStep(1)
        sampleHealth:SetObeyStepOnDrag(true)
        local sampleHealthLabel = unitHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        sampleHealthLabel:SetPoint("RIGHT", sampleHealth, "LEFT", -8, 0)
        local refreshingSample
        sampleHealth:SetScript("OnValueChanged", function(_, value)
            if refreshingSample or not samples[selectedUnit] then return end
            samples[selectedUnit].percent = math.floor(value + 0.5)
            panel.RefreshUnitFramePreview()
        end)

        local sampleButtons = {}
        for key in pairs(barSettings) do
            local bar = key
            local button = CreateFrame("Button", nil, preview)
            button:SetFrameLevel(preview:GetFrameLevel() + 9)
            AddHoverBorder(button)
            button:SetScript("OnClick", function()
                if selectedUnit == "blizzard" then return end
                CloseFrameDropdown()
                selectedSection = "dimensions"
                unitViews[selectedUnit].dimensions.SelectBar(bar)
                RefreshSection(false)
            end)
            sampleButtons[bar] = button
        end

        function panel.RefreshUnitFrameStates()
            local editing = EditModeManagerFrame and EditModeManagerFrame:IsShown()
            for _, unit in ipairs(unitFrames.units) do
                local tab = unitTabs[unit]
                if tab and tab.status then
                    local hidden = unit == "player" and db.hideNativePlayerFrame == true
                        or unit == "target" and db.hideNativeTargetFrame == true
                    local status = L.UnitFrameStatusBlizzard
                    if not editing then
                        if unitFrames.IsActive(unit) then status = L.UnitFrameStatusCompact
                        elseif hidden then status = L.UnitFrameStatusHidden end
                    end
                    tab.status:SetText(status)
                end
            end
        end

        function panel.RefreshUnitFramePreview()
            if not unitViews[selectedUnit] or not unitFramesPage:IsVisible() then return end
            local resizing = selectedSection == "dimensions"
            local selected = resizing and unitViews[selectedUnit].dimensions.SelectedBar()
            local sample = samples[selectedUnit]
            local sampleOnly = unitFrames.BuildPreview(preview, selectedUnit, db, selected, sample)
            for unit, menu in pairs(sampleMenus) do menu:SetShown(unit == selectedUnit) end
            local showHealth = preview.health:IsShown() and unitFrames.GetOption(db, selectedUnit, "colorMode") == "health"
            sampleHealth:SetShown(showHealth)
            sampleHealthLabel:SetShown(showHealth)
            if showHealth then
                refreshingSample = true
                sampleHealth:SetValue(sample.percent)
                sampleHealthLabel:SetText(L.UnitFrameSampleHealth:format(sample.percent))
                refreshingSample = false
            end
            for key, button in pairs(sampleButtons) do
                local region = preview[key]
                button:ClearAllPoints()
                button:SetAllPoints(region)
                button:SetShown(region:IsShown())
            end
            local availableWidth = math.max(64, unitFramesPage:GetWidth() - 30)
            local width, height = preview:GetWidth(), preview:GetHeight()
            preview:SetScale(math.min(1, availableWidth / width, 57 / height))
            local bar = selected and selected ~= "frame" and selected ~= "text" and preview[selected]
            previewOutline:SetShown(bar and bar:IsShown() or false)
            if previewOutline:IsShown() then
                previewOutline:ClearAllPoints()
                previewOutline:SetAllPoints(bar)
            end
            if resizing then
                local measured = bar or preview
                local format = sampleOnly and L.UnitFramePreviewHidden or L.UnitFramePreviewDimensions
                previewLabel:SetText(format:format(math.floor(measured:GetWidth() + 0.5),
                    math.floor(measured:GetHeight() + 0.5)))
            else
                previewLabel:SetText(L.UnitFramePreview)
            end
            place:SetEnabled(unitFrames.IsActive(selectedUnit))
            place:SetAlpha(unitFrames.IsActive(selectedUnit) and 1 or 0.42)
        end
        unitFramesPage:HookScript("OnSizeChanged", panel.RefreshUnitFramePreview)

        for _, unit in ipairs(unitFrames.units) do
            local properties = NewSection(sectionTop + 34)
            local dimensions = NewSection(sectionTop + 34)
            properties.contentHeight = sectionTop + 42 + BuildProperties(properties, unit)
            BuildDimensions(dimensions, unit, sectionTop + 42)
            unitViews[unit] = { properties = properties, dimensions = dimensions }
        end

        local blizzard = NewSection(blizzardTop)
        local y = AddHeading(blizzard, 0, L.BlizzardUnitFrames, L.BlizzardUnitFramesHelp)
        for _, entry in ipairs({ { L.HideNativePlayerFrame, "hideNativePlayerFrame" },
            { L.HideNativeTargetFrame, "hideNativeTargetFrame" } }) do
            local label, key = unpack(entry)
            local check
            y, check = AddCheck(blizzard, y, label, function() return db[key] end, function(value)
                db[key] = value
                ApplyNativeUnitFrameOptions()
            end)
            table.insert(refreshFrameProperties, check.Refresh)
        end
        blizzard.contentHeight = blizzardTop + y + 16

        RefreshSection = function(resetScroll)
            local showCompact = selectedUnit ~= "blizzard"
            for id, button in pairs(unitTabs) do SetSelected(button, id == selectedUnit) end
            for id, button in pairs(sectionTabs) do
                button:SetShown(showCompact)
                SetSelected(button, id == selectedSection)
            end
            for id, sections in pairs(unitViews) do
                for key, section in pairs(sections) do
                    section:SetShown(id == selectedUnit and key == selectedSection)
                end
            end
            unitHeader:SetShown(showCompact)
            blizzard:SetShown(not showCompact)
            local current = showCompact and unitViews[selectedUnit][selectedSection] or blizzard
            unitFramesPage.contentHeight = current.contentHeight
            content:SetHeight(current.contentHeight)
            compactCheck.Refresh()
            panel.RefreshUnitFrameStates()
            panel.RefreshUnitFramePreview()
            if resetScroll then scroll:SetVerticalScroll(0) end
            UpdateScrollBar()
        end

        local function AddFrameTab(tabs, id, label, size, x, top, selectTab)
            local tab = AddSelectionRow(unitFramesPage, label)
            local unit = id == "player" or id == "target"
            tab:SetSize(size, unit and 37 or 30)
            tab:SetPoint("TOPLEFT", x, -top)
            if unit then
                tab.label:ClearAllPoints()
                tab.label:SetPoint("TOPLEFT", 10, -2)
                tab.label:SetPoint("BOTTOMRIGHT", -8, 15)
                tab.status = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                tab.status:SetPoint("BOTTOMLEFT", 10, 3)
                tab.status:SetTextColor(unpack(colors.muted))
            end
            tab:SetScript("OnClick", function()
                CloseFrameDropdown()
                selectTab(id)
                RefreshSection(true)
            end)
            tabs[id] = tab
        end

        local function SelectUnit(id) selectedUnit = id end
        local function SelectSection(id) selectedSection = id end
        AddFrameTab(unitTabs, "player", L.UnitFramePlayer, 94, 4, 51, SelectUnit)
        AddFrameTab(unitTabs, "target", L.UnitFrameTarget, 94, 102, 51, SelectUnit)
        AddFrameTab(unitTabs, "blizzard", L.UnitFrameBlizzardTab, 94, 200, 51, SelectUnit)
        AddFrameTab(sectionTabs, "properties", L.UnitFrameOptions, 108, 4, sectionTop, SelectSection)
        AddFrameTab(sectionTabs, "dimensions", L.UnitFrameDimensions, 108, 116, sectionTop, SelectSection)
        unitFramesPage:HookScript("OnShow", function() RefreshSection(false) end)
        unitFramesPage:HookScript("OnHide", CloseFrameDropdown)
    end

    BuildFrameSettings()

    local questPage = pages.quests
    y = AddHeading(questPage, 8, L.Quests,
        L.QuestsHelp)
    local hideQuestTrackerCheck
    y, hideQuestTrackerCheck = AddCheck(questPage, y, L.HideQuestTracker,
        function() return db.hideBlizzardQuestTracker end, function(value)
            db.hideBlizzardQuestTracker = value
            ApplyQuestTrackerVisibility()
        end)
    local questTrackerStatus = questPage:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    questTrackerStatus:SetPoint("TOPLEFT", 28, -y)
    questTrackerStatus:SetText(L.AfterCombat)
    questTrackerStatus:SetTextColor(unpack(colors.accent))
    questTrackerStatus:SetShown(questTrackerPending and true or false)
    panel.questTrackerStatus = questTrackerStatus
    questPage.contentHeight = y + 30

    local performancePage = pages.performance
    y = AddHeading(performancePage, 8, L.Performance,
        L.PerformanceHelp)
    local performanceChecks = {}
    local function AddPerformanceCheck(key, label)
        y, performanceChecks[key] = AddCheck(performancePage, y, label,
            function() return db[key] end, function(value)
                db[key] = value
                UpdatePerformance()
            end)
    end
    AddPerformanceCheck("showPerformance", L.ShowPerformance)
    AddPerformanceCheck("showFPS", L.ShowFPS)
    AddPerformanceCheck("showHome", L.ShowHomeLatency)
    AddPerformanceCheck("showWorld", L.ShowWorldLatency)
    y = AddRowLabel(performancePage, y + 8, L.DisplaySize)
    local scaleSlider = CreateFrame("Slider", nil, performancePage, "OptionsSliderTemplate")
    scaleSlider:SetPoint("TOPLEFT", 8, -y)
    scaleSlider:SetWidth(math.max(220, math.min(360, content:GetWidth() - 70)))
    scaleSlider:SetMinMaxValues(0.75, 1.5)
    scaleSlider:SetValueStep(0.05)
    scaleSlider:SetObeyStepOnDrag(true)
    local scaleLabel = performancePage:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scaleLabel:SetPoint("LEFT", scaleSlider, "RIGHT", 12, 0)
    scaleLabel:SetTextColor(unpack(colors.accent))
    scaleSlider:SetScript("OnValueChanged", function(_, value)
        SavePerformancePosition(performance)
        db.performanceScale = math.floor(value * 20 + 0.5) / 20
        performance:SetScale(db.performanceScale)
        PositionPerformance()
        scaleLabel:SetText(string.format("%.0f%%", db.performanceScale * 100))
    end)
    local moveButton = AddButton(performancePage, L.MoveOrLockDisplay)
    moveButton:SetSize(174, 28)
    moveButton:SetPoint("TOPLEFT", 8, -y - 40)
    moveButton:SetScript("OnClick", function()
        panel:Hide()
        TogglePerformanceMover()
    end)
    local resetButton = AddButton(performancePage, L.ResetPosition)
    resetButton:SetSize(152, 28)
    if initialContentWidth >= 360 then
        resetButton:SetPoint("LEFT", moveButton, "RIGHT", 8, 0)
    else
        resetButton:SetPoint("TOPLEFT", moveButton, "BOTTOMLEFT", 0, -8)
    end
    resetButton:SetScript("OnClick", ResetPerformancePosition)
    performancePage.contentHeight = y + 110

    local barPreview = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    barPreview:SetFrameStrata("HIGH")
    barPreview:EnableMouse(false)
    barPreview:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    barPreview:SetBackdropBorderColor(unpack(colors.accent))
    barPreview:Hide()

    local function PreviewBar(name)
        barPreview:Hide()
        local frame = _G[name]
        if not frame or not frame:IsVisible() then return end
        local left, bottom, width, height = frame:GetRect()
        if not left or not bottom or not width or not height or width <= 0 or height <= 0 then return end
        local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
        barPreview:ClearAllPoints()
        barPreview:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * scale - 3, bottom * scale - 3)
        barPreview:SetSize(width * scale + 6, height * scale + 6)
        barPreview:Show()
    end

    local undoGroupChange
    local undoButton = AddButton(barPage, L.Undo, "primary")
    undoButton:SetSize(82, 24)
    undoButton:SetPoint("TOPRIGHT", -4, -4)
    undoButton:Hide()
    local groupNotice = barPage:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    groupNotice:SetPoint("TOPLEFT", 4, -42)
    groupNotice:SetPoint("TOPRIGHT", barPage, "TOPRIGHT", -4, -42)
    groupNotice:SetJustifyH("LEFT")
    groupNotice:SetTextColor(unpack(colors.accent))

    local function SetGroupUndo(message, action)
        undoGroupChange = action
        undoButton:SetShown(action ~= nil)
        groupNotice:SetText(message or "")
    end

    undoButton:SetScript("OnClick", function()
        if not undoGroupChange then return end
        undoGroupChange()
        SetGroupUndo(L.ChangeUndone)
        RefreshGroupUI()
    end)

    local selectorWidth = initialContentWidth < 435 and 106 or 142
    local selectorStartY = 64
    local groupRowHeight = 34
    local editorLeft = selectorWidth + 12
    local editorInset = 12

    local groupListTitle = barPage:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    groupListTitle:SetPoint("TOPLEFT", 4, -selectorStartY - 8)
    groupListTitle:SetText(L.Groups)
    groupListTitle:SetTextColor(unpack(colors.muted))

    local addGroup = AddButton(barPage, L.CreateGroup, "primary")
    addGroup:SetSize(66, 24)
    addGroup:SetPoint("TOPRIGHT", barPage, "TOPLEFT", selectorWidth, -selectorStartY)

    local selectedGroupID
    local groupNameInput
    local groupButtons = {}
    for id = 1, 8 do
        local button = AddSelectionRow(barPage, L.GroupName:format(id))
        button:SetSize(selectorWidth, 30)
        button:SetScript("OnClick", function()
            groupNameInput:ClearFocus()
            selectedGroupID = id
            RefreshGroupUI()
        end)
        groupButtons[id] = button
    end

    local groupEditor = CreateFrame("Frame", nil, barPage, "BackdropTemplate")
    groupEditor:SetPoint("TOPLEFT", editorLeft, -selectorStartY)
    groupEditor:SetPoint("RIGHT", barPage, "RIGHT", -4, 0)
    groupEditor:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    groupEditor:SetBackdropColor(unpack(colors.card))
    groupEditor:SetBackdropBorderColor(unpack(colors.border))

    local nameLabel = groupEditor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameLabel:SetPoint("TOPLEFT", editorInset, -14)
    nameLabel:SetText(L.GroupNameLabel)
    nameLabel:SetTextColor(unpack(colors.muted))

    groupNameInput = CreateFrame("EditBox", nil, groupEditor)
    groupNameInput:SetPoint("TOPLEFT", editorInset, -32)
    groupNameInput:SetPoint("TOPRIGHT", groupEditor, "TOPRIGHT", -80, -32)
    groupNameInput:SetHeight(26)
    groupNameInput:SetFontObject(GameFontHighlight)
    groupNameInput:SetTextInsets(8, 8, 0, 0)
    groupNameInput:SetMaxLetters(32)
    groupNameInput:SetAutoFocus(false)
    ColorTexture(groupNameInput, "BACKGROUND", colors.row)

    local saveNameButton = AddButton(groupEditor, L.Save, "quiet")
    saveNameButton:SetSize(68, 26)
    saveNameButton:SetPoint("LEFT", groupNameInput, "RIGHT", 4, 0)

    local function SaveGroupName()
        local id = selectedGroupID
        if not id then return end
        local input = groupNameInput:GetText()
        local value = CleanGroupName(input)
        if not value and input:match("%S") then
            groupNameInput:SetText(GroupDisplayName(id))
            groupNameInput:ClearFocus()
            return
        end
        if value == L.GroupName:format(id) then value = nil end
        if value ~= db.groupNames[id] then
            db.groupNames[id] = value
            SetGroupUndo()
        end
        groupNameInput:ClearFocus()
        RefreshGroupUI()
    end
    groupNameInput:SetScript("OnEnterPressed", SaveGroupName)
    groupNameInput:SetScript("OnEscapePressed", function(self)
        self:SetText(GroupDisplayName(selectedGroupID))
        self:ClearFocus()
    end)
    saveNameButton:SetScript("OnClick", SaveGroupName)
    groupEditor:HookScript("OnHide", function() groupNameInput:ClearFocus() end)

    local policyLabel = groupEditor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    policyLabel:SetPoint("TOPLEFT", editorInset, -64)
    policyLabel:SetText(L.Visibility)
    policyLabel:SetTextColor(unpack(colors.muted))
    local policyButton = AddButton(groupEditor, "", nil, true)
    policyButton:SetSize(176, 28)
    policyButton.label:SetTextColor(unpack(colors.accent))
    policyButton:SetPoint("TOPLEFT", editorInset, -79)
    local policyArrow = policyButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    policyArrow:SetPoint("RIGHT", -9, 0)
    policyArrow:SetText("v")
    policyArrow:SetTextColor(unpack(colors.accent))
    local policyDropdown = CreateFrame("Frame", nil, groupEditor, "UIDropDownMenuTemplate")
    policyDropdown:Hide()
    UIDropDownMenu_Initialize(policyDropdown, function()
        local id = selectedGroupID
        if not id then return end
        for _, item in ipairs(groupPolicies) do
            local key, label = item.key, item.label
            CreateMenuItem(label, db.groups[id] == key, function()
                SetGroupUndo()
                db.groups[id] = key
                RefreshGroupUI()
            end)
        end
    end)
    policyButton:SetScript("OnClick", function(self)
        ToggleDropDownMenu(1, nil, policyDropdown, self, 0, 0)
    end)
    groupEditor:SetScript("OnHide", function()
        if UIDROPDOWNMENU_OPEN_MENU == policyDropdown then CloseDropDownMenus() end
    end)
    local deleteGroup = AddButton(groupEditor, L.DeleteGroup, "danger")
    deleteGroup:SetSize(112, 22)
    deleteGroup:SetPoint("TOPRIGHT", -8, -8)
    deleteGroup:SetScript("OnClick", function()
        local id = selectedGroupID
        if not id then return end
        local policy, customName = db.groups[id], db.groupNames[id]
        local removed = {}
        for name, assignedGroup in pairs(db.barGroups) do
            if assignedGroup == id then
                removed[name] = true
                db.barGroups[name] = nil
            end
        end
        SetGroupUndo(L.GroupDeleted:format(GroupDisplayName(id)), function()
            db.groups[id], db.groupNames[id] = policy, customName
            for name in pairs(removed) do db.barGroups[name] = id end
            selectedGroupID = id
        end)
        db.groups[id], db.groupNames[id] = nil, nil
        selectedGroupID = nil
        RefreshGroupUI()
    end)

    local availableBars = groupEditor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    availableBars:SetPoint("TOPLEFT", editorInset, -119)
    availableBars:SetText(L.Bars)
    availableBars:SetTextColor(unpack(colors.muted))
    local membershipGap = 8
    local editorWidth = initialContentWidth - editorLeft - 4
    local membershipColumns = editorWidth >= 372 and 2 or 1
    local membershipWidth =
        (editorWidth - 2 * editorInset - (membershipColumns - 1) * membershipGap) / membershipColumns
    local membershipRowsByBar = {}
    for index, barName in ipairs(names) do
        local name, label = barName, labels[index]
        local rowFrame = CreateFrame("Button", nil, groupEditor)
        local column = (index - 1) % membershipColumns
        local row = math.floor((index - 1) / membershipColumns)
        rowFrame:SetSize(membershipWidth, 30)
        rowFrame:SetPoint("TOPLEFT", editorInset + column * (membershipWidth + membershipGap),
            -135 - row * 34)
        rowFrame.bg = ColorTexture(rowFrame, "BACKGROUND", colors.row)
        AddHoverBorder(rowFrame)

        local check = AddCheckbox(rowFrame)
        check:SetPoint("LEFT", 8, 0)
        check:EnableMouse(false)
        local barLabel = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        barLabel:SetPoint("LEFT", check, "RIGHT", 8, 0)
        barLabel:SetTextColor(unpack(colors.text))
        barLabel:SetText(label)
        local stateLabel = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        stateLabel:SetPoint("RIGHT", -8, 0)
        stateLabel:SetWidth(membershipWidth * 0.44)
        stateLabel:SetJustifyH("RIGHT")
        stateLabel:SetWordWrap(false)
        stateLabel:SetTextColor(unpack(colors.muted))

        rowFrame:SetScript("OnEnter", function(self)
            local assignedGroup = GroupForBar(name)
            local action = L.ClickToAddBar
            if assignedGroup == selectedGroupID then
                action = L.ClickToRemoveBar
            elseif assignedGroup then
                action = L.ClickToMoveBar:format(GroupDisplayName(assignedGroup))
            end
            PreviewBar(name)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label)
            GameTooltip:AddLine(action, unpack(colors.muted, 1, 3))
            GameTooltip:Show()
        end)
        local function StopPreview()
            barPreview:Hide()
            GameTooltip_Hide()
        end
        rowFrame:SetScript("OnLeave", StopPreview)
        rowFrame:SetScript("OnHide", function(self)
            if GameTooltip:GetOwner() == self then StopPreview() end
        end)
        local rowData = {
            frame = rowFrame,
            state = stateLabel,
            check = check,
        }
        local function ToggleMembership()
            local id = selectedGroupID
            if not id then return end
            local previous = db.barGroups[name]
            SetGroupUndo()
            if previous == id then
                db.barGroups[name] = nil
            else
                db.barGroups[name] = id
                if previous then
                    SetGroupUndo(L.BarMoved:format(label, GroupDisplayName(id)), function()
                        db.barGroups[name] = previous
                    end)
                end
            end
            RefreshGroupUI()
        end
        rowFrame:SetScript("OnClick", ToggleMembership)
        rowFrame:HookScript("OnClick", function(self)
            if self:IsMouseOver() then self:GetScript("OnEnter")(self) end
        end)
        membershipRowsByBar[name] = rowData
    end
    local membershipRows = math.ceil(#names / membershipColumns)
    groupEditor:SetHeight(143 + membershipRows * 34)
    local emptyGroupMessage = barPage:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    emptyGroupMessage:SetPoint("TOPLEFT", groupEditor, "TOPLEFT", 12, -12)
    emptyGroupMessage:SetPoint("RIGHT", barPage, "RIGHT", -8, 0)
    emptyGroupMessage:SetJustifyH("LEFT")
    emptyGroupMessage:SetTextColor(unpack(colors.muted))
    emptyGroupMessage:SetText(L.NoGroups)
    RefreshGroupUI = function()
        if not selectedGroupID or not db.groups[selectedGroupID] then
            selectedGroupID = nil
            for id = 1, 8 do
                if db.groups[id] then
                    selectedGroupID = id
                    break
                end
            end
        end
        local visibleGroupIndex = 0
        for id = 1, 8 do
            local exists = db.groups[id] ~= nil
            local button = groupButtons[id]
            button:SetShown(exists)
            if exists then
                visibleGroupIndex = visibleGroupIndex + 1
                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", 0,
                    -(selectorStartY + 30 + (visibleGroupIndex - 1) * groupRowHeight))
                local memberCount = 0
                for _, name in ipairs(names) do
                    if db.barGroups[name] == id then memberCount = memberCount + 1 end
                end
                button.label:SetWordWrap(false)
                button.label:SetText(L.GroupWithCount:format(GroupDisplayName(id), memberCount))
                SetSelected(button, id == selectedGroupID)
            end
        end
        local canAddGroup = FirstAvailableGroupID() ~= nil
        addGroup:SetEnabled(canAddGroup)
        addGroup:SetAlpha(canAddGroup and 1 or 0.42)
        local hasSelection = selectedGroupID ~= nil
        groupEditor:SetShown(hasSelection)
        emptyGroupMessage:SetShown(not hasSelection)
        if hasSelection then
            groupNameInput:SetText(GroupDisplayName(selectedGroupID))
            groupNameInput:SetCursorPosition(0)
            policyButton.label:SetText(GroupPolicyText(db.groups[selectedGroupID]))
            for _, name in ipairs(names) do
                local row = membershipRowsByBar[name]
                local assignedGroup = db.barGroups[name]
                local selected = assignedGroup == selectedGroupID
                row.check:SetChecked(selected)
                local inOtherGroup = assignedGroup ~= nil and not selected
                row.state:SetText(inOtherGroup and GroupDisplayName(assignedGroup) or "")
                local background = selected and colors.activeGroupBar
                    or inOtherGroup and colors.otherGroup or colors.row
                row.frame.bg:SetColorTexture(unpack(background))
            end
        end
        barPage.contentHeight = selectorStartY + 12 + (hasSelection
            and math.max(groupEditor:GetHeight(), 30 + visibleGroupIndex * groupRowHeight) or 70)
        if barPage:IsShown() then
            content:SetHeight(barPage.contentHeight)
            UpdateScrollBar()
        end
    end
    addGroup:SetScript("OnClick", function()
        SetGroupUndo()
        selectedGroupID = CreateGroup()
        RefreshGroupUI()
    end)
    local profilePage = pages.profiles
    y = AddHeading(profilePage, 8, L.Profiles, L.ProfilesHelp)
    local sourceCharacter
    local profileMenu = CreateFrame("Frame", nil, profilePage, "UIDropDownMenuTemplate")
    profileMenu:Hide()
    local chooseProfile = AddButton(profilePage, L.ChooseCharacter, nil, true)
    chooseProfile:SetSize(230, 30)
    chooseProfile:SetPoint("TOPLEFT", 4, -y)

    local copyButton = AddButton(profilePage, L.CopySettings, "primary")
    copyButton:SetSize(170, 28)
    copyButton:SetPoint("TOPLEFT", chooseProfile, "BOTTOMLEFT", 0, -12)
    local profileStatus = profilePage:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    profileStatus:SetPoint("TOPLEFT", copyButton, "BOTTOMLEFT", 0, -10)
    profileStatus:SetPoint("RIGHT", profilePage, "RIGHT", -4, 0)
    profileStatus:SetJustifyH("LEFT")
    profileStatus:SetTextColor(unpack(colors.muted))
    profilePage.contentHeight = y + 128

    local function AvailableProfiles()
        local available = {}
        for character, saved in pairs(HUDTunerCharacterProfiles or {}) do
            if character ~= profileKey and type(character) == "string" and type(saved) == "table" then
                available[#available + 1] = character
            end
        end
        table.sort(available)
        return available
    end

    local function RefreshProfileControls(message)
        local available = AvailableProfiles()
        if sourceCharacter and not (HUDTunerCharacterProfiles and HUDTunerCharacterProfiles[sourceCharacter]) then
            sourceCharacter = nil
        end
        local canChoose = #available > 0
        local inCombat = InCombatLockdown() and true or false
        local canCopy = sourceCharacter ~= nil and not inCombat
        chooseProfile.label:SetText(sourceCharacter or L.ChooseCharacter)
        chooseProfile.label:SetWordWrap(false)
        chooseProfile:SetEnabled(canChoose)
        chooseProfile:SetAlpha(canChoose and 1 or 0.42)
        copyButton:SetEnabled(canCopy)
        copyButton:SetAlpha(canCopy and 1 or 0.42)
        profileStatus:SetText(message or (not canChoose and L.NoSavedCharacters)
            or (inCombat and L.CopyAfterCombat) or L.CopyReplacesSettings)
    end
    panel.RefreshProfileControls = RefreshProfileControls
    profilePage:SetScript("OnShow", function() RefreshProfileControls() end)
    profilePage:SetScript("OnHide", function()
        if UIDROPDOWNMENU_OPEN_MENU == profileMenu then CloseDropDownMenus() end
    end)
    UIDropDownMenu_Initialize(profileMenu, function()
        for _, character in ipairs(AvailableProfiles()) do
            local source = character
            CreateMenuItem(source, source == sourceCharacter, function()
                sourceCharacter = source
                RefreshProfileControls()
            end)
        end
    end)
    chooseProfile:SetScript("OnClick", function(self)
        ToggleDropDownMenu(1, nil, profileMenu, self, 0, 0)
    end)
    copyButton:SetScript("OnClick", function()
        local source = sourceCharacter and HUDTunerCharacterProfiles[sourceCharacter]
        if not source or InCombatLockdown() then return end

        CopyProfile(source, db)
        InitializeGroups()
        SetGroupUndo()
        selectedGroupID = nil

        PositionMinimapButton()
        UpdateMinimapButton()
        ApplyNativeUnitFrameOptions()
        ApplyQuestTrackerVisibility()
        if performance then
            performance:SetScale(db.performanceScale)
            PositionPerformance()
            UpdatePerformance()
        end
        RefreshAll()
        SaveCharacterProfile()
        RefreshProfileControls(L.SettingsCopied:format(sourceCharacter))
    end)

    RefreshAll = function()
        enabled:SetChecked(db.enabled)
        for _, refresh in ipairs(refreshFrameProperties) do refresh() end
        panel.RefreshUnitFramePreview()
        hideQuestTrackerCheck.Refresh()
        minimapButtonCheck.Refresh()
        for _, check in pairs(performanceChecks) do check.Refresh() end
        scaleSlider:SetValue(db.performanceScale)
        RefreshProfileControls()
        RefreshGroupUI()
    end
    panel:SetScript("OnShow", RefreshAll)
    table.insert(UISpecialFrames, "ForeverHoverBarsOptions")
    SetPage("bars")
    RefreshAll()
    panel:Hide()
end
controller:RegisterEvent("ADDON_LOADED")
controller:RegisterEvent("PLAYER_LOGOUT")
controller:RegisterEvent("PLAYER_LOGIN")
controller:RegisterEvent("PLAYER_ENTERING_WORLD")
controller:RegisterEvent("PLAYER_REGEN_DISABLED")
controller:RegisterEvent("PLAYER_REGEN_ENABLED")
controller:SetScript("OnEvent", function(_, event, loaded)
    if event == "ADDON_LOADED" and loaded == addonName then
        if type(HUDTunerCharacterProfiles) ~= "table" then HUDTunerCharacterProfiles = {} end
        ForeverHoverBarsDB = ForeverHoverBarsDB or {}
        db = ForeverHoverBarsDB
        if type(db.hideBlizzardQuestTracker) ~= "boolean" then
            db.hideBlizzardQuestTracker = false
        end
        if db.enabled == nil then db.enabled = true end
        if type(db.showMinimapButton) ~= "boolean" then db.showMinimapButton = true end
        if type(db.minimapButtonAngle) ~= "number" or db.minimapButtonAngle ~= db.minimapButtonAngle
            or math.abs(db.minimapButtonAngle) == math.huge then
            db.minimapButtonAngle = 225
        end

        if type(db.showPerformance) ~= "boolean" then db.showPerformance = true end
        for _, key in ipairs(performanceMetrics) do
            if type(db[key]) ~= "boolean" then db[key] = true end
        end
        local scale = db.performanceScale
        if type(scale) ~= "number" or scale ~= scale or scale < 0.75 or scale > 1.5 then
            db.performanceScale = 1
        end
        for _, key in ipairs({ "performanceX", "performanceY" }) do
            local value = db[key]
            if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
                db[key] = nil
            end
        end
        InitializeGroups()
        for key, value in pairs(hoverValues) do db[key] = value end
        CreateMinimapButton()
    end
    if event == "PLAYER_LOGOUT" then
        SaveCharacterProfile()
        return
    end
    if event == "PLAYER_LOGIN" then
        CreateMinimapButton()
        local character, realm = UnitFullName("player")
        if character then
            if not realm or realm == "" then realm = GetRealmName() end
            profileKey = realm and realm ~= "" and character .. "-" .. realm or character
        end
        CreatePerformance()
    end
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED" then
        ApplyNativeUnitFrameOptions()
    end
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD"
        or event == "PLAYER_REGEN_ENABLED"
        or (event == "ADDON_LOADED" and loaded == "Blizzard_ObjectiveTracker") then
        ApplyQuestTrackerVisibility()
    end
    DiscoverBars()
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        if panel and panel.RefreshProfileControls then panel.RefreshProfileControls() end
        if event == "PLAYER_REGEN_DISABLED" and hudEditor and hudEditor:IsShown() then
            hudEditor:Hide()
            Notify(L.EditHUDCombatCanceled)
        end
        local inCombat = event == "PLAYER_REGEN_DISABLED"
        local hoveredGroups = {}
        if inCombat and db.enabled then
            for name, state in pairs(bars) do
                local groupID = GroupForBar(name)
                if state.frame:IsShown() and groupID
                    and db.groups[groupID] == "hideInCombat" and Hovered(state.frame) then
                    hoveredGroups[groupID] = true
                end
            end
        end
        for name, state in pairs(bars) do
            local groupID = GroupForBar(name)
            if db.enabled and groupID and db.groups[groupID] == "hideInCombat" then
                if inCombat then
                    if hoveredGroups[groupID] then
                        state.lastHover = GetTime()
                        state.frame:SetAlpha(1)
                    else
                        state.lastHover = GetTime() - db.hideDelay - 1
                        state.frame:SetAlpha(0)
                    end
                else
                    state.lastHover = GetTime()
                    state.frame:SetAlpha(1)
                end
            end
        end
    end

end)
controller:SetScript("OnUpdate", function(_, elapsed)
    if not db then return end
    local now = GetTime()
    local editing = EditModeManagerFrame and EditModeManagerFrame:IsShown()

    local binding = QuickKeybindFrame and QuickKeybindFrame:IsShown()
    local spellbook = (PlayerSpellsFrame and PlayerSpellsFrame:IsShown())
        or (SpellBookFrame and SpellBookFrame:IsShown())
    local groupHover = {}
    for name, state in pairs(bars) do
        if state.frame:IsShown() and Hovered(state.frame) then
            state.lastHover = now
            local groupID = GroupForBar(name)
            if groupID then groupHover[groupID] = true end
        end
    end
    for name, state in pairs(bars) do
        local groupID = GroupForBar(name)
        local policy = groupID and db.groups[groupID]
        if groupID and groupHover[groupID] then state.lastHover = now end
        if not groupID or not db.enabled then
            state.frame:SetAlpha(state.originalAlpha)
        elseif policy == "alwaysHidden" and not editing and not binding then
            state.frame:SetAlpha(0)
        elseif spellbook then
            -- Reveal immediately for placing spells, then use the normal hide delay on close.
            state.lastHover = now
            state.frame:SetAlpha(1)
        elseif state.frame:IsShown() then
            if policy == "alwaysVisible" then
                Fade(state, 1, elapsed)
            elseif policy == "hover" then
                local visible = editing or binding or now - state.lastHover <= db.hideDelay
                Fade(state, visible and 1 or db.minAlpha, elapsed)
            elseif policy == "hideInCombat" then
                local visible = not InCombatLockdown()
                    or editing or binding or now - state.lastHover <= db.hideDelay
                Fade(state, visible and 1 or db.minAlpha, elapsed)
            elseif policy == "alwaysHidden" and (editing or binding) then
                Fade(state, 1, elapsed)
            end
        end
    end
end)
SLASH_FOREVERHOVERBARS1 = "/fhb"
SLASH_FOREVERHOVERBARS2 = "/foreverhud"
SlashCmdList.FOREVERHOVERBARS = function(message)
    if not db then return end
    if hudEditor and hudEditor:IsShown() then
        hudEditor:Hide()
        return
    end
    message = (message or ""):lower():match("^%s*(.-)%s*$")
    if message == "tooltip" or message == "tooltip reset" then
        Notify(L.NativeTooltips)
    elseif message == "rendimiento" or message == "performance" then
        TogglePerformanceMover()
    elseif message == "rendimiento reset" or message == "performance reset" then
        ResetPerformancePosition()
    elseif message == "toggle" then
        db.enabled = not db.enabled
        Notify(db.enabled and L.HoverEnabled or L.BarsVisible)
    else
        ToggleOptions()
    end
end
