-- load pfUI environment
setfenv(1, pfUI:GetEnvironment())

-- return instantly when another libbagsort is already active
if pfUI.api.libbagsort then return end

-- Bag sorter: consolidates partial stacks then sorts by category/name.
-- Adapted from the algo in Bagnon/lib/BagSort.lua.
local libbagsort = CreateFrame("Frame", "pfLibBagSort")
pfUI.api.libbagsort = libbagsort
libbagsort.itemGrid = {}
libbagsort.bagList  = nil

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
  libbagsort.itemGrid = {}
  libbagsort.bagList  = nil
  libbagsort:UnregisterEvent("BAG_UPDATE_DELAYED")
  libbagsort:SetScript("OnEvent", nil)
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
  local bagList = libbagsort.bagList
  libbagsort.itemGrid = {}
  local normalItems = {}
  local poorItems   = {}
  local bagCount    = 0
  local bagSlots    = {}

  for _, bag in ipairs(bagList) do
    bagCount = bagCount + 1
    local numSlots = GetContainerNumSlots(bag)
    bagSlots[bagCount] = numSlots
    if numSlots > 0 then
      libbagsort.itemGrid[bag] = {}
      for slot = 1, numSlots do
        local itemId = C_Container.GetContainerItemID(bag, slot)
        if itemId then
          -- pfUI's compat layer shims GetItemInfo to the modern 10-field
          -- signature (inserts nil for itemLevel between quality and
          -- minlevel) — so itype/subtype sit at positions 6/7, not 5/6.
          local name, _, quality, _, _, itype, subtype = GetItemInfo(itemId)
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
          libbagsort.itemGrid[bag][slot] = item
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
    local grid = libbagsort.itemGrid[item.srcBag][item.srcSlot]
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
    local grid = libbagsort.itemGrid[item.srcBag][item.srcSlot]
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
  for _, bagGrid in pairs(libbagsort.itemGrid) do
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
        local displaced = libbagsort.itemGrid[dBag][dSlot]
        C_Container.SwapItems(curBag, curSlot, dBag, dSlot)
        libbagsort.itemGrid[dBag][dSlot]     = info
        libbagsort.itemGrid[curBag][curSlot] = displaced
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
local function OnEvent()
  if event == "BAG_UPDATE_DELAYED" then
    libbagsort:UnregisterEvent("BAG_UPDATE_DELAYED")
    libbagsort:SetScript("OnEvent", nil)
    RunSortPhase()
  end
end

-- Sort the listed bag IDs in-place: consolidate partial stacks (one
-- BAG_UPDATE_DELAYED cycle), then place items by category/name/quality.
-- e.g. `libbagsort:Sort({0, 1, 2, 3, 4})` for the main bags;
-- `{-1, 5, 6, 7, 8, 9, 10}` for the bank.
function libbagsort:Sort(bagList)
  ClearSortData()
  self.bagList = bagList

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
    self:SetScript("OnEvent", OnEvent)
    self:RegisterEvent("BAG_UPDATE_DELAYED")
    return
  end

  RunSortPhase()
end
