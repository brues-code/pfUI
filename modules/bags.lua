pfUI:RegisterModule("bags", function ()
  local rawborder, default_border = GetBorderSize("bags")

  local knownInventorySpellTextures = {
    Spell_Holy_RemoveCurse = {frame="disenchant"},
    Spell_Nature_MoonKey = {frame="picklock"},
  }
  local scanner = libtipscan:GetScanner("openable")

  -- ============================================================================
  -- Bag sorter: consolidates partial stacks then sorts by category/name.
  -- Adapted from the algo in Bagnon/lib/BagSort.lua.
  -- ============================================================================
  local sorter = CreateFrame("Frame")
  sorter.itemGrid = {}
  sorter.bagList  = nil
  local HEARTHSTONE_ITEM_ID = 6948

  -- Lower prefix = sorted earlier in the bag.
  local function SortCategoryPrefix(itemId, itemType, itemSubType, quality)
    if itemId == HEARTHSTONE_ITEM_ID then return "00" end
    if quality == 0              then return "13" end  -- Poor (gray) always last
    if itemType == "Weapon" or itemType == "Armor" then
      if quality and quality >= 4 then return "01" end  -- Epic+ gear
      if quality == 3             then return "02" end  -- Rare gear
      if quality == 2             then return "03" end  -- Uncommon gear
      return "04"                                        -- Common/poor gear
    end
    if itemType == "Consumable"  then return "05" end
    if itemType == "Reagent"     then return "06" end
    if itemType == "Trade Goods" then return "07" end
    if itemType == "Quest"       then return "08" end
    -- Non-gear items without a specific type, sorted by quality
    if quality and quality >= 4  then return "09" end
    if quality == 3              then return "10" end
    if quality == 2              then return "11" end
    return "12"
  end

  -- Larger stacks sort first among identically-named items; invert + zero-pad
  -- so it sorts lexicographically.
  local function SortCountSuffix(count)
    local s = "000000" .. (999999 - (count or 0))
    return string.sub(s, -6)
  end

  local function SortKey(itemId, name, itype, subtype, quality, count)
    return SortCategoryPrefix(itemId, itype, subtype, quality)
      .. (itype or "") .. "|" .. (subtype or "") .. "|" .. (name or "zzz") .. "|" .. SortCountSuffix(count)
  end

  local function ClearSortData()
    sorter.itemGrid = {}
    sorter.bagList  = nil
    sorter:UnregisterEvent("BAG_UPDATE_DELAYED")
    sorter:SetScript("OnEvent", nil)
  end

  -- Two-pointer consolidation: sorts stacks largest-first, then merges from
  -- both ends toward the middle. n is set explicitly so table.getn / table.sort
  -- work correctly in Lua 5.0.
  local function BuildConsolidateOps(bagList)
    local groups = {}
    for _, bag in ipairs(bagList) do
      for slot = 1, GetContainerNumSlots(bag) do
        local itemId = C_Container.GetContainerItemID(bag, slot)
        if itemId then
          local _, count = GetContainerItemInfo(bag, slot)
          count = count or 0
          local maxStack = C_Item.GetItemMaxStackSizeByID(itemId) or 1
          if count > 0 and maxStack > 1 then
            if not groups[itemId] then
              groups[itemId] = {maxStack=maxStack, n=0}
            end
            local g = groups[itemId]
            g.n = g.n + 1
            g[g.n] = {bag=bag, slot=slot, count=count}
          end
        end
      end
    end

    local ops = {}
    for _, g in pairs(groups) do
      local n = g.n
      if n >= 2 then
        local maxStack = g.maxStack
        table.sort(g, function(a, b) return a.count > b.count end)
        local lo, hi = 1, n
        while lo < hi do
          local space = maxStack - g[lo].count
          if space == 0 then
            lo = lo + 1
          elseif space >= g[hi].count then
            tinsert(ops, {
              dstBag = g[lo].bag, dstSlot = g[lo].slot,
              srcBag = g[hi].bag, srcSlot = g[hi].slot,
              count  = g[hi].count,
            })
            g[lo].count = g[lo].count + g[hi].count
            hi = hi - 1
          else
            tinsert(ops, {
              dstBag = g[lo].bag, dstSlot = g[lo].slot,
              srcBag = g[hi].bag, srcSlot = g[hi].slot,
              count  = space,
            })
            g[hi].count = g[hi].count - space
            g[lo].count = maxStack
            lo = lo + 1
          end
        end
      end
    end
    return ops
  end

  local function BuildSortGrid()
    local bagList = sorter.bagList
    sorter.itemGrid = {}
    local normalItems = {}
    local poorItems   = {}
    local bagCount    = 0
    local bagSlots    = {}

    for _, bag in ipairs(bagList) do
      bagCount = bagCount + 1
      local numSlots = GetContainerNumSlots(bag)
      bagSlots[bagCount] = numSlots
      if numSlots > 0 then
        sorter.itemGrid[bag] = {}
        for slot = 1, numSlots do
          local itemId = C_Container.GetContainerItemID(bag, slot)
          if itemId then
            local name, _, quality, _, itype, subtype = GetItemInfo(itemId)
            local _, count = GetContainerItemInfo(bag, slot)
            local item = {
              key     = SortKey(itemId, name, itype, subtype, quality, count),
              srcBag  = bag,
              srcSlot = slot,
              curBag  = bag,
              curSlot = slot,
            }
            if quality == 0 then
              tinsert(poorItems, item)
            else
              tinsert(normalItems, item)
            end
            sorter.itemGrid[bag][slot] = item
          end
        end
      end
    end

    table.sort(normalItems, function(a, b) return a.key < b.key end)
    -- Sort poor items descending so they read in ascending order when placed
    -- back-to-front (last poor item lands on the last slot).
    table.sort(poorItems, function(a, b) return a.key > b.key end)

    -- Forward pass: assign normal items from slot 1 of bag 1 onward
    local bagIdx, destSlot = 1, 1
    while bagIdx <= bagCount and bagSlots[bagIdx] == 0 do
      bagIdx = bagIdx + 1
    end
    for _, item in ipairs(normalItems) do
      while bagIdx <= bagCount do
        if destSlot <= bagSlots[bagIdx] then break end
        bagIdx   = bagIdx + 1
        destSlot = 1
      end
      if bagIdx > bagCount then break end
      local grid = sorter.itemGrid[item.srcBag][item.srcSlot]
      grid.destBag  = bagList[bagIdx]
      grid.destSlot = destSlot
      destSlot = destSlot + 1
    end

    -- Reverse pass: assign poor items from the last slot of the last bag backward
    local rBagIdx  = bagCount
    local rDestSlot = 0
    while rBagIdx >= 1 do
      if bagSlots[rBagIdx] > 0 then rDestSlot = bagSlots[rBagIdx]; break end
      rBagIdx = rBagIdx - 1
    end
    for _, item in ipairs(poorItems) do
      while rBagIdx >= 1 and rDestSlot < 1 do
        rBagIdx   = rBagIdx - 1
        rDestSlot = rBagIdx >= 1 and bagSlots[rBagIdx] or 0
      end
      if rBagIdx < 1 then break end
      local grid = sorter.itemGrid[item.srcBag][item.srcSlot]
      grid.destBag  = bagList[rBagIdx]
      grid.destSlot = rDestSlot
      rDestSlot = rDestSlot - 1
    end
  end

  -- Build the sort grid (planned from current bag state) and fire every swap
  -- needed to reach it. Items track their live position via curBag/curSlot so
  -- we never read it back from a grid we're mutating.
  local function RunSortPhase()
    BuildSortGrid()

    -- Snapshot items that need to move before any swap runs — iterating
    -- pairs() while mutating itemGrid is undefined in Lua 5.0.
    local toMove = {}
    for _, bagGrid in pairs(sorter.itemGrid) do
      for _, info in pairs(bagGrid) do
        if info.destBag and (info.destBag ~= info.curBag or info.destSlot ~= info.curSlot) then
          tinsert(toMove, info)
        end
      end
    end

    for _, info in ipairs(toMove) do
      local curBag, curSlot = info.curBag, info.curSlot
      local dBag,   dSlot   = info.destBag, info.destSlot
      if dBag ~= curBag or dSlot ~= curSlot then
        local _, _, lock1 = GetContainerItemInfo(curBag, curSlot)
        local _, _, lock2 = GetContainerItemInfo(dBag, dSlot)
        if not (lock1 or lock2) then
          local displaced = sorter.itemGrid[dBag][dSlot]
          C_Container.SwapItems(curBag, curSlot, dBag, dSlot)
          sorter.itemGrid[dBag][dSlot]     = info
          sorter.itemGrid[curBag][curSlot] = displaced
          info.curBag, info.curSlot = dBag, dSlot
          if displaced then
            displaced.curBag, displaced.curSlot = curBag, curSlot
          end
        end
      end
    end

    ClearSortData()
  end

  -- Unregister immediately so the swaps we're about to fire don't re-enter
  -- this handler via their own BAG_UPDATEs.
  local function SorterOnEvent()
    if event == "BAG_UPDATE_DELAYED" then
      sorter:UnregisterEvent("BAG_UPDATE_DELAYED")
      sorter:SetScript("OnEvent", nil)
      RunSortPhase()
    end
  end

  local function StartSort(bagList)
    ClearSortData()
    sorter.bagList = bagList

    -- Phase 1: fire every consolidation op in a single batch.
    local ops = BuildConsolidateOps(bagList)
    local fired = false
    for _, op in ipairs(ops) do
      local _, _, lock1 = GetContainerItemInfo(op.srcBag, op.srcSlot)
      local _, _, lock2 = GetContainerItemInfo(op.dstBag, op.dstSlot)
      if not (lock1 or lock2) then
        C_Container.MoveItem(op.srcBag, op.srcSlot, op.dstBag, op.dstSlot, op.count)
        fired = true
      end
    end

    if fired then
      -- Wait for the server to confirm the merges so the sort grid reads
      -- accurate slot contents.
      sorter:SetScript("OnEvent", SorterOnEvent)
      sorter:RegisterEvent("BAG_UPDATE_DELAYED")
      return
    end

    RunSortPhase()
  end

  -- function to detect openable items in inventory
  local openable = { bag = nil, slot = nil, icon = nil }
  local function GetNextOpenable()
    if openable.icon and openable.icon == GetContainerItemInfo(openable.bag, openable.slot) then
      return openable.bag, openable.slot
    end

    for bag=-2, 11 do
      local bagsize = GetContainerNumSlots(bag)
      if bag == -2 and pfUI.bag.showKeyring == true then bagsize = GetKeyRingSize() end
      for slot=1, bagsize do
        if GetContainerItemInfo(bag, slot) then
          scanner:SetBagItem(bag, slot)

          if scanner:Find(_G.ITEM_OPENABLE, true) then
            openable.bag = bag
            openable.slot = slot
            openable.icon = GetContainerItemInfo(bag, slot)
            return openable.bag, openable.slot
          end
        end
      end
    end
  end

  -- prevent from being placed offscreen
  _G.StackSplitFrame:SetClampedToScreen(true)

  -- overwrite some bag functions
  function _G.OpenAllBags()
    if pfUI.bag.right:IsShown() then
      pfUI.bag.right:Hide()
    else
      pfUI.bag.right:Show()
    end
  end

  function _G.CloseAllBags()
    pfUI.bag.right:Hide()
  end

  function _G.ToggleBackpack()
    if pfUI.bag.right:IsShown() then
      pfUI.bag.right:Hide()
    else
      pfUI.bag.right:Show()
    end
  end

  function _G.OpenBackpack()
    if ( pfUI.bag.right:IsShown() ) then
      ContainerFrame1.backpackWasOpen = 1
      return
    else
      ContainerFrame1.backpackWasOpen = nil
    end

    if ( not ContainerFrame1.backpackWasOpen ) then
      ToggleBackpack()
    end
  end

  function _G.ToggleBag()
    return
  end

  -- hide blizzard's bankframe
  BankFrame:SetScale(0.001)
  BankFrame:SetPoint("TOPLEFT", 0,0)
  BankFrame:SetAlpha(0)

  pfUI.bag = CreateFrame("Frame", "pfUIBag")
  pfUI.bag:RegisterEvent("PLAYER_ENTERING_WORLD")
  pfUI.bag:RegisterEvent("BAG_UPDATE")
  pfUI.bag:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
  pfUI.bag:RegisterEvent("PLAYERBANKBAGSLOTS_CHANGED")
  pfUI.bag:RegisterEvent("BAG_UPDATE_COOLDOWN")
  pfUI.bag:RegisterEvent("BAG_CLOSED")
  pfUI.bag:RegisterEvent("BANKFRAME_CLOSED")
  pfUI.bag:RegisterEvent("BANKFRAME_OPENED")
  pfUI.bag:RegisterEvent("ITEM_LOCK_CHANGED")
  pfUI.bag:RegisterEvent("SPELLS_CHANGED")
  pfUI.bag:RegisterEvent("MERCHANT_CLOSED")

  pfUI.bag.delay = { UpdateBag = {} }

  pfUI.bag:SetScript("OnUpdate", function()
    -- update delayed ones every 0.1s
    if ( this.tick or 1) > GetTime() then return else this.tick = GetTime() + .1 end

    if this.delay.RefreshSpells then
      this.delay.RefreshSpells = nil
      pfUI.bag:RefreshSpells()
    end

    if this.delay.CheckFullUpdate then
      this.delay.CheckFullUpdate = nil
      pfUI.bag:CheckFullUpdate()
    end

    if this.delay.UpdateCooldowns then
      this.delay.UpdateCooldowns = nil
      pfUI.bag:UpdateCooldowns()
    end

    if this.delay.UpdateItemLock then
      this.delay.UpdateItemLock = nil
      pfUI.bag:UpdateItemLock()
    end

    for bag in pairs(this.delay.UpdateBag) do
      this.delay.UpdateBag[bag] = nil
      pfUI.bag:UpdateBag(bag)
    end
  end)

  pfUI.bag:SetScript("OnEvent", function()
    if event == "PLAYER_ENTERING_WORLD" then
      pfUI.bag:CreateBags()
      pfUI.bag.right:Hide()

      pfUI.bag:CreateBags("bank")
      pfUI.bag.left:Hide()

      pfUI.bag:CreateBagSlots(pfUI.bag.right)
      pfUI.bag:CreateBagSlots(pfUI.bag.left)
      pfUI.bag:RefreshSpells()
    end

    if event == "SPELLS_CHANGED" then
      this.delay.RefreshSpells = true
    end

    if event == "BAG_CLOSED" or event == "PLAYERBANKSLOTS_CHANGED" or
       event == "PLAYERBANKBAGSLOTS_CHANGED" or event == "BAG_UPDATE" or
       event == "BANKFRAME_OPENED" or event == "BANKFRAME_CLOSED" then
      this.delay.CheckFullUpdate = true
    end

    if event == "BAG_UPDATE_COOLDOWN" then
      this.delay.UpdateCooldowns = true
    end

    if event == "ITEM_LOCK_CHANGED" then
      this.delay.UpdateItemLock = true
    end

    if event == "PLAYERBANKSLOTS_CHANGED" then
      this.delay.UpdateBag[-1] = true
    end

    if event == "BAG_UPDATE" then
      this.delay.UpdateBag[arg1] = true
    end

    if event == "PLAYERBANKBAGSLOTS_CHANGED" then
      pfUI.bag:CreateBagSlots(pfUI.bag.left)
    end

    if event == "BANKFRAME_OPENED" then
      pfUI.bag.left:Show()
      OpenBackpack()
    end

    if event == "BANKFRAME_CLOSED" then
      pfUI.bag.left:Hide()
    end

    if event == "MERCHANT_CLOSED" then
      if not ContainerFrame1.backpackWasOpen then
        pfUI.bag.right:Hide()
      end
    end
  end)

  tinsert(UISpecialFrames,"pfBag")

  pfUI.BACKPACK = { -2, 0, 1, 2, 3, 4 }
  pfUI.BANK = { -1, 5, 6, 7, 8, 9, 10, 11 }

  pfUI.bags = {}
  pfUI.slots = {}

  function pfUI.bag:CheckFullUpdate()
    local maxslots = 0

    for bag = -2,11 do
      local bagsize = GetContainerNumSlots(bag)
      if bag == -2 and pfUI.bag.showKeyring == true then bagsize = GetKeyRingSize() end

      maxslots = maxslots + bagsize
    end

    if maxslots ~= pfUI.bag.maxslots then
      for bag = -2,11 do
        for slot, f in ipairs(pfUI.bags[bag].slots) do
          local bagsize = GetContainerNumSlots(bag)
          if bag == -2 and pfUI.bag.showKeyring == true then bagsize = GetKeyRingSize() end

          if slot > bagsize then
            pfUI.bags[bag].slots[slot].frame:Hide()
          end
        end
      end

      pfUI.bag:CreateBags()
      pfUI.bag:CreateBags("bank")
      pfUI.bag.maxslots = maxslots
    end
  end

  function pfUI.bag:CreateBags(object)
    local x = 0
    local y = 0
    local frame = {}
    local iterate = {}
    local anchor, rowlength, cwidth

    if object == "bank" then
      if not pfUI.bag.left then pfUI.bag.left = CreateFrame("Frame", "pfBank", UIParent) end
      anchor = { "BOTTOMLEFT", (pfUI.chat and pfUI.chat.left or nil), "BOTTOMRIGHT", "TOPLEFT", "TOPRIGHT" }
      rowlength = tonumber(C.appearance.bags.bankrowlength)
      cwidth = C.chat.left.width
      iterate = pfUI.BANK
      frame = pfUI.bag.left
    else
      if not pfUI.bag.right then pfUI.bag.right = CreateFrame("Frame", "pfBag", UIParent) end
      rowlength = tonumber(C.appearance.bags.bagrowlength)
      anchor = { "BOTTOMRIGHT", (pfUI.chat and pfUI.chat.right or nil), "BOTTOMLEFT", "TOPRIGHT", "TOPLEFT" }
      cwidth = C.chat.right.width
      iterate = pfUI.BACKPACK
      frame = pfUI.bag.right
    end

    if not frame.init then
      pfUI.bag:CreateAdditions(frame)
      frame:SetFrameStrata("HIGH")
      CreateBackdrop(frame, default_border)
      CreateBackdropShadow(frame)
      frame.init = true
    end

    if pfUI.chat and C.appearance.bags.icon_size == "-1" then
      -- align bags to chat if no custom size is set
      frame:SetWidth(cwidth * anchor[2]:GetScale())
    elseif C.appearance.bags.icon_size ~= "-1" then
      -- use custom size if set
      frame:SetWidth((C.appearance.bags.icon_size + default_border*3) * rowlength - default_border)
    else
      -- fallback to 22px without any anchor or custom setting
      frame:SetWidth((22 + default_border*3) * rowlength - default_border)
    end

    if pfUI.chat and C.appearance.bags.icon_size ~= "-1" then
      -- ignore custom icon size
      frame:SetPoint(anchor[1], anchor[2], anchor[1], 0, 0)
    elseif pfUI.chat then
      -- use chat frame as anchor if existing
      if C.appearance.bags.abovechat == "0" then
        frame:SetPoint(anchor[1], anchor[2], anchor[1], 0, 0)
        frame:SetPoint(anchor[3], anchor[2], anchor[3], 0, 0)
      else
        frame:SetPoint(anchor[3], anchor[2], anchor[5], 0, 3*default_border)
        frame:SetPoint(anchor[1], anchor[2], anchor[4], 0, 3*default_border)
      end
    else
      -- align frame to UIParent if no anchor is available
      frame:SetPoint(anchor[1], UIParent, anchor[1], 5, 5)
    end

    if C.appearance.bags.movable == "1" then
      -- enable movable bag frames
      LoadMovable(frame)
      frame:EnableMouse(1)
      frame:SetMovable(1)
      frame:RegisterForDrag("LeftButton")
      frame:SetScript("OnDragStart", function()
        this:StartMoving()
      end)

      frame:SetScript("OnDragStop",  function()
        this:StopMovingOrSizing()
        SaveMovable(this)
      end)
    end

    frame:EnableMouse(1)

    if C.appearance.bags.movable == "1" and C.appearance.bags.icon_size ~= "-1" then
      frame.button_size = C.appearance.bags.icon_size
    else
      frame.button_size = (frame:GetWidth() - 2*default_border - (rowlength-1)*default_border*3)/ rowlength
    end

    local topspace = pfUI.bag.right.close:GetHeight() + default_border * 2
    local bottomspace = pfUI.panel and pfUI.panel.right:IsShown() and pfUI.panel.right:GetHeight() + default_border or 16 + default_border

    for id, bag in pairs(iterate) do
      if not pfUI.bags[bag] then
        pfUI.bags[bag] = CreateFrame("Frame", "pfBag" .. bag,  frame)
        pfUI.bags[bag]:SetAllPoints(frame)
        pfUI.bags[bag].slots = {}
      end
      pfUI.bags[bag]:SetID(bag)
      local bagsize = GetContainerNumSlots(bag)
      if bag == -2 and pfUI.bag.showKeyring == true then bagsize = GetKeyRingSize() end
      for slot=1, bagsize do
        pfUI.bag:UpdateSlot(bag, slot)

        pfUI.bags[bag].slots[slot].frame:ClearAllPoints()
        pfUI.bags[bag].slots[slot].frame:SetPoint("TOPLEFT",
          default_border + x*(frame.button_size+default_border*3),
          -default_border*2 - y*(frame.button_size+default_border*3) - topspace)

        pfUI.bags[bag].slots[slot].frame:SetHeight(frame.button_size)
        pfUI.bags[bag].slots[slot].frame:SetWidth(frame.button_size)

        if x >= rowlength - 1 then
          y = y + 1
          x = 0
        else
          x = x + 1
        end
      end
    end

    if x > 0 then y = y + 1 end
    frame:SetHeight( default_border*2 + y*(frame.button_size+default_border*3) + topspace + bottomspace)

    local chat = pfUI.chat and ( object == "bank" and pfUI.chat.left or pfUI.chat.right) or nil

    frame:SetScript("OnShow", function()
      if C.appearance.bags.hidechat == "1" and chat and chat:IsVisible() then
        frame.chatWasOpen = true
        chat:Hide()
      end
      pfUI.bag:CreateBags(object)
      PlaySound("INTERFACESOUND_BACKPACKOPEN")
    end)

    frame:SetScript("OnHide", function()
      if C.appearance.bags.hidechat == "1" and chat and frame.chatWasOpen then
        chat:Show()
        frame.chatWasOpen = false
      end
      pfUI.bag:CreateBags(object)
      PlaySound("INTERFACESOUND_BACKPACKCLOSE")
    end)
  end

  function pfUI.bag:UpdateBag(bag)
    local bagsize = GetContainerNumSlots(bag)
    if bag == -2 and pfUI.bag.showKeyring == true then bagsize = GetKeyRingSize() end
    for slot=1, bagsize do
      pfUI.bag:UpdateSlot(bag, slot)
    end
  end

  function pfUI.bag:UpdateSlot(bag, slot)
    if not pfUI.bags[bag] then return end

    if not pfUI.bags[bag].slots[slot] then
      local tpl = "ContainerFrameItemButtonTemplate"
      if bag == -1 then tpl = "BankItemButtonGenericTemplate" end
      pfUI.bags[bag].slots[slot] = {}
      pfUI.bags[bag].slots[slot].frame = CreateFrame("Button", "pfBag" .. bag .. "item" .. slot,  pfUI.bags[bag], tpl)
      pfUI.bags[bag].slots[slot].frame.qtext = pfUI.bags[bag].slots[slot].frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")

      pfUI.bags[bag].slots[slot].frame:SetNormalTexture("")
      pfUI.bags[bag].slots[slot].bag = bag
      pfUI.bags[bag].slots[slot].slot = slot
      pfUI.bags[bag].slots[slot].frame:SetID(slot)

      -- add cooldown frame to bankslots
      if tpl == "BankItemButtonGenericTemplate" then
        local bankslot = pfUI.bags[bag].slots[slot].frame
        local name = "pfBag" .. bag .. "item" .. slot .. "Cooldown"
        bankslot.cd = CreateFrame(COOLDOWN_FRAME_TYPE, name, bankslot, "CooldownFrameTemplate")
        bankslot.cd:SetAllPoints(bankslot)
        bankslot.cd.pfCooldownStyleAnimation = 1
        bankslot.cd.pfCooldownType = "ALL"
      else
        local bagslot = pfUI.bags[bag].slots[slot].frame
        bagslot.cd = _G[bagslot:GetName().."Cooldown"]
        bagslot.cd.pfCooldownType = "ALL"
      end

      if not pfUI.bags[bag].slots[slot].frame.backdrop then
        CreateBackdrop(pfUI.bags[bag].slots[slot].frame, default_border)
      end

      local highlight = pfUI.bags[bag].slots[slot].frame:GetHighlightTexture()
      highlight:SetTexture(.5, .5, .5, .5)

      local pushed = pfUI.bags[bag].slots[slot].frame:GetPushedTexture()
      pushed:SetTexture(.5, .5, .5, .5)

      local questText = pfUI.bags[bag].slots[slot].frame.qtext
      questText:SetFont(pfUI.font_default, 13, "THICKOUTLINE")
      questText:SetPoint("TOPLEFT", 0, 0)
      questText:SetTextColor(1, .8, .2, 1)

      local countFrame = _G[pfUI.bags[bag].slots[slot].frame:GetName() .. "Count"]
      countFrame:SetFont(pfUI.font_unit, C.global.font_unit_size, "OUTLINE")
      countFrame:SetAllPoints()
      countFrame:SetJustifyH("RIGHT")
      countFrame:SetJustifyV("BOTTOM")

      local icon = _G[pfUI.bags[bag].slots[slot].frame:GetName() .. "IconTexture"]
      icon:SetTexCoord(.08, .92, .08, .92)
      icon:ClearAllPoints()
      icon:SetPoint("TOPLEFT", 1, -1)
      icon:SetPoint("BOTTOMRIGHT", -1, 1)

      local border = _G[pfUI.bags[bag].slots[slot].frame:GetName() .. "NormalTexture"]
      border:SetTexture("")

      if ShaguScore then
        pfUI.bags[bag].slots[slot].frame.scoreText = pfUI.bags[bag].slots[slot].frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        pfUI.bags[bag].slots[slot].frame.scoreText:SetFont(pfUI.font_default, 12, "OUTLINE")
        pfUI.bags[bag].slots[slot].frame.scoreText:SetPoint("TOPRIGHT", 0, 0)
      end
    end

    local texture, count, locked, quality = GetContainerItemInfo(bag, slot)

    -- Nampower 4.1.4+: spellChargesRemaining gives accurate charge count for
    -- charged items (e.g. Brilliant Mana Oil).
    -- Only use it when stackCount == 1 and spellChargesRemaining > 1,
    -- otherwise we'd override normal stack counts.
    if GetBagItem then
      local ok, itemInfo = pcall(GetBagItem, bag, slot)
      if ok and itemInfo and itemInfo.stackCount == 1 and itemInfo.spellChargesRemaining and itemInfo.spellChargesRemaining > 1 then
        count = itemInfo.spellChargesRemaining
      end
    end
    local _, _, q, _, _, _, itype = GetItemInfo(C_Container.GetContainerItemID(bag, slot))

    -- running advanced item color scan
    if C.appearance.bags.borderonlygear == "0" and texture and quality and quality < 1 then
      if quality then quality = q end
    end

    SetItemButtonTexture(pfUI.bags[bag].slots[slot].frame, texture)
    SetItemButtonCount(pfUI.bags[bag].slots[slot].frame, count)
    SetItemButtonDesaturated(pfUI.bags[bag].slots[slot].frame, locked, 0.5, 0.5, 0.5)

    local hasItem = texture and 1 or nil
    pfUI.bags[bag].slots[slot].frame.hasItem = hasItem
    pfUI.bags[bag].slots[slot].frame.qtext:SetText("")

    ContainerFrame_UpdateCooldown(bag, pfUI.bags[bag].slots[slot].frame)

    -- detect backdrop border color
    if texture and itype == "Quest" then
      pfUI.bags[bag].slots[slot].frame.backdrop:SetBackdropBorderColor(1, .8, .2, .8)
      pfUI.bags[bag].slots[slot].frame.qtext:SetText("?")
    elseif texture and quality and quality > tonumber(C.appearance.bags.borderlimit) then
      pfUI.bags[bag].slots[slot].frame.backdrop:SetBackdropBorderColor(GetItemQualityColor(quality))
    elseif texture and quality then
      pfUI.bags[bag].slots[slot].frame.backdrop:SetBackdropBorderColor(.5,.5,.5,1)
    else
      local bagtype = GetBagFamily(bag)

      if bagtype == "QUIVER" then
        pfUI.bags[bag].slots[slot].frame.backdrop:SetBackdropBorderColor(1,1,.5,.5)
      elseif bagtype == "SOULBAG" then
        pfUI.bags[bag].slots[slot].frame.backdrop:SetBackdropBorderColor(1,.5,.5,.5)
      elseif bagtype == "SPECIAL" then
        pfUI.bags[bag].slots[slot].frame.backdrop:SetBackdropBorderColor(.5,.5,1,.5)
      elseif bagtype == "KEYRING" then
        pfUI.bags[bag].slots[slot].frame.backdrop:SetBackdropBorderColor(.5,1,1,.5)
      else
        pfUI.bags[bag].slots[slot].frame.backdrop:SetBackdropBorderColor(1,1,1,.2)
      end
    end

    -- add shaguscore if we have it
    if ShaguScore and pfUI.bags[bag].slots[slot].frame.scoreText then
      if quality and quality > 0 then
        local item = Item:CreateFromBagAndSlot(bag, slot)
        local r,g,b = item:GetItemQualityColorRGB()
        local itemID = item:GetItemID()
        local itemLevel = ShaguScore.Database[itemID] or 0
        local score = ShaguScore:Calculate(vslot, quality, itemLevel)
        if score and score > 0 and count and count == 1 then
          pfUI.bags[bag].slots[slot].frame.scoreText:SetText(score)
          pfUI.bags[bag].slots[slot].frame.scoreText:SetTextColor(r, g, b)
        else
          pfUI.bags[bag].slots[slot].frame.scoreText:SetText("")
        end
      else
        pfUI.bags[bag].slots[slot].frame.scoreText:SetText("")
      end
    end

    pfUI.bags[bag].slots[slot].frame:Show()
  end

  function pfUI.bag:CreateBagSlots(frame)
    if not frame.bagslots then
      frame.bagslots = CreateFrame("Frame", "pfBagSlots", frame)
      frame.bagslots.slots = {}
      frame.bagslots:Hide()
    end

    local min, max = 0, 3
    local tpl = "BagSlotButtonTemplate"
    local name, append = "pfUIBagsBBag", "Slot"
    local position = "RIGHT"

    if frame == pfUI.bag.left then
      min, max = 1, math.min(NUM_BANKBAGSLOTS, (GetNumBankSlots() or 0))
      tpl = "BankItemButtonBagTemplate"
      name, append = "pfUIBankBBag", ""
      position = "LEFT"
    end

    frame.bagslots:SetPoint("BOTTOM"..position, frame, "TOP"..position, 0, default_border*3)
    CreateBackdrop(frame.bagslots, default_border)
    CreateBackdropShadow(frame.bagslots)

    local extra = frame == pfUI.bag.left and GetNumBankSlots() < NUM_BANKBAGSLOTS and 1 or 0
    local width = (frame.button_size/5*4 + default_border*2) * (max-min+1+extra)
    local height = default_border + (frame.button_size/5*4 + default_border)

    frame.bagslots:SetWidth(width)
    frame.bagslots:SetHeight(height)
    for slot=min, max do
      if not frame.bagslots.slots[slot] then
        frame.bagslots.slots[slot] = {}
        frame.bagslots.slots[slot].frame = CreateFrame("CheckButton", name .. slot .. append, frame.bagslots, tpl)

        local icon = _G[frame.bagslots.slots[slot].frame:GetName() .. "IconTexture"]
        local border = _G[frame.bagslots.slots[slot].frame:GetName() .. "NormalTexture"]
        icon:SetTexCoord(.08, .92, .08, .92)
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", -1, 1)
        border:SetTexture("")

        local highlight = frame.bagslots.slots[slot].frame:GetHighlightTexture()
        highlight:SetTexture(.5, .5, .5, .5)

        local pushed = frame.bagslots.slots[slot].frame:GetPushedTexture()
        pushed:SetTexture(.5, .5, .5, .5)

        if frame == pfUI.bag.left then
          frame.bagslots.slots[slot].frame:SetID(slot + 4)
          frame.bagslots.slots[slot].frame.slot = slot + 3
        else
          frame.bagslots.slots[slot].frame.slot = slot
          frame.bagslots.slots[slot].slot = slot
        end

        local SlotEnter = frame.bagslots.slots[slot].frame:GetScript("OnEnter")
        frame.bagslots.slots[slot].frame:SetScript("OnEnter", function()
          for slot, f in ipairs(pfUI.bags[this.slot + 1].slots) do
            CreateBackdrop(f.frame, default_border)
            f.frame.backdrop:SetBackdropBorderColor(.2,1,.8,1)
          end
          SlotEnter(this)
        end)

        local SlotLeave = frame.bagslots.slots[slot].frame:GetScript("OnLeave")
        frame.bagslots.slots[slot].frame:SetScript("OnLeave", function()
          pfUI.bag:UpdateBag(this.slot + 1)
          SlotLeave()
        end)

        -- On TBC, the OnEvent function of the template scans for framenames,
        -- and obviously doesn't know the pf-Names. Therefore, triggering
        -- the update function on each frame manually
        if frame == pfUI.bag.left and BankFrameItemButton_Update then
          local SlotUpdate = frame.bagslots.slots[slot].frame:GetScript("OnUpdate")
          frame.bagslots.slots[slot].frame:SetScript("OnUpdate", function()
            if SlotUpdate then SlotUpdate(this) end
            BankFrameItemButton_Update(this)
          end)
        end
      end

      local left = (slot-min)*(frame.button_size/5*4+default_border*2) + default_border
      local top = -default_border

      frame.bagslots.slots[slot].frame:ClearAllPoints()
      frame.bagslots.slots[slot].frame:SetPoint("TOPLEFT", frame.bagslots, "TOPLEFT", left, top)
      frame.bagslots.slots[slot].frame:SetHeight(frame.button_size/5*4)
      frame.bagslots.slots[slot].frame:SetWidth(frame.button_size/5*4)

      CreateBackdrop(frame.bagslots.slots[slot].frame, default_border)
      frame.bagslots.slots[slot].frame:Show()

      if ( slot <= GetNumBankSlots() ) then
        frame.bagslots.slots[slot].frame.tooltipText = BANK_BAG
      else
        frame.bagslots.slots[slot].frame.tooltipText = BANK_BAG_PURCHASE
      end
    end

    if frame == pfUI.bag.left then
      if GetNumBankSlots() < NUM_BANKBAGSLOTS then
        if not frame.bagslots.buy then
          frame.bagslots.buy = CreateFrame("Button", "pfBagSlotBuy", frame.bagslots)
        end
        frame.bagslots.buy:SetPoint("RIGHT", frame.bagslots, "RIGHT", -default_border, 0)
        CreateBackdrop(frame.bagslots.buy, default_border)
        frame.bagslots.buy:SetHeight(frame.button_size/5*4)
        frame.bagslots.buy:SetWidth(frame.button_size/5*4)
        frame.bagslots.buy:SetText("+")
        frame.bagslots.buy:SetTextColor(.5,.5,1,1)
        frame.bagslots.buy:SetFont(pfUI.font_default, C.global.font_size, "OUTLINE")
        frame.bagslots.buy:SetScript("OnEnter", function ()
          frame.bagslots.buy:SetTextColor(1,1,1,1)
        end)
        frame.bagslots.buy:SetScript("OnLeave", function ()
          frame.bagslots.buy:SetTextColor(.5,.5,1,1)
        end)
        frame.bagslots.buy:SetScript("OnClick", function()
         StaticPopup_Show("CONFIRM_BUY_BANK_SLOT")
        end)
      else
        if frame.bagslots.buy then frame.bagslots.buy:Hide() end
      end
    end
  end

  function pfUI.bag:ReanchorAdditions()
    local frame = pfUI.bag.right
    local show_disenchant = (frame.disenchant:GetID() > 0)
    local show_picklock = (frame.picklock:GetID() > 0)
    if not show_disenchant then
      frame.disenchant:Hide()
      frame.picklock:SetPoint("TOPRIGHT", frame.open, "TOPLEFT", -default_border*3, 0)
    else
      frame.disenchant:Show()
      frame.picklock:SetPoint("TOPRIGHT", frame.disenchant, "TOPLEFT", -default_border*3, 0)
    end
    if not show_picklock then
      frame.picklock:Hide()
      if show_disenchant then
        frame.keys:SetPoint("TOPRIGHT", frame.disenchant, "TOPLEFT", -default_border*3, 0)
      else
        frame.keys:SetPoint("TOPRIGHT", frame.open, "TOPLEFT", -default_border*3, 0)
      end
    else
      frame.picklock:Show()
      frame.keys:SetPoint("TOPRIGHT", frame.picklock, "TOPLEFT", -default_border*3, 0)
    end
  end

  function pfUI.bag:UpdateCooldowns()
    local frame
    for bag=-2, 11 do
      local bagsize = GetContainerNumSlots(bag)
      if bag == -2 and pfUI.bag.showKeyring == true then bagsize = GetKeyRingSize() end
      for slot=1, bagsize do
        frame = pfUI.bags[bag] and pfUI.bags[bag].slots[slot] and pfUI.bags[bag].slots[slot].frame
        if frame and frame.hasItem and _G[frame:GetName() .. "Cooldown"] then
          ContainerFrame_UpdateCooldown(bag, frame)
        end
      end
    end
  end

  function pfUI.bag:UpdateItemLock()
    for bag=-2, 11 do
      local bagsize = GetContainerNumSlots(bag)
      if bag == -2 and pfUI.bag.showKeyring == true then bagsize = GetKeyRingSize() end
      for slot=1, bagsize do
        if pfUI.bags[bag] and pfUI.bags[bag].slots[slot] and pfUI.bags[bag].slots[slot].frame:IsShown() then
          local _, _, locked, _ = GetContainerItemInfo(bag, slot)
          if pfUI.bags[bag].slots[slot].locked ~= locked then
            SetItemButtonDesaturated(pfUI.bags[bag].slots[slot].frame, locked, 0.5, 0.5, 0.5)
            if pfUI.unusable then pfUI.unusable:UpdateSlot(bag, slot) end
            pfUI.bags[bag].slots[slot].locked = locked
          end
        end
      end
    end
  end

  function pfUI.bag:RefreshSpells()
    if not (pfUI.bag and pfUI.bag.right) then return end
    local _, _, offset, numSpells = GetSpellTabInfo(1)
    for spellIndex = offset + 1, offset + numSpells do
      local spellTexture = GetSpellTexture(spellIndex, BOOKTYPE_SPELL)
      -- scan for disenchant and pick lock
      for texture, widget in pairs(knownInventorySpellTextures) do
        if spellTexture and texture and strfind(spellTexture, texture) and pfUI.bag.right[widget.frame] then
          pfUI.bag.right[widget.frame]:SetID(spellIndex)
        end
      end
    end
    pfUI.bag:ReanchorAdditions()
  end

  function pfUI.bag:CreateAdditions(frame)
    -- bag additions
    if frame == pfUI.bag.right then
      -- bag close button
      if not frame.close then
        frame.close = CreateFrame("Button", "pfBagClose", frame)
        frame.close:SetPoint("TOPRIGHT", -default_border*1,-default_border )
        CreateBackdrop(frame.close, default_border)
        frame.close:SetHeight(12)
        frame.close:SetWidth(12)
        frame.close.texture = frame.close:CreateTexture("pfBagClose")
        frame.close.texture:SetTexture(pfUI.media["img:close"])
        frame.close.texture:ClearAllPoints()
        frame.close.texture:SetPoint("TOPLEFT", frame.close, "TOPLEFT", 2, -2)
        frame.close.texture:SetPoint("BOTTOMRIGHT", frame.close, "BOTTOMRIGHT", -2, 2)
        frame.close.texture:SetVertexColor(1,.25,.25,1)
        frame.close:SetScript("OnEnter", function ()
          frame.close.backdrop:SetBackdropBorderColor(1,.25,.25,1)
        end)

        frame.close:SetScript("OnLeave", function ()
          CreateBackdrop(frame.close, default_border)
        end)

       frame.close:SetScript("OnClick", function()
         CloseAllBags()
        end)
      end

      -- bags button
      if not frame.bags then
        frame.bags = CreateFrame("Button", "pfBagSlotShow", frame)
        frame.bags:SetPoint("TOPRIGHT", frame.close, "TOPLEFT", -default_border*3, 0)
        CreateBackdrop(frame.bags, default_border)
        frame.bags:SetHeight(12)
        frame.bags:SetWidth(12)
        frame.bags:SetTextColor(1,1,.25,1)
        frame.bags:SetFont(pfUI.font_default, C.global.font_size, "OUTLINE")
        frame.bags.texture = frame.bags:CreateTexture("pfBagArrowUp")
        frame.bags.texture:SetTexture(pfUI.media["img:up"])
        frame.bags.texture:ClearAllPoints()
        frame.bags.texture:SetPoint("TOPLEFT", frame.bags, "TOPLEFT", 3, -1)
        frame.bags.texture:SetPoint("BOTTOMRIGHT", frame.bags, "BOTTOMRIGHT", -3, 1)
        frame.bags.texture:SetVertexColor(.25,.25,.25,1)

        frame.bags:SetScript("OnEnter", function ()
          frame.bags.backdrop:SetBackdropBorderColor(1,1,.25,1)
          frame.bags.texture:SetVertexColor(1,1,.25,1)
          GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
          GameTooltip:SetText(_G.TUTORIAL_TITLE10)
          GameTooltip:Show()
        end)

        frame.bags:SetScript("OnLeave", function ()
          CreateBackdrop(frame.bags, default_border)
          frame.bags.texture:SetVertexColor(.25,.25,.25,1)
          if GameTooltip:IsOwned(this) then
            GameTooltip:Hide()
          end
        end)

        frame.bags:SetScript("OnClick", function()
          if pfUI.bag.right.bagslots:IsShown() then
            pfUI.bag.right.bagslots:Hide()
          else
            pfUI.bag.right.bagslots:Show()
          end
        end)
      end

      -- open button
      if not frame.open then
        frame.open = CreateFrame("Button", "pfBagSlotOpen", frame)
        frame.open:SetPoint("TOPRIGHT", frame.bags, "TOPLEFT", -default_border*3, 0)
        CreateBackdrop(frame.open, default_border)
        frame.open:SetHeight(12)
        frame.open:SetWidth(12)
        frame.open:SetTextColor(1,1,.25,1)
        frame.open:SetFont(pfUI.font_default, C.global.font_size, "OUTLINE")
        frame.open.texture = frame.open:CreateTexture("pfBagOpenContainer")
        frame.open.texture:SetTexture(pfUI.media["img:empty"])
        frame.open.texture:ClearAllPoints()
        frame.open.texture:SetPoint("TOPLEFT", frame.open, "TOPLEFT", 3, -1)
        frame.open.texture:SetPoint("BOTTOMRIGHT", frame.open, "BOTTOMRIGHT", -3, 1)
        frame.open.texture:SetVertexColor(.25,.25,.25,1)

        frame.open:SetScript("OnEnter", function ()
          frame.open.backdrop:SetBackdropBorderColor(1,1,.25,1)
          frame.open.texture:SetVertexColor(1,1,.25,1)
          GameTooltip:SetOwner(this, "ANCHOR_RIGHT")

          local bag, slot = GetNextOpenable()
          if bag and slot then
            GameTooltip:SetBagItem(bag, slot)
          else
            GameTooltip:SetText(_G.EMPTY)
          end
          GameTooltip:Show()
        end)

        frame.open:SetScript("OnLeave", function ()
          CreateBackdrop(frame.open, default_border)
          frame.open.texture:SetVertexColor(.25,.25,.25,1)
          if GameTooltip:IsOwned(this) then
            GameTooltip:Hide()
          end
        end)

        frame.open:SetScript("OnClick", function()
          -- open next container item
          local bag, slot = GetNextOpenable()
          if bag and slot then
            ClearCursor()
            if MerchantFrame:IsShown() then
              HideUIPanel(MerchantFrame)
            end
            UseContainerItem(bag, slot)
          end

          -- reload tootltip
          local bag, slot = GetNextOpenable()
          if bag and slot then
            GameTooltip:SetBagItem(bag, slot)
          else
            GameTooltip:SetText(_G.EMPTY)
          end
        end)
      end

      -- disenchant button
      if not frame.disenchant then
        frame.disenchant = CreateFrame("Button", "pfBagSlotDisenchant", frame)
        frame.disenchant:SetPoint("TOPRIGHT", frame.open, "TOPLEFT", -default_border*3, 0)
        CreateBackdrop(frame.disenchant, default_border)
        frame.disenchant:SetHeight(12)
        frame.disenchant:SetWidth(12)
        frame.disenchant:SetTextColor(1,1,.25,1)
        frame.disenchant:SetFont(pfUI.font_default, C.global.font_size, "OUTLINE")
        frame.disenchant.texture = frame.disenchant:CreateTexture("pfBagDisenchant")
        frame.disenchant.texture:SetTexture(pfUI.media["img:disenchant"])
        frame.disenchant.texture:ClearAllPoints()
        frame.disenchant.texture:SetPoint("TOPLEFT", frame.disenchant, "TOPLEFT", 3, -1)
        frame.disenchant.texture:SetPoint("BOTTOMRIGHT", frame.disenchant, "BOTTOMRIGHT", -3, 1)
        frame.disenchant.texture:SetVertexColor(.25,.25,.25,1)

        frame.disenchant:SetScript("OnEnter", function ()
          frame.disenchant.backdrop:SetBackdropBorderColor(1,1,.25,1)
          frame.disenchant.texture:SetVertexColor(1,1,.25,1)
          local id = this:GetID()
          if id and id > 0 then
            local name = GetSpellName(id, BOOKTYPE_SPELL)
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            GameTooltip:SetText(name)
            GameTooltip:Show()
          end
        end)

        frame.disenchant:SetScript("OnLeave", function ()
          CreateBackdrop(frame.disenchant, default_border)
          frame.disenchant.texture:SetVertexColor(.25,.25,.25,1)
          if GameTooltip:IsOwned(this) then
            GameTooltip:Hide()
          end
        end)

        frame.disenchant:SetScript("OnClick", function()
          local id = this:GetID()
          if id and id > 0 then
            CastSpell(id,BOOKTYPE_SPELL)
          end
        end)
      end

      -- pick lock button
      if not frame.picklock then
        frame.picklock = CreateFrame("Button", "pfBagSlotPicklock", frame)
        frame.picklock:SetPoint("TOPRIGHT", frame.disenchant, "TOPLEFT", -default_border*3, 0)
        CreateBackdrop(frame.picklock, default_border)
        frame.picklock:SetHeight(12)
        frame.picklock:SetWidth(12)
        frame.picklock:SetTextColor(1,1,.25,1)
        frame.picklock:SetFont(pfUI.font_default, C.global.font_size, "OUTLINE")
        frame.picklock.texture = frame.picklock:CreateTexture("pfBagPicklock")
        frame.picklock.texture:SetTexture(pfUI.media["img:picklock"])
        frame.picklock.texture:ClearAllPoints()
        frame.picklock.texture:SetPoint("TOPLEFT", frame.picklock, "TOPLEFT", 3, -1)
        frame.picklock.texture:SetPoint("BOTTOMRIGHT", frame.picklock, "BOTTOMRIGHT", -3, 1)
        frame.picklock.texture:SetVertexColor(.25,.25,.25,1)

        frame.picklock:SetScript("OnEnter", function ()
          frame.picklock.backdrop:SetBackdropBorderColor(1,1,.25,1)
          frame.picklock.texture:SetVertexColor(1,1,.25,1)
          local id = this:GetID()
          if id and id > 0 then
            local name = GetSpellName(id, BOOKTYPE_SPELL)
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            GameTooltip:SetText(name)
            GameTooltip:Show()
          end
        end)

        frame.picklock:SetScript("OnLeave", function ()
          CreateBackdrop(frame.picklock, default_border)
          frame.picklock.texture:SetVertexColor(.25,.25,.25,1)
          if GameTooltip:IsOwned(this) then
            GameTooltip:Hide()
          end
        end)

        frame.picklock:SetScript("OnClick", function()
          local id = this:GetID()
          if id and id > 0 then
            CastSpell(id,BOOKTYPE_SPELL)
          end
        end)
      end

      -- key button
      if not frame.keys then
        frame.keys = CreateFrame("Button", "pfBagSlotShow", frame)
        frame.keys:SetPoint("TOPRIGHT", frame.picklock, "TOPLEFT", -default_border*3, 0)
        CreateBackdrop(frame.keys, default_border)
        frame.keys:SetHeight(12)
        frame.keys:SetWidth(12)
        frame.keys:SetTextColor(1,1,.25,1)
        frame.keys:SetFont(pfUI.font_default, C.global.font_size, "OUTLINE")
        frame.keys.texture = frame.keys:CreateTexture("pfBagArrowUp")
        frame.keys.texture:SetTexture(pfUI.media["img:key"])
        frame.keys.texture:ClearAllPoints()
        frame.keys.texture:SetPoint("TOPLEFT", frame.keys, "TOPLEFT", 3, -1)
        frame.keys.texture:SetPoint("BOTTOMRIGHT", frame.keys, "BOTTOMRIGHT", -3, 1)
        frame.keys.texture:SetVertexColor(.25,.25,.25,1)

        frame.keys:SetScript("OnEnter", function ()
          frame.keys.backdrop:SetBackdropBorderColor(1,1,.25,1)
          frame.keys.texture:SetVertexColor(1,1,.25,1)
          GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
          GameTooltip:SetText(_G.KEYRING)
          GameTooltip:Show()
        end)

        frame.keys:SetScript("OnLeave", function ()
          CreateBackdrop(frame.keys, default_border)
          frame.keys.texture:SetVertexColor(.25,.25,.25,1)
          if GameTooltip:IsOwned(this) then
            GameTooltip:Hide()
          end
        end)

        frame.keys:SetScript("OnClick", function()
          if not pfUI.bag.showKeyring then
            pfUI.bag.showKeyring = true
          else
            pfUI.bag.showKeyring = nil
          end
          pfUI.bag:CheckFullUpdate()
        end)
      end

      -- sort button (anchors to keys, which is the always-present leftmost
      -- button in the dynamic chain — picklock and disenchant are class-gated)
      if not frame.sort then
        frame.sort = CreateFrame("Button", "pfBagSort", frame)
        frame.sort:SetPoint("TOPRIGHT", frame.keys, "TOPLEFT", -default_border*3, 0)
        CreateBackdrop(frame.sort, default_border)
        frame.sort:SetHeight(12)
        frame.sort:SetWidth(12)
        frame.sort.texture = frame.sort:CreateTexture("pfBagSortIcon")
        frame.sort.texture:SetTexture(pfUI.media["img:sort"])
        frame.sort.texture:ClearAllPoints()
        frame.sort.texture:SetPoint("TOPLEFT", frame.sort, "TOPLEFT", 2, -2)
        frame.sort.texture:SetPoint("BOTTOMRIGHT", frame.sort, "BOTTOMRIGHT", -2, 2)
        frame.sort.texture:SetVertexColor(.25,.25,.25,1)

        frame.sort:SetScript("OnEnter", function ()
          frame.sort.backdrop:SetBackdropBorderColor(1,1,.25,1)
          frame.sort.texture:SetVertexColor(1,1,.25,1)
          GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
          GameTooltip:SetText("Sort Bags")
          GameTooltip:Show()
        end)

        frame.sort:SetScript("OnLeave", function ()
          CreateBackdrop(frame.sort, default_border)
          frame.sort.texture:SetVertexColor(.25,.25,.25,1)
          if GameTooltip:IsOwned(this) then
            GameTooltip:Hide()
          end
        end)

        frame.sort:SetScript("OnClick", function()
          StartSort({0, 1, 2, 3, 4})
        end)
      end

      -- gold string
      if not frame.gold and (C.appearance.bags.movable == "1" or not pfUI.panel) then
        frame.gold = CreateFrame("Frame", "pfBagGoldString", frame)
        frame.gold:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 1)
        frame.gold:SetWidth(200)
        frame.gold:SetHeight(18)
        frame.gold:RegisterEvent("PLAYER_ENTERING_WORLD")
        frame.gold:RegisterEvent("PLAYER_MONEY")
        frame.gold:SetScript("OnEvent", function()
          frame.gold.text:SetText(CreateGoldString(GetMoney()))
        end)

        frame.gold.text = frame.gold.text or frame.gold:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        frame.gold.text:SetFontObject(GameFontWhite)
        frame.gold.text:SetJustifyH("RIGHT")
        frame.gold.text:SetAllPoints()
      end

      -- bag search
      if not frame.search then
        frame.search = CreateFrame("Frame", "pfBagSearch", frame)
        frame.search.db = {}
        frame.search:SetHeight(12)
        frame.search:SetPoint("TOPLEFT", frame, "TOPLEFT", default_border, -default_border)
        frame.search:SetPoint("TOPRIGHT", frame.sort, "TOPLEFT", -default_border*3, -default_border)
        CreateBackdrop(frame.search, default_border)

        frame.search.edit = CreateFrame("EditBox", "pfUIBagSearch", frame.search, "InputBoxTemplate")
        pfUIBagSearchLeft:SetTexture(nil)
        pfUIBagSearchMiddle:SetTexture(nil)
        pfUIBagSearchRight:SetTexture(nil)
        frame.search.edit:ClearAllPoints()
        frame.search.edit:SetPoint("TOPLEFT", frame.search, "TOPLEFT", default_border*2, 0)
        frame.search.edit:SetPoint("BOTTOMRIGHT", frame.search, "BOTTOMRIGHT", -default_border*2, 0)

        frame.search.edit:SetFont(pfUI.font_default, C.global.font_size, "OUTLINE")
        frame.search.edit:SetAutoFocus(false)
        frame.search.edit:SetText(T["Search"])
        frame.search.edit:SetTextColor(.5,.5,.5,1)

        frame.search.edit:SetScript("OnEditFocusGained", function()
          this:SetText("")
        end)

        frame.search.edit:SetScript("OnEditFocusLost", function()
          this:SetText(T["Search"])
          for bag=-2, 11 do
            local bagsize = GetContainerNumSlots(bag)
            if bag == -2 and pfUI.bag.showKeyring == true then bagsize = GetKeyRingSize() end
            for slot=1, bagsize do
              pfUI.bags[bag].slots[slot].frame:SetAlpha(1)
            end
          end
        end)

        frame.search.edit:SetScript("OnTextChanged", function()
          if this:GetText() == T["Search"] then return end
          for bag=-2, 11 do
            local bagsize = GetContainerNumSlots(bag)
            if bag == -2 and pfUI.bag.showKeyring == true then bagsize = GetKeyRingSize() end
            for slot=1, bagsize do
              pfUI.bags[bag].slots[slot].frame:SetAlpha(.25)
              local texture, itemCount, locked, quality, readable = GetContainerItemInfo(bag, slot)
              if itemCount then
                local itemLink = GetContainerItemLink(bag, slot)
                local itemstring = string.sub(itemLink, string.find(itemLink, "%[")+1, string.find(itemLink, "%]")-1)

                if C.appearance.bags.fulltext == "1" then
                  if not frame.search.db[itemLink] then
                    scanner:SetBagItem(bag, slot)
                    local text = scanner:Text()

                    local str = ""
                    for k, v in pairs(text) do
                      str = str .. (v[1] or "") .. (v[2] or "")
                    end

                    frame.search.db[itemLink] = strlower(str)
                  end

                  if strfind(frame.search.db[itemLink], strlower(this:GetText()), 1, true) then
                    pfUI.bags[bag].slots[slot].frame:SetAlpha(1)
                  end
                end

                if strfind(strlower(itemstring), strlower(this:GetText()), 1, true) then
                  pfUI.bags[bag].slots[slot].frame:SetAlpha(1)
                end
              end
            end
          end
        end)

        frame.search:SetScript("OnLeave", function()
          frame.search.edit:ClearFocus()
        end)

        frame.search:SetScript("OnHide", function()
          frame.search.edit:SetText(T["Search"])
          for bag = -2, 11 do
            if pfUI.bags[bag] then
              local bagsize = GetContainerNumSlots(bag)
              if bag == -2 and pfUI.bag.showKeyring == true then bagsize = GetKeyRingSize() end
              for slot = 1, bagsize do
                if pfUI.bags[bag] and pfUI.bags[bag].slots[slot] then
                  pfUI.bags[bag].slots[slot].frame:SetAlpha(1)
                end
              end
            end
          end
        end)

        frame.search.edit:SetScript("OnMouseUp", function()
          if arg1 == "RightButton" then
            this:ClearFocus()
          end
        end)

        frame.search:SetScript("OnHide", function()
          frame.search.edit:SetText(T["Search"])
          for bag = -2, 11 do
            if pfUI.bags[bag] then
              local bagsize = GetContainerNumSlots(bag)
              if bag == -2 and pfUI.bag.showKeyring == true then bagsize = GetKeyRingSize() end
              for slot = 1, bagsize do
                if pfUI.bags[bag] and pfUI.bags[bag].slots[slot] then
                  pfUI.bags[bag].slots[slot].frame:SetAlpha(1)
                end
              end
            end
          end
        end)
      end
    else
      -- bankframe

      -- bag close button
      if not frame.close then
        frame.close = CreateFrame("Button", "pfBagClose", frame)
        frame.close:SetPoint("TOPRIGHT", -default_border*1,-default_border )
        CreateBackdrop(frame.close, default_border)
        frame.close:SetHeight(12)
        frame.close:SetWidth(12)
        frame.close.texture = frame.close:CreateTexture("pfBagClose")
        frame.close.texture:SetTexture(pfUI.media["img:close"])
        frame.close.texture:ClearAllPoints()
        frame.close.texture:SetPoint("TOPLEFT", frame.close, "TOPLEFT", 2, -2)
        frame.close.texture:SetPoint("BOTTOMRIGHT", frame.close, "BOTTOMRIGHT", -2, 2)
        frame.close.texture:SetVertexColor(1,.25,.25,1)
        frame.close:SetScript("OnEnter", function ()
          frame.close.backdrop:SetBackdropBorderColor(1,.25,.25,1)
        end)

        frame.close:SetScript("OnLeave", function ()
          CreateBackdrop(frame.close, default_border)
        end)

       frame.close:SetScript("OnClick", function()
         CloseBankFrame()
        end)
      end

      -- bags button
      if not frame.bags then
        frame.bags = CreateFrame("Button", "pfBagSlotShow", frame)
        frame.bags:SetPoint("TOPRIGHT", frame.close, "TOPLEFT", -default_border*3, 0)
        CreateBackdrop(frame.bags, default_border)
        frame.bags:SetHeight(12)
        frame.bags:SetWidth(12)
        frame.bags:SetTextColor(1,1,.25,1)
        frame.bags:SetFont(pfUI.font_default, C.global.font_size, "OUTLINE")
        frame.bags.texture = frame.bags:CreateTexture("pfBagArrowUp")
        frame.bags.texture:SetTexture(pfUI.media["img:up"])
        frame.bags.texture:ClearAllPoints()
        frame.bags.texture:SetPoint("TOPLEFT", frame.bags, "TOPLEFT", 3, -1)
        frame.bags.texture:SetPoint("BOTTOMRIGHT", frame.bags, "BOTTOMRIGHT", -3, 1)
        frame.bags.texture:SetVertexColor(.25,.25,.25,1)

        frame.bags:SetScript("OnEnter", function ()
          frame.bags.backdrop:SetBackdropBorderColor(1,1,.25,1)
          frame.bags.texture:SetVertexColor(1,1,.25,1)
          GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
          GameTooltip:SetText(_G.TUTORIAL_TITLE10)
          GameTooltip:Show()
        end)

        frame.bags:SetScript("OnLeave", function ()
          CreateBackdrop(frame.bags, default_border)
          frame.bags.texture:SetVertexColor(.25,.25,.25,1)
          if GameTooltip:IsOwned(this) then
            GameTooltip:Hide()
          end
        end)

        frame.bags:SetScript("OnClick", function()
          if pfUI.bag.left.bagslots:IsShown() then
            pfUI.bag.left.bagslots:Hide()
          else
            pfUI.bag.left.bagslots:Show()
          end
        end)
      end

      -- sort button (bank)
      if not frame.sort then
        frame.sort = CreateFrame("Button", "pfBankSort", frame)
        frame.sort:SetPoint("TOPRIGHT", frame.bags, "TOPLEFT", -default_border*3, 0)
        CreateBackdrop(frame.sort, default_border)
        frame.sort:SetHeight(12)
        frame.sort:SetWidth(12)
        frame.sort.texture = frame.sort:CreateTexture("pfBankSortIcon")
        frame.sort.texture:SetTexture(pfUI.media["img:sort"])
        frame.sort.texture:ClearAllPoints()
        frame.sort.texture:SetPoint("TOPLEFT", frame.sort, "TOPLEFT", 2, -2)
        frame.sort.texture:SetPoint("BOTTOMRIGHT", frame.sort, "BOTTOMRIGHT", -2, 2)
        frame.sort.texture:SetVertexColor(.25,.25,.25,1)

        frame.sort:SetScript("OnEnter", function ()
          frame.sort.backdrop:SetBackdropBorderColor(1,1,.25,1)
          frame.sort.texture:SetVertexColor(1,1,.25,1)
          GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
          GameTooltip:SetText("Sort Bank")
          GameTooltip:Show()
        end)

        frame.sort:SetScript("OnLeave", function ()
          CreateBackdrop(frame.sort, default_border)
          frame.sort.texture:SetVertexColor(.25,.25,.25,1)
          if GameTooltip:IsOwned(this) then
            GameTooltip:Hide()
          end
        end)

        frame.sort:SetScript("OnClick", function()
          StartSort({-1, 5, 6, 7, 8, 9, 10})
        end)
      end
    end
  end
end)