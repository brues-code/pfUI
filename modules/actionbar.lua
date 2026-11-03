pfUI:RegisterModule("actionbar", function ()
  local class = UnitClassBase("player")
  local _, cr, cg, cb = GetUnitColor('player')
  local er, eg, eb, ea = GetStringColor(pfUI_config.appearance.border.color)

  local backdrop_highlight = { edgeFile = pfUI.media["img:glow"], edgeSize = 8 }
  local showgrid = 0
  local showgrid_pet = 0
  local rawborder, border = GetBorderSize("actionbars")
  local bpad = rawborder > 1 and border - GetPerfectPixel() or GetPerfectPixel()

  local passcache = { } -- contains the passes over the visible buttons that shall run later -> [pass] = true
  local updatecache = { } -- contains a list of buttons slots that shall be refreshed later -> [slot] = true
  local buttoncache = { } -- contains a list of all buttons ever created -> [slot] = frame

  -- ClassicAPI's left/right modifier state, which unlike IsShiftKeyDown is
  -- corrected for keys released while the game was in the background
  local function ShiftDown() return IsLeftShiftKeyDown() or IsRightShiftKeyDown() end
  local function CtrlDown() return IsLeftControlKeyDown() or IsRightControlKeyDown() end
  local function AltDown() return IsLeftAltKeyDown() or IsRightAltKeyDown() end

  -- try to assume based on the current mouse positions if a button drag
  -- should happen even if action-on-key-down is used. By that replace the
  -- cast events by reverting the active buttons to the old mouse-up state.
  local drag_await
  local drag_active
  local function AssumeButtonDrag()
    -- skip if keydown press is not enabled
    if C.bars.keydown ~= "1" then return end

    -- skip if always shift-drag is not enabled
    if C.bars.shiftdrag ~= "1" then return end

    if drag_await and not drag_active and ShiftDown() then
      drag_active = true
      -- set all buttons to regular on release clicks
      for id, button in pairs(buttoncache) do
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
      end
    elseif drag_active and not ShiftDown() then
      drag_active = nil
      -- set all buttons back to their defaults
      for id, button in pairs(buttoncache) do
        button:RegisterForClicks("LeftButtonDown", "RightButtonDown")
      end
    end
  end
  pfUI.events:RegisterFrameEventAndCallback("MODIFIER_STATE_CHANGED", AssumeButtonDrag)

  -- hide blizzard bars
  local function kill(f, killshow)
    if f.Show and killshow then f.Show = function() return end end
    if f.UnregisterAllEvents then f:UnregisterAllEvents() end
    if f.Hide then f:Hide() end
  end

  -- the abbreviated text of the key bound to a command, mouse buttons included
  local mouse_abbrevs = {
    [_G.KEY_BUTTON3] = "MB3",
    [_G.KEY_BUTTON4] = "MB4",
    [_G.KEY_BUTTON5] = "MB5",
    [_G.KEY_MOUSEWHEELDOWN] = "MWD",
    [_G.KEY_MOUSEWHEELUP] = "MWU",
  }

  local function GetKeybindText(command)
    local text = GetBindingText(GetBindingKey(command), "KEY_", 1)
    for name, abbrev in pairs(mouse_abbrevs) do
      text = text:gsub(name, abbrev)
    end
    return text
  end

  kill(MainMenuBar)

  local blizzard_elements = { MultiBarBottomLeft,
    MultiBarBottomRight, MultiBarLeft, MultiBarRight }
  for _, f in pairs(blizzard_elements) do
    kill(f, true)
  end

  -- enable all possible actionbar pages
  SetActionBarToggles(0, 0, 0, 0)
  _G.SHOW_MULTI_ACTIONBAR_1 = nil
  _G.SHOW_MULTI_ACTIONBAR_2 = nil
  _G.SHOW_MULTI_ACTIONBAR_3 = nil
  _G.SHOW_MULTI_ACTIONBAR_4 = nil

  -- events that refresh one part of every visible button -> [event] = pass.
  -- Page changes only touch the main bar, whose pager handles them.
  local pass_events = {
    ["ACTIONBAR_UPDATE_COOLDOWN"] = "cooldown",
    -- action slots take ACTION_USABLE_CHANGED; the stance buttons still
    -- need a pass on this one
    ["ACTIONBAR_UPDATE_USABLE"] = "stance",
    ["ACTIONBAR_UPDATE_STATE"] = "state",
    -- the active border of attack, auto repeat and tradeskill actions
    ["PLAYER_ENTER_COMBAT"] = "state",
    ["PLAYER_LEAVE_COMBAT"] = "state",
    ["START_AUTOREPEAT_SPELL"] = "state",
    ["STOP_AUTOREPEAT_SPELL"] = "state",
    ["CRAFT_SHOW"] = "state",
    ["CRAFT_CLOSE"] = "state",
    ["TRADE_SKILL_SHOW"] = "state",
    ["TRADE_SKILL_CLOSE"] = "state",
    -- fires on every ammo shot / consumable use, but only counts, equipped
    -- state, cooldowns and usability can change from it
    ["UNIT_INVENTORY_CHANGED"] = "inventory",
    -- the keybind text of every button, shown or not
    ["UPDATE_BINDINGS"] = "bindings",
  }

  -- events that refresh every button
  local global_events = {
    ["PLAYER_ENTERING_WORLD"] = true,
    ["ACTIONBAR_SLOT_CHANGED"] = true,
  }

  -- events that are used for the aura/shapeshift bar
  local aura_events = {
    ["UPDATE_SHAPESHIFT_FORMS"] = true,
    ["PLAYER_AURAS_CHANGED"] = true,
  }

  -- events that are used for the pet bar
  local pet_events = {
    ["PLAYER_CONTROL_LOST"] = true,
    ["PLAYER_CONTROL_GAINED"] = true,
    ["PLAYER_FARSIGHT_FOCUS_CHANGED"] = true,
    ["UNIT_PET"] = true,
    ["PET_BAR_UPDATE"] = true,
    ["PET_BAR_UPDATE_COOLDOWN"] = true,
  }

  local buttontypes = {
    -- blizzard keybinds
    [3] = "MULTIACTIONBAR3BUTTON",
    [4] = "MULTIACTIONBAR4BUTTON",
    [5] = "MULTIACTIONBAR2BUTTON",
    [6] = "MULTIACTIONBAR1BUTTON",
    [11] = "SHAPESHIFTBUTTON",
    [12] = "BONUSACTIONBUTTON",
    -- additional keybinds
    [2] = "PFPAGING",
    [7] = "PFSTANCEONE",
    [8] = "PFSTANCETWO",
    [9] = "PFSTANCETHREE",
    [10] = "PFSTANCEFOUR",
  }

  local blizzbarmapping = {
    ["MultiBarRight"] = 3,
    ["MultiBarLeft"] = 4,
    ["MultiBarBottomRight"] = 5,
    ["MultiBarBottomLeft"] = 6,
    ["ShapeShiftBar"] = 11,
    ["BonusActionBar"] = 12,
  }

  local barnames = {
    [1] = "Main",
    [2] = "Paging",
    [3] = "Right",
    [4] = "Vertical",
    [5] = "Left",
    [6] = "Top",
    [7] = "StanceBar1",
    [8] = "StanceBar2",
    [9] = "StanceBar3",
    [10] = "StanceBar4",
    [11] = "Stances",
    [12] = "Pet",
  }

  -- Button animations scale and fade a copy of the icon through keyframes of
  -- { duration, scale, alpha, smoothing }. Styles with hideicon hide the icon
  -- while the copy plays.
  local button_animations = {
    ["zoomfade"] = {
      { .67, 2, 0, "NONE" },
    },
    ["shrinkreturn"] = { hideicon = true,
      { .13, .36, .36, "OUT" },
      { .2, 1, 1, "IN" },
    },
    ["elasticzoom"] = { hideicon = true,
      { .1, .47, .47, "OUT" },
      { .28, 1.12, 1, "IN_OUT" },
      { .28, .97, .97, "IN_OUT" },
      { .46, 1, 1, "IN_OUT" },
    },
    ["wobblezoom"] = { hideicon = true,
      { .07, .25, .25, "OUT" },
      { .17, 1.41, 1, "IN_OUT" },
      { .17, .77, .77, "IN_OUT" },
      { .17, 1.12, 1, "IN_OUT" },
      { .17, .93, .93, "IN_OUT" },
      { .17, 1.04, 1, "IN_OUT" },
      { .17, .98, .98, "IN_OUT" },
      { .59, 1, 1, "IN_OUT" },
    },
  }

  local function CreateButtonAnimation(button, style)
    local group = button.animation.tex:CreateAnimationGroup()
    group:SetIgnoreFramerateThrottle(true)

    local scale, alpha = 1, 1
    for order, key in ipairs(style) do
      local duration, nextscale, nextalpha, smoothing = unpack(key)

      local zoom = group:CreateAnimation("Scale")
      zoom:SetOrder(order)
      zoom:SetDuration(duration)
      zoom:SetSmoothing(smoothing)
      zoom:SetScale(nextscale / scale, nextscale / scale)

      local fade = group:CreateAnimation("Alpha")
      fade:SetOrder(order)
      fade:SetDuration(duration)
      fade:SetSmoothing(smoothing)
      fade:SetChange(nextalpha - alpha)

      scale, alpha = nextscale, nextalpha
    end

    local function Done()
      button.animation:Hide()
      button.icon:Show()
    end
    group:SetScript("OnFinished", Done)
    group:SetScript("OnStop", Done)

    return group
  end

  local function PlayButtonAnimation(button)
    local style = button_animations[C.bars.animation]
    if not style then return end

    local animation = button.animation
    animation.groups[style] = animation.groups[style] or CreateButtonAnimation(button, style)

    animation.tex:StopAnimating()
    animation.tex:SetTexture(button.icon:GetTexture())
    animation.tex:SetVertexColor(button.icon:GetVertexColor())
    animation:Show()
    if style.hideicon then button.icon:Hide() end
    animation.groups[style]:Play()
  end

  local function GetActiveBar()
    if CURRENT_ACTIONBAR_PAGE == 1 and GetBonusBarOffset() ~= 0 then
      return NUM_ACTIONBAR_PAGES + GetBonusBarOffset()
    else
      return CURRENT_ACTIONBAR_PAGE
    end
  end

  local function ButtonDrag(self)
    local self = self or this

    if _G.LOCK_ACTIONBAR == "1" and not (pfUI_config.bars.shiftdrag == "1" and IsShiftKeyDown()) then return end

    if self.bar == 12 then
      PickupPetAction(self.id)
    else
      PickupAction(self.id)
    end
  end

  local function ButtonDragStop(self)
    local self = self or this

    if MacroFrame_SaveMacro then
      MacroFrame_SaveMacro()
    end

    if self.bar == 12 then
      PickupPetAction(self.id)
    else
      PlaceAction(self.id)
    end
  end

  local mouse
  local function ButtonAnimate(self)
    local self = self or this
    mouse = arg1 and not keystate

    -- trigger action animation
    if ( pfUI_config.bars.keydown == "1" and keystate == "down" ) or (pfUI_config.bars.keydown == "0" and keystate == "up" ) or self.bar == 11 or mouse then
      if C.bars.animmode == "keypress" and ( self:GetAlpha() > .1  or C.bars.animalways == "1" ) then
        PlayButtonAnimation(self)
      end
    end

    -- handle button highlight
    if keystate == "down" then
      self.highlight:Show()
    elseif not MouseIsOverHitRect(self) then
      self.highlight:Hide()
    end
  end

  local function ButtonClick(self)
    local self = self or this

    local grid = self.bar == 12 and showgrid_pet or showgrid
    local mouse = arg1 and not keystate
    local keystate = keystate
    local slfcast = C.bars.altself == "1" and IsAltKeyDown() and true or self.slfcast
    slfcast = C.bars.rightself == "1" and arg1 and arg1 == "RightButton" and true or slfcast
    self.slfcast = nil
    if ( C.bars.keydown == "1" and keystate == "down" and not drag_active ) or (C.bars.keydown == "0" and keystate == "up" or drag_active ) or self.bar == 11 or mouse then
      if self.bar == 11 then
        CastShapeshiftForm(self.id)
      elseif grid == 1 then
        if self.bar == 12 then
          PickupPetAction(self.id)
        else
          PickupAction(self.id)
        end
      elseif self.bar == 12 then
        if arg1 == "LeftButton" then
          if IsPetAttackActive(self.id) then
            PetStopAttack()
          else
            CastPetAction(self.id)
          end
        else
          TogglePetAutocast(self.id)
        end
      else
        if MacroFrame_SaveMacro then
          MacroFrame_SaveMacro()
        end

        UseAction(self.id, nil, slfcast)
      end
    end
  end

  local function ButtonEnter(self)
    self = self or this

    -- indicate that dragging could get enabled, at once if shift is held
    drag_await = true
    AssumeButtonDrag()

    GameTooltip:ClearLines()
    GameTooltip_SetDefaultAnchor(GameTooltip, self)

    if self.bar == 11 then
      GameTooltip:SetShapeshift(self.id)
    elseif self.bar == 12 then
      local name, _, _, token = GetPetActionInfo(self.id)
      if token then
        GameTooltip:AddLine(_G[name])
        GameTooltip:Show()
      else
        GameTooltip:SetPetAction(self.id)
      end
    elseif self.spellID then
      GameTooltip:SetSpellByID(self.spellID)
    else
      GameTooltip:SetAction(self.id)
    end

    self.highlight:Show()
  end

  local function ButtonLeave(self)
    self = self or this

    -- no longer wait for a drag event
    drag_await = nil

    self.highlight:Hide()
    GameTooltip:Hide()
  end

  -- item counts and equipped border, the parts of a slot an inventory change touches
  local function ButtonInventoryUpdate(self)
    if self.bar == 11 or self.bar == 12 then return end
    local sid = self.id

    -- update consumables
    if IsConsumableAction(sid) then
      self.count:SetText(GetActionCount(sid))
    elseif IsReagentAction and IsReagentAction(sid) then
      self.count:SetText(GetReagentCount(sid))
    else
      self.count:SetText(nil)
    end

    -- equipped item
    self.equipped:SetShown(IsEquippedAction(sid) and C.bars.showequipped == "1")
  end

  -- the keybind text, which an empty hidden button hides as well. The binding
  -- itself is only read on UPDATE_BINDINGS (the "bindings" pass).
  local function ButtonKeybindUpdate(self)
    self.keybind:SetText(not self.hide and self.binding or "")
  end

  -- the active border of current, attack and auto repeat actions, which the
  -- "statechange" animation follows. A full update applies it unconditionally.
  local function ButtonActiveUpdate(self, active, force)
    if active then
      if not self.isactive and C.bars.animmode == "statechange" then
        PlayButtonAnimation(self)
      end

      if force or not self.isactive then
        self.backdrop:SetBackdropBorderColor(cr,cg,cb,1)
        self.active:Show()
        self.isactive = true
      end
    elseif force or self.isactive then
      self.backdrop:SetBackdropBorderColor(er,eg,eb,ea)
      self.active:Hide()
      self.isactive = nil
    end
  end

  -- the pulsing border of a spell whose proc glow is lit
  local function ButtonProcShow(self, glow)
    if glow then
      if not self.proc:IsShown() then
        self.proc:Show()
        self.proc.pulse:Play()
      end
    elseif self.proc:IsShown() then
      self.proc.pulse:Stop()
      self.proc:Hide()
    end
  end

  -- the spell an action slot casts, directly or through a macro, and its
  -- proc glow. The glow events name that spell.
  local function ButtonProcUpdate(self)
    local kind, id, spellid, _
    if C.bars.procglow == "1" then
      kind, id = GetActionInfo(self.id)
      if kind == "spell" then
        spellid = id
      elseif kind == "macro" then
        _, _, spellid = GetMacroSpell(id)
      end
    end

    self.spellid = spellid
    ButtonProcShow(self, spellid and IsSpellOverlayed(spellid))
  end

  local castable, autocast, token
  local grid, sid, active, texture, _
  local function ButtonSlotUpdate(self)
    sid = self.id -- 1 to 120

    -- reset shared variables
    castable, autocast, token = nil, nil, nil

    -- set the own ID for compatibility to some vanilla addons
    self:SetID(sid)

    grid = self.bar == 12 and showgrid_pet or showgrid

    if self.bar == 11 then
      -- stance button
      texture, _, active = GetShapeshiftFormInfo(sid)
    elseif self.bar == 12 then
      -- pet button
      _, _, texture, token, active, castable, autocast = GetPetActionInfo(sid)
      texture = token and _G[texture] or texture
    else
      active = IsCurrentAction(sid) or IsAutoRepeatAction(sid)
      texture = GetActionTexture(sid)
    end

    if not self.showempty and self.backdrop and not texture and grid == 0 then
      self.backdrop:Hide()
      self.hide = true
    else
      self.backdrop:Show()
      self.hide = nil
    end

    ButtonInventoryUpdate(self)

    if self.bar ~= 11 and self.bar ~= 12 then
      -- update macro text
      if C.bars["bar"..self.bar] and C.bars["bar"..self.bar].showmacro == "1" then
        self.macro:SetText(GetActionText(sid))
      else
        self.macro:SetText("")
      end

      ButtonProcUpdate(self)
    end

    -- icon
    if texture ~= self.texture then
      self.icon:SetTexture(texture)
      self.texture = texture
    end

    -- handle pet bar quirks
    if self.bar == 12 then
      -- desaturate disabled petbar
      self.icon:SetDesaturated(not GetPetActionsUsable())

      -- display autocast
      if autocast then
        self.autocast:Show()
        self.autocast:SetAlpha(self:GetAlpha() * 0.10)
      else
        self.autocast:Hide()
      end

      self.autocastable:SetShown(castable and C.bars.showcastable == "1")
    end

    ButtonActiveUpdate(self, active, true)
    ButtonKeybindUpdate(self)
  end

  local sid, usable, oom, _
  local function ButtonUsableUpdate(self)
    self = self or this
    sid = self.id -- 1 to 120

    if self.bar == 11 then
      _, _, _, usable = GetShapeshiftFormInfo(sid)
      oom = nil
    elseif self.bar == 12 then
      usable, oom = true, nil
    else
      usable, oom = IsUsableAction(sid)
    end

    -- update usable [out-of-range = 1, oom = 2, not-usable = 3, default = 0]
    if self.outofrange and C.bars.glowrange == "1" then
      if self.vertexstate ~= 1 then
        self.icon:SetVertexColor(self.rangeColor:GetRGBA())
        self.vertexstate = 1
      end
    elseif oom and C.bars.showoom == "1" then
      if self.vertexstate ~= 2 then
        self.icon:SetVertexColor(self.oomColor:GetRGBA())
        self.vertexstate = 2
      end
    elseif not usable and C.bars.showna == "1" then
      if self.vertexstate ~= 3 then
        self.icon:SetVertexColor(self.naColor:GetRGBA())
        self.vertexstate = 3
      end
    else
      if self.vertexstate ~= 0 then
        self.icon:SetVertexColor(1, 1, 1, 1)
        self.vertexstate = 0
      end
    end
  end

  -- Keeps the range check of the slot a shown action button displays
  -- enabled, so ACTION_RANGE_CHECK_UPDATE reports it. Each button holds its
  -- own enable, as the client counts them per slot. An enable fires the
  -- event with the current state, so a new slot starts in range until then.
  local function ButtonRangeWatch(button)
    local slot = C.bars.glowrange == "1" and button.bar <= 10 and button:IsVisible() and button.id or nil
    if slot == button.rangeslot then return end

    if button.rangeslot then C_ActionBar.EnableActionRangeCheck(button.rangeslot, false) end
    if slot then C_ActionBar.EnableActionRangeCheck(slot, true) end
    button.rangeslot = slot
    button.outofrange = nil
  end

  local start, duration, enable
  local function ButtonCooldownUpdate(button)
    if button.bar == 11 then
      start, duration, enable = GetShapeshiftFormCooldown(button.id)
    elseif button.bar == 12 then
      start, duration, enable = GetPetActionCooldown(button.id)
    else
      start, duration, enable = GetActionCooldown(button.id)
    end

    -- Nil-protect: GetActionCooldown can return nil during macro parsing/indexing
    if not start or not duration then return end
    enable = enable or 1

    -- most buttons keep their cooldown through a cooldown event
    if start == button.cdstart and duration == button.cdduration and enable == button.cdenable then return end
    button.cdstart, button.cdduration, button.cdenable = start, duration, enable

    CooldownFrame_SetTimer(button.cd, start, duration, enable)
  end

  local _, active
  local function ButtonIsActiveUpdate(button)
    if button.bar == 11 then
      _, _, active = GetShapeshiftFormInfo(button.id)
    elseif button.bar == 12 then
      _, _, _, _, active = GetPetActionInfo(button.id)
    else
      active = IsCurrentAction(button.id) or IsAutoRepeatAction(button.id)
    end

    ButtonActiveUpdate(button, active)
  end

  -- everything of a button; the slot update covers its active state
  local function ButtonFullUpdate(button)
    if not button then return end

    ButtonSlotUpdate(button)
    ButtonUsableUpdate(button)
    ButtonCooldownUpdate(button)
  end

  -- the pfActionBar frame handles the events of every button; its array part
  -- holds the bar frames, bars[1] to bars[12]
  local bars = CreateFrame("Frame", "pfActionBar", UIParent)

  -- Updates wait for the next frame, so the events of one frame share one
  -- pass. Passes and full updates skip hidden bars, which catch up as they
  -- show (BarShowHide). The shown buttons of a bar are its first `count` ones.
  local scheduled

  -- calls func on the buttons that show a slot: its own button and the main
  -- bar button paged to it
  local function ForSlotButtons(slot, func, a1)
    local button = buttoncache[slot]
    if button then func(button, a1) end

    local page = bars[1][1].id - 1
    local paged = slot > page and slot <= page + 12 and bars[1][slot - page]
    if paged and paged ~= button then func(paged, a1) end
  end

  -- the range watch follows hidden buttons too, so a hidden bar lets go of
  -- its slots
  local function SlotButtonUpdate(button)
    ButtonRangeWatch(button)
    if button:IsVisible() then pfUI.bars.ButtonFullUpdate(button) end
  end

  local function Flush()
    scheduled = nil

    local inventory, cooldown, state = passcache.inventory, passcache.cooldown, passcache.state
    local stance, bindings = passcache.stance, passcache.bindings
    table.wipe(passcache)

    if inventory or cooldown or state then
      for i = 1, 12 do
        local bar = bars[i]
        if bar:IsVisible() then
          for j = 1, bar.count do
            local button = bar[j]
            if inventory then ButtonInventoryUpdate(button) end
            if inventory or cooldown then ButtonCooldownUpdate(button) end
            if inventory then ButtonUsableUpdate(button) end
            if state then ButtonIsActiveUpdate(button) end
          end
        end
      end
    end

    if stance and not inventory and bars[11]:IsVisible() then
      for j = 1, bars[11].count do
        ButtonUsableUpdate(bars[11][j])
      end
    end

    -- the keybinds of hidden buttons as well, as they don't catch up on them
    if bindings then
      for _, button in pairs(buttoncache) do
        button.binding = GetKeybindText(button.bindcommand)
        ButtonKeybindUpdate(button)
      end
    end

    for slot in pairs(updatecache) do
      updatecache[slot] = nil
      ForSlotButtons(slot, SlotButtonUpdate)
    end
  end

  local function Schedule()
    if scheduled then return end
    scheduled = true
    RunNextFrame(Flush)
  end

  -- queues a full update of the button in a slot
  local function QueueSlot(slot)
    updatecache[slot] = true
    Schedule()
  end

  -- queues a pass over the visible buttons
  local function QueuePass(pass)
    passcache[pass] = true
    Schedule()
  end

  -- passes skip hidden bars, so a bar refreshes its buttons as it shows;
  -- as it hides, its buttons let go of their range checks
  local function BarShowHide()
    local offset = (this:GetID() - 1) * 12
    for j = 1, this.count do
      QueueSlot(offset + j)
    end
  end

  local function ButtonRangeEvent(button, outofrange)
    if button.rangeslot ~= arg1 or button.outofrange == outofrange then return end
    button.outofrange = outofrange
    ButtonUsableUpdate(button)
  end

  local function ButtonUsableEvent(button)
    if button:IsVisible() then ButtonUsableUpdate(button) end
  end

  local function BarsEvent()
    -- slot, isInRange, checksRange of a slot a button watches
    if event == "ACTION_RANGE_CHECK_UPDATE" then
      ForSlotButtons(arg1, ButtonRangeEvent, arg3 and not arg2 or nil)
      return
    end

    -- the slots whose usable state changed
    if event == "ACTION_USABLE_CHANGED" then
      for _, change in ipairs(arg1) do
        ForSlotButtons(change.slot, ButtonUsableEvent)
      end
      return
    end

    -- the spell whose glow started or ended; each rank has its own event
    if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" or event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
      local glow = IsSpellOverlayed(arg1)
      for _, button in pairs(buttoncache) do
        if button.spellid == arg1 then ButtonProcShow(button, glow) end
      end
      return
    end

    -- refresh only specific slots
    if event == "ACTIONBAR_SLOT_CHANGED" and arg1 and arg1 ~= 0 then
      QueueSlot(arg1)
      return
    end

    -- refresh one part of every visible button
    if pass_events[event] then
      QueuePass(pass_events[event])
      return
    end

    -- auras and forms change the stance buttons
    if aura_events[event] then
      for j = 1, bars[11].count do
        QueueSlot(bars[11][j].slot)
      end
      return
    end

    -- handle pet events
    if pet_events[event] then
      for j = 1, bars[12].count do
        QueueSlot(bars[12][j].slot)
      end
      return
    end

    -- refresh every button and its keybind
    if global_events[event] then
      QueuePass("bindings")
      for slot in pairs(buttoncache) do
        QueueSlot(slot)
      end
    end
  end

  -- The only unit events in the tables above; both concern the player alone.
  -- A registration keeps its kind, so these have to go in unit-filtered from
  -- the start -- RegisterUnitEvent over a plain registration stays plain.
  local event_units = {
    ["UNIT_INVENTORY_CHANGED"] = "player",
    ["UNIT_PET"] = "player",
  }

  local function RegisterBarEvent(event)
    local unit = event_units[event]
    if unit then
      bars:RegisterUnitEvent(event, unit)
    else
      bars:RegisterEvent(event)
    end
  end

  for event in pairs(pass_events) do RegisterBarEvent(event) end
  for event in pairs(global_events) do RegisterBarEvent(event) end
  for event in pairs(aura_events) do RegisterBarEvent(event) end
  for event in pairs(pet_events) do RegisterBarEvent(event) end
  bars:RegisterEvent("ACTION_RANGE_CHECK_UPDATE")
  bars:RegisterEvent("ACTION_USABLE_CHANGED")
  bars:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
  bars:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")

  -- refresh actionbar buttons on event
  bars:SetScript("OnEvent", BarsEvent)

  -- enable bar paging via secure functions
  local function EnablePaging(bar)
    if not bar.pager then
      bar.pager = CreateFrame("Frame")
      bar.pager:RegisterEvent("PLAYER_ENTERING_WORLD")
      bar.pager:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
      bar.pager:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
      bar.pager:SetScript("OnEvent", function()
        for i=1, 10 do -- reload pageable bars
          local pageable = C.bars["bar"..i] and C.bars["bar"..i].pageable == "1" and true or nil
          _G.VIEWABLE_ACTION_BAR_PAGES[i] = pageable
        end

        local active = GetActiveBar()
        for i=1,12 do
          bar[i].id = i + (active-1)*12
          QueueSlot(i)
        end
      end)
    end
  end

  local function SwitchBar(bar)
    if _G.CURRENT_ACTIONBAR_PAGE ~= bar then
      _G.CURRENT_ACTIONBAR_PAGE = bar
      ChangeActionBarPage(bar)
    end
  end

  local inCatForm = nil
  local prowlActive = nil

  -- Form IDs per vanilla 1.12 SpellShapeshiftForm.dbc.
  local CAT_FORM = 1
  local SHADOWFORM = 28
  local function HasCatForm()
    return GetShapeshiftFormID() == CAT_FORM and true or nil
  end

  local function InShadowform()
    return GetShapeshiftFormID() == SHADOWFORM and true or nil
  end

  local function FullScan()
    if class ~= "DRUID" then return nil end
    inCatForm = HasCatForm()
    prowlActive = inCatForm and IsStealthed() or nil
    return prowlActive
  end

  -- pagemaster / meta page switch
  do
    local formpage, shift, ctrl, alt, default = 8, 6, 5, 3, 1

    -- while a page modifier is held, MOD-key must run the main bar binding on
    -- that key so the switched page fires. Overrides do this without touching
    -- the saved binding set.
    local pagemods = {}
    if C.bars.pagemasteralt == "1" then table.insert(pagemods, "ALT") end
    if C.bars.pagemasterctrl == "1" then table.insert(pagemods, "CTRL") end
    if C.bars.pagemastershift == "1" then table.insert(pagemods, "SHIFT") end

    if table.getn(pagemods) > 0 then
      local pagemaster = CreateFrame("Frame", "pfPageMaster", UIParent)
      pagemaster:RegisterEvent("PLAYER_ENTERING_WORLD")
      pagemaster:RegisterEvent("UPDATE_BINDINGS")
      pagemaster:SetScript("OnEvent", function()
        ClearOverrideBindings(this)
        for i = 1, 12 do
          for _, key in ipairs({ GetBindingKey("ACTIONBUTTON"..i) }) do
            -- skip keys that already carry a modifier, e.g. "SHIFT-Q"
            if not key:find("^%u+%-.") then
              for _, mod in ipairs(pagemods) do
                SetOverrideBinding(this, false, mod.."-"..key, "ACTIONBUTTON"..i)
              end
            end
          end
        end
      end)
    end

    -- setup page switch frame. `formpaging` is the shared "auto-page is
    -- active" flag; druid prowl and priest shadowform each drive it, and
    -- no character is ever both, so one flag covers both features.
    local formpaging = nil
    local pageswitch = CreateFrame("Frame", "pfActionBarPageSwitch", UIParent)
    pageswitch:RegisterEvent("PLAYER_ENTERING_WORLD")
    pageswitch:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    pageswitch:RegisterEvent("PLAYER_AURAS_CHANGED")
    pageswitch:RegisterEvent("PLAYER_LOGOUT")
    local PROWL_IDS = { [5215] = true, [6783] = true, [9913] = true }
    if class == "DRUID" then
      pageswitch:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    end

    -- tracks prowl and shadowform from the page switch frame's events
    local function UpdateFormPaging()
      if class == "PRIEST" then
        if event == "UPDATE_SHAPESHIFT_FORM" or event == "PLAYER_ENTERING_WORLD" then
          formpaging = InShadowform()
        end
        return
      end

      if class ~= "DRUID" then return end

      if event == "PLAYER_ENTERING_WORLD" then
        formpaging = FullScan()
        return
      end

      -- Eager prowl detection on the cast itself — zero-latency vs.
      -- PLAYER_AURAS_CHANGED, which can land a frame or two behind it.
      -- arg3 = spellID
      if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if PROWL_IDS[arg3] then
          inCatForm = true
          prowlActive = true
          formpaging = true
        end
        return
      end

      if event == "UPDATE_SHAPESHIFT_FORM" then
        -- Authoritative form-change signal — recompute and short-circuit.
        inCatForm = HasCatForm()
        if not inCatForm then
          prowlActive = nil
          formpaging = nil
        end
        return
      end

      -- PLAYER_AURAS_CHANGED: form changes already went through
      -- UPDATE_SHAPESHIFT_FORM above; this handler only watches prowl on/off.
      if inCatForm then
        if IsStealthed() then
          prowlActive = true
          formpaging = true
        else
          prowlActive = nil
          formpaging = nil
        end
      end
    end

    -- sets the page the held modifier and the form ask for. It also runs on
    -- every page change, so a page switched by other means snaps back.
    local function UpdatePage()
      local page = _G.CURRENT_ACTIONBAR_PAGE

      -- switch actionbar page depending on meta key that is pressed
      if C.bars.pagemastershift == "1" and ShiftDown() then
        page = shift
      elseif C.bars.pagemasterctrl == "1" and CtrlDown() then
        page = ctrl
      elseif C.bars.pagemasteralt == "1" and AltDown() then
        page = alt
      elseif C.bars.pagemasteralt == "1" or C.bars.pagemasterctrl == "1" or C.bars.pagemastershift == "1" then
        page = default
      end

      -- switch actionbar page while druid stealth / priest shadowform is active
      if (class == "DRUID" and C.bars.druidstealth == "1")
      or (class == "PRIEST" and C.bars.priestshadow == "1") then
        if formpaging and page == default then
          page = formpage
        elseif not formpaging and page == formpage then
          page = default
        end
      end

      SwitchBar(page)
    end

    pageswitch:SetScript("OnEvent", function()
      if event == "PLAYER_LOGOUT" then
        this:UnregisterAllEvents()
        this:SetScript("OnEvent", nil)
        return
      end

      UpdateFormPaging()
      UpdatePage()
    end)

    pfUI.events:RegisterFrameEventAndCallback("MODIFIER_STATE_CHANGED", UpdatePage)
    pfUI.events:RegisterFrameEventAndCallback("ACTIONBAR_PAGE_CHANGED", UpdatePage)
  end

  local function CreateActionButton(parent, bar, button)
    -- load config
    local size = C.bars["bar"..bar].icon_size
    local font = pfUI.media[C.bars.font]
    local font_offset = tonumber(C.bars.font_offset)

    local macro_size = tonumber(C.bars.macro_size)
    local macro_color = { GetStringColor(C.bars.macro_color) }

    local count_size = tonumber(C.bars.count_size)
    local count_color = { GetStringColor(C.bars.count_color) }

    local bind_size = tonumber(C.bars.bind_size)
    local bind_color = { GetStringColor(C.bars.bind_color) }

    local showempty = C.bars["bar"..bar].showempty
    local showmacro = C.bars["bar"..bar].showmacro
    local showkybind = C.bars["bar"..bar].showkeybind
    local showcount = C.bars["bar"..bar].showcount

    -- sanitize font sizes
    if macro_size == 0 then macro_size = 1 end
    if count_size == 0 then macro_size = 1 end
    if bind_size == 0 then macro_size = 1 end

    local button_name = "pfActionBar" .. barnames[bar] .. "Button" .. button

    local id = (bar-1)*12+button
    local exists = _G[button_name] and true or nil
    local f = _G[button_name] or CreateFrame("Button", button_name, parent)

    -- no button available, create a new one
    if not exists then
      -- prepare the button for vanilla
      if not f.HookScript then f.HookScript = HookScript end
      f:SetScript("OnClick", ButtonClick)

      if bar ~= 11 then
        f:RegisterForDrag("LeftButton", "RightButton")
        f:SetScript("OnDragStart", ButtonDrag)
        f:SetScript("OnReceiveDrag", ButtonDragStop)
      end

      -- add mouseovers
      f:SetScript("OnEnter", ButtonEnter)
      f:SetScript("OnLeave", ButtonLeave)

      -- add click animation handler
      f:HookScript("OnClick", ButtonAnimate)
      f.id = id

      -- set a static slot
      f.slot = id

      -- the binding command of the button, fixed on the paged main bar too
      f.bindcommand = (bar == 1 and "ACTIONBUTTON" or buttontypes[bar]) .. button

      -- cooldown
      f.cd = CreateCooldown(f, "spell", C.bars, "timers", f:GetName() .. "Cooldown")

      -- icon
      f.icon = f:CreateTexture(button_name .. "Icon", "BACKGROUND")
      f.icon:SetTexCoord(.08, .92, .08, .92)
      f.icon:SetAllPoints()

      -- animation
      f.animation = CreateFrame("Frame", button_name .. "Animation", f)
      f.animation.groups = {}
      f.animation:SetAllPoints()
      f.animation:Hide()
      f.animation.tex = f.animation:CreateTexture(button_name .. "AnimationTexture", "BACKGROUND")
      f.animation.tex:SetTexCoord(.08, .92, .08, .92)
      f.animation.tex:SetAllPoints()

      if bar ~= 11 and bar ~= 12 then
        -- equipped item
        f.equipped = f:CreateTexture(nil, "BORDER")
        f.equipped:SetAllPoints()
        f.equipped:Hide()
      elseif bar == 12 then
        f.autocast = CreateFrame("Model", nil, f)
        f.autocast:SetAllPoints()
        f.autocast:SetModel("Interface\\Buttons\\UI-AutoCastButton.mdx")
        f.autocast:SetSequence(0)
        f.autocast:SetSequenceTime(0, 0)
        f.autocast:Hide()

        f.autocastable = f:CreateTexture(nil, "BORDER")
        f.autocastable:SetAllPoints()
        f.autocastable:SetTexture("Interface\\Buttons\\UI-AutoCastableOverlay")
        f.autocastable:SetTexCoord(.25, .75, .25, .75)
      end

      -- macro
      f.macro = f:CreateFontString(button_name .. "Name", "LOW", "GameFontNormal")

      -- keybind
      f.keybind = f:CreateFontString(nil, "LOW", "GameFontNormal")

      -- itemcount
      f.count = f:CreateFontString(button_name .. "Count", "LOW", "GameFontNormal")

      -- highlight
      f.highlight = CreateFrame("Frame", nil, f)
      f.highlight:SetBackdrop(backdrop_highlight)
      f.highlight:SetBackdropBorderColor(1,1,1,.8)
      f.highlight:SetAllPoints()
      f.highlight:Hide()

      -- active
      f.active = CreateFrame("Frame", nil, f)
      f.active:SetBackdrop(backdrop_highlight)
      f.active:SetBackdropBorderColor(1,1,.5,1)
      f.active:SetAllPoints()
      f.active:Hide()

      -- proc glow
      if bar ~= 11 and bar ~= 12 then
        f.proc = CreateFrame("Frame", nil, f)
        f.proc:SetBackdrop(backdrop_highlight)
        f.proc:SetBackdropBorderColor(1,.8,.2,1)
        f.proc:SetAllPoints()
        f.proc:Hide()

        f.proc.pulse = f.proc:CreateAnimationGroup()
        f.proc.pulse:SetLooping("BOUNCE")
        local fade = f.proc.pulse:CreateAnimation("Alpha")
        fade:SetFromAlpha(1)
        fade:SetToAlpha(.3)
        fade:SetDuration(.5)
        fade:SetSmoothing("IN_OUT")
      end

      -- add to buttoncache
      buttoncache[id] = f
    end

    -- set keydown option
    if C.bars.keydown == "1" then
      f:RegisterForClicks("LeftButtonDown", "RightButtonDown")
    else
      f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    end

    -- pet autocast
    if bar == 12 then
      f.autocast:SetScale(C.bars["bar"..bar].icon_size / 25)
      f.autocast:SetAlpha(.10)
    end

    -- macro options
    f.macro:SetShown(showmacro == "1")
    SetAllPointsOffset(f.macro, f, font_offset, -font_offset)
    f.macro:SetFont(font, macro_size, "OUTLINE")
    f.macro:SetTextColor(unpack(macro_color))
    f.macro:SetJustifyH("LEFT")
    f.macro:SetJustifyV("BOTTOM")

    -- keybind options
    f.keybind:SetShown(showkybind == "1")
    SetAllPointsOffset(f.keybind, f, font_offset, -font_offset)
    f.keybind:SetFont(font, bind_size, "OUTLINE")
    f.keybind:SetTextColor(unpack(bind_color))
    f.keybind:SetJustifyH("RIGHT")
    f.keybind:SetJustifyV("TOP")
    f.keybind:SetNonSpaceWrap(false)

    -- item count options
    f.count:SetShown(showcount == "1")
    SetAllPointsOffset(f.count, f, font_offset, -font_offset)
    f.count:SetFont(font, count_size, "OUTLINE")
    f.count:SetTextColor(unpack(count_color))
    f.count:SetJustifyH("RIGHT")
    f.count:SetJustifyV("BOTTOM")

    -- range glow color
    f.rangeColor = GetStringColorObject(C.bars.rangecolor)

    -- out of mana color
    f.oomColor = GetStringColorObject(C.bars.oomcolor)

    -- not usable color
    f.naColor = GetStringColorObject(C.bars.nacolor)

    -- equipped color
    if f.equipped then
      f.equipped:SetColorTexture(GetStringColor(C.bars.eqcolor))
    end

    -- general appearance
    f.showempty = showempty == "1" and true or nil
    f:SetSize(size, size)
    CreateBackdrop(f, border)

    return f
  end

  local function CreateActionBar(i)
    -- load config
    local buttonbasename = "pfActionBar" .. barnames[i] .. "Button"
    local enable = C.bars["bar"..i].enable
    local size = C.bars["bar"..i].icon_size
    local spacing = C.bars["bar"..i].spacing
    local background = C.bars["bar"..i].background
    local formfactor = C.bars["bar"..i].formfactor
    local uneven = C.bars["bar"..i].uneven or "Down"
    local fillmode = C.bars["bar"..i].fillmode or "auto"
    -- validate uneven against bar shape and reset if incompatible
    local _, _, fcols2, frows2 = string.find(tostring(formfactor or ""), "(%d+)%s*x%s*(%d+)")
    fcols2, frows2 = tonumber(fcols2), tonumber(frows2)
    local f_is_square = fcols2 == 3 and frows2 == 3
    local f_is_vertical = fcols2 and fcols2 <= 3 and not f_is_square
    local f_is_horizontal = frows2 and frows2 <= 3 and not f_is_square
    if f_is_vertical then
      if uneven ~= "Up" and uneven ~= "Down" then uneven = "Down" end
    elseif f_is_horizontal then
      if uneven ~= "Left" and uneven ~= "Right" then uneven = "Down" end
    end
    C.bars["bar"..i].uneven = uneven
    local autohide = C.bars["bar"..i].autohide
    local hide_time = C.bars["bar"..i].hide_time
    local hide_combat = C.bars["bar"..i].hide_combat == "1" and true or nil

    local buttons = tonumber(C.bars["bar"..i].buttons) or 12
    if i == 11 and bars[i] then -- shapeshift buttons
      buttons = GetNumShapeshiftForms()
    elseif i == 12 and bars[i] then -- pet buttons
      buttons = NUM_PET_ACTION_SLOTS
    elseif i == 12 or i == 11 then
      -- Fallback to 10 buttons on shapeshift and petbar during initialization.
      -- This lets us load bars that aren't yet available for your class or level.
      buttons = 10
    end

    -- don't process empty bars
    if buttons == 0 then
      bars[i].count = 0
      bars[i]:Hide()
      return
    end

    -- the stored layout is invalid, temporary fallback
    if not fcols2 or not frows2 then
      formfactor = BarLayoutOptions(buttons)[1]
    end

    local font = pfUI.font_unit
    local font_size = C.global.font_unit_size

    local realsize = size+border*2

    -- create frame
    local init = not bars[i]
    bars[i] = bars[i] or CreateFrame("Frame", "pfActionBar" .. barnames[i], UIParent)
    bars[i]:SetID(i)
    bars[i].count = buttons
    if init then
      bars[i]:SetScript("OnShow", BarShowHide)
      if i <= 10 then bars[i]:SetScript("OnHide", BarShowHide) end
    end

    -- autohide
    if autohide == "1" then
      EnableAutohide(bars[i], tonumber(hide_time), hide_combat)
    else
      DisableAutohide(bars[i])
    end

    -- apply visible settings
    if enable == "1" then
      -- handle pet bar
      if i == 12 then
        -- only show when pet actions exists
        bars[i]:SetShown(PetHasActionBar() or pfUI.unlock and pfUI.unlock:IsShown())

        -- show/hide petbar on petbar updates; the pet events of the
        -- pfActionBar frame refresh its buttons
        if init then
          bars[i]:RegisterEvent("PET_BAR_UPDATE")
          bars[i]:SetScript("OnEvent", function()
            this:SetShown(PetHasActionBar() or pfUI.unlock and pfUI.unlock:IsShown())
          end)
        end

      -- handle shapeshift bar
      elseif i == 11 then
        -- only show when shapeshifts exist
        bars[i]:SetShown(GetNumShapeshiftForms() > 0)

        -- update shapeshift bar when amount of spells changes
        if init then
          bars[i]:RegisterEvent("PLAYER_ENTERING_WORLD")
          bars[i]:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
          bars[i]:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
          bars[i]:SetScript("OnEvent", function()
            local count = GetNumShapeshiftForms()
            if count ~= this.lastCount then
              this.lastCount = count

              -- hide obsolete buttons
              for i=1, NUM_SHAPESHIFT_SLOTS do
                if i > GetNumShapeshiftForms() and bars[11][i] then
                  bars[11][i]:Hide()
                end
              end

              -- create new buttons and refresh layout
              CreateActionBar(11)
            end
          end)
        end

      -- regular bars
      else
        bars[i]:Show()
      end

    elseif enable == "0" then
      bars[i]:UnregisterAllEvents()
      bars[i]:Hide()
    end

    -- create action buttons
    local maxbuttons = (i == 11 or i == 12) and 10 or 12
    for j=1,maxbuttons do
      bars[i][j] = CreateActionButton(bars[i], i, j)
      bars[i][j].bar = i

      BarButtonAnchor(bars[i][j], buttonbasename, j, buttons, formfactor, size, border, spacing, uneven, fillmode)
      bars[i][j]:ClearAllPoints()
      bars[i][j]:SetPoint(unpack(bars[i][j]._anchor))
      bars[i][j]:Show()

      if i > 10 then
        bars[i][j].id = j
      end

      -- refresh button
      QueueSlot(bars[i][j].slot)
    end

    for j=buttons+1,12 do
      if bars[i][j] then
        bars[i][j]:Hide()
      end
    end

    -- enable paging for the first actionbar
    if i == 1 then
      EnablePaging(bars[i])
    end

    -- adjust actionbar size
    BarLayoutSize(bars[i], buttons, formfactor, size, border, spacing, uneven, fillmode)
    bars[i]:SetSize(bars[i]._size[1], bars[i]._size[2])
    bars[i]:ClearAllPoints()
    if i == 1 then -- main
      bars[i]:SetPoint("BOTTOM", 0, 2*border)
    elseif i == 3 then -- left
      bars[i]:SetPoint("BOTTOMLEFT", bars[1], "BOTTOMRIGHT", 3*border, 0)
    elseif i == 4 then -- vertical
      bars[i]:SetPoint("RIGHT", -2*border, 0)
    elseif i == 5 then -- right
      bars[i]:SetPoint("BOTTOMRIGHT", bars[1], "BOTTOMLEFT", -3*border, 0)
    elseif i == 6 then -- top
      bars[i]:SetPoint("BOTTOM", bars[1], "TOP", 0, -spacing)
    elseif i == 11 then -- stances
      bars[i]:SetPoint("BOTTOM", bars[6], "TOP", 0, 3*border)
    elseif i == 12 then -- pet
      bars[i]:SetPoint("BOTTOM", bars[6], "TOP", 0, 3*border)

      if init then
        -- make stance bar dodge by default
        bars[i]:HookScript("OnShow", function()
          if pfUI.unlock and pfUI.unlock:IsShown() then return end
          if bars[11] and bars[11]:IsShown() then
            bars[11]:ClearAllPoints()
            bars[11]:SetPoint("BOTTOM", bars[12], "TOP", 0, 3*border)
            UpdateMovable(bars[11], true)
          end
        end)

        -- restore old stance bar position
        bars[i]:SetScript("OnHide", function()
          if pfUI.unlock and pfUI.unlock:IsShown() then return end
          if bars[11] and bars[11]:IsShown() then
            bars[11]:ClearAllPoints()
            bars[11]:SetPoint("BOTTOM", bars[6], "TOP", 0, 3*border)
            UpdateMovable(bars[11], true)
          end
        end)
      end
    else -- others
      bars[i]:SetPoint("TOP", 0, -i*50)
    end

    UpdateMovable(bars[i])

    -- apply backdrop settings
    if background == "1" then
      CreateBackdrop(bars[i], border)
      CreateBackdropShadow(bars[i])
      bars[i].backdrop:Show()
    elseif bars[i].backdrop then
      bars[i].backdrop:Hide()
    end

    -- share backdrop of main and top actionbar
    if bars[6] and bars[1] then
      bars[6].OnMove = bars[6].OnMove or function()
        bars[1].mergedBackdrop = bars[1].mergedBackdrop or CreateFrame("Frame", nil, UIParent)
        bars[1].mergedBackdrop:SetPoint("TOPLEFT", bars[6], "TOPLEFT", 0, 0)
        bars[1].mergedBackdrop:SetPoint("BOTTOMRIGHT", bars[1], "BOTTOMRIGHT", 0, 0)
        CreateBackdrop(bars[1].mergedBackdrop)

        local _, anchor, _ = bars[6]:GetPoint()
        if anchor == bars[1] and C.bars.bar1.enable == "1"
          and C.bars.bar1.enable == "1" and C.bars.bar6.enable == "1"
          and C.bars.bar1.background == "1" and C.bars.bar6.background == "1"
          and C.bars.bar1.autohide == "0" and C.bars.bar6.autohide == "0"
          and C.bars.bar1.icon_size == C.bars.bar6.icon_size
          and C.bars.bar1.spacing == C.bars.bar6.spacing
          and C.bars.bar1.formfactor == C.bars.bar6.formfactor
          and C.bars.bar1.buttons == C.bars.bar6.buttons
        then
          bars[1].mergedBackdrop:Show()

          if C.bars.bar1.background == "1" and bars[1].backdrop then
            bars[1].backdrop:Hide()
          end

          if C.bars.bar6.background == "1" and bars[6].backdrop then
            bars[6].backdrop:Hide()
          end
        else
          bars[1].mergedBackdrop:Hide()

          if C.bars.bar1.background == "1" and bars[1].backdrop then
            bars[1].backdrop:Show()
          end

          if C.bars.bar6.background == "1" and bars[6].backdrop then
            bars[6].backdrop:Show()
          end
        end
      end
      bars[6].OnMove()
    end
  end

  -- create actionbars
  pfUI.bars = bars
  pfUI.bars.QueueSlot = QueueSlot
  pfUI.bars.buttons = buttoncache
  pfUI.bars.ButtonFullUpdate = ButtonFullUpdate
  pfUI.bars.ButtonEnter = ButtonEnter
  pfUI.bars.ButtonLeave = ButtonLeave

  pfUI.bars.UpdateGrid = function(self, state, typ)
    if not typ then
      showgrid = state

      for slot in pairs(buttoncache) do
        QueueSlot(slot)
      end
    elseif typ == "PET" then
      showgrid_pet = state
      for slot=133,142 do
        QueueSlot(slot)
      end
    end
  end

  pfUI.bars.UpdateConfig = function(self)
    for i=1,12 do
      CreateActionBar(i)
    end
  end

  pfUI.bars:UpdateConfig()

  -- update all bars when entering or leaving unlock mode
  if pfUI.unlock then
    pfUI.unlock:HookScript("OnShow", function() pfUI.bars:UpdateConfig() end)
    pfUI.unlock:HookScript("OnHide", function() pfUI.bars:UpdateConfig() end)
  end

  -- Localize custom keybinds for additional actionbars (see Bindings.xml)
  local names = {
    ["PAGING"] = T["Paging Actionbar"],
    ["STANCEONE"] = T["Stance Bar 1"],
    ["STANCETWO"] = T["Stance Bar 2"],
    ["STANCETHREE"] = T["Stance Bar 3"],
    ["STANCEFOUR"] = T["Stance Bar 4"],
  }

  for name, loc in pairs(names) do
    _G["BINDING_HEADER_PFBAR"..name] = T["Action Bar"] .. " " .. loc
    for i=1,12 do
      _G["BINDING_NAME_PF" .. name .. i] = loc .. " " .. T["Button"] .. " " .. i
    end
  end

  -- Map Keybinds to button clicks
  function _G.pfActionButton(slot, slfcast, opt)
    if ChatFrameEditBox:IsShown() then return end

    local bar, button = 1, slot

    -- determine the proper bar and button
    if opt and blizzbarmapping[opt] then
      bar = blizzbarmapping[opt]
    elseif slot > 12 then
      bar, button = ceil(slot/12), mod(slot, 12)
      button = button == 0 and 12 or button
    end

    local frame = bars[bar][button]
    if frame then
      frame.slfcast = slfcast
      frame:Click()
    end
  end

  -- Set keybinds to all actionbuttons
  -- In order to be able to reuse already defined keybinds, we need to remap
  -- existing button functions to pfUI. We need to get rid of the blizzard calls
  -- to avoid having them call texture changes and errors due to missing buttons
  _G.ActionButtonDown = pfActionButton
  _G.ActionButtonUp = pfActionButton
  _G.BonusActionButtonDown = function(slot) pfActionButton(slot, nil, "BonusActionBar") end
  _G.BonusActionButtonUp = function(slot) pfActionButton(slot, nil, "BonusActionBar") end
  _G.MultiActionButtonDown = function(bar, slot, slf) pfActionButton(slot, slf, bar) end
  _G.MultiActionButtonUp = function(bar, slot, slf) pfActionButton(slot, slf, bar) end
  _G.ShapeshiftBar_ChangeForm = function(slot) pfActionButton(slot, nil, "ShapeShiftBar") end

  -- handle drag-drop grid
  pfUI.events:RegisterFrameEventAndCallback("ACTIONBAR_SHOWGRID", function() pfUI.bars:UpdateGrid(1) end)
  pfUI.events:RegisterFrameEventAndCallback("ACTIONBAR_HIDEGRID", function() pfUI.bars:UpdateGrid(0) end)
  pfUI.events:RegisterFrameEventAndCallback("PET_BAR_SHOWGRID", function() pfUI.bars:UpdateGrid(1, "PET") end)
  pfUI.events:RegisterFrameEventAndCallback("PET_BAR_HIDEGRID", function() pfUI.bars:UpdateGrid(0, "PET") end)

  -- reagent counter
  if C.bars.reagents == "1" then
    local reagent_slots = { }   -- action slot -> first reagent itemID
    local reagent_counts = { }  -- itemID -> count in player's inventory

    -- For a given action slot, resolve the spell's first reagent itemID
    -- via GetActionInfo + C_Spell.GetSpellReagents. Macro actions and
    -- bag-item actions are skipped (their reagent resolution would need a
    -- macro-body parse / item-effect lookup that we don't bother with).
    local function UpdateSlot(slot)
      local newID = nil
      if HasAction(slot) then
        local kind, spellID = GetActionInfo(slot)
        if kind == "spell" and spellID then
          local reagents = C_Spell.GetSpellReagents(spellID)
          if reagents and reagents[1] then
            newID = reagents[1].itemID
          end
        end
      end

      if reagent_slots[slot] ~= newID then
        reagent_slots[slot] = newID
        if newID then
          reagent_counts[newID] = reagent_counts[newID] or C_Item.GetItemCount(newID)
        end
        QueueSlot(slot)
      end
    end

    -- Recount every tracked reagent and flag its buttons for a refresh.
    local RecountReagents = function()
      for itemID in pairs(reagent_counts) do
        reagent_counts[itemID] = C_Item.GetItemCount(itemID)
      end
      for slot in pairs(reagent_slots) do
        QueueSlot(slot)
      end
    end

    local reagentcounter = CreateFrame("Frame", "pfReagentCounter", UIParent)
    reagentcounter:RegisterEvent("PLAYER_ENTERING_WORLD")
    reagentcounter:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
    reagentcounter:RegisterEvent("BAG_UPDATE_DELAYED")
    reagentcounter:SetScript("OnEvent", function()
      if event == "ACTIONBAR_SLOT_CHANGED" then
        -- arg1 is the changed slot; 0 (or nil) means "all slots"
        if arg1 and arg1 > 0 then
          UpdateSlot(arg1)
        else
          for slot = 1, 120 do UpdateSlot(slot) end
        end
      elseif event == "BAG_UPDATE_DELAYED" then
        -- inventory changed: refresh the counts we already track
        RecountReagents()
      else
        -- PLAYER_ENTERING_WORLD: seed the full reagent map (UpdateSlot seeds
        -- each new reagent's count; a BAG_UPDATE_DELAYED follows during login)
        for slot = 1, 120 do UpdateSlot(slot) end
      end
    end)

    function IsReagentAction(slot)
      return reagent_slots[slot] and true or nil
    end

    function GetReagentCount(slot)
      return reagent_counts[reagent_slots[slot]]
    end
  end
end)