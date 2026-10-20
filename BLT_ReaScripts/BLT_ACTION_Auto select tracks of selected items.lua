-- @description ACTION - Auto select tracks of selected items (toggle)
-- @version 1.0.4
-- @author Balrulu
-- @provides
--   . > ../
-- @changelog
--   BLT SERIES ACTIONS
-- @about
--   BLT SERIES Beta TEST UPLOAD

local reaper=reaper
do
-- BEGIN BLT NATIVE DIALOGS 1.0.0 (generated from _shared/BLT_NativeDialogs.lua)
local BLTNativeDialogs=(function()
 local M={}
 function M.install(api,view)
  local P=setmetatable({}, {__index=api})
  local title,depth=nil,0
  local windowsOS=api.GetOS and (api.GetOS() or ''):match('Win')~=nil
  if view and view.init then
   local init=view.init
   view.init=function(name,...)
    title=name;return init(name,...)
   end
  end
  local function valid(hwnd)
   if not hwnd or hwnd==0 then return false end
   local value=api.JS_Window_IsWindow(hwnd);return value==true or value==1
  end
  local function owned(hwnd,main)
   if not main then return false end
   local seen={}
   for _=1,32 do
    if hwnd==main then return true end
    if not hwnd or seen[hwnd] then return false end;seen[hwnd]=true
    local parent=api.JS_Window_GetParent and api.JS_Window_GetParent(hwnd)
    if parent==0 or parent==hwnd then parent=nil end
    hwnd=parent or (api.JS_Window_GetRelated and api.JS_Window_GetRelated(hwnd,'OWNER'))
   end
   return false
  end
  local function suspend(session)
   if not api.JS_Window_Find or not api.JS_Window_IsWindow then return end
   local own=title and api.JS_Window_Find(title,true)
   local main=api.GetMainHwnd and api.GetMainHwnd()
   local candidates,seen={},{}
   local function add(hwnd)
    if hwnd~=main and valid(hwnd) and not seen[hwnd] then candidates[#candidates+1]=hwnd;seen[hwnd]=true end
   end
   add(own)
   if api.JS_Window_ListAllTop and api.JS_Window_HandleFromAddress and api.JS_Window_GetTitle then
    local _,list=api.JS_Window_ListAllTop()
    for address in (list or ''):gmatch('[^,]+') do
     local n=tonumber(address) or tonumber(address,16)
     local hwnd=n and api.JS_Window_HandleFromAddress(n)
     if valid(hwnd) then
      local caption=api.JS_Window_GetTitle(hwnd) or ''
      if (caption:match('^BLT[%s_:]') or caption=='LOUDNESS TRACE') and owned(hwnd,main) then add(hwnd) end
     end
    end
   end
   if #candidates==0 then return end
   assert(api.JS_Window_Enable and api.JS_Window_GetLong,'Native dialogs require JS_Window_Enable and JS_Window_GetLong (js_ReaScriptAPI).')
   session.foreground=api.JS_Window_GetForeground and api.JS_Window_GetForeground()
   session.main=main
   for _,hwnd in ipairs(candidates) do
    local style=api.JS_Window_GetLong(hwnd,'STYLE')
    assert(type(style)=='number','Cannot read BLT window input state.')
    local topmost=windowsOS and (math.floor(api.JS_Window_GetLong(hwnd,'EXSTYLE'))&8)~=0
    local enabled=(math.floor(style)&0x08000000)==0
    if enabled or topmost then
     local entry={hwnd=hwnd,enabled=enabled,topmost=topmost};session.windows[#session.windows+1]=entry
     if topmost then
      assert(api.JS_Window_SetZOrder,'Native dialogs require JS_Window_SetZOrder (js_ReaScriptAPI).')
      assert(api.JS_Window_SetZOrder(hwnd,'NOTOPMOST'),'Cannot suspend BLT always-on-top state.')
     end
     if enabled then
      api.JS_Window_Enable(hwnd,false)
      assert((math.floor(api.JS_Window_GetLong(hwnd,'STYLE'))&0x08000000)~=0,'Cannot suspend BLT window input.')
     end
    end
   end
  end
  local function restore(session)
   for i=#session.windows,1,-1 do
    local entry=session.windows[i]
    local checked,exists=pcall(valid,entry.hwnd)
    if not checked or exists then
     if entry.enabled then pcall(api.JS_Window_Enable,entry.hwnd,true) end
     if entry.topmost then pcall(api.JS_Window_SetZOrder,entry.hwnd,'TOPMOST') end
    end
   end
   -- Do not take focus back if the user switched to another application.
   pcall(function()
    local current=api.JS_Window_GetForeground and api.JS_Window_GetForeground()
    if session.foreground and valid(session.foreground) and (current==session.main or owned(current,session.main)) then
     for _,entry in ipairs(session.windows) do
      if entry.enabled and (session.foreground==entry.hwnd or owned(session.foreground,entry.hwnd)) then
       if api.JS_Window_SetForeground then api.JS_Window_SetForeground(entry.hwnd) end
       break
      end
     end
    end
   end)
  end
  local function call(fn,...)
   if depth>0 then return fn(...) end
   local args=table.pack(...);local session={windows={}};depth=depth+1
   local result=table.pack(xpcall(function() suspend(session);return fn(table.unpack(args,1,args.n)) end,debug.traceback))
   depth=depth-1;restore(session)
   if not result[1] then error(result[2],0) end
   return table.unpack(result,2,result.n)
  end
  for _,name in ipairs({'GetUserInputs','MB','ShowMessageBox','GetUserFileNameForRead','JS_Dialog_BrowseForSaveFile','JS_Dialog_BrowseForOpenFiles','JS_Dialog_BrowseForFolder','GR_SelectColor'}) do
   local fn=api[name]
   if type(fn)=='function' then P[name]=function(...) return call(fn,...) end end
  end
  return P
 end
 return M
end)()
-- END BLT NATIVE DIALOGS

reaper=BLTNativeDialogs.install(reaper,gfx)
end

local R = reaper
local _, _, section, command = R.get_action_context()
local has_action = section and command and section >= 0 and command > 0
local project, count, state, first, last
local items, selected, wanted, changes = {}, {}, {}, {}
local next_check, next_audit, change_count = 0, 0, 0
local stopped = false

local function cleanup()
  if stopped then return end
  stopped = true
  if R.set_action_options then pcall(R.set_action_options, 9) end
  if has_action then
    pcall(R.SetToggleCommandState, section, command, 0)
    pcall(R.RefreshToolbar2, section, command)
  end
end

local function apply_tracks(deselect_count)
  for i = 1, change_count do R.SetTrackSelected(changes[i], i > deselect_count) end
end

local function sync_tracks(p, n)
  for track in pairs(wanted) do wanted[track] = nil end
  for i = 1, n do
    local track = R.GetMediaItemTrack(items[i])
    if not track then count = -1; return end
    wanted[track] = true
  end
  change_count = 0
  for i = 0, R.CountSelectedTracks(p) - 1 do
    local track = R.GetSelectedTrack(p, i)
    if R.EnumProjects(-1, "") ~= p then count = -1; return end
    if not track then count = -1; return end
    if wanted[track] == nil then
      change_count = change_count + 1
      changes[change_count] = track
    else
      wanted[track] = false
    end
  end
  local deselect_count = change_count
  for track, needs_select in pairs(wanted) do
    if needs_select then
      change_count = change_count + 1
      changes[change_count] = track
    end
  end
  for i = change_count + 1, #changes do changes[i] = nil end
  if change_count == 0 then return end
  if R.EnumProjects(-1, "") ~= p then count = -1; return end
  for i = 1, change_count do
    if not R.ValidatePtr2(p, changes[i], "MediaTrack*") then count = -1; return end
  end
  R.PreventUIRefresh(1)
  local ok, err = pcall(apply_tracks, deselect_count)
  R.PreventUIRefresh(-1)
  if not ok then error(err, 0) end
  R.UpdateArrange()
  if R.EnumProjects(-1, "") == p then state = R.GetProjectStateChangeCount(p) end
end

local function update(now)
  local p = R.EnumProjects(-1, "")
  if not p then project, count = nil, -1; return end
  local n = R.CountSelectedMediaItems(p)
  local changed = p ~= project or n ~= count
  if n == 0 then
    if changed then
      for i = 1, #items do items[i] = nil end
      for item in pairs(selected) do selected[item] = nil end
      for track in pairs(wanted) do wanted[track] = nil end
      for i = 1, #changes do changes[i] = nil end
      change_count = 0
      project, count, state, first, last = p, 0, nil, nil, nil
    end
    return
  end
  local f = R.GetSelectedMediaItem(p, 0)
  local l = n > 1 and R.GetSelectedMediaItem(p, n - 1) or f
  if not changed and n <= 2 and f == first and l == last then return end
  local s = R.GetProjectStateChangeCount(p)
  if not changed and s == state and f == first and l == last and now < next_audit then return end
  for i = 1, n do
    local item = i == 1 and f or (i == n and l or R.GetSelectedMediaItem(p, i - 1))
    if not item then count = -1; return end
    if item ~= items[i] then
      if not selected[item] then changed = true end
      items[i] = item
    end
  end
  for i = n + 1, #items do items[i] = nil end
  project, count, state, first, last = p, n, s, f, l
  next_audit = now + 0.3
  if changed then
    for item in pairs(selected) do selected[item] = nil end
    for i = 1, n do selected[items[i]] = true end
    sync_tracks(p, n)
  end
end

local function loop()
  if stopped then return end
  local now = R.time_precise()
  if now >= next_check then
    next_check = now + 0.1
    local ok, err = pcall(update, now)
    if not ok then
      cleanup()
      R.ShowMessageBox(tostring(err), "BLT Auto select tracks", 0)
      return
    end
  end
  R.defer(loop)
end

R.atexit(cleanup)
if R.set_action_options then R.set_action_options(5) end
if has_action then
  R.SetToggleCommandState(section, command, 1)
  R.RefreshToolbar2(section, command)
end
R.defer(loop)
