-- @description SIMPLE NORMALIZER
-- @version 0.6.4
-- @author Balrulu
-- @provides
--   . > ../
-- @changelog
--   BLT SERIES Beta TEST UPLOAD
-- @about
--   BLT SERIES Beta TEST UPLOAD

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

BLT.SimpleNormalizerIcon=(function()
local M={width=108,height=54,modes={'normalize'}}
local sin,abs,min,max,pi=math.sin,math.abs,math.min,math.max,math.pi
local offsets={0,-12,10,-8}
local function hash(n,salt) return (sin(n*12.9898+salt*78.233)*43758.5453)%1 end
function M.update() end
local function knob(p,x,y,c,a)
 p:rect(x-6,y-3,12,6,p.C.panel2,.92*a)
 p:line(x-6,y-3,x+6,y-3,c,.72*a,1)
 p:line(x-6,y+3,x+6,y+3,c,.40*a,1)
end
function M.draw(p,s,mode,time)
 local C=p.C;local target=27
 p:line(8,target,101,target,C.accent,.08,7)
 p:line(8,target,101,target,C.ice,.28,1)
 for i,offset in ipairs(offsets) do
  local x=22+(i-1)*21;local c=offset>0 and C.warn or C.ice
  p:line(x,8,x,46,C.edge2,i==1 and .56 or .28,1)
  for k=-2,2 do
   local width=1.8+2.4*abs(sin(i*1.31+k*.87))
   p:line(x-width,target+k*4.3,x+width,target+k*4.3,C.muted,i==1 and .30 or .16,1)
  end
  if i==1 then knob(p,x,target,C.ice,1);p:disc(x,target,1.45,C.ice,.88)
  else
   local cycle=(time*.34+(i-2)*.055)%1;local y,a=target+offset,1
   if cycle>=.12 and cycle<.70 then local t=(cycle-.12)/.58;y=y-offset*(1-(1-t)^3)
   elseif cycle>=.70 then y=target;a=max(0,1-(cycle-.70)/.12) end
   p:line(x,target+offset,x,target,c,.12,1)
   if a>.001 then p:disc(x,y,8,C.accent,.018*a);knob(p,x,y,c,a) end
   p:disc(x,target,1.1,C.ice,.62)
  end
 end
end
function M.emit(s,n,p)
 local lane=2+math.floor(hash(n,1)*3);local x=22+(lane-1)*21;local offset=offsets[lane]
 local dir=offset<0 and 1 or -1
 p.sx,p.sy=x+(hash(n,2)-.5)*6.8,27+offset+(hash(n,3)-.5)*3.8
 p.cx,p.cy=x+(hash(n,4)-.5)*2,27+(hash(n,5)-.5)*1.4
 p.ex,p.ey=x+(hash(n,6)-.5)*1.2,27+dir*(5+hash(n,7)*7)
 p.life=(s.working and .90 or 1.12)+hash(n,8)*(s.working and .36 or .42)
 p.rBefore,p.rGrow,p.rShrink=.72+hash(n,9)*.82,1.55+hash(n,10)*1.55,.30+hash(n,11)*.40
 p.bend,p.drift,p.phase=(hash(n,15)-.5)*7,(hash(n,16)-.5)*8.5,hash(n,17)*pi*2
 p.grows,p.r,p.glint=dir<0,p.rBefore,n%8==0
end
function M.sample(s,p,age)
 local t=min(1,age/p.life);local split=p.grows and .50 or .68
 local before=t<split;local u=before and t/split or (t-split)/(1-split)
 local ease=not before and p.grows and u*u*(3-2*u) or 1-(1-u)^2
 local sway=sin(pi*u)*p.bend*(before and .28 or .20)+sin(u*pi*(before and 2 or 1.6)+p.phase)*(before and 1.15 or 1.35)
 p.r=before and p.rBefore or p.grows and p.rGrow or p.rShrink
 if before then return p.sx+(p.cx-p.sx)*ease+sway,p.sy+(p.cy-p.sy)*ease end
 return p.cx+(p.ex+p.drift-p.cx)*ease+sway,p.cy+(p.ey-p.cy)*ease
end
return M
end)()

