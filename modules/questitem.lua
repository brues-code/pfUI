pfUI:RegisterModule("questitem", function ()
  local questlog = {}
  local itemcache = {}

  local function AddTooltip(frame, item, itemID)
    -- abort when no item was given
    if not item then return end

    -- abort if questitem is disabled
    if C.tooltip.questitem.showquest ~= "1" then return end

    -- check if we can replace the questitem string
    local replace = nil
    if frame and _G[frame:GetName().."TextLeft2"] then
      if _G[frame:GetName().."TextLeft2"]:GetText() == ITEM_BIND_QUEST then
        replace = true
      end
    end

    -- set fallbacks for unidentified quests
    local quest, level = UNKNOWN, 255

    -- check cache for already existing values
    if itemcache[item] and itemcache[item] == false then
      -- not a quest item
      return
    elseif itemcache[item] then
      -- read from caches
      quest, level = GetQuestLogTitle(itemcache[item])
    elseif item then
      -- scan for quests
      for id, text in pairs(questlog) do
        if string.find(string.lower((text or "")), string.lower(item), 1) then
          quest, level = GetQuestLogTitle(id)
          itemcache[item] = id
          break
        end
      end
    end

    -- mark non quest items
    if not itemcache[item] and not replace then
      itemcache[item] = false
      return
    end

    -- return on invalid/empty quest results
    if not quest then return end

    -- read difficulty color
    local color = GetDifficultyColor(level)

    -- read item counts
    if C.tooltip.questitem.showcount == "1" and itemcache[item] and itemcache[item] ~= false then
      local _, _, required = strfind(string.lower(questlog[itemcache[item]]), "_"..string.lower(item).."_(.-)_")
      if required then
        local have = itemID and C_Item.GetItemCount(itemID) or 0
        quest = string.format("%s |cffaaaaaa[%s/%s]", quest, have, required)
      end
    end

    -- add quest to quest item
    if replace then
      _G[frame:GetName().."TextLeft2"]:SetText("|cffffffff"..ITEM_BIND_QUEST..": |r" .. quest)
      _G[frame:GetName().."TextLeft2"]:SetTextColor(color.r, color.g, color.b)
    elseif quest ~= UNKNOWN then
      frame:AddLine("|cffffffff"..ITEM_BIND_QUEST..": |r" .. quest, color.r, color.g, color.b)
    end

    frame:Show()
  end

  -- initialize questlog scanner
  pfUI.questitem = CreateFrame("Frame", "pfQuestItemScanner", UIParent)
  pfUI.questitem:RegisterEvent("PLAYER_ENTERING_WORLD")
  pfUI.questitem:RegisterEvent("QUEST_LOG_UPDATE")
  pfUI.questitem:SetScript("OnEvent", function()
    -- queue update events to run in .5 seconds
    this.run = GetTime() + .5
  end)

  pfUI.questitem:SetScript("OnUpdate", function()
    if C.tooltip.questitem.showquest ~= "1" then return end

    -- skip if nothing to do
    if not this.run or GetTime() < this.run then return end

    -- clear item caches
    for name, quest in pairs(itemcache) do
      itemcache[name] = nil
    end

    -- reload quests
    local text, objective, objcount, objtext, header, _
    local logid = GetQuestLogSelection()
    for quest=1, 50 do
      SelectQuestLogEntry(quest)

      -- detect and ignore quest headers
      _, _, _, header = GetQuestLogTitle(quest)

      if not header then
        text, objective = GetQuestLogQuestText()
        objcount = GetNumQuestLeaderBoards()
        questlog[quest] = string.format("%s:%s", (text or ""), (objective or ""))

        -- scan objectives
        if objcount > 0 then
          for i=1, objcount do
            objtext = GetQuestLogLeaderBoard(i)
            local _, _, obj, cur, req = strfind((objtext or ""), "(.*):%s*([%d]+)%s*/%s*([%d]+)")
            if obj and req then
              questlog[quest] = string.format("%s:_%s_%s_", questlog[quest], obj, req)
            else
              questlog[quest] = string.format("%s:%s", questlog[quest], (objtext or ""))
            end
          end
        end
      else
        questlog[quest] = nil
      end
    end

    -- restore questlog selection
    SelectQuestLogEntry(logid)
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
      local name, _, id = GameTooltip:GetItem()
      if name and id then AddTooltip(GameTooltip, name, id) end
    end
  end)

  -- itemref tooltip (chat link clicks): hooksecurefunc runs after SetItemRef
  -- populates ItemRefTooltip, so we just read the item back out of the tooltip
  -- instead of re-parsing the "item:NNN" out of the link string.
  hooksecurefunc("SetItemRef", function()
    if IsAltKeyDown() or IsShiftKeyDown() or IsControlKeyDown() then return end
    if ItemRefTooltip:HasItem() then
      local name, _, id = ItemRefTooltip:GetItem()
      if name and id then AddTooltip(ItemRefTooltip, name, id) end
    end
  end)
end)
