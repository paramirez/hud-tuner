local addonName = ...
local controller = CreateFrame("Frame")
local bars, panel = {}
local RefreshGroupUI
local CreateOptions
local hoverValues = { fadeIn = 0.25, fadeOut = 0.5, hideDelay = 0.3, minAlpha = 0 }
local names = {
    "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight",
    "MultiBarRight", "MultiBarLeft", "MultiBar5", "MultiBar6", "MultiBar7",
    "PetActionBar", "StanceBar", "BagsBar", "MicroMenu",
}
local labels = {
    "Barra 1", "Barra 2", "Barra 3", "Barra 4", "Barra 5",
    "Barra 6", "Barra 7", "Barra 8", "Mascota", "Posturas", "Mochilas", "Micromenu",
}
local db
local playerPortrait
local targetPortrait
local targetPortraitWatching
local minimapButton
local targetFrameHooked
local wasEditing
local playerMover
local targetMover
local levelMover
local ApplyPlayerPortrait
local targetMouseStates = {}
local function SetTargetFrameMouse(frame, enabled)
    if not frame then return end
    if targetMouseStates[frame] == nil and frame.IsMouseEnabled then
        targetMouseStates[frame] = frame:IsMouseEnabled()
    end
    if enabled then
        if targetMouseStates[frame] and frame.EnableMouse then frame:EnableMouse(true) end
    elseif frame.EnableMouse then
        frame:EnableMouse(false)
    end
    for _, child in ipairs({ frame:GetChildren() }) do
        SetTargetFrameMouse(child, enabled)
    end
end
local function SetClassIcon(texture, unit)
    local _, class = UnitClass(unit)
    local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if coords then
        texture:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
        texture:SetTexCoord(unpack(coords))
    elseif class and texture.SetAtlas then
        texture:SetAtlas("classicon-" .. class:lower(), true)
    else
        texture:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        texture:SetTexCoord(0, 1, 0, 1)
    end
end
local function PositionLevelBadge(button)
    if not button or not button.levelBadge then return end
    button.levelBadge:ClearAllPoints()
    button.levelBadge:SetPoint("BOTTOM", button, "BOTTOM",
        db and db.levelOffsetX or 0, db and db.levelOffsetY or -3)
end
local function UpdatePortraitLevel(button, unit)
    if not button then return end
    if not button.levelBadge then
        local badge = CreateFrame("Frame", nil, button)
        badge:SetFrameLevel(button:GetFrameLevel() + 5)
        badge:SetHeight(15)
        local bg = badge:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.025, 0.035, 0.055, 0.94)
        local border = {}
        for i = 1, 4 do
            border[i] = badge:CreateTexture(nil, "BORDER")
            border[i]:SetColorTexture(0.82, 0.64, 0.3, 1)
        end
        border[1]:SetPoint("TOPLEFT"); border[1]:SetPoint("TOPRIGHT"); border[1]:SetHeight(1)
        border[2]:SetPoint("BOTTOMLEFT"); border[2]:SetPoint("BOTTOMRIGHT"); border[2]:SetHeight(1)
        border[3]:SetPoint("TOPLEFT"); border[3]:SetPoint("BOTTOMLEFT"); border[3]:SetWidth(1)
        border[4]:SetPoint("TOPRIGHT"); border[4]:SetPoint("BOTTOMRIGHT"); border[4]:SetWidth(1)
        local text = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("CENTER")
        text:SetTextColor(1, 0.91, 0.68, 1)
        button.levelBadge = badge
        button.levelText = text
    end
    PositionLevelBadge(button)
    local level = UnitLevel and UnitLevel(unit)
    local label = (not level or level < 1) and "??" or tostring(level)
    button.levelText:SetText(label)
    local fontSize = math.max(9, math.min(13, button:GetWidth() * 0.25))
    button.levelText:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")
    button.levelBadge:SetWidth(math.max(21, button.levelText:GetStringWidth() + 8))
    button.levelBadge:Show()
end
local function UpdateLevelBadgePositions()
    PositionLevelBadge(playerPortrait)
    PositionLevelBadge(targetPortrait)
end
local function ToggleLevelMover()
    if InCombatLockdown() then
        print("ForeverHoverBars: mueve el texto fuera de combate.")
        return
    end
    if levelMover and levelMover:IsShown() then
        levelMover:StopMovingOrSizing()
        levelMover.dragging = false
        local icon = levelMover.anchorIcon
        if icon and icon.levelBadge then
            local mx, my = levelMover:GetCenter()
            local ix, iy = icon:GetCenter()
            local moverScale = levelMover:GetEffectiveScale() / UIParent:GetEffectiveScale()
            local iconScale = icon:GetEffectiveScale() / UIParent:GetEffectiveScale()
            if mx and my and ix and iy then
                db.levelOffsetX = mx * moverScale - ix * iconScale
                db.levelOffsetY = my * moverScale
                    - (iy - icon:GetHeight() / 2) * iconScale
            end
        end
        levelMover:Hide()
        UpdateLevelBadgePositions()
        print("ForeverHoverBars: posicion del nivel guardada.")
        return
    end
    local icon = playerPortrait and playerPortrait:IsShown() and playerPortrait
        or targetPortrait and targetPortrait:IsShown() and targetPortrait
    if not icon or not icon.levelBadge then
        print("ForeverHoverBars: activa el icono del jugador o del objetivo primero.")
        return
    end
    if not levelMover then
        levelMover = CreateFrame("Frame", "ForeverHoverBarsLevelMover", UIParent)
        levelMover:SetFrameStrata("DIALOG")
        levelMover:EnableMouse(true)
        levelMover:SetMovable(true)
        levelMover:SetClampedToScreen(true)
        levelMover:RegisterForDrag("LeftButton")
        local bg = levelMover:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.55, 0.42, 0.23, 0.62)
        local label = levelMover:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("CENTER")
        label:SetText("Nivel: arrastra")
        levelMover:SetScript("OnDragStart", function(self)
            if not InCombatLockdown() then
                self:StartMoving()
                self.dragging = true
            end
        end)
        levelMover:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            self.dragging = false
        end)
        levelMover:SetScript("OnMouseUp", function(_, button)
            if button == "RightButton" then ToggleLevelMover() end
        end)
        levelMover:SetScript("OnUpdate", function(self)
            local anchor = self.anchorIcon
            if not self.dragging or not anchor then return end
            local mx, my = self:GetCenter()
            local ix, iy = anchor:GetCenter()
            local moverScale = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
            local iconScale = anchor:GetEffectiveScale() / UIParent:GetEffectiveScale()
            if mx and my and ix and iy then
                db.levelOffsetX = mx * moverScale - ix * iconScale
                db.levelOffsetY = my * moverScale
                    - (iy - anchor:GetHeight() / 2) * iconScale
                UpdateLevelBadgePositions()
            end
        end)
    end
    levelMover.anchorIcon = icon
    levelMover:ClearAllPoints()
    levelMover:SetSize(58, 22)
    levelMover:SetPoint("CENTER", icon.levelBadge, "CENTER")
    levelMover:Show()
    print("ForeverHoverBars: arrastra el texto azul; clic derecho para guardar.")
