pfUI:RegisterModule("unusable", function ()
  if not pfUI.bag then return end
  if C.appearance.bags.unusable ~= "1" then return end

  pfUI.unusable = {}

  local r, g, b, a = strsplit(",", C.appearance.bags.unusable_color)

  function pfUI.unusable:UpdateSlot(bag, slot)
    -- break on invalid bag slots
    if not pfUI.bags[bag] then return end
    if not pfUI.bags[bag].slots[slot] then return end

    -- return on empty buttons
    local frame = pfUI.bags[bag].slots[slot].frame
    if not frame.hasItem then return end

    -- C_PlayerInfo.CanUseItem is the "is this red in the tooltip" gate:
    -- proficiency, required level, class/race, skill/spell/rep. It checks
    -- *requirements* only, so a broken (0-durability) item still reads as
    -- usable -- no durability-line exclusion needed like the old scanner.
    local itemID = C_Container.GetContainerItemID(bag, slot)
    if itemID and not C_PlayerInfo.CanUseItem(itemID) then
      _G.SetItemButtonTextureVertexColor(frame, r, g, b, a)
    end
  end

  -- update on regular pfUI button updates
  hooksecurefunc(pfUI.bag, "UpdateSlot", function(self, bag, slot)
    pfUI.unusable:UpdateSlot(bag, slot)
  end)

  -- update on bank frame itemlock updates
  hooksecurefunc("BankFrameItemButton_UpdateLock", function()
    pfUI.unusable:UpdateSlot(-1, this:GetID())
  end)

  -- requirement changes (level, proficiency/skill, required spell, reputation,
  -- honor rank) don't touch the bags; queue a full rebag through pfUI.bag's
  -- coalesced delay, whose UpdateSlot resets the tint before we reapply it
  local refresh = CreateFrame("Frame")
  refresh:RegisterEvent("PLAYER_LEVEL_UP")
  refresh:RegisterEvent("SKILL_LINES_CHANGED")
  refresh:RegisterEvent("SPELLS_CHANGED")
  refresh:RegisterEvent("FACTION_STANDING_CHANGED")
  refresh:RegisterEvent("PLAYER_PVP_RANK_CHANGED")
  refresh:SetScript("OnEvent", function()
    for _, bag in pairs(pfUI.BACKPACK) do
      pfUI.bag.delay.UpdateBag[bag] = true
    end
    -- the bank frame is only created on first bank visit
    if pfUI.bag.left and pfUI.bag.left:IsShown() then
      for _, bag in pairs(pfUI.BANK) do
        pfUI.bag.delay.UpdateBag[bag] = true
      end
    end
  end)
end)
