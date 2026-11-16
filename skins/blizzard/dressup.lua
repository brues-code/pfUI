pfUI:RegisterSkin("Dress Up Frame", function ()
  local rawborder, border = GetBorderSize()
  local bpad = rawborder > 1 and border - GetPerfectPixel() or GetPerfectPixel()

  StripTextures(DressUpFrame, nil, "ARTWORK")
  CreateBackdrop(DressUpFrame, nil, nil, .75)
  CreateBackdropShadow(DressUpFrame)

  DressUpFrame.backdrop:SetPoint("TOPLEFT", 10, -10)
  DressUpFrame.backdrop:SetPoint("BOTTOMRIGHT", -32, 72)
  DressUpFrame:SetHitRectInsets(10,32,10,72)
  EnableMovable(DressUpFrame)

  SkinCloseButton(DressUpFrameCloseButton, DressUpFrame.backdrop, -6, -6)

  DressUpFrame:DisableDrawLayer("BACKGROUND")

  DressUpFrameTitleText:ClearAllPoints()
  DressUpFrameTitleText:SetPoint("TOP", DressUpFrame.backdrop, "TOP", 0, -10)

  DressUpFrameDescriptionText:ClearAllPoints()
  DressUpFrameDescriptionText:SetPoint("TOP", DressUpFrame.backdrop, "TOP", 0, -30)

  EnableModelControls(DressUpModel)
  DressUpModelRotateLeftButton:Hide()
  DressUpModelRotateRightButton:Hide()

  SkinButton(DressUpFrameCancelButton)
  SkinButton(DressUpFrameResetButton)
  DressUpFrameResetButton:ClearAllPoints()
  DressUpFrameResetButton:SetPoint("RIGHT", DressUpFrameCancelButton, "LEFT", -2*bpad, 0)

  local undress = CreateFrame("Button", "pfDressUpFrameUndressButton", DressUpFrame, "UIPanelButtonTemplate")
  undress:SetSize(80, 22)
  undress:SetText(T["Undress"])
  undress:SetPoint("RIGHT", DressUpFrameResetButton, "LEFT", -2*bpad, 0)
  undress:SetScript("OnClick", function()
    DressUpModel:Undress()
    PlaySound("gsTitleOptionOK")
  end)
  SkinButton(undress)

  -- one button per slot the model can undress, laid out like the paperdoll
  local columns = {
    { point = "TOPLEFT", x = 8, anchor = "ANCHOR_LEFT", slots = { 1, 3, 15, 5, 4, 19, 9 } },
    { point = "TOPRIGHT", x = -8, anchor = "ANCHOR_RIGHT", slots = { 10, 6, 7, 8, 16, 17 } },
  }

  local slots = {}

  local function SlotOnClick()
    DressUpModel:UndressSlot(this:GetID())
    PlaySound("gsTitleOptionOK")
  end

  local function SlotOnEnter()
    GameTooltip:SetOwner(this, this.anchor)
    GameTooltip:SetText(this.label)
    GameTooltip:AddLine(T["Click to undress"], 1, 1, 1)
    GameTooltip:Show()
  end

  for _, column in ipairs(columns) do
    for row, slot in ipairs(column.slots) do
      local _, texture, _, slotName = C_PaperDollInfo.GetInventorySlotInfoForInvSlot(slot)
      local button = CreateFrame("Button", nil, DressUpFrame)
      button:SetID(slot)
      button:SetSize(26, 26)
      button:SetPoint(column.point, DressUpFrame.backdrop, column.point, column.x, -50 - (row - 1) * 30)
      button:SetFrameLevel(DressUpModel:GetFrameLevel() + 1)
      button.anchor, button.label = column.anchor, _G[slotName:upper()]

      button.icon = button:CreateTexture(nil, "ARTWORK")
      button.icon:SetTexture(texture)
      CreateBackdrop(button)
      SetAllPointsOffset(button.backdrop, button, 0)
      HandleIcon(button.backdrop, button.icon)

      button:SetScript("OnClick", SlotOnClick)
      button:SetScript("OnEnter", SlotOnEnter)
      button:SetScript("OnLeave", GameTooltip_Hide)
      SetHighlight(button)
      table.insert(slots, button)
    end
  end

  -- the control buttons are 32px with 4px hit insets, laid out 6px into
  -- each other, so a backdrop on the hit rect leaves a 2px gap between them
  local controls = DressUpFrameModelScene.ControlFrame
  for _, key in ipairs({ "zoomInButton", "zoomOutButton", "rotateLeftButton", "rotateRightButton", "resetButton" }) do
    local button = controls[key]
    button:SetNormalTexture("")
    button:SetPushedTexture("")
    button:SetHighlightTexture("")
    CreateBackdrop(button)
    SetAllPointsOffset(button.backdrop, button, 4)
    button:SetHitRectInsets(4, 4, 4, 4)
    SetHighlight(button)
  end

  -- mounts preview in a ModelScene in place of DressUpModel; the undress
  -- buttons only act on DressUpModel
  hooksecurefunc(DressUpFrame, "SetMode", function(_, mode)
    local inPlayerMode = mode ~= "mount"
    undress:SetShown(inPlayerMode)
    for _, button in ipairs(slots) do button:SetShown(inPlayerMode) end
  end)
end)
