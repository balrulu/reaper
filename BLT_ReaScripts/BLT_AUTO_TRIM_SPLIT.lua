-- @description AUTO TRIM / SPLIT
-- @version 0.5.7
-- @author Balrulu
-- @provides
--   . > ../
-- @changelog
--   BLT SERIES Beta TEST UPLOAD
-- @about
--   BLT SERIES Beta TEST UPLOAD

-- BLT preset transfer limits 1.1.0. Embedded; no runtime dependency.
local BLTPresetLimits={bytes=16777216,stringBytes=2097152,nodes=262144,entries=8192}
function BLTPresetLimits.show(english)
 reaper.MB(english and 'Preset capacity limit exceeded. Export presets individually instead of as a bundle.' or '容量上限オーバーです。一括ではなく個別に保存してください。','BLT PRESET',0)
end

-- BLT media availability 1.0.2. Pause audio work, never the UI defer loop.
local function create_media_gate(api,graphics)
 local M={waiting=false,epoch=0};local P=setmetatable({}, {__index=api})
 local accessors={};local next_check=0;local ready=true;local settle=0;local last_active
 local function valid(project,p,kind)
  return p and (not api.ValidatePtr2 or api.ValidatePtr2(project,p,kind))
 end
 local function application_active()
  if graphics and graphics.getchar then
   local flags=graphics.getchar(65537)
   if flags>=0 and ((flags&1)==0 or (flags&2)~=0) then return true end
  end
  if not (api.JS_Window_GetForeground and api.GetMainHwnd and api.JS_Window_GetParent) then return nil end
  local foreground=api.JS_Window_GetForeground();local main=api.GetMainHwnd()
  for _=1,32 do
   if not foreground then return false end
   if foreground==main then return true end
   local parent=api.JS_Window_GetParent(foreground)
   if parent==foreground then return nil end;foreground=parent
  end
  return nil
 end
 local function offline(project,take)
  -- targets() resolves or validates each pointer in this same defer pass.
  if not take then return false end
  if api.TakeIsMIDI and api.TakeIsMIDI(take) then return false end
  if not api.GetMediaItemTake_Source then return false end
  local source=api.GetMediaItemTake_Source(take);local seen={}
  for _=1,32 do
   if not source or seen[source] then break end;seen[source]=true
   local is_offline=false
   if api.CF_GetMediaSourceOnline then
    is_offline=not api.CF_GetMediaSourceOnline(source)
   elseif api.GetMediaSourceSampleRate and api.GetMediaSourceNumChannels then
    is_offline=api.GetMediaSourceSampleRate(source)<=0 or api.GetMediaSourceNumChannels(source)<=0
   end
   if is_offline then
    local file=api.GetMediaSourceFileName and api.GetMediaSourceFileName(source,'') or ''
    if file~='' and (not api.file_exists or api.file_exists(file)) then return true end
   end
   source=api.GetMediaSourceParent and api.GetMediaSourceParent(source) or nil
  end
  return false
 end
 local fields={'info','v','source','snapshot','plans','items','list','queue','entries','reader','data','p','left','right','parts','sources','source_items'}
 local function targets(project,all_items)
  local takes,seen,items={},{},{};local invalid=false
  local function item(p,fresh)
   if p and items[p] then return end
   if not p or (not fresh and not valid(project,p,'MediaItem*')) then invalid=true;return end
   items[p]=true
   local take=api.GetActiveTake and api.GetActiveTake(p)
   if take then takes[take]=true end
  end
  local function visit(v,depth)
   if type(v)~='table' or seen[v] or depth>12 then return end;seen[v]=true
   if v.project and v.project~=project then invalid=true;return end
   if v.item then item(v.item) end
   if v.take then
    if takes[v.take] or valid(project,v.take,'MediaItem_Take*') then takes[v.take]=true else invalid=true end
   end
   if v.temp_take and (takes[v.temp_take] or valid(project,v.temp_take,'MediaItem_Take*')) then takes[v.temp_take]=true end
   for _,key in ipairs(fields) do visit(v[key],depth+1) end
   for _,entry in ipairs(v) do if type(entry)=='table' then visit(entry,depth+1) end end
  end
  if api.CountSelectedMediaItems and api.GetSelectedMediaItem then
   for i=0,api.CountSelectedMediaItems(project)-1 do item(api.GetSelectedMediaItem(project,i),true) end
  end
  local a=M.state
  if a then
   for _,key in ipairs({'job','analysis','batch','source_job','wave_job','pjob','xjob','ajob'}) do visit(a[key],0) end
   if a.job or a.batch or a.source_job then visit(a.items,0);visit(a.queue,0) end
  end
  if (all_items or (M.all_items and M.state and M.state.job)) and api.CountMediaItems and api.GetMediaItem then
   for i=0,api.CountMediaItems(project)-1 do item(api.GetMediaItem(project,i),true) end
  end
  return takes,invalid
 end
 function M.ready(force,all_items)
  local now=api.time_precise()
  if not force and now<next_check then return ready end
  next_check=now+.10
  local project=api.EnumProjects(-1,'')
  local takes,invalid=targets(project,all_items);local blocked=false
  if M.state and M.state.project and M.state.project~=project then invalid=true end
  if not invalid then
   if next(takes) and not api.CF_GetMediaSourceOnline and application_active()==false then blocked=true
   else for take in pairs(takes) do if offline(project,take) then blocked=true;break end end end
  end
  if invalid or not next(takes) then settle=0 end
  if blocked then settle=now+.25 end
  local waiting=not invalid and (blocked or now<settle)
  ready=not waiting
  if waiting~=M.waiting then
   M.waiting=waiting;if not waiting then M.epoch=M.epoch+1 end
   if M.onchange then M.onchange() end
  end
  return ready
 end
 function M.tick()
  local active=application_active()
  if active~=last_active then next_check=0;last_active=active end
  return M.ready()
 end
 function M.message(section)
  return api.GetExtState(section,'ui_language')=='EN' and 'Waiting for media to come online…' or 'メディアのオンライン復帰を待っています…'
 end
 local function signature(take)
  if not (api.GetMediaItemTake_Item and api.GetItemStateChunk) then return nil end
  local item=api.GetMediaItemTake_Item(take);if not item then return nil end
  local ok,chunk=api.GetItemStateChunk(item,'',false)
  return ok and chunk or nil
 end
 if api.CreateTakeAudioAccessor then
  function P.CreateTakeAudioAccessor(take)
   local aa=api.CreateTakeAudioAccessor(take)
   if aa then accessors[aa]={take=take,project=api.EnumProjects(-1,''),signature=signature(take),revision=api.GetProjectStateChangeCount and api.GetProjectStateChangeCount(api.EnumProjects(-1,'')),epoch=M.epoch} end
   return aa
  end
 end
 if api.CreateTrackAudioAccessor then
  function P.CreateTrackAudioAccessor(track)
   local aa=api.CreateTrackAudioAccessor(track);local project=api.EnumProjects(-1,'')
   if aa then accessors[aa]={track=track,project=project,revision=api.GetProjectStateChangeCount(project),epoch=M.epoch} end
   return aa
  end
 end
 local function resume(aa)
  local state=accessors[aa]
  if not state or state.epoch==M.epoch or M.waiting then return end
  state.epoch=M.epoch
  if api.EnumProjects(-1,'')~=state.project then return end
  local unchanged=state.take and valid(state.project,state.take,'MediaItem_Take*') and state.signature and signature(state.take)==state.signature
  if state.take and state.revision and api.GetProjectStateChangeCount(state.project)~=state.revision then unchanged=false end
  if state.track then unchanged=valid(state.project,state.track,'MediaTrack*') and api.GetProjectStateChangeCount(state.project)==state.revision end
  if unchanged and api.AudioAccessorUpdate then api.AudioAccessorUpdate(aa) end
 end
 if api.AudioAccessorStateChanged then
  function P.AudioAccessorStateChanged(aa) resume(aa);return api.AudioAccessorStateChanged(aa) end
 end
 if api.GetAudioAccessorSamples then
  function P.GetAudioAccessorSamples(...) local aa=...;resume(aa);return api.GetAudioAccessorSamples(...) end
 end
 if api.DestroyAudioAccessor then
  function P.DestroyAudioAccessor(aa) accessors[aa]=nil;return api.DestroyAudioAccessor(aa) end
 end
 return M,P
end
local Media,reaper=create_media_gate(reaper,gfx)


-- BLT window geometry 1.0.0. Embedded; screen coordinates only.
local function create_window_geometry(api,graphics)
 local osname=api.GetOS() or ''
 if not osname:match('OSX') and not osname:match('macOS') then return api end
 local G=setmetatable({}, {__index=api})
 -- Internal screen Y points downward. Client coordinates remain untouched.
 function G.GetMousePosition()
  local x,y=api.GetMousePosition();return x,-y
 end
 function G.JS_Window_GetRect(hwnd)
  local ok,l,t,r,b=api.JS_Window_GetRect(hwnd)
  if not ok then return ok,l,t,r,b end
  return ok,l,-math.max(t,b),r,-math.min(t,b)
 end
 function G.JS_Window_SetPosition(hwnd,x,y,w,h,z,flags)
  if graphics and graphics.dock and (graphics.dock(-1)&1)~=0 then return false end
  -- SWELL SetWindowPos uses a bottom-left origin for floating macOS windows.
  return api.JS_Window_SetPosition(hwnd,x,-y-h,w,h,z,flags)
 end
 return G
end

local WindowGeometry=create_window_geometry(reaper,gfx)
local BLT_MAC=(reaper.GetOS() or ''):match('OSX')~=nil or (reaper.GetOS() or ''):match('macOS')~=nil

