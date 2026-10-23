-- @description SPECTRAL NORMALIZER
-- @version 0.6.8
-- @author Balrulu
-- @provides
--   . > ../
-- @changelog
--   BLT SERIES Beta TEST UPLOAD
-- @about
--   BLT SERIES Beta TEST UPLOAD

-- BLT external storage 1.1.0. Embedded; large data stays beside this script.
local reaper=reaper
do
-- BEGIN BLT NATIVE DIALOGS 1.1.0 (generated from _shared/BLT_NativeDialogs.lua)
local BLTNativeDialogs=(function()
 local M={}
 function M.install(api,view)
  local P=setmetatable({}, {__index=api})
  local title,depth=nil,0
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
  local function restore(session)
   for i=#session.windows,1,-1 do
    local entry=session.windows[i]
    local checked,exists=pcall(valid,entry.hwnd)
    if not checked or exists then
     if entry.enabled then pcall(api.JS_Window_Enable,entry.hwnd,true) end
     if entry.topmost then pcall(api.JS_Window_SetZOrder,entry.hwnd,'TOPMOST') end
    end
   end
   -- Do not take focus back if the user switched to another application.
   pcall(function()
    local current=api.JS_Window_GetForeground and api.JS_Window_GetForeground()
    if session.foreground and valid(session.foreground) and (current==session.main or owned(current,session.main)) then
     for _,entry in ipairs(session.windows) do
      if entry.enabled and (session.foreground==entry.hwnd or owned(session.foreground,entry.hwnd)) then
       if api.JS_Window_SetForeground then api.JS_Window_SetForeground(entry.hwnd) end
       break
      end
     end
    end
   end)
  end
  local function call(fn,...)
   if depth>0 then return fn(...) end
   local args=table.pack(...);local session={windows={}};depth=depth+1
   local result=table.pack(xpcall(function() suspend(session);return fn(table.unpack(args,1,args.n)) end,debug.traceback))
   depth=depth-1;restore(session)
   if not result[1] then error(result[2],0) end
   return table.unpack(result,2,result.n)
  end
  for _,name in ipairs({'GetUserInputs','MB','ShowMessageBox','GetUserFileNameForRead','JS_Dialog_BrowseForSaveFile','JS_Dialog_BrowseForOpenFiles','JS_Dialog_BrowseForFolder','GR_SelectColor'}) do
   local fn=api[name]
   if type(fn)=='function' then P[name]=function(...) return call(fn,...) end end
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

local reaper=create_external_storage(reaper,'BLT_SPECTRAL_NORMALIZER',debug.getinfo(1,'S').source,{'settings'})

-- BLT preset transfer limits 1.1.0. Embedded; no runtime dependency.
local BLTPresetLimits={bytes=16777216,stringBytes=2097152,nodes=262144,entries=8192}
function BLTPresetLimits.show(english)
 reaper.MB(english and 'Preset capacity limit exceeded. Export presets individually instead of as a bundle.' or '容量上限オーバーです。一括ではなく個別に保存してください。','BLT PRESET',0)
end

-- BLT media availability 1.0.2. Pause audio work, never the UI defer loop.

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
 function H:attachImage(image)
  I.Attach(ctx,image);imageCache[image]=true
 end
 function H:releaseImage(image,batched)
  if self.closing or batched then retiredImages[image]=nil;imageCache[image]=nil;I.Detach(ctx,image)
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
    imageCache[image]=nil;retiredImages[image]=nil;I.Detach(ctx,image)
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
 function T:close(cancel)
  local e=self.edit;self.edit=nil
  if e and not cancel then e.done(e.text) end
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
 function T:draw(item)
  local e=self.edit and self.edit.id==item.id and self.edit or nil
  if not e then self:idle(item);return end
  local b=item.bounds
  local metrics=self:fontMetrics(b)
  local x,y=floor(host.originX+b.x),floor(host.originY+b.y)
  I.PushFont(ctx,host:fontFor(b.face,b.bold),metrics and metrics.size or max(8,floor(b.size+.5)))
  local width=b.w
  if b.align=='right' then
   local measured=I.CalcTextSize(ctx,e.text)
   local offset=max(0,width-measured-2)
   x=floor(host.originX+b.x+offset);width=width-offset
  end
  local height=I.GetTextLineHeight(ctx);local padY=0
  if metrics then
   y=floor(host.originY+b.y+max(0,(b.h-metrics.height)/2)+max(0,(metrics.height-height)/2))
  else padY=max(0,floor((b.h-height)/2)) end
  if b.opticalCenter then
   local dpi=host.dpi or 1
   local offset=host:numberOffset(I.GetFontSize(ctx))
   y=floor((host.originY+b.y+(b.h-height)/2-padY+offset)*dpi+.5)/dpi
  end
  I.SetCursorScreenPos(ctx,x,y)
  I.PushStyleVar(ctx,I.StyleVar_FramePadding,0,padY)
  I.PushStyleColor(ctx,I.Col_Text,item.enabled and self.textColor or self.disabledColor)
  I.BeginDisabled(ctx,not item.enabled);I.SetNextItemWidth(ctx,width)
  if e.frames==0 then I.SetKeyboardFocusHere(ctx) end
  local _,text=I.InputText(ctx,item.label,e.text,I.InputTextFlags_AutoSelectAll)
  e.text=text;local deactivated=I.IsItemDeactivated(ctx)
  local cancel=deactivated and I.IsKeyPressed(ctx,I.Key_Escape,false)
  local focusLost=not I.IsWindowFocused(ctx);local outside
  if I.IsMouseClicked(ctx,0) or I.IsMouseClicked(ctx,1) then
   local mx,my=I.GetMousePos(ctx);local hit=b.hit or b
   local left,top=host.originX+hit.x,host.originY+hit.y
   outside=mx<left or mx>=left+hit.w or my<top or my>=top+hit.h
  end
  I.EndDisabled(ctx);I.PopStyleColor(ctx);I.PopStyleVar(ctx);I.PopFont(ctx)
  e.frames=e.frames+1
  if cancel then self:close(true)
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
  I.PushStyleVar(ctx,I.StyleVar_FrameRounding,0);I.PushStyleVar(ctx,I.StyleVar_FrameBorderSize,0)
  I.PushStyleVar(ctx,I.StyleVar_DisabledAlpha,1)
  I.PushStyleColor(ctx,I.Col_FrameBg,0);I.PushStyleColor(ctx,I.Col_FrameBgHovered,0);I.PushStyleColor(ctx,I.Col_FrameBgActive,0)
  I.PushStyleColor(ctx,I.Col_TextSelectedBg,color(C.accent,.65));I.PushStyleColor(ctx,I.Col_NavCursor,0)
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
 function V:slider(value,x,y,w,h,enabled,tone)
  local cy=y+h/2;local left,right=x+6,x+w-6
  local a=enabled and .85 or .28;local color=tone or C.ice
  ui:rect(left/density,(cy-1.25)/density,(right-left)/density,2.5/density,C.edge,.65)
  ui:rect(left/density,(cy-1.25)/density,(right-left)*max(0,min(1,value))/density,2.5/density,color,a)
  local px=(left+(right-left)*max(0,min(1,value)))/density
  ui:disc(px,cy/density,6/density,C.bg,.95);ui:disc(px,cy/density,4.5/density,color,a)
 end
 return V
end
return M
end)()

