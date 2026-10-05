-- @description ACTION - Open selected item in external editor (original or glued range)
-- @version 1.0.0
-- @author Balrulu
-- @provides
--   . > ../
-- @changelog
--   BLT SERIES ACTIONS
-- @about
--   BLT SERIES Beta TEST UPLOAD

local R = reaper
local PLATFORM = R.GetOS()

local function is_japanese()
  local command
  if PLATFORM:match("^Win") then
    command = [[powershell.exe -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -Command "[Console]::Write((Get-UICulture).Name)"]]
  elseif PLATFORM:match("^OSX") or PLATFORM:match("^macOS") then
    command = "/usr/bin/defaults read NSGlobalDomain AppleLanguages"
  else
    return false
  end
  local ok, result = pcall(R.ExecProcess, command, 5000)
  if not ok or type(result) ~= "string" then return false end
  local status, output = result:match("^(-?%d+)\r?\n(.*)")
  if tonumber(status) ~= 0 then return false end
  local language
  if PLATFORM:match("^Win") then
    language = output:match("^%s*([%a][%w_%-]*)")
  else
    language = output:match('^%s*%(%s*"?([%a][%w_%-]*)')
  end
  return language ~= nil and language:lower():match("^([%a]+)") == "ja"
end

local JAPANESE = is_japanese()
local FONT = PLATFORM:match("^Win")
    and (JAPANESE and "Yu Gothic UI" or "Segoe UI")
    or (JAPANESE and "Hiragino Sans" or "Helvetica")

local function tr(ja, en)
  return JAPANESE and ja or en
end

local GLUE_ACTION = 40362 -- Item: Glue items, ignoring time selection
local OPEN_ACTION = 40109 -- Item: Open items in primary external editor
local GROUP_ACTION = 1156 -- Options: Toggle item grouping override

local function stop(message)
  error({message = message}, 0)
end

local function error_message(err)
  if type(err) == "table" and type(err.message) == "string" then return err.message end
  return tr("処理を停止しました。もう一度実行してください。", "The operation stopped. Please try again.")
end

local function report(message)
  R.ShowMessageBox(message, tr("外部エディタ", "External editor"), 0)
end

local function finite(n)
  return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function uses_entire_source(item, take)
  if R.GetTakeNumStretchMarkers(take) ~= 0 then return false end
  local source = R.GetMediaItemTake_Source(take)
  if not source then return false end
  local offset = R.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
  local speed = R.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
  local item_length = R.GetMediaItemInfo_Value(item, "D_LENGTH")
  if not finite(offset) or not finite(speed) or speed <= 0
      or not finite(item_length) or item_length <= 0 then return false end
  local first, last = offset, offset + item_length * speed
  for _ = 1, 32 do
    local length, beats = R.GetMediaSourceLength(source)
    local rate = R.GetMediaSourceSampleRate(source)
    if beats or not finite(length) or length <= 0 or not finite(rate) or rate <= 0 then return false end
    local tolerance = 0.5 / rate + 1e-9
    if not finite(first) or not finite(last) or math.abs(first) > tolerance
        or math.abs(last - length) > tolerance then return false end
    local parent = R.GetMediaSourceParent(source)
    if not parent then
      local path = R.GetMediaSourceFileName(source, "")
      return type(path) == "string" and path ~= ""
    end
    local ok, section_offset, section_length = R.PCM_Source_GetSectionInfo(source)
    if not ok or not finite(section_offset) or not finite(section_length) or section_length <= 0 then return false end
    first, last = section_offset, section_offset + section_length
    source = parent
  end
  return false
end

local function source_path(take)
  local source = R.GetMediaItemTake_Source(take)
  if not source then return "" end
  for _ = 1, 32 do
    local parent = R.GetMediaSourceParent(source)
    if not parent then return R.GetMediaSourceFileName(source, "") end
    source = parent
  end
  stop(tr("元のソースを確認できません。", "Cannot identify the original audio source."))
end

