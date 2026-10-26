pfUI:RegisterSkin("Pet Stable Master", function ()
  StripTextures(PetStableFrame)
  CreateBackdrop(PetStableFrame, nil, nil, .75)
  CreateBackdropShadow(PetStableFrame)

  PetStableFrame.backdrop:SetPoint("TOPLEFT", 10, -10)
  PetStableFrame.backdrop:SetPoint("BOTTOMRIGHT", -32, 72)
  PetStableFrame:SetHitRectInsets(10,32,10,72)
  EnableMovable(PetStableFrame)

  SkinCloseButton(PetStableFrameCloseButton, PetStableFrame.backdrop, -6, -6)

  PetStableFrame:DisableDrawLayer("BACKGROUND")

  PetStableTitleLabel:ClearAllPoints()
  PetStableTitleLabel:SetPoint("TOP", PetStableFrame.backdrop, "TOP", 0, -10)

  EnableClickRotate(PetStableModel)
  PetStableModelRotateLeftButton:Hide()
  PetStableModelRotateRightButton:Hide()

  PetStablePetInfo:ClearAllPoints()
  PetStablePetInfo:SetPoint("TOPLEFT", PetStableModel, "TOPLEFT", 10, 0)

  -- Servers differ in stable size (Turtle WoW has 4 slots), so collect
  -- every PetStableStabledPetN the client created.
  local buttons = { PetStableCurrentPet }
  local i = 1
  while _G["PetStableStabledPet"..i] do
    table.insert(buttons, _G["PetStableStabledPet"..i])
    i = i + 1
  end

  for _, button in pairs(buttons) do
    StripTextures(button)
    SkinButton(button, nil, nil, nil, _G[button:GetName().."IconTexture"])

    local b = button
    b.Enable = function()
      b:SetBackdropColor()
      b.locked = false
    end
    b.Disable = function()
      b:SetBackdropColor(1, .1, .1, .3)
      b.locked = true
    end
  end

  SkinButton(PetStablePurchaseButton)
end)
