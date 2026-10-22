-- @description ACTION - Auto-hide video window under mouse (toggle)
-- @version 1.1.1
-- @author Balrulu
-- @provides
--   . > ../
-- @changelog
--   BLT SERIES ACTIONS
-- @about
--   BLT SERIES Beta TEST UPLOAD

-- BEGIN BLT TOGGLE RESTORE EMBEDDED 1.0.0
do
local BLTToggleRestoreSource = [====[
-- BLT toggle persistence 1.0.0. Embedded in each supported action.
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

local function command_for(api, id)
  local saved = api.GetExtState(SECTION, id .. '_worker_command')
  local command = saved ~= '' and api.NamedCommandLookup(saved) or 0
  if not command or command <= 0 then
    command = api.AddRemoveReaScript(true, 0, worker_path(api, id), true)
    assert(command and command > 0, 'Cannot register the BLT background worker.')
    save(api, id .. '_worker_command', named(api, command), true)
  end
  return command
end

local function log(api, message)
  if api.ShowConsoleMsg then pcall(api.ShowConsoleMsg, 'BLT toggle restore: ' .. tostring(message) .. '\n') end
end

function M.install(api, id, module_source)
  assert(valid_id(id) and type(module_source) == 'string', 'Invalid BLT restore installation.')
  api.RecursiveCreateDirectory(root(api), 0)
  write(root(api) .. '/BLT_Toggle_Restore.lua', module_source)
  local worker = 'local R=reaper\nlocal fn,err=loadfile(R.GetResourcePath().."/Scripts/BLT ReaScripts/BLT_Toggle_Restore.lua")\n'
    .. 'if not fn then if R.ShowConsoleMsg then R.ShowConsoleMsg(tostring(err).."\\n")end;return end\n'
    .. 'fn().worker(R,' .. string.format('%q', id) .. ')\n'
  write(worker_path(api, id), worker)
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
  if api.set_action_options then api.set_action_options(1) end
  local ok, err = xpcall(function()
    if api.GetExtState(SECTION, id .. '_running') == '1' then
      -- Turning OFF must not depend on rewriting/reading startup files.
      save(api, id .. '_enabled', '0', true)
      local worker = api.NamedCommandLookup(api.GetExtState(SECTION, id .. '_worker_command'))
      if worker and worker > 0 then api.Main_OnCommand(worker, 0) end
      api.SetToggleCommandState(0, command, 0);api.RefreshToolbar2(0, command)
      return
    end
    M.install(api, id, module_source)
    save(api, id .. '_path', path, true)
    save(api, id .. '_command', named(api, command), true)
    local worker = command_for(api, id)
    save(api, id .. '_enabled', '1', true)
    api.Main_OnCommand(worker, 0)
    local on = api.GetExtState(SECTION, id .. '_running') == '1'
    api.SetToggleCommandState(0, command, on and 1 or 0);api.RefreshToolbar2(0, command)
  end, debug.traceback)
  if not ok then log(api, err) end
  return false
end

function M.worker(api, id)
  assert(valid_id(id), 'Unknown BLT toggle worker.')
  if api.GetExtState(SECTION, id .. '_enabled') ~= '1' or api.GetExtState(SECTION, id .. '_running') == '1' then return end
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
      if api.GetExtState(SECTION, id .. '_enabled') == '1' and api.GetExtState(SECTION, id .. '_running') ~= '1' then
        local ok, err = pcall(function() api.Main_OnCommand(command_for(api, id), 0) end)
        if not ok then log(api, err) end
      end
    end
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
