-- @description MINIMAL INFO PANEL
-- @version 0.2.20
-- @author Balrulu
-- @provides
--   . > ../
-- @changelog
--   BLT SERIES Beta TEST UPLOAD
-- @about
--   BLT SERIES Beta TEST UPLOAD

-- BLT preset transfer limits 1.1.0. Embedded; no runtime dependency.
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
local reaper,gfx=AppCanvas.install(reaper,gfx,AppCanvasHost,
 {section='BLT_MINIMAL_INFO_PANEL',title='BLT MINIMAL INFO PANEL',width=1070,height=100,minWidth=1070,minHeight=70},AppShellText,AppChromeRaster,AppCanvasDraw)
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


-- BEGIN BLT COMMON CHROME 1.0.0 (generated from _shared/BLT_Chrome.lua)
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
  end -- full-size preset and language controls
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

  end -- full-size reset control
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
-- END BLT COMMON CHROME

local BLTPresetLimits={bytes=16777216,stringBytes=2097152,nodes=262144,entries=8192}
function BLTPresetLimits.show(english)
 reaper.MB(english and 'Preset capacity limit exceeded. Export presets individually instead of as a bundle.' or '容量上限オーバーです。一括ではなく個別に保存してください。','BLT PRESET',0)
end

-- Only reverse needs online audio; check at commit, then poll while waiting for recovery.
local function create_media_gate(api,graphics)
 local M={waiting=false};local next_check,settle,ready=0,0,true
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
 function M.ready(force)
  local now=api.time_precise()
  if not force and now<next_check then return ready end
  next_check=now+.1
  local project=api.EnumProjects(-1,'');local takes={};local invalid=false
  for i=0,api.CountSelectedMediaItems(project)-1 do
   local item=api.GetSelectedMediaItem(project,i)
   if not item then invalid=true
   else local take=api.GetActiveTake(item);if take then takes[take]=true end end
  end
  if M.state and M.state.project and M.state.project~=project then invalid=true end
  local blocked=false
  if not invalid then
   if next(takes) and not api.CF_GetMediaSourceOnline and application_active()==false then blocked=true
   else for take in pairs(takes) do if offline(project,take) then blocked=true;break end end end
  end
  if invalid or not next(takes) then settle=0 end
  if blocked then settle=now+.25 end
  local waiting=not invalid and (blocked or now<settle);ready=not waiting
  if waiting~=M.waiting then M.waiting=waiting;if M.onchange then M.onchange() end end
  return ready
 end
 function M.tick()
  if M.waiting then return M.ready() end
  return ready
 end
 return M,api
end
local Media,reaper=create_media_gate(reaper,gfx)

