-- @description CR MINIM
-- @version 0.5.10
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
 ["頭フェード ms"]="Fade in ms",
 ["後フェード ms"]="Fade out ms",
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
 ["設定番号が不正です。"]="Invalid setting index.",
 ["素材の長さまたはサンプリングレートが不正です。"]="Invalid source length or sample rate.",
 ["1ms以上の素材を選択してください。"]="Select audio at least 1 ms long.",
 ["この素材では生成可能な範囲を作れませんでした。"]="Cannot create a valid generation range from this source.",
 ["WAVが途中で切れています。"]="Truncated WAV file.",
 ["通常のRIFF/WAVのみ対応しています（RF64/Wave64非対応）。"]="Standard RIFF/WAV only; RF64/Wave64 unsupported.",
 ["WAVサイズが一致しません。レンダー未完了または破損ファイルです。"]="WAV size mismatch. Render incomplete or file damaged.",
 ["WAVチャンクヘッダーが不正です。"]="Invalid WAV chunk header.",
 ["WAVチャンク長が不正です。音声データが途中で切れている可能性があります。"]="Invalid WAV chunk length. Audio data may be truncated.",
 ["WAV fmtが不正です。"]="Invalid WAV fmt chunk.",
 ["WAVEFORMATEXTENSIBLEが不正です。"]="Invalid WAVEFORMATEXTENSIBLE.",
 ["未対応のWAVサブフォーマットです。"]="Unsupported WAV subformat.",
 ["PCM / IEEE float WAVのみ対応しています。"]="PCM / IEEE float WAV only.",
 ["WAV音声フォーマットが不正です。"]="Invalid WAV audio format.",
 ["複数dataチャンクには対応していません。"]="Multiple data chunks are unsupported.",
 ["音声データがありません、またはサンプル境界が不正です。"]="No audio data or invalid sample alignment.",
 ["パネルを1つ以上ONにしてください。"]="Turn on at least one panel.",
 ["設定値が不正です: "]="Invalid setting: ",
 ["切り出し開始がアイテムの末尾を超えています。"]="Slice start exceeds the item end.",
 ["無音時間が間隔以上です。間隔を広げるか無音時間を短くしてください。"]="Silence is not shorter than the interval. Increase interval or reduce silence.",
 ["リピート回数または最後の音を設定してください。"]="Set repeat count or enable the final sound.",
 ["試作の生成上限は10分です。"]="Generation is limited to 10 minutes in this prototype.",
 ["音声アイテムを1つ選択してください。"]="Select one audio item.",
 ["音声テイクを選択してください。"]="Select an audio take.",
 ["試作版は通常のWAVが対象です。逆再生・圧縮音声などは先にグルーしてください。"]="This prototype requires standard WAV. Glue reversed/compressed audio first.",
 ["速度・ピッチ・ストレッチ済みの素材は、先にグルーしてください。"]="Glue rate/pitch/stretched audio first.",
 ["チャンネルモードを変更した素材は先にグルーしてください。"]="Glue audio with modified channel mode first.",
 ["試作版はモノラル／ステレオ対応です。"]="This prototype supports mono/stereo.",
 ["ソース終端をまたぐアイテムは先にグルーしてください。"]="Glue items extending past the source end first.",
 ["WAVが4GiBを超えます。"]="WAV exceeds 4 GiB.",
 ["出力ファイルが既に存在します。"]="Output file already exists.",
 ["作業ファイルが既に存在します。"]="Work file already exists.",
 ["生成WAVの検証に失敗しました。"]="Generated WAV validation failed.",
 ["出力先が使用されています。"]="Output path is in use.",
 ["生成WAVを開けません。"]="Cannot open generated WAV.",
 ["生成元のプロジェクトまたはアイテムが利用できません。"]="Source project or item is unavailable.",
 ["生成元のアイテム自体が編集されたため中止しました。"]="Source item was edited. Stopped.",
 ["生成結果は配置済みです。"]="Generated result is already placed.",
 ["波形ピークの準備が完了していません。"]="Waveform peaks are not ready.",
 ["生成WAVをテイクへ設定できません。"]="Cannot assign generated WAV to the take.",
 ["BLT CR MINIM: バリエーション生成"]="BLT CR MINIM: Generate variations",
 ["\n生成WAVは保存済みです。"]="\nGenerated WAV has been saved.",
 ["音声アイテムを選択してください。"]="Select audio items.",
 ["CHAMELEON  REAPERテーマに擬態"]="CHAMELEON  REAPER theme",
 ["CHAMELEON  オリジナル配色"]="CHAMELEON  Original colors",
 ["カスタムタイトルバーには js_ReaScriptAPI が必要です。\nReaPack から js_ReaScriptAPI をインストールしてください。"]="The app bar requires js_ReaScriptAPI.\nInstall js_ReaScriptAPI via ReaPack.",
 ["配置を中止しました。完成済みWAVは保持しています。"]="Placement cancelled. Completed WAV retained.",
 ["生成を中止しました。"]="Generation stopped.",
 ["生成完了。0 dBFS超過あり：生成アイテムの音量で調整してください。"]="Done. Peaks exceed 0 dBFS; adjust generated item volume.",
 ["生成完了。同じトラックの右側に配置しました。"]="Done. Placed to the right on the same track.",
 ["クリック入力 / 上下ドラッグ / ホイール"]="Click to type / Drag vertically / Wheel",
 [" / Shiftで微調整"]=" / Shift: fine adjust",
 ["全体"]="Full",
 ["波形全体へ戻す"]="Show full waveform",
 ["範囲拡大"]="Zoom range",
 ["切り出し範囲を拡大"]="Zoom to slice range",
 ["RESULT / 結果予想"]="RESULT / Preview",
 ["青：振幅  橙：ピッチ（速度連動）"]="Blue: amplitude  Orange: pitch (rate-linked)",
 ["%.3f 秒"]="%.3f s",
 ["%.3f秒 / %s / %+.2f st / %.2f倍速"]="%.3f s / %s / %+.2f st / %.2fx",
 ["最後の音"]="Final sound",
 ["逆転リトリガー"]="Reverse retrigger",
 ["リトリガー"]="Retrigger",
 ["リトリガーから最後の音まで、同じ時間軸・振幅目盛で表示（簡易予想）"]="Retrigger and final sound shown on shared time/amplitude axes (approximate).",
 ["OFFではこのパネルの音を生成しません"]="OFF: this panel generates no audio",
 ["RETRIGGER MODULATION  リトリガーモジュレーション"]="RETRIGGER MODULATION  Retrigger modulation",
 ["素材と切り出し範囲"]="SOURCE & SLICE",
 ["スライス＆リトリガー"]="SLICE & RETRIGGER",
 ["切り出す範囲"]="SLICE RANGE",
 ["切り出し開始 ms"]="Slice start ms",
 ["最初の長さ ms"]="First length ms",
 ["最後の長さ ms"]="Last length ms",
 ["最初 → 最後で長さを変化させる"]="Vary length from first to last",
 ["発音の並びと間隔"]="REPEATS & TIMING",
 ["リピート回数"]="Repeats",
 ["再生方向"]="Direction",
 ["順転"]="Fwd",
 ["逆転"]="Rev",
 ["順逆"]="Alt",
 ["最初の間隔 ms"]="First gap ms",
 ["最後の間隔 ms"]="Last gap ms",
 ["最小の無音 ms"]="Min. silence ms",
 ["変化カーブ"]="Curve",
 ["リトリガーのピッチ"]="RETRIGGER PITCH",
 ["最初のピッチ st"]="First pitch st",
 ["最後のピッチ st"]="Last pitch st",
 ["最後の音とモーション"]="FINAL SOUND & MOTION",
 ["最後に鳴らす範囲"]="FINAL SOUND RANGE",
 ["素材全体"]="Full source",
 ["切り出し以降"]="From slice",
 ["最後の音にモーションを適用"]="Apply motion to final sound",
 ["ピッチ・速度と通過点"]="PITCH / RATE & PASS",
 ["開始 st"]="Start st",
 ["通過 st"]="Pass st",
 ["終了 st"]="End st",
 ["接近 → 通過 → 遠ざかり"]="Approach → Pass → Recede",
 ["通過位置 %"]="Pass point %",
 ["音量・左右移動・フェード"]="VOLUME / PAN / FADE",
 ["開始音量 dB"]="Start dB",
 ["通過音量 dB"]="Pass dB",
 ["終了音量 dB"]="End dB",
 ["開始パン"]="Start pan",
 ["終了パン"]="End pan",
 ["フェード ms"]="Fade ms",
 ["トレモロ"]="TREMOLO",
 ["開始 Hz"]="Start Hz",
 ["終了 Hz"]="End Hz",
 ["深さ %"]="Depth %",
 ["パラメータをランダムに変化させます"]="Randomize parameters",
 ["生成中止"]="Stop",
 ["生成実行"]="Generate",
 ["もう一度押すと生成を中止します"]="Press again to stop generation",
 ["波形ピークを作成後、同じトラックの右側の空きへ1秒空けて配置します"]="Build peaks, then place in free space to the right on the same track with a 1-second gap",
 ["中止"]="Stop",
 ["作業ファイルを破棄して中止"]="Discard work file and stop",
 ["BLT CR MINIM | 必要な拡張"]="BLT CR MINIM | Required extension",
 ["カスタムアプリバーを初期化できません。"]="Cannot initialize the app bar.",
 ["表示言語を切替（JP / EN）"]="Switch language (JP / EN)",
 ["プリセットを読み込みました: ファクトリーデフォルト"]="Loaded: Factory Default",
 ["選択中のトラック / バスを指定"]="Use selected track / bus",
},patterns={
 {"^「(.*)」を上書きしますか？$","Overwrite \"%s\"?"},
 {"^([%+%-]?[%d%.eE]+)–([%+%-]?[%d%.eE]+) / ([%+%-]?[%d%.eE]+)   スクロールで選択$","%d–%d / %d   Scroll to browse"},
 {"^解析中%.%.%.([%+%-]?[%d%.eE]+)%%$","Analyzing...%d%%"},
 {"^([%+%-]?[%d%.eE]+) 秒$","%.3f s"},
 {"^([%+%-]?[%d%.eE]+)秒 / (.-) / ([%+%-]?[%d%.eE]+) st / ([%+%-]?[%d%.eE]+)倍速$","%.3f s / %s / %+.2f st / %.2fx",{2}},
 {"^「(.-)」を上書きしますか？$","\"%s\"?"},
 {"^(.-)」を上書きしますか？$","%s\"?"},
 {"^プリセットを保存しました: (.-)$","Saved: %s"},
 {"^プリセットを読み込みました: (.-)$","Loaded: %s"},
 {"^(.-)個インポートしました。$","%s preset(s) imported."},
 {"^現在: (.-)(.-)$","Current: %s%s"},
 {"^設定値が不正です: (.-)$","Invalid setting: %s"},
 {"^(.-)\n生成WAVは保存済みです。$","%s\nGenerated WAV has been saved."},
 {"^(.-) / Shiftで微調整$","%s / Shift: fine adjust"},
 {"^「(.*)」を上書きしますか？$","Overwrite \"%s\"?"},
 {"^(%d+)個インポートしました。$","Imported %s preset(s)."},
 {"^(%d+)件をノーマライズしました。選択を解除しました。$","Normalized %s items and deselected them."},
},prefixes={"プリセットを読み込みました: ","プリセットを保存しました: ","設定値が不正です: ","現在: "}}