BLT.SimpleNormalizerWave=(function()
local M={}
local min,max,floor,ceil=math.min,math.max,math.floor,math.ceil
local function pack(c) return 0xff000000|(floor(c[1]*255+.5)<<16)|(floor(c[2]*255+.5)<<8)|floor(c[3]*255+.5) end
function M.new(host,api,C)
 local V={signature={}}
 local bitmap,image,bw,bh
 function V:draw(data,x,y,w,h,scale)
  local dpi=ceil(host.dpi or 1);local factor=scale*dpi
  local iw,ih=max(1,ceil(w*factor)),max(1,ceil(h*factor))
  local changed=not image or self.data~=data or bw~=iw or bh~=ih
  local index=0
  for _,key in ipairs({'field','edge','accent2'}) do for i=1,3 do
   index=index+1;if self.signature[index]~=C[key][i] then self.signature[index]=C[key][i];changed=true end
  end end
  if changed then
   if not bitmap then bitmap=assert(api.JS_LICE_CreateBitmap(true,iw,ih),'Waveform bitmap creation failed')
   elseif bw~=iw or bh~=ih then api.JS_LICE_Resize(bitmap,iw,ih) end
   bw,bh=iw,ih
   api.JS_LICE_Clear(bitmap,pack(C.field))
   api.JS_LICE_Line(bitmap,0,ih/2,iw,ih/2,pack(C.edge),.50,'COPY',true)
   if self.data~=data or not self.peak then
    self.peak=.001;for _,value in ipairs(data) do self.peak=max(self.peak,value or 0) end
   end
   for px=0,iw-1 do
    local first=max(1,floor(px/iw*#data)+1);local last=min(#data,max(first,floor((px+1)/iw*#data)))
    local value=0;for i=first,last do value=max(value,data[i] or 0) end
    local height=value/self.peak*41*factor
    api.JS_LICE_Line(bitmap,px,ih/2-height,px,ih/2+height,pack(C.accent2),.60,'COPY',true)
   end
   if image then host:releaseImage(image) end
   image=host.I.CreateImageFromLICE(bitmap);host:attachImage(image);self.data=data
  end
  host.I.DrawList_AddImage(host.draw,image,host.originX+x,host.originY+y,host.originX+x+w*scale,host.originY+y+h*scale)
 end
 function V:close()
  if image then host:releaseImage(image);image=nil end
  if bitmap then api.JS_LICE_DestroyBitmap(bitmap);bitmap=nil end
 end
 return V
end
return M
end)()

BLT.SimpleNormalizerList=(function()
local M={}
local min,max,floor,ceil=math.min,math.max,math.floor,math.ceil
local columns={8,45,275,347,419,485,559}
local widths={34,226,68,68,62,70,164}
local function fmt(n) return type(n)=='number' and n==n and math.abs(n)<math.huge and string.format('%.1f',n) or '—' end
local function signed(n) return type(n)=='number' and n==n and math.abs(n)<math.huge and string.format('%+.1f',n) or '—' end
function M.new(host,api,text,language,C,Core)
 local V={signature={}};local command={}
 local bitmap,image,bw,bh
 local function font(size,bold,scale) text:setfont(1,host.faces[1],max(7,floor(size*scale+.5)),bold and 98 or 0) end
 local function fit(value,w)
  if text:measurestr(value)<=w then return value end
  local lo,hi=0,utf8.len(value) or 0
  while lo<hi do
   local mid=floor((lo+hi+1)/2);local finish=utf8.offset(value,mid+1) or #value+1
   if text:measurestr(value:sub(1,finish-1)..'…')<=w then lo=mid else hi=mid-1 end
  end
  return value:sub(1,(utf8.offset(value,lo+1) or #value+1)-1)..'…'
 end
 function V:draw(A,S,x,y,scale)
  local dpi=ceil(host.dpi or 1);local factor=scale*dpi
  local sig=self.signature;local changed=false;local n=0
  local function check(value) n=n+1;if sig[n]~=value then sig[n]=value;changed=true end end
  check(scale);check(dpi);check(language.code);check(A.offset);check(S.mode);check(S.targetMode)
  check(S.targetMode==2 and A.selected or 0)
  for slot=1,7 do
   local row=A.items[A.offset+slot]
   check(row);check(row and row.plan);check(row and row.name);check(row and row.ch);check(row and row.reason);check(row and row.rateWarning)
   check(A.job and A.job.index==A.offset+slot or false)
  end
  if not image or changed then
   local w,h=max(1,ceil(738*factor)),max(1,ceil(262*factor))
   if not bitmap then bitmap=assert(api.JS_LICE_CreateBitmap(true,w,h),'List bitmap creation failed')
   elseif bw~=w or bh~=h then api.JS_LICE_Resize(bitmap,w,h) end
   bw,bh=w,h;api.JS_LICE_Clear(bitmap,0xff000000)
   local function label(value,column,yy,bold,header)
    value=tostring(value or ''):gsub('[%z\1-\31\127]',' ')
    if column~=2 or header then value=language.message(value) end
    font(14,bold,scale)
    text:capture(command,fit(value,(widths[column]-4)*scale),columns[column]*scale,yy*scale,0xffffffff,1)
    text:paintMask(command,bitmap)
   end
   local titles={'#','アイテム','現在','チャンネル','補正',S.mode==11 and 'TP後' or 'Peak後','状態'}
   for i,title in ipairs(titles) do label(title,i,4,true,true) end
   for slot=1,7 do
    local index=A.offset+slot;local row=A.items[index]
    if row then
     local p=row.plan or {};local reason=row.reason or p.reason
     local state=reason or row.rateWarning and '1.0倍速換算' or p.reference and '指定基準' or p.changed and 'NORMALIZE' or p.valid and '変更なし' or
      A.job and index==A.job.index and '解析中' or '解析待ち'
     local values={index,row.name,fmt(p.current),Core.channel_label(row.ch),signed(p.gain),fmt(p.peakAfter),state}
     local selected=index==A.selected and S.targetMode==2
     for i,value in ipairs(values) do label(value,i,24+(slot-1)*34+7,i==5 or selected) end
    end
   end
   api.JS_LICE_Blit(bitmap,0,0,bitmap,0,0,w,h,1,'CHANCOPY_RTOA')
   api.JS_LICE_ProcessRect(bitmap,0,0,w,h,'SET_RGB',0xffffff)
   if image then host:releaseImage(image) end
   image=host.I.CreateImageFromLICE(bitmap);host:attachImage(image)
  end
  local I,draw=host.I,host.draw
  local ox,oy=host.windowX or host.originX,host.windowY or host.originY
  x=ox+floor((host.originX-ox+x)*dpi+.5)/dpi
  y=oy+floor((host.originY-oy+y)*dpi+.5)/dpi
  local function part(left,top,right,bottom,c)
   local l,t,r,b=floor(left*factor+.5),floor(top*factor+.5),floor(right*factor+.5),floor(bottom*factor+.5)
   I.DrawList_AddImage(draw,image,x+l/dpi,y+t/dpi,x+r/dpi,y+b/dpi,l/bw,t/bh,r/bw,b/bh,host.rgba(c[1],c[2],c[3],1))
  end
  part(0,0,738,24,C.muted)
  for slot=1,7 do
   local index=A.offset+slot;local row=A.items[index]
   if row then
    local p=row.plan or {};local reason=row.reason or p.reason;local selected=index==A.selected and S.targetMode==2
    local top=24+(slot-1)*34
    for column=1,7 do
     local c=reason or row.rateWarning and column==7
     c=c and C.warn or selected and ((column==2 or column==7) and C.text or C.focus2) or column>=3 and column<=6 and C.accent2 or C.muted
     if column==6 and type(p.peakAfter)=='number' and p.peakAfter>0 then c=C.red end
     part(column==1 and 0 or columns[column],top,column==7 and 738 or columns[column+1],top+34,c)
    end
   end
  end
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
local gfx,Host,U,shell,menu,controls,wave,C
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
 ["ゲート付きIntegrated Loudness。全体平均を基準にします。"]="Gated integrated loudness, based on the overall average.",
 ["音量で無音・小音量区間を除外して平均します。"]="Exclude quiet sections using a level gate; average the remaining sections.",
 ["1秒窓の中央値。突出した一部に引っ張られにくい方式です。"]="Median of 1-second windows. Less affected by isolated loud sections.",
 ["1秒窓の中央60%だけをパワー平均。両端の外れ値を除外します。"]="Power average of the middle 60% of 1-second windows; excludes outliers at both ends.",
 ["1秒窓の80パーセンタイル。やや強い発話を基準にします。"]="80th percentile of 1-second windows; favors stronger speech.",
 ["1秒窓の95パーセンタイル。強い発話を重視します。"]="95th percentile of 1-second windows; emphasizes loud speech.",
 ["最も大きい1秒区間を基準にします。"]="Use the loudest 1-second section.",
 ["最も大きい400ms区間を基準にします。"]="Use the loudest 400 ms section.",
 ["Sample Peakを指定値へ一致させます。"]="Match sample peak to the target.",
 ["音声サンプルが不正です。"]="Invalid audio samples.",
 ["音声を取得できません"]="Cannot read audio",
 ["音声アイテムは5000件まで対応します。"]="Up to 5,000 audio items supported.",
 ["モノ／ステレオのみ対応"]="Mono/stereo only",
 ["一時解析トラックを作成できません。"]="Could not create the analysis track.",
 ["一時解析アイテムを作成できません。"]="Could not create the analysis item.",
 ["一時解析データを解放できません。"]="Could not release temporary analysis data.",
 ["再生速度が不正です"]="Invalid playback rate",
 ["1.0倍速換算"]="At source speed",
 ["速度変更あり：1.0倍速換算の測定値です（実再生値とは異なる場合があります）"]="Rate changed: measured at source speed; playback levels may differ",
 ["1.0倍速換算で30分まで対応"]="Source-speed duration limit: 30 min",
 ["1.0倍速換算の合計は2時間まで対応します。"]="Source-speed duration exceeds 2 hours.",
 ["ミュート／音量0"]="Muted / zero volume",
 ["既存のTake Volumeカーブあり（対象外）"]="Existing take volume curve (skipped)",
 ["長さ0秒超〜30分に対応"]="Length must be >0 s and <=30 min",
 ["有効なTake FXあり（対象外）"]="Active take FX (skipped)",
 ["選択した音声の合計は2時間まで対応します。"]="Selected audio is limited to 2 hours total.",
 ["プロジェクトが切り替わりました。"]="Project switched.",
 ["音声アイテムの選択が変わりました。自動更新します。"]="Audio selection changed. Refreshing automatically.",
 ["対象アイテム自体が変更されています。"]="Target item was modified.",
 ["テイク設定が変更されています。自動更新します。"]="Take settings changed. Refreshing automatically.",
 ["音声アクセサーを作成できません。"]="Cannot create audio accessor.",
 ["取得できる音声範囲がアイテム長と一致しません。"]="Available audio range does not match item length.",
 ["音声解析用バッファを作成できません。"]="Cannot allocate audio analysis buffer.",
 ["ラウドネス解析器を作成できません。"]="Cannot create loudness analyzer.",
 ["解析中にアイテムが変更されました。"]="Item changed during analysis.",
 ["音声サンプルの取得に失敗しました。"]="Failed to read audio samples.",
 ["ピーク解析用バッファを作成できません。"]="Cannot allocate peak buffer.",
 ["Sample Peakを測定できません"]="Cannot measure sample peak",
 ["任意ファイルを基準にするため、そのファイルの解析完了を待っています。"]="Waiting for the reference file to finish analysis.",
 ["この方式で測定できません"]="Cannot measure with this method",
 ["適用する変更がありません。"]="No changes to apply.",
 ["アイテム音量を設定できません。"]="Cannot set item volume.",
 [" 元の音量へ戻せない項目があります。REAPERのUndoで確認してください。"]=" Some volumes could not be restored. Check REAPER Undo.",
 ["音声アイテムを選択すると自動解析します。"]="Select audio items for automatic analysis.",
 ["%s · %d件を処理できます。"]="%s · %d items ready.",
 ["%d件をバックグラウンド解析しています…"]="Analyzing %d items in the background...",
 ["ノーマライズする音声アイテムを選択してください。"]="Select audio items to normalize.",
 ["PEAK Fast Path：通常解析を停止し、未取得分のSample Peakだけを高速取得しています…"]="PEAK Fast Path: paused normal analysis; reading missing sample peaks...",
 ["プロジェクトが切り替わりました。自動更新します。"]="Project switched. Refreshing automatically.",
 ["選択が変わりました。自動更新します。"]="Selection changed. Refreshing automatically.",
 ["対象を固定して、残りを解析後そのままノーマライズします…"]="Targets locked. Finishing analysis, then normalizing...",
 ["件をノーマライズしました。選択を解除しました。"]=" items normalized and deselected.",
 ["PEAK高速実行をキャンセルしました。通常の自動解析へ戻ります。"]="PEAK fast run cancelled. Resuming automatic analysis.",
 ["ノーマライズ実行をキャンセルしました。自動解析は継続します。"]="Normalization cancelled. Automatic analysis continues.",
 ["CHAMELEON  REAPERテーマに擬態"]="CHAMELEON  REAPER theme",
 ["CHAMELEON  オリジナル配色"]="CHAMELEON  Original colors",
 ["カスタムタイトルバーには js_ReaScriptAPI が必要です。\nReaPack から js_ReaScriptAPI をインストールしてください。"]="The app bar requires js_ReaScriptAPI.\nInstall js_ReaScriptAPI via ReaPack.",
 ["数値を入力できなかったため、元の値へ戻しました。"]="Invalid input. Previous value restored.",
 ["クリック入力 ／ ドラッグ・ホイール：1刻み（Shift：0.1）"]="Click: type / Drag or wheel: 1 (Shift: 0.1)",
 ["選択アイテムの波形"]="SELECTED WAVEFORM",
 ["選択アイテムを自動解析しています"]="Analyzing selected items automatically",
 ["アイテム"]="Item",
 ["現在"]="Current",
 ["チャンネル"]="Channels",
 ["補正"]="Gain",
 ["Peak後"]="Peak after",
 ["TP後"]="TP after",
 ["4倍補間でサンプル間のピークを推定します。"]="Estimate inter-sample peaks with 4x interpolation.",
 ["全区間・全チャンネルの二乗平均。無音を含みます。"]="Unweighted RMS across time and channels, including silence.",
 ["個別適用"]="Individual",
 ["全体適用"]="Together",
 ["モノラルの場合追加で-3 dB補正"]="Mono: extra -3 dB",
 ["各アイテムを個別に目標値へ合わせます。"]="Normalize each item to its target.",
 ["選択内の最大測定値を目標に合わせ、全対象に共通ゲインを適用します。"]="Match the highest measured item to the target using common gain.",
 ["ノーマライズ後、モノラル素材だけ追加で-3 dBします。全体適用でも追加補正します。"]="Apply an extra -3 dB to mono sources after normalization, including Together mode.",
 ["TRUE PEAK予測"]="TRUE PEAK AFTER",
 ["無音のため測定できません"]="Cannot measure silence",

 ["状態"]="Status",
 ["指定基準"]="Reference",
 ["変更なし"]="Unchanged",
 ["解析中"]="Analyzing",
 ["解析待ち"]="Pending",
 ["任意ファイルモードでは、この行をReferenceとして使用します。"]="In reference-file mode, use this row as the reference.",
 ["表示 %d–%d / %d"]="Showing %d–%d / %d",
 ["SIMPLE NORMALIZER  シンプルなノーマライザー"]="SIMPLE NORMALIZER  Audio normalization",
 ["任意ファイル"]="Reference file",
 ["リストから指定"]="Select from list",
 ["数値指定"]="Numeric",
 ["指定した値へ揃えます。"]="Match the specified value.",
 ["右側のリストで選んだファイルを基準にします。"]="Use the file selected in the right-hand list as reference.",
 ["目標値"]="Target",
 ["右のリストでReferenceにするファイルを選択します。"]="Select the reference file in the right-hand list.",
 ["選択した方式の目標値です。"]="Target value for the selected method.",
 ["PEAK予測"]="PEAK FORECAST",
 ["対象  %d件"]="Targets %d",
 ["Peak取得  %d / %d"]="Peaks %d / %d",
 ["解析済み  %d / %d"]="Analyzed %d / %d",
 ["解析準備完了"]="Ready to analyze",
 ["実行をキャンセル"]="Cancel run",
 ["ノーマライズを実行"]="Normalize",
 ["クリックすると、予約中のノーマライズ実行をキャンセルします。自動解析は継続します。"]="Cancel the queued normalization. Automatic analysis continues.",
 ["解析途中でも実行できます。押した時点の対象を固定し、未解析分を完了してからItem Volumeへ適用します。"]="Run during analysis if needed. Lock current targets, finish remaining analysis, then apply item volume.",
 ["対象固定中 · 再クリックでキャンセル"]="Targets locked · Click again to cancel",
 ["バックグラウンド解析中"]="Background analysis",
 ["実行後は選択を解除"]="Deselect after run",
 ["Reference：リスト選択"]="Reference: list selection",
 ["目標値：数値指定"]="Target: numeric value",
 ["入力を取り消しました。"]="Input cancelled.",
 ["Simple Normalizer | エラー"]="Simple Normalizer | Error",
 ["カスタムタイトルバーを初期化できません。"]="Cannot initialize the app bar.",
 ["表示言語を切替（JP / EN）"]="Switch language (JP / EN)",
 ["プリセットを読み込みました: ファクトリーデフォルト"]="Loaded: Factory Default",
 ["選択中のトラック / バスを指定"]="Use selected track / bus",
},patterns={
 {"^「(.*)」を上書きしますか？$","Overwrite \"%s\"?"},
 {"^([%+%-]?[%d%.eE]+)–([%+%-]?[%d%.eE]+) / ([%+%-]?[%d%.eE]+)   スクロールで選択$","%d–%d / %d   Scroll to browse"},
 {"^解析中%.%.%.([%+%-]?[%d%.eE]+)%%$","Analyzing...%d%%"},
 {"^(.-) · ([%+%-]?[%d%.eE]+)件を処理できます。$","%s · %d items ready."},
 {"^([%+%-]?[%d%.eE]+)件をバックグラウンド解析しています…$","Analyzing %d items in the background..."},
 {"^表示 ([%+%-]?[%d%.eE]+)–([%+%-]?[%d%.eE]+) / ([%+%-]?[%d%.eE]+)$","Showing %d–%d / %d"},
 {"^対象  ([%+%-]?[%d%.eE]+)件$","Targets %d"},
 {"^Peak取得  ([%+%-]?[%d%.eE]+) / ([%+%-]?[%d%.eE]+)$","Peaks %d / %d"},
 {"^解析済み  ([%+%-]?[%d%.eE]+) / ([%+%-]?[%d%.eE]+)$","Analyzed %d / %d"},
 {"^「(.-)」を上書きしますか？$","\"%s\"?"},
 {"^(.-)」を上書きしますか？$","%s\"?"},
 {"^プリセットを保存しました: (.-)$","Saved: %s"},
 {"^プリセットを読み込みました: (.-)$","Loaded: %s"},
 {"^(.-)個インポートしました。$","%s preset(s) imported."},
 {"^現在: (.-)(.-)$","Current: %s%s"},
 {"^(.-) 元の音量へ戻せない項目があります。REAPERのUndoで確認してください。$","%s Some volumes could not be restored. Check REAPER Undo."},
 {"^(.-)件をノーマライズしました。選択を解除しました。$","%s items normalized and deselected."},
 {"^「(.*)」を上書きしますか？$","Overwrite \"%s\"?"},
 {"^(%d+)個インポートしました。$","Imported %s preset(s)."},
 {"^(%d+)件をノーマライズしました。選択を解除しました。$","Normalized %s items and deselected them."},
},prefixes={"プリセットを読み込みました: ","プリセットを保存しました: ","現在: "}}

LanguageCatalog.en["400msの最大LUFS-M。400ms未満は測定対象外です。"]="Maximum LUFS-M (400 ms). Shorter items are excluded."
LanguageCatalog.en["3秒の最大LUFS-S。3秒未満は測定対象外です。"]="Maximum LUFS-S (3 s). Shorter items are excluded."
LanguageCatalog.en["基準ファイルは選択方式で測定できません。尺と方式を確認してください。"]="Reference cannot use this method. Check its length or choose another method."
LanguageCatalog.en["LUFS-Mには0.4秒以上必要です"]="LUFS-M needs at least 0.4 s"
LanguageCatalog.en["LUFS-Sには3秒以上必要です"]="LUFS-S needs at least 3 s"

local Language=create_language(reaper,"BLT_SIMPLE_NORMALIZER",LanguageCatalog)
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
local min,max,abs,floor,sqrt=math.min,math.max,math.abs,math.floor,math.sqrt
local function clamp(x,a,b) return max(a,min(b,x)) end
local function finite(x) return type(x)=="number" and x==x and abs(x)<math.huge end
local function dbp(x) return 10*math.log(max(x,1e-15),10) end
local function dba(x) return 20*math.log(max(abs(x),1e-15),10) end
local function amp(db) return 10^(db/20) end
local function quantile(values,q)
  if #values==0 then return nil end
  local a={}; for i,v in ipairs(values) do a[i]=v end; table.sort(a)
  return a[clamp(floor((#a-1)*q+1.5),1,#a)]
end
local function mean_power(blocks,gate)
  local sum,n=0,0
  for _,b in ipairs(blocks) do
    if not gate or b.level>=gate then sum=sum+b.power; n=n+1 end
  end
  return n>0 and sum/n or nil,n
end

local Core={SR=48000,HOP=960,DT=.02,READ_BLOCK=16384,PEAK_READ_BLOCK=131072,MAX_ITEMS=5000,MAX_SECONDS=7200,MAX_GAIN=60,WAVEFORM_BINS=1024}
Core.modes={
  {key="integrated",name="LUFS-I",code="I",unit="LUFS",default=-24,desc="ゲート付きIntegrated Loudness。全体平均を基準にします。"},
  {key="speech",name="SPEECH",code="VOICE",unit="LUFS",default=-24,desc="音量で無音・小音量区間を除外して平均します。"},
  {key="median",name="MEDIAN",code="P50",unit="LUFS",default=-24,desc="1秒窓の中央値。突出した一部に引っ張られにくい方式です。"},
  {key="robust",name="ROBUST",code="TRIM",unit="LUFS",default=-24,desc="1秒窓の中央60%だけをパワー平均。両端の外れ値を除外します。"},
  {key="p80",name="P80",code="P80",unit="LUFS",default=-20,desc="1秒窓の80パーセンタイル。やや強い発話を基準にします。"},
  {key="p95",name="P95",code="P95",unit="LUFS",default=-18,desc="1秒窓の95パーセンタイル。強い発話を重視します。"},
  {key="max1s",name="MAX 1s",code="MAX-ST",unit="LUFS",default=-18,desc="最も大きい1秒区間を基準にします。"},
  {key="max400",name="LUFS-M",code="M MAX",unit="LUFS",default=-16,desc="400msの最大LUFS-M。400ms未満は測定対象外です。"},
  {key="peak",name="PEAK",code="SP",unit="dBFS",default=-1,desc="Sample Peakを指定値へ一致させます。"},
  {key="shortterm",name="LUFS-S",code="S MAX",unit="LUFS",default=-18,desc="3秒の最大LUFS-S。3秒未満は測定対象外です。"},
  {key="truepeak",name="TRUE PEAK",code="TP 4x",unit="dBTP",default=-1,desc="4倍補間でサンプル間のピークを推定します。"},
  {key="rms",name="RMS",code="RMS-I",unit="dBFS",default=-20,desc="全区間・全チャンネルの二乗平均。無音を含みます。"},
}
Core.mode_order={9,11,12,1,8,10,2,3,4,5,6,7}

local function biquad(b0,b1,b2,a1,a2) return {b0,b1,b2,a1,a2,0,0} end
local function run(f,x)
  local y=f[1]*x+f[6]
  f[6]=f[2]*x-f[4]*y+f[7]
  f[7]=f[3]*x-f[5]*y
  return y
end

function Core.analyzer(ch,gain)
  local a={ch=ch,gain=gain or 1,frames={},n=0,k=0,peak=0,f={}}
  for c=1,ch do
    a.f[c]={
      shelf=biquad(1.53512485958697,-2.69169618940638,1.19839281085285,-1.69065929318241,.73248077421585),
      rlb=biquad(1,-2,1,-1.99004745483398,.99007225036621)
    }
  end
  return a
end
local function emit(a)
  if a.n<=0 then return end
  a.frames[#a.frames+1]={k=a.k/a.n,peak=a.peak,dt=a.n/Core.SR}
  a.n,a.k,a.peak=0,0,0
end
function Core.feed(a,samples,n)
  local p=1
  for _=1,n do
    for c=1,a.ch do
      local x=samples[p]; p=p+1
      if x~=x or abs(x)>=math.huge then error("音声サンプルが不正です。",0) end
      x=x*a.gain
      local f=a.f[c]
      local y=run(f.shelf,x)
      local k=run(f.rlb,y)
      a.k=a.k+k*k
      local pk=abs(x); if pk>a.peak then a.peak=pk end
    end
    a.n=a.n+1
    if a.n==Core.HOP then emit(a) end
  end
end
function Core.finish(a) emit(a); return a.frames end

local function rolling_blocks(frames,windowSec,hopSec)
  local n=#frames; if n==0 then return {} end
  local win=max(1,floor(windowSec/Core.DT+.5))
  local hop=max(1,floor(hopSec/Core.DT+.5))
  local pe,pd={0},{0}
  for i,f in ipairs(frames) do
    pe[i+1]=pe[i]+(f.k or 0)*(f.dt or Core.DT)
    pd[i+1]=pd[i]+(f.dt or Core.DT)
  end
  local out={}
  if n<win then
    local e=pe[n+1]-pe[1]; local d=pd[n+1]-pd[1]
    if d>0 and e>0 then local p=e/d; out[1]={power=p,level=-.691+dbp(p)} end
    return out
  end
  local i=1
  while i+win-1<=n do
    local j=i+win-1
    local e=pe[j+1]-pe[i]; local d=pd[j+1]-pd[i]
    if d>0 and e>0 then local p=e/d; out[#out+1]={power=p,level=-.691+dbp(p)} end
    i=i+hop
  end
  return out
end

function Core.integrated(frames)
  local blocks=rolling_blocks(frames,.400,.100)
  if #blocks==0 then return nil end
  local absBlocks={}
  for _,b in ipairs(blocks) do if b.level>=-70 then absBlocks[#absBlocks+1]=b end end
  if #absBlocks==0 then return nil end
  local p=mean_power(absBlocks)
  if not p then return nil end
  local prelim=-.691+dbp(p)
  local gate=max(-70,prelim-10)
  local fp=mean_power(blocks,gate)
  return fp and (-.691+dbp(fp)) or prelim
end

function Core.speech(frames)
  local blocks=rolling_blocks(frames,.200,.100)
  if #blocks==0 then return nil,nil end
  local levels={}; for _,b in ipairs(blocks) do levels[#levels+1]=b.level end
  local p90=quantile(levels,.90); if not p90 then return nil,nil end
  local gate=max(-55,p90-25)
  local p,n=mean_power(blocks,gate)
  if not p or n==0 then return nil,nil end
  return -.691+dbp(p),n/#blocks
end

local function robust_level(values)
  if not values or #values==0 then return nil end
  local a={}; for i,v in ipairs(values) do a[i]=v end; table.sort(a)
  local lo=clamp(floor((#a-1)*.20+1.5),1,#a)
  local hi=clamp(floor((#a-1)*.80+1.5),lo,#a)
  local sum,n=0,0
  for i=lo,hi do
    sum=sum+10^((a[i]+.691)/10); n=n+1
  end
  return n>0 and (-.691+dbp(sum/n)) or nil
end

function Core.short_stats(frames)
  local blocks=rolling_blocks(frames,1.000,.100)
  if #blocks==0 then return nil,nil,nil,nil,nil,nil end
  local levels={}; for _,b in ipairs(blocks) do levels[#levels+1]=b.level end
  local p90=quantile(levels,.90); if not p90 then return nil,nil,nil,nil,nil,nil end
  local gate=max(-60,p90-30)
  local active={}
  for _,b in ipairs(blocks) do if b.level>=gate then active[#active+1]=b.level end end
  if #active==0 then active=levels end
  local max1=-150; for _,v in ipairs(active) do if v>max1 then max1=v end end
  return quantile(active,.50),quantile(active,.80),quantile(active,.95),max1,robust_level(active),active
end

function Core.max_window(frames,seconds)
 local win=math.floor(seconds/Core.DT+.5);local hop=math.floor(.1/Core.DT+.5)
 if #frames<win then return nil end
 local energy,duration=0,0;local best=nil
 for i,f in ipairs(frames) do
  local dt=f.dt or Core.DT;energy=energy+(f.k or 0)*dt;duration=duration+dt
  if i>win then local old=frames[i-win];local d=old.dt or Core.DT;energy=energy-(old.k or 0)*d;duration=duration-d end
  if i>=win and (i-win)%hop==0 and duration>=seconds-1e-7 and energy>0 then
   local level=-.691+dbp(energy/duration);best=best and max(best,level) or level
  end
 end
 return best
end
function Core.max_momentary(frames) return Core.max_window(frames,.4) end

function Core.measure(frames)
  if not frames or #frames==0 then return {valid=false,reason="音声を取得できません"} end
  local peak=0; local energy,dt=0,0
  for _,f in ipairs(frames) do
    peak=max(peak,f.peak or 0)
    energy=energy+(f.k or 0)*(f.dt or Core.DT)
    dt=dt+(f.dt or Core.DT)
  end
  local integrated=Core.integrated(frames)
  local speech,activeRatio=Core.speech(frames)
  local median,p80,p95,max1s,robust=Core.short_stats(frames)
  local max400=Core.max_momentary(frames);local shortterm=Core.max_window(frames,3)
  local whole=(dt>0 and energy>0) and (-.691+dbp(energy/dt)) or nil
  return {
    valid=integrated~=nil or speech~=nil or median~=nil or peak>0,
    integrated=integrated,speech=speech,median=median,robust=robust,p80=p80,p95=p95,max1s=max1s,max400=max400,shortterm=shortterm,duration=dt,
    peak=dba(peak),whole=whole,activeRatio=activeRatio,sampleRate=Core.SR
  }
end

function Core.waveform_preview(frames,bins)
  local out={};local n=#(frames or {});bins=min(max(1,bins or Core.WAVEFORM_BINS),max(1,n))
  if n==0 then return out end
  for bin=1,bins do
    local first=max(1,floor((bin-1)*n/bins)+1)
    local last=min(n,max(first,floor(bin*n/bins)))
    local peak=0
    for i=first,last do peak=max(peak,frames[i].peak or 0) end
    out[bin]=peak
  end
  return out
end

function Core.metric(m,mode)
  if not m or not m.valid then return nil end
  local key=Core.modes[mode].key
  return m[key]
end

function Core.neutral(take)
  local env=R.GetTakeEnvelopeByName(take,"Volume")
  if not env then return true end
  if R.CountAutomationItems(env)>0 then return false end
  local mode=R.GetEnvelopeScalingMode(env)
  for i=0,R.CountEnvelopePoints(env)-1 do
    local ok,_,value=R.GetEnvelopePoint(env,i)
    if ok and abs(R.ScaleFromEnvelopeMode(mode,value)-1)>1e-6 then return false end
  end
  return true
end

local function audio_take(item)
  if not item then return nil end
  local take=R.GetActiveTake(item)
  if not take or R.TakeIsMIDI(take) then return nil end
  local source=R.GetMediaItemTake_Source(take)
  if not source then return nil end
  local sourceType=R.GetMediaSourceType(source)
  sourceType=type(sourceType)=="string" and sourceType:upper() or ""
  if sourceType=="EMPTY" or sourceType=="MIDI" or sourceType=="MIDIPOOL" then return nil end
  local sourceRate=R.GetMediaSourceSampleRate(source)
  if not finite(sourceRate) or sourceRate<=0 then return nil end
  local channels=R.GetMediaSourceNumChannels(source)
  if not finite(channels) or channels<1 then return nil end
  return take,source,channels
end
local function take_fx_state(take)
  local n=R.TakeFX_GetCount(take);local enabled={}
  for fx=0,n-1 do enabled[#enabled+1]=R.TakeFX_GetEnabled(take,fx) and "1" or "0" end
  return n,table.concat(enabled)
end
local function stable_num(x)
  return finite(x) and string.format("%.9f",x) or "nan"
end
local function pitch_envelope_state(take)
  local env=R.GetTakeEnvelopeByName(take,"Pitch")
  if not env then return "PITCH_ENV:none" end
  local ok,chunk=R.GetEnvelopeStateChunk(env,"",false)
  if ok and type(chunk)=="string" then return "PITCH_ENV:"..chunk end
  return "PITCH_ENV:unreadable:"..tostring(R.CountEnvelopePoints(env))..":"..tostring(R.CountAutomationItems(env))
end
local function take_transform_state(take)
  local parts={
    "PITCH="..stable_num(R.GetMediaItemTakeInfo_Value(take,"D_PITCH")),
    "PPITCH="..stable_num(R.GetMediaItemTakeInfo_Value(take,"B_PPITCH")),
    "PITCHMODE="..stable_num(R.GetMediaItemTakeInfo_Value(take,"I_PITCHMODE")),
    "PAN="..stable_num(R.GetMediaItemTakeInfo_Value(take,"D_PAN")),
    "PANLAW="..stable_num(R.GetMediaItemTakeInfo_Value(take,"D_PANLAW")),
    "STRETCHFLAGS="..stable_num(R.GetMediaItemTakeInfo_Value(take,"I_STRETCHFLAGS")),
    "STRETCHFADESIZE="..stable_num(R.GetMediaItemTakeInfo_Value(take,"F_STRETCHFADESIZE")),
  }
  local n=R.GetTakeNumStretchMarkers(take)
  parts[#parts+1]="STRETCH_COUNT="..tostring(n)
  for i=0,n-1 do
    local marker,pos,srcpos=R.GetTakeStretchMarker(take,i)
    parts[#parts+1]=table.concat({
      "SM",tostring(marker),stable_num(pos),stable_num(srcpos),stable_num(R.GetTakeStretchMarkerSlope(take,i))
    },":")
  end
  parts[#parts+1]=pitch_envelope_state(take)
  return table.concat(parts,"\30")
end

function Core.audio_selection_count(project)
  if not project then return 0 end
  local count=0
  for i=0,R.CountSelectedMediaItems(project)-1 do
    if audio_take(R.GetSelectedMediaItem(project,i)) then count=count+1 end
  end
  return count
end

function Core.collect(project)
  local n=R.CountSelectedMediaItems(project)
  local result,seconds,sourceSeconds={},0,0
  for i=0,n-1 do
    local item=R.GetSelectedMediaItem(project,i)
    local take,source,channels=audio_take(item)
    if take then
      if #result>=Core.MAX_ITEMS then error("音声アイテムは5000件まで対応します。",0) end
      local track=R.GetMediaItemTrack(item)
      local v={item=item,take=take,track=track,project=project,loop=R.GetMediaItemInfo_Value(item,"B_LOOPSRC"),
        tracknum=R.GetMediaTrackInfo_Value(track,"IP_TRACKNUMBER"),
        pos=R.GetMediaItemInfo_Value(item,"D_POSITION"),len=R.GetMediaItemInfo_Value(item,"D_LENGTH"),
        volume=R.GetMediaItemInfo_Value(item,"D_VOL"),mute=R.GetMediaItemInfo_Value(item,"B_MUTE"),index=R.GetMediaItemInfo_Value(item,"IP_ITEMNUMBER"),
        ch=channels,source=source,sourceType=R.GetMediaSourceType(source),sourceRate=R.GetMediaSourceSampleRate(source),
        sourceChannels=R.GetMediaSourceNumChannels(source),startoffs=R.GetMediaItemTakeInfo_Value(take,"D_STARTOFFS"),
        chanmode=R.GetMediaItemTakeInfo_Value(take,"I_CHANMODE")}
      v.name=R.GetTakeName(take) or "Audio item"
      v.takevol=R.GetMediaItemTakeInfo_Value(take,"D_VOL")
      v.rate=R.GetMediaItemTakeInfo_Value(take,"D_PLAYRATE")
      v.rateWarning=finite(v.rate) and abs(v.rate-1)>1e-9
      v.measureLen=v.len*(v.rateWarning and v.rate or 1)
      v.fxCount,v.fxEnabled=take_fx_state(take)
      v.transformState=take_transform_state(take)
      if v.ch~=1 and v.ch~=2 then v.reason="モノ／ステレオのみ対応"
      elseif not finite(v.rate) or v.rate<=0 then v.reason="再生速度が不正です"
      elseif R.GetMediaItemInfo_Value(item,"B_MUTE")~=0 or v.volume<=0 or abs(v.takevol)<1e-12 then v.reason="ミュート／音量0"
      elseif not Core.neutral(take) then v.reason="既存のTake Volumeカーブあり（対象外）"
      elseif not finite(v.len) or v.len<=0 or v.len>1800 then v.reason="長さ0秒超〜30分に対応"
      elseif not finite(v.measureLen) or v.measureLen>1800 then v.reason="1.0倍速換算で30分まで対応"
      else
        for fx=0,R.TakeFX_GetCount(take)-1 do
          if R.TakeFX_GetEnabled(take,fx) then v.reason="有効なTake FXあり（対象外）"; break end
        end
      end
      if not v.reason then seconds=seconds+v.len;sourceSeconds=sourceSeconds+v.measureLen end
      result[#result+1]=v
    end
  end
  if sourceSeconds>Core.MAX_SECONDS then error("1.0倍速換算の合計は2時間まで対応します。",0) end
  if seconds>Core.MAX_SECONDS then error("選択した音声の合計は2時間まで対応します。",0) end
  table.sort(result,function(a,b)
    if a.tracknum~=b.tracknum then return a.tracknum<b.tracknum end
    if a.pos~=b.pos then return a.pos<b.pos end
    return a.index<b.index
  end)
  return result,seconds
end

function Core.selection_signature(project)
  if not project then return "no_project" end
  local rows={}
  for i=0,R.CountSelectedMediaItems(project)-1 do
    local item=R.GetSelectedMediaItem(project,i)
    local take=audio_take(item)
    if take then
      local _,iguid=R.GetSetMediaItemInfo_String(item,"GUID","",false)
      local parts={
        iguid or tostring(item),
        stable_num(R.GetMediaItemInfo_Value(item,"D_POSITION")),
        stable_num(R.GetMediaItemInfo_Value(item,"D_LENGTH")),
        stable_num(R.GetMediaItemInfo_Value(item,"D_VOL")),
        stable_num(R.GetMediaItemInfo_Value(item,"B_MUTE")),
        stable_num(R.GetMediaItemInfo_Value(item,"B_LOOPSRC")),
      }
      local _,tguid=R.GetSetMediaItemTakeInfo_String(take,"GUID","",false)
      parts[#parts+1]=tguid or tostring(take)
      parts[#parts+1]=stable_num(R.GetMediaItemTakeInfo_Value(take,"D_VOL"))
      parts[#parts+1]=stable_num(R.GetMediaItemTakeInfo_Value(take,"D_PLAYRATE"))
      parts[#parts+1]=stable_num(R.GetMediaItemTakeInfo_Value(take,"D_STARTOFFS"))
      local source=R.GetMediaItemTake_Source(take)
      parts[#parts+1]=tostring(source)
      parts[#parts+1]=tostring(R.GetMediaSourceType(source) or "")
      parts[#parts+1]=stable_num(R.GetMediaSourceSampleRate(source))
      parts[#parts+1]=stable_num(R.GetMediaSourceNumChannels(source))
      parts[#parts+1]=stable_num(R.GetMediaItemTakeInfo_Value(take,"I_CHANMODE"))
      parts[#parts+1]=take_transform_state(take)
      local fxn=R.TakeFX_GetCount(take)
      parts[#parts+1]=tostring(fxn)
      for fx=0,fxn-1 do parts[#parts+1]=R.TakeFX_GetEnabled(take,fx) and "1" or "0" end
      local env=R.GetTakeEnvelopeByName(take,"Volume")
      if env then
        parts[#parts+1]="E"..tostring(R.CountEnvelopePoints(env))..":"..tostring(R.CountAutomationItems(env))
      else
        parts[#parts+1]="E0:0"
      end
      rows[#rows+1]=table.concat(parts,",")
    end
  end
  table.sort(rows)
  if #rows==0 then return "0" end
  return tostring(#rows).."|"..table.concat(rows,"|")
end
function Core.selection_watch_key(project)
  if not project then return "no_project" end
  local n=R.CountSelectedMediaItems(project);local parts={tostring(n)}
  for i=0,n-1 do
    local item=R.GetSelectedMediaItem(project,i)
    parts[#parts+1]=tostring(item)
    parts[#parts+1]=tostring(item and R.GetActiveTake(item) or nil)
  end
  return table.concat(parts,"|")
end

function Core.check(project,items,allowSelectionChange)
  if R.EnumProjects(-1,"")~=project then return nil,"プロジェクトが切り替わりました。" end
  if not allowSelectionChange and Core.audio_selection_count(project)~=#items then return nil,"音声アイテムの選択が変わりました。自動更新します。" end
  for _,v in ipairs(items) do
    if not R.ValidatePtr2(project,v.item,"MediaItem*")
      or (not allowSelectionChange and not R.IsMediaItemSelected(v.item)) then return nil,"音声アイテムの選択が変わりました。自動更新します。" end
    if not v.reason and (R.GetActiveTake(v.item)~=v.take or R.GetMediaItemTrack(v.item)~=v.track
      or R.GetMediaItemInfo_Value(v.item,"D_POSITION")~=v.pos or R.GetMediaItemInfo_Value(v.item,"D_LENGTH")~=v.len
      or R.GetMediaItemInfo_Value(v.item,"B_LOOPSRC")~=v.loop
      or R.GetMediaItemInfo_Value(v.item,"D_VOL")~=v.volume or R.GetMediaItemInfo_Value(v.item,"B_MUTE")~=v.mute) then return nil,"対象アイテム自体が変更されています。" end
    if v.take and not v.reason then
      local source=R.GetMediaItemTake_Source(v.take);local fxCount,fxEnabled=take_fx_state(v.take)
      if R.GetMediaItemTakeInfo_Value(v.take,"D_VOL")~=v.takevol or R.GetMediaItemTakeInfo_Value(v.take,"D_PLAYRATE")~=v.rate
        or R.GetMediaItemTakeInfo_Value(v.take,"D_STARTOFFS")~=v.startoffs or R.GetMediaItemTakeInfo_Value(v.take,"I_CHANMODE")~=v.chanmode
        or source~=v.source or not source or R.GetMediaSourceType(source)~=v.sourceType
        or R.GetMediaSourceSampleRate(source)~=v.sourceRate or R.GetMediaSourceNumChannels(source)~=v.sourceChannels
        or fxCount~=v.fxCount or fxEnabled~=v.fxEnabled
        or take_transform_state(v.take)~=v.transformState
        or not Core.neutral(v.take) then return nil,"テイク設定が変更されています。自動更新します。" end
    end
  end
  return true
end
function Core.source_samples(reader,n)
  local v=reader.v;local sr=reader.sr or Core.SR
  if not reader.cache or reader.n<reader.cacheAt or reader.n+n>reader.cacheAt+reader.cacheFrames then
    if R.EnumProjects(-1,"")~=v.project or not R.ValidatePtr2(v.project,v.take,"MediaItem_Take*")
      or not R.ValidatePtr2(v.project,v.item,"MediaItem*")
      or R.GetMediaItemTake_Source(v.take)~=v.source then
      error("解析中にアイテムが変更されました。",0)
    end
    local track,aa
    local count=min(Core.PEAK_READ_BLOCK,reader.total-reader.n)
    R.PreventUIRefresh(1)
    local ok,result=pcall(function()
      R.InsertTrackAtIndex(0,false)
      track=R.GetTrack(v.project,0)
      if not track then error("一時解析トラックを作成できません。",0) end
      R.SetMediaTrackInfo_Value(track,"B_MAINSEND",0)
      R.SetMediaTrackInfo_Value(track,"B_MUTE",1)
      R.SetMediaTrackInfo_Value(track,"B_SHOWINTCP",0)
      R.SetMediaTrackInfo_Value(track,"B_SHOWINMIXER",0)
      local item=R.AddMediaItemToTrack(track)
      local take=item and R.AddTakeToMediaItem(item)
      if not take then error("一時解析アイテムを作成できません。",0) end
      R.SetMediaItemTake_Source(take,v.source)
      R.SetMediaItemInfo_Value(item,"D_POSITION",0)
      R.SetMediaItemInfo_Value(item,"D_LENGTH",v.measureLen)
      R.SetMediaItemInfo_Value(item,"D_VOL",1)
      R.SetMediaItemInfo_Value(item,"B_LOOPSRC",v.loop)
      R.SetMediaItemTakeInfo_Value(take,"D_PLAYRATE",1)
      R.SetMediaItemTakeInfo_Value(take,"D_STARTOFFS",v.startoffs)
      R.SetMediaItemTakeInfo_Value(take,"I_CHANMODE",v.chanmode)
      R.SetMediaItemTakeInfo_Value(take,"D_VOL",1)
      aa=R.CreateTakeAudioAccessor(take)
      if not aa then error("音声アクセサーを作成できません。",0) end
      local start,finish=R.GetAudioAccessorStartTime(aa),R.GetAudioAccessorEndTime(aa)
      if not finite(start) or not finite(finish) or finish-start<v.measureLen-1/sr then
        error("取得できる音声範囲がアイテム長と一致しません。",0)
      end
      reader.buffer.clear()
      local rv=R.GetAudioAccessorSamples(aa,sr,v.ch,start+reader.n/sr,count,reader.buffer)
      if type(rv)~="number" or rv<0 then error("音声サンプルの取得に失敗しました。",0) end
      return reader.buffer.table(1,count*v.ch)
    end)
    local destroyed,removed=true,true
    if aa then destroyed=pcall(R.DestroyAudioAccessor,aa) end
    if track then removed=pcall(R.DeleteTrack,track) end
    R.PreventUIRefresh(-1)
    if not destroyed or not removed then error("一時解析データを解放できません。",0) end
    if not ok then error(result,0) end
    reader.cache,reader.cacheAt,reader.cacheFrames=result,reader.n,count
  end
  local samples={};local first=(reader.n-reader.cacheAt)*v.ch
  for i=1,n*v.ch do samples[i]=reader.cache[first+i] end
  return samples
end
function Core.unit_reader(v,peak)
  local buffer=R.new_array(Core.PEAK_READ_BLOCK*v.ch)
  if not buffer then error("音声解析用バッファを作成できません。",0) end
  return {unitRate=true,v=v,n=0,total=floor(v.measureLen*Core.SR+.5),buffer=buffer,
    dsp=not peak and Core.analyzer(v.ch,v.volume*abs(v.takevol)) or nil,
    peak=0,gain=v.volume*abs(v.takevol)}
end
function Core.reader(v)
  if v.rateWarning then return Core.unit_reader(v,false) end
  local aa=R.CreateTakeAudioAccessor(v.take)
  if not aa then error("音声アクセサーを作成できません。",0) end
  local start,finish=R.GetAudioAccessorStartTime(aa),R.GetAudioAccessorEndTime(aa)
  if not finite(start) or not finite(finish) or finish-start<v.len-1/Core.SR then
    pcall(R.DestroyAudioAccessor,aa); error("取得できる音声範囲がアイテム長と一致しません。",0)
  end
  local buffer_ok,buffer=pcall(R.new_array,Core.READ_BLOCK*v.ch)
  if not buffer_ok or not buffer then pcall(R.DestroyAudioAccessor,aa); error("音声解析用バッファを作成できません。",0) end
  local baseGain=v.volume*abs(v.takevol)
  local dsp_ok,dsp=pcall(Core.analyzer,v.ch,baseGain)
  if not dsp_ok or not dsp then pcall(R.DestroyAudioAccessor,aa); error("ラウドネス解析器を作成できません。",0) end
  return {aa=aa,v=v,start=start,n=0,total=floor(v.len*Core.SR+.5),
    buffer=buffer,dsp=dsp}
end
function Core.reader_progress(reader)
  return reader and reader.total>0 and clamp(reader.n/reader.total,0,1) or 0
end
function Core.dispose(reader)
  if reader then reader.cache=nil; if reader.reader then Core.dispose(reader.reader);reader.reader=nil end end
  if reader and reader.aa then local aa=reader.aa;reader.aa=nil;pcall(R.DestroyAudioAccessor,aa) end
end
function Core.read_step(reader)
  local n=min(reader.level and 2048 or Core.READ_BLOCK,reader.total-reader.n)
  if n<=0 then return true end
  local samples
  if reader.unitRate then samples=Core.source_samples(reader,n)
  else
  if R.AudioAccessorStateChanged(reader.aa) then error("解析中にアイテムが変更されました。",0) end
  reader.buffer.clear()
  local rv=R.GetAudioAccessorSamples(reader.aa,Core.SR,reader.v.ch,reader.start+reader.n/Core.SR,n,reader.buffer)
  if type(rv)~="number" or rv<0 then error("音声サンプルの取得に失敗しました。",0) end
    samples=reader.buffer.table(1,n*reader.v.ch)
  end
  Core.feed(reader.dsp,samples,n)
  if reader.level then Core.level_feed(reader.level,samples,n) end
  reader.n=reader.n+n
  return reader.n>=reader.total
end
function Core.peak_reader(v)
  local sr=finite(v.sourceRate) and max(1,floor(v.sourceRate+.5)) or Core.SR
  if v.rateWarning then local reader=Core.unit_reader(v,true);reader.sr=sr;reader.total=floor(v.measureLen*sr+.5);return reader end
  local aa=R.CreateTakeAudioAccessor(v.take)
  if not aa then error("音声アクセサーを作成できません。",0) end
  local start,finish=R.GetAudioAccessorStartTime(aa),R.GetAudioAccessorEndTime(aa)
  if not finite(start) or not finite(finish) or finish-start<v.len-1/sr then
    pcall(R.DestroyAudioAccessor,aa); error("取得できる音声範囲がアイテム長と一致しません。",0)
  end
  local buffer_ok,buffer=pcall(R.new_array,Core.PEAK_READ_BLOCK*v.ch)
  if not buffer_ok or not buffer then pcall(R.DestroyAudioAccessor,aa); error("ピーク解析用バッファを作成できません。",0) end
  return {aa=aa,v=v,sr=sr,start=start,n=0,total=floor(v.len*sr+.5),
    buffer=buffer,peak=0,gain=v.volume*abs(v.takevol)}
end
function Core.peak_read_step(reader)
  local n=min(Core.PEAK_READ_BLOCK,reader.total-reader.n)
  if n<=0 then return true end
  local samples
  if reader.unitRate then samples=Core.source_samples(reader,n)
  else
  if R.AudioAccessorStateChanged(reader.aa) then error("解析中にアイテムが変更されました。",0) end
  reader.buffer.clear()
  local rv=R.GetAudioAccessorSamples(reader.aa,reader.sr,reader.v.ch,reader.start+reader.n/reader.sr,n,reader.buffer)
  if type(rv)~="number" or rv<0 then error("音声サンプルの取得に失敗しました。",0) end
    samples=reader.buffer.table(1,n*reader.v.ch)
  end
  local peak=reader.peak
  for i=1,#samples do
    local x=samples[i]
    if x~=x or abs(x)>=math.huge then error("音声サンプルが不正です。",0) end
    local p=abs(x)
    if p>peak then peak=p end
  end
  reader.peak=peak
  reader.n=reader.n+n
  return reader.n>=reader.total
end
function Core.finish_peak_reader(reader)
  local p=(reader.peak or 0)*(reader.gain or 1)
  if p<=0 then return {valid=false,reason="Sample Peakを測定できません",peak=nil,peakOnly=true} end
  return {valid=true,peak=dba(p),peakOnly=true,frames=nil,sampleRate=reader.sr}
end
Core.TP_FIR={
 { .001708984375,.010986328125,-.0196533203125,.033203125,-.0594482421875,.1373291015625,.97216796875,-.102294921875,.047607421875,-.026611328125,.014892578125,-.00830078125},
 {-.0291748046875,.029296875,-.0517578125,.089111328125,-.16650390625,.465087890625,.77978515625,-.2003173828125,.1015625,-.0582275390625,.0330810546875,-.0189208984375},
 {-.0189208984375,.0330810546875,-.0582275390625,.1015625,-.2003173828125,.77978515625,.465087890625,-.16650390625,.089111328125,-.0517578125,.029296875,-.0291748046875},
 {-.00830078125,.014892578125,-.026611328125,.047607421875,-.102294921875,.97216796875,.1373291015625,-.0594482421875,.033203125,-.0196533203125,.010986328125,.001708984375},
}
function Core.level_analyzer(ch,gain,truepeak,sr)
 local a={ch=ch,gain=gain,peak=0,energy=0,frames=0,history={},cursor=1,tp=0,truepeak=truepeak,sr=sr,waveform={},wavePeak=0,waveCount=0}
 if truepeak then for c=1,ch do local h={};for i=1,24 do h[i]=0 end;a.history[c]=h end end
 return a
end
function Core.tp_sample(a,c,x)
 local h=a.history[c];local j=a.cursor;h[j]=x;h[j+12]=x
 local peak=a.tp
 for phase=1,4 do
  local k=Core.TP_FIR[phase]
  local v=k[1]*h[j+11]+k[2]*h[j+10]+k[3]*h[j+9]+k[4]*h[j+8]
   +k[5]*h[j+7]+k[6]*h[j+6]+k[7]*h[j+5]+k[8]*h[j+4]
   +k[9]*h[j+3]+k[10]*h[j+2]+k[11]*h[j+1]+k[12]*h[j]
  peak=max(peak,abs(v))
 end
 a.tp=peak
end
function Core.level_feed(a,samples,n)
 local p=1
 for _=1,n do
  for c=1,a.ch do
   local x=samples[p];p=p+1
   if not finite(x) then error('音声サンプルが不正です。',0) end
   x=x*a.gain;a.energy=a.energy+x*x;a.peak=max(a.peak,abs(x));a.wavePeak=max(a.wavePeak,abs(x))
   if a.truepeak then Core.tp_sample(a,c,x) end
  end
  a.cursor=a.cursor%12+1;a.frames=a.frames+1;a.waveCount=a.waveCount+1
  if a.waveCount>=a.waveHop then a.waveform[#a.waveform+1]=a.wavePeak;a.waveCount=0;a.wavePeak=0 end
 end
end
function Core.level_finish(a)
 if a.truepeak and not a.flushed then
  for _=1,12 do for c=1,a.ch do Core.tp_sample(a,c,0) end;a.cursor=a.cursor%12+1 end
 end
 if not a.flushed and a.waveCount>0 then a.waveform[#a.waveform+1]=a.wavePeak end
 a.flushed=true
 local power=a.frames>0 and a.energy/(a.frames*a.ch) or 0
 return {valid=a.peak>0,reason=a.peak<=0 and '無音のため測定できません' or nil,
  peak=a.peak>0 and dba(a.peak) or nil,rms=power>0 and dbp(power) or nil,
  truepeak=a.truepeak and a.peak>0 and dba(max(a.peak,a.tp)) or nil,
  levelOnly=true,tpComplete=a.truepeak,duration=a.frames/a.sr,sampleRate=a.sr}
end
function Core.level_reader(v,truepeak)
 local sr=truepeak and max(Core.SR,floor(v.sourceRate+.5)) or max(1,floor(v.sourceRate+.5))
 local reader=Core.peak_reader(v)
 reader.sr=sr;reader.total=floor((v.rateWarning and v.measureLen or v.len)*sr+.5)
 reader.level=Core.level_analyzer(v.ch,v.volume*abs(v.takevol),truepeak,sr)
 reader.level.waveHop=max(1,math.ceil(reader.total/Core.WAVEFORM_BINS))
 return reader
end
function Core.level_read_step(reader)
 local n=min(reader.level.truepeak and 2048 or Core.READ_BLOCK,reader.total-reader.n)
 if n<=0 then return true end
 local samples
 if reader.unitRate then samples=Core.source_samples(reader,n)
 else
  if R.AudioAccessorStateChanged(reader.aa) then error('解析中にアイテムが変更されました。',0) end
  reader.buffer.clear()
  local rv=R.GetAudioAccessorSamples(reader.aa,reader.sr,reader.v.ch,reader.start+reader.n/reader.sr,n,reader.buffer)
  if type(rv)~='number' or rv<0 then error('音声サンプルの取得に失敗しました。',0) end
  samples=reader.buffer.table(1,n*reader.v.ch)
 end
 Core.level_feed(reader.level,samples,n);reader.n=reader.n+n
 return reader.n>=reader.total
end
function Core.all_reader(v)
  local r=Core.reader(v)
  local a={v=v,reader=r,n=0,total=1,phase=1,phases=v.sourceRate==Core.SR and 1 or 2}
  if v.sourceRate<=Core.SR then
    r.level=Core.level_analyzer(v.ch,v.volume*abs(v.takevol),true,Core.SR)
    r.level.waveHop=max(1,math.ceil(r.total/Core.WAVEFORM_BINS))
  end
  return a
end
function Core.all_read_step(a)
  local r=a.reader
  if a.phase==1 then
    local done=Core.read_step(r)
    a.n=Core.reader_progress(r)/a.phases
    if not done then return false end
    local frames=Core.finish(r.dsp)
    a.metrics=Core.measure(frames);a.waveform=Core.waveform_preview(frames)
    if r.level then
      local m=Core.level_finish(r.level)
      a.metrics.truepeak=m.truepeak;a.metrics.tpComplete=true
      if a.phases==1 then a.metrics.peak=m.peak;a.metrics.rms=m.rms end
    end
    Core.dispose(r);a.reader=nil
    if a.phases==1 then a.n=1;return true end
    a.phase=2
    a.reader=Core.level_reader(a.v,a.v.sourceRate>Core.SR)
    return false
  end
  local done=Core.level_read_step(r)
  a.n=(1+Core.reader_progress(r))/a.phases
  if not done then return false end
  local m=Core.level_finish(r.level)
  a.metrics.peak=m.peak;a.metrics.rms=m.rms;a.metrics.sampleRate=m.sampleRate
  if m.tpComplete then a.metrics.truepeak=m.truepeak;a.metrics.tpComplete=true end
  Core.dispose(r);a.reader=nil;a.n=1
  return true
end

function Core.execution_reader(v,mode)
  local r
  if mode==9 then r=Core.peak_reader(v)
  elseif mode==11 or mode==12 then r=Core.level_reader(v,mode==11)
  else r=Core.reader(v) end
  r.executionMode=mode
  return r
end
function Core.execution_read_step(r)
  if r.executionMode==9 then return Core.peak_read_step(r) end
  if r.executionMode==11 or r.executionMode==12 then return Core.level_read_step(r) end
  return Core.read_step(r)
end
function Core.execution_finish(r)
  local mode=r.executionMode
  if mode==9 then return Core.finish_peak_reader(r) end
  if mode==11 or mode==12 then return Core.level_finish(r.level),r.level.waveform end
  local frames=Core.finish(r.dsp);local key=Core.modes[mode].key
  local peak=0
  for _,f in ipairs(frames) do peak=max(peak,f.peak or 0) end
  local m={valid=peak>0,peak=peak>0 and dba(peak) or nil,sampleRate=Core.SR}
  if key=='integrated' then m[key]=Core.integrated(frames)
  elseif key=='speech' then m[key],m.activeRatio=Core.speech(frames)
  elseif key=='max400' then m[key]=Core.max_momentary(frames)
  elseif key=='shortterm' then m[key]=Core.max_window(frames,3)
  else m.median,m.p80,m.p95,m.max1s,m.robust=Core.short_stats(frames) end
  return m,Core.waveform_preview(frames)
end

function Core.channel_label(ch)
  if not ch or ch<1 then return "—" end
  if ch==1 then return "mono" end
  if ch==2 then return "stereo" end
  return string.format("%dch",ch)
end

function Core.plan(items,mode,targetMode,targetValue,referenceIndex,applyMode,monoComp)
  for _,v in ipairs(items) do
    local reason=v.reason or (v.metrics and not v.metrics.valid and (v.metrics.reason or "この方式で測定できません"))
    v.plan=reason and {valid=false,reason=reason} or nil
  end
  local reference=nil
  local refIndex=clamp(floor((referenceIndex or 1)+.5),1,max(1,#items))
  if targetMode==2 then
    local ref=items[refIndex]
    reference=ref and ref.metrics and Core.metric(ref.metrics,mode) or nil
    if not reference then return nil,ref and (ref.metrics or ref.reason) and "基準ファイルは選択方式で測定できません。尺と方式を確認してください。" or "任意ファイルを基準にするため、そのファイルの解析完了を待っています。" end
  end
  local commonMax
  if targetMode~=2 and applyMode==2 then
    for _,v in ipairs(items) do
      local m=not v.reason and v.metrics and v.metrics.valid and Core.metric(v.metrics,mode)
      if finite(m) then commonMax=commonMax and max(commonMax,m) or m end
    end
  end
  local changed=0
  for i,v in ipairs(items) do
    if v.metrics and v.metrics.valid and not v.reason then
      local current=Core.metric(v.metrics,mode)
      if current then
        local target=(targetMode==2) and reference or targetValue
        local gain=clamp(target-(commonMax or current),-Core.MAX_GAIN,Core.MAX_GAIN)
        local mono= v.ch==1 or v.chanmode==2 or v.chanmode==3 or v.chanmode==4
        local monoOffset=monoComp and mono and -3 or 0
        gain=gain+monoOffset
        if commonMax then target=current+(target-commonMax)+monoOffset else target=target+monoOffset end
        local refHold=(targetMode==2 and i==refIndex)
        if refHold then gain=0;target=current;monoOffset=0 end
        local predicted=current+gain
        local predictedPeak=Core.modes[mode].key=='truepeak' and v.metrics.truepeak or v.metrics.peak
        local peakAfter=finite(predictedPeak) and (predictedPeak+gain) or nil
        local doesChange=not refHold and abs(gain)>.005
        if doesChange then changed=changed+1 end
        v.plan={valid=true,current=current,target=target,gain=gain,predicted=predicted,peakAfter=peakAfter,reference=refHold,changed=doesChange,monoOffset=monoOffset,common=commonMax~=nil}
      else
        local key=Core.modes[mode] and Core.modes[mode].key
        local short=v.metrics.duration and v.metrics.duration<(key=="max400" and .4 or key=="shortterm" and 3 or 0)-1e-7
        v.plan={valid=false,reason=short and (key=="max400" and "LUFS-Mには0.4秒以上必要です" or "LUFS-Sには3秒以上必要です") or "この方式で測定できません"}
      end
    end
  end
  return changed
end

function Core.apply(project,items,allowSelectionChange)
  local ok,err=Core.check(project,items,allowSelectionChange); if not ok then return nil,err end
  local targets={}
  for _,v in ipairs(items) do if v.plan and v.plan.valid and v.plan.changed then targets[#targets+1]=v end end
  if #targets==0 then return nil,"適用する変更がありません。" end
  R.Undo_BeginBlock2(project); R.PreventUIRefresh(1)
  local touched={}
  local success,detail=xpcall(function()
    for _,v in ipairs(targets) do
      local newVol=v.volume*amp(v.plan.gain)
      if not finite(newVol) or newVol<=0 then error("アイテム音量を設定できません。",0) end
      touched[#touched+1]=v
      if not R.SetMediaItemInfo_Value(v.item,"D_VOL",newVol) then error("アイテム音量を設定できません。",0) end
      R.UpdateItemInProject(v.item)
    end
  end,debug.traceback)
  local restored=true
  if not success then
    for i=#touched,1,-1 do
      local v=touched[i]
      local called,result=pcall(R.SetMediaItemInfo_Value,v.item,"D_VOL",v.volume)
      if not called or not result then restored=false else R.UpdateItemInProject(v.item) end
    end
  end
  R.PreventUIRefresh(-1)
  if not success then
    R.UpdateArrange();R.Undo_EndBlock2(project,restored and "Simple Normalizer: failed (restored)" or "Simple Normalizer: failed",4)
    local message=tostring(detail):match("^[^\n]+") or tostring(detail)
    return nil,restored and message or (message.." 元の音量へ戻せない項目があります。REAPERのUndoで確認してください。")
  end
  R.UpdateArrange()
  R.Undo_EndBlock2(project,"Simple Normalizer: normalize selected items",4)
  return #targets,targets
end

local SECTION="BLT_SIMPLE_NORMALIZER"
local function extnum(key,default)
  local n=tonumber(R.GetExtState(SECTION,key)); return finite(n) and n or default
end
local S={mode=clamp(floor(extnum("mode",1)+.5),1,#Core.modes),targetMode=clamp(floor(extnum("targetMode",1)+.5),1,2),applyMode=clamp(floor(extnum("applyMode",1)+.5),1,2),monoComp=extnum("monoComp",0)~=0,targets={}}
local function field_round(n) return (n<0 and math.ceil(n*100-.5) or floor(n*100+.5))/100 end
local function field_text(n)
  local text=string.format('%.2f',field_round(n))
  return text:gsub('0+$',''):gsub('%.$','')
end
for i,m in ipairs(Core.modes) do S.targets[i]=field_round(clamp(extnum("target"..i,m.default),-80,6)) end
local A={items={},selected=1,offset=0,message="音声アイテムを選択すると自動解析します。",bad=false,needsAnalyze=true,dirty=true,changeCount=0,
  project=nil,selectionSig=nil,analysisSig=nil,pendingSig=nil,pendingSince=0,autoDelay=.12,applyWhenReady=false,executionLocked=false,forceFinish=false,analyzedCount=0,
  watchAt=0,watchInterval=.20,watchRevision=nil,watchSelectionKey=nil,
  fieldFlash={},fieldDrag=nil,scrollDrag=nil}
local E=nil
local completion
local function status(text,bad) A.message=bad and BLT.publicError(text) or tostring(text or ''); A.bad=bad or false end
local function save_settings()
  BLT.store(SECTION,"mode",tostring(S.mode),true)
  BLT.store(SECTION,"targetMode",tostring(S.targetMode),true)
  BLT.store(SECTION,"applyMode",tostring(S.applyMode),true)
  BLT.store(SECTION,"monoComp",S.monoComp and "1" or "0",true)
  for i,v in ipairs(S.targets) do BLT.store(SECTION,"target"..i,tostring(v),true) end
end
local function target_value() return S.targets[S.mode] end
local function unit() return Core.modes[S.mode].unit end
local function eligible_count()
  local n=0; for _,v in ipairs(A.items) do if not v.reason then n=n+1 end end; return n
end
local function invalidate_snapshot(err)
  local project=R.EnumProjects(-1,"")
  local changed=project~=A.project or Core.selection_signature(project)~=A.selectionSig
  A.changeCount=0;A.dirty=false;A.needsAnalyze=changed
  if changed then A.selectionSig=nil end
  status(err,true)
end
local function replan(partial)
  if #A.items==0 then A.changeCount=0; return end
  if not partial and not A.job then
    local ok,err=Core.check(A.project,A.items,A.executionLocked)
    if not ok then invalidate_snapshot(err); return end
  end
  local n,e=Core.plan(A.items,S.mode,S.targetMode,target_value(),A.selected,S.applyMode,S.monoComp)
  if not n then
    A.changeCount=0; A.dirty=false
    if not A.job then status(e,true) end
    return
  end
  A.changeCount=n; A.dirty=false
  if not A.job then status(string.format("%s · %d件を処理できます。",Core.modes[S.mode].name,n)) end
end
local function cancel_auto(message)
  if A.job then BLT.cleanup(Core.dispose,A.job.reader); A.job=nil end
  A.needsAnalyze=true; A.dirty=true; A.changeCount=0; A.analysisSig=nil; A.applyWhenReady=false; A.executionLocked=false; A.forceFinish=false; A.analyzedCount=0
  if message then status(message,false) end
  collectgarbage("step",400)
end
local function begin_auto_analysis(sig)
 if not Media.ready() then return end
  if A.job then return end
  A.project=R.EnumProjects(-1,"")
  local count=Core.audio_selection_count(A.project)
  if count<=0 then
    A.items={}; A.total=0; A.selected=1; A.offset=0; A.changeCount=0; A.analyzedCount=0
    A.needsAnalyze=true; A.dirty=true; A.selectionSig=sig or "0"; A.analysisSig=nil
    status("音声アイテムを選択すると自動解析します。",false)
    collectgarbage("collect")
    return
  end
  local ok,items,total=pcall(function() local a,b=Core.collect(A.project); return a,b end)
  if not ok then
    A.items={}; A.changeCount=0; A.needsAnalyze=true; A.dirty=true; A.selectionSig=sig; A.analyzedCount=0
    status(tostring(items),true); return
  end
  A.items,A.total=items,total
  A.selected=clamp(A.selected or 1,1,max(1,#A.items)); A.offset=0; A.analyzedCount=0
  A.needsAnalyze=true; A.dirty=true; A.changeCount=0
  A.analysisSig=sig or Core.selection_signature(A.project); A.selectionSig=A.analysisSig
  A.job={index=1,done=0,lastSig=A.analysisSig,validateAt=0}; replan(true)
  status(string.format("%d件をバックグラウンド解析しています…",#A.items),false)
end

local apply_ready -- forward declaration
local function prepare_execution()
  local job=A.job
  if job and not job.executionMode then
    Core.dispose(job.reader);job.reader=nil
    job.executionMode=S.mode
  end
  A.applyWhenReady=true;A.executionLocked=true;A.forceFinish=true
end

local function advance()
 if not Media.ready() then return end
  local job=A.job; if not job then return end
  if R.EnumProjects(-1,"")~=A.project then
    cancel_auto("プロジェクトが切り替わりました。自動更新します。"); A.selectionSig=nil; return
  end
  local currentSig=job.lastSig or A.analysisSig
  local now=R.time_precise()
  if not A.executionLocked and now>=(job.validateAt or 0) then
    currentSig=Core.selection_signature(A.project);job.lastSig=currentSig;job.validateAt=now+(A.watchInterval or .20)
    if currentSig~=A.analysisSig then
      cancel_auto("選択が変わりました。自動更新します。"); A.selectionSig=nil; A.pendingSig=currentSig; A.pendingSince=now; return
    end
  end
  local function update_plan()
    local now=R.time_precise()
    if now>=(job.nextPlanAt or 0) then
      replan(true);job.nextPlanAt=R.time_precise()+.1
    end
  end
  local started=R.time_precise()
  local loops=A.forceFinish and 64 or 4
  local budget=A.forceFinish and .050 or .012
  for _=1,loops do
    local v=A.items[job.index]
    if not v then
      A.job=nil; A.needsAnalyze=false; A.analysisSig=nil
      if not A.executionLocked then A.selectionSig=currentSig end
      A.forceFinish=false
      replan(false)
      if A.applyWhenReady and apply_ready then A.applyWhenReady=false; apply_ready() end
      return
    end
    if v.reason or (v.metrics and v.metrics.allComplete) then
      job.index=job.index+1;job.done=job.done+v.len; A.analyzedCount=A.analyzedCount+1; update_plan()
    else
      local ok,done=xpcall(function()
        if not job.reader then job.reader=job.executionMode and Core.execution_reader(v,job.executionMode) or Core.all_reader(v) end
        if job.executionMode then return Core.execution_read_step(job.reader) end
        return Core.all_read_step(job.reader)
      end,debug.traceback)
      if not ok then
        Core.dispose(job.reader); job.reader=nil; v.reason=tostring(done):match("^[^\n]+")
        job.index=job.index+1; job.done=job.done+v.len; A.analyzedCount=A.analyzedCount+1; update_plan()
      elseif done then
        local reader=job.reader
        if job.executionMode then v.metrics,v.waveform=Core.execution_finish(reader)
        else v.waveform=reader.waveform;v.metrics=reader.metrics;v.metrics.allComplete=true end
        Core.dispose(reader); job.reader=nil; job.index=job.index+1; job.done=job.done+v.len; A.analyzedCount=A.analyzedCount+1
        collectgarbage("step",600)
        update_plan() -- Batch interim plans; final completion always updates immediately.
      end
    end
    if R.time_precise()-started>budget then return end
  end
end

local commit

apply_ready=function()
 if not A.job and not Media.ready() then return end
  if A.job then
    prepare_execution()
    status("対象を固定して、残りを解析後そのままノーマライズします…")
    return
  end
  if A.needsAnalyze or A.dirty then replan(false) end
  local ok,err=Core.check(A.project,A.items,A.executionLocked)
  if not ok then
    A.applyWhenReady=false; A.executionLocked=false; A.forceFinish=false
    invalidate_snapshot(err); return
  end
  local n,appliedOrErr=Core.apply(A.project,A.items,A.executionLocked)
  if not n then
    A.applyWhenReady=false; A.executionLocked=false; A.forceFinish=false
    status(appliedOrErr,true); return
  end
  for _,v in ipairs(A.items) do
    if v.item and R.ValidatePtr2(A.project,v.item,"MediaItem*") then R.SetMediaItemSelected(v.item,false) end
  end
  R.UpdateArrange()
  A.items={}; A.changeCount=0; A.analyzedCount=0; A.needsAnalyze=true; A.dirty=true; A.applyWhenReady=false; A.executionLocked=false; A.forceFinish=false
  A.selectionSig="0"; A.analysisSig=nil; A.pendingSig=nil; A.pendingSince=R.time_precise()
  collectgarbage("collect")
  status(n.."件をノーマライズしました。選択を解除しました。")
  if completion then completion() end
end

local function request_apply()
  if not commit() then return end

  if A.applyWhenReady and A.job then
    A.applyWhenReady=false; A.executionLocked=false; A.forceFinish=false
    Core.dispose(A.job.reader)
    A.job={index=1,done=0,lastSig=A.analysisSig,validateAt=0};A.analyzedCount=0
    status("ノーマライズ実行をキャンセルしました。自動解析は継続します。",false)
    return
  end

  local project=R.EnumProjects(-1,""); local sig=Core.selection_signature(project)
  if Core.audio_selection_count(project)<=0 then status("ノーマライズする音声アイテムを選択してください。",true); return end
  if not Media.ready() then return end
  if A.project~=project or A.selectionSig~=sig then
    cancel_auto(nil)
    begin_auto_analysis(sig)
    if not A.job then return end
  end

  if A.job then
    prepare_execution()
    status("対象を固定して、残りを解析後そのままノーマライズします…")
    return
  end
  if #A.items==0 or A.selectionSig~=sig or A.needsAnalyze then
    begin_auto_analysis(sig)
    if A.job then
      prepare_execution()
      status("対象を固定して、残りを解析後そのままノーマライズします…")
      return
    end
  end
  A.executionLocked=true
  replan(false); apply_ready()
end

local function auto_watch()
 if not Media.ready() then return end
  local project=R.EnumProjects(-1,"")
  if project~=A.project and not A.job then
    A.project=project; A.items={}; A.selected=1; A.offset=0; A.changeCount=0; A.analyzedCount=0
    A.needsAnalyze=true; A.dirty=true; A.selectionSig=nil; A.pendingSig=nil
    A.watchAt=0;A.watchRevision=nil;A.watchSelectionKey=nil
  end
  if A.job then return end
  local now=R.time_precise()
  if now<(A.watchAt or 0) then return end
  A.watchAt=now+(A.watchInterval or .20)
  local revision=R.GetProjectStateChangeCount(project)
  local watchKey=Core.selection_watch_key(project)
  if revision==A.watchRevision and watchKey==A.watchSelectionKey and A.selectionSig~=nil and not A.pendingSig then return end
  A.watchRevision=revision;A.watchSelectionKey=watchKey
  local sig=Core.selection_signature(project)
  if sig==A.selectionSig then A.pendingSig=nil; return end
  if sig~=A.pendingSig then A.pendingSig=sig; A.pendingSince=now; return end
  if now-A.pendingSince<A.autoDelay then return end
  A.pendingSig=nil; begin_auto_analysis(sig)
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
function BLT.normalizerDefaults() local t={mode=1,targetMode=1,applyMode=1,monoComp=false,targets={}};for i,m in ipairs(Core.modes) do t.targets[i]=m.default end;return t end

local function value_for_edit(key)
  if key=="target" then return target_value() end
end

function A.normalize_field(key,n)
  if key=="target" then local v=field_round(clamp(n,-80,6));return v,abs(v-n)>1e-12 end
  return n,false
end

function A.apply_field(key,n,flash)
  if not finite(n) then return false end
  local value,clipped=A.normalize_field(key,n)
  if clipped and flash then A.flash_field(key) end
  local old=value_for_edit(key)
  if abs(value-old)<=1e-12 then return true end
  if key=="target" then S.targets[S.mode]=value end
  save_settings();A.dirty=true;replan(A.job~=nil);return true
end

function A.update_field_drag(py,fine)
  local d=A.fieldDrag;if not d then return end
  local dy=d.startY-py
  if not d.moved and abs(dy)<3 then return end
  d.moved=true;E=nil
  local inc=fine and .1 or 1;local pixels=fine and 8 or 3
  local q=dy/pixels;local ticks=(q<0 and -1 or 1)*floor(abs(q)+.5)
  local raw=d.startValue+ticks*inc;local value,clipped=A.normalize_field(d.key,raw)
  if clipped and not d.clipped then A.flash_field(d.key);d.clipped=true elseif not clipped then d.clipped=false end
  if abs(value-value_for_edit(d.key))>1e-12 then A.apply_field(d.key,value,false) end
end

local function fmt(n,d) return finite(n) and string.format("%."..(d or 1).."f",n) or "—" end

local function signed(n) return finite(n) and string.format("%+.1f",n) or "—" end

local function peak_unit() return S.mode==11 and 'dBTP' or 'dBFS' end

local function peak_color(value,normal) return finite(value) and value>0 and C.red or normal end

local function analysis_progress()
  if not A.job then return nil end
  local j=A.job; local current=j.reader and Core.reader_progress(j.reader)*j.reader.v.len or 0
  return clamp((j.done+current)/max(A.total,.001),0,1)
end

local function set_mode(i)
  if not commit() then return end
  if A.executionLocked then return end
  S.mode=i; save_settings(); A.dirty=true; replan(A.job~=nil)
end

local function set_target_mode(i)
  if not commit() then return end
  S.targetMode=i; save_settings(); A.dirty=true; replan(A.job~=nil)
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
 Language.mb('ReaImGui 0.10以降と js_ReaScriptAPI が必要です。ReaPackで導入・更新してください。','Simple Normalizer',0);return
end
local W,H=1120,764
local ok,value=pcall(BLT.CanvasHost.new,R,'BLT Simple Normalizer',W,H+26,SECTION)
if not ok then Language.mb(BLT.publicError(value),'Simple Normalizer',0);return end
Host=value;Host.minWidth,Host.minHeight,Host.persistSize=560,441,true
Host.width=clamp(floor(extnum('window_w',W)+.5),560,3000)
Host.height=clamp(floor(extnum('window_h',H+26)+.5),441,2226)
local I,ctx=Host.I,Host.ctx
local list
gfx=Host.g
C={bg={.018,.030,.055},bg2={.030,.090,.180},panel={.040,.068,.110},panel2={.055,.125,.205},
 field={.018,.040,.080},edge={.145,.285,.445},edge2={.360,.650,.900},text={.955,.980,1},
 muted={.690,.780,.875},faint={.390,.505,.635},disabled={.43,.46,.51},accent={.120,.490,.980},
 accent2={.650,.895,1},accent3={.045,.235,.520},ice={.650,.895,1},focus={.225,.610,1},
 focus2={.690,.900,1},ink={.018,.075,.160},hover={.430,.790,1},warn={1,.755,.490},red={1,.23,.30},
 green={.47,.85,.70},quiet={.30,.36,.44}}
U=BLT.Controls.new(gfx,R.time_precise,C);U.font,U.minFontSize=Host.faces[1],7
local density=BLT.Controls.compactScale
local scale,ox,oy,mx,my=1,0,0,-1,-1
local awakeUntil=R.time_precise()+6.5
local widgets,widgetByID={},{}
local widgetCount=0
local downLast,pressed=false,nil
local rowsY,rowH,shown,tableX,tableW=425,34,7,360,738
local function wake() awakeUntil=R.time_precise()+6.5 end
local function sx(x) return ox+x*scale end
local function sy(y) return oy+y*scale end
local function color(c,a) gfx.set(c[1],c[2],c[3],a or 1) end
local function rect(x,y,w,h,c,a) color(c,a);gfx.rect(sx(x),sy(y),w*scale,h*scale,1) end
local function line(x,y,x2,y2,c,a) color(c,a);gfx.line(sx(x),sy(y),sx(x2),sy(y2),1) end
local function inside(x,y,w,h) return mx>=x and mx<x+w and my>=y and my<y+h end
local function font(size,kind,bold)
 if size<14 then size=max(11,size+2) end
 gfx.setfont(1,Host.faces[kind or 1],max(7,floor(size*scale+.5)),bold and 98 or 0)
end
local function label(text,x,y,w,h,size,c,bold,flags,kind,literal)
 local shown=literal and tostring(text) or Language.message(text)
 shown=shown:gsub('[%z\1-\31\127]',' ')
 font(size,kind,bold);color(c);gfx.x,gfx.y=sx(x),sy(y)
 gfx.drawstr(shown,flags or 0,sx(x+w),sy(y+h))
end
local function right_label(text,right,y,size,c,kind,bold)
 label(text,right-600,y,600,size+9,size,c,bold,2,kind)
end
local function register(id,x,y,w,h,fn,hint,enabled)
 local widget=widgetByID[id]
 if not widget then widget={id=id};widgetByID[id]=widget end
 widget.x,widget.y,widget.w,widget.h=x,y,w,h
 widget.fn,widget.hint,widget.enabled=fn,hint,enabled~=false
 widgetCount=widgetCount+1;widgets[widgetCount]=widget
end
local function panel(x,y,w,h) controls:panel(x,y,w,h) end
local function guarded(fn)
 local success,err=xpcall(fn,debug.traceback)
 if not success then cancel_auto();status(err,true);BLT.logError(err);wake() end
 return success
end
local function edit(key)
 local state=U:state(key)
 state.done=state.done or function(raw)
  E=nil;local n=tonumber(raw)
  if not finite(n) then A.flash_field(key);status('数値を入力できなかったため、元の値へ戻しました。',true)
  else A.apply_field(key,n,true) end
  wake()
 end
 E={key=key};U.editor:open(key,field_text(value_for_edit(key)),state.done);U.focus=key
end
commit=function()
 if U.editor and U.editor.edit then U.editor:close(false) end
 E=nil;return true
end
local function cancelEdit()
 if U.editor then U.editor:close(true) end
 E=nil;A.fieldDrag=nil;A.scrollDrag=nil;U.capture=nil;pressed=nil
end
menu=BLT.PresetMenu.new(Host,U,{presets=Presets,language=Language,commit=commit,
 layout={width=292,rowHeight=29,headerHeight=36,visiblePresets=8,hoverDelay=1},
 busy=function() return A.executionLocked or A.applyWhenReady end})
shell=BLT.Shell.new(Host,U,R,{
 title='SIMPLE NORMALIZER',subtitle='SIMPLE NORMALIZER  シンプルなノーマライザー',
 barTitle='S I M P L E   N O R M A L I Z E R',section=SECTION,persist=true,
 layout={iconX=W-102,iconY=9,iconScale=.78,footerSize=8},
 language=Language.code,languageChanged=function(code) commit();Language.set(code);wake() end,
 translate=Language.message,store=BLT.store,headerIcon=BLT.SimpleNormalizerIcon,
 iconMode=function() shell.icon.state.working=A.job~=nil;return 'normalize' end,
 stepPreset=function(direction) commit();Presets.step(direction) end,
 drawPresets=function(owner) menu:draw(owner) end,presetSize=function() return menu:size() end,dirty=Presets.dirty})
U.editor=BLT.TextInput.new(Host,U,shell.typography)
controls=BLT.EnvelopeWidgets.new(Host,U,density)
wave=BLT.SimpleNormalizerWave.new(Host,R,C)
list=BLT.SimpleNormalizerList.new(Host,R,shell.typography,Language,C,Core)
Media.state=A;Media.onchange=wake
mediaGraphics.getchar=function() return Host.focused and 6 or 4 end
BLT.blocked=function() return shell.popupOpen or Host.drag~=nil or gfx.mouse_y<26 end
BLT.attachPresets({R=R,section=SECTION,defaults=BLT.normalizerDefaults(),capture=function() return S end,
 upgrade=function(v)
  if type(v)~='table' or type(v.targets)~='table' then return end
  if v.applyMode==nil then v.applyMode=1 end
  if v.monoComp==nil then v.monoComp=false end
  if #v.targets==10 then v.targets[11]=Core.modes[11].default;v.targets[12]=Core.modes[12].default end
 end,
 valid=function(v)
  if v.mode%1~=0 or not Core.modes[v.mode] or (v.targetMode~=1 and v.targetMode~=2) or
   (v.applyMode~=1 and v.applyMode~=2) or type(v.monoComp)~='boolean' or #v.targets~=#Core.modes then return false end
  for _,x in ipairs(v.targets) do if x < -80 or x>6 then return false end end
  return true
 end,
 apply=function(v) for k,x in pairs(v) do S[k]=x end;save_settings();replan(A.job~=nil) end,
 busy=function() return A.executionLocked or A.applyWhenReady end,commit=commit,cancelEdit=cancelEdit,wake=wake})
local projectUndo=create_project_undo(R,{
 language=function() return Language.code end,
 notice=function(text,success) BLT.notice=text;BLT.noticeBad=not success;BLT.noticeUntil=R.time_precise()+7;wake() end,
 editing=function() return U.editor.edit~=nil or shell.popupOpen end,
 busy=function() return A.executionLocked or A.applyWhenReady end,
 before=function() cancel_auto(nil);A.selectionSig=nil;A.watchAt=0 end,
 after=function() A.selectionSig=nil;A.watchAt=0;wake() end})
completion=function() U.now=R.time_precise();U:complete('apply',340/density,48/density);wake() end
function A.flash_field(key) U:flash(key);A.flashUntil=R.time_precise()+.9 end
local segmentOptions={}
local function segment_button(id,text,x,y,w,h,active,fn,hint,enabled,code)
 local opt=segmentOptions[id] or {};segmentOptions[id]=opt
 opt.enabled,opt.selected,opt.led=enabled~=false,active,code and 'left' or 'top'
 opt.ledScale,opt.size,opt.bold=h/(44*density),13/density,true
 opt.labelInset=8/density
 opt.secondaryText=code;opt.captionY=4/density;opt.captionHeight=14/density
 opt.captionSize=9/density;opt.captionAlign='right';opt.captionFace=Host.faces[3]
 opt.labelY,opt.labelHeight=0,h/density
 U:button(id,Language.message(text),x/density,y/density,w/density,h/density,opt)
 register(id,x,y,w,h,fn,hint,enabled)
end
local function section_title(text,x,y,line_end)
 label(text,x,y,150,16,9.5,C.accent2,true)
 line(x+92,y+8,line_end,y+8,C.edge2,.22)
end
local function number_field(id,title,unitText,x,y,w,enabled)
 label(title,x,y+6,w-116,22,11,enabled and C.muted or C.quiet,true)
 local fx,fw=x+w-114,72
 controls:number(id,field_text(value_for_edit(id)),fx,y,fw,31,enabled,{left=7,right=7,size=15})
 label(unitText,fx+fw+7,y+7,40,20,9,enabled and C.faint or C.quiet,true)
 register(id,fx,y,fw,31,function() edit(id) end,'クリック入力 ／ ドラッグ・ホイール：1刻み（Shift：0.1）',enabled)
 local widget=widgets[widgetCount];widget.field=true;widget.key=id
 widget.get=widget.get or function() return value_for_edit(id) end
end
local function waveform(v)
 local x,y,w,h=360,121,738,202;panel(x,y,w,h)
 label(v and v.name or '選択アイテムの波形',x+15,y+10,w-30,23,12,C.text,true,nil,nil,v~=nil)
 right_label(v and string.format('%.2f s',v.len) or 'WAVEFORM',x+w-15,y+11,8,C.faint,3,true)
 if not v or not v.waveform then
  label(v and v.reason or '選択アイテムを自動解析しています',x+15,y+82,w-30,32,13,C.muted,false,5)
  local progress=analysis_progress()
  if progress then local scan=x+15+(w-30)*progress;line(scan,y+40,scan,y+h-28,C.accent2,.45) end
  return
 end
 wave:draw(v.waveform,sx(x+15),sy(y+48),w-30,96,scale)
 local p,m=v.plan,v.metrics
 label(Core.modes[S.mode].name..'  '..fmt(p and p.current)..' → '..fmt(p and p.predicted)..'  /  Gain '..signed(p and p.gain)..' dB',x+15,y+157,570,18,10,C.accent2,true)
 right_label((S.mode==11 and 'True Peak ' or 'Peak ')..fmt(m and (S.mode==11 and m.truepeak or m.peak))..' → '..fmt(p and p.peakAfter)..' '..peak_unit(),x+w-15,y+157,9,peak_color(p and p.peakAfter,C.faint),3,true)
end
local function metric_card(title,value,x,y,w,accent)
 panel(x,y,w,56)
 label(title,x+11,y+8,w-22,16,9,C.muted,true)
 right_label(value,x+w-11,y+23,17,accent or C.text,3,true)
end
local function draw_table()
  if #A.items>shown then gfx.wheelRegion(sx(tableX),sy(401),tableW*scale,294*scale)end
  panel(tableX,401,tableW,294)
  rect(tableX+1,402,tableW-2,23,C.panel2,.6)

  A.offset=clamp(A.offset,0,max(0,#A.items-shown))
  for slot=1,shown do
    local i=A.offset+slot; local row=A.items[i]; local yy=rowsY+(slot-1)*rowH
    if row then
      local selected=(i==A.selected)
      if selected then
        if S.targetMode==2 then
          rect(tableX,yy,tableW-14,rowH,C.accent,.20)
          rect(tableX,yy,4,rowH,C.accent2,.98)
          line(tableX+4,yy,tableX+tableW-18,yy,C.accent2,.58)
          line(tableX+4,yy+rowH-1,tableX+tableW-18,yy+rowH-1,C.edge2,.46)
        else
          rect(tableX,yy,tableW-14,rowH,C.accent,.11)
          rect(tableX,yy,2,rowH,C.accent2,.82)
        end
      elseif slot%2==0 then
        rect(tableX,yy,tableW-14,rowH,C.panel,.36)
      end
      register("row"..i,tableX,yy,tableW-14,rowH,function()
        if commit() then
          A.selected=i
          if S.targetMode==2 then A.dirty=true; replan(A.job~=nil) end
        end
      end,"任意ファイルモードでは、この行をReferenceとして使用します。",true)
    end
  end
  list:draw(A,S,sx(tableX),sy(401),scale)
  local bh=shown*rowH; local th=max(22,bh*min(1,shown/max(1,#A.items))); local ty=rowsY+(#A.items>shown and A.offset/(#A.items-shown)*(bh-th) or 0)
  rect(tableX+tableW-14,rowsY,14,bh,C.panel); rect(tableX+tableW-10,ty,6,th,C.edge2,.62); A.bar={x=tableX+tableW-14,y=rowsY,h=bh,thumb=th,top=ty}
  label(string.format("表示 %d–%d / %d",#A.items>0 and A.offset+1 or 0,min(#A.items,A.offset+shown),#A.items),tableX+4,670,280,18,9,C.faint,false)
end
local execution={cancelable=true,autoComplete=false,finishWhenDisabled=true,captionY=2/density,
 captionHeight=11/density,captionSize=8/density,labelY=15/density,labelHeight=28/density,size=16/density,bold=true}
local function primary_button(enabled)
 execution.enabled,execution.busy=enabled,A.applyWhenReady
 execution.caption=A.applyWhenReady and 'WAITING / CANCEL' or 'NORMALIZE'
 U:execute('apply',Language.message(A.applyWhenReady and '実行をキャンセル' or 'ノーマライズを実行'),390/density,714/density,340/density,48/density,execution)
 register('apply',390,714,340,48,request_apply,A.applyWhenReady and
  'クリックすると、予約中のノーマライズ実行をキャンセルします。自動解析は継続します。' or
  '解析途中でも実行できます。押した時点の対象を固定し、未解析分を完了してからItem Volumeへ適用します。',enabled)
end
local function static()
 widgetCount=0
  local ref=A.items[A.selected]; local v=A.items[A.selected]; local mode=Core.modes[S.mode]
  panel(360,96,738,24)
  label(S.targetMode==2 and "任意ファイル" or "TARGET",372,100,100,16,7.5,S.targetMode==2 and C.accent2 or C.faint,true,0,3)
  if S.targetMode==2 then label(ref and ref.name or "リストから指定",478,99,398,18,10,C.focus2,true,nil,nil,ref~=nil)
  else label(string.format("%s   %.1f %s",mode.name,target_value(),mode.unit),478,99,398,18,10,C.accent2,true) end
  right_label(v and string.format("ITEM %02d",A.selected) or "",1087,100,7.5,C.faint,3,true)

  panel(22,112,318,585)
  label("NORMALIZE METHOD",34,124,190,18,9,C.accent2,true,0,3)
  for row,i in ipairs(Core.mode_order) do
    local m=Core.modes[i]
    local yy=149+(row-1)*26
    segment_button("mode"..i,m.name,34,yy,294,24,S.mode==i,function() set_mode(i) end,m.desc,not A.executionLocked,m.code)
  end
  label(mode.desc,35,466,290,30,9.0,C.muted,false)

  section_title("TARGET",35,505,326)
  segment_button("target_abs","数値指定",35,527,137,35,S.targetMode==1,function() set_target_mode(1) end,"指定した値へ揃えます。",true)
  segment_button("target_ref","任意ファイル",181,527,146,35,S.targetMode==2,function() set_target_mode(2) end,"右側のリストで選んだファイルを基準にします。",true)
  number_field("target","目標値",unit(),35,572,292,S.targetMode==1)
  local groupEnabled=S.targetMode==1 and not A.executionLocked
  segment_button("apply_individual","個別適用",35,616,137,31,(S.targetMode==2 or S.applyMode==1) and groupEnabled,function()
    if commit() then S.applyMode=1;save_settings();replan(A.job~=nil) end
  end,"各アイテムを個別に目標値へ合わせます。",groupEnabled)
  segment_button("apply_group","全体適用",181,616,146,31,S.applyMode==2 and groupEnabled,function()
    if commit() then S.applyMode=2;save_settings();replan(A.job~=nil) end
  end,"選択内の最大測定値を目標に合わせ、全対象に共通ゲインを適用します。",groupEnabled)
  local monoEnabled=not A.executionLocked
  local monoOptions={background=false,showState=false,size=13/density,switchScale=33/(44*density)}
  local _,_,hitWidth=U:toggle('monoComp',Language.message('モノラルの場合追加で-3 dB補正'),S.monoComp,35/density,655/density,292/density,33/density,monoEnabled,monoOptions)
  register('monoComp',35,655,hitWidth*density,33,function()
   if commit() then S.monoComp=not S.monoComp;save_settings();replan(A.job~=nil) end
  end,'ノーマライズ後、モノラル素材だけ追加で-3 dBします。全体適用でも追加補正します。',monoEnabled)

  waveform(v)
  local p=v and v.plan or {}
  metric_card(mode.name,fmt(p and p.current).." "..mode.unit,360,335,174,C.text)
  metric_card(S.targetMode==2 and "任意ファイル" or "TARGET",fmt(p and p.target).." "..mode.unit,540,335,174,S.targetMode==2 and C.focus2 or C.text)
  metric_card("GAIN",signed(p and p.gain).." dB",720,335,174,C.accent2)
  metric_card(S.mode==11 and "TRUE PEAK予測" or "PEAK予測",fmt(p and p.peakAfter).." "..peak_unit(),900,335,198,peak_color(p and p.peakAfter,C.accent2))
  draw_table()


 local selectedNow=Core.audio_selection_count(R.EnumProjects(-1,''))
 local count=#A.items>0 and eligible_count() or selectedNow
 local applyEnabled=A.applyWhenReady or selectedNow>0 and (A.job~=nil or (A.changeCount or 0)>0 or #A.items==0 or A.needsAnalyze)
 label(string.format('対象  %d件',count),258,720,120,18,10.5,C.accent2,true,2,3)
 label(A.job and string.format('解析済み  %d / %d',A.analyzedCount or 0,#A.items) or '解析準備完了',258,739,120,16,8.5,C.muted,true,2,3)
 primary_button(applyEnabled)
 label(A.applyWhenReady and '対象固定中 · 再クリックでキャンセル' or (A.job and 'バックグラウンド解析中' or '実行後は選択を解除'),742,720,230,18,9,A.applyWhenReady and C.accent2 or C.faint,true)
 label(S.targetMode==2 and 'Reference：リスト選択' or '目標値：数値指定',742,739,190,16,8.5,S.targetMode==2 and C.focus2 or C.muted,false)
 for i=#widgets,widgetCount+1,-1 do widgets[i]=nil end
end
local function interact()
 if BLT.blocked() then downLast=(gfx.mouse_cap&1)~=0;pressed=nil;gfx.mouse_wheel=0;return end


  local down=(gfx.mouse_cap&1)~=0;local hit=nil
  for i=#widgets,1,-1 do local w=widgets[i];if inside(w.x,w.y,w.w,w.h) then hit=w;break end end
  if U.editor.edit and hit and hit.id==U.editor.edit.id and not A.fieldDrag and gfx.mouse_wheel==0 then downLast=down;return end
  if down and not downLast then
    local b=A.bar
    if b and inside(b.x,b.y,14,b.h) then
      if my>=b.top and my<=b.top+b.thumb then A.scrollDrag=my-b.top else A.offset=clamp(A.offset+(my<b.top and -shown or shown),0,max(0,#A.items-shown)) end
      pressed=nil
    else
      pressed=hit and hit.id
      if hit and hit.field and hit.enabled and commit() then A.fieldDrag={key=hit.key,startY=my,startValue=hit.get(),moved=false,clipped=false} end
    end
  elseif down and A.scrollDrag then
    local b=A.bar;if b.h>b.thumb then A.offset=floor(clamp((my-b.y-A.scrollDrag)/(b.h-b.thumb),0,1)*max(0,#A.items-shown)+.5) end
  elseif down and A.fieldDrag then
    A.update_field_drag(my,(gfx.mouse_cap&8)~=0)
  elseif not down and downLast then
    local wasFieldDrag=A.fieldDrag and A.fieldDrag.moved
    if not A.scrollDrag and not wasFieldDrag and hit and hit.id==pressed and hit.enabled then hit.fn() elseif not hit then commit() end
    A.scrollDrag=nil;A.fieldDrag=nil;pressed=nil
  end
  downLast=down
  if gfx.mouse_wheel~=0 then
    local wheel=gfx.mouse_wheel
    if hit and hit.field and hit.enabled then
      if not E or commit() then
        local steps=max(1,floor(abs(wheel)/120+.5));local dir=wheel>0 and 1 or -1
        A.apply_field(hit.key,hit.get()+dir*((gfx.mouse_cap&8)~=0 and .1 or 1)*steps,true)
      end
    elseif inside(tableX,401,tableW,294) then
      A.offset=clamp(A.offset+(wheel>0 and -3 or 3),0,max(0,#A.items-shown))
    end
    gfx.mouse_wheel=0
  end
end
local function geometry()
 scale=max(.32,min(gfx.w/W,max(1,gfx.h-26)/H));ox,oy=(gfx.w-W*scale)/2,26+(gfx.h-26-H*scale)/2-22*scale
 mx,my=(gfx.mouse_x-ox)/scale,(gfx.mouse_y-oy)/scale
end
local function draw()
 geometry();shell:begin();U.active=Host.focused;U.themeEnabled=shell.theme.enabled
 color(C.bg);gfx.rect(0,0,gfx.w,gfx.h,1)
 U.scale,U.ox,U.oy=scale,ox,oy+22*scale;shell:header(W)
 local key=gfx.getchar();local wheel=gfx.mouse_wheel or 0
 U:begin(density*scale,ox,oy,0);gfx.mouse_wheel=wheel
 interact()
 if not U.editor.edit and not shell.popupOpen and not projectUndo(key,gfx.mouse_cap) and key==27 then A.closing=true end
 local released=U.released;U.released=false
 static();U.released=released;U:finish()
 local msg=A.message;local rateWarning=false
 for _,v in ipairs(A.items) do if v.rateWarning and not v.reason then rateWarning=true;break end end
 if rateWarning and not A.bad then msg='速度変更あり：1.0倍速換算の測定値です（実再生値とは異なる場合があります）' end
 if Media.waiting then msg=Media.message(SECTION) elseif BLT.notice then msg=BLT.notice end
 U.scale,U.ox,U.oy=scale,ox,oy+22*scale
 shell:footer(msg,A.bad or rateWarning or BLT.noticeBad,W,H,'0.6.1',analysis_progress())
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
BLTShortcuts.install(R,gfx,{
 blocked=function() return U.editor.edit~=nil or shell.popupOpen or A.executionLocked or A.applyWhenReady end,
 beforeGlobal=commit,localKey=function(k,cap) return k==27 or (cap&24)==0 and (k==26 or (cap&4)~=0 and (k==90 or k==122)) end})
local finalized=false
local function close()
 if finalized then return end;finalized=true;A.closed=true
 BLT.cleanup(commit);BLT.cleanup(Core.dispose,A.job and A.job.reader);BLT.cleanup(save_settings)
 BLT.cleanup(list.close,list);BLT.cleanup(wave.close,wave);BLT.cleanup(Host.close,Host);BLT.cleanup(shell.close,shell)
end
R.atexit(close)
local inputState,worldState={},{}
local function changed(state,...)
 local different=false
 for i=1,select('#',...) do local value=select(i,...);if state[i]~=value then state[i]=value;different=true end end
 return different
end
local tipID,tipSince
local function tooltip(now)
 local tip
 if Host.focused and not shell.popupOpen and (gfx.mouse_cap&3)==0 then
  for i=#widgets,1,-1 do local w=widgets[i];if inside(w.x,w.y,w.w,w.h) then tip=w.hint;break end end
 end
 if not tip or tip=='' then tipID=nil;return end
 if tipID~=tip then tipID,tipSince=tip,now
 elseif now-tipSince>.7 then I.PushFont(ctx,Host.font,12);I.SetTooltip(ctx,Language.message(tip));I.PopFont(ctx) end
end
local function loop()
 if finalized then return end
 local begun=false
 local success,err=xpcall(function()
  local now=R.time_precise();Media.tick();guarded(auto_watch)
  if A.job then guarded(advance) end
  shell.theme.tick(now)
  if BLT.noticeUntil and now>=BLT.noticeUntil then BLT.notice,BLT.noticeUntil=nil,nil;wake() end
  if changed(worldState,A.items,A.selected,A.offset,A.message,A.bad,A.job~=nil,A.changeCount,A.analyzedCount,
   A.pendingSig,A.applyWhenReady,A.executionLocked,Media.waiting,Language.code,C.bg,Presets.current,Host.requestReset,shell.icon.dirty) then wake() end
  local interactive=U.editor.edit or shell.popupOpen or Host.drag or shell.hoverID or U.capture or A.fieldDrag or A.scrollDrag
  local animating=U:executeAnimating('apply') or shell.icon:animating(now) or now<(A.flashUntil or 0)
  if not A.job and now>=awakeUntil and not interactive and not animating and Host:idle(now) then
   U.now=now;shell.icon.lastTime=now;R.defer(loop);return
  end
  if Host.idleWake then wake();Host.idleWake=nil end
  if Host.requestReset then Host.width,Host.height=W,H+26 end
  local visible=Host:begin();begun=true
  if visible then
   if changed(inputState,gfx.mouse_x,gfx.mouse_y,gfx.mouse_cap,Host.key,gfx.w,gfx.h,Host.dpi,Host.originX,Host.originY,Host.focused) or
    gfx.mouse_wheel~=0 or (gfx.mouse_cap&1)~=0 or interactive then wake() end
   draw();tooltip(now);Host.pointerCapture=A.fieldDrag or A.scrollDrag
   if not Host.focused then awakeUntil=min(awakeUntil,now+.5) end
  end
  local keep=Host:finish();begun=false
  if not keep or A.closing then close() else R.defer(loop) end
 end,debug.traceback)
 if not success then
  if begun then pcall(Host.finish,Host) end
  close();Language.mb(BLT.publicError(err),'Simple Normalizer | エラー',0)
 end
end
loop()
