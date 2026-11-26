pfUI:RegisterModule("totems", function ()
  local backdrop_highlight = { edgeFile = pfUI.media["img:glow"], edgeSize = 8 }

  local slotColors = {
    [FIRE_TOTEM_SLOT]  = CreateColor(.5, .2, .1),
    [EARTH_TOTEM_SLOT] = CreateColor(.2, .4, .1),
    [WATER_TOTEM_SLOT] = CreateColor(.1, .4, .6),
    [AIR_TOTEM_SLOT]   = CreateColor(.4, .1, .7),
  }

  -- flyout direction -> the flyout's point on the element button, the
  -- button's point it attaches to, and the step direction of its entries
  local flyoutAnchors = {
    TOP    = { "BOTTOM", "TOP",     0,  1 },
    BOTTOM = { "TOP",    "BOTTOM",  0, -1 },
    LEFT   = { "RIGHT",  "LEFT",   -1,  0 },
    RIGHT  = { "LEFT",   "RIGHT",   1,  0 },
  }

  -- the key bindings of Bindings.xml
  _G.BINDING_HEADER_PFTOTEMS = T["Totem Bar"]
  _G.BINDING_NAME_PFTOTEMDROP = T["Drop Totem Set"]
  _G.BINDING_NAME_PFTOTEMRECALL = T["Totemic Recall"]
  _G.BINDING_NAME_PFTOTEMSETNEXT = T["Next Totem Set"]
  _G.BINDING_NAME_PFTOTEMSETPREV = T["Previous Totem Set"]

  -- the elements take the localized names of their totem tools
  local totemTools = {
    [FIRE_TOTEM_SLOT]  = 5176, -- Fire Totem
    [EARTH_TOTEM_SLOT] = 5175, -- Earth Totem
    [WATER_TOTEM_SLOT] = 5177, -- Water Totem
    [AIR_TOTEM_SLOT]   = 5178, -- Air Totem
  }

  for slot, itemID in pairs(totemTools) do
    local item = Item:CreateFromItemID(itemID)
    item:ContinueOnItemLoad(function()
      _G["BINDING_NAME_PFTOTEM" .. slot] = item:GetItemName()
    end)
  end

  local SPELL_EFFECT_SUMMON_TOTEM_SLOT1 = 87
  local SPELL_EFFECT_SUMMON_TOTEM_SLOT4 = 90
  local SPELL_EFFECT_DESTROY_ALL_TOTEMS = 110

  -- Reads what a spell does to totems: the element slot it summons a totem
  -- into (the summon effects follow the slot order), or "recall" for a spell
  -- that destroys all totems.
  local function GetTotemEffect(spellID)
    local effects = C_Spell.GetSpellEffectInfo(spellID)
    if not effects then return end
    for i = 1, 3 do
      local effect = effects[i].effect
      if effect >= SPELL_EFFECT_SUMMON_TOTEM_SLOT1 and effect <= SPELL_EFFECT_SUMMON_TOTEM_SLOT4 then
        return effect - SPELL_EFFECT_SUMMON_TOTEM_SLOT1 + 1
      elseif effect == SPELL_EFFECT_DESTROY_ALL_TOTEMS then
        return "recall"
      end
    end
  end

  local totems = CreateFrame("Frame", "pfTotems", UIParent)
  totems.known = { {}, {}, {}, {} }
  totems.buttons = {}

  -- Collects the totems of the spellbook by element, one entry per totem,
  -- and the spell that recalls them. The ranks of a spell follow each other
  -- in rising order, so the last one seen is the highest.
  totems.ScanSpellbook = function(self)
    local known = { {}, {}, {}, {} }
    local kinds = {}
    local byName = {}
    local recall

    local index = 1
    local info = C_SpellBook.GetSpellBookItemInfo(index, Enum.SpellBookSpellBank.Player)
    while info do
      local kind = not info.isPassive and GetTotemEffect(info.spellID)
      if kind then
        kinds[info.spellID] = kind
        local entry = byName[info.name]
        if entry then
          entry.spellID = info.spellID
        else
          entry = { name = info.name, spellID = info.spellID, icon = info.iconID }
          byName[info.name] = entry
          if kind == "recall" then
            recall = entry
          else
            table.insert(known[kind], entry)
          end
        end
      end

      index = index + 1
      info = C_SpellBook.GetSpellBookItemInfo(index, Enum.SpellBookSpellBank.Player)
    end

    self.known = known
    self.kinds = kinds
    self.recall = recall
  end

  -- [ totem sets ]
  -- Per character: named sets that each choose one totem per element slot,
  -- by name so a new rank takes its place, and the index of the active set.
  _G.pfUI_totems = _G.pfUI_totems or {}
  local db = _G.pfUI_totems
  db.sets = db.sets or { { name = T["Default"], totems = {} } }
  db.active = db.active or 1

  totems.GetSet = function(self)
    return db.sets[db.active]
  end

  -- the chosen totem of an element, or its first one when none is chosen
  totems.GetChoice = function(self, slot)
    local choice = db.sets[db.active].totems[slot]
    for _, entry in ipairs(self.known[slot]) do
      if entry.name == choice then return entry end
    end
    return self.known[slot][1]
  end

  totems.SetChoice = function(self, slot, entry)
    db.sets[db.active].totems[slot] = entry.name
    self:Refresh()
  end

  totems.SelectSet = function(self, index)
    db.active = index
    self:Refresh()
  end

  totems.CycleSet = function(self, delta)
    local count = table.getn(db.sets)
    self:SelectSet((db.active - 1 + delta) % count + 1)
  end

  -- a new set with the choices of the active one, which it becomes
  totems.NewSet = function(self, name)
    local choices = {}
    for slot = 1, MAX_TOTEMS do
      local choice = self:GetChoice(slot)
      choices[slot] = choice and choice.name
    end
    table.insert(db.sets, { name = name, totems = choices })
    self:SelectSet(table.getn(db.sets))
  end

  totems.RenameSet = function(self, name)
    db.sets[db.active].name = name
    self:Refresh()
  end

  -- the last set is kept
  totems.DeleteSet = function(self)
    if table.getn(db.sets) < 2 then return end
    table.remove(db.sets, db.active)
    self:SelectSet(math.min(db.active, table.getn(db.sets)))
  end

  local function FindSet(name)
    name = name:lower()
    for index, set in ipairs(db.sets) do
      if set.name:lower() == name then return index end
    end
  end

  -- /totemset <name> switches to a set, so a macro can bind each one
  _G.SLASH_PFTOTEMSET1 = "/totemset"
  SlashCmdList.PFTOTEMSET = function(msg)
    local index = FindSet(strtrim(msg))
    if index then
      totems:SelectSet(index)
    else
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpf|cffffffffUI|r: " .. T["No totem set named"] .. " " .. msg)
    end
  end

  -- [ casting ]
  totems.CastElement = function(self, slot)
    local choice = self:GetChoice(slot)
    if choice then CastSpellByID(choice.spellID) end
  end

  totems.Recall = function(self)
    if self.recall then CastSpellByID(self.recall.spellID) end
  end

  local function IsChoiceDown(slot, choice)
    local _, _, start, _, _, _, spellID = GetTotemInfo(slot)
    return start > 0 and C_Spell.GetSpellName(spellID) == choice.name
  end

  -- An element needs its chosen totem when its slot is empty or holds another
  -- totem, the totem tool is there to drop it, and it is off cooldown.
  local function NeedsChoice(slot, choice)
    local haveTool, _, start = GetTotemInfo(slot)
    if IsChoiceDown(slot, choice) or (start == 0 and not haveTool) then return end

    local cooldown = C_Spell.GetSpellCooldown(choice.spellID)
    return cooldown.duration == 0 or cooldown.isOnGCD
  end

  -- Drops the chosen totems, in bar order, that are not down yet. Most totems
  -- share a cooldown with their element only, not the global cooldown, so
  -- nampower queues them all at once and casts them one after another.
  -- Without it each press drops one, as the client takes one cast at a time.
  totems.DropSet = function(self)
    for _, slot in ipairs(self.order) do
      local choice = self:GetChoice(slot)
      if choice and NeedsChoice(slot, choice) then
        if not HasNampower() then
          CastSpellByID(choice.spellID)
          return
        end
        QueueSpellByName(choice.name)
      end
    end
  end

  -- [ group coverage ]
  -- The buff of a totem has the totem's icon and names the totem's owner as
  -- its caster, so a unit with a buff of that icon that you cast has the
  -- buff of your totem.
  local playerGUID -- known once in the world
  local groupUnits = { "player", "party1", "party2", "party3", "party4" }
  local unitBuffs = {} -- unit -> [icon] = true
  for _, unit in ipairs(groupUnits) do unitBuffs[unit] = {} end

  local function ScanUnit(unit)
    local icons = unitBuffs[unit]
    for icon in pairs(icons) do icons[icon] = nil end

    local index = 1
    local aura = C_UnitAuras.GetAuraDataByIndex(unit, index, "HELPFUL")
    while aura do
      if aura.sourceGUID == playerGUID then icons[aura.icon] = true end
      index = index + 1
      aura = C_UnitAuras.GetAuraDataByIndex(unit, index, "HELPFUL")
    end
  end

  -- Shows how far the buff of each totem reaches: the element greys out
  -- while you lack it, and in a group a badge counts who has it. Only once
  -- a totem's buff was seen, as many totems have none.
  totems.UpdateCoverage = function(self)
    for _, button in pairs(self.buttons) do
      local icon = button.totemIcon
      local covered, members, inRange = 0, 0

      if icon then
        for _, unit in ipairs(groupUnits) do
          if UnitExists(unit) then
            members = members + 1
            if unitBuffs[unit][icon] then covered = covered + 1 end
          end
        end
        inRange = unitBuffs.player[icon]
        if covered > 0 then button.buffSeen = true end
      end

      local tracked = icon and button.buffSeen
      button.icon:SetDesaturated(tracked and not inRange)

      if tracked and members > 1 then
        local color = covered == members and GREEN_FONT_COLOR
          or covered == 0 and RED_FONT_COLOR or YELLOW_FONT_COLOR
        button.coverage:SetText(covered .. "/" .. members)
        button.coverage:SetTextColor(color:GetRGB())
      else
        button.coverage:SetText("")
      end
    end
  end

  -- the group members without the buff of an element's totem
  local function AddMissing(button)
    if not button.totemIcon or not button.buffSeen then return end

    local missing
    for _, unit in ipairs(groupUnits) do
      if UnitExists(unit) and not unitBuffs[unit][button.totemIcon] then
        missing = (missing and missing .. ", " or "") .. UnitName(unit)
      end
    end

    if missing then
      GameTooltip:AddLine(T["Missing"] .. ": " .. missing, RED_FONT_COLOR:GetRGB())
    end
  end

  -- [ tooltips ]
  local function AddHint(button, action)
    GameTooltip:AddDoubleLine(button, action, nil, nil, nil, WHITE_FONT_COLOR:GetRGB())
  end

  local function CheckFlyout(flyout)
    if not MouseIsOverHitRect(flyout.button) and not flyout:IsMouseOver() then
      flyout:Hide()
    end
  end

  -- [ alerts ]
  -- The alert border of an element pulses in a color, or stops with nil.
  local function SetAlert(button, r, g, b)
    if r then
      button.alert:SetBackdropBorderColor(r, g, b, 1)
      if not button.alert:IsShown() then
        button.alert:Show()
        button.alert.pulse:Play()
      end
    elseif button.alert:IsShown() then
      button.alert.pulse:Stop()
      button.alert:Hide()
    end
  end

  -- Warns in white once the totem of an element, which ends at 'expires',
  -- has the configured seconds left. nil stops the warning, unless the
  -- element is showing that its totem was killed.
  local function WatchExpiry(button, expires)
    if button.expires == expires then return end
    button.expires = expires

    if button.expiring then
      button.expiring:Cancel()
      button.expiring = nil
    end

    if not expires then
      if not button.killed then SetAlert(button) end
      return
    end

    if button.killed then
      button.killed:Cancel()
      button.killed = nil
    end
    SetAlert(button)

    local warn = totems.expirywarn
    if warn <= 0 then return end

    local delay = expires - warn - GetTime()
    if delay <= 0 then
      SetAlert(button, 1, 1, 1)
    else
      button.expiring = C_Timer.NewTimer(delay, function()
        button.expiring = nil
        SetAlert(button, 1, 1, 1)
      end)
    end
  end

  -- An element whose totem was killed pulses red for a few seconds.
  totems.Killed = function(self, slot, name, killer)
    local button = self.buttons[slot]
    WatchExpiry(button, nil)
    SetAlert(button, 1, .2, .2)

    if button.killed then button.killed:Cancel() end
    button.killed = C_Timer.NewTimer(3, function()
      button.killed = nil
      SetAlert(button)
    end)

    if C.totems.killalert == "1" then
      local text = killer and string.format(T["%s was killed by %s"], name, killer)
        or string.format(T["%s was killed"], name)
      UIErrorsFrame:AddMessage(text, 1, .3, .3)
    end
  end

  -- [ element buttons ]
  local function ElementEnter(self)
    local slot = self:GetID()
    local choice = totems:GetChoice(slot)
    local spellID = select(7, GetTotemInfo(slot))
    local active = spellID and spellID > 0

    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetSpellByID(active and spellID or choice.spellID, false, true)
    AddHint(T["Left Click"], choice.name)
    if active then AddHint(T["Right Click"], T["Target Totem"]) end
    AddHint(T["Shift-Drag"], T["Move Totem"])
    AddMissing(self)
    GameTooltip:Show()

    if table.getn(totems.known[slot]) > 1 then
      self.flyout:Show()
    end
  end

  local function ElementLeave(self)
    GameTooltip:Hide()
    CheckFlyout(self.flyout)
  end

  -- the health events of the element's own totem only
  local function ElementEvent(self)
    totems:UpdateHealth(self:GetID())
  end

  local function ElementClick(self, button)
    local slot = self:GetID()
    if button == "LeftButton" then
      totems:CastElement(slot)
    elseif button == "RightButton" then
      TargetTotem(slot)
    end
  end

  -- Shift-drag an element onto another to swap their places on the bar.
  local function ElementDragStart(self)
    if not IsShiftKeyDown() then return end
    totems.dragging = self
    self:SetAlpha(.5)
    GameTooltip:Hide()
    self.flyout:Hide()
  end

  local function ElementDragStop(self)
    if totems.dragging ~= self then return end
    totems.dragging = nil
    self:SetAlpha(1)
    for _, target in pairs(totems.buttons) do
      if target ~= self and target:IsVisible() and MouseIsOverHitRect(target) then
        totems:SwapElements(self:GetID(), target:GetID())
        return
      end
    end
  end

  -- [ recall button ]
  local function RecallEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetSpellByID(totems.recall.spellID)
    GameTooltip:Show()
  end

  local function RecallClick()
    totems:Recall()
  end

  -- [ set button ]
  local function NameSet(mode, name)
    name = strtrim(name)
    if name == "" then return end
    if mode == "rename" then totems:RenameSet(name) else totems:NewSet(name) end
  end

  StaticPopupDialogs["PFUI_TOTEM_SET_NAME"] = {
    text = T["Totem Set Name"],
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = 1,
    maxLetters = 32,
    OnAccept = function(mode)
      NameSet(mode, _G[this:GetParent():GetName() .. "EditBox"]:GetText())
    end,
    EditBoxOnEnterPressed = function(mode)
      NameSet(mode, this:GetText())
      this:GetParent():Hide()
    end,
    EditBoxOnEscapePressed = function() this:GetParent():Hide() end,
    timeout = 0, whileDead = 1, hideOnEscape = 1,
  }

  -- 'mode' is "new" or "rename"
  local function OpenNamePopup(mode)
    local dialog = StaticPopup_Show("PFUI_TOTEM_SET_NAME", nil, nil, mode)
    if not dialog then return end
    local editbox = _G[dialog:GetName() .. "EditBox"]
    editbox:SetText(mode == "rename" and totems:GetSet().name or "")
    editbox:HighlightText()
    editbox:SetFocus()
  end

  local function IsActiveSet(index)
    return db.active == index
  end

  local function SelectSet(index)
    totems:SelectSet(index)
  end

  local function DeleteSet()
    totems:DeleteSet()
  end

  local function GenerateSetMenu(owner, rootDescription)
    rootDescription:CreateTitle(T["Totem Sets"])
    for index, set in ipairs(db.sets) do
      rootDescription:CreateRadio(set.name, IsActiveSet, SelectSet, index)
    end
    CreateMenuDivider(rootDescription)
    rootDescription:CreateButton(T["New Set"], OpenNamePopup, "new")
    rootDescription:CreateButton(T["Rename Set"], OpenNamePopup, "rename")
    rootDescription:CreateButton(T["Delete Set"], DeleteSet):SetEnabled(table.getn(db.sets) > 1)
  end

  -- the set's name and its totems, bright when down
  local function SetEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(totems:GetSet().name)
    for _, slot in ipairs(totems.order) do
      local choice = totems:GetChoice(slot)
      if choice then
        local icon = CreateTextureMarkup(choice.icon, 64, 64, 14, 14, .08, .92, .08, .92)
        local color = IsChoiceDown(slot, choice) and HIGHLIGHT_FONT_COLOR or GRAY_FONT_COLOR
        GameTooltip:AddLine(icon .. " " .. choice.name, color:GetRGB())
      end
    end
    AddHint(T["Left Click"], T["Drop Totem Set"])
    AddHint(T["Right Click"], T["Totem Sets"])
    AddHint(T["Mouse Wheel"], T["Switch Totem Set"])
    GameTooltip:Show()
  end

  local function SetClick(self, button)
    if button == "LeftButton" then
      totems:DropSet()
    elseif button == "RightButton" then
      GameTooltip:Hide()
      MenuUtil.CreateContextMenu(self, GenerateSetMenu)
    end
  end

  local function SetWheel(self, delta)
    totems:CycleSet(-delta)
    SetEnter(self)
  end

  -- [ flyout entries ]
  local function EntryEnter(self)
    self.highlight:Show()
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetSpellByID(self.totem.spellID, false, true)
    AddHint(T["Left Click"], T["Cast and choose"])
    AddHint(T["Right Click"], T["Choose"])
    GameTooltip:Show()
  end

  local function EntryLeave(self)
    self.highlight:Hide()
    GameTooltip:Hide()
    CheckFlyout(self.flyout)
  end

  local function EntryClick(self, button)
    local flyout = self.flyout
    totems:SetChoice(flyout.button:GetID(), self.totem)
    if button == "LeftButton" then
      CastSpellByID(self.totem.spellID)
      flyout:Hide()
    end
  end

  local function FlyoutLeave(self)
    CheckFlyout(self)
  end

  -- An icon button with its key text above the cooldown. Hoverbind binds keys
  -- to its 'bindcommand'.
  local function CreateIconButton(name, parent, bindcommand)
    local button = CreateFrame("Button", name, parent)
    CreateBackdrop(button, nil, true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button.bindcommand = bindcommand

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetTexCoord(.08, .92, .08, .92)
    SetAllPointsOffset(button.icon, button, 2, -2)

    button.overlay = CreateFrame("Frame", nil, button)
    button.overlay:SetAllPoints()
    button.overlay:SetFrameLevel(button:GetFrameLevel() + 3)

    button.keybind = button.overlay:CreateFontString(nil, "OVERLAY")
    button.keybind:SetJustifyH("RIGHT")
    button.keybind:SetJustifyV("TOP")
    button.keybind:SetNonSpaceWrap(false)

    if pfUI.hoverbind then pfUI.hoverbind:Register(button) end
    return button
  end

  local function UpdateKeybindFont(button)
    local offset = tonumber(C.bars.font_offset)
    SetAllPointsOffset(button.keybind, button, offset, -offset)
    button.keybind:SetFont(pfUI.media[C.bars.font], tonumber(C.bars.bind_size), "OUTLINE")
    button.keybind:SetTextColor(GetStringColor(C.bars.bind_color))
  end

  local function CreateEntry(flyout)
    local entry = CreateIconButton(nil, flyout)
    entry.flyout = flyout
    entry.cd = CreateCooldown(entry, "spell", C.bars, "timers")
    UpdateKeybindFont(entry)

    entry.highlight = CreateFrame("Frame", nil, entry)
    entry.highlight:SetBackdrop(backdrop_highlight)
    entry.highlight:SetBackdropBorderColor(1, 1, 1, .8)
    entry.highlight:SetAllPoints()
    entry.highlight:Hide()

    entry.chosen = CreateFrame("Frame", nil, entry)
    entry.chosen:SetBackdrop(backdrop_highlight)
    entry.chosen:SetAllPoints()
    entry.chosen:Hide()

    entry:SetScript("OnEnter", EntryEnter)
    entry:SetScript("OnLeave", EntryLeave)
    entry:SetScript("OnClick", EntryClick)
    return entry
  end

  local function CreateElement(slot)
    local button = CreateIconButton("pfTotemsBar" .. slot, totems, "PFTOTEM" .. slot)
    button:SetID(slot)
    button:SetBackdropBorderColor(slotColors[slot]:GetRGB())

    button.cdbg = CreateFrame("Frame", nil, button)
    button.cdbg:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.cd = CreateCooldown(button.cdbg, "aura", C.totems, "timers", "pfTotemsBar" .. slot .. "Cooldown")
    button.spellcd = CreateCooldown(button.cdbg, "spell", C.bars, "timers", "pfTotemsBar" .. slot .. "SpellCooldown")

    button.health = CreateFrame("StatusBar", nil, button)
    button.health:SetFrameLevel(button:GetFrameLevel() + 2)
    button.health:SetStatusBarTexture(pfUI.media["img:bar"])
    button.health:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 2, 2)
    button.health:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
    button.health:SetHeight(3)
    button.health:Hide()
    FrameUtil.RegisterFrameForUnitEvents(button, { "UNIT_HEALTH", "UNIT_MAXHEALTH" }, "totem" .. slot)
    button:SetScript("OnEvent", ElementEvent)

    button.coverage = button.overlay:CreateFontString(nil, "OVERLAY")
    button.coverage:SetJustifyH("RIGHT")
    button.coverage:SetJustifyV("BOTTOM")

    button.alert = CreateFrame("Frame", nil, button)
    button.alert:SetBackdrop(backdrop_highlight)
    button.alert:SetAllPoints()
    button.alert:Hide()
    button.alert.pulse = button.alert:CreateAnimationGroup()
    button.alert.pulse:SetLooping("BOUNCE")
    local fade = button.alert.pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(.3)
    fade:SetDuration(.5)
    fade:SetSmoothing("IN_OUT")

    -- mouse-enabled so the gaps between entries keep it open
    button.flyout = CreateFrame("Frame", nil, button)
    button.flyout:EnableMouse(true)
    button.flyout:SetFrameLevel(button:GetFrameLevel() + 5)
    button.flyout:Hide()
    button.flyout.button = button
    button.flyout.entries = {}
    button.flyout:SetScript("OnLeave", FlyoutLeave)

    button:SetScript("OnEnter", ElementEnter)
    button:SetScript("OnLeave", ElementLeave)
    button:SetScript("OnClick", ElementClick)
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", ElementDragStart)
    button:SetScript("OnDragStop", ElementDragStop)
    return button
  end

  -- the set button shows the set's four totems in a square
  local function CreateSetButton()
    local button = CreateIconButton("pfTotemsSet", totems, "PFTOTEMDROP")
    button.menuMixin = pfUIMenuStyleMixin
    button.icon:Hide()
    button.totems = {}
    for slot = 1, MAX_TOTEMS do
      button.totems[slot] = button:CreateTexture(nil, "ARTWORK")
      button.totems[slot]:SetTexCoord(.08, .92, .08, .92)
    end

    button:EnableMouseWheel(true)
    button:SetScript("OnEnter", SetEnter)
    button:SetScript("OnLeave", GameTooltip_Hide)
    button:SetScript("OnClick", SetClick)
    button:SetScript("OnMouseWheel", SetWheel)
    return button
  end

  local function CreateRecall()
    local button = CreateIconButton("pfTotemsRecall", totems, "PFTOTEMRECALL")
    button:SetScript("OnEnter", RecallEnter)
    button:SetScript("OnLeave", GameTooltip_Hide)
    button:SetScript("OnClick", RecallClick)
    return button
  end

  -- Lays out the flyout of an element: one entry per known totem, leading
  -- away from the button in the configured direction.
  local function LayoutFlyout(button, list)
    local flyout = button.flyout
    local point, relative, dx, dy = unpack(flyoutAnchors[totems.flyoutdir])
    local size, gap = totems.iconsize, totems.spacing * 2
    local count = table.getn(list)

    flyout:ClearAllPoints()
    flyout:SetPoint(point, button, relative, 0, 0)

    local length = count * (size + gap)
    if dx ~= 0 then flyout:SetSize(length, size) else flyout:SetSize(size, length) end

    for i, data in ipairs(list) do
      local entry = flyout.entries[i] or CreateEntry(flyout)
      flyout.entries[i] = entry

      local offset = gap + (i - 1) * (size + gap)
      entry:ClearAllPoints()
      entry:SetPoint(point, flyout, point, dx * offset, dy * offset)
      entry:SetSize(size, size)
      entry.icon:SetTexture(data.icon)
      entry.chosen:SetBackdropBorderColor(slotColors[button:GetID()]:GetRGB())
      entry.totem = data
      entry.bindcommand = "SPELL " .. data.name
      entry:Show()
    end

    for i = count + 1, table.getn(flyout.entries) do
      flyout.entries[i]:Hide()
    end
  end

  -- An element shows the health of its totem once it took damage.
  totems.UpdateHealth = function(self, slot)
    local bar = self.buttons[slot].health
    local unit = "totem" .. slot
    local health, max = UnitHealth(unit), UnitHealthMax(unit)
    if UnitExists(unit) and health < max then
      bar:SetMinMaxValues(0, max)
      bar:SetValue(health)
      bar:SetStatusBarColor(GetColorGradient(health / max))
      bar:Show()
    else
      bar:Hide()
    end
  end

  -- the key text of every button, hidden flyout entries as well
  totems.UpdateBindings = function(self)
    for _, button in pairs(self.buttons) do
      button.keybind:SetText(GetKeybindText(button.bindcommand))
      for _, entry in ipairs(button.flyout.entries) do
        if entry.bindcommand then
          entry.keybind:SetText(GetKeybindText(entry.bindcommand))
        end
      end
    end
    self.recallbutton.keybind:SetText(GetKeybindText(self.recallbutton.bindcommand))
    self.setbutton.keybind:SetText(GetKeybindText(self.setbutton.bindcommand))
  end

  local function SetSpellCooldown(cd, spellID)
    local cooldown = C_Spell.GetSpellCooldown(spellID)
    CooldownFrame_SetTimer(cd, cooldown.startTime, cooldown.duration, 1)
  end

  -- The cooldowns of the totem spells: on every flyout entry, and on an
  -- element without a totem down, which shows the cooldown of its chosen
  -- totem in place of the totem's time left.
  totems.UpdateCooldowns = function(self)
    for slot, button in pairs(self.buttons) do
      local choice = self:GetChoice(slot)
      local start = select(3, GetTotemInfo(slot))
      if choice and start == 0 then
        SetSpellCooldown(button.spellcd, choice.spellID)
      else
        CooldownFrame_SetTimer(button.spellcd, 0, 0, 0)
      end

      for _, entry in ipairs(button.flyout.entries) do
        if entry.totem then SetSpellCooldown(entry.cd, entry.totem.spellID) end
      end
    end
  end

  -- Shows each element in its state: the active totem with its timer, or
  -- the chosen one dimmed. Red when the totem tool of the element is missing.
  -- The set button leads, Totemic Recall follows, dimmed while no totem is
  -- down.
  totems.Refresh = function(self)
    local set = self.setbutton
    local shown = { set }
    local anyActive, anyKnown

    for _, slot in ipairs(self.order) do
      local button = self.buttons[slot]
      local choice = self:GetChoice(slot)
      local haveTool, _, start, duration, icon = GetTotemInfo(slot)
      local active = start > 0 and icon and icon ~= ""
      anyActive = anyActive or active
      anyKnown = anyKnown or choice

      if choice then
        local bright = IsChoiceDown(slot, choice) and 1 or .35
        set.totems[slot]:SetTexture(choice.icon)
        set.totems[slot]:SetVertexColor(bright, bright, bright)
        set.totems[slot]:Show()
      else
        set.totems[slot]:Hide()
      end

      if choice and (active or not self.onlyactive) then
        if active then
          button.icon:SetTexture(icon)
          button.icon:SetVertexColor(1, 1, 1)
          CooldownFrame_SetTimer(button.cd, start, duration, 1)
          WatchExpiry(button, start + duration)
          if button.totemStart ~= start then
            button.totemStart = start
            button.buffSeen = nil
          end
          button.totemIcon = icon
        else
          WatchExpiry(button, nil)
          button.totemIcon = nil
          button.icon:SetTexture(choice.icon)
          if haveTool then
            button.icon:SetVertexColor(.5, .5, .5)
          else
            button.icon:SetVertexColor(1, .2, .2)
          end
          CooldownFrame_SetTimer(button.cd, 0, 0, 0)
        end

        for _, entry in ipairs(button.flyout.entries) do
          entry.chosen:SetShown(entry.totem == choice)
        end
        self:UpdateHealth(slot)

        table.insert(shown, button)
      else
        button:Hide()
      end
    end

    local recall = self.recallbutton
    if self.recall and (anyActive or not self.onlyactive) then
      recall.icon:SetTexture(self.recall.icon)
      recall.icon:SetVertexColor(anyActive and 1 or .5, anyActive and 1 or .5, anyActive and 1 or .5)
      table.insert(shown, recall)
    else
      recall:Hide()
    end

    self:UpdateCooldowns()
    self:UpdateCoverage()

    if not anyKnown then
      self:Hide()
      return
    end

    local count = table.getn(shown)

    local thickness = self.iconsize + self.spacing * 2
    for i, button in ipairs(shown) do
      local offset = self.spacing + (i - 1) * thickness
      button:ClearAllPoints()
      if self.direction == "HORIZONTAL" then
        button:SetPoint("TOPLEFT", self, "TOPLEFT", offset, -self.spacing)
      else
        button:SetPoint("TOPLEFT", self, "TOPLEFT", self.spacing, -offset)
      end
      button:Show()
    end

    local length = thickness * count
    if self.direction == "HORIZONTAL" then
      self:SetSize(length, thickness)
    else
      self:SetSize(thickness, length)
    end
    self:Show()
  end

  totems.UpdateList = function(self)
    self:ScanSpellbook()
    for slot, button in pairs(self.buttons) do
      LayoutFlyout(button, self.known[slot])
    end
    self:UpdateBindings()
    self:Refresh()
  end

  -- The elements in bar order, as the engine's slots (1 fire, 2 earth, 3
  -- water, 4 air). A value that does not name each slot once gives the
  -- engine's order.
  local function ParseOrder(value)
    local order, seen = {}, {}
    for slot in string.gfind(value or "", "%d+") do
      slot = tonumber(slot)
      if slot < 1 or slot > MAX_TOTEMS or seen[slot] then break end
      seen[slot] = true
      table.insert(order, slot)
    end
    if table.getn(order) == MAX_TOTEMS then return order end
    order = {}
    for slot = 1, MAX_TOTEMS do order[slot] = slot end
    return order
  end

  -- the set button's four totems in a square, in bar order
  totems.LayoutSetIcons = function(self)
    local half = (self.iconsize - 4) / 2
    for i, slot in ipairs(self.order) do
      local column, row = (i - 1) % 2, math.floor((i - 1) / 2)
      local texture = self.setbutton.totems[slot]
      texture:SetSize(half, half)
      texture:ClearAllPoints()
      texture:SetPoint("TOPLEFT", self.setbutton, "TOPLEFT", 2 + column * half, -2 - row * half)
    end
  end

  -- swaps two elements' places on the bar, and saves the order
  totems.SwapElements = function(self, a, b)
    local order = self.order
    local ia, ib
    for i, slot in ipairs(order) do
      if slot == a then ia = i elseif slot == b then ib = i end
    end
    order[ia], order[ib] = b, a
    C.totems.order = table.concat(order, ",")
    self:LayoutSetIcons()
    self:Refresh()
  end

  totems.UpdateConfig = function(self)
    self.order = ParseOrder(C.totems.order)
    self.iconsize = tonumber(C.totems.iconsize)
    self.direction = C.totems.direction
    self.flyoutdir = C.totems.flyout
    self.onlyactive = C.totems.onlyactive == "1"
    self.spacing = tonumber(C.totems.spacing) * GetPerfectPixel()
    self.expirywarn = tonumber(C.totems.expirywarn) or 0

    for slot = 1, MAX_TOTEMS do
      local button = self.buttons[slot] or CreateElement(slot)
      self.buttons[slot] = button
      button:SetSize(self.iconsize, self.iconsize)
      button.cdbg:SetSize(self.iconsize - 3, self.iconsize - 3)
      button.expires = 0 -- arms the expiry warning again with the new setting
      local offset = tonumber(C.bars.font_offset)
      SetAllPointsOffset(button.coverage, button, offset, -offset)
      button.coverage:SetFont(pfUI.media[C.bars.font], tonumber(C.bars.bind_size), "OUTLINE")
      UpdateKeybindFont(button)
      for _, entry in ipairs(button.flyout.entries) do
        UpdateKeybindFont(entry)
      end
    end

    self.setbutton = self.setbutton or CreateSetButton()
    self.setbutton:SetSize(self.iconsize, self.iconsize)
    UpdateKeybindFont(self.setbutton)
    self:LayoutSetIcons()

    self.recallbutton = self.recallbutton or CreateRecall()
    self.recallbutton:SetSize(self.iconsize, self.iconsize)
    UpdateKeybindFont(self.recallbutton)

    self:UpdateList()
    self:ClearAllPoints()
    self:SetPoint("BOTTOM", 0, 75)
    UpdateMovable(self, true)

    if C.totems.showbg == "1" then
      CreateBackdrop(self)
      self.backdrop:Show()
    elseif self.backdrop then
      self.backdrop:Hide()
    end
  end

  -- [ killed totems ]
  -- Every totem that goes away is logged as destroyed, so a kill is one with
  -- time left that no totem cast of yours replaced.
  local guidSlots = {} -- totem GUID -> element slot
  local attackers = {} -- element slot -> the last unit that damaged its totem
  local castAt = {}    -- element slot -> time of your last cast that replaces its totem

  local function OnCombatLog(_, _, subevent, _, sourceGUID, sourceName, _, _, destGUID, destName, _, _, spellId)
    if subevent == "SPELL_CAST_SUCCESS" and sourceGUID == playerGUID then
      local kind = totems.kinds[spellId]
      if kind == "recall" then
        for slot = 1, MAX_TOTEMS do castAt[slot] = GetTime() end
      elseif kind then
        castAt[kind] = GetTime()
      end
    end

    local slot = guidSlots[destGUID]
    if not slot then return end

    if subevent == "UNIT_DESTROYED" then
      guidSlots[destGUID] = nil
      if GetTime() - (castAt[slot] or 0) > 1 and GetTotemTimeLeft(slot) > 1 and not UnitIsDeadOrGhost("player") then
        totems:Killed(slot, destName, attackers[slot])
      end
    elseif subevent:find("_DAMAGE$") then
      attackers[slot] = sourceName
    end
  end

  pfUI.events:RegisterFrameEventAndCallback("COMBAT_LOG_EVENT_UNFILTERED", OnCombatLog)

  -- The GUID of the totem in each slot. It is kept once the slot is empty,
  -- as the totem's destroyed entry in the combat log can come later.
  local function TrackTotems()
    for slot = 1, MAX_TOTEMS do
      local guid = UnitGUID("totem" .. slot)
      if guid and not guidSlots[guid] then
        for old, oldSlot in pairs(guidSlots) do
          if oldSlot == slot then guidSlots[old] = nil end
        end
        guidSlots[guid] = slot
        attackers[slot] = nil
      end
    end
  end

  local function ScanGroup()
    playerGUID = UnitGUID("player")
    for _, unit in ipairs(groupUnits) do ScanUnit(unit) end
    totems:UpdateCoverage()
  end

  -- the auras of the group only; ClassicAPI takes more than four units
  totems:RegisterUnitEvent("UNIT_AURA", unpack(groupUnits))
  totems:SetScript("OnEvent", function(_, _, unit)
    ScanUnit(unit)
    totems:UpdateCoverage()
  end)
  pfUI.events:RegisterFrameEventAndCallback("PARTY_MEMBERS_CHANGED", ScanGroup)
  pfUI.events:RegisterFrameEventAndCallback("PLAYER_ENTERING_WORLD", ScanGroup)
  pfUI.events:RegisterFrameEventAndCallback("SPELLS_CHANGED", function() totems:UpdateList() end)
  pfUI.events:RegisterFrameEventAndCallback("SPELL_UPDATE_COOLDOWN", function() totems:UpdateCooldowns() end)
  pfUI.events:RegisterFrameEventAndCallback("UPDATE_BINDINGS", function() totems:UpdateBindings() end)
  pfUI.events:RegisterFrameEventAndCallback("PLAYER_TOTEM_UPDATE", function() TrackTotems() totems:Refresh() end)
  pfUI.events:RegisterFrameEventAndCallback("PLAYER_ENTERING_WORLD", function() TrackTotems() totems:Refresh() end)
  pfUI.events:RegisterFrameEventAndCallback("BAG_UPDATE_DELAYED", function() totems:Refresh() end)

  -- add totems to the pfUI global space
  pfUI.totems = totems
  pfUI.totems:UpdateConfig()
end)
