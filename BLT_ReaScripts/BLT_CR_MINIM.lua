-- @description CR MINIM
-- @version 0.6.9
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

BLT.CrMinimIcon=(function()
local M={width=87,height=52,modes={'retrigger'}}
local sin,pi=math.sin,math.pi
local heights={3,9,13,10,5,8,12,7,4}
local function hash(n,salt) return (sin(n*12.9898+salt*78.233)*43758.5453)%1 end
function M.update() end
function M.draw(p)
 local C=p.C
 for i=0,2 do
  local x=i*32
  for k,h in ipairs(heights) do
   local xx=x+(k-1)*2.3
   p:line(xx,30-h,xx,30+h,C.accent,.13,4)
   p:line(xx,30-h,xx,30+h,C.ice,.65,1)
  end
  local d=i==1 and -1 or 1;local cx=x+9
  p:line(cx-d*7,8,cx+d*7,8,C.ice,.82,1.5)
  p:line(cx+d*7,8,cx+d*3,4,C.ice,.82,1.5)
  p:line(cx+d*7,8,cx+d*3,12,C.ice,.82,1.5)
 end
end
function M.emit(s,n,p)
 local a,b,c=hash(n,1),hash(n,2),hash(n,3)
 p.x,p.y,p.life,p.r,p.phase,p.sway=a*83,9+b*34,2.3+c*1.2,.65+b*.65,a*pi*2,2
 p.vx,p.vy=n%2==0 and 8 or -8,0;p.glint=n%8==0
end
function M.sample(s,p,age) return p.x+p.vx*age,p.y+sin(age+p.phase)*p.sway end
return M
end)()

BLT.CrMinimCanvas=(function()
local M={}
local min,max,floor,ceil=math.min,math.max,math.floor,math.ceil
local function byte(v) return floor(max(0,min(1,v))*255+.5) end
function M.new(host,api,C)
 local V={};local G={};V.g=G
 local bitmap,image,width,height,dpi,color,alpha
 local keys={'bg','field','edge','accent2','warn'}
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
 function V:close()
  if image then host:releaseImage(image);image=nil end
  if bitmap then api.JS_LICE_DestroyBitmap(bitmap);bitmap=nil end
 end
 return V
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
 return V
end
return M
end)()
local gfx,Host,U,shell,menu,controls,sourceCanvas,resultCanvas,C
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
 ["波形を選択してください"]="Select a waveform.",
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

for key,value in pairs({['有効']='Enable',['切り出し開始']='Slice offset',['頭フェード']='Fade in',['後フェード']='Fade out',
 ['最初の長さ']='First length',['最後の長さ']='Last length',['長さを変化']='Vary',
 ['最初の間隔']='First interval',['最後の間隔']='Last interval',['最小の無音']='Minimum gap',
 ['最初のピッチ']='First pitch',['最後のピッチ']='Last pitch',['開始ピッチ']='Start pitch',['通過ピッチ']='Pass pitch',['終了ピッチ']='End pitch',
 ['通過位置']='Pass point',['開始音量']='Start gain',['通過音量']='Pass gain',['終了音量']='End gain',
 ['開始トレモロ']='Start tremolo',['終了トレモロ']='End tremolo',['フェード']='Fade',['深さ']='Depth',
 ['切り出し範囲は波形上でも編集できます']='Edit slice ranges directly on the waveform',
 ['ReaImGui 0.10以降と js_ReaScriptAPI が必要です。ReaPackで導入・更新してください。']='ReaImGui 0.10+ and js_ReaScriptAPI are required. Install or update them through ReaPack.'}) do LanguageCatalog.en[key]=value end
local Language=create_language(reaper,"BLT_CR_MINIM",LanguageCatalog)
local R=reaper
-- BLT primary button 1.0.0. Embedded; no runtime file dependency.
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
 return not B.same(host.capture(),Presets.current.values)
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
-- BEGIN BLT PRESET DELETE 1.0.0 (generated from _shared/BLT_PresetDelete.lua)
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
local min,max,abs,floor=math.min,math.max,math.abs,math.floor
local function finite(n) return type(n)=='number' and n==n and abs(n)<math.huge end
local function clamp(n,a,b) return max(a,min(b,n)) end
local Core={VERSION='0.6.5',SECTION='BLT_CR_MINIM'}
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
  j.reader=Core.reader(p,true);j.file=assert(io.open(j.temp,'wb'),'プロジェクトのメディア保存先へ書き込めません。保存先とアクセス権を確認してください。');assert(j.file:write(Core.wav_header(plan.sr,plan.frames)))
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
 R.PreventUIRefresh(-1);R.Undo_EndBlock2(p.project,'BLT CR MINIM: バリエーション生成',4);R.UpdateArrange()
 if not ok then error(tostring(err)..'\n生成WAVは保存済みです。',0) end
 j.committed=true;return item
