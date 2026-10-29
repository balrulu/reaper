-- @description LOUDNESS TRACE
-- @version 0.8.7
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
  if self.nextRect then
   local b=self.nextRect;I.SetNextWindowPos(ctx,b.x,b.y);I.SetNextWindowSize(ctx,b.w,b.h,I.Cond_Always);self.nextRect=nil
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
  check(painter.b.compact);check(width);check(height);check(scale);check(self.combined);check(painter.dirty or false);check(painter.hot~='drag' and painter.hot or false);check(painter.presetOpen or false);check(painter.themeEnabled or false);check(painter.language)
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
function M.layout(w,compact)
 local b=M.layoutCache
 if b and b.width==w and b.compact==compact then return b end
 b={width=w,closeX=w-38,resetX=w-72,themeX=w-106}
 b.compact=compact;b.foldX=b.themeX-34
 b.languageX=b.foldX-26
 b.nextX=b.languageX-20;b.prevX=b.nextX-20;b.presetX=b.prevX-84
 if compact then b.resetX=b.closeX;b.themeX=w-72;b.foldX=w-106;b.languageX=w+500;b.presetX=w+500 end
 M.layoutCache=b;return b
end
function M.hit(b,x,y,w,h)
 if x<0 or x>=w or y<0 or y>=h then return nil end
 if x>=b.closeX then return 'close' end
 if b.compact then
  if x>=b.themeX then return 'theme' end
  if x>=b.foldX then return 'fold' end
  return 'drag'
 end
 if x>=b.resetX then return 'reset' end
 if x>=b.themeX then return 'theme' end
 if x>=b.foldX then return 'fold' end
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
  gfx.set(Chrome.mint[1],Chrome.mint[2],Chrome.mint[3],.88); gfx.x=14; gfx.y=ty; gfx.drawstr(p.fit(Chrome.titleText,math.max(0,math.min(presetX,b.foldX)-22)))

  if not b.compact then
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
  end
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

  end
  local fc=p.hot=='fold' and Chrome.mint or C.muted
  gfx.set(fc[1],fc[2],fc[3],p.hot=='fold' and .98 or .82)
  local cx,cy=b.foldX+17,Chrome.titleH*.5
  local d=b.compact and 1 or -1
  gfx.line(cx-5,cy-d*2,cx,cy+d*3,1);gfx.line(cx,cy+d*3,cx+5,cy-d*2,1)
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
 S.theme=BLTChameleon.new(themeAPI,C,{section=options.section or 'BLT_UI_DEMO',chrome=chrome,roles={ice='accent2',deep='accent3',disabled='faint'},special=ui.tones,
  store=options.persist and (options.store or api.SetExtState) or function() end,
  applied=function(restored,palette) ui.themeTones=not restored and palette.special or nil end,
  changed=function() if S.icon then S.icon.dirty=true end;if options.themeChanged then options.themeChanged() end end})
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
  self.layout=BLTChrome.layout(gfx.w,options.compact and options.compact() or false)
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
 local tips={fold={'縮小 / 展開','Collapse / Expand'},preset={'プリセットを選択','Choose a preset'},prev={'前のプリセット','Previous preset'},next={'次のプリセット','Next preset'},
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
    elseif self.hot=='fold' then if options.fold then options.fold() end
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

BLT.LoudnessTraceIcon=(function()
local M={width=87,height=54,modes={'trace','analyze'}}
local sin,pi=math.sin,math.pi
local function hash(n,salt) return (sin(n*12.9898+salt*78.233)*43758.5453)%1 end
function M.update(s,mode) s.analyzing=mode=='analyze' end
local function wave(x,t)
 local world=x+t*4.6
 return 7.2*sin(world*.105+.35)+3.8*sin(world*.047+1.55)+1.8*sin(world*.021+.4)
end
function M.draw(p,s,mode,time)
 local C=p.C;local speed=s.analyzing and 1.85 or 1;time=time*speed;s.phase=time
 p:rect(4,7,78,41,C.panel,.60)
 p:line(4,7,4,48,C.edge,.65);p:line(4,48,82,48,C.edge,.65)
 p:line(8,28,78,28,C.edge,.30)
 for x=0,74,2 do
  local a=math.max(0,math.min(1,x/8,(76-x)/8));local y,ny=28+wave(x,time),28+wave(x+2,time)
  p:line(5+x,y,7+x,ny,C.accent,.014*a,9)
  p:line(5+x,y,7+x,ny,C.accent,.065*a,4)
  p:line(5+x,y,7+x,ny,C.ice,.86*a,1)
 end
 local x=5+((time*9)%76);local y=28+wave(x-5,time)
 p:disc(x,y,7,C.accent,.025);p:disc(x,y,3.4,C.ice,.10);p:disc(x,y,1,C.text,.95)
end
function M.emit(s,n,p)
 p.x,p.y=7+hash(n,1)*72,28+wave(hash(n,1)*72,s.phase or 0)
 p.vx,p.vy=-5-hash(n,2)*8,4+hash(n,3)*9
 p.life,p.r,p.phase,p.sway,p.freq,p.glint=1.7+hash(n,4)*1.3,.45+hash(n,5)*.65,hash(n,6)*2*pi,1.5,1.4,n%6==0
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
local gfx,Host,U,shell,menu,controls
local mediaGraphics={}
local awakeUntil=0
local function wake_visuals() awakeUntil=reaper.time_precise()+6.5 end
local UI={}

local function create_media_gate(api,graphics)
 local M={waiting=false}
 local next_check=0;local ready=true;local settle=0;local last_active
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
 local function targets(project,all_items)
  local takes={};local invalid=false
  local all=all_items or (M.all_items and M.state and M.state.job)
  local count=all and api.CountMediaItems(project) or api.CountSelectedMediaItems(project)
  for i=0,count-1 do
   local item=all and api.GetMediaItem(project,i) or api.GetSelectedMediaItem(project,i)
   if not item then invalid=true
   else local take=api.GetActiveTake(item);if take then takes[take]=true end end
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
   M.waiting=waiting
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
 return M
end

local Media=create_media_gate(reaper,mediaGraphics)

local VERSION="0.8.5"
local MAX_HISTORY_ROWS=126000
local MAX_SAVE_BYTES=12*1024*1024
local Core = {}
local floor, min, max, sin, pi = math.floor, math.min, math.max, math.sin, math.pi
function Core.clamp(v, lo, hi) return max(lo, min(hi, v)) end
function Core.finite(v) return type(v)=="number" and v==v and v~=math.huge and v~=-math.huge end
function Core.round(v,digits)
  local factor=10^(digits or 0)
  return (v<0 and math.ceil(v*factor-.5) or floor(v*factor+.5))/factor
end

function Core.time_x(t, first, last, width) return (t-first)/(last-first)*width end
function Core.x_time(x, first, last, width) return first+x/width*(last-first) end
function Core.level_y(v, top, bottom, lo, hi)
  return top+(hi-v)/(hi-lo)*(bottom-top)
end
function Core.clip_level_line(x1,y1,x2,y2,top,bottom)
  if (y1<top and y2<top) or (y1>bottom and y2>bottom) then return end
  local dy=y2-y1
  if dy==0 then return x1,y1,x2,y2 end
  local a,b=(top-y1)/dy,(bottom-y1)/dy
  local first,last=max(0,min(a,b)),min(1,max(a,b))
  if last<=first then return end
  local dx=x2-x1
  return x1+dx*first,Core.clamp(y1+dy*first,top,bottom),x1+dx*last,Core.clamp(y1+dy*last,top,bottom)
end
function Core.clip_track(y,h,viewport)
  local top=max(0,y); local bottom=min(viewport,y+h)
  return top,max(0,bottom-top),top-y
end
function Core.tick_step(span,width)
  local raw=span/max(2,width/110)
  local power=10^floor(math.log(max(1e-9,raw),10))
  for _,n in ipairs({1,2,5,10}) do if n*power>=raw then return n*power end end
end
function Core.clock(t)
  local sign=t<0 and "-" or ""; t=math.abs(t)
  return string.format("%s%d:%06.3f",sign,floor(t/60),t%60)
end

Core.SILENCE=-150
function Core.db(e) return e>0 and max(Core.SILENCE,10*math.log(e,10)) or Core.SILENCE end
function Core.lufs(e) return e>0 and max(Core.SILENCE,-.691+10*math.log(e,10)) or Core.SILENCE end
function Core.lower(a,v)
  local l,h=1,#a+1
  while l<h do local m=(l+h)//2; if a[m]<v then l=m+1 else h=m end end
  return l
end
function Core.integrate(rows,tick)
  local sorted={}
  local gate=10^((-70+.691)/10)
  local nrows=#rows
  for i=1,nrows do local e=rows[i].energy; if e and e>gate then sorted[#sorted+1]=e end end
  table.sort(sorted)
  local sums,counts={},{}
  local sum,count=0,0
  local nsorted=#sorted
  local lower,lufs=Core.lower,Core.lufs
  local function prefix(i)
    local s,c=0,0
    while i>0 do s=s+(sums[i] or 0); c=c+(counts[i] or 0); i=i-(i&-i) end
    return s,c
  end
  for n=1,nrows do
    local r=rows[n]
    local e=r.energy
    if e and e>gate then
      sum=sum+e; count=count+1
      local i=lower(sorted,e)
      while i<=nsorted do sums[i]=(sums[i] or 0)+e; counts[i]=(counts[i] or 0)+1; i=i+(i&-i) end
    end
    if e then
      if count==0 then r.i=Core.SILENCE
      else
        local threshold=max(gate,sum/count*.1)
        local j=lower(sorted,threshold)
        -- BS.1770 uses strictly greater than the gate.
        while j<=nsorted and sorted[j]<=threshold do j=j+1 end
        local s,c=prefix(j-1)
        r.i=count>c and lufs((sum-s)/(count-c)) or Core.SILENCE
      end
    end
    r.energy=nil
    if tick and n%1000==0 then tick(.91+.04*n/nrows) end
  end
  return nrows>0 and rows[nrows].i or Core.SILENCE
end

Core.layouts={
 {id='mono',name='MONO · ch 1',order='M',channels=1,render=2,weights={1}},
 {id='stereo',name='STEREO · ch 1/2',order='L R',channels=2,render=2,weights={1,1}},
 {id='5.1',name='5.1 · L R C LFE Ls Rs',order='L R C LFE Ls Rs',channels=6,render=6,weights={1,1,1,0,1.41,1.41}},
 {id='7.1',name='7.1 · L R C LFE Lss Rss Lrs Rrs',order='L R C LFE Lss Rss Lrs Rrs',channels=8,render=8,weights={1,1,1,0,1.41,1.41,1,1}},
 {id='7.1-rear',name='7.1 · L R C LFE Lrs Rrs Lss Rss',order='L R C LFE Lrs Rrs Lss Rss',channels=8,render=8,weights={1,1,1,0,1,1,1.41,1.41}}
}
function Core.layout(id)
 for _,layout in ipairs(Core.layouts) do if layout.id==id then return layout end end
 error('測定レイアウトが不正です。',0)
end
function Core.check_channels(api,project,layout)
 local master=api.GetMasterTrack(project)
 assert(master and api.GetMediaTrackInfo_Value(master,'I_NCHAN')>=layout.channels,'マスターのチャンネル数が測定レイアウトより少ないため測定できません。')
end
Core.metrics={'s','m','i','rms','peak'}
local function build_lod(data,tick)
  data.lod={}
  for _,key in ipairs(Core.metrics) do

    local first={}
    for _,r in ipairs(data.rows) do
      local value=r[key];if value==nil then value=false end
      first[#first+1]=value;first[#first+1]=value
    end
    local levels={first}
    local n=#data.rows
    while n>1 do
      local prev,nextlevel=levels[#levels],{}
      for i=1,n,2 do
        local ai=(i-1)*2+1;local lo,hi=prev[ai],prev[ai+1]
        if lo==false then lo=nil end;if hi==false then hi=nil end
        if i<n then
          local bi=i*2+1;local blo,bhi=prev[bi],prev[bi+1]
          if blo==false then blo=nil end;if bhi==false then bhi=nil end
          if blo then lo=lo and min(lo,blo) or blo;hi=hi and max(hi,bhi) or bhi end
        end
        nextlevel[#nextlevel+1]=lo~=nil and lo or false;nextlevel[#nextlevel+1]=hi~=nil and hi or false
      end
      levels[#levels+1]=nextlevel;n=(n+1)//2
      if tick then tick(.98) end
    end
    data.lod[key]=levels
  end
end

function Core.live_tree()
  local T={v={},n={},sum={},count={},left={},right={},priority={},free={},root=0,serial=0,seed=17}
  local function update(i)
    local a,b=T.left[i],T.right[i]
    T.count[i]=T.n[i]+(T.count[a] or 0)+(T.count[b] or 0)
    T.sum[i]=T.v[i]*T.n[i]+(T.sum[a] or 0)+(T.sum[b] or 0)
    return i
  end
  local function rotate(i,left)
    local j=left and T.right[i] or T.left[i]
    if left then T.right[i]=T.left[j];T.left[j]=i else T.left[i]=T.right[j];T.right[j]=i end
    update(i);return update(j)
  end
  local function insert(i,v)
    if i==0 then
      i=table.remove(T.free)
      if not i then T.serial=T.serial+1;i=T.serial end
      T.seed=T.seed*48271%2147483647
      T.v[i]=v;T.n[i]=1;T.sum[i]=v;T.count[i]=1;T.left[i]=0;T.right[i]=0;T.priority[i]=T.seed
      return i
    end
    if v==T.v[i] then T.n[i]=T.n[i]+1
    elseif v<T.v[i] then T.left[i]=insert(T.left[i],v);if T.priority[T.left[i]]<T.priority[i] then return rotate(i,false) end
    else T.right[i]=insert(T.right[i],v);if T.priority[T.right[i]]<T.priority[i] then return rotate(i,true) end end
    return update(i)
  end
  local function merge(a,b)
    if a==0 then return b end;if b==0 then return a end
    if T.priority[a]<T.priority[b] then T.right[a]=merge(T.right[a],b);return update(a) end
    T.left[b]=merge(a,T.left[b]);return update(b)
  end
  local function remove(i,v)
    assert(i~=0,'集計データの対応が失われました。')
    if v<T.v[i] then T.left[i]=remove(T.left[i],v)
    elseif v>T.v[i] then T.right[i]=remove(T.right[i],v)
    elseif T.n[i]>1 then T.n[i]=T.n[i]-1
    else
      local root=merge(T.left[i],T.right[i]);T.v[i]=nil;T.n[i]=nil;T.sum[i]=nil;T.count[i]=nil
      T.left[i]=nil;T.right[i]=nil;T.priority[i]=nil;T.free[#T.free+1]=i;return root
    end
    return update(i)
  end
  function T.add(v) T.root=insert(T.root,v) end
  function T.remove(v) T.root=remove(T.root,v) end
  function T.above(v,inclusive)
    local i=T.root;local sum,count=0,0
    while i~=0 do
      if T.v[i]>v or (inclusive and T.v[i]==v) then
        local r=T.right[i];sum=sum+T.v[i]*T.n[i]+(T.sum[r] or 0);count=count+T.n[i]+(T.count[r] or 0);i=T.left[i]
      else i=T.right[i] end
    end
    return sum,count
  end
  function T.rank(n)
    local i=T.root
    while i~=0 do
      local before=T.count[T.left[i]] or 0
      if n<=before then i=T.left[i] elseif n<=before+T.n[i] then return T.v[i] else n=n-before-T.n[i];i=T.right[i] end
    end
  end
  return T
end
function Core.live_meter()
  local M={count=0,k={},r={},km=0,ks=0,rm=0}
  function M.feed(time,k,raw,peak)
    local i=M.count+1;M.count=i
    local slot=(i-1)%30+1;local rmsSlot=(i-1)%4+1
    M.km=max(0,M.km+k-(i>4 and (M.k[(i-5)%30+1] or 0) or 0))
    M.ks=max(0,M.ks+k-(M.k[slot] or 0));M.rm=max(0,M.rm+raw-(M.r[rmsSlot] or 0))
    M.k[slot]=k;M.r[rmsSlot]=raw
    return {time=time,peak=Core.db(peak*peak),m=i>=4 and Core.lufs(M.km/4) or nil,
      rms=i>=4 and Core.db(M.rm/4) or nil,s=i>=30 and Core.lufs(M.ks/30) or nil}
  end
  return M
end

-- Update only the affected min/max path, rather than rebuilding the full graph.
function Core.live_lod_append(seg,row)
  local count=#seg.rows;seg.lod=seg.lod or {}
  for _,key in ipairs(Core.metrics) do
    local levels=seg.lod[key] or {{}};seg.lod[key]=levels
    local index=count;local value=row[key];if value==nil then value=false end
    levels[1][index*2-1]=value;levels[1][index*2]=value
    local level,n=1,count
    while n>1 do
      local parent=(index+1)//2;local left=(parent-1)*4+1
      local prev=levels[level];local lo,hi=prev[left],prev[left+1]
      if lo==false then lo=nil;hi=nil end
      local blo,bhi=prev[left+2],prev[left+3]
      if blo~=nil and blo~=false then lo=lo and min(lo,blo) or blo;hi=hi and max(hi,bhi) or bhi end
      levels[level+1]=levels[level+1] or {};local dst=levels[level+1]
      dst[parent*2-1]=lo~=nil and lo or false;dst[parent*2]=hi~=nil and hi or false
      index=parent;n=(n+1)//2;level=level+1
    end
  end
end
function Core.live_after(rows,t)
  local lo,hi=1,#rows+1
  while lo<hi do local mid=(lo+hi)//2;if rows[mid].time<=t+1e-8 then lo=mid+1 else hi=mid end end
  return lo
end
function Core.live_view(previous,active,source,name)
  local out={source=source,name=name,segments={},rows=active.rows,integrated=active.integrated or Core.SILENCE,lra=active.lra}
  local total=0
  local function keep(seg,a,b)
    if b<=a+1e-8 then return end
    local first,last=Core.live_after(seg.rows,a),Core.live_after(seg.rows,b)-1
    if last<first then return end
    total=total+last-first+1
    out.segments[#out.segments+1]={first=a,last=b,rows=seg.rows,origin=seg.origin,lod=seg.lod,stamp=seg.stamp or 0,stale=seg.stale}
  end
  if previous then for _,seg in ipairs(previous.segments) do
    if seg.last<=active.first or seg.first>=active.last then keep(seg,seg.first,seg.last)
    else keep(seg,seg.first,min(seg.last,active.first));keep(seg,max(seg.first,active.last),seg.last) end
  end end
  keep(active,active.first,active.last)
  table.sort(out.segments,function(a,b)return a.first<b.first end)
  out.first=out.segments[1].first;out.last=out.segments[#out.segments].last;out.liveCount=total
  return out
end
-- Exact aggregate shared by offline and live histories. Each retained 400 ms / 3 s
-- window must lie within its surviving segment; boundary-crossing windows are excluded.
function Core.history_energy(row,key,first)
  local window=key=='m' and .4 or 3
  local v=row[key]
  if not Core.finite(v) or row.time-window<first-1e-7 then return nil end
  if key=='m' then return v> -70 and 10^((v+.691)/10) or nil end
  return v>=-70 and 10^(v/10) or nil
end
function Core.tree_integrated(tree)
  local n=tree.count[tree.root] or 0;if n==0 then return Core.SILENCE end
  local sum,count=tree.above(max(10^((-70+.691)/10),tree.sum[tree.root]/n*.1),false)
  return count>0 and Core.lufs(sum/count) or Core.SILENCE
end
function Core.tree_lra(tree)
  local n=tree.count[tree.root] or 0;if n==0 then return nil end
  local _,count=tree.above(max(1e-7,tree.sum[tree.root]/n*.01),true)
  if count==0 then return nil end
  local a=n-count+max(1,min(count,floor((count-1)*.10+1.5)))
  local b=n-count+max(1,min(count,floor((count-1)*.95+1.5)))
  return max(0,10*math.log(tree.rank(b)/tree.rank(a),10))
end
function Core.row_warning(row,targets)
  local a,b=targets.s,targets.m
  return ((row.s and row.s>a[1]+a[2]) or (row.m and row.m>b[1]+b[2])) and 1 or 0,
    ((row.s and row.s<a[1]-a[2]) or (row.m and row.m<b[1]-b[2])) and 1 or 0,
    row.peak and row.peak>=0 and 1 or 0
end
function Core.history_summary(previous,first,targets)
  local H={m=Core.live_tree(),s=Core.live_tree(),prefix=Core.live_tree(),parts={},first=first,last=first,
    warning={0,0,0},targets={s={targets.s[1],targets.s[2]},m={targets.m[1],targets.m[2]}}}
  local function warning(row,delta)
    local a,b,c=Core.row_warning(row,H.targets)
    H.warning[1]=H.warning[1]+a*delta;H.warning[2]=H.warning[2]+b*delta;H.warning[3]=H.warning[3]+c*delta
  end
  H.warning_row=warning
  for _,seg in ipairs(previous and previous.segments or {}) do
    local q={seg=seg,last=Core.live_after(seg.rows,seg.last)-1}
    local a=Core.live_after(seg.rows,seg.first)
    q.w=max(a,Core.live_after(seg.rows,first))
    q.m=max(q.w,Core.live_after(seg.rows,seg.first+.4-1e-7))
    q.s=max(q.w,Core.live_after(seg.rows,seg.first+3-1e-7))
    H.parts[#H.parts+1]=q
    for i=a,q.last do
      local row=seg.rows[i];warning(row,1)
      if row.m and row.time-.4>=seg.first-1e-7 and row.time<=first+1e-8 then H.prefixValid=true end
      for _,key in ipairs({'m','s'}) do
        local e=Core.history_energy(row,key,seg.first)
        if e then H[key].add(e);if key=='m' and row.time<=first+1e-8 then H.prefix.add(e) end end
      end
    end
  end
  function H.feed(row)
    local last=row.time
    assert(last>H.last,'測定時刻が逆転しています。')
    for _,q in ipairs(H.parts) do
      local seg=q.seg
      if last>seg.first+1e-8 and seg.last>first then
        for _,key in ipairs({'m','s','w'}) do
          local window=key=='m' and .4 or key=='s' and 3 or 0
          local edge=window==0 and last or last+window-1e-7
          local stop=min(q.last,Core.live_after(seg.rows,edge)-1)
          for i=q[key],stop do
            local r=seg.rows[i]
            if key=='w' then warning(r,-1) else local e=Core.history_energy(r,key,seg.first);if e then H[key].remove(e) end end
          end
          q[key]=max(q[key],stop+1)
        end
      end
    end
    for _,key in ipairs({'m','s'}) do
      local e=Core.history_energy(row,key,first)
      if e then H[key].add(e);if key=='m' then H.prefix.add(e) end end
    end
    warning(row,1);H.last=last
    if row.m and row.time-.4>=first-1e-7 then H.prefixValid=true end
    row.i=H.prefixValid and Core.tree_integrated(H.prefix) or nil
    return Core.tree_integrated(H.m),Core.tree_lra(H.s)
  end
  return H
end

Core.offline={memory='BLT_LoudnessTrace_Offline_v1',fx='BLT/BLT_Loudness_Trace_Offline_v1.jsfx'}
function Core.offline.install(api)
 local root=api.GetResourcePath()..'/Effects/'
 local path=root..Core.offline.fx
 local f=io.open(path,'rb');local old=f and f:read('*a');if f then f:close()end
 if old==Core.offline.jsfx then return end
 api.RecursiveCreateDirectory(root..'BLT',0)
 f=assert(io.open(path,'wb'),'オフライン測定JSFXを保存できません。')
 local ok,why=f:write(Core.offline.jsfx);local closed=f:close()
 assert(ok and closed,why or 'オフライン測定JSFXを保存できません。')
end
function Core.offline.find(api,state)
 if not api.ValidatePtr2(state.project,state.master,'MediaTrack*')then return end
 for i=0,api.TrackFX_GetCount(state.master)-1 do
  if api.TrackFX_GetFXGUID(state.master,i)==state.guid then return i end
 end
end
function Core.offline.detach(api,state)
 if state.guid then
  local index=Core.offline.find(api,state)
  if index then
   assert(api.TrackFX_Delete(state.master,index)~=false and not Core.offline.find(api,state),'オフライン測定JSFXを終了できません。')
  end
  state.guid=nil
 end
end
function Core.offline.close(api,state)
 if not state then return end
 local failure
 local function attempt(fn)
  local ok,why=pcall(fn);if not ok then failure=failure or why end
 end
 api.gmem_attach(Core.offline.memory)
 if api.gmem_read(state.base)==state.token then api.gmem_write(state.base+1,0)end
 if state.preference then
  attempt(function()
   assert(api.SNM_SetIntConfigVar('fxfloat_focus',state.preference)~=false,'FXウィンドウの自動表示設定を復元できません。')
   state.preference=nil
  end)
 end
 attempt(function()Core.offline.detach(api,state)end)
 if not state.guid and api.gmem_read(state.base)==state.token then api.gmem_write(state.base,0)end
 if failure then error(failure,0)end
 if Core.offline.active==state then Core.offline.active=nil end
end
function Core.offline.open(api,job,gain)
 Core.offline.install(api)
 api.gmem_attach(Core.offline.memory)
 local base,slot
 for i=0,15 do if api.gmem_read(i*524288)==0 then base,slot=i*524288,i;break end end
 assert(base,'オフライン測定の共有メモリを確保できません。')
 local token=max(1,tonumber(api.genGuid():gsub('[^%x]',''):sub(1,6),16)or 1)
 local state={project=job.project,master=api.GetMasterTrack(job.project),base=base,token=token}
 Core.offline.active=state
 job.offline=state
 api.gmem_write(base,token)
 for i=1,63 do api.gmem_write(base+i,0)end
 api.gmem_write(base+8,job.first);api.gmem_write(base+9,floor((job.last-job.first)*48000+.5))
 api.gmem_write(base+10,job.layout.channels);api.gmem_write(base+11,gain)
 for i,v in ipairs(job.layout.weights)do api.gmem_write(base+15+i,v)end
 local previous=api.SNM_GetIntConfigVar('fxfloat_focus',-2147483647)
 assert(previous~=-2147483647,'FXウィンドウの自動表示設定を取得できません。')
 state.preference=previous
 local ok,why=pcall(function()
  assert(api.SNM_SetIntConfigVar('fxfloat_focus',(previous&~(1|2|4|16|32|64))|8|128|65536)~=false)
  local index=api.TrackFX_AddByName(state.master,'JS: '..Core.offline.fx,false,-1)
  assert(index and index>=0,'オフライン測定JSFXを追加できません。')
  state.guid=assert(api.TrackFX_GetFXGUID(state.master,index))
  assert(index==api.TrackFX_GetCount(state.master)-1,'オフライン測定JSFXの位置を確認できません。')
  api.TrackFX_SetNamedConfigParm(state.master,index,'parallel','0')
  for output=0,1 do for pin=0,7 do
   assert(api.TrackFX_SetPinMappings(state.master,index,output,pin,1<<pin,0),'測定用JSFXのチャンネルを設定できません。')
  end end
  assert(api.TrackFX_SetParam(state.master,index,0,slot)~=false)
  assert(api.TrackFX_SetParam(state.master,index,1,token)~=false)
 end)
 local restored=api.SNM_SetIntConfigVar('fxfloat_focus',previous)
 if restored~=false then state.preference=nil end
 assert(restored~=false,'FXウィンドウの自動表示設定を復元できません。')
 if not ok then error(why,0)end
 api.gmem_attach(Core.offline.memory);api.gmem_write(base+1,1)
 return state
end
function Core.offline.read(api,job,tick)
 local state=job.offline;local base=state.base
 api.gmem_attach(Core.offline.memory);api.gmem_write(base+1,0)
 assert(api.gmem_read(base)==state.token,'オフライン測定の所有情報が失われました。')
 assert(api.gmem_read(base+2)==0,'オフライン測定信号の連続性を確認できません。')
 local frames=api.gmem_read(base+3);local expected=floor((job.last-job.first)*48000+.5)
 assert(frames==expected,'オフライン測定が完了していません。')
 local count=api.gmem_read(base+4)
 assert(count==floor(expected/4800)and count>=4 and count<=126000,'オフライン測定データの長さが不正です。')
 local rows,kbins,rbins={}, {}, {}
 local km,ks3,rm=0,0,0
 for i=1,count do
  local at=base+64+(i-1)*3
  local e,re,peak=api.gmem_read(at),api.gmem_read(at+1),api.gmem_read(at+2)
  assert(Core.finite(e)and e>=0 and Core.finite(re)and re>=0 and Core.finite(peak)and peak>=0,'オフライン測定データが不正です。')
  kbins[i],rbins[i]=e,re
  km=km+e-(kbins[i-4]or 0);ks3=ks3+e-(kbins[i-30]or 0);rm=rm+re-(rbins[i-4]or 0)
  local me=i>=4 and max(0,km/4)or nil
  rows[i]={t=i*.1,energy=me,m=me and Core.lufs(me)or nil,s=i>=30 and Core.lufs(max(0,ks3/30))or nil,
   rms=i>=4 and Core.db(max(0,rm/4))or nil,peak=Core.db(peak*peak)}
  kbins[i-30]=nil;rbins[i-4]=nil
  if tick and i%1000==0 then tick(.9*i/count);api.gmem_attach(Core.offline.memory)end
 end
 local tail=api.gmem_read(base+5)
 assert(Core.finite(tail)and tail>=0,'オフライン測定データが不正です。')
 rows[count].peak=max(rows[count].peak,Core.db(tail*tail))
 local result={rows=rows,duration=frames/48000,srate=48000}
 result.integrated=Core.integrate(rows,tick)
 return result
end
function Core.offline.measure(api,job,tick)
 local master=assert(api.GetMasterTrack(job.project),'マスタートラックを取得できません。')
 -- Measurement uses the master FX output with the starting master gain held constant.
 local gain=api.GetMediaTrackInfo_Value(master,'D_VOL')
 assert(Core.finite(gain)and gain>=0,'マスター音量が不正です。')
 Core.check_channels(api,job.project,job.layout)
 local ok,result=pcall(function()
  Core.offline.open(api,job,gain)
  Core.offline.render(api,job.project,job.first,job.last,job.layout)
  api.gmem_attach(Core.offline.memory);api.gmem_write(job.offline.base+1,0)
  Core.offline.detach(api,job.offline)
  job.renderState=api.GetProjectStateChangeCount(job.project)
  api.gmem_attach(Core.offline.memory)
  local fault=api.gmem_read(job.offline.base+2)
  assert(fault~=1,'測定時の処理レートが48 kHzではありません。')
  assert(fault~=2,'測定中の音声が不連続になりました。測定結果は保存していません。')
  assert(fault==0,'音声にNaNまたは無限大が含まれています。')
  job.phase='analyze'
  return Core.offline.read(api,job,tick)
 end)
 local unchanged=job.renderState==api.GetProjectStateChangeCount(job.project)
 Core.offline.close(api,job.offline);job.offline=nil
 if unchanged then job.renderState=api.GetProjectStateChangeCount(job.project)end
 if not ok then error(result,0)end
 return result
end

Core.offline.jsfx=[====[
desc:BLT Loudness Trace Offline Analysis
options:gmem=BLT_LoudnessTrace_Offline_v1
options:no_meter
in_pin:Measure 1
in_pin:Measure 2
in_pin:Measure 3
in_pin:Measure 4
in_pin:Measure 5
in_pin:Measure 6
in_pin:Measure 7
in_pin:Measure 8
out_pin:Pass 1
out_pin:Pass 2
out_pin:Pass 3
out_pin:Pass 4
out_pin:Pass 5
out_pin:Pass 6
out_pin:Pass 7
out_pin:Pass 8
slider1:0<0,15,1>-Memory slot
slider2:0<0,16777215,1>-Owner token

@init
ext_noinit=1;
ext_nodenorm=1;
ext_tail_size=-1;

@block
base=floor(slider1)*524288;
owned=slider2>0 && gmem[base]===slider2;
active=owned && gmem[base+1]==1 && (play_state&1);
active ? (
  last_token!==slider2 ? (
    last_token=slider2;
    memset(0,0,32);
    frames=0;bins=0;n=0;energy=0;raw=0;pk=0;
    first=gmem[base+8];limit=gmem[base+9];channels=gmem[base+10];gain=gmem[base+11];
    ch=0;loop(channels,32[ch]=gmem[base+16+ch];ch+=1;);
  );
  srate!=48000 ? (gmem[base+2]=1;active=0;);
  offset=floor((play_position-first)*48000+.5);
  block_i=0;
);

@sample
active && frames<limit && !gmem[base+2] ? (
  frame=offset+block_i;
  frame>=0 && frame<limit ? (
    frame!=frames ? gmem[base+2]=2 : (
      ch=0;
      loop(channels,
        v=spl(ch)*gain;
        !(v===v) || abs(v)>10^150 ? gmem[base+2]=3 : (
          z=ch*4;
          y=1.53512485958697*v+z[0];
          z[0]=-2.69169618940638*v+1.69065929318241*y+z[1];
          z[1]=1.19839281085285*v-.73248077421585*y;
          k=y+z[2];z[2]=-2*y+1.99004745483398*k+z[3];z[3]=y-.99007225036621*k;
          energy+=k*k*32[ch];raw+=v*v/channels;pk=max(pk,abs(v));
        );
        ch+=1;
      );
      n+=1;frames+=1;
      n==4800 ? (
        dest=base+64+bins*3;
        gmem[dest]=energy/n;gmem[dest+1]=raw/n;gmem[dest+2]=pk;
        bins+=1;energy=0;raw=0;pk=0;n=0;
        gmem[base+4]=bins;
      );
      frames==limit || block_i+1==samplesblock ? (gmem[base+3]=frames;gmem[base+5]=pk;);
    );
  );
  block_i+=1;
);
]====]

function Core.offline.render(R,project,first,last,layout)

  local nums={RENDER_SETTINGS=0,RENDER_BOUNDSFLAG=2,RENDER_CHANNELS=layout.render,RENDER_SRATE=48000,
    RENDER_STARTPOS=first,RENDER_ENDPOS=last,RENDER_TAILFLAG=0,RENDER_TAILMS=0,RENDER_ADDTOPROJ=0,
    RENDER_DITHER=16,RENDER_NORMALIZE=4<<16}
  local strs={RENDER_FORMAT='ZXZhdyADAA==',RENDER_FORMAT2=''}
  local oldn,olds,oldcfg={},{},{}
  for k in pairs(nums) do oldn[k]=R.GetSetProjectInfo(project,k,0,false) end
  for k in pairs(strs) do local ok,s=R.GetSetProjectInfo_String(project,k,'',false); assert(ok,'レンダー設定を読み取れません: '..k); olds[k]=s end
  for _,k in ipairs({'renderclosewhendone','autosaveonrender','autosaveonrender2','projrenderlimit'}) do
    local v=R.SNM_GetIntConfigVar(k,-2147483647)
    if v~=-2147483647 then oldcfg[k]=v end
  end
  assert(oldcfg.renderclosewhendone,'SWSからレンダー設定を取得できません。')
  local function restore()
    local failures={}
    local function attempt(key,fn)
      local ok,value=pcall(fn)
      if not ok or value==false then failures[#failures+1]=key end
    end
    for k,v in pairs(oldn) do attempt(k,function()return R.GetSetProjectInfo(project,k,v,true)end)end
    for k,v in pairs(olds) do attempt(k,function()return R.GetSetProjectInfo_String(project,k,v,true)end)end
    for k,v in pairs(oldcfg) do attempt(k,function()return R.SNM_SetIntConfigVar(k,v)end)end
    assert(#failures==0,table.concat(failures,', '))
  end
  local ok,result=pcall(function()
    for k,v in pairs(nums) do R.GetSetProjectInfo(project,k,v,true) end
    for k,v in pairs(strs) do assert(R.GetSetProjectInfo_String(project,k,v,true),'レンダー設定を変更できません: '..k) end
    R.SNM_SetIntConfigVar('renderclosewhendone',(oldcfg.renderclosewhendone|1)&~(16|16384|32768))
    for _,k in ipairs({'autosaveonrender','autosaveonrender2'}) do if oldcfg[k] then R.SNM_SetIntConfigVar(k,0) end end
    if oldcfg.projrenderlimit~=nil then
      assert(R.SNM_SetIntConfigVar('projrenderlimit',0)~=false,'レンダー設定を変更できません: projrenderlimit')
    end
    local ok,stats=R.GetSetProjectInfo_String(project,'RENDER_STATS','42441',false)
    assert(ok,'オフライン測定を実行できません。')
    return stats
  end)
  local restored,err=pcall(restore)
  if not restored then error('レンダー設定の復元に失敗: '..tostring(err)) end
  if not ok then error(result,0) end
  return result
end

function Core.segmented(data)
  if not data or data.segments then return data end
  for _,r in ipairs(data.rows) do r.time=data.first+r.t end
  return {source=data.source,name=data.name,segments={{first=data.first,last=data.last,rows=data.rows}}}
end
local function copy_row(r)
  local n={}; for k,v in pairs(r) do n[k]=v end; return n
end
function Core.replace_range(previous,fresh)
  fresh=Core.segmented(fresh); previous=Core.segmented(previous)
  local incoming=fresh.segments[1]
  incoming.stamp=os.time()
  local result={source=fresh.source,name=fresh.name,segments={}}
  local function keep(seg,a,b,stale)
    if b-a<1e-8 then return end
    local out={first=a,last=b,rows={},stale=stale and true or false,stamp=seg.stamp or 0}
    for _,r in ipairs(seg.rows) do
      if r.time>a+1e-8 and r.time<=b+1e-8 then out.rows[#out.rows+1]=copy_row(r) end
    end
    if #out.rows>0 then result.segments[#result.segments+1]=out end
  end
  if previous and previous.source==fresh.source then
    for _,seg in ipairs(previous.segments) do

      if seg.last<=incoming.first or seg.first>=incoming.last then keep(seg,seg.first,seg.last,true)
      else
        keep(seg,seg.first,min(seg.last,incoming.first),true)
        keep(seg,max(seg.first,incoming.last),seg.last,true)
      end
    end
  end

  keep(incoming,incoming.first,incoming.last,false)
  table.sort(result.segments,function(a,b) return a.first<b.first end)
  return result
end
function Core.trim_history(data,maxrows)
  local total=0
  for _,seg in ipairs(data.segments) do total=total+#seg.rows end
  local removed=0
  while total>maxrows and #data.segments>1 do
    local victimIndex,victimStamp=nil,math.huge
    for i,seg in ipairs(data.segments) do
      if seg.stale and (seg.stamp or 0)<victimStamp then victimIndex=i;victimStamp=seg.stamp or 0 end
    end
    if not victimIndex then break end
    local seg=data.segments[victimIndex]
    local excess=total-maxrows
    if #seg.rows<=excess then
      removed=removed+#seg.rows;total=total-#seg.rows;table.remove(data.segments,victimIndex)
    else
      for _=1,excess do table.remove(seg.rows,1) end
      removed=removed+excess;total=total-excess
      seg.first=seg.rows[1].time-.1
    end
  end
  return removed
end
function Core.recompute(data,tick)
  local segments,all={},{};local range=Core.live_tree()
  for _,seg in ipairs(data.segments) do
    assert(seg.last>seg.first and #seg.rows>0,'保存区間が不正です。')
    local rows={}
    local a,b=Core.live_after(seg.rows,seg.first),Core.live_after(seg.rows,seg.last)-1
    for i=a,b do
      local row=copy_row(seg.rows[i]);row.i=nil
      row.energy=(row.m and row.time-.4>=seg.first-1e-7) and (row.m<=-150 and 0 or 10^((row.m+.691)/10)) or nil
      local e=Core.history_energy(row,'s',seg.first);if e then range.add(e) end
      rows[#rows+1]=row;all[#all+1]=row
      if tick and #all%1000==0 then tick(.94) end
    end
    if #rows>0 then segments[#segments+1]={first=seg.first,last=seg.last,rows=rows,origin=rows[1].time-.1,stamp=seg.stamp or 0,stale=seg.stale} end
  end
  assert(#all>0 and #all<=MAX_HISTORY_ROWS,'保存できる共通履歴は最大3.5時間です。古い履歴を整理してから再試行してください。')
  Core.integrate(all,tick);local cumulative
  for _,r in ipairs(all) do if r.i then cumulative=r.i else r.i=cumulative end end
  data.live=nil;data.source='master';data.name=data.name or 'MASTER MIX';data.rows=all;data.segments=segments
  data.integrated=cumulative or Core.SILENCE;data.lra=Core.tree_lra(range)
  data.first=segments[1].first;data.last=segments[#segments].last;data.liveCount=#all
  for _,seg in ipairs(segments) do build_lod(seg,tick) end
end

function Core.row(data,time)
  if not data or not data.segments then return nil end
  local l,h=1,#data.segments;local found,foundIndex
  while l<=h do
    local m=(l+h)//2;local seg=data.segments[m]
    if time>=seg.first then found=seg;foundIndex=m;l=m+1 else h=m-1 end
  end
  if not found or time>found.last+1e-8 then return nil end
  l,h=1,#found.rows;local row
  while l<=h do
    local m=(l+h)//2
    if found.rows[m].time<=time+1e-8 then row=found.rows[m];l=m+1 else h=m-1 end
  end
  if row and row.time<=found.first+1e-8 then row=nil end
  if not row and foundIndex>1 and math.abs(time-found.first)<1e-8 then
    local previous=data.segments[foundIndex-1];local last=previous.rows[#previous.rows]
    if last and math.abs(last.time-time)<1e-8 and last.time<=previous.last+1e-8 then row=last end
  end
  return row
end
-- Byte-bounded BLT2 records; current writer and reader use the same format.

function Core.pack(data)
  local chunks,lines,bytes={}, {},22
  local function flush()
    if #lines>0 then
      local body=table.concat(lines,'|')
      chunks[#chunks+1]='BLT2|'..Core.history_hash({body})..'|'..body;lines={};bytes=22
    end
  end
  local function add(line)
    if bytes+#line+1>8000 then flush() end
    lines[#lines+1]=line;bytes=bytes+#line+1
  end
  local function number(n) return n~=nil and string.format('%.12g',n) or 'x' end
  for _,seg in ipairs(data.segments) do
    local a,b=Core.live_after(seg.rows,seg.first),Core.live_after(seg.rows,seg.last)-1
    -- A LIVE view can retain a shared row array with clipped first/last bounds.
    -- Persist only the visible rows, not the full backing array.
    if a<=b then
      local groups={};local first=a
      for i=a+1,b do
        if math.abs(seg.rows[i].time-seg.rows[i-1].time-.1)>=1e-6 then groups[#groups+1]={first,i-1};first=i end
      end
      groups[#groups+1]={first,b}
      for gi,g in ipairs(groups) do
        local start=gi==1 and seg.first or max(seg.rows[g[1]-1].time,seg.rows[g[1]].time-.1)
        local finish=gi==#groups and seg.last or seg.rows[g[2]].time
        add('G,'..string.format('%.17g,%.17g,%d,%.6f',start,finish,seg.stale and 1 or 0,seg.stamp or 0))
        for i=g[1],g[2] do
          local r=seg.rows[i];local f={'R',string.format('%.17g',r.time)}
          for _,k in ipairs({'s','m','rms','peak'}) do f[#f+1]=number(r[k]) end
          add(table.concat(f,','))
        end
      end
    end
  end
  flush();return chunks
end
function Core.history_hash(chunks)
  local h=0xcbf29ce484222325;local bytes=0
  for _,chunk in ipairs(chunks) do
    bytes=bytes+#chunk
    for i=1,#chunk do h=(h~chunk:byte(i))*0x100000001b3 end
    h=(h~10)*0x100000001b3
  end
  return string.format('%016x',h),bytes
end
function Core.unpack(chunks,recover)
  local data={segments={}};local current;local total=0
  local info={skipped=0,split=0}
  local function bad(message,header)
    if not recover then error(message,0) end
    info.skipped=info.skipped+1
    if header then current=nil end
  end
  for _,chunk in ipairs(chunks) do
    assert(type(chunk)=='string','保存データが不正です。')
    local wire=chunk
    if wire:sub(1,5)=='BLT2|' then
      local hash,body=wire:match('^BLT2|([%x]+)|(.*)$')
      if not hash or #hash~=16 or Core.history_hash({body})~=hash then
        bad('保存グラフの整合性検証に失敗しました。',true);wire=''
      else wire=body:gsub('|','\n') end
    elseif wire=='' then
      if recover then info.skipped=info.skipped+1 end
    else bad('不明な保存データ形式です。',true);wire='' end
    for line in wire:gmatch('[^\r\n]+') do
      line=line:match('^%s*(.-)%s*$')
      if line~='' then
        local f={};for v in (line..','):gmatch('(.-),') do f[#f+1]=v:match('^%s*(.-)%s*$') end
        if f[1]=='G' then
          local a,b,stamp=tonumber(f[2]),tonumber(f[3]),tonumber(f[5])
          if #f~=5 or not Core.finite(a) or not Core.finite(b) or b<=a or not Core.finite(stamp) or (f[4]~='0' and f[4]~='1') then
            bad('保存範囲が不正です。',true)
          elseif data.segments[#data.segments] and a<data.segments[#data.segments].last-1e-8 then
            bad('保存範囲が重複しています。',true)
          else
            current={first=a,last=b,rows={},stale=f[4]=='1',stamp=stamp}
            data.segments[#data.segments+1]=current
          end
        elseif f[1]=='R' then
          local r={time=tonumber(f[2])};local valid=current and #f==6
          local problem='保存データが不正です。'
          if valid then
            valid=Core.finite(r.time) and r.time>current.first and r.time<=current.last+1e-7
            problem='保存時刻が範囲外です。'
          end
          if valid then
            for j,k in ipairs({'s','m','rms','peak'}) do
              local v=tonumber(f[j+2])
              if f[j+2]~='x' and not Core.finite(v) then valid=false;problem='保存数値が不正です。';break end
              r[k]=v
            end
          end
          local prev=current and current.rows[#current.rows]
          if valid and prev and r.time<=prev.time+1e-9 then valid=false;problem='保存時刻が逆転または重複しています。' end
          if valid and prev and math.abs(r.time-prev.time-.1)>=1e-6 then
            if not recover then error('保存カーブが途切れています。',0) end
            -- Keep a genuine missing span as a gap. Never interpolate measurements.
            local stop=current.last;current.last=prev.time
            local first=max(prev.time,r.time-.1)
            current={first=first,last=stop,rows={},stale=current.stale,stamp=current.stamp}
            data.segments[#data.segments+1]=current;info.split=info.split+1
          end
          if valid then
            current.rows[#current.rows+1]=r;total=total+1;assert(total<=MAX_HISTORY_ROWS,'保存データが上限を超えています。')
          else bad(problem,false) end
        else bad('不明な保存データ形式です。',false) end
      end
    end
  end
  local kept={}
  for _,seg in ipairs(data.segments) do
    if #seg.rows>0 then kept[#kept+1]=seg elseif not recover then error('保存区間に測定点がありません。',0) end
  end
  data.segments=kept
  assert(#kept>0,'保存データに復元できる測定点がありません。')
  return data,info
end

function Core.axis_ticks(lo,hi,pixels)
  local step=Core.tick_step(hi-lo,pixels*3)
  local start=math.ceil(lo/step)*step;local out={};local previous

  for i=0,64 do
    local v=start+i*step
    if v>hi then break end
    if v>=lo and v~=previous then out[#out+1]=v;previous=v end
  end
  return out
end

-- Localization
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
 ["オフライン測定JSFXを保存できません。"]="Cannot save the offline measurement JSFX.",
 ["オフライン測定JSFXを終了できません。"]="Cannot remove the offline measurement JSFX.",
 ["オフライン測定の共有メモリを確保できません。"]="Cannot reserve shared memory for offline measurement.",
 ["オフライン測定JSFXを追加できません。"]="Cannot add the offline measurement JSFX.",
 ["オフライン測定JSFXの位置を確認できません。"]="Cannot verify the offline measurement JSFX position.",
 ["オフライン測定の所有情報が失われました。"]="Offline measurement memory ownership was lost.",
 ["オフライン測定信号の連続性を確認できません。"]="Cannot verify the continuity of the offline measurement signal.",
 ["オフライン測定が完了していません。"]="Offline measurement was cancelled or did not complete.",
 ["オフライン測定データの長さが不正です。"]="Invalid offline measurement data length.",
 ["オフライン測定データが不正です。"]="Invalid offline measurement data.",
 ["オフライン測定を実行できません。"]="Cannot run offline measurement.",
 ["FXウィンドウの自動表示設定を復元できません。"]="Cannot restore automatic FX window display settings.",
 ["マスター音量が不正です。"]="Invalid master volume.",
 ["測定時の処理レートが48 kHzではありません。"]="Processing sample rate was not 48 kHz.",
 ["測定中の音声が不連続になりました。測定結果は保存していません。"]="Audio was discontinuous during measurement. Results have not been saved.",
 ["解析完了：高速解析（一時WAVなし）"]="Analysis complete: fast analysis (no temporary WAV).",

 ['測定レイアウトが不正です。']='Invalid measurement layout.',
 ['マスターのチャンネル数が測定レイアウトより少ないため測定できません。']='The master has fewer channels than the measurement layout.',
 ['ハードウェア出力の経路を確認できません。']='Cannot verify the hardware output routing.',
 ['LIVE測定には各測定チャンネルをゲイン0 dB・PAN中央で、混合せずハードウェアへ出力する経路が必要です。']='LIVE requires an isolated unity-gain, centered-pan hardware route for every measurement channel.',

 ["音声にNaNまたは無限大が含まれています。"]="Audio contains NaN or infinity.",
 ["400 ms以上の時間範囲を選択してください。"]="Select a time range of at least 400 ms.",
 ["レンダー設定を読み取れません: "]="Cannot read render setting: ",
 ["SWSからレンダー設定を取得できません。"]="Cannot read render settings from SWS.",
 ["レンダー設定を変更できません: "]="Cannot change render setting: ",
 ["レンダー設定の復元に失敗: "]="Cannot restore render setting: ",
 ["保存区間が不正です。"]="Invalid saved section.",
 ["保存できる共通履歴は最大3.5時間です。古い履歴を整理してから再試行してください。"]="Shared history is limited to 3.5 hours. Remove old history, then retry.",
 ["保存範囲が不正です。"]="Invalid saved range.",
 ["保存範囲が重複しています。"]="Saved ranges overlap.",
 ["保存データが不正です。"]="Invalid saved data.",
 ["保存時刻が範囲外です。"]="Saved time is out of range.",
 ["保存カーブが途切れています。"]="Saved curve has gaps.",
 ["保存数値が不正です。"]="Invalid saved number.",
 ["保存データが上限を超えています。"]="Saved data exceeds limit.",
 ["不明な保存データ形式です。"]="Unknown saved data format.",
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
 ["縮小"]="Collapse",
 ["展開"]="Expand",
 ["次のプリセット"]="Next preset",
 ["前のプリセット"]="Previous preset",
 ["プリセット（読込・保存・インポート／エクスポート）"]="Presets: load, save, import/export",
 ["処理中にエラーが発生しました。"]="An error occurred during processing.",
 ["LOUDNESS TRACEにはSWSとjs_ReaScriptAPIが必要です。\nSWS: https://www.sws-extension.org/\njs_ReaScriptAPI: ReaPackからインストール\n\n不足: "]="LOUDNESS TRACE requires SWS and js_ReaScriptAPI.\nSWS: https://www.sws-extension.org/\njs_ReaScriptAPI: install via ReaPack\n\nMissing: ",
 ["LOUDNESS TRACE | 必要な拡張"]="LOUDNESS TRACE | Required extensions",
 ["保存データが12 MiBの安全上限を超えました。測定範囲を短くしてください。"]="Saved data exceeds the 12 MiB safety limit. Shorten the measurement range.",
 ["保存情報が不正です。"]="Invalid saved information.",
 ["保存カーブが不足しています。"]="Missing saved curve data.",
 ["LOUDNESS TRACE: 表示トラックを作成"]="LOUDNESS TRACE: Create display track",
 ["描画用ビットマップを作成できません。"]="Cannot create drawing bitmap.",
 ["解析ソース"]="Source",
 ["測定開始前にプロジェクトが切り替わりました。"]="Project changed before measurement started.",
 ["測定開始前に時間選択が変更されました。"]="Time selection changed before measurement started.",
 ["LOUDNESS TRACE | 解析"]="LOUDNESS TRACE | Analysis",
 ["LOUDNESS TRACE | 保存"]="LOUDNESS TRACE | Save",
 ["目標"]="Aim",
 ["ドッキング中はウィンドウを縮小できません。\nフローティング表示で使用してください。"]="Cannot collapse while docked.\nUse a floating window.",
 ["中止"]="Stop",
 ["解析"]="Analyze",
 ["ARRANGE LOUDNESS ANALYSIS  アレンジビュー上でラウドネスを解析・表示"]="ARRANGE LOUDNESS ANALYSIS  Analyze and display loudness",
 ["保存済み："]="Saved: ",
 ["区間  ·  選択範囲だけ置換"]=" sections · Replace selected range only",
 ["時間範囲を選択して解析。範囲外の解析結果は保持します。"]="Select a time range to analyze. Keep results outside that range.",
 ["グラフ "]="Graph ",
 ["警告表示"]="WARNINGS",
 ["補助表示"]="GUIDES",
 ["上限"]="Upper",
 ["超過"]="Above",
 ["下限"]="Lower",
 ["未満"]="Below",
 ["ピーク"]="Peak",
 ["グラフ設定"]="GRAPH",
 ["グラフ幅："]="Width:",
 ["解析結果へ最適化"]="Fit to results",
 ["グラフを非表示"]="Hide graph",
 ["グラフを表示"]="Show graph",
 ["グラフをクリア"]="Clear graph",
 ["解析を中止  "]="Stop analysis  ",
 ["選択範囲を解析"]="Analyze selection",
 ["解析中 %d%%"]="Analyzing %d%%",
 ["ドライレンダー解析中"]="Dry render analysis",
 ["解析準備中"]="Preparing analysis",
 ["プロジェクトが変更されています。再解析してください。"]="Project changed. Analyze again.",
 ["解析結果を表示しています。"]="Showing analysis results.",
 ["時間範囲を選択してください。"]="Select a time range.",
 ["グラフ用フォントを作成できません。"]="Cannot create graph font.",
 ["LOUDNESS TRACE | エラー"]="LOUDNESS TRACE | Error",
 ["表示言語を切替（JP / EN）"]="Switch language (JP / EN)",
 ["プリセットを読み込みました: ファクトリーデフォルト"]="Loaded: Factory Default",
 ["グラフ ON"]="Graph ON",
 ["グラフ OFF"]="Graph OFF",
 ["LOUDNESS TRACEはWindows／macOS用です。"]="LOUDNESS TRACE requires Windows or macOS.",
 ["現在のMetal設定ではグラフを重ね描画できません。REAPERの高度なUI設定でMetalを無効にするか、描画互換モードを選び、必要に応じてREAPERを再起動してください。"]="The current Metal mode cannot display the graph overlay. Disable Metal or enable drawing compatibility in REAPER's advanced UI settings, then restart REAPER if needed.",
 ["リアルタイム"]="Real-time",
 ["リアルタイム測定をOFFにしました。グラフは保持します。"]="Real-time recording is OFF. Recorded graph retained.",
 ["リアルタイムOFF：記録したグラフを表示しています。"]="Real-time OFF: showing recorded graph.",
 ["リアルタイムON：再生するとグラフを記録します。"]="Real-time ON: play to record the graph.",
 ["リアルタイム描画中：100 ms単位で追記しています。"]="Recording the live graph in 100 ms steps.",
 ["リアルタイム待機：プロジェクトの再生速度を1.0にしてください。"]="Live standby: set project play rate to 1.0.",
 ["リアルタイム待機：音声のオンライン復帰を待っています。"]="Live standby: waiting for media to come online.",
 ["測定信号を待っています。音声デバイス・モニターFXを確認してください。"]="Waiting for meter data. Check audio device and monitoring FX.",
 ["リアルタイム履歴の上限に達しました。グラフを保持して測定をOFFにしました。"]="Live history limit reached. Graph retained; recording switched OFF.",
 ["リアルタイム結果を保存できませんでした。メモリ内のグラフは保持しています。"]="Cannot save live results. The graph remains in memory.",
 ["測定データの受信が遅れた区間は空白として保持します。"]="Late meter data: missing intervals are left blank.",
 ["リアルタイム測定の共有メモリを確保できません。ほかの測定をOFFにしてください。"]="Cannot reserve live meter memory. Switch other live meters OFF.",
 ["リアルタイム測定JSFXを保存できません。"]="Cannot save the live metering JSFX.",
 ["測定用トラックまたはFXが変更されているため、自動削除できませんでした。確認してください。"]="Meter track or FX was changed and could not be removed safely. Please inspect it.",
 ["リアルタイム測定JSFXを追加できません。FX一覧を再スキャンしてください。"]="Cannot add the metering JSFX. Rescan the FX list.",
 ["リアルタイム測定JSFXを確認できません。"]="Cannot identify the live metering JSFX.",
 ["測定用JSFXの設定に失敗しました。"]="Cannot configure the metering JSFX.",
 ["リアルタイム測定の接続が失われました。"]="Live metering connection was lost.",
 ["リアルタイム測定データが不正です。"]="Invalid live metering data.",
 ["リアルタイム測定に必要なREAPER APIがありません。REAPERを更新してください。"]="Required live metering API is unavailable. Update REAPER.",
 ["リアルタイム測定用FXが削除または移動されました。"]="Live metering FX was removed or moved.",
 ["モニターFXの順序が変更されたため、測定をOFFにしました。"]="Monitoring FX order changed. Live recording switched OFF.",
 ["リアルタイム測定用FXが無効です。"]="Live metering FX is disabled or offline.",
 ["測定先が変更されたため、リアルタイム測定をOFFにしました。"]="Measurement source changed. Live recording switched OFF.",
 ["音声に不正な値があるため、リアルタイム測定をOFFにしました。"]="Invalid audio values. Live recording switched OFF.",
 ["リアルタイム測定では標準的な8～384 kHzのサンプルレートを使用してください。"]="Use a standard sample rate from 8 to 384 kHz for live metering.",
 ["リアルタイム測定JSFXの内容が不正です。"]="Invalid embedded live meter JSFX.",
 ["既存のリアルタイム測定JSFXを読み取れません。権限を確認してください。"]="Cannot read an existing live meter JSFX. Check file permissions.",
 ["リアルタイム測定JSFXの書き込み検証に失敗しました。"]="Live meter JSFX write verification failed.",
 ["リアルタイム測定JSFXの通信形式が一致しません。測定をOFFにしました。"]="Live meter JSFX protocol mismatch. Live measurement was turned OFF.",
 ["測定データのソースがマスターミックスではありません。"]="Measurement source is not the master mix.",
 ["集計データの対応が失われました。"]="History aggregation is inconsistent.",
 ["測定時刻が逆転しています。"]="Measurement time moved backwards.",
 ["共通グラフ：再生・解析した範囲を更新し、範囲外は保持します。"]="Shared graph: playback and analysis replace only the measured range.",
 ["マスタートラックを取得できません。"]="Cannot access the master track.",
 ["マスターのミュート／ソロ／モノ設定を解除するとLIVE測定できます。"]="Disable master mute/solo/mono monitoring to enable LIVE measurement.",
 ["モニターFXがバイパス中のためLIVE測定を待機しています。"]="LIVE is waiting because Monitoring FX are bypassed.",
 ["別プロジェクトを停止するとLIVE測定できます。"]="Stop other projects before LIVE measurement.",
 ["LIVE測定には、マスター1/2を音量・パンロー0 dB、PAN中央のステレオで単独出力する経路が必要です。"]="LIVE needs an isolated stereo post-fader hardware route from master 1/2 at unity gain/pan law and centered pan.",
 ["ハードウェア出力のエンベロープ状態を確認できないため、LIVE測定できません。"]="Cannot verify hardware-output envelopes; LIVE measurement is unavailable.",
 ["ハードウェア出力の音量エンベロープが使用中のため、LIVE測定できません。"]="The hardware-output volume envelope is in use; LIVE measurement is unavailable.",
 ["ハードウェア出力のPANエンベロープが使用中のため、LIVE測定できません。"]="The hardware-output pan envelope is in use; LIVE measurement is unavailable.",
 ["ハードウェア出力のミュートエンベロープが使用中のため、LIVE測定できません。"]="The hardware-output mute envelope is in use; LIVE measurement is unavailable.",
 ["測定用JSFXのチャンネルを設定できません。"]="Cannot set meter JSFX channel mappings.",
 ["測定用JSFXのチャンネルを確認できません。"]="Cannot verify meter JSFX channel mappings.",
 ["FXウィンドウの自動表示設定を取得できません。"]="Cannot read automatic FX window preferences.",
 ["FXウィンドウの自動表示を抑制できません。"]="Cannot suppress automatic FX windows.",
 ["FXウィンドウの自動表示設定を復元できません。終了時に再試行します。"]="Cannot restore FX window preferences. Will retry before exit.",
 ["測定用JSFXのチャンネルが変更されたため、測定をOFFにしました。"]="Meter channel mappings changed; LIVE stopped.",
 ["ハードウェア出力の経路が変わりました。LIVEをOFFにして再度ONにしてください。"]="Hardware output routing changed. Switch LIVE off, then on again.",
 ['リアルタイム測定JSFXの更新用ファイルを読み取れません。']='Cannot read the meter update files.',
 ['リアルタイム測定JSFXの前回更新を復元できません。']='Cannot restore the previous meter installation.',
 ['リアルタイム測定JSFXの作業ファイルを削除できません。']='Cannot remove the meter temporary file.',
 ['リアルタイム測定JSFXの更新用ファイルを削除できません。']='Cannot remove the meter update backup.',
 ['リアルタイム測定JSFXを更新できません。']='Cannot update the meter JSFX.',
 ['起動済みの測定用JSFXを終了できません。']='Cannot remove the running BLT monitoring meter.',
 ['保存時刻が逆転または重複しています。']='Saved measurement times are reversed or duplicated.',
 ['保存区間に測定点がありません。']='A saved segment has no measurements.',
 ['保存データに復元できる測定点がありません。']='No recoverable measurements in the saved data.',
 ['保存情報を取得できません。']='Cannot read the history metadata.',
 ['グラフ保存の読み戻し検証に失敗しました。']='Saved graph read-back validation failed.',
 ['保存グラフの整合性検証に失敗しました。']='Saved graph integrity validation failed.',
 ['グラフ保存先を確保できません。']='Cannot allocate the graph snapshot.',
 ['前回の正常な保存からグラフを復元しました。直近の一部は再測定してください。']='Restored the previous valid snapshot. Remeasure the latest missing section.',
 ['保存グラフの正常な測定点を復元しました。欠けた区間だけ再測定してください。']='Recovered valid measurements. Remeasure only the missing sections.',
 ['保存グラフの形式を修復しました。測定値は保持しています。']='Repaired the saved graph format. Measurements were preserved.',
 ['グラフをメモリ内へ復元しましたが、保存できません。元の保存データは保持しています。']='Recovered graph in memory but could not save. Original stored data retained.',
 ['保存グラフを復元できません。元のデータは保持しています。']='Cannot recover the graph. Original stored data retained.',
 ['保存グラフの欠損データを退避しました。グラフをクリアせず再測定できます。']='Damaged graph data retained separately. You can measure again without clearing the graph.',
},patterns={
 {"^「(.*)」を上書きしますか？$","Overwrite \"%s\"?"},
 {"^([%+%-]?[%d%.eE]+)–([%+%-]?[%d%.eE]+) / ([%+%-]?[%d%.eE]+)   スクロールで選択$","%d–%d / %d   Scroll to browse"},
 {"^解析中 ([%+%-]?[%d%.eE]+)%%$","Analyzing %d%%"},
 {"^レンダー設定を読み取れません: (.-)$","Cannot read render setting: %s"},
 {"^レンダー設定を変更できません: (.-)$","Cannot change render setting: %s"},
 {"^レンダー設定の復元に失敗: (.-)$","Cannot restore render setting: %s"},
 {"^「(.-)」を上書きしますか？$","\"%s\"?"},
 {"^(.-)」を上書きしますか？$","%s\"?"},
 {"^プリセットを保存しました: (.-)$","Saved: %s"},
 {"^プリセットを読み込みました: (.-)$","Loaded: %s"},
 {"^(.-)個インポートしました。$","%s preset(s) imported."},
 {"^現在: (.-)(.-)$","Current: %s%s"},
 {"^LOUDNESS TRACEにはSWSとjs_ReaScriptAPIが必要です。\nSWS: https://www%.sws%-extension%.org/\njs_ReaScriptAPI: ReaPackからインストール\n\n不足: (.-)$","LOUDNESS TRACE requires SWS and js_ReaScriptAPI.\nSWS: https://www.sws-extension.org/\njs_ReaScriptAPI: install via ReaPack\n\nMissing: %s"},
 {"^保存済み：(.-)  /  (.-)$","Saved: %s  /  %s"},
 {"^(.-)区間  ·  選択範囲だけ置換$","%s sections · Replace selected range only"},
 {"^グラフ (.-)$","Graph %s"},
 {"^グラフ幅：(.-)$","Width:%s"},
 {"^解析を中止  (.-)%%$","Stop analysis  %s%%"},
 {"^(%d+)個インポートしました。$","Imported %s preset(s)."},
},prefixes={"LOUDNESS TRACEにはSWSとjs_ReaScriptAPIが必要です。\nSWS: https://www.sws-extension.org/\njs_ReaScriptAPI: ReaPackからインストール\n\n不足: ","レンダー設定を読み取れません: ","レンダー設定を変更できません: ","プリセットを読み込みました: ","レンダー設定の復元に失敗: ","プリセットを保存しました: ","保存済み：","グラフ幅：","現在: "}}

local Language=create_language(reaper,"BLT_LOUDNESS_TRACE",LanguageCatalog)

-- Platform drawing adapter
local function create_trace_platform(api,graphics)
 local osname=api.GetOS()
 local P={mac=osname:match('OSX')~=nil or osname:match('macOS')~=nil,windows=osname:match('Win')~=nil}
 P.api=api
 P.chromeFont=P.mac and 'Helvetica Neue' or 'Segoe UI'
 P.graphFont=P.mac and 'HelveticaNeue-Medium' or P.chromeFont
 P.faces=P.mac and {'Hiragino Sans','Helvetica Neue','Menlo','Hiragino Sans'} or {'Yu Gothic UI','Segoe UI','Consolas','Yu Gothic UI'}
 P.bodyFaces=P.mac and {'Hiragino Sans','Menlo','Helvetica Neue','Hiragino Sans'} or {'Yu Gothic UI','Consolas','Segoe UI','Yu Gothic UI'}
 if not P.mac then return P end
 local R=setmetatable({}, {__index=api});P.api=R
 function R.GetMousePosition() local x,y=api.GetMousePosition();return x,-y end
 -- Async layered drawing can still reference the last published bitmap after
 -- unlink. Retire whole bitmaps for two defer turns instead of resizing/reusing
 -- their storage immediately. This queue exists only on macOS.
 local retired,epoch={},0
 function R.JS_LICE_DestroyBitmap(bitmap)
  if bitmap then retired[#retired+1]={bitmap=bitmap,epoch=epoch+2} end
 end
 function P.advance()
  epoch=epoch+1
  for i=#retired,1,-1 do
   if retired[i].epoch<=epoch then api.JS_LICE_DestroyBitmap(retired[i].bitmap);table.remove(retired,i) end
  end
 end
 function P.finish()
  if #retired==0 or P.draining then return end
  P.draining=true
  local function drain()
   P.advance()
   if #retired>0 then api.defer(drain) else P.draining=false end
  end
  api.defer(drain)
 end
 -- Internal screen Y points downward. Native macOS screen Y points upward.
 -- Client coordinates already point downward and must never be flipped.
 function R.JS_Window_ClientToScreen(hwnd,x,y)
  local sx,sy=api.JS_Window_ClientToScreen(hwnd,x,y);return sx,-sy
 end
 function R.JS_Window_ScreenToClient(hwnd,x,y)
  return api.JS_Window_ScreenToClient(hwnd,x,-y)
 end
 function R.JS_Window_FromPoint(x,y) return api.JS_Window_FromPoint(x,-y) end
 return P
end

local Platform=create_trace_platform(reaper,gfx)
local R=Platform.api


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

local SECTION="BLT_LOUDNESS_TRACE"
local PROJECT_SECTION="LOUDNESS_TRACE"
local TAG="P_EXT:"..PROJECT_SECTION
local W,H=646,592
local COLLAPSED_W,COLLAPSED_H=350,58
Core.analysis_button={normal={x=356,y=526,w=266,h=42},
 compact={x=256,y=12,w=78,h=34}}
local C={bg={.018,.030,.055},panel={.040,.068,.110},field={.018,.040,.080},
  edge={.145,.285,.445},text={.955,.980,1},muted={.690,.780,.875},
  faint={.390,.505,.635},accent={.120,.490,.980},ice={.650,.895,1},
  deep={.045,.235,.520},warn={1,.65,.35},mint={.38,.88,.72},red={1,.27,.34},purple={.77,.64,1},gold={1,.80,.39}}
local S={lo=-60,hi=0,visible=true,height=280,
  show={s=true,m=true,i=true,rms=false,peak=false},
  targets={s={-23,3},m={-23,3},i={-23,1}},source="master",
  alertUpper=false,alertLower=false,alertPeak=false}
-- LIVE meter / embedded JSFX
local Live={enabled=false,protocol=2,memory='BLT_LOUDNESS_TRACE_RT_V2',fx_relative='BLT/BLT_Loudness_Trace_Live.jsfx'}
Live.jsfx=[==[
desc:BLT Loudness Trace Live
// BLT managed LIVE meter; source revision 2.0.0.
// Measurement only: all audio and MIDI pass through unchanged.
// Private, bounded 100 ms energy queue shared with BLT_LOUDNESS_TRACE.lua.
options:gmem=BLT_LOUDNESS_TRACE_RT_V2
in_pin:Meter 1
in_pin:Meter 2
in_pin:Meter 3
in_pin:Meter 4
in_pin:Meter 5
in_pin:Meter 6
in_pin:Meter 7
in_pin:Meter 8
out_pin:Pass 1
out_pin:Pass 2
out_pin:Pass 3
out_pin:Pass 4
out_pin:Pass 5
out_pin:Pass 6
out_pin:Pass 7
out_pin:Pass 8
slider1:0<0,15,1>-BLT memory slot
slider2:0<0,16777215,1>-BLT owner token

@init
ext_noinit=1;
ext_nodenorm=1;
pdc_delay=0;
last_owner=0;
was_running=0;
seq=0;
epoch=0;

@block
base=floor(slider1)*8192;
owned=slider2>0 && gmem[base]===slider2;
owned ? (
  channels=floor(gmem[base+10]);
  owner_changed=last_owner!==slider2;
  owner_changed ? (seq=0; epoch=0; was_running=0; last_owner=slider2;);
  placement=get_host_placement(chain_position,host_flags);
  active=placement==-2 && chain_position==0 && !(host_flags&4) && gmem[base+2]>0 && gmem[base+7]==0 && channels>=1 && channels<=8 && (play_state==1 || play_state==5);
  reset=owner_changed || last_reset!==gmem[base+4] || last_sr!==srate;
  last_reset=gmem[base+4];
  last_sr!==srate ? (
    last_sr=srate;
    // BS.1770 K weighting. At 48 kHz these match the offline analyzer.
    kk=tan($pi*1681.974450955533/srate);
    q=.7071752369554196;
    vh=10^(3.999843853973347/20);
    vb=vh^.4996667741545416;
    aa=1+kk/q+kk*kk;
    b0=(vh+vb*kk/q+kk*kk)/aa;
    b1=2*(kk*kk-vh)/aa;
    b2=(vh-vb*kk/q+kk*kk)/aa;
    a1=2*(kk*kk-1)/aa;
    a2=(1-kk/q+kk*kk)/aa;
    kk=tan($pi*38.13547087602444/srate);
    aa=1+kk/.5003270373238773+kk*kk;
    h1=2*(kk*kk-1)/aa;
    h2=(1-kk/.5003270373238773+kk*kk)/aa;
    hop=max(1,floor(srate*.1+.5));
    inv_sr=1/srate;
    reset=1;
  );
  active && (!was_running || abs(play_position-expected)>max(4/srate,.00005)) ? reset=1;
  reset ? (
    memset(0,0,32);
    energy=0;raw=0;pk=0;n=0;
    epoch+=1;
    last_reset=gmem[base+4];
  );
  active && (srate<8000 || srate>384000 || abs(hop/srate-.1)>.0000001) ? (
    gmem[base+7]=2;active=0;
  );
  block_pos=play_position;
  block_i=0;
  expected=play_position+samplesblock/srate;
  was_running=active;
  gmem[base+5]=epoch;
  gmem[base+6]=srate;
  gmem[base+9]=2; // Protocol acknowledgment; only the current slot owner may publish.
  gmem[base+8]+=1;
) : (active=0;was_running=0;);

@sample
(active && gmem[base]===slider2) ? (
  ch=0;
  loop(channels,
    vv=spl(ch);
    !(vv===vv) || abs(vv)>1000000000 ? (gmem[base+7]=1;active=0;) : (
      zz=ch*4;
      yy=b0*vv+zz[0];
      zz[0]=b1*vv-a1*yy+zz[1];zz[1]=b2*vv-a2*yy;
      kk=yy+zz[2];zz[2]=-2*yy-h1*kk+zz[3];zz[3]=yy-h2*kk;
      energy+=kk*kk*gmem[base+16+ch];
      raw+=vv*vv/channels;pk=max(pk,abs(vv));
    );
    ch+=1;
  );
  active ? (
    n+=1;
    n>=hop ? (
      seq+=1;
      addr=base+64+((seq-1)%512)*8;
      gmem[addr]=-seq;
      gmem[addr+1]=epoch;
      gmem[addr+2]=block_pos+(block_i+1)*inv_sr;
      gmem[addr+3]=energy/n;
      gmem[addr+4]=raw/n;
      gmem[addr+5]=pk;
      gmem[addr+6]=srate;
      gmem[addr+7]=slider2;
      gmem[addr]=seq;
      gmem[base+3]=seq;
      energy=0;raw=0;pk=0;n=0;
    );
  );
  block_i+=1;
);
]==]
local function target_alert(v,target)
  if not v or not target then return false end
  if S.alertUpper and v>target[1]+target[2] then return true end
  if S.alertLower and v<target[1]-target[2] then return true end
  return false
end
local function bucket_alert(low,high,target)
  if not target then return false end
  if S.alertUpper and high and high>target[1]+target[2] then return true end
  if S.alertLower and low and low<target[1]-target[2] then return true end
  return false
end
local function peak_bucket_alert(low,high)
  return S.alertPeak and high and high>=0 or false
end

local function warning_durations(data)
  if Live.run and data then return Live.warnings(data) end
  local c=BLT.warningCache;local a,b=S.targets.s,S.targets.m
  if c and c.data==data and c.a==a[1] and c.b==a[2] and c.c==b[1] and c.d==b[2] then return c[1],c[2],c[3] end
  local upper,lower,peak=0,0,0
  for _,row in ipairs(data and data.rows or {}) do
    local u,l,p=Core.row_warning(row,S.targets)
    upper=upper+u*.1;lower=lower+l*.1;peak=peak+p*.1
  end
  BLT.warningCache={upper,lower,peak,data=data,a=a[1],b=a[2],c=b[1],d=b[2]}
  return upper,lower,peak
end
local function warning_time_text(seconds)
  seconds=max(0,floor((seconds or 0)+.5))
  if seconds>=3600 then
    return string.format('%d:%02d:%02d',seconds//3600,(seconds%3600)//60,seconds%60)
  end
  return string.format('%d:%02d',seconds//60,seconds%60)
end
local A={data=nil,job=nil,stale=false,project=nil,track=nil,bitmap=nil,arrange=nil,
 linked=false,revision=0,lastPaint=0,cache='',hover=nil,mouseRepairQueue={},
 closed=false,down=false,active=true,collapsed=false,tempDeletePending={},tempDeleteRetryAt=0}
local function extnum(key,default)
  local n=tonumber(R.GetExtState(SECTION,key)); return Core.finite(n) and n or default
end

local function public_error(err)
  return BLT.publicError(err,'処理中にエラーが発生しました。')
end
local required={"SNM_GetIntConfigVar","SNM_SetIntConfigVar","JS_Window_FindChildByID","JS_Window_Find","JS_Window_IsWindow","JS_Window_GetClientSize","JS_Window_SetPosition",
  "JS_Window_ClientToScreen","JS_Window_ScreenToClient","JS_Window_FromPoint",
  "JS_Composite","JS_Composite_Unlink","JS_Window_InvalidateRect","JS_LICE_CreateBitmap","JS_LICE_DestroyBitmap",
  "JS_LICE_Clear","JS_LICE_Blit","JS_LICE_FillRect","JS_LICE_Line","JS_LICE_CreateFont",
  "JS_LICE_DestroyFont","JS_LICE_SetFontFromGDI","JS_LICE_SetFontColor",
  "JS_LICE_SetFontBkColor","JS_LICE_DrawText","JS_GDI_CreateFont","JS_GDI_DeleteObject"}
if Platform.windows then required[#required+1]="JS_Composite_Delay" end
if Platform.mac then required[#required+1]="JS_Window_EnableMetal" end
local missing={}
for _,name in ipairs(required) do if not R.APIExists(name) then missing[#missing+1]=name end end
if #missing>0 then
  Language.mb("LOUDNESS TRACEにはSWSとjs_ReaScriptAPIが必要です。\nSWS: https://www.sws-extension.org/\njs_ReaScriptAPI: ReaPackからインストール\n\n不足: "..table.concat(missing,", "), "LOUDNESS TRACE | 必要な拡張",0)

  return
end
if not Platform.windows and not Platform.mac then
  Language.mb("LOUDNESS TRACEはWindows／macOS用です。", "LOUDNESS TRACE",0); return
end

local function restore_composite_delay()
  if not Platform.windows then return end
  if A.compositeDelayWindow and A.compositeDelayPrev and R.JS_Window_IsWindow(A.compositeDelayWindow) then
    local p=A.compositeDelayPrev
    pcall(R.JS_Composite_Delay,A.compositeDelayWindow,p.min,p.max,p.bitmaps)
  end
  A.compositeDelayWindow=nil;A.compositeDelayPrev=nil
end
local function configure_composite_delay(hwnd)
  if not Platform.windows then return end
  if A.compositeDelayWindow==hwnd and A.compositeDelayPrev then return end
  restore_composite_delay()

  local _,pmin,pmax,pbitmaps=R.JS_Composite_Delay(hwnd,-1,-1,-1)
  A.compositeDelayWindow=hwnd
  A.compositeDelayPrev={min=pmin or -1,max=pmax or -1,bitmaps=pbitmaps or -1}
  R.JS_Composite_Delay(hwnd,.040,.040,2)
end
local function unlink()
  if A.linked and A.arrange and A.bitmap then
    if R.JS_Window_IsWindow(A.arrange) then R.JS_Composite_Unlink(A.arrange,A.bitmap,true) end
  end
  restore_composite_delay()
  A.graphContentKey=nil;A.graphCursorPixel=nil
  A.linked=false; A.cache=""; A.layoutCache=nil; A.paintRect=nil; A.hover=nil; A.lastArrangeMouseX=nil; A.mouseRepairQueue={}; A.mouseSweepMin=nil; A.mouseSweepMax=nil; A.lastMouseMoveAt=nil
end
local function dispose_bitmap()
  unlink()
  A.drawBitmap=nil
  if A.backBitmap then R.JS_LICE_DestroyBitmap(A.backBitmap); A.backBitmap=nil end
  if A.bitmap then R.JS_LICE_DestroyBitmap(A.bitmap); A.bitmap=nil end
end
local function valid_track()
  return A.track and A.project and R.ValidatePtr2(A.project,A.track,"MediaTrack*")
end
local function find_track()
  for i=0,R.CountTracks(A.project)-1 do
    local tr=R.GetTrack(A.project,i)
    local _,tag=R.GetSetMediaTrackInfo_String(tr,TAG,"",false)
    if tag=="display" then return tr end
  end
end
local function save_settings()
  local fields={S.source,tostring(S.height),tostring(S.lo),tostring(S.hi)}
  for _,v in ipairs({S.show.s,S.show.m,S.show.i,S.show.rms,S.show.peak}) do fields[#fields+1]=v and '1' or '0' end
  for _,k in ipairs({'s','m','i'}) do fields[#fields+1]=tostring(S.targets[k][1]);fields[#fields+1]=tostring(S.targets[k][2]) end
  fields[#fields+1]=S.alertUpper and '1' or '0'
  fields[#fields+1]=S.alertLower and '1' or '0'
  fields[#fields+1]=S.alertPeak and '1' or '0'
  R.SetProjExtState(A.project,PROJECT_SECTION,'settings',table.concat(fields,';'))
end
local function load_settings()
  S.source='master';S.height=280;S.lo=-60;S.hi=0
  S.show={s=true,m=true,i=true,rms=false,peak=false}
  S.targets={s={-23,3},m={-23,3},i={-23,1}}
  S.alertUpper=false;S.alertLower=false;S.alertPeak=false
  local _,layout=R.GetProjExtState(A.project,PROJECT_SECTION,'measurement_layout')
  A.layout='stereo';for _,v in ipairs(Core.layouts) do if v.id==layout then A.layout=layout end end
  local _,raw=R.GetProjExtState(A.project,PROJECT_SECTION,'settings')
  local f={};for v in raw:gmatch('[^;]+') do f[#f+1]=v end
  if #f~=18 or f[1]~='master' then return end
  S.source='master';S.height=Core.clamp(tonumber(f[2]) or 280,180,800)
  local lo,hi=tonumber(f[3]),tonumber(f[4])
  if Core.finite(lo) and Core.finite(hi) and Core.finite(hi-lo) and hi-lo>1e-6 then
    lo=Core.round(Core.clamp(lo,-120,18),2)
    hi=Core.round(Core.clamp(hi,max(-118,lo+.1),24),2)
    if hi>lo then S.lo,S.hi=lo,hi end
  end
  S.show.s=f[5]=='1';S.show.m=f[6]=='1';S.show.i=f[7]=='1';S.show.rms=f[8]=='1';S.show.peak=f[9]=='1'
  for j,k in ipairs({'s','m','i'}) do
    local base=8+j*2
    local t,e=tonumber(f[base]),tonumber(f[base+1])
    if Core.finite(t) and Core.finite(e) and e>=0 then
      S.targets[k]={Core.round(Core.clamp(t,-150,24),2),Core.round(Core.clamp(e,0,60),2)}
    end
  end
  S.alertUpper=f[16]=='1';S.alertLower=f[17]=='1';S.alertPeak=f[18]=='1'
end
-- Snapshot ownership is explicit. Never delete by subtracting an enumeration
-- from the reference set: enumeration output/case is not an ownership proof.
-- Current graph storage
local History={key='result@master',backup='result_backup@master',recovery='result_recovery@master',failed='result_failed@master',failedBackup='result_failed_backup@master'}
History.references={History.key,History.backup,History.recovery,History.failed,History.failedBackup}
function History.select_layout(id)
 local suffix=id=='stereo' and '@master' or '@master:'..id
 History.key='result'..suffix;History.backup='result_backup'..suffix;History.recovery='result_recovery'..suffix
 History.failed='result_failed'..suffix;History.failedBackup='result_failed_backup'..suffix
 History.references={History.key,History.backup,History.recovery,History.failed,History.failedBackup}
end
function History.manifest(raw)
  assert(type(raw)=='string' and #raw<=512,'保存情報が不正です。')
  local f={};for v in (raw..';'):gmatch('(.-);') do f[#f+1]=v end
  local n,stamp,bytes=tonumber(f[2]),tonumber(f[3]),tonumber(f[5])
  assert(#f==6 and f[1]:match('^[%x]+$') and #f[1]<=128 and n and n>=1 and n<=4096 and n%1==0
    and Core.finite(stamp) and f[4]=='2' and bytes and bytes>0 and bytes<=MAX_SAVE_BYTES
    and f[6]:match('^[%x]+$') and #f[6]==16,'保存情報が不正です。')
  return f[1]:lower(),n,stamp,bytes,f[6]:lower()
end
function History.raw(key)
  local _,value=R.GetProjExtState(A.project,PROJECT_SECTION,key:lower())
  assert(type(value)=='string','保存情報を取得できません。')
  return value
end
function History.put(key,value)
  local canonical=key:lower()
  R.SetProjExtState(A.project,PROJECT_SECTION,canonical,value)
  local _,check=R.GetProjExtState(A.project,PROJECT_SECTION,canonical)
  assert(check==value,'グラフ保存の読み戻し検証に失敗しました。')
end
function History.erase(key)
  if History.raw(key)~='' then History.put(key,'') end
end
function History.retire(raw)
  -- Retire known snapshots only after verified publication or clearing their references.
  if raw=='' then return end
  local parsed,id,n=pcall(History.manifest,raw);if not parsed then return end
  if not id:match('^[%x]+$') or #id<16 then return end
  local canonical=id:lower()
  for _,key in ipairs(History.references) do
    local value=History.raw(key)
    if value~='' then
      local owner=value:match('^([%w]+);')
      if owner and owner:lower()==canonical then return end

      if not owner and value:lower():find(canonical,1,true) then return end
    end
  end
  for i=1,n do History.erase(id..'_'..i) end
  History.erase(id..'_name')
end
function History.read(raw,recover,verifyOnly)
  if raw=='' then return nil end
  local id,n,_,expectedBytes,expectedHash=History.manifest(raw)
  local chunks,bytes={},0
  for i=1,n do
    local v=History.raw(id..'_'..i)
    if not recover then assert(v~='','保存カーブが不足しています。') end
    bytes=bytes+#v;assert(bytes<=MAX_SAVE_BYTES,'保存データが12 MiBの安全上限を超えました。測定範囲を短くしてください。')
    chunks[i]=v
  end
  if not recover then
    local hash,actualBytes=Core.history_hash(chunks)
    assert(actualBytes==expectedBytes and hash==expectedHash,'保存グラフの整合性検証に失敗しました。')
  end

  if verifyOnly and not recover then return true end
  local data,info=Core.unpack(chunks,recover)
  data.source='master';data.name='MASTER MIX · '..Core.layout(A.layout).name
  if not verifyOnly then Core.recompute(data) end
  return data,info
end
local function save_data(data,recovered)
  assert(data.source=='master','測定データのソースがマスターミックスではありません。')
  local chunks=Core.pack(data)
  local verified=Core.unpack(chunks);local rows=0
  for _,seg in ipairs(verified.segments) do rows=rows+#seg.rows end
  assert(rows<=MAX_HISTORY_ROWS,'保存できる共通履歴は最大3.5時間です。古い履歴を整理してから再試行してください。')
  local hash,bytes=Core.history_hash(chunks)
  assert(bytes<=MAX_SAVE_BYTES,'保存データが12 MiBの安全上限を超えました。測定範囲を短くしてください。')
  local old=History.raw(History.key)
  local snapshotKey=recovered and History.recovery or History.backup
  local previousSnapshot=History.raw(snapshotKey)
  local id=R.genGuid():gsub('[^%w]',''):lower()
  assert(id~='' and old:sub(1,#id):lower()~=id and History.raw(id..'_1')=='','グラフ保存先を確保できません。')
  local stamp=os.time()+(R.time_precise()%1)
  local manifest=string.format('%s;%d;%.6f;2;%d;%s',id,#chunks,stamp,bytes,hash)
  local written={};local switching=false
  local ok,why=xpcall(function()
    for i,chunk in ipairs(chunks) do
      local key=id..'_'..i;written[#written+1]=key;History.put(key,chunk)
    end
    local nameKey=id..'_name';written[#written+1]=nameKey;History.put(nameKey,data.name or '')
    History.read(manifest,false,true)
    if old~='' then History.put(snapshotKey,old) end
    switching=true;History.put(History.key,manifest)

    History.read(History.raw(History.key),false,true)
  end,debug.traceback)
  if not ok then
    if switching then pcall(History.put,History.key,old) end
    local read,current=pcall(History.raw,History.key)
    if read and current==old then
      pcall(History.put,snapshotKey,previousSnapshot)
      for _,key in ipairs(written) do pcall(History.erase,key) end
    end
    -- On an uncertain rollback, keep the new chunks rather than delete a possible owner.
    error(why,0)
  end
  A.historyBlocked=false;A.historyProblem=nil
  local cleaned,err=pcall(History.retire,previousSnapshot);if not cleaned then BLT.logError(err) end
  -- Retirement cannot turn a successful save into a missing-curve snapshot.
  History.read(History.raw(History.key),false,true)
end
function History.clear()
  local snapshots={}
  for _,key in ipairs(History.references) do
    snapshots[#snapshots+1]=History.raw(key);History.erase(key)
  end
  for _,raw in ipairs(snapshots) do History.retire(raw) end
end
local function load_data()
  A.data=nil;A.stale=false;A.historyBlocked=false;A.historyProblem=nil;A.historyRecovery=nil
  local raw=History.raw(History.key)
  local ok,result=pcall(History.read,raw)
  if ok then A.data=result;A.stale=result~=nil;return end
  -- Invalid persisted history starts a new measurement without a recovery prompt.
  History.clear()
  Live.run=nil;Live.previous=nil;Live.dirty=false;Live.notice=nil;Live.noticeBad=false
end

local function clear_measurement()
  if A.job then return end
  if Live.enabled then Live.stop() end
  Live.run=nil;Live.previous=nil;Live.dirty=false;Live.notice=nil;Live.noticeBad=false
  History.clear()
  A.historyBlocked=false;A.historyProblem=nil;A.historyRecovery=nil
  A.data=nil;A.stale=false
  A.revision=A.revision+1;A.cache='';A.hover=nil
  A.baseline=R.GetProjectStateChangeCount(A.project)
end

local function source_name() return 'MASTER MIX · '..Core.layout(A.layout or 'stereo').name end

local function ensure_track()
  A.track=find_track()
  if A.track then return end
  R.Undo_BeginBlock2(A.project)

  R.InsertTrackAtIndex(0,false)
  A.track=R.GetTrack(A.project,0)
  R.GetSetMediaTrackInfo_String(A.track,TAG,"display",true)
  R.GetSetMediaTrackInfo_String(A.track,"P_NAME","LOUDNESS TRACE",true)
  R.SetMediaTrackInfo_Value(A.track,"B_MAINSEND",0)
  R.SetMediaTrackInfo_Value(A.track,"B_SHOWINMIXER",0)
  R.SetMediaTrackInfo_Value(A.track,"B_SHOWINTCP",1)
  R.SetMediaTrackInfo_Value(A.track,"I_RECARM",0)
  R.SetMediaTrackInfo_Value(A.track,"I_HEIGHTOVERRIDE",S.height)
  R.SetMediaTrackInfo_Value(A.track,"I_CUSTOMCOLOR",R.ColorToNative(23,67,106)|0x1000000)
  R.TrackList_AdjustWindows(false)
  R.Undo_EndBlock2(A.project,"LOUDNESS TRACE: 表示トラックを作成",1)
end
local function graph_track_is_visible()
  return valid_track() and R.GetMediaTrackInfo_Value(A.track,"B_SHOWINTCP")~=0
end
local function set_graph_track_visible(visible)
  S.visible=visible and true or false
  if S.visible then
    ensure_track()
    if valid_track() then
      R.SetMediaTrackInfo_Value(A.track,"B_SHOWINTCP",1)
      R.SetMediaTrackInfo_Value(A.track,"I_HEIGHTOVERRIDE",S.height)
      R.TrackList_AdjustWindows(false)
      A.cache=""
    end
  else
    unlink()
    if valid_track() then
      R.SetMediaTrackInfo_Value(A.track,"B_SHOWINTCP",0)
      R.TrackList_AdjustWindows(false)
    end
  end
end
local function adopt_project(create)
  if Live.enabled or Live.dirty then Live.stop() end
  Live.project=nil;Live.run=nil;Live.previous=nil;Live.dirty=false;Live.notice=nil;Live.noticeBad=false
  unlink(); A.project=R.EnumProjects(-1,""); A.track=find_track()
  -- Validate stored history before displaying it; invalid history is cleared.
  load_settings();History.select_layout(A.layout);load_data()
  if create then ensure_track() end

  if valid_track() then S.visible=graph_track_is_visible() end
  A.revision=A.revision+1; A.baseline=R.GetProjectStateChangeCount(A.project)
end

-- LIVE acquisition
function Live.wake()
  A.revision=A.revision+1;A.cache='';A.hover=nil
  if BLT.host then BLT.host.wake() end
end
function Live.message(text,bad)
  Live.notice=text;Live.noticeBad=bad==true;Live.wake()
end
function Live.valid_project(project)
  if not project then return false end
  local i=0
  while true do local p=R.EnumProjects(i,'');if not p then return false end;if p==project then return true end;i=i+1 end
end
function Live.select_memory() R.gmem_attach(Live.memory) end
function Live.release_slot()
  if Live.base then
    Live.select_memory()
    if R.gmem_read(Live.base)==Live.token then
      R.gmem_write(Live.base+2,0);R.gmem_write(Live.base,0);R.gmem_write(Live.base+1,0)
    end
  end
  Live.base=nil;Live.slot=nil
end
function Live.reserve_slot()
  Live.select_memory();local now=R.time_precise()
  for slot=0,15 do
    local b=slot*8192;local owner,stamp=R.gmem_read(b),R.gmem_read(b+1)
    if owner==0 or now-stamp>30 or stamp>now+1 then
      local token=tonumber(R.genGuid():gsub('[^%x]',''):sub(1,6),16) or 1
      token=max(1,token)
      R.gmem_write(b+2,0);R.gmem_write(b,token);R.gmem_write(b+1,now)
      for i=3,9 do R.gmem_write(b+i,0) end
      Live.slot,Live.base,Live.token=slot,b,token;Live.readSeq=0
      return
    end
  end
  error('リアルタイム測定の共有メモリを確保できません。ほかの測定をOFFにしてください。',0)
end

function Live.file_contents(path)
  local f,err,code=io.open(path,'rb')
  if not f then
    -- Only ENOENT means missing. Access errors must never become permission to write.
    if code==2 then return nil,'missing' end
    return nil,'unreadable',err
  end
  local ok,body=pcall(f.read,f,131073)
  local closed,result=pcall(f.close,f)
  if not ok or not closed or not result then return nil,'unreadable',body end
  if not body then body='' end
  return body,#body>131072 and 'oversized' or 'read'
end
function Live.discard_install_temp(path)
  local ok,removed=pcall(os.remove,path)
  if ok and removed then return true end
  local _,state=Live.file_contents(path);if state=='missing' then return true end

  A.tempDeletePending[path]=R.time_precise()
  return false
end
function Live.meter_file()
  assert(type(Live.jsfx)=='string' and #Live.jsfx>0 and #Live.jsfx<=131072,'リアルタイム測定JSFXの内容が不正です。')
  local root=R.GetResourcePath()..'/Effects/'
  local path=root..Live.fx_relative
  local body,state=Live.file_contents(path)
  if state=='read' and body==Live.jsfx then
    Live.discard_install_temp(path..'.tmp');Live.discard_install_temp(path..'.bak');return path
  end
  assert(state~='unreadable','既存のリアルタイム測定JSFXを読み取れません。権限を確認してください。')
  -- Never replace the source of a running meter, even if called outside startup.
  Live.remove_monitor_meters()
  R.RecursiveCreateDirectory(root..'BLT',0)
  local temp,backup=path..'.tmp',path..'.bak'
  local _,backupState=Live.file_contents(backup)
  assert(backupState~='unreadable','リアルタイム測定JSFXの更新用ファイルを読み取れません。')
  if state=='missing' and backupState~='missing' then
    assert(os.rename(backup,path),'リアルタイム測定JSFXの前回更新を復元できません。')
    body,state=Live.file_contents(path)
    if state=='read' and body==Live.jsfx then Live.discard_install_temp(temp);return path end
  end
  local moved=false
  local ok,why=xpcall(function()
    -- A single temporary file and backup keep failed updates bounded as well.
    local _,temporaryState=Live.file_contents(temp)
    assert(temporaryState~='unreadable','リアルタイム測定JSFXの更新用ファイルを読み取れません。')
    if temporaryState~='missing' then assert(os.remove(temp),'リアルタイム測定JSFXの作業ファイルを削除できません。') end
    local f,err=io.open(temp,'wb');assert(f,err or 'リアルタイム測定JSFXを保存できません。')
    local called,written,werr=pcall(f.write,f,Live.jsfx)
    local closed,result=pcall(f.close,f)
    assert(called and written and closed and result,werr or 'リアルタイム測定JSFXを保存できません。')
    assert(Live.file_contents(temp)==Live.jsfx,'リアルタイム測定JSFXの書き込み検証に失敗しました。')
    local _,oldBackup=Live.file_contents(backup)
    if oldBackup~='missing' then assert(os.remove(backup),'リアルタイム測定JSFXの更新用ファイルを削除できません。') end
    local _,current=Live.file_contents(path)
    assert(current~='unreadable','既存のリアルタイム測定JSFXを読み取れません。権限を確認してください。')
    if current~='missing' then assert(os.rename(path,backup),'リアルタイム測定JSFXを更新できません。');moved=true end
    assert(os.rename(temp,path),'リアルタイム測定JSFXを保存できません。')
    assert(Live.file_contents(path)==Live.jsfx,'リアルタイム測定JSFXの書き込み検証に失敗しました。')
  end,debug.traceback)
  if not ok then
    if moved then
      -- Restore the last complete source on failure; do not discard a failed rollback.
      local _,current=Live.file_contents(path)
      if current~='missing' then os.remove(path) end
      local restored=os.rename(backup,path)
      if not restored then why=tostring(why)..'\nリアルタイム測定JSFXの前回更新を復元できません。' end
    end
    Live.discard_install_temp(temp)
    error(why,0)
  end
  if moved then Live.discard_install_temp(backup) end
  return path
end

function Live.relative_fx_name(name)
  name=tostring(name or ''):gsub('^JS:%s*',''):gsub('\\','/')
  local root=(R.GetResourcePath()..'/Effects/'):gsub('\\','/')
  local compare,base=name,root
  if Platform.windows then compare,base=compare:lower(),base:lower() end
  if compare:sub(1,#base)==base then name=name:sub(#root+1) end
  return name
end
function Live.find_fx(host,guid)
  if not host or not guid then return end
  for i=0,R.TrackFX_GetRecCount(host)-1 do
    local index=0x1000000+i
    if R.TrackFX_GetFXGUID(host,index)==guid then return index end
  end
end
function Live.is_meter(host,index)
  local ok,name=R.TrackFX_GetNamedConfigParm(host,index,'fx_ident')
  if not ok then return false end
  name=Live.relative_fx_name(name)
  if Platform.windows then return name:lower()==Live.fx_relative:lower() end
  return name==Live.fx_relative
end
-- Startup owns only BLT's dedicated monitoring meters, never other monitor FX.
function Live.remove_monitor_meters()
  local project=R.EnumProjects(-1,'');local host=R.GetMasterTrack(project)
  if not host then return end
  for i=R.TrackFX_GetRecCount(host)-1,0,-1 do
    local index=0x1000000+i
    if Live.is_meter(host,index) then
      local guid=R.TrackFX_GetFXGUID(host,index)
      local slot,token=R.TrackFX_GetParam(host,index,0),R.TrackFX_GetParam(host,index,1)
      if Core.finite(slot) and slot%1==0 and slot>=0 and slot<=15 and Core.finite(token) and token>0 then
        Live.select_memory();local base=slot*8192
        if R.gmem_read(base)==token then
          R.gmem_write(base+2,0);R.gmem_write(base,0);R.gmem_write(base+1,0)
        end
      end
      if R.TrackFX_Show then R.TrackFX_Show(host,index,2) end
      assert(R.TrackFX_Delete(host,index)~=false and not Live.find_fx(host,guid),'起動済みの測定用JSFXを終了できません。')
    end
  end
end
function Live.prepare_install()
  Live.remove_monitor_meters()
  Live.meter_file()
end
function Live.slot_alive(host,index)
  local slot=R.TrackFX_GetParam(host,index,0);local token=R.TrackFX_GetParam(host,index,1)
  if not Core.finite(slot) or slot%1~=0 or not Core.finite(token) or token%1~=0 or token<=0 or slot<0 or slot>15 then return false end
  Live.select_memory();local b=floor(slot+.5)*8192;local age=R.time_precise()-R.gmem_read(b+1)
  return R.gmem_read(b)==token and age>=-1 and age<=30
end
function Live.recover_orphans(project)
  local master=R.GetMasterTrack(project)
  for i=R.TrackFX_GetRecCount(master)-1,0,-1 do
    local index=0x1000000+i
    if Live.is_meter(master,index) and R.TrackFX_GetParam(master,index,1)>0 and not Live.slot_alive(master,index) then
      R.TrackFX_Delete(master,index)
    end
  end
end
function Live.disconnect()
  if Live.base then Live.select_memory();if R.gmem_read(Live.base)==Live.token then R.gmem_write(Live.base+2,0) end end
  local host=R.GetMasterTrack(R.EnumProjects(-1,''));local clean=true
  local idx=Live.find_fx(host,Live.guid)
  if idx then clean=R.TrackFX_Delete(host,idx)~=false and Live.find_fx(host,Live.guid)==nil end
  Live.release_slot();Live.host=nil;Live.guid=nil;Live.fxIndex=nil;Live.connecting=nil;Live.route=nil
  Live.restore_fx_preference()
  if not clean then Live.message('測定用トラックまたはFXが変更されているため、自動削除できませんでした。確認してください。',true) end
  return clean
end

-- P_ENV may return an allocated envelope even when no automation is in use.

function Live.hardware_envelopes_unused(project,track,index)
  local unknown='ハードウェア出力のエンベロープ状態を確認できないため、LIVE測定できません。'
  local entries={
    {'VOLENV','ハードウェア出力の音量エンベロープが使用中のため、LIVE測定できません。'},
    {'PANENV','ハードウェア出力のPANエンベロープが使用中のため、LIVE測定できません。'},
    {'MUTEENV','ハードウェア出力のミュートエンベロープが使用中のため、LIVE測定できません。'},
  }
  local function integer(v) return Core.finite(v) and v>=0 and v%1==0 end
  for _,entry in ipairs(entries) do
    local got,env=pcall(R.GetTrackSendInfo_Value,track,1,index,'P_ENV:<'..entry[1])
    if not got then return false,unknown end
    if env and env~=0 then
      local valid,exists=pcall(R.ValidatePtr2,project,env,'TrackEnvelope*')
      if not valid or exists~=true then return false,unknown end
      local counted,points=pcall(R.CountEnvelopePoints,env)
      local listed,items=pcall(R.CountAutomationItems,env)
      local read,state=pcall(R.GetEnvelopeUIState,env)
      if not counted or not listed or not read or not integer(points) or not integer(items) or not integer(state) or state>7 then
        return false,unknown
      end
      -- Stored points/automation items remain conservatively unsupported, even
      -- when currently bypassed. Empty envelopes that are playing or writing
      -- automation are not safe either. Visibility alone is irrelevant.
      if points>0 or items>0 or (state&3)~=0 then return false,entry[2] end
    end
  end
  return true
end

-- Monitoring FX receive hardware-output audio, not an unconditional master tap.
-- Accept only isolated unity post-fader routes for every measurement channel.
-- Never alter the user's sends, hardware levels, master fader, pan, or monitor FX.
function Live.route_for_master(project)
  local master=R.GetMasterTrack(project)
  if not master or not R.ValidatePtr2(project,master,'MediaTrack*') then return nil,'マスタートラックを取得できません。' end
  local layout=Core.layout(A.layout or 'stereo')
  if R.GetMediaTrackInfo_Value(master,'I_NCHAN')<layout.channels then return nil,'マスターのチャンネル数が測定レイアウトより少ないため測定できません。' end
  if (R.GetMasterMuteSoloFlags()&7)~=0 then return nil,'マスターのミュート／ソロ／モノ設定を解除するとLIVE測定できます。' end
  if R.SNM_GetIntConfigVar('hwoutfx_bypass',0)~=0 then return nil,'モニターFXがバイパス中のためLIVE測定を待機しています。' end
  for i=0,1023 do local p=R.EnumProjects(i,'');if not p then break end
    if p~=project and (R.GetPlayStateEx(p)&1)~=0 then return nil,'別プロジェクトを停止するとLIVE測定できます。' end
  end
  local outputs=math.min(64,R.GetNumAudioOutputs());local occupied,candidates={},{}
  local function inspect(track,isMaster)
    for index=0,R.GetTrackNumSends(track,1)-1 do
      local function value(key)return R.GetTrackSendInfo_Value(track,1,index,key) end
      if value('B_MUTE')==0 then
        local src,dst=value('I_SRCCHAN'),value('I_DSTCHAN')
        if not Core.finite(src) or not Core.finite(dst) or src%1~=0 or dst%1~=0 or dst<0 then return false end
        if src>=0 then
          local first=src&1023;local mode=src>>10;local width=mode==0 and 2 or mode==1 and 1 or mode*2
          local start=dst&1023;local mono=(dst&1024)~=0;local count=mono and 1 or width
          for ch=start,math.min(outputs-1,start+count-1) do occupied[ch]=(occupied[ch] or 0)+1 end
          if isMaster and start+count<=outputs and (not mono or width==1) and (width>1 or mono)
            and value('I_SENDMODE')==0 and value('B_PHASE')==0 and (value('B_MONO')==0 or width==1)
            and math.abs(value('D_VOL')-1)<1e-12 and math.abs(value('D_PAN'))<1e-12 then
            local law=value('D_PANLAW')
            if law==-1 then
              if type(R.get_config_var_string)=='function' then local ok,raw=R.get_config_var_string('panlaw');law=ok and tonumber(raw) or nil
              elseif type(R.SNM_GetDoubleConfigVar)=='function' then law=R.SNM_GetDoubleConfigVar('panlaw',-1) end
            end
            if Core.finite(law) and math.abs(law-1)<1e-12 and Live.hardware_envelopes_unused(project,track,index) then
              candidates[#candidates+1]={first=first,width=width,start=start,index=index}
            end
          end
        end
      end
    end
    return true
  end
  if not inspect(master,true) then return nil,'ハードウェア出力の経路を確認できません。' end
  for i=0,R.CountTracks(project)-1 do if not inspect(R.GetTrack(project,i),false) then return nil,'ハードウェア出力の経路を確認できません。' end end
  local map,signature={},{}
  for channel=0,layout.channels-1 do
    for _,candidate in ipairs(candidates) do
      if channel>=candidate.first and channel<candidate.first+candidate.width then
        local hardware=candidate.start+channel-candidate.first
        if occupied[hardware]==1 then
          map[channel+1]=hardware;signature[channel+1]=candidate.index..':'..hardware;break
        end
      end
    end
    if not map[channel+1] then return nil,'LIVE測定には各測定チャンネルをゲイン0 dB・PAN中央で、混合せずハードウェアへ出力する経路が必要です。' end
  end
  return {master=master,map=map,layout=layout,signature=layout.id..'|'..table.concat(signature,'|')}
end
function Live.same_route(a,b)
 return a and b and a.master==b.master and a.signature==b.signature
end
function Live.pin_mask(channel)
  return channel<32 and (1<<channel) or 0,channel>=32 and (1<<(channel-32)) or 0
end
function Live.map_meter(host,index,route)
  for output=0,1 do for pin=0,7 do
    local channel=route.map[pin+1];local lo,hi=0,0
    if channel then lo,hi=Live.pin_mask(channel) end
    assert(R.TrackFX_SetPinMappings(host,index,output,pin,lo,hi),'測定用JSFXのチャンネルを設定できません。')
    local a,b=R.TrackFX_GetPinMappings(host,index,output,pin)
    assert((a&0xffffffff)==lo and (b&0xffffffff)==hi,'測定用JSFXのチャンネルを確認できません。')
  end end
end
function Live.add_meter_quiet(host)
  local previous=R.SNM_GetIntConfigVar('fxfloat_focus',-2147483647)
  assert(previous~=-2147483647,'FXウィンドウの自動表示設定を取得できません。')
  local visible=R.TrackFX_GetRecChainVisible(host)
  local selected=visible>=0 and R.TrackFX_GetFXGUID(host,0x1000000|(visible&0xffffff)) or nil
  local focus=R.JS_Window_GetFocus and R.JS_Window_GetFocus()
  local idx;local before={}
  for i=0,R.TrackFX_GetRecCount(host)-1 do local id=R.TrackFX_GetFXGUID(host,0x1000000+i);if id then before[id]=true end end
  local ok,why=xpcall(function()
    -- &4 auto-float; !&128 auto-open quick-add. Also prevent focus/chain replacement.
    local quiet=(previous&(~(1|2|4|16|32|64)))|8|128|65536
    Live.restoreFXPreference=previous
    assert(R.SNM_SetIntConfigVar('fxfloat_focus',quiet)~=false,'FXウィンドウの自動表示を抑制できません。')
    assert(R.SNM_GetIntConfigVar('fxfloat_focus',-1)==quiet,'FXウィンドウの自動表示を抑制できません。')
    idx=R.TrackFX_AddByName(host,'JS: '..Live.fx_relative,true,-1000)
    assert(idx and idx>=0,'リアルタイム測定JSFXを追加できません。FX一覧を再スキャンしてください。')
    idx=0x1000000|(idx&0xffffff);Live.fxIndex=idx
    Live.guid=assert(R.TrackFX_GetFXGUID(host,idx))
  end,debug.traceback)
  if not ok and not Live.guid then
    for i=0,R.TrackFX_GetRecCount(host)-1 do
      local n=0x1000000+i;local id=R.TrackFX_GetFXGUID(host,n)
      if id and not before[id] and Live.is_meter(host,n) then Live.guid=id;idx=n;Live.fxIndex=n;break end
    end
  end
  -- All cleanup is attempted independently; a failed add must not leave preferences changed.
  local shown,showerr=pcall(function()
    if idx and idx>=0 then R.TrackFX_Show(host,idx,2) end
    if visible==-1 then R.TrackFX_Show(host,0x1000000,0)
    elseif selected then
      local old=Live.find_fx(host,selected)
      if old then R.TrackFX_Show(host,old,1) end
    end
  end)
  local restored,result=pcall(R.SNM_SetIntConfigVar,'fxfloat_focus',previous)
  if not restored or result==false or R.SNM_GetIntConfigVar('fxfloat_focus',-1)~=previous then
    Live.restoreFXPreference=previous
    error('FXウィンドウの自動表示設定を復元できません。終了時に再試行します。',0)
  end
  Live.restoreFXPreference=nil
  if focus and R.JS_Window_IsWindow(focus) and R.JS_Window_SetFocus then pcall(R.JS_Window_SetFocus,focus) end
  if not ok then error(why,0) end
  if not shown then error(showerr,0) end
  return idx
end
function Live.restore_fx_preference()
  if Live.restoreFXPreference==nil then return end
  local old=Live.restoreFXPreference
  if R.SNM_SetIntConfigVar('fxfloat_focus',old)~=false and R.SNM_GetIntConfigVar('fxfloat_focus',-1)==old then Live.restoreFXPreference=nil end
end
function Live.connect()
  local project=A.project
  assert(project==R.EnumProjects(-1,''),'プロジェクトが切り替わりました。')
  Live.project=project;Live.source='master';Live.layout=A.layout;Live.host=R.GetMasterTrack(project)
  local route,why=Live.route_for_master(project);assert(route,why)
  Live.route=route;Live.routeAt=0;Live.routeRevision=nil;Live.checkedRoute=nil
  Live.recover_orphans(project);Live.meter_file();Live.reserve_slot()
  local idx=Live.add_meter_quiet(Live.host)
  assert(Live.is_meter(Live.host,idx),'リアルタイム測定JSFXを確認できません。')
  Live.map_meter(Live.host,idx,route)
  R.gmem_write(Live.base+10,route.layout.channels)
  for i,w in ipairs(route.layout.weights) do R.gmem_write(Live.base+15+i,w) end
  assert(R.TrackFX_SetParam(Live.host,idx,0,Live.slot)~=false and R.TrackFX_SetParam(Live.host,idx,1,Live.token)~=false,'測定用JSFXの設定に失敗しました。')
  assert(R.TrackFX_GetParam(Live.host,idx,0)==Live.slot and R.TrackFX_GetParam(Live.host,idx,1)==Live.token,'測定用JSFXの設定に失敗しました。')
  R.TrackFX_SetNamedConfigParm(Live.host,idx,'renamed_name','BLT LOUDNESS TRACE [LIVE]')
  Live.startedAt=R.time_precise();Live.checkAt=0;Live.readSeq=0;Live.epoch=nil;Live.wasPlaying=false;Live.prevPos=nil
  A.baseline=R.GetProjectStateChangeCount(project)
end

function Live.finish_run()
  if not Live.run then return end
  if A.data then Core.recompute(A.data) end
  Live.run=nil;Live.previous=nil;Live.warningCache=nil;Live.wake()
end
function Live.save()
  if not Live.dirty or not A.data then return true end
  if not Live.valid_project(Live.project or A.project) then return false end

  local ok,err=pcall(save_data,A.data)
  if ok then Live.dirty=false;A.baseline=R.GetProjectStateChangeCount(A.project)
  else Live.message('リアルタイム結果を保存できませんでした。メモリ内のグラフは保持しています。',true);BLT.logError(err) end
  return ok
end
function Live.accept(packet)
  local run=Live.run;local time=packet.time
  if run and (packet.epoch~=run.epoch or math.abs(time-run.last-.1)>1e-6 or packet.srate~=run.srate) then Live.finish_run();run=nil end
  if not run then
    Live.previous=A.data
    Live.stamp=max(os.time()+(R.time_precise()%1),(Live.stamp or 0)+.000001)
    run={first=time-.1,last=time-.1,origin=time-.1,rows={},stamp=Live.stamp,epoch=packet.epoch,srate=packet.srate,meter=Core.live_meter(),summary=Core.history_summary(Live.previous,time-.1,S.targets)}
    Live.run=run
  end
  local row=run.meter.feed(time,packet.energy,packet.raw,packet.peak)
  run.integrated,run.lra=run.summary.feed(row)
  run.rows[#run.rows+1]=row;run.last=time
  Core.live_lod_append(run,row)
  local data=Core.live_view(Live.previous,run,'master',source_name())
  if data.liveCount>MAX_HISTORY_ROWS or #data.segments>2048 then
    -- Refuse the overflowing row, keeping the previous valid graph intact.
    run.rows[#run.rows]=nil;Live.run=nil;Live.previous=nil
    if A.data then Core.recompute(A.data) end
    error('リアルタイム履歴の上限に達しました。グラフを保持して測定をOFFにしました。',0)
  end
  A.data=data;A.stale=false;Live.dirty=true;Live.latest=row;Live.lastPacketAt=R.time_precise();Live.phase='writing';Live.wake()
end
function Live.pull(limit,final)
  if not Live.base then return end
  Live.select_memory();local base=Live.base
  assert(R.gmem_read(base)==Live.token,'リアルタイム測定の接続が失われました。')
  if R.gmem_read(base+8)>0 then
    assert(R.gmem_read(base+9)==Live.protocol,'リアルタイム測定JSFXの通信形式が一致しません。測定をOFFにしました。')
  end
  local head=R.gmem_read(base+3);local epoch=R.gmem_read(base+5)
  assert(Core.finite(head) and head>=0 and head%1==0 and head<2^45,'リアルタイム測定データが不正です。')
  if head<Live.readSeq then Live.readSeq=0;Live.finish_run() end
  if head-Live.readSeq>512 then Live.readSeq=head-512;Live.finish_run();Live.message('測定データの受信が遅れた区間は空白として保持します。',true) end
  local stop=min(head,Live.readSeq+512)
  for seq=Live.readSeq+1,stop do
    local at=base+64+((seq-1)%512)*8
    if R.gmem_read(at)~=seq then break end
    local p={epoch=R.gmem_read(at+1),time=R.gmem_read(at+2),energy=R.gmem_read(at+3),raw=R.gmem_read(at+4),peak=R.gmem_read(at+5),srate=R.gmem_read(at+6)}
    if R.gmem_read(at)~=seq or R.gmem_read(at+7)~=Live.token then break end
    if p.epoch==epoch or final then
      assert(Core.finite(p.time) and Core.finite(p.energy) and p.energy>=0 and Core.finite(p.raw) and p.raw>=0
        and Core.finite(p.peak) and p.peak>=0 and Core.finite(p.srate) and p.srate>=8000 and p.srate<=384000,'リアルタイム測定データが不正です。')
      if not final and p.time>limit+.005 then break end
      if not limit or p.time<=limit+.005 then Live.accept(p) end
    end
    Live.readSeq=seq
  end
end
function Live.stop(message)
  Live.enabled=false
  if Live.base then
    Live.select_memory();if R.gmem_read(Live.base)==Live.token then R.gmem_write(Live.base+2,0) end
    if Live.project==R.EnumProjects(-1,'') then
      local route=Live.route_for_master(Live.project)
      if Live.same_route(route,Live.route) then
        local ok,err=pcall(Live.pull,Live.lastPos,true);if not ok then BLT.logError(err) end
      end
    end
  end
  local ok,err=pcall(Live.finish_run);if not ok then Live.run=nil;Live.previous=nil;BLT.logError(err) end
  local disconnected,why=pcall(Live.disconnect);if not disconnected then BLT.logError(why);Live.release_slot() end
  local saved=Live.save();Live.phase='off';Live.wasPlaying=false;Live.latest=nil
  if message and saved and not Live.noticeBad then Live.message(message,false) else Live.wake() end
  return saved
end
function Live.toggle()
  if Live.enabled then Live.stop('リアルタイム測定をOFFにしました。グラフは保持します。');return end
  if A.job then return end
  Live.notice=nil;Live.noticeBad=false
  local ok,err=xpcall(function()
    local required={'gmem_attach','gmem_read','gmem_write','TrackFX_AddByName','TrackFX_GetFXGUID','TrackFX_GetNamedConfigParm','TrackFX_GetRecCount',
      'TrackFX_SetParam','TrackFX_GetParam','TrackFX_Delete','GetTrackNumSends','GetTrackSendInfo_Value',
      'TrackFX_GetRecChainVisible','TrackFX_Show','TrackFX_SetPinMappings','TrackFX_GetPinMappings','GetNumAudioOutputs','GetMasterMuteSoloFlags'}
    for _,name in ipairs(required) do assert(type(R[name])=='function','リアルタイム測定に必要なREAPER APIがありません。REAPERを更新してください。') end
    assert(not A.historyBlocked,A.historyProblem or '保存グラフを復元できません。元のデータは保持しています。')
    set_graph_track_visible(true)
    R.PreventUIRefresh(1)
    Live.connecting=true
    local connected,why=xpcall(Live.connect,debug.traceback)
    R.PreventUIRefresh(-1)
    if not connected then error(why,0) end
    Live.connecting=nil;Live.enabled=true;Live.phase='waiting';Live.lastPacketAt=nil;Live.lastPos=nil
    Live.wake()
  end,debug.traceback)
  if not ok then Live.stop();Live.message(public_error(err),true) end
end
function Live.check_connection()
  local host=R.GetMasterTrack(A.project)
  assert(host and R.ValidatePtr2(A.project,host,'MediaTrack*'),'マスタートラックを取得できません。')
  local idx=Live.find_fx(host,Live.guid)
  assert(idx and Live.is_meter(host,idx),'リアルタイム測定用FXが削除または移動されました。')
  assert(idx==0x1000000,'モニターFXの順序が変更されたため、測定をOFFにしました。')
  assert(R.TrackFX_GetEnabled(host,idx) and not R.TrackFX_GetOffline(host,idx),'リアルタイム測定用FXが無効です。')
  assert(R.TrackFX_GetParam(host,idx,0)==Live.slot and R.TrackFX_GetParam(host,idx,1)==Live.token,'測定用JSFXの設定に失敗しました。')
  for output=0,1 do for pin=0,7 do
    local channel=Live.route.map[pin+1];local lo,hi=0,0
    if channel then lo,hi=Live.pin_mask(channel) end
    local a,b=R.TrackFX_GetPinMappings(host,idx,output,pin)
    assert((a&0xffffffff)==lo and (b&0xffffffff)==hi,'測定用JSFXのチャンネルが変更されたため、測定をOFFにしました。')
  end end
end

function Live.tick(now)
  if not Live.enabled then return end
  local ok,err=xpcall(function()
    assert(A.project==Live.project and S.source==Live.source and A.layout==Live.layout,'測定先が変更されたため、リアルタイム測定をOFFにしました。')
    Live.select_memory();assert(R.gmem_read(Live.base)==Live.token,'リアルタイム測定の接続が失われました。')
    R.gmem_write(Live.base+1,now)
    if now>=(Live.checkAt or 0) then Live.check_connection();Live.checkAt=now+.5 end
    if R.gmem_read(Live.base+8)>0 then
      assert(R.gmem_read(Live.base+9)==Live.protocol,'リアルタイム測定JSFXの通信形式が一致しません。測定をOFFにしました。')
    end
    local errorCode=R.gmem_read(Live.base+7)
    assert(errorCode~=1,'音声に不正な値があるため、リアルタイム測定をOFFにしました。')
    assert(errorCode~=2,'リアルタイム測定では標準的な8～384 kHzのサンプルレートを使用してください。')
    local playing=(R.GetPlayStateEx(A.project)&1)~=0
    local ready=Media.ready();local rate=R.Master_GetPlayRate(A.project)
    local revision=R.GetProjectStateChangeCount(A.project)
    local route,routeWhy
    if revision~=Live.routeRevision or now>=(Live.routeAt or 0) then
      route,routeWhy=Live.route_for_master(A.project)
      Live.routeRevision=revision;Live.routeAt=now+.5;Live.checkedRoute=route;Live.checkedRouteProblem=routeWhy
    else route,routeWhy=Live.checkedRoute,Live.checkedRouteProblem end
    local routeOK=Live.same_route(route,Live.route)
    if not routeOK then
      R.gmem_write(Live.base+2,0)
      Live.readSeq=R.gmem_read(Live.base+3)
      Live.finish_run();Live.save()
      if Live.phase~='routing' then R.gmem_write(Live.base+4,R.gmem_read(Live.base+4)+1) end
      Live.wasPlaying=false;Live.routeProblem=routeWhy or 'ハードウェア出力の経路が変わりました。LIVEをOFFにして再度ONにしてください。'
      if Live.phase~='routing' then Live.phase='routing';Live.wake() end
      return
    end
    Live.routeProblem=nil
    local allowed=playing and ready and math.abs(rate-1)<1e-6
    R.gmem_write(Live.base+2,allowed and 1 or 0)
    if allowed then
      local pos=R.GetPlayPositionEx(A.project)
      Live.lastPos=pos;Live.pull(pos,false)
      if not Live.wasPlaying then Live.startedAt=now end
      local phase=now-(Live.lastPacketAt or Live.startedAt)>2 and 'signal' or (Live.run and 'writing' or 'waiting')
      if phase~=Live.phase then Live.phase=phase;Live.wake() end
    else
      if Live.wasPlaying then
        Live.pull(Live.lastPos,true);Live.finish_run();Live.save()
        Live.select_memory();R.gmem_write(Live.base+4,R.gmem_read(Live.base+4)+1)
        Live.readSeq=R.gmem_read(Live.base+3)
      end
      local phase=not ready and 'offline' or math.abs(rate-1)>=1e-6 and 'rate' or 'waiting'
      if phase~=Live.phase then Live.phase=phase;Live.wake() end
    end
    Live.wasPlaying=allowed
  end,debug.traceback)
  if not ok then Live.stop();Live.message(public_error(err),true) end
end
function Live.status()
  if Live.noticeBad then return Live.notice,true end
  if Live.enabled then
    if Live.phase=='routing' then return Live.routeProblem,true end
    if Live.phase=='rate' then return 'リアルタイム待機：プロジェクトの再生速度を1.0にしてください。',true end
    if Live.phase=='offline' then return 'リアルタイム待機：音声のオンライン復帰を待っています。',false end
    if Live.phase=='signal' then return '測定信号を待っています。音声デバイス・モニターFXを確認してください。',true end
    return Live.phase=='writing' and 'リアルタイム描画中：100 ms単位で追記しています。' or 'リアルタイムON：再生するとグラフを記録します。',false
  end
  return Live.notice or 'リアルタイムOFF：記録したグラフを表示しています。',false
end
function Live.prepare_offline()
  if Live.enabled then if not Live.stop() then return false end
  else Live.finish_run();if not Live.save() then return false end end
  Live.notice=nil;Live.noticeBad=false
  return true
end
function Live.restore_after_measure(job)
  local resume=job.resumeLive;job.resumeLive=nil
  if not resume or Live.enabled or A.job or A.closed or A.requestClose
    or A.project~=job.project or R.EnumProjects(-1,'')~=job.project then return end
  local message,bad=Live.notice,Live.noticeBad
  Live.toggle()
  if Live.enabled and bad then Live.message(message,true) end
end

local function value(v) return not v and '—' or (v<=-149 and '-inf' or string.format('%.1f',v)) end

local function argb(c) return 0xff000000 | (floor(c[1]*255)<<16) | (floor(c[2]*255)<<8) | floor(c[3]*255) end
local function draw_bitmap() return A.drawBitmap or A.bitmap end
local function lrect(x,y,w,h,c,a)
  if w>0 and h>0 then R.JS_LICE_FillRect(draw_bitmap(),floor(x),floor(y),floor(w),floor(h),argb(c),a or 1,"COPY") end
end
local function lline(x,y,x2,y2,c,a)
  R.JS_LICE_Line(draw_bitmap(),x,y,x2,y2,argb(c),a or 1,"COPY",true)
end
local function ltext(s,x,y,w,c)
  R.JS_LICE_SetFontColor(A.font,argb(c or C.muted))
  R.JS_LICE_DrawText(draw_bitmap(),A.font,s,#s,floor(x),floor(y),floor(x+w),floor(y+20))
end
-- Arrange graph
local function chart(width,height,first,last,mx)
  R.JS_LICE_Clear(draw_bitmap(),argb(C.bg))
  local top,bottom=48,height-30
  if bottom-top<18 then ltext('LOUDNESS TRACE - increase track height',12,6,width-24,C.ice); return end
  local function yy(v) return Core.level_y(v,top,bottom,S.lo,S.hi) end
  local function xx(t) return Core.time_x(t,first,last,width) end
  local step=Core.tick_step(last-first,width)
  for t=math.ceil(first/step)*step,last,step do lline(xx(t),top,xx(t),bottom,C.edge,.42) end
  local ticks=Core.axis_ticks(S.lo,S.hi,bottom-top)
  for _,v in ipairs(ticks) do lline(0,yy(v),width,yy(v),C.edge,.6) end
  local colors={s=C.ice,m=C.mint,i=C.purple,rms=C.gold,peak=C.faint}
  local data=A.data
  if data then
   local whole=data;local ranges={}
   -- Adjacent history segments share one guide layer; their moving borders do not restart dashes.
   for _,seg in ipairs(whole.segments) do
     local ax,bx=max(0,xx(seg.first)),min(width,xx(seg.last))
     if bx>ax then
       local previous=ranges[#ranges]
       if previous and ax<=previous[2]+1e-6 then previous[2]=max(previous[2],bx)
       else ranges[#ranges+1]={ax,bx} end
     end
   end
   for _,range in ipairs(ranges) do
     local ax,bx=range[1],range[2]
     lrect(ax,top,bx-ax,bottom-top,C.accent,.035)
     for _,key in ipairs({'s','m','i'}) do
       if S.show[key] then
         local target=S.targets[key]
         for j,v in ipairs({target[1]-target[2],target[1]+target[2]}) do
           if v>=S.lo and v<=S.hi and (j==1 or target[2]~=0) then
             local y=yy(v)
             for x=floor(ax/14)*14,bx,14 do
               local left,right=max(ax,x),min(bx,x+5)
               if right>left then lline(left,y,right,y,colors[key],.23) end
             end
           end
         end
       end
     end
   end
   for _,data in ipairs(whole.segments) do
    local ax,bx=max(0,xx(data.first)),min(width,xx(data.last))
    if bx>ax then
      local spp=(last-first)*10/width
      local lev,span=1,1
      while span*2<=spp and span*2<#data.rows do lev=lev+1; span=span*2 end
      for _,key in ipairs(Core.metrics) do
        if S.show[key] then
          local buckets=data.lod[key][lev]
          if key=='i' and Live.run and data.first>=Live.run.last-1e-8 then buckets={} end
          local from=max(1,floor((first-data.origin)*10/span))
          local to=min(#buckets//2,math.ceil((last-data.origin)*10/span)+1)
          local px,py,pbad
          for i=from,to do
            local bi=(i-1)*2+1;local low,high=buckets[bi],buckets[bi+1]
            if low==false then low=nil end;if high==false then high=nil end
            local time=data.origin+((i-1)*span+min(span,#data.rows-(i-1)*span)*.5+.5)*.1
            local x=xx(time)
            if low then
              local bad
              if key=='peak' then bad=peak_bucket_alert(low,high)
              elseif S.targets[key] then bad=bucket_alert(low,high,S.targets[key])
              else bad=false end
              local y=yy((low+high)*.5); local color=bad and C.red or colors[key]
              local pathColor=(bad or pbad) and C.red or colors[key]
              local pathAlpha=(key=='s' and .98 or .78)

              if px and x>=ax and px<=bx and x>px then
                local left,right=max(ax,px),min(bx,x)
                if right>left then
                  local slope=(y-py)/(x-px)
                  local x1,y1,x2,y2=Core.clip_level_line(left,py+(left-px)*slope,right,py+(right-px)*slope,top,bottom)
                  if x1 then lline(x1,y1,x2,y2,pathColor,pathAlpha) end
                end
              end
              if x>=ax and x<=bx and high>=S.lo and low<=S.hi then
                lline(x,yy(max(low,S.lo)),x,yy(min(high,S.hi)),color,.85)
              end
              px,py,pbad=x,y,bad
            else px=nil end
          end
        end
      end
    end
   end
  else ltext(Live.enabled and 'Press PLAY to record live loudness.' or 'Select a time range, or enable REAL-TIME.',65,top+24,width-90,C.muted) end
  for _,v in ipairs(ticks) do
    lrect(5,yy(v)-8,35,17,C.bg,.94); ltext(string.format('%.5g',v),8,yy(v)-8,30,C.muted)
  end
  lrect(0,0,width,28,C.panel)
  local measuredName=source_name()
  ltext('LOUDNESS TRACE  ·  '..tostring(measuredName or 'NO TARGET'),12,5,max(165,width-390),C.ice)
  if width>680 then
    local tags={}
    for _,q in ipairs({{'s','S'},{'m','M'},{'i','I RUN'},{'rms','RMS'},{'peak','PEAK'}}) do if S.show[q[1]] then tags[#tags+1]=q[2] end end
    ltext(table.concat(tags,'  /  '),max(300,width-365),5,180,C.muted)
  end
  if width>370 then ltext(Live.enabled and (Live.phase=='writing' and 'LIVE / RECORDING' or 'LIVE / WAIT') or (data and (A.stale and 'SAVED / RE-MEASURE' or 'MEASURED') or 'NO MEASUREMENT'),width-185,5,180,Live.enabled and C.mint or A.stale and C.gold or C.faint) end
  ltext((S.show.rms or S.show.peak) and 'LUFS / dBFS' or 'LUFS',7,height-20,110,C.faint)
  for t=math.ceil(first/step)*step,last,step do
    local x=xx(t); if x>115 and x<width-64 then ltext(Core.clock(t),x+3,height-20,85,C.faint) end
  end
  local cursor=R.GetCursorPositionEx(A.project)
  if (R.GetPlayStateEx(A.project)&1)==1 then cursor=R.GetPlayPositionEx(A.project) end
  local cx=xx(cursor)
  if cx>=0 and cx<=width then lline(cx,28,cx,height,C.text,.60) end
  A.hover=nil
  if mx and data then
    local t=Core.x_time(mx,first,last,width); local r=Core.row(data,t)
    if r then
      local iv=not (Live.run and t>Live.run.last+1e-8) and r.i or nil
      A.hover={time=t,s=r.s,m=r.m,i=iv,rms=r.rms,peak=r.peak}
      lline(mx,28,mx,bottom,C.text,.4)
      local label=Core.clock(t)..'   S '..value(r.s)..'   M '..value(r.m)..'   I RUN '..value(iv)..' LUFS'
      local boxw=min(555,width-16); local bx=Core.clamp(mx+14,8,max(8,width-boxw-8))
      lrect(bx,29,boxw,19,C.panel); ltext(label,bx+7,29,boxw-12,C.text)
    end
  end
end

function Core.present_graph(hwnd,bitmap,x1,x2,destY,sourceY,height)
  if x2<=x1 or height<=0 then return end
  if Platform.windows and R.JS_GDI_GetClientDC and R.JS_GDI_ReleaseDC and R.JS_LICE_GetDC and R.JS_GDI_Blit then
    local dc=R.JS_GDI_GetClientDC(hwnd)
    if dc then
      local ok,err=pcall(function()
        local source=R.JS_LICE_GetDC(bitmap);assert(source,'Graph bitmap DC unavailable')
        R.JS_GDI_Blit(dc,x1,destY,source,x1,sourceY,x2-x1,height,'SRCCOPY')
      end)
      R.JS_GDI_ReleaseDC(dc,hwnd)
      if ok then return end
      BLT.logError(err)
    end
  end
  R.JS_Window_InvalidateRect(hwnd,x1,destY,x2,destY+height,false)
end
local function overlay(now)
  if not S.visible then unlink(); return end
  if not valid_track() then unlink(); return end
  if R.CountTrackMediaItems(A.track)>0 or R.TrackFX_GetCount(A.track)>0 then
    unlink(); return
  end
  local hwnd=R.JS_Window_FindChildByID(R.GetMainHwnd(),1000)
  if not hwnd then unlink(); return end
  if Platform.mac and A.macCheckedArrange~=hwnd then
    if A.macMetalRetryAt and now<A.macMetalRetryAt then return end
    local mode=R.JS_Window_EnableMetal(hwnd)
    if mode==1 then
      A.macMetalRetryAt=now+1
      if A.macMetalNotice~=hwnd then
        A.macMetalNotice=hwnd
        Language.mb("現在のMetal設定ではグラフを重ね描画できません。REAPERの高度なUI設定でMetalを無効にするか、描画互換モードを選び、必要に応じてREAPERを再起動してください。", "LOUDNESS TRACE",0)
      end
      unlink();return
    end
    A.macCheckedArrange=hwnd;A.macMetalNotice=nil;A.macMetalRetryAt=nil
  end
  if A.arrange~=hwnd then dispose_bitmap(); A.arrange=hwnd end
  configure_composite_delay(hwnd)
  local ok,width,vh=R.JS_Window_GetClientSize(hwnd)
  if not ok or width<100 or vh<30 then unlink(); return end
  local y=floor(R.GetMediaTrackInfo_Value(A.track,"I_TCPY"))
  local height=floor(R.GetMediaTrackInfo_Value(A.track,"I_TCPH"))
  local destY,visible,sourceY=Core.clip_track(y,height,vh)
  if visible<1 or height<1 or R.GetMediaTrackInfo_Value(A.track,"B_SHOWINTCP")==0 then unlink(); return end
  if width>12000 or height>4000 then unlink(); return end
  if A.bw~=width or A.bh~=height or not A.bitmap or not A.backBitmap then
    dispose_bitmap(); A.arrange=hwnd; configure_composite_delay(hwnd)
    A.bitmap=R.JS_LICE_CreateBitmap(true,width,height)
    A.backBitmap=R.JS_LICE_CreateBitmap(true,width,height)
    if not A.bitmap or not A.backBitmap then error("描画用ビットマップを作成できません。") end
    -- The linked front bitmap is never cleared while visible.  All expensive drawing
    -- happens in the hidden back buffer, then one native blit publishes a complete frame.
    R.JS_LICE_Clear(A.bitmap,argb(C.bg))
    R.JS_LICE_Clear(A.backBitmap,argb(C.bg))
    A.bw,A.bh=width,height
  end
  local screenX=R.JS_Window_ClientToScreen(hwnd,0,0)
  local first,last=R.GetSet_ArrangeView2(A.project,false,screenX,screenX+width,0,0)
  if last<=first then unlink(); return end
  local mouseX,mouseY=R.GetMousePosition()
  local clientMouseX,clientMouseY=R.JS_Window_ScreenToClient(hwnd,mouseX,mouseY)
  local hovering=clientMouseX>=0 and clientMouseX<width and clientMouseY>=destY and clientMouseY<destY+visible and R.JS_Window_FromPoint(mouseX,mouseY)==hwnd
  local mx=hovering and floor(clientMouseX) or nil
  local cursor=R.GetCursorPositionEx(A.project)
  if (R.GetPlayStateEx(A.project)&1)==1 then cursor=R.GetPlayPositionEx(A.project) end
  local cursorPixel=floor(Core.time_x(cursor,first,last,width))

  local pointerInArrange=clientMouseX>=0 and clientMouseX<width and clientMouseY>=0 and clientMouseY<vh and R.JS_Window_FromPoint(mouseX,mouseY)==hwnd
  local arrangeMouseX=pointerInArrange and floor(clientMouseX) or nil
  local function queue_mouse_repair(x1,x2,delay)
    if x1==nil or x2==nil then return end
    if x2<x1 then x1,x2=x2,x1 end
    local q=A.mouseRepairQueue

    while #q>=128 do table.remove(q,1) end
    q[#q+1]={due=now+(delay or .030),x1=x1,x2=x2}
  end
  local function extend_mouse_sweep(a,b)
    if b<a then a,b=b,a end
    A.mouseSweepMin=A.mouseSweepMin and min(A.mouseSweepMin,a) or a
    A.mouseSweepMax=A.mouseSweepMax and max(A.mouseSweepMax,b) or b
    A.lastMouseMoveAt=now
  end
  if arrangeMouseX then
    if A.lastArrangeMouseX~=nil and arrangeMouseX~=A.lastArrangeMouseX then
      local a=min(A.lastArrangeMouseX,arrangeMouseX)-7
      local b=max(A.lastArrangeMouseX,arrangeMouseX)+8

      queue_mouse_repair(a,b,.020)
      queue_mouse_repair(a,b,.075)
      extend_mouse_sweep(a,b)
    end
    A.lastArrangeMouseX=arrangeMouseX
  elseif A.lastArrangeMouseX~=nil then
    local a=A.lastArrangeMouseX-7; local b=A.lastArrangeMouseX+8
    queue_mouse_repair(a,b,.025)
    queue_mouse_repair(a,b,.095)
    extend_mouse_sweep(a,b)
    A.lastArrangeMouseX=nil
  end

  if A.mouseSweepMin and A.lastMouseMoveAt and now-A.lastMouseMoveAt>=.050 then
    local a=A.mouseSweepMin-4
    local b=A.mouseSweepMax+4

    queue_mouse_repair(a,b,.005)
    queue_mouse_repair(a,b,.085)
    queue_mouse_repair(a,b,.180)
    queue_mouse_repair(a,b,.320)
    A.mouseSweepMin=nil; A.mouseSweepMax=nil; A.lastMouseMoveAt=nil
  end

  local contentKey=table.concat({width,height,first,last,A.revision,tostring(A.stale),mx or -1},":")
  local key=contentKey..":"..cursorPixel
  local layout=table.concat({width,height,destY,visible,sourceY},":")

  local redraw=key~=A.cache and (A.cache=="" or now-A.lastPaint>=.05)
  local cursorOnly=Platform.mac and redraw and A.cache~="" and A.linked and layout==A.layoutCache and A.graphContentKey==contentKey
  local previousCursor=A.graphCursorPixel
  local dirtyLeft,dirtyRight
  local function present(left,right)
    if right<=left then return end
    if Platform.mac then
      dirtyLeft=dirtyLeft and min(dirtyLeft,left) or left;dirtyRight=dirtyRight and max(dirtyRight,right) or right
    else Core.present_graph(hwnd,A.bitmap,left,right,destY,sourceY,visible) end
  end
  if redraw then
    A.drawBitmap=A.backBitmap
    chart(width,height,first,last,mx)
    A.drawBitmap=nil
    R.JS_LICE_Blit(A.bitmap,0,0,A.backBitmap,0,0,width,height,1,"COPY")
    A.cache=key;A.lastPaint=now;A.graphContentKey=contentKey;A.graphCursorPixel=cursorPixel
  end
  local moved=not A.linked or layout~=A.layoutCache
  if moved then
    local old=A.paintRect
    local code=R.JS_Composite(hwnd,0,destY,width,visible,A.bitmap,0,sourceY,width,visible,false)
    if code~=1 then error("JS_Composite failed: "..tostring(code)) end
    A.linked=true;A.layoutCache=layout;A.paintRect={top=destY,bottom=destY+visible,width=width}

    if old then
      if old.top<destY then R.JS_Window_InvalidateRect(hwnd,0,old.top,old.width,min(old.bottom,destY),false) end
      if old.bottom>destY+visible then R.JS_Window_InvalidateRect(hwnd,0,max(old.top,destY+visible),old.width,old.bottom,false) end
    end
  end
  if redraw or moved then
    if cursorOnly and not moved and previousCursor then

      present(max(0,min(previousCursor,cursorPixel)-3),min(width,max(previousCursor,cursorPixel)+4))
    else present(0,width) end
  end

  if A.linked and A.mouseRepairQueue and #A.mouseRepairQueue>0 then
    local processed=0
    local i=1
    while i<=#A.mouseRepairQueue and processed<24 do
      local r=A.mouseRepairQueue[i]
      if r.due<=now then
        table.remove(A.mouseRepairQueue,i)
        local x1=max(0,floor(r.x1)); local x2=min(width,math.ceil(r.x2))
        if x2>x1 then present(x1,x2) end
        processed=processed+1
      else
        i=i+1
      end
    end
  end

  if dirtyLeft then Core.present_graph(hwnd,A.bitmap,dirtyLeft,dirtyRight,destY,sourceY,visible) end
end


local scale,ox,oy=1,0,0
local widgets,widgetByID={},{}
local widgetCount=0
local function register(id,x,y,w,h,fn,enabled)
 local item=widgetByID[id]
 if not item then item={id=id};widgetByID[id]=item end
 item.x,item.y,item.w,item.h,item.fn,item.enabled=x,y,w,h,fn,enabled~=false
 widgetCount=widgetCount+1;widgets[widgetCount]=item;return item
end
local function inside(x,y,w,h)
 local mx,my=(gfx.mouse_x-ox)/scale,(gfx.mouse_y-oy)/scale
 return mx>=x and mx<x+w and my>=y and my<y+h
end
local function color(c,a) gfx.set(c[1],c[2],c[3],a or 1) end
local function rect(x,y,w,h,c,a) color(c,a);gfx.rect(ox+x*scale,oy+y*scale,w*scale,h*scale,1) end
local function line(x,y,xx,yy,c,a) color(c,a);gfx.line(ox+x*scale,oy+y*scale,ox+xx*scale,oy+yy*scale,1) end
local function disc(x,y,r,c,a) color(c,a);gfx.circle(ox+x*scale,oy+y*scale,r*scale,1,1) end

local function temp_file_exists(path)
  if type(path)~='string' or path=='' then return false end
  if type(R.file_exists)=='function' then return R.file_exists(path) end
  local file=io.open(path,'rb');if file then file:close();return true end
  return false
end
local function remove_temp_file(path)
  if not temp_file_exists(path) then return true end
  local ok,result=pcall(os.remove,path)
  return ok and result and true or false
end
local function retry_temp_deletes(force)
  local now=R.time_precise()
  if not force and now<(A.tempDeleteRetryAt or 0) then return end
  A.tempDeleteRetryAt=now+5
  for path in pairs(A.tempDeletePending or {}) do
    if remove_temp_file(path) then A.tempDeletePending[path]=nil end
  end
end
local function close_measurement(job)
  if job and job.offline then Core.offline.close(R,job.offline);job.offline=nil end
end

local function trigger_analysis_finish_burst()
 local b=A.collapsed and Core.analysis_button.compact or Core.analysis_button.normal
 U.now=R.time_precise();U:complete('measure',b.w/BLT.Controls.compactScale,b.h/BLT.Controls.compactScale);wake_visuals()
end

local function cancel_job(restoreLive)
  if not A.job then return end
  local job=A.job; A.job=nil; close_measurement(job)
  if restoreLive~=false then Live.restore_after_measure(job) end
end
local function measurement_status(job)
  if job.phase=='prepare' then return '解析準備中' end
  if job.phase=='render' then return 'ドライレンダー解析中' end
  return string.format('解析中 %d%%',floor(job.progress*100))
end
local function measure()
 if not Media.ready(true,true) then return end
  if A.job then return end
  if R.GetPlayStateEx(A.project)~=0 then return end
  if math.abs(R.Master_GetPlayRate(A.project)-1)>.000001 then return end
  local first,last=R.GetSet_LoopTimeRange2(A.project,false,false,0,0,false)
  if last-first<.4 then return end
  if last-first>12600 then return end
  if A.historyBlocked then Live.message(A.historyProblem or '保存グラフを復元できません。元のデータは保持しています。',true);return end
  local name=source_name()
  set_graph_track_visible(true)
  local job={project=A.project,first=first,last=last,source=S.source,name=name,progress=0,phase='prepare',resumeLive=Live.enabled,layout=Core.layout(A.layout)}
  A.job=job
  local prepared,ready=xpcall(Live.prepare_offline,debug.traceback)
  if not prepared or not ready then
    cancel_job()
    if not prepared then Live.message(public_error(ready),true) end
    return
  end
  job.co=coroutine.create(function()
    job.phase='render'
    coroutine.yield()
    assert(R.EnumProjects(-1,'')==job.project,'測定開始前にプロジェクトが切り替わりました。')
    local current_first,current_last=R.GetSet_LoopTimeRange2(job.project,false,false,0,0,false)
    assert(math.abs(current_first-first)<=1e-9 and math.abs(current_last-last)<=1e-9,'測定開始前に時間選択が変更されました。')
    local deadline=R.time_precise()+.020
    local function tick(p)
      job.progress=p
      if R.time_precise()>=deadline then coroutine.yield(); deadline=R.time_precise()+.020 end
    end
    local data=Core.offline.measure(R,job,tick)
    data.first,data.last,data.source,data.name=first,last,job.source,name
    data=Core.replace_range(A.data,data)
    job.prunedRows=Core.trim_history(data,MAX_HISTORY_ROWS)
    Core.recompute(data,tick)
    job.result=data; job.progress=1
  end)
end
local function step_job()
  local job=A.job
  if not job then return end
  if job.phase=='prepare' and not Media.ready() then return end
  local ok,err=coroutine.resume(job.co)
  if not ok then
    cancel_job()
    Language.mb(public_error(err),'LOUDNESS TRACE | 解析',0); return
  end
  if coroutine.status(job.co)=='dead' then
    close_measurement(job); A.job=nil
    if R.EnumProjects(-1,'')~=job.project then return end
    trigger_analysis_finish_burst()
    local changed=R.GetProjectStateChangeCount(A.project)~=job.renderState
    local saved,why=pcall(save_data,job.result)
    A.data=job.result
    collectgarbage('step',800)
    A.stale=changed; A.revision=A.revision+1; A.baseline=R.GetProjectStateChangeCount(A.project)
    if not saved then Live.dirty=true;Language.mb(public_error(why),'LOUDNESS TRACE | 保存',0) end
    Live.notice='解析完了：高速解析（一時WAVなし）'
    Live.noticeBad=false
    Live.restore_after_measure(job)
  end
end


local function change_height(h)
  S.height=h
  if valid_track() then
    R.SetMediaTrackInfo_Value(A.track,"I_HEIGHTOVERRIDE",h); R.TrackList_AdjustWindows(false)
  end
  A.cache=""
end
local function edited()
  A.revision=A.revision+1;save_settings()
end

function A.flash_field(id) U:flash(id);A.flashUntil=R.time_precise()+.9;wake_visuals() end

function A.apply_number_field(field,raw,save)
  if not field or not Core.finite(raw) then return false end
  local value,clipped=raw,false
  if field.normalize then value,clipped=field.normalize(raw) end
  if not Core.finite(value) then return false end
  local rounded=Core.round(value,field.digits or 2)
  clipped=clipped or math.abs(rounded-raw)>1e-12;value=rounded
  local old=field.get and field.get() or nil
  if old==nil or math.abs(value-old)>1e-12 then
    if not field.set(value) then return false end
    if save then edited() end
  end
  if clipped then A.flash_field(field.id) end
  return true
end
function A.update_field_drag(py,fine)
  local d=A.fieldDrag;if not d then return end
  local dy=d.startY-py
  if not d.moved and math.abs(dy)<3 then return end
  d.moved=true
  fine=fine and (d.field.step or 1)<1
  local inc=(d.field.step or 1)*(fine and .1 or 1)
  local pixels=fine and 8 or 3
  local q=dy/pixels;local ticks=(q<0 and -1 or 1)*floor(math.abs(q)+.5)
  local raw=d.startValue+ticks*inc
  local value,clipped=raw,false
  if d.field.normalize then value,clipped=d.field.normalize(raw) end
  value=Core.round(value,d.field.digits or 2);clipped=clipped or math.abs(value-raw)>1e-12
  if clipped and not d.clipped then A.flash_field(d.field.id);d.clipped=true elseif not clipped then d.clipped=false end
  if Core.finite(value) and math.abs(value-d.field.get())>1e-12 and d.field.set(value) then edited() end
end

local function number_text(value,digits)
  digits=digits or 2
  local text=string.format('%.'..digits..'f',Core.round(value,digits))
  return digits>0 and text:gsub('0+$',''):gsub('%.$','') or text
end

local function auto_axis_range()
  local data=A.data
  if not data then return end
  local values={}
  local function push(v)
    if Core.finite(v) and v>-120 and v<24 then values[#values+1]=v end
  end
  local enabled={}
  for _,k in ipairs({'s','m','i','rms','peak'}) do if S.show[k] then enabled[#enabled+1]=k end end
  for _,seg in ipairs(data.segments) do
    local duration=seg.last-seg.first

    local settle=min(3.0,max(.5,duration*.16))
    local stableStart=seg.first+settle
    local added=0
    for _,r in ipairs(seg.rows) do
      if r.time>=stableStart then
        for _,k in ipairs(enabled) do
          local n=#values; push(r[k]); if #values>n then added=added+1 end
        end
      end
    end

    if added==0 then
      for _,r in ipairs(seg.rows) do
        for _,k in ipairs(enabled) do push(r[k]) end
      end
    end
  end
  if #values==0 then return end
  table.sort(values)
  local function percentile(p)
    if #values==1 then return values[1] end
    local pos=1+(#values-1)*p
    local i=floor(pos); local f=pos-i
    return values[i]+((values[min(#values,i+1)]-values[i])*f)
  end
  local lo=#values>=12 and percentile(.02) or values[1]
  local hi=#values>=12 and percentile(.98) or values[#values]
  if hi-lo<4 then local mid=(hi+lo)*.5;lo,hi=mid-2,mid+2 end
  local pad=max(2,(hi-lo)*.09)
  lo=floor((lo-pad)/2)*2
  hi=math.ceil((hi+pad)/2)*2
  if hi-lo<12 then local mid=(hi+lo)*.5;lo=floor((mid-6)/2)*2;hi=math.ceil((mid+6)/2)*2 end
  S.lo=Core.clamp(lo,-120,18); S.hi=Core.clamp(hi,S.lo+2,24)
  edited(); A.cache=''
end


local TCP={width=88,height=24}
local function tcp_dispose()
 if TCP.window then
  pcall(reaper.JS_Composite_Unlink,TCP.window,TCP.bitmap,true)
  pcall(reaper.JS_Window_Destroy,TCP.window);TCP.window=nil
 end
 if TCP.bitmap then R.JS_LICE_DestroyBitmap(TCP.bitmap);TCP.bitmap=nil end
 TCP.parent=nil;TCP.signature=nil;TCP.position=nil;TCP.down=nil
end
local function tcp_button(now)
 if TCP.supported==nil then
  TCP.supported=true
  for _,name in ipairs({'GetThingFromPoint','JS_Window_Create','JS_Window_SetParent','JS_Window_Destroy','JS_Window_Show','JS_WindowMessage_Intercept','JS_WindowMessage_Peek'}) do
   if type(reaper[name])~='function' then TCP.supported=false;break end
  end
 end
 if not TCP.supported then return end
 if not valid_track() or R.GetMediaTrackInfo_Value(A.track,'B_SHOWINTCP')==0 then tcp_dispose();return end
 if not TCP.geometryAt or now>=TCP.geometryAt then
  TCP.geometryAt=now+.1
  local arrange=R.JS_Window_FindChildByID(R.GetMainHwnd(),1000)
  if not arrange then tcp_dispose();return end
  local ax,ay=R.JS_Window_ClientToScreen(arrange,0,0)
  local ok,aw,ah=R.JS_Window_GetClientSize(arrange)
  local ty=R.GetMediaTrackInfo_Value(A.track,'I_TCPY');local th=R.GetMediaTrackInfo_Value(A.track,'I_TCPH')
  if not ok or th<48 or ty<0 or ty+th>ah then tcp_dispose();return end
  local sy=ay+ty+th-TCP.height-8;local nativeY=Platform.mac and -sy or sy
  local track,where=reaper.GetThingFromPoint(ax-4,Platform.mac and -(sy+12) or sy+12)
  if track~=A.track or not tostring(where):find('tcp',1,true) then tcp_dispose();return end
  local parent=reaper.JS_Window_FromPoint(ax-4,Platform.mac and -(sy+12) or sy+12)
  if not parent then tcp_dispose();return end
  local x,y=reaper.JS_Window_ScreenToClient(parent,ax-TCP.width-12,nativeY)
  local valid,cw,ch=reaper.JS_Window_GetClientSize(parent)
  if not valid or x<0 or y<0 or x+TCP.width>cw or y+TCP.height>ch then tcp_dispose();return end
  if Platform.mac and reaper.JS_Window_EnableMetal(parent)==1 then tcp_dispose();return end
  if TCP.parent~=parent or not TCP.window or not R.JS_Window_IsWindow(TCP.window) then
   tcp_dispose();TCP.parent=parent
   TCP.window=reaper.JS_Window_Create('BLT TRACE Analyze','BLT_TRACE_TCP',x,y,TCP.width,TCP.height,'CHILD,VISIBLE',parent)
   if not TCP.window then TCP.supported=false;return end
   reaper.JS_Window_SetParent(TCP.window,parent)
   reaper.JS_Window_SetPosition(TCP.window,x,y,TCP.width,TCP.height,'TOP','NOACTIVATE');TCP.position=x..':'..y
   for _,msg in ipairs({'WM_LBUTTONDOWN','WM_LBUTTONUP'}) do
    if reaper.JS_WindowMessage_Intercept(TCP.window,msg,false)~=1 then tcp_dispose();TCP.supported=false;return end
   end
   TCP.bitmap=R.JS_LICE_CreateBitmap(true,TCP.width,TCP.height)
   if not TCP.bitmap then tcp_dispose();return end
  end
  local position=x..':'..y
  if TCP.position~=position then reaper.JS_Window_SetPosition(TCP.window,x,y,TCP.width,TCP.height,'TOP','NOACTIVATE');TCP.position=position end
 end
 if not TCP.window then return end
 local down,_,dt=reaper.JS_WindowMessage_Peek(TCP.window,'WM_LBUTTONDOWN')
 if down and dt~=TCP.lastDown then TCP.lastDown=dt;TCP.down=dt end
 local up,_,ut,_,_,x,y=reaper.JS_WindowMessage_Peek(TCP.window,'WM_LBUTTONUP')
 if up and ut~=TCP.lastUp then
  TCP.lastUp=ut
  if TCP.down and ut>=TCP.down and x>=0 and y>=0 and x<TCP.width and y<TCP.height then
   TCP.down=nil;if A.job then cancel_job() else measure() end
  end
  TCP.down=nil
 end
 local label=A.job and Language.text('中止') or Language.text('解析')
 local signature=label..table.concat(C.accent2,':')..table.concat(C.field,':')..table.concat(C.text,':')
 if signature~=TCP.signature then
  R.JS_LICE_Clear(TCP.bitmap,argb(C.field))
  R.JS_LICE_FillRect(TCP.bitmap,0,TCP.height-2,TCP.width,2,argb(C.accent2),1,'COPY')
  R.JS_LICE_SetFontColor(A.font,argb(C.text))
  R.JS_LICE_DrawText(TCP.bitmap,A.font,label,#label,10,3,TCP.width-4,TCP.height)
  local code=R.JS_Composite(TCP.window,0,0,TCP.width,TCP.height,TCP.bitmap,0,0,TCP.width,TCP.height,true)
  if code~=1 then tcp_dispose();return end
  R.JS_Window_InvalidateRect(TCP.window,0,0,TCP.width,TCP.height,false);TCP.signature=signature
 end
end


BLT.factorySettings={lo=-60,hi=0,visible=true,height=280,show={s=true,m=true,i=true,rms=false,peak=false},targets={s={-23,3},m={-23,3},i={-23,1}},source="master",alertUpper=false,alertLower=false,alertPeak=false}
function Live.warnings(data)
  local run=Live.run;local h=run.summary;local a,b=S.targets.s,S.targets.m
  if h.targets.s[1]~=a[1] or h.targets.s[2]~=a[2] or h.targets.m[1]~=b[1] or h.targets.m[2]~=b[2] then
    h=Core.history_summary(Live.previous,run.first,S.targets)
    for _,row in ipairs(run.rows) do run.integrated,run.lra=h.feed(row) end
    run.summary=h
  end
  return h.warning[1]*.1,h.warning[2]*.1,h.warning[3]*.1
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
if not reaper.ImGui_GetBuiltinPath then
 Language.mb('ReaImGui 0.10以降が必要です。ReaPackで導入・更新してください。','LOUDNESS TRACE',0);return
end
local ok,hostValue=pcall(BLT.CanvasHost.new,reaper,'LOUDNESS TRACE',W,H+26,SECTION)
if not ok then Language.mb(public_error(hostValue),'LOUDNESS TRACE',0);return end
Host=hostValue;Host.minWidth,Host.minHeight=520,327
local savedHeight=extnum('window_h',H)
if R.GetExtState(SECTION,'status_row_layout')~='1' then
 if R.GetExtState(SECTION,'window_h')~='' then savedHeight=savedHeight-24 end
 savedHeight=Core.clamp(savedHeight,301,1000)
 BLT.store(SECTION,'window_h',savedHeight,true);BLT.store(SECTION,'status_row_layout','1',true)
end
Host.width,Host.height=Core.clamp(extnum('window_w',W),520,1200),Core.clamp(savedHeight,301,1000)+26
local I,ctx=Host.I,Host.ctx
gfx=Host.g
mediaGraphics.getchar=function() return Host.focused and 6 or 4 end
for key,c in pairs({bg2={.03,.09,.18},panel2={.055,.125,.205},edge2={.36,.65,.9},disabled={.43,.46,.51},
 accent2=C.ice,accent3=C.deep,focus={.225,.61,1},focus2={.69,.9,1},ink={.018,.075,.16},hover={.43,.79,1},quiet={.3,.36,.44}}) do C[key]=c end
U=BLT.Controls.new(gfx,R.time_precise,C);U.font,U.minFontSize=Host.faces[1],7
local density=BLT.Controls.compactScale
local function text(s,x,y,size,c,w,kind,bold,literal)
 gfx.setfont(1,Host.faces[kind==2 and 3 or kind==3 and 2 or 1],max(7,floor(size*scale+.5)),bold and 98 or 0)
 color(c or C.text);gfx.x,gfx.y=ox+x*scale,oy+y*scale
 gfx.drawstr(literal and tostring(s) or Language.message(s),0,ox+(x+(w or W-x-20))*scale,oy+(y+size+8)*scale)
end
local function commit_edit(cancel)
 if U.editor.edit then U.editor:close(cancel) end
 return true
end
local function release()
 A.fieldDrag=nil;A.pressed=nil;U.capture=nil;Host.pointerCapture=nil
end
menu=BLT.PresetMenu.new(Host,U,{presets=Presets,language=Language,commit=commit_edit,
 layout={width=292,rowHeight=29,headerHeight=36,visiblePresets=8,hoverDelay=1},busy=function() return A.job~=nil or A.windowTransition~=nil end})
shell=BLT.Shell.new(Host,U,reaper,{title='LOUDNESS TRACE',barTitle='L O U D N E S S   T R A C E',
 subtitle='ARRANGE LOUDNESS ANALYSIS  アレンジビュー上でラウドネスを解析・表示',section=SECTION,persist=true,
 layout={iconX=W-102,iconY=6,iconScale=.78,footerSize=8},
 language=Language.code,languageChanged=function(code) commit_edit();Language.set(code);wake_visuals() end,
 translate=Language.message,store=BLT.store,headerIcon=BLT.LoudnessTraceIcon,
 iconMode=function() return A.job and 'analyze' or 'trace' end,
 themeChanged=function() A.cache='';wake_visuals() end,
 compact=function() return A.collapsed end,fold=function() A.requestFold=true end,
 stepPreset=function(direction) commit_edit();Presets.step(direction) end,
 drawPresets=function(owner) menu:draw(owner) end,presetSize=function() return menu:size() end,dirty=Presets.dirty})
U.editor=BLT.TextInput.new(Host,U,shell.typography)
controls=BLT.EnvelopeWidgets.new(Host,U,density)
function BLT.blocked() return shell.popupOpen or Host.drag~=nil or gfx.mouse_y<26 or A.windowTransition~=nil end
BLT.host={wake=wake_visuals}
Media.state=A;Media.onchange=wake_visuals;Media.all_items=true
BLT.attachPresets({R=R,section=SECTION,defaults=BLT.factorySettings,capture=function() return S end,
 valid=function(v)
  if v.lo< -120 or v.hi>24 or v.lo>=v.hi or v.height<100 or v.height>1000 or v.source~='master' then return false end
  for _,t in pairs(v.targets) do if #t~=2 or t[1]< -120 or t[1]>24 or t[2]<0 or t[2]>120 then return false end end
  return true
 end,apply=function(v)
  local hc,vc=S.height~=v.height,S.visible~=v.visible
  for k,x in pairs(v) do S[k]=x end
  if hc then change_height(S.height) end
  if vc then set_graph_track_visible(S.visible) end
  edited();wake_visuals()
 end,busy=function() return A.job~=nil or A.windowTransition~=nil end,commit=commit_edit,
 cancelEdit=function() commit_edit(true);release() end,wake=wake_visuals})
local presetDirty=Presets.dirty
function Presets.dirty()
 local cache=Presets.dirtyCache
 if not cache or cache.current~=Presets.current or cache.revision~=A.revision or cache.visible~=S.visible then
  cache=cache or {};Presets.dirtyCache=cache
  cache.current,cache.revision,cache.visible,cache.value=Presets.current,A.revision,S.visible,presetDirty()
 end
 return cache.value
end
local defaultOptions={size=12/density,bold=true}
local clearOptions={variant='clear',size=12/density,bold=true}
local toggleOptions={size=12/density,bold=true,led='left'}
local execution={cancelable=true,autoComplete=false,finishWhenDisabled=true,bold=true}
local function execution_button(label,x,y,w,h,caption)
 local compact=A.collapsed
 local first,last=R.GetSet_LoopTimeRange2(A.project,false,false,0,0,false)
 local enabled=A.job~=nil or R.GetPlayStateEx(A.project)==0 and math.abs(R.Master_GetPlayRate(A.project)-1)<=.000001 and last-first>=.4 and last-first<=12600 and not A.historyBlocked and not Media.waiting
 execution.enabled,execution.busy,execution.progress=enabled,A.job~=nil,A.job and A.job.progress or nil
 execution.caption=caption;execution.captionY,execution.captionHeight,execution.captionSize=(compact and 2 or 2)/density,11/density,(compact and 7 or 8)/density
 execution.labelY,execution.labelHeight,execution.size=(compact and 13 or 14)/density,(compact and 17 or 23)/density,(compact and 12 or 16)/density
 U:execute('measure',Language.message(label),x/density,y/density,w/density,h/density,execution)
 register('measure',x,y,w,h,function() if A.job then cancel_job() else measure() end end,enabled)
end
local function button(id,label,x,y,w,h,fn,primary,selected,eyebrow)
 if primary then execution_button(label,x,y,w,h,eyebrow);return end
 local enabled=id~='clear' or not A.job and (A.data~=nil or Live.enabled)
 controls:button(id,Language.message(label),x,y,w,h,enabled,selected,nil,id=='clear' and clearOptions or defaultOptions)
 register(id,x,y,w,h,fn,enabled)
end
local function toggle(key,label,x,y,w,h)
 controls:button('toggle_'..key,Language.message(label),x,y,w,h,true,S.show[key],nil,toggleOptions)
 register('toggle_'..key,x,y,w,h,function()
  S.show[key]=not S.show[key]
  if S.show[key] and not graph_track_is_visible() then set_graph_track_visible(true) end
  edited();wake_visuals()
 end)
end
local switchOptions={background=false,showState=false,switchScale=24/(44*density),size=12/density,labelOffset=32/density,bold=true}
local liveOptions={bold=true}
local function option_switch(id,top,bottom,x,y,w,on,fn)
 switchOptions.hitLabel=top..'\n'..bottom
 local _,_,hitWidth=U:toggle(id,'',on,x/density,y/density,w/density,38/density,true,switchOptions)
 text(top,x+32,y+2,12,U:toggleColor(on,true),w-32,nil,true);text(bottom,x+32,y+18,12,on and C.muted or C.disabled,w-32)
 register(id,x,y,hitWidth*density,38,fn)
end
function Live.draw_button(x,y,w,h,compact)
 local enabled=not A.job or Live.enabled
 liveOptions.enabled,liveOptions.ledScale=enabled,h/(44*density)
 liveOptions.size,liveOptions.stateSize=(compact and 8 or 12)/density,(compact and 7 or 8)/density
 liveOptions.onText=compact and 'ON' or Live.phase=='writing' and 'ON / RECORDING' or 'ON / WAIT'
 U:gold('live',Language.text(compact and 'LIVE' or 'リアルタイム'),Live.enabled,x/density,y/density,w/density,h/density,liveOptions)
 register('live',x,y,w,h,function() commit_edit();Live.toggle();wake_visuals() end,enabled)
end
local numberOptions={left=36,right=5,size=13}
local numberCache={}
local function number_field(id,label,x,y,w,get,set,step,h,normalize,digits)
 h=h or 28
 local field=register(id,x,y,w,h,nil)
 field.field,field.get,field.set,field.step,field.normalize,field.digits=true,get,set,step or 1,normalize,digits or 2
 local v=get();local cache=numberCache[id]
 if not cache or cache.value~=v then cache=cache or {};numberCache[id]=cache;cache.value,cache.text=v,number_text(v,digits) end
 controls:number(id,cache.text,x,y,w,h,true,numberOptions)
 gfx.setfont(1,Host.faces[1],max(7,floor(10*scale+.5)),0);color(C.faint)
 gfx.x,gfx.y=ox+(x+5)*scale,oy+y*scale;gfx.drawstr(Language.message(label),4,ox+(x+35)*scale,oy+(y+h)*scale)
 field.fn=function()
  local current=widgetByID[id]
  U.editor:open(id,number_text(current.get(),current.digits),function(raw)
   local n=tonumber(raw)
   if Core.finite(n) then A.apply_number_field(current,n,true) else A.flash_field(id) end
   wake_visuals()
  end);U.focus=id;wake_visuals()
 end
end
local function target_fields(key,x,y,w)
 local half=(w-6)/2
 number_field('goal_'..key,'目標',x,y,half,function() return S.targets[key][1] end,function(v) S.targets[key][1]=v;return true end,1,nil,
  function(v) local n=Core.clamp(v,-150,24);return n,n~=v end,2)
 number_field('tol_'..key,'±LU',x+half+6,y,half,function() return S.targets[key][2] end,function(v) S.targets[key][2]=v;return true end,1,nil,
  function(v) local n=Core.clamp(v,0,60);return n,n~=v end,2)
end
function Live.select_layout() if not A.job then UI.layoutPopup=true;wake_visuals() end end
local sourceOptions={size=12/density,bold=true,labelInset=140/density}
local function source_display(name,x,y,w,h)
 controls:button('layout',name,x,y,w,h,not A.job,nil,nil,sourceOptions)
 text('解析ソース',x+14,y+12,14,not A.job and C.ice or C.disabled,120,nil,true)
 line(x+w-20,y+19,x+w-16,y+23,C.muted,.8);line(x+w-16,y+23,x+w-12,y+19,C.muted,.8)
 register('layout',x,y,w,h,Live.select_layout,not A.job)
end
local function layout_menu()
 if UI.layoutPopup then I.OpenPopup(ctx,'##trace_layout');UI.layoutPopup=nil end
 I.PushFont(ctx,Host.font,13)
 if I.BeginPopup(ctx,'##trace_layout') then
  for _,layout in ipairs(Core.layouts) do
   I.BeginDisabled(ctx,A.job~=nil)
   if I.Selectable(ctx,layout.name,A.layout==layout.id) and layout.id~=A.layout and Live.prepare_offline() then
    A.layout=layout.id;R.SetProjExtState(A.project,SECTION,'measurement_layout',A.layout)
    History.select_layout(A.layout);load_data();Live.latest=nil;Live.warningCache=nil
    A.cache='';A.hover=nil;A.revision=A.revision+1;A.baseline=R.GetProjectStateChangeCount(A.project);wake_visuals()
   end
   I.EndDisabled(ctx)
  end
  I.EndPopup(ctx)
 end
 UI.layoutOpen=I.IsPopupOpen(ctx,'##trace_layout');I.PopFont(ctx)
end
local function inputs_mouse()
 local down=(gfx.mouse_cap&1)~=0
 if BLT.blocked() or UI.layoutOpen then A.down=down;A.pressed=nil;gfx.mouse_wheel=0;return end
 local hit
 for i=widgetCount,1,-1 do local w=widgets[i];if w.enabled and inside(w.x,w.y,w.w,w.h) then hit=w;break end end
 if U.editor.edit and hit and hit.id==U.editor.edit.id and not A.fieldDrag and gfx.mouse_wheel==0 then A.down=down;return end
 local wheel=gfx.mouse_wheel or 0
 if wheel~=0 and hit and hit.field then
  commit_edit();local multiplier=(gfx.mouse_cap&8)~=0 and hit.step<1 and .1 or (gfx.mouse_cap&4)~=0 and 10 or 1
  local ticks=max(1,floor(math.abs(wheel)/120+.5));A.apply_number_field(hit,hit.get()+(wheel>0 and 1 or -1)*ticks*hit.step*multiplier,true)
 end
 if down and not A.down then
  commit_edit();A.pressed=hit and hit.id
  if hit and hit.field then A.fieldDrag={field=hit,startY=(gfx.mouse_y-oy)/scale,startValue=hit.get(),moved=false,clipped=false} end
 elseif down and A.fieldDrag then A.update_field_drag((gfx.mouse_y-oy)/scale,(gfx.mouse_cap&8)~=0)
 elseif not down and A.down then
  local moved=A.fieldDrag and A.fieldDrag.moved;A.fieldDrag=nil
  if not moved and hit and hit.id==A.pressed then hit.fn();wake_visuals() end
  A.pressed=nil
 end
 A.down=down;gfx.mouse_wheel=0
end
local function normal_rect()
 return {x=Host.windowX or 100,y=Host.windowY or 100,w=gfx.w,h=gfx.h}
end
local function fold_window()
 if A.windowTransition then return end
 commit_edit();release();Host.drag=nil
 local from=normal_rect();local to
 if A.collapsed then
  local saved=A.normalWindow or {w=Host.width,h=Host.height}
  to={x=from.x+(from.w-saved.w)/2,y=from.y,w=saved.w,h=saved.h};A.collapsed=false
 else
  A.normalWindow=from
  to={x=from.x+(from.w-COLLAPSED_W)/2,y=from.y,w=COLLAPSED_W,h=COLLAPSED_H+26};A.collapsed=true
 end
 local x,y=Host:place(to.x,to.y,to.w,to.h);to.x,to.y=x,y
 A.windowTransition={from=from,to=to,start=R.time_precise()};Host.minWidth,Host.minHeight=1,1;wake_visuals()
end
local function step_window_transition(now)
 local t=A.windowTransition;if not t then return end
 local u=Core.clamp((now-t.start)/.2,0,1);local q=u*u*(3-2*u)
 local rect={}
 for _,key in ipairs({'x','y','w','h'}) do rect[key]=t.from[key]+(t.to[key]-t.from[key])*q end
 Host.nextRect=rect
 if u==1 then
  A.windowTransition=nil;Host.width,Host.height=t.to.w,t.to.h
  Host.minWidth,Host.minHeight=A.collapsed and 350 or 520,A.collapsed and 84 or 327
 end
end
function Host:savePosition()
 if not self.nativeX or A.windowTransition then return end
 local w,h,x,y=gfx.w,gfx.h,self.windowX,self.windowY
 if A.collapsed then local n=A.normalWindow;w,h=n.w,n.h;x=x+(gfx.w-w)/2 end
 x,y=I.PointConvertNative(ctx,x,y,true)
 for key,v in pairs({window_x=x,window_y=y,window_w=w,window_h=h-26}) do BLT.store(SECTION,key,v,true) end
end
local foldOptions={size=9/density,bold=true}
local function fold_control(id,x,y,w,h,collapse)
 controls:button(id,Language.text(collapse and '縮小' or '展開'),x,y,w,h,true,nil,nil,foldOptions)
 register(id,x,y,w,h,fold_window)
end
local function collapsed_controller()
 text('LOUDNESS TRACE',28,7,12.2,C.text,145,3,true)
 disc(15,16,1.7,(A.job or Live.enabled) and C.ice or C.mint,.85)
 local state=A.job and measurement_status(A.job) or Live.enabled and ('LIVE / '..(Live.phase=='writing' and 'RECORDING' or 'WAIT')) or 'TRACE ACTIVE'
 text(state,29,25,7.7,(A.job or Live.enabled) and C.ice or C.faint,140,3,true)
 fold_control('expand',78,39,48,16,false)
 Live.draw_button(183,15,60,28,true)
 local b=Core.analysis_button.compact
 execution_button(A.job and '中止' or '解析',b.x,b.y,b.w,b.h,A.job and 'CANCEL' or 'ANALYZE')
end
local function controller()
  source_display(source_name(),24,107,598,44)
  local data=A.data

  local pos=R.GetCursorPositionEx(A.project)
  if (R.GetPlayStateEx(A.project)&1)==1 then pos=R.GetPlayPositionEx(A.project) end
  local sample=A.hover or ((Live.enabled and Live.wasPlaying) and Live.latest) or Core.row(data,pos)
  local cardW=190
  for j,q in ipairs({{'s','LUFS-S  /  3 sec',C.ice},{'m','LUFS-M  /  400 ms',C.mint},{'i','Integrated',C.purple}}) do
    local x=24+(j-1)*204;local key,label,c=q[1],q[2],q[3]
    controls:panel(x,157,cardW,169);rect(x,157,cardW,3,c,.58)
    local v=key=='i' and (data and data.integrated) or (sample and sample[key])
    text(value(v),x+11,166,32,target_alert(v,S.targets[key]) and C.red or c,cardW-20,2)
    text(label,x+11,213,11.3,C.muted,cardW-18)
    if key=='i' then
      local lraText=data and data.lra and string.format('LRA %.1f LU',data.lra) or 'LRA —'
      text(lraText,x+91,213,10.3,C.gold,cardW-101,2)
    end
    target_fields(key,x+8,241,cardW-16)
    toggle(key,'グラフ '..(S.show[key] and 'ON' or 'OFF'),x+8,286,cardW-16,30)
  end
  controls:panel(24,336,598,86)
  local warnUp,warnDown,warnPeak=warning_durations(data)
  text('警告表示',36,347,12.5,C.muted,110)
  text('補助表示',346,347,12.5,C.muted,110)
  option_switch('alert_upper','上限','超過',36,366,92,S.alertUpper,function()
    S.alertUpper=not S.alertUpper;edited()
  end)
  option_switch('alert_lower','下限','未満',132,366,92,S.alertLower,function()
    S.alertLower=not S.alertLower;edited()
  end)
  option_switch('alert_peak','ピーク','超過',228,366,98,S.alertPeak,function()
    S.alertPeak=not S.alertPeak;edited()
  end)
  text(warning_time_text(warnUp),36,405,9.4,C.faint,92,2,true)
  text(warning_time_text(warnDown),132,405,9.4,C.faint,92,2,true)
  text(warning_time_text(warnPeak),228,405,9.4,C.faint,98,2,true)
  line(334,366,334,411,C.edge,.30)
  toggle('rms','RMS '..(S.show.rms and 'ON' or 'OFF'),346,375,126,30)
  rect(346,375,126,2,C.gold,.68)
  toggle('peak','Peak '..(S.show.peak and 'ON' or 'OFF'),484,375,126,30)
  rect(484,375,126,2,C.faint,.72)

  controls:panel(24,428,598,76)
  text('グラフ設定',36,435,12.2,C.muted,95)
  button('height','グラフ幅：'..S.height,36,455,100,40,function()
    local heights={200,280,380,520};local nextheight=200
    for i,h in ipairs(heights) do if S.height==h then nextheight=heights[i%#heights+1] end end
    change_height(nextheight);edited()
  end)
  number_field('axis_lo','下限',144,455,80,function() return S.lo end,function(v) S.lo=v;return true end,1,40,
    function(v) local n=Core.clamp(v,-120,min(18,S.hi-.1));return n,n~=v end)
  number_field('axis_hi','上限',232,455,80,function() return S.hi end,function(v) S.hi=v;return true end,1,40,
    function(v) local n=Core.clamp(v,max(-118,S.lo+.1),24);return n,n~=v end)
  button('auto_axis','解析結果へ最適化',320,455,132,40,auto_axis_range)
  local graphVisible=graph_track_is_visible()
  S.visible=graphVisible
  button('visible',graphVisible and 'グラフを非表示' or 'グラフを表示',460,455,150,40,function()
    set_graph_track_visible(not graph_track_is_visible())
  end)

  button('clear','グラフをクリア',24,531,126,32,function() clear_measurement() end)
  Live.draw_button(180,530,146,34,false)
  button('measure',A.job and (A.job.phase=='analyze' and ('解析を中止  '..floor(A.job.progress*100)..'%') or measurement_status(A.job)) or '選択範囲を解析',Core.analysis_button.normal.x,Core.analysis_button.normal.y,Core.analysis_button.normal.w,Core.analysis_button.normal.h,function()
    if A.job then cancel_job() else measure() end
  end,true,false,A.job and 'CANCEL' or 'ANALYZE')
  if A.job and A.job.phase=='analyze' then local b=Core.analysis_button.normal;rect(b.x,b.y+b.h+2,b.w*A.job.progress,2,C.ice,.8) end
  fold_control('collapse',(W-64)*.5,579,64,18,true,function() A.requestFold=true end)

  local status,bad
  if not A.job and (Live.enabled or Live.noticeBad or (Live.notice and not A.stale)) then status,bad=Live.status() else status=A.job and measurement_status(A.job) or (A.stale and 'プロジェクトが変更されています。再解析してください。' or (A.data and '解析結果を表示しています。' or '時間範囲を選択してください。'));bad=A.stale end
  if Media.waiting then status,bad=Media.message(SECTION),true elseif BLT.notice then status,bad=BLT.notice,BLT.noticeBad end
  U.scale,U.ox,U.oy=scale,ox,oy+22*scale;shell:footer(status,bad,W,H,VERSION)
  U.scale,U.ox,U.oy=density*scale,ox,oy
end

local function draw()
 local bw,bh=A.collapsed and COLLAPSED_W or W,A.collapsed and COLLAPSED_H or H
 scale=min(gfx.w/bw,max(1,gfx.h-26)/bh);ox=(gfx.w-bw*scale)/2;oy=26+(gfx.h-26-bh*scale)/2-(A.collapsed and 0 or 22*scale)
 shell:begin();U.active=Host.focused;U.themeEnabled=shell.theme.enabled
 color(C.bg);gfx.rect(0,0,gfx.w,gfx.h,1)
 if not A.collapsed then U.scale,U.ox,U.oy=scale,ox,oy+22*scale;shell:header(W)
 else shell.footerShown=nil;shell.icon:tick(R.time_precise(),false,false) end
 local key=gfx.getchar();local editing=U.editor.edit~=nil
 local wheel=gfx.mouse_wheel or 0;U:begin(density*scale,ox,oy,0);gfx.mouse_wheel=wheel
 inputs_mouse()
 if not editing and not shell.popupOpen and not UI.layoutOpen then
  if key==27 then A.requestClose=true
  elseif key==13 then if A.job then cancel_job() else measure() end;wake_visuals()
  elseif (gfx.mouse_cap&16)==0 and (key==26 or (gfx.mouse_cap&(Host.mac and 36 or 4))~=0 and (key==90 or key==122)) and not A.job then
   commit_edit();release()
   if Media.ready(true) then
    if (gfx.mouse_cap&8)~=0 then R.Undo_DoRedo2(A.project) else R.Undo_DoUndo2(A.project) end
    A.revision=A.revision+1;A.cache='';A.stale=A.data~=nil;wake_visuals()
   end
  end
 end
 widgetCount=0;local released=U.released;U.released=false
 if A.collapsed then collapsed_controller() else controller() end
 U.released=released;U:finish()
 for i=#widgets,widgetCount+1,-1 do widgets[i]=nil end
 U.scale,U.ox,U.oy=density*scale,ox,oy;shell:drawBar();layout_menu()
end
Host:bindShortcuts()
gfx.getchar=function(query)
 if query then return Host.focused and 6 or 4 end
 local key=Host.key or 0
 if key>=97 and key<=122 then
  if (gfx.mouse_cap&(Host.mac and 36 or 4))~=0 then key=key-96 elseif (gfx.mouse_cap&8)~=0 then key=key-32 end
 end
 return key
end
BLTShortcuts.install(reaper,gfx,{blocked=function() return U.editor.edit~=nil or shell.popupOpen or UI.layoutOpen or A.job~=nil or A.windowTransition~=nil end,
 beforeGlobal=commit_edit,localKey=function(k,cap) return k==27 or k==13 or (cap&16)==0 and (k==26 or (cap&(Host.mac and 36 or 4))~=0 and (k==90 or k==122)) end})
local _,_,sectionID,commandID=R.get_action_context()
local function close()
 if A.closed then return end;A.closed=true
 BLT.cleanup(commit_edit)
 if Core.offline.active then BLT.cleanup(Core.offline.close,R,Core.offline.active) end
 BLT.cleanup(Live.stop);BLT.cleanup(cancel_job,false);BLT.cleanup(retry_temp_deletes,true);BLT.cleanup(Live.restore_fx_preference)
 BLT.cleanup(tcp_dispose);BLT.cleanup(dispose_bitmap)
 if A.font then BLT.cleanup(R.JS_LICE_DestroyFont,A.font);A.font=nil end
 if A.gdiFont then BLT.cleanup(R.JS_GDI_DeleteObject,A.gdiFont);A.gdiFont=nil end
 BLT.cleanup(Host.close,Host);BLT.cleanup(shell.close,shell)
 if Platform.mac then BLT.cleanup(Platform.finish) end
 if commandID and commandID>0 then R.SetToggleCommandState(sectionID,commandID,0);R.RefreshToolbar2(sectionID,commandID) end
end
R.atexit(close)
local inputState,worldState={},{}
local function changed(state,...)
 local changed=false
 for i=1,select('#',...) do local v=select(i,...);if state[i]~=v then state[i]=v;changed=true end end
 return changed
end
local function loop()
 if A.closed then return end
 local begun=false
 local success,err=xpcall(function()
  local now=R.time_precise()
  if Platform.mac then Platform.advance() end
  Media.tick();retry_temp_deletes(false);Live.restore_fx_preference()
  if R.EnumProjects(-1,'')~=A.project then commit_edit(true);release();cancel_job(false);adopt_project(false);wake_visuals() end
  if A.data and not Live.enabled and R.GetProjectStateChangeCount(A.project)~=A.baseline then A.stale=true end
  step_job();Live.tick(now);step_window_transition(now);overlay(now)
  local tcpOK,tcpError=pcall(tcp_button,now)
  if not tcpOK then tcp_dispose();TCP.supported=false;BLT.logError(tcpError) end
  shell.theme.tick(now)
  if BLT.noticeUntil and now>=BLT.noticeUntil then BLT.notice,BLT.noticeUntil=nil,nil;wake_visuals() end
  if now>=(UI.meterAt or 0) then
   UI.meterAt=now+.067
   local pos=A.data and not A.collapsed and ((R.GetPlayStateEx(A.project)&1)~=0 and R.GetPlayPositionEx(A.project) or R.GetCursorPositionEx(A.project)) or 0
   if changed(worldState,A.data,A.revision,A.stale,A.hover,Live.enabled,Live.latest,Live.phase,Live.notice,pos,Media.waiting,Language.code,Presets.current,shell.icon.dirty) then wake_visuals() end
  end
  local interactive=U.editor.edit or shell.popupOpen or UI.layoutOpen or Host.drag or shell.hoverID or U.capture or A.fieldDrag
  local animating=U:executeAnimating('measure') or shell.icon:animating(now) or now<(A.flashUntil or 0)
  if not A.job and not A.windowTransition and now>=awakeUntil and not interactive and not animating and Host:idle(now) then
   U.now=now;shell.icon.lastTime=now;R.defer(loop);return
  end
  if Host.idleWake then wake_visuals();Host.idleWake=nil end
  if Host.requestReset then
   if A.collapsed then A.normalWindow.w,A.normalWindow.h=W,H+26;Host.requestReset=nil
   else Host.width,Host.height=W,H+26 end
  end
  local visible=Host:begin();begun=true
  if visible then
   A.active=Host.focused
   if changed(inputState,gfx.mouse_x,gfx.mouse_y,gfx.mouse_cap,Host.key,gfx.w,gfx.h,Host.dpi,Host.originX,Host.originY,Host.focused) or gfx.mouse_wheel~=0 or (gfx.mouse_cap&1)~=0 or interactive then wake_visuals() end
   if not Host.focused and A.fieldDrag then release() end
   draw();Host.pointerCapture=A.fieldDrag
   if not Host.focused then awakeUntil=min(awakeUntil,now+.5) end
  end
  local keep=Host:finish();begun=false
  if A.requestFold then A.requestFold=nil;fold_window() end
  if not keep or A.requestClose then close() else R.defer(loop) end
 end,debug.traceback)
 if not success then
  if begun then pcall(Host.finish,Host) end
  close();Language.mb(public_error(err),'LOUDNESS TRACE | エラー',0)
 end
end
local initialized,why=xpcall(function()
 Live.prepare_install()
 A.gdiFont=R.JS_GDI_CreateFont(14,400,0,false,false,false,Platform.graphFont);A.font=R.JS_LICE_CreateFont()
 if not A.gdiFont or not A.font then error('グラフ用フォントを作成できません。') end
 R.JS_LICE_SetFontFromGDI(A.font,A.gdiFont,'');R.JS_LICE_SetFontBkColor(A.font,0)
 adopt_project(true)
 if commandID and commandID>0 then R.SetToggleCommandState(sectionID,commandID,1);R.RefreshToolbar2(sectionID,commandID) end
end,debug.traceback)
if initialized then loop() else close();Language.mb(public_error(why),'LOUDNESS TRACE | エラー',0) end