local Language=create_language(reaper,"BLT_CR_MINIM",LanguageCatalog)
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
function B.chaosButton(cx,cy,cw,ch,enabled,hot,pushed,time,glow)
 local d=host.chaosPainter
 local violet=Chameleon.enabled and C.accent2 or B.chaosViolet
 local ember=Chameleon.enabled and C.accent or B.chaosEmber
 local pale=Chameleon.enabled and C.text or B.chaosPale
 local surface=Chameleon.enabled and C.field or B.chaosSurface
 local alive=enabled and 1 or .25
 local breath=(.5+.5*math.sin(time*.85))*alive
 local y=cy+(pushed and 1 or 0);local center=ch/2
 -- Keep both the outer glow and the pressed face inside the registered bounds.
 d.cut(cx,cy,cw,ch,11,violet,.025*alive,violet,.10+.07*breath)
 d.cut(cx,y+2,cw,ch-4,9,surface,1,violet,(.45+.3*glow)*alive)
 d.gradient(cx+2,y+4,cw-4,ch-8,violet,C.bg,.12+.15*glow,.015,true)
 for i=1,6 do
  local phase=time*.3+i*1.7;local px=cx+12+(i-1)*(cw-29)/5
  local py=y+center+math.sin(phase)*(center-6)
  local alpha=(.18+.22*math.sin(phase*.7)^2)*alive
  if px<cx+36 or px>cx+cw-36 or math.abs(py-y-center)>11 then
   d.disc(px,py,3,violet,alpha*.08);d.disc(px,py,.7,i%2==0 and ember or pale,alpha)
  end
 end
 d.line(cx+cw*.335,y+ch-5,cx+cw*.665,y+ch-5,violet,(.18+.22*breath+.2*glow)*alive)
 d.label('C H A O S',cx+24,y+center-9,17,enabled and pale or C.faint,2,cw-48,22,1,true)
end
B.chaosViolet={.62,.23,.94};B.chaosEmber={.92,.27,.65};B.chaosPale={.87,.69,1};B.chaosSurface={.038,.014,.068}

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

local min,max,abs,floor=math.min,math.max,math.abs,math.floor
local function finite(n) return type(n)=='number' and n==n and abs(n)<math.huge end
local function clamp(n,a,b) return max(a,min(b,n)) end
local Core={VERSION='0.5.10',SECTION='BLT_CR_MINIM'}
-- Presentation only: show message content without source locations or filenames.
function Core.display_message(value)
 local text=tostring(value or '')
 text=text:match('^(.-)\nstack traceback:') or text
 text=text:gsub('\\','/')
 -- Drive-qualified and UNC directories, including spaces and Japanese names.
 text=text:gsub('[A-Za-z]:/[^:\n\r"<>|]*/','')
 text=text:gsub('[A-Za-z]:/','')
 text=text:gsub('//[^:\n\r"<>|]*/','')
 -- Lua may shorten its source location to .../folder/script.lua:123:.
 text=text:gsub('([^\n\r]+)',function(line)
  line=line:gsub('^.-/([^/]-:%d+:)', '%1')
  -- Absolute POSIX paths from file I/O errors.
  line=line:gsub('/[^/%s:][^:\n\r"<>|]*/','')
  -- Strip Lua's source/line prefix, including repeated wrapper locations.
  while line:match('^.-:%d+:%s*') do line=line:gsub('^.-:%d+:%s*','',1) end
  -- File I/O errors commonly start with a bare filename after directory removal.
  line=line:gsub('^.-%.[%a][%w%-]*:%s*','')
  line=line:gsub('[^%s:"<>|]+%.blt%-part','')
  for _,ext in ipairs({'lua','wav','WAV','reapeaks'}) do
   line=line:gsub('[^%s:"<>|]+%.'..ext,'')
  end
  return line:gsub('^%s+',''):gsub('%s+$','')
 end)
 return BLT.publicError(text)
end
Core.specs={count={0,128,true,1},offset={0,3600000,false,10},slice={1,60000,false,1},interval0={1,60000,false,1},interval1={1,60000,false,1},gap={0,60000,false,1},pitch0={-24,24,false,.5},pitch1={-24,24,false,.5},curve={.2,5,false,.1},fade={0,100,false,1},bend0={-24,24,false,.5},bend1={-24,24,false,.5},trem0={0,80,false,.5},trem1={0,80,false,.5},depth={0,100,false,1},pan0={-100,100,false,1},pan1={-100,100,false,1},gain0={-60,12,false,1},gain1={-60,12,false,1}}
Core.specs.pattern={1,4,true,1};Core.specs.tail={1,2,true,1}
Core.specs.slice_end={1,60000,false,1}
Core.specs.slice_fade_in={0,60000,false,1};Core.specs.slice_fade_out={0,60000,false,1}
Core.specs.bend_mid={-24,24,false,.5};Core.specs.pass={5,95,false,1};Core.specs.gain_mid={-60,12,false,1}
-- Decimal precision is shared by numeric entry, dragging, and waveform editing.
Core.precision={slice_fade_in=2,slice_fade_out=2,offset=0,slice=0,slice_end=0,interval0=0,interval1=0,gap=0,fade=0,count=0,depth=0,pan0=0,pan1=0,pass=0,pitch0=2,pitch1=2,bend0=2,bend_mid=2,bend1=2,gain0=1,gain_mid=1,gain1=1,trem0=1,trem1=1,curve=2}
function Core.quantize(key,value,nearest)
 local digits=Core.precision[key];if not digits then return value end
 local m=10^digits;local n=abs(value)*m
 n=nearest and floor(n+.5+1e-8) or floor(n+1e-8)
 return (value<0 and -n or n)/m
end
function Core.number_text(key,value)
 local digits=Core.precision[key]
 if not digits then return tostring(value) end
 local text=string.format('%.'..digits..'f',Core.quantize(key,value))
 if digits>0 then text=text:gsub('0+$',''):gsub('%.$','') end
 return text
end
function Core.fine_adjustment(key,spec)
 local step=spec and spec[4] or 1
 return (step<1 or key=='slice_fade_in' or key=='slice_fade_out') and (Core.precision[key] or 0)>0
end
Core.chaos_base={retrigger_on=true,tail_on=true,flyby=false,bend_mid=7,pass=50,gain_mid=0,vary_length=false,slice_end=85,count=7,offset=0,slice_fade_in=.5,slice_fade_out=.5,slice=85,interval0=100,interval1=100,gap=10,pitch0=0,pitch1=0,curve=1,fade=2,bend0=0,bend1=0,trem0=0,trem1=0,depth=0,pan0=0,pan1=0,gain0=0,gain1=0,pattern=1,tail=1,motion=false}
Core.defaults={retrigger_on=true,tail_on=true,flyby=true,bend_mid=-13,pass=35,gain_mid=-3,vary_length=true,slice_end=25,count=16,offset=0,slice_fade_in=.5,slice_fade_out=.5,slice=120,interval0=180,interval1=32,gap=3,pitch0=-7,pitch1=12,curve=1.7,fade=2,bend0=0,bend1=-10,trem0=0,trem1=12.5,depth=90,pan0=0,pan1=0,gain0=0,gain1=0,pattern=3,tail=1,motion=true}
function Core.settings()
 local s={};for k,v in pairs(Core.defaults) do s[k]=v end;return s
end
Core.chaos_bank={
 {count=7,slice=55,interval0=85,interval1=85,gap=15,pitch0=0,pitch1=0},
 {count=16,slice=120,slice_end=25,vary_length=true,interval0=180,interval1=32,gap=3,pitch0=-7,pitch1=12,curve=1.7},
 {count=8,pattern=4,slice=150,interval0=170,interval1=320,gap=55,pitch0=0,pitch1=-5,curve=2},
 {count=0,motion=true,flyby=true,bend0=3,bend_mid=8,bend1=-10,pass=35,gain0=-20,gain_mid=0,gain1=-30,trem0=24,trem1=4,depth=45,pan0=-90,pan1=90},
 {count=0,motion=true,bend0=0,bend1=-24,gain1=-30,depth=0,fade=15},
 {count=64,slice=6,interval0=14,interval1=14,gap=8,pitch0=0,pitch1=0,tail_on=false},
 {count=3,pattern=1,slice=90,interval0=650,interval1=650,gap=350,pitch0=0,pitch1=0,tail_on=false},
 {count=1,pattern=2,slice=900,interval0=900,interval1=900,gap=0,pitch0=0,pitch1=0,tail_on=false},
 {count=0,motion=true,flyby=true,bend0=0,bend_mid=0,bend1=0,pass=65,gain0=-42,gain_mid=-3,gain1=-42,fade=15},
 {count=12,slice=6,slice_end=65,vary_length=true,interval0=125,interval1=125,gap=8,pitch0=-5,pitch1=-5,curve=1.4,tail_on=false},
 {count=1,pattern=2,slice=900,interval0=960,interval1=960,gap=60,pitch0=0,pitch1=0},
 {count=0,motion=true,bend0=-12,bend1=-12,gain0=0,gain1=-24,depth=0,fade=0},
 {count=10,slice=15,slice_end=120,vary_length=true,interval0=30,interval1=260,gap=5,pitch0=7,pitch1=0,curve=1.5},
 {count=0,motion=true,bend0=0,bend1=0,trem0=12,trem1=12,depth=75,pan0=-100,pan1=100},
 {count=4,pattern=3,slice=240,interval0=750,interval1=1100,gap=200,pitch0=0,pitch1=-4,tail_on=false},
 {count=0,motion=true,bend0=-5,bend1=12,gain0=-12,gain1=0,trem0=2,trem1=48,depth=85,fade=4}
}

function Core.chaos_values(n)
 local spec=assert(Core.chaos_bank[n],'設定番号が不正です。');local s={};for k,v in pairs(Core.chaos_base) do s[k]=v end
 for k,v in pairs(spec) do s[k]=v end
 s.retrigger_on=s.count>0
 return s