end
local SECTION=Core.SECTION
local W,H=780,732
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

local scale,ox,oy,mouse_x,mouse_y=1,0,0,-1,-1
local widgets,widgetByID={},{}
local widgetCount=0
local down_last,pressed=false,nil
local awakeUntil=R.time_precise()+6.5
local function wake_visuals() A.content_dirty=true;awakeUntil=R.time_precise()+6.5 end
local function sx(x) return ox+x*scale end
local function sy(y) return oy+y*scale end
local function color(c,a) gfx.set(c[1],c[2],c[3],a or 1) end
local function rect(x,y,w,h,c,a) color(c,a); gfx.rect(sx(x),sy(y),w*scale,h*scale,1) end
local function line(x,y,x2,y2,c,a) color(c,a); gfx.line(sx(x),sy(y),sx(x2),sy(y2),1) end
local function inside(x,y,w,h) return mouse_x>=x and mouse_x<=x+w and mouse_y>=y and mouse_y<=y+h end
local function register(id,x,y,w,h,fn,hint,enabled)
 local widget=widgetByID[id] or {id=id};widgetByID[id]=widget
 widget.x,widget.y,widget.w,widget.h,widget.fn,widget.hint,widget.enabled=x,y,w,h,fn,hint,enabled~=false
 widgetCount=widgetCount+1;widgets[widgetCount]=widget
 return widget
end
local function notice(text,warn) A.status=Core.display_message(text);A.warning=warn or false;UI.dirty() end
function UI.dirty() A.content_dirty=true;wake_visuals() end
function UI.refresh()
 A.settings_revision=(A.settings_revision or 0)+1
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
 if not ok then if BLT.cleanup(Core.abort,A.job) then A.job=nil end;A.busy=false;BLT.cleanup(UI.wave_close);notice(tostring(err):match('^(.-)\nstack traceback:') or tostring(err),true);UI.release_capture();UI.commit_edit() end
 return ok
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
local function blt_output_directory(project)
 local root=R.GetProjectPathEx(project,'')
 assert(type(root)=='string' and root~='' and not root:find('%z'),
  '音声の保存先を取得できません。プロジェクトのメディア保存先を設定してください。')
 assert(root:match('^%a:[/\\]') or root:sub(1,1)=='/' or root:sub(1,2)=='\\\\',
  '音声の保存先が絶対パスではありません。プロジェクトのメディア保存先を確認してください。')
 R.RecursiveCreateDirectory(root,0)
 return root
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
  UI.complete();UI.poll(R.time_precise(),true)
 end
 A.content_dirty=true
end
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
function UI.wave_input()
 local x,y,w,h=30,143,720,42;local down=(gfx.mouse_cap&1)~=0
 if not A.source or A.retrigger_on==false or A.busy or UI.blocked() then A.wave_drag=nil;return false end
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
if not R.ImGui_GetBuiltinPath or not R.JS_LICE_CreateBitmap then
 Language.mb('ReaImGui 0.10以降と js_ReaScriptAPI が必要です。ReaPackで導入・更新してください。','BLT CR MINIM',0);return
end
local ok,value=pcall(BLT.CanvasHost.new,R,'BLT CR MINIM',W,H+26,SECTION)
if not ok then Language.mb(BLT.publicError(value),'BLT CR MINIM',0);return end
Host=value;Host.minWidth,Host.minHeight,Host.persistSize=660,646,true
if R.GetExtState(SECTION,'compact_ui')=='1' then
 Host.width=clamp(tonumber(R.GetExtState(SECTION,'window_w')) or W,660,2200)
 Host.height=clamp(tonumber(R.GetExtState(SECTION,'window_h')) or H+26,646,1800)
