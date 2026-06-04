-- load pfUI environment
setfenv(1, pfUI:GetEnvironment())

--[[ libtooltip ]]--
-- A pfUI library that provides additional GameTooltip information.
--
--  libtooltip:GetItemID()
--    returns the itemID of the current GameTooltip
--    `nil` when no item is displayed
--
--  libtooltip:GetItemLink()
--    returns the itemLink of the current GameTooltip
--    `nil` when no item is displayed
--
--  libtooltip:GetItemCount()
--    returns the item count (bags) of the current GameTooltip
--    `nil` when no item is displayed

-- return instantly when another libtooltip is already active
if pfUI.api.libtooltip then return end

local libtooltip = CreateFrame("Frame" , "pfLibTooltip", GameTooltip)

libtooltip:SetScript("OnShow", function()
  if this:GetParent():HasItem() then
    libtooltip.itemName, libtooltip.itemLink, libtooltip.itemID = this:GetParent():GetItem()
  end
end)

libtooltip:SetScript("OnHide", function()
  this.itemID = nil
  this.itemLink = nil
  this.itemCount = nil
  this.itemName = nil
end)

-- core functions
libtooltip.GetItemID = function(self)
  if not libtooltip.itemLink then return end
  if not libtooltip.itemID then
    libtooltip.itemID = C_Item.GetItemInfoInstant(libtooltip.itemLink)
  end

  return libtooltip.itemID
end

libtooltip.GetItemLink = function(self)
  return libtooltip.itemLink
end

libtooltip.GetItemCount = function(self)
  return libtooltip.itemCount
end

pfUI.api.libtooltip = libtooltip

hooksecurefunc(GameTooltip, "SetBagItem", function(self, container, slot)
  _, libtooltip.itemCount = GetContainerItemInfo(container, slot)
end)