end
-- CHAOS alternates two strategies; the caller owns the sequence and PRNG.
function Core.chaos(mode,duration,sr,random)
 local rng=random or math.random
 local function range(a,b) return a+(b-a)*rng() end
 local function integer(a,b) return min(b,floor(range(a,b+1))) end
 local function coin() return rng()<.5 end
 local s,index
 if mode=='bank' then
  index=integer(1,#Core.chaos_bank);s=Core.chaos_values(index)
  -- Correlated changes preserve acceleration, contour, and equal-value relationships.
  local timing=range(.94,1.06);local pitch=range(.96,1.04);local motion=range(.94,1.06)
  for _,key in ipairs({'slice','slice_end','interval0','interval1','gap'}) do s[key]=s[key]*timing end
  for _,key in ipairs({'pitch0','pitch1','bend0','bend_mid','bend1'}) do s[key]=s[key]*pitch end
  for _,key in ipairs({'gain0','gain_mid','gain1','trem0','trem1','depth','pan0','pan1'}) do s[key]=s[key]*motion end
  s.curve=s.curve*range(.97,1.03)
 else
  s=Core.settings()
  for key,sp in pairs(Core.specs) do s[key]=range(sp[1],sp[2]) end
  for key,value in pairs(Core.defaults) do if type(value)=='boolean' then s[key]=coin() end end
  s.count=integer(1,128);s.pattern=integer(1,4);s.tail=integer(1,2)
  s.slice_fade_in=range(0,2);s.slice_fade_out=range(0,2)
  -- Bound the aggregate repetition duration, not merely each individual field.
  local max_interval=min(60000,240000/s.count)
  s.interval0=range(1,max_interval);s.interval1=range(1,max_interval)
  if not s.retrigger_on and not s.tail_on then if coin() then s.retrigger_on=true else s.tail_on=true end end
 end
 for key,sp in pairs(Core.specs) do s[key]=clamp(Core.quantize(key,s[key],true),sp[1],sp[2]) end
 if not duration then
  s.gap=min(s.gap,max(0,min(s.interval0,s.interval1)-1))
  if not s.retrigger_on then s.tail=1 end
  return s,index
 end
 assert(duration>0 and sr and sr>0,'素材の長さまたはサンプリングレートが不正です。')
 local total=floor(duration*1000+1e-8)
 if total<1 then return nil,'1ms以上の素材を選択してください。' end
 local cap=mode=='bank' and min(60000,total) or min(60000,floor(duration*200+1e-8))
 if cap<1 then
  -- Integer-ms slices cannot represent 20% of a source shorter than 5 ms.
  s.retrigger_on=false;s.tail_on=true;s.tail=1;cap=1
 end
 s.slice=min(s.slice,cap);s.slice_end=min(s.slice_end,cap)
 if mode~='bank' then
  s.slice=integer(1,cap);s.slice_end=integer(1,cap)
  s.offset=integer(0,min(Core.specs.offset[2],max(0,total-max(s.slice,s.slice_end))))
 else s.offset=min(s.offset,max(0,total-max(s.slice,s.slice_end))) end
 local min_ms=max(1,math.ceil(2000/sr))
 s.interval0=max(s.interval0,min_ms);s.interval1=max(s.interval1,min_ms)
 s.gap=min(s.gap,min(s.interval0,s.interval1)-min_ms)
 local span=min(s.slice,s.vary_length and s.slice_end or s.slice,duration*1000-s.offset)
 local max_pitch=min(24,floor(12*math.log(span*sr/2000)/math.log(2)*100)/100)
 if max_pitch < -24 then s.retrigger_on=false;s.tail_on=true;s.tail=1
 else s.pitch0=min(s.pitch0,max_pitch);s.pitch1=min(s.pitch1,max_pitch) end
 if not s.retrigger_on then s.tail=1 end
 if s.tail==2 and s.offset+max(s.slice,s.slice_end)>=total then s.tail=1 end
 local ok,plan=pcall(Core.plan,s,duration,sr)
 local max_seconds=min(600,(0xffffffff-44)/(sr*8))
 if not ok or plan.duration>max_seconds then
  -- Long source tails can exceed the renderer limit: retain a valid sliced result.
  if cap<1 or max_pitch < -24 then return nil,'この素材では生成可能な範囲を作れませんでした。' end
  s.tail_on=false;s.retrigger_on=true;s.count=max(1,s.count)
  local limit=max(min_ms,floor(min(240000,max_seconds*1000*.9)/s.count))
  s.interval0=min(s.interval0,limit);s.interval1=min(s.interval1,limit)
  s.gap=min(s.gap,min(s.interval0,s.interval1)-min_ms)
  ok,plan=pcall(Core.plan,s,duration,sr)
 end
 if not ok or plan.duration>max_seconds then return nil,'この素材では生成可能な範囲を作れませんでした。' end
 return s,index
end
local function exp_area(rate,k,u)
 return abs(k)<1e-9 and rate*u or rate*(math.exp(k*u)-1)/k
end
local function read_exact(f,n) local s=f:read(n);assert(s and #s==n,'WAVが途中で切れています。');return s end
function Core.scan(path,options)
 local audio_only=options and options.audio_only
 local f,err=io.open(path,'rb');assert(f,err)
 local ok,result=xpcall(function()
  local size=assert(f:seek('end'));assert(f:seek('set',0));local header=read_exact(f,12)
  assert(header:sub(1,4)=='RIFF' and header:sub(9,12)=='WAVE','通常のRIFF/WAVのみ対応しています（RF64/Wave64非対応）。')
  local declared_size=string.unpack('<I4',header,5)+8
  assert(audio_only or declared_size==size,'WAVサイズが一致しません。レンダー未完了または破損ファイルです。')
  local w={size=size,declared_size=declared_size};local offset=12
  while offset<size do
   assert(offset+8<=size,'WAVチャンクヘッダーが不正です。');assert(f:seek('set',offset))
   local h=read_exact(f,8);local id=h:sub(1,4);local n=string.unpack('<I4',h,5)
   -- Source-audio reading needs a complete payload, not the optional final pad.
   local pad=audio_only and id=='data' and 0 or n%2
   assert(offset+8+n+pad<=size,'WAVチャンク長が不正です。音声データが途中で切れている可能性があります。')
   local c={id=id,offset=offset,size=n,total=8+n+n%2}
   if id=='fmt ' then
    assert(not w.sr and n>=16 and n<=4096,'WAV fmtが不正です。');assert(f:seek('set',offset+8))
    local fmt=read_exact(f,n);local tag,ch,sr,rate,align,bits=string.unpack('<I2I2I4I4I2I2',fmt)
    if tag==65534 then
     assert(n>=40 and string.unpack('<I2',fmt,17)>=22,'WAVEFORMATEXTENSIBLEが不正です。')
     assert(fmt:sub(29,40)=='\0\0\16\0\128\0\0\170\0\56\155\113','未対応のWAVサブフォーマットです。')
     tag=string.unpack('<I4',fmt,25)
    end
    assert((tag==1 and (bits==16 or bits==24 or bits==32)) or (tag==3 and (bits==32 or bits==64)),'PCM / IEEE float WAVのみ対応しています。')
    assert(ch>=1 and ch<=64 and sr>0 and align==ch*bits//8 and rate==sr*align,'WAV音声フォーマットが不正です。')
    w.sr,w.channels,w.bits,w.align,w.tag,w.fmt=sr,ch,bits,align,tag,fmt
   elseif id=='data' then assert(not w.data,'複数dataチャンクには対応していません。');w.data=c end
   offset=offset+c.total
   -- Existing files may contain trailing application data or stale RIFF sizes.
   -- Do not interpret that tail when only the verified audio payload is needed.
   if audio_only and w.sr and w.data then break end
  end
  assert(w.sr and w.data and w.data.size%w.align==0,'音声データがありません、またはサンプル境界が不正です。')
  w.frames=w.data.size//w.align;return w
 end,debug.traceback)
 f:close();if not ok then error(result,0) end;return result
end

function Core.plan(s,duration,sr)
 assert(s.retrigger_on~=false or s.tail_on~=false,'パネルを1つ以上ONにしてください。')
 for k,sp in pairs(Core.specs) do local v=s[k];assert(finite(v) and v>=sp[1] and v<=sp[2] and (not sp[3] or v%1==0),'設定値が不正です: '..k) end
 local off=s.offset/1000;assert(off<duration,'切り出し開始がアイテムの末尾を超えています。')
 local span=min(s.slice/1000,duration-off);local events={};local at=0
 for i=1,(s.retrigger_on~=false and s.count or 0) do
  local u=s.count>1 and ((i-1)/(s.count-1))^s.curve or 0
  local pitch=s.pitch0+(s.pitch1-s.pitch0)*u;local rate=2^(pitch/12)
  local slot=(s.interval0+(s.interval1-s.interval0)*u)/1000
  local eventspan=min((s.slice+(s.vary_length and (s.slice_end-s.slice)*u or 0))/1000,duration-off)
  local audible=min(eventspan/rate,slot-s.gap/1000)
  assert(audible>=2/sr,'無音時間が間隔以上です。間隔を広げるか無音時間を短くしてください。')
  local reverse=s.pattern==2 or s.pattern==3 and i%2==0 or s.pattern==4 and (i-1)%4>=2
  events[#events+1]={start=at,len=audible,source=off,span=eventspan,rate=rate,reverse=reverse,pitch=pitch,slot=slot,fade_in=min(s.slice_fade_in/1000,audible*.5),fade_out=min(s.slice_fade_out/1000,audible*.5)}
  at=at+slot
 end
 if s.tail_on~=false then
  local lastspan=events[#events] and events[#events].span or span
  local from=(s.tail==1 or s.retrigger_on==false) and 0 or off+lastspan;local remaining=duration-from
  if remaining>1/sr then
   local b0=s.motion and s.bend0 or 0;local b1=s.motion and s.bend1 or 0
   local r0=2^(b0/12);local k=(b1-b0)*math.log(2)/12
   local mean=abs(k)<1e-9 and r0 or r0*(math.exp(k)-1)/k
   local event={start=at,len=remaining/mean,source=from,span=remaining,rate=r0,k=k,tail=true,reverse=false}
   if s.motion and s.flyby then
    event.pass=s.pass/100;event.midrate=2^(s.bend_mid/12)
    event.k0=(s.bend_mid-b0)*math.log(2)/12/event.pass
    event.k1=(b1-s.bend_mid)*math.log(2)/12/(1-event.pass)
    event.first_area=exp_area(r0,event.k0,event.pass)
    mean=event.first_area+exp_area(event.midrate,event.k1,1-event.pass)
    event.len=remaining/mean
   end
   events[#events+1]=event
   at=at+remaining/mean
  end
 end
 assert(at>0 and #events>0,'リピート回数または最後の音を設定してください。')
 assert(at<=600,'試作の生成上限は10分です。')
 return {events=events,duration=at,frames=max(1,floor(at*sr+.5)),sr=sr,settings=s}
end
function Core.source_position(e,t,sr)
 if e.tail then
  local u=t/e.len
  if e.pass then
   if u<=e.pass then return e.source+e.len*exp_area(e.rate,e.k0,u),e.rate*math.exp(e.k0*u) end
   return e.source+e.len*(e.first_area+exp_area(e.midrate,e.k1,u-e.pass)),e.midrate*math.exp(e.k1*(u-e.pass))
  end
  local consumed=abs(e.k)<1e-9 and e.rate*t or e.rate*e.len*(math.exp(e.k*u)-1)/e.k
  return e.source+consumed,e.rate*math.exp(e.k*u)
 end
 return e.source+(e.reverse and max(0,e.span-1/sr-t*e.rate) or t*e.rate),e.rate
end
function Core.gains(e,t,s)
 local u=clamp(t/e.len,0,1);local edge=e.tail and min(s.fade/1000,e.len/2) or 0
 local gain=edge>0 and min(1,t/edge,(e.len-t)/edge) or 1
 -- Half-cosine de-click at both retrigger edges; tail uses its own fade control.
 if not e.tail then
  local fade_in,fade_out=e.fade_in,e.fade_out
  if fade_in>0 and t<fade_in then gain=.5-.5*math.cos(math.pi*clamp(t/fade_in,0,1))
  elseif fade_out>0 and e.len-t<fade_out then gain=.5-.5*math.cos(math.pi*clamp((e.len-t)/fade_out,0,1)) end
 end
 local pan=0
 if e.tail and s.motion then
  local db=s.gain0+(s.gain1-s.gain0)*u
  if s.flyby then
   local pass=s.pass/100
   db=u<=pass and s.gain0+(s.gain_mid-s.gain0)*u/pass or s.gain_mid+(s.gain1-s.gain_mid)*(u-pass)/(1-pass)
  end
  gain=gain*10^(db/20)
  local phase=2*math.pi*(s.trem0*t+.5*(s.trem1-s.trem0)*t*t/e.len)
  gain=gain*(1-s.depth/100*(.5-.5*math.cos(phase)))
  pan=(s.pan0+(s.pan1-s.pan0)*u)/100
 end
 -- Stereo balance: preserve unity on both channels at center.
 return gain*(pan>0 and math.cos(pan*math.pi/2) or 1),gain*(pan<0 and math.cos(pan*math.pi/2) or 1)
end
function Core.inspect()
 local project=R.EnumProjects(-1,'');assert(R.CountSelectedMediaItems(project)==1,'音声アイテムを1つ選択してください。')
 local item=R.GetSelectedMediaItem(project,0);local take=R.GetActiveTake(item)
 assert(take and not R.TakeIsMIDI(take),'音声テイクを選択してください。')
 local src=R.GetMediaItemTake_Source(take)
 assert(R.GetMediaSourceType(src,'')=='WAVE','試作版は通常のWAVが対象です。逆再生・圧縮音声などは先にグルーしてください。')
 assert(abs(R.GetMediaItemTakeInfo_Value(take,'D_PLAYRATE')-1)<1e-9 and abs(R.GetMediaItemTakeInfo_Value(take,'D_PITCH'))<1e-9 and R.GetTakeNumStretchMarkers(take)==0,'速度・ピッチ・ストレッチ済みの素材は、先にグルーしてください。')
 assert(R.GetMediaItemTakeInfo_Value(take,'I_CHANMODE')==0,'チャンネルモードを変更した素材は先にグルーしてください。')
 local path=R.GetMediaSourceFileName(src,'');local w=Core.scan(path,{audio_only=true})
 assert(w.channels<=2,'試作版はモノラル／ステレオ対応です。')
 local offset=R.GetMediaItemTakeInfo_Value(take,'D_STARTOFFS');local len=R.GetMediaItemInfo_Value(item,'D_LENGTH')
 assert(offset>=0 and offset+len<=w.frames/w.sr+1/w.sr,'ソース終端をまたぐアイテムは先にグルーしてください。')
 return {project=project,item=item,take=take,track=R.GetMediaItemTrack(item),path=path,wav=w,offset=offset,duration=len,pos=R.GetMediaItemInfo_Value(item,'D_POSITION'),name=R.GetTakeName(take) or 'Audio'}
end
function Core.reader(p,decoded)
 local f=assert(io.open(p.path,'rb'));local w=p.wav
 local r={file=f,cache={},order={}};local bytes=w.bits//8
 local fmt=w.tag==3 and (w.bits==32 and '<f' or '<d') or '<i'..bytes
 local div=w.tag==3 and 1 or 2^(w.bits-1)
 function r:blockdata(block)
  local data=self.cache[block]
  if not data then
   assert(self.file:seek('set',w.data.offset+8+block*4096*w.align))
   local raw=assert(self.file:read(min(4096,w.frames-block*4096)*w.align))
   if decoded then
    data={};local index=1
    for at=1,#raw,bytes do
     local v=string.unpack(fmt,raw,at)/div;data[index]=finite(v) and v or 0;index=index+1
    end
   else data=raw end
   self.cache[block]=data;self.order[#self.order+1]=block
   if #self.order>12 then self.cache[table.remove(self.order,1)]=nil end
  end
  return data
 end
 function r:get(frame,ch)
  if frame<0 or frame>=w.frames then return 0 end
  local data=self:blockdata(frame//4096);local at=frame%4096*w.channels+ch
  if decoded then return data[at] end
  local v=string.unpack(fmt,data,1+(at-1)*bytes)/div
  return finite(v) and v or 0
 end
 function r:pair(frame)
  if frame<0 or frame>=w.frames then return 0,0 end
  local data=self:blockdata(frame//4096);local at=frame%4096*w.channels+1
  if decoded then return data[at],data[at+(w.channels==1 and 0 or 1)] end
  local l,r
  if w.channels==1 then l=string.unpack(fmt,data,1+(at-1)*bytes)/div;r=l
  else l,r=string.unpack(fmt..fmt:sub(2),data,1+(at-1)*bytes);l=l/div;r=r/div end
  return finite(l) and l or 0,finite(r) and r or 0
 end
 local pi,sin,cos=math.pi,math.sin,math.cos
 local window_step=pi/12;local wc,ws=cos(window_step),sin(window_step)
 local last_cutoff,step_cos,step_sin
 function r:stereo(t,rate)
  local pos=(p.offset+t)*w.sr;local nearest=floor(pos+.5)
  if rate==1 and abs(pos-nearest)<1e-7 then return self:pair(nearest) end
  local center=floor(pos);local first,last=center-11,center+12
  local cutoff=min(1,1/max(1,rate))
  if cutoff~=last_cutoff then
   local step=pi*cutoff;step_cos=cos(step);step_sin=sin(step);last_cutoff=cutoff
  end
  local d=pos-first;local angle=pi*d*cutoff
  local sx,cx=sin(angle),cos(angle)
  local sw,cw=sin(window_step*d),cos(window_step*d)
  local left,right,norm=0,0,0
  -- One cache lookup for the entire kernel when all taps share a decoded block.
  local data,index
  if decoded and first>=0 and last<w.frames and first//4096==last//4096
   and first/w.sr-p.offset>=0 and last/w.sr-p.offset<p.duration then
   data=self:blockdata(first//4096);index=first%4096*w.channels+1
  end
  local channels=w.channels;local right_offset=channels==1 and 0 or 1
  for n=first,last do
   local weight=(abs(pi*d*cutoff)<1e-9 and cutoff or sx/(pi*d))*(.5+.5*cw)
   if data then
    left=left+data[index]*weight;right=right+data[index+right_offset]*weight;index=index+channels
   else
    local relative=n/w.sr-p.offset
    if relative>=0 and relative<p.duration then local l,r=self:pair(n);left=left+l*weight;right=right+r*weight end
   end
   norm=norm+weight
   -- Advance the same sinc/Hann kernel via angle recurrence instead of 48 trig calls.
   sx,cx=sx*step_cos-cx*step_sin,cx*step_cos+sx*step_sin
   sw,cw=sw*wc-cw*ws,cw*wc+sw*ws
   d=d-1
  end
  if norm==0 then return 0,0 end
  return left/norm,right/norm
 end
 return r
end
function Core.wav_header(sr,frames)
 local bytes=frames*8;assert(bytes+36<=0xffffffff,'WAVが4GiBを超えます。')
 return 'RIFF'..string.pack('<I4',bytes+36)..'WAVEfmt '..string.pack('<I4I2I2I4I4I2I2',16,3,2,sr,sr*8,8,32)..'data'..string.pack('<I4',bytes)
end
function Core.abort(j)
 if not j then return end
 if j.peak_source then
  if j.peak_active then R.PCM_Source_BuildPeaks(j.peak_source,2);j.peak_active=nil end
  R.PCM_Source_Destroy(j.peak_source);j.peak_source=nil
 end
 if j.reader and j.reader.file then j.reader.file:close();j.reader.file=nil end
 if j.file then j.file:close();j.file=nil end
 if j.temp then os.remove(j.temp);j.temp=nil end
end
function Core.start(p,s,target)
 local plan=Core.plan(s,p.duration,p.wav.sr)
 local existing=io.open(target,'rb');if existing then existing:close();error('出力ファイルが既に存在します。') end
 local j={source=p,plan=plan,target=target,temp=target..'.blt-part',frame=0,event=1,peak=0}
 local ok,err=pcall(function()
  local old=io.open(j.temp,'rb');if old then old:close();j.temp=nil;error('作業ファイルが既に存在します。') end
  j.reader=Core.reader(p,true);j.file=assert(io.open(j.temp,'wb'),'出力先BLTフォルダーへ書き込めません。保存先とアクセス権を確認してください。');assert(j.file:write(Core.wav_header(plan.sr,plan.frames)))
 end)
 if not ok then Core.abort(j);error(err,0) end
 return j
end
function Core.step(j,budget)
 local p,s=j.plan,j.plan.settings;local out={};local untilframe=min(p.frames,j.frame+(budget or 262144))
 local clock=R.time_precise or os.clock;local deadline=clock()+.012;local completed=j.frame
 local f=j.frame
 while f<untilframe do
  local t=f/p.sr
  while p.events[j.event] and t>=p.events[j.event].start+p.events[j.event].len do j.event=j.event+1 end
  local e=p.events[j.event]
  if not e or t<e.start then
   -- Silence is already known; write it in bounded blocks without per-sample DSP.
   local nextframe=e and math.ceil(e.start*p.sr) or untilframe
   -- Match the original f / sr comparison at floating-point event boundaries.
   if e and nextframe>f and (nextframe-1)/p.sr>=e.start then nextframe=nextframe-1 end
   local count=min(32768,untilframe-f,max(1,nextframe-f))
   out[#out+1]=string.rep('\0',count*8);f=f+count;completed=f
   if clock()>=deadline then break end
  else
   local localtime=t-e.start;local pos,rate=Core.source_position(e,localtime,p.sr)
   local gl,gr=Core.gains(e,localtime,s)
   local l,r=j.reader:stereo(pos,rate);l=l*gl;r=r*gr
   j.peak=max(j.peak,abs(l),abs(r));out[#out+1]=string.pack('<ff',l,r)
   f=f+1;completed=f
   if completed%256==0 and clock()>=deadline then break end
  end
 end
 assert(j.file:write(table.concat(out)));j.frame=completed
 if j.frame<p.frames then return false end
 assert(j.file:close());j.file=nil;j.reader.file:close();j.reader.file=nil
 local w=Core.scan(j.temp,{audio_only=true});assert(w.frames==p.frames,'生成WAVの検証に失敗しました。')
 local existing=io.open(j.target,'rb');if existing then existing:close();error('出力先が使用されています。') end
 assert(os.rename(j.temp,j.target));j.temp=nil;return true
end
function Core.peaks_step(j)
 if not j.peak_source then
  j.peak_source=assert(R.PCM_Source_CreateFromFile(j.target),'生成WAVを開けません。')
  j.peak_active=R.PCM_Source_BuildPeaks(j.peak_source,0)~=0
  if not j.peak_active then return true end
 end
 local remaining=R.PCM_Source_BuildPeaks(j.peak_source,1)
 if remaining==0 then R.PCM_Source_BuildPeaks(j.peak_source,2);j.peak_active=nil;return true end
 return false
end
function Core.placement(p,length)
 local track=assert(R.GetMediaItemTrack(p.item));local at=p.pos+p.duration+1
 local occupied={}
 for i=0,R.CountTrackMediaItems(track)-1 do
  local item=R.GetTrackMediaItem(track,i)
  occupied[#occupied+1]={R.GetMediaItemInfo_Value(item,'D_POSITION'),R.GetMediaItemInfo_Value(item,'D_LENGTH')}
 end
 table.sort(occupied,function(a,b) return a[1]<b[1] end)
 for _,v in ipairs(occupied) do if v[1]<at+length+1-1e-9 and v[1]+v[2]+1>at+1e-9 then at=v[1]+v[2]+1 end end
 return track,at
end
function Core.validate_target(p)
 assert(R.EnumProjects(-1,'')==p.project and R.ValidatePtr2(p.project,p.item,'MediaItem*'),'生成元のプロジェクトまたはアイテムが利用できません。')
 assert(R.GetMediaItemTrack(p.item)==p.track and R.GetActiveTake(p.item)==p.take
  and abs(R.GetMediaItemInfo_Value(p.item,'D_POSITION')-p.pos)<1e-9
  and abs(R.GetMediaItemInfo_Value(p.item,'D_LENGTH')-p.duration)<1e-9
  and abs(R.GetMediaItemTakeInfo_Value(p.take,'D_STARTOFFS')-p.offset)<1e-9
  and R.GetMediaSourceFileName(R.GetMediaItemTake_Source(p.take),'')==p.path
  and abs(R.GetMediaItemTakeInfo_Value(p.take,'D_PLAYRATE')-1)<1e-9
  and abs(R.GetMediaItemTakeInfo_Value(p.take,'D_PITCH'))<1e-9
  and R.GetTakeNumStretchMarkers(p.take)==0
  and R.GetMediaItemTakeInfo_Value(p.take,'I_CHANMODE')==0,
  '生成元のアイテム自体が編集されたため中止しました。')
end
function Core.commit(j)
 local p=j.source
 assert(not j.committed,'生成結果は配置済みです。');Core.validate_target(p)
 local track,at=Core.placement(p,j.plan.frames/j.plan.sr)
 local item
 R.Undo_BeginBlock2(p.project);R.PreventUIRefresh(1)
 local ok,err=xpcall(function()
  item=assert(R.AddMediaItemToTrack(track));local take=assert(R.AddTakeToMediaItem(item))
  local source=assert(j.peak_source,'波形ピークの準備が完了していません。')
  assert(R.SetMediaItemTake_Source(take,source),'生成WAVをテイクへ設定できません。');j.peak_source=nil
  R.SetMediaItemInfo_Value(item,'D_POSITION',at);R.SetMediaItemInfo_Value(item,'D_LENGTH',j.plan.frames/j.plan.sr)
  if R.GetMediaTrackInfo_Value(track,'I_FREEMODE')==2 then
   R.SetMediaItemInfo_Value(item,'I_FIXEDLANE',R.GetMediaItemInfo_Value(p.item,'I_FIXEDLANE'))
  end
  R.SetMediaItemInfo_Value(item,'B_LOOPSRC',0);R.SetMediaItemInfo_Value(item,'D_FADEINLEN',0);R.SetMediaItemInfo_Value(item,'D_FADEOUTLEN',0)
  R.SetMediaItemInfo_Value(item,'D_FADEINLEN_AUTO',0);R.SetMediaItemInfo_Value(item,'D_FADEOUTLEN_AUTO',0)
  R.GetSetMediaItemTakeInfo_String(take,'P_NAME','CR MINIM | '..p.name,true)
  R.SetMediaItemSelected(item,false);R.UpdateItemInProject(item)
 end,debug.traceback)
 if not ok and item then R.DeleteTrackMediaItem(track,item) end
 R.PreventUIRefresh(-1);R.Undo_EndBlock2(p.project,'BLT CR MINIM: バリエーション生成',-1);R.UpdateArrange()
 if not ok then error(tostring(err)..'\n生成WAVは保存済みです。',0) end
 j.committed=true;return item
end
if ...=='core_test' then return Core end

local SECTION=Core.SECTION
local W,H=846,930
local A=Core.settings()
A.status='音声アイテムを選択してください。'
A.active=true;A.content_dirty=true;A.progress=0
for k,v in pairs(Core.defaults) do
 local saved=R.GetExtState(SECTION,k)
 if saved~='' then
  if type(v)=='boolean' then A[k]=saved=='true'
  else local n=tonumber(saved);local sp=Core.specs[k];if finite(n) and (not sp or n>=sp[1] and n<=sp[2] and (not sp[3] or n%1==0)) then A[k]=n end end
 end
end
for key in pairs(Core.precision) do if finite(A[key]) then A[key]=Core.quantize(key,A[key],true) end end
local UI={}

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
  if next_draw_time>now+1/20 then next_draw_time=now end
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
  return string.format("%.3f",n):gsub("0+$",""):gsub("%.$","")
end

local function notice(s,warn) A.status=Core.display_message(s);A.warning=warn or false;A.content_dirty=true;wake_visuals() end
local function invalidate_wave_surface() A.wave_dirty=true;A.content_dirty=true;wake_visuals() end

local text_queue={}
local function font_spec(size,kind,bold) return BLT.spec(size,kind,bold,scale) end

local function font(size,kind,bold) BLT.font(size,kind,bold,scale,fonts) end
local function queue_text(t,x,y,right,bottom,flags,size,c,kind,bold,translated)
  local fk,_,_,key=font_spec(size,kind,bold)
  local bucket=text_queue[key]
  if not bucket then bucket={};text_queue[key]=bucket;text_queue[#text_queue+1]=bucket end
  bucket[#bucket+1]={text=t,x=x,y=y,right=right,bottom=bottom,flags=flags or 0,size=size,kind=fk,bold=bold and true or false,fontkey=key,c=c or C.text}
end
local function label(text,x,y,size,c,kind,w,h,flags,bold,literal)
  local t=literal and tostring(text) or Language.message(text)
  queue_text(t,sx(x),sy(y),sx(x+(w or 700)),sy(y+(h or size+8)),flags or 0,size,c,kind,bold,t~=tostring(text))
end

local function measure(text,size,kind,bold) font(size,kind,bold);return BLT.metricsFor(Language.message(text))/scale end
local function right_label(text,right,y,size,c,kind,bold)
  local t=Language.message(text);local tw=measure(t,size,kind,bold)
  queue_text(t,sx(right-tw),sy(y),sx(right+2),sy(y+size+9),0,size,c,kind,bold)
end

local function flush_text_queue()
  if #text_queue==0 then return end
  for _,b in ipairs(text_queue) do
    local first=b[1]
    font(first.size,first.kind,first.bold)
    for _,cmd in ipairs(b) do
      color(cmd.c);gfx.x,gfx.y=cmd.x,cmd.y
      gfx.drawstr(cmd.translated and BLT.ui.fit(cmd.text,cmd.right-cmd.x) or cmd.text,cmd.flags,cmd.right,cmd.bottom)
    end
  end
  text_queue={}
end

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
  chameleonPressed=false,resizeCursors={},resizeCursorMode=nil,titleH=26,windowTitle='BLT CR MINIM',titleText='C R   M I N I M',
  minW=846,minH=978,mint={0.38,0.88,0.72},ice={0.65,0.895,1.0},red={1.0,0.27,0.34},
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
  redraw_dirty=true; A.content_dirty=true; A.wave_dirty=true
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
    redraw_dirty=true; A.content_dirty=true; A.wave_dirty=true
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

function UI.dirty() A.content_dirty=true;wake_visuals() end
function UI.refresh()
 for key in pairs(Core.precision) do if finite(A[key]) then A[key]=Core.quantize(key,A[key],true) end end
 if A.retrigger_on==false and A.tail==2 then A.tail=1 end
 if A.source and A.source.duration>=.001 then
  local limit=floor(A.source.duration*1000+1e-8)
  local values={offset=clamp(A.offset,0,limit-1)}
  values.slice=clamp(A.slice,1,min(60000,limit-values.offset));values.slice_end=clamp(A.slice_end,1,min(60000,limit-values.offset))
  for k,v in pairs(values) do if abs(A[k]-v)>1e-7 then A[k]=v;if UI.flash then UI.flash('field_'..k) end end end
 end
 for k in pairs(Core.defaults) do BLT.store(SECTION,k,tostring(A[k]),true) end
 A.plan=nil;A.prediction=nil
 if A.source then local ok,p=pcall(Core.plan,A,A.source.duration,A.source.wav.sr);if ok then A.plan=p;A.problem=nil else A.problem=tostring(p) end end
 UI.dirty()
end
function UI.safe(fn)
 local ok,err=xpcall(fn,debug.traceback)
 if not ok then if BLT.cleanup(Core.abort,A.job) then A.job=nil end;A.busy=false;BLT.cleanup(UI.wave_close);notice(tostring(err):match('^(.-)\nstack traceback:') or tostring(err),true);BLT.recoverInput(A,err) end
 return ok
end
function UI.geometry()
 -- Anchor content below the app bar; extra window height belongs below the UI.
 scale=min(gfx.w/W,(gfx.h-Chrome.titleH)/H);ox=(gfx.w-W*scale)/2;oy=Chrome.titleH-22*scale;BLT.viewport(scale,gfx.ext_retina or 1)
 mouse_x=(gfx.mouse_x-ox)/scale;mouse_y=(gfx.mouse_y-oy)/scale
end
function UI.poll(now,force)
 if not Media.ready() then return end
 if A.busy or not force and now<(A.poll_at or 0) then return end;A.poll_at=now+.4
 local project=R.EnumProjects(-1,'');local rev=R.GetProjectStateChangeCount(project)
 local selected=R.GetSelectedMediaItem(project,0);local count=R.CountSelectedMediaItems(project)
 if force or project~=A.project or rev~=A.revision or selected~=A.selected or count~=A.selected_count then
  A.project=project;A.revision=rev;A.selected=selected;A.selected_count=count
  local ok,p=pcall(Core.inspect);A.source=ok and p or nil;A.source_problem=not ok and tostring(p) or nil;UI.refresh();UI.wave_load()
 end
end
function UI.cancel()
 local retained=A.job and A.job.audio_done and A.job.target
 Core.abort(A.job);A.job=nil;A.busy=false
 notice(retained and '配置を中止しました。完成済みWAVは保持しています。' or '生成を中止しました。',false)
 UI.poll(R.time_precise(),true)
end
function UI.chaos()
 if A.busy or not UI.commit_edit() then return end
 UI.poll(R.time_precise(),true)
 if not A.chaos_rng then
  local seed=floor(R.time_precise()*1000000)%2147483646+1
  A.chaos_rng=function() seed=(seed*48271)%2147483647;return (seed-1)/2147483646 end
 end
 local mode=A.chaos_next or 'bank'
 local p=A.source
 local settings,index=Core.chaos(mode,p and p.duration,p and p.wav.sr,A.chaos_rng)
 if not settings then notice(index,true);return end
 for key,value in pairs(settings) do A[key]=value end
 A.wave_drag=nil;A.wave_target='slice'
 A.chaos_next=mode=='bank' and 'random' or 'bank'
 UI.refresh()
end
-- Shared generated-audio destination. Keep project recording settings unchanged.
local function blt_output_directory(project)
 local root=R.GetProjectPathEx(project,'')
 assert(type(root)=='string' and root~='' and not root:find('%z'),
  '音声の保存先を取得できません。プロジェクトのメディア保存先を設定してください。')
 assert(root:match('^%a:[/\\]') or root:sub(1,1)=='/' or root:sub(1,2)=='\\\\',
  '音声の保存先が絶対パスではありません。プロジェクトのメディア保存先を確認してください。')
 local dir=root:gsub('[/\\]+$','')..'/BLT'
 R.RecursiveCreateDirectory(dir,0) -- Existing BLT folders are reused.
 return dir
end
function UI.execute()
 if not A.job and not A.busy and not A.batch and not Media.ready() then return end
 if A.busy then UI.cancel();return end
 if A.retrigger_on==false and A.tail_on==false then return end
 if not UI.commit_edit() then return end
 UI.poll(R.time_precise(),true);assert(A.source,A.source_problem);assert(A.plan,A.problem)
 local dir=blt_output_directory(A.project)
 local id=R.genGuid():gsub('[^%w]','');local target=dir..'/CR_MINIM_'..id..'.wav'
 local s={};for k in pairs(Core.defaults) do s[k]=A[k] end
 A.job=Core.start(A.source,s,target);A.busy=true;A.progress=0;UI.dirty()
end
function UI.step()
 if not Media.ready() then return end
 local j=A.job
 Core.validate_target(j.source)
 if not j.audio_done then j.audio_done=Core.step(j);A.progress=j.frame/j.plan.frames*.95 end
 if j.audio_done and Core.peaks_step(j) then
  Core.commit(j);A.last_output=j.target;A.job=nil;A.busy=false;A.progress=1
  notice(j.peak>1 and '生成完了。0 dBFS超過あり：生成アイテムの音量で調整してください。' or '生成完了。同じトラックの右側に配置しました。',j.peak>1)
  UI.poll(R.time_precise(),true)
 end
 A.content_dirty=true
end
local function button(id,x,y,w,h,title,fn,hint,enabled,accent)
 enabled=enabled~=false and not A.busy
 local hot=enabled and inside(x,y,w,h) and not Chrome.mouseActive
 local hover=animate(id,hot and 1 or 0)
 local push=pressed==id and (gfx.mouse_cap&1)~=0 and 1.5 or 0;y=y+push
 cut_panel(x,y,w,h,6,C.field,enabled and 1 or .45,C.edge,enabled and .7 or .2)
 gradient(x+1,y+1,w-2,h-2,C.accent3,C.bg,.12+hover*.2,.05,true)
 line(x+5,y,x+w,y,C.accent2,.15+hover*.45);line(x,y+1,x,y+h-1,C.edge2,.18+hover*.35)
 if accent then line(x+8,y+h-3,x+w-10,y+h-3,accent,.7) end
 label(title,x+7,y+2,16,enabled and (hot and C.text or C.muted) or C.faint,1,w-14,h-3,1|4)
 register(id,x,y-push,w,h,fn,hint,enabled)
end
local function panel(x,y,w,h,title,code)
 cut_panel(x,y,w,h,11,C.panel,1,C.edge,.5)
 label(code or '',x+16,y+13,11,C.faint,2,w-30,16,0,true)
 label(title,x+16,y+31,16,C.text,1,w-30,26,0,true)
end

local field_specs=Core.specs
function UI.flash(id)
 A.field_flash=A.field_flash or {};A.field_flash[id]=R.time_precise();UI.dirty()
end
function UI.commit_edit()
 local e=A.edit;if not e then return true end
 local value=e.text
 if e.spec then
  local ok,n=pcall(function() return tonumber(value) end)
  local s=e.spec
  if not ok or not finite(n) then UI.flash(e.id);A.edit=nil;UI.refresh();return true end
  value=clamp(n,s[1],s[2])
  if s[3] then value=floor(value+.5) end
  value=Core.quantize(e.key,value,true)
  if abs(value-n)>1e-9 then UI.flash(e.id) end
 end
 e.owner[e.key]=value;A.edit=nil;UI.refresh();return true
end
function UI.begin_edit(id,owner,key,spec)
 if not UI.commit_edit() then return end
 A.edit={id=id,owner=owner,key=key,spec=spec,text=Core.number_text(key,owner[key]),selected=true};UI.dirty()
end
function UI.edit_key(k)
 k=BLT.key(k);if k==0 then return end

 local e=A.edit;if not e then return end
 if k==27 then A.edit=nil;UI.dirty();return end
 if k==13 or k==9 then UI.commit_edit();return end
 if k==1 then e.selected=true
 elseif k==8 or k==6579564 then
  local pos=utf8.offset(e.text,-1);e.text=e.selected and '' or (pos and e.text:sub(1,pos-1) or '');e.selected=false
 elseif k>=32 and k<=126 or (k&0xff000000)==0x75000000 then
  local cp=k>=0x75000000 and (k&0xffffff) or k
  if cp>0x10ffff or cp>=0xd800 and cp<=0xdfff then return end
  if e.spec and not (cp>=48 and cp<=57 or cp==46 or cp==45) then UI.flash(e.id);return end
  if #e.text<512 then e.text=(e.selected and '' or e.text)..utf8.char(cp);e.selected=false end
 end
 if e.spec then
  local ok,n=pcall(function() return tonumber(e.text) end)
  if not ok or not finite(n) or n<e.spec[1] or n>e.spec[2] or (e.spec[3] and n%1~=0) then UI.flash(e.id) end
 end
 UI.dirty()
end
function UI.field(key,x,y,w,enabled)
 local owner=A;local spec=field_specs[key]
 local id='field_'..key;local active=A.edit and A.edit.id==id
 enabled=enabled~=false and not A.busy
 rect(x,y,w,28,enabled and C.field or C.bg,1)
 local stamp=A.field_flash and A.field_flash[id];local glow=stamp and max(0,1-(R.time_precise()-stamp)/1.35) or 0
 if glow>0 then
  rect(x-5,y-4,w+10,40,C.red,.035*glow);rect(x-2,y-2,w+4,36,C.red,.075*glow)
  rect(x,y,w,28,C.red,.17*glow)
 end
 line(x,y+28,x+w,y+28,glow>0 and C.red or C.edge,.6)
 line(x,y,x,y+28,glow>0 and C.red or enabled and C.accent2 or C.edge,enabled and (active and .8 or .35) or .18)
 if active and A.edit.selected then rect(x+5,y+4,w-10,24,C.accent3,.8) end
 label(active and A.edit.text or Core.number_text(key,owner[key]),x+8,y+2,16,enabled and C.text or C.faint,3,w-16,25)
 local hint='クリック入力 / 上下ドラッグ / ホイール'
 if Core.fine_adjustment(key,spec) then hint=hint..' / Shiftで微調整' end
 register(id,x,y,w,28,function() UI.begin_edit(id,owner,key,spec) end,hint,enabled)
 local widget=widgets[#widgets];widget.field={id=id,owner=owner,key=key,spec=spec}
end
function UI.field_adjust(f,raw)
 local s=f.spec;if not s then return end
 local n=clamp(raw,s[1],s[2]);if s[3] then n=floor(n+.5) end
 n=Core.quantize(f.key,n,true)
 if abs(n-raw)>1e-9 then UI.flash(f.id) end
 f.owner[f.key]=n;UI.refresh()
end
function UI.field_input(hit,down)
 local f=hit and hit.field
 if gfx.mouse_wheel~=0 and f and f.spec and hit.enabled then
  local fine=(gfx.mouse_cap&8)~=0 and Core.fine_adjustment(f.key,f.spec)
  if UI.commit_edit() then UI.field_adjust(f,f.owner[f.key]+(gfx.mouse_wheel>0 and 1 or -1)*f.spec[4]*(fine and .1 or 1)) end
  gfx.mouse_wheel=0;return false
 end
 if down and not down_last then
  if not UI.commit_edit() then down_last=down;return true end
  if f and f.spec then A.field_drag={f=f,y=mouse_y,value=f.owner[f.key],moved=false} end
 end
 local d=A.field_drag
 if d and down and abs(mouse_y-d.y)>=3 then
  d.moved=true;A.edit=nil
  local fine=(gfx.mouse_cap&8)~=0 and Core.fine_adjustment(d.f.key,d.f.spec)
  UI.field_adjust(d.f,d.value+floor((d.y-mouse_y)/(fine and 8 or 3)+.5)*d.f.spec[4]*(fine and .1 or 1))
 end
 if d and not down then A.field_drag=nil;if d.moved then pressed=nil;down_last=false;return true end end
 return false
end

-- Bounded, approximate source overview. Rendering never reads the source file.
function UI.wave_close()
 if A.wave_job then A.wave_job.reader.file:close();A.wave_job=nil end
 if A.zoom_job then A.zoom_job.reader.file:close();A.zoom_job=nil end
end
function UI.wave_load()
 if not Media.ready() then return end
 local p=A.source
 local signature=p and table.concat({p.path,p.offset,p.duration,p.wav.size},'|') or ''
 if signature==A.wave_signature then return end
 UI.wave_close();A.wave_signature=signature;A.wave=nil;A.wave_drag=nil;A.zoom=nil;A.zoom_signature=nil
 A.view_start=0;A.view_end=p and p.duration or 1
 if p then A.wave_job={source=p,reader=Core.reader(p),index=1,bins={},count=2048} end
 UI.dirty()
end
function UI.wave_step()
 if not Media.ready() then return end
 UI.zoom_step()
 local j=A.wave_job;if not j then return end
 local clock=R.time_precise or os.clock;local deadline=clock()+.006
 local p=j.source;local total=max(1,floor(p.duration*p.wav.sr))
 for b=j.index,j.count do
  local lo,hi=0,0;local start=floor((b-1)*total/j.count);local ending=max(start,floor(b*total/j.count)-1)
  local samples=min(64,ending-start+1)
  for k=0,samples-1 do
   local frame=floor(p.offset*p.wav.sr+.5)+start+floor(k*(ending-start)/max(1,samples-1))
   local l,r=j.reader:pair(frame);lo=min(lo,l,r);hi=max(hi,l,r)
  end
  j.bins[b]={lo,hi};j.index=b+1
  if b%16==0 and clock()>=deadline then break end
 end
 A.wave={bins=j.bins,count=j.count,duration=p.duration};A.content_dirty=true
 if j.index>j.count then j.reader.file:close();A.wave_job=nil end
end
function UI.zoom_step()
 local p=A.source;if not p then return end
 local start,ending=A.view_start or 0,A.view_end or p.duration
 local signature=tostring(start)..':'..tostring(ending)
 if signature~=A.zoom_signature then
  if A.zoom_job then A.zoom_job.reader.file:close();A.zoom_job=nil end
  A.zoom=nil;A.zoom_signature=signature
  if ending-start<p.duration*.98 then A.zoom_job={reader=Core.reader(p),index=1,count=868,bins={},start=start,duration=ending-start} end
 end
 local j=A.zoom_job;if not j then return end
 local clock=R.time_precise or os.clock;local deadline=clock()+.006
 local sr=p.wav.sr
 for b=j.index,j.count do
  local a=floor((p.offset+j.start+(b-1)/j.count*j.duration)*sr)
  local z=max(a,floor((p.offset+j.start+b/j.count*j.duration)*sr)-1)
  local samples=min(64,z-a+1);local lo,hi=0,0
  for k=0,samples-1 do local l,r=j.reader:pair(a+floor(k*(z-a)/max(1,samples-1)));lo=min(lo,l,r);hi=max(hi,l,r) end
  j.bins[b]={lo,hi};j.index=b+1
  if b%16==0 and clock()>=deadline then break end
 end
 A.zoom={bins=j.bins,count=j.count,start=j.start,duration=j.duration};A.content_dirty=true
 if j.index>j.count then j.reader.file:close();A.zoom_job=nil end
end
function UI.wave_bin(t,zoom)
 local w=zoom and A.zoom or A.wave;if not w then return 0,0 end
 local index=clamp(floor((t-(w.start or 0))/w.duration*w.count)+1,1,w.count)
 local b=w.bins[index];if not b then return 0,0 end;return b[1],b[2]
end
function UI.range_edit(mode,value,origin,target)
 local p=A.source;if not p then return end
 local sr=p.wav.sr;local duration=floor(p.duration*1000+1e-8)/1000
 local minimum=min(.001,duration);local function snap(t) return floor(t*1000+.5)/1000 end
 local start,ending=origin.start,origin.ending
 if mode=='move' then local len=ending-start;start=clamp(snap(origin.start+value),0,max(0,duration-len));ending=start+len
 elseif mode=='left' then start=clamp(snap(value),max(0,ending-60),ending-minimum)
 elseif mode=='right' then ending=clamp(snap(value),start+minimum,min(duration,start+60))
 else start=clamp(snap(min(value,origin.anchor)),0,max(0,duration-minimum));ending=clamp(snap(max(value,origin.anchor)),start+minimum,min(duration,start+60)) end
 if abs(A.offset-start*1000)<1e-8 and abs(A[target]-(ending-start)*1000)<1e-8 then return end
 A.offset=start*1000;A[target]=(ending-start)*1000
 -- Both slices share their source start; keep both endpoints within the item.
 A.slice=min(A.slice,(duration-start)*1000);A.slice_end=min(A.slice_end,(duration-start)*1000)
 UI.refresh()
end
function UI.wave_draw()
 local x,y,w,h=36,160,774,53
 local p=A.source;local duration=p and p.duration or 1
 local vs,ve=A.view_start or 0,A.view_end or duration;local span=max(.000001,ve-vs)
 local function px(t) return x+(t-vs)/span*w end
 rect(x,y,w,h,C.field,1);line(x,y+h/2,x+w,y+h/2,C.edge,.3)

 local target=A.vary_length and A.wave_target=='slice_end' and 'slice_end' or 'slice'
 label('全体',684,130,12,C.accent2,1,40,18,1)
 register('wave_full',677,127,48,25,function() A.view_start=0;A.view_end=duration;UI.dirty() end,'波形全体へ戻す',p~=nil)
 label('範囲拡大',730,130,12,C.accent2,1,69,18,1)
 register('wave_zoom',728,127,73,25,function()
  local a=A.offset/1000;local n=A[target]/1000;A.view_start=max(0,a-n*.15);A.view_end=min(duration,a+n*1.15);UI.dirty()
 end,'切り出し範囲を拡大',p~=nil)
 if p then
  for i=0,w-1 do
   local a,b=UI.wave_bin(vs+(i+.5)/w*span,true)
   line(x+i,y+h/2-clamp(b,-1,1)*(h/2-3),x+i,y+h/2-clamp(a,-1,1)*(h/2-3),C.accent2,.52)
  end
  for _,k in ipairs({'slice_end','slice'}) do
   if A.retrigger_on~=false and (k=='slice' or A.vary_length) then
    local a,b=px(A.offset/1000),px(min(duration,(A.offset+A[k])/1000));local c=k=='slice' and C.accent2 or C.warn
    local left,right=clamp(a,x,x+w),clamp(b,x,x+w)
    if right>left then rect(left,y,right-left,h,c,k==target and .12 or .04) end
    if b>=x and b<=x+w then line(b,y,b,y+h,c,.9);rect(b-4,y+(k=='slice' and 0 or h-10),8,10,c,.9) end
    if a>=x and a<=x+w then line(a,y,a,y+h,c,.8);rect(a-4,y+(k=='slice' and 0 or h-10),8,10,c,.9) end
   end
  end
 end
 label(string.format('%.4f s',vs),x,215,11,C.faint,3,100,18)
 right_label(string.format('%.4f s',ve),x+w,215,11,C.faint,3)
end
function UI.wave_input()
 local x,y,w,h=36,160,774,53;local down=(gfx.mouse_cap&1)~=0
 if not A.source or A.retrigger_on==false or A.busy or Chrome.mouseActive then A.wave_drag=nil;return false end
 local vs,ve=A.view_start or 0,A.view_end or A.source.duration;local span=ve-vs
 local function seconds(px) return vs+clamp((px-x)/w,0,1)*span end
 if inside(x,y,w,h) and gfx.mouse_wheel~=0 then
  local duration=A.source.duration;local sign=gfx.mouse_wheel>0 and 1 or -1
  if gfx.mouse_cap&8~=0 then A.view_start=clamp(vs-sign*span*.15,0,max(0,duration-span));A.view_end=A.view_start+span
  else local fraction=clamp((mouse_x-x)/w,0,1);local size=clamp(span*(sign>0 and .75 or 1/.75),min(.005,duration),duration)
   A.view_start=clamp(seconds(mouse_x)-size*fraction,0,duration-size);A.view_end=A.view_start+size end
  gfx.mouse_wheel=0;UI.dirty();return true
 end
 if down and not down_last and inside(x,y,w,h) then
  if not UI.commit_edit() then down_last=down;return true end
  -- Fixed upper handles = first range; lower handles = final range, even when coincident.
  local key=A.vary_length and mouse_y>=y+h/2 and 'slice_end' or 'slice'
  A.wave_target=key
  local a=A.offset/1000;local b=min(A.source.duration,(A.offset+A[key])/1000)
  local ax=x+(a-vs)/span*w;local bx=x+(b-vs)/span*w
  local mode=abs(mouse_x-bx)<=7 and 'right' or abs(mouse_x-ax)<=7 and 'left' or (mouse_x>ax and mouse_x<bx) and 'move' or 'new'
  A.wave_drag={mode=mode,target=key,start=a,ending=b,anchor=seconds(mouse_x)};pressed=nil
 end
 local d=A.wave_drag
 if d then
  if down then local t=seconds(mouse_x);UI.range_edit(d.mode,d.mode=='move' and t-d.anchor or t,d,d.target)
  else A.wave_drag=nil end
  down_last=down;return true
 end
 return false
end
function UI.result_preview(x,y,w,h)
 cut_panel(x,y,w,h,8,C.panel,1,C.edge,.5)
 label('RESULT / 結果予想',x+16,y+9,14,C.text,1,230,22)
 label('青：振幅  橙：ピッチ（速度連動）',x+265,y+10,12,C.muted,1,420,18)
 local p=A.plan
 if not p then return end
 right_label(string.format('%.3f 秒',p.duration),x+w-16,y+10,11,C.accent2,3)
 local bx,by,bw,bh=x+16,y+36,w-32,h-60;local middle=by+bh/2
 rect(bx,by,bw,bh,C.field,1);line(bx,middle,bx+bw,middle,C.edge,.35)
 local event=1;local lastx,lasty,last_event
 for i=0,floor(bw)-1 do
  local t=(i+.5)/bw*p.duration
  while p.events[event] and t>=p.events[event].start+p.events[event].len do event=event+1 end
  local e=p.events[event]
  if e and t>=e.start then
   local localtime=t-e.start;local pos,rate=Core.source_position(e,localtime,p.sr)
   local lo,hi=UI.wave_bin(pos);local l,r=Core.gains(e,localtime,A);local gain=max(l,r)
   line(bx+i,middle-clamp(hi*gain,-1,1)*bh*.46,bx+i,middle-clamp(lo*gain,-1,1)*bh*.46,C.accent2,.65)
   local pitch=12*math.log(rate)/math.log(2);local py=middle-clamp(pitch/24,-1,1)*bh*.46
   if last_event==event then line(lastx,lasty,bx+i,py,C.warn,.8) end
   lastx,lasty,last_event=bx+i,py,event
   if inside(bx+i,by,1,bh) then hover_hint=string.format('%.3f秒 / %s / %+.2f st / %.2f倍速',t,e.tail and '最後の音' or e.reverse and '逆転リトリガー' or 'リトリガー',pitch,rate) end
  else last_event=nil end
 end
 label('0 s',bx,y+h-20,10,C.faint,3,50,16)
 label('リトリガーから最後の音まで、同じ時間軸・振幅目盛で表示（簡易予想）',bx+60,y+h-20,10,C.faint,1,bw-120,16,1)
 right_label(string.format('%.3f s',p.duration),bx+bw,y+h-20,10,C.faint,3)
end

local function choose(id,x,y,w,text,key,value)
 button(id,x,y,w,30,text,function() A[key]=value;UI.refresh() end,text,A.panel_enabled~=false and not (key=='tail' and value==2 and A.retrigger_on==false),A[key]==value and C.accent2 or nil)
 if A[key]==value and A.panel_enabled~=false then rect(x+w*.36,y-2,w*.28,4,C.accent2,.85);rect(x,y,w,30,C.accent,.1) end
end
local function field_label(key,x,y,w,text,enabled,size)
 enabled=enabled~=false and A.panel_enabled~=false
 label(text,x,y,size or 14,enabled==false and C.faint or C.muted,1,w,19)
 UI.field(key,x,y+20,w,enabled)
end
local function checkbox(id,x,y,w,text,key)
 local enabled=not A.busy and A.panel_enabled~=false
 rect(x,y+4,15,15,C.field,1);line(x,y+4,x+15,y+4,C.edge,.8);line(x,y+19,x+15,y+19,C.edge,.8)
 if A[key] then line(x+3,y+11,x+6,y+15,enabled and C.accent2 or C.faint,.9);line(x+6,y+15,x+12,y+7,enabled and C.accent2 or C.faint,.9) end
 label(text,x+23,y+2,14,enabled and C.muted or C.faint,1,w-23,23)
 register(id,x,y,w,25,function() A[key]=not A[key];if key=='flyby' and A[key] then A.motion=true end;UI.refresh() end,text,enabled)
end
local function panel_switch(key,x,y)
 local on=A[key]~=false;local hot=inside(x,y,92,28) and not A.busy
 local tone=on and C.accent2 or C.faint
 cut_panel(x,y,92,28,5,C.field,1,on and C.accent2 or C.edge,hot and .9 or .5)
 -- Same rectangular indicator as the direction selector, on the left edge.
 rect(x-2,y+8,4,12,tone,on and .85 or .28)
 label(on and 'ON' or 'OFF',x+4,y,18,tone,3,84,28,5,true)
 register('switch_'..key,x,y,92,28,function() A[key]=not on;A.wave_drag=nil;UI.refresh() end,'OFFではこのパネルの音を生成しません',not A.busy)
end
local function group_label(text,x,y,w)
 label(text,x,y,14,A.panel_enabled~=false and C.accent2 or C.faint,1,w,20)
 line(x,y+23,x+w,y+23,C.edge,.3)
end
function UI.icon()
 local bs,bx,by=scale,ox,oy;ox,oy=ox+(W-102)*scale,oy+53*scale;scale=scale*.78

 local x,y=0,0
 for i=1,7 do
  local phase=anim_time*(.15+(i%3)*.035)+i*1.41
  disc(x+38+math.sin(phase*1.22)*22,y+math.cos(phase*.87)*11,16+i%4*3,C.accent,.006)
 end
 for i=0,2 do
  local bx=x+i*32
  for k=0,8 do local a=3+10*abs(math.sin(k*.72+i));line(bx+k*2.3,y-a,bx+k*2.3,y+a,C.accent2,.24) end
  local d=i==1 and -1 or 1;local ax=bx+11;local ay=y-22
  line(ax-d*7,ay,ax+d*7,ay,C.accent2,.6);line(ax+d*7,ay,ax+d*3,ay-4,C.accent2,.6);line(ax+d*7,ay,ax+d*3,ay+4,C.accent2,.6)
 end
 if A.active and visual_speed(R.time_precise())>0 then icon_clock=icon_clock+frame_dt end
 while icon_clock>=.11 and #icon_particles<25 do
  icon_clock=icon_clock-.11;icon_serial=icon_serial+1;local n=icon_serial
  icon_particles[#icon_particles+1]={x=x+particle_hash(n,1)*83,y=y-21+particle_hash(n,2)*42,age=0,life=1.8+particle_hash(n,3)*1.2,d=n%2==0 and 1 or -1}
 end
 for i=#icon_particles,1,-1 do
  local p=icon_particles[i];p.age=p.age+frame_dt
  if p.age>=p.life then table.remove(icon_particles,i) else
   local a=math.sin(math.pi*p.age/p.life)^2;local px=p.x+p.d*p.age*8;local py=p.y+math.sin(p.age)*2.3
   disc(px,py,4,C.accent,.022*a);disc(px,py,2,C.accent2,.07*a);disc(px,py,.65,C.focus2,.56*a)
  end
 end

 scale,ox,oy=bs,bx,by
end
function UI.draw(now)
 UI.geometry();frame_dt=min(.1,now-frame_clock);frame_clock=now;anim_time=anim_time+frame_dt*visual_speed(now)
 widgets={};hover_hint='';gfx.dest=-1;gfx.mode=0;gfx.a=1;gfx.clear=-1;color(C.bg);gfx.rect(0,0,gfx.w,gfx.h,1)
 BLT.title('CR MINIM','RETRIGGER MODULATION  リトリガーモジュレーション',W)
 UI.icon()
 panel(20,82,806,152,'素材と切り出し範囲','SOURCE & SEQUENCE')
 local source=A.source
 right_label(source and string.format('%.3f s / %d Hz / %d ch',source.duration,source.wav.sr,source.wav.channels) or '',810,95,12,C.faint,3)
 label(source and source.name or '',36,132,16,C.accent2,1,620,24)
 UI.wave_draw()
 UI.result_preview(20,242,806,102)
 panel(20,354,395,498,'スライス＆リトリガー','REPEAT ENGINE')
 panel_switch('retrigger_on',307,360);A.panel_enabled=A.retrigger_on
 group_label('切り出す範囲',36,410,363)
 field_label('offset',36,436,172,'切り出し開始 ms')
 field_label('slice_fade_in',227,436,80,'頭フェード ms',nil,12);field_label('slice_fade_out',319,436,80,'後フェード ms',nil,12)
 field_label('slice',36,488,172,'最初の長さ ms');field_label('slice_end',227,488,172,'最後の長さ ms',A.vary_length)
 checkbox('vary_length',36,540,363,'最初 → 最後で長さを変化させる','vary_length')
 group_label('発音の並びと間隔',36,570,363)
 field_label('count',36,596,100,'リピート回数')
 label('再生方向',148,596,14,A.panel_enabled~=false and C.muted or C.faint,1,251,20)
 for i,t in ipairs({'順転','逆転','順逆','FFRR'}) do choose('direction'..i,148+(i-1)*64,616,58,t,'pattern',i) end
 field_label('interval0',36,650,172,'最初の間隔 ms');field_label('interval1',227,650,172,'最後の間隔 ms')
 field_label('gap',36,704,172,'最小の無音 ms');field_label('curve',227,704,172,'変化カーブ')
 group_label('リトリガーのピッチ',36,758,363)
 field_label('pitch0',36,784,172,'最初のピッチ st');field_label('pitch1',227,784,172,'最後のピッチ st')
 A.panel_enabled=true
 panel(431,354,395,498,'最後の音とモーション','TAIL & MOTION')
 panel_switch('tail_on',718,360);A.panel_enabled=A.tail_on
 group_label('最後に鳴らす範囲',447,410,363)
 choose('tail1',447,436,172,'素材全体','tail',1)
 choose('tail2',638,436,172,'切り出し以降','tail',2)
 checkbox('motion',447,470,363,'最後の音にモーションを適用','motion')
 local en=A.motion and A.tail_on
 group_label('ピッチ・速度と通過点',447,500,363)
 field_label('bend0',447,526,113,'開始 st',en);field_label('bend_mid',572,526,113,'通過 st',en and A.flyby);field_label('bend1',697,526,113,'終了 st',en)
 checkbox('flyby',447,596,238,'接近 → 通過 → 遠ざかり','flyby')
 field_label('pass',697,578,113,'通過位置 %',en and A.flyby)
 group_label('音量・左右移動・フェード',447,634,363)
 field_label('gain0',447,660,113,'開始音量 dB',en);field_label('gain_mid',572,660,113,'通過音量 dB',en and A.flyby);field_label('gain1',697,660,113,'終了音量 dB',en)
 field_label('pan0',447,712,113,'開始パン',en);field_label('pan1',572,712,113,'終了パン',en);field_label('fade',697,712,113,'フェード ms')
 group_label('トレモロ',447,766,363)
 field_label('trem0',447,792,113,'開始 Hz',en);field_label('trem1',572,792,113,'終了 Hz',en);field_label('depth',697,792,113,'深さ %',en)
 A.panel_enabled=true
 local cx,cy,cw,ch=20,875,164,42
 local chaos_hot=not A.busy and inside(cx,cy,cw,ch)
 local glow=animate('chaos_glow',chaos_hot and 1 or 0)
 BLT.chaosButton(cx,cy,cw,ch,not A.busy,chaos_hot,pressed=='chaos' and (gfx.mouse_cap&1)~=0,anim_time,glow)
 register('chaos',cx,cy,cw,ch,UI.chaos,'パラメータをランダムに変化させます',not A.busy)
 local ex,ey,ew,eh=279,868,288,56;local ready=A.plan~=nil and not A.busy;local hot=(ready or A.busy) and inside(ex,ey,ew,eh)
 PrimaryButton.draw(PrimaryButton.painter,ex,ey,ew,eh,A.busy and '生成中止' or '生成実行',A.busy and 'GENERATING' or 'EXECUTE',ready or A.busy,A.busy,A.busy and A.progress or nil,hot,pressed=='execute' and (gfx.mouse_cap&1)~=0,R.time_precise(),BLT.host.active())
 register('execute',ex,ey,ew,eh,UI.execute,A.busy and 'もう一度押すと生成を中止します' or '波形ピークを作成後、同じトラックの右側の空きへ1秒空けて配置します',ready or A.busy)

 BLT.footer(Core.display_message(A.source_problem or A.problem or A.status),A.source_problem or A.problem or A.warning,W,H+22,'0.5.2')
 flush_text_queue();custom_titlebar();gfx.update();A.content_dirty=false;redraw_dirty=false
end
function UI.interact()
 if BLT.blocked() then down_last=(gfx.mouse_cap&1)~=0;pressed=nil;gfx.mouse_wheel=0;return end

 if UI.wave_input() then return end
 local hit
 if not Chrome.mouseActive then for i=#widgets,1,-1 do local w=widgets[i];if w.enabled and (not A.busy or w.id=='cancel' or w.id=='execute') and inside(w.x,w.y,w.w,w.h) then hit=w;break end end end
 local down=(gfx.mouse_cap&1)~=0
 if UI.field_input(hit,down) then return end
 if down and not down_last then pressed=hit and hit.id or nil;UI.dirty() end
 if not down and down_last then local fn=hit and hit.id==pressed and hit.fn;pressed=nil;if fn then UI.safe(fn) end;UI.dirty() end
 down_last=down;gfx.mouse_wheel=0
end
function UI.close()
 -- Teardown errors must not leave a dead graphics window on screen.
 local ok,err=xpcall(function()
 if A.closed then return end;A.closed=true;Core.abort(A.job);UI.wave_close();clear_chrome_tooltip();titlebar_cleanup()
 local _,x,y,w,h=gfx.dock(-1,0,0,0,0)
 for k,v in pairs({window_x=x,window_y=y,window_w=w,window_h=h}) do if finite(v) then BLT.store(SECTION,k,tostring(floor(v+.5)),true) end end
 gfx.quit()
 end,debug.traceback)
 if not ok then
  A.closed=true
  pcall(gfx.quit)
  if R.TrackCtl_SetToolTip then pcall(R.TrackCtl_SetToolTip,'',0,0,true) end
  BLT.logError(err)
 end
end
function UI.loop()
 UI.safe(function()
 local now=R.time_precise();BLT.tick(now);PrimaryButton.tick(now,BLT.host.active(),PrimaryButton.wake)

 local k=BLT.key(gfx.getchar());if k<0 or A.closed then A.closing=true;return end
   local flags=gfx.getchar(65537);A.active=(flags&1)==0 or (flags&2)~=0
  if gfx.mouse_x~=last_raw_mouse_x or gfx.mouse_y~=last_raw_mouse_y or gfx.mouse_cap~=last_raw_mouse_cap or gfx.mouse_wheel~=0 or k>0 then wake_visuals(now) end
  -- App-bar input is consumed during drawing: preserve every button edge.
  if gfx.mouse_cap~=last_raw_mouse_cap or gfx.mouse_wheel~=0 then next_draw_time=now end
  last_raw_mouse_x,last_raw_mouse_y,last_raw_mouse_cap=gfx.mouse_x,gfx.mouse_y,gfx.mouse_cap
  if A.edit then UI.edit_key(k);k=0 end
  if k==27 then if A.busy then UI.cancel() else A.closing=true end end
  UI.poll(now);if not A.busy then UI.wave_step() end;Chameleon.tick(now)
  if gfx.w~=last_window_w or gfx.h~=last_window_h then last_window_w,last_window_h=gfx.w,gfx.h;UI.dirty() end
  UI.geometry();UI.interact()
  if A.job then UI.step() end
  local moving=(A.active and visual_speed(now)>0) or #icon_particles>0 or Chrome.drag or Chrome.resize
  if (A.content_dirty or redraw_dirty or moving or A.busy) and now>=next_draw_time then
   UI.draw(now);next_draw_time=now+(A.busy and 1/10 or moving and 1/30 or 4);
  end
  if Chrome.requestReset then Chrome.requestReset=false;reset_window_size();UI.dirty() end
  if Chrome.requestClose then A.closing=true end
 end)
 if A.closing then UI.close() else R.defer(UI.loop) end
end
function BLT.pick(obj,keys) local v=BLT.valueView or {};BLT.valueView=v;for k in pairs(keys) do v[k]=obj[k] end;return v end
PrimaryButton.painter={C=C,gradient=gradient,line=line,rect=rect,corners=finish_corners,disc=disc,label=label}
PrimaryButton.painter.motion=function(now) return (gfx.mouse_x-ox)/scale,(gfx.mouse_y-oy)/scale,visual_speed(now) end
PrimaryButton.wake=function() redraw_dirty=true;A.content_dirty=true;next_draw_time=0 end
Media.state=A;Media.onchange=function() if BLT.host and BLT.host.wake then BLT.host.wake() end end
BLT.attach({
 chaosPainter={cut=cut_panel,gradient=gradient,disc=disc,line=line,label=label},
 R=R,C=C,Chrome=Chrome,Chameleon=Chameleon,section=SECTION,faces=fonts,font=font,
 geometry=function() return scale,ox,oy end,active=function() local f=gfx.getchar(65536);return (f&1)==0 or (f&2)~=0 end,
 wake=function() A.content_dirty=true;redraw_dirty=true;next_draw_time=0;wake_visuals() end,
 defaults=Core.defaults,capture=function() return BLT.pick(A,Core.defaults) end,
 valid=function(v) for k,r in pairs(Core.specs) do local n=v[k];if n~=nil and (type(n)~='number' or n<r[1] or n>r[2] or r[3] and n%1~=0) then return false end end;return true end,apply=function(v) for k,x in pairs(v) do A[k]=x end;UI.refresh() end,
 undoRefresh=function() UI.refresh() end,
 busy=function() return A.busy end,commit=function() if A.edit then UI.edit_key(13) end;return A.edit==nil end,
 cancelEdit=function() A.edit=nil;A.field_drag=nil end,editing=function() return A.edit~=nil end,
 modal=function() return false end,
 handle=gfx_window_handle,resizeHit=function(x,y) if y<26 and x>=gfx.w-234 then return nil end;return chrome_resize_hit(x,y) end,
 cursor=set_resize_cursor,beginResize=begin_window_resize,resize=update_window_resize,

})
if ...=='blt_test' then function BLT.testDraw(now) UI.draw(now or R.time_precise()) end end


if ...=='blt_test' then return {Media=Media,BLT=BLT,A=A,Core=Core ,UI=UI} end
if ...=='ui_test' then return {Core=Core,A=A,UI=UI,Chameleon=Chameleon,palette=C} end
local chrome_ok,chrome_err=titlebar_api_ready()
if not chrome_ok then Language.mb(Core.display_message(chrome_err),'BLT CR MINIM | 必要な拡張',0);return end
local ww=clamp(tonumber(R.GetExtState(SECTION,'window_w')) or W,Chrome.minW,2200)
local wh=clamp(tonumber(R.GetExtState(SECTION,'window_h')) or H+Chrome.titleH,Chrome.minH,1800)
local wx,wy=tonumber(R.GetExtState(SECTION,'window_x')),tonumber(R.GetExtState(SECTION,'window_y'))
-- Match native window/input coordinates in logical points on Mac.
gfx.ext_retina=BLT_MAC and 0 or 1
if finite(wx) and finite(wy) then gfx.init(Chrome.windowTitle,ww,wh,0,wx,wy) else gfx.init(Chrome.windowTitle,ww,wh,0) end
if not apply_custom_window_style(ww,wh) then gfx.quit();Language.mb('カスタムアプリバーを初期化できません。','BLT CR MINIM',0);return end
if Chameleon.enabled then Chameleon.refresh(true) end
R.atexit(UI.close);UI.safe(function() UI.poll(R.time_precise(),true) end);UI.loop()
