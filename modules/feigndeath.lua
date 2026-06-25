pfUI:RegisterModule("feigndeath", function ()
  local oldUnitHealth = UnitHealth
  function UnitHealth(unit)
    if UnitIsFeignDeath(unit) then
      local hp = GetUnitField(unit, "health")
      if hp and hp > 0 then return hp end
    end
    return oldUnitHealth(unit)
  end
end)