local function verify(item, before)
  if not item or not R.ValidatePtr2(0, item, "MediaItem*") then
    stop(tr("グルー後のアイテムを取得できません。", "Cannot find the glued item."))
  end
  local take = R.GetActiveTake(item)
  if not take or R.TakeIsMIDI(take) then stop(tr("グルー後の音声テイクを取得できません。", "Cannot find the glued audio take.")) end
  local source = R.GetMediaItemTake_Source(take)
  if not source or R.GetMediaSourceParent(source) then stop(tr("使用範囲だけのソースを作成できませんでした。", "Cannot create an audio source containing only the item range.")) end
  local path = R.GetMediaSourceFileName(source, "")
  if not path or path == "" or not R.file_exists(path) or path:lower() == before.path:lower() then
    stop(tr("新しい音声ファイルの作成を確認できません。グルーが中止された可能性があります。", "Cannot verify the new audio file. Glue may have been cancelled."))
  end
  local length, beats = R.GetMediaSourceLength(source)
  local rate = R.GetMediaSourceSampleRate(source)
  if beats or not finite(length) or not finite(rate) or rate <= 0 then stop(tr("作成した音声の長さを確認できません。", "Cannot verify the length of the new audio.")) end
  local tolerance = 2 / rate + 1e-7
  local offset = R.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
  local speed = R.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
  local position = R.GetMediaItemInfo_Value(item, "D_POSITION")
  local item_length = R.GetMediaItemInfo_Value(item, "D_LENGTH")
  if not finite(offset) or not finite(speed) or not finite(position) or not finite(item_length)
      or math.abs(length - before.length) > tolerance or math.abs(offset) > tolerance
      or math.abs(speed - 1) > 1e-9 or math.abs(position - before.position) > tolerance
      or math.abs(item_length - before.length) > tolerance
      or R.GetMediaItem_Track(item) ~= before.track
      or R.CountMediaItems(0) ~= before.item_count then
    stop(tr("グルー後の音声がアイテムの使用範囲と一致しません。外部エディタへの送信を停止しました。", "The glued audio does not match the item range. Sending to the external editor was stopped."))
  end
  return take
end

local function selection()
  if R.GetPlayState() & 4 ~= 0 then stop(tr("録音を停止してから実行してください。", "Stop recording before running this action.")) end
  if R.CountSelectedMediaItems(0) ~= 1 then stop(tr("音声アイテムを1つだけ選択してください。", "Select exactly one audio item.")) end
  local item = R.GetSelectedMediaItem(0, 0)
  local take = R.GetActiveTake(item)
  if not take or R.TakeIsMIDI(take) then stop(tr("アクティブな音声テイクが必要です。", "An active audio take is required.")) end
  return item, take
end