BLT.SpectralCanvas=(function()
local M={}
local min,max,floor,ceil=math.min,math.max,math.floor,math.ceil
local function byte(v) return floor(max(0,min(1,v))*255+.5) end
function M.new(host,api,C,Core)
 local V={};local G={};V.g=G
 local bitmap,image,width,height,dpi,color,alpha
 local keys={'bg','field','edge','muted','accent2','focus2','text'}
 local signature={}
 function G.set(r,g,b,a) color=0xff000000|(byte(r)<<16)|(byte(g)<<8)|byte(b);alpha=a or 1 end
 function G.rect(x,y,w,h) api.JS_LICE_FillRect(bitmap,floor(x*dpi+.5),floor(y*dpi+.5),max(1,ceil(w*dpi)),max(1,ceil(h*dpi)),color,alpha,'COPY') end
 function G.line(x,y,xx,yy,aa) api.JS_LICE_Line(bitmap,x*dpi,y*dpi,xx*dpi,yy*dpi,color,alpha,'COPY',aa~=0) end
 function G.circle(x,y,r) api.JS_LICE_FillCircle(bitmap,x*dpi,y*dpi,r*dpi,color,alpha,'COPY',true) end
 function V:begin(w,h,scale,revision)
  dpi=ceil(host.dpi or 1)*scale
  local iw,ih=max(1,ceil(w*dpi)),max(1,ceil(h*dpi))
  local changed=not image or not self.valid or self.revision~=revision or self.scale~=dpi or width~=iw or height~=ih
  local index=0
  local function check(c)
   for i=1,3 do index=index+1;if signature[index]~=c[i] then signature[index]=c[i];changed=true end end
  end
  for _,key in ipairs(keys) do check(C[key]) end

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
 function V:nearest(curve,g,axis,upper,revision,mx,my,scale)
  local pad=14/scale
  if mx<g.x-pad or mx>g.x+g.w+pad or my<g.y-pad or my>g.y+g.h+pad then return end
  local cache=self.nodes or {xy={}};self.nodes=cache
  local changed=cache.points~=curve.points or cache.count~=#curve.points or cache.axis~=axis or cache.upper~=upper or
   cache.revision~=revision or cache.x~=g.x or cache.y~=g.y or cache.w~=g.w or cache.h~=g.h
  if changed then
   cache.points,cache.count,cache.axis,cache.upper,cache.revision=curve.points,#curve.points,axis,upper,revision
   cache.x,cache.y,cache.w,cache.h=g.x,g.y,g.w,g.h
   for i,p in ipairs(curve.points) do
    local q=cache.xy[i] or {};cache.xy[i]=q
    q[1],q[2],q[3]=g.x+Core.to_axis(max(0,min(upper,p.x)),axis,upper)*g.w,g.y-p.y/120*g.h,p.x>=-1e-8 and p.x<=upper+1e-8
   end
  elseif cache.mx==mx and cache.my==my and cache.scale==scale then return cache.nearest end
  local best,dist=nil,14*14
  for i=1,cache.count do
   local p=cache.xy[i]
   if p[3] then local dd=((mx-p[1])*scale)^2+((my-p[2])*scale)^2;if dd<=dist then best,dist=i,dd end end
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

BLT.SpectralIcon=(function()
local M={width=96,height=52,modes={'spectral'}}
local sin,pi,floor,min,max=math.sin,math.pi,math.floor,math.min,math.max
local points={{0,45},{7,41},{12,27},{18,39},{24,15},{31,35},{38,23},{45,43},{52,19},{60,32},{67,10},{74,37},{82,21},{89,42},{96,28}}
local function hash(n,salt) return (sin(n*12.9898+salt*78.233)*43758.5453)%1 end
function M.update() end
function M.draw(p)
 local C=p.C
 p:line(0,49,96,49,C.edge2,.24,1)
 for i=2,#points do
  local a,b=points[i-1],points[i]
  p:line(b[1],b[2],b[1],49,C.ice,.10,1)
  p:line(a[1],a[2],b[1],b[2],C.accent,.11,5)
  p:line(a[1],a[2],b[1],b[2],C.ice,.88,1.8)
 end
end
function M.emit(s,n,p)
 local a,b,c,d=hash(n,21),hash(n,22),hash(n,23),hash(n,24)
 local segment=max(1,min(#points-1,floor(a*(#points-1))+1));local q=hash(n,25)
 local first,last=points[segment],points[segment+1]
 p.x,p.y=first[1]+(last[1]-first[1])*q,first[2]+(last[2]-first[2])*q
 p.life,p.r,p.phase,p.sway,p.vy,p.vx=2.8+b*1.55,.65+a*.75,c*pi*2,2+d*3,4+b*4,(c-.5)*4
 p.glint=n%8==0
end
function M.sample(s,p,age) return p.x+p.vx*age+sin(age*.63+p.phase)*p.sway,p.y-p.vy*age end
return M
end)()
local gfx,Host,U,shell,menu,canvas,controls,C,fonts
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
local mediaGraphics={}
local Media,reaper=create_media_gate(reaper,mediaGraphics)
local Core={VERSION='0.6.4',SECTION='BLT_SPECTRAL_NORMALIZER',MAX_POINTS=1024}
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
local App,UI,Presets={},{},{}
App.empty_samples={};App.store_cache={}
function App.store(section,key,value,persist)
 local id=section..'/'..key;local encoded=tostring(value)
 if App.store_cache[id]~=encoded then R.SetExtState(section,key,encoded,persist);App.store_cache[id]=encoded end
end

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

local settings=Core.defaults()
do local raw=R.GetExtState(SECTION,'settings');if raw~='' then local ok,v=pcall(Core.decode,raw);if ok then settings=v end end end
local saved_tool=R.GetExtState(SECTION,'draw_tool')
if saved_tool~='select' and saved_tool~='free' and saved_tool~='line' then saved_tool='free' end
local A={settings=settings,analysis_method=settings.analysis_method,status='音声アイテムを選択し、目標カーブを描いてください。',warning=false,status_until=0,
 job=nil,pending_job=nil,closed=false,closing=false,dirty=true,active=true,pressed=nil,drag=nil,number_drag=nil,edit=nil,tool=saved_tool,selection=nil,
 pattern=settings.pattern,direction=settings.direction,shape_envelope=settings.shape_envelope,period_percent=settings.period_percent,period_shape=settings.period_shape,height=settings.height,hover_node=nil,point_flash=0,pointer_capture=nil,
 history={},redo={},preset_name=nil,preset_dirty=false,
 source_info='音声アイテム未選択',source_detail='',selection_poll=0,selection_project=nil,selection_revision=nil,selection_count=nil,selection_item=nil,selection_take=nil,last_mouse_cap=0,last_right=false,last_mouse_x=-1,last_mouse_y=-1,modal=nil}
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
 A.settings_encoded=encoded;A.encoded_revision=A.settings_revision;A.encoded_settings=A.settings
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
local function blt_output_directory(project)
 local root=R.GetProjectPathEx(project,'')
 assert(type(root)=='string' and root~='' and not root:find('%z'),
  '音声の保存先を取得できません。プロジェクトのメディア保存先を設定してください。')
 assert(root:match('^%a:[/\\]') or root:sub(1,1)=='/' or root:sub(1,2)=='\\\\',
  '音声の保存先が絶対パスではありません。プロジェクトのメディア保存先を確認してください。')
 R.RecursiveCreateDirectory(root,0)
 return root
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
 p.temp=p.path..'.blt-part';j.raw=assert(io.open(p.temp,'wb'),'プロジェクトのメディア保存先へ書き込めません。保存先とアクセス権を確認してください。')
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
 R.PreventUIRefresh(-1);R.Undo_EndBlock2(j.project,'BLT Spectral Normalizer: Render to new items',4);R.UpdateArrange()
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
  UI.complete()
  App.notice(string.format(L.text('%dアイテム完了。終端の1秒後に別アイテムを作成しました。ピーク保護による最大減衰 %.1f dB。'),count,-reduction),false,12)
 end
 A.dirty=true
end

C={
 bg={.018,.030,.055},bg2={.030,.090,.180},panel={.040,.068,.110},panel2={.055,.125,.205},field={.018,.040,.080},
 edge={.145,.285,.445},edge2={.360,.650,.900},ice={.650,.895,1},disabled={.43,.46,.51},text={.955,.980,1},muted={.690,.780,.875},faint={.390,.505,.635},
 accent={.120,.490,.980},accent2={.650,.895,1},accent3={.045,.235,.520},focus2={.690,.900,1},
 ink={.018,.075,.160},warn={1,.755,.490},red={1,.230,.300}}
local scale,ox,oy,mx,my=1,0,TITLE_H,-1,-1
local widgets,widgetByID={},{}
local widgetCount=0
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
 local dpi=gfx.ext_retina or 1
 if UI.fontDPI~=dpi then
  UI.fontDPI=dpi;UI.metric_cache={};UI.metric_count=0;UI.fit_cache={};UI.fit_count=0
 end
 local content=max(1,gfx.h-TITLE_H);scale=max(.25,min(gfx.w/W,content/H));ox=(gfx.w-W*scale)/2;oy=TITLE_H+(content-H*scale)/2
 mx=(gfx.mouse_x-ox)/scale;my=(gfx.mouse_y-oy)/scale
end
function UI.sx(x) return ox+x*scale end
function UI.sy(y) return oy+y*scale end
function UI.color(c,a) gfx.set(c[1],c[2],c[3],a or 1) end
function UI.rect(x,y,w,h,c,a,fill) UI.color(c,a);gfx.rect(UI.sx(x),UI.sy(y),w*scale,h*scale,fill==false and 0 or 1) end
function UI.line(x,y,x2,y2,c,a) UI.color(c,a);gfx.line(UI.sx(x),UI.sy(y),UI.sx(x2),UI.sy(y2),1) end
function UI.disc(x,y,r,c,a) UI.color(c,a);gfx.circle(UI.sx(x),UI.sy(y),r*scale,1,1) end

function UI.thick_line(x,y,x2,y2,c,a,width)
 local dx,dy=x2-x,y2-y;local length=sqrt(dx*dx+dy*dy);if length<1e-9 then return end
 local nx,ny=-dy/length,dx/length
 for i=0,width-1 do local offset=i-(width-1)/2;UI.line(x+nx*offset,y+ny*offset,x2+nx*offset,y2+ny*offset,c,a) end
end

function UI.gradient(x,y,w,h,a,b,aa,bb,vertical)
 aa=aa or 1;bb=bb==nil and aa or bb;local n=max(1,(vertical and h or w)*scale)
 gfx.gradrect(UI.sx(x),UI.sy(y),w*scale,h*scale,a[1],a[2],a[3],aa,
  vertical and 0 or (b[1]-a[1])/n,vertical and 0 or (b[2]-a[2])/n,vertical and 0 or (b[3]-a[3])/n,vertical and 0 or (bb-aa)/n,
  vertical and (b[1]-a[1])/n or 0,vertical and (b[2]-a[2])/n or 0,vertical and (b[3]-a[3])/n or 0,vertical and (bb-aa)/n or 0)
end
UI.metric_cache={};UI.metric_count=0;UI.fit_cache={};UI.fit_count=0
function UI.font(size,kind,bold)
 kind=kind or 1;local pixels=max(8,floor(size*scale+.5))
 local key=kind..':'..pixels..':'..(bold and 1 or 0)
 gfx.setfont(1,fonts[kind] or fonts[1],pixels,bold and 98 or 0)
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

function UI.inside(x,y,w,h) return mx>=x and mx<=x+w and my>=y and my<=y+h end
function UI.register(id,x,y,w,h,fn,enabled)
 local widget=widgetByID[id]
 if not widget then widget={id=id};widgetByID[id]=widget end
 widget.x,widget.y,widget.w,widget.h=x,y,w,h
 widget.fn,widget.enabled=fn,enabled~=false
 widgetCount=widgetCount+1;widgets[widgetCount]=widget
end
function UI.hit()
 for i=#widgets,1,-1 do local w=widgets[i];if UI.inside(w.x,w.y,w.w,w.h) then return w end end
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
 if flash~=false and (invalid or abs(value-n)>1e-9) then U:flash('field_'..key);A.flash_until=R.time_precise()+.9;A.dirty=true end
 if spec.drawing then if A[key]~=value then A[key]=value;if UI.reset_line_preview then UI.reset_line_preview(true) end end else A.settings[key]=value;A.preset_dirty=true end
 UI.touch_curve()
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
 if not p then return A.preset_dirty or false end
 if A.encoded_settings~=A.settings or A.encoded_revision~=A.settings_revision then
  A.settings_encoded=Core.encode(A.settings);A.encoded_settings=A.settings;A.encoded_revision=A.settings_revision
 end
 return A.settings_encoded~=p.data
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
do
local PresetDelete={
 busy=function() return A.job or A.modal end,english=function() return L.code=='EN' end,
 confirm=function(prompt) return R.MB(prompt,'PRESET',4) end,
 visible=function() return Presets.popup.visiblePresets end,
 notify=function(message) App.notice(message,false) end,changed=function() A.dirty=true end,
 persist=function(oldCount,p)
  if A.preset_name==p.name then
   A.preset_name=nil;A.preset_dirty=true;App.store(SECTION,'current_preset','',true)
  end
  Presets.store()
  for _,prefix in ipairs({'preset_name_','preset_data_'}) do
   local key=prefix..oldCount;R.DeleteExtState(SECTION,key,true);App.store_cache[SECTION..'/'..key]=nil
  end
 end,
}
-- BEGIN BLT PRESET DELETE 1.0.0 (generated from _shared/BLT_PresetDelete.lua)
-- Embedded inside the common preset scope of each BLT application.
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

-- END BLT PRESET DELETE
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
UI.log_ticks={0,10,20,50,100,200,500,1000,2000,5000,10000,20000,40000,48000,60000,80000}
UI.tick_cache={}
UI.noop=function()end
UI.actions={undo=function()App.curve_undo(false)end,redo=function()App.curve_undo(true)end,scale_prev=function()UI.set_scale(-1)end,scale_next=function()UI.set_scale(1)end}
for _,q in ipairs(UI.interpolation_options) do local kind=q[1];UI.actions['interp_'..kind]=function()UI.set_interpolation(kind)end end
for _,q in ipairs(UI.tool_options) do local tool=q[1];UI.actions['tool_'..tool]=function()UI.set_tool(tool)end end
UI.actions.tool_line=function()UI.set_tool('line')end
for _,frequency in ipairs(UI.max_frequencies) do local value=frequency;UI.actions['max_'..value]=function()UI.set_maxfreq(value)end end
for index=1,#Core.PRESETS do local value=index;UI.actions['intensity_'..value]=function()UI.apply_intensity(value)end end
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

function UI.frequency_ticks(s)
 local key=s.scale..':'..s.maxfreq;local ticks=UI.tick_cache[key];if ticks then return ticks end
 ticks={}
 if s.scale==1 then for i=0,8 do ticks[#ticks+1]=i*s.maxfreq/8 end
 else for _,f in ipairs(UI.log_ticks) do if f<=s.maxfreq then ticks[#ticks+1]=f end end;if ticks[#ticks]~=s.maxfreq then ticks[#ticks+1]=s.maxfreq end end
 UI.tick_cache[key]=ticks;return ticks
end
function UI.display_curve()
 local c,d=A.settings.curve,A.drag;if not d or d.mode~='transform' or not d.overwritten then return c end
 local cache=UI.filtered_curve
 if cache and cache.source==c and cache.points==c.points and cache.overwritten==d.overwritten and cache.revision==A.settings_revision then return cache.curve end
 local points={};for _,p in ipairs(c.points) do if not d.overwritten[p] then points[#points+1]=p end end
 local curve={points=points,kind=c.kind,smoothness=c.smoothness}
 UI.filtered_curve={source=c,points=c.points,overwritten=d.overwritten,revision=A.settings_revision,curve=curve}
 return curve
end
function UI.point_position(p)
 local g=UI.graph;local visible=p.x>=-1e-8 and p.x<=A.settings.maxfreq+1e-8
 return g.x+Core.to_axis(clamp(p.x,0,A.settings.maxfreq),A.settings.scale,A.settings.maxfreq)*g.w,g.y-p.y/120*g.h,visible
end

function UI.pointer_value(dx,dy)
 local g=UI.graph;local px,py=mx-(dx or 0),my-(dy or 0);local f=Core.from_axis(clamp((px-g.x)/g.w,0,1),A.settings.scale,A.settings.maxfreq);local value=clamp(-(py-g.y)/g.h*120,-120,0)
 return f,value
end
function UI.screen_to_point(x,y) local g=UI.graph;return {x=Core.from_axis(clamp((x-g.x)/g.w,0,1),A.settings.scale,A.settings.maxfreq),y=clamp(-(y-g.y)/g.h*120,-120,0)} end
function UI.nearest()
 return canvas:nearest(A.settings.curve,UI.graph,A.settings.scale,A.settings.maxfreq,A.settings_revision,mx,my,scale)
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
 if not drag or not drag.changed then App.push_history();if drag then drag.changed=true end end;c.smoothness=amount;c.kind=amount==0 and 'linear' or 'smooth';A.preset_dirty=true;A.dirty=true;UI.touch_curve();if not drag then App.persist() end
end
function UI.set_interpolation(kind) UI.set_smoothness(kind=='linear' and 0 or 1) end

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
  elseif d.mode=='transform' then local b=d.box;local dx,dy=mx-d.mx,my-d.my;local l,r,t,bot=b.x,b.r,b.y,b.b;if d.handle=='' then l=l+dx;r=r+dx;t=t+dy;bot=bot+dy else if d.handle:find('l',1,true) then l=l+dx elseif d.handle:find('r',1,true) then r=r+dx end;if d.handle:find('t',1,true) then t=t+dy elseif d.handle:find('b',1,true) then bot=bot+dy end end;local bw,bh=max(b.r-b.x,1e-8),max(b.b-b.y,1e-8);for _,o in ipairs(d.originals) do local q=UI.screen_to_point(l+(o.x-b.x)/bw*(r-l),t+(o.y-b.y)/bh*(bot-t));o.p.x,o.p.y=q.x,q.y end;d.overwritten={};if d.handle=='' or d.handle:find('[lr]') then for _,p in ipairs(A.settings.curve.points) do if not A.selection[p] then for _,o in ipairs(d.originals) do if abs(o.f-o.p.x)>1e-6 and p.x>=min(o.f,o.p.x)-1e-6 and p.x<=max(o.f,o.p.x)+1e-6 then d.overwritten[p]=true;break end end end end end;table.sort(A.settings.curve.points,function(a,b)return a.x<b.x end);UI.touch_curve();A.preset_dirty=true
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
  else Core.stroke(c,x,y,x,y);A.drag={mode='free',x=x,y=y} end;A.pointer_capture=true;UI.touch_curve();A.preset_dirty=true;A.dirty=true;return true
 end
 local d=A.drag;if d and (d.mode=='straight' or d.mode=='free' or d.mode=='node') then
  if down then local x,y=UI.pointer_value(d.dx,d.dy);local c=A.settings.curve
   if d.mode=='straight' then c.points=Core.copy(d.original);Core.stroke(c,d.x,d.y,x,y)
   elseif d.mode=='free' then if abs(x-d.x)>A.settings.maxfreq/g.w*.5 or abs(y-d.y)>.12 then Core.stroke(c,d.x,d.y,x,y);d.x,d.y=x,y;if #c.points>Core.MAX_POINTS then local tolerance=.08;repeat Core.simplify(c,tolerance);tolerance=tolerance*2 until #c.points<=Core.MAX_POINTS end end
   else local i=d.index;local p=c.points[i];if d.anchor~=nil then x=d.anchor else x=clamp(x,i>1 and c.points[i-1].x+1e-5 or 0,i<#c.points and c.points[i+1].x-1e-5 or 96000) end;if ((mx-d.start_x)*scale)^2+((my-d.start_y)*scale)^2>4 then d.moved=true end;if d.moved then p.x,p.y=x,y end
   end;UI.touch_curve();A.preset_dirty=true;A.dirty=true
  elseif released then if d.mode=='straight' then local x,y=UI.pointer_value();A.settings.curve.points=Core.copy(d.original);Core.stroke(A.settings.curve,d.x,d.y,x,y) elseif d.mode=='free' then Core.simplify(A.settings.curve,.08) end;A.drag=nil;A.pointer_capture=nil;App.persist();A.dirty=true end;return true
 end
 return graph_hit
end
function UI.number_input(hit,down,pressed,released,wheel)
 if U.editor.edit and hit and hit.id==U.editor.edit.id and not A.number_drag and wheel==0 then return true end
 local key=hit and hit.enabled and hit.id:match('^field_(.+)$')
 if key and wheel~=0 and not A.job then
  UI.commit_edit();local ticks=max(1,math.floor(abs(wheel)/120+.5));UI.step_value(key,(wheel>0 and 1 or -1)*ticks,true);gfx.mouse_wheel=0;return true
 end
 if pressed and key and not A.job then
  UI.commit_edit();A.number_drag={key=key,y=my,value=UI.value(key),moved=false};A.pointer_capture=true;return true
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
  if not drag.moved and key==drag.key then UI.open_edit(drag.key)
  else App.persist() end
  A.number_drag=nil;A.pointer_capture=nil;A.dirty=true
 end
 return true
end
function UI.modal_input(hit,down,pressed,released)
 if not A.modal then return false end
 if pressed then UI.commit_edit();A.pressed=hit and hit.id:match('^modal_') and hit.id or nil end
 if released then local id=A.pressed;A.pressed=nil;if id and hit and hit.id==id and hit.enabled then App.safe(hit.fn) end end
 return true
end

function UI.key(k)
 if shell.popupOpen or UI.context then return end
 if U.editor.edit then return end
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

-- BEGIN BLT SHORTCUTS 1.0.2 (generated from _shared/BLT_Shortcuts.lua)
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
  if options.blocked() or options.localKey(k,cap) then return false end
  local now=api.time_precise()
  if now>=state.reload_at then
   state.reload_at=now+2
   state.rows=M.read(api.GetResourcePath()..'/reaper-kb.ini')
  end
  if #state.rows==0 then return false end
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
  if not found then return false end
  if options.beforeGlobal then options.beforeGlobal(k) end
  if (found.flags&1)~=0 and type(api.CF_SendActionShortcut)=='function' then
   local ok,result=pcall(api.CF_SendActionShortcut,api.GetMainHwnd(),found.section*100,found.key,mods)
   return ok and (result==true or result==1)
  end
  local command=tonumber(found.command) or api.NamedCommandLookup(found.command)
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
if not R.ImGui_GetBuiltinPath or not R.JS_LICE_CreateBitmap then
 R.MB('ReaImGui 0.10以降と js_ReaScriptAPI が必要です。ReaPackで導入・更新してください。','BLT Spectral Normalizer',0);return
end
local ok,value=pcall(BLT.CanvasHost.new,R,'BLT Spectral Normalizer',W,H+TITLE_H,SECTION)
if not ok then R.MB(App.public_error(value),'BLT Spectral Normalizer',0);return end
Host=value;Host.minWidth,Host.minHeight,Host.persistSize=1000,740,true
Host.captureRight=true
Host.width=clamp(tonumber(R.GetExtState(SECTION,'window_w')) or W,1000,2200)
Host.height=clamp(tonumber(R.GetExtState(SECTION,'window_h')) or H+TITLE_H,740,1800)
local I,ctx=Host.I,Host.ctx
gfx=Host.g
fonts=Host.faces
U=BLT.Controls.new(gfx,R.time_precise,C);U.font,U.minFontSize=Host.faces[1],7
local density=BLT.Controls.compactScale
local awakeUntil=R.time_precise()+6.5
local function wake() A.dirty=true;awakeUntil=R.time_precise()+6.5 end
local function changed(state,...)
 local different=false
 for i=1,select('#',...) do local v=select(i,...);if state[i]~=v then state[i]=v;different=true end end
 return different
end
function UI.touch_curve() A.settings_revision=(A.settings_revision or 0)+1 end
function UI.commit_edit()
 if U.editor and U.editor.edit then U.editor:close(false) end
 A.edit=nil
end
local Language={text=L.text,code=L.code}
function Language.message(text)
 local shown=L.text(text)
 if L.code=='EN' then
  local first,last,total=shown:match('^(%d+)–(%d+) / (%d+)   スクロールで選択$')
  if first then return string.format('%s–%s / %s   Scroll to browse',first,last,total) end
 end
 return shown
end
menu=BLT.PresetMenu.new(Host,U,{presets=Presets,language=Language,commit=UI.commit_edit,
 layout=Presets.popup,busy=function() return A.job or A.modal end})
shell=BLT.Shell.new(Host,U,R,{
 title='SPECTRAL NORMALIZER',subtitle='SPECTRAL TARGET DRAWING  周波数ごとの目標音量を描画',
 barTitle='S P E C T R A L   N O R M A L I Z E R',section=SECTION,persist=true,
 layout={iconX=W-99,iconY=6,iconScale=.78,footerSize=8},
 language=L.code,languageChanged=function(code) UI.commit_edit();L.code=code;Language.code=code;App.store(SECTION,'ui_language',code,true);wake() end,
 translate=Language.message,store=App.store,headerIcon=BLT.SpectralIcon,iconMode=function() return 'spectral' end,
 stepPreset=function(direction) UI.commit_edit();App.safe(Presets.step,direction) end,
 drawPresets=function(owner) App.safe(function() menu:draw(owner) end) end,presetSize=function() return menu:size() end,dirty=Presets.dirty})
U.editor=BLT.TextInput.new(Host,U,shell.typography)
controls=BLT.EnvelopeWidgets.new(Host,U,density)
canvas=BLT.SpectralCanvas.new(Host,R,C,Core)
Media.state=A;Media.onchange=wake
mediaGraphics.getchar=function() return Host.focused and 6 or 4 end
function UI.release_capture()
 A.drag=nil;A.number_drag=nil;A.pointer_capture=nil;A.pressed=nil
 Host.drag=nil;U.capture=nil;A.dirty=true
end
function UI.open_edit(key)
 local id='field_'..key;local state=U:state(id)
 state.done=state.done or function(raw) A.edit=nil;UI.set_value(key,raw,true,true);wake() end
 A.edit={key=key};U.editor:open(id,UI.value_text(key,UI.value(key)),state.done);U.focus=id
end
function UI.complete()
 U.now=R.time_precise();U:complete('primary',338/density,56/density);wake()
end
local buttonOptions={}
function UI.button(id,text,x,y,w,h,fn,enabled,selected,tone)
 local child=id=='pattern' or id=='direction' or id=='shape_envelope' or id=='period_shape'
 enabled=enabled~=false and not (child and A.tool~='line')
 local opt=buttonOptions[id] or {};buttonOptions[id]=opt
 local choice=id:match('^interp_') or id:match('^tool_') or id:match('^max_') or id:match('^intensity_')
 opt.size=14/density;opt.bold=true
 opt.variant=id=='curve_reset' and 'clear' or nil
 opt.led=choice and (id:match('^max_') and 'top' or 'left') or nil
 if not choice then selected=nil end
 controls:button(id,L.text(text),x,y,w,h,enabled,selected,nil,opt)
 UI.register(id,x,y,w,h,fn,enabled)
end
function UI.panel(x,y,w,h) controls:panel(x,y,w,h) end
function UI.field(key,x,y,w,h,enabled,dim)
 local spec=field_by_key[key];enabled=enabled~=false and not dim
 local unit=spec.unit or '';local drawing=spec.drawing
 local right=unit=='' and 9 or drawing and 24 or unit=='dBFS' and 42 or 32
 controls:number('field_'..key,UI.value_text(key,UI.value(key)),x,y,w,h,enabled,{left=drawing and 64 or 116,right=right,size=15})
 UI.label(spec.label,x+(drawing and 6 or 8),y+(drawing and 5 or 7),drawing and 12 or 11,enabled and C.muted or C.faint,1,false,drawing and 60 or 104)
 UI.label(unit,x+w-right+4,y+(drawing and 9 or 10),10,enabled and C.muted or C.faint,1,false,right-9,'right')
 UI.register('field_'..key,x,y,w,h,UI.noop,enabled)
end
function UI.smoothness_slider()
 controls:slider(Core.smoothness(A.settings.curve)/2,24,155,164,16,not A.job)
 UI.register('smoothness',24,155,164,16,UI.noop,not A.job)
end
function UI.scale_menu()
 if A.job or A.modal then return end
 UI.commit_edit();UI.release_capture();UI.context={opening=true}
end
local function scaleMenu()
 local context=UI.context
 if not context then return end
 if context.opening then I.OpenPopup(ctx,'##spectral_scale');context.opening=false end
 I.PushFont(ctx,Host.font,14)
 if I.BeginPopup(ctx,'##spectral_scale') then
  for index,name in ipairs(Core.SCALES) do
   if I.Selectable(ctx,name,A.settings.scale==index) then
    if not A.job and not A.modal then A.settings.scale=index;A.selection=nil;App.changed('処理設定を変更しました。') end
    UI.context=nil
   end
  end
  I.EndPopup(ctx)
 else UI.context=nil end
 I.PopFont(ctx)
end
local graphState={}
local graphRevision=0
function UI.draw_graph()
 local g,s=UI.graph,A.settings;local curve=UI.display_curve()
 if changed(graphState,A.settings_revision,curve,curve.points,Core.smoothness(curve),s.scale,s.maxfreq,s.threshold,A.source_nyquist) then graphRevision=graphRevision+1 end
 if canvas:begin(g.w,g.h,scale,graphRevision) then
  local savedG,savedScale,savedX,savedY=gfx,scale,ox,oy
  gfx=canvas.g;scale,ox,oy=1,-g.x,-g.y
  local success,err=xpcall(function()
   UI.rect(g.x,g.y,g.w,g.h,C.field)
   if A.source_nyquist then
    UI.rect(g.x,g.y,g.w*Core.to_axis(A.source_nyquist,s.scale,s.maxfreq),g.h,C.accent2,.10)
   end
   for d=-120,0,20 do local yy=g.y-d/120*g.h;UI.line(g.x,yy,g.x+g.w,yy,C.edge,d==0 and .55 or .26) end
   local last,lastf=-math.huge,nil
   for _,f in ipairs(UI.frequency_ticks(s)) do
    local xx=g.x+Core.to_axis(f,s.scale,s.maxfreq)*g.w
    if f~=lastf and f<=s.maxfreq and (f==s.maxfreq or (xx-last>=44 and xx<g.x+g.w-44)) then UI.line(xx,g.y,xx,g.y+g.h,C.edge,.25);last=xx end
    lastf=f
   end
   if A.source_nyquist and A.source_nyquist<s.maxfreq then
    local nx=g.x+g.w*Core.to_axis(A.source_nyquist,s.scale,s.maxfreq);UI.rect(nx,g.y,g.x+g.w-nx,g.h,C.bg,.70)
   end
   local threshold=g.y-s.threshold/120*g.h
   for xx=g.x,g.x+g.w,12 do UI.line(xx,threshold,min(xx+6,g.x+g.w),threshold,C.muted,.65) end
   local lastx,lasty
   for px=0,g.w,2 do
    local f=Core.from_axis(px/g.w,s.scale,s.maxfreq);local yy=g.y-Core.target(curve,f)/120*g.h
    if lastx then UI.thick_line(lastx,lasty,g.x+px,yy,C.accent2,.86,3);UI.line(lastx,lasty,g.x+px,yy,C.focus2,.95) end
    lastx,lasty=g.x+px,yy
   end
   for _,point in ipairs(curve.points) do
    local x,y,visible=UI.point_position(point)
    if visible then UI.disc(x,y,3.5,C.field);UI.disc(x,y,2.4,C.accent2,.95) end
   end
  end,debug.traceback)
  gfx,scale,ox,oy=savedG,savedScale,savedX,savedY
  if not success then error(err,0) end
  canvas:finish()
 end
 canvas:draw(UI.sx(g.x),UI.sy(g.y),g.w*scale,g.h*scale)
 for d=-120,0,20 do UI.label(tostring(d),g.x-40,g.y-d/120*g.h-7,12,C.muted,3,false,32,'right') end
 local last,lastf=-math.huge,nil
 for _,f in ipairs(UI.frequency_ticks(s)) do local xx=g.x+Core.to_axis(f,s.scale,s.maxfreq)*g.w
  if f~=lastf and f<=s.maxfreq and (f==s.maxfreq or (xx-last>=44 and xx<g.x+g.w-44)) then
   UI.label(f>=1000 and string.format('%gk',f/1000) or tostring(f),xx-20,g.y+g.h+8,11,C.muted,3,false,40,'center');last=xx
  end;lastf=f
 end
 if A.source_nyquist and A.source_nyquist<s.maxfreq then
  local nx=g.x+g.w*Core.to_axis(A.source_nyquist,s.scale,s.maxfreq)
  if g.x+g.w-nx>72 then UI.label('対象外',nx+4,g.y+9,11,C.faint,1,false,g.x+g.w-nx-8) end
 end
 UI.draw_tool_overlay();UI.point_highlight()
 if UI.inside(g.x,g.y,g.w,g.h) and not A.modal then
  local frequency,value=UI.pointer_value();UI.line(mx,g.y,mx,g.y+g.h,C.focus2,.18);UI.line(g.x,my,g.x+g.w,my,C.focus2,.10)
  UI.rect(g.x+10,g.y+10,190,28,C.field,.92);UI.rect(g.x+10,g.y+10,190,28,C.edge2,.35,false)
  UI.label(string.format('%.1f Hz   %+.1f dBFS',frequency,value),g.x+20,g.y+16,12,C.text,3,true,170)
 end
end
local previewState,previewSegments={},{}
local previewCount=0
function UI.line_preview()
 if A.tool~='line' or A.job or not A.active or not UI.inside(UI.graph.x,UI.graph.y,UI.graph.w,UI.graph.h) then return end
 local points,ua,ub=UI.line_points();if #points==0 then return end
 local g=UI.graph;local source=A.settings.curve
 if changed(previewState,UI.preview_key,source.kind,source.smoothness,g.x,g.y,g.w,g.h) then
  local curve={points=points,kind=source.kind,smoothness=source.smoothness};local previousX,previousY;previewCount=0
  for px=0,g.w,2 do
   local f=Core.from_axis(px/g.w,A.settings.scale,A.settings.maxfreq)
   if f>=ua and f<=ub then
    local x,y=g.x+px,g.y-Core.target(curve,f)/120*g.h
    if previousX then previewCount=previewCount+1;local seg=previewSegments[previewCount] or {};previewSegments[previewCount]=seg;seg[1],seg[2],seg[3],seg[4]=previousX,previousY,x,y end
    previousX,previousY=x,y
   else previousX=nil end
  end
 end
 for i=1,previewCount do local p=previewSegments[i];UI.line(p[1],p[2],p[3],p[4],C.accent2,.42) end
end
local execution={cancelable=true,autoComplete=false,finishWhenDisabled=true,size=16/density,bold=true,
 captionY=4/density,captionHeight=13/density,captionSize=9/density,labelY=21/density,labelHeight=29/density}
function UI.draw_primary()
 local busy=A.job~=nil;local progress=busy and (A.job.kind=='analysis' and A.job.progress or ((A.job.index-1)+(A.job.progress or 0))/#A.job.plans) or nil
 execution.enabled,execution.busy,execution.progress=true,busy,progress
 execution.caption=busy and 'CLICK TO CANCEL SAFELY' or 'NEW ITEMS / END + 1 SEC'
 local text=busy and (A.job.kind=='analysis' and '解析を中止' or '処理を中止') or '選択アイテムを処理'
 U:execute('primary',L.text(text),638/density,754/density,338/density,56/density,execution)
 UI.register('primary',638,754,338,56,busy and App.cancel_processing or App.begin_processing,true)
end
local analyzeOptions={bold=true,size=12/density,secondaryText='WAVE  >  CURVE',captionSize=8/density,
 captionY=4/density,captionHeight=12/density,labelY=17/density,labelHeight=21/density}
local analysisOptions={size=11/density,bold=false,trailing='menu'}
function UI.analysis_controls()
 local busy=A.job and A.job.kind=='analysis';local enabled=not A.job or busy
 analyzeOptions.enabled=enabled
 U:button('analyze',L.text(busy and '解析を中止' or '波形を解析し変換'),24/density,548/density,164/density,40/density,analyzeOptions)
 UI.register('analyze',24,548,164,40,busy and App.cancel_processing or App.begin_analysis,enabled)
 UI.line(32,590,32,607,C.muted,.28);UI.line(32,607,41,607,C.muted,.28)
 analysisOptions.enabled=not A.job
 U:button('analysis_method',L.text(UI.analysis_names[A.analysis_method]),44/density,596/density,144/density,22/density,analysisOptions)
 UI.register('analysis_method',44,596,144,22,UI.next_analysis_method,not A.job)
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
local function static(now)
 widgetCount=0
 UI.label('補完処理',24,91,13,C.muted,1,true,164)
 local smoothing=Core.smoothness(A.settings.curve)
 for i,q in ipairs(UI.interpolation_options) do local kind=q[1];UI.button('interp_'..kind,q[2],24+(i-1)*84,117,80,30,UI.actions['interp_'..kind],not A.job,smoothing==(kind=='linear' and 0 or 1),C.accent2) end
 UI.smoothness_slider()
 UI.label('操作モード',24,181,13,C.muted,1,true,164)
 for i,q in ipairs(UI.tool_options) do local tool=q[1];UI.button('tool_'..tool,q[2],24,207+(i-1)*38,164,32,UI.actions['tool_'..tool],not A.job,A.tool==tool,C.accent2) end
 local selected=A.tool=='line';UI.panel(24,283,164,252)
 UI.button('tool_line','ライン生成',24,283,164,32,UI.actions.tool_line,not A.job,selected,C.accent2);local child=selected and C.accent2 or C.muted;UI.line(32,315,32,495,child,.30);for _,yy in ipairs(UI.line_child_ticks) do UI.line(32,yy,39,yy,child,.30) end
 UI.button('pattern',UI.pattern_names[A.pattern],40,321,140,28,UI.next_pattern,not A.job,false,child)
 UI.button('direction','方向：'..UI.direction_names[A.direction],40,353,140,28,UI.next_direction,not A.job,false,child)
 UI.field('period_percent',40,385,140,28,not A.job,not selected);UI.button('period_shape',UI.period_names[A.period_shape],40,417,140,28,UI.next_period,not A.job,false,child);UI.field('height',40,449,140,28,not A.job,not selected)
 UI.button('shape_envelope',UI.envelope_names[A.shape_envelope],40,481,140,28,UI.next_shape,not A.job,false,child);UI.label('Alt：位相反転',40,512,11,C.muted,1,false,140)
 UI.analysis_controls()
 UI.label('カーブ操作',24,624,13,C.muted,1,true,164)
 UI.button('curve_undo','戻す',24,648,80,30,UI.actions.undo,not A.job and #A.history>0,false,C.accent2);UI.button('curve_redo','進む',108,648,80,30,UI.actions.redo,not A.job and #A.redo>0,false,C.accent2)
 UI.button('curve_reset','カーブを初期化',24,686,164,32,App.reset_curve,not A.job,false,C.warn)
 UI.panel(24,734,164,50);UI.label('選択素材',34,740,9,C.faint,3,true,144);UI.label(A.source_info,34,755,11,C.text,1,true,144);UI.label(A.source_detail,34,771,9,C.muted,3,true,144)
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

 for i=#widgets,widgetCount+1,-1 do widgets[i]=nil end
end
function UI.input()
 UI.geometry()
 local cap=gfx.mouse_cap or 0;local down=(cap&1)~=0;local pressed=down and (A.last_mouse_cap&1)==0;local released=not down and (A.last_mouse_cap&1)~=0
 local right=(cap&2)~=0;local right_pressed=right and not A.last_right;local wheel=gfx.mouse_wheel or 0
 local moved=gfx.mouse_x~=A.last_mouse_x or gfx.mouse_y~=A.last_mouse_y
 if moved or pressed or released or right_pressed or wheel~=0 then wake() end
 local blocked=shell.popupOpen or UI.context or Host.drag or gfx.mouse_y<TITLE_H
 if blocked and not A.pointer_capture then
  A.last_mouse_cap=cap;A.last_right=right;A.last_mouse_x=gfx.mouse_x;A.last_mouse_y=gfx.mouse_y
  A.pressed=nil;gfx.mouse_wheel=0;return
 end
 if not down and (A.drag or A.number_drag) then
  if A.number_drag then UI.number_input(UI.hit(),false,false,true,0)
  elseif A.drag.mode=='smoothness' then UI.smoothness_input(nil,false,false,true)
  else UI.graph_input(false,false,true,false) end
  A.drag=nil;A.number_drag=nil;A.pointer_capture=nil;A.dirty=true
 end
 if down and (A.drag or A.number_drag) and not moved and not pressed and cap==A.last_mouse_cap and wheel==0 then return end
 local hit=UI.hit()
 if A.modal then UI.modal_input(hit,down,pressed,released)
 elseif not UI.smoothness_input(hit,down,pressed,released) and not UI.number_input(hit,down,pressed,released,wheel) and not UI.graph_input(down,pressed,released,right_pressed) then
  if pressed then if A.edit then UI.commit_edit();hit=UI.hit() end;A.pressed=hit and hit.enabled and hit.id or nil
  elseif released then local id=A.pressed;A.pressed=nil;if id and hit and hit.id==id and hit.enabled then App.safe(hit.fn) end end
 end
 gfx.mouse_wheel=0
 A.last_mouse_cap=cap;A.last_right=right;A.last_mouse_x=gfx.mouse_x;A.last_mouse_y=gfx.mouse_y
end
function UI.draw(now)
 UI.geometry();shell:begin();U.active=Host.focused;U.themeEnabled=shell.theme.enabled
 UI.color(C.bg);gfx.rect(0,0,gfx.w,gfx.h,1)
 U.scale,U.ox,U.oy=scale,ox,oy;shell:header(W)
 local key=gfx.getchar();local wheel=gfx.mouse_wheel or 0
 U:begin(density*scale,ox,oy,0);gfx.mouse_wheel=wheel
 App.safe(UI.input);UI.key(key)
 local released=U.released;U.released=false
 local blocked=U.blocked;U.blocked=blocked or A.modal~=nil
 static(now)
 U.blocked=blocked
 local status=A.status
 if A.job then
  local progress=A.job.kind=='analysis' and A.job.progress or ((A.job.index-1)+(A.job.progress or 0))/#A.job.plans
  status=string.format(L.text('処理中 %d / %d   %.1f%%  — 対象素材の編集は避けてください。'),min(A.job.index,#A.job.plans),#A.job.plans,progress*100)
 elseif now>A.status_until then status='音声アイテムを選択し、目標カーブを描いてください。' end
 if Media.waiting then status=Media.message(SECTION) end
 U.scale,U.ox,U.oy=scale,ox,oy;shell:footer(status,A.warning,W,H,Core.VERSION)
 U.scale,U.ox,U.oy=density*scale,ox,oy;UI.draw_modal()
 U.released=released;U:finish();shell:drawBar();scaleMenu()
end
Host:bindShortcuts()
gfx.getchar=function(query)
 if query then return Host.focused and 6 or 4 end
 local key=Host.key or 0
 if key>=97 and key<=122 then
  if (gfx.mouse_cap&4)~=0 then key=key-96 elseif (gfx.mouse_cap&8)~=0 then key=key-32 end
 end
 return key
end
BLTShortcuts.install(R,gfx,{
 blocked=function() return U.editor.edit~=nil or A.modal or A.job or A.drag or A.number_drag or shell.popupOpen or UI.context end,
 localKey=function(k,cap) return k==27 or k==25 or k==26 or k==6579564 or k==127 or k>=49 and k<=51 or (cap&4)~=0 and (k==89 or k==121 or k==90 or k==122) end})
function App.close()
 if A.closed then return end;A.closed=true
 pcall(UI.commit_edit);pcall(App.cleanup,A.job);A.job=nil;A.pending_job=nil;pcall(App.persist)
 pcall(canvas.close,canvas);pcall(Host.close,Host);pcall(shell.close,shell)
end
R.atexit(App.close)
local inputState,worldState={},{}
function App.loop()
 if A.closed then return end
 local begun=false
 local success,err=xpcall(function()
  local now=R.time_precise();Media.tick();App.poll_selection(now);App.process(now);shell.theme.tick(now)
  if A.status_until>0 and now>=A.status_until and not A.job then A.status_until=0;A.warning=false;wake() end
  if changed(worldState,A.settings_revision,A.status,A.warning,A.settings,A.settings.curve,A.job,A.modal,A.source_info,A.source_detail,A.source_nyquist,L.code,C.bg,Presets.current,shell.icon.dirty,Host.requestReset) then wake() end
  local interactive=U.editor.edit or shell.popupOpen or Host.drag or shell.hoverID or U.capture or A.drag or A.number_drag or UI.context or A.modal
  local animating=U:executeAnimating('primary') or shell.icon:animating(now) or now<(A.flash_until or 0) or A.hover_node and now<A.point_flash+.22
  if not A.job and not A.dirty and now>=awakeUntil and not interactive and not animating and Host:idle(now) then
   U.now=now;shell.icon.lastTime=now;R.defer(App.loop);return
  end
  if Host.idleWake then wake();Host.idleWake=nil end
  if Host.requestReset then Host.width,Host.height=W,H+TITLE_H end
  local visible=Host:begin();begun=true
  if visible then
   if A.active~=Host.focused then
    A.active=Host.focused
    if not A.active then UI.commit_edit();UI.release_capture() end
    wake()
   end
   if changed(inputState,gfx.mouse_x,gfx.mouse_y,gfx.mouse_cap,Host.key,gfx.w,gfx.h,Host.dpi,Host.originX,Host.originY,Host.focused) or gfx.mouse_wheel~=0 or (gfx.mouse_cap&3)~=0 or interactive then wake() end
   A.dirty=false;UI.draw(now);Host.pointerCapture=A.pointer_capture or A.drag or A.number_drag
   if not Host.focused then awakeUntil=min(awakeUntil,now+.5) end
  end
  local keep=Host:finish();begun=false
  if not keep or A.closing then App.close() else R.defer(App.loop) end
 end,debug.traceback)
 if not success then
  if begun then pcall(Host.finish,Host) end
  App.close();R.MB(App.public_error(err),'Spectral Normalizer | エラー',0)
 end
end
Presets.load();App.poll_selection(R.time_precise());App.loop()
