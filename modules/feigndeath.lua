-- A feigning hunter reads as 0 health; Nampower's GetUnitField has the real value.
pfUI:RegisterModule("feigndeath", function ()
  if not GetUnitField then return end

  local oldUnitHealth = _G.UnitHealth
  _G.UnitHealth = function(unit)
    if UnitIsFeignDeath(unit) then
      local hp = GetUnitField(unit, "health")
      if hp and hp > 0 then return hp end
    end
    return oldUnitHealth(unit)
  end
end)