-- BLT language runtime 1.1.0. Embed with an app-specific catalog; no runtime file I/O.
local function create_language(api,section,catalog)
 local L={code=api.GetExtState(section,'ui_language')=='EN' and 'EN' or 'JP'}
 local en=catalog.en
 local cache,count={},0
 -- Fixed labels: one lookup, no pattern scan, allocation, or cache insertion.
 function L.text(value)
  local text=type(value)=='string' and value or tostring(value or '')
  if L.code=='JP' then return text end
  return en[text] or text
 end
 -- Only status text, tooltips and dialogs need dynamic-message handling.
 function L.message(value)
  local text=type(value)=='string' and value or tostring(value or '')
  if L.code=='JP' then return text end
  local translated=en[text] or cache[text]
  if translated then return translated end
  if not text:find('[\128-\255]') then return text end
  for _,prefix in ipairs(catalog.prefixes) do
   if text:sub(1,#prefix)==prefix then translated=en[prefix]..text:sub(#prefix+1);break end
  end
  if not translated then for _,entry in ipairs(catalog.patterns) do
   if text:find(entry[1]) then
    if entry[3] then
     local values={text:match(entry[1])}
     for _,i in ipairs(entry[3]) do values[i]=L.message(values[i]) end
     translated=string.format(entry[2],table.unpack(values))
    else translated=string.format(entry[2],text:match(entry[1])) end
    break
   end
  end end
  translated=translated or text
  if count>=64 then cache={};count=0 end
  cache[text]=translated;count=count+1
  return translated
 end
 function L.set(code)
  if (code~='JP' and code~='EN') or code==L.code then return false end
  L.code=code;api.SetExtState(section,'ui_language',code,true);return true
 end
 function L.mb(message,title,kind) return api.MB(L.message(message),L.text(title),kind) end
 function L.input(title,n,captions,defaults) return api.GetUserInputs(L.text(title),n,L.text(captions),defaults) end
 function L.open(path,title,ext) return api.GetUserFileNameForRead(path,L.text(title),ext) end
 function L.save(title,path,file,filter) return api.JS_Dialog_BrowseForSaveFile(L.text(title),path,file,filter) end
 function L.menu(value)
  if L.code=='JP' then return value end
  return (value:gsub('[^|]+',function(item)
   local flags,body=item:match('^([!#<>]*)(.*)$')
   return flags..L.message(body)
  end))
 end
 return L
end

-- Latest embedded application catalog.
local LanguageCatalog={en={
 ["ファクトリーデフォルト"]="Factory Default",
 ["ファクトリーデフォルトは変更できません。"]="Factory Default is read-only.",
 ["「"]="\"",
 ["」を上書きしますか？"]="\"?",
 ["プリセットは200個まで保存できます。"]="Up to 200 presets can be saved.",
 ["名前を付けて保存"]="Save As",
 ["プリセット名:"]="Preset name:",
 ["有効なプリセット名を入力してください。"]="Enter a valid preset name.",
 ["設定値を確認してください。"]="Check settings.",
 ["プリセットを保存しました: "]="Saved: ",
 ["未保存の変更を破棄して読み込みますか？"]="Discard unsaved changes and load?",
 ["プリセットを読み込みました: "]="Loaded: ",
 ["プリセットをインポート（個別／一覧）"]="Import preset(s)",
 ["ファイルを開けません。"]="Cannot open file.",
 ["このアプリ用の有効なプリセットではありません。"]="Not a valid preset for this app.",
 ["プリセットが200個を超えます。"]="Preset count exceeds 200.",
 ["同名のプリセットを上書きして取り込みますか？"]="Overwrite presets with matching names?",
 ["個インポートしました。"]=" preset(s) imported.",
 ["現在値"]="Current settings",
 ["プリセット一覧をエクスポート"]="Export preset list",
 ["現在値をエクスポート"]="Export current settings",
 ["保存先のフルパス:"]="Full save path:",
 ["保存先のファイルを上書きしますか？"]="Overwrite the existing file?",
 ["エクスポートしました。"]="Exported.",
 ["戻る"]="Back",
 ["プリセット"]="Presets",
 ["上書き保存"]="Save",
 ["名前を付けて保存…"]="Save As...",
 ["インポート…"]="Import...",
 ["現在: "]="Current: ",
 ["未選択"]="None",
 ["%d–%d / %d   スクロールで選択"]="%d–%d / %d   Scroll to browse",
 ["閉じる"]="Close",
 ["ウィンドウサイズ初期化"]="Reset window size",
 ["カメレオンモード"]="Chameleon mode",
 ["縮小／展開"]="Collapse / Expand",
 ["次のプリセット"]="Next preset",
 ["前のプリセット"]="Previous preset",
 ["プリセット（読込・保存・インポート／エクスポート）"]="Presets: load, save, import/export",
 ["解析中...%d%%"]="Analyzing...%d%%",
 ["解析中...100%"]="Analyzing...100%",
 ["設定値が範囲外です："]="Setting out of range: ",
 ["クローズはオープン以下の値にしてください。"]="Close must not exceed Open.",
 ["検出基準が無効です。"]="Invalid detection mode.",
 ["処理方法が無効です。"]="Invalid processing mode.",
 ["数値を入力してください。"]="Enter a number.",
 ["対象アイテムがありません。"]="No target items.",
 ["MIDI／空アイテムは対象外です。"]="MIDI and empty items are unsupported.",
 ["音声ソースがありません。"]="No audio source.",
 ["音声を持たないアイテムは対象外です。"]="Items without audio are unsupported.",
 ["音声チャンネルを取得できません。"]="Cannot read audio channels.",
 ["長さが0のアイテムは対象外です。"]="Zero-length items are unsupported.",
 ["対象アイテムが見つかりません。"]="Target item not found.",
 ["アイテムの状態を保存できません。"]="Cannot save item state.",
 ["対象が削除されました。"]="Target was deleted.",
 ["1アイテムは60分以内にしてください。"]="Keep each item under 60 minutes.",
 ["ピーク解析用バッファを作成できません。"]="Cannot allocate peak buffer.",
 ["LUFS-Mはモノ／ステレオ対応です。多チャンネルはピークを選択してください。"]="LUFS-M supports mono/stereo. Use Peak for multichannel audio.",
 ["ラウドネス解析用バッファを作成できません。"]="Cannot allocate loudness buffer.",
 ["音声アクセサを作成できません。"]="Cannot create audio accessor.",
 ["音声を読み出せません。オフライン状態やソースを確認してください。"]="Cannot read audio. Check source and online status.",
 ["REAPERのピークデータを取得できず、音声の直接読み出しにも失敗しました。ソースのオンライン状態を確認してください。"]="Peak data and direct audio reading failed. Check source online status.",
 ["音声の直接読み出しに失敗しました（戻り値："]="Direct audio read failed (code: ",
 ["）。"]=").",
 ["音声に読み取れないサンプルがあります。"]="Audio contains unreadable samples.",
 ["解析中に対象が削除されました。"]="Target was deleted during analysis.",
 ["解析中に音声が変更されました。選択を更新してください。"]="Audio changed during analysis. Refresh selection.",
 ["音声取得に失敗しました（戻り値："]="Audio read failed (code: ",
 ["）。解析を中止しました。"]="). Analysis stopped.",
 ["解析モードが無効です。"]="Invalid analysis mode.",
 ["検出区間が安全上限を超えました。しきい値、最小無音、最小区間の設定を調整してください。"]="Too many detected sections. Adjust threshold, minimum silence and minimum clip length.",
 ["アイテム属性を更新できません："]="Cannot update item property: ",
 ["対象が見つかりません：%s（%s）"]="Target not found: %s (%s)",
 ["不明なエラー"]="Unknown error",
 ["ロックされたアイテムがあります：%s"]="Locked item: %s",
 ["解析後に対象が変更されています：%s"]="Target changed after analysis: %s",
 ["処理対象がありません。"]="Nothing to process.",
 ["アイテムを分割できません。"]="Cannot split item.",
 ["無音部分を削除できません。"]="Cannot delete silence.",
 ["アイテムを移動できません。"]="Cannot move item.",
 ["処理を中止し、元のアイテムを復元しました。"]="Processing stopped. Original items restored.",
 ["復元できない項目があります。REAPERのUndoで戻してください。"]="Some items could not be restored. Use REAPER Undo.",
 ["ファイルが長いため、解析中および結果を表示している間はメモリ使用量が増えます。よろしいですか？\n\n%s\n長さ：%.1f分\n\n［実行］する場合は OK、［キャンセル］する場合はキャンセルを押してください。\nキャンセルしたアイテムは選択解除されます。"]="This long file uses more memory during analysis and while results are shown. Continue?\n\n%s\nLength: %.1f min\n\nOK: continue / Cancel: skip and deselect this item.",
 ["Auto Trim / Split | 長尺LUFS解析"]="Auto Trim / Split | Long LUFS analysis",
 ["長尺アイテム%d件のLUFS解析をキャンセルし、選択を解除しました。"]="Cancelled LUFS analysis and deselected %d long item(s).",
 ["音声アイテムを選択してください。"]="Select audio items.",
 [" 対象外："]=" Skipped: ",
 ["個"]=" items",
 ["長尺アイテム%d件の選択を解除しました。 "]="Deselected %d long item(s). ",
 ["Peakデータをキャッシュから読み込みました。"]="Peak data loaded from cache.",
 ["Loudnessデータをキャッシュから読み込みました。"]="Loudness data loaded from cache.",
 ["Peakを取得しています。"]="Reading peaks.",
 ["ラウドネスを解析しています。"]="Analyzing loudness.",
 ["プレビューを更新しています。"]="Updating preview.",
 ["Peakの数値設定を初期値に戻しました。"]="Peak values reset.",
 ["Loudnessの数値設定を初期値に戻しました。"]="Loudness values reset.",
 ["%dアイテムを処理しました。%s"]="Processed %d item(s). %s",
 ["次の対象を表示しています。"]="Showing next target.",
 ["完了です。"]="Done.",
 ["ロックされたアイテムがあります："]="Locked item: ",
 ["長尺アイテムのLUFS解析をキャンセルし、選択を解除しました。バッチ処理は開始前の状態で中止しました。"]="Long-item LUFS analysis cancelled; item deselected. Batch stopped before edits.",
 ["解析を中止しました。アイテムは変更していません。"]="Analysis stopped. Items unchanged.",
 ["プレビューの解析完了を待ってください。"]="Wait for preview analysis.",
 ["ロックされたアイテムがあります。ロックを解除してください。"]="Unlock the locked items.",
 ["長尺アイテムのLUFS解析をキャンセルし、選択を解除しました。"]="Long-item LUFS analysis cancelled; item deselected.",
 ["実行用に全対象を再解析しています。"]="Reanalyzing all targets for processing.",
 ["音あり区間は0です。実行すると対象全体を削除します。"]="No audio sections. Processing will delete the entire target.",
 ["分割境界はありません。"]="No split boundaries.",
 ["%d区間を検出。設定を調整してから実行できます。"]="Detected %d sections. Adjust settings, then run.",
 ["CHAMELEON  REAPERテーマに擬態"]="CHAMELEON  REAPER theme",
 ["CHAMELEON  オリジナル配色"]="CHAMELEON  Original colors",
 ["カスタムタイトルバーには js_ReaScriptAPI が必要です。\nReaPack から js_ReaScriptAPI をインストールしてください。"]="The app bar requires js_ReaScriptAPI.\nInstall js_ReaScriptAPI via ReaPack.",
 ["ON / 両端のみ"]="ON / Ends only",
 ["ON：最初と最後の有効区間の外側だけを処理します。内部の無音は残し、プリ／ポストロールは外側の両端に適用します。"]="ON: process only outside the first and last audio sections. Keep internal silence; apply pre/post-roll at the outer ends.",
 ["数値を入力できなかったため、元の値へ戻しました。"]="Invalid input. Previous value restored.",
 [" ／ 上下ドラッグ・ホイール："]=" / Drag vertically or wheel: ",
 ["刻み"]=" steps",
 ["Peakを取得しています…"]="Reading peaks...",
 ["ラウドネスを解析しています…"]="Analyzing loudness...",
 ["音声アイテムを選択してください"]="Select audio items",
 ["ホイール：拡大・縮小 ／ Shift＋ホイール：横移動"]="Wheel: zoom / Shift+wheel: pan",
 ["位置 %.3f s / Peak %.1f dBFS / OPEN LUFS-M %.1f / CLOSE FAST %.1f"]="Position %.3f s / Peak %.1f dBFS / OPEN LUFS-M %.1f / CLOSE FAST %.1f",
 ["位置 %.3f s / Peak %.1f dBFS"]="Position %.3f s / Peak %.1f dBFS",
 ["SILENCE DETECTION / TRIM  スレッショルドによる無音検出・区間処理"]="SILENCE DETECTION / TRIM  Threshold-based processing",
 ["選択 %02d   /   残り %02d"]="Selected %02d   /   Left %02d",
 ["検出区間  %d    合計  %.3f s"]="Sections %d    Total %.3f s",
 ["検出基準"]="DETECTION",
 ["ピークレベル"]="Peak level",
 ["各1 ms区間の最大振幅。全チャンネルの最大値で検出します。"]="Maximum amplitude per 1 ms block across all channels.",
 ["ラウドネス"]="Loudness",
 ["OPENはK特性＋400 msのLUFS-M、CLOSEは同じK特性＋100 msのFASTラウドネスで判定します。"]="OPEN: K-weighted 400 ms LUFS-M. CLOSE: K-weighted 100 ms FAST loudness.",
 ["検出レベル"]="LEVELS",
 ["オープンスレッショルド"]="Open threshold",
 ["LUFS-M（400 ms）がこの値を超えると音あり区間を開始します。"]="Start an audio section when LUFS-M (400 ms) exceeds this level.",
 ["この値を超えると音あり区間を開始します。"]="Start an audio section above this level.",
 ["クローズスレッショルド"]="Close threshold",
 ["FASTラウドネス（100 ms）がこの値未満になると無音候補を開始します。"]="Start a silence candidate when FAST loudness (100 ms) drops below this level.",
 ["この値未満になると無音候補を開始します。"]="Start a silence candidate below this level.",
 ["スレッショルド差を固定"]="Link thresholds",
 ["開閉スレッショルドの差を保ったまま両方を動かします。"]="Move both thresholds while keeping their difference.",
 ["時間設定"]="TIMING",
 ["短い無音を無視"]="Ignore short silence",
 ["この時間未満の無音は無視して、前後の音を同じ音あり区間として扱います。"]="Treat silence shorter than this as part of the surrounding audio section.",
 ["最短クリップ長"]="Min. clip length",
 ["この時間未満の音あり区間は残すクリップとして採用しません。プリ／ポストロールを加える前の長さで判定します。"]="Discard audio sections shorter than this, measured before pre/post-roll.",
 ["プリロール"]="Pre-roll",
 ["正：開始を前へ広げる／負：開始を後ろへ縮める。元アイテム内に制限します。"]="Positive: extend start earlier. Negative: trim start later. Limited to the original item.",
 ["ポストロール"]="Post-roll",
 ["正：終了を後ろへ広げる／負：終了を前へ縮める。重なった区間は結合します。"]="Positive: extend end later. Negative: trim end earlier. Merge overlapping sections.",
 ["フェードイン"]="Fade in",
 ["音あり区間に指定時間のフェードインを設定します。"]="Apply this fade-in duration to audio sections.",
 ["フェードアウト"]="Fade out",
 ["音あり区間に指定時間のフェードアウトを設定します。"]="Apply this fade-out duration to audio sections.",
 ["短い区間ではフェードが重ならない長さに縮めます。"]="Shorten fades to avoid overlap on short sections.",
 ["無音部分を削除"]="Remove silence",
 ["灰色の区間を削除し、青色の区間を残します。"]="Delete gray sections and keep blue sections.",
 ["分割"]="Split",
 ["青・灰の境界で分割し、全ての区間を元の位置に残します。"]="Split at blue/gray boundaries and keep all sections in place.",
 ["削除した区間を詰める"]="Close gaps",
 ["ON：無音部分を削除した後、残った検出区間を元アイテムの開始位置から隙間なく詰めます。"]="ON: after removing silence, pack remaining sections from the original item start.",
 ["全選択を解析中  %d / %d    %d%%（解析完了後にまとめて編集）"]="Analyzing all %d / %d    %d%% (edits follow analysis)",
 ["Peak取得  %d%%"]="Reading peaks %d%%",
 ["Loudness解析  %d%%"]="Loudness analysis %d%%",
 ["現在の検出モードの数値設定だけを初期値へ戻します。各スイッチ設定は変更しません。"]="Reset numeric values for the current detection mode. Keep switches unchanged.",
 ["処理を中止"]="Stop",
 ["処理を実行"]="Process",
 ["Enter：実行。編集は1回のUndoで元に戻せます。"]="Enter: run. One Undo restores all edits.",
 ["選択アイテムを一括処理"]="Process all selected",
 ["ON：先頭をプレビューして全選択へ適用。OFF：1つずつ処理して次へ。"]="ON: preview first item, apply to all. OFF: process one at a time.",
 ["Auto Trim / Split | エラー"]="Auto Trim / Split | Error",
 ["カスタムタイトルバーを初期化できません。"]="Cannot initialize the app bar.",
 ["プロジェクトが変更されたため解析を中止しました。"]="Project changed. Analysis stopped.",
 ["表示言語を切替（JP / EN）"]="Switch language (JP / EN)",
 ["プリセットを読み込みました: ファクトリーデフォルト"]="Loaded: Factory Default",
 ["選択中のトラック / バスを指定"]="Use selected track / bus",
},patterns={
 {"^「(.*)」を上書きしますか？$","Overwrite \"%s\"?"},
 {"^([%+%-]?[%d%.eE]+)–([%+%-]?[%d%.eE]+) / ([%+%-]?[%d%.eE]+)   スクロールで選択$","%d–%d / %d   Scroll to browse"},
 {"^解析中%.%.%.([%+%-]?[%d%.eE]+)%%$","Analyzing...%d%%"},
 {"^対象が見つかりません：(.-)（(.-)）$","Target not found: %s (%s)"},
 {"^ロックされたアイテムがあります：(.-)$","Locked item: %s"},
 {"^解析後に対象が変更されています：(.-)$","Target changed after analysis: %s"},
 {"^ファイルが長いため、解析中および結果を表示している間はメモリ使用量が増えます。よろしいですか？\n\n(.-)\n長さ：([%+%-]?[%d%.eE]+)分\n\n［実行］する場合は OK、［キャンセル］する場合はキャンセルを押してください。\nキャンセルしたアイテムは選択解除されます。$","This long file uses more memory during analysis and while results are shown. Continue?\n\n%s\nLength: %.1f min\n\nOK: continue / Cancel: skip and deselect this item."},
 {"^長尺アイテム([%+%-]?[%d%.eE]+)件のLUFS解析をキャンセルし、選択を解除しました。$","Cancelled LUFS analysis and deselected %d long item(s)."},
 {"^長尺アイテム([%+%-]?[%d%.eE]+)件の選択を解除しました。 $","Deselected %d long item(s). "},
 {"^([%+%-]?[%d%.eE]+)アイテムを処理しました。(.-)$","Processed %d item(s). %s",{2}},
 {"^([%+%-]?[%d%.eE]+)区間を検出。設定を調整してから実行できます。$","Detected %d sections. Adjust settings, then run."},
 {"^位置 ([%+%-]?[%d%.eE]+) s / Peak ([%+%-]?[%d%.eE]+) dBFS / OPEN LUFS%-M ([%+%-]?[%d%.eE]+) / CLOSE FAST ([%+%-]?[%d%.eE]+)$","Position %.3f s / Peak %.1f dBFS / OPEN LUFS-M %.1f / CLOSE FAST %.1f"},
 {"^位置 ([%+%-]?[%d%.eE]+) s / Peak ([%+%-]?[%d%.eE]+) dBFS$","Position %.3f s / Peak %.1f dBFS"},
 {"^選択 ([%+%-]?[%d%.eE]+)   /   残り ([%+%-]?[%d%.eE]+)$","Selected %02d   /   Left %02d"},
 {"^検出区間  ([%+%-]?[%d%.eE]+)    合計  ([%+%-]?[%d%.eE]+) s$","Sections %d    Total %.3f s"},
 {"^全選択を解析中  ([%+%-]?[%d%.eE]+) / ([%+%-]?[%d%.eE]+)    ([%+%-]?[%d%.eE]+)%%（解析完了後にまとめて編集）$","Analyzing all %d / %d    %d%% (edits follow analysis)"},
 {"^Peak取得  ([%+%-]?[%d%.eE]+)%%$","Reading peaks %d%%"},
 {"^Loudness解析  ([%+%-]?[%d%.eE]+)%%$","Loudness analysis %d%%"},
 {"^「(.-)」を上書きしますか？$","\"%s\"?"},
 {"^(.-)」を上書きしますか？$","%s\"?"},
 {"^プリセットを保存しました: (.-)$","Saved: %s"},
 {"^プリセットを読み込みました: (.-)$","Loaded: %s"},
 {"^(.-)個インポートしました。$","%s preset(s) imported."},
 {"^現在: (.-)(.-)$","Current: %s%s"},
 {"^設定値が範囲外です：(.-)$","Setting out of range: %s"},
 {"^音声の直接読み出しに失敗しました（戻り値：(.-)）。$","Direct audio read failed (code: %s)."},
 {"^(.-)）。$","%s)."},
 {"^音声取得に失敗しました（戻り値：(.-)）。解析を中止しました。$","Audio read failed (code: %s). Analysis stopped."},
 {"^(.-)）。解析を中止しました。$","%s). Analysis stopped."},
 {"^アイテム属性を更新できません：(.-)$","Cannot update item property: %s"},
 {"^音声アイテムを選択してください。(.-)$","Select audio items.%s"},
 {"^ 対象外：(.-)個$"," Skipped: %s items"},
 {"^(.-)個$","%s items"},
 {"^ロックされたアイテムがあります：(.-)$","Locked item: %s"},
 {"^(.-) ／ 上下ドラッグ・ホイール：(.-)刻み$","%s / Drag vertically or wheel: %s steps"},
 {"^ ／ 上下ドラッグ・ホイール：(.-)刻み$"," / Drag vertically or wheel: %s steps"},
 {"^(.-)刻み$","%s steps"},
 {"^「(.*)」を上書きしますか？$","Overwrite \"%s\"?"},
 {"^(%d+)個インポートしました。$","Imported %s preset(s)."},
 {"^(%d+)件をノーマライズしました。選択を解除しました。$","Normalized %s items and deselected them."},
},prefixes={"音声の直接読み出しに失敗しました（戻り値：","音声取得に失敗しました（戻り値：","ロックされたアイテムがあります：","プリセットを読み込みました: ","アイテム属性を更新できません："," ／ 上下ドラッグ・ホイール：","プリセットを保存しました: ","設定値が範囲外です："," 対象外：","現在: "}}

local Language=create_language(reaper,"BLT_AUTO_TRIM_SPLIT",LanguageCatalog)
local R=reaper
-- BLT primary button 1.0.0. Embedded; no runtime file dependency.
local PrimaryButton=(function()
 local P={state={hover=0},nextFrame=0}
 local sin,pi,min,max=math.sin,math.pi,math.min,math.max
 -- Same emitter, lifetime, trajectory, clipping and three glow layers as LOUDNESS TRACE.
 -- Reuse expired particle records without changing insertion or drawing order.
 function P.drawParticles(d,s,x,y,w,h,hover,analyzing,realDt,animationDt,mx,my)
  local C=d.C;local ice=C.accent2 or C.ice
  if not s.particles then s.particles={};s.pool={};s.serial=0;s.particleClock=0 end
  local particles,pool=s.particles,s.pool
  if hover or analyzing then
   s.particleClock=s.particleClock+(analyzing and realDt or animationDt)
   local interval=analyzing and .030 or .055
   local cap=analyzing and 66 or 44
   while s.particleClock>=interval and #particles<cap do
    s.particleClock=s.particleClock-interval;s.serial=s.serial+1
    local n=s.serial;local h1=(sin(n*12.9898)*43758.5453)%1
    local h2=(sin(n*78.233)*12345.6789)%1
    local px,py
    if analyzing then px=x+12+h1*(w-24);py=y+h-7-h2*8
    else px=mx+(h1-.5)*7;py=my+(h2-.5)*5 end
    local p=pool[#pool]
    if p then pool[#pool]=nil else p={} end
    p.x=px;p.y=py;p.age=0;p.life=analyzing and (.65+h1*.65) or (1.6+h1*1.2)
    p.vx=(h2-.5)*(analyzing and 15 or 7);p.vy=analyzing and (10+h1*14) or (6+h1*8);p.phase=h2*pi*2
    particles[#particles+1]=p
   end
  else s.particleClock=min(s.particleClock,.04) end
  for i=#particles,1,-1 do
   local p=particles[i];p.age=p.age+realDt
   if p.age>=p.life then table.remove(particles,i);pool[#pool+1]=p
   else
    local px=p.x+p.vx*p.age+sin(p.age*1.6+p.phase)*2;local py=p.y-p.vy*p.age
    local e=sin(pi*p.age/p.life)^2
    if px>x+3 and px<x+w-3 and py>y+3 and py<y+h-3 then
     d.disc(px,py,analyzing and 4.4 or 3.7,C.accent,(analyzing and .035 or .02)*e)
     d.disc(px,py,analyzing and 2.2 or 1.9,ice,(analyzing and .10 or .065)*e)
     d.disc(px,py,analyzing and .85 or .7,ice,(analyzing and .78 or .58)*e)
    end
   end
  end
 end
 -- All coordinates are host design units. Hit testing and actions stay with the host.
 function P.draw(d,x,y,w,h,title,caption,enabled,busy,progress,hover,pressed,now,active)
  local s=P.state;local C=d.C;local live=active~=false
  enabled=enabled~=false;busy=busy==true;hover=hover and enabled and live
  local dt=min(.1,max(0,now-(s.time or now)));s.time=now
  local target=(hover or busy) and 1 or 0
  s.hover=s.hover+(target-s.hover)*min(1,dt*14)
  if math.abs(target-s.hover)<.002 then s.hover=target end
  if s.busy and not busy then s.flashUntil=now+.45 end
  s.busy=busy;s.hot=hover;s.live=live
  local a=s.hover;local pulse=busy and live and (.5+.5*sin(now*5.2)) or 0
  local shift=pressed and enabled and 1.5 or 0;y=y+shift
  local deep=C.accent3 or C.deep;local ice=C.accent2 or C.ice
  local edge=(enabled or busy) and ice or C.muted
  -- LOUDNESS TRACE's glass face, lit top/left edges and diagonal corners.
  if enabled or busy then
   d.gradient(x,y,w,h,deep,C.field,.22+.12*a+(busy and .10*pulse or 0),.92)
   if a>.01 then d.gradient(x,y,w,h,C.accent,deep,busy and (.20+.10*pulse) or .13*a,.01,true) end
  else
   d.gradient(x,y,w,h,C.field,C.field,.92,.92)
  end
  d.gradient(x,y,w,busy and 2 or 1,edge,edge,(enabled or busy) and (.62+.28*a) or .18,.03)
  d.line(x,y+h,x+w,y+h,busy and ice or C.edge,busy and (.52+.20*pulse) or (enabled and .48 or .14))
  d.line(x,y,x,y+h,edge,(enabled or busy) and (.66+.18*pulse) or .13)
  d.corners(x,y,w,h,min(10,h/3),true,edge,(enabled or busy) and (.68+.18*pulse) or .18)
  local mx,my,speed=d.motion(now)
  s.emitting=busy or (hover and live and speed>0)
  P.drawParticles(d,s,x,y,w,h,hover,busy,dt,live and dt*speed or 0,mx,my)
  if s.flashUntil and now<s.flashUntil and live then
   local flash=((s.flashUntil-now)/.45)^2
   d.rect(x+1,y+1,w-2,h-2,ice,.07*flash)
   d.line(x,y,x+w,y,ice,.6*flash)
  end
  local top=caption or 'EXECUTE'
  if not enabled and not busy then top='WAIT' end
  if type(progress)=='number' then
   progress=max(0,min(1,progress))
   top=top..'  '..math.floor(progress*100+.5)..'%'
   d.rect(x+4,y+h-5,w-8,2,C.edge,.45)
   if progress>0 then d.rect(x+4,y+h-5,(w-8)*progress,2,ice,.8) end
  end
  -- Center the same two-line typography within each application's existing size.
  local topY=y+(h-42)/2+3
  d.label(top,x+10,topY,8,(enabled or busy) and ice or C.faint,3,w-20,12,5,false)
  d.label(title,x+10,topY+14,15,(enabled or busy) and C.text or C.muted,1,w-20,21,5,false)
 end
 function P.tick(now,active,wake)
  local s=P.state
  local tail=s.particles and #s.particles>0
  local fading=s.hover>.002 and s.hover<.998 or (not s.hot and not s.busy and s.hover>.002)
  if (tail or s.busy or (active and s.live and (s.emitting or fading or (s.flashUntil and now<s.flashUntil)))) and now>=P.nextFrame then
   P.nextFrame=now+(tail and not s.hot and not s.busy and 1/20 or 1/30);wake()
  end
 end
 return P
end)()

-- BLT shared shell 3.2.0. Embedded at build time; no runtime module dependency.
local BLT=(function()
local B={fitCache={},fitCount=0,metrics={},metricCount=0,slots={},nextSlot=1,specs={}}
local host,C,Chrome,Chameleon,scale,ox,oy
local R=reaper
local UI={}
local Layout={bar={height=26,close=38,reset=34,theme=34,language=26,preset=84,arrow=20},popup={width=292,headerHeight=36,rowHeight=29,visiblePresets=8,hoverDelay=1}}
local Presets={items={},revision=0}
local ids={1,2,3,4,5,6,8,9,10,11,12,13,14,15}
local function wake_visuals() if host then host.wake() end end
function B.copy(v)
 if type(v)~='table' then return v end
 local t={};for k,x in pairs(v) do t[k]=B.copy(x) end;return t
end
-- Typed, length-prefixed data. Never evaluate imported Lua or JSON-like code.
function B.pack(v)
 local t=type(v)
 if t=='boolean' then return v and 'b1' or 'b0' end
 if t=='string' or t=='number' then local s=tostring(v);return (t=='string' and 's' or 'n')..#s..':'..s end
 assert(t=='table','Unsupported preset value')
 local keys={};for k in pairs(v) do keys[#keys+1]=k end
 table.sort(keys,function(a,b)return tostring(a)<tostring(b) end)
 local p={'t'..#keys..':'};for _,k in ipairs(keys) do p[#p+1]=B.pack(k);p[#p+1]=B.pack(v[k]) end
 return table.concat(p)
end
function B.unpack(data)
 if type(data)~='string' or #data>BLTPresetLimits.bytes then return nil end
 local at,nodes=1,0;local capacity=false
 local function read(depth)
  nodes=nodes+1;if nodes>BLTPresetLimits.nodes then capacity=true;error("preset capacity") end;assert(depth<14)
  local tag=data:sub(at,at);at=at+1
  if tag=='b' then local v=data:sub(at,at);at=at+1;assert(v=='0' or v=='1');return v=='1' end
  assert(tag=='s' or tag=='n' or tag=='t')
  local finish=data:find(':',at,true);assert(finish and finish-at<9)
  local raw=data:sub(at,finish-1);assert(raw:match('^%d+$'));local n=tonumber(raw);at=finish+1
  if tag=='t' then
   if n>BLTPresetLimits.entries then capacity=true;error("preset capacity") end;local v={}
   for i=1,n do local k=read(depth+1);assert(type(k)=='string' or type(k)=='number');assert(v[k]==nil);v[k]=read(depth+1) end
   return v
  end
  if n>BLTPresetLimits.stringBytes then capacity=true;error("preset capacity") end;assert(at+n-1<=#data);local v=data:sub(at,at+n-1);at=at+n
  if tag=='n' then v=tonumber(v);assert(v and v==v and math.abs(v)<math.huge) end
  return v
 end
 local ok,v=pcall(read,0);if capacity then BLTPresetLimits.show(Language.code=='EN') end;if ok and at==#data+1 then return v end
end

function B.publicError(value,fallback)
 local text=tostring(value or '')
 text=text:match('^(.-)\nstack traceback:') or text
 text=text:gsub('\\','/')
 text=text:gsub('([^\r\n]+)',function(line)
  line=line:gsub('^%s*%[string .-%]:%d+:%s*','')
  line=line:gsub('^%s*.-:%d+:%s*','')
  line=line:gsub('^%s*[A-Za-z]:/[^:\r\n]+:%s*','')
  line=line:gsub('^%s*/[^:\r\n]+:%s*','')
  line=line:gsub('[A-Za-z]:/[^:\r\n"<>|]*','')
  line=line:gsub('//[^:\r\n"<>|]*','')
  line=line:gsub('%s/[^:\r\n"<>|]*','')
  line=line:gsub('[^%s:"<>|/]+/[^%s:"<>|]+','')
  line=line:gsub('[^%s:"<>|]+%.[%a][%w%-]*','')
  line=line:gsub('%s+:%s+',': ')
  return line:match('^%s*(.-)%s*$') or ''
 end)
 if text:match('^%s*$') then return fallback or '処理中にエラーが発生しました。' end
 return text
end
function B.same(a,b)
 if type(a)~=type(b) then return false end
 if type(a)~='table' then return a==b end
 for k,v in pairs(a) do if not B.same(v,b[k]) then return false end end
 for k in pairs(b) do if a[k]==nil then return false end end;return true
end
function B.shape(v,base)
 if type(v)~=type(base) then return false end
 if type(v)=='table' then
  if base[1]~=nil then
   if #v<1 or #v>4096 then return false end
   local count=0;for k,x in pairs(v) do if type(k)~='number' or k%1~=0 or k<1 or k>#v or not B.shape(x,base[1]) then return false end;count=count+1 end
   return count==#v
  end
  for k,x in pairs(base) do if not B.shape(v[k],x) then return false end end
  for k in pairs(v) do if base[k]==nil then return false end end
 elseif type(v)=='number' then return v==v and math.abs(v)<math.huge
 elseif type(v)=='string' then return #v<=8192 and utf8.len(v)~=nil and not v:find('%z') end
 return true
end
function B.viewport(viewScale,dpi)
 if B.viewScale==viewScale and B.dpi==dpi then return end
 B.slots={};B.nextSlot=1;B.fontKey=nil;B.scratch=nil
 if B.dpi~=dpi then B.metrics={};B.metricCount=0;B.fitCache={};B.fitCount=0;B.chromeDPI=nil end
 B.viewScale,B.dpi=viewScale,dpi
end
function B.spec(size,kind,bold,s)
 kind=kind or 1;local px=math.max(8,math.floor((size or 10)*s+.5));local weight=bold and 98 or 0
 local g=kind*2+(bold and 1 or 0);local sizes=B.specs[g]
 if not sizes then sizes={};B.specs[g]=sizes end
 local r=sizes[px];if not r then r={kind,px,weight,kind..':'..px..':'..weight};sizes[px]=r end
 return r[1],r[2],r[3],r[4]
end
function B.font(size,kind,bold,s,faces)
 local k,px,weight,key=B.spec(size,kind,bold,s)
 local face=faces[k] or faces[1]
 B.faceKeys=B.faceKeys or {};local family=B.faceKeys[face]
 if not family then family={};B.faceKeys[face]=family end
 local style=px*2+(bold and 1 or 0)
 key=family[style]
 if not key then key=face..':'..px..':'..weight;family[style]=key end
 if B.fontKey==key then return end
 local slot=B.slots[key]
 if slot then gfx.setfont(slot)
 elseif B.nextSlot<=#ids then slot=ids[B.nextSlot];B.nextSlot=B.nextSlot+1;B.slots[key]=slot;gfx.setfont(slot,face,px,weight)
 elseif B.scratch==key then gfx.setfont(16)
 else gfx.setfont(16,face,px,weight);B.scratch=key end
 B.fontKey=key
end
function B.chromeFont()
 if B.chromeDPI~=(gfx.ext_retina or 1) then gfx.setfont(7,Chrome.font,10,0);B.chromeDPI=gfx.ext_retina or 1 else gfx.setfont(7) end
 B.fontKey='chrome'
end
function UI.textMetrics(text)
 local key=B.fontKey or 'chrome';local bucket=B.metrics[key];local r=bucket and bucket[text]
 if r then return r[1],r[2] end
 local w,h=gfx.measurestr(text)
 if B.metricCount>=2048 then B.metrics={};B.metricCount=0;bucket=nil end
 if not bucket then bucket={};B.metrics[key]=bucket end
 bucket[text]={w,h};B.metricCount=B.metricCount+1;return w,h
end
B.metricsFor=UI.textMetrics
local function font(size,kind,bold) host.font(size,kind,bold) end
function B.position(hwnd,x,y,w,h,a,b)
 local old=B.lastRect
 if old and old[1]==hwnd and old[2]==x and old[3]==y and old[4]==w and old[5]==h then return true end
 local ok,l,t,r,bt=WindowGeometry.JS_Window_GetRect(hwnd)
 if ok and l==x and t==y and r-l==w and bt-t==h then B.lastRect={hwnd,x,y,w,h};return true end
 local done=WindowGeometry.JS_Window_SetPosition(hwnd,x,y,w,h,a,b)
 if done then B.lastRect={hwnd,x,y,w,h} end;return done
end
function B.store(section,key,value,persist)
 local encoded=tostring(value)
 B.saved=B.saved or {};local cache=B.saved[section]
 if not cache then cache={};B.saved[section]=cache end
 if cache[key]==nil then cache[key]=R.GetExtState(section,key) end
 if cache[key]~=encoded then R.SetExtState(section,key,encoded,persist);cache[key]=encoded end
end
local function notice(text,ok) B.notice=ok and text or B.publicError(text);B.noticeUntil=R.time_precise()+7;B.noticeBad=not ok;wake_visuals() end
function Presets.name(s)
 s=tostring(s or ''):match('^%s*(.-)%s*$')
 if s=='' or #s>120 or not utf8.len(s) or s:find('[%z\1-\31\127|<>!#]') then return nil end;return s
end
function Presets.isFactory(p) return p and (p.factory or p.name=='ファクトリーデフォルト') end
function Presets.encode(p) return host.section..'_PRESET_V1\n'..B.pack({name=p.name,values=p.values}) end
function Presets.decode(data)
 local prefix=host.section..'_PRESET_V1\n'
 if data:sub(1,#prefix)~=prefix then return nil end
 local p=B.unpack(data:sub(#prefix+1))
 if type(p)~='table' or not Presets.name(p.name) or not B.shape(p.values,host.defaults) or not host.valid(p.values) then return nil end
 return p
end
function Presets.capture(name)
 if not host.commit() then return nil end
 local values=host.capture()
 if not B.shape(values,host.defaults) or not host.valid(values) then return nil end
 return {name=name,values=B.copy(values)}
end
function Presets.dirty()
 if not Presets.current then return false end
 -- Whitelisted views are reused; never serialize settings in the draw path.
 return not B.same(host.capture(),Presets.current.values)
end
function Presets.flush()
 Presets.revision=Presets.revision+1
 B.store(host.section,'preset_count',#Presets.items,true)
 for i,p in ipairs(Presets.items) do B.store(host.section,'preset_'..i,Presets.encode(p):gsub('%%','%%25'):gsub('\n','%%0A'):gsub('\r','%%0D'),true) end
end
function Presets.put(p)
 if Presets.isFactory(p) then notice('ファクトリーデフォルトは変更できません。',false);return false end
 for i,v in ipairs(Presets.items) do if v.name==p.name then
  if Language.mb('「'..p.name..'」を上書きしますか？','PRESET',4)~=6 then return false end
  Presets.items[i]=p;Presets.flush();return true
 end end
 if #Presets.items>=200 then notice('プリセットは200個まで保存できます。',false);return false end
 Presets.items[#Presets.items+1]=p;table.sort(Presets.items,function(a,b)return a.name<b.name end);Presets.flush();return true
end
function Presets.save(asNew)
 if host.busy() then return end
 if not asNew and Presets.isFactory(Presets.current) then return end
 local name=Presets.current and not Presets.isFactory(Presets.current) and Presets.current.name or ''
 if asNew or name=='' then
  local ok,s=Language.input('名前を付けて保存',1,'プリセット名:',name);if not ok then return end
  name=Presets.name(s);if not name then notice('有効なプリセット名を入力してください。',false);return end
 end
 local p=Presets.capture(name);if not p then notice('設定値を確認してください。',false);return end
 if Presets.put(p) then Presets.current=p;notice('プリセットを保存しました: '..name,true) end
end
function Presets.apply(p)
 if host.busy() or not host.commit() then return end
 if Presets.dirty() and Language.mb('未保存の変更を破棄して読み込みますか？','PRESET',4)~=6 then return end
 host.cancelEdit();host.apply(B.copy(p.values));B.presetRevision=(B.presetRevision or 0)+1;B.presetMotionSeen={};Presets.current=p;wake_visuals();notice('プリセットを読み込みました: '..p.name,true)
end
function Presets.step(d)
 local n=1
 if Presets.current then
  if not Presets.isFactory(Presets.current) then for i,p in ipairs(Presets.items) do if p.name==Presets.current.name then n=i+1;break end end end
  n=(n-1+d)%(#Presets.items+1)+1
 end
 Presets.apply(n==1 and Presets.factory or Presets.items[n-1])
end
function Presets.encodeBundle(items)
 local rows={};local size=128;for _,p in ipairs(items) do local row=Presets.encode(p);size=size+#row+32;if size>BLTPresetLimits.bytes then BLTPresetLimits.show(Language.code=='EN');return end;rows[#rows+1]=row end
 return host.section..'_PRESET_BUNDLE_V1\n'..B.pack(rows)
end
function Presets.decodeTransfer(data)
 if type(data)~='string' or #data>BLTPresetLimits.bytes then return nil end
 local p=Presets.decode(data);if p then return not Presets.isFactory(p) and {p} or nil end
 local prefix=host.section..'_PRESET_BUNDLE_V1\n';if data:sub(1,#prefix)~=prefix then return nil end
 local rows=B.unpack(data:sub(#prefix+1));if type(rows)~='table' or #rows<1 or #rows>200 then return nil end
 local result,names={},{};local count=0
 for k in pairs(rows) do if type(k)~='number' or k%1~=0 or k<1 or k>#rows then return nil end;count=count+1 end
 if count~=#rows then return nil end
 for _,row in ipairs(rows) do
  if type(row)~='string' then return nil end;local v=Presets.decode(row)
  if not v or Presets.isFactory(v) or names[v.name] then return nil end
  result[#result+1]=v;names[v.name]=true
 end;return result
end
function Presets.import()
 local ok,path=Language.open('','プリセットをインポート（個別／一覧）','bltpreset');if not ok then return end
 local f=io.open(path,'rb');if not f then notice('ファイルを開けません。',false);return end
 local data=f:read(BLTPresetLimits.bytes+1);f:close();if #data>BLTPresetLimits.bytes then BLTPresetLimits.show(Language.code=='EN');return end;local items=Presets.decodeTransfer(data)
 if not items then notice('このアプリ用の有効なプリセットではありません。',false);return end
 local merged,index={},{};for i,p in ipairs(Presets.items) do merged[i]=p;index[p.name]=i end
 local conflicts=0
 for _,p in ipairs(items) do if index[p.name] then conflicts=conflicts+1;merged[index[p.name]]=p else merged[#merged+1]=p;index[p.name]=#merged end end
 if #merged>200 then notice('プリセットが200個を超えます。',false);return end
 if conflicts>0 and Language.mb('同名のプリセットを上書きして取り込みますか？','PRESET',4)~=6 then return end
 table.sort(merged,function(a,b)return a.name<b.name end);Presets.items=merged;Presets.flush();notice(#items..'個インポートしました。',true)
end
function Presets.export(all)
 local data,file
 if all then if #Presets.items==0 then return end;data=Presets.encodeBundle(Presets.items);file=host.section..'_presets.bltpreset'
 else
  if Presets.isFactory(Presets.current) then return end
  local p=Presets.capture(Presets.current and Presets.current.name or '現在値');if not p then notice('設定値を確認してください。',false);return end
  data=Presets.encode(p);file=p.name:gsub('[\\/:*?"<>|]','_')..'.bltpreset'
 end
 if not data then return end;if #data>BLTPresetLimits.bytes then BLTPresetLimits.show(Language.code=='EN');return end
 local title=all and 'プリセット一覧をエクスポート' or '現在値をエクスポート'
 local ok,path
 if R.JS_Dialog_BrowseForSaveFile then ok,path=Language.save(title,'',file,'BLT Preset (*.bltpreset)\0*.bltpreset\0')
 else ok,path=Language.input(title,1,'保存先のフルパス:',R.GetResourcePath()..'/'..file) end
 if not ok or ok==0 or not path or path=='' then return end
 if not path:lower():match('%.bltpreset$') then path=path..'.bltpreset' end
 local old=io.open(path,'rb');if old then old:close();if Language.mb('保存先のファイルを上書きしますか？','PRESET',4)~=6 then return end end
 local f,err=io.open(path,'wb');if not f then notice(B.publicError(err),false);return end
 local wrote,werr=f:write(data);local closed,cerr=f:close();notice(wrote and closed and 'エクスポートしました。' or B.publicError(werr or cerr),wrote and closed)
end
function UI.bar(w)
 local compact=host.compactChrome and host.compactChrome() or false
 local c=B.barCache;if c and c.width==w and c.compact==compact then return c end
 local b={width=w,closeX=w-38,resetX=w-72,themeX=w-106}
 b.foldX=host.fold and b.themeX-34 or nil;b.languageX=(b.foldX or b.themeX)-26;b.nextX=b.languageX-20;b.prevX=b.nextX-20;b.presetX=b.prevX-84
 b.compact=compact
 if compact then b.resetX=b.closeX;b.themeX=w-72;b.foldX=w-106;b.languageX=w+500;b.nextX=w+500;b.prevX=w+500;b.presetX=w+500 end
 B.barCache=b;return b
end
local function gfx_window_handle() return host.handle() end
local function chrome_resize_hit(x,y) if y<26 and x>=UI.bar(gfx.w).presetX then return nil end;return host.resizeHit(x,y) end
local function set_resize_cursor(mode) host.cursor(mode) end
local function begin_window_resize(mode) host.beginResize(mode) end
local function update_window_resize() host.resize() end
local function clear_chrome_tooltip() B.popupUntil=nil;if R.TrackCtl_SetToolTip then R.TrackCtl_SetToolTip('',0,0,true) end end
B.clearTooltip=clear_chrome_tooltip
-- Non-modal dependency hint. Uses the existing tick, with no extra defer loop.


function B.switch(x,y,state,enabled)
 local s,bx,by=host.geometry();local cy=by+(y+12)*s;local cx=bx+(x+7+12*state)*s
 local c=C.edge2;gfx.set(c[1],c[2],c[3],enabled and .45 or .2);gfx.line(bx+(x+3)*s,cy,bx+(x+23)*s,cy,1)
 c=C.faint;gfx.set(c[1],c[2],c[3],enabled and .8 or .4);gfx.circle(cx,cy,4.2*s,1,1)
 if state>.001 and enabled then c=C.accent;gfx.set(c[1],c[2],c[3],.06*state);gfx.circle(cx,cy,7*s,1,1);c=C.accent2;gfx.set(c[1],c[2],c[3],.94*state);gfx.circle(cx,cy,4.2*s,1,1) end
end
function B.blend(dt)
 if B.blendDt~=dt then B.blendDt=dt;B.blendValue=1-math.exp(-12*dt) end
 return B.blendValue
end
function Presets.menu(x,y)
  if host.prepareMenu and not host.prepareMenu() then wake_visuals();return end
  Presets.open=true;Presets.page="main";Presets.offset=0;Presets.selected=1
  Presets.down=false;Presets.pressed=nil;Presets.mx=nil;Presets.my=nil;Presets.hoverSince=nil
  host.cancelEdit();wake_visuals()
end
function Presets.dismiss()
  Presets.swallow=((gfx.mouse_cap or 0)&1)~=0
  Presets.open=false;Presets.hoverSince=nil;Presets.pressed=nil;host.cancelEdit();wake_visuals()
end
function Presets.buildRows()
  if Presets.page=="load" then
    local rows={{text="戻る",icon="back",action=function() Presets.page="main";Presets.selected=1 end}}
    local count=math.min(Layout.popup.visiblePresets,#Presets.items-Presets.offset)
    for i=1,count do
      local p=Presets.items[i+Presets.offset]
      rows[#rows+1]={text=p.name,literal=true,icon=Presets.current and Presets.current.name==p.name and "check" or "cards",action=function() Presets.dismiss();Presets.apply(p) end}
    end
    return rows
  end
  return {
    {text=Presets.factory.name,icon=Presets.isFactory(Presets.current) and "check" or "cards",action=function() Presets.dismiss();Presets.apply(Presets.factory) end},
    {text="プリセット",disabled=#Presets.items==0,icon="folder",arrow=true,action=function() Presets.page="load";Presets.offset=0;Presets.selected=nil;Presets.hoverSince=nil;Presets.pressed=nil end},
    {text="上書き保存",icon="save",disabled=Presets.isFactory(Presets.current),action=function() Presets.dismiss();Presets.save(false) end},
    {text="名前を付けて保存…",icon="plus",action=function() Presets.dismiss();Presets.save(true) end},
    {text="インポート…",icon="import",gap=true,action=function() Presets.dismiss();Presets.import() end},
    {text="現在値をエクスポート",icon="export",disabled=Presets.isFactory(Presets.current),action=function() Presets.dismiss();Presets.export(false) end},
    {text="プリセット一覧をエクスポート",icon="export",disabled=#Presets.items==0,action=function() Presets.dismiss();Presets.export(true) end},
  }
end
function Presets.rows()
  local c=Presets.rowCache
  local current=Presets.current and Presets.current.name or ""
  if c and c.page==Presets.page and c.offset==Presets.offset and c.items==Presets.items
    and c.count==#Presets.items and c.revision==Presets.revision and c.current==current then return c.rows end
  local rows=Presets.buildRows()
  Presets.rowCache={page=Presets.page,offset=Presets.offset,items=Presets.items,count=#Presets.items,
    revision=Presets.revision,current=current,rows=rows}
  return rows
end
function Presets.layout()
  local rows=Presets.rows()
  local cached=Presets.layoutCache
  if cached and cached.rows==rows and cached.windowWidth==gfx.w then return cached.x,cached.y,cached.w,cached.h,rows end
  local w=math.min(Layout.popup.width,gfx.w-12)
  local x=math.max(6,gfx.w-w-6);local y=Chrome.titleH+2
  local top=y+Layout.popup.headerHeight
  for _,r in ipairs(rows) do if r.gap then top=top+9 end;r.y=top;top=top+Layout.popup.rowHeight end
  local h=top-y+8+(Presets.page=="load" and #Presets.items>Layout.popup.visiblePresets and 18 or 0)
  Presets.layoutCache={rows=rows,windowWidth=gfx.w,x=x,y=y,w=w,h=h}
  return x,y,w,h,rows
end
function Presets.activate(i)
  local rows=Presets.rows();local row=rows[i]
  if row and not row.disabled then row.action();wake_visuals() end
end
function Presets.key(k)
  if k==27 then Presets.dismiss()
  elseif k==13 then Presets.activate(Presets.selected or 1)
  elseif k==1818584692 and Presets.page=="load" then Presets.page="main";Presets.selected=1
  elseif k==30064 or k==1685026670 then
    local delta=k==30064 and -1 or 1
    local rows=Presets.rows();local n=(Presets.selected or 1)+delta
    if Presets.page=="load" and n>#rows and Presets.offset+Layout.popup.visiblePresets<#Presets.items then Presets.offset=Presets.offset+1;n=#rows
    elseif Presets.page=="load" and n<2 and Presets.offset>0 then Presets.offset=Presets.offset-1;n=2 end
    Presets.selected=math.max(1,math.min(#rows,n))
  end
  wake_visuals()
end
function Presets.update(active)
  if Presets.swallow and ((gfx.mouse_cap or 0)&1)==0 then Presets.swallow=false end
  if not Presets.open then return end
  if not active then Presets.dismiss();return end
  local x,y,w,h,rows=Presets.layout()
  local mx,my=gfx.mouse_x,gfx.mouse_y;local down=(gfx.mouse_cap&1)~=0
  local inside=mx>=x and mx<x+w and my>=y and my<y+h
  local hit=nil
  if inside then for i,r in ipairs(rows) do if my>=r.y and my<r.y+Layout.popup.rowHeight then hit=i end end end
  if mx~=Presets.mx or my~=Presets.my then Presets.selected=hit;Presets.mx=mx;Presets.my=my end
  local wheel=gfx.mouse_wheel or 0
  if wheel~=0 then
    if inside and Presets.page=="load" then Presets.offset=math.max(0,math.min(math.max(0,#Presets.items-Layout.popup.visiblePresets),Presets.offset+(wheel>0 and -1 or 1)));Presets.selected=nil end
    gfx.mouse_wheel=0
  end
  -- Hover only opens the preset list, never applies a preset automatically.
  if Presets.page=="main" and hit==2 and #Presets.items>0 and not down then
    Presets.hoverSince=Presets.hoverSince or R.time_precise()
    if R.time_precise()-Presets.hoverSince>=Layout.popup.hoverDelay then Presets.activate(2);Presets.down=down;return end
  else Presets.hoverSince=nil end
  if down and not Presets.down then
    if not inside then Presets.dismiss() else Presets.pressed=hit end
  elseif not down and Presets.down then
    if hit and hit==Presets.pressed then Presets.activate(hit) end
    Presets.pressed=nil
  end
  Presets.down=down
end
function Presets.icon(kind,x,y)
  local function l(a,b,c,d) gfx.line(x+a,y+b,x+c,y+d,1) end
  local function box(a,b,w,h) gfx.roundrect(x+a,y+b,w,h,1,1) end
  if kind=="cards" then box(0,0,8,9);box(3,3,8,9)
  elseif kind=="folder" then l(0,2,4,2);l(4,2,6,4);l(6,4,12,4);l(12,4,12,12);l(12,12,0,12);l(0,12,0,2)
  elseif kind=="save" or kind=="plus" then
    box(0,0,12,12);box(3,0,5,4);box(3,7,6,5)
    if kind=="plus" then l(10,6,10,12);l(7,9,13,9) end
  elseif kind=="import" or kind=="export" then
    l(0,9,0,13);l(0,13,12,13);l(12,13,12,9)
    if kind=="import" then l(6,0,6,9);l(2,5,6,9);l(6,9,10,5)
    else l(6,9,6,0);l(2,4,6,0);l(6,0,10,4) end
  elseif kind=="check" then l(0,6,4,10);l(4,10,12,1)
  elseif kind=="back" then l(11,6,0,6);l(0,6,4,2);l(0,6,4,10) end
end
function UI.fit(text,width)
  local key=B.fontKey or "chrome"
  local bucket=B.fitCache[key];local cached=bucket and bucket[text]
  if cached and cached.width==width then return cached.text end
  local shown=text
  if UI.textMetrics(text)>width then
    if UI.textMetrics("…")>width then shown=""
    else
      local count=utf8.len(text)
      local valid=text
      if not count then valid=text:gsub("[\128-\255]","?");count=#valid end
      local low,high=0,count
      while low<high do
        local mid=math.floor((low+high+1)/2)
        local stop=utf8.offset(valid,mid+1) or (#valid+1)
        if UI.textMetrics(valid:sub(1,stop-1).."…")<=width then low=mid else high=mid-1 end
      end
      local stop=utf8.offset(valid,low+1) or (#valid+1)
      shown=valid:sub(1,stop-1).."…"
    end
  end
  if B.fitCount>=512 then B.fitCache={};B.fitCount=0;bucket=nil end
  if not bucket then bucket={};B.fitCache[key]=bucket end
  if not bucket[text] then B.fitCount=B.fitCount+1 end
  bucket[text]={width=width,text=shown}
  return shown
end
function Presets.draw()
  if not Presets.open then return end
  local x,y,w,h,rows=Presets.layout()
  gfx.set(0,0,0,.22);gfx.rect(x+3,y+4,w,h,1)
  gfx.set(C.panel[1],C.panel[2],C.panel[3],1);gfx.rect(x,y,w,h,1)
  gfx.set(C.edge2[1],C.edge2[2],C.edge2[3],.65);gfx.roundrect(x,y,w,h,3,1)
  font(12/scale,4,false)
  gfx.set(C.muted[1],C.muted[2],C.muted[3],.9);gfx.x=x+12;gfx.y=y+9
  local title=Presets.page=="load" and Language.text("プリセット") or (Language.text("現在: ")..(Presets.current and (Presets.isFactory(Presets.current) and Language.text(Presets.current.name) or Presets.current.name) or Language.text("未選択"))..(Presets.dirty() and " *" or ""))
  gfx.drawstr(UI.fit(title,w-24))
  gfx.set(C.edge[1],C.edge[2],C.edge[3],.65);gfx.line(x+10,y+30,x+w-10,y+30)
  font(13/scale,4,false)
  for i,r in ipairs(rows) do
    if r.gap then gfx.set(C.edge[1],C.edge[2],C.edge[3],.65);gfx.line(x+10,r.y-5,x+w-10,r.y-5) end
    if i==Presets.selected and not r.disabled then
      gfx.set(Chrome.mint[1],Chrome.mint[2],Chrome.mint[3],.18);gfx.rect(x+1,r.y,w-2,Layout.popup.rowHeight,1)
      gfx.set(Chrome.mint[1],Chrome.mint[2],Chrome.mint[3],.8);gfx.rect(x+1,r.y,2,Layout.popup.rowHeight,1)
    end
    gfx.set(C.text[1],C.text[2],C.text[3],r.disabled and .3 or .94)
    Presets.icon(r.icon,x+13,r.y+8)
    gfx.x=x+39;gfx.y=r.y+7;gfx.drawstr(UI.fit(r.literal and r.text or Language.text(r.text),w-65))
    if r.arrow then gfx.line(x+w-18,r.y+10,x+w-14,r.y+14);gfx.line(x+w-14,r.y+14,x+w-18,r.y+18) end
  end
  if Presets.page=="load" and #Presets.items>Layout.popup.visiblePresets then
    font(10/scale,4,false)
    gfx.set(C.muted[1],C.muted[2],C.muted[3],.8);gfx.x=x+12;gfx.y=y+h-19
    gfx.drawstr(string.format(Language.text("%d–%d / %d   スクロールで選択"),Presets.offset+1,math.min(Presets.offset+Layout.popup.visiblePresets,#Presets.items),#Presets.items))
  end
end

local function custom_titlebar(blocked)
  local w=gfx.w
  local mx,my=gfx.mouse_x,gfx.mouse_y
  local b=UI.bar(w)
  local closeW,resetW,chamW=Layout.bar.close,Layout.bar.reset,Layout.bar.theme
  local closeX,resetX,chamX=b.closeX,b.resetX,b.themeX
  local languageX=b.languageX
  local presetX=b.presetX
  local foldX=b.foldX
  local prevX,nextX=b.prevX,b.nextX
  local inWindow=mx>=0 and mx<w and my>=0 and my<gfx.h
  local inBar=host.active() and not blocked and inWindow and my<Chrome.titleH
  local resizeMode=not blocked and chrome_resize_hit(mx,my) or nil
  local resizing=Chrome.resize~=nil
  local cursorMode=resizing and Chrome.resize.mode or resizeMode
  set_resize_cursor(cursorMode)
  local hoverClose=inBar and mx>=closeX and mx<w and not resizeMode and not resizing
  local hoverReset=not (host.collapsed and host.collapsed()) and not (host.transition and host.transition()) and inBar and mx>=resetX and mx<closeX and not resizeMode and not resizing
  local hoverCham=inBar and mx>=chamX and mx<resetX and not resizeMode and not resizing
  local hoverPreset=inBar and mx>=presetX and mx<prevX and not resizeMode and not resizing
  local hoverPrev=inBar and mx>=prevX and mx<nextX and not resizeMode and not resizing
  local hoverNext=inBar and mx>=nextX and mx<languageX and not resizeMode and not resizing
  local hoverFold=foldX and not (host.transition and host.transition()) and inBar and mx>=foldX and mx<chamX and not resizeMode and not resizing
  local hoverLanguage=inBar and mx>=languageX and mx<(foldX or chamX) and not resizeMode and not resizing
  local down=not blocked and (gfx.mouse_cap&1)~=0
  -- A content modal disables chrome; it does not give chrome ownership of its input.
  Chrome.mouseActive=(Presets.open or Presets.swallow) or inBar or Chrome.drag~=nil or Chrome.resize~=nil or cursorMode~=nil
    or Chrome.languagePressed or Chrome.closePressed or Chrome.resetPressed or Chrome.chameleonPressed or Chrome.presetPressed or Chrome.presetPrevPressed or Chrome.presetNextPressed

  gfx.set(C.bg[1],C.bg[2],C.bg[3],1); gfx.rect(0,0,w,Chrome.titleH,1)
  gfx.gradrect(0,0,w,Chrome.titleH,C.field[1],C.field[2],C.field[3],.72,
    0,0,0,0,(C.bg[1]-C.field[1])/Chrome.titleH,(C.bg[2]-C.field[2])/Chrome.titleH,(C.bg[3]-C.field[3])/Chrome.titleH,.22/Chrome.titleH)
  gfx.set(C.edge[1],C.edge[2],C.edge[3],.42); gfx.line(0,Chrome.titleH-1,w,Chrome.titleH-1,1)

  if not Chrome.textFontsReady or Chrome.fontDPI~=(gfx.ext_retina or 1) then Chrome.fontDPI=gfx.ext_retina or 1;B.chromeFont(); Chrome.textFontsReady=true else B.chromeFont() end; B.fontKey="chrome"
  -- Center the unadorned title within the bar using the actual font height.
  local _,titleHeight=UI.textMetrics(Chrome.titleText)
  local ty=math.floor((Chrome.titleH-titleHeight)*.5)
  gfx.set(Chrome.mint[1],Chrome.mint[2],Chrome.mint[3],.88); gfx.x=14; gfx.y=ty; gfx.drawstr(UI.fit(Chrome.titleText,math.max(0,(b.compact and b.foldX or presetX)-22)))

  if not b.compact then
  if hoverPreset or Presets.open then
    gfx.set(C.accent[1],C.accent[2],C.accent[3],.10);gfx.rect(presetX+2,3,78,20,1)
  end
  gfx.set(C.edge[1],C.edge[2],C.edge[3],(hoverPreset or hoverPrev or hoverNext) and .9 or .5)
  gfx.roundrect(presetX+2,3,languageX-presetX-5,20,3,1)
  gfx.set(C.muted[1],C.muted[2],C.muted[3],.35);gfx.line(languageX-1,6,languageX-1,20)
  local pc=hoverPreset and Chrome.mint or C.muted
  gfx.set(pc[1],pc[2],pc[3],hoverPreset and .98 or .8)
  gfx.roundrect(presetX+10,7,7,8,1,1);gfx.roundrect(presetX+13,10,7,8,1,1)
  B.chromeFont();B.fontKey="chrome"
  gfx.x=presetX+26;gfx.y=7;gfx.drawstr("PRESET")
  gfx.line(presetX+67,11,presetX+70,14);gfx.line(presetX+70,14,presetX+73,11)
  if Presets.dirty() then gfx.set(C.warn[1],C.warn[2],C.warn[3],.9);gfx.circle(presetX+23,6,1.3,1,1) end

  B.arrows=B.arrows or {{},{}}
  local left,right=B.arrows[1],B.arrows[2]
  left[1],left[2],left[3]=prevX,hoverPrev,-1;right[1],right[2],right[3]=nextX,hoverNext,1
  for _,arrow in ipairs(B.arrows) do
    local ax,hover,direction=arrow[1],arrow[2],arrow[3]
    if hover then
      gfx.set(Chrome.mint[1],Chrome.mint[2],Chrome.mint[3],.09);gfx.rect(ax+1,3,18,20,1)
    end
    local c=hover and Chrome.mint or C.muted
    gfx.set(c[1],c[2],c[3],hover and .98 or .8)
    local cx,cy=ax+10,Chrome.titleH*.5
    gfx.line(cx-direction*2,cy-4,cx+direction*2,cy,1)
    gfx.line(cx+direction*2,cy,cx-direction*2,cy+4,1)
  end

  local lc=hoverLanguage and Chrome.mint or C.text
  gfx.set(lc[1],lc[2],lc[3],hoverLanguage and 1 or .95)
  B.font(13,2,true,1,host.faces)
  local lw,lh=UI.textMetrics(Language.code)
  gfx.x=languageX+(26-lw)/2;gfx.y=(Chrome.titleH-lh)/2;gfx.drawstr(Language.code)
  end -- full-size preset and language controls
  if foldX then
    gfx.set(C.accent2[1],C.accent2[2],C.accent2[3],hoverFold and .98 or .8)
    local cx,cy=foldX+17,13;local d=host.collapsed() and 1 or -1
    gfx.line(cx-6,cy-5,cx+6,cy-5);gfx.line(cx-4,cy-d*3,cx,cy+d);gfx.line(cx,cy+d,cx+4,cy-d*3)
  end
  if hoverCham or Chameleon.enabled then
    local a=hoverCham and .095 or .045
    gfx.set(C.accent[1],C.accent[2],C.accent[3],a); gfx.rect(chamX,0,chamW,Chrome.titleH,1)
    gfx.set(C.accent2[1],C.accent2[2],C.accent2[3],hoverCham and .42 or .24)
    gfx.line(chamX,Chrome.titleH-1,resetX,Chrome.titleH-1,1)
  end
  local chx,chy=chamX+chamW*.5,Chrome.titleH*.5
  local active_a=hoverCham and 1 or (Chameleon.enabled and .96 or .85)

  -- Theme / mimicry icon:
  -- three overlapping color fields, visually reading as "take on / blend into
  -- surrounding colors" rather than as a literal animal.
  local c1,c2,c3=Chameleon.icon_colors()

  gfx.set(c1[1],c1[2],c1[3],active_a)
  gfx.circle(chx-3.5,chy+2,4.5,1,1)

  gfx.set(c2[1],c2[2],c2[3],active_a*.92)
  gfx.circle(chx+3.5,chy+2,4.5,1,1)

  gfx.set(c3[1],c3[2],c3[3],active_a*.94)
  gfx.circle(chx,chy-3.3,4.5,1,1)

  if not b.compact then
  if hoverReset then
    gfx.set(Chrome.mint[1],Chrome.mint[2],Chrome.mint[3],.050); gfx.rect(resetX,0,resetW,Chrome.titleH,1)
    gfx.set(Chrome.mint[1],Chrome.mint[2],Chrome.mint[3],.34); gfx.line(resetX,Chrome.titleH-1,closeX,Chrome.titleH-1,1)
  end
  local rcx,rcy=resetX+resetW*.5,Chrome.titleH*.5
  local rcol=hoverReset and Chrome.mint or C.muted
  gfx.set(rcol[1],rcol[2],rcol[3],hoverReset and .98 or .82)
  gfx.roundrect(rcx-6,rcy-6,12,12,1,1)
  gfx.line(rcx+3,rcy-3,rcx-3,rcy+3,1)
  gfx.line(rcx-3,rcy+3,rcx-3,rcy-1,1)
  gfx.line(rcx-3,rcy+3,rcx+1,rcy+3,1)

  end -- full-size reset control
  if hoverClose then
    gfx.set(Chrome.red[1],Chrome.red[2],Chrome.red[3],.10); gfx.rect(closeX,0,closeW,Chrome.titleH,1)
    gfx.set(Chrome.red[1],Chrome.red[2],Chrome.red[3],.56); gfx.line(closeX,Chrome.titleH-1,w,Chrome.titleH-1,1)
  end
  local xc=hoverClose and Chrome.red or C.muted
  local xa=hoverClose and .98 or .82
  local cx,cy=closeX+closeW*.5,Chrome.titleH*.5
  gfx.set(xc[1],xc[2],xc[3],xa)
  gfx.line(cx-4.6,cy-4.6,cx+4.6,cy+4.6,1); gfx.line(cx+4.6,cy-4.6,cx-4.6,cy+4.6,1)

  if down and not Chrome.mouseDown then
    if resizeMode then
      begin_window_resize(resizeMode)
    elseif hoverClose then
      Chrome.closePressed=true
    elseif hoverReset then
      Chrome.resetPressed=true
    elseif hoverPrev then
      Chrome.presetPrevPressed=true
    elseif hoverNext then
      Chrome.presetNextPressed=true
    elseif hoverPreset then
      Chrome.presetPressed=true
    elseif hoverLanguage then
      Chrome.languagePressed=true
    elseif hoverFold then
      Chrome.foldPressed=true
    elseif hoverCham then
      Chrome.chameleonPressed=true
    elseif inBar and not (host.transition and host.transition()) then
      local hwnd=gfx_window_handle()
      if hwnd then
        local ok,l,t,r,b=WindowGeometry.JS_Window_GetRect(hwnd)
        if ok then
          local sx,sy=WindowGeometry.GetMousePosition()
          Chrome.drag={mouseX=sx,mouseY=sy,left=l,top=t,width=r-l,height=b-t,lastX=l,lastY=t}
        end
      end
    end
  end

  if down and Chrome.resize then update_window_resize() end
  if down and Chrome.drag and not Chrome.resize then
    local d=Chrome.drag;local sx,sy=WindowGeometry.GetMousePosition()
    local x,y=d.left+(sx-d.mouseX),d.top+(sy-d.mouseY)
    local hwnd=(x~=d.lastX or y~=d.lastY) and gfx_window_handle() or nil
    if hwnd and B.position(hwnd,x,y,d.width,d.height,"","") then
      d.lastX,d.lastY=x,y;Chrome.geometryDirty=true
    end
  end

  if not down and Chrome.mouseDown then
    if Chrome.languagePressed and hoverLanguage then B.toggleLanguage() end
    Chrome.languagePressed=false
    if Chrome.closePressed and hoverClose then Chrome.requestClose=true end
    if Chrome.resetPressed and hoverReset then Chrome.requestReset=true end
    if Chrome.foldPressed and hoverFold then host.fold() end;Chrome.foldPressed=false
    if Chrome.chameleonPressed and hoverCham then Chameleon.set(not Chameleon.enabled) end
    if Chrome.presetPressed and hoverPreset then
      clear_chrome_tooltip();Presets.menu(presetX,Chrome.titleH)
    end
    if Chrome.presetPrevPressed and hoverPrev then clear_chrome_tooltip();Presets.step(-1) end
    if Chrome.presetNextPressed and hoverNext then clear_chrome_tooltip();Presets.step(1) end
    Chrome.presetPrevPressed=false;Chrome.presetNextPressed=false
    Chrome.presetPressed=false
    Chrome.closePressed=false; Chrome.resetPressed=false; Chrome.chameleonPressed=false
    Chrome.drag=nil; Chrome.resize=nil
  end
  Chrome.mouseDown=down
end

function B.toggleLanguage()
 if Language.set(Language.code=='JP' and 'EN' or 'JP') then
  clear_chrome_tooltip();B.tip=nil;B.tipVisible=false
  wake_visuals()
 end
end
function B.attach(h)
 host=h;R=h.R;C=h.C;Chrome=h.Chrome;Chameleon=h.Chameleon
 B.language=Language;B.presets=Presets;B.ui=UI;B.host=h
 Presets.factory={name='ファクトリーデフォルト',factory=true,values=B.copy(h.defaults)}
 local n=math.min(200,math.max(0,tonumber(R.GetExtState(h.section,'preset_count')) or 0));local names={}
 for i=1,n do
  local raw=R.GetExtState(h.section,'preset_'..i):gsub('%%0A','\n'):gsub('%%0D','\r'):gsub('%%25','%%')
  local p=Presets.decode(raw);if p and not Presets.isFactory(p) and not names[p.name] then Presets.items[#Presets.items+1]=p;names[p.name]=true end
 end;table.sort(Presets.items,function(a,b)return a.name<b.name end)
end
function B.blocked()
 return Presets.open or Presets.swallow or (gfx.mouse_y>=0 and gfx.mouse_y<26)
end
-- Shared project Undo shortcut. Embedded; no runtime file dependency.
local function create_project_undo(api,context)
 local function message(jp,en,ok)
  if context.notice then context.notice(context.language()=='EN' and en or jp,ok) end
 end
 return function(key,modifiers)
  modifiers=modifiers or 0
  if (modifiers&24)~=0 or not (key==26 or ((modifiers&4)~=0 and (key==90 or key==122))) then return false end
  -- Native text editors own their own Undo; never send their shortcut to REAPER.
  if context.editing() then return true end
  if context.busy() then message('処理中は元に戻せません。','Cannot undo during processing.',false);return true end
  local project=api.EnumProjects(-1,'')
  if context.perform then context.perform(project);return true end
  local entry=api.Undo_CanUndo2(project)
  if not entry or entry=='' then message('元に戻せる操作がありません。','Nothing to undo.',true);return true end
  if context.before then context.before() end
  local result=api.Undo_DoUndo2(project)
  if result==nil or result==false or result==0 then message('Undoを実行できませんでした。','Undo failed.',false);return true end
  api.UpdateArrange()
  if context.after then context.after(project) end
  message('元に戻しました。','Undone.',true)
  return true
 end
end
local project_undo=create_project_undo(R,{
 language=function() return Language.code end,notice=notice,
 editing=function() return host.editing() or host.modal() end,
 busy=function() return host.busy() end,
 before=function() if host.undoBefore then host.undoBefore() end end,
 after=function(project) if host.undoRefresh then host.undoRefresh(project) end;wake_visuals() end,
})
function B.key(k)
 if k<0 then return k end
 if Presets.open then Presets.key(k);return 0 end
 if host and not host.localUndo then
  if host.undoAction then
   local cap=gfx.mouse_cap or 0
   if (cap&24)==0 and (k==26 or ((cap&4)~=0 and (k==90 or k==122))) then
    if not host.editing() and not host.modal() then host.undoAction() end
    return 0
   end
  elseif project_undo(k,gfx.mouse_cap) then return 0 end
 end
 return k
end
function B.tick(now)
 Media.tick()
 if not host then return end
 if B.windowW~=gfx.w or B.windowH~=gfx.h then B.windowW,B.windowH=gfx.w,gfx.h;B.lastRect=nil;wake_visuals() end
 B.viewport(host.geometry(),gfx.ext_retina or 1)
 if B.openAfterExpand and not host.collapsed() and not host.busy() then B.openAfterExpand=nil;Presets.menu();wake_visuals() end
 local active=host.active()
 if Presets.open or Presets.swallow then Presets.update(active) end
 if Presets.open and Presets.hoverSince and now>=Presets.hoverSince+1 then wake_visuals() end
 if B.noticeUntil and now>=B.noticeUntil then B.noticeUntil=nil;B.notice=nil;wake_visuals() end
 local phase=host.editing() and (now%1<.5) or false
 if B.caretPhase~=phase then B.caretPhase=phase;wake_visuals() end
 if B.lastDPI~=(gfx.ext_retina or 1) then B.lastDPI=gfx.ext_retina or 1;wake_visuals() end
 if now>=(B.displayAt or 0) then gfx.update();B.displayAt=now+.25 end
 if B.popupUntil then
  if now<B.popupUntil then return end
  clear_chrome_tooltip();B.tip=nil;B.tipVisible=false;B.tipAt=now
 end
 local tip
 local mx,my=gfx.mouse_x,gfx.mouse_y
 if active and not Presets.open and not host.modal() and (gfx.mouse_cap&1)==0 then
  if my>=0 and my<26 then
   local b=UI.bar(gfx.w)
   tip=mx>=b.closeX and '閉じる' or mx>=b.resetX and 'ウィンドウサイズ初期化' or mx>=b.themeX and 'カメレオンモード' or b.foldX and mx>=b.foldX and '縮小／展開' or mx>=b.languageX and '表示言語を切替（JP / EN）' or mx>=b.nextX and '次のプリセット' or mx>=b.prevX and '前のプリセット' or mx>=b.presetX and 'プリセット（読込・保存・インポート／エクスポート）' or nil
  elseif B.footerBounds and B.footerClipped then local r=B.footerBounds;if mx>=r[1] and mx<=r[3] and my>=r[2] and my<=r[4] then tip=B.footerText end end
 end
 if tip then tip=Language.message(tip) end
 if tip~=B.tip then if B.tipVisible then clear_chrome_tooltip() end;B.tip=tip;B.tipAt=now;B.tipVisible=false
 elseif tip and not B.tipVisible and now-B.tipAt>.7 and R.TrackCtl_SetToolTip and gfx.clienttoscreen then
  local x,y=gfx.clienttoscreen(mx,my+18);R.TrackCtl_SetToolTip(tip,x,y,true);B.tipVisible=true
 end
end
function B.bar()
 if not host then return end
 scale,ox,oy=host.geometry()
 local blocked=not B.recoveryMode and (Presets.open or Presets.swallow or host.modal())
 custom_titlebar(blocked)
 Presets.draw()
end

-- Preserve title-bar button edges across repeated application failures.
function B.logError(err)
 local message=B.publicError(err)
 if message~=B.lastLoggedError then
  B.lastLoggedError=message
  if R.ShowConsoleMsg then pcall(R.ShowConsoleMsg,message..'\n') end
 end
end
function B.cleanup(fn,...)
 local ok,result=pcall(fn,...)
 if not ok then B.logError(result) end
 return ok,result
end
function B.recoverInput(state,err)
 gfx.dest=-1;gfx.mode=0;gfx.a=1
 for _,key in ipairs({'drag','number_drag','pointer_capture','field_drag','fieldDrag','scrollDrag','source_wave_drag','curve_drag','scroll_drag','seam_drag','seam_hold','pressed','popup','name_dialog','duplicate_modal'}) do state[key]=nil end
 if host.cancelEdit then B.cleanup(host.cancelEdit) end
 Presets.open=false;Presets.swallow=false;Presets.pressed=nil;Presets.hoverSince=nil
 Chrome.drag=nil;Chrome.resize=nil
 if host.cursor then B.cleanup(host.cursor,nil) end
 B.recoveryMode=true
 local ok,why=pcall(B.bar)
 B.recoveryMode=nil
 if not ok then
  B.logError(why)
  -- A failed font, preset or theme draw must still allow closing the window.
  local down=((gfx.mouse_cap or 0)&1)~=0
  local hit=gfx.mouse_y>=0 and gfx.mouse_y<26 and gfx.mouse_x>=gfx.w-38 and gfx.mouse_x<gfx.w
  if down and not B.emergencyDown then B.emergencyClose=hit end
  if not down and B.emergencyDown then
   if B.emergencyClose and hit then Chrome.requestClose=true end
   B.emergencyClose=nil
  end
  B.emergencyDown=down
 else B.emergencyDown=nil;B.emergencyClose=nil end
 pcall(B.footer,B.publicError(err),true,gfx.w,0,B.footerVersion or '')
 pcall(gfx.update)
 if Chrome.requestClose then state.closing=true end
 state.content_dirty=true
 B.cleanup(host.wake)
 B.logError(err)
end

function B.title(title,subtitle,width,divider)
 scale,ox,oy=host.geometry();local origin=oy+22*scale
 B.font(35,2,true,scale,host.faces);gfx.set(C.text[1],C.text[2],C.text[3],1);gfx.x=ox+24*scale;gfx.y=origin+8*scale;gfx.drawstr(UI.fit(title,(width-150)*scale))
 B.font(10,1,false,scale,host.faces);gfx.set(C.accent2[1],C.accent2[2],C.accent2[3],1);gfx.x=ox+26*scale;gfx.y=origin+44*scale;gfx.drawstr(UI.fit(Language.text(subtitle),(width-155)*scale))
 if divider~=false then gfx.set(C.edge2[1],C.edge2[2],C.edge2[3],.26);gfx.line(ox+24*scale,origin+62*scale,ox+(width-24)*scale,origin+62*scale,1) end
end


function B.footer(message,bad,width,height,version,progress)
 if Media.waiting then message=Media.message(host.section);bad=false;progress=nil end
 if version~='' then B.footerVersion=version end
 scale,ox,oy=host.geometry();message=Language.message(B.notice or tostring(message or ''))
 if B.notice then bad=B.noticeBad end
 local y=oy+(height-13)*scale
 B.font(8,3,true,scale,host.faces);local ver=version~='' and 'v'..version or '';local vw=UI.textMetrics(ver)
 local available=(width-48)*scale-vw-14*scale
 local progressing=type(progress)=='number'
 B.font(9,1,false,scale,host.faces);local shown=progressing and '' or UI.fit(message,available)
 B.footerText=progressing and '' or message;B.footerClipped=not progressing and shown~=message;B.footerBounds={ox+24*scale,y,ox+24*scale+available,y+14*scale}
 gfx.set(C.edge[1],C.edge[2],C.edge[3],.26);gfx.line(ox+24*scale,y-3*scale,ox+(width-24)*scale,y-3*scale)
 if progressing then
  local fraction=math.max(0,math.min(1,progress))
  -- Reserve the widest caption so the track stays still as the percentage changes.
  local caption=string.format(Language.text('解析中...%d%%'),math.floor(fraction*100+.5))
  local captionWidth=UI.textMetrics(Language.text('解析中...100%'))
  gfx.set(C.muted[1],C.muted[2],C.muted[3],1);gfx.x=ox+24*scale;gfx.y=y;gfx.drawstr(caption)
  local x=ox+24*scale+captionWidth+10*scale;local barY=y+3*scale;local barH=6*scale
  local barW=math.max(0,math.min(available,(width-48)*scale*.45)-captionWidth-10*scale)
  gfx.set(C.field[1],C.field[2],C.field[3],1);gfx.rect(x,barY,barW,barH,1)
  gfx.set(C.accent2[1],C.accent2[2],C.accent2[3],.95);gfx.rect(x,barY,barW*fraction,barH,1)
  gfx.set(C.muted[1],C.muted[2],C.muted[3],.5);gfx.rect(x,barY,barW,barH,0)
 else
  local c=bad and C.warn or C.muted;gfx.set(c[1],c[2],c[3],1);gfx.x=ox+24*scale;gfx.y=y;gfx.drawstr(shown)
 end
 B.font(8,3,true,scale,host.faces);gfx.set(C.faint[1],C.faint[2],C.faint[3],1);gfx.x=ox+(width-24)*scale-vw;gfx.y=y;gfx.drawstr(ver)
end
return B
end)()

local Core={SR=48000,HOP=48,LOUD_BLOCK=24000,PEAK_RATE=1000,PEAK_BUFFER_VALUES=262144,
  MAX_ITEM_SECONDS=60*60,LONG_LUFS_WARNING_SECONDS=25*60,MAX_DETECTED_REGIONS=65536}
local abs,min,max,floor,ceil=math.abs,math.min,math.max,math.floor,math.ceil
local function finite(n) return type(n)=="number" and n==n and abs(n)<math.huge end
local function clamp(n,a,b) return max(a,min(b,n)) end
local function copy(t) local o={}; for k,v in pairs(t) do o[k]=v end; return o end
local function db(x) return x>1e-12 and 20*math.log(x,10) or -240 end
Core.defaults={basis="peak",open=-61,close=-61,relative=true,min_open=1000,min_close=165,
  pre=1,post=15,fade_in_on=true,fade_out_on=true,fade_in=1,fade_out=20,
  all=true,action="delete",keep=true,edge_mode=false}
Core.ranges={open={-120,12},close={-120,12},min_open={0,60000},min_close={0,60000},
  pre={-60000,60000},post={-60000,60000},fade_in={0,60000},fade_out={0,60000}}
Core.steps={open=1,close=1,min_open=10,min_close=10,pre=1,post=1,fade_in=1,fade_out=1}
Core.precision={open=2,close=2,min_open=0,min_close=0,pre=0,post=0,fade_in=0,fade_out=0}
function Core.quantize(key,n)
  local digits=Core.precision[key]
  if digits==nil then return n end
  local factor=10^digits
  return (n<0 and ceil(n*factor-.5) or floor(n*factor+.5))/factor
end
function Core.validate(s)
  for k,r in pairs(Core.ranges) do
    if not finite(s[k]) or s[k]<r[1] or s[k]>r[2] then return nil,"設定値が範囲外です："..k end
  end
  if s.close>s.open then return nil,"クローズはオープン以下の値にしてください。" end
  if s.basis~="peak" and s.basis~="lufs" then return nil,"検出基準が無効です。" end
  if s.action~="delete" and s.action~="split" then return nil,"処理方法が無効です。" end
  return true
end
function Core.set_number(s,key,n)
  local r=Core.ranges[key]
  if not r or not finite(n) then return nil,"数値を入力してください。" end
  local requested=n
  n=Core.quantize(key,n)
  local old=s[key]
  if (key=="open" or key=="close") and s.relative then
    local other=key=="open" and "close" or "open"
    local delta=clamp(n-old,max(r[1]-old,r[1]-s[other]),min(r[2]-old,r[2]-s[other]))
    s[key],s[other]=old+delta,s[other]+delta
  else
    n=clamp(n,r[1],r[2])
    if key=="open" then n=max(n,s.close) elseif key=="close" then n=min(n,s.open) end
    s[key]=n
  end
  s[key]=Core.quantize(key,s[key])
  return true,abs((s[key] or requested)-requested)>1e-9
end
local function valid_item(project,item) return item and R.ValidatePtr2(project,item,"MediaItem*") end
function Core.info(project,item)
  if not valid_item(project,item) then return nil,"対象アイテムがありません。" end
  local take=R.GetActiveTake(item)
  if not take or R.TakeIsMIDI(take) then return nil,"MIDI／空アイテムは対象外です。" end
  local source=R.GetMediaItemTake_Source(take)
  if not source then return nil,"音声ソースがありません。" end

  -- Empty/note items can still expose a PCM_source-like object.  Filter them
  -- before peak/accessor analysis so only sources with real audio are queued.
  local source_type=R.GetMediaSourceType(source)
  source_type=type(source_type)=="string" and source_type:upper() or ""
  if source_type=="EMPTY" or source_type=="MIDI" or source_type=="MIDIPOOL" then
    return nil,"MIDI／空アイテムは対象外です。"
  end
  local source_sr=R.GetMediaSourceSampleRate(source)
  if not finite(source_sr) or source_sr<=0 then
    return nil,"音声を持たないアイテムは対象外です。"
  end

  local channels=R.GetMediaSourceNumChannels(source)
  if not finite(channels) or channels<1 or channels>64 then return nil,"音声チャンネルを取得できません。" end
  local channel_mode=R.GetMediaItemTakeInfo_Value(take,"I_CHANMODE")
  if channel_mode==2 or channel_mode==3 or channel_mode==4 then channels=1 end
  local pos,len=R.GetMediaItemInfo_Value(item,"D_POSITION"),R.GetMediaItemInfo_Value(item,"D_LENGTH")
  if not finite(pos) or not finite(len) or len<=0 then return nil,"長さが0のアイテムは対象外です。" end
  local track=R.GetMediaItemTrack(item)
  local _,guid=R.GetSetMediaItemInfo_String(item,"GUID","",false)
  return {item=item,take=take,track=track,pos=pos,len=len,channels=floor(channels),
    guid=guid or tostring(item),name=R.GetTakeName(take) or "Audio item",
    tracknum=R.GetMediaTrackInfo_Value(track,"IP_TRACKNUMBER"),
    index=R.GetMediaItemInfo_Value(item,"IP_ITEMNUMBER"),
    gain=abs(R.GetMediaItemInfo_Value(item,"D_VOL")*R.GetMediaItemTakeInfo_Value(take,"D_VOL")),
    locked=(floor(R.GetMediaItemInfo_Value(item,"C_LOCK"))&1)~=0}
end
local function find_item_by_guid(project,guid)
  if not guid or guid=="" then return nil end
  for i=0,R.CountMediaItems(project)-1 do
    local item=R.GetMediaItem(project,i)
    local _,g=R.GetSetMediaItemInfo_String(item,"GUID","",false)
    if g==guid then return item end
  end
  return nil
end
function Core.refresh_info(project,snapshot)
  if not snapshot then return nil,"対象アイテムがありません。" end
  local item=snapshot.item
  if not valid_item(project,item) then item=find_item_by_guid(project,snapshot.guid) end
  if not item then return nil,"対象アイテムが見つかりません。" end
  return Core.info(project,item)
end
function Core.selection(project)
  local list,ids,skipped={},{},0
  for i=0,R.CountSelectedMediaItems(project)-1 do
    local item=R.GetSelectedMediaItem(project,i)
    ids[#ids+1]=tostring(item)
    local info=Core.info(project,item)
    if info then list[#list+1]=info else skipped=skipped+1 end
  end
  table.sort(list,function(a,b)
    if a.pos~=b.pos then return a.pos<b.pos end
    if a.tracknum~=b.tracknum then return a.tracknum<b.tracknum end
    return a.index<b.index
  end)
  table.sort(ids)
  return list,table.concat(ids,"|"),skipped
end
function Core.selection_key(project)
  local ids={}
  for i=0,R.CountSelectedMediaItems(project)-1 do ids[#ids+1]=tostring(R.GetSelectedMediaItem(project,i)) end
  table.sort(ids)
  return table.concat(ids,"|")
end
function Core.chunk(info)
  local ok,text=R.GetItemStateChunk(info.item,"",false)
  if not ok or type(text)~="string" or text=="" then error("アイテムの状態を保存できません。",0) end
  return text
end
function Core.dispose(j)
  if not j then return end
  if j.accessor then local accessor=j.accessor;j.accessor=nil;pcall(R.DestroyAudioAccessor,accessor) end
  if j.peak_accessor then local accessor=j.peak_accessor;j.peak_accessor=nil;pcall(R.DestroyAudioAccessor,accessor) end
end
function Core.start(project,info,basis,known_chunk)
  if not valid_item(project,info.item) then error("対象が削除されました。",0) end
  if info.len>Core.MAX_ITEM_SECONDS then error("1アイテムは60分以内にしてください。",0) end
  local chunk=known_chunk or Core.chunk(info)
  if basis=="peak" then
    local total=ceil(info.len*Core.PEAK_RATE)
    local max_bins=max(1,floor(Core.PEAK_BUFFER_VALUES/max(2,info.channels*2)))
    local buffer_ok,buffer=pcall(R.new_array,max_bins*info.channels*2)
    if not buffer_ok or not buffer then error("ピーク解析用バッファを作成できません。",0) end
    return {mode="peak",info=info,project=project,offset=0,total=total,peak={},lufs={},fast={},
      max_peak=0,chunk=chunk,done=false,max_bins=max_bins,buffer=buffer}
  end
  if basis~="lufs" then error("検出基準が無効です。",0) end
  if info.channels>2 then error("LUFS-Mはモノ／ステレオ対応です。多チャンネルはピークを選択してください。",0) end
  local j={mode="lufs",info=info,project=project,offset=0,total=ceil(info.len*Core.SR),peak={},lufs={},fast={},
    ring={},ring_index=1,ring_sum=0,fast_ring={},fast_index=1,fast_sum=0,
    bin_energy=0,bin_peak=0,bin_samples=0,states={},max_peak=0,
    chunk=chunk,done=false}
  for c=1,info.channels do j.states[c]={0,0,0,0} end
  local buffer_ok,buffer=pcall(R.new_array,Core.LOUD_BLOCK*info.channels)
  if not buffer_ok or not buffer then error("ラウドネス解析用バッファを作成できません。",0) end
  j.buffer=buffer
  j.accessor=R.CreateTakeAudioAccessor(info.take)
  if not j.accessor then error("音声アクセサを作成できません。",0) end
  local a,b=R.GetAudioAccessorStartTime(j.accessor),R.GetAudioAccessorEndTime(j.accessor)
  if not finite(a) or not finite(b) or b<=a then
    Core.dispose(j); error("音声を読み出せません。オフライン状態やソースを確認してください。",0)
  end
  return j
end
local function finish_bin(j)
  local k=#j.peak+1
  j.peak[k]=j.bin_peak; j.max_peak=max(j.max_peak,j.bin_peak)
  -- Standard LUFS-M OPEN detector: trailing 400 ms K-weighted power.
  local ri=j.ring_index
  j.ring_sum=max(0,j.ring_sum-(j.ring[ri] or 0)+j.bin_energy)
  j.ring[ri]=j.bin_energy; j.ring_index=ri%400+1
  local power=j.ring_sum/(Core.SR*0.4)
  j.lufs[k]=power>1e-24 and -0.691+10*math.log(power,10) or -240

  -- FAST CLOSE detector: same K weighting, but a much faster trailing 100 ms window.
  local fi=j.fast_index
  j.fast_sum=max(0,j.fast_sum-(j.fast_ring[fi] or 0)+j.bin_energy)
  j.fast_ring[fi]=j.bin_energy; j.fast_index=fi%100+1
  local fast_power=j.fast_sum/(Core.SR*0.1)
  j.fast[k]=fast_power>1e-24 and -0.691+10*math.log(fast_power,10) or -240
  j.bin_samples,j.bin_peak,j.bin_energy=0,0,0
end
local function start_peak_accessor_fallback(j)
  if j.peak_accessor then return end
  j.peak_accessor=R.CreateTakeAudioAccessor(j.info.take)
  if not j.peak_accessor then
    error("REAPERのピークデータを取得できず、音声の直接読み出しにも失敗しました。ソースのオンライン状態を確認してください。",0)
  end
  -- Keep fallback memory bounded even for high-channel-count sources. At 48 kHz
  -- one 1 ms peak bin contains exactly 48 source samples.
  j.fallback_bins=max(1,floor(Core.PEAK_BUFFER_VALUES/(j.info.channels*48)))
  j.buffer=R.new_array(j.fallback_bins*48*j.info.channels)
end

local function read_peak_accessor_step(j)
  local remaining=j.total-j.offset
  if remaining<=0 then
    if j.peak_accessor then local accessor=j.peak_accessor;j.peak_accessor=nil;pcall(R.DestroyAudioAccessor,accessor) end
    j.done=true; j.buffer=nil; return true
  end
  local bins=min(j.fallback_bins,remaining)
  local samples=bins*48
  local nchan=j.info.channels
  j.buffer.clear()
  local rc=R.GetAudioAccessorSamples(j.peak_accessor,Core.SR,nchan,j.offset/Core.PEAK_RATE,samples,j.buffer)
  if type(rc)~="number" or (rc~=0 and rc~=1) then
    if j.peak_accessor then local accessor=j.peak_accessor;j.peak_accessor=nil;pcall(R.DestroyAudioAccessor,accessor) end
    error("音声の直接読み出しに失敗しました（戻り値："..tostring(rc).."）。",0)
  end
  local values=j.buffer.table(1,samples*nchan)
  local gain=j.info.gain
  for b=0,bins-1 do
    local pk=0
    local first=b*48*nchan
    if rc~=0 then
      for frame=0,47 do
        local base=first+frame*nchan
        for c=1,nchan do
          local sample=values[base+c] or 0
          if not finite(sample) then
            if j.peak_accessor then local accessor=j.peak_accessor;j.peak_accessor=nil;pcall(R.DestroyAudioAccessor,accessor) end
            error("音声に読み取れないサンプルがあります。",0)
          end
          pk=max(pk,abs(sample))
        end
      end
    end
    pk=pk*gain
    j.peak[#j.peak+1]=pk
    j.max_peak=max(j.max_peak,pk)
  end
  j.offset=j.offset+bins
  if j.offset>=j.total then
    if j.peak_accessor then local accessor=j.peak_accessor;j.peak_accessor=nil;pcall(R.DestroyAudioAccessor,accessor) end
    j.offset=j.total; j.done=true; j.buffer=nil
  end
  return j.done
end

local function read_peak_step(j)
  if j.done then return true end
  if not valid_item(j.project,j.info.item) then error("解析中に対象が削除されました。",0) end
  if j.peak_accessor then return read_peak_accessor_step(j) end
  local remaining=j.total-j.offset
  if remaining<=0 then j.done=true; j.buffer=nil; return true end
  local request=min(j.max_bins,remaining)
  local nchan=j.info.channels
  j.buffer.clear()
  -- Fast path: REAPER's native take-peak reader. If it unexpectedly reports no
  -- samples, retry with a smaller block before falling back to direct audio.
  local rv=R.GetMediaItemTake_Peaks(j.info.take,Core.PEAK_RATE,j.info.pos+j.offset/Core.PEAK_RATE,nchan,request,0,j.buffer)
  local got=(type(rv)=="number") and (rv & 0xFFFFF) or 0
  if got<=0 and request>4096 then
    request=min(4096,remaining)
    j.buffer.clear()
    rv=R.GetMediaItemTake_Peaks(j.info.take,Core.PEAK_RATE,j.info.pos+j.offset/Core.PEAK_RATE,nchan,request,0,j.buffer)
    got=(type(rv)=="number") and (rv & 0xFFFFF) or 0
  end
  if got<=0 then
    start_peak_accessor_fallback(j)
    return read_peak_accessor_step(j)
  end
  local values=j.buffer.table(1,got*nchan*2)
  local second=got*nchan
  local gain=j.info.gain
  for i=0,got-1 do
    local pk=0
    local base=i*nchan
    for c=1,nchan do
      local idx=base+c
      local hi=values[idx] or 0
      local lo=values[second+idx] or 0
      pk=max(pk,abs(hi),abs(lo))
    end
    pk=pk*gain
    j.peak[#j.peak+1]=pk
    j.max_peak=max(j.max_peak,pk)
  end
  j.offset=j.offset+got
  if j.offset>=j.total or got<request then
    while #j.peak<j.total do j.peak[#j.peak+1]=0 end
    j.offset=j.total; j.done=true; j.buffer=nil
  end
  return j.done
end
local function read_loud_step(j)
  if j.done then return true end
  if not valid_item(j.project,j.info.item) then error("解析中に対象が削除されました。",0) end
  if R.AudioAccessorStateChanged(j.accessor) then error("解析中に音声が変更されました。選択を更新してください。",0) end
  local count=min(Core.LOUD_BLOCK,j.total-j.offset)
  j.buffer.clear()
  -- TAKE accessor reads item-local seconds, NOT item project position or source offset.
  local rc=R.GetAudioAccessorSamples(j.accessor,Core.SR,j.info.channels,j.offset/Core.SR,count,j.buffer)
  if type(rc)~="number" or (rc~=0 and rc~=1) then
    error("音声取得に失敗しました（戻り値："..tostring(rc).."）。解析を中止しました。",0)
  end
  local values=j.buffer.table(1,count*j.info.channels)
  local nchan,gain=j.info.channels,j.info.gain
  for i=0,count-1 do
    local pk,energy=0,0
    for c=1,nchan do
      local raw=values[i*nchan+c]
      if not finite(raw) then error("音声に読み取れないサンプルがあります。",0) end
      local sample=(rc==0 and 0 or raw)*gain
      pk=max(pk,abs(sample))
      -- ITU-R BS.1770, 48 kHz K weighting, transposed direct form II.
      local st=j.states[c]
      local v=1.53512485958697*sample+st[1]
      st[1]=-2.69169618940638*sample+1.69065929318241*v+st[2]
      st[2]=1.19839281085285*sample-0.73248077421585*v
      local z=v+st[3]
      st[3]=-2*v+1.99004745483398*z+st[4]
      st[4]=v-0.99007225036621*z
      energy=energy+z*z
    end
    j.bin_peak=max(j.bin_peak,pk); j.bin_energy=j.bin_energy+energy; j.bin_samples=j.bin_samples+1
    if j.bin_samples==Core.HOP then finish_bin(j) end
  end
  j.offset=j.offset+count
  if j.offset>=j.total then
    if j.bin_samples>0 then finish_bin(j) end
    Core.dispose(j); j.buffer=nil; j.states=nil; j.ring=nil; j.fast_ring=nil; j.done=true
  end
  return j.done
end
function Core.read_step(j)
  -- Do not use the Lua `a and f() or g()` idiom here: read_peak_step()
  -- legitimately returns false while a long Peak job is still in progress,
  -- which would then incorrectly fall through and call the Loudness reader.
  if j.mode=="peak" then
    return read_peak_step(j)
  elseif j.mode=="lufs" then
    return read_loud_step(j)
  end
  error("解析モードが無効です。",0)
end
function Core.detector(data,s)
  local ok,err=Core.validate(s); if not ok then error(err,0) end
  if s.basis=="lufs" and data.info.channels>2 then error("LUFS-Mはモノ／ステレオ対応です。多チャンネルはピークを選択してください。",0) end
  -- REAPER Auto Trim / Dynamic Split style timing:
  --   min_open  = ignore silence shorter than this duration.
  --   min_close = minimum accepted non-silent clip duration.
  -- A CLOSE candidate starts as soon as the close detector drops below the
  -- threshold. It is confirmed only if silence lasts min_open; the edit
  -- boundary stays at the beginning of that silence. Shorter silences are
  -- absorbed into the current non-silent region. A completed non-silent
  -- region shorter than min_close is discarded before pre/post roll.
  return {data=data,s=copy(s),i=1,regions={},raw={},raw_first=nil,raw_last=nil,raw_count=0,opened=nil,quiet=nil,done=false}
end
local function append_region(d,a,b)
  if b<=a then return end
  -- "Make non-silent clips no shorter than": reject short detected clips
  -- before pads are applied, so pre/post roll cannot make a rejected clip
  -- pass the minimum-length test.
  if b-a+1e-10 < d.s.min_close/1000 then return end
  -- EDGE MODE needs only the first opening and final closing edge. Keeping every
  -- intermediate raw region used large amounts of memory without affecting its
  -- result, particularly when thresholds oscillated around adjacent 1 ms bins.
  if d.s.edge_mode then
    d.raw_first=d.raw_first or a;d.raw_last=b;d.raw_count=d.raw_count+1
    return
  end
  a=clamp(a-d.s.pre/1000,0,d.data.info.len)
  b=clamp(b+d.s.post/1000,0,d.data.info.len)
  if b-a<1/Core.SR then return end
  local last=d.regions[#d.regions]
  if last and a<=last[2]+1e-10 then last[2]=max(last[2],b)
  else
    if #d.regions>=Core.MAX_DETECTED_REGIONS then
      error("検出区間が安全上限を超えました。しきい値、最小無音、最小区間の設定を調整してください。",0)
    end
    d.regions[#d.regions+1]={a,b}
  end
end
function Core.detect_step(d,limit)
  if d.done then return true end
  local data,s=d.data,d.s
  local ignore_silence_s=s.min_open/1000
  for _=1,limit or 8192 do
    local i=d.i
    if i>#data.peak then
      if d.opened then append_region(d,d.opened,data.info.len) end
      if s.edge_mode and d.raw_first then
        local a=clamp(d.raw_first-s.pre/1000,0,data.info.len)
        local b=clamp(d.raw_last+s.post/1000,0,data.info.len)
        if b-a>=1/Core.SR then d.regions={{a,b}};d.raw={{d.raw_first,d.raw_last}} end
      end
      d.done=true; return true
    end
    local t=(i-1)*0.001
    local ending=min(i*0.001,data.info.len)
    local open_level,close_level
    if s.basis=="lufs" then
      -- Custom loudness mode: LUFS-M (400 ms) opens, FAST (100 ms) closes.
      open_level=data.lufs[i] or -240
      close_level=data.fast[i] or -240
    else
      open_level=db(data.peak[i])
      close_level=open_level
    end

    if d.opened then
      if close_level<s.close then
        -- Start measuring silence, but do not close yet. If the signal comes
        -- back before the requested duration, this silence is ignored.
        d.quiet=d.quiet or t
        if ending-d.quiet+1e-10>=ignore_silence_s then
          append_region(d,d.opened,d.quiet)
          d.opened=nil
          d.quiet=nil
        end
      else
        d.quiet=nil
      end
    else
      if open_level>s.open then
        d.opened=t
        d.quiet=nil
      end
    end
    d.i=i+1
  end
  return false
end

function Core.plan(info,regions,s)
  local parts,cursor,packed={},0,0
  local function add(a,b,sound)
    if b-a<1e-10 then return end
    local keep=sound or s.action=="split"
    local dest=info.pos+a
    if sound and s.action=="delete" and not s.keep then dest=info.pos+packed; packed=packed+b-a end
    parts[#parts+1]={a=a,b=b,sound=sound,keep=keep,dest=dest}
  end
  for _,r in ipairs(regions) do add(cursor,r[1],false); add(r[1],r[2],true); cursor=r[2] end
  add(cursor,info.len,false)
  return parts
end
local function set_item(item,key,value)
  if not R.SetMediaItemInfo_Value(item,key,value) then error("アイテム属性を更新できません："..key,0) end
end
function Core.apply(project,entries,s)
  local ok,err=Core.validate(s); if not ok then return nil,err end
  local saved={}
  -- Complete preflight before the first project mutation.
  for index,e in ipairs(entries) do
    local now,info_err=Core.refresh_info(project,e.info)
    local label=e.info and e.info.name or ("#"..index)
    if not now then return nil,string.format("対象が見つかりません：%s（%s）",label,info_err or "不明なエラー") end
    if now.locked then return nil,string.format("ロックされたアイテムがあります：%s",now.name or label) end
    if Core.chunk(now)~=e.chunk then return nil,string.format("解析後に対象が変更されています：%s",now.name or label) end
    -- Rebind the entry as well; apply() below must use the current pointer.
    e.info=now
    saved[#saved+1]={info=now,chunk=e.chunk,fragments={now.item},touched=false}
  end
  if #saved==0 then return nil,"処理対象がありません。" end
  local produced,changed={},0
  R.Undo_BeginBlock2(project); R.PreventUIRefresh(1)
  local success,detail=xpcall(function()
    for ei,e in ipairs(entries) do
      local info=e.info; local parts=Core.plan(info,e.regions,s)
      local no_boundary_change=s.action=="split" and #parts==1
        and not (parts[1].sound and (s.fade_in_on or s.fade_out_on))
      if no_boundary_change then
        produced[#produced+1]=info.item
      else
        saved[ei].touched=true
        local original_in=max(0,R.GetMediaItemInfo_Value(info.item,"D_FADEINLEN"),R.GetMediaItemInfo_Value(info.item,"D_FADEINLEN_AUTO"))
        local original_out=max(0,R.GetMediaItemInfo_Value(info.item,"D_FADEOUTLEN"),R.GetMediaItemInfo_Value(info.item,"D_FADEOUTLEN_AUTO"))
        local piece=info.item
        -- Split from right to left so every split uses the original timeline.
        for i=#parts,2,-1 do
          local right=R.SplitMediaItem(piece,info.pos+parts[i].a)
          if not right then error("アイテムを分割できません。",0) end
          saved[ei].fragments[#saved[ei].fragments+1]=right
          parts[i].item=right; changed=changed+1
        end
        parts[1].item=piece
        for _,p in ipairs(parts) do
          if not p.keep then
            if not R.DeleteTrackMediaItem(info.track,p.item) then error("無音部分を削除できません。",0) end
            changed=changed+1
          else
            if abs(p.dest-(info.pos+p.a))>1e-10 then
              if not R.SetMediaItemPosition(p.item,p.dest,false) then error("アイテムを移動できません。",0) end
              changed=changed+1
            end
            local dur=p.b-p.a
            local fi=p.a<1e-10 and original_in or 0
            local fo=abs(p.b-info.len)<1e-10 and original_out or 0
            if p.sound and s.fade_in_on then fi=s.fade_in/1000 end
            if p.sound and s.fade_out_on then fo=s.fade_out/1000 end
            -- No fade overlap on short regions; global split/auto-fade preferences
            -- must not change the requested result.
            fi,fo=min(fi,dur),min(fo,dur)
            if fi+fo>dur then local k=dur/(fi+fo); fi,fo=fi*k,fo*k end
            set_item(p.item,"D_FADEINLEN_AUTO",-1); set_item(p.item,"D_FADEOUTLEN_AUTO",-1)
            set_item(p.item,"D_FADEINLEN",fi); set_item(p.item,"D_FADEOUTLEN",fo)
            if p.sound and s.fade_in_on then set_item(p.item,"C_FADEINSHAPE",0); set_item(p.item,"D_FADEINDIR",0) end
            if p.sound and s.fade_out_on then set_item(p.item,"C_FADEOUTSHAPE",0); set_item(p.item,"D_FADEOUTDIR",0) end
            R.SetMediaItemSelected(p.item,true)
            produced[#produced+1]=p.item
          end
        end
      end
    end
  end,debug.traceback)
  local restored=true
  if not success then
    -- Restore only this operation's items; never invoke a global Undo blindly.
    for _,v in ipairs(saved) do if v.touched then
      if #v.fragments==1 and valid_item(project,v.fragments[1]) then
        local call,result=pcall(R.SetItemStateChunk,v.fragments[1],v.chunk,false)
        if not call or not result then restored=false end
      else
        local deleted=true
        for _,item in ipairs(v.fragments) do
          if valid_item(project,item) then
            local call,result=pcall(R.DeleteTrackMediaItem,v.info.track,item)
            if not call or not result then deleted=false;restored=false end
          end
        end
        if deleted then
          local call,result=pcall(function()
            local item=R.AddMediaItemToTrack(v.info.track)
            return item and R.SetItemStateChunk(item,v.chunk,false)
          end)
          if not call or not result then restored=false end
        end
      end
     end
    end
  end
  R.PreventUIRefresh(-1); R.UpdateArrange()
  R.Undo_EndBlock2(project,success and "Auto Trim / Split" or "Auto Trim / Split (restored after error)",4)
  if not success then
    R.ShowConsoleMsg("Auto Trim / Split:\n"..BLT.publicError(detail).."\n")
    return nil,restored and "処理を中止し、元のアイテムを復元しました。" or "復元できない項目があります。REAPERのUndoで戻してください。"
  end
  return {items=produced,count=#entries,changes=changed}
end

local SECTION="BLT_AUTO_TRIM_SPLIT"
local S=copy(Core.defaults)
for key,default in pairs(S) do
  if type(default)~="number" then
    local v=R.GetExtState(SECTION,key)
    if v~="" then
      if type(default)=="boolean" then S[key]=v=="1"
      elseif key=="basis" and (v=="peak" or v=="lufs") then S[key]=v
      elseif key=="action" and (v=="delete" or v=="split") then S[key]=v end
    end
  end
end

local PROFILE_NUMERIC_KEYS={"open","close","min_open","min_close","pre","post","fade_in","fade_out"}
local PROFILE_DEFAULTS={
  peak={open=-61,close=-61,min_open=1000,min_close=165,pre=1,post=15,fade_in=1,fade_out=20},
  lufs={open=-55,close=-55,min_open=1100,min_close=15,pre=1,post=15,fade_in=1,fade_out=20},
}
local function saved_profile_number(basis,key,default)
  local n=tonumber(R.GetExtState(SECTION,basis.."_"..key))
  if not finite(n) then n=default end
  local r=Core.ranges[key]
  return r and Core.quantize(key,clamp(n,r[1],r[2])) or n
end

local profile_state={peak={},lufs={}}
for _,basis in ipairs({"peak","lufs"}) do
  local p=profile_state[basis]
  for _,key in ipairs(PROFILE_NUMERIC_KEYS) do
    p[key]=saved_profile_number(basis,key,PROFILE_DEFAULTS[basis][key])
  end
  p.close=min(p.close,p.open)
end

local function load_profile(basis)
  local p=profile_state[basis]
  for _,key in ipairs(PROFILE_NUMERIC_KEYS) do S[key]=p[key] end
end
local function stash_profile()
  local p=profile_state[S.basis]
  for _,key in ipairs(PROFILE_NUMERIC_KEYS) do p[key]=S[key] end
end
load_profile(S.basis)

local A={project=R.EnumProjects(-1,""),queue={},index=1,selection_key="",skipped=0,selection_total=0,
  ready=false,regions={},raw={},message="",bad=false,poll_at=0,zoom=1,view_start=0,
  audio_cache={},long_lufs_approved={},wave_surface_dirty=true,settings_pending=false,settings_due=0,
  field_flash={},field_drag=nil}
local function persist()
  stash_profile()
  for k,v in pairs(S) do
    if type(v)~="number" or not Core.ranges[k] then
      BLT.store(SECTION,k,type(v)=="boolean" and (v and "1" or "0") or tostring(v),true)
    end
  end
  for basis,p in pairs(profile_state) do
    for _,key in ipairs(PROFILE_NUMERIC_KEYS) do
      BLT.store(SECTION,basis.."_"..key,tostring(p[key]),true)
    end
  end
end
local function notice(text,bad) A.message=bad and BLT.publicError(text) or tostring(text or ''); A.bad=bad or false end
local function invalidate_wave_surface(full)
  if full then A.wave_cache=nil end
  A.wave_surface_dirty=true
end
local function cache_slot(info,chunk)
  local key=info.guid or tostring(info.item)
  local e=A.audio_cache[key]
  if not e or e.chunk~=chunk then
    A.audio_cache={}
    e={chunk=chunk}; A.audio_cache[key]=e
  end
  return e
end
local function cached_audio(info,chunk,basis)
  local cached=cache_slot(info,chunk)[basis]
  if not cached then return nil end
  -- Cache only the expensive analysis result. MediaItem/Take pointers can become
  -- stale after Undo/redo or other project reconstruction even when GUID and
  -- state chunk are unchanged. Return a shallow bound view with the CURRENT
  -- item metadata so batch processing never reuses an obsolete pointer.
  local bound=copy(cached)
  bound.info=info
  bound.project=A.project
  bound.chunk=chunk
  return bound
end
local function store_audio(data)
  if not data or not data.info or not data.chunk then return end
  A.audio_cache={}
  cache_slot(data.info,data.chunk)[data.mode]=data
end
local function stop_jobs()
  Core.dispose(A.analysis); A.analysis=nil; A.detector=nil; A.batch=nil
end
local function long_lufs_key(info)
  return info and (info.guid or tostring(info.item)) or nil
end
local function prune_long_lufs_approvals()
  local keep={}
  for _,info in ipairs(A.queue or {}) do
    local key=long_lufs_key(info)
    if key and A.long_lufs_approved[key] then keep[key]=true end
  end
  A.long_lufs_approved=keep
end
local function confirm_long_lufs(info,basis)
  if basis~="lufs" or not info or info.len<=Core.LONG_LUFS_WARNING_SECONDS then return true end
  local key=long_lufs_key(info)
  if key and A.long_lufs_approved[key] then return true end
  local message=string.format(
    "ファイルが長いため、解析中および結果を表示している間はメモリ使用量が増えます。よろしいですか？\n\n%s\n長さ：%.1f分\n\n［実行］する場合は OK、［キャンセル］する場合はキャンセルを押してください。\nキャンセルしたアイテムは選択解除されます。",
    info.name or "Audio item",info.len/60)
  if Language.mb(message,"Auto Trim / Split | 長尺LUFS解析",1)==1 then
    if key then A.long_lufs_approved[key]=true end
    return true
  end
  if valid_item(A.project,info.item) then R.SetMediaItemSelected(info.item,false) end
  R.UpdateArrange()
  return false
end
local function detect_preview()
  A.ready=false; A.regions={}; A.raw={}; A.detector=nil
  invalidate_wave_surface()
  if A.data then A.detector=Core.detector(A.data,S); A.detector.context="preview" end
end
local function start_preview(reset_view)
 if not Media.ready() then return end
  A.settings_pending=false; A.settings_due=0
  stop_jobs(); A.data=nil; A.ready=false; A.regions={}; A.raw={}
  invalidate_wave_surface(true)
  if reset_view~=false then A.zoom=1; A.view_start=0 end
  local canceled=0
  while true do
    local info=A.queue[A.index]
    if not info then
      local had_cache=next(A.audio_cache or {})~=nil
      A.audio_cache={};A.long_lufs_approved={}
      if had_cache then collectgarbage("collect") end
      if canceled>0 then
        notice(string.format("長尺アイテム%d件のLUFS解析をキャンセルし、選択を解除しました。",canceled))
      else
        notice("音声アイテムを選択してください。"..(A.skipped>0 and (" 対象外："..A.skipped.."個") or ""))
      end
      return
    end
    local fresh,err=Core.info(A.project,info.item)
    if not fresh then error(err,0) end
    if fresh.len>Core.MAX_ITEM_SECONDS then error("1アイテムは60分以内にしてください。",0) end
    A.queue[A.index]=fresh
    local chunk=Core.chunk(fresh)
    local cached=cached_audio(fresh,chunk,S.basis)
    if cached then
      A.data=cached
      detect_preview()
      local prefix=canceled>0 and string.format("長尺アイテム%d件の選択を解除しました。 ",canceled) or ""
      notice(prefix..(S.basis=="peak" and "Peakデータをキャッシュから読み込みました。" or "Loudnessデータをキャッシュから読み込みました。"))
      return
    end
    if confirm_long_lufs(fresh,S.basis) then
      A.analysis=Core.start(A.project,fresh,S.basis,chunk); A.analysis.context="preview"
      local prefix=canceled>0 and string.format("長尺アイテム%d件の選択を解除しました。 ",canceled) or ""
      notice(prefix..(S.basis=="peak" and "Peakを取得しています。" or "ラウドネスを解析しています。"))
      return
    end
    canceled=canceled+1
    A.queue,A.selection_key,A.skipped=Core.selection(A.project); A.index=1
    A.selection_total=#A.queue
    prune_long_lufs_approvals()
    A.revision=R.GetProjectStateChangeCount(A.project)
  end
end
local function sync_selection()
 if not Media.ready() then return end
  A.queue,A.selection_key,A.skipped=Core.selection(A.project); A.index=1
  A.selection_total=#A.queue
  prune_long_lufs_approvals()
  A.revision=R.GetProjectStateChangeCount(A.project)
  start_preview(true)
end
local function settings_changed()
  A.settings_pending=false; A.settings_due=0
  persist(); detect_preview()
  if A.data then notice("プレビューを更新しています。") end
end

-- Mouse-wheel edits can arrive many times per second. Updating the detector and
-- waveform on every notch makes the preview flash between READY / recalculating.
-- Keep the numeric field responsive, but rebuild the preview only once after
-- the wheel has been idle for a short moment.
local function schedule_settings_changed()
  stash_profile()
  A.settings_pending=true
  A.settings_due=R.time_precise()+0.15
end

local function flush_scheduled_settings()
  if not A.settings_pending then return false end
  A.settings_pending=false; A.settings_due=0
  persist(); detect_preview()
  if A.data then notice("プレビューを更新しています。") end
  return true
end
local function set_basis(value)
  if value~="peak" and value~="lufs" then return end
  if S.basis==value then return end
  stash_profile()
  S.basis=value
  load_profile(value)
  persist()
  start_preview(false)
end

local function fail(err)
  BLT.cleanup(stop_jobs); A.ready=false
  notice(err,true)
  BLT.recoverInput(A,err)
end
local function guarded(fn)
  local ok,err=xpcall(fn,debug.traceback); if not ok then fail(err) end
end

-- Duration-weighted batch progress. Loudness analysis cost is roughly
-- proportional to source duration, so this tracks perceived waiting time much
-- better than a simple item counter. Analysis occupies most of each item's
-- work; the final detector scan uses the remaining small fraction.
local function batch_progress()
  local b=A.batch
  if not b then return 0 end
  local total=max(1e-9,b.total_work or 0)
  local done=b.done_work or 0
  local current=0
  if A.analysis and A.analysis.info then
    local f=clamp(A.analysis.offset/max(1,A.analysis.total),0,1)
    current=(A.analysis.info.len or 0)*(0.96*f)
  elseif A.detector and A.detector.context=="batch" and A.detector.data and A.detector.data.info then
    local bins=max(1,#(A.detector.data.peak or {}))
    local f=clamp((A.detector.i-1)/bins,0,1)
    current=(A.detector.data.info.len or 0)*(0.96+0.04*f)
  elseif b.i and b.i>#b.list then
    return 1
  end
  return clamp((done+current)/total,0,1)
end

local function batch_next()
  local b=A.batch
  if b.i>#b.list then
    local result,err=Core.apply(A.project,b.entries,b.settings)
    if not result then error(err,0) end
    local all=b.settings.all
    A.batch=nil; A.analysis=nil; A.detector=nil; A.data=nil; A.ready=false
    if all then A.queue={}; A.index=1
    else table.remove(A.queue,A.index); if A.index>#A.queue then A.index=1 end end
    local _,key=Core.selection(A.project); A.selection_key=key
    A.revision=R.GetProjectStateChangeCount(A.project)
    start_preview(true)
    notice(string.format("%dアイテムを処理しました。%s",result.count,#A.queue>0 and "次の対象を表示しています。" or "完了です。"))
    return
  end
  local info,info_err=Core.refresh_info(A.project,b.list[b.i])
  if not info then error(info_err or "対象アイテムが見つかりません。",0) end
  if info.len>Core.MAX_ITEM_SECONDS then error("1アイテムは60分以内にしてください。",0) end
  if info.locked then error("ロックされたアイテムがあります："..(info.name or tostring(b.i)),0) end
  -- Recheck immediately before every fresh read as well. This covers the narrow
  -- case where an item's length changes after Execute was pressed but before its
  -- turn in a multi-item batch.
  if not confirm_long_lufs(info,b.settings.basis) then
    sync_selection()
    notice("長尺アイテムのLUFS解析をキャンセルし、選択を解除しました。バッチ処理は開始前の状態で中止しました。")
    return
  end
  b.list[b.i]=info
  local chunk=Core.chunk(info)
  -- Execute always performs a fresh read. Preview caches are intentionally never
  -- authoritative for a destructive split/delete operation.
  A.analysis=Core.start(A.project,info,b.settings.basis,chunk); A.analysis.context="batch"
end
local function execute()
 if not A.job and not A.busy and not A.batch and not Media.ready() then return end
  if A.settings_pending then flush_scheduled_settings() end
  if A.batch then stop_jobs(); start_preview(false); notice("解析を中止しました。アイテムは変更していません。"); return end
  if not A.ready or not A.data then notice("プレビューの解析完了を待ってください。",true); return end
  local list={}
  if S.all then for _,v in ipairs(A.queue) do list[#list+1]=v end
  else list[1]=A.queue[A.index] end
  for i,v in ipairs(list) do
    local info,err=Core.refresh_info(A.project,v)
    if not info then error(err,0) end
    if info.len>Core.MAX_ITEM_SECONDS then error("1アイテムは60分以内にしてください。",0) end
    if info.locked then error("ロックされたアイテムがあります。ロックを解除してください。",0) end
    if S.basis=="lufs" and info.channels>2 then error("LUFS-Mはモノ／ステレオ対応です。多チャンネルはピークを選択してください。",0) end
    if not confirm_long_lufs(info,S.basis) then
      sync_selection()
      notice("長尺アイテムのLUFS解析をキャンセルし、選択を解除しました。")
      return
    end
    list[i]=info
  end
  local total_work=0
  for i=1,#list do total_work=total_work+(list[i].len or 0) end
  A.batch={list=list,i=1,settings=copy(S),entries={},
    total_work=total_work,done_work=0}
  A.analysis=nil;A.detector=nil;A.data=nil;A.audio_cache={};A.ready=false;invalidate_wave_surface(true);collectgarbage("collect")
  notice("実行用に全対象を再解析しています。")
  batch_next()
end
local function work_step()
 if not Media.ready() then return end
  -- Time-budgeted pipeline. Peak retrieval, detection, cached batch items and
  -- Loudness blocks can all advance within the same frame until the budget is used.
  local until_time=R.time_precise()+0.012
  while R.time_precise()<until_time do
    if A.analysis then
      local j=A.analysis
      if Core.read_step(j) then
        A.analysis=nil
        if j.context=="preview" then store_audio(j);A.data=j end
        A.detector=Core.detector(j,A.batch and A.batch.settings or S)
        A.detector.context=j.context
        invalidate_wave_surface(true)
      end
    elseif A.detector then
      local d=A.detector
      if Core.detect_step(d,32768) then
        A.detector=nil
        if d.context=="batch" then
          local b=A.batch
          b.entries[#b.entries+1]={info=d.data.info,chunk=d.data.chunk,regions=d.regions}
          b.done_work=(b.done_work or 0)+(d.data.info.len or 0)
          b.i=b.i+1
          d.data=nil;collectgarbage("step",400)
          batch_next() -- may immediately provide another cached detector/job
        else
          A.regions,A.raw,A.ready=d.regions,d.raw,true
          invalidate_wave_surface()
          notice(#d.regions==0 and (S.action=="delete" and "音あり区間は0です。実行すると対象全体を削除します。" or "分割境界はありません。")
            or string.format("%d区間を検出。設定を調整してから実行できます。",#d.regions))
          break
        end
      end
    else
      break
    end
  end
end

local W,H=722,728
local C={
  bg={0.018,0.030,0.055}, bg2={0.030,0.090,0.180},
  panel={0.040,0.068,0.110}, panel2={0.055,0.125,0.205},
  field={0.018,0.040,0.080}, edge={0.145,0.285,0.445}, edge2={0.360,0.650,0.900},
  text={0.955,0.980,1.000}, muted={0.690,0.780,0.875}, faint={0.390,0.505,0.635},
  accent={0.120,0.490,0.980}, accent2={0.650,0.895,1.000}, accent3={0.045,0.235,0.520},
  focus={0.225,0.610,1.000}, focus2={0.690,0.900,1.000}, ink={0.018,0.075,0.160},
  hover={0.430,0.790,1.000}, warn={1.000,0.755,0.490}, red={1.000,0.230,0.300}, quiet={0.300,0.360,0.440}
}
local fonts={"Yu Gothic UI","Segoe UI","Consolas"}
if BLT_MAC then fonts={"Hiragino Sans","Helvetica Neue","Menlo"} end
if R.GetOS():match("Linux") then fonts={"sans-serif","sans-serif","monospace"} end

local scale,ox,oy=1,0,0
 BLT.viewport(scale,gfx.ext_retina or 1);local frame_clock,frame_dt,particle_dt,anim_time=R.time_precise(),1/60,1/60,0
local animations_active=true
local animation_speed=1
local EFFECT_IDLE_TAIL=2.5
local EFFECT_COAST=0.70
local effect_activity_until=R.time_precise()+EFFECT_IDLE_TAIL
local redraw_dirty=true
local next_draw_time=0
local last_raw_mouse_x,last_raw_mouse_y,last_raw_mouse_cap=nil,nil,nil
local last_window_w,last_window_h=nil,nil
local last_window_active=nil
local function wake_visuals(now)
  now=now or R.time_precise(); redraw_dirty=true
  effect_activity_until=max(effect_activity_until,now+EFFECT_IDLE_TAIL)
  if next_draw_time==math.huge then next_draw_time=now end
end
local function visual_speed(now)
  local remain=effect_activity_until-(now or R.time_precise())
  if remain<=0 then return 0 end
  if remain>=EFFECT_COAST then return 1 end
  local t=clamp(remain/EFFECT_COAST,0,1)
  return t*t*(3-2*t)
end
local motion={}
local icon_particles,icon_clock,icon_serial={},0,0
local widgets={}
local edit=nil
local down_last,pressed=false,nil
local mouse_x,mouse_y=-1,-1
local hover_hint=""

local function sx(x) return ox+x*scale end
local function sy(y) return oy+y*scale end
local function color(c,a) gfx.set(c[1],c[2],c[3],a or 1) end
local function rect(x,y,w,h,c,a) color(c,a); gfx.rect(sx(x),sy(y),w*scale,h*scale,1) end
local function line(x,y,x2,y2,c,a) color(c,a); gfx.line(sx(x),sy(y),sx(x2),sy(y2),1) end
local function disc(x,y,r,c,a) color(c,a); gfx.circle(sx(x),sy(y),r*scale,1,1) end

local function font(size,kind,bold) BLT.font(size,kind,bold,scale,fonts) end
local function label(text,x,y,size,c,kind,w,h,flags,bold,literal)
  local shown=literal and tostring(text) or Language.message(text)
  font(size,kind,bold); color(c or C.text); gfx.x,gfx.y=sx(x),sy(y)
  if shown~=tostring(text) and w then shown=BLT.ui.fit(shown,w*scale) end
  gfx.drawstr(shown,flags or 0,sx(x+(w or 700)),sy(y+(h or size+8)))
end
local function measure(text,size,kind,bold) font(size,kind,bold);return BLT.metricsFor(Language.message(text))/scale end
local function right_label(text,right,y,size,c,kind,bold)
  local tw=measure(text,size,kind,bold); label(text,right-tw,y,size,c,kind,tw+2,size+9,0,bold)
end
local function gradient(x,y,w,h,a,b,alpha1,alpha2,vertical)
  local aa1=alpha1 or 1; local aa2=alpha2==nil and aa1 or alpha2
  local n=max(1,(vertical and h or w)*scale)
  if (a==b or (a[1]==b[1] and a[2]==b[2] and a[3]==b[3])) and aa1==aa2 then rect(x,y,w,h,a,aa1); return end
  if n<=1.01 then rect(x,y,w,h,a,aa1); return end
  local dr,dg,db=(b[1]-a[1])/n,(b[2]-a[2])/n,(b[3]-a[3])/n
  local da=(aa2-aa1)/n
  gfx.gradrect(sx(x),sy(y),w*scale,h*scale,a[1],a[2],a[3],aa1,
    vertical and 0 or dr,vertical and 0 or dg,vertical and 0 or db,vertical and 0 or da,
    vertical and dr or 0,vertical and dg or 0,vertical and db or 0,vertical and da or 0)
end
local function glow_line(x,y,x2,y2,c,strength)
  strength=strength or 1
  line(x,y-3,x2,y2-3,c,0.025*strength); line(x,y+3,x2,y2+3,c,0.025*strength)
  line(x,y-2,x2,y2-2,c,0.055*strength); line(x,y+2,x2,y2+2,c,0.055*strength)
  line(x,y-1,x2,y2-1,c,0.13*strength); line(x,y+1,x2,y2+1,c,0.13*strength)
  line(x,y,x2,y2,c,0.95*strength)
end
local function cut_panel(x,y,w,h,cut,c,a,edge,edge_a,top_left)
  local tl=top_left and cut or 0
  local pts={{x+tl,y},{x+w,y},{x+w,y+h-cut},{x+w-cut,y+h},{x,y+h},{x,y+tl}}
  local cx,cy=x+w/2,y+h/2
  color(c,a)
  for i=1,#pts do local p,q=pts[i],pts[i%#pts+1]; gfx.triangle(sx(cx),sy(cy),sx(p[1]),sy(p[2]),sx(q[1]),sy(q[2])) end
  if edge then for i=1,#pts do local p,q=pts[i],pts[i%#pts+1]; line(p[1],p[2],q[1],q[2],edge,edge_a or 1) end end
end
local function finish_corners(x,y,w,h,cut,top_left,edge,a)
  color(C.bg)
  gfx.triangle(sx(x+w-cut-1),sy(y+h+1),sx(x+w+1),sy(y+h-cut-1),sx(x+w+1),sy(y+h+1))
  if top_left then gfx.triangle(sx(x-1),sy(y-1),sx(x+cut+1),sy(y-1),sx(x-1),sy(y+cut+1)) end
  line(x+w,y+h-cut,x+w-cut,y+h,edge,a)
  if top_left then line(x,y+cut,x+cut,y,edge,a) end
end
local function animate(key,target)
 if BLT.presetRevision and BLT.presetMotionSeen[key]~=BLT.presetRevision then
  BLT.presetMotionSeen[key]=BLT.presetRevision;motion[key]=target;return target
 end
  local p=motion[key]; if p==nil then p=target end
  local v=p+(target-p)*BLT.blend(frame_dt); motion[key]=v; return v
end
local function particle_hash(n,salt)
  local v=math.sin(n*12.9898+salt*78.233)*43758.5453; return v-floor(v)
end
local function inside(x,y,w,h) return mouse_x>=x and mouse_x<=x+w and mouse_y>=y and mouse_y<=y+h end
local function register(id,x,y,w,h,fn,hint,enabled)
  widgets[#widgets+1]={id=id,x=x,y=y,w=w,h=h,fn=fn,hint=hint,enabled=enabled~=false}
  if inside(x,y,w,h) and hint then hover_hint=hint end
end
local function fmt(n)
  if abs(n-floor(n+0.5))<1e-8 then return tostring(floor(n+0.5)) end
  return string.format("%.2f",n):gsub("0+$",""):gsub("%.$","")
end

local function draw_background()
  rect(0,0,W,H+22,C.bg)
  disc(W-30,42,145,C.accent,0.018)
  disc(8,H-72,120,C.bg2,0.034)
  gradient(0,0,W,90,C.bg2,C.bg,0.22,0,true)

  line(17,138,17,668,C.edge2,0.14)
  for y=147,665,18 do line(17,y,22,y,C.edge2,0.12) end
end

local chameleon_host_refresh=function() invalidate_wave_surface(true) end
local C_DEFAULT={}
for k,v in pairs(C) do
  if type(v)=="table" and type(v[1])=="number" and type(v[2])=="number" and type(v[3])=="number" then
    C_DEFAULT[k]={v[1],v[2],v[3]}
  end
end
local Chameleon={
  enabled=R.GetExtState(SECTION,"chameleon")=="1",
  signature=nil,poll_at=0,poll_interval=3.0,
}
local Chrome={window=nil,mouseDown=false,drag=nil,resize=nil,mouseActive=false,requestClose=false,requestReset=false,
  chameleonPressed=false,resizeCursors={},resizeCursorMode=nil,titleH=26,windowTitle='BLT Auto Trim Split',titleText='A U T O   T R I M   /   S P L I T',
  minW=560,minH=646,mint={0.38,0.88,0.72},ice={0.65,0.895,1.0},red={1.0,0.27,0.34},
  isWindows=R.GetOS():match("Win")~=nil,resizeEdge=6,resizeCornerBand=8,resizeCornerSpan=24,resizeTopLeftGuard=30,resizeTopRightGuard=110,
  tooltipHover=nil,tooltipSince=0,tooltipVisible=false,tooltipDelay=.70,
  cursorId={we=32644,ns=32645,nwse=32642,nesw=32643,arrow=32512}}
Chrome.font=Chrome.isWindows and "Segoe UI" or (BLT_MAC and "Helvetica Neue" or "sans-serif")
local CHROME_DEFAULT={
  mint={Chrome.mint[1],Chrome.mint[2],Chrome.mint[3]},
  ice={Chrome.ice[1],Chrome.ice[2],Chrome.ice[3]},
}
local function chameleon_notify(text)
  notice(text,false)
end

-- CHAMELEON THEME ADAPTER
--
-- Theme adapter interface:
--   Required palette tables : C, C_DEFAULT
--   Optional chrome colors   : Chrome, CHROME_DEFAULT
--   Persistence              : SECTION / ExtState key "chameleon"
--   Host hooks               : notice(), wake_visuals(), redraw_dirty
--   UI integration           : Chameleon.enabled / Chameleon.set(...)
--   Main-loop integration    : Chameleon.tick(now)
--
Chameleon.keys={
  -- Main/surface colors
  "col_main_bg2","col_main_bg","col_arrangebg","col_tracklistbg","col_mixerbg",
  "genlist_bg","col_tl_bg","col_trans_bg","col_tr1_bg","col_tr2_bg",
  "col_main_editbk","col_transport_editbk","col_buttonbg",

  -- Text colors
  "col_main_text2","col_main_text","genlist_fg","col_tcp_text",
  "col_toolbar_text","col_toolbar_text_on","col_tl_fg","col_tl_fg2","col_trans_fg",

  -- Selection / active / accent colors
  "col_seltrack","col_seltrack2","genlist_selbg",
  "col_tl_bgsel","toolbararmed_color","col_main_resize2",
  "selitem_dot","selitem_tag","activetake_tag",
  "col_routinghl1","col_routinghl2","track_lanesolo_tabcol",

  -- REAPER's own highlight / shadow / separators
  "col_main_3dhl","col_main_3dsh","genlist_grid","col_toolbar_frame",
  "col_tr1_divline","col_tr2_divline","docker_shadow",
}
local function ccopy(c) return {c[1],c[2],c[3]} end
local function cmix(a,b,t)
  t=math.max(0,math.min(1,t or 0))
  return {a[1]+(b[1]-a[1])*t,a[2]+(b[2]-a[2])*t,a[3]+(b[3]-a[3])*t}
end
local function clum(c) return c[1]*0.2126+c[2]*0.7152+c[3]*0.0722 end
local function csat(c)
  local hi=math.max(c[1],c[2],c[3]); local lo=math.min(c[1],c[2],c[3])
  return hi-lo
end
local function cclamp(c)
  return {
    math.max(0,math.min(1,c[1])),
    math.max(0,math.min(1,c[2])),
    math.max(0,math.min(1,c[3])),
  }
end
local function cshift_luma(c,target)
  local l=clum(c)
  target=math.max(0,math.min(1,target))
  if math.abs(target-l)<1e-5 then return ccopy(c) end
  if target<l then
    local t=(l-target)/math.max(l,1e-9)
    return cmix(c,{0,0,0},t)
  end
  local t=(target-l)/math.max(1-l,1e-9)
  return cmix(c,{1,1,1},t)
end
local function cboost_sat(c,factor)
  local l=clum(c)
  return cclamp({
    l+(c[1]-l)*factor,
    l+(c[2]-l)*factor,
    l+(c[3]-l)*factor,
  })
end
local function dominant_surface(colors,fallback)
  local list={}
  for i=1,#colors do
    local c=colors[i]
    if c then list[#list+1]={c=c,l=clum(c)} end
  end
  if #list==0 then return ccopy(fallback) end
  table.sort(list,function(a,b) return a.l<b.l end)
  local median
  local n=#list
  if n%2==1 then median=list[(n+1)//2].l
  else median=(list[n//2].l+list[n//2+1].l)*.5 end
  local best,bestd=list[1],math.huge
  for i=1,n do
    local d=math.abs(list[i].l-median)
    if d<bestd then best,bestd=list[i],d end
  end
  return ccopy(best.c)
end
local function generated_text(bg)
  -- Text polarity follows the ACTUAL palette background, not a theme text slot.
  -- This guarantees black-ish text on light themes and white-ish text on dark themes.
  local l=clum(bg)
  if l>=0.56 then
    return {0.070,0.075,0.082},false
  elseif l<=0.44 then
    return {0.935,0.945,0.958},true
  end
  -- Mid-grey themes: choose the side with the larger luminance separation.
  if l>=0.50 then return {0.075,0.080,0.088},false end
  return {0.935,0.945,0.958},true
end
local function fit_accent_to_bg(accent,bg,text_is_light)
  local out=ccopy(accent)
  local delta=math.abs(clum(out)-clum(bg))
  if delta>=0.17 then return out end
  if text_is_light then
    -- Dark background: lift the accent without washing it toward full white.
    local target=math.min(.78,clum(bg)+.28)
    return cshift_luma(out,target)
  end
  -- Light background: darken the accent so controls remain visible.
  local target=math.max(.16,clum(bg)-.30)
  return cshift_luma(out,target)
end
local function contrast_anchor_bg(bg)
  local l=clum(bg)
  if l<0.50 then
    local target=math.max(.025,l-(.50-l)*.16-.018)
    return cshift_luma(bg,target)
  end
  local target=math.min(.975,l+(l-.50)*.10+.010)
  return cshift_luma(bg,target)
end
local function contrast_surface(c,old_bg,new_bg,factor,min_gap,max_gap)
  local delta=clum(c)-clum(old_bg)
  local sign=delta<0 and -1 or 1
  local mag=math.abs(delta)*factor
  if min_gap and mag<min_gap then mag=min_gap end
  if max_gap and mag>max_gap then mag=max_gap end
  return cshift_luma(c,math.max(.01,math.min(.99,clum(new_bg)+sign*mag)))
end
local function theme_color(key)
  local ok,native=pcall(R.GetThemeColor,key,0)
  if not ok or type(native)~="number" or native==-1 then return nil,native end
  local okc,r,g,b=pcall(R.ColorFromNative,native)
  if not okc or type(r)~="number" or type(g)~="number" or type(b)~="number" then return nil,native end
  return {r/255,g/255,b/255},native
end
local function first_near(map,bg,keys,max_delta)
  for i=1,#keys do
    local c=map[keys[i]]
    if c and math.abs(clum(c)-clum(bg))<=(max_delta or .18) then return ccopy(c) end
  end
  return nil
end
local function best_contrast_color(map,bg,keys,min_delta)
  local bg_l=clum(bg)
  local best,best_score=nil,-1
  for i=1,#keys do
    local c=map[keys[i]]
    if c then
      local delta=math.abs(clum(c)-bg_l)
      if delta>=(min_delta or 0) then
        local score=delta+csat(c)*.20
        if score>best_score then best,best_score=c,score end
      end
    end
  end
  return best and ccopy(best) or nil
end
local function theme_edge_role(map,bg,dark,highlight)
  local keys
  if highlight then
    keys={"col_main_3dhl","col_toolbar_frame","genlist_grid","col_tl_fg2","col_tr1_divline","col_tr2_divline"}
  else
    keys={"col_main_3dsh","docker_shadow","genlist_grid","col_tr1_divline","col_tr2_divline"}
  end
  local bg_l=clum(bg)
  local best,best_score=nil,-1
  for i=1,#keys do
    local c=map[keys[i]]
    if c then
      local delta=clum(c)-bg_l
      local wanted=highlight and (dark and delta>0 or (not dark and delta<0))
        or (dark and delta<0 or (not dark and delta>0))
      local score=math.abs(delta)+(wanted and .16 or 0)
      if score>best_score then best,best_score=c,score end
    end
  end
  return best and ccopy(best) or nil
end
local function usable_theme_text(map,bg,keys,generated)
  local c=best_contrast_color(map,bg,keys,.28)
  if not c then return ccopy(generated) end
  -- Never let a theme text slot invert into poor contrast after user transforms.
  if math.abs(clum(c)-clum(bg))<.28 then return ccopy(generated) end
  return c
end

local function best_theme_accent(map,bg)
  local keys={
    "genlist_selbg","col_seltrack","toolbararmed_color","col_tl_bgsel",
    "col_toolbar_text_on","col_main_resize2","selitem_dot","selitem_tag",
    "activetake_tag","col_routinghl1","col_routinghl2","track_lanesolo_tabcol",
    "col_tl_fg",
  }
  local bg_l=clum(bg)
  local best,best_score=nil,-1
  for i=1,#keys do
    local c=map[keys[i]]
    if c then
      local sat=csat(c)
      local delta=math.abs(clum(c)-bg_l)
      local score=sat*1.45+delta*.72
      if keys[i]=="genlist_selbg" or keys[i]=="col_seltrack" or keys[i]=="toolbararmed_color" then
        score=score+.12
      end
      -- Ignore almost-background colors unless no better candidate exists.
      if delta<.035 and sat<.035 then score=score-.35 end
      if score>best_score then best,best_score=c,score end
    end
  end
  return best and ccopy(best) or ccopy(C_DEFAULT.accent)
end
local function theme_snapshot()
  local map,raw={},{}
  for i=1,#Chameleon.keys do
    local key=Chameleon.keys[i]
    local c,native=theme_color(key)
    map[key]=c
    raw[#raw+1]=tostring(native or -1)
  end
  return map,table.concat(raw,":")
end
local function build_chameleon_palette(map)
  -- Derive a stable BLT palette from REAPER's current theme.
  -- Missing/unsupported keys are ignored and each semantic role has a safe
  -- fallback, which is important for custom and older themes.
  local sampled_bg=dominant_surface({
    map.col_main_bg2,
    map.col_main_bg,
    map.col_tracklistbg,
    map.genlist_bg,
    map.col_arrangebg,
  },C_DEFAULT.bg)

  local sampled_l=clum(sampled_bg)
  local dark=sampled_l<0.50

  local sampled_panel=
    first_near(map,sampled_bg,{
      "col_main_bg","col_tracklistbg","col_mixerbg","genlist_bg",
      "col_seltrack2","col_tl_bg","col_tr1_bg","col_tr2_bg",
    },.16)

  local sampled_field=
    first_near(map,sampled_bg,{
      "col_main_editbk","col_transport_editbk","genlist_bg","col_buttonbg",
      "col_trans_bg",
    },.14)

  if not sampled_panel then
    sampled_panel=cshift_luma(sampled_bg,dark and math.min(.92,sampled_l+.040) or math.max(.08,sampled_l-.040))
  end
  if not sampled_field then
    sampled_field=cshift_luma(sampled_bg,dark and math.min(.92,sampled_l+.018) or math.min(.96,sampled_l+.020))
  end
  local bg=contrast_anchor_bg(sampled_bg)
  local panel=contrast_surface(sampled_panel,sampled_bg,bg,1.48,.030,.105)
  local field=contrast_surface(sampled_field,sampled_bg,bg,1.38,.020,.085)

  if dark then
    if clum(panel)<=clum(bg)+.022 then panel=cshift_luma(panel,math.min(.94,clum(bg)+.038)) end
  else
    if clum(panel)>=clum(bg)-.022 then panel=cshift_luma(panel,math.max(.06,clum(bg)-.038)) end
  end

  -- Generated polarity remains the safety net; a readable theme text color can
  -- contribute some hue/temperature without sacrificing contrast.
  local generated,text_is_light=generated_text(bg)
  local theme_text=usable_theme_text(map,bg,{
    "col_main_text2","col_main_text","genlist_fg","col_tcp_text",
    "col_toolbar_text","col_tl_fg","col_trans_fg",
  },generated)
  local textcol=cmix(generated,theme_text,.18)
  local muted=cmix(textcol,bg,dark and .28 or .30)
  local faint=cmix(textcol,bg,dark and .50 or .52)

  local accent=best_theme_accent(map,bg)
  accent=cboost_sat(accent,dark and 1.18 or 1.14)
  accent=fit_accent_to_bg(accent,bg,text_is_light)
  local al=clum(accent)
  if dark and al<clum(bg)+.22 then
    accent=cshift_luma(accent,math.min(.82,clum(bg)+.26))
  elseif not dark and al>clum(bg)-.22 then
    accent=cshift_luma(accent,math.max(.12,clum(bg)-.28))
  end

  -- Use REAPER's own highlight/shadow roles when available, but only as a
  -- restrained contribution so an unusual theme cannot destroy readability.
  local theme_hi=theme_edge_role(map,bg,dark,true)
  local theme_sh=theme_edge_role(map,bg,dark,false)
  local edge_base=cmix(bg,textcol,dark and .20 or .18)
  local edge_active=cmix(accent,textcol,dark and .12 or .09)
  local edge=theme_sh and cmix(edge_base,theme_sh,.28) or edge_base
  local edge2=theme_hi and cmix(edge_active,theme_hi,.24) or edge_active

  local out={}
  out.bg=ccopy(bg)
  out.bg2=cmix(bg,accent,dark and .080 or .065)
  out.panel=panel
  out.panel2=cmix(panel,accent,dark and .105 or .085)
  out.field=field

  out.text=textcol
  out.muted=muted
  out.faint=faint

  out.edge=edge
  out.edge2=edge2

  out.accent=accent
  out.accent2=cmix(accent,textcol,dark and .14 or .09)
  out.accent3=cmix(accent,bg,dark and .48 or .46)
  out.focus=cmix(accent,textcol,dark and .06 or .04)
  out.focus2=cmix(accent,textcol,dark and .20 or .12)
  out.ink=cmix(bg,accent,dark and .16 or .12)
  out.hover=cmix(accent,textcol,dark and .15 or .10)

  out.warn=fit_accent_to_bg(C_DEFAULT.warn,bg,text_is_light)
  out.red=fit_accent_to_bg(C_DEFAULT.red,bg,text_is_light)
  return out
end

function Chameleon.restore()
  for k,v in pairs(C_DEFAULT) do C[k]=ccopy(v) end
  Chrome.mint=ccopy(CHROME_DEFAULT.mint)
  Chrome.ice=ccopy(CHROME_DEFAULT.ice)
  if chameleon_host_refresh then chameleon_host_refresh() end
end

function Chameleon.apply(palette)
  for k,v in pairs(palette) do C[k]=v end
  Chrome.mint=ccopy(C.accent2)
  Chrome.ice=ccopy(C.focus2)
  if chameleon_host_refresh then chameleon_host_refresh() end
end

function Chameleon.refresh(force)
  if not Chameleon.enabled then return false end
  local map,sig=theme_snapshot()
  if not force and sig==Chameleon.signature then return false end
  Chameleon.signature=sig
  Chameleon.apply(build_chameleon_palette(map))
  redraw_dirty=true
  return true
end

function Chameleon.set(on)
  Chameleon.enabled=on and true or false
  BLT.store(SECTION,"chameleon",Chameleon.enabled and "1" or "0",true)
  Chameleon.signature=nil

  if Chameleon.enabled then
    Chameleon.refresh(true)
    chameleon_notify("CHAMELEON  REAPERテーマに擬態")
  else
    Chameleon.restore()
    redraw_dirty=true
    chameleon_notify("CHAMELEON  オリジナル配色")
  end
  wake_visuals(R.time_precise())
end

function Chameleon.tick(now)
  if not Chameleon.enabled or now<Chameleon.poll_at then return false end
  Chameleon.poll_at=now+Chameleon.poll_interval
  return Chameleon.refresh(false)
end

-- Icon-only color separation.
-- The main UI palette remains untouched; this only keeps the three overlapping
-- Chameleon circles visually distinct even when a REAPER theme is nearly mono-hued.
local function rgb_to_hsv(c)
  local r,g,b=c[1],c[2],c[3]
  local mx=math.max(r,g,b)
  local mn=math.min(r,g,b)
  local d=mx-mn
  local h=0

  if d>1e-6 then
    if mx==r then
      h=((g-b)/d)%6
    elseif mx==g then
      h=(b-r)/d+2
    else
      h=(r-g)/d+4
    end
    h=h/6
  end

  local s=(mx<=1e-6) and 0 or d/mx
  return h,s,mx
end

local function hsv_to_rgb(h,s,v)
  h=h%1
  local i=math.floor(h*6)
  local f=h*6-i
  local p=v*(1-s)
  local q=v*(1-f*s)
  local t=v*(1-(1-f)*s)
  i=i%6

  if i==0 then return {v,t,p}
  elseif i==1 then return {q,v,p}
  elseif i==2 then return {p,v,t}
  elseif i==3 then return {p,q,v}
  elseif i==4 then return {t,p,v}
  else return {v,p,q}
  end
end

function Chameleon.compute_icon_colors()
  if not Chameleon.enabled then
    return C.muted,C.faint,C.edge
  end

  local h,s,v=rgb_to_hsv(C.accent)
  -- Only the icon gets a saturation floor; the actual BLT theme does not.
  s=math.max(s,.46)

  -- Preserve the theme's base hue, but fan the other two colors away from it.
  -- +/- 0.19 ~= 68 degrees: clearly different without turning into a rainbow badge.
  local c1=hsv_to_rgb(h,      s,                v)
  local c2=hsv_to_rgb(h+.19, math.max(.42,s*.90), v)
  local c3=hsv_to_rgb(h-.19, math.max(.42,s*.86), v)

  return c1,c2,c3
end
function Chameleon.icon_colors()
 local c=Chameleon.bltIcon;local a=C.accent
 if c and c.on==Chameleon.enabled and c.r==a[1] and c.g==a[2] and c.b==a[3] then return c[1],c[2],c[3] end
 local x,y,z=Chameleon.compute_icon_colors()
 if not Chameleon.enabled then for _,v in ipairs({x,y,z}) do local gray=v[1]*.2126+v[2]*.7152+v[3]*.0722;for i=1,3 do v[i]=gray+(v[i]-gray)*.12 end end end
 Chameleon.bltIcon={x,y,z,on=Chameleon.enabled,r=a[1],g=a[2],b=a[3]};return x,y,z
end

local function titlebar_api_ready()
  local required={"JS_Window_Find","JS_Window_IsWindow","JS_Window_GetRect","JS_Window_SetPosition","JS_Window_SetStyle"}
  if Chrome.isWindows then
    required[#required+1]="JS_Mouse_LoadCursor"
    required[#required+1]="JS_Mouse_SetCursor"
  end
  for _,name in ipairs(required) do
    if type(R[name])~="function" then
      return false,"カスタムタイトルバーには js_ReaScriptAPI が必要です。\nReaPack から js_ReaScriptAPI をインストールしてください。"
    end
  end
  return true
end

local function gfx_window_handle()
  if Chrome.window and R.JS_Window_IsWindow(Chrome.window) then return Chrome.window end
  Chrome.window=R.JS_Window_Find(Chrome.windowTitle,true)
  return Chrome.window
end

local function apply_custom_window_style(target_w,target_h)
  local hwnd=gfx_window_handle()
  if not hwnd then return false end
  local ok,l,t=WindowGeometry.JS_Window_GetRect(hwnd)
  if not R.JS_Window_SetStyle(hwnd,"POPUP") then return false end
  if ok then BLT.position(hwnd,l,t,target_w,target_h,"","") end
  return true
end

local function reset_window_size()
  local hwnd=gfx_window_handle()
  if not hwnd then return end
  local ok,l,t=WindowGeometry.JS_Window_GetRect(hwnd)
  if ok then BLT.position(hwnd,l,t,W,H+Chrome.titleH,"","") end
  BLT.store(SECTION,"window_w",tostring(W),true)
  BLT.store(SECTION,"window_h",tostring(H+Chrome.titleH),true)
  last_window_w,last_window_h=W,H+Chrome.titleH
  invalidate_wave_surface(true)
end

local function chrome_resize_hit(mx,my)
  local w,h=gfx.w,gfx.h
  if not w or not h or w<=0 or h<=0 then return nil end
  if mx<0 or mx>=w or my<0 or my>=h then return nil end
  local edge=Chrome.resizeEdge
  local band=Chrome.resizeCornerBand
  local span=Chrome.resizeCornerSpan
  local bottomBand=my>=h-band
  local bottomSpan=my>=h-span
  local leftBand=mx<band
  local rightBand=mx>=w-band
  local leftSpan=mx<span
  local rightSpan=mx>=w-span
  if (bottomBand and leftSpan) or (leftBand and bottomSpan) then return "lb" end
  if (bottomBand and rightSpan) or (rightBand and bottomSpan) then return "rb" end
  -- Upper corners are reserved for ordinary title-bar use. In particular the
  -- close/reset controls must remain clickable right up to the window edge.
  if my<Chrome.titleH then
    if mx<Chrome.resizeTopLeftGuard or mx>=w-Chrome.resizeTopRightGuard then return nil end
  end
  local nearL=mx<edge
  local nearR=mx>=w-edge
  local nearT=my<edge
  local nearB=my>=h-edge
  if nearL then return "l" end
  if nearR then return "r" end
  if nearT then return "t" end
  if nearB then return "b" end
  return nil
end

local function resize_cursor_kind(mode)
  if mode=="l" or mode=="r" then return "we" end
  if mode=="t" or mode=="b" then return "ns" end
  if mode=="lt" or mode=="rb" then return "nwse" end
  if mode=="rt" or mode=="lb" then return "nesw" end
  return nil
end
local function set_resize_cursor(mode)
  if not Chrome.isWindows then return end
  local kind=resize_cursor_kind(mode)
  if kind then
    local cursor=Chrome.resizeCursors[kind]
    if not cursor then cursor=R.JS_Mouse_LoadCursor(Chrome.cursorId[kind]); Chrome.resizeCursors[kind]=cursor end
    if cursor then R.JS_Mouse_SetCursor(cursor) end
    Chrome.resizeCursorMode=kind
  elseif Chrome.resizeCursorMode then
    local cursor=Chrome.resizeCursors.arrow
    if not cursor then cursor=R.JS_Mouse_LoadCursor(Chrome.cursorId.arrow); Chrome.resizeCursors.arrow=cursor end
    if cursor then R.JS_Mouse_SetCursor(cursor) end
    Chrome.resizeCursorMode=nil
  end
end
local function titlebar_cleanup() set_resize_cursor(nil) end

local function begin_window_resize(mode)
  local hwnd=gfx_window_handle()
  if not hwnd or not mode then return false end
  local ok,l,t,r,b=WindowGeometry.JS_Window_GetRect(hwnd)
  if not ok then return false end
  local sx,sy=WindowGeometry.GetMousePosition()
  Chrome.resize={mode=mode,mouseX=sx,mouseY=sy,left=l,top=t,right=r,bottom=b}
  Chrome.drag=nil
  return true
end

local function update_window_resize()
  local d=Chrome.resize
  if not d then return end
  local hwnd=gfx_window_handle()
  if not hwnd then Chrome.resize=nil; return end
  local sx,sy=WindowGeometry.GetMousePosition()
  local dx,dy=sx-d.mouseX,sy-d.mouseY
  local l,t,r,b=d.left,d.top,d.right,d.bottom
  if d.mode:find("l",1,true) then l=math.min(d.left+dx,r-Chrome.minW) end
  if d.mode:find("r",1,true) then r=math.max(d.right+dx,l+Chrome.minW) end
  if d.mode:find("t",1,true) then t=math.min(d.top+dy,b-Chrome.minH) end
  if d.mode:find("b",1,true) then b=math.max(d.bottom+dy,t+Chrome.minH) end
  BLT.position(hwnd,math.floor(l+.5),math.floor(t+.5),math.max(Chrome.minW,math.floor(r-l+.5)),math.max(Chrome.minH,math.floor(b-t+.5)),"","")
end

local function clear_chrome_tooltip() BLT.clearTooltip() end

local function custom_titlebar() BLT.bar() end

local function choice_card(id,title,code,x,y,w,h,active,fn,hint,enabled)
  enabled=enabled~=false
  local hovered=inside(x,y,w,h) and enabled
  local a=animate("choice_"..id,active and 1 or (hovered and 0.30 or 0))
  gradient(x,y,w,h,C.panel2,C.panel,0.28+0.28*a,0.72)
  if a>0.01 then
    gradient(x+3,y,w-3,h,C.accent3,C.accent3,0.18*a,0)
    rect(x,y+8,3,h-16,C.accent2,0.75*a)
    glow_line(x+8,y,x+62,y,C.accent2,0.28*a)
  end
  line(x,y,x+w,y,C.edge2,0.20+0.43*a); line(x,y+h,x+w,y+h,C.edge,0.33)
  finish_corners(x,y,w,h,8,true,C.edge2,0.26+0.38*a)
  label(title,x+14,y+17,15,enabled and (active and C.text or C.muted) or C.faint,1,w-28,24,0,true)
  right_label(code,x+w-12,y+4,7,active and C.accent2 or C.faint,3,true)
  register(id,x,y,w,h,fn,hint,enabled)
end

local function edge_mode_button(x,y,w,h,fn,enabled)
  local active=S.edge_mode
  local hovered=inside(x,y,w,h) and enabled
  local a=animate("edge_mode",active and 1 or (hovered and 0.20 or 0))
  local gold={1.000,0.885,0.440}
  local light={1.000,0.965,0.745}
  local dark={0.280,0.210,0.075}
  if active then
    for spread=6,1,-1 do
      local alpha=0.006+0.003*(7-spread)
      cut_panel(x-spread,y-spread,w+2*spread,h+2*spread,8+spread,
        gold,alpha,nil,nil,true)
    end
  end
  cut_panel(x,y,w,h,8,C.panel,0.98,active and gold or C.edge2,active and 0.95 or 0.30,true)
  gradient(x+2,y+2,w-4,h-4,gold,dark,0.46*a,0.75*a,true)
  if active then
    glow_line(x+9,y,x+w-9,y,gold,0.85)
    glow_line(x+9,y+h,x+w-9,y+h,gold,0.65)
    disc(x+14,y+30,5,gold,0.12)
    disc(x+14,y+30,2,gold,1)
  end
  label("EDGE MODE",x,y+5,13,active and light or C.muted,3,w,19,1,true)
  label(active and "ON / 両端のみ" or "OFF",x+17,y+24,9,active and light or C.faint,1,w-25,16,1,true)
  register("edge_mode",x,y,w,h,fn,"ON：最初と最後の有効区間の外側だけを処理します。内部の無音は残し、プリ／ポストロールは外側の両端に適用します。",enabled)
end

local function segment_button(id,text,x,y,w,h,active,fn,hint,enabled)
  enabled=enabled~=false
  local hovered=inside(x,y,w,h) and enabled
  local a=animate("segment_"..id,active and 1 or (hovered and 0.28 or 0))
  rect(x,y,w,h,C.panel,0.98)
  gradient(x,y,w,h,C.accent3,C.panel,0.22*a,0)
  line(x,y+h-1,x+w,y+h-1,C.edge2,0.20+0.52*a)
  if active then glow_line(x+12,y+h-1,x+w-12,y+h-1,C.accent2,0.22) end
  finish_corners(x,y,w,h,6,false,C.edge2,0.22+0.42*a)
  label(text,x,y+3,11,enabled and (active and C.text or C.muted) or C.faint,1,w,h-5,5,true)
  register(id,x,y,w,h,fn,hint,enabled)
end

local function toggle_switch(id,text,x,y,w,checked,fn,hint,enabled)
 enabled=enabled~=false;local hot=enabled and inside(x,y,w,26)
 BLT.switch(x,y,animate('toggle_state_'..id,checked and 1 or 0),enabled)
 label(text,x+34,y+1,11.2,enabled and (hot and C.text or C.muted) or C.faint,1,w-34,24,4,false)
 register(id,x,y,w,26,fn,hint,enabled)
end

function A.flash_field(key) A.field_flash[key]=R.time_precise() end
function A.field_flash_value(key)
  local t=A.field_flash[key]; if not t then return 0 end
  local age=R.time_precise()-t
  if age>=1.15 then A.field_flash[key]=nil; return 0 end
  local q=clamp(age/1.15,0,1); return 1-q*q*(3-2*q)
end
function A.update_field_drag(py,fine)
  local d=A.field_drag; if not d then return end
  local dy=d.start_y-py
  if not d.moved and abs(dy)<3 then return end
  d.moved=true; edit=nil
  local inc=Core.steps[d.key] or 1
  local q=dy/3; local ticks=(q<0 and -1 or 1)*floor(abs(q)+.5)
  local old=S[d.key]; local ok,clipped=Core.set_number(S,d.key,d.start_value+ticks*inc)
  if ok then
    if clipped and not d.clipped then A.flash_field(d.key); d.clipped=true elseif not clipped then d.clipped=false end
    if S[d.key]~=old then schedule_settings_changed() end
  end
end
local function commit_edit()
  if not edit then return true end
  local n=tonumber(edit.text)
  if not finite(n) then local key=edit.key;A.flash_field(key);edit=nil;notice("数値を入力できなかったため、元の値へ戻しました。",true);return true end
  local old=S[edit.key]
  local ok,clipped=Core.set_number(S,edit.key,n)
  if not ok then notice(clipped,true); return false end
  if clipped then A.flash_field(edit.key) end
  local changed=S[edit.key]~=old
  edit=nil; if changed then settings_changed() end; return true
end

local function field(key,title,x,y,w,unit,hint,enabled)
  enabled=enabled~=false and not A.batch
  local fh=32
  if title then label(title,x,y-17,9.6,C.muted,1,w,15,0,true) end
  local active=edit and edit.key==key
  local hovered=inside(x,y,w,fh) and enabled
  local a=animate("field_"..key,active and 1 or (hovered and 0.24 or 0))
  local flash=A.field_flash_value(key)
  gradient(x,y,w,fh,C.field,C.panel,0.98,0.56)
  if flash>0 then
    rect(x-4,y-4,w+8,fh+8,C.red,.025*flash); gradient(x,y,w,fh,C.red,C.field,.22*flash,.02*flash,true)
  end
  line(x,y,x+w,y,flash>0 and C.red or C.edge2,0.18+0.35*a+0.45*flash); line(x,y+fh-1,x+w,y+fh-1,C.edge,0.38+0.25*a)
  line(x,y,x,y+fh,flash>0 and C.red or C.accent2,0.22+0.48*a+0.42*flash)
  if a>0.01 then glow_line(x+1,y+fh-1,x+min(70,w-8),y+fh-1,C.accent2,0.26*a) end
  finish_corners(x,y,w,fh,6,false,flash>0 and C.red or C.edge2,0.28+0.38*a+0.42*flash)
  local str=active and edit.text or fmt(S[key])
  local selected=active and edit.selected
  if selected then
    local tw=measure(str,20.5,3,true)
    local right=x+w-43
    local sw=min(w-55,tw+7)
    rect(right-sw,y+5,sw,fh-10,C.focus2,0.90)
    label(str,x+8,y,20.5,C.ink,3,w-51,fh,6,true)
  else
    label(str,x+8,y,20.5,enabled and C.text or C.faint,3,w-51,fh,6,true)
  end
  label(unit,x+w-43,y,8.8,C.faint,3,34,fh,6,true)
  if active and not selected and R.time_precise()%1<0.55 then line(x+8,y+fh-4,x+w-47,y+fh-4,C.accent2,0.72) end
  register("field_"..key,x,y,w,fh,function() edit={key=key,text=fmt(S[key]),selected=true} end,
    (hint or title or key).." ／ 上下ドラッグ・ホイール："..fmt(Core.steps[key] or 1).."刻み",enabled)
end

local function toggle(key) S[key]=not S[key]; settings_changed() end
local function set_choice(key,value) S[key]=value; settings_changed() end

local function trim_icon(x,y)
  local w,h=104,60
  local cy=y+37
  local basis_mix=animate("icon_basis",S.basis=="lufs" and 1 or 0)
  for i=1,7 do
    local phase=anim_time*(0.15+(i%3)*0.035)+i*1.41
    local spread=19+7*basis_mix
    local px=x+52+math.sin(phase*1.22)*spread
    local py=y+35+math.cos(phase*0.87)*(8+2*basis_mix)
    local rr=9+(i%4)*3
    disc(px,py,rr+7,C.accent,0.006)
    disc(px,py,rr,C.accent3,0.010)
  end
  if animations_active then icon_clock=icon_clock+frame_dt end
  while animations_active and icon_clock>=0.085 and #icon_particles<30 do
    icon_clock=icon_clock-0.085; icon_serial=icon_serial+1
    local n=icon_serial
    local h1,h2,h3,h4=particle_hash(n,31),particle_hash(n,32),particle_hash(n,33),particle_hash(n,34)
    local spread=43+10*basis_mix
    icon_particles[#icon_particles+1]={x=x+32+h1*spread,y=y+49+(h2-.5)*4,vx=(h3-.5)*(7+3*basis_mix),vy=8+h4*8,life=1.8+h2*1.2,age=0,r=.45+h1*.55,phase=h3*6.28}
  end
  for i=#icon_particles,1,-1 do
    local p=icon_particles[i]; p.age=p.age+particle_dt
    if p.age>=p.life then table.remove(icon_particles,i) else
      local t=p.age/p.life; local e=math.sin(math.pi*t)^2
      local px=p.x+p.vx*p.age+math.sin(p.age*1.4+p.phase)*2.3
      local py=p.y-p.vy*p.age
      disc(px,py,p.r+3.2,C.accent,0.022*e); disc(px,py,p.r+1.3,C.accent2,0.070*e); disc(px,py,p.r,C.focus2,0.56*e)
    end
  end

  line(x+12,cy,x+92,cy,C.edge2,0.28)
  local peak_bars={3,5,4,9,5,24,6,4,19,5,8,4,5,3}
  local lufs_bars={5,7,9,11,13,15,16,15,14,12,10,8,6,5}
  for i=1,#peak_bars do
    local bh=peak_bars[i]*(1-basis_mix)+lufs_bars[i]*basis_mix
    local xx=x+17+(i-1)*5.05
    rect(xx,cy-bh/2,1.35,bh,C.muted,0.76)
  end

  local l,r=x+29,x+79
  glow_line(l,y+23,r,y+23,C.accent,0.24)
  for _,xx in ipairs({l,r}) do rect(xx-1,y+20,2,33,C.accent2,0.94); disc(xx,y+23,1.5,C.text,0.9) end

  local peak_a=1-basis_mix
  if peak_a>0.001 then
    line(x+52,y+8,x+52,y+28,C.focus2,0.78*peak_a)
    line(x+47,y+20,x+52,y+11,C.accent2,0.58*peak_a)
    line(x+52,y+11,x+57,y+20,C.accent2,0.58*peak_a)
    disc(x+52,y+11,2.2,C.text,0.78*peak_a)
    disc(x+52,y+11,6.5,C.accent,0.045*peak_a)
  end
  if basis_mix>0.001 then
    local a=basis_mix
    cut_panel(x+29,y+8,48,13,3,C.accent3,0.11*a,C.accent2,0.55*a)
    cut_panel(x+43,y+13,20,9,2,C.field,0.78*a,C.warn,0.62*a)
    glow_line(x+33,y+9,x+73,y+9,C.accent2,0.18*a)
    disc(x+43,y+17.5,1.3,C.warn,0.62*a); disc(x+63,y+17.5,1.3,C.warn,0.62*a)
  end
end

local function region_contains(t)
  local lo,hi=1,#A.regions
  while lo<=hi do
    local m=floor((lo+hi)/2); local r=A.regions[m]
    if t<r[1] then hi=m-1 elseif t>=r[2] then lo=m+1 else return true end
  end
  return false
end

local WAVE_IMAGE=63
local function image_color(c,a) gfx.set(c[1],c[2],c[3],a or 1) end
local function image_line(x,y,x2,y2,c,a) image_color(c,a); gfx.line(x,y,x2,y2,1) end
local function image_rect(x,y,w,h,c,a) image_color(c,a); gfx.rect(x,y,w,h,1) end
local function build_wave_surface(data,start,span,plot_w,wave_h,meter_h)
  local iw=max(1,floor(plot_w+0.5))
  local meter_top=wave_h+8
  local ih=meter_top+meter_h
  gfx.setimgdim(WAVE_IMAGE,-1,-1)
  gfx.setimgdim(WAVE_IMAGE,iw,ih)
  gfx.dest=WAVE_IMAGE; gfx.mode=0
  gfx.set(0,0,0,0); gfx.rect(0,0,iw,ih,1)

  local cache=A.wave_cache
  if not cache or cache.data~=data or cache.start~=start or cache.span~=span or cache.basis~=S.basis or cache.width~=iw then
    cache={data=data,start=start,span=span,basis=S.basis,width=iw,peaks={},levels={},close_levels={}}
    for px=0,iw-1 do
      local a=start+px/iw*span; local b=start+(px+1)/iw*span
      local ia=max(1,floor(a*1000)+1); local ib=min(#data.peak,max(ia,ceil(b*1000)))
      local peak,level,close_level=0,-240,-240
      for i=ia,ib do
        peak=max(peak,data.peak[i] or 0)
        if S.basis=="lufs" then
          level=max(level,data.lufs[i] or -240)
          close_level=max(close_level,data.fast[i] or -240)
        else
          level=max(level,db(data.peak[i] or 0)); close_level=level
        end
      end
      cache.peaks[px+1],cache.levels[px+1],cache.close_levels[px+1]=peak,level,close_level
    end
    A.wave_cache=cache
  end

  local function txi(t) return (t-start)/span*iw end
  -- Detected regions and fades are cached with the waveform image. They are
  -- rebuilt only after data, zoom, thresholds or relevant settings change.
  for _,r in ipairs(A.regions) do
    if r[2]>start and r[1]<start+span then
      local left,right=txi(max(start,r[1])),txi(min(start+span,r[2]))
      image_rect(left,0,right-left,wave_h,C.accent,0.12)
      image_line(left,0,left,ih,C.accent2,0.28)
      image_line(right,0,right,ih,C.accent2,0.28)
      local dur=r[2]-r[1]
      local fi=S.fade_in_on and min(dur,S.fade_in/1000) or 0
      local fo=S.fade_out_on and min(dur,S.fade_out/1000) or 0
      if fi+fo>dur then local k=dur/(fi+fo); fi,fo=fi*k,fo*k end
      if fi>0 and r[1]>=start and r[1]+fi<=start+span then image_line(txi(r[1]),wave_h,txi(r[1]+fi),0,C.accent2,0.62) end
      if fo>0 and r[2]-fo>=start and r[2]<=start+span then image_line(txi(r[2]-fo),0,txi(r[2]),wave_h,C.accent2,0.62) end
    end
  end

  local center=wave_h/2
  image_line(0,center,iw,center,C.edge,0.48)
  local norm=max(data.max_peak,0.000001)
  local prev_level_y,prev_close_y=nil,nil
  for px=0,iw-1 do
    local a=start+px/iw*span; local b=start+(px+1)/iw*span
    local peak,level,close_level=cache.peaks[px+1],cache.levels[px+1],cache.close_levels[px+1]
    local amp=min(1,peak/norm)*(wave_h/2-3)
    image_line(px,center-amp,px,center+amp,region_contains((a+b)/2) and C.accent2 or C.quiet,0.94)
    local ly=meter_top+meter_h*(1-clamp((level+90)/102,0,1))
    if prev_level_y then image_line(px-1,prev_level_y,px,ly,C.accent,0.88) end
    prev_level_y=ly
    if S.basis=="lufs" then
      local cy=meter_top+meter_h*(1-clamp((close_level+90)/102,0,1))
      if prev_close_y then image_line(px-1,prev_close_y,px,cy,C.warn,0.42) end
      prev_close_y=cy
    end
  end
  for _,v in ipairs({-60,-30,0}) do
    local yy=meter_top+meter_h*(1-(v+90)/102); image_line(0,yy,iw,yy,C.edge,0.12)
  end
  for _,v in ipairs({{S.open,C.accent2},{S.close,C.warn}}) do
    local yy=meter_top+meter_h*(1-clamp((v[1]+90)/102,0,1))
    for xx=0,iw-4,9 do image_line(xx,yy,min(xx+4,iw),yy,v[2],0.78) end
  end

  gfx.dest=-1; gfx.mode=0
  A.wave_surface={data=data,start=start,span=span,basis=S.basis,w=iw,h=ih}
  A.wave_surface_dirty=false
end

local function waveform()
  local x,y,w,h=22,132,678,174
  gradient(x,y,w,h,C.field,C.panel,0.96,0.62)
  line(x,y,x+w,y,C.edge2,0.34); line(x,y+h,x+w,y+h,C.edge,0.48)
  line(x,y,x,y+h,C.edge2,0.22)
  finish_corners(x,y,w,h,9,false,C.edge2,0.44)
  local data=A.data
  local info=data and data.info or A.queue[A.index]
  label("WAVEFORM PREVIEW",x+14,y+8,8,C.faint,3,150,13,0,true)
  right_label(S.basis=="peak" and "PEAK / dBFS" or "OPEN LUFS-M  /  CLOSE FAST",x+w-13,y+8,7.5,C.muted,3,true)
  if not data then
    local message=A.analysis and (A.analysis.mode=="peak" and "Peakを取得しています…" or "ラウドネスを解析しています…") or "音声アイテムを選択してください"

    if A.analysis then
      local progress=A.analysis.offset/max(1,A.analysis.total)
      rect(x+105,y+108,w-210,3,C.edge,0.40); rect(x+105,y+108,(w-210)*progress,3,C.accent,0.90)
      glow_line(x+105,y+108,x+105+(w-210)*progress,y+108,C.accent2,0.18)
    end
    return
  end

  local plot_x,plot_w=x+40,w-54
  local span=info.len/A.zoom
  A.view_start=clamp(A.view_start,0,max(0,info.len-span))
  local start,finish=A.view_start,A.view_start+span
  local function tx(t) return plot_x+(t-start)/span*plot_w end
  local wave_y,wave_h=y+29,57
  local meter_y,meter_h=y+94,28
  local surface=A.wave_surface
  if A.wave_surface_dirty or not surface or surface.data~=data or surface.start~=start or surface.span~=span or surface.basis~=S.basis then
    build_wave_surface(data,start,span,plot_w,wave_h,meter_h)
    surface=A.wave_surface
  end
  if surface then
    gfx.dest=-1; gfx.mode=0; gfx.set(1,1,1,1)
    gfx.blit(WAVE_IMAGE,1,0,0,0,surface.w,surface.h,sx(plot_x),sy(wave_y),surface.w*scale,surface.h*scale)
  end

  label(S.basis=="peak" and "dBFS" or "LU",x+4,y+84,7.5,C.faint,3,34,11,0,true)
  local result_y=y+132
  label("RESULT",x+4,result_y-4,7,C.faint,3,34,10,0,true)
  rect(plot_x,result_y,plot_w,4,C.field)
  local parts=Core.plan(data.info,A.regions,S)
  local aligned=S.action=="split" or S.keep
  for _,p in ipairs(parts) do
    if p.keep then
      if aligned then
        local a=max(start,p.a); local b=min(finish,p.b)
        if b>a then rect(tx(a),result_y,tx(b)-tx(a),4,p.sound and C.accent or C.quiet,0.86) end
      else
        local xx=plot_x+(p.dest-data.info.pos)/data.info.len*plot_w
        rect(xx,result_y,(p.b-p.a)/data.info.len*plot_w,4,p.sound and C.accent or C.quiet,0.86)
      end
    end
  end
  for i=0,4 do
    local t=start+span*i/4
    label(string.format("%.2f",t),plot_x+plot_w*i/4-21,y+143,7,C.faint,3,42,11,1,false)
  end
  label(string.format("×%.1f",A.zoom),plot_x,y+157,7,C.faint,3,54,11,0,true)
  right_label("WHEEL ZOOM  /  SHIFT SCROLL",x+w-12,y+157,7,C.faint,3,true)
  register("wave",plot_x,wave_y,plot_w,meter_y+meter_h-wave_y,function() end,"ホイール：拡大・縮小 ／ Shift＋ホイール：横移動",not A.batch)
  if inside(plot_x,wave_y,plot_w,meter_y+meter_h-wave_y) then
    local t=start+(mouse_x-plot_x)/plot_w*span; local i=clamp(floor(t*1000)+1,1,#data.peak)
    hover_hint=S.basis=="lufs" and string.format("位置 %.3f s / Peak %.1f dBFS / OPEN LUFS-M %.1f / CLOSE FAST %.1f",t,db(data.peak[i]),data.lufs[i] or -240,data.fast[i] or -240) or string.format("位置 %.3f s / Peak %.1f dBFS",t,db(data.peak[i]))
  end
end

local function draw_glass_group(x,y,w,h,title)
  gradient(x,y,w,h,C.panel2,C.panel,0.22,0.58)
  line(x,y,x+w,y,C.edge2,0.22); line(x,y+h,x+w,y+h,C.edge,0.34)
  finish_corners(x,y,w,h,8,false,C.edge2,0.30)
  label(title,x+12,y+6,7.5,C.faint,3,w-24,12,0,true)
end

local function draw_primary_button(id,text,x,y,w,h,fn,hint,enabled)
 enabled=enabled~=false
 PrimaryButton.draw(PrimaryButton.painter,x,y,w,h,text,A.batch and 'ANALYZING' or 'EXECUTE',enabled,A.batch~=nil,A.batch and batch_progress() or nil,inside(x,y,w,h),pressed==id and (gfx.mouse_cap&1)~=0,R.time_precise(),BLT.host.active())
 register(id,x,y,w,h,fn,hint,enabled)
end

local function draw()
  local contentH=max(1,gfx.h-Chrome.titleH); scale=max(0.25,min(gfx.w/W,contentH/H)); ox,oy=(gfx.w-W*scale)/2,Chrome.titleH+(contentH-H*scale)/2-22*scale
 BLT.viewport(scale,gfx.ext_retina or 1);  mouse_x,mouse_y=(gfx.mouse_x-ox)/scale,(gfx.mouse_y-oy)/scale
  widgets={}; hover_hint=""; gfx.clear=-1;gfx.set(C.bg[1],C.bg[2],C.bg[3],1);gfx.rect(0,0,gfx.w,gfx.h,1)
  local now=R.time_precise(); particle_dt=max(0,min(0.1,now-frame_clock)); frame_clock=now
  frame_dt=animations_active and particle_dt*animation_speed or 0
  anim_time=anim_time+frame_dt
  draw_background()

  BLT.title('AUTO TRIM / SPLIT','SILENCE DETECTION / TRIM  スレッショルドによる無音検出・区間処理',W,false)
  BLT.drawIcon()

  local info=A.queue[A.index]
  gradient(22,93,678,32,C.panel2,C.panel,0.42,0.12)
  line(22,93,700,93,C.edge2,0.25); line(22,125,700,125,C.edge,0.34)
  finish_corners(22,93,678,32,6,false,C.edge2,0.30)
  label(info and info.name or "",34,98,10.5,C.text,1,450,21,0,true)
  local selected_total=A.selection_total or #A.queue
  local remaining=#A.queue
  gradient(514,97,174,24,C.field,C.panel2,0.20,0.46)
  line(514,120,688,120,C.edge2,0.28)
  finish_corners(514,97,174,24,5,false,C.edge2,0.26)
  right_label(string.format("選択 %02d   /   残り %02d",selected_total,remaining),680,100,10.5,
    remaining>0 and C.accent2 or C.muted,3,true)

  waveform()

  local total=0; for _,r in ipairs(A.regions) do total=total+r[2]-r[1] end
  label(A.ready and string.format("検出区間  %d    合計  %.3f s",#A.regions,total) or "",26,312,13,A.ready and C.text or C.muted,1,420,21,0,true)
  right_label(S.action=="split" and "SPLIT / KEEP SILENCE" or (S.keep and "DELETE / KEEP TIMING" or "DELETE / PACK"),696,316,7.5,C.faint,3,true)

  label("検出基準",22,339,9.5,C.accent2,1,100,16,0,true)
  gradient(80,347,620,1,C.edge2,C.edge2,0.28,0.02)
  choice_card("basis_peak","ピークレベル","PEAK / dBFS",22,354,258,44,S.basis=="peak",function() set_basis("peak") end,"各1 ms区間の最大振幅。全チャンネルの最大値で検出します。",not A.batch)
  edge_mode_button(292,354,138,44,function() toggle("edge_mode") end,not A.batch)
  choice_card("basis_lufs","ラウドネス","M OPEN / FAST CLOSE",442,354,258,44,S.basis=="lufs",function() set_basis("lufs") end,"OPENはK特性＋400 msのLUFS-M、CLOSEは同じK特性＋100 msのFASTラウドネスで判定します。",not A.batch)

  label("検出レベル",22,405,9.5,C.accent2,1,105,16,0,true)
  local open_units=S.basis=="peak" and "dBFS" or "LUFS"
  local close_units=S.basis=="peak" and "dBFS" or "FAST"
  field("open","オープンスレッショルド",22,439,202,open_units,S.basis=="lufs" and "LUFS-M（400 ms）がこの値を超えると音あり区間を開始します。" or "この値を超えると音あり区間を開始します。")
  field("close","クローズスレッショルド",236,439,202,close_units,S.basis=="lufs" and "FASTラウドネス（100 ms）がこの値未満になると無音候補を開始します。" or "この値未満になると無音候補を開始します。")
  toggle_switch("relative","スレッショルド差を固定",454,445,246,S.relative,function() toggle("relative") end,"開閉スレッショルドの差を保ったまま両方を動かします。",not A.batch)
  label(string.format("DELTA  %.1f dB",S.open-S.close),493,469,7.5,C.faint,3,180,12,0,true)

  label("時間設定",22,485,9.5,C.accent2,1,90,16,0,true)
  local fw=159
  field("min_open","短い無音を無視",22,519,fw,"ms","この時間未満の無音は無視して、前後の音を同じ音あり区間として扱います。")
  field("min_close","最短クリップ長",194,519,fw,"ms","この時間未満の音あり区間は残すクリップとして採用しません。プリ／ポストロールを加える前の長さで判定します。")
  field("pre","プリロール",366,519,fw,"ms","正：開始を前へ広げる／負：開始を後ろへ縮める。元アイテム内に制限します。")
  field("post","ポストロール",538,519,162,"ms","正：終了を後ろへ広げる／負：終了を前へ縮める。重なった区間は結合します。")

  draw_glass_group(22,569,326,91,"FADE")
  toggle_switch("fade_in_on","フェードイン",34,587,142,S.fade_in_on,function() toggle("fade_in_on") end,"音あり区間に指定時間のフェードインを設定します。",not A.batch)
  toggle_switch("fade_out_on","フェードアウト",181,587,154,S.fade_out_on,function() toggle("fade_out_on") end,"音あり区間に指定時間のフェードアウトを設定します。",not A.batch)
  field("fade_in",nil,34,620,137,"ms","短い区間ではフェードが重ならない長さに縮めます。",S.fade_in_on)
  field("fade_out",nil,184,620,151,"ms","短い区間ではフェードが重ならない長さに縮めます。",S.fade_out_on)

  draw_glass_group(360,569,340,91,"PROCESS")
  segment_button("delete","無音部分を削除",372,587,151,27,S.action=="delete",function() set_choice("action","delete") end,"灰色の区間を削除し、青色の区間を残します。",not A.batch)
  segment_button("split","分割",531,587,157,27,S.action=="split",function() set_choice("action","split") end,"青・灰の境界で分割し、全ての区間を元の位置に残します。",not A.batch)
  toggle_switch("keep","削除した区間を詰める",372,620,316,S.action=="delete" and not S.keep,function() toggle("keep") end,"ON：無音部分を削除した後、残った検出区間を元アイテムの開始位置から隙間なく詰めます。",S.action=="delete" and not A.batch)

  local message=A.message
  if A.batch then
    local p=batch_progress()
    message=string.format("全選択を解析中  %d / %d    %d%%（解析完了後にまとめて編集）",min(A.batch.i,#A.batch.list),#A.batch.list,floor(p*100+0.5))
  elseif A.analysis then message=string.format(A.analysis.mode=="peak" and "Peak取得  %d%%" or "Loudness解析  %d%%",floor(100*A.analysis.offset/max(1,A.analysis.total))) end

  draw_primary_button("execute",A.batch and "処理を中止" or "処理を実行",190,686,312,44,execute,"Enter：実行。編集は1回のUndoで元に戻せます。",A.batch or A.ready)
  toggle_switch("all","選択アイテムを一括処理",518,696,182,S.all,function()
    S.all=not S.all; persist(); if S.all then A.index=1; start_preview() else detect_preview() end
  end,"ON：先頭をプレビューして全選択へ適用。OFF：1つずつ処理して次へ。",not A.batch)
  BLT.footer(message~='' and message or (not A.ready and '音声アイテムを選択してください。' or ''),A.bad,W,H+22,'0.5.7')
  custom_titlebar()
end

local function interact()
 if BLT.blocked() then down_last=(gfx.mouse_cap&1)~=0;pressed=nil;gfx.mouse_wheel=0;return end

  if Chrome.mouseActive then down_last=(gfx.mouse_cap&1)~=0; pressed=nil; A.field_drag=nil; return end
  local hit=nil
  for i=#widgets,1,-1 do local w=widgets[i]; if inside(w.x,w.y,w.w,w.h) then hit=w; break end end
  local wheel=gfx.mouse_wheel or 0
  if wheel~=0 then
    gfx.mouse_wheel=0
    if hit and hit.enabled then
      local direction=wheel>0 and 1 or -1
      if hit.id:match("^field_") then
        if commit_edit() then
          local key=hit.id:sub(7)
          local step=Core.steps[key] or 1;if (gfx.mouse_cap&8)~=0 then step=step*.1;if Core.precision[key]==0 then step=max(1,step) end end
          local old=S[key];local ok,clipped=Core.set_number(S,key,old+direction*step)
          if ok then
            if clipped then A.flash_field(key) end
            if S[key]~=old then schedule_settings_changed() end
          end
        end
      elseif hit.id=="wave" and A.data then
        local len=A.data.info.len; local old_span=len/A.zoom
        if (gfx.mouse_cap&8)~=0 then A.view_start=clamp(A.view_start-direction*old_span*0.12,0,max(0,len-old_span)); invalidate_wave_surface(true)
        else
          local fraction=clamp((mouse_x-hit.x)/hit.w,0,1)
          local anchor=A.view_start+fraction*old_span
          A.zoom=clamp(A.zoom*(direction>0 and 1.5 or 1/1.5),1,max(1,min(200,len/0.005)))
          A.view_start=clamp(anchor-fraction*len/A.zoom,0,max(0,len-len/A.zoom))
          invalidate_wave_surface(true)
        end
      end
    end
  end
  local down=(gfx.mouse_cap&1)~=0
  if down and not down_last then
    pressed=hit and hit.id or nil
    if hit and hit.enabled and hit.id:match("^field_") and commit_edit() then
      local key=hit.id:sub(7); A.field_drag={key=key,start_y=mouse_y,start_value=S[key],moved=false,clipped=false}
    end
  elseif down and A.field_drag then
    A.update_field_drag(mouse_y,(gfx.mouse_cap&8)~=0)
  elseif not down and down_last then
    local was_drag=A.field_drag and A.field_drag.moved
    A.field_drag=nil
    if not was_drag then
      if hit and hit.enabled and pressed==hit.id then if commit_edit() then hit.fn() end
      elseif edit then commit_edit() end
    end
    pressed=nil
  end
  down_last=down
end

local function keypress(k)
 k=BLT.key(k);if k==0 then return end

  if k==27 then
    if edit then edit=nil; return end
    A.closing=true; return
  end
  if A.batch then return end
  if k==13 then if edit then commit_edit() else execute() end; return end
  if not edit then return end
  if k==9 then commit_edit(); return end
  if k==1 then edit.selected=true
  elseif k==8 or k==6579564 then edit.text=edit.selected and "" or edit.text:sub(1,-2); edit.selected=false
  elseif (k>=48 and k<=57) or k==45 or k==46 then
    local str=string.char(k)
    if edit.selected then edit.text=str else if #edit.text<14 then edit.text=edit.text..str end end
    edit.selected=false
  end
end

local function save_window()
  local _,x,y,w,h=gfx.dock(-1,0,0,0,0)
  for key,v in pairs({window_x=x,window_y=y,window_w=w,window_h=h}) do
    if finite(v) then BLT.store(SECTION,key,tostring(floor(v+0.5)),true) end
  end
end
local function close()
 -- Teardown errors must not leave a dead graphics window on screen.
 local ok,err=xpcall(function()
  if A.closed then return end
  stop_jobs(); persist(); save_window(); clear_chrome_tooltip(); titlebar_cleanup(); A.closed=true; gfx.quit()
 end,debug.traceback)
 if not ok then
  A.closed=true
  pcall(gfx.quit)
  if R.TrackCtl_SetToolTip then pcall(R.TrackCtl_SetToolTip,'',0,0,true) end
  BLT.logError(err)
 end
end

PrimaryButton.painter={C=C,gradient=gradient,line=line,rect=rect,corners=finish_corners,disc=disc,label=label}
PrimaryButton.painter.motion=function(now) return (gfx.mouse_x-ox)/scale,(gfx.mouse_y-oy)/scale,visual_speed(now) end
PrimaryButton.wake=function() redraw_dirty=true;A.content_dirty=true;next_draw_time=0 end
Media.state=A;Media.onchange=function() if BLT.host and BLT.host.wake then BLT.host.wake() end end
BLT.attach({
 R=R,C=C,Chrome=Chrome,Chameleon=Chameleon,section=SECTION,faces=fonts,font=font,
 geometry=function() return scale,ox,oy end,active=function() local f=gfx.getchar(65536);return (f&1)==0 or (f&2)~=0 end,
 wake=function() A.content_dirty=true;redraw_dirty=true;next_draw_time=0;wake_visuals() end,
 defaults=Core.defaults,capture=function() return S end,
 valid=function(v) return Core.validate(v)~=nil and (v.basis=='peak' or v.basis=='lufs') and (v.action=='delete' or v.action=='split') end,apply=function(v) for k,v in pairs(v) do S[k]=v end;settings_changed() end,
 undoRefresh=function() sync_selection() end,
 busy=function() return A.batch~=nil end,commit=function() return commit_edit() end,
 cancelEdit=function() edit=nil;A.field_drag=nil end,editing=function() return edit~=nil end,
 modal=function() return false end,
 handle=gfx_window_handle,resizeHit=function(x,y) if y<26 and x>=gfx.w-234 then return nil end;return chrome_resize_hit(x,y) end,
 cursor=set_resize_cursor,beginResize=begin_window_resize,resize=update_window_resize,

})
if ...=='blt_test' then function BLT.testDraw(now) draw(now or R.time_precise()) end end
function BLT.drawIcon()

 local bs,bx,by=scale,ox,oy;ox,oy=ox+(W-102)*scale,oy+31*scale;scale=scale*.78
 trim_icon(0,0)

 scale,ox,oy=bs,bx,by
end

if ...=='blt_test' then return {Media=Media,BLT=BLT,A=A,Core=Core,S=S} end
local chrome_ok,chrome_err=titlebar_api_ready()
if not chrome_ok then Language.mb(BLT.publicError(chrome_err),"Auto Trim / Split | エラー",0); return end
local wx,wy=tonumber(R.GetExtState(SECTION,"window_x")),tonumber(R.GetExtState(SECTION,"window_y"))
local ww,wh=tonumber(R.GetExtState(SECTION,"window_w")),tonumber(R.GetExtState(SECTION,"window_h"))
ww=finite(ww) and clamp(ww,560,1500) or W
wh=finite(wh) and clamp(wh,620+Chrome.titleH,1500+Chrome.titleH) or (H+Chrome.titleH)
-- Match native window/input coordinates in logical points on Mac.
gfx.ext_retina=BLT_MAC and 0 or 1
if finite(wx) and finite(wy) then gfx.init(Chrome.windowTitle,ww,wh,0,wx,wy)
else gfx.init(Chrome.windowTitle,ww,wh,0) end
if not apply_custom_window_style(ww,wh) then gfx.quit(); Language.mb("カスタムタイトルバーを初期化できません。","Auto Trim / Split | エラー",0); return end
if Chameleon.enabled then Chameleon.refresh(true) end
R.atexit(close)
guarded(sync_selection)
local function loop()
  guarded(function()
 local now=R.time_precise();BLT.tick(now);PrimaryButton.tick(now,BLT.host.active(),PrimaryButton.wake)

  if A.closing then A.closing=true; return end
  local k=BLT.key(gfx.getchar()); if k<0 then close(); return end
        Chameleon.tick(now)
    local flags=gfx.getchar(65537)
    local window_active=((flags & 1)==0) or ((flags & 2)~=0)
    if last_window_active==nil or window_active~=last_window_active then last_window_active=window_active; wake_visuals(now) end

    local key_activity=false
    local count=0
    while k>0 and count<32 do key_activity=true; keypress(k); count=count+1; k=BLT.key(gfx.getchar()) end
    if key_activity then wake_visuals(now) end
    if A.closing then return end

    local project=R.EnumProjects(-1,"")
    if project~=A.project then
      stop_jobs(); A.project=project; A.audio_cache={}; A.long_lufs_approved={}; sync_selection(); wake_visuals(now)
    end
    if A.settings_pending and now>=A.settings_due then flush_scheduled_settings(); redraw_dirty=true end
    if Media.ready() and now>=A.poll_at then
      A.poll_at=now+0.35
      local revision=R.GetProjectStateChangeCount(A.project)
      local key=Core.selection_key(A.project)
      if key~=A.selection_key then
        sync_selection(); wake_visuals(now)
      elseif revision~=A.revision then
        local was_batch=A.batch~=nil
        A.revision=revision; start_preview(true); wake_visuals(now)
        if was_batch then notice("プロジェクトが変更されたため解析を中止しました。",true) end
      end
    end

    local had_work=A.analysis~=nil or A.detector~=nil or A.batch~=nil
    work_step()
    local work_active=A.analysis~=nil or A.detector~=nil or A.batch~=nil
    if had_work~=work_active then redraw_dirty=true end

    local raw_x,raw_y,raw_cap=gfx.mouse_x,gfx.mouse_y,gfx.mouse_cap
    local raw_wheel=gfx.mouse_wheel or 0

    local cap_changed=raw_cap~=last_raw_mouse_cap
    local wheel_activity=raw_wheel~=0
    local pointer_activity=raw_x~=last_raw_mouse_x or raw_y~=last_raw_mouse_y or cap_changed or wheel_activity
    if pointer_activity then wake_visuals(now) end
    -- Button/wheel transitions are input events, not decoration. Render them on
    -- the current defer pass so short clicks cannot fall between capped frames.
    if cap_changed or wheel_activity then next_draw_time=now end
    last_raw_mouse_x,last_raw_mouse_y,last_raw_mouse_cap=raw_x,raw_y,raw_cap
    if gfx.w~=last_window_w or gfx.h~=last_window_h then last_window_w,last_window_h=gfx.w,gfx.h; wake_visuals(now) end

    local dragging=A.field_drag~=nil or Chrome.drag~=nil or Chrome.resize~=nil or ((raw_cap or 0)&1)~=0
    if dragging then wake_visuals(now) end
    animation_speed=work_active and 1 or visual_speed(now)
    animations_active=window_active and animation_speed>0
    local particle_tail=#icon_particles>0
    local frame_interval
    if dragging then frame_interval=1/60
    elseif work_active then frame_interval=1/30
    elseif animations_active then frame_interval=1/(8+22*animation_speed)
    elseif particle_tail then frame_interval=1/20 end
    if frame_interval and next_draw_time==math.huge then next_draw_time=now end
    local frame_due=frame_interval and now>=next_draw_time or (not frame_interval and (redraw_dirty))
    if frame_due then
      draw(); interact(); gfx.update(); redraw_dirty=false
      next_draw_time=frame_interval and now+frame_interval or math.huge

      if Chrome.requestReset then Chrome.requestReset=false; reset_window_size(); wake_visuals(now) end
      if Chrome.requestClose then Chrome.requestClose=false; A.closing=true end
    end
    if pointer_activity or key_activity or dragging then redraw_dirty=true end
  end)
  if A.closing then close(); return end
  R.defer(loop)
end
loop()
