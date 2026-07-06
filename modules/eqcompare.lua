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

    -- find correct side
    local rightDist = 0;
    local leftPos = self:GetLeft();
    local rightPos = self:GetRight();
    if ( not rightPos ) then
      rightPos = 0;
    end
    if ( not leftPos ) then
      leftPos = 0;
    end

    rightDist = GetScreenWidth() - rightPos;

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

  local prevMerchant = ShoppingTooltip1.SetMerchantCompareItem
  local function SetMerchantCompareItem(self, index, compareItem)
    if C.tooltip.compare.basestats == "1" and compareItem == 1 then
      ShowCompareItem(nil, GetMerchantItemLink(index), 1)
      return false
    end
    return prevMerchant and prevMerchant(self, index, compareItem)
  end

  local prevAuction = ShoppingTooltip1.SetAuctionCompareItem
  local function SetAuctionCompareItem(self, type, index, compareItem)
    if C.tooltip.compare.basestats == "1" and compareItem == 1 then
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

  local function makeHook(getter)
    return function(tooltip, arg1, arg2, arg3)
      if C.tooltip.compare.basestats == "1" then
        ShowCompareItem(tooltip, getter(arg1, arg2, arg3))
      end
    end
  end

  local function HookTooltip(tooltip)
    for setter, getter in pairs(TooltipHooks) do
      pfUI.hooksecurefunc(tooltip, setter, makeHook(getter))
    end
  end

  HookTooltip(GameTooltip)

  pfUI.eqcompare.HookTooltip = HookTooltip
end)
