pfUI:RegisterModule("mirrortimers", function ()
  local font = pfUI.font_default
  local fontsize = tonumber(C.global.font_size)
  local height = fontsize * 1.3

  -- The value of a mirror timer moves by `scale` per second: breath drains at
  -- -1, and refills faster than that. A running bar fills from a duration
  -- object that spans the whole bar at that rate, and its text binding shows
  -- the value as m:ss. A paused bar holds its value.
  local function Sync(frame)
    local value = GetMirrorTimerProgress(frame.timer) / 1000
    local max, scale = frame.maxvalue, frame.scale
    local label = frame.label:GetText() or ""

    if frame.paused or scale == 0 then
      frame.statusbar:SetMinMaxValues(0, max)
      frame.statusbar:SetValue(value)
      frame.binding:Disable()
      frame.text:SetFormattedText("%s (%d:%02d)", label, value / 60, value % 60)
      return
    end

    -- the shown value is the seconds of the duration times the rate
    local rate = math.abs(scale)
    local property
    if scale < 0 then
      frame.duration:SetTimeFromEnd(GetTime() + value / rate, max / rate)
      frame.statusbar:SetTimerDuration(frame.duration, Enum.StatusBarInterpolation.Immediate, Enum.StatusBarTimerDirection.RemainingTime)
      property = Enum.DurationTextBindingProperty.RemainingDuration
    else
      frame.duration:SetTimeFromEnd(GetTime() + (max - value) / rate, max / rate)
      frame.statusbar:SetTimerDuration(frame.duration, Enum.StatusBarInterpolation.Immediate, Enum.StatusBarTimerDirection.ElapsedTime)
      property = Enum.DurationTextBindingProperty.ElapsedDuration
    end

    local Down = Enum.NumericRuleFormatRounding.Down
    frame.clock:SetBreakpoints({
      { threshold = 0, format = "%d:%02d", components = {
        { div = 60 / rate, step = 1, rounding = Down },
        { div = 1 / rate, mod = 60, step = 1, rounding = Down },
      } },
    })
    frame.binding:SetTextFormat(label .. " ({})", { { property = property, formatter = frame.clock } })
    frame.binding:Enable()
  end

  for i = 1, MIRRORTIMER_NUMTIMERS do
    local frame = _G["MirrorTimer"..i]
    frame:GetRegions():Hide()
    frame:SetWidth(200)
    frame:SetHeight(height)
    frame:SetScript("OnUpdate", nil)

    frame:ClearAllPoints()
    frame:SetPoint("TOP", UIParent, "TOP", 0, -120-(i-1)*(height + 10))

    CreateBackdrop(frame)
    CreateBackdropShadow(frame)
    UpdateMovable(frame)

    frame.border = _G["MirrorTimer"..i.."Border"]
    frame.border:Hide()

    frame.label = _G["MirrorTimer"..i.."Text"]
    frame.label:Hide()

    frame.statusbar = _G["MirrorTimer"..i.."StatusBar"]
    frame.statusbar:SetStatusBarTexture(pfUI.media["img:bar"])
    frame.statusbar:SetAllPoints(frame)

    frame.text = frame:CreateFontString(nil, "OVERLAY")
    frame.text:SetFont(font, fontsize, "OUTLINE")
    frame.text:SetPoint("CENTER", frame.statusbar, "CENTER", 0, 0)

    frame.duration = C_DurationUtil.CreateDuration()
    frame.clock = C_StringUtil.CreateNumericRuleFormatter()
    frame.binding = C_DurationUtil.CreateDurationTextBinding()
    frame.binding:SetFontString(frame.text)
    frame.binding:SetDuration(frame.duration)

    -- the stock handler has already set the pause state
    frame:HookScript("OnEvent", function()
      if event == "MIRROR_TIMER_PAUSE" and this:IsShown() and arg1 == this.timer then
        Sync(this)
      end
    end)

    frame:HookScript("OnHide", function()
      this.binding:Disable()
    end)
  end

  -- the stock function picks the bar and sets its timer, scale and pause state
  hooksecurefunc("MirrorTimer_Show", function(timer, _, maxvalue)
    for i = 1, MIRRORTIMER_NUMTIMERS do
      local frame = _G["MirrorTimer"..i]
      if frame:IsShown() and frame.timer == timer then
        frame.maxvalue = maxvalue / 1000
        Sync(frame)
        return
      end
    end
  end)
end)