-- BLT window geometry 1.0.0. Embedded; screen coordinates only.
local WindowGeometry=gfx.geometryAPI()
local BLT_MAC=(reaper.GetOS() or ''):match('OSX')~=nil or (reaper.GetOS() or ''):match('macOS')~=nil

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
 ["CHAMELEON  REAPERテーマに擬態"]="CHAMELEON  REAPER theme",
 ["CHAMELEON  オリジナル配色"]="CHAMELEON  Original colors",
 ["カスタムタイトルバーには js_ReaScriptAPI が必要です。\nReaPack から js_ReaScriptAPI をインストールしてください。"]="The app bar requires js_ReaScriptAPI.\nInstall js_ReaScriptAPI via ReaPack.",
 ["アイテム"]="Item",
 ["現在"]="Current",
 ["解析中"]="Analyzing",
 ["表示言語を切替（JP / EN）"]="Switch language (JP / EN)",
 ["名前"]="Name",
 ["長さ"]="Length",
 ["ボリューム"]="Volume",
 ["ピッチ"]="Pitch",
 ["再生速度"]="Rate",
 ["逆再生"]="Reverse",
 ["ミュート"]="Mute",
 ["ロック"]="Lock",
 ["ピーク表示ズーム率"]="Peak zoom",
 ["ピーク表示の調整にはSWS Extensionが必要です。"]="Peak zoom requires SWS Extension.",
 ["ピーク表示の設定を取得できません。"]="Cannot read the peak display gain.",
 ["ピーク表示の設定を変更できません。"]="Cannot change the peak display gain.",
 ["プロジェクトが切り替わったため、ピーク表示の操作を終了しました。"]="Peak zoom adjustment ended because the project changed.",
 ["（名前なし）"]="(Unnamed)",
 ["アイテムを選択してください。"]="Select items.",
 ["編集中に対象が変更されました。もう一度操作してください。"]="Items changed while editing. Please try again.",
 ["選択が変更されました。もう一度操作してください。"]="Selection changed. Please try again.",
 ["対象アイテムが変更または削除されました。"]="An item was changed or deleted.",
 ["名前は改行なし・4096バイト以内で入力してください。"]="Use a single-line name, up to 4096 bytes.",
 ["数値が範囲外です。元の値を保持しました。"]="Value out of range. Original value retained.",
 ["この項目は選択アイテムでは編集できません。"]="This property is unavailable for the selected item.",
 ["選択内にこの項目を編集できないアイテムがあります。"]="Some selected items do not support this property.",
 ["ロックされたアイテムがあります。先にロックを解除してください。"]="Unlock selected items before editing.",
 ["数値が不正です。"]="Invalid number.",
 ["値が不正です。"]="Invalid value.",
 ["値を変更できませんでした。"]="Could not change the value.",
 ["変更に失敗したため、元の値へ戻しました。"]="Update failed. Original values restored.",
 ["復元できない項目があります。REAPERのUndoで確認してください。"]="Some items could not be restored. Check REAPER Undo.",
 ["音声がオンラインになるまでお待ちください。"]="Wait until media is online.",
 ["逆再生の切り替えにはSWS Extensionが必要です。"]="Reverse editing requires SWS Extension.",
 ["ウィンドウを初期化できません。"]="Could not initialize the window.",
 ["プリセットを読み込みました: ファクトリーデフォルト"]="Loaded: Factory Default",
},prefixes={"プリセットを保存しました: ","プリセットを読み込みました: ","現在: "},patterns={
 {'^「(.*)」を上書きしますか？$','Overwrite "%s"?'},
 {'^(%d+)個インポートしました。$','Imported %d preset(s).'},
 {'^(%d+)個選択 · トラック順・時間順の先頭を表示$','%d selected · First by track/time'},
 {'^(%d+)個のアイテムを変更しました。$','%d items updated.'}
}}
local Language=create_language(reaper,"BLT_MINIMAL_INFO_PANEL",LanguageCatalog)
local R=reaper
-- BLT shared shell 3.2.0. Embedded at build time; no runtime module dependency.
local BLT=(function()
local B={fitCache={},fitCount=0,metrics={},metricCount=0}
local host,C,Chrome,Chameleon,scale,ox,oy
local R=reaper
local UI={}
local Layout={bar={height=26,close=38,reset=34,theme=34,language=26,preset=84,arrow=20},popup={width=292,headerHeight=36,rowHeight=29,visiblePresets=8,hoverDelay=1}}
local Presets={items={},revision=0}
local function wake_visuals() if host then host.wake() end end
function B.copy(v)
 if type(v)~='table' then return v end
 local t={};for k,x in pairs(v) do t[k]=B.copy(x) end;return t
end
-- Typed, length-prefixed data. Never evaluate imported Lua or JSON-like code.
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
function B.cleanText(text)
 text=tostring(text);B.cleanCache=B.cleanCache or {};local v=B.cleanCache[text];if v then return v end
 v=text:gsub('[%z\1-\31\127]',' ')
 B.cleanCount=(B.cleanCount or 0)+1;if B.cleanCount>512 then B.cleanCache={};B.cleanCount=1 end
 B.cleanCache[text]=v;return v
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
B.metricsFor=UI.textMetrics
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
 -- Whitelisted views are reused; never serialize settings in the draw path.
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

function Presets.context(p,x,y)
 if not p or Presets.isFactory(p) or PresetDelete.busy() then return end
 gfx.x=x;gfx.y=y
 if gfx.showmenu(PresetDelete.english() and 'Delete' or '削除')==1 then Presets.remove(p) end
 Presets.pressed=nil;Presets.hoverSince=nil
 Presets.down=((gfx.mouse_cap or 0)&1)~=0
 Presets.rightDown=((gfx.mouse_cap or 0)&2)~=0
 PresetDelete.changed()
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
 host.cancelEdit();host.apply(B.copy(p.values));B.presetRevision=(B.presetRevision or 0)+1;B.presetMotionSeen={};Presets.current=p;wake_visuals();notice('プリセットを読み込みました: '..p.name,true)
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
function UI.bar(w)
 local inline=host.docked()
 local compact=host.compactChrome and host.compactChrome() or false
 local dpi=gfx.ext_retina or 1
 local c=B.barCache;if c and c.width==w and c.compact==compact and c.inline==inline and c.dpi==dpi then return c end
 local b={width=w,closeX=w-38,resetX=w-72,themeX=w-106}
 b.foldX=host.fold and b.themeX-34 or nil;b.languageX=(b.foldX or b.themeX)-26;b.nextX=b.languageX-20;b.prevX=b.nextX-20;b.presetX=b.prevX-84
 b.compact=compact;b.inline=inline;b.dpi=dpi
 if inline then B.chromeFont();b.titleEnd=math.min(math.ceil(UI.textMetrics(Chrome.titleText))+28,math.max(0,b.presetX-100)) end
 if compact then b.resetX=b.closeX;b.themeX=w-72;b.foldX=w-106;b.languageX=w+500;b.nextX=w+500;b.prevX=w+500;b.presetX=w+500 end
 B.barCache=b;return b
end
function UI.barHit(x,y)
 local b=UI.bar(gfx.w)
 return y>=0 and y<26 and x>=0 and x<gfx.w and (not b.inline or x<b.titleEnd or x>=b.presetX)
end
local function gfx_window_handle() return host.handle() end
local function chrome_resize_hit(x,y) if host.docked()or(host.transition and host.transition())then return nil end;if y<26 and x>=UI.bar(gfx.w).presetX then return nil end;return host.resizeHit(x,y) end
local function set_resize_cursor(mode) host.cursor(mode) end
local function begin_window_resize(mode) host.beginResize(mode) end
local function update_window_resize() host.resize() end
local function clear_chrome_tooltip() B.popupUntil=nil;if R.TrackCtl_SetToolTip then R.TrackCtl_SetToolTip('',0,0,true) end end
B.clearTooltip=clear_chrome_tooltip
-- Non-modal dependency hint. Uses the existing tick, with no extra defer loop.



function Presets.nativeMenu(x,y)
 if not host.commit() then return end
 host.cancelEdit()
 local labels,actions={},{}
 local function add(label,action,disabled)
  labels[#labels+1]=(disabled and '#' or '')..label:gsub('[|<>!#]',' ')
  actions[#actions+1]=disabled and false or action
 end
 add(Language.message(Presets.factory.name),function() Presets.apply(Presets.factory) end)
 for _,p in ipairs(Presets.items) do
  labels[#labels+1]='>'..p.name:gsub('[|<>!#]',' ')
  add(Language.code=='EN' and 'Load' or '読み込み',function() Presets.apply(p) end)
  add(Language.code=='EN' and 'Delete' or '削除',function() Presets.remove(p) end,host.busy())
  labels[#labels]='<'..labels[#labels]
 end
 add(Language.message('上書き保存'),function() Presets.save(false) end,Presets.isFactory(Presets.current))
 add(Language.message('名前を付けて保存…'),function() Presets.save(true) end)
 add(Language.message('インポート…'),function() Presets.import() end)
 add(Language.message('現在値をエクスポート'),function() Presets.export(false) end,Presets.isFactory(Presets.current))
 add(Language.message('プリセット一覧をエクスポート'),function() Presets.export(true) end,#Presets.items==0)
 gfx.x=x;gfx.y=y
 local choice=gfx.showmenu(table.concat(labels,'|'))
 local action=actions[choice];if action then action() end
 Presets.swallow=true;wake_visuals()
end
function Presets.menu(x,y)
  if host.docked() then Presets.nativeMenu(x,y);return end
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
  -- Hover only opens the preset list, never applies a preset automatically.
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
  local closeW,resetW,chamW=Layout.bar.close,Layout.bar.reset,Layout.bar.theme
  local closeX,resetX,chamX=b.closeX,b.resetX,b.themeX
  local languageX=b.languageX
  local presetX=b.presetX
  local foldX=b.foldX
  local prevX,nextX=b.prevX,b.nextX
  local inWindow=mx>=0 and mx<w and my>=0 and my<gfx.h
  local inBar=not blocked and inWindow and UI.barHit(mx,my) and (host.active() or (gfx.getchar(65536)&8)~=0)
  local resizeMode=not blocked and chrome_resize_hit(mx,my) or nil
  local resizing=Chrome.resize~=nil
  local cursorMode=resizing and Chrome.resize.mode or resizeMode
  set_resize_cursor(cursorMode)
  local control=inBar and not resizeMode and not resizing and BLTChrome.hit(b,mx,my,w,Chrome.titleH) or nil
  local hoverClose=control=='close'
  local hoverReset=not host.docked() and not (host.collapsed and host.collapsed()) and not (host.transition and host.transition()) and control=='reset'
  local hoverCham=control=='theme'
  local hoverPreset=control=='preset'
  local hoverPrev=control=='prev'
  local hoverNext=control=='next'
  local hoverFold=foldX and not (host.transition and host.transition()) and control=='fold'
  local hoverLanguage=control=='language'
  local down=not blocked and (gfx.mouse_cap&1)~=0
  -- A content modal disables chrome; it does not give chrome ownership of its input.
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
  p.hot=hoverClose and 'close' or hoverReset and 'reset' or hoverCham and 'theme' or hoverLanguage and 'language' or hoverPreset and 'preset' or hoverPrev and 'prev' or hoverNext and 'next' or hoverFold and 'fold' or nil
  p.collapsed=host.collapsed and host.collapsed() or false;p.docked=host.docked and host.docked() or false;p.dockButton=host.docked~=nil;p.compactLanguage=false
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
    elseif hoverFold then
      Chrome.foldPressed=true
    elseif hoverCham then
      Chrome.chameleonPressed=true
    elseif inBar and not host.docked() and not (host.transition and host.transition()) then
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
      d.lastX,d.lastY=x,y;Chrome.geometryDirty=true
    end
  end

  if not down and Chrome.mouseDown then
    if Chrome.languagePressed and hoverLanguage then B.toggleLanguage() end
    Chrome.languagePressed=false
    if Chrome.closePressed and hoverClose then Chrome.requestClose=true end
    if Chrome.resetPressed and hoverReset then Chrome.requestReset=true end
    if Chrome.foldPressed and hoverFold then host.fold() end;Chrome.foldPressed=false
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
 return Presets.open or Presets.swallow or UI.barHit(gfx.mouse_x,gfx.mouse_y)
end
-- Shared project Undo shortcut. Embedded; no runtime file dependency.
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
local project_undo=create_project_undo(R,{
 language=function() return Language.code end,notice=notice,
 editing=function() return host.editing() or host.modal() end,
 busy=function() return host.busy() end,
 before=function() if host.undoBefore then host.undoBefore() end end,
 after=function(project) if host.undoRefresh then host.undoRefresh(project) end;wake_visuals() end,
})
function B.key(k)
 if k<0 then return k end
 if host and host.beforeKey then host.beforeKey(k) end
 if Presets.open then Presets.key(k);return 0 end
 if host and not host.localUndo then
  if host.undoAction then
   local cap=gfx.mouse_cap or 0
   if (cap&24)==0 and (k==26 or ((cap&4)~=0 and (k==90 or k==122))) then
    if not host.editing() and not host.modal() then host.undoAction() end
    return 0
   end
  elseif project_undo(k,gfx.mouse_cap) then return 0 end
 end
 return k
end
function B.tick(now)
 Media.tick()
 if not host then return end
 if B.windowW~=gfx.w or B.windowH~=gfx.h then B.windowW,B.windowH=gfx.w,gfx.h;B.lastRect=nil;wake_visuals() end
 B.viewport(host.geometry(),gfx.ext_retina or 1)
 if B.openAfterExpand and not host.collapsed() and not host.busy() then B.openAfterExpand=nil;Presets.menu();wake_visuals() end
 local active=host.active()
 if Presets.open or Presets.swallow then Presets.update(active) end
 if Presets.open and Presets.hoverSince and now>=Presets.hoverSince+1 then wake_visuals() end
 if B.noticeUntil and now>=B.noticeUntil then B.noticeUntil=nil;B.notice=nil;wake_visuals() end
 local phase=host.editing() and (now%1<.5) or false
 if B.caretPhase~=phase then B.caretPhase=phase;wake_visuals() end
 if B.lastDPI~=(gfx.ext_retina or 1) then B.lastDPI=gfx.ext_retina or 1;wake_visuals() end
 if now>=(B.displayAt or 0) then gfx.update();B.displayAt=now+.25 end
 if B.popupUntil then
  if now<B.popupUntil then return end
  clear_chrome_tooltip();B.tip=nil;B.tipVisible=false;B.tipAt=now
 end
 local tip
 local mx,my=gfx.mouse_x,gfx.mouse_y
 if active and not Presets.open and not host.modal() and (gfx.mouse_cap&1)==0 then
  if UI.barHit(mx,my) then
   local b=UI.bar(gfx.w)
   tip=mx>=b.closeX and '閉じる' or mx>=b.resetX and 'ウィンドウサイズ初期化' or mx>=b.themeX and 'カメレオンモード' or b.foldX and mx>=b.foldX and (Language.code=='JP' and (host.docked() and 'ドック解除' or 'ドッカーに格納') or (host.docked() and 'Undock' or 'Dock')) or mx>=b.languageX and '表示言語を切替（JP / EN）' or mx>=b.nextX and '次のプリセット' or mx>=b.prevX and '前のプリセット' or mx>=b.presetX and 'プリセット（読込・保存・インポート／エクスポート）' or nil
  end
 end
 if not tip and host.tip and active and not Presets.open and not host.modal() and (gfx.mouse_cap&1)==0 then tip=host.tip(mx,my) end
 if tip then tip=Language.message(tip) end
 if tip~=B.tip then if B.tipVisible then clear_chrome_tooltip() end;B.tip=tip;B.tipAt=now;B.tipVisible=false
 elseif tip and not B.tipVisible and now-B.tipAt>.7 and R.TrackCtl_SetToolTip and gfx.clienttoscreen then
  local x,y=gfx.clienttoscreen(mx,my+18);R.TrackCtl_SetToolTip(tip,x,y,true);B.tipVisible=true
 end
end
function B.bar()
 if not host then return end
 gfx.textRoute(true)
 scale,ox,oy=host.geometry()
 local blocked=not B.recoveryMode and (Presets.open or Presets.swallow or host.modal())
 custom_titlebar(blocked)
 Presets.draw()
gfx.textRoute(false)
end

-- Preserve title-bar button edges across repeated application failures.
function B.logError(err)
 local message=B.publicError(err)
 if message~=B.lastLoggedError then
  B.lastLoggedError=message
  if R.ShowConsoleMsg then pcall(R.ShowConsoleMsg,tostring(err)..'\n') end
 end
end
function B.cleanup(fn,...)
 local ok,result=pcall(fn,...)
 if not ok then B.logError(result) end
 return ok,result
end
function B.recoverInput(state,err)
 gfx.abort()
 for _,key in ipairs({'drag','number_drag','pointer_capture','field_drag','fieldDrag','scrollDrag','source_wave_drag','curve_drag','scroll_drag','seam_drag','seam_hold','pressed','popup','name_dialog','duplicate_modal'}) do state[key]=nil end
 if host.cancelEdit then B.cleanup(host.cancelEdit) end
 Presets.open=false;Presets.swallow=false;Presets.pressed=nil;Presets.hoverSince=nil
 Chrome.drag=nil;Chrome.resize=nil
 if host.cursor then B.cleanup(host.cursor,nil) end
 B.recoveryMode=true
 local ok,why=pcall(B.bar)
 B.recoveryMode=nil
 if not ok then
  B.logError(why)
  -- A failed font, preset or theme draw must still allow closing the window.
  local down=((gfx.mouse_cap or 0)&1)~=0
  local hit=gfx.mouse_y>=0 and gfx.mouse_y<26 and gfx.mouse_x>=gfx.w-38 and gfx.mouse_x<gfx.w
  if down and not B.emergencyDown then B.emergencyClose=hit end
  if not down and B.emergencyDown then
   if B.emergencyClose and hit then Chrome.requestClose=true end
   B.emergencyClose=nil
  end
  B.emergencyDown=down
 else B.emergencyDown=nil;B.emergencyClose=nil end
 pcall(gfx.update)
 if Chrome.requestClose then state.closing=true end
 state.content_dirty=true
 B.cleanup(host.wake)
 B.logError(err)
end

return B
end)()

local SECTION='BLT_MINIMAL_INFO_PANEL'
local min,max,abs,floor=math.min,math.max,math.abs,math.floor
local function clamp(v,a,b) return max(a,min(b,v)) end
local function finite(v) return type(v)=='number' and v==v and abs(v)<math.huge end
local Core={}
function Core.precision(key,value)
 if key~='volume' and key~='pitch' then return value end
 local n=math.floor(math.abs(value)*100+1e-9)/100
 return n==0 and 0 or (value<0 and -n or n)
end
-- Host values can be just below a hundredth after state restoration or gain/dB
-- conversion. Round only the control/display value; retain raw snapshot values
-- for rollback and native Undo. Explicit typed input keeps Core.precision.
function Core.control_value(key,value)
 if key~='volume' and key~='pitch' then return value end
 local n=math.floor(math.abs(value)*100+.5+1e-9)/100
 return n==0 and 0 or (value<0 and -n or n)
end
function Core.step(key,value,fine)
 local n=value*(fine and .1 or 1)
 if key=='volume' or key=='pitch' then return max(.01,Core.precision(key,n)) end
 return n
end
Core.specs={length={label='長さ',lo=.000001,hi=10000000},volume={label='ボリューム',lo=-150,hi=24},pitch={label='ピッチ',lo=-120,hi=120},rate={label='再生速度',lo=.001,hi=100},pan={label='PAN',lo=-100,hi=100}}
Core.defaults={lengthMode=-1}
function Core.valid_length_mode(v) return v==-1 or v==0 or v==2 or v==3 or v==4 or v==5 or v==6 end
function Core.valid_settings(v)
 if type(v)~='table' or not Core.valid_length_mode(v.lengthMode) then return false end
 for k in pairs(v) do if k~='lengthMode' then return false end end
 return true
end
function Core.valid(project,p,kind) return p and R.ValidatePtr2(project,p,kind) end
function Core.row(project,item)
 local take=R.GetActiveTake(item)
 local v={item=item,take=take,project=project,pos=R.GetMediaItemInfo_Value(item,'D_POSITION'),
  track=R.GetMediaTrackInfo_Value(R.GetMediaItemTrack(item),'IP_TRACKNUMBER'),index=R.GetMediaItemInfo_Value(item,'IP_ITEMNUMBER'),
  length=R.GetMediaItemInfo_Value(item,'D_LENGTH'),gain=R.GetMediaItemInfo_Value(item,'D_VOL'),
  mute=R.GetMediaItemInfo_Value(item,'B_MUTE_ACTUAL')~=0,lockBits=floor(R.GetMediaItemInfo_Value(item,'C_LOCK') or 0)}
 v.volume=v.gain>0 and max(Core.specs.volume.lo,20*math.log(v.gain,10)) or Core.specs.volume.lo
 v.lock=(v.lockBits&1)~=0
 if take then
  v.midi=R.TakeIsMIDI(take)
  v.name=R.GetTakeName(take) or '';v.pitch=R.GetMediaItemTakeInfo_Value(take,'D_PITCH');v.pan=R.GetMediaItemTakeInfo_Value(take,'D_PAN')*100
  local rate=R.GetMediaItemTakeInfo_Value(take,'D_PLAYRATE');if finite(rate) and rate>0 then v.rate=rate end
  if not v.midi and R.BR_GetMediaSourceProperties then
   local ok,section,start,len,fade,reverse=R.BR_GetMediaSourceProperties(take)
   if ok then v.reverse=reverse;v.sourceProps={section,start,len,fade,reverse} end
  end
 end
 return v
end
function Core.collect(project)
 local rows={}
 for i=0,R.CountSelectedMediaItems(project)-1 do
  local item=R.GetSelectedMediaItem(project,i)
  if Core.valid(project,item,'MediaItem*') then rows[#rows+1]=Core.row(project,item) end
 end
 table.sort(rows,function(a,b)
  if a.track~=b.track then return a.track<b.track end
  if a.pos~=b.pos then return a.pos<b.pos end
  return a.index<b.index
 end)
 return rows
end
function Core.snapshot()
 local project=R.EnumProjects(-1,'')
 return {project=project,revision=R.GetProjectStateChangeCount(project),rows=Core.collect(project)}
end
function Core.display(project,selection)
 local first,track,pos,index
 local mixed,trackNumbers={},{}
 local mute,lock,reverse,hasMidi=nil,nil,nil,false
 local count=selection and #selection or R.CountSelectedMediaItems(project)
 for i=0,count-1 do
  local item=selection and selection[i+1] or R.GetSelectedMediaItem(project,i)
  if Core.valid(project,item,'MediaItem*') then
   if not mixed.mute then
    local value=R.GetMediaItemInfo_Value(item,'B_MUTE_ACTUAL')~=0
    if mute~=nil and mute~=value then mixed.mute=true end;mute=value
   end
   if not mixed.lock then
    local value=(floor(R.GetMediaItemInfo_Value(item,'C_LOCK') or 0)&1)~=0
    if lock~=nil and lock~=value then mixed.lock=true end;lock=value
   end
   if not hasMidi then
    local take=R.GetActiveTake(item)
    if take and R.TakeIsMIDI(take) then hasMidi=true
    elseif take and not mixed.reverse and R.BR_GetMediaSourceProperties then
     local ok,_,_,_,_,value=R.BR_GetMediaSourceProperties(take)
     if ok and value~=nil then
      if reverse~=nil and reverse~=value then mixed.reverse=true end;reverse=value
     end
    end
   end
   local tr=R.GetMediaItemTrack(item);local t=trackNumbers[tr]
   if t==nil then t=R.GetMediaTrackInfo_Value(tr,'IP_TRACKNUMBER');if tr then trackNumbers[tr]=t end end
   if not first or t<track then
    first,track,pos,index=item,t,R.GetMediaItemInfo_Value(item,'D_POSITION'),R.GetMediaItemInfo_Value(item,'IP_ITEMNUMBER')
   elseif t==track then
    local p=R.GetMediaItemInfo_Value(item,'D_POSITION')
    if p<pos then first,pos,index=item,p,R.GetMediaItemInfo_Value(item,'IP_ITEMNUMBER')
    elseif p==pos then
     local n=R.GetMediaItemInfo_Value(item,'IP_ITEMNUMBER');if n<index then first,index=item,n end
    end
   end
  end
 end
 return first and {Core.row(project,first)} or {},count,mixed,hasMidi
end
function Core.check(s)
 if R.EnumProjects(-1,'')~=s.project or R.GetProjectStateChangeCount(s.project)~=s.revision then return false,'編集中に対象が変更されました。もう一度操作してください。' end
 if R.CountSelectedMediaItems(s.project)~=#s.rows then return false,'選択が変更されました。もう一度操作してください。' end
 for _,v in ipairs(s.rows) do
  if not Core.valid(s.project,v.item,'MediaItem*') or not R.IsMediaItemSelected(v.item)
   or R.GetActiveTake(v.item)~=v.take or (v.take and not Core.valid(s.project,v.take,'MediaItem_Take*')) then return false,'対象アイテムが変更または削除されました。' end
 end
 return true
end
function Core.parse(key,text)
 if key=='name' then
  if type(text)~='string' or not utf8.len(text) or text:find('[%z\r\n]') or #text>4096 then return nil,'名前は改行なし・4096バイト以内で入力してください。' end
  return text
 end
 local s=tostring(text):match('^%s*(.-)%s*$')
 if key=='pan' then
  if s:upper()=='C' then return 0 end
  local side,n=s:upper():match('^([LR])%s*(%d+%.?%d*)%%?$')
  if side then s=tostring(tonumber(n)*(side=='L' and -1 or 1)) end
 end
 local n=tonumber(s);local spec=Core.specs[key]
 if not finite(n) or not spec or n<spec.lo or n>spec.hi then return nil,'数値が範囲外です。元の値を保持しました。' end
 return Core.precision(key,n)
end
function Core.format(key,v)
 if v==nil then return '—' end
 if key=='name' then return v~='' and v or '（名前なし）' end
 if key=='length' then return string.format('%.3f s',v) end
 if key=='volume' then v=Core.control_value(key,v);return v<=-150 and '−∞ dB' or v==0 and '0.00 dB' or string.format('%+.2f dB',v) end
 if key=='pitch' then v=Core.control_value(key,v);return v==0 and '0.00 st' or string.format('%+.2f st',v) end
 if key=='rate' then
  local st=Core.control_value('pitch',12*math.log(v,2))
  return string.format('%.3f (%s st)',v,st==0 and '0.00' or string.format('%+.2f',st))
 end
 if key=='pan' then return abs(v)<.0001 and 'C' or string.format('%s %.1f%%',v<0 and 'L' or 'R',abs(v)) end
 return v and 'ON' or 'OFF'
end
function Core.plan(s,key,value,absolute)
 if #s.rows==0 then return nil,'アイテムを選択してください。' end
 local spec=Core.specs[key];local changes={};local first=s.rows[1][key]
 if first==nil then return nil,'この項目は選択アイテムでは編集できません。' end
 if spec and not finite(value) then return nil,'数値が不正です。' end
 if spec then value=Core.precision(key,value);first=Core.control_value(key,first) end
 if not spec and key~='name' and type(value)~='boolean' then return nil,'値が不正です。' end
 for _,v in ipairs(s.rows) do
  if v[key]==nil then return nil,'選択内にこの項目を編集できないアイテムがあります。' end
  if key~='lock' and v.lock then return nil,'ロックされたアイテムがあります。先にロックを解除してください。' end
  local current=spec and Core.control_value(key,v[key]) or v[key]
  local target=value
  if spec then
   target=Core.precision(key,clamp(absolute and value or current+(value-first),spec.lo,spec.hi))
  end
  if key=='rate' then
   local newLength=v.length*v.rate/target
   if not finite(newLength) or newLength<=0 then return nil,'数値が範囲外です。元の値を保持しました。' end
  end
  -- Committing the displayed value must not rewrite hidden precision or create
  -- an Undo step. Explicit -infinity still silences a nonzero gain.
  local changed=target~=current or (key=='volume' and absolute and target<=-150 and v.gain~=0)
  if changed then changes[#changes+1]={row=v,before=v[key],after=target} end
 end
 return changes
end
function Core.set(v,key,value,restore)
 if key=='name' then return R.GetSetMediaItemTakeInfo_String(v.take,'P_NAME',value,true)
 elseif key=='length' then return R.SetMediaItemInfo_Value(v.item,'D_LENGTH',value)
 elseif key=='volume' then return R.SetMediaItemInfo_Value(v.item,'D_VOL',restore and v.gain or (value<=-150 and 0 or 10^(value/20)))
 elseif key=='pitch' then return R.SetMediaItemTakeInfo_Value(v.take,'D_PITCH',value)
 elseif key=='rate' then
  local length=restore and v.length or v.length*v.rate/value
  local rateOK=R.SetMediaItemTakeInfo_Value(v.take,'D_PLAYRATE',value)
  if not rateOK and not restore then return false end
  local lengthOK=R.SetMediaItemInfo_Value(v.item,'D_LENGTH',length)
  return rateOK and lengthOK
 elseif key=='pan' then return R.SetMediaItemTakeInfo_Value(v.take,'D_PAN',value/100)
 elseif key=='mute' then return R.SetMediaItemInfo_Value(v.item,'B_MUTE_ACTUAL',value and 1 or 0)
 elseif key=='lock' then return R.SetMediaItemInfo_Value(v.item,'C_LOCK',(v.lockBits&(~1))|(value and 1 or 0))
 elseif key=='reverse' then
  if not R.BR_SetMediaSourceProperties then return false end
  local p=v.sourceProps
  if not R.BR_SetMediaSourceProperties(v.take,p[1],p[2],p[3],p[4],value) then return false end
  -- Trigger the native take-change path synchronously; restore exact pitch even if the first setter fails.
  local pitch=v.pitch
  if not finite(pitch) then return false end
  local delta=pitch>=120 and -.000001 or .000001
  local ok,touched=pcall(R.SetMediaItemTakeInfo_Value,v.take,'D_PITCH',pitch+delta)
  local restored,result=pcall(R.SetMediaItemTakeInfo_Value,v.take,'D_PITCH',pitch)
  if not restored or not result then return false end
  return ok and touched
 end
 return false
end
function Core.refresh_item(v,key)
 if key=='reverse' or key=='rate' then
  local ok,err=pcall(R.UpdateItemInProject,v.item)
  if not ok then
   BLT.logError(err)
   local track=R.GetMediaItemTrack(v.item)
   if track and R.MarkTrackItemsDirty then
    local worked,why=pcall(R.MarkTrackItemsDirty,track,v.item)
    if not worked then BLT.logError(why) end
   end
  end
 end
end
function Core.commit(s,key,changes,defer_undo)
 if #changes==0 then return 0 end
 local attempted=0
 if not defer_undo then R.Undo_BeginBlock2(s.project) end
 R.PreventUIRefresh(1)
 local success,why=xpcall(function()
  for i,c in ipairs(changes) do attempted=i;if not Core.set(c.row,key,c.after,false) then error('値を変更できませんでした。',0) end end
 end,debug.traceback)
 local restored=true
 if not success then for i=attempted,1,-1 do local c=changes[i];local worked,result=pcall(Core.set,c.row,key,c.before,true);if not worked or not result then restored=false end end end
 for i=1,attempted do Core.refresh_item(changes[i].row,key) end
 R.PreventUIRefresh(-1);R.UpdateArrange()
 if not defer_undo then R.Undo_EndBlock2(s.project,'BLT MINIMAL INFO PANEL: '..key..(success and '' or ' (failed)'),-1) end
 if not success then return nil,restored and '変更に失敗したため、元の値へ戻しました。' or '復元できない項目があります。REAPERのUndoで確認してください。' end
 return #changes
end
function Core.apply(s,key,value,absolute,defer_undo)
 local ok,err=Core.check(s);if not ok then return nil,err end
 local changes;changes,err=Core.plan(s,key,value,absolute);if not changes then return nil,err end
 return Core.commit(s,key,changes,defer_undo)
end

local S=BLT.copy(Core.defaults)
local A={selection={},items={},project=nil,message='アイテムを選択してください。',bad=false,nextPoll=0,revision=nil,flash={},closing=false}
local lengthMode=tonumber(R.GetExtState(SECTION,'length_mode')) or -1
if not Core.valid_length_mode(lengthMode) then lengthMode=-1 end
S.lengthMode=lengthMode
local function frame_rate()
 local fps=R.TimeMap_curFrameRate(R.EnumProjects(-1,''))
 return fps
end
local function length_text(value,pos)
 if lengthMode==6 then return string.format('%.3f',value*frame_rate()):gsub('0+$',''):gsub('%.$','') end
 if lengthMode==3 then return string.format('%.3f',value) end
 return R.format_timestr_len(value,'',pos or 0,lengthMode)
end
local function effective_length_mode()
 local mode=lengthMode
 if mode==-1 and R.GetToggleCommandState then
  if R.GetToggleCommandState(40369)==1 then return 4 end
  if R.GetToggleCommandState(40370)==1 or R.GetToggleCommandState(41973)==1 then return 5 end
  if R.GetToggleCommandState(40365)==1 or R.GetToggleCommandState(40368)==1 then return 3 end
  return 2
 end
 return mode
end
local function length_step(fine)
 local mode=effective_length_mode()
 if mode==4 then return R.parse_timestr_len('1',0,4) end
 if mode==5 or mode==6 then return 1/frame_rate() end
 return fine and .1 or 1
end
function Core.adjust_value(key,first,ticks,fine,mode)
 if ticks==0 then return Core.control_value(key,first[key]) end
 local value=first[key]
 if key=='rate' then
  local unit=fine and .1 or 1
  local st=12*math.log(value,2)/unit
  local nextIndex=ticks>0 and math.floor(st+1e-9)+ticks or math.ceil(st-1e-9)+ticks
  value=2^(nextIndex*unit/12)
 elseif key=='length' and (mode or effective_length_mode())==2 then
  local project=first.project or R.EnumProjects(-1,'')
  local _,_,_,beats=R.TimeMap2_timeToBeats(project,first.pos+value)
  value=R.TimeMap2_beatsToTime(project,beats+ticks*(fine and .1 or 1))-first.pos
 else
  local step=key=='length' and length_step(fine) or Core.step(key,1,fine)
  value=Core.control_value(key,value)+ticks*step
 end
 local spec=Core.specs[key]
 return Core.precision(key,clamp(value,spec.lo,spec.hi))
end
-- Wheel edits are live, but only the settled result becomes an Undo point.
-- Do not leave a project-wide Undo block open across defer calls: other native
-- actions must remain free to create/restore their own history states.
local WheelUndo={delay=.5}
function WheelUndo.project_open(project)
 if R.EnumProjects(-1,'')==project then return true end
 local i=0
 while true do
  local p=R.EnumProjects(i,'');if not p then return false end
  if p==project then return true end;i=i+1
 end
end
function WheelUndo.history_changed(p)
 return R.Undo_CanUndo2(p.project)~=p.undo or R.Undo_CanRedo2(p.project)~=p.redo
end
function WheelUndo.selection_matches(p)
 if R.EnumProjects(-1,'')~=p.project or R.CountSelectedMediaItems(p.project)~=#p.before.rows then return false end
 for i=0,#p.before.rows-1 do
  local item=R.GetSelectedMediaItem(p.project,i);local v=item and p.selected[item]
  if not v or not Core.valid(p.project,item,'MediaItem*') or R.GetActiveTake(item)~=v.take then return false end
 end
 return true
end
function WheelUndo.has_changes(p,rows)
 -- Compare stored native values, not formatted decimals. This also covers the
 -- coupled item length when wheel-editing playback rate.
 for _,v in ipairs(rows or p.before.rows) do
  if not Core.valid(p.project,v.item,'MediaItem*') then return true end
  if p.key=='volume' then
   if R.GetMediaItemInfo_Value(v.item,'D_VOL')~=v.gain then return true end
  elseif p.key=='length' then
   if R.GetMediaItemInfo_Value(v.item,'D_LENGTH')~=v.length then return true end
  else
   if not Core.valid(p.project,v.take,'MediaItem_Take*') then return true end
   if p.key=='pitch' and R.GetMediaItemTakeInfo_Value(v.take,'D_PITCH')~=v.pitch then return true end
   if p.key=='pan' and R.GetMediaItemTakeInfo_Value(v.take,'D_PAN')*100~=v.pan then return true end
   if p.key=='rate' and (R.GetMediaItemTakeInfo_Value(v.take,'D_PLAYRATE')~=v.rate
      or R.GetMediaItemInfo_Value(v.item,'D_LENGTH')~=v.length) then return true end
  end
 end
 return false
end
function WheelUndo.commit(p)
 if not WheelUndo.project_open(p.project) or WheelUndo.history_changed(p) then
  -- A native action has already checkpointed/restored the live state. Never
  -- append a stale timer point (which would invalidate native Redo).
  return false
 end
 -- Older REAPER versions may expose identical Undo/Redo descriptions for
 -- adjacent entries. An unexpected change to the values we just wrote also
 -- invalidates the pending group; never checkpoint an externally restored value.
 if not p.applying and p.after and R.GetProjectStateChangeCount(p.project)~=p.revision
    and WheelUndo.has_changes(p,p.after) then return false end
 local changed=WheelUndo.has_changes(p)
 if changed then R.Undo_OnStateChangeEx2(p.project,'BLT MINIMAL INFO PANEL: '..p.key,4,-1) end
 return changed
end
function WheelUndo.finish()
 local p=WheelUndo.pending;WheelUndo.pending=nil
 return p and WheelUndo.commit(p) or false
end
function WheelUndo.poll(now)
 local p=WheelUndo.pending;if not p then return end
 if not WheelUndo.project_open(p.project) or WheelUndo.history_changed(p) then WheelUndo.pending=nil;return end
 local flags=gfx.getchar(65536)
 local focused=(flags&1)==0 or (flags&2)~=0
 local buttons=(gfx.mouse_cap or 0)&3
 if R.JS_Mouse_GetState then
  local ok,state=pcall(R.JS_Mouse_GetState,3)
  if ok and type(state)=='number' then buttons=buttons|(floor(state)&3) end
 end
 if now>=p.deadline or not WheelUndo.selection_matches(p)
    or R.GetProjectStateChangeCount(p.project)~=p.revision
    or focused~=p.focused or buttons~=0 then WheelUndo.finish() end
end
function WheelUndo.apply(key,ticks,fine,absolute)
 WheelUndo.poll(R.time_precise())
 local p=WheelUndo.pending
 if p and (p.key~=key or p.absolute~=(absolute==true)) then WheelUndo.finish();p=nil end
 local snap=Core.snapshot();local first=snap.rows[1]
 if not first or first[key]==nil then return 0 end
 local value=Core.adjust_value(key,first,ticks,fine)
 local ok,err=Core.check(snap);if not ok then WheelUndo.finish();return nil,err end
 local changes;changes,err=Core.plan(snap,key,value,absolute)
 if not changes then WheelUndo.finish();return nil,err end
 if #changes==0 then
  if p then p.deadline=R.time_precise()+WheelUndo.delay end
  return 0
 end
 if not p then
  local flags=gfx.getchar(65536)
  p={project=snap.project,key=key,absolute=absolute==true,before=snap,selected={},
   undo=R.Undo_CanUndo2(snap.project),redo=R.Undo_CanRedo2(snap.project),
   focused=(flags&1)==0 or (flags&2)~=0,revision=snap.revision}
  for _,v in ipairs(snap.rows) do p.selected[v.item]=v end
  WheelUndo.pending=p
 end
 p.deadline=R.time_precise()+WheelUndo.delay
 p.applying=true
 local n; n,err=Core.apply(snap,key,value,absolute,true)
 if n then p.after=Core.collect(p.project) end
 p.revision=R.GetProjectStateChangeCount(p.project);p.applying=nil
 p.deadline=R.time_precise()+WheelUndo.delay
 if not n then WheelUndo.finish();return nil,err end
 return n
end

local IME={};local E=nil;local gesture=nil
local function status(text,bad) A.message=tostring(text or '');A.bad=bad==true;A.content_dirty=true end
local function save_settings()
 S.lengthMode=lengthMode;BLT.store(SECTION,'length_mode',tostring(lengthMode),true)
end
local function extnum(key,default) local n=tonumber(R.GetExtState(SECTION,key));return finite(n) and n or default end
local W,H=1230,44
local C={
  bg={0.018,0.030,0.055}, bg2={0.030,0.090,0.180}, panel={0.040,0.068,0.110}, panel2={0.055,0.125,0.205},
  field={0.018,0.040,0.080}, edge={0.145,0.285,0.445}, edge2={0.360,0.650,0.900},
  text={0.955,0.980,1.000}, muted={0.690,0.780,0.875}, faint={0.390,0.505,0.635},
  accent={0.120,0.490,0.980}, accent2={0.650,0.895,1.000}, accent3={0.045,0.235,0.520},
  focus={0.225,0.610,1.000}, focus2={0.690,0.900,1.000}, ink={0.018,0.075,0.160},
  disabled={.43,.46,.51},ice={.65,.895,1},
  hover={0.430,0.790,1.000}, warn={1.000,0.755,0.490}, red={1.000,0.230,0.300}, green={0.470,0.850,0.700}, quiet={0.300,0.360,0.440}
}
local BLTFieldControls=(function()
local M={}
M.compactScale=458/904
function M.new(g,clock,palette)
 local U={C=palette,states={},scale=M.compactScale,ox=0,oy=0,now=clock(),frameSerial=0}
 local min,max=math.min,math.max
 function U:state(id) self.states[id]=self.states[id] or {};return self.states[id] end
 function U:rect(x,y,w,h,c,a,fill)
  g.set(c[1],c[2],c[3],a or 1);g.rect(self.ox+x*self.scale,self.oy+y*self.scale,w*self.scale,h*self.scale,fill==false and 0 or 1)
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
local fieldUI=BLTFieldControls.new(gfx,R.time_precise,C)
local density=BLTFieldControls.compactScale
local fonts={"Yu Gothic UI","Segoe UI","Consolas"}
local os_name=R.GetOS()
if os_name:match("OSX") or os_name:match("macOS") then fonts={"Hiragino Sans","Helvetica Neue","Menlo"}
elseif not os_name:match("Win") then fonts={"sans-serif","sans-serif","monospace"} end
local ValueTextMetrics=(function()
local M={}
local floor,ceil,min,max=math.floor,math.ceil,math.min,math.max
local function font(path,index)
 local file=io.open(path,'rb');if not file then return end
 local function read(at,n)assert(file:seek('set',at));return assert(file:read(n))end
 local ok,result=pcall(function()
  local header=read(0,16);local base=0
  if header:sub(1,4)=='ttcf'then
   local count=string.unpack('>I4',header,9);if index>=count then return end
   base=string.unpack('>I4',read(12+index*4,4))
  elseif index~=0 then return end
  local count=string.unpack('>I2',read(base,12),5);if count<1 or count>256 then return end
  local tables={}
  for i=0,count-1 do
   local entry=read(base+12+i*16,16);local at,length=string.unpack('>I4I4',entry,9);tables[entry:sub(1,4)]={at,length}
  end
  if not(tables.hhea and tables['OS/2'])then return end
  local ascent,descent=string.unpack('>i2i2',read(tables.hhea[1],10),5)
  local os2=read(tables['OS/2'][1],min(90,tables['OS/2'][2]))
  if (string.unpack('>I2',os2,63)&128)~=0 then ascent,descent=string.unpack('>i2i2',os2,69)end
  if ascent<=0 or descent>0 then return end
  local cap=#os2>=90 and string.unpack('>i2',os2,89)or ascent*.85
  local p={file=file,ascent=ascent,height=ascent-descent,cap=cap,glyphs={},count=0}
  if not(tables.head and tables.cmap and tables.loca and tables.glyf)then return p end
  local cmap=read(tables.cmap[1],tables.cmap[2]);p.cmap=cmap
  for i=0,string.unpack('>I2',cmap,3)-1 do
   local platform,encoding,offset=string.unpack('>I2I2I4',cmap,5+i*8)
   if platform==0 or platform==3 and(encoding==1 or encoding==10)then
    local format=string.unpack('>I2',cmap,offset+1)
    if format==4 then p.cmap4=offset+1 elseif format==12 then p.cmap12=offset+1 end
   end
  end
  p.short=string.unpack('>i2',read(tables.head[1],54),51)==0
  p.loca=read(tables.loca[1],tables.loca[2]);p.glyf=tables.glyf[1]
  return p
 end)
 if ok and result then return result end
 file:close()
end
local function glyph(p,cp)
 local s=p.cmap;local at=p.cmap12
 if at then
  local lo,hi=0,string.unpack('>I4',s,at+12)-1
  while lo<=hi do
   local mid=(lo+hi)//2;local first,last,id=string.unpack('>I4I4I4',s,at+16+mid*12)
   if cp<first then hi=mid-1 elseif cp>last then lo=mid+1 else return id+cp-first end
  end
 end
 at=p.cmap4;if not at or cp>65535 then return end
 local count=string.unpack('>I2',s,at+6)//2;local lo,hi=0,count-1
 while lo<hi do local mid=(lo+hi)//2;if string.unpack('>I2',s,at+14+mid*2)<cp then lo=mid+1 else hi=mid end end
 local first=string.unpack('>I2',s,at+16+count*2+lo*2)
 if cp<first or cp>string.unpack('>I2',s,at+14+lo*2)then return end
 local delta=string.unpack('>i2',s,at+16+count*4+lo*2)
 local address=at+16+count*6+lo*2;local offset=string.unpack('>I2',s,address)
 if offset==0 then return(cp+delta)&65535 end
 local id=string.unpack('>I2',s,address+offset+(cp-first)*2)
 return id~=0 and(id+delta)&65535 or nil
end
local function bounds(p,cp)
 local cached=p.glyphs[cp];if cached~=nil then return cached end
 local result=false;local id=p.cmap and glyph(p,cp)
 if id and id>0 then
  local width=p.short and 2 or 4;local format=p.short and '>I2'or '>I4'
  local first=string.unpack(format,p.loca,id*width+1);local last=string.unpack(format,p.loca,(id+1)*width+1)
  if first~=last then
   p.file:seek('set',p.glyf+first*(p.short and 2 or 1))
   local data=p.file:read(10)
   if data and #data==10 then local lo=string.unpack('>i2',data,5);local hi=string.unpack('>i2',data,9);result={lo,hi}end
  end
 end
 if p.count>=2048 then p.glyphs={};p.count=0 end
 p.glyphs[cp]=result;p.count=p.count+1;return result
end
function M.new(osName)
 local mac=osName:match('OSX')or osName:match('macOS')
 local root=(os.getenv('WINDIR')or 'C:/Windows')..'/Fonts/'
 local paths=mac and{{'/System/Library/Fonts/ヒラギノ角ゴシック W4.ttc',0},{'/System/Library/Fonts/Menlo.ttc',0}}or
  osName:match('Win')and{{root..'YuGothM.ttc',1},{root..'consola.ttf',0}}or {}
 local T={fonts={},cache={}}
 function T:offset(name,text,size,dpi)
  local kind=name and 1 or 2;text=text~=''and text or(name and 'Hg名前'or '0123456789')
  local cached=self.cache[kind]
  if not cached or cached.size~=size or cached.dpi~=dpi or cached.count>=128 then
   cached={size=size,dpi=dpi,values={},count=0};self.cache[kind]=cached
  end
  if cached.values[text]~=nil then return cached.values[text]end
  local p=self.fonts[kind]
  if p==nil then local path=paths[kind];p=path and font(path[1],path[2])or false;self.fonts[kind]=p end
  local offset=name and -1 or 1
  if p then
   local lower,upper=math.huge,-math.huge
   for _,cp in utf8.codes(text)do local b=bounds(p,cp);if b then lower,upper=min(lower,b[1]),max(upper,b[2])end end
   if lower==math.huge then lower,upper=name and -p.height*.12 or 0,name and p.height*.72 or p.cap end
   local pixels=size*dpi
   offset=(pixels*.5-ceil(pixels*p.ascent/p.height)+(ceil(pixels*upper/p.height)+floor(pixels*lower/p.height))*.5)/dpi
  end
  cached.values[text]=offset;cached.count=cached.count+1;return offset
 end
 function T:close()for _,p in pairs(self.fonts)do if p and p.file then p.file:close();p.file=nil end end end
 return T
end
return M
end)()
local valueMetrics=ValueTextMetrics.new(os_name)

local scale,ox,oy,mx,my=1,0,0,-1,-1
local downLast=false
local redraw_dirty=true
local last_raw_mouse_x,last_raw_mouse_y,last_raw_mouse_cap=nil,nil,nil
local function wake_visuals() redraw_dirty=true end

local function sx(x) return ox+x*scale end
local function sy(y) return oy+y*scale end
local function color(c,a) gfx.set(c[1],c[2],c[3],a or 1) end
local function rect(x,y,w,h,c,a) color(c,a); gfx.rect(sx(x),sy(y),w*scale,h*scale,1) end
local function line(x,y,xx,yy,c,a) color(c,a); gfx.line(sx(x),sy(y),sx(xx),sy(yy),1) end

local function font(size,kind,bold) BLT.font(size,kind,bold,scale,fonts) end
local function value_offset(text,kind,size) return valueMetrics:offset(kind==1,text,size,gfx.ext_retina or 1)end
local function label(text,x,y,w,h,size,c,bold,flags,kind,literal,optical)
  local shown=literal and tostring(text) or Language.message(text)
  font(size,kind,bold); color(c or C.text); gfx.x,gfx.y=sx(x),sy(y)
  if w then shown=BLT.ui.fit(shown,w*scale) end
  if optical then optical=optical(shown,kind,size)end
  gfx.drawstr(BLT.cleanText(shown),flags or 0,sx(x+w),sy(y+h),optical)
end

local function flash_field(key)
 local now=R.time_precise();fieldUI.now=now;fieldUI:flash(key)
 A.flash[key]=now+.9;wake_visuals()
end
local Chameleon
local Chrome={window=nil,mouseDown=false,drag=nil,resize=nil,mouseActive=false,requestClose=false,requestReset=false,
  chameleonPressed=false,titleH=26,windowTitle='BLT MINIMAL INFO PANEL',titleText='M I N I M A L   I N F O   P A N E L',
  minW=1070,minH=70,mint={0.38,0.88,0.72},ice={0.65,0.895,1.0},red={1.0,0.27,0.34},
  isWindows=R.GetOS():match("Win")~=nil,resizeEdge=6,resizeCornerBand=8,resizeCornerSpan=24,resizeTopLeftGuard=30,resizeTopRightGuard=110,
  tooltipHover=nil,tooltipSince=0,tooltipVisible=false,tooltipDelay=.70,
  cursorId={we=32644,ns=32645,nwse=32642,nesw=32643,arrow=32512}}
Chrome.font=Chrome.isWindows and "Segoe UI" or (BLT_MAC and "Helvetica Neue" or "sans-serif")
local function chameleon_notify(text)
  status(text,false)
end

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



Chameleon=BLTChameleon.new(R,C,{
 section=SECTION,
 store=BLT.store,
 notify=chameleon_notify,
 chrome=Chrome,roles={ice='accent2',disabled='faint'},
 changed=wake_visuals
})


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
  if ok then BLT.position(hwnd,l,t,W,H+Chrome.titleH,"","") end
  BLT.store(SECTION,"window_w",tostring(W),true)
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
  -- Upper corners are reserved for ordinary title-bar use. In particular the
  -- close/reset controls must remain clickable right up to the window edge.
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

local fields={{key='name',label='名前'}, {key='length',label='長さ',width=130},
 {key='volume',label='ボリューム',width=93},{key='pitch',label='ピッチ',width=88},{key='rate',label='再生速度',width=180},{key='pan',label='PAN',width=93},
 {key='reverse',label='逆再生',width=36,check=true},{key='mute',label='ミュート',width=36,check=true},{key='lock',label='ロック',width=36,check=true}}

-- REAPER's projpeaksgain is a linear display multiplier, not item audio gain.
-- Keep this view control outside item snapshots, presets, and project Undo edits.
local PeakZoom={key='projpeaksgain',min=0,max=36.1,width=90,gap=18,nextPoll=0}
PeakZoom.modes={
 {42301,'通常の波形','Normal peaks'},
 {42073,'スペクトル波形','Spectral peaks'},
 {43145,'ラウドネス波形（LUFS-M）','Loudness peaks (LUFS-M)'},
 {43147,'ラウドネス波形（LUFS-S）','Loudness peaks (LUFS-S)'},
 {43146,'ラウドネスグラフ（LUFS-M）','Loudness graph (LUFS-M)'},
 {43148,'ラウドネスグラフ（LUFS-S）','Loudness graph (LUFS-S)'},
 {42294,'スペクトログラム','Spectrogram'},
 {42295,'通常の波形 ＋ スペクトログラム','Normal peaks + spectrogram'},
 {43207,'スペクトル波形 ＋ ラウドネスグラフ（LUFS-M）','Spectral peaks + loudness graph (LUFS-M)'},
 {43208,'スペクトル波形 ＋ ラウドネスグラフ（LUFS-S）','Spectral peaks + loudness graph (LUFS-S)'},
 {43209,'スペクトル波形 ＋ スペクトログラム','Spectral peaks + spectrogram'},
}
function PeakZoom.menu()
 WheelUndo.finish();PeakZoom.drag=nil
 local project=R.EnumProjects(-1,'');local names,commands={},{}
 for _,mode in ipairs(PeakZoom.modes)do
  local state=R.GetToggleCommandStateEx(0,mode[1])
  if state>=0 then
   names[#names+1]=(state==1 and '!'or '')..mode[Language.code=='JP' and 2 or 3]
   commands[#commands+1]=mode[1]
  end
 end
 if #commands==0 then return end
 gfx.x=gfx.mouse_x;gfx.y=gfx.mouse_y
 local command=commands[gfx.showmenu(table.concat(names,'|'))]
 if command and project==R.EnumProjects(-1,'') and R.GetToggleCommandStateEx(0,command)~=1 then
  R.Main_OnCommand(command,0);R.UpdateArrange()
 end
 PeakZoom.poll(true);wake_visuals()
end
function PeakZoom.supported()
 return (type(R.SNM_GetDoubleConfigVarEx)=='function' or type(R.SNM_GetDoubleConfigVar)=='function')
    and (type(R.SNM_SetDoubleConfigVarEx)=='function' or type(R.SNM_SetDoubleConfigVar)=='function')
end
function PeakZoom.read(project)
 if not PeakZoom.supported() then return nil,'ピーク表示の調整にはSWS Extensionが必要です。' end
 if project~=R.EnumProjects(-1,'') then return nil,'プロジェクトが切り替わったため、ピーク表示の操作を終了しました。' end
 local ok,gain
 if type(R.SNM_GetDoubleConfigVarEx)=='function' then ok,gain=pcall(R.SNM_GetDoubleConfigVarEx,project,PeakZoom.key,-1)
 else ok,gain=pcall(R.SNM_GetDoubleConfigVar,PeakZoom.key,-1) end
 if not ok or not finite(gain) or gain<=0 then return nil,'ピーク表示の設定を取得できません。' end
 return gain
end
function PeakZoom.write(project,gain)
 if project~=R.EnumProjects(-1,'') then return false end
 local ok,result
 if type(R.SNM_SetDoubleConfigVarEx)=='function' then ok,result=pcall(R.SNM_SetDoubleConfigVarEx,project,PeakZoom.key,gain)
 elseif type(R.SNM_SetDoubleConfigVar)=='function' then ok,result=pcall(R.SNM_SetDoubleConfigVar,PeakZoom.key,gain)
 else return false end
 return ok and result==true
end
function PeakZoom.poll(force,project,now)
 now=now or R.time_precise();project=project or R.EnumProjects(-1,'')
 local switched=project~=PeakZoom.project
 if not force and not switched and now<PeakZoom.nextPoll then return end
 PeakZoom.nextPoll=now+.15
 if switched then PeakZoom.drag=nil end
 local gain,problem=PeakZoom.read(project)
 if switched or gain~=PeakZoom.gain or problem~=PeakZoom.problem then
  PeakZoom.project=project;PeakZoom.gain=gain;PeakZoom.problem=problem;PeakZoom.available=gain~=nil
  PeakZoom.db=gain and 20*math.log(gain,10) or nil
  PeakZoom.text=PeakZoom.db and string.format('%.1f dB',abs(PeakZoom.db)<.05 and 0 or PeakZoom.db) or '—'
  wake_visuals()
 end
end
function PeakZoom.set(value,project)
 if not finite(value) then return nil,'数値が不正です。' end
 project=project or R.EnumProjects(-1,'')
 -- Finalize the preceding item-wheel edit before touching a different control.
 WheelUndo.finish()
 local old,err=PeakZoom.read(project);if not old then PeakZoom.poll(true);return nil,err end
 local db=floor(clamp(value,PeakZoom.min,PeakZoom.max)*10+.5)/10
 local gain=10^(db/20)
 if abs(old-gain)<=1e-12*max(1,gain) then PeakZoom.poll(true);return true end
 if not PeakZoom.write(project,gain) then PeakZoom.poll(true);return nil,'ピーク表示の設定を変更できません。' end
 local actual=PeakZoom.read(project)
 if not actual or abs(20*math.log(actual,10)-db)>1e-5 then
  -- Restore this display preference only; never touch item/take volume or history.
  PeakZoom.write(project,old);R.UpdateArrange();PeakZoom.poll(true)
  return nil,'ピーク表示の設定を変更できません。'
 end
 R.UpdateArrange();PeakZoom.poll(true)
 return true
end
function PeakZoom.apply(value,project)
 local ok,err=PeakZoom.set(value,project)
 if not ok then PeakZoom.drag=nil;flash_field('peak_zoom');status(err,true) end
 return ok
end
function PeakZoom.at(x,y)
 return PeakZoom.x and x>=PeakZoom.x and x<PeakZoom.x+PeakZoom.w and y>=PeakZoom.y and y<=PeakZoom.y+39
end
function PeakZoom.fraction()
 return clamp((PeakZoom.db or 0)/PeakZoom.max,0,1)
end
function PeakZoom.value_at(x)
 return clamp((x-PeakZoom.railX)/PeakZoom.railW,0,1)*PeakZoom.max
end
function PeakZoom.capture(cap,down)
 local d=PeakZoom.drag;if not d then return false end
 local flags=gfx.getchar(65536);local focused=(flags&1)==0 or (flags&2)~=0
 if d.project~=R.EnumProjects(-1,'') or d.x~=PeakZoom.x or d.w~=PeakZoom.w or d.y~=PeakZoom.y
    or not focused or BLT.presets.open or E then
  PeakZoom.drag=nil;wake_visuals();return true
 end
 if not down then PeakZoom.drag=nil;wake_visuals();return true end
 if gfx.mouse_x~=d.mouse then
  if (cap&8)~=0 then
   d.value=clamp(d.value+(gfx.mouse_x-d.mouse)*PeakZoom.max/PeakZoom.railW*.1,PeakZoom.min,PeakZoom.max)
  else d.value=PeakZoom.value_at(gfx.mouse_x) end
  d.mouse=gfx.mouse_x;PeakZoom.apply(d.value,d.project)
 end
 return true
end
function PeakZoom.input(cap,down,right)
 if gesture or not PeakZoom.at(gfx.mouse_x,gfx.mouse_y) then return false end
 if right and not A.rightLast then PeakZoom.menu();return true end
 local wheel=gfx.mouse_wheel or 0
 if (down and not downLast) or wheel~=0 then
  WheelUndo.finish();PeakZoom.poll(true)
  if not PeakZoom.available then status(PeakZoom.problem,true);wake_visuals();return true end
 end
 if down and not downLast then
  if (cap&4)~=0 then PeakZoom.apply(0,PeakZoom.project)
  elseif gfx.mouse_y>=PeakZoom.y+24 then
   local value=clamp(PeakZoom.db,PeakZoom.min,PeakZoom.max)
   if (cap&8)==0 then
    value=PeakZoom.value_at(gfx.mouse_x)
    if not PeakZoom.apply(value,PeakZoom.project) then return true end
   end
   PeakZoom.drag={project=PeakZoom.project,mouse=gfx.mouse_x,value=value,x=PeakZoom.x,y=PeakZoom.y,w=PeakZoom.w}
   wake_visuals()
  end
 elseif wheel~=0 and not down then
  if (gfx.getchar(65536)&2)==0 and R.JS_Mouse_GetState then
   local ok,state=pcall(R.JS_Mouse_GetState,8)
   if ok and type(state)=='number' then cap=(cap&(~8))|(floor(state)&8) end
  end
  local ticks=max(1,floor(abs(wheel)/120+.5))*(wheel>0 and 1 or -1)
  PeakZoom.apply((PeakZoom.db or 0)+ticks*((cap&8)~=0 and .1 or 1),PeakZoom.project)
 end
 return true
end

local function poll(force)
 local now=R.time_precise();local project=R.EnumProjects(-1,'')
 PeakZoom.poll(force,project,now)
 if not force and (now<A.nextPoll or E or gesture) then return end
 A.nextPoll=now+.15
 local rev=R.GetProjectStateChangeCount(project)
 local count=R.CountSelectedMediaItems(project);local ids=A.selection
 local changed=force or project~=A.project or rev~=A.revision or count~=#ids
 for i=1,count do
  local item=R.GetSelectedMediaItem(project,i-1)
  if ids[i]~=item then changed=true;ids[i]=item end
 end
 for i=#ids,count+1,-1 do ids[i]=nil end
 if changed then
  local rows,n,mixed,midi=Core.display(project,ids)
  local previous=A.items[1];local first=rows[1]
  local dirty=force or n~=A.count or midi~=A.hasMidi or not A.display
   or (previous and previous.name=='')~=(first and first.name=='')
  for _,key in ipairs({'mute','lock','reverse'}) do if mixed[key]~=(A.mixed and A.mixed[key]) then dirty=true end end
  A.items,A.count,A.mixed,A.hasMidi=rows,n,mixed,midi;A.project=project;A.revision=rev
  A.display=A.display or {}
  for _,f in ipairs(fields) do
   local shown=(f.key=='length' and first) and length_text(first.length,first.pos) or Core.format(f.key,first and first[f.key])
   if A.display[f.key]~=shown then dirty=true;A.display[f.key]=shown end
  end
  if dirty then wake_visuals() end
 elseif (lengthMode==-1 or lengthMode==6) and A.items[1] then
  local first=A.items[1];local shown=length_text(first.length,first.pos)
  if A.display.length~=shown then A.display.length=shown;wake_visuals() end
 end
end
local function fail(key,message)
 flash_field(key);status(message,true)
end
local function apply_value(snapshot,key,value,absolute)
 local revision=R.GetProjectStateChangeCount(snapshot.project)
 WheelUndo.finish()
 if snapshot.revision==revision then snapshot.revision=R.GetProjectStateChangeCount(snapshot.project) end
 if key=='reverse' and not Media.ready(true) then fail(key,'音声がオンラインになるまでお待ちください。');return false end
 local n,err=Core.apply(snapshot,key,value,absolute)
 if not n then fail(key,err);return false end
 poll(true);wake_visuals();return true
end
local function preview_length(g,absolute)
 local s=g.snapshot;local live=g.live
 local ok,err=Core.check(s)
 if ok and live and WheelUndo.history_changed(live)then ok=false;err='編集中に対象が変更されました。もう一度操作してください。'end
 if not ok then return nil,err end
 local plan;plan,err=Core.plan(s,'length',g.value,absolute)
 if not plan then return nil,err end
 local targets,changes={},{}
 for _,c in ipairs(plan)do targets[c.row]=c.after end
 for i,v in ipairs(s.rows)do
  local before=live and live.after[i].length or v.length
  local after=targets[v]or v.length
  if after~=before then changes[#changes+1]={row=v,before=before,after=after}end
 end
 if #changes==0 then return 0 end
 if not live then
  live={project=s.project,key='length',before=s,after={},revision=s.revision,
   undo=R.Undo_CanUndo2(s.project),redo=R.Undo_CanRedo2(s.project)}
  for i,v in ipairs(s.rows)do live.after[i]={item=v.item,length=v.length}end
  g.live=live
 end
 local n;n,err=Core.commit(s,'length',changes,true)
 if n then for i,v in ipairs(s.rows)do live.after[i].length=targets[v]or v.length end end
 s.revision=R.GetProjectStateChangeCount(s.project);live.revision=s.revision
 return n,err
end
local function finish_gesture(cancel)
 local g=gesture;if not g then return end
 if g.live then
  if cancel then
   g.value=g.start
   local n,err=preview_length(g,false)
   if not n then fail(g.key,err)end
  end
  WheelUndo.commit(g.live)
 end
 gesture=nil
 if g.live then poll(true)end
 wake_visuals()
end
local function finish_edit(cancel,absolute)
 if not E then return true end
 local e=E;E=nil;IME.active=false;IME.ctx=nil;IME.font=nil
 if cancel then wake_visuals();return true end
 local value,err
 if e.key=='length' then
  if lengthMode==6 then local n=tonumber(e.text);if finite(n) then value=n/frame_rate() end
  elseif e.text:match('^[%d%s:%.%+%-%[%]%(%)|/]+$') then value=R.parse_timestr_len(e.text,e.snapshot.rows[1].pos,lengthMode) end
  if not finite(value) or value<Core.specs.length.lo or value>Core.specs.length.hi then value=nil;err='数値が範囲外です。元の値を保持しました。' end
 else value,err=Core.parse(e.key,e.text) end
 if value==nil then fail(e.key,err);return false end
 return apply_value(e.snapshot,e.key,value,absolute==true)
end
local Dock={state=0}
local function row_y() return (Dock.state&1)~=0 and 0 or 28 end
local function value_bounds(f) return f.x+7,row_y()+13,f.w-14,26 end
local function open_edit(f)
 WheelUndo.finish()
 local snapshot=Core.snapshot();local first=snapshot.rows[1]
 if not first or first[f.key]==nil then fail(f.key,'この項目は選択アイテムでは編集できません。');return end
 local value=first[f.key]
 if Core.specs[f.key] then value=Core.control_value(f.key,value) end
 if f.key=='length' then value=length_text(value,first.pos) end
 local x,y,w,h=value_bounds(f)
 local reference=f.key=='name'and(value~=''and value or Language.text('（名前なし）'))or
  (f.key=='length'and tostring(value)or Core.format(f.key,first[f.key]))
 font(16,f.key=='name'and 1 or 3,false);reference=BLT.ui.fit(reference,w)
 E={key=f.key,text=tostring(value),reference=reference,snapshot=snapshot,bounds={x=x,y=y,w=w,h=h},absolute=false}
 local ok,err=pcall(function()
  IME.api,IME.ctx,IME.font=gfx.inputContext(fonts[f.key=='name'and 1 or 3])
  IME.active=true;IME.frames=0
 end)
 if not ok then finish_edit(true);fail(f.key,tostring(err)) end
 wake_visuals()
end
local function rgba(c,a) return (floor(c[1]*255+.5)<<24)|(floor(c[2]*255+.5)<<16)|(floor(c[3]*255+.5)<<8)|floor((a or 1)*255+.5) end
local function ime_frame()
 if not E or not IME.active then return end
 local I,ctx,b=IME.api,IME.ctx,E.bounds
 local _,_,_,originX,originY=gfx.inputContext()
 local focus=IME.frames==0
 I.PushStyleVar(ctx,I.StyleVar_FramePadding,0,0)
 I.PushStyleVar(ctx,I.StyleVar_FrameRounding,0);I.PushStyleVar(ctx,I.StyleVar_FrameBorderSize,0)
 I.PushStyleColor(ctx,I.Col_FrameBg,rgba(C.field));I.PushStyleColor(ctx,I.Col_Text,rgba((A.count or 0)>1 and C.warn or C.text))
 I.PushFont(ctx,IME.font,16)
 local dpi=gfx.ext_retina or 1
 local offset=valueMetrics:offset(E.key=='name',E.reference,16,dpi)
 local y=originY+b.y+max(0,(b.h-I.GetTextLineHeight(ctx))*.5)+offset
 I.SetCursorScreenPos(ctx,originX+b.x,floor(y*dpi+.5)/dpi)
 I.SetNextItemWidth(ctx,b.w);if focus then I.SetKeyboardFocusHere(ctx)end
 local _,text=I.InputText(ctx,'##item_strip_'..E.key,E.text,I.InputTextFlags_AutoSelectAll)
 E.text=text
 local mods=I.GetKeyMods(ctx);E.absolute=(mods&I.Mod_Ctrl)~=0 or ((gfx.mouse_cap or 0)&4)~=0 or (BLT_MAC and (mods&I.Mod_Super)~=0)
 local cancel=I.IsKeyPressed(ctx,I.Key_Escape,false)
 local done=I.IsItemDeactivated(ctx)or I.IsKeyPressed(ctx,I.Key_Enter,false)or I.IsKeyPressed(ctx,I.Key_KeypadEnter,false)
 local focused=I.IsWindowFocused(ctx)
 I.PopFont(ctx);I.PopStyleColor(ctx,2);I.PopStyleVar(ctx,3)
 IME.frames=IME.frames+1
 if cancel then finish_edit(true)
 elseif IME.frames>1 and(done or not focused)then local absolute=E.absolute;finish_edit(false,absolute)end
end

local layoutWidth=nil
local function layout()
 local isDocked=(Dock.state&1)~=0
 local b=isDocked and BLT.ui.bar(gfx.w)
 local signature=table.concat({gfx.w,isDocked and 1 or 0,b and b.titleEnd or 0,Dock.left or 0,Dock.right or 1},':')
 if layoutWidth==signature then return end
 layoutWidth=signature
 local fixed=(#fields-1)*6+PeakZoom.width+PeakZoom.gap
 for _,f in ipairs(fields) do fixed=fixed+(f.width or 0) end
 local left,right=0,gfx.w
 if isDocked then
  local origin=b.titleEnd;local width=max(1,b.presetX-origin);local minimum=min(width,fixed+80+24)
  Dock.areaLeft,Dock.areaWidth=origin,width
  local l=clamp(Dock.left or 0,0,1)*width;local r=clamp(Dock.right or 1,0,1)*width
  local span=clamp(r-l,minimum,width)
  left=origin+clamp((l+r-span)/2,0,width-span);right=left+span
  Dock.pixelLeft,Dock.pixelRight,Dock.minSpan=left,right,minimum
 end
 local content=max(1,right-left-24)
 local fit=min(1,content/(fixed+80))
 local x=left+12
 for _,f in ipairs(fields) do
  f.x=x;f.w=f.width and f.width*fit or max(80*fit,content-fixed*fit)
  x=x+f.w+6*fit
 end
 PeakZoom.x=x+(PeakZoom.gap-6)*fit;PeakZoom.w=PeakZoom.width*fit;PeakZoom.y=row_y()
 PeakZoom.separator=PeakZoom.x-PeakZoom.gap*fit/2
 local inset=min(10,PeakZoom.w*.08)
 PeakZoom.railX=PeakZoom.x+inset;PeakZoom.railW=max(1,PeakZoom.w-inset*2)
end
local function bar_at(x,y)
 if (Dock.state&1)==0 or y<0 or y>39 then return nil end
 layout()
 if x>=Dock.pixelLeft and x<Dock.pixelLeft+10 then return 'left' end
 if x>Dock.pixelRight-10 and x<=Dock.pixelRight then return 'right' end
end
local function draw_bars()
 if (Dock.state&1)==0 then return end
 local hot=bar_at(gfx.mouse_x,gfx.mouse_y)
 for _,side in ipairs({'left','right'}) do
  local x=side=='left' and Dock.pixelLeft+3 or Dock.pixelRight-6
  local active=hot==side or Dock.barDrag and Dock.barDrag.side==side
  rect(x,3,3,33,active and C.accent2 or C.edge2,active and .95 or .65)
  if active then rect(x-2,1,7,37,C.accent2,.1) end
 end
end
local function bar_input(down)
 if (Dock.state&1)==0 then Dock.barDrag=nil;return false end
 local hit=bar_at(gfx.mouse_x,gfx.mouse_y)
 if hit and not gesture and not PeakZoom.drag then set_resize_cursor('l') end
 if down and not downLast and hit and not gesture and not PeakZoom.drag then
  if E and not finish_edit(false,E.absolute) then downLast=down;return true end
  Dock.barDrag={side=hit,x=gfx.mouse_x,left=Dock.pixelLeft,right=Dock.pixelRight,width=Dock.areaWidth,origin=Dock.areaLeft}
 end
 local d=Dock.barDrag
 if not d then return false end
 local width=Dock.areaWidth
 if width~=d.width or Dock.areaLeft~=d.origin then
  Dock.barDrag=nil;downLast=down;layoutWidth=nil;wake_visuals();return true
 end
 local l,r=d.left,d.right;local dx=gfx.mouse_x-d.x
 if d.side=='left' then l=clamp(l+dx,d.origin,r-Dock.minSpan)
 else r=clamp(r+dx,l+Dock.minSpan,d.origin+width) end
 Dock.left,Dock.right=(l-d.origin)/width,(r-d.origin)/width;layoutWidth=nil;layout();wake_visuals()
 gfx.mouse_wheel=0;downLast=down
 if not down then
  Dock.barDrag=nil
  BLT.store(SECTION,'dock_row_left',tostring(Dock.left),true)
  BLT.store(SECTION,'dock_row_right',tostring(Dock.right),true)
 end
 return true
end
local function field_at(x,y)
 local top=row_y()
 if y<top or y>top+39 then return nil end
 for _,f in ipairs(fields) do if f.x and f.w and x>=f.x and x<f.x+f.w then return f end end
end
function PeakZoom.draw()
 local x,y,w=PeakZoom.x,PeakZoom.y,PeakZoom.w
 local enabled=PeakZoom.available;local hot=PeakZoom.at(gfx.mouse_x,gfx.mouse_y) and not E and not BLT.blocked() and not Chrome.mouseActive
 if enabled then gfx.wheelRegion(x,y,w,39)end
 local active=hot or PeakZoom.drag~=nil
 local tint=enabled and C.green or C.faint
 line(PeakZoom.separator,y+3,PeakZoom.separator,y+36,C.edge2,.52)
 fieldUI:fieldFrame('peak_zoom',x/density,y/density,w/density,39/density,enabled,active)
 -- Separate text rows retain the full label without widening this view control.
 local size=w>=87 and 9 or 8;local pad=min(3,w*.02);local textW=max(1,w-pad*2)
 label('ピーク表示ズーム率',x+pad,y+1,textW,12,size,tint,true,0)
 label(PeakZoom.text or '—',x+pad,y+12,textW,12,w>=80 and 10 or 9,enabled and C.text or C.faint,false,6,3,true)
 local rx,rw=PeakZoom.railX,PeakZoom.railW;local cy=y+31
 rect(rx,cy-2,rw,4,C.bg,1)
 local f=PeakZoom.fraction()
 if enabled and f>0 then rect(rx,cy-2,rw*f,4,tint,active and .90 or .68) end
 line(rx,cy+3,rx+rw,cy+3,C.edge,.40)
 for i=0,6 do local tx=rx+rw*i/6;line(tx,cy+5,tx,cy+7,C.edge2,.34) end
 local thumb=rx+rw*f
 if active and enabled then rect(thumb-5,cy-8,10,16,C.hover,.12) end
 rect(thumb-3,cy-6,6,12,enabled and (active and C.accent2 or tint) or C.faint,.95)
 line(thumb,cy-4,thumb,cy+4,C.bg,.55)
end
local function draw()
 gfx.beginDraw()
 if gfx.w<1 or gfx.h<1 then rect(0,0,1,1,C.bg);redraw_dirty=true;return end
 fieldUI.now=R.time_precise();fieldUI.frameSerial=fieldUI.frameSerial+1
 scale,ox,oy=1,0,0;mx,my=gfx.mouse_x,gfx.mouse_y;layout()
 rect(0,0,gfx.w,gfx.h,C.bg)
 local top=row_y()
 local first=A.items[1]
 for _,f in ipairs(fields) do
  local value=first and first[f.key];local disabled=f.key=='reverse' and A.hasMidi
  local enabled=value~=nil and not disabled
  if enabled and Core.specs[f.key]then gfx.wheelRegion(f.x,top,f.w,39)end
  local hot=not disabled and mx>=f.x and mx<f.x+f.w and my>=top and my<=top+39
  local on=not disabled and f.check and value==true
  local mixed=not disabled and f.check and A.mixed and A.mixed[f.key]
  local multi=(A.count or 0)>1
  fieldUI:fieldFrame(f.key,f.x/density,top/density,f.w/density,39/density,enabled,on or hot or E and E.key==f.key)
  label(f.label,f.x+(f.check and 2 or 7),top+1,f.w-(f.check and 4 or 14),12,(f.check and 7 or 9),disabled and C.disabled or enabled and (multi and C.warn or C.muted) or C.faint,true)
  if f.check then
   local cx=f.x+(f.w-16)/2
   rect(cx,top+18,16,16,disabled and C.field or on and not mixed and C.accent2 or C.bg)
   color(disabled and C.disabled or mixed and C.warn or (on and C.accent2 or C.edge2));gfx.rect(cx,top+18,16,16,0)
   local icon=f.key=='reverse' and 'R' or f.key=='mute' and 'M' or 'L'
   if mixed then rect(cx+3,top+25,10,2,C.warn)
   elseif on then label(icon,cx,top+18,16,16,12,not enabled and C.faint or C.bg,true,5,2,true) end
  else
   local shown=A.display and A.display[f.key] or '—'
   if f.key=='name' and value=='' then shown=Language.text('（名前なし）') end
   if gesture and gesture.key==f.key and gesture.moved then shown=f.key=='length' and length_text(gesture.value,first.pos) or Core.format(f.key,gesture.value) end
   local x,y,w,h=value_bounds(f)
   label(shown,x,y,w,h,16,enabled and (multi and C.warn or C.text) or C.faint,false,4,f.key=='name' and 1 or 3,true,value_offset)
  end
 end
 PeakZoom.draw()
 draw_bars()
 BLT.bar()
end
local function interact()
 WheelUndo.poll(R.time_precise())
 local cap=gfx.mouse_cap or 0;local down=(cap&1)~=0;local right=(cap&2)~=0
 if PeakZoom.capture(cap,down) then downLast=down;A.rightLast=right;gfx.mouse_wheel=0;return end
 if not BLT.blocked() and not Chrome.mouseActive and bar_input(down) then A.rightLast=right;return end
 if E then downLast=down;A.rightLast=right;gfx.mouse_wheel=0;return end
 if BLT.blocked() or Chrome.mouseActive then
  if gesture then finish_gesture(true)end
  downLast=down;A.rightLast=right;gfx.mouse_wheel=0;return
 end
 if PeakZoom.input(cap,down,right) then downLast=down;A.rightLast=right;gfx.mouse_wheel=0;return end
 local f=field_at(gfx.mouse_x,gfx.mouse_y)
 if right and not A.rightLast and f and Core.specs[f.key] then
  if f.key=='length' then
   local modes={3,0,4,5,6,2,-1};local names=Language.code=='JP' and {'秒','分秒','サンプル','時:分:秒:フレーム','フレーム','小節.拍','ルーラーと連動'} or {'Seconds','Time','Samples','Timecode (h:m:s:f)','Frames','Measures.beats','Follow ruler'}
   for i,m in ipairs(modes) do if m==lengthMode then names[i]='!'..names[i] end end
   gfx.x=gfx.mouse_x;gfx.y=gfx.mouse_y
   local choice=gfx.showmenu(table.concat(names,'|'))
   if modes[choice] then lengthMode=modes[choice];save_settings();poll(true)
   end
   gfx.mouse_wheel=0;A.rightLast=true;downLast=false;return
  end
 end
 A.rightLast=right
 if down and not downLast and f and not (f.key=='reverse' and A.hasMidi) then
  local snap=Core.snapshot();local first=snap.rows[1]
  if first and first[f.key]~=nil then
   gesture={key=f.key,field=f,snapshot=snap,start=first[f.key],value=first[f.key],x=gfx.mouse_x,y=gfx.mouse_y,moved=false,reset=(cap&4)~=0}
  elseif f.key=='reverse' and not R.BR_GetMediaSourceProperties then fail(f.key,'逆再生の切り替えにはSWS Extensionが必要です。') end
 elseif down and gesture and Core.specs[gesture.key] then
  local dy=gesture.y-gfx.mouse_y;local dx=gfx.mouse_x-gesture.x
  if abs(dx)+abs(dy)>3 then gesture.moved=true end
  if gesture.moved then
   local delta=abs(dx)>abs(dy) and dx or dy
   local ticks=(delta<0 and -1 or 1)*floor(abs(delta)/4)
   local value=Core.adjust_value(gesture.key,gesture.snapshot.rows[1],ticks,(cap&8)~=0)
   local absolute=(cap&4)~=0
   if value~=gesture.value or gesture.absolute~=absolute then
    gesture.value=value;gesture.absolute=absolute
    if gesture.key=='length'then
     local n,err=preview_length(gesture,absolute)
     if not n then finish_gesture(false);fail('length',err)end
    end
    wake_visuals()
   end
  end
 elseif not down and downLast and gesture then
  local g=gesture
  if g.moved and g.key=='length'then
   local n,err=preview_length(g,(cap&4)~=0)
   finish_gesture(false);if not n then fail('length',err)end
  elseif g.moved then gesture=nil;apply_value(g.snapshot,g.key,g.value,(cap&4)~=0)
  elseif f and f.key==g.key then
   gesture=nil
   if (g.reset or (cap&4)~=0) and (g.key=='volume' or g.key=='pitch' or g.key=='pan' or g.key=='rate') then
    apply_value(g.snapshot,g.key,g.key=='rate' and 1 or 0,true)
   elseif f.check then apply_value(g.snapshot,g.key,not g.start,true) else open_edit(f) end
  else gesture=nil end
 end
 downLast=down
 local wheel=gfx.mouse_wheel or 0
 if wheel~=0 then
  if (gfx.getchar(65536)&2)==0 and R.JS_Mouse_GetState then
   local ok,state=pcall(R.JS_Mouse_GetState,8)
   if ok and type(state)=='number' then cap=(cap&(~8))|(math.floor(state)&8) end
  end
  if f and Core.specs[f.key] and not gesture then
   local ticks=max(1,floor(abs(wheel)/120+.5))*(wheel>0 and 1 or -1)
   local n,err=WheelUndo.apply(f.key,ticks,(cap&8)~=0,(cap&4)~=0)
   if not n then fail(f.key,err) else poll(true);wake_visuals() end
  end
  gfx.mouse_wheel=0
 end
end
local function initial_dock_state()
 local saved=extnum('dock_state',-1)
 if saved>=0 then return math.floor(clamp(saved,0,3841))&0xF01,true end
 if R.DockGetPosition then
  for index=0,15 do
   if R.DockGetPosition(index)==2 then return index<<8 end
  end
 end
 return 0
end
local function docked() return (Dock.state&1)~=0 end
local function save_float()
 if gfx.w<1 or gfx.h<1 then return end
 local hwnd=gfx_window_handle()
 local ok,x,y,r,b=WindowGeometry.JS_Window_GetRect(hwnd)
 if ok then
  Dock.floating={x=x,y=y,w=r-x,h=A.menuHeight or b-y}
  for k,v in pairs(Dock.floating) do BLT.store(SECTION,'float_'..k,tostring(v),true) end
  local _,gx,gy,gw,gh=gfx.dock(-1,0,0,0,0)
  for k,v in pairs({x=gx,y=gy,w=gw,h=A.menuHeight or gh}) do
   if finite(v) then BLT.store(SECTION,'window_'..k,tostring(v),true) end
  end
 end
end
local function sync_dock()
 local actual=gfx.dock(-1)
 local state=(actual&1)~=0 and actual or(Dock.state&0xF00)
 if Dock.target~=nil then
  if state~=Dock.target or(gfx.getchar(65537)&4)==0 or gfx.w<1 or gfx.h<1 then
   local now=R.time_precise()
   if now>=(Dock.retryAt or 0)then gfx.dock(Dock.target);Dock.retryAt=now+.4 end
   return
  end
  Dock.target,Dock.retryAt=nil,nil
  if state==Dock.state then wake_visuals()end
 elseif(Dock.state&1)~=0 and(state&1)==0 then
  if(gfx.getchar(65537)&4)==0 then Dock.undocked=nil;return end
  Dock.undocked=(Dock.undocked or 0)+1
  if Dock.undocked<2 then return end
 end
 Dock.undocked=nil
 if state~=Dock.state then
  local was=docked();Dock.state=state;Dock.saved=true;Dock.barDrag=nil;PeakZoom.drag=nil;layoutWidth=nil
  BLT.store(SECTION,'dock_state',state,true)
  Chrome.drag=nil;Chrome.resize=nil;Chrome.window=nil;BLT.lastRect=nil
  if was and not docked() then
   local f=Dock.floating
   if f then BLT.lastRect=nil;BLT.position(gfx_window_handle(),f.x,f.y,f.w,f.h,'','') end
  end
  wake_visuals()
 end
 if gfx.w>=1 and gfx.h>=1 and(Dock.w~=gfx.w or Dock.h~=gfx.h)then if E then finish_edit(false,E.absolute) end;Dock.w,Dock.h=gfx.w,gfx.h;wake_visuals() end
end
local function toggle_dock()
 if Dock.target~=nil then return end
 if not Dock.saved and not docked()then Dock.state=initial_dock_state()end
 WheelUndo.finish()
 if E and not finish_edit(false,E.absolute) then return end
 finish_gesture(false);Dock.barDrag=nil;PeakZoom.drag=nil
 if not docked() then save_float() end
 A.menuHeight=nil;BLT.presets.dismiss();set_resize_cursor(nil)
 Dock.saved=true;Dock.target=Dock.state~1;Dock.retryAt=R.time_precise()+.4
 BLT.store(SECTION,'dock_state',Dock.target,true);gfx.dock(Dock.target)
 sync_dock()
end
-- Shared BLT app restoration protocol. Each app owns one registry ID.
local BLTRestore={section='BLT_APP_RESTORE',id='BLT_MINIMAL_INFO_PANEL'}
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

local function close()
 BLTRestore.finish(R,A.manualClose or Chrome.requestClose)
 WheelUndo.finish()
 if A.closed then return end
 finish_gesture(false)
 PeakZoom.drag=nil
 finish_edit(true);gesture=nil;Dock.barDrag=nil;BLT.store(SECTION,'dock_row_left',tostring(Dock.left or 0),true);BLT.store(SECTION,'dock_row_right',tostring(Dock.right or 1),true);save_settings();titlebar_cleanup();clear_chrome_tooltip()
 BLT.store(SECTION,'dock_state',Dock.target or Dock.state,true)
 if not docked()and Dock.target==nil then save_float() end
 A.closed=true;valueMetrics:close();gfx.quit()
end
local function prepare_menu()
 WheelUndo.finish()
 if E and not finish_edit(false,E.absolute) then return false end
 if gfx.h<360 then
  local hwnd=gfx_window_handle();local ok,l,t=WindowGeometry.JS_Window_GetRect(hwnd)
  if ok then A.menuHeight=gfx.h;BLT.position(hwnd,l,t,gfx.w,360,'','') end
 end
 return true
end
local function restore_menu_size()
 if A.menuHeight and not BLT.presets.open and not BLT.presets.swallow then
  local h=A.menuHeight;A.menuHeight=nil
  local hwnd=gfx_window_handle();local ok,l,t=WindowGeometry.JS_Window_GetRect(hwnd)
  if ok then BLT.position(hwnd,l,t,gfx.w,h,'','') end
 end
end
local function tooltip(x,y)
 if bar_at(x,y) then return Language.code=='JP' and 'ドラッグ：項目の左右端を調整' or 'Drag to adjust the row edges' end
 if E then return nil end
 if PeakZoom.at(x,y) then return nil end
 local f=field_at(x,y);if not f then return nil end
 if f.key=='reverse' and A.hasMidi then return Language.code=='JP' and 'MIDIアイテムを含む選択では逆再生を変更できません。' or 'Reverse is unavailable when the selection includes MIDI.' end
 if f.check then return Language.code=='JP' and 'クリックで全選択を同じON / OFFに設定' or 'Click to set all selected items ON / OFF' end
 if f.key=='rate' then return Language.code=='JP' and '再生速度（半音換算） · ホイール: 次の1 st位置（Shift: 0.1 st） · Ctrl+クリック: 1.0\n半音換算は速度比の参考値です。ピッチ維持設定は保持し、アイテムの長さは速度に追従します。' or 'Playback rate · Wheel: next semitone (Shift: 0.1 st) · Ctrl (Cmd)+click: 1.0\nPitch preservation stays unchanged; item length follows the rate.' end
 if f.key=='length' then return Language.code=='JP' and '右クリック: 尺度を選択 · 入力も選択した尺度を使用' or 'Right-click: units · Input uses selected units' end
 if f.key=='name' then
  local name=A.items[1] and A.items[1].name or ''
  return name..'\n'..(Language.code=='JP' and 'クリックして入力 · 複数選択は同名に変更' or 'Click to type · Rename all selected takes')
 end
 return Language.code=='JP' and ('入力 / ホイール / ドラッグ · Shift: 1/10 · Ctrl: 絶対値 · Ctrl+クリック: 初期値')
  or ('Type / Wheel / Drag · Shift: 1/10 · Ctrl (Cmd): absolute · Ctrl (Cmd)+click: reset')
end
Media.state=A;Media.onchange=function() wake_visuals() end
BLT.attach({R=R,C=C,Chrome=Chrome,Chameleon=Chameleon,section=SECTION,faces=fonts,font=font,
 docked=docked,fold=function() Chrome.requestDock=true end,transition=function()return Dock.target~=nil end,geometry=function() return 1,0,0 end,active=function() local f=gfx.getchar(65536);return (f&1)==0 or (f&2)~=0 end,
 wake=function() wake_visuals();A.content_dirty=true end,defaults=Core.defaults,capture=function() return S end,
 valid=Core.valid_settings,apply=function(v) S=BLT.copy(v);lengthMode=S.lengthMode;save_settings();poll(true);wake_visuals() end,
 beforeKey=function(k) if k>0 then WheelUndo.finish() end end,
 undoBefore=function() WheelUndo.finish();finish_gesture(false);finish_edit(true)end,undoRefresh=function() poll(true) end,
 busy=function() return gesture~=nil or PeakZoom.drag~=nil end,commit=function() WheelUndo.finish();finish_gesture(false);return not E or finish_edit(false,E.absolute) end,
 cancelEdit=function() WheelUndo.finish();finish_gesture(true);finish_edit(true);PeakZoom.drag=nil end,editing=function() return E~=nil end,modal=function() return false end,
 handle=gfx_window_handle,resizeHit=chrome_resize_hit,cursor=set_resize_cursor,beginResize=begin_window_resize,resize=update_window_resize,prepareMenu=prepare_menu,tip=tooltip})
local function recover_input(err)
 BLT.cleanup(WheelUndo.finish);BLT.cleanup(finish_gesture,false);BLT.cleanup(finish_edit,true);gesture=nil;PeakZoom.drag=nil;Dock.barDrag=nil
 BLT.recoverInput(A,err);status(BLT.publicError(err),true)
end
local function overlay_frame()
 if gfx.w<1 or gfx.h<1 then return end
 ime_frame()
 if not IME.inputPending then return end
 IME.inputPending=nil;interact()
 if Chrome.requestDock then Chrome.requestDock=false;toggle_dock();wake_visuals()end
 if Chrome.requestReset then Chrome.requestReset=false;A.menuHeight=nil;reset_window_size();wake_visuals()end
 if Chrome.requestClose then A.manualClose=true;A.closing=true end
end
gfx.setOverlay(function()
 local ok,err=xpcall(overlay_frame,debug.traceback);if not ok then recover_input(err)end
end)
local function loop_body()
 WheelUndo.poll(R.time_precise())
 sync_dock();local now=R.time_precise();local drawable=gfx.w>=1 and gfx.h>=1
 if drawable then BLT.tick(now)end;Chameleon.tick(now)
 local k=gfx.getchar();if k<0 then A.manualClose=true end;if k<0 or A.closing then close();return false end
 local n=0
 while k>0 and n<32 do
  k=BLT.key(k)
  if k==27 then if PeakZoom.drag then PeakZoom.drag=nil;downLast=(gfx.mouse_cap&1)~=0;wake_visuals() elseif Dock.barDrag then Dock.left=(Dock.barDrag.left-Dock.barDrag.origin)/Dock.barDrag.width;Dock.right=(Dock.barDrag.right-Dock.barDrag.origin)/Dock.barDrag.width;Dock.barDrag=nil;layoutWidth=nil;wake_visuals() elseif E then finish_edit(true) elseif gesture then finish_gesture(true)else A.manualClose=true;A.closing=true end end
  k=gfx.getchar();n=n+1
 end
 poll(false)
 if not drawable then draw();gfx.update();return true end
 restore_menu_size()
 if (gfx.getchar(65537)&4)==0 then redraw_dirty=true;return true end
 local cap=gfx.mouse_cap or 0
 local x,y=gfx.mouse_x,gfx.mouse_y
 local inside=x>=0 and x<gfx.w and y>=0 and y<gfx.h
 local wasInside=last_raw_mouse_x and last_raw_mouse_x>=0 and last_raw_mouse_x<gfx.w and last_raw_mouse_y>=0 and last_raw_mouse_y<gfx.h
 local capture=gesture or PeakZoom.drag or Dock.barDrag or Chrome.drag or Chrome.resize or Chrome.mouseDown and Chrome.mouseActive
 local changed=(inside or wasInside) and (x~=last_raw_mouse_x or y~=last_raw_mouse_y or cap~=last_raw_mouse_cap or (gfx.mouse_wheel or 0)~=0)
 if not inside and not capture and not E and not BLT.presets.open then
  gfx.mouse_wheel=0;downLast=(cap&1)~=0;A.rightLast=(cap&2)~=0;Chrome.mouseDown=downLast
 end
 if changed or capture or E or BLT.presets.open then redraw_dirty=true end
 for key,t in pairs(A.flash) do redraw_dirty=true;if now>=t then A.flash[key]=nil end end
 if redraw_dirty or A.content_dirty then
  redraw_dirty=false;A.content_dirty=false
  draw();IME.inputPending=true;gfx.update()
 end
 last_raw_mouse_x,last_raw_mouse_y,last_raw_mouse_cap=gfx.mouse_x,gfx.mouse_y,cap
 return true
end
local function loop()
 if A.closing then BLT.cleanup(close);return end
 local ok,continue=xpcall(loop_body,debug.traceback)
 if not ok then recover_input(continue)end
 if not A.closed and (not ok or continue) then R.defer(loop) end
end
Dock.left=clamp(extnum('dock_row_left',0),0,1);Dock.right=clamp(extnum('dock_row_right',1),0,1)
if Dock.right<=Dock.left then Dock.left,Dock.right=0,1 end

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

BLTShortcuts.install(R,gfx,{
 blocked=function() return BLT.presets.open or (BLT.host and (BLT.host.editing() or BLT.host.modal() or BLT.host.busy())) or Dock.barDrag~=nil end,
 beforeGlobal=function(k) if BLT.host and BLT.host.beforeKey then BLT.host.beforeKey(k) end end,
 localKey=function(k,cap)
  return k==27 or ((cap&24)==0 and (k==26 or (cap&4)~=0 and (k==90 or k==122)))
 end
})

local ok,err=titlebar_api_ready()
if not ok then Language.mb(err,'BLT MINIMAL INFO PANEL',0);return end
gfx.ext_retina=1
local ww=clamp(extnum('window_w',W),Chrome.minW,4000);local wh=H+26
local wx,wy=extnum('window_x',0/0),extnum('window_y',0/0)
Dock.state,Dock.saved=initial_dock_state()
if docked()then Dock.target=Dock.state;Dock.retryAt=R.time_precise()+.4 end
local fx,fy=extnum('float_x',0/0),extnum('float_y',0/0)
if finite(fx) and finite(fy) then Dock.floating={x=fx,y=fy,w=clamp(extnum('float_w',ww),Chrome.minW,4000),h=clamp(extnum('float_h',wh),Chrome.minH,2000)} end
if finite(wx) and finite(wy) then gfx.init(Chrome.windowTitle,ww,wh,Dock.state,wx,wy) else gfx.init(Chrome.windowTitle,ww,wh,Dock.state) end
if not docked() and Dock.floating then local f=Dock.floating;BLT.lastRect=nil;BLT.position(gfx_window_handle(),f.x,f.y,f.w,f.h,'','') end
if Chameleon.enabled then Chameleon.refresh(true) end
poll(true)
R.atexit(function() BLT.cleanup(close) end)
if R.set_action_options then R.set_action_options(2)end
local restoreOK,restoreError=pcall(BLTRestore.start,R)
if not restoreOK then Language.mb('自動復元の登録に失敗しました。\n'..tostring(restoreError),'BLT MINIMAL INFO PANEL',0)end
loop()
