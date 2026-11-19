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

    -- Spell-name path: cast straight at the unit, no target swap dance required.
    if not func then
      C_Spell.CastAtUnit(msg, unit)
      return
    end

    -- Macro path: switch target so the macro's spell calls land on `unit`,
    -- then put the old target back by GUID, or clear when there was none.
    -- Not TargetLastTarget: with ClassicAPI's soft targeting a select from no
    -- target keeps the last target, and a hidden SoftTargetForce target (no
    -- GUID through the token) must clear so it is forced again, not chosen.
    local restore_target = not UnitIsUnit("target", unit)
    local prev = restore_target and UnitGUID("target")
    if restore_target then TargetUnit(unit) end
    func()
    if restore_target then
      if prev and prev ~= "0x0000000000000000" then
        TargetUnit(prev)
      else
        ClearTarget()
      end
    end
  end, true)
end)