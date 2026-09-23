-- @description SPECTRAL NORMALIZER
-- @version 0.2.10
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

local reaper=create_external_storage(reaper,'BLT_SPECTRAL_NORMALIZER',debug.getinfo(1,'S').source,{'settings'})

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

local Core={VERSION='0.2.10',SECTION='BLT_SPECTRAL_NORMALIZER',MAX_POINTS=1024}
local abs,min,max,sqrt,log,pi,floor,ceil=math.abs,math.min,math.max,math.sqrt,math.log,math.pi,math.floor,math.ceil
local function clamp(x,a,b) return min(b,max(a,x)) end
local function finite(x) return type(x)=='number' and x==x and abs(x)<math.huge end
local function db(x) return 20*log(max(x,1e-15),10) end
local function amp(x) return 10^(x/20) end
Core.SCALES={'Linear','Mel','Bark','Log','Extended Log','Flat Log'}
Core.PRESETS={
 {name='Soft',strength=40,boost=12,cut=24,smooth=50},
 {name='Medium',strength=65,boost=18,cut=36,smooth=20},
 {name='Strong',strength=85,boost=24,cut=60,smooth=5},
 {name='Force',strength=100,boost=48,cut=96,smooth=0},
}
Core.PRESET_KEYS={'strength','boost','cut','smooth'}
Core.SERIAL_KEYS={'fft','overlap','strength','threshold','knee','boost','cut','smooth','ceiling','scale','maxfreq'}
Core.REQUIRED_KEYS={'fft','overlap','strength','threshold','knee','boost','cut','smooth','ceiling','scale','maxfreq','curve_kind','curve_smoothness','curve'}
Core.DRAW_LIMITS={analysis_method={1,3},period_percent={1,200},period_shape={1,3},pattern={1,6},direction={1,3},shape_envelope={1,3},height={0,200}}
for key in pairs(Core.DRAW_LIMITS) do Core.SERIAL_KEYS[#Core.SERIAL_KEYS+1]=key;Core.REQUIRED_KEYS[#Core.REQUIRED_KEYS+1]=key end
table.sort(Core.SERIAL_KEYS)
Core.PARAM_RANGES={strength={0,100},threshold={-120,0},knee={0,24},boost={0,60},cut={0,120},smooth={0,500},ceiling={-24,0}}
local function axis_raw(f,scale)
 if scale==1 then return f end
 if scale==2 then return log(1+f/700) end
 if scale==3 then local z=f/600;return log(z+sqrt(z*z+1)) end
 if scale==6 then return log(1+f/100) end
 local knee=scale==5 and 10 or 100
 return f<=knee and f/knee or 1+log(f/knee)
end
function Core.to_axis(f,scale,upper)
 return axis_raw(clamp(f,0,upper),scale)/axis_raw(upper,scale)
end
function Core.from_axis(x,scale,upper)
 local v=clamp(x,0,1)*axis_raw(upper,scale)
 if scale==1 then return v end
 if scale==2 then return 700*(math.exp(v)-1) end
 if scale==3 then return 300*(math.exp(v)-math.exp(-v)) end
 if scale==6 then return 100*(math.exp(v)-1) end
 local knee=scale==5 and 10 or 100
 return v<=1 and v*knee or knee*math.exp(v-1)
end
function Core.apply_preset(s,index)
 local p=assert(Core.PRESETS[index],'プリセット番号が不正です。')
 for _,k in ipairs(Core.PRESET_KEYS) do s[k]=p[k] end
end
function Core.preset_index(s)
 for i,p in ipairs(Core.PRESETS) do
  if s.strength==p.strength and s.boost==p.boost and s.cut==p.cut and s.smooth==p.smooth then return i end
 end
 return 0
end
function Core.defaults()
 local s={fft=4096,overlap=8,strength=100,threshold=-72,knee=6,boost=48,cut=96,smooth=0,ceiling=-1,scale=1,maxfreq=24000}
 s.analysis_method=1;s.period_percent=100;s.period_shape=1;s.pattern=1;s.direction=3;s.shape_envelope=1;s.height=100
 s.curve={points={{x=0,y=-42},{x=96000,y=-42}},kind='linear',smoothness=0}
 return s
end
function Core.copy(value)
 if type(value)~='table' then return value end
 local out={};for k,v in pairs(value) do out[k]=Core.copy(v) end;return out
end
function Core.smoothness(curve)
 if curve.kind~='smooth' then return 0 end
 return finite(curve.smoothness) and clamp(curve.smoothness,0,2) or 1
end
function Core.validate(s)
 for key,range in pairs(Core.DRAW_LIMITS) do local n=s[key];assert(finite(n) and n>=range[1] and n<=range[2] and n%1==0,'ライン設定が不正です。') end
 for k,range in pairs(Core.PARAM_RANGES) do
  assert(finite(s[k]) and s[k]>=range[1] and s[k]<=range[2],k..': 設定範囲外です。')
 end
 assert(s.fft==1024 or s.fft==2048 or s.fft==4096 or s.fft==8192 or s.fft==16384,'FFTの値が不正です。')
 assert(s.overlap==4 or s.overlap==8 or s.overlap==16,'重なりは4 / 8 / 16です。')
 assert(finite(s.scale) and s.scale%1==0 and Core.SCALES[s.scale],'尺度が不正です。')
 assert(s.maxfreq==24000 or s.maxfreq==48000 or s.maxfreq==96000,'上限は24 / 48 / 96 kHzです。')
 local curve=s.curve;assert(type(curve)=='table' and type(curve.points)=='table' and #curve.points>=2 and #curve.points<=Core.MAX_POINTS,'カーブが不正です。')
 assert(curve.kind=='linear' or curve.kind=='smooth','補完方式が不正です。');assert(finite(curve.smoothness) and curve.smoothness>=0 and curve.smoothness<=2,'滑らかさが不正です。')
 local previous=-math.huge
 for _,point in ipairs(curve.points) do
  assert(type(point)=='table' and finite(point.x) and finite(point.y) and point.x>=0 and point.x<=96000 and point.x>previous and point.y>=-120 and point.y<=0,'カーブの値が不正です。');previous=point.x
 end
 return s
end
function Core.tangent(points,i)
 if i==1 then return (points[2].y-points[1].y)/(points[2].x-points[1].x) end
 if i==#points then return (points[i].y-points[i-1].y)/(points[i].x-points[i-1].x) end
 local h0,h1=points[i].x-points[i-1].x,points[i+1].x-points[i].x;local d0,d1=(points[i].y-points[i-1].y)/h0,(points[i+1].y-points[i].y)/h1
 if d0*d1<=0 then return 0 end;local w0,w1=2*h1+h0,h1+2*h0;return (w0+w1)/(w0/d0+w1/d1)
end
function Core.interpolate(curve,x)
 local points=curve.points;if x<=points[1].x then return points[1].y elseif x>=points[#points].x then return points[#points].y end
 local lo,hi=1,#points;while hi-lo>1 do local mid=(lo+hi)//2;if points[mid].x<=x then lo=mid else hi=mid end end
 local a,b=points[lo],points[hi];local width=b.x-a.x;local u=(x-a.x)/width;local linear=a.y+(b.y-a.y)*u;local amount=Core.smoothness(curve)
 if amount==0 then return linear end
 local slope=(b.y-a.y)/width
 if abs(slope)<1e-12 then return a.y end
 local m0,m1=Core.tangent(points,lo),Core.tangent(points,hi);local aa,bb=m0/slope,m1/slope;local radius=aa*aa+bb*bb
 if radius>9 then local q=3/sqrt(radius);m0=q*aa*slope;m1=q*bb*slope end
 local curved=clamp((2*u^3-3*u*u+1)*a.y+(u^3-2*u*u+u)*width*m0+(-2*u^3+3*u*u)*b.y+(u^3-u*u)*width*m1,min(a.y,b.y),max(a.y,b.y))
 if amount<=1 then return linear+(curved-linear)*amount end
 local eased=a.y+(b.y-a.y)*(u*u*u*(10+u*(-15+6*u)));return curved+(eased-curved)*(amount-1)
end
function Core.target(curve,f) return clamp(Core.interpolate(curve,clamp(f,0,96000)),-120,0) end
function Core.add(curve,x,y)
 x,y=clamp(x,0,96000),clamp(y,-120,0)
 for i,p in ipairs(curve.points) do
  if abs(x-p.x)<1e-6 then p.y=y;return i end
  if x<p.x then table.insert(curve.points,i,{x=x,y=y});return i end
 end
 curve.points[#curve.points+1]={x=x,y=y};return #curve.points
end
function Core.stroke(curve,x0,y0,x1,y1)
 if x1<x0 then x0,x1,y0,y1=x1,x0,y1,y0 end
 local keep={};for _,p in ipairs(curve.points) do if p.x<x0-1e-6 or p.x>x1+1e-6 then keep[#keep+1]=p end end
 curve.points=keep;Core.add(curve,x0,y0);Core.add(curve,x1,y1)
end
function Core.simplify(curve,tolerance)
 local points=curve.points;if #points<3 then return end;local keep={[1]=true,[#points]=true};local stack={{1,#points}}
 while #stack>0 do local pair=table.remove(stack);local a,b=pair[1],pair[2];local worst,index=0,nil
  for i=a+1,b-1 do local u=(points[i].x-points[a].x)/max(1e-12,points[b].x-points[a].x);local error=abs(points[i].y-(points[a].y+(points[b].y-points[a].y)*u));if error>worst then worst,index=error,i end end
  if index and worst>tolerance then keep[index]=true;stack[#stack+1]={a,index};stack[#stack+1]={index,b} end
 end
 local out={};for i,p in ipairs(points) do if keep[i] then out[#out+1]=p end end;curve.points=out
end
function Core.limit_points(points,limit)
 if #points<=limit then return points end;local curve={points=points};local tolerance=.01
 repeat Core.simplify(curve,tolerance);tolerance=tolerance*1.8 until #curve.points<=limit or tolerance>120
 if #curve.points>limit then local out={};for i=0,limit-1 do out[#out+1]=curve.points[1+floor(i*(#curve.points-1)/(limit-1)+.5)] end;curve.points=out end
 return curve.points
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
  local out={}
  for _,x in ipairs(xs) do
   if #out==0 or x-out[#out].x>1e-10 then out[#out+1]={x=x,y=value(x)} end
  end
  if #out>Core.MAX_POINTS then out=Core.limit_points(out,Core.MAX_POINTS) end
  return Core.compact_pattern(out)
 end
 local xs={};local n=min(768,max(1,ceil(cycles*48)))
 for i=0,n do xs[#xs+1]=i/n end
 table.sort(xs);local points={}
 for _,x in ipairs(xs) do
  if #points==0 or x-points[#points].x>1e-10 then
  local y=math.sin(x*cycles*2*math.pi)
  local gain=envelope==2 and x or envelope==3 and 1-x or 1
  points[#points+1]={x=x,y=y*height*gain}
 end end;return Core.compact_pattern(points)
end
Core.fft_cache={}
function Core.fft_plan(n)
 local plan=Core.fft_cache[n];if plan then return plan end
 plan={swaps={},stages={}};local j=0
 for i=0,n-1 do
  if i<j then plan.swaps[#plan.swaps+1]=i+1;plan.swaps[#plan.swaps+1]=j+1 end
  local bit=n//2;while bit>0 and j>=bit do j=j-bit;bit=bit//2 end;j=j+bit
 end
 local len=2
 while len<=n do
  local angle=-2*pi/len;local cr,ci=math.cos(angle),math.sin(angle);local wr,wi=1,0;local stage={len=len,re={},im={},inverse_im={}}
  for k=1,len//2 do stage.re[k],stage.im[k],stage.inverse_im[k]=wr,wi,-wi;wr,wi=wr*cr-wi*ci,wr*ci+wi*cr end
  plan.stages[#plan.stages+1]=stage;len=len*2
 end
 Core.fft_cache[n]=plan;return plan
end
function Core.fft(re,im,inverse)
 local n=#re;local plan=Core.fft_plan(n);local swaps=plan.swaps
 for i=1,#swaps,2 do local a,b=swaps[i],swaps[i+1];re[a],re[b]=re[b],re[a];im[a],im[b]=im[b],im[a] end
 for _,stage in ipairs(plan.stages) do
  local len=stage.len;local half=len//2;local trr,tii=stage.re,inverse and stage.inverse_im or stage.im
  for base=1,n,len do
   for k=0,half-1 do
    local wr,wi=trr[k+1],tii[k+1];local a,b=base+k,base+k+half
    local tr,ti=wr*re[b]-wi*im[b],wr*im[b]+wi*re[b]
    re[b],im[b]=re[a]-tr,im[a]-ti;re[a],im[a]=re[a]+tr,im[a]+ti
   end
  end
 end
 if inverse then for i=1,n do re[i],im[i]=re[i]/n,im[i]/n end end
end
function Core.targets(s,sr)
 local targets={};local n=s.fft
 for k=1,n//2-1 do if k*sr/n<=s.maxfreq then targets[k]=Core.target(s.curve,k*sr/n) end end
 return targets
end
function Core.processor(s,sr,ch,total,targets)
 Core.validate(s)
 local n=s.fft;local spectra={}
 for c=1,ch do spectra[c]={{},{}} end
 local p={s=s,sr=sr,ch=ch,total=total,n=n,hop=n//s.overlap,win={},sum={},weight={},previous={},out={},peak=0,targets=targets or Core.targets(s,sr),spectra=spectra,strength=s.strength/100}
 for i=1,n do p.win[i]=.5-.5*math.cos(2*pi*(i-1)/n) end
 p.alpha=s.smooth==0 and 1 or 1-math.exp(-p.hop/(sr*s.smooth*.001))
 p.at=-n+p.hop;p.flushed=0
 return p
end
function Core.frame(p,input,input_offset)
 local s,n,spectra=p.s,p.n,p.spectra
 input_offset=input_offset or 0
 for c=1,p.ch do
  local re,im=spectra[c][1],spectra[c][2]
  for i=1,n do re[i]=(input[(i-1)*p.ch+c-input_offset] or 0)*p.win[i];im[i]=0 end
  Core.fft(re,im,false)
 end
 local alpha=p.alpha
 for k=1,n//2-1 do
  if p.targets[k] then
   local power=0
   for c=1,p.ch do local z=spectra[c];power=power+z[1][k+1]^2+z[2][k+1]^2 end
   local level=db(4*sqrt(power/p.ch)/n)
   local desired=clamp(p.targets[k]-level,-s.cut,s.boost)*p.strength
   local gate=clamp((level-s.threshold)/max(s.knee,1e-9),0,1);gate=gate*gate*(3-2*gate)
   if desired>0 then desired=desired*gate end
   local previous=p.previous[k] or desired;local gain=previous+alpha*(desired-previous)
   if gain>0 then gain=min(gain,s.boost*p.strength*gate) end
   p.previous[k]=gain;local g=amp(gain)
   for c=1,p.ch do
    local re,im=spectra[c][1],spectra[c][2];local a,b=k+1,n-k+1
    re[a],im[a]=re[a]*g,im[a]*g;re[b],im[b]=re[b]*g,im[b]*g
   end
  end
 end
 for c=1,p.ch do Core.fft(spectra[c][1],spectra[c][2],true) end
 for i=1,n do
  local t=p.at+i-1
  if t>=0 and t<p.total then
   p.weight[t]=(p.weight[t] or 0)+p.win[i]^2
   for c=1,p.ch do
    local idx=t*p.ch+c;p.sum[idx]=(p.sum[idx] or 0)+spectra[c][1][i]*p.win[i]
   end
  end
 end
 p.at=p.at+p.hop
 local ending=min(p.total,max(0,p.at));local out=p.out;for i=#out,1,-1 do out[i]=nil end
 for t=p.flushed,ending-1 do
  assert((p.weight[t] or 0)>1e-12,'Overlap-add window coverage error')
  for c=1,p.ch do
   local idx=t*p.ch+c;local v=p.sum[idx]/p.weight[t]
   assert(finite(v),'非有限の音声値が発生しました。')
   out[#out+1]=v;p.peak=max(p.peak,abs(v));p.sum[idx]=nil
  end
  p.weight[t]=nil
 end
 p.flushed=ending
 return out,p.at>=p.total
end
function Core.encode(s)
 Core.validate(s);local t={'BLT_SPECTRAL_NORMALIZER_V1'}
 for _,k in ipairs(Core.SERIAL_KEYS) do t[#t+1]=k..'='..s[k] end
 t[#t+1]='curve_kind='..s.curve.kind;t[#t+1]='curve_smoothness='..Core.smoothness(s.curve)
 local points={};for i,p in ipairs(s.curve.points) do points[i]=string.format('%.17g:%.17g',p.x,p.y) end
 t[#t+1]='curve='..table.concat(points,',');return table.concat(t,'\n')
end
function Core.decode(text)
 assert(type(text)=='string' and #text<=BLTPresetLimits.stringBytes,'プリセットが大きすぎます。')
 text=text:gsub('\r\n','\n')
 assert(text:match('^BLT_SPECTRAL_NORMALIZER_V1\n'),'このアプリのプリセットではありません。')
 local s=Core.defaults();local seen,raw_curve={}
 for line in text:gmatch('[^\r\n]+') do
  local k,v=line:match('^([%w_]+)=(.+)$')
  if k then
   assert(not seen[k],'プリセット項目が不正です。');seen[k]=true
   if k=='curve' then raw_curve=v
   elseif k=='curve_kind' then s.curve.kind=v
   elseif k=='curve_smoothness' then s.curve.smoothness=assert(tonumber(v),'数値が不正です。')
   else assert(s[k]~=nil and type(s[k])=='number','プリセット項目が不正です。');s[k]=assert(tonumber(v),'数値が不正です。') end
  end
 end
 for _,k in ipairs(Core.REQUIRED_KEYS) do assert(seen[k],'設定が不足しています。') end
 s.curve.points={}
 for token in (raw_curve..','):gmatch('(.-),') do assert(#s.curve.points<Core.MAX_POINTS,'カーブの点数が多すぎます。');local x,y=token:match('^([^:]+):([^:]+)$');assert(x and y,'カーブの値が不正です。');s.curve.points[#s.curve.points+1]={x=assert(tonumber(x),'数値が不正です。'),y=assert(tonumber(y),'数値が不正です。')} end
 return Core.validate(s)
end
local R=reaper
local SECTION,W,H,TITLE_H=Core.SECTION,1000,838,26
local App,UI,Theme,Chrome,Presets={},{},{},{},{}
App.empty_samples={};App.store_cache={}
function App.store(section,key,value,persist)
 local id=section..'/'..key;local encoded=tostring(value)
 if App.store_cache[id]~=encoded then R.SetExtState(section,key,encoded,persist);App.store_cache[id]=encoded end
end

local PrimaryButton=(function()
 local P={state={hover=0},nextFrame=0};local sin,min,max=math.sin,math.min,math.max
 function P.draw_particles(d,s,x,y,w,h,hover,busy,real_dt,animation_dt,mx,my)
  local C=d.C;local ice=C.accent2
  if not s.particles then s.particles={};s.pool={};s.serial=0;s.clock=0 end
  if hover or busy then
   s.clock=s.clock+(busy and real_dt or animation_dt);local interval=busy and .030 or .055;local cap=busy and 66 or 44
   while s.clock>=interval and #s.particles<cap do
    s.clock=s.clock-interval;s.serial=s.serial+1;local n=s.serial;local h1=(sin(n*12.9898)*43758.5453)%1;local h2=(sin(n*78.233)*12345.6789)%1
    local p=table.remove(s.pool) or {};p.x=busy and x+12+h1*(w-24) or mx+(h1-.5)*7;p.y=busy and y+h-7-h2*8 or my+(h2-.5)*5
    p.age=0;p.life=busy and (.65+h1*.65) or (1.6+h1*1.2);p.vx=(h2-.5)*(busy and 15 or 7);p.vy=busy and (10+h1*14) or (6+h1*8);p.phase=h2*pi*2;s.particles[#s.particles+1]=p
   end
  else s.clock=min(s.clock,.04) end
  for i=#s.particles,1,-1 do local p=s.particles[i];p.age=p.age+real_dt
   if p.age>=p.life then table.remove(s.particles,i);s.pool[#s.pool+1]=p else
    local px=p.x+p.vx*p.age+sin(p.age*1.6+p.phase)*2;local py=p.y-p.vy*p.age;local e=sin(pi*p.age/p.life)^2
    if px>x+3 and px<x+w-3 and py>y+3 and py<y+h-3 then d.disc(px,py,busy and 4.4 or 3.7,C.accent,(busy and .035 or .02)*e);d.disc(px,py,busy and 2.2 or 1.9,ice,(busy and .10 or .065)*e);d.disc(px,py,busy and .85 or .7,ice,(busy and .78 or .58)*e) end
   end
  end
 end
 function P.draw(d,x,y,w,h,title,caption,enabled,busy,progress,hover,pressed,now,active)
  local s=P.state;local C=d.C;local live=active~=false;enabled=enabled~=false;busy=busy==true;hover=hover and enabled and live
  local dt=min(.1,max(0,now-(s.time or now)));s.time=now;local target=(hover or busy) and 1 or 0;s.hover=s.hover+(target-s.hover)*min(1,dt*14)
  if abs(target-s.hover)<.002 then s.hover=target end;if s.busy and not busy then s.flash_until=now+.45 end;s.busy=busy;s.hot=hover;s.live=live
  local amount=s.hover;local pulse=busy and live and (.5+.5*sin(now*5.2)) or 0;y=y+(pressed and enabled and 1.5 or 0)
  local deep,ice=C.accent3,C.accent2;local edge=(enabled or busy) and ice or C.muted
  if enabled or busy then d.gradient(x,y,w,h,deep,C.field,.22+.12*amount+(busy and .10*pulse or 0),.92);if amount>.01 then d.gradient(x,y,w,h,C.accent,deep,busy and (.20+.10*pulse) or .13*amount,.01,true) end else d.gradient(x,y,w,h,C.field,C.field,.92,.92) end
  d.gradient(x,y,w,busy and 2 or 1,edge,edge,(enabled or busy) and (.62+.28*amount) or .18,.03);d.line(x,y+h,x+w,y+h,busy and ice or C.edge,busy and (.52+.20*pulse) or (enabled and .48 or .14));d.line(x,y,x,y+h,edge,(enabled or busy) and (.66+.18*pulse) or .13)
  d.corners(x,y,w,h,min(10,h/3),true,edge,(enabled or busy) and (.68+.18*pulse) or .18)
  local mx,my,speed=d.motion(now);s.emitting=busy or (hover and live and speed>0);P.draw_particles(d,s,x,y,w,h,hover,busy,dt,live and dt*speed or 0,mx,my)
  if s.flash_until and now<s.flash_until and live then local flash=((s.flash_until-now)/.45)^2;d.rect(x+1,y+1,w-2,h-2,ice,.07*flash);d.line(x,y,x+w,y,ice,.6*flash) end
  local top=caption or 'EXECUTE';if not enabled and not busy then top='WAIT' end
  if type(progress)=='number' then progress=clamp(progress,0,1);top=top..'  '..floor(progress*100+.5)..'%';d.rect(x+4,y+h-5,w-8,2,C.edge,.45);if progress>0 then d.rect(x+4,y+h-5,(w-8)*progress,2,ice,.8) end end
  local top_y=y+(h-42)/2+3;d.label(top,x+10,top_y,8,(enabled or busy) and ice or C.faint,3,true,w-20,'center');d.label(title,x+10,top_y+14,15,(enabled or busy) and C.text or C.muted,1,false,w-20,'center')
 end
 function P.tick(now,active,wake)
  local s=P.state;local tail=s.particles and #s.particles>0;local fading=s.hover>.002 and s.hover<.998 or (not s.hot and not s.busy and s.hover>.002)
  if (tail or s.busy or (active and s.live and (s.emitting or fading or (s.flash_until and now<s.flash_until)))) and now>=P.nextFrame then P.nextFrame=now+(tail and not s.hot and not s.busy and 1/20 or 1/30);wake() end
 end
 return P
end)()

local L={code=R.GetExtState(SECTION,'ui_language')=='EN' and 'EN' or 'JP',en={
 ['波形を解析し変換']='Analyze to curve',['集計']='Mode',['解析を中止']='Cancel analysis',['平均（パワー）']='Mean (power)',['中央値（0.5dB）']='Median (0.5 dB)',['最大値']='Maximum',
 ['解析を中止しました。カーブは保持されています。']='Analysis canceled. Curve preserved.',['波形を解析中…']='Analyzing waveform…',['周波数特性でカーブを置き換えました。']='Replaced curve with spectral analysis.',
 ['周期幅']='Period',['周期：一定']='Constant',['アッチェレランド']='Accelerando',['リタルダンド']='Ritardando',
 ['SPECTRAL TARGET DRAWING  周波数ごとの目標音量を描画']='SPECTRAL TARGET DRAWING  Draw target levels by frequency',
 ['表示尺度']='Scale',['処理上限']='Process limit',['選択素材']='Selection',
 ['音声アイテム未選択']='No audio items selected',
 ['補完処理']='INTERPOLATION',['直線']='Linear',['滑らか']='Smooth',['操作モード']='EDIT MODE',
 ['範囲選択']='Select',['ペン']='Pen',['ライン']='Line',['ライン生成']='Generate line',
 ['サイン波']='Sine',['ノコギリ波']='Saw',['矩形波']='Square',['三角波']='Triangle',['水平線']='Flat',['ランダムステップ']='Random Step',
 ['方向：左']='Direction: Left',['方向：両側']='Direction: Both',['方向：右']='Direction: Right',['最大高さ']='Max. height',
 ['振幅：一定']='Constant',['クレッシェンド']='Crescendo',['デクレッシェンド']='Decrescendo',['Alt：位相反転']='Alt: invert phase',
 ['カーブ操作']='CURVE TOOLS',
 ['カーブを初期化']='Reset curve',['処理強度プリセット']='INTENSITY PRESETS',
 ['戻す']='Undo',['進む']='Redo',
 ['処理パラメーター']='PROCESSING PARAMETERS',['FFTサイズ']='FFT size',['重なり']='Overlap',['追従強度']='Strength',
 ['増幅閾値']='Boost threshold',['移行幅']='Knee',['時間平滑化']='Time smoothing',['最大ブースト']='Max boost',
 ['最大カット']='Max cut',['ピーク上限']='Peak ceiling',['選択アイテムを処理']='Process selected items',['処理を中止']='Cancel processing',
 ['音声アイテムを選択し、目標カーブを描いてください。']='Select audio items and draw a target curve.',['処理中…']='Processing...',
 ['中止しました。元のテイクは保持されています。']='Cancelled. Original takes were preserved.',
 ['処理に失敗しました。']='Processing failed.',
 ['カーブを初期化しました。']='Curve reset.',['元に戻せるカーブ編集がありません。']='No curve edit to undo.',
 ['やり直せるカーブ編集がありません。']='No curve edit to redo.',
 ['カーブ編集を元に戻しました。']='Curve edit undone.',['カーブ編集をやり直しました。']='Curve edit redone.',
 ['ファクトリーデフォルト']='Factory Default',['プリセット']='Presets',['未選択']='None',
 ['上書き保存']='Save',['名前を付けて保存…']='Save As...',['削除']='Delete',['インポート…']='Import...',
 ['現在値をエクスポート']='Export current',['プリセットを保存しました。']='Preset saved.',
 ['プリセットを読み込みました。']='Preset loaded.',['プリセットを削除しました。']='Preset deleted.',
 ['プリセットをインポートしました。']='Preset imported.',['プリセットをエクスポートしました。']='Preset exported.',
 ['プリセットは50個まで保存できます。']='Up to 50 presets can be saved.',['有効なプリセット名を入力してください。']='Enter a valid preset name.',
 ['プリセットファイルを開けません。']='Cannot open the preset file.',['同名ファイルを上書きしますか？']='Overwrite the existing file?',
 ['保存先を開けません。']='Cannot open the destination.',['保存に失敗しました。']='Save failed.',
 ['ファクトリーデフォルトを読み込みました。']='Factory Default loaded.',['処理設定を変更しました。']='Processing settings changed.',
 ['CHAMELEON  REAPERテーマに擬態']='CHAMELEON  REAPER theme',['CHAMELEON  オリジナル配色']='CHAMELEON  Original colors',
 ['カスタムアプリバーには js_ReaScriptAPI が必要です。\nReaPack から js_ReaScriptAPI をインストールしてください。']='The custom app bar requires js_ReaScriptAPI.\nInstall js_ReaScriptAPI from ReaPack.',
 ['カスタムアプリバーを初期化できません。']='Cannot initialize the custom app bar.',
 ['長尺処理の確認']='LONG PROCESS CONFIRMATION',['選択範囲の合計が25分以上です。']='The selected duration is 25 minutes or longer.',
 ['処理中は一時WAVと出力WAVを作成し、時間と空き容量を使用します。']='Temporary and output WAV files require time and disk space.',
 ['キャンセル']='Cancel',['このまま実行']='Continue',['対象外']='Inactive',['カスタム']='CUSTOM',
 ['破線＝増幅閾値。目標はFFTビンの正弦波ピーク換算値。DC・Nyquistは保持。']='Dashed line: boost threshold. Targets use FFT-bin sine peak level; DC and Nyquist are preserved.',
 ['ドラッグ：範囲選択  ·  辺／角：変形  ·  枠内：移動  ·  Delete／枠内右クリック：削除']='Drag: range select · Edges/corners: resize · Inside: move · Delete/right-click: remove',
 ['波形上をクリック：カーソル位置からライン生成']='Click graph: generate line from cursor',
 ['ドラッグ：描画／点移動  ·  Shift：直線  ·  Alt：点をつかまず描画  ·  右クリック：点削除']='Drag: draw/move points · Shift: line · Alt: draw without grabbing points · Right-click: delete point',
 ['1 / 2 / 3：範囲選択 / ペン / ライン生成  ·  数値欄ドラッグ／ホイール：変更  ·  Ctrl+Z / Ctrl+Y：履歴']='1 / 2 / 3: Select / Pen / Generate line · Drag/wheel fields: adjust · Ctrl+Z / Ctrl+Y: history',
 ['再生・録音を停止してから処理してください。']='Stop playback/recording before processing.',
 ['処理中 %d / %d   %.1f%%  — 対象素材の編集は避けてください。']='Processing %d / %d   %.1f%%  — Do not edit the source items.',
 ['%dアイテム完了。終端の1秒後に別アイテムを作成しました。ピーク保護による最大減衰 %.1f dB。']='Completed %d item(s). Created new items 1 second after each source end. Maximum peak-protection reduction: %.1f dB.',
 ['先にREAPERプロジェクトを保存してください。']='Save the REAPER project first.',
 ['音声アイテムを選択してください。']='Select audio items.',
 ['選択には音声アイテムのみを含めてください。']='The selection must contain audio items only.',
 ['ロックされたアイテムがあります。']='A selected item is locked.',
 ['全テイク同時再生は非対応です。']='Play-all-takes is not supported.',
 ['再生速度・ピッチ・ストレッチ変更は先にGlueしてください。']='Glue items with rate, pitch, or stretch changes first.',
 ['テイクのチャンネルモード・パンは先にGlueしてください。']='Glue items with take channel-mode or pan changes first.',
 ['テイクFX・テイクエンベロープは先にGlueしてください。']='Glue items with take FX or take envelopes first.',
 ['反転・セクション素材は先にGlueしてください。']='Glue reversed or section sources first.',
 ['8〜192 kHzのモノラル／ステレオ素材に対応します。']='Only 8–192 kHz mono/stereo sources are supported.',
 ['プロジェクトが切り替わったため中止しました。']='Cancelled because the project changed.',
 ['処理中にプロジェクトが変更されたため中止しました。']='Cancelled because the project was edited during processing.',
 ['対象テイクが変更されました。']='A target take changed.',
 ['処理中に音声が変更されました。']='Source audio changed during processing.',
 ['処理中にエラーが発生しました。']='An error occurred during processing.',
 ['WAVが4 GBを超えます。アイテムを分割してください。']='The WAV would exceed 4 GB. Split the item first.',
 ['プロジェクトフォルダが不明です。']='Cannot determine the project folder.',['空のアイテムがあります。']='A selected item is empty.',
 ['音声アクセサーを作成できません。']='Cannot create an audio accessor.',['音声範囲が不足しています。先にGlueしてください。']='The readable audio range is too short. Glue the item first.',
 ['作業WAVを作成できません。']='Cannot create the working WAV.',['処理WAVを読み込めません。']='Cannot load the processed WAV.',
['新しいテイクを追加できません。']='Cannot add a new take.',
 ['音声ソースを設定できません。']='Cannot assign the audio source.',['テイク設定を適用できません。']='Cannot apply take settings.',
 ['音声の読み取りに失敗しました。']='Audio read failed.',['元音声に非有限値があります。']='The source contains a non-finite sample.',
 ['32-bit floatで保存できない音声値です。']='A sample cannot be stored as 32-bit float.',['作業WAVが破損しています。']='The working WAV is damaged.',
 ['書き込みサンプル数が一致しません。']='The written sample count does not match.',
}}
L.en["戻る"]="Back"
L.en["現在: "]="Current: "
L.en["未選択"]="None"
L.en["プリセット一覧をエクスポート"]="Export preset list"
L.en["同名のプリセットを上書きしますか？"]="Overwrite presets with matching names?"
L.en["未保存の変更を破棄して読み込みますか？"]="Discard unsaved changes and load?"
L.en["インポートしました。一覧から選択してください。"]="Imported. Select from the preset list."
L.en["プリセットは200個まで保存できます。"]="Up to 200 presets can be saved."
function L.text(value) local s=tostring(value or '');return L.code=='EN' and (L.en[s] or s) or s end
function L.toggle() L.code=L.code=='JP' and 'EN' or 'JP';App.store(SECTION,'ui_language',L.code,true) end

local settings=Core.defaults()
do local raw=R.GetExtState(SECTION,'settings');if raw~='' then local ok,v=pcall(Core.decode,raw);if ok then settings=v end end end
local saved_tool=R.GetExtState(SECTION,'draw_tool')
if saved_tool~='select' and saved_tool~='free' and saved_tool~='line' then saved_tool='free' end
local A={settings=settings,analysis_method=settings.analysis_method,status='音声アイテムを選択し、目標カーブを描いてください。',warning=false,status_until=0,
 job=nil,pending_job=nil,closed=false,closing=false,dirty=true,active=true,pressed=nil,drag=nil,number_drag=nil,edit=nil,tool=saved_tool,selection=nil,
 pattern=settings.pattern,direction=settings.direction,shape_envelope=settings.shape_envelope,period_percent=settings.period_percent,period_shape=settings.period_shape,height=settings.height,hover_node=nil,point_flash=0,pointer_capture=nil,
 history={},redo={},number_flash={},preset_name=nil,preset_dirty=false,
 source_info='音声アイテム未選択',source_detail='',selection_poll=0,selection_project=nil,selection_revision=nil,selection_count=nil,selection_item=nil,selection_take=nil,last_mouse_cap=0,last_right=false,last_mouse_x=-1,last_mouse_y=-1,last_w=0,last_h=0,
 next_draw=0,icon_particles={},icon_pool={},icon_clock=0,icon_serial=0,icon_last=R.time_precise(),effect_until=R.time_precise()+2.5,modal=nil}
function App.public_error(value)
 local text=tostring(value or ''):match('^(.-)\nstack traceback:') or tostring(value or '')
 text=text:gsub('\\','/')
 text=text:gsub('([^\r\n]+)',function(line)
  line=line:gsub('^%s*%[string .-%]:%d+:%s*',''):gsub('^%s*.-:%d+:%s*','')
  line=line:gsub('^%s*[A-Za-z]:/[^:\r\n]+:%s*',''):gsub('^%s*/[^:\r\n]+:%s*','')
  line=line:gsub('[A-Za-z]:/[^:\r\n"<>|]*',''):gsub('//[^:\r\n"<>|]*','')
  line=line:gsub('%s/[^:\r\n"<>|]*',''):gsub('[^%s:"<>|/]+/[^%s:"<>|]+','')
  line=line:gsub('[^%s:"<>|]+%.[%a][%w%-]*',''):gsub('%s+:%s+',': ')
  return line:match('^%s*(.-)%s*$') or ''
 end)
 return text:match('%S') and text or '処理中にエラーが発生しました。'
end
function App.notice(text,warning,seconds)
 A.status=L.text(text);A.warning=warning==true;A.status_until=R.time_precise()+(seconds or 7);A.dirty=true
end
function App.safe(fn,...)
 local ok,result=xpcall(fn,debug.traceback,...)
 if not ok then if UI.release_capture then UI.release_capture() end;App.notice(App.public_error(result),true) end
 return ok,result
end
function App.persist()
 for key in pairs(Core.DRAW_LIMITS) do A.settings[key]=A[key] end
 local encoded=Core.encode(A.settings)
 App.store(SECTION,'settings',encoded,true)
 if Presets.current_entry then local p=Presets.current_entry();if p then A.preset_dirty=encoded~=p.data end end
 App.store(SECTION,'draw_tool',A.tool,true)
end
function App.changed(message)
 A.preset_dirty=true;App.persist();if message then App.notice(message,false,3) else A.dirty=true end
end
function App.copy_curve(curve) return Core.copy(curve) end
function App.push_history()
 A.history[#A.history+1]=App.copy_curve(A.settings.curve);if #A.history>40 then table.remove(A.history,1) end;A.redo={}
end
function App.curve_undo(redo)
 local from,to=redo and A.redo or A.history,redo and A.history or A.redo
 if #from==0 then App.notice(redo and 'やり直せるカーブ編集がありません。' or '元に戻せるカーブ編集がありません。',false,3);return end
 to[#to+1]=App.copy_curve(A.settings.curve);A.settings.curve=table.remove(from);A.selection=nil;A.drag=nil
 App.changed(redo and 'カーブ編集をやり直しました。' or 'カーブ編集を元に戻しました。')
end
function App.reset_curve()
 App.push_history();A.settings.curve={points={{x=0,y=-42},{x=96000,y=-42}},kind='linear',smoothness=0}
 A.selection=nil;App.changed('カーブを初期化しました。')
end

function App.wav_header(sr,ch,frames)
 local bytes=frames*ch*4
 assert(bytes<0xFFFFFFFF-48,'WAVが4 GBを超えます。アイテムを分割してください。')
 return 'RIFF'..string.pack('<I4',bytes+48)..'WAVEfmt '..string.pack('<I4I2I2I4I4I2I2',16,3,ch,sr,sr*ch*4,ch*4,32)..'fact'..string.pack('<I4I4',4,frames)..'data'..string.pack('<I4',bytes)
end
function App.cleanup(j)
 if not j then return end
 if j.aa then pcall(R.DestroyAudioAccessor,j.aa);j.aa=nil end
 for _,k in ipairs({'raw','input','output'}) do if j[k] then pcall(function()j[k]:close()end);j[k]=nil end end
 for _,p in ipairs(j.plans or {}) do
  if p.pendingSource then pcall(R.PCM_Source_Destroy,p.pendingSource);p.pendingSource=nil end
  if p.temp then pcall(os.remove,p.temp) end
  if p.path and not j.committed and not j.preserve then pcall(os.remove,p.path) end
 end
end
function App.item_signature(item)
 local ok,chunk=R.GetItemStateChunk(item,'',false);assert(ok,'対象アイテムの状態を取得できません。')
 -- Selection is UI state, not an audio edit. Preserve every other chunk field.
 return ('\n'..chunk:gsub('\r\n','\n')):gsub('\nSEL [^\n]*','')
end
function App.check_job(j,force)
 assert(R.EnumProjects(-1,'')==j.project,'プロジェクトが切り替わったため中止しました。')
 local revision=R.GetProjectStateChangeCount(j.project)
 if not force and revision==j.checked_revision then return end
 for _,p in ipairs(j.plans) do
  assert(R.ValidatePtr2(j.project,p.item,'MediaItem*') and R.ValidatePtr2(j.project,p.track,'MediaTrack*'),'対象アイテムまたはトラックが削除されました。')
  assert(R.GetActiveTake(p.item)==p.take and R.GetMediaItemTrack(p.item)==p.track,'対象テイクまたはトラックが変更されました。')
  assert(App.item_signature(p.item)==p.signature,'対象アイテムの内容が変更されたため中止しました。')
 end
 j.checked_revision=revision
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
function App.plan()
 local project=R.EnumProjects(-1,'')
 assert((R.GetPlayStateEx(project)&5)==0,'再生・録音を停止してから処理してください。')
 local dir=blt_output_directory(project)
 local plans={};local token=R.genGuid():gsub('[^%w]','');local total_seconds=0
 for i=0,R.CountSelectedMediaItems(project)-1 do
  local item=R.GetSelectedMediaItem(project,i);local take=R.GetActiveTake(item)
  assert(take and not R.TakeIsMIDI(take),'選択には音声アイテムのみを含めてください。')
  assert(R.GetMediaItemInfo_Value(item,'C_LOCK')==0,'ロックされたアイテムがあります。')
  assert(R.GetMediaItemInfo_Value(item,'B_ALLTAKESPLAY')==0,'全テイク同時再生は非対応です。')
  assert(R.GetMediaItemTakeInfo_Value(take,'D_PLAYRATE')==1 and R.GetMediaItemTakeInfo_Value(take,'D_PITCH')==0 and R.GetTakeNumStretchMarkers(take)==0,'再生速度・ピッチ・ストレッチ変更は先にGlueしてください。')
  assert(R.GetMediaItemTakeInfo_Value(take,'I_CHANMODE')==0 and R.GetMediaItemTakeInfo_Value(take,'D_PAN')==0,'テイクのチャンネルモード・パンは先にGlueしてください。')
  assert(R.CountTakeEnvelopes(take)==0 and R.TakeFX_GetCount(take)==0,'テイクFX・テイクエンベロープは先にGlueしてください。')
  local source=R.GetMediaItemTake_Source(take)
  assert(R.GetMediaSourceType(source)~='SECTION','反転・セクション素材は先にGlueしてください。')
  local sr=R.GetMediaSourceSampleRate(source);local ch=R.GetMediaSourceNumChannels(source)
  assert(sr>=8000 and sr<=192000 and sr%1==0 and (ch==1 or ch==2),'8〜192 kHzのモノラル／ステレオ素材に対応します。')
  local len=R.GetMediaItemInfo_Value(item,'D_LENGTH');local frames=math.floor(len*sr+.5)
  assert(frames>0,'空のアイテムがあります。');App.wav_header(sr,ch,frames);total_seconds=total_seconds+len
  plans[#plans+1]={item=item,take=take,track=R.GetMediaItemTrack(item),position=R.GetMediaItemInfo_Value(item,'D_POSITION'),itemvolume=R.GetMediaItemInfo_Value(item,'D_VOL'),signature=App.item_signature(item),sr=sr,ch=ch,len=len,frames=frames,volume=R.GetMediaItemTakeInfo_Value(take,'D_VOL'),path=dir..'/BLT_SPECTRAL_NORMALIZER_'..token..'_'..(i+1)..'.wav'}
 end
 assert(#plans>0,'音声アイテムを選択してください。')
 return {project=project,plans=plans,index=1,revision=R.GetProjectStateChangeCount(project),s=Core.copy(Core.validate(A.settings)),phase='render',total_seconds=total_seconds,targets_by_rate={}}
end
function App.audio_samples(j,p,first,count)
 if count<=0 then return App.empty_samples,first end
 local cache=j.audio_cache
 if not cache or first<cache.first or first+count>cache.ending then
  local frames=min(p.frames-first,max(32768,j.n or j.s.fft))
  j.buffer.clear();local rc=R.GetAudioAccessorSamples(j.aa,p.sr,p.ch,j.start+first/p.sr,frames,j.buffer)
  assert(type(rc)=='number' and rc>=0,'音声の読み取りに失敗しました。')
  local values=j.buffer.table(1,frames*p.ch)
  for i,v in ipairs(values) do assert(finite(v),'元音声に非有限値があります。');if j.kind~='analysis' then values[i]=v*p.volume end end
  cache={first=first,ending=first+frames,values=values};j.audio_cache=cache
 end
 return cache.values,cache.first
end
function App.start_item(j,p)
 j.aa=assert(R.CreateTakeAudioAccessor(p.take),'音声アクセサーを作成できません。')
 j.start=R.GetAudioAccessorStartTime(j.aa)
 assert(R.GetAudioAccessorEndTime(j.aa)-j.start>=p.len-1/p.sr,'音声範囲が不足しています。先にGlueしてください。')
 local targets=j.targets_by_rate[p.sr];if not targets then targets=Core.targets(j.s,p.sr);j.targets_by_rate[p.sr]=targets end
 j.audio_cache=nil;j.buffer=R.new_array(max(32768,j.s.fft)*p.ch);j.proc=Core.processor(j.s,p.sr,p.ch,p.frames,targets);j.packed={}
 p.temp=p.path..'.blt-part';j.raw=assert(io.open(p.temp,'wb'),'出力先BLTフォルダーへ書き込めません。保存先とアクセス権を確認してください。')
end
function App.build_peaks(j,p)
 assert(type(R.PCM_Source_BuildPeaks)=='function','波形ピーク構築APIを利用できません。REAPERを更新してください。')
 if not p.pendingSource then
  p.pendingSource=assert(R.PCM_Source_CreateFromFile(p.path),'処理WAVを読み込めません。')
  local remaining=R.PCM_Source_BuildPeaks(p.pendingSource,0)
  assert(type(remaining)=='number' and remaining>=0,'波形ピークの作成を開始できません。')
  p.peaksBuilding=remaining~=0
  if not p.peaksBuilding then j.index=j.index+1;j.phase='render';j.progress=0;return end
 end
 local remaining=R.PCM_Source_BuildPeaks(p.pendingSource,1)
 assert(type(remaining)=='number' and remaining>=0,'波形ピークを作成できません。')
 j.progress=.95+.05*(1-clamp(remaining/100,0,1))
 if remaining==0 then
  R.PCM_Source_BuildPeaks(p.pendingSource,2);p.peaksBuilding=nil
  j.index=j.index+1;j.phase='render';j.progress=0
 end
end
function App.commit(j)
 App.check_job(j,true);local created={}
 for _,p in ipairs(j.plans) do assert(p.pendingSource,'処理WAVの波形ピークを準備できません。') end
 R.Undo_BeginBlock2(j.project);R.PreventUIRefresh(1)
 local ok,err=xpcall(function()
  for _,p in ipairs(j.plans) do
   local item=assert(R.AddMediaItemToTrack(p.track),'出力アイテムを追加できません。');created[#created+1]={item=item,track=p.track}
   for key,value in pairs({D_POSITION=p.position+p.len+1,D_LENGTH=p.len,D_VOL=p.itemvolume,B_LOOPSRC=0,D_FADEINLEN=0,D_FADEOUTLEN=0,D_FADEINLEN_AUTO=0,D_FADEOUTLEN_AUTO=0}) do
    assert(R.SetMediaItemInfo_Value(item,key,value),'出力アイテムを設定できません。')
   end
   local take=assert(R.AddTakeToMediaItem(item),'新しいテイクを追加できません。')
   R.SetMediaItemTake_Source(take,p.pendingSource);assert(R.GetMediaItemTake_Source(take)==p.pendingSource,'音声ソースを設定できません。');p.pendingSource=nil
   for key,value in pairs({D_VOL=1,D_PAN=0,D_PLAYRATE=1,D_STARTOFFS=0,D_PITCH=0,I_CHANMODE=0}) do assert(R.SetMediaItemTakeInfo_Value(take,key,value),'テイク設定を適用できません。') end
   R.GetSetMediaItemTakeInfo_String(take,'P_NAME','BLT SPECTRAL NORMALIZER',true);R.SetActiveTake(take);R.UpdateItemInProject(item)
  end
 end,debug.traceback)
 if not ok then
  for i=#created,1,-1 do local v=created[i];local safe,removed=pcall(R.DeleteTrackMediaItem,v.track,v.item)
   if not safe or not removed then j.preserve=true end
  end
 end
 R.PreventUIRefresh(-1);R.Undo_EndBlock2(j.project,'BLT Spectral Normalizer: Render to new items',-1);R.UpdateArrange()
 assert(ok,err);j.committed=true
end
function App.step(j)
 App.check_job(j);local p=j.plans[j.index]
 if not p then App.commit(j);return true end
 if j.phase=='peaks' then App.build_peaks(j,p);return false end
 if j.phase=='render' then
  if not j.proc then App.start_item(j,p) end
  assert(not R.AudioAccessorStateChanged(j.aa),'処理中に音声が変更されました。')
  local proc=j.proc;local first=max(0,proc.at);local ending=min(p.frames,proc.at+proc.n);local count=max(0,ending-first);local samples,offset
  local origin;samples,origin=App.audio_samples(j,p,first,count);offset=(origin-proc.at)*p.ch
  local out,done=Core.frame(proc,samples,offset);local packed=j.packed;for i=#packed,1,-1 do packed[i]=nil end
  for i,v in ipairs(out) do assert(abs(v)<=3.4028234e38,'32-bit floatで保存できない音声値です。');packed[i]=string.pack('<f',v) end
  if #packed>0 then assert(j.raw:write(table.concat(packed))) end
  j.progress=clamp(proc.flushed/p.frames,0,1)*.88
  if done then
   assert(j.raw:close());j.raw=nil;R.DestroyAudioAccessor(j.aa);j.aa=nil
   p.peak=proc.peak;p.scale=min(1,amp(j.s.ceiling)/max(p.peak,1e-15));j.proc=nil
   j.input=assert(io.open(p.temp,'rb'));j.output=assert(io.open(p.path,'wb'),'出力WAVへ書き込めません。保存先の空き容量とアクセス権を確認してください。')
   assert(j.output:write(App.wav_header(p.sr,p.ch,p.frames)));j.written=0;j.phase='write'
  end
 else
  local raw=j.input:read(65536)
  if raw then
   assert(#raw%4==0,'作業WAVが破損しています。');local packed=j.packed;for i=#packed,1,-1 do packed[i]=nil end
   if p.scale==1 then assert(j.output:write(raw)) else
    for offset=1,#raw,4 do packed[#packed+1]=string.pack('<f',string.unpack('<f',raw,offset)*p.scale) end
    assert(j.output:write(table.concat(packed)))
   end;j.written=j.written+#raw;j.progress=.88+.07*j.written/(p.frames*p.ch*4)
  else
   assert(j.written==p.frames*p.ch*4,'書き込みサンプル数が一致しません。')
   assert(j.input:close());j.input=nil;assert(j.output:close());j.output=nil;pcall(os.remove,p.temp);j.packed=nil
   j.phase='peaks';j.progress=.95
  end
 end
 return false
end
function App.begin_processing()
 if not Media.ready() then return end
 local candidate=App.plan()
 if candidate.total_seconds>=1500 then A.pending_job=candidate;A.modal='long';A.dirty=true
 else A.job=candidate;App.notice('処理中…',false,3600) end
end
function App.confirm_processing()
 if A.pending_job then A.job=A.pending_job;A.pending_job=nil;A.modal=nil;App.notice('処理中…',false,3600) end
end
function App.cancel_pending() A.pending_job=nil;A.modal=nil;A.dirty=true end
function App.cancel_processing()
 if not A.job then return end;local analysis=A.job.kind=='analysis';App.cleanup(A.job);A.job=nil;App.notice(analysis and '解析を中止しました。カーブは保持されています。' or '中止しました。元のテイクは保持されています。',false)
end
function Core.analysis_accumulate(bin,power,weight,method)
 bin.weight=bin.weight+weight
 if method==1 then bin.sum=bin.sum+power*weight
 elseif method==3 then bin.peak=max(bin.peak,power)
 else
  local bucket=floor((clamp(db(sqrt(power)),-120,0)+120)*2+.5)
  bin.hist[bucket]=(bin.hist[bucket] or 0)+weight
 end
end
function Core.analysis_value(bin,method)
 if bin.weight==0 then return -120 end
 if method==1 then return clamp(db(sqrt(bin.sum/bin.weight)),-120,0) end
 if method==3 then return clamp(db(sqrt(bin.peak)),-120,0) end
 local cumulative=0
 for bucket=0,240 do cumulative=cumulative+(bin.hist[bucket] or 0);if cumulative>=bin.weight*.5 then return bucket*.5-120 end end
 return 0
end
function App.begin_analysis()
 if not Media.ready() then return end
 if A.job then return end
 UI.commit_edit()
 local project=R.EnumProjects(-1,'');local plans={};local total=0;local upper=0
 for i=0,R.CountSelectedMediaItems(project)-1 do
  local item=R.GetSelectedMediaItem(project,i);local take=R.GetActiveTake(item)
  assert(take and not R.TakeIsMIDI(take),'選択には音声アイテムのみを含めてください。')
  local source=R.GetMediaItemTake_Source(take);local sr=R.GetMediaSourceSampleRate(source);local ch=R.GetMediaSourceNumChannels(source)
  local length=R.GetMediaItemInfo_Value(item,'D_LENGTH')
  assert(finite(sr) and sr>=8000 and sr<=192000 and (ch==1 or ch==2) and finite(length) and length>0,'8〜192 kHzのモノラル／ステレオ素材に対応します。')
  plans[#plans+1]={item=item,take=take,track=R.GetMediaItemTrack(item),signature=App.item_signature(item),sr=sr,ch=ch,len=length,frames=max(1,floor(length*sr+.5)),volume=R.GetMediaItemTakeInfo_Value(take,'D_VOL')}
  total=total+length;upper=max(upper,sr/2-sr/A.settings.fft)
 end
 assert(#plans>0,'音声アイテムを選択してください。')
 local n=A.settings.fft;local bins={};upper=min(upper,A.settings.maxfreq)
 for i=0,511 do
  local frequency=Core.from_axis(i/511,A.settings.scale,upper)
  bins[i+1]={x=frequency,weight=0,sum=0,peak=0,hist=A.analysis_method==2 and {} or nil}
 end
 local win={};for i=1,n do win[i]=.5-.5*math.cos(2*pi*(i-1)/n) end
 A.job={kind='analysis',project=project,plans=plans,index=1,n=n,hop=n//A.settings.overlap,win=win,bins=bins,method=A.analysis_method,total_seconds=total,completed=0,progress=0}
 UI.release_capture();App.notice('波形を解析中…',false,3600)
end
function App.analysis_step(j)
 App.check_job(j);local p=j.plans[j.index];if not p then return true end
 if not j.aa then
  j.aa=assert(R.CreateTakeAudioAccessor(p.take),'音声アクセサーを作成できません。');j.start=R.GetAudioAccessorStartTime(j.aa)
  assert(R.GetAudioAccessorEndTime(j.aa)-j.start>=p.len-1/p.sr,'音声範囲が不足しています。先にGlueしてください。')
  j.audio_cache=nil;j.buffer=R.new_array(max(32768,j.n)*p.ch);j.at=-j.n+j.hop;j.spectra={}
  j.maps=j.maps or {};local map=j.maps[p.sr]
  if not map then
   map={entries={},needed={}};local seen={}
   for _,bin in ipairs(j.bins) do
    local k=bin.x*j.n/p.sr
    if k<=j.n//2-1 then
     k=max(1,k);local a=floor(k);local b=min(a+1,j.n//2-1)
     map.entries[#map.entries+1]={bin=bin,a=a,b=b,q=k-a}
     for _,index in ipairs({a,b}) do if not seen[index] then seen[index]=true;map.needed[#map.needed+1]=index end end
    end
   end
   j.maps[p.sr]=map
  end
  j.map=map
  for c=1,p.ch do j.spectra[c]={{},{}} end
 end
 assert(not R.AudioAccessorStateChanged(j.aa),'処理中に音声が変更されました。')
 local first=max(0,j.at);local ending=min(p.frames,j.at+j.n);local count=max(0,ending-first);local samples
 local origin;samples,origin=App.audio_samples(j,p,first,count)
 local offset=origin-j.at;local norm=0;local window_offset=first-j.at
 for i=window_offset+1,window_offset+count do norm=norm+j.win[i] end
 for c=1,p.ch do
  local re,im=j.spectra[c][1],j.spectra[c][2]
  for i=1,j.n do local v=samples[(i-1-offset)*p.ch+c] or 0;re[i]=v*j.win[i]*p.volume;im[i]=0 end
  Core.fft(re,im,false)
 end
 if norm>1e-12 then
  local power=j.power or {};j.power=power
  for _,k in ipairs(j.map.needed) do
   local sum=0;for c=1,p.ch do local z=j.spectra[c];sum=sum+z[1][k+1]^2+z[2][k+1]^2 end
   power[k]=sum/p.ch*(2/norm)^2
  end
  local weight=norm*j.hop/(p.sr*(j.n/2))
  for _,entry in ipairs(j.map.entries) do
   local q=entry.q;local value=power[entry.a]*(1-q)+power[entry.b]*q
   Core.analysis_accumulate(entry.bin,value,weight,j.method)
  end
 end
 j.at=j.at+j.hop
 j.progress=clamp((j.completed+clamp(j.at,0,p.frames)/p.sr)/j.total_seconds,0,1)
 if j.at>=p.frames then R.DestroyAudioAccessor(j.aa);j.aa=nil;j.completed=j.completed+p.len;j.index=j.index+1 end
 return j.index>#j.plans
end
function App.finish_analysis(j)
 App.check_job(j,true);local points={}
 for _,bin in ipairs(j.bins) do points[#points+1]={x=bin.x,y=Core.analysis_value(bin,j.method)} end
 local last=points[#points].x
 if last<96000 then points[#points+1]={x=min(96000,last+.001),y=-120};if last+.001<96000 then points[#points+1]={x=96000,y=-120} end end
 local curve={points=points,kind='linear',smoothness=0};local candidate=Core.copy(A.settings);candidate.curve=curve;Core.validate(candidate)
 App.push_history();A.settings.curve=curve;A.selection=nil;A.hover_node=nil;UI.reset_line_preview(true)
 App.changed('周波数特性でカーブを置き換えました。')
end

function App.process(now)
 if not Media.ready() then return end
 local current=A.job;if not current then return end
 local ok,done=xpcall(function()
  local deadline=now+.014
  repeat if (current.kind=='analysis' and App.analysis_step(current) or current.kind~='analysis' and App.step(current)) then return true end until R.time_precise()>=deadline
  return false
 end,debug.traceback)
 if not ok then App.cleanup(current);A.job=nil;App.notice(L.text('処理に失敗しました。')..' '..L.text(App.public_error(done)),true,12)
 elseif done and current.kind=='analysis' then
  local success,err=xpcall(App.finish_analysis,debug.traceback,current);App.cleanup(current);A.job=nil
  if not success then App.notice(App.public_error(err),true,12) end
 elseif done then
  local reduction=0;for _,p in ipairs(current.plans) do reduction=min(reduction,db(p.scale)) end
  local count=#current.plans;App.cleanup(current);A.job=nil
  App.notice(string.format(L.text('%dアイテム完了。終端の1秒後に別アイテムを作成しました。ピーク保護による最大減衰 %.1f dB。'),count,-reduction),false,12)
 end
 A.dirty=true
end

local C={
 bg={.018,.030,.055},bg2={.030,.090,.180},panel={.040,.068,.110},panel2={.055,.125,.205},field={.018,.040,.080},
 edge={.145,.285,.445},edge2={.360,.650,.900},text={.955,.980,1},muted={.690,.780,.875},faint={.390,.505,.635},
 accent={.120,.490,.980},accent2={.650,.895,1},accent3={.045,.235,.520},focus2={.690,.900,1},
 ink={.018,.075,.160},warn={1,.755,.490},red={1,.230,.300}}
local C_BASE={};for k,v in pairs(C) do C_BASE[k]={v[1],v[2],v[3]} end
local fonts={'Yu Gothic UI','Segoe UI','Consolas'}
if BLT_MAC then fonts={'Hiragino Sans','Helvetica Neue','Menlo'} elseif R.GetOS():match('Linux') then fonts={'sans-serif','sans-serif','monospace'} end

function Theme.rgb_to_hsv(c)
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
function Theme.hsv_to_rgb(h,s,v)
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
function Theme.icon_colors()
  local cache=Theme.iconCache
  if cache and cache.enabled==Theme.enabled and cache.r==C.accent[1] and cache.g==C.accent[2] and cache.b==C.accent[3] then return cache[1],cache[2],cache[3] end
  if not Theme.enabled then
    cache={{0.59,0.66,0.64},{0.48,0.53,0.58},{0.56,0.63,0.63},enabled=false,r=C.accent[1],g=C.accent[2],b=C.accent[3]}
    Theme.iconCache=cache;return cache[1],cache[2],cache[3]
  end

  local h,s,v=Theme.rgb_to_hsv(C.accent)
  s=math.max(s,.46)

  local c1=Theme.hsv_to_rgb(h,      s,                v)
  local c2=Theme.hsv_to_rgb(h+.19, math.max(.42,s*.90), v)
  local c3=Theme.hsv_to_rgb(h-.19, math.max(.42,s*.86), v)

  Theme.iconCache={c1,c2,c3,enabled=true,r=C.accent[1],g=C.accent[2],b=C.accent[3]}
  return c1,c2,c3
end
function Theme.copy(c) return {c[1],c[2],c[3]} end
function Theme.mix(a,b,q) return {a[1]+(b[1]-a[1])*q,a[2]+(b[2]-a[2])*q,a[3]+(b[3]-a[3])*q} end
function Theme.luma(c) return c[1]*.2126+c[2]*.7152+c[3]*.0722 end
function Theme.sample(names,fallback)
 if type(R.GetThemeColor)~='function' or type(R.ColorFromNative)~='function' then return Theme.copy(fallback) end
 for _,name in ipairs(names) do
  local value=R.GetThemeColor(name,0)
  if type(value)=='number' and value>=0 then local r,g,b=R.ColorFromNative(value);return {r/255,g/255,b/255} end
 end
 return Theme.copy(fallback)
end
function Theme.restore() for k,v in pairs(C_BASE) do C[k]=Theme.copy(v) end end
function Theme.signature()
 if type(R.GetThemeColor)~='function' then return 'none' end
 local out={};for _,k in ipairs({'col_main_bg2','col_main_text2','col_toolbar_text_on','col_tl_fg','genlist_bg'}) do out[#out+1]=tostring(R.GetThemeColor(k,0)) end
 return table.concat(out,':')
end
function Theme.refresh(force)
 if not Theme.enabled then return false end
 local sig=Theme.signature();if not force and sig==Theme.last_signature then return false end;Theme.last_signature=sig
 local raw_bg=Theme.sample({'col_main_bg2','genlist_bg','col_main_bg'},C_BASE.bg);local dark=Theme.luma(raw_bg)<.5
 local anchor=dark and {0,0,0} or {1,1,1};local bg=Theme.mix(raw_bg,anchor,dark and .18 or .12)
 local generated=dark and {.96,.98,1} or {.035,.045,.06}
 local theme_text=Theme.sample({'col_main_text2','genlist_fg','col_main_text'},generated)
 local text=Theme.mix(generated,theme_text,.18);local accent=Theme.sample({'col_toolbar_text_on','col_tl_fg','col_main_3dhl'},C_BASE.accent2)
 if abs(Theme.luma(accent)-Theme.luma(bg))<.22 then accent=Theme.mix(accent,generated,.55) end
 C.bg=bg;C.bg2=Theme.mix(bg,accent,.08);C.panel=Theme.mix(bg,generated,dark and .045 or .055);C.panel2=Theme.mix(C.panel,accent,.11)
 C.field=Theme.mix(bg,anchor,dark and .06 or .04);C.text=text;C.muted=Theme.mix(text,bg,.30);C.faint=Theme.mix(text,bg,.52)
 C.edge=Theme.mix(bg,text,.20);C.edge2=Theme.mix(accent,text,.18);C.accent=accent;C.accent2=Theme.mix(accent,text,.16);C.accent3=Theme.mix(accent,bg,.48)
 C.focus2=Theme.mix(accent,text,.24);C.ink=Theme.mix(bg,accent,.15)
 C.warn=Theme.copy(C_BASE.warn);C.red=Theme.copy(C_BASE.red);A.dirty=true;return true
end
function Theme.toggle()
 Theme.enabled=not Theme.enabled;App.store(SECTION,'chameleon',Theme.enabled and '1' or '0',true);Theme.last_signature=nil
 if Theme.enabled then Theme.refresh(true);App.notice('CHAMELEON  REAPERテーマに擬態',false,3)
 else Theme.restore();App.notice('CHAMELEON  オリジナル配色',false,3) end
end
Theme.enabled=R.GetExtState(SECTION,'chameleon')=='1';Theme.poll_at=0
if Theme.enabled then Theme.refresh(true) end

local scale,ox,oy,mx,my=1,0,TITLE_H,-1,-1
local widgets={}
local fields={
 {key='fft',label='FFTサイズ',values={1024,2048,4096,8192,16384},digits=0},
 {key='overlap',label='重なり',values={4,8,16},digits=0,unit='x'},
 {key='strength',label='追従強度',min=0,max=100,step=1,digits=0,unit='%'},
 {key='threshold',label='増幅閾値',min=-120,max=0,step=1,digits=0,unit='dBFS'},
 {key='knee',label='移行幅',min=0,max=24,step=1,digits=0,unit='dB'},
 {key='smooth',label='時間平滑化',min=0,max=500,step=1,digits=0,unit='ms'},
 {key='boost',label='最大ブースト',min=0,max=60,step=1,digits=0,unit='dB'},
 {key='cut',label='最大カット',min=0,max=120,step=1,digits=0,unit='dB'},
 {key='ceiling',label='ピーク上限',min=-24,max=0,step=.1,digits=1,unit='dBFS'},
}
local field_by_key={};for _,spec in ipairs(fields) do field_by_key[spec.key]=spec end
field_by_key.period_percent={key='period_percent',label='周期幅',min=1,max=200,step=1,digits=0,unit='%',drawing=true}
field_by_key.height={key='height',label='最大高さ',min=0,max=200,step=1,digits=0,unit='%',drawing=true}

function UI.geometry()
 local content=max(1,gfx.h-TITLE_H);scale=max(.25,min(gfx.w/W,content/H));ox=(gfx.w-W*scale)/2;oy=TITLE_H+(content-H*scale)/2
 mx=(gfx.mouse_x-ox)/scale;my=(gfx.mouse_y-oy)/scale
end
function UI.sx(x) return ox+x*scale end
function UI.sy(y) return oy+y*scale end
function UI.color(c,a) gfx.set(c[1],c[2],c[3],a or 1) end
function UI.rect(x,y,w,h,c,a,fill) UI.color(c,a);gfx.rect(UI.sx(x),UI.sy(y),w*scale,h*scale,fill==false and 0 or 1) end
function UI.line(x,y,x2,y2,c,a) UI.color(c,a);gfx.line(UI.sx(x),UI.sy(y),UI.sx(x2),UI.sy(y2),1) end
function UI.disc(x,y,r,c,a) UI.color(c,a);gfx.circle(UI.sx(x),UI.sy(y),r*scale,1,1) end
function UI.finish_corners(x,y,w,h,cut,top_left,edge,a)
 UI.color(C.bg);gfx.triangle(UI.sx(x+w-cut-1),UI.sy(y+h+1),UI.sx(x+w+1),UI.sy(y+h-cut-1),UI.sx(x+w+1),UI.sy(y+h+1))
 if top_left then gfx.triangle(UI.sx(x-1),UI.sy(y-1),UI.sx(x+cut+1),UI.sy(y-1),UI.sx(x-1),UI.sy(y+cut+1)) end
 UI.line(x+w,y+h-cut,x+w-cut,y+h,edge,a);if top_left then UI.line(x,y+cut,x+cut,y,edge,a) end
end
function UI.thick_line(x,y,x2,y2,c,a,width)
 local dx,dy=x2-x,y2-y;local length=sqrt(dx*dx+dy*dy);if length<1e-9 then return end
 local nx,ny=-dy/length,dx/length
 for i=0,width-1 do local offset=i-(width-1)/2;UI.line(x+nx*offset,y+ny*offset,x2+nx*offset,y2+ny*offset,c,a) end
end
function UI.particle_hash(n,salt) local v=math.sin(n*12.9898+salt*78.233)*43758.5453;return v-math.floor(v) end
function UI.gradient(x,y,w,h,a,b,aa,bb,vertical)
 aa=aa or 1;bb=bb==nil and aa or bb;local n=max(1,(vertical and h or w)*scale)
 gfx.gradrect(UI.sx(x),UI.sy(y),w*scale,h*scale,a[1],a[2],a[3],aa,
  vertical and 0 or (b[1]-a[1])/n,vertical and 0 or (b[2]-a[2])/n,vertical and 0 or (b[3]-a[3])/n,vertical and 0 or (bb-aa)/n,
  vertical and (b[1]-a[1])/n or 0,vertical and (b[2]-a[2])/n or 0,vertical and (b[3]-a[3])/n or 0,vertical and (bb-aa)/n or 0)
end
UI.font_slots={};UI.metric_cache={};UI.metric_count=0;UI.fit_cache={};UI.fit_count=0
function UI.font(size,kind,bold)
 kind=kind or 1;local slot=kind*2+(bold and 1 or 0);local pixels=max(8,floor(size*scale+.5))
 local key=kind..':'..pixels..':'..(bold and 1 or 0)
 if UI.font_slots[slot]~=key then gfx.setfont(slot,fonts[kind] or fonts[1],pixels,bold and 98 or 0);UI.font_slots[slot]=key else gfx.setfont(slot) end
 return key
end
function UI.metrics(text,size,kind,bold)
 local key=UI.font(size,kind,bold)..':'..text;local found=UI.metric_cache[key]
 if found then return found[1],found[2] end
 local w,h=gfx.measurestr(text)
 if UI.metric_count>=1024 then UI.metric_cache={};UI.metric_count=0 end
 UI.metric_cache[key]={w,h};UI.metric_count=UI.metric_count+1;return w,h
end

function UI.fit(text,width,size,kind,bold)
 local shown=L.text(text);local limit=width*scale;local key=UI.font(size,kind,bold)..':'..limit..':'..shown
 local cached=UI.fit_cache[key];if cached then return cached end
 local result=shown
 if UI.metrics(shown,size,kind,bold)>limit then
  local low,high=0,utf8.len(shown) or #shown
  while low<high do local mid=(low+high+1)//2;local stop=utf8.offset(shown,mid+1) or #shown+1
   if UI.metrics(shown:sub(1,stop-1)..'…',size,kind,bold)<=limit then low=mid else high=mid-1 end
  end
  local stop=utf8.offset(shown,low+1) or #shown+1;result=shown:sub(1,stop-1)..'…'
 end
 if UI.fit_count>=1024 then UI.fit_cache={};UI.fit_count=0 end
 UI.fit_cache[key]=result;UI.fit_count=UI.fit_count+1;return result
end
function UI.label(text,x,y,size,c,kind,bold,width,align)
 local shown=width and UI.fit(text,width,size,kind,bold) or L.text(text);local tw,th=UI.metrics(shown,size,kind,bold);local px=UI.sx(x)
 if width and align=='center' then px=UI.sx(x)+(width*scale-tw)/2 elseif width and align=='right' then px=UI.sx(x+width)-tw end
 UI.color(c or C.text);gfx.x=px;gfx.y=UI.sy(y)+(size*scale-th)*.15;gfx.drawstr(shown)
end
function UI.panel(x,y,w,h,tone)
 tone=tone or C.accent2;UI.gradient(x,y,w,h,C.panel2,C.panel,.42,.94,true);UI.rect(x,y,w,h,tone,.018)
 UI.line(x,y+h,x+w,y+h,C.edge,.46);UI.line(x,y,x,y+h,tone,.30);UI.finish_corners(x,y,w,h,6,false,C.edge2,.28)
end
function UI.inside(x,y,w,h) return mx>=x and mx<=x+w and my>=y and my<=y+h end
function UI.register(id,x,y,w,h,fn,enabled)
 widgets[#widgets+1]={id=id,x=x,y=y,w=w,h=h,fn=fn,enabled=enabled~=false}
end
function UI.hit()
 for i=#widgets,1,-1 do local w=widgets[i];if UI.inside(w.x,w.y,w.w,w.h) then return w end end
end
UI.line_dim_panel={.16,.16,.17};UI.line_dim_base={.09,.09,.10}
UI.line_dim_field={.12,.12,.13};UI.line_dim_field_base={.085,.085,.095}
function UI.canvas_color(original,role) return Theme.enabled and C[role] or original end
function UI.button(id,text,x,y,w,h,fn,enabled,selected,tone)
 local child=id=='pattern' or id=='direction' or id=='shape_envelope' or id=='period_shape'
 local dim=child and A.tool~='line';enabled=enabled~=false and not dim
 local hover=UI.inside(x,y,w,h) and A.active and enabled;local c=dim and C.muted or tone or C.accent2
 A.button_glow=A.button_glow or {};local a=A.button_glow[id] or 0;a=a+((hover and 1 or 0)-a)*min(1,(UI.button_dt or 0)*14);A.button_glow[id]=a
 local dy=A.pressed==id and (gfx.mouse_cap&1)~=0 and 1.5 or 0;local yy=y+dy
 UI.gradient(x,yy,w,h,dim and UI.canvas_color(UI.line_dim_panel,'panel2') or C.panel2,dim and UI.canvas_color(UI.line_dim_base,'panel') or C.panel,dim and .95 or (.34+.16*a),.92)
 if selected and enabled and id:match('^tool_') then UI.rect(x+1,yy+1,w-2,h-2,c,.10) end
 UI.gradient(x,yy,w,1,c,c,selected and .68 or (.16+.50*a),.02)
 UI.line(x,yy+h,x+w,yy+h,C.edge,.46)
 if hover or selected then UI.rect(x,yy,id:match('^tool_') and 4 or 2,h,c,selected and .55 or .65) end
 UI.finish_corners(x,yy,w,h,6,false,selected and c or C.edge2,(enabled or dim) and (.28+.35*a) or .16)
 UI.font(14,1,true);UI.color(dim and C.muted or enabled and ((hover or selected) and C.text or C.muted) or C.faint)
 gfx.x,gfx.y=UI.sx(x),UI.sy(yy+2);gfx.drawstr(UI.fit(text,w,14,1,true),5,UI.sx(x+w),UI.sy(yy+h-1))
 UI.register(id,x,y,w,h,fn,enabled)
end
function UI.value(key) local spec=field_by_key[key];return spec and spec.drawing and A[key] or A.settings[key] end
function UI.value_text(key,value)
 local spec=field_by_key[key];local text=string.format('%.'..(spec.digits or 0)..'f',value)
 if (spec.digits or 0)>0 then text=text:gsub('0+$',''):gsub('%.$','') end
 return text
end
function UI.nearest_value(values,value)
 local best,dist=values[1],math.huge;for _,v in ipairs(values) do local d=abs(v-value);if d<dist then best,dist=v,d end end;return best
end
function UI.set_value(key,raw,flash,persist_now)
 local spec=field_by_key[key];local current=UI.value(key);local n=tonumber(raw);local invalid=not finite(n)
 if invalid then n=current end
 local value
 if spec.values then value=UI.nearest_value(spec.values,n) else
  value=clamp(n,spec.min,spec.max);local factor=10^(spec.digits or 0);value=math.floor(value*factor+.5)/factor
 end
 if flash~=false and (invalid or abs(value-n)>1e-9) then A.number_flash[key]=R.time_precise();A.dirty=true end
 if spec.drawing then if A[key]~=value then A[key]=value;if UI.reset_line_preview then UI.reset_line_preview(true) end end else A.settings[key]=value;A.preset_dirty=true end
 if persist_now then App.persist() end;A.dirty=true;return value
end
function UI.step_value(key,delta,persist_now)
 local spec=field_by_key[key];local value=UI.value(key)
 if spec.values then
  local index=1;for i,v in ipairs(spec.values) do if v==value then index=i;break end end
  value=spec.values[clamp(index+delta,1,#spec.values)]
 else value=value+delta*spec.step end
 return UI.set_value(key,value,true,persist_now)
end
function UI.commit_edit()
 local edit=A.edit;if not edit then return end;A.edit=nil;UI.set_value(edit.key,edit.text,true,true)
end
function UI.line_field(key,x,y,w,h,enabled,dim)
 local spec=field_by_key[key];enabled=enabled~=false and not dim
 local active=enabled and A.edit and A.edit.key==key;local hot=enabled and UI.inside(x,y,w,h)
 UI.gradient(x,y,w,h,dim and UI.canvas_color(UI.line_dim_field,'field') or C.field,dim and UI.canvas_color(UI.line_dim_field_base,'panel') or C.panel,.98,.60)
 UI.line(x,y,x,y+h,dim and C.muted or C.accent2,hot and .8 or .35)
 UI.finish_corners(x,y,w,h,5,false,C.edge2,hot and .65 or .3)
 UI.label(spec.label,x+6,y+5,12,C.muted,1,false,60)
 if active and A.edit.selected then UI.rect(x+65,y+3,w-83,22,C.focus2,.8) end
 local value=active and A.edit.text or UI.value_text(key,UI.value(key))
 UI.label(value,x+65,y+5,15,active and A.edit.selected and C.ink or dim and C.muted or C.text,3,true,w-89,'right')
 UI.label(spec.unit or '',x+w-20,y+9,10,C.muted,1,false,16,'right')
 local flash=A.number_flash[key];if flash then local q=max(0,1-(R.time_precise()-flash)/1.2);if q>0 then UI.rect(x,y,w,h,C.red,.25*q) end end
 UI.register('field_'..key,x,y,w,h,UI.noop,enabled)
end
function UI.field(key,x,y,w,h,enabled,dim)
 if field_by_key[key].drawing then return UI.line_field(key,x,y,w,h,enabled,dim) end
 local spec=field_by_key[key];enabled=enabled~=false and not dim;local active=enabled and A.edit and A.edit.key==key;local hot=UI.inside(x,y,w,h) and enabled;local tone=dim and C.faint or C.accent2
 UI.gradient(x,y,w,h,dim and C.bg or C.field,C.panel,dim and .35 or .96,dim and .25 or .58);UI.line(x,y,x,y+h,active and C.focus2 or tone,active and .95 or hot and .72 or .34);UI.finish_corners(x,y,w,h,5,false,active and C.focus2 or C.edge2,active and .78 or hot and .52 or dim and .08 or .28)
 local flash=A.number_flash[key];if flash then local age=R.time_precise()-flash;if age<1.2 then local q=1-age/1.2;UI.rect(x-3,y-3,w+6,h+6,C.red,.08*q);UI.rect(x,y,w,h,C.red,.25*q) end end
 UI.label(spec.label,x+8,y+7,11,enabled and C.muted or C.faint,1,false,w*.55)
 local text=active and A.edit.text or UI.value_text(key,UI.value(key));local unit=spec.unit and ' '..spec.unit or ''
 if active and A.edit.selected then UI.rect(x+w*.46,y+4,w*.50,25,C.focus2,.78) end
 UI.label(text..unit,x+w*.46,y+5,15,enabled and (active and A.edit.selected and C.ink or active and C.focus2 or C.text) or C.faint,3,true,w*.50,'right')
 UI.register('field_'..key,x,y,w,h,UI.noop,enabled)
end

Presets.items={};Presets.revision=0
Presets.factory={name='ファクトリーデフォルト',data=Core.encode(Core.defaults()),factory=true}
Presets.header='BLT_SPECTRAL_NORMALIZER_PRESET_V1\n'
Presets.bundleHeader='BLT_SPECTRAL_NORMALIZER_PRESET_BUNDLE_V1\n'
function Presets.valid_name(name)
 if type(name)~='string' then return end
 name=name:match('^%s*(.-)%s*$')
 return utf8.len(name) and name~='' and #name<=120 and not name:find('[%c|<>!#]') and name
end
function Presets.isFactory(p) return p and (p.factory or p.name==Presets.factory.name) end
function Presets.find(name) for i,p in ipairs(Presets.items) do if p.name==name then return i,p end end end
function Presets.current_entry()
 if A.preset_name==Presets.factory.name then return Presets.factory end
 local _,p=Presets.find(A.preset_name);return p
end
function Presets.dirty()
 local p=Presets.current_entry()
 return p and Core.encode(A.settings)~=p.data or not p and A.preset_dirty or false
end
function Presets.capture(name)
 UI.commit_edit();App.persist()
 assert(Presets.valid_name(name),'有効なプリセット名を入力してください。')
 return {name=name,data=Core.encode(A.settings)}
end
function Presets.encode(p) return Presets.header..p.name..'\n'..p.data end
function Presets.decode(data)
 if type(data)~='string' or #data>BLTPresetLimits.stringBytes or data:sub(1,#Presets.header)~=Presets.header then return end
 local name,body=data:sub(#Presets.header+1):match('^([^\n]+)\n(.*)$')
 if not Presets.valid_name(name) or name==Presets.factory.name then return end
 local ok,s=pcall(Core.decode,body);if not ok then return end
 local canonical=Core.encode(s);if body~=canonical then return end
 return {name=name,data=canonical}
end
function Presets.encodeBundle(items)
 local out={Presets.bundleHeader,tostring(#items),'\n'}
 local size=128;for _,p in ipairs(items) do local data=Presets.encode(p);size=size+#data+32;if size>BLTPresetLimits.bytes then BLTPresetLimits.show(L.code=='EN');return end;out[#out+1]=#data..'\n'..data end
 return table.concat(out)
end
function Presets.decodeTransfer(data)
 if type(data)~='string' or #data>BLTPresetLimits.bytes then return end
 local p=Presets.decode(data);if p then return {p} end
 if data:sub(1,#Presets.bundleHeader)~=Presets.bundleHeader then return end
 local cursor=#Presets.bundleHeader+1
 local function number()
  local stop=data:find('\n',cursor,true);if not stop then return end
  local text=data:sub(cursor,stop-1);cursor=stop+1
  if not text:match('^%d+$') then return end;return tonumber(text)
 end
 local count=number();if not count or count<1 or count>200 then return end
 local items,names={},{}
 for i=1,count do
  local size=number();if not size or size<1 or size>BLTPresetLimits.stringBytes or cursor+size-1>#data then return end
  local entry=Presets.decode(data:sub(cursor,cursor+size-1));cursor=cursor+size
  if not entry or names[entry.name] then return end;names[entry.name]=true;items[i]=entry
 end
 if cursor~=#data+1 then return end;return items
end
function Presets.load()
 Presets.items={};local names={};local count=clamp(floor(tonumber(R.GetExtState(SECTION,'preset_count')) or 0),0,200)
 for i=1,count do
  local name=Presets.valid_name(R.GetExtState(SECTION,'preset_name_'..i));local data=R.GetExtState(SECTION,'preset_data_'..i)
  local ok,s=pcall(Core.decode,data)
  if name and name~=Presets.factory.name and not names[name] and ok then names[name]=true;Presets.items[#Presets.items+1]={name=name,data=Core.encode(s)} end
 end
 table.sort(Presets.items,function(a,b)return a.name<b.name end)
 local current=R.GetExtState(SECTION,'current_preset')
 A.preset_name=current=='__factory__' and Presets.factory.name or (Presets.find(current) and current or nil)
 Presets.current=Presets.current_entry();A.preset_dirty=Presets.dirty();Presets.revision=Presets.revision+1
end
function Presets.store()
 local previous=clamp(floor(tonumber(R.GetExtState(SECTION,'preset_count')) or 0),0,200)
 App.store(SECTION,'preset_count',tostring(#Presets.items),true)
 for i,p in ipairs(Presets.items) do App.store(SECTION,'preset_name_'..i,p.name,true);App.store(SECTION,'preset_data_'..i,p.data,true) end
 for i=#Presets.items+1,previous do App.store(SECTION,'preset_name_'..i,'',true);App.store(SECTION,'preset_data_'..i,'',true) end
 Presets.revision=Presets.revision+1;A.dirty=true
end
function Presets.put(p)
 if Presets.isFactory(p) then return false end
 local index=Presets.find(p.name)
 if index and R.MB(L.text('同名のプリセットを上書きしますか？'),L.text('プリセット'),4)~=6 then return false end
 assert(index or #Presets.items<200,'プリセットは200個まで保存できます。')
 if index then Presets.items[index]=p else Presets.items[#Presets.items+1]=p;table.sort(Presets.items,function(a,b)return a.name<b.name end) end
 Presets.store();return true
end
function Presets.save(as_new)
 if A.job or A.modal then return end
 if not as_new and Presets.isFactory(Presets.current_entry()) then return end
 local name=A.preset_name
 if as_new or not name then
  local ok,text=R.GetUserInputs(L.text('名前を付けて保存…'),1,L.text('プリセット')..':,extrawidth=180',Presets.isFactory(Presets.current_entry()) and '' or name or '')
  if not ok then return end;name=Presets.valid_name(text);assert(name and name~=Presets.factory.name,'有効なプリセット名を入力してください。')
 end
 local p=Presets.capture(name)
 if Presets.put(p) then A.preset_name=name;Presets.current=p;A.preset_dirty=false;App.store(SECTION,'current_preset',name,true);App.notice('プリセットを保存しました。',false) end
end
function Presets.apply(p)
 if A.job or A.modal then return end
 UI.commit_edit()
 local settings=Core.decode(p.data)
 if Presets.dirty() and R.MB(L.text('未保存の変更を破棄して読み込みますか？'),L.text('プリセット'),4)~=6 then return end
 UI.release_capture();A.edit=nil;A.selection=nil;A.hover_node=nil;A.settings=settings
 for key in pairs(Core.DRAW_LIMITS) do A[key]=settings[key] end
 UI.reset_line_preview(true);A.history={};A.redo={};A.preset_name=p.name;Presets.current=p;A.preset_dirty=false
 App.persist();App.store(SECTION,'current_preset',Presets.isFactory(p) and '__factory__' or p.name,true)
 App.notice('プリセットを読み込みました。',false)
end
function Presets.merge(items)
 local merged,index={},{};local conflicts=false
 for i,p in ipairs(Presets.items) do merged[i]=p;index[p.name]=i end
 for _,p in ipairs(items) do
  if index[p.name] then conflicts=true;merged[index[p.name]]=p else merged[#merged+1]=p;index[p.name]=#merged end
 end
 assert(#merged<=200,'プリセットは200個まで保存できます。')
 if conflicts and R.MB(L.text('同名のプリセットを上書きしますか？'),L.text('プリセット'),4)~=6 then return false end
 table.sort(merged,function(a,b)return a.name<b.name end);Presets.items=merged;Presets.store();Presets.current=Presets.current_entry();A.preset_dirty=Presets.dirty();return true
end
function Presets.import()
 if A.job or A.modal then return end
 local ok,path=R.GetUserFileNameForRead('',L.text('インポート…'),'.bltpreset');if not ok then return end
 local file=assert(io.open(path,'rb'),'プリセットファイルを開けません。');local data=file:read(BLTPresetLimits.bytes+1);file:close()
 if #data>BLTPresetLimits.bytes then BLTPresetLimits.show(L.code=='EN');return end
 local items=Presets.decodeTransfer(data);assert(items,'このアプリのプリセットではありません。')
 if Presets.merge(items) then App.notice('インポートしました。一覧から選択してください。',false) end
end
function Presets.export(all)
 if A.job or A.modal then return end
 local data,filename,title
 if all then
  if #Presets.items==0 then return end;data=Presets.encodeBundle(Presets.items);filename='SPECTRAL_NORMALIZER_presets.bltpreset';title='プリセット一覧をエクスポート'
 else
  if Presets.isFactory(Presets.current_entry()) then return end
  data=Presets.encode(Presets.capture(A.preset_name or '現在値'));filename='Spectral.bltpreset';title='現在値をエクスポート'
 end
 if not data then return end;if #data>BLTPresetLimits.bytes then BLTPresetLimits.show(L.code=='EN');return end
 local ok,path=R.JS_Dialog_BrowseForSaveFile(L.text(title),R.GetProjectPath(''),filename,'BLT preset (*.bltpreset)\0*.bltpreset\0')
 if not ok or ok==0 or not path or path=='' then return end
 if not path:lower():match('%.bltpreset$') then path=path..'.bltpreset' end
 local exists=io.open(path,'rb');if exists then exists:close();if R.MB(L.text('同名ファイルを上書きしますか？'),L.text('プリセット'),4)~=6 then return end end
 local file=assert(io.open(path,'wb'),'保存先を開けません。');local wrote,err=file:write(data);local closed=file:close();assert(wrote and closed,err or '保存に失敗しました。')
 App.notice('プリセットをエクスポートしました。',false)
end
function Presets.step(delta)
 if A.job or A.modal then return end
 local index=A.preset_name==Presets.factory.name and 1 or nil
 for i,p in ipairs(Presets.items) do if p.name==A.preset_name then index=i+1;break end end
 index=index and ((index-1+delta)%(#Presets.items+1))+1 or 1
 Presets.apply(index==1 and Presets.factory or Presets.items[index-1])
end

Presets.popup={width=286,rowHeight=29,headerHeight=34,visiblePresets=7,hoverDelay=1}
function Presets.fit(text,width)
 local cache=Presets.fitCache or {};Presets.fitCache=cache
 local key=width..':'..text;local hit=cache[key];if hit then return hit end
 local shown=text
 if gfx.measurestr(shown)>width then
  local lo,hi=0,utf8.len(text) or 0
  while lo<hi do local mid=(lo+hi+1)//2;local stop=utf8.offset(text,mid+1) or #text+1
   if gfx.measurestr(text:sub(1,stop-1)..'…')<=width then lo=mid else hi=mid-1 end
  end
  shown=text:sub(1,(utf8.offset(text,lo+1) or #text+1)-1)..'…'
 end
 if (Presets.fitCount or 0)>=512 then cache={};Presets.fitCache=cache;Presets.fitCount=0 end
 cache[key]=shown;Presets.fitCount=(Presets.fitCount or 0)+1;return shown
end
function Presets.menu(x,y)
  if A.job or A.modal then return end;UI.commit_edit();UI.release_capture();Presets.current=Presets.current_entry()
  Presets.open=true;Presets.page="main";Presets.offset=0;Presets.selected=1
  Presets.down=false;Presets.pressed=nil;Presets.mx=nil;Presets.my=nil;Presets.hoverSince=nil
  A.dirty=true
end
function Presets.dismiss()
  Presets.swallow=((gfx.mouse_cap or 0)&1)~=0
  Presets.open=false;Presets.hoverSince=nil;Presets.pressed=nil;A.dirty=true
end
function Presets.buildRows()
  if Presets.page=="load" then
    local rows={{text="戻る",icon="back",action=function() Presets.page="main";Presets.selected=1 end}}
    local count=math.min(Presets.popup.visiblePresets,#Presets.items-Presets.offset)
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
  local w=math.min(Presets.popup.width,gfx.w-12)
  local x=math.max(6,gfx.w-w-6);local y=TITLE_H+2
  local top=y+Presets.popup.headerHeight
  for _,r in ipairs(rows) do if r.gap then top=top+9 end;r.y=top;top=top+Presets.popup.rowHeight end
  local h=top-y+8+(Presets.page=="load" and #Presets.items>Presets.popup.visiblePresets and 18 or 0)
  Presets.layoutCache={rows=rows,windowWidth=gfx.w,x=x,y=y,w=w,h=h}
  return x,y,w,h,rows
end
function Presets.activate(i)
  local rows=Presets.rows();local row=rows[i]
  if row and not row.disabled then row.action();A.dirty=true end
end
function Presets.key(k)
  if k==27 then Presets.dismiss()
  elseif k==13 then Presets.activate(Presets.selected or 1)
  elseif k==1818584692 and Presets.page=="load" then Presets.page="main";Presets.selected=1
  elseif k==30064 or k==1685026670 then
    local delta=k==30064 and -1 or 1
    local rows=Presets.rows();local n=(Presets.selected or 1)+delta
    if Presets.page=="load" and n>#rows and Presets.offset+Presets.popup.visiblePresets<#Presets.items then Presets.offset=Presets.offset+1;n=#rows
    elseif Presets.page=="load" and n<2 and Presets.offset>0 then Presets.offset=Presets.offset-1;n=2 end
    Presets.selected=math.max(1,math.min(#rows,n))
  end
  A.dirty=true
end
function Presets.update(active)
  if Presets.swallow and ((gfx.mouse_cap or 0)&1)==0 then Presets.swallow=false end
  if not Presets.open then return end
  if not active or A.job or A.modal then Presets.dismiss();return end
  local x,y,w,h,rows=Presets.layout()
  local mx,my=gfx.mouse_x,gfx.mouse_y;local down=(gfx.mouse_cap&1)~=0
  local inside=mx>=x and mx<x+w and my>=y and my<y+h
  local hit=nil
  if inside then for i,r in ipairs(rows) do if my>=r.y and my<r.y+Presets.popup.rowHeight then hit=i end end end
  if mx~=Presets.mx or my~=Presets.my then Presets.selected=hit;Presets.mx=mx;Presets.my=my end
  local wheel=gfx.mouse_wheel or 0
  if wheel~=0 then
    if inside and Presets.page=="load" then Presets.offset=math.max(0,math.min(math.max(0,#Presets.items-Presets.popup.visiblePresets),Presets.offset+(wheel>0 and -1 or 1)));Presets.selected=nil end
    gfx.mouse_wheel=0
  end
  -- Hover only opens the preset list, never applies a preset automatically.
  if Presets.page=="main" and hit==2 and #Presets.items>0 and not down then
    Presets.hoverSince=Presets.hoverSince or R.time_precise()
    if R.time_precise()-Presets.hoverSince>=Presets.popup.hoverDelay then Presets.activate(2);Presets.down=down;return end
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
function Presets.draw()
  if not Presets.open then return end
  local x,y,w,h,rows=Presets.layout()
  gfx.set(0,0,0,.22);gfx.rect(x+3,y+4,w,h,1)
  gfx.set(C.panel[1],C.panel[2],C.panel[3],1);gfx.rect(x,y,w,h,1)
  gfx.set(C.edge2[1],C.edge2[2],C.edge2[3],.65);gfx.roundrect(x,y,w,h,3,1)
  UI.font(12/scale,1,false)
  gfx.set(C.muted[1],C.muted[2],C.muted[3],.9);gfx.x=x+12;gfx.y=y+9
  local title=Presets.page=="load" and L.text("プリセット") or (L.text("現在: ")..(Presets.current and (Presets.isFactory(Presets.current) and L.text(Presets.current.name) or Presets.current.name) or L.text("未選択"))..(Presets.dirty() and " *" or ""))
  gfx.drawstr(Presets.fit(title,w-24))
  gfx.set(C.edge[1],C.edge[2],C.edge[3],.65);gfx.line(x+10,y+30,x+w-10,y+30)
  UI.font(13/scale,1,false)
  for i,r in ipairs(rows) do
    if r.gap then gfx.set(C.edge[1],C.edge[2],C.edge[3],.65);gfx.line(x+10,r.y-5,x+w-10,r.y-5) end
    if i==Presets.selected and not r.disabled then
      gfx.set(C.accent2[1],C.accent2[2],C.accent2[3],.18);gfx.rect(x+1,r.y,w-2,Presets.popup.rowHeight,1)
      gfx.set(C.accent2[1],C.accent2[2],C.accent2[3],.8);gfx.rect(x+1,r.y,2,Presets.popup.rowHeight,1)
    end
    gfx.set(C.text[1],C.text[2],C.text[3],r.disabled and .3 or .94)
    Presets.icon(r.icon,x+13,r.y+8)
    gfx.x=x+39;gfx.y=r.y+7;gfx.drawstr(Presets.fit(r.literal and r.text or L.text(r.text),w-65))
    if r.arrow then gfx.line(x+w-18,r.y+10,x+w-14,r.y+14);gfx.line(x+w-14,r.y+14,x+w-18,r.y+18) end
  end
  if Presets.page=="load" and #Presets.items>Presets.popup.visiblePresets then
    UI.font(10/scale,1,false)
    gfx.set(C.muted[1],C.muted[2],C.muted[3],.8);gfx.x=x+12;gfx.y=y+h-19
    gfx.drawstr(string.format(L.code=='EN' and "%d–%d / %d   Scroll to select" or "%d–%d / %d   スクロールで選択",Presets.offset+1,math.min(Presets.offset+Presets.popup.visiblePresets,#Presets.items),#Presets.items))
  end
end


Presets.load()

Chrome.title='BLT Spectral Normalizer';Chrome.text='S P E C T R A L   N O R M A L I Z E R';Chrome.window=nil;Chrome.minW=1000;Chrome.minH=740
Chrome.drag=nil;Chrome.resize=nil;Chrome.press=nil;Chrome.resize_cursor=nil;Chrome.isWindows=R.GetOS():match('Win')~=nil
Chrome.cursor_ids={we=32644,ns=32645,nwse=32642,nesw=32643,arrow=32512};Chrome.cursors={}
function Chrome.layout()
 if Chrome.layoutWidth==gfx.w then return Chrome.layoutCache end
 local close=gfx.w-38;local reset=close-34;local theme=reset-34;local language=theme-26;local nextp=language-20;local prev=nextp-20;local preset=prev-84
 Chrome.layoutWidth=gfx.w
 Chrome.layoutCache={close=close,reset=reset,theme=theme,language=language,next=nextp,prev=prev,preset=preset}
 return Chrome.layoutCache
end
function Chrome.handle()
 if Chrome.window and R.JS_Window_IsWindow(Chrome.window) then return Chrome.window end
 Chrome.window=R.JS_Window_Find(Chrome.title,true);return Chrome.window
end
function Chrome.position(hwnd,x,y,w,h)
 x,y,w,h=floor(x+.5),floor(y+.5),floor(w+.5),floor(h+.5)
 local ok,l,t,r,b=WindowGeometry.JS_Window_GetRect(hwnd)
 if ok and l==x and t==y and r-l==w and b-t==h then return true end
 return WindowGeometry.JS_Window_SetPosition(hwnd,x,y,w,h)
end
function Chrome.resize_hit(x,y)
 if x<0 or y<0 or x>=gfx.w or y>=gfx.h then return end
 local edge,corner=6,22;local l=x<edge;local r=x>=gfx.w-edge;local top=y<edge;local bot=y>=gfx.h-edge
 if top and x>=Chrome.layout().preset and not r then return end
 if (l and y<corner) or (top and x<corner) then return 'lt' end
 if (r and y<corner) or (top and x>=gfx.w-corner) then return 'rt' end
 if (l and y>=gfx.h-corner) or (bot and x<corner) then return 'lb' end
 if (r and y>=gfx.h-corner) or (bot and x>=gfx.w-corner) then return 'rb' end
 return l and 'l' or r and 'r' or top and 't' or bot and 'b' or nil
end
function Chrome.cursor(mode)
 local kind=(mode=='l' or mode=='r') and 'we' or (mode=='t' or mode=='b') and 'ns' or (mode=='lt' or mode=='rb') and 'nwse' or (mode=='rt' or mode=='lb') and 'nesw' or nil
 Chrome.resize_cursor=kind
 local use=kind or 'arrow';local cursor=Chrome.cursors[use]
 if not cursor then cursor=R.JS_Mouse_LoadCursor and R.JS_Mouse_LoadCursor(Chrome.cursor_ids[use]);Chrome.cursors[use]=cursor end
 if gfx.setcursor then gfx.setcursor(Chrome.cursor_ids[use]) end
 if cursor and R.JS_Mouse_SetCursor then R.JS_Mouse_SetCursor(cursor) end
end
function Chrome.control_at(x,y)
 if x<0 or x>=gfx.w or y<0 or y>=TITLE_H then return end;local b=Chrome.layout()
 if x>=b.close then return 'close' elseif x>=b.reset then return 'reset' elseif x>=b.theme then return 'theme' elseif x>=b.language then return 'language'
 elseif x>=b.next then return 'next' elseif x>=b.prev then return 'prev' elseif x>=b.preset then return 'preset' else return 'drag' end
end
function Chrome.begin_resize(mode)
 local hwnd=Chrome.handle();if not hwnd then return end;local ok,l,t,r,b=WindowGeometry.JS_Window_GetRect(hwnd);if not ok then return end
 local x,y=WindowGeometry.GetMousePosition();Chrome.resize={mode=mode,mx=x,my=y,l=l,t=t,r=r,b=b};Chrome.drag=nil
end
function Chrome.update_move()
 local hwnd=Chrome.handle();if not hwnd then Chrome.drag=nil;Chrome.resize=nil;return end;local x,y=WindowGeometry.GetMousePosition()
 if Chrome.drag then local d=Chrome.drag;Chrome.position(hwnd,d.l+x-d.mx,d.t+y-d.my,d.w,d.h)
 elseif Chrome.resize then
  local d=Chrome.resize;local dx,dy=x-d.mx,y-d.my;local l,t,r,b=d.l,d.t,d.r,d.b
  if d.mode:find('l',1,true) then l=min(d.l+dx,r-Chrome.minW) end;if d.mode:find('r',1,true) then r=max(d.r+dx,l+Chrome.minW) end
  if d.mode:find('t',1,true) then t=min(d.t+dy,b-Chrome.minH) end;if d.mode:find('b',1,true) then b=max(d.b+dy,t+Chrome.minH) end
  Chrome.position(hwnd,l,t,r-l,b-t)
 end
end
function Chrome.reset_window()
 local hwnd=Chrome.handle();if not hwnd then return end;local ok,l,t=WindowGeometry.JS_Window_GetRect(hwnd);if ok then Chrome.position(hwnd,l,t,W,H+TITLE_H) end
 App.store(SECTION,'window_w',tostring(W),true);App.store(SECTION,'window_h',tostring(H+TITLE_H),true);A.dirty=true
end
function Chrome.action(id)
 if (A.job or A.modal) and (id=='preset' or id=='prev' or id=='next') then return end
 if id=='close' then A.closing=true elseif id=='reset' then Chrome.reset_window() elseif id=='theme' then Theme.toggle()
 elseif id=='language' then L.toggle();A.status=L.text('音声アイテムを選択し、目標カーブを描いてください。');A.status_until=0;A.dirty=true elseif id=='preset' then Presets.menu() elseif id=='prev' then Presets.step(-1) elseif id=='next' then Presets.step(1) end
end
function Chrome.input(down,pressed,released)
 local x,y=gfx.mouse_x,gfx.mouse_y;local resize=Chrome.resize_hit(x,y);Chrome.cursor(Chrome.resize and Chrome.resize.mode or resize)
 local control=Chrome.control_at(x,y)
 if pressed and (resize or control) then
  if resize then Chrome.begin_resize(resize)
  elseif control=='drag' then
   local hwnd=Chrome.handle()
   if hwnd then local ok,l,t,r,b=WindowGeometry.JS_Window_GetRect(hwnd);if ok then local sx,sy=WindowGeometry.GetMousePosition();Chrome.drag={mx=sx,my=sy,l=l,t=t,w=r-l,h=b-t} end end
  else Chrome.press=control end
 end
 if down and (Chrome.drag or Chrome.resize) then Chrome.update_move() end
 if released then
  if Chrome.press and control==Chrome.press then Chrome.action(Chrome.press) end
  Chrome.press=nil;Chrome.drag=nil;Chrome.resize=nil
 end
 return control~=nil or resize~=nil or Chrome.drag~=nil or Chrome.resize~=nil or Chrome.press~=nil
end
function Chrome.draw()
 local w=gfx.w;local b=Chrome.layout();local x,y=gfx.mouse_x,gfx.mouse_y;local hot=Chrome.control_at(x,y)
 gfx.set(C.bg[1],C.bg[2],C.bg[3],1);gfx.rect(0,0,w,TITLE_H,1)
 gfx.gradrect(0,0,w,TITLE_H,C.field[1],C.field[2],C.field[3],.72,0,0,0,0,(C.bg[1]-C.field[1])/TITLE_H,(C.bg[2]-C.field[2])/TITLE_H,(C.bg[3]-C.field[3])/TITLE_H,.22/TITLE_H)
 gfx.set(C.edge[1],C.edge[2],C.edge[3],.44);gfx.line(0,TITLE_H-1,w,TITLE_H-1)
 gfx.setfont(14,fonts[2],10,0);gfx.set(C.accent2[1],C.accent2[2],C.accent2[3],.88);gfx.x=14;gfx.y=7;gfx.drawstr(Chrome.text)
 if hot and hot~='drag' then local hx=hot=='close' and b.close or hot=='reset' and b.reset or hot=='theme' and b.theme or hot=='language' and b.language or hot=='next' and b.next or hot=='prev' and b.prev or b.preset;local hw=hot=='close' and 38 or hot=='reset' and 34 or hot=='theme' and 34 or hot=='language' and 26 or hot=='preset' and 84 or 20;local hc=hot=='close' and C.red or C.accent;gfx.set(hc[1],hc[2],hc[3],hot=='close' and .10 or .09);gfx.rect(hx,0,hw,TITLE_H,1);gfx.set(hc[1],hc[2],hc[3],hot=='close' and .56 or .34);gfx.line(hx,TITLE_H-1,hx+hw,TITLE_H-1) end
 gfx.set(C.edge[1],C.edge[2],C.edge[3],(hot=='preset' or hot=='prev' or hot=='next') and .90 or .50);gfx.roundrect(b.preset+2,3,b.language-b.preset-5,20,3,1)
 gfx.set(C.muted[1],C.muted[2],C.muted[3],.35);gfx.line(b.language-1,6,b.language-1,20)
 local pc=hot=='preset' and C.accent2 or C.muted;gfx.set(pc[1],pc[2],pc[3],hot=='preset' and .98 or .80);gfx.roundrect(b.preset+10,7,7,8,1,1);gfx.roundrect(b.preset+13,10,7,8,1,1)
 gfx.setfont(15,fonts[2],10,0);gfx.x=b.preset+26;gfx.y=7;gfx.drawstr('PRESET');gfx.line(b.preset+67,11,b.preset+70,14);gfx.line(b.preset+70,14,b.preset+73,11)
 if A.preset_dirty then gfx.set(C.warn[1],C.warn[2],C.warn[3],.95);gfx.circle(b.preset+23,6,1.3,1,1) end
 for _,q in ipairs({{b.prev,-1,'prev'},{b.next,1,'next'}}) do local cx,cy=q[1]+10,13;local ac=hot==q[3] and C.accent2 or C.muted;gfx.set(ac[1],ac[2],ac[3],hot==q[3] and .98 or .80);gfx.line(cx-q[2]*2,cy-4,cx+q[2]*2,cy);gfx.line(cx+q[2]*2,cy,cx-q[2]*2,cy+4) end
 gfx.setfont(16,fonts[2],12,98);local lc=hot=='language' and C.accent2 or C.text;gfx.set(lc[1],lc[2],lc[3],hot=='language' and 1 or .95);local lw=gfx.measurestr(L.code);gfx.x=b.language+(26-lw)/2;gfx.y=5;gfx.drawstr(L.code)
 local c1,c2,c3=Theme.icon_colors();local ca=hot=='theme' and 1 or .88;local tx,ty=b.theme+17,13;gfx.set(c1[1],c1[2],c1[3],ca);gfx.circle(tx-3.5,ty+2,4.5,1,1);gfx.set(c2[1],c2[2],c2[3],ca*.92);gfx.circle(tx+3.5,ty+2,4.5,1,1);gfx.set(c3[1],c3[2],c3[3],ca*.94);gfx.circle(tx,ty-3.3,4.5,1,1)
 local rc=hot=='reset' and C.accent2 or C.muted;gfx.set(rc[1],rc[2],rc[3],hot=='reset' and .98 or .82);local rx,ry=b.reset+17,13;gfx.roundrect(rx-6,ry-6,12,12,1,1);gfx.line(rx+3,ry-3,rx-3,ry+3);gfx.line(rx-3,ry+3,rx-3,ry-1);gfx.line(rx-3,ry+3,rx+1,ry+3)
 local closec=hot=='close' and C.red or C.muted;gfx.set(closec[1],closec[2],closec[3],hot=='close' and .98 or .82);local cx,cy=b.close+19,13;gfx.line(cx-4.6,cy-4.6,cx+4.6,cy+4.6);gfx.line(cx+4.6,cy-4.6,cx-4.6,cy+4.6)
end

UI.graph={x=212,y=148,w=764,h=350}
UI.pattern_names={'サイン波','ノコギリ波','矩形波','三角波','水平線','ランダムステップ'}
UI.pattern_kinds={'sine','saw','square','triangle','horizontal','random_step'}
UI.period_names={'周期：一定','アッチェレランド','リタルダンド'}
UI.analysis_names={'平均（パワー）','中央値（0.5dB）','最大値'}
function UI.next_analysis_method() if A.job then return end;A.analysis_method=A.analysis_method%3+1;App.persist();A.dirty=true end
UI.envelope_names={'振幅：一定','クレッシェンド','デクレッシェンド'}
UI.interpolation_options={{'linear','直線'},{'smooth','滑らか'}}
UI.tool_options={{'select','範囲選択'},{'free','ペン'}}
UI.direction_names={'左','両側','右'}
UI.max_frequencies={24000,48000,96000}
UI.line_child_ticks={335,367,399,431,463,495}
UI.field_x={212,470,728}
UI.field_y={618,660,702}
UI.icon_points={{0,45},{7,41},{12,27},{18,39},{24,15},{31,35},{38,23},{45,43},{52,19},{60,32},{67,10},{74,37},{82,21},{89,42},{96,28}}
UI.log_ticks={0,10,20,50,100,200,500,1000,2000,5000,10000,20000,40000,48000,60000,80000}
UI.tick_cache={}
UI.noop=function()end
UI.actions={undo=function()App.curve_undo(false)end,redo=function()App.curve_undo(true)end,scale_prev=function()UI.set_scale(-1)end,scale_next=function()UI.set_scale(1)end}
for _,q in ipairs(UI.interpolation_options) do local kind=q[1];UI.actions['interp_'..kind]=function()UI.set_interpolation(kind)end end
for _,q in ipairs(UI.tool_options) do local tool=q[1];UI.actions['tool_'..tool]=function()UI.set_tool(tool)end end
UI.actions.tool_line=function()UI.set_tool('line')end
for _,frequency in ipairs(UI.max_frequencies) do local value=frequency;UI.actions['max_'..value]=function()UI.set_maxfreq(value)end end
for index=1,#Core.PRESETS do local value=index;UI.actions['intensity_'..value]=function()UI.apply_intensity(value)end end
PrimaryButton.painter={C=C,gradient=UI.gradient,line=UI.line,rect=UI.rect,corners=UI.finish_corners,disc=UI.disc,label=UI.label}
PrimaryButton.painter.motion=function(now)
 local q=A.active and clamp(((A.effect_until or 0)-now)/.70,0,1) or 0;return mx,my,q*q*(3-2*q)
end
function App.poll_selection(now)
 if not Media.ready() then return end
 if A.job or now<A.selection_poll then return end;A.selection_poll=now+.5
 local project=R.EnumProjects(-1,'');local revision=R.GetProjectStateChangeCount(project);local count=R.CountSelectedMediaItems(project);local item=count>0 and R.GetSelectedMediaItem(project,0) or nil;local take=item and R.GetActiveTake(item) or nil
 if project==A.selection_project and revision==A.selection_revision and count==A.selection_count and item==A.selection_item and take==A.selection_take then return end
 A.selection_project,A.selection_revision,A.selection_count,A.selection_item,A.selection_take=project,revision,count,item,take
 local info='音声アイテム未選択';local detail='';local nyquist=nil
 if count>0 then
  if take and not R.TakeIsMIDI(take) then
   local source=R.GetMediaItemTake_Source(take);local sr=R.GetMediaSourceSampleRate(source);local ch=R.GetMediaSourceNumChannels(source);nyquist=sr/2
   info=string.format('%d ITEM%s',count,count==1 and '' or 'S');detail=string.format('%.1f kHz  ·  %s',sr/1000,ch==1 and 'MONO' or ch==2 and 'STEREO' or tostring(ch)..' ch')
  else info=string.format('%d ITEM%s',count,count==1 and '' or 'S');detail='AUDIO ONLY' end
 end
 if info~=A.source_info or detail~=A.source_detail or nyquist~=A.source_nyquist then A.source_info=info;A.source_detail=detail;A.source_nyquist=nyquist;A.dirty=true end
end
function UI.set_scale(delta)
 if A.job then return end;A.settings.scale=((A.settings.scale-1+delta)%#Core.SCALES)+1;A.selection=nil;App.changed('処理設定を変更しました。')
end
function UI.scale_menu()
 if A.job then return end;local entries={};for i,name in ipairs(Core.SCALES) do entries[i]=(A.settings.scale==i and '!' or '')..name end
 gfx.x,gfx.y=gfx.mouse_x,gfx.mouse_y;local chosen=gfx.showmenu(table.concat(entries,'|'));if chosen>=1 and chosen<=#Core.SCALES then A.settings.scale=chosen;A.selection=nil;App.changed('処理設定を変更しました。') end
end
function UI.set_maxfreq(value) if not A.job and A.settings.maxfreq~=value then A.settings.maxfreq=value;A.selection=nil;App.changed('処理設定を変更しました。') end end
function UI.apply_intensity(index)
 if A.job then return end;Core.apply_preset(A.settings,index);App.changed(Core.PRESETS[index].name..'  /  '..L.text('処理設定を変更しました。'))
end
function UI.set_tool(tool)
 if A.job or (tool~='select' and tool~='free' and tool~='line') or A.tool==tool then return end
 UI.commit_edit();A.drag=nil;A.selection=nil;A.hover_node=nil;A.tool=tool;UI.reset_line_preview(false);App.store(SECTION,'draw_tool',tool,true);A.dirty=true
end
function UI.tool_help()
 if A.tool=='select' then return 'ドラッグ：範囲選択  ·  辺／角：変形  ·  枠内：移動  ·  Delete／枠内右クリック：削除' end
 if A.tool=='line' then return '波形上をクリック：カーソル位置からライン生成' end
 return 'ドラッグ：描画／点移動  ·  Shift：直線  ·  Alt：点をつかまず描画  ·  右クリック：点削除'
end
function UI.draw_icon(now)
 local x,y,unit=W-99,6,.78;local points=UI.icon_points
 local dt=clamp(now-(A.icon_last or now),0,.1);A.icon_last=now
 local remain=(A.effect_until or 0)-now;local speed=A.active and clamp(remain/.70,0,1) or 0;speed=speed*speed*(3-2*speed)
 UI.line(x,y+49*unit,x+96*unit,y+49*unit,C.edge2,.24)
 for i=2,#points do local a,b=points[i-1],points[i];local c=C.focus2
  UI.line(x+b[1]*unit,y+b[2]*unit,x+b[1]*unit,y+49*unit,c,.10)
  UI.thick_line(x+a[1]*unit,y+a[2]*unit,x+b[1]*unit,y+b[2]*unit,c,.88,2)
 end
 if speed>0 then A.icon_clock=A.icon_clock+dt*speed end
 while A.icon_clock>.16 and #A.icon_particles<24 do
  A.icon_clock=A.icon_clock-.16;A.icon_serial=A.icon_serial+1;local n=A.icon_serial
  local a,b,c,d=UI.particle_hash(n,21),UI.particle_hash(n,22),UI.particle_hash(n,23),UI.particle_hash(n,24);local segment=clamp(floor(a*(#points-1))+1,1,#points-1);local q=UI.particle_hash(n,25);local pa,pb=points[segment],points[segment+1]
  local p=table.remove(A.icon_pool) or {};p.x=x+(pa[1]+(pb[1]-pa[1])*q)*unit;p.y=y+(pa[2]+(pb[2]-pa[2])*q)*unit
  p.age=0;p.life=2.8+b*1.55;p.r=(.65+a*.75)*unit;p.phase=c*pi*2;p.sway=(2+d*3)*unit;p.vy=(4+b*4)*unit;p.vx=(c-.5)*4*unit;A.icon_particles[#A.icon_particles+1]=p
 end
 for i=#A.icon_particles,1,-1 do local p=A.icon_particles[i];p.age=p.age+dt
  if p.age>p.life then table.remove(A.icon_particles,i);A.icon_pool[#A.icon_pool+1]=p
  else local a=math.sin(pi*p.age/p.life)^1.85;local xx=p.x+p.vx*p.age+math.sin(p.age*.63+p.phase)*p.sway;local yy=p.y-p.vy*p.age
   UI.disc(xx,yy,p.r+8*unit,C.accent,.008*a);UI.disc(xx,yy,p.r+4*unit,C.accent3,.016*a)
   UI.disc(xx,yy,p.r+1.8*unit,C.accent2,.060*a);UI.disc(xx,yy,p.r,C.focus2,.46*a)
  end
 end
end
function UI.frequency_ticks(s)
 local key=s.scale..':'..s.maxfreq;local ticks=UI.tick_cache[key];if ticks then return ticks end
 ticks={}
 if s.scale==1 then for i=0,8 do ticks[#ticks+1]=i*s.maxfreq/8 end
 else for _,f in ipairs(UI.log_ticks) do if f<=s.maxfreq then ticks[#ticks+1]=f end end;if ticks[#ticks]~=s.maxfreq then ticks[#ticks+1]=s.maxfreq end end
 UI.tick_cache[key]=ticks;return ticks
end
function UI.display_curve()
 local c,d=A.settings.curve,A.drag;if not d or d.mode~='transform' or not d.overwritten then return c end
 local points={};for _,p in ipairs(c.points) do if not d.overwritten[p] then points[#points+1]=p end end
 return {points=points,kind=c.kind,smoothness=c.smoothness}
end
function UI.point_position(p)
 local g=UI.graph;local visible=p.x>=-1e-8 and p.x<=A.settings.maxfreq+1e-8
 return g.x+Core.to_axis(clamp(p.x,0,A.settings.maxfreq),A.settings.scale,A.settings.maxfreq)*g.w,g.y-p.y/120*g.h,visible
end
function UI.draw_graph()
 local g,s=UI.graph,A.settings;UI.panel(g.x,g.y,g.w,g.h,C.accent2)
 for d=-120,0,20 do local yy=g.y-d/120*g.h;UI.line(g.x,yy,g.x+g.w,yy,C.edge,d==0 and .55 or .26);UI.label(tostring(d),g.x-40,yy-7,12,C.muted,3,false,32,'right') end
 local last,lastf=-math.huge,nil;for _,f in ipairs(UI.frequency_ticks(s)) do local xx=g.x+Core.to_axis(f,s.scale,s.maxfreq)*g.w
  if f~=lastf and f<=s.maxfreq and (f==s.maxfreq or (xx-last>=44 and xx<g.x+g.w-44)) then UI.line(xx,g.y,xx,g.y+g.h,C.edge,.25);UI.label(f>=1000 and string.format('%gk',f/1000) or tostring(f),xx-20,g.y+g.h+8,11,C.muted,3,false,40,'center');last=xx end;lastf=f
 end
 if A.source_nyquist and A.source_nyquist<s.maxfreq then local nx=g.x+g.w*Core.to_axis(A.source_nyquist,s.scale,s.maxfreq);UI.rect(nx,g.y,g.x+g.w-nx,g.h,C.bg,.70);if g.x+g.w-nx>72 then UI.label('対象外',nx+4,g.y+9,11,C.faint,1,false,g.x+g.w-nx-8) end end
 local threshold=g.y-s.threshold/120*g.h;for xx=g.x,g.x+g.w,12 do UI.line(xx,threshold,min(xx+6,g.x+g.w),threshold,C.muted,.65) end
 local curve=UI.display_curve();local lastx,lasty
 for px=0,g.w,2 do local f=Core.from_axis(px/g.w,s.scale,s.maxfreq);local yy=g.y-Core.target(curve,f)/120*g.h
  if lastx then UI.thick_line(lastx,lasty,g.x+px,yy,C.accent2,.86,3);UI.line(lastx,lasty,g.x+px,yy,C.focus2,.95) end;lastx,lasty=g.x+px,yy
 end
 for _,p in ipairs(curve.points) do local x,y,visible=UI.point_position(p);if visible then UI.disc(x,y,3.5,C.field,1);UI.disc(x,y,2.4,C.accent2,.95) end end
 UI.draw_tool_overlay();UI.point_highlight()
 if UI.inside(g.x,g.y,g.w,g.h) and not A.modal then local frequency,value=UI.pointer_value();UI.line(mx,g.y,mx,g.y+g.h,C.focus2,.18);UI.line(g.x,my,g.x+g.w,my,C.focus2,.10);UI.gradient(g.x+10,g.y+10,190,28,C.field,C.panel,.92,.72,true);UI.rect(g.x+10,g.y+10,190,28,C.edge2,.35,false);UI.label(string.format('%.1f Hz   %+.1f dBFS',frequency,value),g.x+20,g.y+16,12,C.text,3,true,170) end
end
function UI.draw_primary(now)
 local x,y,w,h=638,754,338,56;local busy=A.job~=nil;local hot=UI.inside(x,y,w,h) and A.active;A.primary_hot=hot
 local progress=busy and (A.job.kind=='analysis' and A.job.progress or ((A.job.index-1)+(A.job.progress or 0))/#A.job.plans) or nil
 PrimaryButton.draw(PrimaryButton.painter,x,y,w,h,busy and (A.job.kind=='analysis' and '解析を中止' or '処理を中止') or '選択アイテムを処理',busy and 'CLICK TO CANCEL SAFELY' or 'NEW ITEMS / END + 1 SEC',true,busy,progress,hot,A.pressed=='primary' and (gfx.mouse_cap&1)~=0,now,A.active)
 UI.register('primary',x,y,w,h,busy and App.cancel_processing or App.begin_processing,true)
end
function UI.draw_modal()
 if A.modal~='long' then return end
 UI.rect(0,0,W,H,C.bg,.78);local x,y,w,h=234,256,532,244;UI.gradient(x,y,w,h,C.panel2,C.panel,.72,.98,true);UI.rect(x,y,w,h,C.warn,.62,false);UI.rect(x,y,5,h,C.warn,.68)
 UI.label('長尺処理の確認',x+28,y+25,18,C.warn,1,true,w-56)
 UI.label('選択範囲の合計が25分以上です。',x+28,y+66,15,C.text,1,false,w-56)
 UI.label('処理中は一時WAVと出力WAVを作成し、時間と空き容量を使用します。',x+28,y+96,13,C.muted,1,false,w-56)
 if A.pending_job then UI.label(string.format('TOTAL  %.1f min   /   %d item%s',A.pending_job.total_seconds/60,#A.pending_job.plans,#A.pending_job.plans==1 and '' or 's'),x+28,y+132,13,C.warn,3,true,w-56) end
 UI.button('modal_cancel','キャンセル',x+28,y+178,218,38,App.cancel_pending,true,false,C.muted)
 UI.button('modal_continue','このまま実行',x+286,y+178,218,38,App.confirm_processing,true,false,C.warn)
end
function UI.analysis_controls()
 local busy=A.job and A.job.kind=='analysis';local enabled=not A.job or busy
 local x,y,w,h=24,548,164,40;local hot=enabled and A.active and UI.inside(x,y,w,h)
 local down=A.pressed=='analyze' and (gfx.mouse_cap&1)~=0
 A.button_glow=A.button_glow or {};local glow=A.button_glow.analyze or 0
 glow=glow+((hot and 1 or 0)-glow)*min(1,(UI.button_dt or 0)*14);A.button_glow.analyze=glow
 local yy=y+(down and 1.5 or 0);local tone=enabled and C.accent2 or C.faint
 UI.gradient(x,yy,w,h,C.accent3,C.panel,enabled and .48+.20*glow or .12,.90)
 UI.rect(x+1,yy+1,w-2,h-2,tone,enabled and .05+.08*glow or .01)
 UI.gradient(x,yy,w,1,tone,tone,enabled and .78 or .15,.04)
 UI.line(x,yy,x,yy+h,tone,enabled and .70 or .18)
 UI.line(x,yy+h,x+w-7,yy+h,C.edge,.46)
 UI.finish_corners(x,yy,w,h,7,false,tone,enabled and .55+.30*glow or .16)
 UI.label('WAVE  >  CURVE',x+10,yy+5,8,tone,3,true,w-25)
 UI.line(x+w-17,yy+7,x+w-17,yy+13,tone,.75);UI.line(x+w-20,yy+10,x+w-14,yy+10,tone,.75)
 UI.label(busy and '解析を中止' or '波形を解析し変換',x+4,yy+19,12,enabled and C.text or C.faint,1,true,w-8,'center')
 UI.register('analyze',x,y,w,h,busy and App.cancel_processing or App.begin_analysis,enabled)
 local ox,oy,ow,oh=44,596,144,22;local option_enabled=not A.job
 local option_hot=option_enabled and A.active and UI.inside(ox,oy,ow,oh)
 UI.line(32,y+h+2,32,oy+oh/2,C.muted,.28);UI.line(32,oy+oh/2,ox-3,oy+oh/2,C.muted,.28)
 UI.gradient(ox,oy,ow,oh,C.field,C.panel,.68,.48)
 UI.line(ox,oy,ox,oy+oh,C.muted,option_hot and .6 or .22)
 UI.finish_corners(ox,oy,ow,oh,4,false,C.edge2,option_hot and .48 or .15)
 UI.label('集計',ox+5,oy+6,9,C.faint,1,false,28)
 UI.label(UI.analysis_names[A.analysis_method],ox+32,oy+5,11,option_enabled and C.muted or C.faint,1,false,ow-44)
 UI.line(ox+ow-10,oy+9,ox+ow-7,oy+12,C.muted,.5);UI.line(ox+ow-7,oy+12,ox+ow-4,oy+9,C.muted,.5)
 UI.register('analysis_method',ox,oy,ow,oh,UI.next_analysis_method,option_enabled)
end
function UI.draw(now)
 UI.button_dt=min(.1,max(0,now-(UI.button_time or now)));UI.button_time=now
 UI.geometry();for i=#widgets,1,-1 do widgets[i]=nil end;UI.rect(0,0,W,H,C.bg);UI.gradient(0,0,W,72,C.bg2,C.bg,.23,0,true)
 UI.label('SPECTRAL NORMALIZER',24,8,35,C.text,2,true,760)
 UI.label('SPECTRAL TARGET DRAWING  周波数ごとの目標音量を描画',26,44,10,C.accent2,1,true,820)
 UI.line(24,62,W-24,62,C.edge2,.28);UI.draw_icon(now)
 UI.label('補完処理',24,91,13,C.muted,1,true,164)
 local smoothing=Core.smoothness(A.settings.curve)
 for i,q in ipairs(UI.interpolation_options) do local kind=q[1];UI.button('interp_'..kind,q[2],24+(i-1)*84,117,80,30,UI.actions['interp_'..kind],not A.job,smoothing==(kind=='linear' and 0 or 1),C.accent2) end
 UI.smoothness_slider()
 UI.label('操作モード',24,181,13,C.muted,1,true,164)
 for i,q in ipairs(UI.tool_options) do local tool=q[1];UI.button('tool_'..tool,q[2],24,207+(i-1)*38,164,32,UI.actions['tool_'..tool],not A.job,A.tool==tool,C.accent2) end
 local selected=A.tool=='line';UI.gradient(24,283,164,252,C.panel2,C.panel,.55,.95);UI.rect(24,283,164,252,C.accent2,selected and .065 or .022);UI.line(24,283,24,535,C.accent2,selected and .70 or .32);UI.line(188,283,188,535,C.accent2,selected and .55 or .25);UI.line(24,535,188,535,C.accent2,selected and .55 or .25)
 UI.button('tool_line','ライン生成',24,283,164,32,UI.actions.tool_line,not A.job,selected,C.accent2);local child=selected and C.accent2 or C.muted;UI.line(32,315,32,495,child,.30);for _,yy in ipairs(UI.line_child_ticks) do UI.line(32,yy,39,yy,child,.30) end
 UI.button('pattern',UI.pattern_names[A.pattern],40,321,140,28,UI.next_pattern,not A.job,false,child)
 UI.button('direction','方向：'..UI.direction_names[A.direction],40,353,140,28,UI.next_direction,not A.job,false,child)
 UI.field('period_percent',40,385,140,28,not A.job,not selected);UI.button('period_shape',UI.period_names[A.period_shape],40,417,140,28,UI.next_period,not A.job,false,child);UI.field('height',40,449,140,28,not A.job,not selected)
 UI.button('shape_envelope',UI.envelope_names[A.shape_envelope],40,481,140,28,UI.next_shape,not A.job,false,child);UI.label('Alt：位相反転',40,512,11,C.muted,1,false,140)
 UI.analysis_controls()
 UI.label('カーブ操作',24,624,13,C.muted,1,true,164)
 UI.button('curve_undo','戻す',24,648,80,30,UI.actions.undo,not A.job and #A.history>0,false,C.accent2);UI.button('curve_redo','進む',108,648,80,30,UI.actions.redo,not A.job and #A.redo>0,false,C.accent2)
 UI.button('curve_reset','カーブを初期化',24,686,164,32,App.reset_curve,not A.job,false,C.warn)
 UI.panel(24,734,164,50,C.accent2);UI.label('選択素材',34,740,9,C.faint,3,true,144);UI.label(A.source_info,34,755,11,C.text,1,true,144);UI.label(A.source_detail,34,771,9,C.muted,3,true,144)
 UI.label('TARGET  /  dBFS · FFT BIN',212,91,11,C.text,3,true,286);UI.label(A.source_info..(A.source_detail~='' and '  ·  '..A.source_detail or ''),212,112,10,C.muted,1,false,282)
 UI.label('表示尺度',510,91,9,C.faint,1,true,176);UI.button('scale_prev','<',510,108,28,28,UI.actions.scale_prev,not A.job,false,C.accent2);UI.button('scale_menu',Core.SCALES[A.settings.scale],542,108,112,28,UI.scale_menu,not A.job,false,C.accent2);UI.button('scale_next','>',658,108,28,28,UI.actions.scale_next,not A.job,false,C.accent2)
 UI.label('処理上限',700,91,9,C.faint,1,true,276);local fw=(276-8)/3;for i,freq in ipairs(UI.max_frequencies) do UI.button('max_'..freq,(freq//1000)..' kHz',700+(i-1)*(fw+4),108,fw,28,UI.actions['max_'..freq],not A.job,A.settings.maxfreq==freq,C.accent2) end
 UI.draw_graph();UI.label('処理強度プリセット',212,531,12,C.muted,1,true,764)
 local preset=Core.preset_index(A.settings);local pw=(764-12)/4
 for i,p in ipairs(Core.PRESETS) do UI.button('intensity_'..i,p.name,212+(i-1)*(pw+4),548,pw,32,UI.actions['intensity_'..i],not A.job,preset==i,C.accent2) end
 if preset==0 then UI.label('カスタム',910,531,10,C.accent2,3,true,66,'right') end
 UI.label('処理パラメーター',212,594,12,C.muted,1,true,764);local n=1
 for row=1,3 do for col=1,3 do UI.field(fields[n].key,UI.field_x[col],UI.field_y[row],248,34,not A.job);n=n+1 end end
 UI.label('破線＝増幅閾値。目標はFFTビンの正弦波ピーク換算値。DC・Nyquistは保持。',212,743,11,C.faint,1,false,410)
 UI.draw_primary(now)
 UI.label(UI.tool_help(),212,766,10,C.muted,1,false,410)
 UI.label('1 / 2 / 3：範囲選択 / ペン / ライン生成  ·  数値欄ドラッグ／ホイール：変更  ·  Ctrl+Z / Ctrl+Y：履歴',212,786,9,C.faint,1,false,410)
 local status=A.status;if A.job then local progress=A.job.kind=='analysis' and A.job.progress or ((A.job.index-1)+(A.job.progress or 0))/#A.job.plans;status=string.format(L.text('処理中 %d / %d   %.1f%%  — 対象素材の編集は避けてください。'),min(A.job.index,#A.job.plans),#A.job.plans,progress*100)
 elseif R.time_precise()>A.status_until then status='音声アイテムを選択し、目標カーブを描いてください。' end
 if Media.waiting then status=Media.message(SECTION) end
 UI.line(24,H-22,W-24,H-22,C.edge,.34);UI.label(status,24,H-17,10,A.warning and C.warn or C.muted,1,false,850)
 UI.label('v'..Core.VERSION,W-100,H-17,9,C.faint,3,true,76,'right');UI.draw_modal();Chrome.draw();Presets.draw();gfx.update()
end
function UI.pointer_value(dx,dy)
 local g=UI.graph;local px,py=mx-(dx or 0),my-(dy or 0);local f=Core.from_axis(clamp((px-g.x)/g.w,0,1),A.settings.scale,A.settings.maxfreq);local value=clamp(-(py-g.y)/g.h*120,-120,0)
 return f,value
end
function UI.screen_to_point(x,y) local g=UI.graph;return {x=Core.from_axis(clamp((x-g.x)/g.w,0,1),A.settings.scale,A.settings.maxfreq),y=clamp(-(y-g.y)/g.h*120,-120,0)} end
function UI.nearest()
 local best,dist=nil,14*14;for i,p in ipairs(A.settings.curve.points) do local x,y,visible=UI.point_position(p);local dd=((mx-x)*scale)^2+((my-y)*scale)^2;if visible and dd<=dist then best,dist=i,dd end end;return best
end
function UI.hover_point(index)
 if index~=A.hover_node then A.hover_node=index;A.point_flash=R.time_precise();A.dirty=true end
end
function UI.point_highlight()
 local p=A.hover_node and A.settings.curve.points[A.hover_node];if not p or not A.active or A.job then return end;local x,y,visible=UI.point_position(p);if not visible then return end
 local flash=max(0,1-(R.time_precise()-(A.point_flash or 0))/.22);UI.disc(x,y,6/scale,C.field,.95);UI.disc(x,y,4.3/scale,C.accent2,1);if flash>0 then UI.disc(x,y,(4.3+2*flash)/scale,C.focus2,flash*.85) end
end
function UI.set_smoothness(amount,drag)
 if A.job then return end;local c=A.settings.curve;amount=clamp(amount,0,2);if abs(Core.smoothness(c)-amount)<1e-10 then return end
 if not drag or not drag.changed then App.push_history();if drag then drag.changed=true end end;c.smoothness=amount;c.kind=amount==0 and 'linear' or 'smooth';A.preset_dirty=true;A.dirty=true;if not drag then App.persist() end
end
function UI.set_interpolation(kind) UI.set_smoothness(kind=='linear' and 0 or 1) end
UI.slider_track={.08,.08,.085}
function UI.smoothness_slider()
 local x,y,w,h=24,155,164,16;local amount=Core.smoothness(A.settings.curve);local left,right=x+6,x+w-6;local cy=y+h/2;local knob=left+(right-left)*amount/2
 UI.rect(left,cy-2,right-left,4,UI.slider_track,1);UI.rect(left,cy-2,knob-left,4,C.accent2,A.job and .25 or .70);UI.disc(knob,cy,6,C.field,1);UI.disc(knob,cy,4,C.accent2,A.job and .35 or .95);UI.register('smoothness',x,y,w,h,UI.noop,not A.job)
end
function UI.smoothness_input(hit,down,pressed,released)
 local drag=A.drag and A.drag.mode=='smoothness' and A.drag;if not drag and hit and hit.id=='smoothness' and pressed and not A.job then drag={mode='smoothness'};A.drag=drag;A.pointer_capture=true end
 if not drag then return false end;if down or released then UI.set_smoothness((mx-30)/76,drag) end
 if released then A.drag=nil;A.pointer_capture=nil;if drag.changed then App.persist() end;A.dirty=true end;return true
end
function UI.reset_line_preview(reset_random) UI.preview_key=nil;UI.preview_points=nil;UI.preview_ua=nil;UI.preview_ub=nil;if reset_random then UI.random_step_state=nil end end
function UI.random_step_levels(slot)
 local state=UI.random_step_state;if not state then state={};UI.random_step_state=state end;local levels=state[slot];if not levels then levels={};state[slot]=levels end;local count=max(1,ceil(100/A.period_percent-1e-12));for i=#levels+1,count do levels[i]=math.random()*2-1 end;return levels
end
function UI.next_pattern() if A.job then return end;A.pattern=A.pattern%#UI.pattern_names+1;UI.reset_line_preview(true);App.persist();A.dirty=true end
function UI.next_direction() if A.job then return end;A.direction=A.direction%3+1;UI.reset_line_preview(false);App.persist();A.dirty=true end
function UI.next_period() if A.job then return end;A.period_shape=A.period_shape%3+1;UI.reset_line_preview(false);App.persist();A.dirty=true end
function UI.next_shape() if A.job then return end;A.shape_envelope=A.shape_envelope%3+1;UI.reset_line_preview(false);App.persist();A.dirty=true end
function UI.line_anchor()
 local g=UI.graph;local x,y=mx,my;for _,px in ipairs({g.x,g.x+g.w}) do if abs(x-px)*scale<=9 then x=px end end;for _,py in ipairs({g.y,g.y+g.h/2,g.y+g.h}) do if abs(y-py)*scale<=9 then y=py end end;return clamp(x,g.x,g.x+g.w),clamp(y,g.y,g.y+g.h)
end
function UI.clean_points(points)
 table.sort(points,function(a,b)return a.x<b.x end);for i=#points,2,-1 do if points[i].x-points[i-1].x<1e-6 then table.remove(points,i-1) end end;if #points>Core.MAX_POINTS then points=Core.limit_points(points,Core.MAX_POINTS) end;return points
end
function UI.line_points()
 local g=UI.graph;local x,y=UI.line_anchor();local invert=(gfx.mouse_cap&16)~=0 and -1 or 1;local key=x..':'..y..':'..A.pattern..':'..A.period_percent..':'..A.period_shape..':'..A.height..':'..A.shape_envelope..':'..A.direction..':'..A.settings.scale..':'..A.settings.maxfreq..':'..invert
 if UI.preview_key==key then return UI.preview_points,UI.preview_ua,UI.preview_ub end
 local full_left,full_right=g.x,g.x+g.w;local left=A.direction==3 and x or full_left;local right=A.direction==1 and x or full_right;if right-left<1e-7 then return {},0,0 end
 local out={};local joined=A.direction==2 and x>full_left+1e-7 and x<full_right-1e-7;local omit_origin=joined and (A.pattern==2 or A.pattern==4 or (A.pattern==3 and A.shape_envelope==2));local origin_jump=joined and ((A.pattern==3 and not omit_origin) or A.pattern==6);local single_jump=(A.pattern==3 or A.pattern==6) and A.direction~=2
 if single_jump then out[#out+1]=UI.screen_to_point(x,y) end
 local function side(edge,sign,skip_origin,slot)
  if abs(edge-x)<1e-7 then return end;local levels=A.pattern==6 and UI.random_step_levels(slot) or nil;local cycles=100/A.period_percent*abs(edge-x)/g.w;local points=Core.pattern(UI.pattern_kinds[A.pattern],cycles,A.height/100,A.shape_envelope,levels,A.period_shape)
  for _,p in ipairs(points) do if not (skip_origin and p.x==0) and not (single_jump and p.x==0 and abs(p.y)<1e-10) then local u=p.x;if u==0 and ((origin_jump and edge<x) or single_jump) then u=min(1e-5,.01/cycles) end;out[#out+1]=UI.screen_to_point(x+(edge-x)*u,y-p.y*sign*invert*g.h/2) end end
 end
 if A.direction~=3 then side(left,A.direction==2 and -1 or 1,omit_origin or (joined and not origin_jump),'left') end;if A.direction~=1 then side(right,1,omit_origin,'right') end
 local ua,ub=UI.screen_to_point(left,y).x,UI.screen_to_point(right,y).x;local generated={points=UI.clean_points(out)};Core.simplify(generated,1e-8);UI.preview_key=key;UI.preview_points=generated.points;UI.preview_ua=ua;UI.preview_ub=ub;return UI.preview_points,ua,ub
end
function UI.stamp_line()
 local points,ua,ub=UI.line_points();if #points==0 then return end;App.push_history();local c=A.settings.curve;local out={};for _,p in ipairs(c.points) do if p.x<ua-1e-6 or p.x>ub+1e-6 then out[#out+1]=p end end;for _,p in ipairs(points) do out[#out+1]={x=p.x,y=p.y} end;c.points=UI.clean_points(out);if #c.points<2 then c.points={{x=0,y=-42},{x=96000,y=-42}} end;A.selection=nil;A.hover_node=nil;UI.reset_line_preview(A.pattern==6);App.changed()
end
function UI.line_preview()
 if A.tool~='line' or A.job or not A.active or not UI.inside(UI.graph.x,UI.graph.y,UI.graph.w,UI.graph.h) then return end;local points,ua,ub=UI.line_points();if #points==0 then return end;local curve={points=points,kind=A.settings.curve.kind,smoothness=A.settings.curve.smoothness};local g=UI.graph
 local previous_x,previous_y
 for px=0,g.w,2 do local f=Core.from_axis(px/g.w,A.settings.scale,A.settings.maxfreq);if f>=ua and f<=ub then local x,y=g.x+px,g.y-Core.target(curve,f)/120*g.h;if previous_x then UI.line(previous_x,previous_y,x,y,C.accent2,.42) end;previous_x,previous_y=x,y else previous_x=nil end end
end
function UI.selection_bounds()
 if not A.selection then return end
 local b={x=math.huge,y=math.huge,r=-math.huge,b=-math.huge};local count=0
 for _,p in ipairs(A.settings.curve.points) do if A.selection[p] then local x,y,visible=UI.point_position(p);if visible then b.x=min(b.x,x);b.r=max(b.r,x);b.y=min(b.y,y);b.b=max(b.b,y);count=count+1 end end end
 if count==0 then A.selection=nil;return end
 if b.r-b.x<8/scale then b.x=b.x-4/scale;b.r=b.r+4/scale end
 if b.b-b.y<8/scale then b.y=b.y-4/scale;b.b=b.b+4/scale end
 return b
end
function UI.selection_hit()
 local b=UI.selection_bounds();if not b then return end
 local pad=9/scale;local hx,hy
 if abs(mx-b.x)<=pad then hx='l' elseif abs(mx-b.r)<=pad then hx='r' end
 if abs(my-b.y)<=pad then hy='t' elseif abs(my-b.b)<=pad then hy='b' end
 if mx>=b.x-pad and mx<=b.r+pad and my>=b.y-pad and my<=b.b+pad then return (hx or '')..(hy or ''),b end
end
function UI.delete_selected()
 if A.tool~='select' or A.job or A.drag or not A.selection then return false end;local c=A.settings.curve;local out={};local count=0;for _,p in ipairs(c.points) do if A.selection[p] then count=count+1 else out[#out+1]=p end end;if count==0 then return false end
 App.push_history();if #out<2 then local y=out[1] and out[1].y or -42;if not out[1] then out={{x=0,y=y},{x=96000,y=y}} elseif out[1].x<48000 then out[#out+1]={x=96000,y=y} else table.insert(out,1,{x=0,y=y}) end end;c.points=UI.clean_points(out);A.selection=nil;A.hover_node=nil;App.changed();return true
end
function UI.selection_input(down,pressed,released,in_graph)
 if pressed and (in_graph or UI.selection_hit()) then local handle,b=UI.selection_hit();A.pointer_capture=true;if handle~=nil then App.push_history();local originals={};for _,p in ipairs(A.settings.curve.points) do if A.selection[p] then local x,y=UI.point_position(p);originals[#originals+1]={p=p,x=x,y=y,f=p.x} end end;A.drag={mode='transform',handle=handle,box=b,mx=mx,my=my,originals=originals} else local g=UI.graph;local x,y=clamp(mx,g.x,g.x+g.w),clamp(my,g.y,g.y+g.h);A.selection=nil;A.drag={mode='marquee',x=x,y=y,r=x,b=y} end end
 local d=A.drag;if down and d then
  if d.mode=='marquee' then local g=UI.graph;d.r=clamp(mx,g.x,g.x+g.w);d.b=clamp(my,g.y,g.y+g.h)
  elseif d.mode=='transform' then local b=d.box;local dx,dy=mx-d.mx,my-d.my;local l,r,t,bot=b.x,b.r,b.y,b.b;if d.handle=='' then l=l+dx;r=r+dx;t=t+dy;bot=bot+dy else if d.handle:find('l',1,true) then l=l+dx elseif d.handle:find('r',1,true) then r=r+dx end;if d.handle:find('t',1,true) then t=t+dy elseif d.handle:find('b',1,true) then bot=bot+dy end end;local bw,bh=max(b.r-b.x,1e-8),max(b.b-b.y,1e-8);for _,o in ipairs(d.originals) do local q=UI.screen_to_point(l+(o.x-b.x)/bw*(r-l),t+(o.y-b.y)/bh*(bot-t));o.p.x,o.p.y=q.x,q.y end;d.overwritten={};if d.handle=='' or d.handle:find('[lr]') then for _,p in ipairs(A.settings.curve.points) do if not A.selection[p] then for _,o in ipairs(d.originals) do if abs(o.f-o.p.x)>1e-6 and p.x>=min(o.f,o.p.x)-1e-6 and p.x<=max(o.f,o.p.x)+1e-6 then d.overwritten[p]=true;break end end end end end;table.sort(A.settings.curve.points,function(a,b)return a.x<b.x end);A.preset_dirty=true
  end;A.dirty=true
 end
 if released and d then
  if d.mode=='marquee' then A.selection={};for _,p in ipairs(A.settings.curve.points) do local x,y,visible=UI.point_position(p);if visible and x>=min(d.x,d.r) and x<=max(d.x,d.r) and y>=min(d.y,d.b) and y<=max(d.y,d.b) then A.selection[p]=true end end;if not next(A.selection) then A.selection=nil end
  elseif d.mode=='transform' then local g=UI.graph;local out={};for _,p in ipairs(A.settings.curve.points) do local x,y=UI.point_position(p);if not (d.overwritten and d.overwritten[p]) and (not A.selection[p] or (p.x>=0 and p.x<=96000 and x>=g.x-1e-7 and x<=g.x+g.w+1e-7 and y>=g.y-1e-7 and y<=g.y+g.h+1e-7)) then out[#out+1]=p end end;if #out<2 then local value=out[1] and out[1].y or -42;out={{x=0,y=value},{x=96000,y=value}};A.selection=nil end;A.settings.curve.points=UI.clean_points(out);App.persist()
  end;A.drag=nil;A.pointer_capture=nil;A.dirty=true
 end
 return d~=nil
end
function UI.draw_tool_overlay()
 UI.line_preview();local g=UI.graph;local d=A.drag
 local b
 if d and d.mode=='marquee' then b={x=min(d.x,d.r),r=max(d.x,d.r),y=min(d.y,d.b),b=max(d.y,d.b)}
 elseif A.tool=='select' then b=UI.selection_bounds() end
 if b then
  UI.rect(b.x,b.y,b.r-b.x,b.b-b.y,C.accent2,.055);UI.line(b.x,b.y,b.r,b.y,C.accent2,.90);UI.line(b.x,b.b,b.r,b.b,C.accent2,.90)
  UI.line(b.x,b.y,b.x,b.b,C.accent2,.90);UI.line(b.r,b.y,b.r,b.b,C.accent2,.90)
  if not d or d.mode~='marquee' then for _,x in ipairs({b.x,(b.x+b.r)/2,b.r}) do for _,y in ipairs({b.y,(b.y+b.b)/2,b.b}) do
   if x~=(b.x+b.r)/2 or y~=(b.y+b.b)/2 then UI.rect(x-3/scale,y-3/scale,6/scale,6/scale,C.accent2,.92) end
  end end end
 end
 if A.tool=='line' and not A.job and UI.inside(g.x,g.y,g.w,g.h) and not A.modal then local x,y=UI.line_anchor();for i=1,16 do UI.line(x+(i-1)-8,y+math.sin((i-1)*.55)*4,x+i-8,y+math.sin(i*.55)*4,C.focus2,.95) end;UI.line(x-4,y-9,x+4,y-9,C.focus2,.8) end
end
function UI.graph_input(down,pressed,released,right_pressed)
 local g=UI.graph;local in_graph=UI.inside(g.x,g.y,g.w,g.h);if A.job then return false end;local nearest=A.tool=='free' and (gfx.mouse_cap&24)==0 and UI.nearest() or nil;UI.hover_point(nearest);local graph_hit=in_graph or nearest~=nil
 if A.tool=='select' then
  if right_pressed and not A.drag then local b=UI.selection_bounds();if b and UI.inside(b.x,b.y,b.r-b.x,b.b-b.y) then UI.delete_selected() end;return true end
  return UI.selection_input(down,pressed,released,in_graph) or in_graph
 end
 if A.tool=='line' then if pressed and in_graph then UI.commit_edit();UI.stamp_line();return true end;return in_graph end
 if right_pressed and graph_hit then local i=UI.nearest();if i then App.push_history();local c=A.settings.curve;if i==1 or i==#c.points then c.points[i].y=-42 else table.remove(c.points,i) end;A.hover_node=nil;App.changed() end;return true end
 if pressed and graph_hit then UI.commit_edit();App.push_history();local x,y=UI.pointer_value();local c=A.settings.curve;A.selection=nil
  if (gfx.mouse_cap&8)~=0 then A.drag={mode='straight',x=x,y=y,original=Core.copy(c.points)};c.kind='linear';c.smoothness=0;Core.stroke(c,x,y,x,y)
  elseif nearest then local px,py=UI.point_position(c.points[nearest]);local f=c.points[nearest].x;A.drag={mode='node',index=nearest,anchor=(f==0 or f==96000) and f or nil,dx=mx-px,dy=my-py,start_x=mx,start_y=my}
  else Core.stroke(c,x,y,x,y);A.drag={mode='free',x=x,y=y} end;A.pointer_capture=true;A.preset_dirty=true;A.dirty=true;return true
 end
 local d=A.drag;if d and (d.mode=='straight' or d.mode=='free' or d.mode=='node') then
  if down then local x,y=UI.pointer_value(d.dx,d.dy);local c=A.settings.curve
   if d.mode=='straight' then c.points=Core.copy(d.original);Core.stroke(c,d.x,d.y,x,y)
   elseif d.mode=='free' then if abs(x-d.x)>A.settings.maxfreq/g.w*.5 or abs(y-d.y)>.12 then Core.stroke(c,d.x,d.y,x,y);d.x,d.y=x,y;if #c.points>Core.MAX_POINTS then local tolerance=.08;repeat Core.simplify(c,tolerance);tolerance=tolerance*2 until #c.points<=Core.MAX_POINTS end end
   else local i=d.index;local p=c.points[i];if d.anchor~=nil then x=d.anchor else x=clamp(x,i>1 and c.points[i-1].x+1e-5 or 0,i<#c.points and c.points[i+1].x-1e-5 or 96000) end;if ((mx-d.start_x)*scale)^2+((my-d.start_y)*scale)^2>4 then d.moved=true end;if d.moved then p.x,p.y=x,y end
   end;A.preset_dirty=true;A.dirty=true
  elseif released then if d.mode=='straight' then local x,y=UI.pointer_value();A.settings.curve.points=Core.copy(d.original);Core.stroke(A.settings.curve,d.x,d.y,x,y) elseif d.mode=='free' then Core.simplify(A.settings.curve,.08) end;A.drag=nil;A.pointer_capture=nil;App.persist();A.dirty=true end;return true
 end
 return graph_hit
end
function UI.number_input(hit,down,pressed,released,wheel)
 local key=hit and hit.enabled and hit.id:match('^field_(.+)$')
 if key and wheel~=0 and not A.job then
  UI.commit_edit();local ticks=max(1,math.floor(abs(wheel)/120+.5));UI.step_value(key,(wheel>0 and 1 or -1)*ticks,true);gfx.mouse_wheel=0;return true
 end
 if pressed and key and not A.job then
  UI.commit_edit();A.number_drag={key=key,y=my,value=UI.value(key),moved=false};return true
 end
 local drag=A.number_drag;if not drag then return false end
 if down then
  local dy=(drag.y-my)*scale
  if abs(dy)>=3 or drag.moved then
   drag.moved=true;local ticks=(dy<0 and -1 or 1)*math.floor(abs(dy)/3+.5);local spec=field_by_key[drag.key];local raw
   if spec.values then local index=1;for i,v in ipairs(spec.values) do if v==drag.value then index=i;break end end;raw=spec.values[clamp(index+ticks,1,#spec.values)]
   else raw=drag.value+ticks*spec.step end
   local clipped=not spec.values and (raw<spec.min or raw>spec.max);UI.set_value(drag.key,raw,not drag.clipped,false);drag.clipped=clipped
  end
 elseif released then
  if not drag.moved and key==drag.key then A.edit={key=drag.key,text=UI.value_text(drag.key,UI.value(drag.key)),selected=true}
  else App.persist() end
  A.number_drag=nil;A.dirty=true
 end
 return true
end
function UI.modal_input(hit,down,pressed,released)
 if not A.modal then return false end
 if pressed then UI.commit_edit();A.pressed=hit and hit.id:match('^modal_') and hit.id or nil end
 if released then local id=A.pressed;A.pressed=nil;if id and hit and hit.id==id and hit.enabled then App.safe(hit.fn) end end
 return true
end
function UI.release_capture()
 A.drag=nil;A.number_drag=nil;A.pointer_capture=nil;A.pressed=nil
 Chrome.drag=nil;Chrome.resize=nil;Chrome.press=nil;A.dirty=true
end
function UI.input()
 UI.geometry()
 local popup_blocked=Presets.open or Presets.swallow
 local before_selected,before_offset,before_page=Presets.selected,Presets.offset,Presets.page
 Presets.update(A.active)
 if before_selected~=Presets.selected or before_offset~=Presets.offset or before_page~=Presets.page then A.dirty=true end
 if popup_blocked then
  A.last_mouse_cap=gfx.mouse_cap or 0;A.last_right=((gfx.mouse_cap or 0)&2)~=0;A.pressed=nil;gfx.mouse_wheel=0;return
 end
 local cap=gfx.mouse_cap or 0;local down=(cap&1)~=0;local pressed=down and (A.last_mouse_cap&1)==0;local released=not down and (A.last_mouse_cap&1)~=0
 local right=(cap&2)~=0;local right_pressed=right and not A.last_right
 local moved=gfx.mouse_x~=A.last_mouse_x or gfx.mouse_y~=A.last_mouse_y;local wheel=gfx.mouse_wheel or 0
 if moved or pressed or released or right_pressed or wheel~=0 then A.dirty=true;A.effect_until=R.time_precise()+2.5 end
 if not down and (A.drag or A.number_drag) then
  if A.number_drag then UI.number_input(UI.hit(),false,false,true,0)
  elseif A.drag.mode=='smoothness' then UI.smoothness_input(nil,false,false,true)
  else UI.graph_input(false,false,true,false) end
  A.drag=nil;A.number_drag=nil;A.pointer_capture=nil;A.dirty=true
 end
 if pressed and (gfx.mouse_y<TITLE_H or Chrome.resize_hit(gfx.mouse_x,gfx.mouse_y)) then UI.commit_edit();UI.release_capture() end
 local chrome=Chrome.input(down,pressed,released)
 if not chrome and not Chrome.drag and not Chrome.resize then
  local hit=UI.hit()
  if A.modal then UI.modal_input(hit,down,pressed,released)
  elseif not UI.smoothness_input(hit,down,pressed,released) and not UI.number_input(hit,down,pressed,released,wheel) and not UI.graph_input(down,pressed,released,right_pressed) then
   if pressed then
    if A.edit then UI.commit_edit();hit=UI.hit() end
    A.pressed=hit and hit.enabled and hit.id or nil
   elseif released then
    local id=A.pressed;A.pressed=nil
    if id and hit and hit.id==id and hit.enabled then App.safe(hit.fn) end
   end
  end
 end
 if gfx.setcursor then
  if not chrome then local hit=UI.hit();local graph_hot=not A.job and UI.inside(UI.graph.x,UI.graph.y,UI.graph.w,UI.graph.h);local cursor=graph_hot and (A.tool=='line' and 32515 or 32512) or hit and hit.enabled and hit.id:match('^field_') and 32645 or 32512
   gfx.setcursor(cursor)
  elseif not Chrome.resize and not Chrome.resize_hit(gfx.mouse_x,gfx.mouse_y) then gfx.setcursor(32512) end
 end
 A.last_mouse_cap=cap;A.last_right=right;A.last_mouse_x=gfx.mouse_x;A.last_mouse_y=gfx.mouse_y
end
function UI.key(k)
 if Presets.open then Presets.key(k);return end
 if A.edit then
  local edit=A.edit
  if k==13 or k==9 then UI.commit_edit()
  elseif k==27 then A.edit=nil;A.dirty=true
  elseif k==1 then edit.selected=true;A.dirty=true
  elseif k==8 or k==6579564 then edit.text=edit.selected and '' or edit.text:sub(1,-2);edit.selected=false;A.dirty=true
  elseif (k>=48 and k<=57) or k==45 or k==46 then if edit.selected then edit.text='';edit.selected=false end;if #edit.text<16 then edit.text=edit.text..string.char(k);A.dirty=true end end
  return
 end
 if A.modal then if k==27 then App.cancel_pending() elseif k==13 then App.confirm_processing() end;return end
 local ctrl=(gfx.mouse_cap&4)~=0;local shift=(gfx.mouse_cap&8)~=0
 local undo_key=k==26 or (ctrl and (k==90 or k==122));local redo_key=k==25 or (ctrl and (k==89 or k==121)) or (shift and undo_key)
 if not A.job and redo_key then App.curve_undo(true)
 elseif not A.job and undo_key then App.curve_undo(false)
 elseif not A.job and (k==6579564 or k==127) then UI.delete_selected()
 elseif not A.job and k>=49 and k<=51 then UI.set_tool(({'select','free','line'})[k-48])
 elseif k==27 then
  if A.drag then
   if A.drag.mode~='marquee' and #A.history>0 then A.settings.curve=table.remove(A.history) end
   A.drag=nil;A.pointer_capture=nil;A.selection=nil;A.hover_node=nil;App.persist();A.dirty=true
  elseif A.selection then A.selection=nil;A.dirty=true else A.closing=true end
 end
end
function App.close()
 if A.closed then return end;A.closed=true
 if A.edit then pcall(UI.commit_edit) end
 pcall(App.cleanup,A.job);A.job=nil;A.pending_job=nil;pcall(App.persist)
 pcall(function()
  local hwnd=Chrome.handle();if hwnd then local ok,l,t,r,b=WindowGeometry.JS_Window_GetRect(hwnd);if ok then
   App.store(SECTION,'window_x',tostring(math.floor(l+.5)),true);App.store(SECTION,'window_y',tostring(math.floor(t+.5)),true)
   App.store(SECTION,'window_w',tostring(math.floor(r-l+.5)),true);App.store(SECTION,'window_h',tostring(math.floor(b-t+.5)),true)
  end end
 end)
 pcall(Chrome.cursor,nil);pcall(gfx.quit)
end
function App.loop()
 Media.tick()
 if A.closing then App.close();return end
 local key=gfx.getchar();if key<0 then A.closing=true;App.close();return end
 local now=R.time_precise();local flags=gfx.getchar(65537);local active=(flags&1)==0 or (flags&2)~=0
 if active~=A.active then A.active=active;if not active then if A.edit then UI.commit_edit() end;UI.release_capture() end;A.dirty=true end
 local count=0;while key>0 and count<32 do UI.key(key);count=count+1;key=gfx.getchar() end;if key<0 then A.closing=true;App.close();return end
 App.poll_selection(now);App.safe(UI.input);App.process(now)
 if Theme.enabled and now>=Theme.poll_at then Theme.poll_at=now+3;if Theme.refresh(false) then A.dirty=true end end
 if gfx.w~=A.last_w or gfx.h~=A.last_h then A.last_w,A.last_h=gfx.w,gfx.h;A.dirty=true end
 if A.status_until>0 and now>=A.status_until and not A.job then A.status_until=0;A.warning=false;A.dirty=true end
 local flashing=false;for _,time in pairs(A.number_flash) do if now-time<1.2 then flashing=true;break end end
 PrimaryButton.tick(now,A.active,function()A.dirty=true end)
 local primary_state=PrimaryButton.state;local animate=A.job or A.drag or A.number_drag or flashing or (primary_state.particles and #primary_state.particles>0) or #A.icon_particles>0 or (A.primary_hot and A.active) or now<(A.effect_until or 0)
 local interval=animate and (A.drag or A.number_drag) and 1/60 or animate and 1/30 or nil
 if A.dirty and (not interval or now>=A.next_draw) then UI.draw(now);A.dirty=false;A.next_draw=now+(interval or .25)
 elseif animate and now>=A.next_draw then A.dirty=true;UI.draw(now);A.dirty=false;A.next_draw=now+(interval or 1/30) end
 if A.closing then App.close() else R.defer(App.tick) end
end

function App.tick()
 local ok,err=xpcall(App.loop,debug.traceback)
 if not ok then
  gfx.dest=-1;gfx.mode=0;gfx.a=1
  pcall(UI.release_capture);pcall(App.notice,App.public_error(err),true)
  pcall(App.cleanup,A.job);A.job=nil;A.pending_job=nil;A.modal=nil
  Presets.open=false;Presets.swallow=false;Presets.pressed=nil
  pcall(Chrome.cursor,nil)
  -- Independent close edges survive failures before normal input dispatch.
  local down=((gfx.mouse_cap or 0)&1)~=0
  local hit=gfx.mouse_y>=0 and gfx.mouse_y<26 and gfx.mouse_x>=gfx.w-38 and gfx.mouse_x<gfx.w
  if down and not A.emergencyDown then A.emergencyClose=hit end
  if not down and A.emergencyDown then
   if A.emergencyClose and hit then A.closing=true end
   A.emergencyClose=nil
  end
  A.emergencyDown=down;pcall(Chrome.draw);pcall(gfx.update)
  if A.closing then App.close() elseif not A.closed then R.defer(App.tick) else pcall(gfx.quit) end
 else A.emergencyDown=nil;A.emergencyClose=nil end
end
Media.state=A;Media.onchange=function() A.dirty=true end
if ... == 'blt_test' then return {Media=Media,Presets=Presets,Core=Core,A=A,UI=UI,App=App,Chrome=Chrome,Theme=Theme,L=L,BLT={testDraw=UI.draw},Geometry=WindowGeometry} end
local required={'JS_Window_Find' ,'JS_Window_IsWindow','JS_Window_GetRect','JS_Window_SetPosition','JS_Window_SetStyle','JS_Dialog_BrowseForSaveFile'}
if Chrome.isWindows then required[#required+1]='JS_Mouse_LoadCursor';required[#required+1]='JS_Mouse_SetCursor' end
for _,name in ipairs(required) do if type(R[name])~='function' then R.MB(L.text('カスタムアプリバーには js_ReaScriptAPI が必要です。\nReaPack から js_ReaScriptAPI をインストールしてください。'),'BLT Spectral Normalizer',0);return end end
local ww=clamp(tonumber(R.GetExtState(SECTION,'window_w')) or W,Chrome.minW,2200);local wh=clamp(tonumber(R.GetExtState(SECTION,'window_h')) or H+TITLE_H,Chrome.minH,1800)
local wx,wy=tonumber(R.GetExtState(SECTION,'window_x')),tonumber(R.GetExtState(SECTION,'window_y'));gfx.ext_retina=BLT_MAC and 0 or 1
if finite(wx) and finite(wy) then gfx.init(Chrome.title,ww,wh,0,wx,wy) else gfx.init(Chrome.title,ww,wh,0) end
local hwnd=Chrome.handle();local rect_ok,left,top
if hwnd then rect_ok,left,top=WindowGeometry.JS_Window_GetRect(hwnd) end
if not hwnd or not R.JS_Window_SetStyle(hwnd,'POPUP') then gfx.quit();R.MB(L.text('カスタムアプリバーを初期化できません。'),'BLT Spectral Normalizer',0);return end
if rect_ok then Chrome.position(hwnd,left,top,ww,wh) end
R.atexit(App.close);App.poll_selection(R.time_precise());UI.draw(R.time_precise());A.dirty=false;App.tick()
