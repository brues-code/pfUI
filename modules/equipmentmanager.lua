-- Equipment Manager module
-- Backport of the 4.3.4 GearManagerDialog UI on top of ClassicAPI's C_EquipmentSet.* API.

pfUI:RegisterModule("equipmentmanager", function()
  if not C_EquipmentSet or not C_EquipmentSet.CanUseEquipmentSets() then return end

  pfUI.equipmentmanager = {}

  -- Per-character storage for the features ClassicAPI doesn't persist
  -- itself: automatic-switch triggers (they reference this character's
  -- setIDs), the "not in any set" ignore list and a snapshot of the bank
  -- so bank items can be listed while the bank is closed.
  _G.pfUI_eqmgr = _G.pfUI_eqmgr or {}
  local db = _G.pfUI_eqmgr
  db.triggers = db.triggers or {}
  db.nextID = db.nextID or 1
  db.bank = db.bank or {}
  if not db.ignore then
    -- Tools and quest disguises that are equippable but never belong in a
    -- set (same list Outfitter ships). Users can un-ignore them.
    db.ignore = {
      [2901] = true,   -- Mining Pick
      [5956] = true,   -- Blacksmith Hammer
      [6219] = true,   -- Arclight Spanner
      [7005] = true,   -- Skinning Knife
      [7297] = true,   -- Morbent's Bane
      [10696] = true,  -- Enchanted Azsharite Felbane Sword
      [10697] = true,  -- Enchanted Azsharite Felbane Dagger
      [10698] = true,  -- Enchanted Azsharite Felbane Staff
      [20406] = true,  -- Twilight Cultist Mantle
      [20407] = true,  -- Twilight Cultist Robe
      [20408] = true,  -- Twilight Cultist Cowl
    }
  end

  -- Hidden set used by the trigger engine to remember the gear worn before
  -- a trigger kicked in ("restore previous gear"). It's GUID-based like any
  -- other set, so restoring is a single atomic UseEquipmentSet. Filtered
  -- out of every list this module shows and deleted once it's restored.
  local RESTORE_SET_NAME = "pfUI Auto-Restore"

  local function IsRestoreSet(setID)
    return setID and C_EquipmentSet.GetEquipmentSetInfo(setID) == RESTORE_SET_NAME
  end

  -- All set IDs except the hidden restore snapshot.
  local function GetVisibleSetIDs()
    local result = {}
    for _, id in ipairs(C_EquipmentSet.GetEquipmentSetIDs() or {}) do
      if not IsRestoreSet(id) then table.insert(result, id) end
    end
    return result
  end

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
  frame:SetSize(220, 368)
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
  -- Per-row context menu, opened from the gear icon on each set row.
  -- ============================================================

  local function EditSet(setID)
    local name, icon = C_EquipmentSet.GetEquipmentSetInfo(setID)
    selectedSetID = setID
    OpenNamePopup("save", name, icon)
  end

  local function DeleteSet(setID)
    local name = C_EquipmentSet.GetEquipmentSetInfo(setID)
    StaticPopupDialogs["PFUI_EQMGR_DELETE"] = {
      text = string.format(CONFIRM_DELETE_EQUIPMENT_SET, name or "?"),
      button1 = YES, button2 = NO,
      OnAccept = function()
        pendingIgnoredToggles[setID] = nil
        C_EquipmentSet.DeleteEquipmentSet(setID)
        if selectedSetID == setID then selectedSetID = nil end
        pfUI.equipmentmanager.Refresh()
      end,
      timeout = 0, whileDead = 1, hideOnEscape = 1, exclusive = 1,
    }
    StaticPopup_Show("PFUI_EQMGR_DELETE")
  end

  -- The row owns the menu, not the gear: the gear hides when the cursor
  -- leaves the row for the menu, and a menu closes with its owner.
  local function GenerateSetMenu(row, rootDescription)
    rootDescription:CreateButton(EQUIPMENT_SET_EDIT, EditSet, row.setID)
    rootDescription:CreateButton(DELETE, DeleteSet, row.setID)
  end

  -- ============================================================
  -- Set list (left column)
  -- ============================================================

  local LIST_VISIBLE_ROWS = 7
  -- The template keeps 5px around the rows, which sit 2px apart.
  local listFrame = CreateFrame("Frame", nil, frame, "pfUIScrollBoxListTemplate")
  listFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -58)
  listFrame:SetSize(180, LIST_VISIBLE_ROWS * (SET_ROW_HEIGHT + 2) - 2 + 10)
  CreateBackdrop(listFrame, nil, nil, .75)

  -- One-time setup of a pooled row. A row shows a set or, last in the
  -- list, the "New Set" entry; InitSetRow sets what differs.
  local function SetupSetRow(row)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("CENTER", row, "LEFT", 17, 0)

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.text:SetPoint("LEFT", row, "LEFT", 38, 0)
    row.text:SetJustifyH("LEFT")

    row.highlight = row:CreateTexture(nil, "BACKGROUND")
    row.highlight:SetAllPoints(row)
    row.highlight:SetColorTexture(.3, .3, .3, .4)
    row.highlight:Hide()

    row.gear = CreateFrame("Button", nil, row)
    row.gear:SetSize(16, 16);
    row.gear:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.gear.tex = row.gear:CreateTexture(nil, "ARTWORK")
    row.gear.tex:SetAllPoints(row.gear)
    row.gear.tex:SetTexture(pfUI.path.."\\img\\Gear_64Grey")
    row.gear.tex:SetAlpha(.5)
    -- the gear drawn again additively lights up the gear itself
    row.gear:SetHighlightTexture(pfUI.path.."\\img\\Gear_64Grey", "ADD")
    -- moving onto the gear does not leave the row
    row.gear:SetPropagateMouseMotion(true)
    row.gear:Hide()
    row.menuMixin = pfUIMenuStyleMixin
    row.gear:SetScript("OnClick", function()
      if row.setID then MenuUtil.CreateContextMenu(row, GenerateSetMenu) end
    end)

    row:SetScript("OnClick", function()
      if row.setID then
        selectedSetID = row.setID
        pfUI.equipmentmanager.Refresh()
      else
        OpenNamePopup("new")
      end
    end)
    row:SetScript("OnDoubleClick", function()
      if row.setID then EquipSet(row.setID) end
    end)

    -- Drag a set onto an action bar.
    row:RegisterForDrag("LeftButton")
    row:SetScript("OnDragStart", function()
      if row.setID then C_EquipmentSet.PickupEquipmentSet(row.setID) end
    end)

    -- A set row shows its gear and tooltip while the cursor is over it;
    -- the "New Set" row lights up.
    row:SetScript("OnEnter", function()
      if not row.setID then
        row.highlight:Show()
        return
      end
      local name = C_EquipmentSet.GetEquipmentSetInfo(row.setID)
      if name then
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:SetEquipmentSet(name)
        GameTooltip:Show()
      end
      row.gear:Show()
    end)
    row:SetScript("OnLeave", function()
      GameTooltip:Hide()
      row.gear:Hide()
      if not row.setID then row.highlight:Hide() end
    end)
  end

  local function InitSetRow(row, entry)
    if not row.text then SetupSetRow(row) end

    row.setID = entry.setID
    row.gear:Hide()

    if not entry.setID then
      row.icon:SetSize(24, 24)
      row.icon:SetTexCoord(0, 1, 0, 1)
      row.icon:SetTexture(pfUI.path.."\\img\\Character-Plus")
      row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
      row.text:SetText(PAPERDOLL_NEWEQUIPMENTSET)
      row.text:SetTextColor(0.2, 1, 0.2)
      row.highlight:Hide()
      return
    end

    local name, icon, _, isEquipped, _, _, _, numMissing = C_EquipmentSet.GetEquipmentSetInfo(entry.setID)
    row.icon:SetSize(30, 30)
    row.icon:SetTexCoord(.08, .92, .08, .92)
    if icon then
      row.icon:SetTexture(string.find(icon, "\\") and icon or ("Interface\\Icons\\" .. icon))
    else
      row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end
    -- Color precedence: missing items (red) > equipped (green) > normal (white).
    local color = (numMissing and numMissing > 0) and "|cffff5555"
                  or isEquipped and "|cff33ff33" or "|cffffffff"
    row.text:SetPoint("RIGHT", row, "RIGHT", -22, 0)
    row.text:SetText(color .. (name or "?") .. "|r")
    row.highlight:SetShown(entry.setID == selectedSetID)
  end

  local setView = CreateScrollBoxListLinearView(0, 0, 0, 2, 2)
  setView:SetElementExtent(SET_ROW_HEIGHT)
  setView:SetElementInitializer("Button", InitSetRow)
  ScrollUtil.InitScrollBoxListWithScrollBar(listFrame.ScrollBox, listFrame.ScrollBar, setView)

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
    -- The "ignored slot" overlays belong to the selected set, which is
    -- only meaningful while the manager is open.
    for _, overlay in pairs(slotOverlays) do overlay:Hide() end
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
        local quality
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
            local tex, count, _, q = GetContainerItemInfo(loc.bag, loc.slot)
            quality = q
            b.texture:SetTexture(tex)
            if count and count > 1 then b.count:SetText(count) else b.count:SetText("") end
          else  -- isPlayer (equipped in some other slot)
            b.invSlot = loc.slot
            b.texture:SetTexture(GetInventoryItemTexture("player", loc.slot))
            b.count:SetText("")
            quality = GetInventoryItemQuality("player", loc.slot)
          end
        end
        -- Quality border, matching the character slots
        if quality and quality > 0 then
          b.backdrop:SetBackdropBorderColor(GetItemQualityColor(quality))
        else
          b.backdrop:SetBackdropBorderColor(pfUI.cache.er, pfUI.cache.eg, pfUI.cache.eb, pfUI.cache.ea)
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
  -- IsVisible, not IsShown: closing CharacterFrame fires OnHide on both
  -- without clearing their own shown flags.
  local function PopoutsActive()
    if C.character.inventory.equipflyout == "1" then
      return PaperDollFrame:IsVisible()
    end
    return frame:IsVisible()
  end

  function UpdatePopouts()
    local show = PopoutsActive()
    for _, b in ipairs(popoutButtons) do
      b:SetShown(show)
    end
    if not show then flyout:Hide() end
  end

  PaperDollFrame:HookScript("OnShow", UpdatePopouts)
  PaperDollFrame:HookScript("OnHide", UpdatePopouts)

  -- ============================================================
  -- Refresh
  -- ============================================================

  function pfUI.equipmentmanager.Refresh()
    local ids = GetVisibleSetIDs()
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

    -- The rows are the sets, then the "New Set" entry. They are rebuilt
    -- only when the sets change; otherwise the shown rows refresh in
    -- place, so the row under the cursor stays the same frame and a
    -- double-click reaches it.
    local setsKey = table.concat(ids, ",")
    if setsKey ~= listFrame.setsKey then
      listFrame.setsKey = setsKey
      local entries = {}
      for _, setID in ipairs(ids) do
        table.insert(entries, { setID = setID })
      end
      table.insert(entries, { newSet = true })
      listFrame.ScrollBox:SetDataProvider(CreateDataProvider(entries), ScrollBoxConstants.RetainScrollPosition)
    else
      listFrame.ScrollBox:ReinitializeFrames()
    end

    -- Update the ignored-overlay textures attached to each paperdoll
    -- slot. Uses effective state (persistent + pending toggles) so
    -- uncommitted user changes show immediately.
    local setIgnored = selectedSetID and GetEffectiveIgnored(selectedSetID) or {}
    for slotID, overlay in pairs(slotOverlays) do
      overlay:SetShown(frame:IsShown() and selectedSetID and setIgnored[slotID])
    end

    local hasSelection = selectedSetID and true or false
    if hasSelection then btnEquip:Enable(); btnSave:Enable()
    else btnEquip:Disable(); btnSave:Disable() end

    pfUI.equipmentmanager.RefreshExtras()
  end

  -- ============================================================
  -- Shared helpers for the extra panels (unused items / triggers)
  -- ============================================================

  local function CreateCheckbox(parent, label)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(20, 20)
    SkinCheckbox(cb, 14)
    if label then
      cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontWhite")
      cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
      cb.label:SetText(label)
    end
    return cb
  end

  local function CreateSmallButton(parent, dir, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size or 14, size or 14)
    SkinArrowButton(b, dir, size or 14)
    return b
  end

  local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpf|cffffffffUI|r: " .. msg)
  end

  -- Side panels open to the right of the equipment manager. Only one is
  -- shown at a time; they're children of the sidecar so they close with it.
  local subPanels = {}
  local function CreateSubPanel(name, width, height, titleText)
    local p = CreateFrame("Frame", name, frame)
    p:SetSize(width, height)
    p:SetFrameStrata("HIGH")
    p:SetPoint("TOPLEFT", frame, "TOPRIGHT", 2*border + 2, 0)
    p:EnableMouse(true)
    CreateBackdrop(p, nil, nil, .9)
    CreateBackdropShadow(p)
    p:Hide()

    p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    p.title:SetPoint("TOP", p, "TOP", 0, -10)
    p.title:SetText(titleText)

    p.close = CreateFrame("Button", nil, p, "UIPanelCloseButton")
    p.close:SetPoint("TOPRIGHT", p, "TOPRIGHT", -4, -4)
    p.close:SetScript("OnClick", function() p:Hide() end)
    SkinCloseButton(p.close, p.backdrop or p, -6, -6)

    table.insert(subPanels, p)
    return p
  end

  local function ToggleSubPanel(p)
    if p:IsShown() then
      p:Hide()
      return
    end
    for _, other in ipairs(subPanels) do other:Hide() end
    p:Show()
  end

  -- ============================================================
  -- Items not in any set
  -- ============================================================

  local WHERE_ORDER = { equipped = 1, bags = 2, bank = 3 }
  local BANK_BAGS = { -1, 5, 6, 7, 8, 9, 10 }  -- main bank, bank bags

  local bankOpen = false

  -- Returns the list of equippable items that no equipment set references,
  -- plus how many of those are on the ignore list. Ignored items are only
  -- included in the list when includeIgnored is set.
  local function ScanUnusedItems(includeIgnored)
    local minQuality = tonumber(C.equipmentmanager.unusedquality)
    local result, numIgnored = {}, 0

    local function Consider(entry)
      entry.icon = C_Item.GetItemIconByID(entry.itemID)
      entry.quality = C_Item.GetItemQualityByID(entry.itemID) or 1
      if entry.quality < minQuality then return end
      if db.ignore[entry.itemID] then
        numIgnored = numIgnored + 1
        if not includeIgnored then return end
        entry.ignored = true
      end
      table.insert(result, entry)
    end

    -- Packed location of every item some set uses. Paperdoll and bag items
    -- always resolve, so these match GetInventoryItemsForSlot's keys.
    local inSet = {}
    for _, setID in ipairs(GetVisibleSetIDs()) do
      for _, location in pairs(C_EquipmentSet.GetItemLocations(setID)) do
        inSet[location] = true
      end
    end

    -- Everything on the paperdoll or in the bags that fits a gear slot,
    -- keyed by packed location (rings and trinkets fit two slots).
    local items = {}
    for invSlot = 1, 19 do GetInventoryItemsForSlot(invSlot, items) end

    for location, link in pairs(items) do
      if not inSet[location] then
        local loc = EquipmentManager_GetLocationData(location)
        Consider({
          where = loc.isBags and "bags" or "equipped",
          bag = loc.bag, slot = loc.slot,
          itemID = (C_Item.GetItemInfoInstant(link)), link = link,
        })
      end
    end

    if C.equipmentmanager.unusedbank == "1" then
      for _, item in ipairs(db.bank) do
        if not item.inSet then
          Consider({ where = "bank", bag = item.bag, slot = item.slot, itemID = item.id, link = item.link })
        end
      end
    end

    table.sort(result, function(a, b)
      if a.where ~= b.where then return WHERE_ORDER[a.where] < WHERE_ORDER[b.where] end
      if a.quality ~= b.quality then return a.quality > b.quality end
      if a.itemID ~= b.itemID then return a.itemID < b.itemID end
      if a.bag ~= b.bag then return (a.bag or 0) < (b.bag or 0) end
      return a.slot < b.slot
    end)

    return result, numIgnored
  end

  -- Snapshot the bank while it's open so its items stay listed afterwards.
  -- Set membership is recorded now as well: ClassicAPI only resolves set
  -- items in the bank while the bank window is open.
  local function ScanBank()
    local snapshot = {}
    for _, bag in ipairs(BANK_BAGS) do
      for slot = 1, GetContainerNumSlots(bag) do
        local itemID = C_Container.GetContainerItemID(bag, slot)
        if itemID then
          table.insert(snapshot, {
            id = itemID, link = GetContainerItemLink(bag, slot), bag = bag, slot = slot,
            inSet = C_Container.GetContainerItemEquipmentSetInfo(bag, slot),
          })
        end
      end
    end
    db.bank = snapshot
  end

  local UNUSED_COLS, UNUSED_ROWS = 7, 8
  local UNUSED_SIZE, UNUSED_GAP = 30, 4

  -- The grid's list template keeps 5px around the buttons and a 7px scroll
  -- bar 2px right of them.
  local UNUSED_GRID_W = UNUSED_COLS * (UNUSED_SIZE + UNUSED_GAP) - UNUSED_GAP + 2 + 7 + 10
  local UNUSED_GRID_H = UNUSED_ROWS * (UNUSED_SIZE + UNUSED_GAP) - UNUSED_GAP + 10

  local unusedPanel = CreateSubPanel("pfEqMgrUnusedFrame",
    UNUSED_GRID_W + 22, frame:GetHeight(), T["Items Not In Any Set"])

  unusedPanel.info = unusedPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  unusedPanel.info:SetPoint("TOPLEFT", unusedPanel, "TOPLEFT", 14, -34)
  unusedPanel.info:SetJustifyH("LEFT")

  unusedPanel.showIgnored = CreateCheckbox(unusedPanel)
  unusedPanel.showIgnored:SetPoint("TOPRIGHT", unusedPanel, "TOPRIGHT", -12, -29)
  unusedPanel.showIgnored.label = unusedPanel.showIgnored:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  unusedPanel.showIgnored.label:SetPoint("RIGHT", unusedPanel.showIgnored, "LEFT", -4, 0)
  unusedPanel.showIgnored.label:SetText(T["Show Ignored"])

  local unusedGrid = CreateFrame("Frame", nil, unusedPanel, "pfUIScrollBoxListTemplate")
  unusedGrid:SetPoint("TOPLEFT", unusedPanel, "TOPLEFT", 11, -51)
  unusedGrid:SetSize(UNUSED_GRID_W, UNUSED_GRID_H)

  unusedPanel.empty = unusedPanel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  unusedPanel.empty:SetPoint("CENTER", unusedGrid, "CENTER", 0, 0)
  unusedPanel.empty:SetWidth(UNUSED_GRID_W - 20)
  unusedPanel.empty:SetText(T["Every equippable item is part of a set."])

  unusedPanel.hint = unusedPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  unusedPanel.hint:SetPoint("BOTTOMLEFT", unusedPanel, "BOTTOMLEFT", 14, 12)
  unusedPanel.hint:SetPoint("BOTTOMRIGHT", unusedPanel, "BOTTOMRIGHT", -14, 12)
  unusedPanel.hint:SetJustifyH("LEFT")
  unusedPanel.hint:SetText(T["Shift-Click: Link  Ctrl-Click: Preview\nRight-Click: Ignore / Unignore"])

  local RefreshUnusedPanel  -- forward decl

  -- Bag highlight: while the panel is open, items of the list glow in
  -- pfUI's bag and bank frames and every other item is dimmed.
  local bagHighlight = { active = false, locs = {}, hooked = false }

  local function ApplyBagHighlight(bag, slot)
    local entry = pfUI.bags and pfUI.bags[bag] and pfUI.bags[bag].slots[slot]
    if not entry or not entry.frame then return end
    local f = entry.frame
    local o = f.pfEqMgrUnused

    if not bagHighlight.active or not f.hasItem then
      if o then o:Hide() end
      return
    end

    if not o then
      o = CreateFrame("Frame", nil, f)
      o:SetAllPoints(f)
      o:SetFrameLevel(f:GetFrameLevel() + 3)

      o.dim = o:CreateTexture(nil, "OVERLAY")
      o.dim:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
      o.dim:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
      o.dim:SetColorTexture(0, 0, 0, .7)

      o.glow = o:CreateTexture(nil, "OVERLAY")
      o.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
      o.glow:SetBlendMode("ADD")
      o.glow:SetVertexColor(.2, 1, .2, 1)
      o.glow:SetPoint("CENTER", f, "CENTER", 0, 0)

      f.pfEqMgrUnused = o
    end

    if bagHighlight.locs[bag] and bagHighlight.locs[bag][slot] then
      local w = f:GetWidth()
      if w and w > 0 then o.glow:SetSize(w * 1.8, w * 1.8) end
      o.dim:Hide()
      o.glow:Show()
    else
      o.glow:Hide()
      o.dim:Show()
    end
    o:Show()
  end

  local function UpdateBagHighlights()
    -- Only pfUI's own bag frames are decorated (the bags module may be off).
    if not pfUI.bag or not pfUI.bags then return end
    if not bagHighlight.hooked and pfUI.bag.UpdateSlot then
      -- Re-apply whenever pfUI redraws a slot (item moved, bag reopened...).
      hooksecurefunc(pfUI.bag, "UpdateSlot", function(_, bag, slot)
        if bagHighlight.active then ApplyBagHighlight(bag, slot) end
      end)
      bagHighlight.hooked = true
    end
    for bag, data in pairs(pfUI.bags) do
      if data and data.slots then
        for slot in pairs(data.slots) do ApplyBagHighlight(bag, slot) end
      end
    end
  end

  local WHERE_TAG = { equipped = "|cff33ff33E|r", bags = "", bank = "|cff66aaffB|r" }
  local WHERE_TEXT = { equipped = T["Equipped"], bags = T["In Bags"], bank = T["In Bank"] }

  -- one-time setup of a pooled grid button
  local function SetupUnusedButton(b)
    CreateBackdrop(b)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(b)
    b.icon:SetTexCoord(.08, .92, .08, .92)

    b.tag = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.tag:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)

    b:SetScript("OnEnter", function()
      local e = this.entry
      if not e then return end
      GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
      if e.where == "equipped" then
        GameTooltip:SetInventoryItem("player", e.slot)
      elseif e.where == "bags" then
        GameTooltip:SetBagItem(e.bag, e.slot)
      else
        GameTooltip:SetHyperlink(e.link)
      end
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(T["Not part of any equipment set"] .. " - " .. WHERE_TEXT[e.where], 1, .82, 0)
      if e.ignored then
        GameTooltip:AddLine(T["Ignored (Right-Click to unignore)"], .6, .6, .6)
      end
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)

    b:SetScript("OnClick", function()
      local e = this.entry
      if not e then return end
      if arg1 == "RightButton" then
        db.ignore[e.itemID] = (not db.ignore[e.itemID]) and true or nil
        GameTooltip:Hide()
        pfUI.equipmentmanager.Refresh()
      elseif IsShiftKeyDown() then
        if ChatFrameEditBox:IsVisible() then ChatFrameEditBox:Insert(e.link) end
      elseif IsControlKeyDown() then
        DressUpItemLink(e.link)
      end
    end)
  end

  local function InitUnusedButton(b, e)
    if not b.icon then SetupUnusedButton(b) end

    b.entry = e
    b.icon:SetTexture(e.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    b.icon:SetDesaturated(e.ignored and true or false)
    b.icon:SetAlpha(e.ignored and .5 or 1)
    b.tag:SetText(WHERE_TAG[e.where] or "")
    local r, g, bl = GetItemQualityColor(e.quality or 1)
    b.backdrop:SetBackdropBorderColor(r, g, bl, 1)
  end

  local unusedView = CreateScrollBoxListGridView(UNUSED_COLS, 0, 0, 0, 2, UNUSED_GAP, UNUSED_GAP)
  unusedView:SetElementSize(UNUSED_SIZE, UNUSED_SIZE)
  unusedView:SetElementInitializer("Button", InitUnusedButton)
  ScrollUtil.InitScrollBoxListWithScrollBar(unusedGrid.ScrollBox, unusedGrid.ScrollBar, unusedView)

  function RefreshUnusedPanel()
    local list, numIgnored = ScanUnusedItems(unusedPanel.showIgnored:GetChecked() and true or nil)
    local total = table.getn(list)
    local numShownIgnored = unusedPanel.showIgnored:GetChecked() and numIgnored or 0
    unusedPanel.info:SetText(string.format(T["%d items, %d ignored"], total - numShownIgnored, numIgnored))

    unusedGrid.ScrollBox:SetDataProvider(CreateDataProvider(list), ScrollBoxConstants.RetainScrollPosition)

    unusedPanel.empty:SetShown(total == 0)

    bagHighlight.active = true
    bagHighlight.locs = {}
    for _, e in ipairs(list) do
      if e.bag then
        bagHighlight.locs[e.bag] = bagHighlight.locs[e.bag] or {}
        bagHighlight.locs[e.bag][e.slot] = true
      end
    end
    UpdateBagHighlights()
  end

  unusedPanel.showIgnored:SetScript("OnClick", function() RefreshUnusedPanel() end)
  unusedPanel:SetScript("OnShow", function() RefreshUnusedPanel() end)
  unusedPanel:SetScript("OnHide", function()
    bagHighlight.active = false
    UpdateBagHighlights()
  end)

  local function RescanBank()
    if not bankOpen then return end
    ScanBank()
    if frame:IsShown() then pfUI.equipmentmanager.Refresh() end
  end

  pfUI.events:RegisterFrameEventAndCallback("BANKFRAME_OPENED", function()
    bankOpen = true
    RescanBank()
  end)
  pfUI.events:RegisterFrameEventAndCallback("BANKFRAME_CLOSED", function()
    bankOpen = false
  end)
  for _, event in ipairs({ "PLAYERBANKSLOTS_CHANGED", "BAG_UPDATE_DELAYED", "EQUIPMENT_SETS_CHANGED" }) do
    pfUI.events:RegisterFrameEventAndCallback(event, RescanBank)
  end

  -- ============================================================
  -- Automatic set switching (triggers)
  -- ============================================================

  local _, playerClass = UnitClass("player")

  -- Shapeshift form IDs as GetShapeshiftFormID reports them on this client
  -- (SpellShapeshiftForm.dbc, incl. Turtle's custom forms). A value can
  -- list several IDs so e.g. "Bear Form" covers Dire Bear Form too.
  local FORM_OPTIONS = {
    DRUID = {
      { value = "0", text = T["No Form (Caster)"] },
      { value = "5,8", text = T["Bear Form"] },
      { value = "1", text = T["Cat Form"] },
      { value = "3,11", text = T["Travel Form"] },
      { value = "4", text = T["Aquatic Form"] },
      { value = "31", text = T["Moonkin Form"] },
      { value = "2,9", text = T["Tree of Life Form"] },
    },
    WARRIOR = {
      { value = "17", text = T["Battle Stance"] },
      { value = "18", text = T["Defensive Stance"] },
      { value = "19", text = T["Berserker Stance"] },
    },
    ROGUE = { { value = "30", text = T["Stealth"] } },
    SHAMAN = { { value = "16", text = T["Ghost Wolf"] } },
    PRIEST = { { value = "28", text = T["Shadowform"] } },
  }
  local myForms = FORM_OPTIONS[playerClass]
  if myForms then table.insert(myForms, { value = "any", text = T["Any Form"] }) end

  local INSTANCE_OPTIONS = {
    { value = "party", text = T["Dungeon"] },
    { value = "raid", text = T["Raid"] },
    { value = "pvp", text = T["Battleground"] },
    { value = "none", text = T["Open World"] },
  }

  -- value: nil (no parameter), "list" (dropdown from .options) or "text".
  local TRIGGER_TYPES = {
    { key = "mounted",  text = T["Mounted"] },
    { key = "swimming", text = T["Swimming"] },
    { key = "dining",   text = T["Eating / Drinking"] },
    { key = "resting",  text = T["Resting (Inn / City)"] },
    { key = "stealth",  text = T["Stealthed"] },
    { key = "form",     text = T["Shapeshift Form / Stance"], value = "list", options = myForms },
    { key = "instance", text = T["Instance Type"], value = "list", options = INSTANCE_OPTIONS },
    { key = "zone",     text = T["Zone"], value = "text" },
    { key = "boss",     text = T["Targeting A Boss"] },
    { key = "time",     text = T["Time Of Day"], value = "text" },
  }
  local TRIGGER_TYPE = {}
  for _, info in ipairs(TRIGGER_TYPES) do TRIGGER_TYPE[info.key] = info end

  local function DefaultTriggerValue(key)
    if key == "form" then return myForms and myForms[1].value end
    if key == "instance" then return "raid" end
    if key == "zone" then return GetRealZoneText() end
    if key == "time" then return "20:00-23:00" end
  end

  local function DescribeTrigger(t)
    local info = TRIGGER_TYPE[t.type]
    if not info then return "?" end
    if info.value == "list" then
      for _, o in ipairs(info.options or {}) do
        if o.value == t.value then return info.text .. ": " .. o.text end
      end
      return info.text
    elseif info.value == "text" then
      return info.text .. ": " .. (t.value or "")
    end
    return info.text
  end

  -- Condition checks ---------------------------------------------

  -- Every food and drink buff shares the name of the base Food (433) or
  -- Drink (430) aura, so their localized names identify all of them.
  local DINING_AURAS = { C_Spell.GetSpellName(433), C_Spell.GetSpellName(430) }

  -- Like Outfitter: the dining set stays on only while there's still
  -- health or mana to regenerate, so it comes off as soon as you're full.
  local function IsDining()
    local healthFull = UnitHealth("player") >= UnitHealthMax("player")
    local manaFull = UnitPowerType("player") ~= 0 or UnitMana("player") >= UnitManaMax("player")
    if healthFull and manaFull then return false end
    for _, name in ipairs(DINING_AURAS) do
      if C_UnitAuras.GetAuraDataBySpellName("player", name, "HELPFUL") then return true end
    end
    return false
  end

  local function InForm(value)
    local formID = GetShapeshiftFormID() or 0
    if value == "any" then return formID ~= 0 end
    for _, id in ipairs({ strsplit(",", value or "") }) do
      if tonumber(id) == formID then return true end
    end
    return false
  end

  -- Zone trigger values are "zone; subzone; ..." as typed or added with "Here".
  local function ZoneEntries(value)
    local entries = {}
    for _, entry in ipairs({ strsplit(";", value or "") }) do
      entry = strtrim(entry):lower()
      if entry ~= "" then table.insert(entries, entry) end
    end
    return entries
  end

  local function InZone(value)
    local zone, subzone, minimap = GetRealZoneText():lower(), GetSubZoneText():lower(), GetMinimapZoneText():lower()
    for _, entry in ipairs(ZoneEntries(value)) do
      if entry == zone or entry == subzone or entry == minimap then return true end
    end
    return false
  end

  local function ParseTimeWindow(value)
    local _, _, h1, m1, h2, m2 = (value or ""):find("^%s*(%d%d?):(%d%d)%s*%-%s*(%d%d?):(%d%d)%s*$")
    if not h1 then return nil end
    return tonumber(h1) * 60 + tonumber(m1), tonumber(h2) * 60 + tonumber(m2)
  end

  local function InTimeWindow(value)
    local from, to = ParseTimeWindow(value)
    if not from then return false end
    local now = tonumber(date("%H")) * 60 + tonumber(date("%M"))
    if from <= to then return now >= from and now < to end
    return now >= from or now < to  -- window wraps past midnight
  end

  local function TargetIsBoss()
    if not UnitExists("target") or UnitIsDead("target") then return false end
    if not UnitCanAttack("player", "target") or UnitIsPlayer("target") then return false end
    return UnitClassification("target") == "worldboss" or UnitLevel("target") == -1
  end

  local function ConditionActive(t)
    local key = t.type
    if key == "mounted" then return IsMounted() and true or false
    elseif key == "swimming" then return IsSwimming() and true or false
    elseif key == "dining" then return IsDining()
    elseif key == "resting" then return IsResting() and true or false
    elseif key == "stealth" then return IsStealthed() and true or false
    elseif key == "form" then return InForm(t.value)
    elseif key == "instance" then
      local _, instanceType = GetInstanceInfo()
      return instanceType == t.value
    elseif key == "zone" then return InZone(t.value)
    elseif key == "boss" then return TargetIsBoss()
    elseif key == "time" then return InTimeWindow(t.value)
    end
    return false
  end

  -- Engine ---------------------------------------------------------

  -- forceApply: the active trigger was edited, equip its (new) set again.
  local engine = { ready = false, timer = nil, poll = nil, forceApply = nil }

  local function FindTrigger(id)
    if not id then return nil end
    for i, t in ipairs(db.triggers) do
      if t.id == id then return t, i end
    end
  end

  local function SetExists(setID)
    return setID and C_EquipmentSet.GetEquipmentSetInfo(setID) and not IsRestoreSet(setID)
  end

  local function TriggerUsable(t)
    return t.enabled and SetExists(t.setID) and TRIGGER_TYPE[t.type] and true or false
  end

  -- Highest-priority (topmost) enabled trigger whose condition holds.
  local function GetActiveTrigger()
    for _, t in ipairs(db.triggers) do
      if TriggerUsable(t) and ConditionActive(t) then return t end
    end
  end

  -- Whether the applied trigger differs from the one that should be, and
  -- the one that should be.
  local function NeedsSwitch()
    local best = GetActiveTrigger()
    return engine.forceApply or (best and best.id or 0) ~= (db.applied or 0), best
  end

  -- Gear can't change in combat or while dead, swapping mid-cast would
  -- interrupt it, and only one set swap runs at a time: the switch waits.
  local function SwapBlocked(setID)
    if UnitAffectingCombat("player") or UnitIsDeadOrGhost("player") then return true end
    if C_Spell.UnitCastingInfo("player") or C_Spell.UnitChannelInfo("player") then return true end
    if CursorHasItem() or not C_EquipmentSet.CanUseEquipmentSets() then return true end
    return C_EquipmentSet.EquipmentSetContainsLockedItems(setID)
  end

  -- A swap that's blocked or refused is retried by scheduling again.
  local function TryEquip(setID)
    return not SwapBlocked(setID) and C_EquipmentSet.UseEquipmentSet(setID)
  end

  -- Remember the gear worn before the first trigger fires. Only slots that
  -- some trigger set actually changes are recorded, so restoring doesn't
  -- undo unrelated gear changes made while the trigger was active.
  local function TakeRestoreSnapshot()
    local touched = {}
    for _, t in ipairs(db.triggers) do
      if TriggerUsable(t) then
        local ignored = {}
        for _, s in ipairs(C_EquipmentSet.GetIgnoredSlots(t.setID) or {}) do ignored[s] = true end
        for s = 1, 19 do
          if not ignored[s] then touched[s] = true end
        end
      end
    end

    C_EquipmentSet.ClearIgnoredSlotsForSave()
    for s = 1, 19 do
      if not touched[s] then C_EquipmentSet.IgnoreSlotForSave(s) end
    end
    local id = C_EquipmentSet.GetEquipmentSetID(RESTORE_SET_NAME)
    if id then
      C_EquipmentSet.SaveEquipmentSet(id)
    else
      C_EquipmentSet.CreateEquipmentSet(RESTORE_SET_NAME, "Spell_Nature_TimeStop")
    end
    C_EquipmentSet.ClearIgnoredSlotsForSave()
  end

  local function Announce(msg)
    if C.equipmentmanager.announce == "1" then Print(msg) end
  end

  local function SetName(setID)
    return (C_EquipmentSet.GetEquipmentSetInfo(setID)) or "?"
  end

  local RefreshTriggerPanel  -- forward decl
  local Schedule             -- forward decl

  local function Evaluate()
    if not engine.ready or C.equipmentmanager.autoswitch ~= "1" then return end

    local needed, best = NeedsSwitch()
    if not needed then return end
    local appliedID = db.applied or 0

    if best then
      if SwapBlocked(best.setID) then return Schedule() end
      -- Only the first trigger in a chain records what to go back to.
      if appliedID == 0 then TakeRestoreSnapshot() end
      if not C_EquipmentSet.UseEquipmentSet(best.setID) then return Schedule() end
      db.applied = best.id
      Announce(string.format(T["Equipping %s (%s)"], SetName(best.setID), DescribeTrigger(best)))
    else
      local prev = FindTrigger(appliedID)
      local leave = prev and prev.leave or "restore"
      local restoreID = C_EquipmentSet.GetEquipmentSetID(RESTORE_SET_NAME)
      if leave == "restore" and restoreID then
        if not TryEquip(restoreID) then return Schedule() end
        Announce(T["Restoring previous gear"])
      elseif type(leave) == "number" and SetExists(leave) then
        if not TryEquip(leave) then return Schedule() end
        Announce(string.format(T["Equipping %s"], SetName(leave)))
      end
      -- The swap copied the item GUIDs when it started; the set can go.
      if restoreID then C_EquipmentSet.DeleteEquipmentSet(restoreID) end
      db.applied = nil
    end

    engine.forceApply = nil
    RefreshTriggerPanel()
  end

  -- Switch half a second after something changed, so bobbing at the water
  -- surface or a quick target swap doesn't thrash gear. Also retries a
  -- swap that's blocked.
  function Schedule()
    if engine.timer then return end
    engine.timer = C_Timer.NewTimer(0.5, function()
      engine.timer = nil
      Evaluate()
    end)
  end

  -- Swimming and the time of day fire no event, so those are polled while
  -- a trigger needs them.
  local POLLED = { swimming = true, time = true }

  local engineEvents = CreateFrame("Frame")

  -- Call after any change to the triggers or the autoswitch setting.
  local function UpdateEngine()
    local poll, dining = false, false
    if C.equipmentmanager.autoswitch == "1" then
      for _, t in ipairs(db.triggers) do
        if t.enabled and POLLED[t.type] then poll = true end
        if t.enabled and t.type == "dining" then dining = true end
      end
    end

    -- The dining set comes off once health and mana are full; these fire
    -- constantly in combat, so only listen while a dining trigger exists.
    if dining then
      engineEvents:RegisterUnitEvent("UNIT_HEALTH", "player")
      engineEvents:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
    else
      engineEvents:UnregisterEvent("UNIT_HEALTH")
      engineEvents:UnregisterEvent("UNIT_POWER_UPDATE")
    end

    if poll and not engine.poll then
      engine.poll = C_Timer.NewTicker(0.5, function()
        if NeedsSwitch() then Schedule() end
      end)
    elseif not poll and engine.poll then
      engine.poll:Cancel()
      engine.poll = nil
    end
    Schedule()
  end

  engineEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
  engineEvents:RegisterEvent("PLAYER_LEAVING_WORLD")
  engineEvents:RegisterUnitEvent("UNIT_AURA_DELTA", "player") -- stealth, dining
  engineEvents:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
  engineEvents:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
  engineEvents:RegisterEvent("ZONE_CHANGED")
  engineEvents:RegisterEvent("ZONE_CHANGED_INDOORS")
  engineEvents:RegisterEvent("ZONE_CHANGED_NEW_AREA")
  engineEvents:RegisterEvent("PLAYER_UPDATE_RESTING")
  engineEvents:RegisterEvent("PLAYER_TARGET_CHANGED")
  engineEvents:RegisterEvent("PLAYER_REGEN_ENABLED")    -- a boss target died mid-fight
  engineEvents:SetScript("OnEvent", function()
    if event == "PLAYER_LEAVING_WORLD" then
      engine.ready = false
    elseif event == "PLAYER_ENTERING_WORLD" then
      -- Zone/instance info is unreliable right after a loading screen.
      engine.ready = false
      C_Timer.After(3, function()
        engine.ready = true
        Schedule()
      end)
    elseif event ~= "UNIT_POWER_UPDATE" or arg2 == "MANA" then
      -- the dining set waits on mana alone, not on rage or energy
      Schedule()
    end
  end)

  -- ============================================================
  -- Trigger editor panel
  -- ============================================================

  local TRIGGER_ROWS, TRIGGER_ROW_H = 5, 24
  local triggerPanel = CreateSubPanel("pfEqMgrTriggerFrame", 310, 404, T["Automatic Set Switching"])
  local selectedTriggerID = nil

  local cbAuto = CreateCheckbox(triggerPanel, T["Enable Automatic Set Switching"])
  cbAuto:SetPoint("TOPLEFT", triggerPanel, "TOPLEFT", 12, -30)
  cbAuto:SetScript("OnClick", function()
    C.equipmentmanager.autoswitch = this:GetChecked() and "1" or "0"
    UpdateEngine()
  end)

  -- The template keeps 5px around the rows, which sit 2px apart.
  local triggerList = CreateFrame("Frame", nil, triggerPanel, "pfUIScrollBoxListTemplate")
  triggerList:SetPoint("TOPLEFT", triggerPanel, "TOPLEFT", 14, -56)
  triggerList:SetSize(282, TRIGGER_ROWS * (TRIGGER_ROW_H + 2) - 2 + 10)
  CreateBackdrop(triggerList, nil, nil, .75)

  triggerList.empty = triggerList:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  triggerList.empty:SetPoint("CENTER", triggerList, "CENTER", 0, 0)
  triggerList.empty:SetWidth(260)
  triggerList.empty:SetText(T["No triggers yet. Click \"New Trigger\" to add one."])

  local function MoveTrigger(index, delta)
    local target = index + delta
    if target < 1 or target > table.getn(db.triggers) then return end
    db.triggers[index], db.triggers[target] = db.triggers[target], db.triggers[index]
    UpdateEngine()
    RefreshTriggerPanel()
  end

  -- one-time setup of a pooled trigger row
  local function SetupTriggerRow(row)
    row.highlight = row:CreateTexture(nil, "BACKGROUND")
    row.highlight:SetAllPoints(row)
    row.highlight:SetColorTexture(.3, .3, .3, .4)
    row.highlight:Hide()

    row.check = CreateCheckbox(row)
    row.check:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.check:SetScript("OnClick", function()
      if not row.trigger then return end
      row.trigger.enabled = this:GetChecked() and true or false
      UpdateEngine()
      RefreshTriggerPanel()
    end)

    row.delete = CreateSmallButton(row, "close", 14)
    row.delete:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row.down = CreateSmallButton(row, "down", 14)
    row.down:SetPoint("RIGHT", row.delete, "LEFT", -4, 0)
    row.up = CreateSmallButton(row, "up", 14)
    row.up:SetPoint("RIGHT", row.down, "LEFT", -4, 0)

    row.up:SetScript("OnClick", function() if row.index then MoveTrigger(row.index, -1) end end)
    row.down:SetScript("OnClick", function() if row.index then MoveTrigger(row.index, 1) end end)
    row.delete:SetScript("OnClick", function()
      if not row.index then return end
      local t = table.remove(db.triggers, row.index)
      if t and t.id == selectedTriggerID then selectedTriggerID = nil end
      UpdateEngine()
      RefreshTriggerPanel()
    end)

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", row.check, "RIGHT", 4, 0)
    row.text:SetPoint("RIGHT", row.up, "LEFT", -4, 0)
    row.text:SetJustifyH("LEFT")

    row:SetScript("OnClick", function()
      if not row.trigger then return end
      selectedTriggerID = row.trigger.id
      RefreshTriggerPanel()
    end)

    row:SetScript("OnEnter", function()
      if not row.trigger then return end
      GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
      GameTooltip:SetText(DescribeTrigger(row.trigger), 1, 1, 1)
      local t = row.trigger
      local equip = SetExists(t.setID) and SetName(t.setID) or ("|cffff5555" .. T["No set selected"] .. "|r")
      GameTooltip:AddDoubleLine(T["Equip"], equip, .7, .7, .7, 1, 1, 1)
      local leave = T["Restore Previous Gear"]
      if t.leave == "none" then leave = T["Do Nothing"]
      elseif type(t.leave) == "number" then leave = SetExists(t.leave) and SetName(t.leave) or "?" end
      GameTooltip:AddDoubleLine(T["When It Ends"], leave, .7, .7, .7, 1, 1, 1)
      if db.applied == t.id then
        GameTooltip:AddLine(T["Currently active"], .2, 1, .2)
      elseif TriggerUsable(t) and ConditionActive(t) then
        GameTooltip:AddLine(T["Condition met, but a trigger higher in the list wins"], 1, .82, 0)
      end
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end

  local function InitTriggerRow(row, entry)
    if not row.check then SetupTriggerRow(row) end

    local t, index = entry.trigger, entry.index
    row.trigger = t
    row.index = index
    row.check:SetChecked(t.enabled)

    local color = "|cffffffff"
    if not t.enabled then
      color = "|cff808080"
    elseif not SetExists(t.setID) then
      color = "|cffff5555"
    elseif db.applied == t.id then
      color = "|cff33ff33"
    elseif ConditionActive(t) then
      color = "|cffffd100"
    end
    local target = SetExists(t.setID) and SetName(t.setID) or T["No set selected"]
    row.text:SetText(color .. DescribeTrigger(t) .. "|r |cffaaaaaa>|r " .. color .. target .. "|r")

    row.highlight:SetShown(t.id == selectedTriggerID)
    row.up:SetEnabled(index > 1)
    row.down:SetEnabled(index < table.getn(db.triggers))
  end

  local triggerView = CreateScrollBoxListLinearView(0, 0, 0, 2, 2)
  triggerView:SetElementExtent(TRIGGER_ROW_H)
  triggerView:SetElementInitializer("Button", InitTriggerRow)
  ScrollUtil.InitScrollBoxListWithScrollBar(triggerList.ScrollBox, triggerList.ScrollBar, triggerView)

  local btnNewTrigger = CreateFrame("Button", nil, triggerPanel, "UIPanelButtonTemplate")
  btnNewTrigger:SetSize(110, 22)
  btnNewTrigger:SetPoint("TOPLEFT", triggerList, "BOTTOMLEFT", 0, -6)
  btnNewTrigger:SetText(T["New Trigger"])
  SkinButton(btnNewTrigger)
  btnNewTrigger:SetScript("OnClick", function()
    local ids = GetVisibleSetIDs()
    local t = {
      id = db.nextID,
      enabled = true,
      type = "mounted",
      setID = ids[1],
      leave = "restore",
    }
    db.nextID = db.nextID + 1
    table.insert(db.triggers, t)
    selectedTriggerID = t.id
    UpdateEngine()
    RefreshTriggerPanel()
    -- the new trigger is the last row
    triggerList.ScrollBox:ScrollToEnd()
  end)

  -- Editor for the selected trigger
  local editor = CreateFrame("Frame", nil, triggerPanel)
  editor:SetPoint("TOPLEFT", btnNewTrigger, "BOTTOMLEFT", 0, -12)
  editor:SetSize(282, 108)

  editor.header = editor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  editor.header:SetPoint("TOPLEFT", editor, "TOPLEFT", 0, 0)
  editor.header:SetText(T["Selected Trigger"])

  local EDITOR_ROW_Y = { -18, -44, -70, -96 }
  local function EditorLabel(text, row)
    local fs = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", editor, "TOPLEFT", 0, EDITOR_ROW_Y[row] - 4)
    fs:SetText(text)
    return fs
  end

  local function EditorDropdown(row)
    local dd = CreateFrame("DropdownButton", nil, editor, "pfUIDropdownTemplate")
    dd:SetWidth(190)
    dd:SetPoint("TOPRIGHT", editor, "TOPRIGHT", 0, EDITOR_ROW_Y[row])
    CreateBackdrop(dd, nil, true)
    return dd
  end

  local function SelectedTrigger()
    return FindTrigger(selectedTriggerID)
  end

  local function OnTriggerEdited()
    -- Re-evaluate from scratch: the edit may change which trigger wins,
    -- and an edited active trigger may now point at another set.
    if selectedTriggerID and selectedTriggerID == db.applied then engine.forceApply = true end
    UpdateEngine()
    RefreshTriggerPanel()
  end

  -- The radio callbacks for one field of the selected trigger; a trigger
  -- without the field reads as `default`.
  local function TriggerField(field, default)
    local function IsSelected(value)
      local t = SelectedTrigger()
      return t ~= nil and (t[field] or default) == value
    end
    local function SetSelected(value)
      local t = SelectedTrigger()
      if not t then return end
      t[field] = value
      OnTriggerEdited()
    end
    return IsSelected, SetSelected
  end

  EditorLabel(T["When"], 1)
  local ddType = EditorDropdown(1)
  local IsType = TriggerField("type")
  local function SetType(key)
    local t = SelectedTrigger()
    if not t or t.type == key then return end
    t.type = key
    t.value = DefaultTriggerValue(key)
    OnTriggerEdited()
  end
  ddType:SetupMenu(function(dropdown, rootDescription)
    for _, info in ipairs(TRIGGER_TYPES) do
      if info.value ~= "list" or info.options then
        rootDescription:CreateRadio(info.text, IsType, SetType, info.key)
      end
    end
  end)

  local valueLabel = EditorLabel(T["Value"], 2)
  local ddValue = EditorDropdown(2)
  local IsValue, SetValue = TriggerField("value")
  ddValue:SetupMenu(function(dropdown, rootDescription)
    local t = SelectedTrigger()
    local info = t and TRIGGER_TYPE[t.type]
    for _, o in ipairs(info and info.options or {}) do
      rootDescription:CreateRadio(o.text, IsValue, SetValue, o.value)
    end
  end)

  local editValue = CreateTextBox(nil, editor)
  editValue:SetHeight(20)
  editValue:SetTextInsets(4, 4, 2, 2)
  editValue:SetScript("OnTextChanged", function()
    if this.updating then return end
    local t = SelectedTrigger()
    if not t then return end
    t.value = this:GetText()
    Schedule()
  end)
  editValue:SetScript("OnEnterPressed", function()
    this:ClearFocus()
    RefreshTriggerPanel()
  end)
  editValue:SetScript("OnEditFocusGained", function() this.hasFocus = true end)
  editValue:SetScript("OnEditFocusLost", function()
    this.hasFocus = nil
    RefreshTriggerPanel()
  end)
  editValue:SetScript("OnEnter", function()
    local t = SelectedTrigger()
    if not t then return end
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    if t.type == "zone" then
      GameTooltip:SetText(T["Zone or subzone name"], 1, 1, 1)
      GameTooltip:AddLine(T["Separate several zones with ;"], .8, .8, .8, 1)
    else
      GameTooltip:SetText(T["Local time window, e.g. 20:00-23:00"], 1, 1, 1)
      GameTooltip:AddLine(T["Windows may wrap past midnight (22:00-02:00)."], .8, .8, .8, 1)
    end
    GameTooltip:Show()
  end)
  editValue:SetScript("OnLeave", function() GameTooltip:Hide() end)

  local btnCurrentZone = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
  btnCurrentZone:SetSize(56, 20)
  btnCurrentZone:SetPoint("TOPRIGHT", editor, "TOPRIGHT", 0, EDITOR_ROW_Y[2])
  btnCurrentZone:SetText(T["Here"])
  SkinButton(btnCurrentZone)
  btnCurrentZone:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:SetText(T["Add the current zone"], 1, 1, 1)
    GameTooltip:AddLine(GetRealZoneText() .. ((GetSubZoneText() or "") ~= "" and (" / " .. GetSubZoneText()) or ""), .8, .8, .8)
    GameTooltip:Show()
  end)
  btnCurrentZone:SetScript("OnLeave", function() GameTooltip:Hide() end)
  btnCurrentZone:SetScript("OnClick", function()
    local t = SelectedTrigger()
    if not t then return end
    -- Shift adds the subzone instead of the zone.
    local here = IsShiftKeyDown() and GetSubZoneText() or GetRealZoneText()
    if here == "" then here = GetRealZoneText() end
    local entries = ZoneEntries(t.value)
    if table.getn(entries) == 0 then
      t.value = here
    else
      for _, entry in ipairs(entries) do
        if entry == here:lower() then return end
      end
      t.value = t.value .. "; " .. here
    end
    OnTriggerEdited()
  end)

  editValue:SetPoint("TOPLEFT", editor, "TOPRIGHT", -190, EDITOR_ROW_Y[2])
  editValue:SetPoint("BOTTOMRIGHT", editor, "TOPRIGHT", 0, EDITOR_ROW_Y[2] - 20)

  EditorLabel(T["Equip"], 3)
  local ddSet = EditorDropdown(3)
  local IsSet, SetSet = TriggerField("setID")
  ddSet:SetupMenu(function(dropdown, rootDescription)
    for _, id in ipairs(GetVisibleSetIDs()) do
      rootDescription:CreateRadio(SetName(id), IsSet, SetSet, id)
    end
  end)

  EditorLabel(T["When It Ends"], 4)
  local ddLeave = EditorDropdown(4)
  local IsLeave, SetLeave = TriggerField("leave", "restore")
  ddLeave:SetupMenu(function(dropdown, rootDescription)
    rootDescription:CreateRadio(T["Restore Previous Gear"], IsLeave, SetLeave, "restore")
    rootDescription:CreateRadio(T["Do Nothing"], IsLeave, SetLeave, "none")
    for _, id in ipairs(GetVisibleSetIDs()) do
      rootDescription:CreateRadio(T["Equip"] .. " " .. SetName(id), IsLeave, SetLeave, id)
    end
  end)

  editor.noSets = editor:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  editor.noSets:SetPoint("TOPRIGHT", editor, "TOPRIGHT", 0, EDITOR_ROW_Y[3] - 4)
  editor.noSets:SetText(T["Create an equipment set first."])

  local triggerHint = triggerPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  triggerHint:SetPoint("BOTTOMLEFT", triggerPanel, "BOTTOMLEFT", 14, 12)
  triggerHint:SetPoint("BOTTOMRIGHT", triggerPanel, "BOTTOMRIGHT", -14, 12)
  triggerHint:SetHeight(40)  -- room to wrap to three lines below the editor
  triggerHint:SetJustifyH("LEFT")
  triggerHint:SetJustifyV("BOTTOM")
  triggerHint:SetText(T["Triggers higher in the list take priority. Gear is never swapped in combat, while dead or while casting: the switch waits until it can happen."])

  editor.placeholder = triggerPanel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  editor.placeholder:SetPoint("TOPLEFT", editor, "TOPLEFT", 0, -30)
  editor.placeholder:SetPoint("TOPRIGHT", editor, "TOPRIGHT", 0, -30)
  editor.placeholder:SetText(T["Select a trigger to edit it."])

  local function RefreshTriggerRows()
    cbAuto:SetChecked(C.equipmentmanager.autoswitch == "1")

    local entries = {}
    for index, t in ipairs(db.triggers) do
      table.insert(entries, { trigger = t, index = index })
    end
    triggerList.ScrollBox:SetDataProvider(CreateDataProvider(entries), ScrollBoxConstants.RetainScrollPosition)
    triggerList.empty:SetShown(table.getn(entries) == 0)
  end

  function RefreshTriggerPanel()
    if not triggerPanel:IsShown() then return end
    RefreshTriggerRows()

    local num = table.getn(db.triggers)
    local t = SelectedTrigger()
    if not t then
      editor:Hide()
      editor.placeholder:SetShown(num > 0)
      return
    end
    editor:Show()
    editor.placeholder:Hide()

    ddType:GenerateMenu()

    local info = TRIGGER_TYPE[t.type]
    local kind = info and info.value
    valueLabel:SetShown(kind ~= nil)
    ddValue:SetShown(kind == "list")
    editValue:SetShown(kind == "text")
    btnCurrentZone:SetShown(t.type == "zone")
    if kind == "list" then
      ddValue:GenerateMenu()
    elseif kind == "text" then
      editValue:ClearAllPoints()
      editValue:SetPoint("TOPLEFT", editor, "TOPRIGHT", -190, EDITOR_ROW_Y[2])
      if t.type == "zone" then
        editValue:SetPoint("BOTTOMRIGHT", btnCurrentZone, "BOTTOMLEFT", -4, 0)
      else
        editValue:SetPoint("BOTTOMRIGHT", editor, "TOPRIGHT", 0, EDITOR_ROW_Y[2] - 20)
      end
      if not editValue.hasFocus then
        editValue.updating = true
        editValue:SetText(t.value or "")
        editValue.updating = nil
      end
      local valid = t.type ~= "time" or ParseTimeWindow(t.value)
      editValue:SetTextColor(1, valid and 1 or .3, valid and 1 or .3)
    end

    local hasSets = table.getn(GetVisibleSetIDs()) > 0
    ddSet:SetShown(hasSets)
    editor.noSets:SetShown(not hasSets)
    ddSet:GenerateMenu()
    ddLeave:GenerateMenu()
  end

  triggerPanel:SetScript("OnShow", function() RefreshTriggerPanel() end)
  -- Row colors show which conditions currently hold; keep them live.
  triggerPanel:SetScript("OnUpdate", function()
    this.elapsed = (this.elapsed or 0) + (arg1 or 0)
    if this.elapsed < 1 then return end
    this.elapsed = 0
    RefreshTriggerRows()
  end)
  triggerPanel:SetScript("OnHide", function()
    editValue:ClearFocus()
  end)

  -- ============================================================
  -- Sidecar buttons that open the panels
  -- ============================================================

  local btnUnused = CreateFrame("Button", "pfEqMgrUnused", frame, "UIPanelButtonTemplate")
  btnUnused:SetSize(86, 22)
  btnUnused:SetPoint("TOPLEFT", listFrame, "BOTTOMLEFT", 0, -8)
  btnUnused:SetText(T["Unused"])
  SkinButton(btnUnused)
  btnUnused:SetScript("OnClick", function() ToggleSubPanel(unusedPanel) end)
  btnUnused:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:SetText(T["Items Not In Any Set"], 1, 1, 1)
    GameTooltip:AddLine(T["Equippable items in your bags, bank and paperdoll that no equipment set uses."], .8, .8, .8, 1)
    GameTooltip:Show()
  end)
  btnUnused:SetScript("OnLeave", function() GameTooltip:Hide() end)

  local btnTriggers = CreateFrame("Button", "pfEqMgrTriggers", frame, "UIPanelButtonTemplate")
  btnTriggers:SetSize(86, 22)
  btnTriggers:SetPoint("LEFT", btnUnused, "RIGHT", 6, 0)
  btnTriggers:SetText(T["Triggers"])
  SkinButton(btnTriggers)
  btnTriggers:SetScript("OnClick", function() ToggleSubPanel(triggerPanel) end)
  btnTriggers:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:SetText(T["Automatic Set Switching"], 1, 1, 1)
    GameTooltip:AddLine(T["Equip sets automatically when mounted, swimming, eating, in a zone, at a given time and more."], .8, .8, .8, 1)
    GameTooltip:Show()
  end)
  btnTriggers:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- Called at the end of every Refresh().
  function pfUI.equipmentmanager.RefreshExtras()
    local list = ScanUnusedItems()
    btnUnused:SetText(T["Unused"] .. " (" .. table.getn(list) .. ")")
    if unusedPanel:IsShown() then RefreshUnusedPanel() end
    if triggerPanel:IsShown() then RefreshTriggerPanel() end
  end

  -- pfUI GUI hook (U["equipmentmanager"]).
  function pfUI.equipmentmanager.UpdateConfig()
    UpdateEngine()
    if frame:IsShown() then pfUI.equipmentmanager.Refresh() end
  end

  UpdateEngine()

  -- ============================================================
  -- Events
  -- ============================================================

  local function RefreshShown()
    if not frame:IsShown() then return end
    pfUI.equipmentmanager.Refresh()
  end

  for _, event in ipairs({ "EQUIPMENT_SETS_CHANGED", "EQUIPMENT_SWAP_FINISHED", "EQUIPMENT_SWAP_PENDING",
      "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED" }) do
    pfUI.events:RegisterFrameEventAndCallback(event, RefreshShown)
  end

end)
