pfUI:RegisterModule("skin", function ()
  -- durability frame
  pfUI.durability = CreateFrame("Frame", "pfDurability", UIParent)
  if pfUI.minimap then
    pfUI.durability:SetPoint("TOPLEFT", pfUI.minimap, "BOTTOMLEFT", 0, -35)
  else
    pfUI.durability:SetPoint("LEFT", UIParent, "RIGHT", -120, 120)
  end
  UpdateMovable(pfUI.durability)
  pfUI.durability:SetWidth(80)
  pfUI.durability:SetHeight(70)
  pfUI.durability:SetFrameStrata("BACKGROUND")
  DurabilityFrame:SetParent(pfUI.durability)
  DurabilityFrame:SetAllPoints(pfUI.durability)
  DurabilityFrame:SetFrameLevel(1)
  DurabilityFrame.SetPoint = function() return end

  if C.appearance.cd.blizzard == "1" then
    hooksecurefunc("PaperDollItemSlotButton_Update", function()
      local cooldown = _G[this:GetName().."Cooldown"]
      if cooldown then cooldown.pfCooldownType = "BLIZZARD" end
    end)

    hooksecurefunc("SpellButton_UpdateButton", function()
      local cooldown = _G[this:GetName().."Cooldown"]
      if cooldown then cooldown.pfCooldownType = "BLIZZARD" end
    end)
  end

  for i = 1, UIDROPDOWNMENU_MAXLEVELS do
    CreateBackdrop(_G["DropDownList"..i.."MenuBackdrop"], nil, true, .8)
    CreateBackdropShadow(_G["DropDownList"..i.."MenuBackdrop"])

    CreateBackdrop(_G["DropDownList"..i.."Backdrop"], nil, true, .8)
    CreateBackdropShadow(_G["DropDownList"..i.."Backdrop"])
  end

  if C.global.errors_limit == "1" then
    UIErrorsFrame:SetHeight(25)
  end

  if C.global.errors_hide == "1" then
    UIErrorsFrame:UnregisterEvent("UI_ERROR_MESSAGE")
  else
    UIErrorsFrame:RegisterEvent("UI_ERROR_MESSAGE")
  end
end)
