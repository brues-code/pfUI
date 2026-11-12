pfUI:RegisterModule("thirdparty", function()
  -- This module includes the core logic of thirdparty modules.
  -- Right now, in particular the functions to register addons to the
  -- dockframe of the chat panel aswell as the thirdparty root-table.
  -- For vanilla-specific glue, see: thirdparty-vanilla.

  pfUI.thirdparty = {}

  do -- addon dockframe
    pfUI.thirdparty.meters = CreateFrame("Frame")
    pfUI.thirdparty.meters:SetScript("OnEvent", function()
      if C.thirdparty.showmeter == "1" then
        pfUI.thirdparty.meters.state = nil
      else
        pfUI.thirdparty.meters.state = true
      end

      pfUI.thirdparty.meters:Toggle()
      this:UnregisterAllEvents()
    end)

    pfUI.thirdparty.meters.damage = nil
    pfUI.thirdparty.meters.threat = nil
    pfUI.thirdparty.meters.state = nil

    function pfUI.thirdparty.meters:RegisterMeter(side, data)
      -- abort when one addon is already register on the side
      if pfUI.thirdparty.meters[side] then return end

      -- load addon table
      local config, addon, frame, single, dual, show, hide, once = unpack(data)

      -- put addon into dockmode when enabled
      if C.thirdparty[config] and C.thirdparty[config].dock == "1" then
        pfUI.thirdparty.meters[side] = data

        -- initialize and hide the frame in the beginning
        if once then once() end
        if hide then hide() end

        -- enable toggle event on the panel button
        if pfUI.panel then
          pfUI.panel.right.hide:SetScript("OnClick", function()
            pfUI.thirdparty.meters:Toggle()
          end)
        end

        -- show/hide meter on login by default
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
      end
    end

    function pfUI.thirdparty.meters:Resize()
      if not pfUI.chat or not pfUI.panel then return end

      if self.damage then -- resize damage meter
        local config, addon, frame, single, dual, show, hide = unpack(self.damage)
        if frame and C.thirdparty[config].dock == "1" then
          if not self.threat then single() else dual() end
        end
      end

      if self.threat then -- resize threat meter
        local config, addon, frame, single, dual, show, hide = unpack(self.threat)
        if frame and C.thirdparty[config].dock == "1" then
          if not self.damage then single() else dual() end
        end
      end
    end

    function pfUI.thirdparty.meters:Toggle()
      self:Resize()

      -- show/hide right chatframe
      if pfUI.chat and C.chat.right.enable == "1" then
        -- make sure the panel header stays hidden
        pfUI.chat.right.panelTop:SetShown(self.state)

        -- set chat visibility
        pfUI.chat.right:SetAlpha(self.state and 1 or 0)
      end

      -- show/hide damage meters
      if self.damage then
        local config, addon, frame, single, dual, show, hide = unpack(self.damage)
        if not self.state then show() else hide() end
      end

      -- show/hide threat meters
      if self.threat then
        local config, addon, frame, single, dual, show, hide = unpack(self.threat)
        if not self.state then show() else hide() end
      end

      -- show meters
      if not self.state then
        self.state = true
      else
        self.state = nil
      end
    end

    -- Anchors a docked window to the panel: fill it, or take its "LEFT" or
    -- "RIGHT" half in split mode.
    function pfUI.thirdparty.meters:Place(frame, half)
      local panel = pfUI.chat.right
      frame:ClearAllPoints()
      if half == "LEFT" then
        frame:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
        frame:SetPoint("BOTTOMRIGHT", panel, "BOTTOM", 0, 0)
      elseif half == "RIGHT" then
        frame:SetPoint("TOPLEFT", panel, "TOP", 0, 0)
        frame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
      else
        frame:SetAllPoints(panel)
      end
      frame:SetWidth(half and panel:GetWidth() / 2 or panel:GetWidth())
    end

    -- A meter with several windows docks its second one into the threat slot
    -- while that window exists. The slot is only claimed when free and only
    -- released by its owner. Returns whether the slot holds 'data'.
    function pfUI.thirdparty.meters:SetSecondary(data, present)
      if present and not self.threat then
        self.threat = data
      elseif not present and self.threat == data then
        self.threat = nil
      end
      return self.threat == data
    end
  end


  do -- bag sort addon
    pfUI.thirdparty.bagsort = nil
    -- Third-party sort addons (SortBags, MrPlow, etc.) override pfUI's built-
    -- in sorter by rebinding the existing pfUI.bag.{right,left}.sort buttons
    -- created in modules/bags.lua. First-come-first-served — if multiple
    -- third-party sorters are installed, the first to register wins.
    function pfUI.thirdparty.RegisterBagSort(name, bag, bagtooltip, bank, banktooltip)
      if pfUI.thirdparty.bagsort then return end
      if not pfUI.bag or not pfUI.bag.right or not pfUI.bag.right.sort then return end

      pfUI.thirdparty.bagsort = name

      -- Rebind bag (right) button
      local rb = pfUI.bag.right.sort
      rb:SetScript("OnClick", bag)
      rb:SetScript("OnEnter", function()
        rb.backdrop:SetBackdropBorderColor(1,1,.25,1)
        rb.texture:SetVertexColor(1,1,.25,1)
        if bagtooltip then bagtooltip() end
      end)

      -- Rebind bank (left) button
      if pfUI.bag.left and pfUI.bag.left.sort then
        local lb = pfUI.bag.left.sort
        lb:SetScript("OnClick", bank)
        lb:SetScript("OnEnter", function()
          lb.backdrop:SetBackdropBorderColor(1,1,.25,1)
          lb.texture:SetVertexColor(1,1,.25,1)
          if banktooltip then banktooltip() end
        end)
      end
    end
  end

  -- MrPlow Bag Sorting Addon.
  -- Vanilla: https://www.wowace.com/projects/mr-plow/files/288059
  -- TBC: https://www.wowace.com/projects/mr-plow/files/136162
  HookAddon("MrPlow", function()
    if C.thirdparty.mrplow.enable == "0" then return end

    EventUtil.RegisterOnceFrameEventAndCallback("PLAYER_ENTERING_WORLD", function()
      local MrPlowL = AceLibrary and AceLibrary("AceLocale-2.2"):new("MrPlow")
      if not (MrPlowL and MrPlowL["Bank"]) then return end

      pfUI.thirdparty.RegisterBagSort("MrPlow",
        function()
          MrPlow:Works()
        end,
        function()
          GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
          GameTooltip:SetText(MrPlowL["Mr Plow"])
          GameTooltip:AddLine(MrPlowL["The Works"],1,1,1)
          GameTooltip:Show()
        end,
        function()
          MrPlow:Works(MrPlowL["Bank"])
        end,
        function()
          GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
          GameTooltip:SetText(MrPlowL["Mr Plow"])
          GameTooltip:AddLine(MrPlowL["Bank"],1,1,1)
          GameTooltip:Show()
        end)
    end)
  end)

  -- ShaguDPS Damage Meter
  -- Vanilla: https://github.com/shagu/ShaguDPS
  -- TBC: https://github.com/shagu/ShaguDPS
  HookAddon("ShaguDPS", function()
    local docktable = { "shagudps", "ShaguDPS", "ShaguDPSWindow",
      function() -- single
        ShaguDPSWindow:ClearAllPoints()
        ShaguDPSWindow:SetAllPoints(pfUI.chat.right)
        ShaguDPSWindow:SetWidth(pfUI.chat.right:GetWidth())
        if ShaguDPSWindow.Resize then ShaguDPSWindow:Resize() end
      end,
      function() -- dual
        ShaguDPSWindow:ClearAllPoints()
        ShaguDPSWindow:SetPoint("TOPLEFT", pfUI.chat.right, "TOP", 0, 0)
        ShaguDPSWindow:SetPoint("BOTTOMRIGHT", pfUI.chat.right, "BOTTOMRIGHT", 0, 0)
        ShaguDPSWindow:SetWidth(pfUI.chat.right:GetWidth() / 2)
        if ShaguDPSWindow.Resize then ShaguDPSWindow:Resize() end
      end,
      function() -- show
        ShaguDPS.config.visible = 1
        ShaguDPS.window.Refresh(true)
      end,
      function() -- hide
        ShaguDPS.config.visible = 0
        ShaguDPS.window.Refresh(true)
      end
    }

    pfUI.thirdparty.meters:RegisterMeter("damage", docktable)

    if C.thirdparty.shagudps.skin == "1" then
      local hookRefresh = ShaguDPS.window.Refresh
      ShaguDPS.window.Refresh = function (arg1, arg2)
        hookRefresh(arg1, arg2)

        for wid=1,10 do
          local window = ShaguDPS.window[wid]

          -- legacy single-window support
          if wid == 1 and not window then
            window = ShaguDPS.window
          end

          if window then
            local _, chat_border = GetBorderSize("chat")

            window.title:Hide()
            window.title:SetPoint("TOPLEFT", 1, -1)
            window.title:SetPoint("TOPRIGHT", -1, -1)

            CreateBackdrop(window, chat_border, nil, (C.thirdparty.chatbg == "1" and .8))
            CreateBackdropShadow(window)

            local hook = window.Refresh
            if not window.pfRefreshHook then
              window.pfRefreshHook = window.Refresh
              window.Refresh = function(self, arg1, arg2)
                window.pfRefreshHook(self, arg1, arg2)

                -- keep backdrop hidden
                if C.thirdparty.shagudps.skin == "1" then
                  window:SetBackdrop(nil)
                  window.border:SetBackdrop(nil)
                end
              end
            end

            if C.thirdparty.chatbg == "1" and C.chat.global.custombg == "1" then
              local r, g, b, a = GetStringColor(C.chat.global.background)
              window.backdrop:SetBackdropColor(tonumber(r), tonumber(g), tonumber(b), tonumber(a))

              local r, g, b, a = GetStringColor(C.chat.global.border)
              window.backdrop:SetBackdropBorderColor(tonumber(r), tonumber(g), tonumber(b), tonumber(a))
            end

            -- skin buttons
            local buttons = {
              window.btnAnnounce, window.btnReset, window.btnSegment, window.btnMode,
              window.btnDamage, window.btnDPS, window.btnHeal, window.btnHPS,
              window.btnCurrent, window.btnOverall, window.btnWindow, window.btnSettings,
            }

            for _, button in pairs(buttons) do
              if button then
                button:SetHeight(14)
                CreateBackdrop(button, -1, true, .75)
                button:SetBackdropBorderColor(.4,.4,.4,1)

                if button:GetWidth() == 16 then
                  button:SetWidth(14)
                end
              end
            end

            window.border:Hide()
          end
        end
      end
    end
  end)

  -- GreedMeter Damage Meter
  -- Vanilla: https://github.com/iGreed/GreedMeter
  -- GreedMeter builds its windows lazily and supports several of them, so the
  -- frames are resolved at call time. The primary window takes the "damage"
  -- dock slot; a second window (GreedMeter.UI.frames[2]) takes the "threat"
  -- slot so the two tile the panel side-by-side. Docking triggers a
  -- LayoutBars/RefreshFrame so the bars refit the new width.
  HookAddon("GreedMeter", function()
    local UI = GreedMeter.UI

    local function frameAt(i)
      return UI and UI.frames and UI.frames[i]
    end
    local function primary()
      return (UI and UI.mainFrame) or getglobal("GreedMeterFrame1")
    end
    local function relayout(frame)
      if not UI then return end
      if UI.LayoutBars then UI:LayoutBars(frame) end
      if UI.RefreshFrame then UI:RefreshFrame(frame) end
    end

    local meters = pfUI.thirdparty.meters

    -- Builds a docktable for a window resolved through getframe(). half is
    -- the panel half it takes in split mode.
    local function BuildDock(name, getframe, half)
      return { "greedmeter", "GreedMeter", name,
        function() -- single
          local frame = getframe()
          if frame then meters:Place(frame) relayout(frame) end
        end,
        function() -- dual
          local frame = getframe()
          if frame then meters:Place(frame, half) relayout(frame) end
        end,
        function() -- show
          local frame = getframe()
          if frame then frame:Show() relayout(frame) end
        end,
        function() -- hide
          local frame = getframe()
          if frame then frame:Hide() end
        end
      }
    end

    local maindock = BuildDock("GreedMeterFrame1", primary, "RIGHT")
    local threatdock = BuildDock("GreedMeterFrame2", function() return frameAt(2) end, "LEFT")
    meters:RegisterMeter("damage", maindock)

    -- Only the first two windows fit; any beyond that float.
    local function SyncSecond()
      if meters.damage ~= maindock then return end
      local owned = meters:SetSecondary(threatdock, frameAt(2) ~= nil)
      meters:Resize()

      -- match the second window's visibility to the panel (the primary tracks it)
      if owned then
        local f1, f2 = primary(), frameAt(2)
        if f1 and f1:IsShown() then f2:Show() relayout(f2) else f2:Hide() end
      end
    end

    -- AddFrame and the login-time layout restore both go through
    -- CreateMeterFrame; RemoveFrame handles closing a window.
    hooksecurefunc(UI, "CreateMeterFrame", SyncSecond)
    hooksecurefunc(UI, "RemoveFrame", SyncSecond)
  end)

  -- CombatLedger Damage/Threat Meter
  -- Vanilla: https://github.com/akzkak/CombatLedger
  -- CombatLedger builds its windows at the first PLAYER_ENTERING_WORLD and
  -- supports several of them (CombatLedger.UIWindows, keyed by id), so frames
  -- are resolved at call time. The "main" window takes the "damage" dock slot.
  -- The lowest-numbered extra window takes the "threat" slot and keeps it
  -- until it closes, so the two split the panel. Any further windows float.
  HookAddon("CombatLedger", function()
    local CL, UI = CombatLedger, CombatLedger.UI
    local windows = CL.UIWindows
    local meters = pfUI.thirdparty.meters

    -- CombatLedger ships its own pfUI dock for the main window. It shares
    -- the "combatledger" config key and turns this dock on by itself.
    CL.TryRegisterPfuiDock = nop

    local shown  -- whether the panel shows the meters
    local second -- id of the docked extra window

    local function frameOf(id)
      local inst = id and windows[id]
      return inst and inst.frame
    end

    local function pickSecond()
      local best, bestnum
      for id, inst in pairs(windows) do
        local _, _, num = string.find(id, "^window(%d+)$")
        num = tonumber(num)
        if num and inst.frame and (not bestnum or num < bestnum) then
          best, bestnum = id, num
        end
      end
      return best
    end

    -- The Mode/Segment header buttons and the bars are sized from the window
    -- width, and CombatLedger refits them only on a resize drag or an
    -- appearance change. Fire that once per frame, after the docked widths
    -- settle.
    local queued
    local function relayout()
      if queued then return end
      queued = true
      RunNextFrame(function()
        queued = nil
        CL.FireAppearanceChanged()
      end)
    end

    local function place(frame, half)
      local width = frame:GetWidth()
      meters:Place(frame, half)
      if frame:GetWidth() ~= width then relayout() end
    end

    -- Docked windows can't be dragged or resized: that would pull them out of
    -- the panel and save the panel geometry as their floating layout.
    -- CombatLedger shows windows by itself (auto-show on combat, group
    -- changes, /cl show), so a docked window stays hidden while the panel is
    -- collapsed.
    local function dock(frame)
      if frame.pfDocked then return end
      frame.pfDocked = true
      frame:SetScript("OnDragStart", nil)
      frame:SetScript("OnDragStop", nil)
      frame.resizeGrip:EnableMouse(false)
      frame.resizeGrip:SetAlpha(0)
      frame:HookScript("OnShow", function()
        if not shown then frame:Hide() end
      end)
      if not shown then frame:Hide() end
    end

    local function BuildDock(name, getid, half)
      return { "combatledger", "CombatLedger", name,
        function() -- single
          local frame = frameOf(getid())
          if frame then place(frame) end
        end,
        function() -- dual
          local frame = frameOf(getid())
          if frame then place(frame, half) end
        end,
        function() -- show: unless the window's own rules hide it right now
          shown = true
          local id = getid()
          if frameOf(id) and not UI.IsSuppressedNow(id) then UI.ShowWindowById(id) end
        end,
        function() -- hide
          shown = nil
          local frame = frameOf(getid())
          if frame then frame:Hide() end
        end
      }
    end

    local maindock = BuildDock("CombatLedgerMainWindow", function() return "main" end, "RIGHT")
    local threatdock = BuildDock("CombatLedgerSecondWindow", function() return second end, "LEFT")
    meters:RegisterMeter("damage", maindock)

    -- login restore, "New Window" and closing a window change the set of
    -- frames; the dock follows
    local function Sync()
      if meters.damage ~= maindock then return end
      if not frameOf(second) then second = pickSecond() end

      dock(frameOf("main"))
      if meters:SetSecondary(threatdock, second ~= nil) then
        dock(frameOf(second))
      end
      meters:Resize()
    end

    hooksecurefunc(UI, "RestoreAllWindows", Sync)
    hooksecurefunc(UI, "CreateExtraWindow", Sync)
    hooksecurefunc(UI, "CloseExtraWindow", Sync)
  end)

  -- DPSMate Damage Meter
  -- Vanilla: https://github.com/Geigerkind/DPSMate
  -- TBC: https://github.com/Geigerkind/DPSMateTBC
  -- Repacks ship DPSMate under other folder names, so this waits on login and
  -- checks DPSMate's globals instead of HookAddon's folder lookup.
  EventUtil.ContinueOnPlayerLogin(function()
    if not DPSMate or not DPSMateSettings then return end

    -- DPSMate names each window "DPSMate_<name>" after its settings entry and
    -- the user can rename it at any time, so the first window is resolved on
    -- every call
    local function window()
      local first = DPSMateSettings.windows and DPSMateSettings.windows[1]
      return first and _G["DPSMate_"..first.name]
    end

    local function place(anchor, width)
      local frame = window()
      if not frame then return end
      local name = frame:GetName()

      frame:ClearAllPoints()
      frame:SetPoint("TOPLEFT", pfUI.chat.right, anchor, 0, 0)
      frame:SetPoint("BOTTOMRIGHT", pfUI.chat.right, "BOTTOMRIGHT", 0, 0)
      frame:SetWidth(width)
      _G[name.."_ScrollFrame"]:ClearAllPoints()
      _G[name.."_ScrollFrame"]:SetWidth(width)
      _G[name.."_ScrollFrame"]:SetPoint("TOPLEFT", _G[name.."_Head"], "BOTTOMLEFT", 0, 0)
      _G[name.."_ScrollFrame"]:SetPoint("BOTTOMRIGHT", pfUI.chat.right, "BOTTOMRIGHT", 0, pfUI.panel.right:GetHeight())
      _G[name.."_ScrollFrame_Child"]:SetWidth(width)
      _G[name.."_Resize"]:Hide()
    end

    local docktable = { "dpsmate", "DPSMate", "DPSMate",
      function() -- single
        place("TOPLEFT", pfUI.chat.right:GetWidth())
      end,
      function() -- dual
        place("TOP", pfUI.chat.right:GetWidth() / 2)
      end,
      function() -- show
        local frame = window()
        if frame then frame:Show() end
      end,
      function() -- hide
        local frame = window()
        if frame then frame:Hide() end
      end
    }

    pfUI.thirdparty.meters:RegisterMeter("damage", docktable)

    -- DPSMate rebuilds its windows at their saved positions whenever its
    -- settings change, so put the docked one back afterwards
    hooksecurefunc(DPSMate, "InitializeFrames", function()
      if pfUI.thirdparty.meters.damage == docktable then
        pfUI.thirdparty.meters:Resize()
      end
    end)

    if C.thirdparty.dpsmate.skin == "1" then
      if DPSMateSettings then
        -- set DPSMate appearance to match pfUI
        for w in pairs(DPSMateSettings["windows"]) do
          DPSMateSettings["windows"][w]["titlebarheight"] = 20
          DPSMateSettings["windows"][w]["titlebarfontsize"] = 12
          DPSMateSettings["windows"][w]["titlebarfont"] = "Accidental Presidency"
          DPSMateSettings["windows"][w]["titlebaropacity"] = 0

          DPSMateSettings["windows"][w]["titlebarfontcolor"][1] = 1
          DPSMateSettings["windows"][w]["titlebarfontcolor"][2] = 1
          DPSMateSettings["windows"][w]["titlebarfontcolor"][3] = 1

          DPSMateSettings["windows"][w]["barheight"] = 11
          DPSMateSettings["windows"][w]["barfontsize"] = 13
          DPSMateSettings["windows"][w]["bartexture"] = "normTex"
          DPSMateSettings["windows"][w]["barfont"] = "Accidental Presidency"

          DPSMateSettings["windows"][w]["opacity"] = 1
          DPSMateSettings["windows"][w]["contentbgtexture"] = "Solid Background"
          DPSMateSettings["windows"][w]["bgopacity"] = 0
          DPSMateSettings["windows"][w]["borderopacity"] = 0
        end

        if DPSMate.UpdatePointer then
          DPSMate:UpdatePointer()
        end
        DPSMate:InitializeFrames()

        for k, val in pairs(DPSMateSettings["windows"]) do
          local frame = _G["DPSMate_"..val["name"]]
          CreateBackdrop(frame, nil, nil, (C.thirdparty.chatbg == "1" and .8))
          CreateBackdropShadow(frame)

          if C.thirdparty.chatbg == "1" and C.chat.global.custombg == "1" then
            local r, g, b, a = GetStringColor(C.chat.global.background)
            frame.backdrop:SetBackdropColor(tonumber(r), tonumber(g), tonumber(b), tonumber(a))

            local r, g, b, a = GetStringColor(C.chat.global.border)
            frame.backdrop:SetBackdropBorderColor(tonumber(r), tonumber(g), tonumber(b), tonumber(a))
          end
        end
      end
    end
  end)
end)
