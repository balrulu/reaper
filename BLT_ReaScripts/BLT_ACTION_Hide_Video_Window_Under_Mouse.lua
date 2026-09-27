-- @description ACTION - Auto-hide video window under mouse (toggle)
-- @version 1.0.2
-- @author Balrulu
-- @provides
--   . > ../
-- @changelog
--   BLT SERIES ACTIONS
-- @about
--   BLT SERIES Beta TEST UPLOAD

local R = reaper
local required = {"JS_Window_Find", "JS_Window_FromPoint", "JS_Window_IsChild",
  "JS_Localize", "JS_Window_GetClientRect", "JS_Window_Show",
  "JS_Window_IsVisible", "JS_Window_IsWindow", "JS_Window_GetTitle",
  "JS_Window_GetLong"}
for _, name in ipairs(required) do
  if not R[name] then R.defer(function() end); return end
end

if R.set_action_options then R.set_action_options(1) end
local _, _, section, command = R.get_action_context()
local title = R.JS_Localize("Video Window", "video2_DLG_102")
local video, hidden, bounds
local next_check, next_find = 0, 0
local last_x, last_y, next_refresh = nil, nil, 0
local restoring, next_restore, next_hidden_check = false, 0, 0

local function main_can_show()
  local main = R.GetMainHwnd()
  if not main or not R.JS_Window_IsVisible(main) then return false end
  -- IsVisible alone remains true for a minimized Windows window.
  local style = R.JS_Window_GetLong(main, "STYLE")
  return type(style) == "number" and (math.floor(style) & 0x20000000) == 0
end

local function valid(hwnd)
  if not hwnd or not R.JS_Window_IsWindow(hwnd) then return false end
  local name = R.JS_Window_GetTitle(hwnd)
  return name == title or name == "Video Window"
end

local function toggle(state)
  if R.set_action_options then R.set_action_options(state == 1 and 5 or 9) end
  if section and command and section >= 0 and command > 0 then
    R.SetToggleCommandState(section, command, state)
    R.RefreshToolbar2(section, command)
  end
end

local function release_hidden()
  hidden, bounds, restoring = false, nil, false
  last_x, last_y, next_refresh = nil, nil, 0
end

local function restore(fallback)
  if not hidden then return true end
  if not valid(video) then
    -- A destroyed/replaced window must never be shown through its old handle.
    video = nil
    release_hidden()
    return true
  end
  -- Keep ownership and retry later; never bring up the video over a minimized host.
  if not main_can_show() then return false end
  R.JS_Window_Show(video, fallback and "SHOW" or "SHOWNA")
  if not R.JS_Window_IsVisible(video) then return false end
  release_hidden()
  return true
end

local function cleanup()
  -- Each attempt is isolated so an API error cannot skip all later cleanup.
  for attempt = 1, 3 do
    local ok, restored = pcall(restore, attempt == 3)
    if ok and restored then break end
  end
  if R.set_action_options then pcall(R.set_action_options, 9) end
  if section and command and section >= 0 and command > 0 then
    pcall(R.SetToggleCommandState, section, command, 0)
    pcall(R.RefreshToolbar2, section, command)
  end
  local checked, can_show = pcall(main_can_show)
  if hidden and checked and can_show and R.ShowConsoleMsg then
    pcall(R.ShowConsoleMsg, "BLT Video auto-hide: could not restore the video window. Use Video: Show/hide video window to reopen it.\n")
  end
end

R.atexit(cleanup)
toggle(1)

local function update(now)
  -- Fast mouse checks; only revalidate the hidden handle twice per second.
  if hidden then
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
    end
    -- Keep retrying even if the pointer re-enters before restoration succeeds.
    if restoring and now >= next_restore then
      next_restore = now + 0.5
      pcall(restore, false)
    end
    return
  end
  if not video and now < next_find then return end

  local x, y = R.GetMousePosition()
  local refresh = now >= next_refresh
  if x == last_x and y == last_y and not refresh then return end
  last_x, last_y = x, y
  -- Recheck even with a stationary mouse, to detect moved/reopened windows.
  if refresh then next_refresh = now + 0.5 end

  if not video or not R.JS_Window_IsWindow(video)
      or (refresh and not valid(video)) then
    video, hidden, bounds = nil, false, nil
    if now < next_find then return end
    next_find = now + 0.5
    video = R.JS_Window_Find(title, true)
    if not video and title ~= "Video Window" then
      video = R.JS_Window_Find("Video Window", true)
    end
    if not valid(video) then video = nil; return end
  end

  if not R.JS_Window_IsVisible(video) then return end
  local hovered = R.JS_Window_FromPoint(x, y)
  if not hovered or (hovered ~= video and not R.JS_Window_IsChild(video, hovered)) then
    return
  end
  local ok, left, top, right, bottom = R.JS_Window_GetClientRect(video)
  if not ok then return end
  -- Normalize vertical bounds for macOS screen coordinates as well.
  bounds = {math.min(left, right), math.min(top, bottom),
    math.max(left, right), math.max(top, bottom)}
  if bounds[1] == bounds[3] or bounds[2] == bounds[4] then bounds = nil; return end
  if x < bounds[1] or x >= bounds[3] or y < bounds[2] or y >= bounds[4] then
    bounds = nil
    return
  end
  if not valid(video) then bounds = nil; video = nil; return end
  if not main_can_show() then bounds = nil; return end
  hidden = true -- Register restoration before changing visibility.
  next_restore, next_hidden_check = 0, now + 0.5
  R.JS_Window_Show(video, "HIDE")
end

local function loop()
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
