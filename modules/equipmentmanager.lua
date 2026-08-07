-- Equipment Manager module
-- Backport of the 4.3.4 GearManagerDialog UI on top of ClassicAPI's C_EquipmentSet.* API.

pfUI:RegisterModule("equipmentmanager", function()
  if not C_EquipmentSet or not C_EquipmentSet.CanUseEquipmentSets() then return end

  pfUI.equipmentmanager = {}

  local SET_ROW_HEIGHT = 36

  local rawborder, border = GetBorderSize()
  local selectedSetID = nil
  local pendingAction = nil  -- "new" | "save" | "rename" — what the popups apply to
  local slotOverlays = {}    -- [invSlotID] = ignored-overlay texture on the character slot
  local popoutButtons = {}   -- popout arrow buttons; toggled with the EM frame
  local UpdatePopouts        -- forward decl; assigned once popouts + flyout exist

  -- Pending ignored-slot toggles per set: a slotID here means the
  -- effective state is flipped from what's persisted. Committed on
  -- Save, cleared on delete.
  local pendingIgnoredToggles = {}

  local function GetEffectiveIgnored(setID)
    local result = {}
    if not setID then return result end
    local persistent = C_EquipmentSet.GetIgnoredSlots(setID) or {}
    for _, s in ipairs(persistent) do result[s] = true end
    local pending = pendingIgnoredToggles[setID]
    if pending then
      for slotID in pairs(pending) do
        if result[slotID] then result[slotID] = nil else result[slotID] = true end
      end
    end
    return result
  end

  local function ToggleIgnoredForSet(setID, slotID)
    if not setID then return end
    pendingIgnoredToggles[setID] = pendingIgnoredToggles[setID] or {}
    if pendingIgnoredToggles[setID][slotID] then
      pendingIgnoredToggles[setID][slotID] = nil
    else
      pendingIgnoredToggles[setID][slotID] = true
    end
  end

  local function SetPopoutReversed(popout, reversed)
    if not popout then return end
    local nc = reversed and popout.coordReversed or popout.coordNormal
    local hc = reversed and popout.coordReversedHi or popout.coordNormalHi
    popout:GetNormalTexture():SetTexCoord(unpack(nc))
    popout:GetHighlightTexture():SetTexCoord(unpack(hc))
  end

  local function EquipSet(setID)
    if not setID then return end
    if C_EquipmentSet.EquipmentSetContainsLockedItems(setID) then
      UIErrorsFrame:AddMessage(ERR_CLIENT_LOCKED_OUT, 1, .1, .1, 1)
      return
    end
    ClearCursor()
    C_EquipmentSet.UseEquipmentSet(setID)
  end

  -- ============================================================
  -- Main content frame: opens as a sidecar to the right of CharacterFrame
  -- (matches ReputationDetailFrame's positioning pattern).
  -- ============================================================

  local frame = CreateFrame("Frame", "pfEquipmentManagerFrame", CharacterFrame)
  frame:SetSize(220, 350)
  frame:SetFrameStrata("HIGH")
  frame:SetScript("OnShow", function()
    this:ClearAllPoints()
    if CharacterFrame.backdrop then
      frame:SetPoint("TOPLEFT", CharacterFrame.backdrop, "TOPRIGHT", 2*border, -2)
    else
      frame:SetPoint("TOPLEFT", CharacterFrame, "TOPRIGHT", 0, 0)
    end
    UpdatePopouts()
  end)
  CreateBackdrop(frame, nil, nil, .9)
  CreateBackdropShadow(frame)
  frame:Hide()

  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  frame.title:SetPoint("TOP", frame, "TOP", 0, -10)
  frame.title:SetText(EQUIPMENT_MANAGER)

  local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
  closeBtn:SetScript("OnClick", function() frame:Hide() end)
  if SkinCloseButton then SkinCloseButton(closeBtn, frame.backdrop or frame, -6, -6) end

  -- ============================================================
  -- Toggle button on character pane (above the Hands slot)
  -- ============================================================

  local toggleBtn = CreateFrame("Button", "pfEqMgrToggleButton", PaperDollFrame)
  toggleBtn:SetSize(28, 28)
  toggleBtn:SetPoint("BOTTOM", CharacterHandsSlot, "TOP", 0, 4)
  toggleBtn:SetNormalTexture(pfUI.path.."\\img\\UI-GearManager-Button")
  toggleBtn:SetPushedTexture(pfUI.path.."\\img\\UI-GearManager-Button-Pushed")
  toggleBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  toggleBtn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:SetText(PAPERDOLL_EQUIPMENTMANAGER)
    GameTooltip:Show()
  end)
  toggleBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  toggleBtn:SetScript("OnClick", function()
    if frame:IsShown() then
      frame:Hide()
    else
      frame:Show()
      pfUI.equipmentmanager.Refresh()
    end
  end)

  local OpenNamePopup  -- forward declared; assigned below

  -- ============================================================
  -- Equip + Save buttons (top of list area)
  -- ============================================================

  local btnEquip = CreateFrame("Button", "pfEqMgrEquip", frame, "UIPanelButtonTemplate")
  btnEquip:SetSize(86, 22); btnEquip:SetText(EQUIPSET_EQUIP)
  btnEquip:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -30)
  SkinButton(btnEquip)
  btnEquip:SetScript("OnClick", function() EquipSet(selectedSetID) end)

  local btnSave = CreateFrame("Button", "pfEqMgrSave", frame, "UIPanelButtonTemplate")
  btnSave:SetSize(86, 22); btnSave:SetText(SAVE)
  btnSave:SetPoint("LEFT", btnEquip, "RIGHT", 6, 0)
  SkinButton(btnSave)
  btnSave:SetScript("OnClick", function()
    if not selectedSetID then return end
    local name, icon = C_EquipmentSet.GetEquipmentSetInfo(selectedSetID)
    if not name then return end
    local targetID = selectedSetID
    StaticPopupDialogs["PFUI_EQMGR_SAVE_CONFIRM"] = {
      text = string.format(CONFIRM_SAVE_EQUIPMENT_SET, name),
      button1 = YES, button2 = NO,
      OnAccept = function()
        C_EquipmentSet.ClearIgnoredSlotsForSave()
        local effective = GetEffectiveIgnored(targetID)
        for slotID in pairs(effective) do
          C_EquipmentSet.IgnoreSlotForSave(slotID)
        end
        C_EquipmentSet.SaveEquipmentSet(targetID, icon)
        C_EquipmentSet.ClearIgnoredSlotsForSave()
        pendingIgnoredToggles[targetID] = nil
        pfUI.equipmentmanager.Refresh()
      end,
      timeout = 0, whileDead = 1, hideOnEscape = 1, exclusive = 1,
    }
    StaticPopup_Show("PFUI_EQMGR_SAVE_CONFIRM")
  end)

  -- ============================================================
  -- Per-row context menu (single instance, repositioned per click).
  -- Triggered by the gear icon on each set row.
  -- ============================================================

  local rowMenu = CreateFrame("Frame", "pfEqMgrRowMenu", UIParent)
  rowMenu:SetFrameStrata("DIALOG")
  rowMenu:SetSize(140, 50);
  rowMenu:Hide()
  CreateBackdrop(rowMenu, nil, nil, .95)
  CreateBackdropShadow(rowMenu)
  rowMenu:EnableMouse(true)

  -- Close on click outside via GLOBAL_MOUSE_DOWN (fires on any click
  -- without consuming it). The anchorBtn check defers the gear-click
  -- toggle to the gear's own OnClick so opening doesn't trigger close.
  rowMenu:RegisterEvent("GLOBAL_MOUSE_DOWN")
  rowMenu:SetScript("OnEvent", function()
    if not this:IsShown() then return end
    if MouseIsOver(this) then return end
    if this.anchorBtn and MouseIsOver(this.anchorBtn) then return end
    this:Hide()
  end)
  tinsert(UISpecialFrames, "pfEqMgrRowMenu")  -- Escape closes it

  rowMenu.changeBtn = CreateFrame("Button", nil, rowMenu, "UIPanelButtonTemplate")
  rowMenu.changeBtn:SetSize(130, 20);
  rowMenu.changeBtn:SetPoint("TOPLEFT", rowMenu, "TOPLEFT", 5, -3)
  rowMenu.changeBtn:SetText(EQUIPMENT_SET_EDIT)
  SkinButton(rowMenu.changeBtn)
  rowMenu.changeBtn:SetScript("OnClick", function()
    rowMenu:Hide()
    if not rowMenu.targetSetID then return end
    local name, icon = C_EquipmentSet.GetEquipmentSetInfo(rowMenu.targetSetID)
    selectedSetID = rowMenu.targetSetID
    OpenNamePopup("save", name, icon)
  end)

  rowMenu.deleteBtn = CreateFrame("Button", nil, rowMenu, "UIPanelButtonTemplate")
  rowMenu.deleteBtn:SetSize(130, 20);
  rowMenu.deleteBtn:SetPoint("TOP", rowMenu.changeBtn, "BOTTOM", 0, -2)
  rowMenu.deleteBtn:SetText(DELETE)
  SkinButton(rowMenu.deleteBtn)
  rowMenu.deleteBtn:SetScript("OnClick", function()
    rowMenu:Hide()
    if not rowMenu.targetSetID then return end
    local targetID = rowMenu.targetSetID
    local name = C_EquipmentSet.GetEquipmentSetInfo(targetID)
    StaticPopupDialogs["PFUI_EQMGR_DELETE"] = {
      text = string.format(CONFIRM_DELETE_EQUIPMENT_SET, name or "?"),
      button1 = YES, button2 = NO,
      OnAccept = function()
        pendingIgnoredToggles[targetID] = nil
        C_EquipmentSet.DeleteEquipmentSet(targetID)
        if selectedSetID == targetID then selectedSetID = nil end
        pfUI.equipmentmanager.Refresh()
      end,
      timeout = 0, whileDead = 1, hideOnEscape = 1, exclusive = 1,
    }
    StaticPopup_Show("PFUI_EQMGR_DELETE")
  end)

  -- ============================================================
  -- Set list (left column)
  -- ============================================================

  local LIST_VISIBLE_ROWS = 7
  local LIST_ROW_STRIDE = SET_ROW_HEIGHT + 2
  local listFrame = CreateFrame("Frame", nil, frame)
  listFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -58)
  -- Height fits N rows + (N-1) inter-row gaps + 3px top/bottom padding.
  listFrame:SetSize(180, LIST_VISIBLE_ROWS * LIST_ROW_STRIDE + 4)
  CreateBackdrop(listFrame, nil, nil, .75)

  -- Mouse-wheel scroll: list of [sets..., newSetRow] is virtualized
  -- through LIST_VISIBLE_ROWS slots. Refresh() consumes listFrame.offset
  -- and the wheel handler clamps + bumps it.
  listFrame.offset = 0
  listFrame:EnableMouseWheel(true)
  listFrame:SetScript("OnMouseWheel", function()
    listFrame.offset = listFrame.offset - (arg1 or 0)
    pfUI.equipmentmanager.Refresh()
  end)

  local setRows = {}
  local function CreateSetRow()
    local row = CreateFrame("Button", nil, listFrame)
    row:SetSize(170, SET_ROW_HEIGHT)
    -- Position is set per-Refresh based on the row's visible slot;
    -- start anchored to avoid uninitialized geometry before first Refresh.
    row:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 5, -3)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(30, 30)
    row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.icon:SetTexCoord(.08, .92, .08, .92)

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", -22, 0)
    row.text:SetJustifyH("LEFT")

    row.highlight = row:CreateTexture(nil, "BACKGROUND")
    row.highlight:SetAllPoints(row)
    row.highlight:SetTexture(.3, .3, .3, .4)
    row.highlight:Hide()

    row.gear = CreateFrame("Button", nil, row)
    row.gear:SetSize(16, 16);
    row.gear:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.gear.tex = row.gear:CreateTexture(nil, "ARTWORK")
    row.gear.tex:SetAllPoints(row.gear)
    row.gear.tex:SetTexture(pfUI.path.."\\img\\Gear_64Grey")
    row.gear:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    row.gear:Hide()
    row.gear:SetScript("OnClick", function()
      if not row.setID then return end
      -- Toggle: clicking the gear that owns the open menu closes it.
      -- GLOBAL_MOUSE_DOWN's anchorBtn check excludes the gear, so the
      -- close has to happen here.
      if rowMenu:IsShown() and rowMenu.targetSetID == row.setID then
        rowMenu:Hide()
        return
      end
      rowMenu.targetSetID = row.setID
      rowMenu.anchorBtn = row.gear
      rowMenu:ClearAllPoints()
      rowMenu:SetPoint("TOPRIGHT", row.gear, "BOTTOMRIGHT", 0, 0)
      rowMenu:Show()
    end)

    row:SetScript("OnClick", function()
      selectedSetID = row.setID
      -- Detect double-click manually; vanilla Button has no native event.
      local now = GetTime()
      if row.lastClick and (now - row.lastClick) < 0.4 then
        row.lastClick = nil
        EquipSet(row.setID)
      else
        row.lastClick = now
      end
      pfUI.equipmentmanager.Refresh()
    end)

    -- Show the gear and tooltip while the cursor is over the row or its
    -- gear child. The gear sits inside the row's rectangle, so a single
    -- MouseIsOver(row) check covers both. OnLeave on the row and the gear
    -- catches every exit path, so no OnUpdate poll is needed.
    local function HideRowHover()
      if MouseIsOver(row) then return end
      GameTooltip:Hide()
      row.gear:Hide()
    end
    row:SetScript("OnEnter", function()
      if not row.setID then return end
      local name = C_EquipmentSet.GetEquipmentSetInfo(row.setID)
      if name then
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:SetEquipmentSet(name)
        GameTooltip:Show()
      end
      row.gear:Show()
    end)
    row:SetScript("OnLeave", HideRowHover)
    row.gear:SetScript("OnLeave", HideRowHover)

    return row
  end

  -- Rows are allocated lazily in Refresh — ClassicAPI no longer caps
  -- the number of equipment sets, so we grow the pool to numSets on
  -- demand. The set list is wheel-scrolled, so only LIST_VISIBLE_ROWS
  -- are ever positioned in-frame at a time, but each row is bound to a
  -- specific set index (row[i] always shows ids[i]).

  local newSetRow = CreateFrame("Button", nil, listFrame)
  newSetRow:SetSize(170, SET_ROW_HEIGHT);

  newSetRow.icon = newSetRow:CreateTexture(nil, "ARTWORK")
  newSetRow.icon:SetSize(24, 24);
  newSetRow.icon:SetPoint("LEFT", newSetRow, "LEFT", 5, 0)
  newSetRow.icon:SetTexture(pfUI.path.."\\img\\Character-Plus")

  newSetRow.text = newSetRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  newSetRow.text:SetPoint("LEFT", newSetRow.icon, "RIGHT", 8, 0)
  newSetRow.text:SetPoint("RIGHT", newSetRow, "RIGHT", -4, 0)
  newSetRow.text:SetJustifyH("LEFT")
  newSetRow.text:SetText(PAPERDOLL_NEWEQUIPMENTSET)
  newSetRow.text:SetTextColor(0.2, 1, 0.2)

  newSetRow.highlight = newSetRow:CreateTexture(nil, "BACKGROUND")
  newSetRow.highlight:SetAllPoints(newSetRow)
  newSetRow.highlight:SetTexture(.3, .3, .3, .4)
  newSetRow.highlight:Hide()
  newSetRow:SetScript("OnEnter", function() newSetRow.highlight:Show() end)
  newSetRow:SetScript("OnLeave", function() newSetRow.highlight:Hide() end)
  newSetRow:SetScript("OnClick", function() OpenNamePopup("new") end)

  local function MakeButton(name, label, parent, anchor, ax, ay, width)
    local b = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 70, 22)
    b:SetText(label)
    b:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", ax, ay)
    SkinButton(b)
    return b
  end

  -- ============================================================
  -- Name/icon entry popup
  -- ============================================================

  local namePopup = CreateFrame("Frame", "pfEqMgrNamePopup", UIParent)
  namePopup:SetFrameStrata("DIALOG")
  namePopup:SetSize(472, 484)
  namePopup:SetPoint("CENTER", UIParent, "CENTER")
  namePopup:Hide()
  CreateBackdrop(namePopup, nil, nil, .9)
  CreateBackdropShadow(namePopup)
  namePopup:EnableMouse(true)
  namePopup:SetMovable(true)
  namePopup:RegisterForDrag("LeftButton")
  namePopup:SetScript("OnDragStart", function() this:StartMoving() end)
  namePopup:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)

  -- Equipment seed leads the grid with gear-relevant item icons. The widget
  -- owns the name field, preview, grid, filter, and search; this module keeps
  -- the OK/Cancel buttons and the create/save/rename flow below.
  local iconPicker = CreateIconPicker("pfEqMgrIcon", namePopup,
                                      IconDataProviderExtraType.Equipment, GEARSETS_POPUP_TEXT)

  local btnPopupOK = MakeButton("pfEqMgrPopupOK", OKAY, namePopup, namePopup, 14, -340, 80)

  local btnPopupCancel = MakeButton("pfEqMgrPopupCancel", CANCEL, namePopup, namePopup, 0, 0, 80)
  btnPopupCancel:ClearAllPoints()
  btnPopupCancel:SetPoint("BOTTOMRIGHT", namePopup, "BOTTOMRIGHT", -14, 12)
  btnPopupCancel:SetScript("OnClick", function() namePopup:Hide() end)

  -- Okay | Cancel, both anchored to the bottom-right corner.
  btnPopupOK:ClearAllPoints()
  btnPopupOK:SetPoint("BOTTOMRIGHT", btnPopupCancel, "BOTTOMLEFT", -6, 0)

  btnPopupOK:SetScript("OnClick", function()
    local name = namePopup.editbox:GetText()
    if not name or name == "" then return end
    -- Strip the prefix to match ClassicAPI's persisted short-form basenames.
    local iconForSave = string.gsub(iconPicker.GetIcon(), "INTERFACE\\ICONS\\", "")
    if pendingAction == "new" then
      C_EquipmentSet.CreateEquipmentSet(name, iconForSave)
      C_EquipmentSet.ClearIgnoredSlotsForSave()
      selectedSetID = C_EquipmentSet.GetEquipmentSetID(name)
    elseif pendingAction == "save" and selectedSetID then
      -- Commit pending ignored toggles: load the effective list into
      -- ClassicAPI's session state, then SaveEquipmentSet captures it.
      C_EquipmentSet.ClearIgnoredSlotsForSave()
      local effective = GetEffectiveIgnored(selectedSetID)
      for slotID in pairs(effective) do
        C_EquipmentSet.IgnoreSlotForSave(slotID)
      end
      C_EquipmentSet.SaveEquipmentSet(selectedSetID, iconForSave)
      C_EquipmentSet.ClearIgnoredSlotsForSave()
      pendingIgnoredToggles[selectedSetID] = nil
    elseif pendingAction == "rename" and selectedSetID then
      C_EquipmentSet.ModifyEquipmentSet(selectedSetID, name)
    end
    namePopup:Hide()
    pfUI.equipmentmanager.Refresh()
  end)

  -- Assignment (not `local function`) so this fills in the forward
  -- declaration at the top of the module — closures created earlier
  -- (row gear menu, "+ New Set" row, etc.) capture the same upvalue.
  function OpenNamePopup(action, prefillName, prefillIcon)
    pendingAction = action
    namePopup.editbox:SetText(prefillName or "")
    if prefillIcon then
      -- Stored icons come back either as a full path or a bare basename
      -- (see the row rendering in Refresh). Only prepend the prefix when
      -- there's no path separator, so a full path isn't double-prefixed.
      iconPicker.SetIcon(string.find(prefillIcon, "\\") and prefillIcon
                         or ("INTERFACE\\ICONS\\" .. prefillIcon))
    else
      iconPicker.SetIcon(nil)
    end
    namePopup.search:SetText("")
    -- Rename only changes the name, so hide the whole icon-picking area.
    iconPicker.SetIconAreaShown(action ~= "rename")
    namePopup:Show()
    if action ~= "rename" then iconPicker.Refresh() end
    namePopup.editbox:SetFocus()
  end

  -- ============================================================
  -- Equipment flyout (per-slot popup)
  -- ============================================================

  local flyout = CreateFrame("Frame", "pfEqMgrFlyout", UIParent)
  -- The name/icon popup is sidecar-only, so it closes with the sidecar.
  -- Popout arrows and the flyout are reconciled by UpdatePopouts: by
  -- default they follow the sidecar, but with the "Always Show Equipment
  -- Slot Flyouts" option they stay while the paperdoll is open.
  frame:SetScript("OnHide", function()
    namePopup:Hide()
    UpdatePopouts()
  end)
  flyout:SetFrameStrata("DIALOG")
  flyout:Hide()
  CreateBackdrop(flyout, nil, nil, .9)
  flyout.buttons = {}

  local FLYOUT_BTN_SIZE = 36
  local FLYOUT_COLS = 5
  -- Sentinels for the flyout's virtual entries (negative values never
  -- collide with real packed locations from GetInventoryItemsForSlot).
  local PLACEINBAGS_LOCATION = -1
  local IGNORESLOT_LOCATION = -2    -- "ignore this slot" — shown when not ignored
  local UNIGNORESLOT_LOCATION = -3  -- "un-ignore this slot" — shown when ignored

  -- Find first empty bag slot and drop the cursor item into it.
  local function UnequipToBags(invSlot)
    if not GetInventoryItemID("player", invSlot) then return end
    ClearCursor()
    PickupInventoryItem(invSlot)
    if not CursorHasItem() then return end
    for bag = 0, 4 do
      local nslots = GetContainerNumSlots(bag) or 0
      for slot = 1, nslots do
        if not C_Container.GetContainerItemID(bag, slot) then
          PickupContainerItem(bag, slot)
          return
        end
      end
    end
    ClearCursor()
    UIErrorsFrame:AddMessage(ERR_EQUIPMENT_MANAGER_BAGS_FULL, 1, .1, .1, 1)
  end

  local function MakeFlyoutButton(i)
    local b = CreateFrame("Button", nil, flyout)
    b:SetWidth(FLYOUT_BTN_SIZE)
    b:SetHeight(FLYOUT_BTN_SIZE)
    CreateBackdrop(b)
    b.texture = b:CreateTexture(nil, "ARTWORK")
    b.texture:SetAllPoints(b)
    b.texture:SetTexCoord(.08, .92, .08, .92)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
    b:SetScript("OnEnter", function()
      GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
      if this.specialAction == "placeInBags" then
        GameTooltip:SetText(EQUIPMENT_MANAGER_PLACE_IN_BAGS, 1, 1, 1)
      elseif this.specialAction == "ignore" then
        GameTooltip:SetText(EQUIPMENT_MANAGER_IGNORE_SLOT, 1, 1, 1)
      elseif this.specialAction == "unignore" then
        GameTooltip:SetText(EQUIPMENT_MANAGER_UNIGNORE_SLOT, 1, 1, 1)
      elseif this.bag then
        GameTooltip:SetBagItem(this.bag, this.slot)
      elseif this.invSlot then
        GameTooltip:SetInventoryItem("player", this.invSlot)
      end
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    b:SetScript("OnClick", function()
      if this.specialAction == "placeInBags" then
        UnequipToBags(flyout.targetInvSlot)
        flyout:Hide()
        return
      elseif this.specialAction == "ignore" or this.specialAction == "unignore" then
        ToggleIgnoredForSet(selectedSetID, flyout.targetInvSlot)
        flyout:Hide()
        pfUI.equipmentmanager.Refresh()
        return
      end
      ClearCursor()
      if this.bag then
        PickupContainerItem(this.bag, this.slot)
      elseif this.invSlot then
        PickupInventoryItem(this.invSlot)
      end
      if CursorHasItem() then
        PickupInventoryItem(flyout.targetInvSlot)
      end
      flyout:Hide()
    end)
    return b
  end

  function pfUI.equipmentmanager.ShowFlyout(slotBtn)
    -- Accept either the EM grid btn (has .slotID) or a vanilla
    -- CharacterXxxxSlot button (use GetID()).
    local invSlot = slotBtn.slotID or slotBtn:GetID()

    -- ClassicAPI's GetInventoryItemsForSlot does the eligibility filter
    -- (invType → slot compatibility, 2H/finger/trinket rules) for us;
    -- the result is `{[packedLocation] = itemLink}`.
    local items = {}
    GetInventoryItemsForSlot(invSlot, items)
    -- Skip the item currently equipped in this slot (it would be a no-op swap).
    items[invSlot + ITEM_INVENTORY_LOCATION_PLAYER] = nil

    -- Special buttons go FIRST (ignore/un-ignore, then place-in-bags),
    -- with eligible items appended after. Layout matches modern WoW.
    local ordered = {}
    if selectedSetID then
      local effective = GetEffectiveIgnored(selectedSetID)
      table.insert(ordered, effective[invSlot] and UNIGNORESLOT_LOCATION or IGNORESLOT_LOCATION)
    end
    if GetInventoryItemID("player", invSlot) then
      table.insert(ordered, PLACEINBAGS_LOCATION)
    end
    -- Eligible items, sorted by packed location for stable display.
    local itemLocations = {}
    for location in pairs(items) do
      table.insert(itemLocations, location)
    end
    table.sort(itemLocations)
    for _, location in ipairs(itemLocations) do
      table.insert(ordered, location)
    end

    flyout.targetInvSlot = invSlot
    local num = table.getn(ordered)
    while table.getn(flyout.buttons) < num do
      flyout.buttons[table.getn(flyout.buttons) + 1] = MakeFlyoutButton(table.getn(flyout.buttons) + 1)
    end
    for i, b in ipairs(flyout.buttons) do
      if i <= num then
        local location = ordered[i]
        b.specialAction = nil; b.bag = nil; b.slot = nil; b.invSlot = nil
        if location == PLACEINBAGS_LOCATION then
          b.specialAction = "placeInBags"
          b.texture:SetTexture(pfUI.path.."\\img\\UI-GearManager-ItemIntoBag")
          b.count:SetText("")
        elseif location == IGNORESLOT_LOCATION then
          b.specialAction = "ignore"
          b.texture:SetTexture(pfUI.path.."\\img\\UI-GearManager-LeaveItem-Opaque")
          b.count:SetText("")
        elseif location == UNIGNORESLOT_LOCATION then
          b.specialAction = "unignore"
          b.texture:SetTexture(pfUI.path.."\\img\\UI-GearManager-Undo")
          b.count:SetText("")
        else
          local loc = EquipmentManager_GetLocationData(location)
          if loc.isBags then
            b.bag = loc.bag; b.slot = loc.slot
            local tex, count = GetContainerItemInfo(loc.bag, loc.slot)
            b.texture:SetTexture(tex)
            if count and count > 1 then b.count:SetText(count) else b.count:SetText("") end
          else  -- isPlayer (equipped in some other slot)
            b.invSlot = loc.slot
            b.texture:SetTexture(GetInventoryItemTexture("player", loc.slot))
            b.count:SetText("")
          end
        end
        local col = math.mod(i - 1, FLYOUT_COLS)
        local row = math.floor((i - 1) / FLYOUT_COLS)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", flyout, "TOPLEFT", 4 + col * (FLYOUT_BTN_SIZE + 2), -4 - row * (FLYOUT_BTN_SIZE + 2))
        b:Show()
      else
        b:Hide()
      end
    end

    if num == 0 then
      flyout:Hide()
      return
    end

    local cols = math.min(num, FLYOUT_COLS)
    local rows = math.ceil(num / FLYOUT_COLS)
    flyout:SetWidth(cols * (FLYOUT_BTN_SIZE + 2) + 6)
    flyout:SetHeight(rows * (FLYOUT_BTN_SIZE + 2) + 6)
    flyout:ClearAllPoints()
    -- Anchor to the popout button so the flyout sits past it (avoids
    -- overlapping the chevron). Falls back to the slot itself for the
    -- EM grid btns which don't have a separate popout.
    local anchorBtn = slotBtn.popout or slotBtn
    if invSlot == 16 or invSlot == 17 or invSlot == 18 then
      flyout:SetPoint("BOTTOMLEFT", anchorBtn, "TOPLEFT", 0, 4)
    else
      local centerX = (anchorBtn:GetLeft() or 0) + anchorBtn:GetWidth()/2
      if centerX > GetScreenWidth()/2 then
        flyout:SetPoint("TOPRIGHT", anchorBtn, "TOPLEFT", -4, 0)
      else
        flyout:SetPoint("TOPLEFT", anchorBtn, "TOPRIGHT", 4, 0)
      end
    end
    -- Reverse the chevron on the active popout, restore the previously
    -- active one (if any). flyout.currentPopout drives OnHide cleanup.
    if flyout.currentPopout and flyout.currentPopout ~= slotBtn.popout then
      SetPopoutReversed(flyout.currentPopout, false)
    end
    flyout.currentPopout = slotBtn.popout
    SetPopoutReversed(slotBtn.popout, true)
    flyout:Show()
  end

  flyout:SetScript("OnHide", function()
    this.targetInvSlot = nil
    if this.currentPopout then
      SetPopoutReversed(this.currentPopout, false)
      this.currentPopout = nil
    end
  end)

  -- ============================================================
  -- Paperdoll slot setup: ignored overlay + popout button per slot.
  -- ============================================================

  local CHAR_SLOT_NAMES = {
    "HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot",
    "ShirtSlot", "TabardSlot", "WristSlot", "HandsSlot", "WaistSlot",
    "LegsSlot", "FeetSlot", "Finger0Slot", "Finger1Slot",
    "Trinket0Slot", "Trinket1Slot", "MainHandSlot", "SecondaryHandSlot",
    "RangedSlot",
  }
  -- Slot ID classification for popout positioning. Weapons sit at the
  -- bottom of the paperdoll, so their popout goes on top (chevron up).
  -- All other slots get the popout on their right side, chevron right.
  local POPOUT_TEX = pfUI.path.."\\img\\UI-GearManager-FlyoutButton"

  for _, slotName in ipairs(CHAR_SLOT_NAMES) do
    local slot = _G["Character"..slotName]
    if slot then
      -- "Ignored" overlay rendered on top of the paperdoll slot icon.
      -- pfUI loads modules BEFORE skins (pfUI.lua:407-418), so at this
      -- point slot.backdrop doesn't exist yet — the character skin
      -- creates it later and reparents the item icon to it. A plain
      -- texture on `slot` would render BENEATH the backdrop's icon.
      -- Wrap the texture in a frame with a higher frame level so it
      -- renders above the backdrop regardless of skin-init order.
      local overlayFrame = CreateFrame("Frame", nil, slot)
      overlayFrame:SetAllPoints(slot)
      overlayFrame:SetFrameLevel(slot:GetFrameLevel() + 10)
      local overlay = overlayFrame:CreateTexture(nil, "OVERLAY")
      overlay:SetAllPoints(overlayFrame)
      overlay:SetTexture(pfUI.path.."\\img\\UI-GearManager-LeaveItem-Transparent")
      overlayFrame:Hide()
      slotOverlays[slot:GetID()] = overlayFrame

      -- Popout arrow button — clicking opens the equipment flyout for
      -- this slot. Replaces the Alt+click trigger with a discoverable
      -- visual affordance matching modern WoW's paperdoll.
      local invSlot = slot:GetID()
      local popout = CreateFrame("Button", nil, slot)
      popout:SetFrameLevel(slot:GetFrameLevel() + 1)
      -- Match Blizzard's EquipmentFlyoutPopoutButtonTemplate: 16x32,
      -- anchored LEFT to slot's RIGHT (chevron points away from slot
      -- toward the flyout's opening side).
      popout:SetWidth(16); popout:SetHeight(32)
      if INVSLOTS_EQUIPABLE_IN_COMBAT[invSlot] then
        -- Weapon row: popout on TOP, vertical orientation.
        popout:SetWidth(32); popout:SetHeight(16)
        popout:SetPoint("BOTTOM", slot, "TOP", 0, 0)
      else
        -- All horizontal slots get the popout on the RIGHT edge, chevron
        -- points right. Right-column slot popouts extend slightly into
        -- the EM sidecar gutter — acceptable, matches modern UX.
        popout:SetPoint("LEFT", slot, "RIGHT", 0, 0)
      end
      popout:SetNormalTexture(POPOUT_TEX)
      popout:SetHighlightTexture(POPOUT_TEX, "ADD")
      -- Stash both texCoord variants (normal=closed, reversed=open) so
      -- SetPopoutReversed can swap between them. Reversed = swap all
      -- y-values 0↔0.5 / 0.5↔1, matching modern WoW.
      if INVSLOTS_EQUIPABLE_IN_COMBAT[invSlot] then
        -- Closed: chevron points UP (toward where the flyout will open).
        popout.coordNormal     = { 0.15625, 0.84375, 0, 0.5 }
        popout.coordReversed   = { 0.15625, 0.84375, 0.5, 0 }
        popout.coordNormalHi   = { 0.15625, 0.84375, 0.5, 1 }
        popout.coordReversedHi = { 0.15625, 0.84375, 1, 0.5 }
      else
        popout.coordNormal     = { 0.15625, 0.5, 0.84375, 0.5, 0.15625, 0, 0.84375, 0 }
        popout.coordReversed   = { 0.15625, 0, 0.84375, 0, 0.15625, 0.5, 0.84375, 0.5 }
        popout.coordNormalHi   = { 0.15625, 1, 0.84375, 1, 0.15625, 0.5, 0.84375, 0.5 }
        popout.coordReversedHi = { 0.15625, 0.5, 0.84375, 0.5, 0.15625, 1, 0.84375, 1 }
      end
      SetPopoutReversed(popout, false)
      slot.popout = popout
      popout:SetScript("OnClick", function()
        -- Toggle: if the flyout is showing for this same slot, hide it;
        -- otherwise (re)open it for the clicked slot.
        if flyout:IsShown() and flyout.targetInvSlot == invSlot then
          flyout:Hide()
        else
          pfUI.equipmentmanager.ShowFlyout(slot)
        end
      end)
      popout:Hide()
      table.insert(popoutButtons, popout)
    end
  end

  -- Popout arrows follow the EM sidecar by default. With the
  -- "Always Show Equipment Slot Flyouts" option they follow the paperdoll
  -- instead, so gear can be swapped without opening the equipment manager.
  local function PopoutsActive()
    if C.character.inventory.equipflyout == "1" then
      return PaperDollFrame:IsShown()
    end
    return frame:IsShown()
  end

  function UpdatePopouts()
    local show = PopoutsActive()
    for _, b in ipairs(popoutButtons) do
      if show then b:Show() else b:Hide() end
    end
    if not show then flyout:Hide() end
  end

  PaperDollFrame:HookScript("OnShow", UpdatePopouts)
  PaperDollFrame:HookScript("OnHide", UpdatePopouts)

  -- ============================================================
  -- Refresh
  -- ============================================================

  function pfUI.equipmentmanager.Refresh()
    local ids = C_EquipmentSet.GetEquipmentSetIDs() or {}
    local numSets = table.getn(ids)

    -- Auto-select the first set if none is selected (or the previously
    -- selected one was deleted). Falls through to "show equipped" only
    -- when zero sets exist.
    if numSets > 0 then
      local stillExists = false
      if selectedSetID then
        for _, id in ipairs(ids) do
          if id == selectedSetID then stillExists = true; break end
        end
      end
      if not stillExists then selectedSetID = ids[1] end
    else
      selectedSetID = nil
    end

    -- Virtual list = sets ++ newSetRow. Clamp the current scroll
    -- offset against the visible window before laying out rows so
    -- deleting sets snaps the list back into view.
    local totalItems = numSets + 1
    local maxOffset = math.max(0, totalItems - LIST_VISIBLE_ROWS)
    if listFrame.offset > maxOffset then listFrame.offset = maxOffset end
    if listFrame.offset < 0 then listFrame.offset = 0 end
    local off = listFrame.offset

    -- Set rows: lazy-grow the pool to numSets, then position visible
    -- ones into slots and hide the rest. Each row stays bound to a
    -- specific set index (row[i] always shows ids[i]).
    for i = 1, numSets do
      if not setRows[i] then setRows[i] = CreateSetRow() end
      local row = setRows[i]
      local slot = i - off
      if slot >= 1 and slot <= LIST_VISIBLE_ROWS then
        local setID = ids[i]
        local name, icon, _, isEquipped, _, _, _, numMissing = C_EquipmentSet.GetEquipmentSetInfo(setID)
        row.setID = setID
        -- Color precedence: missing items (red) > equipped (green) > normal (white).
        local color = (numMissing and numMissing > 0) and "|cffff5555"
                      or isEquipped and "|cff33ff33" or "|cffffffff"
        row.text:SetText(color .. (name or "?") .. "|r")
        if icon then
          local full = string.find(icon, "\\") and icon or ("Interface\\Icons\\" .. icon)
          row.icon:SetTexture(full)
        else
          row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        end
        if setID == selectedSetID then row.highlight:Show() else row.highlight:Hide() end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 5, -3 - (slot - 1) * LIST_ROW_STRIDE)
        row:Show()
      else
        row:Hide()
        row.setID = nil
      end
    end
    -- Hide pool entries past the current set count (left over from a
    -- previous Refresh with more sets — e.g. just deleted one).
    for i = numSets + 1, table.getn(setRows) do
      setRows[i]:Hide()
      setRows[i].setID = nil
    end

    -- "+ New Set" row occupies virtual index numSets+1.
    local newSlot = (numSets + 1) - off
    if newSlot >= 1 and newSlot <= LIST_VISIBLE_ROWS then
      newSetRow:ClearAllPoints()
      newSetRow:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 5, -3 - (newSlot - 1) * LIST_ROW_STRIDE)
      newSetRow:Show()
    else
      newSetRow:Hide()
    end

    -- Update the ignored-overlay textures attached to each paperdoll
    -- slot. Uses effective state (persistent + pending toggles) so
    -- uncommitted user changes show immediately.
    local setIgnored = selectedSetID and GetEffectiveIgnored(selectedSetID) or {}
    for slotID, overlay in pairs(slotOverlays) do
      if selectedSetID and setIgnored[slotID] then overlay:Show() else overlay:Hide() end
    end

    local hasSelection = selectedSetID and true or false
    if hasSelection then btnEquip:Enable(); btnSave:Enable()
    else btnEquip:Disable(); btnSave:Disable() end
  end

  -- ============================================================
  -- Events
  -- ============================================================

  local events = CreateFrame("Frame")
  events:RegisterEvent("EQUIPMENT_SETS_CHANGED")
  events:RegisterEvent("EQUIPMENT_SWAP_FINISHED")
  events:RegisterEvent("EQUIPMENT_SWAP_PENDING")
  events:RegisterEvent("BAG_UPDATE_DELAYED")
  events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
  events:SetScript("OnEvent", function()
    if not frame:IsShown() then return end
    pfUI.equipmentmanager.Refresh()
  end)

end)
