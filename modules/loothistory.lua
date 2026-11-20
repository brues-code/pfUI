pfUI:RegisterModule("loothistory", function ()
  local rawborder, border = GetBorderSize()

  -- Layout (rows are 2px apart)
  local ITEM_H, PLAYER_H = 24, 16
  local PLAYER_INDENT = 18

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

  -- expansion state keyed on the stable rollID (indexes shift as items come and go)
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

  -- ==========================================================================
  -- List: a row per item and, under an expanded item, a row per player
  -- ==========================================================================
  local list = CreateFrame("Frame", "pfLootHistoryList", pfUI.loothistory, "pfUIScrollBoxListTemplate")
  list:SetSize(370, 450)
  list:SetPoint("BOTTOM", 0, 5)
  CreateBackdrop(list, nil, true)
  pfUI.loothistory.list = list

  local FullUpdate -- forward declaration (toggle handlers call it)

  local function ToggleExpanded(f)
    local id = f.rollID
    if id then expanded[id] = not expanded[id]; FullUpdate() end
  end

  -- one-time setup of a pooled item row
  local function SetupItemRow(f)
    f:SetBackdrop(pfUI.backdrop_hover)
    f:SetBackdropBorderColor(1, 1, 1, .04)
    f:EnableMouse(1)

    -- expand / collapse toggle
    f.toggle = CreateFrame("Button", nil, f)
    f.toggle:SetSize(14, 14)
    f.toggle:SetPoint("LEFT", 4, 0)
    f.toggle:SetScript("OnClick", function() ToggleExpanded(f) end)

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

    f.winroll = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.winroll:SetFont(pfUI.font_default, C.global.font_size, "OUTLINE")
    f.winroll:SetPoint("RIGHT", f.winicon, "LEFT", -2, 0)
    f.winroll:SetTextColor(1, 1, 1, 1)

    f.winname = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.winname:SetFont(pfUI.font_default, C.global.font_size, "OUTLINE")
    f.winname:SetPoint("RIGHT", f.winroll, "LEFT", -4, 0)
    f.winname:SetJustifyH("RIGHT")

    -- item name (leaves room on the right for the winner block)
    f.name = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
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
    f:SetScript("OnClick", function() ToggleExpanded(f) end)
  end

  -- one-time setup of a pooled player row
  local function SetupPlayerRow(f)
    -- name is indented to leave room for the winner checkmark on its left
    f.name = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.name:SetFont(pfUI.font_default, C.global.font_size, "OUTLINE")
    f.name:SetPoint("LEFT", 20, 0)
    f.name:SetJustifyH("LEFT")

    f.rollicon = f:CreateTexture(nil, "OVERLAY")
    f.rollicon:SetSize(16, 16)
    f.rollicon:SetPoint("RIGHT", -4, 0)

    f.rolltext = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.rolltext:SetFont(pfUI.font_default, C.global.font_size, "OUTLINE")
    f.rolltext:SetPoint("RIGHT", f.rollicon, "LEFT", -3, 0)
    f.rolltext:SetTextColor(1, 1, 1, 1)

    -- winner checkmark, just left of the player name (matches reference)
    f.winmark = f:CreateTexture(nil, "OVERLAY")
    f.winmark:SetSize(16, 16)
    f.winmark:SetTexture(WINMARK)
    f.winmark:SetPoint("RIGHT", f.name, "LEFT", -1, 0)
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
  local function InitItemRow(f, row)
    if not f.toggle then SetupItemRow(f) end

    local i = row.item
    local rollID, itemLink, _, isDone, winnerIdx = C_LootHistory.GetItem(i)
    f.rollID = rollID
    f.itemLink = itemLink

    local isExpanded = rollID and expanded[rollID]
    SetToggleTexture(f.toggle, isExpanded)

    -- Item icon/name/quality via the ClassicAPI Item mixin. The row shows a
    -- placeholder until ContinueOnItemLoad paints it, which happens at once
    -- when the item is cached (guarded on rollID: rows are pooled, so the
    -- callback must no-op if the row has since been reused for another roll).
    ShowRetrieving(f)
    if itemLink then
      local item = Item:CreateFromItemLink(itemLink)
      local pending = rollID
      item:ContinueOnItemLoad(function()
        if f.rollID == pending then RenderItemVisual(f, item) end
      end)
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
        f.winname:SetTextColor(PFUI_CLASS_COLORS[wclass]:GetRGB())
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

  local function InitPlayerRow(pf, row)
    if not pf.name then SetupPlayerRow(pf) end

    local name, class, rollType, roll, isWinner = C_LootHistory.GetPlayerInfo(row.item, row.player)
    pf.name:SetText(name or UNKNOWN)
    pf.name:SetTextColor(PFUI_CLASS_COLORS[class]:GetRGB())

    -- no rollType = has not voted on an open roll (Blizzard shows "... ")
    pf.rollicon:SetTexture(rollType and ROLL_TEX[rollType] or nil)
    if not rollType then
      pf.rolltext:SetText("... ")
    elseif roll and roll > 0 then
      pf.rolltext:SetText(roll)
    else
      pf.rolltext:SetText("")
    end

    pf.winmark:SetShown(isWinner)
  end

  local view = CreateScrollBoxListLinearView(2, 2, 4, 4, 2)
  view:SetElementFactory(function(factory, row)
    if row.player then
      factory("Frame", InitPlayerRow)
    else
      factory("Button", InitItemRow)
    end
  end)
  view:SetElementExtentCalculator(function(_, row)
    return row.player and PLAYER_H or ITEM_H
  end)
  view:SetElementIndentCalculator(function(row)
    return row.player and PLAYER_INDENT or 0
  end)
  ScrollUtil.InitScrollBoxListWithScrollBar(list.ScrollBox, list.ScrollBar, view)

  -- A player row is worth showing while the roll is undecided (see everyone),
  -- or afterwards only if they actually rolled or it's you (hide the passers'
  -- noise on a decided roll) — mirrors Blizzard's ShouldDisplayPlayer.
  local function ShouldDisplayPlayer(isDone, roll, isMe)
    return isMe or (roll and roll > 0) or not isDone
  end

  function FullUpdate()
    if not pfUI.loothistory:IsShown() then return end

    local rows = {}
    for i = 1, C_LootHistory.GetNumItems() do
      local rollID, _, numPlayers, isDone = C_LootHistory.GetItem(i)
      table.insert(rows, { item = i })

      if rollID and expanded[rollID] then
        for p = 1, numPlayers or 0 do
          local _, _, _, roll, _, isMe = C_LootHistory.GetPlayerInfo(i, p)
          if ShouldDisplayPlayer(isDone, roll, isMe) then
            table.insert(rows, { item = i, player = p })
          end
        end
      end
    end

    list.ScrollBox:SetDataProvider(CreateDataProvider(rows), ScrollBoxConstants.RetainScrollPosition)
  end

  pfUI.loothistory:SetScript("OnShow", function() FullUpdate() end)

  -- ==========================================================================
  -- Events
  -- ==========================================================================
  -- auto-show when a bind-on-pickup roll starts, if enabled: open with that
  -- roll expanded, as Blizzard's frame does on LOOT_HISTORY_AUTO_SHOW
  local function AutoShow(_, rollID)
    if C.loothistory.autoshow ~= "1" then return end
    expanded[rollID] = true
    if pfUI.loothistory:IsShown() then
      FullUpdate()
    else
      pfUI.loothistory:Show() -- OnShow runs FullUpdate
    end
  end

  pfUI.events:RegisterFrameEventAndCallback("LOOT_HISTORY_FULL_UPDATE", FullUpdate)
  pfUI.events:RegisterFrameEventAndCallback("LOOT_HISTORY_ROLL_COMPLETE", FullUpdate)
  pfUI.events:RegisterFrameEventAndCallback("LOOT_HISTORY_ROLL_CHANGED", FullUpdate)
  pfUI.events:RegisterFrameEventAndCallback("LOOT_HISTORY_AUTO_SHOW", AutoShow)

  -- ==========================================================================
  -- Slash command
  -- ==========================================================================
  local function Toggle()
    pfUI.loothistory:SetShown(not pfUI.loothistory:IsShown())
  end

  pfUI.api.RegisterSlashCommand("PFLOOTHISTORY", { "/loothistory", "/pfloothistory" }, Toggle, true)
end)
