-- @noindex
-- Run once in REAPER's Action List. Run again and choose Terminate to stop.
-- Shares only theme colors with every BLT SPATIAL FIELD instance.
local R=reaper
R.gmem_attach('BLT_SPATIAL_THEME')
local _,_,section,command=R.get_action_context()
R.SetToggleCommandState(section,command,1)
R.RefreshToolbar2(section,command)
-- BEGIN BLT THEME COLORS 1.0.0 (generated from _shared/BLT_ThemeColors.lua)
local BLTThemeColors=(function()
 local M={}
 function M.native(api,key)
  local ok,n=pcall(api.GetThemeColor,key,0)
  if not ok or type(n)~='number' or n~=n or n%1~=0 then return -1 end
  return n
 end
 function M.decode(api,n)
  if n==-1 then return nil end
  local ok,r,g,b=pcall(api.ColorFromNative,n)
  if not ok then return nil end
  for _,v in ipairs({r,g,b}) do
   if type(v)~='number' or v~=v or v<0 or v>255 then return nil end
  end
  if r==nil or g==nil or b==nil then return nil end
  return {r/255,g/255,b/255}
 end
 function M.read(api,key,fallback) return M.decode(api,M.native(api,key)) or fallback end
 local function linear(v) return v<=.04045 and v/12.92 or ((v+.055)/1.055)^2.4 end
 function M.luminance(c) return linear(c[1])*.2126+linear(c[2])*.7152+linear(c[3])*.0722 end
 function M.contrast(a,b)
  local x,y=M.luminance(a),M.luminance(b)
  return (math.max(x,y)+.05)/(math.min(x,y)+.05)
 end
 return M
end)()
-- END BLT THEME COLORS
local bg_keys={'col_main_bg2','col_main_bg','col_tracklistbg','genlist_bg','col_arrangebg'}
local function background()
  for _,key in ipairs(bg_keys) do
    local c=BLTThemeColors.read(R,key)
    if c then return c end
  end
  return {.027,.036,.055}
end
local nextThemePoll,nextHeartbeat=0,0
local function tick()
  local now=R.time_precise()
  if now>=nextThemePoll then
    nextThemePoll=now+3
    local bg=background()
    local tx=BLTThemeColors.read(R,'col_main_text2',{.90,.95,1})
    local light,dark={.935,.945,.958},{.070,.075,.082}
    local use_light=BLTThemeColors.contrast(bg,light)>BLTThemeColors.contrast(bg,dark)
    local readable=use_light and light or dark
    if BLTThemeColors.contrast(bg,readable)<4.5 then readable=use_light and {1,1,1} or {0,0,0} end
    if BLTThemeColors.contrast(bg,tx)<4.5 then tx=readable end
    local ac=BLTThemeColors.read(R,'col_seltrack2',{.20,.70,.92})
    for _=1,8 do
      if BLTThemeColors.contrast(bg,ac)>=3 then break end
      for i=1,3 do ac[i]=ac[i]+(readable[i]-ac[i])*.2 end
    end
    for i=1,3 do R.gmem_write(i,bg[i]);R.gmem_write(i+3,tx[i]);R.gmem_write(i+6,ac[i]) end
  end
  -- The JSFX detects a stopped bridge through this lightweight heartbeat.
  if now>=nextHeartbeat then
    nextHeartbeat=now+.25
    R.gmem_write(0,R.gmem_read(0)+1)
  end
  R.defer(tick)
end
R.atexit(function()
  R.gmem_write(0,0)
  R.SetToggleCommandState(section,command,0);R.RefreshToolbar2(section,command)
end)
tick()
