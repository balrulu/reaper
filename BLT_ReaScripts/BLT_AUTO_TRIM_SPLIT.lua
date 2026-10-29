-- @description AUTO TRIM / SPLIT
-- @version 0.6.6
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

BLT.AutoTrimIcon=(function()
local M={width=104,height=60,modes={'peak','lufs'}}
local sin,cos,pi=math.sin,math.cos,math.pi
local peak={3,5,4,9,5,24,6,4,19,5,8,4,5,3}
local loudness={5,7,9,11,13,15,16,15,14,12,10,8,6,5}
local function hash(n,salt) return (sin(n*12.9898+salt*78.233)*43758.5453)%1 end
function M.update(s,mode,dt)
 local target=mode=='lufs' and 1 or 0
 s.mix=s.mix and s.mix+(target-s.mix)*(1-math.exp(-dt*14)) or target
 if math.abs(s.mix-target)<.001 then s.mix=target end
 s.bars=s.bars or {}
 for i,value in ipairs(peak) do s.bars[i]=value*(1-s.mix)+loudness[i]*s.mix end
end
function M.draw(p,s,mode,time)
 local C=p.C
 for i=1,9 do
  local phase=time*(.16+(i%3)*.035)+i*1.73
  local x=52+sin(phase*1.37)*(15+5*s.mix)+cos(phase*.71+i)*5
  local y=34+cos(phase*.91)*8-(i%3)*2;local r=10+(i%4)*4
  p:disc(x,y,r+8,C.accent,.015)
  p:disc(x,y,r,C.accent,.011)
  p:disc(x+2,y-1,r*.55,C.ice,.011)
 end
 p:line(12,37,92,37,C.edge2,.28)
 p:bars(49.825,37,5.05,1.35,s.bars,C.muted,.76)
 p:line(29,23,79,23,C.accent,.025,7)
 p:line(29,23,79,23,C.ice,.55)
 for i=1,2 do
  local x=i==1 and 29 or 79
  p:line(x,20,x,53,C.accent,.035,6)
  p:line(x,20,x,53,C.ice,.94,2)
  p:disc(x,23,6.5,C.accent,.04)
  p:disc(x,23,1.5,C.text,.90)
 end
 local a=1-s.mix
 if a>.001 then
  p:line(52,8,52,28,C.ice,.78*a)
  p:line(47,20,52,11,C.ice,.58*a)
  p:line(52,11,57,20,C.ice,.58*a)
  p:disc(52,11,6.5,C.accent,.045*a)
  p:disc(52,11,2.2,C.text,.78*a)
 end
 if s.mix>.001 then
  p:rect(29,8,48,13,C.accent,.11*s.mix)
  p:line(32,8,74,8,C.ice,.55*s.mix)
  p:line(29,11,29,21,C.ice,.55*s.mix)
  p:line(77,8,77,18,C.ice,.55*s.mix)
  p:line(29,21,74,21,C.ice,.55*s.mix)
  p:rect(43,13,20,9,C.field,.78*s.mix)
  p:line(43,13,63,13,C.warn,.62*s.mix)
  p:line(43,22,63,22,C.warn,.62*s.mix)
  p:disc(43,17.5,1.3,C.warn,.62*s.mix)
  p:disc(63,17.5,1.3,C.warn,.62*s.mix)
 end
end
function M.emit(s,n,p)
 local a,b,c,d=hash(n,31),hash(n,32),hash(n,33),hash(n,34)
 p.x,p.y=32+a*(43+10*s.mix),49+(b-.5)*4
 p.vx,p.vy=(c-.5)*(7+3*s.mix),8+d*8
 p.sway,p.freq,p.phase=2.3,1.4,c*pi*2
 p.life,p.r,p.glint=1.8+b*1.2,.45+a*.55,n%6==0
end
return M
end)()

