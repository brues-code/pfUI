pfUI:RegisterModule("skin", function ()
  -- align UIParent panels
  pfUI.panelalign = CreateFrame("Frame", "pfUIParentPanelAlign", UIParent)
  pfUI.panelalign:SetScript("OnUpdate", function()
    -- throttle to 5 updates per second instead of every frame
    if (this.tick or 0.2) > GetTime() then return else this.tick = GetTime() + 0.2 end

    local left = UIParent.left
    local center = UIParent.center
    if not left or not left:IsShown() or not center or not center:IsShown() then
      return
    elseif center and center:IsShown() and left and left:IsShown() then
      -- Include visible children that extend beyond the panel backdrop, such
      -- as the Spellbook skill-line tabs. Recalculate this while both panels
      -- are visible because a child may have been hidden during an earlier
      -- alignment pass.
      local width = left.backdrop and left.backdrop:GetRight() or left:GetRight()
      for _, frame in pairs({left:GetChildren()}) do
        local object = frame.backdrop or frame
        local right = frame:IsShown() and object.GetRight and object:GetRight()
        if right and (not width or right > width) then
          width = right
        end
      end

      -- Blizzard's initial center-panel position may already clear the left
      -- panel (the Spellbook tabs occupy its otherwise empty right inset).
      -- Never pull such a panel back to the left; only correct real overlap.
      local centerObject = center.backdrop or center
      local centerLeft = centerObject.GetLeft and centerObject:GetLeft()
      local current = center:GetLeft()
      if width and centerLeft and current and centerLeft < width then
        center:SetPoint("TOPLEFT", "UIParent", "TOPLEFT", current + width - centerLeft + 10, -104)
      end
    end
  end)

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