end
local function PositionPlayerPortrait(x, y)
    if not playerPortrait then return end
    playerPortrait:ClearAllPoints()
    if x and y then
        playerPortrait:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    else
        playerPortrait:SetPoint("CENTER", PlayerFrame, "CENTER")
    end
end
local function PositionTargetPortrait(x, y)
    if not targetPortrait then return end
    targetPortrait:ClearAllPoints()
    if x and y then
        targetPortrait:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    else
        targetPortrait:SetPoint("CENTER", TargetFrame, "CENTER")
    end
end
local function SavePlayerMoverPosition()
    if not playerMover or not playerMover:IsShown() then return end
    playerMover:StopMovingOrSizing()
    playerMover.dragging = false
    local x, y = playerMover:GetCenter()
    if x and y then
        local scale = playerMover:GetEffectiveScale() / UIParent:GetEffectiveScale()
        db.playerPortraitX, db.playerPortraitY = x * scale, y * scale
    end
    PositionPlayerPortrait(db.playerPortraitX, db.playerPortraitY)
    playerMover:Hide()
    if playerMover.controls then playerMover.controls:Hide() end
    print("ForeverHoverBars: posicion del icono del jugador guardada.")
end
local function TogglePlayerMover()
    if InCombatLockdown() then
        print("ForeverHoverBars: mueve el icono fuera de combate.")
        return
    end
    db.hidePlayerFrame = true
    ApplyPlayerPortrait()
    if playerMover and playerMover:IsShown() then
        SavePlayerMoverPosition()
        return
    end
    if not playerMover then
        playerMover = CreateFrame("Frame", "ForeverHoverBarsPlayerMover", UIParent)
        playerMover:SetFrameStrata("DIALOG")
        playerMover:EnableMouse(true)
        playerMover:SetMovable(true)
        playerMover:SetClampedToScreen(true)
        playerMover:RegisterForDrag("LeftButton")
        local bg = playerMover:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.55, 0.42, 0.23, 0.55)
        local label = playerMover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("CENTER")
        label:SetText("ARRASTRA PARA MOVER")
        playerMover:SetScript("OnDragStart", function(self)
            if not InCombatLockdown() then
                self:StartMoving()
                self.dragging = true
            end
        end)
        playerMover:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            self.dragging = false
            local x, y = self:GetCenter()
            if x and y then
                local scale = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
                db.playerPortraitX, db.playerPortraitY = x * scale, y * scale
            end
            PositionPlayerPortrait(db.playerPortraitX, db.playerPortraitY)
        end)
        playerMover:SetScript("OnUpdate", function(self)
            if self.dragging then
                local x, y = self:GetCenter()
                if x and y then
                    local scale = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
                    PositionPlayerPortrait(x * scale, y * scale)
                end
            end
        end)

        local controls = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        controls:SetSize(224, 166)
        controls:SetPoint("TOP", UIParent, "TOP", 0, -110)
        controls:SetFrameStrata("DIALOG")
        controls:SetFrameLevel(playerMover:GetFrameLevel() + 2)
        controls:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        controls:SetBackdropColor(0.04, 0.06, 0.10, 0.96)
        controls:EnableMouse(true)
        local title = controls:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -12)
        title:SetText("Colocar icono del jugador")
        local hint = controls:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hint:SetPoint("TOP", title, "BOTTOM", 0, -4)
        hint:SetText("Arrastra el icono o usa las flechas")

        local step = 1
        local stepButton = CreateFrame("Button", nil, controls, "UIPanelButtonTemplate")
        stepButton:SetSize(58, 24)
        stepButton:SetPoint("BOTTOMLEFT", 12, 12)
        stepButton:SetText("Paso: 1")
        stepButton:SetScript("OnClick", function(self)
            step = step == 1 and 5 or (step == 5 and 15 or 1)
            self:SetText("Paso: " .. step)
        end)
        local function Nudge(dx, dy)
            local x, y = playerMover:GetCenter()
            if not x or not y then return end
            local scale = playerMover:GetEffectiveScale() / UIParent:GetEffectiveScale()
            x, y = x * scale + dx * step, y * scale + dy * step
            playerMover:ClearAllPoints()
            playerMover:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
            PositionPlayerPortrait(x, y)
        end
        local function AddNudgeButton(text, x, y, dx, dy)
            local button = CreateFrame("Button", nil, controls, "UIPanelButtonTemplate")
            button:SetSize(32, 28)
            button:SetPoint("BOTTOM", controls, "BOTTOM", x, y)
            button:SetText(text)
            button:SetScript("OnClick", function() Nudge(dx, dy) end)
        end
        AddNudgeButton("↑", 0, 78, 0, 1)
        AddNudgeButton("←", -34, 49, -1, 0)
        AddNudgeButton("↓", 0, 49, 0, -1)
        AddNudgeButton("→", 34, 49, 1, 0)
        local centerButton = CreateFrame("Button", nil, controls, "UIPanelButtonTemplate")
        centerButton:SetSize(58, 24)
        centerButton:SetPoint("BOTTOMLEFT", stepButton, "BOTTOMRIGHT", 6, 0)
        centerButton:SetText("Centro")
        centerButton:SetScript("OnClick", function()
            db.playerPortraitX, db.playerPortraitY = nil, nil
            PositionPlayerPortrait()
            local x, y = playerPortrait:GetCenter()
            if x and y then
                local scale = playerPortrait:GetEffectiveScale() / UIParent:GetEffectiveScale()
                playerMover:ClearAllPoints()
                playerMover:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x * scale, y * scale)
            end
        end)
        local saveButton = CreateFrame("Button", nil, controls, "UIPanelButtonTemplate")
        saveButton:SetSize(74, 24)
        saveButton:SetPoint("BOTTOMRIGHT", -12, 12)
        saveButton:SetText("Guardar")
        saveButton:SetScript("OnClick", SavePlayerMoverPosition)
        playerMover.controls = controls
    end
    local x, y = playerPortrait:GetCenter()
    local scale = playerPortrait:GetEffectiveScale() / UIParent:GetEffectiveScale()
    playerMover:ClearAllPoints()
    playerMover:SetSize(math.max(96, playerPortrait:GetWidth() + 24), math.max(96, playerPortrait:GetHeight() + 24))
    if x and y then
        playerMover:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x * scale, y * scale)
    else
        playerMover:SetPoint("CENTER", playerPortrait, "CENTER")
    end
    playerMover:Show()
    playerMover.controls:Show()
    print("ForeverHoverBars: arrastra el icono o usa las flechas; pulsa Guardar al terminar.")