BLT.AutoTrimWave=(function()
local M={}
local min,max,floor,ceil=math.min,math.max,math.floor,math.ceil
local function clamp(n,a,b) return max(a,min(b,n)) end
local function packed(c)
 return 0xff000000|(floor(clamp(c[1],0,1)*255+.5)<<16)|(floor(clamp(c[2],0,1)*255+.5)<<8)|floor(clamp(c[3],0,1)*255+.5)
end
function M.new(host,api,Core,A,S,C)
 local V={signature={}}
 local bitmap,image,bw,bh
 local keys={'field','accent','accent2','quiet','warn','edge'}
 local function detach()
  if image then host:releaseImage(image);image=nil end
 end
 function V:clear()
  detach()
  if bitmap then api.JS_LICE_DestroyBitmap(bitmap);bitmap=nil end
  self.data=nil;A.wave_cache=nil
 end
 function V:draw(x,y,w,waveH,meterH,start,span,scale)
  local data=A.data;if not data then self:clear();return end
  local density=ceil(host.dpi or 1);local factor=scale*density
  local totalH=waveH+50
  local iw,ih=max(1,min(4096,floor(w*factor+.5))),max(1,min(1024,floor(totalH*factor+.5)))
  local dirty=A.wave_surface_dirty or not image or self.data~=data or self.start~=start or self.span~=span or self.basis~=S.basis or bw~=iw or bh~=ih
  local index=0
  for _,key in ipairs(keys) do
   for i=1,3 do
    index=index+1;local value=C[key][i]
    if self.signature[index]~=value then self.signature[index]=value;dirty=true end
   end
  end
  if dirty then
   if not bitmap then bitmap=assert(api.JS_LICE_CreateBitmap(true,iw,ih),'Waveform bitmap creation failed')
   elseif bw~=iw or bh~=ih then api.JS_LICE_Resize(bitmap,iw,ih) end
   bw,bh=iw,ih
   api.JS_LICE_Clear(bitmap,packed(C.field))
   local fx,fy=iw/w,ih/totalH
   local function line(x1,y1,x2,y2,c,a)
    api.JS_LICE_Line(bitmap,x1*fx,y1*fy,x2*fx,y2*fy,packed(c),a or 1,'COPY',true)
   end
   local function rect(xx,yy,ww,hh,c,a)
    api.JS_LICE_FillRect(bitmap,floor(xx*fx),floor(yy*fy),max(1,ceil(ww*fx)),max(1,ceil(hh*fy)),packed(c),a or 1,'COPY')
   end
   local cache=A.wave_cache
   if not cache or cache.data~=data or cache.start~=start or cache.span~=span or cache.basis~=S.basis or cache.width~=iw then
    cache={data=data,start=start,span=span,basis=S.basis,width=iw,peaks={},levels={},close_levels={}}
    for px=0,iw-1 do
     local a=start+px/iw*span;local b=start+(px+1)/iw*span
     local ia=max(1,floor(a*1000)+1);local ib=min(#data.peak,max(ia,ceil(b*1000)))
     local peak,level,closeLevel=0,-240,-240
     for i=ia,ib do
      peak=max(peak,data.peak[i] or 0)
      if S.basis=='lufs' then
       level=max(level,data.lufs[i] or -240);closeLevel=max(closeLevel,data.fast[i] or -240)
      else level=max(level,(data.peak[i] or 0)>1e-12 and 20*math.log(data.peak[i],10) or -240);closeLevel=level end
     end
     cache.peaks[px+1],cache.levels[px+1],cache.close_levels[px+1]=peak,level,closeLevel
    end
    A.wave_cache=cache
   end
   local function tx(t) return (t-start)/span*w end
   local meterTop=waveH+8;local plotBottom=meterTop+meterH
   for _,r in ipairs(A.regions) do
    if r[2]>start and r[1]<start+span then
     local left,right=tx(max(start,r[1])),tx(min(start+span,r[2]))
     rect(left,0,right-left,waveH,C.accent,.12)
     line(left,0,left,plotBottom,C.accent2,.28);line(right,0,right,plotBottom,C.accent2,.28)
     local duration=r[2]-r[1]
     local fi=S.fade_in_on and min(duration,S.fade_in/1000) or 0
     local fo=S.fade_out_on and min(duration,S.fade_out/1000) or 0
     if fi+fo>duration then local k=duration/(fi+fo);fi,fo=fi*k,fo*k end
     if fi>0 and r[1]>=start and r[1]+fi<=start+span then line(tx(r[1]),waveH,tx(r[1]+fi),0,C.accent2,.62) end
     if fo>0 and r[2]-fo>=start and r[2]<=start+span then line(tx(r[2]-fo),0,tx(r[2]),waveH,C.accent2,.62) end
    end
   end
   local center=waveH/2;local norm=max(data.max_peak,.000001)
   line(0,center,w,center,C.edge,.48)
   local previous,previousClose
   local region=1
   for px=0,iw-1 do
    local xx=px/fx;local middle=start+(px+.5)/iw*span
    while A.regions[region] and middle>=A.regions[region][2] do region=region+1 end
    local active=A.regions[region] and middle>=A.regions[region][1]
    local amp=min(1,cache.peaks[px+1]/norm)*(waveH/2-3)
    line(xx,center-amp,xx,center+amp,active and C.accent2 or C.quiet,.94)
    local ly=meterTop+meterH*(1-clamp((cache.levels[px+1]+90)/102,0,1))
    if previous then line((px-1)/fx,previous,xx,ly,C.accent,.88) end
    previous=ly
    if S.basis=='lufs' then
     local cy=meterTop+meterH*(1-clamp((cache.close_levels[px+1]+90)/102,0,1))
     if previousClose then line((px-1)/fx,previousClose,xx,cy,C.warn,.42) end
     previousClose=cy
    end
   end
   for _,value in ipairs({-60,-30,0}) do
    local yy=meterTop+meterH*(1-(value+90)/102);line(0,yy,w,yy,C.edge,.12)
   end
   for _,v in ipairs({{S.open,C.accent2},{S.close,C.warn}}) do
    local yy=meterTop+meterH*(1-clamp((v[1]+90)/102,0,1))
    for xx=0,w-4,9 do line(xx,yy,min(xx+4,w),yy,v[2],.78) end
   end
   local resultY=waveH+46
   for _,p in ipairs(Core.plan(data.info,A.regions,S)) do
    if p.keep then
     local left,right
     if S.action=='split' or S.keep then left,right=tx(max(start,p.a)),tx(min(start+span,p.b))
     else left=(p.dest-data.info.pos)/data.info.len*w;right=left+(p.b-p.a)/data.info.len*w end
     left,right=max(0,left),min(w,right)
     if right>left then rect(left,resultY,right-left,4,p.sound and C.accent or C.quiet,.86) end
    end
   end
   detach();image=host.I.CreateImageFromLICE(bitmap);host:attachImage(image)
   self.data,self.start,self.span,self.basis=data,start,span,S.basis
   A.wave_surface_dirty=false
  end
  local xx,yy=host.originX+x,host.originY+y
  host.I.DrawList_AddImage(host.draw,image,xx,yy,xx+w*scale,yy+totalH*scale)
 end
 V.close=V.clear
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
 function L.text(value)
  local text=type(value)=='string' and value or tostring(value or '')
  if L.code=='JP' then return text end
  return en[text] or text
 end
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
 ["設定値が範囲外です："]="Setting out of range: ",
 ["クローズはオープン以下の値にしてください。"]="Close must not exceed Open.",
 ["検出基準が無効です。"]="Invalid detection mode.",
 ["処理方法が無効です。"]="Invalid processing mode.",
 ["数値を入力してください。"]="Enter a number.",
 ["対象アイテムがありません。"]="No target items.",
 ["MIDI／空アイテムは対象外です。"]="MIDI and empty items are unsupported.",
 ["音声ソースがありません。"]="No audio source.",
 ["音声を持たないアイテムは対象外です。"]="Items without audio are unsupported.",
 ["音声チャンネルを取得できません。"]="Cannot read audio channels.",
 ["長さが0のアイテムは対象外です。"]="Zero-length items are unsupported.",
 ["対象アイテムが見つかりません。"]="Target item not found.",
 ["アイテムの状態を保存できません。"]="Cannot save item state.",
 ["対象が削除されました。"]="Target was deleted.",
 ["1アイテムは60分以内にしてください。"]="Keep each item under 60 minutes.",
 ["ピーク解析用バッファを作成できません。"]="Cannot allocate peak buffer.",
 ["LUFS-Mはモノ／ステレオ対応です。多チャンネルはピークを選択してください。"]="LUFS-M supports mono/stereo. Use Peak for multichannel audio.",
 ["ラウドネス解析用バッファを作成できません。"]="Cannot allocate loudness buffer.",
 ["音声アクセサを作成できません。"]="Cannot create audio accessor.",
 ["音声を読み出せません。オフライン状態やソースを確認してください。"]="Cannot read audio. Check source and online status.",
 ["REAPERのピークデータを取得できず、音声の直接読み出しにも失敗しました。ソースのオンライン状態を確認してください。"]="Peak data and direct audio reading failed. Check source online status.",
 ["音声の直接読み出しに失敗しました（戻り値："]="Direct audio read failed (code: ",
 ["）。"]=").",
 ["音声に読み取れないサンプルがあります。"]="Audio contains unreadable samples.",
 ["解析中に対象が削除されました。"]="Target was deleted during analysis.",
 ["解析中に音声が変更されました。選択を更新してください。"]="Audio changed during analysis. Refresh selection.",
 ["音声取得に失敗しました（戻り値："]="Audio read failed (code: ",
 ["）。解析を中止しました。"]="). Analysis stopped.",
 ["解析モードが無効です。"]="Invalid analysis mode.",
 ["検出区間が安全上限を超えました。しきい値、最小無音、最小区間の設定を調整してください。"]="Too many detected sections. Adjust threshold, minimum silence and minimum clip length.",
 ["アイテム属性を更新できません："]="Cannot update item property: ",
 ["対象が見つかりません：%s（%s）"]="Target not found: %s (%s)",
 ["不明なエラー"]="Unknown error",
 ["ロックされたアイテムがあります：%s"]="Locked item: %s",
 ["解析後に対象が変更されています：%s"]="Target changed after analysis: %s",
 ["処理対象がありません。"]="Nothing to process.",
 ["アイテムを分割できません。"]="Cannot split item.",
 ["無音部分を削除できません。"]="Cannot delete silence.",
 ["アイテムを移動できません。"]="Cannot move item.",
 ["処理を中止し、元のアイテムを復元しました。"]="Processing stopped. Original items restored.",
 ["復元できない項目があります。REAPERのUndoで戻してください。"]="Some items could not be restored. Use REAPER Undo.",
 ["ファイルが長いため、解析中および結果を表示している間はメモリ使用量が増えます。よろしいですか？\n\n%s\n長さ：%.1f分\n\n［実行］する場合は OK、［キャンセル］する場合はキャンセルを押してください。\nキャンセルしたアイテムは選択解除されます。"]="This long file uses more memory during analysis and while results are shown. Continue?\n\n%s\nLength: %.1f min\n\nOK: continue / Cancel: skip and deselect this item.",
 ["Auto Trim / Split | 長尺LUFS解析"]="Auto Trim / Split | Long LUFS analysis",
 ["長尺アイテム%d件のLUFS解析をキャンセルし、選択を解除しました。"]="Cancelled LUFS analysis and deselected %d long item(s).",
 ["音声アイテムを選択してください。"]="Select audio items.",
 [" 対象外："]=" Skipped: ",
 ["個"]=" items",
 ["長尺アイテム%d件の選択を解除しました。 "]="Deselected %d long item(s). ",
 ["Peakデータをキャッシュから読み込みました。"]="Peak data loaded from cache.",
 ["Loudnessデータをキャッシュから読み込みました。"]="Loudness data loaded from cache.",
 ["Peakを取得しています。"]="Reading peaks.",
 ["ラウドネスを解析しています。"]="Analyzing loudness.",
 ["プレビューを更新しています。"]="Updating preview.",
 ["Peakの数値設定を初期値に戻しました。"]="Peak values reset.",
 ["Loudnessの数値設定を初期値に戻しました。"]="Loudness values reset.",
 ["%dアイテムを処理しました。%s"]="Processed %d item(s). %s",
 ["次の対象を表示しています。"]="Showing next target.",
 ["完了です。"]="Done.",
 ["ロックされたアイテムがあります："]="Locked item: ",
 ["長尺アイテムのLUFS解析をキャンセルし、選択を解除しました。バッチ処理は開始前の状態で中止しました。"]="Long-item LUFS analysis cancelled; item deselected. Batch stopped before edits.",
 ["解析を中止しました。アイテムは変更していません。"]="Analysis stopped. Items unchanged.",
 ["プレビューの解析完了を待ってください。"]="Wait for preview analysis.",
 ["ロックされたアイテムがあります。ロックを解除してください。"]="Unlock the locked items.",
 ["長尺アイテムのLUFS解析をキャンセルし、選択を解除しました。"]="Long-item LUFS analysis cancelled; item deselected.",
 ["実行用に全対象を再解析しています。"]="Reanalyzing all targets for processing.",
 ["音あり区間は0です。実行すると対象全体を削除します。"]="No audio sections. Processing will delete the entire target.",
 ["分割境界はありません。"]="No split boundaries.",
 ["%d区間を検出。設定を調整してから実行できます。"]="Detected %d sections. Adjust settings, then run.",
 ["CHAMELEON  REAPERテーマに擬態"]="CHAMELEON  REAPER theme",
 ["CHAMELEON  オリジナル配色"]="CHAMELEON  Original colors",
 ["カスタムタイトルバーには js_ReaScriptAPI が必要です。\nReaPack から js_ReaScriptAPI をインストールしてください。"]="The app bar requires js_ReaScriptAPI.\nInstall js_ReaScriptAPI via ReaPack.",
 ["ON / 両端のみ"]="ON / Ends only",
 ["ON：最初と最後の有効区間の外側だけを処理します。内部の無音は残し、プリ／ポストロールは外側の両端に適用します。"]="ON: process only outside the first and last audio sections. Keep internal silence; apply pre/post-roll at the outer ends.",
 ["数値を入力できなかったため、元の値へ戻しました。"]="Invalid input. Previous value restored.",
 [" ／ 上下ドラッグ・ホイール："]=" / Drag vertically or wheel: ",
 ["刻み"]=" steps",
 ["Peakを取得しています…"]="Reading peaks...",
 ["ラウドネスを解析しています…"]="Analyzing loudness...",
 ["音声アイテムを選択してください"]="Select audio items",
 ["ホイール：拡大・縮小 ／ Shift＋ホイール：横移動"]="Wheel: zoom / Shift+wheel: pan",
 ["位置 %.3f s / Peak %.1f dBFS / OPEN LUFS-M %.1f / CLOSE FAST %.1f"]="Position %.3f s / Peak %.1f dBFS / OPEN LUFS-M %.1f / CLOSE FAST %.1f",
 ["位置 %.3f s / Peak %.1f dBFS"]="Position %.3f s / Peak %.1f dBFS",
 ["SILENCE DETECTION / TRIM  スレッショルドによる無音検出・区間処理"]="SILENCE DETECTION / TRIM  Threshold-based processing",
 ["選択 %02d   /   残り %02d"]="Selected %02d   /   Left %02d",
 ["検出区間  %d    合計  %.3f s"]="Sections %d    Total %.3f s",
 ["検出基準"]="DETECTION",
 ["ピークレベル"]="Peak level",
 ["各1 ms区間の最大振幅。全チャンネルの最大値で検出します。"]="Maximum amplitude per 1 ms block across all channels.",
 ["ラウドネス"]="Loudness",
 ["OPENはK特性＋400 msのLUFS-M、CLOSEは同じK特性＋100 msのFASTラウドネスで判定します。"]="OPEN: K-weighted 400 ms LUFS-M. CLOSE: K-weighted 100 ms FAST loudness.",
 ["検出レベル"]="LEVELS",
 ["オープンスレッショルド"]="Open threshold",
 ["LUFS-M（400 ms）がこの値を超えると音あり区間を開始します。"]="Start an audio section when LUFS-M (400 ms) exceeds this level.",
 ["この値を超えると音あり区間を開始します。"]="Start an audio section above this level.",
 ["クローズスレッショルド"]="Close threshold",
 ["FASTラウドネス（100 ms）がこの値未満になると無音候補を開始します。"]="Start a silence candidate when FAST loudness (100 ms) drops below this level.",
 ["この値未満になると無音候補を開始します。"]="Start a silence candidate below this level.",
 ["スレッショルド差を固定"]="Link thresholds",
 ["開閉スレッショルドの差を保ったまま両方を動かします。"]="Move both thresholds while keeping their difference.",
 ["時間設定"]="TIMING",
 ["短い無音を無視"]="Ignore short silence",
 ["この時間未満の無音は無視して、前後の音を同じ音あり区間として扱います。"]="Treat silence shorter than this as part of the surrounding audio section.",
 ["最短クリップ長"]="Min. clip length",
 ["この時間未満の音あり区間は残すクリップとして採用しません。プリ／ポストロールを加える前の長さで判定します。"]="Discard audio sections shorter than this, measured before pre/post-roll.",
 ["プリロール"]="Pre-roll",
 ["正：開始を前へ広げる／負：開始を後ろへ縮める。元アイテム内に制限します。"]="Positive: extend start earlier. Negative: trim start later. Limited to the original item.",
 ["ポストロール"]="Post-roll",
 ["正：終了を後ろへ広げる／負：終了を前へ縮める。重なった区間は結合します。"]="Positive: extend end later. Negative: trim end earlier. Merge overlapping sections.",
 ["フェードイン"]="Fade in",
 ["音あり区間に指定時間のフェードインを設定します。"]="Apply this fade-in duration to audio sections.",
 ["フェードアウト"]="Fade out",
 ["音あり区間に指定時間のフェードアウトを設定します。"]="Apply this fade-out duration to audio sections.",
 ["短い区間ではフェードが重ならない長さに縮めます。"]="Shorten fades to avoid overlap on short sections.",
 ["無音部分を削除"]="Remove silence",
 ["灰色の区間を削除し、青色の区間を残します。"]="Delete gray sections and keep blue sections.",
 ["分割"]="Split",
 ["青・灰の境界で分割し、全ての区間を元の位置に残します。"]="Split at blue/gray boundaries and keep all sections in place.",
 ["削除した区間を詰める"]="Close gaps",
 ["ON：無音部分を削除した後、残った検出区間を元アイテムの開始位置から隙間なく詰めます。"]="ON: after removing silence, pack remaining sections from the original item start.",
 ["全選択を解析中  %d / %d    %d%%（解析完了後にまとめて編集）"]="Analyzing all %d / %d    %d%% (edits follow analysis)",
 ["Peak取得  %d%%"]="Reading peaks %d%%",
 ["Loudness解析  %d%%"]="Loudness analysis %d%%",
 ["現在の検出モードの数値設定だけを初期値へ戻します。各スイッチ設定は変更しません。"]="Reset numeric values for the current detection mode. Keep switches unchanged.",
 ["処理を中止"]="Stop",
 ["処理を実行"]="Process",
 ["Enter：実行。編集は1回のUndoで元に戻せます。"]="Enter: run. One Undo restores all edits.",
 ["選択アイテムを一括処理"]="Process all selected",
 ["ON：先頭をプレビューして全選択へ適用。OFF：1つずつ処理して次へ。"]="ON: preview first item, apply to all. OFF: process one at a time.",
 ["Auto Trim / Split | エラー"]="Auto Trim / Split | Error",
 ["カスタムタイトルバーを初期化できません。"]="Cannot initialize the app bar.",
 ["プロジェクトが変更されたため解析を中止しました。"]="Project changed. Analysis stopped.",
 ["表示言語を切替（JP / EN）"]="Switch language (JP / EN)",
 ["プリセットを読み込みました: ファクトリーデフォルト"]="Loaded: Factory Default",
 ["選択中のトラック / バスを指定"]="Use selected track / bus",
},patterns={
 {"^「(.*)」を上書きしますか？$","Overwrite \"%s\"?"},
 {"^([%+%-]?[%d%.eE]+)–([%+%-]?[%d%.eE]+) / ([%+%-]?[%d%.eE]+)   スクロールで選択$","%d–%d / %d   Scroll to browse"},
 {"^解析中%.%.%.([%+%-]?[%d%.eE]+)%%$","Analyzing...%d%%"},
 {"^対象が見つかりません：(.-)（(.-)）$","Target not found: %s (%s)"},
 {"^ロックされたアイテムがあります：(.-)$","Locked item: %s"},
 {"^解析後に対象が変更されています：(.-)$","Target changed after analysis: %s"},
 {"^ファイルが長いため、解析中および結果を表示している間はメモリ使用量が増えます。よろしいですか？\n\n(.-)\n長さ：([%+%-]?[%d%.eE]+)分\n\n［実行］する場合は OK、［キャンセル］する場合はキャンセルを押してください。\nキャンセルしたアイテムは選択解除されます。$","This long file uses more memory during analysis and while results are shown. Continue?\n\n%s\nLength: %.1f min\n\nOK: continue / Cancel: skip and deselect this item."},
 {"^長尺アイテム([%+%-]?[%d%.eE]+)件のLUFS解析をキャンセルし、選択を解除しました。$","Cancelled LUFS analysis and deselected %d long item(s)."},
 {"^長尺アイテム([%+%-]?[%d%.eE]+)件の選択を解除しました。 $","Deselected %d long item(s). "},
 {"^([%+%-]?[%d%.eE]+)アイテムを処理しました。(.-)$","Processed %d item(s). %s",{2}},
 {"^([%+%-]?[%d%.eE]+)区間を検出。設定を調整してから実行できます。$","Detected %d sections. Adjust settings, then run."},
 {"^位置 ([%+%-]?[%d%.eE]+) s / Peak ([%+%-]?[%d%.eE]+) dBFS / OPEN LUFS%-M ([%+%-]?[%d%.eE]+) / CLOSE FAST ([%+%-]?[%d%.eE]+)$","Position %.3f s / Peak %.1f dBFS / OPEN LUFS-M %.1f / CLOSE FAST %.1f"},
 {"^位置 ([%+%-]?[%d%.eE]+) s / Peak ([%+%-]?[%d%.eE]+) dBFS$","Position %.3f s / Peak %.1f dBFS"},
 {"^選択 ([%+%-]?[%d%.eE]+)   /   残り ([%+%-]?[%d%.eE]+)$","Selected %02d   /   Left %02d"},
 {"^検出区間  ([%+%-]?[%d%.eE]+)    合計  ([%+%-]?[%d%.eE]+) s$","Sections %d    Total %.3f s"},
 {"^全選択を解析中  ([%+%-]?[%d%.eE]+) / ([%+%-]?[%d%.eE]+)    ([%+%-]?[%d%.eE]+)%%（解析完了後にまとめて編集）$","Analyzing all %d / %d    %d%% (edits follow analysis)"},
 {"^Peak取得  ([%+%-]?[%d%.eE]+)%%$","Reading peaks %d%%"},
 {"^Loudness解析  ([%+%-]?[%d%.eE]+)%%$","Loudness analysis %d%%"},
 {"^「(.-)」を上書きしますか？$","\"%s\"?"},
 {"^(.-)」を上書きしますか？$","%s\"?"},
 {"^プリセットを保存しました: (.-)$","Saved: %s"},
 {"^プリセットを読み込みました: (.-)$","Loaded: %s"},
 {"^(.-)個インポートしました。$","%s preset(s) imported."},
 {"^現在: (.-)(.-)$","Current: %s%s"},
 {"^設定値が範囲外です：(.-)$","Setting out of range: %s"},
 {"^音声の直接読み出しに失敗しました（戻り値：(.-)）。$","Direct audio read failed (code: %s)."},
 {"^(.-)）。$","%s)."},
 {"^音声取得に失敗しました（戻り値：(.-)）。解析を中止しました。$","Audio read failed (code: %s). Analysis stopped."},
 {"^(.-)）。解析を中止しました。$","%s). Analysis stopped."},
 {"^アイテム属性を更新できません：(.-)$","Cannot update item property: %s"},
 {"^音声アイテムを選択してください。(.-)$","Select audio items.%s"},
 {"^ 対象外：(.-)個$"," Skipped: %s items"},
 {"^(.-)個$","%s items"},
 {"^ロックされたアイテムがあります：(.-)$","Locked item: %s"},
 {"^(.-) ／ 上下ドラッグ・ホイール：(.-)刻み$","%s / Drag vertically or wheel: %s steps"},
 {"^ ／ 上下ドラッグ・ホイール：(.-)刻み$"," / Drag vertically or wheel: %s steps"},
 {"^(.-)刻み$","%s steps"},
 {"^「(.*)」を上書きしますか？$","Overwrite \"%s\"?"},
 {"^(%d+)個インポートしました。$","Imported %s preset(s)."},
 {"^(%d+)件をノーマライズしました。選択を解除しました。$","Normalized %s items and deselected them."},
},prefixes={"音声の直接読み出しに失敗しました（戻り値：","音声取得に失敗しました（戻り値：","ロックされたアイテムがあります：","プリセットを読み込みました: ","アイテム属性を更新できません："," ／ 上下ドラッグ・ホイール：","プリセットを保存しました: ","設定値が範囲外です："," 対象外：","現在: "}}

