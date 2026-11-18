pfUI:RegisterModule("eqcompare", function ()
  pfUI.eqcompare = {}

  local function ShowCompareItem(self, link, shift)
    self = self or GameTooltip
    shift = shift or IsShiftKeyDown()

    if not link or (not shift and (C.tooltip.compare.showalways ~= "1" or C_Item.IsEquippedItem(link))) then
      return
    end

    local shoppingTooltip1, shoppingTooltip2 = unpack(self.shoppingTooltips or { ShoppingTooltip1, ShoppingTooltip2 });

    local SEPARATION = 6;
    local backdrop = shoppingTooltip1.GetBackdrop and shoppingTooltip1:GetBackdrop();
    local GAP = SEPARATION + ((type(backdrop) == "table" and backdrop.edgeSize) or 0);

    local item1 = nil;
    local item2 = nil;
    local side = "left";
    if ( shoppingTooltip1:SetHyperlinkCompareItem(link, 1, shift, self) ) then
      item1 = true;
    end
    if ( shoppingTooltip2:SetHyperlinkCompareItem(link, 2, shift, self) ) then
      item2 = true;
    end

    -- find correct side. A cursor-anchored tooltip has no points until the
    -- client's next update sets its BOTTOM at the cursor (SetOwner clears
    -- them), so read where it is about to be instead of an empty rect.
    local leftPos, rightPos
    if self:GetAnchorType() == "ANCHOR_CURSOR" and self:GetNumPoints() == 0 then
      local x = GetCursorPosition() / self:GetEffectiveScale()
      local halfWidth = self:GetWidth() / 2
      leftPos, rightPos = x - halfWidth, x + halfWidth
    else
      leftPos, rightPos = self:GetLeft() or 0, self:GetRight() or 0
    end

    local rightDist = GetScreenWidth() - rightPos;

    if (leftPos and (rightDist < leftPos)) then
      side = "left";
    else
      side = "right";
    end

    -- see if we should slide the tooltip
    if ( self:GetAnchorType() and self:GetAnchorType() ~= "ANCHOR_PRESERVE" ) then
      local totalWidth = 0;
      if ( item1  ) then
        totalWidth = totalWidth + shoppingTooltip1:GetWidth();
      end
      if ( item2  ) then
        totalWidth = totalWidth + shoppingTooltip2:GetWidth();
      end

      if ( (side == "left") and (totalWidth > leftPos) ) then
        self:SetAnchorType(self:GetAnchorType(), (totalWidth - leftPos), 0);
      elseif ( (side == "right") and (rightPos + totalWidth) >  GetScreenWidth() ) then
        self:SetAnchorType(self:GetAnchorType(), -((rightPos + totalWidth) - GetScreenWidth()), 0);
      end
    end

    if ( item1 ) then
      shoppingTooltip1:SetOwner(self, "ANCHOR_NONE");
      shoppingTooltip1:ClearAllPoints();
      if ( side and side == "left" ) then
        shoppingTooltip1:SetPoint("TOPRIGHT", self, "TOPLEFT", -GAP, -10);
      else
        shoppingTooltip1:SetPoint("TOPLEFT", self, "TOPRIGHT", GAP, -10);
      end
      shoppingTooltip1:SetHyperlinkCompareItem(link, 1, shift, self);
      shoppingTooltip1:Show();

      if ( item2 ) then
        shoppingTooltip2:SetOwner(shoppingTooltip1, "ANCHOR_NONE");
        shoppingTooltip2:ClearAllPoints();
        if ( side and side == "left" ) then
          shoppingTooltip2:SetPoint("TOPRIGHT", shoppingTooltip1, "TOPLEFT", -GAP, 0);
        else
          shoppingTooltip2:SetPoint("TOPLEFT", shoppingTooltip1, "TOPRIGHT", GAP, 0);
        end
        shoppingTooltip2:SetHyperlinkCompareItem(link, 2, shift, self);
        shoppingTooltip2:Show();
      end
    end
  end

  local function HideCompareItem(self)
    local shoppingTooltip1, shoppingTooltip2 = unpack(self.shoppingTooltips or { ShoppingTooltip1, ShoppingTooltip2 })
    shoppingTooltip1:Hide()
    shoppingTooltip2:Hide()
  end

  local prevMerchant = ShoppingTooltip1.SetMerchantCompareItem
  local function SetMerchantCompareItem(self, index, compareItem)
    if compareItem == 1 then
      ShowCompareItem(nil, GetMerchantItemLink(index), 1)
      return false
    end
    return prevMerchant and prevMerchant(self, index, compareItem)
  end

  local prevAuction = ShoppingTooltip1.SetAuctionCompareItem
  local function SetAuctionCompareItem(self, type, index, compareItem)
    if compareItem == 1 then
      ShowCompareItem(nil, GetAuctionItemLink(type, index), 1)
      return false
    end
    return prevAuction and prevAuction(self, type, index, compareItem)
  end

  ShoppingTooltip1.SetMerchantCompareItem = SetMerchantCompareItem
  ShoppingTooltip2.SetMerchantCompareItem = SetMerchantCompareItem
  ShoppingTooltip1.SetAuctionCompareItem  = SetAuctionCompareItem
  ShoppingTooltip2.SetAuctionCompareItem  = SetAuctionCompareItem

  local TooltipHooks = {
    SetLootRollItem = GetLootRollItemLink,
    SetLootItem = GetLootSlotLink,
    SetQuestLogItem = GetQuestLogItemLink,
    SetQuestItem = GetQuestItemLink,
    SetHyperlink = function(link) return link end,
    SetBagItem = GetContainerItemLink,
    SetInboxItem = GetInboxItemLink,
    SetInventoryItem = GetInventoryItemLink,
    SetTradeSkillItem = function(skillIndex, reagentIndex)
        if reagentIndex then
            return GetTradeSkillReagentItemLink(skillIndex, reagentIndex)
        else
            return GetTradeSkillItemLink(skillIndex)
        end
    end,
    SetAuctionSellItem = GetAuctionSellItemLink,
    SetTradePlayerItem = GetTradePlayerItemLink,
    SetTradeTargetItem = GetTradeTargetItemLink
  }

  -- Guda anchors its item tooltips with ANCHOR_NONE and its own SetPoint, and
  -- the tooltip module then moves every ANCHOR_NONE tooltip to its configured
  -- spot. Reading the rect inside the Set* call picks the side against the
  -- position the tooltip is about to leave, so place the compare a frame later.
  local deferred
  HookAddon("Guda", function()
    deferred = true
  end)

  -- the item each hooked tooltip shows, for MODIFIER_STATE_CHANGED. Every Set*
  -- clears the tooltip before it builds, so OnTooltipCleared drops the link
  -- of the previous content before the hook stores the new one.
  local links = {}
  local function forget()
    links[this] = nil
  end

  local function makeHook(getter)
    return function(tooltip, arg1, arg2, arg3)
      local link = getter(arg1, arg2, arg3)
      links[tooltip] = link
      if not deferred then
        return ShowCompareItem(tooltip, link)
      end
      RunNextFrame(function()
        if tooltip:IsShown() then
          ShowCompareItem(tooltip, link)
        end
      end)
    end
  end

  local function HookTooltip(tooltip)
    for setter, getter in pairs(TooltipHooks) do
      hooksecurefunc(tooltip, setter, makeHook(getter))
    end
    tooltip:HookScript("OnTooltipCleared", forget)
    tooltip:HookScript("OnHide", forget)
  end

  -- pressing or releasing shift over an item toggles its comparison at once.
  -- Merchant and auction comparisons show regardless of shift and never set
  -- a link, so they stay up.
  pfUI.events:RegisterFrameEventAndCallback("MODIFIER_STATE_CHANGED", function(_, key)
    if key ~= "LSHIFT" and key ~= "RSHIFT" then return end

    local shift = IsShiftKeyDown()
    for tooltip, link in pairs(links) do
      -- a hidden tooltip got its item from a scan, not a hover
      if tooltip:IsShown() then
        if shift then
          ShowCompareItem(tooltip, link, shift)
        elseif C.tooltip.compare.showalways ~= "1" or C_Item.IsEquippedItem(link) then
          HideCompareItem(tooltip)
        end
      end
    end
  end)

  HookTooltip(GameTooltip)

  pfUI.eqcompare.HookTooltip = HookTooltip
end)
