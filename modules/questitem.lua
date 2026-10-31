pfUI:RegisterModule("questitem", function ()
  local requiredItems = {}

  local function AddQuest(questID)
    local details = C_QuestLog.GetQuestDetails(questID)
    if not details then return false end
    if details.requirements then
      for _, req in ipairs(details.requirements) do
        if req.kind == "item" and req.id and req.id > 0 then
          requiredItems[req.id] = {
            questID = questID,
            title = details.title,
            level = details.level,
            count = req.count,
          }
        end
      end
    end
    return true
  end

  local function RemoveQuest(questID)
    for itemID, entry in pairs(requiredItems) do
      if entry.questID == questID then requiredItems[itemID] = nil end
    end
  end

  local function Seed()
    for k in pairs(requiredItems) do requiredItems[k] = nil end
    local complete = true
    local i = 1
    while true do
      local questID = C_QuestLog.GetQuestIDForLogIndex(i)
      if questID == nil then break end
      if questID > 0 and not AddQuest(questID) then complete = false end
      i = i + 1
    end
    return complete
  end

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
    if entry then quest, level = entry.title, entry.level end
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

  -- Seed half a second after the last trigger; each trigger pushes it back.
  local seeding, timer
  local function QueueSeed()
    if C.tooltip.questitem.showquest ~= "1" then return end
    seeding = true
    if timer then timer:Cancel() end
    timer = C_Timer.NewTimer(.5, function()
      if Seed() then seeding = nil end
    end)
  end

  -- seed pre-existing quests
  pfUI.events:RegisterFrameEventAndCallback("PLAYER_ENTERING_WORLD", QueueSeed)

  -- keep retrying while the quest cache warms
  pfUI.events:RegisterFrameEventAndCallback("QUEST_LOG_UPDATE", function()
    if seeding then QueueSeed() end
  end)

  -- a cold cache (rare) needs a full reseed
  pfUI.events:RegisterFrameEventAndCallback("QUEST_ACCEPTED", function(_, _, questID)
    if not AddQuest(questID) then QueueSeed() end
  end)

  pfUI.events:RegisterFrameEventAndCallback("QUEST_REMOVED", function(_, questID)
    RemoveQuest(questID)
  end)

  pfUI.questitem = { UpdateConfig = QueueSeed }

  pfUI.questitem.tooltip = CreateFrame("Frame", "pfQuestItems", GameTooltip)
  pfUI.questitem.tooltip:SetScript("OnShow", function()
    if GameTooltip:HasItem() then
      local _, _, id = GameTooltip:GetItem()
      if id then AddTooltip(GameTooltip, id) end
    end
  end)

  hooksecurefunc("SetItemRef", function()
    if IsModifierKeyDown() then return end
    if ItemRefTooltip:HasItem() then
      local _, _, id = ItemRefTooltip:GetItem()
      if id then AddTooltip(ItemRefTooltip, id) end
    end
  end)
end)
