-- @description MARKER REGION DESK
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
    local text=self.editor and self.editor.edit and self.editor.edit.id==id and self.editor.edit.text or (opt.format and opt.format(value) or tostring(value))
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

BLT.MarkerDeskIcon=(function()
local M={width=100,height=70,modes={'list'}}
local sin,pi=math.sin,math.pi
local function hash(n,salt)
 local value=sin(n*12.9898+salt*78.233)*43758.5453
 return value-math.floor(value)
end
function M.update() end
function M.draw(p,s,mode,time)
 local C=p.C;local breath=.85+.15*sin(time*.72)
 for i=7,1,-1 do
  p:disc(64,34,3+i*3.3,C.accent,(.002+(7-i)*.0018)*breath)
  p:disc(75,24,2+i*1.7,C.ice,.0025*breath)
 end
 p:rect(39,12,71,52,C.bg,.97)
 p:rect(41,14,67,48,C.panel2,.82)
 for lane=1,3 do
  local y=17+(lane-1)*16
  p:rect(46,y,57,11,C.field,.48)
  p:line(73,y+4,99-(lane==3 and 3 or 0),y+4,C.ice,.64)
  p:line(73,y+8,91+(lane==2 and 4 or 0),y+8,C.edge2,.40)
  if lane<3 then p:line(44,y+13,105,y+13,C.edge2,.22) end
 end
 p:line(53,18,53,27,C.ice,.78)
 p:line(54,18,66,21,C.ice,.8);p:line(66,21,54,24,C.ice,.55)
 p:line(54,24,54,18,C.accent,.72)
 p:rect(54,36,12,5,C.accent,.30)
 p:line(53,38.5,67,38.5,C.ice,.70)
 p:line(53,34.5,53,42.5,C.ice,.76);p:line(67,34.5,67,42.5,C.ice,.76)
 p:disc(60,38.5,1.05,C.ice,.82)
 p:line(55,50,55,59,C.ice,.68)
 p:line(55,50,65,52.5,C.ice,.72);p:line(65,52.5,55,55,C.ice,.54)
 p:line(44,12,102,12,C.ice,.72)
 p:line(102,12,110,20,C.ice,.64);p:line(110,20,110,57,C.edge2,.36)
 p:line(110,57,103,64,C.ice,.58);p:line(103,64,44,64,C.edge2,.28)
 p:line(39,59,39,17,C.ice,.42)
 p:disc(102,12,3.6,C.ice,.035);p:disc(102,12,.65,C.ice,.92)
end
function M.emit(s,n,p)
 p.lane=1+(n-1)%3;p.subline=hash(n,69)>.68 and 2 or 1
 p.slot,p.spread=.22+hash(n,70)*.78,(hash(n,72)-.5)*5.5
 p.phase,p.depth=hash(n,73)*pi*2,hash(n,75)
 p.life,p.r,p.glint=1.05+hash(n,71)*.70,.28+p.depth*.77,hash(n,74)>.90
end
local sourceX,sourceY={66,67,65},{21,38.5,52.5}
local lineY,lineEndX={{21,25},{37,41},{53,57}},{{99,91},{99,95},{96,88}}
function M.sample(s,p,age)
 local t=age/p.life;local u=1-t
 local x,y=sourceX[p.lane],sourceY[p.lane]
 local ey=lineY[p.lane][p.subline];local ex=75+(lineEndX[p.lane][p.subline]-75)*p.slot
 return u*u*u*x+3*u*u*t*(x+7)+3*u*t*t*(ex-6)+t*t*t*ex,
  u*u*u*y+3*u*u*t*(y+p.spread)+3*u*t*t*(ey+p.spread*.16)+t*t*t*ey+
   sin(t*8+p.phase)*u*u*(.7+p.depth*1.1)
end
return M
end)()

