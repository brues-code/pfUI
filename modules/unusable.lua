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
end)
