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

  -- Clear cast state on the bar. Shows the bar full for one frame, then
  -- OnUpdate fades it out.
  local function ClearBar(cb)
    cb.startTime, cb.endTime, cb.isChannel = nil, nil, nil
    cb.activeName, cb.spellID = nil, nil
    cb.isTradeskill = nil
    cb.tradeskillTotal, cb.tradeskillCompleted, cb.tradeskillSpellID = nil, nil, nil
    cb.tradeskillSingleMs, cb.currentCraftStart = nil, nil
    cb.lastMax = nil
    cb.delay = 0
    cb.bar:SetMinMaxValues(1, 100)
    cb.bar:SetValue(100)
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
  -- SPELLCAST_START / SPELL_START_SELF handlers). Resets the per-craft
  -- spark to the left edge of the bar.
  local function StartTradeskillCraft(cb)
    cb.currentCraftStart = GetTime() * 1000
    UpdateTradeskillLabel(cb)
  end

  -- Stamp the bar with cast data and render text/icon/lag once. OnUpdate
  -- then animates the fill from this state without touching C_Spell.
  local function StampBar(cb, name, tex, startMs, endMs, spellID, isChannel, delayMs, isTradeskill)
    cb.startTime = startMs
    cb.endTime = endMs
    cb.isChannel = isChannel
    cb.spellID = spellID
    cb.activeName = name
    cb.isTradeskill = isTradeskill
    cb.delay = (delayMs or 0) / 1000
    cb:SetAlpha(1)
    cb.fadeout = nil

    cb.bar:SetStatusBarColor(strsplit(",", C.appearance.castbar[isChannel and "channelcolor" or "castbarcolor"]))

    local rank = ""
    if spellID and GetSpellRecField then
      rank = GetSpellRecField(spellID, "rank") or ""
    end
    local spellname = (cb.showname and name) and (name .. " ") or ""
    local rankstr = (cb.showrank and rank ~= "") and string.format("|cffaaffcc[%s]|r", rank) or ""
    cb.bar.left:SetText(spellname .. rankstr)

    if tex and cb.showicon then
      local size = cb:GetHeight()
      cb.icon:Show()
      cb.icon:SetHeight(size)
      cb.icon:SetWidth(size)
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
  end

  -- One-shot poll: read C_Spell for the bar's unit, stamp or clear. Called
  -- from event handlers (cast start, target/focus change), never per-frame.
  local function RefreshBar(cb)
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
      StampBar(cb, name, tex, startMs, endMs, spellID, isChan, delayMs, isTradeskill)
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
    cb.icon:SetHeight(16)
    cb.icon:SetWidth(16)

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

    -- Cast lifecycle events. Player bars react to vanilla SPELLCAST_*; non-
    -- player bars also react to Nampower SPELL_*_OTHER (gated by the
    -- NP_EnableSpell{Start,Go}Events CVars, enabled by libdebuff) plus the
    -- retarget event. Player events also feed non-player bars for the
    -- target=self case.
    cb:RegisterEvent("SPELLCAST_START")
    cb:RegisterEvent("SPELLCAST_STOP")
    cb:RegisterEvent("SPELLCAST_FAILED")
    cb:RegisterEvent("SPELLCAST_INTERRUPTED")
    cb:RegisterEvent("SPELLCAST_CHANNEL_START")
    cb:RegisterEvent("SPELLCAST_CHANNEL_STOP")
    cb:RegisterEvent("SPELLCAST_CHANNEL_UPDATE")
    cb:RegisterEvent("SPELL_DELAYED_SELF")
    -- Chained same-spell recasts never run the client cast path (the 1.12
    -- engine short-circuits at spellID == current-cast), so vanilla
    -- SPELLCAST_START never fires for them. nampower's SPELL_START_SELF
    -- (server-driven) is the only signal that shows them.
    cb:RegisterEvent("SPELL_START_SELF")
    if unitstr == "player" then
      cb:RegisterEvent("SPELL_GO_SELF")
    end
    if unitstr ~= "player" and unitstr ~= "" then
      cb:RegisterEvent("SPELL_START_OTHER")
      cb:RegisterEvent("SPELL_FAILED_OTHER")
      if unitstr == "target" then
        cb:RegisterEvent("PLAYER_TARGET_CHANGED")
      elseif unitstr == "focus" then
        cb:RegisterEvent("PLAYER_FOCUS_CHANGED")
      end
    end

    cb:SetScript("OnEvent", function()
      local unit = this.unitstr

      if event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" then
        RefreshBar(this)
        return
      end

      if event == "SPELL_START_OTHER" then
        -- arg3=casterGuid. Defer one frame so ClassicAPI's UnitChannelInfo
        -- can see the engine's +0x228 broadcast for remote-unit channels
        -- (the cohook+packet handler runs in the same frame; the broadcast
        -- propagates after).
        if arg3 == UnitGUID(unit) then
          local target = this
          RunNextFrame(function() RefreshBar(target) end)
        end
        return
      end

      if event == "SPELL_FAILED_OTHER" then
        if arg1 == UnitGUID(unit) then ClearBar(this) end
        return
      end

      -- Vanilla SPELLCAST_* + SPELL_DELAYED_SELF fire only for the local
      -- player. Non-player bars handle them only when their unit currently
      -- resolves to the player (target=self / focus=self).
      if not UnitIsUnit(unit, 'player') then return end

      if event == "SPELLCAST_START" or event == "SPELLCAST_CHANNEL_START" then
        if this.tradeskillTotal then
          -- Mid-chain craft N+1 of N. Keep the merged bar; resync the spark
          -- to the new craft's start and refresh the "(N)" count label.
          StartTradeskillCraft(this)
        else
          RefreshBar(this)
          if this.isTradeskill and (this.pendingTradeskillCount or 0) > 1
              and C.castbar.player.mergetradeskill == "1" then
            EnterTradeskillMerge(this, this.startTime, this.endTime, this.pendingTradeskillCount)
          end
          this.pendingTradeskillCount = nil
        end
      elseif event == "SPELL_START_SELF" then
        -- Catches chained same-spell recasts (no SPELLCAST_START fires) —
        -- including tradeskill chaining where craft 2..N reuse one spell.
        -- Defer one frame so ClassicAPI's SMSG_SPELL_START co-hook has
        -- stamped g_cast before we poll, regardless of co-hook order.
        if this.tradeskillTotal then
          StartTradeskillCraft(this)
        else
          local target = this
          RunNextFrame(function()
            -- Re-check: SPELL_START_SELF (nampower co-hook) fires before vanilla
            -- SPELLCAST_START on the same packet, so SPELLCAST_START may have
            -- entered merge in this same frame. Don't restamp over it.
            if target.tradeskillTotal then
              StartTradeskillCraft(target)
              return
            end
            RefreshBar(target)
            if target.unitstr == "player" and target.isTradeskill
                and (target.pendingTradeskillCount or 0) > 1
                and C.castbar.player.mergetradeskill == "1" then
              EnterTradeskillMerge(target, target.startTime, target.endTime, target.pendingTradeskillCount)
            end
            target.pendingTradeskillCount = nil
          end)
        end
      elseif event == "SPELLCAST_CHANNEL_STOP" then
        -- A channel's stop can arrive after a following cast already claimed
        -- the bar (channel->cast transition); only clear if a channel is
        -- actually being shown, so it doesn't wipe an active cast bar.
        if this.isChannel then ClearBar(this) end
      elseif event == "SPELLCAST_STOP" then
        -- During a tradeskill chain, SPELL_GO_SELF already counted this craft
        -- and either cleared the bar (chain done) or kept it running. Only a
        -- non-merge cast clears here.
        if not this.tradeskillTotal then ClearBar(this) end
      elseif event == "SPELLCAST_FAILED" or event == "SPELLCAST_INTERRUPTED" then
        ClearBar(this)
      elseif event == "SPELL_GO_SELF" then
        -- arg2 = spellId. In a tradeskill merge, count each successful craft
        -- and clear when the chain is done.
        if this.tradeskillTotal and arg2 == this.tradeskillSpellID then
          this.tradeskillCompleted = (this.tradeskillCompleted or 0) + 1
          if this.tradeskillCompleted >= this.tradeskillTotal then
            ClearBar(this)
          else
            UpdateTradeskillLabel(this)
          end
        end
      elseif event == "SPELL_DELAYED_SELF" then
        -- Cast pushback. nampower's event carries the delay (arg2); apply it
        -- locally rather than re-polling, so the bar doesn't depend on
        -- ClassicAPI's SMSG_SPELL_DELAYED co-hook having bumped g_cast before
        -- this fires (co-hook order vs nampower is not guaranteed).
        if not this.endTime or not arg2 then return end
        local delayMs = tonumber(arg2) or 0
        if delayMs > 0 then
          this.delay = (this.delay or 0) + delayMs / 1000
          this.endTime = this.endTime + delayMs
          local newDuration = (this.endTime - this.startTime) / 1000
          this.bar:SetMinMaxValues(0, newDuration)
          this.lastMax = newDuration
        end
      elseif event == "SPELLCAST_CHANNEL_UPDATE" then
        -- Channel pushback. ClassicAPI doesn't track channel delay in
        -- g_channel, so we adjust endTime + delay locally and resize the
        -- bar so OnUpdate animates against the new total.
        if not this.endTime or not arg1 then return end
        local newEndMs = GetTime() * 1000 + arg1
        local diff = this.endTime - newEndMs
        if diff > 50 then
          this.delay = (this.delay or 0) + diff / 1000
          this.endTime = newEndMs
          local newDuration = (this.endTime - this.startTime) / 1000
          this.bar:SetMinMaxValues(0, newDuration)
          this.lastMax = newDuration
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
    -- requested count before the first SPELLCAST_START fires. Always-on hook
    -- (the config knob is read at event time so toggling takes effect on the
    -- next craft without a /reload). DoTradeSkill is synchronous; the server
    -- roundtrip to SPELLCAST_START gives us plenty of time after this hook.
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