end
ApplyPlayerPortrait = function()
    if not PlayerFrame then return end
    if InCombatLockdown() then return end
    if not playerPortrait then
        playerPortrait = CreateFrame("Button", "ForeverHoverBarsPlayerPortrait", UIParent,
            "SecureUnitButtonTemplate")
        playerPortrait:SetFrameStrata("HIGH")
        playerPortrait:SetPoint("CENTER", PlayerFrame, "CENTER")
        playerPortrait:RegisterForClicks("AnyUp")
        playerPortrait:SetAttribute("unit", "player")
        playerPortrait:SetAttribute("*type1", "target")
        playerPortrait:SetAttribute("*type2", "togglemenu")
        playerPortrait.texture = playerPortrait:CreateTexture(nil, "ARTWORK")
        playerPortrait.texture:SetAllPoints()
    end
    local size = db.playerPortraitSize or 48
    playerPortrait:SetSize(size, size)
    SetClassIcon(playerPortrait.texture, "player")
    UpdatePortraitLevel(playerPortrait, "player")
    PositionPlayerPortrait(db.playerPortraitX, db.playerPortraitY)
    if db.hidePlayerFrame then
        playerPortrait:Show()
    else
        playerPortrait:Hide()
    end
    if db.hidePlayerFrame then
        PlayerFrame:Hide()
    else
        PlayerFrame:Show()
    end
end
local function ApplyTargetVisibility()
    if not TargetFrame or not db or InCombatLockdown() then return end
    if not targetFrameHooked then
        TargetFrame:HookScript("OnShow", function(frame)
            local editing = EditModeManagerFrame and EditModeManagerFrame:IsShown()
            if not db or not db.hideTargetFrame or editing then return end
            frame:SetAlpha(0)
            if not InCombatLockdown() then frame:Hide() end
        end)
        targetFrameHooked = true
    end
    if db.hideTargetFrame then
        if not targetPortrait then
            targetPortrait = CreateFrame("Button", "ForeverHoverBarsTargetPortrait", UIParent,
                "SecureUnitButtonTemplate")
            targetPortrait:SetFrameStrata("HIGH")
            targetPortrait:SetPoint("CENTER", TargetFrame, "CENTER")
            targetPortrait:RegisterForClicks("AnyUp")
            targetPortrait:SetAttribute("unit", "target")
            targetPortrait:SetAttribute("*type1", "target")
            targetPortrait:SetAttribute("*type2", "togglemenu")
            targetPortrait.texture = targetPortrait:CreateTexture(nil, "ARTWORK")
            targetPortrait.texture:SetAllPoints()
        end
        local size = db.playerPortraitSize or 48
        targetPortrait:SetSize(size, size)
        SetClassIcon(targetPortrait.texture, "target")
        UpdatePortraitLevel(targetPortrait, "target")
        PositionTargetPortrait(db.targetPortraitX, db.targetPortraitY)
        local editing = EditModeManagerFrame and EditModeManagerFrame:IsShown()
        if editing then
            if targetPortraitWatching and UnregisterUnitWatch then
                UnregisterUnitWatch(targetPortrait)
                targetPortraitWatching = false
            end
            TargetFrame:SetAlpha(1)
            TargetFrame:Show()
            SetTargetFrameMouse(TargetFrame, true)
            targetPortrait:Hide()
        else
            if not targetPortraitWatching and RegisterUnitWatch then
                RegisterUnitWatch(targetPortrait)
                targetPortraitWatching = true
            end
            TargetFrame:Hide()
            SetTargetFrameMouse(TargetFrame, false)
        end
    else
        if targetPortraitWatching and UnregisterUnitWatch then
            UnregisterUnitWatch(targetPortrait)
            targetPortraitWatching = false
        end
        if targetPortrait then targetPortrait:Hide() end
        TargetFrame:SetAlpha(1)
        TargetFrame:Show()
        SetTargetFrameMouse(TargetFrame, true)
    end
