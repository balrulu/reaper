-- @description ACTION - Auto-hide video window under mouse (toggle)
-- @version 1.1.8
-- @author Balrulu
-- @provides
--   . > ../
-- @changelog
--   BLT SERIES ACTIONS
-- @about
--   BLT SERIES Beta TEST UPLOAD

-- BEGIN BLT TOGGLE RESTORE EMBEDDED 1.4.1
do
local BLTToggleRestoreSource = [====[
-- BLT toggle persistence 1.4.1. Embedded in each supported action.
-- The public action is a dispatcher; its private worker owns the defer loop.
-- Normal worker shutdown preserves the persisted ON choice.
-- BEGIN BLT PORTABLE PATHS 1.0.0
local BLTPaths=(function()
-- BLT portable paths 1.0.0. Embedded in standalone scripts.
local M = {}
local function windows(api) return (api.GetOS() or ''):match('Win') ~= nil end
local function slash(path)
  path = tostring(path or ''):gsub('\\', '/')
  local prefix = path:sub(1, 2) == '//' and '//' or ''
  return prefix .. path:sub(#prefix + 1):gsub('/+', '/'):gsub('/+$', '')
end
function M.absolute(path)
  if type(path) ~= 'string' then return false end
  local value = path:gsub('\\', '/')
  return value:sub(1, 1) == '/' or value:match('^%a:/') ~= nil
end
function M.native(api, path, relative)
  if type(path) ~= 'string' or path:find('[%z\r\n]') then return false end
  if path == '' then return relative == true end
  if windows(api) then
    if path:match('^%a:[/\\]') or path:match('^[/\\][/\\][^/\\]+[/\\][^/\\]+') then return true end
    return relative == true and not path:match('^[/\\]') and not path:match('^%a:')
  end
  if path:match('^%a:') or path:find('\\', 1, true) then return false end
  return path:sub(1, 1) == '/' or relative == true
end
local function child(value)
  if value == '' or value:sub(1, 1) == '/' or value:find('\\', 1, true) or value:find('[%z\r\n:]') then return end
  for part in value:gmatch('[^/]+') do if part == '.' or part == '..' then return end end
  return value
end
function M.join(base, relative)
  local value = child(relative)
  if value then return slash(base) .. '/' .. value end
end
function M.encode(api, path)
  if type(path) ~= 'string' or path == '' or path:sub(1, 10) == '@resource/' then return path end
  local root, value = slash(api.GetResourcePath()), slash(path)
  local a, b = root, value
  if windows(api) then a, b = a:lower(), b:lower() end
  if b:sub(1, #a + 1) == a .. '/' then
    local relative = child(value:sub(#root + 2))
    if relative then return '@resource/' .. relative end
  end
  return path
end
function M.decode(api, path)
  if type(path) ~= 'string' then return end
  if path:sub(1, 10) ~= '@resource/' then return path end
  local relative = child(path:sub(11))
  if relative then return slash(api.GetResourcePath()) .. '/' .. relative end
end
function M.exists(api, path)
  if not path or path == '' or not M.native(api, path, false) then return false end
  if api.file_exists then return api.file_exists(path) == true end
  local file = io.open(path, 'rb');if not file then return false end
  file:close();return true
end
function M.readable(api, path)
  if not path or path == '' or not M.native(api, path, false) then return false end
  local file = io.open(path, 'rb');if not file then return false end
  file:close();return true
end
function M.executable(api, path)
  path = M.decode(api, path)
  if type(path) ~= 'string' or path == '' or path:find('[%z\r\n]') then return end
  if not windows(api) and path:lower():match('%.exe$') then return end
  if M.absolute(path) then return M.exists(api, path) and path or nil end
  if path:match('^[%w_.%-]+$') then return path end
end
function M.directory(api, path)
  if type(path) ~= 'string' or path == '' or type(api.JS_File_Stat) ~= 'function' then return false end
  local result = table.pack(pcall(api.JS_File_Stat, path))
  return result[1] and result[2] == 0 and type(result[10]) == 'number' and (result[10] & 0xF000) == 0x4000
end
function M.file(api, path, folders)
  local value = M.decode(api, path)
  if M.exists(api, value) then return value end
  if type(path) ~= 'string' or path:sub(1, 10) == '@resource/' then return end
  local normalized = slash(path)
  for _, folder in ipairs(folders or {}) do
    local prefix = '/' .. folder .. '/'
    local at = normalized:lower():find(prefix:lower(), 1, true)
    local relative = at and child(normalized:sub(at + #prefix))
    if relative then
      local candidate = slash(api.GetResourcePath()) .. '/' .. folder .. '/' .. relative
      if M.exists(api, candidate) then return candidate end
    end
  end
end
local environments = {}
function M.environment(api)
  local root = slash(api.GetResourcePath())
  if environments[root] ~= nil then return environments[root] or nil end
  local path = root .. '/UserPlugins/.blt-environment-id'
  local function read()
    local file = io.open(path, 'rb');if not file then return end
    local value = file:read(129);file:close()
    if value and #value >= 16 and #value <= 128 and value:match('^[%x{}%-]+$') then return value end
  end
  local value = read()
  if not value and api.genGuid then
    pcall(function()
      if api.RecursiveCreateDirectory then api.RecursiveCreateDirectory(root .. '/UserPlugins', 0) end
      local token = api.genGuid();assert(type(token) == 'string' and token:match('^[%x{}%-]+$'))
      local file = assert(io.open(path, 'wb'));local ok = file:write(token);local closed = file:close()
      if ok and closed then value = read() end
    end)
  end
  environments[root] = value or false
  return value
end
local confirmed = {}
function M.confirm(path) confirmed[path] = true end
function M.output(api, path, owner)
  if not M.native(api, path, true) then return false end
  if path == '' or not M.absolute(path) or confirmed[path] then return true end
  if owner and owner ~= '' then return owner == M.environment(api) end
  return M.directory(api, path)
end
function M.registry(api, identify)
  local file = io.open(api.GetResourcePath() .. '/reaper-kb.ini', 'rb')
  if not file then return {} end
  local raw = file:read('*a');file:close()
  local result = {data = raw}
  for line in raw:gmatch('[^\r\n]+') do
    local command, path = line:match('^SCR%s+%d+%s+0%s+(%S+)%s+.*%s+"([^"]+)"%s*$')
    if not command then command, path = line:match('^SCR%s+%d+%s+0%s+(%S+)%s+.*%s+(%S+)%s*$') end
    local name = path and slash(path):match('([^/]+)$')
    local id = name and identify(name:lower():gsub(' ', '_'))
    if id then
      if not M.absolute(path) then path = api.GetResourcePath() .. '/Scripts/' .. path end
      result[id] = result[id] or {}
      result[id][#result[id] + 1] = {path = path, command = '_' .. command:gsub('^_', '')}
    end
  end
  return result
end
function M.action(api, id, stored, command, entries, identify, verify)
  local choices, seen = {}, {}
  for _, row in ipairs(entries[id] or {}) do
    if M.readable(api, row.path) and (not verify or verify(id, row.path)) then
      if row.command == command then return row.path, row.command end
      local key = slash(row.path);if windows(api) then key = key:lower() end
      if not seen[key] then choices[#choices + 1] = row;seen[key] = true end
    end
  end
  if #choices == 1 then return choices[1].path, choices[1].command end
  if #choices > 1 then return nil, 'Multiple registered copies; run the intended action once.' end
  local path = M.decode(api, stored)
  local name = path and slash(path):match('([^/]+)$')
  if name and identify(name:lower():gsub(' ', '_')) == id then
    path = M.file(api, stored, {'Scripts'})
    if path and M.readable(api, path) and (not verify or verify(id, path)) then return path, '' end
  end
  return nil, 'Script not found; run the installed action once to enable restoration again.'
end
return M
end)()
-- END BLT PORTABLE PATHS
local M = {}
local SECTION = 'BLT_TOGGLE_RESTORE'
local IDS = {'folder_covers', 'selected_tracks', 'video_hover', 'cover_name_markers'}
local FILE_IDS = {
  ['blt_action_add_folder_covers(auto).lua'] = 'folder_covers',
  ['blt_action_auto_select_tracks_of_selected_items.lua'] = 'selected_tracks',
  ['blt_action_hide_video_window_under_mouse.lua'] = 'video_hover',
  ['blt_action_add_folder_cover_name_markers(auto).lua'] = 'cover_name_markers'
}
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

local function readable(path,api)
  return BLTPaths.readable(api, path)
end
local function identify(name) return FILE_IDS[name] end
local function registry(api) return BLTPaths.registry(api, identify) end
local function resolve(api, id, entries)
  return BLTPaths.action(api, id, api.GetExtState(SECTION, id .. '_path'), api.GetExtState(SECTION, id .. '_command'), entries, identify)
end

local function clear_target(api, id)
  save(api, id .. '_enabled', '0', true)
  for _, suffix in ipairs({'_path', '_command', '_worker_command'}) do
    if api.GetExtState(SECTION, id .. suffix) ~= '' then api.DeleteExtState(SECTION, id .. suffix, true) end
  end
  save(api, id .. '_start_pending', '', false)
end

function M.reset(api)
  for _, id in ipairs(IDS) do
    local command = api.NamedCommandLookup(api.GetExtState(SECTION, id .. '_command'))
    if command and command > 0 then
      api.SetToggleCommandState(0, command, 0);api.RefreshToolbar2(0, command)
    end
    clear_target(api, id)
  end
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

local function launch(api, id, batch, last)
  local command = command_for(api, id)
  if batch then
    batch.dirty = true;batch.path = worker_path(api, id)
    batch.pending = batch.pending or {};batch.pending[batch.path] = true
  end
  local ok, err = pcall(api.Main_OnCommand, command, 0)
  -- Unregistering a running ReaScript keeps its defer/atexit callbacks alive.
  -- The temporary command must never remain in the user's action list.
  local removed, why = pcall(api.AddRemoveReaScript, false, 0, worker_path(api, id), not batch or last)
  assert(removed and type(why) == 'number' and why > 0, why or 'Cannot unregister the BLT background worker.')
  if batch then
    batch.pending[batch.path] = nil
    if last then batch.dirty = next(batch.pending) ~= nil end
  end
  assert(ok, err)
  if api.GetExtState(SECTION, id .. '_running') == '1' then return true end
  if api.GetExtState(SECTION, id .. '_enabled') ~= '1' then return false end
  error('The BLT background worker did not start: ' .. id, 0)
end

local function remove_legacy_workers(api, registry_data)
  if api.GetExtState(SECTION, 'worker_cleanup') == '1.2.0' then return end
  local ok, data = true, registry_data
  if not data then ok, data = pcall(read, api.GetResourcePath() .. '/reaper-kb.ini') end
  data = ok and data and data:gsub('\\', '/') or ''
  local windows = api.GetOS and (api.GetOS() or ''):match('Win')
  if windows then data = data:lower() end
  local pending = {}
  for _, id in ipairs(IDS) do
    local relative = 'BLT ReaScripts/BLT_Toggle_Worker_' .. id .. '.lua'
    local absolute = worker_path(api, id):gsub('\\', '/')
    if windows then relative, absolute = relative:lower(), absolute:lower() end
    if data:find('"' .. relative .. '"', 1, true) or data:find('"' .. absolute .. '"', 1, true)
        or api.GetExtState(SECTION, id .. '_worker_command') ~= '' then pending[#pending + 1] = id end
    if api.GetExtState(SECTION, id .. '_worker_command') ~= '' then
      api.DeleteExtState(SECTION, id .. '_worker_command', true)
    end
  end
  for i, id in ipairs(pending) do api.AddRemoveReaScript(false, 0, worker_path(api, id), i == #pending) end
  save(api, 'worker_cleanup', '1.2.0', false)
end

local function flush_registry(api, batch)
  if not batch.dirty then return end
  if batch.pending and next(batch.pending) then
    local paths = {};for path in pairs(batch.pending) do paths[#paths + 1] = path end
    for i, path in ipairs(paths) do
      assert(api.AddRemoveReaScript(false, 0, path, i == #paths) > 0, 'Cannot remove a pending BLT worker.')
      batch.pending[path] = nil
    end
    batch.dirty = false;return
  end
  local command = api.AddRemoveReaScript(true, 0, batch.path, false)
  assert(command and command > 0, 'Cannot finish the BLT worker registry update.')
  assert(api.AddRemoveReaScript(false, 0, batch.path, true) > 0, 'Cannot remove the BLT temporary worker.')
  batch.dirty = false
end

local function log(api, message)
  if api.ShowConsoleMsg then pcall(api.ShowConsoleMsg, 'BLT toggle restore: ' .. tostring(message) .. '\n') end
end

function M.install(api, id, module_source)
  assert(valid_id(id) and type(module_source) == 'string', 'Invalid BLT restore installation.')
  api.RecursiveCreateDirectory(root(api), 0)
  write(root(api) .. '/BLT_Toggle_Restore.lua', module_source)
  save(api, 'module_version', '1.4.1', false)
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
  if api.BLT_ToggleRestoreWorker == id then
    if api.GetExtState(SECTION, 'module_version') ~= '1.4.1' then
      write(root(api) .. '/BLT_Toggle_Restore.lua', module_source)
      save(api, 'module_version', '1.4.1', false)
    end
    return true
  end
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
    save(api, id .. '_path', BLTPaths.encode(api, path), true)
    save(api, id .. '_command', named(api, command), true)
    save(api, id .. '_enabled', '1', true)
    display(launch(api, id))
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
  local path = BLTPaths.decode(api, api.GetExtState(SECTION, id .. '_path'))
  if not readable(path,api) then
    clear_target(api, id)
    log(api, id .. ': script unavailable; restoration disabled. Run the installed action once to restore it.')
    if api.set_action_options then api.set_action_options(9) end
    return
  end
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
    -- Closing REAPER must not turn off the next startup's restoration.
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
  if not fn then finish();clear_target(api, id);log(api, err);return end
  local ok, reason = xpcall(fn, debug.traceback)
  if not ok then finish();log(api, reason) end
end

function M.restore(api)
  if api.GetExtState(SECTION, 'startup_done') == '1' then return end
  save(api, 'startup_done', '1', false)
  save(api, 'module_version', '1.4.1', false)
  api.defer(function()
    local pending, batch = {}, {}
    for _, id in ipairs(IDS) do
      if api.GetExtState(SECTION, id .. '_enabled') == '1' then
        pending[#pending + 1] = id;save(api, id .. '_start_pending', '1', false)
      end
    end
    local entries
    if #pending > 0 then
      local ok, value = pcall(registry, api)
      if ok then entries = value else log(api, value) end
    end
    remove_legacy_workers(api, entries and entries.data)
    local index = 1
    local function step()
      local id = pending[index];index = index + 1
      if not id then
        local ok, err = pcall(flush_registry, api, batch)
        if not ok then log(api, err) end
        return
      end
      save(api, id .. '_start_pending', '', false)
      if api.GetExtState(SECTION, id .. '_enabled') == '1' then
        local ok, err = pcall(function()
          if api.GetExtState(SECTION, id .. '_running') == '1' then return end
          if not entries then return end
          local path, command = resolve(api, id, entries)
          if not path then
            clear_target(api, id);log(api, id .. ': ' .. command .. ' Restoration disabled.');return
          end
          save(api, id .. '_path', BLTPaths.encode(api, path), true)
          save(api, id .. '_command', command, true)
          launch(api, id, batch, index > #pending)
        end)
        if not ok then log(api, err) end
      end
      api.defer(step)
    end
    step()
  end)
end

return M

]====]
local module = assert(load(BLTToggleRestoreSource, "@BLT_Toggle_Restore.lua", "t", _ENV))()
if not module.enter(reaper, 'video_hover', BLTToggleRestoreSource) then return end
end
-- END BLT TOGGLE RESTORE EMBEDDED
local R = reaper
local required = {"JS_Window_GetParent", "JS_Window_GetRelated", "JS_Window_FromPoint", "JS_Window_IsChild",
  "JS_Localize", "JS_Window_GetClientRect", "JS_Window_Show",
  "JS_Window_IsVisible", "JS_Window_IsWindow", "JS_Window_GetTitle",
  "JS_Window_GetLong", "JS_Mouse_GetState"}
for _, name in ipairs(required) do
  if not R[name] then R.defer(function() end); return end
end

local _, _, section, command = R.get_action_context()
local has_action = section and command and section >= 0 and command > 0
local main = R.GetMainHwnd()
if not main then R.defer(function() end); return end
local title = R.JS_Localize("Video Window", "video2_DLG_102")
if not title or title == "" then title = "Video Window" end
local video, hidden, bounds
local next_check = 0
local last_x, last_y, next_refresh = nil, nil, 0
local restoring, next_restore, next_hidden_check = false, 0, 0
local last_hover, stopped
local parent_chain = {}

local function main_can_show()
  if not R.JS_Window_IsVisible(main) then return false end
  local style = R.JS_Window_GetLong(main, "STYLE")
  return type(style) == "number" and (math.floor(style) & 0x20000000) == 0
end

local function video_at(hwnd)
  local hovered, count = hwnd, 0
  for _ = 1, 32 do
    if hwnd == main then break end
    if not hwnd or hwnd == 0 or not R.JS_Window_IsWindow(hwnd) then return end
    count = count + 1
    parent_chain[count] = hwnd
    local parent = R.JS_Window_GetParent(hwnd)
    if parent == 0 or parent == hwnd then parent = nil end
    hwnd = parent or R.JS_Window_GetRelated(hwnd, "OWNER")
  end
  if hwnd ~= main then return end
  for i = count, 1, -1 do
    local candidate = parent_chain[i]
    local name = R.JS_Window_GetTitle(candidate)
    if (name == title or name == "Video Window")
        and (hovered == candidate or R.JS_Window_IsChild(candidate, hovered)) then
      return candidate
    end
  end
end
local function valid(hwnd)
  return hwnd and video_at(hwnd) == hwnd
end

local function release_hidden()
  hidden, bounds, restoring = false, nil, false
  last_x, last_y, next_refresh = nil, nil, 0
  last_hover = nil
end

local function restore(force)
  if not hidden then return true end
  if not valid(video) then
    video = nil
    release_hidden()
    return true
  end
  if R.JS_Window_IsVisible(video) then release_hidden(); return true end
  if not force and not main_can_show() then return false end
  R.JS_Window_Show(video, "SHOWNA")
  if not R.JS_Window_IsVisible(video) then return false end
  release_hidden()
  return true
end

local function cleanup()
  if stopped then return end
  stopped = true
  if hidden then
    for _ = 1, 3 do
      local ok, restored = pcall(restore, true)
      if ok and restored then break end
    end
  end
  if R.set_action_options then pcall(R.set_action_options, 9) end
  if has_action then
    pcall(R.SetToggleCommandState, section, command, 0)
    pcall(R.RefreshToolbar2, section, command)
  end
  if hidden and R.ShowConsoleMsg then
    local checked, can_show = pcall(main_can_show)
    if checked and can_show then
      pcall(R.ShowConsoleMsg, "BLT Video auto-hide: could not restore the video window. Use Video: Show/hide video window to reopen it.\n")
    end
  end
end

R.atexit(cleanup)
if R.set_action_options then R.set_action_options(5) end
if has_action then
  R.SetToggleCommandState(section, command, 1)
  R.RefreshToolbar2(section, command)
end

local function update(now)
  if hidden then
    if restoring then
      if now >= next_restore then
        next_restore = now + 0.5
        pcall(restore)
      end
      return
    end
    if now >= next_hidden_check then
      next_hidden_check = now + 0.5
      if not valid(video) then
        video = nil
        release_hidden()
        return
      end
    end
    local x, y = R.GetMousePosition()
    if x < bounds[1] or x >= bounds[3]
        or y < bounds[2] or y >= bounds[4] then
      restoring = true
      next_restore = now + 0.5
      pcall(restore)
    end
    return
  end
  local x, y = R.GetMousePosition()
  local refresh = now >= next_refresh
  if x == last_x and y == last_y and not refresh then return end
  -- A resize drag can move the pointer into the video client area.
  if (R.JS_Mouse_GetState(1) & 1) ~= 0 then
    last_x, last_y = nil, nil
    return
  end
  last_x, last_y = x, y
  if refresh then next_refresh = now + 0.5 end
  local hovered = R.JS_Window_FromPoint(x, y)
  local checked = hovered ~= last_hover or refresh
  if checked then video, last_hover = video_at(hovered), hovered end
  if video and not R.JS_Window_IsWindow(video) then video, last_hover = nil, nil; return end
  if not video or not R.JS_Window_IsVisible(video) then return end
  local ok, left, top, right, bottom = R.JS_Window_GetClientRect(video)
  if not ok then return end
  if left > right then left, right = right, left end
  if top > bottom then top, bottom = bottom, top end
  if left >= right or top >= bottom
      or x < left or x >= right or y < top or y >= bottom then return end
  if not checked and not valid(video) then video = nil; return end
  if not main_can_show() then return end
  bounds = {left, top, right, bottom}
  hidden = true
  next_hidden_check = now + 0.5
  R.JS_Window_Show(video, "HIDE")
  if R.JS_Window_IsVisible(video) then error("Could not hide the video window.") end
end

local function loop()
  if stopped then return end
  local now = R.time_precise()
  if now >= next_check then
    next_check = now + 0.05
    local ok, err = pcall(update, now)
    if not ok then
      cleanup()
      if R.ShowConsoleMsg then pcall(R.ShowConsoleMsg, "BLT Video auto-hide stopped: " .. tostring(err) .. "\n") end
      return
    end
  end
  R.defer(loop)
end
loop()
