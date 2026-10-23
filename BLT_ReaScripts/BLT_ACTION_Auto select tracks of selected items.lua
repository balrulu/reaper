-- @description ACTION - Auto select tracks of selected items (toggle)
-- @version 1.1.2
-- @author Balrulu
-- @provides
--   . > ../
-- @changelog
--   BLT SERIES ACTIONS
-- @about
--   BLT SERIES Beta TEST UPLOAD

-- BEGIN BLT TOGGLE RESTORE EMBEDDED 1.0.1
do
local BLTToggleRestoreSource = [====[
-- BLT toggle persistence 1.0.1. Embedded in each supported action.
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

local function cached_worker(api, id)
  local saved = api.GetExtState(SECTION, id .. '_worker_command')
  local command = saved ~= '' and api.NamedCommandLookup(saved) or 0
  command = command or 0
  return command, command > 0 and api.GetToggleCommandStateEx(0, command) or -1
end

local function worker_source(id)
  return 'local R=reaper\nlocal fn,err=loadfile(R.GetResourcePath().."/Scripts/BLT ReaScripts/BLT_Toggle_Restore.lua")\n'
    .. 'if not fn then if R.ShowConsoleMsg then R.ShowConsoleMsg(tostring(err).."\\n")end;return end\n'
    .. 'fn().worker(R,' .. string.format('%q', id) .. ')\n'
end

local function command_for(api, id)
  local path = worker_path(api, id)
  write(path, worker_source(id))
  local command = api.AddRemoveReaScript(true, 0, path, true)
  assert(command and command > 0, 'Cannot register the BLT background worker.')
  save(api, id .. '_worker_command', named(api, command), true)
  return command
end

local function log(api, message)
  if api.ShowConsoleMsg then pcall(api.ShowConsoleMsg, 'BLT toggle restore: ' .. tostring(message) .. '\n') end
end

function M.install(api, id, module_source)
  assert(valid_id(id) and type(module_source) == 'string', 'Invalid BLT restore installation.')
  api.RecursiveCreateDirectory(root(api), 0)
  write(root(api) .. '/BLT_Toggle_Restore.lua', module_source)
  write(worker_path(api, id), worker_source(id))
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
    local worker = command_for(api, id)
    save(api, id .. '_enabled', '1', true)
    api.Main_OnCommand(worker, 0)
    local on = api.GetExtState(SECTION, id .. '_running') == '1' and api.GetToggleCommandStateEx(0, worker) == 1
    display(on)
    assert(on, 'The BLT background worker did not start: ' .. id)
  end
  attempt(function()
    local marked = api.GetExtState(SECTION, id .. '_running') == '1'
    local worker, state = cached_worker(api, id)
    if marked and (state == 1 or worker <= 0) then
      -- Turning OFF must not depend on rewriting/reading startup files.
      save(api, id .. '_enabled', '0', true)
      if worker > 0 then api.Main_OnCommand(worker, 0)
      end
      if api.GetExtState(SECTION, id .. '_running') == '1' then api.defer(function() attempt(function()
        if api.GetExtState(SECTION, id .. '_enabled') == '0' then
          save(api, id .. '_running', '', false)
          if worker > 0 then api.SetToggleCommandState(0, worker, 0);api.RefreshToolbar2(0, worker) end
        end
      end) end) end
      display(false)
      return
    end
    if marked or state == 1 then
      save(api, id .. '_enabled', '0', true)
      if state == 1 then api.Main_OnCommand(worker, 0) end
      display(false)
      -- Let a stopped or unregistered worker finish before creating its replacement.
      api.defer(function() api.defer(function() attempt(function()
        save(api, id .. '_running', '', false);start()
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
    for _, id in ipairs(IDS) do
      if api.GetExtState(SECTION, id .. '_enabled') == '1' then
        local ok, err = pcall(function()
          local worker, state = cached_worker(api, id)
          if state == 1 or worker <= 0 and api.GetExtState(SECTION, id .. '_running') == '1' then return end
          save(api, id .. '_running', '', false)
          api.Main_OnCommand(command_for(api, id), 0)
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