end
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
        GameTooltip:SetText("ForeverHUD")
        GameTooltip:AddLine("Clic para abrir o cerrar la configuración.", 1, 1, 1)
        GameTooltip:AddLine("Arrastra para cambiar la posición.", 0.7, 0.7, 0.7)
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
        if not panel then CreateOptions() end
        panel:SetShown(not panel:IsShown())
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
local function SaveTargetMoverPosition()
    if not targetMover or not targetMover:IsShown() then return end
    targetMover:StopMovingOrSizing()
    targetMover.dragging = false
    local x, y = targetMover:GetCenter()
    if x and y then
        local scale = targetMover:GetEffectiveScale() / UIParent:GetEffectiveScale()
        db.targetPortraitX, db.targetPortraitY = x * scale, y * scale
    end
    PositionTargetPortrait(db.targetPortraitX, db.targetPortraitY)
    targetMover:Hide()
    if targetMover.controls then targetMover.controls:Hide() end
    ApplyTargetVisibility()
    print("ForeverHoverBars: posicion del icono del objetivo guardada.")
end
local function ToggleTargetMover()
    if InCombatLockdown() then
        print("ForeverHoverBars: mueve el icono del objetivo fuera de combate.")
        return
    end
    if not TargetFrame then
        print("ForeverHoverBars: el marco del objetivo aún no está disponible.")
        return
    end
    if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
        print("ForeverHoverBars: sal de Edit Mode para colocar el icono personalizado.")
        return
    end
    db.hideTargetFrame = true
    ApplyTargetVisibility()
    if targetMover and targetMover:IsShown() then
        SaveTargetMoverPosition()
        return
    end
    if not targetMover then
        targetMover = CreateFrame("Frame", "ForeverHoverBarsTargetMover", UIParent)
        targetMover:SetFrameStrata("DIALOG")
        targetMover:EnableMouse(true)
        targetMover:SetMovable(true)
        targetMover:SetClampedToScreen(true)
        targetMover:RegisterForDrag("LeftButton")
        local bg = targetMover:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.55, 0.42, 0.23, 0.55)
        local label = targetMover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("CENTER")
        label:SetText("ARRASTRA PARA MOVER")
        targetMover:SetScript("OnDragStart", function(self)
            if not InCombatLockdown() then
                self:StartMoving()
                self.dragging = true
            end
        end)
        targetMover:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            self.dragging = false
            local x, y = self:GetCenter()
            if x and y then
                local scale = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
                db.targetPortraitX, db.targetPortraitY = x * scale, y * scale
            end
            PositionTargetPortrait(db.targetPortraitX, db.targetPortraitY)
        end)
        targetMover:SetScript("OnUpdate", function(self)
            if self.dragging then
                local x, y = self:GetCenter()
                if x and y then
                    local scale = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
                    PositionTargetPortrait(x * scale, y * scale)
                end
            end
        end)

        local controls = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        controls:SetSize(224, 166)
        controls:SetPoint("TOP", UIParent, "TOP", 0, -110)
        controls:SetFrameStrata("DIALOG")
        controls:SetFrameLevel(targetMover:GetFrameLevel() + 2)
        controls:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        controls:SetBackdropColor(0.04, 0.06, 0.10, 0.96)
        controls:EnableMouse(true)
        local title = controls:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -12)
        title:SetText("Colocar icono del objetivo")
        local hint = controls:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hint:SetPoint("TOP", title, "BOTTOM", 0, -4)
        hint:SetText("Arrastra el icono o usa las flechas")
        local step = 1
        local stepButton = CreateFrame("Button", nil, controls, "UIPanelButtonTemplate")
        stepButton:SetSize(58, 24)
        stepButton:SetPoint("BOTTOMLEFT", 12, 12)
        stepButton:SetText("Paso: 1")
        stepButton:SetScript("OnClick", function(self)
            step = step == 1 and 5 or (step == 5 and 15 or 1)
            self:SetText("Paso: " .. step)
        end)
        local function Nudge(dx, dy)
            local x, y = targetMover:GetCenter()
            if not x or not y then return end
            local scale = targetMover:GetEffectiveScale() / UIParent:GetEffectiveScale()
            x, y = x * scale + dx * step, y * scale + dy * step
            targetMover:ClearAllPoints()
            targetMover:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
            PositionTargetPortrait(x, y)
        end
        local function AddNudgeButton(text, x, y, dx, dy)
            local button = CreateFrame("Button", nil, controls, "UIPanelButtonTemplate")
            button:SetSize(32, 28)
            button:SetPoint("BOTTOM", controls, "BOTTOM", x, y)
            button:SetText(text)
            button:SetScript("OnClick", function() Nudge(dx, dy) end)
        end
        AddNudgeButton("↑", 0, 78, 0, 1)
        AddNudgeButton("←", -34, 49, -1, 0)
        AddNudgeButton("↓", 0, 49, 0, -1)
        AddNudgeButton("→", 34, 49, 1, 0)
        local centerButton = CreateFrame("Button", nil, controls, "UIPanelButtonTemplate")
        centerButton:SetSize(58, 24)
        centerButton:SetPoint("BOTTOMLEFT", stepButton, "BOTTOMRIGHT", 6, 0)
        centerButton:SetText("Centro")
        centerButton:SetScript("OnClick", function()
            db.targetPortraitX, db.targetPortraitY = nil, nil
            PositionTargetPortrait()
            local x, y = targetPortrait:GetCenter()
            if x and y then
                local scale = targetPortrait:GetEffectiveScale() / UIParent:GetEffectiveScale()
                targetMover:ClearAllPoints()
                targetMover:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x * scale, y * scale)
            end
        end)
        local saveButton = CreateFrame("Button", nil, controls, "UIPanelButtonTemplate")
        saveButton:SetSize(74, 24)
        saveButton:SetPoint("BOTTOMRIGHT", -12, 12)
        saveButton:SetText("Guardar")
        saveButton:SetScript("OnClick", SaveTargetMoverPosition)
        targetMover.controls = controls
    end
    if targetPortraitWatching and UnregisterUnitWatch then
        UnregisterUnitWatch(targetPortrait)
        targetPortraitWatching = false
    end
    targetPortrait:Show()
    local x, y = targetPortrait:GetCenter()
    local scale = targetPortrait:GetEffectiveScale() / UIParent:GetEffectiveScale()
    targetMover:ClearAllPoints()
    targetMover:SetSize(math.max(96, targetPortrait:GetWidth() + 24),
        math.max(96, targetPortrait:GetHeight() + 24))
    if db.targetPortraitX and db.targetPortraitY then
        targetMover:SetPoint("CENTER", UIParent, "BOTTOMLEFT", db.targetPortraitX, db.targetPortraitY)
    elseif x and y then
        targetMover:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x * scale, y * scale)
    else
        targetMover:SetPoint("CENTER", TargetFrame, "CENTER")
    end
    targetMover:Show()
    targetMover.controls:Show()
    print("ForeverHoverBars: arrastra el icono del objetivo o usa las flechas; pulsa Guardar al terminar.")
