-- @description ACTION - Auto select tracks of selected items (toggle)
-- @version 1.0.2
-- @author Balrulu
-- @provides
--   . > ../
-- @changelog
--   BLT SERIES ACTIONS
-- @about
--   BLT SERIES Beta TEST UPLOAD

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
  local s = R.GetProjectStateChangeCount(p)
  local f = R.GetSelectedMediaItem(p, 0)
  local l = n > 1 and R.GetSelectedMediaItem(p, n - 1) or f
  if not changed and s == state and f == first and l == last and now < next_audit then return end
  for i = 1, n do
    local item = i == 1 and f or (i == n and l or R.GetSelectedMediaItem(p, i - 1))
    if not item then count = -1; return end
    if not selected[item] then changed = true end
    items[i] = item
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