end
BLT.store(SECTION,'compact_ui','1',true)
local I,ctx=Host.I,Host.ctx
gfx=Host.g
C={bg={.018,.030,.055},bg2={.030,.090,.180},panel={.040,.068,.110},panel2={.055,.125,.205},
 field={.018,.040,.080},edge={.145,.285,.445},edge2={.360,.650,.900},text={.955,.980,1},
 muted={.690,.780,.875},faint={.390,.505,.635},disabled={.43,.46,.51},accent={.120,.490,.980},
 accent2={.650,.895,1},accent3={.045,.235,.520},ice={.650,.895,1},focus={.225,.610,1},
 focus2={.690,.900,1},ink={.018,.075,.160},hover={.430,.790,1},warn={1,.755,.490},red={1,.23,.30},quiet={.30,.36,.44}}
U=BLT.Controls.new(gfx,R.time_precise,C);U.font,U.minFontSize=Host.faces[1],7
local density=BLT.Controls.compactScale
local function font(size,kind,bold)
 gfx.setfont(1,Host.faces[kind or 1],max(7,floor(size*scale+.5)),bold and 98 or 0)
end
local function label(text,x,y,size,c,kind,w,h,flags,bold,literal)
 font(size,kind,bold);color(c);gfx.x,gfx.y=sx(x),sy(y)
 gfx.drawstr(literal and tostring(text) or Language.message(text),flags or 0,sx(x+(w or 200)),sy(y+(h or size+5)))
end
local function right_label(text,right,y,size,c,kind,bold)
 label(text,right-500,y,size,c,kind,500,size+6,2,bold)
end
function UI.release_capture()
 A.field_drag=nil;A.wave_drag=nil;pressed=nil;U.capture=nil;Host.pointerCapture=nil;UI.dirty()
end
function UI.commit_edit()
 if U.editor and U.editor.edit then U.editor:close(false) end
 A.edit=nil;return true
end
function UI.flash(id) U:flash(id);A.flashUntil=R.time_precise()+.9;UI.dirty() end
function UI.field_adjust(key,raw,flash)
 local spec=Core.specs[key];local value=clamp(raw,spec[1],spec[2])
 if spec[3] then value=floor(value+.5) end
 value=Core.quantize(key,value,true)
 if flash and abs(value-raw)>1e-9 then UI.flash('field_'..key) end
 if A[key]~=value then A[key]=value;UI.refresh() end
end
function UI.begin_edit(key)
 local id='field_'..key;local state=U:state(id)
 state.done=state.done or function(raw)
  A.edit=nil;local n=tonumber(raw)
  if finite(n) then UI.field_adjust(key,n,true) else UI.flash(id) end
  UI.dirty()
 end
 A.edit={key=key};U.editor:open(id,Core.number_text(key,A[key]),state.done);U.focus=id
end
menu=BLT.PresetMenu.new(Host,U,{presets=Presets,language=Language,commit=UI.commit_edit,
 layout={width=292,rowHeight=29,headerHeight=36,visiblePresets=8,hoverDelay=1},busy=function() return A.busy end})
shell=BLT.Shell.new(Host,U,R,{
 title='CR MINIM',subtitle='RETRIGGER MODULATION  リトリガーモジュレーション',barTitle='C R   M I N I M',
 section=SECTION,persist=true,layout={iconX=W-102,iconY=6,iconScale=.78,footerSize=8},
 language=Language.code,languageChanged=function(code) UI.commit_edit();Language.set(code);UI.dirty() end,
 translate=Language.message,store=BLT.store,headerIcon=BLT.CrMinimIcon,iconMode=function() return 'retrigger' end,
 stepPreset=function(direction) UI.commit_edit();Presets.step(direction) end,
 drawPresets=function(owner) menu:draw(owner) end,presetSize=function() return menu:size() end,dirty=Presets.dirty})
U.editor=BLT.TextInput.new(Host,U,shell.typography)
controls=BLT.EnvelopeWidgets.new(Host,U,density)
sourceCanvas=BLT.CrMinimCanvas.new(Host,R,C);resultCanvas=BLT.CrMinimCanvas.new(Host,R,C)
Media.state=A;Media.onchange=wake_visuals
mediaGraphics.getchar=function() return Host.focused and 6 or 4 end
function UI.blocked() return shell.popupOpen or Host.drag~=nil or gfx.mouse_y<26 end
local values={}
BLT.attachPresets({R=R,section=SECTION,defaults=Core.defaults,capture=function()
 for key in pairs(Core.defaults) do values[key]=A[key] end;return values
end,valid=function(v)
 for key,spec in pairs(Core.specs) do
  local n=v[key];if n~=nil and (not finite(n) or n<spec[1] or n>spec[2] or spec[3] and n%1~=0) then return false end
 end;return true
end,apply=function(v) for key,x in pairs(v) do A[key]=x end;A.wave_drag=nil;UI.refresh() end,
 busy=function() return A.busy end,commit=UI.commit_edit,cancelEdit=function() U.editor:close(true);A.edit=nil;UI.release_capture() end,wake=wake_visuals})
