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

local ItemClass   = Enum.ItemClass
local ItemQuality = Enum.ItemQuality

-- Lower prefix = sorted earlier in the bag.
local function SortCategoryPrefix(itemId, classID, quality)
  if itemId == HEARTHSTONE_ITEM_ID     then return "00" end
  if quality == ItemQuality.Poor       then return "13" end  -- gray always last
  if classID == ItemClass.Weapon or classID == ItemClass.Armor then
    if quality and quality >= ItemQuality.Epic then return "01" end  -- Epic+ gear
    if quality == ItemQuality.Rare             then return "02" end  -- Rare gear
    if quality == ItemQuality.Uncommon         then return "03" end  -- Uncommon gear
    return "04"                                                      -- Common/poor gear
  end
  if classID == ItemClass.Consumable then return "05" end
  if classID == ItemClass.Reagent    then return "06" end
  if classID == ItemClass.Tradegoods then return "07" end
  if classID == ItemClass.Questitem  then return "08" end
  -- Non-gear items without a specific type, sorted by quality
  if quality and quality >= ItemQuality.Epic then return "09" end
  if quality == ItemQuality.Rare             then return "10" end
  if quality == ItemQuality.Uncommon         then return "11" end
  return "12"
end

-- Larger stacks sort first among identically-named items; invert + zero-pad
-- so it sorts lexicographically.
local function SortCountSuffix(count)
  local s = "000000" .. (999999 - (count or 0))
  return string.sub(s, -6)
end

local function SortKey(itemId, name, classID, subClassID, quality, count)
  -- Zero-pad the class/subclass so the secondary grouping sorts numerically
  -- (as a string, "10" would otherwise precede "2").
  return SortCategoryPrefix(itemId, classID, quality)
    .. string.format("%02d|%02d|", classID or 99, subClassID or 99)
    .. (name or "zzz") .. "|" .. SortCountSuffix(count)
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

-- Bag family bitmask (1 << (familyID-1)); 0 = general-purpose (holds
-- anything). Backpack (0) and bank (-1) are always general. A specialty
-- bag's family comes from the equipped bag item -- ClassicAPI derives it
-- from the container subclass when the raw field is empty (Turtle leaves
-- bags' m_bagFamily at 0), so quivers/soul/profession bags report properly.
local function BagFamily(bag)
  if bag == 0 or bag == -1 then return 0 end
  local id = GetInventoryItemID("player", ContainerIDToInventoryID(bag))
  return id and C_Item.GetItemFamily(id) or 0
end

local function BuildSortGrid()
  local bagList = libbagsort.bagList
  libbagsort.itemGrid = {}
  local normalItems = {}
  local poorItems   = {}

  -- Destination cells, split by the family they can accept. A specialty
  -- bag's slots only take items of its own family; general slots take
  -- anything. Cells are collected in forward order (bag order, slot 1..n).
  local generalCells   = {}   -- { {bag=,slot=}, ... }
  local specialtyCells = {}   -- family -> { {bag=,slot=}, ... }

  for _, bag in ipairs(bagList) do
    local fam = BagFamily(bag)
    local numSlots = GetContainerNumSlots(bag)
    if numSlots > 0 then
      libbagsort.itemGrid[bag] = {}
      for slot = 1, numSlots do
        if fam == 0 then
          tinsert(generalCells, {bag=bag, slot=slot})
        else
          specialtyCells[fam] = specialtyCells[fam] or {}
          tinsert(specialtyCells[fam], {bag=bag, slot=slot})
        end

        local itemId = C_Container.GetContainerItemID(bag, slot)
        if itemId then
          -- C_Item.GetItemInfo is the full 18-field tuple; classID/subClassID
          -- sit at positions 12/13. We categorize on those numeric class IDs
          -- rather than the localized itemType/itemSubType strings. (pfUI's
          -- shimmed global GetItemInfo is only 10 fields and lacks them.)
          local name, _, quality, _, _, _, _, _, _, _, _, classID, subClassID = C_Item.GetItemInfo(itemId)
          local _, count = GetContainerItemInfo(bag, slot)
          local item = {
            key     = SortKey(itemId, name, classID, subClassID, quality, count),
            -- vanilla items carry at most one family bit, so equality
            -- against a bag family suffices (no bit.band needed).
            family  = C_Item.GetItemFamily(itemId) or 0,
            srcBag  = bag,
            srcSlot = slot,
            curBag  = bag,
            curSlot = slot,
          }
          if quality == ItemQuality.Poor then
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

  -- Forward pass: route each normal item into the next free cell that
  -- accepts it -- a matching specialty bag first, overflowing to general.
  local genIdx  = 1
  local specIdx = {}   -- family -> next free index into specialtyCells[family]
  for _, item in ipairs(normalItems) do
    local cell
    local fam = item.family
    if fam ~= 0 and specialtyCells[fam] then
      local i = specIdx[fam] or 1
      if i <= table.getn(specialtyCells[fam]) then
        cell = specialtyCells[fam][i]
        specIdx[fam] = i + 1
      end
    end
    if not cell and genIdx <= table.getn(generalCells) then
      cell = generalCells[genIdx]
      genIdx = genIdx + 1
    end
    if not cell then break end
    item.destBag  = cell.bag
    item.destSlot = cell.slot
  end

  -- Reverse pass: poor items are general; fill remaining general cells from
  -- the back, stopping before the ones the forward pass already claimed.
  local genBack = table.getn(generalCells)
  for _, item in ipairs(poorItems) do
    if genBack < genIdx then break end
    local cell = generalCells[genBack]
    genBack = genBack - 1
    item.destBag  = cell.bag
    item.destSlot = cell.slot
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
