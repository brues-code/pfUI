pfUI:RegisterModule("castbar", function ()

  local font = C.castbar.use_unitfonts == "1" and pfUI.font_unit or pfUI.font_default
  local font_size = C.castbar.use_unitfonts == "1" and C.global.font_unit_size or C.global.font_size
  local rawborder, default_border = GetBorderSize("unitframes")
  local cbtexture = pfUI.media[C.appearance.castbar.texture]

  -- Castbar timer text: 1 decimal rounded half up (matches Blizzard spellbook
  -- display), or 2 decimals (default)
  local formatter = C_StringUtil.CreateNumericRuleFormatter()
  if C.unitframes.castbardecimals == "1" then
    formatter:AddBreakpoint({ threshold = 0, step = .1, format = "%.1f" })
  else
    formatter:AddBreakpoint({ threshold = 0, format = "%.2f" })
  end

  -- "cur / max": a cast counts up, a channel counts down
  local castText = {
    { property = Enum.DurationTextBindingProperty.ElapsedDuration, formatter = formatter },
    { property = Enum.DurationTextBindingProperty.TotalDuration, formatter = formatter },
  }
  local channelText = {
    { property = Enum.DurationTextBindingProperty.RemainingDuration, formatter = formatter },
    { property = Enum.DurationTextBindingProperty.TotalDuration, formatter = formatter },
  }

  -- The bar's fill and timer text both follow cb.duration on their own; only
  -- the pushback total in front of the text needs a refresh.
  local function UpdateTimerText(cb)
    if not cb.showtimer then return end
    local prefix = ""
    if cb.delay > 0 then
      prefix = "|cffffaaaa" .. (cb.isChannel and "-" or "+") .. formatter:FormatNumber(cb.delay) .. " |r "
    end
    cb.timer:SetTextFormat(prefix .. "{} / {}", cb.isChannel and channelText or castText)
    cb.timer:Enable()
  end

  -- STOP doesn't arrive for every cast (a synthetic cast has none, a remote
  -- unit's can be missed out of range), so the bar also clears at its end time.
  local function ArmExpiry(cb)
    if cb.expiry then cb.expiry:Cancel() end
    cb.expiry = C_Timer.NewTimer(cb.duration:GetRemainingDuration(), cb.onExpire)
  end

  -- Clear cast state on the bar and start the fade-out. The fill freezes where
  -- the cast stopped (SetMinMaxValues drops the timer). When `failed` is set for
  -- a cast that was actually in progress, the bar flashes full red before
  -- fading — the cancelled-cast indicator.
  local function ClearBar(cb, failed)
    if cb.expiry then cb.expiry:Cancel() end
    cb.expiry = nil
    cb.timer:Disable()
    if cb.active then
      cb.bar:SetMinMaxValues(0, 1)
      if failed then
        cb.bar:SetStatusBarColor(GetStringColor(C.appearance.castbar.failcolor))
        cb.bar:SetValue(1)
      else
        cb.bar:SetValue(cb.isChannel and cb.duration:GetRemainingPercent() or cb.duration:GetElapsedPercent())
      end
    end
    cb.active, cb.isChannel = nil, nil
    cb.activeName, cb.spellID = nil, nil
    cb.isTradeskill = nil
    cb.tradeskillTotal, cb.tradeskillCompleted, cb.tradeskillSpellID = nil, nil, nil
    cb.tradeskillSingle = nil
    cb.delay = 0
    if cb.craftbar then cb.craftbar:Hide() end
    if cb:IsShown() and not cb.fade:IsPlaying() then cb.fade:Play() end
  end

  -- "Spellname (N)" label for an active tradeskill merge — N is the number
  -- of crafts remaining. Falls back to the bare spell name when ≤1 left.
  local function UpdateTradeskillLabel(cb)
    if not cb.tradeskillTotal or not cb.activeName or not cb.showname then return end
    local remaining = cb.tradeskillTotal - (cb.tradeskillCompleted or 0)
    if remaining > 1 then
      cb.bar.left:SetFormattedText("%s (%d)", cb.activeName, remaining)
    else
      cb.bar.left:SetText(cb.activeName)
    end
  end

  -- Stretch the bar to span all queued crafts (Quartz-style merge): the bar
  -- fills continuously across the chain instead of resetting per craft.
  -- Also arms the per-craft spark — a thin marker that crosses the bar once
  -- per craft (so it moves N× faster than the main fill on an N-stack).
  local function EnterTradeskillMerge(cb, count)
    local start, single = cb.duration:GetStartTime(), cb.duration:GetTotalDuration()
    cb.tradeskillTotal = count
    cb.tradeskillCompleted = 0
    cb.tradeskillSpellID = cb.spellID
    cb.tradeskillSingle = single
    cb.craft:SetTimeFromStart(start, single)
    cb.duration:SetTimeFromStart(start, single * count)
    ArmExpiry(cb)
    cb.craftbar:Show()
    UpdateTradeskillLabel(cb)
  end

  -- Mark the start of craft 2..N within an active merge (called from the
  -- UNIT_SPELLCAST_START handler) and re-fit the bar's end to the crafts left.
  local function StartTradeskillCraft(cb)
    local now = GetTime()
    local remaining = cb.tradeskillTotal - cb.tradeskillCompleted
    cb.craft:SetTimeFromStart(now, cb.tradeskillSingle)
    cb.duration:SetTimeSpan(cb.duration:GetStartTime(), now + cb.tradeskillSingle * remaining)
    ArmExpiry(cb)
    UpdateTradeskillLabel(cb)
  end

  -- Stamp the bar with cast data and render text/icon/lag once. From here the
  -- bar's timer and text binding follow cb.duration without any Lua.
  local function StampBar(cb, name, tex, startMs, endMs, spellID, isChannel, delayMs, isTradeskill, rank, noInterrupt)
    cb.duration:SetTimeSpan(startMs / 1000, endMs / 1000)
    cb.active = true
    cb.isChannel = isChannel
    cb.spellID = spellID
    cb.activeName = name
    cb.isTradeskill = isTradeskill
    cb.delay = (delayMs or 0) / 1000
    cb.fade:Stop()
    cb:Show()

    -- Shield an uninterruptible cast. Not on the player's own bar: the flag is
    -- measured against the reader's own interrupts and silences, so on your own
    -- cast it answers a question nobody asked.
    SetCastbarShield(cb.bar, cb.icon, noInterrupt and cb.unitstr ~= "player", isChannel)

    -- Rank: prefer the value the UNIT_SPELLCAST_* event delivered (arg5, passed
    -- through by RefreshBar). Only the retarget re-poll has no event in hand, so
    -- it falls back to a lookup.
    if not rank and spellID then
      rank = C_Spell.GetSpellSubtext(spellID) or ""
    end
    rank = rank or ""
    local spellname = (cb.showname and name) and (name .. " ") or ""
    local rankstr = (cb.showrank and rank ~= "") and string.format("|cffaaffcc[%s]|r", rank) or ""
    cb.bar.left:SetText(spellname .. rankstr)

    if tex and cb.showicon then
      local size = cb:GetHeight()
      cb.icon:Show()
      cb.icon:SetSize(size, size)
      cb.icon.texture:SetTexture(tex)
      cb.bar:SetPoint("TOPLEFT", cb.icon, "TOPRIGHT", cb.spacing, 0)
    else
      cb.bar:SetPoint("TOPLEFT", cb, 0, 0)
      cb.icon:Hide()
    end

    if cb.showlag then
      local _, _, lag = GetNetStats()
      cb.bar.lag:SetWidth(math.min(cb:GetWidth(), cb:GetWidth() / cb.duration:GetTotalDuration() * (lag/1000)))
      cb.bar.lag:Show()
    else
      cb.bar.lag:Hide()
    end

    cb.bar:SetTimerDuration(cb.duration, Enum.StatusBarInterpolation.Immediate,
      isChannel and Enum.StatusBarTimerDirection.RemainingTime or Enum.StatusBarTimerDirection.ElapsedTime)
    UpdateTimerText(cb)
    ArmExpiry(cb)
  end

  -- One-shot poll: read C_Spell for the bar's unit, stamp or clear. Called
  -- from event handlers (cast start, target/focus change), never per-frame.
  local function RefreshBar(cb, rank)
    local query = cb.unitstr
    if not UnitExists(query) then
      ClearBar(cb)
      return
    end
    local name, _, tex, startMs, endMs, isTradeskill, _, noInterrupt, spellID, _, delayMs = C_Spell.UnitCastingInfo(query)
    local isChan
    if not name then
      name, _, tex, startMs, endMs, _, noInterrupt, spellID = C_Spell.UnitChannelInfo(query)
      isChan = true
    end
    -- Synthetic fallback for abilities the engine treats as instant-cast but
    -- that have a meaningful wait window (e.g. Turtle WoW Steady Shot on the
    -- ranged-swing queue). Per-unit table populated by module-side hooks.
    if not name and pfUI.synthetic_casts and pfUI.synthetic_casts[query] then
      local s = pfUI.synthetic_casts[query]
      if s.endMs > GetTime() * 1000 then
        name, tex, startMs, endMs, spellID = s.name, s.icon, s.startMs, s.endMs, s.spellID
        isChan = nil
      end
    end
    if name and startMs and endMs then
      StampBar(cb, name, tex, startMs, endMs, spellID, isChan, delayMs, isTradeskill, rank, noInterrupt)
    else
      ClearBar(cb)
    end
  end

  local function CreateCastbar(name, parent, unitstr)
    local cb = CreateFrame("Frame", name, parent or UIParent)

    cb:SetHeight(C.global.font_size * 1.5)
    cb:SetFrameStrata("MEDIUM")
    cb:SetFrameLevel(8)

    cb.unitstr = unitstr
    cb.delay = 0
    cb.duration = C_DurationUtil.CreateDuration()
    cb.craft = C_DurationUtil.CreateDuration() -- the current craft of a tradeskill merge
    cb.onExpire = function() ClearBar(cb) end

    -- icon
    cb.icon = CreateFrame("Frame", nil, cb)
    cb.icon:SetPoint("TOPLEFT", 0, 0)
    cb.icon:SetSize(16, 16)

    cb.icon.texture = cb.icon:CreateTexture(nil, "OVERLAY")
    cb.icon.texture:SetAllPoints()
    cb.icon.texture:SetTexCoord(.08, .92, .08, .92)
    CreateBackdrop(cb.icon, default_border)

    -- statusbar
    cb.bar = CreateFrame("StatusBar", nil, cb)
    cb.bar:SetStatusBarTexture(cbtexture)
    cb.bar:ClearAllPoints()
    cb.bar:SetAllPoints(cb)
    cb.bar:SetMinMaxValues(0, 100)
    cb.bar:SetValue(20)
    local r,g,b,a = strsplit(",", C.appearance.castbar.castbarcolor)
    cb.bar:SetStatusBarColor(r,g,b,a)
    CreateBackdrop(cb.bar, default_border)
    CreateBackdropShadow(cb.bar)

    -- text left
    cb.bar.left = cb.bar:CreateFontString("Status", "OVERLAY", "GameFontNormal")
    cb.bar.left:ClearAllPoints()
    cb.bar.left:SetPoint("TOPLEFT", cb.bar, "TOPLEFT", 3 + C.castbar[unitstr].txtleftoffx, C.castbar[unitstr].txtleftoffy)
    cb.bar.left:SetPoint("BOTTOMRIGHT", cb.bar, "BOTTOMRIGHT", -3 + C.castbar[unitstr].txtleftoffx, C.castbar[unitstr].txtleftoffy)
    cb.bar.left:SetNonSpaceWrap(false)
    cb.bar.left:SetFontObject(GameFontWhite)
    cb.bar.left:SetTextColor(1,1,1,1)
    cb.bar.left:SetFont(font, font_size, "OUTLINE")
    cb.bar.left:SetJustifyH(C.castbar[unitstr].namealign or "LEFT")

    -- text right
    cb.bar.right = cb.bar:CreateFontString("Status", "OVERLAY", "GameFontNormal")
    cb.bar.right:ClearAllPoints()
    cb.bar.right:SetPoint("TOPLEFT", cb.bar, "TOPLEFT", 3 + C.castbar[unitstr].txtrightoffx, C.castbar[unitstr].txtrightoffy)
    cb.bar.right:SetPoint("BOTTOMRIGHT", cb.bar, "BOTTOMRIGHT", -3 + C.castbar[unitstr].txtrightoffx, C.castbar[unitstr].txtrightoffy)
    cb.bar.right:SetNonSpaceWrap(false)
    cb.bar.right:SetFontObject(GameFontWhite)
    cb.bar.right:SetTextColor(1,1,1,1)
    cb.bar.right:SetFont(font, font_size, "OUTLINE")
    cb.bar.right:SetJustifyH(C.castbar[unitstr].timealign or "RIGHT")

    cb.timer = C_DurationUtil.CreateDurationTextBinding()
    cb.timer:SetFontString(cb.bar.right)
    cb.timer:SetDuration(cb.duration)

    cb.bar.lag = cb.bar:CreateTexture(nil, "OVERLAY")
    cb.bar.lag:SetPoint("TOPRIGHT", cb.bar, "TOPRIGHT", 0, 0)
    cb.bar.lag:SetPoint("BOTTOMRIGHT", cb.bar, "BOTTOMRIGHT", 0, 0)
    cb.bar.lag:SetColorTexture(1,.2,.2,.2)

    -- Per-craft progress spark for tradeskill merge — a thin vertical line
    -- that crosses the bar once per craft in the chain (so on a 5-stack it
    -- moves 5x faster than the main fill). It rides the edge of an invisible
    -- fill that follows cb.craft, shown while a merge is active, and snaps
    -- back to the left each time StartTradeskillCraft restarts the craft.
    cb.craftbar = CreateFrame("StatusBar", nil, cb.bar)
    cb.craftbar:SetAllPoints(cb.bar)
    cb.craftbar:SetColorFill(1, 1, 1, 0)
    cb.craftbar:SetTimerDuration(cb.craft, Enum.StatusBarInterpolation.Immediate, Enum.StatusBarTimerDirection.ElapsedTime)
    cb.craftbar:Hide()

    cb.craftbar.spark = cb.craftbar:CreateTexture(nil, "OVERLAY")
    cb.craftbar.spark:SetColorTexture(1, 1, 1, 0.8)
    cb.craftbar.spark:SetWidth(2)
    cb.craftbar.spark:SetPoint("TOPRIGHT", cb.craftbar:GetStatusBarTexture(), "TOPRIGHT")
    cb.craftbar.spark:SetPoint("BOTTOMRIGHT", cb.craftbar:GetStatusBarTexture(), "BOTTOMRIGHT")

    -- Fade-out after a cast ends. The bar is hidden while idle; unlock mode
    -- keeps it shown for dragging.
    cb.fade = cb:CreateAnimationGroup()
    local fade = cb.fade:CreateAnimation("Alpha")
    fade:SetChange(-1)
    fade:SetDuration(.4)
    cb.fade:SetScript("OnFinished", function()
      if not (cb.drag and cb.drag:IsShown()) then cb:Hide() end
    end)

    -- Cast lifecycle, entirely on ClassicAPI's UNIT_SPELLCAST_* events. They
    -- fire per unit token: arg1=="player" for the player's own casts, and the
    -- remote token(s) ("target", "focus", ...) for other units -- so one set of
    -- events drives every bar with no Nampower dependency. The handler routes an
    -- event to this bar when arg1 matches its unit, or -- since the player's own
    -- casts only ever fire arg1=="player" -- when the bar's unit resolves to the
    -- player (target=self). PLAYER_TARGET/FOCUS_CHANGED re-polls so a unit
    -- already mid-cast when it becomes the target/focus still shows.
    -- Filter to this bar's unit, plus "player" for the target/focus bars: the
    -- player's own casts only ever fire arg1=="player", so a self-targeted cast
    -- has to reach them too (nil for the player bar itself, which the filter
    -- skips). This only narrows what arrives -- the arg1/UnitIsUnit test below
    -- still decides whether the bar acts on it.
    local selfunit = unitstr ~= "player" and "player" or nil
    cb:RegisterUnitEvent("UNIT_SPELLCAST_START", unitstr, selfunit)
    cb:RegisterUnitEvent("UNIT_SPELLCAST_STOP", unitstr, selfunit)
    cb:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", unitstr, selfunit)
    cb:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", unitstr, selfunit)
    cb:RegisterUnitEvent("UNIT_SPELLCAST_DELAYED", unitstr, selfunit)
    cb:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", unitstr, selfunit)
    cb:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", unitstr, selfunit)
    cb:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", unitstr, selfunit)
    cb:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", unitstr, selfunit)
    if unitstr == "target" then
      cb:RegisterEvent("PLAYER_TARGET_CHANGED")
    elseif unitstr == "focus" then
      cb:RegisterEvent("PLAYER_FOCUS_CHANGED")
    end
    -- The shield can flip mid-cast (the caster gains or loses an aura that
    -- blocks interrupts). These only fire for target and focus.
    if unitstr == "target" or unitstr == "focus" then
      cb:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTIBLE", unitstr)
      cb:RegisterUnitEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", unitstr)
    end

    cb:SetScript("OnEvent", function()
      local unit = this.unitstr

      if event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" then
        RefreshBar(this)
        return
      end

      -- UNIT_SPELLCAST_* fire per unit token (arg1). Handle an event when it's
      -- for this bar's unit, or -- since the player's own casts only ever fire
      -- arg1=="player" -- when this bar's unit currently resolves to the player
      -- (target=self / focus=self).
      -- Args: arg1=unit, arg2=castGUID, arg3=spellID, arg4=name, arg5=rank.
      if arg1 ~= unit and not (arg1 == "player" and UnitIsUnit(unit, "player")) then
        return
      end

      if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
        -- START also fires per craft in a same-spell chain, so an active merge
        -- just resyncs the current craft's spark/label instead of restamping.
        if this.tradeskillTotal then
          StartTradeskillCraft(this)
        else
          RefreshBar(this, arg5)
          if this.isTradeskill and (this.pendingTradeskillCount or 0) > 1
              and C.castbar.player.mergetradeskill == "1" then
            EnterTradeskillMerge(this, this.pendingTradeskillCount)
          end
          this.pendingTradeskillCount = nil
        end
      elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- Per-craft completion during a tradeskill merge (arg3 = spellID):
        -- count and clear when the chain is done. A no-op for normal casts,
        -- which are cleared by UNIT_SPELLCAST_STOP.
        if this.tradeskillTotal and arg3 == this.tradeskillSpellID then
          this.tradeskillCompleted = this.tradeskillCompleted + 1
          if this.tradeskillCompleted >= this.tradeskillTotal then
            ClearBar(this)
          else
            UpdateTradeskillLabel(this)
          end
        end
      elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        -- A channel's stop can arrive after a following cast already claimed
        -- the bar (channel->cast transition); only clear if a channel is
        -- actually being shown, so it doesn't wipe an active cast bar.
        if this.isChannel then ClearBar(this) end
      elseif event == "UNIT_SPELLCAST_STOP" then
        -- STOP fires between crafts in a merge too (each craft is a new cast);
        -- UNIT_SPELLCAST_SUCCEEDED owns the count, so only a non-merge cast
        -- clears here.
        if not this.tradeskillTotal then ClearBar(this) end
      elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        ClearBar(this, true)
      elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" or event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
        if this.active then
          SetCastbarShield(this.bar, this.icon, event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE", this.isChannel)
        end
      elseif event == "UNIT_SPELLCAST_DELAYED" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
        -- Pushback: a cast delayed later or a channel shortened. Following
        -- Quartz, re-read just the times and accumulate the shift into a running
        -- this.delay for the +/- indicator, rather than a full restamp (which
        -- would reset that total and re-render icon/text). Pushback moves the
        -- end time while the start stays put, so we diff the end. delay is a
        -- positive magnitude; UpdateTimerText signs it "+" for casts and "-"
        -- for channels. Skipped during a tradeskill merge.
        if this.active and not this.tradeskillTotal then
          local duration
          if this.isChannel then
            duration = UnitChannelDuration(unit)
          else
            duration = UnitCastingDuration(unit)
          end
          if duration then
            local shift = duration:GetEndTime() - this.duration:GetEndTime()
            this.delay = this.delay + (this.isChannel and -shift or shift)
            this.duration:Assign(duration)
            UpdateTimerText(this)
            ArmExpiry(this)
          end
        end
      end
    end)

    cb:Hide()
    return cb
  end

  pfUI.castbar = CreateFrame("Frame", "pfCastBar", UIParent)

  -- hide blizzard
  if C.castbar.player.hide_blizz == "1" then
    CastingBarFrame:SetScript("OnShow", function() CastingBarFrame:Hide() end)
    CastingBarFrame:UnregisterAllEvents()
    CastingBarFrame:Hide()
  end

  -- [[ pfPlayerCastbar ]] --
  if C.castbar.player.hide_pfui == "0" then
    pfUI.castbar.player = CreateCastbar("pfPlayerCastbar", UIParent, "player")
    pfUI.castbar.player.showicon = C.castbar.player.showicon == "1" and true or nil
    pfUI.castbar.player.showname = C.castbar.player.showname == "1" and true or nil
    pfUI.castbar.player.showtimer = C.castbar.player.showtimer == "1" and true or nil
    pfUI.castbar.player.showlag = C.castbar.player.showlag == "1" and true or nil
    pfUI.castbar.player.showrank = C.castbar.player.showrank == "1" and true or nil
    pfUI.castbar.player.spacing = default_border * 2 + tonumber(C.unitframes.player.pspace) * GetPerfectPixel()

    if pfUI.uf.player then
      local anchor = pfUI.uf.player.portrait:GetHeight() > pfUI.uf.player:GetHeight() and pfUI.uf.player.power or pfUI.uf.player
      local width = C.castbar.player.width ~= "-1" and C.castbar.player.width or anchor:GetWidth()
      pfUI.castbar.player:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -pfUI.castbar.player.spacing)
      pfUI.castbar.player:SetWidth(width)
    else
      local width = C.castbar.player.width ~= "-1" and C.castbar.player.width or 200
      pfUI.castbar.player:SetPoint("CENTER", 0, -200)
      pfUI.castbar.player:SetWidth(width)
    end

    if C.castbar.player.height ~= "-1" then
      pfUI.castbar.player:SetHeight(C.castbar.player.height)
    end

    UpdateMovable(pfUI.castbar.player)

    -- Tradeskill merge: hook DoTradeSkill so the player castbar knows the
    -- requested count before the first UNIT_SPELLCAST_START fires. Always-on
    -- hook (the config knob is read at event time so toggling takes effect on
    -- the next craft without a /reload). DoTradeSkill is synchronous; the
    -- server roundtrip to UNIT_SPELLCAST_START gives us plenty of time.
    hooksecurefunc("DoTradeSkill", function(index, num)
      if pfUI.castbar.player then
        pfUI.castbar.player.pendingTradeskillCount = tonumber(num) or 1
      end
    end)
  end

  -- [[ pfTargetCastbar ]] --
  if C.castbar.target.hide_pfui == "0" then
    pfUI.castbar.target = CreateCastbar("pfTargetCastbar", UIParent, "target")
    pfUI.castbar.target.showicon = C.castbar.target.showicon == "1" and true or nil
    pfUI.castbar.target.showname = C.castbar.target.showname == "1" and true or nil
    pfUI.castbar.target.showtimer = C.castbar.target.showtimer == "1" and true or nil
    pfUI.castbar.target.showlag = C.castbar.target.showlag == "1" and true or nil
    pfUI.castbar.target.showrank = C.castbar.target.showrank == "1" and true or nil
    pfUI.castbar.target.spacing = default_border * 2 + tonumber(C.unitframes.target.pspace) * GetPerfectPixel()

    if pfUI.uf.target then
      local anchor = pfUI.uf.target.portrait:GetHeight() > pfUI.uf.target:GetHeight() and pfUI.uf.target.power or pfUI.uf.target
      local width = C.castbar.target.width ~= "-1" and C.castbar.target.width or anchor:GetWidth()
      pfUI.castbar.target:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -pfUI.castbar.target.spacing)
      pfUI.castbar.target:SetWidth(width)
    else
      local width = C.castbar.target.width ~= "-1" and C.castbar.target.width or 200
      pfUI.castbar.target:SetPoint("CENTER", 0, -225)
      pfUI.castbar.target:SetWidth(width)
    end

    if C.castbar.target.height ~= "-1" then
      pfUI.castbar.target:SetHeight(C.castbar.target.height)
    end

    UpdateMovable(pfUI.castbar.target)
  end

  -- [[ pfFocusCastbar ]] --
  if C.castbar.focus.hide_pfui == "0" and pfUI.uf.focus then
    pfUI.castbar.focus = CreateCastbar("pfFocusCastbar", UIParent, "focus")
    pfUI.castbar.focus.showicon = C.castbar.focus.showicon == "1" and true or nil
    pfUI.castbar.focus.showname = C.castbar.focus.showname == "1" and true or nil
    pfUI.castbar.focus.showtimer = C.castbar.focus.showtimer == "1" and true or nil
    pfUI.castbar.focus.showlag = C.castbar.focus.showlag == "1" and true or nil
    pfUI.castbar.focus.showrank = C.castbar.focus.showrank == "1" and true or nil
    pfUI.castbar.focus.spacing = default_border * 2 + tonumber(C.unitframes.focus.pspace) * GetPerfectPixel()

    local anchor = pfUI.uf.focus.portrait:GetHeight() > pfUI.uf.focus:GetHeight() and pfUI.uf.focus.power or pfUI.uf.focus
    local width = C.castbar.focus.width ~= "-1" and C.castbar.focus.width or anchor:GetWidth()
    pfUI.castbar.focus:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -pfUI.castbar.focus.spacing)
    pfUI.castbar.focus:SetWidth(width)

    if C.castbar.focus.height ~= "-1" then
      pfUI.castbar.focus:SetHeight(C.castbar.focus.height)
    end

    UpdateMovable(pfUI.castbar.focus)
  end
end)