local originalDirty=Presets.dirty
function Presets.dirty()
 local state=Presets.dirtyCache
 if not state or state.current~=Presets.current or state.revision~=A.settings_revision then
  state=state or {};Presets.dirtyCache=state
  state.current,state.revision,state.value=Presets.current,A.settings_revision,originalDirty()
 end
 return state.value
end
local projectUndo=create_project_undo(R,{
 language=function() return Language.code end,
 notice=function(text,success) notice(text,not success) end,
 editing=function() return U.editor.edit~=nil or shell.popupOpen end,busy=function() return A.busy end,
 before=UI.release_capture,after=function() UI.poll(R.time_precise(),true) end})
function UI.complete() U.now=R.time_precise();U:complete('execute',272/density,48/density);UI.dirty() end
local toggleOptions={background=false,showState=false,size=11/density,switchScale=28/(44*density)}
local function toggle(key,text,x,y,w,enabled)
 enabled=enabled~=false and not A.busy
 local _,_,hitWidth=U:toggle('switch_'..key,Language.text(text),A[key],x/density,y/density,w/density,28/density,enabled,toggleOptions)
 register('switch_'..key,x,y,hitWidth*density,28,function()
  A[key]=not A[key];if key=='flyby' and A[key] then A.motion=true end;A.wave_drag=nil;UI.refresh()
 end,text,enabled)
end
local choiceOptions={led='top',size=11/density,bold=true}
local function choose(id,text,key,value,x,y,w,enabled)
 enabled=enabled~=false and not A.busy
 controls:button(id,Language.text(text),x,y,w,28,enabled,A[key]==value,nil,choiceOptions)
 register(id,x,y,w,28,function() A[key]=value;UI.refresh() end,text,enabled)
end
local numberOptions={left=6,right=28,size=15}
local unitlessOptions={left=6,right=7,size=15}
local numberText={}
local function field(key,title,unit,x,y,w,enabled)
 enabled=enabled~=false and not A.busy
 label(title,x,y,11,enabled and C.muted or C.faint,1,w,15)
 local id='field_'..key;local cached=numberText[key]
 if not cached or cached.value~=A[key] then
  cached=cached or {};numberText[key]=cached;cached.value,cached.text=A[key],Core.number_text(key,A[key])
 end
 controls:number(id,cached.text,x,y+17,w,29,enabled,unit=='' and unitlessOptions or numberOptions)
 if unit~='' then label(unit,x+w-25,y+24,9,enabled and C.muted or C.faint,3,21,15,2) end
 local spec=Core.specs[key];local hint='クリック入力 / 上下ドラッグ / ホイール'
 if Core.fine_adjustment(key,spec) then hint=hint..' / Shiftで微調整' end
 local widget=register(id,x,y+17,w,29,function() UI.begin_edit(key) end,hint,enabled);widget.key=key
end
local sourceState,resultState={},{}
local sourceRevision,resultRevision=0,0
local function changed(state,...)
 local different=false
 for i=1,select('#',...) do local value=select(i,...);if state[i]~=value then state[i]=value;different=true end end
 return different
end
local function cached(canvas,x,y,w,h,revision,draw)
 if canvas:begin(w,h,scale,revision) then
  local savedG,savedScale,savedX,savedY=gfx,scale,ox,oy
  gfx=canvas.g;scale,ox,oy=1,-x,-y
  local success,err=xpcall(draw,debug.traceback)
  gfx,scale,ox,oy=savedG,savedScale,savedX,savedY
  if not success then error(err,0) end
  canvas:finish()
 end
 canvas:draw(sx(x),sy(y),w*scale,h*scale)
