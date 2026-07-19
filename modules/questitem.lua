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

  pfUI.questitem = CreateFrame("Frame", "pfQuestItemScanner", UIParent)
  pfUI.questitem:RegisterEvent("PLAYER_ENTERING_WORLD")
  pfUI.questitem:RegisterEvent("QUEST_LOG_UPDATE")
  pfUI.questitem:RegisterEvent("QUEST_ACCEPTED")
  pfUI.questitem:RegisterEvent("QUEST_REMOVED")
  pfUI.questitem:SetScript("OnEvent", function()
    if C.tooltip.questitem.showquest ~= "1" then return end
    if event == "QUEST_ACCEPTED" then          -- arg1 = logIndex, arg2 = questID
      if not AddQuest(arg2) then                -- cache cold (rare) -> reseed
        this.seeding = true
        this.run = GetTime() + .5
      end
    elseif event == "QUEST_REMOVED" then        -- arg1 = questID
      RemoveQuest(arg1)
    elseif event == "PLAYER_ENTERING_WORLD" then
      this.seeding = true                       -- seed pre-existing quests
      this.run = GetTime() + .5
    elseif event == "QUEST_LOG_UPDATE" and this.seeding then
      this.run = GetTime() + .5                 -- keep retrying while cache warms
    end
  end)

  pfUI.questitem:SetScript("OnUpdate", function()
    if not this.run or GetTime() < this.run then return end
    this.run = nil
    if Seed() then this.seeding = nil end
  end)

  pfUI.questitem.UpdateConfig = function()
    if C.tooltip.questitem.showquest ~= "1" then return end
    pfUI.questitem.seeding = true
    pfUI.questitem.run = GetTime() + .5
  end

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
