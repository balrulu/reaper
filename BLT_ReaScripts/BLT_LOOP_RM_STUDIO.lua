-- @description LOOP RM STUDIO
-- @version 0.6.15
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

local BLT={}

BLT.Controls=(function()
local M={}
M.compactScale=458/904
M.palette={bg={.018,.030,.055},panel={.040,.068,.110},field={.018,.040,.080},
 edge={.145,.285,.445},ice={.650,.895,1},accent={.120,.490,.980},
 text={.955,.980,1},muted={.690,.780,.875},disabled={.43,.46,.51},red={1,.18,.26}}
function M.number(raw,previous,lo,hi,step)
 local n=tonumber(raw)
 if not n or n~=n or math.abs(n)==math.huge then return previous,true end
 local v=math.max(lo,math.min(hi,n))
 if step and step>0 then v=math.max(lo,math.min(hi,lo+math.floor((v-lo)/step+.5)*step)) end
 return v,math.abs(v-n)>1e-9
end
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
 function U:gold(id,label,value,x,y,w,h,opt)
  opt=opt or empty;local enabled=opt.enabled~=false
  local click,_,held,s=self:interaction(id,x,y,w,h,enabled)
  if click then value=not value end
  if enabled and value and (s.goldValue==false or click) then s.sparkAt=self.now end
  s.goldValue=value
  if not enabled or not value then s.sparkAt=nil end
  held=held or opt.preview=='pressed'
  local hot=(opt.preview=='hover' or held) and 1 or s.hover
  local target=value and 1 or 0
  s.active=approach(s.active or target,target,self.hoverStep,.0001)
  local C=self.C;local P=self.themeEnabled and self.themeTones and self.themeTones.gold or gold
  local frame=s.frame or {};s.frame=frame
  frame.disabled,frame.hot,frame.selected,frame.pressed=not enabled,max(hot,s.active*.40),value,held
  frame.focus,frame.palette,frame.lightX=self.focus==id and enabled,P,s.lightX
  self:frame(x,y,w,h,frame)
  self:led(x+4,y+(opt.ledY or 0),w-4,opt.ledHeight or h,'left',value,enabled,P,opt.ledScale)
  self:electricFlash(s,x,y,w,h,enabled,P)
  local color=not enabled and C.disabled or P.text
  if enabled and not value then color=blend(C.muted,P.text,fade(hot)) end
  local shift=held and 1 or 0
  if opt.showState==false then
   self:text(label,x+32,y+shift+(opt.labelY or 0),w-48,opt.labelHeight or h,opt.size or min(14,h*.27),color,true,opt.bold,opt.face)
  else
   self:text(label,x+32,y+shift+3,w-48,h*.52,opt.size or min(14,h*.27),color,nil,opt.bold,opt.face)
   self:text(value and (opt.onText or 'ON') or (opt.offText or 'OFF'),x+33,y+shift+h*.52,w-49,h*.36,opt.stateSize or min(10,h*.21),color)
  end
  return value,click
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
 function U:assign(id,raw,value,opt)
  local v,corrected
  if opt.normalize then v,corrected=opt.normalize(raw);if v==nil then v,corrected=value,true end
  else v,corrected=M.number(raw,value,opt.min or 0,opt.max or 100,opt.step or 1) end
  if corrected then self:flash(id) end
  return v
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
 function U:field(id,value,x,y,w,h,opt)
  opt=opt or empty;local enabled=opt.enabled~=false;local number=opt.kind=='number'
  local dragDistance=opt.dragDistance or 3
  local clicked,hot,held,s=self:interaction(id,x,y,w,h,enabled)
  if hot and self.pressed then s.startY=self.my;s.startValue=value;s.dragged=false;s.clipped=false;s.dragStep=nil end
  local lo,hi=opt.min or 0,opt.max or 100
  if number and held and math.abs(self.my-(s.startY or self.my))>=dragDistance-1e-9 then
   s.dragged=true
   local step=(opt.step or 1)*((g.mouse_cap&8)~=0 and (opt.fineStep or .1) or 1)
   if opt.rebaseDrag and s.dragStep and s.dragStep~=step then s.startY,s.startValue=self.my,value end
   s.dragStep=step
   local q=(s.startY-self.my)/dragDistance
   local raw=s.startValue+(q<0 and -floor(-q+.5) or floor(q+.5))*step
   local v,clipped
   if opt.normalize then v,clipped=opt.normalize(raw) else v,clipped=M.number(raw,value,lo,hi,step) end
   v=v or value;local boundary=v==lo or v==hi
   if (clipped or (boundary and v~=value)) and not s.clipped then self:flash(id) end
   s.clipped=clipped or boundary;value=v
  end
  if s.pending~=nil then value=number and self:assign(id,s.pending,value,opt) or s.pending;s.pending=nil end
  local bounds=s.bounds or {hit={}};s.bounds=bounds
  bounds.x,bounds.y=self.ox+(x+12)*self.scale,self.oy+(y+3)*self.scale
  bounds.w,bounds.h,bounds.size=(w-24)*self.scale,(h-6)*self.scale,max(self.minFontSize or 8,(opt.size or 15)*self.scale)
  bounds.number,bounds.face,bounds.bold,bounds.align,bounds.calibrate=number,opt.face,opt.bold,opt.align,opt.calibrate
  bounds.opticalCenter=opt.opticalCenter
  local suffixX,suffixWidth,suffixSize
  if opt.prefix or opt.suffix then
   local inset=opt.inset or 16;local suffix=opt.suffix or ''
   suffixSize=opt.suffixSize or 15
   g.setfont(1,opt.face or self.font,max(self.minFontSize or 8,floor(suffixSize*self.scale+.5)),opt.bold and 98 or 0)
   suffixWidth=g.measurestr(suffix)/self.scale
   local right=x+w-inset-suffixWidth
   suffixX=right
   bounds.x=self.ox+(x+(opt.valueInset or 115))*self.scale
   bounds.w=max(1,(right-(opt.gap or 8))*self.scale+self.ox-bounds.x)
   bounds.y,bounds.h=self.oy+y*self.scale,h*self.scale
   local requested=max(self.minFontSize or 8,floor((opt.size or 15)*self.scale+.5))
   bounds.size=requested
   if opt.autoSize~=false then
    local text=opt.format and opt.format(value) or tostring(value)
    local minimum=max(self.minFontSize or 8,(opt.minSize or 13)*self.scale)
    local fit=s.valueFit or {};s.valueFit=fit
    if fit.text~=text or fit.width~=bounds.w or fit.requested~=requested or fit.minimum~=minimum or
     fit.face~=opt.face or fit.bold~=opt.bold or fit.dpi~=g.ext_retina then
     local size=requested
     g.setfont(1,opt.face or self.font,size,opt.bold and 98 or 0)
     while g.measurestr(text)>bounds.w-2 and size>minimum do
      size=size-1;g.setfont(1,opt.face or self.font,size,opt.bold and 98 or 0)
     end
     fit.text,fit.width,fit.requested,fit.minimum=text,bounds.w,requested,minimum
     fit.face,fit.bold,fit.dpi,fit.size=opt.face,opt.bold,g.ext_retina,size
    end
    bounds.size=fit.size
   end
  end
  local hit=bounds.hit;hit.x,hit.y,hit.w,hit.h=self.ox+x*self.scale,self.oy+y*self.scale,w*self.scale,h*self.scale
  local opening=enabled and ((clicked and self.released and not s.dragged) or (self.focus==id and self.key==13))
  if opening then
   if self.editor then
    s.done=s.done or function(text) s.pending=text end
    self.editor:open(id,opt.format and opt.format(value) or value,s.done)
   else self.inputError='日本語入力にはReaImGui 0.10以降の入力アダプターが必要です。' end
   self.key=0
  end
  if number and hot and self.wheel~=0 then
   local step=(opt.step or 1)*((g.mouse_cap&8)~=0 and opt.fineStep or 1)
   local raw=value+(self.wheel/120)*step;local v,corrected
   if opt.normalize then v,corrected=opt.normalize(raw) else v,corrected=M.number(raw,value,lo,hi,opt.step or 1) end
   v=v or value
   local boundary=v==lo or v==hi
   local repeated=boundary and s.wheelLimit==v and s.wheelAt and self.now-s.wheelAt<.20
   if (corrected or (boundary and v~=value)) and not repeated then self:flash(id) end
   s.wheelLimit,s.wheelAt=boundary and v or nil,self.now;value=v
  end
  local flash=self:fieldFrame(id,x,y,w,h,enabled,self.focus==id)
  if opt.suffix then self:text(opt.suffix,suffixX,y,suffixWidth+2,h,suffixSize,enabled and self.C.muted or self.C.disabled,false,opt.bold,opt.face) end
  if opt.prefix then self:text(opt.prefix,x+(opt.prefixInset or opt.inset or 16),y,opt.prefixWidth or 100,h,opt.prefixSize or 8,enabled and self.C.muted or self.C.disabled,false,opt.bold,opt.face) end
  if self.editor and self.editor.queue then
   self.editor:queue(id,opt.format and opt.format(value) or value,bounds,enabled)
  else
   local suffix=opt.unit and (' '..opt.unit) or ''
   self:text(tostring(value)..suffix,x+12,y,w-24,h,opt.size or 15,enabled and self.C.text or self.C.disabled)
  end
  return value,flash
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

BLT.LoopStudioIcon=(function()
local M={width=94,height=70,modes={'loop'}}
local sin,cos,abs,pi=math.sin,math.cos,math.abs,math.pi
local function hash(n,salt) return (sin(n*12.9898+salt*78.233)*43758.5453)%1 end
function M.update() end
function M.draw(p,s,mode,time)
 local C=p.C;local k=.7
 for i=1,7 do
  local phase=time*(.15+(i%3)*.035)+i*1.41
  local x,y=46.2+sin(phase*1.22)*19,35+cos(phase*.87)*8;local r=9+(i%4)*3
  p:disc(x,y,r+7,C.accent,.006);p:disc(x,y,r,C.accent3,.010)
 end
 p:rect(.7,2.1,91,65.8,C.field,.5)
 p:line(7,2.1,91.7,2.1,C.edge,.26);p:line(.7,8.4,.7,67.9,C.edge,.26)
 p:line(.7,8.4,7,2.1,C.edge,.26);p:line(.7,67.9,85.4,67.9,C.edge,.26)
 p:line(85.4,67.9,91.7,61.6,C.edge,.26);p:line(91.7,2.1,91.7,61.6,C.edge,.26)
 for i=0,38 do
  local x=(12+i*108/38)*k;local amp=((sin(i*.78)*sin(i*.23+1)*.5+.5)*12+2)*k
  p:line(x,35-amp,x,35+amp,C.ice,.18+abs(sin(i*.45))*.16)
 end
 p:line(15.4,14,77,14,C.focus,.7);p:line(15.4,14,15.4,19.6,C.focus,.6)
 p:line(77,14,77,28.7,C.focus,.6)
 p:line(21,14,24.5,11.2,C.ice,.7);p:line(21,14,24.5,16.8,C.ice,.7)
 p:line(13.3,56.7,72.1,56.7,C.edge2,.6)
 p:line(13.3,52.5,13.3,58.8,C.edge2,.6);p:line(72.1,52.5,72.1,58.8,C.edge2,.6)
end
function M.emit(s,n,p)
 local a,b,c,d=hash(n,31),hash(n,32),hash(n,33),hash(n,34)
 local lane=n%3;p.direction=lane==0 and -1 or 1
 p.x=(p.direction<0 and 115-a*12 or 17+a*12)*.7;p.y=(lane==0 and 20 or lane==1 and 81 or 50)*.7
 p.speed,p.drift=8+d*8,(c-.5)*7
 p.phase,p.life,p.r,p.glint=c*pi*2,1.8+b*1.2,.45+a*.55,n%8==0
end
function M.sample(s,p,age)
 return p.x+p.direction*p.speed*age,p.y+p.drift*age+sin(age*1.4+p.phase)*2.3
end
return M
end)()

BLT.LoopStudioWave=(function()
local M={}
local min,max,floor,ceil=math.min,math.max,math.floor,math.ceil
local function byte(v) return floor(max(0,min(1,v))*255+.5) end
function M.new(host,api,text,language,C)
 local V={signature={}};local G=setmetatable({}, {__index=host.g});V.canvas=G
 local bitmap,image,width,height,dpi,left,top
 local color,alpha=0xffffffff,1
 local command={}
 local keys={'field','accent','accent2','quiet','warn','edge','edge2','muted','faint','focus','focus2','bg','hover','text'}
 local index=0
 local function check(value)
  index=index+1;if V.signature[index]~=value then V.signature[index]=value;V.dirty=true end
 end
 function G.set(r,g,b,a) color=0xff000000|(byte(r)<<16)|(byte(g)<<8)|byte(b);alpha=a or 1 end
 function G.rect(x,y,w,h,filled)
  x,y=(x-left)*dpi,(y-top)*dpi;w,h=w*dpi,h*dpi
  if filled==0 then
   api.JS_LICE_Line(bitmap,x,y,x+w,y,color,alpha,'COPY',true)
   api.JS_LICE_Line(bitmap,x+w,y,x+w,y+h,color,alpha,'COPY',true)
   api.JS_LICE_Line(bitmap,x+w,y+h,x,y+h,color,alpha,'COPY',true)
   api.JS_LICE_Line(bitmap,x,y+h,x,y,color,alpha,'COPY',true)
  else api.JS_LICE_FillRect(bitmap,floor(x+.5),floor(y+.5),max(1,floor(w+.5)),max(1,floor(h+.5)),color,alpha,'COPY') end
 end
 function G.line(x,y,xx,yy,aa)
  api.JS_LICE_Line(bitmap,(x-left)*dpi,(y-top)*dpi,(xx-left)*dpi,(yy-top)*dpi,color,alpha,'COPY',aa~=0)
 end
 G.setfont=function(...) return text:setfont(...) end
 G.measurestr=function(value) return text:measurestr(value) end
 local function fit(value,available)
  if text:measurestr(value)<=available then return value end
  local lo,hi=0,utf8.len(value) or 0
  while lo<hi do
   local mid=floor((lo+hi+1)/2);local at=utf8.offset(value,mid+1) or #value+1
   if text:measurestr(value:sub(1,at-1)..'…')<=available then lo=mid else hi=mid-1 end
  end
  return text:measurestr('…')<=available and value:sub(1,(utf8.offset(value,lo+1) or #value+1)-1)..'…' or ''
 end
 function G.drawstr(value,flags,right,bottom)
  value=tostring(value);flags=flags or 0
  local x,y=G.x,G.y;right,bottom=right or left+width/dpi,bottom or top+height/dpi
  value=fit(value,max(0,right-x))
  local w,h=text:measurestr(value)
  if flags&2~=0 then x=right-w elseif flags&1~=0 then x=x+(right-x-w)/2 end
  if flags&4~=0 then y=y+(bottom-y-h)/2 end
  text:capture(command,value,x-left,y-top,color,alpha);text:paint(command,bitmap)
 end
 function V:begin(A,x,y,w,h,scale,now)
  dpi=ceil(host.dpi or 1);left,top=x,y
  local iw,ih=max(1,ceil(w*scale*dpi)),max(1,ceil(h*scale*dpi))
  local d=A.seam_drag or A.seam_hold
  index=0;self.dirty=not image or not self.valid
  check(iw);check(ih);check(dpi);check(scale);check(language.code);check(A.seam);check(A.seam_problem)
  check(A.pjob~=nil);check(A.seam_refreshing);check(A.seam_drag~=nil)
  check(d and d.delta);check(d and d.edge);check(d and d.relative)
  check(d and A.seam_drag and host.g.mouse_x)
  local flashes=A.wave_entry_flash
  for _,side in ipairs({'left','right'}) do
   local stamp=flashes and flashes[side];check(stamp and max(0,1-(now-stamp)/.30) or 0)
  end
  for _,key in ipairs(keys) do local c=C[key];check(c[1]);check(c[2]);check(c[3]) end
  if not self.dirty then return false end
  self.valid=false
  if not bitmap then bitmap=assert(api.JS_LICE_CreateBitmap(true,iw,ih),'Waveform bitmap creation failed')
  elseif iw~=width or ih~=height then api.JS_LICE_Resize(bitmap,iw,ih) end
  width,height=iw,ih;api.JS_LICE_Clear(bitmap,0xff000000)
  return true
 end
 function V:finish()
  api.JS_LICE_ProcessRect(bitmap,0,0,width,height,'SET_A',0xff000000)
  if image then host:releaseImage(image) end
  image=host.I.CreateImageFromLICE(bitmap);host:attachImage(image);self.valid=true
 end
 function V:draw(x,y,w,h,scale)
  local native=host.dpi or 1;local ox,oy=host.windowX or host.originX,host.windowY or host.originY
  x=ox+floor((host.originX-ox+x)*native+.5)/native;y=oy+floor((host.originY-oy+y)*native+.5)/native
  host.I.DrawList_AddImage(host.draw,image,x,y,x+w*scale,y+h*scale)
 end
 function V:close()
  if image then host:releaseImage(image);image=nil end
  if bitmap then api.JS_LICE_DestroyBitmap(bitmap);bitmap=nil end
 end
 return V
end
return M
end)()
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


local NAME="LOOP RM STUDIO"
local APP_NAME="BLT "..NAME
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

 return L
end

local LanguageCatalog={en={
 ['レンダリングの準備中…']='Preparing render...',
 ['書き出し範囲と埋め込み情報を確認しています…']='Checking render ranges and metadata...',
 ['出力先とファイル名を準備しています…']='Preparing output folder and file name...',
 ['REAPERでレンダリング中… 詳細な進捗は標準レンダラーに表示されます。']='Rendering in REAPER... Detailed progress is shown in the native renderer.',
 ['レンダーされたWAVを確認しています…']='Checking rendered WAV...',
 ['音声と区間情報を書き込んでいます…']='Writing audio and region metadata...',
 ['書き出し結果を検証しています…']='Verifying exported WAV...',
 ['一時WAVを整理しています…']='Cleaning up temporary WAV...',
 ['書き出しを中止しました。']='Export cancelled.',
 ['前回の一時WAVを削除できません。再試行してください。']='Cannot remove the previous temporary WAV. Retry.',
 ['一時WAVを削除できないため、一括書き出しを停止しました。完了済み: %d / %d件。']='Batch export stopped because a temporary WAV could not be removed. Completed: %d / %d.',
 ['工程全体の進捗です。標準レンダー中の詳細はREAPERのレンダラーに表示されます。']='Overall stage progress. Detailed native render progress is shown in REAPER.',
 ['書き出しを中止。完成済みのWAVは保持します。']='Cancel export. Keep completed WAV files.',
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
 ["サステイン"]="Sustain",
 ["リージョン"]="Region",
 ["マーカー"]="Marker",
 ["REAPERで選択するリージョンは1つにしてください。"]="Select just one region in REAPER.",
 ["現在のグリッド設定を取得できません。"]="Cannot read current grid settings.",
 ["基準幅／間隔補正が不正です。"]="Invalid base width / gap offset.",
 ["グリッド位置を取得できません。"]="Cannot read grid position.",
 ["単位が不正です。"]="Invalid unit.",
 ["間隔により挿入位置がプロジェクト先頭より前になります。"]="Spacing would place content before project start.",
 ["基準幅は0より大きい値で指定してください。秒は mm:ss または hh:mm:ss も使えます。"]="Base width must be positive. Seconds also accept mm:ss or hh:mm:ss.",
 ["間隔補正は-864000〜864000秒で指定してください。秒は -mm:ss または -hh:mm:ss も使えます。"]="Gap offset must be -864000 to 864000 seconds. -mm:ss or -hh:mm:ss is also accepted.",
 ["個数は0〜1000の整数で指定してください（0＝A：自動）。"]="Count must be an integer from 0 to 1000 (0 = A: automatic).",
 ["クリック入力 / 上下ドラッグ / ホイール。0＝A：選択時間÷（基準幅＋間隔補正）の整数部分を自動挿入。計算できない場合は1個、最大1000個。"]="Click to type / Drag vertically / Wheel. 0 = A: insert the whole-number count from time-selection duration / (base width + gap offset). Use 1 if unavailable; maximum 1000.",
 ["自動個数が1000個を超えるため、1000個に制限して挿入しました。"]="Automatic count exceeded 1000; insertion was limited to 1000.",
 ["基準幅の単位が不正です。"]="Invalid base width unit.",
 ["基準幅の値が不正です。"]="Invalid base width value.",
 ["間隔補正の単位が不正です。"]="Invalid gap offset unit.",
 ["間隔補正の値が不正です。"]="Invalid gap offset value.",
 ["アイテムを選択してください。"]="Select items.",
 ["選択アイテムは1000個までにしてください。"]="Select at most 1000 items.",
 ["長さが不正なアイテムがあります。"]="Some items have invalid lengths.",
 ["追加方法が不正です。"]="Invalid insertion mode.",
 ["先にREAPERで時間選択を作ってください。"]="Create a time selection in REAPER first.",
 ["追加する範囲が不正です。"]="Invalid insertion range.",
 ["名前にNUL文字は使用できません。"]="Names cannot contain NUL.",
 ["名前が正しいUTF-8ではありません。"]="Name is not valid UTF-8.",
 ["CP932に変換できない文字があります: "]="Character cannot be encoded in CP932: ",
 [" — 名前を変更するかUTF-8を選んでください。"]=" — Rename it or choose UTF-8.",
 ["書き出し範囲を指定してください。"]="Specify an export range.",
 ["サンプルレートが不正です。"]="Invalid sample rate.",
 ["書き出し範囲がWAVの上限を超えています。"]="Export range exceeds WAV limits.",
 ["リージョン位置が不正です。"]="Invalid region position.",
 ["不明なBLT接頭辞: "]="Unknown BLT prefix: ",
 ["未対応の区間種類です。"]="Unsupported section type.",
 ["1サンプル未満のリージョンがあります: "]="Region shorter than one sample: ",
 ["名前が長すぎます。"]="Name too long.",
 ["REAPERから出力先を取得できません。"]="Cannot read output path from REAPER.",
 ["REAPER本体の設定からWAV出力先を取得できません。出力形式をWAVにしてください。"]="Cannot read WAV output path. Set REAPER output format to WAV.",
 ["REAPER本体の設定から複数のWAV出力先が返されました。セカンダリ出力やステム出力を無効にしてください。"]="REAPER returned multiple WAV paths. Disable secondary/stem output.",
 ["一括出力名の指定が不正です。"]="Invalid batch output name.",
 ["リージョン情報が大きすぎます。"]="Region metadata too large.",
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
 ["既存のWAVメタデータが大きすぎます。"]="Existing WAV metadata too large.",
 ["音声データがありません、またはサンプル境界が不正です。"]="No audio data or invalid sample alignment.",
 ["出力ファイル名を確保できません。"]="Cannot reserve output filename.",
 ["出力先は新しいWAVファイルを指定してください。"]="Choose a new WAV file as the destination.",
 ["レンダーのサンプルレートが一致しません。"]="Render sample rate mismatch.",
 ["レンダーの長さが一致しません。\n指定範囲: %.9f ～ %.9f 秒\n予定: %d samples (%.9f 秒)\n実際: %d samples (%.9f 秒)\n差: %+d samples / %+.6f ms\nサンプルレート: %d Hz"]="Render duration mismatch.\nRange: %.9f to %.9f s\nExpected: %d samples (%.9f s)\nActual: %d samples (%.9f s)\nDifference: %+d samples / %+.6f ms\nSample rate: %d Hz",
 ["レンダー音声に必要な切り出し範囲が含まれていません。"]="Rendered audio does not contain the complete required slice.",
 ["メタデータが実際のWAV終端を超えています。"]="Metadata exceeds the actual WAV end.",
 ["BWF時刻が上限を超えています。"]="BWF time exceeds limit.",
 ["4 GiBを超えるWAVには対応していません。"]="WAV files over 4 GiB are unsupported.",
 ["作業ファイルが存在します: "]="Work file exists: ",
 ["書き込み検証に失敗しました。"]="Write verification failed.",
 ["出力先が別の処理で作成されました。再実行してください。"]="Another process created the output file. Run again.",
 ["REAPERのリージョン選択APIを利用できません。REAPERを更新してください。"]="Region selection API unavailable. Update REAPER.",
 ["レンダー対象リージョンの選択を変更できません。"]="Cannot change render region selection.",
 ["レンダー対象リージョンが見つかりません: "]="Render region not found: ",
 ["レンダー設定を取得できません: "]="Cannot read render setting: ",
 ["ビット深度が不正です。"]="Invalid bit depth.",
 ["チャンネル数が不正です。"]="Invalid channel count.",
 ["レンダー対象リージョンが不正です。"]="Invalid render region.",
 ["レンダー用の時間選択をサンプル精度で設定できません。時間選択のロックなどを確認してください。"]="Cannot set sample-accurate render selection. Check time-selection locking.",
 ["レンダー設定を変更できません: "]="Cannot change render setting: ",
 ["REAPER本体の出力形式を取得できません。"]="Cannot read REAPER output format.",
 ["REAPER本体の出力形式をWAVに設定してください。"]="Set REAPER output format to WAV.",
 ["対応形式はWAV 16/24 bit PCM・32 bit floatです。"]="WAV 16/24-bit PCM and 32-bit float supported.",
 ["標準サンプルレートを解決できません。REAPER本体で明示指定してください。"]="Cannot resolve default sample rate. Set it explicitly in REAPER.",
 ["REAPER本体のチャンネル数が不正です。"]="Invalid REAPER channel count.",
 ["追加する区間種類が不正です。"]="Invalid section type to add.",
 ["開始番号は1〜12桁の数字で指定してください。"]="Start number must contain 1 to 12 digits.",
 ["開始番号が大きすぎます。"]="Start number too large.",
 ["音声アイテムを1〜1000個選択してください。"]="Select 1 to 1000 audio items.",
 ["クロスフェードに必要な仮想トラック素材が足りません。"]="Not enough virtual-track audio for crossfade.",
 ["クロスフェードに必要な素材尺が足りません。"]="Source too short for crossfade.",
 ["クロスフェード置換範囲が不正です。"]="Invalid crossfade replacement range.",
 ["クロスフェード置換範囲を確定できません。"]="Cannot determine crossfade replacement range.",
 ["クロスフェード置換範囲の音声アイテムがありません。"]="No audio items in crossfade replacement range.",
 ["クロスフェード置換範囲をサンプル境界へ整列できません。"]="Cannot align crossfade range to sample boundaries.",
 ["クロスフェード時間を指定してください。"]="Specify crossfade duration.",
 ["サステイン区間が2サンプル未満のため、クロスフェードできません。"]="Sustain is shorter than two samples; cannot crossfade.",
 ["ループポイント直前にクロスフェード用の音声が2サンプル以上必要です。"]="At least two samples of audio are needed before the loop point.",
 ["ループ尺が足りません。クロスフェード時間はループ長以下、2サンプル以上にしてください。"]="Crossfade must be at least two samples and no longer than the loop.",
 ["クロスフェード置換範囲が不足しています。"]="Insufficient crossfade replacement range.",
 ["クロスフェード置換範囲の音声アイテムがロックされています。"]="Audio items in crossfade range are locked.",
 ["アイテムの復元情報を取得できません。"]="Cannot read item restore data.",
 ["固定レーンをまたぐクロスフェード重複は、通常の音声アイテムへまとめてから実行してください。"]="Merge overlapping crossfades across fixed lanes into regular audio items first.",
 ["4 GiBを超える加工素材には対応していません。"]="Processed audio over 4 GiB is unsupported.",
 ["作業ファイルが存在します。"]="Work file exists.",
 ["トラック合成音声を取得できません。"]="Cannot read mixed track audio.",
 ["仮想トラック素材の音声範囲を取得できません。"]="Cannot read virtual-track audio range.",
 ["元WAVを開けません。"]="Cannot open source WAV.",
 ["音声アクセサーを作成できません。"]="Cannot create audio accessor.",
 ["素材尺が足りません。必要な音声範囲を取得できません。"]="Source too short for the required audio range.",
 ["元WAVの読み取り範囲が不正です。"]="Invalid source WAV read range.",
 ["元WAVの音声読み取りに失敗しました。"]="Failed to read source WAV audio.",
 ["素材の音声取得に失敗しました。"]="Failed to read source audio.",
 ["処理中にプロジェクトが変更されました。やり直してください。"]="Project changed during processing. Retry.",
 ["素材に不正な音声値があります。"]="Source contains invalid audio values.",
 ["加工音声の検証に失敗しました。"]="Processed audio validation failed.",
 ["ループ音声を保存できません。"]="Cannot save loop audio.",
 ["プロジェクトが変更されました。"]="Project changed.",
 ["クロスフェード対象のアイテムが変更されました。"]="Crossfade target items changed.",
 ["アイテムが変更されました。"]="Item changed.",
 ["安全なクロスフェード置換に必要なUndo APIを利用できません。"]="Undo API required for safe crossfade replacement is unavailable.",
 ["アイテムの分割に失敗しました。"]="Item split failed.",
 ["分割端のフェードを更新できません。"]="Cannot update split-edge fades.",
 ["加工素材を読み込めません。"]="Cannot load processed audio.",
 ["加工音声用のアイテムを作成できません。"]="Cannot create item for processed audio.",
 ["加工アイテムの位置を設定できません。"]="Cannot set processed item position.",
 ["加工アイテムの長さを設定できません。"]="Cannot set processed item length.",
 ["加工アイテムの音量を設定できません。"]="Cannot set processed item volume.",
 ["加工素材のループ設定を更新できません。"]="Cannot update processed source loop setting.",
 ["加工アイテムの固定レーンを設定できません。"]="Cannot set processed item fixed lane.",
 ["加工音声用のテイクを作成できません。"]="Cannot create take for processed audio.",
 ["加工素材を適用できません。"]="Cannot apply processed audio.",
 ["加工テイクの再生設定を更新できません。"]="Cannot update processed take playback settings.",
 ["置換前の重複音声を取り除けません。"]="Cannot remove overlapping original audio.",
 ["加工区間のテイクを取得できません。"]="Cannot read take in processed section.",
 ["加工素材の開始位置を更新できません。"]="Cannot update processed source offset.",
 ["サステインのサンプル位置を更新できません。"]="Cannot update sustain sample position.",
 ["\n一部のアイテムを復元できませんでした。REAPERのUndoで処理を戻してください。"]="\nSome items could not be restored. Use REAPER Undo.",
 ["BLT LOOP RM STUDIO: クロスフェードループ"]="BLT LOOP RM STUDIO: Crossfade loop",
 ["\n処理前のアイテムを自動復元できませんでした。REAPERのUndoを実行してください。"]="\nCould not automatically restore original items. Use REAPER Undo.",
 ["クロスフェード素材がまだ適用されていません。"]="Crossfade audio has not been applied yet.",
 ["生成素材の波形ピークを構築できません。"]="Cannot build peaks for generated audio.",
 ["音声に不正な値があります。"]="Audio contains invalid values.",
 ["ゼロクロスを判定できません。対象付近が無音です。"]="Cannot detect zero crossing; nearby audio is silent.",
 ["指定方向の100 ms以内に次のゼロクロスが見つかりませんでした。"]="No next zero crossing within 100 ms in that direction.",
 ["前後20 ms以内にゼロクロスが見つかりませんでした。"]="No zero crossing within 20 ms either side.",
 ["周期解析範囲が不正です。"]="Invalid period analysis range.",
 ["100秒を超えるサステインは周期解析できません。"]="Cannot analyze periods for sustains over 100 seconds.",
 ["周期解析には少なくとも0.6秒程度の音声が必要です。"]="Period analysis needs at least about 0.6 seconds of audio.",
 ["明確なリズム周期を検出できませんでした。"]="No clear rhythmic period detected.",
 ["安定した周期を検出できませんでした。"]="No stable period detected.",
 ["周期候補を絞り込めませんでした。"]="Cannot narrow down period candidates.",
 ["周期に合わせると区間がなくなります。長めのサステインを指定してください。"]="Period alignment leaves no range. Use a longer sustain.",
 ["解析方法が不正です。"]="Invalid analysis method.",
 ["移動方向が不正です。"]="Invalid move direction.",
 ["音声アイテムを選択してください。"]="Select audio items.",
 ["選択アイテムの位置または長さが不正です。"]="Invalid selected item position or length.",
 ["選択アイテムに複数のサステインが重なっています。対象を分けて選択してください。"]="Multiple sustains overlap selected items. Select targets separately.",
 ["選択アイテムと重なるサステインがありません。"]="No sustain overlaps selected items.",
 ["同じループを構成する音声アイテムは同じトラックから選択してください。"]="Select audio for one loop from the same track.",
 ["サステイン上の選択アイテム間に隙間があります。連続するアイテムを選択してください。"]="Gaps between selected items over sustain. Select contiguous items.",
 ["サステイン開始を覆う音声アイテムも選択してください。"]="Also select audio covering sustain start.",
 ["サステイン終了を覆う音声アイテムも選択してください。"]="Also select audio covering sustain end.",
 ["境界付近にゼロクロス解析用の音声が足りません。"]="Not enough audio near boundaries for zero-crossing analysis.",
 ["プレビュー範囲が仮想トラック素材の外です。"]="Preview range is outside virtual-track audio.",
 ["周期解析範囲を選択アイテムで覆えていません。"]="Selected items do not cover period analysis range.",
 ["周期解析範囲が100秒を超えています。"]="Period analysis range exceeds 100 seconds.",
 ["調整後のサステイン区間が短すぎます。"]="Adjusted sustain is too short.",
 ["移動先を探す基準トラックを取得できません。"]="Cannot read reference track for destination search.",
 ["移動先のアイテムが多すぎます。"]="Too many items at destination.",
 ["移動先の音声範囲を延長できません。"]="Cannot extend destination audio range.",
 ["選択アイテム内に有効なループ範囲を確保できません。"]="No valid loop range within selected items.",
 ["解析中にプロジェクトが変更されました。やり直してください。"]="Project changed during analysis. Retry.",
 ["仮想トラック素材の解析範囲を取得できません。"]="Cannot read virtual-track analysis range.",
 ["音声を取得できません。"]="Cannot read audio.",
 ["解析範囲の音声を取得できません。"]="Cannot read audio in analysis range.",
 ["解析したアイテムが削除されました。"]="Analyzed item was deleted.",
 ["解析したアイテムのアクティブテイクが変更されました。"]="Analyzed item's active take changed.",
 ["解析したアイテムの位置または素材範囲が変更されました。"]="Analyzed item position or source range changed.",
 ["サステインの更新に失敗しました。"]="Failed to update sustain.",
 ["\n一部を復元できませんでした。REAPERのUndoで戻してください。"]="\nSome data could not be restored. Use REAPER Undo.",
 ["ゼロクロスへ調整"]="Align to zero crossing",
 ["周期へ調整"]="Align to period",
 ["アイテムが選択されていません"]="No items selected",
 ["操作中のループリージョンが見つかりません。"]="Active loop region not found.",
 ["選択アイテム範囲に収まるループリージョンがありません"]="No loop region fits within selected items",
 ["選択アイテム範囲にループリージョンが複数存在しています！"]="Multiple loop regions within selected items!",
 ["対象のサステインリージョンが不正です。"]="Invalid target sustain region.",
 ["波形を見る音声アイテムを選択してください。"]="Select audio items to view the waveform.",
 ["対象リージョンと重なる音声アイテムは同じトラックから選択してください。"]="Select audio overlapping the target region from one track.",
 ["選択したサステインと重なる音声アイテムを選択してください。"]="Select audio overlapping the selected sustain.",
 ["選択アイテムが離れた複数の素材群に分かれています。対象を分けて選択してください。"]="Selected items form separate blocks. Select targets separately.",
 ["選択アイテムを対象トラック上で確認できませんでした。"]="Cannot find selected items on target track.",
 ["サステイン全体を覆う、隙間のない連続音声アイテムを同じトラックに配置してください。"]="Place contiguous audio covering the full sustain on one track.",
 ["仮想素材として扱える連続アイテムは1000個までです。"]="Virtual source supports at most 1000 contiguous items.",
 ["仮想トラック素材に音声アイテムがありません。"]="No audio items in virtual track source.",
 ["MIDIではなく音声アイテムを選択してください。"]="Select audio items, not MIDI.",
 ["仮想素材として扱う音声アイテムは同じトラックから選択してください。"]="Select virtual source audio from one track.",
 ["音声アイテムの位置または長さが不正です。"]="Invalid audio item position or length.",
 ["仮想トラック素材のサンプルレートを取得できません。"]="Cannot read virtual-track sample rate.",
 ["仮想トラック素材のチャンネル数を取得できません。"]="Cannot read virtual-track channel count.",
 ["仮想トラック素材から音声範囲を取得できません。"]="Cannot read audio range from virtual track.",
 ["移動する境界が不正です。"]="Invalid boundary to move.",
 ["ドラッグ移動量が不正です。"]="Invalid drag distance.",
 ["ループ調整に使う音声アイテムは同じトラックから選択してください。"]="Select loop adjustment audio from one track.",
 ["ループ調整に使う音声アイテム間に隙間があります。"]="Gaps between audio items used for loop adjustment.",
 ["開始側と終了側の音声アイテムを両方選択してください。"]="Select audio items at both start and end.",
 ["波形ドラッグ量が不正です。"]="Invalid waveform drag distance.",
 ["波形表示位置が不正です。"]="Invalid waveform display position.",
 ["サステイン範囲が不正です。"]="Invalid sustain range.",
 ["波形表示幅が不正です。"]="Invalid waveform display width.",
 ["調整したサステイン範囲がありません。"]="No adjusted sustain range.",
 ["調整後のサステイン範囲が不正です。"]="Invalid adjusted sustain range.",
 ["自動再生範囲を取得できません。"]="Cannot read auto-playback range.",
 ["時間選択から区間を追加し、WAVへ書き出します。"]="Add sections from the time selection and export WAV.",
 ["CHAMELEON  REAPERテーマに擬態"]="CHAMELEON  REAPER theme",
 ["CHAMELEON  オリジナル配色"]="CHAMELEON  Original colors",
 ["カスタムタイトルバーには js_ReaScriptAPI が必要です。\nReaPack から js_ReaScriptAPI をインストールしてください。"]="The app bar requires js_ReaScriptAPI.\nInstall js_ReaScriptAPI via ReaPack.",
 ["ReaImGui 0.10以降が必要です。ReaPackで導入・更新してください。"]="ReaImGui 0.10+ is required. Install/update via ReaPack.",
 ["日本語入力欄を初期化できません。\n"]="Cannot initialize the text input.\n",
 ["あいうえお漢字ABC012345"]="あいうえお漢字ABC012345",
 ["\n\nレンダー音声は保持しています:\n"]="\n\nRendered audio retained:\n",
 ["配置元が不正です。"]="Invalid placement source.",
 ["保存先フォルダーを開き、「保存」で選択"]="Open the destination folder and choose Save",
 ["このフォルダーを選択.folder"]="Select this folder.folder",
 ["フォルダー選択用 (*.folder)\0*.folder\0"]="Folder selector (*.folder)\0*.folder\0",
 ["保存先のディレクトリパスを取得できません。"]="Cannot read destination directory path.",
 ["プロジェクトが変わりました。"]="Project changed.",
 ["処理中は元に戻せません。処理を完了または中止してください。"]="Cannot undo during processing. Finish or stop first.",
 ["元に戻せる操作がありません。"]="Nothing to undo.",
 ["REAPERのUndo APIを利用できません。"]="REAPER Undo API unavailable.",
 ["元に戻しました。"]="Undone.",
 ["プロジェクトが変わりました。追加をやり直してください。"]="Project changed. Add again.",
 ["を追加"]=": add",
 ["追加できませんでした。"]="Could not add.",
 ["録音中は繋ぎ目を自動再生できません。"]="Cannot auto-play seam while recording.",
 ["プロジェクトの再生速度を取得できません。"]="Cannot read project playback rate.",
 ["繋ぎ目の自動再生を開始できませんでした。"]="Cannot start seam auto-playback.",
 ["録音中は調整できません。録音を停止してください。"]="Stop recording before adjusting.",
 ["再生を停止できませんでした。"]="Cannot stop playback.",
 ["プロジェクトの再生速度を1.0にしてください。"]="Set project playback rate to 1.0.",
 ["クロスフェード用のループ素材を作成中…"]="Creating loop audio for crossfade...",
 ["生成したループ素材の波形を準備中…"]="Preparing generated loop waveform...",
 ["サステイン区間をクロスフェード処理しました。時間選択を追従しました。Undoで戻せます。"]="Sustain crossfade applied. Time selection followed. Undo available.",
 ["開始・終了付近のゼロクロスを解析中…"]="Analyzing zero crossings near start/end...",
 ["サステイン周辺の周期を解析中…"]="Analyzing periods around sustain...",
 ["周期を検出できませんでした・・・！"]="No period detected!",
 ["周期解析を終了しました。リージョンは変更していません。"]="Period analysis finished. Regions unchanged.",
 ["（周期 %.3f 秒 / 一致度 %.0f%%）"]=" (period %.3f s / match %.0f%%)",
 [" 移動先の音声アイテムを選択へ追加: "]=" Added destination audio items to selection: ",
 ["件。"]=" items.",
 ["ゼロクロスへ移動しました。"]="Moved to zero crossing.",
 ["周期に合わせて移動しました。"]="Moved to match period.",
 ["時間選択を追従しました。Undoで戻せます。"]="Time selection followed. Undo available.",
 ["選択アイテム内でこれ以上移動できません"]="Cannot move further within selected items",
 ["出力フォルダーが不正です。"]="Invalid output folder.",
 ["出力フォルダーは絶対パスで指定してください。"]="Use an absolute output folder path.",
 ["ファイル名に使用できない文字があります。"]="Filename contains invalid characters.",
 ["予約されたファイル名です。"]="Reserved filename.",
 ["REAPER本体の保存フォルダーを解決できません。"]="Cannot resolve REAPER save folder.",
 ["出力先のフォルダーを解決できません。"]="Cannot resolve output folder.",
 ["リージョン情報を埋め込んでいます…"]="Embedding region metadata...",
 ["書き出し中にプロジェクトが切り替わりました。"]="Project switched during export.",
 ["一時ファイル名が衝突しました。"]="Temporary filename collision.",
 ["出力先に同名ファイルが作成されました。再実行してください。"]="Output file already created. Run again.",
 ["REAPERでミックスダウン中… %d / %d"]="Mixing down in REAPER... %d / %d",
 ["REAPERでミックスダウン中…"]="Mixing down in REAPER...",
 ["REAPERが予期しないWAV出力先を返しました: "]="REAPER returned an unexpected WAV path: ",
 ["レンダーがキャンセルされたか、WAVが作成されませんでした。"]="Render cancelled or WAV not created.",
 ["レンダー音声を一時保存名へ変更できませんでした。"]="Cannot rename rendered audio to temporary filename.",
 ["レンダーされたWAVのチャンネル数／ビット深度が設定と一致しません。"]="Rendered WAV channel count / bit depth does not match settings.",
 ["リージョンを選択されていません"]="No regions selected",
 ["選択したリージョンからレンダー範囲を取得できませんでした"]="Cannot read render range from selected regions",
 ["再生・録音を停止してから書き出してください。"]="Stop playback/recording before exporting.",
 ["4 GiBを超える出力には対応していません。"]="Output over 4 GiB is unsupported.",
 ["解析を中止しました。リージョンは変更していません。"]="Analysis stopped. Regions unchanged.",
 ["クロスフェード処理を中止しました。"]="Crossfade processing stopped.",
 ["一括書き出しを中止しました。完了済み: "]="Batch export stopped. Completed: ",
 ["件。現在のレンダー音声は保持されています。"]=" items. Current rendered audio retained.",
 ["埋め込みを中止しました。元の音声は保持されています。"]="Embedding stopped. Original audio retained.",
 ["完了。一時WAVが残っています: "]="Done. Temporary WAV remains: ",
 ["書き出し完了: "]="Export complete: ",
 ["件"]=" items",
 ["選択範囲"]="Time range",
 ["選択アイテム（個別）"]="Each item",
 ["選択アイテム全体"]="All items",
 ["カーソル位置"]="Cursor",
 ["秒"]="sec",
 ["拍"]="beats",
 ["小節"]="bars",
 ["グリッド"]="grid",
 ["原則UTF-8を推奨\nSoundForgeで日本語を文字化けさせたくない場合のみCP932を選択してください。\nただし他の大多数アプリケーションで文字化けします。※英語圏には無関係な機能です"]="UTF-8 recommended.\nUse CP932 only for Japanese names in SoundForge.\nMost other applications will misread CP932; irrelevant for English-only names.",
 ["相対保持"]="Link ends",
 ["ONでは開始と終了を同じ量だけ移動し、ループ尺を保持"]="ON: move start and end equally to keep loop length",
 ["入力できない制御文字、または長すぎる文字列です。"]="Invalid control character or text too long.",
 ["保存フォルダーを入力してください。"]="Enter a save folder.",
 ["数値を入力できなかったため、元の値へ戻しました。"]="Invalid input. Previous value restored.",
 ["クリック入力 / 上下ドラッグ / ホイール"]="Click to type / Drag vertically / Wheel",
 ["クリックして直接入力"]="Click to type",
 [" / REAPERワイルドカード使用可"]=" / REAPER wildcards supported",
 [" / Shiftで微調整"]=" / Shift: fine adjust",
 ["名前と番号を設定"]="NAME & NUMBER",
 ["名前"]="Name",
 ["選択アイテム名を使用"]="Use selected item names",
 ["拡張子を無視"]="Ignore extension",
 ["アイテム名の末尾の拡張子を除いて使用"]="Use item names without the final extension",
 ["挿入色を選択"]="Choose insertion color",
 ["カラー選択を開けませんでした。"]="Could not open the color chooser.",
 ["ONではアイテム名をそのまま使用（連番なし）"]="ON: use item names unchanged (no numbering)",
 ["番号を付与"]="Add numbers",
 ["OFFではすべて同じ名前で追加"]="OFF: add all with the same name",
 ["開始番号"]="Start number",
 ["キャンセル"]="Cancel",
 ["追加を取り消す"]="Cancel insertion",
 ["追加"]="Add",
 ["指定した名前で追加"]="Add with this name",
 ["ドラッグ中にプロジェクトが変わりました。やり直してください。"]="Project switched during drag. Retry.",
 ["ドラッグ中にプロジェクトが変更されました。やり直してください。"]="Project changed during drag. Retry.",
 ["波形ドラッグでループ範囲を移動"]="Move loop range by dragging waveform",
 ["終了位置"]="End",
 ["開始位置"]="Start",
 ["を波形ドラッグで移動しました。"]=" moved by waveform drag.",
 [" 時間選択を追従しました。Undoで戻せます。"]=" Time selection followed. Undo available.",
 ["選択アイテム範囲に収まる\nループリージョンがありません"]="No loop region fits\nwithin selected items",
 ["選択アイテム範囲に\nループリージョンが\n複数存在しています！"]="Multiple loop regions\nwithin selected\nitems!",
 ["継ぎ目を読み取り中…"]="Reading seam...",
 ["終了 −6 ms  /  DRAG"]="End -6 ms / DRAG",
 ["開始 ＋6 ms  /  DRAG"]="Start +6 ms / DRAG",
 [" / クリックで更新"]=" / Click to refresh",
 ["更新中…"]="Updating...",
 ["終了 "]="End ",
 ["開始 "]="Start ",
 ["  /  相対保持"]=" / Linked ends",
 ["波形を右へドラッグ＝時間位置を前へ / 左へドラッグ＝後ろへ / クリックで更新"]="Drag right: move earlier / Drag left: move later / Click: refresh",
 ["LOOP / REGION / MARKER MANAGER  ループ・リージョン・マーカー管理ツール"]="LOOP / REGION / MARKER MANAGER  Manage loops, regions and markers",
 ["ループ・リージョン・マーカーを追加"]="ADD LOOP / REGION / MARKER",
 ["ループ（サステイン）"]="Loop (sustain)",
 ["を配置元にする"]=": placement source",
 ["個数"]="Qty",
 ["基準幅"]="Width",
 ["リージョンの長さ／マーカーの配置基準幅"]="Region length / marker placement base width",
 ["間隔補正"]="Gap",
 ["次の配置位置＝現在位置＋基準幅＋間隔補正。-基準幅で同位置、さらに小さい負値で左方向"]="Next position = current + base width + gap. Negative base width repeats position; smaller values move left.",
 ["名前入力を省略"]="Skip name input",
 ["ONでは追加時の名前入力を省略します"]="ON: add without asking for a name",
 ["ループ調整"]="LOOP ADJUSTMENT",
 ["クロスフェードを適用"]="Apply crossfade",
 ["レベル突出を抑える滑らかなカーブで指定時間分だけ加工。時間は2サンプル〜ループ長に自動補正"]="Smooth curve limits level buildup. Duration is clamped to 2 samples through loop length.",
 ["時間"]="Time",
 ["開始・終了の両方を近い位置へ調整"]="Adjust both start and end to nearby positions",
 ["終了"]="End",
 ["開始"]="In",
 ["と反対端を同じ量だけ移動（ループ尺を保持）"]=" and opposite end move equally (keep loop length)",
 ["だけを"]=" only to ",
 ["前"]="previous",
 ["次"]="next",
 ["の"]=" ",
 ["ゼロクロス"]="zero crossing",
 ["周期"]="period",
 ["へ移動"]=": move",
 ["最寄りゼロクロスへ補正"]="Snap to nearest zero crossing",
 ["周期を検出し補正"]="Detect and align to period",
 ["調整後、繋ぎ目を自動再生"]="Auto-play seam after adjustment",
 ["通常はループ末端の0.75秒前から再生。クロスフェード時はその開始点（最低0.75秒前）から再生し、1回ループした約1秒後に停止"]="Usually play from 0.75 s before loop end. With crossfade, start at its beginning (at least 0.75 s early); stop about 1 s after one loop.",
 ["レンダリング設定"]="RENDER SETTINGS",
 ["対象"]="Source",
 ["マスターミックス"]="Master mix",
 ["マスターミックス\n現状マスターミックスのみ対応としています。"]="Master mix\nOnly master mix is currently supported.",
 ["選択リージョン"]="Selected regions",
 ["選択リージョン\n現状選択リージョンの書き出しのみ対応しています。\nREAPER本体や、BLT MARKER REGION DESK等でリージョンを選択してください。"]="Selected regions\nOnly selected region export is supported.\nSelect regions in REAPER or BLT MARKER REGION DESK.",
 ["Master mix  /  REAPERで選択した各リージョンを個別のWAVとしてレンダリングします"]="Master mix / Render each selected REAPER region to a separate WAV",
 ["フォーマット"]="FORMAT",
 ["REAPER本体の設定を使用"]="Use REAPER settings",
 ["WAVのビット深度・サンプルレート・チャンネル数をREAPER本体から参照"]="Read WAV bit depth, sample rate and channels from REAPER",
 ["形式"]="Format",
 ["ビット深度"]="Bit depth",
 ["サンプルレート"]="Sample rate",
 ["チャンネル"]="Channels",
 ["WAV\n現状WAVのみ対応としています。\nOGG等への対応はしていません。"]="WAV\nOnly WAV is supported.\nOGG and other formats are unsupported.",
 ["WAVのビット深度"]="WAV bit depth",
 ["出力サンプルレート"]="Output sample rate",
 ["出力チャンネル数"]="Output channel count",
 ["出力先"]="OUTPUT",
 ["（プロジェクトの標準保存先）"]="(Project default folder)",
 ["（REAPERの既定名）"]="(REAPER default name)",
 ["保存フォルダー"]="Folder",
 ["REAPER設定を使用"]="Use REAPER",
 ["保存フォルダーのみREAPER本体の設定を使用"]="Use REAPER settings for save folder only",
 ["参照"]="Browse",
 ["保存フォルダーを選択"]="Choose save folder",
 ["ファイル名"]="Filename",
 ["ファイル名のみREAPER本体の設定を使用。ワイルドカードもREAPERで解決"]="Use REAPER filename settings; REAPER also resolves wildcards",
 ["埋め込むマーカー/リージョンを設定"]="EMBED MARKERS / REGIONS",
 ["レンダー範囲内のマーカーをWAVへ埋め込み"]="Embed markers within the render range into WAV",
 ["レンダー範囲内の通常リージョンをWAVへ埋め込み"]="Embed regular regions within the render range into WAV",
 ["ループリージョン"]="Loop regions",
 ["レンダー範囲内のサステインをWAVのループ情報として埋め込み"]="Embed sustains within the render range as WAV loop data",
 ["選択中のリージョンを除外"]="Exclude selected regions",
 ["書き出し範囲として選択しているリージョンは埋め込まないようにします。\nただし、ループリージョン自体を選択して書き出した場合に、ループリージョンは除外しません。"]="Do not embed regions selected as export ranges.\nSelected loop regions are still embedded when exported themselves.",
 ["マーカー文字コード設定"]="MARKER ENCODING",
 ["出力 "]="Output ",
 ["件 / 埋め込み "]=" / Embedded ",
 ["件 / 除外 "]=" / Excluded ",
 ["件 / 範囲外 "]=" / Outside ",
 ["件 / 切詰め "]=" / Trimmed ",
 ["処理中"]="Processing",
 ["レンダリング実行"]="Render",
 ["Master mixをレンダーして区間情報を埋め込む"]="Render master mix and embed section metadata",
 ["中止"]="Stop",
 ["埋め込みを中止。元のWAVは保持"]="Stop embedding; keep original WAV",
 ["BLT LOOP RM STUDIO | 必要な拡張"]="BLT LOOP RM STUDIO | Required extension",
 ["カスタムアプリバーを初期化できません。"]="Cannot initialize the app bar.",
 ["表示言語を切替（JP / EN）"]="Switch language (JP / EN)",
 ["プリセットを読み込みました: ファクトリーデフォルト"]="Loaded: Factory Default",
 ["選択中のトラック / バスを指定"]="Use selected track / bus",
},patterns={
 {"^処理中  (%d+)/(%d+)$","Processing  %d/%d"},
 {"^一時WAVを削除できないため、一括書き出しを停止しました。完了済み: (%d+) / (%d+)件。$","Batch export stopped because a temporary WAV could not be removed. Completed: %d / %d."},
 {"^「(.*)」を上書きしますか？$","Overwrite \"%s\"?"},
 {"^([%+%-]?[%d%.eE]+)–([%+%-]?[%d%.eE]+) / ([%+%-]?[%d%.eE]+)   スクロールで選択$","%d–%d / %d   Scroll to browse"},
 {"^解析中%.%.%.([%+%-]?[%d%.eE]+)%%$","Analyzing...%d%%"},
 {"^レンダーの長さが一致しません。\n指定範囲: ([%+%-]?[%d%.eE]+) ～ ([%+%-]?[%d%.eE]+) 秒\n予定: ([%+%-]?[%d%.eE]+) samples %(([%+%-]?[%d%.eE]+) 秒%)\n実際: ([%+%-]?[%d%.eE]+) samples %(([%+%-]?[%d%.eE]+) 秒%)\n差: ([%+%-]?[%d%.eE]+) samples / ([%+%-]?[%d%.eE]+) ms\nサンプルレート: ([%+%-]?[%d%.eE]+) Hz$","Render duration mismatch.\nRange: %.9f to %.9f s\nExpected: %d samples (%.9f s)\nActual: %d samples (%.9f s)\nDifference: %+d samples / %+.6f ms\nSample rate: %d Hz"},
 {"^（周期 ([%+%-]?[%d%.eE]+) 秒 / 一致度 ([%+%-]?[%d%.eE]+)%%）$"," (period %.3f s / match %.0f%%)"},
 {"^REAPERでミックスダウン中… ([%+%-]?[%d%.eE]+) / ([%+%-]?[%d%.eE]+)$","Mixing down in REAPER... %d / %d"},
 {"^「(.-)」を上書きしますか？$","\"%s\"?"},
 {"^(.-)」を上書きしますか？$","%s\"?"},
 {"^プリセットを保存しました: (.-)$","Saved: %s"},
 {"^プリセットを読み込みました: (.-)$","Loaded: %s"},
 {"^(.-)個インポートしました。$","%s preset(s) imported."},
 {"^現在: (.-)(.-)$","Current: %s%s"},
 {"^CP932に変換できない文字があります: (.-) — 名前を変更するかUTF%-8を選んでください。$","Character cannot be encoded in CP932: %s — Rename it or choose UTF-8."},
 {"^(.-) — 名前を変更するかUTF%-8を選んでください。$","%s — Rename it or choose UTF-8."},
 {"^不明なBLT接頭辞: (.-)$","Unknown BLT prefix: %s"},
 {"^1サンプル未満のリージョンがあります: (.-)$","Region shorter than one sample: %s"},
 {"^作業ファイルが存在します: (.-)$","Work file exists: %s"},
 {"^レンダー対象リージョンが見つかりません: (.-)$","Render region not found: %s"},
 {"^レンダー設定を取得できません: (.-)$","Cannot read render setting: %s"},
 {"^レンダー設定を変更できません: (.-)$","Cannot change render setting: %s"},
 {"^(.-)\n一部のアイテムを復元できませんでした。REAPERのUndoで処理を戻してください。$","%s\nSome items could not be restored. Use REAPER Undo."},
 {"^(.-)\n処理前のアイテムを自動復元できませんでした。REAPERのUndoを実行してください。$","%s\nCould not automatically restore original items. Use REAPER Undo."},
 {"^(.-)周期解析には少なくとも0%.6秒程度の音声が必要です。$","%sPeriod analysis needs at least about 0.6 seconds of audio."},
 {"^(.-)明確なリズム周期を検出できませんでした。$","%sNo clear rhythmic period detected."},
 {"^(.-)安定した周期を検出できませんでした。$","%sNo stable period detected."},
 {"^(.-)周期候補を絞り込めませんでした。$","%sCannot narrow down period candidates."},
 {"^(.-)周期に合わせると区間がなくなります。長めのサステインを指定してください。$","%sPeriod alignment leaves no range. Use a longer sustain."},
 {"^(.-)\n一部を復元できませんでした。REAPERのUndoで戻してください。$","%s\nSome data could not be restored. Use REAPER Undo."},
 {"^日本語入力欄を初期化できません。\n(.-)$","Cannot initialize the text input.\n%s"},
 {"^\n\nレンダー音声は保持しています:\n(.-)$","\n\nRendered audio retained:\n%s"},
 {"^元に戻しました。(.-)$","Undone.%s"},
 {"^(.-)を追加$","%s: add"},
 {"^ 移動先の音声アイテムを選択へ追加: (.-)件。$"," Added destination audio items to selection: %s items."},
 {"^(.-)件。$","%s items."},
 {"^(.-)(.-)(.-)時間選択を追従しました。Undoで戻せます。$","%s%s%sTime selection followed. Undo available."},
 {"^(.-)(.-)時間選択を追従しました。Undoで戻せます。$","%s%sTime selection followed. Undo available."},
 {"^(.-)時間選択を追従しました。Undoで戻せます。$","%sTime selection followed. Undo available."},
 {"^REAPERが予期しないWAV出力先を返しました: (.-)$","REAPER returned an unexpected WAV path: %s"},
 {"^一括書き出しを中止しました。完了済み: (.-)件。現在のレンダー音声は保持されています。$","Batch export stopped. Completed: %s items. Current rendered audio retained."},
 {"^(.-)件。現在のレンダー音声は保持されています。$","%s items. Current rendered audio retained."},
 {"^完了。一時WAVが残っています: (.-)$","Done. Temporary WAV remains: %s"},
 {"^書き出し完了: (.-)件$","Export complete: %s items"},
 {"^(.-)件$","%s items"},
 {"^書き出し完了: (.-)$","Export complete: %s"},
 {"^(.-) / REAPERワイルドカード使用可$","%s / REAPER wildcards supported"},
 {"^(.-) / Shiftで微調整$","%s / Shift: fine adjust"},
 {"^(.-)を波形ドラッグで移動しました。(.-) 時間選択を追従しました。Undoで戻せます。$","%s moved by waveform drag.%s Time selection followed. Undo available."},
 {"^を波形ドラッグで移動しました。(.-) 時間選択を追従しました。Undoで戻せます。$"," moved by waveform drag.%s Time selection followed. Undo available."},
 {"^(.-) 時間選択を追従しました。Undoで戻せます。$","%s Time selection followed. Undo available."},
 {"^(.-) / クリックで更新$","%s / Click to refresh"},
 {"^(.-)を配置元にする$","%s: placement source"},
 {"^(.-)と反対端を同じ量だけ移動（ループ尺を保持）$","%s and opposite end move equally (keep loop length)"},
 {"^(.-)だけを(.-)の(.-)へ移動$","%s only to %s %s: move"},
 {"^だけを(.-)の(.-)へ移動$"," only to %s %s: move"},
 {"^(.-)の(.-)へ移動$","%s %s: move"},
 {"^の(.-)へ移動$"," %s: move"},
 {"^(.-)へ移動$","%s: move"},
 {"^出力 (.-)$","Output %s"},
 {"^(.-)件 / 埋め込み (.-)件 / 除外 (.-)件 / 範囲外 (.-)件 / 切詰め (.-)件$","%s / Embedded %s / Excluded %s / Outside %s / Trimmed %s items"},
 {"^件 / 埋め込み (.-)件 / 除外 (.-)件 / 範囲外 (.-)件 / 切詰め (.-)件$"," / Embedded %s / Excluded %s / Outside %s / Trimmed %s items"},
 {"^(.-)件 / 除外 (.-)件 / 範囲外 (.-)件 / 切詰め (.-)件$","%s / Excluded %s / Outside %s / Trimmed %s items"},
 {"^件 / 除外 (.-)件 / 範囲外 (.-)件 / 切詰め (.-)件$"," / Excluded %s / Outside %s / Trimmed %s items"},
 {"^(.-)件 / 範囲外 (.-)件 / 切詰め (.-)件$","%s / Outside %s / Trimmed %s items"},
 {"^件 / 範囲外 (.-)件 / 切詰め (.-)件$"," / Outside %s / Trimmed %s items"},
 {"^(.-)件 / 切詰め (.-)件$","%s / Trimmed %s items"},
 {"^件 / 切詰め (.-)件$"," / Trimmed %s items"},
 {"^処理中(.-)$","Processing%s"},
 {"^「(.*)」を上書きしますか？$","Overwrite \"%s\"?"},
 {"^(%d+)個インポートしました。$","Imported %s preset(s)."},
 {"^(%d+)件をノーマライズしました。選択を解除しました。$","Normalized %s items and deselected them."},
},prefixes={"REAPERが予期しないWAV出力先を返しました: ","CP932に変換できない文字があります: ","レンダー対象リージョンが見つかりません: ","1サンプル未満のリージョンがあります: ","一括書き出しを中止しました。完了済み: "," 移動先の音声アイテムを選択へ追加: ","\n\nレンダー音声は保持しています:\n","日本語入力欄を初期化できません。\n","完了。一時WAVが残っています: ","レンダー設定を取得できません: ","レンダー設定を変更できません: ","プリセットを読み込みました: ","プリセットを保存しました: ","作業ファイルが存在します: ","不明なBLT接頭辞: ","書き出し完了: ","現在: "}}

LanguageCatalog.en["選択アイテム"]="Selected items"
LanguageCatalog.en["個別"]="Each"
LanguageCatalog.en["ブロック"]="Blocks"
LanguageCatalog.en["全体"]="All"
LanguageCatalog.en["選択アイテム（ブロック）"]="Selected item blocks"
LanguageCatalog.en["選択アイテムから配置範囲を作成"]="Build ranges from selected items"

local Language=create_language(reaper,"BLT_LOOP_RM_STUDIO",LanguageCatalog)
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
local function clamp(x,a,b) return max(a,min(b,x)) end
local function finite(x) return type(x)=='number' and x==x and abs(x)<math.huge end
local function optional_number(fn,...)
 if type(fn)~='function' then return nil end
 local ok,value=pcall(fn,...)
 return ok and finite(value) and value or nil
end
local Core={VERSION='0.5.31',SECTION='BLT_LOOP_RM_STUDIO',MAX_METADATA=16*1024*1024,SEAM_SECONDS=.006,SEAM_DRAG_SECONDS=.250,
 PERIOD_ANALYSIS_MIN=7,PERIOD_ANALYSIS_MAX=100,CROSSFADE_GUARD_FRAMES=1024}
Core.PERIOD_FAILURE='[BLT:PERIOD_FAILURE]'
-- REAPER's stock rate list (also verified in the installed executable).
Core.sample_rates={8000,11025,16000,22050,32000,44100,48000,88200,96000,176400,192000}
Core.channel_options={1,2,4,6,8}
Core.count_spec={0,1000,true,1,0}
Core.length_specs={
 seconds={.001,864000,false,1,3,1},
 beats={.001,100000,false,1,3,1},bars={1,10000,true,1,0,1},grid={1,100000,true,1,0,1}
}
Core.interval_specs={}
for unit,spec in pairs(Core.length_specs) do Core.interval_specs[unit]={-spec[2],spec[2],spec[3],spec[4],spec[5],0} end
function Core.normalize_spec_number(value,spec)
 local n=clamp(value,spec[1],spec[2])
 if spec[3] then return floor(n+.5) end
 local digits=spec[8] or spec[5] or 2;local factor=10^digits
 return (n<0 and math.ceil(n*factor-.5) or floor(n*factor+.5))/factor
end
function Core.interactive_floor(key,unit,fine)
 if key=='length' and (unit=='seconds' or unit=='beats') then return fine and .1 or 1 end
 if key=='xfade_seconds' then return fine and .1 or 1 end
 return nil
end
function Core.field_allows_fine(key,spec)
 return key=='xfade_seconds' or not spec[3] and (spec[4] or 1)<1
end
Core.tags={sustain='[BLT:SUSTAIN]',region='[BLT:REGION]'}
Core.names={sustain='サステイン',region='リージョン',marker='マーカー'}
function Core.valid_insert_color(n) return finite(n) and n%1==0 and n>=-1 and n<=0xffffff end
function Core.classify(isr,name)
 name=name or ''
 if not isr then return 'marker',name end
 for _,kind in ipairs({'sustain','region'}) do
  local tag=Core.tags[kind]
  if name:sub(1,#tag):upper()==tag then return kind,(name:sub(#tag+1):gsub('^%s+','')) end
 end
 if name:upper():match('^%[BLT:') then return 'invalid',name end
 return 'region',name
end
function Core.project_rows(project)
 local rows={};local i=0
 while true do
  local ok,isr,pos,ending,name,id,col=R.EnumProjectMarkers3(project,i)
  if ok==0 then break end
  local kind,clean=Core.classify(isr,name)
  rows[#rows+1]={id=id,isr=isr,start=pos,finish=isr and ending or pos,name=clean,raw=name,kind=kind,color=col,key=(isr and 'r' or 'm')..id}
  i=i+1
 end
 return rows
end
function Core.selected_project_regions(project,rows)
 local selected={}
 if type(R.GetNumRegionsOrMarkers)=='function' and type(R.GetRegionOrMarker)=='function' and type(R.GetRegionOrMarkerInfo_Value)=='function' then
  for i=0,R.GetNumRegionsOrMarkers(project)-1 do
   local ptr=R.GetRegionOrMarker(project,i,'')
   if ptr and R.GetRegionOrMarkerInfo_Value(project,ptr,'B_ISREGION')~=0
    and R.GetRegionOrMarkerInfo_Value(project,ptr,'B_UISEL')~=0 then
    local id=R.GetRegionOrMarkerInfo_Value(project,ptr,'I_NUMBER')
    if finite(id) then selected[#selected+1]='r'..floor(id+.5) end
   end
  end
 else
  -- Compatibility fallback: an exact REAPER time selection identifies a
  -- region only when the native region-selection API is unavailable.
  local s,e=R.GetSet_LoopTimeRange2(project,false,false,0,0,false)
  if e>s then for _,row in ipairs(rows or {}) do
   if row.isr and abs(row.start-s)<=1e-8 and abs(row.finish-e)<=1e-8 then selected[#selected+1]=row.key end
  end end
 end
 local order={};for i,row in ipairs(rows or {}) do order[row.key]=i end
 table.sort(selected,function(a,b) return (order[a] or math.huge)<(order[b] or math.huge) end)
 return selected,table.concat(selected,':')
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

local function measure_at(project,qn)
 local index,first,last=R.TimeMap_QNToMeasures(project,qn)
 if not finite(index) or not finite(first) or not finite(last) or last<=first then return nil end
 return index,first,last
end

-- Piecewise grid coordinates retain the reference's position between grid lines.
local function swing_map(project,qn,grid,inverse)
 local _,first,last=measure_at(project,qn)
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

function Core.advance_grid(project,reference,amount,unit,grid)
 if amount==0 then return reference end
 if unit~='grid' then return reference+amount end
 local qn=R.TimeMap2_timeToQN(project,reference)
 if not finite(qn) then return nil end
 local target
 if grid.mode=='measure' then
  local index,first,last=measure_at(project,qn)
  if not index then return nil end
  local coordinate=index+(qn-first)/(last-first)+amount
  local next_index=math.floor(coordinate)
  local _,a,b=R.TimeMap_GetMeasureInfo(project,next_index)
  if not finite(a) or not finite(b) or b<=a then return nil end
  target=a+(coordinate-next_index)*(b-a)
 elseif grid.mode=='swing' and grid.swing~=0 then
  local straight=swing_map(project,qn,grid,true)
  if not straight then return nil end
  target=swing_map(project,straight+amount*grid.qn,grid,false)
 else
  target=qn+amount*grid.qn
 end
 if not finite(target) then return nil end
 return R.TimeMap2_QNToTime(project,target)
end

function Core.advance(project,origin,amount,unit,grid)
 assert(finite(origin) and finite(amount),'基準幅／間隔補正が不正です。')
 if unit=='seconds' then return origin+amount end
 if unit=='grid' then
  if amount==0 then return origin end
  grid=grid or assert(Core.read_grid(project))
  local target=Core.advance_grid(project,origin,amount,unit,grid)
  assert(finite(target),'グリッド位置を取得できません。')
  return target
 end
 if amount==0 then return origin end
 local beat,measure,numerator,fullbeats=R.TimeMap2_timeToBeats(project,origin)
 if unit=='beats' then return R.TimeMap2_beatsToTime(project,fullbeats+amount) end
 assert(unit=='bars','単位が不正です。')
 -- Maintain fractional position within a measure across time signatures.
 local position=measure+beat/numerator+amount
 local target=floor(position+1e-10);local fraction=max(0,position-target)
 assert(target>=0,'間隔により挿入位置がプロジェクト先頭より前になります。')
 local _,qn_start,qn_end=R.TimeMap_GetMeasureInfo(project,target)
 return R.TimeMap2_QNToTime(project,qn_start+(qn_end-qn_start)*fraction)
end
local function time_number(text,unit)
 local v=tonumber(text)
 if v or unit~='seconds' then return v end
 local raw=tostring(text or ''):match('^%s*(.-)%s*$');local sign=1
 if raw:sub(1,1)=='-' then sign=-1;raw=raw:sub(2)
 elseif raw:sub(1,1)=='+' then raw=raw:sub(2) end
 if raw:match('^%s*:') or raw:match(':%s*$') or raw:match(':%s*:') then return nil end
 local parts={};for part in raw:gmatch('[^:]+') do parts[#parts+1]=tonumber(part) or -1 end
 if #parts~=2 and #parts~=3 then return nil end
 v=0
 for i,n in ipairs(parts) do
  if n<0 or (i>1 and n>=60) or (i<#parts and n%1~=0) then return nil end
  v=v*60+n
 end
 return sign*v
end
function Core.duration(text,unit)
 local v=time_number(text,unit)
 assert(finite(v) and v>0 and v<=864000,'基準幅は0より大きい値で指定してください。秒は mm:ss または hh:mm:ss も使えます。')
 return v
end

-- Shared overlap block formation: positive overlap, transitive across all tracks.
function Core.overlap_blocks(ranges)
 local sorted={};for i,r in ipairs(ranges) do sorted[i]=r end
 table.sort(sorted,function(a,b) return a.start==b.start and a.finish<b.finish or a.start<b.start end)
 local blocks={}
 for _,r in ipairs(sorted) do
  local g=blocks[#blocks]
  if not g or r.start>=g.finish then g={start=r.start,finish=r.finish,members={}};blocks[#blocks+1]=g end
  g.finish=math.max(g.finish,r.finish);g.members[#g.members+1]=r
 end
 return blocks
end

-- Count complete base-width + gap cycles in a window with the selection's
-- duration, anchored at the insertion cursor. Reading here keeps A live between
-- insertions without adding background polling or retained range caches.
function Core.auto_insert_count(project,cursor,length,unit,interval,interval_unit,grid)
 local first,last=R.GetSet_LoopTimeRange2(project,false,false,0,0,false)
 if not finite(first) or not finite(last) then return 1,false end
 local duration=last-first
 if not finite(duration) or duration<=0 then return 1,false end
 local limit=Core.count_spec[2]
 if unit=='seconds' and (interval_unit=='seconds' or interval==0) then
  local step=length+interval
  if not finite(step) or step<=0 then return 1,false end
  local quotient=duration/step
  if not finite(quotient) then return 1,false end
  -- Correct only floating-point boundary noise, never a meaningful remainder.
  local tolerance=min(1e-7,max(1,abs(first),abs(last),duration)*2^-48/step)
  local count=max(1,floor(quotient+tolerance))
  return min(limit,count),count>limit
 end
 -- Reuse the placement map for musical/mixed units: tempo, meter and swing can
 -- make successive cycles differ in seconds. A fixed 1001-step budget prevents
 -- runaway work even for tiny positive spacing or malformed tempo data.
 local start=cursor;local count=0
 for i=1,limit+1 do
  local nominal_end=Core.advance(project,start,length,unit,grid)
  local ok,next_start=pcall(Core.advance,project,nominal_end,interval,interval_unit,grid)
  if not ok or not finite(next_start) then return 1,false end
  local epsilon=max(1,abs(start),abs(nominal_end),abs(next_start))*2^-48
  if next_start-start<=epsilon then return 1,false end
  local tolerance=max(epsilon*i,max(1,abs(first),abs(last))*2^-48)
  if next_start-cursor>duration+tolerance then break end
  count=i;start=next_start
 end
 return max(1,min(limit,count)),count>limit
end

function Core.item_order(a,b)
 if a.start~=b.start then return a.start<b.start end
 if a.track_index~=b.track_index then return a.track_index<b.track_index end
 if a.finish~=b.finish then return a.finish<b.finish end
 return a.order<b.order
end
function Core.add_ranges(project,mode,kind,length,unit,count,interval,interval_unit)
 local ranges={}
 if mode=='cursor' then
  assert(finite(count) and count>=Core.count_spec[1] and count<=Core.count_spec[2] and count%1==0,'個数は0〜1000の整数で指定してください（0＝A：自動）。')
  local spec=Core.length_specs[unit];assert(spec,'基準幅の単位が不正です。')
  assert(finite(length) and length>=spec[1] and length<=spec[2] and (not spec[3] or length%1==0),'基準幅の値が不正です。')
  interval=interval or 0;interval_unit=interval_unit or unit
  local interval_spec=Core.interval_specs[interval_unit];assert(interval_spec,'間隔補正の単位が不正です。')
  assert(finite(interval) and interval>=interval_spec[1] and interval<=interval_spec[2]
   and (not interval_spec[3] or interval%1==0),'間隔補正の値が不正です。')
  local grid=(unit=='grid' or (interval_unit=='grid' and interval~=0)) and assert(Core.read_grid(project)) or nil
  local cursor=R.GetCursorPositionEx(project);local s=cursor
  if count==0 then count,ranges.auto_limited=Core.auto_insert_count(project,cursor,length,unit,interval,interval_unit,grid) end
  for i=0,count-1 do
   -- Markers remain points, but their next-position pitch keeps the same
   -- notional length used before interval support was added.
   local nominal_end=Core.advance(project,s,length,unit,grid)
   local e=kind=='marker' and s or nominal_end
   ranges[#ranges+1]={start=s,finish=e}
   if i<count-1 then s=Core.advance(project,nominal_end,interval,interval_unit,grid) end
  end
 elseif mode=='items' or mode=='itemspan' or mode=='itemblocks' then
  local n=R.CountSelectedMediaItems(project);assert(n>0,'アイテムを選択してください。');assert(n<=1000,'選択アイテムは1000個までにしてください。')
  for i=0,n-1 do
   local item=R.GetSelectedMediaItem(project,i)
   local s=R.GetMediaItemInfo_Value(item,'D_POSITION');local len=R.GetMediaItemInfo_Value(item,'D_LENGTH')
   assert(finite(s) and finite(len) and len>0,'長さが不正なアイテムがあります。')
   local take=R.GetActiveTake(item);local track=R.GetMediaItemTrack(item)
   ranges[#ranges+1]={start=s,finish=s+len,item_name=take and R.GetTakeName(take) or '',
    track_index=R.GetMediaTrackInfo_Value(track,'IP_TRACKNUMBER'),order=i}
  end
  table.sort(ranges,Core.item_order)
  if mode=='itemblocks' then
   ranges=Core.overlap_blocks(ranges)
   for _,g in ipairs(ranges) do
    local first=g.members[1]
    for _,r in ipairs(g.members) do if Core.item_order(r,first) then first=r end end
    g.item_name=first.item_name
   end
  elseif mode=='itemspan' then
   local finish=ranges[1].finish;for _,r in ipairs(ranges) do finish=max(finish,r.finish) end
   ranges={{start=ranges[1].start,finish=finish,item_name=ranges[1].item_name}}
  end
 else
  assert(mode=='selection','追加方法が不正です。')
  local s,e=R.GetSet_LoopTimeRange2(project,false,false,0,0,false)
  assert(e>s,'先にREAPERで時間選択を作ってください。');ranges={{start=s,finish=e}}
 end
 for _,r in ipairs(ranges) do
  if kind=='marker' then r.finish=r.start end
  assert(r.start>=0 and r.finish>=0,'間隔により挿入位置がプロジェクト先頭より前になります。')
  assert(finite(r.start) and finite(r.finish) and (kind=='marker' or r.finish>r.start),'追加する範囲が不正です。')
 end
 return ranges
end
function Core.base64(data)
 local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
 local out={}
 for i=1,#data,3 do
  local a,c,d=data:byte(i,i+2);local n=a*65536+(c or 0)*256+(d or 0)
  out[#out+1]=b:sub((n>>18)+1,(n>>18)+1)..b:sub(((n>>12)&63)+1,((n>>12)&63)+1)..(c and b:sub(((n>>6)&63)+1,((n>>6)&63)+1) or '=')..(d and b:sub((n&63)+1,(n&63)+1) or '=')
 end
 return table.concat(out)
end
function Core.unbase64(data)
 local alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
 local map={};for i=1,64 do map[alphabet:byte(i)]=i-1 end
 local out={};local n,bits=0,0
 for i=1,#data do local v=map[data:byte(i)];if v then
  n=(n<<6)|v;bits=bits+6
  if bits>=8 then bits=bits-8;out[#out+1]=string.char((n>>bits)&255);n=n&((1<<bits)-1) end
 end end
 return table.concat(out)
end
-- CP932_TABLE is generated from Python's Windows-31J codec, loaded lazily.
local CP932_TABLE='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UzCxglQwsoJVMLOCVjC0glcwtYJYMLaCWTC3glowuIJbMLmCXDC6gl0wu4JeMLyCXzC9gmAwvoJhML+CYjDAgmMwwYJkMMKCZTDDgmYwxIJnMMWCaDDGgmkwx4JqMMiCazDJgmwwyoJtMMuCbjDMgm8wzYJwMM6CcTDPgnIw0IJzMNGCdDDSgnUw04J2MNSCdzDVgngw1oJ5MNeCejDYgnsw2YJ8MNqCfTDbgn4w3IJ/MN2CgDDegoEw34KCMOCCgzDhgoQw4oKFMOOChjDkgocw5YKIMOaCiTDngoow6IKLMOmCjDDqgo0w64KOMOyCjzDtgpAw7oKRMO+CkjDwgpMw8YKbMEqBnDBLgZ0wVIGeMFWBoTBAg6IwQYOjMEKDpDBDg6UwRIOmMEWDpzBGg6gwR4OpMEiDqjBJg6swSoOsMEuDrTBMg64wTYOvME6DsDBPg7EwUIOyMFGDszBSg7QwU4O1MFSDtjBVg7cwVoO4MFeDuTBYg7owWYO7MFqDvDBbg70wXIO+MF2DvzBeg8AwX4PBMGCDwjBhg8MwYoPEMGODxTBkg8YwZYPHMGaDyDBng8kwaIPKMGmDyzBqg8wwa4PNMGyDzjBtg88wboPQMG+D0TBwg9IwcYPTMHKD1DBzg9UwdIPWMHWD1zB2g9gwd4PZMHiD2jB5g9sweoPcMHuD3TB8g94wfYPfMH6D4DCAg+EwgYPiMIKD4zCDg+QwhIPlMIWD5jCGg+cwh4PoMIiD6TCJg+owioPrMIuD7DCMg+0wjYPuMI6D7zCPg/AwkIPxMJGD8jCSg/Mwk4P0MJSD9TCVg/YwloP7MEWB/DBbgf0wUoH+MFOBMTKKhzIyi4c5MoyHpDKFh6UyhoemMoeHpzKIh6gyiYcDM2WHDTNphxQzYIcYM2OHIjNhhyMza4cmM2qHJzNkhyszbIc2M2aHOzNuh0kzX4dKM22HTTNih1EzZ4dXM2iHezN+h3wzj4d9M46HfjONh44zcoePM3OHnDNvh50zcIeeM3GHoTN1h8QzdIfNM4OHAE7qiAFOmpIDTrWOB06clghO5I8JTk+OCk7jjwtOuokNTnOVDk5elxBOoJgRTk6JFE6OihVOoZgWTqKQF07AmRhOdYsZTriVHk7ljyFOvJcmTsCVKE5M7SpOopgtToaSMU6jmDJO+Is2TqSYOE7bijlOT5I7TuWOPE6lmD9OpphCTqeYQ05UlEVOdotLTlaUTU7hk05OwYxPTlKWVU5o5VZOqJhXTuaPWE6pmFlOs4ldTuOLXk7ujF9O55ZiTqSbcU6Ql3NO+5N+TqOKgE5Ui4JOqpiFTquYhk65l4hOXJeJToiRik6tmItOlo6MTvGTjk6wmJFOXYmSTt2MlE7cjJVO5IiYTmqYmU5pmJtOsY2cTp+Ink6xmJ9OspigTrOYoU5TlqJOtJikTvCMpU7liKZOkpaoTpyLq06di6xOnoutTuCSrk66l7BOtZizTraYtk63mLpObJDATlmPwU5tkMJOvJjETrqYxk67mMdOd4vKTqGNy07uic1OuZjOTriYz06nldROZY7VTmSO1k68kddOvZjYTnSV2U7lkN1OV4HeTr6Y307AmOFOTe3jTuOR5E7fl+VOyIjtTr+Y7k68ifBOwovyToeS9k6PjPdOwZj7TkOU/E5O7QBPT+0BT+mKA09Q7QlPwpgKT8mIDU/ejA5P6ooPT5qVEE+wlBFPeIsaT++JHE/lmB1PYJMvT4yUME/EmDRPupQ2T+CXOE9MkDlPUe06T2aOPE+Xjj1PvolDT8+SRk9BkkdPyJhNT8qITk/hkk9PWo9QT7KNUU9Dl1NPzJFVT72JVk9S7VdPx5hZT12XWk/DmFtPxZhcT+yNXU/GmF5PQ5tpT86Yb0/RmHBPz5hzT8CJdU+5lXZPyZh7T82YfE/xjH9PZ46DT6SKhk/SmIhPypiKT1Tti0/hl41PmI6PT8uYkU/QmJJPU+2UT1btlk/TmJhPzJiaT1Xtm0+fi51Py4igT6CLoU+/iatPRJutT5mWrk+Ola9P8oy1T06Qtk+1l79P1pXCT1eMw0+jkcRP4onJT0Xtyk9yj81PV+3OT9eY0E/cmNFP2pjUT9WY10+tkdhP2JjaT9uY20/ZmN1P25XfT9aY4U9NkONPk5bkT92Y5U/emO5PQ4/vT+uY809vlPVPVZX2T+aY+E/ulfpPtIn+T+qY/09a7QVQ5JgGUO2YCVBxkQtQwowNUHuUD1DF4BFQ7JgSUHyTFFDhmBZQ9IwZUPOMGlDfmB5QW+0fUNiOIVDnmCJQWe0jUO2VJFBskiVQ45gmUJGMKFDgmClQ6JgqUOKYK1DPlyxQ6ZgtUGCYNlDkizlQkIxAUFjtQlBe7UNQ7phGUFztR1DvmEhQ85hJUMyIT1DOlVBQ8phVUPGYVlD1mFpQ9JhcUOKSZVCSjGxQ9phwUF3tclDDjnRQpJF1UOOSdlD0i3hQ95h9UFWLgFD4mIVQ+piNUFSWkVCGjJRQX+2YUFCOmVD1lJpQ+ZisUMONrVBil7JQ/JizUEKZtFD7mLVQwo23UJ2PvlBYjMJQQ5nFUM2LyVBAmcpQQZnNUK2Tz1CckdFQoYvVUGyW1lBEmdhQYe3aULuX3lBFmeNQSJnlUEaZ51Btke1QR5nuUEmZ9FBg7fVQS5n5UEqZ+1DGlQBRVosBUU2ZAlFOmQRRrYkJUUyZElHyjhRRUZkVUVCZFlFPmRhR1JgaUVKZH1GejyFRU5kqUUSXMlHXljdRVZk6UVSZO1FXmTxRVpk/UViZQFFZmUFR8ohDUbOMRFFajEVRW49GUZuSR1Gii0hR5pBJUfWMSlFi7UtRjo1MUVuZTVHGlk5RZZNQUZmOUlFamVRRXJlaUX2TXFGVimJRXZlkUWPtZVH8k2hRU5FpUV+ZalFgmWtRqpRsUfaMbVFamG5RYZlxUaSLdVG6lXZRtJF3Ue+LeFFUk3xRk4yAUWKZglFjmYVR4JOGUX6JiVFmmYpR+42MUWWZjVHEjY9RZ5mQUezjkVFomZJRYJaTUWmZlVFqmZZRa5mXUeePmVHKjp1RZO2gUaWKolFumaRRbJmlUbuWplFtmahReZWpUW+ZqlFwmatRcZmsUX6TsFF1mbFRc5myUXSZs1FymbRR4Y21UXaZtlHolrdR4pe9UXeZvlFl7cRRppDFUXiZxlF5j8lReZnLUZySzFG9l81RgJPWUcOZ21F6mdxRo+rdUcOL4FF7meFRfZbmUYiP51H6kelRfZnqUeKT7FFm7e1RfpnwUYCZ8VFNivVRgZn2UaWL+FHKk/lRmon6UW+P/VGflP5RgpkAUoGTA1JukARSg5kGUqqVB1LYkAhSoIoKUqeKC1KEmQ5ShpkRUlmMFFKFmRVSZ+0XUvGXHVKJjyRSu5QlUsqVJ1KHmSlSmJcqUoiZLlKJmTBSnpMzUoqZNlKnkDdS/I04UpSMOVKLmTpSaI47Uo+NQ1LkkkRSjZlHUqWRSlLtjUtSjplMUo+ZTVJPkU9SjJlUUpGZVlJVlltShI1eUpCZY1KVjGRS3I1lUo2UaVKUmWpSkplvUpuVcFLoj3FSm5lyUoSKc1KVmXRSk5l1Um6RfVKXmX9SlpmDUmOKh1KAjIhSnJmJUquXjVKYmZFSnZmSUpqZlFKZmZtSzZecUmjtn1L3jKBSwYmjUvKXplJp7alSlY+qUneTq1KFjaxSoJmtUqGZr1Jb7rFS45e0UkqYtVKjmblS+Iy8UqKZvlJOisBSau3BUqSZw1J1lsVSupLHUkWXyVLXlc1SpZnSUtPo1VKuk9dSppnYUqiK2VKxlttSa+3dUp+P3lKnmd9S5ZXgUquZ4lKokONSqJnkUs6L5lKpmedSqYryUk2M81KsmfVSrZn4Uq6Z+VKvmfpS2Y7+UvmM/1LclgBTbO0BU+aWAlP1kwVT75UGU7CZB1Nt7QhTsZkNU7OZD1O1mRBTtJkVU7aZFlO7iRdTa5YZU/qNGlO3mR1TeJEgU6CPIVOniyNTuJkkU27tKlPZlC9TuZkxU7qZM1O7mThTvJk5U0OVOlPmiztT44g/U72TQFO9mUFTXI9DU+eQRVO/mUZTvplHU6GPSFPfjElTwZlKU7yUTVPCmVFT2pRSU7KRU1PskVRTpotXU+yTWFNQklpTjpRcU22WXlPEmWBT6JBmU1SMaVPFmW5TxplvU0uJcFPziHFT64pyU2/tc1OmkXRTcIt1U5GXd1PJmXhTtYl7U8iZf1Ooi4JTypmEU++Wk1Nw7ZZTy5mYU9CXmlP6jJ9TtIygU8yZpVPOmaZTzZmoU36QqVNYia1TfYmuU8+ZsFPQmbJTce2zU7WMtlPRmbtTjovCU1GOw1PSmchTlJbJU7ONylN5i8tTRpfMU2+RzVO9lM5T+47UU2aP1lPmjtdT847ZU5aP21O+lN1Tcu3fU9WZ4VNiieJTcJHjU/uM5FPDjOVT5YvoU9mZ6VNAkupT/JHrU6mL7FOij+1T2pnuU9iZ71PCifBT5JHxU7aO8lNqjvNTRYn2U5CK91OGjfhTaY76U9uZAVTcmQNUaIsEVGWKCFSHjQlUZ4sKVN2SC1REiQxUr5MNVLyWDlRAjQ9UmZcQVGaTEVT8jBtUTowdVOWZH1ThiyBUaZYmVNuUKVTkmStU3IosVN+ZLVTgmS5U4pk2VOOZOFR6izlUgZA7VKuVPFThmT1U3Zk+VOGMQFTemUJUQ5hGVPCVSFTmkklU4IxKVJCNTlTmmVFU25NfVOqZaFT8jmpU9I5wVO2ZcVTrmXNUoZZ1VOiZdlTxmXdU7Jl7VO+ZfFTEjH1UvZaAVPCZhFTymYZU9JmKVHXti1TujYxUYZiOVOmZj1TnmZBU85mSVO6ZnFR07aJU9pmkVEKapVT4mahU/JmpVHbtq1RAmqxU+ZmvVF2aslTnjbNUUIq4VPeZvFREmr1U9Ii+VEOawFSjiMFUaZXCVEGaxFT6mcdU9ZnIVPuZyVTGjdhURZrhVPWI4lROmuVURprmVEea6FSjj+lUiZbtVEya7lRLmvJUTpP6VE2a/VRKmv9Ud+0EVVOJBlW0jQdVT5APVUiaEFWCkxRVSZoWVaCILlVTmi9VQpcxVaWPM1VZmjhVWJo5VU+aPlXBkUBVUJpEVe2RRVVVmkZVpI9MVVKaT1XillNVW4xWVVaaV1VXmlxVVJpdVVqaY1VRmntVYJp8VWWaflVhmoBVXJqDVWaahFVQkYZVeO2HVWiaiVVBjYpVXpqLVZ2SmFVimplVW5qaVauKnFXsip1VhYqeVWOan1VfmqdVloyoVWmaqVVnmqpVcpGrVWmLrFWqi65VZJqwVfKLtlVjicRVbZrFVWuax1WlmtRVcJraVWqa3FVumt9VbJrjVWuO5FVvmvdVcpr5VXea/VV1mv5VdJoGVlGSCVbDiRRWcZoWVnOaF1amjxhWUokbVnaaKVbciS9WgpoxVvqPMlZ9mjRWe5o2VnyaOFZ+mkJWXIlMVliRTlZ4mlBWeZpbVpqKZFaBmmhW7YpqVoSaa1aAmmxWg5p0VqyVeFbTk3pWtpSAVoaahlaFmodWZIqKVoeaj1aKmpRWiZqgVoiaolZYlKVWi5quVoyatFaOmrZWjZq8VpCawFaTmsFWkZrCVo+aw1aSmshWlJrOVpWa0VaWmtNWl5rXVpia2FZkmdpW+o7bVmyO3lbxieBW9ojjVmOS7laZmvBWoo3yVs2I81Z9kPlWmpr6VsWM/VaRjf9WnJoAV5uaA1felQRXnZoIV5+aCVeemgtXoJoNV6GaD1eXjBJXgIkTV6KaFlekmhhXo5ocV6aaH1d5kyZXp5onV7OIKFfdjS1XXIwwV26SN1eomjhXqZo7V6uaQFesmkJX4o1HV8+LSldWlk5XqppPV62aUFe/jVFXQo1ZV3ntYVexmmRXo41lV3rtZldSkmlXrppqV9iSf1eymoJXgpCIV7CaiVezmotXXoyTV7SaoFe1mqJXQ42jV1+KpFe3mqpXuJqsV3vtsFe5mrNXtprAV6+aw1e6msZXu5rHV33tyFd87ctXhJbOV+mP0le9mtNXvprUV7ya1lfAmtxXV5TfV+aI4Fd1leNXwZr0V/uP91e3jvlXfJT6V+6K/FfpjQBYeJYCWLCTBViYjAZYzZEKWL+aC1jCmhVYwpEZWMOaHVjEmiFYxpokWOeSKlisii9Yn+owWIGJMVjxlTRY6o81WGeTOljkjT1YzJpAWLuVQVjbl0pY8olLWMiaUVhZkVJYy5pUWIOTV1hok1hYhJNZWLeUWljLkl5Yx41iWMeaaViWiWtYVZNwWMmacljFmnVYb5B5WM2aflhtj4NYq4uFWM6ak1jmlZdYnZGcWMSSnliB7Z9Y0JqoWG6Wq1jRmq5Y1pqyWILts1itlbhY1Zq5WM+auljSmrtY1Jq+WKSNwVjHlcVY15rHWGSSyljzicxY64/RWNma01jYmtVYiI3XWNqa2FjcmtlY25rcWN6a3ljTmt9Y4JrkWN+a5VjdmutYbY7sWHCQ7lhzke9Y4ZrwWLqQ8VjriPJYhJT3WNmS+VjjmvpY4pr7WOSa/Fjlmv1Y5poCWeeaCVnPlQpZ6JoLWYPtD1nEiRBZ6ZoVWVuXFllPihhZx5kZWWePGlm9kRtZ6pocWemWIlmyliVZ7JonWeWRKVlWkypZvpErWXaVLFntmi1Z7pouWZuJMVm4jjJZ75o3Wc6IOFnwmj5Z8ZpEWYKJR1nvikhZ3pNJWfKVTln1mk9ZdJFQWfSaUVlfjFNZhO1UWXqWVVnzmldZhZNYWfeaWln2mltZhe1dWYbtYFn5mmJZ+JpjWYftZVmciWdZ+ppoWaePaVn8mmpZRJJsWfuablmxlXNZl490WXqTeFlAm31ZRI2BWUGbgllAlINZ3JSEWc+WillElI1ZSpuTWVeLlllkl5lZrZabWaqbnVlCm6NZRZukWYjtpVnDkahZV5asWWmTsllGm7lZhZa6WYntu1nIjb5ZqI/GWUebyVlvjstZbo7QWbeI0VnGjNNZqZDUWc+I2VlLm9pZTJvcWUmb5VlXieZZrYroWUib6lnDlutZUJX2WaaI+1n3iP9ZcI4BWtCIA1qhiAlaUZsRWk+bGFq6lhpaUpscWlCbH1pOmyBaUJAlWk2bKVrYlS9a4ow1WlabNlpXmzxaqY9AWlObQVpLmEZaa5RJWlWbWlqljWJaWJtmWneValpZm2xaVJt/WrmWklp9lJpaWpubWlGVvFpbm71aX5u+WlybwVrFicJaXpvJWrmOy1pdm8xamYzQWmub1lpkm9daYZvhWoSS41pgm+ZaYpvpWmOb+lplm/taZpsJW/CKC1tomwxbZ5sWW2mbIlvsjypbbJssW9qSMFtkiTJbaps2W22bPltum0BbcZtDW2+bRVtwm1BbcY5RW3KbVFtFjVVbc5tWW4rtV1uajlhbtpFaW3SbW1t1m1xbeY5dW0aNX1vQlmNbR4tkW8eMZVt2m2Zbd4ppW3eba1u3kXBbeJtxW6Gbc1t5m3Vbept4W3ubelt9m4BbfpuDW4CbhVvukYdbRomIW+eOiVvAiItbdpGMW66KjVuzjo9bR42VW4aTl1tAj5hbr4qZW4iSmlvokptbtoicW1iLnVvzlZ9bwI6iW3GLo1vpkKRbuo6lW0eXpluBm65be4uwW8mNs1tRirRbg4m1W6qPtlvGibhbgpu5W2WXv1toj8Bbi+3CW+KOw1uDm8Rb8YrFW9CTxlunlsdbhJvJW4WbzFt4ldBbh5vSW6aK01v1i9RbhpvYW43t21uwit1bUZDeW4ub31tAjuFbx4niW4qb5FuIm+VbjJvmW4mb51tKlOhby57pW1KQ61uNm+xbju3uW76X8FuOm/NbkJv1W56S9luPm/hboZD6W5uO/lvOkf9b9Y4BXJWVAlzqkARcy44FXJGbBlyrjwdckpsIXJObCVzRiApcuJELXHGQDVyUmw5csZMPXKyPEVytjxNclZsWXOuQGlyujx5cj+0gXJabIlyXmyRc3pYoXJibLVzEizFcQY84XJmbOVyamzpc2o47XEuQPFzykz1cc5A+XPaUP1xBlEBcx4tBXJubRVyPi0ZcnJtIXPyLSlzNk0tcrolNXHKOTlydm09coJtQXJ+bUVz7i1NcnptVXFeTXlyukWBcapNhXMaOZFx3kWVcmpdsXKKbblyjm29c1JNxXFKOdlylm3lcppuMXKebkFzyipFcqJuUXKmboVyqiaZckO2oXFqRqVziiqtcq5usXKaWsVzQkbNceIq2XK2bt1yvm7hc3Yq6XJHtu1ysm7xcrpu+XLGbxVywm8dcspvZXLOb4Fy7k+FcrIvoXOOJ6Vy0m+pcuZvtXLeb71z1lfBc9JX1XJLt9lyHk/pctpv7XHOP/Vy1mwddkpALXbqbDl3ojRFdwJsUXcGbFV27mxZdUooXXbybGF3FmxldxJsaXcObG12/mx9dvpsiXcKbJ12T7Sld9pVCXZbtS13Jm0xdxptOXcibUF2Sl1Jdx5tTXZTtXF29m2ldk5BsXcqbbV2X7W9dtY1zXcubdl3Mm4Jdz5uEXc6bh13Nm4tdiJOMXbibkF3Vm51d0ZuiXdCbrF3Sm65d05u3XdabuF2Y7bldme26XeSXvF3Xm71d1JvJXdibzF3eis1d2ZvQXZrt0l3bm9Nd2pvWXdyb213dm91d7JDeXUKP4V2Ej+Ndg5HlXUiN5l22jeddSY3oXZCL613em+5dt43xXciM8l3fm/NdpJb0XWKU9V3gm/ddSo37XaqK/V1Gkv5d0IsCXnOOA156lQZev5QLXuGbDF7zihFe5JsWXp+SGV7jmxpe4psbXuWbHV7pkiVeg5ArXnSOLV7IkC9e0ZEwXkGLM16gkjZe5ps3XuebOF7tjz1eWJZAXuqbQ17pm0Re6JtFXp2VR17xm0xeeZZOXuubVF7tm1Vei5ZXXuybX17um2FeppRiXu+bY168lWRe8JtyXrGKc169lXReTpR1XvKbdl7zm3heS415XrKKel70m3tetox8XmOXfV5Il35e9Ip/XvabgV6hkoNeTI2EXq+Ph17dlIpesI+PXpiPlV7qkpZe95WXXliTml5NjZxee5WgXvebpl54k6dewI2rXsmMrV7rkrVewYi2Xo6Pt15OjbheZpfBXvibwl75m8NecJTIXvqbyV71l8peTJjPXvyb0F77m9NeZorWXkCc2l5DnNteRJzdXkKc315fleBesY/hXkac4l5FnONeQZzoXkec6V5InOxeSZzwXkyc8V5KnPNeS5z0Xk2c9l6Eifde7JL4Xk6c+l6ajPte9In8XlWU/l5PnP9e+ZMBX9mVA19QnARfTZgJX1GcCl++lQtfVJwMX5+YDV+vmA9fro4QX/OTEV9VnBNffIsUX6KSFV/4iBZfVpwXX6SVGF9PjRtfb5IfX+2SIV+b7SVf7ZYmX7eMJ1/KjClfV5wtX1icL19enDFf4440X5ztNV+jkjdfrYs4X1mcPF9KlT5fZZJBX1qcRV9L7UhfW5xKX66LTF9cnE5fXZxRX1+cU1+Wk1ZfYJxXX2GcWV9inFxfU5xdX1KcYV9jnGJfYIxmX0aVZ1+d7Wlfyo1qX1aVa1+kkmxfapVtX2SccF+yj3FfZYlzX2Wcd19mnHlf8JZ8X96Uf19pnIBfnYmBX6qQgl9onINfZ5yEX2GMhV/SkYdfbZyIX2ucil9qnItfpZeMX+OMkF+Zj5FfbJySX2uTk19dj5dfvpOYX3CcmV9vnJ5fbpygX3GcoV/kjKhfcpypX5yVql96j61fc5yuX/eUs1+/k7RfpZK3X57tuV9Pk7xfdJy9X0qLw19TkMVfS5XMX/WKzV9FlNZfdZzXX3WO2F9ZltlfWpbcX56J3V96nN5fn+3gX4mS5F93nOtf9YnwX6uc8V95nPVfT5T4X3ic+192nP1fmo3/X3ycDmCDnA9giZwQYIGcEmB7kxVghpwWYHyVGWCAnBtghZwcYOWXHWB2jiBg05EhYH2cJWB9iyZgiJwnYKuQKGCFiSlggpwqYPaJK2CHnC9gr4sxYIScOmCKnEFgjJxCYJacQ2CUnEZgkZxKYJCcS2D2l01gkpxQYLCLUmBQjVVgmo9ZYJmcWmCLnF1goO1fYI+cYGB+nGJg+IljYJOcZGCVnGVgcJJoYKaNaWC2iWpgjZxrYJicbGCXnG1gsYtvYKeRcGCGinVgYox3YI6cgWCanINgnZyEYJ+chWCh7Ylgu46KYKLti2ClnIxg7pKNYJuckmCjnJRg94mWYKGcl2CinJpgnpybYKCcn2DljKBgSZejYLOKpmB4iadgpJypYFmUqmCriLJg35SzYHuctGCqnLVgrpy2YOOWuGCnnLxgiZO9YKycxWDuj8ZgrZzHYNWT0WBmmNNgqZzVYKTt2GCvnNpgm43cYMmQ3mCj7d9g0ojgYKic4WCmnONgeZHnYJyc6GBTjvBgxJHxYLuc8mCm7fNgepH0YLac9mCznPdgtJz5YOSO+mC3nPtgupwAYbWcAWFEjwNhuJwGYbKcCGH6lglh+ZYNYbycDmG9nA9h04gRYaftFWGxnBph8IsbYaSIH2G0iiBhpe0hYbmcJ2HBnChhwJwsYcWcMGGp7TRhxpw3YajtPGHEnD1hx5w+Yb+cP2HDnEJhyJxEYcmcR2G+nEhhnI5KYcKcS2HUkUxhUY1NYbCcTmFUkFNh1pxVYeeVWGHMnFlhzZxaYc6cXWHVnF9h1JxiYZ2WY2G1imVh0pxnYWSMaGFTimthz5xuYbaXb2HRnHBh1IhxYdOcc2HKnHRh0Jx1YdecdmFjjHdhy5x+YXyXgmFKl4dh2pyKYd6cjmGekZBh95eRYd+clGHcnJZh2ZyYYartmWHYnJph3ZykYa6Vp2Gyk6lhZYyrYeCcrGHbnK5h4ZyyYZuMtmGvibph6Zy+YbaKw2HnnMZh6JzHYaeNyGHmnMlh5JzKYeOcy2HqnMxh4pzNYeyc0GH5ieNh7pzmYe2c8mGmkvRh8Zz2Ye+c92HlnPhhnIz6YfCc/GH0nP1h85z+YfWc/2HynABi9pwIYvecCWL4nApi6JUMYvqcDWL5nA5iXo8QYqyQEWLkiRJi+okTYqvtFGL7nBZivYgaYsqQG2L8nB1iweYeYkCdH2KBjCFiQZ0mYu2QKmJCnS5iQ50vYlmLMGJEnTJiRZ0zYkadNGLVkThiy4w7Yt+WP2JblkBiio9BYkedR2LukEhiu+dJYuCUS2Lojk1iy41OYkidU2LFkVVipZVYYu+RW2JLnV5iSZ1gYkydY2JKnWhiTZ1uYq+VcWK1iHZifZV5YuGUfGJOnX5iUZ1/YrOPgGJai4JiT52DYladhGK0j4liUJ2KYmOUkWJ9l5JiUp2TYlOdlGJXnZViipOWYlSdl2JSjZhi3JCbYmWdnGKylJ5i8JGmYqztq2LilKxiq52xYviVtWLvkrlilZa7YlqdvGKfib1iipLCYmOdxWJTksZiXZ3HYmSdyGJfncliZp3KYmKdzGJhnc1ij5TPYlud0GL7idFiWZ3SYpGL02LxkdRiVZ3XYlid2GJTjdli2ZDbYrWP3GJgnd1icZTgYpKL4WJniuxih4rtYkCQ7mJone9ibZ3xYmmd82KdjPVibp32YkGO92KJjf5iRY//YlydAWOdjgJja50HY3eOCGNsnQljwogMY2edEWOnkhljk4sfY7KLJ2NqnShjpYgrY8GNL2NVkDpj8JI9Y9KUPmNwnT9jfZFJY6iRTGNKjk1jcZ1PY3OdUGNvnVVj35VXY7uSXGN7kWdj+ZVoY8yOaWOAnWtjfp1uY5iQcmOejHZjeJ13Y7ePemPmk3tjUJSAY3adg2N8kYhj9o6JY3udjGO2j45jdZ2PY3qdkmNylJZjdJ2YY0CMm2N8ip9jfJ2gY6mXoWPMjaJjVJKjY3mdpWPakKdjVI2oY4SQqWOGiapjW5GrY3edrGNki7JjZoy0Y82StWN9nbtjfpG+Y4GdwGODncNjtZHEY4mdxmOEncljhp3PY2CV0GPxktJjh53WY0uX2mNnl9tjt4rhY6yI42OFneljgp3uY/aK9GOHifVjre32Y4id+mNolwZkjJ0NZLmRD2STnRNkjZ0WZIqdF2SRnRxkcp0mZI6dKGSSnSxkwJQtZIuTNGSLnTZkj506ZGeMPmTvjUJk25BOZJedWGRFk2Bkru1nZJSdaWSAlm9klZ12ZJadeGTMlnpkoJCDZIKMiGSdnZJkVI6TZJqdlWSZnZpkUZSdZK/tnmSzk6RkUJOlZJudqWScnatkj5WtZGSUrmRCjrBk75CyZG+WuWRoirtko528ZJ6dwWRpl8JkpZ3FZKGdx2Sinc1kgJHOZLDt0mSgndRkXp3YZKSd2mSfneBkqZ3hZKqd4mRGk+NkrJ3mZEOO52SnnexkW4vvZK2d8WSmnfJksZ30ZLCd9mSvnfpksp39ZLSd/mTvjwBls50FZbedGGW1nRxltp0dZZCdI2W5nSRluJ0qZZidK2W6nSxlrp0vZXiONGW7nTVlvJ02Zb6dN2W9nThlv505ZfyJO2VVjT5l+pU/Za2QRWXMjEhlwZ1NZcSdTmWx7U9lcZVRZX6LVWXDnVZlwp1XZXOUWGXFnVlls4tdZcedXmXGnWJluIpjZVWOZmXWk2xlaIxwZZSQcmXInXRlrpB1ZUeTd2V+lXhlyZ2CZcqdg2XLnYdltpWIZXybiWXEkIxla5WOZdaNkGXjlJFlwZSXZWyTmWW/l5tlzZ2cZc6On2XOnaFltIikZdKLpWXLkKdlgJWrZc+drGVhjq1lZpKvZXqOsGVWkLdl0J25ZfuVvGWXib1le47BZdOdw2XRncRl1J3FZbeXxmXSnctl+ZDMZdWdz2WwkdJl1p3XZfiK2WXYndtl153gZdmd4WXaneJl+YrlZfqT5mVVkudljIvoZXyO6WWBkexle4/tZa6I8WXbnfploIn7Zd+dAGay7QJmVo0DZt6dBmapjQdmuI8JZrXtCmbdnQxmuY8OZr6WD2aojRNm1YgUZsyQFWaz7Rxm5J0eZrftH2avkCBmZokkZrjtJWZ0jydmhpYoZvCNLWa6jy5mtu0vZqWQMWZH7TRm4501ZuGdNmbinTtmtO08ZouSP2ZFnkFm6J1CZp6OQ2ZXjURm5p1JZuedS2ZXkE9m5Z1SZk6OV2a67Vlmu+1dZuqdXmbpnV9m7p1iZu+dZGbrnWVmue1mZkGKZ2bsnWhm7Z1pZtOUbmaBlW9maYxwZvCdc2a97XRmsJB2ZruPemZxkoFmxYuDZvGdhGb1nYdmyYmIZvKdiWb0nY5m852RZouPlmZnkpdmw4iYZvadmWa+7Z1m952gZr/tomaokqZm75erZmKOrmbplbJmwO20ZlyWuGZBnrlm+Z28Zvydvmb7nb9mwe3BZvidxGZAnsdm3JPJZvqd1mZCntlmjI/aZkOe3GZql91mmJTgZkSe5mZGnulmR57wZkie8mbIi/NmZ4n0ZliN9WZJnvdmSp74ZpGP+WaCkfpmwu37Zkrt/GbWmf1mXZH+ZlyR/2bWkQBnxY0DZ/CYCGeOjAlnTJcLZ/yVDWeelQ5nw+0PZ0ueFGfxjRVnvZIWZ0yeF2dOmBtnXZYdZ6mSHmdNnh9n+oomZ06eJ2dPnihn2JYqZ6KWK2eWlixne5YtZ0SOLmdRnjFn6Y40Z3CWNmdTnjdnVp44Z1WeOmf3ij1ngIs/Z1KeQWdUnkZnV55JZ5mQTmebl09nx4hQZ96NUWe6kVNn245WZ/GPWWdanlxnbZNeZ1ieX2epkWBnWZ5hZ/CPYmfblmNnW55kZ1yeZWeIl2Znxe1qZ2GebWdZjW9ndJRwZ16ecWeMk3Jn3J1zZ+CddWdui3dnZpR8Z2Cefme8j39nwpSFZ2aeh2f4lIlnXZ6LZ2OejGdinpBnzZCVZ42Wl2fRl5pnh5acZ8qJnWd9jqBnZ5ihZ2WeomeVkKZnZJ6pZ1+er2fNjLNna560Z2metmfLibdnZ564Z22euWdznrtnxu3AZ8jtwWfGkcRnv5XGZ3WeymdBlc5ndJ7PZ5CU0GdeltFnuYrTZ/WQ1Gdfj9hn0ZLaZ02X3Wdwnt5nb57iZ3Ge5Gdunudndp7pZ2ye7Gdqnu5ncp7vZ2ie8WeMkvNn9pb0Z8SO9WfyjftnuI3+Z4+W/2dgigFoye0CaMySA2jIkwRoaIkTaPCQFmiykBdoSYweaHieIWhajSJonIopaHqeKmiUiitogZ4yaH2eNGjxkDhoaoo5aKqNPGhpij1ozY1AaHueQWiFjEJoaoxDaI2TRGjK7UZoeZ5IaMSITWh8nk5ofp5QaMuLUWhLjFJox+1TaLqKVGhqi1logp5caPeNXWiRll9oVo5jaIOeZ2hPlXRoj552aLGJd2iEnn5olZ5/aIWegWjAl4NojJ6FaH6UjWiUno9oh56TaLKIlGiJnpdoW42baIuenWiKnp9ohp6gaJGeomi9j6Zo65qnaOaMqGicl61oiJ6vaPKSsGhCirFoq42zaICetWiQnrZogYq5aI6eumiSnrxojpPEaPyKxmiwnshoSO3JaMeWymiXnsto+4rNaJ6ez2jL7dJoX5bUaJ+e1WihntdopZ7YaJme2mhJkt9oj5PgaKme4WicnuNopp7naKCe7mhYkO9oqp7yaLGQ+Wionvpou4oAaW+YAWmWngRppJ4FadaICGmYngtpuJYMaZ2eDWlBkA5pxZIPaZOeEmmjnhlpmpAaaa2eG2mRihxpn4whaa+eImmaniNprp4laaeeJmmbnihpq54qaayeMGm9njRpzJM2aaKeOWm5nj1pu54/adaSSmlrl1NplpVUabaeVWnIkVlpvJ5aaV6RXGmznl1pwJ5eab+eYGntk2Fpvp5iaeiTaGnN7Wppwp5rabWebWnGi25puJ5vaXyPc2mAlHRpup51acmLd2mynnhptJ55abGefGlPmH1peYp+abeegWnBnoJpVIqKaeWNjml8iZFp0p6UaVCYlWnVnphpz+2baVmQnGnUnqBp056nadCermnEnrFp4Z6yacOetGnWnrtpzp6+acmev2nGnsFpx57Dac+ex2mg6sppzJ7LaVyNzGnGks1phJHOacqe0GnFntNpyJ7YaWyX2WmKlt1pzZ7eadee4mnQ7edp357oadie62nlnu1p457yad6e+WndnvtpzpL9aYWR/2nbngJq2Z4FauCeCmrmngtq85QMauyeEmrnnhNq6p4UauSeF2qUkhlqV5UbatqeHmrinh9qvo8has2WImr2niNq6Z4paqCMKmqhiStqfoouatGeMGrR7TVqv482au6eOGr1njlq9446apKKPWpNkkRq655GatPtR2rwnkhq9J5LarSLWGpri1lq8p5fakCLYWrJk2Jq8Z5mavOea2rS7XJq7Z5zatTteGrvnn5q1e1/aoCKgGpokoRq+p6NaviejmrnjJBq956XakCfnGp3nqBq+Z6iavueo2r8nqpqS5+sakefrmqNnrNqRp+4akWfu2pCn8Fq6J7CakSfw2pDn9FqSZ/TakWY2mpMn9tq+Yveakif32pKn+Jq1u3katft6GqllOpqTZ/6alGf+2pOnwRrk5cFa0+fCmvcnhJrUp8Wa1OfHWtUiR9rVZ8ga4eMIWufjiNr04sna6KJMmt+lzdrV584a1afOWtZnzprXIs9a9SLPmu8ikNrXJ9Ha1ufSWtdn0xrzIlOa1aSUGten1NrvYpUa2CfWWtfn1trYZ9fa2KfYWtjn2Jrfo5ja7OQZGufjWZrkJVpa+CVamtjmG9rlY5za86NdGvwl3hrZJ95a2Wfe2uAjn9rZp+Aa2efg2tpn4RraJ+Ga3eWiWt9j4pr6o6La2OOjWtqn5VrbJ+Wa0KQmGtrn55rbZ+ka26fqmtvn6trcJ+va3GfsWtzn7Jrcp+za3SftGujibVraZK3a3WfumtFjrtra4q8a3afv2thk8BryprFa0KLxmt3n8treJ/Na+qVzmuIltJrxZPTa3mf1GvklNZr2O3Ya/mU22vRlt9rep/ra3yf7Gt7n+9rfp/za32fCGyBnw9sgY4RbK+WE2yCnxRsg58XbEOLG2yEnyNshp8kbIWfNGyFkDdsWJU4bGmJPmzDlD9s2e1AbPOSQWxgj0JsgYtObMSUUGysjlVsiJ9XbL6KWmyYiVxs2u1dbPCTXmyHn19sXY1gbHKSYmyJn2hskZ9qbIqfb2zc7XBsv5FybIKLc2ySn3psiIx9bESLfmyQn4Fsjp+CbIufg2yAl4Zs2+2IbL6SjGzXk41sjJ+QbJSfkmyTn5NsQoyWbKuJmWy5jZpsjZ+bbI+foWx2lqJs8pGrbJeWrmycn7FsnZ+zbM2JuGymlbls+5a6bJ+fu2yhjrxswI+9bJifvmyen79siInBbLWLxGyVn8Vsmp/JbPKQymyRlMxs5ZTTbJef1WxAltdsmZ/ZbKKf2mzd7dtsoJ/dbJuf4WxBluJsZ5TjbIOL5WxEk+hsjZLqbKOf72yhn/Bs15HxbJaf82xqiQRt3u0LbW2XDG2unxJtrZ8XbfSQGW2qnxttjJcebbSTH22knyVtw5IpbWuJKm1ejSttp58ybUaPM22snzVtq582baafOG2pnzttiIo9baifPm1olEFtrJdEbfKPRW3zkFlttJ9abbKfXG1slWNtr59kbbGfZm1ZiWltX41qbVGYbG1cim5tgpVvbeDtdG2Bl3dtQ4p4bVqQeW2zn4VtuJ+Hbd/tiG3Bj4xtT5eObbWfk22wn5Vttp+WbeHtmW3cl5ttk5OcbcCTrG3i7a9tVYqybXSJ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B43U5giNoZEKjdPmC43kig2N1uYPjdXmEI3X5hKNk+4TjdnmFI3b5haN3OZkjdSQZo3NjmeN3eZrjXGKbY3e5nCNlpFxjd/mc43g5nSNi5V2jZTud41Oi4GN4eaFjbSSio16iZmN4uajje+OqI2WkLONq5G6jeXmvo3k5sKN4+bLjevmzI3p5s+N5ubWjejm2o3n5tuN6ubdjZeL343u5uGN1ZDjje/m6I3XjOqN7Obrje3m741ImPONtZL1jUiR/I3w5v+N8+YIjvHmCY7y5gqOeJcPjqWTEI725h2O9OYejvXmH4735iqOSOcwjvrmNI775jWO+eZCjvjmRI77kkeOQOdIjkTnSY5B50qO/OZMjkLnUI5D51WOSudZjkXnX47WkGCOR+djjknnZI5G53KOTOd0jlKPdo5L53yOTeeBjk7nhI5R54WOUOeHjk/nio5T54uOUueNjvSWkY5V55OOVOeUjlbnmY5X56GOWeeqjljnq45nkKyOWuevjuuLsI5b57GOXee+jl7nxY5f58aOXOfIjmDnyo7UjsuOYefMjk+LzY5SjM+Olu7SjqyM245i59+O7pPijl2T445j5+uOZuf4jrKO+45l5/yOZOf9jnmM/o5n5wOPcooFj2nnCY/ajQqPaOcMj3HnEo9r5xOPbecUj+OVFY9q5xmPbOcbj3DnHI9u5x2PUIsfj2/nJo9y5ymPeZQqj9aXL49TjzOPc+c4j0GXOY915zuPdOc+j3jnP49gl0KPd+dEj42KRY9250aPe+dJj3rnTI95502PUZNOj3znV49951yPfudfj4yNYY9EjGKPgOdjj4HnZI+C55uPaJCcj4Pnno+rjp+PhOejj4Xnp4+fmaiPnpmtj4bnro+Q46+Ph+ewj0OSsY9KkLKPX5S3j4jnuo/TlbuP0pK8j56Nv49IksKPSYnEj5iWxY92kM6PfYzRj9+L1I/UldqPiefij4vn5Y+K5+aP3onpj/ST6o+M5+uPl5Ttj1KT74+N5/CPcY/0j4/n94/AlviPnuf5j5Hn+o+S5/2Px5IAkN6RAZCXkQOQppMFkJDnBpB0iwuQmecNkJbnDpCj5w+Qp5MQkICSEZCT5xOQ/JIUkHKTFZCU5xaQmOcXkICQGZCHlBqQypIdkMCQHpCX5x+QrJEgkKKRIZCV5yKQp4gjkEGYJ5Ca5y6Q35ExkFSPMpBpkDWQnOc2kJvnOJDtiDmQnec8kE6VPpCl50GQ2ZNCkIuQRZB4kkeQ9otJkKTnSpBWl0uQXolNkNWVTpDfiU+Qn+dQkKDnUZCh51KQoudTkLmTVJBCklWQ4YhWkKbnWJCn51mQoepckLuRXpCo52CQk4lhkGuRY5CtjGWQeZdnkJnuaJCp52mQS5NtkJiRbpDVjm+QqudykK3ndZCFj3aQq+d3kEqReJBJkXqQ4oh8kMmXfZCv53+Q8JSAkLHngZCw54KQrueDkITihJDSioeQjueJkLPnipCy54+QtOeRkFeXo5Dfk6aQTZaokLXnqpDXjq+QtuexkLfntZC457iQQJPBkOiIypB4jc6QWZjbkLzn3pCa7uGQU4zikLnn5JC65+iQlJXtkHOK9ZBYl/eQvYv9kHOTApG95xKRvucVkZzuGZG/5yeRne4tkUGTMJHB5zKRwOdJkdGTSpHC50uRVY9Mkd6OTZF6lE6RkZJSkfCOVJGMkFaRw+dYkcTnYpF8kGORxedlkcbnaZHH52qRj5dskVaPcpHJ53ORyOd1kXmNd5GTjXiRX46Ckcznh5GGj4mRy+eLkcrnjZHnkZCR7YySkcGQl5GulJyRWI+ikc3npJHdj6qR0Oerkc7nr5HP57SR0ue1kdHnuJH4j7qR0+fAkdTnwZHV58aRzpTHkdGNyJHfjsmR1ufLkdfnzJGil82RZI/OkeyWz5HKl9CR2OfRkeCL1pHZ59eRn+7YkUKT2pGe7tuR3OfckZiK3ZFqkN6RoO7fkdrn4ZHb5+OR3pLkkaPu5ZGk7uaRdJbnkfqL7ZGh7u6Rou71kd7n9pHf5/yR3ef/keHnBpKl7gqSp+4Nkt2TDpJiihCSpu4RkuXnFJLi5xWS5OcekuDnKZJu6CyS4+c0kumXN5LYjDmSru46kqjuPJKq7j+S7edAkqnuRJJTk0WS6OdIkuvnSZLp50uS7udOkqvuUJLv51GSre5XkufnWZKs7lqS9OdbkpSJXpLm52KSq5RkkurnZpLej2eSr+5xknqNd5Kx7niSsu5+kmeWgJLii4OSZY+FkrqTiJJD7ZGSTJGTkvLnlZLs55aS8eeYksGWmpK2kpuS8+eckvDnp5Kw7q2SS5G3kvfnuZL258+S9efQkrbu0pJOltOSuu7Vkrju15K07tmSte7gkrnu5JKbj+eSs+7pkvjn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vJlo6cGZnZTEmcqRxZl3icaZ7IvIme2L0JmTktGZbenSme6L1ZntidiZbOnbmWrp3Zlr6d+ZaenimXfp7Zlu6e6Zb+nxmXDp8plx6fiZc+n7mXLp/5l4jwGadOkFmnbpDppSiw+adekSmpuRE5qxjBmaeOkomsuRK5p56TCaq5M3mnrpPpqA6UCafelCmnzpQ5p+6UWae+lNmoLpTprf7lWagelXmoTpWprBi1uag+lfmoXpYpqG6WSaiOllmofpaZqJ6Wqai+lrmorpqJqcja2ajOmwmo3puJpbiryajunAmo/pxJqRkM+akOnRmpHp05qS6dSak+nYmoKN2Zrg7tya4e7empTp35qV6eKalunjmpfp5pqY6eqar5Trmprp7ZpFle6am+nvmpnp8Zqd6fSanOn3mp7p+5qf6QaboOkYm6HpGpui6R+bo+kim6TpI5ul6SWbpuknm6fpKJuo6Smbqekqm6rpLpur6S+brOkxm1SfMput6Tub9uI8m1OLQZtAikKbsI1Dm6/pRJuu6UWbo5ZNm7HpTpuy6U+bsOlRm7PpVJuCllibtOlam5uLb5tEmHKb4+50m7XpdZvi7oObt+mOm7yIj5vk7pGbuOmSm6mVk5u26ZabuemXm7rpn5u76aCbvOmom73pqpuOlqubTI6tm/iNrptOkbGb5e60m77puZvB6bub5u7Am7/pxpvC6cmb74zKm8Dpz5vD6dGbxOnSm8Xp1JvJ6dabSY7bm+KR4ZvK6eKbx+njm8bp5JvI6eibfozwm87p8ZvN6fKbzOn1m7GIAJzn7gSc2OkGnNTpCJzV6Qmc0ekKnNfpDJzT6Q2cgooQnGuYEpzW6ROc0ukUnNDpFZzP6Ruc2ukhnN3pJJzc6SWc2+ktnGiVLpzZ6S+c8YgwnN7pMpzg6Tmcj4o6nMvpO5xWiT6c4ulGnOHpR5zf6UicTJJSnJCWV5zYl1qc4+lgnOTpZ5zl6Xac5ul4nOfp5Zy5kuec6OnpnLWU65zt6eyc6enwnOrp85xQlvScwpb2nM6TA53u6Qad7+kHnbyTCJ3s6Qmd6+kOnaiJEp336RWd9ukbnZWJH5306SOd8+kmnfHpKJ2biiqd8OkrnbCOLJ2niTudg40+nfrpP5356UGd+OlEnfXpRp376Uid/OlQnUTqUZ1D6lmdRepcnUyJXZ1A6l6dQepgnZSNYZ23lmSdQuprnenubJ1Rlm+dSupwnejucp1G6nqdS+qHnUjqiZ1H6o+de4yanUzqpJ1N6qmdTuqrnUnqr53y6bKdT+q0nd+SuJ1T6rqdVOq7nVLqwZ1R6sKdV+rEnVDqxp1V6s+dVurTnVnq2Z1Y6uadW+rtnVzq751d6vKdaJj4nVrq+Z3pkfqd6439nV7qGZ7r7hqeX+obnmDqHp5h6nWeYup4nrKMeZ5j6n2eZOp/nq2OgZ5l6oieZuqLnmfqjJ5o6pGea+qSnmnqk55bmJWeauqXnu2XnZ5s6p+e2Zelnm3qpp6elKmebuqqnnDqrZ5x6rieb+q5no2Nup7Llrueg5a8nvWbvp6An7+em5bEnqmJzJ5z6s2eb4vOnnTqz5516tCedurRnuzu0p6VjdSed+rYntLg2Z7Zltue4ZHcnnjq3Z566t6eeergnnvq5Z586uiefervnn7q9J6A6vaeger3noLq+Z6D6vuehOr8noXq/Z6G6gefh+oIn4jqDp9DkxOf24wVn4rqIJ9skSGfi+osn4zqO59AlT6fjepKn47qS59W4k6f2OZPn+voUp+P6lSfkOpfn5LqYJ+T6mGflOpin+6XY5+R6maflepnn5bqap+Y6myfl+pyn5rqdp+b6nefmeqNn7SXlZ+c6pyfneqdn3PioJ+e6gDgQPAB4EHwAuBC8APgQ/AE4ETwBeBF8AbgRvAH4EfwCOBI8AngSfAK4ErwC+BL8AzgTPAN4E3wDuBO8A/gT/AQ4FDwEeBR8BLgUvAT4FPwFOBU8BXgVfAW4FbwF+BX8BjgWPAZ4FnwGuBa8BvgW/Ac4FzwHeBd8B7gXvAf4F/wIOBg8CHgYfAi4GLwI+Bj8CTgZPAl4GXwJuBm8CfgZ/Ao4GjwKeBp8CrgavAr4GvwLOBs8C3gbfAu4G7wL+Bv8DDgcPAx4HHwMuBy8DPgc/A04HTwNeB18DbgdvA34HfwOOB48DngefA64HrwO+B78DzgfPA94H3wPuB+8D/ggPBA4IHwQeCC8ELgg/BD4ITwROCF8EXghvBG4IfwR+CI8EjgifBJ4IrwSuCL8EvgjPBM4I3wTeCO8E7gj/BP4JDwUOCR8FHgkvBS4JPwU+CU8FTglfBV4JbwVuCX8FfgmPBY4JnwWeCa8Frgm/Bb4JzwXOCd8F3gnvBe4J/wX+Cg8GDgofBh4KLwYuCj8GPgpPBk4KXwZeCm8Gbgp/Bn4KjwaOCp8GngqvBq4Kvwa+Cs8GzgrfBt4K7wbuCv8G/gsPBw4LHwceCy8HLgs/Bz4LTwdOC18HXgtvB24Lfwd+C48HjgufB54LrweuC78HvgvPB84L3wfeC+8H7gv/B/4MDwgODB8IHgwvCC4MPwg+DE8ITgxfCF4MbwhuDH8IfgyPCI4MnwieDK8Irgy/CL4MzwjODN8I3gzvCO4M/wj+DQ8JDg0fCR4NLwkuDT8JPg1PCU4NXwleDW8Jbg1/CX4NjwmODZ8Jng2vCa4Nvwm+Dc8Jzg3fCd4N7wnuDf8J/g4PCg4OHwoeDi8KLg4/Cj4OTwpODl8KXg5vCm4Ofwp+Do8Kjg6fCp4OrwquDr8Kvg7PCs4O3wreDu8K7g7/Cv4PDwsODx8LHg8vCy4PPws+D08LTg9fC14PbwtuD38Lfg+PC44PnwueD68Lrg+/C74PzwvOBA8b3gQfG+4ELxv+BD8cDgRPHB4EXxwuBG8cPgR/HE4EjxxeBJ8cbgSvHH4EvxyOBM8cngTfHK4E7xy+BP8czgUPHN4FHxzuBS8c/gU/HQ4FTx0eBV8dLgVvHT4Ffx1OBY8dXgWfHW4Frx1+Bb8djgXPHZ4F3x2uBe8dvgX/Hc4GDx3eBh8d7gYvHf4GPx4OBk8eHgZfHi4Gbx4+Bn8eTgaPHl4Gnx5uBq8efga/Ho4Gzx6eBt8ergbvHr4G/x7OBw8e3gcfHu4HLx7+Bz8fDgdPHx4HXx8uB28fPgd/H04Hjx9eB58fbgevH34Hvx+OB88fngffH64H7x++CA8fzggfH94ILx/uCD8f/ghPEA4YXxAeGG8QLhh/ED4YjxBOGJ8QXhivEG4YvxB+GM8QjhjfEJ4Y7xCuGP8QvhkPEM4ZHxDeGS8Q7hk/EP4ZTxEOGV8RHhlvES4ZfxE+GY8RThmfEV4ZrxFuGb8RfhnPEY4Z3xGeGe8Rrhn/Eb4aDxHOGh8R3hovEe4aPxH+Gk8SDhpfEh4abxIuGn8SPhqPEk4anxJeGq8Sbhq/En4azxKOGt8SnhrvEq4a/xK+Gw8SzhsfEt4bLxLuGz8S/htPEw4bXxMeG28TLht/Ez4bjxNOG58TXhuvE24bvxN+G88TjhvfE54b7xOuG/8TvhwPE84cHxPeHC8T7hw/E/4cTxQOHF8UHhxvFC4cfxQ+HI8UThyfFF4crxRuHL8UfhzPFI4c3xSeHO8Urhz/FL4dDxTOHR8U3h0vFO4dPxT+HU8VDh1fFR4dbxUuHX8VPh2PFU4dnxVeHa8Vbh2/FX4dzxWOHd8Vnh3vFa4d/xW+Hg8Vzh4fFd4eLxXuHj8V/h5PFg4eXxYeHm8WLh5/Fj4ejxZOHp8WXh6vFm4evxZ+Hs8Wjh7fFp4e7xauHv8Wvh8PFs4fHxbeHy8W7h8/Fv4fTxcOH18XHh9vFy4ffxc+H48XTh+fF14frxduH78Xfh/PF44UDyeeFB8nrhQvJ74UPyfOFE8n3hRfJ+4Ubyf+FH8oDhSPKB4UnyguFK8oPhS/KE4UzyheFN8obhTvKH4U/yiOFQ8onhUfKK4VLyi+FT8ozhVPKN4VXyjuFW8o/hV/KQ4VjykeFZ8pLhWvKT4VvylOFc8pXhXfKW4V7yl+Ff8pjhYPKZ4WHymuFi8pvhY/Kc4WTyneFl8p7hZvKf4WfyoOFo8qHhafKi4Wryo+Fr8qThbPKl4W3ypuFu8qfhb/Ko4XDyqeFx8qrhcvKr4XPyrOF08q3hdfKu4Xbyr+F38rDhePKx4XnysuF68rPhe/K04XzyteF98rbhfvK34YDyuOGB8rnhgvK64YPyu+GE8rzhhfK94YbyvuGH8r/hiPLA4YnyweGK8sLhi/LD4YzyxOGN8sXhjvLG4Y/yx+GQ8sjhkfLJ4ZLyyuGT8svhlPLM4ZXyzeGW8s7hl/LP4Zjy0OGZ8tHhmvLS4Zvy0+Gc8tThnfLV4Z7y1uGf8tfhoPLY4aHy2eGi8trho/Lb4aTy3OGl8t3hpvLe4afy3+Go8uDhqfLh4ary4uGr8uPhrPLk4a3y5eGu8ubhr/Ln4bDy6OGx8unhsvLq4bPy6+G08uzhtfLt4bby7uG38u/huPLw4bny8eG68vLhu/Lz4bzy9OG98vXhvvL24b/y9+HA8vjhwfL54cLy+uHD8vvhxPL84cXy/eHG8v7hx/L/4cjyAOLJ8gHiyvIC4svyA+LM8gTizfIF4s7yBuLP8gfi0PII4tHyCeLS8gri0/IL4tTyDOLV8g3i1vIO4tfyD+LY8hDi2fIR4tryEuLb8hPi3PIU4t3yFeLe8hbi3/IX4uDyGOLh8hni4vIa4uPyG+Lk8hzi5fId4ubyHuLn8h/i6PIg4unyIeLq8iLi6/Ij4uzyJOLt8iXi7vIm4u/yJ+Lw8iji8fIp4vLyKuLz8ivi9PIs4vXyLeL28i7i9/Iv4vjyMOL58jHi+vIy4vvyM+L88jTiQPM14kHzNuJC8zfiQ/M44kTzOeJF8zriRvM74kfzPOJI8z3iSfM+4krzP+JL80DiTPNB4k3zQuJO80PiT/NE4lDzReJR80biUvNH4lPzSOJU80niVfNK4lbzS+JX80ziWPNN4lnzTuJa80/iW/NQ4lzzUeJd81LiXvNT4l/zVOJg81XiYfNW4mLzV+Jj81jiZPNZ4mXzWuJm81viZ/Nc4mjzXeJp817iavNf4mvzYOJs82HibfNi4m7zY+Jv82TicPNl4nHzZuJy82fic/No4nTzaeJ182ridvNr4nfzbOJ4823iefNu4nrzb+J783DifPNx4n3zcuJ+83PigPN04oHzdeKC83big/N34oTzeOKF83nihvN64ofze+KI83ziifN94orzfuKL83/ijPOA4o3zgeKO84Lij/OD4pDzhOKR84XikvOG4pPzh+KU84jilfOJ4pbziuKX84vimPOM4pnzjeKa847im/OP4pzzkOKd85HinvOS4p/zk+Kg85TiofOV4qLzluKj85fipPOY4qXzmeKm85rip/Ob4qjznOKp853iqvOe4qvzn+Ks86DirfOh4q7zouKv86PisPOk4rHzpeKy86bis/On4rTzqOK186nitvOq4rfzq+K486ziufOt4rrzruK786/ivPOw4r3zseK+87Liv/Oz4sDztOLB87XiwvO24sPzt+LE87jixfO54sbzuuLH87viyPO84snzveLK877iy/O/4szzwOLN88HizvPC4s/zw+LQ88Ti0fPF4tLzxuLT88fi1PPI4tXzyeLW88ri1/PL4tjzzOLZ883i2vPO4tvzz+Lc89Di3fPR4t7z0uLf89Pi4PPU4uHz1eLi89bi4/PX4uTz2OLl89ni5vPa4ufz2+Lo89zi6fPd4urz3uLr89/i7PPg4u3z4eLu8+Li7/Pj4vDz5OLx8+Xi8vPm4vPz5+L08+ji9fPp4vbz6uL38+vi+PPs4vnz7eL68+7i+/Pv4vzz8OJA9PHiQfTy4kL08+JD9PTiRPT14kX09uJG9PfiR/T44kj0+eJJ9PriSvT74kv0/OJM9P3iTfT+4k70/+JP9ADjUPQB41H0AuNS9APjU/QE41T0BeNV9AbjVvQH41f0CONY9AnjWfQK41r0C+Nb9AzjXPQN4130DuNe9A/jX/QQ42D0EeNh9BLjYvQT42P0FONk9BXjZfQW42b0F+Nn9BjjaPQZ42n0GuNq9Bvja/Qc42z0HeNt9B7jbvQf42/0IONw9CHjcfQi43L0I+Nz9CTjdPQl43X0JuN29Cfjd/Qo43j0KeN59CrjevQr43v0LON89C3jffQu4370L+OA9DDjgfQx44L0MuOD9DPjhPQ044X0NeOG9Dbjh/Q344j0OOOJ9DnjivQ644v0O+OM9DzjjfQ94470PuOP9D/jkPRA45H0QeOS9ELjk/RD45T0ROOV9EXjlvRG45f0R+OY9EjjmfRJ45r0SuOb9EvjnPRM4530TeOe9E7jn/RP46D0UOOh9FHjovRS46P0U+Ok9FTjpfRV46b0VuOn9FfjqPRY46n0WeOq9Frjq/Rb46z0XOOt9F3jrvRe46/0X+Ow9GDjsfRh47L0YuOz9GPjtPRk47X0ZeO29Gbjt/Rn47j0aOO59GnjuvRq47v0a+O89GzjvfRt4770buO/9G/jwPRw48H0cePC9HLjw/Rz48T0dOPF9HXjxvR248f0d+PI9HjjyfR548r0euPL9HvjzPR84830fePO9H7jz/R/49D0gOPR9IHj0vSC49P0g+PU9ITj1fSF49b0huPX9Ifj2PSI49n0iePa9Irj2/SL49z0jOPd9I3j3vSO49/0j+Pg9JDj4fSR4+L0kuPj9JPj5PSU4+X0lePm9Jbj5/SX4+j0mOPp9Jnj6vSa4+v0m+Ps9Jzj7fSd4+70nuPv9J/j8PSg4/H0oePy9KLj8/Sj4/T0pOP19KXj9vSm4/f0p+P49Kjj+fSp4/r0quP79Kvj/PSs40D1reNB9a7jQvWv40P1sONE9bHjRfWy40b1s+NH9bTjSPW140n1tuNK9bfjS/W440z1ueNN9brjTvW740/1vONQ9b3jUfW+41L1v+NT9cDjVPXB41X1wuNW9cPjV/XE41j1xeNZ9cbjWvXH41v1yONc9cnjXfXK4171y+Nf9czjYPXN42H1zuNi9c/jY/XQ42T10eNl9dLjZvXT42f11ONo9dXjafXW42r11+Nr9djjbPXZ42312uNu9dvjb/Xc43D13eNx9d7jcvXf43P14ON09eHjdfXi43b14+N39eTjePXl43n15uN69efje/Xo43z16eN99erjfvXr44D17OOB9e3jgvXu44P17+OE9fDjhfXx44b18uOH9fPjiPX044n19eOK9fbji/X344z1+OON9fnjjvX644/1++OQ9fzjkfX945L1/uOT9f/jlPUA5JX1AeSW9QLkl/UD5Jj1BOSZ9QXkmvUG5Jv1B+Sc9QjknfUJ5J71CuSf9QvkoPUM5KH1DeSi9Q7ko/UP5KT1EOSl9RHkpvUS5Kf1E+So9RTkqfUV5Kr1FuSr9RfkrPUY5K31GeSu9Rrkr/Ub5LD1HOSx9R3ksvUe5LP1H+S09SDktfUh5Lb1IuS39SPkuPUk5Ln1JeS69Sbku/Un5Lz1KOS99SnkvvUq5L/1K+TA9SzkwfUt5ML1LuTD9S/kxPUw5MX1MeTG9TLkx/Uz5Mj1NOTJ9TXkyvU25Mv1N+TM9TjkzfU55M71OuTP9Tvk0PU85NH1PeTS9T7k0/U/5NT1QOTV9UHk1vVC5Nf1Q+TY9UTk2fVF5Nr1RuTb9Ufk3PVI5N31SeTe9Urk3/VL5OD1TOTh9U3k4vVO5OP1T+Tk9VDk5fVR5Ob1UuTn9VPk6PVU5On1VeTq9Vbk6/VX5Oz1WOTt9Vnk7vVa5O/1W+Tw9Vzk8fVd5PL1XuTz9V/k9PVg5PX1YeT29WLk9/Vj5Pj1ZOT59WXk+vVm5Pv1Z+T89WjkQPZp5EH2auRC9mvkQ/Zs5ET2beRF9m7kRvZv5Ef2cORI9nHkSfZy5Er2c+RL9nTkTPZ15E32duRO9nfkT/Z45FD2eeRR9nrkUvZ75FP2fORU9n3kVfZ+5Fb2f+RX9oDkWPaB5Fn2guRa9oPkW/aE5Fz2heRd9obkXvaH5F/2iORg9onkYfaK5GL2i+Rj9ozkZPaN5GX2juRm9o/kZ/aQ5Gj2keRp9pLkavaT5Gv2lORs9pXkbfaW5G72l+Rv9pjkcPaZ5HH2muRy9pvkc/ac5HT2neR19p7kdvaf5Hf2oOR49qHkefai5Hr2o+R79qTkfPal5H32puR+9qfkgPao5IH2qeSC9qrkg/ar5IT2rOSF9q3khvau5If2r+SI9rDkifax5Ir2suSL9rPkjPa05I32teSO9rbkj/a35JD2uOSR9rnkkva65JP2u+SU9rzklfa95Jb2vuSX9r/kmPbA5Jn2weSa9sLkm/bD5Jz2xOSd9sXknvbG5J/2x+Sg9sjkofbJ5KL2yuSj9svkpPbM5KX2zeSm9s7kp/bP5Kj20OSp9tHkqvbS5Kv20+Ss9tTkrfbV5K721uSv9tfksPbY5LH22eSy9trks/bb5LT23OS19t3ktvbe5Lf23+S49uDkufbh5Lr24uS79uPkvPbk5L325eS+9ubkv/bn5MD26OTB9unkwvbq5MP26+TE9uzkxfbt5Mb27uTH9u/kyPbw5Mn28eTK9vLky/bz5Mz29OTN9vXkzvb25M/29+TQ9vjk0fb55NL2+uTT9vvk1Pb85NX2/eTW9v7k1/b/5Nj2AOXZ9gHl2vYC5dv2A+Xc9gTl3fYF5d72BuXf9gfl4PYI5eH2CeXi9grl4/YL5eT2DOXl9g3l5vYO5ef2D+Xo9hDl6fYR5er2EuXr9hPl7PYU5e32FeXu9hbl7/YX5fD2GOXx9hnl8vYa5fP2G+X09hzl9fYd5fb2HuX39h/l+PYg5fn2IeX69iLl+/Yj5fz2JOVA9yXlQfcm5UL3J+VD9yjlRPcp5UX3KuVG9yvlR/cs5Uj3LeVJ9y7lSvcv5Uv3MOVM9zHlTfcy5U73M+VP9zTlUPc15VH3NuVS9zflU/c45VT3OeVV9zrlVvc75Vf3POVY9z3lWfc+5Vr3P+Vb90DlXPdB5V33QuVe90PlX/dE5WD3ReVh90blYvdH5WP3SOVk90nlZfdK5Wb3S+Vn90zlaPdN5Wn3TuVq90/la/dQ5Wz3UeVt91LlbvdT5W/3VOVw91XlcfdW5XL3V+Vz91jldPdZ5XX3WuV291vld/dc5Xj3XeV5917levdf5Xv3YOV892Hlffdi5X73Y+WA92Tlgfdl5YL3ZuWD92flhPdo5YX3aeWG92rlh/dr5Yj3bOWJ923livdu5Yv3b+WM93Dljfdx5Y73cuWP93PlkPd05ZH3deWS93blk/d35ZT3eOWV93nllvd65Zf3e+WY93zlmfd95Zr3fuWb93/lnPeA5Z33geWe94Lln/eD5aD3hOWh94XloveG5aP3h+Wk94jlpfeJ5ab3iuWn94vlqPeM5an3jeWq947lq/eP5az3kOWt95HlrveS5a/3k+Ww95TlsfeV5bL3luWz95fltPeY5bX3meW295rlt/eb5bj3nOW5953luvee5bv3n+W896Dlvfeh5b73ouW/96PlwPek5cH3peXC96blw/en5cT3qOXF96nlxveq5cf3q+XI96zlyfet5cr3ruXL96/lzPew5c33seXO97Llz/ez5dD3tOXR97Xl0ve25dP3t+XU97jl1fe55db3uuXX97vl2Pe85dn3veXa977l2/e/5dz3wOXd98Hl3vfC5d/3w+Xg98Tl4ffF5eL3xuXj98fl5PfI5eX3yeXm98rl5/fL5ej3zOXp983l6vfO5ev3z+Xs99Dl7ffR5e730uXv99Pl8PfU5fH31eXy99bl8/fX5fT32OX199nl9vfa5ff32+X499zl+ffd5fr33uX799/l/Pfg5UD44eVB+OLlQvjj5UP45OVE+OXlRfjm5Ub45+VH+OjlSPjp5Un46uVK+OvlS/js5Uz47eVN+O7lTvjv5U/48OVQ+PHlUfjy5VL48+VT+PTlVPj15VX49uVW+PflV/j45Vj4+eVZ+PrlWvj75Vv4/OVc+P3lXfj+5V74/+Vf+ADmYPgB5mH4AuZi+APmY/gE5mT4BeZl+AbmZvgH5mf4COZo+AnmafgK5mr4C+Zr+AzmbPgN5m34DuZu+A/mb/gQ5nD4EeZx+BLmcvgT5nP4FOZ0+BXmdfgW5nb4F+Z3+BjmePgZ5nn4GuZ6+Bvme/gc5nz4HeZ9+B7mfvgf5oD4IOaB+CHmgvgi5oP4I+aE+CTmhfgl5ob4JuaH+CfmiPgo5on4KeaK+Crmi/gr5oz4LOaN+C3mjvgu5o/4L+aQ+DDmkfgx5pL4MuaT+DPmlPg05pX4NeaW+Dbml/g35pj4OOaZ+Dnmmvg65pv4O+ac+Dzmnfg95p74Puaf+D/moPhA5qH4Qeai+ELmo/hD5qT4ROal+EXmpvhG5qf4R+ao+EjmqfhJ5qr4Suar+EvmrPhM5q34Teau+E7mr/hP5rD4UOax+FHmsvhS5rP4U+a0+FTmtfhV5rb4Vua3+FfmuPhY5rn4Wea6+Frmu/hb5rz4XOa9+F3mvvhe5r/4X+bA+GDmwfhh5sL4YubD+GPmxPhk5sX4ZebG+Gbmx/hn5sj4aObJ+Gnmyvhq5sv4a+bM+Gzmzfht5s74bubP+G/m0Phw5tH4cebS+HLm0/hz5tT4dObV+HXm1vh25tf4d+bY+Hjm2fh55tr4eubb+Hvm3Ph85t34febe+H7m3/h/5uD4gObh+IHm4viC5uP4g+bk+ITm5fiF5ub4hubn+Ifm6PiI5un4iebq+Irm6/iL5uz4jObt+I3m7viO5u/4j+bw+JDm8fiR5vL4kubz+JPm9PiU5vX4leb2+Jbm9/iX5vj4mOb5+Jnm+via5vv4m+b8+JzmQPmd5kH5nuZC+Z/mQ/mg5kT5oeZF+aLmRvmj5kf5pOZI+aXmSfmm5kr5p+ZL+ajmTPmp5k35quZO+avmT/ms5lD5reZR+a7mUvmv5lP5sOZU+bHmVfmy5lb5s+ZX+bTmWPm15ln5tuZa+bfmW/m45lz5ueZd+brmXvm75l/5vOZg+b3mYfm+5mL5v+Zj+cDmZPnB5mX5wuZm+cPmZ/nE5mj5xeZp+cbmavnH5mv5yOZs+cnmbfnK5m75y+Zv+czmcPnN5nH5zuZy+c/mc/nQ5nT50eZ1+dLmdvnT5nf51OZ4+dXmefnW5nr51+Z7+djmfPnZ5n352uZ++dvmgPnc5oH53eaC+d7mg/nf5oT54OaF+eHmhvni5of54+aI+eTmifnl5or55uaL+efmjPno5o356eaO+ermj/nr5pD57OaR+e3mkvnu5pP57+aU+fDmlfnx5pb58uaX+fPmmPn05pn59eaa+fbmm/n35pz5+Oad+fnmnvn65p/5++ag+fzmofn95qL5/uaj+f/mpPkA56X5Aeem+QLnp/kD56j5BOep+QXnqvkG56v5B+es+QjnrfkJ5675Cuev+QvnsPkM57H5Deey+Q7ns/kP57T5EOe1+RHntvkS57f5E+e4+RTnufkV57r5Fue7+RfnvPkY5735Gee++Rrnv/kb58D5HOfB+R3nwvke58P5H+fE+SDnxfkh58b5IufH+SPnyPkk58n5JefK+Sbny/kn58z5KOfN+Snnzvkq58/5K+fQ+Szn0fkt59L5LufT+S/n1Pkw59X5MefW+TLn1/kz59j5NOfZ+TXn2vk259v5N+fc+Tjn3fk55975Ouff+Tvn4Pk85+H5Pefi+T7n4/k/5+T5QOfl+UHn5vlC5+f5Q+fo+UTn6flF5+r5Rufr+Ufn7PlI5+35Sefu+Urn7/lL5/D5TOfx+U3n8vlO5/P5T+f0+VDn9flR5/b5Uuf3+VPn+PlU5/n5Vef6+Vbn+/lX5/z58PigAPH4/QDy+P4A8/j/ACn5xO3c+c3uDvpz7Q/6fu0Q+oDtEfqV7RL6vO0T+sztFPrO7RX6+e0W+kLuF/pZ7hj6Ye4Z+mLuGvpj7hv6Ze4c+mnuHfps7h76de4f+oHuIPqD7iH6hO4i+o3uI/qV7iT6l+4l+pjuJvqb7if6t+4o+r7uKfrO7ir62u4r+tvuLPrd7i366u4B/0mBAv/87gP/lIEE/5CBBf+TgQb/lYEH//vuCP9pgQn/aoEK/5aBC/97gQz/Q4EN/3yBDv9EgQ//XoEQ/0+CEf9QghL/UYIT/1KCFP9TghX/VIIW/1WCF/9Wghj/V4IZ/1iCGv9GgRv/R4Ec/4OBHf+BgR7/hIEf/0iBIP+XgSH/YIIi/2GCI/9igiT/Y4Il/2SCJv9lgif/ZoIo/2eCKf9ogir/aYIr/2qCLP9rgi3/bIIu/22CL/9ugjD/b4Ix/3CCMv9xgjP/coI0/3OCNf90gjb/dYI3/3aCOP93gjn/eII6/3mCO/9tgTz/X4E9/26BPv9PgT//UYFA/02BQf+BgkL/goJD/4OCRP+EgkX/hYJG/4aCR/+Hgkj/iIJJ/4mCSv+Kgkv/i4JM/4yCTf+Ngk7/joJP/4+CUP+QglH/kYJS/5KCU/+TglT/lIJV/5WCVv+Wglf/l4JY/5iCWf+Zglr/moJb/2+BXP9igV3/cIFe/2CBYf+hAGL/ogBj/6MAZP+kAGX/pQBm/6YAZ/+nAGj/qABp/6kAav+qAGv/qwBs/6wAbf+tAG7/rgBv/68AcP+wAHH/sQBy/7IAc/+zAHT/tAB1/7UAdv+2AHf/twB4/7gAef+5AHr/ugB7/7sAfP+8AH3/vQB+/74Af/+/AID/wACB/8EAgv/CAIP/wwCE/8QAhf/FAIb/xgCH/8cAiP/IAIn/yQCK/8oAi//LAIz/zACN/80Ajv/OAI//zwCQ/9AAkf/RAJL/0gCT/9MAlP/UAJX/1QCW/9YAl//XAJj/2ACZ/9kAmv/aAJv/2wCc/9wAnf/dAJ7/3gCf/98A4P+RgeH/koHi/8qB4/9QgeT/+u7l/4+B'
local cp932
function Core.encode_name(name,encoding)
 if name:find('%z') then error('名前にNUL文字は使用できません。',0) end
 if encoding=='UTF-8' then
  if not utf8.len(name) then error('名前が正しいUTF-8ではありません。',0) end
  return name
 end
 if not cp932 then
  cp932={};local raw=Core.unbase64(CP932_TABLE)
  for i=1,#raw,4 do local u,v=string.unpack('<I2I2',raw,i);cp932[u]=v<256 and string.char(v) or string.char(v>>8,v&255) end
 end
 local out={}
 for _,u in utf8.codes(name) do
  if not cp932[u] then error('CP932に変換できない文字があります: '..utf8.char(u)..' — 名前を変更するかUTF-8を選んでください。',0) end
  out[#out+1]=cp932[u]
 end
 return table.concat(out)
end
local function u32(n) assert(finite(n) and n>=0 and n<=0xffffffff and n%1==0,'Invalid uint32');return string.pack('<I4',n) end
function Core.chunk(id,data) return id..u32(#data)..data..(#data%2==1 and '\0' or '') end
function Core.plan(rows,start,ending,sr,options)
 options=options or {};assert(finite(start) and finite(ending) and ending>start,'書き出し範囲を指定してください。')
 assert(finite(sr) and sr>=8000 and sr<=384000 and sr%1==0,'サンプルレートが不正です。')
 local first,last=floor(start*sr+.5),floor(ending*sr+.5)
 local p={start=first/sr,finish=last/sr,requested_start=start,requested_finish=ending,sr=sr,frames=last-first,entries={},outside=0,clipped=0,omitted=0,encoding=options.encoding or 'UTF-8'}
 assert(p.frames>0 and p.frames<=0xffffffff,'書き出し範囲がWAVの上限を超えています。')
 local sustainStart,sustainId,sustainIndex,sustainClipped
 local function sample(t)return floor(t*sr+.5)-first end
 for _,row in ipairs(rows)do
  assert(finite(row.start)and finite(row.finish),'リージョン位置が不正です。')
  local isr=row.isr;local included=isr and row.finish>start and row.start<ending or not isr and row.start>=start and row.start<=ending
  if included then
   assert(row.kind~='invalid','不明なBLT接頭辞: '..row.raw)
   assert(row.kind=='marker'or row.kind=='region'or row.kind=='sustain','未対応の区間種類です。')
   local loop=row.kind=='sustain'
   local enabled=row.kind=='marker'and options.embed_markers~=false
    or row.kind=='region'and options.embed_regions~=false
    or loop and options.embed_loop_region~=false
   if options.exclude_selected_region and row.kind=='region'and(row.key==options.selected_key or(options.selected_keys and options.selected_keys[row.key]))then enabled=false end
   if(row.kind=='marker'and options.marker_hash_only or row.kind=='region'and options.region_hash_only)and row.raw:sub(1,1)~='#'then enabled=false end
   if not enabled then p.omitted=p.omitted+1;goto continue end
   if loop and p.sustain and not(row.start<sustainStart or(row.start==sustainStart and row.id and sustainId and row.id<sustainId))then p.omitted=p.omitted+1;goto continue end
   assert(not loop or row.finish>row.start,'リージョン位置が不正です。')
   local s,e=sample(row.start),sample(row.finish)
   local clipped=isr and(s<0 or e>p.frames)
   s=clamp(s,0,p.frames);e=clamp(e,0,p.frames)
   if loop then s=math.min(s,p.frames-1);e=math.max(e,s+1)end
   assert(not isr or e>s,'1サンプル未満のリージョンがあります: '..row.name)
   local encoded=loop and''or Core.encode_name(row.name,p.encoding)
   local entry={kind=row.kind,name=row.name,start=s,finish=e,encoded=encoded,id=row.id,key=row.key}
   assert(#entry.encoded<=65535,'名前が長すぎます。')
   if loop then
    if p.sustain then
     p.omitted=p.omitted+1;if sustainClipped then p.clipped=p.clipped-1 end
     p.entries[sustainIndex]=entry
    else sustainIndex=#p.entries+1;p.entries[sustainIndex]=entry end
    p.sustain,sustainStart,sustainId,sustainClipped=entry,row.start,row.id,clipped
   else p.entries[#p.entries+1]=entry end
   if clipped then p.clipped=p.clipped+1 end
  else p.outside=p.outside+1 end
  ::continue::
 end
 return p
end
function Core.single_render_wav_target(got,targets)
 assert(got,'REAPERから出力先を取得できません。')
 local wavs={}
 for path in tostring(targets or ''):gmatch('[^;]+') do
  path=path:match('^%s*(.-)%s*$')
  if path:lower():match('%.wav$') then wavs[#wavs+1]=path end
 end
 assert(#wavs>0,'REAPER本体の設定からWAV出力先を取得できません。出力形式をWAVにしてください。')
 assert(#wavs==1,'REAPER本体の設定から複数のWAV出力先が返されました。セカンダリ出力やステム出力を無効にしてください。')
 return wavs[1]
end
function Core.batch_output_name(name,index,count)
 assert(type(name)=='string' and name~='' and finite(index) and finite(count) and index>=1 and index<=count,'一括出力名の指定が不正です。')
 return count>1 and (name..string.format('_%03d',index)) or name
end
function Core.manual_render_pattern(value)
 local name=tostring(value or ''):gsub('%.[Ww][Aa][Vv]$','')
 if name=='' or name=='.' or name=='..' or name:find('[<>:"/\\|?*%c;]') or name:match('[%. ]$') then return nil end
 return name
end
function Core.reserved_filename(name)
 local stem=(tostring(name or ''):match('^[^.]+') or ''):upper()
 return stem=='CON' or stem=='PRN' or stem=='AUX' or stem=='NUL' or stem:match('^COM[1-9]$') or stem:match('^LPT[1-9]$')
end
function Core.metadata(p)
 local cues,adtl,loops={},{},{}
 local cueid=1
 for _,e in ipairs(p.entries) do
  if e.kind=='marker' or e.kind=='region' then
   -- Avoid a label consisting solely of its NUL terminator.
   local name=e.encoded~='' and e.encoded or ((e.kind=='marker' and 'Marker_' or 'Region_')..cueid)
   cues[#cues+1]=u32(cueid)..u32(e.start)..'data'..u32(0)..u32(0)..u32(e.start)
   adtl[#adtl+1]=Core.chunk('labl',u32(cueid)..name..'\0')
   if e.kind=='region' then
    -- Sound Forge's ordinary region: cue start + ltxt length, purpose "rgn ".
    adtl[#adtl+1]=Core.chunk('ltxt',u32(cueid)..u32(e.finish-e.start)..'rgn '..string.pack('<I2I2I2I2',0,0,0,p.encoding=='UTF-8' and 65001 or 932)..name..'\0')
   end
   cueid=cueid+1
  end
 end
 -- A play count of 0 means infinite repetition in the WAV smpl chunk.
 local e=p.sustain
 if e then loops[1]=u32(0)..u32(0)..u32(e.start)..u32(e.finish-1)..u32(0)..u32(0) end
 local out={}
 if #cues>0 then out[#out+1]=Core.chunk('cue ',u32(#cues)..table.concat(cues));out[#out+1]=Core.chunk('LIST','adtl'..table.concat(adtl)) end
 if #loops>0 then out[#out+1]=Core.chunk('smpl',u32(0)..u32(0)..u32(floor(1e9/p.sr+.5))..u32(60)..u32(0)..u32(0)..u32(0)..u32(#loops)..u32(0)..table.concat(loops)) end
 local blob=table.concat(out);assert(#blob<=Core.MAX_METADATA,'リージョン情報が大きすぎます。');return blob
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
  local w={size=size,declared_size=declared_size,chunks={},metadata={}};local offset=12
  while offset<size do
   assert(offset+8<=size,'WAVチャンクヘッダーが不正です。');assert(f:seek('set',offset))
   local h=read_exact(f,8);local id=h:sub(1,4);local n=string.unpack('<I4',h,5)
   -- Source-audio reading needs a complete payload, not the optional final pad.
   local pad=audio_only and id=='data' and 0 or n%2
   assert(offset+8+n+pad<=size,'WAVチャンク長が不正です。音声データが途中で切れている可能性があります。')
   local c={id=id,offset=offset,size=n,total=8+n+n%2}
   if id=='LIST' and n>=4 then c.list=read_exact(f,4) end
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
   c.remove=id=='cue ' or id=='smpl' or id=='plst' or (id=='LIST' and c.list=='adtl')
   if c.remove and not audio_only then
    assert(n<=Core.MAX_METADATA,'既存のWAVメタデータが大きすぎます。');assert(f:seek('set',offset));w.metadata[#w.metadata+1]=read_exact(f,c.total)
   end
   w.chunks[#w.chunks+1]=c;offset=offset+c.total
   -- Existing files may contain trailing application data or stale RIFF sizes.
   -- Do not interpret that tail when only the verified audio payload is needed.
   if audio_only and w.sr and w.data then break end
  end
  assert(w.sr and w.data and w.data.size%w.align==0,'音声データがありません、またはサンプル境界が不正です。')
  w.frames=w.data.size//w.align;return w
 end,debug.traceback)
 f:close();if not ok then error(result,0) end;return result
end
function Core.exists(path) local f=io.open(path,'rb');if f then f:close();return true end;return false end
Core.PENDING_FILE_DELETE={};Core.PENDING_FILE_DELETE_LIMIT=32;Core.pending_file_retry_at=0
function Core.queue_file_delete(path)
 if not path or not Core.exists(path) or Core.PENDING_FILE_DELETE[path] then return end
 local count,oldest_path,oldest_time=0,nil,math.huge
 for pending_path,queued_at in pairs(Core.PENDING_FILE_DELETE) do
  count=count+1
  if queued_at<oldest_time then oldest_path,oldest_time=pending_path,queued_at end
 end
 if count>=Core.PENDING_FILE_DELETE_LIMIT and oldest_path then Core.PENDING_FILE_DELETE[oldest_path]=nil end
 Core.PENDING_FILE_DELETE[path]=R.time_precise()
end
function Core.retry_file_deletes(force)
 local now=R.time_precise()
 if not force and now<Core.pending_file_retry_at then return end
 Core.pending_file_retry_at=now+2
 for path in pairs(Core.PENDING_FILE_DELETE) do
  local called,removed=pcall(os.remove,path)
  if not Core.exists(path) or (called and removed) then Core.PENDING_FILE_DELETE[path]=nil end
 end
end
function Core.unique(path)
 if not Core.exists(path) then return path end
 local base=path:gsub('%.[Ww][Aa][Vv]$','')
 for i=1,9999 do local p=base..string.format('_%03d.wav',i);if not Core.exists(p) then return p end end
 error('出力ファイル名を確保できません。',0)
end
function Core.render_window(p)
 local first=floor(p.start*p.sr+.5);local guard=math.ceil(.05*p.sr)
 local pre=min(guard,max(0,first))
 return {start=(first-pre)/p.sr,finish=(first+p.frames+guard)/p.sr,
  frames=pre+p.frames+guard,pre=pre}
end
function Core.copy_start(source,target,p)
 assert(source~=target and not Core.exists(target),'出力先は新しいWAVファイルを指定してください。')
 local wav=Core.scan(source)
 assert(wav.sr==p.sr,'レンダーのサンプルレートが一致しません。')
 local window=p.render_window or {frames=p.frames,pre=0}
 -- Tolerate only +/-1 frame in the intermediate render; keep the final slice unchanged.
 assert(abs(wav.frames-window.frames)<=1,string.format('レンダーの長さが一致しません。\n指定範囲: %.9f ～ %.9f 秒\n予定: %d samples (%.9f 秒)\n実際: %d samples (%.9f 秒)\n差: %+d samples / %+.6f ms\nサンプルレート: %d Hz',window.start or p.start,window.finish or p.finish,window.frames,window.frames/p.sr,wav.frames,wav.frames/wav.sr,wav.frames-window.frames,(wav.frames-window.frames)*1000/p.sr,p.sr))
 -- The complete slice must remain inside audio data, never padding or following chunks.
 assert(window.pre+p.frames<=wav.frames,'レンダー音声に必要な切り出し範囲が含まれていません。')
 -- Metadata is relative to the final WAV, not the padded intermediate render.
 for _,e in ipairs(p.entries) do assert(e.start<=p.frames and e.finish<=p.frames,'メタデータが実際のWAV終端を超えています。') end
 local blob=Core.metadata(p);local keep={};local size=12+#blob
 local function add(c) keep[#keep+1]=c;size=size+c.total end
 local function bytes(data) add({bytes=data,total=#data}) end
 for _,c in ipairs(wav.chunks) do
  if c.id=='data' then
   local n=p.frames*wav.align
   bytes('data'..u32(n))
   add({offset=c.offset+8+window.pre*wav.align,total=n})
   if n%2==1 then bytes('\0') end
  elseif not c.remove and c.id~='PEAK' then
   if c.id=='fact' or (c.id=='bext' and window.pre>0) then
    local f=assert(io.open(source,'rb'));assert(f:seek('set',c.offset));local raw=read_exact(f,c.total);f:close()
    if c.id=='fact' and c.size>=4 then raw=raw:sub(1,8)..u32(p.frames)..raw:sub(13)
    elseif c.id=='bext' and c.size>=346 then
     local lo,hi=string.unpack('<I4I4',raw,347)
     local sum=lo+window.pre;local carry=sum//4294967296
     assert(hi+carry<=0xffffffff,'BWF時刻が上限を超えています。')
     raw=raw:sub(1,346)..u32(sum%4294967296)..u32(hi+carry)..raw:sub(355)
    end
    bytes(raw)
   else add(c) end
  end
 end
 assert(size-8<=0xffffffff,'4 GiBを超えるWAVには対応していません。')
 local temp=target..'.blt-part';assert(not Core.exists(temp),'作業ファイルが存在します: '..temp)
 local input=assert(io.open(source,'rb'));local output,err=io.open(temp,'wb')
 if not output then input:close();error(err,0) end
 local j={input=input,output=output,source=source,target=target,temp=temp,wav=wav,blob=blob,chunks=keep,index=1,within=0,copied=0,size=size,plan=p}
 local ok,msg=output:write('RIFF'..u32(size-8)..'WAVE')
 if not ok then Core.copy_abort(j);error(msg,0) end
 return j
end
function Core.copy_abort(j)
 if not j then return end
 if j.input then j.input:close();j.input=nil end
 if j.output then j.output:close();j.output=nil end
 if j.temp then
  local path=j.temp;j.temp=nil
  local called,removed=pcall(os.remove,path)
  if Core.exists(path) and not (called and removed) then Core.queue_file_delete(path) end
 end
end
function Core.copy_step(j)
 local c=j.chunks[j.index]
 if c then
  local n=min(1024*1024,c.total-j.within)
  if c.bytes then assert(j.output:write(c.bytes:sub(j.within+1,j.within+n)))
  else assert(j.input:seek('set',c.offset+j.within));assert(j.output:write(read_exact(j.input,n))) end
  j.within=j.within+n;j.copied=j.copied+n
  if j.within==c.total then j.index=j.index+1;j.within=0 end
  return false
 end
 assert(j.output:write(j.blob));assert(j.output:flush());assert(j.output:close());j.output=nil;j.input:close();j.input=nil
 local check=Core.scan(j.temp)
 assert(check.frames==j.plan.frames and check.sr==j.plan.sr and table.concat(check.metadata)==j.blob,'書き込み検証に失敗しました。')
 assert(not Core.exists(j.target),'出力先が別の処理で作成されました。再実行してください。')
 assert(os.rename(j.temp,j.target));j.temp=nil;return true
end
-- No hard-coded project format preferences are left behind after rendering.
Core.render_numbers={'RENDER_SETTINGS','RENDER_BOUNDSFLAG','RENDER_STARTPOS','RENDER_ENDPOS','RENDER_TAILFLAG','RENDER_ADDTOPROJ','RENDER_SRATE','RENDER_CHANNELS','RENDER_NORMALIZE','RENDER_DITHER'}
Core.render_strings={'RENDER_FILE','RENDER_PATTERN','RENDER_FORMAT','RENDER_FORMAT2'}
function Core.project_region_selection(project)
 assert(type(R.GetNumRegionsOrMarkers)=='function' and type(R.GetRegionOrMarker)=='function'
  and type(R.GetRegionOrMarkerInfo_Value)=='function','REAPERのリージョン選択APIを利用できません。REAPERを更新してください。')
 local selected={}
 for i=0,R.GetNumRegionsOrMarkers(project)-1 do
  local ptr=R.GetRegionOrMarker(project,i,'')
  if ptr and R.GetRegionOrMarkerInfo_Value(project,ptr,'B_ISREGION')~=0 then
   local id=R.GetRegionOrMarkerInfo_Value(project,ptr,'I_NUMBER')
   if finite(id) and R.GetRegionOrMarkerInfo_Value(project,ptr,'B_UISEL')~=0 then selected[floor(id+.5)]=true end
  end
 end
 return selected
end
function Core.set_project_region_selection(project,selected)
 assert(type(R.SetRegionOrMarkerInfo_Value)=='function','REAPERのリージョン選択APIを利用できません。REAPERを更新してください。')
 local found={}
 for i=0,R.GetNumRegionsOrMarkers(project)-1 do
  local ptr=R.GetRegionOrMarker(project,i,'')
  if ptr and R.GetRegionOrMarkerInfo_Value(project,ptr,'B_ISREGION')~=0 then
   local value=R.GetRegionOrMarkerInfo_Value(project,ptr,'I_NUMBER')
   if finite(value) then
    local id=floor(value+.5);local wanted=selected[id] and 1 or 0
    R.SetRegionOrMarkerInfo_Value(project,ptr,'B_UISEL',wanted)
    assert((R.GetRegionOrMarkerInfo_Value(project,ptr,'B_UISEL')~=0)==(wanted~=0),'レンダー対象リージョンの選択を変更できません。')
    if selected[id] then found[id]=true end
   end
  end
 end
 for id in pairs(selected) do assert(found[id],'レンダー対象リージョンが見つかりません: '..id) end
 if type(R.UpdateArrange)=='function' then R.UpdateArrange() end
end
function Core.snapshot_render(project)
 local s={project=project,n={},s={}}
 s.selection={R.GetSet_LoopTimeRange2(project,false,false,0,0,false)}
 s.loop={R.GetSet_LoopTimeRange2(project,false,true,0,0,false)}
 s.regions=Core.project_region_selection(project)
 for _,key in ipairs(Core.render_numbers) do s.n[key]=R.GetSetProjectInfo(project,key,0,false) end
 for _,key in ipairs(Core.render_strings) do local ok,v=R.GetSetProjectInfo_String(project,key,'',false);assert(ok,'レンダー設定を取得できません: '..key);s.s[key]=v end
 return s
end
function Core.restore_render(s)
 if not s then return end
 if R.ValidatePtr and not R.ValidatePtr(s.project,'ReaProject*') then return end
 for _,key in ipairs(Core.render_numbers) do R.GetSetProjectInfo(s.project,key,s.n[key],true) end
 for _,key in ipairs(Core.render_strings) do R.GetSetProjectInfo_String(s.project,key,s.s[key],true) end
 -- Work around REAPER sink configuration order sensitivity.
 R.GetSetProjectInfo_String(s.project,'RENDER_FORMAT',s.s.RENDER_FORMAT,true)
 if s.regions then Core.set_project_region_selection(s.project,s.regions) end
 if s.selection_changed then
  R.GetSet_LoopTimeRange2(s.project,true,false,s.selection[1],s.selection[2],false)
  R.GetSet_LoopTimeRange2(s.project,true,true,s.loop[1],s.loop[2],false)
 end
end
function Core.configure_render(project,p,dir,pattern,bits,channels,resolve_region_name)
 assert(bits==16 or bits==24 or bits==32,'ビット深度が不正です。')
 assert(finite(channels) and channels>=1 and channels<=64 and channels%1==0,'チャンネル数が不正です。')
 assert(p.target_row and p.target_row.isr and finite(p.target_row.id),'レンダー対象リージョンが不正です。')
 Core.set_project_region_selection(project,{[floor(p.target_row.id+.5)]=true})
 -- Follow REAPER's native "include project metadata" switch. Other render
 -- mode bits stay under this script's control so the output remains one WAV.
 local native_settings=R.GetSetProjectInfo(project,'RENDER_SETTINGS',0,false)
 -- Region bounds are used only to resolve native region filename wildcards.
 -- Use time selection for audio to bypass custom-bound time text conversion.
 local n={RENDER_SETTINGS=native_settings&512,RENDER_BOUNDSFLAG=resolve_region_name and 5 or 2,RENDER_TAILFLAG=0,RENDER_ADDTOPROJ=0,RENDER_SRATE=p.sr,RENDER_CHANNELS=channels,RENDER_NORMALIZE=0,RENDER_DITHER=0}
 for k,v in pairs(n) do R.GetSetProjectInfo(project,k,v,true) end
 if not resolve_region_name then
  p.render_window=Core.render_window(p);local window=p.render_window
  R.GetSet_LoopTimeRange2(project,true,false,window.start,window.finish,false)
  local first,last=R.GetSet_LoopTimeRange2(project,false,false,0,0,false)
  assert(abs(first-window.start)*p.sr<.01 and abs(last-window.finish)*p.sr<.01,
   'レンダー用の時間選択をサンプル精度で設定できません。時間選択のロックなどを確認してください。')
 end
 -- evaw + depth + flags (force RIFF, no project region embedding) + large-file mode.
 local s={RENDER_FILE=dir,RENDER_PATTERN=pattern,RENDER_FORMAT=Core.base64('evaw'..string.char(bits,2,0)),RENDER_FORMAT2=''}
 for _,k in ipairs(Core.render_strings) do assert(R.GetSetProjectInfo_String(project,k,s[k],true),'レンダー設定を変更できません: '..k) end
 R.GetSetProjectInfo_String(project,'RENDER_FORMAT',s.RENDER_FORMAT,true)
end
function Core.native_format(project)
 local ok,encoded=R.GetSetProjectInfo_String(project,'RENDER_FORMAT','',false)
 assert(ok,'REAPER本体の出力形式を取得できません。')
 local sink=Core.unbase64(encoded or '')
 assert(sink:sub(1,4)=='evaw','REAPER本体の出力形式をWAVに設定してください。')
 local bits=sink:byte(5)
 assert(bits==16 or bits==24 or bits==32,'対応形式はWAV 16/24 bit PCM・32 bit floatです。')
 local sr=R.GetSetProjectInfo(project,'RENDER_SRATE',0,false)
 if sr==0 then
  if R.GetSetProjectInfo(project,'PROJECT_SRATE_USE',0,false)~=0 then sr=R.GetSetProjectInfo(project,'PROJECT_SRATE',0,false)
  elseif R.GetAudioDeviceInfo then local got,value=R.GetAudioDeviceInfo('SRATE');sr=got and tonumber(value) or 0 end
 end
 assert(finite(sr) and sr>=8000 and sr<=384000 and sr%1==0,'標準サンプルレートを解決できません。REAPER本体で明示指定してください。')
 local channels=R.GetSetProjectInfo(project,'RENDER_CHANNELS',0,false)
 assert(finite(channels) and channels>=1 and channels<=64 and channels%1==0,'REAPER本体のチャンネル数が不正です。')
 return {sr=sr,bits=bits,channels=channels}
end
function Core.without_extension(name)
 local base=name:match('^(.*)%.[^%.\\/]+$')
 return base and base:match('[^\\/]+$') and base or name
end
function Core.add_names(kind,name,count,numbering,start,item_ranges,ignore_extension)
 assert(Core.names[kind],'追加する区間種類が不正です。')
 if item_ranges then numbering=false end
 local first,width=1,1
 if numbering then
  assert(type(start)=='string' and start:match('^%d+$') and #start<=12,'開始番号は1〜12桁の数字で指定してください。')
  first=tonumber(start);width=#start;assert(first+count-1<=999999999999,'開始番号が大きすぎます。')
 end
 local names={}
 for i=1,count do
  local text=item_ranges and item_ranges[i].item_name or name
  if item_ranges and ignore_extension then text=Core.without_extension(text) end
  if numbering then text=text..string.format('%0'..width..'d',first+i-1) end
  local raw=(Core.tags[kind] and kind~='region') and (Core.tags[kind]..(text~='' and ' '..text or '')) or text
  if kind=='region' then local k=Core.classify(true,text);if k~='region' then raw=Core.tags.region..' '..text end end
  names[i]=raw
 end
 return names
end
function Core.crossfade_mix(dry,handle,index,count)
 if count<=1 or index>=count-1 then return handle end
 if index<=0 then return dry end
 local theta=math.pi*.5*index/(count-1)
 return dry*math.cos(theta)+handle*math.sin(theta)
end
function Core.crossfade_split_tolerance(sr)
 sr=finite(sr) and sr>0 and sr or 48000
 return max(1e-12,1e-7/sr)
end
function Core.item_effective_channels(item)
 local take=R.GetActiveTake(item);if not take or R.TakeIsMIDI(take) then return nil end
 local source=R.GetMediaItemTake_Source(take);if not source then return nil end
 local channels=optional_number(R.GetMediaSourceNumChannels,source)
 if not channels or channels<1 then return nil end
 local mode=optional_number(R.GetMediaItemTakeInfo_Value,take,'I_CHANMODE') or 0
 if mode==2 or mode==3 or mode==4 then channels=1 end
 return clamp(floor(channels+.5),1,64)
end
function Core.crossfade_channel_count(items,windows,track_channels)
 local cap=finite(track_channels) and clamp(floor(track_channels+.5),1,64) or nil
 local channels=0
 for _,item in ipairs(items or {}) do
  local pos=R.GetMediaItemInfo_Value(item,'D_POSITION');local ending=pos+R.GetMediaItemInfo_Value(item,'D_LENGTH')
  local involved=false
  for _,window in ipairs(windows or {}) do
   if ending>window[1]+1e-9 and pos<window[2]-1e-9 then involved=true;break end
  end
  if involved then channels=max(channels,Core.item_effective_channels(item) or 0) end
 end
 channels=channels>0 and channels or cap or 2
 return cap and min(channels,cap) or channels
end
function Core.crossfade_context(project,rows,items_override)
 local items={}
 if items_override then for _,item in ipairs(items_override) do items[#items+1]=item end
 else for i=0,R.CountSelectedMediaItems(project)-1 do items[#items+1]=R.GetSelectedMediaItem(project,i) end end
 assert(#items>0 and #items<=1000,'音声アイテムを1〜1000個選択してください。')
 local row=Core.loop_target(project,rows,nil,items)
 return row,Core.virtual_loop_items(project,row,items,0)
end
function Core.crossfade_source_range(source,start,frames)
 local first=floor((start-source.s)*source.sr+.5);local last=first+frames-1
 local sample_finish=start+max(0,frames-1)/source.sr
 if source.track_mix then
  assert(start>=source.pos-1e-8 and sample_finish<=source.ending+1e-8,'クロスフェードに必要な仮想トラック素材が足りません。')
  return first
 end
 local available=source.wav and source.wav.frames or floor(source.source_length*source.sr+.5)
 assert(start>=source.pos-1e-8 and sample_finish<=source.ending+1e-8 and first>=0 and last<available,'クロスフェードに必要な素材尺が足りません。')
 return first
end
function Core.crossfade_patch_range(items,start,finish)
 assert(type(items)=='table' and #items>0 and finite(start) and finite(finish) and finish>start,'クロスフェード置換範囲が不正です。')
 local a,b=start,finish;local guard=0
 while true do
  local changed=false;guard=guard+1;assert(guard<=#items*4+4,'クロスフェード置換範囲を確定できません。')
  for _,item in ipairs(items) do
   local pos=R.GetMediaItemInfo_Value(item,'D_POSITION');local ending=pos+R.GetMediaItemInfo_Value(item,'D_LENGTH')
   if ending>a+1e-9 and pos<b-1e-9 then
    local fi=max(0,R.GetMediaItemInfo_Value(item,'D_FADEINLEN') or 0,R.GetMediaItemInfo_Value(item,'D_FADEINLEN_AUTO') or 0)
    local fo=max(0,R.GetMediaItemInfo_Value(item,'D_FADEOUTLEN') or 0,R.GetMediaItemInfo_Value(item,'D_FADEOUTLEN_AUTO') or 0)
    local ranges={{pos,min(ending,pos+fi)},{max(pos,ending-fo),ending}}
    for _,fade in ipairs(ranges) do
     if fade[2]>fade[1]+1e-10 then
      if a>fade[1]+1e-9 and a<fade[2]-1e-9 then a=fade[1];changed=true end
      if b>fade[1]+1e-9 and b<fade[2]-1e-9 then b=fade[2];changed=true end
     end
    end
   end
  end
  if not changed then break end
 end
 local affected={}
 for _,item in ipairs(items) do
  local pos=R.GetMediaItemInfo_Value(item,'D_POSITION');local ending=pos+R.GetMediaItemInfo_Value(item,'D_LENGTH')
  if ending>a+1e-9 and pos<b-1e-9 then affected[#affected+1]=item end
 end
 assert(#affected>0,'クロスフェード置換範囲の音声アイテムがありません。')
 return a,b,affected
end
function Core.crossfade_aligned_patch(items,start,finish,anchor,sr)
 local a,b=start,finish
 for _=1,#items*4+8 do
  local expanded_start,expanded_end,affected=Core.crossfade_patch_range(items,a,b)
  local left_frames=max(1,math.ceil((anchor-expanded_start)*sr-1e-7))
  local aligned_start=anchor-left_frames/sr
  -- Only the start must share the loop-end sample grid. Keep the expanded
  -- right boundary exact; the WAV may contain one trimmed guard frame there.
  if abs(aligned_start-a)<=1e-12 and abs(expanded_end-b)<=1e-12 then return aligned_start,expanded_end,affected end
  a,b=aligned_start,expanded_end
 end
 error('クロスフェード置換範囲をサンプル境界へ整列できません。',0)
end
function Core.crossfade_grid_row(row,sr)
 local aligned={};for k,v in pairs(row) do aligned[k]=v end
 aligned.start=floor(row.start*sr+.5)/sr
 aligned.finish=floor(row.finish*sr+.5)/sr
 return aligned
end
function Core.crossfade_fit(project,rows,seconds,items_override)
 assert(finite(seconds) and seconds>0,'クロスフェード時間を指定してください。')
 local row,items=Core.crossfade_context(project,rows,items_override)
 local source=Core.track_mix_source(project,items)
 row=Core.crossfade_grid_row(row,source.sr)
 local frames=floor((row.finish-row.start)*source.sr+.5);assert(frames>=2,'サステイン区間が2サンプル未満のため、クロスフェードできません。')
 local lower=2/source.sr;local upper=min(frames/source.sr,row.finish-source.pos,row.start-source.pos)
 assert(upper>=lower-1e-12,'ループポイント直前にクロスフェード用の音声が2サンプル以上必要です。')
 return clamp(seconds,lower,upper)
end
function Core.crossfade_plan(project,rows,seconds,items_override)
 assert(finite(seconds) and seconds>0,'クロスフェード時間を指定してください。')
 local row,items=Core.crossfade_context(project,rows,items_override)
 local dry=Core.track_mix_source(project,items);local handle=Core.track_mix_source(project,items)
 local original_row=row;row=Core.crossfade_grid_row(row,dry.sr)
 local sr=dry.sr;local frames=floor((row.finish-row.start)*sr+.5);local fade=floor(seconds*sr+.5)
 assert(fade>=2 and frames>=fade,'ループ尺が足りません。クロスフェード時間はループ長以下、2サンプル以上にしてください。')
 local t=fade/sr;local output_start=row.finish-t;local handle_start=row.start-t
 -- Move the item edge beyond the loop and return smoothly to untouched audio.
 local extension=min(64,max(0,floor((dry.ending-row.finish)*sr+1e-7)),max(0,frames-1))
 local patch_start,patch_end,patch_items=Core.crossfade_aligned_patch(items,output_start,row.finish+extension/sr,row.finish,sr)
 local ch=Core.crossfade_channel_count(items,{{handle_start,row.start},{patch_start,patch_end}},dry.ch)
 dry.ch=ch;handle.ch=ch
 local output_frames=math.ceil((patch_end-patch_start)*sr-1e-7);assert(output_frames>=fade,'クロスフェード置換範囲が不足しています。')
 -- Keep inaudible source padding around the visible replacement. REAPER may
 -- need neighbouring source samples when an item/region boundary falls
 -- between project samples. Without this padding, the resampler can see the
 -- physical beginning/end of the generated WAV and create a one-sample edge.
 local guard_cap=min(Core.CROSSFADE_GUARD_FRAMES,max(0,frames-1))
 local pre_guard=min(guard_cap,max(0,floor((patch_start-dry.pos)*sr+1e-7)))
 local post_role,post_start,post_guard
 if abs(patch_end-row.finish)<=Core.crossfade_split_tolerance(sr) then
  post_role='handle';post_start=row.start
  post_guard=min(guard_cap,max(0,floor((handle.ending-post_start)*sr+1e-7)))
 else
  -- The visible patch contains original audio beyond the loop: continue that audio.
  post_role='dry';post_start=patch_start+output_frames/sr
  post_guard=min(guard_cap,max(0,floor((dry.ending-post_start)*sr+1e-7)))
 end
 local file_frames=pre_guard+output_frames+post_guard
 Core.crossfade_source_range(dry,patch_start-pre_guard/sr,pre_guard+output_frames)
 Core.crossfade_source_range(handle,handle_start,fade)
 if post_guard>0 then Core.crossfade_source_range(post_role=='dry' and dry or handle,post_start,post_guard) end
 local blend_first=floor((output_start-patch_start)*sr+.5)
 local snapshots={};local sources={};local track=dry.track;local fixed_lane,lanes_differ
 for _,item in ipairs(patch_items) do
  assert(R.GetMediaItemInfo_Value(item,'C_LOCK')==0,'クロスフェード置換範囲の音声アイテムがロックされています。')
  local ok,chunk=R.GetItemStateChunk(item,'',false);assert(ok,'アイテムの復元情報を取得できません。')
  snapshots[#snapshots+1]={item=item,track=track,chunk=chunk}
  local lane=optional_number(R.GetMediaItemInfo_Value,item,'I_FIXEDLANE')
  if lane then if fixed_lane~=nil and lane~=fixed_lane then lanes_differ=true else fixed_lane=fixed_lane or lane end end
 end
 local lane_mode=optional_number(R.GetMediaTrackInfo_Value,track,'I_FREEMODE')
 assert(not (lane_mode==2 and lanes_differ),'固定レーンをまたぐクロスフェード重複は、通常の音声アイテムへまとめてから実行してください。')
 for _,item in ipairs(items) do sources[#sources+1]={item=item,track=track,pos=R.GetMediaItemInfo_Value(item,'D_POSITION'),ending=R.GetMediaItemInfo_Value(item,'D_POSITION')+R.GetMediaItemInfo_Value(item,'D_LENGTH')} end
 local fmt=string.pack('<I2I2I4I4I2I2',3,ch,sr,sr*ch*4,ch*4,32);local fmt_chunk=Core.chunk('fmt ',fmt)
 local data_bytes=file_frames*ch*4;assert(4+#fmt_chunk+8+data_bytes+data_bytes%2<=0xffffffff,'4 GiBを超える加工素材には対応していません。')
 return {{item=patch_items[1],track=track,patch_items=patch_items,snapshots=snapshots,sources=sources,dry=dry,handle=handle,s=row.start,e=row.finish,
  loop_start=row.start,loop_finish=row.finish,frames=frames,fade=fade,sr=sr,ch=ch,mode='pre',output_frames=output_frames,
  pre_guard=pre_guard,post_guard=post_guard,file_frames=file_frames,post_role=post_role,post_start=post_start,region=original_row,
  output_start=output_start,handle_start=handle_start,blend_first=blend_first,extension=extension,
  patch_start=patch_start,patch_end=patch_end,fmt_chunk=fmt_chunk,data_bytes=data_bytes,mixed_commit=true,fixed_lane=lane_mode==2 and fixed_lane or nil}}
end
local function cf_close(j)
 for _,role in ipairs({'dry','handle'}) do
  local file=role..'_file';if j[file] then j[file]:close();j[file]=nil end
  local accessor=role..'_accessor';if j[accessor] then R.DestroyAudioAccessor(j[accessor]);j[accessor]=nil end
 end
 if j.source_file then j.source_file:close();j.source_file=nil end
 if j.accessor then R.DestroyAudioAccessor(j.accessor);j.accessor=nil end
 if j.file then j.file:close();j.file=nil end
 j.open_source=nil
end
function Core.crossfade_abort(j)
 if not j then return end
 cf_close(j)
 for _,p in ipairs(j.plans or {}) do
  if p.peak_pending and p.peak_source and R.PCM_Source_BuildPeaks then
   pcall(R.PCM_Source_BuildPeaks,p.peak_source,2)
   p.peak_pending=false
   if p.peak_item and R.UpdateItemInProject then R.UpdateItemInProject(p.peak_item) end
  end
 end
 if not j.committed and not j.commit_started then
  for _,p in ipairs(j.plans) do if p.path then os.remove(p.path) end;if p.temp then os.remove(p.temp) end end
 end
end
function Core.crossfade_start(project,plans,dir)
 local j={project=project,plans=plans,index=1,at=0,done=0,total=0,progress=0,revision=R.GetProjectStateChangeCount(project)}
 for i,p in ipairs(plans) do
  local token=R.genGuid():gsub('[^%w]','');p.path=Core.unique(dir..'/LRM_Loop_'..token..'_'..i..'.wav');p.temp=p.path..'.blt-part'
  assert(not Core.exists(p.temp),'作業ファイルが存在します。');j.total=j.total+(p.file_frames or p.output_frames)
 end
 return j
end
local function cf_open(j,source,role,start,ending)
 if source.track_mix then
  local accessor=assert(R.CreateTrackAudioAccessor(source.track),'トラック合成音声を取得できません。');j[role..'_accessor']=accessor
  assert(R.GetAudioAccessorStartTime(accessor)<=start+1e-8 and R.GetAudioAccessorEndTime(accessor)>=ending-1e-8,'仮想トラック素材の音声範囲を取得できません。')
 elseif source.wav then j[role..'_file']=assert(io.open(source.source_path,'rb'),'元WAVを開けません。')
 else
  local accessor=assert(R.CreateTakeAudioAccessor(source.take),'音声アクセサーを作成できません。');j[role..'_accessor']=accessor
  assert(R.GetAudioAccessorStartTime(accessor)<=start+1e-8 and R.GetAudioAccessorEndTime(accessor)>=ending-1e-8,'素材尺が足りません。必要な音声範囲を取得できません。')
 end
end
local function cf_read(j,source,role,start,n,buffer)
 if source.wav then
  local w=source.wav;local first=floor((start-source.s)*source.sr+.5)
  assert(first>=0 and first+n<=w.frames,'元WAVの読み取り範囲が不正です。')
  local file=j[role..'_file'];assert(file:seek('set',w.data.offset+8+first*w.align))
  local raw=file:read(n*w.align);assert(raw and #raw==n*w.align,'元WAVの音声読み取りに失敗しました。')
  local out={};local bytes=w.bits//8
  local fmt=w.tag==3 and (w.bits==32 and '<f' or '<d') or ('<i'..bytes)
  local scale=w.tag==3 and 1 or 2^(w.bits-1)
  for i=1,n*source.ch do out[i]=string.unpack(fmt,raw,1+(i-1)*bytes)/scale end
  return out
 end
 buffer.clear()
 local accessor=role=='source' and j.accessor or j[role..'_accessor']
 local rc=R.GetAudioAccessorSamples(accessor,source.sr,source.ch,start,n,buffer)
 assert(rc==0 or rc==1,'素材の音声取得に失敗しました。')
 return buffer.table(1,n*source.ch)
end
function Core.crossfade_step(j)
 assert(R.EnumProjects(-1,'')==j.project and R.GetProjectStateChangeCount(j.project)==j.revision,'処理中にプロジェクトが変更されました。やり直してください。')
 local p=j.plans[j.index];if not p then return true end
 local pre_guard=p.pre_guard or 0;local post_guard=p.post_guard or 0
 local file_frames=p.file_frames or (pre_guard+p.output_frames+post_guard)
 if not j.file then
  local patch_start=p.patch_start or p.output_start
  local dry_end=p.patch_end or p.loop_finish
  if p.post_role=='dry' and post_guard>0 then dry_end=max(dry_end,p.post_start+(post_guard-1)/p.sr) end
  cf_open(j,p.dry,'dry',patch_start-pre_guard/p.sr,dry_end)
  cf_open(j,p.handle,'handle',p.handle_start,p.loop_start+max(p.extension or 0,p.post_role=='dry' and 0 or post_guard)/p.sr)
  j.buf=R.new_array(8192*p.ch);j.handle_buf=R.new_array(8192*p.ch)
  j.file=assert(io.open(p.temp,'wb'))
  local bytes=p.data_bytes
  assert(j.file:write('RIFF'..string.pack('<I4',4+#p.fmt_chunk+8+bytes+bytes%2)..'WAVE'..p.fmt_chunk..'data'..string.pack('<I4',bytes)))
 end
 local patch_start=p.patch_start or p.output_start;local n,audio
 if j.at<pre_guard then
  n=min(8192,pre_guard-j.at)
  audio=cf_read(j,p.dry,'dry',patch_start-pre_guard/p.sr+j.at/p.sr,n,j.buf)
 elseif j.at<pre_guard+p.output_frames then
  local visible_at=j.at-pre_guard
  n=min(8192,pre_guard+p.output_frames-j.at)
  audio=cf_read(j,p.dry,'dry',patch_start+visible_at/p.sr,n,j.buf)
  local blend_first=p.blend_first or 0;local local_first=max(0,blend_first-visible_at)
  local local_last=min(n,blend_first+p.fade-visible_at)
  if local_last>local_first then
   local blend_index=visible_at+local_first-blend_first
   local extra=cf_read(j,p.handle,'handle',p.loop_start+(blend_index-p.fade)/p.sr,local_last-local_first,j.handle_buf)
   for frame=local_first,local_last-1 do for ch=1,p.ch do
    local i=frame*p.ch+ch;local extra_i=(frame-local_first)*p.ch+ch
    audio[i]=Core.crossfade_mix(audio[i],extra[extra_i],visible_at+frame-blend_first,p.fade)
   end end
  end
  local ext=p.extension or 0
  if ext>0 then
   local ext_first=blend_first+p.fade
   local a=max(0,ext_first-visible_at);local b=min(n,ext_first+ext-visible_at)
   if b>a then
    local index=visible_at+a-ext_first
    local extra=cf_read(j,p.handle,'handle',p.loop_start+index/p.sr,b-a,j.handle_buf)
    local hold=math.floor(ext/2)
    for frame=a,b-1 do
     local k=visible_at+frame-ext_first
     local weight=k<hold and 1 or (ext-hold<=1 and 0 or .5+.5*math.cos(math.pi*(k-hold)/(ext-hold-1)))
     for ch=1,p.ch do local i=frame*p.ch+ch
      audio[i]=audio[i]*(1-weight)+extra[(frame-a)*p.ch+ch]*weight
     end
    end
   end
  end
 else
  local post_at=j.at-pre_guard-p.output_frames
  n=min(8192,file_frames-j.at)
  local role=p.post_role or 'handle'
  audio=cf_read(j,role=='dry' and p.dry or p.handle,role,(p.post_start or p.loop_start)+post_at/p.sr,n,role=='dry' and j.buf or j.handle_buf)
 end
 local fmt='<f';local scale=nil
 local packed={}
 for i,v in ipairs(audio) do
  assert(finite(v),'素材に不正な音声値があります。')
  if scale then v=clamp(floor(v*scale+.5),-scale,scale-1) end
  packed[i]=string.pack(fmt,v)
 end
 assert(j.file:write(table.concat(packed)));j.at=j.at+n;j.done=j.done+n;j.progress=j.done/j.total
 if j.at==file_frames then
  if p.data_bytes%2==1 then assert(j.file:write('\0')) end
  assert(j.file:flush());cf_close(j)
  local check=Core.scan(p.temp);assert(check.frames==file_frames and check.channels==p.ch and check.sr==p.sr,'加工音声の検証に失敗しました。')
  assert(not Core.exists(p.path) and os.rename(p.temp,p.path),'ループ音声を保存できません。');p.temp=nil
  j.index=j.index+1;j.at=0
 end
 return j.index>#j.plans
end
function Core.crossfade_commit(j)
 assert(R.EnumProjects(-1,'')==j.project and R.GetProjectStateChangeCount(j.project)==j.revision,'プロジェクトが変更されました。')
 local has_mixed=false
 for _,p in ipairs(j.plans) do
  if p.mixed_commit then
   has_mixed=true
   for _,snapshot in ipairs(p.snapshots or {}) do
    local ok,chunk=R.GetItemStateChunk(snapshot.item,'',false);assert(ok and chunk==snapshot.chunk,'クロスフェード対象のアイテムが変更されました。')
   end
  else
   local ok,chunk=R.GetItemStateChunk(p.item,'',false);assert(ok and chunk==p.chunk,'アイテムが変更されました。')
  end
 end
 if has_mixed then assert(type(R.Undo_DoUndo2)=='function','安全なクロスフェード置換に必要なUndo APIを利用できません。') end
 local undo_flags=4
 j.commit_started=true;R.Undo_BeginBlock2(j.project)
 local created={}
 local function split(item,at)
  local right=assert(R.SplitMediaItem(item,at),'アイテムの分割に失敗しました。')
  created[#created+1]={item=right,track=R.GetMediaItemTrack(right)}
  return right
 end
 local function clear_edge(item,edge)
  for _,k in ipairs({'D_FADE'..edge..'LEN','D_FADE'..edge..'LEN_AUTO'}) do
   assert(R.SetMediaItemInfo_Value(item,k,0),'分割端のフェードを更新できません。')
  end
 end
 local ok,err=xpcall(function()
 for _,p in ipairs(j.plans) do
  local split_tolerance=Core.crossfade_split_tolerance(p.sr)
  local source=assert(R.PCM_Source_CreateFromFile(p.path),'加工素材を読み込めません。')
   local middle
   if p.mixed_commit then
    local remove={};p.result_items={};j.commit_mutated=true
    for _,snapshot in ipairs(p.snapshots) do
     local item=snapshot.item;local pos=R.GetMediaItemInfo_Value(item,'D_POSITION')
     local ending=pos+R.GetMediaItemInfo_Value(item,'D_LENGTH');middle=item
     if p.patch_end<ending-split_tolerance then
      local right=split(middle,p.patch_end);p.result_items[#p.result_items+1]=right
      clear_edge(right,'IN')
     end
     if p.patch_start>pos+split_tolerance then
      middle=split(middle,p.patch_start);p.result_items[#p.result_items+1]=item
      clear_edge(item,'OUT');clear_edge(middle,'IN')
     end
     remove[#remove+1]=middle
    end
    middle=assert(R.AddMediaItemToTrack(p.track),'加工音声用のアイテムを作成できません。')
    created[#created+1]={item=middle,track=p.track};p.result_items[#p.result_items+1]=middle
    assert(R.SetMediaItemInfo_Value(middle,'D_POSITION',p.patch_start),'加工アイテムの位置を設定できません。')
    assert(R.SetMediaItemInfo_Value(middle,'D_LENGTH',p.patch_end-p.patch_start),'加工アイテムの長さを設定できません。')
    assert(R.SetMediaItemInfo_Value(middle,'D_VOL',1),'加工アイテムの音量を設定できません。')
    assert(R.SetMediaItemInfo_Value(middle,'B_LOOPSRC',0),'加工素材のループ設定を更新できません。')
    if p.fixed_lane~=nil then assert(R.SetMediaItemInfo_Value(middle,'I_FIXEDLANE',p.fixed_lane),'加工アイテムの固定レーンを設定できません。') end
    clear_edge(middle,'IN');clear_edge(middle,'OUT')
    local take=assert(R.AddTakeToMediaItem(middle),'加工音声用のテイクを作成できません。')
    R.SetMediaItemTake_Source(take,source);assert(R.GetMediaItemTake_Source(take)==source,'加工素材を適用できません。')
    for key,value in pairs({D_STARTOFFS=(p.pre_guard or 0)/p.sr,D_VOL=1,D_PAN=0,D_PLAYRATE=1,D_PITCH=0}) do
     assert(R.SetMediaItemTakeInfo_Value(take,key,value),'加工テイクの再生設定を更新できません。')
    end
    for _,item in ipairs(remove) do assert(R.DeleteTrackMediaItem(p.track,item),'置換前の重複音声を取り除けません。') end
    if R.SetMediaItemSelected then R.SetMediaItemSelected(middle,true) end
   else
    middle=p.item;p.result_items={p.item}
    if p.patch_end<p.ending-split_tolerance then
     local right=split(middle,p.patch_end);p.result_items[#p.result_items+1]=right
     clear_edge(middle,'OUT');clear_edge(right,'IN')
    end
    if p.patch_start>p.pos+split_tolerance then
     middle=split(middle,p.patch_start);p.result_items[#p.result_items+1]=middle
     clear_edge(p.item,'OUT');clear_edge(middle,'IN')
    end
    local take=assert(R.GetActiveTake(middle),'加工区間のテイクを取得できません。')
    R.SetMediaItemTake_Source(take,source);assert(R.GetMediaItemTake_Source(take)==source,'加工素材を適用できません。')
    assert(R.SetMediaItemTakeInfo_Value(take,'D_STARTOFFS',(p.pre_guard or 0)/p.sr),'加工素材の開始位置を更新できません。')
    assert(R.SetMediaItemInfo_Value(middle,'B_LOOPSRC',0),'加工素材のループ設定を更新できません。')
   end
   if p.region and (p.region.start~=p.loop_start or p.region.finish~=p.loop_finish) then
    undo_flags=undo_flags|8
    assert(R.SetProjectMarker3(j.project,p.region.id,true,p.loop_start,p.loop_finish,p.region.raw,p.region.color),'サステインのサンプル位置を更新できません。')
   end
   p.peak_source=source;p.peak_item=middle
   p.peak_pending=R.PCM_Source_BuildPeaks and R.PCM_Source_BuildPeaks(source,0)~=0 or false
   if R.UpdateItemInProject then R.UpdateItemInProject(middle) end
 end
 end,debug.traceback)
 local rollback_complete=false
 if not ok then
  -- Finish any peak-builder begun for a source before restoring/deleting the
  -- take that owns it; the source pointer may no longer be valid afterwards.
  for _,p in ipairs(j.plans) do if p.peak_pending and p.peak_source then
   pcall(R.PCM_Source_BuildPeaks,p.peak_source,2);p.peak_pending=false
  end end
  if not has_mixed then
   local failed=false
   for i=#created,1,-1 do
    local c=created[i];if not R.DeleteTrackMediaItem(c.track,c.item) then failed=true end
   end
   for _,p in ipairs(j.plans) do if not R.SetItemStateChunk(p.item,p.chunk,false) then failed=true end end
   if failed then err=err..'\n一部のアイテムを復元できませんでした。REAPERのUndoで処理を戻してください。' end
   rollback_complete=not failed
  end
 end
 R.Undo_EndBlock2(j.project,'BLT LOOP RM STUDIO: クロスフェードループ',undo_flags)
 if not ok and has_mixed and j.commit_mutated then
  local called,result=pcall(R.Undo_DoUndo2,j.project);local restored=called and result~=0
  if not restored then err=err..'\n処理前のアイテムを自動復元できませんでした。REAPERのUndoを実行してください。' end
  rollback_complete=restored
 end
 if not ok and has_mixed and not j.commit_mutated then rollback_complete=true end
 R.UpdateArrange()
 if not ok then if rollback_complete then j.commit_started=false end;error(err,0) end
 j.committed=true
end
function Core.crossfade_peaks_step(j)
 assert(j and j.committed,'クロスフェード素材がまだ適用されていません。')
 j.peak_index=j.peak_index or 1
 while j.peak_index<=#j.plans do
  local p=j.plans[j.peak_index]
  if p.peak_pending then
   local remaining=R.PCM_Source_BuildPeaks(p.peak_source,1)
   assert(type(remaining)=='number' and remaining>=0,'生成素材の波形ピークを構築できません。')
   if remaining~=0 then return false end
   R.PCM_Source_BuildPeaks(p.peak_source,2);p.peak_pending=false
   if p.peak_item and R.UpdateItemInProject then R.UpdateItemInProject(p.peak_item) end
  end
  j.peak_index=j.peak_index+1
 end
 R.UpdateArrange()
 return true
end

-- Shared bounded audio reader for non-destructive loop analysis.
function Core.loop_audio_read(j,source,start,n,buffer)
 return cf_read(j,source,'source',start,n,buffer)
end
Core.loop_audio_close=cf_close

-- Non-destructive region adjustment. Read only endpoint windows (zero crossing)
-- or the loop plus a short margin (rhythmic period), never the whole source.
function Core.near_zero(audio,ch,first,target,sr,direction)
 local n=#audio//ch;local energy=0
 for _,v in ipairs(audio) do assert(finite(v),'音声に不正な値があります。');energy=energy+v*v end
 energy=energy/max(1,#audio)
 assert(energy>1e-14,'ゼロクロスを判定できません。対象付近が無音です。')
 local best,bestscore
 for f=1,n-1 do
  local crossing=false;local before,after=0,0
  for c=1,ch do
   local a,b=audio[(f-1)*ch+c],audio[f*ch+c]
   if a*b<=0 and abs(a-b)>1e-10 then crossing=true end
   before=before+a*a;after=after+b*b
  end
  if crossing then
   local k=after<before and f or f-1
   local distance=abs(first+k-target)
   -- All channels share one boundary. Other-channel residual energy matters,
   -- so antiphase stereo cannot falsely look like silence through mono summing.
   local allowed=not direction or direction*(first+k-target)>0
   local score=direction and (distance+min(before,after)/(ch*energy)*.001) or (min(before,after)/(ch*energy)+.15*distance/max(1,.020*sr))
   if allowed and (not bestscore or score<bestscore) then best,bestscore=first+k,score end
  end
 end
 assert(best,direction and '指定方向の100 ms以内に次のゼロクロスが見つかりませんでした。' or '前後20 ms以内にゼロクロスが見つかりませんでした。')
 return best
end

function Core.period_analysis_window(start,finish,available_start,available_end)
 assert(finite(start) and finite(finish) and finite(available_start) and finite(available_end)
  and available_start<=start+1e-7 and finish<=available_end+1e-7 and finish>start,'周期解析範囲が不正です。')
 local duration=finish-start
 assert(duration<=Core.PERIOD_ANALYSIS_MAX+1e-9,'100秒を超えるサステインは周期解析できません。')
 local target=clamp(duration*3,Core.PERIOD_ANALYSIS_MIN,Core.PERIOD_ANALYSIS_MAX)
 local margin=(target-duration)/2
 local wanted_start,wanted_end=start-margin,finish+margin
 if wanted_start<available_start then
  wanted_end=min(available_end,wanted_end+available_start-wanted_start);wanted_start=available_start
 end
 if wanted_end>available_end then
  wanted_start=max(available_start,wanted_start-(wanted_end-available_end));wanted_end=available_end
 end
 return wanted_start,wanted_end,target
end

function Core.period_fit(features,rate,start,finish,lo,hi,allow_empty)
 local n=#features;if n<60 then error(Core.PERIOD_FAILURE..'周期解析には少なくとも0.6秒程度の音声が必要です。',0) end
 local channels={}
 for field=1,2 do
  local mean,var=0,0
  for _,v in ipairs(features) do mean=mean+v[field] end;mean=mean/n
  for _,v in ipairs(features) do var=var+(v[field]-mean)^2 end
  local sd=math.sqrt(var/n)
  if sd>1e-7 and sd/max(abs(mean),1e-9)>.05 then
   local values={};for i,v in ipairs(features) do values[i]=(v[field]-mean)/sd end
   local smooth={}
   for i=1,n do smooth[i]=(values[max(1,i-1)]+values[i]+values[min(n,i+1)])/3 end
   channels[#channels+1]=smooth
  end
 end
 if #channels==0 then error(Core.PERIOD_FAILURE..'明確なリズム周期を検出できませんでした。',0) end
 local minlag=max(3,floor(.12*rate));local maxlag=min(floor(5*rate),floor(n/3))
 local correlation={};local peak=-1
 for lag=minlag-1,maxlag+1 do
  local ab,aa,bb=0,0,0
  for _,values in ipairs(channels) do for i=1,n-lag do
   local a,b=values[i],values[i+lag];ab=ab+a*b;aa=aa+a*a;bb=bb+b*b
  end end
  correlation[lag]=ab/math.sqrt(max(1e-20,aa*bb))
 end
 for lag=minlag,maxlag do
  if correlation[lag]>=correlation[lag-1] and correlation[lag]>correlation[lag+1] then peak=max(peak,correlation[lag]) end
 end
 if peak<.65 then error(Core.PERIOD_FAILURE..'安定した周期を検出できませんでした。',0) end
 local lag
 for i=minlag,maxlag do
  if correlation[i]>=max(.65,peak-.04) and correlation[i]>=correlation[i-1] and correlation[i]>correlation[i+1] then lag=i;break end
 end
 if not lag then error(Core.PERIOD_FAILURE..'周期候補を絞り込めませんでした。',0) end
 -- Fold the strongest repeating feature over a cycle; its averaged maximum
 -- provides a consistent phase for both region edges.
 local bestvalue,bestphase=-math.huge,0
 for _,values in ipairs(channels) do for phase=0,lag-1 do
  local sum,count=0,0
  for i=phase+1,n,lag do sum=sum+values[i];count=count+1 end
  if sum/count>bestvalue then bestvalue,bestphase=sum/count,phase end
 end end
 local period=lag/rate;local anchor=lo+(bestphase+.5)/rate
 local function snap(t)
  local k=floor((t-anchor)/period+.5)
  k=clamp(k,math.ceil((lo-anchor)/period),floor((hi-anchor)/period))
  return anchor+k*period
 end
 local s,e=snap(start),snap(finish)
 if not allow_empty and e<=s then error(Core.PERIOD_FAILURE..'周期に合わせると区間がなくなります。長めのサステインを指定してください。',0) end
 return s,e,period,correlation[lag],anchor
end

function Core.loop_adjust_start(project,rows,mode,edge,direction,items_override,relative)
 assert(mode=='zero' or mode=='period' or mode=='preview','解析方法が不正です。')
 assert(not edge or (edge=='start' or edge=='finish') and (direction==1 or direction==-1),'移動方向が不正です。')
 local count=items_override and #items_override or R.CountSelectedMediaItems(project)
 assert(count>0 and count<=1000,'音声アイテムを選択してください。')
 local j={project=project,revision=R.GetProjectStateChangeCount(project),plans={},index=1,window=1,at=0,done=0,total=0,mode=mode,edge=edge,direction=direction,relative=relative==true and edge~=nil}
 local target_row=#rows==1 and rows[1].kind=='sustain' and rows[1] or nil
 local blocks,by_row={},{}
 for i=0,count-1 do
  local item=items_override and items_override[i+1] or R.GetSelectedMediaItem(project,i)
  local pos=R.GetMediaItemInfo_Value(item,'D_POSITION');local length=R.GetMediaItemInfo_Value(item,'D_LENGTH')
  assert(finite(pos) and finite(length) and length>0,'選択アイテムの位置または長さが不正です。')
  local ending=pos+length;local row=target_row
  if not row then for _,r in ipairs(rows) do if r.kind=='sustain' and r.start<ending and r.finish>pos then
   assert(not row,'選択アイテムに複数のサステインが重なっています。対象を分けて選択してください。');row=r
  end end end
  assert(row,'選択アイテムと重なるサステインがありません。')
  local key=row.key or tostring(row);local g=by_row[key]
  if not g then g={row=row,items={}};by_row[key]=g;blocks[#blocks+1]=g end
  g.items[#g.items+1]={item=item,pos=pos,ending=ending}
 end
 table.sort(blocks,function(a,b) return a.row.start==b.row.start and a.row.finish<b.row.finish or a.row.start<b.row.start end)
 local function plan_for(block)
  local sources,source_items,track={},{},nil
  for _,entry in ipairs(block.items) do
   local take=R.GetActiveTake(entry.item);assert(take and not R.TakeIsMIDI(take),'音声アイテムを選択してください。')
   local item_track=R.GetMediaItem_Track(entry.item)
   assert(not track or track==item_track,'同じループを構成する音声アイテムは同じトラックから選択してください。')
   track=track or item_track
   sources[#sources+1]={item=entry.item,take=take,track=item_track,pos=entry.pos,ending=entry.ending}
   source_items[#source_items+1]=entry.item
  end
  table.sort(sources,function(a,b) return a.pos==b.pos and a.ending>b.ending or a.pos<b.pos end)
  local min_time,max_time=sources[1].pos,sources[1].ending;local right_source=sources[1]
  for i=2,#sources do
   local source=sources[i]
   assert(source.pos<=max_time+1e-7,'サステイン上の選択アイテム間に隙間があります。連続するアイテムを選択してください。')
   if source.ending>max_time then max_time=source.ending;right_source=source end
  end
  local mix=Core.track_mix_source(project,source_items);local first=sources[1];local row=block.row
  local p={item=first.item,take=first.take,row=row,s=mix.s,sr=mix.sr,ch=mix.ch,lo=mix.lo,hi=mix.hi,audio_source=mix,
   sources=sources,left_source=first,right_source=right_source,snapshots={},windows={},features={},bin_sum=0,bin_cross=0,bin_count=0,previous={},min_time=min_time,max_time=max_time}
  for _,source in ipairs(sources) do
   p.snapshots[#p.snapshots+1]={item=source.item,take=source.take,pos=source.pos,ending=source.ending,startoffs=R.GetMediaItemTakeInfo_Value(source.take,'D_STARTOFFS')}
  end
  assert(row.start>=p.min_time-1e-7,'サステイン開始を覆う音声アイテムも選択してください。')
  assert(row.finish<=p.max_time+1e-7,'サステイン終了を覆う音声アイテムも選択してください。')
  return p
 end
 for _,block in ipairs(blocks) do
  local p=plan_for(block);local row=p.row
  if mode=='zero' then
   for _,which in ipairs(edge and {edge} or {'start','finish'}) do
    local t=which=='start' and row.start or row.finish;local source=p.audio_source
    local target=floor((t-source.s)*source.sr+.5);target=clamp(target,source.lo,source.hi)
    local radius=floor((direction and .1 or .02)*source.sr)
    local first=max(source.lo,target-radius);local last=min(source.hi,target+radius+2)
    assert(last-first>=2,'境界付近にゼロクロス解析用の音声が足りません。')
    p.windows[#p.windows+1]={first=first,last=last,target=target,edge=which,audio={},source=source}
   end
  elseif mode=='preview' then
   local source=p.audio_source
   local sf=floor((row.start-source.s)*source.sr+.5);local ef=floor((row.finish-source.s)*source.sr+.5)
   assert(sf>=source.lo-1 and ef<=source.hi+1,'プレビュー範囲が仮想トラック素材の外です。')
   sf,ef=clamp(sf,source.lo,source.hi),clamp(ef,source.lo,source.hi)
   -- Cache the full drag range once; drawing still visits only visible samples.
   local view=math.ceil(Core.SEAM_SECONDS*source.sr)
   local guard=math.ceil(Core.SEAM_DRAG_SECONDS*source.sr)+1
   p.windows={{first=max(source.lo,ef-view-guard),last=min(source.hi,ef+guard),audio={},edge='finish',source=source},
    {first=max(source.lo,sf-guard),last=min(source.hi,sf+view+guard),audio={},edge='start',source=source}}
  else
   local source=p.audio_source
   local wanted_start,wanted_end=Core.period_analysis_window(row.start,row.finish,p.min_time,p.max_time)
   local first=max(source.lo,floor((wanted_start-source.s)*source.sr+.5))
   local last=min(source.hi,floor((wanted_end-source.s)*source.sr+.5))
   if last>first then
    p.windows[1]={first=first,last=last,source=source}
    p.analysis_start=source.s+first/source.sr;p.analysis_end=source.s+last/source.sr
   end
   assert(#p.windows>0 and p.analysis_start<=row.start+1/p.sr and p.analysis_end>=row.finish-1/p.sr,'周期解析範囲を選択アイテムで覆えていません。')
   assert(p.analysis_end-p.analysis_start<=Core.PERIOD_ANALYSIS_MAX+2/p.sr,'周期解析範囲が100秒を超えています。')
   p.bin_size=max(1,floor(p.sr/100+.5));p.feature_rate=p.sr/p.bin_size
  end
  for _,w in ipairs(p.windows) do j.total=j.total+w.last-w.first end
  j.plans[#j.plans+1]=p
 end
 return j
end

function Core.loop_align_time(p,t,which)
 if p.audio_source and p.audio_source.track_mix then
  local source=p.audio_source
  return source.s+floor((t-source.s)*source.sr+.5)/source.sr
 end
 local chosen,closest,distance
 for _,source in ipairs(p.sources or {p}) do
  local contains=which=='start' and t>=source.pos-1e-8 and t<source.ending-1e-8 or which=='finish' and t>source.pos+1e-8 and t<=source.ending+1e-8
  local d=t<source.pos and source.pos-t or t>source.ending and t-source.ending or 0
  if contains then chosen=source;break end
  if not distance or d<distance then closest,distance=source,d end
 end
 chosen=chosen or closest or p
 return chosen.s+floor((t-chosen.s)*chosen.sr+.5)/chosen.sr
end

function Core.loop_extension_items(project,p,new_start,new_end,relative)
 assert(finite(new_start) and finite(new_end) and new_end>new_start,'調整後のサステイン区間が短すぎます。')
 local additions,seen={},{}
 local function add(item)
  if not seen[item] then seen[item]=true;additions[#additions+1]=item end
 end
 for _,source in ipairs(p.sources or {}) do if source.item then seen[source.item]=true end end
 local function extend(side,target)
  local left=side=='left';local cursor=left and p.min_time or p.max_time
  if (left and target>=cursor-1e-9) or ((not left) and target<=cursor+1e-9) then return cursor,true end
  local sources=p.sources or {}
  local boundary=left and (p.left_source or sources[1]) or (p.right_source or sources[#sources])
  local track=boundary and (boundary.track or boundary.item and R.GetMediaItem_Track(boundary.item))
  assert(track,'移動先を探す基準トラックを取得できません。')
  local guard=0
  while (left and target<cursor-1e-9) or ((not left) and target>cursor+1e-9) do
   local found={};local next_cursor=cursor
   for i=0,R.CountTrackMediaItems(track)-1 do
    local item=R.GetTrackMediaItem(track,i);local pos=R.GetMediaItemInfo_Value(item,'D_POSITION')
    local ending=pos+R.GetMediaItemInfo_Value(item,'D_LENGTH')
    local connected=not seen[item] and ((left and ending>=cursor-1e-7 and pos<cursor-1e-9)
      or ((not left) and pos<=cursor+1e-7 and ending>cursor+1e-9))
    if connected then
     local take=R.GetActiveTake(item)
     if take and not R.TakeIsMIDI(take) then
      found[#found+1]={item=item,pos=pos,ending=ending}
      next_cursor=left and min(next_cursor,pos) or max(next_cursor,ending)
     end
    end
   end
   if #found==0 then return cursor,false end
   for _,entry in ipairs(found) do add(entry.item) end
   guard=guard+#found;assert(guard<=1000,'移動先のアイテムが多すぎます。')
   assert(left and next_cursor<cursor-1e-9 or not left and next_cursor>cursor+1e-9,'移動先の音声範囲を延長できません。')
   cursor=next_cursor
  end
  return cursor,true
 end
 local left_limit,left_complete=extend('left',new_start)
 local right_limit,right_complete=extend('right',new_end)
 local limited=not left_complete or not right_complete
 if relative then
  local shift=new_start-p.row.start
  if shift<0 and not left_complete then shift=left_limit-p.row.start
  elseif shift>0 and not right_complete then shift=right_limit-p.row.finish end
  new_start=p.row.start+shift;new_end=p.row.finish+shift
 else
  if not left_complete then new_start=left_limit end
  if not right_complete then new_end=right_limit end
 end
 assert(new_end>new_start+1e-10,'選択アイテム内に有効なループ範囲を確保できません。')
 return additions,new_start,new_end,limited
end

function Core.loop_adjust_step(j)
 assert(R.EnumProjects(-1,'')==j.project and R.GetProjectStateChangeCount(j.project)==j.revision,'解析中にプロジェクトが変更されました。やり直してください。')
 local p=j.plans[j.index];if not p then return true end
 local w=p.windows[j.window];local source=w.source or p
 if j.open_source~=source then
  Core.loop_audio_close(j);j.open_source=source
  if source.track_mix then
   j.accessor=assert(R.CreateTrackAudioAccessor(source.track),'トラック合成音声を取得できません。');j.buf=R.new_array(8192*source.ch)
   local a,b=R.GetAudioAccessorStartTime(j.accessor),R.GetAudioAccessorEndTime(j.accessor)
   assert(source.s+w.first/source.sr>=a-1e-8 and source.s+w.last/source.sr<=b+1e-8,'仮想トラック素材の解析範囲を取得できません。')
  elseif source.wav then j.source_file=assert(io.open(source.source_path,'rb'),'元WAVを開けません。')
  else
   j.accessor=assert(R.CreateTakeAudioAccessor(source.take),'音声を取得できません。');j.buf=R.new_array(8192*source.ch)
   local a,b=R.GetAudioAccessorStartTime(j.accessor),R.GetAudioAccessorEndTime(j.accessor)
   assert(source.s+w.first/source.sr>=a-1e-8 and source.s+w.last/source.sr<=b+1e-8,'解析範囲の音声を取得できません。')
  end
 end
 local n=min(8192,w.last-w.first-j.at)
 local audio=Core.loop_audio_read(j,source,source.s+(w.first+j.at)/source.sr,n,j.buf)
 if j.mode=='zero' then
  for _,v in ipairs(audio) do assert(finite(v),'音声に不正な値があります。');w.audio[#w.audio+1]=v end
 elseif j.mode=='preview' then
  local draw_ch=min(2,source.ch);w.draw_ch=draw_ch
  for f=0,n-1 do for c=1,draw_ch do
   local v=audio[f*source.ch+c]
   assert(finite(v),'音声に不正な値があります。');w.audio[#w.audio+1]=v
  end end
 else
  for f=0,n-1 do
   for c=1,p.ch do
    local v=audio[f*p.ch+c];assert(finite(v),'音声に不正な値があります。')
    p.bin_sum=p.bin_sum+v*v
    if p.previous[c] and p.previous[c]*v<0 then p.bin_cross=p.bin_cross+1 end
    p.previous[c]=v
   end
   p.bin_count=p.bin_count+1
   if p.bin_count==p.bin_size then
    p.features[#p.features+1]={math.sqrt(p.bin_sum/(p.bin_count*p.ch)),p.bin_cross/(p.bin_count*p.ch)}
    p.bin_sum,p.bin_cross,p.bin_count=0,0,0
   end
  end
 end
 j.at=j.at+n;j.done=j.done+n;j.progress=j.done/max(1,j.total)
 if j.at==w.last-w.first then
  if j.mode=='zero' then w.result=Core.near_zero(w.audio,source.ch,w.first,w.target,source.sr,j.direction);w.audio=nil end
  j.at=0;j.window=j.window+1
  if j.window>#p.windows then
   if j.mode=='zero' then
    p.new_start,p.new_end=p.row.start,p.row.finish
    for _,window in ipairs(p.windows) do
     local src=window.source or p;local result_time=src.s+window.result/src.sr
     if window.edge=='start' then p.new_start=result_time else p.new_end=result_time end
    end
    if j.relative then
     local duration=p.row.finish-p.row.start
     if j.edge=='start' then p.new_end=p.new_start+duration else p.new_start=p.new_end-duration end
    end
   elseif j.mode=='period' then
    local a,b,period,confidence,anchor=Core.period_fit(p.features,p.feature_rate,p.row.start,p.row.finish,p.analysis_start,p.analysis_end,j.edge~=nil)
    if j.edge then
     local t=j.edge=='start' and p.row.start or p.row.finish
     local phase=(t-anchor)/period;local nearest=floor(phase+.5)
     local tolerance=max(1/p.sr,2/p.feature_rate)/period
     local k
     if abs(phase-nearest)<=tolerance then k=nearest+j.direction
     else k=j.direction==1 and floor(phase)+1 or math.ceil(phase)-1 end
     a,b=p.row.start,p.row.finish
     if j.edge=='start' then a=anchor+k*period else b=anchor+k*period end
    end
    p.new_start=Core.loop_align_time(p,a,'start');p.new_end=Core.loop_align_time(p,b,'finish')
    if j.edge then
     if j.relative then
      local duration=p.row.finish-p.row.start
      if j.edge=='start' then p.new_end=p.new_start+duration else p.new_start=p.new_end-duration end
     elseif j.edge=='start' then p.new_end=p.row.finish else p.new_start=p.row.start end
    end
    p.period,p.confidence=period,confidence;p.features=nil
   end
   if j.mode~='preview' then
    p.auto_select,p.new_start,p.new_end,p.limited=Core.loop_extension_items(j.project,p,p.new_start,p.new_end,j.relative)
   end
   Core.loop_audio_close(j);j.index=j.index+1;j.window=1
  end
 end
 return j.index>#j.plans
end

function Core.loop_adjust_commit(j)
 assert(R.EnumProjects(-1,'')==j.project and R.GetProjectStateChangeCount(j.project)==j.revision,'プロジェクトが変更されました。')
 for _,p in ipairs(j.plans) do
  for _,snapshot in ipairs(p.snapshots or {{item=p.item,take=p.take}}) do
   if R.ValidatePtr2 then assert(R.ValidatePtr2(j.project,snapshot.item,'MediaItem*'),'解析したアイテムが削除されました。') end
   assert(R.GetActiveTake(snapshot.item)==snapshot.take,'解析したアイテムのアクティブテイクが変更されました。')
   if snapshot.pos then
    local pos=R.GetMediaItemInfo_Value(snapshot.item,'D_POSITION');local ending=pos+R.GetMediaItemInfo_Value(snapshot.item,'D_LENGTH')
    assert(abs(pos-snapshot.pos)<1e-12 and abs(ending-snapshot.ending)<1e-12 and abs(R.GetMediaItemTakeInfo_Value(snapshot.take,'D_STARTOFFS')-snapshot.startoffs)<1e-12,'解析したアイテムの位置または素材範囲が変更されました。')
   end
  end
 end
 R.Undo_BeginBlock2(j.project)
 local ok,err=xpcall(function()
  for _,p in ipairs(j.plans) do local r=p.row
   assert(R.SetProjectMarker3(j.project,r.id,true,p.new_start,p.new_end,r.raw,r.color),'サステインの更新に失敗しました。')
  end
  local selected={};j.auto_selected_count=0
  for _,p in ipairs(j.plans) do for _,item in ipairs(p.auto_select or {}) do if not selected[item] then
   selected[item]=true
   if not R.IsMediaItemSelected or not R.IsMediaItemSelected(item) then j.auto_selected_count=j.auto_selected_count+1 end
   R.SetMediaItemSelected(item,true)
  end end end
 end,debug.traceback)
 if not ok then
  local restored=true
  for _,p in ipairs(j.plans) do local r=p.row
   if not R.SetProjectMarker3(j.project,r.id,true,r.start,r.finish,r.raw,r.color) then restored=false end
  end
  if not restored then err=err..'\n一部を復元できませんでした。REAPERのUndoで戻してください。' end
 end
 R.Undo_EndBlock2(j.project,'BLT LOOP RM STUDIO: '..(j.mode=='zero' and 'ゼロクロスへ調整' or '周期へ調整'),4|8);R.UpdateArrange()
 if not ok then error(err,0) end
end

function Core.wave_selection_memory(current,signature,remembered,last_signature)
 current=current or {};remembered=remembered or {}
 if #current>0 and signature~=last_signature then return current,signature end
 return remembered,last_signature
end
function Core.wave_plan_memory_items(plans)
 local items={}
 for _,p in ipairs(plans or {}) do
  for _,item in ipairs(p.auto_select or {}) do items[#items+1]=item end
  for _,item in ipairs(p.result_items or {}) do items[#items+1]=item end
 end
 return items
end
function Core.undo_shortcut(key,modifiers)
 modifiers=modifiers or 0
 if (modifiers&8)~=0 then return false end
 return key==26 or (modifiers&4)~=0 and (key==90 or key==122)
end

function Core.loop_target(project,rows,selected_key,items_override)
 local items={}
 if items_override then for _,item in ipairs(items_override) do items[#items+1]=item end
 else for i=0,R.CountSelectedMediaItems(project)-1 do items[#items+1]=R.GetSelectedMediaItem(project,i) end end
 assert(#items>0,'アイテムが選択されていません')
 local row
 if selected_key then
  for _,r in ipairs(rows) do if r.key==selected_key and r.kind=='sustain' then row=r;break end end
  assert(row,'操作中のループリージョンが見つかりません。')
 else
  -- Treat only genuinely covered item spans as candidates. A global minimum /
  -- maximum would turn gaps and separate tracks into imaginary audio, allowing
  -- unrelated nearby sustain regions to be counted.
  local by_track={}
  for _,item in ipairs(items) do
   local a=R.GetMediaItemInfo_Value(item,'D_POSITION');local b=a+R.GetMediaItemInfo_Value(item,'D_LENGTH')
   local track=R.GetMediaItem_Track(item)
   if track and finite(a) and finite(b) and b>a then
    local spans=by_track[track];if not spans then spans={};by_track[track]=spans end
    spans[#spans+1]={start=a,finish=b}
   end
  end
  local components={}
  for _,spans in pairs(by_track) do
   table.sort(spans,function(a,b) return a.start==b.start and a.finish>b.finish or a.start<b.start end)
   local component
   for _,span in ipairs(spans) do
    if not component or span.start>component.finish+1e-7 then
     component={start=span.start,finish=span.finish};components[#components+1]=component
    else component.finish=max(component.finish,span.finish) end
   end
  end
  local matches={}
  for _,r in ipairs(rows) do
   if r.kind=='sustain' then for _,component in ipairs(components) do
    if r.start>=component.start-1e-8 and r.finish<=component.finish+1e-8 then matches[#matches+1]=r;break end
   end end
  end
  assert(#matches>0,'選択アイテム範囲に収まるループリージョンがありません')
  assert(#matches==1,'選択アイテム範囲にループリージョンが複数存在しています！')
  row=matches[1]
 end
 return row,items
end

function Core.virtual_loop_items(project,row,seeds,margin)
 assert(row and row.kind=='sustain' and row.finish>row.start,'対象のサステインリージョンが不正です。')
 assert(type(seeds)=='table' and #seeds>0,'波形を見る音声アイテムを選択してください。')
 margin=max(0,finite(margin) and margin or 0)
 local seed_set,track={}
 for _,item in ipairs(seeds) do
  if not R.ValidatePtr2 or R.ValidatePtr2(project,item,'MediaItem*') then
   local take=R.GetActiveTake(item);local pos=R.GetMediaItemInfo_Value(item,'D_POSITION')
   local ending=pos+R.GetMediaItemInfo_Value(item,'D_LENGTH')
   if take and not R.TakeIsMIDI(take) and row.start<ending-1e-9 and row.finish>pos+1e-9 then
    local item_track=R.GetMediaItem_Track(item)
    assert(not track or track==item_track,'対象リージョンと重なる音声アイテムは同じトラックから選択してください。')
    track=item_track;seed_set[item]=true
   end
  end
 end
 assert(track,'選択したサステインと重なる音声アイテムを選択してください。')
 local all={}
 for i=0,R.CountTrackMediaItems(track)-1 do
  local item=R.GetTrackMediaItem(track,i);local take=R.GetActiveTake(item)
  if take and not R.TakeIsMIDI(take) then
   local pos=R.GetMediaItemInfo_Value(item,'D_POSITION');local length=R.GetMediaItemInfo_Value(item,'D_LENGTH')
   if finite(pos) and finite(length) and length>0 then all[#all+1]={item=item,pos=pos,ending=pos+length} end
  end
 end
 table.sort(all,function(a,b) return a.pos==b.pos and a.ending>b.ending or a.pos<b.pos end)
 local components={};local component
 for _,entry in ipairs(all) do
  if not component or entry.pos>component.ending+1e-7 then
   component={start=entry.pos,ending=entry.ending,items={entry},has_seed=seed_set[entry.item]==true}
   components[#components+1]=component
  else
   component.items[#component.items+1]=entry
   component.ending=max(component.ending,entry.ending)
   component.has_seed=component.has_seed or seed_set[entry.item]==true
  end
 end
 local chosen
 for _,candidate in ipairs(components) do if candidate.has_seed then
  assert(not chosen,'選択アイテムが離れた複数の素材群に分かれています。対象を分けて選択してください。')
  chosen=candidate
 end end
 assert(chosen,'選択アイテムを対象トラック上で確認できませんでした。')
 local wanted_start=max(0,row.start-margin);local wanted_end=row.finish+margin
 assert(chosen.start<=wanted_start+1e-7 and chosen.ending>=wanted_end-1e-7,
  'サステイン全体を覆う、隙間のない連続音声アイテムを同じトラックに配置してください。')
 local items={};for _,entry in ipairs(chosen.items) do items[#items+1]=entry.item end
 assert(#items<=1000,'仮想素材として扱える連続アイテムは1000個までです。')
 return items
end

function Core.track_mix_source(project,items)
 assert(type(items)=='table' and #items>0,'仮想トラック素材に音声アイテムがありません。')
 local track,sr_hint,ch_hint,min_time,max_time
 min_time,max_time=math.huge,-math.huge
 for _,item in ipairs(items) do
  local take=R.GetActiveTake(item)
  assert(take and not R.TakeIsMIDI(take),'MIDIではなく音声アイテムを選択してください。')
  local item_track=R.GetMediaItem_Track(item)
  assert(not track or track==item_track,'仮想素材として扱う音声アイテムは同じトラックから選択してください。')
  track=track or item_track
  local pos=R.GetMediaItemInfo_Value(item,'D_POSITION');local ending=pos+R.GetMediaItemInfo_Value(item,'D_LENGTH')
  assert(finite(pos) and finite(ending) and ending>pos,'音声アイテムの位置または長さが不正です。')
  min_time=min(min_time,pos);max_time=max(max_time,ending)
  local source=R.GetMediaItemTake_Source(take)
  if source then
   local source_sr=optional_number(R.GetMediaSourceSampleRate,source)
   local source_ch=optional_number(R.GetMediaSourceNumChannels,source)
   if source_sr and source_sr>0 then sr_hint=sr_hint or source_sr end
   if source_ch and source_ch>=1 then ch_hint=max(ch_hint or 1,source_ch) end
  end
 end
 local sr
 if type(R.GetSetProjectInfo)=='function' then
  local use=optional_number(R.GetSetProjectInfo,project,'PROJECT_SRATE_USE',0,false)
  if use and use~=0 then sr=optional_number(R.GetSetProjectInfo,project,'PROJECT_SRATE',0,false) end
 end
 if not sr and type(R.GetAudioDeviceInfo)=='function' then
  local ok,got,value=pcall(R.GetAudioDeviceInfo,'SRATE')
  if ok and got then sr=tonumber(value) end
 end
 sr=finite(sr) and sr>0 and sr or sr_hint or 48000
 assert(sr>=8000 and sr<=384000,'仮想トラック素材のサンプルレートを取得できません。')
 local ch=optional_number(R.GetMediaTrackInfo_Value,track,'I_NCHAN')
 ch=finite(ch) and ch>=1 and ch or ch_hint or 2
 ch=floor(ch+.5);assert(ch>=1 and ch<=64,'仮想トラック素材のチャンネル数を取得できません。')
 local lo=math.ceil(min_time*sr-1e-7);local hi=floor(max_time*sr+1e-7)
 assert(hi>lo,'仮想トラック素材から音声範囲を取得できません。')
 return {track_mix=true,track=track,s=0,sr=sr,ch=ch,pos=min_time,ending=max_time,lo=lo,hi=hi}
end

function Core.loop_move_plan(project,rows,selected_key,edge,delta,relative,items_override)
 assert(edge=='start' or edge=='finish','移動する境界が不正です。')
 assert(finite(delta),'ドラッグ移動量が不正です。')
 local row,items=Core.loop_target(project,rows,selected_key,items_override)
 local sources={};local track
 for _,item in ipairs(items) do
  local take=R.GetActiveTake(item);assert(take and not R.TakeIsMIDI(take),'音声アイテムを選択してください。')
  local item_track=R.GetMediaItem_Track(item)
  assert(not track or track==item_track,'ループ調整に使う音声アイテムは同じトラックから選択してください。')
  track=track or item_track
  local pos=R.GetMediaItemInfo_Value(item,'D_POSITION');local ending=pos+R.GetMediaItemInfo_Value(item,'D_LENGTH')
  sources[#sources+1]={item=item,take=take,track=item_track,pos=pos,ending=ending}
 end
 table.sort(sources,function(a,b) return a.pos==b.pos and a.ending>b.ending or a.pos<b.pos end)
 local min_time,max_time=sources[1].pos,sources[1].ending;local right=sources[1]
 for i=2,#sources do
  local source=sources[i]
  assert(source.pos<=max_time+1e-7,'ループ調整に使う音声アイテム間に隙間があります。')
  if source.ending>max_time then max_time=source.ending;right=source end
 end
 assert(row.start>=min_time-1e-7 and row.finish<=max_time+1e-7,'開始側と終了側の音声アイテムを両方選択してください。')
 local p={row=row,left_source=sources[1],right_source=right,sources=sources,min_time=min_time,max_time=max_time}
 p.new_start,p.new_end=row.start,row.finish
 if relative then p.new_start=row.start+delta;p.new_end=row.finish+delta
 elseif edge=='start' then p.new_start=row.start+delta else p.new_end=row.finish+delta end
 p.auto_select,p.new_start,p.new_end,p.limited=Core.loop_extension_items(project,p,p.new_start,p.new_end,relative)
 return p
end

function Core.seam_drag_delta(dx,seconds_per_px)
 assert(finite(dx) and finite(seconds_per_px) and seconds_per_px>0,'波形ドラッグ量が不正です。')
 return clamp(-dx*seconds_per_px,-Core.SEAM_DRAG_SECONDS,Core.SEAM_DRAG_SECONDS)
end

function Core.seam_wave_shift(delta,half_width)
 assert(finite(delta) and finite(half_width) and half_width>0,'波形表示位置が不正です。')
 return -delta/Core.SEAM_SECONDS*half_width
end

function Core.seam_boundary_delta(delta,edge,start,finish,relative,min_time,max_time)
 assert(finite(delta) and finite(start) and finite(finish) and finish>start,'サステイン範囲が不正です。')
 assert(edge=='start' or edge=='finish','移動する境界が不正です。')
 local lo,hi=-math.huge,math.huge
 if not relative then
  local limit=finish-start-1e-6
  if edge=='finish' then lo=-limit else hi=limit end
 end
 if finite(min_time) and finite(max_time) then
  if relative or edge=='start' then lo=max(lo,max(0,min_time)-start) end
  if relative or edge=='finish' then hi=min(hi,max_time-finish) end
 end
 assert(lo<=hi,'選択アイテム内に有効なループ範囲を確保できません。')
 return clamp(delta,lo,hi)
end

function Core.seam_geometry(x,width)
 assert(finite(x) and finite(width) and width>12,'波形表示幅が不正です。')
 local left=x+6;local right=x+width-6;local middle=(left+right)/2
 return left,middle,right,(right-left)/2
end

function Core.adjusted_loop_bounds(plans)
 assert(type(plans)=='table' and #plans>0,'調整したサステイン範囲がありません。')
 local first,last
 for _,p in ipairs(plans) do
  local start=p.new_start or p.loop_start or p.s or p.row and p.row.start
  local finish=p.new_end or p.loop_finish or p.e or p.row and p.row.finish
  assert(finite(start) and finite(finish) and finish>start,'調整後のサステイン範囲が不正です。')
  first=first and min(first,start) or start;last=last and max(last,finish) or finish
 end
 return first,last
end
function Core.loop_audition_timing(start,finish,rate,lead_seconds)
 assert(finite(start) and finite(finish) and finish>start and finite(rate) and rate>0,'自動再生範囲を取得できません。')
 lead_seconds=finite(lead_seconds) and max(.75,lead_seconds) or .75
 local play_start=max(start,finish-lead_seconds)
 return play_start,(finish-play_start)/rate+.15,1
end
function Core.crossfade_audition_lead(plans)
 local lead=.75
 for _,p in ipairs(plans or {}) do
  local finish=p.loop_finish or p.e or p.row and p.row.finish
  local crossfade_start=p.output_start
  if finite(finish) and finite(crossfade_start) and crossfade_start<finish then lead=max(lead,finish-crossfade_start) end
 end
 return lead
end

function Core.seam_start(project,rows,selected_key,items_override)
 local row,items=Core.loop_target(project,rows,selected_key,items_override)
 local j=Core.loop_adjust_start(project,{row},'preview',nil,nil,items,false)
 local base=j.plans[1];local plans={};j.total=0
 for _,window in ipairs(base.windows) do
  local p={}
  for key,value in pairs(base) do if key~='windows' then p[key]=value end end
  p.windows={window};p.preview_side=window.edge
  p.preview_origin=window.edge=='finish' and row.finish or row.start
  plans[#plans+1]=p;j.total=j.total+window.last-window.first
 end
 j.plans=plans;j.index=1;j.window=1;j.at=0;j.done=0
 return j
end

local SECTION=Core.SECTION
local PROJECT_SECTION='BLT_REGION_FORGE'
local W,H=980,926
local A={status='時間選択から区間を追加し、WAVへ書き出します。',warning=false,content_dirty=true,closed=false,
 rows={},selected=nil,selected_regions={},poll_at=0,active=true,sr=48000,bits=24,channels=2,encoding='UTF-8',
 directory='',filename='$region',busy=false,progress=0,use_default_directory=true,use_default_filename=false,use_format=false,
 embed_markers=true,embed_regions=true,exclude_selected_region=true,embed_loop_region=true,
 marker_color=-1,region_color=-1,sustain_color=-1,
 add_mode='selection',length=1,length_values={seconds=1,beats=1,bars=1,grid=1},unit='seconds',
 interval=0,interval_values={seconds=0,beats=0,bars=0,grid=0},interval_unit='seconds',count=0,omit_name=true,
 xfade_seconds=3,relative_lock=false,auto_audition=false,wave_items={},audition=nil,period_notice=nil,
 loop_enable={crossfade=false,zero=false,period=false}}
local UI={}

local gfx,Host,U,shell,menu,wave,C
local scale,ox,oy,mouse_x,mouse_y=1,0,4,-1,-1
local pressed,down_last=nil,false
local wake_visuals
local function notice(s,warn)
 A.status=warn and BLT.publicError(s) or tostring(s or '');A.warning=warn or false
 A.content_dirty=true;if wake_visuals then wake_visuals() end
end
local function kind_color(kind)
 return kind=='sustain' and C.accent2 or kind=='marker' and C.muted or kind=='invalid' and C.red or C.focus
end
function UI.insert_color(kind)
 local packed=A[kind..'_color']
 if not Core.valid_insert_color(packed) or packed==-1 then return kind_color(kind) end
 UI.insert_color_cache=UI.insert_color_cache or {}
 local cached=UI.insert_color_cache[kind]
 if not cached or cached.packed~=packed then
  cached={packed=packed,rgb={((packed>>16)&255)/255,((packed>>8)&255)/255,(packed&255)/255}}
  UI.insert_color_cache[kind]=cached
 end
 return cached.rgb
end
function UI.select_insert_color(kind)
 if A.busy or not UI.commit_edit() then return end
 local project=A.project
 local ok,accepted,native=pcall(R.GR_SelectColor,Host.nativeWindow or R.GetMainHwnd())
 pressed=nil;U.capture=nil;down_last=(gfx.mouse_cap&1)~=0;gfx.mouse_wheel=0
 UI.dirty()
 if not ok then notice('カラー選択を開けませんでした。',true);return end
 if not accepted or accepted==0 then return end
 local decoded,r,g,b=pcall(R.ColorFromNative,native)
 if not decoded then notice('カラー選択を開けませんでした。',true);return end
 for _,v in ipairs({r,g,b}) do
  if not finite(v) or v%1~=0 or v<0 or v>255 then notice('カラー選択を開けませんでした。',true);return end
 end
 if r==nil or g==nil or b==nil then notice('カラー選択を開けませんでした。',true);return end
 assert(project==R.EnumProjects(-1,''),'プロジェクトが変わりました。追加をやり直してください。')
 A[kind..'_color']=(r<<16)|(g<<8)|b;UI.refresh()
end
function UI.cleanup_raw()
 if not A.own_raw or not A.raw then A.raw=nil;A.own_raw=false;A.raw_delete_at=nil;return true end
 local path=A.raw
 if type(R.reduce_open_files)=='function' then pcall(R.reduce_open_files,2) end
 local called,removed=pcall(os.remove,path)
 if not Core.exists(path) or (called and removed) then
  A.raw=nil;A.own_raw=false;A.raw_delete_at=nil
  return true
 end
 A.raw_delete_at=R.time_precise()+2
 return false
end
function UI.safe(fn,...)
 local ok,err=xpcall(fn,debug.traceback,...)
 if not ok then
  if A.render_snapshot and BLT.cleanup(Core.restore_render,A.render_snapshot) then A.render_snapshot=nil end
  if A.job and BLT.cleanup(Core.copy_abort,A.job) then A.job=nil end
  if A.xjob and BLT.cleanup(Core.crossfade_abort,A.xjob) then A.xjob=nil end
  if A.ajob and BLT.cleanup(Core.loop_audio_close,A.ajob) then A.ajob=nil end
  if A.pjob and BLT.cleanup(Core.loop_audio_close,A.pjob) then A.pjob=nil end
  if A.audition and UI.stop_loop_audition then BLT.cleanup(UI.stop_loop_audition,true) end
  BLT.cleanup(Core.retry_file_deletes,true)
  A.busy=false;A.seam_hold=nil;A.seam_drag=nil;A.render_batch=nil;A.render_complete_until=nil
  if not A.pjob then A.seam_refreshing=false;A.preview_signature=nil;A.preview_at=0 end
  pressed=nil;down_last=(gfx.mouse_cap&1)~=0
  local cleanup_ok,cleaned=BLT.cleanup(UI.cleanup_raw)
  cleaned=cleanup_ok and cleaned
  local msg=BLT.publicError(err)
  if not cleaned then msg=msg..'\n\n一時WAVを削除できませんでした。終了前に再試行します。' end
  notice(msg,true);BLT.recoverInput(A,msg)
 end
 return ok
end
function UI.dirty() A.content_dirty=true;wake_visuals() end
function UI.selected()
 for _,row in ipairs(A.rows) do if row.key==A.selected then return row end end
end
function UI.selected_rows()
 local wanted={};for _,key in ipairs(A.selected_regions or {}) do wanted[key]=true end
 local rows={};for _,row in ipairs(A.rows) do if wanted[row.key] and row.isr and row.finish>row.start then rows[#rows+1]=row end end
 return rows
end
local function valid_audio_item(project,item)
 if not item or R.ValidatePtr2 and not R.ValidatePtr2(project,item,'MediaItem*') then return false end
 local take=R.GetActiveTake(item)
 return take~=nil and not R.TakeIsMIDI(take)
end
local function selected_audio_items(project)
 local current={}
 for i=0,R.CountSelectedMediaItems(project)-1 do
  local item=R.GetSelectedMediaItem(project,i)
  if valid_audio_item(project,item) then current[#current+1]=item end
 end
 local keys={};for _,item in ipairs(current) do keys[#keys+1]=tostring(item) end
 return current,table.concat(keys,':')
end
function UI.wave_target_items(project,allow_empty)
 project=project or A.project
 local current,signature=selected_audio_items(project)
 A.wave_items,A.last_wave_selection=Core.wave_selection_memory(current,signature,A.wave_items,A.last_wave_selection)
 local valid={}
 for _,item in ipairs(A.wave_items or {}) do if valid_audio_item(project,item) then valid[#valid+1]=item end end
 A.wave_items=valid
 if not allow_empty then assert(#valid>0,'波形を見る音声アイテムを選択してください。') end
 return valid
end
function UI.remember_wave_items(items)
 local remembered,seen={},{}
 local function add(item)
  if not seen[item] and valid_audio_item(A.project,item) then seen[item]=true;remembered[#remembered+1]=item end
 end
 for _,item in ipairs(A.wave_items or {}) do add(item) end
 for _,item in ipairs(items or {}) do add(item) end
 A.wave_items=remembered
end
function UI.remember_plan_items(plans)
 UI.remember_wave_items(Core.wave_plan_memory_items(plans))
 local current,signature=selected_audio_items(A.project)
 if #current>0 then A.last_wave_selection=signature end
end
function UI.loop_target_items(project,mode,allow_empty,selected_key)
 local seeds=UI.wave_target_items(project,allow_empty)
 if #seeds==0 then return seeds end
 local row=Core.loop_target(project,A.rows,selected_key,seeds)
 local margin=mode=='zero' and .1 or 0
 local items=Core.virtual_loop_items(project,row,seeds,margin)
 return items,row
end
function UI.refresh_loop_enable()
 local state={crossfade=false,zero=false,period=false}
 local seeds=UI.wave_target_items(A.project,true)
 if #seeds==0 then A.loop_enable=state;return end
 local ok,row=pcall(Core.loop_target,A.project,A.rows,nil,seeds)
 if not ok then A.loop_enable=state;return end
 local function validate_adjust(mode)
  local margin=mode=='period' and 0 or .1
  local items=Core.virtual_loop_items(A.project,row,seeds,margin)
  Core.loop_adjust_start(A.project,{row},mode,nil,nil,items,false)
  return true
 end
 state.zero=pcall(validate_adjust,'zero')
 state.period=pcall(validate_adjust,'period')
 state.crossfade=pcall(function()
  local seconds=Core.crossfade_fit(A.project,{row},A.xfade_seconds,seeds)
  Core.crossfade_plan(A.project,{row},seconds,seeds)
 end)
 A.loop_enable=state
end
function UI.bounds()
 local first,last
 for _,row in ipairs(UI.selected_rows()) do first=first and min(first,row.start) or row.start;last=last and max(last,row.finish) or row.finish end
 return first or 0,last or 0
end
function UI.options(selected_key)
 return {encoding=A.encoding,selected_key=selected_key,embed_markers=A.embed_markers,embed_regions=A.embed_regions,
  exclude_selected_region=A.exclude_selected_region,embed_loop_region=A.embed_loop_region}
end
function UI.preflight()
 if not Media.ready() then return end
 local selected=UI.selected_rows();local start,ending=UI.bounds()
 A.start,A.finish=start,ending;A.plans={}
 if #selected==0 or not finite(start) or not finite(ending) or ending<=start then
  A.plan=nil
  A.problem=nil
  return
 end
 if A.format_problem then A.plan=nil;A.problem=A.format_problem;return end
 local ok,result=pcall(function()
  local plans={}
  for _,row in ipairs(selected) do
   local p=Core.plan(A.rows,row.start,row.finish,A.format.sr,UI.options(row.key));p.target_row=row;plans[#plans+1]=p
  end
  return plans
 end)
 A.plans=ok and result or {};A.plan=A.plans[1];A.problem=not ok and BLT.publicError(result) or nil
end
function UI.load_project(project)
 if A.project~=project then
  if A.audition and UI.stop_loop_audition then UI.stop_loop_audition(true) end
  if A.pjob then Core.loop_audio_close(A.pjob);A.pjob=nil end
  A.seam=nil;A.seam_problem=nil;A.seam_refreshing=false;A.preview_signature=nil;A.seam_drag=nil;A.seam_hold=nil;A.wave_items={};A.last_wave_selection=nil
  A.loop_enable={crossfade=false,zero=false,period=false}
 end
 A.project=project;A.selected=nil;A.selected_regions={};A.region_selection_signature=nil;A.region_selection_problem=nil
 local function get(key,default) local _,v=R.GetProjExtState(project,PROJECT_SECTION,key);return v~='' and v or default end
 A.filename=get('filename','$region');A.directory=get('directory','')
 if A.directory=='' then A.directory=R.GetProjectPathEx(project,'') end
 A.encoding=get('encoding','UTF-8');if A.encoding~='UTF-8' and A.encoding~='CP932' then A.encoding='UTF-8' end
 for k,default in pairs({sr=48000,bits=24,channels=2}) do A[k]=tonumber(get(k,tostring(default))) or default end
 if A.sr<8000 or A.sr>384000 or A.sr%1~=0 then A.sr=48000 end
 if A.bits~=16 and A.bits~=24 and A.bits~=32 then A.bits=24 end
 local channel_ok=false;for _,v in ipairs(Core.channel_options) do if A.channels==v then channel_ok=true end end
 if not channel_ok then A.channels=2 end
 A.use_default_directory=get('use_default_directory','true')=='true'
 A.use_default_filename=get('use_default_filename','false')=='true'
 A.embed_markers=get('embed_markers','true')=='true'
 A.embed_regions=get('embed_regions','true')=='true'
 A.exclude_selected_region=get('exclude_selected_region','true')=='true'
 A.embed_loop_region=get('embed_loop_region','true')=='true'
 for _,kind in ipairs({'marker','region','sustain'}) do
  local key=kind..'_color';local packed=tonumber(get(key,'-1'))
  A[key]=Core.valid_insert_color(packed) and packed or -1
 end
 A.omit_name=get('omit_name','true')=='true'
 A.auto_audition=get('auto_audition','false')=='true'
 A.xfade_seconds=tonumber(get('xfade_seconds','3'))
 if not finite(A.xfade_seconds) or A.xfade_seconds<.000001 or A.xfade_seconds>10 then A.xfade_seconds=3 end
 A.xfade_seconds=Core.normalize_spec_number(A.xfade_seconds,{.000001,10,false,1,6,nil,false,6})
 A.name_dialog=nil
 A.use_format=get('use_format','false')=='true';A.popup=nil
 A.add_mode=get('add_mode','selection');if not ({selection=true,items=true,itemblocks=true,itemspan=true,cursor=true})[A.add_mode] then A.add_mode='selection' end
 A.unit=get('unit','seconds');if not Core.length_specs[A.unit] then A.unit='seconds' end
 A.length_values={}
 for unit,spec in pairs(Core.length_specs) do
  local value=tonumber(get('length_'..unit,''))
  if not finite(value) or value<spec[1] or value>spec[2] or spec[3] and value%1~=0 then value=spec[6] end
  A.length_values[unit]=Core.normalize_spec_number(value,spec)
 end
 A.length=A.length_values[A.unit]
 A.interval_unit=get('interval_unit','seconds');if not Core.interval_specs[A.interval_unit] then A.interval_unit='seconds' end
 A.interval_values={}
 for unit,spec in pairs(Core.interval_specs) do
  local value=tonumber(get('interval_'..unit,''))
  if not finite(value) or value<spec[1] or value>spec[2] or spec[3] and value%1~=0 then value=0 end
  A.interval_values[unit]=Core.normalize_spec_number(value,spec)
 end
 A.interval=A.interval_values[A.interval_unit]
 A.count=tonumber(get('count','0')) or 0;if not finite(A.count) or A.count<Core.count_spec[1] or A.count>Core.count_spec[2] or A.count%1~=0 then A.count=0 end
 A.relative_lock=get('relative_lock','false')=='true'
 A.revision=nil
end
function UI.save_settings()
 if not A.project or (R.ValidatePtr and not R.ValidatePtr(A.project,'ReaProject*')) then return end
 A.length_values[A.unit]=A.length
 A.interval_values[A.interval_unit]=A.interval
 for _,k in ipairs({'filename','directory','sr','bits','channels','encoding','use_default_directory','use_default_filename','use_format','embed_markers','embed_regions','exclude_selected_region','embed_loop_region','omit_name','xfade_seconds','add_mode','unit','interval_unit','count','relative_lock','auto_audition','marker_color','region_color','sustain_color'}) do
  local val=tostring(A[k]);local _,old=R.GetProjExtState(A.project,PROJECT_SECTION,k)
  if old~=val then R.SetProjExtState(A.project,PROJECT_SECTION,k,val) end
 end
 for unit,value in pairs(A.length_values) do
  local key='length_'..unit;local val=tostring(value);local _,old=R.GetProjExtState(A.project,PROJECT_SECTION,key)
  if old~=val then R.SetProjExtState(A.project,PROJECT_SECTION,key,val) end
 end
 for unit,value in pairs(A.interval_values) do
  local key='interval_'..unit;local val=tostring(value);local _,old=R.GetProjExtState(A.project,PROJECT_SECTION,key)
  if old~=val then R.SetProjExtState(A.project,PROJECT_SECTION,key,val) end
 end
end
function UI.set_unit(unit)
 assert(Core.length_specs[unit],'基準幅の単位が不正です。')
 A.length_values[A.unit]=A.length;A.unit=unit;A.length=A.length_values[unit]
end
function UI.set_interval_unit(unit)
 assert(Core.interval_specs[unit],'間隔補正の単位が不正です。')
 A.interval_values[A.interval_unit]=A.interval;A.interval_unit=unit;A.interval=A.interval_values[unit]
end
function UI.set_add_mode(mode)
 assert(mode=='selection' or mode=='items' or mode=='itemspan' or mode=='itemblocks' or mode=='cursor','配置元が不正です。')
 A.add_mode=mode;A.add_kind_flash=R.time_precise();UI.refresh()
end
function UI.poll(now,force,render_prepare)
 if (A.busy and not render_prepare) or (not force and now<A.poll_at) then return end
 if not Media.ready() then return end;A.poll_at=now+.12
 local project=R.EnumProjects(-1,'')
 if project~=A.project then UI.load_project(project);force=true end
 local _,dir=R.GetSetProjectInfo_String(project,'RENDER_FILE','',false)
 local _,pattern=R.GetSetProjectInfo_String(project,'RENDER_PATTERN','',false)
 if dir~=A.default_directory or pattern~=A.default_pattern then A.default_directory=dir;A.default_pattern=pattern;UI.dirty() end
 local native_ok,native
 if A.use_format then native_ok,native=pcall(Core.native_format,project) end
 local format
 if A.use_format then format=native_ok and native or nil else format={sr=A.sr,bits=A.bits,channels=A.channels} end
 local problem=A.use_format and not native_ok and BLT.publicError(native) or nil
 local signature=problem or (format.sr..':'..format.bits..':'..format.channels)
 if signature~=A.format_signature then A.popup=nil;A.format_signature=signature;force=true;UI.dirty() end
 A.format=format;A.format_problem=problem
 local rev=R.GetProjectStateChangeCount(project)
 if force or rev~=A.revision then A.rows=Core.project_rows(project);A.revision=rev;UI.dirty() end
 local selected,selection_signature=Core.selected_project_regions(project,A.rows)
 if selection_signature~=A.region_selection_signature then
  A.selected_regions=selected;A.selected=selected[1];A.region_selection_problem=nil;A.region_selection_signature=selection_signature;force=true;UI.dirty()
 end
 local s,e=UI.bounds()
 if force or rev~=A.plan_revision or s~=A.start or e~=A.finish then
  if render_prepare then A.start,A.finish=s,e
  else UI.preflight();A.plan_revision=rev end
  UI.dirty()
 end
end
function UI.refresh() UI.save_settings();UI.poll(R.time_precise(),true) end
function UI.choose_directory()
 if R.JS_Dialog_BrowseForSaveFile then
  local ok,path=Language.save('保存先フォルダーを開き、「保存」で選択',A.directory,'このフォルダーを選択.folder','フォルダー選択用 (*.folder)\0*.folder\0')
  if (ok==1 or ok==true) and type(path)=='string' and path~='' then
   local dir=path:match('^(.*)[/\\][^/\\]*$')
   assert(dir and dir~='','保存先のディレクトリパスを取得できません。')
   if dir:match('^%a:$') then dir=dir..'\\' end
   A.directory=dir;UI.refresh()
  end
 else UI.begin_edit('field_directory',A,'directory',nil) end
end
function UI.undo(label,flags,fn)
 assert(R.EnumProjects(-1,'')==A.project,'プロジェクトが変わりました。')
 R.Undo_BeginBlock2(A.project)
 local ok,err=xpcall(fn,debug.traceback)
 R.Undo_EndBlock2(A.project,'BLT LOOP RM STUDIO: '..label,flags);R.UpdateArrange();UI.poll(R.time_precise(),true)
 if not ok then error(err,0) end
end
function UI.project_undo()
 if A.busy then notice('処理中は元に戻せません。処理を完了または中止してください。',true);return end
 local project=R.EnumProjects(-1,'')
 if project~=A.project then UI.load_project(project) end
 local description=type(R.Undo_CanUndo2)=='function' and R.Undo_CanUndo2(project) or nil
 if type(R.Undo_CanUndo2)=='function' and (not description or description=='') then notice('元に戻せる操作がありません。',false);return end
 if A.audition then UI.stop_loop_audition(true) end
 if A.pjob then Core.loop_audio_close(A.pjob);A.pjob=nil end
 assert(type(R.Undo_DoUndo2)=='function','REAPERのUndo APIを利用できません。')
 local result=R.Undo_DoUndo2(project)
 if result==0 then notice('元に戻せる操作がありません。',false);return end
 A.preview_signature=nil;A.preview_at=0;A.seam=nil;A.seam_hold=nil;A.seam_drag=nil;A.last_wave_selection=nil
 R.UpdateArrange();UI.poll(R.time_precise(),true)
 notice('元に戻しました。'..(description and description~='' and ' '..description or ''),false)
end
function UI.add_commit(kind,ranges,names,project)
 assert(project==R.EnumProjects(-1,''),'プロジェクトが変わりました。追加をやり直してください。')
 UI.undo(Core.names[kind]..'を追加',8,function()
  local c=UI.insert_color(kind);local native=R.ColorToNative(floor(c[1]*255+.5),floor(c[2]*255+.5),floor(c[3]*255+.5))|0x1000000
  local added={}
  local ok,err=xpcall(function()
   for i,r in ipairs(ranges) do
    local id=R.AddProjectMarker2(project,kind~='marker',r.start,kind=='marker' and 0 or r.finish,names[i],-1,native)
    assert(id>=0,'追加できませんでした。');added[#added+1]=id
   end
  end,debug.traceback)
  if not ok then for _,id in ipairs(added) do R.DeleteProjectMarker(project,id,kind~='marker') end;error(err,0) end
 end)
 if ranges.auto_limited then notice('自動個数が1000個を超えるため、1000個に制限して挿入しました。',true) end
end
function UI.add(kind)
 if not UI.commit_edit() then return end
 UI.poll(R.time_precise(),true)
 local project=A.project;local ranges=Core.add_ranges(project,A.add_mode,kind,A.length,A.unit,A.count,A.interval,A.interval_unit)
 if A.omit_name then UI.add_commit(kind,ranges,Core.add_names(kind,'',#ranges,false,'1'),project)
 else
  A.popup=nil;A.name_dialog={project=project,kind=kind,ranges=ranges,name=Core.names[kind],item_names_available=ranges[1].item_name~=nil,use_item_name=false,ignore_extension=false,numbering=#ranges>1,serial_start='001'};UI.dirty()
 end
end
local function repeat_state(project,value)
 if R.GetSetRepeatEx then return R.GetSetRepeatEx(project,value) end
 return R.GetSetRepeat(value)
end
function UI.stop_loop_audition(stop_playback)
 local d=A.audition;if not d then return end
 local valid=not R.ValidatePtr or R.ValidatePtr(d.project,'ReaProject*')
 if valid and stop_playback and R.GetPlayStateEx(d.project)~=0 then
  if R.OnStopButtonEx then R.OnStopButtonEx(d.project) else R.OnStopButton() end
 end
 if valid and d.forced_repeat and repeat_state(d.project,-1)==1 then repeat_state(d.project,0) end
 A.audition=nil;UI.dirty()
end
function UI.start_loop_audition(plans,lead_seconds)
 if not A.auto_audition then return end
 UI.stop_loop_audition(true)
 local project=A.project;local start,finish=Core.adjusted_loop_bounds(plans)
 assert((R.GetPlayStateEx(project)&4)==0,'録音中は繋ぎ目を自動再生できません。')
 local rate=R.Master_GetPlayRate(project);assert(finite(rate) and rate>0,'プロジェクトの再生速度を取得できません。')
 local play_start,wrap_after,stop_after=Core.loop_audition_timing(start,finish,rate,lead_seconds)
 local previous_repeat=repeat_state(project,-1)
 local now=R.time_precise()
 A.audition={project=project,loop_start=start,loop_finish=finish,
  expected_wrap=now+wrap_after,stop_after=stop_after,forced_repeat=previous_repeat~=1}
 R.GetSet_LoopTimeRange2(project,true,true,start,finish,false)
 repeat_state(project,1)
 R.SetEditCurPos2(project,play_start,false,false)
 if R.OnPlayButtonEx then R.OnPlayButtonEx(project) else R.OnPlayButton() end
 assert((R.GetPlayStateEx(project)&1)~=0,'繋ぎ目の自動再生を開始できませんでした。')
end
function UI.loop_audition_tick(now)
 local d=A.audition;if not d then return end
 if R.EnumProjects(-1,'')~=d.project or (R.GetPlayStateEx(d.project)&1)==0 then UI.stop_loop_audition(false);return end
 local position=R.GetPlayPositionEx(d.project);local duration=d.loop_finish-d.loop_start
 if not d.looped_at then
  if d.last_position and position<d.last_position-max(.005,duration*.25) then d.looped_at=now
  elseif now>=d.expected_wrap then d.looped_at=d.expected_wrap end
 end
 d.last_position=position
 if d.looped_at and now-d.looped_at>=d.stop_after then UI.stop_loop_audition(true) end
end
function UI.stop_for_adjustment(project)
 if A.audition then UI.stop_loop_audition(true) end
 local state=R.GetPlayStateEx(project)
 assert((state&4)==0,'録音中は調整できません。録音を停止してください。')
 if state~=0 then
  if R.OnStopButtonEx then R.OnStopButtonEx(project) else R.OnStopButton() end
  assert(R.GetPlayStateEx(project)==0,'再生を停止できませんでした。')
 end
end
function UI.follow_loop_selection(project,plans)
 assert(project==A.project,'プロジェクトが変わりました。')
 local start,finish=Core.adjusted_loop_bounds(plans)
 R.GetSet_LoopTimeRange2(project,true,false,start,finish,false)
 if R.UpdateTimeline then R.UpdateTimeline() else R.UpdateArrange() end
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
function UI.crossfade()
 if not Media.ready() then return end
 if not UI.commit_edit() then return end
 local project=R.EnumProjects(-1,'')
 if project~=A.project then UI.load_project(project) end
 A.rows=Core.project_rows(project)
 A.revision=R.GetProjectStateChangeCount(project)
 UI.stop_for_adjustment(A.project)
 assert(abs(R.Master_GetPlayRate(A.project)-1)<1e-9,'プロジェクトの再生速度を1.0にしてください。')
 local items,row=UI.loop_target_items(project,'crossfade')
 local seconds=Core.crossfade_fit(A.project,{row},A.xfade_seconds,items)
 if abs(seconds-A.xfade_seconds)>1e-12 then
  A.xfade_seconds=seconds;UI.flash('field_xfade_seconds');UI.save_settings()
 end
 local plans=Core.crossfade_plan(A.project,{row},seconds,items)
 local dir=blt_output_directory(A.project)
 A.xjob=Core.crossfade_start(A.project,plans,dir);A.busy=true;A.progress=0
 notice('クロスフェード用のループ素材を作成中…',false)
end
function UI.crossfade_step()
 if not Media.ready() then return end
 local j=A.xjob;if not j then return end
 if not j.committed then
  if not Core.crossfade_step(j) then A.progress=j.progress;UI.dirty();return end
  Core.crossfade_commit(j)
  UI.remember_plan_items(j.plans)
  UI.follow_loop_selection(A.project,j.plans)
  UI.poll(R.time_precise(),true)
 end
 if not Core.crossfade_peaks_step(j) then
  A.progress=1
  if not j.peak_notice then j.peak_notice=true;notice('生成したループ素材の波形を準備中…',false) end
  return
 end
 A.xjob=nil;A.busy=false;A.progress=1
 UI.start_loop_audition(j.plans,Core.crossfade_audition_lead(j.plans))
 A.preview_signature=nil;A.preview_at=R.time_precise()+.35;A.seam=nil;A.seam_hold=nil
 UI.preview_refresh(UI.preview_signature_now())
 notice('サステイン区間をクロスフェード処理しました。時間選択を追従しました。Undoで戻せます。',false)
end

function UI.adjust_loop(mode,edge,direction)
 if not Media.ready() then return end
 if not UI.commit_edit() then return end
 A.period_notice=nil
 local project=R.EnumProjects(-1,'')
 if project~=A.project then UI.load_project(project) end
 UI.stop_for_adjustment(project)
 assert(abs(R.Master_GetPlayRate(project)-1)<1e-9,'プロジェクトの再生速度を1.0にしてください。')
 A.rows=Core.project_rows(project)
 local items,row=UI.loop_target_items(project,mode)
 A.ajob=Core.loop_adjust_start(project,{row},mode,edge,direction,items,edge and A.relative_lock);A.busy=true;A.progress=0
 notice(mode=='zero' and '開始・終了付近のゼロクロスを解析中…' or 'サステイン周辺の周期を解析中…',false)
end
function UI.show_transient_notice(text)
 local now=R.time_precise()
 A.period_notice={text=text,born=now,fade_at=now+2.2,finish=now+3}
 UI.dirty()
end
function UI.show_period_failure()
 UI.show_transient_notice('周期を検出できませんでした・・・！')
 A.status='周期解析を終了しました。リージョンは変更していません。';A.warning=false;UI.dirty()
end
function UI.adjust_loop_step()
 if not Media.ready() then return end
 local j=A.ajob;if not j then return end
 local ok,done=xpcall(function() return Core.loop_adjust_step(j) end,debug.traceback)
 if not ok then
  if j.mode=='period' and tostring(done):find(Core.PERIOD_FAILURE,1,true) then
   Core.loop_audio_close(j);A.ajob=nil;A.busy=false;A.progress=0;A.preview_signature=nil;A.preview_at=0
   UI.show_period_failure();return
  end
  error(done,0)
 end
 if done then
  Core.loop_adjust_commit(j);A.ajob=nil;A.busy=false;A.progress=1
  UI.remember_plan_items(j.plans)
  UI.follow_loop_selection(A.project,j.plans)
  local detail=''
  if j.mode=='period' and #j.plans==1 then detail=string.format('（周期 %.3f 秒 / 一致度 %.0f%%）',j.plans[1].period,j.plans[1].confidence*100) end
  UI.poll(R.time_precise(),true);A.preview_signature=nil;A.preview_at=0;UI.start_loop_audition(j.plans)
  local selected=j.auto_selected_count and j.auto_selected_count>0 and (' 移動先の音声アイテムを選択へ追加: '..j.auto_selected_count..'件。') or ' '
  notice((j.mode=='zero' and 'ゼロクロスへ移動しました。' or '周期に合わせて移動しました。')..detail..selected..'時間選択を追従しました。Undoで戻せます。',false)
  for _,p in ipairs(j.plans) do if p.limited then UI.show_transient_notice('選択アイテム内でこれ以上移動できません');break end end
 else A.progress=j.progress;UI.dirty() end
end

function UI.output_path(p,batch_index,batch_count)
 p=p or A.plan;assert(p,A.problem)
 local directory,name,manual_pattern
 if not A.use_default_directory then
  directory=A.directory
  assert(directory~='' and not directory:find('[%c;$]'),'出力フォルダーが不正です。')
  assert(directory:match('^%a:[/\\]') or directory:match('^[/\\]'),'出力フォルダーは絶対パスで指定してください。')
 end
 if not A.use_default_filename then
  name=Core.manual_render_pattern(A.filename)
  assert(name,'ファイル名に使用できない文字があります。')
  if name:find('$',1,true) then manual_pattern=name
  else
   assert(not Core.reserved_filename(name),'予約されたファイル名です。')
   name=Core.batch_output_name(name,batch_index or 1,batch_count or 1)..'.wav'
  end
 end
 local target
 if A.use_default_directory or A.use_default_filename or manual_pattern then
  local snapshot=Core.snapshot_render(A.project);A.render_snapshot=snapshot
  local ok,result=xpcall(function()
   snapshot.selection_changed=true
   if A.use_default_directory then
    local probe='__BLT_DIRECTORY_'..R.genGuid():gsub('[^%w]','')
    Core.configure_render(A.project,p,snapshot.s.RENDER_FILE,probe,A.format.bits,A.format.channels,false)
    local got,paths=R.GetSetProjectInfo_String(A.project,'RENDER_TARGETS','',false)
    local resolved=Core.single_render_wav_target(got,paths)
    directory=resolved:match('^(.*)[/\\][^/\\]+$')
    assert(directory and directory~='','REAPER本体の保存フォルダーを解決できません。')
   end
   if A.use_default_filename or manual_pattern then
    Core.configure_render(A.project,p,directory,A.use_default_filename and snapshot.s.RENDER_PATTERN or manual_pattern,A.format.bits,A.format.channels,true)
    local got,paths=R.GetSetProjectInfo_String(A.project,'RENDER_TARGETS','',false)
    return Core.single_render_wav_target(got,paths)
   end
   return directory..'/'..name
  end,debug.traceback)
  Core.restore_render(snapshot);A.render_snapshot=nil
  if not ok then error(result,0) end
  target=result
 else target=directory..'/'..name end
 local target_directory=target:match('^(.*)[/\\][^/\\]+$')
 assert(target_directory and target_directory~='','出力先のフォルダーを解決できません。')
 R.RecursiveCreateDirectory(target_directory,0)
 return Core.unique(target)
end
-- The host presents each stage before its work can run on a later defer turn.
-- Native rendering stays synchronous: never invent a live percentage while REAPER
-- owns the call. Overall percentages are weighted stages, not elapsed-time estimates.
UI.render_stages={
 prepare={caption='PREPARING',message='レンダリングの準備中…'},
 plan={caption='PREPARING',message='書き出し範囲と埋め込み情報を確認しています…'},
 path={caption='PREPARING',fraction=0,message='出力先とファイル名を準備しています…'},
 render={caption='RENDERING',fraction=.05,message='REAPERでレンダリング中… 詳細な進捗は標準レンダラーに表示されます。'},
 inspect={caption='CHECKING WAV',fraction=.80,message='レンダーされたWAVを確認しています…'},
 embed={caption='EMBEDDING',fraction=.83,message='リージョン情報を埋め込んでいます…'},
 copy={caption='WRITING WAV',fraction=.85,message='音声と区間情報を書き込んでいます…'},
 verify={caption='VERIFYING',fraction=.98,message='書き出し結果を検証しています…'},
 cleanup={caption='FINALIZING',fraction=.99,message='一時WAVを整理しています…'},
}
function UI.render_progress(fraction)
 local b=A.render_batch
 if not b or not b.total_frames or b.total_frames<=0 or not b.plans[b.index] then return end
 local value=.05+.95*(b.completed_frames+b.plans[b.index].frames*clamp(fraction,0,1))/b.total_frames
 -- Reserve 100% for verified output AND successful cleanup of the entire batch.
 A.progress=max(A.progress or 0,min(.99,value));A.content_dirty=true
end
function UI.render_stage(phase)
 local b=assert(A.render_batch);local spec=assert(UI.render_stages[phase])
 b.phase=phase;b.presented=false
 if spec.fraction then UI.render_progress(spec.fraction) end
 notice(spec.message,false);UI.dirty()
end
function UI.render_mix()
 if A.busy or A.render_batch or A.closed or A.closing then return end
 -- No media scan, planning, path I/O or native command before this first busy frame.
 A.render_complete_until=nil;A.progress=0;A.busy=true
 A.render_batch={project=R.EnumProjects(-1,''),plans={},outputs={},index=0,count=0,completed_frames=0}
 UI.render_stage('prepare')
end
function UI.start_copy(source,p,target)
 A.job=Core.copy_start(source,target,p);A.busy=true
 if A.render_batch then UI.render_stage('copy')
 else A.progress=0;notice('リージョン情報を埋め込んでいます…',false) end
end
function UI.render_one(p,batch_index,batch_count,target)
 assert(R.EnumProjects(-1,'')==A.project,'書き出し中にプロジェクトが切り替わりました。')
 target=target or UI.output_path(p,batch_index,batch_count)
 local token=R.genGuid():gsub('[^%w]','')
 -- Keep path resolution and native metadata wildcards identical to previous releases.
 local pattern=assert(target:match('[/\\]([^/\\]+)$')):sub(1,-5)
 local outputdir=assert(target:match('^(.*)[/\\][^/\\]+$'))
 local raw=outputdir..'/_BLT_RENDER_'..token..'.wav';assert(not Core.exists(raw),'一時ファイル名が衝突しました。')
 assert(not Core.exists(target),'出力先に同名ファイルが作成されました。再実行してください。')
 assert(R.GetPlayStateEx(A.project)==0,'再生・録音を停止してから書き出してください。')
 assert(abs(R.Master_GetPlayRate(A.project)-1)<1e-9,'プロジェクトの再生速度を1.0にしてください。')
 A.raw=target;A.own_raw=true
 local snapshot=Core.snapshot_render(A.project);A.render_snapshot=snapshot
 local ok,err=xpcall(function()
  snapshot.selection_changed=true
  Core.configure_render(A.project,p,outputdir,pattern,A.format.bits,A.format.channels)
  local got,targets=R.GetSetProjectInfo_String(A.project,'RENDER_TARGETS','',false)
  local wav_target=Core.single_render_wav_target(got,targets)
  local function norm(s) return s:gsub('\\','/'):lower() end
  assert(norm(wav_target)==norm(target),'REAPERが予期しないWAV出力先を返しました: '..targets)
  R.Main_OnCommand(41824,0) -- Synchronous native render; never automate overwrite dialogs.
 end,debug.traceback)
 -- Never yield with temporary project render settings or selection still installed.
 Core.restore_render(snapshot);A.render_snapshot=nil
 if not ok then error(err,0) end
 assert(Core.exists(target),'レンダーがキャンセルされたか、WAVが作成されませんでした。')
 assert(os.rename(target,raw),'レンダー音声を一時保存名へ変更できませんでした。')
 A.raw=raw
 return raw
end
function UI.render_stop(message,warning,transient)
 local b=A.render_batch
 if b then A.last_outputs=b.outputs end
 A.render_batch=nil;A.busy=false;A.render_complete_until=nil
 notice(message,warning);if transient then UI.show_transient_notice(message) end
 UI.dirty()
end
function UI.render_step()
 local b=A.render_batch
 if not b or not b.presented or A.closed or A.closing then return end
 assert(R.EnumProjects(-1,'')==b.project,'書き出し中にプロジェクトが切り替わりました。')
 if not Media.ready() then return end
 local phase=b.phase
 if phase=='prepare' then
  if not UI.commit_edit() then UI.render_stop('書き出しを中止しました。',false);return end
  UI.poll(R.time_precise(),true,true)
  b.selected=UI.selected_rows();b.rows=A.rows;b.count=#b.selected
  A.plans=b.plans;A.plan=nil;A.problem=nil
  if b.count==0 then UI.render_stop('リージョンを選択されていません',false,true);return end
  if A.format_problem then A.problem=A.format_problem;UI.render_stop(A.problem,true,true);return end
  assert(R.GetPlayStateEx(b.project)==0,'再生・録音を停止してから書き出してください。')
  assert(abs(R.Master_GetPlayRate(b.project)-1)<1e-9,'プロジェクトの再生速度を1.0にしてください。')
  assert(UI.cleanup_raw(),'前回の一時WAVを削除できません。再試行してください。')
  b.total_frames=0;A.progress=.01;UI.render_stage('plan')
 elseif phase=='plan' then
  local deadline=R.time_precise()+.004
  for _=1,8 do
   local row=b.selected[#b.plans+1];if not row then break end
   local p=Core.plan(b.rows,row.start,row.finish,A.format.sr,UI.options(row.key));p.target_row=row
   assert(p.frames*A.format.channels*(A.format.bits//8)<0xffffffff-32*1024*1024,'4 GiBを超える出力には対応していません。')
   b.plans[#b.plans+1]=p;b.total_frames=b.total_frames+p.frames
   A.progress=.01+.04*#b.plans/b.count;A.content_dirty=true
   if R.time_precise()>=deadline then break end
  end
  if #b.plans==b.count then
   b.rows=nil;b.selected=nil;b.index=1;A.plan=b.plans[1]
   A.plan_revision=R.GetProjectStateChangeCount(b.project);UI.save_settings()
   UI.render_stage('path')
  end
 elseif phase=='path' then
  b.target=UI.output_path(b.plans[b.index],b.index,b.count)
  UI.render_stage('render')
 elseif phase=='render' then
  b.raw=UI.render_one(b.plans[b.index],b.index,b.count,b.target)
  UI.render_stage('inspect')
 elseif phase=='inspect' then
  local audio=Core.scan(b.raw)
  assert(audio.channels==A.format.channels and audio.bits==A.format.bits and (A.format.bits~=32 or audio.tag==3),'レンダーされたWAVのチャンネル数／ビット深度が設定と一致しません。')
  UI.render_stage('embed')
 elseif phase=='embed' then
  UI.start_copy(b.raw,b.plans[b.index],b.target)
 elseif phase=='copy' or phase=='verify' then
  UI.step()
 elseif phase=='cleanup' then
  local cleaned=UI.cleanup_raw()
  b.completed_frames=b.completed_frames+b.plans[b.index].frames
  if not cleaned then
   local message=b.index<b.count and string.format('一時WAVを削除できないため、一括書き出しを停止しました。完了済み: %d / %d件。',#b.outputs,b.count)
    or '書き出しは完了しましたが、一時WAVを削除できませんでした。終了前に再試行します。'
   UI.render_stop(message,true);return
  end
  if b.index<b.count then
   b.index=b.index+1;b.target=nil;b.raw=nil;UI.render_stage('path')
  else
   A.last_outputs=b.outputs;A.render_batch=nil;A.busy=false;A.progress=1
   A.render_complete_until=R.time_precise()+.7
   notice(b.count>1 and ('書き出し完了: '..b.count..'件') or '書き出し完了。',false);UI.dirty()
  end
 end
end
function UI.cancel()
 if A.render_batch then
  local b=A.render_batch
  if A.render_snapshot then Core.restore_render(A.render_snapshot);A.render_snapshot=nil end
  Core.copy_abort(A.job);A.job=nil
  local cleaned=UI.cleanup_raw();local done=#b.outputs
  UI.render_stop(cleaned and (done>0 and ('一括書き出しを中止しました。完了済み: '..done..'件。') or '書き出しを中止しました。')
   or '処理を中止しました。一時WAVを削除できませんでした。終了前に再試行します。',not cleaned)
  return
 end
 if A.ajob then Core.loop_audio_close(A.ajob);A.ajob=nil;A.busy=false;notice('解析を中止しました。リージョンは変更していません。',false) end
 if A.xjob then Core.crossfade_abort(A.xjob);A.xjob=nil;A.busy=false;notice('クロスフェード処理を中止しました。',false) end
 if A.job then
  Core.copy_abort(A.job);A.job=nil;A.busy=false
  local cleaned=UI.cleanup_raw()
  notice(cleaned and '埋め込みを中止しました。' or '処理を中止しました。一時WAVを削除できませんでした。終了前に再試行します。',not cleaned)
 end
end
function UI.step()
 if not Media.ready() or not A.job then return end
 local j=A.job;local b=A.render_batch
 if b and b.phase=='copy' and not j.chunks[j.index] then UI.render_stage('verify');return end
 if Core.copy_step(j) then
  A.job=nil;A.last_output=j.target
  if b then
   b.outputs[#b.outputs+1]=j.target;UI.render_stage('cleanup')
  else
   A.busy=false;local raw_problem=not UI.cleanup_raw()
   if raw_problem then notice('書き出しは完了しましたが、一時WAVを削除できませんでした。終了前に再試行します。',true)
   else A.progress=1;notice('書き出し完了。',false) end
  end
 else
  if b then UI.render_progress(.85+.13*clamp(j.copied/max(1,j.size-12-#j.blob),0,1))
  else A.progress=j.copied/j.size;A.content_dirty=true end
 end
end
local field_specs={count=Core.count_spec,serial_start={0,999999999999,true,1,0},
 xfade_seconds={.000001,10,false,1,6,nil,false,6}}
local function field_spec(key)
 if key=='length' then return Core.length_specs[A.unit] end
 if key=='interval' then return Core.interval_specs[A.interval_unit] end
 return field_specs[key]
end
local function field_text(value,spec,key)
 if key=='count' and tonumber(value)==0 then return 'A' end
 if not spec then return tostring(value or '') end
 value=tonumber(value) or spec[1]
 if spec[3] then return tostring(floor(value+.5)) end
 local digits=spec[5] or 3
 local text=string.format('%.'..digits..'f',value)
 return spec[7] and text or text:gsub('0+$',''):gsub('%.$','')
end
local function parse_field(e,text)
 if e.key=='count' and tostring(text):match('^%s*[Aa]%s*$') then return 0 end
 if e.key=='length' and A.unit=='seconds' then return time_number(text,A.unit) end
 if e.key=='interval' and A.interval_unit=='seconds' then return time_number(text,A.interval_unit) end
 return tonumber(text)
end
local function normalize_field_number(value,spec)
 return Core.normalize_spec_number(value,spec)
end
local function normalized_text_value(key,value)
 value=tostring(value or '')
 if not utf8.len(value) or #value>4096 or value:find('[%z\1-\31\127]') then return nil,'入力できない制御文字、または長すぎる文字列です。' end
 if key=='filename' then
  value=Core.manual_render_pattern(value)
  if not value then return nil,'ファイル名に使用できない文字があります。' end
 elseif key=='directory' and value=='' then return nil,'保存フォルダーを入力してください。' end
 return value
end

function UI.confirm_name()
 local d=A.name_dialog;if not d or not UI.commit_edit() then return end
 local ok,names=pcall(Core.add_names,d.kind,d.name,#d.ranges,d.numbering,d.serial_start,d.use_item_name and d.ranges or nil,d.ignore_extension)
 if not ok then UI.flash('field_serial_start');notice(tostring(names),true);return end
 A.name_dialog=nil;UI.add_commit(d.kind,d.ranges,names,d.project)
end
function UI.preview_signature_now()
 local keys={tostring(A.project),tostring(R.GetProjectStateChangeCount(A.project))}
 for _,item in ipairs(UI.wave_target_items(A.project,true)) do keys[#keys+1]=tostring(item) end
 return table.concat(keys,':')
end
function UI.preview_refresh(signature)
 if not Media.ready() then return end
 if A.pjob then Core.loop_audio_close(A.pjob);A.pjob=nil end
 if signature then A.preview_signature=signature end;A.seam_problem=nil;A.seam_refreshing=true
 local enabled=pcall(UI.refresh_loop_enable)
 if not enabled then A.loop_enable={crossfade=false,zero=false,period=false} end
 local ok,j=pcall(function()
  local items,row=UI.loop_target_items(A.project,'preview',true)
  assert(row,'アイテムが選択されていません')
  return Core.seam_start(A.project,{row},row.key,items)
 end)
 if ok then A.pjob=j
 else A.seam=nil;A.seam_hold=nil;A.seam_refreshing=false;A.seam_problem=tostring(j):gsub('^.-:%d+: ','') end
 UI.dirty()
end
function UI.preview_tick(now)
 if not Media.ready() then return end
 if A.busy or now<(A.preview_at or 0) then return end
 A.preview_at=now+.35
 local signature=UI.preview_signature_now()
 if signature~=A.preview_signature then UI.preview_refresh(signature) end
end
function UI.preview_step()
 if not Media.ready() then return end
 local j=A.pjob;if not j then return end
 local ok,done=pcall(Core.loop_adjust_step,j)
 if not ok then
  Core.loop_audio_close(j);A.pjob=nil;A.seam=nil;A.seam_hold=nil;A.seam_refreshing=false
  A.seam_problem=tostring(done):gsub('^.-:%d+: ','');UI.dirty()
 elseif done then
  A.pjob=nil;A.seam=j.plans;A.seam_hold=nil;A.seam_refreshing=false
  UI.dirty()
 end
end

function UI.move_loop_drag(d)
 assert(R.EnumProjects(-1,'')==A.project,'ドラッグ中にプロジェクトが変わりました。やり直してください。')
 UI.stop_for_adjustment(A.project)
 assert(R.GetProjectStateChangeCount(A.project)==d.revision,'ドラッグ中にプロジェクトが変更されました。やり直してください。')
 A.rows=Core.project_rows(A.project)
 local items=UI.loop_target_items(A.project,'drag',false,d.selected)
 local p=Core.loop_move_plan(A.project,A.rows,d.selected,d.edge,d.delta,d.relative,items)
 local added=0
 UI.undo('波形ドラッグでループ範囲を移動',4|8,function()
  local r=p.row
  assert(R.SetProjectMarker3(A.project,r.id,true,p.new_start,p.new_end,r.raw,r.color),'サステインの更新に失敗しました。')
  for _,item in ipairs(p.auto_select) do
   if not R.IsMediaItemSelected or not R.IsMediaItemSelected(item) then added=added+1 end
   R.SetMediaItemSelected(item,true)
  end
 end)
 UI.remember_plan_items({p})
 UI.follow_loop_selection(A.project,{p})
 A.preview_at=R.time_precise()+.35
 UI.start_loop_audition({p});UI.preview_refresh(UI.preview_signature_now())
 local extra=added>0 and (' 移動先の音声アイテムを選択へ追加: '..added..'件。') or ''
 notice((d.edge=='finish' and '終了位置' or '開始位置')..'を波形ドラッグで移動しました。'..extra..' 時間選択を追従しました。Undoで戻せます。',false)
 if p.limited then UI.show_transient_notice('選択アイテム内でこれ以上移動できません') end
end

function UI.seam_input(hit,down)
 local seam=hit and hit.seam
 if down and not down_last and seam then
 local started=false
 UI.safe(function()
   local items,row=UI.loop_target_items(A.project,'drag')
   local bounds=Core.loop_move_plan(A.project,{row},row.key,'start',0,false,items)
   A.seam_drag={x=mouse_x,delta=0,edge=mouse_x<seam.mid and 'finish' or 'start',seconds_per_px=seam.seconds_per_px,
    revision=R.GetProjectStateChangeCount(A.project),selected=row.key,relative=A.relative_lock,row_start=row.start,row_finish=row.finish,min_time=bounds.min_time,max_time=bounds.max_time,moved=false}
   started=true
  end)
  down_last=down;pressed=started and 'seam_drag' or nil;UI.dirty();return true
 end
 local d=A.seam_drag
 if d and down then
  local dx=mouse_x-d.x
  if abs(dx)>=2 then
   d.moved=true;d.delta=Core.seam_boundary_delta(Core.seam_drag_delta(dx,d.seconds_per_px),d.edge,d.row_start,d.row_finish,d.relative,d.min_time,d.max_time)
  end
  down_last=down;UI.dirty();return true
 end
 if d and not down then
  A.seam_drag=nil;pressed=nil;down_last=false
  if d.moved and abs(d.delta)>1e-10 then
   A.seam_hold=d
   if not UI.safe(function() UI.move_loop_drag(d) end) then A.seam_hold=nil end
  else A.seam_hold=nil;UI.preview_refresh() end
  UI.dirty();return true
 end
 return false
end

BLT.factorySettings={};for k in ('filename directory sr bits channels encoding use_default_directory use_default_filename use_format embed_markers embed_regions exclude_selected_region embed_loop_region omit_name xfade_seconds add_mode unit interval_unit count relative_lock auto_audition length length_values interval interval_values'):gmatch('%S+') do BLT.factorySettings[k]=BLT.copy(A[k]) end
function BLT.pick(obj,keys) local v=BLT.valueView or {};BLT.valueView=v;for k in pairs(keys) do v[k]=obj[k] end;return v end
-- Shared BLT app restoration protocol. Each app owns one registry ID.
local BLTRestore={section='BLT_APP_RESTORE',id='BLT_LOOP_RM_STUDIO'}
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
 if actionSection==-1 and command==-1 and api.BLT_ProfileTarget==path then return end
 assert(actionSection==0 and path~='','BLT restore requires a Main action')
 local root=api.GetResourcePath()..'/Scripts'
 api.RecursiveCreateDirectory(root..'/BLT ReaScripts',0)
 restore_write(root..'/BLT ReaScripts/BLT_Restore_Open_Apps.lua',BLTRestoreLauncher)
 local startup=root..'/__startup.lua';local original=restore_read(startup)or''
 local marker='-- BLT_APP_RESTORE_STARTUP'
 if not original:find(marker,1,true)then
  local block=marker..'\ndo\n local path=reaper.GetResourcePath().."/Scripts/BLT ReaScripts/BLT_Restore_Open_Apps.lua"\n local fn=loadfile(path)\n if fn then local ok,err=pcall(fn);if not ok then reaper.ShowConsoleMsg(tostring(err).."\\n")end end\nend\n'
  restore_write(startup,block..original:gsub('^\239\187\191',''))
 else
  local old=' local path=reaper.GetResourcePath().."/Scripts/BLT/BLT_Restore_Open_Apps.lua"'
  local at=original:find(old,1,true)
  if at then
   local replacement=' local path=reaper.GetResourcePath().."/Scripts/BLT ReaScripts/BLT_Restore_Open_Apps.lua"'
   restore_write(startup,original:sub(1,at-1)..replacement..original:sub(at+#old))
  end
 end
 local legacy=root..'/BLT/BLT_Restore_Open_Apps.lua'
 local savedStartup=restore_read(startup) or ''
 if not savedStartup:find('/Scripts/BLT/BLT_Restore_Open_Apps.lua',1,true) and restore_read(legacy)==BLTRestoreLauncher then
  os.remove(legacy)
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
 Language.mb('ReaImGui 0.10以降と js_ReaScriptAPI が必要です。ReaPackで導入・更新してください。',APP_NAME,0);return
end
local ok,value=pcall(BLT.CanvasHost.new,R,APP_NAME,W,H+26,SECTION)
if not ok then Language.mb(BLT.publicError(value),APP_NAME,0);return end
Host=value;Host.minWidth,Host.minHeight,Host.persistSize=784,790,true
local savedW,savedH=tonumber(R.GetExtState(SECTION,'window_w')),tonumber(R.GetExtState(SECTION,'window_h'))
if R.GetExtState(SECTION,'render_button_balance_206')~='true' then
 if savedH then savedH=savedH+16 end
 BLT.store(SECTION,'render_button_balance_206','true',true)
end
Host.width=finite(savedW) and clamp(savedW,784,2200) or W
Host.height=finite(savedH) and clamp(savedH,790,1800) or H+26
local I,ctx=Host.I,Host.ctx
gfx=Host.g
local g=gfx
C={bg={.018,.030,.055},bg2={.030,.090,.180},panel={.040,.068,.110},panel2={.055,.125,.205},
 field={.018,.040,.080},edge={.145,.285,.445},edge2={.360,.650,.900},text={.955,.980,1},
 muted={.690,.780,.875},faint={.390,.505,.635},disabled={.43,.46,.51},accent={.120,.490,.980},
 accent2={.650,.895,1},accent3={.045,.235,.520},ice={.650,.895,1},focus={.225,.610,1},
 focus2={.690,.900,1},ink={.018,.075,.160},hover={.430,.790,1},warn={1,.755,.490},red={1,.18,.26},quiet={.30,.36,.44}}
U=BLT.Controls.new(gfx,R.time_precise,C);U.font,U.minFontSize=Host.faces[1],7
local density=BLT.Controls.compactScale
local awakeUntil=R.time_precise()+6.5
local pass=0
wake_visuals=function() A.content_dirty=true;awakeUntil=R.time_precise()+6.5 end
local fields={}
local function cancelEdit()
 if U.editor then U.editor:close(true) end
 U.capture=nil
end
local function applyField(field,raw,interactive)
 local result=raw
 if field.spec then
  local success,n=pcall(parse_field,field,tostring(raw))
  if not success or not finite(n) then
   UI.flash(field.id);notice('数値を入力できなかったため、元の値へ戻しました。',true);return
  end
  result=normalize_field_number(n,field.spec)
  if abs(result-n)>1e-12 then UI.flash(field.id) end
  if field.key=='serial_start' then
   local source=interactive and tostring(field.owner[field.key]) or tostring(raw):match('^%s*(.-)%s*$')
   result=string.format('%0'..clamp(#source,1,12)..'d',result)
  end
 else
  local err;result,err=normalized_text_value(field.key,raw)
  if not result then UI.flash(field.id);notice(err,true);return end
 end
 if field.owner[field.key]~=result then field.owner[field.key]=result;UI.refresh() end
end
function UI.flash(id) U:flash(id);UI.dirty() end
function UI.commit_edit()
 if U.editor and U.editor.edit then U.editor:close(false) end
 return true
end
function UI.begin_edit(id,owner,key,spec)
 UI.commit_edit()
 local field=fields[id] or {id=id};fields[id]=field
 field.owner,field.key,field.spec=owner,key,spec
 field.done=field.done or function(raw) UI.safe(applyField,field,raw,false);UI.dirty() end
 local text=key=='serial_start' and tostring(owner[key]) or field_text(owner[key],spec,key)
 if spec and spec[8] then text=string.format('%.'..spec[8]..'f',owner[key]):gsub('0+$',''):gsub('%.$','') end
 U.editor:open(id,text,field.done);U.focus=id;UI.dirty()
end
menu=BLT.PresetMenu.new(Host,U,{presets=Presets,language=Language,
 layout={width=292,rowHeight=29,headerHeight=36,visiblePresets=8,hoverDelay=1},commit=UI.commit_edit,
 busy=function() return A.busy or A.name_dialog~=nil end})
shell=BLT.Shell.new(Host,U,R,{
 title='LOOP RM STUDIO',subtitle='LOOP / REGION / MARKER MANAGER  ループ・リージョン・マーカー管理ツール',
 barTitle='L O O P   R M   S T U D I O',section=SECTION,persist=true,layout={iconX=W-102,iconY=9,iconScale=.78,footerSize=8},
 language=Language.code,languageChanged=Language.set,translate=Language.message,store=BLT.store,
 headerIcon=BLT.LoopStudioIcon,iconMode=function() return 'loop' end,
 stepPreset=function(direction) UI.commit_edit();Presets.step(direction) end,
 drawPresets=function(owner) menu:draw(owner) end,presetSize=function() return menu:size() end,dirty=Presets.dirty})
U.editor=BLT.TextInput.new(Host,U,shell.typography)
wave=BLT.LoopStudioWave.new(Host,R,shell.typography,Language,C)
Media.state=A;Media.onchange=UI.dirty
mediaGraphics.getchar=function() return Host.focused and 6 or 4 end
BLT.recoverInput=function(_,err)
 cancelEdit();A.popup=nil;A.name_dialog=nil;A.seam_drag=nil;U.down=false;pressed=nil;UI.dirty();BLT.logError(err)
end
local hintID,hintText,tooltipID,tooltipSince
local function sx(x) return ox+x*scale end
local function sy(y) return oy+y*scale end
local function color(c,a) gfx.set(c[1],c[2],c[3],a or 1) end
local function rect(x,y,w,h,c,a) color(c,a);gfx.rect(sx(x),sy(y),w*scale,h*scale,1) end
local function line(x,y,xx,yy,c,a) color(c,a);gfx.line(sx(x),sy(y),sx(xx),sy(yy),1) end
local function font(size,kind,bold) gfx.setfont(1,Host.faces[kind or 1],max(7,floor(size*scale+.5)),bold and 98 or 0) end
local function font_spec(size,kind,bold) return kind or 1,max(7,floor(size*scale+.5)),bold and 98 or 0 end
local function label(text,x,y,size,c,kind,w,h,flags,bold,literal)
 font(size,kind,bold);color(c or C.text);gfx.x,gfx.y=sx(x),sy(y)
 gfx.drawstr(literal and tostring(text) or Language.message(text),flags or 0,sx(x+(w or 700)),sy(y+(h or size+8)))
end
local function measure(text,size,kind,bold) font(size,kind,bold);return gfx.measurestr(Language.message(text))/scale end
local quietFrame={glow=false,panel=true}
local function cut_panel(x,y,w,h) U:frame(x/density,y/density,w/density,h/density,quietFrame) end
local function inside(x,y,w,h) return mouse_x>=x and mouse_x<x+w and mouse_y>=y and mouse_y<y+h end
local function hint(id,text,x,y,w,h)
 if text and inside(x,y,w,h) and not shell.popupOpen then hintID,hintText=id,Language.message(text) end
end
local function prime(id,x,y,w,h,enabled)
 if enabled and not U.blocked and U.pressed and U.editor.edit and inside(x,y,w,h) then U.capture=id;U.focus=id;U.hit=true end
end
function UI.geometry()
 local contentH=max(1,gfx.h-26);scale=max(.3,min(gfx.w/W,contentH/H))
 ox,oy=(gfx.w-W*scale)/2,26+(contentH-H*scale)/2-22*scale
 mouse_x,mouse_y=(gfx.mouse_x-ox)/scale,(gfx.mouse_y-oy)/scale
end
local buttonOptions={}
local function button(id,x,y,w,h,title,action,tip,enabled,accent,prominent,text_size,selected)
 enabled=enabled~=false and (not A.busy or id=='cancel')
 local opt=buttonOptions[id] or {};buttonOptions[id]=opt
 opt.enabled,opt.selected,opt.accent=enabled,selected,accent
 opt.size,opt.bold,opt.labelInset=(text_size or 13)/density,prominent==true,7/density
 opt.led=selected~=nil and 'top' or nil
 opt.ledScale=h/(44*density)
 prime(id,x,y,w,h,enabled)
 if U:button(id,Language.text(title),x/density,y/density,w/density,h/density,opt) then
  UI.commit_edit();UI.safe(action);UI.dirty()
 end
 hint(id,tip,x,y,w,h)
end
local insertOptions={leading='insert',trailing='color',size=13/density,labelInset=7/density,labelAlign='center',
 colorSize=18/density,leadingInset=15/density,leadingScale=1.1/density,leadingWidth=27/density}
local function insert_button(id,x,y,w,h,title,action,tip,accent)
 local kind=id:sub(5)
 insertOptions.enabled,insertOptions.color,insertOptions.accent=not A.busy,UI.insert_color(kind),accent
 prime(id,x,y,w,h,insertOptions.enabled)
 local clicked,colorClicked=U:button(id,Language.text(title),x/density,y/density,w/density,h/density,insertOptions)
 if clicked then UI.commit_edit();UI.safe(action);UI.dirty()
 elseif colorClicked then UI.safe(UI.select_insert_color,kind) end
 hint(id,tip,x,y,w,h)
end
local function panel(x,y,w,h,title,code)
 cut_panel(x,y,w,h)
 label(code or '',x+16,y+13,10,C.faint,2,w-30,16,0,true)
 label(title,x+16,y+31,16,C.text,1,w-30,26,0,true)
 line(x+16,y+58,x+w-16,y+58,C.edge,.22)
end
local toggleOptions={background=false,showState=false}
local function toggle(id,x,y,w,h,text,checked,action,tip,enabled,size,bold)
 enabled=enabled~=false and not A.busy
 toggleOptions.size,toggleOptions.bold,toggleOptions.switchScale=(size or 14.5)/density,bold,h/(44*density)
 prime(id,x,y,U:toggleWidth(id,Language.text(text),w/density,h/density,toggleOptions)*density,h,enabled)
 local value,clicked,hitWidth=U:toggle(id,Language.text(text),checked,x/density,y/density,w/density,h/density,enabled,toggleOptions)
 if clicked and value~=checked then UI.commit_edit();UI.safe(action);UI.dirty() end
 hint(id,tip,x,y,hitWidth*density,h)
end
local function checkbox(id,x,y,w,text,checked,action,tip,enabled,text_size)
 toggle(id,x,y,w,26,text,checked,action,tip,enabled,text_size or 12,false)
end
local function slide_toggle(id,x,y,w,text,checked,action,tip,enabled)
 toggle(id,x,y,w,24,text,checked,action,tip,enabled,14.5,true)
end
local relativeOptions={showState=false,size=9.5/density,bold=true}
local function relative_toggle(x,y,w,h)
 relativeOptions.enabled,relativeOptions.ledScale=not A.busy,h/(44*density)
 prime('relative_lock',x,y,w,h,relativeOptions.enabled)
 local value,clicked=U:gold('relative_lock',Language.text('相対保持'),A.relative_lock,x/density,y/density,w/density,h/density,relativeOptions)
 if clicked then UI.commit_edit();A.relative_lock=value;UI.safe(UI.refresh);UI.dirty() end
 hint('relative_lock','ONでは開始と終了を同じ量だけ移動し、ループ尺を保持',x,y,w,h)
end
function UI.field(key,x,y,w,enabled,owner,textonly)
 owner=owner or A;local id='field_'..key;local spec=not textonly and field_spec(key) or nil
 local f=fields[id] or {id=id};fields[id]=f;f.owner,f.key,f.spec=owner,key,spec
 f.done=f.done or function(raw) UI.safe(applyField,f,raw,false);UI.dirty() end
 local state=U:state(id);state.done=f.done
 local opt=f.options or {};f.options=opt
 opt.enabled=enabled~=false and not A.busy;opt.kind=spec and 'number' or nil
 opt.size=(textonly and 13 or 16)/density;opt.autoSize=false
 opt.face,opt.bold,opt.align=Host.faces[spec and 3 or 1],spec~=nil,spec and 'right' or nil
 opt.calibrate=not spec;opt.opticalCenter=spec~=nil
 if spec then
  local fine=(gfx.mouse_cap&8)~=0 and Core.field_allows_fine(key,spec)
  opt.min,opt.max,opt.step,opt.fineStep=spec[1],spec[2],spec[4],Core.field_allows_fine(key,spec) and .1 or 1
  opt.dragDistance,opt.rebaseDrag=(fine and 8 or 3)/density,true
  opt.suffix,opt.inset,opt.valueInset,opt.gap='',(key=='count' and 3 or 7)/density,(key=='count' and 3 or 8)/density,0
  opt.normalize=opt.normalize or function(raw)
   local success,n=pcall(parse_field,f,tostring(raw));if not success or not finite(n) then return nil,true end
   local requested=n
   local unit=key=='length' and A.unit or key=='interval' and A.interval_unit or nil
   local minimum=Core.interactive_floor(key,unit,(gfx.mouse_cap&8)~=0 and Core.field_allows_fine(key,f.spec))
   if minimum then n=max(n,minimum) end
   n=normalize_field_number(n,f.spec);return n,abs(n-requested)>1e-12
  end
  opt.format=opt.format or function(value)
   if key=='serial_start' then return string.format('%0'..clamp(#tostring(f.owner[key]),1,12)..'d',value) end
   return field_text(value,f.spec,key)
  end
 end
 local previous=owner[key];local value=spec and tonumber(previous) or tostring(previous or '')
 local h=textonly and 32 or 36;prime(id,x,y,w,h,opt.enabled)
 local result=U:field(id,value,x/density,y/density,w/density,h/density,opt)
 if result~=value then UI.safe(applyField,f,result,true) end
 local tip=spec and 'クリック入力 / 上下ドラッグ / ホイール' or 'クリックして直接入力'
 if key=='count' then tip='クリック入力 / 上下ドラッグ / ホイール。0＝A：選択時間÷（基準幅＋間隔補正）の整数部分を自動挿入。計算できない場合は1個、最大1000個。'
 elseif key=='filename' then tip=tip..' / REAPERワイルドカード使用可' end
 if spec and Core.field_allows_fine(key,spec) then tip=tip..' / Shiftで微調整' end
 if spec and not U.editor.edit and inside(x,y,w,h) then tip=opt.format(tonumber(owner[key]))..'\n'..tip end
 hint(id,tip,x,y,w,h)
end
local dropdownOptions={trailing='menu',labelInset=7/density,center=false}
local function dropdown(id,x,y,w,h,text,action,tip,enabled,text_size)
 dropdownOptions.enabled,dropdownOptions.size=enabled~=false and not A.busy,(text_size or 13)/density
 prime(id,x,y,w,h,dropdownOptions.enabled)
 if U:button(id,Language.message(text),x/density,y/density,w/density,h/density,dropdownOptions) then
  UI.commit_edit();UI.menu_anchor={id=id,x=x,y=y,w=w,h=h};UI.safe(action)
 end
 hint(id,tip,x,y,w,h)
end
local execution={autoComplete=false,finishWhenDisabled=true,size=15/density,bold=true,
 captionY=5/density,captionHeight=11/density,captionSize=8/density,labelY=19/density,labelHeight=26/density}
local completedStamp
local function drawExecute(now)
 local b=A.render_batch;local completed=not A.busy and A.render_complete_until and now<A.render_complete_until
 if completed and completedStamp~=A.render_complete_until then
  completedStamp=A.render_complete_until;U:complete('execute',310/density,52/density)
 end
 execution.busy,execution.progress=A.busy,A.busy and A.progress or completed and 1 or nil
 execution.caption=b and UI.render_stages[b.phase].caption or A.ajob and 'ANALYZING' or A.busy and 'WRITING WAV' or completed and 'COMPLETE' or 'RENDER'
 local title=A.busy and ('処理中'..(b and b.index>0 and string.format('  %d/%d',b.index,b.count) or '')) or 'レンダリング実行'
 if U:execute('execute',Language.message(title),335/density,864/density,310/density,52/density,execution) then UI.commit_edit();UI.render_mix() end
 hint('execute',b and '工程全体の進捗です。標準レンダー中の詳細はREAPERのレンダラーに表示されます。' or 'Master mixをレンダーして区間情報を埋め込む',335,864,310,52)
 if A.busy and (b or A.job or A.xjob or A.ajob) then button('cancel',678,877,92,29,'中止',UI.cancel,'処理を中止',true,C.warn) end
end
local function tooltip(now)
 if hintID~=tooltipID then tooltipID,tooltipSince=hintID,now end
 if hintText and not U.down and not shell.popupOpen and not A.popup and not U.editor.edit and now-(tooltipSince or now)>=.7 then
  I.PushFont(ctx,Host.font,12);I.SetTooltip(ctx,hintText);I.PopFont(ctx)
 end
end

local function validPreset(v) local function valid(n,r) return type(n)=='number' and n>=r[1] and n<=r[2] and (not r[3] or n%1==0) end;if not Core.length_specs[v.unit] or not Core.interval_specs[v.interval_unit] then return false end;if not valid(v.count,Core.count_spec) or not valid(v.xfade_seconds,{.000001,10}) or not valid(v.sr,{8000,384000,true}) then return false end;for k,n in pairs(v.length_values) do local r=Core.length_specs[k];if not r or not valid(n,r) then return false end end;for k,n in pairs(v.interval_values) do local r=Core.interval_specs[k];if not r or not valid(n,r) then return false end end;if not valid(v.length,Core.length_specs[v.unit]) or not valid(v.interval,Core.interval_specs[v.interval_unit]) then return false end;local channel=false;for _,x in ipairs(Core.channel_options) do if v.channels==x then channel=true end end;return channel and (v.encoding=='UTF-8' or v.encoding=='CP932') and (v.add_mode=='selection' or v.add_mode=='items' or v.add_mode=='itemblocks' or v.add_mode=='itemspan' or v.add_mode=='cursor') and (v.bits==16 or v.bits==24 or v.bits==32) end
BLT.attachPresets({R=R,section=SECTION,wake=UI.dirty,defaults=BLT.factorySettings,
 capture=function() return BLT.pick(A,BLT.factorySettings) end,valid=validPreset,
 apply=function(v) for key,value in pairs(v) do A[key]=value end;UI.refresh() end,
 busy=function() return A.busy or A.name_dialog~=nil end,commit=UI.commit_edit,cancelEdit=function() cancelEdit();A.popup=nil end})

local ADD_LABELS={selection='選択範囲',items='選択アイテム（個別）',itemblocks='選択アイテム（ブロック）',itemspan='選択アイテム全体',cursor='カーソル位置'}
local UNIT_LABELS={seconds='秒',beats='拍',bars='小節',grid='グリッド'}
local ENCODING_HINT='原則UTF-8を推奨\nSoundForgeで日本語を文字化けさせたくない場合のみCP932を選択してください。\nただし他の大多数アプリケーションで文字化けします。※英語圏には無関係な機能です'
function UI.menu(values,current,display,fn)
 local a=assert(UI.menu_anchor,'Dropdown anchor missing')
 if A.popup and A.popup.id==a.id then A.popup=nil;UI.dirty();return end
 local selected=1;for i,v in ipairs(values) do if v==current then selected=i end end
 local rows=max(1,min(8,#values,floor((H-24-a.y-a.h-4)/28)))
 A.popup={id=a.id,x=a.x,y=a.y+a.h+4,w=a.w,h=rows*28+4,rows=rows,scroll=clamp(selected-rows,0,max(0,#values-rows)),selected=selected,values=values,current=current,display=display,fn=fn}
 UI.dirty()
end
function UI.popup_pick(index)
 local p=A.popup;if not p or not p.values[index] then return end
 A.popup=nil;pressed=nil;p.fn(p.values[index]);UI.refresh()
end
function UI.popup_key(k)
 local p=A.popup;if not p then return end
 if k==27 then A.popup=nil;pressed=nil;UI.dirty()
 elseif k==13 then UI.popup_pick(p.selected)
 elseif k==30064 or k==1685026670 then
  p.selected=clamp(p.selected+(k==30064 and -1 or 1),1,#p.values)
  p.scroll=clamp(p.scroll,max(0,p.selected-p.rows),p.selected-1);UI.dirty()
 end
end
function UI.popup_input()
 local p=A.popup;local down=(gfx.mouse_cap&1)~=0
 local within=not shell.hot and inside(p.x,p.y+2,p.w,p.rows*28)
 local index=within and p.scroll+floor((mouse_y-p.y-2)/28)+1 or nil
 if down and not down_last then
  if index then p.pressed=index else A.popup=nil end
  pressed=nil;UI.dirty()
 elseif not down and down_last then
  if index and index==p.pressed then UI.safe(function() UI.popup_pick(index) end) end
  p.pressed=nil;UI.dirty()
 end
 down_last=down
 if gfx.mouse_wheel~=0 then
  p.scroll=clamp(p.scroll-floor(gfx.mouse_wheel/120),0,max(0,#p.values-p.rows))
  gfx.mouse_wheel=0;UI.dirty()
 end
end
function UI.draw_popup()
 local p=A.popup;if not p then return end
 rect(p.x,p.y,p.w,p.h,C.field,1)
 for row=1,p.rows do
  local index=p.scroll+row;local value=p.values[index];local y=p.y+2+(row-1)*28
  local hot=inside(p.x,y,p.w,28)
  if hot or index==p.selected then rect(p.x+1,y,p.w-2,28,C.accent3,.85) end
  if value==p.current then rect(p.x+5,y+9,3,10,C.accent2,1) end
  label(p.display and p.display(value) or tostring(value),p.x+15,y+4,12,hot and C.text or C.muted,1,p.w-28,22)
 end
 if #p.values>p.rows then
  local h=p.h*p.rows/#p.values;local y=p.y+(p.h-h)*p.scroll/(#p.values-p.rows)
  rect(p.x+p.w-5,y,3,h,C.accent2,.65)
 end
end

function UI.draw_period_notice(now)
 local d=A.period_notice;if not d then return end
 local alpha=now<d.fade_at and 1 or clamp((d.finish-now)/(d.finish-d.fade_at),0,1)
 if alpha<=0 then return end
 local w,h=430,72;local x,y=(W-w)/2,360
 rect(x-12,y-10,w+24,h+20,C.warn,.025*alpha)
 rect(x-6,y-5,w+12,h+10,C.warn,.045*alpha)
 cut_panel(x,y,w,h)
 line(x+18,y+1,x+w-22,y+1,C.warn,.72*alpha)
 font(18,1,true);color(C.warn,alpha);gfx.x,gfx.y=sx(x+18),sy(y+8)
 gfx.drawstr(Language.message(d.text),1|4,sx(x+w-18),sy(y+h-8))
end
function UI.period_notice_tick(now)
 if A.period_notice and now>=A.period_notice.finish then A.period_notice=nil;UI.dirty() end
end


function UI.draw_name_dialog()
 local d=A.name_dialog;if not d then return end
 rect(0,0,W,H,C.bg,.87);U.blocked=false
 local x,y=240,370
 rect(x,y,500,280,C.panel,1)
 label('名前と番号を設定',x+22,y+18,19,C.text,1,456,30)
 local item_name_width=40+math.ceil(measure('選択アイテム名を使用',12,1))
 checkbox('use_item_name',x+22,y+58,item_name_width,'選択アイテム名を使用',d.use_item_name,function()
  if not UI.commit_edit() then return end
  d.use_item_name=not d.use_item_name;UI.dirty()
 end,'ONではアイテム名をそのまま使用（連番なし）',d.item_names_available,12)
 checkbox('ignore_extension',x+32+item_name_width,y+58,172,'拡張子を無視',d.ignore_extension,function()
  d.ignore_extension=not d.ignore_extension;UI.dirty()
 end,'アイテム名の末尾の拡張子を除いて使用',d.item_names_available and d.use_item_name,12)
 label('名前',x+22,y+100,12,d.use_item_name and C.faint or C.muted,1,80,23)
 UI.field('name',x+112,y+94,364,not d.use_item_name,d,true)
 checkbox('serial',x+22,y+149,205,'番号を付与',d.numbering,function() d.numbering=not d.numbering;UI.dirty() end,'OFFではすべて同じ名前で追加',not d.use_item_name)
 label('開始番号',x+254,y+154,12,d.use_item_name and C.faint or C.muted,1,80,22)
 UI.field('serial_start',x+342,y+145,134,d.numbering and not d.use_item_name,d,false)
 label('1 → 1, 2, 3    /    001 → 001, 002, 003',x+22,y+190,12,C.faint,1,456,22)
 button('name_cancel',x+220,y+231,112,30,'キャンセル',function() A.name_dialog=nil;UI.dirty() end,'追加を取り消す')
 button('name_ok',x+344,y+231,132,30,'追加',UI.confirm_name,'指定した名前で追加')
end


function UI.draw_wave_hint(hint,x,y,w,h)
 local text,size=hint,15
 if hint=='アイテムが選択されていません' then
  size=19
 elseif hint=='選択アイテム範囲に収まるループリージョンがありません' then
  text='選択アイテム範囲に収まる\nループリージョンがありません';size=18
 elseif hint=='選択アイテム範囲にループリージョンが複数存在しています！' then
  text='選択アイテム範囲に\nループリージョンが\n複数存在しています！';size=17.5
 elseif hint=='継ぎ目を読み取り中…' then size=18 end

 local content_top,content_bottom=y+28,y+h-12
 local max_width,max_height=w-48,content_bottom-content_top
 local gap=5
 local function layout(at_size)
  local lines={}
  local function add_wrapped(raw)
   if raw=='' then lines[#lines+1]='';return end
   local current=''
   for ch in raw:gmatch(utf8.charpattern) do
    local candidate=current..ch
    if current~='' and measure(candidate,at_size,1,true)>max_width then
     lines[#lines+1]=current;current=ch
    else current=candidate end
   end
   lines[#lines+1]=current
  end
  for raw in (text..'\n'):gmatch('(.-)\n') do add_wrapped(raw) end
  local _,pixels=font_spec(at_size,1,true)
  local line_height=pixels/scale+gap
  return lines,line_height,#lines*line_height-gap
 end

 local lines,line_height,block_height
 while true do
  lines,line_height,block_height=layout(size)
  if block_height<=max_height or size<=12 then break end
  size=size-.5
 end
 if block_height>max_height then
  local count=max(1,floor((max_height+gap)/line_height))
  while #lines>count do lines[#lines]=nil end
  lines[count]='…';block_height=#lines*line_height-gap
 end

 font(size,1,true)
 local top=content_top+(max_height-block_height)/2
 local function draw_line(line_text,line_y,dx,dy)
  local width=measure(line_text,size,1,true)
  gfx.x,gfx.y=sx(x+(w-width)/2+dx),sy(line_y+dy)
  gfx.drawstr(Language.message(line_text))
 end
 for dx=-2,2 do for dy=-2,2 do
  if dx~=0 or dy~=0 then
   local inner=abs(dx)<=1 and abs(dy)<=1
   color(inner and C.accent2 or C.focus,inner and .060 or .026)
   for i,line_text in ipairs(lines) do draw_line(line_text,top+(i-1)*line_height,dx,dy) end
  end
 end end
 color(C.focus2,.98)
 for i,line_text in ipairs(lines) do draw_line(line_text,top+(i-1)*line_height,0,0) end
end

function UI.wave_hover_tick(blocked)
 local b=A.wave_hover_bounds;local side
 if b and inside(b.x,b.y,b.w,b.h) then side=mouse_x<b.mid and 'left' or 'right' end
 local entered=side and side~=A.wave_hover_side
 -- Track entry even while dragging/refreshing. Releasing in the other pane
 -- must not turn that suppressed entry into a delayed flash.
 A.wave_hover_side=side
 if entered and not blocked and A.active~=false and not A.popup and not A.name_dialog
  and A.seam and not A.busy and not A.seam_refreshing and not A.seam_drag and (gfx.mouse_cap&3)==0 then
  A.wave_entry_flash=A.wave_entry_flash or {};A.wave_entry_flash[side]=R.time_precise();UI.dirty()
 end
end
function UI.draw_wave_entry_flash(x,y,w,h,mid)
 local flashes=A.wave_entry_flash;if not flashes then return end
 local now=R.time_precise()
 for side,start in pairs(flashes) do
  local remaining=1-(now-start)/.30
  if remaining<=0 then flashes[side]=nil
  else
   local left=side=='left' and x+1 or mid+1;local right=side=='left' and mid-1 or x+w-1
   rect(left,y+1,right-left,h-2,C.hover,.28*remaining*remaining)
  end
 end
end
function UI.paint_seam(x,y,w,h)
 rect(x,y,w,h,C.field,1)
 local inner_left,mid,inner_right,half=Core.seam_geometry(x,w)
 local bounds=A.wave_hover_bounds or {};A.wave_hover_bounds=bounds
 bounds.x,bounds.y,bounds.w,bounds.h,bounds.mid=x,y,w,h,mid
 UI.draw_wave_entry_flash(x,y,w,h,mid)
 local function center_line(color_value,alpha,glow)
  for yy=y+20,y+h-5,8 do local ending=min(yy+4,y+h-5)
   if glow then line(mid-1,yy,mid-1,ending,color_value,.10);line(mid+1,yy,mid+1,ending,color_value,.10) end
   line(mid,yy,mid,ending,color_value,alpha)
  end
 end
 label('終了 −6 ms  /  DRAG',inner_left+2,y+3,10,C.muted,1,half-4,17)
 label('開始 ＋6 ms  /  DRAG',mid+2,y+3,10,C.muted,1,half-4,17)
 center_line(C.accent2,.65,false)
 local a=A.seam
 if not a then
  local hint=A.pjob and '継ぎ目を読み取り中…' or A.seam_problem or 'アイテムが選択されていません'
  UI.draw_wave_hint(hint,x,y,w,h)
   return
 end
 local drag=A.seam_drag;local d=drag or A.seam_hold
 local function visible(p)
  local window=p.windows[1];local data=window.audio;local draw_ch=window.draw_ch or min(2,p.ch);local frames=#data//draw_ch
  local left=p.preview_side=='finish'
  local start=p.preview_origin and (mid+(p.s+window.first/p.sr-p.preview_origin)/Core.SEAM_SECONDS*half) or (left and (mid-frames/p.sr/Core.SEAM_SECONDS*half) or mid)
  local follows=d and (d.relative or (d.edge=='finish' and left) or (d.edge=='start' and not left))
  if follows then start=start+Core.seam_wave_shift(d.delta,half) end
  local clip_left,clip_right=left and inner_left or mid,left and mid or inner_right
  local pixels_per_frame=half/(Core.SEAM_SECONDS*p.sr)
  local first=max(0,floor((clip_left-start)/pixels_per_frame)-1)
  local last=min(frames-1,math.ceil((clip_right-start)/pixels_per_frame)+1)
  local v=p._draw_view or {};p._draw_view=v
  v.data,v.draw_ch,v.start,v.clip_left,v.clip_right,v.pixels_per_frame,v.first,v.last=data,draw_ch,start,clip_left,clip_right,pixels_per_frame,first,last
  return v
 end
 local channels=1;local visible_peak=.001
 for _,p in ipairs(a) do
  local v=visible(p);channels=max(channels,v.draw_ch)
  if v.last>=v.first then for f=v.first,v.last do for c=1,v.draw_ch do
   visible_peak=max(visible_peak,abs(v.data[f*v.draw_ch+c]))
  end end end
 end
 local lane=(h-26)/channels
 for c=1,channels do
  local cy=y+23+(c-.5)*lane
  line(inner_left,cy,inner_right,cy,C.edge,.4)
  label(channels==1 and 'M' or c==1 and 'L' or 'R',x+4,cy-lane/2+1,8,C.faint,3,12,12)
  for _,p in ipairs(a) do local v=p._draw_view
   if c<=v.draw_ch and v.last>=v.first then
    -- Preserve the minimum and maximum sample in every screen column. Picking
    -- one sample per stride can alias a periodic/high-frequency waveform into
    -- an apparently empty horizontal line.
    local color_value=c==1 and C.accent2 or C.focus
    local column,column_min,column_max,previous_x,previous_y
    local function flush_column()
     if not column then return end
     local upper=cy-column_max/visible_peak*(lane*.4)
     local lower=cy-column_min/visible_peak*(lane*.4)
     local center=(upper+lower)/2
     if previous_x then line(previous_x,previous_y,column,center,color_value,.72) end
     if lower-upper>=.5 then line(column,upper,column,lower,color_value,.92)
     else line(column-.5,center,column+.5,center,color_value,.92) end
     previous_x,previous_y=column,center
    end
    for f=v.first,v.last do
     local px=v.start+f*v.pixels_per_frame
     if px>=v.clip_left and px<=v.clip_right then
      local xcol=floor(px+.5);local sample=v.data[f*v.draw_ch+c]
      if column~=xcol then
       flush_column();column=xcol;column_min=sample;column_max=sample
      else column_min=min(column_min,sample);column_max=max(column_max,sample) end
     else
      flush_column();column,column_min,column_max,previous_x,previous_y=nil,nil,nil,nil,nil
     end
    end
    flush_column()
   end
  end
 end
 if A.seam_refreshing then
  rect(x+w-66,y+h-21,58,16,C.bg,.82);label('更新中…',x+w-63,y+h-21,9,C.warn,1,52,15,1,true)
 end
 if drag then
  local left=drag.edge=='finish';local shade_x=drag.relative and inner_left or (left and inner_left or mid)
  rect(shade_x,y,drag.relative and inner_right-inner_left or half,h,drag.relative and C.warn or C.accent,.055)
  center_line(drag.relative and C.warn or C.focus,.95,true)
  local text=(left and '終了 ' or '開始 ')..string.format('%+.4f s',drag.delta)..(drag.relative and '  /  相対保持' or '')
  local tw=min(w-24,measure(text,11,1,true)+18);local tx=clamp(mouse_x-tw/2,x+8,x+w-tw-8)
  rect(tx,y+h-25,tw,19,C.bg,.88);label(text,tx+8,y+h-24,11,drag.relative and C.warn or C.focus2,1,tw-16,18,1,true)
 end
end


function UI.draw_seam(x,y,w,h)
 local inner_left,mid,inner_right,half=Core.seam_geometry(x,w)
 local b=A.wave_hover_bounds or {};A.wave_hover_bounds=b
 b.x,b.y,b.w,b.h,b.mid,b.half=x,y,w,h,mid,half
 if wave:begin(A,sx(x),sy(y),w,h,scale,U.now) then
  local canvas=gfx;gfx=wave.canvas
  local success,err=xpcall(UI.paint_seam,debug.traceback,x,y,w,h)
  gfx=canvas;if not success then error(err,0) end
  wave:finish()
 end
 wave:draw(sx(x),sy(y),w,h,scale)
 local tip='波形を右へドラッグ＝時間位置を前へ / 左へドラッグ＝後ろへ / クリックで更新'
 if not A.seam then
  local clicked=U:interaction('seam_refresh',x/density,y/density,w/density,h/density,not A.busy)
  if clicked then UI.safe(UI.preview_refresh) end
  tip=(A.pjob and '継ぎ目を読み取り中…' or A.seam_problem or 'アイテムが選択されていません')..' / クリックで更新'
 end
 hint('wave',tip,x,y,w,h)
end
function UI.interact()
 local down=U.down
 local blocked=U.blocked or shell.popupOpen or shell.hot or A.name_dialog
 UI.wave_hover_tick(blocked)
 if blocked then down_last=down;pressed=nil;return end
 if A.popup then
  gfx.mouse_wheel=U.wheel;UI.popup_input();gfx.mouse_wheel=0;U.wheel=0;U.blocked=true;return
 end
 local b=A.wave_hover_bounds
 local hit
 if b and inside(b.x,b.y,b.w,b.h) and A.seam and not A.busy and not A.seam_refreshing then
  hit=b.hit or {seam={}};b.hit=hit;hit.seam.mid=b.mid
  hit.seam.seconds_per_px=Core.SEAM_SECONDS/b.half
 end
 if hit and U.pressed then U.capture='seam_drag';U.focus=nil;U.hit=true end
 if UI.seam_input(hit,down) then return end
 down_last=down
end
local function keypress(key)
 if shell.popupOpen or Host.drag then return end
 if U.editor.edit then return end
 if A.name_dialog then
  if key==27 then cancelEdit();A.name_dialog=nil;UI.dirty() elseif key==13 then UI.safe(UI.confirm_name) end
  U.key=0;return
 end
 if A.popup then UI.popup_key(key);U.key=0;return end
 if Core.undo_shortcut(key,gfx.mouse_cap) then cancelEdit();UI.safe(UI.project_undo);U.key=0
 elseif key==27 then
  if A.busy then UI.safe(UI.cancel) elseif A.audition then UI.stop_loop_audition(true) else A.manualClose=true;A.closing=true end
  U.key=0
 end
end
function UI.draw(now)
 UI.geometry();shell:begin();U.active=Host.focused;U.themeEnabled=shell.theme.enabled
 if A.name_dialog or A.popup then Host.drag=nil;shell.capture=nil;shell.hot=nil;shell.pressed=false;shell.released=false end
 color(C.bg);gfx.rect(0,0,gfx.w,gfx.h,1)
 U.scale,U.ox,U.oy=scale,ox,oy+22*scale;shell:header(W)
 local key=gfx.getchar()
 U:begin(density*scale,ox,oy,key)
 hintID,hintText=nil,nil
 keypress(key)
 UI.interact();U.blocked=U.blocked or A.name_dialog~=nil or A.popup~=nil
 panel(20,92,940,156,'ループ・リージョン・マーカーを追加','AUTHOR')
 local kinds={{'marker',36,178,'マーカー'},{'region',222,178,'リージョン'},{'sustain',408,390,'ループ（サステイン）'}}
 local item_mode=A.add_mode=='items' or A.add_mode=='itemblocks' or A.add_mode=='itemspan'
 if item_mode then A.last_item_mode=A.add_mode end
 local function mode_button(mode,x,y,w,h,text)
  local selected=A.add_mode==mode
  button('mode_'..mode,x,y,w,h,text,function() UI.set_add_mode(mode) end,ADD_LABELS[mode]..'を配置元にする',true,nil,false,nil,selected)
 end
 mode_button('selection',36,159,96,32,ADD_LABELS.selection)
 button('mode_items_parent',138,153,282,18,'選択アイテム',function() UI.set_add_mode(A.last_item_mode or 'items') end,'選択アイテムから配置範囲を作成',true,nil,false,11.5,item_mode)
 line(148,172,410,172,item_mode and C.accent2 or C.edge,.5)
 mode_button('items',138,176,88,20,'個別')
 mode_button('itemblocks',232,176,88,20,'ブロック')
 mode_button('itemspan',326,176,94,20,'全体')
 mode_button('cursor',426,159,92,32,ADD_LABELS.cursor)
 local cursor=A.add_mode=='cursor'
 label('個数',526,163,10.5,cursor and C.text or C.faint,1,30,26,2|4,true)
 UI.field('count',562,157,42,cursor)
 label('基準幅',610,163,10.5,cursor and C.text or C.faint,1,42,26,2|4,true)
 UI.field('length',658,157,48,cursor)
 dropdown('unit',709,157,68,36,UNIT_LABELS[A.unit],function()
  UI.menu({'seconds','beats','bars','grid'},A.unit,function(v) return UNIT_LABELS[v] end,UI.set_unit)
 end,'リージョンの長さ／マーカーの配置基準幅',cursor,11.5)
 label('間隔補正',781,163,10.5,cursor and C.text or C.faint,1,50,26,2|4,true)
 UI.field('interval',837,157,49,cursor)
 dropdown('interval_unit',889,157,67,36,UNIT_LABELS[A.interval_unit],function()
  UI.menu({'seconds','beats','bars','grid'},A.interval_unit,function(v) return UNIT_LABELS[v] end,UI.set_interval_unit)
 end,'次の配置位置＝現在位置＋基準幅＋間隔補正。-基準幅で同位置、さらに小さい負値で左方向',cursor,11.5)
 local add_flash=A.add_kind_flash and clamp(1-(now-A.add_kind_flash)/.65,0,1) or 0
 for _,k in ipairs(kinds) do
  insert_button('add_'..k[1],k[2],207,k[3],30,k[4],function() UI.add(k[1]) end,ADD_LABELS[A.add_mode]..' → '..k[4],kind_color(k[1]))
  if add_flash>0 then
   local pulse=add_flash*add_flash
   rect(k[2]-5,202,k[3]+10,40,C.focus,.045*pulse)
   rect(k[2]-2,205,k[3]+4,34,C.focus,.090*pulse)
   rect(k[2]+1,208,k[3]-2,28,C.accent2,.105*pulse)
  end
 end
 checkbox('omit_name',803,210,153,'名前入力を省略',A.omit_name,function() A.omit_name=not A.omit_name;UI.refresh() end,'ONでは追加時の名前入力を省略します',nil,14)
 panel(20,262,940,238,'ループ調整','LOOP ADJUSTMENT')
 local loop_state=A.loop_enable or {};local transport_ready=(R.GetPlayStateEx(A.project)&4)==0 and abs(R.Master_GetPlayRate(A.project)-1)<1e-9
 button('crossfade',36,321,228,28,'クロスフェードを適用',UI.crossfade,'レベル突出を抑える滑らかなカーブで指定時間分だけ加工。時間は2サンプル〜ループ長に自動補正',loop_state.crossfade and transport_ready,nil,true,12.5)
 label('時間',276,322,13,C.text,1,38,27,2|4,true)
 UI.field('xfade_seconds',317,317,110,true);label('s',435,325,12,C.faint,3,28,22,4,true)
 local function adjust_row(mode,y,text)
  local mode_ready=loop_state[mode] and transport_ready
  button(mode=='zero' and 'zero_cross' or 'period',36,y,228,28,text,function() UI.adjust_loop(mode) end,'開始・終了の両方を近い位置へ調整',mode_ready,nil,true,12.5)
  local locked=A.relative_lock
  for _,edge in ipairs({{'finish',276,'終了'},{'start',382,'開始'}}) do
   label(edge[3],edge[2],y,10,not mode_ready and C.faint or locked and C.warn or C.muted,1,28,28,2|4,locked and mode_ready)
   for i,d in ipairs({-1,1}) do
    local x=edge[2]+31+(i-1)*28
    local hint=locked and edge[3]..'と反対端を同じ量だけ移動（ループ尺を保持）' or edge[3]..'だけを'..(d<0 and '前' or '次')..'の'..(mode=='zero' and 'ゼロクロス' or '周期')..'へ移動'
    button(mode..'_'..edge[1]..'_'..d,x,y+2,24,24,d<0 and '◀' or '▶',function() UI.adjust_loop(mode,edge[1],d) end,hint,mode_ready,locked and C.warn or nil)
   end
  end
  if locked and mode_ready then line(307,y+27,465,y+27,C.warn,.30) end
 end
 adjust_row('zero',365,'最寄りゼロクロスへ補正')
 adjust_row('period',409,'周期を検出し補正')
 relative_toggle(342,393,76,16)
 slide_toggle('auto_audition',36,455,428,'調整後、繋ぎ目を自動再生',A.auto_audition,function()
  A.auto_audition=not A.auto_audition;if not A.auto_audition then UI.stop_loop_audition(true) end;UI.refresh()
 end,'通常はループ末端の0.75秒前から再生。クロスフェード時はその開始点（最低0.75秒前）から再生し、1回ループした約1秒後に停止',not A.busy)
 UI.draw_seam(488,278,456,207)
 panel(20,514,940,329,'レンダリング設定','RENDER SETTINGS')
 label('対象',36,584,13,C.text,1,138,22,4,true)
 button('master_mix',185,579,169,31,'マスターミックス',function() end,'マスターミックス\n現状マスターミックスのみ対応としています。',false)
 button('range_fixed',368,579,218,31,'選択リージョン',function() end,'選択リージョン\n現状選択リージョンの書き出しのみ対応しています。\nREAPER本体や、BLT MARKER REGION DESK等でリージョンを選択してください。',false)
 label('Master mix  /  REAPERで選択した各リージョンを個別のWAVとしてレンダリングします',36,621,11,C.faint,1,905,20)
 line(36,651,607,651,C.edge,.28)

 label('フォーマット',36,658,13,C.text,1,102,26,4,true)
 checkbox('format_defaults',145,658,439,'REAPER本体の設定を使用',A.use_format,function() A.use_format=not A.use_format;UI.refresh() end,'WAVのビット深度・サンプルレート・チャンネル数をREAPER本体から参照',true,12)
 local f=A.format or {};local manual=not A.use_format
 label('形式',36,696,11,C.faint,1,92,20)
 label('ビット深度',146,696,11,C.faint,1,122,20)
 label('サンプルレート',284,696,11,C.faint,1,137,20)
 label('チャンネル',439,696,11,C.faint,1,140,20)
 button('format',36,718,96,31,'WAV',function() end,'WAV\n現状WAVのみ対応としています。\nOGG等への対応はしていません。',false)
 dropdown('bits',146,718,124,31,f.bits and (f.bits..(f.bits==32 and ' bit float' or ' bit PCM')) or '—',function()
  UI.menu({16,24,32},A.bits,function(v) return v..(v==32 and ' bit float' or ' bit PCM') end,function(v) A.bits=v end)
 end,'WAVのビット深度',manual)
 dropdown('sr',284,718,141,31,f.sr and (f.sr..' Hz') or '—',function()
  UI.menu(Core.sample_rates,A.sr,function(v) return v..' Hz' end,function(v) A.sr=v end)
 end,'出力サンプルレート',manual)
 dropdown('ch',439,718,145,31,f.channels and (f.channels==1 and 'Mono' or f.channels==2 and 'Stereo' or f.channels..' ch') or '—',function()
  UI.menu(Core.channel_options,A.channels,function(v) return v==1 and 'Mono' or v==2 and 'Stereo' or v..' ch' end,function(v) A.channels=v end)
 end,'出力チャンネル数',manual)
 line(607,579,607,749,C.edge,.28)
 label('出力先',624,584,13,C.text,1,70,22,4,true)
 local dir=A.use_default_directory and (A.default_directory~='' and A.default_directory or '（プロジェクトの標準保存先）') or A.directory
 local name=A.use_default_filename and (A.default_pattern~='' and A.default_pattern or '（REAPERの既定名）') or (A.filename..'.wav')
 label('保存フォルダー',624,610,11,C.faint,1,58,26,4)
 checkbox('directory_defaults',686,610,258,'REAPER設定を使用',A.use_default_directory,function()
 A.use_default_directory=not A.use_default_directory;UI.refresh()
end,'保存フォルダーのみREAPER本体の設定を使用',true,11)
 if A.use_default_directory then button('dir_default',624,637,320,31,dir,function() end,dir,false)
 else
  UI.field('directory',624,637,250,true,A,true)
  button('dir_browse',882,637,62,31,'参照',UI.choose_directory,'保存フォルダーを選択',true,nil,true,11)
 end
 label('ファイル名',624,674,11,C.faint,1,58,26,4)
 checkbox('filename_defaults',686,674,258,'REAPER設定を使用',A.use_default_filename,function()
 A.use_default_filename=not A.use_default_filename;UI.refresh()
end,'ファイル名のみREAPER本体の設定を使用。ワイルドカードもREAPERで解決',true,11)
 if A.use_default_filename then button('name_default',624,701,320,31,name,function() end,name,false)
 else UI.field('filename',624,701,320,true,A,true) end

 line(36,758,944,758,C.edge,.28)
 label('埋め込むマーカー/リージョンを設定',36,766,13,C.text,1,355,22,4,true)
 slide_toggle('embed_markers',36,794,110,'マーカー',A.embed_markers,function()
  A.embed_markers=not A.embed_markers;UI.refresh()
 end,'レンダー範囲内のマーカーをWAVへ埋め込み',not A.busy)
 slide_toggle('embed_regions',150,794,122,'リージョン',A.embed_regions,function()
  A.embed_regions=not A.embed_regions;UI.refresh()
 end,'レンダー範囲内の通常リージョンをWAVへ埋め込み',not A.busy)
 slide_toggle('embed_loop_region',276,794,176,'ループリージョン',A.embed_loop_region,function()
  A.embed_loop_region=not A.embed_loop_region;UI.refresh()
 end,'レンダー範囲内のサステインをWAVのループ情報として埋め込み',not A.busy)
 slide_toggle('exclude_selected_region',456,794,246,'選択中のリージョンを除外',A.exclude_selected_region,function()
  A.exclude_selected_region=not A.exclude_selected_region;UI.refresh()
 end,'書き出し範囲として選択しているリージョンは埋め込まないようにします。\nただし、ループリージョン自体を選択して書き出した場合に、ループリージョンは除外しません。',not A.busy)
 label('マーカー文字コード設定',706,793,11.5,C.faint,1,132,26,2|4)
 dropdown('encoding',842,793,102,26,A.encoding,function()
  UI.menu({'UTF-8','CP932'},A.encoding,nil,function(v) A.encoding=v end)
 end,ENCODING_HINT,true,11.5)

 local entry_count,outside_count,clipped_count,omitted_count=0,0,0,0
 for _,p in ipairs(A.plans or {}) do
  entry_count=entry_count+#p.entries;outside_count=outside_count+p.outside;clipped_count=clipped_count+p.clipped;omitted_count=omitted_count+(p.omitted or 0)
 end
 local message=A.problem and BLT.publicError(A.problem) or (A.plan and ('出力 '..#A.plans..'件 / 埋め込み '..entry_count..'件 / 除外 '..omitted_count..'件 / 範囲外 '..outside_count..'件 / 切詰め '..clipped_count..'件') or '')
 drawExecute(now)
 local completed=not A.busy and A.render_complete_until and now<A.render_complete_until
 U.scale,U.ox,U.oy=scale,ox,oy+22*scale
 local footer=(A.warning or A.render_batch or completed) and A.status or (message~='' and message or A.status)
 if Media.waiting then footer=Media.message(SECTION) elseif BLT.notice then footer=BLT.notice end
 shell:footer(footer,A.warning or (not A.render_batch and A.problem),W,H,'0.6.13')
 U.scale,U.ox,U.oy=density*scale,ox,oy
 U.editor:frame()
 UI.draw_name_dialog();UI.draw_popup();UI.draw_period_notice(now)
 U:finish();shell:drawBar();tooltip(now)
end

Host:bindShortcuts()
g.getchar=function(query)
 if query==65536 or query==65537 then return Host.focused and 6 or 4 end
 local key=Host.key or 0
 if key>=97 and key<=122 then
  local primary=(g.mouse_cap&4)~=0 or Host.mac and (g.mouse_cap&32)~=0 and (key==97 or key==99 or key==118 or key==122)
  if primary then key=key-96 elseif (g.mouse_cap&8)~=0 then key=key-32 end
 end
 return key,0
end
BLTShortcuts.install(R,gfx,{
 blocked=function() return U.editor.edit~=nil or shell.popupOpen or A.name_dialog~=nil or A.popup~=nil or A.busy or A.closing end,
 localKey=function(key,cap) return key==27 or Core.undo_shortcut(key,cap) end,
 beforeGlobal=UI.commit_edit})
local finalized=false
function UI.close()
 if finalized then return end;finalized=true
 BLT.cleanup(UI.commit_edit)
 if A.audition then BLT.cleanup(UI.stop_loop_audition,true) end
 if A.render_snapshot then BLT.cleanup(Core.restore_render,A.render_snapshot);A.render_snapshot=nil end
 BLT.cleanup(Core.copy_abort,A.job);A.job=nil
 if A.xjob then BLT.cleanup(Core.crossfade_abort,A.xjob);A.xjob=nil end
 if A.ajob then BLT.cleanup(Core.loop_audio_close,A.ajob);A.ajob=nil end
 if A.pjob then BLT.cleanup(Core.loop_audio_close,A.pjob);A.pjob=nil end
 BLT.cleanup(Core.retry_file_deletes,true);BLT.cleanup(UI.cleanup_raw);BLT.cleanup(UI.save_settings)
 BLT.cleanup(BLTRestore.finish,R,A.manualClose or Host.requestClose)
 BLT.cleanup(wave.close,wave);BLT.cleanup(Host.close,Host);BLT.cleanup(shell.close,shell)
 A.render_batch=nil;A.seam_drag=nil;A.seam_hold=nil;A.closed=true
end
R.atexit(UI.close)
if R.set_action_options then R.set_action_options(2) end
local restored,restoreError=pcall(BLTRestore.start,R)
if not restored then Language.mb('自動復元の登録に失敗しました。\n'..tostring(restoreError),APP_NAME,0) end
local function poll(now)
 Media.tick()
 if R.EnumProjects(-1,'')~=A.project then cancelEdit() end
 UI.poll(now)
 Core.retry_file_deletes(false)
 if not A.busy and A.raw_delete_at and now>=A.raw_delete_at then UI.cleanup_raw() end
 UI.preview_tick(now)
 if not A.busy then UI.preview_step()
 elseif A.pjob then Core.loop_audio_close(A.pjob);A.pjob=nil;A.preview_signature=nil;A.seam_hold=nil;A.seam_refreshing=false end
 UI.loop_audition_tick(now);UI.period_notice_tick(now)
 local b=A.render_batch
 if b then
  if b.presented and b.presentedPass and pass>b.presentedPass+1 then UI.render_step() end
 elseif A.job then UI.step() end
 if A.xjob then UI.crossfade_step() end
 if A.ajob then UI.adjust_loop_step() end
 if A.render_complete_until and now>=A.render_complete_until then A.render_complete_until=nil;UI.dirty() end
 if BLT.noticeUntil and now>=BLT.noticeUntil then BLT.notice,BLT.noticeUntil=nil,nil;A.content_dirty=true end
end
local inputState,worldState={},{}
local function changed(state,...)
 local different=false
 for i=1,select('#',...) do local value=select(i,...);if state[i]~=value then state[i]=value;different=true end end
 return different
end
function UI.loop()
 if finalized then return end
 pass=pass+1;local begun=false
 local success,err=xpcall(function()
  local now=R.time_precise();UI.safe(poll,now);shell.theme.tick(now)
  if changed(worldState,A.rows,A.selected,A.status,A.warning,A.busy,A.seam,A.seam_refreshing,A.popup,A.name_dialog,
   A.render_batch,A.progress,Language.code,C.bg,Presets.current,BLT.noticeUntil,Host.requestReset,shell.icon.dirty) then A.content_dirty=true end
  local interactive=U.editor.edit or A.popup or A.name_dialog or shell.popupOpen or Host.drag or shell.hoverID or U.capture or
   A.seam_drag or A.period_notice
  local animating=U:executeAnimating('execute') or shell.icon:animating(now)
  if not A.content_dirty and not A.busy and not A.pjob and now>=awakeUntil and not interactive and not animating and Host:idle(now) then
   U.now=now;shell.icon.lastTime=now;R.defer(UI.loop);return
  end
  if Host.idleWake then wake_visuals();Host.idleWake=nil end
  if Host.requestReset then Host.width,Host.height=W,H+26 end
  local shown=Host:begin();begun=true
  if shown then
   local cap=(Host.hovered or Host.focused or U.capture or Host.drag) and gfx.mouse_cap or 0
   if changed(inputState,gfx.mouse_x,gfx.mouse_y,cap,Host.key,gfx.w,gfx.h,Host.dpi,Host.originX,Host.originY,Host.focused) or
    gfx.mouse_wheel~=0 or (cap&1)~=0 or interactive then wake_visuals() end
   A.active=Host.focused;A.content_dirty=false;UI.draw(now)
   if not Host.focused then awakeUntil=min(awakeUntil,now+.5) end
  end
  local keep=Host:finish();begun=false
  local b=A.render_batch
  if shown and b and not b.presented then b.presented=true;b.presentedPass=pass end
  if not keep or A.closing then UI.close() else R.defer(UI.loop) end
 end,debug.traceback)
 if not success then
  if begun then pcall(Host.finish,Host) end
  UI.close();Language.mb(BLT.publicError(err),APP_NAME..' | エラー',0)
 end
end
UI.safe(UI.poll,R.time_precise(),true)
UI.loop()