end
local performance, performanceMoving
local performanceMetrics = {
    { key = "showFPS", label = "FPS" },
    { key = "showHome", label = "Hogar" },
    { key = "showWorld", label = "Mundo" },
}

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
        if db.showHome then parts[#parts + 1] = string.format("Hogar %d ms", home) end
        if db.showWorld then parts[#parts + 1] = string.format("Mundo %d ms", world) end
    end
    performance.label:SetText(#parts > 0 and table.concat(parts, "  |  ") or "Arrastra el visor")
    performance:SetWidth(math.max(58, performance.label:GetStringWidth() + 14))
end

local function UpdatePerformance()
    local visible = performanceMoving
        or (db.showPerformance and (db.showFPS or db.showHome or db.showWorld))
    performance:EnableMouse(performanceMoving == true)
    performance.bg:SetColorTexture(0.10, 0.085, 0.065, performanceMoving and 0.96 or 0.84)
    performance:SetShown(visible and true or false)
    if visible then SamplePerformance() end
end

local function TogglePerformanceMover()
    if performanceMoving then SavePerformancePosition(performance) end
    performanceMoving = not performanceMoving
    UpdatePerformance()
    if performanceMoving then
        print("ForeverHoverBars: arrastra el visor. Clic derecho o /fhb rendimiento para bloquear.")
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
    { key = "hover", label = "Hover" },
    { key = "alwaysVisible", label = "Siempre visible" },
    { key = "alwaysHidden", label = "Siempre oculto" },
    { key = "hideInCombat", label = "Ocultar en combate" },
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
    return "Hover"
end
local questTrackerHooked
local questTrackerHidden
local questTrackerAlpha

local function ApplyQuestTrackerVisibility()
    local tracker = ObjectiveTrackerFrame
    if not db or not tracker then return end

    local hide = db.hideBlizzardQuestTracker
    local locked = InCombatLockdown() and tracker:IsProtected()
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
    local width = math.min(900, UIParent:GetWidth() - 32)
    local height = math.min(490, UIParent:GetHeight() - 32)
    local colors = {
        window = { 0.065, 0.075, 0.095, 0.98 },
        card = { 0.087, 0.103, 0.13, 1 },
        row = { 0.107, 0.125, 0.156, 1 },
        border = { 0.22, 0.25, 0.30, 1 },
        accent = { 0.89, 0.73, 0.42, 1 },
        text = { 0.91, 0.93, 0.97, 1 },
        muted = { 0.67, 0.72, 0.80, 1 },
        selected = { 0.19, 0.17, 0.14, 1 },
        activeGroupBar = { 0.19, 0.145, 0.09, 1 },
        otherGroup = { 0.21, 0.19, 0.16, 1 },
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

    local function AddButton(parent, text, kind, leftAligned)
        local button = CreateFrame("Button", nil, parent)
        local background = kind == "primary" and colors.selected
            or (kind == "quiet" or kind == "danger") and colors.clear or colors.row
        button.bg = ColorTexture(button, "BACKGROUND", background)
        button:SetHighlightTexture(ColorTexture(button, "HIGHLIGHT", { 1, 1, 1, 0.075 }))
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
        check:GetCheckedTexture():SetAllPoints()
        check:SetHighlightTexture(ColorTexture(check, "HIGHLIGHT", { 1, 1, 1, 0.14 }))
        return check
    end

    local header = CreateFrame("Frame", nil, panel)
    header:SetPoint("TOPLEFT", 16, -2)
    header:SetPoint("TOPRIGHT", -16, -2)
    header:SetHeight(48)
    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT")
    title:SetText("ForeverHUD")
    title:SetTextColor(unpack(colors.accent))
    AddRule(header, "BOTTOMLEFT", "BOTTOMLEFT", 0, 0, width - 32, 1, unpack(colors.border))

    local close = AddButton(header, "×", "quiet")
    close:SetSize(36, 28)
    close:SetPoint("RIGHT")
    close:SetScript("OnClick", function() panel:Hide() end)

    local enabled = AddCheckbox(header)
    enabled:SetPoint("RIGHT", close, "LEFT", -6, 0)
    local enabledLabel = header:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    enabledLabel:SetPoint("RIGHT", enabled, "LEFT", -8, 0)
    enabledLabel:SetText("Visibilidad activa")
    enabledLabel:SetTextColor(unpack(colors.muted))
    enabled:SetScript("OnClick", function(self)
        db.enabled = self:GetChecked() and true or false
    end)
    panel.enabled = enabled

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
    divider:SetColorTexture(unpack(colors.border))

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
        { id = "bars", label = "Barras y grupos" },
        { id = "frames", label = "Marcos" },
        { id = "quests", label = "Misiones" },
        { id = "performance", label = "Rendimiento" },
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
    barPage.contentHeight = AddHeading(barPage, 8, "Barras y grupos",
        "Elige un grupo para editar su visibilidad y sus barras.")

    local y
    local framePage = pages.frames
    y = AddHeading(framePage, 8, "Marcos de unidad",
        "Personaliza cómo se muestran los iconos del jugador y del objetivo.")
    local hidePlayerCheck
    y, hidePlayerCheck = AddCheck(framePage, y, "Ocultar marco del jugador y usar icono",
        function() return db.hidePlayerFrame end, function(value)
            db.hidePlayerFrame = value
            ApplyPlayerPortrait()
        end)
    panel.hidePlayer = hidePlayerCheck
    local hideTargetCheck
    y, hideTargetCheck = AddCheck(framePage, y, "Ocultar marco del objetivo y usar icono",
        function() return db.hideTargetFrame end, function(value)
            db.hideTargetFrame = value
            ApplyTargetVisibility()
        end)
    panel.hideTarget = hideTargetCheck
    y = AddRowLabel(framePage, y + 8, "Tamaño del icono")
    local portraitSizeSlider = CreateFrame("Slider", nil, framePage, "OptionsSliderTemplate")
    portraitSizeSlider:SetPoint("TOPLEFT", 8, -y)
    portraitSizeSlider:SetWidth(math.max(220, math.min(360, content:GetWidth() - 70)))
    portraitSizeSlider:SetMinMaxValues(24, 120)
    portraitSizeSlider:SetValueStep(4)
    portraitSizeSlider:SetObeyStepOnDrag(true)
    local portraitSizeLabel = framePage:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    portraitSizeLabel:SetPoint("LEFT", portraitSizeSlider, "RIGHT", 12, 0)
    portraitSizeSlider:SetScript("OnValueChanged", function(_, value)
        db.playerPortraitSize = math.floor(value / 4 + 0.5) * 4
        ApplyPlayerPortrait()
        ApplyTargetVisibility()
        portraitSizeLabel:SetText(db.playerPortraitSize .. " px")
    end)
    panel.portraitSize = portraitSizeSlider
    y = y + 64
    local movePlayerPortrait = AddButton(framePage, "Colocar icono del jugador")
    movePlayerPortrait:SetSize(230, 28)
    movePlayerPortrait:SetPoint("TOPLEFT", 8, -y)
    movePlayerPortrait:SetScript("OnClick", function()
        panel:Hide()
        TogglePlayerMover()
    end)
    y = y + 38
    local moveTargetPortrait = AddButton(framePage, "Colocar icono del objetivo")
    moveTargetPortrait:SetSize(230, 28)
    moveTargetPortrait:SetPoint("TOPLEFT", 8, -y)
    moveTargetPortrait:SetScript("OnClick", function()
        panel:Hide()
        ToggleTargetMover()
    end)
    y = y + 42
    y = AddHeading(framePage, y + 8, "Acceso rápido",
        "El botón del minimapa abre o cierra esta configuración.")
    local minimapButtonCheck
    y, minimapButtonCheck = AddCheck(framePage, y, "Mostrar botón en el minimapa",
        function() return db.showMinimapButton end, function(value)
            db.showMinimapButton = value
            UpdateMinimapButton()
        end)
    panel.minimapButtonCheck = minimapButtonCheck
    framePage.contentHeight = y + 30

    local questPage = pages.quests
    y = AddHeading(questPage, 8, "Misiones",
        "Controla el rastreador de objetivos de Blizzard en pantalla.")
    local hideQuestTrackerCheck
    y, hideQuestTrackerCheck = AddCheck(questPage, y, "Ocultar rastreador de Blizzard",
        function() return db.hideBlizzardQuestTracker end, function(value)
            db.hideBlizzardQuestTracker = value
            ApplyQuestTrackerVisibility()
        end)
    questPage.contentHeight = y + 14

    local performancePage = pages.performance
    y = AddHeading(performancePage, 8, "Rendimiento",
        "Configura la información del visor y su posición en pantalla.")
    local performanceChecks = {}
    local function AddPerformanceCheck(key, label)
        y, performanceChecks[key] = AddCheck(performancePage, y, label,
            function() return db[key] end, function(value)
                db[key] = value
                UpdatePerformance()
            end)
    end
    AddPerformanceCheck("showPerformance", "Mostrar visor de rendimiento")
    AddPerformanceCheck("showFPS", "Mostrar FPS")
    AddPerformanceCheck("showHome", "Mostrar latencia de hogar")
    AddPerformanceCheck("showWorld", "Mostrar latencia de mundo")
    y = AddRowLabel(performancePage, y + 8, "Tamaño del visor")
    local scaleSlider = CreateFrame("Slider", nil, performancePage, "OptionsSliderTemplate")
    scaleSlider:SetPoint("TOPLEFT", 8, -y)
    scaleSlider:SetWidth(math.max(220, math.min(360, content:GetWidth() - 70)))
    scaleSlider:SetMinMaxValues(0.75, 1.5)
    scaleSlider:SetValueStep(0.05)
    scaleSlider:SetObeyStepOnDrag(true)
    local scaleLabel = performancePage:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scaleLabel:SetPoint("LEFT", scaleSlider, "RIGHT", 12, 0)
    scaleSlider:SetScript("OnValueChanged", function(_, value)
        SavePerformancePosition(performance)
        db.performanceScale = math.floor(value * 20 + 0.5) / 20
        performance:SetScale(db.performanceScale)
        PositionPerformance()
        scaleLabel:SetText(string.format("%.0f%%", db.performanceScale * 100))
    end)
    local moveButton = AddButton(performancePage, "Mover / bloquear visor")
    moveButton:SetSize(174, 28)
    moveButton:SetPoint("TOPLEFT", 8, -y - 40)
    moveButton:SetScript("OnClick", function()
        panel:Hide()
        TogglePerformanceMover()
    end)
    local resetButton = AddButton(performancePage, "Restaurar posición")
    resetButton:SetSize(152, 28)
    if initialContentWidth >= 360 then
        resetButton:SetPoint("LEFT", moveButton, "RIGHT", 8, 0)
    else
        resetButton:SetPoint("TOPLEFT", moveButton, "BOTTOMLEFT", 0, -8)
    end
    resetButton:SetScript("OnClick", ResetPerformancePosition)
    performancePage.contentHeight = y + 110

    local selectorWidth = initialContentWidth < 435 and 106 or 142
    local selectorStartY = 56
    local groupRowHeight = 34
    local editorLeft = selectorWidth + 12
    local editorInset = 12

    local groupListTitle = barPage:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    groupListTitle:SetPoint("TOPLEFT", 4, -selectorStartY - 8)
    groupListTitle:SetText("Grupos")
    groupListTitle:SetTextColor(unpack(colors.muted))

    local addGroup = AddButton(barPage, "+ Crear", "primary")
    addGroup:SetSize(66, 24)
    addGroup:SetPoint("TOPRIGHT", barPage, "TOPLEFT", selectorWidth, -selectorStartY)

    local selectedGroupID
    local groupButtons = {}
    for id = 1, 8 do
        local button = AddSelectionRow(barPage, "Grupo " .. id)
        button:SetSize(selectorWidth, 30)
        button:SetScript("OnClick", function()
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

    local editorTitle = groupEditor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    editorTitle:SetPoint("TOPLEFT", editorInset, -15)
    editorTitle:SetTextColor(unpack(colors.text))

    local policyLabel = groupEditor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    policyLabel:SetPoint("TOPLEFT", editorInset, -39)
    policyLabel:SetText("Visibilidad")
    policyLabel:SetTextColor(unpack(colors.muted))
    local policyButton = AddButton(groupEditor, "", nil, true)
    policyButton:SetSize(176, 28)
    policyButton:SetPoint("TOPLEFT", editorInset, -54)
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
    local deleteGroup = AddButton(groupEditor, "Eliminar grupo", "danger")
    deleteGroup:SetSize(112, 26)
    deleteGroup:SetPoint("TOPRIGHT", -8, -8)
    deleteGroup:SetScript("OnClick", function()
        local id = selectedGroupID
        if not id then return end
        for name, assignedGroup in pairs(db.barGroups) do
            if assignedGroup == id then db.barGroups[name] = nil end
        end
        db.groups[id] = nil
        selectedGroupID = nil
        RefreshGroupUI()
    end)

    local availableBars = groupEditor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    availableBars:SetPoint("TOPLEFT", editorInset, -94)
    availableBars:SetText("Barras")
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
            -110 - row * 34)
        rowFrame.bg = ColorTexture(rowFrame, "BACKGROUND", colors.row)
        rowFrame:SetHighlightTexture(ColorTexture(rowFrame, "HIGHLIGHT", { 1, 1, 1, 0.075 }))

        local check = AddCheckbox(rowFrame)
        check:SetPoint("LEFT", 8, 0)
        check:EnableMouse(false)
        local barLabel = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        barLabel:SetPoint("LEFT", check, "RIGHT", 8, 0)
        barLabel:SetTextColor(unpack(colors.text))
        barLabel:SetText(label)
        local stateLabel = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        stateLabel:SetPoint("RIGHT", -8, 0)
        stateLabel:SetTextColor(unpack(colors.muted))

        rowFrame:SetScript("OnEnter", function(self)
            local assignedGroup = GroupForBar(name)
            local action = "Clic para añadir al grupo."
            if assignedGroup == selectedGroupID then
                action = "Clic para quitar del grupo."
            elseif assignedGroup then
                action = "Clic para mover desde Grupo " .. assignedGroup .. "."
            end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label)
            GameTooltip:AddLine(action, unpack(colors.muted, 1, 3))
            GameTooltip:Show()
        end)
        rowFrame:SetScript("OnLeave", GameTooltip_Hide)
        local rowData = {
            frame = rowFrame,
            state = stateLabel,
            check = check,
        }
        local function ToggleMembership()
            local id = selectedGroupID
            if not id then return end
            if db.barGroups[name] == id then
                db.barGroups[name] = nil
            else
                db.barGroups[name] = id
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
    groupEditor:SetHeight(118 + membershipRows * 34)
    local emptyGroupMessage = barPage:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    emptyGroupMessage:SetPoint("TOPLEFT", groupEditor, "TOPLEFT", 12, -12)
    emptyGroupMessage:SetPoint("RIGHT", barPage, "RIGHT", -8, 0)
    emptyGroupMessage:SetJustifyH("LEFT")
    emptyGroupMessage:SetTextColor(unpack(colors.muted))
    emptyGroupMessage:SetText("Todavía no hay grupos. Crea uno para elegir qué barras controla.")
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
                button.label:SetText("Grupo " .. id .. " · " .. memberCount)
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
            editorTitle:SetText("Grupo " .. selectedGroupID)
            policyButton.label:SetText(GroupPolicyText(db.groups[selectedGroupID]))
            for _, name in ipairs(names) do
                local row = membershipRowsByBar[name]
                local assignedGroup = db.barGroups[name]
                local selected = assignedGroup == selectedGroupID
                row.check:SetChecked(selected)
                local inOtherGroup = assignedGroup ~= nil and not selected
                row.state:SetText(inOtherGroup and "Grupo " .. assignedGroup or "")
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
        selectedGroupID = CreateGroup()
        RefreshGroupUI()
    end)
    local function RefreshAll()
        enabled:SetChecked(db.enabled)
        hidePlayerCheck.Refresh()
        hideQuestTrackerCheck.Refresh()
        hideTargetCheck.Refresh()
        minimapButtonCheck.Refresh()
        portraitSizeSlider:SetValue(db.playerPortraitSize or 48)
        for _, check in pairs(performanceChecks) do check.Refresh() end
        scaleSlider:SetValue(db.performanceScale)
        RefreshGroupUI()
    end
    panel:SetScript("OnShow", RefreshAll)
    table.insert(UISpecialFrames, "ForeverHoverBarsOptions")
    SetPage("bars")
    RefreshAll()
    panel:Hide()
end
controller:RegisterEvent("ADDON_LOADED")
controller:RegisterEvent("PLAYER_LOGIN")
controller:RegisterEvent("PLAYER_ENTERING_WORLD")
controller:RegisterEvent("PLAYER_REGEN_DISABLED")
controller:RegisterEvent("PLAYER_REGEN_ENABLED")
controller:RegisterEvent("PLAYER_TARGET_CHANGED")
controller:RegisterEvent("UNIT_PORTRAIT_UPDATE")
controller:RegisterEvent("UNIT_LEVEL")
controller:RegisterEvent("PLAYER_LEVEL_UP")
controller:SetScript("OnEvent", function(_, event, loaded)
    if event == "ADDON_LOADED" and loaded == addonName then
        ForeverHoverBarsDB = ForeverHoverBarsDB or {}
        db = ForeverHoverBarsDB
        if type(db.hideBlizzardQuestTracker) ~= "boolean" then
            db.hideBlizzardQuestTracker = false
        end
        if db.enabled == nil then db.enabled = true end
        if type(db.hideTargetFrame) ~= "boolean" then db.hideTargetFrame = false end
        if type(db.showMinimapButton) ~= "boolean" then db.showMinimapButton = true end
        if type(db.minimapButtonAngle) ~= "number" or db.minimapButtonAngle ~= db.minimapButtonAngle
            or math.abs(db.minimapButtonAngle) == math.huge then
            db.minimapButtonAngle = 225
        end
        if type(db.hidePlayerFrame) ~= "boolean" then db.hidePlayerFrame = false end
        if type(db.playerPortraitSize) ~= "number" or db.playerPortraitSize < 24
            or db.playerPortraitSize > 120 then db.playerPortraitSize = 48 end
        if type(db.showPerformance) ~= "boolean" then db.showPerformance = true end
        for _, metric in ipairs(performanceMetrics) do
            if type(db[metric.key]) ~= "boolean" then db[metric.key] = true end
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
    if event == "PLAYER_LOGIN" then
        CreateMinimapButton()
        CreatePerformance()
        ApplyPlayerPortrait()
        ApplyTargetVisibility()
    end
    if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED" then
        ApplyPlayerPortrait()
    end
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD"
        or event == "PLAYER_REGEN_ENABLED"
        or (event == "ADDON_LOADED" and loaded == "Blizzard_ObjectiveTracker") then
        ApplyQuestTrackerVisibility()
    end
    if event == "UNIT_PORTRAIT_UPDATE" then
        if loaded == "player" then ApplyPlayerPortrait() end
        if loaded == "target" and targetPortrait then
            SetClassIcon(targetPortrait.texture, "target")
        end
    end
    if event == "UNIT_LEVEL" then
        if loaded == "player" and playerPortrait then UpdatePortraitLevel(playerPortrait, "player") end
        if loaded == "target" and targetPortrait then UpdatePortraitLevel(targetPortrait, "target") end
    elseif event == "PLAYER_LEVEL_UP" then
        if playerPortrait then UpdatePortraitLevel(playerPortrait, "player") end
        if targetPortrait then UpdatePortraitLevel(targetPortrait, "target") end
    end
    if event == "PLAYER_TARGET_CHANGED" and targetPortrait and db.hideTargetFrame then
        SetClassIcon(targetPortrait.texture, "target")
        UpdatePortraitLevel(targetPortrait, "target")
    end
    DiscoverBars()
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
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
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD"
        or event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_TARGET_CHANGED" then
        ApplyTargetVisibility()
    end
end)
controller:SetScript("OnUpdate", function(_, elapsed)
    if not db then return end
    local now = GetTime()
    local editing = EditModeManagerFrame and EditModeManagerFrame:IsShown()
    if editing ~= wasEditing then
        wasEditing = editing
        ApplyTargetVisibility()
    end
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
    message = (message or ""):lower():match("^%s*(.-)%s*$")
    if message == "level" then
        ToggleLevelMover()
    elseif message == "level reset" then
        db.levelOffsetX, db.levelOffsetY = nil, nil
        UpdateLevelBadgePositions()
        print("ForeverHoverBars: posicion original del nivel restaurada.")
    elseif message == "player" then
        TogglePlayerMover()
    elseif message == "target" then
        print("ForeverHUD: mueve el marco del objetivo con Edit Mode.")
    elseif message == "target reset" then
        print("ForeverHUD: la posición del objetivo se controla con Edit Mode.")
    elseif message == "tooltip" then
        print("ForeverHUD: las descripciones usan el anclaje nativo de Blizzard.")
    elseif message == "tooltip reset" then
        print("ForeverHUD: las descripciones usan el anclaje nativo de Blizzard.")
    elseif message == "rendimiento" then
        TogglePerformanceMover()
    elseif message == "rendimiento reset" then
        ResetPerformancePosition()
    elseif message == "toggle" then
        db.enabled = not db.enabled
        print("ForeverHoverBars: " .. (db.enabled and "hover activado" or "barras visibles"))
    else
        if not panel then CreateOptions() end
        panel:SetShown(not panel:IsShown())
    end
end
