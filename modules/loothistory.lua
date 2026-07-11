pfUI:RegisterNewModule("loothistory", "Loot History")
pfUI:RegisterModule("loothistory", function ()
  local rawborder, border = GetBorderSize()

  -- Layout
  local ITEM_H, PLAYER_H = 24, 18
  local ITEM_W, PLAYER_W = 350, 330

  -- rollType constants returned by C_LootHistory.GetPlayerInfo (0/1/2; vanilla
  -- has no disenchant roll).
  local ROLL_PASS, ROLL_NEED, ROLL_GREED = 0, 1, 2
  local ROLL_TEX = {
    [ROLL_NEED]  = "Interface\\Buttons\\UI-GroupLoot-Dice-Up",
    [ROLL_GREED] = "Interface\\Buttons\\UI-GroupLoot-Coin-Up",
    [ROLL_PASS]  = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
  }
  local WINMARK = "Interface\\Buttons\\UI-CheckBox-Check"
  local QUESTIONMARK = "Interface\\Icons\\INV_Misc_QuestionMark"

  local function ClassColor(class)
    local c = class and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
  end

  -- Paint an item row's icon/name/quality from a loaded Item mixin.
  local function RenderItemVisual(f, item)
    local r, g, b = 1, 1, 1
    local qc = item:GetItemQualityColor()
    if qc then r, g, b = qc.r, qc.g, qc.b end
    f.icon:SetTexture(item:GetItemIcon())
    f.iconbg:SetBackdropBorderColor(r, g, b, 1)
    f.name:SetText(item:GetItemName() or UNKNOWN)
    f.name:SetTextColor(r, g, b)
  end

  local function ShowRetrieving(f)
    f.icon:SetTexture(QUESTIONMARK)
    f.iconbg:SetBackdropBorderColor(1, .3, .3, 1)
    f.name:SetText(T["Retrieving item information..."])
    f.name:SetTextColor(1, .3, .3)
  end

  -- expansion state keyed on the stable rollID (survives ring-index shifts)
  local expanded = {}

  -- ==========================================================================
  -- Window
  -- ==========================================================================
  pfUI.loothistory = CreateFrame("Frame", "pfLootHistory", UIParent)
  pfUI.loothistory:SetFrameStrata("DIALOG")
  pfUI.loothistory:SetSize(380, 490)
  pfUI.loothistory:SetPoint("CENTER", 0, 0)
  pfUI.loothistory:SetMovable(true)
  pfUI.loothistory:EnableMouse(true)
  pfUI.loothistory:RegisterForDrag("LeftButton")
  pfUI.loothistory:SetScript("OnDragStart", function() this:StartMoving() end)
  pfUI.loothistory:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
  pfUI.loothistory:Hide()

  CreateBackdrop(pfUI.loothistory, nil, true, .75)
  CreateBackdropShadow(pfUI.loothistory)
  tinsert(UISpecialFrames, "pfLootHistory")

  pfUI.loothistory.caption = pfUI.loothistory:CreateFontString("Status", "LOW", "GameFontNormal")
  pfUI.loothistory.caption:SetFont(pfUI.font_default, C.global.font_size + 4, "OUTLINE")
  pfUI.loothistory.caption:SetTextColor(.2, 1, .8, 1)
  pfUI.loothistory.caption:SetPoint("TOP", 0, -10)
  pfUI.loothistory.caption:SetText(T["Loot History"])

  -- close button
  pfUI.loothistory.close = CreateFrame("Button", nil, pfUI.loothistory)
  pfUI.loothistory.close:SetPoint("TOPRIGHT", -border*2, -border*2)
  CreateBackdrop(pfUI.loothistory.close)
  pfUI.loothistory.close:SetSize(15, 15)
  pfUI.loothistory.close.texture = pfUI.loothistory.close:CreateTexture("pfLootHistoryClose")
  pfUI.loothistory.close.texture:SetTexture(pfUI.media["img:close"])
  pfUI.loothistory.close.texture:SetPoint("TOPLEFT", pfUI.loothistory.close, "TOPLEFT", 4, -4)
  pfUI.loothistory.close.texture:SetPoint("BOTTOMRIGHT", pfUI.loothistory.close, "BOTTOMRIGHT", -4, 4)
  pfUI.loothistory.close.texture:SetVertexColor(1, .25, .25, 1)
  pfUI.loothistory.close:SetScript("OnEnter", function()
    CreateBackdrop(pfUI.loothistory.close)
    pfUI.loothistory.close.backdrop:SetBackdropBorderColor(1, .25, .25, 1)
  end)
  pfUI.loothistory.close:SetScript("OnLeave", function() CreateBackdrop(pfUI.loothistory.close) end)
  pfUI.loothistory.close:SetScript("OnClick", function() pfUI.loothistory:Hide() end)

  -- clear button
  pfUI.loothistory.clear = CreateFrame("Button", nil, pfUI.loothistory, "UIPanelButtonTemplate")
  SkinButton(pfUI.loothistory.clear)
  pfUI.loothistory.clear:SetSize(60, 16)
  pfUI.loothistory.clear:SetPoint("TOPLEFT", 10, -8)
  pfUI.loothistory.clear:SetText(T["Clear"])
  pfUI.loothistory.clear:SetScript("OnClick", function() C_LootHistory.Clear() end)

  -- scroll frame
  pfUI.loothistory.scroll = CreateScrollFrame("pfLootHistoryScroll", pfUI.loothistory)
  pfUI.loothistory.scroll:SetSize(360, 440)
  pfUI.loothistory.scroll:SetPoint("BOTTOM", 0, 10)

  pfUI.loothistory.scroll.backdrop = CreateFrame("Frame", nil, pfUI.loothistory.scroll)
  pfUI.loothistory.scroll.backdrop:SetFrameLevel(1)
  pfUI.loothistory.scroll.backdrop:SetPoint("TOPLEFT", pfUI.loothistory.scroll, "TOPLEFT", -5, 5)
  pfUI.loothistory.scroll.backdrop:SetPoint("BOTTOMRIGHT", pfUI.loothistory.scroll, "BOTTOMRIGHT", 5, -5)
  CreateBackdrop(pfUI.loothistory.scroll.backdrop, nil, true)

  local list = CreateScrollChild("pfLootHistoryList", pfUI.loothistory.scroll)
  pfUI.loothistory.list = list

  -- ==========================================================================
  -- Frame pools
  -- ==========================================================================
  local itemFrames = {}
  local usedPlayers, freePlayers = {}, {}

  local FullUpdate -- forward declaration (toggle handlers call it)

  local function CreateItemFrame()
    local f = CreateFrame("Button", nil, list)
    f:SetSize(ITEM_W, ITEM_H)
    f:SetBackdrop(pfUI.backdrop_hover)
    f:SetBackdropBorderColor(1, 1, 1, .04)
    f:EnableMouse(1)

    -- expand / collapse toggle
    f.toggle = CreateFrame("Button", nil, f)
    f.toggle:SetSize(14, 14)
    f.toggle:SetPoint("LEFT", 4, 0)
    f.toggle:SetScript("OnClick", function()
      local id = f.rollID
      if id then expanded[id] = not expanded[id]; FullUpdate() end
    end)

    -- icon + quality-colored border
    f.iconbg = CreateFrame("Frame", nil, f)
    f.iconbg:SetSize(ITEM_H - 8, ITEM_H - 8)
    f.iconbg:SetPoint("LEFT", f.toggle, "RIGHT", 4, 0)
    CreateBackdrop(f.iconbg, nil, true)
    f.icon = f.iconbg:CreateTexture(nil, "ARTWORK")
    f.icon:SetPoint("TOPLEFT", f.iconbg, "TOPLEFT", 2, -2)
    f.icon:SetPoint("BOTTOMRIGHT", f.iconbg, "BOTTOMRIGHT", -2, 2)
    f.icon:SetTexCoord(.08, .92, .08, .92)

    -- winner block (right side, shown for decided rolls)
    f.winicon = f:CreateTexture(nil, "OVERLAY")
    f.winicon:SetSize(14, 14)
    f.winicon:SetPoint("RIGHT", f, "RIGHT", -6, 0)

    f.winroll = f:CreateFontString("Status", "OVERLAY", "GameFontNormal")
    f.winroll:SetFont(pfUI.font_default, C.global.font_size, "OUTLINE")
    f.winroll:SetPoint("RIGHT", f.winicon, "LEFT", -2, 0)
    f.winroll:SetTextColor(1, 1, 1, 1)

    f.winname = f:CreateFontString("Status", "OVERLAY", "GameFontNormal")
    f.winname:SetFont(pfUI.font_default, C.global.font_size, "OUTLINE")
    f.winname:SetPoint("RIGHT", f.winroll, "LEFT", -4, 0)
    f.winname:SetJustifyH("RIGHT")

    -- item name (leaves room on the right for the winner block)
    f.name = f:CreateFontString("Status", "OVERLAY", "GameFontNormal")
    f.name:SetFont(pfUI.font_default, C.global.font_size, "OUTLINE")
    f.name:SetPoint("LEFT", f.iconbg, "RIGHT", 5, 0)
    f.name:SetPoint("RIGHT", f, "RIGHT", -100, 0)
    f.name:SetJustifyH("LEFT")

    f:SetScript("OnEnter", function()
      this:SetBackdropBorderColor(1, 1, 1, .08)
      if this.itemLink then
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(this.itemLink)
        GameTooltip:Show()
      end
    end)
    f:SetScript("OnLeave", function()
      this:SetBackdropBorderColor(1, 1, 1, .04)
      GameTooltip:Hide()
    end)
    f:SetScript("OnClick", function()
      local id = this.rollID
      if id then expanded[id] = not expanded[id]; FullUpdate() end
    end)

    return f
  end

  local function CreatePlayerFrame()
    local f = CreateFrame("Frame", nil, list)
    f:SetSize(PLAYER_W, PLAYER_H)

    -- name is indented to leave room for the winner checkmark on its left
    f.name = f:CreateFontString("Status", "OVERLAY", "GameFontNormal")
    f.name:SetFont(pfUI.font_default, C.global.font_size, "OUTLINE")
    f.name:SetPoint("LEFT", 20, 0)
    f.name:SetJustifyH("LEFT")

    f.rollicon = f:CreateTexture(nil, "OVERLAY")
    f.rollicon:SetSize(16, 16)
    f.rollicon:SetPoint("RIGHT", -4, 0)

    f.rolltext = f:CreateFontString("Status", "OVERLAY", "GameFontNormal")
    f.rolltext:SetFont(pfUI.font_default, C.global.font_size, "OUTLINE")
    f.rolltext:SetPoint("RIGHT", f.rollicon, "LEFT", -3, 0)
    f.rolltext:SetTextColor(1, 1, 1, 1)

    -- winner checkmark, just left of the player name (matches reference)
    f.winmark = f:CreateTexture(nil, "OVERLAY")
    f.winmark:SetSize(16, 16)
    f.winmark:SetTexture(WINMARK)
    f.winmark:SetPoint("RIGHT", f.name, "LEFT", -1, 0)

    return f
  end

  local function RecycleAllPlayers()
    for i = 1, table.getn(usedPlayers) do
      local pf = usedPlayers[i]
      pf:Hide()
      table.insert(freePlayers, pf)
    end
    usedPlayers = {}
  end

  local function GetPlayerFrame()
    local pf = table.remove(freePlayers) or CreatePlayerFrame()
    table.insert(usedPlayers, pf)
    return pf
  end

  local function SetToggleTexture(toggle, isExpanded)
    if isExpanded then
      toggle:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up")
      toggle:SetPushedTexture("Interface\\Buttons\\UI-MinusButton-Down")
    else
      toggle:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
      toggle:SetPushedTexture("Interface\\Buttons\\UI-PlusButton-Down")
    end
  end

  -- ==========================================================================
  -- Rendering
  -- ==========================================================================
  local function UpdateItemFrame(f, i)
    local rollID, itemLink, numPlayers, isDone, winnerIdx = C_LootHistory.GetItem(i)
    f.rollID = rollID
    f.itemIdx = i
    f.itemLink = itemLink
    f.numPlayers = numPlayers or 0
    f.isDone = isDone

    local isExpanded = rollID and expanded[rollID]
    SetToggleTexture(f.toggle, isExpanded)

    -- Item icon/name/quality via the ClassicAPI Item mixin. When the item
    -- isn't cached yet, show a placeholder and re-paint this row from the
    -- ContinueOnItemLoad callback (guarded on rollID: rows are pooled, so the
    -- callback must no-op if the row has since been reused for another roll).
    local item = itemLink and Item:CreateFromItemLink(itemLink)
    if item and not item:IsItemEmpty() then
      if item:IsItemDataCached() then
        RenderItemVisual(f, item)
      else
        ShowRetrieving(f)
        local pending = rollID
        item:ContinueOnItemLoad(function()
          if f.rollID == pending then RenderItemVisual(f, item) end
        end)
      end
    else
      ShowRetrieving(f)
    end

    -- winner summary only on a decided, collapsed row
    if isDone and not isExpanded then
      if winnerIdx then
        local wname, wclass, wrollType, wroll = C_LootHistory.GetPlayerInfo(i, winnerIdx)
        f.winicon:SetTexture(ROLL_TEX[wrollType] or ROLL_TEX[ROLL_NEED])
        f.winicon:Show()
        if wroll and wroll > 0 then f.winroll:SetText(wroll) else f.winroll:SetText("") end
        f.winroll:Show()
        f.winname:SetText(wname or UNKNOWN)
        f.winname:SetTextColor(ClassColor(wclass))
        f.winname:Show()
      else
        -- nobody won: everyone passed
        f.winicon:SetTexture(ROLL_TEX[ROLL_PASS])
        f.winicon:Show()
        f.winroll:SetText("")
        f.winroll:Show()
        f.winname:SetText(T["All players passed"])
        f.winname:SetTextColor(1, .4, .4)
        f.winname:Show()
      end
    else
      f.winicon:Hide()
      f.winroll:Hide()
      f.winname:Hide()
    end
  end

  local function RenderPlayerFrame(pf, name, class, rollType, roll, isWinner)
    pf.name:SetText(name or UNKNOWN)
    pf.name:SetTextColor(ClassColor(class))

    pf.rollicon:SetTexture(ROLL_TEX[rollType] or ROLL_TEX[ROLL_PASS])
    if roll and roll > 0 then pf.rolltext:SetText(roll) else pf.rolltext:SetText("") end

    if isWinner then pf.winmark:Show() else pf.winmark:Hide() end
  end

  -- A player row is worth showing while the roll is undecided (see everyone),
  -- or afterwards only if they actually rolled or it's you (hide the passers'
  -- noise on a decided roll) — mirrors Blizzard's ShouldDisplayPlayer.
  local function ShouldDisplayPlayer(isDone, roll, isMe)
    return isMe or (roll and roll > 0) or not isDone
  end

  function FullUpdate()
    if not pfUI.loothistory:IsShown() then return end
    RecycleAllPlayers()

    local num = C_LootHistory.GetNumItems()
    local y = -2

    for i = 1, num do
      local f = itemFrames[i] or CreateItemFrame()
      itemFrames[i] = f
      UpdateItemFrame(f, i)
      f:ClearAllPoints()
      f:SetPoint("TOPLEFT", list, "TOPLEFT", 4, y)
      f:Show()
      y = y - ITEM_H - 2

      if f.rollID and expanded[f.rollID] then
        for p = 1, f.numPlayers do
          local name, class, rollType, roll, isWinner, isMe = C_LootHistory.GetPlayerInfo(i, p)
          if ShouldDisplayPlayer(f.isDone, roll, isMe) then
            local pf = GetPlayerFrame()
            RenderPlayerFrame(pf, name, class, rollType, roll, isWinner)
            pf:ClearAllPoints()
            pf:SetPoint("TOPLEFT", list, "TOPLEFT", 22, y)
            pf:Show()
            y = y - PLAYER_H
          end
        end
        y = y - 2
      end
    end

    for i = num + 1, table.getn(itemFrames) do
      itemFrames[i]:Hide()
    end

    -- Resize the scroll child and re-attach it: SetHeight alone on a
    -- SetAllPoints'd child doesn't make the ScrollFrame recompute its scroll
    -- range, so a dynamically-grown list wouldn't scroll until a /reload.
    list:SetHeight(math.max(1, -y + 2))
    pfUI.loothistory.scroll:SetScrollChild(list)
    pfUI.loothistory.scroll:UpdateScrollState()
  end

  pfUI.loothistory:SetScript("OnShow", function() FullUpdate() end)

  -- ==========================================================================
  -- Events
  -- ==========================================================================
  local events = CreateFrame("Frame")
  events:RegisterEvent("LOOT_HISTORY_FULL_UPDATE")
  events:RegisterEvent("LOOT_HISTORY_ROLL_CHANGED")
  events:RegisterEvent("LOOT_HISTORY_ROLL_COMPLETE")
  events:SetScript("OnEvent", function()
    -- auto-show on a new roll opening / completing, if enabled
    if C.loothistory.autoshow == "1"
        and (event == "LOOT_HISTORY_FULL_UPDATE" or event == "LOOT_HISTORY_ROLL_COMPLETE")
        and not pfUI.loothistory:IsShown() then
      pfUI.loothistory:Show() -- OnShow runs FullUpdate
      return
    end
    FullUpdate() -- no-op while hidden
  end)

  -- ==========================================================================
  -- Slash command
  -- ==========================================================================
  local function Toggle()
    pfUI.loothistory:SetShown(not pfUI.loothistory:IsShown())
  end

  _G.SLASH_PFLOOTHISTORY1, _G.SLASH_PFLOOTHISTORY2 = "/loothistory", "/pfloothistory"
  _G.SlashCmdList.PFLOOTHISTORY = Toggle
end)
