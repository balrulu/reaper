-- @description ACTION - Add Folder Covers (Auto)
-- @version 1.0.6
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
-- BEGIN BLT NATIVE DIALOGS 1.2.0 (generated from _shared/BLT_NativeDialogs.lua)
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
   local failed={}
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
     if not enabled or not topmost then failed[#failed+1]=entry end
    end
   end
   -- Do not take focus back if the user switched to another application.
   pcall(function()
    local current=api.JS_Window_GetForeground and api.JS_Window_GetForeground()
    if session.foreground and valid(session.foreground) and (current==session.main or owned(current,session.main)) then
     for _,entry in ipairs(session.windows) do
      if entry.enabled and entry.inputRestored and (session.foreground==entry.hwnd or owned(session.foreground,entry.hwnd)) then
       if api.JS_Window_SetForeground then api.JS_Window_SetForeground(entry.hwnd) end
       break
      end
     end
    end
   end)
   return failed
  end
  local function warn()
   if host.ShowConsoleMsg then
    pcall(host.ShowConsoleMsg,'BLT: ウィンドウの操作状態／最前面状態を復元できませんでした。操作できないBLTはアクションリストから終了・再実行してください。\nBLT window recovery failed after retries. Stop and restart the affected BLT action.\n')
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
   if not pending then pending={windows={},main=session.main,foreground=session.foreground};rounds=0 end
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
if not module.enter(reaper, 'folder_covers', BLTToggleRestoreSource) then return end
end
-- END BLT TOGGLE RESTORE EMBEDDED
local R = reaper
local TITLE = 'BLT Add Folder Covers (Auto)'
local TAG, TAG_VALUE = 'P_EXT:BLT_FOLDER_COVER', '1'
local SOURCE_KEY = 'P_EXT:BLT_FOLDER_COVER_SOURCE'
local NOTE_BACKUP_KEY = 'P_EXT:BLT_FOLDER_COVER_NOTE_BACKUP'
local TRACK_KEY = 'P_EXT:BLT_FOLDER_COVER_TRACK'
local EPS = 1e-9
local _, _, section, command = R.get_action_context()
local has_action = section and command and section >= 0 and command > 0
local project, applied_revision, last_rows, gesture, history_index
local bindings = {}
local display_names = {}
local cover_states = {}
local deleted_sets = {}
local stopped = false
local arrange_pending = false
local function request_arrange() arrange_pending = true end
local next_audit, audit_item, audit_track, was_editing = 0, 1, 1, false

-- Native item drag action IDs. Only movement assignments are constrained;
-- copy, trim, slip, pitch and custom actions keep their existing behavior.
local HORIZONTAL = {
  [1] = 71, [4] = 72, [13] = 73, [9] = 74,
  [14] = 75, [10] = 76, [15] = 77, [16] = 78,
  [32] = 71, [33] = 74, [34] = 73, [35] = 77,
  [22] = 71, [23] = 72,
  [49] = 79, [50] = 80, [51] = 81, [52] = 82, [53] = 83, [54] = 84
}
local MOUSE_CONTEXTS = {'MM_CTX_ITEM', 'MM_CTX_ITEMLOWER'}
local INPUT_STATE = 'BLT_FOLDER_COVER_INPUT'
local input_guard, input_project, mouse_x, mouse_y, mouse_revision
local mouse_window, mouse_check = nil, 0

local function mouse_action_id(action)
  return type(action) == 'string' and tonumber(action:match('^(%d+)%s*m?%s*$')) or nil
end

local function restore_input()
  local failed = false
  for _, context in ipairs(MOUSE_CONTEXTS) do
    for modifier = 0, 15 do
      local key = context .. ':' .. modifier
      local record = R.GetExtState(INPUT_STATE, key)
      if record ~= '' then
        local original, forced = record:match('^(.-)|(%d+)$')
        if original then
          local restored = true
          if mouse_action_id(R.GetMouseModifier(context, modifier)) == tonumber(forced) then
            local ok = pcall(R.SetMouseModifier, context, modifier, original)
            local current = R.GetMouseModifier(context, modifier)
            restored = ok and (current == original or mouse_action_id(current) == mouse_action_id(original))
          end
          if restored then R.DeleteExtState(INPUT_STATE, key, true) else failed = true end
        end
      end
    end
  end
  input_guard, input_project = nil, nil
  if failed then error('Cannot restore mouse settings. Original settings remain saved for the next script start.', 0) end
end

local constrain_input

local function finite(n)
  return type(n) == 'number' and n == n and math.abs(n) < math.huge
end

local function string_info(item, key)
  local ok, value = R.GetSetMediaItemInfo_String(item, key, '', false)
  -- A missing extension key normally returns false; ordinary empty items have no tag.
  if not ok and key:sub(1, 6) == 'P_EXT:' then return '' end
  assert(ok, 'Cannot read item information: ' .. key)
  return value
end

-- Multi-take items containing any real source remain normal media items.
local function is_blank(item)
  local n = R.CountTakes(item)
  for i = 0, n - 1 do
    local take = R.GetTake(item, i)
    local source = take and R.GetMediaItemTake_Source(take)
    if source and R.GetMediaSourceType(source) ~= 'EMPTY' then return false end
  end
  return true
end

constrain_input = function(p, flags, revision)
  if input_project and input_project ~= p then restore_input() end
  if (flags & 5) ~= 0 then return end
  local x, y = R.GetMousePosition()
  local now = R.time_precise()
  local window = R.JS_Window_FromPoint and R.JS_Window_FromPoint(x, y)
  if input_project == p and x == mouse_x and y == mouse_y and revision == mouse_revision
      and window == mouse_window and now < mouse_check then return end
  mouse_window, mouse_check = window, now + .1
  mouse_x, mouse_y, mouse_revision, input_project = x, y, revision, p
  local item = R.GetItemFromPoint(x, y, false)
  local target = item and R.ValidatePtr2(p, item, 'MediaItem*') and string_info(item, TAG) == TAG_VALUE and is_blank(item)
  if target then
    if input_guard then return end
    input_guard = true
    for _, context in ipairs(MOUSE_CONTEXTS) do
      for modifier = 0, 15 do
        local original = R.GetMouseModifier(context, modifier)
        local forced = HORIZONTAL[mouse_action_id(original)]
        if forced then
          local key = context .. ':' .. modifier
          -- Persist the original first, so a later script start can also repair
          -- settings left by an unexpected REAPER/process termination.
          R.SetExtState(INPUT_STATE, key, original .. '|' .. forced, true)
          R.SetMouseModifier(context, modifier, forced .. ' m')
          assert(mouse_action_id(R.GetMouseModifier(context, modifier)) == forced,
            'This REAPER version does not support native horizontal cover movement.')
        end
      end
    end
  elseif input_guard then
    restore_input();input_project = p
  end
end

local function by_position(a, b)
  if a.s ~= b.s then return a.s < b.s end
  if a.e ~= b.e then return a.e < b.e end
  return a.order < b.order
end

local function groups_from(ranges)
  if #ranges > 1 then table.sort(ranges, by_position) end
  local groups = {}
  for _, range in ipairs(ranges) do
    local group = groups[#groups]
    if not group or range.s >= group.e - EPS then
      group = {s = range.s, e = range.e, members = {}}
      groups[#groups + 1] = group
    elseif range.e > group.e then
      group.e = range.e
    end
    group.members[#group.members + 1] = range.guid
  end
  return groups
end

local function return_to_track(p, item, track)
  assert(R.ValidatePtr2(p, track, 'MediaTrack*'), 'Original cover track disappeared.')
  assert(R.MoveMediaItemToTrack(item, track), 'Cannot return cover to its original track.')
  assert(R.GetMediaItemTrack(item) == track, 'Cover did not return to its original track.')
end

-- Repair vertical motion before matching or deletion can see the wrong track.
-- This keeps the same item/takes/GUIDs instead of recreating a blank cover.
local function restore_known_tracks(p, drivers)
  local changed = false
  for item, state in pairs(drivers or cover_states) do
    if drivers then state = state.state;item = state.item end
    if R.ValidatePtr2(p, item, 'MediaItem*') and R.GetMediaItemTrack(item) ~= state.track
        and R.ValidatePtr2(p, state.track, 'MediaTrack*') and is_blank(item) and string_info(item, TAG) == TAG_VALUE then
      return_to_track(p, item, state.track);changed = true
    end
  end
  if changed then request_arrange() end
end

-- A single track/item traversal supplies every ancestor, with no synthetic-item feedback.
local function snapshot(p)
  local tracks, parents, by_guid, order, all_items = {}, {}, {}, 0, {}
  tracks.by_track = {}
  tracks.audit_items, tracks.audit_by_item = {}, {}
  for ti = 0, R.CountTracks(p) - 1 do
    local track = assert(R.GetTrack(p, ti), 'Track disappeared.')
    local depth = R.GetMediaTrackInfo_Value(track, 'I_FOLDERDEPTH')
    local row = {track = track, key = R.GetTrackGUID(track), index = ti, depth = depth, related = #parents > 0, ranges = {}, ranges_by_guid = {}, owned = {}, item_count = R.CountTrackMediaItems(track)}
    tracks[#tracks + 1] = row
    tracks.by_track[track] = row
    by_guid[row.key] = row
    for ii = 0, row.item_count - 1 do
      local item = assert(R.GetTrackMediaItem(track, ii), 'Item disappeared.')
      local guid = string_info(item, 'GUID')
      all_items[guid] = item
      local s = R.GetMediaItemInfo_Value(item, 'D_POSITION')
      local length = R.GetMediaItemInfo_Value(item, 'D_LENGTH')
      local e = s + length
      order = order + 1
      local tag = string_info(item, TAG)
      local managed = tag == TAG_VALUE and is_blank(item)
      local entry = {item = item, guid = guid, track = track, s = s, e = e, managed = managed}
      tracks.audit_items[#tracks.audit_items + 1] = entry;tracks.audit_by_item[item] = entry
      if managed then
        local display_name
        local take = R.GetActiveTake(item)
        if take then
          local ok, name = R.GetSetMediaItemTakeInfo_String(take, 'P_NAME', '', false)
          assert(ok, 'Cannot read cover take name.')
          display_name = name
        end
        row.owned[#row.owned + 1] = {
          item = item, guid = guid, s = s, e = e, order = order,
          display_name = display_name,
          notes = string_info(item, 'P_NOTES'),
          source_id = string_info(item, SOURCE_KEY),
          home_id = string_info(item, TRACK_KEY),
          locked = (math.floor(R.GetMediaItemInfo_Value(item, 'C_LOCK')) & 1) ~= 0
        }
      elseif finite(s) and finite(e) and length > 0 and #parents > 0 then
        local range = {s = s, e = e, guid = guid, order = order, item = item, track = track}
        for _, parent in ipairs(parents) do
          parent.ranges[#parent.ranges + 1] = range;parent.ranges_by_guid[guid] = range
        end
      end
    end
    if depth > 0 then
      parents[#parents + 1] = row
    elseif depth < 0 then
      for _ = 1, -depth do parents[#parents] = nil end
    end
  end
  local returned = false
  for _, row in ipairs(tracks) do
    local retained = {}
    for _, old in ipairs(row.owned) do
      if old.home_id == '' or old.home_id == row.key then
        retained[#retained + 1] = old
      elseif by_guid[old.home_id] then
        return_to_track(p, old.item, by_guid[old.home_id].track);returned = true
      end
      -- A cover with an unavailable original track is kept intact but is not
      -- adopted or deleted on an unrelated track (for example after a paste).
    end
    row.owned = retained
  end
  if returned then request_arrange();return snapshot(p) end
  for _, row in ipairs(tracks) do
    if #row.owned > 1 then table.sort(row.owned, by_position) end
  end
  tracks.all_items = all_items
  return tracks
end

-- Mouse edits only need geometry from cover tracks and their original children.
-- Keep unchanged rows and groups intact; a structural change uses a full scan.
local function refresh_rows(p, cached)
  if R.CountTracks(p) ~= #cached then return nil end
  for _, row in ipairs(cached.watch_tracks) do
    if R.GetTrack(p, row.index) ~= row.track
        or R.CountTrackMediaItems(row.track) ~= row.item_count
        or R.GetMediaTrackInfo_Value(row.track, 'I_FOLDERDEPTH') ~= row.depth then return nil end
  end
  local changed, dirty, indexed = {}, {}, {}
  for _, entry in ipairs(cached.watch_items) do
    local item = entry.item
    local slots = indexed[entry.track]
    if not slots and R.GetTrackMediaItem(entry.track, entry.slot) ~= item then
      slots = {};indexed[entry.track] = slots
      for i = 0, cached.by_track[entry.track].item_count - 1 do
        local current = R.GetTrackMediaItem(entry.track, i)
        if not current then return nil end
        slots[current] = i
      end
    end
    if slots then
      entry.slot = slots[item]
      if entry.slot == nil then return nil end
    end
    local s = R.GetMediaItemInfo_Value(item, 'D_POSITION')
    local e = s + R.GetMediaItemInfo_Value(item, 'D_LENGTH')
    if math.abs(s - entry.s) > EPS or math.abs(e - entry.e) > EPS then
      changed[item] = {s = s, e = e}
      for _, track in ipairs(entry.parents) do dirty[track] = true end
    end
  end
  if not next(changed) then return false end
  local rows, ranges = cached, {}
  rows.dirty, rows.geometry, rows.dirty_rows = dirty, changed, {}
  for track in pairs(dirty) do
    local prior = cached.by_track[track]
    local row = {track = prior.track, key = prior.key, index = prior.index, depth = prior.depth, related = prior.related,
      item_count = prior.item_count, ranges = {}, ranges_by_guid = {}, owned = {}}
    for _, old in ipairs(prior.owned) do
      local copy, value = old, changed[old.item]
      if value then
        copy = {};for k, v in pairs(old) do copy[k] = v end
        copy.s, copy.e = value.s, value.e
      end
      row.owned[#row.owned + 1] = copy
    end
    for _, previous in ipairs(prior.ranges) do
      local range = ranges[previous.item]
      if not range then
        range = previous;local value = changed[previous.item]
        if value then
          range = {};for k, v in pairs(previous) do range[k] = v end
          range.s, range.e = value.s, value.e
        end
        ranges[previous.item] = range
      end
      if finite(range.s) and finite(range.e) and range.e > range.s then
        row.ranges[#row.ranges + 1] = range;row.ranges_by_guid[range.guid] = range
      end
    end
    if #row.owned > 1 then table.sort(row.owned, by_position) end
    rows[prior.index + 1] = row;rows.by_track[track] = row
    rows.dirty_rows[#rows.dirty_rows + 1] = row
  end
  table.sort(rows.dirty_rows, function(a, b) return a.index < b.index end)
  return rows
end

local function sync_removed_covers(p, rows, suppress_delete)
  local saved, present, changed = deleted_sets[p], rows.all_items, false

  -- Native Undo may restore only the deleted parent item. Restore any original
  -- children missing from that undo snapshot, without creating an extra entry.
  if saved then
    local restored, completed = {}, {}
    local ok, err = xpcall(function()
      for guid, children in pairs(saved) do
        local parent = present[guid]
        if parent and is_blank(parent) and string_info(parent, TAG) == TAG_VALUE then
          local complete = true
          for _, child in ipairs(children) do
            if not present[child.guid] then
              if R.ValidatePtr2(p, child.track, 'MediaTrack*') then
                local item = assert(R.AddMediaItemToTrack(child.track), 'Cannot restore deleted cover child.')
                restored[#restored + 1] = {item = item, track = child.track}
                assert(R.SetItemStateChunk(item, child.chunk, false), 'Cannot restore deleted child information.')
                present[child.guid] = item;changed = true
              else complete = false end
            end
          end
          if complete then completed[#completed + 1] = guid end
        end
      end
    end, debug.traceback)
    if not ok then
      for i = #restored, 1, -1 do pcall(R.DeleteTrackMediaItem, restored[i].track, restored[i].item) end
      error(err, 0)
    end
    for _, guid in ipairs(completed) do saved[guid] = nil end
    if not next(saved) then deleted_sets[p] = nil end
    if changed then request_arrange();return true end
  end
  if suppress_delete then return false end

  local missing
  for _, state in pairs(cover_states) do
    local row = rows.by_track[state.track]
    if not present[state.guid] and row and row.depth > 0 and not state.locked
        and not R.ValidatePtr2(p, state.item, 'MediaItem*')
        and R.GetMediaTrackInfo_Value(state.track, 'I_FOLDERCOMPACT') > 0 then
      missing = missing or {};missing[#missing + 1] = state
    end
  end
  if not missing then return false end

  local pool, batches, targets = {}, {}, {}
  for _, state in ipairs(missing) do
    local available, children = rows.by_track[state.track].ranges_by_guid, {}
    for _, child in ipairs(state.children) do
      local range = available[child.guid]
      if range and (math.floor(R.GetMediaItemInfo_Value(range.item, 'C_LOCK')) & 1) == 0 then
        if not pool[child.guid] then
          local read, chunk = R.GetItemStateChunk(range.item, '', false)
          assert(read, 'Cannot back up child before deleting closed cover.')
          pool[child.guid] = {guid = child.guid, item = range.item, track = range.track, chunk = chunk}
          targets[#targets + 1] = pool[child.guid]
        end
        children[#children + 1] = pool[child.guid]
      end
    end
    if #children > 0 then batches[state.guid] = children end
  end
  if not next(pool) then return false end
  -- Derived covers on other folder levels may disappear after their sources are
  -- removed. Keep their metadata with the same native deletion for Undo as well.
  local auxiliary, dependents = {}, {}
  for _, state in pairs(cover_states) do
    if present[state.guid] then
      for _, child in ipairs(state.children) do
        if pool[child.guid] then
          local list = dependents[child.guid]
          if not list then list = {};dependents[child.guid] = list end
          list[#list + 1] = state
        end
      end
    end
  end
  for _, children in pairs(batches) do
    local counts = {}
    for _, child in ipairs(children) do
      for _, state in ipairs(dependents[child.guid] or {}) do counts[state] = (counts[state] or 0) + 1 end
    end
    for state, count in pairs(counts) do
      if count == #state.children and is_blank(state.item) and string_info(state.item, TAG) == TAG_VALUE then
        if not auxiliary[state.guid] then
          local read, chunk = R.GetItemStateChunk(state.item, '', false)
          assert(read, 'Cannot preserve related cover before deleting children.')
          auxiliary[state.guid] = {guid = state.guid, track = state.track, chunk = chunk}
        end
        children[#children + 1] = auxiliary[state.guid]
      end
    end
  end
  local removed = 0
  local ok, err = xpcall(function()
    for i, child in ipairs(targets) do
      assert(R.DeleteTrackMediaItem(child.track, child.item), 'Cannot delete closed cover child.')
      removed = i
    end
  end, debug.traceback)
  if not ok then
    for i = 1, removed do
      local child = targets[i]
      pcall(function()
        local item = assert(R.AddMediaItemToTrack(child.track))
        assert(R.SetItemStateChunk(item, child.chunk, false))
      end)
    end
    error(err, 0)
  end
  saved = deleted_sets[p] or {};deleted_sets[p] = saved
  for guid, children in pairs(batches) do saved[guid] = children end
  request_arrange();return true
end

local function begin_gesture()
  local session = {by_track = {}, drivers = {}}
  for _, state in pairs(cover_states) do
    local states = session.by_track[state.track]
    if not states then states = {};session.by_track[state.track] = states end
    states[#states + 1] = state
    if not state.locked and R.IsMediaItemSelected(state.item) then
      session.drivers[#session.drivers + 1] = {state = state, active = false, last_position = state.s}
    end
  end
  -- An outer cover wins when selected nested covers refer to the same child.
  table.sort(session.drivers, function(a, b) return #a.state.children > #b.state.children end)
  return session
end

local function move_gesture_children(p, session)
  local targets, journal, changed = {}, {}, false
  for _, driver in ipairs(session.drivers) do
    local state = driver.state
    local valid = R.ValidatePtr2(p, state.item, 'MediaItem*') and R.GetMediaItemTrack(state.item) == state.track
    local delta = valid and R.GetMediaItemInfo_Value(state.item, 'D_POSITION') - state.s or 0
    if valid and math.abs(state.s + delta - (driver.last_position or state.s)) > EPS then driver.active = true end
    valid = valid and driver.active and is_blank(state.item) and string_info(state.item, TAG) == TAG_VALUE
    if valid then
      local length = R.GetMediaItemInfo_Value(state.item, 'D_LENGTH')
      valid = math.abs(length - (state.e - state.s)) <= EPS
        and (math.floor(R.GetMediaItemInfo_Value(state.item, 'C_LOCK')) & 1) == 0
    end
    if valid then
      for _, child in ipairs(state.children) do
        if not R.ValidatePtr2(p, child.item, 'MediaItem*') or R.GetMediaItemTrack(child.item) ~= child.track
            or (math.floor(R.GetMediaItemInfo_Value(child.item, 'C_LOCK')) & 1) ~= 0 then valid = false;break end
      end
    end
    if valid then
      for _, child in ipairs(state.children) do
        if not targets[child.item] then targets[child.item] = child.s + delta end
      end
    end
  end
  local ok, err = xpcall(function()
    for item, position in pairs(targets) do
      local before = R.GetMediaItemInfo_Value(item, 'D_POSITION')
      if math.abs(position - before) > EPS then
        journal[#journal + 1] = {item = item, position = before}
        assert(R.SetMediaItemInfo_Value(item, 'D_POSITION', position), 'Cannot move cover child.')
        changed = true
      end
    end
  end, debug.traceback)
  if not ok then
    for i = #journal, 1, -1 do pcall(R.SetMediaItemInfo_Value, journal[i].item, 'D_POSITION', journal[i].position) end
    error(err, 0)
  end
  if changed then request_arrange() end
end

-- Also recognize item-only native Undo/Redo or a position edit outside a mouse
-- gesture. Propagate only if children are unchanged or already moved by exactly
-- the same amount, so a child edit is never mistaken for a cover command.
local function move_changed_covers(p)
  local session = {drivers = {}}
  for _, state in pairs(cover_states) do
    local valid = not state.locked and R.ValidatePtr2(p, state.item, 'MediaItem*')
      and R.GetMediaItemTrack(state.item) == state.track
    local delta = valid and R.GetMediaItemInfo_Value(state.item, 'D_POSITION') - state.s or 0
    if valid and math.abs(delta) > EPS then
      valid = math.abs(R.GetMediaItemInfo_Value(state.item, 'D_LENGTH') - (state.e - state.s)) <= EPS
      for _, child in ipairs(state.children) do
        if not valid or not R.ValidatePtr2(p, child.item, 'MediaItem*') then valid = false;break end
        local position = R.GetMediaItemInfo_Value(child.item, 'D_POSITION')
        if math.abs(R.GetMediaItemInfo_Value(child.item, 'D_LENGTH') - (child.e - child.s)) > EPS
            or (math.abs(position - child.s) > EPS and math.abs(position - child.s - delta) > EPS) then valid = false;break end
      end
      if valid then session.drivers[#session.drivers + 1] = {state = state, active = true} end
    end
  end
  table.sort(session.drivers, function(a, b) return #a.state.children > #b.state.children end)
  if #session.drivers > 0 then move_gesture_children(p, session) end
end

-- Keep original child GUID sets for the entire drag. Passing another group must
-- not change membership or delete a cover midway through the gesture.
local function freeze_groups(rows, session)
  for _, row in ipairs(rows.dirty_rows or rows) do
    if not rows.dirty or rows.dirty[row.track] then
      local owned, available, assigned, groups = {}, row.ranges_by_guid, {}, {}
      for _, old in ipairs(row.owned) do owned[old.item] = old end
      for _, state in ipairs(session.by_track[row.track] or {}) do
        local old = owned[state.item]
        if old then
          local group = {s = math.huge, e = -math.huge, members = {}, old = old}
          for _, child in ipairs(state.children) do
            local range = available[child.guid]
            if range then
              group.s, group.e = math.min(group.s, range.s), math.max(group.e, range.e)
              group.members[#group.members + 1] = range.guid;assigned[range.guid] = true
            end
          end
          if #group.members > 0 then groups[#groups + 1] = group end
        end
      end
      local extra = {}
      for _, range in ipairs(row.ranges) do if not assigned[range.guid] then extra[#extra + 1] = range end end
      for _, group in ipairs(groups_from(extra)) do groups[#groups + 1] = group end
      if #groups > 1 then table.sort(groups, function(a, b) return a.s < b.s end) end
      row.groups = groups
    end
  end
end

local function overlap(a, b)
  return math.max(0, math.min(a.e, b.e) - math.max(a.s, b.s))
end

local function has_name(old)
  return old.display_name and old.display_name:find('%S') ~= nil or false
end

-- Only inspect generic extensions when multiple unnamed covers actually compete.
-- The common render-channel tag has a direct API lookup; no chunk read is needed.
local function has_external_tags(item)
  if string_info(item, 'P_EXT:BLT_DEDICATED_RENDER_CHANNELS') ~= '' then return true end
  local ok, chunk = R.GetItemStateChunk(item, '', false)
  assert(ok, 'Cannot inspect cover extension tags.')
  local depth, extension_depth = 0, nil
  for line in chunk:gmatch('[^\r\n]+') do
    if line:match('^%s*<') then
      depth = depth + 1
      if line:match('^%s*<EXTI?%s*$') then extension_depth = depth end
    elseif line:match('^%s*>%s*$') then
      if extension_depth == depth then extension_depth = nil end
      depth = depth - 1
    elseif extension_depth == depth then
      local key, value = line:match('^%s*(%S+)[ \t]+(.-)%s*$')
      if key and key:sub(1, 16) ~= 'BLT_FOLDER_COVER' and value ~= '' and value ~= '""' then return true end
    end
  end
  return false
end

-- Prefer shared child GUIDs so a labelled item survives even a long-distance move.
-- The in-memory map is rebuilt from current groups, never appended to project data.
local function match_groups(row, previous)
  if #row.owned == 0 or #row.groups == 0 then return {} end
  local used, pending = {}, false
  for _, group in ipairs(row.groups) do
    if group.old then used[group.old.item] = true else pending = true end
  end
  if not pending then return used end
  local existing, candidates, source_links, linked = {}, {}, {}, {}
  for _, old in ipairs(row.owned) do
    existing[old.item] = old
    if old.source_id ~= '' and not source_links[old.source_id] then source_links[old.source_id] = old.item end
  end
  for gi, group in ipairs(row.groups) do
    if not group.old then
    local votes = {}
    for _, guid in ipairs(group.members) do
      local item = previous and previous[guid]
      if not item or not existing[item] then item = source_links[guid] end
      if item and existing[item] then votes[item] = (votes[item] or 0) + 1 end
    end
    for item, count in pairs(votes) do
      local old = existing[item]
      linked[item] = true
      candidates[#candidates + 1] = {
        group = gi, old = old, count = count, overlap = overlap(group, old),
        distance = math.abs(group.s - old.s)
      }
    end
    end
  end
  -- Unlinked covers can still belong to a merged range after their saved child
  -- was removed. Use time overlap only if no surviving child identifies them.
  local first = 1
  for _, old in ipairs(row.owned) do
    if not linked[old.item] and not used[old.item] then
      while first <= #row.groups and row.groups[first].e <= old.s do first = first + 1 end
      local gi = first
      while gi <= #row.groups and row.groups[gi].s < old.e do
        local group = row.groups[gi]
        candidates[#candidates + 1] = {
          group = gi, old = old, count = 0, overlap = overlap(group, old),
          distance = math.abs(group.s - old.s)
        }
        gi = gi + 1
      end
    end
  end
  local choices = {}
  for _, candidate in ipairs(candidates) do
    local choice = choices[candidate.group] or {count = 0, named = false}
    choices[candidate.group] = choice;choice.count = choice.count + 1
    choice.named = choice.named or has_name(candidate.old)
  end
  for _, candidate in ipairs(candidates) do
    local choice, old = choices[candidate.group], candidate.old
    if choice.count > 1 and not choice.named and old.external_tags == nil then
      old.external_tags = has_external_tags(old.item)
    end
  end
  table.sort(candidates, function(a, b)
    -- Preserve the earliest named object. With no name, prefer an object with
    -- external tags, then time order; the retained object keeps all metadata.
    local an, bn = has_name(a.old), has_name(b.old)
    if an ~= bn then return an end
    if not an and not bn and (a.old.external_tags == true) ~= (b.old.external_tags == true) then
      return a.old.external_tags == true
    end
    if a.old.s ~= b.old.s then return a.old.s < b.old.s end
    if a.old.order ~= b.old.order then return a.old.order < b.old.order end
    if a.count ~= b.count then return a.count > b.count end
    if a.overlap ~= b.overlap then return a.overlap > b.overlap end
    if a.distance ~= b.distance then return a.distance < b.distance end
    return a.group < b.group
  end)
  for _, candidate in ipairs(candidates) do
    local group, old = row.groups[candidate.group], candidate.old
    if not group.old and not used[old.item] then group.old = old; used[old.item] = true end
  end
  -- An old cover can match several new ranges after a split. Every unmatched
  -- branch inherits that original object, even though only one can keep it.
  for _, candidate in ipairs(candidates) do
    local group = row.groups[candidate.group]
    if not group.old and not group.template then group.template = candidate.old end
  end
  -- After restarting, the persistent representative may identify only one
  -- branch. An original cover spanning another branch still supplies its data.
  for _, group in ipairs(row.groups) do
    if not group.old and not group.template then
      local best
      for _, old in ipairs(row.owned) do
        if used[old.item] and overlap(old, group) > EPS
            and (not best or (has_name(old) and not has_name(best))
              or (has_name(old) == has_name(best) and old.s < best.s)) then best = old end
      end
      group.template = best
    end
  end
  return used
end

-- Only the root item's display flag is changed; nested source data stays intact.
local function display_chunk(item)
  local ok, chunk = R.GetItemStateChunk(item, '', false)
  assert(ok, 'Cannot read cover display settings.')
  local depth, found, changed = 0, false, false
  local updated = chunk:gsub('[^\n]+\n?', function(line)
    if depth == 1 then
      local prefix, value, ending = line:match('^([ \t]*IMGRESOURCEFLAGS[ \t]+)([^\r\n]*)(\r?\n?)$')
      if prefix then
        found = true
        if tonumber(value) ~= 3 then changed = true;return prefix .. '3' .. ending end
      end
    end
    if line:match('^%s*<') then depth = depth + 1
    elseif line:match('^%s*>%s*$') then depth = depth - 1 end
    return line
  end)
  if not found then
    local count
    local newline = chunk:match('\r?\n') or '\n'
    updated, count = chunk:gsub('^(<ITEM[^\r\n]*\r?\n)', function(header)
      return header .. 'IMGRESOURCEFLAGS 3' .. newline
    end, 1)
    assert(count == 1, 'Cannot locate cover item header.')
    changed = true
  end
  return changed and updated or nil
end

local function clone_chunk(chunk)
  local depth, extension_depth = 0, nil
  return chunk:gsub('[^\n]+\n?', function(line)
    if not extension_depth then
      local prefix, key, guid, tail, ending = line:match('^([ \t]*)(%u+)[ \t]+({[%x%-]+})([^\r\n]*)(\r?\n?)$')
      if key == 'IGUID' or key == 'GUID' or key == 'FXID' or key == 'EGUID' then
        line = prefix .. key .. ' ' .. assert(R.genGuid(), 'Cannot create copied cover GUID.') .. tail .. ending
      elseif depth == 1 then
        line = line:gsub('^([ \t]*SEL[ \t]+)[^ \t\r\n]+', function(p) return p .. '0' end, 1)
      end
    end
    if line:match('^%s*<') then
      depth = depth + 1
      if line:match('^%s*<EXTI?%s*\r?\n?$') then extension_depth = depth end
    elseif line:match('^%s*>%s*$') then
      if extension_depth == depth then extension_depth = nil end
      depth = depth - 1
    end
    return line
  end)
end

local function writable_cover(old)
  if not is_blank(old.item) or string_info(old.item, TAG) ~= TAG_VALUE then return false end
  old.locked = (math.floor(R.GetMediaItemInfo_Value(old.item, 'C_LOCK')) & 1) ~= 0
  return true
end

local function make_plan(rows)
  local plan = {create = {}, move = {}, remove = {}, source_id = {}, track_id = {}, display = {}}
  for _, row in ipairs(rows.dirty_rows or rows) do
    if not rows.dirty or rows.dirty[row.track] then
      local used = match_groups(row, bindings[row.key])
      for _, group in ipairs(row.groups) do
        local old = group.old
        group.source_id = group.members[1]
        if old then
          for _, guid in ipairs(group.members) do
            if guid == old.source_id then group.source_id = old.source_id; break end
          end
        end
        local previous, display
        if old then
          previous = display_names[old.item]
          local clear_label = previous and previous.name ~= '' and old.display_name == '' and old.notes == previous.name
          display = old.display_name ~= nil and (old.display_name ~= '' or clear_label)
            and (old.notes ~= old.display_name or not previous or previous.name ~= old.display_name or previous.notes ~= old.notes)
          if (math.abs(old.s - group.s) > EPS or math.abs(old.e - group.e) > EPS
              or old.source_id ~= group.source_id or old.home_id ~= row.key or display)
              and not writable_cover(old) then return nil end
        end
        if not old then
          plan.create[#plan.create + 1] = {row = row, group = group}
        elseif not old.locked and (math.abs(old.s - group.s) > EPS or math.abs(old.e - group.e) > EPS) then
          plan.move[#plan.move + 1] = {row = row, group = group, item = old.item}
        end
        if old and not old.locked and old.source_id ~= group.source_id then
          plan.source_id[#plan.source_id + 1] = {row = row, group = group, item = old.item}
        end
        if old and not old.locked and old.home_id ~= row.key then
          plan.track_id[#plan.track_id + 1] = {row = row, item = old.item}
        end
        if old and not old.locked and display then
          plan.display[#plan.display + 1] = {row = row, item = old.item, old = old, name = old.display_name, previous = previous}
        end
      end
      for _, old in ipairs(row.owned) do
        if not used[old.item] then
          if not writable_cover(old) then return nil end
          if not old.locked then plan.remove[#plan.remove + 1] = {row = row, item = old.item} end
        end
      end
    end
  end
  return plan
end

local function remember(rows)
  local incremental = rows.dirty ~= nil
  local current = incremental and bindings or {}
  local names = incremental and display_names or {}
  local states = incremental and cover_states or {}
  for _, row in ipairs(rows.dirty_rows or rows) do
    if not incremental or rows.dirty[row.track] then
      current[row.key] = nil
      local live, kept, lookup = {}, {}, row.ranges_by_guid
      if #row.groups > 0 then
        local map = {}
        for _, group in ipairs(row.groups) do
          local item = group.item or (group.old and group.old.item)
          for _, guid in ipairs(group.members) do map[guid] = item end
          local old = group.old
          if not old then
            local original = group.template
            old = {item = item, order = 1000000000 + #live, display_name = group.display_name or '',
              s = group.s, e = group.e, source_id = group.source_id, home_id = row.key,
              notes = original and original.notes or '', locked = original and original.locked or false,
              guid = string_info(item, 'GUID')}
          elseif not old.locked then
            old.s, old.e, old.source_id, old.home_id = group.s, group.e, group.source_id, row.key
          end
          local previous = display_names[item]
          if old.locked then names[item] = previous
          elseif not previous or previous.name ~= old.display_name or previous.notes ~= old.notes then
            names[item] = {name = old.display_name, notes = old.notes}
          else names[item] = previous end
          live[#live + 1] = old;kept[item] = true
          rows.all_items[old.guid] = item
          local entry = rows.audit_by_item[item]
          if not entry then
            entry = {item = item, guid = old.guid};rows.audit_items[#rows.audit_items + 1] = entry
            rows.audit_by_item[item] = entry
          end
          entry.track, entry.s, entry.e, entry.managed, entry.cover = row.track, old.s, old.e, true, old
          local state = incremental and cover_states[item]
          local changed = not state or state.s ~= old.s or state.e ~= old.e or state.locked ~= old.locked or #state.children ~= #group.members
          if not changed then
            for i, guid in ipairs(group.members) do
              if state.children[i] ~= lookup[guid] then changed = true;break end
            end
          end
          if changed then
            state = {item = item, guid = old.guid, track = row.track, s = old.s, e = old.e, locked = old.locked, children = {}}
            for _, guid in ipairs(group.members) do state.children[#state.children + 1] = lookup[guid] end
          end
          states[item] = state
        end
        current[row.key] = map
      end
      for _, old in ipairs(row.owned) do
        if not kept[old.item] then
          names[old.item], states[old.item] = nil, nil
          if old.locked then
            live[#live + 1] = old;rows.audit_by_item[old.item].cover = old
          else rows.all_items[old.guid] = nil end
        end
      end
      row.owned = live
      if #live > 1 then table.sort(live, by_position) end
    end
  end
  bindings = current
  display_names = names
  cover_states, last_rows = states, rows
  if incremental and not rows.rebuild_watch then
    for item, value in pairs(rows.geometry) do
      local entry = rows.watch_by_item[item]
      if entry then entry.s, entry.e = value.s, value.e end
    end
    for i, prior in ipairs(rows.watch_tracks) do
      local row = rows.by_track[prior.track];rows.watch_tracks[i] = row
      if rows.dirty[row.track] then
        for _, old in ipairs(row.owned) do
          local entry = rows.watch_by_item[old.item]
          if entry then entry.s, entry.e = old.s, old.e end
        end
      end
    end
    return
  end
  local watched = {}
  rows.watch_items, rows.watch_tracks, rows.watch_by_item = {}, {}, watched
  local function watch(item, track, s, e, parent)
    local entry = watched[item]
    if not entry then
      entry = {item = item, track = track, slot = R.GetMediaItemInfo_Value(item, 'IP_ITEMNUMBER'), s = s, e = e, parents = {}}
      watched[item] = entry;rows.watch_items[#rows.watch_items + 1] = entry
    end
    entry.parents[#entry.parents + 1] = parent
  end
  for _, row in ipairs(rows) do
    if row.related or row.depth > 0 or #row.owned > 0 then rows.watch_tracks[#rows.watch_tracks + 1] = row end
    for _, old in ipairs(row.owned) do watch(old.item, row.track, old.s, old.e, row.track) end
    for _, range in ipairs(row.ranges) do watch(range.item, range.track, range.s, range.e, row.track) end
  end
end

local function validate_plan(p, plan)
  for _, entries in ipairs({plan.create, plan.move, plan.remove, plan.source_id, plan.track_id, plan.display}) do
    for _, entry in ipairs(entries) do
      assert(R.ValidatePtr2(p, entry.row.track, 'MediaTrack*'), 'Target track changed.')
      if entry.item then
        assert(R.ValidatePtr2(p, entry.item, 'MediaItem*'), 'Target item changed.')
        assert(R.GetMediaItemTrack(entry.item) == entry.row.track, 'Target item moved to another track.')
        assert(string_info(entry.item, TAG) == TAG_VALUE, 'Cover ownership changed.')
      end
    end
  end
end

local function set_range(item, group, position, length)
  if not position or math.abs(position - group.s) > EPS then
    assert(R.SetMediaItemInfo_Value(item, 'D_POSITION', group.s), 'Cannot set cover position.')
  end
  if not length or math.abs(length - (group.e - group.s)) > EPS then
    assert(R.SetMediaItemInfo_Value(item, 'D_LENGTH', group.e - group.s), 'Cannot set cover length.')
  end
end

local function apply_plan(p, plan)
  validate_plan(p, plan)
  local journal, templates = {}, {}
  local function save_chunk(item)
    local ok, chunk = R.GetItemStateChunk(item, '', false)
    assert(ok, 'Cannot back up cover state.')
    journal[#journal + 1] = function() return R.SetItemStateChunk(item, chunk, false) end
    return chunk
  end
  R.PreventUIRefresh(1)
  local ok, err = xpcall(function()
    for _, entry in ipairs(plan.display) do
      save_chunk(entry.item)
      local notes = entry.old.notes
      local last_label = entry.previous and entry.previous.name
      if notes ~= '' and notes ~= entry.name and notes ~= last_label and string_info(entry.item, NOTE_BACKUP_KEY) == '' then
        assert(R.GetSetMediaItemInfo_String(entry.item, NOTE_BACKUP_KEY, notes, true), 'Cannot preserve existing cover note.')
      end
      if notes ~= entry.name then
        assert(R.GetSetMediaItemInfo_String(entry.item, 'P_NOTES', entry.name, true), 'Cannot copy cover take name to notes.')
      end
      local chunk = display_chunk(entry.item)
      if chunk then assert(R.SetItemStateChunk(entry.item, chunk, false), 'Cannot update cover display settings.') end
      entry.old.notes = entry.name
    end
    for _, entry in ipairs(plan.create) do
      local item = assert(R.AddMediaItemToTrack(entry.row.track), 'Cannot create cover.')
      journal[#journal + 1] = function()
        if R.ValidatePtr2(p, item, 'MediaItem*') then return R.DeleteTrackMediaItem(entry.row.track, item) end
        return true
      end
      local original = entry.group.template
      if original then
        if not templates[original.item] then
          local read, chunk = R.GetItemStateChunk(original.item, '', false)
          assert(read, 'Cannot read split cover information.')
          templates[original.item] = chunk
        end
        assert(R.SetItemStateChunk(item, clone_chunk(templates[original.item]), false), 'Cannot copy split cover information.')
        entry.group.display_name = original.display_name
      else
        local take = assert(R.AddTakeToMediaItem(item), 'Cannot create empty take.')
        assert(R.GetSetMediaItemTakeInfo_String(take, 'P_NAME', '', true), 'Cannot initialize item name.')
      end
      assert(R.GetSetMediaItemInfo_String(item, TAG, TAG_VALUE, true), 'Cannot tag cover.')
      assert(R.GetSetMediaItemInfo_String(item, SOURCE_KEY, entry.group.source_id, true), 'Cannot store cover source link.')
      assert(R.GetSetMediaItemInfo_String(item, TRACK_KEY, entry.row.key, true), 'Cannot store original cover track.')
      set_range(item, entry.group)
      local chunk = display_chunk(item)
      if chunk then assert(R.SetItemStateChunk(item, chunk, false), 'Cannot initialize cover display settings.') end
      entry.group.item = item
      entry.row.item_count = entry.row.item_count + 1
    end
    for _, entry in ipairs(plan.move) do
      local s = R.GetMediaItemInfo_Value(entry.item, 'D_POSITION')
      local length = R.GetMediaItemInfo_Value(entry.item, 'D_LENGTH')
      journal[#journal + 1] = function()
        local moved = R.SetMediaItemInfo_Value(entry.item, 'D_POSITION', s)
        return R.SetMediaItemInfo_Value(entry.item, 'D_LENGTH', length) and moved
      end
      set_range(entry.item, entry.group, s, length)
    end
    for _, entry in ipairs(plan.source_id) do
      local previous = string_info(entry.item, SOURCE_KEY)
      journal[#journal + 1] = function() return R.GetSetMediaItemInfo_String(entry.item, SOURCE_KEY, previous, true) end
      assert(R.GetSetMediaItemInfo_String(entry.item, SOURCE_KEY, entry.group.source_id, true), 'Cannot update cover source link.')
    end
    for _, entry in ipairs(plan.track_id) do
      local previous = string_info(entry.item, TRACK_KEY)
      journal[#journal + 1] = function() return R.GetSetMediaItemInfo_String(entry.item, TRACK_KEY, previous, true) end
      assert(R.GetSetMediaItemInfo_String(entry.item, TRACK_KEY, entry.row.key, true), 'Cannot store original cover track.')
    end
    for _, entry in ipairs(plan.remove) do
      local read, chunk = R.GetItemStateChunk(entry.item, '', false)
      assert(read, 'Cannot back up obsolete cover.')
      assert(R.DeleteTrackMediaItem(entry.row.track, entry.item), 'Cannot remove obsolete cover.')
      entry.row.item_count = entry.row.item_count - 1
      journal[#journal + 1] = function()
        local restored = R.AddMediaItemToTrack(entry.row.track)
        return restored and R.SetItemStateChunk(restored, chunk, false)
      end
    end
  end, debug.traceback)
  R.PreventUIRefresh(-1)
  request_arrange()
  if not ok then
    local restored = true
    for i = #journal, 1, -1 do
      local success, result = pcall(journal[i]);if not success or result == false or result == nil then restored = false end
    end
    request_arrange()
    error(tostring(err) .. (restored and '\nThe automatic changes were restored.' or '\nSome automatic changes could not be restored.'), 0)
  end
end

local function cleanup()
  if stopped then return end
  stopped = true
  bindings = {}
  display_names = {}
  cover_states, last_rows, gesture = {}, nil, nil
  deleted_sets = {}
  pcall(restore_input)
  if R.set_action_options then pcall(R.set_action_options, 9) end
  if has_action then
    pcall(R.SetToggleCommandState, section, command, 0)
    pcall(R.RefreshToolbar2, section, command)
  end
end

-- Native setters can edit items without advancing the project revision.
local function audit_changed(p, now)
  if now < next_audit then return false end
  next_audit = now + .1
  if R.CountTracks(p) ~= #last_rows then return true end
  for _ = 1, math.min(32, #last_rows) do
    local index = audit_track;local row = last_rows[index]
    audit_track = index % #last_rows + 1
    if R.GetTrack(p, index - 1) ~= row.track or R.CountTrackMediaItems(row.track) ~= row.item_count
        or R.GetMediaTrackInfo_Value(row.track, 'I_FOLDERDEPTH') ~= row.depth then return true end
  end
  for _ = 1, math.min(64, #last_rows.audit_items) do
    local index = audit_item;local entry = last_rows.audit_items[index]
    audit_item = index % #last_rows.audit_items + 1
    if last_rows.all_items[entry.guid] == entry.item then
      local item = entry.item
      if not R.ValidatePtr2(p, item, 'MediaItem*') or R.GetMediaItemTrack(item) ~= entry.track
          or string_info(item, 'GUID') ~= entry.guid then return true end
      local managed = string_info(item, TAG) == TAG_VALUE and is_blank(item)
      local s = R.GetMediaItemInfo_Value(item, 'D_POSITION')
      if managed ~= entry.managed or math.abs(s - entry.s) > EPS
          or math.abs(s + R.GetMediaItemInfo_Value(item, 'D_LENGTH') - entry.e) > EPS then return true end
      local old = entry.cover
      if old then
        local take, name = R.GetActiveTake(item), nil
        if take then local ok;ok, name = R.GetSetMediaItemTakeInfo_String(take, 'P_NAME', '', false);assert(ok, 'Cannot read cover take name.') end
        if name ~= old.display_name or string_info(item, 'P_NOTES') ~= old.notes
            or string_info(item, SOURCE_KEY) ~= old.source_id or string_info(item, TRACK_KEY) ~= old.home_id
            or ((math.floor(R.GetMediaItemInfo_Value(item, 'C_LOCK')) & 1) ~= 0) ~= old.locked then return true end
      end
    end
  end
  return false
end

local function update()
  local p = R.EnumProjects(-1, '')
  if not p then return end
  local revision = R.GetProjectStateChangeCount(p)
  local changed_project = p ~= project
  if p ~= project then
    project, applied_revision, history_index = p, nil, nil
    bindings, display_names, cover_states, last_rows, gesture = {}, {}, {}, nil, nil
    audit_item, audit_track, was_editing = 1, 1, false
  end
  local flags = 0
  if R.GetItemEditingTime2 then local _, _, f = R.GetItemEditingTime2();flags = f or 0 end
  constrain_input(p, flags, revision)
  if (R.GetPlayStateEx(p) & 4) ~= 0 then return end
  local moving, editing = (flags & 4) ~= 0, (flags & 5) ~= 0
  local released = was_editing and not editing;was_editing = editing
  local redo = R.Undo_CanRedo2(p)
  -- Available redo history describes an older action, not the current mouse
  -- operation. REAPER may retain it until a new drag is committed on release.
  -- A live move/edge edit must still use its original child set and geometry.
  local undoing = redo and redo ~= '' and not editing
  local current_history = R.Undo_GetCurEntry and R.Undo_GetCurEntry(p)
  local suppress_delete = current_history and history_index and current_history < history_index
    or (not R.Undo_GetCurEntry and undoing)
  if undoing then gesture = nil end
  local counts_changed = not last_rows or R.CountMediaItems(p) ~= last_rows.item_count
  local silent = false
  if not changed_project and applied_revision == revision and not editing and not gesture and not released and not counts_changed then
    silent = audit_changed(p, R.time_precise());if not silent then return end
  end
  if not editing then restore_known_tracks(p) end
  if moving and not gesture and not undoing and next(cover_states) then gesture = begin_gesture() end
  if gesture then restore_known_tracks(p, gesture.drivers);move_gesture_children(p, gesture)
  elseif not editing and not changed_project and (revision ~= applied_revision or silent or counts_changed) then move_changed_covers(p) end
  local rows
  if editing and last_rows and not undoing and not counts_changed then
    rows = refresh_rows(p, last_rows)
    if rows == false then
      applied_revision = R.GetProjectStateChangeCount(p);history_index = current_history
      return
    end
  end
  rows = rows or snapshot(p)
  if R.EnumProjects(-1, '') ~= p then return end
  if sync_removed_covers(p, rows, changed_project or suppress_delete) then rows = snapshot(p) end
  if moving and gesture then freeze_groups(rows, gesture)
  else
    gesture = nil
    for _, row in ipairs(rows.dirty_rows or rows) do
      row.groups = groups_from(row.ranges)
    end
  end
  local plan = make_plan(rows)
  if not plan then
    rows = snapshot(p)
    if moving and gesture then freeze_groups(rows, gesture)
    else for _, row in ipairs(rows) do row.groups = groups_from(row.ranges) end end
    plan = assert(make_plan(rows), 'Cover ownership changed during the update.')
  end
  rows.rebuild_watch = #plan.create + #plan.remove > 0
  if #plan.create + #plan.move + #plan.remove + #plan.source_id + #plan.track_id + #plan.display > 0 then apply_plan(p, plan) end
  remember(rows)
  rows.item_count = R.CountMediaItems(p)
  next_audit, audit_item, audit_track = R.time_precise() + .1, 1, 1
  if gesture then
    for _, driver in ipairs(gesture.drivers) do
      if R.ValidatePtr2(p, driver.state.item, 'MediaItem*') then
        driver.last_position = R.GetMediaItemInfo_Value(driver.state.item, 'D_POSITION')
      end
    end
  end
  -- Acknowledge our own writes immediately so they cannot cause another update loop.
  applied_revision = R.GetProjectStateChangeCount(p)
  history_index = current_history
end

local function run_update()
  if stopped then return false end
  local ok, err = xpcall(update, debug.traceback)
  if arrange_pending then
    arrange_pending = false
    local drawn, why = pcall(R.UpdateArrange)
    if not drawn then
      if ok then ok, err = false, why else err = tostring(err) .. '\n' .. tostring(why) end
    end
  end
  if not ok then
    cleanup()
    R.ShowMessageBox(tostring(err), TITLE, 0)
  end
  return ok
end

local function loop()
  if run_update() then R.defer(loop) end
end

R.atexit(cleanup)
-- Repair a temporary assignment left by a prior interrupted script instance.
restore_input()
if R.set_action_options then R.set_action_options(5) end
if has_action then
  R.SetToggleCommandState(section, command, 1)
  R.RefreshToolbar2(section, command)
end
-- Defer suppresses implicit undo, including startup errors. Scan immediately
-- so the first mouse gesture already has complete cover/child bindings.
R.defer(loop)
run_update()
