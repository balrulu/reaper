-- @description ENVELOPE CANVAS TRACK
-- @version 0.7.3
-- @author Balrulu
-- @provides
--   . > ../
-- @changelog
--   BLT SERIES Beta TEST UPLOAD
-- @about
--   BLT SERIES Beta TEST UPLOAD

local reaper=reaper
do
-- BEGIN BLT NATIVE DIALOGS 1.2.0 (generated from _shared/BLT_NativeDialogs.lua)
local BLTNativeDialogs=(function()
 local M={}
 function M.install(api,view)
  local P=setmetatable({}, {__index=api})
  local title,depth=nil,0
  local active,pending,scheduled,rounds,exitHandler=nil,nil,false,0,nil
  local host=api
  for _=1,8 do
   local mt=getmetatable(host)
   if type(mt)~='table' or type(mt.__index)~='table' then break end
   host=mt.__index
  end
  local windowsOS=api.GetOS and (api.GetOS() or ''):match('Win')~=nil
  if view and view.init then
   local init=view.init
   view.init=function(name,...)
    title=name;return init(name,...)
   end
  end
  local function valid(hwnd)
   if not hwnd or hwnd==0 then return false end
   local value=api.JS_Window_IsWindow(hwnd);return value==true or value==1
  end
  local function owned(hwnd,main)
   if not main then return false end
   local seen={}
   for _=1,32 do
    if hwnd==main then return true end
    if not hwnd or seen[hwnd] then return false end;seen[hwnd]=true
    local parent=api.JS_Window_GetParent and api.JS_Window_GetParent(hwnd)
    if parent==0 or parent==hwnd then parent=nil end
    hwnd=parent or (api.JS_Window_GetRelated and api.JS_Window_GetRelated(hwnd,'OWNER'))
   end
   return false
  end
  local function suspend(session)
   if not api.JS_Window_Find or not api.JS_Window_IsWindow then return end
   local own=title and api.JS_Window_Find(title,true)
   local main=api.GetMainHwnd and api.GetMainHwnd()
   local candidates,seen={},{}
   local function add(hwnd)
    if hwnd~=main and valid(hwnd) and not seen[hwnd] then candidates[#candidates+1]=hwnd;seen[hwnd]=true end
   end
   add(own)
   if api.JS_Window_ListAllTop and api.JS_Window_HandleFromAddress and api.JS_Window_GetTitle then
    local _,list=api.JS_Window_ListAllTop()
    for address in (list or ''):gmatch('[^,]+') do
     local n=tonumber(address) or tonumber(address,16)
     local hwnd=n and api.JS_Window_HandleFromAddress(n)
     if valid(hwnd) then
      local caption=api.JS_Window_GetTitle(hwnd) or ''
      if (caption:match('^BLT[%s_:]') or caption=='LOUDNESS TRACE') and owned(hwnd,main) then add(hwnd) end
     end
    end
   end
   if #candidates==0 then return end
   assert(api.JS_Window_Enable and api.JS_Window_GetLong,'Native dialogs require JS_Window_Enable and JS_Window_GetLong (js_ReaScriptAPI).')
   session.foreground=api.JS_Window_GetForeground and api.JS_Window_GetForeground()
   session.main=main
   for _,hwnd in ipairs(candidates) do
    local style=api.JS_Window_GetLong(hwnd,'STYLE')
    assert(type(style)=='number','Cannot read BLT window input state.')
    local topmost=windowsOS and (math.floor(api.JS_Window_GetLong(hwnd,'EXSTYLE'))&8)~=0
    local enabled=(math.floor(style)&0x08000000)==0
    if enabled or topmost then
     local entry={hwnd=hwnd,enabled=enabled,topmost=topmost};session.windows[#session.windows+1]=entry
     if topmost then
      assert(api.JS_Window_SetZOrder,'Native dialogs require JS_Window_SetZOrder (js_ReaScriptAPI).')
      assert(api.JS_Window_SetZOrder(hwnd,'NOTOPMOST'),'Cannot suspend BLT always-on-top state.')
     end
     if enabled then
      api.JS_Window_Enable(hwnd,false)
      assert((math.floor(api.JS_Window_GetLong(hwnd,'STYLE'))&0x08000000)~=0,'Cannot suspend BLT window input.')
     end
    end
   end
  end
  local function has_flag(hwnd,name,mask,on)
   local ok,value=pcall(api.JS_Window_GetLong,hwnd,name)
   return ok and type(value)=='number' and value==value and math.abs(value)<math.huge
    and ((math.floor(value)&mask)~=0)==on
  end
  local function restore(session)
   local failed={}
   for i=#session.windows,1,-1 do
    local entry=session.windows[i]
    local checked,exists=pcall(valid,entry.hwnd)
    if not checked or exists then
     local enabled,topmost=not entry.enabled,not entry.topmost
     for _=1,3 do
      if not enabled then
       enabled=has_flag(entry.hwnd,'STYLE',0x08000000,false)
       if not enabled then
        pcall(api.JS_Window_Enable,entry.hwnd,true)
        enabled=has_flag(entry.hwnd,'STYLE',0x08000000,false)
       end
      end
      if not topmost then
       topmost=has_flag(entry.hwnd,'EXSTYLE',8,true)
       if not topmost then
        pcall(api.JS_Window_SetZOrder,entry.hwnd,'TOPMOST')
        topmost=has_flag(entry.hwnd,'EXSTYLE',8,true)
       end
      end
      if enabled and topmost then break end
     end
     entry.inputRestored=enabled
     if not enabled or not topmost then failed[#failed+1]=entry end
    end
   end
   -- Do not take focus back if the user switched to another application.
   pcall(function()
    local current=api.JS_Window_GetForeground and api.JS_Window_GetForeground()
    if session.foreground and valid(session.foreground) and (current==session.main or owned(current,session.main)) then
     for _,entry in ipairs(session.windows) do
      if entry.enabled and entry.inputRestored and (session.foreground==entry.hwnd or owned(session.foreground,entry.hwnd)) then
       if api.JS_Window_SetForeground then api.JS_Window_SetForeground(entry.hwnd) end
       break
      end
     end
    end
   end)
   return failed
  end
  local function warn()
   if host.ShowConsoleMsg then
    pcall(host.ShowConsoleMsg,'BLT: ウィンドウの操作状態／最前面状態を復元できませんでした。操作できないBLTはアクションリストから終了・再実行してください。\nBLT window recovery failed after retries. Stop and restart the affected BLT action.\n')
   end
  end
  local function retry()
   scheduled=false
   if not pending then return end
   if depth>0 then
    if host.defer then scheduled=true;host.defer(retry) end
    return
   end
   pending.windows=restore(pending)
   if #pending.windows==0 then pending=nil;return end
   rounds=rounds+1
   if rounds<8 and host.defer then scheduled=true;host.defer(retry) else warn() end
  end
  local function recover(session,failed)
   if #failed==0 then return end
   if not pending then pending={windows={},main=session.main,foreground=session.foreground};rounds=0 end
   for _,entry in ipairs(failed) do
    local duplicate=false
    for _,old in ipairs(pending.windows) do
     if old.hwnd==entry.hwnd then
      old.enabled,old.topmost=old.enabled or entry.enabled,old.topmost or entry.topmost;duplicate=true;break
     end
    end
    if not duplicate then pending.windows[#pending.windows+1]=entry end
   end
   if not scheduled then
    if host.defer then scheduled=true;host.defer(retry) else retry() end
   end
  end
  if type(api.atexit)=='function' then
   local function finish()
    if active then local session=active;active=nil;local failed=restore(session);if #failed>0 then warn() end end
    if pending then pending.windows=restore(pending);if #pending.windows>0 then warn() end end
    if exitHandler then exitHandler() end
   end
   P.atexit=function(fn) exitHandler=fn;return api.atexit(finish) end
   api.atexit(finish)
  end
  local function call(fn,...)
   if depth>0 then return fn(...) end
   local args=table.pack(...);local session={windows={}};depth=depth+1;active=session
   local result=table.pack(xpcall(function() suspend(session);return fn(table.unpack(args,1,args.n)) end,debug.traceback))
   local failed=restore(session);active=nil;depth=depth-1;recover(session,failed)
   if not result[1] then error(result[2],0) end
   return table.unpack(result,2,result.n)
  end
  for _,name in ipairs({'GetUserInputs','MB','ShowMessageBox','GetUserFileName','GetUserFileNameForRead','JS_Dialog_BrowseForSaveFile','JS_Dialog_BrowseForOpenFiles','JS_Dialog_BrowseForFolder','GR_SelectColor','Main_OnCommand','Main_OnCommandEx','CF_SendActionShortcut','MIDIEditor_LastFocused_OnCommand'}) do
   local fn=api[name]
   if type(fn)=='function' then P[name]=function(...) return call(fn,...) end end
  end
  if type(api.GetSetProjectInfo_String)=='function' then
   local fn=api.GetSetProjectInfo_String
   P.GetSetProjectInfo_String=function(project,key,value,...)
    local stats=key=='RENDER_STATS' or key=='RENDER_STATS_SUMMARY'
    if stats and value and value~='' and tonumber(value)~=0 then return call(fn,project,key,value,...) end
    return fn(project,key,value,...)
   end
  end
  -- Native actions may also display modal progress or error windows.
  P.BLT_WithNativeDialog=call
  return P
 end
 return M
end)()
-- END BLT NATIVE DIALOGS

reaper=BLTNativeDialogs.install(reaper,gfx)
end

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

local reaper=create_external_storage(reaper,'BLT_ENVELOPE_CANVAS_TRACK',debug.getinfo(1,'S').source,{'preferences_v1','background_mode','spectrum_scale'})

local BLTPresetLimits={bytes=16777216,stringBytes=2097152,nodes=262144,entries=8192}
function BLTPresetLimits.show(english)
 reaper.MB(english and 'Preset capacity limit exceeded. Export presets individually instead of as a bundle.' or '容量上限オーバーです。一括ではなく個別に保存してください。','BLT PRESET',0)
end

local BLT={}

BLT.Controls=(function()
local M={}
M.compactScale=458/904
M.palette={bg={.018,.030,.055},panel={.040,.068,.110},field={.018,.040,.080},
 edge={.145,.285,.445},ice={.650,.895,1},accent={.120,.490,.980},
 text={.955,.980,1},muted={.690,.780,.875},disabled={.43,.46,.51},red={1,.18,.26}}
function M.new(g,clock,palette)
 if not palette then
  palette={};for key,c in pairs(M.palette) do palette[key]={c[1],c[2],c[3]} end
 end
 local U={C=palette,states={},order={},scale=1,ox=0,oy=0}
 local min,max,sin,pi,floor,exp=math.min,math.max,math.sin,math.pi,math.floor,math.exp
 local empty={}
 local function approach(value,target,factor,epsilon)
  if value==target then return value end
  value=value+(target-value)*factor
  return math.abs(target-value)<epsilon and target or value
 end
 local function recycle(items,pool)
  for i=#items,1,-1 do pool[#pool+1]=items[i];items[i]=nil end
 end
 local mixed={}
 local function fade(a)
  local t=min(1,a/.12)
  return t*t*(3-2*t)
 end
 local function blend(from,to,t,fromAlpha,toAlpha)
  if t==0 then return from,fromAlpha or 1 end
  if t==1 then return to,toAlpha or 1 end
  local a,b=(fromAlpha or 1)*(1-t),(toAlpha or 1)*t
  local alpha=a+b
  for i=1,3 do mixed[i]=(from[i]*a+to[i]*b)/alpha end
  return mixed,alpha
 end
 local points={{},{},{},{},{},{}}
 local arrow={{},{},{},{},{},{},{}}
 local arrowShape={{-1,-8},{1,-8},{1,-1},{6,-1},{0,5},{-6,-1},{-1,-1}}
 local cornerWeights={1,.5625,.25,.0625,0}
 local goldEdges={1,.85,.35,.24,.45,.90}
 local gold={field={.025,.027,.030},edge={.38,.33,.23},ice={1,.92,.74},accent={.88,.66,.32},text={.98,.94,.84},rim={.94,.79,.51},gilded=true}
 local chaos={field={.038,.014,.068},edge={.34,.14,.48},ice={.87,.69,1},accent={.62,.23,.94},text={.87,.69,1},ember={.92,.27,.65},spark={.97,.93,1}}
 U.tones={gold=gold,chaos=chaos}
 local faceCache,glowCache,colorCache={},{},{}
 local idleLights={}
 for band=0,4 do idleLights[band+1]=exp(-((band/4-.18)/.46)^2) end
 local function surfaceColors(C,h,k,hover,selected,pressed,hotspot,field,themed)
  if hotspot~=.18 or h>256 or (hover~=0 and hover~=1 and hover~=.4 and hover~=.85 and hover~=.24 and hover~=.82 and hover~=.12) then return end
  selected,pressed=not not selected,not not pressed
  local accent,ice=C.accent,C.ice
  for _,entry in ipairs(colorCache) do
   if entry.palette==C and entry.h==h and entry.k==k and entry.hover==hover and entry.selected==selected and entry.pressed==pressed and entry.themed==themed then
    local signature=entry.signature
    if signature[1]==field[1] and signature[2]==field[2] and signature[3]==field[3] and
     signature[4]==accent[1] and signature[5]==accent[2] and signature[6]==accent[3] and
     signature[7]==ice[1] and signature[8]==ice[2] and signature[9]==ice[3] and entry.gilded==(C.gilded==true) then return entry end
   end
  end
  colorCache.next=(colorCache.next or 0)%16+1
  local entry=colorCache[colorCache.next] or {colors={},packed={},signature={}}
  colorCache[colorCache.next]=entry
  entry.palette,entry.h,entry.k,entry.hover,entry.selected,entry.pressed,entry.gilded=C,h,k,hover,selected,pressed,C.gilded==true
  entry.themed=themed
  local signature=entry.signature
  for i=1,3 do signature[i],signature[i+3],signature[i+6]=field[i],accent[i],ice[i] end
  return entry,true
 end
 local function rows(cache,h,k,pressed)
  for _,entry in ipairs(cache) do
   if entry.h==h and entry.k==k and entry.pressed==pressed then return entry end
  end
  local entry={h=h,k=k,pressed=pressed}
  if k then
   for row=0,floor(h)-1 do
    local v=row/max(1,h-1)
    entry[row+1]={max(0,k-(h-1-row)),max(0,k-row),1-.08*exp(-((v-.72)/.30)^2),
     .18+.82*(1-v)^1.5,exp(-((v-.04)/.43)^2),v,.72*(1-v)^2}
   end
  else
   for row=-14,floor(h)+13 do
    local edgeFade=min(1,(row+14)/12,(h+13-row)/12)
    entry[row+15]=exp(-((row-h*pressed)/(h*.35+12))^2)*max(0,edgeFade)
   end
  end
  cache.next=(cache.next or 0)%8+1;cache[cache.next]=entry
  return entry
 end
 function U:state(id) self.states[id]=self.states[id] or {};return self.states[id] end
 function U:rect(x,y,w,h,c,a,fill)
  g.set(c[1],c[2],c[3],a or 1);g.rect(self.ox+x*self.scale,self.oy+y*self.scale,w*self.scale,h*self.scale,fill==false and 0 or 1)
 end
 function U:line(x,y,xx,yy,c,a,width)
  g.set(c[1],c[2],c[3],a or 1);g.line(self.ox+x*self.scale,self.oy+y*self.scale,self.ox+xx*self.scale,self.oy+yy*self.scale,1,width and width*self.scale or nil)
 end
 function U:disc(x,y,r,c,a)
  g.set(c[1],c[2],c[3],a or 1);g.circle(self.ox+x*self.scale,self.oy+y*self.scale,r*self.scale,1,1)
 end
 function U:glowParticle(x,y,r,a,glint)
  local C=self.C
  self:disc(x,y,r+6,C.accent,.008*a)
  self:disc(x,y,r+4,C.accent,.030*a)
  self:disc(x,y,r+2.2,C.ice,.10*a)
  self:disc(x,y,r+(glint and .35 or 0),glint and C.text or C.ice,(glint and .65 or .74)*a)
  if glint then
   self:rect(x-.35,y-2.1,.7,4.2,C.ice,.33*a);self:rect(x-2.1,y-.35,4.2,.7,C.ice,.26*a)
  end
 end
 function U:text(t,x,y,w,h,size,c,center,bold,face,opticalCenter)
  local px=max(self.minFontSize or 8,floor(size*self.scale+.5));local height=max(h*self.scale,px)
  g.setfont(1,face or self.font or 'Yu Gothic UI',px,bold and 98 or 0)
  g.set(c[1],c[2],c[3],1);g.x=self.ox+x*self.scale;g.y=self.oy+y*self.scale+(h*self.scale-height)/2
  g.drawstr(tostring(t),center=='right' and 6 or center and 5 or 4,self.ox+(x+w)*self.scale,g.y+height,opticalCenter)
 end
 function U:inside(x,y,w,h) return self.mx>=x and self.mx<x+w and self.my>=y and self.my<y+h end
 function U:begin(scale,ox,oy,key)
  self.scale,self.ox,self.oy=scale or 1,ox or 0,oy or 0
  local now=clock();self.dt=min(.1,max(0,now-(self.now or now)));self.now=now
  self.hoverStep,self.lightStep,self.slideStep=min(1,self.dt*14),min(1,self.dt*12),min(1,self.dt*16)
  self.frameSerial=(self.frameSerial or 0)+1
  self.mx=(g.mouse_x-self.ox)/self.scale;self.my=(g.mouse_y-self.oy)/self.scale
  self.speed=min(1,((self.mx-(self.lastX or self.mx))^2+(self.my-(self.lastY or self.my))^2)^.5/3)
  self.lastX,self.lastY=self.mx,self.my
  local down=(g.mouse_cap&1)==1
  self.pressed=down and not self.down;self.released=not down and self.down;self.down=down
  self.key=key or 0;self.wheel=g.mouse_wheel or 0;g.mouse_wheel=0
  if self.editor and self.editor.edit then self.key=0;self.wheel=0 end
  if self.key==9 and #self.order>0 then
   local i=0;for j,id in ipairs(self.order) do if id==self.focus then i=j end end
   local dir=(g.mouse_cap&8)~=0 and -1 or 1
   if i==0 and dir<0 then i=1 end
   self.focus=self.order[(i-1+dir)%#self.order+1]
  end
  for i=#self.order,1,-1 do self.order[i]=nil end;self.hit=false
 end
 function U:finish()
  if self.pressed and not self.hit then self.focus=nil end
  if self.editor then self.editor:frame() end
  if self.released then self.capture=nil end
 end
 function U:interaction(id,x,y,w,h,enabled)
  enabled=enabled~=false and not self.blocked and not (self.editor and self.editor.edit);local s=self:state(id);local hot=enabled and self:inside(x,y,w,h)
  if enabled then self.order[#self.order+1]=id end
  if hot and self.pressed then self.capture=id;self.focus=id;self.hit=true end
  local held=enabled and self.capture==id and self.down
  local click=enabled and ((self.capture==id and self.released and hot) or (self.focus==id and (self.key==13 or self.key==32)))
  local targetX=hot and max(.12,min(.88,(self.mx-x)/w)) or .18
  s.lightX=approach(s.lightX or targetX,targetX,self.lightStep,.0001)
  s.hover=approach(s.hover or 0,hot and 1 or 0,self.hoverStep,.0001)
  return click,hot,held,s
 end
 function U:shape(x,y,w,h,k,c,alpha,fill,weights)
  alpha=alpha or 1
  local right,bottom=x+w-1,y+h-1
  k=min(k,math.floor((h-1)/3),math.floor((w-1)/3))
  if fill then
   if g.polygon then
    local scale,ox,oy=self.scale,self.ox,self.oy
    points[1][1],points[1][2]=ox+x*scale,oy+y*scale
    points[2][1],points[2][2]=ox+(right-k)*scale,oy+y*scale
    points[3][1],points[3][2]=ox+right*scale,oy+(y+k)*scale
    points[4][1],points[4][2]=ox+right*scale,oy+bottom*scale
    points[5][1],points[5][2]=ox+(x+k)*scale,oy+bottom*scale
    points[6][1],points[6][2]=ox+x*scale,oy+(bottom-k)*scale
    g.set(c[1],c[2],c[3],alpha or 1)
    g.polygon(points)
    return
   end
   for row=0,math.floor(h)-1 do
    local leftCut=max(0,k-(h-1-row));local rightCut=max(0,k-row)
    self:rect(x+leftCut,y+row,w-leftCut-rightCut,1,c,alpha)
   end
  else
   self:line(x,y,right-k,y,c,alpha*(weights and weights[1] or 1));self:line(right-k,y,right,y+k,c,alpha*(weights and weights[2] or 1))
   self:line(right,y+k,right,bottom,c,alpha*(weights and weights[3] or 1));self:line(right,bottom,x+k,bottom,c,alpha*(weights and weights[4] or 1))
   self:line(x+k,bottom,x,bottom-k,c,alpha*(weights and weights[5] or 1));self:line(x,bottom-k,x,y,c,alpha*(weights and weights[6] or 1))
  end
 end
 function U:surface(x,y,w,h,k,hover,selected,pressed,lightX,palette,background)
  local C=palette or self.C;local hotspot=lightX or .18;local themed=self.themeEnabled==true
  local field=themed and background or C.field
  local cached=g.beginGradient and (hover==0 or hover==1 or hover==.4 or hover==.85 or hover==.24 or hover==.82 or hover==.12)
  if cached and g.beginGradient(themed and 'themeSurface' or 'surface',self.ox+x*self.scale,self.oy+y*self.scale,w*self.scale,h*self.scale,
   self.scale,h,k,hover,hotspot,not not selected,not not pressed,C.gilded==true,
   field[1],field[2],field[3],C.accent[1],C.accent[2],C.accent[3],C.ice[1],C.ice[2],C.ice[3]) then return end
  local bodyBase=.012+.18*hover+(selected and .14 or 0)
  local reflectionBase=.003+.48*hover+.14*(selected and 1 or 0)
  if pressed then bodyBase=bodyBase*.72;reflectionBase=reflectionBase*.64 end
  local lights=idleLights
  if hotspot~=.18 then
   lights=self.lights or {};self.lights=lights
   if self.lightSource~=hotspot then
    for band=0,4 do lights[band+1]=exp(-((band/4-hotspot)/.46)^2) end
    self.lightSource=hotspot
   end
  end
  local geometry=rows(faceCache,h,k)
  local entry,rebuild=surfaceColors(C,h,k,hover,selected,pressed,hotspot,field,themed)
  local colors=entry and entry.colors
  local packed=entry and g.gradcolors and g.packColor and entry.packed
  local gilded=C.gilded==true
  local scale,ox,oy=self.scale,self.ox,self.oy
  local fr,fg,fb=field[1],field[2],field[3]
  local ar,ag,ab=C.accent[1],C.accent[2],C.accent[3]
  local ir,ig,ib=C.ice[1],C.ice[2],C.ice[3]
  for row=0,floor(h)-1 do
   local curve=geometry[row+1];local l=curve[1];local rw=w-l-curve[2]
   local r,gc,b,previous
   for band=0,4 do
    local index=row*15+band*3+1
    local nr,ng,nb
    if entry and not rebuild then nr,ng,nb=colors[index],colors[index+1],colors[index+2]
    else
     local light=lights[band+1];local u=band/4
     local body=bodyBase*(.12+.88*light)*curve[4]*curve[3]
     local reflection=reflectionBase*curve[5]*(.18+.82*light)*(1-.68*u)
     reflection=reflection*(1+cornerWeights[band+1]*curve[7])
     if gilded then body=body*.55;reflection=reflection*.68 end
     if themed then
      local shade=.94+.06*(1-u)*(1-curve[6])
      local keep=max(0,1-body-reflection);local weight=1/max(1,body+reflection)
      nr,ng,nb=min(1,fr*shade*keep+(ar*body+ir*reflection)*weight),min(1,fg*shade*keep+(ag*body+ig*reflection)*weight),min(1,fb*shade*keep+(ab*body+ib*reflection)*weight)
     else
      local shade=.32+.68*(1-u)*(1-curve[6])
      nr,ng,nb=min(1,fr*shade+ar*body+ir*reflection),min(1,fg*shade+ag*body+ig*reflection),min(1,fb*shade+ab*body+ib*reflection)
     end
     if colors then colors[index],colors[index+1],colors[index+2]=nr,ng,nb end
    end
    local encoded
    if packed then
     local at=row*5+band+1
     if rebuild then packed[at]=g.packColor(nr,ng,nb,1) end
     encoded=packed[at]
    end
    if band>0 then
     local bx=x+l+rw*((band-1)/4);local width=rw/4
     if packed then g.gradcolors(ox+bx*scale,oy+(y+row)*scale,width*scale,scale,previous,encoded)
     else g.gradrect(ox+bx*scale,oy+(y+row)*scale,width*scale,scale,
      r,gc,b,1,(nr-r)/(width*scale),(ng-gc)/(width*scale),(nb-b)/(width*scale),0) end
    end
    r,gc,b,previous=nr,ng,nb,encoded
   end
  end
  if cached then g.endGradient() end
 end
 function U:bloom(x,y,w,h,strength,lightX,lightY,palette)
  if strength<=.005 then return end
  local hotspot=lightX or .18;local sourceY=lightY or .08
  local C=palette or self.C
  local mix=C.gilded==true and .55 or .80
  local r,gc,b=C.ice[1]*mix+C.accent[1]*(1-mix),C.ice[2]*mix+C.accent[2]*(1-mix),C.ice[3]*mix+C.accent[3]*(1-mix)
  local cached=g.beginGradient and (strength==1 or strength==.48 or strength==.30 or strength==.22 or strength==.12)
  if cached and g.beginGradient('bloom',self.ox+x*self.scale,self.oy+y*self.scale,w*self.scale,h*self.scale,
   self.scale,h,strength,hotspot,sourceY,r,gc,b) then return end
  local geometry=rows(glowCache,h,nil,sourceY)
  local spans=self.spans or {};self.spans=spans
  local length=w+28;local width=length/8;local scale,ox,oy=self.scale,self.ox,self.oy
  for band=0,7 do
   local bx=x-14+length*band/8;local span=spans[band+1] or {};spans[band+1]=span;span[1]=ox+bx*scale
   for side=0,1 do
    local u=((side==0 and bx or bx+width)-x)/w
    local sideFade=max(0,min(1,(u*w+14)/12,(w+14-u*w)/12))
    span[side*2+2]=exp(-((u-hotspot)/.40)^2);span[side*2+3]=sideFade
   end
  end
  for row=-14,floor(h)+13 do
   local base=.34*strength*geometry[row+15]
   for band=0,7 do
    local span=spans[band+1];local a=base*span[2]*span[3];local alpha=base*span[4]*span[5]
    if max(a,alpha)>=.5/255 then
     g.gradrect(span[1],oy+(y+row)*scale,width*scale,scale,r,gc,b,a,0,0,0,(alpha-a)/(width*scale))
    end
   end
  end
  if cached then g.endGradient() end
 end
 function U:frame(x,y,w,h,opt)
  opt=opt or empty;local C=opt.palette or self.C;local disabled=opt.disabled;local a=opt.hot or 0
  local k=min(10,math.floor(h*.21))
  if not disabled and opt.glow~=false then
   local strength=max(a,opt.selected and .48 or 0,opt.focus and .30 or 0)
   self:bloom(x,y,w,h,strength,opt.lightX,.08,C)
  end
  if disabled then self:shape(x,y,w,h,k,self.C.field,1,true)
  else self:surface(x,y,w,h,k,a,opt.selected,opt.pressed,opt.lightX,C,opt.panel and C.panel) end
  local color,alpha=C.rim or C.ice,.26+.18*a
  if disabled then color,alpha=self.C.disabled,.27
  elseif opt.selected or opt.focus then alpha=.65
  elseif a<.12 then color,alpha=blend(C.edge,color,fade(a),.50,alpha) end
  self:shape(x,y,w,h,k,color,alpha,false,not disabled and C.gilded==true and goldEdges or nil)
 end
 function U:led(x,y,w,h,placement,on,enabled,palette,scale)
  local C=palette or self.C;local color=enabled==false and self.C.disabled or (on and C.text or C.edge)
  local lx,ly,lw,lh;scale=scale or 1
  if placement=='top' then lw=min(30*scale,w*.24);lh=3*scale;lx=x+(w-lw)/2;ly=y+3*scale
  else lw=3*scale;lh=min(18*scale,h-14*scale);lx=x+7*scale;ly=y+(h-lh)/2 end
  self:rect(lx-scale,ly-scale,lw+2*scale,lh+2*scale,self.C.bg,1)
  if on and enabled~=false then
   self:rect(lx-4*scale,ly-4*scale,lw+8*scale,lh+8*scale,C.accent,.12)
   self:rect(lx-2*scale,ly-2*scale,lw+4*scale,lh+4*scale,C.ice,.22)
  end
  self:rect(lx,ly,lw,lh,color,on and enabled~=false and 1 or .32)
 end
 function U:attention(id,enabled,low,high,speed,linear)
  local states=self.attentionStates
  if not enabled then if states then states[id]=nil end;return end
  if not states then states={};self.attentionStates=states end
  local s=states[id]
  local now=self.now;speed=speed or 2.5
  if not s then s={phase=(now*speed)%(2*pi),time=now};states[id]=s end
  local active=self.focused;if active==nil then active=self.active~=false end
  local phase=s.phase+max(0,now-s.time)*speed
  if s.active==false and s.stop then phase=min(phase,s.stop)end
  if not active then
   if s.active~=false then
    s.stop=pi/2+(floor((phase-pi/2)/(2*pi))+2)*2*pi
   end
   phase=min(phase,s.stop)
  else s.stop=nil end
  s.phase,s.time,s.active,s.seen=phase,now,active,self.frameSerial
  local v=s.stop and phase==s.stop and 1 or .5+.5*sin(phase)
  s.level=(low or .08)+((high or .90)-(low or .08))*(linear and v or v*v)
  return s.level
 end
 function U:attentionAnimating()
  if not self.attentionStates then return false end
  for id,s in pairs(self.attentionStates)do
   if s.seen~=self.frameSerial then self.attentionStates[id]=nil
   elseif s.active or s.stop and s.phase<s.stop then return true end
  end
  return false
 end
 function U:button(id,label,x,y,w,h,opt)
  opt=opt or empty;local enabled=opt.enabled~=false
  local trailing=opt.trailing
  local slot=trailing=='color' and (opt.colorSize or min(24,h-12))+20 or (trailing=='menu' and 30 or (trailing=='value' and 80 or 0))
  local click,_,held,s=self:interaction(id,x,y,w-(trailing=='color' and slot or 0),h,enabled)
  local colorClick,colorHot,colorHeld
  if trailing=='color' then
   s.colorID=s.colorID or id..':color'
   colorClick,colorHot,colorHeld=self:interaction(s.colorID,x+w-slot,y,slot,h,enabled)
  end
  held=held or opt.preview=='pressed';local a=(opt.preview=='hover' or held) and 1 or s.hover
  local attention=self:attention(id,enabled and opt.attention)
  if attention then a=max(a,attention)end
  local frame=s.frame or {};s.frame=frame
  frame.disabled,frame.hot,frame.pressed,frame.selected=not enabled,a,held,opt.selected
  frame.palette=nil
  frame.focus,frame.glow,frame.lightX=(self.focus==id or (s.colorID and self.focus==s.colorID)) and enabled,opt.glow,s.lightX
  if opt.variant=='clear' then
   local C=self.C;local k=min(4,floor(h*.12))
   if enabled then
    self:bloom(x,y,w,h,.22+.50*a,s.lightX,.08,C)
    self:surface(x,y,w,h,k,.24+.58*a,false,held,s.lightX,C)
   else self:shape(x,y,w,h,k,C.field,1,true) end
   self:shape(x,y,w,h,k,enabled and C.ice or C.disabled,enabled and (.58+.30*a) or .24,false)
   if enabled then self:line(x+1,y,x+w-1-k,y,C.ice,.70+.30*a,2) end
  else self:frame(x,y,w,h,frame) end
  local ledScale=opt.ledScale or 1
  if opt.led then self:led(x,y,w,h,opt.led,opt.selected,enabled,nil,ledScale) end
  local C=self.C;local pad=opt.leading and (opt.leadingWidth or 28) or (opt.led=='left' and 12+10*(ledScale-1) or 0)
  local accent=enabled and (not self.themeEnabled and opt.accent or C.ice) or C.disabled
  if opt.leading=='insert' then
   local cx,cy=x+(opt.leadingInset or 20),y+h/2+(held and 1 or 0)
   self:insertIcon(cx,cy,h,accent,enabled,opt.leadingScale)
  end
  local labelColor=not enabled and C.disabled or C.text
  if enabled and opt.led and not opt.selected then labelColor=blend(C.muted,C.text,fade(a)) end
  local ty=y+(held and 1 or 0)
  local inset=opt.labelInset or 14
  if opt.secondaryText then
   self:text(opt.secondaryText,x+inset+pad,ty+(opt.captionY or 3),max(0,w-2*inset-pad-slot),opt.captionHeight or 12,opt.captionSize or 9,C.muted,opt.captionAlign or opt.center~=false,false,opt.captionFace)
   ty=ty+(opt.labelY or h*.36)
  end
  local align=opt.center~=false and not opt.leading and trailing~='value'
  if opt.labelAlign then align=opt.labelAlign=='center' or opt.labelAlign=='right' and 'right' end
  self:text(label,x+inset+pad,ty,max(0,w-2*inset-pad-slot),opt.labelHeight or h,opt.size or 14,labelColor,align,opt.bold)
  if trailing=='color' then
   local size=slot-20;local xx,yy=x+w-slot+8,y+(h-size)/2+(colorHeld and 1 or 0)
   self:rect(xx-2,yy-2,size+4,size+4,C.bg,1)
   self:rect(xx,yy,size,size,opt.color or C.accent,enabled and 1 or .25)
   self:rect(xx-2,yy-2,size+4,size+4,colorHot and C.ice or C.edge,enabled and .7 or .25,false)
  elseif trailing=='menu' then
   local cx,cy=x+w-18,y+h/2
   self:line(cx-4,cy-2,cx,cy+2,accent,.8);self:line(cx,cy+2,cx+4,cy-2,accent,.8)
  elseif trailing=='value' then self:text(opt.value or '',x+w-slot,y,slot-14,h,opt.valueSize or 11,accent,true) end
  return click,colorClick
 end
 function U:insertIcon(cx,cy,h,c,enabled,scale)
  local unit=scale or min(1,h/32);local alpha=enabled and 1 or .3
  if g.polygon then
   local ox,oy,scale=self.ox,self.oy,self.scale
   for i,v in ipairs(arrowShape) do arrow[i][1],arrow[i][2]=ox+(cx+v[1]*unit)*scale,oy+(cy+v[2]*unit)*scale end
   g.set(c[1],c[2],c[3],alpha);g.polygon(arrow,true)
  else
   self:rect(cx-unit,cy-8*unit,2*unit,7*unit,c,alpha)
   for row=0,5 do self:rect(cx-(6-row)*unit,cy+(row-1)*unit,(12-row*2)*unit,unit,c,alpha) end
  end
  self:rect(cx-6*unit,cy+8*unit,12*unit,2*unit,c,alpha)
 end
 local function outline(points,w,h,k)
  for i=1,6 do points[i]=points[i] or {} end
  k=min(k,floor((h-1)/3),floor((w-1)/3))
  points[1][1],points[1][2]=0,0
  points[2][1],points[2][2]=w-1-k,0
  points[3][1],points[3][2]=w-1,k
  points[4][1],points[4][2]=w-1,h-1
  points[5][1],points[5][2]=k,h-1
  points[6][1],points[6][2]=0,h-1-k
 end
 local function noise(n) return (sin(n*12.9898)*43758.5453)%1 end
 local function contour(e,w,h)
  outline(e.outline,w,h,min(10,floor(h*.21)));e.perimeter=0
  for i,a in ipairs(e.outline) do
   local b=e.outline[i%6+1];local dx,dy=b[1]-a[1],b[2]-a[2]
   e.lengths[i]=(dx*dx+dy*dy)^.5;e.perimeter=e.perimeter+e.lengths[i]
  end
  e.w,e.h=w,h
  return e.perimeter
 end
 local function onPerimeter(e,t)
  local distance=(t%1)*e.perimeter;local edge=1
  while edge<6 and distance>=e.lengths[edge] do distance=distance-e.lengths[edge];edge=edge+1 end
  local a,b=e.outline[edge],e.outline[edge%6+1];local length=e.lengths[edge]
  local dx,dy=b[1]-a[1],b[2]-a[2];local u=distance/length
  return a[1]+dx*u,a[2]+dy*u,dy/length,-dx/length
 end
 function U:lightLine(x,y,xx,yy,P,tint,a,outer,middle,inner)
  local scale,ox,oy=self.scale,self.ox,self.oy
  x,y,xx,yy=ox+x*scale,oy+y*scale,ox+xx*scale,oy+yy*scale
  g.set(tint[1],tint[2],tint[3],outer*a);g.line(x,y,xx,yy,1,7*scale)
  local c=P.ice;g.set(c[1],c[2],c[3],middle*a);g.line(x,y,xx,yy,1,3*scale)
  c=P.spark or P.text;g.set(c[1],c[2],c[3],inner*a);g.line(x,y,xx,yy,1,scale)
 end
 function U:arc(points,x,y,a,P,tint)
  if a<=.005 then return end
  for j=1,#points-1 do
   local p,q=points[j],points[j+1]
   self:lightLine(x+p[1],y+p[2],x+q[1],y+q[2],P,tint,a,.045,.20,.90)
  end
 end
 function U:electric(s,x,y,w,h,strength,P)
  if strength<=.02 then return end
  local e=s.electric or {outline={},lengths={},arcs={}};s.electric=e
  local bucket=floor(self.now*24)
  if e.w~=w or e.h~=h then
   contour(e,w,h);e.bucket=nil
  end
  if e.bucket~=bucket then
   e.bucket=bucket
   for i=1,4 do
    local arc=e.arcs[i] or {};e.arcs[i]=arc
    local start=(self.now*.38+(i-1)/4+noise(bucket+i*37)*.045)%1
    local length=.11+.08*noise(bucket*.37+i*19)
    local flicker=noise(bucket+i*47)
    arc.alpha=flicker<.12 and 0 or (.20+.80*flicker)^2
    for j=0,10 do
     local u=j/10;local px,py,nx,ny=onPerimeter(e,start+u*length)
     local offset=.5+sin(pi*u)*(1+7*noise(bucket*31+i*137+j*17))
     local p=arc[j+1] or {};arc[j+1]=p;p[1],p[2]=px+nx*offset,py+ny*offset
    end
   end
  end
  for i,arc in ipairs(e.arcs) do
   local a=strength*arc.alpha;local tint=i%2==0 and (P.ember or P.accent) or P.accent
   if a>.005 then
   self:arc(arc,x,y,a,P,tint)
   local p=arc[6]
   self:disc(x+p[1],y+p[2],2.8,P.ice,.06*a)
   self:disc(x+p[1],y+p[2],.8,P.spark or P.text,.85*a)
   end
  end
 end
 function U:electricFlash(s,x,y,w,h,enabled,P)
  if not s.sparkAt then return end
  local age=max(0,self.now-s.sparkAt)
  if enabled and age<.26 then self:electric(s,x,y,w,h,(1-age/.26)^1.5,P)
  else s.sparkAt=nil end
 end
 function U:chaos(id,label,x,y,w,h,opt)
  opt=opt or empty;local enabled=opt.enabled~=false
  local click,over,held,s=self:interaction(id,x,y,w,h,enabled)
  held=held or opt.preview=='pressed'
  local hot=(opt.preview=='hover' or held) and 1 or s.hover
  local C=self.C;local P=self.themeEnabled and self.themeTones and self.themeTones.chaos or chaos
  local breath=enabled and (.5+.5*sin(self.now*.85)) or 0
  local frame=s.frame or {};s.frame=frame
  frame.disabled,frame.hot,frame.pressed,frame.selected=not enabled,.12+.10*breath+.55*hot,held,nil
  frame.focus,frame.palette,frame.lightX=self.focus==id and enabled,P,s.lightX
  self:frame(x,y,w,h,frame)
  if s.chaosFrame and self.frameSerial-s.chaosFrame>1 then s.over=false;s.sparkAt=nil end
  s.chaosFrame=self.frameSerial
  over=enabled and (over or opt.preview=='hover' or opt.preview=='pressed')
  if over and not s.over then s.sparkAt=self.now end
  s.over=over
  self:electricFlash(s,x,y,w,h,enabled,P)
  local yy=y+(held and 1 or 0);local center=h/2
  if enabled then
   for i=1,6 do
    local phase=self.now*.3+i*1.7;local px=x+12+(i-1)*(w-29)/5
    local py=yy+center+sin(phase)*(center-6)
    if px<x+36 or px>x+w-36 or math.abs(py-yy-center)>11 then
     local a=.18+.22*sin(phase*.7)^2
     self:disc(px,py,3,P.accent,a*.08)
     self:disc(px,py,.7,i%2==0 and (P.ember or P.accent) or P.text,a)
    end
   end
   self:line(x+w*.335,yy+h-5,x+w*.665,yy+h-5,P.accent,.18+.22*breath+.2*hot)
  end
  self:text(label or 'C H A O S',x+18,yy,w-36,h,opt.size or min(17,h*.34),enabled and P.text or C.disabled,true,true)
  return click
 end
 function U:particles(s,x,y,w,h,hover,busy)
  if self.active==false and not s.particles then return end
  s.particles=s.particles or {};s.pool=s.pool or {};s.serial=s.serial or 0;s.pc=s.pc or 0
  if self.active~=false and (hover or busy) then
   s.pc=s.pc+(busy and self.dt or self.dt*self.speed)
   local interval=busy and .030 or .055;local cap=busy and 66 or 44
   while s.pc>=interval and #s.particles<cap do
    s.pc=s.pc-interval;s.serial=s.serial+1;local n=s.serial
    local a=(sin(n*12.9898)*43758.5453)%1;local b=(sin(n*78.233)*12345.6789)%1
    local p=s.pool[#s.pool] or {};s.pool[#s.pool]=nil
    p.x=busy and 12+a*(w-24) or self.mx-x+(a-.5)*7
    p.y=busy and h-7-b*8 or self.my-y+(b-.5)*5
    p.born,p.age,p.life=self.now,0,busy and .65+a*.65 or 1.6+a*1.2
    p.vx,p.vy,p.phase=(b-.5)*(busy and 15 or 7),busy and 10+a*14 or 6+a*8,b*pi*2
    s.particles[#s.particles+1]=p
   end
  else s.pc=self.active==false and 0 or min(s.pc,.04) end
  for i=#s.particles,1,-1 do
   local p=s.particles[i];p.age=max(0,self.now-p.born)
   if p.age>=p.life then s.pool[#s.pool+1]=p;table.remove(s.particles,i) else
    local px=x+p.x+p.vx*p.age+sin(p.age*1.6+p.phase)*2;local py=y+p.y-p.vy*p.age;local e=sin(pi*p.age/p.life)^2
    if px>x+5 and px<x+w-5 and py>y+5 and py<y+h-5 then
     if busy then
      self:disc(px,py,4.4,self.C.accent,.035*e)
      self:disc(px,py,2.2,self.C.ice,.10*e)
      self:disc(px,py,.85,self.C.ice,.78*e)
     else self:glowParticle(px,py,1.2,e) end
    end
   end
  end
 end
 function U:complete(id,w,h)
  local s=self:state(id);s.completionSerial=(s.completionSerial or 0)+1
  local b=s.burst or {outline={},lengths={},nodes={},particles={},pool={},serial=0};s.burst=b
  recycle(b.particles,b.pool)
  b.started,b.active=self.now,true
  local perimeter=contour(b,w,h)
  local spacing=max(90,perimeter/16);local count=0
  for edge=1,6 do
   if edge~=2 and edge~=5 then
    local v,nextv=b.outline[edge],b.outline[edge%6+1]
    local dx,dy=nextv[1]-v[1],nextv[2]-v[2];local length=b.lengths[edge]
    local slots=max(1,floor(length/spacing+.5))
    for slot=1,slots do
     count=count+1;local n=b.serial+count*73
     local node=b.nodes[count] or {stem={},branch={}};b.nodes[count]=node
     node.edge,node.t,node.nx,node.ny,node.tx,node.ty=edge,(slot-.5+(noise(n)-.5)*.44)/slots,dy/length,-dx/length,dx/length,dy/length
     node.delay,node.life,node.seed,node.bucket=count==1 and 0 or noise(n+41)*.060,.11+noise(n+9)*.09,n,nil
     node.reach,node.side=min(24,h*.20+4)*1.35*(.65+.35*noise(n+17)),noise(n+27)*1.6-.8
    end
   end
  end
  b.nodeCount=count
  for i=1,count*6 do
   b.serial=b.serial+1;local n=b.serial
   local r1=(sin(n*12.9898)*43758.5453)%1;local r2=(sin(n*78.233)*12345.6789)%1
   local node=b.nodes[(i-1)%count+1]
   local streak=i%3==0;local speed=(streak and 80 or 28)+r2*(streak and 65 or 54)
   local tangent=(r1-.5)*speed*1.4
   local p=b.pool[#b.pool] or {};b.pool[#b.pool]=nil
   p.edge,p.t=node.edge,max(0,min(1,node.t+(r2-.5)*min(.06,10/b.lengths[node.edge])))
   p.vx,p.vy=node.nx*speed+node.tx*tangent,node.ny*speed+node.ty*tangent
   local velocity=(p.vx*p.vx+p.vy*p.vy)^.5
   p.dx,p.dy,p.trail=p.vx/velocity,p.vy/velocity,streak and (4+r2*7) or 0
   p.life,p.delay,p.drag,p.radius=.36+r1*.44,node.delay+r2*.028,3+r1*3,.5+r2*.35
   b.particles[#b.particles+1]=p
  end
 end
 function U:discharge(b,x,y,age)
  local C=self.C
  for i=1,b.nodeCount do
   local node=b.nodes[i]
   local t=age-node.delay
   if t>=0 and t<node.life then
    local v,q=b.outline[node.edge],b.outline[node.edge%6+1]
    local px,py=v[1]+(q[1]-v[1])*node.t,v[2]+(q[2]-v[2])*node.t
    local bucket=floor(t*30)
    if node.bucket~=bucket or node.x~=px or node.y~=py then
     node.bucket,node.x,node.y=bucket,px,py
     for j=0,8 do
      local u=j/8;local jitter=sin(pi*u)*(noise(node.seed+bucket*31+j*17)*2-1)*8.1
      local outward=node.reach*u
      local side=node.reach*node.side*u+jitter
      local p=node.stem[j+1] or {};node.stem[j+1]=p
      p[1],p[2]=px+node.nx*outward+node.tx*side,py+node.ny*outward+node.ty*side
     end
     local root=node.stem[5]
     for j=0,3 do
      local u=j/3;local reach=node.reach*.55*u
      local side=-node.side*reach+(noise(node.seed+bucket*19+j*7)*2-1)*sin(pi*u)*5.4
      local p=node.branch[j+1] or {};node.branch[j+1]=p
      p[1],p[2]=root[1]+node.nx*reach+node.tx*side,root[2]+node.ny*reach+node.ty*side
     end
    end
    local a=(1-t/node.life)^.7*(.65+.35*noise(node.seed+bucket*43))
    self:arc(node.stem,x,y,a,C,C.accent)
    self:arc(node.branch,x,y,a*.55,C,C.ice)
    self:disc(x+px,y+py,5,C.accent,.12*a)
    self:disc(x+px,y+py,1,C.text,.85*a)
   end
  end
 end
 function U:completion(s,x,y,w,h)
  local b=s.burst;if not b or not b.active then return end
  local age=max(0,self.now-b.started);local C=self.C
  if b.w~=w or b.h~=h then contour(b,w,h) end
  if age<.22 then
   local flash=(1-age/.22)^3
   for i,p in ipairs(b.outline) do
    local q=b.outline[i%6+1]
    self:lightLine(x+p[1],y+p[2],x+q[1],y+q[2],C,C.accent,flash,.08,.30,.95)
   end
  end
  if age<.26 then
   self:electric(b,x,y,w,h,(1-age/.26)^1.5,C)
   self:discharge(b,x,y,age)
  end
  for i=#b.particles,1,-1 do
   local p=b.particles[i]
   local t=age-p.delay
   if t>=p.life then b.pool[#b.pool+1]=p;table.remove(b.particles,i)
   elseif t>=0 then
    local v,nextv=b.outline[p.edge],b.outline[p.edge%6+1]
    local drag=exp(-p.drag*t);local travel=(1-drag)/p.drag
    local px=x+v[1]+(nextv[1]-v[1])*p.t+p.vx*travel
    local py=y+v[2]+(nextv[2]-v[2])*p.t+p.vy*travel;local e=(1-t/p.life)^2
    if p.trail>0 then
     local length=p.trail*min(1,t/.025)*drag
     if length>.03 then
      self:line(px,py,px-p.dx*length,py-p.dy*length,C.accent,.10*e,3)
      self:line(px,py,px-p.dx*length,py-p.dy*length,C.ice,.65*e,1)
     end
    end
    self:disc(px,py,3.6,C.accent,.06*e);self:disc(px,py,1.7,C.ice,.18*e);self:disc(px,py,p.radius,C.ice,.90*e)
   end
  end
  if age>=.26 and #b.particles==0 then b.active=false end
 end
 function U:executeAnimating(id)
  local s=self.states[id]
  return s and ((s.particles and #s.particles>0) or (s.burst and s.burst.active)) or false
 end
 function U:execute(id,label,x,y,w,h,opt)
  opt=opt or empty;local busy=opt.busy;local enabled=opt.enabled~=false
  local click,hot,held,s=self:interaction(id,x,y,w,h,enabled and (not busy or opt.cancelable==true))
  held=held or opt.preview=='pressed'
  local frame=s.frame or {};s.frame=frame
  frame.disabled,frame.hot,frame.pressed,frame.focus,frame.lightX=not enabled,busy and .85 or enabled and max(.12,s.hover) or s.hover,held,self.focus==id and enabled,s.lightX
  frame.selected,frame.glow,frame.palette=nil,nil,nil
  self:frame(x,y,w,h,frame)
  if enabled then self:particles(s,x,y,w,h,hot,busy)
  elseif s.particles then recycle(s.particles,s.pool) end
  if opt.autoComplete~=false and enabled and s.busy and not busy and (s.seenCompletion or 0)==(s.completionSerial or 0) then self:complete(id,w,h) end
  s.seenCompletion,s.busy=s.completionSerial,busy
  if enabled or opt.finishWhenDisabled then self:completion(s,x,y,w,h)
  elseif s.burst and s.burst.active then
   s.burst.active=false
   recycle(s.burst.particles,s.burst.pool)
  end
  local c=enabled and self.C.ice or self.C.disabled
  self:text(not enabled and 'UNAVAILABLE' or opt.caption or (busy and 'PROCESSING' or 'EXECUTE'),x+18,y+(opt.captionY or h/2-24),w-36,opt.captionHeight or 20,opt.captionSize or 10,c,true)
  self:text(label,x+18,y+(opt.labelY or h/2-3)+(held and 1 or 0),w-36,opt.labelHeight or 25,opt.size or 16,enabled and self.C.text or c,true,opt.bold)
  local rail=x+18;local length=max(1,w-36)
  self:rect(rail,y+h-9,length,1,c,.13)
  if busy then self:rect(rail,y+h-9,length*max(0,min(1,opt.progress or 0)),1,c,.85) end
  return click
 end
 function U:toggleWidth(id,label,w,h,opt)
  opt=opt or empty;local s=self:state(id)
  local unit=opt.switchScale or 1;local sw=min(32*unit,w*.25)
  local offset=opt.labelOffset or sw+24*unit
  local text=tostring(opt.hitLabel or label)
  local size=max(self.minFontSize or 8,floor((opt.size or 13)*self.scale+.5))
  local face=opt.face or self.font or 'Yu Gothic UI';local bold=opt.bold and 98 or 0
  local cache=s.toggleMeasure
  if not cache or cache.text~=text or cache.size~=size or cache.face~=face or cache.bold~=bold or cache.scale~=self.scale or cache.dpi~=g.ext_retina then
   g.setfont(1,face,size,bold)
   cache={text=text,size=size,face=face,bold=bold,scale=self.scale,dpi=g.ext_retina,width=g.measurestr(text)/self.scale}
   s.toggleMeasure=cache
  end
  if opt.showState~=false and not cache.stateWidth then
   local stateSize=max(self.minFontSize or 8,floor(10*self.scale+.5))
   g.setfont(1,self.font or 'Yu Gothic UI',stateSize,0);cache.stateWidth=g.measurestr('OFF')/self.scale
  end
  local room=max(0,w-offset-5*unit-(opt.showState==false and 0 or 10*unit+cache.stateWidth))
  s.toggleLabelWidth=min(room,cache.width);s.toggleLabelX=offset
  local right=max(12*unit+sw,offset+s.toggleLabelWidth)
  if opt.showState~=false then s.toggleStateX=right+10*unit;s.toggleStateWidth=cache.stateWidth;right=s.toggleStateX+s.toggleStateWidth end
  s.toggleWidth=min(w,opt.hitWidth or right+5*unit)
  return s.toggleWidth
 end
 function U:toggleColor(value,enabled)
  if enabled==false then return self.C.disabled end
  return value and self.C.text or blend(self.C.disabled,self.C.muted,.45)
 end
 function U:toggle(id,label,value,x,y,w,h,enabled,opt)
  opt=opt or empty
  local hitWidth=self:toggleWidth(id,label,w,h,opt)
  local click,_,_,s=self:interaction(id,x,y,hitWidth,h,enabled)
  if click then value=not value end
  if s.slide==nil then s.slide=value and 1 or 0 end
  local target=value and 1 or 0
  s.slide=approach(s.slide,target,self.slideStep,1e-12)
  local C=self.C;local c=enabled==false and C.disabled or C.ice
  local background=opt.background~=false;local unit=opt.switchScale or 1
  if background then
   self:rect(x,y,w,h,C.panel,enabled==false and .3 or .65)
   if self.focus==id and enabled~=false then self:rect(x,y,w,h,C.accent,.10) end
  end
  local sw=min(32*unit,w*.25);local sx=x+12*unit;local cy=y+h/2
  local radius=min(6.5*unit,h*.19)
  local thumb=sx+radius+(sw-2*radius)*s.slide
  local railH=max(1.5*unit,1/(self.scale*(g.ext_retina or 1)));local railY=cy-railH/2
  self:rect(sx,railY,sw,railH,enabled==false and C.disabled or (background and C.edge or C.muted),enabled==false and .28 or (background and .85 or .55))
  if s.slide>.005 and enabled~=false then
   self:rect(sx,railY,thumb-sx,railH,C.ice,.95*s.slide)
   self:disc(thumb,cy,radius+3*unit,C.accent,.11*s.slide)
   self:disc(thumb,cy,radius+1.7*unit,C.ice,.10*s.slide)
  end
  if not background and self.focus==id and enabled~=false then self:disc(thumb,cy,radius+3*unit,C.accent,.14)end
  self:disc(thumb,cy,radius+unit,C.bg,.8)
  self:disc(thumb,cy,radius,c,enabled==false and .30 or .48+.52*s.slide)
  self:text(label,x+s.toggleLabelX,y,s.toggleLabelWidth,h,opt.size or 13,self:toggleColor(value,enabled),false,opt.bold,opt.face)
  if opt.showState~=false then self:text(value and 'ON' or 'OFF',x+s.toggleStateX,y,s.toggleStateWidth,h,10,c,false)end
  return value,click,hitWidth
 end
 function U:flash(id)
  local s=self:state(id);s.flashPending,s.flashFrame=self.now,self.frameSerial
 end
 function U:fieldFrame(id,x,y,w,h,enabled,active)
  local s=self:state(id)
  local flash,focusReturn=0,1
  if s.flashPending and s.flashFrame~=self.frameSerial then s.flash=s.flashPending;s.flashPending=nil end
  if s.flash then
   local age=max(0,self.now-s.flash);local q=min(1,age/.9)
   flash=.7*max(0,1-age/.045)^3+.3*(1-q)^2
   local t=min(1,max(0,(age-.65)/.25));focusReturn=t*t*(3-2*t)
   if q==1 then s.flash=nil end
  end
  self:rect(x,y,w,h,self.C.field,1)
  self:rect(x,y,w,h,enabled and self.C.edge or self.C.disabled,enabled and .7 or .25,false)
  self:rect(x+1,y+h-3,w-2,2,self.C.ice,.18+(active and enabled and .72*focusReturn or 0))
  if flash>0 then
   self:rect(x+1,y+h-3,w-2,2,self.C.red,flash)
   self:rect(x+1,y+1,w-2,h-4,self.C.red,.50*flash)
  end
  return flash
 end
 return U
end
return M
end)()

BLT.CanvasHost=(function()
local M={}
local floor,ceil,min,max=math.floor,math.ceil,math.min,math.max
local function finite(v) return type(v)=='number' and v==v and math.abs(v)<math.huge end
local function byte(v) return floor(max(0,min(1,v))*255+.5) end
local function rgba(r,g,b,a)
 return (byte(r)<<24)|(byte(g)<<16)|(byte(b)<<8)|byte(a or 1)
end
local function numberMetrics(path)
 local f=io.open(path,'rb');if not f then return end
 local ok,ascent,cap=pcall(function()
  local header=f:read(16);local base=header:sub(1,4)=='ttcf' and string.unpack('>I4',header,13) or 0
  f:seek('set',base);header=f:read(12)
  local count=string.unpack('>I2',header,5);if count<1 or count>256 then return end
  local tables={}
  for _=1,count do
   local entry=f:read(16);local tag=entry:sub(1,4)
   if tag=='hhea' or tag=='OS/2' then tables[tag]=string.unpack('>I4',entry,9) end
  end
  if not tables.hhea or not tables['OS/2'] then return end
  f:seek('set',tables.hhea);local hhea=f:read(10)
  f:seek('set',tables['OS/2']);local os2=f:read(90)
  if string.unpack('>I2',os2)<2 then return end
  local a,d=string.unpack('>i2i2',hhea,5)
  if (string.unpack('>I2',os2,63)&128)~=0 then a,d=string.unpack('>i2i2',os2,69) end
  local c=string.unpack('>i2',os2,89);local height=a-d
  if height>0 and c>0 and c<=height then return a/height,c/height end
 end)
 f:close()
 if ok then return ascent,cap end
end
function M.new(api,title,width,height,section)
 local I=dofile(api.ImGui_GetBuiltinPath()..'/imgui.lua')('0.10')
 local H={I=I,title=title,width=width,height=height,rgba=rgba,section=section}
 H.ctx=I.CreateContext(title,I.ConfigFlags_NoSavedSettings)
 local osName=api.GetOS()
 H.mac=not not (osName:match('OSX') or osName:match('macOS'))
 H.faces=osName:match('Win') and {'Yu Gothic UI','Segoe UI','Consolas'} or
  (H.mac and {'Hiragino Sans','Helvetica Neue','Menlo'} or {'sans-serif','sans-serif','monospace'})
 local numberAscent,numberCap
 function H:numberOffset(size)
  if not numberAscent then
   local path=osName:match('Win') and ((os.getenv('WINDIR') or 'C:/Windows')..'/Fonts/consolab.ttf') or
    (self.mac and '/System/Library/Fonts/Menlo.ttc' or '')
   numberAscent,numberCap=numberMetrics(path)
   if not numberAscent then
    numberAscent,numberCap=self.mac and 1901/2384 or 1521/2048,self.mac and 1493/2384 or 1307/2048
   end
  end
  local dpi=self.dpi or 1;local pixels=size*dpi
  return (pixels*.5-math.ceil(pixels*numberAscent)+math.ceil(pixels*numberCap)*.5)/dpi
 end
 local families,records={},{}
 local function register(face,bold)
  families[face]=families[face] or {};local family=families[face];local key=bold and 98 or 0
  if not family[key] then
   local font=I.CreateFont(face,bold and I.FontFlags_Bold or 0);I.Attach(H.ctx,font)
   family[key]={font=font,sizes={},retainSize=15};records[#records+1]=family[key]
  end
  return family[key]
 end
 local currentFont=register(H.faces[1],false)
 H.font=currentFont.font
 function H:fontFor(face,bold) return register(face or self.faces[1],bold).font end
 register(H.faces[1],true)
 local ctx=H.ctx;local G={mouse_x=0,mouse_y=0,mouse_cap=0,mouse_wheel=0,w=width,h=height}
 local imageCache,retiredImages={},{}
 local gradientFrame=0
 local retireEpoch,retireFrame=floor(api.time_precise()*10),0
 local function detach(image)
  if type(I.ValidatePtr)~='function' or I.ValidatePtr(ctx,'ImGui_Context*')then
   pcall(I.Detach,ctx,image)
  end
 end
 function H:attachImage(image)
  I.Attach(ctx,image);imageCache[image]=true
 end
 function H:releaseImage(image,batched)
  if self.closing or batched then retiredImages[image]=nil;imageCache[image]=nil;detach(image)
  elseif not retiredImages[image] then retiredImages[image]={frame=gradientFrame,time=api.time_precise()} end
 end
 function H:retainImages()
  if not next(imageCache) then return end
  local draw=I.GetForegroundDrawList(ctx)
  for image in pairs(imageCache) do I.DrawList_AddImage(draw,image,0,0,0,0,0,0,1,1,0) end
 end
 function H:retainResources()
  self:retainImages()
  for _,record in ipairs(records) do I.PushFont(ctx,record.font,record.retainSize);I.PopFont(ctx) end
 end
 function H:releaseRetiredImages()
  if not next(retiredImages) then return end
  if not self.closing then
   if gradientFrame-retireFrame<2 then return end
   if api.SNM_GetIntConfigVar then
    local tick=api.SNM_GetIntConfigVar('__reascript_runcnt',-1)
    if tick and tick>=0 and tick%4~=0 then return end
   end
   local epoch=floor(api.time_precise()*10)
   if epoch==retireEpoch then return end
   retireEpoch,retireFrame=epoch,gradientFrame
  end
  local now=api.time_precise()
  for image,retired in pairs(retiredImages) do
   if self.closing or gradientFrame-retired.frame>=2 and now-retired.time>=.1 then
    imageCache[image]=nil;retiredImages[image]=nil;detach(image)
   end
  end
 end
 if section and api.GetExtState then
  local x,y=tonumber(api.GetExtState(section,'window_x')),tonumber(api.GetExtState(section,'window_y'))
  if finite(x) and finite(y) then H.restoreX,H.restoreY=x,y;H.savedX,H.savedY=x,y end
 end
 local _,maxWindowSize=I.NumericLimits_Float()
 H.g=G
 local wheelRegions,wheelCount={},0
 function G.wheelRegion(x,y,w,h)
  wheelCount=wheelCount+1
  local r=wheelRegions[wheelCount]or {};wheelRegions[wheelCount]=r
  r.x,r.y,r.w,r.h=x,y,w,h
 end
 local color=0xffffffff;local fontSize=15
 G.packColor=rgba
 local lastR,lastG,lastB,lastA
 local colors,colorCount={},0
 local function packed(r,g,b,a)
  local green=colors[r]
  if not green then green={};colors[r]=green end
  local blue=green[g]
  if not blue then blue={};green[g]=blue end
  local alphas=blue[b]
  if not alphas then alphas={};blue[b]=alphas end
  local value=alphas[a]
  if value then return value end
  value=rgba(r,g,b,a);alphas[a]=value;colorCount=colorCount+1
  if colorCount>=512 then colors={};colorCount=0 end
  return value
 end
 G.packedColor=packed
 local gradientR,gradientG,gradientB,gradientRGB
 local fontCount,epoch=0,0
 local gradients,gradientSlots,gradientNext={},{},0
 local recording,gradientPixels=nil,0
 local gradientImages,gradientTrimFrame={},-60
 local function releaseGradient(entry)
  if entry.image then entry.image.owner=nil;entry.image=nil end
 end
 local function clearGradients()
  for _,entry in pairs(gradients) do releaseGradient(entry) end
  gradients,gradientSlots,gradientNext={},{},0
 end
 local function cacheGradient(entry)
  if entry.count==0 or entry.vectorOnly or not api.new_array or not I.CreateImageFromSize or (H.gradientBuilds or 0)>0 or entry.hits<2 then return end
  local dpi=entry.dpi;local ox,oy=H.originX,H.originY
  local left,top,right,bottom=math.huge,math.huge,-math.huge,-math.huge
  for i=1,entry.count do
   local r=entry.runs[i]
   left,top=min(left,floor((ox+r.x)*dpi)),min(top,floor((oy+r.y)*dpi))
   right,bottom=max(right,ceil((ox+r.x+r.w)*dpi)),max(bottom,ceil((oy+r.y+r.h)*dpi))
  end
  local w,h=right-left,bottom-top
  if w<1 or h<1 or w*h>262144 then return end
  local slot
  for _,image in ipairs(gradientImages) do
   if not H.resourceHold and not image.owner and image.frame<gradientFrame-1 and image.w>=w and image.h>=h and
    (not slot or image.w*image.h<slot.w*slot.h) then slot=image end
  end
  local iw,ih=ceil(w/16)*16,ceil(h/8)*8
  if not slot then
   if iw*ih>262144 then return end
   if (#gradientImages>=96 or gradientPixels+iw*ih>2097152) and
    gradientFrame-gradientTrimFrame>=60 and not H.resourceHold then
    gradientTrimFrame=gradientFrame
    for i=#gradientImages,1,-1 do
     local image=gradientImages[i]
     if not image.owner and image.frame<gradientFrame-1 then
      H:releaseImage(image.image,true);gradientPixels=gradientPixels-image.w*image.h;table.remove(gradientImages,i)
     end
    end
   end
   if #gradientImages>=96 or gradientPixels+iw*ih>2097152 then return end
  end
  local direct,boxes={},{}
  if entry.uncertain then
   local epsilon=1/256
   local queue={}
   local function near(v) return math.abs(v-.5-floor(v))<=epsilon end
   for i=1,entry.count do
    local r=entry.runs[i];local x,y=(ox+r.x)*dpi,(oy+r.y)*dpi
    local xx,yy=x+r.w*dpi,y+r.h*dpi
    boxes[i]={ceil(x-.5-epsilon),ceil(y-.5-epsilon),ceil(xx-.5+epsilon),ceil(yy-.5+epsilon)}
    if near(x) or near(xx) or near(y) or near(yy) then direct[i]=true;queue[#queue+1]=i end
   end
   local at=1
   while at<=#queue do
    local b=boxes[queue[at]];at=at+1
    for i,a in ipairs(boxes) do
     if not direct[i] and a[1]<b[3] and a[3]>b[1] and a[2]<b[4] and a[4]>b[2] then
      direct[i]=true;queue[#queue+1]=i
     end
    end
   end
  end
  local safe=0;for i=1,entry.count do if not direct[i] then safe=safe+1 end end
  if safe<8 then entry.vectorOnly=true;return end
  local pixels={};for i=1,w*h do pixels[i]=0 end
  for i=1,entry.count do
   if not direct[i] then
    local r=entry.runs[i];local x,y=(ox+r.x)*dpi,(oy+r.y)*dpi
    local width,height=r.w*dpi,r.h*dpi
    local x1,x2=max(left,ceil(x-.5)),min(right,ceil(x+width-.5))
    local y1,y2=max(top,ceil(y-.5)),min(bottom,ceil(y+height-.5))
    local l,rr=r.left,r.right
    local lr,lg,lb,la=(l>>24)&255,(l>>16)&255,(l>>8)&255,l&255
    local dr,dg,db,da=((rr>>24)&255)-lr,((rr>>16)&255)-lg,((rr>>8)&255)-lb,(rr&255)-la
    for px=x1,x2-1 do
     local u=(px+.5-x)/width
     local color=(floor(lr+dr*u+.5)<<24)|(floor(lg+dg*u+.5)<<16)|(floor(lb+db*u+.5)<<8)|floor(la+da*u+.5)
     for py=y1,y2-1 do pixels[(py-top)*w+px-left+1]=color end
    end
   end
  end
  if not slot then
   slot={image=I.CreateImageFromSize(iw,ih),w=iw,h=ih};H:attachImage(slot.image)
   gradientImages[#gradientImages+1]=slot;gradientPixels=gradientPixels+iw*ih
  end
  I.Image_SetPixels_Array(slot.image,0,0,w,h,api.new_array(pixels))
  slot.owner,slot.frame=entry,gradientFrame
  entry.image,entry.imageX,entry.imageY,entry.imageW,entry.imageH=slot,left/dpi-ox,top/dpi-oy,w/dpi,h/dpi
  entry.imageU,entry.imageV=w/slot.w,h/slot.h
  local vectors={}
  for i=1,entry.count do if direct[i] then vectors[#vectors+1]=entry.runs[i] end end
  entry.runs=vectors;entry.count=#vectors
  H.gradientBuilds=(H.gradientBuilds or 0)+1
 end
 local function replayGradient(entry)
  if entry.lastFrame~=gradientFrame then entry.hits=entry.hits+1;entry.lastFrame=gradientFrame end
  if not entry.image then cacheGradient(entry) end
  local ox,oy=H.originX,H.originY
  if entry.image then
   local x,y=ox+entry.imageX,oy+entry.imageY
   entry.image.frame=gradientFrame
   I.DrawList_AddImage(H.draw,entry.image.image,x,y,x+entry.imageW,y+entry.imageH,0,0,entry.imageU,entry.imageV)
  end
  for i=1,entry.count do
   local r=entry.runs[i];local x,y=ox+r.x,oy+r.y
   I.DrawList_AddRectFilledMultiColor(H.draw,x,y,x+r.w,y+r.h,r.left,r.right,r.right,r.left)
  end
 end
 function G.beginGradient(kind,x,y,w,h,...)
  local dpi=H.dpi or 1;local key=kind..':'..x..':'..y..':'..w..':'..h
  local fx,fy=(H.originX*dpi)%1,(H.originY*dpi)%1
  local entry=gradients[key];local n=select('#',...)
  local same=entry and entry.dpi==dpi and entry.fx==fx and entry.fy==fy and entry.n==n
  if same then for i=1,n do if entry.signature[i]~=select(i,...) then same=false;break end end end
  if same then replayGradient(entry);return true end
  if not entry then
   gradientNext=gradientNext%96+1
   local old=gradientSlots[gradientNext]
   if old then releaseGradient(gradients[old]);gradients[old]=nil end
   gradientSlots[gradientNext]=key
   entry={runs={},signature={}};gradients[key]=entry
  end
  releaseGradient(entry)
  entry.dpi,entry.fx,entry.fy,entry.n,entry.count,entry.hits,entry.lastFrame=dpi,fx,fy,n,0,0,nil
  entry.columns={};entry.edges={};entry.uncertain=false;entry.vectorOnly=nil
  for i=1,n do entry.signature[i]=select(i,...) end
  recording=entry
  return false
 end
 function G.endGradient()
  local entry=recording;recording=nil;entry.columns=nil
  if next(entry.edges) then entry.uncertain=true end
  entry.edges=nil
  for i=#entry.runs,entry.count+1,-1 do entry.runs[i]=nil end
  replayGradient(entry)
 end
 local function gradientEdge(entry,first,last,at,distance,color,side)
  if distance<=1e-7 or distance>1/256 then return end
  local key=first..':'..last..':'..floor(at*256+.5)
  local previous=entry.edges[key]
  if previous and previous.color==color and previous.side~=side then entry.edges[key]=nil
  else entry.edges[key]={color=color,side=side} end
 end
 local function horizontalGradient(x,y,w,h,left,right)
  if ((left|right)&255)==0 then return end
  local dpi=H.dpi or 1;local xx,yy=H.originX+x,H.originY+y
  local top,bottom=yy*dpi-.5,(yy+h)*dpi-.5
  local first,last=ceil(top),ceil(bottom)
  local epsilon=1/256
  if ceil(top-epsilon)>=ceil(bottom+epsilon) or ceil(xx*dpi-.5-epsilon)>=ceil((xx+w)*dpi-.5+epsilon) then return end
  if not recording then
   I.DrawList_AddRectFilledMultiColor(H.draw,xx,yy,xx+w,yy+h,left,right,right,left)
   return
  end
  local stable=math.abs(top-floor(top+.5))>epsilon and math.abs(bottom-floor(bottom+.5))>epsilon
  local entry=recording;local previous=entry.columns[x]
  if not stable then entry.uncertain=true end
  local x1,x2=xx*dpi-.5,(xx+w)*dpi-.5
  local d1,d2=math.abs(x1-floor(x1+.5)),math.abs(x2-floor(x2+.5))
  gradientEdge(entry,first,last,x1,d1,left,1);gradientEdge(entry,first,last,x2,d2,right,2)
  if stable and previous and previous.last==first and previous.w==w and previous.left==left and previous.right==right then
   previous.last=last;previous.h=(last-previous.first)/dpi
   return
  end
  entry.count=entry.count+1;local r=entry.runs[entry.count] or {};entry.runs[entry.count]=r
  r.x,r.w,r.left,r.right=x,w,left,right
  r.y,r.h=stable and first/dpi-H.originY or y,stable and (last-first)/dpi or h
  r.first,r.last=first,last;entry.columns[x]=stable and r or nil
 end
 local keys={{I.Key_Tab,9},{I.Key_Enter,13},{I.Key_KeypadEnter,13},{I.Key_Space,32}}
 function H:bindShortcuts(escape)
  local list={}
  local function add(name,code)list[#list+1]={I['Key_'..name],code}end
  if escape~=false then add('Escape',27)end
  for _,p in ipairs({{'Backspace',8},{'Delete',6579564},{'Insert',6909555},{'Home',1752132965},{'End',6647396},
   {'LeftArrow',1818584692},{'RightArrow',1919379572},{'UpArrow',30064},{'DownArrow',1685026670},
   {'PageUp',1885828464},{'PageDown',1885824110},{'Minus',45},{'Equal',61},{'LeftBracket',91},
   {'RightBracket',93},{'Backslash',92},{'Semicolon',59},{'Apostrophe',39},{'GraveAccent',96},
   {'Comma',44},{'Period',46},{'Slash',47},{'KeypadDecimal',46},{'KeypadDivide',47},
   {'KeypadMultiply',42},{'KeypadSubtract',45},{'KeypadAdd',43},{'KeypadEqual',61}})do add(p[1],p[2])end
  for code=65,90 do add(string.char(code),code+32)end
  for code=48,57 do add(string.char(code),code);add('Keypad'..(code-48),code)end
  for index=1,12 do
   local code=0;for c in ('f'..index):gmatch('.')do code=(code<<8)|c:byte()end
   add('F'..index,code)
  end
  self.extraKeys=list
 end
 local function xy(x,y) return H.originX+x,H.originY+y end
 function G.set(r,g,b,a)
  a=a or 1
  if r~=lastR or g~=lastG or b~=lastB or a~=lastA then
   color=packed(r,g,b,a);lastR,lastG,lastB,lastA=r,g,b,a
  end
 end
 function G.rect(x,y,w,h,filled)
  if w<=0 or h<=0 or (color&255)==0 then return end
  local xx,yy=xy(x,y)
  if filled==0 then I.DrawList_AddRect(H.draw,xx+.5,yy+.5,xx+w-.5,yy+h-.5,color)
  else I.DrawList_AddRectFilled(H.draw,xx,yy,xx+w,yy+h,color) end
 end
 function G.line(x,y,xx,yy,aa,width)
  if (color&255)==0 then return end
  local a,b=xy(x,y);local c,d=xy(xx,yy);I.DrawList_AddLine(H.draw,a+.5,b+.5,c+.5,d+.5,color,width or 1)
 end
 function G.bars(x,y,spacing,width,heights,scale)
  if (color&255)==0 then return end
  local dpi=H.dpi or 1;local step=max(1,floor(spacing*scale*dpi+.5))/dpi
  local cx,cy=xy(x,y)
  local left=(floor((cx-(#heights-1)*step*.5)*dpi)+.5)/dpi
  for i,h in ipairs(heights) do
   local xx=left+(i-1)*step;local half=h*scale*.5
   I.DrawList_AddLine(H.draw,xx,cy-half,xx,cy+half,color,width*scale)
  end
 end
 function G.circle(x,y,r)
  if (color&255)==0 then return end
  local xx,yy=xy(x,y);I.DrawList_AddCircleFilled(H.draw,xx,yy,r,color)
 end
 local polygons,polygonSlot={},0
 function G.polygon(points,concave)
  if api.new_array then
   local entry
   for _,candidate in ipairs(polygons) do
    local same=candidate.count==#points
    if same then for i,p in ipairs(points) do if candidate.coords[i*2-1]~=H.originX+p[1] or candidate.coords[i*2]~=H.originY+p[2] then same=false;break end end end
    if same then entry=candidate;break end
   end
   if not entry then
    entry={count=#points,coords={}}
    for i,p in ipairs(points) do entry.coords[i*2-1],entry.coords[i*2]=H.originX+p[1],H.originY+p[2] end
    entry.array=api.new_array(entry.coords)
    polygonSlot=polygonSlot%32+1;polygons[polygonSlot]=entry
   end
   if concave then I.DrawList_AddConcavePolyFilled(H.draw,entry.array,color) else I.DrawList_AddConvexPolyFilled(H.draw,entry.array,color) end
   return
  end
  I.DrawList_PathClear(H.draw)
  for _,p in ipairs(points) do local x,y=xy(p[1],p[2]);I.DrawList_PathLineTo(H.draw,x,y) end
  if concave then I.DrawList_PathFillConcave(H.draw,color) else I.DrawList_PathFillConvex(H.draw,color) end
 end
 function G.gradrect(x,y,w,h,r,g,b,a,rx,gx,bx,ax,ry,gy,by,ay)
  if ry and (ry~=0 or gy~=0 or by~=0 or ay~=0) then
   local xx,yy=xy(x,y)
   I.DrawList_AddRectFilledMultiColor(H.draw,xx,yy,xx+w,yy+h,rgba(r,g,b,a),
    rgba(r+rx*w,g+gx*w,b+bx*w,a+ax*w),rgba(r+rx*w+ry*h,g+gx*w+gy*h,b+bx*w+by*h,a+ax*w+ay*h),
    rgba(r+ry*h,g+gy*h,b+by*h,a+ay*h));return
  end
  local left,right
  if rx==0 and gx==0 and bx==0 then
   if r~=gradientR or g~=gradientG or b~=gradientB then
    gradientRGB=rgba(r,g,b,0);gradientR,gradientG,gradientB=r,g,b
   end
   left=gradientRGB|byte(a);right=gradientRGB|byte(a+ax*w)
  else left=rgba(r,g,b,a);right=rgba(r+rx*w,g+gx*w,b+bx*w,a+ax*w) end
  horizontalGradient(x,y,w,h,left,right)
 end
 function G.gradcolors(x,y,w,h,left,right)
  horizontalGradient(x,y,w,h,left,right)
 end
 function G.setfont(_,face,size,flags)
  fontSize=size
  currentFont=register(face or H.faces[1],flags==98)
  currentFont.retainSize=size
 end
 local function measure(text)
  local metrics=currentFont.sizes[fontSize]
  if not metrics or metrics.frame~=epoch then
   I.PushFont(ctx,currentFont.font,fontSize);local size=I.GetFontSize(ctx);I.PopFont(ctx)
   if not metrics or metrics.size~=size then
    if not metrics then
     fontCount=fontCount+1
     if fontCount>32 then for _,record in ipairs(records) do record.sizes={} end;fontCount=1 end
    end
    metrics={size=size,strings={},count=0};currentFont.sizes[fontSize]=metrics
   end
   metrics.frame=epoch
  end
  local measured=metrics.strings[text]
  if not measured then
   if metrics.count==128 then metrics.strings={};metrics.count=0 end
   I.PushFont(ctx,currentFont.font,fontSize);local w,h=I.CalcTextSize(ctx,text);I.PopFont(ctx)
   measured={w,h};metrics.strings[text]=measured;metrics.count=metrics.count+1
  end
  return measured[1],measured[2],metrics.size
 end
 function G.measurestr(text) return measure(tostring(text)) end
 function G.textMetrics(text)
  local w,h,size=measure(text);return w,h,size,currentFont.font
 end
 function G.numberOffset(size) return H:numberOffset(size or fontSize) end
 function G.drawstr(text,flags,right,bottom,opticalCenter)
  text=tostring(text);flags=flags or 0;right=right or G.w;bottom=bottom or G.h
  local w,h,renderedSize=measure(text)
  local x,y=G.x,G.y
  local left,top=xy(x,y);local r,b=xy(right,bottom)
  if (flags&2)~=0 then x=right-w
  elseif (flags&1)~=0 then x=x+(right-x-w)/2 end
  if (flags&4)~=0 then y=y+(bottom-y-h)/2 end
  x,y=xy(x,y)
  if opticalCenter then
   local dpi=H.dpi or 1;y=floor((y+H:numberOffset(renderedSize))*dpi+.5)/dpi
  else y=floor(y) end
  x=floor(x)
  I.DrawList_AddTextEx(H.draw,currentFont.font,renderedSize,x,y,color,text,0,floor(left),floor(top),math.ceil(r),math.ceil(b))
 end
 function H:place(x,y,w,h)
  if not api.my_getViewport then return x,y end
  local nx,ny=I.PointConvertNative(ctx,x,y,true)
  local nr,nb=I.PointConvertNative(ctx,x+min(120,w),y+min(26,h),true)
  local al,at,ar,ab=api.my_getViewport(0,0,0,0,floor(min(nx,nr)),floor(min(ny,nb)),math.ceil(max(nx,nr)),math.ceil(max(ny,nb)),true)
  if not (finite(al) and finite(at) and finite(ar) and finite(ab)) or ar<=al or at==ab then return x,y end
  al,at=I.PointConvertNative(ctx,al,at);ar,ab=I.PointConvertNative(ctx,ar,ab)
  al,ar=min(al,ar),max(al,ar);at,ab=min(at,ab),max(at,ab)
  if x>=al and x+min(120,w,ar-al)<=ar and y>=at and y+min(26,h,ab-at)<=ab then return x,y end
  local mx,my=min(8,max(0,(ar-al-w)*.5)),min(8,max(0,(ab-at-h)*.5))
  return floor(max(al+mx,min(x,ar-w-mx))+.5),floor(max(at+my,min(y,ab-h-my))+.5)
 end
 function H:savePosition()
  if not self.section or not api.SetExtState or not self.nativeX then return end
  if self.nativeX~=self.savedX then api.SetExtState(self.section,'window_x',tostring(self.nativeX),true);self.savedX=self.nativeX end
  if self.nativeY~=self.savedY then api.SetExtState(self.section,'window_y',tostring(self.nativeY),true);self.savedY=self.nativeY end
  if self.persistSize then
   if G.w~=self.savedWidth then api.SetExtState(self.section,'window_w',tostring(G.w),true);self.savedWidth=G.w end
   if G.h~=self.savedHeight then api.SetExtState(self.section,'window_h',tostring(G.h),true);self.savedHeight=G.h end
  end
 end
 function H:close()
  self:savePosition()
  self.closing=true;self.imageHold=nil;self.resourceHold=nil
  self:releaseRetiredImages()
  clearGradients()
  for _,image in ipairs(gradientImages) do self:releaseImage(image.image) end
  gradientImages={};gradientPixels=0
 end
 local function invalidateExposed(hwnd,l,t,r,b,nl,nt,nr,nb)
  if not(api.JS_Window_GetParent and api.JS_Window_ScreenToClient and api.JS_Window_InvalidateRect)then return end
  l,r=min(l,r),max(l,r);t,b=min(t,b),max(t,b)
  nl,nr=min(nl,nr),max(nl,nr);nt,nb=min(nt,nb),max(nt,nb)
  if nl<=l and nt<=t and nr>=r and nb>=b then return end
  local parent=api.JS_Window_GetParent(hwnd)
  if not parent or parent==0 then return end
  if api.JS_Window_GetClientRect then
   for _=1,8 do
    local ok,pl,pt,pr,pb=api.JS_Window_GetClientRect(parent)
    if ok and min(pl,pr)<=l and min(pt,pb)<=t and max(pl,pr)>=r and max(pt,pb)>=b then break end
    local nextParent=api.JS_Window_GetParent(parent)
    if not nextParent or nextParent==0 or nextParent==parent then break end
    parent=nextParent
   end
  end
  local function paint(x,y,xx,yy)
   if xx<=x or yy<=y then return end
   x,y=api.JS_Window_ScreenToClient(parent,x,y);xx,yy=api.JS_Window_ScreenToClient(parent,xx,yy)
   api.JS_Window_InvalidateRect(parent,min(x,xx),min(y,yy),max(x,xx),max(y,yy),false)
  end
  local il,it,ir,ib=max(l,nl),max(t,nt),min(r,nr),min(b,nb)
  if il>=ir or it>=ib then paint(l,t,r,b)
  else paint(l,t,r,it);paint(l,ib,r,b);paint(l,it,il,ib);paint(ir,it,r,ib)end
 end
 function H:idle(now)
  if self.shown==false or (self.visibilitySettle or 0)>0 then return false end
  if next(retiredImages) and not self.imageHold and not self.resourceHold then self:releaseRetiredImages() end
  if not (api.GetMousePosition and api.JS_Mouse_GetState and api.JS_VKeys_GetDown) then return false end
  local x,y=api.GetMousePosition();local cap=api.JS_Mouse_GetState(63)
  if self.windowGesture then self.idleWake=true;return false end
  local held=(cap&1)~=0
  if not self.section and(held or self.resizeWindow)then
   local hwnd=self.nativeWindow
   if not hwnd or not api.JS_Window_GetRect then self.resizeWindow=nil;self.idleWake=true;return false end
   local ok,l,t,r,b=api.JS_Window_GetRect(hwnd)
   if not ok then self.nativeWindow=nil;self.resizeWindow=nil;self.idleWake=true;return false end
   local sameWindow=self.resizeWindow==hwnd
   local changed=not sameWindow or self.resizeLeft~=l or self.resizeTop~=t or self.resizeRight~=r or self.resizeBottom~=b
   if changed and self.nativeLeft then
    invalidateExposed(hwnd,sameWindow and self.resizeLeft or self.nativeLeft,sameWindow and self.resizeTop or self.nativeTop,
     sameWindow and self.resizeRight or self.nativeRight,sameWindow and self.resizeBottom or self.nativeBottom,l,t,r,b)
   end
   self.resizeWindow,self.resizeLeft,self.resizeTop,self.resizeRight,self.resizeBottom=held and hwnd or nil,l,t,r,b
   if changed then self.idleWake=true;return false end
  else self.resizeWindow=nil end
  local keys=api.JS_VKeys_GetDown(-.25)
  if type(keys)~='string' or #keys<255 then return false end
  local margin=8*(self.mac and 1 or self.dpi or 1)
  local inside=self.nativeLeft and x>=self.nativeLeft-margin and x<self.nativeRight+margin and y>=self.nativeTop-margin and y<self.nativeBottom+margin
  if inside and api.JS_Window_FromPoint then
   local window=api.JS_Window_FromPoint(x,y)
   if window~=self.nativeWindow and window~=self.probedWindow then
    self.probedWindow=window;self.nativeProbe=true;return false
   end
   inside=window~=nil and window~=0 and self.nativeWindow~=nil and window==self.nativeWindow
  end
  local wasInside=self.idleInside
  if wasInside==nil then wasInside=self.hovered end
  local recent=self.lastIdle and now-self.lastIdle<1
  local pointer=(inside or wasInside) and recent and (x~=self.idleX or y~=self.idleY or cap~=self.idleCap)
  local keyDown=keys:find('\1',1,true)~=nil
  local keyProbe=keyDown and keys~=self.idleKeys
  local wheelTarget=false
  if inside and self.hovered then
   for i=1,wheelCount do
    local r=wheelRegions[i]
    if G.mouse_x>=r.x and G.mouse_x<r.x+r.w and G.mouse_y>=r.y and G.mouse_y<r.y+r.h then wheelTarget=true;break end
   end
  end
  local activity=pointer or inside~=wasInside or self.focused and keyDown or wheelTarget
  self.idleX,self.idleY,self.idleCap,self.lastIdle=x,y,cap,now
  self.idleInside,self.idleKeys=inside,keys
  if activity then self.idleWake=true;return false end
  if keyProbe then return false end
  if now>=(self.nextIdleFrame or 0) then self.nextIdleFrame=now+(self.focused and .25 or 1);return false end
  I.GetConfigVar(ctx,I.ConfigVar_Flags)
  return true
 end
 function H:begin()
  wheelCount=0
  local previouslyShown=self.shown
  self.gradientBuilds=0
  gradientFrame=gradientFrame+1
  local now=api.time_precise()
  I.SetNextWindowSize(ctx,self.width,self.height,self.requestReset and I.Cond_Always or I.Cond_FirstUseEver)
  self.requestReset=nil
  I.SetNextWindowSizeConstraints(ctx,self.minWidth or 640,self.minHeight or 620,maxWindowSize,maxWindowSize)
  if self.drag then
   if I.IsMouseDown(ctx,0) then
    local mx,my=I.GetMousePos(ctx);I.SetNextWindowPos(ctx,mx-self.drag.x,my-self.drag.y)
   else self.drag=nil end
  end
  if self.section and not self.drag and (self.restoreX or now>=(self.nextPlacement or 0)) then
   local x,y=self.windowX,self.windowY
   if self.restoreX then x,y=I.PointConvertNative(ctx,self.restoreX,self.restoreY);self.restoreX,self.restoreY=nil,nil end
   if x then
    local px,py=self:place(x,y,G.w,G.h)
    if px~=self.windowX or py~=self.windowY then I.SetNextWindowPos(ctx,px,py) end
   end
   self.nextPlacement=now+.5
  end
  I.PushStyleVar(ctx,I.StyleVar_WindowPadding,0,0)
  I.PushStyleVar(ctx,I.StyleVar_WindowRounding,0);I.PushStyleVar(ctx,I.StyleVar_WindowBorderSize,0)
  I.PushStyleColor(ctx,I.Col_WindowBg,0x05080eff)
  local focusFlag=self.seenWindow and I.WindowFlags_NoFocusOnAppearing or 0
  local shown,open=I.Begin(ctx,self.title,true,I.WindowFlags_NoScrollbar|I.WindowFlags_NoScrollWithMouse|I.WindowFlags_NoTitleBar|I.WindowFlags_NoMove|focusFlag)
  I.PopStyleColor(ctx);I.PopStyleVar(ctx,3)
  if gradientFrame%60==1 then self:retainResources() end
  self.shown=shown;self.open=open
  if shown and previouslyShown==false then self.visibilitySettle=4 end
  self.resourceHold=self.imageHold or not shown or (self.visibilitySettle or 0)>0
  self.windowBegun=shown
  if not shown then return false end
  self.seenWindow=true
  local dpi=I.GetWindowDpiScale(ctx)
  if self.section then
   local x,y=I.GetWindowPos(ctx)
   if x~=self.windowX or y~=self.windowY or dpi~=self.dpi then
    self.windowX,self.windowY=x,y
    self.nativeX,self.nativeY=I.PointConvertNative(ctx,x,y,true)
   end
   if not self.drag and now>=(self.nextSave or 0) then self:savePosition();self.nextSave=now+.25 end
  end
  if dpi~=self.dpi then self.dpi=dpi;epoch=epoch+1 end
  G.ext_retina=dpi
  self.originX,self.originY=I.GetCursorScreenPos(ctx)
  local w,h=I.GetContentRegionAvail(ctx)
  if w~=G.w or h~=G.h or dpi~=self.gradientDpi then clearGradients();self.gradientDpi=dpi end
  G.w,G.h=w,h;self.draw=I.GetWindowDrawList(ctx)
  if self.boundsX~=self.originX or self.boundsY~=self.originY or self.boundsW~=w or self.boundsH~=h or self.boundsDpi~=dpi then
   local l,t=I.PointConvertNative(ctx,self.originX,self.originY,true)
   local r,b=I.PointConvertNative(ctx,self.originX+w,self.originY+h,true)
   self.nativeLeft,self.nativeRight=min(l,r),max(l,r);self.nativeTop,self.nativeBottom=min(t,b),max(t,b)
   self.boundsX,self.boundsY,self.boundsW,self.boundsH,self.boundsDpi=self.originX,self.originY,w,h,dpi
  end
  local mx,my=I.GetMousePos(ctx);G.mouse_x=mx-self.originX;G.mouse_y=my-self.originY
  local hovered=I.IsWindowHovered(ctx)
  self.hovered,self.idleInside=hovered,hovered
  if hovered and api.JS_Window_FromPoint and (not self.nativeWindow or self.nativeProbe) then
   local x,y=api.GetMousePosition();self.nativeWindow=api.JS_Window_FromPoint(x,y)
  end
  self.nativeProbe=nil
  if not hovered and not self.pointerCapture then G.mouse_x=-10000;G.mouse_y=-10000 end
  G.mouse_cap=I.IsMouseDown(ctx,0) and 1 or 0
  if self.captureRight and I.IsMouseDown(ctx,1) then G.mouse_cap=G.mouse_cap|2 end
  if self.windowGesture and api.JS_Mouse_GetState and(api.JS_Mouse_GetState(1)&1)==0 then
   G.mouse_cap=G.mouse_cap&~1;self.windowGesture=nil
  end
  local mods=I.GetKeyMods(ctx)
  if (mods&I.Mod_Ctrl)~=0 then G.mouse_cap=G.mouse_cap|4 end
  if (mods&I.Mod_Shift)~=0 then G.mouse_cap=G.mouse_cap|8 end
  if (mods&I.Mod_Alt)~=0 then G.mouse_cap=G.mouse_cap|16 end
  if (mods&I.Mod_Super)~=0 then G.mouse_cap=G.mouse_cap|32 end
  G.mouse_wheel=hovered and (I.GetMouseWheel(ctx)*120) or 0
  self.key=0
  self.focused=I.IsWindowFocused(ctx)
  if self.focused then
   for _,pair in ipairs(keys) do
    if I.IsKeyPressed(ctx,pair[1],false) then self.key=pair[2];break end
   end
   if self.key==0 and self.extraKeys then
    for _,pair in ipairs(self.extraKeys) do
     if I.IsKeyPressed(ctx,pair[1],false) then self.key=pair[2];break end
    end
   end
  end
  return true
 end
 function H:finish()
  if self.resourceHold then self:retainImages() end
  if self.windowBegun then
   self.windowBegun=false
   I.SetCursorScreenPos(ctx,self.originX,self.originY);I.Dummy(ctx,G.w,G.h);I.End(ctx)
  end
  if self.shown then
   if (self.visibilitySettle or 0)>0 then self.visibilitySettle=self.visibilitySettle-1 end
   if not self.imageHold and (self.visibilitySettle or 0)==0 then self:releaseRetiredImages() end
  end
  return self.open and not self.requestClose
 end
 return H
end
return M
end)()

BLT.TextInput=(function()
local M={}
local floor,min,max=math.floor,math.min,math.max
function M.new(host,ui,reference)
 local T={pending={},items={},metrics={{},{}},metricCount=0};local I,ctx=host.I,host.ctx
 local function color(c,a) return host.rgba(c[1],c[2],c[3],a) end
 function T:fontMetrics(b)
  if not reference or b.calibrate==false then return end
  local kind=b.number and 2 or 1;local size=max(8,b.size)
  local key=b.face and b.face..':'..tostring(b.bold)..':'..kind or kind
  local group=self.metrics[key];if not group then group={};self.metrics[key]=group end
  local cached=group[size];if cached then return cached end
  if self.metricCount>=32 then self.metrics={{},{}};self.metricCount=0;group={};self.metrics[key]=group end
  local sample=kind==1 and 'あいうえお漢字ABC012345' or '0123456789.-'
  reference:setfont(1,b.face or host.faces[1],size,b.bold and 98 or 0)
  local width,height=reference:measurestr(sample)
  I.PushFont(ctx,host:fontFor(b.face,b.bold),size);local measured=I.CalcTextSize(ctx,sample);I.PopFont(ctx)
  local calibrated=min(96,max(1,measured>0 and size*width/measured*1.04 or size*1.04))
  cached={size=calibrated,height=height};group[size]=cached;self.metricCount=self.metricCount+1
  return cached
 end
 function T:close(cancel,reason)
  local e=self.edit;self.edit=nil
  if e and not cancel then
   e.done(e.text)
   if self.onCommit then self.onCommit(e.id,e.text,reason or'blur')end
  end
 end
 function T:open(id,text,done)
  if self.edit then self:close(false) end
  self.edit={id=id,text=tostring(text),done=done,frames=0}
 end
 function T:queue(id,value,bounds,enabled)
  if enabled~=false and bounds.number then local b=bounds.hit or bounds;host.g.wheelRegion(b.x,b.y,b.w,b.h)end
  local item=self.items[id]
  if not item then item={id=id,label='##blt_input_'..id};self.items[id]=item end
  item.value,item.bounds,item.enabled=tostring(value),bounds,enabled~=false
  self.pending[#self.pending+1]=item
 end
 function T:idle(item)
  local b=item.bounds;local dpi=host.dpi or 1;local p=item.layout
  if not p or p.text~=item.value or p.dpi~=dpi or p.bx~=b.x or p.by~=b.y or p.bw~=b.w or p.bh~=b.h or
   p.requested~=b.size or p.face~=b.face or p.bold~=b.bold or p.align~=b.align or
   p.calibrate~=b.calibrate or p.number~=b.number or p.optical~=b.opticalCenter then
   local metrics=self:fontMetrics(b);local font=host:fontFor(b.face,b.bold)
   I.PushFont(ctx,font,metrics and metrics.size or max(8,floor(b.size+.5)))
   local height,size=I.GetTextLineHeight(ctx),I.GetFontSize(ctx)
   local offset=b.align=='right' and max(0,b.w-I.CalcTextSize(ctx,item.value)-2) or 0
   I.PopFont(ctx)
   local y1,y2,padY=0,0,0
   if metrics then y1,y2=max(0,(b.h-metrics.height)/2),max(0,(metrics.height-height)/2)
   else padY=max(0,floor((b.h-height)/2)) end
   p=p or {};item.layout=p
   p.text,p.dpi,p.bx,p.by,p.bw,p.bh=item.value,dpi,b.x,b.y,b.w,b.h
   p.requested,p.face,p.bold,p.align,p.calibrate,p.number,p.optical=b.size,b.face,b.bold,b.align,b.calibrate,b.number,b.opticalCenter
   p.font,p.size,p.offsetX,p.w,p.h,p.padY=font,size,offset,b.w-offset,height+2*padY,padY
   p.y1,p.y2,p.center,p.numberOffset=y1,y2,(b.h-height)/2,b.opticalCenter and host:numberOffset(size) or 0
  end
  if item.value=='' then return end
  local x=floor(host.originX+p.bx+p.offsetX)
  local y=floor(host.originY+p.by+p.y1+p.y2)
  if p.optical then y=floor((host.originY+p.by+p.center-p.padY+p.numberOffset)*dpi+.5)/dpi end
  I.DrawList_AddTextEx(host.draw,p.font,p.size,x,y+p.padY,item.enabled and self.textColor or self.disabledColor,item.value,0,x,y,x+p.w,y+p.h)
 end
 local prefixKeys={'cursor','first','last'}
 function T:caretFunction()
  if not self.caret then
   self.caret=I.CreateFunctionFromEEL([[
    restore ? (CursorPos=caret;SelectionStart=caret;SelectionEnd=caret;restore=0;);
    pointer ? (CursorPos=min(strlen(#Buf),hit);SelectionStart=min(strlen(#Buf),anchor);SelectionEnd=CursorPos;);
    cursor=CursorPos;first=SelectionStart;last=SelectionEnd;strcpy(#value,#Buf);valid=1;
   ]])
   I.Attach(ctx,self.caret)
  end
  return self.caret
 end
 local function textHit(text,pixel)
  local lo,hi=0,utf8.len(text) or #text
  while lo<hi do
   local mid=floor((lo+hi+1)/2);local at=(utf8.offset(text,mid+1) or #text+1)-1
   if I.CalcTextSize(ctx,text:sub(1,at))<=pixel then lo=mid else hi=mid-1 end
  end
  local at=(utf8.offset(text,lo+1) or #text+1)-1
  if at<#text then
   local nextAt=(utf8.offset(text,lo+2) or #text+1)-1
   local a,b=I.CalcTextSize(ctx,text:sub(1,at)),I.CalcTextSize(ctx,text:sub(1,nextAt))
   if pixel>(a+b)/2 then at=nextAt end
  end
  return at
 end
 function T:aligned(e,item,x,y,width,height,font,size)
  local text=e.text;local p=e.render or {};e.render=p
  local cursor=min(#text,max(0,e.cursor or #text));local first=min(#text,max(0,e.first or cursor));local last=min(#text,max(0,e.last or cursor))
  if p.text~=text or p.size~=size or p.font~=font then
   p.text,p.size,p.font=text,size,font;p.width=I.CalcTextSize(ctx,text);p.cursor,p.first,p.last=nil,nil,nil
  end
  for _,key in ipairs(prefixKeys) do
   local at=key=='cursor' and cursor or key=='first' and first or last
   if p[key]~=at then p[key],p[key..'Width']=at,I.CalcTextSize(ctx,text:sub(1,at)) end
  end
  local available=max(1,width-2);local scroll=min(e.scroll or 0,max(0,p.width-available))
  if p.width>available then
   if p.cursorWidth<scroll then scroll=p.cursorWidth elseif p.cursorWidth>scroll+available then scroll=p.cursorWidth-available end
  else scroll=0 end
  e.scroll=scroll
  local base=host.originX+item.bounds.x
  local px=floor(base+max(0,width-p.width-2)-scroll);e.textX=px
  local ink=item.enabled and self.textColor or self.disabledColor
  I.DrawList_PushClipRect(host.draw,x,y,base+width,y+height,true)
  if e.active and first~=last then
   I.DrawList_AddRectFilled(host.draw,px+min(p.firstWidth,p.lastWidth),y,px+max(p.firstWidth,p.lastWidth),y+height,self.selectionColor)
  end
  if text~='' then I.DrawList_AddTextEx(host.draw,font,size,px,y,ink,text,0,x,y,base+width,y+height) end
  local now=ui.now or 0
  if e.blinkText~=text or e.blinkCursor~=cursor or e.blinkFirst~=first or e.blinkLast~=last or I.IsMouseClicked(ctx,0) then
   e.blinkText,e.blinkCursor,e.blinkFirst,e.blinkLast,e.blinkAt=text,cursor,first,last,now
  end
  if e.active and (now-(e.blinkAt or now))%1.2<.8 then
   local cx=px+p.cursorWidth;I.DrawList_AddLine(host.draw,cx,y,cx,y+height,ink,1)
  end
  I.DrawList_PopClipRect(host.draw)
 end
 function T:draw(item)
  local e=self.edit and self.edit.id==item.id and self.edit or nil
  if not e then self:idle(item);return end
  local b=item.bounds
  local metrics=self:fontMetrics(b)
  local x,y=floor(host.originX+b.x),floor(host.originY+b.y)
  local font=host:fontFor(b.face,b.bold)
  I.PushFont(ctx,font,metrics and metrics.size or max(8,floor(b.size+.5)))
  local width=b.w
  local height=I.GetTextLineHeight(ctx);local padY=0
  if metrics then
   y=floor(host.originY+b.y+max(0,(b.h-metrics.height)/2)+max(0,(metrics.height-height)/2))
  else padY=max(0,floor((b.h-height)/2)) end
  if b.opticalCenter then
   local dpi=host.dpi or 1
   local offset=host:numberOffset(I.GetFontSize(ctx))
   y=floor((host.originY+b.y+(b.h-height)/2-padY+offset)*dpi+.5)/dpi
  end
  local aligned=b.align=='right';local callback;local padX=0
  if aligned then
   callback=self:caretFunction();I.Function_SetValue(callback,'valid',0);I.Function_SetValue(callback,'pointer',0)
   local measured=e.render and e.render.text==e.text and e.render.size==I.GetFontSize(ctx) and e.render.width or I.CalcTextSize(ctx,e.text)
   padX=max(0,width-measured-2)
   local down=I.IsMouseDown(ctx,0)
   if not down then e.dragAnchor,e.dragAll=nil,nil end
   if e.active and down and ((e.scroll or 0)>0 or e.dragAnchor) then
    local mx,my=I.GetMousePos(ctx)
    local pressed=I.IsMouseClicked(ctx,0) and mx>=x and mx<x+width and my>=y and my<y+height+2*padY
    local hit=textHit(e.text,mx-(e.textX or x))
    if pressed then
     e.dragAnchor=(I.GetKeyMods(ctx)&I.Mod_Shift)~=0 and (e.first~=e.last and e.first or e.cursor or 0) or hit
     e.dragAll=I.IsMouseDoubleClicked(ctx,0)
    end
    if down and e.dragAnchor then
     I.Function_SetValue(callback,'pointer',1);I.Function_SetValue(callback,'hit',e.dragAll and #e.text or hit);I.Function_SetValue(callback,'anchor',e.dragAll and 0 or e.dragAnchor)
    end
   end
   I.PushStyleColor(ctx,I.Col_InputTextCursor,0);I.PushStyleColor(ctx,I.Col_TextSelectedBg,0)
  end
  I.SetCursorScreenPos(ctx,x,y)
  I.PushStyleVar(ctx,I.StyleVar_FramePadding,padX,padY)
  I.PushStyleColor(ctx,I.Col_Text,aligned and 0 or item.enabled and self.textColor or self.disabledColor)
  I.BeginDisabled(ctx,not item.enabled);I.SetNextItemWidth(ctx,width)
  if e.frames==0 then I.SetKeyboardFocusHere(ctx) end
  local flags=I.InputTextFlags_AutoSelectAll
  if self.onCommit then flags=flags|I.InputTextFlags_EnterReturnsTrue end
  if aligned then flags=flags|I.InputTextFlags_CallbackAlways|I.InputTextFlags_NoHorizontalScroll end
  local accepted,text=I.InputText(ctx,item.label,e.text,flags,callback)
  e.text=text;e.active=I.IsItemActive(ctx)
  if callback and I.Function_GetValue(callback,'valid')~=0 then
   e.text=I.Function_GetValue_String(callback,'#value')
   e.cursor,e.first,e.last=I.Function_GetValue(callback,'cursor'),I.Function_GetValue(callback,'first'),I.Function_GetValue(callback,'last')
  end
  local deactivated=I.IsItemDeactivated(ctx)
  local cancel=deactivated and I.IsKeyPressed(ctx,I.Key_Escape,false)
  local focusLost=not I.IsWindowFocused(ctx);local outside
  if I.IsMouseClicked(ctx,0) or I.IsMouseClicked(ctx,1) then
   local mx,my=I.GetMousePos(ctx);local hit=b.hit or b
   local left,top=host.originX+hit.x,host.originY+hit.y
   outside=mx<left or mx>=left+hit.w or my<top or my>=top+hit.h
  end
  if aligned then self:aligned(e,item,x,y+padY,width,height,font,I.GetFontSize(ctx)) end
  I.EndDisabled(ctx);I.PopStyleColor(ctx,aligned and 3 or 1);I.PopStyleVar(ctx);I.PopFont(ctx)
  e.frames=e.frames+1
  if cancel then self:close(true)
  elseif self.onCommit and accepted and e.frames>1 then self:close(false,'enter')
  elseif e.frames>1 and (deactivated or outside or focusLost) then self:close(false) end
 end
 function T:frame()
  local list=self.pending
  if #list==0 then return end
  if reference then
   local dpi=host.dpi or I.GetWindowDpiScale(ctx)
   if self.metricDpi~=dpi then self.metrics={{},{}};self.metricCount=0;self.metricDpi=dpi end
  end
  local C=ui.C
  self.textColor,self.disabledColor=color(C.text),color(C.disabled)
  if not self.edit then
   for _,item in ipairs(list) do self:idle(item) end
   for i=#list,1,-1 do list[i]=nil end
   return
  end
  self.selectionColor=color(C.accent,.65)
  I.PushStyleVar(ctx,I.StyleVar_FrameRounding,0);I.PushStyleVar(ctx,I.StyleVar_FrameBorderSize,0)
  I.PushStyleVar(ctx,I.StyleVar_DisabledAlpha,1)
  I.PushStyleColor(ctx,I.Col_FrameBg,0);I.PushStyleColor(ctx,I.Col_FrameBgHovered,0);I.PushStyleColor(ctx,I.Col_FrameBgActive,0)
  I.PushStyleColor(ctx,I.Col_TextSelectedBg,self.selectionColor);I.PushStyleColor(ctx,I.Col_NavCursor,0)
  for _,item in ipairs(list) do self:draw(item) end
  I.PopStyleColor(ctx,5);I.PopStyleVar(ctx,3)
  for i=#list,1,-1 do list[i]=nil end
 end
 return T
end
return M
end)()

BLT.ShellText=(function()
local M={}
local floor,ceil,max=math.floor,math.ceil,math.max
function M.new(host,api,native)
 native=native or gfx
 assert(native and native.setfont and native.measurestr,'REAPER gfx font API is required')
 local I,ctx=host.I,host.ctx
 local T={fonts={},images={},imageCount=0,measureCount=0}
 local faces=host.mac and {['Hiragino Sans']={'HiraginoSans-W4','HiraginoSans-W6'},
  ['Helvetica Neue']={'HelveticaNeue-Medium','HelveticaNeue-Bold'},Menlo={'Menlo-Regular','Menlo-Bold'}}
 local current,bitmap,bw,bh
 local function clearImages()
  for _,entry in pairs(T.images) do host:releaseImage(entry.image) end
  T.images={};T.imageCount=0
  for _,f in ipairs(T.fonts) do f.images={} end
 end
 local function release(f)
  api.JS_LICE_DestroyFont(f.lice);api.JS_GDI_DeleteObject(f.gdi)
 end
 function T:setfont(_,face,size,flags)
  local dpi=ceil(host.dpi or I.GetWindowDpiScale(ctx));local px=max(1,floor(size*dpi+.5));flags=flags or 0
  if current and current.face==face and current.px==px and current.flags==flags then self.dpi=dpi;return px/dpi end
  for _,f in ipairs(self.fonts) do
   if f.face==face and f.px==px and f.flags==flags then current=f;self.dpi=dpi;return px/dpi end
  end
  local slot=(self.nextSlot or 0)%16+1;self.nextSlot=slot
  if self.fonts[slot] then release(self.fonts[slot]) end
  local family=faces and faces[face];local nativeFace=family and family[flags==98 and 2 or 1] or face
  local nativeFlags=family and 0 or flags
  native.setfont(slot,nativeFace,px,nativeFlags)
  local f={face=face,px=px,flags=flags,slot=slot,metrics={},images={},key=face..':'..px..':'..flags..':'}
  f.gdi=assert(api.JS_GDI_CreateFont(px,nativeFlags==98 and 700 or 400,0,false,false,false,nativeFace),'Font creation failed')
  f.lice=assert(api.JS_LICE_CreateFont(),'LICE font creation failed')
  api.JS_LICE_SetFontFromGDI(f.lice,f.gdi,'')
  api.JS_LICE_SetFontColor(f.lice,0xffffffff)
  self.fonts[slot]=f;current=f;self.dpi=dpi
  return px/dpi
 end
 function T:measurestr(text)
  text=tostring(text);local result=current.metrics[text]
  if not result then
   if self.measureCount>=512 then
    for _,f in ipairs(self.fonts) do f.metrics={} end;self.measureCount=0
   end
   native.setfont(current.slot)
   local w,h=native.measurestr(text)
   result={w,h};current.metrics[text]=result;self.measureCount=self.measureCount+1
  end
  return result[1]/self.dpi,result[2]/self.dpi,current.px/self.dpi
 end
 function T:rasterize(text)
   local w,h=self:measurestr(text);w,h=max(1,floor(w*self.dpi+.5)),max(1,floor(h*self.dpi+.5))
   local unicode=text:find('[\128-\255]')
   if unicode and bitmap then api.JS_LICE_DestroyBitmap(bitmap);bitmap=nil end
   if not bitmap then bitmap=assert(api.JS_LICE_CreateBitmap(true,w,h))
   elseif w~=bw or h~=bh then api.JS_LICE_Resize(bitmap,w,h) end
   bw,bh=w,h;api.JS_LICE_Clear(bitmap,0xff000000)
   if unicode then
    local left=0
    if unicode>1 then
     local prefix=text:sub(1,unicode-1)
     api.JS_LICE_DrawText(bitmap,current.lice,prefix,#prefix,0,0,w,h)
     left=floor(self:measurestr(prefix)*self.dpi+.5)
    end
    local dc=assert(api.JS_LICE_GetDC(bitmap),'Bitmap drawing context is required')
    api.JS_GDI_SelectObject(dc,current.gdi)
    api.JS_GDI_SetTextBkMode(dc,1);api.JS_GDI_SetTextColor(dc,0xffffff)
    local rest=text:sub(unicode)
    api.JS_GDI_DrawText(dc,rest,#rest,left,0,w,h,'SINGLELINE NOPREFIX')
   else api.JS_LICE_DrawText(bitmap,current.lice,text,#text,0,0,w,h) end
   api.JS_LICE_Blit(bitmap,0,0,bitmap,0,0,w,h,1,'CHANCOPY_RTOA')
   return bitmap,w,h,unicode
 end
 function T:paint(command,destination)
  if command.text=='' then return end
  self:setfont(1,command.face,command.size,command.flags)
  local source,w,h,unicode=self:rasterize(command.text)
  api.JS_LICE_ProcessRect(source,0,0,w,h,'SET_RGB',command.color&0xffffff)
  local alpha=floor(command.alpha*255+.5)/255
  api.JS_LICE_Blit(destination,floor(command.x*self.dpi+.5),floor(command.y*self.dpi+.5),source,0,0,w,h,alpha,'COPY ALPHA')
  if unicode then api.JS_LICE_DestroyBitmap(bitmap);bitmap=nil end
 end
 function T:paintMask(command,destination)
  local value=command.text;if value=='' then return end
  self:setfont(1,command.face,command.size,command.flags)
  local w,h=self:measurestr(value)
  w,h=max(1,floor(w*self.dpi+.5)),max(1,floor(h*self.dpi+.5))
  local x,y=floor(command.x*self.dpi+.5),floor(command.y*self.dpi+.5)
  local right,bottom=x+w,y+h;local unicode=value:find('[\128-\255]')
  if unicode then
   if unicode>1 then
    local prefix=value:sub(1,unicode-1)
    api.JS_LICE_DrawText(destination,current.lice,prefix,#prefix,x,y,right,bottom)
    x=x+floor(self:measurestr(prefix)*self.dpi+.5)
   end
   local dc=assert(api.JS_LICE_GetDC(destination),'Bitmap drawing context is required')
   api.JS_GDI_SelectObject(dc,current.gdi)
   api.JS_GDI_SetTextBkMode(dc,1);api.JS_GDI_SetTextColor(dc,0xffffff)
   local rest=value:sub(unicode)
   api.JS_GDI_DrawText(dc,rest,#rest,x,y,right,bottom,'SINGLELINE NOPREFIX')
  else api.JS_LICE_DrawText(destination,current.lice,value,#value,x,y,right,bottom) end
 end
 function T:draw(text,x,y,r,g,b,a)
  text=tostring(text);if text=='' then return end
  local entry=current.images[text]
  local key
  if not entry then key=current.key..text;entry=self.images[key] end
  if not entry then
   local source,w,h,unicode=self:rasterize(text)
   api.JS_LICE_ProcessRect(source,0,0,w,h,'SET_RGB',0xffffff)
   if self.imageCount>=64 then clearImages() end
   entry={image=I.CreateImageFromLICE(source),w=w,h=h};host:attachImage(entry.image)
   if unicode then api.JS_LICE_DestroyBitmap(bitmap);bitmap=nil end
   self.images[key]=entry;self.imageCount=self.imageCount+1
  end
  current.images[text]=entry
  local ox,oy=host.windowX or host.originX,host.windowY or host.originY
  local xx=ox+floor((host.originX-ox+x)*self.dpi+.5)/self.dpi
  local yy=oy+floor((host.originY-oy+y)*self.dpi+.5)/self.dpi
  I.DrawList_AddImage(host.draw,entry.image,xx,yy,xx+entry.w/self.dpi,yy+entry.h/self.dpi,0,0,1,1,host.rgba(r,g,b,a or 1))
 end
 function T:capture(command,text,x,y,color,alpha)
  command.text,command.x,command.y,command.color,command.alpha=text,x,y,color,alpha
  command.face,command.size,command.flags=current.face,current.px/self.dpi,current.flags
 end
 function T:replay(command)
  self:setfont(1,command.face,command.size,command.flags)
  local c=command.color
  self:draw(command.text,command.x,command.y,((c>>16)&255)/255,((c>>8)&255)/255,(c&255)/255,command.alpha)
 end
 function T:canvas(G)
  local P=setmetatable({},{__index=G});local r,g,b,a=1,1,1,1
  P.setfont=function(...) return self:setfont(...) end
  P.measurestr=function(text) return self:measurestr(text) end
  P.set=function(rr,gg,bb,aa) r,g,b,a=rr,gg,bb,aa or 1;G.set(r,g,b,a) end
  P.drawstr=function(text) self:draw(text,P.x,P.y,r,g,b,a) end
  return P
 end
 function T:close()
  if bitmap then api.JS_LICE_DestroyBitmap(bitmap);bitmap=nil end
  for _,f in ipairs(self.fonts) do release(f) end
  self.fonts={};clearImages();current=nil
 end
 return T
end
return M
end)()

BLT.ChromeRaster=(function()
local M={}
local floor,max=math.floor,math.max
local function byte(v) return floor(max(0,math.min(1,v))*255) end
function M.new(host,api,text)
 local I,ctx,G=host.I,host.ctx,host.g
 for _,name in ipairs({'CreateBitmap','DestroyBitmap','Resize','Clear','FillRect','GradRect','Line','RoundRect','FillCircle','ProcessRect'}) do
  assert(type(api['JS_LICE_'..name])=='function','js_ReaScriptAPI: JS_LICE_'..name..' が必要です。')
 end
 local B={g={},signature={},texts={},count=0}
 local P=B.g
 local bitmap,image,scale,width,height
 local color,alpha=0xffffffff,1
 local paletteKeys={'bg','field','edge','accent','accent2','muted','text'}
 local extraColors={}
 local signatureIndex=0
 local function check(value)
  signatureIndex=signatureIndex+1
  if B.signature[signatureIndex]~=value then B.signature[signatureIndex]=value;B.dirty=true end
 end
 function P.set(r,g,b,a)
  color=(255<<24)|(byte(r)<<16)|(byte(g)<<8)|byte(b);alpha=a or 1
 end
 function P.rect(x,y,w,h,filled)
  if not B.dirty then return end
  x,y,w,h=floor(x*scale),floor(y*scale),floor(w*scale),floor(h*scale)
  if filled==0 then
   api.JS_LICE_Line(bitmap,x,y,x+w-1,y,color,alpha,'COPY',false)
   api.JS_LICE_Line(bitmap,x+w-1,y,x+w-1,y+h-1,color,alpha,'COPY',false)
   api.JS_LICE_Line(bitmap,x+w-1,y+h-1,x,y+h-1,color,alpha,'COPY',false)
   api.JS_LICE_Line(bitmap,x,y+h-1,x,y,color,alpha,'COPY',false)
  else api.JS_LICE_FillRect(bitmap,x,y,w,h,color,alpha,'COPY') end
 end
 function P.line(x,y,xx,yy,aa)
  if B.dirty then api.JS_LICE_Line(bitmap,floor(x*scale),floor(y*scale),floor(xx*scale),floor(yy*scale),color,alpha,'COPY',aa~=0) end
 end
 function P.roundrect(x,y,w,h,r,aa)
  if B.dirty then api.JS_LICE_RoundRect(bitmap,x*scale,y*scale,w*scale,h*scale,floor(r*scale),color,alpha,'COPY',aa~=0) end
 end
 function P.circle(x,y,r,filled,aa)
  if B.dirty then api.JS_LICE_FillCircle(bitmap,x*scale,y*scale,r*scale,color,alpha,'COPY',aa~=0) end
 end
 function P.gradrect(x,y,w,h,r,g,b,a,rx,gx,bx,ax,ry,gy,by,ay)
  if B.dirty then api.JS_LICE_GradRect(bitmap,floor(x*scale),floor(y*scale),floor(w*scale),floor(h*scale),
   r,g,b,a,(rx or 0)/scale,(gx or 0)/scale,(bx or 0)/scale,(ax or 0)/scale,
   (ry or 0)/scale,(gy or 0)/scale,(by or 0)/scale,(ay or 0)/scale,'COPY') end
 end
 P.setfont=function(...) return text:setfont(...) end
 P.measurestr=function(value) return text:measurestr(value) end
 function P.drawstr(value)
  B.count=B.count+1;local command=B.texts[B.count] or {};B.texts[B.count]=command
  text:capture(command,tostring(value),P.x,P.y,color,alpha)
 end
 function B:begin(painter)
  scale=host.dpi or I.GetWindowDpiScale(ctx);width,height=floor(G.w*scale+.5),floor(painter.chrome.titleH*scale+.5)
  self.combined=scale==math.ceil(scale) and math.abs(G.w*scale-width)<1e-7 and math.abs(painter.chrome.titleH*scale-height)<1e-7 and
   math.abs(host.originX*scale-floor(host.originX*scale+.5))<1e-7 and math.abs(host.originY*scale-floor(host.originY*scale+.5))<1e-7
  signatureIndex=0;self.dirty=not image
  check(width);check(height);check(scale);check(self.combined);check(painter.dirty or false);check(painter.hot~='drag' and painter.hot or false);check(painter.presetOpen or false);check(painter.themeEnabled or false);check(painter.language)
  for _,key in ipairs(paletteKeys) do local c=painter.C[key];check(c[1]);check(c[2]);check(c[3]) end
  extraColors[1],extraColors[2],extraColors[3],extraColors[4],extraColors[5]=painter.chrome.mint,painter.chrome.red,painter.c1,painter.c2,painter.c3
  for _,c in ipairs(extraColors) do check(c[1]);check(c[2]);check(c[3]) end
  if not bitmap then bitmap=assert(api.JS_LICE_CreateBitmap(true,width,height),'LICE bitmap creation failed')
  elseif self.width~=width or self.height~=height then api.JS_LICE_Resize(bitmap,width,height) end
  self.width,self.height=width,height
  if self.dirty then api.JS_LICE_Clear(bitmap,0xff000000) end
  P.w,P.h=G.w,painter.chrome.titleH
  if self.dirty then self.count=0 end
  return P
 end
 function B:finish()
  if self.dirty then
   if self.combined then for i=1,self.count do text:paint(self.texts[i],bitmap) end end
   api.JS_LICE_ProcessRect(bitmap,0,0,width,height,'SET_A',0xff000000)
   if image then host:releaseImage(image) end
   image=I.CreateImageFromLICE(bitmap);host:attachImage(image)
  end
  I.DrawList_AddImage(host.draw,image,host.originX,host.originY,host.originX+P.w,host.originY+P.h)
  if not self.combined then for i=1,self.count do text:replay(self.texts[i]) end end
 end
 function B:close()
  if bitmap then api.JS_LICE_DestroyBitmap(bitmap);bitmap=nil end
  if image then host:releaseImage(image);image=nil end
 end
 return B
end
return M
end)()

BLT.HeaderIcon=(function()
local M={}
local min,max,sin,pi=math.min,math.max,math.sin,math.pi
function M.new(host,ui,definition)
 local icon={definition=definition,mode=definition.modes[1],state={},particles={},pool={},commands={},serial=0,
  phase=0,spawnClock=0,untilTime=0}
 local pen={C=ui.C,font=host.faces[1],minFontSize=5,scale=1,ox=0,oy=0}
 for _,name in ipairs({'rect','line','disc','text','shape','surface','bloom','frame','glowParticle'}) do pen[name]=ui[name] end
 function pen:bars(x,y,spacing,width,heights,c,a)
  host.g.set(c[1],c[2],c[3],a or 1)
  host.g.bars(self.ox+x*self.scale,self.oy+y*self.scale,spacing,width,heights,self.scale)
 end
 icon.pen=pen
 local recorder={C=ui.C};local count=0
 for _,name in ipairs({'rect','line','disc','text','bars'}) do
  recorder[name]=function(_,...)
   count=count+1;local c=icon.commands[count] or {};icon.commands[count]=c
   c.draw,c.n=pen[name],select('#',...)
   c[1],c[2],c[3],c[4],c[5],c[6],c[7],c[8],c[9]=...
  end
 end
 function icon:cycle(now)
  local modes=self.definition.modes;local index=1
  for i,mode in ipairs(modes) do if mode==self.mode then index=i;break end end
  self.mode=modes[index%#modes+1];self.dirty=true
  self.untilTime=now+2.5
 end
 function icon:animating(now)
  return self.dirty or not self.ready or #self.particles>0 or self.active and now<self.untilTime
 end
 function icon:tick(now,active,wake)
  local gap=self.lastTime and max(0,now-self.lastTime) or 0;self.lastTime=now
  if self.ready and not self.dirty and self.active==active and #self.particles==0 and
   (not active or (not wake and now>=self.untilTime)) then return end
  local dt=gap>.25 and 0 or min(.1,gap)
  if active and (wake or not self.active) then self.untilTime=now+2.5 end
  local remaining=self.untilTime-now
  local speed=active and min(1,max(0,remaining/.7)) or 0;speed=speed*speed*(3-2*speed)
  if not active or speed==0 or gap>.25 then self.spawnClock=0 end
  self.phase=self.phase+dt*speed
  local provider=self.definition
  if self.dirty or not self.ready or (speed>0 and now>=(self.nextShape or 0)) or self.active~=active then
   provider.update(self.state,self.mode,active and min(.1,max(0,now-(self.lastShape or now))) or 1)
   count=0;provider.draw(recorder,self.state,self.mode,self.phase)
   self.commandCount=count
   self.ready,self.dirty,self.nextShape,self.lastShape=true,false,now+1/30,now
  end
  self.active=active
  if speed>0 and dt>0 then
   self.spawnClock=self.spawnClock+dt*speed
   while self.spawnClock>=.075 and #self.particles<36 do
    self.spawnClock=self.spawnClock-.075;self.serial=self.serial+1
    local p=self.pool[#self.pool] or {};self.pool[#self.pool]=nil
    provider.emit(self.state,self.serial,p);p.born,p.alpha=now,0
    self.particles[#self.particles+1]=p
   end
   self.spawnClock=min(self.spawnClock,.075)
  end
  if #self.particles==0 then return end
  if now<(self.nextParticles or 0) then return end
  self.nextParticles=now+1/30
  for i=#self.particles,1,-1 do
   local p=self.particles[i];local age=max(0,now-p.born)
   if age>=p.life then self.pool[#self.pool+1]=p;table.remove(self.particles,i)
   else
    if provider.sample then p.px,p.py=provider.sample(self.state,p,age)
    else p.px=p.x+p.vx*age+sin(age*p.freq+p.phase)*p.sway;p.py=p.y-p.vy*age end
    p.alpha=sin(pi*age/p.life)^2
   end
  end
 end
 function icon:draw(x,y,scale)
  pen.scale,pen.ox,pen.oy=scale,x,y
  for i=1,self.commandCount or 0 do
   local c=self.commands[i];c.draw(pen,table.unpack(c,1,c.n))
  end
  for _,p in ipairs(self.particles) do
   local a=p.alpha or 0
   if a>.002 then
    pen:glowParticle(p.px,p.py,p.r,a,p.glint)
   end
  end
 end
 return icon
end
return M
end)()

BLT.Shell=(function()
local M={}
local ChromeRaster,ShellText=BLT.ChromeRaster,BLT.ShellText
M.spec={barHeight=26,titleSize=35,subtitleSize=10,titleX=24,titleY=8,subtitleX=26,subtitleY=44,
 dividerY=62,inset=24,footerBottom=13,footerSize=9,versionSize=8,versionGap=14}
function M.new(host,ui,api,options)
 local gfx=host.g

local BLTChrome=(function()
local M={}
function M.layout(w)
 local b=M.layoutCache
 if b and b.width==w then return b end
 b={width=w,closeX=w-38,resetX=w-72,themeX=w-106}
 b.languageX=b.themeX-26
 b.nextX=b.languageX-20;b.prevX=b.nextX-20;b.presetX=b.prevX-84
 M.layoutCache=b;return b
end
function M.hit(b,x,y,w,h)
 if x<0 or x>=w or y<0 or y>=h then return nil end
 if x>=b.closeX then return 'close' end
 if x>=b.resetX then return 'reset' end
 if x>=b.themeX then return 'theme' end
 if x>=b.languageX then return 'language' end
 if x>=b.nextX then return 'next' end
 if x>=b.prevX then return 'prev' end
 if x>=b.presetX then return 'preset' end
 return 'drag'
end
function M.background(C,h,x,w)
 gfx.set(C.bg[1],C.bg[2],C.bg[3],1);gfx.rect(x,0,w,h,1)
 gfx.gradrect(x,0,w,h,C.field[1],C.field[2],C.field[3],.72,0,0,0,0,(C.bg[1]-C.field[1])/h,(C.bg[2]-C.field[2])/h,(C.bg[3]-C.field[3])/h,.22/h)
 gfx.set(C.edge[1],C.edge[2],C.edge[3],.42);gfx.line(x,h-1,x+w,h-1,1)
end
function M.draw(p)
 local C,Chrome,b,w=p.C,p.chrome,p.b,gfx.w
 local closeX,resetX,chamX=b.closeX,b.resetX,b.themeX
 local languageX,presetX,prevX,nextX=b.languageX,b.presetX,b.prevX,b.nextX
 local closeW,resetW,chamW=38,34,34
 local hoverClose,hoverReset,hoverCham=p.hot=='close',p.hot=='reset',p.hot=='theme'
 local hoverLanguage,hoverPreset=p.hot=='language',p.hot=='preset'
 local hoverPrev,hoverNext=p.hot=='prev',p.hot=='next'
  M.background(C,Chrome.titleH,0,w)

  p.barFont()
  local _,titleHeight=p.metrics(Chrome.titleText)
  local ty=math.floor((Chrome.titleH-titleHeight)*.5)
  gfx.set(Chrome.mint[1],Chrome.mint[2],Chrome.mint[3],.88); gfx.x=14; gfx.y=ty; gfx.drawstr(p.fit(Chrome.titleText,math.max(0,presetX-22)))

  if hoverPreset or p.presetOpen then
    gfx.set(C.accent[1],C.accent[2],C.accent[3],.10);gfx.rect(presetX+2,3,78,20,1)
  end
  gfx.set(C.edge[1],C.edge[2],C.edge[3],(hoverPreset or hoverPrev or hoverNext) and .9 or .5)
  gfx.roundrect(presetX+2,3,languageX-presetX-5,20,3,1)
  gfx.set(C.muted[1],C.muted[2],C.muted[3],.35);gfx.line(languageX-1,6,languageX-1,20)
  local pc=hoverPreset and Chrome.mint or C.muted
  gfx.set(pc[1],pc[2],pc[3],hoverPreset and .98 or .8)
  gfx.roundrect(presetX+10,7,7,8,1,1);gfx.roundrect(presetX+13,10,7,8,1,1)
  p.barFont()
  gfx.x=presetX+26;gfx.y=7;gfx.drawstr("PRESET")
  gfx.line(presetX+67,11,presetX+70,14);gfx.line(presetX+70,14,presetX+73,11)

  p.arrows=p.arrows or {{},{}}
  local left,right=p.arrows[1],p.arrows[2]
  left[1],left[2],left[3]=prevX,hoverPrev,-1;right[1],right[2],right[3]=nextX,hoverNext,1
  for _,arrow in ipairs(p.arrows) do
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
  p.languageFont()
  local lw,lh=p.metrics(p.language)
  gfx.x=languageX+(26-lw)/2;gfx.y=(Chrome.titleH-lh)/2;gfx.drawstr(p.language)
  if hoverCham or p.themeEnabled then
    local a=hoverCham and .095 or .045
    gfx.set(C.accent[1],C.accent[2],C.accent[3],a); gfx.rect(chamX,0,chamW,Chrome.titleH,1)
    gfx.set(C.accent2[1],C.accent2[2],C.accent2[3],hoverCham and .42 or .24)
    gfx.line(chamX,Chrome.titleH-1,resetX,Chrome.titleH-1,1)
  end
  local chx,chy=chamX+chamW*.5,Chrome.titleH*.5
  local active_a=hoverCham and 1 or (p.themeEnabled and .96 or .85)

  local c1,c2,c3=p.c1,p.c2,p.c3

  gfx.set(c1[1],c1[2],c1[3],active_a)
  gfx.circle(chx-3.5,chy+2,4.5,1,1)

  gfx.set(c2[1],c2[2],c2[3],active_a*.92)
  gfx.circle(chx+3.5,chy+2,4.5,1,1)

  gfx.set(c3[1],c3[2],c3[3],active_a*.94)
  gfx.circle(chx,chy-3.3,4.5,1,1)

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

  if hoverClose then
    gfx.set(Chrome.red[1],Chrome.red[2],Chrome.red[3],.10); gfx.rect(closeX,0,closeW,Chrome.titleH,1)
    gfx.set(Chrome.red[1],Chrome.red[2],Chrome.red[3],.56); gfx.line(closeX,Chrome.titleH-1,w,Chrome.titleH-1,1)
  end
  local xc=hoverClose and Chrome.red or C.muted
  local xa=hoverClose and .98 or .82
  local cx,cy=closeX+closeW*.5,Chrome.titleH*.5
  gfx.set(xc[1],xc[2],xc[3],xa)
  gfx.line(cx-4.6,cy-4.6,cx+4.6,cy+4.6,1); gfx.line(cx+4.6,cy-4.6,cx-4.6,cy+4.6,1)

end
return M
end)()



local BLTChameleon=(function()

local BLTThemeColors=(function()
 local M={}
 function M.native(api,key)
  local ok,n=pcall(api.GetThemeColor,key,0)
  if not ok or type(n)~='number' or n~=n or n%1~=0 then return -1 end
  return n
 end
 function M.decode(api,n)
  if n==-1 then return nil end
  local ok,r,g,b=pcall(api.ColorFromNative,n)
  if not ok then return nil end
  for _,v in ipairs({r,g,b}) do
   if type(v)~='number' or v~=v or v<0 or v>255 then return nil end
  end
  if r==nil or g==nil or b==nil then return nil end
  return {r/255,g/255,b/255}
 end
 local function linear(v) return v<=.04045 and v/12.92 or ((v+.055)/1.055)^2.4 end
 function M.luminance(c) return linear(c[1])*.2126+linear(c[2])*.7152+linear(c[3])*.0722 end
 function M.contrast(a,b)
  local x,y=M.luminance(a),M.luminance(b)
  return (math.max(x,y)+.05)/(math.min(x,y)+.05)
 end
 return M
end)()

 local M={}
 M.keys={
  'col_main_bg2','col_main_bg','col_arrangebg','col_tracklistbg','col_mixerbg',
  'genlist_bg','col_tl_bg','col_trans_bg','col_tr1_bg','col_tr2_bg',
  'col_main_editbk','col_transport_editbk','col_buttonbg',
  'col_main_text2','col_main_text','genlist_fg','col_tcp_text',
  'col_toolbar_text','col_toolbar_text_on','col_tl_fg','col_tl_fg2','col_trans_fg',
  'col_seltrack','col_seltrack2','genlist_selbg','col_tl_bgsel','toolbararmed_color',
  'col_main_resize2','selitem_dot','selitem_tag','activetake_tag',
  'col_routinghl1','col_routinghl2','track_lanesolo_tabcol',
  'col_main_3dhl','col_main_3dsh','genlist_grid','col_toolbar_frame',
  'col_tr1_divline','col_tr2_divline','docker_shadow',
 }
 function M.copy(c) return {c[1],c[2],c[3]} end
 function M.mix(a,b,t)
  t=math.max(0,math.min(1,t or 0))
  return {a[1]+(b[1]-a[1])*t,a[2]+(b[2]-a[2])*t,a[3]+(b[3]-a[3])*t}
 end
 function M.luma(c) return c[1]*.2126+c[2]*.7152+c[3]*.0722 end
 local function saturation(c) return math.max(c[1],c[2],c[3])-math.min(c[1],c[2],c[3]) end
 local function shift(c,target)
  local l=M.luma(c);target=math.max(0,math.min(1,target))
  if math.abs(target-l)<1e-5 then return M.copy(c) end
  if target<l then return M.mix(c,{0,0,0},(l-target)/math.max(l,1e-9)) end
  return M.mix(c,{1,1,1},(target-l)/math.max(1-l,1e-9))
 end
 local function boost(c,factor)
  local l=M.luma(c);local out={}
  for i=1,3 do out[i]=math.max(0,math.min(1,l+(c[i]-l)*factor)) end
  return out
 end
 function M.fit(accent,bg,light)
  if math.abs(M.luma(accent)-M.luma(bg))>=.17 then return M.copy(accent) end
  return shift(accent,light and math.min(.78,M.luma(bg)+.28) or math.max(.16,M.luma(bg)-.30))
 end
 local function surface(c,bg,factor,lo,hi)
  local delta=M.luma(c)-M.luma(bg)
  return shift(c,math.max(.01,math.min(.99,M.luma(bg)+(delta<0 and -1 or 1)*math.max(lo,math.min(hi,math.abs(delta)*factor)))))
 end
 local function first_near(map,bg,keys,gap)
  local l=M.luma(bg)
  for _,key in ipairs(keys) do local c=map[key];if c and math.abs(M.luma(c)-l)<=gap then return c end end
 end
 local function generated_text(bg)
  local light,dark={.935,.945,.958},{.070,.075,.082}
  local lr,dr=BLTThemeColors.contrast(light,bg),BLTThemeColors.contrast(dark,bg)
  local is_light=lr>dr;local color=is_light and light or dark
  if math.max(lr,dr)<4.5 then color=is_light and {1,1,1} or {0,0,0} end
  return color,is_light
 end
 local text_keys={'col_main_text2','col_main_text','genlist_fg','col_tcp_text','col_toolbar_text','col_tl_fg','col_trans_fg'}
 local accent_keys={'genlist_selbg','col_seltrack','toolbararmed_color','col_tl_bgsel','col_toolbar_text_on','col_main_resize2',
  'selitem_dot','selitem_tag','activetake_tag','col_routinghl1','col_routinghl2','track_lanesolo_tabcol','col_tl_fg'}
 local hi_keys={'col_main_3dhl','col_toolbar_frame','genlist_grid','col_tl_fg2','col_tr1_divline','col_tr2_divline'}
 local sh_keys={'col_main_3dsh','docker_shadow','genlist_grid','col_tr1_divline','col_tr2_divline'}
 local panel_keys={'col_main_bg','col_tracklistbg','col_mixerbg','genlist_bg','col_seltrack2','col_tl_bg','col_tr1_bg','col_tr2_bg'}
 local field_keys={'col_main_editbk','col_transport_editbk','genlist_bg','col_buttonbg','col_trans_bg'}
 local function best_color(map,bg,keys,role,dark)
  local best,score=nil,-math.huge;local l=M.luma(bg)
  for i,key in ipairs(keys) do
   local c=map[key]
   if c then
    local delta=M.luma(c)-l;local gap=math.abs(delta);local sat=saturation(c);local value
    if role=='text' then
     if gap>=.28 then value=gap+sat*.20 end
    elseif role=='accent' then
     value=sat*1.45+gap*.72+(i<=3 and .12 or 0)-(gap<.035 and sat<.035 and .35 or 0)
    else
     local wanted=role=='hi' and (dark and delta>0 or not dark and delta<0)
      or role=='sh' and (dark and delta<0 or not dark and delta>0)
     value=gap+(wanted and .16 or 0)
    end
    if value and value>score then best,score=c,value end
   end
  end
  return best
 end

 function M.snapshot(api,cache,force)
  cache=cache or {raw={},map={}};local changed=not cache.ready
  for i,key in ipairs(M.keys) do
   local native=BLTThemeColors.native(api,key)
   if force or native~=cache.raw[i] then
    local c=BLTThemeColors.decode(api,native)
    cache.map[key]=c;cache.raw[i]=c and native or -1;changed=true
   end
  end
  cache.ready=true
  return cache.map,changed,cache
 end
 local function hue_gap(a,b)
  local al,bl=math.min(a[1],a[2],a[3]),math.min(b[1],b[2],b[3])
  local ar,br=saturation(a),saturation(b)
  if ar<.06 or br<.06 then return 1 end
  local gap=0
  for i=1,3 do gap=gap+math.abs((a[i]-al)/ar-(b[i]-bl)/br) end
  return gap/3
 end
 local function special_color(map,base,original,other)
  local best,score=nil,-math.huge
  for _,key in ipairs(accent_keys) do
   local c=map[key]
   if c and saturation(c)>=.08 then
    local gap=hue_gap(c,base);local separation=other and hue_gap(c,other) or 1
    if gap>=.14 and separation>=.14 then
     local value=gap*.8+separation*.65+saturation(c)*.3+(1-hue_gap(c,original))*.25
     if value>score then best,score=c,value end
    end
   end
  end
  if best then return best end
  local fallback=original
  for _=1,3 do
   local color=M.mix(base,fallback,.55)
   if hue_gap(color,base)>=.14 and (not other or hue_gap(color,other)>=.14) then return color end
   fallback={fallback[2],fallback[3],fallback[1]}
  end
  return M.mix(base,original,.55)
 end
 local function special_palette(base,source,original,light)
  local accent=M.fit(source,base.bg,light)
  local field=M.mix(base.field,accent,.045)
  local text=M.mix(accent,base.text,.48)
  if BLTThemeColors.contrast(text,field)<4.5 then text=generated_text(field) end
  local ice=M.mix(accent,base.text,.30)
  return {field=field,edge=M.mix(base.edge,accent,.35),
   accent=accent,ice=ice,text=text,rim=ice,ember=M.mix(accent,base.text,.16),spark=base.text,gilded=original.gilded==true}
 end
 function M.palette(map,defaults,special)

  local bg=M.copy(map.col_main_bg2 or map.col_main_bg or map.col_tracklistbg or map.genlist_bg or map.col_arrangebg or defaults.bg)
  local l=M.luma(bg);local dark=l<.50
  local panel=first_near(map,bg,panel_keys,.16) or shift(bg,dark and math.min(.92,l+.040) or math.max(.08,l-.040))
  local field=first_near(map,bg,field_keys,.14) or shift(bg,dark and math.min(.92,l+.018) or math.min(.96,l+.020))
  panel=surface(panel,bg,1.48,.030,.105);field=surface(field,bg,1.38,.020,.085)
  if dark and M.luma(panel)<=l+.022 then panel=shift(panel,math.min(.94,l+.038))
  elseif not dark and M.luma(panel)>=l-.022 then panel=shift(panel,math.max(.06,l-.038)) end
  local generated,light=generated_text(bg)
  local text=M.mix(generated,best_color(map,bg,text_keys,'text') or generated,.18)
  if BLTThemeColors.contrast(text,bg)<4.5 then text=generated end
  local accent=boost(best_color(map,bg,accent_keys,'accent') or defaults.accent,dark and 1.18 or 1.14)
  accent=M.fit(accent,bg,light)
  if dark and M.luma(accent)<l+.22 then accent=shift(accent,math.min(.82,l+.26))
  elseif not dark and M.luma(accent)>l-.22 then accent=shift(accent,math.max(.12,l-.28)) end
  local edge=M.mix(bg,text,dark and .20 or .18);local edge2=M.mix(accent,text,dark and .12 or .09)
  local hi=best_color(map,bg,hi_keys,'hi',dark);local sh=best_color(map,bg,sh_keys,'sh',dark)
  if sh then edge=M.mix(edge,sh,.28) end;if hi then edge2=M.mix(edge2,hi,.24) end
  local out={bg=bg,bg2=M.mix(bg,accent,dark and .080 or .065),panel=panel,panel2=M.mix(panel,accent,dark and .105 or .085),field=field,
   text=text,muted=M.mix(text,bg,dark and .28 or .30),faint=M.mix(text,bg,dark and .50 or .52),edge=edge,edge2=edge2,
   accent=accent,accent2=M.mix(accent,text,dark and .14 or .09),accent3=M.mix(accent,bg,dark and .48 or .46),
   focus=M.mix(accent,text,dark and .06 or .04),focus2=M.mix(accent,text,dark and .20 or .12),
   ink=M.mix(bg,accent,dark and .16 or .12),hover=M.mix(accent,text,dark and .15 or .10)}
  if defaults.green then out.green=M.copy(out.accent2) end
  for _,key in ipairs({'warn','red','gold','purple','lock'}) do
   if defaults[key] then out[key]=M.fit(defaults[key],bg,light) end
  end
  if out.lock and defaults.lock2 then out.lock2=M.mix(out.lock,text,dark and .22 or .16) end
  if special then
   local gold=special_color(map,accent,special.gold.accent)
   local chaos=special_color(map,accent,special.chaos.accent,gold)
   out.special={gold=special_palette(out,gold,special.gold,light),chaos=special_palette(out,chaos,special.chaos,light)}
  end
  return out
 end
 local function hsv(c)
  local r,g,b=c[1],c[2],c[3];local mx=math.max(r,g,b);local d=mx-math.min(r,g,b);local h=0
  if d>1e-6 then h=(mx==r and ((g-b)/d)%6 or mx==g and (b-r)/d+2 or (r-g)/d+4)/6 end
  return h,mx<=1e-6 and 0 or d/mx,mx
 end
 local function rgb(h,s,v)
  h=h%1;local i=math.floor(h*6);local f=h*6-i
  local p,q,t=v*(1-s),v*(1-f*s),v*(1-(1-f)*s)
  i=i%6
  if i==0 then return {v,t,p} elseif i==1 then return {q,v,p} elseif i==2 then return {p,v,t}
  elseif i==3 then return {p,q,v} elseif i==4 then return {t,p,v} else return {v,p,q} end
 end
 function M.new(api,colors,options)
  options=options or {};local defaults={};local chrome_defaults
  for k,c in pairs(colors) do if type(c)=='table' and type(c[1])=='number' then defaults[k]=M.copy(c) end end
  local theme={enabled=api.GetExtState(options.section,'chameleon')=='1',poll_at=0,poll_interval=3}
  local cache,pending=nil,false
  local function chrome()
   local c=options.chrome;if type(c)=='function' then c=c() end
   if c and not chrome_defaults then chrome_defaults={mint=M.copy(c.mint),ice=M.copy(c.ice)} end
   return c
  end
  chrome()
  local function updated(restored,palette)
   theme.bltIcon=nil
   if options.applied then options.applied(restored,palette) end
   if options.changed then options.changed() end
  end
  function theme.apply(palette)
   for key in pairs(defaults) do
    local c=palette[options.roles and options.roles[key] or key]
    if c then colors[key]=c end
   end
   local c=chrome();if c then c.mint=M.copy(palette.accent2);c.ice=M.copy(palette.focus2) end
   updated(false,palette)
  end
  function theme.restore()
   for key,c in pairs(defaults) do colors[key]=M.copy(c) end
   local c=chrome();if c then c.mint=M.copy(chrome_defaults.mint);c.ice=M.copy(chrome_defaults.ice) end
   updated(true)
  end
  function theme.refresh(force)
   if not theme.enabled then return false end
   local map,changed;map,changed,cache=M.snapshot(api,cache,force)
   if not force and not changed and not pending then return false end
   pending=true;theme.apply(M.palette(map,defaults,options.special));pending=false
   if force then theme.poll_at=api.time_precise()+theme.poll_interval end
   return true
  end
  function theme.set(on)
   theme.enabled=on and true or false;cache=nil;pending=false
   local value=theme.enabled and '1' or '0'
   if options.store then options.store(options.section,'chameleon',value,true)
   else api.SetExtState(options.section,'chameleon',value,true) end
   if theme.enabled then theme.refresh(true) else theme.restore() end
   if options.notify then options.notify(theme.enabled and 'CHAMELEON  REAPERテーマに擬態' or 'CHAMELEON  オリジナル配色') end
  end
  function theme.toggle() theme.set(not theme.enabled) end
  function theme.tick(now)
   if not theme.enabled or now<theme.poll_at then return false end
   theme.poll_at=now+theme.poll_interval
   return theme.refresh(false)
  end
  function theme.icon_colors()
   local c=theme.bltIcon;local a=colors.accent
   if c and c.on==theme.enabled and c.r==a[1] and c.g==a[2] and c.b==a[3] then return c[1],c[2],c[3] end
   local x,y,z
   if theme.enabled then
    local h,s,v=hsv(a);s=math.max(s,.46)
    x,y,z=rgb(h,s,v),rgb(h+.19,math.max(.42,s*.90),v),rgb(h-.19,math.max(.42,s*.86),v)
   else
    x,y,z=M.copy(colors.muted),M.copy(colors.faint),M.copy(colors.edge)
    for _,color in ipairs({x,y,z}) do
     local gray=M.luma(color);for i=1,3 do color[i]=gray+(color[i]-gray)*.12 end
    end
   end
   theme.bltIcon={x,y,z,on=theme.enabled,r=a[1],g=a[2],b=a[3]};return x,y,z
  end
  return theme
 end
 return M
end)()


 local S={language=options.language or 'JP',preset=1,fitCache={},fitCount=0}
 S.typography=ShellText.new(host,api)
 S.textG=S.typography:canvas(host.g);gfx=S.textG
 S.raster=ChromeRaster.new(host,api,S.typography)
 local I,ctx,C=host.I,host.ctx,ui.C
 local spec=M.spec
 if options.layout then
  spec={};for key,value in pairs(M.spec) do spec[key]=value end
  for key,value in pairs(options.layout) do spec[key]=value end
 end
 C.accent2=C.ice;C.edge2={.36,.65,.90};C.faint={.39,.505,.635};C.warn={1,.755,.49}
 local chrome={titleH=spec.barHeight,titleText=options.barTitle or 'C O N T R O L   L A B',mint={.38,.88,.72},ice={.65,.895,1},red={1,.27,.34}}
 S.chrome=chrome
 if options.headerIcon then S.icon=BLT.HeaderIcon.new(host,ui,options.headerIcon) end
 local themeAPI=options.persist and api or setmetatable({GetExtState=function() return '' end},{__index=api})
 S.theme=BLTChameleon.new(themeAPI,C,{section=options.section or 'BLT_UI_DEMO',chrome=chrome,roles={ice='accent2',disabled='faint'},special=ui.tones,
  store=options.persist and (options.store or api.SetExtState) or function() end,
  applied=function(restored,palette) ui.themeTones=not restored and palette.special or nil end,
  changed=function() if S.icon then S.icon.dirty=true end end})
 function S:translate(text)
  if options.translate then return options.translate(text,self.language) end
  return text
 end
 function S:font(size,kind,bold,scale)
  local px=math.max(8,math.floor(size*(scale or ui.scale)+.5))
  self.face,self.weight,self.size=host.faces[kind],bold and 98 or 0,px
  local actual=gfx.setfont(1,self.face,px,self.weight)
  self.fontKey=self.face..':'..self.weight..':'..actual..':'..(host.dpi or 1)
 end
 function S:fit(text,width)
  local bucket=self.fitCache[self.fontKey];local cached=bucket and bucket[text]
  if cached and cached.width==width then return cached.text end
  local shown=text
  if gfx.measurestr(text)>width then
   if gfx.measurestr('…')>width then shown=''
   else
    local count=utf8.len(text);local valid=text
    if not count then valid=text:gsub('[\128-\255]','?');count=#valid end
    local low,high=0,count
    while low<high do
     local mid=math.floor((low+high+1)/2);local stop=utf8.offset(valid,mid+1) or (#valid+1)
     if gfx.measurestr(valid:sub(1,stop-1)..'…')<=width then low=mid else high=mid-1 end
    end
    shown=valid:sub(1,(utf8.offset(valid,low+1) or (#valid+1))-1)..'…'
   end
  end
  if self.fitCount>=512 then self.fitCache={};self.fitCount=0;bucket=nil end
  if not bucket then bucket={};self.fitCache[self.fontKey]=bucket end
  if not bucket[text] then self.fitCount=self.fitCount+1 end
  bucket[text]={width=width,text=shown};return shown
 end
 local function color(c,a) gfx.set(c[1],c[2],c[3],a or 1) end
 function S:text(text,x,y,width,size,kind,bold,c)
  self:font(size,kind,bold);color(c)
  gfx.x,gfx.y=ui.ox+x*ui.scale,ui.oy+y*ui.scale
  gfx.drawstr(self:fit(text,width*ui.scale))
 end
 function S:header(width)
  self:text(options.title or 'CONTROL LAB',spec.titleX,spec.titleY,width-150,spec.titleSize,2,true,C.text)
  self:text(self:translate(options.subtitle or 'COMMON BUTTON AND INPUT DESIGN STUDY'),spec.subtitleX,spec.subtitleY,width-155,spec.subtitleSize,1,false,C.accent2)
  ui:line(spec.inset,spec.dividerY,width-spec.inset,spec.dividerY,C.edge2,.26)
  if self.icon then
   local icon=self.icon;local now=api.time_precise();local active=I.IsWindowFocused(ctx)
   if options.iconMode then
    local mode=options.iconMode()
    if icon.mode~=mode then icon.mode=mode;icon.dirty=true end
   end
   local x,y=width-178,30
   local mx,my=(gfx.mouse_x-ui.ox)/ui.scale,(gfx.mouse_y-ui.oy)/ui.scale
   local hot=not options.iconMode and active and not self.popupOpen and mx>=x and mx<x+54 and my>=y and my<y+20
   if self.pressed and hot then self.iconPressed=true end
   if self.released or not active then
    if self.iconPressed and hot and active then icon:cycle(now) end
    self.iconPressed=false
   end
   local text=ui.editor.edit and ui.editor.edit.text
   local wake=(gfx.mouse_x>=0 and gfx.mouse_y>=0 and (gfx.mouse_x~=self.iconMX or gfx.mouse_y~=self.iconMY)) or
    gfx.mouse_cap~=self.iconCap or gfx.mouse_wheel~=0 or host.key~=0 or text~=self.iconText or gfx.w~=self.iconWidth or gfx.h~=self.iconHeight or host.dpi~=self.iconDpi
   self.iconMX,self.iconMY,self.iconCap,self.iconText,self.iconWidth,self.iconHeight,self.iconDpi=gfx.mouse_x,gfx.mouse_y,gfx.mouse_cap,text,gfx.w,gfx.h,host.dpi
   icon:tick(now,active,wake)
   local scale=spec.iconScale or math.min(.8,80/icon.definition.width,50/icon.definition.height)
   icon:draw(ui.ox+(spec.iconX or width-spec.inset-icon.definition.width*scale)*ui.scale,ui.oy+(spec.iconY or 6)*ui.scale,scale*ui.scale)
   if not options.iconMode then
    local p=icon.pen;p.scale,p.ox,p.oy=ui.scale,ui.ox,ui.oy
    local f=self.iconFrame or {};self.iconFrame=f
    f.hot,f.pressed,f.focus=hot and 1 or 0,self.iconPressed and hot,false
    p:frame(x,y,54,20,f)
    p:text(self.language=='JP' and '切替' or 'SWITCH',x,y,54,20,9,C.muted,true)
   end
  end
 end
 function S:footer(message,bad,width,height,version,progress)
  local scale=ui.scale;local y=height-spec.footerBottom;local ver='v'..version
  self:font(spec.versionSize,3,true);local vw=gfx.measurestr(ver)
  local available=(width-spec.inset*2)*scale-vw-spec.versionGap*scale
  self:font(spec.footerSize,1,false)
  self.footerMessage=self:translate(tostring(message or ''))
  self.footerShown=type(progress)=='number' and '' or self:fit(self.footerMessage,available)
  self.footerX,self.footerY,self.footerW=ui.ox+spec.inset*scale,ui.oy+y*scale,available
  self.footerH=14*scale
  ui:line(spec.inset,y-3,width-spec.inset,y-3,C.edge,.26)
  if type(progress)=='number' then
   local fraction=math.max(0,math.min(1,progress))
   local pattern=self.language=='JP' and '生成中...%d%%' or 'Generating...%d%%'
   local caption=string.format(pattern,math.floor(fraction*100+.5));local cw=gfx.measurestr(string.format(pattern,100))
   color(C.muted);gfx.x,gfx.y=self.footerX,self.footerY;gfx.drawstr(caption)
   local x=self.footerX+cw+10*scale;local by=self.footerY+3*scale
   local w=math.max(0,math.min(available,(width-48)*scale*.45)-cw-10*scale)
   color(C.field);gfx.rect(x,by,w,6*scale,1);color(C.accent2,.95);gfx.rect(x,by,w*fraction,6*scale,1)
   color(C.muted,.5);gfx.rect(x,by,w,6*scale,0)
  else color(bad and C.warn or C.muted);gfx.x,gfx.y=self.footerX,self.footerY;gfx.drawstr(self.footerShown) end
  self:font(spec.versionSize,3,true);color(C.faint);gfx.x,gfx.y=ui.ox+(width-spec.inset)*scale-vw,self.footerY;gfx.drawstr(ver)
 end
 function S:applyPreset(index)
  if options.stepPreset then options.stepPreset(index<self.preset and -1 or 1);return end
  self.preset=(index-1)%#options.presets+1
  if ui.editor.edit then ui.editor:close(false) end
  options.apply(options.presets[self.preset])
 end
 function S:begin()
  self.theme.tick(api.time_precise())
  self.layout=BLTChrome.layout(gfx.w)
  self.hot=host.hovered and BLTChrome.hit(self.layout,gfx.mouse_x,gfx.mouse_y,gfx.w,spec.barHeight) or nil
  local down=(gfx.mouse_cap&1)~=0
  self.pressed,self.released=down and not self.down,not down and self.down;self.down=down
  if self.pressed and self.hot and not self.popupOpen then
   self.capture=self.hot
   if self.hot=='drag' then
    local mx,my=I.GetMousePos(ctx);local wx,wy=I.GetWindowPos(ctx);host.drag={x=mx-wx,y=my-wy}
   end
  end
  ui.blocked=self.popupOpen or self.hot~=nil or host.drag~=nil or not (host.focused or host.hovered)
 end
 local tips={preset={'プリセットを選択','Choose a preset'},prev={'前のプリセット','Previous preset'},next={'次のプリセット','Next preset'},
  language={'日本語 / English','Japanese / English'},theme={'CHAMELEON：REAPERテーマに擬態','CHAMELEON: match the REAPER theme'},
  reset={'ウィンドウサイズを初期値に戻す','Restore default window size'},close={'閉じる','Close'}}
 local painter={C=C,chrome=chrome,metrics=gfx.measurestr,fit=function(t,w) return S:fit(t,w) end,
  barFont=function() S:font(10,2,false,1) end,languageFont=function() S:font(13,2,true,1) end}
 function S:drawBar()
  local opening=false
  if self.released then
   if self.capture==self.hot then
    if self.hot=='close' then host.requestClose=true
    elseif self.hot=='reset' then host.requestReset=true
    elseif self.hot=='theme' then self.theme.toggle()
    elseif self.hot=='language' then
     self.language=self.language=='JP' and 'EN' or 'JP'
     if options.languageChanged then options.languageChanged(self.language) end
    elseif self.hot=='prev' then self:applyPreset(self.preset-1)
    elseif self.hot=='next' then self:applyPreset(self.preset+1)
    elseif self.hot=='preset' then
     I.OpenPopup(ctx,'BLT_DEMO_PRESETS')
     opening=true
    end
   end
   self.capture=nil
  end
  self.popupOpen=I.IsPopupOpen(ctx,'BLT_DEMO_PRESETS')
  painter.b,painter.hot,painter.language=self.layout,self.hot,self.language
  painter.presetOpen,painter.themeEnabled,painter.dirty=self.popupOpen,self.theme.enabled,options.dirty and options.dirty() or false
  painter.c1,painter.c2,painter.c3=self.theme.icon_colors()
  gfx=self.raster:begin(painter)
  if self.raster.dirty then BLTChrome.draw(painter) end
  gfx=self.textG;self.raster:finish()
  if self.popupOpen then
  local width,height
  if options.presetSize then width,height=options.presetSize();I.SetNextWindowSize(ctx,width,height) end
  if opening then
   I.SetNextWindowPos(ctx,host.originX+(width and math.max(6,gfx.w-width-6) or self.layout.presetX),host.originY+spec.barHeight+2)
  end
  I.PushFont(ctx,host.font,13)
  I.PushStyleVar(ctx,I.StyleVar_WindowPadding,12,10)
  I.PushStyleColor(ctx,I.Col_PopupBg,host.rgba(C.panel[1],C.panel[2],C.panel[3],1))
  I.PushStyleColor(ctx,I.Col_Text,host.rgba(C.text[1],C.text[2],C.text[3],1))
  if I.BeginPopup(ctx,'BLT_DEMO_PRESETS') then
   if options.drawPresets then options.drawPresets(self) else
   for index,preset in ipairs(options.presets) do
    if I.Selectable(ctx,self.language=='JP' and preset.name or preset.nameEN,index==self.preset,0,180,24) then self:applyPreset(index) end
   end
   end
   I.EndPopup(ctx)
  end
  self.popupOpen=I.IsPopupOpen(ctx,'BLT_DEMO_PRESETS')
  I.PopStyleColor(ctx,2);I.PopStyleVar(ctx);I.PopFont(ctx)
  end
  local tip=self.hot and tips[self.hot]
  local footerHot=self.footerShown and self.footerShown~='' and self.footerShown~=self.footerMessage and
   gfx.mouse_x>=self.footerX and gfx.mouse_x<self.footerX+self.footerW and gfx.mouse_y>=self.footerY and gfx.mouse_y<self.footerY+self.footerH
  local hoverID=self.hot or (footerHot and 'footer' or nil)
  local now=api.time_precise()
  if self.hoverID~=hoverID then self.hoverID,self.hoverSince=hoverID,now end
  if tip and not self.down and not self.popupOpen and now-(self.hoverSince or now)>=.7 then
   I.PushFont(ctx,host.font,12);I.SetTooltip(ctx,tip[self.language=='JP' and 1 or 2]);I.PopFont(ctx)
  elseif footerHot and not self.down and not self.popupOpen and now-(self.hoverSince or now)>=.7 then
   I.PushFont(ctx,host.font,12);I.SetTooltip(ctx,self.footerMessage);I.PopFont(ctx)
  end
 end
 function S:close() self.raster:close();self.typography:close() end
 return S
end
return M
end)()

BLT.PresetMenu=(function()
local M={}
function M.new(Host,ui,options)
 local UI={}
 local R=reaper
 local I,ctx,C=Host.I,Host.ctx,ui.C
 local Layout={popup=options.layout}
 local Presets,Language,commit=options.presets,options.language,options.commit
local function presetIcon(draw,kind,x,y,color)
 local function line(a,b,c,d) I.DrawList_AddLine(draw,x+a,y+b,x+c,y+d,color,1) end
 local function box(a,b,w,h) I.DrawList_AddRect(draw,x+a,y+b,x+a+w,y+b+h,color,1) end
 if kind=='cards' then box(0,0,8,9);box(3,3,8,9)
 elseif kind=='folder' then line(0,2,4,2);line(4,2,6,4);line(6,4,12,4);line(12,4,12,12);line(12,12,0,12);line(0,12,0,2)
 elseif kind=='save' or kind=='plus' then
  box(0,0,12,12);box(3,0,5,4);box(3,7,6,5)
  if kind=='plus' then line(10,6,10,12);line(7,9,13,9) end
 elseif kind=='import' or kind=='export' then
  line(0,9,0,13);line(0,13,12,13);line(12,13,12,9)
  if kind=='import' then line(6,0,6,9);line(2,5,6,9);line(6,9,10,5)
  else line(6,9,6,0);line(2,4,6,0);line(6,0,10,4) end
 elseif kind=='check' then line(0,6,4,10);line(4,10,12,1)
 elseif kind=='back' then line(11,6,0,6);line(0,6,4,2);line(0,6,4,10) end
end
function UI:size()
 local p=Layout.popup;local count=math.min(#Presets.items,p.visiblePresets)
 return p.width,p.headerHeight+math.max(7*p.rowHeight+9,(count+1)*p.rowHeight+(#Presets.items>p.visiblePresets and 18 or 0))+10
end
function UI:draw(owner)
 if I.IsWindowAppearing(ctx) then
  commit();UI.presetPage='main';UI.presetHoverAt=nil;UI.contextPreset=nil;UI.presetOffset=0;UI.presetFocused=nil
 end
 if UI.presetPage=='load' and I.IsKeyPressed(ctx,I.Key_LeftArrow,false) then UI.presetPage='main' end
 local current=Presets.current
 local title=UI.presetPage=='load' and Language.text('プリセット') or
  Language.text('現在: ')..(current and (Presets.isFactory(current) and Language.text(current.name) or current.name) or Language.text('未選択'))..(Presets.dirty() and ' *' or '')
 local width=Layout.popup.width-24
 local draw=I.GetWindowDrawList(ctx);local wx,wy=I.GetWindowPos(ctx);local ww,wh=I.GetWindowSize(ctx)
 I.DrawList_PushClipRect(draw,wx+1,wy+1,wx+ww-1,wy+wh-1,false)
 local function text(label,x,y,size,color,alpha,available)
  owner:font(size,1,false,1)
  local draw=Host.draw;Host.draw=I.GetWindowDrawList(ctx)
  owner.typography:draw(owner:fit(label,available),x-Host.originX,y-Host.originY,color[1],color[2],color[3],alpha)
  Host.draw=draw
 end
 local x,y=I.GetCursorScreenPos(ctx)
 text(title,x,y-1,12,C.muted,.9,width)
 I.Dummy(ctx,width,15);I.Separator(ctx)
 local function item(label,icon,action,disabled,navigate)
  disabled=disabled or (options.busy and options.busy())
  local x,y=I.GetCursorScreenPos(ctx);local mint=owner.chrome.mint
  I.PushStyleColor(ctx,I.Col_HeaderHovered,Host.rgba(mint[1],mint[2],mint[3],.18))
  I.PushStyleColor(ctx,I.Col_HeaderActive,Host.rgba(mint[1],mint[2],mint[3],.18))
  I.BeginDisabled(ctx,disabled==true)
  local clicked=I.Selectable(ctx,'##'..label,false,navigate and I.SelectableFlags_NoAutoClosePopups or 0,width,25)
  I.PopStyleColor(ctx,2)
  if I.IsItemVisible(ctx) then
   local draw=I.GetWindowDrawList(ctx)
   local alpha=disabled and .3 or .94;local color=Host.rgba(C.text[1],C.text[2],C.text[3],alpha)
   if not disabled and (I.IsItemHovered(ctx) or I.IsItemFocused(ctx)) then
    I.DrawList_AddRectFilled(draw,x-11,y,x-9,y+Layout.popup.rowHeight,Host.rgba(mint[1],mint[2],mint[3],.8))
   end
   presetIcon(draw,icon,x+1,y+8,color)
   text(label,x+27,y+7,13,C.text,alpha,width-42)
   if icon=='folder' then
    I.DrawList_AddLine(draw,x+width-6,y+10,x+width-2,y+14,color,1)
    I.DrawList_AddLine(draw,x+width-2,y+14,x+width-6,y+18,color,1)
   end
  end
  I.EndDisabled(ctx)
  if clicked then
   if navigate then UI.presetHoverAt=nil;action() else commit();action() end
  end
  return clicked
 end
 if UI.presetPage=='load' then
  item(Language.text('戻る'),'back',function() UI.presetPage='main' end,false,true)
  if I.IsItemFocused(ctx) then UI.presetFocused=nil end
  local visible=Layout.popup.visiblePresets;local offset=UI.presetOffset or 0
  local x,y=I.GetCursorScreenPos(ctx)
  if I.IsMouseHoveringRect(ctx,x-11,y,x+width+11,y+visible*Layout.popup.rowHeight) then
   local wheel=I.GetMouseWheel(ctx)
   if wheel~=0 then offset=offset+(wheel>0 and -1 or 1) end
  end
  local focused=UI.presetFocused;local target
  if focused then
   if I.IsKeyPressed(ctx,I.Key_DownArrow,true) and focused==offset+visible and focused<#Presets.items then target=focused+1;offset=offset+1
   elseif I.IsKeyPressed(ctx,I.Key_UpArrow,true) and focused==offset+1 and offset>0 then target=focused-1;offset=offset-1 end
  end
  offset=math.max(0,math.min(math.max(0,#Presets.items-visible),offset));UI.presetOffset=offset
  I.PushID(ctx,'INTERVAL_SAVED_PRESETS')
  for index=offset+1,math.min(#Presets.items,offset+visible) do
    local p=Presets.items[index]
    if not p then break end
    if target==index then I.SetKeyboardFocusHere(ctx) end
    item(p.name,current and current.name==p.name and 'check' or 'cards',function() Presets.apply(p);I.CloseCurrentPopup(ctx) end)
    if I.IsItemFocused(ctx) then UI.presetFocused=index end
    if I.IsItemClicked(ctx,1) then UI.contextPreset=p;I.OpenPopup(ctx,'INTERVAL_DELETE_PRESET') end
    if UI.contextPreset==p and I.BeginPopup(ctx,'INTERVAL_DELETE_PRESET') then
     if I.Selectable(ctx,Language.code=='EN' and 'Delete' or '削除',false,0,120,24) then
      Presets.remove(p);UI.contextPreset=nil;if #Presets.items==0 then UI.presetPage='main' end
     end
     I.EndPopup(ctx)
    end
  end
  I.PopID(ctx)
  if #Presets.items>visible then
   local x,y=I.GetCursorScreenPos(ctx)
   text(Language.message(string.format('%d–%d / %d   スクロールで選択',offset+1,math.min(#Presets.items,offset+visible),#Presets.items)),x,y,10,C.muted,.8,width)
   I.Dummy(ctx,width,14)
  end
  I.DrawList_PopClipRect(draw)
  return
 end
 item(Language.text(Presets.factory.name),Presets.isFactory(current) and 'check' or 'cards',function() Presets.apply(Presets.factory) end)
 item(Language.text('プリセット'),'folder',function() UI.presetPage='load' end,#Presets.items==0,true)
 if #Presets.items>0 and I.IsItemHovered(ctx) and not I.IsMouseDown(ctx,0) then
  local now=R.time_precise();UI.presetHoverAt=UI.presetHoverAt or now
  if now-UI.presetHoverAt>=Layout.popup.hoverDelay then UI.presetPage='load';UI.presetHoverAt=nil end
 else UI.presetHoverAt=nil end
 item(Language.text('上書き保存'),'save',function() Presets.save(false) end,Presets.isFactory(current))
 item(Language.text('名前を付けて保存…'),'plus',function() Presets.save(true) end)
 I.Separator(ctx)
 item(Language.text('インポート…'),'import',Presets.import)
 item(Language.text('現在値をエクスポート'),'export',function() Presets.export(false) end,Presets.isFactory(current))
 item(Language.text('プリセット一覧をエクスポート'),'export',function() Presets.export(true) end,#Presets.items==0)
 I.DrawList_PopClipRect(draw)
end
 return UI
end
return M
end)()

BLT.EnvelopeWidgets=(function()
local M={}
local min,max,floor=math.min,math.max,math.floor
local empty={}
function M.fit(color,bg,text)
 local function luma(c) return c[1]*.2126+c[2]*.7152+c[3]*.0722 end
 local level,base=luma(color),luma(bg)
 if math.abs(level-base)>=.17 then return {color[1],color[2],color[3]} end
 local target=luma(text)>base and min(.78,base+.28) or max(.16,base-.30)
 local weight=target<level and (level-target)/max(level,1e-9) or (target-level)/max(1-level,1e-9)
 local toward=target<level and 0 or 1
 return {color[1]+(toward-color[1])*weight,color[2]+(toward-color[2])*weight,color[3]+(toward-color[3])*weight}
end
function M.new(host,ui,density)
 local V={options={},palettes=setmetatable({}, {__mode='k'}),bounds={}};local C=ui.C
 function V:tone(tone)
  if not tone then return C end
  local palette=self.palettes[tone]
  if not palette then palette={accent={},ice={}};self.palettes[tone]=palette end
  for key,c in pairs(C) do if key~='accent' and key~='ice' then palette[key]=c end end
  for i=1,3 do palette.accent[i]=tone[i]*.76;palette.ice[i]=tone[i] end
  return palette
 end
 function V:button(id,text,x,y,w,h,enabled,selected,tone,options)
  local opt=self.options[id] or {};self.options[id]=opt
  opt.enabled,opt.selected=enabled~=false,selected
  opt.led,opt.ledScale=selected~=nil and 'left' or nil,h/(44*density)
  opt.size,opt.bold,opt.labelInset=14/density,true,5/density
  opt.variant,opt.attention=nil,nil
  if options then for key,value in pairs(options) do opt[key]=value end end
  ui.C=self:tone(tone)
  local click=ui:button(id,text,x/density,y/density,w/density,h/density,opt)
  ui.C=C
  return click
 end
 function V:panel(x,y,w,h,tone)
  local opt=self.panelOptions or {glow=false,panel=true};self.panelOptions=opt
  opt.palette=self:tone(tone)
  ui:frame(x/density,y/density,w/density,h/density,opt)
 end
 function V:outline(x,y,w,h,palette)
  x,y,w,h=x/density,y/density,w/density,h/density
  local right,bottom=x+w-1,y+h-1
  local k=min(10,floor(h*.21),floor((h-1)/3),floor((w-1)/3))
  local points=self.outlinePoints or {{},{},{},{},{},{}};self.outlinePoints=points
  points[1][1],points[1][2]=x,y
  points[2][1],points[2][2]=right-k,y
  points[3][1],points[3][2]=right,y+k
  points[4][1],points[4][2]=right,bottom
  points[5][1],points[5][2]=x+k,bottom
  points[6][1],points[6][2]=x,bottom-k
  local light=self.outlineLight or {};self.outlineLight=light
  light.ice,light.spark=palette.ice,palette.ice
  for i,p in ipairs(points) do
   local q=points[i%6+1]
   ui:lightLine(p[1],p[2],q[1],q[2],light,palette.ice,1,.02,.08,.50)
  end
 end
 function V:number(id,value,x,y,w,h,enabled,options)
  options=options or empty
  local active=ui.editor.edit and ui.editor.edit.id==id
  ui:fieldFrame(id,x/density,y/density,w/density,h/density,enabled,active or ui.focus==id)
  local b=self.bounds[id] or {hit={}};self.bounds[id]=b
  local unit=ui.scale/density
  b.x,b.y=ui.ox+(x+(options.left or 64))*unit,ui.oy+y*unit
  b.w,b.h=(w-(options.left or 64)-(options.right or 24))*unit,h*unit
  b.size=max(7,floor((options.size or 14)*unit+.5))
  b.face,b.bold,b.number,b.align,b.opticalCenter=host.faces[3],true,true,'right',true
  b.hit.x,b.hit.y,b.hit.w,b.hit.h=ui.ox+x*unit,ui.oy+y*unit,w*unit,h*unit
  ui.editor:queue(id,value,b,enabled)
 end
 return V
end
return M
end)()

BLT.EnvelopeCanvas=(function()
local M={}
local min,max,floor,ceil=math.min,math.max,math.floor,math.ceil
local function byte(v) return floor(max(0,min(1,v))*255+.5) end
local function geometry(cache,curve,g,view,span,layer,range,revision)
 local changed=not cache.ready or cache.points~=curve.points or cache.pointCount~=#curve.points or
  cache.kind~=curve.kind or cache.smoothness~=curve.smoothness or cache.filter~=curve.filter or
  cache.x~=g.x or cache.y~=g.y or cache.w~=g.w or cache.h~=g.h or
  cache.view~=view or cache.span~=span or cache.layer~=layer or cache.range~=range or cache.revision~=revision
 cache.points,cache.pointCount,cache.kind,cache.smoothness,cache.filter=curve.points,#curve.points,curve.kind,curve.smoothness,curve.filter
 cache.x,cache.y,cache.w,cache.h=g.x,g.y,g.w,g.h
 cache.view,cache.span,cache.layer,cache.range,cache.revision=view,span,layer,range,revision
 return changed
end
function M.new(host,api,C)
 local V={};local G={};V.g=G
 local bitmap,image,width,height,dpi,color,alpha
 local keys={'field','edge','muted','accent2','text'}
 local signature={}
 function G.set(r,g,b,a) color=0xff000000|(byte(r)<<16)|(byte(g)<<8)|byte(b);alpha=a or 1 end
 function G.rect(x,y,w,h) api.JS_LICE_FillRect(bitmap,floor(x*dpi+.5),floor(y*dpi+.5),max(1,ceil(w*dpi)),max(1,ceil(h*dpi)),color,alpha,'COPY') end
 function G.line(x,y,xx,yy,aa) api.JS_LICE_Line(bitmap,x*dpi,y*dpi,xx*dpi,yy*dpi,color,alpha,'COPY',aa~=0) end
 function G.circle(x,y,r) api.JS_LICE_FillCircle(bitmap,x*dpi,y*dpi,r*dpi,color,alpha,'COPY',true) end
 function G.bitmap(source,x,y,w,h,srcx,srcy,srcw,srch,opacity)
  api.JS_LICE_ScaledBlit(bitmap,floor(x*dpi+.5),floor(y*dpi+.5),max(1,ceil(w*dpi)),max(1,ceil(h*dpi)),source,srcx,srcy,srcw,srch,opacity or 1,'COPY')
 end
 function V:begin(w,h,scale,revision,tones)
  dpi=ceil(host.dpi or 1)*scale
  local iw,ih=max(1,ceil(w*dpi)),max(1,ceil(h*dpi))
  local changed=not image or not self.valid or self.revision~=revision or self.scale~=dpi or width~=iw or height~=ih
  local index=0
  local function check(c)
   for i=1,3 do index=index+1;if signature[index]~=c[i] then signature[index]=c[i];changed=true end end
  end
  for _,key in ipairs(keys) do check(C[key]) end
  for _,tone in ipairs(tones) do check(tone.color) end
  if not changed then return false end
  self.valid=false;self.revision,self.scale=revision,dpi
  if not bitmap then bitmap=assert(api.JS_LICE_CreateBitmap(true,iw,ih),'Curve bitmap creation failed')
  elseif iw~=width or ih~=height then api.JS_LICE_Resize(bitmap,iw,ih) end
  width,height=iw,ih
  api.JS_LICE_Clear(bitmap,0xff000000)
  return true
 end
 function V:finish()
  api.JS_LICE_ProcessRect(bitmap,0,0,width,height,'SET_A',0xff000000)
  if image then host:releaseImage(image) end
  image=host.I.CreateImageFromLICE(bitmap);host:attachImage(image);self.valid=true
 end
 function V:draw(x,y,w,h)
  host.I.DrawList_AddImage(host.draw,image,host.originX+x,host.originY+y,host.originX+x+w,host.originY+y+h)
 end
 function V:nearest(curve,g,view,span,layer,range,revision,mx,my,scale,toAxis)
  local pad=14/scale
  if mx<g.x-pad or mx>g.x+g.w+pad or my<g.y-pad or my>g.y+g.h+pad then return end
  local cache=self.nodes or {pointsXY={}};self.nodes=cache
  local changed=geometry(cache,curve,g,view,span,layer,range,revision) or cache.axis~=toAxis
  if changed then
   cache.axis=toAxis
   for i,p in ipairs(curve.points) do
    local ay=toAxis(layer,p.y);local point=cache.pointsXY[i] or {};cache.pointsXY[i]=point
    point[1],point[2]=g.x+(p.x-view)/span*g.w,g.y+(1-ay)*g.h/2
    point[3]=p.x>=view-1e-9 and p.x<=view+span+1e-9 and math.abs(ay)<=1
   end
   cache.ready=true
  elseif cache.mx==mx and cache.my==my and cache.scale==scale then return cache.nearest end
  local best,dist=nil,14*14
  for i=1,cache.pointCount do
   local p=cache.pointsXY[i]
   if p[3] then
    local dd=((mx-p[1])*scale)^2+((my-p[2])*scale)^2
    if dd<=dist then best,dist=i,dd end
   end
  end
  cache.mx,cache.my,cache.scale,cache.nearest=mx,my,scale,best
  return best
 end
 function V:close()
  if image then host:releaseImage(image);image=nil end
  if bitmap then api.JS_LICE_DestroyBitmap(bitmap);bitmap=nil end
 end
 return V
end
return M
end)()

BLT.EnvelopeSpectrogram=(function()
local M={SR=48000,N=8192,ROWS=384,MIN_COLUMNS=512,MAX_COLUMNS=2048,HOP=256,HIGH=24000}
local min,max,floor,ceil,log=math.min,math.max,math.floor,math.ceil,math.log
local byte=string.byte
M.scales={{id='linear',name='Linear'},{id='mel',name='Mel'},{id='bark',name='Bark'},{id='log',name='Log'},{id='extended_log',name='Extended Log'}}
local definitions={};for i,scale in ipairs(M.scales) do scale.index=i;definitions[scale.id]=scale end
local total_rows=M.ROWS*#M.scales
local pack_format='<'..string.rep('f',total_rows)
function M.scale_id(id) return definitions[id] and id or 'log' end
function M.scale_name(id) return definitions[M.scale_id(id)].name end
function M.low(id) return id=='log' and 100 or id=='extended_log' and 10 or 0 end
local function transform(hz,id)
 if id=='linear' then return hz
 elseif id=='mel' then return log(1+hz/700)
 elseif id=='bark' then local x=hz/650;return log(x+math.sqrt(x*x+1)) end
 return log(max(M.low(id),hz))
end
function M.position(hz,id)
 id=M.scale_id(id);local low=transform(M.low(id),id)
 return (transform(hz,id)-low)/(transform(M.HIGH,id)-low)
end
function M.frequency(position,id)
 id=M.scale_id(id);local low=transform(M.low(id),id)
 local value=low+position*(transform(M.HIGH,id)-low)
 if id=='linear' then return value
 elseif id=='mel' then return 700*(math.exp(value)-1)
 elseif id=='bark' then return 325*(math.exp(value)-math.exp(-value)) end
 return math.exp(value)
end
local window,band_cache=nil,{}
local function reference_window()
 if not window then window={};for i=0,M.N-1 do window[i+1]=.5-.5*math.cos(2*math.pi*i/(M.N-1)) end end
 return window
end
local function bands_for(id)
 if band_cache[id] then return band_cache[id] end
 local bands={}
 for row=1,M.ROWS do
  local lo,hi=M.frequency((row-1)/M.ROWS,id),M.frequency(row/M.ROWS,id)
  local first,last=max(1,ceil(lo*M.N/M.SR)),min(M.N//2-1,floor(hi*M.N/M.SR))
  if last<first then first=max(1,min(M.N//2-1,floor(M.frequency((row-.5)/M.ROWS,id)*M.N/M.SR+.5)));last=first end
  bands[row]={first,last}
 end
 band_cache[id]=bands;return bands
end
local stops={{.010,.020,.042},{.045,.080,.240},{.180,.200,.540},{.440,.300,.780},{.290,.640,.910},{.790,.940,1}}
local crc_table={}
for i=0,255 do
 local c=i;for _=1,8 do c=(c>>1)~((c&1)==1 and 0xedb88320 or 0) end;crc_table[i]=c
end
local crc1,crc2,crc3={},{},{}
for i=0,255 do
 local c=crc_table[i];c=(c>>8)~crc_table[c&255];crc1[i]=c
 c=(c>>8)~crc_table[c&255];crc2[i]=c
 c=(c>>8)~crc_table[c&255];crc3[i]=c
end
local function crc(bytes,value)
 local c=value or 0xffffffff;local size=#bytes;local i=1
 while i+3<=size do
  local a,b,d,e=byte(bytes,i,i+3);c=c~(a|(b<<8)|(d<<16)|(e<<24))
  c=crc3[c&255]~crc2[(c>>8)&255]~crc1[(c>>16)&255]~crc_table[c>>24];i=i+4
 end
 for k=i,size do c=(c>>8)~crc_table[(c~byte(bytes,k))&255] end
 return c
end
local function chunk(kind,bytes)
 return string.pack('>I4',#bytes)..kind..bytes..string.pack('>I4',crc(bytes,crc(kind))~0xffffffff)
end
local png_signature='\137PNG\13\10\26\10'
local png_end=chunk('IEND','')
local default_palette
local function mix(a,b,t) return {a[1]+(b[1]-a[1])*t,a[2]+(b[2]-a[2])*t,a[3]+(b[3]-a[3])*t} end
function M.configure_palette(C,enabled)
 if not enabled and default_palette then
  local changed=M.palette~=default_palette;M.palette=default_palette;return changed
 end
 local colors=stops
 if enabled then
  local base=mix(C.field,C.bg,.25);local accent=C.accent;local high=C.accent2
  colors={base,mix(base,accent,.18),mix(base,accent,.45),mix(base,accent,.8),mix(accent,high,.35),mix(high,C.text,.8)}
 end
 local bytes={}
 for i=0,255 do
  local t=i/255*(#colors-1);local a=min(#colors-1,floor(t)+1);local f=t-(a-1)
  for k=1,3 do bytes[#bytes+1]=floor(max(0,min(1,colors[a][k]+(colors[a+1][k]-colors[a][k])*f))*255+.5) end
 end
 local plte=chunk('PLTE',string.char(table.unpack(bytes)))
 if M.palette and M.palette.chunk==plte then return false end
 M.palette={chunk=plte};if not enabled then default_palette=M.palette end;return true
end
M.configure_palette(nil,false)
local color_processor=[[
function png_crc_byte(value) local(high) (
 high=floor(crc_value/256);
 crc_value=high ~ crc_table[(crc_value-high*256) ~ value];
 crc_value<0 ? crc_value+=4294967296;
);
function png_put(value) (
 str_setchar(#block,strlen(#block),value);png_crc_byte(value);
);
function png_put32(word) local(c a b d e high) (
 word>=2147483648 ? word-=4294967296;
 str_setchar(#block,strlen(#block),word,'i');
 c=crc_value>=2147483648 ? crc_value-4294967296 : crc_value;
 c=c ~ word;c<0 ? c+=4294967296;
 high=floor(c/256);a=c-high*256;c=high;
 high=floor(c/256);b=c-high*256;c=high;
 high=floor(c/256);d=c-high*256;e=high;
 crc_value=crc3[a] ~ crc2[b] ~ crc1[d] ~ crc_table[e];
 crc_value<0 ? crc_value+=4294967296;
);
maxima=0;crc_table=groups;crc1=crc_table+256;crc2=crc1+256;crc3=crc2+256;pixels=crc3+256;
operation<0 ? memset(pixels,0,rows*columns) : operation==0 ? (
 row=0;loop(rows,
  maximum=maxima[floor(row/height)];
  value=floor(min(1,max(0,(10*log(max(str_getchar(#power,row*4,'f'),power_floor)/max(maximum,normal_floor))/log(10)+80)/80))*255+0.5);
  pixels[row*columns+column_index]=value;row+=1;
 );
) : (
 strcpy(#block,"");loop(min(row_count,height-row_index),
 row_index==0 ? (crc_value=crc_start;adler_a=1;adler_b=0;);
 n=columns+1;
 png_put(row_index==height-1);png_put(n%256);png_put(floor(n/256));
 n=65535-n;png_put(n%256);png_put(floor(n/256));png_put(0);
 adler_b+=adler_a;source=(scale_index*height+height-1-row_index)*columns;x=0;
 loop(floor(columns/4),
  p0=pixels[source+x];p1=pixels[source+x+1];p2=pixels[source+x+2];p3=pixels[source+x+3];
  png_put32(p0+p1*256+p2*65536+p3*16777216);
  adler_b+=4*adler_a+4*p0+3*p1+2*p2+p3;adler_a+=p0+p1+p2+p3;x+=4;
 );
 loop(columns-x,value=pixels[source+x];png_put(value);adler_a+=value;adler_b+=adler_a;x+=1;);
 adler_a%=65521;adler_b%=65521;
 row_index==height-1 ? (
  png_put(floor(adler_b/256));png_put(adler_b%256);png_put(floor(adler_a/256));png_put(adler_a%256);
  png_crc=4294967295-crc_value;
 );
 row_index+=1;
 );
);
]]
local processor=[[
input=0; spectrum=block*channels; window=spectrum+n; low=window+n; high=low+rows; output=high+rows; maxima=output+rows; bins=maxima+rows/height;
operation==0 ? (
 memset(maxima,0,rows/height);i=0;loop(n,window[i]=0.5-0.5*cos(2*$pi*i/(n-1));i+=1;);
) : operation==1 ? (
 memset(spectrum,0,n);i=0;
 loop(count,p=i+offset;spectrum[p]=input[(i+source_offset)*channels+channel]*window[p];i+=1;);
) : (
 k=1;loop(n/2-1,re=spectrum[2*k];im=spectrum[2*k+1];bins[k]=re*re+im*im;k+=1;);
 channel==channels-1 ? strcpy(#power,"");
 row=0;loop(rows,
  k=low[row];peak=0;
  loop(high[row]-k+1,peak=max(peak,bins[k]);k+=1;);
  output[row]=(channel==0 ? 0 : output[row])+peak/channels;
  group=floor(row/height);maxima[group]=max(maxima[group],output[row]);
  channel==channels-1 ? str_setchar(#power,row*4,output[row],'f');row+=1;
 );
);
]]
local function stop_processor(j)
 if j.processor then j.host.I.Detach(j.host.ctx,j.processor);j.processor=nil end
end
local function start_processor(api,j,quantizing)
 if not j.host then return end
 local I=j.host.I
 local ok,fn=pcall(I.CreateFunctionFromEEL,quantizing and color_processor or processor)
 if not ok or not fn then return end
 j.processor=fn;I.Attach(j.host.ctx,fn)
 local values=quantizing and {maxima=0,crc_table=#M.scales,rows=total_rows,height=M.ROWS,groups=#M.scales,
  columns=j.columns,row_count=max(1,floor(8192/(j.columns+6))),operation=0,power_floor=1e-30,normal_floor=1e-20,crc_start=crc('\120\1',crc('IDAT'))}
  or {n=M.N,rows=total_rows,height=M.ROWS,block=j.block,channels=j.channels,operation=0}
 for name,value in pairs(values) do I.Function_SetValue(fn,name,value) end
 if not quantizing then
  I.Function_Execute(fn)
  local first,last={},{};for row,band in ipairs(j.bands) do first[row],last[row]=band[1],band[2] end
  I.Function_SetValue_Array(fn,'low',api.new_array(first));I.Function_SetValue_Array(fn,'high',api.new_array(last))
 end
 if quantizing then
  I.Function_SetValue_Array(fn,'maxima',api.new_array(j.data.maxima))
  local values={}
  for _,table in ipairs({crc_table,crc1,crc2,crc3}) do
   for i=0,255 do local c=table[i];values[#values+1]=c>=0x80000000 and c-0x100000000 or c end
  end
  I.Function_SetValue_Array(fn,'crc_table',api.new_array(values));j.native_encoding=true;j.encode_batch=max(1,floor(8192/(j.columns+6)))
  if j.coverage then I.Function_SetValue(fn,'operation',-1);I.Function_Execute(fn);I.Function_SetValue(fn,'operation',0) end
 end
end
function M.start(v,view,span,map,lookup,scale,host,reader,coverage)
 local duration=map and lookup(map,view+span,'u','t')-lookup(map,view,'u','t') or v.len*span
 local columns=coverage and coverage.columns or max(M.MIN_COLUMNS,min(M.MAX_COLUMNS,ceil(duration*M.SR/M.HOP)))
 local bands={};for _,choice in ipairs(M.scales) do for _,band in ipairs(bands_for(choice.id)) do bands[#bands+1]=band end end
 return {v=v,view=view,span=span,map=map,lookup=lookup,host=host,reader=reader,coverage=coverage,scale=M.scale_id(scale),bands=bands,index=0,channel=1,phase='read',kind='analysis',
  columns=columns,channels=min(64,v.channels),data={columns=columns,view=view,span=span,frames={},pngs={},maxima={0,0,0,0,0}}}
end
function M.render(v,data,scale,host)
 assert(data.complete,'Spectrogram analysis is incomplete')
 return {v=v,view=data.view,span=data.span,columns=data.columns,host=host,scale=M.scale_id(scale),data=data,index=0,phase='paint',kind='render',
  done=data.empty or nil,palette=data.empty and M.palette or nil}
end
function M.release(api,result)
 if result and result.bitmap then api.JS_LICE_DestroyBitmap(result.bitmap);result.bitmap=nil end
 if result then result.data=nil end
end
function M.cancel(api,j)
 if not j then return end
 if j.accessor then local aa=j.accessor;j.accessor=nil;api.DestroyAudioAccessor(aa) end
 stop_processor(j);M.release(api,j);j.buffer=nil;j.fft=nil;j.values=nil;j.time=nil;j.power=nil;j.bin_power=nil;j.bands=nil;j.blocks=nil;j.row_bytes=nil;j.native_encoding=nil;j.data=nil
 j.read_cache=nil;j.stitch=nil;j.input_buffer=nil;j.coverage=nil
end
function M.create_accessor(api,v)
 local mute=api.GetMediaItemInfo_Value(v.item,'B_MUTE')
 if mute==0 then return api.CreateTakeAudioAccessor(v.take) end
 assert(api.SetMediaItemInfo_Value(v.item,'B_MUTE',0),'解析用のミュート除外に失敗しました。')
 local ok,aa=pcall(api.CreateTakeAudioAccessor,v.take)
 local restored=api.SetMediaItemInfo_Value(v.item,'B_MUTE',mute)
 if not restored then if ok and aa then api.DestroyAudioAccessor(aa) end;error('アイテムのミュート状態を復元できません。',0) end
 if not ok then error(aa,0) end
 return aa
end
local function sparse_block(api,j,range,first,last)
 local cache=j.read_cache
 for i,entry in ipairs(cache) do
  if entry.range==range and entry.first<=first and entry.first+entry.count>=last then
   if i>1 then table.remove(cache,i);table.insert(cache,1,entry) end
   return entry
  end
 end
 local entry=#cache>=2 and table.remove(cache) or {buffer=#cache==0 and j.buffer or api.new_array(j.block*j.channels)}
 entry.range=range;entry.first=first;entry.count=min(j.block,range.last-first);entry.buffer.clear()
 local rc=api.GetAudioAccessorSamples(j.accessor,M.SR,j.channels,j.first+first/M.SR,entry.count,entry.buffer)
 assert(type(rc)=='number' and rc>=0,'スペクトログラムの音声読み出しに失敗しました。')
 j.read_serial=(j.read_serial or 0)+1;entry.version=j.read_serial
 entry.values=not j.processor and entry.buffer.table(1,entry.count*j.channels) or nil
 table.insert(cache,1,entry);return entry
end
local function read_sparse_column(api,j)
 local centers,ranges=j.coverage.centers,j.coverage.ranges
 if centers[j.index+1]==false then
  repeat j.index=j.index+1;j.data.frames[j.index]=false until j.index==j.columns or centers[j.index+1]~=false
  return false
 end
 local start=centers[j.index+1]-M.N//2;local finish=start+M.N
 local lo,hi=1,#ranges
 while lo<hi do local mid=(lo+hi)//2;if ranges[mid].last<=start then lo=mid+1 else hi=mid end end
 local range=ranges[lo];local first,last=max(start,range.first),min(finish,range.last)
 local buffer,version
 if not ranges[lo+1] or ranges[lo+1].first>=finish then
  local entry=sparse_block(api,j,range,first,last)
  buffer,version=entry.buffer,entry.version;j.values=entry.values
  j.offset,j.count,j.source_offset=first-start,last-first,first-entry.first
 else
  j.stitch=j.stitch or api.new_array(M.N*j.channels);j.stitch.clear()
  repeat
   range=ranges[lo];first,last=max(start,range.first),min(finish,range.last)
   local entry=sparse_block(api,j,range,first,last)
   j.stitch.copy(entry.buffer,(first-entry.first)*j.channels+1,(last-first)*j.channels,(first-start)*j.channels+1)
   lo=lo+1
  until not ranges[lo] or ranges[lo].first>=finish
  buffer=j.stitch;j.read_serial=(j.read_serial or 0)+1;version=j.read_serial
  j.values=not j.processor and buffer.table(1,M.N*j.channels) or nil
  j.offset,j.count,j.source_offset=0,M.N,0
 end
 if j.processor then
  local I=j.host.I
  if j.input_buffer~=buffer or j.input_version~=version then I.Function_SetValue_Array(j.processor,'input',buffer);j.input_buffer,j.input_version=buffer,version end
  I.Function_SetValue(j.processor,'offset',j.offset);I.Function_SetValue(j.processor,'count',j.count);I.Function_SetValue(j.processor,'source_offset',j.source_offset)
 else j.power={};for row=1,total_rows do j.power[row]=0 end end
 j.column_ready=true;return true
end
local function read_column(api,j)
 if j.coverage then return read_sparse_column(api,j) end
 local u=j.view+(j.index+.5)/j.columns*j.span
 local t=j.map and j.lookup(j.map,u,'u','t') or u*j.v.len
 local start=floor(t*M.SR-M.N/2);local requested=max(0,start)
 local offset=max(0,-start);local count=max(0,min(M.N-offset,j.samples-requested))
 j.offset,j.count=offset,count
 if count>0 and (not j.block_start or requested<j.block_start or requested+count>j.block_start+j.block_count) then
  j.block_start=requested;j.block_count=min(j.block,j.samples-requested);j.buffer.clear()
  local rc=api.GetAudioAccessorSamples(j.accessor,M.SR,j.channels,j.first+requested/M.SR,j.block_count,j.buffer)
  assert(type(rc)=='number' and rc>=0,'スペクトログラムの音声読み出しに失敗しました。')
  if j.processor then j.host.I.Function_SetValue_Array(j.processor,'input',j.buffer)
  else j.values=j.buffer.table(1,j.block_count*j.channels) end
 end
 j.source_offset=requested-(j.block_start or requested);j.column_ready=true
 if j.processor then
  local I=j.host.I
  I.Function_SetValue(j.processor,'offset',offset);I.Function_SetValue(j.processor,'count',count)
  I.Function_SetValue(j.processor,'source_offset',j.source_offset)
 else j.power={};for row=1,total_rows do j.power[row]=0 end end
 return true
end
local function channel_fft(j)
 if j.processor then
  local I=j.host.I
  I.Function_SetValue(j.processor,'channel',j.channel-1);I.Function_SetValue(j.processor,'operation',1);I.Function_Execute(j.processor)
  I.Function_GetValue_Array(j.processor,'spectrum',j.fft);j.fft.fft_real(M.N,true)
  I.Function_SetValue_Array(j.processor,'spectrum',j.fft)
  I.Function_SetValue(j.processor,'operation',2);I.Function_Execute(j.processor)
 else
  local window=reference_window()
  for n=0,M.N-1 do
   local i=n-j.offset
   j.time[n+1]=(i>=0 and i<j.count and j.values[(i+j.source_offset)*j.channels+j.channel] or 0)*window[n+1]
  end
  j.fft.copy(j.time);j.fft.fft_real(M.N,true)
  local fft=j.fft.table(1,M.N);local bins=j.bin_power
  for k=1,M.N//2-1 do local re,im=fft[2*k+1],fft[2*k+2];bins[k]=re*re+im*im end
  -- Average channel powers without cancelling anti-phase stereo.
  for row,band in ipairs(j.bands) do
   local peak=0
   for k=band[1],band[2] do peak=max(peak,bins[k]) end
   j.power[row]=j.power[row]+peak/j.channels
  end
 end
 j.channel=j.channel+1
 if j.channel>j.channels then
  local frame
  if j.processor then
   frame=j.host.I.Function_GetValue_String(j.processor,'#power')
   assert(#frame==total_rows*4,'Spectrogram power transfer failed')
  else
   for row,power in ipairs(j.power) do local group=(row-1)//M.ROWS+1;j.data.maxima[group]=max(j.data.maxima[group],power) end
   frame=string.pack(pack_format,table.unpack(j.power))
  end
  j.index=j.index+1;j.channel=1;j.data.frames[j.index]=frame;j.power=nil;j.column_ready=false
 end
end
local zero_column=string.rep('\0',total_rows)
local function quantize_column(j)
 if j.data.frames[j.index+1]==false then
  repeat
   j.index=j.index+1;j.data.frames[j.index]=not j.processor and zero_column or nil
  until j.index==j.columns or j.data.frames[j.index+1]~=false
  return
 end
 if j.processor then
  local I=j.host.I;I.Function_SetValue_String(j.processor,'#power',j.data.frames[j.index+1])
  I.Function_SetValue(j.processor,'column_index',j.index);I.Function_Execute(j.processor)
  j.data.frames[j.index+1]=nil
 else
  local values={string.unpack(pack_format,j.data.frames[j.index+1])};values[total_rows+1]=nil
  for row,power in ipairs(values) do
   local maximum=j.data.maxima[(row-1)//M.ROWS+1]
   values[row]=floor(max(0,min(1,(10*log(max(power,1e-30)/max(maximum,1e-20),10)+80)/80))*255+.5)
  end
  j.data.frames[j.index+1]=string.char(table.unpack(values))
 end
 j.index=j.index+1
end
local function encode_row(j)
 if not j.blocks then
  j.blocks={'\120\1'}
  if j.native_encoding then
   j.host.I.Function_SetValue(j.processor,'scale_index',j.scale_index-1);j.host.I.Function_SetValue(j.processor,'row_index',0)
  else
   j.png_crc=crc(j.blocks[1],crc('IDAT'));j.adler_a,j.adler_b=1,0;j.row_bytes={0}
  end
 end
 if j.native_encoding then
  local I=j.host.I;local fn=j.processor
  I.Function_Execute(fn)
  local count=min(M.ROWS-j.index,j.encode_batch);local block=I.Function_GetValue_String(fn,'#block')
  assert(#block==count*(j.columns+6)+(j.index+count==M.ROWS and 4 or 0),'Spectrogram image transfer failed')
  j.blocks[#j.blocks+1]=block;j.index=j.index+count
 else
  local row=(j.scale_index-1)*M.ROWS+M.ROWS-j.index;local bytes=j.row_bytes;local frames=j.data.frames
  local a,b=j.adler_a,j.adler_b+j.adler_a -- PNG filter byte is zero.
  for x=1,j.columns do local value=byte(frames[x],row);bytes[x+1]=value;a=a+value;b=b+a end
  j.adler_a,j.adler_b=a%65521,b%65521
  local raw=string.char(table.unpack(bytes));local n=#raw
  local block=string.pack('<BI2I2',j.index==M.ROWS-1 and 1 or 0,n,0xffff-n)..raw
  j.blocks[#j.blocks+1]=block;j.png_crc=crc(block,j.png_crc);j.index=j.index+1
 end
 if j.index==M.ROWS then
  local checksum
  if j.native_encoding then checksum=j.host.I.Function_GetValue(j.processor,'png_crc')
  else
   local tail=string.pack('>I4',(j.adler_b<<16)|j.adler_a);j.blocks[#j.blocks+1]=tail
   checksum=crc(tail,j.png_crc)~0xffffffff
  end
  local payload=table.concat(j.blocks)
  j.data.pngs[M.scales[j.scale_index].id]=string.pack('>I4',#payload)..'IDAT'..payload..string.pack('>I4',checksum)
  j.blocks=nil;j.row_bytes=nil;j.scale_index=j.scale_index+1;j.index=0
  if j.scale_index>#M.scales then
   stop_processor(j);j.native_encoding=nil
   j.data.header=png_signature..chunk('IHDR',string.pack('>I4I4BBBBB',j.columns,M.ROWS,8,3,0,0,0))
   j.data.frames=nil;j.data.maxima=nil;j.data.complete=true;j.phase='paint'
  end
 end
end
local function paint(api,j)
 local png=j.data.header..M.palette.chunk..j.data.pngs[j.scale]..png_end
 j.bitmap=assert(api.JS_LICE_LoadPNGFromMemory(png,#png),'Spectrogram image creation failed')
 j.palette=M.palette;j.index=j.columns;j.done=true
end
function M.step(api,j,budget)
 if j.done then return true end
 local deadline=api.time_precise()+(budget or .003);local work=0
 if not j.accessor and j.phase=='read' then
  if j.reader then j.accessor,j.first,j.last=j.reader(api,j.v,j.coverage)
  else
   j.accessor=M.create_accessor(api,j.v)
   if j.accessor then j.first=api.GetAudioAccessorStartTime(j.accessor);j.last=api.GetAudioAccessorEndTime(j.accessor) end
  end
  assert(j.accessor,'スペクトログラム用の音声を取得できません。')
  assert(j.last>j.first,'スペクトログラム用の音声範囲が空です。')
  j.samples=floor((j.last-j.first)*M.SR+1e-7);j.block=max(M.N,floor(131072/j.channels))
  j.buffer=api.new_array(j.block*j.channels);j.fft=api.new_array(M.N);start_processor(api,j)
  if j.coverage then j.read_cache={} end
  if not j.processor then j.time={};j.bin_power={} end
 end
 repeat
  if j.phase=='read' then
   if j.column_ready or read_column(api,j) then channel_fft(j) end
   if j.index==j.columns then
    api.DestroyAudioAccessor(j.accessor);j.accessor=nil;j.buffer=nil;j.fft=nil;j.time=nil;j.values=nil
    j.read_cache=nil;j.stitch=nil;j.input_buffer=nil
    j.phase='quantize';j.index=0
    if j.processor then
     local maxima=api.new_array(#M.scales);j.host.I.Function_GetValue_Array(j.processor,'maxima',maxima);j.data.maxima=maxima.table()
    end
    stop_processor(j);j.bin_power=nil;j.bands=nil;start_processor(api,j,true)
   end
  elseif j.phase=='quantize' then
   quantize_column(j)
   if j.index==j.columns then
    j.phase='encode';j.scale_index=1;j.index=0
    if j.native_encoding then j.data.frames=nil;j.host.I.Function_SetValue(j.processor,'operation',1) end
   end
  elseif j.phase=='encode' then encode_row(j)
  else paint(api,j);return true end
  work=work+1
 until work>=256 or api.time_precise()>=deadline
 return false
end
function M.progress(j)
 if j.done then return 1 end
 if j.kind=='render' then return 0 end
 if j.phase=='read' then return .8*(j.index+(j.channel-1)/j.channels)/j.columns end
 if j.phase=='quantize' then return .8+.05*j.index/j.columns end
 if j.phase=='encode' then return .85+.14*((j.scale_index-1)*M.ROWS+j.index)/(#M.scales*M.ROWS) end
 return .99
end
function M.draw(g,result,graph,view,span)
 if not result or not result.bitmap then return end
 local first,last=max(view,result.view),min(view+span,result.view+result.span)
 if last<=first then return end
 g.bitmap(result.bitmap,graph.x+(first-view)/span*graph.w,graph.y,(last-first)/span*graph.w,graph.h,
  (first-result.view)/result.span*result.columns,0,(last-first)/result.span*result.columns,M.ROWS,1)
end
return M
end)()

BLT.EnvelopeTrackIcon=(function()
local M={width=94,height=70,modes={'track'}}
local sin,pi=math.sin,math.pi
local function hash(n,salt) return (sin(n*12.9898+salt*78.233)*43758.5453)%1 end
function M.update() end
function M.draw(p,s)
 for lane=1,3 do
  local c=s.tones and s.tones[lane==3 and 4 or lane].color or p.C.ice
  p:rect(0,12+lane*12,9,9,p.C.panel2,.85)
  p:rect(0,12+lane*12,2,9,c,.75)
  p:line(12,23+lane*12,93,23+lane*12,c,.16,1)
  local previousX,previousY
  for i=0,24 do
   local u=i/24;local x,y=13+u*80,16+lane*12+sin(u*5+lane*.8)*3
   if previousX then p:line(previousX,previousY,x,y,c,.12,5);p:line(previousX,previousY,x,y,c,.78,1.4) end
   previousX,previousY=x,y
  end
 end
end
function M.emit(s,n,p)
 local a,b,c,d=hash(n,21),hash(n,22),hash(n,23),hash(n,24)
 local lane=n%3+1;local u=.1+.8*a
 p.x,p.y=13+u*80,16+lane*12+sin(u*5+lane*.8)*3
 p.vx,p.vy,p.phase,p.life,p.r,p.sway=(c-.5)*4,4+b*4,c*pi*2,2.8+b*1.55,.65+a*.75,2+d*3
 p.glint=n%8==0
end
function M.sample(s,p,age) return p.x+p.vx*age+sin(age*.63+p.phase)*p.sway,p.y-p.vy*age end
return M
end)()
local gfx,Host,U,shell,menu,canvas,controls,C
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
   for _,key in ipairs({'job','analysis','batch','source_job','wave_job','spectrum_job','pjob','xjob','ajob'}) do visit(a[key],0) end
   if a.display_mode=='spectrogram' then visit(a.spectrum_sources,0) end
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
local mediaGraphics={}
local Media,reaper=create_media_gate(reaper,mediaGraphics)

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
 ["波形"]="Waveform",
 ["スペクトログラム"]="Spectrogram",
 ["解析中"]="Analyzing",
 ["表示更新中"]="Updating display",
 ["スペクトログラムを解析中  %d%%"]="Analyzing spectrogram %d%%",
 ["スペクトログラムの表示を更新中  %d%%"]="Updating spectrogram %d%%",
 ["スペクトログラム用の音声を取得できません。"]="Cannot read audio for the spectrogram.",
 ["スペクトログラム用の音声範囲が空です。"]="The spectrogram audio range is empty.",
 ["スペクトログラムの音声読み出しに失敗しました。"]="Spectrogram audio read failed.",
 ["スペクトログラム用の素材情報を取得できません。"]="Cannot read source information for the spectrogram.",
 ["解析用のミュート除外に失敗しました。"]="Cannot bypass mute for analysis.",
 ["アイテムのミュート状態を復元できません。"]="Cannot restore the item mute state.",
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
 {"^スペクトログラムを解析中  ([%+%-]?[%d%.eE]+)%%$","Analyzing spectrogram %d%%"},
 {"^スペクトログラムの表示を更新中  ([%+%-]?[%d%.eE]+)%%$","Updating spectrogram %d%%"},
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
local Presets={items={},revision=0}
do
 local B=BLT
 local host
 local R=reaper
 local Layout={popup={visiblePresets=8}}
 local function wake_visuals() if host then host.wake() end end
function B.copy(v)
 if type(v)~='table' then return v end
 local t={};for k,x in pairs(v) do t[k]=B.copy(x) end;return t
end
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
 local values,revision=host.capture(),host.revision()
 if Presets.dirtyPreset~=Presets.current or Presets.dirtyRevision~=revision or not B.same(values.settings,Presets.dirtySettings) then
  Presets.dirtyPreset,Presets.dirtyRevision=Presets.current,revision
  Presets.dirtySettings=B.copy(values.settings)
  Presets.dirtyValue=not B.same(values,Presets.current.values)
 end
 return Presets.dirtyValue
end
function Presets.flush()
 Presets.revision=Presets.revision+1
 B.store(host.section,'preset_count',#Presets.items,true)
 for i,p in ipairs(Presets.items) do B.store(host.section,'preset_'..i,Presets.encode(p):gsub('%%','%%25'):gsub('\n','%%0A'):gsub('\r','%%0D'),true) end
end
do
local PresetDelete={
 busy=function() return host.busy() end,english=function() return Language.code=='EN' end,
 confirm=function(prompt) return Language.mb(prompt,'PRESET',4) end,
 visible=function() return Layout.popup.visiblePresets end,
 notify=function(message) notice(message,true) end,changed=wake_visuals,
 persist=function(oldCount)
  Presets.flush();local key='preset_'..oldCount
  R.DeleteExtState(host.section,key,true)
  if B.saved and B.saved[host.section] then B.saved[host.section][key]=nil end
 end,
}
function Presets.remove(p)
 if PresetDelete.busy() or not p or Presets.isFactory(p) then return false end
 local index
 for i,item in ipairs(Presets.items) do if item.name==p.name then index=i;break end end
 if not index then return false end
 local english=PresetDelete.english()
 local prompt=english and ('Delete preset "'..p.name..'"?') or ('プリセット「'..p.name..'」を削除しますか？')
 if PresetDelete.confirm(prompt)~=6 then return false end
 local oldCount=#Presets.items
 table.remove(Presets.items,index)
 if Presets.current and Presets.current.name==p.name then Presets.current=nil;Presets.dirtyCache=nil end
 PresetDelete.persist(oldCount,p)
 Presets.offset=math.min(Presets.offset or 0,math.max(0,#Presets.items-PresetDelete.visible()))
 Presets.selected=nil;Presets.pressed=nil;Presets.hoverSince=nil
 if #Presets.items==0 then Presets.page='main' end
 PresetDelete.notify((english and 'Deleted preset: ' or 'プリセットを削除しました: ')..p.name)
 PresetDelete.changed();return true
end

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
 host.cancelEdit();host.apply(B.copy(p.values));Presets.current=p;wake_visuals();notice('プリセットを読み込みました: '..p.name,true)
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
function B.attachPresets(h)
 host=h;R=h.R
 Presets.factory={name='ファクトリーデフォルト',factory=true,values=B.copy(h.defaults)}
 local n=math.min(200,math.max(0,tonumber(R.GetExtState(h.section,'preset_count')) or 0));local names={}
 for i=1,n do
  local raw=R.GetExtState(h.section,'preset_'..i):gsub('%%0A','\n'):gsub('%%0D','\r'):gsub('%%25','%%')
  local p=Presets.decode(raw);if p and not Presets.isFactory(p) and not names[p.name] then Presets.items[#Presets.items+1]=p;names[p.name]=true end
 end;table.sort(Presets.items,function(a,b)return a.name<b.name end)
end
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
end
local Core={VERSION='0.7.3',GENERATED_MAX_POINTS=1024,SECTION='BLT_ENVELOPE_CANVAS_TRACK'}
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

local SECTION=Core.SECTION
local W,H=1120,838
local A={layers=Core.new_layers(),layer='slot1',tool='free',direction=3,pattern=1,period_unit='sec',width_variable=true,height_variable=true,width_start=1,width_end=1,width_duration=1,width_curve=0,height_start=100,height_end=100,height_duration=1,height_curve=0,
 status='',warning=false,content_dirty=true,view=0,span=1,wave={},wave_max=1,
 display_mode=R.GetExtState(SECTION,'background_mode')=='spectrogram' and 'spectrogram' or 'wave',
 spectrum_scale=BLT.EnvelopeSpectrogram.scale_id(R.GetExtState(SECTION,'spectrum_scale')),spectrum_cache={},spectrum_data_cache={},
 busy=false,poll_at=0,active=true,bindings={},track_sessions={}}

local UI={}
UI.pattern_names={'サイン波','ノコギリ波','矩形波','三角波','水平線','ランダムステップ'}
UI.pattern_kinds={'sine','saw','square','triangle','horizontal','random_step'}
UI.number_limits={width_start={.001,3600,1,3},width_end={.001,3600,1,3},width_duration={.001,3600,1,3},width_curve={-100,100,1,1},height_start={0,200,1,1},height_end={0,200,1,1},height_duration={.001,3600,1,3},height_curve={-100,100,1,1}}
UI.number_rows={height_start=402,height_end=430,height_duration=458,height_curve=486,width_start=542,width_end=570,width_duration=598,width_curve=626}

C={
  bg={0.018,0.030,0.055}, bg2={0.030,0.090,0.180},
  panel={0.040,0.068,0.110}, panel2={0.055,0.125,0.205},
  field={0.018,0.040,0.080}, edge={0.145,0.285,0.445}, edge2={0.360,0.650,0.900},
  ice={.650,.895,1},disabled={.43,.46,.51},text={0.955,0.980,1.000}, muted={0.690,0.780,0.875}, faint={0.390,0.505,0.635},
  accent={0.120,0.490,0.980}, accent2={0.650,0.895,1.000}, accent3={0.045,0.235,0.520},
  focus={0.225,0.610,1.000}, focus2={0.690,0.900,1.000}, ink={0.018,0.075,0.160},
  hover={0.430,0.790,1.000}, warn={1.000,0.755,0.490}, red={1.000,0.230,0.300}, quiet={0.300,0.360,0.440}
}
local scale,ox,oy=1,0,0
local density=BLT.Controls.compactScale
local awakeUntil=R.time_precise()+6.5
local widgets,widgetByID={},{}
local widgetCount=0
local function noop() end
local down_last,pressed=false,nil
local mouse_x,mouse_y=-1,-1
local function wake_visuals() A.content_dirty=true;awakeUntil=R.time_precise()+6.5 end
local function sx(x) return ox+x*scale end
local function sy(y) return oy+y*scale end
local function color(c,a) gfx.set(c[1],c[2],c[3],a or 1) end
local function rect(x,y,w,h,c,a) color(c,a);gfx.rect(sx(x),sy(y),w*scale,h*scale,1) end
local function line(x,y,xx,yy,c,a) color(c,a);gfx.line(sx(x),sy(y),sx(xx),sy(yy),1) end
local function disc(x,y,r,c,a) color(c,a);gfx.circle(sx(x),sy(y),r*scale,1,1) end
local function inside(x,y,w,h) return mouse_x>=x and mouse_x<x+w and mouse_y>=y and mouse_y<y+h end
local function register(id,x,y,w,h,fn,hint,enabled)
 local widget=widgetByID[id]
 if not widget then widget={id=id};widgetByID[id]=widget end
 widget.x,widget.y,widget.w,widget.h=x,y,w,h
 widget.fn,widget.hint,widget.enabled=fn,hint,enabled~=false
 widgetCount=widgetCount+1;widgets[widgetCount]=widget
end
local function font(size,kind,bold) gfx.setfont(1,Host.faces[kind or 1],max(7,floor(size*scale+.5)),bold and 98 or 0) end
local function label(text,x,y,size,c,kind,w,h,flags,bold,literal,opticalCenter)
 font(size,kind,bold);color(c or C.text);gfx.x,gfx.y=sx(x),sy(y)
 gfx.drawstr(literal and tostring(text) or Language.message(text),flags or 0,sx(x+(w or 700)),sy(y+(h or size+8)),opticalCenter)
end
local function right_label(text,right,y,size,c,kind,bold)
 label(text,right-400,y,size,c,kind,400,size+9,2,bold)
end
local function notice(s,warn)
 A.status=warn and BLT.publicError(s) or tostring(s or '');A.warning=warn or false;wake_visuals()
end
local Track
UI.defs={
 {key='slot1',name='ENV 1',code='ENV 1',sub='トラックのエンベロープ',color={.46,.82,1}},
 {key='slot2',name='ENV 2',code='ENV 2',sub='トラックのエンベロープ',color={.78,.56,1}},
 {key='slot3',name='ENV 3',code='ENV 3',sub='トラックのエンベロープ',color={1,.73,.36}},
 {key='slot4',name='ENV 4',code='ENV 4',sub='トラックのエンベロープ',color={.38,.91,.72}},
 {key='slot5',name='ENV 5',code='ENV 5',sub='トラックのエンベロープ',color={.89,.75,.36}},
 {key='slot6',name='ENV 6',code='ENV 6',sub='トラックのエンベロープ',color={1,.52,.42}}
}

UI.graph={x=212,y=166,w=784,h=372}
function UI.from_axis(key,y) return clamp(y,-1,1) end
function UI.to_axis(key,y) return y end

function UI.def() for _,d in ipairs(UI.defs) do if d.key==A.layer then return d end end end

function UI.card_geometry(i) return 212+((i-1)%3)*294,619+floor((i-1)/3)*69,282 end

function UI.refresh() wake_visuals() end
function UI.dirty()
 A.canvas_revision=(A.canvas_revision or 0)+1;wake_visuals()
end
function UI.safe(fn)
 local ok,err=xpcall(fn,debug.traceback)
 if not ok then
  A.busy=false
  BLT.cleanup(Track.finish)
  BLT.cleanup(UI.stop_wave)
  if A.display_mode=='spectrogram' then A.spectrum_failed=true end
  BLT.cleanup(UI.stop_spectrum)
  if A.v then
   local refreshed,value=pcall(Track.target)
   A.v=refreshed and value or nil;A.revision=nil
  end
  notice(err,true)
  BLT.recoverInput(A,err);BLT.cleanup(UI.cancel_preview);pcall(UI.sync_curves)
 end
 return ok
end

function UI.undo_draw(redo)
 if A.busy or not Track.valid(A.v) then return end
 Track.finish();UI.cancel_preview()
 if redo then R.Undo_DoRedo2(A.v.project) else R.Undo_DoUndo2(A.v.project) end
 UI.sync_curves()
end
function UI.stop_wave()
 A.wave_job=nil
end
function UI.drop_spectrum(index)
 local result=table.remove(A.spectrum_cache,index)
 if A.spectrum==result then A.spectrum=nil end
 BLT.EnvelopeSpectrogram.release(R,result)
end

function UI.stop_spectrum(clear)
 if A.spectrum_job then local j=A.spectrum_job;A.spectrum_job=nil;BLT.EnvelopeSpectrogram.cancel(R,j) end
 if clear then
  while #A.spectrum_cache>0 do UI.drop_spectrum(#A.spectrum_cache) end
  A.spectrum=nil;A.spectrum_data=nil;A.spectrum_key=nil;A.spectrum_failed=nil;A.spectrum_plan=nil
 end
end

function UI.spectrum_source_key()
 if not A.spectrum_key then
  A.spectrum_signature=A.spectrum_signature or Track.spectrum_signature(A.v,A.spectrum_sources)
  A.spectrum_key={project=A.v.project,track=A.v.track,guid=A.v.guid,pos=A.v.pos,len=A.v.len,signature=A.spectrum_signature}
 end
 return A.spectrum_key
end
function UI.remember_spectrum_data(data)
 if A.spectrum_data==data then return end
 A.spectrum_data=data
 for i,entry in ipairs(A.spectrum_data_cache) do
  if entry.data==data then table.remove(A.spectrum_data_cache,i);break end
 end
 table.insert(A.spectrum_data_cache,1,{key=UI.spectrum_source_key(),data=data})
 while #A.spectrum_data_cache>2 do table.remove(A.spectrum_data_cache) end
end
function UI.ensure_spectrum()
 if A.display_mode~='spectrogram' or A.spectrum_failed or not A.v or A.busy or A.spectrum_fade_editing then return end
 local S=BLT.EnvelopeSpectrogram;local job=A.spectrum_job
 if A.spectrum and A.spectrum.scale==A.spectrum_scale and A.spectrum.palette==S.palette and not job then return end
 if not A.spectrum_plan then
  if not A.spectrum_sources then A.spectrum_sources=Track.wave_sources(A.v) end
  A.spectrum_plan=Track.spectrum_plan(A.v,A.spectrum_sources)
 end
 local plan=A.spectrum_plan
 if #plan.ranges==0 then
  UI.stop_spectrum()
  if not A.spectrum_data then UI.remember_spectrum_data({empty=true,complete=true,columns=0,view=0,span=1}) end
  while #A.spectrum_cache>=2 do UI.drop_spectrum(#A.spectrum_cache) end
  local result=S.render(A.v,A.spectrum_data,A.spectrum_scale,Host)
  table.insert(A.spectrum_cache,1,result);A.spectrum=result;UI.dirty();return
 end
 -- Scale changes preserve both FFT analysis and initial image preparation.
 if job and job.kind=='analysis' and not job.data.complete then job.scale=A.spectrum_scale;return end
 if job and job.scale==A.spectrum_scale then return end
 if not Media.ready() then return end
 UI.stop_spectrum()
 for i,cached in ipairs(A.spectrum_cache) do
  if cached.scale==A.spectrum_scale and cached.palette==S.palette then
   if i>1 then table.remove(A.spectrum_cache,i);table.insert(A.spectrum_cache,1,cached) end
   if A.spectrum~=cached then A.spectrum=cached;UI.dirty() end
   return
  end
 end
 while #A.spectrum_cache>=2 do UI.drop_spectrum(#A.spectrum_cache) end
 if not A.spectrum_data then
  local key=UI.spectrum_source_key()
  for _,entry in ipairs(A.spectrum_data_cache) do
   local k=entry.key
   if k.project==key.project and k.track==key.track and k.guid==key.guid and k.pos==key.pos and k.len==key.len and k.signature==key.signature then
    UI.remember_spectrum_data(entry.data);break
   end
  end
 end
 if A.spectrum_data then
  A.spectrum_job=S.render(A.v,A.spectrum_data,A.spectrum_scale,Host);UI.safe(UI.spectrum_step)
 else
  -- Avoid analyzing every intermediate range while the ruler is being dragged.
  if R.time_precise()<(A.spectrum_due or 0) then return end
  -- Reserve one of the two data slots before starting another range.
  while #A.spectrum_data_cache>=2 do table.remove(A.spectrum_data_cache) end
  A.spectrum_job=S.start(A.v,plan.view,plan.span,nil,nil,A.spectrum_scale,Host,Track.spectrum_reader,plan)
 end
 UI.refresh()
end

function UI.spectrum_step()
 local j=A.spectrum_job;if not j then return end
 if A.drag or A.spectrum_fade_editing or not Media.ready() then return end
 if not Track.valid(j.v) or not Track.same(j.v,A.v) then UI.stop_spectrum(true);return end
 local done=BLT.EnvelopeSpectrogram.step(R,j,.006)
 if j.data.complete then UI.remember_spectrum_data(j.data) end
 if done then
  table.insert(A.spectrum_cache,1,j);A.spectrum=j;A.spectrum_job=nil;UI.dirty()
 else
  local now=R.time_precise()
  if now>(A.spectrum_present_at or 0) then A.spectrum_present_at=now+.15;UI.refresh() end
 end
end

function UI.spectrum_wheel(wheel)
 if A.display_mode~='spectrogram' or A.busy or A.drag then A.spectrum_wheel=0;return end
 local steps,remainder=math.modf((A.spectrum_wheel or 0)+wheel/120);A.spectrum_wheel=remainder
 if steps==0 then return end
 local scales=BLT.EnvelopeSpectrogram.scales
 for i,choice in ipairs(scales) do
  if choice.id==A.spectrum_scale then UI.set_spectrum_scale(scales[clamp(i-steps,1,#scales)].id);return end
 end
end

function UI.set_spectrum_scale(id)
 id=BLT.EnvelopeSpectrogram.scale_id(id)
 if A.busy or A.drag or id==A.spectrum_scale then return end
 UI.number_commit();A.spectrum_scale=id;A.spectrum_failed=nil
 BLT.store(SECTION,'spectrum_scale',id,true)
 UI.ensure_spectrum();UI.dirty()
end

function UI.set_display(mode)
 if A.busy or A.drag or (mode~='wave' and mode~='spectrogram') or A.display_mode==mode then return end
 UI.number_commit();A.display_mode=mode;A.spectrum_failed=nil
 BLT.store(SECTION,'background_mode',mode,true)
 if mode=='spectrogram' then UI.stop_wave();A.wave_retry=nil;UI.ensure_spectrum()
 else UI.stop_spectrum();UI.start_wave(nil,nil,true) end
 UI.dirty()
end

function UI.start_wave(sources,signature,preserve_spectrum)
 UI.stop_wave();A.wave={};A.wave_max=1
 if not preserve_spectrum then UI.stop_spectrum(true);A.spectrum_signature=nil;A.spectrum_due=R.time_precise()+.15 end
 if not A.v then return end
 if not sources then sources,signature=Track.wave_sources(A.v) end
 A.spectrum_sources=sources
 A.wave_signature=signature
 if A.display_mode=='spectrogram' then UI.ensure_spectrum();UI.dirty();return end
 for i=1,4096 do A.wave[i]=0 end
 if #sources>0 then
  A.wave_job={v=A.v,total=#sources,index=0,sources=sources,bin=0,max=0}
 end
 UI.dirty()
end
function UI.wave_step()
 local j=A.wave_job;if not j then return end
 if not Media.ready() then return end
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
    A.wave_retry=now+2
   end
   j.bin=j.bin+count
  end
  batches=batches+1
 until j.index>=j.total or batches>=8 or R.time_precise()>=budget
 A.wave_max=max(.001,j.max)
 if j.index>=j.total then UI.stop_wave();UI.dirty()
 elseif now>(A.wave_present_at or 0) then A.wave_present_at=now+.15;UI.dirty() end
end

function UI.check_current()
 local reason
 if not Track.valid(A.v) then reason='トラックと時間範囲を選択してください。'
 elseif not Track.same(A.v,Track.target()) then reason='対象トラックまたは時間範囲が変わりました。'
 elseif (R.GetPlayStateEx(A.v.project)&5)~=0 then reason='編集は再生・録音を停止してから行ってください。' end
 if reason then notice(reason,true);UI.dirty();return false end
 return true
end

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

function UI.output_time(u) return A.v and (A.v.pos+u*A.v.len) or 0 end

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
function UI.automation_regions(labels)
 local c=A.layers[A.layer];if not c or not c.env or not A.v then return end
 local g=UI.graph
 for _,a in ipairs(c.items) do
  local first,last=max(A.v.pos,a.pos),min(A.v.pos+A.v.len,a.pos+a.len)
  if last>first then
   local x=g.x+(first-A.v.pos)/A.v.len*g.w;local r=g.x+(last-A.v.pos)/A.v.len*g.w
   local tint=a.mute and C.muted or UI.def().color
   if not labels then
   rect(x,g.y,r-x,g.h,tint,.065)
   line(x,g.y,x,g.y+g.h,tint,.4);line(r,g.y,r,g.y+g.h,tint,.4)
   end
   if labels and r-x>44 then label('AI '..(a.ai+1),x+5,g.y+4,10,tint,3,r-x-10,14) end
  end
 end
end
function UI.curves()
 local g=UI.graph
 for pass=1,2 do for _,d in ipairs(UI.defs) do
  local active=d.key==A.layer;local c=A.layers[d.key]
  if c.env and (active or c.enabled) and (pass==2)==active then
   local count=ceil(g.w*canvas.scale)
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

function UI.thick_line(x,y,x2,y2,c,a,width)
 local dx,dy=x2-x,y2-y;local length=math.sqrt(dx*dx+dy*dy)
 if length<1e-9 then return end
 local nx,ny=-dy/length,dx/length
 for i=0,width-1 do local offset=i-(width-1)/2;line(x+nx*offset,y+ny*offset,x2+nx*offset,y2+ny*offset,c,a) end
end

function UI.poll_playhead()
 local playing=A.v and (R.GetPlayStateEx(A.v.project)&1)~=0 or false
 if playing~=A.playing then A.playing=playing;UI.refresh() end
end
function UI.playhead()
 if not A.playing or not A.v then return end
 local time=R.GetPlayPositionEx(A.v.project)
 if not finite(time) or time<A.v.pos or time>A.v.pos+A.v.len then return end
 local g=UI.graph;local x=g.x+(time-A.v.pos)/A.v.len*g.w
 line(x,g.y,x,g.y+g.h,C.focus2,.95)
 rect(x-3,g.y,6,4,C.focus2,1)
end

function UI.point_position(p)
 local g=UI.graph;local u=p.x;local ay=UI.to_axis(A.layer,p.y)
 return g.x+(u-A.view)/A.span*g.w,g.y+(1-ay)*g.h/2,u>=A.view-1e-9 and u<=A.view+A.span+1e-9 and abs(ay)<=1
end
function UI.nearest()
 return canvas:nearest(A.layers[A.layer],UI.graph,A.view,A.span,A.layer,1,A.canvas_revision,mouse_x,mouse_y,scale,UI.to_axis)
end
function UI.hover_point(index)
 local key=index and A.layer..':'..index or nil
 if key~=A.hover_point_key then
  A.hover_point_key=key;A.hover_node=index;A.point_flash=R.time_precise();UI.refresh()
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
  A.hover_segment_key=key;A.segment_flash=R.time_precise();UI.refresh()
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
 if A.hit~=id then A.hit=id;UI.refresh() end
 local g=UI.graph;local in_graph=inside(g.x,g.y,g.w,g.h)
 if not (A.active or A.pointer_capture or UI.activation_press(down)) then
  Track.finish();UI.cancel_preview();down_last=down;A.right_last=right;return
 end
 if id=='spectrum_scale' then
  if wheel~=0 then gfx.mouse_wheel=0;UI.spectrum_wheel(wheel);down_last=down;A.right_last=right;return end
 else A.spectrum_wheel=0 end
 if UI.number_input(id,down,wheel) then down_last=down;A.right_last=right;return end
 gfx.mouse_wheel=0
 local nearest=in_graph and A.v and UI.nearest() or nil
 UI.hover_point(nearest)
 UI.hover_segment(in_graph and not nearest and not down and not right)
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
 if k==0 or U.editor.edit or UI.context or A.spectrum_menu_open then return end
 local ctrl=(gfx.mouse_cap&4)~=0;local shift=(gfx.mouse_cap&8)~=0
 if k==27 then if A.drag then Track.finish();UI.cancel_preview();UI.sync_curves() else A.closing=true end
 elseif k==26 or ctrl and (k==122 or k==90) then UI.undo_draw(shift)
 elseif k==25 or ctrl and (k==121 or k==89) then UI.undo_draw(true)
 elseif k==6579564 or k==127 then UI.delete_selected()
 elseif k>=49 and k<=51 then UI.set_mode(({'select','free','line'})[k-48])
 elseif k==13 then UI.apply() end
end
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

-- Routing envelopes use TRACKCFG; include FX/non-FX envelopes and shared pool contents.
Track={tag='P_POOL_EXT:BLT_CANVAS_TRACK_V1',undo_flags=1|32|64|128}
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
 local current=1
 for i,entry in ipairs(entries) do
  rows[#rows+1]=entry.name
  if A.bindings[key] and A.bindings[key].guid==entry.guid then current=i+1 end
 end
 local selected=A.v;local bindings=A.bindings
 UI.open_menu(rows,function(pick)
 if A.bindings~=bindings or not Track.same(selected,A.v) or not Track.same(selected,Track.target()) then return end
 pressed=nil;A.pointer_capture=nil;A.drag=nil;down_last=(gfx.mouse_cap&1)~=0
 if pick==1 then A.bindings[key]=nil;A.layers[key]=Core.new_layers()[key];UI.sync_curves()
 elseif pick>1 and entries[pick-1] then
  local entry=entries[pick-1]
  for k,binding in pairs(A.bindings) do if k~=key and binding.guid==entry.guid then notice('同じエンベロープを複数の枠には割り当てられません。',true);UI.dirty();return end end
  local ok,properties=pcall(Track.properties,entry.env)
  if not ok then notice(properties,true);UI.dirty();return end
  A.bindings[key]={track=R.GetTrackGUID(track),guid=entry.guid,name=entry.name};A.layer=key;A.record=nil
  A.layers[key].enabled=true
  UI.sync_curves()
 end
 UI.dirty()
 end,nil,current)
end
function UI.load_selection(force,selected)
 if A.busy then return end
 local v=selected or Track.target()
 if Track.same(v,A.v) and not force then return end
 Track.finish();UI.stop_wave();UI.stop_spectrum(true);A.spectrum_signature=nil;A.spectrum_fade_editing=nil;A.spectrum_fade_check=nil;A.drag=nil;A.number_drag=nil;A.selection=nil;pressed=nil;A.pointer_capture=nil
 A.v=v;A.record=nil;A.conflict=false;A.revision=nil;A.source_revision=nil;A.live_failed=nil;A.host_pending=nil;A.wave_retry=nil
 if not v then
  A.bindings={};A.layers=Core.new_layers();A.host_layers=A.layers;A.host_state=nil;A.wave={};A.wave_max=1;A.track_key=nil;A.spectrum_sources=nil
  notice('トラックと時間範囲を選択してください。');UI.dirty();return
 end
 local key=tostring(v.project)..':'..v.guid
 if not A.track_sessions[key] then
  A.track_sessions[key]={};A.track_order=A.track_order or {};A.track_order[#A.track_order+1]=key
  while #A.track_order>16 do A.track_sessions[table.remove(A.track_order,1)]=nil end
 end
 A.bindings=A.track_sessions[key];A.track_key=key;A.layers=Core.new_layers();for k in pairs(A.bindings) do A.layers[k].enabled=true end
 A.status='';A.warning=false;UI.start_wave();A.source_revision=R.GetProjectStateChangeCount(v.project);UI.sync_curves()
 A.follow_env=nil;UI.follow_envelope(v);UI.dirty()
end

function UI.follow_envelope(v,env,context)
 if A.drag or A.number_drag then return end
 if context==nil then
  if not R.GetCursorContext2 or R.GetCursorContext2(true)~=2 then return end
  env=R.GetSelectedEnvelope(v.project)
 elseif context~=2 then return end
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
function UI.poll_spectrum_fades(now,down)
 if A.display_mode~='spectrogram' or not A.v or A.drag or A.number_drag or A.busy or not A.spectrum_sources or #A.spectrum_sources==0 then
  A.spectrum_fade_editing=nil;return
 end
 local editing=false
 if down then
  if R.GetItemEditingTime2 then
   local _,_,flags=R.GetItemEditingTime2();editing=type(flags)=='number' and (flags&2)~=0
  else editing=not Host.focused and R.GetCursorContext2 and R.GetCursorContext2(true)==1 end
 end
 if not editing and not A.spectrum_fade_editing then return end
 local released=A.spectrum_fade_editing and not down
 A.spectrum_fade_editing=editing or down and A.spectrum_fade_editing or nil
 if not released and now<(A.spectrum_fade_check or 0) then return end
 A.spectrum_fade_check=now+.12
 local changed=false;local fades={}
 for _,source in ipairs(A.spectrum_sources) do
  if R.ValidatePtr2(A.v.project,source.item,'MediaItem*') then
   local value=Track.fade_signature(source.item)
   fades[source.item]=value
   if source.fade_signature~=value then source.fade_signature=value;changed=true end
  end
 end
 if changed then
  UI.stop_spectrum(true);A.spectrum_signature=nil;A.spectrum_due=now+.15;UI.ensure_spectrum();UI.dirty()
 end
 return fades
end
function UI.poll(now)
 if now<A.poll_at or A.busy then return end;A.poll_at=now+.05
 local project=R.EnumProjects(-1,'');local revision=R.GetProjectStateChangeCount(project)
 local v=Track.target(project,revision==A.source_revision and A.v or nil)
 if not v then if A.v then UI.load_selection(false) end;return end
 if not Track.same(v,A.v) then UI.load_selection(false,v);return end
 local native_down=R.JS_Mouse_GetState and (R.JS_Mouse_GetState(3)&3)~=0
 local fades=UI.poll_spectrum_fades(now,native_down)
 -- Curve synchronization and Undo must not consume pending audio changes.
 if not A.drag and not A.number_drag and not A.spectrum_fade_editing and (revision~=A.source_revision or not A.wave_signature) then
  A.v=v
  local sources,signature=Track.wave_sources(v,fades)
  A.spectrum_sources=sources
  if signature~=A.wave_signature then UI.start_wave(sources,signature)
  elseif A.spectrum_signature and not A.spectrum_failed then
   local fingerprint=Track.spectrum_signature(v,sources)
   if fingerprint~=A.spectrum_signature then
    UI.stop_spectrum(true);A.spectrum_signature=fingerprint;A.spectrum_due=now+.15;UI.ensure_spectrum();UI.dirty()
   end
  end
  A.source_revision=revision
 end
 local env=R.GetSelectedEnvelope(v.project);local context=R.GetCursorContext2(true)
 UI.follow_envelope(v,env,context)
 local revised=revision~=A.revision
 local native_edit=env~=nil and context==2
 local native_release=A.host_mouse_down and not native_down
 A.host_mouse_down=native_down
 local check_drag=native_edit and ((native_down and now>=(A.host_check_at or 0)) or native_release)
 if revised or not A.host_state or check_drag then
  A.host_check_at=now+.25
  local state=Track.host_state(v,A.bindings)
  if not A.host_state or not BLT.same(state,A.host_state) then
   Track.finish();UI.cancel_preview();notice('REAPER側でカーブが変更されたため、ドラッグを終了しました。',true)
   for _,binding in pairs(A.bindings) do local env=Track.resolve(v,binding)
    if env then local _,name=R.GetEnvelopeName(env,'');binding.name=name else binding.name='[missing]' end
   end
   UI.sync_curves(state)
  elseif revised then
   if not A.drag then Track.finish();UI.sync_curves(state) end
  end
  A.revision=R.GetProjectStateChangeCount(v.project)
 end
 if A.wave_retry and now>=A.wave_retry and not A.wave_job and Media.ready() then A.wave_retry=nil;UI.start_wave() end
end
function UI.apply()
 if not UI.available('apply') then notice('エンベロープの割当先を選択してください。');return end
 if not UI.check_current() or not UI.ensure_host() then return end
 local count=Track.automate(A.v,A.bindings,A.layers);UI.sync_curves()
 if count and count>0 then U:complete('apply',444/density,52/density) end
 notice('表示範囲をオートメーションアイテムにまとめました。')
end

function Track.target(project,cached)
 project=project or R.EnumProjects(-1,'')
 local track=R.GetSelectedTrack(project,0)
 local env=R.GetSelectedEnvelope(project)
 if env and R.Envelope_GetParentTrack and (not track or R.GetCursorContext2(true)==2) then
  local parent=R.Envelope_GetParentTrack(env)
  if parent and R.ValidatePtr2(project,parent,'MediaTrack*') then track=parent end
 end
 local first,last=R.GetSet_LoopTimeRange2(project,false,false,0,0,false)
 if not track or not R.ValidatePtr2(project,track,'MediaTrack*') or not finite(first) or not finite(last) or last<=first then return end
 if cached and cached.project==project and cached.track==track then
  if cached.pos==first and cached.len==last-first then return cached end
  return {project=project,track=track,guid=cached.guid,name=cached.name,pos=first,len=last-first,channels=cached.channels}
 end
 local _,name=R.GetTrackName(track,'')
 return {project=project,track=track,guid=R.GetTrackGUID(track),name=name or '',pos=first,len=last-first,channels=clamp(floor(R.GetMediaTrackInfo_Value(track,'I_NCHAN')),1,64)}
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
  R.Undo_EndBlock2(g.project,'BLT Envelope Canvas Track: Draw',Track.undo_flags)
  if A.v and A.v.project==g.project then A.revision=R.GetProjectStateChangeCount(g.project) end
 end
end
function Track.fade_signature(item)
 if not Track.fade_keys then
  local version=R.GetAppVersion and R.GetAppVersion() or ''
  local major,minor=version:match('^(%d+)%.(%d+)');major,minor=tonumber(major) or 0,tonumber(minor) or 0
  local keys={'D_FADEINLEN','D_FADEOUTLEN','D_FADEINLEN_AUTO','D_FADEOUTLEN_AUTO'}
  local curves=major>7 or major==7 and minor>=81
  curves=curves and {'D_FADEINDIR_NEW','D_FADEOUTDIR_NEW','D_FADEINDIR2_NEW','D_FADEOUTDIR2_NEW'}
   or {'C_FADEINSHAPE','C_FADEOUTSHAPE','D_FADEINDIR','D_FADEOUTDIR'}
  for _,key in ipairs(curves) do keys[#keys+1]=key end
  if major>7 or major==7 and minor>=46 then keys[#keys+1]='I_FADELPF' end
  Track.fade_keys=keys
 end
 local values={}
 for i,key in ipairs(Track.fade_keys) do values[i]=tostring(R.GetMediaItemInfo_Value(item,key)) end
 return table.concat(values,':')
end
function Track.wave_sources(v,fades)
 local list,signature={},{}
 for i=0,R.CountTrackMediaItems(v.track)-1 do
  local item=R.GetTrackMediaItem(v.track,i)
  local pos=R.GetMediaItemInfo_Value(item,'D_POSITION');local len=R.GetMediaItemInfo_Value(item,'D_LENGTH')
  if len>0 and pos<v.pos+v.len and pos+len>v.pos then
   local take=R.GetActiveTake(item)
   if take and not R.TakeIsMIDI(take) then
    local source=R.GetMediaItemTake_Source(take);local channels=source and R.GetMediaSourceNumChannels(source) or 0
    local length,isQN=0,false
    if channels>0 then length,isQN=R.GetMediaSourceLength(source) end
    if channels>0 and length>0 and not isQN and R.GetMediaSourceType(source,'')~='EMPTY' then
     list[#list+1]={item=item,take=take,pos=pos,len=len,channels=min(64,channels),
      fade_signature=(A.display_mode=='spectrogram' or A.spectrum_signature) and (fades and fades[item] or Track.fade_signature(item)) or nil}
     signature[#signature+1]=table.concat({tostring(item),tostring(take),tostring(source),pos,len,channels,
      R.GetMediaItemTakeInfo_Value(take,'D_PLAYRATE'),R.GetMediaItemTakeInfo_Value(take,'D_STARTOFFS'),
      R.GetMediaItemTakeInfo_Value(take,'D_PITCH'),R.GetMediaItemTakeInfo_Value(take,'D_VOL'),
      R.GetMediaItemInfo_Value(item,'D_VOL')},':')
    end
   end
  end
 end
 return list,table.concat(signature,'|')
end
function Track.spectrum_plan(v,sources)
 local S=BLT.EnvelopeSpectrogram;local ranges={};local samples=floor(v.len*S.SR+1e-7)
 for _,source in ipairs(sources) do
  local first=max(0,ceil((source.pos-v.pos)*S.SR-1e-7))
  local last=min(samples,floor((source.pos+source.len-v.pos)*S.SR+1e-7))
  if last>first then ranges[#ranges+1]={first=first,last=last} end
 end
 table.sort(ranges,function(a,b)return a.first<b.first end)
 local merged={}
 for _,range in ipairs(ranges) do
  local previous=merged[#merged]
  if previous and range.first<=previous.last then previous.last=max(previous.last,range.last)
  else merged[#merged+1]=range end
 end
 local plan={ranges=merged,sources=sources,centers={}}
 if #merged==0 then return plan end
 local first,last=merged[1].first,merged[#merged].last
 local columns=clamp(ceil((last-first)/S.HOP),32,S.MAX_COLUMNS)
 plan.view,plan.span,plan.columns=first/(v.len*S.SR),(last-first)/(v.len*S.SR),columns
 local width=(last-first)/columns;local index=1
 for i=0,columns-1 do
  local left,right=first+i*width,first+(i+1)*width;local center=(left+right)/2
  while merged[index] and merged[index].last<=left do index=index+1 end
  local at=index;local chosen=false;local distance=math.huge
  while merged[at] and merged[at].first<right do
   local range=merged[at];local candidate=clamp(floor(center),range.first,range.last-1)
   if abs(candidate-center)<distance then chosen=candidate;distance=abs(candidate-center) end
   at=at+1
  end
  plan.centers[i+1]=chosen
 end
 return plan
end
-- Track automation edits do not change the source snapshot. Ignore item
-- selection and mute so their UI changes also retain the cached analysis.
function Track.spectrum_signature(v,sources)
 sources=sources or Track.wave_sources(v)
 local parts={tostring(v.channels)}
 for _,source in ipairs(sources) do
  local ok,chunk=R.GetItemStateChunk(source.item,'',false)
  assert(ok and chunk and chunk~='','スペクトログラム用の素材情報を取得できません。')
  source.fade_signature=source.fade_signature or Track.fade_signature(source.item)
  local lines,stack={tostring(source.item),source.fade_signature},{}
  for line in (chunk:gsub('\r\n','\n')..'\n'):gmatch('(.-)\n') do
   local token=line:match('^%s*(%S+)');local parent=stack[#stack]
   local ignored=parent=='ITEM' and (token=='SEL' or token=='MUTE') or
    parent=='TAKEFX' and (token=='SHOW' or token=='LASTSEL' or token=='DOCKED' or token=='FLOATPOS')
   if not ignored then lines[#lines+1]=line end
   if token and token:sub(1,1)=='<' then stack[#stack+1]=token:sub(2)
   elseif token=='>' then stack[#stack]=nil end
  end
  local text=table.concat(lines,'\n');parts[#parts+1]=#text..':'..text
 end
 return table.concat(parts,'|')
end
function Track.spectrum_reader(api,v,coverage)
 local muted={};local aa
 -- Capture once, with source-item mute bypassed, and restore before yielding.
 local ok,err=xpcall(function()
  local sources=coverage and coverage.sources or Track.wave_sources(v)
  for _,source in ipairs(sources) do
   local item=source.item
   assert(api.ValidatePtr2(v.project,item,'MediaItem*'),'解析対象のアイテムが見つかりません。')
   local mute=api.GetMediaItemInfo_Value(item,'B_MUTE')
   if mute~=0 then
    muted[#muted+1]={item=item,value=mute}
    assert(api.SetMediaItemInfo_Value(item,'B_MUTE',0),'解析用のミュート除外に失敗しました。')
   end
  end
  aa=api.CreateTrackAudioAccessor(v.track)
 end,debug.traceback)
 local restored=true
 for i=#muted,1,-1 do
  local entry=muted[i];local success,result=pcall(api.SetMediaItemInfo_Value,entry.item,'B_MUTE',entry.value)
  if not success or not result then restored=false end
 end
 if not ok or not restored then
  if aa then api.DestroyAudioAccessor(aa) end
  error(not restored and 'アイテムのミュート状態を復元できません。' or err,0)
 end
 -- Use project time, keeping silence before/between/after items in the range.
 return aa,v.pos,v.pos+v.len
end
function Track.read(v,bindings)
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
function UI.sync_curves(state)
 if not Track.valid(A.v) then A.layers=Core.new_layers();A.host_layers=A.layers;UI.dirty();return false end
 local ok,layers=pcall(Track.read,A.v,A.bindings)
 if not ok then A.layers=Core.new_layers();A.host_layers=A.layers;notice(layers,true);UI.dirty();return false end
 A.layers=layers;A.host_layers=layers;A.host_state=state or Track.host_state(A.v,A.bindings)
 A.revision=R.GetProjectStateChangeCount(A.v.project);A.host_check_at=R.time_precise()+.25
 A.hover_node=nil;UI.dirty();return true
end

function Track.content_state(chunk)
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
  Track.finish();UI.cancel_preview();UI.sync_curves(current)
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
 UI.sync_line_targets();UI.reset_line_preview(false);UI.save_settings();UI.dirty()
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
 local names=Language.code=='JP' and {'線形','矩形','緩やかな開始／終了','速い開始','速い終了','Bezier','選択ポイントを削除'} or {'Linear','Square','Slow start/end','Fast start','Fast end','Bezier','Delete selected points'}
 local selected=A.v
 UI.open_menu(names,function(choice)
 if not Track.same(selected,A.v) or not Track.same(selected,Track.target()) or A.layers[A.layer]~=c then return end
 if choice==7 then UI.delete_selected();return end
 if choice<1 or choice>6 then return end
 UI.native_write(c.env,function()
  for _,p in ipairs(c.points) do if p.selected then Track.set(c.env,p,nil,nil,choice-1,p.tension,nil) end end
 end,false)
 end,7)
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
 R.PreventUIRefresh(-1);R.Undo_EndBlock2(v.project,'BLT Envelope Canvas Track: Automation items',Track.undo_flags);R.UpdateArrange()
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
   if u==0 and ((origin_jump and edge<x) or single_jump) then u=min(1e-5,.01/cycles) end
   local time=UI.period_time(domain,coord+(edge_coord-coord)*u)
   local q=UI.screen_to_point(g.x+(time-A.v.pos)/A.v.len*g.w,y-p.y*UI.height_gain(abs(edge_coord-coord)*u)*sign*invert*g.h/2)
   q.y=clamp(q.y,c.min_y,c.max_y);out[#out+1]=q
  end end
 end
 if A.direction~=3 then side(left,A.direction==2 and -1 or 1,omit_origin or (joined and not origin_jump),'left') end
 if A.direction~=1 then side(right,1,omit_origin,'right') end
 local ua=UI.screen_to_point(left,y).x;local ub=UI.screen_to_point(right,y).x
 local generated={points=UI.clean_points(out)}
 if (A.pattern==3 or A.pattern==6) and A.height_start==A.height_end then
  local compact={}
  for i,p in ipairs(generated.points) do
   if #compact==0 or abs(p.y-compact[#compact].y)>1e-10 or i==#generated.points then
    p.shape=1;compact[#compact+1]=p
   end
  end
  generated.points=compact
 else
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
  U:flash('number_'..key);A.number_flash_until=R.time_precise()+.9
 end
 A[key]=v;UI.sync_line_targets();UI.refresh()
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
 A.layer=previous;UI.dirty()
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
  for _,e in ipairs(edits) do Track.set(c.env,rebound[e.p],e.time,e.value,e.p.shape,e.p.tension,true);sorted[e.p.ai]=true end
  local looped={}
  for _,p in ipairs(erase) do
   if p.ai<0 then
    if not R.DeleteEnvelopePointEx(c.env,p.ai,rebound[p].index) then error('Cannot overwrite envelope point',0) end
   else looped[p.ai]=true end
   sorted[p.ai]=true
  end
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
 controls:panel(24,250,164,412,tone)
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
 U:chaos('chaos','C H A O S',24/density,670/density,164/density,44/density,{enabled=enabled,size=17/density,bold=true})
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
 local function knot(i)
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
function BLT.preferences() local p=BLT.preferenceView or {};BLT.preferenceView=p;for path in pairs(UI.settings_schema()) do local obj,k=UI.settings_slot(path);p[path]=obj[k] end;return p end
function BLT.captureEnvelope() return {settings=BLT.preferences()} end
BLT.envelopeDefaults=BLT.copy(BLT.captureEnvelope())


-- BEGIN BLT SHORTCUTS 1.0.3 (generated from _shared/BLT_Shortcuts.lua)
local BLTShortcuts=(function()
local M={}
local special={[8]=8,[9]=9,[13]=13,[27]=27,[32]=32,
 [1752132965]=32804,[30064]=32806,[1885828464]=32801,[1818584692]=32805,
 [1919379572]=32807,[6647396]=32803,[1685026670]=32808,[1885824110]=32802,
 [6909555]=32813,[6579564]=32814}
for i=1,12 do
 local code=0;for c in ('f'..i):gmatch('.') do code=(code<<8)|c:byte() end
 special[code]=111+i
end
function M.decode(k,cap)
 local char=k;local mods=cap&60
 if k>=257 and k<=282 then return k-192,mods|20,char
 elseif k>=321 and k<=346 or k>=353 and k<=378 then k=k-256;mods=mods|16 end
 if k>=1 and k<=26 and not special[k] then return k+64,(mods&36)~=0 and mods or mods|4,char end
 if (k>>24)==117 then char=k&0xffffff;k=char end
 if k>=97 and k<=122 then return k-32,mods,char end
 if k>=65 and k<=90 or k>=48 and k<=57 then return k,mods,char end
 return special[k],mods,char
end
function M.read(path)
 local f=io.open(path,'rb');if not f then return {} end
 local ok,raw=pcall(f.read,f,4*1024*1024+1);pcall(f.close,f)
 if not ok or not raw or #raw>4*1024*1024 then return {} end
 local bindings,scopes={},{}
 for line in raw:gmatch('[^\r\n]+') do
  local flags,key,command,section,tail=line:match('^KEY%s+(%d+)%s+(%d+)%s+(%S+)%s+(%d+)(.*)$')
  flags,key,section=tonumber(flags),tonumber(key),tonumber(section)
  if flags and flags<=63 and key<=65535 and (tail:match('^%s*$') or tail:match('^%s+#')) and (section==0 or section==100 or section==102 or section==103) then
   local id=flags..':'..key
   if section==102 or section==103 then
    if command=='1' or command=='101' then scopes[#scopes+1]={id=id,flags=flags,key=key,section=section-102} end
   else
    bindings[section..':'..id]=command
   end
  end
 end
 local rows={}
 for _,row in ipairs(scopes) do
  row.command=bindings[(row.section==1 and 100 or 0)..':'..row.id]
  if row.command and row.command~='0' then rows[#rows+1]=row end
 end
 return rows
end
function M.install(api,view,options)
 local getchar=view.getchar
 local state={rows={},reload_at=0,focus=nil}
 local function forward(k)
  local cap=view.mouse_cap or 0
  if options.blocked() then return false end
  local space=k==32 and (cap&60)==0
  if space then
   if (getchar(65537)&2)==0 then return true end
   if view.spacePressed and not view.spacePressed() then return true end
  end
  if options.localKey(k,cap) then return false end
  local now=api.time_precise()
  if now>=state.reload_at then
   state.reload_at=now+2
   state.rows=M.read(api.GetResourcePath()..'/reaper-kb.ini')
  end
  if #state.rows==0 and not space then return false end
  local vk,mods,char=M.decode(k,cap)
  local flags=((mods&4)~=0 and 8 or 0)|((mods&8)~=0 and 4 or 0)|(mods&48)
  local physical
  -- Physical key state disambiguates numpad and layout-dependent virtual keys.
  local ambiguous=vk and vk>=48 and vk<=57 or k==8 or k==9 or k==13
  local needs_physical=not vk or ambiguous
  if needs_physical and type(api.JS_VKeys_GetState)=='function' then
   local ok,value=pcall(api.JS_VKeys_GetState,0)
   if ok and type(value)=='string' and #value>=255 then physical=value end
  end
  local section=(api.GetPlayState()&4)~=0 and 1 or 0
  local found,score=nil,-1
  for _,row in ipairs(state.rows) do
   if row.section<=section and (row.flags&62)==flags then
    local virtual=(row.flags&1)~=0
    local held=virtual and physical and (physical:byte(row.key&0x7fff) or 0)~=0
    local matched=virtual and vk and (row.key&0x7fff)==(vk&0x7fff) and (not ambiguous or held) or not virtual and row.key==char
    local base=row.key&0x7fff
    local layout_key=base>=96 and base<=111 or base>=186 and base<=226
    local ctrl_letter=(mods&36)~=0 and (k==8 or k==9 or k==13) and base==k+64
    if matched or held and (not vk and layout_key or vk and vk>=48 and vk<=57 and base>=96 and base<=105 or ctrl_letter) then
     local rank=row.section*4+(held and 2 or 0)+(matched and 1 or 0)
     if rank>score then found,score=row,rank
     elseif rank==score and found and found.id~=row.id then found=nil end
    end
   end
  end
  if not found then
   if not space then return false end
   if options.beforeGlobal then options.beforeGlobal(k) end
   return pcall(api.Main_OnCommand,40044,0)
  end
  if options.beforeGlobal then options.beforeGlobal(k) end
  if (found.flags&1)~=0 and type(api.CF_SendActionShortcut)=='function' then
   local ok,result=pcall(api.CF_SendActionShortcut,api.GetMainHwnd(),found.section*100,found.key,mods)
   if ok and (result==true or result==1) then return true end
   if not space then return false end
  end
  local command=tonumber(found.command) or api.NamedCommandLookup(found.command)
  if space and (not command or command<=0) then command=40044 end
  if not command or command<=0 then return false end
  return pcall(api.Main_OnCommand,command,0)
 end
 view.getchar=function(query,...)
  local k,unicode=getchar(query,...)
  if query==65536 or query==65537 then
   local focused=(k&2)~=0
   if focused~=state.focus then state.focus=focused;state.reload_at=0 end
  elseif (query==nil or query==0) and k>0 then
   local ok,sent=pcall(forward,k)
   if ok and sent then return 0,0 end
  end
  return k,unicode
 end
 return state
end
return M
end)()
-- END BLT SHORTCUTS
if not R.ImGui_GetBuiltinPath or not R.JS_LICE_CreateBitmap or not R.JS_LICE_LoadPNGFromMemory then
 Language.mb('ReaImGui 0.10以降と js_ReaScriptAPI が必要です。ReaPackで導入・更新してください。','Envelope Canvas Track',0);return
end
local ok,value=pcall(BLT.CanvasHost.new,R,'BLT Envelope Canvas Track',W,H+26,SECTION)
if not ok then Language.mb(BLT.publicError(value),'Envelope Canvas Track',0);return end
Host=value;Host.minWidth,Host.minHeight,Host.persistSize=1000,740,true
Host.captureRight=true
local savedW,savedH=tonumber(R.GetExtState(SECTION,'window_w')),tonumber(R.GetExtState(SECTION,'window_h'))
Host.width=finite(savedW) and clamp(savedW,1000,2200) or W
Host.height=finite(savedH) and clamp(savedH,740,1800) or H+26
local I,ctx=Host.I,Host.ctx
gfx=Host.g
U=BLT.Controls.new(gfx,R.time_precise,C);U.font,U.minFontSize=Host.faces[1],7
function UI.number_commit()
 if U.editor and U.editor.edit then U.editor:close(false) end
 return true
end
local function cancelEdit()
 if U.editor then U.editor:close(true) end
 Track.finish();UI.cancel_preview();U.capture=nil
end
menu=BLT.PresetMenu.new(Host,U,{presets=Presets,language=Language,commit=UI.number_commit,
 layout={width=292,rowHeight=29,headerHeight=36,visiblePresets=8,hoverDelay=1},busy=function() return A.busy or A.drag~=nil end})
shell=BLT.Shell.new(Host,U,R,{
 title='ENVELOPE CANVAS TRACK',subtitle='TRACK AUTOMATION DRAWING  トラックのオートメーション描画',
 barTitle='E N V E L O P E   C A N V A S   T R A C K',section=SECTION,persist=true,
 layout={iconX=W-102,iconY=9,iconScale=.78,footerSize=8},
 language=Language.code,languageChanged=function(code) Language.set(code);UI.dirty() end,
 translate=Language.message,store=BLT.store,headerIcon=BLT.EnvelopeTrackIcon,
 iconMode=function() shell.icon.state.tones=UI.defs;return 'track' end,
 stepPreset=function(direction) UI.number_commit();Presets.step(direction) end,
 drawPresets=function(owner) menu:draw(owner) end,presetSize=function() return menu:size() end,dirty=Presets.dirty})
U.editor=BLT.TextInput.new(Host,U,shell.typography)
controls=BLT.EnvelopeWidgets.new(Host,U,density)
canvas=BLT.EnvelopeCanvas.new(Host,R,C)
Media.state=A;Media.onchange=wake_visuals
mediaGraphics.getchar=function() return Host.focused and 6 or 4 end
BLT.blocked=function() return UI.context~=nil or shell.popupOpen or A.spectrum_menu_open or Host.drag~=nil or gfx.mouse_y<26 and not A.pointer_capture end
BLT.recoverInput=function(_,err) cancelEdit();U.down=false;BLT.logError(err);wake_visuals() end
BLT.attachPresets({R=R,section=SECTION,defaults=BLT.envelopeDefaults,capture=BLT.captureEnvelope,
 valid=BLT.validTrackSettings,apply=BLT.applyTrackSettings,busy=function() return A.busy or A.drag~=nil end,
 revision=function() return 0 end,
 commit=function() UI.number_commit();Track.finish();UI.cancel_preview();return true end,
 cancelEdit=cancelEdit,wake=wake_visuals})
function UI.activation_press(down)
 return down and Host.hovered
end
function UI.open_menu(rows,choose,separator,selected)
 UI.number_commit();Track.finish();UI.cancel_preview()
 UI.context={rows=rows,choose=choose,separator=separator,selected=selected,opening=true}
 UI.refresh()
end
local function contextMenu()
 local context=UI.context
 if not context then return end
 if context.opening then I.OpenPopup(ctx,'##track_actions');context.opening=false end
 I.PushFont(ctx,Host.font,14)
 if I.BeginPopup(ctx,'##track_actions') then
  local choice
  for i,text in ipairs(context.rows) do
   if i==context.separator then I.Separator(ctx) end
   if I.Selectable(ctx,text..'##track_action_'..i,i==context.selected) then choice=i end
  end
  I.EndPopup(ctx)
  if choice then UI.context=nil;UI.safe(function() context.choose(choice) end);UI.refresh() end
 else UI.context=nil end
 I.PopFont(ctx)
end
local themeSignature={}
function UI.theme_sync()
 local index=0;local changed=false
 local function check(v) index=index+1;if themeSignature[index]~=v then themeSignature[index]=v;changed=true end end
 check(shell.theme.enabled)
 for _,color in ipairs({C.bg,C.field,C.text,C.accent,C.accent2}) do for i=1,3 do check(color[i]) end end
 if not changed then return end
 for _,d in ipairs(UI.defs) do d.original_color=d.original_color or d.color;d.color=shell.theme.enabled and BLT.EnvelopeWidgets.fit(d.original_color,C.bg,C.text) or d.original_color end
 if BLT.EnvelopeSpectrogram.configure_palette(C,shell.theme.enabled) then
  local j=A.spectrum_job
  if j and j.data.complete then UI.remember_spectrum_data(j.data);UI.stop_spectrum() end
  while #A.spectrum_cache>0 do UI.drop_spectrum(#A.spectrum_cache) end
  UI.ensure_spectrum()
 end
 canvas.valid=false
end
function UI.geometry()
 local content=max(1,gfx.h-26);scale=max(.25,min(gfx.w/W,content/H))
 ox,oy=(gfx.w-W*scale)/2,26+(content-H*scale)/2-22*scale
 mouse_x,mouse_y=(gfx.mouse_x-ox)/scale,(gfx.mouse_y-oy)/scale
end
function UI.fit_text(text,width,size,kind)
 font(size,kind,false)
 if gfx.measurestr(text)<=width*scale then return text end
 local lo,hi=0,utf8.len(text) or 0
 while lo<hi do
  local mid=floor((lo+hi+1)/2);local finish=utf8.offset(text,mid+1) or #text+1
  if gfx.measurestr(text:sub(1,finish-1)..'…')<=width*scale then lo=mid else hi=mid-1 end
 end
 return text:sub(1,(utf8.offset(text,lo+1) or #text+1)-1)..'…'
end
local buttonOptions={}
function UI.button(id,title,sub,x,y,w,h,fn,enabled,selected,tone)
 local choice=id:match('^mode_') or id:match('^interp_') or id:match('^display_')
 local options=buttonOptions[id] or {};buttonOptions[id]=options
 options.variant=id:match('^clear') and 'clear' or nil
 options.attention=id=='fit' and (A.span<1 or A.view>0) or nil
 options.size=(id=='readcurves' and 15 or id:match('^period_unit_') and 10 or 14)/density
 options.bold=id~='readcurves'
 if not choice and not id:match('^period_unit_') then selected=nil end
 controls:button(id,Language.text(title),x,y,w,h,enabled,selected,tone,options)
 register(id,x,y,w,h,fn,'',enabled)
end

local topControls
function UI.top_controls_layout()
 if topControls and topControls.scale==scale and topControls.dpi==Host.dpi and topControls.face==Host.faces[1] then return topControls end
 local dropdownWidth=0;font(11,1,false)
 for _,item in ipairs(BLT.EnvelopeSpectrogram.scales) do local w=gfx.measurestr(item.name);dropdownWidth=max(dropdownWidth,w/scale) end
 topControls={scale=scale,dpi=Host.dpi,face=Host.faces[1],scaleWidth=math.ceil(dropdownWidth+16+30*density+2)}
 topControls.scaleX=1098-topControls.scaleWidth
 topControls.spectrogramX=topControls.scaleX-158;topControls.waveX=topControls.spectrogramX-96
 topControls.nameWidth=topControls.waveX-44
 return topControls
end
local scaleButtonOptions={size=11/density,bold=false,trailing='menu',center=false,labelInset=8/density}
function UI.spectrum_scale_button()
 local layout=UI.top_controls_layout()
 local enabled=A.display_mode=='spectrogram' and not A.busy and not A.drag
 if enabled then gfx.wheelRegion(ox+layout.scaleX*scale,oy+115*scale,layout.scaleWidth*scale,20*scale) end
 controls:button('spectrum_scale',BLT.EnvelopeSpectrogram.scale_name(A.spectrum_scale),layout.scaleX,115,layout.scaleWidth,20,enabled,nil,nil,scaleButtonOptions)
 register('spectrum_scale',layout.scaleX,115,layout.scaleWidth,20,function()
  if enabled then UI.number_commit();A.spectrum_menu_request=true;UI.refresh() end
 end,Language.code=='JP' and '周波数の尺度を切り替えます。Log：100 Hz～ ／ Extended Log：10 Hz～ ／ Linear・Mel・Bark：0 Hz～'
  or 'Frequency scale. Log: 100 Hz and up / Extended Log: 10 Hz and up / Linear, Mel, Bark: 0 Hz and up',enabled)
end
function UI.spectrum_scale_menu()
 if A.spectrum_menu_request then
  A.spectrum_menu_request=nil
  local b=widgetByID.spectrum_scale
  I.SetNextWindowPos(ctx,Host.originX+sx(b.x),Host.originY+sy(b.y+b.h+4))
  I.OpenPopup(ctx,'BLT_TRACK_SPECTRUM_SCALE')
 end
 I.PushFont(ctx,Host.font,max(10,12*scale))
 I.PushStyleColor(ctx,I.Col_PopupBg,Host.rgba(C.panel[1],C.panel[2],C.panel[3],1))
 I.PushStyleColor(ctx,I.Col_Text,Host.rgba(C.text[1],C.text[2],C.text[3],1))
 if I.BeginPopup(ctx,'BLT_TRACK_SPECTRUM_SCALE') then
  for _,item in ipairs(BLT.EnvelopeSpectrogram.scales) do
   if I.Selectable(ctx,item.name,A.spectrum_scale==item.id,0,150*scale,24*scale) then UI.set_spectrum_scale(item.id) end
  end
  I.EndPopup(ctx)
 end
 A.spectrum_menu_open=I.IsPopupOpen(ctx,'BLT_TRACK_SPECTRUM_SCALE')
 I.PopStyleColor(ctx,2);I.PopFont(ctx)
end
local variableOptions={background=false,showState=false,size=12/density,switchScale=.58/density}
function UI.variable_checkbox(group,x,y)
 local on=A[group..'_variable']~=false;local enabled=not A.busy and A.tool=='line'
 local text=Language.code=='JP' and (on and '可変' or '一定') or (on and 'Vary' or 'Fixed')
 local _,_,hitWidth=U:toggle('variable_'..group,text,on,x/density,y/density,72/density,20/density,enabled,variableOptions)
 register('variable_'..group,x,y,hitWidth*density,20,function() UI.toggle_variable(group) end,
  Language.code=='JP' and 'ON：可変 / OFF：一定（変動先を開始にリンク）' or 'ON: variable / OFF: fixed (target follows start)')
end
function UI.number_open(key)
 local id='number_'..key;local s=U:state(id)
 s.done=s.done or function(raw)
  local n=tonumber(raw)
  if UI.number_enabled(key) then UI.number_set(key,n) end
 end
 U.editor:open(id,UI.number_text(key,A[key]),s.done);U.focus=id
end
function UI.number_field(key,title,x,y,w,unit)
 local enabled=not A.busy and A.tool=='line' and UI.number_enabled(key)
 controls:number('number_'..key,UI.number_text(key,A[key]),x,y,w,28,enabled)
 label(title,x+6,y,12,enabled and C.muted or C.disabled,1,58,28,4)
 label(unit,x+w-22,y,10,enabled and C.muted or C.disabled,1,18,28,2|4)
 local hint=key:match('_duration$') and (Language.code=='JP' and '開始から変動先までの時間。大きいほどゆっくり変化' or 'Time to target; larger values change more slowly') or key:match('_curve$') and (Language.code=='JP' and '0：直線 / ＋：先に変化 / −：後で変化' or '0: linear / +: early change / -: late change') or ''
 register('number_'..key,x,y,w,28,noop,hint)
end
function UI.number_input(id,down,wheel)
 if U.editor.edit and id==U.editor.edit.id and not A.number_drag then
  gfx.mouse_wheel=0;return true
 end
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
  if U.editor.edit then UI.number_commit() end
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
  if not d.moved and key==d.key then UI.number_open(d.key) end
  A.number_drag=nil;A.pointer_capture=nil;UI.refresh()
 end
 return true
end
local executeOptions={autoComplete=false,finishWhenDisabled=true,size=16/density,bold=true,
 captionSize=10/density,captionY=5/density,captionHeight=14/density,labelY=22/density,labelHeight=23/density}
function UI.primary()
 local enabled=UI.available('apply')
 executeOptions.enabled,executeOptions.busy=enabled,A.busy
 executeOptions.caption=Language.code=='JP' and '既存分は延伸・統合' or 'EXTEND / MERGE EXISTING'
 U:execute('apply',Language.text('表示範囲をオートメーション化'),390/density,767/density,444/density,52/density,executeOptions)
 register('apply',390,767,444,52,UI.apply,'',enabled)
end


local layerEnableOptions={led='top',size=11/density,bold=true}
function UI.layer_cards()
 for i,q in ipairs(UI.defs) do
  local x,cy,cw=UI.card_geometry(i);local layer=A.layers[q.key];local enabled=layer.env~=nil;local visible=layer.visible
  local tint=enabled and q.color or C.muted;local palette=controls:tone(tint)
  local _,_,held,state=U:interaction('layer_'..q.key,x/density,cy/density,(cw-74)/density,30/density,true)
  local frame=state.frame or {};state.frame=frame
  frame.panel,frame.selected=true,A.layer==q.key
  frame.hot=frame.selected and max(.24,state.hover) or state.hover
  frame.pressed,frame.lightX,frame.palette=held,state.lightX,palette
  U:frame(x/density,cy/density,cw/density,61/density,frame)
  if enabled and visible then controls:outline(x,cy,cw,61,palette) end
  label(q.name,x+8,cy+1,16,enabled and C.text or C.muted,1,cw-84,28,5,true)
  register('layer_'..q.key,x,cy,cw-74,30,function() UI.number_commit();A.layer=q.key;A.selection=nil;UI.dirty() end,'')
  UI.button('copy_'..q.key,'COPY',nil,x+cw-70,cy+4,62,23,function() UI.copy_curve(q.key) end,not A.busy and enabled and A.layer~=q.key and A.layers[A.layer].env~=nil,nil,tint)
  local binding=A.bindings[q.key];local caption=binding and binding.name or Language.message('割当先を選択')
  UI.button('assign_'..q.key,UI.fit_text(caption,cw-102,14,1),nil,x+8,cy+32,cw-86,26,function() UI.assign(q.key) end,not A.busy and A.v~=nil,nil,tint)
  local text=Language.code=='EN' and (visible and 'Shown' or 'Hidden') or (visible and '表示' or '非表示')
  controls:button('visible_'..q.key,text,x+cw-68,cy+32,60,26,not A.busy and enabled,visible,tint,layerEnableOptions)
  register('visible_'..q.key,x+cw-68,cy+32,60,26,function() UI.toggle_lane(q.key) end,'',not A.busy and enabled)
 end
end
function UI.canvas_surface()
 local g=UI.graph
 if A.v and not A.busy then gfx.wheelRegion(ox+g.x*scale,oy+g.y*scale,g.w*scale,g.h*scale)end
 if canvas:begin(g.w,g.h,scale,A.canvas_revision or 0,UI.defs) then
  local savedG,savedScale,savedX,savedY=gfx,scale,ox,oy
  gfx=canvas.g;scale,ox,oy=1,-g.x,-g.y
  local success,err=xpcall(function()
   rect(g.x,g.y,g.w,g.h,C.field)
   if A.display_mode=='spectrogram' and A.spectrum and A.spectrum.scale==A.spectrum_scale then
    BLT.EnvelopeSpectrogram.draw(gfx,A.spectrum,{x=0,y=0,w=g.w,h=g.h},A.view,A.span)
   end
   for i=0,8 do
    local x=g.x+g.w*i/8;line(x,g.y,x,g.y+g.h,C.edge,i%2==0 and .35 or .18)
    local y=g.y+g.h*i/8;line(g.x,y,g.x+g.w,y,C.edge,i==4 and .56 or .21)
   end
   local count=#A.wave
   if A.display_mode=='wave' and count>0 then for px=0,g.w-1 do
    local first=clamp(floor((A.view+px/g.w*A.span)*count)+1,1,count)
    local last=clamp(ceil((A.view+(px+1)/g.w*A.span)*count),1,count);local peak=0
    for j=first,max(first,last) do peak=max(peak,A.wave[j] or 0) end
    local amplitude=min(.47*g.h,peak/max(.001,A.wave_max)*g.h*.38)
    line(g.x+px,g.y+g.h/2-amplitude,g.x+px,g.y+g.h/2+amplitude,C.muted,.28)
   end end
   UI.automation_regions(false);UI.curves()
  end,debug.traceback)
  gfx,scale,ox,oy=savedG,savedScale,savedX,savedY
  if not success then error(err,0) end
  canvas:finish()
 end
 canvas:draw(sx(g.x),sy(g.y),g.w*scale,g.h*scale)
 UI.automation_regions(true)
end
function UI.static()
 widgetCount=0
 local layout=UI.top_controls_layout()
 label(A.v and UI.fit_text(string.format('%s  |  %.3f — %.3f s',A.v.name,A.v.pos,A.v.pos+A.v.len),layout.nameWidth,16,1) or '',24,105,16,C.text,1,layout.nameWidth,27,0,true)
 UI.button('display_wave','波形',nil,layout.waveX,101,88,34,function() UI.set_display('wave') end,not A.busy and not A.drag,A.display_mode=='wave')
 UI.button('display_spectrogram','スペクトログラム',nil,layout.spectrogramX,101,150,34,function() UI.set_display('spectrogram') end,not A.busy and not A.drag,A.display_mode=='spectrogram')
 UI.spectrum_scale_button()
 widgetByID.display_spectrogram.hint=Language.code=='JP' and '選択トラックの時間選択範囲を解析します。尺度変更は解析結果を再利用。トラックFX前の音声を表示します。'
  or 'Analyze the time selection on the selected track, before track FX. Scale changes reuse the analysis.'
 UI.tools_panel()
 local d=UI.def();label(d.code,212,143,12,d.color,3,130,21,0,true)
 label(UI.fit_text(A.bindings[d.key] and A.bindings[d.key].name or Language.message(d.sub),380,12,1),350,141,12,C.muted,1,380,21)
 right_label(A.v and 'LIVE / TRACK AUTOMATION' or 'TRACK / TIME SELECTION',996,141,11,C.muted,3,true)
 UI.canvas_surface()
 if A.display_mode=='spectrogram' then
  local g=UI.graph
  for _,hz in ipairs(UI.spectrum_ticks[A.spectrum_scale]) do
   local y=g.y+g.h*(1-BLT.EnvelopeSpectrogram.position(hz,A.spectrum_scale))
   label(hz>=1000 and string.format('%gk Hz',hz/1000) or hz..' Hz',g.x+7,clamp(y-7,g.y+3,g.y+g.h-17),10,C.muted,3,62,16)
  end
 end

 local g=UI.graph
 local layer=A.layers[A.layer]
 if UI.axisLayer~=layer then
  UI.axisLayer=layer;UI.axisLabels=UI.axisLabels or {}
  for i=0,4 do UI.axisLabels[i+1]=UI.axis_label(A.layer,1-i*.5) end
 end
 for i=0,4 do
  right_label(UI.fit_text(UI.axisLabels[i+1],98,12,3),1100,g.y+i*g.h/4-7,12,d.color,3,false)
 end
 for i=0,4 do label(string.format('%.3f s',UI.output_time(A.view+A.span*i/4)),g.x+g.w*i/4-(i==4 and 90 or 0),548,12,C.muted,3,120,20) end
 label(A.tool=='line' and 'クリック：描画  ·  ホイール：横幅の開始 / Ctrl：縦幅の開始 / Shift：微調整  ·  Alt：位相反転' or A.tool=='select' and 'ドラッグ：範囲選択  ·  枠内：移動  ·  辺／角：変形  ·  Alt＋線：曲率' or 'ドラッグ：描画／点移動  ·  Ctrl：点をつかまず描画  ·  Alt＋線：曲率  ·  右ドラッグ：範囲選択',212,573,13,C.muted,1,866,23)
 if A.tool=='line' then
  label(Language.code=='JP' and '変化速度：到達までの時間（大きいほど遅い）  ·  曲率：0＝直線 / ＋＝先に変化 / −＝後で変化' or 'Time: duration to target (larger = slower) · Curve: 0 linear / + early / - late',212,594,12,C.muted,1,866,20)
 end
 UI.layer_cards()
 UI.primary()
 for i=#widgets,widgetCount+1,-1 do widgets[i]=nil end
end
function UI.analysis_overlay()
 local job=A.display_mode=='spectrogram' and A.spectrum_job
 if not job then return end
 local g=UI.graph;local w,h=300,88;local x,y=g.x+(g.w-w)/2,g.y+(g.h-h)/2
 local progress=clamp(BLT.EnvelopeSpectrogram.progress(job),0,1)
 rect(g.x,g.y,g.w,g.h,C.field,.62)
 controls:panel(x,y,w,h,C.accent2)
 local title=job.kind=='render' and (Language.code=='JP' and '表示更新中' or 'Updating display')
  or (Language.code=='JP' and '解析中' or 'Analyzing')
 label(string.format('%s  %d%%',title,floor(progress*100)),x+20,y+14,17,C.text,1,w-40,28,5,true,true)
 rect(x+24,y+59,w-48,6,C.edge,.75)
 if progress>0 then rect(x+24,y+59,(w-48)*progress,6,C.accent2) end
end
UI.spectrum_ticks={linear={0,5000,10000,15000,20000,24000},log={100,200,500,1000,2000,5000,10000,20000},
 extended_log={10,20,50,100,200,500,1000,2000,5000,10000,20000},mel={0,500,1000,2000,4000,8000,16000,24000},
 bark={0,200,500,1000,2000,4000,8000,16000,24000}}
local tipID,tipSince
local function tooltip(now)
 local tip
 if not shell.popupOpen and not A.spectrum_menu_open and Host.focused and (gfx.mouse_cap&3)==0 then
  for i=#widgets,1,-1 do local w=widgets[i];if inside(w.x,w.y,w.w,w.h) then tip=w.hint;break end end
 end
 if not tip or tip=='' then tipID=nil;return end
 if tipID~=tip then tipID,tipSince=tip,now
 elseif now-tipSince>.7 then I.PushFont(ctx,Host.font,12);I.SetTooltip(ctx,Language.message(tip));I.PopFont(ctx) end
end
function UI.draw(now)
 UI.geometry();shell:begin();U.active=Host.focused;U.themeEnabled=shell.theme.enabled
 UI.theme_sync()
 color(C.bg);gfx.rect(0,0,gfx.w,gfx.h,1)
 U.scale,U.ox,U.oy=scale,ox,oy+22*scale;shell:header(W)
 local key=gfx.getchar();local wheel=gfx.mouse_wheel or 0
 U:begin(density*scale,ox,oy,0)
 gfx.mouse_wheel=wheel
 UI.interact();gfx.mouse_wheel=0
 UI.key(key)
 local released=U.released;U.released=false
 UI.static()
 UI.playhead();UI.point_highlight();UI.segment_highlight();UI.mode_overlay()
 local graph=UI.graph
 if Host.focused and A.v and inside(graph.x,graph.y,graph.w,graph.h) then
  local u=A.view+(mouse_x-graph.x)/graph.w*A.span;local value=clamp(1-2*(mouse_y-graph.y)/graph.h,-1,1)
  line(mouse_x,graph.y,mouse_x,graph.y+graph.h,C.accent2,.23);line(graph.x,mouse_y,graph.x+graph.w,mouse_y,C.accent2,.12)
  label(string.format('%.3fs  /  %s',UI.output_time(u),UI.axis_label(A.layer,value)),mouse_x-105,mouse_y+21,13,UI.def().color,3,210,21,1)
 end
 UI.analysis_overlay()
 local status=A.spectrum_job and string.format(A.spectrum_job.kind=='render' and 'スペクトログラムの表示を更新中  %d%%' or 'スペクトログラムを解析中  %d%%',floor(BLT.EnvelopeSpectrogram.progress(A.spectrum_job)*100))
  or A.wave_job and string.format('波形を読み込み中  %d%%',floor(A.wave_job.index/A.wave_job.total*100))
  or BLT.notice or A.status~='' and A.status or not A.v and 'トラックと時間範囲を選択してください。' or ''
 if Media.waiting then status=Media.message(SECTION) end
 U.scale,U.ox,U.oy=scale,ox,oy+22*scale;shell:footer(status,A.warning or A.conflict or BLT.noticeBad,W,H,Core.VERSION)
 U.scale,U.ox,U.oy=density*scale,ox,oy
 U.released=released;U:finish();shell:drawBar();contextMenu();UI.spectrum_scale_menu();tooltip(now)
end
Host:bindShortcuts()
gfx.getchar=function(query)
 if query then return Host.focused and 6 or 4 end
 local key=Host.key or 0
 if key>=97 and key<=122 then
  local primary=(gfx.mouse_cap&4)~=0 or Host.mac and (gfx.mouse_cap&32)~=0 and (key==97 or key==99 or key==118 or key==122)
  if primary then key=key-96 elseif (gfx.mouse_cap&8)~=0 then key=key-32 end
 end
 return key
end
BLTShortcuts.install(R,gfx,{
 blocked=function() return U.editor.edit~=nil or shell.popupOpen or A.drag~=nil or A.number_drag~=nil or A.busy or UI.context~=nil or A.spectrum_menu_open end,
 beforeGlobal=UI.number_commit,
 localKey=function(k,cap) return k==27 or k==13 or k==25 or k==26 or k==6579564 or k==127 or k>=49 and k<=51
  or (cap&4)~=0 and (k==89 or k==121 or k==90 or k==122) end})
local finalized=false
function UI.close()
 if finalized then return end;finalized=true
 BLT.cleanup(Track.finish);BLT.cleanup(UI.number_commit);BLT.cleanup(UI.save_settings);BLT.cleanup(UI.stop_wave)
 BLT.cleanup(UI.stop_spectrum,true);A.spectrum_data_cache={};A.spectrum_signature=nil;A.spectrum_sources=nil;A.spectrum_fade_editing=nil;A.wave={};A.v=nil
 BLT.cleanup(canvas.close,canvas);BLT.cleanup(Host.close,Host);BLT.cleanup(shell.close,shell)
end
R.atexit(UI.close)
if R.set_action_options then R.set_action_options(2) end
UI.load_settings();UI.safe(UI.load_selection)
local inputState,worldState={},{}
local function changed(state,...)
 local different=false
 for i=1,select('#',...) do local value=select(i,...);if state[i]~=value then state[i]=value;different=true end end
 return different
end
function UI.loop()
 if finalized then return end
 local begun=false
 local success,err=xpcall(function()
  local now=R.time_precise();Media.tick();UI.safe(function() UI.poll(now) end);UI.poll_playhead();shell.theme.tick(now)
  if A.wave_job and R.EnumProjects(-1,'')==A.wave_job.v.project then UI.safe(UI.wave_step) end
  if A.display_mode=='spectrogram' then UI.safe(UI.ensure_spectrum) end
  if A.spectrum_job and R.EnumProjects(-1,'')==A.spectrum_job.v.project then UI.safe(UI.spectrum_step) end
  if BLT.noticeUntil and now>=BLT.noticeUntil then BLT.notice,BLT.noticeUntil=nil,nil;wake_visuals() end
  if changed(worldState,A.canvas_revision,A.status,A.warning,A.v,A.wave_job,A.spectrum_job,A.spectrum_fade_editing,Language.code,C.bg,Presets.current,Host.requestReset,shell.icon.dirty) then A.content_dirty=true end
  local interactive=U.editor.edit or shell.popupOpen or Host.drag or shell.hoverID or A.drag or A.number_drag or U.capture or UI.context or A.spectrum_menu_open or A.playing
  local animating=(A.hover_segment and now<(A.segment_flash or 0)+.22) or (A.hover_node and now<(A.point_flash or 0)+.22) or U:attentionAnimating() or U:executeAnimating('apply') or shell.icon:animating(now) or now<(A.number_flash_until or 0)
  if not A.content_dirty and not A.busy and not A.wave_job and (not A.spectrum_job or Media.waiting or A.spectrum_fade_editing) and not (A.v and A.display_mode=='spectrogram' and not A.spectrum and not A.spectrum_failed and not Media.waiting and not A.spectrum_fade_editing) and now>=awakeUntil and not interactive and not animating and Host:idle(now) then
   U.now=now;shell.icon.lastTime=now;R.defer(UI.loop);return
  end
  if Host.idleWake then wake_visuals();Host.idleWake=nil end
  if Host.requestReset then Host.width,Host.height=W,H+26 end
  local shown=Host:begin();begun=true
  if shown then
   local cap=(Host.hovered or Host.focused or A.pointer_capture or Host.drag) and gfx.mouse_cap or 0
   if changed(inputState,gfx.mouse_x,gfx.mouse_y,cap,Host.key,gfx.w,gfx.h,Host.dpi,Host.originX,Host.originY,Host.focused) or
    gfx.mouse_wheel~=0 or (cap&1)~=0 or interactive then wake_visuals() end
   A.active=Host.focused;A.content_dirty=false;UI.draw(now)
   Host.pointerCapture=A.pointer_capture or A.drag or A.number_drag
   if not Host.focused then awakeUntil=min(awakeUntil,now+.5) end
  end
  local keep=Host:finish();begun=false
  if not keep or A.closing then UI.close() else R.defer(UI.loop) end
 end,debug.traceback)
 if not success then
  if begun then pcall(Host.finish,Host) end
  UI.close();Language.mb(BLT.publicError(err),'Envelope Canvas Track | エラー',0)
 end
end
UI.loop()
