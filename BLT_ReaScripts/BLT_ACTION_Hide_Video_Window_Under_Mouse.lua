-- @description ACTION - Auto-hide video window under mouse (toggle)
-- @version 1.0.3
-- @author Balrulu
-- @provides
--   . > ../
-- @changelog
--   BLT SERIES ACTIONS
-- @about
--   BLT SERIES Beta TEST UPLOAD

local R = reaper
local required = {"JS_Window_GetParent", "JS_Window_GetRelated", "JS_Window_FromPoint", "JS_Window_IsChild",
  "JS_Localize", "JS_Window_GetClientRect", "JS_Window_Show",
  "JS_Window_IsVisible", "JS_Window_IsWindow", "JS_Window_GetTitle",
  "JS_Window_GetLong"}
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
    if not hwnd or not R.JS_Window_IsWindow(hwnd) then return end
    count = count + 1
    parent_chain[count] = hwnd
    hwnd = R.JS_Window_GetParent(hwnd) or R.JS_Window_GetRelated(hwnd, "OWNER")
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

local function restore()
  if not hidden then return true end
  if not valid(video) then
    video = nil
    release_hidden()
    return true
  end
  if R.JS_Window_IsVisible(video) then release_hidden(); return true end
  if not main_can_show() then return false end
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
      local ok, restored = pcall(restore)
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
  last_x, last_y = x, y
  if refresh then next_refresh = now + 0.5 end
  local hovered = R.JS_Window_FromPoint(x, y)
  if hovered ~= last_hover or refresh then
    video, last_hover = video_at(hovered), hovered
  end
  if not video or not R.JS_Window_IsVisible(video) then return end
  local ok, left, top, right, bottom = R.JS_Window_GetClientRect(video)
  if not ok then return end
  if left > right then left, right = right, left end
  if top > bottom then top, bottom = bottom, top end
  if left >= right or top >= bottom
      or x < left or x >= right or y < top or y >= bottom then return end
  if not valid(video) then video = nil; return end
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
