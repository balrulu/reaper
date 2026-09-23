-- @description ENVELOPE CANVAS TRACK
-- @version 0.0.22
-- @author Balrulu
-- @provides
--   . > ../
-- @changelog
--   BLT SERIES Beta TEST UPLOAD
-- @about
--   BLT SERIES Beta TEST UPLOAD

-- BLT external storage 1.1.0. Embedded; large data stays beside this script.
local function create_external_storage(api,section,source,state_keys)
 local P=setmetatable({}, {__index=api})
 local wanted={};for _,key in ipairs(state_keys) do wanted[key]='state' end
 wanted.preset_count='presets';wanted.current_preset='presets'
 for i=1,200 do
  wanted['preset_'..i]='presets';wanted['preset_name_'..i]='presets';wanted['preset_data_'..i]='presets'
 end
 local path=source:match('^@(.+)$')
 if not path and api.get_action_context then local _,p=api.get_action_context();if p and p~='' then path=p end end
 local base=path and path:match('^(.*)[.]lua$')
 local stores={};local warned={};local cap=268435456
 local function report(kind,detail)
  if warned[kind] then return end;warned[kind]=true
  local en=api.GetExtState(section,'ui_language')=='EN'
  api.MB((en and 'BLT could not save/load its data file. Existing files are retained. Check folder permissions and free disk space.\n\n' or 'BLTのデータファイルを保存・読み込みできません。既存ファイルは保持しています。フォルダの書き込み権限と空き容量を確認してください。\n\n')..tostring(detail),'BLT DATA',0)
 end
 local function exists(p)
  if api.file_exists then return api.file_exists(p) end
  local f=io.open(p,'rb');if f then f:close();return true end
  return os.rename(p,p) and true or false
 end
 local function value_limit(key)
  if key=='preset_count' then return 3 end
  if key=='current_preset' or key:match('^preset_name_%d+$') then return 2048 end
  if key=='preferences_v1' or key=='curve_guide_data' then return 131072 end
  if key=='settings' then return 2097152 end
  return 16777216
 end
 local function read(p)
  local f,err=io.open(p,'rb');if not f then return nil,err end
  local ok,raw=pcall(function()
   local size=f:seek('end')
   if not size or size>cap or not f:seek('set',0) then return nil end
   local data=f:read(size+1)
   if not data or #data~=size then return nil end
   return data
  end)
  pcall(f.close,f)
  if not ok or not raw then return nil,'Cannot read data file safely: '..p end
  if raw:sub(1,12)~='BLT_DATA_V1\n' or raw:sub(-4)~='END\n' then return nil,'Invalid data file: '..p end
  local values={};local pos=13;local count=0
  while pos<=#raw-4 do
   local a,b,klen,vlen=raw:find('^(%d+) (%d+)\n',pos)
   klen,vlen=tonumber(klen),tonumber(vlen)
   if not a or not klen or not vlen or klen>128 or vlen>16777216 or b+klen+vlen>#raw-4 then return nil,'Invalid data record: '..p end
   local key=raw:sub(b+1,b+klen)
   if not wanted[key] or vlen>value_limit(key) then return nil,'Invalid data key/size: '..p end
   local value=raw:sub(b+klen+1,b+klen+vlen)
   if values[key]~=nil then return nil,'Duplicate data record: '..p end
   if key=='preset_count' and (not value:match('^%d+$') or tonumber(value)>200) then return nil,'Invalid preset count: '..p end
   values[key]=value;pos=b+klen+vlen+1;count=count+1
   if count>1024 then return nil,'Too many data records: '..p end
  end
  return values
 end
 local function encode(values)
  local keys={};for key in pairs(values) do keys[#keys+1]=key end;table.sort(keys)
  local rows={'BLT_DATA_V1\n'};local size=16
  for _,key in ipairs(keys) do
   local value=values[key];local h=#key..' '..#value..'\n';size=size+#h+#key+#value
   if size>cap or #value>16777216 then return nil,'Local data capacity exceeded' end
   rows[#rows+1]=h;rows[#rows+1]=key;rows[#rows+1]=value
  end
  rows[#rows+1]='END\n';return table.concat(rows)
 end
 for _,kind in ipairs({'presets','state'}) do
  local p=base and (base..'.'..kind..'.dat')
  local s={path=p,values={},pending={}};stores[kind]=s
  if not p then s.blocked=true;report(kind,'Cannot locate the Lua script file')
  elseif exists(p) then
   local values,err=read(p)
   if values then s.values=values else
    s.values=read(p..'.bak') or {};s.blocked=true;report(kind,err..'\nBackup: '..p..'.bak')
   end
  elseif exists(p..'.bak') then
   local values,err=read(p..'.bak')
   if values then s.values=values else s.blocked=true;report(kind,err) end
  end
 end
 local function mark(s,key,value)
  s.values[key]=value;s.pending[key]=value;s.due=s.due or (api.time_precise()+0.75)
 end
 local function flush(s,kind)
  if s.blocked or not s.due then return end
  local values={}
  if exists(s.path) then
   local current,err=read(s.path);if not current then s.blocked=true;report(kind,err);return end
   values=current
  else for k,v in pairs(s.values) do values[k]=v end end
  for k,v in pairs(s.pending) do values[k]=v end
  local raw,err=encode(values)
  local temp=s.path..'.tmp'
  local ok=false
  if raw then
   local f;f,err=io.open(temp,'wb')
   if f then
    local success,wrote,werr=pcall(f.write,f,raw);local closing,closed,cerr=pcall(f.close,f);if not closing then cerr=closed;closed=nil end
    if not success then werr=wrote;wrote=nil end
    if wrote and closed then
     local check;check,err=read(temp)
     if check then
      ok=true;for k,v in pairs(values) do if check[k]~=v then ok=false;err='Data verification failed';break end end
     end
    else err=werr or cerr end
   end
  end
  if ok then
   local had=exists(s.path)
   if had then
    if exists(s.path..'.bak') then ok,err=os.remove(s.path..'.bak') end
    if ok then ok,err=os.rename(s.path,s.path..'.bak') end
   end
   if ok then
    ok,err=os.rename(temp,s.path)
    if not ok and had then os.rename(s.path..'.bak',s.path) end
   end
  end
  if not ok then s.due=api.time_precise()+5;report(kind,(s.path or '')..'\n'..tostring(err));return end
  s.values=values;s.pending={};s.due=nil;warned[kind]=nil

 end
 function P.BLT_FlushStorage(force)
  local now=api.time_precise()
  for kind,s in pairs(stores) do
   if not s.blocked and s.due and (force or now>=s.due) then
    local ok,err=pcall(flush,s,kind)
    if not ok then s.due=now+5;pcall(report,kind,tostring(s.path)..'\n'..tostring(err)) end
   end
  end
 end
 function P.GetExtState(sec,key)
  local kind=sec==section and wanted[key]
  if kind then return stores[kind].values[key] or '' end
  return api.GetExtState(sec,key)
 end
 function P.SetExtState(sec,key,value,persist)
  local kind=sec==section and wanted[key]
  if not kind then return api.SetExtState(sec,key,value,persist) end
  local s=stores[kind];value=tostring(value)
  if persist and s.values[key]~=value then mark(s,key,value) else s.values[key]=value end
 end
 function P.DeleteExtState(sec,key,persist)
  if sec==section and wanted[key] then return P.SetExtState(sec,key,'',persist) end
  return api.DeleteExtState(sec,key,persist)
 end
 function P.HasExtState(sec,key)
  if sec==section and wanted[key] then return P.GetExtState(sec,key)~='' end
  return api.HasExtState(sec,key)
 end
 function P.defer(fn)
  local ok,err=pcall(P.BLT_FlushStorage,false)
  if not ok then pcall(report,'runtime',err) end
  return api.defer(fn)
 end
 function P.atexit(fn)
  return api.atexit(function()
   local ok,err=xpcall(fn,debug.traceback);pcall(P.BLT_FlushStorage,true)
   if not ok then error(err) end
  end)
 end
 return P
end

local reaper=create_external_storage(reaper,'BLT_ENVELOPE_CANVAS_TRACK',debug.getinfo(1,'S').source,{'preferences_v1'})

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
 ["秒"]="Seconds",
 ["拍"]="Beats",
 ["グリッド"]="Grid",
 ["クリック：描画  ·  ホイール：横幅の開始 / Ctrl：縦幅の開始 / Shift：微調整  ·  Alt：位相反転"]="Click: draw · Wheel: width start / Ctrl: height start / Shift: fine · Alt: invert",
 ["ドラッグ：範囲選択  ·  枠内：移動  ·  辺／角：変形  ·  Alt＋線：曲率"]="Drag: select  ·  Inside box: move  ·  Edges: transform  ·  Alt+line: tension",
 ["ドラッグ：描画／点移動  ·  Ctrl：点をつかまず描画  ·  Alt＋線：曲率  ·  右ドラッグ：範囲選択"]="Drag: draw / move points · Ctrl: draw past points · Alt+line: tension · Right-drag: select",
 ["エンベロープ編集"]="Envelope editing",
 ["点ドラッグ：移動"]="Drag point: move",
 ["Alt＋線ドラッグ：曲率"]="Alt+drag line: tension",
 ["Shift＋クリック：点追加"]="Shift+click: add point",
 ["ダブルクリック：点追加"]="Double-click: add point",
 ["右ドラッグ：範囲選択"]="Right-drag: select",
 ["Ctrl＋点：選択を切替"]="Ctrl+point: toggle select",
 ["右クリック：点の形状"]="Right-click: point shape",
 ["ポイントの形状"]="Point shape",
 ["選択ポイントを削除"]="Delete selected points",
 ["REAPERと常時連動"]="Live REAPER envelopes",
 ["実際のポイントと形状を直接編集  ·  Alt＋線ドラッグ：Bezier曲率"]="Edit native points and shapes  ·  Alt+drag segment: Bezier tension",
 ["表示範囲をオートメーション化"]="Make automation items",
 ["表示範囲をオートメーションアイテムにまとめました。"]="Visible range collected into automation items.",
 ["重なったオートメーションは先にまとめてください。"]="Merge overlapping automation items first.",
 ["無音化されたオートメーションはREAPER側で解除してください。"]="Unmute or restore automation item amplitude in REAPER first.",
 ["割当先を選択"]="Assign envelope",
 ["割当先のカーブ取得"]="Read envelopes",
 ["トラックのエンベロープ"]="Track envelope",
 ["割り当て解除"]="Unassign",
 ["最新のエンベロープを確認しました。割当先を確認してもう一度操作してください。"]="Envelope refreshed. Check the assignment and retry.",
 ["トラックと時間範囲を選択してください。"]="Select a track and a time range.",
 ["対象トラックまたは時間範囲が変わりました。"]="The target track or time range has changed.",
 ["LIVE：カーブを反映しました。"]="LIVE: Curve applied.",
 ["カーブを再反映"]="Reapply curves",
 ["エンベロープを先にREAPERで表示してください。"]="Show the desired envelopes in REAPER first.",
 ["SWS拡張をインストールしてください。"]="Please install the SWS extension.",
 ["同じエンベロープを複数の枠には割り当てられません。"]="This envelope is already assigned.",
 ["割当先のエンベロープが見つかりません。再度割り当ててください。"]="Envelope missing. Please assign it again.",
 ["エンベロープの割当先を選択してください。"]="Choose an envelope assignment.",
 ["カーブを生成しました。REAPERで一括アンドゥできます。"]="Curves generated. Undo in REAPER.",
 ["既存のオートメーションアイテムと重なっています。"]="An existing automation item overlaps this range.",
 ["割当先のカーブを読み込みました。"]="Assigned envelopes loaded.",
 ["BLTフィルターのReaEQを確認できません。"]="Cannot identify the managed ReaEQ.",
 ["ReaEQの周波数範囲を取得できません。"]="Cannot read the ReaEQ frequency range.",
 ["BLTフィルターが重複しています。FXチェーンを確認してください。"]="Duplicate BLT filters. Check the FX chain.",
 ["ReaEQ (Cockos) を追加できません。"]="Cannot add ReaEQ (Cockos).",
 ["ReaEQの初期状態を設定できません。"]="Cannot initialize ReaEQ.",
 ["ReaEQのバンドを設定できません。"]="Cannot configure ReaEQ bands.",
 ["ReaEQのチャンネルを設定できません。"]="Cannot configure ReaEQ channels.",
 ["ReaEQの識別情報を保存できません。"]="Cannot store the ReaEQ identity.",
 ["旧BLTフィルターを置換できません。"]="Cannot replace the old BLT filter.",
 ["ReaEQの周波数を設定できません。"]="Cannot set the ReaEQ frequency.",
 [" ReaEQの周波数範囲に収めました。"]=" Clamped to the ReaEQ frequency range.",

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
 ["時間カーブが複雑すぎます。点を減らしてから適用してください。"]="Time curve too complex. Reduce points before applying.",
 ["対象の復元データを取得できません。"]="Cannot capture target restore data.",
 ["エンベロープを作成できません。"]="Cannot create envelope.",
 ["エンベロープを有効化できません。"]="Cannot enable envelope.",
 ["カーブが複雑すぎます。点を減らしてから適用してください。"]="Curve too complex. Reduce points before applying.",
 ["音量カーブが複雑すぎます。点を減らしてください。"]="Volume curve too complex. Reduce points.",
 ["専用フィルターの同名ファイルに異なる内容があります："]="Different filter content exists at: ",
 ["専用フィルターを保存できません："]="Cannot save dedicated filter: ",
 ["専用フィルターの保存に失敗しました："]="Failed to save dedicated filter: ",
 ["HPの有効状態を設定できません。"]="Cannot set HP enabled state.",
 ["LPの有効状態を設定できません。"]="Cannot set LP enabled state.",
 ["フィルターのカーブを作成できません。"]="Cannot create filter curves.",
 ["対象のテイクが変更されています。再読み込みしてください。"]="Target take changed. Reload it.",
 ["反転・セクション素材：グルー後に尺連動・速度カーブを適用してください。"]="Reversed/section source: glue before applying linked pitch/rate curves.",
 ["アイテムのロックを解除してから適用してください。"]="Unlock the item before applying.",
 ["全テイク同時再生をOFFにしてから適用してください。"]="Disable Play all takes before applying.",
 ["時間マーカーを置き換えられません。"]="Cannot replace time markers.",
 ["尺を変更できません。"]="Cannot change duration.",
 ["再生速度を変更できません。"]="Cannot change playback rate.",
 ["時間カーブを書き込めません。"]="Cannot write time curve.",
 ["\n復元に失敗しました。REAPERのUndoで戻してください。"]="\nRestore failed. Use REAPER Undo.",
 ["対象のテイクが変更されています。"]="Target take changed.",
 ["対象に外部変更があります。REAPERのUndoで確認してください。"]="Target was changed externally. Check REAPER Undo.",
 ["生成前の状態へ戻せません。"]="Cannot restore the state before generation.",
 ["生成元の音声を取得できません。"]="Cannot read source audio.",
 [" / 復元失敗：REAPERのUndoを使用してください。"]=" / Restore failed: use REAPER Undo.",
 ["CHAMELEON  REAPERテーマに擬態"]="CHAMELEON  REAPER theme",
 ["CHAMELEON  オリジナル配色"]="CHAMELEON  Original colors",
 ["カスタムタイトルバーには js_ReaScriptAPI が必要です。\nReaPack から js_ReaScriptAPI をインストールしてください。"]="The app bar requires js_ReaScriptAPI.\nInstall js_ReaScriptAPI via ReaPack.",
 ["ピッチ"]="Pitch",
 ["尺を保持"]="Keep length",
 ["ピッチ · 尺連動"]="Pitch · Rate",
 ["音程と尺を連動"]="Link pitch and length",
 ["再生速度"]="Rate",
 ["音程を保持"]="Keep pitch",
 ["ボリューム"]="Volume",
 ["ゲインを描画"]="Draw gain",
 ["ローパス"]="Low-pass",
 ["カットオフ · 中高域重視"]="Cutoff · Mid/high focus",
 ["ハイパス"]="High-pass",
 ["サイン波"]="Sine",
 ["ノコギリ波"]="Saw",
 ["矩形波"]="Square",
 ["三角波"]="Triangle",
 ["水平線"]="Flat",
 ["ランダムステップ"]="Random Step",
 ["現在のカーブをランダム生成しました。"]="Current curve randomized.",
 ["現在のカーブにラインを生成しました。"]="Line generated on current curve.",
 ["HP／LPリンク ON：次の編集から帯域幅を連動します。"]="HP/LP link ON: bandwidth follows future edits.",
 ["HP／LPリンク OFF：個別に編集できます。"]="HP/LP link OFF: edit independently.",
 ["帯域幅 / oct"]="Bandwidth / oct",
 ["波形を取得できません。音声ファイルがオンラインか確認してください。"]="Cannot read waveform. Check that the audio file is online.",
 ["音声の読み出しに失敗しました。"]="Audio read failed.",
 ["音声アイテムを選択すると自動で読み込みます。"]="Select an audio item to load it automatically.",
 ["トラックと時間範囲を選択してください。"]="Select audio items.",
 ["対象のプロジェクトタブに戻ってください。"]="Return to the target project tab.",
 ["対象が削除されたか、テイクが変わっています。再読み込みしてください。"]="Target deleted or take changed. Reload it.",
 ["編集は再生・録音を停止してから行ってください。"]="Stop playback/recording before generating.",
 ["対象の音声アイテムを確認してください。"]="Check the target audio item.",
 ["カーブを読み込みました。一部の値は編集範囲の上限・下限に収めています。"]="Curves loaded. Some values were clamped to the editing range.",
 ["ピッチ・ボリューム・専用HP／LPを読み込みました。既存の速度設定は保持します。"]="Pitch, volume and dedicated HP/LP loaded. Existing rate settings retained.",
 ["生成済みのカーブを読み込みました。"]="Generated curves loaded.",
 ["波形の読み込み完了を待ってください。"]="Wait for waveform loading.",
 ["カーブを描いてから適用してください。"]="Draw a curve before applying.",
 ["適用条件を確認してください。"]="Check the conditions for applying.",
 ["生成完了：時間 %d点 / エンベロープ %d点%s。"]="Done: %d time points / %d envelope points%s.",
 ["（上限に合わせて近似）"]=" (approximated to point limit)",
 ["生成を更新"]="Update",
 ["カーブを生成"]="Generate",
 ["TRACK AUTOMATION DRAWING  トラックのオートメーション描画"]="WAVEFORM CURVE DRAWING  Draw curves on audio",
 ["直線"]="Linear",
 ["操作モード"]="EDIT MODE",
 ["範囲選択"]="Select",
 ["ペン"]="Pen",
 ["ライン生成"]="Generate line",
 ["方向："]="Direction: ",
 ["左"]="Left",
 ["両側"]="Both",
 ["右"]="Right",
 ["Alt：位相反転"]="Alt: invert phase",
 ["割当先のカーブ取得"]="Read existing curve",
 ["ランダム生成"]="Randomize",
 ["戻す"]="Undo",
 ["やり直す"]="Redo",
 ["現在のカーブを消去"]="Clear current curve",
 ["全カーブを消去"]="Clear all curves",
 ["EDITED / 生成で更新"]="EDITED / Generate to update",
 ["GENERATED / AUTOMATION"]="GENERATED / Pre-FX outline",
 ["ドラッグ：範囲選択  ·  辺／角：変形  ·  枠内：移動  ·  Delete／枠内右クリック：削除"]="Drag: select · Edges/corners: reshape · Inside: move · Delete/right-click inside: delete",
 ["波形上をクリック：カーソル位置からライン生成"]="Click waveform: generate line from cursor",
 ["ドラッグ：描画／点移動  ·  Shift：直線  ·  Ctrl：点をつかまず描画  ·  右クリック：点削除"]="Drag: draw/move points · Shift: line · Ctrl: draw without grabbing points · Right-click: delete point",
 ["ホイール：ズーム  /  Shift＋ホイール：横移動"]="Wheel: zoom / Shift+wheel: pan",
 ["512点以上：処理が重くなる可能性があります"]="512+ points may increase processing load",
 ["波形を読み込み中  %d%%"]="Loading waveform %d%%",
 ["%d 点"]="%d pts",
 ["Envelope Canvas Track | 必要な拡張"]="Envelope Canvas Track | Required extension",
 ["カスタムアプリバーを初期化できません。"]="Cannot initialize the app bar.",
 ["表示言語を切替（JP / EN）"]="Switch language (JP / EN)",
 ["プリセットを読み込みました: ファクトリーデフォルト"]="Loaded: Factory Default",
 ["選択中のトラック / バスを指定"]="Use selected track / bus",
 ["方向：左"]="Direction: Left",
 ["方向：両側"]="Direction: Both",
 ["方向：右"]="Direction: Right",
},patterns={
 {"^「(.*)」を上書きしますか？$","Overwrite \"%s\"?"},
 {"^([%+%-]?[%d%.eE]+)–([%+%-]?[%d%.eE]+) / ([%+%-]?[%d%.eE]+)   スクロールで選択$","%d–%d / %d   Scroll to browse"},
 {"^解析中%.%.%.([%+%-]?[%d%.eE]+)%%$","Analyzing...%d%%"},
 {"^生成完了：時間 ([%+%-]?[%d%.eE]+)点 / エンベロープ ([%+%-]?[%d%.eE]+)点(.-)。$","Done: %d time points / %d envelope points%s.",{3}},
 {"^波形を読み込み中  ([%+%-]?[%d%.eE]+)%%$","Loading waveform %d%%"},
 {"^([%+%-]?[%d%.eE]+) 点$","%d pts"},
 {"^「(.-)」を上書きしますか？$","\"%s\"?"},
 {"^(.-)」を上書きしますか？$","%s\"?"},
 {"^プリセットを保存しました: (.-)$","Saved: %s"},
 {"^プリセットを読み込みました: (.-)$","Loaded: %s"},
 {"^(.-)個インポートしました。$","%s preset(s) imported."},
 {"^現在: (.-)(.-)$","Current: %s%s"},
 {"^(.-)エンベロープを作成できません。$","%sCannot create envelope."},
 {"^専用フィルターの同名ファイルに異なる内容があります：(.-)$","Different filter content exists at: %s"},
 {"^専用フィルターを保存できません：(.-)$","Cannot save dedicated filter: %s"},
 {"^専用フィルターの保存に失敗しました：(.-)$","Failed to save dedicated filter: %s"},
 {"^(.-)\n復元に失敗しました。REAPERのUndoで戻してください。$","%s\nRestore failed. Use REAPER Undo."},
 {"^(.-) / 復元失敗：REAPERのUndoを使用してください。$","%s / Restore failed: use REAPER Undo."},
 {"^方向：(.-)$","Direction: %s"},
 {"^「(.*)」を上書きしますか？$","Overwrite \"%s\"?"},
 {"^(%d+)個インポートしました。$","Imported %s preset(s)."},
 {"^(%d+)件をノーマライズしました。選択を解除しました。$","Normalized %s items and deselected them."},
},prefixes={"専用フィルターの同名ファイルに異なる内容があります：","専用フィルターの保存に失敗しました：","専用フィルターを保存できません：","プリセットを読み込みました: ","プリセットを保存しました: ","現在: ","方向："}}

local Language=create_language(reaper,"BLT_ENVELOPE_CANVAS_TRACK",LanguageCatalog)
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

local Core={VERSION='0.0.22',GENERATED_MAX_POINTS=1024,SECTION='BLT_ENVELOPE_CANVAS_TRACK'}
local min,max,abs,floor,ceil=math.min,math.max,math.abs,math.floor,math.ceil
local function clamp(v,a,b) return max(a,min(b,v)) end
local function finite(v) return type(v)=='number' and v==v and abs(v)<math.huge end
function Core.copy(t)
 if type(t)~='table' then return t end
 local out={};for k,v in pairs(t) do out[k]=Core.copy(v) end;return out
end
function Core.new_layers()
 local layers={}
 for i=1,6 do layers['slot'..i]={points={},enabled=false,min_y=-1,max_y=1,neutral=0} end
 return layers
end

if ...=='core_test' then return Core end

local SECTION=Core.SECTION
local W,H=1120,838
local A={layers=Core.new_layers(),layer='slot1',tool='free',direction=3,pattern=1,period_unit='sec',width_variable=true,height_variable=true,width_start=1,width_end=1,width_duration=1,width_curve=0,height_start=100,height_end=100,height_duration=1,height_curve=0,
 status='',warning=false,content_dirty=true,wave_dirty=true,view=0,span=1,wave={},wave_max=1,
 busy=false,closed=false,poll_at=0,active=true,bindings={},track_sessions={}}

local UI={}
UI.pattern_names={'サイン波','ノコギリ波','矩形波','三角波','水平線','ランダムステップ'}
UI.pattern_kinds={'sine','saw','square','triangle','horizontal','random_step'}
UI.number_limits={width_start={.001,3600,1,3},width_end={.001,3600,1,3},width_duration={.001,3600,1,3},width_curve={-100,100,1,1},height_start={0,200,1,1},height_end={0,200,1,1},height_duration={.001,3600,1,3},height_curve={-100,100,1,1}}
UI.number_rows={height_start=402,height_end=430,height_duration=458,height_curve=486,width_start=542,width_end=570,width_duration=598,width_curve=626}

local Track

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

local function notice(s,warn) A.status=warn and BLT.publicError(s) or tostring(s or '');A.warning=warn or false;A.status_until=R.time_precise()+7;A.content_dirty=true;wake_visuals() end
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
  chameleonPressed=false,resizeCursors={},resizeCursorMode=nil,titleH=26,windowTitle='BLT Envelope Canvas Track',titleText='E N V E L O P E   C A N V A S   T R A C K',
  minW=1000,minH=740,mint={0.38,0.88,0.72},ice={0.65,0.895,1.0},red={1.0,0.27,0.34},
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

UI.defs={
 {key='slot1',name='ENV 1',code='ENV 1',sub='トラックのエンベロープ',color={.46,.82,1}},
 {key='slot2',name='ENV 2',code='ENV 2',sub='トラックのエンベロープ',color={.78,.56,1}},
 {key='slot3',name='ENV 3',code='ENV 3',sub='トラックのエンベロープ',color={1,.73,.36}},
 {key='slot4',name='ENV 4',code='ENV 4',sub='トラックのエンベロープ',color={.38,.91,.72}},
 {key='slot5',name='ENV 5',code='ENV 5',sub='トラックのエンベロープ',color={.89,.75,.36}},
 {key='slot6',name='ENV 6',code='ENV 6',sub='トラックのエンベロープ',color={1,.52,.42}}
}
function UI.theme_color(original,role)
 if not Chameleon.enabled then return original end
 if role then return C[role] end
 return fit_accent_to_bg(original,C.bg,clum(C.text)>clum(C.bg))
end
function UI.theme_sync()
 local signature=tostring(Chameleon.enabled)..tostring(C.bg)..tostring(C.text)
 if UI.theme_signature==signature then return end
 UI.theme_signature=signature
 for _,d in ipairs(UI.defs) do
  d.original_color=d.original_color or d.color
  d.color=UI.theme_color(d.original_color)
 end
end
-- Keep one lottery while the preview moves, then retire it after stamping.

UI.graph={x=212,y=166,w=784,h=372}
function UI.from_axis(key,y) return clamp(y,-1,1) end
function UI.to_axis(key,y) return y end

UI.FRAME=60;UI.WAVE=61;UI.frame_w=0;UI.frame_h=0
function UI.def() for _,d in ipairs(UI.defs) do if d.key==A.layer then return d end end end

function UI.card_geometry(i) return 212+((i-1)%3)*294,619+floor((i-1)/3)*69,282 end

function UI.dirty(wave) ;A.content_dirty=true;if wave then A.wave_dirty=true end;wake_visuals() end
function UI.safe(fn)
 local ok,err=xpcall(fn,debug.traceback)
 if not ok then
  A.busy=false
  BLT.cleanup(Track.finish)
  BLT.cleanup(UI.stop_wave)
  if A.v then
   local refreshed,value=pcall(Track.target)
   A.v=refreshed and value or nil;A.revision=nil
  end
  notice(err,true)
  BLT.recoverInput(A,err);BLT.cleanup(UI.cancel_preview);pcall(UI.sync_curves,true)
 end
 return ok
end

function UI.undo_draw(redo)
 if A.busy or not Track.valid(A.v) then return end
 Track.finish();UI.cancel_preview()
 if redo then R.Undo_DoRedo2(A.v.project) else R.Undo_DoUndo2(A.v.project) end
 UI.sync_curves(true)
end
function UI.stop_wave()
 if A.wave_job and A.wave_job.accessor then R.DestroyAudioAccessor(A.wave_job.accessor) end;A.wave_job=nil
end
function UI.start_wave(sources,signature)
 UI.stop_wave();A.wave={};A.wave_max=1
 if not A.v then return end
 if not sources then sources,signature=Track.wave_sources(A.v) end
 A.wave_signature=signature
 for i=1,4096 do A.wave[i]=0 end
 if #sources>0 then
  A.wave_job={v=A.v,total=#sources,index=0,sources=sources,bin=0,max=0}
 end
 UI.dirty(true)
end
function UI.wave_step()
 if not Media.ready() then return end
 local j=A.wave_job;if not j then return end
 if not Track.valid(j.v) then UI.stop_wave();return end
 local now=R.time_precise();local budget=now+.004;local rate=4096/j.v.len;local batches=0
 repeat
  local source=j.sources[j.index+1]
  if not source then break end
  if not R.ValidatePtr2(j.v.project,source.item,'MediaItem*') or not R.ValidatePtr2(j.v.project,source.take,'MediaItem_Take*') or R.GetActiveTake(source.item)~=source.take then
   UI.stop_wave();A.wave_signature=nil;return
  end
  if not j.buffer then
   j.bin=max(0,floor((max(j.v.pos,source.pos)-j.v.pos)*rate))
   j.last=min(4096,ceil((min(j.v.pos+j.v.len,source.pos+source.len)-j.v.pos)*rate))
   j.buffer=R.new_array(1024*source.channels)
  end
  local count=min(512,j.last-j.bin)
  if count<=0 then j.index=j.index+1;j.buffer=nil else
   j.buffer.clear()
   local got=R.GetMediaItemTake_Peaks(source.take,rate,j.v.pos+j.bin/rate,source.channels,count,0,j.buffer)
   got=type(got)=='number' and (got&0xfffff) or 0
   if got>0 then
    local values=j.buffer.table(1,got*source.channels*2)
    for i=0,min(got,count)-1 do
     local bin=j.bin+i+1;local pk=A.wave[bin] or 0
     for c=1,source.channels do local k=i*source.channels+c;pk=max(pk,abs(values[k] or 0),abs(values[got*source.channels+k] or 0)) end
     A.wave[bin]=pk;j.max=max(j.max,pk)
    end
   else
    -- Missing/offline peak data is optional; retain editing and retry later.
    A.wave_retry=now+2
   end
   j.bin=j.bin+count
  end
  batches=batches+1
 until j.index>=j.total or batches>=8 or R.time_precise()>=budget
 A.wave_max=max(.001,j.max)
 if j.index>=j.total then UI.stop_wave();UI.dirty(true)
 elseif now>(A.wave_present_at or 0) then A.wave_present_at=now+.15;UI.dirty(true) end
end

function UI.check_current()
 local reason
 if not Track.valid(A.v) then reason='トラックと時間範囲を選択してください。'
 elseif not Track.same(A.v,Track.target()) then reason='対象トラックまたは時間範囲が変わりました。'
 elseif (R.GetPlayStateEx(A.v.project)&5)~=0 then reason='編集は再生・録音を停止してから行ってください。' end
 if reason then notice(reason,true);UI.dirty();return false end
 return true
end

function UI.format(key,y) return string.format('%.1f %%',(y+1)*50) end
function UI.axis_label(key,y)
 local c=A.layers[key];local p=c and c.properties
 if not p or not c.env then return '—' end
 local raw=Track.raw(p,y)
 if R.Envelope_FormatValue then
  local ok,text=pcall(R.Envelope_FormatValue,c.env,raw)
  if ok and type(text)=='string' and text~='' then return text end
 end
 local value=R.ScaleFromEnvelopeMode and R.ScaleFromEnvelopeMode(p.mode,raw) or raw
 if p.kind==0 or p.kind==1 then return value<=0 and '-inf dB' or string.format('%.2f dB',20*math.log(value,10)) end
 return string.format('%.6g',value)
end
function UI.available(id)
 local editing=not A.busy
 local number=id:match('^number_(.+)$')
 if number then return editing and A.tool=='line' and UI.number_enabled(number) end
 if id=='pattern' or id=='direction' or id:match('^period_unit_') or id:match('^variable_') then return editing and A.tool=='line' end
 if id=='apply' then
  if not editing or A.drag or not Track.valid(A.v) or A.conflict then return false end
  for _,binding in pairs(A.bindings) do if Track.resolve(A.v,binding) then return true end end
  return false
 end
 if id=='drawundo' then return editing and A.v~=nil and R.Undo_CanUndo2(A.v.project)~=nil end
 if id=='drawredo' then return editing and A.v~=nil and R.Undo_CanRedo2(A.v.project)~=nil end
 if id=='clear' or id:match('^tool_') or id:match('^enable_') then return editing end
 return true
end
function UI.fit_text(t,width,size,kind) font(size,kind,false);return BLT.ui.fit(tostring(t),width*scale) end

function UI.button(id,title,sub,x,y,w,h,fn,enabled,selected,tone)
 enabled=enabled~=false;local hover=A.hit==id and enabled;local c=tone or C.accent2
 local child=id=='pattern' or id=='direction' or id:match('^period_unit_')
 local dim=child and A.tool~='line'
 local dy=pressed==id and (gfx.mouse_cap&1)~=0 and 1.5 or 0;y=y+dy
 local a=animate('button_'..id,hover and 1 or 0)
 if id:match('^enable_') and selected then
  gradient(x,y,w,h,UI.theme_color({.15,.45,.8},'accent'),C.panel,.72+.16*a,.75);rect(x,y,w,2,UI.theme_color({.45,.8,1},'focus2'),.9);finish_corners(x,y,w,h,5,false,UI.theme_color({.4,.75,1},'accent2'),.85)

 else
  gradient(x,y,w,h,dim and UI.theme_color({.16,.16,.17},'panel2') or C.panel2,dim and UI.theme_color({.09,.09,.10},'panel') or C.panel,dim and .95 or (.34+.16*a),.92)
  gradient(x,y,w,1,c,c,selected and .68 or (.16+.50*a),.02)
  line(x,y+h,x+w,y+h,C.edge,.46)
  if hover or selected then rect(x,y,id:match('^mode_') and 4 or 2,h,c,selected and .55 or .65) end
  finish_corners(x,y,w,h,6,false,selected and c or C.edge2,enabled and (.28+.35*a) or .16)
 end
 if selected and enabled and id:match('^mode_') then
  rect(x+1,y+1,w-2,h-2,c,.10)
  finish_corners(x,y,w,h,6,false,c,.85)
 end
 if sub then
  label(sub,x+12,y+6,11,enabled and c or C.faint,3,w-24,16,0,true)
  label(title,x+12,y+25,16,enabled and C.text or C.faint,1,w-24,26,0,true)
 else label(title,x,y+2,id:match('^period_unit_') and 11 or 14,dim and C.muted or enabled and ((hover or selected) and C.text or C.muted) or C.faint,1,w,h-3,5,true) end
 register(id,x,y-dy,w,h,fn,'',enabled)
end
function UI.primary()
 local x,y,w,h=390,767,444,52;local enabled=UI.available('apply')
 PrimaryButton.draw(PrimaryButton.painter,x,y,w,h,'表示範囲をオートメーション化',Language.code=='JP' and '既存分は延伸・統合' or 'EXTEND / MERGE EXISTING',enabled,false,nil,A.hit=='apply',pressed=='apply' and (gfx.mouse_cap&1)~=0,R.time_precise(),BLT.host.active())
 register('apply',x,y,w,h,UI.apply,'',enabled)
end
function UI.canvas_surface()
 local g=UI.graph
 if A.wave_dirty then
  local saveDest=gfx.dest;local oldscale,oldox,oldoy=scale,ox,oy
  gfx.setimgdim(UI.WAVE,g.w,g.h);gfx.dest=UI.WAVE;scale,ox,oy=1,-g.x,-g.y
 BLT.viewport(scale,gfx.ext_retina or 1);  rect(g.x,g.y,g.w,g.h,C.field,1)
  for i=0,8 do local x=g.x+g.w*i/8;line(x,g.y,x,g.y+g.h,C.edge,i%2==0 and .35 or .18) end
  for i=0,8 do local y=g.y+g.h*i/8;line(g.x,y,g.x+g.w,y,C.edge,(i==4 and not A.layers[A.layer].filter) and .56 or .21) end
  local n=#A.wave;local original=false
  if n>0 then
   for px=0,g.w-1 do
    local u=A.view+px/g.w*A.span;local u2=A.view+(px+1)/g.w*A.span
    local a,b=clamp(floor(u*n)+1,1,n),clamp(ceil(u2*n),1,n);local pk=0
    for j=a,max(a,b) do pk=max(pk,A.wave[j] or 0) end
    local gain=1
    local amplitude=min(.47*g.h,pk/max(.001,A.wave_max)*g.h*.38*gain)
    local c=original and C.accent2 or C.muted
    line(g.x+px,g.y+g.h/2-amplitude,g.x+px,g.y+g.h/2+amplitude,c,original and .40 or .28)
   end
  end
  scale,ox,oy=oldscale,oldox,oldoy; BLT.viewport(scale,gfx.ext_retina or 1);gfx.dest=saveDest;A.wave_dirty=false
 end
 gfx.mode=0;gfx.a=1;gfx.blit(UI.WAVE,1,0,0,0,g.w,g.h,sx(g.x),sy(g.y),g.w*scale,g.h*scale)
end
function UI.output_time(u) return A.v and (A.v.pos+u*A.v.len) or 0 end
function UI.curve_screen_u(u)
 -- Keep the editor on the source timeline; generation only maps output audio.
 return u
end

function UI.region(c,time,owner)
 local first,last=A.v.pos,A.v.pos+A.v.len
 if owner==nil then local count;owner,count=Track.owner(c.items,time);if count>1 then return end end
 if owner>=0 then
  local item=c.items[owner+1];if not item then return end
  first,last=max(first,item.pos),min(last,item.pos+item.len)
  for _,a in ipairs(c.items) do if a.ai~=owner and a.pos<last-1e-9 and a.pos+a.len>first+1e-9 then
   if a.pos<=time and a.pos+a.len>=time then return end
   if a.pos>time then last=min(last,a.pos-1e-8) else first=max(first,a.pos+a.len+1e-8) end
  end end
 else
  for _,a in ipairs(c.items) do
   if a.pos+a.len<=time then first=max(first,a.pos+a.len+1e-8)
   elseif a.pos>=time then last=min(last,a.pos-1e-8)
   else return end
  end
 end
 if last<first then return end
 return {first=first,last=last,owner=owner}
end
function UI.in_region(point,region)
 return region and point.ai==region.owner and point.time>=region.first-1e-9 and point.time<=region.last+1e-9
end
function UI.automation_regions()
 local c=A.layers[A.layer];if not c or not c.env or not A.v then return end
 local g=UI.graph
 for _,a in ipairs(c.items) do
  local first,last=max(A.v.pos,a.pos),min(A.v.pos+A.v.len,a.pos+a.len)
  if last>first then
   local x=g.x+(first-A.v.pos)/A.v.len*g.w;local r=g.x+(last-A.v.pos)/A.v.len*g.w
   local tint=a.mute and C.muted or UI.def().color
   rect(x,g.y,r-x,g.h,tint,.065)
   line(x,g.y,x,g.y+g.h,tint,.4);line(r,g.y,r,g.y+g.h,tint,.4)
   if r-x>44 then label('AI '..(a.ai+1),x+5,g.y+4,10,tint,3,r-x-10,14) end
  end
 end
end
function UI.curves()
 local g=UI.graph
 for pass=1,2 do for _,d in ipairs(UI.defs) do
  local active=d.key==A.layer;local c=A.layers[d.key]
  if c.env and (active or c.enabled) and (pass==2)==active then
   local count=ceil(g.w*scale)
   if not c.trace or c.trace_width~=count then
    c.trace_width=count;local times={}
    for i=0,count do times[#times+1]=A.v.pos+A.v.len*i/count end
    for _,p in ipairs(c.points) do
     times[#times+1]=p.time
     if p.time>A.v.pos then times[#times+1]=p.time-min(1e-9,A.v.len*1e-10) end
    end
    for _,a in ipairs(c.items) do
     for _,time in ipairs({a.pos,a.pos+a.len}) do if time>A.v.pos and time<A.v.pos+A.v.len then
      times[#times+1]=time;times[#times+1]=time-min(1e-9,A.v.len*1e-10)
     end end
    end
    table.sort(times);c.trace={}
    for _,time in ipairs(times) do c.trace[#c.trace+1]={x=(time-A.v.pos)/A.v.len,y=Track.normalized(c.properties,Track.evaluate(c.env,time))} end
   end
   local previous
   for _,p in ipairs(c.trace) do
    local x,y=g.x+p.x*g.w,g.y+(1-p.y)*g.h/2
    if previous then
     if active then UI.thick_line(previous.x,previous.y,x,y,d.color,.32,3) end
     line(previous.x,previous.y,x,y,d.color,active and .98 or .38)
    end
    previous={x=x,y=y}
   end
   if active then
    for _,p in ipairs(c.points) do
     local x,y=UI.point_position(p)
     disc(x,y,p.selected and 4.5 or 3.5,C.field,1)
     disc(x,y,p.selected and 3.2 or 2.3,p.selected and C.focus2 or d.color,p.editable and .98 or .35)
    end
   end
  end
 end end
end
function UI.static()
 UI.theme_sync()
 widgets={};text_queue={};rect(0,0,W,H+22,C.bg)
 gradient(0,0,W,90,C.bg2,C.bg,.22,0,true);
 BLT.title('ENVELOPE CANVAS TRACK','TRACK AUTOMATION DRAWING  トラックのオートメーション描画',W)
 label(A.v and UI.fit_text(string.format('%s  |  %.3f — %.3f s',A.v.name,A.v.pos,A.v.pos+A.v.len),1050,16,1) or '',24,105,16,C.text,1,1050,27,0,true)
 UI.tools_panel()
 local d=UI.def();label(d.code,212,141,12,d.color,3,130,21,0,true)
 label(UI.fit_text(A.bindings[d.key] and A.bindings[d.key].name or Language.message(d.sub),380,12,1),350,141,12,C.muted,1,380,21)
 right_label(A.v and 'LIVE / TRACK AUTOMATION' or 'TRACK / TIME SELECTION',996,141,11,C.muted,3,true)
 UI.canvas_surface();UI.automation_regions();UI.curves()

 local g=UI.graph
 for i=0,4 do
  local y=1-i*.5;right_label(UI.fit_text(UI.axis_label(A.layer,y),98,12,3),1100,g.y+i*g.h/4-7,12,d.color,3,false)
 end
 for i=0,4 do label(string.format('%.3f s',UI.output_time(A.view+A.span*i/4)),g.x+g.w*i/4-(i==4 and 90 or 0),548,12,C.muted,3,120,20) end
 label(A.tool=='line' and 'クリック：描画  ·  ホイール：横幅の開始 / Ctrl：縦幅の開始 / Shift：微調整  ·  Alt：位相反転' or A.tool=='select' and 'ドラッグ：範囲選択  ·  枠内：移動  ·  辺／角：変形  ·  Alt＋線：曲率' or 'ドラッグ：描画／点移動  ·  Ctrl：点をつかまず描画  ·  Alt＋線：曲率  ·  右ドラッグ：範囲選択',212,573,13,C.muted,1,866,23)
 if A.tool=='line' then
  label(Language.code=='JP' and '変化速度：到達までの時間（大きいほど遅い）  ·  曲率：0＝直線 / ＋＝先に変化 / −＝後で変化' or 'Time: duration to target (larger = slower) · Curve: 0 linear / + early / - late',212,594,12,C.muted,1,866,20)
 end
 for i,q in ipairs(UI.defs) do
  local x,cy,cw=UI.card_geometry(i);local enabled=A.layers[q.key].env~=nil;local visible=A.layers[q.key].visible
  local tint=enabled and q.color or C.muted
  local hover=A.hit=='layer_'..q.key
  local glow=animate('card_'..q.key,hover and 1 or 0)
  gradient(x,cy,cw,61,enabled and C.panel2 or UI.theme_color({.15,.15,.16},'panel2'),enabled and C.panel or UI.theme_color({.085,.085,.09},'panel'),enabled and (.22+.22*glow) or .95,.92)
  if hover then gradient(x,cy,cw,30,tint,C.panel,.16,.03) end
  rect(x,cy,cw,2,tint,hover and .95 or A.layer==q.key and .65 or .25);finish_corners(x,cy,cw,61,8,false,C.edge2,.3)
  label(q.name,x+8,cy+5,16,enabled and (A.layer==q.key and C.text or C.muted) or C.muted,1,cw-86,24,5,true)
  register('layer_'..q.key,x,cy,cw,30,function() A.layer=q.key;A.selection=nil;UI.dirty(true) end,'',true)
  UI.button('copy_'..q.key,'COPY',nil,x+cw-70,cy+4,62,23,function() UI.copy_curve(q.key) end,not A.busy and enabled and A.layer~=q.key and A.layers[A.layer].env~=nil,false,tint)
  local binding=A.bindings[q.key]
  local caption=binding and binding.name or '割当先を選択'
  UI.button('assign_'..q.key,UI.fit_text(Language.message(caption),cw-102,14,1),nil,x+8,cy+32,cw-86,26,function() UI.assign(q.key) end,not A.busy and A.v~=nil,false,tint)
  UI.button('visible_'..q.key,Language.code=='EN' and (visible and 'Shown' or 'Hidden') or (visible and '表示' or '非表示'),nil,x+cw-68,cy+32,60,26,function() UI.toggle_lane(q.key) end,not A.busy and enabled,visible,tint)
 end
 
 UI.primary()
 local status=A.status
 if A.wave_job then status=string.format('波形を読み込み中  %d%%',floor(A.wave_job.index/A.wave_job.total*100))

 elseif status=='' then status=A.v and '' or 'トラックと時間範囲を選択してください。' end

 BLT.footer(status,A.warning or A.conflict,W,H+22,Core.VERSION)
 flush_text_queue()
end
function UI.thick_line(x,y,x2,y2,c,a,width)
 local dx,dy=x2-x,y2-y;local length=math.sqrt(dx*dx+dy*dy)
 if length<1e-9 then return end
 local nx,ny=-dy/length,dx/length
 for i=0,width-1 do local offset=i-(width-1)/2;line(x+nx*offset,y+ny*offset,x2+nx*offset,y2+ny*offset,c,a) end
end
function UI.icon()
 local bs,bx,by=scale,ox,oy;ox,oy=ox+(W-102)*scale,oy+31*scale;scale=scale*.78

 local x,y=0,0;local colors={UI.defs[1].color,UI.defs[2].color,UI.defs[4].color}
 local breathe=.5+.5*math.sin(anim_time*.55)
 for i=1,6 do
  local phase=anim_time*(.10+(i%3)*.018)+i*1.47
  local px=x+46+math.sin(phase*1.09)*(20+(i%2)*6);local py=y+33+math.cos(phase*.79)*(7+(i%3)*2)
  local rr=10+(i%4)*3+breathe*1.6
  disc(px,py,rr+10,C.accent,.004+.003*breathe);disc(px,py,rr+3,C.accent3,.008+.004*breathe)
 end
 for lane=1,3 do
  local c=colors[lane];local last
  rect(0,12+lane*12,9,9,C.panel2,.85);rect(0,12+lane*12,2,9,c,.75)
  line(12,23+lane*12,93,23+lane*12,c,.16)
  for i=0,24 do local u=i/24;local py=y+16+lane*12+math.sin(u*5+lane*.8)*3
   if last then UI.thick_line(last.x,last.y,x+13+u*80,py,c,.4,2) end;last={x=x+13+u*80,y=py}
  end
 end
 if animations_active then icon_clock=icon_clock+frame_dt end
 while icon_clock>.16 and #icon_particles<24 do
  icon_clock=icon_clock-.16;icon_serial=icon_serial+1;local n=icon_serial;local lane=n%3+1
  local a,b,c,d=particle_hash(n,21),particle_hash(n,22),particle_hash(n,23),particle_hash(n,24)
  local u=.10+.80*a
  icon_particles[#icon_particles+1]={x=x+13+u*80,y=y+16+lane*12+math.sin(u*5+lane*.8)*3,
   age=0,life=2.8+b*1.55,r=.65+a*.75,phase=c*math.pi*2,sway=2+d*3,vy=4+b*4,vx=(c-.5)*4}
 end
 for i=#icon_particles,1,-1 do
  local p=icon_particles[i];p.age=p.age+particle_dt
  if p.age>p.life then table.remove(icon_particles,i) else
   local a=math.sin(math.pi*p.age/p.life)^1.85
   local xx=p.x+p.vx*p.age+math.sin(p.age*.63+p.phase)*p.sway;local yy=p.y-p.vy*p.age
   disc(xx,yy,p.r+8,C.accent,.008*a);disc(xx,yy,p.r+4,C.accent3,.016*a)
   disc(xx,yy,p.r+1.8,C.accent2,.060*a);disc(xx,yy,p.r,C.focus2,.46*a)
  end
 end

 scale,ox,oy=bs,bx,by
end
function UI.soft_lights()
 local glow=UI.theme_color({.28,.64,1},'accent2')
 for i,q in ipairs(UI.defs) do if A.layers[q.key].visible then
  local cx,cy,cw=UI.card_geometry(i);local x,y=cx+cw-68,cy+32
  for r=1,5 do rect(x-r,y-r,60+2*r,26+2*r,glow,.010*(6-r)) end
 end end
end
function UI.poll_playhead()
 local playing=A.v and (R.GetPlayStateEx(A.v.project)&1)~=0 or false
 if playing~=A.playing then A.playing=playing;redraw_dirty=true;next_draw_time=0 end
end
function UI.playhead()
 if not A.playing or not A.v then return end
 local time=R.GetPlayPositionEx(A.v.project)
 if not finite(time) or time<A.v.pos or time>A.v.pos+A.v.len then return end
 local g=UI.graph;local x=g.x+(time-A.v.pos)/A.v.len*g.w
 line(x,g.y,x,g.y+g.h,C.focus2,.95)
 rect(x-3,g.y,6,4,C.focus2,1)
end
function UI.effects()
 UI.icon();UI.playhead();UI.point_highlight();UI.segment_highlight();UI.mode_overlay();UI.soft_lights();UI.number_lights()
end
function UI.geometry()
 local content=max(1,gfx.h-Chrome.titleH);local newscale=max(.25,min(gfx.w/W,content/H))
 if newscale~=scale then A.content_dirty=true;A.wave_dirty=true end
 scale=newscale;ox,oy=(gfx.w-W*scale)/2,Chrome.titleH+(content-H*scale)/2-22*scale
 BLT.viewport(scale,gfx.ext_retina or 1); mouse_x,mouse_y=(gfx.mouse_x-ox)/scale,(gfx.mouse_y-oy)/scale
end
function UI.render(now)
 UI.geometry()
 particle_dt=clamp(now-frame_clock,0,.1);frame_clock=now
 animation_speed=A.active and visual_speed(now) or 0;animations_active=animation_speed>0
 frame_dt=particle_dt*animation_speed;anim_time=anim_time+frame_dt
 if now<(A.hover_until or 0) or now<(A.number_flash_until or 0) then A.content_dirty=true end
 if UI.frame_w~=gfx.w or UI.frame_h~=gfx.h then
  UI.frame_w,UI.frame_h=gfx.w,gfx.h;gfx.setimgdim(UI.FRAME,gfx.w,gfx.h);A.content_dirty=true
 end
 if A.content_dirty then
  gfx.dest=UI.FRAME;gfx.mode=0;gfx.set(C.bg[1],C.bg[2],C.bg[3],1);gfx.rect(0,0,gfx.w,gfx.h,1)
  UI.static();gfx.dest=-1;A.content_dirty=false
 end
 -- Never inherit gfx.x/y here: text drawing leaves the cursor near the footer.
 -- An implicit destination shifts the entire cached UI outside the window,
 -- while the separately drawn icon/titlebar still appear in their normal places.
 gfx.dest=-1;gfx.mode=0;gfx.a=1
 gfx.blit(UI.FRAME,1,0,0,0,UI.frame_w,UI.frame_h,0,0,gfx.w,gfx.h)
 UI.effects()
 if inside(UI.graph.x,UI.graph.y,UI.graph.w,UI.graph.h) and A.v and A.active then
  local g=UI.graph;local u=A.view+(mouse_x-g.x)/g.w*A.span;local value=clamp(1-2*(mouse_y-g.y)/g.h,-1,1)
  line(mouse_x,g.y,mouse_x,g.y+g.h,C.accent2,.23);line(g.x,mouse_y,g.x+g.w,mouse_y,C.accent2,.12)
  local s=string.format('%.3fs  /  %s',UI.output_time(u),UI.axis_label(A.layer,value))
  local xx=mouse_x-112;local yy=mouse_y+18
  label(s,xx+7,yy+3,13,UI.def().color,3,210,21,1);flush_text_queue()
 end
 custom_titlebar();gfx.update()
end

function UI.point_position(p)
 local g=UI.graph;local u=UI.curve_screen_u(p.x);local ay=UI.to_axis(A.layer,p.y)
 return g.x+(u-A.view)/A.span*g.w,g.y+(1-ay)*g.h/2,u>=A.view-1e-9 and u<=A.view+A.span+1e-9 and abs(ay)<=1
end
function UI.nearest()
 local best,dist=nil,14*14
 for i,p in ipairs(A.layers[A.layer].points) do
  local x,y,visible=UI.point_position(p)
  local dd=((mouse_x-x)*scale)^2+((mouse_y-y)*scale)^2
  if visible and dd<=dist then best,dist=i,dd end
 end;return best
end
function UI.hover_point(index)
 local key=index and A.layer..':'..index or nil
 if key~=A.hover_point_key then
  A.hover_point_key=key;A.hover_node=index;A.point_flash=R.time_precise();UI.dirty()
 end
end
function UI.point_highlight()
 local i=A.hover_node;local p=i and A.layers[A.layer].points[i]
 if not p or not A.active or A.busy then return end
 local x,y,visible=UI.point_position(p);if not visible then return end
 local flash=max(0,1-(R.time_precise()-(A.point_flash or 0))/.22)
 disc(x,y,6/scale,C.field,.95);disc(x,y,4.3/scale,UI.def().color,1)
 if flash>0 then disc(x,y,(4.3+2*flash)/scale,C.focus2,flash*.85) end
end
function UI.hover_segment(allowed)
 local point,segment
 if allowed and A.tool=='free' and A.active and not A.busy and not A.drag and A.v then point,segment=UI.segment_at(true) end
 local key=point and segment and table.concat({A.layer,tostring(A.layers[A.layer].env),point.ai,point.index,segment.first,segment.last},':') or nil
 if key~=A.hover_segment_key then
  A.hover_segment_key=key;A.segment_flash=R.time_precise();UI.dirty()
  if key then wake_visuals(A.segment_flash) end
 end
 A.hover_segment=segment
end
function UI.segment_highlight()
 local segment=A.hover_segment
 if not segment or A.tool~='free' or not A.active or A.busy or A.drag or A.hover_node or not A.v then return end
 local flash=max(0,1-(R.time_precise()-(A.segment_flash or 0))/.22)
 if flash<=0 then return end
 local c=A.layers[A.layer];local trace=c.trace;if not trace then return end
 local g=UI.graph;local first=max(0,(segment.first-A.v.pos)/A.v.len);local last=min(1,(segment.last-A.v.pos)/A.v.len)
 for i=2,#trace do
  local a,b=trace[i-1],trace[i]
  if a.x>=last then break end
  if b.x>first and b.x>a.x then
   local left=max(first,a.x);local right=min(last,b.x)
   local y1=a.y+(b.y-a.y)*(left-a.x)/(b.x-a.x);local y2=a.y+(b.y-a.y)*(right-a.x)/(b.x-a.x)
   UI.thick_line(g.x+left*g.w,g.y+(1-y1)*g.h/2,g.x+right*g.w,g.y+(1-y2)*g.h/2,C.focus2,.65*flash,(3+2*flash)/scale)
  end
 end
end
function UI.activation_press(down)
 if not down or type(gfx.screentoclient)~='function' then return false end
 local sx0,sy0=R.GetMousePosition();local px,py=gfx.screentoclient(sx0,sy0)
 return px and py and px>=0 and px<gfx.w and py>=0 and py<gfx.h
end

function UI.delete_selected()
 if A.busy or A.drag then return end
 local c=A.layers[A.layer];if not c.env then return end
 local selected={};for _,p in ipairs(c.points) do if p.selected then selected[#selected+1]=p end end
 if #selected==0 then return end
 table.sort(selected,function(a,b) if a.ai==b.ai then return a.index>b.index end;return a.ai>b.ai end)
 UI.native_write(c.env,function()
  local sorted={};local has_ai=false
  for _,p in ipairs(selected) do
   if p.ai<0 then
    if not R.DeleteEnvelopePointEx(c.env,p.ai,p.index) then error('Cannot delete envelope point',0) end
    sorted[p.ai]=true
   else has_ai=true end
  end
  if has_ai then
   -- Deleting one pooled point removes its visible repetitions too. Re-read
   -- indices after each deletion instead of applying stale duplicate indices.
   local deadline=R.time_precise()+.35;local removed=0
   while true do
    local candidate
    for _,a in ipairs(c.items) do
     for _,p in ipairs(Track.nodes(c.env,a.ai,A.v.pos,A.v.pos+A.v.len)) do
      if p.selected and p.time>=A.v.pos and p.time<=A.v.pos+A.v.len then candidate=p end
     end
    end
    if not candidate then break end
    if R.time_precise()>deadline or removed>=10000 then error('Too many pooled points in one edit. Select a smaller range.',0) end
    if not R.DeleteEnvelopePointEx(c.env,candidate.ai,candidate.index) then error('Cannot delete envelope point',0) end
    sorted[candidate.ai]=true;removed=removed+1
   end
  end
  for ai in pairs(sorted) do R.Envelope_SortPointsEx(c.env,ai) end
 end,false)
end

function UI.mode_overlay()
 UI.line_preview()
 local d=A.drag
 if A.tool=='select' and (not d or d.mode~='marquee') then
  local b=UI.selection_bounds()
  if b then
   rect(b.x,b.y,b.r-b.x,b.b-b.y,C.accent2,.05)
   for _,x in ipairs({b.x,b.r}) do line(x,b.y,x,b.b,C.accent2,.75) end
   for _,y in ipairs({b.y,b.b}) do line(b.x,y,b.r,y,C.accent2,.75) end
   for _,x in ipairs({b.x,(b.x+b.r)/2,b.r}) do for _,y in ipairs({b.y,(b.y+b.b)/2,b.b}) do
    if x~=(b.x+b.r)/2 or y~=(b.y+b.b)/2 then rect(x-3/scale,y-3/scale,6/scale,6/scale,C.accent2,.85) end
   end end
  end
 end
 if d and d.mode=='marquee' then
  local x,y=min(d.x,d.r),min(d.y,d.b);local w,h=abs(d.r-d.x),abs(d.b-d.y)
  rect(x,y,w,h,C.accent2,.1);line(x,y,x+w,y,C.accent2,.8);line(x,y+h,x+w,y+h,C.accent2,.8)
  line(x,y,x,y+h,C.accent2,.8);line(x+w,y,x+w,y+h,C.accent2,.8)
 end
end

function UI.pointer_buttons()
 local cap=gfx.mouse_cap
 if A.pointer_capture and A.drag and R.JS_Mouse_GetState then
  local ok,state=pcall(R.JS_Mouse_GetState,3)
  if ok and type(state)=='number' then cap=(cap&~3)|(state&3) end
 end
 return (cap&1)~=0,(cap&2)~=0
end
function UI.interact()
 local down,right=UI.pointer_buttons()
 if BLT.blocked() and not (A.drag and A.pointer_capture) then
  if A.drag then Track.finish();UI.cancel_preview() end
  down_last=down;A.right_last=right;pressed=nil;gfx.mouse_wheel=0;return
 end
 UI.geometry();local wheel=gfx.mouse_wheel or 0
 local hit
 for i=#widgets,1,-1 do local w=widgets[i];if inside(w.x,w.y,w.w,w.h) then hit=w;break end end
 local id=hit and hit.id
 if A.hit~=id then A.hit=id;UI.dirty() end
 local g=UI.graph;local in_graph=inside(g.x,g.y,g.w,g.h)
 if not (A.active or A.pointer_capture or UI.activation_press(down)) then
  Track.finish();UI.cancel_preview();down_last=down;A.right_last=right;return
 end
 if UI.number_input(id,down,wheel) then down_last=down;A.right_last=right;return end
 gfx.mouse_wheel=0
 local nearest=in_graph and A.v and UI.nearest() or nil
 UI.hover_point(nearest)
 UI.hover_segment(in_graph and not nearest and not down and not right)
 if gfx.setcursor then gfx.setcursor(32512) end
 if right and not A.right_last and in_graph and A.v and not A.drag then
  A.drag={mode='marquee',x=mouse_x,y=mouse_y,r=mouse_x,b=mouse_y,index=nearest};A.pointer_capture=true
 end
 if A.drag and A.drag.mode=='marquee' then
  local d=A.drag;local region=UI.region(A.layers[A.layer],A.v.pos+clamp((d.x-g.x)/g.w,0,1)*A.v.len)
  local l=region and g.x+(region.first-A.v.pos)/A.v.len*g.w or d.x
  local r=region and g.x+(region.last-A.v.pos)/A.v.len*g.w or d.x
  d.r=clamp(mouse_x,l,r);d.b=clamp(mouse_y,g.y,g.y+g.h);UI.dirty()
  if not (d.left and down or not d.left and right) then
   local moved=abs(d.r-d.x)+abs(d.b-d.y)>4/scale;A.drag=nil;A.pointer_capture=nil
   if moved then UI.select_native(nil,false,{x=min(d.x,d.r),r=max(d.x,d.r),y=min(d.y,d.b),b=max(d.y,d.b),anchor=d.x})
   elseif not d.left then UI.shape_menu(d.index) else UI.select_native(nil,false) end
  end
  down_last=down;A.right_last=right;return
 end
 if down and not down_last then
  pressed=hit and hit.enabled and UI.available(id) and id or nil
  if in_graph and A.v and A.bindings[A.layer] and not A.busy then
   local alt=(gfx.mouse_cap&16)~=0;local ctrl=(gfx.mouse_cap&4)~=0;local shift=(gfx.mouse_cap&8)~=0
   if alt and A.tool~='line' then
    local point=UI.segment_at()
    if point then A.drag={mode='native_tension',point=Core.copy(point),env=A.layers[A.layer].env,tension=point.tension,mx=mouse_x,my=mouse_y};A.pointer_capture=true end
   elseif A.tool=='line' then UI.stamp_line()
   elseif A.tool=='select' and not ctrl then
    local handle,box=UI.box_hit()
    if handle~=nil then UI.begin_transform(handle,box)
    elseif nearest then UI.begin_nodes(nearest)
    else A.drag={mode='marquee',left=true,x=mouse_x,y=mouse_y,r=mouse_x,b=mouse_y};A.pointer_capture=true end
   elseif nearest and not (A.tool=='free' and ctrl) then
    if A.tool=='select' and ctrl then UI.select_native(nearest,true) else UI.begin_nodes(nearest) end
   else
    local x=clamp((mouse_x-g.x)/g.w,0,1);local y=clamp(1-2*(mouse_y-g.y)/g.h,-1,1)
    if UI.write_drawing({{x=x,y=y}},x,x,true) then A.drag={mode='native_pen',x=x,y=y};A.pointer_capture=true end
   end
  end
 end
 if down and A.drag then
  if A.drag.mode=='native_pen' then UI.pen_tick(false) elseif A.drag.mode=='native_transform' then UI.transform_tick(false) elseif A.drag.mode~='marquee' then UI.drag_native(false) end
 end
 if not down and down_last then
  if A.drag then
   if A.drag.mode=='native_pen' then UI.pen_tick(true) elseif A.drag.mode=='native_transform' then UI.transform_tick(true) elseif A.drag.mode~='marquee' then UI.drag_native(true) end
   Track.finish();A.drag=nil;A.pointer_capture=nil;UI.sync_curves()
  elseif hit and hit.enabled and pressed==id and UI.available(id) then UI.safe(hit.fn) end
  pressed=nil;UI.dirty()
 end
 down_last=down;A.right_last=right
end
function UI.key(k)
 k=BLT.key(k);if k==0 then return end
 if UI.number_key(k) then return end
 local ctrl=(gfx.mouse_cap&4)~=0;local shift=(gfx.mouse_cap&8)~=0
 if k==27 then if A.drag then Track.finish();UI.cancel_preview();UI.sync_curves() else A.closing=true end
 elseif k==26 or ctrl and (k==122 or k==90) then UI.undo_draw(shift)
 elseif k==25 or ctrl and (k==121 or k==89) then UI.undo_draw(true)
 elseif k==6579564 or k==127 then UI.delete_selected()
 elseif k>=49 and k<=51 then UI.set_mode(({'select','free','line'})[k-48])
 elseif k==13 then UI.apply()
 elseif k==32 and A.v then R.Main_OnCommandEx(40044,0,A.v.project) end
end

-- Store preferences only: drawing points and track targets belong to the session.
function UI.settings_schema()
 if UI.preference_schema then return UI.preference_schema end
 UI.preference_schema={layer={values={'slot1','slot2','slot3','slot4','slot5','slot6'}},tool={values={'select','free','line'}},
  width_variable={boolean=true},height_variable={boolean=true},
  direction={values={1,2,3}},pattern={values={1,2,3,4,5,6}},period_unit={values={'sec','beat','grid'}},
  width_start={min=.001,max=3600},width_end={min=.001,max=3600},width_duration={min=.001,max=3600},width_curve={min=-100,max=100},
  height_start={min=0,max=200},height_end={min=0,max=200},height_duration={min=.001,max=3600},height_curve={min=-100,max=100}}
 return UI.preference_schema
end
function UI.settings_slot(path)
 local obj=A;local last
 for part in path:gmatch('[^.]+') do if last then obj=obj[last] end;last=part end
 return obj,last
end
function UI.save_settings()
 local rows={'version=1'}
 for path in pairs(UI.settings_schema()) do
  local obj,key=UI.settings_slot(path);local value=obj[key]
  if value~=nil then rows[#rows+1]=path..'='..tostring(value) end
 end
 BLT.store(SECTION,'preferences_v1',table.concat(rows,'\n'),true)
end
function UI.load_settings()
 local data=R.GetExtState(SECTION,'preferences_v1')
 if not data or not data:match('^version=1\n') then return end
 local schema=UI.settings_schema()
 for line in data:gmatch('[^\n]+') do
  local path,raw=line:match('^([^=]+)=(.*)$')
  local spec=path and schema[path]
  if spec then
   local value,valid
   if spec.boolean then value=raw=='true';valid=raw=='true' or raw=='false'
   elseif spec.values then
    for _,v in ipairs(spec.values) do if tostring(v)==raw then value=v;valid=true;break end end
   else value=tonumber(raw);valid=finite(value) and value>=spec.min and value<=spec.max end
   if valid then local obj,key=UI.settings_slot(path);obj[key]=value end
  end
 end

 
 UI.sync_line_targets()
end
function UI.close()
 -- Teardown errors must not leave a dead graphics window on screen.
 local ok,err=xpcall(function()
 Track.finish()
 if A.closed then return end;UI.save_settings();A.closed=true;UI.stop_wave();clear_chrome_tooltip();titlebar_cleanup()
 local _,x,y,w,h=gfx.dock(-1,0,0,0,0)
 for key,v in pairs({window_x=x,window_y=y,window_w=w,window_h=h}) do if finite(v) then BLT.store(SECTION,key,tostring(floor(v+.5)),true) end end
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

 if A.closing then A.closing=true;return end
 local k=BLT.key(gfx.getchar());if k<0 then A.closing=true;return end
   local flags=gfx.getchar(65537);local active=(flags&1)==0 or (flags&2)~=0
  if active~=A.active then A.active=active;A.content_dirty=true;wake_visuals(now);next_draw_time=0;A.revision=nil end
  local button_changed=gfx.mouse_cap~=last_raw_mouse_cap
  local changed=gfx.mouse_x~=last_raw_mouse_x or gfx.mouse_y~=last_raw_mouse_y or gfx.mouse_cap~=last_raw_mouse_cap or (gfx.mouse_wheel or 0)~=0
  if changed or k>0 then wake_visuals(now) end
  -- The app bar consumes input during render; never drop a press/release
  -- merely because it arrived between animation frames.
  if button_changed then next_draw_time=0 end
  last_raw_mouse_x,last_raw_mouse_y,last_raw_mouse_cap=gfx.mouse_x,gfx.mouse_y,gfx.mouse_cap
  local count=0;while k>0 and count<32 do UI.key(k);count=count+1;k=BLT.key(gfx.getchar()) end
  if k<0 then A.closing=true;return end
  UI.poll(now)
  if Chameleon.tick(now) then UI.dirty(true) end

  if gfx.w~=last_window_w or gfx.h~=last_window_h then last_window_w,last_window_h=gfx.w,gfx.h;UI.dirty(true) end
  -- Input runs on each defer tick; animated presentation is capped independently.
  UI.geometry()
  UI.interact()
  -- Work is budgeted after input, so a new click never waits for waveform IO.
  if A.wave_job and R.EnumProjects(-1,'')==A.wave_job.v.project then
   local ok,err=pcall(UI.wave_step);if not ok then UI.stop_wave();notice(tostring(err),true) end
  end
  local speed=A.active and visual_speed(now) or 0
  UI.poll_playhead()
  local motion_active=(A.hover_segment and now<(A.segment_flash or 0)+.22) or A.playing or A.drag or A.number_drag or now<(A.number_flash_until or 0) or Chrome.drag or Chrome.resize
  local interval=motion_active and 1/60 or speed>0 and 1/30 or (#icon_particles>0) and 1/20 or nil
  if ((redraw_dirty or A.content_dirty or interval) and now>=next_draw_time) or (not interval and (redraw_dirty or A.content_dirty)) then
   UI.render(now);next_draw_time=now+(interval or 4);redraw_dirty=false
  end
  if Chrome.requestReset then Chrome.requestReset=false;reset_window_size();UI.dirty(true) end
  if Chrome.requestClose then A.closing=true end
 end)
 if A.closing then UI.close() else R.defer(UI.loop) end
end
Track={tag='P_POOL_EXT:BLT_CANVAS_TRACK_V1'}
function Track.required()
 if not R.BR_EnvAlloc or not R.BR_EnvGetProperties or not R.BR_EnvSetProperties or not R.BR_EnvFree then
  error('SWS拡張をインストールしてください。',0)
 end
end
function Track.list(track)
 local list={}
 for i=0,R.CountTrackEnvelopes(track)-1 do
  local env=R.GetTrackEnvelope(track,i)
  local ok,guid=R.GetSetEnvelopeInfo_String(env,'GUID','',false)
  local _,name=R.GetEnvelopeName(env,'')
  if ok and guid~='' then list[#list+1]={env=env,guid=guid,name=name} end
 end
 return list
end
function Track.resolve(v,binding)
 if not binding then return end
 local track=v.track
 if binding.track~=R.GetTrackGUID(track) then return end
 for _,entry in ipairs(Track.list(track)) do if entry.guid==binding.guid then return entry.env end end
end
function Track.properties(env)
 Track.required()
 local br=R.BR_EnvAlloc(env,false);if not br then error('Envelope properties unavailable',0) end
 local result={pcall(R.BR_EnvGetProperties,br)}
 R.BR_EnvFree(br,false)
 if not result[1] then error(result[2],0) end
 table.remove(result,1)
 local p={active=result[1],visible=result[2],armed=result[3],lane=result[4],height=result[5],shape=result[6],
  minimum=result[7],maximum=result[8],center=result[9],kind=result[10],fader=result[11],options=result[12]}
 if not finite(p.minimum) or not finite(p.maximum) or p.maximum<=p.minimum then error('Unsupported envelope range',0) end
 p.mode=R.GetEnvelopeScalingMode(env)
 p.low=R.ScaleToEnvelopeMode(p.mode,p.minimum);p.high=R.ScaleToEnvelopeMode(p.mode,p.maximum)
 if not finite(p.low) or not finite(p.high) or p.high<=p.low then error('Unsupported envelope scale',0) end
 return p
end
function Track.normalized(p,value) return clamp((value-p.low)/(p.high-p.low),0,1)*2-1 end
function Track.raw(p,y)
 local value=p.low+clamp((y+1)/2,0,1)*(p.high-p.low)
 if p.kind==6 then return y>=0 and p.high or p.low end
 return value
end

function UI.assign(key)
 if A.busy or not A.v then return end
 local track=A.v.track;local entries=Track.list(track)
 if #entries==0 then notice('エンベロープを先にREAPERで表示してください。',true);return end
 local rows={Language.message('割り当て解除')}
 local function safe(s) return s:gsub('[|<>#!]',' '):gsub('[\r\n]',' ') end
 for _,entry in ipairs(entries) do rows[#rows+1]=(A.bindings[key] and A.bindings[key].guid==entry.guid and '!' or '')..safe(entry.name) end
 gfx.x,gfx.y=gfx.mouse_x,gfx.mouse_y
 local pick=gfx.showmenu(table.concat(rows,'|'))
 pressed=nil;A.pointer_capture=nil;A.drag=nil;down_last=(gfx.mouse_cap&1)~=0
 if pick==1 then A.bindings[key]=nil;A.layers[key]=Core.new_layers()[key];UI.sync_curves()
 elseif pick>1 and entries[pick-1] then
  local entry=entries[pick-1]
  for k,binding in pairs(A.bindings) do if k~=key and binding.guid==entry.guid then notice('同じエンベロープを複数の枠には割り当てられません。',true);UI.dirty();return end end
  local ok,properties=pcall(Track.properties,entry.env)
  if not ok then notice(properties,true);UI.dirty();return end
  A.bindings[key]={track=R.GetTrackGUID(track),guid=entry.guid,name=entry.name};A.layer=key;A.record=nil
  A.layers[key].enabled=true
  UI.sync_curves(true,key)
 end
 UI.dirty(true)
end
function UI.load_selection(force,selected)
 if A.busy then return end
 local v=selected or Track.target()
 if Track.same(v,A.v) and not force then return end
 Track.finish();UI.stop_wave();A.drag=nil;A.number_drag=nil;A.selection=nil;pressed=nil;A.pointer_capture=nil
 A.v=v;A.record=nil;A.conflict=false;A.revision=nil;A.live_failed=nil;A.host_pending=nil;A.wave_retry=nil
 if not v then
  A.bindings={};A.layers=Core.new_layers();A.host_layers=A.layers;A.host_state=nil;A.wave={};A.wave_max=1;A.track_key=nil
  notice('トラックと時間範囲を選択してください。');UI.dirty(true);return
 end
 local key=tostring(v.project)..':'..v.guid
 if not A.track_sessions[key] then
  A.track_sessions[key]={};A.track_order=A.track_order or {};A.track_order[#A.track_order+1]=key
  while #A.track_order>16 do A.track_sessions[table.remove(A.track_order,1)]=nil end
 end
 A.bindings=A.track_sessions[key];A.track_key=key;A.layers=Core.new_layers();for k in pairs(A.bindings) do A.layers[k].enabled=true end
 A.status='';A.warning=false;UI.start_wave();UI.sync_curves(true)
 A.revision=R.GetProjectStateChangeCount(v.project);A.follow_env=nil;UI.follow_envelope(v);UI.dirty(true)
end

function UI.follow_envelope(v)
 if A.drag or A.number_drag or not R.GetCursorContext2 or R.GetCursorContext2(true)~=2 then return end
 local env=R.GetSelectedEnvelope(v.project)
 if not env or env==A.follow_env or not R.Envelope_GetParentTrack or R.Envelope_GetParentTrack(env)~=v.track then return end
 A.follow_env=env
 local ok,guid=R.GetSetEnvelopeInfo_String(env,'GUID','',false);if not ok then return end
 local key
 for k,b in pairs(A.bindings) do if b.guid==guid then key=k;break end end
 if not key then
  for _,def in ipairs(UI.defs) do if not A.bindings[def.key] then key=def.key;break end end
  if not key then return end
  local _,name=R.GetEnvelopeName(env,'')
  A.bindings[key]={track=v.guid,guid=guid,name=name}
 end
 A.layer=key;UI.sync_curves()
end
function UI.poll(now)
 if now<A.poll_at or A.busy then return end;A.poll_at=now+.05
 local v=Track.target()
 if v and Track.same(v,A.v) then UI.follow_envelope(v) end
 if not v then if A.v then UI.load_selection(false) end;return end
 if not Track.same(v,A.v) then UI.load_selection(false,v);return end
 local revision=R.GetProjectStateChangeCount(v.project)
 local revised=revision~=A.revision
 if revised then
  A.v=v
  local sources,signature=Track.wave_sources(v)
  if signature~=A.wave_signature then UI.start_wave(sources,signature) end
 end
 local native_down=R.JS_Mouse_GetState and (R.JS_Mouse_GetState(3)&3)~=0
 local native_edit=R.GetSelectedEnvelope(v.project)~=nil and R.GetCursorContext2(true)==2
 local native_release=A.host_mouse_down and not native_down
 A.host_mouse_down=native_down
 -- Native drags may precede the project revision update. Check those and their release.
 local check_drag=native_edit and ((native_down and now>=(A.host_check_at or 0)) or native_release)
 if revised or not A.host_state or check_drag then
  A.host_check_at=now+.25
  local state=Track.host_state(v,A.bindings)
  if not A.host_state or not BLT.same(state,A.host_state) then
   Track.finish();UI.cancel_preview();notice('REAPER側でカーブが変更されたため、ドラッグを終了しました。',true)
   for _,binding in pairs(A.bindings) do local env=Track.resolve(v,binding)
    if env then local _,name=R.GetEnvelopeName(env,'');binding.name=name else binding.name='[missing]' end
   end
   UI.sync_curves(true)
  elseif revised then
   if not A.drag then Track.finish();UI.sync_curves() end
  end
  A.revision=R.GetProjectStateChangeCount(v.project)
 end
 if A.wave_retry and now>=A.wave_retry and not A.wave_job and Media.ready() then A.wave_retry=nil;UI.start_wave() end
end
function UI.apply()
 if not UI.available('apply') then notice('エンベロープの割当先を選択してください。');return end
 if not UI.check_current() or not UI.ensure_host() then return end
 Track.automate(A.v,A.bindings,A.layers);UI.sync_curves()
 notice('表示範囲をオートメーションアイテムにまとめました。')
end


function Track.target(project)
 project=project or R.EnumProjects(-1,'')
 local track=R.GetSelectedTrack(project,0)
 local env=R.GetSelectedEnvelope(project)
 if env and R.Envelope_GetParentTrack and (not track or R.GetCursorContext2(true)==2) then
  local parent=R.Envelope_GetParentTrack(env)
  if parent and R.ValidatePtr2(project,parent,'MediaTrack*') then track=parent end
 end
 local first,last=R.GetSet_LoopTimeRange2(project,false,false,0,0,false)
 if not track or not R.ValidatePtr2(project,track,'MediaTrack*') or not finite(first) or not finite(last) or last<=first then return end
 local _,name=R.GetTrackName(track,'')
 return {project=project,track=track,guid=R.GetTrackGUID(track),name=name or '',pos=first,len=last-first}
end
function Track.same(a,b)
 return a and b and a.project==b.project and a.track==b.track and abs(a.pos-b.pos)<1e-9 and abs(a.len-b.len)<1e-9
end
function Track.valid(v)
 return v and R.EnumProjects(-1,'')==v.project and R.ValidatePtr2(v.project,v.track,'MediaTrack*') and R.GetTrackGUID(v.track)==v.guid
end
function Track.finish()
 local g=Track.gesture;Track.gesture=nil
 if g then
  local alive=R.EnumProjects(-1,'')==g.project
  if not alive then for i=0,1023 do local p=R.EnumProjects(i,'');if not p then break end;if p==g.project then alive=true;break end end end
  if not alive then return end
  R.Undo_EndBlock2(g.project,'BLT Envelope Canvas Track: Draw',-1)
  if A.v and A.v.project==g.project then A.revision=R.GetProjectStateChangeCount(g.project) end
 end
end
function Track.wave_sources(v)
 local list,signature={},{}
 for i=0,R.CountTrackMediaItems(v.track)-1 do
  local item=R.GetTrackMediaItem(v.track,i)
  local pos=R.GetMediaItemInfo_Value(item,'D_POSITION');local len=R.GetMediaItemInfo_Value(item,'D_LENGTH')
  if pos<v.pos+v.len and pos+len>v.pos then
   local take=R.GetActiveTake(item)
   if take and not R.TakeIsMIDI(take) then
    local source=R.GetMediaItemTake_Source(take);local channels=source and R.GetMediaSourceNumChannels(source) or 0
    if channels>0 then
     list[#list+1]={item=item,take=take,pos=pos,len=len,channels=min(64,channels)}
     signature[#signature+1]=table.concat({tostring(item),tostring(take),tostring(source),pos,len,
      R.GetMediaItemTakeInfo_Value(take,'D_PLAYRATE'),R.GetMediaItemTakeInfo_Value(take,'D_STARTOFFS'),
      R.GetMediaItemTakeInfo_Value(take,'D_PITCH'),R.GetMediaItemTakeInfo_Value(take,'D_VOL'),
      R.GetMediaItemInfo_Value(item,'D_VOL')},':')
    end
   end
  end
 end
 return list,table.concat(signature,'|')
end
function Track.read(v,bindings,layers)
 local result=Core.new_layers()
 for key,binding in pairs(bindings) do
  local env=Track.resolve(v,binding)
  if not env then error('割当先のエンベロープが見つかりません。再度割り当ててください。',0) end
  local properties=Track.properties(env);local items=Track.items(env)
  local c=result[key];c.enabled=true;c.visible=properties.visible and properties.lane;c.env=env;c.properties=properties;c.items=items;c.segments={}
  local lists={Track.nodes(env,-1,v.pos,v.pos+v.len)}
  for _,a in ipairs(items) do
   if a.pos<=v.pos+v.len and a.pos+a.len>=v.pos then
    lists[#lists+1]=Track.nodes(env,a.ai,max(v.pos,a.pos),min(v.pos+v.len,a.pos+a.len))
   end
  end
  for _,list in ipairs(lists) do
   for i,p in ipairs(list) do
    local owner,count=Track.owner(items,p.time)
    p.visible=p.time>=v.pos and p.time<=v.pos+v.len and (p.ai>=0 or owner<0)
    p.x=(p.time-v.pos)/v.len
    p.y=Track.normalized(properties,Track.evaluate(env,p.time))
    p.amp=1;p.editable=true
    if p.ai>=0 then
     local a=items[p.ai+1];p.amp=a.amp;p.editable=not a.mute and abs(a.amp)>1e-12 and count<=1
     p.visible=p.visible and p.time>=a.pos-1e-9 and p.time<=a.pos+a.len+1e-9
    end
    if p.visible then c.points[#c.points+1]=p end
    if list[i+1] then
     local q=list[i+1]
     c.segments[#c.segments+1]={point=p,first=p.time,last=q.time}
    end
   end
  end
  table.sort(c.points,function(a,b) if a.time==b.time then return a.ai<b.ai end;return a.time<b.time end)
 end
 return result
end
function UI.sync_curves()
 if not Track.valid(A.v) then A.layers=Core.new_layers();A.host_layers=A.layers;UI.dirty();return false end
 local ok,layers=pcall(Track.read,A.v,A.bindings,A.layers)
 if not ok then A.layers=Core.new_layers();A.host_layers=A.layers;notice(layers,true);UI.dirty();return false end
 A.layers=layers;A.host_layers=layers;A.host_state=Track.host_state(A.v,A.bindings)
 A.revision=R.GetProjectStateChangeCount(A.v.project);A.host_check_at=R.time_precise()+.25
 A.hover_node=nil;UI.dirty();return true
end

function Track.content_state(chunk)
 -- Lane layout and focus are not curve edits. Retain every unknown token,
 -- native point, automation instance and pool definition in the guard.
 local lines={}
 for line in chunk:gmatch('[^\r\n]+') do
  local tag=line:match('^%s*([%u_]+)%s')
  if tag~='VIS' and tag~='LANEHEIGHT' then lines[#lines+1]=line end
 end
 return table.concat(lines,'\n')
end
function Track.host_state(v,bindings)
 if not Track.valid(v) then return nil end
 local state={}
 for key,binding in pairs(bindings) do
  local env=Track.resolve(v,binding)
  if env then
   local ok,chunk=R.GetEnvelopeStateChunk(env,'',false)
   if not ok then error('Cannot read envelope state',0) end
   state[key]=Track.content_state(chunk)
  else state[key]=false end
 end
 return state
end
function UI.cancel_preview()
 A.drag=nil;A.number_drag=nil;A.pointer_capture=nil;A.selection=nil;A.hover_node=nil
 A.line_preview=nil;A.hover_segment=nil;A.hover_segment_key=nil;UI.reset_line_preview(true);pressed=nil;down_last=(gfx.mouse_cap&1)~=0
end

function UI.ensure_host()
 if not Track.valid(A.v) or not Track.same(A.v,Track.target()) then return false end
 local current=Track.host_state(A.v,A.bindings)
 if not A.host_state or not BLT.same(current,A.host_state) then
  Track.finish();UI.cancel_preview();UI.sync_curves(true)
  notice('REAPER側でカーブが変更されたため、ドラッグを終了しました。',true)
  return false
 end
 return true
end
function BLT.validTrackSettings(v)
 if type(v)~='table' or type(v.settings)~='table' or v.curves~=nil then return false end
 local schema=UI.settings_schema()
 for path,r in pairs(schema) do
  local x=v.settings[path]
  if r.values then local found=false;for _,a in ipairs(r.values) do if a==x then found=true end end;if not found then return false end
  elseif r.boolean then if type(x)~='boolean' then return false end
  elseif not finite(x) or x<r.min or x>r.max then return false end
 end
 for path in pairs(v.settings) do if not schema[path] then return false end end
 return true
end
function BLT.applyTrackSettings(v)
 UI.number_commit();A.number_drag=nil;A.pointer_capture=nil
 for path,x in pairs(v.settings) do local obj,k=UI.settings_slot(path);obj[k]=x end
 UI.sync_line_targets();UI.reset_line_preview(false);UI.save_settings();UI.dirty(true)
end
function Track.items(env)
 local items={}
 for ai=0,R.CountAutomationItems(env)-1 do
  local function get(k) return R.GetSetAutomationItemInfo(env,ai,k,0,false) end
  items[#items+1]={ai=ai,pos=get('D_POSITION'),len=get('D_LENGTH'),amp=get('D_AMPLITUDE'),mute=get('D_MUTE')~=0}
 end
 return items
end
function Track.owner(items,time)
 local owner=-1;local count=0
 for _,a in ipairs(items) do
  if time>=a.pos-1e-9 and time<=a.pos+a.len+1e-9 then owner=a.ai;count=count+1 end
 end
 return owner,count
end
function Track.evaluate(env,time)
 local _,value=R.Envelope_Evaluate(env,time,0,0)
 if not finite(value) then error('Cannot evaluate envelope',0) end
 return value
end
function Track.nodes(env,ai,first,last)
 local out={};local count=R.CountEnvelopePointsEx(env,ai)
 local lo,hi=0,count
 while lo<hi do
  local mid=floor((lo+hi)/2);local ok,t=R.GetEnvelopePointEx(env,ai,mid)
  if not ok then error('Cannot read envelope point',0) end
  if t<first then lo=mid+1 else hi=mid end
 end
 -- Include the adjacent real points for segments crossing the visible edges.
 for index=max(0,lo-1),count-1 do
  local ok,time,value,shape,tension,selected=R.GetEnvelopePointEx(env,ai,index)
  if not ok then error('Cannot read envelope point',0) end
  out[#out+1]={ai=ai,index=index,time=time,value=value,shape=shape,tension=tension,selected=selected}
  if time>last then break end
  if #out>100000 then error('Too many visible envelope points. Select a shorter time range.',0) end
 end
 return out
end
function UI.native_write(env,fn,hold)
 if not UI.check_current() or not UI.ensure_host() then return false end
 if env~=Track.resolve(A.v,A.bindings[A.layer]) then return false end
 local ok,chunk=R.GetEnvelopeStateChunk(env,'',false)
 if not ok then error('Cannot back up envelope',0) end
 if not Track.gesture then R.Undo_BeginBlock2(A.v.project);Track.gesture={project=A.v.project} end
 R.PreventUIRefresh(1)
 local source_backup
 local captured,capture_err=pcall(function()
  if A.drag and A.drag.mode=='native_transform' and A.drag.source then source_backup=Track.capture_pool(env,A.drag.source.ai) end
 end)
 local success,err
 if captured then success,err=xpcall(fn,debug.traceback) else success,err=false,capture_err end
 if not success then
  local restored,result=pcall(R.SetEnvelopeStateChunk,env,chunk,false)
  if not restored or result==false then err=tostring(err)..' / Envelope restore failed; use REAPER Undo.' end
  if source_backup then
   local ok,why=pcall(Track.restore_pool,env,source_backup)
   if not ok then err=tostring(err)..' / '..tostring(why)..'; use REAPER Undo.' end
  end
 end
 R.PreventUIRefresh(-1);R.UpdateArrange()
 if not hold or not success then Track.finish() end
 UI.sync_curves()
 if not success then UI.cancel_preview();notice(err,true) end
 return success
end
function Track.set(env,p,time,value,shape,tension,selected)
 time=time or p.time;value=value or p.value;shape=shape or p.shape;tension=tension or p.tension
 if selected==nil then selected=p.selected==true end
 local function matches()
  local ok,t,v,s,b,sel=R.GetEnvelopePointEx(env,p.ai,p.index)
  return ok and abs(t-time)<1e-10 and abs(v-value)<1e-10 and s==shape and abs(b-tension)<1e-10 and sel==selected
 end
 -- An unchanged point (e.g. the fixed edge of a resize) is already correct.
 if matches() then return end
 if not R.SetEnvelopePointEx(env,p.ai,p.index,time,value,shape,tension,selected,true) and not matches() then
  error(string.format('Cannot edit envelope point (lane %d, point %d, time %.6f)',p.ai,p.index,time),0)
 end
end
function Track.capture_pool(env,ai)
 local index=ai>=0 and (ai|0x10000000) or -1
 local snapshot={ai=ai,index=index,points={}}
 local count=R.CountEnvelopePointsEx(env,index)
 if count>100000 then error('Too many envelope points for live editing',0) end
 for i=0,count-1 do
  local ok,time,value,shape,tension,selected=R.GetEnvelopePointEx(env,index,i)
  if not ok then error('Cannot capture automation source points',0) end
  snapshot.points[#snapshot.points+1]={time=time,value=value,shape=shape,tension=tension,selected=selected}
 end
 return snapshot
end
function Track.restore_pool(env,snapshot)
 local index=snapshot.index
 -- Full-source indices include trimmed points and count a loop only once.
 for i=R.CountEnvelopePointsEx(env,index)-1,0,-1 do
  if not R.DeleteEnvelopePointEx(env,index,i) then error('Cannot clear automation source points',0) end
 end
 for _,p in ipairs(snapshot.points) do
  if not R.InsertEnvelopePointEx(env,index,p.time,p.value,p.shape,p.tension,p.selected,true) then error('Cannot restore automation source points',0) end
 end
 R.Envelope_SortPointsEx(env,index)
 if R.CountEnvelopePointsEx(env,index)~=#snapshot.points then error('Automation source point count mismatch',0) end
end
function Track.rebind_points(env,points)
 local lanes={};local bound={}
 for _,p in ipairs(points) do
  local lane=lanes[p.ai]
  if not lane then
   lane={};lanes[p.ai]=lane
   local count=R.CountEnvelopePointsEx(env,p.ai)
   if count>100000 then error('Too many envelope points to restore a drag',0) end
   for i=0,count-1 do
    local ok,time,value,shape,tension,selected=R.GetEnvelopePointEx(env,p.ai,i)
    if ok then lane[#lane+1]={ai=p.ai,index=i,time=time,value=value,shape=shape,tension=tension,selected=selected} end
   end
  end
  local found
  -- Binary search by time; no quadratic scan of a large envelope.
  local lo,hi=1,#lane+1
  while lo<hi do local mid=floor((lo+hi)/2);if lane[mid].time<p.time-1e-7 then lo=mid+1 else hi=mid end end
  for i=lo,#lane do
   local q=lane[i];if q.time>p.time+1e-7 then break end
   if not q.used and abs(q.value-p.value)<1e-7 and q.shape==p.shape and abs(q.tension-p.tension)<1e-7 then found=q;break end
  end
  if not found then error(string.format('Cannot restore envelope point (lane %d, time %.6f)',p.ai,p.time),0) end
  found.used=true;bound[p]=found
 end
 return bound
end
function UI.select_native(index,toggle,box)
 local c=A.layers[A.layer];if not c.env then return end
 local region
 if box then
  local time=A.v.pos+clamp(((box.anchor or box.x)-UI.graph.x)/UI.graph.w,0,1)*A.v.len
  region=UI.region(c,time)
 elseif index then region=UI.region(c,c.points[index].time,c.points[index].ai) end
 if (box or index) and not region then notice('重なった範囲は先にオートメーション化でまとめてください。',true);return false end
 return UI.native_write(c.env,function()
  for i,p in ipairs(c.points) do
   local selected
   if box then local x,y=UI.point_position(p);selected=x>=box.x and x<=box.r and y>=box.y and y<=box.b
   elseif toggle then selected=i==index and not p.selected or i~=index and p.selected
   else selected=i==index end
   selected=selected and UI.in_region(p,region) or false
   if selected~=p.selected then Track.set(c.env,p,nil,nil,nil,nil,selected) end
  end
 end,false)
end

function UI.shape_menu(index)
 local c=A.layers[A.layer];if not c.env then return end
 if index and not c.points[index].selected then UI.select_native(index,false);c=A.layers[A.layer] end
 local names=Language.code=='JP' and {'線形','矩形','緩やかな開始／終了','速い開始','速い終了','Bezier','|選択ポイントを削除'} or {'Linear','Square','Slow start/end','Fast start','Fast end','Bezier','|Delete selected points'}
 gfx.x=gfx.mouse_x;gfx.y=gfx.mouse_y;local choice=gfx.showmenu(table.concat(names,'|'))
 if choice==7 then UI.delete_selected();return end
 if choice<1 or choice>6 then return end
 UI.native_write(c.env,function()
  for _,p in ipairs(c.points) do if p.selected then Track.set(c.env,p,nil,nil,choice-1,p.tension,nil) end end
 end,false)
end
function Track.union_range(env,first,last)
 local items=Track.items(env);local changed=true
 while changed do
  changed=false
  for _,a in ipairs(items) do if a.pos<last-1e-9 and a.pos+a.len>first+1e-9 then
   local l,r=min(first,a.pos),max(last,a.pos+a.len)
   if l<first or r>last then first,last=l,r;changed=true end
  end end
 end
 return first,last,items
end
function Track.all_envelopes(project)
 local envs={}
 for i=-1,R.CountTracks(project)-1 do
  local track=i<0 and R.GetMasterTrack(project) or R.GetTrack(project,i)
  for j=0,R.CountTrackEnvelopes(track)-1 do envs[#envs+1]=R.GetTrackEnvelope(track,j) end
 end
 return envs
end
function Track.select_automation_range(p)
 local count=0
 for ai=0,R.CountAutomationItems(p.env)-1 do
  local pos=R.GetSetAutomationItemInfo(p.env,ai,'D_POSITION',0,false)
  local len=R.GetSetAutomationItemInfo(p.env,ai,'D_LENGTH',0,false)
  local include=pos<p.last-1e-9 and pos+len>p.first+1e-9
  R.GetSetAutomationItemInfo(p.env,ai,'D_UISEL',include and 1 or 0,true)
  if include then count=count+1 end
 end
 return count
end
function Track.automation_covers(p)
 local count=0
 for ai=0,R.CountAutomationItems(p.env)-1 do
  local pos=R.GetSetAutomationItemInfo(p.env,ai,'D_POSITION',0,false)
  local len=R.GetSetAutomationItemInfo(p.env,ai,'D_LENGTH',0,false)
  if pos<p.last-1e-9 and pos+len>p.first+1e-9 then
   if abs(pos-p.first)>1e-7 or abs(pos+len-p.last)>1e-7 then return false end
   count=count+1
  end
 end
 return count==1
end
function Track.native_automation_action(env,command,project)
 local parent=R.Envelope_GetParentTrack(env)
 if not parent or not R.ValidatePtr2(project,parent,'MediaTrack*') then error('Automation parent track missing',0) end
 local tracks={}
 for i=-1,R.CountTracks(project)-1 do
  local track=i<0 and R.GetMasterTrack(project) or R.GetTrack(project,i)
  tracks[#tracks+1]={track=track,selected=R.IsTrackSelected(track)}
 end
 local previous=R.GetSelectedEnvelope(project);local context=R.GetCursorContext2(true)
 local properties=Track.properties(env)
 local function visibility(visible,lane)
  local br=R.BR_EnvAlloc(env,false);if not br then error('Envelope properties unavailable',0) end
  local ok,err=pcall(R.BR_EnvSetProperties,br,properties.active,visible,properties.armed,lane,properties.height,properties.shape,properties.fader,properties.options)
  R.BR_EnvFree(br,ok);if not ok then error(err,0) end
 end
 local revealed=not properties.visible or not properties.lane
 local ok,err=xpcall(function()
  for _,entry in ipairs(tracks) do R.SetTrackSelected(entry.track,entry.track==parent) end
  if revealed then visibility(true,true);R.TrackList_AdjustWindows(false) end
  R.SetCursorContext(2,env)
  R.Main_OnCommandEx(command,0,project)
 end,debug.traceback)
 -- Restore UI context on success and on any native command failure.
 local function cleanup(fn,...)
  local good,why=pcall(fn,...)
  if not good then ok=false;err=tostring(err or '')..' / '..tostring(why) end
 end
 if revealed then cleanup(visibility,properties.visible,properties.lane);cleanup(R.TrackList_AdjustWindows,false) end
 for _,entry in ipairs(tracks) do cleanup(R.SetTrackSelected,entry.track,entry.selected) end
 if previous and R.ValidatePtr2(project,previous,'TrackEnvelope*') then cleanup(R.SetCursorContext,2,previous)
 else cleanup(R.SetCursorContext,context==0 and 0 or 1,nil) end
 if not ok then error(err,0) end
end
function Track.recollect_automation(p,project)
 -- Rebuild from the original envelope, never from an incomplete glue result.
 if not R.SetEnvelopeStateChunk(p.env,p.chunk,false) then error('Cannot restore envelope before consolidation',0) end
 local count=Track.select_automation_range(p)
 if count>0 then
  Track.native_automation_action(p.env,42088,project) -- Delete automation items, preserve points.
  if Track.select_automation_range(p)~=0 then error('Cannot preserve automation points for consolidation',0) end
 end
 local ai=R.InsertAutomationItem(p.env,-1,p.first,p.last-p.first)
 if not ai or ai<0 then error('Cannot collect automation points',0) end
 if not Track.automation_covers(p) then error('Cannot create automation item for the requested range',0) end
end
function Track.automate(v,bindings,layers)
 if not Track.valid(v) then error('対象トラックまたは時間範囲が変わりました。',0) end
 local plans={}
 for _,d in ipairs(UI.defs) do if bindings[d.key] then
  local env=Track.resolve(v,bindings[d.key]);if not env then error('Envelope missing',0) end
  local first,last,items=Track.union_range(env,v.pos,v.pos+v.len)
  local ok,chunk=R.GetEnvelopeStateChunk(env,'',false);if not ok then error('Cannot back up envelope',0) end
  plans[#plans+1]={env=env,first=first,last=last,items=items,chunk=chunk}
 end end
 if #plans==0 then error('エンベロープの割当先を選択してください。',0) end
 local selections={};local previous=R.GetSelectedEnvelope(v.project)
 for _,env in ipairs(Track.all_envelopes(v.project)) do
  for ai=0,R.CountAutomationItems(env)-1 do
   selections[#selections+1]={env=env,ai=ai,value=R.GetSetAutomationItemInfo(env,ai,'D_UISEL',0,false),
    pos=R.GetSetAutomationItemInfo(env,ai,'D_POSITION',0,false),len=R.GetSetAutomationItemInfo(env,ai,'D_LENGTH',0,false),
    pool=R.GetSetAutomationItemInfo(env,ai,'D_POOL_ID',0,false)}
  end
 end
 local touched={};Track.finish();R.Undo_BeginBlock2(v.project);R.PreventUIRefresh(1)
 local ok,err=xpcall(function()
  for _,s in ipairs(selections) do R.GetSetAutomationItemInfo(s.env,s.ai,'D_UISEL',0,true) end
  for _,p in ipairs(plans) do
   touched[p.env]=p
   table.sort(p.items,function(a,b)return a.pos<b.pos end)
   local cursor=p.first;local gaps={}
   for _,a in ipairs(p.items) do if a.pos<p.last and a.pos+a.len>p.first then
    if a.pos>cursor+1e-9 then gaps[#gaps+1]={cursor,a.pos} end
    cursor=max(cursor,a.pos+a.len)
   end end
   if cursor<p.last-1e-9 then gaps[#gaps+1]={cursor,p.last} end
   for _,gap in ipairs(gaps) do
    -- Negative pool ID asks REAPER to collect the existing underlying points.
    local ai=R.InsertAutomationItem(p.env,-1,gap[1],gap[2]-gap[1])
    if not ai or ai<0 then error('Cannot create automation item',0) end
   end
   local selected=Track.select_automation_range(p)
   if selected>1 then Track.native_automation_action(p.env,42089,v.project) end
   if not Track.automation_covers(p) then Track.recollect_automation(p,v.project) end
   for ai=0,R.CountAutomationItems(p.env)-1 do R.GetSetAutomationItemInfo(p.env,ai,'D_UISEL',0,true) end
  end
 end,debug.traceback)
 if not ok then for _,p in ipairs(plans) do if touched[p.env] then
  local restored,result=pcall(R.SetEnvelopeStateChunk,p.env,p.chunk,false)
  if not restored or result==false then err=tostring(err)..' / Envelope restore failed; use REAPER Undo.' end
 end end end
 -- Unrelated envelope selections and focus are restored even after failure.
 for _,s in ipairs(selections) do
  local p=touched[s.env]
  if not p then R.GetSetAutomationItemInfo(s.env,s.ai,'D_UISEL',s.value,true)
  elseif ok and (s.pos+s.len<=p.first or s.pos>=p.last) then
   for ai=0,R.CountAutomationItems(s.env)-1 do
    if R.GetSetAutomationItemInfo(s.env,ai,'D_POOL_ID',0,false)==s.pool
     and abs(R.GetSetAutomationItemInfo(s.env,ai,'D_POSITION',0,false)-s.pos)<1e-9
     and abs(R.GetSetAutomationItemInfo(s.env,ai,'D_LENGTH',0,false)-s.len)<1e-9 then
      R.GetSetAutomationItemInfo(s.env,ai,'D_UISEL',s.value,true);break
    end
   end
  end
 end
 if previous and R.ValidatePtr2(v.project,previous,'TrackEnvelope*') then R.SetCursorContext(2,previous) else R.SetCursorContext(1,nil) end
 R.PreventUIRefresh(-1);R.Undo_EndBlock2(v.project,'BLT Envelope Canvas Track: Automation items',-1);R.UpdateArrange()
 if not ok then error(err,0) end
 return #plans
end
function UI.segment_at(cached)
 local c=A.layers[A.layer];if not c.env then return end
 local g=UI.graph;local time=A.v.pos+clamp((mouse_x-g.x)/g.w,0,1)*A.v.len
 local value
 if cached then
  local trace=c.trace;if not trace or #trace<2 then return end
  local u=(time-A.v.pos)/A.v.len;local lo,hi=1,#trace
  while hi-lo>1 do local mid=floor((lo+hi)/2);if trace[mid].x<=u then lo=mid else hi=mid end end
  local a,b=trace[lo],trace[hi]
  value=a.y+(b.y-a.y)*clamp((u-a.x)/max(1e-20,b.x-a.x),0,1)
 else value=Track.normalized(c.properties,Track.evaluate(c.env,time)) end
 local y=g.y+(1-value)*g.h/2
 if abs(mouse_y-y)*scale>10 then return end
 local owner,count=Track.owner(c.items,time);if count>1 then return end
 for _,segment in ipairs(c.segments) do
  if segment.point.ai==owner and time>=segment.first and time<segment.last and segment.point.editable then return segment.point,segment end
 end
end
function UI.begin_nodes(index)
 local c=A.layers[A.layer];local p=c.points[index]
 if not p.editable then notice('重なったオートメーションは先にまとめてください。',true);return end
 if not p.selected and not UI.select_native(index,false) then return end
 local box=UI.selection_bounds();if box then UI.begin_transform('',box) end
end
function UI.drag_native(release)
 local d=A.drag;if not d or d.mode=='marquee' then return end
 local now=R.time_precise();if not release and now<(d.next or 0) then return end
 local dx,dy=mouse_x-d.mx,mouse_y-d.my
 if dx==d.lastx and dy==d.lasty then return end
 if not d.lastx and dx*dx+dy*dy<4/(scale*scale) then return end
 d.lastx,d.lasty=dx,dy;d.next=now+1/30
 UI.native_write(d.env,function()
  if d.mode=='native_tension' then
   Track.set(d.env,d.point,nil,nil,5,clamp(d.tension-dy/150,-1,1),nil)
  else
   local dt=clamp(dx/UI.graph.w*A.v.len,d.dtmin,d.dtmax)
   local delta=-dy/UI.graph.h*2;local sorted={}
   for _,p in ipairs(d.points) do
    local value=Track.raw(d.properties,clamp(p.y+delta,-1,1))
    if abs(dy)<1e-12 then value=p.value end
    Track.set(d.env,p,p.time+dt,value,nil,nil,nil);sorted[p.ai]=true
   end
   for ai in pairs(sorted) do R.Envelope_SortPointsEx(d.env,ai) end
  end
 end,not release)
end
function Core.limit_points(points,limit)
 if not limit or #points<=limit then return points,false end
 limit=max(2,floor(limit));local keep={[1]=true,[#points]=true};local heap={}
 local function push(a,b)
  if b-a<2 then return end
  local worst,idx=-1,a+1;local p,q=points[a],points[b]
  for i=a+1,b-1 do local r=points[i];local f=(r.x-p.x)/max(1e-20,q.x-p.x)
   local e=abs(r.y-(p.y+(q.y-p.y)*f));if e>worst then worst,idx=e,i end
  end
  local entry={a=a,b=b,i=idx,e=worst};local n=#heap+1
  while n>1 and heap[floor(n/2)].e<entry.e do heap[n]=heap[floor(n/2)];n=floor(n/2) end;heap[n]=entry
 end
 local function pop()
  local top=heap[1];local last=table.remove(heap)
  if #heap>0 then local n=1
   while n*2<=#heap do local c=n*2;if c<#heap and heap[c+1].e>heap[c].e then c=c+1 end
    if heap[c].e<=last.e then break end;heap[n]=heap[c];n=c
   end;heap[n]=last
  end;return top
 end
 push(1,#points)
 for _=3,limit do if #heap==0 then break end;local p=pop();keep[p.i]=true;push(p.a,p.i);push(p.i,p.b) end
 local out={};for i,p in ipairs(points) do if keep[i] then out[#out+1]=p end end
 return out,true
end
function Core.simplify(c,tolerance)
 local pts=c.points;if #pts<3 then return end
 local keep={[1]=true,[#pts]=true};local stack={{1,#pts}}
 while #stack>0 do
  local pair=table.remove(stack);local a,b=pair[1],pair[2];local worst,index=0,nil
  for i=a+1,b-1 do
   local u=(pts[i].x-pts[a].x)/max(1e-12,pts[b].x-pts[a].x)
   local e=abs(pts[i].y-(pts[a].y+(pts[b].y-pts[a].y)*u))
   if e>worst then worst,index=e,i end
  end
  if index and worst>tolerance then keep[index]=true;stack[#stack+1]={a,index};stack[#stack+1]={index,b} end
 end
 local out={};for i,p in ipairs(pts) do if keep[i] then out[#out+1]=p end end;c.points=out
end
function Core.compact_pattern(points)
 local c={points=points};Core.simplify(c,.0015);return c.points
end
function Core.pattern(kind,cycles,height,envelope,random_levels,tempo)
 if tempo and tempo~=1 then
  local points=Core.pattern(kind,cycles,height,1,random_levels)
  for _,p in ipairs(points) do
   local phase=p.x
   -- Invert integrated speed: 0.5 -> 1.5 (or 1.5 -> 0.5), mean 1.
   local x=tempo==2 and 2*phase/(.5+math.sqrt(.25+2*phase)) or 2*phase/(1.5+math.sqrt(2.25-2*phase))
   p.x=x;p.y=p.y*(envelope==2 and x or envelope==3 and 1-x or 1)
  end
  return points
 end
 if kind=='random_step' then
  local count=max(1,ceil(cycles-1e-12));local levels={}
  for i=1,count do
   local v=random_levels and random_levels[i]
   levels[i]=finite(v) and clamp(v,-1,1) or math.random()*2-1
  end
  local function value(i)
   local a=(i-1)/cycles;local b=min(i/cycles,1);local center=(a+b)/2
   local gain=envelope==2 and center or envelope==3 and 1-center or 1
   return levels[i]*height*gain
  end
  local out={{x=0,y=value(1)}}
  for i=1,count-1 do
   local x=i/cycles
   if x<1 then
    out[#out+1]={x=max(0,x-min(1e-5,.01/cycles)),y=value(i)}
    out[#out+1]={x=x,y=value(i+1)}
   end
  end
  out[#out+1]={x=1,y=value(count)}
  return Core.compact_pattern(out)
 end
 if kind=='horizontal' then return {{x=0,y=0},{x=1,y=0}} end
 -- Piecewise-linear waves need only extrema or the two sides of a jump.
 if kind=='triangle' or kind=='saw' or kind=='square' then
  local xs={0,1}
  if kind=='triangle' then
   for i=0,ceil(cycles*2) do local x=(.25+i*.5)/cycles;if x>0 and x<1 then xs[#xs+1]=x end end
  elseif kind=='square' then
   for i=1,floor(cycles*2) do local x=i/(cycles*2)
    if x<=1 then xs[#xs+1]=max(0,x-min(1e-5,.01/cycles));xs[#xs+1]=x end
   end
  else
   for i=0,ceil(cycles) do local x=(.5+i)/cycles
    if x>0 and x<=1 then xs[#xs+1]=max(0,x-min(1e-5,.01/cycles));xs[#xs+1]=x end
   end
  end
  table.sort(xs)
  local function value(x)
   local phase=(x*cycles+(kind=='saw' and .5 or kind=='triangle' and .25 or 0)+1e-12)%1
   local y=kind=='saw' and 2*phase-1 or kind=='square' and (phase<.5 and 1 or -1) or 1-4*abs(phase-.5)
   return y*height*(envelope==2 and x or envelope==3 and 1-x or 1)
  end
  -- Scale only the defining corners: envelope modes change vertex heights,
  -- never tessellate the spans between them into extra control points.
  local out={}
  for _,x in ipairs(xs) do
   if #out==0 or x-out[#out].x>1e-10 then out[#out+1]={x=x,y=value(x)} end
  end
  if #out>Core.GENERATED_MAX_POINTS then out=Core.limit_points(out,Core.GENERATED_MAX_POINTS) end
  return Core.compact_pattern(out)
 end
 local xs={};local n=min(768,max(1,ceil(cycles*48)))
 for i=0,n do xs[#xs+1]=i/n end
 if kind=='saw' or kind=='square' then
  local edges=cycles*(kind=='square' and 2 or 1);local total=floor(edges+(kind=='saw' and .5 or 0));local count=min(120,total)
  for j=1,count do local i=ceil(j*total/count);local x=(i-(kind=='saw' and .5 or 0))/edges
   if x<=1 then xs[#xs+1]=max(0,x-min(1e-5,.01/edges));xs[#xs+1]=x end
  end
 end
 table.sort(xs);local points={}
 for _,x in ipairs(xs) do
  if #points==0 or x-points[#points].x>1e-10 then
  local phase=(x*cycles+(kind=='saw' and .5 or kind=='triangle' and .25 or 0))%1;local y
  if kind=='sine' then y=math.sin(x*cycles*2*math.pi)
  elseif kind=='saw' then y=2*phase-1
  elseif kind=='square' then y=phase<.5 and 1 or -1
  elseif kind=='triangle' then y=1-4*abs(phase-.5)
  else y=math.random()*2-1 end
  local gain=envelope==2 and x or envelope==3 and 1-x or 1
  points[#points+1]={x=x,y=y*height*gain}
 end end;return Core.compact_pattern(points)
end
function Core.chaos(limit)
 local n=math.random(8,min(128,limit));local exponent=.2+math.random()*4;local center=math.random()
 local pts={{x=0,y=math.random()*2-1},{x=1,y=math.random()*2-1}}
 for _=3,n do local x
  if math.random()<.55 then x=clamp(center+(math.random()-.5)*math.random(),.00001,.99999) else x=math.random()^exponent end
  pts[#pts+1]={x=clamp(x,.00001,.99999),y=(math.random()*2-1)*(math.random()<.3 and .15 or 1)}
 end
 table.sort(pts,function(a,b)return a.x<b.x end)
 for i=#pts,2,-1 do if pts[i].x-pts[i-1].x<1e-6 then table.remove(pts,i-1) end end
 return pts
end
function UI.reset_line_preview(reset_random)
 UI.preview_key=nil;UI.preview_points=nil;UI.preview_ua=nil;UI.preview_ub=nil
 if reset_random then UI.random_step_state=nil end
end
function UI.random_step_levels(slot)
 local target=tostring(A.v and (A.v.guid..':'..A.v.pos..':'..A.v.len))
 local state=UI.random_step_state
 if not state or state.target~=target then state={target=target};UI.random_step_state=state end
 local levels=state[slot]
 if not levels then levels={};state[slot]=levels end
 local count=min(1024,max(1,ceil(UI.period_span()/min(A.width_start,A.width_end)-1e-12)))
 for i=#levels+1,count do levels[i]=math.random()*2-1 end
 return levels
end
function UI.next_pattern()
 A.pattern=A.pattern%#UI.pattern_names+1
 UI.reset_line_preview(true);UI.dirty()
end
function UI.line_anchor()
 local g=UI.graph;local x,y=mouse_x,mouse_y
 for _,px in ipairs({g.x,g.x+g.w}) do if abs(x-px)*scale<=9 then x=px end end
 for _,py in ipairs({g.y,g.y+g.h/2,g.y+g.h}) do if abs(y-py)*scale<=9 then y=py end end
 return clamp(x,g.x,g.x+g.w),clamp(y,g.y,g.y+g.h)
end
function UI.screen_to_point(x,y)
 local g=UI.graph;local u=A.view+(x-g.x)/g.w*A.span
 return {x=u,y=UI.from_axis(A.layer,1-2*(y-g.y)/g.h)}
end
function UI.transition(first,last,duration,curve,elapsed)
 local u=clamp(elapsed/duration,0,1)
 if curve~=0 then
  local k=abs(curve)*.2
  u=curve>0 and math.log(1+k*u)/math.log(1+k) or 1-math.log(1+k*(1-u))/math.log(1+k)
 end
 return first+(last-first)*u
end
function UI.rate_phase(domain,origin,edge)
 local span=abs(edge-origin)
 local minimum=max(.001,span/512)
 local function rate(t)
  return 1/max(minimum,UI.transition(A.width_start,A.width_end,A.width_duration,A.width_curve,t))
 end
 local map={{u=0,phase=0}};local total=0
 if span<1e-20 then return {{u=0,phase=0},{u=1,phase=0}},0 end
 local transition=min(span,A.width_duration)
 if A.width_start==A.width_end then transition=0 end
 -- Dense only during the transition; a constant tail needs one interval.
 local steps=transition>0 and 512 or 0
 local function integrate(a,b,fa,fm,fb,whole,depth)
  local middle=(a+b)/2;local fl=rate((a+middle)/2);local fr=rate((middle+b)/2)
  local left=(middle-a)*(fa+4*fl+fm)/6;local right=(b-middle)*(fm+4*fr+fb)/6
  if depth<12 and abs(left+right-whole)>1e-9+abs(left+right)*1e-6 then
   integrate(a,middle,fa,fl,fm,left,depth+1);integrate(middle,b,fm,fr,fb,right,depth+1)
  else total=total+left+right;map[#map+1]={u=b/span,phase=total} end
 end
 for i=1,steps do
  local a=transition*(i-1)/steps;local b=transition*i/steps
  local fa,fm,fb=rate(a),rate((a+b)/2),rate(b)
  integrate(a,b,fa,fm,fb,(b-a)*(fa+4*fm+fb)/6,0)
 end
 if transition<span then
  total=total+(span-transition)*rate(span)
  map[#map+1]={u=1,phase=total}
 end
 return map,min(512,total)
end
function UI.phase_position(map,phase)
 local lo,hi=1,#map
 while hi-lo>1 do local mid=floor((lo+hi)/2);if map[mid].phase<phase then lo=mid else hi=mid end end
 local a,b=map[lo],map[hi]
 return a.u+(b.u-a.u)*clamp((phase-a.phase)/max(1e-20,b.phase-a.phase),0,1)
end
function UI.height_gain(elapsed)
 return UI.transition(A.height_start,A.height_end,A.height_duration,A.height_curve,elapsed)/100
end
function UI.phase_at(map,u)
 local lo,hi=1,#map
 while hi-lo>1 do local mid=floor((lo+hi)/2);if map[mid].u<u then lo=mid else hi=mid end end
 local a,b=map[lo],map[hi]
 return a.phase+(b.phase-a.phase)*clamp((u-a.u)/max(1e-20,b.u-a.u),0,1)
end
function UI.line_points()
 UI.sync_line_targets()
 local g=UI.graph;local x,y=UI.line_anchor();local c=A.layers[A.layer]
 local invert=(gfx.mouse_cap&16)~=0 and -1 or 1
 local domain=UI.period_domain()
 local coord=UI.period_coordinate(domain,A.v.pos+(x-g.x)/g.w*A.v.len)
 local cachekey=table.concat({A.period_unit,domain.mode,domain.qn or 0,domain.swing or 0,R.GetProjectStateChangeCount(A.v.project),x,y,A.pattern,A.width_start,A.width_end,A.width_duration,A.width_curve,A.height_start,A.height_end,A.height_duration,A.height_curve,A.direction,A.layer,A.view,A.span,invert,tostring(A.v and (A.v.guid..':'..A.v.pos..':'..A.v.len)),tostring(A.record)},':')
 if UI.preview_key==cachekey then return UI.preview_points,UI.preview_ua,UI.preview_ub end
 local full_left=g.x-A.view/A.span*g.w
 local full_right=g.x+(1-A.view)/A.span*g.w
 local left=A.direction==3 and x or full_left;local right=A.direction==1 and x or full_right
 if right-left<1e-7 then return {},0,0 end
 local out={}
 local joined=A.direction==2 and x>full_left+1e-7 and x<full_right-1e-7
 local omit_origin=joined and (A.pattern==2 or A.pattern==4 or (A.pattern==3 and A.height_start==0))
 local origin_jump=joined and ((A.pattern==3 and not omit_origin) or A.pattern==6)
 local single_jump=(A.pattern==3 or A.pattern==6) and A.direction~=2
 if single_jump then out[#out+1]=UI.screen_to_point(x,y) end
 local function side(edge,sign,skip_origin,slot)
  local width=abs(edge-x);if width<1e-7 then return end
  local edge_coord=UI.period_coordinate(domain,A.v.pos+(edge-g.x)/g.w*A.v.len)
  local phase_map,cycles=UI.rate_phase(domain,coord,edge_coord)
  cycles=min(512,cycles)
  local levels=A.pattern==6 and UI.random_step_levels(slot) or nil
  local pts=Core.pattern(UI.pattern_kinds[A.pattern],cycles,1,1,levels,1)
  if A.height_start~=A.height_end or (A.width_start~=A.width_end and A.pattern~=3 and A.pattern~=6 and A.pattern~=5) then
   local original=pts;pts=Core.copy(original)
   local duration=max(A.height_start~=A.height_end and A.height_duration or 0,A.width_start~=A.width_end and A.width_duration or 0)
   local extent=min(1,duration/max(1e-20,abs(edge_coord-coord)))
   for i=1,128 do
    local phase=UI.phase_at(phase_map,extent*i/128)/max(cycles,1e-20)
    local duplicate=false
    for _,p in ipairs(original) do if abs(p.x-phase)<1e-10 then duplicate=true;break end end
    if not duplicate then pts[#pts+1]={x=phase,y=UI.generated_value(original,phase)} end
   end
   table.sort(pts,function(a,b)return a.x<b.x end)
  end
  for _,p in ipairs(pts) do if not (skip_origin and p.x==0) and not (single_jump and p.x==0 and abs(p.y)<1e-10) then
   local u=UI.phase_position(phase_map,p.x*cycles)
   -- Preserve both sides of a central step. A left endpoint
   -- at exactly the same x would otherwise be discarded by clean_points.
   if u==0 and ((origin_jump and edge<x) or single_jump) then u=min(1e-5,.01/cycles) end
   local time=UI.period_time(domain,coord+(edge_coord-coord)*u)
   local q=UI.screen_to_point(g.x+(time-A.v.pos)/A.v.len*g.w,y-p.y*UI.height_gain(abs(edge_coord-coord)*u)*sign*invert*g.h/2)
   q.y=clamp(q.y,c.min_y,c.max_y);out[#out+1]=q
  end end
 end
 if A.direction~=3 then side(left,A.direction==2 and -1 or 1,omit_origin or (joined and not origin_jump),'left') end
 if A.direction~=1 then side(right,1,omit_origin,'right') end
 local ua=UI.screen_to_point(left,y).x;local ub=UI.screen_to_point(right,y).x
 -- Remove collinear nodes introduced by clipping or envelope endpoints.
 local generated={points=UI.clean_points(out)}
 if (A.pattern==3 or A.pattern==6) and A.height_start==A.height_end then
  -- Native square segments hold their value up to the next transition.
  -- Remove the redundant point just before each jump, retaining range endpoints.
  local compact={}
  for i,p in ipairs(generated.points) do
   if #compact==0 or abs(p.y-compact[#compact].y)>1e-10 or i==#generated.points then
    p.shape=1;compact[#compact+1]=p
   end
  end
  generated.points=compact
 else
  -- At most 0.025% of the full envelope range, independent of window size.
  Core.simplify(generated,.0005)
 end
 UI.preview_key=cachekey;UI.preview_points=generated.points;UI.preview_ua=ua;UI.preview_ub=ub
 return UI.preview_points,ua,ub
end
function UI.sync_line_targets()
 for _,group in ipairs({'width','height'}) do
  if A[group..'_variable']==false then A[group..'_end']=A[group..'_start'] end
 end
end
function UI.number_enabled(key)
 local group,field=key:match('^(%a+)_(%a+)$')
 return field=='start' or A[group..'_variable']~=false
end
function UI.toggle_variable(group)
 if A.busy or A.tool~='line' then return end
 UI.number_commit();A.number_drag=nil;A.pointer_capture=nil
 A[group..'_variable']=not A[group..'_variable']
 UI.sync_line_targets();UI.reset_line_preview(false);UI.dirty()
end
function UI.variable_checkbox(group,x,y,tone)
 local on=A[group..'_variable']~=false;local enabled=not A.busy and A.tool=='line'
 local c=enabled and tone or C.muted
 local cy=y+10;local top=cy-6.5;local bottom=cy+6.5
 rect(x,top,13,13,C.field,1)
 line(x,top,x+13,top,c,.7);line(x,bottom,x+13,bottom,c,.7)
 line(x,top,x,bottom,c,.7);line(x+13,top,x+13,bottom,c,.7)
 if on then line(x+3,cy-.5,x+6,cy+2.5,c,1);line(x+6,cy+2.5,x+10,cy-3.5,c,1) end
 label(Language.code=='JP' and (on and '可変' or '一定') or (on and 'Vary' or 'Fixed'),x+19,y,12,c,1,53,20,4)
 register('variable_'..group,x,y,72,20,function() UI.toggle_variable(group) end,
  Language.code=='JP' and 'チェックON：可変 / OFF：一定（変動先を開始にリンク）' or 'Checked: variable / unchecked: fixed (target follows start)',enabled)
end
function UI.number_text(key,value)
 local digits=UI.number_limits[key][4] or 0
 local text=string.format('%.'..digits..'f',value)
 return digits>0 and text:gsub('0+$',''):gsub('%.$','') or text
end
function UI.number_set(key,raw,flash)
 local spec=UI.number_limits[key];local n=tonumber(raw)
 local invalid=not finite(n)
 if invalid then n=A[key] end
 local factor=10^(spec[4] or 0)
 local v=clamp(n,spec[1],spec[2]);v=floor(v*factor+.5)/factor
 if flash~=false and (invalid or abs(v-n)>1e-8) then
  A.number_flash=A.number_flash or {};A.number_flash[key]=R.time_precise();A.number_flash_until=R.time_precise()+1.35
 end
 A[key]=v;UI.sync_line_targets();UI.dirty()
end
function UI.number_commit()
 if not A.number_edit then return end
 local e=A.number_edit;A.number_edit=nil;if UI.number_enabled(e.key) then UI.number_set(e.key,e.text) end
end
function UI.number_field(key,title,x,y,w,unit)
 local e=A.number_edit;local active=e and e.key==key;local dim=A.tool~='line' or not UI.number_enabled(key)
 gradient(x,y,w,28,dim and UI.theme_color({.12,.12,.13},'field') or C.field,dim and UI.theme_color({.085,.085,.095},'panel') or C.panel,.98,.60)
 local hot=A.hit=='number_'..key
 line(x,y,x,y+28,dim and C.muted or UI.def().color,hot and .8 or .35);finish_corners(x,y,w,28,5,false,C.edge2,hot and .65 or .3)
 label(title,x+6,y+5,12,C.muted,1,60,20,0,false)
 if active and e.selected then rect(x+65,y+3,w-83,22,C.focus2,.8) end
 local value=active and e.text or UI.number_text(key,A[key])
 local value_size=min(15,max(9,15*(w-88)/max(1,measure(value,15,3,true))))
 right_label(value,x+w-24,y+5,value_size,active and e.selected and C.ink or dim and C.muted or C.text,3,true)
 right_label(unit,x+w-4,y+9,10,C.muted,1,false)
 local hint=key:match('_duration$') and (Language.code=='JP' and '開始から変動先までの時間。大きいほどゆっくり変化' or 'Time to target; larger values change more slowly') or key:match('_curve$') and (Language.code=='JP' and '0：直線 / ＋：先に変化 / −：後で変化' or '0: linear / +: early change / -: late change') or ''
 register('number_'..key,x,y,w,28,function() end,hint,not A.busy and A.tool=='line' and UI.number_enabled(key))
end
function UI.number_input(id,down,wheel)
 local key=A.tool=='line' and id and id:match('^number_(.+)$')
 local g=UI.graph
 if wheel~=0 and A.tool=='line' and A.v and not A.drag and not down and inside(g.x,g.y,g.w,g.h) then
  key=(gfx.mouse_cap&4)~=0 and 'height_start' or 'width_start'
 end
 if key and wheel~=0 and not UI.number_enabled(key) then gfx.mouse_wheel=0;return true end
 if key and not UI.number_enabled(key) then key=nil end
 if key and wheel~=0 and not A.busy then
  UI.number_commit();local step=UI.number_limits[key][3]*((gfx.mouse_cap&8)~=0 and .1 or 1)
  local notches=max(1,floor(abs(wheel)/120+.5))
  UI.number_set(key,A[key]+(wheel>0 and 1 or -1)*notches*step);gfx.mouse_wheel=0;return true
 end
 if down and not down_last then
  if A.number_edit then UI.number_commit() end
  if key and not A.busy then A.number_drag={key=key,y=mouse_y,value=A[key]};A.pointer_capture=true end
 end
 local d=A.number_drag
 if not d then return false end
 if not UI.number_enabled(d.key) then A.number_drag=nil;A.pointer_capture=nil;return true end
 if down then
  local dy=(d.y-mouse_y)*scale
  if abs(dy)>=3 or d.moved then
   d.moved=true
   local step=UI.number_limits[d.key][3]*((gfx.mouse_cap&8)~=0 and .1 or 1)
   local ticks=dy/3;ticks=(ticks<0 and -1 or 1)*floor(abs(ticks)+.5)
   local raw=d.value+ticks*step;local limits=UI.number_limits[d.key];local clipped=raw<limits[1] or raw>limits[2]
   UI.number_set(d.key,raw,not d.clipped);d.clipped=clipped
  end
 else
  if not d.moved and key==d.key then A.number_edit={key=d.key,text=UI.number_text(d.key,A[d.key]),selected=true} end
  A.number_drag=nil;A.pointer_capture=nil;UI.dirty()
 end
 return true
end
function UI.number_key(k)
 local e=A.number_edit;if not e then return false end
 if k==13 then UI.number_commit()
 elseif k==27 then A.number_edit=nil;UI.dirty()
 elseif k==1 then e.selected=true;UI.dirty()
 elseif k==8 or k==6579564 then e.text=e.selected and '' or e.text:sub(1,-2);e.selected=false;UI.dirty()
 elseif (k>=48 and k<=57) or k==46 or k==45 then
  if e.selected then e.text='';e.selected=false end
  if #e.text<12 then e.text=e.text..string.char(k);UI.dirty() end
 end
 return true
end
function UI.number_lights()
 for key,t in pairs(A.number_flash or {}) do
  local age=R.time_precise()-t;local q=clamp(age/1.35,0,1);local a=1-q*q*(3-2*q)
  if a>0 then local y=UI.number_rows[key] or 402
   rect(35,y-5,150,38,UI.theme_color({1,.19,.16},'red'),.06*a);rect(40,y,140,28,UI.theme_color({1,.26,.20},'red'),.28*a)
  end
 end
end
function UI.set_mode(mode)
 if A.busy or A.drag then return end
 UI.number_commit();A.tool=mode;A.hover_node=nil;UI.reset_line_preview(true);UI.dirty()
end
function UI.clean_points(points)
 table.sort(points,function(a,b)return a.x<b.x end)
 for i=#points,2,-1 do if abs(points[i].x-points[i-1].x)<1e-12 then table.remove(points,i-1) end end
 return points
end
function UI.generated_value(points,x)
 if x<=points[1].x then return points[1].y end
 for i=2,#points do local a,b=points[i-1],points[i]
  if x<b.x then return a.shape==1 and a.y or a.y+(b.y-a.y)*(x-a.x)/max(1e-20,b.x-a.x) elseif x==b.x then return b.y end
 end
 return points[#points].y
end
function UI.write_drawing(points,first,last,hold)
 local c=A.layers[A.layer]
 if not c.env or not A.bindings[A.layer] or #points==0 then return false end
 first,last=clamp(min(first,last),0,1),clamp(max(first,last),0,1)
 points=UI.clean_points(Core.copy(points))
 local start,finish=A.v.pos+first*A.v.len,A.v.pos+last*A.v.len
 local cuts={start,finish};local plans={}
 for _,a in ipairs(c.items) do for _,t in ipairs({a.pos,a.pos+a.len}) do
  if t>start and t<finish then cuts[#cuts+1]=t end
 end end
 table.sort(cuts)
 for i=#cuts,2,-1 do if abs(cuts[i]-cuts[i-1])<1e-12 then table.remove(cuts,i) end end
 if #cuts==1 then cuts[2]=cuts[1] end
 for i=2,#cuts do
  local left,right=cuts[i-1],cuts[i];local ai,count=Track.owner(c.items,(left+right)/2)
  if count>1 then notice('重なったオートメーションは先にまとめてください。',true);return false end
  if ai>=0 then local item=c.items[ai+1]
   if item.mute or abs(item.amp)<1e-12 then notice('無音化されたオートメーションはREAPER側で解除してください。',true);return false end
  end
  local a,b=(left-A.v.pos)/A.v.len,(right-A.v.pos)/A.v.len
  local edge=UI.drawing_segment(points,a)
  local generated={{time=left,y=UI.generated_value(points,a),shape=edge.shape,tension=edge.tension}}
  for _,p in ipairs(points) do if p.x>a+1e-12 and p.x<b-1e-12 then generated[#generated+1]={time=A.v.pos+p.x*A.v.len,y=p.y,shape=p.shape,tension=p.tension} end end
  if right>left then generated[#generated+1]={time=right,y=UI.generated_value(points,b)} end
  plans[#plans+1]={ai=ai,first=left,last=right,points=generated}
 end
 local ok=UI.native_write(c.env,function()
  local sorted={}
  for _,plan in ipairs(plans) do
   Track.erase_range(c.env,plan.ai,plan.first-1e-10,plan.last+1e-10)
   for _,point in ipairs(plan.points) do
    if not R.InsertEnvelopePointEx(c.env,plan.ai,point.time,Track.raw(c.properties,point.y),point.shape or 0,point.tension or 0,false,true) then error('Cannot insert envelope point',0) end
   end
   sorted[plan.ai]=true
  end
  for ai in pairs(sorted) do R.Envelope_SortPointsEx(c.env,ai) end
 end,hold)
 if ok then UI.dirty() end
 return ok
end
function UI.drawing_segment(points,x)
 local point=points[1]
 for _,p in ipairs(points) do if p.x>x+1e-12 then break end;point=p end
 return point
end
function UI.toggle_lane(key)
 if A.drag or A.busy or not UI.check_current() or not UI.ensure_host() then return end
 local c=A.layers[key];if not c.env then return end
 local previous=A.layer;A.layer=key
 local ok,err=pcall(UI.native_write,c.env,function()
  local br=R.BR_EnvAlloc(c.env,false);if not br then error('Envelope properties unavailable',0) end
  local p=c.properties;local show=not c.visible
  local success,result=pcall(R.BR_EnvSetProperties,br,p.active,show,p.armed,true,p.height,p.shape,p.fader,p.options)
  R.BR_EnvFree(br,success)
  if not success then error(result,0) end
  R.TrackList_AdjustWindows(false)
 end,false)
 A.layer=previous;UI.dirty(true)
 if not ok then error(err,0) end
end
function UI.copy_curve(target)
 if A.busy or A.drag or target==A.layer or not UI.check_current() or not UI.ensure_host() then return end
 local src=A.layers[A.layer];local dest=A.layers[target]
 if not src.env or not dest.env then return end
 local points={};local first,last=A.v.pos,A.v.pos+A.v.len
 local function append(time,shape,tension)
  points[#points+1]={x=(time-first)/A.v.len,y=Track.normalized(src.properties,Track.evaluate(src.env,time)),shape=shape or 0,tension=tension or 0}
 end
 local shape,tension=0,0
 for _,seg in ipairs(src.segments) do if seg.first<=first and seg.last>first then shape,tension=seg.point.shape,seg.point.tension end end
 append(first,shape,tension)
 for _,point in ipairs(src.points) do if point.time>first and point.time<last then append(point.time,point.shape,point.tension) end end
 for _,item in ipairs(src.items) do for _,time in ipairs({item.pos,item.pos+item.len}) do
  if time>first and time<last then append(time-1e-8);append(time) end
 end end
 append(last)
 local previous=A.layer;A.layer=target
 local ok,err=pcall(UI.write_drawing,points,0,1,false)
 A.layer=previous;UI.dirty()
 if not ok then error(err,0) end
end
function UI.stamp_line()
 local points,first,last=UI.line_points()
 if #points==0 then return end
 if UI.write_drawing(points,first,last,false) then UI.reset_line_preview(A.pattern==6) end
end
function UI.generate_chaos()
 if A.busy or A.drag then return end
 local points=Core.chaos(128)
 UI.write_drawing(points,0,1,false)
end
function UI.line_preview()
 if A.tool~='line' or not A.v or not A.active or A.busy or A.drag or not A.bindings[A.layer] then return end
 local g=UI.graph;if not inside(g.x,g.y,g.w,g.h) then return end
 local ok,points=pcall(UI.line_points)
 if not ok then
  if UI.preview_error~=tostring(points) then UI.preview_error=tostring(points);notice(points,true) end
  return
 end
 UI.preview_error=nil;local previous
 for _,point in ipairs(points) do
  local x,y=UI.point_position(point)
  if previous then
   if previous.shape==1 then
    line(previous.x,previous.y,x,previous.y,UI.def().color,.4)
    line(x,previous.y,x,y,UI.def().color,.4)
   else line(previous.x,previous.y,x,y,UI.def().color,.4) end
  end
  previous={x=x,y=y,shape=point.shape}
 end
end
function UI.pen_tick(release)
 local d=A.drag;if not d or d.mode~='native_pen' then return end
 local g=UI.graph;local x=clamp((mouse_x-g.x)/g.w,0,1);local y=clamp(1-2*(mouse_y-g.y)/g.h,-1,1)
 if abs(x-d.x)*g.w*scale<2 and abs(y-d.y)*g.h*scale<2 then return end
 local now=R.time_precise();if not release and now<(d.next or 0) then return end
 local points={{x=d.x,y=d.y},{x=x,y=y}}
 if UI.write_drawing(points,min(d.x,x),max(d.x,x),not release) then
  d.x=x;d.y=y;d.next=now+1/30
 else Track.finish();A.drag=nil;A.pointer_capture=nil end
end
function UI.selection_bounds()
 local c=A.layers[A.layer];local box={x=math.huge,y=math.huge,r=-math.huge,b=-math.huge};local count=0
 for _,p in ipairs(c.points) do if p.selected then
  local x,y=UI.point_position(p);box.x=min(box.x,x);box.r=max(box.r,x);box.y=min(box.y,y);box.b=max(box.b,y);count=count+1
 end end
 if count==0 then return end
 if box.r-box.x<8/scale then box.x=box.x-4/scale;box.r=box.r+4/scale end
 if box.b-box.y<8/scale then box.y=box.y-4/scale;box.b=box.b+4/scale end
 return box
end
function UI.box_hit()
 local b=UI.selection_bounds();if not b then return end
 local pad=7/scale;local hx,hy
 if abs(mouse_x-b.x)<=pad then hx='l' elseif abs(mouse_x-b.r)<=pad then hx='r' end
 if abs(mouse_y-b.y)<=pad then hy='t' elseif abs(mouse_y-b.b)<=pad then hy='b' end
 if mouse_x>=b.x-pad and mouse_x<=b.r+pad and mouse_y>=b.y-pad and mouse_y<=b.b+pad then return (hx or '')..(hy or ''),b end
end
function UI.begin_transform(handle,box)
 local c=A.layers[A.layer];local originals={};local region
 for _,p in ipairs(c.points) do if p.selected then
  if not p.editable then notice('重なったオートメーションは先にまとめてください。',true);return end
  region=region or UI.region(c,p.time,p.ai)
  if not UI.in_region(p,region) then notice('同じ範囲のポイントだけを選択してください。範囲をまたぐ場合は先にオートメーション化してください。',true);return end
  local x,y=UI.point_position(p);originals[#originals+1]={x=x,y=y,ai=p.ai}
 end end
 if not region then return end
 local source=Track.capture_pool(c.env,region.owner)
 A.drag={region=region,source=source,layer=c,mode='native_transform',mx=mouse_x,my=mouse_y,handle=handle,box=box,originals=originals,env=c.env}
 A.pointer_capture=true
end
function UI.transform_tick(release)
 local d=A.drag;if not d or d.mode~='native_transform' then return end
 local now=R.time_precise();if not release and now<(d.next or 0) then return end
 local dx,dy=mouse_x-d.mx,mouse_y-d.my
 if dx==d.lastx and dy==d.lasty or not d.lastx and dx*dx+dy*dy<4/(scale*scale) then return end
 local g=UI.graph
 local boundleft=g.x+(d.region.first-A.v.pos)/A.v.len*g.w
 local boundright=g.x+(d.region.last-A.v.pos)/A.v.len*g.w
 local box=d.box;local left,right,top,bottom=box.x,box.r,box.y,box.b
 if d.handle=='' then
  dx=clamp(dx,boundleft-left,boundright-right);dy=clamp(dy,g.y-top,g.y+g.h-bottom)
  left=left+dx;right=right+dx;top=top+dy;bottom=bottom+dy
 else
  if d.handle:find('l') then left=clamp(left+dx,boundleft,right-1/scale) elseif d.handle:find('r') then right=clamp(right+dx,left+1/scale,boundright) end
  if d.handle:find('t') then top=clamp(top+dy,g.y,bottom-1/scale) elseif d.handle:find('b') then bottom=clamp(bottom+dy,top+1/scale,g.y+g.h) end
 end
 local c=d.layer;local selected={}
 for _,p in ipairs(c.points) do if p.selected then selected[#selected+1]=p end end
 if #selected~=#d.originals then Track.finish();UI.cancel_preview();return end
 local edits={};local erase={};local spans={}
 for i,p in ipairs(selected) do
  local o=d.originals[i]
  if p.ai~=o.ai then Track.finish();UI.cancel_preview();return end
  local x=left+(o.x-box.x)/(box.r-box.x)*(right-left);local y=top+(o.y-box.y)/(box.b-box.y)*(bottom-top)
  local time=A.v.pos+clamp((x-g.x)/g.w,0,1)*A.v.len
  time=clamp(time,d.region.first,d.region.last)
  edits[#edits+1]={p=p,time=time,value=Track.raw(c.properties,clamp(1-2*(y-g.y)/g.h,-1,1))}
  -- Only horizontal motion sweeps out other points, on the same native lane.
  if abs(time-p.time)>1e-10 then spans[#spans+1]={ai=p.ai,first=min(time,p.time),last=max(time,p.time)} end
 end
 for _,p in ipairs(c.points) do if not p.selected then
  for _,span in ipairs(spans) do if p.ai==span.ai and p.time>=span.first-1e-10 and p.time<=span.last+1e-10 then erase[#erase+1]=p;break end end
 end end
 table.sort(erase,function(a,b) if a.ai==b.ai then return a.index>b.index end;return a.ai>b.ai end)
 d.lastx,d.lasty=mouse_x-d.mx,mouse_y-d.my;d.next=now+1/30
 UI.native_write(c.env,function()
  Track.restore_pool(c.env,d.source)
  local needed={}
  for _,e in ipairs(edits) do needed[#needed+1]=e.p end
  for _,p in ipairs(erase) do if p.ai<0 then needed[#needed+1]=p end end
  local rebound=Track.rebind_points(c.env,needed)
  local sorted={}
  -- Set first without sorting: original indices stay valid until deletions finish.
  for _,e in ipairs(edits) do Track.set(c.env,rebound[e.p],e.time,e.value,e.p.shape,e.p.tension,true);sorted[e.p.ai]=true end
  local looped={}
  for _,p in ipairs(erase) do
   if p.ai<0 then
    if not R.DeleteEnvelopePointEx(c.env,p.ai,rebound[p].index) then error('Cannot overwrite envelope point',0) end
   else looped[p.ai]=true end
   sorted[p.ai]=true
  end
  -- A pooled deletion can remove more than one visible repetition. Refresh
  -- indices before the next deletion and never delete selected moving points.
  local deadline=R.time_precise()+.35
  for ai in pairs(looped) do
   local removed=0
   while true do
    local candidate
    for index=R.CountEnvelopePointsEx(c.env,ai)-1,0,-1 do
     local ok,time,_,_,_,selected=R.GetEnvelopePointEx(c.env,ai,index)
     if ok and not selected then
      for _,span in ipairs(spans) do
       if span.ai==ai and time>=span.first-1e-10 and time<=span.last+1e-10 then candidate=index;break end
      end
     end
     if candidate then break end
     if R.time_precise()>deadline then error('Too many pooled points in one edit. Select a smaller range.',0) end
    end
    if not candidate then break end
    if removed>=10000 or R.time_precise()>deadline then error('Too many pooled points in one edit. Select a smaller range.',0) end
    if not R.DeleteEnvelopePointEx(c.env,ai,candidate) then error('Cannot overwrite envelope point',0) end
    removed=removed+1
   end
  end
  for ai in pairs(sorted) do R.Envelope_SortPointsEx(c.env,ai) end
 end,not release)
end
function UI.tools_panel()
 label('操作モード',24,145,14,C.muted,1,164,22)
 for i,q in ipairs({{'select','範囲選択'},{'free','ペン'}}) do
  UI.button('mode_'..q[1],q[2],nil,24,174+(i-1)*38,164,32,function() UI.set_mode(q[1]) end,not A.busy,A.tool==q[1],UI.def().color)
 end
 local tone=UI.def().color;local selected=A.tool=='line';local jp=Language.code=='JP'
 gradient(24,250,164,412,C.panel2,C.panel,.55,.95);rect(24,250,164,412,tone,selected and .065 or .022)
 line(24,250,24,662,tone,.4);line(188,250,188,662,tone,.3);line(24,662,188,662,tone,.3)
 UI.button('mode_line','ライン生成',nil,24,250,164,32,function() UI.set_mode('line') end,not A.busy,selected,tone)
 UI.button('pattern',UI.pattern_names[A.pattern],nil,40,288,140,28,UI.next_pattern,selected and not A.busy)
 UI.button('direction','方向：'..({'左','両側','右'})[A.direction],nil,40,320,140,28,function() A.direction=A.direction%3+1;UI.dirty() end,selected and not A.busy)
 for i,q in ipairs({{'sec','秒'},{'beat','拍'},{'grid','グリッド'}}) do
  UI.button('period_unit_'..q[1],jp and q[2] or ({'SEC','BEAT','GRID'})[i],nil,40+(i-1)*36,352,i==3 and 68 or 34,24,function() UI.period_unit(q[1]) end,selected and not A.busy,A.period_unit==q[1],tone)
 end
 local unit=A.period_unit=='sec' and 's' or A.period_unit=='beat' and 'bt' or 'gr'
 for _,block in ipairs({{'height',jp and '縦幅' or 'HEIGHT',380},{'width',jp and '横幅' or 'WIDTH',520}}) do
  label(block[2],40,block[3],12,selected and tone or C.muted,1,65,20,4)
  UI.variable_checkbox(block[1],108,block[3],tone)
  line(32,block[3]+22,32,block[3]+134,selected and tone or C.muted,.3)
  for i,field in ipairs({'start','end','duration','curve'}) do
   local key=block[1]..'_'..field;local y=UI.number_rows[key]
   line(32,y+14,39,y+14,selected and tone or C.muted,.3)
   local title=jp and ({'開始','変動先','変化速度','変化曲率'})[i] or ({'Start','Target','Time','Curve'})[i]
   local suffix=i==4 and '' or i==3 and unit or block[1]=='height' and '%' or unit
   UI.number_field(key,title,40,y,140,suffix)
  end
 end
 local enabled=not A.busy and A.bindings[A.layer]~=nil
 local hot=A.hit=='chaos' and enabled
 BLT.chaosButton(24,670,164,44,enabled,hot,pressed=='chaos' and (gfx.mouse_cap&1)~=0,anim_time,animate('chaos_glow',hot and 1 or 0))
 register('chaos',24,670,164,44,UI.generate_chaos,'ランダム生成',enabled)
 UI.button('drawundo','戻す',nil,24,774,80,28,function() UI.undo_draw(false) end,UI.available('drawundo'))
 UI.button('drawredo','やり直す',nil,108,774,80,28,function() UI.undo_draw(true) end,UI.available('drawredo'))
end
function Track.erase_range(env,ai,first,last)
 local function remaining()
  for _,p in ipairs(Track.nodes(env,ai,first,last)) do
   if p.time>=first and p.time<last then return true end
  end
  return false
 end
 -- An empty deletion is a no-op, not an error. This is usual on pen-down.
 if not remaining() then return end
 R.DeleteEnvelopePointRangeEx(env,ai,first,last)
 if remaining() then error('Cannot replace envelope points',0) end
end
function UI.period_domain()
 local project=A.v and A.v.project or R.EnumProjects(-1,'')
 if A.period_unit~='grid' then return {project=project,mode=A.period_unit} end
 local grid,reason=Core.read_grid(project)
 if not grid then error(reason,0) end
 grid.project=project;return grid
end
function UI.period_coordinate(domain,time)
 if domain.mode=='sec' then return time end
 local qn=R.TimeMap2_timeToQN(domain.project,time)
 if domain.mode=='beat' then return qn end
 if domain.mode=='measure' then
  local index,first,last=Core.measure_at(domain.project,qn)
  if not index then error('Cannot read time signature',0) end
  return index+(qn-first)/(last-first)
 end
 if domain.mode=='swing' then qn=Core.swing_map(domain.project,qn,domain,true) end
 if not finite(qn) then error('Cannot read grid position',0) end
 return qn/domain.qn
end
function UI.period_time(domain,coordinate)
 if domain.mode=='sec' then return coordinate end
 local qn
 if domain.mode=='beat' then qn=coordinate
 elseif domain.mode=='measure' then
  local index=floor(coordinate);local _,first,last=R.TimeMap_GetMeasureInfo(domain.project,index)
  if not finite(first) or not finite(last) or last<=first then error('Cannot read time signature',0) end
  qn=first+(coordinate-index)*(last-first)
 else
  qn=coordinate*domain.qn
  if domain.mode=='swing' then qn=Core.swing_map(domain.project,qn,domain,false) end
 end
 if not finite(qn) then error('Cannot read grid position',0) end
 return R.TimeMap2_QNToTime(domain.project,qn)
end
function UI.period_span()
 if not A.v then return 1 end
 local d=UI.period_domain()
 return abs(UI.period_coordinate(d,A.v.pos+A.v.len)-UI.period_coordinate(d,A.v.pos))
end
function UI.period_unit(unit)
 UI.number_commit();A.period_unit=unit;UI.reset_line_preview(true);UI.dirty()
end
function Core.read_grid(project)
 local _,division,mode,swing=R.GetSetProjectGrid(project,false)
 mode=mode or 0
 if mode==3 then return {mode='measure'} end
 if not finite(division) or division<=0 or not finite(division*4) then
  return nil,"現在のグリッド設定を取得できません。"
 end
 if mode==1 and (not finite(swing) or swing < -1 or swing > 1) then
  return nil,"現在のグリッド設定を取得できません。"
 end
 return {mode=mode==1 and 'swing' or 'straight',qn=division*4,swing=mode==1 and swing or 0}
end
function Core.measure_at(project,qn)
 local index,first,last=R.TimeMap_QNToMeasures(project,qn)
 if not finite(index) or not finite(first) or not finite(last) or last<=first then return nil end
 return index,first,last
end
function Core.swing_map(project,qn,grid,inverse)
 local _,first,last=Core.measure_at(project,qn)
 if not first then return nil end
 local step=grid.qn
 function knot(i)
  local straight=math.min(last,first+i*step)
  if straight>=last then return last end
  return math.min(last,straight+(i%2)*step*grid.swing*.5)
 end
 local index=math.max(0,math.floor((qn-first)/step))
 if inverse then
  if knot(index)>qn then index=math.max(0,index-1)
  elseif knot(index+1)<=qn then index=index+1 end
  local lo,hi=knot(index),knot(index+1)
  if hi<=lo then return nil end
  local a,b=math.min(last,first+index*step),math.min(last,first+(index+1)*step)
  return a+(qn-lo)/(hi-lo)*(b-a)
 end
 local a,b=first+index*step,math.min(last,first+(index+1)*step)
 if b<=a then return nil end
 return knot(index)+(qn-a)/(b-a)*(knot(index+1)-knot(index))
end
function BLT.preferences() local p=BLT.preferenceView or {};BLT.preferenceView=p;for path in pairs(UI.settings_schema()) do local obj,k=UI.settings_slot(path);p[path]=obj[k] end;return p end;BLT.factoryPreferences=BLT.copy(BLT.preferences())
function BLT.captureEnvelope() return {settings=BLT.preferences()} end
BLT.envelopeDefaults=BLT.copy(BLT.captureEnvelope())

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
 defaults=BLT.envelopeDefaults,capture=function() return BLT.captureEnvelope() end,
 valid=BLT.validTrackSettings,apply=BLT.applyTrackSettings,
 localUndo=true,
 busy=function() return A.busy end,commit=function() UI.number_commit();Track.finish();UI.cancel_preview();return true end,
 cancelEdit=function() A.number_edit=nil;Track.finish();UI.cancel_preview() end,editing=function() return A.number_edit~=nil end,
 modal=function() return false end,
 handle=gfx_window_handle,resizeHit=function(x,y) if y<26 and x>=gfx.w-234 then return nil end;return chrome_resize_hit(x,y) end,
 cursor=set_resize_cursor,beginResize=begin_window_resize,resize=update_window_resize,

})
if ...=='blt_test' then function BLT.testDraw(now) UI.static(now or R.time_precise()) end end


if ...=='blt_test' then return {Media=Media,BLT=BLT,A=A,Core=Core,Track=Track,UI=UI} end
UI.load_settings()
if ...=='ui_test' then return {Core=Core,A=A,UI=UI,Chameleon=Chameleon,palette=C} end
local chrome_ok,chrome_err=titlebar_api_ready()
if not chrome_ok then Language.mb(BLT.publicError(chrome_err),'Envelope Canvas Track | 必要な拡張',0);return end
local ww=tonumber(R.GetExtState(SECTION,'window_w')) or W;local wh=tonumber(R.GetExtState(SECTION,'window_h')) or H+Chrome.titleH
ww=clamp(ww,Chrome.minW,2200);wh=clamp(wh,Chrome.minH,1800)
local wx,wy=tonumber(R.GetExtState(SECTION,'window_x')),tonumber(R.GetExtState(SECTION,'window_y'))
-- Match native window/input coordinates in logical points on Mac.
gfx.ext_retina=BLT_MAC and 0 or 1
if finite(wx) and finite(wy) then gfx.init(Chrome.windowTitle,ww,wh,0,wx,wy) else gfx.init(Chrome.windowTitle,ww,wh,0) end
if not apply_custom_window_style(ww,wh) then gfx.quit();Language.mb('カスタムアプリバーを初期化できません。','Envelope Canvas Track',0);return end
if Chameleon.enabled then Chameleon.refresh(true) end
R.atexit(UI.close);UI.safe(function() UI.load_selection(false) end);UI.loop()
