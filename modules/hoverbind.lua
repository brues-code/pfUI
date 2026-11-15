pfUI:RegisterModule("hoverbind", function ()
  local mousebuttonmap = {
    ["LeftButton"]   = "BUTTON1",
    ["RightButton"]  = "BUTTON2",
    ["MiddleButton"] = "BUTTON3",
    ["Button4"]      = "BUTTON4",
    ["Button5"]      = "BUTTON5",
  }

  local mousewheelmap = {
    [1]  = "MOUSEWHEELUP",
    [-1] = "MOUSEWHEELDOWN",
  }

  local modifiers = {
    ["ALT"]   = "ALT-",
    ["CTRL"]  = "CTRL-",
    ["SHIFT"] = "SHIFT-"
  }

  -- We don't allow binding these keys without any modifiers
  local blockedKeys = {
    "LeftButton",
    "RightButton",
  }

  pfUI.hoverbind = CreateFrame("Frame","pfKeyBindingFrame",UIParent)
  pfUI.hoverbind:Hide()
  pfUI.hoverbind:RegisterEvent("PLAYER_REGEN_DISABLED")
  pfUI.hoverbind:EnableMouse(true)
  pfUI.hoverbind.edit = CreateFrame("Button", "pfKeyBindingFrameEdit", pfUI.hoverbind)
  pfUI.hoverbind.edit:SetFrameStrata("BACKGROUND")
  pfUI.hoverbind.edit:SetAllPoints(UIParent)
  pfUI.hoverbind.edit.tex = pfUI.hoverbind.edit:CreateTexture("pfKeyBindShade", "BACKGROUND")
  pfUI.hoverbind.edit.tex:SetAllPoints(pfUI.hoverbind.edit)
  pfUI.hoverbind.edit.tex:SetColorTexture(0,0,0,.5)
  pfUI.hoverbind.edit:SetScript("OnClick", function()
    pfUI.hoverbind:Hide()
  end)

  pfUI.hoverbind:SetScript("OnMouseUp",function(...)
    pfUI.hoverbind:Hide()
  end)

  pfUI.hoverbind:SetScript("OnShow", function()
    if pfUI.bars then
      pfUI.bars:UpdateGrid(1)
      pfUI.bars:UpdateGrid(1, "PET")
    end

    pfUI.hoverbind:RegisterActionButtons()

    pfUI.gui:Hide()
    pfUI.hoverbind.edit:Show()
    pfUI.hoverbind:ShowHoverbindFrames()

    local txt = T["|cff33ffccKeybind Mode|r\nThis mode allows you to bind keyboard shortcuts to your actionbars.\nBy hovering a button with your cursor and pressing a key, the key will be assigned to that button.\nHit Escape on a button to remove bindings.\n\nPress Escape or click on an empty area to leave the keybind mode."]
    CreateInfoBox(txt, 30,  pfUI.hoverbind.edit)
  end)

  pfUI.hoverbind:SetScript("OnHide",function()
    if pfUI.bars then
      pfUI.bars:UpdateGrid(0)
      pfUI.bars:UpdateGrid(0, "PET")
    end
    pfUI.hoverbind:HideHoverbindFrames()
    pfUI.hoverbind.edit:Hide()
    pfUI.gui:Show()
  end)

  -- the readable name of a binding command: its BINDING_NAME_, or the spell,
  -- item or macro a direct-action command names
  local function BindingName(command)
    return _G["BINDING_NAME_" .. command]
      or command:match("^SPELL (.+)")
      or command:match("^ITEM (.+)")
      or command:match("^MACRO (.+)")
      or command
  end

  function pfUI.hoverbind:GetPrefix()
    return string.format("%s%s%s",
      (IsAltKeyDown() and modifiers.ALT or ""),
      (IsControlKeyDown() and modifiers.CTRL or ""),
      (IsShiftKeyDown() and modifiers.SHIFT or ""))
  end

  local function GetHoverbindHandler(map)
    return function()
      if modifiers[arg1] then return end -- ignore single modifier keyup

      local prefix = pfUI.hoverbind:GetPrefix()

      -- Don't allow binding certain buttons without modifiers
      if not prefix or prefix == "" then
        for _, blockedKey in ipairs(blockedKeys) do
          if arg1 == blockedKey then return end
        end
      end

      local frame = GetMouseFocus()
      local binding = frame and frame.button and frame.button.bindcommand
      if arg1 == "ESCAPE" and not binding then pfUI.hoverbind:Hide() return end
      if binding then
        if arg1 == "ESCAPE" then
          -- Remove all existing bindings
          local keys = { GetBindingKey(binding) }
          for _, key in ipairs(keys) do
            SetBinding(key)
          end
          if keys[1] then
            SaveBindings(GetCurrentBindingSet())
          end
        else
          -- Create new binding
          local key = prefix .. (map and map[arg1] or arg1)
          local previous = GetBindingAction(key)
          if (SetBinding(key, binding)) then
            SaveBindings(GetCurrentBindingSet())

            if previous and previous ~= "" and previous ~= binding then
              DEFAULT_CHAT_FRAME:AddMessage("|cff33ffcc" .. key .. "|r " .. T["was unbound from"] .. " " .. BindingName(previous))
            end

            local active = GetBindingAction(key, true)
            if active ~= binding then
              DEFAULT_CHAT_FRAME:AddMessage("|cff33ffcc" .. key .. "|r " .. T["is currently overridden by"] .. " " .. BindingName(active))
            end
          end
        end
      end
    end
  end

  local keyHandler = GetHoverbindHandler()
  local mouseHandler = GetHoverbindHandler(mousebuttonmap)
  local wheelHandler = GetHoverbindHandler(mousewheelmap)

  -- Run the button's own enter/leave scripts for its highlight and tooltip,
  -- as the hoverbind frame swallows the mouse events of the button.
  local function HoverEnter(self)
    local script = self.button:GetScript("OnEnter")
    if script then script(self.button) end
  end

  local function HoverLeave(self)
    local script = self.button:GetScript("OnLeave")
    if script then script(self.button) end
  end

  pfUI.hoverbind.frames = {}

  -- Covers a button with an invisible hoverbind frame, shown only while the
  -- keybind mode is active, that binds keys, mouse buttons and the mouse
  -- wheel to the button's 'bindcommand'. Otherwise the button itself would
  -- not be clickable.
  function pfUI.hoverbind:Register(button)
    local frame = CreateFrame("Frame", nil, button)
    frame:SetAllPoints(button)
    frame:EnableKeyboard(true)
    frame:EnableMouse(true)
    frame:EnableMouseWheel(true)
    frame:SetShown(self:IsShown())
    frame.button = button

    frame:SetScript("OnKeyUp", keyHandler)
    frame:SetScript("OnMouseUp", mouseHandler)
    frame:SetScript("OnMouseWheel", wheelHandler)
    frame:SetScript("OnEnter", HoverEnter)
    frame:SetScript("OnLeave", HoverLeave)

    table.insert(self.frames, frame)
  end

  -- the action bars might not exist yet when this module is loaded
  function pfUI.hoverbind:RegisterActionButtons()
    if self.actionbuttons or not pfUI.bars then return end
    self.actionbuttons = true

    for i=1,12 do
      for j=1,12 do
        local button = pfUI.bars[i][j]
        if button then self:Register(button) end
      end
    end
  end

  function pfUI.hoverbind:ShowHoverbindFrames()
    for _, frame in ipairs(pfUI.hoverbind.frames) do
      frame:Show()
    end
  end

  function pfUI.hoverbind:HideHoverbindFrames()
    for _, frame in ipairs(pfUI.hoverbind.frames) do
      frame:Hide()
    end
  end

  pfUI.hoverbind:SetScript("OnEvent",function()
    -- disable hoverbind so player gets back control of their keyboard to fight
    pfUI.hoverbind:Hide()
  end)
end)
