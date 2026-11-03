-- @description ACTION - Auto select tracks of selected items (toggle)
-- @version 1.1.4
-- @author Balrulu
-- @provides
--   . > ../
-- @changelog
--   BLT SERIES ACTIONS
-- @about
--   BLT SERIES Beta TEST UPLOAD

-- BEGIN BLT TOGGLE RESTORE EMBEDDED 1.1.0
local reaper=reaper
do
-- BEGIN BLT NATIVE DIALOGS 1.2.1 (generated from _shared/BLT_NativeDialogs.lua)
local BLTNativeDialogs=(function()
 local M={}
 function M.install(api,view)
  local P=setmetatable({}, {__index=api})
  local title,depth=nil,0
  local active,pending,scheduled,rounds,exitHandler=nil,nil,false,0,nil
  local host=api
  for _=1,8 do
   local mt=getmetatable(host)
   if type(mt)~='table' or type(mt.__index)~='table' then break end
   host=mt.__index
  end
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
   session.focus=api.JS_Window_GetFocus and api.JS_Window_GetFocus()
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
  local function has_flag(hwnd,name,mask,on)
   local ok,value=pcall(api.JS_Window_GetLong,hwnd,name)
   return ok and type(value)=='number' and value==value and math.abs(value)<math.huge
    and ((math.floor(value)&mask)~=0)==on
  end
  local function restore(session)
   local failed,seen={},{}
   local function retain(entry)
    if not seen[entry] then failed[#failed+1]=entry;seen[entry]=true end
   end
   for i=#session.windows,1,-1 do
    local entry=session.windows[i]
    local checked,exists=pcall(valid,entry.hwnd)
    if not checked or exists then
     local enabled,topmost=not entry.enabled,not entry.topmost
     for _=1,3 do
      if not enabled then
       enabled=has_flag(entry.hwnd,'STYLE',0x08000000,false)
       if not enabled then
        pcall(api.JS_Window_Enable,entry.hwnd,true)
        enabled=has_flag(entry.hwnd,'STYLE',0x08000000,false)
       end
      end
      if not topmost then
       topmost=has_flag(entry.hwnd,'EXSTYLE',8,true)
       if not topmost then
        pcall(api.JS_Window_SetZOrder,entry.hwnd,'TOPMOST')
        topmost=has_flag(entry.hwnd,'EXSTYLE',8,true)
       end
      end
      if enabled and topmost then break end
     end
     entry.inputRestored=enabled
     if not enabled or not topmost then retain(entry) end
    end
   end
   -- Do not take focus back if the user switched to another application.
   pcall(function()
    local current=api.JS_Window_GetForeground and api.JS_Window_GetForeground()
    if session.foreground and valid(session.foreground) and
     (current==session.foreground or current==session.main or owned(current,session.foreground)) then
     for _,entry in ipairs(session.windows) do
      local foreground=session.foreground==entry.hwnd or owned(session.foreground,entry.hwnd)
      local focus=session.focus and valid(session.focus) and (session.focus==entry.hwnd or owned(session.focus,entry.hwnd))
      if entry.enabled and entry.inputRestored and (foreground or focus) then
       if foreground and current~=entry.hwnd and api.JS_Window_SetForeground then api.JS_Window_SetForeground(entry.hwnd) end
       if focus and api.JS_Window_SetFocus and api.JS_Window_GetFocus then
        local ok,actual=pcall(api.JS_Window_GetFocus)
        if not ok or actual~=session.focus then
         pcall(api.JS_Window_SetFocus,session.focus)
         ok,actual=pcall(api.JS_Window_GetFocus)
         if not ok or actual~=session.focus then retain(entry) end
        end
       end
       break
      end
     end
    end
   end)
   return failed
  end
  local function warn()
   if host.ShowConsoleMsg then
    pcall(host.ShowConsoleMsg,'BLT: ウィンドウの操作状態／最前面状態／キー入力先を復元できませんでした。操作できないBLTはアクションリストから終了・再実行してください。\nBLT window recovery failed after retries. Stop and restart the affected BLT action.\n')
   end
  end
  local function retry()
   scheduled=false
   if not pending then return end
   if depth>0 then
    if host.defer then scheduled=true;host.defer(retry) end
    return
   end
   pending.windows=restore(pending)
   if #pending.windows==0 then pending=nil;return end
   rounds=rounds+1
   if rounds<8 and host.defer then scheduled=true;host.defer(retry) else warn() end
  end
  local function recover(session,failed)
   if #failed==0 then return end
   if not pending then pending={windows={},main=session.main,foreground=session.foreground,focus=session.focus};rounds=0 end
   for _,entry in ipairs(failed) do
    local duplicate=false
    for _,old in ipairs(pending.windows) do
     if old.hwnd==entry.hwnd then
      old.enabled,old.topmost=old.enabled or entry.enabled,old.topmost or entry.topmost;duplicate=true;break
     end
    end
    if not duplicate then pending.windows[#pending.windows+1]=entry end
   end
   if not scheduled then
    if host.defer then scheduled=true;host.defer(retry) else retry() end
   end
  end
  if type(api.atexit)=='function' then
   local function finish()
    if active then local session=active;active=nil;local failed=restore(session);if #failed>0 then warn() end end
    if pending then pending.windows=restore(pending);if #pending.windows>0 then warn() end end
    if exitHandler then exitHandler() end
   end
   P.atexit=function(fn) exitHandler=fn;return api.atexit(finish) end
   api.atexit(finish)
  end
  local function call(fn,...)
   if depth>0 then return fn(...) end
   local args=table.pack(...);local session={windows={}};depth=depth+1;active=session
   local result=table.pack(xpcall(function() suspend(session);return fn(table.unpack(args,1,args.n)) end,debug.traceback))
   local failed=restore(session);active=nil;depth=depth-1;recover(session,failed)
   if not result[1] then error(result[2],0) end
   return table.unpack(result,2,result.n)
  end
  for _,name in ipairs({'GetUserInputs','MB','ShowMessageBox','GetUserFileName','GetUserFileNameForRead','JS_Dialog_BrowseForSaveFile','JS_Dialog_BrowseForOpenFiles','JS_Dialog_BrowseForFolder','GR_SelectColor','Main_OnCommand','Main_OnCommandEx','CF_SendActionShortcut','MIDIEditor_LastFocused_OnCommand'}) do
   local fn=api[name]
   if type(fn)=='function' then P[name]=function(...) return call(fn,...) end end
  end
  if type(api.GetSetProjectInfo_String)=='function' then
   local fn=api.GetSetProjectInfo_String
   P.GetSetProjectInfo_String=function(project,key,value,...)
    local stats=key=='RENDER_STATS' or key=='RENDER_STATS_SUMMARY'
    if stats and value and value~='' and tonumber(value)~=0 then return call(fn,project,key,value,...) end
    return fn(project,key,value,...)
   end
  end
  -- Native actions may also display modal progress or error windows.
  P.BLT_WithNativeDialog=call
  return P
 end
 return M
end)()
-- END BLT NATIVE DIALOGS
reaper=BLTNativeDialogs.install(reaper,gfx)
end

do
local BLTToggleRestoreSource = [====[
-- BLT toggle persistence 1.1.0. Embedded in each supported action.
-- The public action is a dispatcher; its private worker owns the defer loop.
-- Only a dispatcher's explicit OFF writes OFF. Worker shutdown never does.
local M = {}
local SECTION = 'BLT_TOGGLE_RESTORE'
local IDS = {'folder_covers', 'selected_tracks', 'video_hover', 'cover_name_markers'}
local BEGIN = '-- BEGIN BLT TOGGLE RESTORE'
local ENDING = '-- END BLT TOGGLE RESTORE'

local function valid_id(id)
  for _, value in ipairs(IDS) do if value == id then return true end end
  return false
end

local function root(api)
  return api.GetResourcePath() .. '/Scripts/BLT ReaScripts'
end

local function worker_path(api, id)
  assert(valid_id(id), 'Unknown BLT toggle action.')
  return root(api) .. '/BLT_Toggle_Worker_' .. id .. '.lua'
end

local function read(path)
  local file, err, code = io.open(path, 'rb')
  if not file then
    if code == 2 then return nil end
    error(err or ('Cannot read ' .. path), 0)
  end
  local data = assert(file:read('*a'));assert(file:close());return data
end

local function bytes(path, data)
  local file, err = io.open(path, 'wb');assert(file, err)
  local ok, why = file:write(data);local closed, close_error = file:close()
  assert(ok and closed, why or close_error or 'Cannot save BLT startup file.')
  assert(read(path) == data, 'BLT startup file verification failed: ' .. path)
end

local function write(path, data)
  local previous = read(path)
  if previous == data then return end
  if previous then
    local backup, suffix = path .. '.blt-toggle-backup', 0
    while true do
      local saved = read(backup)
      if not saved then bytes(backup, previous);break end
      if saved == previous then break end
      suffix = suffix + 1;assert(suffix <= 100, 'Too many BLT startup backups.')
      backup = path .. '.blt-toggle-backup-' .. suffix
    end
  end
  local ok, err = pcall(bytes, path, data)
  if not ok then
    if previous then
      local restored, reason = pcall(bytes, path, previous)
      if not restored then error(tostring(err) .. '\nCannot restore startup file: ' .. tostring(reason), 0) end
    end
    error(err, 0)
  end
end

local function save(api, key, value, persist)
  if api.GetExtState(SECTION, key) ~= value then api.SetExtState(SECTION, key, value, persist) end
end

local function named(api, command)
  local value = api.ReverseNamedCommandLookup(command) or ''
  return value ~= '' and ('_' .. value:gsub('^_', '')) or ''
end

local function worker_source(id)
  return 'local R=reaper\nlocal fn,err=loadfile(R.GetResourcePath().."/Scripts/BLT ReaScripts/BLT_Toggle_Restore.lua")\n'
    .. 'if not fn then if R.ShowConsoleMsg then R.ShowConsoleMsg(tostring(err).."\\n")end;return end\n'
    .. 'fn().worker(R,' .. string.format('%q', id) .. ')\n'
end

local function command_for(api, id)
  local path = worker_path(api, id)
  write(path, worker_source(id))
  local command = api.AddRemoveReaScript(true, 0, path, false)
  assert(command and command > 0, 'Cannot register the BLT background worker.')
  return command
end

local function launch(api, id)
  local command = command_for(api, id)
  local ok, err = pcall(api.Main_OnCommand, command, 0)
  -- Unregistering a running ReaScript keeps its defer/atexit callbacks alive.
  -- The temporary command must never remain in the user's action list.
  local removed, why = pcall(api.AddRemoveReaScript, false, 0, worker_path(api, id), true)
  assert(removed and type(why) == 'number' and why > 0, why or 'Cannot unregister the BLT background worker.')
  assert(ok, err)
  assert(api.GetExtState(SECTION, id .. '_running') == '1', 'The BLT background worker did not start: ' .. id)
end

local function remove_legacy_workers(api)
  for _, id in ipairs(IDS) do
    api.AddRemoveReaScript(false, 0, worker_path(api, id), true)
    if api.GetExtState(SECTION, id .. '_worker_command') ~= '' then
      api.DeleteExtState(SECTION, id .. '_worker_command', true)
    end
  end
end

local function log(api, message)
  if api.ShowConsoleMsg then pcall(api.ShowConsoleMsg, 'BLT toggle restore: ' .. tostring(message) .. '\n') end
end

function M.install(api, id, module_source)
  assert(valid_id(id) and type(module_source) == 'string', 'Invalid BLT restore installation.')
  api.RecursiveCreateDirectory(root(api), 0)
  write(root(api) .. '/BLT_Toggle_Restore.lua', module_source)
  write(worker_path(api, id), worker_source(id))
  remove_legacy_workers(api)
  local startup = api.GetResourcePath() .. '/Scripts/__startup.lua'
  local original = read(startup) or ''
  local bom = original:sub(1, 3) == '\239\187\191' and original:sub(1, 3) or ''
  local body = bom ~= '' and original:sub(4) or original
  local block = BEGIN .. '\ndo\n local fn,err=loadfile(reaper.GetResourcePath().."/Scripts/BLT ReaScripts/BLT_Toggle_Restore.lua")\n'
    .. ' if fn then local ok,why=pcall(function()fn().restore(reaper)end);if not ok and reaper.ShowConsoleMsg then reaper.ShowConsoleMsg(tostring(why).."\\n")end\n'
    .. ' elseif reaper.ShowConsoleMsg then reaper.ShowConsoleMsg(tostring(err).."\\n")end\nend\n' .. ENDING .. '\n'
  local first = body:find(BEGIN, 1, true)
  if first then
    local last = assert(body:find(ENDING, first + #BEGIN, true), 'Incomplete BLT startup block; original file was kept.')
    local after = last + #ENDING
    if body:sub(after, after + 1) == '\r\n' then after = after + 2
    elseif body:sub(after, after) == '\n' then after = after + 1 end
    write(startup, bom .. body:sub(1, first - 1) .. block .. body:sub(after))
  else
    -- Run before a foreign top-level return without changing foreign code.
    write(startup, bom .. block .. body)
  end
end

function M.enter(api, id, module_source)
  if api.BLT_ToggleRestoreWorker == id then return true end
  local _, path, section, command = api.get_action_context()
  -- Profilers/unregistered loadfile callers have no public action to dispatch.
  if section ~= 0 or not command or command <= 0 then return true end
  api.defer(function() end)
  if api.set_action_options then api.set_action_options(3) end
  local function display(on)
    api.SetToggleCommandState(0, command, on and 1 or 0);api.RefreshToolbar2(0, command)
  end
  local function attempt(fn)
    local ok, err = xpcall(fn, debug.traceback)
    if not ok then pcall(display, false);log(api, err) end
  end
  local function start()
    M.install(api, id, module_source)
    save(api, id .. '_path', path, true)
    save(api, id .. '_command', named(api, command), true)
    save(api, id .. '_enabled', '1', true)
    launch(api, id)
    display(true)
  end
  attempt(function()
    local marked = api.GetExtState(SECTION, id .. '_running') == '1'
    local pending = api.GetExtState(SECTION, id .. '_start_pending') == '1'
    if pending or marked and api.GetExtState(SECTION, id .. '_enabled') == '1' then
      -- Turning OFF must not depend on rewriting/reading startup files.
      save(api, id .. '_enabled', '0', true)
      save(api, id .. '_start_pending', '', false)
      display(false)
      return
    end
    if marked then
      save(api, id .. '_enabled', '0', true)
      save(api, id .. '_start_pending', '1', false)
      display(false)
      -- Let a stopped or unregistered worker finish before creating its replacement.
      api.defer(function() api.defer(function() attempt(function()
        if api.GetExtState(SECTION, id .. '_start_pending') ~= '1' then return end
        save(api, id .. '_start_pending', '', false)
        assert(api.GetExtState(SECTION, id .. '_running') ~= '1', 'The previous BLT worker did not stop: ' .. id)
        start()
      end) end) end)
    else start() end
  end)
  return false
end

function M.worker(api, id)
  assert(valid_id(id), 'Unknown BLT toggle worker.')
  if api.GetExtState(SECTION, id .. '_enabled') ~= '1' then
    if api.set_action_options then api.set_action_options(9) end
    return
  end
  if api.GetExtState(SECTION, id .. '_running') == '1' then return end
  local path = api.GetExtState(SECTION, id .. '_path')
  local command = api.NamedCommandLookup(api.GetExtState(SECTION, id .. '_command'))
  if not command or command <= 0 then
    command = api.AddRemoveReaScript(true, 0, path, true)
    assert(command and command > 0, 'Cannot register restored BLT action.')
    save(api, id .. '_command', named(api, command), true)
  end
  local exits, ended = {}, false
  local function finish()
    if ended then return end
    ended = true
    for i = #exits, 1, -1 do local ok, err = pcall(exits[i]);if not ok then log(api, err) end end
    -- Session-only running state is cleared on either stop or host shutdown.
    -- The persisted enabled state belongs exclusively to the public dispatcher.
    save(api, id .. '_running', '', false)
    if api.set_action_options then pcall(api.set_action_options, 9) end
    pcall(api.SetToggleCommandState, 0, command, 0);pcall(api.RefreshToolbar2, 0, command)
  end
  api.atexit(finish)
  local context = table.pack(api.get_action_context())
  context[2], context[3], context[4] = path, 0, command
  local proxy = setmetatable({BLT_ToggleRestoreWorker = id}, {__index = api})
  proxy.get_action_context = function() return table.unpack(context, 1, context.n) end
  proxy.atexit = function(fn) assert(type(fn) == 'function');exits[#exits + 1] = fn end
  proxy.defer = function(fn)
    api.defer(function()
      if ended then return end
      if api.GetExtState(SECTION, id .. '_enabled') ~= '1' then finish();return end
      local ok, err = xpcall(fn, debug.traceback)
      if not ok then finish();log(api, err) end
    end)
  end
  proxy.runloop = proxy.defer
  save(api, id .. '_running', '1', false)
  if api.set_action_options then api.set_action_options(5) end
  local env = setmetatable({reaper = proxy}, {__index = _G})
  local fn, err = loadfile(path, 't', env)
  if not fn then finish();log(api, err);return end
  local ok, reason = xpcall(fn, debug.traceback)
  if not ok then finish();log(api, reason) end
end

function M.restore(api)
  if api.GetExtState(SECTION, 'startup_done') == '1' then return end
  save(api, 'startup_done', '1', false)
  api.defer(function()
    remove_legacy_workers(api)
    for _, id in ipairs(IDS) do
      if api.GetExtState(SECTION, id .. '_enabled') == '1' then
        local ok, err = pcall(function()
          if api.GetExtState(SECTION, id .. '_running') == '1' then return end
          launch(api, id)
        end)
        if not ok then log(api, err) end
      end
    end
  end)
end

return M

]====]
local module = assert(load(BLTToggleRestoreSource, "@BLT_Toggle_Restore.lua", "t", _ENV))()
if not module.enter(reaper, 'selected_tracks', BLTToggleRestoreSource) then return end
end
-- END BLT TOGGLE RESTORE EMBEDDED
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
    local track = selected[items[i]]
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
  if not changed and n <= 2 and f == first and l == last
      and R.GetMediaItemTrack(f) == selected[f] and R.GetMediaItemTrack(l) == selected[l] then return end
  local s = R.GetProjectStateChangeCount(p)
  if not changed and s == state and f == first and l == last and now < next_audit then return end
  for i = 1, n do
    local item = i == 1 and f or (i == n and l or R.GetSelectedMediaItem(p, i - 1))
    if not item then count = -1; return end
    if selected[item] ~= R.GetMediaItemTrack(item) then changed = true end
    items[i] = item
  end
  for i = n + 1, #items do items[i] = nil end
  project, count, state, first, last = p, n, s, f, l
  next_audit = now + 0.3
  if changed then
    for item in pairs(selected) do selected[item] = nil end
    for i = 1, n do selected[items[i]] = R.GetMediaItemTrack(items[i]) end
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