end
local function source_plot()
 local x,y,w,h=30,143,720,42
 local p=A.source;local duration=p and p.duration or 1
 local vs,ve=A.view_start or 0,A.view_end or duration;local span=max(.000001,ve-vs)
 rect(x,y,w,h,C.field)
 if not p then return end
 line(x,y+h/2,x+w,y+h/2,C.edge,.3)
 for i=0,w-1 do
  local a,b=UI.wave_bin(vs+(i+.5)/w*span,true)
  line(x+i,y+h/2-clamp(b,-1,1)*(h/2-3),x+i,y+h/2-clamp(a,-1,1)*(h/2-3),C.accent2,.52)
 end
 local target=A.vary_length and A.wave_target=='slice_end' and 'slice_end' or 'slice'
 for _,key in ipairs({'slice_end','slice'}) do
  if A.retrigger_on~=false and (key=='slice' or A.vary_length) then
   local a=x+(A.offset/1000-vs)/span*w;local b=x+(min(duration,(A.offset+A[key])/1000)-vs)/span*w
   local tone=key=='slice' and C.accent2 or C.warn;local left,right=clamp(a,x,x+w),clamp(b,x,x+w)
   if right>left then rect(left,y,right-left,h,tone,key==target and .12 or .04) end
   if b>=x and b<=x+w then line(b,y,b,y+h,tone,.9);rect(b-4,y+(key=='slice' and 0 or h-10),8,10,tone,.9) end
   if a>=x and a<=x+w then line(a,y,a,y+h,tone,.8);rect(a-4,y+(key=='slice' and 0 or h-10),8,10,tone,.9) end
  end
 end
end
local waveButtonOptions={size=10/density,bold=false}
local function wave_draw()
 local p=A.source;local duration=p and p.duration or 1
 controls:panel(18,96,744,114)
 label(p and p.name or '',30,105,13,C.accent2,1,550,19,0,true,p~=nil)
 label(p and string.format('%.3f s / %d Hz / %d ch',p.duration,p.wav.sr,p.wav.channels) or 'SOURCE',30,125,9,C.faint,3,550,14)
 controls:button('wave_full',Language.text('全体'),598,104,54,24,p~=nil and not A.busy,nil,nil,waveButtonOptions)
 register('wave_full',598,104,54,24,function() A.view_start=0;A.view_end=duration;UI.dirty() end,'波形全体へ戻す',p~=nil and not A.busy)
 controls:button('wave_zoom',Language.text('範囲拡大'),660,104,90,24,p~=nil and not A.busy,nil,nil,waveButtonOptions)
 register('wave_zoom',660,104,90,24,function()
  local target=A.vary_length and A.wave_target=='slice_end' and 'slice_end' or 'slice'
  local a,n=A.offset/1000,A[target]/1000;A.view_start=max(0,a-n*.15);A.view_end=min(duration,a+n*1.15);UI.dirty()
 end,'切り出し範囲を拡大',p~=nil and not A.busy)
 if changed(sourceState,A.wave,A.wave_job and A.wave_job.index,A.zoom,A.zoom_job and A.zoom_job.index,
  A.source~=nil,A.view_start,A.view_end,A.offset,A.slice,A.slice_end,A.vary_length,A.retrigger_on,A.wave_target) then sourceRevision=sourceRevision+1 end
 if A.source and A.retrigger_on~=false and not A.busy then gfx.wheelRegion(ox+30*scale,oy+143*scale,720*scale,42*scale)end
 cached(sourceCanvas,30,143,720,42,sourceRevision,source_plot)
 if not p then label('波形を選択してください',30,143,13,C.muted,1,720,42,5) end
 label(string.format('%.4f s',A.view_start or 0),30,190,9,C.faint,3,100,14)
 right_label(string.format('%.4f s',A.view_end or duration),750,190,9,C.faint,3)
end
local function result_plot()
 local x,y,w,h=30,252,720,28;local middle=y+h/2;local plan=A.plan
 rect(x,y,w,h,C.field);line(x,middle,x+w,middle,C.edge,.35)
 if not plan then return end
 local event,lastx,lasty,lastEvent=1
 for i=0,w-1 do
  local t=(i+.5)/w*plan.duration
  while plan.events[event] and t>=plan.events[event].start+plan.events[event].len do event=event+1 end
  local e=plan.events[event]
  if e and t>=e.start then
   local localtime=t-e.start;local position,rate=Core.source_position(e,localtime,plan.sr)
   local lo,hi=UI.wave_bin(position);local l,r=Core.gains(e,localtime,A);local gain=max(l,r)
   line(x+i,middle-clamp(hi*gain,-1,1)*h*.46,x+i,middle-clamp(lo*gain,-1,1)*h*.46,C.accent2,.65)
   local py=middle-clamp(12*math.log(rate)/math.log(2)/24,-1,1)*h*.46
   if lastEvent==event then line(lastx,lasty,x+i,py,C.warn,.8) end
   lastx,lasty,lastEvent=x+i,py,event
  else lastEvent=nil end
 end
