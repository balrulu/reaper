-- @description BLT MINIMAL INFO PANEL
-- @version 0.1.32
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
 ["CHAMELEON  REAPERテーマに擬態"]="CHAMELEON  REAPER theme",
 ["CHAMELEON  オリジナル配色"]="CHAMELEON  Original colors",
 ["カスタムタイトルバーには js_ReaScriptAPI が必要です。\nReaPack から js_ReaScriptAPI をインストールしてください。"]="The app bar requires js_ReaScriptAPI.\nInstall js_ReaScriptAPI via ReaPack.",
 ["アイテム"]="Item",
 ["現在"]="Current",
 ["解析中"]="Analyzing",
 ["表示言語を切替（JP / EN）"]="Switch language (JP / EN)",
 ["名前"]="Name",
 ["長さ"]="Length",
 ["ボリューム"]="Volume",
 ["ピッチ"]="Pitch",
 ["再生速度"]="Rate",
 ["逆再生"]="Reverse",
 ["ミュート"]="Mute",
 ["ロック"]="Lock",
 ["ピーク表示ズーム率"]="Peak zoom",
 ["ピーク表示の調整にはSWS Extensionが必要です。"]="Peak zoom requires SWS Extension.",
 ["ピーク表示の設定を取得できません。"]="Cannot read the peak display gain.",
 ["ピーク表示の設定を変更できません。"]="Cannot change the peak display gain.",
 ["プロジェクトが切り替わったため、ピーク表示の操作を終了しました。"]="Peak zoom adjustment ended because the project changed.",
 ["（名前なし）"]="(Unnamed)",
 ["アイテムを選択してください。"]="Select items.",
 ["編集中に対象が変更されました。もう一度操作してください。"]="Items changed while editing. Please try again.",
 ["選択が変更されました。もう一度操作してください。"]="Selection changed. Please try again.",
 ["対象アイテムが変更または削除されました。"]="An item was changed or deleted.",
 ["名前は改行なし・4096バイト以内で入力してください。"]="Use a single-line name, up to 4096 bytes.",
 ["数値が範囲外です。元の値を保持しました。"]="Value out of range. Original value retained.",
 ["この項目は選択アイテムでは編集できません。"]="This property is unavailable for the selected item.",
 ["選択内にこの項目を編集できないアイテムがあります。"]="Some selected items do not support this property.",
 ["ロックされたアイテムがあります。先にロックを解除してください。"]="Unlock selected items before editing.",
 ["数値が不正です。"]="Invalid number.",
 ["値が不正です。"]="Invalid value.",
 ["値を変更できませんでした。"]="Could not change the value.",
 ["変更に失敗したため、元の値へ戻しました。"]="Update failed. Original values restored.",
 ["復元できない項目があります。REAPERのUndoで確認してください。"]="Some items could not be restored. Check REAPER Undo.",
 ["音声がオンラインになるまでお待ちください。"]="Wait until media is online.",
 ["逆再生の切り替えにはSWS Extensionが必要です。"]="Reverse editing requires SWS Extension.",
 ["ウィンドウを初期化できません。"]="Could not initialize the window.",
 ["プリセットを読み込みました: ファクトリーデフォルト"]="Loaded: Factory Default",
},prefixes={"プリセットを保存しました: ","プリセットを読み込みました: ","現在: "},patterns={
 {'^「(.*)」を上書きしますか？$','Overwrite "%s"?'},
 {'^(%d+)個インポートしました。$','Imported %d preset(s).'},
 {'^(%d+)個選択 · トラック順・時間順の先頭を表示$','%d selected · First by track/time'},
 {'^(%d+)個のアイテムを変更しました。$','%d items updated.'}
}}
local Language=create_language(reaper,"BLT_ITEM_STRIP",LanguageCatalog)
local R=reaper
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
function B.cleanText(text)
 text=tostring(text);B.cleanCache=B.cleanCache or {};local v=B.cleanCache[text];if v then return v end
 v=text:gsub('[%z\1-\31\127]',' ')
 B.cleanCount=(B.cleanCount or 0)+1;if B.cleanCount>512 then B.cleanCache={};B.cleanCount=1 end
 B.cleanCache[text]=v;return v
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
 if type(p)=='table' and host.upgrade then host.upgrade(p.values) end
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
 local inline=host.docked()
 local compact=host.compactChrome and host.compactChrome() or false
 local c=B.barCache;if c and c.width==w and c.compact==compact and c.inline==inline then return c end
 local b={width=w,closeX=w-38,resetX=w-72,themeX=w-106}
 b.foldX=host.fold and b.themeX-34 or nil;b.languageX=(b.foldX or b.themeX)-26;b.nextX=b.languageX-20;b.prevX=b.nextX-20;b.presetX=b.prevX-84
 b.compact=compact;b.inline=inline;b.titleEnd=inline and math.min(210,math.max(0,b.presetX-100)) or nil
 if compact then b.resetX=b.closeX;b.themeX=w-72;b.foldX=w-106;b.languageX=w+500;b.nextX=w+500;b.prevX=w+500;b.presetX=w+500 end
 B.barCache=b;return b
end
function UI.barHit(x,y)
 local b=UI.bar(gfx.w)
 return y>=0 and y<26 and x>=0 and x<gfx.w and (not b.inline or x<b.titleEnd or x>=b.presetX)
end
local function gfx_window_handle() return host.handle() end
local function chrome_resize_hit(x,y) if host.docked() then return nil end;if y<26 and x>=UI.bar(gfx.w).presetX then return nil end;return host.resizeHit(x,y) end
local function set_resize_cursor(mode) host.cursor(mode) end
local function begin_window_resize(mode) host.beginResize(mode) end
local function update_window_resize() host.resize() end
local function clear_chrome_tooltip() B.popupUntil=nil;if R.TrackCtl_SetToolTip then R.TrackCtl_SetToolTip('',0,0,true) end end
B.clearTooltip=clear_chrome_tooltip
-- Non-modal dependency hint. Uses the existing tick, with no extra defer loop.
function B.inputNotice()
 local x,y=gfx.clienttoscreen(gfx.mouse_x,gfx.mouse_y+18)
 R.TrackCtl_SetToolTip(Language.message('ReaImGui 0.10以降が必要です。ReaPackで導入・更新してください。'),x,y,true)
 B.popupUntil=R.time_precise()+1;B.tip=nil;B.tipVisible=false
end
function B.requireInput(ime)
 if ime.api then return true end
 if type(R.ImGui_GetBuiltinPath)~='function' then B.inputNotice();return false end
 local ok,api=pcall(function() return dofile(R.ImGui_GetBuiltinPath()..'/imgui.lua')('0.10') end)
 if not ok or type(api)~='table' then B.inputNotice();return false end
 ime.api=api;return true
end

