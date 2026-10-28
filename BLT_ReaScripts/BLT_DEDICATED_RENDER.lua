-- @description BLT DEDICATED RENDER
-- @version 0.14.15
-- @author Balrulu
-- @provides
--   . > ../
-- @changelog
--   BLT SERIES Beta TEST UPLOAD
-- @about
--   BLT SERIES Beta TEST UPLOAD

local AppCanvasHost=(function()
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
 local function xy(x,y) return H.originX+x,H.originY+y end
 function G.set(r,g,b,a)
  a=a or 1
  if r~=lastR or g~=lastG or b~=lastB or a~=lastA then
   color=packed(r,g,b,a);lastR,lastG,lastB,lastA=r,g,b,a
  end
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
  if self.beforeBegin then self.beforeBegin() end
  I.PushStyleVar(ctx,I.StyleVar_WindowPadding,0,0)
  I.PushStyleVar(ctx,I.StyleVar_WindowRounding,0);I.PushStyleVar(ctx,I.StyleVar_WindowBorderSize,0)
  I.PushStyleColor(ctx,I.Col_WindowBg,0x05080eff)
  local focusFlag=self.seenWindow and I.WindowFlags_NoFocusOnAppearing or 0
  local shown,open=I.Begin(ctx,self.title,true,I.WindowFlags_NoScrollbar|I.WindowFlags_NoScrollWithMouse|I.WindowFlags_NoTitleBar|I.WindowFlags_NoMove|I.WindowFlags_NoResize|focusFlag)
  I.PopStyleColor(ctx);I.PopStyleVar(ctx,3)
  if gradientFrame%60==1 then self:retainResources() end
  self.shown=shown;self.open=open
  if self.onWindow then self.onWindow() end
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
  self.focused=I.IsWindowFocused(ctx)
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
local AppShellText=(function()
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
local AppChromeRaster=(function()
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
local AppCanvasDraw=(function()
local M={}
local floor,ceil,min,max=math.floor,math.ceil,math.min,math.max
function M.new(H,G,api,native,ShellText,ChromeRaster,beginFrame,changed)
 local I,ctx,g=H.I,H.ctx,H.g
 local text=ShellText.new(H,api,native)
 local chrome=ChromeRaster.new(H,api,text)
 local D={}
 local front,back,partial={n=0},{n=0},{n=0}
 local backChrome,partialChrome=false,false
 local wheelFront,wheelBack,fullDraw={n=0},{n=0},false
 local target=back
 local fonts,families,images,gradients,slots={},{},{},{},{}
 local selected,route,gradientKey,serial=nil,false,nil,0
 local color=0xffffffff
 local lastR,lastG,lastB,lastA
 local gradientR,gradientG,gradientB,gradientRGB
 local function byte(a)return floor(max(0,min(1,a))*255+.5)end
 local function command(paint)
  local n=target.n+1;target.n=n
  local c=target[n]
  if not c then c={};target[n]=c end
  c.paint,c.color=paint,color
  return c
 end
 local function rect(c)
  if c.color&255==0 or c.w<=0 or c.h<=0 then return end
  local x,y=H.originX+c.x,H.originY+c.y
  if c.fill then I.DrawList_AddRectFilled(H.draw,x,y,x+c.w,y+c.h,c.color)
  else I.DrawList_AddRect(H.draw,x+.5,y+.5,x+c.w-.5,y+c.h-.5,c.color)end
 end
 local function line(c)
  if c.color&255==0 then return end
  I.DrawList_AddLine(H.draw,H.originX+c.x+.5,H.originY+c.y+.5,H.originX+c.xx+.5,H.originY+c.yy+.5,c.color,c.width)
 end
 local function circle(c)
  if c.color&255==0 then return end
  if c.fill then I.DrawList_AddCircleFilled(H.draw,H.originX+c.x,H.originY+c.y,c.radius,c.color)
  else I.DrawList_AddCircle(H.draw,H.originX+c.x,H.originY+c.y,c.radius,c.color)end
 end
 local function roundrect(c)
  I.DrawList_AddRect(H.draw,H.originX+c.x,H.originY+c.y,H.originX+c.x+c.w,H.originY+c.y+c.h,c.color,c.radius)
 end
 local function gradrect(c)g.gradcolors(c.x,c.y,c.w,c.h,c.left,c.right)end
 local function gradrect2(c)
  I.DrawList_AddRectFilledMultiColor(H.draw,H.originX+c.x,H.originY+c.y,H.originX+c.x+c.w,H.originY+c.y+c.h,c.left,c.right,c.br,c.bl)
 end
 local function bars(c)
  g.set(c.r,c.g,c.b,c.a);g.bars(c.x,c.y,c.spacing,c.width,c.heights,c.scale)
 end
 local function polygon(c)
  if c.originX~=H.originX or c.originY~=H.originY or c.dirty then
   local coords=c.coords or {};c.coords=coords
   for i,p in ipairs(c.points)do coords[i*2-1],coords[i*2]=H.originX+p[1],H.originY+p[2]end
   for i=#coords,#c.points*2+1,-1 do coords[i]=nil end
   c.array=api.new_array(coords);c.originX,c.originY,c.dirty=H.originX,H.originY,false
  end
  if c.concave then I.DrawList_AddConcavePolyFilled(H.draw,c.array,c.color)
  else I.DrawList_AddConvexPolyFilled(H.draw,c.array,c.color)end
 end
 local function bodyText(c)
  local x,y=c.x,c.y
  local left,top=H.originX+x,H.originY+y;local right,bottom=H.originX+c.right,H.originY+c.bottom
  if c.flags&2~=0 then x=c.right-c.w elseif c.flags&1~=0 then x=x+(c.right-x-c.w)*.5 end
  if c.flags&4~=0 then y=y+(c.bottom-y-c.h)*.5 end
  x,y=H.originX+x,H.originY+y
  if c.optical then local dpi=H.dpi or 1;y=floor((y+c.offset)*dpi+.5)/dpi else y=floor(y)end
  I.DrawList_AddTextEx(H.draw,c.font,c.size,floor(x),y,c.color,c.text,0,floor(left),floor(top),ceil(right),ceil(bottom))
 end
 local function shellText(c)
  text:setfont(1,c.face,c.size,c.bold)
  local x,y=c.x,c.y;local right,bottom=c.right,c.bottom
  local clip=right and bottom and(c.flags&256)==0
  if clip then I.DrawList_PushClipRect(H.draw,H.originX+x,H.originY+y,H.originX+right,H.originY+bottom,true)end
  if right then if c.flags&2~=0 then x=right-c.w elseif c.flags&1~=0 then x=x+(right-x-c.w)*.5 end end
  if bottom then if c.flags&8~=0 then y=bottom-c.h elseif c.flags&4~=0 then y=y+(bottom-y-c.h)*.5 end end
  text:draw(c.text,x,y,c.r,c.g,c.b,c.a)
  if clip then I.DrawList_PopClipRect(H.draw)end
 end
 local function pushClip(c)
  I.DrawList_PushClipRect(H.draw,H.originX+c.x,H.originY+c.y,H.originX+c.x+c.w,H.originY+c.y+c.h,true)
 end
 local function popClip()I.DrawList_PopClipRect(H.draw)end
 local function image(c)
  local img=images[c.slot]
  if not img or c.sw<=0 or c.sh<=0 then return end
  local x,y=H.originX+c.x,H.originY+c.y
  I.DrawList_PushClipRect(H.draw,x,y,x+c.w,y+c.h,true)
  I.DrawList_AddImage(H.draw,img.image,x,y,x+c.w,y+c.h,c.sx/img.w,c.sy/img.h,(c.sx+c.sw)/img.w,(c.sy+c.sh)/img.h,H.rgba(1,1,1,c.a))
  I.DrawList_PopClipRect(H.draw)
 end
 local function replay(list)
  for i=1,list.n do local c=list[i];c.paint(c)end
 end
 local function gradient(c)
  local e=c.entry
  if not g.beginGradient(e.kind,e.x,e.y,e.w,e.h,1,table.unpack(e.signature,1,e.n))then replay(e.commands);g.endGradient()end
 end
 local chromeState={}
 local function paintChrome(c)
  local p=c.painter;local b=p.b
  local state={b.inline or false,b.compact or false,b.titleEnd or 0,p.collapsed or false,p.docked or false,p.dockButton or false,p.compactLanguage or false,p.chrome.titleText or ''}
  for j,value in ipairs(state)do if chromeState[j]~=value then chromeState[j]=value;chrome.signature={}end end
  local output=chrome:begin(p);if chrome.dirty then c.draw(output,p)end
  if b.inline then
   I.DrawList_PushClipRect(H.draw,H.originX,H.originY,H.originX+b.titleEnd,H.originY+p.chrome.titleH,true);chrome:finish();I.DrawList_PopClipRect(H.draw)
   chrome.dirty=false
   I.DrawList_PushClipRect(H.draw,H.originX+b.presetX,H.originY,H.originX+G.w,H.originY+p.chrome.titleH,true);chrome:finish();I.DrawList_PopClipRect(H.draw)
  else chrome:finish()end
 end
 function G.set(r,green,b,a)
  green,b,a=green or r,b or r,a or 1
  G.r,G.g,G.b,G.a=r,green,b,a
  if r~=lastR or green~=lastG or b~=lastB or a~=lastA then
   color=g.packedColor(r,green,b,a);lastR,lastG,lastB,lastA=r,green,b,a
  end
 end
 function G.rect(x,y,w,h,filled)
  local c=command(rect);c.x,c.y,c.w,c.h,c.fill=x,y,w,h,filled~=0
 end
 function G.line(x,y,xx,yy,aa,width)
  local c=command(line);c.x,c.y,c.xx,c.yy,c.width=x,y,xx,yy,width or 1
 end
 function G.circle(x,y,r,filled)
  local c=command(circle);c.x,c.y,c.radius,c.fill=x,y,r,filled~=0
 end
 function G.roundrect(x,y,w,h,r)
  local c=command(roundrect);c.x,c.y,c.w,c.h,c.radius=x,y,w,h,r
 end
 function G.gradrect(x,y,w,h,r,green,b,a,rx,gx,bx,ax,ry,gy,by,ay)
  rx,gx,bx,ax=rx or 0,gx or 0,bx or 0,ax or 0
  local c=command(ry and(ry~=0 or gy~=0 or by~=0 or ay~=0)and gradrect2 or gradrect)
  c.x,c.y,c.w,c.h=x,y,w,h
  if c.paint==gradrect and rx==0 and gx==0 and bx==0 then
   if r~=gradientR or green~=gradientG or b~=gradientB then
    gradientRGB=H.rgba(r,green,b,0);gradientR,gradientG,gradientB=r,green,b
   end
   c.left,c.right=gradientRGB|byte(a),gradientRGB|byte(a+ax*w)
  else c.left,c.right=H.rgba(r,green,b,a),H.rgba(r+rx*w,green+gx*w,b+bx*w,a+ax*w)end
  if c.paint==gradrect2 then
   c.br=H.rgba(r+rx*w+ry*h,green+gx*w+gy*h,b+bx*w+by*h,a+ax*w+ay*h)
   c.bl=H.rgba(r+ry*h,green+gy*h,b+by*h,a+ay*h)
  end
 end
 function G.bars(x,y,spacing,width,heights,scale)
  local c=command(bars);c.x,c.y,c.spacing,c.width,c.scale=x,y,spacing,width,scale
  c.r,c.g,c.b,c.a=G.r,G.g,G.b,G.a;c.heights=c.heights or {}
  for i,h in ipairs(heights)do c.heights[i]=h end
  for i=#c.heights,#heights+1,-1 do c.heights[i]=nil end
 end
 function G.polygon(points,concave)
  local c=command(polygon);c.points=c.points or {};c.concave=concave
  if #c.points~=#points then c.dirty=true end
  for i,p in ipairs(points)do
   local q=c.points[i]or {};if q[1]~=p[1]or q[2]~=p[2]then c.dirty=true end
   q[1],q[2]=p[1],p[2];c.points[i]=q
  end
  for i=#c.points,#points+1,-1 do c.points[i]=nil end
 end
 function G.triangle(x,y,xx,yy,xxx,yyy)
  assert(x and y and xx and yy and xxx and yyy,'Canvas polygon requires x,y pairs')
  local c=command(polygon);local points=c.points or {{},{},{}};c.points=points
  for i=1,3 do points[i]=points[i]or {}end
  if #points~=3 or points[1][1]~=x or points[1][2]~=y or points[2][1]~=xx or points[2][2]~=yy or points[3][1]~=xxx or points[3][2]~=yyy then c.dirty=true end
  points[1][1],points[1][2]=x,y;points[2][1],points[2][2]=xx,yy;points[3][1],points[3][2]=xxx,yyy
  for i=#points,4,-1 do points[i]=nil end;c.concave=false
 end
 function G.textRoute(value)if value~=nil then route=value end;return route end
 local function font()
  if route then text:setfont(1,selected[1],selected[2],selected[3])
  else g.setfont(1,selected[1],selected[2],selected[3])end
 end
 function G.setfont(slot,face,size,flags)
  beginFrame()
  local f=fonts[slot]
  if face and(not f or f[1]~=face or f[2]~=(size or 10)or f[3]~=(flags or 0))then f={face,size or 10,flags or 0};fonts[slot]=f end
  selected=f or fonts[1]or {H.faces[1],10,0}
  font()
  local key=route and 'shellHeight' or 'bodyHeight'
  if selected.dpi~=H.dpi then selected.dpi=H.dpi;selected.shellHeight,selected.bodyHeight=nil,nil end
  if not selected[key]then
   if route then selected[key]=select(2,text:measurestr('Hg'))else selected[key]=select(2,g.measurestr('Hg'))end
  end
  G.texth=selected[key];return 1
 end
 function G.selectFont(size,kind,bold,scale,faces)
  local face=faces[kind or 1]or faces[1]
  local px=max(8,floor((size or 10)*scale+.5));local weight=bold and 98 or 0
  local family=families[face];if not family then family={};families[face]=family end
  local style=px*2+(bold and 1 or 0);local f=family[style]
  if not f then f={face,px,weight,body={},shell={}};family[style]=f end
  G.setfont(f,face,px,weight)
  return route and f.shell or f.body
 end
 function G.measurestr(value)
  beginFrame();font();if route then return text:measurestr(tostring(value))end;return g.measurestr(tostring(value))
 end
 function G.drawstr(value,flags,right,bottom,optical)
  value=tostring(value);font()
  local c=command(route and shellText or bodyText)
  c.text,c.x,c.y,c.flags,c.optical=value,G.x,G.y,flags or 0,optical
  if route then
   c.face,c.size,c.bold=selected[1],selected[2],selected[3]
   c.w,c.h=text:measurestr(value);c.right,c.bottom=right,bottom
   c.r,c.g,c.b,c.a=G.r,G.g,G.b,G.a
  else
   c.w,c.h,c.size,c.font=g.textMetrics(value)
   c.offset=type(optical)=='number'and optical or optical and H:numberOffset(c.size)or 0
   c.right,c.bottom=right or G.w,bottom or G.h
  end
  G.x=G.x+c.w
 end
 function G.pushClip(x,y,w,h)local c=command(pushClip);c.x,c.y,c.w,c.h=x,y,w,h end
 function G.popClip()command(popClip)end
 function G.wheelRegion(x,y,w,h)
  local n=wheelBack.n+1;wheelBack.n=n
  local r=wheelBack[n]or {};wheelBack[n]=r;r.x,r.y,r.w,r.h=x,y,w,h
 end
 function G.loadimg(slot,path)
  local ok,img=pcall(I.CreateImage,path);if not ok or not img then return -1 end
  local previous=images[slot];if previous then H:releaseImage(previous.image)end
  local w,h=I.Image_GetSize(img);H:attachImage(img);images[slot]={image=img,w=w,h=h};return slot
 end
 function G.getimgdim(slot)local img=images[slot];return img and img.w or 0,img and img.h or 0 end
 function G.blit(slot,scale,rotation,sx,sy,sw,sh,x,y,w,h)
  local img=images[slot];if not img then return end
  assert(not rotation or rotation==0,'Image rotation is not supported')
  local c=command(image)
  c.slot,c.sx,c.sy,c.sw,c.sh=slot,sx or 0,sy or 0,sw or img.w,sh or img.h
  c.x,c.y,c.w,c.h,c.a=x or G.x,y or G.y,w or c.sw*(scale or 1),h or c.sh*(scale or 1),G.a
 end
 function G.beginGradient(kind,x,y,w,h,...)
  assert(not gradientKey,'Nested canvas gradient')
  local key=kind..':'..x..':'..y..':'..w..':'..h
  local e=gradients[key];local n=select('#',...);local same=e and e.n==n
  if same then for i=1,n do if e.signature[i]~=select(i,...)then same=false;break end end end
  if not same then
   if not e then serial=serial%96+1;local old=slots[serial];if old then gradients[old]=nil end;slots[serial]=key end
   e={kind=kind,x=x,y=y,w=w,h=h,n=n,signature={...},commands={n=0}};gradients[key]=e
  end
  local c=command(gradient);c.entry=e
  if same then return true end
  gradientKey=key;target=e.commands;return false
 end
 function G.endGradient()assert(gradientKey,'No canvas gradient');target=back;gradientKey=nil end
 function G.paintChrome(draw,painter)
  backChrome=true
  local c=command(paintChrome);local p=c.painter or {};c.painter=p;c.draw=draw;p.hot=painter.hot
  for key,value in pairs(painter)do if type(value)~='function'then p[key]=value end end
  if p.barFont then return end
  p.barFont=function()text:setfont(1,H.faces[2],10,0)end
  p.languageFont=function()text:setfont(1,H.faces[2],13,98)end
  p.metrics=function(s)return text:measurestr(s)end
  p.fit=function(s,w)
   if text:measurestr(s)<=w then return s end
   local n=utf8.len(s)or 0
   while n>0 do local stop=utf8.offset(s,n);local t=s:sub(1,stop-1)..'…';if text:measurestr(t)<=w then return t end;n=n-1 end
   return ''
  end
 end
 function D:commit()
  local complete=fullDraw
  if fullDraw then wheelFront,wheelBack=wheelBack,wheelFront;fullDraw=false end
  wheelBack.n=0
  if back.n==0 then return end
  if complete then front,back=back,front;partial.n=0;partialChrome=false
  else partial,back=back,partial;partialChrome=backChrome end
  back.n,backChrome=0,false;target=back;changed()
 end
 function D:draw()
  for i=1,wheelFront.n do local r=wheelFront[i];g.wheelRegion(r.x,r.y,r.w,r.h)end
  if partialChrome then
   for i=1,front.n do local c=front[i];if c.paint~=paintChrome then c.paint(c)end end
  else replay(front)end
  replay(partial)
 end
 function G.update()D:commit()end
 function G.abort()
  if gradientKey then gradients[gradientKey]=nil end
  gradientKey,route,fullDraw,backChrome=nil,false,false,false;back.n=0;wheelBack.n=0;target=back
 end
 function G.beginDraw()beginFrame();G.abort();fullDraw=true end
 G.release=G.abort
 function D:close()
  for _,img in pairs(images)do H:releaseImage(img.image)end
  chrome:close();text:close();front,back,partial,fonts,families,images,gradients,slots={n=0},{n=0},{n=0},{},{},{},{},{}
 end
 return D
end
return M
end)()
local AppCanvas=(function()
local M={}
local cursorNames={we='ResizeEW',ns='ResizeNS',nwse='ResizeNWSE',nesw='ResizeNESW'}
function M.install(api,native,CanvasHost,options,ShellText,ChromeRaster,CanvasDraw)
 local P=setmetatable({},{__index=api})
 local G={x=0,y=0,w=options.width,h=options.height,a=1,r=1,g=1,b=1,
  mouse_x=-10000,mouse_y=-10000,mouse_cap=0,mouse_wheel=0,ext_retina=1}
 local H,I,ctx,frame,insideCallback,closed
 local keys={}
 local dockID,requestedDock,rectRequest=0,nil,nil
 local redraw=true
 local dockWait,dockSettle=0,0
 local beginFrame,special,display,overlay
 local function ensure()
  assert(api.ImGui_GetBuiltinPath,'ReaImGui 0.10以降が必要です。')
  if H then return end
  H=CanvasHost.new(api,options.title,options.width,options.height,options.section);I,ctx=H.I,H.ctx
  display=CanvasDraw.new(H,G,api,native,ShellText,ChromeRaster,function()beginFrame()end,function()redraw=true end)
  I.SetConfigVar(ctx,I.ConfigVar_Flags,I.GetConfigVar(ctx,I.ConfigVar_Flags)|I.ConfigFlags_DockingEnable)
  H.minWidth,H.minHeight,H.persistSize=options.minWidth,options.minHeight,true
  for _,face in ipairs(H.faces)do H:fontFor(face,false);H:fontFor(face,true)end
  H.captureRight,H.pointerCapture=true,true
  special={{'Escape',27},{'Enter',13},{'KeypadEnter',13},{'Tab',9},{'Backspace',8},{'Delete',6579564},{'LeftArrow',1818584692},{'RightArrow',1919379572},{'UpArrow',30064},{'DownArrow',1685026670},{'Home',1752132965},{'End',6647396},{'PageUp',1885828464},{'PageDown',1885824110}}
  for i=1,12 do local code=0;for ch in ('f'..i):gmatch('.')do code=(code<<8)|ch:byte()end;special[#special+1]={'F'..i,code}end
  H.onWindow=function()
   if H.shown then
    local current=I.GetWindowDockID(ctx)
    if current~=dockID then H.nativeWindow,H.probedWindow=nil,nil;H.nativeProbe=true;H.imageHold=true;dockSettle=4 end
    dockID=current;H.section=dockID==0 and options.section or nil
   end
  end
  H.beforeBegin=function()
   if requestedDock~=nil then
    if dockWait>0 then dockWait=dockWait-1
    else
     I.SetNextWindowDockID(ctx,requestedDock);dockID=requestedDock;requestedDock=nil;dockSettle=4
     H.section=dockID==0 and options.section or nil
     H.nativeWindow,H.probedWindow=nil,nil;H.nativeProbe=true
    end
   end
   if rectRequest then
    local r=rectRequest;I.SetNextWindowPos(ctx,r[1],r[2]);I.SetNextWindowSize(ctx,r[3],r[4]);rectRequest=nil
   end
  end
 end
 function G.setfont(...)ensure();return G.setfont(...)end
 function G.measurestr(...)ensure();return G.measurestr(...)end
 local function input()
  if not H.focused then keys={};return end
  local ctrl,alt=(G.mouse_cap&4)~=0 or H.mac and(G.mouse_cap&32)~=0,(G.mouse_cap&16)~=0
  local idx=0
  while true do local ok,cp=I.GetInputQueueCharacter(ctx,idx);if not ok then break end
   local modified=(ctrl or alt)and(cp>=65 and cp<=90 or cp>=97 and cp<=122)
   if cp>=32 and not modified then keys[#keys+1]=cp<256 and cp or (117<<24)|cp end;idx=idx+1
  end
  for _,p in ipairs(special)do if I.IsKeyPressed(ctx,I['Key_'..p[1]],true)then keys[#keys+1]=p[2]end end
  if ctrl or alt then for cp=65,90 do if I.IsKeyPressed(ctx,I['Key_'..string.char(cp)],true)then keys[#keys+1]=ctrl and(alt and cp+192 or cp-64)or cp+256 end end end
 end
 beginFrame=function()
  if frame or closed or not H then return end
  local nextDock=dockWait==0 and requestedDock or dockID
  H.imageHold=requestedDock~=nil or dockSettle>0 or not H.shown
  H.minWidth,H.minHeight=nextDock~=0 and 1 or options.minWidth,nextDock~=0 and 1 or options.minHeight
  H:begin();frame=true
  if not H.shown then H.imageHold=true end
  if H.shown then
   for _,key in ipairs({'w','h','mouse_x','mouse_y','mouse_cap','mouse_wheel','ext_retina'})do G[key]=H.g[key]end
   input()
  else
   H.focused,H.hovered=false,false;G.mouse_x,G.mouse_y,G.mouse_cap,G.mouse_wheel=-10000,-10000,0,0;keys={}
  end
 end
 function G.inputContext(face)
  ensure();return I,ctx,H:fontFor(face,false),H.originX or 0,H.originY or 0
 end
 function G.setOverlay(fn)overlay=fn end
 local function finishFrame()
  if not frame then return end
  display:commit()
  local previousCallback=insideCallback;insideCallback=true
  local ok,err=pcall(function()
   if H.shown and not closed then
    display:draw()
    if overlay then overlay()end
   end
  end)
  insideCallback=previousCallback
  frame=false;local open=H:finish()
  if requestedDock==nil and H.shown and dockSettle>0 then dockSettle=dockSettle-1 end
  if requestedDock==nil and H.shown and dockSettle==0 then H.imageHold=nil end
  redraw=requestedDock~=nil or rectRequest~=nil or dockSettle>0
  if not open then H.requestClose=true end
  if not ok then error(err,0)end
 end
 function P.defer(fn)
  if frame and not insideCallback then finishFrame()end
  return api.defer(function()
   if closed then return end
   local idle=H and H.shown and not redraw and H:idle(api.time_precise())
   if not idle then beginFrame()end
   insideCallback=true
   local ok,err=xpcall(fn,debug.traceback);insideCallback=false
   if redraw and not frame then beginFrame()end
   finishFrame()
   if not ok then error(err,0)end
  end)
 end
 function G.init(title,w,h,state,x,y)
  options.title,options.width,options.height=title,w,h;G.w,G.h=w,h;ensure()
  H.width,H.height=w,h
  if x and y then H.restoreX,H.restoreY=x,y end
  requestedDock=state and (state&1)~=0 and -1-((state>>8)&15)or 0
  beginFrame();return 1
 end
 function G.getchar(mask)
  if mask==65536 or mask==65537 then return 1|(H and H.focused and 2 or 0)|(H and H.shown and 4 or 0)|(mask==65536 and H and H.hovered and 8 or 0)end
  if closed or H and H.requestClose then return -1 end
  return table.remove(keys,1)or 0
 end
 function G.setCursor(kind)
  if not frame then return end
  I.SetMouseCursor(ctx,I['MouseCursor_'..(cursorNames[kind]or'Arrow')])
 end
 function G.dock(state)
  ensure()
  if state and state>=0 then
   local target=(state&1)~=0 and -1-((state>>8)&15)or 0
   if target~=dockID then requestedDock=target;dockWait=4;H.imageHold=true;redraw=true end
  end
  local value=dockID~=0 and (1|((dockID<0 and -dockID-1 or 0)<<8))or 0
  return value,H.nativeX or H.restoreX or 100,H.nativeY or H.restoreY or 100,G.w,G.h
 end
 function G.windowHandle()
  local hwnd=H and (api.JS_Window_Find and api.JS_Window_Find(options.title,true)or H.nativeWindow)or nil
  return hwnd~=0 and hwnd or nil
 end
 function G.setWindowRect(x,y,w,h)
  if dockID~=0 then return false end
  if api.JS_Mouse_GetState and(api.JS_Mouse_GetState(1)&1)~=0 then H.windowGesture=true end
  rectRequest={x,y,w,h};redraw=true;return true
 end
 function G.geometryAPI()
  local V={}
  V.GetMousePosition=function()ensure();if not frame then beginFrame()end;return I.PointConvertNative(ctx,api.GetMousePosition())end
  V.JS_Window_GetRect=function(hwnd)
   if not hwnd or hwnd==0 then return false,0,0,0,0 end
   if hwnd and hwnd==G.windowHandle()then return true,H.windowX or 0,H.windowY or 0,(H.windowX or 0)+G.w,(H.windowY or 0)+G.h end
   return false,0,0,0,0
  end
  V.JS_Window_SetPosition=function(hwnd,x,y,w,h,...)
   if not hwnd or hwnd==0 then return false end
   if hwnd and hwnd==G.windowHandle()then return G.setWindowRect(x,y,w,h)end
   return false
  end
  return V
 end
 function G.clienttoscreen(x,y)ensure();if not frame then beginFrame()end;return I.PointConvertNative(ctx,(H.originX or 0)+x,(H.originY or 0)+y,true)end
 function G.showmenu(menu)
  local x,y=G.clienttoscreen(G.x,G.y);native.x,native.y=x,y
  return native.showmenu(menu)
 end
 function G.quit()
  if closed then return end;closed=true;overlay=nil
  if frame then frame=false;H:finish()end
  if H then
   H.imageHold=nil;H:releaseRetiredImages()
   display:close();keys={};H:close()
  end
 end
 return P,G
end
return M
end)()
if type(reaper.ImGui_GetBuiltinPath)~='function'then reaper.MB('ReaImGui 0.10以降が必要です。ReaPackから導入・更新してください。','BLT | エラー',0);return end
local ItemLabelNative=reaper
local reaper,gfx=AppCanvas.install(reaper,gfx,AppCanvasHost,
 {section='BLT_DEDICATED_RENDER',title='BLT DEDICATED RENDER',width=648,height=720,minWidth=648,minHeight=681},AppShellText,AppChromeRaster,AppCanvasDraw)
do

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

  P.BLT_WithNativeDialog=call
  return P
 end
 return M
end)()

reaper=BLTNativeDialogs.install(reaper,gfx)
end

local AudioOutput=(function()
local AudioOutput={}
local function check(ok,message)if not ok then error(message,0)end;return ok end
local function readn(f,n)local s=f:read(n);return check(s and #s==n and s,'WAVが途中で切れています。')end
local function inspect_wav(path)
 local f=check(io.open(path,'rb'),'出力ファイルがありません：'..path)
 local ok,result=pcall(function()
  local size=f:seek('end');f:seek('set',0);local h=readn(f,12)
  local kind=h:sub(1,4);check((kind=='RIFF' or kind=='RF64') and h:sub(9,12)=='WAVE','未対応のWAVコンテナー（RIFF/RF64のみ）：'..path)
  if kind=='RIFF'then check(string.unpack('<I4',h,5)+8==size,'未完了または不正なWAVサイズ：'..path)end
  local pos=12;local w={};local data64
  while pos<size do
   f:seek('set',pos);local c=readn(f,8);local id,n=c:sub(1,4),string.unpack('<I4',c,5)
   if n==0xffffffff then check(id=='data' and data64,'RF64サイズ表が未対応です。');n=data64 end
   check(n>=0 and pos+8+n+n%2<=size,'WAVチャンク長が不正です。')
   if id=='ds64' then
    check(n>=28 and not data64,'RF64 ds64が不正です。');local d=readn(f,28)
    local riff,frames,entries;riff,data64,frames,entries=string.unpack('<I8I8I8I4',d)
    check(riff+8==size and entries==0,'RF64サイズが不正、または未対応です。')
   elseif id=='fmt 'then
    check(n>=16 and n<=4096 and not w.channels,'WAV fmtが不正です。');local fmt=readn(f,n)
    local tag,channels,sr,rate,align,bits=string.unpack('<I2I2I4I4I2I2',fmt)
    if tag==65534 then check(n>=40,'拡張WAV fmtが不正です。');tag=string.unpack('<I4',fmt,25)end
    check((tag==1 or tag==3) and (channels>=1 and channels<=128) and sr>0 and align==channels*bits//8 and rate==sr*align,'対応するPCM/float WAVではありません。')
    w.channels,w.sr,w.align=channels,sr,align
   elseif id=='data'then check(not w.bytes,'複数dataチャンクは未対応です。');w.bytes=n end
   pos=pos+8+n+n%2
  end
  check(w.align and w.align>0 and w.bytes and w.bytes>0 and w.bytes%w.align==0,'WAVの音声データが不正です。')
  if kind=='RF64' then check(data64,'RF64 ds64がありません。')end
  w.frames=w.bytes//w.align;return w
 end)
 f:close();if not ok then error(result,0)end;return result
end

function AudioOutput.inspect(path,api)
 if path:lower():match('%.wav$')then
  local f=check(io.open(path,'rb'),'出力ファイルがありません：'..path)
  local magic=f:read(16);f:close()

  if magic~='riff\x2e\x91\xcf\x11\xa5\xd6\x28\xdb\x04\xc1\x00\x00'then return inspect_wav(path)end
 end
 check(api and api.PCM_Source_CreateFromFile,'出力形式の確認APIを使用できません。')
 local src=check(api.PCM_Source_CreateFromFile(path),'出力ファイルを読み込めません：'..path)
 local ok,w=pcall(function()
  local ch=api.GetMediaSourceNumChannels(src);local len=api.GetMediaSourceLength(src)
  check(ch>0 and len>0,'音声データを確認できません：'..path);return {channels=ch}
 end)
 api.PCM_Source_Destroy(src);if not ok then error(w,0)end;return w
end

return AudioOutput
end)()

local Scope={}
local function need(ok,msg)if not ok then error(msg,0)end;return ok end
function Scope.regions(api,p,positions)
 local out={}
 for i=0,api.GetNumRegionsOrMarkers(p)-1 do
  local ptr=api.GetRegionOrMarker(p,i,'')
  local row={ptr=ptr,id=api.GetRegionOrMarkerInfo_Value(p,ptr,'I_NUMBER'),isr=api.GetRegionOrMarkerInfo_Value(p,ptr,'B_ISREGION')~=0,selected=api.GetRegionOrMarkerInfo_Value(p,ptr,'B_UISEL')}
  if positions~=false then row.start=api.GetRegionOrMarkerInfo_Value(p,ptr,'D_STARTPOS');row.finish=api.GetRegionOrMarkerInfo_Value(p,ptr,'D_ENDPOS')end
  out[#out+1]=row
 end
 return out
end
function Scope.selection(api,p,ptr,value,message)
 if api.GetRegionOrMarkerInfo_Value(p,ptr,'B_UISEL')~=value then
  api.SetRegionOrMarkerInfo_Value(p,ptr,'B_UISEL',value)
  need(api.GetRegionOrMarkerInfo_Value(p,ptr,'B_UISEL')==value,message)
 end
end
function Scope.selectregion(api,p,rows,id)
 for _,v in ipairs(rows)do
  local wanted=v.isr and v.id==id and 1 or 0
  Scope.selection(api,p,v.ptr,wanted,'確認用のリージョン選択を設定できません。')
 end
end
function Scope.razors(api,p)
 local all={}
 for i=0,api.CountTracks(p)-1 do
  local track=api.GetTrack(p,i);local ok,raw=api.GetSetMediaTrackInfo_String(track,'P_RAZOREDITS_EXT','',false)
  need(ok,'レイザー領域を取得できません。')
  local v={track=track,raw=raw,areas={}}
  for entry in raw:gmatch('[^,]+')do
   local a,b,rest=entry:match('^%s*([%+%-%d.eE]+)%s+([%+%-%d.eE]+)%s*(.-)%s*$')
   need(a and tonumber(a)and tonumber(b),'レイザー領域の形式を解釈できません。')
   local guid=rest:match('^"(.-)"')or''
   if guid==''then need(tonumber(b)>tonumber(a),'レイザー領域の長さが不正です。');v.areas[#v.areas+1]={start=tonumber(a),finish=tonumber(b),raw=entry}end
  end
  all[#all+1]=v
 end
 return all
end
function Scope.setrazors(api,all,keep,single)
 for _,v in ipairs(all)do
  local raw=single and(single.track==v.track and single.raw or'')or(keep[v.track]and v.raw or'')
  local ok,now=api.GetSetMediaTrackInfo_String(v.track,'P_RAZOREDITS_EXT','',false);need(ok,'レイザー領域を取得できません。')
  if now~=raw then need(api.GetSetMediaTrackInfo_String(v.track,'P_RAZOREDITS_EXT',raw,true),'レイザー領域を設定できません。')end
 end
end
function Scope.restore(api,p,regions,razors)
 local errors={};local function attempt(fn)local ok,e=pcall(fn);if not ok then errors[#errors+1]=tostring(e)end end
 for _,v in ipairs(regions or{})do attempt(function()
  Scope.selection(api,p,v.ptr,v.selected,'リージョン選択の復元失敗')
 end)end
 for _,v in ipairs(razors or{})do attempt(function()
  need(api.GetSetMediaTrackInfo_String(v.track,'P_RAZOREDITS_EXT',v.raw,true),'レイザー領域の復元失敗')
  local ok,raw=api.GetSetMediaTrackInfo_String(v.track,'P_RAZOREDITS_EXT','',false);need(ok and raw==v.raw,'レイザー領域の復元不一致')
 end)end
 need(#errors==0,table.concat(errors,'\n'))
end

local LoopMetadata=(function()
local R
local min,max,abs,floor=math.min,math.max,math.abs,math.floor
local function clamp(x,a,b)return max(a,min(b,x))end
local function finite(x)return type(x)=='number'and x==x and abs(x)<math.huge end
local Core={MAX_METADATA=16*1024*1024}
Core.tags={sustain='[BLT:SUSTAIN]',region='[BLT:REGION]'}
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

local CP932_TABLE='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UzCxglQwsoJVMLOCVjC0glcwtYJYMLaCWTC3glowuIJbMLmCXDC6gl0wu4JeMLyCXzC9gmAwvoJhML+CYjDAgmMwwYJkMMKCZTDDgmYwxIJnMMWCaDDGgmkwx4JqMMiCazDJgmwwyoJtMMuCbjDMgm8wzYJwMM6CcTDPgnIw0IJzMNGCdDDSgnUw04J2MNSCdzDVgngw1oJ5MNeCejDYgnsw2YJ8MNqCfTDbgn4w3IJ/MN2CgDDegoEw34KCMOCCgzDhgoQw4oKFMOOChjDkgocw5YKIMOaCiTDngoow6IKLMOmCjDDqgo0w64KOMOyCjzDtgpAw7oKRMO+CkjDwgpMw8YKbMEqBnDBLgZ0wVIGeMFWBoTBAg6IwQYOjMEKDpDBDg6UwRIOmMEWDpzBGg6gwR4OpMEiDqjBJg6swSoOsMEuDrTBMg64wTYOvME6DsDBPg7EwUIOyMFGDszBSg7QwU4O1MFSDtjBVg7cwVoO4MFeDuTBYg7owWYO7MFqDvDBbg70wXIO+MF2DvzBeg8AwX4PBMGCDwjBhg8MwYoPEMGODxTBkg8YwZYPHMGaDyDBng8kwaIPKMGmDyzBqg8wwa4PNMGyDzjBtg88wboPQMG+D0TBwg9IwcYPTMHKD1DBzg9UwdIPWMHWD1zB2g9gwd4PZMHiD2jB5g9sweoPcMHuD3TB8g94wfYPfMH6D4DCAg+EwgYPiMIKD4zCDg+QwhIPlMIWD5jCGg+cwh4PoMIiD6TCJg+owioPrMIuD7DCMg+0wjYPuMI6D7zCPg/AwkIPxMJGD8jCSg/Mwk4P0MJSD9TCVg/YwloP7MEWB/DBbgf0wUoH+MFOBMTKKhzIyi4c5MoyHpDKFh6UyhoemMoeHpzKIh6gyiYcDM2WHDTNphxQzYIcYM2OHIjNhhyMza4cmM2qHJzNkhyszbIc2M2aHOzNuh0kzX4dKM22HTTNih1EzZ4dXM2iHezN+h3wzj4d9M46HfjONh44zcoePM3OHnDNvh50zcIeeM3GHoTN1h8QzdIfNM4OHAE7qiAFOmpIDTrWOB06clghO5I8JTk+OCk7jjwtOuokNTnOVDk5elxBOoJgRTk6JFE6OihVOoZgWTqKQF07AmRhOdYsZTriVHk7ljyFOvJcmTsCVKE5M7SpOopgtToaSMU6jmDJO+Is2TqSYOE7bijlOT5I7TuWOPE6lmD9OpphCTqeYQ05UlEVOdotLTlaUTU7hk05OwYxPTlKWVU5o5VZOqJhXTuaPWE6pmFlOs4ldTuOLXk7ujF9O55ZiTqSbcU6Ql3NO+5N+TqOKgE5Ui4JOqpiFTquYhk65l4hOXJeJToiRik6tmItOlo6MTvGTjk6wmJFOXYmSTt2MlE7cjJVO5IiYTmqYmU5pmJtOsY2cTp+Ink6xmJ9OspigTrOYoU5TlqJOtJikTvCMpU7liKZOkpaoTpyLq06di6xOnoutTuCSrk66l7BOtZizTraYtk63mLpObJDATlmPwU5tkMJOvJjETrqYxk67mMdOd4vKTqGNy07uic1OuZjOTriYz06nldROZY7VTmSO1k68kddOvZjYTnSV2U7lkN1OV4HeTr6Y307AmOFOTe3jTuOR5E7fl+VOyIjtTr+Y7k68ifBOwovyToeS9k6PjPdOwZj7TkOU/E5O7QBPT+0BT+mKA09Q7QlPwpgKT8mIDU/ejA5P6ooPT5qVEE+wlBFPeIsaT++JHE/lmB1PYJMvT4yUME/EmDRPupQ2T+CXOE9MkDlPUe06T2aOPE+Xjj1PvolDT8+SRk9BkkdPyJhNT8qITk/hkk9PWo9QT7KNUU9Dl1NPzJFVT72JVk9S7VdPx5hZT12XWk/DmFtPxZhcT+yNXU/GmF5PQ5tpT86Yb0/RmHBPz5hzT8CJdU+5lXZPyZh7T82YfE/xjH9PZ46DT6SKhk/SmIhPypiKT1Tti0/hl41PmI6PT8uYkU/QmJJPU+2UT1btlk/TmJhPzJiaT1Xtm0+fi51Py4igT6CLoU+/iatPRJutT5mWrk+Ola9P8oy1T06Qtk+1l79P1pXCT1eMw0+jkcRP4onJT0Xtyk9yj81PV+3OT9eY0E/cmNFP2pjUT9WY10+tkdhP2JjaT9uY20/ZmN1P25XfT9aY4U9NkONPk5bkT92Y5U/emO5PQ4/vT+uY809vlPVPVZX2T+aY+E/ulfpPtIn+T+qY/09a7QVQ5JgGUO2YCVBxkQtQwowNUHuUD1DF4BFQ7JgSUHyTFFDhmBZQ9IwZUPOMGlDfmB5QW+0fUNiOIVDnmCJQWe0jUO2VJFBskiVQ45gmUJGMKFDgmClQ6JgqUOKYK1DPlyxQ6ZgtUGCYNlDkizlQkIxAUFjtQlBe7UNQ7phGUFztR1DvmEhQ85hJUMyIT1DOlVBQ8phVUPGYVlD1mFpQ9JhcUOKSZVCSjGxQ9phwUF3tclDDjnRQpJF1UOOSdlD0i3hQ95h9UFWLgFD4mIVQ+piNUFSWkVCGjJRQX+2YUFCOmVD1lJpQ+ZisUMONrVBil7JQ/JizUEKZtFD7mLVQwo23UJ2PvlBYjMJQQ5nFUM2LyVBAmcpQQZnNUK2Tz1CckdFQoYvVUGyW1lBEmdhQYe3aULuX3lBFmeNQSJnlUEaZ51Btke1QR5nuUEmZ9FBg7fVQS5n5UEqZ+1DGlQBRVosBUU2ZAlFOmQRRrYkJUUyZElHyjhRRUZkVUVCZFlFPmRhR1JgaUVKZH1GejyFRU5kqUUSXMlHXljdRVZk6UVSZO1FXmTxRVpk/UViZQFFZmUFR8ohDUbOMRFFajEVRW49GUZuSR1Gii0hR5pBJUfWMSlFi7UtRjo1MUVuZTVHGlk5RZZNQUZmOUlFamVRRXJlaUX2TXFGVimJRXZlkUWPtZVH8k2hRU5FpUV+ZalFgmWtRqpRsUfaMbVFamG5RYZlxUaSLdVG6lXZRtJF3Ue+LeFFUk3xRk4yAUWKZglFjmYVR4JOGUX6JiVFmmYpR+42MUWWZjVHEjY9RZ5mQUezjkVFomZJRYJaTUWmZlVFqmZZRa5mXUeePmVHKjp1RZO2gUaWKolFumaRRbJmlUbuWplFtmahReZWpUW+ZqlFwmatRcZmsUX6TsFF1mbFRc5myUXSZs1FymbRR4Y21UXaZtlHolrdR4pe9UXeZvlFl7cRRppDFUXiZxlF5j8lReZnLUZySzFG9l81RgJPWUcOZ21F6mdxRo+rdUcOL4FF7meFRfZbmUYiP51H6kelRfZnqUeKT7FFm7e1RfpnwUYCZ8VFNivVRgZn2UaWL+FHKk/lRmon6UW+P/VGflP5RgpkAUoGTA1JukARSg5kGUqqVB1LYkAhSoIoKUqeKC1KEmQ5ShpkRUlmMFFKFmRVSZ+0XUvGXHVKJjyRSu5QlUsqVJ1KHmSlSmJcqUoiZLlKJmTBSnpMzUoqZNlKnkDdS/I04UpSMOVKLmTpSaI47Uo+NQ1LkkkRSjZlHUqWRSlLtjUtSjplMUo+ZTVJPkU9SjJlUUpGZVlJVlltShI1eUpCZY1KVjGRS3I1lUo2UaVKUmWpSkplvUpuVcFLoj3FSm5lyUoSKc1KVmXRSk5l1Um6RfVKXmX9SlpmDUmOKh1KAjIhSnJmJUquXjVKYmZFSnZmSUpqZlFKZmZtSzZecUmjtn1L3jKBSwYmjUvKXplJp7alSlY+qUneTq1KFjaxSoJmtUqGZr1Jb7rFS45e0UkqYtVKjmblS+Iy8UqKZvlJOisBSau3BUqSZw1J1lsVSupLHUkWXyVLXlc1SpZnSUtPo1VKuk9dSppnYUqiK2VKxlttSa+3dUp+P3lKnmd9S5ZXgUquZ4lKokONSqJnkUs6L5lKpmedSqYryUk2M81KsmfVSrZn4Uq6Z+VKvmfpS2Y7+UvmM/1LclgBTbO0BU+aWAlP1kwVT75UGU7CZB1Nt7QhTsZkNU7OZD1O1mRBTtJkVU7aZFlO7iRdTa5YZU/qNGlO3mR1TeJEgU6CPIVOniyNTuJkkU27tKlPZlC9TuZkxU7qZM1O7mThTvJk5U0OVOlPmiztT44g/U72TQFO9mUFTXI9DU+eQRVO/mUZTvplHU6GPSFPfjElTwZlKU7yUTVPCmVFT2pRSU7KRU1PskVRTpotXU+yTWFNQklpTjpRcU22WXlPEmWBT6JBmU1SMaVPFmW5TxplvU0uJcFPziHFT64pyU2/tc1OmkXRTcIt1U5GXd1PJmXhTtYl7U8iZf1Ooi4JTypmEU++Wk1Nw7ZZTy5mYU9CXmlP6jJ9TtIygU8yZpVPOmaZTzZmoU36QqVNYia1TfYmuU8+ZsFPQmbJTce2zU7WMtlPRmbtTjovCU1GOw1PSmchTlJbJU7ONylN5i8tTRpfMU2+RzVO9lM5T+47UU2aP1lPmjtdT847ZU5aP21O+lN1Tcu3fU9WZ4VNiieJTcJHjU/uM5FPDjOVT5YvoU9mZ6VNAkupT/JHrU6mL7FOij+1T2pnuU9iZ71PCifBT5JHxU7aO8lNqjvNTRYn2U5CK91OGjfhTaY76U9uZAVTcmQNUaIsEVGWKCFSHjQlUZ4sKVN2SC1REiQxUr5MNVLyWDlRAjQ9UmZcQVGaTEVT8jBtUTowdVOWZH1ThiyBUaZYmVNuUKVTkmStU3IosVN+ZLVTgmS5U4pk2VOOZOFR6izlUgZA7VKuVPFThmT1U3Zk+VOGMQFTemUJUQ5hGVPCVSFTmkklU4IxKVJCNTlTmmVFU25NfVOqZaFT8jmpU9I5wVO2ZcVTrmXNUoZZ1VOiZdlTxmXdU7Jl7VO+ZfFTEjH1UvZaAVPCZhFTymYZU9JmKVHXti1TujYxUYZiOVOmZj1TnmZBU85mSVO6ZnFR07aJU9pmkVEKapVT4mahU/JmpVHbtq1RAmqxU+ZmvVF2aslTnjbNUUIq4VPeZvFREmr1U9Ii+VEOawFSjiMFUaZXCVEGaxFT6mcdU9ZnIVPuZyVTGjdhURZrhVPWI4lROmuVURprmVEea6FSjj+lUiZbtVEya7lRLmvJUTpP6VE2a/VRKmv9Ud+0EVVOJBlW0jQdVT5APVUiaEFWCkxRVSZoWVaCILlVTmi9VQpcxVaWPM1VZmjhVWJo5VU+aPlXBkUBVUJpEVe2RRVVVmkZVpI9MVVKaT1XillNVW4xWVVaaV1VXmlxVVJpdVVqaY1VRmntVYJp8VWWaflVhmoBVXJqDVWaahFVQkYZVeO2HVWiaiVVBjYpVXpqLVZ2SmFVimplVW5qaVauKnFXsip1VhYqeVWOan1VfmqdVloyoVWmaqVVnmqpVcpGrVWmLrFWqi65VZJqwVfKLtlVjicRVbZrFVWuax1WlmtRVcJraVWqa3FVumt9VbJrjVWuO5FVvmvdVcpr5VXea/VV1mv5VdJoGVlGSCVbDiRRWcZoWVnOaF1amjxhWUokbVnaaKVbciS9WgpoxVvqPMlZ9mjRWe5o2VnyaOFZ+mkJWXIlMVliRTlZ4mlBWeZpbVpqKZFaBmmhW7YpqVoSaa1aAmmxWg5p0VqyVeFbTk3pWtpSAVoaahlaFmodWZIqKVoeaj1aKmpRWiZqgVoiaolZYlKVWi5quVoyatFaOmrZWjZq8VpCawFaTmsFWkZrCVo+aw1aSmshWlJrOVpWa0VaWmtNWl5rXVpia2FZkmdpW+o7bVmyO3lbxieBW9ojjVmOS7laZmvBWoo3yVs2I81Z9kPlWmpr6VsWM/VaRjf9WnJoAV5uaA1felQRXnZoIV5+aCVeemgtXoJoNV6GaD1eXjBJXgIkTV6KaFlekmhhXo5ocV6aaH1d5kyZXp5onV7OIKFfdjS1XXIwwV26SN1eomjhXqZo7V6uaQFesmkJX4o1HV8+LSldWlk5XqppPV62aUFe/jVFXQo1ZV3ntYVexmmRXo41lV3rtZldSkmlXrppqV9iSf1eymoJXgpCIV7CaiVezmotXXoyTV7SaoFe1mqJXQ42jV1+KpFe3mqpXuJqsV3vtsFe5mrNXtprAV6+aw1e6msZXu5rHV33tyFd87ctXhJbOV+mP0le9mtNXvprUV7ya1lfAmtxXV5TfV+aI4Fd1leNXwZr0V/uP91e3jvlXfJT6V+6K/FfpjQBYeJYCWLCTBViYjAZYzZEKWL+aC1jCmhVYwpEZWMOaHVjEmiFYxpokWOeSKlisii9Yn+owWIGJMVjxlTRY6o81WGeTOljkjT1YzJpAWLuVQVjbl0pY8olLWMiaUVhZkVJYy5pUWIOTV1hok1hYhJNZWLeUWljLkl5Yx41iWMeaaViWiWtYVZNwWMmacljFmnVYb5B5WM2aflhtj4NYq4uFWM6ak1jmlZdYnZGcWMSSnliB7Z9Y0JqoWG6Wq1jRmq5Y1pqyWILts1itlbhY1Zq5WM+auljSmrtY1Jq+WKSNwVjHlcVY15rHWGSSyljzicxY64/RWNma01jYmtVYiI3XWNqa2FjcmtlY25rcWN6a3ljTmt9Y4JrkWN+a5VjdmutYbY7sWHCQ7lhzke9Y4ZrwWLqQ8VjriPJYhJT3WNmS+VjjmvpY4pr7WOSa/Fjlmv1Y5poCWeeaCVnPlQpZ6JoLWYPtD1nEiRBZ6ZoVWVuXFllPihhZx5kZWWePGlm9kRtZ6pocWemWIlmyliVZ7JonWeWRKVlWkypZvpErWXaVLFntmi1Z7pouWZuJMVm4jjJZ75o3Wc6IOFnwmj5Z8ZpEWYKJR1nvikhZ3pNJWfKVTln1mk9ZdJFQWfSaUVlfjFNZhO1UWXqWVVnzmldZhZNYWfeaWln2mltZhe1dWYbtYFn5mmJZ+JpjWYftZVmciWdZ+ppoWaePaVn8mmpZRJJsWfuablmxlXNZl490WXqTeFlAm31ZRI2BWUGbgllAlINZ3JSEWc+WillElI1ZSpuTWVeLlllkl5lZrZabWaqbnVlCm6NZRZukWYjtpVnDkahZV5asWWmTsllGm7lZhZa6WYntu1nIjb5ZqI/GWUebyVlvjstZbo7QWbeI0VnGjNNZqZDUWc+I2VlLm9pZTJvcWUmb5VlXieZZrYroWUib6lnDlutZUJX2WaaI+1n3iP9ZcI4BWtCIA1qhiAlaUZsRWk+bGFq6lhpaUpscWlCbH1pOmyBaUJAlWk2bKVrYlS9a4ow1WlabNlpXmzxaqY9AWlObQVpLmEZaa5RJWlWbWlqljWJaWJtmWneValpZm2xaVJt/WrmWklp9lJpaWpubWlGVvFpbm71aX5u+WlybwVrFicJaXpvJWrmOy1pdm8xamYzQWmub1lpkm9daYZvhWoSS41pgm+ZaYpvpWmOb+lplm/taZpsJW/CKC1tomwxbZ5sWW2mbIlvsjypbbJssW9qSMFtkiTJbaps2W22bPltum0BbcZtDW2+bRVtwm1BbcY5RW3KbVFtFjVVbc5tWW4rtV1uajlhbtpFaW3SbW1t1m1xbeY5dW0aNX1vQlmNbR4tkW8eMZVt2m2Zbd4ppW3eba1u3kXBbeJtxW6Gbc1t5m3Vbept4W3ubelt9m4BbfpuDW4CbhVvukYdbRomIW+eOiVvAiItbdpGMW66KjVuzjo9bR42VW4aTl1tAj5hbr4qZW4iSmlvokptbtoicW1iLnVvzlZ9bwI6iW3GLo1vpkKRbuo6lW0eXpluBm65be4uwW8mNs1tRirRbg4m1W6qPtlvGibhbgpu5W2WXv1toj8Bbi+3CW+KOw1uDm8Rb8YrFW9CTxlunlsdbhJvJW4WbzFt4ldBbh5vSW6aK01v1i9RbhpvYW43t21uwit1bUZDeW4ub31tAjuFbx4niW4qb5FuIm+VbjJvmW4mb51tKlOhby57pW1KQ61uNm+xbju3uW76X8FuOm/NbkJv1W56S9luPm/hboZD6W5uO/lvOkf9b9Y4BXJWVAlzqkARcy44FXJGbBlyrjwdckpsIXJObCVzRiApcuJELXHGQDVyUmw5csZMPXKyPEVytjxNclZsWXOuQGlyujx5cj+0gXJabIlyXmyRc3pYoXJibLVzEizFcQY84XJmbOVyamzpc2o47XEuQPFzykz1cc5A+XPaUP1xBlEBcx4tBXJubRVyPi0ZcnJtIXPyLSlzNk0tcrolNXHKOTlydm09coJtQXJ+bUVz7i1NcnptVXFeTXlyukWBcapNhXMaOZFx3kWVcmpdsXKKbblyjm29c1JNxXFKOdlylm3lcppuMXKebkFzyipFcqJuUXKmboVyqiaZckO2oXFqRqVziiqtcq5usXKaWsVzQkbNceIq2XK2bt1yvm7hc3Yq6XJHtu1ysm7xcrpu+XLGbxVywm8dcspvZXLOb4Fy7k+FcrIvoXOOJ6Vy0m+pcuZvtXLeb71z1lfBc9JX1XJLt9lyHk/pctpv7XHOP/Vy1mwddkpALXbqbDl3ojRFdwJsUXcGbFV27mxZdUooXXbybGF3FmxldxJsaXcObG12/mx9dvpsiXcKbJ12T7Sld9pVCXZbtS13Jm0xdxptOXcibUF2Sl1Jdx5tTXZTtXF29m2ldk5BsXcqbbV2X7W9dtY1zXcubdl3Mm4Jdz5uEXc6bh13Nm4tdiJOMXbibkF3Vm51d0ZuiXdCbrF3Sm65d05u3XdabuF2Y7bldme26XeSXvF3Xm71d1JvJXdibzF3eis1d2ZvQXZrt0l3bm9Nd2pvWXdyb213dm91d7JDeXUKP4V2Ej+Ndg5HlXUiN5l22jeddSY3oXZCL613em+5dt43xXciM8l3fm/NdpJb0XWKU9V3gm/ddSo37XaqK/V1Gkv5d0IsCXnOOA156lQZev5QLXuGbDF7zihFe5JsWXp+SGV7jmxpe4psbXuWbHV7pkiVeg5ArXnSOLV7IkC9e0ZEwXkGLM16gkjZe5ps3XuebOF7tjz1eWJZAXuqbQ17pm0Re6JtFXp2VR17xm0xeeZZOXuubVF7tm1Vei5ZXXuybX17um2FeppRiXu+bY168lWRe8JtyXrGKc169lXReTpR1XvKbdl7zm3heS415XrKKel70m3tetox8XmOXfV5Il35e9Ip/XvabgV6hkoNeTI2EXq+Ph17dlIpesI+PXpiPlV7qkpZe95WXXliTml5NjZxee5WgXvebpl54k6dewI2rXsmMrV7rkrVewYi2Xo6Pt15OjbheZpfBXvibwl75m8NecJTIXvqbyV71l8peTJjPXvyb0F77m9NeZorWXkCc2l5DnNteRJzdXkKc315fleBesY/hXkac4l5FnONeQZzoXkec6V5InOxeSZzwXkyc8V5KnPNeS5z0Xk2c9l6Eifde7JL4Xk6c+l6ajPte9In8XlWU/l5PnP9e+ZMBX9mVA19QnARfTZgJX1GcCl++lQtfVJwMX5+YDV+vmA9fro4QX/OTEV9VnBNffIsUX6KSFV/4iBZfVpwXX6SVGF9PjRtfb5IfX+2SIV+b7SVf7ZYmX7eMJ1/KjClfV5wtX1icL19enDFf4440X5ztNV+jkjdfrYs4X1mcPF9KlT5fZZJBX1qcRV9L7UhfW5xKX66LTF9cnE5fXZxRX1+cU1+Wk1ZfYJxXX2GcWV9inFxfU5xdX1KcYV9jnGJfYIxmX0aVZ1+d7Wlfyo1qX1aVa1+kkmxfapVtX2SccF+yj3FfZYlzX2Wcd19mnHlf8JZ8X96Uf19pnIBfnYmBX6qQgl9onINfZ5yEX2GMhV/SkYdfbZyIX2ucil9qnItfpZeMX+OMkF+Zj5FfbJySX2uTk19dj5dfvpOYX3CcmV9vnJ5fbpygX3GcoV/kjKhfcpypX5yVql96j61fc5yuX/eUs1+/k7RfpZK3X57tuV9Pk7xfdJy9X0qLw19TkMVfS5XMX/WKzV9FlNZfdZzXX3WO2F9ZltlfWpbcX56J3V96nN5fn+3gX4mS5F93nOtf9YnwX6uc8V95nPVfT5T4X3ic+192nP1fmo3/X3ycDmCDnA9giZwQYIGcEmB7kxVghpwWYHyVGWCAnBtghZwcYOWXHWB2jiBg05EhYH2cJWB9iyZgiJwnYKuQKGCFiSlggpwqYPaJK2CHnC9gr4sxYIScOmCKnEFgjJxCYJacQ2CUnEZgkZxKYJCcS2D2l01gkpxQYLCLUmBQjVVgmo9ZYJmcWmCLnF1goO1fYI+cYGB+nGJg+IljYJOcZGCVnGVgcJJoYKaNaWC2iWpgjZxrYJicbGCXnG1gsYtvYKeRcGCGinVgYox3YI6cgWCanINgnZyEYJ+chWCh7Ylgu46KYKLti2ClnIxg7pKNYJuckmCjnJRg94mWYKGcl2CinJpgnpybYKCcn2DljKBgSZejYLOKpmB4iadgpJypYFmUqmCriLJg35SzYHuctGCqnLVgrpy2YOOWuGCnnLxgiZO9YKycxWDuj8ZgrZzHYNWT0WBmmNNgqZzVYKTt2GCvnNpgm43cYMmQ3mCj7d9g0ojgYKic4WCmnONgeZHnYJyc6GBTjvBgxJHxYLuc8mCm7fNgepH0YLac9mCznPdgtJz5YOSO+mC3nPtgupwAYbWcAWFEjwNhuJwGYbKcCGH6lglh+ZYNYbycDmG9nA9h04gRYaftFWGxnBph8IsbYaSIH2G0iiBhpe0hYbmcJ2HBnChhwJwsYcWcMGGp7TRhxpw3YajtPGHEnD1hx5w+Yb+cP2HDnEJhyJxEYcmcR2G+nEhhnI5KYcKcS2HUkUxhUY1NYbCcTmFUkFNh1pxVYeeVWGHMnFlhzZxaYc6cXWHVnF9h1JxiYZ2WY2G1imVh0pxnYWSMaGFTimthz5xuYbaXb2HRnHBh1IhxYdOcc2HKnHRh0Jx1YdecdmFjjHdhy5x+YXyXgmFKl4dh2pyKYd6cjmGekZBh95eRYd+clGHcnJZh2ZyYYartmWHYnJph3ZykYa6Vp2Gyk6lhZYyrYeCcrGHbnK5h4ZyyYZuMtmGvibph6Zy+YbaKw2HnnMZh6JzHYaeNyGHmnMlh5JzKYeOcy2HqnMxh4pzNYeyc0GH5ieNh7pzmYe2c8mGmkvRh8Zz2Ye+c92HlnPhhnIz6YfCc/GH0nP1h85z+YfWc/2HynABi9pwIYvecCWL4nApi6JUMYvqcDWL5nA5iXo8QYqyQEWLkiRJi+okTYqvtFGL7nBZivYgaYsqQG2L8nB1iweYeYkCdH2KBjCFiQZ0mYu2QKmJCnS5iQ50vYlmLMGJEnTJiRZ0zYkadNGLVkThiy4w7Yt+WP2JblkBiio9BYkedR2LukEhiu+dJYuCUS2Lojk1iy41OYkidU2LFkVVipZVYYu+RW2JLnV5iSZ1gYkydY2JKnWhiTZ1uYq+VcWK1iHZifZV5YuGUfGJOnX5iUZ1/YrOPgGJai4JiT52DYladhGK0j4liUJ2KYmOUkWJ9l5JiUp2TYlOdlGJXnZViipOWYlSdl2JSjZhi3JCbYmWdnGKylJ5i8JGmYqztq2LilKxiq52xYviVtWLvkrlilZa7YlqdvGKfib1iipLCYmOdxWJTksZiXZ3HYmSdyGJfncliZp3KYmKdzGJhnc1ij5TPYlud0GL7idFiWZ3SYpGL02LxkdRiVZ3XYlid2GJTjdli2ZDbYrWP3GJgnd1icZTgYpKL4WJniuxih4rtYkCQ7mJone9ibZ3xYmmd82KdjPVibp32YkGO92KJjf5iRY//YlydAWOdjgJja50HY3eOCGNsnQljwogMY2edEWOnkhljk4sfY7KLJ2NqnShjpYgrY8GNL2NVkDpj8JI9Y9KUPmNwnT9jfZFJY6iRTGNKjk1jcZ1PY3OdUGNvnVVj35VXY7uSXGN7kWdj+ZVoY8yOaWOAnWtjfp1uY5iQcmOejHZjeJ13Y7ePemPmk3tjUJSAY3adg2N8kYhj9o6JY3udjGO2j45jdZ2PY3qdkmNylJZjdJ2YY0CMm2N8ip9jfJ2gY6mXoWPMjaJjVJKjY3mdpWPakKdjVI2oY4SQqWOGiapjW5GrY3edrGNki7JjZoy0Y82StWN9nbtjfpG+Y4GdwGODncNjtZHEY4mdxmOEncljhp3PY2CV0GPxktJjh53WY0uX2mNnl9tjt4rhY6yI42OFneljgp3uY/aK9GOHifVjre32Y4id+mNolwZkjJ0NZLmRD2STnRNkjZ0WZIqdF2SRnRxkcp0mZI6dKGSSnSxkwJQtZIuTNGSLnTZkj506ZGeMPmTvjUJk25BOZJedWGRFk2Bkru1nZJSdaWSAlm9klZ12ZJadeGTMlnpkoJCDZIKMiGSdnZJkVI6TZJqdlWSZnZpkUZSdZK/tnmSzk6RkUJOlZJudqWScnatkj5WtZGSUrmRCjrBk75CyZG+WuWRoirtko528ZJ6dwWRpl8JkpZ3FZKGdx2Sinc1kgJHOZLDt0mSgndRkXp3YZKSd2mSfneBkqZ3hZKqd4mRGk+NkrJ3mZEOO52SnnexkW4vvZK2d8WSmnfJksZ30ZLCd9mSvnfpksp39ZLSd/mTvjwBls50FZbedGGW1nRxltp0dZZCdI2W5nSRluJ0qZZidK2W6nSxlrp0vZXiONGW7nTVlvJ02Zb6dN2W9nThlv505ZfyJO2VVjT5l+pU/Za2QRWXMjEhlwZ1NZcSdTmWx7U9lcZVRZX6LVWXDnVZlwp1XZXOUWGXFnVlls4tdZcedXmXGnWJluIpjZVWOZmXWk2xlaIxwZZSQcmXInXRlrpB1ZUeTd2V+lXhlyZ2CZcqdg2XLnYdltpWIZXybiWXEkIxla5WOZdaNkGXjlJFlwZSXZWyTmWW/l5tlzZ2cZc6On2XOnaFltIikZdKLpWXLkKdlgJWrZc+drGVhjq1lZpKvZXqOsGVWkLdl0J25ZfuVvGWXib1le47BZdOdw2XRncRl1J3FZbeXxmXSnctl+ZDMZdWdz2WwkdJl1p3XZfiK2WXYndtl153gZdmd4WXaneJl+YrlZfqT5mVVkudljIvoZXyO6WWBkexle4/tZa6I8WXbnfploIn7Zd+dAGay7QJmVo0DZt6dBmapjQdmuI8JZrXtCmbdnQxmuY8OZr6WD2aojRNm1YgUZsyQFWaz7Rxm5J0eZrftH2avkCBmZokkZrjtJWZ0jydmhpYoZvCNLWa6jy5mtu0vZqWQMWZH7TRm4501ZuGdNmbinTtmtO08ZouSP2ZFnkFm6J1CZp6OQ2ZXjURm5p1JZuedS2ZXkE9m5Z1SZk6OV2a67Vlmu+1dZuqdXmbpnV9m7p1iZu+dZGbrnWVmue1mZkGKZ2bsnWhm7Z1pZtOUbmaBlW9maYxwZvCdc2a97XRmsJB2ZruPemZxkoFmxYuDZvGdhGb1nYdmyYmIZvKdiWb0nY5m852RZouPlmZnkpdmw4iYZvadmWa+7Z1m952gZr/tomaokqZm75erZmKOrmbplbJmwO20ZlyWuGZBnrlm+Z28Zvydvmb7nb9mwe3BZvidxGZAnsdm3JPJZvqd1mZCntlmjI/aZkOe3GZql91mmJTgZkSe5mZGnulmR57wZkie8mbIi/NmZ4n0ZliN9WZJnvdmSp74ZpGP+WaCkfpmwu37Zkrt/GbWmf1mXZH+ZlyR/2bWkQBnxY0DZ/CYCGeOjAlnTJcLZ/yVDWeelQ5nw+0PZ0ueFGfxjRVnvZIWZ0yeF2dOmBtnXZYdZ6mSHmdNnh9n+oomZ06eJ2dPnihn2JYqZ6KWK2eWlixne5YtZ0SOLmdRnjFn6Y40Z3CWNmdTnjdnVp44Z1WeOmf3ij1ngIs/Z1KeQWdUnkZnV55JZ5mQTmebl09nx4hQZ96NUWe6kVNn245WZ/GPWWdanlxnbZNeZ1ieX2epkWBnWZ5hZ/CPYmfblmNnW55kZ1yeZWeIl2Znxe1qZ2GebWdZjW9ndJRwZ16ecWeMk3Jn3J1zZ+CddWdui3dnZpR8Z2Cefme8j39nwpSFZ2aeh2f4lIlnXZ6LZ2OejGdinpBnzZCVZ42Wl2fRl5pnh5acZ8qJnWd9jqBnZ5ihZ2WeomeVkKZnZJ6pZ1+er2fNjLNna560Z2metmfLibdnZ564Z22euWdznrtnxu3AZ8jtwWfGkcRnv5XGZ3WeymdBlc5ndJ7PZ5CU0GdeltFnuYrTZ/WQ1Gdfj9hn0ZLaZ02X3Wdwnt5nb57iZ3Ge5Gdunudndp7pZ2ye7Gdqnu5ncp7vZ2ie8WeMkvNn9pb0Z8SO9WfyjftnuI3+Z4+W/2dgigFoye0CaMySA2jIkwRoaIkTaPCQFmiykBdoSYweaHieIWhajSJonIopaHqeKmiUiitogZ4yaH2eNGjxkDhoaoo5aKqNPGhpij1ozY1AaHueQWiFjEJoaoxDaI2TRGjK7UZoeZ5IaMSITWh8nk5ofp5QaMuLUWhLjFJox+1TaLqKVGhqi1logp5caPeNXWiRll9oVo5jaIOeZ2hPlXRoj552aLGJd2iEnn5olZ5/aIWegWjAl4NojJ6FaH6UjWiUno9oh56TaLKIlGiJnpdoW42baIuenWiKnp9ohp6gaJGeomi9j6Zo65qnaOaMqGicl61oiJ6vaPKSsGhCirFoq42zaICetWiQnrZogYq5aI6eumiSnrxojpPEaPyKxmiwnshoSO3JaMeWymiXnsto+4rNaJ6ez2jL7dJoX5bUaJ+e1WihntdopZ7YaJme2mhJkt9oj5PgaKme4WicnuNopp7naKCe7mhYkO9oqp7yaLGQ+Wionvpou4oAaW+YAWmWngRppJ4FadaICGmYngtpuJYMaZ2eDWlBkA5pxZIPaZOeEmmjnhlpmpAaaa2eG2mRihxpn4whaa+eImmaniNprp4laaeeJmmbnihpq54qaayeMGm9njRpzJM2aaKeOWm5nj1pu54/adaSSmlrl1NplpVUabaeVWnIkVlpvJ5aaV6RXGmznl1pwJ5eab+eYGntk2Fpvp5iaeiTaGnN7Wppwp5rabWebWnGi25puJ5vaXyPc2mAlHRpup51acmLd2mynnhptJ55abGefGlPmH1peYp+abeegWnBnoJpVIqKaeWNjml8iZFp0p6UaVCYlWnVnphpz+2baVmQnGnUnqBp056nadCermnEnrFp4Z6yacOetGnWnrtpzp6+acmev2nGnsFpx57Dac+ex2mg6sppzJ7LaVyNzGnGks1phJHOacqe0GnFntNpyJ7YaWyX2WmKlt1pzZ7eadee4mnQ7edp357oadie62nlnu1p457yad6e+WndnvtpzpL9aYWR/2nbngJq2Z4FauCeCmrmngtq85QMauyeEmrnnhNq6p4UauSeF2qUkhlqV5UbatqeHmrinh9qvo8has2WImr2niNq6Z4paqCMKmqhiStqfoouatGeMGrR7TVqv482au6eOGr1njlq9446apKKPWpNkkRq655GatPtR2rwnkhq9J5LarSLWGpri1lq8p5fakCLYWrJk2Jq8Z5mavOea2rS7XJq7Z5zatTteGrvnn5q1e1/aoCKgGpokoRq+p6NaviejmrnjJBq956XakCfnGp3nqBq+Z6iavueo2r8nqpqS5+sakefrmqNnrNqRp+4akWfu2pCn8Fq6J7CakSfw2pDn9FqSZ/TakWY2mpMn9tq+Yveakif32pKn+Jq1u3katft6GqllOpqTZ/6alGf+2pOnwRrk5cFa0+fCmvcnhJrUp8Wa1OfHWtUiR9rVZ8ga4eMIWufjiNr04sna6KJMmt+lzdrV584a1afOWtZnzprXIs9a9SLPmu8ikNrXJ9Ha1ufSWtdn0xrzIlOa1aSUGten1NrvYpUa2CfWWtfn1trYZ9fa2KfYWtjn2Jrfo5ja7OQZGufjWZrkJVpa+CVamtjmG9rlY5za86NdGvwl3hrZJ95a2Wfe2uAjn9rZp+Aa2efg2tpn4RraJ+Ga3eWiWt9j4pr6o6La2OOjWtqn5VrbJ+Wa0KQmGtrn55rbZ+ka26fqmtvn6trcJ+va3GfsWtzn7Jrcp+za3SftGujibVraZK3a3WfumtFjrtra4q8a3afv2thk8BryprFa0KLxmt3n8treJ/Na+qVzmuIltJrxZPTa3mf1GvklNZr2O3Ya/mU22vRlt9rep/ra3yf7Gt7n+9rfp/za32fCGyBnw9sgY4RbK+WE2yCnxRsg58XbEOLG2yEnyNshp8kbIWfNGyFkDdsWJU4bGmJPmzDlD9s2e1AbPOSQWxgj0JsgYtObMSUUGysjlVsiJ9XbL6KWmyYiVxs2u1dbPCTXmyHn19sXY1gbHKSYmyJn2hskZ9qbIqfb2zc7XBsv5FybIKLc2ySn3psiIx9bESLfmyQn4Fsjp+CbIufg2yAl4Zs2+2IbL6SjGzXk41sjJ+QbJSfkmyTn5NsQoyWbKuJmWy5jZpsjZ+bbI+foWx2lqJs8pGrbJeWrmycn7FsnZ+zbM2JuGymlbls+5a6bJ+fu2yhjrxswI+9bJifvmyen79siInBbLWLxGyVn8Vsmp/JbPKQymyRlMxs5ZTTbJef1WxAltdsmZ/ZbKKf2mzd7dtsoJ/dbJuf4WxBluJsZ5TjbIOL5WxEk+hsjZLqbKOf72yhn/Bs15HxbJaf82xqiQRt3u0LbW2XDG2unxJtrZ8XbfSQGW2qnxttjJcebbSTH22knyVtw5IpbWuJKm1ejSttp58ybUaPM22snzVtq582baafOG2pnzttiIo9baifPm1olEFtrJdEbfKPRW3zkFlttJ9abbKfXG1slWNtr59kbbGfZm1ZiWltX41qbVGYbG1cim5tgpVvbeDtdG2Bl3dtQ4p4bVqQeW2zn4VtuJ+Hbd/tiG3Bj4xtT5eObbWfk22wn5Vttp+WbeHtmW3cl5ttk5OcbcCTrG3i7a9tVYqybXSJtW28n7htv5+8bcGXwG2El8Vtxp/GbcCfx229n8tt0pfMbcOfz23j7dFtaY/SbcWf1W3Kn9htkZPZbcif3m3Cn+FtV5Lkbcmf5m2+n+htxJ/qbcuf6236iOxtwZ/ubcyf8W1bkPJt5e3zbX6P9W2jlfdtrI34beTt+W25n/ptx5/7bVmT/G3m7QVutJAHbomKCG7PjQluwo8KbrufC25hjxNua4wVbrqfGW7QnxpujY8bbriMHW7fnx9u2Z8gbpSLIW5ukyNu1J8kbt2fJW6tiCZuUYknbuntKW63iStu1p8sbqqRLW7Nny5uz58vbmCNOG7gnzlu5+06btufPG7q7T5u059DbtqfSm6plk1u2J9ObtyfVm7OjFhuw49bbliSXG7o7V9u0p9nbk6Xa27Vn25uzp9vbpKTcm7Rn3Zu159+bnCYf268joBunpaCbuGfjG6slI9u7Z+QbrmMlm6Aj5hu45+cbq2XnW5hjZ9u8J+ibuyIpW7un6pu4p+vbuifsm7qn7Zubpe3buWfum5Nk71u55+/buvtwm7vn8Ru6Z/FbsWWyW7kn8tuoI7Mbvyf0W6KitNu5p/Ubuuf1W7sn91u6pHebtiR7G70n+9u+p/ybvif9G5Ik/duQuD4bvWf/m72n/9u3p8Bb5mLAm9ZlQZvvY4Jb5eND29SmBFv8p8Tb0HgFG+JiRVvhpEgb5mUIm+/iiNv+Jcrb5+WLG/QkjFv+Z8yb/ufOG9RkT5vQOA/b/efQW/xn0VvwYpUb4mMWG9O4FtvSeBcb/aQX2+DimRvgY9mb1LgbW9L4G5vqpJvb0jgcG/XknRva+B4b0Xgem9E4HxvTeCAb0fggW9G4IJvTOCEb5+Qhm9D4Ihv7O2Ob0/gkW9Q4JdvwIqhb1Xgo29U4KRvVuCqb1ngsW9ik7NvU+C1b+3tuW9X4MBvg4zBb/eRwm9R4MNvWpTGb1jg1G9d4NVvW+DYb17g229h4N9vWuDgb4qN4W9HlORvt5/rb5SX7G9c4O5vYODvb/OR8W9f4PNvSuD1b+7t9m+J6PpvZOD+b2jgAXBm4AVw7+0HcPDtCXBi4AtwY+APcGfgEXBl4BVwbZUYcG3gGnBq4BtwaeAdcGzgHnDSkx9wbuAmcJWSJ3DrkShw8e0scKOQMHBv4DJwceA+cHDgTHDzn1FwcuBYcOWTY3Bz4GtwzolvcJSTcHBEinhwhIt8cNyOfXDQjYVw8u2JcEaYinCGkI5wiomScHXgmXB04Ktw8+2scHjgrXBZkq5we+CvcHbgs3B64LhweeC5cF+TunDXiLtwRu3IcPOXy3B94M9wR4nZcIDg3XB+4N9wfODxcHfg+XBClv1wguAEcfXtCXGB4A9x9O0UcYuJGXGE4BpxsJUccYPgIXGzliZxxY82cVKRPHHEj0Zx9+1HcfjtSXH5l0xxiuBOcfeQVXGG4FZxi+BZcYyJXHH27WJxieBkcYGUZXGF4GZxiOBnccaPaXHPlGxxjOBucc+OfXH4kIRxj+CIcYfginFGjI9xjeCUcW+XlXGQ4JlxpOqfcW6PqHGR4KxxkuCxcU2UuXGU4L5xleDBcfrtw3FSlMhxlZPJcZfgznGZ4NBx05fScZbg1HGY4NVxjYnXcZPg33F6muBxmuDlcYeR5nFXjudxnODscZvg7XFDkO5x15n1cZ3g+XGf4PtxjuD8cZ7g/nH77f9xoOAGcpqUDXKh4BByouAbcqPgKHKk4Cpy3JIscqbgLXKl4DByp+AycqjgNXLdjjZyg5U6cuqWO3Kp4DxyquA9cnWRPnKijj9yq+BAcqzgRnKt4Edy0JVIcsWUS3Ku4ExydpRScquSWHKv4Fly5Ylbco2LXXLEll9ytJZhcrKJYnJTmGdycZZpcqiVcnK1kHRysOB5csGTfXKhjH5yseCActKNgXKz4IJysuCHcrTgknK14JZytuCgcl2LonK34KdyuOCscqKMr3LGlLFy/O2ycrrgtnLzj7lyueC+ckDuwnK2i8Nyu+DEcr3gxnK84M5yvuDQcs+M0nK/4Ndy54vZcl+R23KdjeByweDhcsLg4nLA4Oly647scsaT7XK3i/dyxOD4ckuS+XLD4PxyVJj9coKUCnPH4BZzyeAXc8bgG3PSlhxzyOAdc8rgH3PClyRzQe4lc87gKXPN4CpzlpIrc0yULnOjjC9zzOA0c8vgNnNQlzdzUZc+c8/gP3OOiURzlo1Fc4KOTnPQ4E9z0eBXc9PgY3Nij2hz1eBqc9TgcHPW4HJzbIp1c9jgd3ND7nhz1+B6c9rge3PZ4IRzuoyHc6aXiXPKi4tzpImWc+iLqXPfirJz5pezc9zgu3Pe4L1zRO7Ac9/gwnPPichz2+DJc0XuynNYjs1zv5LOc93g0nNI7tZzRu7ec+Lg4HPsjuNzR+7lc+Dg6nNdjO1zx5Tuc+Hg8XP84PVzSu74c+fg/nO7jAN0hYsFdOTgBnSdlwd0Se4JdK6XInT0kSV05uAmdEvuKXRN7ip0TO4udE7uMnTo4DN01Jc0dNWLNXT6lDZ0aZQ6dOngP3Tr4EF07uBVdOrgWXTt4Fp06IxbdGyJXHTv4F50kJBfdOzgYHTal2J0T+5jdPLgZHSi6ml08OBqdPPgb3Tl4HB08eBzdLqNdnT04H509eCDdJ6XiXRQ7ot09uCedPfgn3RR7qJ04+CndPjgsHTCir10o47KdPngz3T64NR0++DcdFqJ4HRA4eJ0WpXjdEHh5nSiiud0QuHpdEPh7nRE4fB0RuHxdEfh8nRF4fZ0cpX3dEnh+HRI4QF1Uu4DdUvhBHVK4QV1TOEMdU3hDXVP4Q51TuERdZmNE3VR4RV1UOEYdcOKGnVykBx1W5MedVLhH3W2kCN1WY4ldZmJJnVT4Sh1cJcrdeGVLHVU4S91jO0wdWOTMXVSlzJ1Yo0zdVyQN3Vqkjh1spk6daySO3XmiTx1VeFEdVbhRnVb4Ul1WeFKdVjhS3XAnUx1RYpNdVfhT3XYiFF1qJRUdciUWXWvl1p1XOFbdVrhXHV7kl11pJBgdamUYnVMlWR1XuFldaqXZnVsjGd1X+FpdV3hanXUlGt1YOFtdWHhb3VT7nB12YhzdfSPdHVm4XZ1Y+F3deuTeHVi4X91RYuCdWnhhnVk4Yd1ZeGJdWjhinVn4Yt1RJWOdWGRj3VgkZF1XouUdWrhmnVr4Z11bOGjdW7hpXVt4at1dYmxdXbhsnXmlLN1cOG1dXLhuHV04bl1XZC8dXXhvXVz4b51vo7CdW/hw3Vx4cV1YZXHdcePynV44c11d+HSdXnh1HWkjtV1rY3YdZeT2XV64dt1yZLedXzh4nWfl+N1e+HpdYmR8HWC4fJ1hOHzdYXh9HVzkvp1g+H8dYDh/nV94f91fuEBdoHhCXaI4Qt2huENdofhH3aJ4SB2i+EhdozhInaN4SR2juEndorhMHaQ4TR2j+E7dpHhQnbDl0Z2lOFHdpLhSHaT4Ux24IpSdvyWVnbIlVh2luFcdpXhYXaX4WJ2mOFndpzhaHaZ4Wl2muFqdpvhbHad4XB2nuFydp/hdnag4Xh2oeF6dq2Ue3Zvk3x2ouF9dpKUfnZTlYB2o+GCdlTug3ak4YR2SZOGdkaKh3ZjjYh2peGLdqbhjnan4ZB2SI6Tdqnhlnao4Zl2quGadqvhm3ZX7px2Ve6edlbupnZY7q5255SwdqzhtHat4bd2ieq4dq7huXav4bp2sOG/dk2Ownax4cN2dZTGdn6WyHZticp2donNdrLh0na04dZ2s+HXdpCT23a3kNx2WJ/edrXh33a/luF2tuHjdsSK5HbVlOV2t+Hndrjh6na54e522pbydtOW9Ha8kvh2ipH7drvh/naCjwF3yI8Ed77hB3e94Qh3vOEJd/uUC3fFigx3p4wbd8ThHnfB4R93XpAgd7CWJHfA4SV3wuEmd8PhKXe/4Td3xeE4d8bhOnetkjx34YpAd4WSRnda7kd3x+Fad8jhW3fL4WF3h5Bjd8KTZXfM4WZ3cpZod8nha3fK4Xl3z+F+d87hf3fN4Yt30eGOd9DhkXfS4Z531OGgd9PhpXfLlax3dY+td8SXsHfV4bN3tZO2d9bhuXfX4bt32+G8d9nhvXfa4b932OHHd9zhzXfd4dd33uHad9/h23e1ltx34OHid+6W43fh4eV3bZLnd4qU6Xfpi+13WpLud+Lh73e4i/N3zpD8d+PhAni7jQx45OESeOXhFHikjBV4040geOfhIXhc7iV4dZMmeNSNJ3htizJ4Q5Y0eGqUOnh2kz94e41FeOnhTnhd7l14yY9keF7ua3iwl2x4ZI1veKWMcnihlHR46+F6eF/ufHjt4YF46YyGeOzhh3j0kox47+GNeFaKjnjq4ZF46JSTeE+JlXjqjZd4cZiaeO7ho3jw4ad4yZWpeNeQqnjy4a948+G1ePHhunhtirx4+eG+ePjhwXiljsV4+uHGePXhynj74ct49uHQeNaU0Xj04dR49+HaeEHi53hA4uh4gZbsePzh73jpiPR4Q+L9eELiAXnKjwd5ROIOeWKREXlG4hJ5ReIZeUfiJnnm4Sp56OEreUniLHlI4jB5YO46eaaOPHnnlz550I5AeUriQXlWjEd5X4tIeUaLSXmDjlB5U5dTeVDiVXlP4lZ5Y5FXeUziWnlO4l15ao9eeV+QX3lN4mB5S+JieUmUZXnLj2h5W5VtedWNd3mYk3p5UeJ/eVLigHlo4oF51ouEeVyYhXlUkYp5U+KNedCJjnn1ko95n5WUeWTum3lm7p15VOKmeZqLp3lV4qp5V+KueVjisHlIlLN5WeK5eVriunlb4r1514u+edGJv3nDk8B5R4/BeYSOyXlc4st5SI/ReciJ0nlildV5XeLYeemU33lkkeF5YOLjeWHi5HmJlOZ5YJDneV7i6XmBkux5X+LwecyP+3naiAB6SIsIemLiC3r2kg16Y+IOesWQFHqrlhd6QpUYemTiGXpl4hp6dJIcesWXH3pn4iB6ZuIueu2OMXpp4jJ67og3emziO3pq4jx60ok9em2MPnpr4j96ZY1AepKNQnrklUN6beJGenOWSXpv4k16z5BOem6JT3q4iVB6qohXem7iYXpw4mJ6ceJjevWPaXpy4mt6bopwenTidHqKjHZ6hot5enXienrzi316duJ/evqQgXrLk4N63pCEevONiHp34pJ6gpKTeouRlXp54pZ6e+KXenjimHp64p96QYypenziqnpFjK56h4uvenGXsHp+4rZ6gOK6ek2Jv3qD4sN6lorEeoLixXqB4sd6heLIen3iynqG4st6p5fNeofiz3qI4tF6Z+7SevKa03qK4tV6ieLZeovi2nqM4tx6s5fdeo3i33rt6OB6zY/heo7i4nqP4uN6do/leraT5nqQ4ud6aO7qekeS63pq7u16keLveluS8HqS4vZ6o4v4el6Z+Xp8kvp6sY7/esaKAnuT4gR7oOIGe5biCHuIiwp7leILe6LiD3uU4hF7zo8Ye5jiGXuZ4ht7SpMee5riIHt9iiV7eZAme4SVKHuc4ix75pEze5fiNXub4jZ7neI5e/mNRXuk4kZ7TZVIe6SUSXuZk0t72ItMe6PiTXuh4k97s5RQe57iUXt9klJ7m5NUe5qTVnv0jV17tuJle6biZ3uo4mx7q+Jue6zicHup4nF7quJ0e6fidXul4np7n+KGe82Vh3vTiYt7s+KNe7Dij3u14pJ7tOKUe5OUlXullpd7Wo6Ye67imXu34pp7suKce7HinXut4p57a+6fe6/ioXvHiqp7XJKte/uQsXuglLR7vOK4e6KUwHvfkMF7ueLEe82Uxnu94sd70ZXJe3qSy3u44sx7uuLPe7vi3Xu+4uB7wo7ke8ST5XvD4uZ7wuLpe7/i7XtVmPN7yOL2e8zi93vJ4gB8xeIHfMbiDXzL4hF8wOISfNOZE3zH4hR8weIXfMriH3zQ4iF8yIojfM3iJ3zO4ip8z+IrfNLiN3zR4jh89JQ9fNPiPnz6lz9865VAfNjiQ3zV4kx81OJNfNCQT3zX4lB82eJUfNbiVnzd4lh82uJffNviYHzE4mR83OJlfN7ibHzf4nN8xJV1fODifnzgloF8zIuCfEiMg3zh4ol8spWLfIiQjXyulpB84uKSfLGXlXyUlJd8ZZGYfFOUm3xsj598voihfOfionzl4qR84+KlfJ+Kp3zPj6h86OKrfObirXzk4q587OKxfOvisnzq4rN86eK5fO3ivXzu4r58uJDAfO/iwnzx4sV88OLKfNCMznxXkdJ88+LWfJyT2Hzy4tx89OLefLOV33yMkeB8Zo3ifPXi53zGl+989+LyfPji9Hz54vZ8+uL4fIWO+nz74vt8boz+fIqLAH1JiwJ9QOMEffGWBX1njQZ9/OIKfUPjC33klg19W5QQfVKVFH2DjxV9QuMXfdGOGH1ojRl9ho4afYmLG320lRx9QeMgfWaRIX1hliJ99Y0rfYeOLH3bki59RuMvfd2XMH3XjTJ9R+MzfWGQNX1J4zl90I86fa6NP31I40J9SY9DfbyMRH1nkUV9RONGfUrjSH1t7kt9ReNMfW+MTn1N4099UeNQfYuMVn1M41t9VeNcfW7uXn1pjWF9jZdifbqIY31S42Z9i4tofU/jbn1Q43F9nZNyfU7jc31L43V9R4p2feKQeX2mjH19V+OJfVTjj31W45N9U+OZfXCMmn2xkZt9WOOcfY6Rn31l46B9cO6ifWHjo31b46t9X+OsffiOrX3biK59WuOvfWLjsH1m47F9ao2yfdSWtH3UkrV9XOO3fW/uuH1k47p9WeO7fV2SvX1e4759u4i/fciWx31d48p92YvLfeqUz32NkdF9zpfSfY+P1X2O49Z9ce7YfWfj2n38kNx9Y+PdfWjj3n1q4+B995LhfW3j5H1p4+h90pXpfcmK7H3Jlu993IjyfWzj9H37l/t9a+MBfo+JBH7qkwV+buMJfnXjCn5v4wt+duMSfnLjG36blB5+yI4ffnTjIX5x4yJ+d+MjfnDjJn5jjyt+RJYufmuPMX5z4zJ+gOM1fnvjN35+4zl+fOM6foHjO3564z1+YOM+ftGQQX7JlEN+feNGfnjjSn5AkUt+cYxNfkqPUn5y7lR+RJBVflWRVn6E41l+huNafofjXX6D415+heNmfnnjZ36C42l+iuNqfonjbX6alnB+Sox5fojje36M43x+i+N9fo/jf36R44J+W46Dfo3jiH6S44l+k+OKfkDtjH6U445+muOPflqTkH6W45J+leOTfpfjlH6Y45Z+meObfpvjnH6c4zZ/yoo4f53jOn+e40V/n+NHf3PuTH+g401/oeNOf6LjUH+j41F/pONUf6bjVX+l41h/p+Nff6jjYH+p42d/rONof6rjaX+r42p/341rf3KMbn91knB/sZRyf5CPdX9slHd/65R4f63jeX/rnIJ/ruODf7DjhX+Fl4Z/r+OHf7LjiH+x44p/cpeMf7Pjjn/8lJR/tOOaf7fjnX+2455/teOhf3Tuo3+446R/UYyof0GRqX9gi65/vOOvf7njsn+647Z/veO4f77juX+7471/SInBf6WJxX/A48Z/wePKf8LjzH+Cl9J/S4/Uf8Tj1X/D4+B/iZDhf8Xj5n/G4+l/x+Prf+OK8H/LivN/yOP5f8nj+398lvx/g5cAgHOXAYBWmAOAbI0EgMzjBYDSjgaAy+MLgM3jDICnjhCAz5ESgM7jFYBrjReA1ZYYgM/jGYDQ4xyA0eMhgNLjKIDT4zOAqI42gOuWO4DV4z2AXpI/gNTjRoDX40qA1uNSgNjjVoC5kFiA2eNagNrjXoC3lV+A2+NhgI+RYoDc42iA3eNvgPyXcIDg43KA3+NzgN7jdICuknaA4eN3gEWQeYDi432A4+N+gFeYf4Dk44SA5eOFgOfjhoDm44eAo5SJgPeTi4BdmIyAp5STgOnjloDRj5iASZWagOrjm4Do452AzIqhgNKMooCIjqWA7JSpgKiMqoBilqyA7eOtgOvjr4BtjbGAbo2ygOeItIDmjbqAeJTDgN2IxIDy48aAX5LMgHeUzoDZkdaA9OPZgPDj2oDz49uA7uPdgPHj3oBFluGA04zkgPuI5YDv4++A9uPxgPfj9IC3k/iAuYv8gEXk/YBclAKBiY4FgbqLBoHGkAeBZZgIgayWCYH14wqB0pAagXKLG4H44yOB+uMpgfnjL4H74zGBRZIzgV2UOYGvkj6BQuRGgUHkS4H8406BdJBQgYWVUYFE5FOBQ+RUgW+NVYFymF+BVORlgUjkZoFJ5GuB7o5ugUfkcIGYjXGBRuR0gUrkeIGwknmBoJV6gUKRf4HakYCBTuSCgU/kg4FL5IiBTOSKgU3kj4FwjZOBVeSVgVHkmoGGlZyBjJadgUeVoIFQ5KOBU+SkgVLkqIFjlqmBVuSwgVfks4FWkbWBWOS4gVrkuoFe5L2BW+S+gVnkv4FelMCBXOTCgV3kxoGwiciBZOTJgV/kzYFg5NGBYeTTgZ+R2IFj5NmBYuTagWXk34Fm5OCBZ+TjgWKQ5YHnieeBaOTogdWX6oGpju2BTI/zgYqO9IF2kvqBaeT7gWrk/IFQif6Ba+QBgmzkAoJt5AWCbuQHgm/kCIK7iwmCqJ0KgnDkDILjkA2CceQOgsmOEIJy5BKCrpgWgnPkF4LclRiC2oobgkORHIJ3jx6CkZUfgk2PKYJ05CqCcY0rgnXkLILKlC6ChOQzgnfkNYLHkTaClZQ3gr2MOIJ25DmCRJFAgnjkR4L4kliCeuRZgnnkWoJ85F2Ce+Rfgn3kYoKA5GSCfuRmgs2KaIKB5GqCguRrgoPkboKvjW+Cx5dxgoXkcoJGkHaCkIl3gobkeIKH5H6CiOSLgvCIjYKJ5JKCiuSZgoeVnYLFjp+CjOSlgkiKpoKwiKuCi+Ssgo7krYJtlK+CY5CxgtSJs4JGlriCfIy5gtqLu4KN5L2C6InFgqGK0YKRidKCkuTTguiX1ILbkdeCY5XZgp7k24LVidyCnOTegprk34KR5OGCj+TjgpDk5YLhjuaC6ovngpeS64LPk/GCcInzgpTk9IKT5PmCmeT6gpXk+4KY5AGDdu4Cg86WA4OX5ASD1okFg52KBoOb5AmDneQOg3OMFoOh5BeDquQYg6vkHIOpiCODsuQog++IK4Op5C+DqOQxg6PkMoOi5DSDoOQ1g5/kNoODkjiD+ZE5g6XkQIOk5EWDp+RJg5CRSoN0jE+DYIlQg6bkUoNyjViDkZFig3fuc4O45HWDueR3g9eJe4OsiXyDtuR/g3juhYOs5IeDtOSJg7vkioO15I6Ds+STg5bkloOx5JqDreSeg86Kn4Ov5KCDuuSig7DkqIO85KqDruSrg5yUsYOJl7WDt+S9g83kwYPF5MWDm5DHg3nuyoNli8yD24vOg8Dk04PZidaD0o/Yg8Pk3IPYjd+DcJPgg8jk6YPsleuDv+Tvg9iJ8IPUjPGDSJXyg8nk9IO95PaDeu73g8bk+4PQ5P2DweQDhMLkBIS4kweEx+QLhMTkDIRHlg2EyuQOhN6IE4S+5CCEzOQihMvkKYSLlCqE0uQshN3kMYSeijWE4OQ4hM7kPITT5D2EjpdGhNzkSIR77kmEdJdOhKiXV4SYkluEi4phhJKVYoTi5GOEn5NmhK+IaYTb5GuE1+RshJKRbYTR5G6E2eRvhN7kcYRLlHWEqIh3hNbkeYTf5HqEmJWChNrkhITV5IuE04+QhE6PlISqjpmE1pachGaVn4Tl5KGE7uSthNjksoSXirSEfO64hPaPuYTj5LuE6OS8hJORv4Tk5MGE6+TEhH6SxoTs5MmEdZfKhOHky4RXis2E5+TQhOrk0YSqltaE7eTZhObk2oTp5NyERO3shEiW7oRAmPSE8eT8hPjk/4Tw5ACFwY4Ghc/kEYXMlROFoJYUhffkFYX25BeF8uQYhfPkGoVViR+F9eQhhe/kJoXTkiyF9OQthfyINYWgkT2FwZVAhfnkQYVA5UOF15RIhfzkSYXUj0qFx45LhULlToW8i1OFfe5VhUPlV4WZlViF++RZhX7uWoXU5GOF+uRohW6YaYWgk2qFk5VrhYDubYVK5XeFUOV+hVHlgIVE5YSFlpSHhU7liIVG5YqFSOWQhVLlkYVH5ZSFS+WXhZKJmYXjk5uFTOWchU/lpIVF5aaFRZGohUnlqYVGjqqFZJCrhU+MrIXylq6F95avhZKPsIWC7rmFVuW6hVTlwYVtmMmFU+XNhZWXz4VV5dCFV+XVhVjl3IVb5d2FWeXkhaGT5YVa5emFy5TqhU3l94WTj/mFXOX6hWHl+4WUkf6FYOUChkHlBoZi5QeGaJEKhl3lC4Zf5ROGXuUWhlCfF4ZBnxqGZOUihmPlLYaWly+GuuEwhmXlP4Zm5U2GZ+VOhtWMUIZzi1SGaeVVhnyZWoaVi1yGuJdehvGLX4Zq5WeGa+Vrho6ScYZs5XmG+JN7hriIiobhiYuGceWMhnLlk4Zt5ZWGXI6jhm7lpIZhlKmGb+WqhnDlq4Z65a+GdOWwhnfltoZz5cSGdeXGhnblx4bWjsmGeOXLhmCSzYZ1jM6GYYrUhnvl2YZeituGgeXehnzl34aA5eSGuJTphn3l7IZ+5e2GZ5XuhtiU74aC5fiG+5H5hozl+4aI5f6G6YkAh4blAodJlgOHh+UGh4TlCIeF5QmHiuUKh43lDYeL5RGHieUSh4PlGId3khqHlOUch6iWJYeS5SmHk+U0h47lN4eQ5TuHkeU/h4/lSYfkkEuHWJhMh5jlToeZ5VOHn+VVh0mQV4eb5VmHnuVfh5blYIeV5WOHoOVmh9qJaIec5WqHoeVuh53ldIea5XaHsZJ4h5flf4eIlIKHpeWNh1qXn4ek5aKHo+Wrh6zlr4em5bOHruW6h4aXu4ex5b2HqOXAh6nlxIet5caHsOXHh6/ly4en5dCHquXSh7vl4Ie05e+HsuXyh7Pl9oe45feHueX5h0mK+4dhi/6Ht+UFiKLlB4iF7g2ItuUOiLrlD4i15RGIvOUViL7lFoi95SGIwOUiiL/lI4h55SeIxOUxiMHlNojC5TmIw+U7iMXlQIiMjEKIx+VEiMblRohPj0yIc41NiKWfUojI5VOIcI9XiFiKWYjJ5VuIcYldiNWPXojK5WGIdI1iiMvlY4jfiGiIXJVriMzlcIiKkHKI0+V1iNDld4iPkn2I0eV+iM7lf4jci4GIzeWCiNTliIhVjIuI3JGNiNrlkojW5ZaIs5GXiNXlmYjY5Z6Iz+WiiNnlpIjb5auI7ZSuiNflsIjc5bGI3uW0iNGMtYjS5beIv4i/iN3lwYjZjcKI9JfDiN/lxIjg5cWIlZHPiKCX1Ijh5dWIVJfYiOLl2Yjj5dyI4pXdiOTl34i+jeGIoZfoiOnl8ojq5fOI1o/0iOjl9YiG7viIh5f5iOXl/Ijn5f2Iu5D+iJ6QAonm5QSJ6+UHiaGVCont5QyJ7OUQiYyKEolKlhOJ7uUciUHtHYn65R6J8OUlifHlKony5SuJ8+U2ifflOIn45TuJ9uVBifTlQ4nv5USJ9eVMifnlTYm16FaJpoleifzlX4ndi2CJ++VkiUHmZolA5mqJQ+ZtiULmb4lE5nKJUI90iUXmd4lG5n6JR+Z/ibyQgYl2l4OJSOaGiaKVh4lllIiJSeaKiUrmi4mpjI+JS4uTiUvmlomLjpeJYJSYiUzmmolviqGJTeamiU/mp4mXl6mJTuaqiWWQrIlQ5q+JUeayiVLms4nPirqJU+a9iVTmv4lV5sCJVubSiXCK2olX5tyJWObdiVnm44nwieaJR5DniVrm9Ilb5viJXOYAir6MAor5kgOKXeYIinaMCop1kAyKYOYOiqKTEIpf5hKKh+4TilCMFope5heK9ZEYikyLG4ph5h2KYuYfitePI4qNjCWKY+YqikuWLYrdkDGKloszivOWNIppkTaKZOY3iojuOopmkDuKkJI8itiPQYpl5kaKaOZIimnmUIq8jVGKwJFSimfmVIrZj1WKXZVbimbmXoqMjmCKcoliim3mY4p3jGaKjo5pio2Oa4psmGyKbOZtimvmbopGkXCKbItximKYcopZinOK2o95ionufIpq5oKKb+aEinDmhYpu5oeK1oyJil+XjIqPjo2KRpSRinPmk4q+kJWKYZKYilWXmop25p6K6oygir2QoYpy5qOKd+akiuuMpYp05qaKdeanioruqIpx5qyK4JCtiseTsIpOkrKK24m5iu6UvIpii76Ki+6/irKSwop65sSKeObHimuSy4q/kMyK0IrNinnmz4p6kNKKyJfWil+Y2op75tuKh+bcirOS3oqG5t+KjO7gioPm4YqL5uKKhObkioDm5or6kueKfubrinzm7YpAl+6KkI7xioHm84p95vaKju73ioXm+IqUj/qKv4z+iviRAItklgGLeYkCi+CIBIujkweLieYMi4jmDovkkxCLjeYUi4LmFouM5heLjuYZi6qMGouK5huLdY0di9OOIIuP5iGLd5cmi5LmKIuV5iuLk+Ysi1SVM4uQ5jmL3os+i5TmQYuW5kmLmuZMi5fmTouZ5k+LmOZTi4/uVoub5liLr45ai53mW4uc5lyLiJVfi5/mZot4jGuLnuZsi6Dmb4uh5nCLY4txi7/jcov3j3SLouZ3i+yMfYuj5n+LkO6Ai6Tmg4tdjoqLzJ2Mi6Xmjoum5pCLUY+Si6fmk4uo5paLqeaZi6rmmour5jeMSpI6jKzmP4yu5kGMreZGjKSTSIyv5kqMTJZMjLDmToyx5lCMsuZVjLPmWozYk2GM249ijLTmaoyLjWuMrJhsjLXmeIy25nmMXpV6jLfmfIy/5oKMuOaFjLrmiYy55oqMu+aMjGWWjYy85o6MveaUjL7mmIzA5p2MTIqejOWSoIyJlaGM4I2ijHaNp4xulaiM3YmpjMyUqozD5quM0YqsjNOQrYzC5q6Mx+avjJmSsIzhlrKMxeazjMbmtIxNi7aMyOa3jIOUuIzdkbuM75S8jFyTvYzE5r+MZpbAjOqJwYzK5sKMR5jDjMCSxIxkmMeMkY7IjMnmyoyvkc2M2ubOjEeR0Yz2k9OMb5XajM3m24xejtyMko7ejNyP4IyFlOKMq4zjjMzm5IzL5uaMipXqjL+O7Yxxk/CMke70jJLu+ozP5vuM0Ob8jHeN/YzO5gSN0eYFjdLmB43U5giNoZEKjdPmC43kig2N1uYPjdXmEI3X5hKNk+4TjdnmFI3b5haN3OZkjdSQZo3NjmeN3eZrjXGKbY3e5nCNlpFxjd/mc43g5nSNi5V2jZTud41Oi4GN4eaFjbSSio16iZmN4uajje+OqI2WkLONq5G6jeXmvo3k5sKN4+bLjevmzI3p5s+N5ubWjejm2o3n5tuN6ubdjZeL343u5uGN1ZDjje/m6I3XjOqN7Obrje3m741ImPONtZL1jUiR/I3w5v+N8+YIjvHmCY7y5gqOeJcPjqWTEI725h2O9OYejvXmH4735iqOSOcwjvrmNI775jWO+eZCjvjmRI77kkeOQOdIjkTnSY5B50qO/OZMjkLnUI5D51WOSudZjkXnX47WkGCOR+djjknnZI5G53KOTOd0jlKPdo5L53yOTeeBjk7nhI5R54WOUOeHjk/nio5T54uOUueNjvSWkY5V55OOVOeUjlbnmY5X56GOWeeqjljnq45nkKyOWuevjuuLsI5b57GOXee+jl7nxY5f58aOXOfIjmDnyo7UjsuOYefMjk+LzY5SjM+Olu7SjqyM245i59+O7pPijl2T445j5+uOZuf4jrKO+45l5/yOZOf9jnmM/o5n5wOPcooFj2nnCY/ajQqPaOcMj3HnEo9r5xOPbecUj+OVFY9q5xmPbOcbj3DnHI9u5x2PUIsfj2/nJo9y5ymPeZQqj9aXL49TjzOPc+c4j0GXOY915zuPdOc+j3jnP49gl0KPd+dEj42KRY9250aPe+dJj3rnTI95502PUZNOj3znV49951yPfudfj4yNYY9EjGKPgOdjj4HnZI+C55uPaJCcj4Pnno+rjp+PhOejj4Xnp4+fmaiPnpmtj4bnro+Q46+Ph+ewj0OSsY9KkLKPX5S3j4jnuo/TlbuP0pK8j56Nv49IksKPSYnEj5iWxY92kM6PfYzRj9+L1I/UldqPiefij4vn5Y+K5+aP3onpj/ST6o+M5+uPl5Ttj1KT74+N5/CPcY/0j4/n94/AlviPnuf5j5Hn+o+S5/2Px5IAkN6RAZCXkQOQppMFkJDnBpB0iwuQmecNkJbnDpCj5w+Qp5MQkICSEZCT5xOQ/JIUkHKTFZCU5xaQmOcXkICQGZCHlBqQypIdkMCQHpCX5x+QrJEgkKKRIZCV5yKQp4gjkEGYJ5Ca5y6Q35ExkFSPMpBpkDWQnOc2kJvnOJDtiDmQnec8kE6VPpCl50GQ2ZNCkIuQRZB4kkeQ9otJkKTnSpBWl0uQXolNkNWVTpDfiU+Qn+dQkKDnUZCh51KQoudTkLmTVJBCklWQ4YhWkKbnWJCn51mQoepckLuRXpCo52CQk4lhkGuRY5CtjGWQeZdnkJnuaJCp52mQS5NtkJiRbpDVjm+QqudykK3ndZCFj3aQq+d3kEqReJBJkXqQ4oh8kMmXfZCv53+Q8JSAkLHngZCw54KQrueDkITihJDSioeQjueJkLPnipCy54+QtOeRkFeXo5Dfk6aQTZaokLXnqpDXjq+QtuexkLfntZC457iQQJPBkOiIypB4jc6QWZjbkLzn3pCa7uGQU4zikLnn5JC65+iQlJXtkHOK9ZBYl/eQvYv9kHOTApG95xKRvucVkZzuGZG/5yeRne4tkUGTMJHB5zKRwOdJkdGTSpHC50uRVY9Mkd6OTZF6lE6RkZJSkfCOVJGMkFaRw+dYkcTnYpF8kGORxedlkcbnaZHH52qRj5dskVaPcpHJ53ORyOd1kXmNd5GTjXiRX46Ckcznh5GGj4mRy+eLkcrnjZHnkZCR7YySkcGQl5GulJyRWI+ikc3npJHdj6qR0Oerkc7nr5HP57SR0ue1kdHnuJH4j7qR0+fAkdTnwZHV58aRzpTHkdGNyJHfjsmR1ufLkdfnzJGil82RZI/OkeyWz5HKl9CR2OfRkeCL1pHZ59eRn+7YkUKT2pGe7tuR3OfckZiK3ZFqkN6RoO7fkdrn4ZHb5+OR3pLkkaPu5ZGk7uaRdJbnkfqL7ZGh7u6Rou71kd7n9pHf5/yR3ef/keHnBpKl7gqSp+4Nkt2TDpJiihCSpu4RkuXnFJLi5xWS5OcekuDnKZJu6CyS4+c0kumXN5LYjDmSru46kqjuPJKq7j+S7edAkqnuRJJTk0WS6OdIkuvnSZLp50uS7udOkqvuUJLv51GSre5XkufnWZKs7lqS9OdbkpSJXpLm52KSq5RkkurnZpLej2eSr+5xknqNd5Kx7niSsu5+kmeWgJLii4OSZY+FkrqTiJJD7ZGSTJGTkvLnlZLs55aS8eeYksGWmpK2kpuS8+eckvDnp5Kw7q2SS5G3kvfnuZL258+S9efQkrbu0pJOltOSuu7Vkrju15K07tmSte7gkrnu5JKbj+eSs+7pkvjn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vJlo6cGZnZTEmcqRxZl3icaZ7IvIme2L0JmTktGZbenSme6L1ZntidiZbOnbmWrp3Zlr6d+ZaenimXfp7Zlu6e6Zb+nxmXDp8plx6fiZc+n7mXLp/5l4jwGadOkFmnbpDppSiw+adekSmpuRE5qxjBmaeOkomsuRK5p56TCaq5M3mnrpPpqA6UCafelCmnzpQ5p+6UWae+lNmoLpTprf7lWagelXmoTpWprBi1uag+lfmoXpYpqG6WSaiOllmofpaZqJ6Wqai+lrmorpqJqcja2ajOmwmo3puJpbiryajunAmo/pxJqRkM+akOnRmpHp05qS6dSak+nYmoKN2Zrg7tya4e7empTp35qV6eKalunjmpfp5pqY6eqar5Trmprp7ZpFle6am+nvmpnp8Zqd6fSanOn3mp7p+5qf6QaboOkYm6HpGpui6R+bo+kim6TpI5ul6SWbpuknm6fpKJuo6Smbqekqm6rpLpur6S+brOkxm1SfMput6Tub9uI8m1OLQZtAikKbsI1Dm6/pRJuu6UWbo5ZNm7HpTpuy6U+bsOlRm7PpVJuCllibtOlam5uLb5tEmHKb4+50m7XpdZvi7oObt+mOm7yIj5vk7pGbuOmSm6mVk5u26ZabuemXm7rpn5u76aCbvOmom73pqpuOlqubTI6tm/iNrptOkbGb5e60m77puZvB6bub5u7Am7/pxpvC6cmb74zKm8Dpz5vD6dGbxOnSm8Xp1JvJ6dabSY7bm+KR4ZvK6eKbx+njm8bp5JvI6eibfozwm87p8ZvN6fKbzOn1m7GIAJzn7gSc2OkGnNTpCJzV6Qmc0ekKnNfpDJzT6Q2cgooQnGuYEpzW6ROc0ukUnNDpFZzP6Ruc2ukhnN3pJJzc6SWc2+ktnGiVLpzZ6S+c8YgwnN7pMpzg6Tmcj4o6nMvpO5xWiT6c4ulGnOHpR5zf6UicTJJSnJCWV5zYl1qc4+lgnOTpZ5zl6Xac5ul4nOfp5Zy5kuec6OnpnLWU65zt6eyc6enwnOrp85xQlvScwpb2nM6TA53u6Qad7+kHnbyTCJ3s6Qmd6+kOnaiJEp336RWd9ukbnZWJH5306SOd8+kmnfHpKJ2biiqd8OkrnbCOLJ2niTudg40+nfrpP5356UGd+OlEnfXpRp376Uid/OlQnUTqUZ1D6lmdRepcnUyJXZ1A6l6dQepgnZSNYZ23lmSdQuprnenubJ1Rlm+dSupwnejucp1G6nqdS+qHnUjqiZ1H6o+de4yanUzqpJ1N6qmdTuqrnUnqr53y6bKdT+q0nd+SuJ1T6rqdVOq7nVLqwZ1R6sKdV+rEnVDqxp1V6s+dVurTnVnq2Z1Y6uadW+rtnVzq751d6vKdaJj4nVrq+Z3pkfqd6439nV7qGZ7r7hqeX+obnmDqHp5h6nWeYup4nrKMeZ5j6n2eZOp/nq2OgZ5l6oieZuqLnmfqjJ5o6pGea+qSnmnqk55bmJWeauqXnu2XnZ5s6p+e2Zelnm3qpp6elKmebuqqnnDqrZ5x6rieb+q5no2Nup7Llrueg5a8nvWbvp6An7+em5bEnqmJzJ5z6s2eb4vOnnTqz5516tCedurRnuzu0p6VjdSed+rYntLg2Z7Zltue4ZHcnnjq3Z566t6eeergnnvq5Z586uiefervnn7q9J6A6vaeger3noLq+Z6D6vuehOr8noXq/Z6G6gefh+oIn4jqDp9DkxOf24wVn4rqIJ9skSGfi+osn4zqO59AlT6fjepKn47qS59W4k6f2OZPn+voUp+P6lSfkOpfn5LqYJ+T6mGflOpin+6XY5+R6maflepnn5bqap+Y6myfl+pyn5rqdp+b6nefmeqNn7SXlZ+c6pyfneqdn3PioJ+e6gDgQPAB4EHwAuBC8APgQ/AE4ETwBeBF8AbgRvAH4EfwCOBI8AngSfAK4ErwC+BL8AzgTPAN4E3wDuBO8A/gT/AQ4FDwEeBR8BLgUvAT4FPwFOBU8BXgVfAW4FbwF+BX8BjgWPAZ4FnwGuBa8BvgW/Ac4FzwHeBd8B7gXvAf4F/wIOBg8CHgYfAi4GLwI+Bj8CTgZPAl4GXwJuBm8CfgZ/Ao4GjwKeBp8CrgavAr4GvwLOBs8C3gbfAu4G7wL+Bv8DDgcPAx4HHwMuBy8DPgc/A04HTwNeB18DbgdvA34HfwOOB48DngefA64HrwO+B78DzgfPA94H3wPuB+8D/ggPBA4IHwQeCC8ELgg/BD4ITwROCF8EXghvBG4IfwR+CI8EjgifBJ4IrwSuCL8EvgjPBM4I3wTeCO8E7gj/BP4JDwUOCR8FHgkvBS4JPwU+CU8FTglfBV4JbwVuCX8FfgmPBY4JnwWeCa8Frgm/Bb4JzwXOCd8F3gnvBe4J/wX+Cg8GDgofBh4KLwYuCj8GPgpPBk4KXwZeCm8Gbgp/Bn4KjwaOCp8GngqvBq4Kvwa+Cs8GzgrfBt4K7wbuCv8G/gsPBw4LHwceCy8HLgs/Bz4LTwdOC18HXgtvB24Lfwd+C48HjgufB54LrweuC78HvgvPB84L3wfeC+8H7gv/B/4MDwgODB8IHgwvCC4MPwg+DE8ITgxfCF4MbwhuDH8IfgyPCI4MnwieDK8Irgy/CL4MzwjODN8I3gzvCO4M/wj+DQ8JDg0fCR4NLwkuDT8JPg1PCU4NXwleDW8Jbg1/CX4NjwmODZ8Jng2vCa4Nvwm+Dc8Jzg3fCd4N7wnuDf8J/g4PCg4OHwoeDi8KLg4/Cj4OTwpODl8KXg5vCm4Ofwp+Do8Kjg6fCp4OrwquDr8Kvg7PCs4O3wreDu8K7g7/Cv4PDwsODx8LHg8vCy4PPws+D08LTg9fC14PbwtuD38Lfg+PC44PnwueD68Lrg+/C74PzwvOBA8b3gQfG+4ELxv+BD8cDgRPHB4EXxwuBG8cPgR/HE4EjxxeBJ8cbgSvHH4EvxyOBM8cngTfHK4E7xy+BP8czgUPHN4FHxzuBS8c/gU/HQ4FTx0eBV8dLgVvHT4Ffx1OBY8dXgWfHW4Frx1+Bb8djgXPHZ4F3x2uBe8dvgX/Hc4GDx3eBh8d7gYvHf4GPx4OBk8eHgZfHi4Gbx4+Bn8eTgaPHl4Gnx5uBq8efga/Ho4Gzx6eBt8ergbvHr4G/x7OBw8e3gcfHu4HLx7+Bz8fDgdPHx4HXx8uB28fPgd/H04Hjx9eB58fbgevH34Hvx+OB88fngffH64H7x++CA8fzggfH94ILx/uCD8f/ghPEA4YXxAeGG8QLhh/ED4YjxBOGJ8QXhivEG4YvxB+GM8QjhjfEJ4Y7xCuGP8QvhkPEM4ZHxDeGS8Q7hk/EP4ZTxEOGV8RHhlvES4ZfxE+GY8RThmfEV4ZrxFuGb8RfhnPEY4Z3xGeGe8Rrhn/Eb4aDxHOGh8R3hovEe4aPxH+Gk8SDhpfEh4abxIuGn8SPhqPEk4anxJeGq8Sbhq/En4azxKOGt8SnhrvEq4a/xK+Gw8SzhsfEt4bLxLuGz8S/htPEw4bXxMeG28TLht/Ez4bjxNOG58TXhuvE24bvxN+G88TjhvfE54b7xOuG/8TvhwPE84cHxPeHC8T7hw/E/4cTxQOHF8UHhxvFC4cfxQ+HI8UThyfFF4crxRuHL8UfhzPFI4c3xSeHO8Urhz/FL4dDxTOHR8U3h0vFO4dPxT+HU8VDh1fFR4dbxUuHX8VPh2PFU4dnxVeHa8Vbh2/FX4dzxWOHd8Vnh3vFa4d/xW+Hg8Vzh4fFd4eLxXuHj8V/h5PFg4eXxYeHm8WLh5/Fj4ejxZOHp8WXh6vFm4evxZ+Hs8Wjh7fFp4e7xauHv8Wvh8PFs4fHxbeHy8W7h8/Fv4fTxcOH18XHh9vFy4ffxc+H48XTh+fF14frxduH78Xfh/PF44UDyeeFB8nrhQvJ74UPyfOFE8n3hRfJ+4Ubyf+FH8oDhSPKB4UnyguFK8oPhS/KE4UzyheFN8obhTvKH4U/yiOFQ8onhUfKK4VLyi+FT8ozhVPKN4VXyjuFW8o/hV/KQ4VjykeFZ8pLhWvKT4VvylOFc8pXhXfKW4V7yl+Ff8pjhYPKZ4WHymuFi8pvhY/Kc4WTyneFl8p7hZvKf4WfyoOFo8qHhafKi4Wryo+Fr8qThbPKl4W3ypuFu8qfhb/Ko4XDyqeFx8qrhcvKr4XPyrOF08q3hdfKu4Xbyr+F38rDhePKx4XnysuF68rPhe/K04XzyteF98rbhfvK34YDyuOGB8rnhgvK64YPyu+GE8rzhhfK94YbyvuGH8r/hiPLA4YnyweGK8sLhi/LD4YzyxOGN8sXhjvLG4Y/yx+GQ8sjhkfLJ4ZLyyuGT8svhlPLM4ZXyzeGW8s7hl/LP4Zjy0OGZ8tHhmvLS4Zvy0+Gc8tThnfLV4Z7y1uGf8tfhoPLY4aHy2eGi8trho/Lb4aTy3OGl8t3hpvLe4afy3+Go8uDhqfLh4ary4uGr8uPhrPLk4a3y5eGu8ubhr/Ln4bDy6OGx8unhsvLq4bPy6+G08uzhtfLt4bby7uG38u/huPLw4bny8eG68vLhu/Lz4bzy9OG98vXhvvL24b/y9+HA8vjhwfL54cLy+uHD8vvhxPL84cXy/eHG8v7hx/L/4cjyAOLJ8gHiyvIC4svyA+LM8gTizfIF4s7yBuLP8gfi0PII4tHyCeLS8gri0/IL4tTyDOLV8g3i1vIO4tfyD+LY8hDi2fIR4tryEuLb8hPi3PIU4t3yFeLe8hbi3/IX4uDyGOLh8hni4vIa4uPyG+Lk8hzi5fId4ubyHuLn8h/i6PIg4unyIeLq8iLi6/Ij4uzyJOLt8iXi7vIm4u/yJ+Lw8iji8fIp4vLyKuLz8ivi9PIs4vXyLeL28i7i9/Iv4vjyMOL58jHi+vIy4vvyM+L88jTiQPM14kHzNuJC8zfiQ/M44kTzOeJF8zriRvM74kfzPOJI8z3iSfM+4krzP+JL80DiTPNB4k3zQuJO80PiT/NE4lDzReJR80biUvNH4lPzSOJU80niVfNK4lbzS+JX80ziWPNN4lnzTuJa80/iW/NQ4lzzUeJd81LiXvNT4l/zVOJg81XiYfNW4mLzV+Jj81jiZPNZ4mXzWuJm81viZ/Nc4mjzXeJp817iavNf4mvzYOJs82HibfNi4m7zY+Jv82TicPNl4nHzZuJy82fic/No4nTzaeJ182ridvNr4nfzbOJ4823iefNu4nrzb+J783DifPNx4n3zcuJ+83PigPN04oHzdeKC83big/N34oTzeOKF83nihvN64ofze+KI83ziifN94orzfuKL83/ijPOA4o3zgeKO84Lij/OD4pDzhOKR84XikvOG4pPzh+KU84jilfOJ4pbziuKX84vimPOM4pnzjeKa847im/OP4pzzkOKd85HinvOS4p/zk+Kg85TiofOV4qLzluKj85fipPOY4qXzmeKm85rip/Ob4qjznOKp853iqvOe4qvzn+Ks86DirfOh4q7zouKv86PisPOk4rHzpeKy86bis/On4rTzqOK186nitvOq4rfzq+K486ziufOt4rrzruK786/ivPOw4r3zseK+87Liv/Oz4sDztOLB87XiwvO24sPzt+LE87jixfO54sbzuuLH87viyPO84snzveLK877iy/O/4szzwOLN88HizvPC4s/zw+LQ88Ti0fPF4tLzxuLT88fi1PPI4tXzyeLW88ri1/PL4tjzzOLZ883i2vPO4tvzz+Lc89Di3fPR4t7z0uLf89Pi4PPU4uHz1eLi89bi4/PX4uTz2OLl89ni5vPa4ufz2+Lo89zi6fPd4urz3uLr89/i7PPg4u3z4eLu8+Li7/Pj4vDz5OLx8+Xi8vPm4vPz5+L08+ji9fPp4vbz6uL38+vi+PPs4vnz7eL68+7i+/Pv4vzz8OJA9PHiQfTy4kL08+JD9PTiRPT14kX09uJG9PfiR/T44kj0+eJJ9PriSvT74kv0/OJM9P3iTfT+4k70/+JP9ADjUPQB41H0AuNS9APjU/QE41T0BeNV9AbjVvQH41f0CONY9AnjWfQK41r0C+Nb9AzjXPQN4130DuNe9A/jX/QQ42D0EeNh9BLjYvQT42P0FONk9BXjZfQW42b0F+Nn9BjjaPQZ42n0GuNq9Bvja/Qc42z0HeNt9B7jbvQf42/0IONw9CHjcfQi43L0I+Nz9CTjdPQl43X0JuN29Cfjd/Qo43j0KeN59CrjevQr43v0LON89C3jffQu4370L+OA9DDjgfQx44L0MuOD9DPjhPQ044X0NeOG9Dbjh/Q344j0OOOJ9DnjivQ644v0O+OM9DzjjfQ94470PuOP9D/jkPRA45H0QeOS9ELjk/RD45T0ROOV9EXjlvRG45f0R+OY9EjjmfRJ45r0SuOb9EvjnPRM4530TeOe9E7jn/RP46D0UOOh9FHjovRS46P0U+Ok9FTjpfRV46b0VuOn9FfjqPRY46n0WeOq9Frjq/Rb46z0XOOt9F3jrvRe46/0X+Ow9GDjsfRh47L0YuOz9GPjtPRk47X0ZeO29Gbjt/Rn47j0aOO59GnjuvRq47v0a+O89GzjvfRt4770buO/9G/jwPRw48H0cePC9HLjw/Rz48T0dOPF9HXjxvR248f0d+PI9HjjyfR548r0euPL9HvjzPR84830fePO9H7jz/R/49D0gOPR9IHj0vSC49P0g+PU9ITj1fSF49b0huPX9Ifj2PSI49n0iePa9Irj2/SL49z0jOPd9I3j3vSO49/0j+Pg9JDj4fSR4+L0kuPj9JPj5PSU4+X0lePm9Jbj5/SX4+j0mOPp9Jnj6vSa4+v0m+Ps9Jzj7fSd4+70nuPv9J/j8PSg4/H0oePy9KLj8/Sj4/T0pOP19KXj9vSm4/f0p+P49Kjj+fSp4/r0quP79Kvj/PSs40D1reNB9a7jQvWv40P1sONE9bHjRfWy40b1s+NH9bTjSPW140n1tuNK9bfjS/W440z1ueNN9brjTvW740/1vONQ9b3jUfW+41L1v+NT9cDjVPXB41X1wuNW9cPjV/XE41j1xeNZ9cbjWvXH41v1yONc9cnjXfXK4171y+Nf9czjYPXN42H1zuNi9c/jY/XQ42T10eNl9dLjZvXT42f11ONo9dXjafXW42r11+Nr9djjbPXZ42312uNu9dvjb/Xc43D13eNx9d7jcvXf43P14ON09eHjdfXi43b14+N39eTjePXl43n15uN69efje/Xo43z16eN99erjfvXr44D17OOB9e3jgvXu44P17+OE9fDjhfXx44b18uOH9fPjiPX044n19eOK9fbji/X344z1+OON9fnjjvX644/1++OQ9fzjkfX945L1/uOT9f/jlPUA5JX1AeSW9QLkl/UD5Jj1BOSZ9QXkmvUG5Jv1B+Sc9QjknfUJ5J71CuSf9QvkoPUM5KH1DeSi9Q7ko/UP5KT1EOSl9RHkpvUS5Kf1E+So9RTkqfUV5Kr1FuSr9RfkrPUY5K31GeSu9Rrkr/Ub5LD1HOSx9R3ksvUe5LP1H+S09SDktfUh5Lb1IuS39SPkuPUk5Ln1JeS69Sbku/Un5Lz1KOS99SnkvvUq5L/1K+TA9SzkwfUt5ML1LuTD9S/kxPUw5MX1MeTG9TLkx/Uz5Mj1NOTJ9TXkyvU25Mv1N+TM9TjkzfU55M71OuTP9Tvk0PU85NH1PeTS9T7k0/U/5NT1QOTV9UHk1vVC5Nf1Q+TY9UTk2fVF5Nr1RuTb9Ufk3PVI5N31SeTe9Urk3/VL5OD1TOTh9U3k4vVO5OP1T+Tk9VDk5fVR5Ob1UuTn9VPk6PVU5On1VeTq9Vbk6/VX5Oz1WOTt9Vnk7vVa5O/1W+Tw9Vzk8fVd5PL1XuTz9V/k9PVg5PX1YeT29WLk9/Vj5Pj1ZOT59WXk+vVm5Pv1Z+T89WjkQPZp5EH2auRC9mvkQ/Zs5ET2beRF9m7kRvZv5Ef2cORI9nHkSfZy5Er2c+RL9nTkTPZ15E32duRO9nfkT/Z45FD2eeRR9nrkUvZ75FP2fORU9n3kVfZ+5Fb2f+RX9oDkWPaB5Fn2guRa9oPkW/aE5Fz2heRd9obkXvaH5F/2iORg9onkYfaK5GL2i+Rj9ozkZPaN5GX2juRm9o/kZ/aQ5Gj2keRp9pLkavaT5Gv2lORs9pXkbfaW5G72l+Rv9pjkcPaZ5HH2muRy9pvkc/ac5HT2neR19p7kdvaf5Hf2oOR49qHkefai5Hr2o+R79qTkfPal5H32puR+9qfkgPao5IH2qeSC9qrkg/ar5IT2rOSF9q3khvau5If2r+SI9rDkifax5Ir2suSL9rPkjPa05I32teSO9rbkj/a35JD2uOSR9rnkkva65JP2u+SU9rzklfa95Jb2vuSX9r/kmPbA5Jn2weSa9sLkm/bD5Jz2xOSd9sXknvbG5J/2x+Sg9sjkofbJ5KL2yuSj9svkpPbM5KX2zeSm9s7kp/bP5Kj20OSp9tHkqvbS5Kv20+Ss9tTkrfbV5K721uSv9tfksPbY5LH22eSy9trks/bb5LT23OS19t3ktvbe5Lf23+S49uDkufbh5Lr24uS79uPkvPbk5L325eS+9ubkv/bn5MD26OTB9unkwvbq5MP26+TE9uzkxfbt5Mb27uTH9u/kyPbw5Mn28eTK9vLky/bz5Mz29OTN9vXkzvb25M/29+TQ9vjk0fb55NL2+uTT9vvk1Pb85NX2/eTW9v7k1/b/5Nj2AOXZ9gHl2vYC5dv2A+Xc9gTl3fYF5d72BuXf9gfl4PYI5eH2CeXi9grl4/YL5eT2DOXl9g3l5vYO5ef2D+Xo9hDl6fYR5er2EuXr9hPl7PYU5e32FeXu9hbl7/YX5fD2GOXx9hnl8vYa5fP2G+X09hzl9fYd5fb2HuX39h/l+PYg5fn2IeX69iLl+/Yj5fz2JOVA9yXlQfcm5UL3J+VD9yjlRPcp5UX3KuVG9yvlR/cs5Uj3LeVJ9y7lSvcv5Uv3MOVM9zHlTfcy5U73M+VP9zTlUPc15VH3NuVS9zflU/c45VT3OeVV9zrlVvc75Vf3POVY9z3lWfc+5Vr3P+Vb90DlXPdB5V33QuVe90PlX/dE5WD3ReVh90blYvdH5WP3SOVk90nlZfdK5Wb3S+Vn90zlaPdN5Wn3TuVq90/la/dQ5Wz3UeVt91LlbvdT5W/3VOVw91XlcfdW5XL3V+Vz91jldPdZ5XX3WuV291vld/dc5Xj3XeV5917levdf5Xv3YOV892Hlffdi5X73Y+WA92Tlgfdl5YL3ZuWD92flhPdo5YX3aeWG92rlh/dr5Yj3bOWJ923livdu5Yv3b+WM93Dljfdx5Y73cuWP93PlkPd05ZH3deWS93blk/d35ZT3eOWV93nllvd65Zf3e+WY93zlmfd95Zr3fuWb93/lnPeA5Z33geWe94Lln/eD5aD3hOWh94XloveG5aP3h+Wk94jlpfeJ5ab3iuWn94vlqPeM5an3jeWq947lq/eP5az3kOWt95HlrveS5a/3k+Ww95TlsfeV5bL3luWz95fltPeY5bX3meW295rlt/eb5bj3nOW5953luvee5bv3n+W896Dlvfeh5b73ouW/96PlwPek5cH3peXC96blw/en5cT3qOXF96nlxveq5cf3q+XI96zlyfet5cr3ruXL96/lzPew5c33seXO97Llz/ez5dD3tOXR97Xl0ve25dP3t+XU97jl1fe55db3uuXX97vl2Pe85dn3veXa977l2/e/5dz3wOXd98Hl3vfC5d/3w+Xg98Tl4ffF5eL3xuXj98fl5PfI5eX3yeXm98rl5/fL5ej3zOXp983l6vfO5ev3z+Xs99Dl7ffR5e730uXv99Pl8PfU5fH31eXy99bl8/fX5fT32OX199nl9vfa5ff32+X499zl+ffd5fr33uX799/l/Pfg5UD44eVB+OLlQvjj5UP45OVE+OXlRfjm5Ub45+VH+OjlSPjp5Un46uVK+OvlS/js5Uz47eVN+O7lTvjv5U/48OVQ+PHlUfjy5VL48+VT+PTlVPj15VX49uVW+PflV/j45Vj4+eVZ+PrlWvj75Vv4/OVc+P3lXfj+5V74/+Vf+ADmYPgB5mH4AuZi+APmY/gE5mT4BeZl+AbmZvgH5mf4COZo+AnmafgK5mr4C+Zr+AzmbPgN5m34DuZu+A/mb/gQ5nD4EeZx+BLmcvgT5nP4FOZ0+BXmdfgW5nb4F+Z3+BjmePgZ5nn4GuZ6+Bvme/gc5nz4HeZ9+B7mfvgf5oD4IOaB+CHmgvgi5oP4I+aE+CTmhfgl5ob4JuaH+CfmiPgo5on4KeaK+Crmi/gr5oz4LOaN+C3mjvgu5o/4L+aQ+DDmkfgx5pL4MuaT+DPmlPg05pX4NeaW+Dbml/g35pj4OOaZ+Dnmmvg65pv4O+ac+Dzmnfg95p74Puaf+D/moPhA5qH4Qeai+ELmo/hD5qT4ROal+EXmpvhG5qf4R+ao+EjmqfhJ5qr4Suar+EvmrPhM5q34Teau+E7mr/hP5rD4UOax+FHmsvhS5rP4U+a0+FTmtfhV5rb4Vua3+FfmuPhY5rn4Wea6+Frmu/hb5rz4XOa9+F3mvvhe5r/4X+bA+GDmwfhh5sL4YubD+GPmxPhk5sX4ZebG+Gbmx/hn5sj4aObJ+Gnmyvhq5sv4a+bM+Gzmzfht5s74bubP+G/m0Phw5tH4cebS+HLm0/hz5tT4dObV+HXm1vh25tf4d+bY+Hjm2fh55tr4eubb+Hvm3Ph85t34febe+H7m3/h/5uD4gObh+IHm4viC5uP4g+bk+ITm5fiF5ub4hubn+Ifm6PiI5un4iebq+Irm6/iL5uz4jObt+I3m7viO5u/4j+bw+JDm8fiR5vL4kubz+JPm9PiU5vX4leb2+Jbm9/iX5vj4mOb5+Jnm+via5vv4m+b8+JzmQPmd5kH5nuZC+Z/mQ/mg5kT5oeZF+aLmRvmj5kf5pOZI+aXmSfmm5kr5p+ZL+ajmTPmp5k35quZO+avmT/ms5lD5reZR+a7mUvmv5lP5sOZU+bHmVfmy5lb5s+ZX+bTmWPm15ln5tuZa+bfmW/m45lz5ueZd+brmXvm75l/5vOZg+b3mYfm+5mL5v+Zj+cDmZPnB5mX5wuZm+cPmZ/nE5mj5xeZp+cbmavnH5mv5yOZs+cnmbfnK5m75y+Zv+czmcPnN5nH5zuZy+c/mc/nQ5nT50eZ1+dLmdvnT5nf51OZ4+dXmefnW5nr51+Z7+djmfPnZ5n352uZ++dvmgPnc5oH53eaC+d7mg/nf5oT54OaF+eHmhvni5of54+aI+eTmifnl5or55uaL+efmjPno5o356eaO+ermj/nr5pD57OaR+e3mkvnu5pP57+aU+fDmlfnx5pb58uaX+fPmmPn05pn59eaa+fbmm/n35pz5+Oad+fnmnvn65p/5++ag+fzmofn95qL5/uaj+f/mpPkA56X5Aeem+QLnp/kD56j5BOep+QXnqvkG56v5B+es+QjnrfkJ5675Cuev+QvnsPkM57H5Deey+Q7ns/kP57T5EOe1+RHntvkS57f5E+e4+RTnufkV57r5Fue7+RfnvPkY5735Gee++Rrnv/kb58D5HOfB+R3nwvke58P5H+fE+SDnxfkh58b5IufH+SPnyPkk58n5JefK+Sbny/kn58z5KOfN+Snnzvkq58/5K+fQ+Szn0fkt59L5LufT+S/n1Pkw59X5MefW+TLn1/kz59j5NOfZ+TXn2vk259v5N+fc+Tjn3fk55975Ouff+Tvn4Pk85+H5Pefi+T7n4/k/5+T5QOfl+UHn5vlC5+f5Q+fo+UTn6flF5+r5Rufr+Ufn7PlI5+35Sefu+Urn7/lL5/D5TOfx+U3n8vlO5/P5T+f0+VDn9flR5/b5Uuf3+VPn+PlU5/n5Vef6+Vbn+/lX5/z58PigAPH4/QDy+P4A8/j/ACn5xO3c+c3uDvpz7Q/6fu0Q+oDtEfqV7RL6vO0T+sztFPrO7RX6+e0W+kLuF/pZ7hj6Ye4Z+mLuGvpj7hv6Ze4c+mnuHfps7h76de4f+oHuIPqD7iH6hO4i+o3uI/qV7iT6l+4l+pjuJvqb7if6t+4o+r7uKfrO7ir62u4r+tvuLPrd7i366u4B/0mBAv/87gP/lIEE/5CBBf+TgQb/lYEH//vuCP9pgQn/aoEK/5aBC/97gQz/Q4EN/3yBDv9EgQ//XoEQ/0+CEf9QghL/UYIT/1KCFP9TghX/VIIW/1WCF/9Wghj/V4IZ/1iCGv9GgRv/R4Ec/4OBHf+BgR7/hIEf/0iBIP+XgSH/YIIi/2GCI/9igiT/Y4Il/2SCJv9lgif/ZoIo/2eCKf9ogir/aYIr/2qCLP9rgi3/bIIu/22CL/9ugjD/b4Ix/3CCMv9xgjP/coI0/3OCNf90gjb/dYI3/3aCOP93gjn/eII6/3mCO/9tgTz/X4E9/26BPv9PgT//UYFA/02BQf+BgkL/goJD/4OCRP+EgkX/hYJG/4aCR/+Hgkj/iIJJ/4mCSv+Kgkv/i4JM/4yCTf+Ngk7/joJP/4+CUP+QglH/kYJS/5KCU/+TglT/lIJV/5WCVv+Wglf/l4JY/5iCWf+Zglr/moJb/2+BXP9igV3/cIFe/2CBYf+hAGL/ogBj/6MAZP+kAGX/pQBm/6YAZ/+nAGj/qABp/6kAav+qAGv/qwBs/6wAbf+tAG7/rgBv/68AcP+wAHH/sQBy/7IAc/+zAHT/tAB1/7UAdv+2AHf/twB4/7gAef+5AHr/ugB7/7sAfP+8AH3/vQB+/74Af/+/AID/wACB/8EAgv/CAIP/wwCE/8QAhf/FAIb/xgCH/8cAiP/IAIn/yQCK/8oAi//LAIz/zACN/80Ajv/OAI//zwCQ/9AAkf/RAJL/0gCT/9MAlP/UAJX/1QCW/9YAl//XAJj/2ACZ/9kAmv/aAJv/2wCc/9wAnf/dAJ7/3gCf/98A4P+RgeH/koHi/8qB4/9QgeT/+u7l/4+B'
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

function Core.metadata(p)
 local cues,adtl,loops={},{},{}
 local cueid=1
 for _,e in ipairs(p.entries) do
  if e.kind=='marker' or e.kind=='region' then

   local name=e.encoded~='' and e.encoded or ((e.kind=='marker' and 'Marker_' or 'Region_')..cueid)
   cues[#cues+1]=u32(cueid)..u32(e.start)..'data'..u32(0)..u32(0)..u32(e.start)
   adtl[#adtl+1]=Core.chunk('labl',u32(cueid)..name..'\0')
   if e.kind=='region' then

    adtl[#adtl+1]=Core.chunk('ltxt',u32(cueid)..u32(e.finish-e.start)..'rgn '..string.pack('<I2I2I2I2',0,0,0,p.encoding=='UTF-8' and 65001 or 932)..name..'\0')
   end
   cueid=cueid+1
  end
 end

 local e=p.sustain
 if e then loops[1]=u32(0)..u32(0)..u32(e.start)..u32(e.finish-1)..u32(0)..u32(0) end
 local out={}
 if #cues>0 then out[#out+1]=Core.chunk('cue ',u32(#cues)..table.concat(cues));out[#out+1]=Core.chunk('LIST','adtl'..table.concat(adtl)) end
 if #loops>0 then out[#out+1]=Core.chunk('smpl',u32(0)..u32(0)..u32(floor(1e9/p.sr+.5))..u32(60)..u32(0)..u32(0)..u32(0)..u32(#loops)..u32(0)..table.concat(loops)) end
 local blob=table.concat(out);assert(#blob<=Core.MAX_METADATA,'リージョン情報が大きすぎます。');return blob
end
function Core.setapi(api)R=api end
return Core
end)()

local Embed={NUMBERING_REQUIRED='BLT_NUMBERING_REQUIRED:'}
function Embed.defaults()return {embed_markers=true,embed_regions=true,embed_loop_region=true,exclude_selected_region=true,encoding='UTF-8'}end
local function check(v,msg)if not v then error(msg,0)end;return v end
local function key(p)return p:gsub('\\','/'):lower()end
function Embed.supported(path)return path:lower():match('%.wav$')or path:lower():match('%.aiff?$')or path:lower():match('%.aifc$')end
local function paths(api,p,state)
 local ok,text=api.GetSetProjectInfo_String(p,'RENDER_TARGETS','',false);check(ok,'出力範囲を取得できません。')
 local out={};for name in text:gmatch('[^;]+')do out[#out+1]=name end;return out
end
function Embed.prepare(api,state,originalRegions,numbering,knownOutputs)
 if not state.embed then return end
 local p=api.EnumProjects(-1,'');local outputs={}
 for _,path in ipairs(knownOutputs or paths(api,p,state))do outputs[#outputs+1]=path end
 local wav=false
 for _,path in ipairs(outputs)do if Embed.supported(path)and(not state.s or Embed.accepts(state,path))then wav=true end end;if not wav then return end
 LoopMetadata.setapi(api)
 local rows=LoopMetadata.project_rows(p);local opts={};for k,v in pairs(state.embed)do opts[k]=v end
 local any=false;for _,row in ipairs(rows)do if row.kind=='sustain'and opts.embed_loop_region or row.kind=='region'and opts.embed_regions or row.kind=='marker'and opts.embed_markers then any=true end end
 local norm=api.GetSetProjectInfo(p,'RENDER_NORMALIZE',0,false)
 local rate=api.Master_GetPlayRate and api.Master_GetPlayRate(p)or 1;check(rate>0,'再生レートが不正です。')
 local pad=(norm&(4<<16))==0 and(norm&(1<<16))~=0 and api.GetSetProjectInfo(p,'RENDER_PADSTART',0,false)or 0
 local source=api.GetSetProjectInfo(p,'RENDER_SETTINGS',0,false);local bounds=api.GetSetProjectInfo(p,'RENDER_BOUNDSFLAG',0,false)
 local items={};for i=0,api.CountSelectedMediaItems(p)-1 do items[#items+1]=api.GetSelectedMediaItem(p,i)end
 local ui={};opts.selected_keys={}
 if api.GetNumRegionsOrMarkers and api.GetRegionOrMarker and api.GetRegionOrMarkerInfo_Value then
  for i=0,api.GetNumRegionsOrMarkers(p)-1 do local ptr=api.GetRegionOrMarker(p,i,'');if ptr then
   local isr=api.GetRegionOrMarkerInfo_Value(p,ptr,'B_ISREGION')~=0
   local id=math.floor(api.GetRegionOrMarkerInfo_Value(p,ptr,'I_NUMBER')+.5);local sel=api.GetRegionOrMarkerInfo_Value(p,ptr,'B_UISEL')
   ui[#ui+1]={ptr=ptr,isr=isr,id=id,sel=sel};if isr and sel~=0 then opts.selected_keys['r'..id]=true end
  end end
 end

 if originalRegions then
  opts.selected_keys={}
  for _,v in ipairs(originalRegions)do if v.isr and v.selected~=0 then opts.selected_keys['r'..math.floor(v.id+.5)]=true end end
 end
 local activeItems=items
 local function selectitem(item)
  if not item then
   activeItems={};for i=0,api.CountSelectedMediaItems(p)-1 do activeItems[#activeItems+1]=api.GetSelectedMediaItem(p,i)end
  end
  local wanted=item and {item}or items;local keep,previous={},{}
  for _,v in ipairs(wanted)do keep[v]=true end
  for _,v in ipairs(activeItems)do previous[v]=true;if not keep[v]then api.SetMediaItemSelected(v,false)end end
  for _,v in ipairs(wanted)do if not previous[v]then api.SetMediaItemSelected(v,true)end end
  activeItems=wanted
 end
 local function selectrow(row)
  check(api.SetRegionOrMarkerInfo_Value and #ui>0,'リージョン／マーカー選択APIが必要です。')
  for _,v in ipairs(ui)do local wanted=(v.id==row.id and v.isr==row.isr)and 1 or 0;api.SetRegionOrMarkerInfo_Value(p,v.ptr,'B_UISEL',wanted);check(api.GetRegionOrMarkerInfo_Value(p,v.ptr,'B_UISEL')==wanted,'確認用のリージョン選択を設定できません。')end
 end
 local razors=(source&4096)~=0 and Scope.razors(api,p)or nil
 local units={};local function add(a,b,item,row)check(b>a,'書き出し範囲が空です。');units[#units+1]={start=a,finish=b,item=item,row=row}end
 if razors then
  local first,last=math.huge,-math.huge
  for _,v in ipairs(razors)do for _,area in ipairs(v.areas)do
   if(source&(4<<16))~=0 then first=math.min(first,area.start);last=math.max(last,area.finish)
   else add(area.start,area.finish);units[#units].razor={track=v.track,raw=area.raw}end
  end end
  if(source&(4<<16))~=0 and first<last then add(first,last)end
 elseif(source&(32|64))~=0 then
  local first,last=math.huge,-math.huge
  for _,item in ipairs(items)do local a=api.GetMediaItemInfo_Value(item,'D_POSITION');local b=a+api.GetMediaItemInfo_Value(item,'D_LENGTH')
   if(source&(4<<16))~=0 then first=math.min(first,a);last=math.max(last,b)else add(a,b,item)end
  end
  if(source&(4<<16))~=0 and #items>0 then add(first,last)end
 elseif bounds==3 or bounds==5 or bounds==6 or bounds==7 then
  local isregion=bounds==3 or bounds==5;local selected={};local selectedCount=0;for _,v in ipairs(ui)do if v.sel~=0 then selected[(v.isr and'r'or'm')..v.id]=true;if v.isr==isregion then selectedCount=selectedCount+1 end end end
  for i,row in ipairs(rows)do if row.isr==isregion and((bounds==3 or bounds==6)or selectedCount==0 or selected[row.key])then
   local ending=row.finish
   if not isregion then ending=api.GetProjectLength(p);for _,nextrow in ipairs(rows)do if not nextrow.isr and nextrow.start>row.start and nextrow.start<ending then ending=nextrow.start end end end
   add(row.start,ending,nil,row)
  end end
 elseif bounds==0 then add(api.GetSetProjectInfo(p,'RENDER_STARTPOS',0,false),api.GetSetProjectInfo(p,'RENDER_ENDPOS',0,false))
 elseif bounds==2 then local a,b=api.GetSet_LoopTimeRange2(p,false,false,0,0,false);add(a,b)
 elseif bounds==1 then
  local a,b=0,api.GetProjectLength(p);for _,row in ipairs(rows)do if not row.isr then if row.raw=='=START'then a=row.start elseif row.raw=='=END'then b=row.start end end end;add(a,b)
 else error('埋め込み範囲を解決できません：'..bounds,0)end
 local originalPattern
 if numbering then local yes;yes,originalPattern=api.GetSetProjectInfo_String(p,'RENDER_PATTERN','',false);check(yes,'出力名を取得できません。')end
 local signatures,probePaths={},{}
 local resolved={};local originals={};for _,path in ipairs(outputs)do originals[key(path)]=true end
 local function restore()
  local errors={};local function attempt(fn)local ok,err=pcall(fn);if not ok then errors[#errors+1]=tostring(err)end end
  if numbering then attempt(function()check(api.GetSetProjectInfo_String(p,'RENDER_PATTERN',originalPattern,true),'出力名の復元失敗')end)end
  attempt(function()api.GetSetProjectInfo(p,'RENDER_BOUNDSFLAG',bounds,true);check(api.GetSetProjectInfo(p,'RENDER_BOUNDSFLAG',0,false)==bounds,'範囲の復元失敗')end);attempt(function()selectitem()end)
  for _,v in ipairs(ui)do if api.SetRegionOrMarkerInfo_Value then attempt(function()api.SetRegionOrMarkerInfo_Value(p,v.ptr,'B_UISEL',v.sel);check(api.GetRegionOrMarkerInfo_Value(p,v.ptr,'B_UISEL')==v.sel,'選択の復元失敗：'..v.id)end)end end
  if razors then attempt(function()Scope.restore(api,p,nil,razors)end)end
  check(#errors==0,table.concat(errors,' / '))
 end
 local function activateUnit(unit)
  if unit.razor then Scope.setrazors(api,razors,{},unit.razor)
  elseif unit.item then selectitem(unit.item)
  elseif unit.row then api.GetSetProjectInfo(p,'RENDER_BOUNDSFLAG',unit.row.isr and 5 or 7,true);selectrow(unit.row)
  end
 end
 local function metadata(files)
  return {files=files,units=units,rows=rows,options=opts,rate=rate,pad=pad,accept=function(path)return not state.s or Embed.accepts(state,path)end}
 end
 local token='__BLT_RANGE__'
 local ending='__BLT_RANGE_END__'
 local function probe(path)
  local a=path:find(token,1,true);local b=a and path:find(ending,a+#token,true)
  check(a and b,'埋め込み範囲の照合情報を取得できません。')
  return path:sub(a+#token,b-1),path:sub(1,a-1)..path:sub(b+#ending)
 end
 local ok,err=xpcall(function()
  if numbering then
   local identity=(source&(32|64))~=0 and '$tracknumber_$itemnumber_'or ''
   local pattern=originalPattern..token..identity..'$start_$end'..ending
   check(api.GetSetProjectInfo_String(p,'RENDER_PATTERN',pattern,true),'確認用の出力名を設定できません。')
   local probes=paths(api,p,state)
   check(#probes==#outputs,'確認用の出力数が変わりました。')

   for i,path in ipairs(probes)do
    local signature=probe(path);local k=key(outputs[i])
    check(not probePaths[k],'出力名が重複しています：'..outputs[i])
    probePaths[k]=signature
   end
  end
  for _,unit in ipairs(units)do

   activateUnit(unit)
   local current=(numbering or unit.razor or unit.item or unit.row)and paths(api,p,state)or outputs
   if #current>0 then
    local test=LoopMetadata.plan(rows,unit.start,unit.finish,48000,opts)
    unit.loop=test.sustain~=nil
    check(unit.loop or not any or(norm&(4<<16))~=0 or(norm&(16384|32768))==0,'無音トリムとリージョン埋め込みは開始位置を確定できません。トリムまたは埋め込みをOFFにしてください。')
    for _,path in ipairs(current)do if Embed.supported(path)and not path:lower():match('%.wav$')then Embed.aiff_metadata(test)end end
   end
   for _,path in ipairs(current)do
    if numbering then
     local signature=probe(path);local previous=signatures[signature]
     check(not previous or(previous.start==unit.start and previous.finish==unit.finish),'埋め込み範囲を区別できません：'..path)
     signatures[signature]=unit
    else
     check(originals[key(path)],Embed.NUMBERING_REQUIRED..path)
     local previous=resolved[key(path)];check(not previous or(previous.start==unit.start and previous.finish==unit.finish),Embed.NUMBERING_REQUIRED..path)
     resolved[key(path)]=unit
    end
   end
  end
  for _,path in ipairs(outputs)do
   local k=key(path)
   if numbering then resolved[k]=signatures[probePaths[k]]end
   check(resolved[k],numbering and('埋め込み範囲を照合できません：'..path)or(Embed.NUMBERING_REQUIRED..path))
   local unit=resolved[k];unit.paths=unit.paths or{};unit.paths[#unit.paths+1]=path
  end
 end,tostring)
 local restored,restoreerr=pcall(restore);check(restored,'範囲確認後の復元に失敗：'..tostring(restoreerr));check(ok,err)
 return metadata(resolved)
end
local function exact(f,n)local bytes=f:read(n);check(bytes and #bytes==n,'WAVが途中で切れています。');return bytes end
function Embed.scan(path)
 local f=check(io.open(path,'rb'),'WAVを開けません：'..path)
 local ok,w=pcall(function()
  local size=f:seek('end');f:seek('set',0);local header=exact(f,12);local kind=header:sub(1,4)
  check((kind=='RIFF'or kind=='RF64')and header:sub(9)=='WAVE','埋め込みはRIFF / RF64 WAVに対応しています。')
  local out={size=size,kind=kind,chunks={}};local at=12
  while at<size do
   f:seek('set',at);local h=exact(f,8);local id=h:sub(1,4);local n=string.unpack('<I4',h,5)
   if n==0xffffffff then check(id=='data'and out.data64,'RF64のサイズが不正です。');n=out.data64 end
   check(at+8+n+n%2<=size,'WAVチャンクの長さが不正です。')
   local c={id=id,offset=at,size=n,total=8+n+n%2}
   if id=='ds64' then
    check(n>=28,'RF64ヘッダーが不正です。');local d=exact(f,28);out.riff64,out.data64=string.unpack('<I8I8',d);check(string.unpack('<I4',d,25)==0,'RF64追加サイズ表は非対応です。')
   elseif id=='fmt 'then
    check(n>=16 and n<=4096,'WAV形式情報が不正です。');local d=exact(f,n);local tag,ch,sr,_,align,bits=string.unpack('<I2I2I4I4I2I2',d)
    if tag==65534 then check(n>=40,'拡張WAV形式が不正です。');tag=string.unpack('<I4',d,25)end
    check((tag==1 or tag==3)and ch>0 and sr>0 and bits>0 and align==ch*bits//8,'埋め込みはPCM / float WAVに対応しています。');out.sr,out.align=sr,align
   elseif id=='data'then check(not out.data,'複数dataチャンクは非対応です。');out.data=c
   end
   if id=='LIST'and n>=4 then c.list=exact(f,4)end
   c.remove=id=='cue 'or id=='smpl'or id=='plst'or(id=='LIST'and c.list=='adtl')
   out.chunks[#out.chunks+1]=c;at=at+c.total
  end
  check(out.data and out.align and out.data.size%out.align==0,'WAV音声データが不正です。')
  check(kind=='RIFF'and string.unpack('<I4',header,5)+8==size or kind=='RF64'and out.riff64+8==size,'未完了のWAVです。')
  out.frames=out.data.size//out.align;return out
 end)
 f:close();check(ok,w);return w
end
local function exists(p)local f=io.open(p,'rb');if f then f:close();return true end end
local function spare(p)local i=1;while exists(p..i)do i=i+1 end;return p..i end
function Embed.timeline(path,plan,w)
 local unit=check(plan.files[key(path)],'出力先の範囲が不明です：'..path)
 local projected={}
 for _,r in ipairs(plan.rows)do local v={};for k,x in pairs(r)do v[k]=x end
  v.start=r.start/plan.rate+plan.pad;v.finish=r.finish/plan.rate+plan.pad;projected[#projected+1]=v
 end
 if unit.window then return LoopMetadata.plan(plan.rows,unit.start,unit.window.finish,w.sr,plan.options)end
 local origin=unit.start/plan.rate;return LoopMetadata.plan(projected,origin,origin+w.frames/w.sr,w.sr,plan.options)
end
local function loop_slice(path,plan,w)
 local unit=plan.files[key(path)];local window=unit and unit.window
 if not window then return 0,w.frames,false end
 check(w.sr==window.sr and math.abs(w.frames-window.rawFrames)<=1,'ループ用レンダーのサンプルレートまたは長さが一致しません。')
 check(window.pre>=0 and window.frames>0 and window.pre+window.frames<=w.frames,'ループ用レンダーに切り出し範囲が含まれていません。')
 return window.pre,window.frames,true
end
local function copy_audio(input,output,offset,n)
 check(input:seek('set',offset),'音声ファイルの読み取り位置を変更できません。')
 while n>0 do local count=math.min(n,1048576);check(output:write(exact(input,count)),'音声ファイルの書込エラー');n=n-count end
end
local function replace_output(path,temp,backup)
 local had=exists(path)
 if had then check(os.rename(path,backup),'出力ファイルが使用中です。元ファイルを保持します。')end
 local moved,why=os.rename(temp,path)
 if not moved then local restored=not had or os.rename(backup,path);error('出力の置換失敗：'..tostring(why)..(restored and''or(' 元ファイル：'..backup)),0)end
 if had then check(os.remove(backup),'出力は完了しましたが退避ファイルを削除できません：'..backup)end
end
function Embed.write(path,plan,source)
 if not path:lower():match('%.wav$')then return Embed.write_aiff(path,plan,source)end
 local w=Embed.scan(source or path);local pre,frames,crop=loop_slice(path,plan,w)
 local blob=LoopMetadata.metadata(Embed.timeline(path,plan,w));local bytes=frames*w.align
 local size=12+#blob
 for _,c in ipairs(w.chunks)do if not c.remove and not(crop and c.id=='PEAK')then size=size+(crop and c==w.data and(8+bytes+bytes%2)or c.total)end end
 check(w.kind=='RF64'or size-8<=0xffffffff,'埋め込み後にRIFFサイズ上限を超えます。RF64で書き出してください。')
 local temp=spare(path..'.blt-rm-');local backup=spare(path..'.blt-original-');local input,output
 local ok,err=xpcall(function()
  input=check(io.open(source or path,'rb'),'元WAVを開けません。');output=check(io.open(temp,'wb'),'作業WAVを作成できません。')
  check(output:write(w.kind..string.pack('<I4',w.kind=='RF64'and 0xffffffff or size-8)..'WAVE'),'書込エラー')
  for _,c in ipairs(w.chunks)do if not c.remove and not(crop and c.id=='PEAK')then
   if crop and c==w.data then
    check(output:write('data'..string.pack('<I4',w.kind=='RF64'and 0xffffffff or bytes)),'書込エラー')
    copy_audio(input,output,c.offset+8+pre*w.align,bytes)
    if bytes%2~=0 then check(output:write('\0'),'書込エラー')end
   elseif c.id=='ds64' then
    input:seek('set',c.offset);local d=exact(input,32)
    check(output:write(d:sub(1,8)..(crop and string.pack('<I8I8I8',size-8,bytes,frames)or(string.pack('<I8',size-8)..d:sub(17)))),'書込エラー')
    copy_audio(input,output,c.offset+32,c.total-32)
   elseif crop and c.id=='fact'and c.size>=4 then
    input:seek('set',c.offset);local d=exact(input,12)
    check(output:write(d:sub(1,8)..string.pack('<I4',frames)),'書込エラー');copy_audio(input,output,c.offset+12,c.total-12)
   elseif crop and c.id=='bext'and c.size>=346 and pre>0 then
    input:seek('set',c.offset);local d=exact(input,354);local lo,hi=string.unpack('<I4I4',d,347)
    local sum=lo+pre;check(hi+sum//4294967296<=0xffffffff,'BWF時刻が上限を超えています。')
    check(output:write(d:sub(1,346)..string.pack('<I4I4',sum%4294967296,hi+sum//4294967296)),'書込エラー')
    copy_audio(input,output,c.offset+354,c.total-354)
   else copy_audio(input,output,c.offset,c.total)end
  end end
  check(output:write(blob),'書込エラー');check(output:close(),'書込終了エラー');output=nil;input:close();input=nil
  local verified=Embed.scan(temp);check(verified.frames==frames and verified.sr==w.sr and verified.size==size,'埋め込みWAV検証に失敗しました。')
  local verifyfile=check(io.open(temp,'rb'),'検証WAVを開けません。');local actual={}
  local vok,verr=pcall(function()for _,c in ipairs(verified.chunks)do if c.remove then check(c.total<=LoopMetadata.MAX_METADATA,'メタデータ上限を超えました。');verifyfile:seek('set',c.offset);actual[#actual+1]=exact(verifyfile,c.total)end end;check(table.concat(actual)==blob,'埋め込み情報の照合に失敗しました。')end);verifyfile:close();check(vok,verr)
  replace_output(path,temp,backup)
 end,tostring)
 if input then pcall(function()input:close()end)end;if output then pcall(function()output:close()end)end
 if not ok then if exists(temp)then os.remove(temp)end;error(err,0)end
end
function Embed.finish(stats,plan)
 if not plan then return end
 local done={};for entry in (stats or''):gmatch('[^;]+')do local path=entry:match('^FILE:(.+)$')
  if path and Embed.supported(path)and(not plan.accept or plan.accept(path))and not done[key(path)]and not(plan.finished and plan.finished[key(path)])then Embed.write(path,plan);done[key(path)]=true end
 end
end

local function acheck(ok,msg)if not ok then error(msg,0)end;return ok end
local function achunk(id,data)return id..string.pack('>I4',#data)..data..(#data%2==1 and '\0'or'')end
function Embed.aiff_metadata(p,instrument)
 local marks={};local first,last=0,0
 local function mark(pos,name)
  local id=#marks+1
  acheck(id<=32767,'AIFF marker limit exceeded (32767).')
  acheck(#name<=255,'AIFF marker name exceeds 255 encoded bytes: '..name)
  local text=string.char(#name)..name;if #text%2==1 then text=text..'\0'end
  marks[id]=string.pack('>I2I4',id,pos)..text;return id
 end
 for _,e in ipairs(p.entries)do
  if e.kind=='sustain'then first=mark(e.start,'Loop Start');last=mark(e.finish,'Loop End')
  elseif e.kind=='region'then
   local name=e.encoded~=''and e.encoded or'Region'
   mark(e.start,name..' [START]');mark(e.finish,name..' [END]')
  else mark(e.start,e.encoded~=''and e.encoded or'Marker')end
 end
 local out={}
 if #marks>0 then out[#out+1]=achunk('MARK',string.pack('>I2',#marks)..table.concat(marks))end

 if instrument or first>0 then
  local prefix=instrument and instrument:sub(1,8)or string.pack('>BBBBBBi2',60,0,0,127,1,127,0)
  out[#out+1]=achunk('INST',prefix..string.pack('>I2I2I2I2I2I2',first>0 and 1 or 0,first,last,0,0,0))
 end
 local blob=table.concat(out);acheck(#blob<=LoopMetadata.MAX_METADATA,'AIFF metadata is too large.');return blob
end
function Embed.scan_aiff(path)
 local f=acheck(io.open(path,'rb'),'Cannot open AIFF: '..path)
 local function read(n)local d=f:read(n);acheck(d and #d==n,'Truncated AIFF.');return d end
 local ok,w=pcall(function()
  local size=f:seek('end');f:seek('set',0);local h=read(12);local kind=h:sub(9,12)
  acheck(h:sub(1,4)=='FORM'and(kind=='AIFF'or kind=='AIFC')and string.unpack('>I4',h,5)+8==size,'Invalid or unfinished AIFF.')
  local out={size=size,kind=kind,chunks={}};local at=12
  while at<size do
   f:seek('set',at);local header=read(8);local id=header:sub(1,4);local n=string.unpack('>I4',header,5)
   acheck(at+8+n+n%2<=size,'Invalid AIFF chunk size.')
   local c={id=id,offset=at,size=n,total=8+n+n%2,remove=id=='MARK'or id=='INST'}
   if id=='COMM'then
    acheck(not out.sr and n>=18 and n<=4096,'Invalid AIFF COMM chunk.');local d=read(n)
    local ch,frames,bits,ex,hi,lo=string.unpack('>I2I4I2I2I4I4',d)
    local sr=(hi*4294967296.0+lo)*2^(ex-16383-63)
    local codec=kind=='AIFF'and'NONE'or d:sub(19,22)
    acheck(ex>0 and ex<32767 and hi>=0x80000000 and sr>=8000 and sr<=384000 and math.abs(sr-math.floor(sr+.5))<.001,'Unsupported AIFF sample rate.')
    acheck(ch>0 and bits>0 and bits<=64 and(codec=='NONE'or codec=='sowt'or codec=='fl32'or codec=='FL32'or codec=='fl64'or codec=='FL64'),'AIFF embedding supports PCM / float only.')
    acheck((codec~='fl32'and codec~='FL32'or bits==32)and(codec~='fl64'and codec~='FL64'or bits==64),'Invalid AIFF float depth.')
    out.sr,out.frames,out.align=math.floor(sr+.5),frames,ch*math.ceil(bits/8)
   elseif id=='SSND'then
    acheck(not out.data and n>=8,'Invalid AIFF SSND chunk.');local off=string.unpack('>I4',read(8));acheck(off<=n-8,'Invalid AIFF audio offset.');out.data=c;out.audioSize=n-8-off;out.audioOffset=at+16+off
   elseif id=='INST'then acheck(not out.instrument and n==20,'Invalid AIFF INST chunk.');out.instrument=read(n)
   elseif id=='COMT'then

    acheck(n>=2 and n<=LoopMetadata.MAX_METADATA,'Invalid AIFF COMT chunk.');local d=read(n);local count=string.unpack('>I2',d);local pos=3;local comments={d:sub(1,2)}
    for i=1,count do
     acheck(pos+7<=#d,'Truncated AIFF comment.');local length=string.unpack('>I2',d,pos+6);local finish=pos+8+length+length%2
     acheck(finish-1<=#d,'Truncated AIFF comment text.');comments[#comments+1]=d:sub(pos,pos+3)..'\0\0'..d:sub(pos+6,finish-1);pos=finish
    end
    acheck(pos==#d+1,'Invalid AIFF comment length.');c.replacement=achunk(id,table.concat(comments))
   end
   out.chunks[#out.chunks+1]=c;at=at+c.total
  end
  acheck(out.sr and out.data and out.frames>0 and out.audioSize>=out.frames*out.align,'Incomplete AIFF audio data.');return out
 end)
 f:close();acheck(ok,w);return w
end
function Embed.write_aiff(path,plan,source)
 local w=Embed.scan_aiff(source or path);local pre,frames,crop=loop_slice(path,plan,w)
 local blob=Embed.aiff_metadata(Embed.timeline(path,plan,w),w.instrument);local bytes=frames*w.align
 local size=12+#blob
 for _,c in ipairs(w.chunks)do if not c.remove and not(crop and c.id=='PEAK')then size=size+(crop and c==w.data and(16+bytes+bytes%2)or(c.replacement and #c.replacement or c.total))end end
 acheck(size-8<=0xffffffff,'AIFF exceeds the FORM size limit.')
 local temp,backup=spare(path..'.blt-rm-'),spare(path..'.blt-original-');local input,output
 local ok,err=xpcall(function()
  input=acheck(io.open(source or path,'rb'),'Cannot read AIFF.');output=acheck(io.open(temp,'wb'),'Cannot create AIFF temporary file.')
  acheck(output:write('FORM'..string.pack('>I4',size-8)..w.kind),'AIFF write failed.')
  for _,c in ipairs(w.chunks)do if not c.remove and not(crop and c.id=='PEAK')then
   if crop and c==w.data then
    acheck(output:write('SSND'..string.pack('>I4I4I4',8+bytes,0,0)),'AIFF write failed.')
    copy_audio(input,output,w.audioOffset+pre*w.align,bytes)
    if bytes%2~=0 then acheck(output:write('\0'),'AIFF write failed.')end
   elseif crop and c.id=='COMM'then
    input:seek('set',c.offset);local d=exact(input,14)
    acheck(output:write(d:sub(1,10)..string.pack('>I4',frames)),'AIFF write failed.');copy_audio(input,output,c.offset+14,c.total-14)
   elseif c.replacement then acheck(output:write(c.replacement),'AIFF comment write failed.')
   else copy_audio(input,output,c.offset,c.total)end
  end end
  acheck(output:write(blob),'AIFF metadata write failed.');acheck(output:close(),'AIFF close failed.');output=nil;input:close();input=nil
  local v=Embed.scan_aiff(temp);acheck(v.sr==w.sr and v.frames==frames and v.size==size,'AIFF verification failed.')
  local f=acheck(io.open(temp,'rb'),'Cannot verify AIFF metadata.');local parts={}
  local yes,e=pcall(function()for _,c in ipairs(v.chunks)do if c.remove then f:seek('set',c.offset);parts[#parts+1]=f:read(c.total)end end;acheck(table.concat(parts)==blob,'AIFF metadata verification failed.')end);f:close();acheck(yes,e)
  replace_output(path,temp,backup)
 end,tostring)
 if input then pcall(function()input:close()end)end;if output then pcall(function()output:close()end)end
 if not ok then if exists(temp)then os.remove(temp)end;error(err,0)end
end

local Model={VERSION='0.14.15',SOURCE_MASK=1|2|8|32|64|128|4096}
Model.numbers={'RENDER_SETTINGS','RENDER_BOUNDSFLAG','RENDER_CHANNELS','RENDER_SRATE','RENDER_STARTPOS','RENDER_ENDPOS','RENDER_TAILFLAG','RENDER_TAILMS','RENDER_ADDTOPROJ','RENDER_DITHER','RENDER_NORMALIZE','RENDER_NORMALIZE_TARGET','RENDER_BRICKWALL','RENDER_FADEIN','RENDER_FADEOUT','RENDER_FADEINSHAPE','RENDER_FADEOUTSHAPE','RENDER_FADELPF','RENDER_PADSTART','RENDER_PADEND','RENDER_TRIMSTART','RENDER_TRIMEND','RENDER_DELAY'}
Model.strings={'RENDER_FILE','RENDER_PATTERN','RENDER_EXTRAFILEDIR','RENDER_FORMAT2','RENDER_FORMAT'}
Model.configs={'projrenderlimit','projrenderspeedcap','projrenderresample','projrenderrateinternal','renderclosewhendone','renderpeaks','projrenderqdelay','renderbsnew'}
function Model.render_features(api)
 if Model.featureAPI==api then return end
 local version=api.GetAppVersion and api.GetAppVersion()or''
 local major,minor=version:match('^(%d+)%.(%d+)');major,minor=tonumber(major)or 0,tonumber(minor)or 0
 Model.render783=major>7 or major==7 and minor>=83;Model.featureAPI=api
end
function Model.complete_render_options(api,state)
 for _,key in ipairs({'projrenderspeedcap','renderpeaks'})do
  if state.c[key]==nil and api.SNM_GetIntConfigVar then
   local value=api.SNM_GetIntConfigVar(key,-2147483648)
   if value and value~=-2147483648 then state.c[key]=key=='projrenderspeedcap'and 1 or value end
  end
 end
 return state
end
do
local speeds={{'フルスピード・オフライン',0},{'1倍速・オフライン',1},{'オンライン',2},{'オンライン（アイドル）',3},{'1倍速・オフライン（アイドル）',4}}
local speeds783={{'フルスピード・オフライン',0},{'1倍速・オフライン',1},{'2倍速・オフライン','1:2'},
 {'オンライン',2},{'オンライン（アイドル）',3},{'1倍速・オフライン（アイドル）',4},{'2倍速・オフライン（アイドル）','4:2'}}
function Model.speedchoices(s)return Model.render783 and s.c.projrenderspeedcap~=nil and speeds783 or speeds end
function Model.speedchoice(s)
 local speed=s.c.projrenderlimit
 return (speed==1 or speed==4)and(s.c.projrenderspeedcap or 1)>=2 and(speed..':2')or speed
end
function Model.setspeed(s,value)
 local speed,cap=value,1
 if value=='1:2'or value=='4:2'then
  if not Model.render783 or s.c.projrenderspeedcap==nil then return false end
  speed,cap=tonumber(value:sub(1,1)),2
 elseif type(value)~='number'or value%1~=0 or value<0 or value>4 then return false end
 s.c.projrenderlimit=speed
 if s.c.projrenderspeedcap~=nil then s.c.projrenderspeedcap=cap end
 return true
end
end
function Model.configbits(s,key,mask,value)
 local current=s.c[key]
 if current==nil then return false end
 s.c[key]=(current&~mask)|(value&mask);return true
end
function Model.graphchoice(s)
 local flags=s.c.renderpeaks or 0
 return(flags&32)~=0 and 32 or(flags&16)~=0 and 16 or 0
end
function Model.loudnesschoice(s)
 local flags=s.c.renderclosewhendone or 0
 return(flags&8192)~=0 and 8192 or(flags&1536)~=0 and 1536 or 0
end
Model.sources={{'マスターミックス',0},{'マスター＋選択トラックのステム',1},{'選択トラックのステム',3},{'選択メディアアイテム',32},{'選択メディアアイテム・マスター経由',64},{'選択トラック・マスター経由',128},{'リージョン・レンダーマトリックス',8},{'リージョン・レンダーマトリックス・マスター経由',136},{'レイザー編集領域',4096},{'レイザー編集領域・マスター経由',4224}}
for _,v in ipairs({{'選択メディアアイテムを1ファイルに結合',32|(4<<16)},{'選択メディアアイテム・マスター経由を1ファイルに結合',64|(4<<16)},{'レイザー編集領域を1ファイルに結合',4096|(4<<16)},{'レイザー編集領域・マスター経由を1ファイルに結合',4224|(4<<16)}})do Model.sources[#Model.sources+1]=v end
Model.bounds={{'カスタム時間範囲',0},{'プロジェクト全体',1},{'時間選択',2},{'全リージョン',3},{'選択メディアアイテム',4},{'選択リージョン',5},{'全マーカー',6},{'選択マーカー',7}}
Model.channelFallbacks={{'defaultChannels','default_channels','デフォルトカラー（色未設定）'},{'otherChannels','other_channels','その他（カスタム色ではない色指定）'}}
Model.appkeys={'auto','colorMap','defaultChannels','otherChannels','embed','itemEmbedChannels','excludeFolderContents','excludeUnnamedItems'}
Model.formats={{'WAV','evaw'},{'AIFF','ffia'},{'FLAC','calf'},{'MP3 (LAME)','l3pm'}}
function Model.enumerate_formats(api)
 if Model.formatsAPI==api then return end
 if not api.PCM_Sink_Enum then return end
 local out={}
 for i=0,127 do local id,name=api.PCM_Sink_Enum(i);if not id or id==0 then break end
  out[#out+1]={name,string.pack('<I4',id & 0xffffffff)}
 end
 if #out>0 then Model.formats=out;Model.formatsAPI=api end
end
local function clone(v)if type(v)~='table'then return v end;local o={};for k,x in pairs(v)do o[k]=clone(x)end;return o end
Model.clone=clone
local function ensure(ok,msg)if not ok then error(msg,0)end;return ok end
function Model.load(api)
 Model.render_features(api)
 Model.enumerate_formats(api);Model.enumerate_resamplers(api)
 local p=api.EnumProjects(-1,'');local s={n={},s={},c={},meta={},auto=false}
 for _,k in ipairs(Model.numbers)do s.n[k]=api.GetSetProjectInfo(p,k,0,false)end
 for _,k in ipairs(Model.strings)do local ok,v=api.GetSetProjectInfo_String(p,k,'',false);ensure(ok,'設定取得失敗：'..k);s.s[k]=v end
 for _,k in ipairs(Model.configs)do local v=api.SNM_GetIntConfigVar and api.SNM_GetIntConfigVar(k,-2147483648);if v and v~=-2147483648 then s.c[k]=v end end
 local ok,keys=api.GetSetProjectInfo_String(p,'RENDER_METADATA','',false)
 if ok then for k in keys:gmatch('[^;]+')do local yes,v=api.GetSetProjectInfo_String(p,'RENDER_METADATA',k,false);if yes then s.meta[k]=v end end end
 s.colorMap=Model.readmap(api);for _,v in ipairs(Model.channelFallbacks)do s[v[1]]=Model.readchanneldefault(api,v[2])end;s.embed=Model.readembed(api);return {project=p,state=s,base=clone(s)}
end
do
Model.resamplers={{'Sinc · 64pt',0},{'Linear',1},{'Point sampling',2},{'Sinc · 192pt',3},{'Sinc · 384pt',4},{'Linear + IIR',5},{'Linear + IIR×2',6},{'Sinc · 16pt',7},{'Sinc · 512pt',8},{'Sinc · 768pt',9},{'r8brain free',10}}
function Model.enumerate_resamplers(api)
 if Model.resampleAPI==api or not api.Resample_EnumModes then return end
 local modes={}
 for i=0,63 do local name=api.Resample_EnumModes(i);if not name or name==''then break end;modes[#modes+1]={name,i}end
 if #modes>0 then Model.resamplers=modes;Model.resampleAPI=api end
end
end
function Model.source(s)return s.n.RENDER_SETTINGS & Model.SOURCE_MASK end
function Model.sourcechoice(s)
 local v=Model.source(s);local flags=s.n.RENDER_SETTINGS
 if(flags&(4<<16))~=0 and(Model.itemsource(s)or Model.razorsource(s))then return v|(4<<16)end
 return v
end
function Model.itemsource(s)local v=Model.source(s);return v==32 or v==64 end
function Model.matrixsource(s)return(Model.source(s)&8)~=0 end
function Model.razorsource(s)return(Model.source(s)&4096)~=0 end
function Model.autosupported(s)
 local v=Model.source(s)
 if v==4096 or v==4224 then return(s.n.RENDER_SETTINGS&(4<<16))==0 end
 return v==1 or v==3 or v==32 or v==64 or v==128 or v==8 or v==136
end
function Model.autoactive(s)return s.auto and Model.autosupported(s)end
function Model.combined(s)return(Model.itemsource(s)or Model.razorsource(s))and(s.n.RENDER_SETTINGS&(4<<16))~=0 end
function Model.viamaster(s)local v=Model.source(s);return not Model.combined(s)and(v==64 or(v&128)~=0)end
do
local matrixBounds={{'全リージョン',3},{'選択リージョン',5}}
local razorBounds={{'レイザー編集領域',4}}
local itemBounds={{'選択メディアアイテム',4}}
local timeBounds={};for _,v in ipairs(Model.bounds)do if v[2]~=4 then timeBounds[#timeBounds+1]=v end end
function Model.boundchoices(s)
 return Model.matrixsource(s)and matrixBounds or Model.razorsource(s)and razorBounds or Model.itemsource(s)and itemBounds or timeBounds
end
end
function Model.setsource(s,v)
 s.n.RENDER_SETTINGS=(s.n.RENDER_SETTINGS & ~(Model.SOURCE_MASK|(4<<16)))|v
 v=v&Model.SOURCE_MASK
 if (v&8)~=0 then if s.n.RENDER_BOUNDSFLAG~=3 and s.n.RENDER_BOUNDSFLAG~=5 then s.n.RENDER_BOUNDSFLAG=3 end
 elseif v==32 or v==64 or(v&4096)~=0 then s.n.RENDER_BOUNDSFLAG=4 elseif s.n.RENDER_BOUNDSFLAG==4 then s.n.RENDER_BOUNDSFLAG=1 end
end
function Model.valid(s)
 if type(s)~='table' or type(s.n)~='table' or type(s.s)~='table' or type(s.c)~='table' or type(s.meta)~='table' or type(s.auto)~='boolean'then return false end
 if s.colorMap~=nil then if type(s.colorMap)~='table'then return false end;for i=1,16 do local v=s.colorMap[i];if type(v)~='number'or v%1~=0 or v< -1 or v>128 then return false end end end
 for _,k in ipairs({'excludeFolderContents','excludeUnnamedItems'})do if s[k]~=nil and type(s[k])~='boolean'then return false end end
 if s.itemEmbedChannels~=nil then local v=s.itemEmbedChannels;if type(v)~='number'or v%1~=0 or v<3 or v>128 then return false end end
 for _,row in ipairs(Model.channelFallbacks)do local v=s[row[1]];if v~=nil and(type(v)~='number'or v%1~=0 or v< -1 or v>128)then return false end end
 if s.embed~=nil then if type(s.embed)~='table'or(s.embed.encoding~='UTF-8'and s.embed.encoding~='CP932')then return false end;for _,k in ipairs({'embed_markers','embed_regions','embed_loop_region','exclude_selected_region'})do if type(s.embed[k])~='boolean'then return false end end end
 for _,k in ipairs(Model.numbers)do local n=s.n[k];if type(n)~='number' or n~=n or math.abs(n)==math.huge then return false end end
 for _,k in ipairs(Model.strings)do if type(s.s[k])~='string' or #s.s[k]>1048576 then return false end end
 if s.n.RENDER_CHANNELS<1 or s.n.RENDER_CHANNELS>128 or s.n.RENDER_CHANNELS%1~=0 then return false end
 if s.n.RENDER_SRATE<0 or s.n.RENDER_SRATE>768000 then return false end
 if s.n.RENDER_BOUNDSFLAG==0 and s.n.RENDER_ENDPOS<=s.n.RENDER_STARTPOS then return false end
 for _,k in ipairs(Model.configs)do local v=s.c[k];if v~=nil and (type(v)~='number' or v%1~=0 or math.abs(v)>2147483647)then return false end end
 for k,v in pairs(s.meta)do if type(k)~='string' or type(v)~='string' or k:find('[|;\r\n]')then return false end end
 return true
end
function Model.apply(api,m)
 ensure(api.EnumProjects(-1,'')==m.project,'別のプロジェクトに切り替わっています。「再読込」を押してください。')
 local before=Model.load(api);local s=m.state;local b=m.base or clone(before.state);local undo={}
 local current=before.state.c
 local speedChanged=s.c.projrenderlimit~=b.c.projrenderlimit or s.c.projrenderspeedcap~=b.c.projrenderspeedcap
 local nativeSpeedChanged=current.projrenderlimit~=b.c.projrenderlimit or current.projrenderspeedcap~=b.c.projrenderspeedcap
 local sameSpeed=s.c.projrenderlimit==current.projrenderlimit and s.c.projrenderspeedcap==current.projrenderspeedcap
 ensure(not(speedChanged and nativeSpeedChanged and not sameSpeed),'REAPER側でも同じ設定が変更されています。再読込してください：projrenderlimit / projrenderspeedcap')

 for _,group in ipairs({'n','s','c','meta'})do
  local keys={};for k in pairs(b[group])do keys[k]=true end;for k in pairs(before.state[group])do keys[k]=true end;for k in pairs(s[group])do keys[k]=true end
  for k in pairs(keys)do
   local live=before.state[group][k]
   if s[group][k]==b[group][k]then s[group][k]=live;b[group][k]=live
   elseif live~=b[group][k]and live~=s[group][k]then error('REAPER側でも同じ設定が変更されています。再読込してください：'..k,0)end
  end
 end
 ensure(Model.valid(m.state),'設定値を確認してください。カスタム範囲は終了を開始より後にしてください。')
 local function put(f,back)undo[#undo+1]=back;f()end
 local ok,err=xpcall(function()
  for _,k in ipairs(Model.numbers)do if s.n[k]~=b.n[k]then
   put(function()api.GetSetProjectInfo(m.project,k,s.n[k],true)end,function()api.GetSetProjectInfo(m.project,k,before.state.n[k],true)end)
  end end
  for _,k in ipairs(Model.configs)do if s.c[k]~=b.c[k] and s.c[k]~=nil then
   ensure(api.SNM_SetIntConfigVar,'この項目の変更にはSWSが必要です。')
   put(function()ensure(api.SNM_SetIntConfigVar(k,s.c[k]),'設定変更失敗：'..k)end,function()api.SNM_SetIntConfigVar(k,before.state.c[k])end)
  end end
  local all={};for k in pairs(b.meta)do all[k]=true end;for k in pairs(s.meta)do all[k]=true end
  for k in pairs(all)do if s.meta[k]~=b.meta[k]then
   put(function()ensure(api.GetSetProjectInfo_String(m.project,'RENDER_METADATA',k..'|'..(s.meta[k] or ''),true),'メタデータ変更失敗：'..k)end,function()api.GetSetProjectInfo_String(m.project,'RENDER_METADATA',k..'|'..(before.state.meta[k] or ''),true)end)
  end end
  for _,k in ipairs(Model.strings)do if s.s[k]~=b.s[k]then
   put(function()ensure(api.GetSetProjectInfo_String(m.project,k,s.s[k],true),'設定変更失敗：'..k)end,function()api.GetSetProjectInfo_String(m.project,k,before.state.s[k],true)end)
  end end

 end,tostring)
 if not ok then local errors={};for i=#undo,1,-1 do local good,e=pcall(undo[i]);if not good then errors[#errors+1]=tostring(e)end end;error(err..(#errors>0 and '\n復元失敗：'..table.concat(errors,'\n') or ''),0)end
 m.base=clone(s)
end
do
local alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local decoded,decodedCount={},0
function Model.decode(s)
 if #s==4 then return s end
 if decoded[s]then return decoded[s]end
 local out,bits,v={},0,0
 for c in s:gmatch('.')do local i=alphabet:find(c,1,true);if i then v=(v<<6)|(i-1);bits=bits+6;if bits>=8 then bits=bits-8;out[#out+1]=string.char((v>>bits)&255);v=v&((1<<bits)-1)end end end
 local value=table.concat(out)
 if #s<=4096 then
  if decodedCount>=32 then decoded,decodedCount={},0 end
  decoded[s]=value;decodedCount=decodedCount+1
 end
 return value
end
function Model.encode(s)
 local out,bits,v={},0,0
 for i=1,#s do v=(v<<8)|s:byte(i);bits=bits+8;while bits>=6 do bits=bits-6;local n=(v>>bits)&63;out[#out+1]=alphabet:sub(n+1,n+1)end;v=v&((1<<bits)-1)end
 if bits>0 then local n=(v<<(6-bits))&63;out[#out+1]=alphabet:sub(n+1,n+1)end
 while #out%4~=0 do out[#out+1]='='end;return table.concat(out)
end
end
function Model.formatname(s)
 local id=Model.decode(s):sub(1,4)
 if s==''then return 'なし'end
 for _,v in ipairs(Model.formats)do if id==v[2]then return v[1]end end
 return '現在の形式（標準画面で詳細設定）'
end
function Model.wavbits(s,bits)
 local raw=Model.decode(s);ensure(raw:sub(1,4)=='evaw','WAV形式を選択してください。')
 raw=raw..string.rep('\0',math.max(0,8-#raw))
 return Model.encode(raw:sub(1,4)..string.char(bits)..raw:sub(6))
end

function Model.nativepresets(api)
 local presets={}
 local function tokens(line)
  local t={};local i=1
  while i<=#line do
   while line:sub(i,i):match('%s')do i=i+1 end
   if i>#line then break end
   local q=line:sub(i,i);local start=i
   if q=='"'or q=="'"or q=='`'then
    start=i+1;i=line:find(q,start,true)or(#line+1);t[#t+1]=line:sub(start,i-1);i=i+1
   else while i<=#line and not line:sub(i,i):match('%s')do i=i+1 end;t[#t+1]=line:sub(start,i-1)end
  end;return t
 end
 for _,file in ipairs({'reaper-render.ini','reaper-render2.ini'})do
  local f=io.open(api.GetResourcePath()..'/'..file,'rb')
  if f then local content=f:read('*a');f:close();local current,tag,body,metakey
   for line in (content..'\n'):gmatch('(.-)\r?\n')do
    local t=tokens(line);local kind=t[1]
    if current then
     if kind=='>'then
      if metakey then current.meta[metakey]=table.concat(body);metakey=nil;body={}
      else if tag=='<RENDERPRESET'or tag=='<RENDERPRESET2'then current.s[tag=='<RENDERPRESET'and 'RENDER_FORMAT'or 'RENDER_FORMAT2']=table.concat(body)end;current=nil end
     elseif tag=='<RENDERPRESETMETADATA' then
      if kind=='TAG'then current.meta[t[2]]=t[3]or''elseif kind=='<TAG'then metakey=t[2];body={}elseif metakey then body[#body+1]=line:match('^%s*(.-)%s*$')end
     else body[#body+1]=line:match('^%s*(.-)%s*$')end
    elseif kind and kind:find('RENDERPRESET',1,true)and t[2]then
     local p=presets[t[2]]or{n={},s={},c={},masks={}};presets[t[2]]=p
     local function num(group,key,index)local v=tonumber(t[index]);if v then p[group][key]=v end end
     if kind=='<RENDERPRESET'then
      num('n','RENDER_SRATE',3);num('n','RENDER_CHANNELS',4);num('c','projrenderlimit',5);num('c','projrenderrateinternal',6);num('c','projrenderresample',7);num('n','RENDER_DITHER',8)
      if Model.render783 then p.c.projrenderspeedcap=tonumber(t[10])or 1 end
      if tonumber(t[9])then p.masks[#p.masks+1]={0x6F14|32768|(1<<16)|(2<<16)|(16<<16),tonumber(t[9])}end

      p.n.RENDER_FADELPF=0
      p.s.RENDER_FORMAT2='';current=p;tag=kind;body={}
     elseif kind=='<RENDERPRESET2'then current=p;tag=kind;body={}
     elseif kind=='RENDERPRESET_OUTPUT'then
      num('n','RENDER_BOUNDSFLAG',3);num('n','RENDER_STARTPOS',4);num('n','RENDER_ENDPOS',5)
      if tonumber(t[6])then p.masks[#p.masks+1]={0x10EB|(4<<16)|(8<<16),tonumber(t[6])}end
      p.s.RENDER_PATTERN=t[8]or'';p.n.RENDER_TAILFLAG=tonumber(t[9])==1 and 255 or 0
      if t[10]and(t[10]~=''or(tonumber(t[14])or 0)>0)then p.s.RENDER_FILE=t[10]end;num('n','RENDER_TAILMS',11)
      if t[13]~=nil then p.s.RENDER_EXTRAFILEDIR=t[13]end
     elseif kind=='RENDERPRESET_EXT'then
      for i,key in ipairs({'RENDER_NORMALIZE','RENDER_NORMALIZE_TARGET','RENDER_BRICKWALL','RENDER_FADEIN','RENDER_FADEOUT','RENDER_FADEINSHAPE','RENDER_FADEOUTSHAPE','RENDER_TRIMSTART','RENDER_TRIMEND','RENDER_PADSTART','RENDER_PADEND'})do num('n',key,i+2)end
     elseif kind=='<RENDERPRESETMETADATA'then p.meta={};current=p;tag=kind;body={}end
    end
   end
  end
 end

 for _,p in pairs(presets)do
  if p.s.RENDER_FORMAT and p.n.RENDER_NORMALIZE==nil then p.n.RENDER_NORMALIZE=4<<16 end
 end
 return presets
end
function Model.loadpreset(s,p)
 local draft=clone(s);if p.n.RENDER_CHANNELS~=nil then draft.auto=false end
 for _,g in ipairs({'n','s','c'})do for k,v in pairs(p[g])do draft[g][k]=v end end
 for _,pair in ipairs(p.masks)do draft.n.RENDER_SETTINGS=(draft.n.RENDER_SETTINGS&~pair[1])|(pair[2]&pair[1])end
 if p.meta then draft.meta=clone(p.meta)end

 for _,key in ipairs({'RENDER_FORMAT','RENDER_FORMAT2'})do
  if p.s[key]then
   local raw=Model.decode(p.s[key])
   if raw:sub(1,4)=='evaw'and(#raw==4 or #raw>=7)then
    local flags=raw:byte(6)or 0;local mode=((flags&8)~=0 and 1 or 0)+((flags&16)~=0 and 1 or 0)+((flags&64)~=0 and 2 or 0)+((flags&128)~=0 and 4 or 0)
    if mode<=6 then
     draft.embed=draft.embed or Embed.defaults()
     draft.embed.embed_markers=mode>=1 and mode<=4
     draft.embed.embed_regions=mode==1 or mode==2 or mode==5 or mode==6
     draft.embed.marker_hash_only=mode==2 or mode==4
     draft.embed.region_hash_only=mode==2 or mode==6
    end
    break
   end
  end
 end
 local supported=false;for _,v in ipairs(Model.sources)do if v[2]==Model.sourcechoice(draft)then supported=true end end
 ensure(supported,'未対応のソース値を使用しているプリセットです。')
 ensure(Model.valid(draft),'プリセットの設定値を確認してください。')
 return draft
end
do
local depthChoices={
 evaw={{'8 bit PCM',8},{'16 bit PCM',16},{'24 bit PCM',24},{'32 bit float',32},{'64 bit float',64},{'32 bit PCM',33}},
 ffia={{'8 bit PCM',8},{'16 bit PCM',16},{'24 bit PCM',24},{'32 bit PCM',32}},calf={}}
for bits=24,16,-1 do depthChoices.calf[#depthChoices.calf+1]={bits..' bit',bits}end
local noDepths={}
function Model.depthchoices(codec)return depthChoices[codec]or noDepths end
end
Model.fadeShapes={{'Linear',0},{'Inverted quadratic',1},{'Quadratic',2},{'Inverted quartic',3},{'Quartic',4},{'Cosine S-curve',5},{'Quartic S-curve',6}}
function Model.setdepth(s,bits)
 local raw=Model.decode(s);local codec=raw:sub(1,4);local allowed=false
 for _,v in ipairs(Model.depthchoices(codec))do if v[2]==bits then allowed=true end end
 ensure(allowed,'この形式では使用できないビット深度です。')
 if codec=='evaw'then return Model.wavbits(s,bits)end
 if codec=='calf'and #raw<12 then raw=codec..string.pack('<I4I4',24,5)end
 if codec=='ffia'and #raw<7 then raw=codec..string.char(24,0,0)end
 return Model.encode(raw:sub(1,4)..string.char(bits)..raw:sub(6))
end
function Model.channelmax(codec)
 if codec=='l3pm'or codec==' osi'or codec==' pdd'then return 2 end
 if codec=='calf'or codec=='SggO'then return 8 end
 return 128
end

do
local persisted=setmetatable({},{__mode='k'})
local function read_setting(api,key)
 local value=api.GetExtState('BLT_DEDICATED_RENDER',key)
 local cache=persisted[api];if not cache then cache={};persisted[api]=cache end
 cache[key]=value;return value
end
local function store_setting(api,key,value)
 local cache=persisted[api]
 if not cache or cache[key]==nil then read_setting(api,key);cache=persisted[api]end
 if cache[key]~=value then api.SetExtState('BLT_DEDICATED_RENDER',key,value,true);cache[key]=value end
end
function Model.defaultmap()local map={};for i=1,16 do map[i]=0 end;return map end
function Model.factory(state)
 local s=clone(state);s.n.RENDER_SETTINGS=s.n.RENDER_SETTINGS&~2048;s.colorMap=Model.defaultmap()
 for _,v in ipairs(Model.channelFallbacks)do s[v[1]]=0 end
 return s
end
function Model.readmap(api)
 local map=Model.defaultmap()
 local raw=api.GetExtState and read_setting(api,'color_mapping')or''
 local values={};for v in raw:gmatch('[^,]+')do values[#values+1]=tonumber(v)end
 if #values==16 then local valid=true;for _,v in ipairs(values)do if type(v)~='number'or v%1~=0 or v< -1 or v>128 then valid=false end end;if valid then map=values end end
 return map
end
function Model.readchanneldefault(api,key)
 local v=tonumber(api.GetExtState and read_setting(api,key)or'')
 return v and v%1==0 and v>= -1 and v<=128 and v or 0
end
function Model.persistmap(api,state)
 if not api.SetExtState then return end
 for _,v in ipairs(Model.channelFallbacks)do store_setting(api,v[2],tostring(state[v[1]]or 0))end
 if state.colorMap then store_setting(api,'color_mapping',table.concat(state.colorMap,','))end
end
function Model.embedsupported(s,path)
 for _,key in ipairs({'RENDER_FORMAT','RENDER_FORMAT2'})do
  local raw=Model.decode(s.s[key]);local codec=raw:sub(1,4)
  if codec=='ffia'and(not path or not path:lower():match('%.wav$'))then return true end
  if codec=='evaw'and(not path or path:lower():match('%.wav$'))then
   local bits=raw:byte(5)or 24;local large=raw:byte(7)or 0
   if large~=2 and(bits==8 or bits==16 or bits==24 or bits==32 or bits==33 or bits==64)then return true end
  end
 end
 return false
end
do
local sourceOptions={4,16,16384,8192,8<<16,4<<16,1<<16,2<<16,32768,256,1024}
function Model.optionenabled(s,key,mask)
 local source=Model.source(s)
 if key=='RENDER_SETTINGS'then
  if mask==4<<16 then return Model.itemsource(s)or Model.razorsource(s)end
  if mask==8<<16 then return Model.viamaster(s)end
  if mask==8192 then return source~=0 and not Model.viamaster(s)and not Model.combined(s)end
  if mask==4 or mask==16 or mask==16384 then return source~=0 and not Model.viamaster(s)and not Model.combined(s)and not Model.autoactive(s)end
  if mask==1<<16 or mask==2<<16 or mask==32768 then
   if not Model.itemsource(s)and not Model.razorsource(s)or Model.combined(s)then return false end
   if mask==2<<16 and(s.n.RENDER_NORMALIZE&(4<<16))==0 then
    local norm=s.n.RENDER_NORMALIZE
    if(norm&1)~=0 and(norm&32)~=0 or(norm&64)~=0 and(norm&(32<<16))~=0 then return false end
   end
  elseif mask==256 or mask==1024 then return Model.embedsupported(s)end
 elseif key=='RENDER_DITHER'and(mask==4 or mask==8)then
  return source~=0 and not Model.viamaster(s)and not Model.combined(s)
 elseif key=='RENDER_NORMALIZE'then
  if mask==1 then return not Model.viamaster(s)or(s.n.RENDER_NORMALIZE&(16<<16))==0 end
  if mask==64 or mask==128 then return not Model.viamaster(s)or(s.n.RENDER_NORMALIZE&(64<<16))==0 end
 end
 return true
end
function Model.postchoice(s,key,mask,value)
 return key~='RENDER_NORMALIZE'or not Model.viamaster(s)or(mask~=(32|4096|(16<<16))or(value&(16<<16))==0)and(mask~=((32<<16)|(64<<16))or(value&(64<<16))==0)
end
function Model.effective(s)
 local result=clone(s);result.auto=Model.autoactive(s)
 for _,mask in ipairs(sourceOptions)do if not Model.optionenabled(s,'RENDER_SETTINGS',mask)then result.n.RENDER_SETTINGS=result.n.RENDER_SETTINGS&~mask end end
 for _,mask in ipairs({1,64})do if not Model.optionenabled(s,'RENDER_NORMALIZE',mask)then result.n.RENDER_NORMALIZE=result.n.RENDER_NORMALIZE&~(mask|(mask==1 and(16<<16)or(64<<16)))end end
 for _,mask in ipairs({4,8})do if not Model.optionenabled(s,'RENDER_DITHER',mask)then result.n.RENDER_DITHER=result.n.RENDER_DITHER&~mask end end
 return result
end
end
Embed.accepts=Model.embedsupported
function Model.closeafter(s)return ((s.c.renderclosewhendone or 0)&1)~=0 and((s.c.renderclosewhendone or 0)&16384)==0 end
function Model.setcloseafter(s,on)s.c.renderclosewhendone=((s.c.renderclosewhendone or 0)&~(1|16384))|(on and 1 or 0)end
function Model.readembed(api)
 if type(api.EnumProjectMarkers3)~='function'then return nil end
 local e=Embed.defaults();local raw=api.GetExtState and read_setting(api,'embedding')or''
 local a,b,c,d,enc,mh,rh=raw:match('^([01]),([01]),([01]),([01]),([^,]+),([01]),([01])$')
 if a and(enc=='UTF-8'or enc=='CP932')then e={embed_markers=a=='1',embed_regions=b=='1',embed_loop_region=c=='1',exclude_selected_region=d=='1',encoding=enc,marker_hash_only=mh=='1',region_hash_only=rh=='1'}end
 return e
end
function Model.persistembed(api,state)
 local e=state.embed;if not e or not api.SetExtState then return end
 local fields={};for _,k in ipairs({'embed_markers','embed_regions','embed_loop_region','exclude_selected_region'})do fields[#fields+1]=e[k]and'1'or'0'end;fields[#fields+1]=e.encoding
 fields[#fields+1]=e.marker_hash_only and'1'or'0';fields[#fields+1]=e.region_hash_only and'1'or'0'
 local value=table.concat(fields,',')
 store_setting(api,'embedding',value)
end
end
Model.Embed=Embed;Model.LoopMetadata=LoopMetadata

Model.ITEM_CHANNEL_KEY='P_EXT:BLT_DEDICATED_RENDER_CHANNELS'
local function item_channel_data(api,item)
 local _,raw=api.GetSetMediaItemInfo_String(item,Model.ITEM_CHANNEL_KEY,'',false)

 if raw==nil then return ''end
 return raw
end
function Model.itemchannels(api,item)
 local raw=item_channel_data(api,item)
 if raw==''then return nil end
 local value=tonumber(raw)
 ensure(value and value%1==0 and value>=1 and value<=128,'アイテムのチャンネル設定が不正です。再設定してください。')
 return value
end
local function write_item_channels(api,item,raw)

 api.GetSetMediaItemInfo_String(item,Model.ITEM_CHANNEL_KEY,raw,true)
 ensure(item_channel_data(api,item)==raw,'アイテムへのチャンネル設定の保存に失敗しました。')
end
function Model.setitemchannels(api,project,channels)
 ensure(api.EnumProjects(-1,'')==project,'別のプロジェクトです。REAPER設定を読込してください。')
 ensure(channels==nil or(type(channels)=='number'and channels%1==0 and channels>=1 and channels<=128),'チャンネル数は1～128の整数で指定してください。')
 local entries={}
 for i=0,api.CountSelectedMediaItems(project)-1 do
  local item=api.GetSelectedMediaItem(project,i)
  entries[#entries+1]={item=item,old=item_channel_data(api,item)}
 end
 if #entries==0 then return 0 end
 api.Undo_BeginBlock2(project);api.PreventUIRefresh(1)
 local applied={};local ok,err=xpcall(function()
  for _,entry in ipairs(entries)do
   applied[#applied+1]=entry
   write_item_channels(api,entry.item,channels and tostring(channels)or'')
  end
 end,tostring)
 local errors={}
 if not ok then for _,entry in ipairs(applied)do
  local restored=pcall(write_item_channels,api,entry.item,entry.old)
  if not restored then errors[#errors+1]='アイテム設定の復元に失敗しました。'end
 end end
 api.PreventUIRefresh(-1);api.Undo_EndBlock2(project,channels and'BLT: Set item render channels'or'BLT: Clear item render channels',4);api.UpdateArrange()
 ensure(ok,tostring(err)..(#errors>0 and '\n'..table.concat(errors,'\n')or''))
 return #entries
end

function Model.filteritems(api,s,items)
 if not s.excludeFolderContents and not s.excludeUnnamedItems then return items end
 local info={};local folders={}
 for _,item in ipairs(items)do
  local take=api.GetActiveTake(item);local track=api.GetMediaItemTrack(item)
  local name
  if take then name=api.GetTakeName(take)else local _,notes=api.GetSetMediaItemInfo_String(item,'P_NOTES','',false);name=notes end
  local v={item=item,track=track,named=type(name)=='string'and name:find('%S')~=nil}
  if s.excludeFolderContents then
   v.start=api.GetMediaItemInfo_Value(item,'D_POSITION');v.finish=v.start+api.GetMediaItemInfo_Value(item,'D_LENGTH')
   if api.GetMediaTrackInfo_Value(track,'I_FOLDERDEPTH')>0 then folders[#folders+1]=v end
  end
  info[#info+1]=v
 end
 local result={}
 for _,v in ipairs(info)do
  local excluded=s.excludeUnnamedItems and not v.named
  if not excluded and s.excludeFolderContents then
   local ancestors={};local parent=api.GetParentTrack(v.track)
   while parent do ancestors[parent]=true;parent=api.GetParentTrack(parent)end
   for _,folder in ipairs(folders)do
    if ancestors[folder.track]and v.start<folder.finish-1e-9 and v.finish>folder.start+1e-9 then excluded=true;break end
   end
  end
  if not excluded then result[#result+1]=v.item end
 end
 return result
end

local function channel_choices(limit,includeMaster)
 local t=includeMaster and {{'マスターのチャンネル設定',0},{'トラックのチャンネル設定',-1}}or{}
 t.channelLimit=limit or 128
 for i=1,t.channelLimit do t[#t+1]={i==1 and'モノラル'or i==2 and'ステレオ'or(i..' チャンネル'),i}end
 return t
end
Model.channelchoices=channel_choices
local function paths_now(api,p)
 local ok,s=api.GetSetProjectInfo_String(p,'RENDER_TARGETS','',false);ensure(ok,'出力先を取得できません。')
 local t={};for v in (s or''):gmatch('[^;]+')do t[#t+1]=v end;return t
end
local function pathkey(api,s)s=s:gsub('\\','/');return api.GetOS():match('Win')and s:lower()or s end
local function selected(api,p,items)
 local t={};local n=items and api.CountSelectedMediaItems(p)or api.CountSelectedTracks(p)
 for i=0,n-1 do t[#t+1]=items and api.GetSelectedMediaItem(p,i)or api.GetSelectedTrack(p,i)end;return t
end
local function select_only(api,p,list,items)
 local wanted,was={},{};for _,v in ipairs(list)do wanted[v]=true end
 local setter=items and api.SetMediaItemSelected or api.SetTrackSelected
 for _,v in ipairs(selected(api,p,items))do was[v]=true;if not wanted[v]then setter(v,false)end end
 for _,v in ipairs(list)do if not was[v]then setter(v,true)end end
end

local function transaction(api,m,fn,draft,previewOnly)
 ensure(api.EnumProjects(-1,'')==m.project,'別のプロジェクトです。REAPER設定を読込してください。')
 local live=Model.load(api);local selections={}
 local filtering=Model.itemsource(m.state)and(m.state.excludeFolderContents or m.state.excludeUnnamedItems)
 if m.state.auto or filtering then selections.items=selected(api,m.project,true);selections.tracks=selected(api,m.project,false)end
 local originalState=m.state;local scope={};local oldScope=m.scope
 local ok,out=xpcall(function()
  do
   local working={project=m.project,state=Model.effective(m.state),base=clone(draft and m.base or live.state)}

   if draft and previewOnly and live.state.c.renderclosewhendone~=nil then
    local mask=1|16384;local current=live.state.c.renderclosewhendone
    for _,s in ipairs({working.state,working.base})do s.c.renderclosewhendone=((s.c.renderclosewhendone or current)&~mask)|(current&mask)end
   end
   Model.apply(api,working);m.state=working.state
  end
  if m.state.auto then
   if Model.matrixsource(m.state)then scope.regions=Scope.regions(api,m.project)end
   if Model.razorsource(m.state)then scope.razors=Scope.razors(api,m.project)end
  end
  m.scope=scope;local workingSelections=selections
  if filtering then workingSelections={items=Model.filteritems(api,m.state,selections.items),tracks=selections.tracks};select_only(api,m.project,workingSelections.items,true)end
  return fn(workingSelections)
 end,tostring)
 m.state=originalState;m.scope=oldScope
 local errors={};local function attempt(f)local yes,e=pcall(f);if not yes then errors[#errors+1]=tostring(e)end end
 for _,k in ipairs(Model.numbers)do attempt(function()if api.GetSetProjectInfo(m.project,k,0,false)~=live.state.n[k]then api.GetSetProjectInfo(m.project,k,live.state.n[k],true)end end)end
 for _,k in ipairs(Model.configs)do if live.state.c[k]~=nil then attempt(function()if api.SNM_GetIntConfigVar(k,0)~=live.state.c[k]then ensure(api.SNM_SetIntConfigVar(k,live.state.c[k]),'復元失敗：'..k)end end)end end
 local metas={};for k in pairs(live.state.meta)do metas[k]=true end;for k in pairs(m.state.meta)do metas[k]=true end
 for k in pairs(metas)do attempt(function()local _,v=api.GetSetProjectInfo_String(m.project,'RENDER_METADATA',k,false);if v~=(live.state.meta[k]or'')then ensure(api.GetSetProjectInfo_String(m.project,'RENDER_METADATA',k..'|'..(live.state.meta[k]or''),true),'復元失敗：メタデータ')end end)end
 for _,k in ipairs(Model.strings)do attempt(function()local _,v=api.GetSetProjectInfo_String(m.project,k,'',false);if v~=live.state.s[k]then ensure(api.GetSetProjectInfo_String(m.project,k,live.state.s[k],true),'復元失敗：'..k)end end)end
 attempt(function()Scope.restore(api,m.project,scope.regions,scope.razors)end)
 for k,v in pairs(selections)do attempt(function()select_only(api,m.project,v,k=='items')end)end
 ensure(#errors==0,(ok and''or tostring(out)..'\n')..'設定の復元に失敗しました：'..table.concat(errors,'\n'))
 ensure(ok,out);return out
end
local function jobs_for(api,m,selections)
 local s=m.state;local source=Model.source(s);local jobs={};local by={};local missing,missingSeen={},{}
 local limit=math.min(Model.channelmax(Model.decode(s.s.RENDER_FORMAT):sub(1,4)),Model.channelmax(Model.decode(s.s.RENDER_FORMAT2):sub(1,4)))
 local mergedItems=(source==32 or source==64)and(s.n.RENDER_SETTINGS&(4<<16))~=0
 local function add(src,ch,object,isitem,region)
  ensure(ch and ch%1==0 and ch>=1 and ch<=limit,'設定チャンネル数は出力形式で使用できません（上限 '..limit..' ch）。')
  local id=mergedItems and'items'or(src..':'..ch..':'..(region and region.id or''));local j=by[id]
  if not j then j={source=src,channels=ch,objects={},items=isitem};by[id]=j;jobs[#jobs+1]=j
  elseif mergedItems and ch>j.channels then j.channels=ch end
  if object then j.objects[#j.objects+1]=object end
  if region then j.region=region;j.regions=m.scope.regions end
  return j
 end
 if not Model.autoactive(s)then return {{source=source,channels=s.n.RENDER_CHANNELS}}end
 local masterTrack=api.GetMasterTrack(m.project);local masterValue
 local function master_channels()
  if not masterValue then masterValue=api.GetMediaTrackInfo_Value(masterTrack,'I_NCHAN')end
  return masterValue
 end
 local trackColors,trackChannels={},{}
 local function track_channels(track)
  local ch=trackChannels[track]
  if ch==nil then ch=api.GetMediaTrackInfo_Value(track,'I_NCHAN');trackChannels[track]=ch end
  return ch
 end
 local function track_color(track)
  local color=trackColors[track];if color==nil then color=api.GetTrackColor(track);trackColors[track]=color end;return color
 end
 local function master()add(0,master_channels())end
 if source==0 or source==1 then master()end
 if source==0 then return jobs end
 local isitem=source==32 or source==64;local matrix=(source&8)~=0;local razor=(source&4096)~=0
 local objects=isitem and selections.items or selections.tracks
 if matrix then
  objects={};local anySelected=false
  for _,row in ipairs(m.scope.regions)do if row.isr and row.selected~=0 then anySelected=true end end
  for _,row in ipairs(m.scope.regions)do if row.isr and(s.n.RENDER_BOUNDSFLAG~=5 or not anySelected or row.selected~=0)then
   local i=0;while true do local track=api.EnumRegionRenderMatrix(m.project,row.id,i);if not track then break end
    objects[#objects+1]={track=track,region=row};i=i+1
   end
  end end
 elseif razor then
  objects={};for _,v in ipairs(m.scope.razors)do if #v.areas>0 then objects[#objects+1]=v.track end end
 end

 if razor and(s.n.RENDER_SETTINGS&(4<<16))~=0 then
  local ch=master_channels()
  for _,o in ipairs(objects)do local j=add(source,ch,o,isitem);if razor then j.razors=m.scope.razors;j.keep=j.keep or{};j.keep[o]=true end end
  return jobs
 end
 local itemChannels={}
 if isitem then for _,item in ipairs(objects)do itemChannels[item]=Model.itemchannels(api,item)end end
 local colors,usedColors,objectTracks={},{},{}
 for _,o in ipairs(objects)do
  local track=matrix and o.track or(isitem and api.GetMediaItemTrack(o)or o)
  objectTracks[o]=track
  if not itemChannels[o]and track~=masterTrack then local rgb=track_color(track);if(rgb&0x1000000)~=0 then usedColors[rgb&0xffffff]=true end end
 end
 if next(usedColors)then
  ensure(api.CF_GetCustomColor,'カラー判定にはSWS Extensionが必要です。')
  for i,ch in ipairs(s.colorMap or Model.readmap(api))do
   local rgb=api.CF_GetCustomColor(i-1);ensure(type(rgb)=='number'and rgb>=0,'カスタムカラーを取得できません。')
   rgb=rgb&0xffffff
   if usedColors[rgb]then
    local previous=colors[rgb]

    ensure(not previous or previous<=0 or ch<=0 or previous==ch,'同じ色に異なるチャンネルが設定されています。')
    if previous==nil or ch>0 or(previous==0 and ch==-1)then colors[rgb]=ch end
   end
  end
  for rgb,ch in pairs(colors)do if ch==0 then colors[rgb]=master_channels()end end
 end
 local function addObject(o,ch)
  if matrix then
   add(o.track==masterTrack and 0 or((source&128)~=0 and 128 or 3),ch,o.track~=masterTrack and o.track or nil,false,o.region)
  else
   local j=add(source==1 and 3 or source,ch,o,isitem)
   if razor then j.razors=m.scope.razors;j.keep=j.keep or{};j.keep[o]=true end
  end
 end
 for _,o in ipairs(objects)do
  local track=objectTracks[o];local ch
  if itemChannels[o]then ch=itemChannels[o]
  elseif matrix and track==masterTrack then ch=master_channels()
  else local rgb=track_color(track)
   if(rgb&0x1000000)==0 then
    ch=s.defaultChannels or 0
   else ch=colors[rgb&0xffffff];if ch==nil then ch=s.otherChannels or 0 end end
  end
  if ch==0 then ch=master_channels()end
  if ch==-1 then ch=track_channels(track)end
  if not ch then
   ch=master_channels()
   if not missingSeen[track]then
    missingSeen[track]=true;local _,name=api.GetTrackName(track)
    missing[#missing+1]=(name and name~=''and name or'無名トラック')
   end
  end
  addObject(o,ch)
 end
 return jobs,missing
end
local function activate(api,m,j)
 if m.state.auto then
  if j.razors then Scope.setrazors(api,j.razors,j.keep)
  elseif j.source~=0 then select_only(api,m.project,j.objects,j.items)end
  if j.region then
   Scope.selectregion(api,m.project,j.regions,j.region.id)
   api.GetSetProjectInfo(m.project,'RENDER_BOUNDSFLAG',5,true)
   local tail=m.state.n.RENDER_TAILFLAG
   if m.state.n.RENDER_BOUNDSFLAG==3 then tail=(tail&~32)|((tail&8)~=0 and 32 or 0)end
   api.GetSetProjectInfo(m.project,'RENDER_TAILFLAG',tail,true)
  end
  local flags=m.state.n.RENDER_SETTINGS

  flags=(flags&~(Model.SOURCE_MASK|4|16|16384))|j.source
  if api.GetSetProjectInfo(m.project,'RENDER_SETTINGS',0,false)~=flags then api.GetSetProjectInfo(m.project,'RENDER_SETTINGS',flags,true)end
  if api.GetSetProjectInfo(m.project,'RENDER_CHANNELS',0,false)~=j.channels then api.GetSetProjectInfo(m.project,'RENDER_CHANNELS',j.channels,true)end
 end
end
local function enable_numbering(api)
 local flags=api.SNM_GetIntConfigVar('renderclosewhendone',-1)
 ensure(flags>=0 and api.SNM_SetIntConfigVar('renderclosewhendone',flags|16),'自動連番の設定に失敗しました。')
end
local LoopRender=(function()
local M={}
local function norm(path)return path:gsub('\\','/'):lower()end
local function fail(ok,text)if not ok then error(text,0)end;return ok end
local function present(path)local f=io.open(path,'rb');if f then f:close();return true end end
local function sample_rate(api,p)
 local sr=api.GetSetProjectInfo(p,'RENDER_SRATE',0,false)
 if sr==0 then
  if api.GetSetProjectInfo(p,'PROJECT_SRATE_USE',0,false)~=0 then sr=api.GetSetProjectInfo(p,'PROJECT_SRATE',0,false)
  elseif api.GetAudioDeviceInfo then local ok,value=api.GetAudioDeviceInfo('SRATE');sr=ok and tonumber(value)or 0 end
 end
 fail(type(sr)=='number'and sr>=8000 and sr<=384000 and sr%1==0,'ループ書き出しのサンプルレートを明示指定してください。')
 return sr
end
function M.prepare(api,m,j)
 j.loop=nil
 if not j.embed or not j.embed.options.embed_loop_region then return end
 for _,unit in ipairs(j.embed.units)do if unit.loop then
  fail(not Model.itemsource(m.state)and not Model.razorsource(m.state),'アイテム／レイザー単位では、対象音声を変えずにループ用の前後余裕を追加できないため停止しました。リージョンまたは時間範囲で書き出してください。')
  fail(j.embed.rate==1,'ループ書き出しはプロジェクトの再生速度を1.0にしてください。')
  fail(m.state.n.RENDER_ADDTOPROJ==0,'ループ用の一時音声は尺が長く、自動追加すると配置に影響するため停止しました。「プロジェクトへ追加」をOFFにしてください。')
  if(m.state.n.RENDER_SETTINGS&512)~=0 then for _,value in pairs(m.state.meta)do fail(not value:find('%$[%a_]'),'埋込メタ情報のワイルドカードに一時ファイル名や拡張範囲が入る可能性があるため停止しました。ワイルドカードを固定値へ置き換えてください。')end end
  j.loop=true
 end end
 if j.loop then
  j.loopRate=sample_rate(api,m.project)
  for _,unit in ipairs(j.embed.units)do if unit.loop then
   LoopMetadata.plan(j.embed.rows,unit.start,unit.finish,j.loopRate,j.embed.options)
  end end
 end
end
function M.window(unit,sr,tail)
 local first=math.floor(unit.start*sr+.5)
 local ending=unit.finish+tail;local last=math.floor(ending*sr+.5)
 local guard=math.ceil(.05*sr);local pre=math.min(guard,math.max(0,first))
 return{sr=sr,pre=pre,frames=last-first,rawFrames=pre+last-first+guard,start=(first-pre)/sr,ending=(last+guard)/sr,finish=ending}
end
function M.render(api,m,j,current,numbering)
 local p=m.project
 local numbers={'RENDER_SETTINGS','RENDER_BOUNDSFLAG','RENDER_TAILFLAG','RENDER_NORMALIZE','RENDER_DITHER','RENDER_FADELPF','RENDER_ADDTOPROJ'}
 local strings={'RENDER_FILE','RENDER_PATTERN','RENDER_FORMAT','RENDER_FORMAT2','RENDER_EXTRAFILEDIR'}
 local saved={n={},s={},regions=Scope.regions(api,p),time={api.GetSet_LoopTimeRange2(p,false,false,0,0,false)},loop={api.GetSet_LoopTimeRange2(p,false,true,0,0,false)}}
 for _,k in ipairs(numbers)do saved.n[k]=api.GetSetProjectInfo(p,k,0,false)end
 for _,k in ipairs(strings)do local ok,value=api.GetSetProjectInfo_String(p,k,'',false);fail(ok,'ループ用設定を取得できません：'..k);saved.s[k]=value end
 local temporary,changedRegion={},nil
 local results,indices={},{};for i,path in ipairs(current)do indices[norm(path)]=i end
 local function number(k,v)api.GetSetProjectInfo(p,k,v,true);fail(api.GetSetProjectInfo(p,k,0,false)==v,'ループ用設定を変更できません：'..k)end
 local function text(k,v)fail(api.GetSetProjectInfo_String(p,k,v,true),'ループ用設定を変更できません：'..k)end
 local function region_restore()
  if changedRegion then
   local r=changedRegion
   fail(api.SetProjectMarker3(p,r.id,true,r.start,r.finish,r.raw,r.color),'ループ出力後にリージョンを復元できません。')
   local found=false;for _,v in ipairs(Scope.regions(api,p))do if v.isr and v.id==r.id then found=v.start==r.start and v.finish==r.finish;break end end
   fail(found,'ループ出力後のリージョン範囲が元の位置と一致しません。')
   changedRegion=nil
  end
 end
 local function reset()
  region_restore()
  for _,k in ipairs(numbers)do number(k,saved.n[k])end
  for _,k in ipairs(strings)do text(k,saved.s[k])end
 end
 local function select_region(unit)
  if not unit.row then return end
  for _,r in ipairs(Scope.regions(api,p))do
   local wanted=r.isr==unit.row.isr and r.id==unit.row.id and 1 or 0
   Scope.selection(api,p,r.ptr,wanted,'ループ用の範囲選択を変更できません。')
  end
  number('RENDER_BOUNDSFLAG',unit.row.isr and 5 or 7)
  local bit=(saved.n.RENDER_BOUNDSFLAG==3 or saved.n.RENDER_BOUNDSFLAG==6)and 8 or 32
  number('RENDER_TAILFLAG',(saved.n.RENDER_TAILFLAG&~32)|((saved.n.RENDER_TAILFLAG&bit)~=0 and 32 or 0))
 end
 local function native(expected)
  local wanted={};for _,path in ipairs(expected)do wanted[norm(path)]=true end
  local ok,stats=api.GetSetProjectInfo_String(p,'RENDER_STATS','42230',false);fail(ok,'レンダー結果を取得できません。')
  local paths,seen={},{}
  for path in stats:gmatch('FILE:([^;]+)')do
   local k=norm(path);fail(wanted[k]and not seen[k],'予期しないループ用出力です：'..path)
   seen[k]=true;paths[#paths+1]=path
  end
  return #paths==#expected,stats
 end
 local function eligible(path)return Embed.supported(path)and j.embed.accept(path)end
 local cancelled=false
 local ok,err=xpcall(function()
  for _,unit in ipairs(j.embed.units)do if unit.paths and #unit.paths>0 then
   reset();select_region(unit)
   local dest=paths_now(api,p)
   fail(#dest==#unit.paths,'ループ用の出力数が変わりました。')
   if not numbering then for i,path in ipairs(dest)do fail(norm(path)==norm(unit.paths[i]),'ループ用の出力先が変わりました。')end end
   for _,path in ipairs(dest)do fail(not present(path),'確認後にループの出力先へファイルが現れました：'..path)end
   if unit.loop then
    number('RENDER_NORMALIZE',4<<16);number('RENDER_DITHER',0);number('RENDER_FADELPF',0)
    local cropTargets,other={},false
    for _,path in ipairs(dest)do if eligible(path)then cropTargets[#cropTargets+1]=path else other=true end end
    if other then local done=native(dest);if not done then cancelled=true;break end end
    local formats={}
    for _,k in ipairs({'RENDER_FORMAT','RENDER_FORMAT2'})do
     local raw=Model.decode(saved.s[k]);local codec=raw:sub(1,4)
     if codec=='evaw'or codec=='ffia'then
      local state={s={RENDER_FORMAT=saved.s[k],RENDER_FORMAT2=''}}
      if Model.embedsupported(state)then formats[#formats+1]=saved.s[k]end
     end
    end
    fail(#formats>0,'ループ用のPCM/float出力形式を取得できません。')
    text('RENDER_FORMAT',formats[1]);text('RENDER_FORMAT2',formats[2]or'')
    local directory=fail(cropTargets[1]:match('^(.*)[/\\][^/\\]+$'),'ループ用の保存先を取得できません。')
    text('RENDER_FILE',directory);text('RENDER_EXTRAFILEDIR','')
    text('RENDER_PATTERN','__BLT_LOOP_'..api.genGuid():gsub('[^%w]','')..'_$tracknumber_$track')
    local tailBits={[0]=1,[1]=2,[2]=4,[3]=8,[4]=16,[5]=32,[6]=8,[7]=32}
    local bit=tailBits[api.GetSetProjectInfo(p,'RENDER_BOUNDSFLAG',0,false)]or 1
    local tail=(api.GetSetProjectInfo(p,'RENDER_TAILFLAG',0,false)&bit)~=0 and math.max(0,m.state.n.RENDER_TAILMS)/1000 or 0
    unit.window=M.window(unit,j.loopRate,tail)
    number('RENDER_TAILFLAG',0);number('RENDER_ADDTOPROJ',0)
    local window=unit.window
    if (saved.n.RENDER_SETTINGS&8)~=0 then
     changedRegion=unit.row
     fail(api.SetProjectMarker3(p,unit.row.id,true,window.start,window.ending,unit.row.raw,unit.row.color),'ループ用の一時リージョン範囲を設定できません。')
    else
     number('RENDER_BOUNDSFLAG',2)
     api.GetSet_LoopTimeRange2(p,true,false,window.start,window.ending,false)
     local a,b=api.GetSet_LoopTimeRange2(p,false,false,0,0,false)
     fail(math.abs(a-window.start)*window.sr<.01 and math.abs(b-window.ending)*window.sr<.01,'ループ用の時間選択をサンプル精度で設定できません。')
    end
    local raw=paths_now(api,p);fail(#raw==#cropTargets,'ループ用の出力形式または出力数が変わりました。')
    local unique={}
    for _,path in ipairs(raw)do
     local k=norm(path);fail(not unique[k]and not present(path),'ループ用の一時ファイル名が重複しています。')
     unique[k]=true;temporary[#temporary+1]=path
    end
    local done=native(raw);region_restore()
    if not done then cancelled=true;break end
    local plan={files={},rows=j.embed.rows,options=j.embed.options,rate=1,pad=0}
    for i,path in ipairs(cropTargets)do
     plan.files[norm(path)]=unit
     api.RecursiveCreateDirectory(fail(path:match('^(.*)[/\\][^/\\]+$'),'出力先フォルダーを取得できません。'),0)
     Embed.write(path,plan,raw[i])
     j.embed.finished=j.embed.finished or{};j.embed.finished[norm(path)]=true
    end
   else
    local done=native(dest);if not done then cancelled=true;break end
   end
   for i,path in ipairs(dest)do results[fail(indices[norm(unit.paths[i])],'ループ出力の対応先がありません。')]=path end
  end end
 end,tostring)
 local errors={}
 local function attempt(fn)local done,e=pcall(fn);if not done then errors[#errors+1]=tostring(e)end end
 attempt(reset)
 attempt(function()api.GetSet_LoopTimeRange2(p,true,false,saved.time[1],saved.time[2],false)end)
 attempt(function()api.GetSet_LoopTimeRange2(p,true,true,saved.loop[1],saved.loop[2],false)end)
 attempt(function()
  local wanted={};for _,r in ipairs(saved.regions)do wanted[(r.isr and'r'or'm')..r.id]=r.selected end
  local fresh=Scope.regions(api,p);for _,r in ipairs(fresh)do r.selected=wanted[(r.isr and'r'or'm')..r.id]or r.selected end
  Scope.restore(api,p,fresh)
 end)
 for _,path in ipairs(temporary)do if present(path)then attempt(function()fail(os.remove(path),'ループ用一時ファイルを削除できません：'..path)end)end end
 fail(ok and #errors==0,tostring(err or'')..(#errors>0 and'\n'..table.concat(errors,'\n')or''))
 local stats={};for i=1,#current do if results[i]then stats[#stats+1]='FILE:'..results[i]end end
 fail(cancelled or #stats==#current,'ループ出力の件数が一致しません。')
 return table.concat(stats,';')
end
return M
end)()

local function plan(api,m,selections,embedding,numbering,deferEmbedding,allowDuplicates)
 local jobs,missing=jobs_for(api,m,selections);local all,seen={},{}
 if numbering then enable_numbering(api)end
 for _,j in ipairs(jobs)do
  activate(api,m,j);j.paths=paths_now(api,m.project)
  if embedding and not deferEmbedding and #j.paths>0 then j.embed=Embed.prepare(api,m.state,m.scope and m.scope.regions,numbering,j.paths);LoopRender.prepare(api,m,j)end
  for _,path in ipairs(j.paths)do
   local k=pathkey(api,path)
   ensure(allowDuplicates or numbering or not seen[k],embedding and(Embed.NUMBERING_REQUIRED..path)or('出力ファイル名が重複しています：'..path))
   seen[k]=true;all[#all+1]=path
  end
 end
 return {jobs=jobs,files=all,missing=missing or{}}
end
function Model.relativepath(path,base,windows)
 local function split(value)
  value=value:gsub('\\','/')
  local root=value:match('^%a:/')or value:match('^//[^/]+/[^/]+')or(value:sub(1,1)=='/'and'/'or'')
  local parts={};for part in value:sub(#root+1):gmatch('[^/]+')do
   if part=='..'and #parts>0 and parts[#parts]~='..'then table.remove(parts)
   elseif part~='.'then parts[#parts+1]=part end
  end
  return root,parts
 end
 local function equal(a,b)return windows and a:lower()==b:lower()or a==b end
 local ar,a=split(path);local br,b=split(base)
 if not equal(ar,br)then return path end
 local i=1;while a[i]and b[i]and equal(a[i],b[i])do i=i+1 end
 local out={};for _=i,#b do out[#out+1]='..'end;for j=i,#a do out[#out+1]=a[j]end
 return #out>0 and table.concat(out,'/')or'.'
end
function Model.previewdetails(api,m)
 local project=api.GetProjectPathEx(m.project,'');local base=m.state.s.RENDER_FILE
 if base==''then base=project
 elseif not base:match('^%a:[/\\]')and not base:match('^[/\\]')then base=project..'/'..base end
 local windows=api.GetOS():match('Win')~=nil
 return transaction(api,m,function(selections)
  local result=plan(api,m,selections,false,nil,nil,true);local rows,byPath={},{}
  for _,job in ipairs(result.jobs)do
   local native=not m.state.auto and(m.state.n.RENDER_SETTINGS&(4|16|16384))~=0
   for _,path in ipairs(job.paths)do
    local key=pathkey(api,path);local first=byPath[key]
    local row={path=path,relative=Model.relativepath(path,base,windows),channels=not native and job.channels or nil,duplicate=first~=nil or nil}
    if first then first.duplicate=true else byPath[key]=row end
    rows[#rows+1]=row
   end
  end
  return rows
 end,true,true)
end

function Model.count(api,m)
 ensure(api.EnumProjects(-1,'')==m.project,'別のプロジェクトです。REAPER設定を読込してください。')
 local s=m.state;local source=Model.source(s);local bounds=s.n.RENDER_BOUNDSFLAG
 local items=Model.itemsource(s);local matrix=Model.matrixsource(s);local razor=Model.razorsource(s)
 local selections={items={},tracks={}};local scope={};local count=0
 if items then selections.items=Model.filteritems(api,s,selected(api,m.project,true))end
 if source==1 or source==3 or source==128 then selections.tracks=selected(api,m.project,false)end
 if matrix or(not items and not razor and(bounds==3 or bounds==5 or bounds==6 or bounds==7))then scope.regions=Scope.regions(api,m.project,false)end
 if razor then scope.razors=Scope.razors(api,m.project)end
 local function ranges(isregion,onlySelected)
  local all,chosen={},{}
  for _,v in ipairs(scope.regions or{})do if v.isr==isregion then all[#all+1]=v;if v.selected~=0 then chosen[#chosen+1]=v end end end
  return onlySelected and #chosen>0 and chosen or all
 end
 local rangeCount=1
 if not items and not razor and not matrix then
  if bounds==3 or bounds==5 then rangeCount=#ranges(true,bounds==5)
  elseif bounds==6 or bounds==7 then rangeCount=#ranges(false,bounds==7)
  elseif bounds==0 then rangeCount=s.n.RENDER_ENDPOS>s.n.RENDER_STARTPOS and 1 or 0
  elseif bounds==2 then local a,b=api.GetSet_LoopTimeRange2(m.project,false,false,0,0,false);rangeCount=b>a and 1 or 0
  elseif bounds==1 then rangeCount=api.GetProjectLength(m.project)>0 and 1 or 0 end
 end
 local combined=(s.n.RENDER_SETTINGS&(4<<16))~=0
 local groups={mono=0,stereo=0,multi=0};local factor=s.s.RENDER_FORMAT2~=''and 2 or 1
 local function add(ch,n)
  local key=ch==1 and'mono'or ch==2 and'stereo'or'multi'
  n=n*factor;groups[key]=groups[key]+n;count=count+n
 end
 if Model.autoactive(s)then
  for _,j in ipairs(jobs_for(api,{state=s,project=m.project,scope=scope},selections))do
   local n=0
   if matrix then n=j.source==0 and 1 or #j.objects
   elseif items then n=combined and(#j.objects>0 and 1 or 0)or #j.objects
   elseif razor then
    for _,v in ipairs(j.razors or{})do if j.keep[v.track]then n=n+#v.areas end end
    if combined and n>0 then n=1 end
   else n=rangeCount*(j.source==0 and 1 or #j.objects)end
   add(j.channels,n)
  end
 else
  local n=0
  if matrix then
   for _,row in ipairs(ranges(true,bounds==5))do local i=0;while api.EnumRegionRenderMatrix(m.project,row.id,i)do n=n+1;i=i+1 end end
  elseif razor then
   for _,v in ipairs(scope.razors)do n=n+#v.areas end
   if combined and n>0 then n=1 end
  elseif items then n=combined and(#selections.items>0 and 1 or 0)or #selections.items
  else n=rangeCount*(source==0 and 1 or source==1 and(#selections.tracks+1)or #selections.tracks)end
  add(s.n.RENDER_CHANNELS,n)
 end
 return count,groups
end
local function exists(p)local f=io.open(p,'rb');if f then f:close();return true end;return false end
local function spare(p,suffix)local i=1;while exists(p..suffix..i)do i=i+1 end;return p..suffix..i end
local function numbered_outputs(api,planned,actual,embed,existing)
 local files={}

 for i,path in ipairs(actual)do
  local k,base=pathkey(api,path),pathkey(api,planned[i])
  ensure(not existing[k],'予期しない出力が報告されました：'..path)
  if k~=base then
   local stem,ext=base:match('^(.*)(%.[^./]+)$')
   local outstem,outext=k:match('^(.*)(%.[^./]+)$')
   local valid=false
   if stem and outstem and ext==outext then
    local suffix=outstem:sub(#stem+1)
    valid=outstem:sub(1,#stem)==stem and suffix:match('^[-_ ]%d+$')~=nil
    if not valid then
     local root=stem:match('^(.*)[-_ ]%d+$')
     valid=root and outstem:sub(1,#root)==root and outstem:sub(#root+1):match('^[-_ ]%d+$')~=nil
    end
   end
   ensure(valid,'予期しない出力が報告されました：'..path)
  end
  if embed then
   local unit=embed.files[planned[i]:gsub('\\','/'):lower()]
   if unit then files[path:gsub('\\','/'):lower()]=unit end
  end
 end
 if embed then embed.files=files end
end

local function confirmation(api,m,p)
 local c={files=p.files,conflicts={},missing=p.missing}
 for _,path in ipairs(p.files)do if exists(path)then c.conflicts[#c.conflicts+1]=path end end
 if #c.missing>0 then c.channels=api.GetMediaTrackInfo_Value(api.GetMasterTrack(m.project),'I_NCHAN')end
 c.signature=table.concat(c.files,'\n')..'\0'..table.concat(c.conflicts,'\n')..'\0'..table.concat(c.missing,'\n')..':'..tostring(c.channels)
 return c
end
function Model.render(api,m,kind,approval)
 ensure(kind=='render','この操作はレンダー専用です。')
 local numbering=approval and approval.choice=='number'
 local ok,preflight=pcall(transaction,api,m,function(selection)return plan(api,m,selection,true,numbering,true)end,true)
 if not ok then
  if not numbering and tostring(preflight):sub(1,#Embed.NUMBERING_REQUIRED)==Embed.NUMBERING_REQUIRED then
   return {confirmation={naming=true,conflicts={},missing={},signature='numbering-required'}},false
  end
  error(preflight,0)
 end
 local question=confirmation(api,m,preflight);question.naming=numbering or nil
 if #question.conflicts>0 and(not approval or approval.signature~=question.signature)then return {confirmation=question},false end
 local choice=approval and approval.choice or'overwrite'
 ensure(choice=='number'or choice=='overwrite'or choice=='skip','レンダーの選択肢が無効です。')
 if #question.missing>0 and #question.conflicts==0 then
  local tr=Model.translate or function(v)return v end
  api.MB(string.format(tr('チャンネル未設定のトラックカラーがあります。マスターの %d ch で書き出します。'),question.channels)..'\n\n'..table.concat(question.missing,'\n'),'BLT DEDICATED RENDER',0)
 end
 if m.state.c.renderclosewhendone~=nil then Model.setcloseafter(m.state,Model.closeafter(m.state))end
 Model.apply(api,m)
 local result=transaction(api,m,function(selection)

  local ready,p=pcall(plan,api,m,selection,true,numbering)
  if not ready then
   if not numbering and tostring(p):sub(1,#Embed.NUMBERING_REQUIRED)==Embed.NUMBERING_REQUIRED then
    return {confirmation={naming=true,conflicts={},missing={},signature='numbering-required'}}
   end
   error(p,0)
  end
  local backups={};local result={total=0,failed=0,cancelled=false,skipped=0}
  local currentQuestion=confirmation(api,m,p);currentQuestion.naming=numbering or nil
  if currentQuestion.signature~=question.signature then return {confirmation=currentQuestion}end
  local ok,err=xpcall(function()

   for _,j in ipairs(p.jobs)do
    local allExisting=#j.paths>0;for _,path in ipairs(j.paths)do if not exists(path)then allExisting=false end end
    j.skip=choice=='skip' and allExisting
    if j.skip then result.skipped=result.skipped+#j.paths else
     for _,path in ipairs(j.paths)do if not numbering and exists(path)then
      local b={path=path,backup=spare(path,'.blt-backup-'),keep=choice=='skip'}
      ensure(os.rename(path,b.backup),'既存ファイルを退避できません：'..path);backups[#backups+1]=b
     end end
    end
   end
   for _,j in ipairs(p.jobs)do if not j.skip and #j.paths>0 then
    ensure(api.EnumProjects(-1,'')==m.project,'プロジェクトが切り替わりました。');activate(api,m,j)
    local current=paths_now(api,m.project);ensure(#current==#j.paths,'出力先が変更されました。')
    if numbering then

     local changed=false;for i,path in ipairs(current)do if pathkey(api,path)~=pathkey(api,j.paths[i])then changed=true;break end end
     if changed then j.paths=current;j.embed=Embed.prepare(api,m.state,m.scope and m.scope.regions,true,current);LoopRender.prepare(api,m,j)end
    end
    local expected,existing={},{};for i,path in ipairs(current)do
     ensure(pathkey(api,path)==pathkey(api,j.paths[i]),'出力先が変更されました。')
     if exists(path)then
      ensure(numbering,'確認後に出力先へファイルが現れました：'..path);existing[pathkey(api,path)]=true
     end
     expected[pathkey(api,path)]=true
    end
    for _,b in ipairs(backups)do if expected[pathkey(api,b.path)]then b.started=true end end
    if numbering then enable_numbering(api)end
    local yes,stats
     if j.loop then yes,stats=true,LoopRender.render(api,m,j,current,numbering)
     else yes,stats=api.GetSetProjectInfo_String(m.project,'RENDER_STATS','42230',false)end
     ensure(yes,'レンダー結果を取得できません。')
    local reported,actual={},{};local n=0
    for path in (stats or''):gmatch('FILE:([^;]+)')do
     local key=pathkey(api,path);ensure((numbering or expected[key])and not reported[key],'予期しない出力が報告されました：'..path)
     reported[key]=true;n=n+1;actual[n]=path
    end
    if n~=#current then result.cancelled=true;break end
    if numbering then numbered_outputs(api,current,actual,j.embed,existing);current=actual end
    Embed.finish(stats,j.embed)
    for _,path in ipairs(current)do
     if m.state.auto then local audio=AudioOutput.inspect(path,api);ensure(audio.channels==j.channels,'出力チャンネル数を確認できません：'..path)end
     local kept=false;for _,b in ipairs(backups)do if pathkey(api,b.path)==pathkey(api,path)then b.committed=true;kept=b.keep end end
     if kept then result.skipped=result.skipped+1 else result.total=result.total+1 end
    end
   end end
  end,tostring)
  local restoreErrors={}
  for _,b in ipairs(backups)do
   local yes,e=pcall(function()
    if b.committed and not b.keep then ensure(os.remove(b.backup),'退避ファイルを削除できません：'..b.backup)
    else
     if exists(b.path)then
      ensure(b.started,'出力先に別のファイルがあります。退避先：'..b.backup)
      local partial=spare(b.path,'.blt-partial-');ensure(os.rename(b.path,partial),'途中出力を退避できません：'..b.path)
      ensure(os.rename(b.backup,b.path),'元ファイルを復元できません：'..b.backup)
      if b.keep and b.committed then ensure(os.remove(partial),'一時出力を削除できません：'..partial)end
     else ensure(os.rename(b.backup,b.path),'元ファイルを復元できません：'..b.backup)end
    end
   end)
   if not yes then restoreErrors[#restoreErrors+1]=tostring(e)end
  end
  ensure(#restoreErrors==0,tostring(err or'')..'\n'..table.concat(restoreErrors,'\n'));ensure(ok,err);return result
 end,false)
 return result,not result.confirmation
end
function Model.completed(result,ok)
 return type(result)=='table'and ok==true and not result.cancelled and result.failed==0 and(result.total or 0)>0
end

local BLTPresetLimits={bytes=16777216,stringBytes=2097152,nodes=262144,entries=8192}
function BLTPresetLimits.show(english)
 reaper.MB(english and 'Preset capacity limit exceeded. Export presets individually instead of as a bundle.' or '容量上限オーバーです。一括ではなく個別に保存してください。','BLT PRESET',0)
end

local WindowGeometry=gfx.geometryAPI()
local BLT_MAC=(reaper.GetOS() or ''):match('OSX')~=nil or (reaper.GetOS() or ''):match('macOS')~=nil

local NAME="DEDICATED RENDER"
local APP_NAME="BLT "..NAME

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
 ["次のプリセット"]="Next preset",
 ["前のプリセット"]="Previous preset",
 ["プリセット（読込・保存・インポート／エクスポート）"]="Presets: load, save, import/export",
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

local Language=create_language(reaper,"BLT_DEDICATED_RENDER",LanguageCatalog)
local R=reaper

local CanvasGraphics={}
function CanvasGraphics.new(gfx,font)
 local G={}
 function G.setfont(_,face,size,flags)font(face,size,flags)end
 return setmetatable(G,{__index=function(_,key)if key=='mouse_wheel'then return 0 end;return gfx[key]end,
  __newindex=function(_,key,value)if key~='mouse_wheel'then gfx[key]=value end end})
end

local RenderControls=(function()
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

local RenderHeaderIcon=(function()
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

local RenderIconDefinition=(function()
local M={width=98,height=62,modes={'render'}}
local heights={5,12,23,16,30,18,8}
function M.update() end
function M.draw(p)
 local C=p.C
 p:disc(60,26,24,C.accent,.012);p:disc(72,26,16,C.ice,.012)
 p:bars(17,27,4,1.3,heights,C.ice,.72)
 p:line(35,27,52,27,C.accent,.10,5);p:line(35,27,52,27,C.ice,.8,1.1)
 p:line(48,23,52,27,C.ice,.8,1.1);p:line(48,31,52,27,C.ice,.8,1.1)
 p:rect(62,12,23,32,C.field,.85)
 p:line(62,12,77,12,C.ice,.85);p:line(77,12,85,20,C.ice,.85)
 p:line(85,20,85,44,C.ice,.85);p:line(85,44,62,44,C.ice,.85);p:line(62,44,62,12,C.ice,.85)
 p:line(77,12,77,20,C.ice,.7);p:line(77,20,85,20,C.ice,.7)
 for _,y in ipairs({28,32,36})do p:line(67,y,80,y,C.ice,.45)end
end
function M.emit(_,n,p)
 local a=(math.sin(n*12.9898)*43758.5453)%1;local b=(math.sin(n*78.233)*12345.6789)%1
 p.x,p.y=28+(a-.5)*8,27+(b-.5)*13
 p.vx,p.vy=15+a*12,(b-.5)*4;p.sway,p.freq,p.phase=1.2,1.4,a*math.pi*2
 p.life,p.r,p.glint=1.3+b*1.0,.5+a*.65,n%6==0
end
function M.sample(_,p,age)
 return p.x+p.vx*age,p.y-p.vy*age+math.sin(age*p.freq+p.phase)*p.sway
end
return M
end)()

local BLTChrome=(function()
local gfx=gfx
local M={}
function M.layout(w,fold,compact)
 local b=M.layoutCache
 if b and b.width==w and b.hasFold==fold and b.compact==compact then return b end
 b={width=w,hasFold=fold,compact=compact,closeX=w-38,resetX=w-72,themeX=w-106}
 b.foldX=fold and b.themeX-34 or nil;b.languageX=(b.foldX or b.themeX)-26
 b.nextX=b.languageX-20;b.prevX=b.nextX-20;b.presetX=b.prevX-84
 if compact then
  b.resetX=b.closeX;b.themeX=w-72;b.foldX=w-106
  b.languageX=w+500;b.nextX=w+500;b.prevX=w+500;b.presetX=w+500
 end
 b.close,b.reset,b.theme,b.language=b.closeX,b.resetX,b.themeX,b.languageX
 b.next,b.prev,b.preset=b.nextX,b.prevX,b.presetX
 M.layoutCache=b;return b
end
function M.hit(b,x,y,w,h)
 if x<0 or x>=w or y<0 or y>=h then return nil end
 if x>=b.closeX then return 'close' end
 if not b.compact and x>=b.resetX then return 'reset' end
 if x>=b.themeX then return 'theme' end
 if b.foldX and x>=b.foldX then return 'fold' end
 if x>=b.languageX then return 'language' end
 if not b.compact then
  if x>=b.nextX then return 'next' end
  if x>=b.prevX then return 'prev' end
  if x>=b.presetX then return 'preset' end
 end
 return 'drag'
end
function M.background(C,h,x,w)
 gfx.set(C.bg[1],C.bg[2],C.bg[3],1);gfx.rect(x,0,w,h,1)
 gfx.gradrect(x,0,w,h,C.field[1],C.field[2],C.field[3],.72,0,0,0,0,(C.bg[1]-C.field[1])/h,(C.bg[2]-C.field[2])/h,(C.bg[3]-C.field[3])/h,.22/h)
 gfx.set(C.edge[1],C.edge[2],C.edge[3],.42);gfx.line(x,h-1,x+w,h-1,1)
end
function M.draw(p)
 local C,Chrome,b,w=p.C,p.chrome,p.b,gfx.w
 local closeX,resetX,chamX,foldX=b.closeX,b.resetX,b.themeX,b.foldX
 local languageX,presetX,prevX,nextX=b.languageX,b.presetX,b.prevX,b.nextX
 local closeW,resetW,chamW=38,34,34
 local hoverClose,hoverReset,hoverCham=p.hot=='close',p.hot=='reset',p.hot=='theme'
 local hoverLanguage,hoverPreset=p.hot=='language',p.hot=='preset'
 local hoverPrev,hoverNext,hoverFold=p.hot=='prev',p.hot=='next',p.hot=='fold'
  if b.inline then M.background(C,Chrome.titleH,0,b.titleEnd);M.background(C,Chrome.titleH,presetX,w-presetX)
  else M.background(C,Chrome.titleH,0,w) end

  p.barFont()
  local _,titleHeight=p.metrics(Chrome.titleText)
  local ty=math.floor((Chrome.titleH-titleHeight)*.5)
  gfx.set(Chrome.mint[1],Chrome.mint[2],Chrome.mint[3],.88); gfx.x=14; gfx.y=ty; gfx.drawstr(p.fit(Chrome.titleText,math.max(0,(b.titleEnd or (b.compact and b.foldX or presetX))-22)))

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
  if p.dirty then gfx.set(C.warn[1],C.warn[2],C.warn[3],.9);gfx.circle(presetX+23,6,1.3,1,1) end

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

  end
  if not b.compact or p.compactLanguage then
  local lc=hoverLanguage and Chrome.mint or C.text
  gfx.set(lc[1],lc[2],lc[3],hoverLanguage and 1 or .95)
  p.languageFont()
  local lw,lh=p.metrics(p.language)
  gfx.x=languageX+(26-lw)/2;gfx.y=(Chrome.titleH-lh)/2;gfx.drawstr(p.language)
  end 

  if foldX then
    gfx.set(C.accent2[1],C.accent2[2],C.accent2[3],hoverFold and .98 or .8)
    local cx,cy=foldX+17,13
    if p.dockButton then
      gfx.rect(cx-7,cy-6,14,12,0)
      if p.docked then gfx.rect(cx-5,cy+1,10,3,1)
      else gfx.line(cx-5,cy+2,cx+5,cy+2);gfx.line(cx,cy-4,cx,cy);gfx.line(cx-2,cy-2,cx,cy);gfx.line(cx,cy,cx+2,cy-2) end
    else
      local d=p.collapsed and 1 or -1
      gfx.line(cx-6,cy-5,cx+6,cy-5);gfx.line(cx-4,cy-d*3,cx,cy+d);gfx.line(cx,cy+d,cx+4,cy-d*3)
    end
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
  gfx.set(rcol[1],rcol[2],rcol[3],p.docked and .25 or (hoverReset and .98 or .82))
  gfx.roundrect(rcx-6,rcy-6,12,12,1,1)
  gfx.line(rcx+3,rcy-3,rcx-3,rcy+3,1)
  gfx.line(rcx-3,rcy+3,rcx-3,rcy-1,1)
  gfx.line(rcx-3,rcy+3,rcx+1,rcy+3,1)

  end 

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
local canvas,draw=gfx,M.draw
local function paint(target,painter)
 gfx=target;local ok,err=pcall(draw,painter);gfx=canvas;if not ok then error(err,0)end
end
function M.draw(painter)canvas.paintChrome(paint,painter)end
return M
end)()

local BLT=(function()
local B={fitCache={},fitCount=0,metrics={},metricCount=0,}
local host,C,Chrome,Chameleon,scale,ox,oy
local R=reaper
local UI={}
local Layout={popup={width=292,headerHeight=36,rowHeight=29,visiblePresets=8,hoverDelay=1}}
local Presets={items={},revision=0}
local function wake_visuals() if host then host.wake() end end
B.copy=Model.clone
function B.invalidate()B.stateRevision=(B.stateRevision or 0)+1 end

function B.pack(v)
 local t=type(v)
 if t=='boolean' then return v and 'b1' or 'b0' end
 if t=='string' or t=='number' then local s=t=='number' and math.type(v)=='float' and string.format('%.17g',v) or tostring(v);return (t=='string' and 's' or 'n')..#s..':'..s end
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
function B.viewport(viewScale,dpi)
 if B.viewScale==viewScale and B.dpi==dpi then return end
 B.fontKey=nil
 if B.dpi~=dpi then B.metrics={};B.metricCount=0;B.fitCache={};B.fitCount=0;B.chromeDPI=nil end
 B.viewScale,B.dpi=viewScale,dpi
end

function B.font(size,kind,bold,s,faces)
 B.fontKey=gfx.selectFont(size,kind,bold,s,faces)
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
 if type(p)~='table' or not Presets.name(p.name) or not host.valid(p.values) then return nil end
 return p
end
function Presets.capture(name)
 if not host.commit() then return nil end
 local values=host.capture()
 if not host.valid(values) then return nil end
 return {name=name,values=B.copy(values)}
end
function Presets.dirty()
 local current=Presets.current;if not current then return false end
 local state=host.capture()
 if Presets.dirtyCurrent~=current or Presets.dirtyState~=state or Presets.dirtyRevision~=B.stateRevision then
  Presets.dirtyCache=not B.same(state,current.values)
  Presets.dirtyCurrent,Presets.dirtyState,Presets.dirtyRevision=current,state,B.stateRevision
 end
 return Presets.dirtyCache
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

function Presets.context(p,x,y)
 if not p or Presets.isFactory(p) or PresetDelete.busy() then return end
 gfx.x=x;gfx.y=y
 if gfx.showmenu(PresetDelete.english() and 'Delete' or '削除')==1 then Presets.remove(p) end
 Presets.pressed=nil;Presets.hoverSince=nil
 Presets.down=((gfx.mouse_cap or 0)&1)~=0
 Presets.rightDown=((gfx.mouse_cap or 0)&2)~=0
 PresetDelete.changed()
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
  local ok,value=Language.input('名前を付けて保存',1,'プリセット名:',name);if not ok then return end
  name=Presets.name(value);if not name then notice('有効なプリセット名を入力してください。',false);return end
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
function UI.bar(w) return BLTChrome.layout(w,false,false) end
function UI.barHit(x,y) return x>=0 and x<gfx.w and y>=0 and y<26 end
local function gfx_window_handle() return host.handle() end
local function chrome_resize_hit(x,y) if y<26 and x>=UI.bar(gfx.w).presetX then return nil end;return host.resizeHit(x,y) end
local function set_resize_cursor(mode) host.cursor(mode) end
local function begin_window_resize(mode) host.beginResize(mode) end
local function update_window_resize() host.resize() end
local function clear_chrome_tooltip() if R.TrackCtl_SetToolTip then R.TrackCtl_SetToolTip('',0,0,true) end end
B.clearTooltip=clear_chrome_tooltip
function Presets.menu(x,y)
 if not host.commit()then return end
  if host.prepareMenu and not host.prepareMenu() then wake_visuals();return end
  Presets.open=true;Presets.page="main";Presets.offset=0;Presets.selected=1
  Presets.down=false;Presets.rightDown=((gfx.mouse_cap or 0)&2)~=0;Presets.pressed=nil;Presets.mx=nil;Presets.my=nil;Presets.hoverSince=nil
  host.cancelEdit();wake_visuals()
end
function Presets.dismiss()
  Presets.swallow=((gfx.mouse_cap or 0)&3)~=0
  Presets.open=false;Presets.hoverSince=nil;Presets.pressed=nil;host.cancelEdit();wake_visuals()
end
function Presets.buildRows()
  if Presets.page=="load" then
    local rows={{text="戻る",icon="back",action=function() Presets.page="main";Presets.selected=1 end}}
    local count=math.min(Layout.popup.visiblePresets,#Presets.items-Presets.offset)
    for i=1,count do
      local p=Presets.items[i+Presets.offset]
      rows[#rows+1]={text=p.name,literal=true,preset=p,icon=Presets.current and Presets.current.name==p.name and "check" or "cards",action=function() Presets.dismiss();Presets.apply(p) end}
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
  if Presets.swallow and ((gfx.mouse_cap or 0)&3)==0 then Presets.swallow=false end
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

  local rightDown=(gfx.mouse_cap&2)~=0
  local rightPressed=rightDown and not Presets.rightDown
  Presets.rightDown=rightDown
  if rightPressed and hit and rows[hit].preset then
    Presets.selected=hit;Presets.context(rows[hit].preset,mx,my);return
  end
  if rightDown then Presets.hoverSince=nil;return end
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
  local presetX=b.presetX
  local inWindow=mx>=0 and mx<w and my>=0 and my<gfx.h
  local inBar=(host.active() or (gfx.getchar(65536)&8)~=0) and not blocked and inWindow and UI.barHit(mx,my)
  local resizeMode=not blocked and chrome_resize_hit(mx,my) or nil
  local resizing=Chrome.resize~=nil
  local cursorMode=resizing and Chrome.resize.mode or resizeMode
  set_resize_cursor(cursorMode)
  local control=inBar and not resizeMode and not resizing and BLTChrome.hit(b,mx,my,w,Chrome.titleH) or nil
  local hoverClose=control=='close'
  local hoverReset=control=='reset'
  local hoverCham=control=='theme'
  local hoverPreset=control=='preset'
  local hoverPrev=control=='prev'
  local hoverNext=control=='next'
  local hoverLanguage=control=='language'
  local down=not blocked and (gfx.mouse_cap&1)~=0
  Chrome.mouseActive=(Presets.open or Presets.swallow) or inBar or Chrome.drag~=nil or Chrome.resize~=nil or cursorMode~=nil
    or Chrome.languagePressed or Chrome.closePressed or Chrome.resetPressed or Chrome.chameleonPressed or Chrome.presetPressed or Chrome.presetPrevPressed or Chrome.presetNextPressed

  local p=Chrome.presenter
  if not p then
    p={C=C,chrome=Chrome,metrics=UI.textMetrics,fit=UI.fit,
      barFont=B.chromeFont,languageFont=function() B.font(13,2,true,1,host.faces) end}
    Chrome.presenter=p
  end
  p.b=b;p.language=Language.code;p.presetOpen=Presets.open;p.dirty=not b.compact and Presets.dirty()
  p.themeEnabled=Chameleon.enabled;p.c1,p.c2,p.c3=Chameleon.icon_colors()
  p.hot=hoverClose and 'close' or hoverReset and 'reset' or hoverCham and 'theme' or hoverLanguage and 'language' or hoverPreset and 'preset' or hoverPrev and 'prev' or hoverNext and 'next' or nil
  p.collapsed,p.docked,p.dockButton=false,false,false;p.compactLanguage=true
  BLTChrome.draw(p)

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
    elseif hoverCham then
      Chrome.chameleonPressed=true
    elseif inBar then
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
      d.lastX,d.lastY=x,y
    end
  end

  if not down and Chrome.mouseDown then
    if Chrome.languagePressed and hoverLanguage then B.toggleLanguage() end
    Chrome.languagePressed=false
    if Chrome.closePressed and hoverClose then Chrome.requestClose=true end
    if Chrome.resetPressed and hoverReset then Chrome.requestReset=true end
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
 return Presets.open or Presets.swallow or (gfx.mouse_y>=0 and gfx.mouse_y<26)
end
function B.key(k)
 if k<0 then return k end
 if Presets.open then Presets.key(k);return 0 end

 return k
end
function B.tick(now)
 if not host then return end
 if B.windowW~=gfx.w or B.windowH~=gfx.h then B.windowW,B.windowH=gfx.w,gfx.h;B.lastRect=nil;wake_visuals() end
 B.viewport(host.geometry(),gfx.ext_retina or 1)
 local active=host.active()
 if Presets.open or Presets.swallow then Presets.update(active) end
 if Presets.open and Presets.hoverSince and now>=Presets.hoverSince+1 then wake_visuals() end
 if B.noticeUntil and now>=B.noticeUntil then B.noticeUntil=nil;B.notice=nil;wake_visuals() end
 local phase=host.editing() and (now%1<.5) or false
 if B.caretPhase~=phase then B.caretPhase=phase;wake_visuals() end
 if B.lastDPI~=(gfx.ext_retina or 1) then B.lastDPI=gfx.ext_retina or 1;wake_visuals() end
 if now>=(B.displayAt or 0) then gfx.update();B.displayAt=now+.25 end
 local tip,tipDelay
 local mx,my=gfx.mouse_x,gfx.mouse_y
 if active and not Presets.open and not host.modal() and (gfx.mouse_cap&1)==0 then
  if my>=0 and my<26 then
   local b=UI.bar(gfx.w)
   tip=mx>=b.closeX and '閉じる' or mx>=b.resetX and 'ウィンドウサイズ初期化' or mx>=b.themeX and 'カメレオンモード' or mx>=b.languageX and '表示言語を切替（JP / EN）' or mx>=b.nextX and '次のプリセット' or mx>=b.prevX and '前のプリセット' or mx>=b.presetX and 'プリセット（読込・保存・インポート／エクスポート）' or nil
  elseif B.footerBounds and B.footerClipped and mx>=B.footerBounds[1] and mx<=B.footerBounds[3] and my>=B.footerBounds[2] and my<=B.footerBounds[4] then tip=B.footerText
  elseif host.tooltip then tip,tipDelay=host.tooltip(mx,my)end
 end
 if tip then tip=Language.message(tip) end
 if tip~=B.tip then if B.tipVisible then clear_chrome_tooltip() end;B.tip=tip;B.tipAt=now;B.tipVisible=false
 elseif tip and not B.tipVisible and now-B.tipAt>=(tipDelay or .7) and R.TrackCtl_SetToolTip and gfx.clienttoscreen then
  local x,y=gfx.clienttoscreen(mx,my+18);R.TrackCtl_SetToolTip(tip,x,y,true);B.tipVisible=true
 end
end
function B.bar()
 if not host then return end
 gfx.textRoute(true)
 scale,ox,oy=host.geometry()
 local blocked=Presets.open or Presets.swallow or host.modal()
 custom_titlebar(blocked)
 Presets.draw()
gfx.textRoute(false)
end

function B.title(title,subtitle,width,divider)
 gfx.textRoute(true)
 scale,ox,oy=host.geometry()
 B.font(35,2,true,scale,host.faces);gfx.set(C.text[1],C.text[2],C.text[3],1)
 gfx.x,gfx.y=ox+24*scale,oy+8*scale;gfx.drawstr(UI.fit(title,(width-150)*scale))
 B.font(10,1,false,scale,host.faces);gfx.set(C.accent2[1],C.accent2[2],C.accent2[3],1)
 gfx.x,gfx.y=ox+26*scale,oy+44*scale;gfx.drawstr(UI.fit(Language.text(subtitle),(width-155)*scale))
 if divider~=false then gfx.set(C.edge2[1],C.edge2[2],C.edge2[3],.26);gfx.line(ox+24*scale,oy+62*scale,ox+(width-24)*scale,oy+62*scale,1)end
gfx.textRoute(false)
end

function B.footer(message,bad,width,height,version)
 gfx.textRoute(true)
 scale,ox,oy=host.geometry();message=Language.message(B.notice or tostring(message or ''))
 if B.notice then bad=B.noticeBad end
 local y=oy+(height-13)*scale
 B.font(8,3,true,scale,host.faces);local ver=version~='' and 'v'..version or '';local vw=UI.textMetrics(ver)
 local available=(width-48)*scale-vw-14*scale
 B.font(8,1,false,scale,host.faces);local shown=UI.fit(message,available)
 B.footerText=message;B.footerClipped=shown~=message;B.footerBounds={ox+24*scale,y,ox+24*scale+available,y+14*scale}
 gfx.set(C.edge[1],C.edge[2],C.edge[3],.26);gfx.line(ox+24*scale,y-3*scale,ox+(width-24)*scale,y-3*scale)
  local c=bad and C.warn or C.muted;gfx.set(c[1],c[2],c[3],1);gfx.x=ox+24*scale;gfx.y=y;gfx.drawstr(shown)
 B.font(8,3,true,scale,host.faces);gfx.set(C.faint[1],C.faint[2],C.faint[3],1);gfx.x=ox+(width-24)*scale-vw;gfx.y=y;gfx.drawstr(ver)
gfx.textRoute(false)
end
return B
end)()

local Session={section='BLT_DEDICATED_RENDER',key='last_session'}
function Session.read(api)
 local raw=api.GetExtState(Session.section,Session.key)
 if raw==''then return nil end
 local v=BLT.unpack(raw:gsub('%%0A','\n'):gsub('%%0D','\r'):gsub('%%25','%%'))
 if type(v)~='table'or not Model.valid(v.state)then return nil,'保存状態を読み込めないためREAPER設定を読み込みました。'end
 if type(v.view)~='table'then v.view={}end
 return v
end
function Session.start(api)
 Model.render_features(api)
 local saved,warning=Session.read(api)
 if saved then
  Model.enumerate_formats(api);Model.enumerate_resamplers(api)
  Model.complete_render_options(api,saved.state)
  return {project=api.EnumProjects(-1,''),state=saved.state,base=nil},saved.view,warning
 end
 return Model.load(api),nil,warning
end
function Session.save(api,m,view)
 if not Model.valid(m.state)then return false end
 local raw=BLT.pack({state=m.state,view=view}):gsub('%%','%%25'):gsub('\n','%%0A'):gsub('\r','%%0D')
 if api.GetExtState(Session.section,Session.key)~=raw then api.SetExtState(Session.section,Session.key,raw,true)end
 return true
end

local SECTION='BLT_DEDICATED_RENDER'
local min,max,floor=math.min,math.max,math.floor
local function clamp(v,a,b)return max(a,min(b,v))end
local function finite(v)return type(v)=='number' and v==v and math.abs(v)<math.huge end
local A={pressed=nil,tab=1,status='REAPERの現在のレンダー設定',bad=false,files={},busy=false}
local m,sessionView,sessionWarning=Session.start(R)
if sessionView then
 for k,limit in pairs({tab=6,detailTab=3,channelTab=2,formatTab=2})do local v=sessionView[k];if type(v)=='number'and v%1==0 and v>=1 and v<=limit then A[k]=v end end
 A.status='前回の状態を復元しました。'
end
if sessionWarning then A.status=sessionWarning;A.bad=true end

local BASE_W,H=648,655
local W=BASE_W
local C={
  bg={0.018,0.030,0.055}, bg2={0.030,0.090,0.180},
  panel={0.040,0.068,0.110}, panel2={0.055,0.125,0.205},
  ice={.65,.895,1},disabled={.43,.46,.51},
  field={0.018,0.040,0.080}, edge={0.145,0.285,0.445}, edge2={0.360,0.650,0.900},
  text={0.955,0.980,1.000}, muted={0.690,0.780,0.875}, faint={0.390,0.505,0.635},
  accent={0.120,0.490,0.980}, accent2={0.650,0.895,1.000}, accent3={0.045,0.235,0.520},
  focus={0.225,0.610,1.000}, focus2={0.690,0.900,1.000}, ink={0.018,0.075,0.160},
  hover={0.430,0.790,1.000}, warn={1.000,0.755,0.490}, red={1.000,0.180,0.260}, quiet={0.300,0.360,0.440}
}
local fonts={"Yu Gothic UI","Segoe UI","Consolas"}
local os=R.GetOS()
if os:match("OSX") or os:match("macOS") then fonts={"Hiragino Sans","Helvetica Neue","Menlo"}
elseif not os:match("Win") then fonts={"sans-serif","sans-serif","monospace"} end

local scale,ox,oy=1,0,0
 BLT.viewport(scale,gfx.ext_retina or 1);local mx,my=-1,-1
local widgets,last_down={},false
local animations_active=true
local animation_speed=1
local EFFECT_IDLE_TAIL=2.5
local EFFECT_COAST=0.70
local effect_activity_until=R.time_precise()+EFFECT_IDLE_TAIL
local redraw_dirty=true
local next_draw_time=0
local last_window_active=nil
local function wake_visuals(now)
  now=now or R.time_precise(); redraw_dirty=true
  effect_activity_until=max(effect_activity_until,now+EFFECT_IDLE_TAIL)
  if next_draw_time==math.huge then next_draw_time=now end
end
local function visual_speed(now)
  local remain=effect_activity_until-(now or R.time_precise())
  if remain<=0 then return 0 end
  if remain>=EFFECT_COAST then return 1 end
  local t=clamp(remain/EFFECT_COAST,0,1)
  return t*t*(3-2*t)
end

local function sx(x) return ox+x*scale end
local function sy(y) return oy+y*scale end
local function color(c,a) gfx.set(c[1],c[2],c[3],a or 1) end
local function rect(x,y,w,h,c,a) color(c,a); gfx.rect(sx(x),sy(y),w*scale,h*scale,1) end
local function line(x,y,x2,y2,c,a) color(c,a); gfx.line(sx(x),sy(y),sx(x2),sy(y2),1) end

local function font(size,kind,bold) BLT.font(size,kind,bold,scale,fonts) end
local function label(text,x,y,size,c,kind,w,h,flags,bold,literal)
  local shown=literal and tostring(text) or Language.message(text)
  font(size,kind,bold); color(c or C.text); gfx.x,gfx.y=sx(x),sy(y)
  if shown~=tostring(text) and w then shown=BLT.ui.fit(shown,w*scale) end
  gfx.drawstr(shown,flags or 0,sx(x+(w or 700)),sy(y+(h or size+8)))
end

local function inside(x,y,w,h) return mx>=x and mx<=x+w and my>=y and my<=y+h end
local function widget(id,x,y,w,h,fn,enabled)
  widgets[#widgets+1]={id=id,x=x,y=y,w=w,h=h,fn=fn,enabled=enabled~=false}
end

local function draw_background() rect(0,0,W,H+22,C.bg) end
local Chameleon
local Chrome={mouseDown=false,drag=nil,resize=nil,mouseActive=false,requestClose=false,requestReset=false,
  chameleonPressed=false,titleH=26,titleText='D E D I C A T E D   R E N D E R',
  minW=648,minH=681,mint={0.38,0.88,0.72},ice={0.65,0.895,1.0},red={1.0,0.27,0.34},
  isWindows=R.GetOS():match("Win")~=nil,resizeEdge=6,resizeCornerBand=8,resizeCornerSpan=24,resizeTopLeftGuard=30,resizeTopRightGuard=110,
}
Chrome.font=Chrome.isWindows and "Segoe UI" or (BLT_MAC and "Helvetica Neue" or "sans-serif")

local density=RenderControls.compactScale
local RenderGraphics=CanvasGraphics.new(gfx,function(face,size,flags)
 local kind=1;for i,name in ipairs(fonts)do if face==name then kind=i;break end end
 BLT.font(size,kind,flags==98,1,fonts)
end)
local RenderUI=RenderControls.new(RenderGraphics,R.time_precise,C)
RenderUI.font,RenderUI.minFontSize=fonts[1],7
local render_frame=RenderUI.frame
function RenderUI:frame(x,y,w,h,opt)
 if not self.joinedTab and not self.joinedPanel then return render_frame(self,x,y,w,h,opt)end
 local C=opt.palette or self.C;local hot=opt.hot or 0
 local selected=opt.selected;local tab=self.joinedTab
 local extra=tab and(selected and 2 or 1)/density or 0
 if tab then self:bloom(x,y,w,h,math.max(hot,selected and .48 or 0),opt.lightX,.08,C)end
 self:surface(x,y,w,h+extra,0,hot,selected,opt.pressed,opt.lightX,C,C.panel)
 local edge,alpha=C.rim or C.ice,selected and .65 or .26+.18*hot
 local right,bottom=x+w-1,y+h-(tab and 0 or 1)
 self:line(x,y,right,y,edge,alpha)
 self:line(x,y,x,bottom,edge,alpha)
 self:line(right,y,right,bottom,edge,alpha)
 if not tab or not selected then self:line(x,bottom,right,bottom,edge,alpha)end
end
local render_interaction=RenderUI.interaction
function RenderUI:interaction(...)
 local _,hot,held,state=render_interaction(self,...)
 local x,_,w=select(2,...)
 state.renderSeen=self.frameSerial;state.renderHot=hot and 1 or 0
 state.renderLight=hot and max(.12,min(.88,(self.mx-x)/w)) or .18
 return false,hot,held,state
end
local options={}
local function render_options(id)
 local opt=options[id];if not opt then opt={};options[id]=opt end;return opt
end
local function render_animating(now)
 for _,s in pairs(RenderUI.states)do
  if s.flash and now-s.flash>=.9 then s.flash=nil end
  if s.flashPending and now-s.flashPending>=.9 then s.flashPending=nil end
  if s.renderSeen==RenderUI.frameSerial then
   if s.hover and s.hover~=s.renderHot or s.lightX and s.renderLight and math.abs(s.lightX-s.renderLight)>.0001
    or s.slide and s.slide>0 and s.slide<1 or s.flash or s.flashPending then return true end
  end
 end
 return false
end
local RenderIcon=RenderHeaderIcon.new({faces=fonts,g=RenderGraphics},RenderUI,RenderIconDefinition)

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
 function M.palette(map,defaults)

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
   pending=true;theme.apply(M.palette(map,defaults));pending=false
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

Chameleon=BLTChameleon.new(R,C,{section=SECTION,store=BLT.store,chrome=Chrome,
 roles={ice='accent2',disabled='faint'},changed=wake_visuals})

local function titlebar_api_ready()
  local required={"JS_Window_Find","JS_Window_IsWindow","JS_Mouse_GetState","JS_VKeys_GetDown"}
  for _,name in ipairs(required) do
    if type(R[name])~="function" then
      return false,"カスタムタイトルバーには js_ReaScriptAPI が必要です。\nReaPack から js_ReaScriptAPI をインストールしてください。"
    end
  end
  return true
end

local function gfx_window_handle()return gfx.windowHandle()end

local function reset_window_size()
  local hwnd=gfx_window_handle()
  if not hwnd then return end
  local ok,l,t=WindowGeometry.JS_Window_GetRect(hwnd)
  if ok then BLT.position(hwnd,l,t,BASE_W,H+Chrome.titleH,"","") end
  BLT.store(SECTION,"window_w",tostring(BASE_W),true)
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
local function set_resize_cursor(mode)gfx.setCursor(resize_cursor_kind(mode))end
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

LanguageCatalog.en['レンダー対象がありません。']='No render targets.'
LanguageCatalog.en['トラックのチャンネル設定']='Track channel setting'
LanguageCatalog.en['マルチチャンネル']='Multichannel'
LanguageCatalog.en['アイテム／レイザー単位では、対象音声を変えずにループ用の前後余裕を追加できないため停止しました。リージョンまたは時間範囲で書き出してください。']='Stopped: item/razor rendering cannot add loop handles without changing the audio source. Render regions or a time range instead.'
LanguageCatalog.en['ループ用の一時音声は尺が長く、自動追加すると配置に影響するため停止しました。「プロジェクトへ追加」をOFFにしてください。']='Stopped: the longer temporary loop audio would affect placement when added to the project. Turn off Add to project.'
LanguageCatalog.en['埋込メタ情報のワイルドカードに一時ファイル名や拡張範囲が入る可能性があるため停止しました。ワイルドカードを固定値へ置き換えてください。']='Stopped: metadata wildcards may contain temporary filenames or extended ranges. Replace the wildcards with fixed text.'
LanguageCatalog.en['ループ書き出しはプロジェクトの再生速度を1.0にしてください。']='Set the project play rate to1.0 for loop export.'
LanguageCatalog.en['ループ書き出しのサンプルレートを明示指定してください。']='Specify an integer sample rate from8000 to384000Hz for loop export.'
LanguageCatalog.en['マーカー #']='Markers #';LanguageCatalog.en['リージョン #']='Regions #'
for jp,en in pairs({
 ['FORMAT / 形式・レート']='FORMAT / AUDIO',
 ['カスタムカラー']='Custom colors',['多チャンネルを維持']='Keep multiple channels',
 ['モノラル素材のみならモノラル']='Mono-only sources to mono',
 ['親へ送るチャンネルのみ']='Channels sent to parent only',
 ['トランジェントガイド']='Transient guides',['テイクマーカー']='Take markers',
 ['開始オフセットを維持']='Preserve start offset',
 ['ミックス / FXにプロジェクトSR']='Project rate for mix / FX',
 ['ノイズ整形']='Noise shaping',['ステムに整形']='Shape stems',
 ['ディザ処理を無効']='Disable dithering',['新規トラックへ追加']='Add to new tracks',
 ['無音のファイルを除外']='Skip silent files',['最大音量へ合わせる']='Match loudest file',
 ['リミッター']='Limiter',['インLPF']='In LPF',['アウトLPF']='Out LPF',
 ['リージョン管理']='Region manager',['リージョン / マーカー管理']='Region / marker manager',
 ['マーカー文字コード']='Marker encoding',['キューの開始待機']='Queue start delay',
 ['レンダー保存先']='Render output directory',['プリセット名']='Preset name',['値']='Value',
 ['識別子（例 INFO:INAM / BWF:Description）']='Identifier (e.g. INFO:INAM / BWF:Description)',
 ['現在の形式（標準画面で詳細設定）']='Current format (native settings)',
 ['保存されているREAPERレンダープリセットはありません。']='No saved REAPER render presets.',
 ['標準画面で変更後「REAPER設定を読込」を押してください。']='After editing native settings, click Load REAPER settings.',
 ['出力先を更新してください。']='Refresh targets to show output paths.',
 ['出力先を更新しました。']='Targets refreshed.',['出力先をコピーしました。']='Output path copied.',
 ['別プロジェクトです。REAPER設定を読込してください。']='Project changed. Load REAPER settings.',
 ['別のプロジェクトです。REAPER設定を読込してください。']='Project changed. Load REAPER settings.',
 ['別のプロジェクトに切り替わっています。「再読込」を押してください。']='Project changed. Load REAPER settings.',
 ['プロジェクトが切り替わりました。']='The active project changed.',
 ['数値を入力してください。']='Enter a number.',['0以上の整数を入力してください。']='Enter a nonnegative integer.',
 ['設定値が範囲外です。']='Value is out of range.',['範囲外のレートです。']='Sample rate is out of range.',
 ['識別子を確認してください。']='Check the identifier.',['WAV形式を選択してください。']='Select WAV format.',
 ['この操作はレンダー専用です。']='This operation only supports rendering.',
 ['この項目の変更にはSWSが必要です。']='Changing this setting requires SWS.',
 ['カラー判定にはSWS Extensionが必要です。']='Color mapping requires SWS Extension.',
 ['カスタムカラーを取得できません。']='Cannot read custom colors.',
 ['同じ色に異なるチャンネルが設定されています。']='The same color has conflicting channel assignments.',
 ['設定値を確認してください。カスタム範囲は終了を開始より後にしてください。']='Check settings. Custom bounds must end after they start.',
 ['レンダー結果を取得できません。']='Cannot retrieve render results.',
 ['レンダー結果を取得できませんでした。']='Cannot retrieve render results.',
 ['出力先が変更されました。']='Output targets changed.',
 ['出力先を取得できません。']='Cannot retrieve output targets.',
 ['無名トラック']='Unnamed track',['BLTアプリバーの初期化に失敗しました。']='Cannot initialize the BLT app bar.',
 ['復元失敗：メタデータ']='Cannot restore metadata.'
})do LanguageCatalog.en[jp]=en end
for jp,en in pairs({
 ['REAPER側でも同じ設定が変更されています。再読込してください：']='Settings also changed in REAPER. Reload: ',
 ['設定取得失敗：']='Cannot read setting: ',['設定変更失敗：']='Cannot update setting: ',
 ['メタデータ変更失敗：']='Cannot update metadata: ',['復元失敗：']='Cannot restore: ',
 ['設定の復元に失敗しました：']='Cannot restore settings: ',
 ['出力ファイル名が重複しています：']='Duplicate output filename: ',
 ['一時出力を削除できません：']='Cannot remove temporary output: ',
 ['予期しない出力が報告されました：']='Unexpected output reported: ',
 ['元ファイルを復元できません：']='Cannot restore original file: ',
 ['出力チャンネル数を確認できません：']='Cannot verify channel count: ',
 ['出力先に別のファイルがあります。退避先：']='Another file occupies the output path. Backup: ',
 ['既存ファイルを退避できません：']='Cannot back up existing file: ',
 ['確認後に出力先へファイルが現れました：']='A file appeared after checking the output path: ',
 ['退避ファイルを削除できません：']='Cannot remove backup: ',
 ['途中出力を退避できません：']='Cannot preserve partial output: '
})do LanguageCatalog.en[jp]=en;LanguageCatalog.prefixes[#LanguageCatalog.prefixes+1]=jp end
LanguageCatalog.patterns[#LanguageCatalog.patterns+1]={'^(%d+) チャンネル$','%s channels'}
LanguageCatalog.patterns[#LanguageCatalog.patterns+1]={'^設定チャンネル数は出力形式で使用できません（上限 (%d+) ch）。$','Channel count exceeds the format limit (%s ch).'}
Model.translate=Language.message
for jp,en in pairs({
 ['リージョン・レンダーマトリックス']='Region render matrix',
 ['リージョン・レンダーマトリックス・マスター経由']='Region render matrix via master',
 ['レイザー編集領域']='Razor edit areas',['レイザー編集領域・マスター経由']='Razor edit areas via master',
 ['選択メディアアイテムを1ファイルに結合']='Selected media items as one file',
 ['レイザー編集領域を1ファイルに結合']='Razor edit areas as one file',
 ['レイザー領域を1ファイルに結合']='Razor areas as one file',
 ['マトリックス']='Render matrix',
 ['RENDER TO FILE  /  追加機能付きファイルレンダリング']='RENDER TO FILE',
 ['基本']='General',['詳細']='Options',['後処理']='Postprocess',['メタデータ']='Metadata',['出力確認']='Targets',
 ['既存ファイルの確認']='Existing files',
 ['既存ファイルが %d 件あります。']='%d files already exist.',
 ['チャンネル未設定のトラックカラーがあります。']='Some track colors have no channel assignment.',
 ['未設定の %d トラックはマスターの %d ch で書き出します。']='%d unassigned tracks will use the master channel count (%d).',
 ['チャンネル未設定のトラックカラーがあります。マスターの %d ch で書き出します。']='Some track colors have no channel assignment. They will use the master channel count (%d).',
 ['書き出し方法を選択してください。']='Choose how to handle existing files.',
 ['キャンセル']='Cancel', ['連番付与']='Auto-number', ['上書き']='Overwrite', ['新規のみ書き出し']='Write new files only',
 ['ソース']='Source',['範囲']='Bounds',['開始位置（秒）']='Start (seconds)',['終了位置（秒）']='End (seconds)',
 ['テールを追加']='Render tail',['テール長（ms）']='Tail length (ms)',
 ['保存先フォルダー']='Output directory',['参照']='Browse',['ファイル名 / ワイルドカード']='File name / wildcards',
 ['ワイルドカードを追加']='Insert wildcard',['付随ファイルの保存先']='Extra output directory',
 ['サンプルレート']='Sample rate',['プロジェクト設定を使用']='Use project rate',['カスタム値…']='Custom…',
 ['チャンネル']='Channels',['自動（トラックカラーで判定）']='Auto (track custom color)',
 ['モノラル']='Mono',['ステレオ']='Stereo',['名前付きフォルダー疑似アイテム / WAV']='Named folder items / WAV',
 ['レンダリング速度']='Render speed',['フルスピード・オフライン']='Full-speed offline',['1倍速・オフライン']='1x offline',
 ['2倍速・オフライン']='2x offline',['1倍速・オフライン（アイドル）']='1x offline (idle)',
 ['2倍速・オフライン（アイドル）']='2x offline (idle)',
 ['統計・表示']='Statistics / display',['統計の計算']='Statistics calculation',['ラウドネス統計']='Loudness statistics',
 ['計算しない（最速）']='None (fastest)',['ピーク統計']='Peak statistics',['サンプルピーク']='Sample peak',
 ['トゥルーピーク']='True peak',['正規化・リミットは「後処理」で設定します。']='Normalization / limiting: Postprocess tab.',
 ['統計グラフ']='Statistics graphs',['ラウドネスグラフ']='Loudness graph',['モーメンタリー']='Momentary',
 ['ショートターム']='Short-term',['LUFSゲート対象外を色分け']='Shade excluded LUFS areas',
 ['ピーク超過箇所を強調']='Highlight overs',['統計ファイル']='Statistics files',['HTMLレポート']='HTML report',
 ['保存しない']='Do not save',['ファイルごとに保存']='Save per file',['まとめて保存']='Save combined report',
 ['最後の統計をメモリに保持']='Keep last statistics in memory',['表示する情報']='Display options',
 ['レンダー中にトラックメーターを表示']='Show track meters during render',
 ['HTMLにファイルパスを含める']='Include file paths in HTML',
 ['HTMLにリージョン／マーカーを含める']='Include regions / markers in HTML',
 ['REAPER v7.83以降とSWSが必要です。']='Requires REAPER v7.83 or later and SWS.',
 ['オンライン']='Online',['オンライン（アイドル）']='Online (idle)',['オフライン（アイドル）']='Offline (idle)',
 ['一次出力形式']='Primary output format',['二次出力形式']='Secondary output format',['なし']='None',
 ['WAVビット深度']='WAV bit depth',['エンコーダー詳細 / BWF / マーカー…']='Encoder / BWF / markers…',
 ['コーデック固有の詳細は標準画面で編集 → 再読込']='Edit codec details in REAPER, then reload',
 ['マスターミックス']='Master mix',['マスター＋選択トラックのステム']='Master mix + selected stems',
 ['選択トラックのステム']='Selected track stems',['リージョン・レンダーマトリクス']='Region render matrix',
 ['選択メディアアイテム']='Selected media items',['選択メディアアイテム・マスター経由']='Selected media items via master',
 ['選択トラック・マスター経由']='Selected tracks via master',['レーザー編集領域']='Razor edit areas',
 ['レーザー編集領域・マスター経由']='Razor edit areas via master',['カスタム時間範囲']='Custom time bounds',
 ['プロジェクト全体']='Entire project',['時間選択']='Time selection',['全リージョン']='All regions',
 ['選択リージョン']='Selected regions',['全マーカー']='All markers',['選択マーカー']='Selected markers',
 ['トラックの多チャンネルを維持']='Multichannel tracks to multichannel files',
 ['モノラル素材のみのトラックはモノラル']='Mono-only tracks to mono files',
 ['親へ送信するチャンネルのみ']='Only channels sent to parent',['フェーダー前のステム']='Pre-fader stems',
 ['2パスレンダー']='Second-pass render',['マスター経由の並列レンダー']='Parallel render via master',
 ['FX初期化を待って開始']='Delay start for FX initialization',
 ['選択アイテム / レーザーを1ファイルに結合']='Combine items / razor areas into one file',
 ['トランジェントガイドを埋め込む']='Embed transient guides',['メタデータを埋め込む']='Embed metadata',
 ['テイクマーカーを埋め込む']='Embed take markers',['ソースのメタデータを維持']='Preserve source metadata',
 ['ソースの開始オフセットを維持']='Preserve source start offset',['ソースのサンプルレートを維持']='Preserve source sample rate',
 ['FX初期化の待ち時間（秒）']='FX initialization delay (seconds)',
 ['リサンプルモード']='Resample mode',['ミックス / FXにプロジェクトSRを使用']='Use project sample rate for mixing / FX',
 ['ディザ']='Dither',['ノイズシェーピング']='Noise shaping',['ステムにディザ']='Dither stems',
 ['ステムにシェーピング']='Shape noise on stems',['ディザ処理をすべて無効']='Disable all dither',
 ['レンダー後、新規トラックへ追加']='Add rendered files to new tracks',['無音と推定されるファイルを書き出さない']='Do not render likely-silent files',
 ['重複時に自動ナンバリング']='Silently increment filenames',['完了後にレンダーウィンドウを閉じる']='Auto-close render windows',
 ['完了後にレンダー設定へ戻る']='Return to render setup',['レンダー統計をHTMLへ保存']='Save render statistics as HTML',
 ['レンダーのブロックサイズ（0＝自動）']='Render block size (0 = auto)',
 ['正規化を有効']='Enable normalization',['測定方式']='Measurement',['正規化ターゲット（dB / LUFS）']='Normalize target (dB / LUFS)',
 ['複数ファイルの正規化']='Multi-file normalization',['ファイルごと']='Per file',
 ['同時再生として正規化']='As if playing together',['最大音量ファイルに合わせる']='To loudest file',
 ['同時再生 / 共通ゲイン']='Playing together / common gain',['マスターミックスへ合わせる']='To master mix',
 ['ターゲットへの適用']='Apply to',['上下両方']='Both directions',['大きすぎる場合のみ']='Only too loud',['小さすぎる場合のみ']='Only too quiet',
 ['モノラル補正']='Mono adjustment',['ブリックウォール・リミット']='Brickwall limit',['トゥルーピーク・リミット']='True-peak limit',
 ['リミット閾値（dB）']='Limit threshold (dB)',['リミッターの複数ファイル処理']='Multi-file limiter',
 ['同時再生として処理']='As if playing together',['マスターミックス基準']='Relative to master mix',
 ['先頭の無音をトリム']='Trim leading silence',['先頭トリム閾値（dB）']='Leading threshold (dB)',
 ['末尾トリム閾値（dB）']='Trailing threshold (dB)',['末尾の無音をトリム']='Trim trailing silence',
 ['先頭に無音を追加']='Pad start',['末尾に無音を追加']='Pad end',['先頭パディング（秒）']='Start pad (seconds)',
 ['末尾パディング（秒）']='End pad (seconds)',['フェードイン']='Fade in',['フェードアウト']='Fade out',
 ['フェードイン（秒）']='Fade in (seconds)',['フェードアウト（秒）']='Fade out (seconds)',
 ['インのカーブ']='Fade-in shape',['アウトのカーブ']='Fade-out shape',['インにローパス']='Low-pass fade in',
 ['アウトにローパス']='Low-pass fade out',['後処理をすべてバイパス']='Bypass all postprocessing',
 ['フィールドを追加']='Add field',['標準メタデータ / タグ一覧…']='REAPER metadata / tag browser…',
 ['行をクリックして編集。空の値を入力すると削除します。']='Click a row to edit. An empty value removes the field.',
 ['メタデータなし。追加、または標準画面から読み込めます。']='No metadata. Add fields or load them from REAPER.',
 ['設定を適用して出力先を更新']='Apply and refresh targets',['出力フォルダーを開く']='Open output directory',
 ['レンダーキュー…']='Render queue…',['「出力先を更新」で一覧を表示します。']='Refresh targets to show output paths.',
 ['REAPERから再読込']='Reload from REAPER',['標準レンダー設定…']='REAPER render setup…',['設定を適用']='Apply settings',
 ['ドライラン']='Dry run',['キューへ追加']='Add to queue',
 ['変更した設定は「適用」「レンダー」でREAPERへ反映します。']='Apply settings or render to update REAPER.',
 ['REAPERの現在のレンダー設定']='Current REAPER render settings',['待機中']='Ready',
 ['設定を変更しました。適用またはレンダーで反映します。']='Settings edited. Apply or render to commit.',
 ['設定を適用しました。']='Settings applied.',['REAPERから設定を読み込みました。']='Loaded settings from REAPER.',
 ['レンダリング中…']='Rendering…',['ドライラン終了']='Dry run finished.',['キューに追加しました。']='Added to render queue.'
})do LanguageCatalog.en[jp]=en end

for jp,en in pairs({
 ['SOURCE / ソース選択']='SOURCE', ['FORMAT / フォーマット・レート']='FORMAT / AUDIO', ['OUTPUT / 出力設定']='OUTPUT',
 ['対象（ソース）']='Source', ['出力形式']='Output format', ['サンプリングレート']='Sample rate', ['ビット深度']='Bit depth',
 ['開始（秒）']='Start (seconds)', ['終了（秒）']='End (seconds)', ['プロジェクト設定']='Project rate',
 ['REAPERプリセットを読み込む']='Load REAPER preset', ['再読込']='Reload', ['標準設定…']='Native setup…', ['レンダー']='Render',
 ['ワイルドカード']='Wildcards', ['選択アイテムを1ファイルに結合']='Combine selected items into one file',
 ['選択したアイテムごとに書き出します。']='Render each selected item.', ['選択範囲はREAPERの状態に追従します。']='Bounds follow the REAPER project.',
 ['ビット深度：この形式では指定しません']='Bit depth does not apply to this format.', ['音声設定のない出力形式です。']='This format has no audio settings.',
 ['設定は「適用」または「レンダー」でREAPERに反映します。']='Apply or Render commits settings to REAPER.'
})do LanguageCatalog.en[jp]=en end

for jp,en in pairs({
 ['設定を変更しました。']='Settings changed.', ['REAPERプリセット']='REAPER presets',
 ['レンダー後閉じる']='Close after render', ['出力・品質']='Output / quality', ['カラー判定']='Color mapping', ['開始待機']='Start delay',
 ['トラックと書き出し']='Tracks / rendering', ['埋め込み・ソース情報']='Embed / source data', ['音声処理の品質']='Audio quality', ['出力後・ファイル管理']='Files / after render',
 ['カスタムカラー 01–08']='Custom colors 01–08', ['カスタムカラー 09–16']='Custom colors 09–16', ['未設定']='Unassigned',
 ['FXの初期化']='FX initialization', ['キューレンダーの開始']='Queued render start', ['開始待機（秒）']='Start delay (s)', ['サンプル読込の待機（秒）']='Sample loading delay (s)',
 ['音量の正規化']='Normalization', ['ピークの制限']='Peak limiting', ['無音のトリム']='Trim silence', ['無音の追加']='Pad silence', ['フェード']='Fades',
 ['有効']='Enable', ['目標（dB / LUFS）']='Target (dB / LUFS)', ['複数ファイル']='Multiple files', ['適用条件']='Apply when', ['上限（dB）']='Ceiling (dB)',
 ['先頭']='Start', ['末尾']='End', ['先頭閾値（dB）']='Start threshold (dB)', ['末尾閾値（dB）']='End threshold (dB)', ['先頭（秒）']='Start (s)', ['末尾（秒）']='End (s)',
 ['イン']='In', ['アウト']='Out', ['イン（秒）']='In (s)', ['アウト（秒）']='Out (s)', ['後処理を有効']='Enable postprocessing', ['出力先を更新']='Refresh targets'
})do LanguageCatalog.en[jp]=en end

for jp,en in pairs({
 ['メイン出力']='Main output', ['二次出力']='Secondary output', ['リージョンとマーカー']='Regions and markers',
 ['マーカー']='Markers', ['リージョン']='Regions', ['ループリージョン']='Loop regions', ['選択中のリージョンを除外']='Exclude selected regions',
 ['選択リージョンを除外']='Exclude selected', ['文字コード']='Encoding', ['REAPER設定を読込']='Load REAPER settings', ['標準レンダーウィンドウを開く']='Open REAPER render window', ['標準レンダーを開く']='Open REAPER render'
})do LanguageCatalog.en[jp]=en end

for jp,en in pairs({
 ['前回の状態を復元しました。']='Restored the last session.',
 ['保存状態を読み込めないためREAPER設定を読み込みました。']='Saved session is invalid; loaded REAPER settings.',
})do LanguageCatalog.en[jp]=en end

LanguageCatalog.en['…他%d個']='…and %d more'
LanguageCatalog.en['デフォルトカラー（色未設定）']='Default color (uncolored)'
LanguageCatalog.en['マスターのチャンネル設定']='Master channel setting'

LanguageCatalog.en['自動（トラックカラー・アイテム設定）']='Auto (track color / item)'
LanguageCatalog.en['チャンネル判定']='Channels'
LanguageCatalog.en['フォルダアイテムの中身を除外']='Exclude folder item contents'
LanguageCatalog.en['無名のアイテムを除外']='Exclude unnamed items'
LanguageCatalog.en['アイテム埋込']='Item settings'
LanguageCatalog.en['選択アイテムに…']='Set on selected items'
LanguageCatalog.en['自動判定時・選択メディアアイテムの書き出しのみ有効です。']='Auto mode: applies only when rendering selected media items.'
LanguageCatalog.en['アイテム設定を最優先し、指定がない場合はトラックカラーを使います。']='Item settings take priority; otherwise track colors are used.'
LanguageCatalog.en['MONOを埋込']='Set MONO'
LanguageCatalog.en['STEREOを埋込']='Set STEREO'
LanguageCatalog.en['Ch%dを埋込']='Set Ch%d'
LanguageCatalog.en['チャンネル数（3～128）']='Channels (3–128)'
LanguageCatalog.en['%d個のアイテムに%dchを設定しました。']='Set %d items to %d channels.'
LanguageCatalog.en['アイテムが選択されていません。']='No items selected.'
LanguageCatalog.en['1ファイルに結合するアイテムのチャンネル指定が異なります。設定を揃えてください。']='Items combined into one file have different channel settings. Use matching settings.'
LanguageCatalog.en['アイテムのチャンネル設定が不正です。再設定してください。']='Invalid item channel settings. Set the channel count again.'
LanguageCatalog.en['チャンネル数は1～128の整数で指定してください。']='Specify an integer channel count from 1 to 128.'
LanguageCatalog.en['アイテムへのチャンネル設定の保存に失敗しました。']='Failed to save item channel settings.'
LanguageCatalog.en['アイテム設定の復元に失敗しました。']='Failed to restore item settings.'

LanguageCatalog.en['並列レンダー']='Parallel render'

LanguageCatalog.en['埋込を削除']='Clear setting'
LanguageCatalog.en['%d個のアイテムの埋込を削除しました。']='Cleared settings on %d items.'

LanguageCatalog.en['出力名の確認']='Output names'
LanguageCatalog.en['出力名を一意に確定できません。']='Output names cannot be resolved uniquely.'
LanguageCatalog.en['重複する名前だけに連番を付けて書き出しますか？']='Add serial numbers only to conflicting names?'

LanguageCatalog.en['出力先（相対パス）']='Output (relative path)'
LanguageCatalog.en['REAPER判定']='REAPER auto'

LanguageCatalog.en['選択メディアアイテム・マスター経由を1ファイルに結合']='Selected media items via master as one file'
LanguageCatalog.en['レイザー編集領域・マスター経由を1ファイルに結合']='Razor edit areas via master as one file'
LanguageCatalog.en['無効な設定は値を保持し、書き出し時には適用しません。']='Inactive settings are retained and ignored when rendering.'
LanguageCatalog.en['その他（カスタム色ではない色指定）']='Other (non-custom color)'
LanguageCatalog.en['レンダー']='Render'
LanguageCatalog.en['自動']='Auto'

local function status(s,bad,now)A.status=s;A.bad=bad or false;wake_visuals(now)end
local ItemLabels=(function()
local M={}
local floor,ceil,min,max=math.floor,math.ceil,math.min,math.max
local TEXT_W,TEXT_H,PAD_X,PAD_Y,MARGIN=96,36,5,3,4
local MAX_W,MAX_H=TEXT_W+PAD_X*2,TEXT_H+PAD_Y*2
function M.new(api,key,report)
 local T={labels={},free={},cache={},channels={},bounds={},templates={},erasures={},nextTrim=0,pending=true,scanDue=0,enabled=true,frame=0,visibility=0}
 local os=api.GetOS();local mac=os:match('OSX')or os:match('macOS')
 local required={'JS_Window_FindChildByID','JS_Window_IsWindow','JS_Window_IsVisible','JS_Window_GetClientSize','JS_Window_ClientToScreen','JS_Window_ScreenToClient','JS_Window_GetScrollInfo','ValidatePtr2',
  'JS_Composite','JS_Composite_Unlink','JS_Window_InvalidateRect','JS_ReaScriptAPI_Version',
  'JS_LICE_CreateBitmap','JS_LICE_DestroyBitmap','JS_LICE_Clear','JS_LICE_CreateFont','JS_LICE_DestroyFont',
  'JS_LICE_SetFontFromGDI','JS_LICE_SetFontColor','JS_LICE_DrawText','JS_LICE_GetPixel','JS_LICE_Blit','JS_LICE_ProcessRect',
  'JS_GDI_CreateFont','JS_GDI_DeleteObject'}
 if mac then required[#required+1]='JS_Window_EnableMetal'end
 for _,name in ipairs(required)do
  if type(api[name])~='function'then T.error='js_ReaScriptAPI API missing: '..name;break end
 end
 if not T.error and(tonumber(api.JS_ReaScriptAPI_Version())or 0)<1.215 then T.error='js_ReaScriptAPI 1.215 or later is required.'end
 local function invalidate(window,x,y,w,h)
  if x and api.JS_Window_IsWindow(window)then api.JS_Window_InvalidateRect(window,x,y,x+w,y+h,false)end
 end
 local function present(entry)
  if entry.repaintFrame~=T.frame then
   invalidate(entry.window,entry.x,entry.y,entry.w,entry.h);entry.repaintFrame=T.frame
  end
 end
 local function eraseLater(entry,now)
  local area=T.erasures[entry]
  if not area then area={};T.erasures[entry]=area end
  area.window,area.x,area.y,area.w,area.h,area.at=entry.window,entry.x,entry.y,entry.w,entry.h,now+.06
 end
 local function eraseReady(now)
  for entry,area in pairs(T.erasures)do
   if now>=area.at then
    if api.JS_Window_IsWindow(area.window)then
     api.JS_Window_InvalidateRect(area.window,area.x,area.y,area.x+area.w,area.y+area.h,true)
    end
    T.erasures[entry]=nil
   end
  end
 end
 local function unlink(entry,now)
  if entry.linked then
   eraseLater(entry,now)
   api.JS_Composite_Unlink(entry.window,entry.bitmap,true)
   entry.linked=false;entry.repairAt=nil;entry.reuseAfter=now+.2;entry.reuseFrame=T.frame+2
  end
 end
 local function hide(now)
  for item,entry in pairs(T.labels)do
   unlink(entry,now);T.free[#T.free+1]=entry;T.labels[item]=nil
  end
 end
 local function fail(message,now)
  T.error=tostring(message);T.job=nil;hide(now)
  if not T.reported then T.reported=true;report(T.error)end
 end
 local function font()
  if T.font then return end
  T.gdi=assert(api.JS_GDI_CreateFont(19,700,0,false,false,false,mac and'Menlo-Bold'or'Consolas'),'Cannot create label font')
  T.font=assert(api.JS_LICE_CreateFont(),'Cannot create LICE label font')
  api.JS_LICE_SetFontFromGDI(T.font,T.gdi,'')
  api.JS_LICE_SetFontColor(T.font,0xffffffff)
 end
 local function template(ch,short)
  local cacheKey=short and-ch or ch
  local source=T.templates[cacheKey];if source then return source end
  font()
  local text=short and(ch==1 and'MO'or ch==2 and'ST'or tostring(ch))or(ch==1 and'MONO'or ch==2 and'STEREO'or ch..'ch')
  source={bitmap=assert(api.JS_LICE_CreateBitmap(true,TEXT_W,TEXT_H),'Cannot allocate label image')}
  T.templates[cacheKey]=source
  api.JS_LICE_Clear(source.bitmap,0xff000000)
  api.JS_LICE_DrawText(source.bitmap,T.font,text,#text,0,0,TEXT_W,TEXT_H)
  local function ink(x,y)return(floor(api.JS_LICE_GetPixel(source.bitmap,x,y))&0xffffff)~=0 end
  local function row(y)
   for x=0,TEXT_W-1 do if ink(x,y)then return true end end
  end
  local top,bottom=0,TEXT_H-1
  while top<TEXT_H and not row(top)do top=top+1 end
  assert(top<TEXT_H,'Cannot rasterize item label: '..text)
  while not row(bottom)do bottom=bottom-1 end
  local function column(x)
   for y=top,bottom do if ink(x,y)then return true end end
  end
  local left,right=0,TEXT_W-1
  while not column(left)do left=left+1 end
  while not column(right)do right=right-1 end
  source.x,source.y,source.tw,source.th=left,top,right-left+1,bottom-top+1
  source.w,source.h=source.tw+PAD_X*2,source.th+PAD_Y*2
  if short then source.h=T.templates[ch].h end
  api.JS_LICE_Blit(source.bitmap,0,0,source.bitmap,0,0,TEXT_W,TEXT_H,1,'CHANCOPY_RTOA')
  return source
 end
 local function allocate(now)
  local entry
  for i=#T.free,1,-1 do
   if now>=T.free[i].reuseAfter and T.frame>=T.free[i].reuseFrame then entry=table.remove(T.free,i);break end
  end
  if not entry then
   entry={bitmap=assert(api.JS_LICE_CreateBitmap(true,MAX_W,MAX_H),'Cannot allocate item label')}
  end
  return entry
 end
 local function paint(entry,ch,source,compact)
  local bitmap=entry.bitmap
  api.JS_LICE_Clear(bitmap,0xa6000000)
  if not compact then api.JS_LICE_Blit(bitmap,PAD_X,floor((source.h-source.th)/2),source.bitmap,source.x,source.y,source.tw,source.th,1,'COPY ALPHA')end
  api.JS_LICE_ProcessRect(bitmap,0,0,MAX_W,MAX_H,'ALPHAMUL',0)
  entry.ch,entry.compact,entry.source=ch,compact,source
 end
 local function render(project,v,now)
  for _,entry in pairs(T.labels)do entry.seen=false end
  for _,item in ipairs(T.cache)do
   local bounds=T.bounds[item]
   if bounds and bounds[1]<v.finish and bounds[1]+bounds[2]>v.start and api.ValidatePtr2(project,item,'MediaItem*')then
    local ch=T.channels[item]
    local track=api.GetMediaItemTrack(item)
    local y=api.GetMediaTrackInfo_Value(track,'I_TCPY')+api.GetMediaItemInfo_Value(item,'I_LASTY')
    local ih=api.GetMediaItemInfo_Value(item,'I_LASTH')
    if ih>0 and y<v.h and y+ih>0 and api.GetMediaItemInfo_Value(item,'B_FIXEDLANE_HIDDEN')==0 then
     local pos=api.GetMediaItemInfo_Value(item,'D_POSITION')
     local length=api.GetMediaItemInfo_Value(item,'D_LENGTH')
     local left=max(0,(pos-v.start)*v.zoom);local right=min(v.w,(pos+length-v.start)*v.zoom)
     local top=max(0,y);local bottom=min(v.h,y+ih)
     local source=template(ch)
     if right>left and bottom>top then
      if right-left<source.w+2 and bottom-top>=source.h+2 then source=template(ch,true)end
      local compact=right-left<source.w+2 or bottom-top<source.h+2
      local w,h=source.w,source.h
      if compact then
       w=min(w,max(1,ceil(right)-floor(left)-2))
       h=min(h,ceil(bottom)-floor(top))
      end
      local marginX=min(MARGIN,max(0,floor((right-left-w)/2)))
      local marginY=min(MARGIN,max(0,floor((bottom-top-h)/2)))
      local x,yy=max(floor(left),floor(right-w-marginX)),max(floor(top),floor(bottom-h-marginY))
      local entry=T.labels[item]
      if entry and(entry.compact~=compact or not compact and entry.source~=source)then unlink(entry,now);T.free[#T.free+1]=entry;T.labels[item]=nil;entry=nil end
      if not entry then entry=allocate(now);T.labels[item]=entry;paint(entry,ch,source,compact)end
      entry.seen,entry.ch=true,ch
      if not entry.linked or entry.x~=x or entry.y~=yy or entry.w~=w or entry.h~=h or entry.window~=T.window then
       if entry.linked and entry.window~=T.window then unlink(entry,now)end
       if entry.linked then eraseLater(entry,now)end
       local oldx,oldy,oldw,oldh=entry.linked and entry.x or nil,entry.y,entry.w,entry.h
       entry.x,entry.y,entry.window,entry.linked=x,yy,T.window,true
       entry.w,entry.h=w,h
       local result=api.JS_Composite(T.window,x,yy,entry.w,entry.h,entry.bitmap,0,0,entry.w,entry.h,false)
       assert(type(result)=='number'and result>0,'Cannot composite item label: '..tostring(result))
       invalidate(T.window,oldx,oldy,oldw,oldh)
       present(entry)
      end
     end
    end
   end
  end
  for item,entry in pairs(T.labels)do
   if not entry.seen then unlink(entry,now);T.free[#T.free+1]=entry;T.labels[item]=nil end
  end
 end
 local function repair(project,now)
  local v=T.view
  if not v or not next(T.labels)then T.pointerX,T.pointerY,T.editX,T.playX,T.repairPending=nil,nil,nil,nil,nil;return end
  local x,y=api.GetMousePosition();x,y=api.JS_Window_ScreenToClient(T.window,x,y)
  local editX=floor((api.GetCursorPositionEx(project)-v.start)*v.zoom)
  local playX=(api.GetPlayStateEx(project)&1)~=0 and floor((api.GetPlayPositionEx(project)-v.start)*v.zoom)or nil
  local mouse=x~=T.pointerX or y~=T.pointerY
  local edit,play=editX~=T.editX,playX~=T.playX
  local oldX,oldY,oldEdit,oldPlay=T.pointerX,T.pointerY,T.editX,T.playX
  T.pointerX,T.pointerY,T.editX,T.playX=x,y,editX,playX
  if not(mouse or edit or play or T.repairPending)then return end
  T.repairPending=false
  local function point(entry,px,py)
   return px and px+24>=entry.x and px-24<entry.x+entry.w and py+24>=entry.y and py-24<entry.y+entry.h
  end
  local function line(entry,px)return px and px+2>=entry.x and px-2<entry.x+entry.w end
  for _,entry in pairs(T.labels)do
   local touched=mouse and(T.dragging or point(entry,x,y)or point(entry,oldX,oldY)or line(entry,x)or line(entry,oldX))
    or edit and(line(entry,editX)or line(entry,oldEdit))or play and(line(entry,playX)or line(entry,oldPlay))
   if touched then present(entry);entry.repairAt=now+.04
   elseif entry.repairAt and now>=entry.repairAt then present(entry);entry.repairAt=nil end
   if entry.repairAt then T.repairPending=true end
  end
 end
 local function scan(project,now)
  local job=T.job;if not job then return end
  local deadline=api.time_precise()+.0003
  for n=1,256 do
   if job.track then
    if job.itemIndex>=job.itemCount then job.track=nil
    else
     local item=api.GetTrackMediaItem(job.track,job.itemIndex);job.itemIndex=job.itemIndex+1
     if item then
      local _,raw=api.GetSetMediaItemInfo_String(item,key,'',false)
      local ch=tonumber(raw)
      if ch and ch>=1 and ch<=128 and ch%1==0 then
       job.items[#job.items+1]=item;job.channels[item]=floor(ch)
       job.bounds[item]={api.GetMediaItemInfo_Value(item,'D_POSITION'),api.GetMediaItemInfo_Value(item,'D_LENGTH')}
      end
     end
    end
   elseif job.trackIndex<job.trackCount then
    local track=api.GetTrack(project,job.trackIndex);job.trackIndex=job.trackIndex+1
    if track then
     local y=api.GetMediaTrackInfo_Value(track,'I_TCPY');local h=api.GetMediaTrackInfo_Value(track,'I_TCPH')
     if h>0 and not job.anchor then job.anchor=track end
     if h>0 and y<T.view.h and y+h>0 and api.IsTrackVisible(track,false)then
      job.track=track;job.itemIndex=0;job.itemCount=api.CountTrackMediaItems(track)
     end
    end
   else
    T.cache,T.channels,T.bounds,T.anchor=job.items,job.channels,job.bounds,job.anchor;T.job=nil
    local shifted=T.visibility~=job.visibility
    T.pending=shifted or T.view.revision~=job.revision
    if T.pending then T.scanDue=shifted and now or now+.12 end
    render(project,T.view,now);return
   end
   if n%16==0 and api.time_precise()>=deadline then return end
  end
 end
 local function same(a,b)
  return a and a.w==b.w and a.h==b.h and a.start==b.start and a.finish==b.finish and a.zoom==b.zoom
   and a.scroll==b.scroll and a.page==b.page and a.maximum==b.maximum and a.anchorY==b.anchorY
 end
 local function poll(now,project)
  if T.project~=project then
   hide(now);T.project=project;T.job=nil;T.view=nil;T.cache={};T.channels={};T.bounds={};T.anchor=nil;T.pending=true
  end
  if api.EnumProjects(-1,'')~=project then
   hide(now);T.job=nil;T.view=nil;T.cache={};T.channels={};T.bounds={};T.anchor=nil;T.pending=true;return
  end
  local window=T.window
  if not window or not api.JS_Window_IsWindow(window)then
   hide(now);T.window=nil;T.view=nil;T.job=nil;T.pending=true
   window=api.JS_Window_FindChildByID(api.GetMainHwnd(),1000)
   if not window then return end
   if mac then
    T.mode=api.JS_Window_EnableMetal(window)
    if T.mode==1 then error('METAL_MODE_1',0)end
   end
   T.window=window
  end
  if not api.JS_Window_IsVisible(window)then hide(now);T.view=nil;T.job=nil;T.pending=true;return end
  local ok,w,h=api.JS_Window_GetClientSize(window)
  if not ok then hide(now);T.view=nil;T.job=nil;T.pending=true;return end
  local screenX=api.JS_Window_ClientToScreen(window,0,0)
  local start,finish=api.GetSet_ArrangeView2(project,false,screenX,screenX+w,0,0)
  local scrollOK,scroll,page,_,maximum=api.JS_Window_GetScrollInfo(window,'v')
  local v={w=w,h=h,start=start,finish=finish,zoom=finish>start and w/(finish-start)or 0,
   scroll=scrollOK and scroll or nil,page=page,maximum=maximum,revision=api.GetProjectStateChangeCount(project)}
  if not scrollOK and T.anchor and api.ValidatePtr2(project,T.anchor,'MediaTrack*')then v.anchorY=api.GetMediaTrackInfo_Value(T.anchor,'I_TCPY')end
  if v.w<=0 or v.h<=0 or finish<=start or v.zoom<=0 then hide(now);T.view=nil;T.job=nil;T.pending=true;return end
  local previous=T.view;T.view=v
  local changed=not same(previous,v)
  local revision=not previous or previous.revision~=v.revision
  local vertical=not previous or previous.scroll~=v.scroll or previous.h~=v.h or previous.maximum~=v.maximum or previous.page~=v.page or previous.anchorY~=v.anchorY
  if changed then T.layoutUntil=now+.08 end
  if vertical then T.visibility=T.visibility+1;T.pending=true;T.scanDue=now end
  if revision then T.pending=true;T.scanDue=previous and not vertical and not T.forceScan and now+.12 or now end
  if changed or revision or now<(T.layoutUntil or 0)then render(project,v,now)end
 end
 function T:invalidate()self.pending=true;self.scanDue=0;self.forceScan=true end
 function T:setEnabled(on)
  self.enabled=on
  if on then
   if self.error=='METAL_MODE_1'then self.error=nil;self.reported=nil;self.window=nil end
   self.view=nil;self:invalidate()
  else hide(api.time_precise());self.job=nil;self.view=nil;self.cache={};self.channels={};self.bounds={};self.anchor=nil end
 end
 function T:tick(now,project)
  if self.closed then return end
  self.frame=self.frame+1
  if self.error and not self.reported then fail(self.error,now)end
  local ok,err=pcall(function()
   if not self.enabled or self.error then eraseReady(now);return end
   self.dragging=type(api.JS_Mouse_GetState)=='function'and(api.JS_Mouse_GetState(1)&1)~=0
   poll(now,project)
   if now>=self.nextTrim then
    self.nextTrim=now+1
    if #self.free>32 then
     for i=#self.free,1,-1 do
      if #self.free<=32 then break end
      local entry=self.free[i]
      if now>=entry.reuseAfter and self.frame>=entry.reuseFrame then api.JS_LICE_DestroyBitmap(entry.bitmap);table.remove(self.free,i)end
     end
    end
   end
   if self.view and self.pending and not self.job and now>=self.scanDue then
    self.forceScan=false
    self.job={trackIndex=0,trackCount=api.CountTracks(project),items={},channels={},bounds={},revision=self.view.revision,visibility=self.visibility}
   end
   if self.job then
    if self.job.track and not api.ValidatePtr2(project,self.job.track,'MediaTrack*')then self.job=nil;self.pending=true;self.scanDue=now+.12
    else scan(project,now)end
   end
   repair(project,now)
   eraseReady(now)
  end)
  if not ok then fail(err,now)end
 end
 function T:close()
  if self.closed then return end;self.closed=true
  local now=api.time_precise();hide(now);self.job=nil
  local bitmaps={}
  for _,entry in ipairs(self.free)do bitmaps[#bitmaps+1]=entry.bitmap end
  for _,entry in pairs(self.templates)do bitmaps[#bitmaps+1]=entry.bitmap end
  self.free={};self.templates={};self.cache={};self.channels={};self.bounds={};self.anchor=nil
  if self.font then api.JS_LICE_DestroyFont(self.font);self.font=nil end
  if self.gdi then api.JS_GDI_DeleteObject(self.gdi);self.gdi=nil end
  if #bitmaps>0 then
   local frame=0
   local function release()
    frame=frame+1
    if frame<2 or api.time_precise()<now+.2 then api.defer(release);return end
    eraseReady(api.time_precise())
    for _,bitmap in ipairs(bitmaps)do api.JS_LICE_DestroyBitmap(bitmap)end
   end
   api.defer(release)
  end
 end
 return T
end
return M

end)().new(ItemLabelNative,Model.ITEM_CHANNEL_KEY,function(message)
 if message=='METAL_MODE_1'then message=Language.code=='EN'and'The current Metal mode cannot display item labels (same restriction as LOUDNESS TRACE).'or'現在のMetal設定ではChを重ね描画できません（LOUDNESS TRACEと同じ制限）。'end
 status('Ch label: '..message,true)
end)
local function guarded(fn)local ok,e=xpcall(fn,tostring);if not ok then RenderGraphics.abort();status(BLT.publicError(e),true);Language.mb(e,APP_NAME,0)end end
local function changed(keepTargets)
 BLT.invalidate()
 local now=R.time_precise();A.sessionDue=now+.5
 if not keepTargets then A.countAt=nil;A.countDue=now+.25;A.files={};A.targetsDirty=true end
 status('設定を変更しました。',false,now);Model.persistmap(R,m.state);Model.persistembed(R,m.state)
end
local function reload()
 local previous=m.state;m=Model.load(R);BLT.invalidate()
 for _,key in ipairs(Model.appkeys)do if previous[key]~=nil then m.state[key]=Model.clone(previous[key])end end
 A.files={};A.targetsDirty=true;A.countAt=nil;A.countDue=R.time_precise()+.25;status('REAPERから設定を読み込みました。')
 A.sessionDue=R.time_precise()+.5
end
local function native()
 BLT.invalidate();Model.apply(R,m);R.Main_OnCommand(40015,0)
 status('標準画面で変更後「REAPER設定を読込」を押してください。')
end
local function choose(title,options,current,setter)
 local parts,leaves={},{}
 local function caption(text)
  text=Language.message(text):gsub('[%z|\r\n]',' ');if text:find('^[><#!]')then text=' '..text end;return text
 end
 local function emit(rows)
  for _,o in ipairs(rows)do
   if o.children then
    parts[#parts+1]='>'..caption(o[1])
    emit(o.children);parts[#parts+1]='<'
   elseif o[1]==''then parts[#parts+1]=''
   else
    local enabled=o[3]~=false and(not options.available or options.available(o[2]))
    parts[#parts+1]=(enabled and''or'#')..(o[2]==current and'!'or'')..caption(o[1])
    leaves[#leaves+1]={o[2],enabled}
   end
  end
 end
 if options.channelLimit then
  local rows,multi,bucket={},nil,nil
  for _,o in ipairs(options)do
   if o[2]<3 then rows[#rows+1]=o
   else
    if not multi then multi={};rows[#rows+1]={'マルチチャンネル',children=multi}end
    local index=floor(o[2]/10)
    if index~=bucket then
     local group={};multi[#multi+1]={max(3,index*10)..'～'..min(index*10+9,options.channelLimit),children=group};bucket=index
    end
    local group=multi[#multi].children;group[#group+1]=o
   end
  end
  emit(rows)
 else emit(options)end
 gfx.x,gfx.y=gfx.mouse_x,gfx.mouse_y
 local i=gfx.showmenu(table.concat(parts,'|'));local leaf=leaves[i]
 if leaf and leaf[2]and setter(leaf[1])~=false then changed()end
end
do
local Wildcards=(function()
local M={}
local groups={
 {'Project Information','プロジェクト情報',items={
  {'$project','project name','プロジェクト名'},
  {'$projectbase','project name without an auto-increment suffix','自動連番を除いたプロジェクト名',since783=true},
  {'$title','project title (from Project Settings/Notes dialog)','プロジェクトのタイトル (プロジェクト設定/ノート タブより)'},
  {'$author','project author (from Project Settings/Notes dialog)','プロジェクトの作成者 (プロジェクト設定/ノート タブより)'},
  {'$projectnotes','project notes (from Project Settings/Notes dialog)','プロジェクトのメモ (プロジェクト設定/ノート タブより)'},
  {'$projectnotes(name)','value part of project notes matching name=value separated by newline','改行で区切られた name=value 形式のプロジェクトメモの「value」部分'},
  {'$projectdirectory','project directory on disk','ディスク上のプロジェクトディレクトリ'},
  {'$projectdirectoryN','project directory parent level N (example: $directory2 is "a" for /a/b/project.rpp)','N階層上のプロジェクトディレクトリの親 (例: $directory2 is \\"a\\" for /a/b/project.rpp)'},
  {'$track','track name','トラック名'},
  {'$trackslashes','track name, including slash characters','「/」を含むトラック名'},
  {'$tracknumber','1 for the first track, 2 for the second...','1番目のトラックは 1、2番目は 2...'},
  {'$tracknameornumber','track name if the track has a name, otherwise "Track N"','名前があればトラック名、なければトラックNo'},
  {'$seltrack','first selected unmuted track, regardless of whether the track has media or is being rendered','選択されている中の最初の非ミュートのトラック（メディアの有無やレンダリング対象かどうかに関わらず）'},
  {'$folders','track folder structure','トラックのフォルダ構造'},
  {'$folders[X]','track folder structure, separated by X','トラックのフォルダ構造 (X で区切る)'},
  {'$parent','parent track name','親トラック名'},
  {'$tempo','project tempo','プロジェクトのテンポ'},
  {'$timesignature','project time signature formatted as 4-4','プロジェクトの拍子記号（4-4形式）'},
  {'$timesignum','project time signature numerator','プロジェクトの拍子記号（分子）'},
  {'$timesigdenom','project time signature denominator','プロジェクトの拍子記号（分母）'},
  {'$playrate','project play rate','プロジェクトの再生レート'},
  {'$fx','FX list','FXリスト'},
  {'$fx[X]','FX list, separated by X','"X"区切りのFXリスト'},
 }},
 {'Regions/Markers','リージョン/マーカー',items={
  {'$region','region name or ID number','リージョン名またはID番号'},
  {'$region{lane}','region in the specified ruler lane','指定したルーラーレーン内のリージョン'},
  {'$regionname','region name','リージョン名'},
  {'$region(name)','value part of region matching name=value','名前=値に一致するリージョンの値部分'},
  {'$region(name)[s]','value part of region matching name=value separated by s','名前=値に一致するリージョンの値部分、sで区切られたもの'},
  {'$regionnumber','region ID number','リージョンID番号'},
  {'$regionnumber[N]','N for region ID number 1, N+1 for region ID number 2...','リージョン ID 1 なら N、ID 2 なら N+1...'},
  {'$marker','marker name or ID number','マーカー名または ID 番号'},
  {'$marker{lane}','marker in the specified ruler lane','指定したルーラーレーン内のマーカー'},
  {'$markername','marker name','マーカー名'},
  {'$marker(name)','value part of marker matching name=value','名前=値に一致するマーカーの値部分'},
  {'$marker(name)[s]','value part of marker matching name=value separated by s','名前=値に一致するマーカーの値部分、sで区切られたもの'},
  {'$markernumber','marker ID number','マーカーID番号'},
  {'$markernumber[N]','N for marker ID number 1, N+1 for marker ID number 2...','マーカー ID 1 なら N、ID 2 なら N+1...'},
 }},
 {'Media Items','メディアアイテム',items={
  {'$item','media item take name','メディアアイテムのテイク名'},
  {'$itemnumber','1 for the first media item on a track, 2 for the second...','トラック上のアイテムを先頭から1、2…と数えた番号'},
  {'$itemnotes','media item notes','メディアアイテムのアイテムメモ'},
  {'$itemnotes(name)','value part of media item notes matching name=value separated by newline','改行で区切られた「名前=値」形式のメディアアイテムメモのうち、名前に一致する値の部分'},
  {'$takemarker','media item take marker (first take marker within the item)','メディアアイテムのテイクマーカー (アイテム内の最初のもの)'},
  {'$takemarker(name)','value part of media item take marker matching name=value','名前=値に一致するメディアアイテムテイクマーカーの値部分'},
  {'$takemarker(name)[s]','value part of media item take marker matching name=value separated by s','名前=値に一致するメディアアイテムテイクマーカーの値部分、sで区切られたもの'},
  {'$lane','media item lane number','アイテムのレーン番号'},
 }},
 {'Position/Length','位置/長さ',items={
  {'$start','start time as M-SS.TTT','開始時間をM-SS.TTT形式で表示'},
  {'$end','end time as M-SS.TTT','終了時間をM-SS.TTT形式で表示'},
  {'$length','length as M-SS.TTT','長さをM-SS.TTT形式で表示'},
  {'$startbeats','start time as measures.beats','開始時間を小節.拍で表示'},
  {'$endbeats','end time as measures.beats','終了時間を小節.拍で表示'},
  {'$lengthbeats','length as measures.beats','長さを小節.拍で表示'},
  {'$starttc','start time as HH.MM.SS.FF','開始時間をHH.MM.SS.FF形式で表示'},
  {'$endtc','end time as HH.MM.SS.FF','終了時間をHH.MM.SS.FF形式で表示'},
  {'$startframes','start time as absolute frames','開始時間を絶対フレームで表示'},
  {'$endframes','end time as absolute frames','終了時間を絶対フレームで表示'},
  {'$lengthframes','length as absolute frames','長さを絶対フレームで表示'},
  {'$startseconds','start time as total seconds','開始時間を総秒数で表示'},
  {'$endseconds','end time as total seconds','終了時間を総秒数で表示'},
  {'$lengthseconds','length as total seconds','長さを総秒数で表示'},
  {'$lenhh','length as hours','長さを時間で表示'},
  {'$lenmm','length as minutes modulo hours','長さを時間単位の分で表示'},
  {'$lenss','length as seconds modulo minutes','長さを分単位の秒で表示'},
  {'$lentt','length as milliseconds modulo seconds','長さを秒単位のミリ秒で表示'},
 }},
 {'Recording','録音',items={
  {'$filenumber','1 for the first file rendered, 2 for the second...','レンダリングされた 1番目のファイルは 1、2番目は 2...'},
  {'$filenumber[N]','N for the first file rendered, N+1 for the second...','レンダリングされた 1番目のファイルは N、2番目は N+1...'},
  {'$filecount','the total number of rendered files','レンダリングされたファイルの総数'},
  {'$note','C0 for the first file rendered,C#0 for the second...','1番目のレンダリングファイルは C0、2番目は C#0... (音名)'},
  {'$note[X]','X (example: B2) for the first file rendered, X+1 (example: C3) for the second...','1番目のレンダリングファイルは X (例: B2)、2番目は X+1 (例: C3)...'},
  {'$natural','C0 for the first file rendered, D0 for the second...','1番目のレンダリングファイルは C0、2番目は D0... (全音)'},
  {'$namenumber','1 for the first region or item with the same name, 2 for the second...','同名のリージョン/アイテム 1番目は 1、2番目は 2...'},
  {'$timelineorder','1 for the first item or region on the timeline, 2 for the second...','タイムライン上の 1番目のアイテム/リージョンは 1、2番目は 2...'},
  {'$timelineorder[N]','N for the first item or region on the timeline, N+1 for the second...','タイムライン上の 1番目のアイテム/リージョンは N、2番目は N+1...'},
  {'$timelineorder_track','1 for the first item or region on the timeline on this track, 2 for the second...','トラックのタイムライン上の 1番目のアイテム/リージョンは 1、2番目は 2...'},
  {'$timelineorder_track[N]','N for the first item or region on the timeline on this track, N+1 for the second...','トラックのタイムライン上の 1番目のアイテム/リージョンは N、2番目は N+1...'},
 }},
 {'Output Format','出力フォーマット',items={
  {'$format','render format (example: wav)','レンダリング形式 (例: wav)'},
  {'$samplerate','sample rate in Hz','サンプリングレート (Hz)'},
  {'$sampleratek','sample rate in kHz','サンプリングレート (kHz)'},
  {'$bitdepth','bit depth, if available','ビット深度 (利用可能な場合)'},
 }},
 {'Channels','Ch',items={
  {'$channels','number of render channels','レンダーチャンネルの数'},
  {'$chid','render channel number, or provide channel IDs like $chid(L,R,C,LFE,Ls,Rs) or $chid{3}(L,R,C)','レンダーチャンネル番号、または $chid(L,R,C,LFE,Ls,Rs) や $chid{3}(L,R,C) のようなチャンネルIDを指定'},
 }},
 {'Date/Time/Unique ID','日付/時刻/ユニークID',items={
  {'$date','date','日付'},
  {'$time','time','時間'},
  {'$datetime','date+time','日付+時刻'},
  {'$year','year','年'},
  {'$year2','last 2 digits of the year','年の下2桁'},
  {'$month','month number','月番号'},
  {'$monthname','month name','月名'},
  {'$day','day of the month','日'},
  {'$dayname','day of the week','曜日'},
  {'$hour','hour of the day in 24-hour format','時 (24時間制)'},
  {'$hour12','hour of the day in 12-hour format','時 (12時間制)'},
  {'$ampm','am if before noon, pm if after noon','正午前ならam、正午後ならpm'},
  {'$minute','minute of the hour','分'},
  {'$second','second of the minute','秒'},
  {'$localtime','date+time string','日付＋時刻文字列'},
  {'$uniqueid[N]','N-character random hexadecimal string, N must be between 8 and 16','N文字のランダム16進文字列（Nは8～16）'},
 }},
 {'Computer Information','コンピューター情報',items={
  {'$user','user name','ユーザー名'},
  {'$computer','computer name','コンピューター名'},
 }},
}
function M.menu(api,language,render783)
 local rows={};local jp=language~='EN'
 for _,group in ipairs(groups)do
  local items={}
  for _,item in ipairs(group.items)do
   if not item.since783 or render783~=false then items[#items+1]={item[1]..' : '..item[jp and 3 or 2],item[1]}end
  end
  rows[#rows+1]={group[jp and 2 or 1],children=items}
 end
 local recent={}
 if api.get_ini_file then
  local f=io.open(api.get_ini_file(),'r')
  if f then
   local section,patterns,count=false,{},0
   for line in f:lines()do
    local name=line:gsub('^\239\187\191',''):match('^%[([^%]]+)%]')
    if name then if section then break end;section=name:lower()=='reaper'end
    if section then local index,pattern=line:match('^render_pattern_(%d+)=(.*)$');index=tonumber(index)
     if index and index<16 and pattern~=''and not patterns[index]then patterns[index]=pattern;count=count+1;if count==16 then break end end
    end
   end
   f:close()
   for i=0,15 do if patterns[i]then recent[#recent+1]={patterns[i],'recent:'..patterns[i]}end end
  end
 end
 rows[#rows+1]={''}
 rows[#rows+1]={jp and'最近使用したワイルドカードパターン'or'Recent wildcard patterns',children=#recent>0 and recent or{{jp and'履歴なし'or'No recent patterns','',false}}}
 rows[#rows+1]={jp and'ワイルドカードのヘルプ…'or'Wildcard help...','help'}
 return rows
end
function M.help(language)
 if language=='EN'then return 'The menu follows REAPER 7.83 render wildcards.\n\n$projectbase removes an auto-increment suffix from the project name (REAPER 7.83+).\n\nReplace name / lane / N / X / s in parameterized entries with your value.\n$region(name)[;] reads a name=value field separated by semicolons.\n$projectnotes(name) and $itemnotes(name) read newline-separated fields.\n$regionnumber[01] produces 01, 02, ...\n$region[<4] keeps the first four characters.\n$track< > removes spaces; $track< _> replaces spaces with underscores.\n$Project capitalizes the first letter; $PROJECT makes all letters uppercase; $pROJECT makes all letters lowercase.\n$trackslashes and $folders may create subdirectories.\n\nRecent patterns replace the whole filename pattern; other entries append a wildcard.'end
 return 'REAPER 7.83のレンダー用ワイルドカードに対応しています。\n\n$projectbase はプロジェクト名末尾の自動連番を除きます（REAPER 7.83以降）。\n\n引数付きの項目は name / lane / N / X / s を実際の値に置き換えてください。\n$region(name)[;] は ; 区切りの name=value から値を取得します。\n$projectnotes(name) と $itemnotes(name) は改行区切りです。\n$regionnumber[01] は 01, 02, ... の連番です。\n$region[<4] は先頭4文字に制限します。\n$track< > は空白を削除、$track< _> は空白を _ に置換します。\n$Project は先頭を大文字、$PROJECT は全て大文字、$pROJECT は全て小文字にします。\n$trackslashes と $folders はサブフォルダーを作成する場合があります。\n\n履歴はファイル名全体を置き換え、その他の項目はワイルドカードを末尾に追加します。'
end
return M

end)()
function A.wildcards()
 local rows=Wildcards.menu(R,Language.code,Model.render783)
 choose('ワイルドカード',rows,nil,function(value)
  if value=='help'then Language.mb(Wildcards.help(Language.code),'Render Wildcards',0);return false
  elseif value:sub(1,7)=='recent:'then m.state.s.RENDER_PATTERN=value:sub(8)
  else m.state.s.RENDER_PATTERN=m.state.s.RENDER_PATTERN..value end
 end)
end
end
local function current_text(options,v)for _,o in ipairs(options)do if o[2]==v then return o[1]end end;return tostring(v)end
local IME={};local E
function A.flash_field(id)if id then RenderUI.now=R.time_precise();RenderUI:flash(id);wake_visuals()end end
local function finish_edit(cancel)
 if not E then return true end
 local e=E;E=nil;IME.active=false;IME.ctx=nil;IME.font=nil
 if cancel then return true end
 local value=e.text
 if e.numeric then value=tonumber(value);if not finite(value)then A.flash_field(e.id);status('数値を入力してください。',true);return false end end
 local ok,err=pcall(e.setter,value)
 if not ok then status(BLT.publicError(err),true);return false end
 changed();return true
end
local function edit(caption,value,setter,numeric,id)
 if E and not finish_edit(false)then return end
 local b=A.editBounds or{x=30,y=120,w=W-60,h=31}
 E={text=tostring(value or ''),setter=setter,numeric=numeric,id=id,bounds={x=b.x,y=b.y,w=b.w,h=b.h}}
 IME.api,IME.ctx,IME.font=gfx.inputContext(fonts[1])
 IME.active=true;IME.frames=0;wake_visuals()
end
local function rgba(c)return(floor(c[1]*255+.5)<<24)|(floor(c[2]*255+.5)<<16)|(floor(c[3]*255+.5)<<8)|255 end
local function ime_frame()
 if not E then return end
 local I,ctx,_,wx,wy=gfx.inputContext(fonts[1]);local b=E.bounds
 local w,h=b.w*scale,b.h*scale
 I.PushStyleVar(ctx,I.StyleVar_FrameRounding,0);I.PushStyleVar(ctx,I.StyleVar_FrameBorderSize,0)
 I.PushStyleColor(ctx,I.Col_FrameBg,rgba(C.field));I.PushStyleColor(ctx,I.Col_Text,rgba(C.text))
 I.PushFont(ctx,IME.font,13*scale)
 I.PushStyleVar(ctx,I.StyleVar_FramePadding,7*scale,max(0,(h-I.GetTextLineHeight(ctx))/2))
 I.SetCursorScreenPos(ctx,wx+sx(b.x),wy+sy(b.y));I.SetNextItemWidth(ctx,w)
 if IME.frames==0 then I.SetKeyboardFocusHere(ctx)end
 local _,text=I.InputText(ctx,'##render_value',E.text,I.InputTextFlags_AutoSelectAll);E.text=text
 local cancel=I.IsKeyPressed(ctx,I.Key_Escape,false)
 local done=I.IsItemDeactivated(ctx)or I.IsKeyPressed(ctx,I.Key_Enter,false)or I.IsKeyPressed(ctx,I.Key_KeypadEnter,false)
 local focused=I.IsWindowFocused(ctx)
 I.PopFont(ctx);I.PopStyleColor(ctx,2);I.PopStyleVar(ctx,3);IME.frames=IME.frames+1
 if cancel then finish_edit(true)elseif IME.frames>1 and(done or not focused)then finish_edit(false)end
end

local function small_button(id,text,x,y,w,h,fn,enabled)
 enabled=enabled~=false and not A.controlsDisabled
 local opt=render_options(id);opt.enabled,opt.selected,opt.led=enabled,nil,nil
 opt.size,opt.labelInset=13/density,5/density
 opt.variant=(id=='embedClear' or id=='embedMono' or id=='embedStereo' or id=='embedCustom') and 'clear' or nil
 RenderUI.C=C;RenderUI:button(id,Language.message(text),x/density,y/density,w/density,h/density,opt)
 widget(id,x,y,w,h,fn,enabled)
end
local panelOptions={glow=false,panel=true}
local function block_surface(x,y,w,h,joined)
 panelOptions.palette=C;RenderUI.joinedPanel=joined
 RenderUI:frame(x/density,y/density,w/density,h/density,panelOptions);RenderUI.joinedPanel=nil
end
local function field(id,title,value,x,y,w,fn,enabled,menu,valueEnabled)
 enabled=enabled~=false and not A.controlsDisabled
 if title~=''then label(title,x,y,12,C.muted,1,w,18)end
 local h=22;local yy=y+(title==''and 0 or 15)
 RenderUI.C=C;RenderUI:fieldFrame(id,x/density,yy/density,w/density,h/density,enabled,E and E.id==id)
 local state=RenderUI:state(id);state.renderSeen=RenderUI.frameSerial
 local textSize=id=='channels'and 12 or 13
 local inset=menu and 24 or 14
 font(textSize,1,false);local t=BLT.ui.fit(Language.message(tostring(value or '')),max(5,(w-inset-2)*scale))
 label(t,x+7,yy,textSize,enabled and valueEnabled~=false and C.text or C.faint,1,w-inset,h,4,false,true)
 if menu then
  line(x+w-16,yy+9,x+w-13,yy+12,C.faint,.9);line(x+w-13,yy+12,x+w-10,yy+9,C.faint,.9)
 end
 if fn then widget(id,x,yy,w,h,fn,enabled)end
end
local function selectfield(id,title,options,value,x,y,w,setter,enabled)
 field(id,title,current_text(options,value),x,y,w,function()choose(title,options,value,setter)end,enabled,true,not options.available or options.available(value))
end
function A.numeric_spec(key,db,lo,hi,group,step,integer)
 group=group or'n'
 local spec={id=key,step=step or(db and 1 or key=='RENDER_TAILMS'and 10 or .01),integer=integer}
 spec.get=function()local v=m.state[group][key];return db and 20*math.log(max(v,1e-12),10)or v end
 spec.set=function(n)
  if not finite(n)then A.flash_field(spec.id);return end
  local requested=n;n=clamp(n,lo or -math.huge,hi or math.huge)
  local gap=1/math.max(1,m.state.n.RENDER_SRATE>0 and m.state.n.RENDER_SRATE or 48000)
  if key=='RENDER_STARTPOS'then n=math.min(n,m.state.n.RENDER_ENDPOS-gap)
  elseif key=='RENDER_ENDPOS'then n=math.max(n,m.state.n.RENDER_STARTPOS+gap)end
  if integer then n=floor(n+.5)end
  if math.abs(n-requested)>1e-10 then A.flash_field(spec.id)end
  local value=db and 10^(n/20)or n
  if m.state[group][key]==value then return false end
  m.state[group][key]=value;return true
 end
 return spec
end
local function numberfield(key,title,x,y,w,db,lo,hi,inline,group,step,integer)
 local spec=A.numeric_spec(key,db,lo,hi,group,step,integer);local v=spec.get()
 field(key,inline and''or title,string.format('%.6g',v)..(inline and' ms'or''),x,y,w,function()
  edit(title,string.format('%.17g',spec.get()),spec.set,true,key)
 end)
 widgets[#widgets].numeric=spec
 local hit=widgets[#widgets];if hit.enabled then gfx.wheelRegion(sx(hit.x),sy(hit.y),hit.w*scale,hit.h*scale)end
end
function A.numeric_input(hit,down,wasDown,mouseY)
 local spec=hit and hit.enabled and hit.numeric
 if gfx.mouse_wheel~=0 and spec then
  if finish_edit(false)then
   local fine=(gfx.mouse_cap&8)~=0 and not spec.integer
   if spec.set(spec.get()+(gfx.mouse_wheel>0 and 1 or -1)*spec.step*(fine and .1 or 1))then changed()end
  end
  gfx.mouse_wheel=0
 end
 if down and not wasDown and spec and finish_edit(false)then A.numericDrag={spec=spec,y=mouseY,moved=false}end
 local d=A.numericDrag
 if d and down then
  local fine=(gfx.mouse_cap&8)~=0 and not d.spec.integer;local pixels=fine and 8 or 3
  if d.fine~=fine then d.fine=fine;d.y=mouseY end
  local delta=d.y-mouseY
  if math.abs(delta)>=pixels then
   local steps=delta>0 and floor(delta/pixels)or -floor(-delta/pixels)
   d.moved=true;d.y=d.y-steps*pixels
   if d.spec.set(d.spec.get()+steps*d.spec.step*(fine and .1 or 1))then changed()end
  end
 end
 if d and not down then A.numericDrag=nil;return d.moved end
 return false
end
local function strfield(key,title,x,y,w)
 field(key,title,m.state.s[key],x,y,w,function()edit(title,m.state.s[key],function(s)m.state.s[key]=s end)end)
end
A.optionHelp={
 ['RENDER_SETTINGS:4']={
  JP='多チャンネルのトラックを、チャンネル数を保ったファイルとして書き出します。\nステレオにまとめず、個別チャンネルを残したい場合に使います。',
  EN='Export multichannel tracks as multichannel files.\nUse this to retain separate channels instead of reducing them to stereo.'},
 ['RENDER_SETTINGS:16']={
  JP='モノラル素材だけを含むトラックは、モノラルファイルとして書き出します。\nステムごとに不要なステレオ化を避けたい場合に使います。',
  EN='Export tracks containing only mono media as mono files.\nUse this to avoid unnecessary stereo files when rendering stems.'},
 ['RENDER_SETTINGS:16384']={
  JP='ステムのうち、親フォルダー／マスターへ送っているチャンネルだけを書き出します。\n親へ送らない内部用のチャンネルを出力から外します。',
  EN='Export only the stem channels sent to the parent track or master.\nChannels used internally but not sent to the parent are omitted.'},
 ['RENDER_SETTINGS:8192']={
  JP='トラックフェーダーによる音量調整より前の信号を、ステムとして書き出します。\nミックスのフェーダー値を出力音量に反映したくない場合に使います。',
  EN='Render stems before the track volume fader.\nUse this when the mix fader level should not determine the exported level.'},
 ['RENDER_SETTINGS:2048']={
  JP='同じ範囲を2回処理し、2回目の音を出力します。\n開始直後のFXの状態を整えたい場合に使います。処理時間は増えます。',
  EN='Process the range twice and export the second pass.\nThis can help settle FX state at the start, at the cost of extra rendering time.'},
 ['RENDER_SETTINGS:524288']={
  JP='マスター経由の複数出力を並列に処理します。\nCPUやFXによって、高速化の効果とメモリー使用量が変わります。',
  EN='Process multiple outputs through the master in parallel.\nThe speed benefit and memory use depend on the CPU and FX.'},
 ['RENDER_SETTINGS:262144']={
  JP='選択アイテム、またはレイザー領域を個別ファイルにせず、1ファイルに結合して書き出します。\n対象によって、このスイッチの表示名が切り替わります。',
  EN='Render the selected items or razor edits together as one file instead of separate files.\nThe label follows the current render source.'},
 ['RENDER_SETTINGS:256']={
  JP='音の立ち上がり位置を示すトランジェントガイドを、対応する形式のファイルに埋め込みます。\n対応アプリでタイミング編集の目印として利用できます。',
  EN='Embed transient guides in a supported output format.\nCompatible applications can use these onset positions as editing guides.'},
 ['RENDER_SETTINGS:1024']={
  JP='素材のテイクマーカーを、対応する形式の出力ファイルに埋め込みます。\nファイル内に編集の目印を引き継ぎたい場合に使います。',
  EN='Embed take markers in a supported output format.\nUse this to carry editing reference points into the exported file.'},
 ['RENDER_SETTINGS:65536']={
  JP='元ソース内での開始位置情報を、可能な場合に引き継ぎます。\nアイテム／レイザーを個別に書き出す場合に使います。',
  EN='Preserve the source start offset when possible.\nThis applies when rendering individual items or razor edits.'},
 ['RENDER_SETTINGS:131072']={
  JP='可能な場合に、元メディアのサンプルレートを保って個別に書き出します。\n一括結合など、対応しない設定では適用されません。',
  EN='Preserve each source media sample rate when possible.\nThis is not applied to incompatible settings such as combined output.'},
 ['projrenderrateinternal:1']={
  JP='ミックスとFXをプロジェクトのサンプルレートで処理し、出力レートへ変換します。\n出力レートを変えても、FXの処理レートを維持したい場合に使います。',
  EN='Process the mix and FX at the project sample rate, then convert to the output rate.\nUse this to keep the FX processing rate when exporting at a different rate.'},
 ['RENDER_DITHER:1']={
  JP='書き出し時に微小なノイズを加え、ビット深度を下げる際の量子化歪みを抑えます。\n主に整数PCMへ最終出力する場合に使います。',
  EN='Add low-level noise to reduce quantization distortion when reducing bit depth.\nPrimarily useful for final output to integer PCM.'},
 ['RENDER_DITHER:2']={
  JP='量子化ノイズの周波数分布を調整し、耳につきにくくします。\n主に整数PCMへの最終出力で使うノイズ整形の設定です。',
  EN='Shape the frequency distribution of quantization noise to make it less audible.\nPrimarily intended for final integer PCM output.'},
 ['RENDER_DITHER:4']={
  JP='個別トラックの書き出しであるステムにもディザを適用します。\nビット深度を下げる場合の量子化歪みを抑えます。',
  EN='Apply dither to stem outputs as well.\nThis reduces quantization distortion when reducing their bit depth.'},
 ['RENDER_DITHER:8']={
  JP='個別トラックの書き出しであるステムにもノイズ整形を適用します。\n量子化ノイズの周波数分布を調整します。',
  EN='Apply noise shaping to stem outputs as well.\nThis adjusts the frequency distribution of their quantization noise.'},
 ['RENDER_DITHER:16']={
  JP='ONにすると、ディザとノイズ整形をまとめて無効にします。\n各スイッチの設定値は保持したまま、出力への適用を止めます。',
  EN='Disable all dithering and noise shaping.\nThe individual settings are retained but are not applied to the output.'},
 ['RENDER_ADDTOPROJ:1']={
  JP='レンダー完了後、生成したファイルをプロジェクトの新規トラックへ追加します。\nすぐに再生・確認したい場合に使います。',
  EN='Add rendered files to new tracks in the project after rendering.\nUse this to audition or inspect the results immediately.'},
 ['RENDER_ADDTOPROJ:2']={
  JP='REAPERが無音と判断した出力対象は、ファイルを書き出しません。\n音が入っていないステムなどの不要なファイルを減らします。',
  EN='Skip outputs that REAPER determines are likely silent.\nUse this to avoid unnecessary files such as silent stems.'},
 ['renderclosewhendone:16']={
  JP='同名ファイルがある場合、番号を付けた別名で自動保存します。\n既存ファイルの上書きを避けたい場合に使います。',
  EN='Automatically number output files when a filename already exists.\nUse this to avoid overwriting existing files.'},
 ['renderclosewhendone:32768']={
  JP='レンダー結果の統計をHTMLレポートとして保存します。\n書き出し後に出力結果の情報を確認・記録したい場合に使います。',
  EN='Save rendering statistics as an HTML report.\nUse this to review or keep a record of the output results.'},
 ['renderpeaks:512']={
  JP='レンダー中もREAPERのトラックメーターを表示します。\nOFFではメーターの更新を抑えます。音声の処理や出力内容は変わりません。',
  EN='Show REAPER track meters while rendering.\nTurning this off avoids their display updates; the rendered audio is unchanged.'},
 ['renderclosewhendone:2097152']={
  JP='最後のレンダー統計をメモリに保持し、後からREAPERの統計表示アクションで開けるようにします。\nファイルとして保存するにはHTML出力も指定してください。',
  EN='Keep the last render statistics in memory for REAPER statistics actions.\nSelect HTML export as well if you need a report saved to disk.'},
 ['renderpeaks:4']={
  JP='LUFS-Iのゲート計算に含まれない区間を、統計グラフで色分けします。\nLUFS統計とラウドネスグラフを有効にした場合に使います。',
  EN='Shade graph areas excluded by the LUFS-I gate.\nAvailable with LUFS statistics and a loudness graph enabled.'},
 ['renderclosewhendone:128']={
  JP='ピーク表示で基準を超えた箇所を強調します。\n書き出す音声をリミットする設定ではありません。',
  EN='Highlight overs in the render peaks display.\nThis does not limit the exported audio.'},
 ['stats_paths']={
  JP='HTML統計に出力ファイルのパスを含めます。\n外部へ共有するレポートからパスを隠す場合はOFFにしてください。',
  EN='Include output file paths in HTML statistics.\nTurn this off to hide paths in reports you share.'},
 ['stats_regions']={
  JP='HTML統計にプロジェクトのリージョンとマーカーを表示します。\n音声ファイルへのマーカー埋め込み設定とは別です。',
  EN='Include project regions and markers in HTML statistics.\nThis is separate from marker embedding in the audio file.'},
 ['RENDER_SETTINGS:1048576']={
  JP='開始待機の秒数だけ待ってからレンダーを開始します。\nFXの初期化やサンプルの読み込みが完了する時間を確保します。',
  EN='Wait for the specified start delay before rendering.\nThis gives FX time to initialize and load samples.'},
}
function A.detail_tip(clientX,clientY)
 if A.tab~=2 or A.busy or E or Chrome.mouseActive or(gfx.mouse_cap&67)~=0 then return end
 local x,y=(clientX-ox)/scale,(clientY-oy)/scale
 for _,v in ipairs(widgets)do
  if v.tip and x>=v.x and x<=v.x+v.w and y>=v.y and y<=v.y+v.h then return v.tip,3 end
 end
end
local function tick(id,title,on,x,y,w,fn,enabled,keepTargets)
 enabled=enabled~=false and not A.controlsDisabled
 font(12,1,false);local text=BLT.ui.fit(Language.text(title),(w-31)*scale)
 local opt=render_options(id);opt.background,opt.showState=false,false
 opt.size,opt.switchScale=12/density,20/(44*density)
 RenderUI.C=C;local _,_,hitWidth=RenderUI:toggle(id,text,on,x/density,y/density,w/density,20/density,enabled,opt)
 widget(id,x,y,hitWidth*density,20,function()if enabled==false then return end;fn(not on);changed(keepTargets)end,enabled)
 local help=A.tab==2 and A.optionHelp[id]
 if help then
  local tip=Language.text(title)..'\n'..help[Language.code]
  if not enabled then tip=tip..(Language.code=='EN'and'\nUnavailable for the current source, format or REAPER environment.\nThe setting is retained but is not applied when rendering.'or'\n現在の対象・形式またはREAPER環境では利用できません。\n設定値は保持され、書き出し時には適用されません。')end
  widgets[#widgets].tip=tip
 end
end
local function bit(key,mask,title,x,y,w,group)
 local values=m.state[group or 'n'];local available=values[key]~=nil
 available=available and Model.optionenabled(m.state,key,mask)
 local v=values[key] or 0
 tick(key..':'..mask,title,(v&mask)~=0,x,y,w,function(on)values[key]=on and (v|mask)or(v&~mask)end,available)
end
local function bitsselect(key,mask,title,options,x,y,w)
 options.available=function(v)return Model.postchoice(m.state,key,mask,v)end
 selectfield(key..':'..mask,title,options,m.state.n[key]&mask,x,y,w,function(v)m.state.n[key]=(m.state.n[key]&~mask)|v end)
end
local function cfgselect(key,title,options,x,y,w)
 selectfield(key,title,options,m.state.c[key],x,y,w,function(v)m.state.c[key]=v end,m.state.c[key]~=nil)
end
local function section(title,x,y,w,h)
 if h then block_surface(x-12,y-12,w+24,h)end
 label(title,x,y,15,C.text,1,w,20,0,true);line(x,y+21,x+w,y+21,C.edge,.22)
end
local function formatfield(key,title,x,y,w,allowOff)
 field(key,title,Model.formatname(m.state.s[key]),x,y,w,function()
  local choices={};if allowOff then choices[#choices+1]={'なし',''}end
  for _,v in ipairs(Model.formats)do choices[#choices+1]=v end
  choose(title,choices,Model.decode(m.state.s[key]):sub(1,4),function(v)
   if Model.decode(m.state.s[key]):sub(1,4)~=v then m.state.s[key]=v;local a=Model.decode(m.state.s.RENDER_FORMAT):sub(1,4);local b=Model.decode(m.state.s.RENDER_FORMAT2):sub(1,4);m.state.n.RENDER_CHANNELS=math.min(Model.channelmax(a),Model.channelmax(b),m.state.n.RENDER_CHANNELS);if(a=='l3pm'or b=='l3pm')and m.state.n.RENDER_SRATE>48000 then m.state.n.RENDER_SRATE=48000 end end
  end)
 end,true,true)
end
local tabLayouts={}
local function tabrow(id,titles,current,x,y,w,h,size,setter,joined)
 local layout=tabLayouts[id];local signature=table.concat(titles,'|')
 if not layout or layout.language~=Language.code or layout.scale~=scale or layout.dpi~=gfx.ext_retina or layout.signature~=signature or layout.w~=w or layout.joined~=joined then
  layout={language=Language.code,scale=scale,dpi=gfx.ext_retina,signature=signature,w=w,joined=joined,widths={}};tabLayouts[id]=layout
  local total=0;layout.size=size
  repeat
   total=0;font(layout.size,1,true)
   for i,title in ipairs(titles)do local width=math.ceil(gfx.measurestr(Language.text(title))/scale)+24;layout.widths[i]=width;total=total+width end
   if total+4*(#titles-1)<=w or layout.size<=10 then break end
   layout.size=layout.size-1
  until false
  local factor=min(1,(w-4*(#titles-1))/total)
  for i,width in ipairs(layout.widths)do layout.widths[i]=joined and(w-4*(#titles-1))/#titles or width*factor end
 end
 local px=x
 for i,title in ipairs(titles)do
  local width=layout.widths[i];local opt=render_options(id..i)
  opt.enabled,opt.selected,opt.led=true,current==i,'top';opt.ledScale=h/(44*density)
  opt.size,opt.bold,opt.labelInset=layout.size/density,true,5/density
  RenderUI.C=C;RenderUI.joinedTab=joined
  RenderUI:button(id..i,Language.text(title),px/density,y/density,width/density,h/density,opt);RenderUI.joinedTab=nil
  local index=i;widget(id..i,px,y,width,h,function()setter(index)end);px=px+width+4
 end
end
local function selection_switch(id,title,x,y,w,enabled)
 tick(id,title,m.state[id]==true,x,y,w,function(on)m.state[id]=on end,enabled)
 local hit=widgets[#widgets];hit.y,hit.h=y-2,24
end
local function basic()
 local x1,x2,w=36,W/2+19,W/2-55
 section('SOURCE / ソース選択',x1,120,w,210)
 selectfield('source','対象（ソース）',Model.sources,Model.sourcechoice(m.state),x1,146,w,function(v)Model.setsource(m.state,v)end,true)
 local item=Model.itemsource(m.state)or Model.razorsource(m.state)
 if item and m.state.n.RENDER_BOUNDSFLAG~=4 then m.state.n.RENDER_BOUNDSFLAG=4;BLT.invalidate()end
 selectfield('bounds','範囲',Model.boundchoices(m.state),m.state.n.RENDER_BOUNDSFLAG,x1,189,w,function(v)m.state.n.RENDER_BOUNDSFLAG=v end,not item)
 if m.state.n.RENDER_BOUNDSFLAG==0 then
  numberfield('RENDER_STARTPOS','開始（秒）',x1,228,(w-14)/2,false,-360000,360000)
  numberfield('RENDER_ENDPOS','終了（秒）',x1+(w+14)/2,228,(w-14)/2,false,-360000,360000)
 end
 local tails={[0]=1,[1]=2,[2]=4,[3]=8,[4]=16,[5]=32,[6]=8,[7]=32}
 local tailY=m.state.n.RENDER_BOUNDSFLAG==0 and 275 or 236
 bit('RENDER_TAILFLAG',tails[m.state.n.RENDER_BOUNDSFLAG]or 1,'テールを追加',x1,tailY,w/2)
 numberfield('RENDER_TAILMS','テール長（ms）',x1+(w+14)/2,tailY,(w-14)/2,false,0,3600000,true)
 if Model.itemsource(m.state)then
  selection_switch('excludeFolderContents','フォルダアイテムの中身を除外',x1,267,w,true)
  selection_switch('excludeUnnamedItems','無名のアイテムを除外',x1,291,w,true)
 elseif Model.matrixsource(m.state)then
  small_button('regionManager','リージョン管理',x1,265,126,25,function()R.Main_OnCommand(40326,0)end)
  small_button('regionMatrix','マトリックス',x1+138,265,w-138,25,function()R.Main_OnCommand(41888,0)end)
 elseif Model.razorsource(m.state)then
  bit('RENDER_SETTINGS',4<<16,'レイザー領域を1ファイルに結合',x1,267,w)
 elseif m.state.n.RENDER_BOUNDSFLAG>=3 and m.state.n.RENDER_BOUNDSFLAG~=4 then
  small_button('regionManager','リージョン / マーカー管理',x1,265,w,25,function()R.Main_OnCommand(40326,0)end)
 end
 section('FORMAT / 形式・レート',x2,120,w,210)
 A.formatTab=A.formatTab or 1
 tabrow('formatTab',{'メイン出力','二次出力'},A.formatTab,x2,146,w,22,12,function(i)A.formatTab=i end)
 local formatkey=A.formatTab==2 and'RENDER_FORMAT2'or'RENDER_FORMAT'
 formatfield(formatkey,'出力形式',x2,173,w-60,A.formatTab==2)
 small_button('encoderDetails','詳細',x2+w-52,188,52,22,native)
 local rates={{'プロジェクト設定',0},{'44,100 Hz',44100},{'48,000 Hz',48000},{'88,200 Hz',88200},{'96,000 Hz',96000},{'192,000 Hz',192000}}
 local raw=Model.decode(m.state.s[formatkey]);local codec=raw:sub(1,4)
 if Model.decode(m.state.s.RENDER_FORMAT):sub(1,4)=='l3pm'or Model.decode(m.state.s.RENDER_FORMAT2):sub(1,4)=='l3pm'then rates={{'プロジェクト設定',0},{'8,000 Hz',8000},{'11,025 Hz',11025},{'12,000 Hz',12000},{'16,000 Hz',16000},{'22,050 Hz',22050},{'24,000 Hz',24000},{'32,000 Hz',32000},{'44,100 Hz',44100},{'48,000 Hz',48000}}end
 if codec~=''and codec~=' FIG'and codec~=' FCL'then
 local depths=Model.depthchoices(codec);local ratew=#depths>0 and(w-12)/2 or w
 field('rate','サンプルレート',current_text(rates,m.state.n.RENDER_SRATE),x2,216,ratew,function()
  local opts=Model.clone(rates);if Model.decode(m.state.s.RENDER_FORMAT):sub(1,4)~='l3pm'and Model.decode(m.state.s.RENDER_FORMAT2):sub(1,4)~='l3pm'then opts[#opts+1]={'カスタム値…',-1}end
  choose('サンプリングレート',opts,m.state.n.RENDER_SRATE,function(v)
   if v==-1 then local spec=A.numeric_spec('RENDER_SRATE',false,0,768000,nil,1000,true);spec.id='rate';edit('サンプリングレート',m.state.n.RENDER_SRATE,spec.set,true,'rate')else m.state.n.RENDER_SRATE=v end
  end)
 end,nil,true)
 if Model.decode(m.state.s.RENDER_FORMAT):sub(1,4)~='l3pm'and Model.decode(m.state.s.RENDER_FORMAT2):sub(1,4)~='l3pm'then
  local spec=A.numeric_spec('RENDER_SRATE',false,0,768000,nil,1000);spec.id='rate';widgets[#widgets].numeric=spec
 end
 if #depths>0 then
  selectfield('depth','ビット深度',depths,raw:byte(5)or 24,x2+(w+12)/2,216,(w-12)/2,function(v)m.state.s[formatkey]=Model.setdepth(m.state.s[formatkey],v)end)

 end
 local maxChannels=math.min(Model.channelmax(Model.decode(m.state.s.RENDER_FORMAT):sub(1,4)),Model.channelmax(Model.decode(m.state.s.RENDER_FORMAT2):sub(1,4)))
 local mode=m.state.auto and'auto'or(m.state.n.RENDER_CHANNELS<=2 and m.state.n.RENDER_CHANNELS or'custom')
 local channels={{'自動（トラックカラー・アイテム設定）','auto',Model.autosupported(m.state)},{'mono',1},{'stereo',2}}
 channels.available=function(v)return v~='auto'or Model.autosupported(m.state)end
 if maxChannels>=3 then channels[#channels+1]={'multi ch','custom'}end
 local custom=mode=='custom';local gap=10;local inputWidth=78
 selectfield('channels','チャンネル',channels,mode,x2,255,custom and w-inputWidth-gap or w,function(v)
  m.state.auto=v=='auto'
  if v=='custom'then m.state.n.RENDER_CHANNELS=clamp(m.state.n.RENDER_CHANNELS,3,maxChannels)
  elseif not m.state.auto then m.state.n.RENDER_CHANNELS=v end
 end)
 if custom then numberfield('RENDER_CHANNELS','Ch',x2+w-inputWidth,255,inputWidth,false,3,maxChannels,false,'n',1,true)end
 end
 section('リージョンとマーカー',36,344,W-72,63)
 if not m.state.embed then m.state.embed=Embed.defaults();BLT.invalidate()end
 local em=m.state.embed
 local wav=Model.embedsupported(m.state)
 tick('embed_markers',em.marker_hash_only and'マーカー #'or'マーカー',em.embed_markers,36,370,80,function(v)em.embed_markers=v;em.marker_hash_only=false end,wav)
 tick('embed_regions',em.region_hash_only and'リージョン #'or'リージョン',em.embed_regions,120,370,93,function(v)em.embed_regions=v;em.region_hash_only=false end,wav)
 tick('embed_loop_region','ループリージョン',em.embed_loop_region,217,370,132,function(v)em.embed_loop_region=v end,wav)
 tick('exclude_selected_region','選択リージョンを除外',em.exclude_selected_region,353,370,158,function(v)em.exclude_selected_region=v end,wav)
 small_button('markerEncoding',em.encoding,515,369,97,22,function()choose('マーカー文字コード',{{'UTF-8','UTF-8'},{'CP932','CP932'}},em.encoding,function(v)em.encoding=v end)end,wav)
 section('OUTPUT / 出力設定',36,421,W-72,119)
 strfield('RENDER_FILE','保存先フォルダー',36,447,W-160)
 small_button('browse','参照',W-114,462,78,22,function()
  local title,initial=Language.text('レンダー保存先'),m.state.s.RENDER_FILE
  if initial==''then initial=R.GetProjectPathEx(m.project,'')
  elseif not initial:match('^%a:[/\\]')and not initial:match('^[/\\]')then initial=R.GetProjectPathEx(m.project,'')..'/'..initial end
  local ok,path
  if R.GetOS():match('Win')and type(R.GetUserFileName)=='function'then
   ok,path=R.BLT_WithNativeDialog(R.GetUserFileName,3,title,initial,'')
  elseif R.JS_Dialog_BrowseForFolder then ok,path=R.JS_Dialog_BrowseForFolder(title,initial)end
  if(ok==true or ok==1)and type(path)=='string'and path~=''and path~=m.state.s.RENDER_FILE then m.state.s.RENDER_FILE=path;changed()end
 end)
 strfield('RENDER_PATTERN','ファイル名 / ワイルドカード',36,485,W-218)
 small_button('wildcards','ワイルドカード',W-176,500,140,22,A.wildcards)
end

local function card(title,x,y,w,h,joined)
 block_surface(x-12,y-12,w+24,h,joined)
 label(title,x,y,15,C.text,1,w-10,20,0,true);line(x,y+22,x+w,y+22,C.edge,.22)
end
local function render_statistics(x1,x2,w)
 local state=m.state;local flags=state.c.renderclosewhendone or 0
 local enabled=Model.render783 and state.c.renderclosewhendone~=nil and state.c.renderpeaks~=nil
 local function selectconfig(id,title,key,mask,options,value,x,y,active)
  selectfield(id,title,options,value,x,y,w,function(v)return Model.configbits(state,key,mask,v)end,enabled and active~=false)
 end
 local function toggleconfig(id,title,key,mask,x,y,inverse,active)
  local value=((state.c[key]or 0)&mask)~=0
  tick(id,title,value~=inverse,x,y,w,function(on)
   Model.configbits(state,key,mask,on~=inverse and mask or 0)
  end,enabled and active~=false)
 end
 card('統計の計算',x1,152,w,161)
 selectconfig('stats_loudness','ラウドネス統計','renderclosewhendone',0x2600,
  {{'LUFS-M / S / I・LRA',0},{'RMS-M / S / I・RMS-RA',1536},{'計算しない（最速）',8192}},Model.loudnesschoice(state),x1,181)
 selectconfig('stats_peak','ピーク統計','renderclosewhendone',256,
  {{'サンプルピーク',0},{'トゥルーピーク',256}},flags&256,x1,228)
 label('正規化・リミットは「後処理」で設定します。',x1,278,10,C.faint,1,w,18)
 card('統計グラフ',x1,326,w,178)
 local loudness=Model.loudnesschoice(state);local graph=Model.graphchoice(state)
 selectconfig('stats_graph','ラウドネスグラフ','renderpeaks',48,
  {{'なし',0},{'モーメンタリー',16},{'ショートターム',32}},graph,x1,355,loudness~=8192)
 toggleconfig('renderpeaks:4','LUFSゲート対象外を色分け','renderpeaks',4,x1,411,false,loudness==0 and graph~=0)
 toggleconfig('renderclosewhendone:128','ピーク超過箇所を強調','renderclosewhendone',128,x1,445,false)
 card('統計ファイル',x2,152,w,161)
 local html=(flags&32768)==0 and 0 or flags&0x28000
 selectconfig('stats_html','HTMLレポート','renderclosewhendone',0x28000,
  {{'保存しない',0},{'ファイルごとに保存',32768},{'まとめて保存',0x28000}},html,x2,181)
 toggleconfig('renderclosewhendone:2097152','最後の統計をメモリに保持','renderclosewhendone',2097152,x2,248,false)
 card('表示する情報',x2,326,w,178)
 toggleconfig('renderpeaks:512','レンダー中にトラックメーターを表示','renderpeaks',512,x2,355,false)
 toggleconfig('stats_paths','HTMLにファイルパスを含める','renderclosewhendone',0x40000,x2,397,true)
 toggleconfig('stats_regions','HTMLにリージョン／マーカーを含める','renderclosewhendone',0x80000,x2,439,true)
 if not enabled then label('REAPER v7.83以降とSWSが必要です。',36,522,11,C.faint,1,W-72,18)end
end
local function advanced()
 local x1,x2,w=36,W/2+19,W/2-55
 local subtabs={'出力・品質','開始待機','統計・表示'};A.detailTab=A.detailTab or 1
 tabrow('detail',subtabs,A.detailTab,30,103,W-60,23,13,function(i)A.detailTab=i end)
 if A.detailTab==3 then render_statistics(x1,x2,w);return end
 if A.detailTab==2 then
  local x1,x2,w=36,286,212
  card('FXの初期化',x1,152,w,116)
  bit('RENDER_SETTINGS',16<<16,'FX初期化を待って開始',x1,181,w)
  numberfield('RENDER_DELAY','開始待機（秒）',x1,207,w,false,0,600)
  card('キューレンダーの開始',x2,152,w,90)
  if m.state.c.projrenderqdelay~=nil then numberfield('projrenderqdelay','サンプル読込の待機（秒）',x2,181,w,false,0,2147483647,false,'c',1,true)end
  return
 end
 card('トラックと書き出し',x1,152,w,199)
 local flags={{4,'多チャンネルを維持'},{16,'モノラル素材のみならモノラル'},{16384,'親へ送るチャンネルのみ'},{8192,'フェーダー前のステム'},{2048,'2パスレンダー'},{8<<16,'並列レンダー'},{4<<16,Model.razorsource(m.state)and'レイザー領域を1ファイルに結合'or'選択アイテムを1ファイルに結合'}}
 for i,v in ipairs(flags)do bit('RENDER_SETTINGS',v[1],v[2],x1,181+(i-1)*21,w)end
 card('埋め込み・ソース情報',x1,365,w,138)
 local flags2={{256,'トランジェントガイド'},{1024,'テイクマーカー'},{1<<16,'開始オフセットを維持'},{2<<16,'ソースのサンプルレートを維持'}}
 for i,v in ipairs(flags2)do bit('RENDER_SETTINGS',v[1],v[2],x1,393+(i-1)*22,w)end
 card('音声処理の品質',x2,152,w,199)
 cfgselect('projrenderresample','リサンプルモード',Model.resamplers,x2,181,w)
 bit('projrenderrateinternal',1,'ミックス / FXにプロジェクトSR',x2,223,w,'c')
 bit('RENDER_DITHER',1,'ディザ',x2,250,w/2);bit('RENDER_DITHER',2,'ノイズ整形',x2+w/2,250,w/2)
 bit('RENDER_DITHER',4,'ステムにディザ',x2,276,w/2);bit('RENDER_DITHER',8,'ステムに整形',x2+w/2,276,w/2)
 bit('RENDER_DITHER',16,'ディザ処理を無効',x2,303,w)
 card('出力後・ファイル管理',x2,365,w,138)
 bit('RENDER_ADDTOPROJ',1,'新規トラックへ追加',x2,393,w)
 bit('RENDER_ADDTOPROJ',2,'無音のファイルを除外',x2,415,w)
 bit('renderclosewhendone',16,'重複時に自動ナンバリング',x2,437,w,'c')
 bit('renderclosewhendone',32768,'レンダー統計をHTMLへ保存',x2,459,w,'c')
 label('無効な設定は値を保持し、書き出し時には適用しません。',36,522,11,C.faint,1,W-72,18)
end
function A.embed_item_channels(ch)
 local count=Model.setitemchannels(R,m.project,ch)
 ItemLabels:invalidate()
 if count==0 then status('アイテムが選択されていません。',true);return end
 changed();if ch then status(string.format(Language.text('%d個のアイテムに%dchを設定しました。'),count,ch))
 else status(string.format(Language.text('%d個のアイテムの埋込を削除しました。'),count))end
end
local channelOptions=Model.channelchoices(128,true)
local function channel_settings()
 local x1,x2,w=36,W/2+19,W/2-55
 A.channelTab=A.channelTab or 1
 if A.channelTab==1 then
  if not m.state.colorMap then m.state.colorMap=Model.readmap(R);BLT.invalidate()end
  local map=m.state.colorMap
  for col=0,1 do
   local x=col==0 and x1 or x2;if col==0 then card('カスタムカラー',36,152,W-72,312,true)end
   for row=0,7 do local i=col*8+row+1;local y=185+row*33
    local color=C.faint
    if R.CF_GetCustomColor and R.ColorFromNative then local rgb=R.CF_GetCustomColor(i-1);if rgb and rgb>=0 then local rr,gg,bb=R.ColorFromNative(rgb);color={rr/255,gg/255,bb/255}end end
    rect(x+2,y+7,14,14,color,1);label(string.format('%02d',i),x+25,y+5,12,C.text,3,28,24)
    local opts=channelOptions
    small_button('map'..i,current_text(opts,map[i]),x+62,y,w-62,24,function()
     choose('チャンネル',opts,map[i],function(v)map[i]=v end)
    end)
   end
  end
  block_surface(24,466,W-48,80)
  for i,row in ipairs(Model.channelFallbacks)do
   local key,y=row[1],478+(i-1)*32
   label(row[3],36,y,13,C.text,1,w+24,24,4,true)
   selectfield(key,'',channelOptions,m.state[key]or 0,x2,y+1,w,function(v)m.state[key]=v end)
  end

 else
  card('選択アイテムに…',36,152,W-72,142,true)
  local enabled=R.CountSelectedMediaItems(m.project)>0 and R.EnumProjects(-1,'')==m.project
  small_button('embedMono','MONOを埋込',36,196,100,26,function()A.embed_item_channels(1)end,enabled)
  small_button('embedStereo','STEREOを埋込',144,196,112,26,function()A.embed_item_channels(2)end,enabled)
  local spec={id='itemEmbedChannels',step=1,integer=true,get=function()return m.state.itemEmbedChannels or 3 end}
  spec.set=function(value)
   if not finite(value)then A.flash_field(spec.id);return end
   local bounded=clamp(floor(value+.5),3,128);if bounded~=value then A.flash_field(spec.id)end
   if m.state.itemEmbedChannels==bounded then return false end
   m.state.itemEmbedChannels=bounded;return true
  end
  label('Ch',272,196,13,C.text,1,24,26,4)
  field(spec.id,'',spec.get(),300,198,54,function()edit('チャンネル数（3～128）',spec.get(),spec.set,true,spec.id)end)
  widgets[#widgets].numeric=spec
  small_button('embedCustom',string.format(Language.text('Ch%dを埋込'),spec.get()),362,196,96,26,function()A.embed_item_channels(spec.get())end,enabled)
  small_button('embedClear','埋込を削除',36,232,134,26,function()A.embed_item_channels(nil)end,enabled)
  tick('itemLabels',Language.code=='EN'and'Show embedded channel info on items'or'埋込情報がある場合アイテム上に表示',ItemLabels.enabled,190,235,W-226,function(on)ItemLabels:setEnabled(on)end)
  label('自動判定時・選択メディアアイテムの書き出しのみ有効です。',36,306,12,C.muted,1,W-72,22)
  label('アイテム設定を最優先し、指定がない場合はトラックカラーを使います。',36,330,12,C.muted,1,W-72,22)
  if ItemLabels.error then
   label(Language.code=='EN'and'Item labels unavailable. See footer error.'or'Ch表示は利用できません。フッターのエラーを確認してください。',36,404,12,C.warn,1,W-72,22)
  end

 end
 tabrow('channelTab',{'カラー判定','アイテム埋込'},A.channelTab,24,108,(W-48)*.7,32,13,function(i)A.channelTab=i end,true)
end
local function postprocess()
 local x1,x2,w=36,W/2+19,W/2-55
 local enabled=(m.state.n.RENDER_NORMALIZE&(4<<16))==0
 tick('postprocessEnabled','後処理を有効',enabled,x1,108,W-72,function(on)
  local v=m.state.n.RENDER_NORMALIZE
  m.state.n.RENDER_NORMALIZE=on and(v&~(4<<16))or(v|(4<<16))
 end)

 local palette=C
 if not enabled then
  C={};for key,c in pairs(palette)do local gray=(c[1]+c[2]+c[3])/3;C[key]={gray,gray,gray}end
  C.text=C.faint;C.muted=C.faint
 end
 A.controlsDisabled=not enabled
 card('音量の正規化',x1,150,w,223)
 bit('RENDER_NORMALIZE',1,'有効',x1,180,w)
 bitsselect('RENDER_NORMALIZE',14,'測定方式',{{'LUFS-I',0},{'RMS',2},{'Peak',4},{'True Peak',6},{'LUFS-M max',8},{'LUFS-S max',10}},x1,198,(w-12)/2)
 numberfield('RENDER_NORMALIZE_TARGET','目標（dB / LUFS）',x1+(w+12)/2,198,(w-12)/2,true,-100,24)
 bitsselect('RENDER_NORMALIZE',32|4096|(16<<16),'複数ファイル',{{'ファイルごと',0},{'同時再生として正規化',32},{'最大音量へ合わせる',4096},{'同時再生 / 共通ゲイン',32|4096},{'マスターミックス基準',16<<16}},x1,236,w)
 bitsselect('RENDER_NORMALIZE',256|2048,'適用条件',{{'上下両方',0},{'大きすぎる場合のみ',256},{'小さすぎる場合のみ',2048}},x1,274,w)
 bitsselect('RENDER_NORMALIZE',16|(8<<16),'モノラル補正',{{'なし',0},{'-3 dB',16},{'+3 dB',16|(8<<16)}},x1,312,w)
 card('ピークの制限',x1,387,w,152)
 bit('RENDER_NORMALIZE',64,'リミッター',x1,415,w/2)
 bit('RENDER_NORMALIZE',128,'True peak',x1+w/2,415,w/2)
 numberfield('RENDER_BRICKWALL','上限（dB）',x1,437,w,true,-100,24)
 bitsselect('RENDER_NORMALIZE',(32<<16)|(64<<16),'複数ファイル',{{'ファイルごと',0},{'同時再生として処理',32<<16},{'マスターミックス基準',64<<16}},x1,478,w)
 card('無音のトリム',x2,150,w,104)
 bit('RENDER_NORMALIZE',16384,'先頭',x2,180,w/2);bit('RENDER_NORMALIZE',32768,'末尾',x2+w/2,180,w/2)
 numberfield('RENDER_TRIMSTART','先頭閾値（dB）',x2,198,(w-12)/2,true,-150,0)
 numberfield('RENDER_TRIMEND','末尾閾値（dB）',x2+(w+12)/2,198,(w-12)/2,true,-150,0)
 card('無音の追加',x2,268,w,104)
 bit('RENDER_NORMALIZE',1<<16,'先頭',x2,293,w/2);bit('RENDER_NORMALIZE',2<<16,'末尾',x2+w/2,293,w/2)
 numberfield('RENDER_PADSTART','先頭（秒）',x2,316,(w-12)/2,false,0,3600)
 numberfield('RENDER_PADEND','末尾（秒）',x2+(w+12)/2,316,(w-12)/2,false,0,3600)
 card('フェード',x2,386,w,159)
 bit('RENDER_NORMALIZE',512,'イン',x2,414,w/2);bit('RENDER_NORMALIZE',1024,'アウト',x2+w/2,414,w/2)
 numberfield('RENDER_FADEIN','イン（秒）',x2,437,(w-12)/2,false,0,3600)
 numberfield('RENDER_FADEOUT','アウト（秒）',x2+(w+12)/2,437,(w-12)/2,false,0,3600)
 local shapes=Model.fadeShapes
 small_button('fadeinshape',current_text(shapes,m.state.n.RENDER_FADEINSHAPE),x2,478,(w-12)/2,20,function()choose('インのカーブ',shapes,m.state.n.RENDER_FADEINSHAPE,function(v)m.state.n.RENDER_FADEINSHAPE=v end)end)
 small_button('fadeoutshape',current_text(shapes,m.state.n.RENDER_FADEOUTSHAPE),x2+(w+12)/2,478,(w-12)/2,20,function()choose('アウトのカーブ',shapes,m.state.n.RENDER_FADEOUTSHAPE,function(v)m.state.n.RENDER_FADEOUTSHAPE=v end)end)
 bit('RENDER_FADELPF',1,'インLPF',x2,501,w/2);bit('RENDER_FADELPF',2,'アウトLPF',x2+w/2,501,w/2)
 A.controlsDisabled=nil;C=palette
end

local function pager(id,count,size,x,y,w)
 local key=id..'Page';local total=max(1,math.ceil(count/size));A[key]=clamp(A[key]or 1,1,total)
 small_button(id..'Prev','‹',x,y,28,24,function()A[key]=max(1,A[key]-1)end,A[key]>1)
 label(A[key]..' / '..total,x+32,y+3,12,C.muted,1,w-64,20,1)
 small_button(id..'Next','›',x+w-28,y,28,24,function()A[key]=min(total,A[key]+1)end,A[key]<total)
 return(A[key]-1)*size
end
local function metadata()
 local x,w=36,W-72;section('METADATA',x,120,w,378)
 bit('RENDER_SETTINGS',512,'メタデータ',x,158,170)
 bit('RENDER_SETTINGS',32768,'ソースのメタデータを維持',x+184,158,w-184)
 small_button('addmeta','フィールドを追加',x,198,132,24,function()
  edit('識別子（例 INFO:INAM / BWF:Description）','',function(k)
   if k==''or k:find('[|;\r\n]')then error('識別子を確認してください。',0)end
   edit('値','',function(v)m.state.meta[k]=v end)
  end)
 end)
 small_button('nativemeta','標準メタデータ / タグ一覧…',x+140,198,240,24,native)

 local keys={};for k in pairs(m.state.meta)do keys[#keys+1]=k end;table.sort(keys)
 local count=math.min(6,#keys);local offset=pager('meta',#keys,6,x+392,198,w-392)
 for i=1,count do local k=keys[i+offset];if k then field('meta'..k,k,m.state.meta[k],x,242+(i-1)*39,w,function()edit(k,m.state.meta[k],function(v)m.state.meta[k]=v~=''and v or nil end)end)end end
 if #keys==0 then label('メタデータなし。追加、または標準画面から読み込めます。',x,284,13,C.faint,1,w,25)end
end
A.targetList={x=36,y=216,w=576,h=270,rowHeight=30,scroll=0}
function A.scroll_targets(value)
 local list=A.targetList
 list.limit=max(0,#A.files*list.rowHeight-list.h)
 value=clamp(value,0,list.limit)
 if value==list.scroll then return end
 list.scroll=value;redraw_dirty=true;next_draw_time=0
end
function A.target_input(down,wasDown,allowed)
 local list=A.targetList
 if not allowed or A.tab~=6 then local captured=list.drag~=nil;list.drag=nil;return captured end
 local limit=max(0,#A.files*list.rowHeight-list.h)
 if limit==0 then list.drag=nil;return false end
 local thumb=max(24,list.h*list.h/(#A.files*list.rowHeight))
 local top=list.y+(list.h-thumb)*list.scroll/limit
 if list.drag then
  if down then A.scroll_targets((my-list.drag-list.y)*limit/(list.h-thumb))else list.drag=nil end
  gfx.mouse_wheel=0;return true
 end
 if gfx.mouse_wheel~=0 and inside(list.x,list.y,list.w,list.h)then
  local wheel=gfx.mouse_wheel;gfx.mouse_wheel=0
  if not down then A.scroll_targets(list.scroll-wheel/120*list.rowHeight*3)end
  return true
 end
 if down and not wasDown and inside(list.x+list.w-14,list.y,14,list.h)then
  if my>=top and my<=top+thumb then list.drag=my-top
  else A.scroll_targets(list.scroll+(my<top and -list.h or list.h))end
  return true
 end
 return false
end
local function target_revision()
 local ok,revision=pcall(R.GetProjectStateChangeCount,m.project)
 return ok and revision or nil
end
function A.refresh_targets()
 if A.busy then return false end
 local ok,files=pcall(Model.previewdetails,R,m)
 A.targetsRevision=target_revision();A.targetsDirty=false;A.countAt=nil
 if not ok or type(files)~='table'then
  A.targetsError=true;status('出力先を取得できません。',true);return false
 end
 A.files=files;A.targetList.drag=nil;A.scroll_targets(A.targetList.scroll)
 if A.targetsError then status('出力先を更新しました。')end
 A.targetsError=nil;redraw_dirty=true;next_draw_time=0;return true
end
local function output()
 local x,w=36,W-72;section('RENDER TARGETS',x,120,w,378)
 small_button('openfolder','出力フォルダーを開く',x,160,204,24,function()
  if R.CF_ShellExecute then R.CF_ShellExecute(m.state.s.RENDER_FILE~=''and m.state.s.RENDER_FILE or R.GetProjectPathEx(m.project,''))end
 end)

 local list=A.targetList;A.scroll_targets(list.scroll)
 local rowWidth=w-16;local chx=x+rowWidth-100
 label('出力先（相対パス）',x+58,190,12,C.muted,1,rowWidth-174,20)
 label('チャンネル',chx,190,12,C.muted,1,94,20)
 label(tostring(#A.files),x+382,162,12,C.muted,3,w-382,20,2,true)
 local first=floor(list.scroll/list.rowHeight)+1
 local last=min(#A.files,math.ceil((list.scroll+list.h)/list.rowHeight))
 gfx.pushClip(sx(list.x),sy(list.y),rowWidth*scale,list.h*scale)
 for i=first,last do local entry=A.files[i]
  local y=list.y+(i-1)*list.rowHeight-list.scroll;rect(x,y,rowWidth,27,i%2==0 and C.panel or C.field,.7)
  label(string.format('%03d',i),x+8,y+4,11,C.faint,3,40,20)
  font(12,1,false);label(BLT.ui.fit(entry.relative,(rowWidth-178)*scale),x+58,y+4,12,entry.duplicate and C.red or C.text,1,rowWidth-174,20,0,false,true)
  label(entry.channels and(entry.channels..' ch')or'REAPER判定',chx,y+4,12,C.text,1,94,20)
  local hitY=max(list.y,y);local hitBottom=min(list.y+list.h,y+27)
  if hitBottom>hitY then widget('path'..i,x,hitY,rowWidth,hitBottom-hitY,function()if R.CF_SetClipboard then R.CF_SetClipboard(entry.path);status('出力先をコピーしました。')end end)end
 end
 gfx.popClip()
 if list.limit>0 then
  gfx.wheelRegion(sx(list.x),sy(list.y),list.w*scale,list.h*scale)
  local thumb=max(24,list.h*list.h/(#A.files*list.rowHeight))
  local top=list.y+(list.h-thumb)*list.scroll/list.limit
  rect(x+w-9,list.y,3,list.h,C.edge,.32)
  rect(x+w-11,top,7,thumb,list.drag and C.accent2 or C.edge2,.85)
 end
 if #A.files==0 then label(A.targetsError and'出力先を取得できません。'or'レンダー対象がありません。',x,224,13,C.faint,1,w,25)end
end
local function poll_count(now)
 if not A.busy and not E and not A.renderConfirm and now>=(A.countDue or 0)and(not A.countAt or now-A.countAt>1)then
  local revision=target_revision()
  local targetsChanged=A.tab==6 and(A.targetsDirty or A.targetsRevision==nil or revision~=A.targetsRevision)
  if not A.countAt or revision~=A.countRevision or targetsChanged then
   local before,err=A.fileCount,A.countError
   local oldGroups=A.channelCounts;local ok,count,groups=pcall(Model.count,R,m);A.fileCount=ok and count or nil;A.channelCounts=ok and groups or nil;A.countError=ok and nil or tostring(count)
   if ok and groups and(not oldGroups or oldGroups.mono~=groups.mono or oldGroups.stereo~=groups.stereo or oldGroups.multi~=groups.multi)then redraw_dirty=true end
   if A.fileCount~=before or A.countError~=err then redraw_dirty=true end
   if targetsChanged and not A.targetList.drag then A.refresh_targets()end
   A.countRevision=target_revision()
  end
  A.countAt=now
 end
end
local function visual_step(now,active,dragging)
 animation_speed=active and visual_speed(now)or 0;animations_active=animation_speed>0
 RenderIcon:tick(now,active,redraw_dirty and active)
 if dragging or E then return 1/60 end
 if animations_active or render_animating(now) then return 1/30 end
 if RenderIcon:animating(now) or RenderUI:executeAnimating('render') then return 1/30 end
end
function A.run_render(approval)
 A.renderConfirm=nil;A.busy=true;status('レンダリング中…');gfx.update()
 local ok,result,done=xpcall(function()return Model.render(R,m,'render',approval)end,tostring);A.busy=false;BLT.invalidate()
 if not ok then error(result,0)end
 if type(result)=='table'and result.confirmation then A.renderConfirm=result.confirmation;status('書き出し方法を選択してください。');return end
 status('待機中')
 if Model.completed(result,done)then
  RenderUI.now=R.time_precise();RenderUI:complete('render',274/density,36/density);wake_visuals()
  if Model.closeafter(m.state)then Chrome.requestClose=true end
 end
end
function A.draw_render_confirm()
 local q=A.renderConfirm;if not q then return end
 widgets={};rect(0,0,W,H,C.bg,.92)
 local x,y,w=48,156,W-96
 block_surface(x,y,w,278)
 label(q.naming and'出力名の確認'or'既存ファイルの確認',x+18,y+16,17,C.text,1,w-36,24,0,true)
 if q.naming then
  label('出力名を一意に確定できません。',x+18,y+51,14,C.text,1,w-36,22)
  label('重複する名前だけに連番を付けて書き出しますか？',x+18,y+82,13,C.muted,1,w-36,22)
 else label(string.format(Language.text('既存ファイルが %d 件あります。'),#q.conflicts),x+18,y+51,14,C.text,1,w-36,22)end
 if #q.missing>0 then
  label('チャンネル未設定のトラックカラーがあります。',x+18,y+82,13,C.warn,1,w-36,22)
  label(string.format(Language.text('未設定の %d トラックはマスターの %d ch で書き出します。'),#q.missing,q.channels),x+18,y+106,13,C.warn,1,w-36,22)
 end
 local names={};for i=1,math.min(3,#q.conflicts)do names[#names+1]=q.conflicts[i]end
 for i,path in ipairs(names)do label(BLT.ui.fit(path,(w-36)*scale),x+18,y+142+(i-1)*20,12,C.muted,1,w-36,20,0,false,true)end
 if #q.conflicts>#names then label(string.format(Language.text('…他%d個'),#q.conflicts-#names),x+18,y+202,12,C.muted,1,w-36,20)end
 local available=w-140;local px=x+18
 local widths={available*.28,available*.25,available*.47,80}
 local choices={{'連番付与','number'},{'上書き','overwrite'},{'新規のみ書き出し','skip'},{'キャンセル','cancel'}}
 if q.naming then choices={{'連番付与','number'},{'キャンセル','cancel'}};widths={w-124,80}end
 for i,v in ipairs(choices)do
  small_button('renderChoice:'..v[2],v[1],px,y+224,widths[i],32,function()
   if v[2]=='cancel'then A.renderConfirm=nil;status('待機中')
   else A.run_render({choice=v[2],signature=q.signature,naming=q.naming})end
  end)
  px=px+widths[i]+8
 end
end
local pages={basic,advanced,postprocess,metadata,channel_settings,output}
local function draw()
 gfx.beginDraw()
 scale=math.min(gfx.w/BASE_W,(gfx.h-26)/H);ox=(gfx.w-BASE_W*scale)/2;oy=26;W=BASE_W
 mx,my=(gfx.mouse_x-ox)/scale,(gfx.mouse_y-oy)/scale
 BLT.viewport(scale,gfx.ext_retina or 1);widgets={}
 local now=R.time_precise();RenderUI:begin(density*scale,ox,oy);RenderUI.active=BLT.host.active() and animation_speed>0
 RenderUI.themeEnabled=Chameleon.enabled;RenderUI.blocked=BLT.blocked()or E~=nil or Chrome.mouseActive
 gfx.set(C.bg[1],C.bg[2],C.bg[3],1);gfx.rect(0,0,gfx.w,gfx.h,1)
 draw_background()
 pages[A.tab]()
 BLT.title(NAME,'RENDER TO FILE  /  追加機能付きファイルレンダリング',W)
 RenderIcon:draw(sx(W-103),sy(5),scale*.92)
 local tabs={'基本','詳細','後処理','メタデータ','チャンネル判定','出力確認'}
 tabrow('tab',tabs,A.tab,30,65,W-60,29,14,function(i)A.tab=i;if i==6 then A.refresh_targets()end end)
 line(24,542,W-24,542,C.edge,.6)
 small_button('reload','REAPER設定を読込',36,564,152,23,reload)
 small_button('reaperpresets','REAPERプリセット',196,564,152,23,function()
  local presets=Model.nativepresets(R);local choices={};for name in pairs(presets)do choices[#choices+1]={name,name}end
  table.sort(choices,function(a,b)return a[1]<b[1]end)
  if #choices==0 then status('保存されているREAPERレンダープリセットはありません。',true);return end
  choose('REAPER presets',choices,nil,function(name)m.state=Model.loadpreset(m.state,presets[name]) end)
 end)
 local closing=Model.closeafter(m.state)
 tick('closeAfter','レンダー後閉じる',closing,36,609,150,function(on)Model.setcloseafter(m.state,on)end,true,true)
 widgets[#widgets].y,widgets[#widgets].h=603,28
 small_button('native','標準レンダーを開く',194,604,134,24,native)
 selectfield('projrenderlimit','レンダリング速度',Model.speedchoices(m.state),Model.speedchoice(m.state),356,550,256,function(v)return Model.setspeed(m.state,v)end,m.state.c.projrenderlimit~=nil)
 local rx,ry,rw,rh=338,597,W-374,36
 local parts={};for _,key in ipairs({'mono','stereo','multi'})do local n=A.channelCounts and A.channelCounts[key]or 0;if n>0 then parts[#parts+1]=key..'['..n..']' end end
 local renderLabel=Language.text('レンダー')..(#parts>0 and(' ('..table.concat(parts,' ')..')')or'')
 local titleSize=15;font(titleSize,1,false);while titleSize>11 and gfx.measurestr(renderLabel)>(rw-24)*scale do titleSize=titleSize-1;font(titleSize,1,false)end
 titleSize=titleSize-1
 local renderEnabled=not A.busy and A.fileCount~=0
 local execution=render_options('render');execution.enabled,execution.busy=renderEnabled,A.busy
 execution.autoComplete,execution.finishWhenDisabled=false,true
 execution.caption,execution.captionY,execution.captionHeight,execution.captionSize='RENDER TO FILE',2/density,11/density,7/density
 execution.labelY,execution.labelHeight,execution.size=12/density,23/density,titleSize/density
 RenderUI.C=C;RenderUI:execute('render',renderLabel,rx/density,ry/density,rw/density,rh/density,execution)
 widget('render',rx,ry,rw,rh,function()
  if A.busy then return end
  local counted,count=pcall(Model.count,R,m)
  if counted and count==0 then A.fileCount=0;status('レンダー対象がありません。');return end
  A.run_render()
 end,renderEnabled)
 BLT.footer(A.status,A.bad,W,H,Model.VERSION)
 BLT.bar()
 A.draw_render_confirm();RenderUI:finish()
end
BLT.attach({R=R,C=C,Chrome=Chrome,Chameleon=Chameleon,section=SECTION,faces=fonts,font=font,
 geometry=function()return scale,ox,oy end,active=function()local f=gfx.getchar(65537);return(f&1)==0 or(f&2)~=0 end,
 wake=wake_visuals,defaults=Model.factory(m.state),capture=function()return m.state end,
 valid=Model.valid,apply=function(v)m.state=Model.complete_render_options(R,v);changed()end,
 busy=function()return A.busy end,commit=function()return finish_edit(false)end,cancelEdit=function()finish_edit(true)end,editing=function()return E~=nil end,modal=function()return A.renderConfirm~=nil end,
 tooltip=A.detail_tip,
 handle=gfx_window_handle,resizeHit=chrome_resize_hit,cursor=set_resize_cursor,beginResize=begin_window_resize,resize=update_window_resize})
function A.save_session()
 if Session.save(R,m,{tab=A.tab,detailTab=A.detailTab or 1,channelTab=A.channelTab or 1,formatTab=A.formatTab or 1})then A.sessionDue=nil end
end
A.sessionDue=R.time_precise()+.5
local closed=false
local function close()
 if closed then return end;closed=true
 ItemLabels:close()
 if gfx_window_handle()then local ok,l,t,r,b=WindowGeometry.JS_Window_GetRect(gfx_window_handle());if ok then
  for k,v in pairs({window_x=l,window_y=t,window_w=r-l,window_h=b-t})do BLT.store(SECTION,k,tostring(v),true)end
 end end
 finish_edit(false);A.save_session();RenderGraphics.release();titlebar_cleanup();BLT.clearTooltip();gfx.quit()
end

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

BLTShortcuts.install(R,gfx,{
 blocked=function() return BLT.presets.open or (BLT.host and (BLT.host.editing() or BLT.host.modal() or BLT.host.busy())) end,
 beforeGlobal=function(k) if BLT.host and BLT.host.beforeKey then BLT.host.beforeKey(k) end end,
 localKey=function(k,cap)
  return k==27 or ((cap&24)==0 and (k==26 or (cap&4)~=0 and (k==90 or k==122)))
 end
})

local function pointer_frame()
 local now=R.time_precise()
 local usable=BLT.host.active()or(gfx.getchar(65536)&8)~=0
 local down=(gfx.mouse_cap&1)~=0
 mx,my=(gfx.mouse_x-ox)/scale,(gfx.mouse_y-oy)/scale
 if A.target_input(down,last_down,usable and not A.busy and not E and not BLT.blocked()and not BLT.host.modal()and not Chrome.mouseActive)then
  A.pressed=nil;last_down=down;return
 end
 local hit
 if usable and not A.busy and not BLT.blocked()and not Chrome.mouseActive then
  for _,v in ipairs(widgets)do if v.enabled and inside(v.x,v.y,v.w,v.h)then hit=v;break end end
 elseif A.numericDrag then A.numericDrag=nil;A.pressed=nil end
 if A.numeric_input(hit,down,last_down,my)then A.pressed=nil end
 if down~=last_down then
   if down then A.pressed=hit and hit.id or nil
   else
    if hit and hit.id==A.pressed then
     A.editBounds={x=hit.x,y=hit.y,w=hit.w,h=hit.h}
     if finish_edit(false)then guarded(hit.fn)end
    end
    A.pressed=nil
  end;last_down=down;wake_visuals();next_draw_time=now
 end
 if gfx.mouse_wheel~=0 then gfx.mouse_wheel=0 end
end
local function overlay_frame()
 ime_frame();pointer_frame()
end
gfx.setOverlay(function()guarded(overlay_frame)end)

local ready,reason=titlebar_api_ready();if not ready then R.MB(reason,APP_NAME,0);return end

if R.set_action_options then R.set_action_options(2)end
gfx.ext_retina=1
local ww=clamp(tonumber(R.GetExtState(SECTION,'window_w'))or BASE_W,Chrome.minW,2200)
local hh=clamp(tonumber(R.GetExtState(SECTION,'window_h'))or H+26,Chrome.minH,1700)
local xx=tonumber(R.GetExtState(SECTION,'window_x'));local yy=tonumber(R.GetExtState(SECTION,'window_y'))
if xx and yy then gfx.init(APP_NAME,ww,hh,0,xx,yy)else gfx.init(APP_NAME,ww,hh,0)end
R.atexit(close);if Chameleon.enabled then Chameleon.refresh(true)end
local function loop()
 local k=BLT.key(gfx.getchar())
 if k==27 and A.renderConfirm then A.renderConfirm=nil;status('待機中');k=0 end
 if k<0 or(k==27 and not E)or Chrome.requestClose then close();return end
 local now=R.time_precise();ItemLabels:tick(now,m.project);BLT.tick(now);Chameleon.tick(now)
 if A.sessionDue and now>=A.sessionDue and not E and not A.busy then A.save_session()end
 local active=BLT.host.active()
 if last_window_active~=active then last_window_active=active;wake_visuals(now)end
 if k>0 then wake_visuals(now);next_draw_time=now end
 local insideWindow=gfx.mouse_x>=0 and gfx.mouse_x<gfx.w and gfx.mouse_y>=0 and gfx.mouse_y<gfx.h
 local wasInside=A.lastmx and A.lastmx>=0 and A.lastmx<gfx.w and A.lastmy>=0 and A.lastmy<gfx.h
 if A.lastmx~=gfx.mouse_x or A.lastmy~=gfx.mouse_y then
  A.lastmx,A.lastmy=gfx.mouse_x,gfx.mouse_y
  if insideWindow or wasInside then wake_visuals(now)end
 end
 if Chrome.requestReset then Chrome.requestReset=false;reset_window_size()end
 local mismatch=R.EnumProjects(-1,'')~=m.project
 if mismatch and not A.projectMismatch then status('別プロジェクトです。REAPER設定を読込してください。',true)end;A.projectMismatch=mismatch
 poll_count(now)
 local dragging=(gfx.mouse_cap&1)~=0 or Chrome.drag or Chrome.resize
 if dragging then wake_visuals(now)end
 if(gfx.getchar(65537)&4)==0 then redraw_dirty=true;A.pressed=nil;A.numericDrag=nil;last_down=false;R.defer(loop);return end
 local interval=visual_step(now,active,dragging)
 if interval and next_draw_time==math.huge then next_draw_time=now end
 if(interval and now>=next_draw_time)or(not interval and redraw_dirty)then
  redraw_dirty=false;guarded(draw);gfx.update();next_draw_time=interval and now+interval or math.huge
 end
 R.defer(loop)
end
loop()