BLT.MarkerDeskList=(function()
local M={}
local min,max,floor,ceil=math.min,math.max,math.floor,math.ceil
M.keys={'isrgn','id','pos','ending','before'}
local titles={'種別','ID','開始','終了','名前'}
local paletteKeys={'field','panel','panel2','edge','edge2','accent3','focus2'}
function M.new(host,api,text,language,C)
 local L={signature={}};local background,glyph={},{}
 local scale,density,factor,offset,width,rows,T,sortKey,descending
 local colors,colorCount={},0
 local function packed(c)
  return 0xff000000|(floor(c[1]*255+.5)<<16)|(floor(c[2]*255+.5)<<8)|floor(c[3]*255+.5)
 end
 local function prepare(layer,w,h,fill)
  if not layer.bitmap then layer.bitmap=assert(api.JS_LICE_CreateBitmap(true,w,h),'List bitmap creation failed')
  elseif layer.w~=w or layer.h~=h then api.JS_LICE_Resize(layer.bitmap,w,h) end
  layer.w,layer.h=w,h;api.JS_LICE_Clear(layer.bitmap,fill)
 end
 local function upload(layer)
  if layer.image then host:releaseImage(layer.image) end
  layer.image=host.I.CreateImageFromLICE(layer.bitmap);host:attachImage(layer.image)
 end
 local function rect(x,y,w,h,c,a)
  api.JS_LICE_FillRect(background.bitmap,floor(x*factor+.5),floor(y*factor+.5),
   max(1,floor(w*factor+.5)),max(1,floor(h*factor+.5)),packed(c),a or 1,'COPY')
 end
 local function line(x,y,xx,yy,c)
  api.JS_LICE_Line(background.bitmap,x*factor,y*factor,xx*factor,yy*factor,packed(c),1,'COPY',true)
 end
 local function decorations(v,y,drawRect,drawLine)
  if v.color~=0 then
   local c=colors[v.color]
   if not c then
    if colorCount>=128 then colors={};colorCount=0 end
    local r,g,b=api.ColorFromNative(v.color);c={r/255,g/255,b/255};colors[v.color]=c;colorCount=colorCount+1
   end
   drawRect(3,y+9,3,14,c,1)
  end
  drawRect(8,y+8,15,15,C.field,1)
  drawRect(8,y+8,15,1,C.edge2,.85);drawRect(8,y+22,15,1,C.edge2,.85)
  drawRect(8,y+8,1,15,C.edge2,.85);drawRect(22,y+8,1,15,C.edge2,.85)
  if v.visible then
   drawRect(9,y+9,13,13,C.accent3,.8)
   drawLine(11,y+15,14,y+19,C.focus2);drawLine(14,y+19,20,y+12,C.focus2)
  end
 end
 local function font(size,bold,kind)
  text:setfont(1,host.faces[kind or 1],max(8,floor(size*scale+.5)),bold and 98 or 0)
 end
 local function fit(value,available)
  if text:measurestr(value)<=available then return value end
  if text:measurestr('…')>available then return '' end
  local n=utf8.len(value)
  if not n then value=value:gsub('[\128-\255]','?');n=#value end
  local lo,hi=0,n
  while lo<hi do
   local mid=floor((lo+hi+1)/2);local at=utf8.offset(value,mid+1) or #value+1
   if text:measurestr(value:sub(1,at-1)..'…')<=available then lo=mid else hi=mid-1 end
  end
  return value:sub(1,(utf8.offset(value,lo+1) or #value+1)-1)..'…'
 end
 local command={}
 local function label(value,x,y,w,size,bold,kind,centerH,band)
  font(size,bold,kind);value=fit(tostring(value),max(0,w*scale))
  if centerH then local _,height=text:measurestr(value);y=y+(centerH-height/scale)*.5 end
  text:capture(command,value,x*scale,y*scale,0xffffffff,1)
  if band then command.x=(background.w+(band-1)*L.strip)/density end
  text:paintMask(command,glyph.bitmap)
 end
 function L:columns(style,W)
  local tw=max(75,min(style.time_width or 75,max(75,(W-289)/2)))
  self.cols=self.cols or {};self.widths=self.widths or {}
  local c,w=self.cols,self.widths
  c[1],c[2],c[3],c[4],c[5]=style.x+34,style.x+78,style.x+115,style.x+117+tw,style.x+119+2*tw
  w[1],w[2],w[3],w[4],w[5]=42,35,tw,tw,W-189-2*tw
  return c,w
 end
 function L:prepare(A,style,W,s,sort,desc,editing)
  scale,density=s,ceil(host.dpi or 1);factor=scale*density
  local count=floor((style.h-style.header)/style.row)
  local i=0;local bgDirty,textDirty=self.bgDirty or not background.image,self.textDirty or not glyph.image
  local function check(v,kind)
   i=i+1
   if self.signature[i]~=v then
    self.signature[i]=v
    if kind~=1 then bgDirty=true end
    if kind~=2 then textDirty=true end
   end
  end
  check(scale);check(density);check(style.w);check(style.h);check(A.offset);check(count)
  check(min(count,max(0,#A.rows-A.offset)))
  check(language.code,1);check(sort or false);check(desc)
  for _,key in ipairs(paletteKeys) do check(C[key],2) end
  local timeWidth=75
  for index=A.offset+1,min(#A.rows,A.offset+count) do
   local row=A.rows[index];local v=row.info;local values=row.text
   check(v.visible,2);check(v.color,2);check(v.isrgn,1)
   check(values[1],1);check(values[2],1);check(values[3],1);check(values[4],1)
   local metrics=row.widths
   if not metrics or metrics.scale~=s or metrics.dpi~=density or metrics.first~=values[2] or metrics.last~=values[3] then
    font(13.5,false)
    metrics={scale=s,dpi=density,first=values[2],last=values[3],
     width=max(ceil(text:measurestr(values[2])/s)+4,ceil(text:measurestr(values[3])/s)+4)}
    row.widths=metrics
   end
   timeWidth=max(timeWidth,metrics.width)
  end
  if not editing then style.time_width=timeWidth end
  check(style.time_width)
  for k=#self.signature,i+1,-1 do self.signature[k]=nil end
  self.bgDirty,self.textDirty=bgDirty,textDirty;self:columns(style,W)
  offset,width,rows,T,sortKey,descending=A.offset,style.w,A.rows,style,sort,desc
 end
 local drawX,drawY
 local function drawRect(x,y,w,h,c,a)
  local xx,yy=drawX+floor(x*factor+.5)/density,drawY+floor(y*factor+.5)/density
  host.I.DrawList_AddRectFilled(host.draw,xx,yy,xx+max(1,floor(w*factor+.5))/density,
   yy+max(1,floor(h*factor+.5))/density,host.rgba(c[1],c[2],c[3],a or 1))
 end
 local function drawLine(x,y,xx,yy,c)
  host.I.DrawList_AddLine(host.draw,drawX+x*scale,drawY+y*scale,drawX+xx*scale,drawY+yy*scale,host.rgba(c[1],c[2],c[3],1),1)
 end
 local function drawGradient(x,y,w,h,a,b,aa,ab)
  local xx,yy=drawX+floor(x*factor+.5)/density,drawY+floor(y*factor+.5)/density
  local left,right=host.rgba(a[1],a[2],a[3],aa),host.rgba(b[1],b[2],b[3],ab)
  host.I.DrawList_AddRectFilledMultiColor(host.draw,xx,yy,xx+max(1,floor(w*factor+.5))/density,
   yy+max(1,floor(h*factor+.5))/density,left,right,right,left)
 end
 function L:draw(x,y)
  local cols,widths=self.cols,self.widths
  local count=floor((T.h-T.header)/T.row)
  if self.bgDirty then
   prepare(background,max(1,ceil(T.w*factor)),max(1,ceil(T.h*factor)),packed(C.field))
   rect(0,0,width,T.header,C.panel2,1);rect(0,0,width,1,C.edge2,.65)
   for i,key in ipairs(M.keys) do if sortKey==key then rect(cols[i]-T.x-2,0,widths[i]+2,T.header,C.accent3,.50) end end
   for slot=1,count do
    local row=rows[offset+slot]
    if row then
     local yy=T.header+(slot-1)*T.row
     if slot%2==0 then rect(1,yy,width-T.bar-1,T.row,C.panel,.50) end
     rect(4,yy+T.row-1,width-T.bar-4,1,C.edge,.16)
     decorations(row.info,yy,rect,line)
    end
   end
   api.JS_LICE_ProcessRect(background.bitmap,0,0,background.w,background.h,'SET_A',0xff000000)
   upload(background);self.bgDirty=false
  end
  if self.textDirty then
   self.strip=max(1,ceil(32*factor))
   prepare(glyph,background.w+2*self.strip,background.h,0xff000000)
   label(language.text('表示'),2,7,30,13,true)
   for i,key in ipairs(M.keys) do
    local active=sortKey==key
    label(language.text(titles[i])..(active and (descending and ' ↓' or ' ↑') or ''),cols[i]-T.x,7,widths[i],14,true)
   end
   for slot=1,count do
    local row=rows[offset+slot]
    if row then
     local v=row.info;local yy=T.header+(slot-1)*T.row
     label(v.isrgn and 'R' or 'M',cols[1]-T.x,yy+6,widths[1],16,true,3,nil,v.isrgn and 1 or nil)
     label(row.text[1],cols[2]-T.x,yy+6,widths[2]-2,16,false)
     for column=2,3 do
      local available=widths[column+1]-2
      font(13.5,false);local measured=text:measurestr(row.text[column])/scale
      local size=measured>available and max(9,13.5*available/measured) or 13.5
      label(row.text[column],cols[column+1]-T.x,yy+7+(13.5-size)/2,available,size,false,1,nil,column==3 and not v.isrgn and 2 or nil)
     end
     label(row.text[4],cols[5]-T.x,yy,widths[5]-8,18,false,1,T.row)
    end
   end
   api.JS_LICE_Blit(glyph.bitmap,0,0,glyph.bitmap,0,0,glyph.w,glyph.h,1,'CHANCOPY_RTOA')
   api.JS_LICE_ProcessRect(glyph.bitmap,0,0,glyph.w,glyph.h,'SET_RGB',0xffffff)
   upload(glyph);self.textDirty=false
  end
  local ox,oy=host.windowX or host.originX,host.windowY or host.originY
  drawX=ox+floor((host.originX-ox+x)*density+.5)/density
  drawY=oy+floor((host.originY-oy+y)*density+.5)/density
  local I,draw=host.I,host.draw;local w,h=background.w/density,background.h/density
  I.DrawList_AddImage(draw,background.image,drawX,drawY,drawX+w,drawY+h)
  for slot=1,count do
   local row=rows[offset+slot]
   if row and row.info.selected then
    local yy=T.header+(slot-1)*T.row
    drawRect(1,yy,width-T.bar-1,T.row,C.field,1)
    drawGradient(1,yy,width-T.bar-1,T.row,C.accent3,C.panel,.76,1)
    drawRect(1,yy,3,T.row,C.focus2,.88)
    drawGradient(4,yy,13,T.row,C.accent2,C.accent2,.18,0)
    drawGradient(4,yy,width-T.bar-4,1,C.focus2,C.accent2,.50,.05)
    drawRect(4,yy+T.row-1,width-T.bar-4,1,C.edge,.16)
    decorations(row.info,yy,drawRect,drawLine)
   end
  end
  local c=C.text;local tint=host.rgba(c[1],c[2],c[3],1)
  I.DrawList_AddImage(draw,glyph.image,drawX,drawY,drawX+w,drawY+h,0,0,background.w/glyph.w,1,tint)
  local accent,faint=host.rgba(C.accent2[1],C.accent2[2],C.accent2[3],1),host.rgba(C.faint[1],C.faint[2],C.faint[3],1)
  for slot=1,count do
   local row=rows[offset+slot]
   if row then
    local region=row.info.isrgn;local band=region and 1 or 2
    local px=background.w+(band-1)*self.strip
    local top=floor((T.header+(slot-1)*T.row)*factor+.5)
    local bottom=floor((T.header+slot*T.row)*factor+.5)
    local xx=drawX+floor((cols[region and 1 or 4]-T.x)*factor+.5)/density
    local yy=drawY+top/density
    I.DrawList_AddImage(draw,glyph.image,xx,yy,xx+self.strip/density,drawY+bottom/density,
     px/glyph.w,top/glyph.h,(px+self.strip)/glyph.w,bottom/glyph.h,region and accent or faint)
   end
  end
 end
 function L:close()
  for _,layer in ipairs({background,glyph}) do
   if layer.image then host:releaseImage(layer.image);layer.image=nil end
   if layer.bitmap then api.JS_LICE_DestroyBitmap(layer.bitmap);layer.bitmap=nil end
  end
 end
 return L
end
return M
end)()
local NAME="MARKER REGION DESK"
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
 ["テキストを取得できません。"]="Cannot read text.",
 ["テキストは16 MiB以内にしてください。"]="Keep text under 16 MiB.",
 ["UTF-16テキストが途中で切れています。"]="Truncated UTF-16 text.",
 ["UTF-16の文字が不完全です。"]="Incomplete UTF-16 character.",
 ["UTF-16の文字が不正です。"]="Invalid UTF-16 character.",
 ["UTF-8またはBOM付きUTF-16のテキストを使用してください。"]="Use UTF-8 or UTF-16 with a BOM.",
 ["名前は1行4096バイト以内にしてください。"]="Keep each name under 4096 bytes.",
 ["名前に使用できない制御文字があります。"]="Name contains invalid control characters.",
 ["入力は20万行以内にしてください。"]="Limit input to 200,000 lines.",
 ["引用符の後に区切り以外の文字があります。入力形式を確認してください。"]="Unexpected text after a quote. Check input format.",
 ["閉じられていない引用符があります。テキストの末尾を確認してください。"]="Unclosed quote. Check the end of the text.",
 ["クリップボードを読み込めません。"]="Cannot read clipboard.",
 ["クリップボード取得に失敗しました。もう一度コピーして貼り付けてください。"]="Clipboard read failed. Copy and paste again.",
 ["クリップボードの読み込みが不完全です。件数を減らして貼り付けてください。"]="Incomplete clipboard read. Paste fewer entries.",
 ["この環境での貼り付けにはSWSのクリップボード機能が必要です。"]="Pasting requires SWS clipboard support on this system.",
 ["選択・表示の連動にはREAPER 7.62以降が必要です。"]="Selection/visibility sync requires REAPER 7.62+.",
 ["マーカー／リージョンを取得できません。"]="Cannot read markers/regions.",
 ["マーカー／リージョン情報の取得に失敗しました。"]="Failed to read marker/region information.",
 ["対象が変更されました。一覧を確認してください。"]="Targets changed. Check the list.",
 ["選択／表示状態を変更できませんでした。"]="Cannot update selection/visibility.",
 ["プロジェクトが変わりました。"]="Project changed.",
 ["対象が変更されました。選択を確認してください。"]="Targets changed. Check selection.",
 ["削除する行を選択してください。"]="Select rows to delete.",
 ["削除に失敗しました。"]="Delete failed.",
 ["削除結果を確認できません。"]="Cannot verify deletion.",
 ["削除できませんでした。一覧を確認してください。\n"]="Could not delete. Check the list.\n",
 ["削除を中止しましたが復元を確認できません。REAPERのUndo履歴を確認してください。"]="Deletion stopped but restore could not be verified. Check REAPER Undo history.",
 ["削除を中止し、変更をUndoで復元しました。\n"]="Deletion stopped. Changes restored with Undo.\n",
 ["名前は4096バイト以内にしてください。"]="Keep names under 4096 bytes.",
 ["種類\tID\t名前\t開始（秒）\t終了（秒）\t長さ（秒）\t色（RGB）"]="Type\tID\tName\tStart (s)\tEnd (s)\tLength (s)\tColor (RGB)",
 ["標準"]="Default",
 ["コピーは16 MiB以内にしてください。対象を絞り込んでください。"]="Keep copied data under 16 MiB. Select fewer targets.",
 ["クリップボードへの書き込みを確認できませんでした。もう一度コピーしてください。"]="Cannot verify clipboard write. Copy again.",
 ["情報のコピーにはSWSのクリップボード機能が必要です。"]="Copying information requires SWS clipboard support.",
 ["一時ファイルの作成に失敗しました。"]="Cannot create temporary file.",
 ["一時ファイルのパスが無効です。"]="Invalid temporary file path.",
 ["プロジェクトが変わりました。対応関係を確認してください。"]="Project changed. Check mappings.",
 ["対象が変わりました。対応関係を確認してください。"]="Targets changed. Check mappings.",
 ["マーカー／リージョンが変更されました。対応関係を確認してください。"]="Markers/regions changed. Check mappings.",
 ["変更予定がありません。"]="No changes planned.",
 ["名前の設定結果を確認できません（%s ID %.0f）。"]="Cannot verify name (%s ID %.0f).",
 ["リージョン"]="Region",
 ["マーカー"]="Marker",
 ["変更に失敗したため、元の名前に戻しました。"]="Rename failed. Original names restored.",
 ["復元に失敗した項目があります。REAPERのUndoで戻してください。"]="Some names could not be restored. Use REAPER Undo.",
 ["個別の非表示は解除しました。レーンやREAPERの表示設定も確認してください。"]="Individual visibility restored. Also check lane and REAPER display settings.",
 ["Undoを実行できませんでした。"]="Cannot perform Undo.",
 ["選択が変わりました。対象を確認して貼り付け直してください。"]="Selection changed. Check targets and paste again.",
 ["コピー|一覧情報をコピー|名前を貼り付け"]="Copy|Copy list details|Paste names",
 ["コピーしました"]="Copied",
 ["カスタムタイトルバーには js_ReaScriptAPI が必要です。\nReaPack から js_ReaScriptAPI をインストールしてください。"]="The app bar requires js_ReaScriptAPI.\nInstall js_ReaScriptAPI via ReaPack.",
 ["〈空欄〉"]="<empty>",
 ["あいうえお漢字ABC012345"]="あいうえお漢字ABC012345",
 ["名前が長すぎるか、使用できない制御文字があります。"]="Name too long or contains invalid control characters.",
 ["ReaImGui 0.10以降が必要です。ReaPackで導入・更新してください。"]="ReaImGui 0.10+ is required. Install/update via ReaPack.",
 ["ReaImGui 0.10以降と js_ReaScriptAPI が必要です。ReaPackで導入・更新してください。"]="ReaImGui 0.10+ and js_ReaScriptAPI are required. Install/update them via ReaPack.",
 ["日本語入力欄を初期化できません。\n"]="Cannot initialize the text input.\n",
 ["文字列でフィルター…"]="Filter text...",
 ["種別"]="Type",
 ["開始"]="Start",
 ["終了"]="End",
 ["名前"]="Name",
 ["表示"]="Vis",
 ["プロジェクトにマーカー/リージョンがありません"]="No markers/regions in the project",
 ["該当するマーカー/リージョンはありません"]="No matching markers/regions",
 ["MARKER / REGION / LOOP LIST  マーカー・リージョン・ループのリスト"]="MARKER / REGION / LOOP LIST  Browse markers, regions and loops",
 ["すべて"]="All",
 ["ループリージョンを除外"]="Exclude loop regions",
 ["クリア"]="Clear",
 ["シーク再生"]="Seek playback",
 ["選択位置へ移動"]="Go to selection",
 ["↑ 先頭"]="↑ First",
 ["↓ 末尾"]="↓ Last",
 ["全名前をコピー"]="Copy all names",
 ["全情報をコピー"]="Copy all details",
 ["名前を貼付（先頭から）"]="Paste names (from first)",
 ["マーカー／リージョンがありません。"]="No markers/regions.",
 ["%d件  選択 %d件"]="%d entries  %d selected",
 ["カスタムタイトルバーを初期化できません。"]="Cannot initialize the app bar.",
 ["日本語入力欄でエラーが発生しました。\n"]="Text input error.\n",
 ["表示言語を切替（JP / EN）"]="Switch language (JP / EN)",
 ["プリセットを読み込みました: ファクトリーデフォルト"]="Loaded: Factory Default",
 ["選択中のトラック / バスを指定"]="Use selected track / bus",
},patterns={
 {"^「(.*)」を上書きしますか？$","Overwrite \"%s\"?"},
 {"^([%+%-]?[%d%.eE]+)–([%+%-]?[%d%.eE]+) / ([%+%-]?[%d%.eE]+)   スクロールで選択$","%d–%d / %d   Scroll to browse"},
 {"^解析中%.%.%.([%+%-]?[%d%.eE]+)%%$","Analyzing...%d%%"},
 {"^名前の設定結果を確認できません（(.-) ID ([%+%-]?[%d%.eE]+)）。$","Cannot verify name (%s ID %.0f).",{1}},
 {"^([%+%-]?[%d%.eE]+)件  選択 ([%+%-]?[%d%.eE]+)件$","%d entries  %d selected"},
 {"^「(.-)」を上書きしますか？$","\"%s\"?"},
 {"^(.-)」を上書きしますか？$","%s\"?"},
 {"^プリセットを保存しました: (.-)$","Saved: %s"},
 {"^プリセットを読み込みました: (.-)$","Loaded: %s"},
 {"^(.-)個インポートしました。$","%s preset(s) imported."},
 {"^現在: (.-)(.-)$","Current: %s%s"},
 {"^削除できませんでした。一覧を確認してください。\n(.-)$","Could not delete. Check the list.\n%s"},
 {"^削除を中止し、変更をUndoで復元しました。\n(.-)$","Deletion stopped. Changes restored with Undo.\n%s"},
 {"^日本語入力欄を初期化できません。\n(.-)$","Cannot initialize the text input.\n%s"},
 {"^日本語入力欄でエラーが発生しました。\n(.-)$","Text input error.\n%s"},
 {"^「(.*)」を上書きしますか？$","Overwrite \"%s\"?"},
 {"^(%d+)個インポートしました。$","Imported %s preset(s)."},
 {"^(%d+)件をノーマライズしました。選択を解除しました。$","Normalized %s items and deselected them."},
},prefixes={"削除できませんでした。一覧を確認してください。\n","削除を中止し、変更をUndoで復元しました。\n","日本語入力欄でエラーが発生しました。\n","日本語入力欄を初期化できません。\n","プリセットを読み込みました: ","プリセットを保存しました: ","現在: "}}

local Language=create_language(reaper,"BLT_MARKER_REGION_DESK",LanguageCatalog)
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
local Core={MAX_BYTES=16*1024*1024,MAX_ROWS=200000,MAX_NAME=4096}
local min,max,floor=math.min,math.max,math.floor
local function clamp(n,a,b) return max(a,min(b,n)) end
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end

function Core.text(s)
  if type(s)~="string" then error("テキストを取得できません。",0) end
  if #s>Core.MAX_BYTES then error("テキストは16 MiB以内にしてください。",0) end
  if s:sub(1,2)=="\255\254" or s:sub(1,2)=="\254\255" then
    local le=s:byte(1)==255
    if #s%2~=0 then error("UTF-16テキストが途中で切れています。",0) end
    local out={}; local i=3
    local function unit(p) local a,b=s:byte(p,p+1); return le and a+b*256 or b+a*256 end
    while i<=#s do
      local u=unit(i); i=i+2
      if u>=0xD800 and u<=0xDBFF then
        if i>#s then error("UTF-16の文字が不完全です。",0) end
        local low=unit(i); i=i+2
        if low<0xDC00 or low>0xDFFF then error("UTF-16の文字が不正です。",0) end
        u=0x10000+(u-0xD800)*1024+low-0xDC00
      elseif u>=0xDC00 and u<=0xDFFF then error("UTF-16の文字が不正です。",0) end
      out[#out+1]=utf8.char(u)
    end
    s=table.concat(out)
  end
  if s:sub(1,3)=="\239\187\191" then s=s:sub(4) end
  if s:find("\0",1,true) or not utf8.len(s) then error("UTF-8またはBOM付きUTF-16のテキストを使用してください。",0) end
  return s:gsub("\r\n","\n"):gsub("\r","\n")
end
function Core.parser(text)
  text=Core.text(text)
  return {text=text,p=1,rows={},field={},col=1,at_start=true,quoted=false,after_quote=false,
    row_started=false,columns=false,flattened=0,done=false}
end
local function finish_row(j)
  local value=table.concat(j.field)
  if #value>Core.MAX_NAME then error("名前は1行4096バイト以内にしてください。",0) end
  local clean,n=value:gsub("[\n\t]"," ")
  if clean:find("[%z\1-\8\11\12\14-\31\127]") then error("名前に使用できない制御文字があります。",0) end
  if n>0 then j.flattened=j.flattened+1 end
  j.rows[#j.rows+1]=clean
  if #j.rows>Core.MAX_ROWS then error("入力は20万行以内にしてください。",0) end
  j.field={}; j.col=1; j.at_start=true; j.after_quote=false; j.row_started=false
end
function Core.parse_step(j,budget)
  if j.done then return true end
  local last=min(#j.text,j.p+(budget or 65536)-1)
  while j.p<=last do
    local ch=j.text:sub(j.p,j.p); local nextch=j.text:sub(j.p+1,j.p+1)
    if j.quoted then
      if ch=='"' then
        if nextch=='"' then if j.col==1 then j.field[#j.field+1]='"' end; j.p=j.p+1
        else j.quoted=false; j.after_quote=true end
      elseif j.col==1 then j.field[#j.field+1]=ch end
      j.row_started=true
    elseif ch=='\n' then
      finish_row(j)
    elseif ch=='\t' then
      j.col=j.col+1; j.columns=true; j.at_start=true; j.after_quote=false; j.row_started=true
    elseif ch=='"' and j.at_start then
      j.quoted=true; j.at_start=false; j.row_started=true
    else
      if j.after_quote then error("引用符の後に区切り以外の文字があります。入力形式を確認してください。",0) end
      if j.col==1 then j.field[#j.field+1]=ch end
      j.at_start=false; j.row_started=true
    end
    j.p=j.p+1
  end
  if j.p>#j.text then
    if j.quoted then error("閉じられていない引用符があります。テキストの末尾を確認してください。",0) end
    if j.row_started then finish_row(j) end
    j.done=true
  end
  return j.done
end
function Core.parse(text)
  local j=Core.parser(text); while not Core.parse_step(j) do end; return j.rows,j
end

Core.WINDOWS_COMMAND=[[powershell.exe -NoLogo -NoProfile -NonInteractive -STA -WindowStyle Hidden -Command "$ErrorActionPreference='Stop'; [Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false); $text=[string](Get-Clipboard -Raw); [Console]::Write(('RN1 '+[Text.Encoding]::UTF8.GetByteCount($text)+[char]10+$text))"]]
function Core.process_output(output,framed)
  if type(output)~="string" then error("クリップボードを読み込めません。",0) end
  local code,body=output:match("^([%-]?%d+)\r?\n(.*)$")
  if tonumber(code)~=0 then error("クリップボード取得に失敗しました。もう一度コピーして貼り付けてください。",0) end
  if framed then
    local size,payload=body:match("^RN1 (%d+)\r?\n(.*)$")
    if not size or tonumber(size)~=#payload then error("クリップボードの読み込みが不完全です。件数を減らして貼り付けてください。",0) end
    body=payload
  end
  return body
end
function Core.clipboard()
  if type(R.CF_GetClipboard)=="function" then
    local ok,text=pcall(R.CF_GetClipboard,"")
    if ok and type(text)=="string" then return text,"SWS" end
  end
  local os=R.GetOS()
  if os:match("Win") then return Core.process_output(R.ExecProcess(Core.WINDOWS_COMMAND,5000),true),"Windows"
  elseif os:match("OSX") or os:match("macOS") then return Core.process_output(R.ExecProcess("/usr/bin/pbpaste",5000),false),"macOS" end
  error("この環境での貼り付けにはSWSのクリップボード機能が必要です。",0)
end

Core.scope={kind="all",query="",sort=nil,desc=false,exclude_loop=false}
function Core.require_api()
  for _,name in ipairs({"GetNumRegionsOrMarkers","GetRegionOrMarker","GetRegionOrMarkerInfo_Value",
    "SetRegionOrMarkerInfo_Value","GetSetRegionOrMarkerInfo_String","DeleteProjectMarkerByIndex"}) do
    if type(R[name])~="function" then error("選択・表示の連動にはREAPER 7.62以降が必要です。",0) end
  end
end
function Core.collect(project)
  local out={}
  for i=0,R.GetNumRegionsOrMarkers(project)-1 do
    local ptr=R.GetRegionOrMarker(project,i,"")
    if not ptr then error("マーカー／リージョンを取得できません。",0) end
    local function value(key) return R.GetRegionOrMarkerInfo_Value(project,ptr,key) end
    local ok,guid=R.GetSetRegionOrMarkerInfo_String(project,ptr,"GUID","",false)
    local named,name=R.GetSetRegionOrMarkerInfo_String(project,ptr,"P_NAME","",false)
    if not ok or not named or guid=="" then error("マーカー／リージョン情報の取得に失敗しました。",0) end
    local isrgn=value("B_ISREGION")~=0;local pos=value("D_STARTPOS");local ending=value("D_ENDPOS")
    out[#out+1]={index=i,guid=guid,isrgn=isrgn,pos=pos,ending=ending,before=name,id=value("I_NUMBER"),
      color=value("I_CUSTOMCOLOR"),length=isrgn and ending-pos or 0,selected=value("B_UISEL")~=0,
      hidden=value("B_HIDDEN")~=0,visible=value("B_VISIBLE")~=0}
  end
  return out
end
function Core.targets(items)
  local s=Core.scope;local out={};local query=s.query:lower()
  for _,v in ipairs(items) do
    local kind=s.kind=="all" or (s.kind=="region" and v.isrgn) or (s.kind=="marker" and not v.isrgn)
    local loop=s.exclude_loop and v.isrgn and v.before:sub(1,13):upper()=="[BLT:SUSTAIN]"
    if kind and not (s.exclude_loop and loop) and (query=="" or v.before:lower():find(query,1,true)) then out[#out+1]=v end
  end
  do
    local key=s.sort or "pos"
    local descending=s.sort~=nil and s.desc
    local function value(v)
      if key=="isrgn" then return v.isrgn and 1 or 0 end
      return v[key]
    end
    table.sort(out,function(a,b)
      local av,bv=value(a),value(b)
      if av==bv then return a.index<b.index end
      if descending then return av>bv end;return av<bv
    end)
  end
  return out
end
function Core.same(a,b)
  return a and b and a.guid==b.guid and a.id==b.id and a.isrgn==b.isrgn and a.pos==b.pos
    and a.ending==b.ending and a.before==b.before and a.color==b.color
end
function Core.content_matches(project,snapshot)
  for i,v in ipairs(snapshot) do
    local ptr=R.GetRegionOrMarker(project,i-1,"")
    if not ptr then return false end
    local ok,guid=R.GetSetRegionOrMarkerInfo_String(project,ptr,"GUID","",false)
    local named,name=R.GetSetRegionOrMarkerInfo_String(project,ptr,"P_NAME","",false)
    if not ok or not named or guid~=v.guid or name~=v.before
      or (R.GetRegionOrMarkerInfo_Value(project,ptr,"B_ISREGION")~=0)~=v.isrgn
      or R.GetRegionOrMarkerInfo_Value(project,ptr,"D_STARTPOS")~=v.pos
      or R.GetRegionOrMarkerInfo_Value(project,ptr,"D_ENDPOS")~=v.ending
      or R.GetRegionOrMarkerInfo_Value(project,ptr,"I_NUMBER")~=v.id
      or R.GetRegionOrMarkerInfo_Value(project,ptr,"I_CUSTOMCOLOR")~=v.color then return false end
  end
  return true
end
function Core.resolve(project,guid)
  local ptr=R.GetRegionOrMarker(project,-1,guid)
  if not ptr then error("対象が変更されました。一覧を確認してください。",0) end
  return ptr
end
function Core.set_name(project,v,name)
  local ptr=Core.resolve(project,v.guid)
  local ok=R.GetSetRegionOrMarkerInfo_String(project,ptr,"P_NAME",name,true)
  local read,current=R.GetSetRegionOrMarkerInfo_String(project,ptr,"P_NAME","",false)
  return ok and read and current==name
end
function Core.set_flag(project,guid,key,on)
  local ptr=Core.resolve(project,guid)
  R.SetRegionOrMarkerInfo_Value(project,ptr,key,on and 1 or 0)
  if (R.GetRegionOrMarkerInfo_Value(project,ptr,key)~=0)~=on then error("選択／表示状態を変更できませんでした。",0) end
end
function Core.select(project,wanted,defer_redraw)
  local changed={}
  local ok,err=xpcall(function()
    for i=0,R.GetNumRegionsOrMarkers(project)-1 do
      local ptr=R.GetRegionOrMarker(project,i,"")
      if not ptr then error("マーカー／リージョンを取得できません。",0) end
      local read,guid=R.GetSetRegionOrMarkerInfo_String(project,ptr,"GUID","",false)
      if not read or guid=="" then error("マーカー／リージョン情報の取得に失敗しました。",0) end
      local selected=R.GetRegionOrMarkerInfo_Value(project,ptr,"B_UISEL")~=0
      if selected~=(wanted[guid]==true) then
        changed[#changed+1]={guid=guid,selected=selected}
        Core.set_flag(project,guid,"B_UISEL",wanted[guid]==true)
      end
    end
  end,debug.traceback)
  if not ok then for _,v in ipairs(changed) do pcall(Core.set_flag,project,v.guid,"B_UISEL",v.selected) end end
  if #changed>0 then
    if defer_redraw then Core.selection_redraw=true
    else R.UpdateTimeline();R.UpdateArrange() end
  end
  if not ok then error(err,0) end
end
function Core.delete(project,items)
  if R.EnumProjects(-1,"")~=project then return nil,"プロジェクトが変わりました。" end
  local current={};for _,v in ipairs(Core.collect(project)) do current[v.guid]=v end
  local target={}
  for _,v in ipairs(items) do
    if not Core.same(v,current[v.guid]) or not current[v.guid].selected then return nil,"対象が変更されました。選択を確認してください。" end
    target[#target+1]=current[v.guid]
  end
  if #target==0 then return nil,"削除する行を選択してください。" end
  table.sort(target,function(a,b) return a.index>b.index end)
  R.Undo_BeginBlock2(project);R.PreventUIRefresh(1)
  local count=0
  local ok,err=xpcall(function()
    for _,v in ipairs(target) do
      local ptr=Core.resolve(project,v.guid)
      local index=R.GetRegionOrMarkerInfo_Value(project,ptr,"I_INDEX")
      if not R.DeleteProjectMarkerByIndex(project,index) then error("削除に失敗しました。",0) end
      count=count+1
      if R.GetRegionOrMarker(project,-1,v.guid) then error("削除結果を確認できません。",0) end
    end
  end,debug.traceback)
  R.PreventUIRefresh(-1);R.UpdateTimeline();R.UpdateArrange();R.Undo_EndBlock2(project,APP_NAME..": delete markers/regions",-1)
  if not ok then
    if count==0 then return nil,"削除できませんでした。一覧を確認してください。\n"..tostring(err) end
    R.Undo_DoUndo2(project)
    local restored={};for _,v in ipairs(Core.collect(project)) do restored[v.guid]=v end
    for _,v in ipairs(target) do
      if not Core.same(v,restored[v.guid]) then return nil,"削除を中止しましたが復元を確認できません。REAPERのUndo履歴を確認してください。" end
    end
    return nil,"削除を中止し、変更をUndoで復元しました。\n"..tostring(err)
  end
  return count
end
function Core.rename_rows(items,name_map)
  local rows,changes={},0
  for i,v in ipairs(items) do
    local name=name_map[v.guid]
    if name==nil then name=v.before end
    if #name>Core.MAX_NAME then error("名前は4096バイト以内にしてください。",0) end
    local changed=name~=v.before
    rows[i]={info=v,before=v.before,after=name,change=changed}
    if changed then changes=changes+1 end
  end
  return rows,changes
end

function Core.tsv_cell(value)
  local s=tostring(value)
  if s:find('[\t\r\n"]') or s=="" then return '"'..s:gsub('"','""')..'"' end
  return s
end
function Core.export(items,names_only)
  local lines={}
  if not names_only then lines[1]="種類\tID\t名前\t開始（秒）\t終了（秒）\t長さ（秒）\t色（RGB）" end
  for _,v in ipairs(items) do
    if names_only then lines[#lines+1]=Core.tsv_cell(v.before)
    else
      local color="標準"
      if v.color~=0 then local r,g,b=R.ColorFromNative(v.color);color=string.format("#%02X%02X%02X",r,g,b) end
      local fields={v.isrgn and "Region" or "Marker",string.format("%.0f",v.id),v.before,string.format("%.6f",v.pos),
        v.isrgn and string.format("%.6f",v.ending) or "",v.isrgn and string.format("%.6f",v.length) or "",color}
      for i,f in ipairs(fields) do fields[i]=Core.tsv_cell(f) end
      lines[#lines+1]=table.concat(fields,"\t")
    end
  end
  return table.concat(lines,"\r\n")..(#lines>0 and "\r\n" or "")
end
function Core.write_clipboard(text)
  if #text>Core.MAX_BYTES then error("コピーは16 MiB以内にしてください。対象を絞り込んでください。",0) end
  if type(R.CF_SetClipboard)=="function" then
    R.CF_SetClipboard(text)
    if type(R.CF_GetClipboard)=="function" and Core.text(R.CF_GetClipboard(""))~=Core.text(text) then
      error("クリップボードへの書き込みを確認できませんでした。もう一度コピーしてください。",0)
    end
    return
  end
  if not R.GetOS():match("Win") then error("情報のコピーにはSWSのクリップボード機能が必要です。",0) end
  local path=os.tmpname()
  local ok,err=xpcall(function()
    local f,msg=io.open(path,"wb");if not f then error(msg,0) end
    local written,why=f:write(text);local closed,close_err=f:close()
    if not written or not closed then error(why or close_err or "一時ファイルの作成に失敗しました。",0) end
    local quoted=path:gsub("'","''")
    if quoted:find('["\r\n]') then error("一時ファイルのパスが無効です。",0) end
    local command=[[powershell.exe -NoLogo -NoProfile -NonInteractive -STA -WindowStyle Hidden -Command "$ErrorActionPreference='Stop'; $t=[IO.File]::ReadAllText(']]..quoted..[[',[Text.Encoding]::UTF8); Set-Clipboard -Value $t; if ((Get-Clipboard -Raw) -cne $t) { throw 'Clipboard verification failed' }"]]
    Core.process_output(R.ExecProcess(command,5000),false)
  end,debug.traceback)
  local removed=os.remove(path)
  if not removed then
    local check=io.open(path,'rb')
    if check then
      check:close()
      if ok then error('クリップボード用一時ファイルを削除できませんでした。',0) end
    end
  end
  if not ok then error(err,0) end
end

function Core.preflight(project,items)
  if R.EnumProjects(-1,"")~=project then return nil,"プロジェクトが変わりました。対応関係を確認してください。" end
  local current=Core.targets(Core.collect(project),project)
  if #current~=#items then return nil,"対象が変わりました。対応関係を確認してください。" end
  for i,v in ipairs(items) do
    if not Core.same(v,current[i]) then return nil,"マーカー／リージョンが変更されました。対応関係を確認してください。" end
  end
  return true
end
function Core.apply(project,items,rows)
  local ok,err=Core.preflight(project,items); if not ok then return nil,err end
  local changes={}; for _,row in ipairs(rows) do if row.change then changes[#changes+1]=row end end
  if #changes==0 then return nil,"変更予定がありません。" end
  local touched={}
  R.Undo_BeginBlock2(project); R.PreventUIRefresh(1)
  local success,detail=xpcall(function()
    for _,row in ipairs(changes) do
      touched[#touched+1]=row
      local set=Core.set_name(project,row.info,row.after)
      if not set then error(string.format("名前の設定結果を確認できません（%s ID %.0f）。",row.info.isrgn and "リージョン" or "マーカー",row.info.id),0) end
    end
  end,debug.traceback)
  local restored=true
  if not success then
    for i=#touched,1,-1 do
      local row=touched[i]
      local call,result=pcall(function()
        return Core.set_name(project,row.info,row.before)
      end)
      if not call or not result then restored=false end
    end
  end
  R.PreventUIRefresh(-1); R.UpdateArrange()
  R.Undo_EndBlock2(project,success and APP_NAME..": marker and region names" or APP_NAME..": restored after failure",8)
  if not success then
    R.ShowConsoleMsg(APP_NAME..":\n"..BLT.publicError(detail).."\n")
    return nil,restored and "変更に失敗したため、元の名前に戻しました。" or "復元に失敗した項目があります。REAPERのUndoで戻してください。"
  end
  return #changes
end
local LIST_ROWS=21
local SECTION="BLT_MARKER_REGION_DESK"
Core.scope.exclude_loop=R.GetExtState(SECTION,"exclude_loop")~="0"

local S={seek=R.GetExtState(SECTION,"seek")=="1",move=R.GetExtState(SECTION,"move")=="1"}
local A={project=R.EnumProjects(-1,""),items={},rows={},
  offset=0,focus=nil,pressed=nil,flashes={},selected={},anchor_guid=nil,focus_guid=nil}
local function report_error(text)
  A.blt_status=BLT.publicError(text);A.blt_bad=true;BLT.host.wake()
end
local function persist()
  BLT.store(SECTION,"seek",S.seek and "1" or "0",true);BLT.store(SECTION,"move",S.move and "1" or "0",true)
end
local function rebuild_selection()
  A.focus=nil;A.selected={};A.selected_count=0
  for _,v in ipairs(A.snapshot or {}) do if v.selected then A.selected[v.guid]=true end end
  for i,v in ipairs(A.items) do
    if v.guid==A.focus_guid then A.focus=i end
    if v.selected then A.selected_count=A.selected_count+1 end
  end
end
local function rebuild()
  local previous
  local rows={}
  for i,v in ipairs(A.items) do
    local row=A.rows[i]
    if not row or row.info.guid~=v.guid then
      if not previous then previous={};for _,old in ipairs(A.rows) do previous[old.info.guid]=old end end
      row=previous[v.guid] or {}
    end
    local old=row.info
    if not old or old.before~=v.before or old.id~=v.id or old.pos~=v.pos or old.ending~=v.ending or old.isrgn~=v.isrgn then row.text=nil end
    row.info=v;rows[i]=row
  end
  A.rows=rows
  rebuild_selection()
  local s=Core.scope;A.scope_state={s.kind,s.query,s.sort,s.desc,s.exclude_loop}
end
local function refresh(project,snapshot)
  A.project=project or R.EnumProjects(-1,"");A.snapshot=snapshot or Core.collect(A.project);A.items=Core.targets(A.snapshot)
  A.revision=R.GetProjectStateChangeCount(A.project)
  A.offset=0;A.focus=nil;A.generation=(A.generation or 0)+1
  rebuild()
end
local function scope_change(key,value)
  Core.scope[key]=value
  refresh()
end

local function follow_selection(guid)
  if not guid then return end
  for i,v in ipairs(A.items) do if v.guid==guid then
    A.focus_guid=v.guid;A.focus=i
    if i<=A.offset or i>A.offset+LIST_ROWS then A.offset=max(0,i-1) end
    return
  end end
end
local function sync_selection()
  local project=R.EnumProjects(-1,"")
  local current=Core.collect(project)
  local s=Core.scope;local previous=A.scope_state or {}
  local changed=project~=A.project or #current~=#(A.snapshot or {})
    or s.kind~=previous[1] or s.query~=previous[2] or s.sort~=previous[3]
    or s.desc~=previous[4] or s.exclude_loop~=previous[5]
  local state_changed=false;local newly_selected=nil
  for i,v in ipairs(current) do
    local old=A.snapshot and A.snapshot[i]
    if not Core.same(v,old) then changed=true end
    if not old or v.guid~=old.guid or old.selected~=v.selected or old.hidden~=v.hidden or old.visible~=v.visible then state_changed=true end
    if v.selected and (not old or old.guid~=v.guid or not old.selected) then newly_selected=newly_selected or v.guid end
  end
  if changed then
    if project~=A.project then A.anchor_guid=nil;A.focus_guid=nil end
    refresh(project,current)
  elseif state_changed then
    local by_guid={};for _,v in ipairs(current) do by_guid[v.guid]=v end
    for i,v in ipairs(A.items) do A.items[i]=by_guid[v.guid] end
    A.snapshot=current;rebuild()
  end
  follow_selection(newly_selected)
  return changed or state_changed
end
-- Between full content checks, read only UI flags. Reacquire each handle so no
-- native marker pointer survives deletion, insertion or project switching.
local function poll_selection(now)
  local project=R.EnumProjects(-1,"")
  local revision=R.GetProjectStateChangeCount(project)
  if project~=A.project or revision~=A.revision
    or R.GetNumRegionsOrMarkers(project)~=#A.snapshot then
    local changed=sync_selection()
    A.revision=revision;A.content_poll=now+.12;A.content_deferred=false
    return changed
  end
  local changed,newly_selected=false,nil
  for i,v in ipairs(A.snapshot) do
    local ptr=R.GetRegionOrMarker(project,i-1,"")
    if not ptr then return sync_selection() end
    local selected=R.GetRegionOrMarkerInfo_Value(project,ptr,"B_UISEL")~=0
    local hidden=R.GetRegionOrMarkerInfo_Value(project,ptr,"B_HIDDEN")~=0
    local visible=R.GetRegionOrMarkerInfo_Value(project,ptr,"B_VISIBLE")~=0
    if selected and not v.selected then newly_selected=newly_selected or v.guid end
    if selected~=v.selected or hidden~=v.hidden or visible~=v.visible then changed=true end
    v.selected=selected;v.hidden=hidden;v.visible=visible
  end
  if changed then
    rebuild_selection()
    follow_selection(newly_selected)
  end
  -- Give selection one priority frame, but do not starve content/sort updates
  -- when UI flags keep changing during a drag or another script's operation.
  if now>=(A.content_poll or 0) then
    if changed and not A.content_deferred then
      A.content_deferred=true
    else
      A.content_poll=now+.12;A.content_deferred=false
      if not Core.content_matches(project,A.snapshot) then return sync_selection() or changed end
    end
  end
  return changed
end
local function select_row(guid,mods,no_navigation)
  poll_selection(R.time_precise())
  local index=nil;for i,v in ipairs(A.items) do if v.guid==guid then index=i;break end end
  if not index then return end
  local ctrl=(mods&4)~=0;local shift=(mods&8)~=0;local wanted={}
  if ctrl then for k,v in pairs(A.selected) do wanted[k]=v end end
  if shift then
    local anchor=index;for i,v in ipairs(A.items) do if v.guid==A.anchor_guid then anchor=i end end
    for i=min(anchor,index),max(anchor,index) do wanted[A.items[i].guid]=true end
  elseif ctrl then wanted[guid]=not wanted[guid];A.anchor_guid=guid
  else wanted[guid]=true;A.anchor_guid=guid end
  Core.select(A.project,wanted,true);A.focus_guid=guid
  poll_selection(R.time_precise())
  if not no_navigation and (S.move or S.seek) then
    for _,v in ipairs(A.items) do if v.selected then
      R.SetEditCurPos2(A.project,v.pos,S.move,S.seek)
      if S.seek and (R.GetPlayStateEx(A.project)&1)==0 then R.OnPlayButtonEx(A.project) end
      break
    end end
  end
end
local function select_all_rows()
  sync_selection()
  if #A.items==0 then return end
  A.anchor_guid=A.items[1].guid
  select_row(A.items[#A.items].guid,8)
end
local function clear_row_selection()
  sync_selection()
  Core.select(A.project,{})
  A.anchor_guid=nil;A.focus_guid=nil;A.focus=nil
  sync_selection()
end
local function toggle_visibility(guid)
  sync_selection()
  local target=nil;for _,v in ipairs(A.items) do if v.guid==guid then target=v;break end end
  if not target then return end
  R.Undo_BeginBlock2(A.project)
  local ok,err=pcall(Core.set_flag,A.project,guid,"B_HIDDEN",target.visible)
  R.UpdateTimeline();R.UpdateArrange();R.Undo_EndBlock2(A.project,APP_NAME..": visibility",-1)
  sync_selection()
  if not ok then report_error(tostring(err));return end
  local ptr=Core.resolve(A.project,guid)
  if not target.visible and R.GetRegionOrMarkerInfo_Value(A.project,ptr,"B_VISIBLE")==0 then
    report_error("個別の非表示は解除しました。レーンやREAPERの表示設定も確認してください。")
  end
end
local function delete_selected()
  sync_selection();local items={}
  for _,v in ipairs(A.items) do if v.selected then items[#items+1]=v end end
  if #items==0 then return end
  local n,err=Core.delete(A.project,items)
  refresh();if not n then report_error(err) end
end

local function undo_project()
  local project=R.EnumProjects(-1,"")
  local entry=R.Undo_CanUndo2(project)
  if not entry or entry=="" then return end
  local ok=R.Undo_DoUndo2(project)
  if not ok or ok==0 then report_error("Undoを実行できませんでした。");return end
  refresh()
end
local function sort_column(key)
  sync_selection()
  local s=Core.scope
  if s.sort~=key then s.sort=key;s.desc=false
  elseif not s.desc then s.desc=true
  else s.sort=nil;s.desc=false end
  A.items=Core.targets(A.snapshot);A.offset=0;A.generation=(A.generation or 0)+1;rebuild()
  A.column_flash={key=key,time=R.time_precise()}
end
local function copy_information(names_only,selected_only)
  sync_selection()
  local items={}
  for _,v in ipairs(A.items) do if not selected_only or v.selected then items[#items+1]=v end end
  if #items==0 then return end
  Core.write_clipboard(Core.export(items,names_only))
  A.flashes[names_only and "copy_names" or "copy_info"]=R.time_precise()

end

local function paste_names(selected_only)
  sync_selection()
  local items=A.items;local project=A.project;local selected={}
  for _,v in ipairs(items) do if not selected_only or v.selected then selected[#selected+1]=v end end
  if #selected==0 then return end
  local text=Core.clipboard();local names=Core.parse(text)
  local map={};for i,v in ipairs(selected) do map[v.guid]=names[i] end
  local rows,changes=Core.rename_rows(items,map)
  if selected_only then
    local selected_now={}
    for _,v in ipairs(Core.collect(project)) do if v.selected then selected_now[v.guid]=true end end
    for _,v in ipairs(items) do
      if v.selected~=(selected_now[v.guid]==true) then report_error("選択が変わりました。対象を確認して貼り付け直してください。");return end
    end
  end
  local n,err=0,nil
  if changes>0 then n,err=Core.apply(project,items,rows) end
  refresh()
  if not n then report_error(err) end
end
local function paste_selected() paste_names(true) end
local function guarded(fn)
  local ok,err=xpcall(fn,debug.traceback)
  if not ok then report_error(err); BLT.recoverInput(A,err) end
end

-- Shared BLT app restoration protocol. Each app owns one registry ID.
local BLTRestore={section='BLT_APP_RESTORE',id='BLT_MARKER_REGION_DESK'}
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

local apiOK,apiError=pcall(Core.require_api)
if not apiOK then Language.mb(BLT.publicError(apiError),APP_NAME,0);return end
if not R.ImGui_GetBuiltinPath or not R.JS_LICE_CreateBitmap then
 Language.mb('ReaImGui 0.10以降と js_ReaScriptAPI が必要です。ReaPackで導入・更新してください。',APP_NAME,0)
 return
end
local BASE_W,BASE_H=540,962
local ok,Host=pcall(BLT.CanvasHost.new,R,APP_NAME,BASE_W,BASE_H+26,SECTION)
if not ok then Language.mb(BLT.publicError(Host),APP_NAME,0);return end
Host.minWidth,Host.minHeight,Host.persistSize=486,500,true
local savedW,savedH=tonumber(R.GetExtState(SECTION,'window_w')),tonumber(R.GetExtState(SECTION,'window_h'))
Host.width=finite(savedW) and clamp(savedW,486,1600) or BASE_W
Host.height=finite(savedH) and clamp(savedH,500,1426) or BASE_H+26
local I,ctx,g=Host.I,Host.ctx,Host.g
local C={bg={.018,.030,.055},bg2={.030,.090,.180},panel={.040,.068,.110},panel2={.055,.125,.205},
 field={.018,.040,.080},edge={.145,.285,.445},edge2={.360,.650,.900},text={.955,.980,1},
 muted={.690,.780,.875},faint={.390,.505,.635},disabled={.43,.46,.51},accent={.120,.490,.980},
 accent2={.650,.895,1},accent3={.045,.235,.520},ice={.650,.895,1},focus={.225,.610,1},
 focus2={.690,.900,1},ink={.018,.075,.160},hover={.430,.790,1},warn={1,.755,.490},red={1,.18,.26}}
local U=BLT.Controls.new(g,R.time_precise,C)
U.font,U.minFontSize=Host.faces[1],7
local awakeUntil=R.time_precise()+6.5
local displayDirty=true
local function wake() awakeUntil=R.time_precise()+6.5 end
BLT.host={wake=wake}
local shell,menu,list
local W,H,scale,ox,oy,mx,my=BASE_W,BASE_H,1,0,4,-1,-1
local density=BLT.Controls.compactScale
local T={x=24,y=180,w=492,h=704,row=32,header=32,bar=14}
local renameTarget,contextGUID,contextOpen,scrollDrag,rowPress,rightPress
local function visible() return floor((T.h-T.header)/T.row) end
local function max_offset() return max(0,#A.rows-visible()) end
local function inside(x,y,w,h) return mx>=x and mx<x+w and my>=y and my<y+h end
local function valid_text(value,limit)
 return type(value)=='string' and #value<=limit and utf8.len(value)~=nil and not value:find('[%z\1-\8\11\12\14-\31\127]')
end
local function applyQuery(value)
 if not valid_text(value,1024) then
  U:flash('query');report_error('検索文字列が長すぎるか、使用できない制御文字があります。');return false
 end
 if value~=Core.scope.query then scope_change('query',value);wake() end
 return true
end
local function applyRename(value)
 local target=renameTarget;renameTarget=nil
 if not target or value==target.before then return true end
 if not valid_text(value,Core.MAX_NAME) then
  U:flash('rename');A.name_flash=target.guid
  report_error('名前が長すぎるか、使用できない制御文字があります。');return false
 end
 local rows,changes=Core.rename_rows(target.items,{[target.guid]=value})
 if changes>0 then
  local n,err=Core.apply(target.project,target.items,rows)
  if not n then report_error(err);sync_selection();return false end
 end
 local offset=A.offset;sync_selection();A.offset=clamp(offset,0,max_offset());wake()
 return true
end
local function pending()
 local state=U.states.query
 if state and state.pending~=nil then local value=state.pending;state.pending=nil;applyQuery(value) end
 state=U.states.rename
 if state and state.pending~=nil then local value=state.pending;state.pending=nil;applyRename(value) end
end
local function commit()
 if U.editor and U.editor.edit then U.editor:close(false) end
 pending();return true
end
local function cancelEdit()
 U.editor:close(true);renameTarget=nil;A.pending_rename=nil;U.capture=nil
end
local function scroll(delta)
 if renameTarget then commit() end
 A.offset=clamp(A.offset+delta,0,max_offset());wake()
end
local function open_rename(row)
 if not row then return end
 if (g.mouse_cap&1)~=0 then
  A.pending_rename={guid=row.info.guid,project=A.project,x=g.mouse_x,y=g.mouse_y}
  A.last_row_click=nil;return
 end
 commit();local guid=row.info.guid;sync_selection()
 for _,v in ipairs(A.items) do if v.guid==guid then
  renameTarget={guid=guid,before=v.before,project=A.project,items=A.items}
  A.last_row_click=nil;U.focus=nil;U.editor:open('rename',v.before,applyRename);wake();return
 end end
end
local popupLayout={width=292,rowHeight=29,headerHeight=36,visiblePresets=8,hoverDelay=1}
menu=BLT.PresetMenu.new(Host,U,{presets=Presets,language=Language,layout=popupLayout,commit=commit})
shell=BLT.Shell.new(Host,U,R,{
 title=NAME,subtitle='MARKER / REGION / LOOP LIST  マーカー・リージョン・ループのリスト',
 barTitle='M A R K E R   R E G I O N   D E S K',section=SECTION,persist=true,
 layout={iconY=31-38*.78,iconScale=.78,footerSize=8},
 language=Language.code,languageChanged=Language.set,translate=Language.message,store=BLT.store,
 headerIcon=BLT.MarkerDeskIcon,iconMode=function() return 'list' end,
 stepPreset=function(direction) commit();Presets.step(direction) end,
 drawPresets=function(owner) menu:draw(owner) end,presetSize=function() return menu:size() end,dirty=Presets.dirty})
U.editor=BLT.TextInput.new(Host,U,shell.typography)
list=BLT.MarkerDeskList.new(Host,R,shell.typography,Language,C)
BLT.attachPresets({R=R,section=SECTION,wake=wake,
 defaults={seek=false,move=false,kind='all',query='',exclude_loop=true},
 capture=function()
  local v=BLT.scopeView or {};BLT.scopeView=v
  v.seek,v.move,v.kind,v.query,v.exclude_loop=S.seek,S.move,Core.scope.kind,Core.scope.query,Core.scope.exclude_loop
  return v
 end,
 valid=function(v) return (v.kind=='all' or v.kind=='marker' or v.kind=='region') and valid_text(v.query,1024) end,
 apply=function(v)
  S.seek,S.move=v.seek,v.move;Core.scope.kind,Core.scope.query,Core.scope.exclude_loop=v.kind,v.query,v.exclude_loop
  persist();BLT.store(SECTION,'exclude_loop',v.exclude_loop and '1' or '0',true);refresh()
 end,busy=function() return false end,commit=commit,cancelEdit=cancelEdit})
BLT.recoverInput=function(_,err)
 cancelEdit();U.down=false;scrollDrag,rowPress,rightPress=nil,nil,nil;wake();BLT.logError(err)
end
local function update_row_time(row)
 local v=row.info;local first=R.format_timestr_pos(v.pos,'',-1)
 local last=v.isrgn and R.format_timestr_pos(v.ending,'',-1) or '—'
 local text=row.text
 if not text then
  row.text={string.format('%.0f',v.id),first,last,v.before=='' and '〈空欄〉' or v.before:gsub('[\r\n\t]',' ')}
  return true
 end
 if text[2]==first and text[3]==last then return false end
 text[2],text[3]=first,last;return true
end
local function poll_time_display(now)
 if now<(A.time_display_poll or 0) then return false end
 A.time_display_poll=now+.12
 if R.EnumProjects(-1,'')~=A.project then return false end
 local changed=false
 for index=A.offset+1,min(#A.rows,A.offset+visible()) do if update_row_time(A.rows[index]) then changed=true end end
 return changed
end
local segmentOptions={led='top',ledScale=28/(44*density),size=14/density,bold=true}
local switchOptions={background=false,showState=false,switchScale=30/(44*density),size=14/density,bold=true}
local smallOptions={size=14/density,bold=true}
local scrollOptions={size=13/density}
local clearOptions={variant='clear',size=14/density,bold=true}
local queryOptions={size=13/density}
local function button(id,text,x,y,w,h,enabled,action,options)
 options=options or smallOptions;options.enabled=enabled~=false
 local stamp=A.flashes[id];local flash=stamp and U.now-stamp<.65
 if flash and (id=='copy_names' or id=='copy_info') then text='コピーしました' end
 if U:button(id,Language.text(text),x/density,y/density,w/density,h/density,options) then
  commit();guarded(action);wake()
 end
end
local function toggle(id,text,x,y,w,on,action)
 local value,clicked=U:toggle(id,Language.text(text),on,x/density,y/density,w/density,30/density,true,switchOptions)
 if clicked and value~=on then commit();guarded(action);wake() end
end
local function drawContext()
 I.PushStyleColor(ctx,I.Col_PopupBg,Host.rgba(C.panel[1],C.panel[2],C.panel[3],1))
 I.PushStyleColor(ctx,I.Col_Text,Host.rgba(C.text[1],C.text[2],C.text[3],1))
 local shown=I.BeginPopup(ctx,'BLT_MARKER_ROW_CONTEXT')
 contextOpen=shown
 if not shown then I.PopStyleColor(ctx,2);contextGUID=nil;return end
 I.PushFont(ctx,Host.font,13)
 for i,text in ipairs({'コピー','一覧情報をコピー','名前を貼り付け'}) do
  if I.Selectable(ctx,Language.text(text),false,0,180,25) then
   guarded(function()
    sync_selection()
    local target
    for _,v in ipairs(A.items) do if v.guid==contextGUID then target=v;break end end
    if not target then return end
    if not target.selected then select_row(target.guid,0,true) end
    if i==1 then copy_information(true,true) elseif i==2 then copy_information(false,true) else paste_selected() end
   end);wake()
  end
 end
 I.PopFont(ctx);I.EndPopup(ctx);I.PopStyleColor(ctx,2)
end
local function releaseRename()
 local p=A.pending_rename;if not p then return end
 if R.EnumProjects(-1,'')~=p.project or math.abs(g.mouse_x-p.x)>6 or math.abs(g.mouse_y-p.y)>6 then A.pending_rename=nil;return end
 if U.down then return end
 A.pending_rename=nil
 for _,row in ipairs(A.rows) do if row.info.guid==p.guid then open_rename(row);return end end
end
local function tableInput(cols,widths)
 if max_offset()>0 then g.wheelRegion(ox+T.x*scale,oy+T.y*scale,T.w*scale,T.h*scale)end
 if U.blocked or U.editor.edit then rowPress,rightPress,scrollDrag=nil,nil,nil;return end
 local inTable=inside(T.x,T.y,T.w,T.h)
 local rowIndex=inTable and my>=T.y+T.header and my<T.y+T.header+visible()*T.row and A.offset+floor((my-T.y-T.header)/T.row)+1 or nil
 local row=rowIndex and A.rows[rowIndex]
 local bar=A.scrollbar
 if U.pressed and inTable then
  U.hit=true;U.focus=nil
  if bar and inside(bar.x,bar.y,bar.w,bar.h) then
   if my>=bar.thumb_y and my<bar.thumb_y+bar.thumb_h then scrollDrag=my-bar.thumb_y
   else scroll(my<bar.thumb_y and -visible() or visible()) end
  elseif my<T.y+T.header then
   for i,key in ipairs(BLT.MarkerDeskList.keys) do if inside(cols[i]-2,T.y,widths[i]+2,T.header) then
    rowPress={sort=key,generation=A.generation};break
   end end
  elseif row then
   local v=row.info;local mods=g.mouse_cap&28
   if Host.mac and (g.mouse_cap&32)~=0 then mods=mods|4 end
   if mx<T.x+30 then rowPress={guid=v.guid,visible=true,generation=A.generation}
   else
    local double=A.last_row_guid==v.guid and A.last_row_click and U.now-A.last_row_click<.4
    local nameClick=A.selected[v.guid] and mx>=cols[5] and mx<cols[5]+widths[5]
    if mods==0 and (double or nameClick) then open_rename(row)
    else guarded(function() select_row(v.guid,mods) end);A.last_row_click=U.now;A.last_row_guid=v.guid end
   end
  else guarded(clear_row_selection) end
  wake()
 elseif U.down and scrollDrag and bar then
  local travel=bar.h-bar.thumb_h
  if travel>0 then A.offset=floor(clamp((my-bar.y-scrollDrag)/travel,0,1)*max_offset()+.5) end
  wake()
 elseif U.released then
  if rowPress and rowPress.generation==A.generation then
   local captured=rowPress
   if captured.sort then
    for i,key in ipairs(BLT.MarkerDeskList.keys) do if key==captured.sort and inside(cols[i]-2,T.y,widths[i]+2,T.header) then guarded(function() sort_column(key) end) end end
   elseif captured.visible and row and row.info.guid==captured.guid and mx<T.x+30 then guarded(function() toggle_visibility(captured.guid) end) end
  end
  rowPress,scrollDrag=nil,nil
 end
 local right=I.IsMouseDown(ctx,1)
 if right and not A.right_down and inTable then rightPress=row and row.info.guid or nil end
 if not right and A.right_down then
  if rightPress and row and row.info.guid==rightPress then
   contextGUID=rightPress;guarded(function() if not row.info.selected then select_row(contextGUID,0,true) end end)
   I.OpenPopup(ctx,'BLT_MARKER_ROW_CONTEXT');contextOpen=true;wake()
  end
  rightPress=nil
 end
 A.right_down=right
 if inTable and U.wheel~=0 then scroll((U.wheel>0 and -1 or 1)*((g.mouse_cap&8)~=0 and visible() or 3));U.wheel=0 end
end
local function drawTable()
 A.offset=clamp(A.offset,0,max_offset())
 if renameTarget then
  local found
  for index,row in ipairs(A.rows) do if row.info.guid==renameTarget.guid then found=index;break end end
  if not found then cancelEdit()
  elseif found<=A.offset or found>A.offset+visible() then commit() end
 end
 for index=A.offset+1,min(#A.rows,A.offset+visible()) do if not A.rows[index].text then update_row_time(A.rows[index]) end end
 local flashState=U.states.rename
 if A.name_flash and not (flashState and (flashState.flash or flashState.flashPending)) then A.name_flash=nil end
 local editGUID=renameTarget and renameTarget.guid or A.name_flash
 list:prepare(A,T,W,scale,Core.scope.sort,Core.scope.desc,renameTarget~=nil)
 local cols,widths=list.cols,list.widths
 local bx,by,bh=T.x+T.w-T.bar,T.y+T.header,T.h-T.header
 local thumb=#A.rows>0 and max(26,bh*min(1,visible()/#A.rows)) or bh
 A.scrollbar={x=bx,y=by,w=T.bar,h=bh,thumb_y=by+(max_offset()>0 and A.offset/max_offset()*(bh-thumb) or 0),thumb_h=thumb}
 local oldRows,oldOffset=A.rows,A.offset
 tableInput(cols,widths)
 if A.rows~=oldRows or A.offset~=oldOffset then
  for index=A.offset+1,min(#A.rows,A.offset+visible()) do if not A.rows[index].text then update_row_time(A.rows[index]) end end
 end
 editGUID=renameTarget and renameTarget.guid or A.name_flash
 if A.rows~=oldRows or A.offset~=oldOffset then list:prepare(A,T,W,scale,Core.scope.sort,Core.scope.desc,renameTarget~=nil) end
 list:draw(ox+T.x*scale,oy+T.y*scale)
 U:rect(bx/density,by/density,T.bar/density,bh/density,C.panel,.95)
 thumb=#A.rows>0 and max(26,bh*min(1,visible()/#A.rows)) or bh
 local ty=by+(max_offset()>0 and A.offset/max_offset()*(bh-thumb) or 0)
 U:rect((bx+4)/density,(ty+1)/density,(T.bar-8)/density,(thumb-2)/density,C.muted,.62)
 local flash=A.column_flash
 if flash then
  local alpha=max(0,1-(U.now-flash.time)/.55)
  if alpha==0 then A.column_flash=nil else
   for i,key in ipairs(BLT.MarkerDeskList.keys) do if key==flash.key then
    U:rect((cols[i]-2)/density,T.y/density,(widths[i]+2)/density,T.h/density,C.ice,.12*alpha)
   end end
  end
 end
 if editGUID then
  for index=A.offset+1,min(#A.rows,A.offset+visible()) do if A.rows[index].info.guid==editGUID then
   local y=T.y+T.header+(index-A.offset-1)*T.row
   U:fieldFrame('rename',(cols[5]-4)/density,(y+1)/density,(widths[5]-4)/density,(T.row-2)/density,true,renameTarget~=nil)
   local bounds={x=ox+cols[5]*scale,y=oy+y*scale,w=(widths[5]-8)*scale,h=T.row*scale,size=18*scale,
    hit={x=ox+(cols[5]-4)*scale,y=oy+y*scale,w=(widths[5]-4)*scale,h=T.row*scale}}
   U.editor:queue('rename',A.rows[index].info.before,bounds,true)
   break
  end end
 end
end
local function keypress(key)
 if U.editor.edit or shell.popupOpen or contextOpen then return end
 local cap=g.mouse_cap
 if (cap&24)==0 and (key==26 or (cap&36)~=0 and (key==90 or key==122)) then guarded(undo_project);wake();return end
 if key==27 then A.manualClose=true;A.closing=true
 elseif key==1 then guarded(select_all_rows)
 elseif key==6579564 then guarded(delete_selected)
 elseif key==3 then guarded(function() copy_information(true,true) end)
 elseif key==22 then guarded(paste_selected)
 elseif key==13 and A.focus and not U.focus then open_rename(A.rows[A.focus])
 elseif key==1752132965 then A.offset=0
 elseif key==6647396 then A.offset=max_offset()
 elseif key==1885828464 then scroll(-visible())
 elseif key==1885824110 then scroll(visible())
 elseif key==30064 then scroll(-1)
 elseif key==1685026670 then scroll(1) end
 if key~=0 then wake() end
end
local scopes={{'all','すべて'},{'marker','マーカー'},{'region','リージョン'}}
local function draw()
 shell:begin();U.themeEnabled=shell.theme.enabled
 scale=max(.30,min(g.w/BASE_W,1));H=max(1,g.h-26)/scale;W=g.w/scale
 ox,oy=0,26-22*scale;mx,my=(g.mouse_x-ox)/scale,(g.mouse_y-oy)/scale
 T.w,T.h=W-48,max(T.header+T.row,H-258);LIST_ROWS=visible()
 g.set(C.bg[1],C.bg[2],C.bg[3],1);g.rect(0,0,g.w,g.h,1)
 U.scale,U.ox,U.oy=scale,ox,oy+22*scale
 shell:header(W)
 local key=g.getchar();local editing=U.editor.edit~=nil
 U:begin(density*scale,ox,oy,key);U.blocked=U.blocked or contextOpen
 releaseRename();keypress(key)
 if editing then U.key=0 end
 local scope=Core.scope
 for i,v in ipairs(scopes) do
  segmentOptions.selected=scope.kind==v[1]
  button('scope_'..v[1],v[2],24+(i-1)*90,102,84,28,true,function() scope_change('kind',v[1]) end,segmentOptions)
 end
 toggle('exclude_loop','ループリージョンを除外',302,102,212,scope.exclude_loop,function()
  scope_change('exclude_loop',not Core.scope.exclude_loop)
  BLT.store(SECTION,'exclude_loop',Core.scope.exclude_loop and '1' or '0',true)
 end)
 local query=U:field('query',scope.query,24/density,140/density,(W-144)/density,30/density,queryOptions)
 if query~=scope.query then applyQuery(query) end
 if scope.query=='' and not (U.editor.edit and U.editor.edit.id=='query') then
  U:text(Language.text('文字列でフィルター…'),(24+12*density)/density,140/density,(W-144-24*density)/density,30/density,13/density,C.faint,false)
 end
 local clearable=scope.kind~='all' or scope.query~=''
 button('reset','クリア',W-108,140,84,30,clearable,function()
  Core.scope.kind,Core.scope.query='all','';refresh();A.flashes.reset=U.now
 end,clearOptions)
 drawTable()
 toggle('seek','シーク再生',24,H-72,138,S.seek,function() S.seek=not S.seek;persist() end)
 toggle('move','選択位置へ移動',172,H-72,176,S.move,function() S.move=not S.move;persist() end)
 button('top','↑ 先頭',W-180,H-72,72,30,#A.rows>0,function() A.offset=0 end,scrollOptions)
 button('bottom','↓ 末尾',W-96,H-72,72,30,#A.rows>0,function() A.offset=max_offset() end,scrollOptions)
 button('copy_names','全名前をコピー',24,H-32,142,30,#A.items>0,function() copy_information(true) end)
 button('copy_info','全情報をコピー',178,H-32,142,30,#A.items>0,function() copy_information(false) end)
 button('paste_all','名前を貼付（先頭から）',332,H-32,W-356,30,#A.items>0,function() paste_names(false) end)
 U:finish();pending()
 if renameTarget and not U.editor.edit then renameTarget=nil end
 if U.editor.edit and U.editor.edit.id=='query' then
  if not applyQuery(U.editor.edit.text) then U.editor:close(true) end
 elseif U.editor.edit and U.editor.edit.id=='rename' and not valid_text(U.editor.edit.text,Core.MAX_NAME) then
  local value=U.editor.edit.text;U.editor:close(true);applyRename(value)
 end
 U.scale,U.ox,U.oy=scale,ox,oy
 local message=A.blt_status or (#A.items==0 and 'マーカー／リージョンがありません。' or string.format('%d件  選択 %d件',#A.items,A.selected_count or 0))
 local bad=A.blt_bad
 if BLT.notice then message,bad=BLT.notice,BLT.noticeBad end
 shell:footer(message,bad,W,H+22,'0.6.5')
 shell:drawBar();drawContext()
 U.scale,U.ox,U.oy=density*scale,ox,oy
end
Host:bindShortcuts()
g.getchar=function(query)
 if query==65536 or query==65537 then return Host.focused and 6 or 4 end
 local key=Host.key
 if key>=97 and key<=122 then
  local primary=(g.mouse_cap&4)~=0 or Host.mac and (g.mouse_cap&32)~=0 and (key==97 or key==99 or key==118 or key==122)
  if primary then key=key-96 elseif (g.mouse_cap&8)~=0 then key=key-32 end
 end
 return key,0
end
BLTShortcuts.install(R,g,{
 blocked=function() return U.editor.edit~=nil or shell.popupOpen or contextOpen or A.closing end,
 localKey=function(key,cap)
  return key==27 or key==9 or key==1 or key==3 or key==22 or key==13 or key==6579564 or
   key==1752132965 or key==6647396 or key==1885828464 or key==1885824110 or key==30064 or key==1685026670 or
   ((cap&24)==0 and (key==26 or (cap&36)~=0 and (key==90 or key==122)))
 end,beforeGlobal=commit})
local finalized=false
local function close()
 if finalized then return end;finalized=true
 BLT.cleanup(commit);BLT.cleanup(persist)
 BLT.cleanup(BLTRestore.finish,R,A.manualClose or Host.requestClose)
 BLT.cleanup(list.close,list);BLT.cleanup(Host.close,Host);BLT.cleanup(shell.close,shell)
 A.closed=true
end
R.atexit(close)
if R.set_action_options then R.set_action_options(2) end
local restoreOK,restoreError=pcall(BLTRestore.start,R)
if not restoreOK then Language.mb('自動復元の登録に失敗しました。\n'..tostring(restoreError),APP_NAME,0) end
local inputState,worldState={},{}
local function changed(state,...)
 local different=false
 for i=1,select('#',...) do local value=select(i,...);if state[i]~=value then state[i]=value;different=true end end
 return different
end
local function poll(now)
 local previous=A.project
 local selectionChanged=poll_selection(now)
 if A.project~=previous and U.editor.edit then cancelEdit() end
 if selectionChanged then displayDirty=true end
 if poll_time_display(now) then displayDirty=true end
 if BLT.noticeUntil and now>=BLT.noticeUntil then BLT.notice,BLT.noticeUntil=nil,nil;displayDirty=true end
end
local function run()
 if finalized then return end
 local begun=false
 local success,err=xpcall(function()
  local now=R.time_precise();poll(now);shell.theme.tick(now)
  if changed(worldState,A.rows,A.offset,A.generation,A.selected_count,A.blt_status,Language.code,C.bg,
   Presets.current,BLT.noticeUntil,Host.requestReset,shell.icon.dirty) then displayDirty=true end
  local interactive=U.editor.edit or shell.popupOpen or contextOpen or Host.drag or shell.hoverID or U.capture or scrollDrag or A.pending_rename
  if not displayDirty and now>=awakeUntil and not interactive and not shell.icon:animating(now) and Host:idle(now) then U.now=now;shell.icon.lastTime=now;R.defer(run);return end
  if Host.idleWake then wake();Host.idleWake=nil end
  if Host.requestReset then Host.width,Host.height=BASE_W,BASE_H+26 end
  local shown=Host:begin();begun=true
  if shown then
   local cap=(Host.hovered or Host.focused or U.capture or Host.drag) and g.mouse_cap or 0
   if changed(inputState,g.mouse_x,g.mouse_y,cap,Host.key,g.w,g.h,Host.dpi,Host.originX,Host.originY,Host.focused) or
    g.mouse_wheel~=0 or (cap&1)~=0 or I.IsMouseDown(ctx,1) or interactive then wake() end
   draw();displayDirty=false
   if not Host.focused then awakeUntil=min(awakeUntil,now+.5) end
  end
  local keep=Host:finish();begun=false
  if Core.selection_redraw then Core.selection_redraw=nil;R.UpdateTimeline();R.UpdateArrange() end
  if not keep or A.closing then close() else R.defer(run) end
 end,debug.traceback)
 if not success then
  if begun then pcall(Host.finish,Host) end
  close();Language.mb(BLT.publicError(err),APP_NAME..' | エラー',0)
 end
end
guarded(refresh)
run()
