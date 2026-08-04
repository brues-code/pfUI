pfUI:RegisterModule("castbar", function ()

  local font = C.castbar.use_unitfonts == "1" and pfUI.font_unit or pfUI.font_default
  local font_size = C.castbar.use_unitfonts == "1" and C.global.font_unit_size or C.global.font_size
  local rawborder, default_border = GetBorderSize("unitframes")
  local cbtexture = pfUI.media[C.appearance.castbar.texture]

  -- Helper function for castbar timer formatting
  local function FormatCastbarTime(value)
    if C.unitframes.castbardecimals == "1" then
      -- 1 decimal, round half up (matches Blizzard spellbook display)
      return string.format("%.1f", floor(value * 10 + 0.5) / 10)
    else
      -- 2 decimals (default)
      return string.format("%.2f", value)
    end
  end

  -- Clear cast state on the bar and start the fade-out. On a normal end the bar
  -- is left at its current fill (a completed cast is already ~full; nothing
  -- snaps to full, which used to flash for a frame when the next cast stamped
  -- the bar). When `failed` is set for a cast that was actually in progress, the
  -- bar flashes full red before fading — the cancelled-cast indicator.
  local function ClearBar(cb, failed)
    local wasActive = cb.endTime ~= nil
    cb.startTime, cb.endTime, cb.isChannel = nil, nil, nil
    cb.activeName, cb.spellID = nil, nil
    cb.isTradeskill = nil
    cb.tradeskillTotal, cb.tradeskillCompleted, cb.tradeskillSpellID = nil, nil, nil
    cb.tradeskillSingleMs, cb.currentCraftStart = nil, nil
    cb.lastMax = nil
    cb.delay = 0
    if failed and wasActive then
      cb.bar:SetStatusBarColor(GetStringColor(C.appearance.castbar.failcolor))
      cb.bar:SetMinMaxValues(0, 1)
      cb.bar:SetValue(1)
    end
    if cb.bar.spark then cb.bar.spark:Hide() end
    cb.fadeout = 1
  end

  -- "Spellname (N)" label for an active tradeskill merge — N is the number
  -- of crafts remaining. Falls back to the bare spell name when ≤1 left.
  local function UpdateTradeskillLabel(cb)
    if not cb.tradeskillTotal or not cb.activeName or not cb.showname then return end
    local remaining = cb.tradeskillTotal - (cb.tradeskillCompleted or 0)
    if remaining > 1 then
      cb.bar.left:SetText(string.format("%s (%d)", cb.activeName, remaining))
    else
      cb.bar.left:SetText(cb.activeName)
    end
  end

  -- Stretch the bar to span all queued crafts (Quartz-style merge): the bar
  -- fills continuously across the chain instead of resetting per craft.
  -- Also arms the per-craft spark — a thin marker that crosses the bar once
  -- per craft (so it moves N× faster than the main fill on an N-stack).
  local function EnterTradeskillMerge(cb, startMs, endMs, count)
    cb.tradeskillTotal = count
    cb.tradeskillCompleted = 0
    cb.tradeskillSpellID = cb.spellID
    local single = endMs - startMs
    cb.tradeskillSingleMs = single
    cb.currentCraftStart = startMs
    local mergedEnd = startMs + single * count
    cb.endTime = mergedEnd
    local duration = (mergedEnd - startMs) / 1000
    cb.bar:SetMinMaxValues(0, duration)
    cb.lastMax = duration
    if cb.bar.spark then cb.bar.spark:Show() end
    UpdateTradeskillLabel(cb)
  end

  -- Mark the start of craft 2..N within an active merge (called from the
  -- UNIT_SPELLCAST_START handler). Resets the per-craft spark to the left
  -- edge of the bar.
  local function StartTradeskillCraft(cb)
    cb.currentCraftStart = GetTime() * 1000
    local remaining = cb.tradeskillTotal - (cb.tradeskillCompleted or 0)
    cb.endTime = cb.currentCraftStart + cb.tradeskillSingleMs * remaining
    local duration = (cb.endTime - cb.startTime) / 1000
    cb.bar:SetMinMaxValues(0, duration)
    cb.lastMax = duration
    UpdateTradeskillLabel(cb)
  end

  -- Stamp the bar with cast data and render text/icon/lag once. OnUpdate
  -- then animates the fill from this state without touching C_Spell.
  local function StampBar(cb, name, tex, startMs, endMs, spellID, isChannel, delayMs, isTradeskill, rank)
    cb.startTime = startMs
    cb.endTime = endMs
    cb.isChannel = isChannel
    cb.spellID = spellID
    cb.activeName = name
    cb.isTradeskill = isTradeskill
    cb.delay = (delayMs or 0) / 1000
    cb:SetAlpha(1)
    cb.fadeout = nil

    cb.bar:SetStatusBarColor(GetStringColor(C.appearance.castbar[isChannel and "channelcolor" or "castbarcolor"]))

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

    local duration = (endMs - startMs) / 1000
    if cb.showlag then
      local _, _, lag = GetNetStats()
      cb.bar.lag:SetWidth(math.min(cb:GetWidth(), cb:GetWidth() / duration * (lag/1000)))
      cb.bar.lag:Show()
    else
      cb.bar.lag:Hide()
    end

    cb.bar:SetMinMaxValues(0, duration)
    cb.lastMax = duration

    -- Prime the fill on this frame. StampBar otherwise leaves the previous
    -- value in place (ClearBar, run on the prior cast's STOP, leaves it full),
    -- so the bar would flash full for the frame between here and the next
    -- OnUpdate tick. Reset the throttle too so the timer text updates promptly.
    local nowSec = GetTime()
    local cur = isChannel and (endMs / 1000 - nowSec) or (nowSec - startMs / 1000)
    if cur < 0 then cur = 0 elseif cur > duration then cur = duration end
    cb.bar:SetValue(cur)
    cb.tick = 0
  end

  -- One-shot poll: read C_Spell for the bar's unit, stamp or clear. Called
  -- from event handlers (cast start, target/focus change), never per-frame.
  local function RefreshBar(cb, rank)
    local query = cb.unitstr ~= "" and cb.unitstr or cb.unitname
    if not query or (cb.unitstr ~= "" and not UnitExists(cb.unitstr)) then
      ClearBar(cb)
      return
    end
    local name, _, tex, startMs, endMs, isTradeskill, _, _, spellID, _, delayMs = C_Spell.UnitCastingInfo(query)
    local isChan
    if not name then
      name, _, tex, startMs, endMs, _, _, spellID = C_Spell.UnitChannelInfo(query)
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
      StampBar(cb, name, tex, startMs, endMs, spellID, isChan, delayMs, isTradeskill, rank)
    else
      ClearBar(cb)
    end
  end

  local function CreateCastbar(name, parent, unitstr, unitname)
    local cb = CreateFrame("Frame", name, parent or UIParent)

    cb:SetHeight(C.global.font_size * 1.5)
    cb:SetFrameStrata("MEDIUM")
    cb:SetFrameLevel(8)

    cb.unitstr = unitstr
    cb.unitname = unitname

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
    cb.bar.left = cb.bar:CreateFontString("Status", "DIALOG", "GameFontNormal")
    cb.bar.left:ClearAllPoints()
    cb.bar.left:SetPoint("TOPLEFT", cb.bar, "TOPLEFT", 3 + C.castbar[unitstr].txtleftoffx, C.castbar[unitstr].txtleftoffy)
    cb.bar.left:SetPoint("BOTTOMRIGHT", cb.bar, "BOTTOMRIGHT", -3 + C.castbar[unitstr].txtleftoffx, C.castbar[unitstr].txtleftoffy)
    cb.bar.left:SetNonSpaceWrap(false)
    cb.bar.left:SetFontObject(GameFontWhite)
    cb.bar.left:SetTextColor(1,1,1,1)
    cb.bar.left:SetFont(font, font_size, "OUTLINE")
    cb.bar.left:SetJustifyH(C.castbar[unitstr].namealign or "LEFT")

    -- text right
    cb.bar.right = cb.bar:CreateFontString("Status", "DIALOG", "GameFontNormal")
    cb.bar.right:ClearAllPoints()
    cb.bar.right:SetPoint("TOPLEFT", cb.bar, "TOPLEFT", 3 + C.castbar[unitstr].txtrightoffx, C.castbar[unitstr].txtrightoffy)
    cb.bar.right:SetPoint("BOTTOMRIGHT", cb.bar, "BOTTOMRIGHT", -3 + C.castbar[unitstr].txtrightoffx, C.castbar[unitstr].txtrightoffy)
    cb.bar.right:SetNonSpaceWrap(false)
    cb.bar.right:SetFontObject(GameFontWhite)
    cb.bar.right:SetTextColor(1,1,1,1)
    cb.bar.right:SetFont(font, font_size, "OUTLINE")
    cb.bar.right:SetJustifyH(C.castbar[unitstr].timealign or "RIGHT")

    cb.bar.lag = cb.bar:CreateTexture(nil, "OVERLAY")
    cb.bar.lag:SetPoint("TOPRIGHT", cb.bar, "TOPRIGHT", 0, 0)
    cb.bar.lag:SetPoint("BOTTOMRIGHT", cb.bar, "BOTTOMRIGHT", 0, 0)
    cb.bar.lag:SetTexture(1,.2,.2,.2)

    -- Per-craft progress spark for tradeskill merge — a thin vertical line
    -- that crosses the bar once per craft in the chain (so on a 5-stack it
    -- moves 5x faster than the main fill). Position is updated by OnUpdate
    -- while a merge is active; hidden otherwise.
    cb.bar.spark = cb.bar:CreateTexture(nil, "OVERLAY")
    cb.bar.spark:SetTexture(1, 1, 1, 0.8)
    cb.bar.spark:SetWidth(2)
    cb.bar.spark:SetPoint("TOP", cb.bar, "TOPLEFT", 0, 0)
    cb.bar.spark:SetPoint("BOTTOM", cb.bar, "BOTTOMLEFT", 0, 0)
    cb.bar.spark:Hide()

    -- OnUpdate animates the bar fill and fades it out on completion. All
    -- state transitions (cast start/stop/interrupt, channel start/stop,
    -- pushback) come from the event handler below — we never poll C_Spell
    -- here.
    cb:SetScript("OnUpdate", function()
      if (this.tick or 0) > GetTime() then return end
      this.tick = GetTime() + 0.020 -- ~50 FPS

      if this.drag and this.drag:IsShown() then
        this:SetAlpha(1)
        return
      end

      if this.fadeout and this:GetAlpha() > 0 then
        this:SetAlpha(this:GetAlpha() - 0.05)
        if this:GetAlpha() <= 0 then this.fadeout = nil end
        return
      end

      if not this.endTime then
        if this:GetAlpha() ~= 0 then this:SetAlpha(0) end
        return
      end

      -- Non-player bars: if the unit disappears (target died / detarget),
      -- drop the bar immediately.
      if this.unitstr ~= "" and this.unitstr ~= "player" and not UnitExists(this.unitstr) then
        ClearBar(this)
        return
      end

      local now = GetTime()
      local endSec = this.endTime / 1000
      if now >= endSec then
        ClearBar(this)
        return
      end

      local startSec = this.startTime / 1000
      local max = endSec - startSec
      local cur = this.isChannel and (endSec - now) or (now - startSec)
      if cur > max then cur = max end
      if cur < 0 then cur = 0 end

      this.bar:SetValue(cur)

      -- Per-craft spark for a tradeskill merge: position by (now - current
      -- craft's start) / single-craft duration, clamped to [0, 1]. Snaps back
      -- to the left edge each time StartTradeskillCraft fires for craft N+1.
      if this.tradeskillTotal and this.tradeskillSingleMs and this.currentCraftStart then
        local craftElapsed = now * 1000 - this.currentCraftStart
        local p = craftElapsed / this.tradeskillSingleMs
        if p < 0 then p = 0 elseif p > 1 then p = 1 end
        local x = p * this.bar:GetWidth() - 1
        this.bar.spark:ClearAllPoints()
        this.bar.spark:SetPoint("TOP", this.bar, "TOPLEFT", x, 0)
        this.bar.spark:SetPoint("BOTTOM", this.bar, "BOTTOMLEFT", x, 0)
      end

      if this.showtimer then
        if (this.delay or 0) > 0 then
          local prefix = "|cffffaaaa" .. (this.isChannel and "-" or "+") .. FormatCastbarTime(this.delay) .. " |r "
          this.bar.right:SetText(prefix .. FormatCastbarTime(cur) .. " / " .. FormatCastbarTime(max))
        else
          this.bar.right:SetText(FormatCastbarTime(cur) .. " / " .. FormatCastbarTime(max))
        end
      end
    end)

    -- Cast lifecycle, entirely on ClassicAPI's UNIT_SPELLCAST_* events. They
    -- fire per unit token: arg1=="player" for the player's own casts, and the
    -- remote token(s) ("target", "focus", ...) for other units -- so one set of
    -- events drives every bar with no Nampower dependency. The handler routes an
    -- event to this bar when arg1 matches its unit, or -- since the player's own
    -- casts only ever fire arg1=="player" -- when the bar's unit resolves to the
    -- player (target=self). PLAYER_TARGET/FOCUS_CHANGED re-polls so a unit
    -- already mid-cast when it becomes the target/focus still shows.
    cb:RegisterEvent("UNIT_SPELLCAST_START")
    cb:RegisterEvent("UNIT_SPELLCAST_STOP")
    cb:RegisterEvent("UNIT_SPELLCAST_FAILED")
    cb:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
    cb:RegisterEvent("UNIT_SPELLCAST_DELAYED")
    cb:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    cb:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
    cb:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
    cb:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE")
    if unitstr == "target" then
      cb:RegisterEvent("PLAYER_TARGET_CHANGED")
    elseif unitstr == "focus" then
      cb:RegisterEvent("PLAYER_FOCUS_CHANGED")
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
            EnterTradeskillMerge(this, this.startTime, this.endTime, this.pendingTradeskillCount)
          end
          this.pendingTradeskillCount = nil
        end
      elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- Per-craft completion during a tradeskill merge (arg3 = spellID):
        -- count and clear when the chain is done. A no-op for normal casts,
        -- which are cleared by UNIT_SPELLCAST_STOP.
        if this.tradeskillTotal and arg3 == this.tradeskillSpellID then
          this.tradeskillCompleted = (this.tradeskillCompleted or 0) + 1
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
      elseif event == "UNIT_SPELLCAST_DELAYED" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
        -- Pushback: a cast delayed later or a channel shortened. Following
        -- Quartz, re-poll just the times and accumulate the shift into a running
        -- this.delay for the +/- indicator, rather than a full restamp (which
        -- would reset that total and re-render icon/text). ClassicAPI moves
        -- endMs (SpellDelayed_h bumps g_cast.endMs; the MSG_CHANNEL_UPDATE
        -- co-hook rewrites g_channel.endMs) while startMs stays put, so we diff
        -- endMs. delay is a positive magnitude; OnUpdate signs it "+" for casts
        -- and "-" for channels. Skipped during a tradeskill merge.
        if this.endTime and not this.tradeskillTotal then
          local query = this.unitstr ~= "" and this.unitstr or this.unitname
          local startMs, endMs
          if this.isChannel then
            local _, _, _, s, e = C_Spell.UnitChannelInfo(query)
            startMs, endMs = s, e
          else
            local _, _, _, s, e = C_Spell.UnitCastingInfo(query)
            startMs, endMs = s, e
          end
          if startMs and endMs then
            local shift = this.isChannel and (this.endTime - endMs) or (endMs - this.endTime)
            this.delay = (this.delay or 0) + shift / 1000
            this.startTime = startMs
            this.endTime = endMs
            local newDuration = (endMs - startMs) / 1000
            this.bar:SetMinMaxValues(0, newDuration)
            this.lastMax = newDuration
          end
        end
      end
    end)

    cb:SetAlpha(0)
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

    -- bind castbar to the "focus" unit token; the GUID resolves at read time
    pfUI.castbar.focus.unitstr = "focus"

    UpdateMovable(pfUI.castbar.focus)
  end
end)