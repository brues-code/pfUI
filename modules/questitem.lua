pfUI:RegisterModule("questitem", function ()
  -- [itemID] = { index = questLogIndex, count = requiredCount }. Rebuilt
  -- on QUEST_LOG_UPDATE from ClassicAPI's per-quest cached requirements.
  local requiredItems = {}

  local function AddTooltip(frame, itemID)
    if not itemID then return end
    if C.tooltip.questitem.showquest ~= "1" then return end

    -- Replace the existing "Quest Item" line if the tooltip already has one.
    local replace = nil
    if frame and _G[frame:GetName().."TextLeft2"] then
      if _G[frame:GetName().."TextLeft2"]:GetText() == ITEM_BIND_QUEST then
        replace = true
      end
    end

    local entry = requiredItems[itemID]
    if not entry and not replace then return end

    local quest, level = UNKNOWN, 255
    if entry then quest, level = GetQuestLogTitle(entry.index) end
    if not quest then return end

    local color = GetDifficultyColor(level)

    if C.tooltip.questitem.showcount == "1" and entry and entry.count and entry.count > 0 then
      local have = C_Item.GetItemCount(itemID) or 0
      quest = string.format("%s |cffaaaaaa[%s/%s]", quest, have, entry.count)
    end

    if replace then
      _G[frame:GetName().."TextLeft2"]:SetText("|cffffffff"..ITEM_BIND_QUEST..": |r" .. quest)
      _G[frame:GetName().."TextLeft2"]:SetTextColor(color.r, color.g, color.b)
    elseif quest ~= UNKNOWN then
      frame:AddLine("|cffffffff"..ITEM_BIND_QUEST..": |r" .. quest, color.r, color.g, color.b)
    end

    frame:Show()
  end

  pfUI.questitem = CreateFrame("Frame", "pfQuestItemScanner", UIParent)
  pfUI.questitem:RegisterEvent("PLAYER_ENTERING_WORLD")
  pfUI.questitem:RegisterEvent("QUEST_LOG_UPDATE")
  pfUI.questitem:SetScript("OnEvent", function()
    -- debounce rebuilds — QUEST_LOG_UPDATE fires in bursts
    this.run = GetTime() + .5
  end)

  pfUI.questitem:SetScript("OnUpdate", function()
    if C.tooltip.questitem.showquest ~= "1" then return end
    if not this.run or GetTime() < this.run then return end

    for k in pairs(requiredItems) do requiredItems[k] = nil end

    -- GetQuestIDForLogIndex returns nil past the end, 0 for headers, else
    -- the questID. GetQuestDetails reads the engine's static-info cache —
    -- nil if not yet populated; we'll catch it on the next refresh.
    local i = 1
    while true do
      local questID = C_QuestLog.GetQuestIDForLogIndex(i)
      if questID == nil then break end
      if questID > 0 then
        local details = C_QuestLog.GetQuestDetails(questID)
        if details and details.requirements then
          for _, req in ipairs(details.requirements) do
            if req.kind == "item" and req.id and req.id > 0 then
              requiredItems[req.id] = { index = i, count = req.count }
            end
          end
        end
      end
      i = i + 1
    end

    this.run = nil
  end)

  -- reload quest entries on config change
  pfUI.questitem.UpdateConfig = function()
    pfUI.questitem.run = GetTime() + .5
  end

  -- regular tooltip: catch every Show via a child frame's OnShow, then ask
  -- the tooltip directly for the item it's displaying. Replaces a libtooltip
  -- indirection that did the same query with extra caching layers.
  pfUI.questitem.tooltip = CreateFrame("Frame", "pfQuestItems", GameTooltip)
  pfUI.questitem.tooltip:SetScript("OnShow", function()
    if GameTooltip:HasItem() then
      local _, _, id = GameTooltip:GetItem()
      if id then AddTooltip(GameTooltip, id) end
    end
  end)

  -- itemref tooltip (chat link clicks): hooksecurefunc runs after SetItemRef
  -- populates ItemRefTooltip, so we just read the item back out of the tooltip
  -- instead of re-parsing the "item:NNN" out of the link string.
  pfUI.hooksecurefunc("SetItemRef", function()
    if IsModifierKeyDown() then return end
    if ItemRefTooltip:HasItem() then
      local _, _, id = ItemRefTooltip:GetItem()
      if id then AddTooltip(ItemRefTooltip, id) end
    end
  end)
end)