function Presets.nativeMenu(x,y)
 if not host.commit() then return end
 host.cancelEdit()
 local labels,actions={},{}
 local function add(label,action,disabled)
  labels[#labels+1]=(disabled and '#' or '')..label:gsub('[|<>!#]',' ')
  actions[#actions+1]=disabled and false or action
 end
 add(Language.message(Presets.factory.name),function() Presets.apply(Presets.factory) end)
 for _,p in ipairs(Presets.items) do
  add(p.name,function() Presets.apply(p) end)
 end
 add(Language.message('上書き保存'),function() Presets.save(false) end,Presets.isFactory(Presets.current))
 add(Language.message('名前を付けて保存…'),function() Presets.save(true) end)
 add(Language.message('インポート…'),function() Presets.import() end)
 add(Language.message('現在値をエクスポート'),function() Presets.export(false) end,Presets.isFactory(Presets.current))
 add(Language.message('プリセット一覧をエクスポート'),function() Presets.export(true) end,#Presets.items==0)
 gfx.x=x;gfx.y=y
 local choice=gfx.showmenu(table.concat(labels,'|'))
 local action=actions[choice];if action then action() end
 Presets.swallow=true;wake_visuals()
end
function Presets.menu(x,y)
  if host.docked() then Presets.nativeMenu(x,y);return end
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
  local inBar=host.active() and not blocked and inWindow and UI.barHit(mx,my)
  local resizeMode=not blocked and chrome_resize_hit(mx,my) or nil
  local resizing=Chrome.resize~=nil
  local cursorMode=resizing and Chrome.resize.mode or resizeMode
  set_resize_cursor(cursorMode)
  local hoverClose=inBar and mx>=closeX and mx<w and not resizeMode and not resizing
  local hoverReset=not host.docked() and not (host.collapsed and host.collapsed()) and not (host.transition and host.transition()) and inBar and mx>=resetX and mx<closeX and not resizeMode and not resizing
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

  local function background(x,width)
  gfx.set(C.bg[1],C.bg[2],C.bg[3],1); gfx.rect(x,0,width,Chrome.titleH,1)
  gfx.gradrect(x,0,width,Chrome.titleH,C.field[1],C.field[2],C.field[3],.72,
    0,0,0,0,(C.bg[1]-C.field[1])/Chrome.titleH,(C.bg[2]-C.field[2])/Chrome.titleH,(C.bg[3]-C.field[3])/Chrome.titleH,.22/Chrome.titleH)
  gfx.set(C.edge[1],C.edge[2],C.edge[3],.42); gfx.line(x,Chrome.titleH-1,x+width,Chrome.titleH-1,1)

  end
  if b.inline then background(0,b.titleEnd);background(presetX,w-presetX) else background(0,w) end

  if not Chrome.textFontsReady or Chrome.fontDPI~=(gfx.ext_retina or 1) then Chrome.fontDPI=gfx.ext_retina or 1;B.chromeFont(); Chrome.textFontsReady=true else B.chromeFont() end; B.fontKey="chrome"
  -- Center the unadorned title within the bar using the actual font height.
  local _,titleHeight=UI.textMetrics(Chrome.titleText)
  local ty=math.floor((Chrome.titleH-titleHeight)*.5)
  gfx.set(Chrome.mint[1],Chrome.mint[2],Chrome.mint[3],.88); gfx.x=14; gfx.y=ty; gfx.drawstr(UI.fit(Chrome.titleText,math.max(0,(b.titleEnd or (b.compact and b.foldX or presetX))-22)))

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
    local cx,cy=foldX+17,13
    gfx.rect(cx-7,cy-6,14,12,0)
    if host.docked() then gfx.rect(cx-5,cy+1,10,3,1)
    else gfx.line(cx-5,cy+2,cx+5,cy+2);gfx.line(cx,cy-4,cx,cy);gfx.line(cx-2,cy-2,cx,cy);gfx.line(cx,cy,cx+2,cy-2) end
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
  gfx.set(rcol[1],rcol[2],rcol[3],host.docked() and .25 or (hoverReset and .98 or .82))
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
    elseif inBar and not host.docked() and not (host.transition and host.transition()) then
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
 return Presets.open or Presets.swallow or UI.barHit(gfx.mouse_x,gfx.mouse_y)
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
 if host and host.beforeKey then host.beforeKey(k) end
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
  if UI.barHit(mx,my) then
   local b=UI.bar(gfx.w)
   tip=mx>=b.closeX and '閉じる' or mx>=b.resetX and 'ウィンドウサイズ初期化' or mx>=b.themeX and 'カメレオンモード' or b.foldX and mx>=b.foldX and (Language.code=='JP' and (host.docked() and 'ドック解除' or 'ドッカーに格納') or (host.docked() and 'Undock' or 'Dock')) or mx>=b.languageX and '表示言語を切替（JP / EN）' or mx>=b.nextX and '次のプリセット' or mx>=b.prevX and '前のプリセット' or mx>=b.presetX and 'プリセット（読込・保存・インポート／エクスポート）' or nil
  end
 end
 if not tip and host.tip and active and not Presets.open and not host.modal() and (gfx.mouse_cap&1)==0 then tip=host.tip(mx,my) end
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
  if R.ShowConsoleMsg then pcall(R.ShowConsoleMsg,tostring(err)..'\n') end
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
 pcall(gfx.update)
 if Chrome.requestClose then state.closing=true end
 state.content_dirty=true
 B.cleanup(host.wake)
 B.logError(err)
end

return B
end)()

local SECTION='BLT_ITEM_STRIP'
local min,max,abs,floor=math.min,math.max,math.abs,math.floor
local function clamp(v,a,b) return max(a,min(b,v)) end
local function finite(v) return type(v)=='number' and v==v and abs(v)<math.huge end
local Core={}
function Core.precision(key,value)
 if key~='volume' and key~='pitch' then return value end
 local n=math.floor(math.abs(value)*100+1e-9)/100
 return n==0 and 0 or (value<0 and -n or n)
end
-- Host values can be just below a hundredth after state restoration or gain/dB
-- conversion. Round only the control/display value; retain raw snapshot values
-- for rollback and native Undo. Explicit typed input keeps Core.precision.
function Core.control_value(key,value)
 if key~='volume' and key~='pitch' then return value end
 local n=math.floor(math.abs(value)*100+.5+1e-9)/100
 return n==0 and 0 or (value<0 and -n or n)
end
function Core.step(key,value,fine)
 local n=value*(fine and .1 or 1)
 if key=='volume' or key=='pitch' then return max(.01,Core.precision(key,n)) end
 return n
end
Core.specs={length={label='長さ',lo=.000001,hi=10000000},volume={label='ボリューム',lo=-150,hi=24},pitch={label='ピッチ',lo=-120,hi=120},rate={label='再生速度',lo=.001,hi=100},pan={label='PAN',lo=-100,hi=100}}
Core.defaults={lengthMode=-1}
function Core.valid_length_mode(v) return v==-1 or v==0 or v==2 or v==3 or v==4 or v==5 or v==6 end
function Core.valid_settings(v)
 if type(v)~='table' or not Core.valid_length_mode(v.lengthMode) then return false end
 for k in pairs(v) do if k~='lengthMode' then return false end end
 return true
end
function Core.valid(project,p,kind) return p and R.ValidatePtr2(project,p,kind) end
function Core.row(project,item)
 local take=R.GetActiveTake(item)
 local v={item=item,take=take,project=project,pos=R.GetMediaItemInfo_Value(item,'D_POSITION'),
  track=R.GetMediaTrackInfo_Value(R.GetMediaItemTrack(item),'IP_TRACKNUMBER'),index=R.GetMediaItemInfo_Value(item,'IP_ITEMNUMBER'),
  length=R.GetMediaItemInfo_Value(item,'D_LENGTH'),gain=R.GetMediaItemInfo_Value(item,'D_VOL'),
  mute=R.GetMediaItemInfo_Value(item,'B_MUTE_ACTUAL')~=0,lockBits=floor(R.GetMediaItemInfo_Value(item,'C_LOCK') or 0)}
 v.volume=v.gain>0 and max(Core.specs.volume.lo,20*math.log(v.gain,10)) or Core.specs.volume.lo
 v.lock=(v.lockBits&1)~=0
 if take then
  v.midi=R.TakeIsMIDI(take)
  v.name=R.GetTakeName(take) or '';v.pitch=R.GetMediaItemTakeInfo_Value(take,'D_PITCH');v.pan=R.GetMediaItemTakeInfo_Value(take,'D_PAN')*100
  local rate=R.GetMediaItemTakeInfo_Value(take,'D_PLAYRATE');if finite(rate) and rate>0 then v.rate=rate end
  if not v.midi and R.BR_GetMediaSourceProperties then
   local ok,section,start,len,fade,reverse=R.BR_GetMediaSourceProperties(take)
   if ok then v.reverse=reverse;v.sourceProps={section,start,len,fade,reverse} end
  end
 end
 return v
end
function Core.collect(project)
 local rows={}
 for i=0,R.CountSelectedMediaItems(project)-1 do
  local item=R.GetSelectedMediaItem(project,i)
  if Core.valid(project,item,'MediaItem*') then rows[#rows+1]=Core.row(project,item) end
 end
 table.sort(rows,function(a,b)
  if a.track~=b.track then return a.track<b.track end
  if a.pos~=b.pos then return a.pos<b.pos end
  return a.index<b.index
 end)
 return rows
end
function Core.snapshot()
 local project=R.EnumProjects(-1,'')
 return {project=project,revision=R.GetProjectStateChangeCount(project),rows=Core.collect(project)}
end
function Core.display(project,selection)
 local first,track,pos,index
 local mixed,seen,baseline,flags={},{},{},{}
 local hasMidi=false
 local count=selection and #selection or R.CountSelectedMediaItems(project)
 for i=0,count-1 do
  local item=selection and selection[i+1] or R.GetSelectedMediaItem(project,i)
  if Core.valid(project,item,'MediaItem*') then
   flags.mute=R.GetMediaItemInfo_Value(item,'B_MUTE_ACTUAL')~=0
   flags.lock=(floor(R.GetMediaItemInfo_Value(item,'C_LOCK') or 0)&1)~=0;flags.reverse=nil
   local take=R.GetActiveTake(item)
   if take and R.TakeIsMIDI(take) then hasMidi=true end
   if not hasMidi and not mixed.reverse and R.BR_GetMediaSourceProperties then
    if take then local ok,_,_,_,_,rev=R.BR_GetMediaSourceProperties(take);if ok then flags.reverse=rev end end
   end
   for k,v in pairs(flags) do if seen[k] and baseline[k]~=v then mixed[k]=true end;seen[k]=true;baseline[k]=v end
   local t=R.GetMediaTrackInfo_Value(R.GetMediaItemTrack(item),'IP_TRACKNUMBER')
   local p=R.GetMediaItemInfo_Value(item,'D_POSITION');local n=R.GetMediaItemInfo_Value(item,'IP_ITEMNUMBER')
   if not first or t<track or (t==track and (p<pos or (p==pos and n<index))) then first,track,pos,index=item,t,p,n end
  end
 end
 return first and {Core.row(project,first)} or {},count,mixed,hasMidi
end
function Core.check(s)
 if R.EnumProjects(-1,'')~=s.project or R.GetProjectStateChangeCount(s.project)~=s.revision then return false,'編集中に対象が変更されました。もう一度操作してください。' end
 if R.CountSelectedMediaItems(s.project)~=#s.rows then return false,'選択が変更されました。もう一度操作してください。' end
 for _,v in ipairs(s.rows) do
  if not Core.valid(s.project,v.item,'MediaItem*') or not R.IsMediaItemSelected(v.item)
   or R.GetActiveTake(v.item)~=v.take or (v.take and not Core.valid(s.project,v.take,'MediaItem_Take*')) then return false,'対象アイテムが変更または削除されました。' end
 end
 return true
end
function Core.parse(key,text)
 if key=='name' then
  if type(text)~='string' or not utf8.len(text) or text:find('[%z\r\n]') or #text>4096 then return nil,'名前は改行なし・4096バイト以内で入力してください。' end
  return text
 end
 local s=tostring(text):match('^%s*(.-)%s*$')
 if key=='pan' then
  if s:upper()=='C' then return 0 end
  local side,n=s:upper():match('^([LR])%s*(%d+%.?%d*)%%?$')
  if side then s=tostring(tonumber(n)*(side=='L' and -1 or 1)) end
 end
 local n=tonumber(s);local spec=Core.specs[key]
 if not finite(n) or not spec or n<spec.lo or n>spec.hi then return nil,'数値が範囲外です。元の値を保持しました。' end
 return Core.precision(key,n)
end
function Core.format(key,v)
 if v==nil then return '—' end
 if key=='name' then return v~='' and v or '（名前なし）' end
 if key=='length' then return string.format('%.3f s',v) end
 if key=='volume' then v=Core.control_value(key,v);return v<=-150 and '−∞ dB' or v==0 and '0.00 dB' or string.format('%+.2f dB',v) end
 if key=='pitch' then v=Core.control_value(key,v);return v==0 and '0.00 st' or string.format('%+.2f st',v) end
 if key=='rate' then
  local st=Core.control_value('pitch',12*math.log(v,2))
  return string.format('%.3f (%s st)',v,st==0 and '0.00' or string.format('%+.2f',st))
 end
 if key=='pan' then return abs(v)<.0001 and 'C' or string.format('%s %.1f%%',v<0 and 'L' or 'R',abs(v)) end
 return v and 'ON' or 'OFF'
end
function Core.plan(s,key,value,absolute)
 if #s.rows==0 then return nil,'アイテムを選択してください。' end
 local spec=Core.specs[key];local changes={};local first=s.rows[1][key]
 if first==nil then return nil,'この項目は選択アイテムでは編集できません。' end
 if spec and not finite(value) then return nil,'数値が不正です。' end
 if spec then value=Core.precision(key,value);first=Core.control_value(key,first) end
 if not spec and key~='name' and type(value)~='boolean' then return nil,'値が不正です。' end
 for _,v in ipairs(s.rows) do
  if v[key]==nil then return nil,'選択内にこの項目を編集できないアイテムがあります。' end
  if key~='lock' and v.lock then return nil,'ロックされたアイテムがあります。先にロックを解除してください。' end
  local current=spec and Core.control_value(key,v[key]) or v[key]
  local target=value
  if spec then
   target=Core.precision(key,clamp(absolute and value or current+value-first,spec.lo,spec.hi))
  end
  if key=='rate' then
   local newLength=v.length*v.rate/target
   if not finite(newLength) or newLength<=0 then return nil,'数値が範囲外です。元の値を保持しました。' end
  end
  -- Committing the displayed value must not rewrite hidden precision or create
  -- an Undo step. Explicit -infinity still silences a nonzero gain.
  local changed=target~=current or (key=='volume' and absolute and target<=-150 and v.gain~=0)
  if changed then changes[#changes+1]={row=v,before=v[key],after=target} end
 end
 return changes
end
function Core.set(v,key,value,restore)
 if key=='name' then return R.GetSetMediaItemTakeInfo_String(v.take,'P_NAME',value,true)
 elseif key=='length' then return R.SetMediaItemInfo_Value(v.item,'D_LENGTH',value)
 elseif key=='volume' then return R.SetMediaItemInfo_Value(v.item,'D_VOL',restore and v.gain or (value<=-150 and 0 or 10^(value/20)))
 elseif key=='pitch' then return R.SetMediaItemTakeInfo_Value(v.take,'D_PITCH',value)
 elseif key=='rate' then
  local length=restore and v.length or v.length*v.rate/value
  local rateOK=R.SetMediaItemTakeInfo_Value(v.take,'D_PLAYRATE',value)
  if not rateOK and not restore then return false end
  local lengthOK=R.SetMediaItemInfo_Value(v.item,'D_LENGTH',length)
  return rateOK and lengthOK
 elseif key=='pan' then return R.SetMediaItemTakeInfo_Value(v.take,'D_PAN',value/100)
 elseif key=='mute' then return R.SetMediaItemInfo_Value(v.item,'B_MUTE_ACTUAL',value and 1 or 0)
 elseif key=='lock' then return R.SetMediaItemInfo_Value(v.item,'C_LOCK',(v.lockBits&(~1))|(value and 1 or 0))
 elseif key=='reverse' then
  if not R.BR_SetMediaSourceProperties then return false end
  local p=v.sourceProps
  if not R.BR_SetMediaSourceProperties(v.take,p[1],p[2],p[3],p[4],value) then return false end
  -- Trigger the native take-change path synchronously; restore exact pitch even if the first setter fails.
  local pitch=v.pitch
  if not finite(pitch) then return false end
  local delta=pitch>=120 and -.000001 or .000001
  local ok,touched=pcall(R.SetMediaItemTakeInfo_Value,v.take,'D_PITCH',pitch+delta)
  local restored,result=pcall(R.SetMediaItemTakeInfo_Value,v.take,'D_PITCH',pitch)
  if not restored or not result then return false end
  return ok and touched
 end
 return false
end
function Core.refresh_item(v,key)
 if key=='reverse' or key=='rate' then
  local ok,err=pcall(R.UpdateItemInProject,v.item)
  if not ok then
   BLT.logError(err)
   local track=R.GetMediaItemTrack(v.item)
   if track and R.MarkTrackItemsDirty then
    local worked,why=pcall(R.MarkTrackItemsDirty,track,v.item)
    if not worked then BLT.logError(why) end
   end
  end
 end
end
function Core.apply(s,key,value,absolute,defer_undo)
 local ok,err=Core.check(s);if not ok then return nil,err end
 local changes;changes,err=Core.plan(s,key,value,absolute);if not changes then return nil,err end
 if #changes==0 then return 0 end
 local attempted=0
 if not defer_undo then R.Undo_BeginBlock2(s.project) end
 R.PreventUIRefresh(1)
 local success,why=xpcall(function()
  for i,c in ipairs(changes) do attempted=i;if not Core.set(c.row,key,c.after,false) then error('値を変更できませんでした。',0) end end
 end,debug.traceback)
 local restored=true
 if not success then for i=attempted,1,-1 do local c=changes[i];local worked,result=pcall(Core.set,c.row,key,c.before,true);if not worked or not result then restored=false end end end
 for i=1,attempted do Core.refresh_item(changes[i].row,key) end
 R.PreventUIRefresh(-1);R.UpdateArrange()
 if not defer_undo then R.Undo_EndBlock2(s.project,'BLT MINIMAL INFO PANEL: '..key..(success and '' or ' (failed)'),-1) end
 if not success then return nil,restored and '変更に失敗したため、元の値へ戻しました。' or '復元できない項目があります。REAPERのUndoで確認してください。' end
 return #changes
end

local S=BLT.copy(Core.defaults)
local A={selection={},items={},project=nil,message='アイテムを選択してください。',bad=false,nextPoll=0,revision=nil,flash={},closing=false}
local lengthMode=tonumber(R.GetExtState(SECTION,'length_mode')) or -1
if not Core.valid_length_mode(lengthMode) then lengthMode=-1 end
S.lengthMode=lengthMode
local function frame_rate()
 local fps=R.TimeMap_curFrameRate(R.EnumProjects(-1,''))
 return fps
end
local function length_text(value,pos)
 if lengthMode==6 then return string.format('%.3f',value*frame_rate()):gsub('0+$',''):gsub('%.$','') end
 if lengthMode==3 then return string.format('%.3f',value) end
 return R.format_timestr_len(value,'',pos or 0,lengthMode)
end
local function effective_length_mode()
 local mode=lengthMode
 if mode==-1 and R.GetToggleCommandState then
  if R.GetToggleCommandState(40369)==1 then return 4 end
  if R.GetToggleCommandState(40370)==1 or R.GetToggleCommandState(41973)==1 then return 5 end
  if R.GetToggleCommandState(40365)==1 or R.GetToggleCommandState(40368)==1 then return 3 end
  return 2
 end
 return mode
end
local function length_step(fine)
 local mode=effective_length_mode()
 if mode==4 then return R.parse_timestr_len('1',0,4) end
 if mode==5 or mode==6 then return 1/frame_rate() end
 return fine and .1 or 1
end
function Core.adjust_value(key,first,ticks,fine,mode)
 if ticks==0 then return Core.control_value(key,first[key]) end
 local value=first[key]
 if key=='rate' then
  local unit=fine and .1 or 1
  local st=12*math.log(value,2)/unit
  local nextIndex=ticks>0 and math.floor(st+1e-9)+ticks or math.ceil(st-1e-9)+ticks
  value=2^(nextIndex*unit/12)
 elseif key=='length' and (mode or effective_length_mode())==2 then
  local project=first.project or R.EnumProjects(-1,'')
  local _,_,_,beats=R.TimeMap2_timeToBeats(project,first.pos+value)
  value=R.TimeMap2_beatsToTime(project,beats+ticks*(fine and .1 or 1))-first.pos
 else
  local step=key=='length' and length_step(fine) or Core.step(key,1,fine)
  value=Core.control_value(key,value)+ticks*step
 end
 local spec=Core.specs[key]
 return Core.precision(key,clamp(value,spec.lo,spec.hi))
end
-- Wheel edits are live, but only the settled result becomes an Undo point.
-- Do not leave a project-wide Undo block open across defer calls: other native
-- actions must remain free to create/restore their own history states.
local WheelUndo={delay=.5}
function WheelUndo.project_open(project)
 if R.EnumProjects(-1,'')==project then return true end
 local i=0
 while true do
  local p=R.EnumProjects(i,'');if not p then return false end
  if p==project then return true end;i=i+1
 end
end
function WheelUndo.history_changed(p)
 return R.Undo_CanUndo2(p.project)~=p.undo or R.Undo_CanRedo2(p.project)~=p.redo
end
function WheelUndo.selection_matches(p)
 if R.EnumProjects(-1,'')~=p.project or R.CountSelectedMediaItems(p.project)~=#p.before.rows then return false end
 for i=0,#p.before.rows-1 do
  local item=R.GetSelectedMediaItem(p.project,i);local v=item and p.selected[item]
  if not v or not Core.valid(p.project,item,'MediaItem*') or R.GetActiveTake(item)~=v.take then return false end
 end
 return true
end
function WheelUndo.has_changes(p,rows)
 -- Compare stored native values, not formatted decimals. This also covers the
 -- coupled item length when wheel-editing playback rate.
 for _,v in ipairs(rows or p.before.rows) do
  if not Core.valid(p.project,v.item,'MediaItem*') then return true end
  if p.key=='volume' then
   if R.GetMediaItemInfo_Value(v.item,'D_VOL')~=v.gain then return true end
  elseif p.key=='length' then
   if R.GetMediaItemInfo_Value(v.item,'D_LENGTH')~=v.length then return true end
  else
   if not Core.valid(p.project,v.take,'MediaItem_Take*') then return true end
   if p.key=='pitch' and R.GetMediaItemTakeInfo_Value(v.take,'D_PITCH')~=v.pitch then return true end
   if p.key=='pan' and R.GetMediaItemTakeInfo_Value(v.take,'D_PAN')*100~=v.pan then return true end
   if p.key=='rate' and (R.GetMediaItemTakeInfo_Value(v.take,'D_PLAYRATE')~=v.rate
      or R.GetMediaItemInfo_Value(v.item,'D_LENGTH')~=v.length) then return true end
  end
 end
 return false
end
function WheelUndo.finish()
 local p=WheelUndo.pending;if not p then return false end
 if not WheelUndo.project_open(p.project) or WheelUndo.history_changed(p) then
  -- A native action has already checkpointed/restored the live state. Never
  -- append a stale timer point (which would invalidate native Redo).
  WheelUndo.pending=nil;return false
 end
 -- Older REAPER versions may expose identical Undo/Redo descriptions for
 -- adjacent entries. An unexpected change to the values we just wrote also
 -- invalidates the pending group; never checkpoint an externally restored value.
 if not p.applying and p.after and R.GetProjectStateChangeCount(p.project)~=p.revision
    and WheelUndo.has_changes(p,p.after) then WheelUndo.pending=nil;return false end
 local changed=WheelUndo.has_changes(p)
 if changed then R.Undo_OnStateChangeEx2(p.project,'BLT MINIMAL INFO PANEL: '..p.key,4,-1) end
 WheelUndo.pending=nil
 return changed
end
function WheelUndo.poll(now)
 local p=WheelUndo.pending;if not p then return end
 if not WheelUndo.project_open(p.project) or WheelUndo.history_changed(p) then WheelUndo.pending=nil;return end
 local flags=gfx.getchar(65536)
 local focused=(flags&1)==0 or (flags&2)~=0
 local buttons=(gfx.mouse_cap or 0)&3
 if R.JS_Mouse_GetState then
  local ok,state=pcall(R.JS_Mouse_GetState,3)
  if ok and type(state)=='number' then buttons=buttons|(floor(state)&3) end
 end
 if now>=p.deadline or not WheelUndo.selection_matches(p)
    or R.GetProjectStateChangeCount(p.project)~=p.revision
    or focused~=p.focused or buttons~=0 then WheelUndo.finish() end
end
function WheelUndo.apply(key,ticks,fine,absolute)
 WheelUndo.poll(R.time_precise())
 local p=WheelUndo.pending
 if p and (p.key~=key or p.absolute~=(absolute==true)) then WheelUndo.finish();p=nil end
 local snap=Core.snapshot();local first=snap.rows[1]
 if not first or first[key]==nil then return 0 end
 local value=Core.adjust_value(key,first,ticks,fine)
 local ok,err=Core.check(snap);if not ok then WheelUndo.finish();return nil,err end
 local changes;changes,err=Core.plan(snap,key,value,absolute)
 if not changes then WheelUndo.finish();return nil,err end
 if #changes==0 then
  if p then p.deadline=R.time_precise()+WheelUndo.delay end
  return 0
 end
 if not p then
  local flags=gfx.getchar(65536)
  p={project=snap.project,key=key,absolute=absolute==true,before=snap,selected={},
   undo=R.Undo_CanUndo2(snap.project),redo=R.Undo_CanRedo2(snap.project),
   focused=(flags&1)==0 or (flags&2)~=0,revision=snap.revision}
  for _,v in ipairs(snap.rows) do p.selected[v.item]=v end
  WheelUndo.pending=p
 end
 p.deadline=R.time_precise()+WheelUndo.delay
 p.applying=true
 local n; n,err=Core.apply(snap,key,value,absolute,true)
 if n then p.after=Core.collect(p.project) end
 p.revision=R.GetProjectStateChangeCount(p.project);p.applying=nil
 p.deadline=R.time_precise()+WheelUndo.delay
 if not n then WheelUndo.finish();return nil,err end
 return n
end

local IME={};local E=nil;local gesture=nil
local function status(text,bad) A.message=tostring(text or '');A.bad=bad==true;A.content_dirty=true end
local function save_settings()
 S.lengthMode=lengthMode;BLT.store(SECTION,'length_mode',tostring(lengthMode),true)
end
local function extnum(key,default) local n=tonumber(R.GetExtState(SECTION,key));return finite(n) and n or default end
local W,H=1230,44
local C={
  bg={0.018,0.030,0.055}, bg2={0.030,0.090,0.180}, panel={0.040,0.068,0.110}, panel2={0.055,0.125,0.205},
  field={0.018,0.040,0.080}, edge={0.145,0.285,0.445}, edge2={0.360,0.650,0.900},
  text={0.955,0.980,1.000}, muted={0.690,0.780,0.875}, faint={0.390,0.505,0.635},
  accent={0.120,0.490,0.980}, accent2={0.650,0.895,1.000}, accent3={0.045,0.235,0.520},
  focus={0.225,0.610,1.000}, focus2={0.690,0.900,1.000}, ink={0.018,0.075,0.160},
  hover={0.430,0.790,1.000}, warn={1.000,0.755,0.490}, red={1.000,0.230,0.300}, green={0.470,0.850,0.700}, quiet={0.300,0.360,0.440}
}
local fonts={"Yu Gothic UI","Segoe UI","Consolas"}
local os_name=R.GetOS()
if os_name:match("OSX") or os_name:match("macOS") then fonts={"Hiragino Sans","Helvetica Neue","Menlo"}
elseif not os_name:match("Win") then fonts={"sans-serif","sans-serif","monospace"} end

local scale,ox,oy,mx,my=1,0,0,-1,-1
local downLast=false
local redraw_dirty=true
local last_raw_mouse_x,last_raw_mouse_y,last_raw_mouse_cap=nil,nil,nil
local function wake_visuals() redraw_dirty=true end

local function sx(x) return ox+x*scale end
local function sy(y) return oy+y*scale end
local function color(c,a) gfx.set(c[1],c[2],c[3],a or 1) end
local function rect(x,y,w,h,c,a) color(c,a); gfx.rect(sx(x),sy(y),w*scale,h*scale,1) end
local function line(x,y,xx,yy,c,a) color(c,a); gfx.line(sx(x),sy(y),sx(xx),sy(yy),1) end

local function font(size,kind,bold) BLT.font(size,kind,bold,scale,fonts) end
local function label(text,x,y,w,h,size,c,bold,flags,kind,literal)
  local shown=literal and tostring(text) or Language.message(text)
  font(size,kind,bold); color(c or C.text); gfx.x,gfx.y=sx(x),sy(y)
  if w then shown=BLT.ui.fit(shown,w*scale) end
  gfx.drawstr(BLT.cleanText(shown),flags or 0,sx(x+w),sy(y+h))
end

local panelPoints={{0,0},{0,0},{0,0},{0,0},{0,0},{0,0}}
local function cut_panel(x,y,w,h,cut,c,a,edge,edge_a,top_left)
  local tl=top_left and cut or 0
  local pts=panelPoints
  pts[1][1],pts[1][2]=x+tl,y;pts[2][1],pts[2][2]=x+w,y
  pts[3][1],pts[3][2]=x+w,y+h-cut;pts[4][1],pts[4][2]=x+w-cut,y+h
  pts[5][1],pts[5][2]=x,y+h;pts[6][1],pts[6][2]=x,y+tl
  local cx,cy=x+w/2,y+h/2
  color(c,a)
  for i=1,#pts do local p,q=pts[i],pts[i%#pts+1]; gfx.triangle(sx(cx),sy(cy),sx(p[1]),sy(p[2]),sx(q[1]),sy(q[2])) end
  if edge then for i=1,#pts do local p,q=pts[i],pts[i%#pts+1]; line(p[1],p[2],q[1],q[2],edge,edge_a or 1) end end
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
  chameleonPressed=false,resizeCursors={},resizeCursorMode=nil,titleH=26,windowTitle='BLT MINIMAL INFO PANEL',titleText='M I N I M A L   I N F O   P A N E L',
  minW=1070,minH=70,mint={0.38,0.88,0.72},ice={0.65,0.895,1.0},red={1.0,0.27,0.34},
  isWindows=R.GetOS():match("Win")~=nil,resizeEdge=6,resizeCornerBand=8,resizeCornerSpan=24,resizeTopLeftGuard=30,resizeTopRightGuard=110,
  tooltipHover=nil,tooltipSince=0,tooltipVisible=false,tooltipDelay=.70,
  cursorId={we=32644,ns=32645,nwse=32642,nesw=32643,arrow=32512}}
Chrome.font=Chrome.isWindows and "Segoe UI" or (BLT_MAC and "Helvetica Neue" or "sans-serif")
local CHROME_DEFAULT={
  mint={Chrome.mint[1],Chrome.mint[2],Chrome.mint[3]},
  ice={Chrome.ice[1],Chrome.ice[2],Chrome.ice[3]},
}
local function chameleon_notify(text)
  status(text,false)
end

Chameleon.keys={
  "col_main_bg2","col_main_bg","col_arrangebg","col_tracklistbg","col_mixerbg",
  "genlist_bg","col_tl_bg","col_trans_bg","col_tr1_bg","col_tr2_bg",
  "col_main_editbk","col_transport_editbk","col_buttonbg",

  "col_main_text2","col_main_text","genlist_fg","col_tcp_text",
  "col_toolbar_text","col_toolbar_text_on","col_tl_fg","col_tl_fg2","col_trans_fg",

  "col_seltrack","col_seltrack2","genlist_selbg",
  "col_tl_bgsel","toolbararmed_color","col_main_resize2",
  "selitem_dot","selitem_tag","activetake_tag",
  "col_routinghl1","col_routinghl2","track_lanesolo_tabcol",

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
  -- Peak zoom shares the theme accent; the default green is restored when disabled.
  out.green=ccopy(out.accent2)

  out.warn=fit_accent_to_bg(C_DEFAULT.warn,bg,text_is_light)
  out.red=fit_accent_to_bg(C_DEFAULT.red,bg,text_is_light)
  return out
end

function Chameleon.restore()
  for k,v in pairs(C_DEFAULT) do C[k]=ccopy(v) end
  Chrome.mint=ccopy(CHROME_DEFAULT.mint)
  Chrome.ice=ccopy(CHROME_DEFAULT.ice)
end

function Chameleon.apply(palette)
  for k,v in pairs(palette) do C[k]=v end
  Chrome.mint=ccopy(C.accent2)
  Chrome.ice=ccopy(C.focus2)
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

local fields={{key='name',label='名前'}, {key='length',label='長さ',width=130},
 {key='volume',label='ボリューム',width=93},{key='pitch',label='ピッチ',width=88},{key='rate',label='再生速度',width=180},{key='pan',label='PAN',width=93},
 {key='reverse',label='逆再生',width=36,check=true},{key='mute',label='ミュート',width=36,check=true},{key='lock',label='ロック',width=36,check=true}}

-- REAPER's projpeaksgain is a linear display multiplier, not item audio gain.
-- Keep this view control outside item snapshots, presets, and project Undo edits.
local PeakZoom={key='projpeaksgain',min=0,max=36.1,width=90,gap=18,nextPoll=0}
function PeakZoom.supported()
 return (type(R.SNM_GetDoubleConfigVarEx)=='function' or type(R.SNM_GetDoubleConfigVar)=='function')
    and (type(R.SNM_SetDoubleConfigVarEx)=='function' or type(R.SNM_SetDoubleConfigVar)=='function')
end
function PeakZoom.read(project)
 if not PeakZoom.supported() then return nil,'ピーク表示の調整にはSWS Extensionが必要です。' end
 if project~=R.EnumProjects(-1,'') then return nil,'プロジェクトが切り替わったため、ピーク表示の操作を終了しました。' end
 local ok,gain
 if type(R.SNM_GetDoubleConfigVarEx)=='function' then ok,gain=pcall(R.SNM_GetDoubleConfigVarEx,project,PeakZoom.key,-1)
 else ok,gain=pcall(R.SNM_GetDoubleConfigVar,PeakZoom.key,-1) end
 if not ok or not finite(gain) or gain<=0 then return nil,'ピーク表示の設定を取得できません。' end
 return gain
end
function PeakZoom.write(project,gain)
 if project~=R.EnumProjects(-1,'') then return false end
 local ok,result
 if type(R.SNM_SetDoubleConfigVarEx)=='function' then ok,result=pcall(R.SNM_SetDoubleConfigVarEx,project,PeakZoom.key,gain)
 elseif type(R.SNM_SetDoubleConfigVar)=='function' then ok,result=pcall(R.SNM_SetDoubleConfigVar,PeakZoom.key,gain)
 else return false end
 return ok and result==true
end
function PeakZoom.poll(force)
 local now=R.time_precise();local project=R.EnumProjects(-1,'')
 local switched=project~=PeakZoom.project
 if not force and not switched and now<PeakZoom.nextPoll then return end
 PeakZoom.nextPoll=now+.15
 if switched then PeakZoom.drag=nil end
 local gain,problem=PeakZoom.read(project)
 if switched or gain~=PeakZoom.gain or problem~=PeakZoom.problem then
  PeakZoom.project=project;PeakZoom.gain=gain;PeakZoom.problem=problem;PeakZoom.available=gain~=nil
  PeakZoom.db=gain and 20*math.log(gain,10) or nil
  PeakZoom.text=PeakZoom.db and string.format('%.1f dB',abs(PeakZoom.db)<.05 and 0 or PeakZoom.db) or '—'
  wake_visuals()
 end
end
function PeakZoom.set(value,project)
 if not finite(value) then return nil,'数値が不正です。' end
 project=project or R.EnumProjects(-1,'')
 -- Finalize the preceding item-wheel edit before touching a different control.
 WheelUndo.finish()
 local old,err=PeakZoom.read(project);if not old then PeakZoom.poll(true);return nil,err end
 local db=floor(clamp(value,PeakZoom.min,PeakZoom.max)*10+.5)/10
 local gain=10^(db/20)
 if abs(old-gain)<=1e-12*max(1,gain) then PeakZoom.poll(true);return true end
 if not PeakZoom.write(project,gain) then PeakZoom.poll(true);return nil,'ピーク表示の設定を変更できません。' end
 local actual=PeakZoom.read(project)
 if not actual or abs(20*math.log(actual,10)-db)>1e-5 then
  -- Restore this display preference only; never touch item/take volume or history.
  PeakZoom.write(project,old);R.UpdateArrange();PeakZoom.poll(true)
  return nil,'ピーク表示の設定を変更できません。'
 end
 R.UpdateArrange();PeakZoom.poll(true)
 return true
end
function PeakZoom.apply(value,project)
 local ok,err=PeakZoom.set(value,project)
 if not ok then PeakZoom.drag=nil;A.flash.peak_zoom=R.time_precise()+.5;status(err,true);wake_visuals() end
 return ok
end
function PeakZoom.at(x,y)
 return PeakZoom.x and x>=PeakZoom.x and x<PeakZoom.x+PeakZoom.w and y>=PeakZoom.y and y<=PeakZoom.y+39
end
function PeakZoom.fraction()
 return clamp((PeakZoom.db or 0)/PeakZoom.max,0,1)
end
function PeakZoom.capture(cap,down)
 local d=PeakZoom.drag;if not d then return false end
 local flags=gfx.getchar(65536);local focused=(flags&1)==0 or (flags&2)~=0
 if d.project~=R.EnumProjects(-1,'') or d.x~=PeakZoom.x or d.w~=PeakZoom.w or d.y~=PeakZoom.y
    or not focused or BLT.presets.open or E then
  PeakZoom.drag=nil;wake_visuals();return true
 end
 if not down then PeakZoom.drag=nil;wake_visuals();return true end
 if gfx.mouse_x~=d.mouse then
  local factor=(cap&8)~=0 and .1 or 1
  d.value=clamp(d.value+(gfx.mouse_x-d.mouse)*PeakZoom.max/PeakZoom.railW*factor,PeakZoom.min,PeakZoom.max)
  d.mouse=gfx.mouse_x;PeakZoom.apply(d.value,d.project)
 end
 return true
end
function PeakZoom.input(cap,down,right)
 if gesture or not PeakZoom.at(gfx.mouse_x,gfx.mouse_y) then return false end
 local wheel=gfx.mouse_wheel or 0
 if (down and not downLast) or wheel~=0 then
  WheelUndo.finish();PeakZoom.poll(true)
  if not PeakZoom.available then status(PeakZoom.problem,true);wake_visuals();return true end
 end
 if down and not downLast then
  if (cap&4)~=0 then PeakZoom.apply(0,PeakZoom.project)
  elseif gfx.mouse_y>=PeakZoom.y+24 then
   local value=clamp(PeakZoom.db,PeakZoom.min,PeakZoom.max)
   local thumb=PeakZoom.railX+PeakZoom.fraction()*PeakZoom.railW
   if abs(gfx.mouse_x-thumb)>7 and (cap&8)==0 then
    value=clamp((gfx.mouse_x-PeakZoom.railX)/PeakZoom.railW,0,1)*PeakZoom.max
    if not PeakZoom.apply(value,PeakZoom.project) then return true end
   end
   PeakZoom.drag={project=PeakZoom.project,mouse=gfx.mouse_x,value=value,x=PeakZoom.x,y=PeakZoom.y,w=PeakZoom.w}
   wake_visuals()
  end
 elseif wheel~=0 and not down then
  if (gfx.getchar(65536)&2)==0 and R.JS_Mouse_GetState then
   local ok,state=pcall(R.JS_Mouse_GetState,8)
   if ok and type(state)=='number' then cap=(cap&(~8))|(floor(state)&8) end
  end
  local ticks=max(1,floor(abs(wheel)/120+.5))*(wheel>0 and 1 or -1)
  PeakZoom.apply((PeakZoom.db or 0)+ticks*((cap&8)~=0 and .1 or 1),PeakZoom.project)
 end
 return true
end

local function poll(force)
 PeakZoom.poll(force)
 local now=R.time_precise();if not force and (now<A.nextPoll or E or gesture) then return end
 A.nextPoll=now+.15
 local project=R.EnumProjects(-1,'');local rev=R.GetProjectStateChangeCount(project)
 local count=R.CountSelectedMediaItems(project);local ids=A.selection
 local changed=force or project~=A.project or rev~=A.revision or count~=#ids
 for i=1,count do
  local item=R.GetSelectedMediaItem(project,i-1)
  if ids[i]~=item then changed=true;ids[i]=item end
 end
 for i=#ids,count+1,-1 do ids[i]=nil end
 if changed then
  A.items,A.count,A.mixed,A.hasMidi=Core.display(project,ids);A.project=project;A.revision=rev
  A.display={};local first=A.items[1]
  for _,f in ipairs(fields) do A.display[f.key]=(f.key=='length' and first) and length_text(first.length,first.pos) or Core.format(f.key,first and first[f.key]) end
  wake_visuals()
 elseif (lengthMode==-1 or lengthMode==6) and A.items[1] then
  local first=A.items[1];local shown=length_text(first.length,first.pos)
  if A.display.length~=shown then A.display.length=shown;wake_visuals() end
 end
end
local function fail(key,message)
 A.flash[key]=R.time_precise()+.5;status(message,true);wake_visuals()
end
local function apply_value(snapshot,key,value,absolute)
 local revision=R.GetProjectStateChangeCount(snapshot.project)
 WheelUndo.finish()
 if snapshot.revision==revision then snapshot.revision=R.GetProjectStateChangeCount(snapshot.project) end
 if key=='reverse' and not Media.ready() then fail(key,'音声がオンラインになるまでお待ちください。');return false end
 local n,err=Core.apply(snapshot,key,value,absolute)
 if not n then fail(key,err);return false end
 poll(true);wake_visuals();return true
end
local function finish_edit(cancel,absolute)
 if not E then return true end
 local e=E;E=nil;IME.active=false;IME.ctx=nil;IME.font=nil
 if cancel then wake_visuals();return true end
 local value,err
 if e.key=='length' then
  if lengthMode==6 then local n=tonumber(e.text);if finite(n) then value=n/frame_rate() end
  elseif e.text:match('^[%d%s:%.%+%-%[%]%(%)|/]+$') then value=R.parse_timestr_len(e.text,e.snapshot.rows[1].pos,lengthMode) end
  if not finite(value) or value<Core.specs.length.lo or value>Core.specs.length.hi then value=nil;err='数値が範囲外です。元の値を保持しました。' end
 else value,err=Core.parse(e.key,e.text) end
 if value==nil then fail(e.key,err);return false end
 return apply_value(e.snapshot,e.key,value,absolute==true)
end
local Dock={state=0}
local function open_edit(f)
 WheelUndo.finish()
 if not BLT.requireInput(IME) then return end
 local snapshot=Core.snapshot();local first=snapshot.rows[1]
 if not first or first[f.key]==nil then fail(f.key,'この項目は選択アイテムでは編集できません。');return end
 local value=first[f.key]
 if Core.specs[f.key] then value=Core.control_value(f.key,value) end
 if f.key=='length' then value=length_text(value,first.pos) end
 E={key=f.key,text=tostring(value),snapshot=snapshot,bounds={x=f.x+3,y=((Dock.state&1)~=0 and 14 or 42),w=f.w-6,h=25},absolute=false}
 local ok,err=pcall(function()
  local I=IME.api;IME.ctx=I.CreateContext('BLT MINIMAL INFO PANEL input');IME.font=I.CreateFont(fonts[f.key=='name' and 1 or 3]);I.Attach(IME.ctx,IME.font)
  IME.active=true;IME.frames=0
 end)
 if not ok then finish_edit(true);fail(f.key,tostring(err)) end
 wake_visuals()
end
local function rgba(c,a) return (floor(c[1]*255+.5)<<24)|(floor(c[2]*255+.5)<<16)|(floor(c[3]*255+.5)<<8)|floor((a or 1)*255+.5) end
local function ime_frame()
 if not E or not IME.active then return end
 local I,ctx,b=IME.api,IME.ctx,E.bounds
 local nx,ny=gfx.clienttoscreen(b.x,b.y);local ex,ey=gfx.clienttoscreen(b.x+b.w,b.y+b.h)
 local x,y=I.PointConvertNative(ctx,nx,ny);local x2,y2=I.PointConvertNative(ctx,ex,ey)
 local w,h=abs(x2-x),abs(y2-y);x,y=min(x,x2),min(y,y2)
 local focus=IME.frames==1
 I.SetNextWindowPos(ctx,x,y,I.Cond_Always);I.SetNextWindowSize(ctx,w,h,I.Cond_Always)
 if focus then I.SetNextWindowFocus(ctx) end
 I.PushStyleVar(ctx,I.StyleVar_WindowPadding,0,0);I.PushStyleVar(ctx,I.StyleVar_WindowMinSize,1,1)
 I.PushStyleVar(ctx,I.StyleVar_WindowRounding,0);I.PushStyleVar(ctx,I.StyleVar_WindowBorderSize,0)
 I.PushStyleVar(ctx,I.StyleVar_FramePadding,4,1)
 I.PushStyleColor(ctx,I.Col_WindowBg,rgba(C.field));I.PushStyleColor(ctx,I.Col_FrameBg,rgba(C.field));I.PushStyleColor(ctx,I.Col_Text,rgba((A.count or 0)>1 and C.warn or C.text))
 I.PushFont(ctx,IME.font,16)
 local flags=I.WindowFlags_NoDecoration|I.WindowFlags_NoMove|I.WindowFlags_NoSavedSettings|I.WindowFlags_NoDocking
 local shown=I.Begin(ctx,'##item_strip_'..E.key,nil,flags)
 local done,cancel,focused=false,false,true
 if shown then
  I.SetNextItemWidth(ctx,w);if focus then I.SetKeyboardFocusHere(ctx) end
  local _,text=I.InputText(ctx,'##value',E.text,I.InputTextFlags_AutoSelectAll)
  E.text=text -- Preserve edits before deactivation (including paste then outside click).
  local mods=I.GetKeyMods(ctx);E.absolute=(mods&I.Mod_Ctrl)~=0 or ((gfx.mouse_cap or 0)&4)~=0 or (BLT_MAC and (mods&I.Mod_Super)~=0)
  cancel=I.IsKeyPressed(ctx,I.Key_Escape,false)
  done=I.IsItemDeactivated(ctx) or I.IsKeyPressed(ctx,I.Key_Enter,false) or I.IsKeyPressed(ctx,I.Key_KeypadEnter,false)
  focused=I.IsWindowFocused(ctx);I.End(ctx)
 end
 I.PopFont(ctx);I.PopStyleColor(ctx,3);I.PopStyleVar(ctx,5)
 IME.frames=IME.frames+1
 if cancel then finish_edit(true)
 elseif IME.frames>2 and (done or not focused) then local absolute=E.absolute;finish_edit(false,absolute) end
end
local layoutWidth=nil
local function row_y() return (Dock.state&1)~=0 and 0 or 28 end
local function layout()
 local isDocked=(Dock.state&1)~=0
 local signature=table.concat({gfx.w,isDocked and 1 or 0,Dock.left or 0,Dock.right or 1},':')
 if layoutWidth==signature then return end
 layoutWidth=signature
 local fixed=(#fields-1)*6+PeakZoom.width+PeakZoom.gap
 for _,f in ipairs(fields) do fixed=fixed+(f.width or 0) end
 local left,right=0,gfx.w
 if isDocked then
  local b=BLT.ui.bar(gfx.w);local origin=b.titleEnd;local width=max(1,b.presetX-origin);local minimum=min(width,fixed+80+24)
  Dock.areaLeft,Dock.areaWidth=origin,width
  local l=clamp(Dock.left or 0,0,1)*width;local r=clamp(Dock.right or 1,0,1)*width
  local span=clamp(r-l,minimum,width)
  left=origin+clamp((l+r-span)/2,0,width-span);right=left+span
  Dock.pixelLeft,Dock.pixelRight,Dock.minSpan=left,right,minimum
 end
 local content=max(1,right-left-24)
 local fit=min(1,content/(fixed+80))
 local x=left+12
 for _,f in ipairs(fields) do
  f.x=x;f.w=f.width and f.width*fit or max(80*fit,content-fixed*fit)
  x=x+f.w+6*fit
 end
 PeakZoom.x=x+(PeakZoom.gap-6)*fit;PeakZoom.w=PeakZoom.width*fit;PeakZoom.y=row_y()
 PeakZoom.separator=PeakZoom.x-PeakZoom.gap*fit/2
 local inset=min(10,PeakZoom.w*.08)
 PeakZoom.railX=PeakZoom.x+inset;PeakZoom.railW=max(1,PeakZoom.w-inset*2)
end
local function bar_at(x,y)
 if (Dock.state&1)==0 or y<0 or y>39 then return nil end
 layout()
 if x>=Dock.pixelLeft and x<Dock.pixelLeft+10 then return 'left' end
 if x>Dock.pixelRight-10 and x<=Dock.pixelRight then return 'right' end
end
local function draw_bars()
 if (Dock.state&1)==0 then return end
 local hot=bar_at(gfx.mouse_x,gfx.mouse_y)
 for _,side in ipairs({'left','right'}) do
  local x=side=='left' and Dock.pixelLeft+3 or Dock.pixelRight-6
  local active=hot==side or Dock.barDrag and Dock.barDrag.side==side
  rect(x,3,3,33,active and C.accent2 or C.edge2,active and .95 or .65)
  if active then rect(x-2,1,7,37,C.accent2,.1) end
 end
end
local function bar_input(down)
 if (Dock.state&1)==0 then Dock.barDrag=nil;return false end
 local hit=bar_at(gfx.mouse_x,gfx.mouse_y)
 if hit and not gesture and not PeakZoom.drag then set_resize_cursor('l') end
 if down and not downLast and hit and not gesture and not PeakZoom.drag then
  if E and not finish_edit(false,E.absolute) then downLast=down;return true end
  Dock.barDrag={side=hit,x=gfx.mouse_x,left=Dock.pixelLeft,right=Dock.pixelRight,width=Dock.areaWidth,origin=Dock.areaLeft}
 end
 local d=Dock.barDrag
 if not d then return false end
 local width=Dock.areaWidth
 if width~=d.width or Dock.areaLeft~=d.origin then
  Dock.barDrag=nil;downLast=down;layoutWidth=nil;wake_visuals();return true
 end
 local l,r=d.left,d.right;local dx=gfx.mouse_x-d.x
 if d.side=='left' then l=clamp(l+dx,d.origin,r-Dock.minSpan)
 else r=clamp(r+dx,l+Dock.minSpan,d.origin+width) end
 Dock.left,Dock.right=(l-d.origin)/width,(r-d.origin)/width;layoutWidth=nil;layout();wake_visuals()
 gfx.mouse_wheel=0;downLast=down
 if not down then
  Dock.barDrag=nil
  BLT.store(SECTION,'dock_row_left',tostring(Dock.left),true)
  BLT.store(SECTION,'dock_row_right',tostring(Dock.right),true)
 end
 return true
end
local function field_at(x,y)
 local top=row_y()
 if y<top or y>top+39 then return nil end
 for _,f in ipairs(fields) do if f.x and f.w and x>=f.x and x<f.x+f.w then return f end end
end
function PeakZoom.draw()
 local x,y,w=PeakZoom.x,PeakZoom.y,PeakZoom.w
 local enabled=PeakZoom.available;local hot=PeakZoom.at(gfx.mouse_x,gfx.mouse_y) and not E and not BLT.blocked() and not Chrome.mouseActive
 local active=hot or PeakZoom.drag~=nil
 local flash=(A.flash.peak_zoom or 0)>R.time_precise()
 local tint=enabled and C.green or C.faint
 line(PeakZoom.separator,y+3,PeakZoom.separator,y+36,C.edge2,.52)
 cut_panel(x,y,w,39,4,C.panel,.65,flash and C.red or tint,flash and .9 or .32)
 if active and enabled then rect(x+1,y+1,w-2,37,C.hover,.09) end
 -- Separate text rows retain the full label without widening this view control.
 local size=w>=87 and 9 or 8;local pad=min(3,w*.02);local textW=max(1,w-pad*2)
 label('ピーク表示ズーム率',x+pad,y+1,textW,12,size,tint,true,0)
 label(PeakZoom.text or '—',x+pad,y+12,textW,12,w>=80 and 10 or 9,enabled and C.text or C.faint,false,6,3,true)
 local rx,rw=PeakZoom.railX,PeakZoom.railW;local cy=y+31
 rect(rx,cy-2,rw,4,C.bg,1)
 local f=PeakZoom.fraction()
 if enabled and f>0 then rect(rx,cy-2,rw*f,4,tint,active and .90 or .68) end
 line(rx,cy+3,rx+rw,cy+3,C.edge,.40)
 for i=0,6 do local tx=rx+rw*i/6;line(tx,cy+5,tx,cy+7,C.edge2,.34) end
 local thumb=rx+rw*f
 if active and enabled then rect(thumb-5,cy-8,10,16,C.hover,.12) end
 rect(thumb-3,cy-6,6,12,enabled and (active and C.accent2 or tint) or C.faint,.95)
 line(thumb,cy-4,thumb,cy+4,C.bg,.55)
end
local disabledPanel={.025,.025,.025}
local disabledInk={.24,.24,.24}
local function draw()
 scale,ox,oy=1,0,0;mx,my=gfx.mouse_x,gfx.mouse_y;layout()
 rect(0,0,gfx.w,gfx.h,C.bg)
 local top=row_y()
 local first=A.items[1]
 for _,f in ipairs(fields) do
  local value=first and first[f.key];local disabled=f.key=='reverse' and A.hasMidi
  local enabled=value~=nil and not disabled
  local hot=not disabled and mx>=f.x and mx<f.x+f.w and my>=top and my<=top+39
  local flash=not disabled and (A.flash[f.key] or 0)>R.time_precise()
  local on=not disabled and f.check and value==true
  local mixed=not disabled and f.check and A.mixed and A.mixed[f.key]
  local multi=(A.count or 0)>1
  cut_panel(f.x,top,f.w,39,4,disabled and disabledPanel or on and C.panel2 or C.field,1,disabled and disabledInk or flash and C.red or (on and C.accent2 or C.edge2),flash and .9 or (on and .65 or hot and .45 or .2))
  label(f.label,f.x+(f.check and 2 or 7),top+1,f.w-(f.check and 4 or 14),12,(f.check and 7 or 9),disabled and disabledInk or enabled and (multi and C.warn or C.muted) or C.faint,true)
  if f.check then
   local cx=f.x+(f.w-16)/2
   rect(cx,top+18,16,16,disabled and disabledPanel or on and not mixed and C.accent2 or C.bg)
   color(disabled and disabledInk or mixed and C.warn or (on and C.accent2 or C.edge2));gfx.rect(cx,top+18,16,16,0)
   local icon=f.key=='reverse' and 'R' or f.key=='mute' and 'M' or 'L'
   if mixed then rect(cx+3,top+25,10,2,C.warn)
   elseif on then label(icon,cx,top+18,16,16,12,not enabled and C.faint or C.bg,true,5,2,true) end
  else
   local shown=A.display and A.display[f.key] or '—'
   if f.key=='name' and value=='' then shown=Language.text('（名前なし）') end
   if gesture and gesture.key==f.key and gesture.moved then shown=f.key=='length' and length_text(gesture.value,first.pos) or Core.format(f.key,gesture.value) end
   label(shown,f.x+7,top+15,f.w-14,23,16,enabled and (multi and C.warn or C.text) or C.faint,false,0,f.key=='name' and 1 or 3,true)
  end
 end
 PeakZoom.draw()
 draw_bars()
 BLT.bar()
end
local function interact()
 WheelUndo.poll(R.time_precise())
 local cap=gfx.mouse_cap or 0;local down=(cap&1)~=0;local right=(cap&2)~=0
 if PeakZoom.capture(cap,down) then downLast=down;A.rightLast=right;gfx.mouse_wheel=0;return end
 if not BLT.blocked() and not Chrome.mouseActive and bar_input(down) then A.rightLast=right;return end
 if E then downLast=down;A.rightLast=right;gfx.mouse_wheel=0;return end
 if BLT.blocked() or Chrome.mouseActive then
  if gesture then gesture=nil;wake_visuals() end
  downLast=down;A.rightLast=right;gfx.mouse_wheel=0;return
 end
 if PeakZoom.input(cap,down,right) then downLast=down;A.rightLast=right;gfx.mouse_wheel=0;return end
 local f=field_at(gfx.mouse_x,gfx.mouse_y)
 if right and not A.rightLast and f and Core.specs[f.key] then
  if f.key=='length' then
   local modes={3,0,4,5,6,2,-1};local names=Language.code=='JP' and {'秒','分秒','サンプル','時:分:秒:フレーム','フレーム','小節.拍','ルーラーと連動'} or {'Seconds','Time','Samples','Timecode (h:m:s:f)','Frames','Measures.beats','Follow ruler'}
   for i,m in ipairs(modes) do if m==lengthMode then names[i]='!'..names[i] end end
   gfx.x=gfx.mouse_x;gfx.y=gfx.mouse_y
   local choice=gfx.showmenu(table.concat(names,'|'))
   if modes[choice] then lengthMode=modes[choice];save_settings();poll(true)
   end
   gfx.mouse_wheel=0;A.rightLast=true;downLast=false;return
  end
 end
 A.rightLast=right
 if down and not downLast and f and not (f.key=='reverse' and A.hasMidi) then
  local snap=Core.snapshot();local first=snap.rows[1]
  if first and first[f.key]~=nil then
   gesture={key=f.key,field=f,snapshot=snap,start=first[f.key],value=first[f.key],x=gfx.mouse_x,y=gfx.mouse_y,moved=false,reset=(cap&4)~=0}
  elseif f.key=='reverse' and not R.BR_GetMediaSourceProperties then fail(f.key,'逆再生の切り替えにはSWS Extensionが必要です。') end
 elseif down and gesture and Core.specs[gesture.key] then
  local dy=gesture.y-gfx.mouse_y;local dx=gfx.mouse_x-gesture.x
  if abs(dx)+abs(dy)>3 then gesture.moved=true end
  if gesture.moved then
   local delta=abs(dx)>abs(dy) and dx or dy
   local ticks=(delta<0 and -1 or 1)*floor(abs(delta)/4)
   gesture.value=Core.adjust_value(gesture.key,gesture.snapshot.rows[1],ticks,(cap&8)~=0)
   wake_visuals()
  end
 elseif not down and downLast and gesture then
  local g=gesture;gesture=nil
  if g.moved then apply_value(g.snapshot,g.key,g.value,(cap&4)~=0)
  elseif f and f.key==g.key then
   if (g.reset or (cap&4)~=0) and (g.key=='volume' or g.key=='pitch' or g.key=='pan' or g.key=='rate') then
    apply_value(g.snapshot,g.key,g.key=='rate' and 1 or 0,true)
   elseif f.check then apply_value(g.snapshot,g.key,not g.start,true) else open_edit(f) end
  end
 end
 downLast=down
 local wheel=gfx.mouse_wheel or 0
 if wheel~=0 then
  if (gfx.getchar(65536)&2)==0 and R.JS_Mouse_GetState then
   local ok,state=pcall(R.JS_Mouse_GetState,8)
   if ok and type(state)=='number' then cap=(cap&(~8))|(math.floor(state)&8) end
  end
  if f and Core.specs[f.key] and not gesture then
   local ticks=max(1,floor(abs(wheel)/120+.5))*(wheel>0 and 1 or -1)
   local n,err=WheelUndo.apply(f.key,ticks,(cap&8)~=0,(cap&4)~=0)
   if not n then fail(f.key,err) else poll(true);wake_visuals() end
  end
  gfx.mouse_wheel=0
 end
end
local function initial_dock_state()
 local saved=extnum('dock_state',-1)
 if saved>=0 then return math.floor(clamp(saved,0,3841))&0xF01 end
 if R.DockGetPosition then
  for index=0,15 do
   if R.DockGetPosition(index)==2 then return index<<8 end
  end
 end
 return 0
end
local function docked() return (Dock.state&1)~=0 end
local function save_float()
 local hwnd=gfx_window_handle()
 local ok,x,y,r,b=WindowGeometry.JS_Window_GetRect(hwnd)
 if ok then
  Dock.floating={x=x,y=y,w=r-x,h=A.menuHeight or b-y}
  for k,v in pairs(Dock.floating) do BLT.store(SECTION,'float_'..k,tostring(v),true) end
  local _,gx,gy,gw,gh=gfx.dock(-1,0,0,0,0)
  for k,v in pairs({x=gx,y=gy,w=gw,h=A.menuHeight or gh}) do
   if finite(v) then BLT.store(SECTION,'window_'..k,tostring(v),true) end
  end
 end
end
local function sync_dock()
 local state=gfx.dock(-1)
 if state~=Dock.state then
  local was=docked();Dock.state=state;Dock.barDrag=nil;PeakZoom.drag=nil;layoutWidth=nil
  BLT.store(SECTION,'dock_state',state,true)
  Chrome.drag=nil;Chrome.resize=nil;Chrome.window=nil;BLT.lastRect=nil
  if was and not docked() then
   local f=Dock.floating
   apply_custom_window_style(f and f.w or W,f and f.h or H+26)
   if f then BLT.lastRect=nil;BLT.position(gfx_window_handle(),f.x,f.y,f.w,f.h,'','') end
  end
  wake_visuals()
 end
 if Dock.w~=gfx.w or Dock.h~=gfx.h then if E then finish_edit(false,E.absolute) end;Dock.w,Dock.h=gfx.w,gfx.h;wake_visuals() end
end
local function toggle_dock()
 WheelUndo.finish()
 if E and not finish_edit(false,E.absolute) then return end
 gesture=nil;Dock.barDrag=nil;PeakZoom.drag=nil
 if not docked() then save_float() end
 A.menuHeight=nil;BLT.presets.dismiss();set_resize_cursor(nil)
 gfx.dock(Dock.state~1)
 sync_dock()
end
-- Shared BLT app restoration protocol. Each app owns one registry ID.
local BLTRestore={section='BLT_APP_RESTORE',id='BLT_MINIMAL_INFO_PANEL'}
local BLTRestoreLauncher=[=[
local r=reaper
local section='BLT_APP_RESTORE'
if r.GetExtState(section,'startup_done')=='1'then return end
r.SetExtState(section,'startup_done','1',false)
r.defer(function()
 local count=math.min(128,tonumber(r.GetExtState(section,'count'))or 0)
 for i=1,count do
  local id=r.GetExtState(section,'app_'..i)
  if id~=''and r.GetExtState(section,id..'_open')=='1'and r.GetExtState(section,id..'_running')~='1'then
   local ok,err=pcall(function()
    local path=r.GetExtState(section,id..'_path')
    local f=io.open(path,'rb');if not f then return end;f:close()
    local command=r.NamedCommandLookup(r.GetExtState(section,id..'_command'))
    if command==0 then command=r.AddRemoveReaScript(true,0,path,true)end
    if command and command>0 then r.Main_OnCommand(command,0)end
   end)
   if not ok then r.ShowConsoleMsg('BLT restore: '..id..': '..tostring(err)..'\n')end
  end
 end
end)
]=]
local function restore_read(path)
 local f=io.open(path,'rb');if not f then return nil end
 local data=f:read('*a');f:close();return data
end
local function restore_write_bytes(path,data)
 local f,err=io.open(path,'wb');assert(f,err)
 local ok,why=f:write(data);local closed,closeError=f:close()
 assert(ok and closed,why or closeError or'BLT startup write failed')
 assert(restore_read(path)==data,'BLT startup verification failed: '..path)
end
local function restore_write(path,data)
 local previous=restore_read(path)
 if previous==data then return end
 if previous then
  local backup=path..'.blt-backup';local suffix=0
  while restore_read(backup)and restore_read(backup)~=previous do suffix=suffix+1;backup=path..'.blt-backup-'..suffix end
  if not restore_read(backup)then restore_write_bytes(backup,previous)end
 end
 local ok,err=pcall(restore_write_bytes,path,data)
 if not ok then
  if previous then
   local restored,why=pcall(restore_write_bytes,path,previous)
   if not restored then error(tostring(err)..'\nBLT startup restoration failed: '..tostring(why))end
  end
  error(err)
 end
 if os.remove then os.remove(path..'.blt-tmp')end
end
function BLTRestore.start(api)
 local section,id=BLTRestore.section,BLTRestore.id
 local _,path,actionSection,command=api.get_action_context()
 assert(actionSection==0 and path~='','BLT restore requires a Main action')
 local root=api.GetResourcePath()..'/Scripts'
 api.RecursiveCreateDirectory(root..'/BLT',0)
 restore_write(root..'/BLT/BLT_Restore_Open_Apps.lua',BLTRestoreLauncher)
 local startup=root..'/__startup.lua';local original=restore_read(startup)or''
 local marker='-- BLT_APP_RESTORE_STARTUP'
 if not original:find(marker,1,true)then
  local block=marker..'\ndo\n local path=reaper.GetResourcePath().."/Scripts/BLT/BLT_Restore_Open_Apps.lua"\n local fn=loadfile(path)\n if fn then local ok,err=pcall(fn);if not ok then reaper.ShowConsoleMsg(tostring(err).."\\n")end end\nend\n'
  restore_write(startup,block..original:gsub('^\239\187\191',''))
 end
 local count=math.min(128,tonumber(api.GetExtState(section,'count'))or 0);local found=false
 for i=1,count do if api.GetExtState(section,'app_'..i)==id then found=true;break end end
 if not found then assert(count<128,'BLT restore registry is full');api.SetExtState(section,'app_'..(count+1),id,true);api.SetExtState(section,'count',tostring(count+1),true)end
 api.SetExtState(section,id..'_path',path,true)
 local named=api.ReverseNamedCommandLookup(command)or''
 api.SetExtState(section,id..'_command',named~=''and'_'..named:gsub('^_','')or'',true)
 api.SetExtState(section,id..'_open','1',true)
 api.SetExtState(section,id..'_running','1',false)
 BLTRestore.started=true
end
function BLTRestore.finish(api,manual)
 if not BLTRestore.started then return end
 if manual then api.SetExtState(BLTRestore.section,BLTRestore.id..'_open','0',true)end
 api.SetExtState(BLTRestore.section,BLTRestore.id..'_running','',false)
 BLTRestore.started=false
end

local function close()
 BLTRestore.finish(R,A.manualClose or Chrome.requestClose)
 WheelUndo.finish()
 if A.closed then return end
 PeakZoom.drag=nil
 finish_edit(true);gesture=nil;Dock.barDrag=nil;BLT.store(SECTION,'dock_row_left',tostring(Dock.left or 0),true);BLT.store(SECTION,'dock_row_right',tostring(Dock.right or 1),true);save_settings();titlebar_cleanup();clear_chrome_tooltip()
 BLT.store(SECTION,'dock_state',gfx.dock(-1),true)
 if not docked() then save_float() end
 A.closed=true;gfx.quit()
end
local function prepare_menu()
 WheelUndo.finish()
 if E and not finish_edit(false,E.absolute) then return false end
 if gfx.h<360 then
  local hwnd=gfx_window_handle();local ok,l,t=WindowGeometry.JS_Window_GetRect(hwnd)
  if ok then A.menuHeight=gfx.h;BLT.position(hwnd,l,t,gfx.w,360,'','') end
 end
 return true
end
local function restore_menu_size()
 if A.menuHeight and not BLT.presets.open and not BLT.presets.swallow then
  local h=A.menuHeight;A.menuHeight=nil
  local hwnd=gfx_window_handle();local ok,l,t=WindowGeometry.JS_Window_GetRect(hwnd)
  if ok then BLT.position(hwnd,l,t,gfx.w,h,'','') end
 end
end
local function tooltip(x,y)
 if bar_at(x,y) then return Language.code=='JP' and 'ドラッグ：項目の左右端を調整' or 'Drag to adjust the row edges' end
 if E then return nil end
 if PeakZoom.at(x,y) then return nil end
 local f=field_at(x,y);if not f then return nil end
 if f.key=='reverse' and A.hasMidi then return Language.code=='JP' and 'MIDIアイテムを含む選択では逆再生を変更できません。' or 'Reverse is unavailable when the selection includes MIDI.' end
 if f.check then return Language.code=='JP' and 'クリックで全選択を同じON / OFFに設定' or 'Click to set all selected items ON / OFF' end
 if f.key=='rate' then return Language.code=='JP' and '再生速度（半音換算） · ホイール: 次の1 st位置（Shift: 0.1 st） · Ctrl+クリック: 1.0\n半音換算は速度比の参考値です。ピッチ維持設定は保持し、アイテムの長さは速度に追従します。' or 'Playback rate · Wheel: next semitone (Shift: 0.1 st) · Ctrl (Cmd)+click: 1.0\nPitch preservation stays unchanged; item length follows the rate.' end
 if f.key=='length' then return Language.code=='JP' and '右クリック: 尺度を選択 · 入力も選択した尺度を使用' or 'Right-click: units · Input uses selected units' end
 if f.key=='name' then
  local name=A.items[1] and A.items[1].name or ''
  return name..'\n'..(Language.code=='JP' and 'クリックして入力 · 複数選択は同名に変更' or 'Click to type · Rename all selected takes')
 end
 return Language.code=='JP' and ('入力 / ホイール / ドラッグ · Shift: 1/10 · Ctrl: 絶対値 · Ctrl+クリック: 初期値')
  or ('Type / Wheel / Drag · Shift: 1/10 · Ctrl (Cmd): absolute · Ctrl (Cmd)+click: reset')
end
Media.state=A;Media.onchange=function() wake_visuals() end
BLT.attach({R=R,C=C,Chrome=Chrome,Chameleon=Chameleon,section=SECTION,faces=fonts,font=font,
 docked=docked,fold=function() Chrome.requestDock=true end,geometry=function() return 1,0,0 end,active=function() local f=gfx.getchar(65536);return (f&1)==0 or (f&2)~=0 end,
 wake=function() wake_visuals();A.content_dirty=true end,defaults=Core.defaults,capture=function() return S end,
 valid=Core.valid_settings,apply=function(v) S=BLT.copy(v);lengthMode=S.lengthMode;save_settings();poll(true);wake_visuals() end,
 beforeKey=function(k) if k>0 then WheelUndo.finish() end end,
 undoBefore=function() WheelUndo.finish();finish_edit(true);gesture=nil end,undoRefresh=function() poll(true) end,
 busy=function() return gesture~=nil or PeakZoom.drag~=nil end,commit=function() WheelUndo.finish();return not E or finish_edit(false,E.absolute) end,
 cancelEdit=function() WheelUndo.finish();finish_edit(true);gesture=nil;PeakZoom.drag=nil end,editing=function() return E~=nil end,modal=function() return false end,
 handle=gfx_window_handle,resizeHit=chrome_resize_hit,cursor=set_resize_cursor,beginResize=begin_window_resize,resize=update_window_resize,prepareMenu=prepare_menu,tip=tooltip})
function BLT.testDraw() draw() end
local function loop_body()
 WheelUndo.poll(R.time_precise())
 sync_dock();local now=R.time_precise();BLT.tick(now);Chameleon.tick(now)
 local k=gfx.getchar();if k<0 then A.manualClose=true end;if k<0 or A.closing then close();return false end
 local n=0
 while k>0 and n<32 do
  k=BLT.key(k)
  if k==27 then if PeakZoom.drag then PeakZoom.drag=nil;downLast=(gfx.mouse_cap&1)~=0;wake_visuals() elseif Dock.barDrag then Dock.left=(Dock.barDrag.left-Dock.barDrag.origin)/Dock.barDrag.width;Dock.right=(Dock.barDrag.right-Dock.barDrag.origin)/Dock.barDrag.width;Dock.barDrag=nil;layoutWidth=nil;wake_visuals() elseif E then finish_edit(true) elseif gesture then gesture=nil;wake_visuals() else A.manualClose=true;A.closing=true end end
  k=gfx.getchar();n=n+1
 end
 poll(false);ime_frame();restore_menu_size()
 local cap=gfx.mouse_cap or 0
 local changed=gfx.mouse_x~=last_raw_mouse_x or gfx.mouse_y~=last_raw_mouse_y or cap~=last_raw_mouse_cap or (gfx.mouse_wheel or 0)~=0
 if changed or gesture or PeakZoom.drag or Dock.barDrag or Chrome.drag or Chrome.resize or E or BLT.presets.open then redraw_dirty=true end
 for key,t in pairs(A.flash) do if now>=t then A.flash[key]=nil;redraw_dirty=true end end
 if redraw_dirty or A.content_dirty then
  redraw_dirty=false;A.content_dirty=false
  draw();interact();gfx.update()
  if Chrome.requestDock then Chrome.requestDock=false;toggle_dock();wake_visuals() end
  if Chrome.requestReset then Chrome.requestReset=false;A.menuHeight=nil;reset_window_size();wake_visuals() end
  if Chrome.requestClose then A.manualClose=true;A.closing=true end
 end
 last_raw_mouse_x,last_raw_mouse_y,last_raw_mouse_cap=gfx.mouse_x,gfx.mouse_y,cap
 return true
end
local function loop()
 if A.closing then BLT.cleanup(close);return end
 local ok,continue=xpcall(loop_body,debug.traceback)
 if not ok then BLT.cleanup(WheelUndo.finish);BLT.cleanup(finish_edit,true);gesture=nil;PeakZoom.drag=nil;Dock.barDrag=nil;BLT.recoverInput(A,continue);status(BLT.publicError(continue),true) end
 if not A.closed and (not ok or continue) then R.defer(loop) end
end
Dock.left=clamp(extnum('dock_row_left',0),0,1);Dock.right=clamp(extnum('dock_row_right',1),0,1)
if Dock.right<=Dock.left then Dock.left,Dock.right=0,1 end
if ...=='blt_test' then return {initialDockState=initial_dock_state,layout=layout,barAt=bar_at,Dock=Dock,toggleDock=toggle_dock,syncDock=sync_dock,close=close,Core=Core,A=A,S=S,BLT=BLT,Media=Media,draw=draw,poll=poll,interact=interact,finishEdit=finish_edit,openEdit=open_edit,fields=fields,IME=IME,imeFrame=ime_frame,WheelUndo=WheelUndo,PeakZoom=PeakZoom,tooltip=tooltip,loopBody=loop_body} end
local ok,err=titlebar_api_ready()
if not ok then Language.mb(err,'BLT MINIMAL INFO PANEL',0);return end
gfx.ext_retina=BLT_MAC and 0 or 1
local ww=clamp(extnum('window_w',W),Chrome.minW,4000);local wh=H+26
local wx,wy=extnum('window_x',0/0),extnum('window_y',0/0)
Dock.state=initial_dock_state()
local fx,fy=extnum('float_x',0/0),extnum('float_y',0/0)
if finite(fx) and finite(fy) then Dock.floating={x=fx,y=fy,w=clamp(extnum('float_w',ww),Chrome.minW,4000),h=clamp(extnum('float_h',wh),Chrome.minH,2000)} end
if finite(wx) and finite(wy) then gfx.init(Chrome.windowTitle,ww,wh,Dock.state,wx,wy) else gfx.init(Chrome.windowTitle,ww,wh,Dock.state) end
if not docked() and not apply_custom_window_style(ww,wh) then gfx.quit();Language.mb('ウィンドウを初期化できません。','BLT MINIMAL INFO PANEL',0);return end
if not docked() and Dock.floating then local f=Dock.floating;BLT.lastRect=nil;BLT.position(gfx_window_handle(),f.x,f.y,f.w,f.h,'','') end
if Chameleon.enabled then Chameleon.refresh(true) end
poll(true)
R.atexit(function() BLT.cleanup(close) end)
if R.set_action_options then R.set_action_options(2)end
local restoreOK,restoreError=pcall(BLTRestore.start,R)
if not restoreOK then Language.mb('自動復元の登録に失敗しました。\n'..tostring(restoreError),'BLT MINIMAL INFO PANEL',0)end
loop()
