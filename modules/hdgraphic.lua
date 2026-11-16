pfUI:RegisterModule("hdgraphic", function ()
  -- extend the old video options' environment detail slider (the SetWorldDetail
  -- hook below maps the extra steps); newer clients replace that window entirely
  if OptionsFrameSliders then
    OptionsFrameSliders[3].maxValue = 15
  end

  local HookSetWorldDetail = SetWorldDetail
  function _G.SetWorldDetail(arg)
    HookSetWorldDetail((arg > 2 and 2 or arg))

    if arg > 2 then
      ConsoleExec("frillDensity " .. (arg+1)*16)
      ConsoleExec("lodDist " .. 100+arg*10)
      ConsoleExec("nearClip " .. arg*2/100)
      ConsoleExec("maxLOD " .. arg)
      ConsoleExec("footstepBias " .. arg/15)
      ConsoleExec("DistCull " .. 500+arg*25.92)

      -- static triggers
      ConsoleExec("SkyCloudLOD 1")
      ConsoleExec("mapObjLightLOD 2")
      ConsoleExec("texLodBias -1")
    else
      -- defaults
      ConsoleExec("frillDensity 24")
      ConsoleExec("lodDist 100")
      ConsoleExec("nearClip 0.1")
      ConsoleExec("maxLOD 0")
      ConsoleExec("footstepBias 0.125")
      ConsoleExec("DistCull 500")

      ConsoleExec("SkyCloudLOD 0")
      ConsoleExec("mapObjLightLOD 0")
      ConsoleExec("texLodBias 0")
    end
  end

  local HookGetWorldDetail = GetWorldDetail
  function _G.GetWorldDetail(arg)
    local frill = tonumber(GetCVar("frillDensity"))
    return frill > 48 and frill/16-1 or HookGetWorldDetail()
  end
end)