local Language=create_language(reaper,"BLT_AUTO_TRIM_SPLIT",LanguageCatalog)
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
local Core={SR=48000,HOP=48,LOUD_BLOCK=24000,PEAK_RATE=1000,PEAK_BUFFER_VALUES=262144,
  MAX_ITEM_SECONDS=60*60,LONG_LUFS_WARNING_SECONDS=25*60,MAX_DETECTED_REGIONS=65536}
local abs,min,max,floor,ceil=math.abs,math.min,math.max,math.floor,math.ceil
local function finite(n) return type(n)=="number" and n==n and abs(n)<math.huge end
local function clamp(n,a,b) return max(a,min(b,n)) end
local function copy(t) local o={}; for k,v in pairs(t) do o[k]=v end; return o end
local function db(x) return x>1e-12 and 20*math.log(x,10) or -240 end
Core.defaults={basis="peak",open=-61,close=-61,relative=true,min_open=1000,min_close=165,
  pre=1,post=15,fade_in_on=true,fade_out_on=true,fade_in=1,fade_out=20,
  all=true,action="delete",keep=true,edge_mode=false}
Core.ranges={open={-120,12},close={-120,12},min_open={0,60000},min_close={0,60000},
  pre={-60000,60000},post={-60000,60000},fade_in={0,60000},fade_out={0,60000}}
Core.steps={open=1,close=1,min_open=10,min_close=10,pre=1,post=1,fade_in=1,fade_out=1}
Core.precision={open=2,close=2,min_open=0,min_close=0,pre=0,post=0,fade_in=0,fade_out=0}
function Core.quantize(key,n)
  local digits=Core.precision[key]
  if digits==nil then return n end
  local factor=10^digits
  return (n<0 and ceil(n*factor-.5) or floor(n*factor+.5))/factor
end
function Core.validate(s)
  for k,r in pairs(Core.ranges) do
    if not finite(s[k]) or s[k]<r[1] or s[k]>r[2] then return nil,"設定値が範囲外です："..k end
  end
  if s.close>s.open then return nil,"クローズはオープン以下の値にしてください。" end
  if s.basis~="peak" and s.basis~="lufs" then return nil,"検出基準が無効です。" end
  if s.action~="delete" and s.action~="split" then return nil,"処理方法が無効です。" end
  return true
end
function Core.set_number(s,key,n)
  local r=Core.ranges[key]
  if not r or not finite(n) then return nil,"数値を入力してください。" end
  local requested=n
  n=Core.quantize(key,n)
  local old=s[key]
  if (key=="open" or key=="close") and s.relative then
    local other=key=="open" and "close" or "open"
    local delta=clamp(n-old,max(r[1]-old,r[1]-s[other]),min(r[2]-old,r[2]-s[other]))
    s[key],s[other]=old+delta,s[other]+delta
  else
    n=clamp(n,r[1],r[2])
    if key=="open" then n=max(n,s.close) elseif key=="close" then n=min(n,s.open) end
    s[key]=n
  end
  s[key]=Core.quantize(key,s[key])
  return true,abs((s[key] or requested)-requested)>1e-9
end
local function valid_item(project,item) return item and R.ValidatePtr2(project,item,"MediaItem*") end
function Core.info(project,item)
  if not valid_item(project,item) then return nil,"対象アイテムがありません。" end
  local take=R.GetActiveTake(item)
  if not take or R.TakeIsMIDI(take) then return nil,"MIDI／空アイテムは対象外です。" end
  local source=R.GetMediaItemTake_Source(take)
  if not source then return nil,"音声ソースがありません。" end
  local source_type=R.GetMediaSourceType(source)
  source_type=type(source_type)=="string" and source_type:upper() or ""
  if source_type=="EMPTY" or source_type=="MIDI" or source_type=="MIDIPOOL" then
    return nil,"MIDI／空アイテムは対象外です。"
  end
  local source_sr=R.GetMediaSourceSampleRate(source)
  if not finite(source_sr) or source_sr<=0 then
    return nil,"音声を持たないアイテムは対象外です。"
  end

  local channels=R.GetMediaSourceNumChannels(source)
  if not finite(channels) or channels<1 or channels>64 then return nil,"音声チャンネルを取得できません。" end
  local channel_mode=R.GetMediaItemTakeInfo_Value(take,"I_CHANMODE")
  if channel_mode==2 or channel_mode==3 or channel_mode==4 then channels=1 end
  local pos,len=R.GetMediaItemInfo_Value(item,"D_POSITION"),R.GetMediaItemInfo_Value(item,"D_LENGTH")
  if not finite(pos) or not finite(len) or len<=0 then return nil,"長さが0のアイテムは対象外です。" end
  local track=R.GetMediaItemTrack(item)
  local _,guid=R.GetSetMediaItemInfo_String(item,"GUID","",false)
  return {item=item,take=take,track=track,pos=pos,len=len,channels=floor(channels),
    guid=guid or tostring(item),name=R.GetTakeName(take) or "Audio item",
    tracknum=R.GetMediaTrackInfo_Value(track,"IP_TRACKNUMBER"),
    index=R.GetMediaItemInfo_Value(item,"IP_ITEMNUMBER"),
    gain=abs(R.GetMediaItemInfo_Value(item,"D_VOL")*R.GetMediaItemTakeInfo_Value(take,"D_VOL")),
    locked=(floor(R.GetMediaItemInfo_Value(item,"C_LOCK"))&1)~=0}
end
local function find_item_by_guid(project,guid)
  if not guid or guid=="" then return nil end
  for i=0,R.CountMediaItems(project)-1 do
    local item=R.GetMediaItem(project,i)
    local _,g=R.GetSetMediaItemInfo_String(item,"GUID","",false)
    if g==guid then return item end
  end
  return nil
end
function Core.refresh_info(project,snapshot)
  if not snapshot then return nil,"対象アイテムがありません。" end
  local item=snapshot.item
  if not valid_item(project,item) then item=find_item_by_guid(project,snapshot.guid) end
  if not item then return nil,"対象アイテムが見つかりません。" end
  return Core.info(project,item)
