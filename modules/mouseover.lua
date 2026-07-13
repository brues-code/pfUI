pfUI:RegisterModule("mouseover", function ()
  pfUI.api.RegisterSlashCommand("PFCAST", { "/pfcast", "/pfmouse" }, function(msg)
    local func = pfUI.api.TryMemoizedFuncLoadstringForSpellCasts(msg)
    local unit = "mouseover"

    if not UnitExists(unit) then
      local frame = GetMouseFocus()
      if frame.label and frame.id then
        unit = frame.label .. frame.id
      elseif UnitExists("target") then
        unit = "target"
      elseif GetCVar("autoSelfCast") == "1" then
        unit = "player"
      else
        return
      end
    end

    -- Spell-name path: Nampower's CastSpellByName takes a second unit
    -- parameter directly, no target swap dance required.
    if not func then
      CastSpellByName(msg, unit)
      return
    end

    -- Macro path: switch target so the macro's spell calls land on `unit`,
    -- then restore.
    local restore_target = not UnitIsUnit("target", unit)
    if restore_target then TargetUnit(unit) end
    func()
    if restore_target then TargetLastTarget() end
  end, true)
end)