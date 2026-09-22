-- @noindex
-- Run once in REAPER's Action List. Run again and choose Terminate to stop.
-- Shares only theme colors with every BLT SPATIAL FIELD instance.
local R=reaper
R.gmem_attach('BLT_SPATIAL_THEME')
local _,_,section,command=R.get_action_context()
R.SetToggleCommandState(section,command,1)
R.RefreshToolbar2(section,command)
local function color(key,fallback)
  local n=R.GetThemeColor(key,0)
  if n<0 then return fallback end
  local r,g,b=R.ColorFromNative(n)
  return {r/255,g/255,b/255}
end
local function luminance(c)
  local function lin(v) return v<=.04045 and v/12.92 or ((v+.055)/1.055)^2.4 end
  return .2126*lin(c[1])+.7152*lin(c[2])+.0722*lin(c[3])
end
local function contrast(a,b)
  local x,y=luminance(a),luminance(b)
  return (math.max(x,y)+.05)/(math.min(x,y)+.05)
end
local nextPoll=0
local function tick()
  local now=R.time_precise()
  if now>=nextPoll then
    nextPoll=now+.25
    local bg=color('col_main_bg2',{.027,.036,.055})
    local tx=color('col_main_text2',{.90,.95,1})
    local light,dark={.96,.97,.98},{.025,.03,.04}
    local readable=contrast(bg,light)>contrast(bg,dark) and light or dark
    if contrast(bg,tx)<4.5 then tx=readable end
    local ac=color('col_seltrack2',{.20,.70,.92})
    for _=1,8 do
      if contrast(bg,ac)>=3 then break end
      for i=1,3 do ac[i]=ac[i]+(readable[i]-ac[i])*.2 end
    end
    for i=1,3 do R.gmem_write(i,bg[i]);R.gmem_write(i+3,tx[i]);R.gmem_write(i+6,ac[i]) end
    R.gmem_write(0,R.gmem_read(0)+1)
  end
  R.defer(tick)
end
R.atexit(function()
  R.gmem_write(0,0)
  R.SetToggleCommandState(section,command,0);R.RefreshToolbar2(section,command)
end)
tick()
