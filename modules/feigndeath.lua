pfUI:RegisterModule("feigndeath", function ()
  local oldUnitHealth = _G.UnitHealth
  _G.UnitHealth = function(unit)
    if UnitIsFeignDeath(unit) then
      local hp = GetUnitField(unit, "health")
      if hp and hp > 0 then return hp end
    end
    return oldUnitHealth(unit)
  end
end)