local function execute(mode, expected)
  if mode ~= "original" and mode ~= "glue" then stop(tr("編集方法を選択できませんでした。", "Cannot identify the selected editing mode.")) end
  if expected and R.EnumProjects(-1, "") ~= expected.project then
    stop(tr("ダイアログを開いた後にプロジェクトが切り替わりました。再実行してください。", "The project changed while the dialog was open. Run the action again."))
  end
  local item, take = selection()
  if expected and (item ~= expected.item or take ~= expected.take) then
    stop(tr("ダイアログを開いた後にアイテムまたはテイクの選択が変わりました。再実行してください。", "The selected item or take changed while the dialog was open. Run the action again."))
  end
  if mode == "original" then
    R.Main_OnCommand(OPEN_ACTION, 0)
    return
  end
  if R.GetMediaItemInfo_Value(item, "C_LOCK") & 1 ~= 0 then stop(tr("アイテムのロックを解除してから実行してください。", "Unlock the item before running this action.")) end
  local name_ok, take_name = R.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
  if not name_ok or type(take_name) ~= "string" then stop(tr("元のテイク名を取得できません。", "Cannot read the original take name.")) end
  local before = {
    path = source_path(take),
    track = R.GetMediaItem_Track(item),
    position = R.GetMediaItemInfo_Value(item, "D_POSITION"),
    length = R.GetMediaItemInfo_Value(item, "D_LENGTH"),
    item_count = R.CountMediaItems(0),
  }
  if not finite(before.position) or not finite(before.length) or before.length <= 0 then stop(tr("アイテムの範囲が不正です。", "The item range is invalid.")) end
  local razor = {}
  for i = 0, R.CountTracks(0) - 1 do
    local track = R.GetTrack(0, i)
    local property = "P_RAZOREDITS_EXT"
    local ok, area = R.GetSetMediaTrackInfo_String(track, property, "", false)
    if not ok then
      property = "P_RAZOREDITS"
      ok, area = R.GetSetMediaTrackInfo_String(track, property, "", false)
    end
    if ok and area ~= "" then
      razor[#razor + 1] = {track = track, property = property, area = area}
    end
  end
  local grouping = R.GetToggleCommandStateEx(0, GROUP_ACTION) == 1
  R.Undo_BeginBlock2(0)
  R.PreventUIRefresh(1)
  local ok, message = xpcall(function()
    if grouping then R.Main_OnCommand(GROUP_ACTION, 0) end
    for _, r in ipairs(razor) do
      if not R.GetSetMediaTrackInfo_String(r.track, r.property, "", true) then stop(tr("レイザー編集範囲を一時解除できません。", "Cannot temporarily clear razor edit areas.")) end
    end
    R.Main_OnCommand(GLUE_ACTION, 0)
    if R.CountSelectedMediaItems(0) ~= 1 then stop(tr("グルー後の選択を確認できません。", "Cannot verify the selection after gluing.")) end
    local glued = R.GetSelectedMediaItem(0, 0)
    local glued_take = verify(glued, before)
    if not R.GetSetMediaItemTakeInfo_String(glued_take, "P_NAME", take_name, true) then
      stop(tr("グルー後のテイク名を元に戻せません。", "Cannot restore the original take name."))
    end
    local checked, restored_name = R.GetSetMediaItemTakeInfo_String(glued_take, "P_NAME", "", false)
    if not checked or restored_name ~= take_name then stop(tr("グルー後のテイク名を確認できません。", "Cannot verify the restored take name.")) end
  end, error_message)
  local restored = true
  for _, r in ipairs(razor) do
    local success, result = pcall(R.GetSetMediaTrackInfo_String, r.track, r.property, r.area, true)
    if not success or not result then restored = false end
  end
  if grouping and R.GetToggleCommandStateEx(0, GROUP_ACTION) ~= 1 then
    local success = pcall(R.Main_OnCommand, GROUP_ACTION, 0)
    if not success then restored = false end
  end
  R.PreventUIRefresh(-1)
  R.Undo_EndBlock2(0, "BLT_ACTION: " .. tr("表示範囲をグルー", "Glue visible item range"), -1)
  R.UpdateArrange()
  if not restored then stop(tr("編集範囲またはグループ設定を復元できません。Ctrl+Zで今回の操作を戻してください。", "Cannot restore the editing areas or grouping settings. Undo this operation in REAPER.")) end
  if not ok then stop(message .. tr("\n外部エディタへの送信は行っていません。作成途中の変更はCtrl+Zで戻せます。", "\nNothing was sent to the external editor. You can undo any changes made in REAPER.")) end
  R.Main_OnCommand(OPEN_ACTION, 0)
end

local function dialog_position(width, height)
  local x, y = R.GetMousePosition()
  local left, top, right, bottom = R.my_getViewport(0, 0, 0, 0, x, y, x + 1, y + 1, true)
  return math.floor(math.max(left + 8, math.min(x + 12, right - width - 16))),
         math.floor(math.max(top + 32, math.min(y + 12, bottom - height - 48)))
end

local function choose_mode(on_choice)
  local closed, pressed = false, nil
  local function close()
    if not closed then
      closed = true
      gfx.quit()
    end
  end
  local x, y = dialog_position(440, 86)
  gfx.init(tr("編集する範囲を選択", "Choose editing range"), 440, 86, 0, x, y)
  R.atexit(close)
  local previous_left = (gfx.mouse_cap & 1) ~= 0
  local function poll()
    if closed then return end
    local key = gfx.getchar()
    if key < 0 or key == 27 then
      close()
      return
    end
    local width = math.max(1, (gfx.w - 48) / 2)
    local height = math.max(1, gfx.h - 36)
    local buttons = {
      {mode = "original", text = tr("元波形を編集", "Edit original audio"), x = 16, y = 18, w = width, h = height},
      {mode = "glue", text = tr("表示範囲をグルー", "Glue visible range"), x = 32 + width, y = 18, w = width, h = height},
    }
    local hovered
    for _, b in ipairs(buttons) do
      if gfx.mouse_x >= b.x and gfx.mouse_x < b.x + b.w and
          gfx.mouse_y >= b.y and gfx.mouse_y < b.y + b.h then hovered = b.mode end
    end
    local left = (gfx.mouse_cap & 1) ~= 0
    if left and not previous_left then pressed = hovered end
    if not left and previous_left then
      local mode = pressed
      pressed = nil
      if mode and mode == hovered then
        close()
        on_choice(mode)
        return
      end
    end
    previous_left = left
    gfx.set(0.10, 0.11, 0.13, 1)
    gfx.rect(0, 0, gfx.w, gfx.h, 1)
    gfx.setfont(1, FONT, 18)
    for _, b in ipairs(buttons) do
      if hovered == b.mode then gfx.set(0.24, 0.37, 0.53, 1) else gfx.set(0.18, 0.23, 0.30, 1) end
      gfx.rect(b.x, b.y, b.w, b.h, 1)
      gfx.set(0.95, 0.96, 0.98, 1)
      local tw, th = gfx.measurestr(b.text)
      gfx.x, gfx.y = b.x + (b.w - tw) / 2, b.y + (b.h - th) / 2
      gfx.drawstr(b.text)
    end
    gfx.update()
  end
  local function tick()
    local ok, message = xpcall(poll, error_message)
    if not ok then
      close()
      report(message)
    elseif not closed then
      R.defer(tick)
    end
  end
  tick()
end

local function main()
  local item, take = selection()
  local expected = {project = R.EnumProjects(-1, ""), item = item, take = take}
  if uses_entire_source(item, take) then
    execute("original", expected)
    return
  end
  choose_mode(function(mode) execute(mode, expected) end)
end

local ok, message = xpcall(main, error_message)
if not ok then report(message) end
