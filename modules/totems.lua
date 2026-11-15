pfUI:RegisterModule("totems", function ()
  local backdrop_highlight = { edgeFile = pfUI.media["img:glow"], edgeSize = 8 }

  local slotColors = {
    [FIRE_TOTEM_SLOT]  = CreateColor(.5, .2, .1),
    [EARTH_TOTEM_SLOT] = CreateColor(.2, .4, .1),
    [WATER_TOTEM_SLOT] = CreateColor(.1, .4, .6),
    [AIR_TOTEM_SLOT]   = CreateColor(.4, .1, .7),
  }

  -- the config key that remembers the chosen totem of each element
  local slotKeys = {
    [FIRE_TOTEM_SLOT]  = "fire",
    [EARTH_TOTEM_SLOT] = "earth",
    [WATER_TOTEM_SLOT] = "water",
    [AIR_TOTEM_SLOT]   = "air",
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
  _G.BINDING_NAME_PFTOTEM1 = T["Fire Totem"]
  _G.BINDING_NAME_PFTOTEM2 = T["Earth Totem"]
  _G.BINDING_NAME_PFTOTEM3 = T["Water Totem"]
  _G.BINDING_NAME_PFTOTEM4 = T["Air Totem"]
  _G.BINDING_NAME_PFTOTEMRECALL = T["Totemic Recall"]

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
    local byName = {}
    local recall

    local index = 1
    local info = C_SpellBook.GetSpellBookItemInfo(index, Enum.SpellBookSpellBank.Player)
    while info do
      local kind = not info.isPassive and GetTotemEffect(info.spellID)
      if kind then
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
    self.recall = recall
  end

  -- the chosen totem of an element, or its first one when none is chosen
  totems.GetChoice = function(self, slot)
    local choice = C.totems[slotKeys[slot]]
    for _, entry in ipairs(self.known[slot]) do
      if entry.name == choice then return entry end
    end
    return self.known[slot][1]
  end

  totems.SetChoice = function(self, slot, entry)
    C.totems[slotKeys[slot]] = entry.name
    self:Refresh()
  end

  -- [ casting ]
  totems.CastElement = function(self, slot)
    local choice = self:GetChoice(slot)
    if choice then CastSpellByID(choice.spellID) end
  end

  totems.Recall = function(self)
    if self.recall then CastSpellByID(self.recall.spellID) end
  end

  -- An element needs its chosen totem when its slot is empty or holds another
  -- totem, the totem tool is there to drop it, and it is off cooldown.
  local function NeedsChoice(slot, choice)
    local haveTool, _, start, _, _, _, spellID = GetTotemInfo(slot)
    if start > 0 then
      if C_Spell.GetSpellName(spellID) == choice.name then return end
    elseif not haveTool then
      return
    end

    local cooldown = C_Spell.GetSpellCooldown(choice.spellID)
    return cooldown.duration == 0 or cooldown.isOnGCD
  end

  -- Drops the first chosen totem, in bar order, that is not down yet. Each
  -- press drops one, so pressing it over and over drops the whole set.
  totems.DropSet = function(self)
    for _, slot in ipairs(SHAMAN_TOTEM_PRIORITIES) do
      local choice = self:GetChoice(slot)
      if choice and NeedsChoice(slot, choice) then
        CastSpellByID(choice.spellID)
        return
      end
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

  -- [ element buttons ]
  local function ElementEnter(self)
    local slot = self:GetID()
    local choice = totems:GetChoice(slot)
    local spellID = select(7, GetTotemInfo(slot))
    local active = spellID and spellID > 0

    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetSpellByID(active and spellID or choice.spellID)
    AddHint(T["Left Click"], choice.name)
    if active then AddHint(T["Right Click"], T["Target Totem"]) end
    GameTooltip:Show()

    if table.getn(totems.known[slot]) > 1 then
      self.flyout:Show()
    end
  end

  local function ElementLeave(self)
    GameTooltip:Hide()
    CheckFlyout(self.flyout)
  end

  local function ElementClick(self, button)
    local slot = self:GetID()
    if button == "LeftButton" then
      totems:CastElement(slot)
    elseif button == "RightButton" then
      TargetTotem(slot)
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

  -- [ flyout entries ]
  local function EntryEnter(self)
    self.highlight:Show()
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetSpellByID(self.totem.spellID)
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
  -- Totemic Recall follows, dimmed while no totem is down.
  totems.Refresh = function(self)
    local shown = {}
    local anyActive

    for _, slot in ipairs(SHAMAN_TOTEM_PRIORITIES) do
      local button = self.buttons[slot]
      local choice = self:GetChoice(slot)
      local haveTool, _, start, duration, icon = GetTotemInfo(slot)
      local active = start > 0 and icon and icon ~= ""
      anyActive = anyActive or active

      if choice and (active or not self.onlyactive) then
        if active then
          button.icon:SetTexture(icon)
          button.icon:SetVertexColor(1, 1, 1)
          CooldownFrame_SetTimer(button.cd, start, duration, 1)
        else
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

    local count = table.getn(shown)
    if count == 0 then
      self:Hide()
      return
    end

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

  totems.UpdateConfig = function(self)
    self.iconsize = tonumber(C.totems.iconsize)
    self.direction = C.totems.direction
    self.flyoutdir = C.totems.flyout
    self.onlyactive = C.totems.onlyactive == "1"
    self.spacing = tonumber(C.totems.spacing) * GetPerfectPixel()

    for slot = 1, MAX_TOTEMS do
      local button = self.buttons[slot] or CreateElement(slot)
      self.buttons[slot] = button
      button:SetSize(self.iconsize, self.iconsize)
      button.cdbg:SetSize(self.iconsize - 3, self.iconsize - 3)
      UpdateKeybindFont(button)
      for _, entry in ipairs(button.flyout.entries) do
        UpdateKeybindFont(entry)
      end
    end

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

  pfUI.events:RegisterFrameEventAndCallback("SPELLS_CHANGED", function() totems:UpdateList() end)
  pfUI.events:RegisterFrameEventAndCallback("SPELL_UPDATE_COOLDOWN", function() totems:UpdateCooldowns() end)
  pfUI.events:RegisterFrameEventAndCallback("UPDATE_BINDINGS", function() totems:UpdateBindings() end)
  pfUI.events:RegisterFrameEventAndCallback("PLAYER_TOTEM_UPDATE", function() totems:Refresh() end)
  pfUI.events:RegisterFrameEventAndCallback("PLAYER_ENTERING_WORLD", function() totems:Refresh() end)
  pfUI.events:RegisterFrameEventAndCallback("BAG_UPDATE_DELAYED", function() totems:Refresh() end)

  -- add totems to the pfUI global space
  pfUI.totems = totems
  pfUI.totems:UpdateConfig()
end)