end
local function result_draw()
 controls:panel(18,220,744,82)
 label('RESULT / 結果予想',30,230,12,C.text,1,180,18,0,true)
 label('青：振幅  橙：ピッチ（速度連動）',238,232,10,C.muted,1,330,16)
 local plan=A.plan
 right_label(plan and string.format('%.3f s',plan.duration) or '',750,230,11,C.accent2,3)
 if changed(resultState,plan,A.wave,A.wave_job and A.wave_job.index) then resultRevision=resultRevision+1 end
 cached(resultCanvas,30,252,720,28,resultRevision,result_plot)
 label('0 s',30,285,9,C.faint,3,60,14)
 if plan then right_label(string.format('%.3f s',plan.duration),750,285,9,C.faint,3) end
end
local execution={cancelable=true,autoComplete=false,finishWhenDisabled=true,captionY=3/density,
 captionHeight=12/density,captionSize=8/density,labelY=17/density,labelHeight=27/density,size=16/density,bold=true}
local chaosOptions={size=14/density,bold=true}
local directions={'順転','逆転','順逆','FFRR'}
local panelOptions={panel=true,glow=false}
local function engine_panel(x,enabled)
 panelOptions.disabled=not enabled
 U:frame(x/density,312/density,364/density,336/density,panelOptions)
end
local function dim_panels()
 if not A.retrigger_on then rect(24,346,352,298,C.bg,.50) end
 if not A.tail_on then rect(404,346,352,298,C.bg,.50) end
end
local function static()
 widgetCount=0
 wave_draw();result_draw()
 engine_panel(18,A.retrigger_on);engine_panel(398,A.tail_on)
 label('REPEAT ENGINE',30,322,12,A.retrigger_on and C.accent2 or C.disabled,2,190,20,0,true)
 toggle('retrigger_on','有効',282,318,88,true)
 local en=A.retrigger_on
 field('offset','切り出し開始','ms',30,350,104,en)
 field('slice_fade_in','頭フェード','ms',146,350,104,en);field('slice_fade_out','後フェード','ms',262,350,108,en)
 field('slice','最初の長さ','ms',30,404,104,en);field('slice_end','最後の長さ','ms',146,404,104,en and A.vary_length)
 toggle('vary_length','長さを変化',262,420,108,en)
 field('count','リピート回数','',30,458,104,en)
 label('再生方向',146,458,11,en and C.muted or C.faint,1,224,15)
 for i,text in ipairs(directions) do choose('direction'..i,text,'pattern',i,146+(i-1)*57,475,53,en) end
 field('interval0','最初の間隔','ms',30,512,104,en);field('interval1','最後の間隔','ms',146,512,104,en);field('gap','最小の無音','ms',262,512,108,en)
 field('pitch0','最初のピッチ','st',30,566,104,en);field('pitch1','最後のピッチ','st',146,566,104,en);field('curve','変化カーブ','',262,566,108,en)
 label('切り出し範囲は波形上でも編集できます',30,624,10,C.faint,1,340,16)
 label('TAIL & MOTION',410,322,12,A.tail_on and C.accent2 or C.disabled,2,190,20,0,true)
 toggle('tail_on','有効',662,318,88,true)
 en=A.tail_on
 choose('tail1','素材全体','tail',1,410,346,164,en);choose('tail2','切り出し以降','tail',2,586,346,164,en and A.retrigger_on)
 toggle('motion','最後の音にモーションを適用',410,378,340,en)
 local motionEnabled=en and A.motion
 field('bend0','開始ピッチ','st',410,406,104,motionEnabled);field('bend_mid','通過ピッチ','st',526,406,104,motionEnabled and A.flyby);field('bend1','終了ピッチ','st',642,406,108,motionEnabled)
 toggle('flyby','接近 → 通過 → 遠ざかり',410,474,218,en)
 field('pass','通過位置','%',642,454,108,motionEnabled and A.flyby)
 field('gain0','開始音量','dB',410,502,104,motionEnabled);field('gain_mid','通過音量','dB',526,502,104,motionEnabled and A.flyby);field('gain1','終了音量','dB',642,502,108,motionEnabled)
 field('pan0','開始パン','',410,550,104,motionEnabled);field('pan1','終了パン','',526,550,104,motionEnabled);field('fade','フェード','ms',642,550,108,en)
 field('trem0','開始トレモロ','Hz',410,598,104,motionEnabled);field('trem1','終了トレモロ','Hz',526,598,104,motionEnabled);field('depth','深さ','%',642,598,108,motionEnabled)
 chaosOptions.enabled=not A.busy
 U:chaos('chaos','CHAOS',18/density,672/density,148/density,38/density,chaosOptions)
 register('chaos',18,672,148,38,UI.chaos,'パラメータをランダムに変化させます',not A.busy)
 local ready=A.plan~=nil and not A.busy
 execution.enabled,execution.busy,execution.progress=ready or A.busy,A.busy,A.busy and A.progress or nil
 execution.caption=A.busy and 'GENERATING / CANCEL' or 'EXECUTE'
 U:execute('execute',Language.text(A.busy and '生成中止' or '生成実行'),254/density,666/density,272/density,48/density,execution)
 register('execute',254,666,272,48,UI.execute,A.busy and 'もう一度押すと生成を中止します' or '波形ピークを作成後、同じトラックの右側の空きへ1秒空けて配置します',ready or A.busy)
 label('NEW ITEM / END + 1 SEC',546,681,9,C.faint,3,216,20,2)
 for i=#widgets,widgetCount+1,-1 do widgets[i]=nil end