end
function Core.selection(project)
  local list,ids,skipped={},{},0
  for i=0,R.CountSelectedMediaItems(project)-1 do
    local item=R.GetSelectedMediaItem(project,i)
    ids[#ids+1]=tostring(item)
    local info=Core.info(project,item)
    if info then list[#list+1]=info else skipped=skipped+1 end
  end
  table.sort(list,function(a,b)
    if a.pos~=b.pos then return a.pos<b.pos end
    if a.tracknum~=b.tracknum then return a.tracknum<b.tracknum end
    return a.index<b.index
  end)
  table.sort(ids)
  return list,table.concat(ids,"|"),skipped
end
function Core.selection_key(project)
  local ids={}
  for i=0,R.CountSelectedMediaItems(project)-1 do ids[#ids+1]=tostring(R.GetSelectedMediaItem(project,i)) end
  table.sort(ids)
  return table.concat(ids,"|")
end
function Core.chunk(info)
  local ok,text=R.GetItemStateChunk(info.item,"",false)
  if not ok or type(text)~="string" or text=="" then error("アイテムの状態を保存できません。",0) end
  return text
end
function Core.dispose(j)
  if not j then return end
  if j.accessor then local accessor=j.accessor;j.accessor=nil;pcall(R.DestroyAudioAccessor,accessor) end
  if j.peak_accessor then local accessor=j.peak_accessor;j.peak_accessor=nil;pcall(R.DestroyAudioAccessor,accessor) end
end
function Core.start(project,info,basis,known_chunk)
  if not valid_item(project,info.item) then error("対象が削除されました。",0) end
  if info.len>Core.MAX_ITEM_SECONDS then error("1アイテムは60分以内にしてください。",0) end
  local chunk=known_chunk or Core.chunk(info)
  if basis=="peak" then
    local total=ceil(info.len*Core.PEAK_RATE)
    local max_bins=max(1,floor(Core.PEAK_BUFFER_VALUES/max(2,info.channels*2)))
    local buffer_ok,buffer=pcall(R.new_array,max_bins*info.channels*2)
    if not buffer_ok or not buffer then error("ピーク解析用バッファを作成できません。",0) end
    return {mode="peak",info=info,project=project,offset=0,total=total,peak={},lufs={},fast={},
      max_peak=0,chunk=chunk,done=false,max_bins=max_bins,buffer=buffer}
  end
  if basis~="lufs" then error("検出基準が無効です。",0) end
  if info.channels>2 then error("LUFS-Mはモノ／ステレオ対応です。多チャンネルはピークを選択してください。",0) end
  local j={mode="lufs",info=info,project=project,offset=0,total=ceil(info.len*Core.SR),peak={},lufs={},fast={},
    ring={},ring_index=1,ring_sum=0,fast_ring={},fast_index=1,fast_sum=0,
    bin_energy=0,bin_peak=0,bin_samples=0,states={},max_peak=0,
    chunk=chunk,done=false}
  for c=1,info.channels do j.states[c]={0,0,0,0} end
  local buffer_ok,buffer=pcall(R.new_array,Core.LOUD_BLOCK*info.channels)
  if not buffer_ok or not buffer then error("ラウドネス解析用バッファを作成できません。",0) end
  j.buffer=buffer
  j.accessor=R.CreateTakeAudioAccessor(info.take)
  if not j.accessor then error("音声アクセサを作成できません。",0) end
  local a,b=R.GetAudioAccessorStartTime(j.accessor),R.GetAudioAccessorEndTime(j.accessor)
  if not finite(a) or not finite(b) or b<=a then
    Core.dispose(j); error("音声を読み出せません。オフライン状態やソースを確認してください。",0)
  end
  return j
end
local function finish_bin(j)
  local k=#j.peak+1
  j.peak[k]=j.bin_peak; j.max_peak=max(j.max_peak,j.bin_peak)
  local ri=j.ring_index
  j.ring_sum=max(0,j.ring_sum-(j.ring[ri] or 0)+j.bin_energy)
  j.ring[ri]=j.bin_energy; j.ring_index=ri%400+1
  local power=j.ring_sum/(Core.SR*0.4)
  j.lufs[k]=power>1e-24 and -0.691+10*math.log(power,10) or -240
  local fi=j.fast_index
  j.fast_sum=max(0,j.fast_sum-(j.fast_ring[fi] or 0)+j.bin_energy)
  j.fast_ring[fi]=j.bin_energy; j.fast_index=fi%100+1
  local fast_power=j.fast_sum/(Core.SR*0.1)
  j.fast[k]=fast_power>1e-24 and -0.691+10*math.log(fast_power,10) or -240
  j.bin_samples,j.bin_peak,j.bin_energy=0,0,0
end
local function start_peak_accessor_fallback(j)
  if j.peak_accessor then return end
  j.peak_accessor=R.CreateTakeAudioAccessor(j.info.take)
  if not j.peak_accessor then
    error("REAPERのピークデータを取得できず、音声の直接読み出しにも失敗しました。ソースのオンライン状態を確認してください。",0)
  end
  j.fallback_bins=max(1,floor(Core.PEAK_BUFFER_VALUES/(j.info.channels*48)))
  j.buffer=R.new_array(j.fallback_bins*48*j.info.channels)
end

local function read_peak_accessor_step(j)
  local remaining=j.total-j.offset
  if remaining<=0 then
    if j.peak_accessor then local accessor=j.peak_accessor;j.peak_accessor=nil;pcall(R.DestroyAudioAccessor,accessor) end
    j.done=true; j.buffer=nil; return true
  end
  local bins=min(j.fallback_bins,remaining)
  local samples=bins*48
  local nchan=j.info.channels
  j.buffer.clear()
  local rc=R.GetAudioAccessorSamples(j.peak_accessor,Core.SR,nchan,j.offset/Core.PEAK_RATE,samples,j.buffer)
  if type(rc)~="number" or (rc~=0 and rc~=1) then
    if j.peak_accessor then local accessor=j.peak_accessor;j.peak_accessor=nil;pcall(R.DestroyAudioAccessor,accessor) end
    error("音声の直接読み出しに失敗しました（戻り値："..tostring(rc).."）。",0)
  end
  local values=j.buffer.table(1,samples*nchan)
  local gain=j.info.gain
  for b=0,bins-1 do
    local pk=0
    local first=b*48*nchan
    if rc~=0 then
      for frame=0,47 do
        local base=first+frame*nchan
        for c=1,nchan do
          local sample=values[base+c] or 0
          if not finite(sample) then
            if j.peak_accessor then local accessor=j.peak_accessor;j.peak_accessor=nil;pcall(R.DestroyAudioAccessor,accessor) end
            error("音声に読み取れないサンプルがあります。",0)
          end
          pk=max(pk,abs(sample))
        end
      end
    end
    pk=pk*gain
    j.peak[#j.peak+1]=pk
    j.max_peak=max(j.max_peak,pk)
  end
  j.offset=j.offset+bins
  if j.offset>=j.total then
    if j.peak_accessor then local accessor=j.peak_accessor;j.peak_accessor=nil;pcall(R.DestroyAudioAccessor,accessor) end
    j.offset=j.total; j.done=true; j.buffer=nil
  end
  return j.done
end

local function read_peak_step(j)
  if j.done then return true end
  if not valid_item(j.project,j.info.item) then error("解析中に対象が削除されました。",0) end
  if j.peak_accessor then return read_peak_accessor_step(j) end
  local remaining=j.total-j.offset
  if remaining<=0 then j.done=true; j.buffer=nil; return true end
  local request=min(j.max_bins,remaining)
  local nchan=j.info.channels
  j.buffer.clear()
  local rv=R.GetMediaItemTake_Peaks(j.info.take,Core.PEAK_RATE,j.info.pos+j.offset/Core.PEAK_RATE,nchan,request,0,j.buffer)
  local got=(type(rv)=="number") and (rv & 0xFFFFF) or 0
  if got<=0 and request>4096 then
    request=min(4096,remaining)
    j.buffer.clear()
    rv=R.GetMediaItemTake_Peaks(j.info.take,Core.PEAK_RATE,j.info.pos+j.offset/Core.PEAK_RATE,nchan,request,0,j.buffer)
    got=(type(rv)=="number") and (rv & 0xFFFFF) or 0
  end
  if got<=0 then
    start_peak_accessor_fallback(j)
    return read_peak_accessor_step(j)
  end
  local values=j.buffer.table(1,got*nchan*2)
  local second=got*nchan
  local gain=j.info.gain
  for i=0,got-1 do
    local pk=0
    local base=i*nchan
    for c=1,nchan do
      local idx=base+c
      local hi=values[idx] or 0
      local lo=values[second+idx] or 0
      pk=max(pk,abs(hi),abs(lo))
    end
    pk=pk*gain
    j.peak[#j.peak+1]=pk
    j.max_peak=max(j.max_peak,pk)
  end
  j.offset=j.offset+got
  if j.offset>=j.total or got<request then
    while #j.peak<j.total do j.peak[#j.peak+1]=0 end
    j.offset=j.total; j.done=true; j.buffer=nil
  end
  return j.done
end
local function read_loud_step(j)
  if j.done then return true end
  if not valid_item(j.project,j.info.item) then error("解析中に対象が削除されました。",0) end
  if R.AudioAccessorStateChanged(j.accessor) then error("解析中に音声が変更されました。選択を更新してください。",0) end
  local count=min(Core.LOUD_BLOCK,j.total-j.offset)
  j.buffer.clear()
  local rc=R.GetAudioAccessorSamples(j.accessor,Core.SR,j.info.channels,j.offset/Core.SR,count,j.buffer)
  if type(rc)~="number" or (rc~=0 and rc~=1) then
    error("音声取得に失敗しました（戻り値："..tostring(rc).."）。解析を中止しました。",0)
  end
  local values=j.buffer.table(1,count*j.info.channels)
  local nchan,gain=j.info.channels,j.info.gain
  for i=0,count-1 do
    local pk,energy=0,0
    for c=1,nchan do
      local raw=values[i*nchan+c]
      if not finite(raw) then error("音声に読み取れないサンプルがあります。",0) end
      local sample=(rc==0 and 0 or raw)*gain
      pk=max(pk,abs(sample))
      local st=j.states[c]
      local v=1.53512485958697*sample+st[1]
      st[1]=-2.69169618940638*sample+1.69065929318241*v+st[2]
      st[2]=1.19839281085285*sample-0.73248077421585*v
      local z=v+st[3]
      st[3]=-2*v+1.99004745483398*z+st[4]
      st[4]=v-0.99007225036621*z
      energy=energy+z*z
    end
    j.bin_peak=max(j.bin_peak,pk); j.bin_energy=j.bin_energy+energy; j.bin_samples=j.bin_samples+1
    if j.bin_samples==Core.HOP then finish_bin(j) end
  end
  j.offset=j.offset+count
  if j.offset>=j.total then
    if j.bin_samples>0 then finish_bin(j) end
    Core.dispose(j); j.buffer=nil; j.states=nil; j.ring=nil; j.fast_ring=nil; j.done=true
  end
  return j.done
end
function Core.read_step(j)
  if j.mode=="peak" then
    return read_peak_step(j)
  elseif j.mode=="lufs" then
    return read_loud_step(j)
  end
  error("解析モードが無効です。",0)
end
function Core.detector(data,s)
  local ok,err=Core.validate(s); if not ok then error(err,0) end
  if s.basis=="lufs" and data.info.channels>2 then error("LUFS-Mはモノ／ステレオ対応です。多チャンネルはピークを選択してください。",0) end
  return {data=data,s=copy(s),i=1,regions={},raw={},raw_first=nil,raw_last=nil,raw_count=0,opened=nil,quiet=nil,done=false}
end
local function append_region(d,a,b)
  if b<=a then return end
  if b-a+1e-10 < d.s.min_close/1000 then return end
  if d.s.edge_mode then
    d.raw_first=d.raw_first or a;d.raw_last=b;d.raw_count=d.raw_count+1
    return
  end
  a=clamp(a-d.s.pre/1000,0,d.data.info.len)
  b=clamp(b+d.s.post/1000,0,d.data.info.len)
  if b-a<1/Core.SR then return end
  local last=d.regions[#d.regions]
  if last and a<=last[2]+1e-10 then last[2]=max(last[2],b)
  else
    if #d.regions>=Core.MAX_DETECTED_REGIONS then
      error("検出区間が安全上限を超えました。しきい値、最小無音、最小区間の設定を調整してください。",0)
    end
    d.regions[#d.regions+1]={a,b}
  end
end
function Core.detect_step(d,limit)
  if d.done then return true end
  local data,s=d.data,d.s
  local ignore_silence_s=s.min_open/1000
  for _=1,limit or 8192 do
    local i=d.i
    if i>#data.peak then
      if d.opened then append_region(d,d.opened,data.info.len) end
      if s.edge_mode and d.raw_first then
        local a=clamp(d.raw_first-s.pre/1000,0,data.info.len)
        local b=clamp(d.raw_last+s.post/1000,0,data.info.len)
        if b-a>=1/Core.SR then d.regions={{a,b}};d.raw={{d.raw_first,d.raw_last}} end
      end
      d.done=true; return true
    end
    local t=(i-1)*0.001
    local ending=min(i*0.001,data.info.len)
    local open_level,close_level
    if s.basis=="lufs" then
      open_level=data.lufs[i] or -240
      close_level=data.fast[i] or -240
    else
      open_level=db(data.peak[i])
      close_level=open_level
    end

    if d.opened then
      if close_level<s.close then
        d.quiet=d.quiet or t
        if ending-d.quiet+1e-10>=ignore_silence_s then
          append_region(d,d.opened,d.quiet)
          d.opened=nil
          d.quiet=nil
        end
      else
        d.quiet=nil
      end
    else
      if open_level>s.open then
        d.opened=t
        d.quiet=nil
      end
    end
    d.i=i+1
  end
  return false
end

function Core.plan(info,regions,s)
  local parts,cursor,packed={},0,0
  local function add(a,b,sound)
    if b-a<1e-10 then return end
    local keep=sound or s.action=="split"
    local dest=info.pos+a
    if sound and s.action=="delete" and not s.keep then dest=info.pos+packed; packed=packed+b-a end
    parts[#parts+1]={a=a,b=b,sound=sound,keep=keep,dest=dest}
  end
  for _,r in ipairs(regions) do add(cursor,r[1],false); add(r[1],r[2],true); cursor=r[2] end
  add(cursor,info.len,false)
  return parts
end
local function set_item(item,key,value)
  if not R.SetMediaItemInfo_Value(item,key,value) then error("アイテム属性を更新できません："..key,0) end
end
function Core.apply(project,entries,s)
  local ok,err=Core.validate(s); if not ok then return nil,err end
  local saved={}
  for index,e in ipairs(entries) do
    local now,info_err=Core.refresh_info(project,e.info)
    local label=e.info and e.info.name or ("#"..index)
    if not now then return nil,string.format("対象が見つかりません：%s（%s）",label,info_err or "不明なエラー") end
    if now.locked then return nil,string.format("ロックされたアイテムがあります：%s",now.name or label) end
    if Core.chunk(now)~=e.chunk then return nil,string.format("解析後に対象が変更されています：%s",now.name or label) end
    e.info=now
    saved[#saved+1]={info=now,chunk=e.chunk,fragments={now.item},touched=false}
  end
  if #saved==0 then return nil,"処理対象がありません。" end
  local produced,changed={},0
  R.Undo_BeginBlock2(project); R.PreventUIRefresh(1)
  local success,detail=xpcall(function()
    for ei,e in ipairs(entries) do
      local info=e.info; local parts=Core.plan(info,e.regions,s)
      local no_boundary_change=s.action=="split" and #parts==1
        and not (parts[1].sound and (s.fade_in_on or s.fade_out_on))
      if no_boundary_change then
        produced[#produced+1]=info.item
      else
        saved[ei].touched=true
        local original_in=max(0,R.GetMediaItemInfo_Value(info.item,"D_FADEINLEN"),R.GetMediaItemInfo_Value(info.item,"D_FADEINLEN_AUTO"))
        local original_out=max(0,R.GetMediaItemInfo_Value(info.item,"D_FADEOUTLEN"),R.GetMediaItemInfo_Value(info.item,"D_FADEOUTLEN_AUTO"))
        local piece=info.item
        for i=#parts,2,-1 do
          local right=R.SplitMediaItem(piece,info.pos+parts[i].a)
          if not right then error("アイテムを分割できません。",0) end
          saved[ei].fragments[#saved[ei].fragments+1]=right
          parts[i].item=right; changed=changed+1
        end
        parts[1].item=piece
        for _,p in ipairs(parts) do
          if not p.keep then
            if not R.DeleteTrackMediaItem(info.track,p.item) then error("無音部分を削除できません。",0) end
            changed=changed+1
          else
            if abs(p.dest-(info.pos+p.a))>1e-10 then
              if not R.SetMediaItemPosition(p.item,p.dest,false) then error("アイテムを移動できません。",0) end
              changed=changed+1
            end
            local dur=p.b-p.a
            local fi=p.a<1e-10 and original_in or 0
            local fo=abs(p.b-info.len)<1e-10 and original_out or 0
            if p.sound and s.fade_in_on then fi=s.fade_in/1000 end
            if p.sound and s.fade_out_on then fo=s.fade_out/1000 end
            fi,fo=min(fi,dur),min(fo,dur)
            if fi+fo>dur then local k=dur/(fi+fo); fi,fo=fi*k,fo*k end
            set_item(p.item,"D_FADEINLEN_AUTO",-1); set_item(p.item,"D_FADEOUTLEN_AUTO",-1)
            set_item(p.item,"D_FADEINLEN",fi); set_item(p.item,"D_FADEOUTLEN",fo)
            if p.sound and s.fade_in_on then set_item(p.item,"C_FADEINSHAPE",0); set_item(p.item,"D_FADEINDIR",0) end
            if p.sound and s.fade_out_on then set_item(p.item,"C_FADEOUTSHAPE",0); set_item(p.item,"D_FADEOUTDIR",0) end
            R.SetMediaItemSelected(p.item,true)
            produced[#produced+1]=p.item
          end
        end
      end
    end
  end,debug.traceback)
  local restored=true
  if not success then
    for _,v in ipairs(saved) do if v.touched then
      if #v.fragments==1 and valid_item(project,v.fragments[1]) then
        local call,result=pcall(R.SetItemStateChunk,v.fragments[1],v.chunk,false)
        if not call or not result then restored=false end
      else
        local deleted=true
        for _,item in ipairs(v.fragments) do
          if valid_item(project,item) then
            local call,result=pcall(R.DeleteTrackMediaItem,v.info.track,item)
            if not call or not result then deleted=false;restored=false end
          end
        end
        if deleted then
          local call,result=pcall(function()
            local item=R.AddMediaItemToTrack(v.info.track)
            return item and R.SetItemStateChunk(item,v.chunk,false)
          end)
          if not call or not result then restored=false end
        end
      end
     end
    end
  end
  R.PreventUIRefresh(-1); R.UpdateArrange()
  R.Undo_EndBlock2(project,success and "Auto Trim / Split" or "Auto Trim / Split (restored after error)",4)
  if not success then
    R.ShowConsoleMsg("Auto Trim / Split:\n"..BLT.publicError(detail).."\n")
    return nil,restored and "処理を中止し、元のアイテムを復元しました。" or "復元できない項目があります。REAPERのUndoで戻してください。"
  end
  return {items=produced,count=#entries,changes=changed}
end

local SECTION="BLT_AUTO_TRIM_SPLIT"
local S=copy(Core.defaults)
for key,default in pairs(S) do
  if type(default)~="number" then
    local v=R.GetExtState(SECTION,key)
    if v~="" then
      if type(default)=="boolean" then S[key]=v=="1"
      elseif key=="basis" and (v=="peak" or v=="lufs") then S[key]=v
      elseif key=="action" and (v=="delete" or v=="split") then S[key]=v end
    end
  end
end

local PROFILE_NUMERIC_KEYS={"open","close","min_open","min_close","pre","post","fade_in","fade_out"}
local PROFILE_DEFAULTS={
  peak={open=-61,close=-61,min_open=1000,min_close=165,pre=1,post=15,fade_in=1,fade_out=20},
  lufs={open=-55,close=-55,min_open=1100,min_close=15,pre=1,post=15,fade_in=1,fade_out=20},
}
local function saved_profile_number(basis,key,default)
  local n=tonumber(R.GetExtState(SECTION,basis.."_"..key))
  if not finite(n) then n=default end
  local r=Core.ranges[key]
  return r and Core.quantize(key,clamp(n,r[1],r[2])) or n
end

local profile_state={peak={},lufs={}}
for _,basis in ipairs({"peak","lufs"}) do
  local p=profile_state[basis]
  for _,key in ipairs(PROFILE_NUMERIC_KEYS) do
    p[key]=saved_profile_number(basis,key,PROFILE_DEFAULTS[basis][key])
  end
  p.close=min(p.close,p.open)
end

local function load_profile(basis)
  local p=profile_state[basis]
  for _,key in ipairs(PROFILE_NUMERIC_KEYS) do S[key]=p[key] end
end
local function stash_profile()
  local p=profile_state[S.basis]
  for _,key in ipairs(PROFILE_NUMERIC_KEYS) do p[key]=S[key] end
end
load_profile(S.basis)

local A={project=R.EnumProjects(-1,""),queue={},index=1,selection_key="",skipped=0,selection_total=0,
  ready=false,regions={},raw={},message="",bad=false,poll_at=0,zoom=1,view_start=0,
  audio_cache={},long_lufs_approved={},wave_surface_dirty=true,settings_pending=false,settings_due=0}
local function persist()
  stash_profile()
  for k,v in pairs(S) do
    if type(v)~="number" or not Core.ranges[k] then
      BLT.store(SECTION,k,type(v)=="boolean" and (v and "1" or "0") or tostring(v),true)
    end
  end
  for basis,p in pairs(profile_state) do
    for _,key in ipairs(PROFILE_NUMERIC_KEYS) do
      BLT.store(SECTION,basis.."_"..key,tostring(p[key]),true)
    end
  end
end
local function notice(text,bad) A.message=bad and BLT.publicError(text) or tostring(text or ''); A.bad=bad or false end
local function invalidate_wave_surface(full)
  if full then A.wave_cache=nil end
  A.wave_surface_dirty=true
end
local function cache_slot(info,chunk)
  local key=info.guid or tostring(info.item)
  local e=A.audio_cache[key]
  if not e or e.chunk~=chunk then
    A.audio_cache={}
    e={chunk=chunk}; A.audio_cache[key]=e
  end
  return e
end
local function cached_audio(info,chunk,basis)
  local cached=cache_slot(info,chunk)[basis]
  if not cached then return nil end
  local bound=copy(cached)
  bound.info=info
  bound.project=A.project
  bound.chunk=chunk
  return bound
end
local function store_audio(data)
  if not data or not data.info or not data.chunk then return end
  A.audio_cache={}
  cache_slot(data.info,data.chunk)[data.mode]=data
end
local function stop_jobs()
  Core.dispose(A.analysis); A.analysis=nil; A.detector=nil; A.batch=nil
end
local function long_lufs_key(info)
  return info and (info.guid or tostring(info.item)) or nil
end
local function prune_long_lufs_approvals()
  local keep={}
  for _,info in ipairs(A.queue or {}) do
    local key=long_lufs_key(info)
    if key and A.long_lufs_approved[key] then keep[key]=true end
  end
  A.long_lufs_approved=keep
end
local function confirm_long_lufs(info,basis)
  if basis~="lufs" or not info or info.len<=Core.LONG_LUFS_WARNING_SECONDS then return true end
  local key=long_lufs_key(info)
  if key and A.long_lufs_approved[key] then return true end
  local message=string.format(
    "ファイルが長いため、解析中および結果を表示している間はメモリ使用量が増えます。よろしいですか？\n\n%s\n長さ：%.1f分\n\n［実行］する場合は OK、［キャンセル］する場合はキャンセルを押してください。\nキャンセルしたアイテムは選択解除されます。",
    info.name or "Audio item",info.len/60)
  if Language.mb(message,"Auto Trim / Split | 長尺LUFS解析",1)==1 then
    if key then A.long_lufs_approved[key]=true end
    return true
  end
  if valid_item(A.project,info.item) then R.SetMediaItemSelected(info.item,false) end
  R.UpdateArrange()
  return false
end
local function detect_preview()
  A.ready=false; A.regions={}; A.raw={}; A.detector=nil
  invalidate_wave_surface()
  if A.data then A.detector=Core.detector(A.data,S); A.detector.context="preview" end
end
local function start_preview(reset_view)
 if not Media.ready() then return end
  A.settings_pending=false; A.settings_due=0
  stop_jobs(); A.data=nil; A.ready=false; A.regions={}; A.raw={}
  invalidate_wave_surface(true)
  if reset_view~=false then A.zoom=1; A.view_start=0 end
  local canceled=0
  while true do
    local info=A.queue[A.index]
    if not info then
      local had_cache=next(A.audio_cache or {})~=nil
      A.audio_cache={};A.long_lufs_approved={}
      if had_cache then collectgarbage("collect") end
      if canceled>0 then
        notice(string.format("長尺アイテム%d件のLUFS解析をキャンセルし、選択を解除しました。",canceled))
      else
        notice("音声アイテムを選択してください。"..(A.skipped>0 and (" 対象外："..A.skipped.."個") or ""))
      end
      return
    end
    local fresh,err=Core.info(A.project,info.item)
    if not fresh then error(err,0) end
    if fresh.len>Core.MAX_ITEM_SECONDS then error("1アイテムは60分以内にしてください。",0) end
    A.queue[A.index]=fresh
    local chunk=Core.chunk(fresh)
    local cached=cached_audio(fresh,chunk,S.basis)
    if cached then
      A.data=cached
      detect_preview()
      local prefix=canceled>0 and string.format("長尺アイテム%d件の選択を解除しました。 ",canceled) or ""
      notice(prefix..(S.basis=="peak" and "Peakデータをキャッシュから読み込みました。" or "Loudnessデータをキャッシュから読み込みました。"))
      return
    end
    if confirm_long_lufs(fresh,S.basis) then
      A.analysis=Core.start(A.project,fresh,S.basis,chunk); A.analysis.context="preview"
      local prefix=canceled>0 and string.format("長尺アイテム%d件の選択を解除しました。 ",canceled) or ""
      notice(prefix..(S.basis=="peak" and "Peakを取得しています。" or "ラウドネスを解析しています。"))
      return
    end
    canceled=canceled+1
    A.queue,A.selection_key,A.skipped=Core.selection(A.project); A.index=1
    A.selection_total=#A.queue
    prune_long_lufs_approvals()
    A.revision=R.GetProjectStateChangeCount(A.project)
  end
end
local function sync_selection()
 if not Media.ready() then return end
  A.queue,A.selection_key,A.skipped=Core.selection(A.project); A.index=1
  A.selection_total=#A.queue
  prune_long_lufs_approvals()
  A.revision=R.GetProjectStateChangeCount(A.project)
  start_preview(true)
end
local function settings_changed()
  A.settings_pending=false; A.settings_due=0
  persist(); detect_preview()
  if A.data then notice("プレビューを更新しています。") end
end
local function schedule_settings_changed()
  stash_profile()
  A.settings_pending=true
  A.settings_due=R.time_precise()+0.15
end

local function flush_scheduled_settings()
  if not A.settings_pending then return false end
  A.settings_pending=false; A.settings_due=0
  persist(); detect_preview()
  if A.data then notice("プレビューを更新しています。") end
  return true
end
local function set_basis(value)
  if value~="peak" and value~="lufs" then return end
  if S.basis==value then return end
  stash_profile()
  S.basis=value
  load_profile(value)
  persist()
  start_preview(false)
end

local function fail(err)
  BLT.cleanup(stop_jobs); A.ready=false
  notice(err,true)
  BLT.recoverInput(A,err)
end
local function guarded(fn)
  local ok,err=xpcall(fn,debug.traceback); if not ok then fail(err) end
end
local function batch_progress()
  local b=A.batch
  if not b then return 0 end
  local total=max(1e-9,b.total_work or 0)
  local done=b.done_work or 0
  local current=0
  if A.analysis and A.analysis.info then
    local f=clamp(A.analysis.offset/max(1,A.analysis.total),0,1)
    current=(A.analysis.info.len or 0)*(0.96*f)
  elseif A.detector and A.detector.context=="batch" and A.detector.data and A.detector.data.info then
    local bins=max(1,#(A.detector.data.peak or {}))
    local f=clamp((A.detector.i-1)/bins,0,1)
    current=(A.detector.data.info.len or 0)*(0.96+0.04*f)
  elseif b.i and b.i>#b.list then
    return 1
  end
  return clamp((done+current)/total,0,1)
end

local function batch_next()
  local b=A.batch
  if b.i>#b.list then
    local result,err=Core.apply(A.project,b.entries,b.settings)
    if not result then error(err,0) end
    local all=b.settings.all
    A.batch=nil; A.analysis=nil; A.detector=nil; A.data=nil; A.ready=false
    if all then A.queue={}; A.index=1
    else table.remove(A.queue,A.index); if A.index>#A.queue then A.index=1 end end
    local _,key=Core.selection(A.project); A.selection_key=key
    A.revision=R.GetProjectStateChangeCount(A.project)
    start_preview(true)
    notice(string.format("%dアイテムを処理しました。%s",result.count,#A.queue>0 and "次の対象を表示しています。" or "完了です。"))
    if BLT.completed then BLT.completed(result) end
    return
  end
  local info,info_err=Core.refresh_info(A.project,b.list[b.i])
  if not info then error(info_err or "対象アイテムが見つかりません。",0) end
  if info.len>Core.MAX_ITEM_SECONDS then error("1アイテムは60分以内にしてください。",0) end
  if info.locked then error("ロックされたアイテムがあります："..(info.name or tostring(b.i)),0) end
  if not confirm_long_lufs(info,b.settings.basis) then
    sync_selection()
    notice("長尺アイテムのLUFS解析をキャンセルし、選択を解除しました。バッチ処理は開始前の状態で中止しました。")
    return
  end
  b.list[b.i]=info
  local chunk=Core.chunk(info)
  A.analysis=Core.start(A.project,info,b.settings.basis,chunk); A.analysis.context="batch"
end
local function execute()
 if not A.job and not A.busy and not A.batch and not Media.ready() then return end
  if A.settings_pending then flush_scheduled_settings() end
  if A.batch then stop_jobs(); start_preview(false); notice("解析を中止しました。アイテムは変更していません。"); return end
  if not A.ready or not A.data then notice("プレビューの解析完了を待ってください。",true); return end
  local list={}
  if S.all then for _,v in ipairs(A.queue) do list[#list+1]=v end
  else list[1]=A.queue[A.index] end
  for i,v in ipairs(list) do
    local info,err=Core.refresh_info(A.project,v)
    if not info then error(err,0) end
    if info.len>Core.MAX_ITEM_SECONDS then error("1アイテムは60分以内にしてください。",0) end
    if info.locked then error("ロックされたアイテムがあります。ロックを解除してください。",0) end
    if S.basis=="lufs" and info.channels>2 then error("LUFS-Mはモノ／ステレオ対応です。多チャンネルはピークを選択してください。",0) end
    if not confirm_long_lufs(info,S.basis) then
      sync_selection()
      notice("長尺アイテムのLUFS解析をキャンセルし、選択を解除しました。")
      return
    end
    list[i]=info
  end
  local total_work=0
  for i=1,#list do total_work=total_work+(list[i].len or 0) end
  A.batch={list=list,i=1,settings=copy(S),entries={},
    total_work=total_work,done_work=0}
  A.analysis=nil;A.detector=nil;A.data=nil;A.audio_cache={};A.ready=false;invalidate_wave_surface(true);collectgarbage("collect")
  notice("実行用に全対象を再解析しています。")
  batch_next()
end
local function work_step()
 if not Media.ready() then return end
  local until_time=R.time_precise()+0.012
  while R.time_precise()<until_time do
    if A.analysis then
      local j=A.analysis
      if Core.read_step(j) then
        A.analysis=nil
        if j.context=="preview" then store_audio(j);A.data=j end
        A.detector=Core.detector(j,A.batch and A.batch.settings or S)
        A.detector.context=j.context
        invalidate_wave_surface(true)
      end
    elseif A.detector then
      local d=A.detector
      if Core.detect_step(d,32768) then
        A.detector=nil
        if d.context=="batch" then
          local b=A.batch
          b.entries[#b.entries+1]={info=d.data.info,chunk=d.data.chunk,regions=d.regions}
          b.done_work=(b.done_work or 0)+(d.data.info.len or 0)
          b.i=b.i+1
          d.data=nil;collectgarbage("step",400)
          batch_next() -- may immediately provide another cached detector/job
        else
          A.regions,A.raw,A.ready=d.regions,d.raw,true
          invalidate_wave_surface()
          notice(#d.regions==0 and (S.action=="delete" and "音あり区間は0です。実行すると対象全体を削除します。" or "分割境界はありません。")
            or string.format("%d区間を検出。設定を調整してから実行できます。",#d.regions))
          break
        end
      end
    else
      break
    end
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
 Language.mb('ReaImGui 0.10以降と js_ReaScriptAPI が必要です。ReaPackで導入・更新してください。','Auto Trim / Split | エラー',0)
 return
end
local W,H=722,728
local ok,Host=pcall(BLT.CanvasHost.new,R,'BLT Auto Trim Split',W,H+26,SECTION)
if not ok then Language.mb(tostring(Host),'Auto Trim / Split | エラー',0);return end
Host.minWidth,Host.minHeight,Host.persistSize=560,646,true
local savedW,savedH=tonumber(R.GetExtState(SECTION,'window_w')),tonumber(R.GetExtState(SECTION,'window_h'))
Host.width=finite(savedW) and clamp(savedW,560,1500) or W
Host.height=finite(savedH) and clamp(savedH,646,1526) or H+26
local I,ctx,g=Host.I,Host.ctx,Host.g
local C={
 bg={.018,.030,.055},bg2={.030,.090,.180},panel={.040,.068,.110},panel2={.055,.125,.205},
 field={.018,.040,.080},edge={.145,.285,.445},edge2={.360,.650,.900},
 text={.955,.980,1},muted={.690,.780,.875},faint={.390,.505,.635},disabled={.43,.46,.51},
 accent={.120,.490,.980},accent2={.650,.895,1},accent3={.045,.235,.520},ice={.650,.895,1},
 focus={.225,.610,1},focus2={.690,.900,1},ink={.018,.075,.160},
 hover={.430,.790,1},warn={1,.755,.490},red={1,.18,.26},quiet={.300,.360,.440}}
local U=BLT.Controls.new(g,R.time_precise,C)
U.font,U.minFontSize=Host.faces[1],7
local UI={}
local shell,menu
local awakeUntil=R.time_precise()+6.5
local function wake() awakeUntil=R.time_precise()+6.5 end
local numericKeys={'open','close','min_open','min_close','pre','post','fade_in','fade_out'}
local numeric={}
local function applyNumber(key,raw)
 local value=tonumber(raw)
 if not finite(value) then U:flash('field_'..key);notice('数値を入力できなかったため、元の値へ戻しました。',true);return end
 local old=S[key]
 local success,clipped=Core.set_number(S,key,value)
 if not success then notice(clipped,true);return end
 if clipped then U:flash('field_'..key) end
 if S[key]~=old then schedule_settings_changed();wake() end
end
local function pending()
 for _,key in ipairs(numericKeys) do
  local state=U.states['field_'..key]
  if state and state.pending~=nil then local text=state.pending;state.pending=nil;applyNumber(key,text) end
 end
end
local function commit()
 if U.editor and U.editor.edit then U.editor:close(false) end
 pending()
 if A.settings_pending then flush_scheduled_settings() end
 return true
end
local popupLayout={width=292,rowHeight=29,headerHeight=36,visiblePresets=8,hoverDelay=1}
menu=BLT.PresetMenu.new(Host,U,{presets=Presets,language=Language,layout=popupLayout,commit=commit,busy=function() return A.batch~=nil end})
shell=BLT.Shell.new(Host,U,R,{
 title='AUTO TRIM / SPLIT',subtitle='SILENCE DETECTION / TRIM  スレッショルドによる無音検出・区間処理',
 barTitle='A U T O   T R I M   /   S P L I T',section=SECTION,persist=true,
 layout={iconX=W-102,iconY=9,iconScale=.78,footerSize=8},
 language=Language.code,languageChanged=Language.set,translate=Language.message,
 store=BLT.store,headerIcon=BLT.AutoTrimIcon,iconMode=function() return S.basis end,
 stepPreset=function(direction) commit();Presets.step(direction) end,
 drawPresets=function(owner) menu:draw(owner) end,presetSize=function() return menu:size() end,dirty=Presets.dirty})
U.editor=BLT.TextInput.new(Host,U,shell.typography)
BLT.attachPresets({R=R,section=SECTION,defaults=Core.defaults,wake=wake,
 capture=function() return S end,
 valid=function(v) return Core.validate(v)~=nil and (v.basis=='peak' or v.basis=='lufs') and (v.action=='delete' or v.action=='split') end,
 apply=function(v) for k,value in pairs(v) do S[k]=value end;settings_changed() end,
 busy=function() return A.batch~=nil end,commit=commit,cancelEdit=function() U.editor:close(true);U.capture=nil end})
BLT.recoverInput=function(_,err)
 U.editor:close(true);U.capture=nil;U.down=false
 local execution=U.states.execute;if execution then execution.busy=false end
 wake();BLT.logError(err)
end
Media.state=A;Media.onchange=wake
mediaGraphics.getchar=function() return Host.focused and 6 or 4 end
local density=BLT.Controls.compactScale
local wave=BLT.AutoTrimWave.new(Host,R,Core,A,S,C)
local scale,ox,oy,mouse_x,mouse_y=1,0,26-22,-1,-1
local hoverID,hoverHint
local quietFrame={glow=false,panel=true}
local function box(x,y,w,h)
 U:frame(x/density,y/density,w/density,h/density,quietFrame)
end
local function label(text,x,y,size,c,kind,w,h,flags,bold,literal)
 local shown=literal and tostring(text) or Language.message(text)
 g.setfont(1,Host.faces[kind or 1],max(7,floor(size*scale+.5)),bold and 98 or 0)
 g.set((c or C.text)[1],(c or C.text)[2],(c or C.text)[3],1)
 g.x,g.y=ox+x*scale,oy+y*scale
 g.drawstr(shown,flags or 0,ox+(x+(w or 700))*scale,oy+(y+(h or size+8))*scale)
end
local function right_label(text,right,y,size,c,kind,bold)
 local shown=Language.message(text)
 g.setfont(1,Host.faces[kind or 1],max(7,floor(size*scale+.5)),bold and 98 or 0)
 local width=g.measurestr(shown)/scale
 label(shown,right-width,y,size,c,kind,width+2,size+9,0,bold,true)
end
local function rect(x,y,w,h,c,a) U:rect(x/density,y/density,w/density,h/density,c,a) end
local function gradient(x,y,w,h,a,b,alpha1,alpha2,vertical)
 local aa1,aa2=alpha1 or 1,alpha2==nil and (alpha1 or 1) or alpha2
 local n=max(1,(vertical and h or w)*scale)
 local dr,dg,db,da=(b[1]-a[1])/n,(b[2]-a[2])/n,(b[3]-a[3])/n,(aa2-aa1)/n
 g.gradrect(ox+x*scale,oy+y*scale,w*scale,h*scale,a[1],a[2],a[3],aa1,
  vertical and 0 or dr,vertical and 0 or dg,vertical and 0 or db,vertical and 0 or da,
  vertical and dr or 0,vertical and dg or 0,vertical and db or 0,vertical and da or 0)
end
local function inside(x,y,w,h) return mouse_x>=x and mouse_x<x+w and mouse_y>=y and mouse_y<y+h end
local function hint(id,text,x,y,w,h,enabled)
 if enabled~=false and not shell.popupOpen and not U.editor.edit and inside(x,y,w,h) then hoverID,hoverHint=id,Language.message(text) end
end
local function fmt(n)
 if abs(n-floor(n+.5))<1e-8 then return tostring(floor(n+.5)) end
 return string.format('%.2f',n):gsub('0+$',''):gsub('%.$','')
end
for _,key in ipairs(numericKeys) do
 local range=Core.ranges[key];local step=Core.steps[key] or 1
 numeric[key]={kind='number',min=range[1],max=range[2],step=step,
  fineStep=Core.precision[key]==0 and max(1,step*.1)/step or .1,
  rebaseDrag=true,dragDistance=3/density,size=20.5/density,minSize=12/density,
  face=Host.faces[3],bold=true,align='right',calibrate=false,opticalCenter=true,
  inset=9/density,valueInset=8/density,gap=8/density,suffixSize=8.8/density,format=fmt,
  normalize=function(raw)
   local value=tonumber(raw);if not finite(value) then return nil,true end
   local candidate=copy(S);local success,clipped=Core.set_number(candidate,key,value)
   return success and candidate[key] or nil,clipped
  end}
end
local choiceOptions={led='left',ledScale=44/(44*density),size=15/density,bold=true,center=false,
 captionY=4/density,captionHeight=10/density,captionSize=7/density,captionAlign='right',captionFace=Host.faces[3],labelY=0,labelHeight=44/density}
local segmentOptions={led='top',ledScale=27/(44*density),size=11/density,bold=true}
local switchOptions={background=false,showState=false,switchScale=26/(44*density),size=11.2/density}
local goldOptions={size=13/density,stateSize=9/density,ledScale=44/(44*density),bold=true}
local execution={cancelable=true,autoComplete=false,finishWhenDisabled=true,captionY=2/density,captionHeight=11/density,captionSize=8/density,
 labelY=13/density,labelHeight=27/density,size=15/density,bold=true}
local function choose(id,text,code,x,y,w,h,active,action,tip,enabled,options)
 options=options or choiceOptions
 options.selected,options.enabled,options.secondaryText=active,enabled~=false,code
 if U:button(id,Language.text(text),x/density,y/density,w/density,h/density,options) then commit();action();wake() end
 hint(id,tip,x,y,w,h,enabled)
end
local function choice_card(id,title,code,x,y,w,h,active,fn,tip,enabled)
 choose(id,title,code,x,y,w,h,active,fn,tip,enabled)
end
local function segment_button(id,title,x,y,w,h,active,fn,tip,enabled)
 choose(id,title,nil,x,y,w,h,active,fn,tip,enabled,segmentOptions)
end
local function toggle_switch(id,title,x,y,w,checked,fn,tip,enabled)
 local value,clicked,hitWidth=U:toggle(id,Language.text(title),checked,x/density,y/density,w/density,26/density,enabled,switchOptions)
 if clicked and value~=checked then commit();fn();wake() end
 hint(id,tip,x,y,hitWidth*density,26,enabled)
end
local function toggle(key) S[key]=not S[key];settings_changed() end
local function set_choice(key,value) S[key]=value;settings_changed() end
local function edge_mode_button(x,y,w,h,action,enabled)
 goldOptions.enabled=enabled
 goldOptions.onText=Language.text('ON / 両端のみ')
 local value,clicked=U:gold('edge_mode','EDGE MODE',S.edge_mode,x/density,y/density,w/density,h/density,goldOptions)
 if clicked and value~=S.edge_mode then commit();action();wake() end
 hint('edge_mode','ON：最初と最後の有効区間の外側だけを処理します。内部の無音は残し、プリ／ポストロールは外側の両端に適用します。',x,y,w,h,enabled)
end
local function field(key,title,x,y,w,unit,tip,enabled)
 enabled=enabled~=false and not A.batch
 if title then label(title,x,y-17,9.6,C.muted,1,w,15,0,true) end
 local options=numeric[key];options.enabled,options.suffix=enabled,unit
 local range=Core.ranges[key];options.min,options.max=range[1],range[2]
 if key=='open' or key=='close' then
  local other=key=='open' and 'close' or 'open'
  if S.relative then options.min=max(range[1],range[1]+S[key]-S[other]);options.max=min(range[2],range[2]+S[key]-S[other])
  elseif key=='open' then options.min=max(options.min,S.close) else options.max=min(options.max,S.open) end
 end
 local value=U:field('field_'..key,S[key],x/density,y/density,w/density,32/density,options)
 if value~=S[key] then applyNumber(key,value) end
 hint('field_'..key,(tip or title or key)..' ／ 上下ドラッグ・ホイール：'..fmt(Core.steps[key] or 1)..'刻み',x,y,w,32,enabled)
end
local function draw_glass_group(x,y,w,h,title)
 box(x,y,w,h);label(title,x+12,y+6,7.5,C.faint,3,w-24,12,0,true)
end
local function runExecute()
 commit();execute();wake()
end
local function draw_primary_button(id,text,x,y,w,h,tip,enabled)
 execution.enabled,execution.busy,execution.progress=enabled~=false,A.batch~=nil,A.batch and batch_progress() or nil
 execution.caption=A.batch and 'ANALYZING' or 'EXECUTE'
 if U:execute(id,Language.text(text),x/density,y/density,w/density,h/density,execution) then runExecute() end
 hint(id,tip,x,y,w,h,enabled)
end
BLT.completed=function()
 U.now=R.time_precise();U:complete('execute',312/density,44/density);wake()
end
local function waveform()
 local x,y,w,h=22,132,678,174
 box(x,y,w,h)
 local data=A.data;local info=data and data.info or A.queue[A.index]
 label('WAVEFORM PREVIEW',x+14,y+8,8,C.faint,3,150,13,0,true)
 right_label(S.basis=='peak' and 'PEAK / dBFS' or 'OPEN LUFS-M  /  CLOSE FAST',x+w-13,y+8,7.5,C.muted,3,true)
 if not data then
  wave:clear()
  local message=A.analysis and (A.analysis.mode=='peak' and 'Peakを取得しています…' or 'ラウドネスを解析しています…') or '音声アイテムを選択してください'
  label(message,x+24,y+55,12,C.muted,1,w-48,32,5,false)
  if A.analysis then
   local progress=A.analysis.offset/max(1,A.analysis.total)
   rect(x+105,y+108,w-210,3,C.edge,.40);rect(x+105,y+108,(w-210)*progress,3,C.accent,.90)
  end
  return
 end
 local plotX,plotW=x+40,w-54
 if not A.batch then g.wheelRegion(ox+plotX*scale,oy+(y+29)*scale,plotW*scale,93*scale)end
 local span=info.len/A.zoom
 A.view_start=clamp(A.view_start,0,max(0,info.len-span))
 local start=A.view_start
 if inside(plotX,y+29,plotW,93) and not A.batch and not U.blocked and not U.editor.edit then
  if U.wheel~=0 then
   local direction=U.wheel>0 and 1 or -1
   if (g.mouse_cap&8)~=0 then A.view_start=clamp(A.view_start-direction*span*.12,0,max(0,info.len-span))
   else
    local fraction=clamp((mouse_x-plotX)/plotW,0,1);local anchor=start+fraction*span
    A.zoom=clamp(A.zoom*(direction>0 and 1.5 or 1/1.5),1,max(1,min(200,info.len/.005)))
    A.view_start=clamp(anchor-fraction*info.len/A.zoom,0,max(0,info.len-info.len/A.zoom))
   end
   U.wheel=0;span=info.len/A.zoom;start=A.view_start;invalidate_wave_surface(true);wake()
  end
  local time=start+(mouse_x-plotX)/plotW*span;local index=clamp(floor(time*1000)+1,1,#data.peak)
  local tip=S.basis=='lufs' and string.format('位置 %.3f s / Peak %.1f dBFS / OPEN LUFS-M %.1f / CLOSE FAST %.1f',time,db(data.peak[index]),data.lufs[index] or -240,data.fast[index] or -240) or string.format('位置 %.3f s / Peak %.1f dBFS',time,db(data.peak[index]))
  hint('wave',tip,plotX,y+29,plotW,93,true)
 end
 wave:draw(ox+plotX*scale,oy+(y+29)*scale,plotW,57,28,start,span,scale)
 label(S.basis=='peak' and 'dBFS' or 'LU',x+4,y+84,7.5,C.faint,3,34,11,0,true)
 label('RESULT',x+4,y+128,7,C.faint,3,34,10,0,true)
 for i=0,4 do label(string.format('%.2f',start+span*i/4),plotX+plotW*i/4-21,y+143,7,C.faint,3,42,11,1,false) end
 label(string.format('×%.1f',A.zoom),plotX,y+157,7,C.faint,3,54,11,0,true)
 right_label('WHEEL ZOOM  /  SHIFT SCROLL',x+w-12,y+157,7,C.faint,3,true)
end

local function draw()
 shell:begin();U.active=Host.focused;U.themeEnabled=shell.theme.enabled
 local contentH=max(1,g.h-26)
 scale=max(.25,min(g.w/W,contentH/H));ox=(g.w-W*scale)/2;oy=26+(contentH-H*scale)/2-22*scale
 mouse_x,mouse_y=(g.mouse_x-ox)/scale,(g.mouse_y-oy)/scale
 g.set(C.bg[1],C.bg[2],C.bg[3],1);g.rect(0,0,g.w,g.h,1)
 U.scale,U.ox,U.oy=scale,ox,oy+22*scale
 shell:header(W)
 local editing=U.editor.edit~=nil;local key=g.getchar()
 if key==27 and not editing and not shell.popupOpen then A.closing=true end
 if (g.mouse_cap&24)==0 and (g.mouse_cap&36)~=0 and (key==122 or key==26) and not editing and not shell.popupOpen then
  if A.batch then notice(Language.code=='EN' and 'Cannot undo during processing.' or '処理中は元に戻せません。',true)
  elseif R.Undo_CanUndo2(A.project) then commit();stop_jobs();R.Undo_DoUndo2(A.project);R.UpdateArrange();sync_selection();wake() end
  key=0
 end
 local executeKey=key==13 and not editing and not shell.popupOpen
 if executeKey then key=0 end
 hoverID,hoverHint=nil,nil
 U:begin(density*scale,ox,oy,key)
 if executeKey then runExecute() end
  local info=A.queue[A.index]
  box(22,93,678,32)
  label(info and info.name or "",34,98,10.5,C.text,1,450,21,0,true)
  local selected_total=A.selection_total or #A.queue
  local remaining=#A.queue
  rect(514,97,174,24,C.field,1)
  right_label(string.format("選択 %02d   /   残り %02d",selected_total,remaining),680,100,10.5,
    remaining>0 and C.accent2 or C.muted,3,true)

  waveform()

  if UI.regions~=A.regions then
   UI.regions=A.regions;UI.duration=0
   for _,region in ipairs(A.regions) do UI.duration=UI.duration+region[2]-region[1] end
  end
  local total=UI.duration
  label(A.ready and string.format("検出区間  %d    合計  %.3f s",#A.regions,total) or "",26,312,13,A.ready and C.text or C.muted,1,420,21,0,true)
  right_label(S.action=="split" and "SPLIT / KEEP SILENCE" or (S.keep and "DELETE / KEEP TIMING" or "DELETE / PACK"),696,316,7.5,C.faint,3,true)

  label("検出基準",22,339,9.5,C.accent2,1,100,16,0,true)
  gradient(80,347,620,1,C.edge2,C.edge2,0.28,0.02)
  choice_card("basis_peak","ピークレベル","PEAK / dBFS",22,354,258,44,S.basis=="peak",function() set_basis("peak") end,"各1 ms区間の最大振幅。全チャンネルの最大値で検出します。",not A.batch)
  edge_mode_button(292,354,138,44,function() toggle("edge_mode") end,not A.batch)
  choice_card("basis_lufs","ラウドネス","M OPEN / FAST CLOSE",442,354,258,44,S.basis=="lufs",function() set_basis("lufs") end,"OPENはK特性＋400 msのLUFS-M、CLOSEは同じK特性＋100 msのFASTラウドネスで判定します。",not A.batch)

  label("検出レベル",22,405,9.5,C.accent2,1,105,16,0,true)
  local open_units=S.basis=="peak" and "dBFS" or "LUFS"
  local close_units=S.basis=="peak" and "dBFS" or "FAST"
  field("open","オープンスレッショルド",22,439,202,open_units,S.basis=="lufs" and "LUFS-M（400 ms）がこの値を超えると音あり区間を開始します。" or "この値を超えると音あり区間を開始します。")
  field("close","クローズスレッショルド",236,439,202,close_units,S.basis=="lufs" and "FASTラウドネス（100 ms）がこの値未満になると無音候補を開始します。" or "この値未満になると無音候補を開始します。")
  toggle_switch("relative","スレッショルド差を固定",454,445,246,S.relative,function() toggle("relative") end,"開閉スレッショルドの差を保ったまま両方を動かします。",not A.batch)
  label(string.format("DELTA  %.1f dB",S.open-S.close),493,469,7.5,C.faint,3,180,12,0,true)

  label("時間設定",22,485,9.5,C.accent2,1,90,16,0,true)
  local fw=159
  field("min_open","短い無音を無視",22,519,fw,"ms","この時間未満の無音は無視して、前後の音を同じ音あり区間として扱います。")
  field("min_close","最短クリップ長",194,519,fw,"ms","この時間未満の音あり区間は残すクリップとして採用しません。プリ／ポストロールを加える前の長さで判定します。")
  field("pre","プリロール",366,519,fw,"ms","正：開始を前へ広げる／負：開始を後ろへ縮める。元アイテム内に制限します。")
  field("post","ポストロール",538,519,162,"ms","正：終了を後ろへ広げる／負：終了を前へ縮める。重なった区間は結合します。")

  draw_glass_group(22,569,326,91,"FADE")
  toggle_switch("fade_in_on","フェードイン",34,587,142,S.fade_in_on,function() toggle("fade_in_on") end,"音あり区間に指定時間のフェードインを設定します。",not A.batch)
  toggle_switch("fade_out_on","フェードアウト",181,587,154,S.fade_out_on,function() toggle("fade_out_on") end,"音あり区間に指定時間のフェードアウトを設定します。",not A.batch)
  field("fade_in",nil,34,620,137,"ms","短い区間ではフェードが重ならない長さに縮めます。",S.fade_in_on)
  field("fade_out",nil,184,620,151,"ms","短い区間ではフェードが重ならない長さに縮めます。",S.fade_out_on)

  draw_glass_group(360,569,340,91,"PROCESS")
  segment_button("delete","無音部分を削除",372,587,151,27,S.action=="delete",function() set_choice("action","delete") end,"灰色の区間を削除し、青色の区間を残します。",not A.batch)
  segment_button("split","分割",531,587,157,27,S.action=="split",function() set_choice("action","split") end,"青・灰の境界で分割し、全ての区間を元の位置に残します。",not A.batch)
  toggle_switch("keep","削除した区間を詰める",372,620,316,S.action=="delete" and not S.keep,function() toggle("keep") end,"ON：無音部分を削除した後、残った検出区間を元アイテムの開始位置から隙間なく詰めます。",S.action=="delete" and not A.batch)

  local message=A.message
  if A.batch then
    local p=batch_progress()
    message=string.format("全選択を解析中  %d / %d    %d%%（解析完了後にまとめて編集）",min(A.batch.i,#A.batch.list),#A.batch.list,floor(p*100+0.5))
  elseif A.analysis then message=string.format(A.analysis.mode=="peak" and "Peak取得  %d%%" or "Loudness解析  %d%%",floor(100*A.analysis.offset/max(1,A.analysis.total))) end

  draw_primary_button("execute",A.batch and "処理を中止" or "処理を実行",190,686,312,44,"Enter：実行。編集は1回のUndoで元に戻せます。",A.batch or A.ready)
  toggle_switch("all","選択アイテムを一括処理",518,696,182,S.all,function()
    S.all=not S.all; persist(); if S.all then A.index=1; start_preview() else detect_preview() end
  end,"ON：先頭をプレビューして全選択へ適用。OFF：1つずつ処理して次へ。",not A.batch)
  pending()
  U:finish()
  pending()
  U.scale,U.ox,U.oy=scale,ox,oy+22*scale
  local bad=A.bad
  if Media.waiting then message=Media.message(SECTION);bad=false
  elseif BLT.notice then message,bad=BLT.notice,BLT.noticeBad end
  shell:footer(message~='' and message or (not A.ready and '音声アイテムを選択してください。' or ''),bad,W,H,'0.6.3')
  shell:drawBar()
  U.scale,U.ox,U.oy=density*scale,ox,oy
end
Host:bindShortcuts()
g.getchar=function(query)
 if query==65536 or query==65537 then return Host.focused and 6 or 4 end
 local key=Host.key
 if key>=97 and key<=122 then
  if (g.mouse_cap&4)~=0 then key=key-96
  elseif (g.mouse_cap&8)~=0 then key=key-32 end
 end
 return key,0
end
BLTShortcuts.install(R,g,{
 blocked=function() return U.editor.edit~=nil or shell.popupOpen or A.batch~=nil or A.closing end,
 localKey=function(k,cap) return k==27 or k==13 or k==9 or ((cap&24)==0 and (cap&36)~=0 and (k==122 or k==26)) end,
 beforeGlobal=commit})
local finalized=false
local function close()
 if finalized then return end
 finalized=true
 pcall(commit);pcall(stop_jobs);pcall(persist)
 pcall(wave.close,wave);pcall(Host.close,Host);pcall(shell.close,shell)
 A.closed=true
end
R.atexit(close)
local function poll(now)
 local project=R.EnumProjects(-1,'')
 if project~=A.project then stop_jobs();A.project=project;A.audio_cache={};A.long_lufs_approved={};guarded(sync_selection);wake() end
 Media.tick()
 if A.settings_pending and now>=A.settings_due then guarded(flush_scheduled_settings) end
 if Media.ready() and now>=A.poll_at then
  A.poll_at=now+.35
  local revision=R.GetProjectStateChangeCount(A.project)
  local key=Core.selection_key(A.project)
  if key~=A.selection_key then guarded(sync_selection);wake()
  elseif revision~=A.revision then
   local wasBatch=A.batch~=nil
   A.revision=revision
   local unchanged=not (A.analysis or A.detector or A.batch) and A.data and valid_item(A.project,A.data.info.item) and Core.chunk(A.data.info)==A.data.chunk
   if not unchanged then
    guarded(function() start_preview(true) end);wake()
    if wasBatch then notice('プロジェクトが変更されたため解析を中止しました。',true) end
   end
  end
 end
 if A.analysis or A.detector then guarded(work_step) end
 if BLT.noticeUntil and now>=BLT.noticeUntil then BLT.notice,BLT.noticeUntil=nil,nil;wake() end
end
local inputState,worldState={},{}
local function changed(state,...)
 local different=false
 for i=1,select('#',...) do local value=select(i,...);if state[i]~=value then state[i]=value;different=true end end
 return different
end
local function tooltip(now)
 if hoverID~=UI.hoverID then UI.hoverID,UI.hoverSince=hoverID,now end
 if hoverHint and not U.down and not shell.popupOpen and not U.editor.edit and now-(UI.hoverSince or now)>=.7 then
  I.PushFont(ctx,Host.font,12);I.SetTooltip(ctx,hoverHint);I.PopFont(ctx)
 end
end
local function run()
 if finalized then return end
 local begun=false
 local success,err=xpcall(function()
  local now=R.time_precise();poll(now);shell.theme.tick(now)
  local working=A.analysis or A.detector or A.batch
  if changed(worldState,A.ready,A.data,A.regions,#A.queue,A.index,A.message,A.bad,A.batch~=nil,A.analysis~=nil,A.detector~=nil,
   A.settings_pending,Media.waiting,Language.code,C.bg,Presets.current,BLT.noticeUntil,Host.requestReset,shell.icon.dirty) then awakeUntil=now+6.5 end
  local interactive=U.editor.edit or shell.popupOpen or Host.drag or shell.hoverID or U.capture
  local animating=U:executeAnimating('execute') or shell.icon:animating(now)
  if not working and now>=awakeUntil and not interactive and not animating and Host:idle(now) then
   U.now=now;shell.icon.lastTime=now;R.defer(run);return
  end
  if Host.idleWake then awakeUntil=now+6.5;Host.idleWake=nil end
  if Host.requestReset then Host.width,Host.height=W,H+26 end
  local shown=Host:begin();begun=true
  if shown then
   local cap=(Host.hovered or Host.focused or U.capture or Host.drag) and g.mouse_cap or 0
   if changed(inputState,g.mouse_x,g.mouse_y,cap,Host.key,g.w,g.h,Host.dpi,Host.originX,Host.originY,Host.focused) or
    g.mouse_wheel~=0 or (cap&1)~=0 or interactive then awakeUntil=now+6.5 end
   draw();tooltip(now)
  end
  local keep=Host:finish();begun=false
  if not keep or A.closing then close() else R.defer(run) end
 end,debug.traceback)
 if not success then
  if begun then pcall(Host.finish,Host) end
  close();Language.mb(BLT.publicError(err),'Auto Trim / Split | エラー',0)
 end
end
guarded(sync_selection)
run()
