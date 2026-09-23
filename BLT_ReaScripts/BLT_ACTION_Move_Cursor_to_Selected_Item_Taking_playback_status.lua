-- @description ACTION_Move_Cursor_to_Selected_Item_Taking_playback_status
-- @version 1.0.0
-- @author Balrulu
-- @provides
--   . > ../
-- @changelog
--   BLT SERIES ACTIONS
-- @about
--   BLT SERIES Beta TEST UPLOAD

reaper.defer(function() end)

local project = 0 -- 現在のプロジェクト
local play_state = reaper.GetPlayStateEx(project)

-- 録音中の意図しない移動を防止
if (play_state & 4) ~= 0 then return end

local count = reaper.CountSelectedMediaItems(project)
if count == 0 then return end

-- トラック順や選択順ではなく、実際の開始位置を比較
local target_position = nil
for index = 0, count - 1 do
    local item = reaper.GetSelectedMediaItem(project, index)
    if item then
        local position = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        if target_position == nil or position < target_position then
            target_position = position
        end
    end
end

if target_position == nil then return end

local is_playing = (play_state & 1) ~= 0 and (play_state & 2) == 0

-- 表示を移動先へ追従させ、再生中の場合だけ再生位置も移動
reaper.SetEditCurPos2(project, target_position, true, is_playing)