end
function UI.interact()
 local down=(gfx.mouse_cap&1)~=0
 if UI.blocked() then down_last=down;pressed=nil;gfx.mouse_wheel=0;return end
 if UI.wave_input() then return end
 local hit
 for i=#widgets,1,-1 do local w=widgets[i];if w.enabled and inside(w.x,w.y,w.w,w.h) then hit=w;break end end
 if U.editor.edit and hit and hit.id==U.editor.edit.id and not A.field_drag and gfx.mouse_wheel==0 then down_last=down;return end
 if gfx.mouse_wheel~=0 and hit and hit.key then
  UI.commit_edit();local key=hit.key;local spec=Core.specs[key]
  local fine=(gfx.mouse_cap&8)~=0 and Core.fine_adjustment(key,spec)
  UI.field_adjust(key,A[key]+(gfx.mouse_wheel>0 and 1 or -1)*spec[4]*(fine and .1 or 1),true)
 end
 if down and not down_last then
  UI.commit_edit();pressed=hit and hit.id
  if hit and hit.key then A.field_drag={key=hit.key,y=mouse_y,value=A[hit.key],moved=false} end
 elseif down and A.field_drag then
  local d=A.field_drag
  if abs(mouse_y-d.y)>=3 then
   d.moved=true;local spec=Core.specs[d.key];local fine=(gfx.mouse_cap&8)~=0 and Core.fine_adjustment(d.key,spec)
   local raw=d.value+floor((d.y-mouse_y)/(fine and 8 or 3)+.5)*spec[4]*(fine and .1 or 1)
   if d.last~=raw then UI.field_adjust(d.key,raw,not d.clipped);d.last=raw;d.clipped=raw<spec[1] or raw>spec[2] end
  end
 elseif not down and down_last then
  local moved=A.field_drag and A.field_drag.moved;A.field_drag=nil
  if not moved and hit and hit.id==pressed then UI.safe(hit.fn) end
  pressed=nil
 end
 down_last=down;gfx.mouse_wheel=0
end
local function geometry()
 scale=min(gfx.w/W,max(1,gfx.h-26)/H);ox,oy=(gfx.w-W*scale)/2,26+(gfx.h-26-H*scale)/2-22*scale
 mouse_x,mouse_y=(gfx.mouse_x-ox)/scale,(gfx.mouse_y-oy)/scale
end
local function draw()
 geometry();shell:begin();U.active=Host.focused;U.themeEnabled=shell.theme.enabled
 color(C.bg);gfx.rect(0,0,gfx.w,gfx.h,1)
 U.scale,U.ox,U.oy=scale,ox,oy+22*scale;shell:header(W)
 local key=gfx.getchar();local wheel=gfx.mouse_wheel or 0
 U:begin(density*scale,ox,oy,0);gfx.mouse_wheel=wheel
 UI.interact()
 if not U.editor.edit and not shell.popupOpen and not projectUndo(key,gfx.mouse_cap) and key==27 then
  if A.busy then UI.cancel() else A.closing=true end
 end
 local released=U.released;U.released=false;static();U.released=released;U:finish()
 dim_panels()
 local message=A.source_problem or A.problem or A.status;local bad=A.source_problem or A.problem or A.warning
 if Media.waiting then message=Media.message(SECTION) elseif BLT.notice then message=BLT.notice;bad=BLT.noticeBad end
 U.scale,U.ox,U.oy=scale,ox,oy+22*scale;shell:footer(Core.display_message(message),bad,W,H,Core.VERSION,A.busy and A.progress or nil)
 U.scale,U.ox,U.oy=density*scale,ox,oy;shell:drawBar()
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
BLTShortcuts.install(R,gfx,{blocked=function() return U.editor.edit~=nil or shell.popupOpen or A.busy end,
 beforeGlobal=UI.commit_edit,localKey=function(k,cap) return k==27 or (cap&24)==0 and (k==26 or (cap&4)~=0 and (k==90 or k==122)) end})
local finalized=false
local function close()
 if finalized then return end;finalized=true;A.closed=true
 BLT.cleanup(UI.commit_edit);BLT.cleanup(Core.abort,A.job);BLT.cleanup(UI.wave_close)
 BLT.cleanup(sourceCanvas.close,sourceCanvas);BLT.cleanup(resultCanvas.close,resultCanvas)
 BLT.cleanup(Host.close,Host);BLT.cleanup(shell.close,shell)
end
R.atexit(close)
local inputState,worldState={},{}
local tipID,tipSince
local function tooltip(now)
 local tip
 if Host.focused and not shell.popupOpen and (gfx.mouse_cap&3)==0 then
  for i=#widgets,1,-1 do local w=widgets[i];if inside(w.x,w.y,w.w,w.h) then tip=w.hint;break end end
 end
 if not tip or tip=='' then tipID=nil;return end
 if tip~=tipID then tipID,tipSince=tip,now
 elseif now-tipSince>.7 then I.PushFont(ctx,Host.font,12);I.SetTooltip(ctx,Language.message(tip));I.PopFont(ctx) end
end
local function loop()
 if finalized then return end
 local begun=false
 local success,err=xpcall(function()
  local now=R.time_precise();Media.tick();UI.safe(function() UI.poll(now);if not A.busy then UI.wave_step() end end)
  if A.job then UI.safe(UI.step) end
  shell.theme.tick(now)
  if BLT.noticeUntil and now>=BLT.noticeUntil then BLT.notice,BLT.noticeUntil=nil,nil;UI.dirty() end
  if changed(worldState,A.plan,A.source,A.content_dirty,A.busy,Media.waiting,Language.code,Presets.current,Host.requestReset,shell.icon.dirty) then wake_visuals() end
  local interactive=U.editor.edit or shell.popupOpen or Host.drag or shell.hoverID or U.capture or A.field_drag or A.wave_drag
  local animating=U:executeAnimating('execute') or shell.icon:animating(now) or now<(A.flashUntil or 0)
  if not A.busy and not A.wave_job and not A.zoom_job and now>=awakeUntil and not interactive and not animating and Host:idle(now) then
   U.now=now;shell.icon.lastTime=now;R.defer(loop);return
  end
  if Host.idleWake then wake_visuals();Host.idleWake=nil end
  if Host.requestReset then Host.width,Host.height=W,H+26 end
  local visible=Host:begin();begun=true
  if visible then
   A.active=Host.focused
   if changed(inputState,gfx.mouse_x,gfx.mouse_y,gfx.mouse_cap,Host.key,gfx.w,gfx.h,Host.dpi,Host.originX,Host.originY,Host.focused) or
    gfx.mouse_wheel~=0 or (gfx.mouse_cap&1)~=0 or interactive then wake_visuals() end
   if not Host.focused and (A.field_drag or A.wave_drag) then UI.release_capture() end
   draw();tooltip(now);Host.pointerCapture=A.field_drag or A.wave_drag;A.content_dirty=false
   if not Host.focused then awakeUntil=min(awakeUntil,now+.5) end
  end
  local keep=Host:finish();begun=false
  if not keep or A.closing then close() else R.defer(loop) end
 end,debug.traceback)
 if not success then
  if begun then pcall(Host.finish,Host) end
  close();Language.mb(BLT.publicError(err),'BLT CR MINIM | エラー',0)
 end
end
UI.safe(function() UI.poll(R.time_precise(),true) end)
loop()
