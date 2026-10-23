-- @description TRACK TREE
-- @version 0.3.13
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
 {section='BLT_TRACK_TREE',title='BLT TRACK TREE',width=648,height=700,minWidth=360,minHeight=300},AppShellText,AppChromeRaster,AppCanvasDraw)
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
local WindowGeometry=gfx.geometryAPI()
local BLT_MAC=(reaper.GetOS() or ''):match('OSX')~=nil or (reaper.GetOS() or ''):match('macOS')~=nil
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
 ["CHAMELEON  REAPERテーマに擬態"]="CHAMELEON  REAPER theme",
 ["CHAMELEON  オリジナル配色"]="CHAMELEON  Original colors",
 ["カスタムタイトルバーには js_ReaScriptAPI が必要です。\nReaPack から js_ReaScriptAPI をインストールしてください。"]="The app bar requires js_ReaScriptAPI.\nInstall js_ReaScriptAPI via ReaPack.",
 ["現在"]="Current",
 ["表示言語を切替（JP / EN）"]="Switch language (JP / EN)",
 ["名前"]="Name",
},prefixes={"プリセットを保存しました: ","プリセットを読み込みました: ","現在: "},patterns={
 {'^「(.*)」を上書きしますか？$','Overwrite "%s"?'},
 {'^(%d+)個インポートしました。$','Imported %d preset(s).'},
}}
local Language=create_language(reaper,"BLT_TRACK_TREE",LanguageCatalog)
local R=reaper
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
 local compact=inline
 local dpi=gfx.ext_retina or 1
 local c=B.barCache;if c and c.width==w and c.compact==compact and c.inline==inline and c.dpi==dpi then return c end
 local b={width=w,closeX=w-38,resetX=w-72,themeX=w-106}
 b.foldX=host.fold and b.themeX-34 or nil;b.languageX=(b.foldX or b.themeX)-26;b.nextX=b.languageX-20;b.prevX=b.nextX-20;b.presetX=b.prevX-84
 b.compact=compact;b.inline=inline;b.dpi=dpi
 if compact then
  b.resetX=b.closeX;b.themeX=w-72;b.foldX=w-106;b.languageX=w-132;b.nextX=w+500;b.prevX=w+500
  b.presetX=b.languageX -- Hidden presets; shared background starts at the visible controls.
  B.chromeFont();b.titleEnd=math.min(math.ceil(UI.textMetrics(Chrome.titleText))+28,math.max(0,b.languageX-8))
 end
 B.barCache=b;return b
end
function UI.barHit(x,y)
 local b=UI.bar(gfx.w)
 return y>=0 and y<26 and x>=0 and x<gfx.w and (not b.inline or x<b.titleEnd or x>=(b.compact and b.languageX or b.presetX))
end
local function gfx_window_handle() return host.handle() end
local function chrome_resize_hit(x,y) if host.docked()or(host.transition and host.transition())then return nil end;if y<26 and x>=UI.bar(gfx.w).presetX then return nil end;return host.resizeHit(x,y) end
local function set_resize_cursor(mode) host.cursor(mode) end
local function begin_window_resize(mode) host.beginResize(mode) end
local function update_window_resize() host.resize() end
local function clear_chrome_tooltip() if R.TrackCtl_SetToolTip then R.TrackCtl_SetToolTip('',0,0,true) end end
B.clearTooltip=clear_chrome_tooltip

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
  local inBar=(host.active() or (gfx.getchar(65536)&8)~=0) and not blocked and inWindow and UI.barHit(mx,my)
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
  p.collapsed=host.collapsed and host.collapsed() or false;p.docked=host.docked and host.docked() or false;p.dockButton=host.docked~=nil;p.compactLanguage=true
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
local function create_project_undo(api,context)
 local function message(jp,en,ok)
  if context.notice then context.notice(context.language()=='EN' and en or jp,ok) end
 end
 return function(key,modifiers)
  modifiers=modifiers or 0
  if (modifiers&24)~=0 or not (key==26 or ((modifiers&4)~=0 and (key==90 or key==122))) then return false end
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
function B.logError(err)
 local message=B.publicError(err)
 if message~=B.lastLoggedError then
  B.lastLoggedError=message
  if R.ShowConsoleMsg then pcall(R.ShowConsoleMsg,tostring(err)..'\n') end
 end
end

return B
end)()

local SECTION='BLT_TRACK_TREE'
local min,max,abs,floor=math.min,math.max,math.abs,math.floor
local function clamp(v,a,b)return max(a,min(b,v))end
local function finite(v)return type(v)=='number'and v==v and abs(v)<math.huge end
local Core={}
function Core.snapshot(api)
 local project=api.EnumProjects(-1,'');local rows,roots,stack,by={},{},{},{}
 for i=0,api.CountTracks(project)-1 do
  local ptr=api.GetTrack(project,i);local _,name=api.GetTrackName(ptr)
  local delta=api.GetMediaTrackInfo_Value(ptr,'I_FOLDERDEPTH')
  local row={ptr=ptr,id=api.GetTrackGUID(ptr),name=name,index=i,depth=#stack,children={},parent=stack[#stack],delta=delta,
   selected=api.IsTrackSelected(ptr),shown=api.GetMediaTrackInfo_Value(ptr,'B_SHOWINTCP')~=0,
   mixer=api.GetMediaTrackInfo_Value(ptr,'B_SHOWINMIXER')~=0,color=api.GetTrackColor(ptr),pinned=api.GetMediaTrackInfo_Value(ptr,'B_TCPPIN')~=0}
  rows[#rows+1]=row;by[row.id]=row
  local list=row.parent and row.parent.children or roots;list[#list+1]=row
  if delta>0 then stack[#stack+1]=row elseif delta<0 then for _=1,-delta do stack[#stack]=nil end end
 end
 local signature={};for _,r in ipairs(rows)do signature[#signature+1]=r.id..':'..r.delta end
 local ptr=api.GetMasterTrack(project);local flags=api.GetMasterTrackVisibility()
 local master={ptr=ptr,id='__MASTER__',name='MASTER',index=-1,depth=0,children={},delta=0,master=true,pinned=api.GetMediaTrackInfo_Value(ptr,'B_TCPPIN')~=0,
  selected=api.IsTrackSelected(ptr),shown=(flags&1)~=0,mixer=(flags&2)==0,color=api.GetTrackColor(ptr)}
 by[master.id]=master
 return {project=project,rows=rows,roots=roots,by=by,master=master,signature=table.concat(signature,'|')}
end
function Core.visible(tree,closed,query,match,related)
 local q=query:lower():match('^%s*(.-)%s*$')
 local function matches(row)
  if match then return match(row,q)end
  return row.name:lower():find(q,1,true)~=nil or row.master and ('マスター'):find(q,1,true)~=nil
 end
 local out={}
 if q==''or matches(tree.master)then out[1]=tree.master end
 if q~=''and not related then
  for _,row in ipairs(tree.rows)do if matches(row)then out[#out+1]=row end end
  return out
 end
 local included={}
 local function mark(row,above)
  local hit=above or matches(row);local child=false
  for _,v in ipairs(row.children)do if mark(v,hit)then child=true end end
  included[row.id]=hit or child;return included[row.id]
 end
 if q~=''then for _,row in ipairs(tree.roots)do mark(row,false)end end
 local function visit(row)
  if q~=''and not included[row.id]then return end
  out[#out+1]=row
  if q~=''or not closed[row.id]then for _,v in ipairs(row.children)do visit(v)end end
 end
 for _,row in ipairs(tree.roots)do visit(row)end
 return out
end
function Core.searchdata(api,row,items,fx)
 local data={items={},fx={}}
 if items and not row.master then
  for i=0,api.CountTrackMediaItems(row.ptr)-1 do
   local item=api.GetTrackMediaItem(row.ptr,i)
   for t=0,api.CountTakes(item)-1 do local take=api.GetTake(item,t);if take then data.items[#data.items+1]=(api.GetTakeName(take)or''):lower()end end
  end
 end
 if fx then
  local seen={}
  local function visit(index)
   if seen[index]then return end;seen[index]=true
   local ok,name=api.TrackFX_GetFXName(row.ptr,index,'');if ok then data.fx[#data.fx+1]=name:lower()end
   local yes,original=api.TrackFX_GetNamedConfigParm(row.ptr,index,'fx_name');if yes then data.fx[#data.fx+1]=original:lower()end
   local has,count=api.TrackFX_GetNamedConfigParm(row.ptr,index,'container_count')
   if has then for child=0,(tonumber(count)or 0)-1 do
    local found,address=api.TrackFX_GetNamedConfigParm(row.ptr,index,'container_item.'..child)
    if found and tonumber(address)then visit(tonumber(address))end
   end end
  end
  for i=0,api.TrackFX_GetCount(row.ptr)-1 do visit(i)end
 end
 return data
end
function Core.linkview(api,tree,rows,saved)
 if api.EnumProjects(-1,'')~=tree.project then return end
 for _,row in ipairs(tree.rows)do if not api.ValidatePtr2(tree.project,row.ptr,'MediaTrack*')then return end end
 if saved then
  for _,row in ipairs(tree.rows)do if not saved.tracks[row.id]then
   saved.tracks[row.id]={shown=row.shown,compact=api.GetMediaTrackInfo_Value(row.ptr,'I_FOLDERCOMPACT')}
  end end
 end
 local shown,expanded={},{};for _,row in ipairs(rows)do shown[row.id]=true;local parent=row.parent;while parent do expanded[parent.id]=true;parent=parent.parent end end
 local changes={}
 for _,row in ipairs(tree.rows)do
  local visible=shown[row.id]==true
  if row.shown~=visible then changes[#changes+1]={row=row,key='B_SHOWINTCP',value=visible and 1 or 0}end
  if #row.children>0 then
   local before=saved and saved.tracks[row.id]
   local compact=expanded[row.id]and 0 or(before and before.compact)
   if compact~=nil and api.GetMediaTrackInfo_Value(row.ptr,'I_FOLDERCOMPACT')~=compact then
    changes[#changes+1]={row=row,key='I_FOLDERCOMPACT',value=compact}
   end
  end
 end
 local master=shown[tree.master.id]==true
 if #changes==0 and master==tree.master.shown then return end
 api.PreventUIRefresh(1)
 local ok,err=xpcall(function()
  for _,change in ipairs(changes)do
   assert(api.SetMediaTrackInfo_Value(change.row.ptr,change.key,change.value))
   if change.key=='B_SHOWINTCP'then change.row.shown=change.value==1 end
  end
  if master~=tree.master.shown then
   local flags=api.GetMasterTrackVisibility();api.SetMasterTrackVisibility((flags&~1)|(master and 1 or 0));tree.master.shown=master
  end
 end,tostring)
 api.PreventUIRefresh(-1);api.TrackList_AdjustWindows(false);api.UpdateArrange();assert(ok,err)
end
function Core.restoreview(api,saved)
 if not saved then return end
 local active=api.EnumProjects(-1,'');local available=active==saved.project
 if not available then local i=0;while true do local p=api.EnumProjects(i,'');if not p then break end;if p==saved.project then available=true;break end;i=i+1 end end
 if not available then return end
 api.PreventUIRefresh(1)
 local ok,err=xpcall(function()
  for i=0,api.CountTracks(saved.project)-1 do
   local track=api.GetTrack(saved.project,i);local before=saved.tracks[api.GetTrackGUID(track)]
   if before then
    local visible=before.shown and 1 or 0
    if api.GetMediaTrackInfo_Value(track,'B_SHOWINTCP')~=visible then assert(api.SetMediaTrackInfo_Value(track,'B_SHOWINTCP',visible))end
    if api.GetMediaTrackInfo_Value(track,'I_FOLDERDEPTH')>0 and api.GetMediaTrackInfo_Value(track,'I_FOLDERCOMPACT')~=before.compact then
     assert(api.SetMediaTrackInfo_Value(track,'I_FOLDERCOMPACT',before.compact))
    end
   end
  end
  if active==saved.project then
   local flags=api.GetMasterTrackVisibility();local restored=(flags&~1)|(saved.master and 1 or 0)
   if flags~=restored then api.SetMasterTrackVisibility(restored)end
  end
 end,tostring)
 api.PreventUIRefresh(-1);api.TrackList_AdjustWindows(false);api.UpdateArrange();assert(ok,err)
end
function Core.plan(tree,selected,targetId,mode)
 local roots={};local moving={}
 for _,r in ipairs(tree.rows)do
  if selected[r.id]then
   local p=r.parent;local covered=false;while p do if selected[p.id]then covered=true;break end;p=p.parent end
   if not covered then roots[#roots+1]=r end
  end
 end
 assert(#roots>0,'移動するトラックがありません。')
 local function mark(r)moving[r.id]=true;for _,v in ipairs(r.children)do mark(v)end end
 for _,r in ipairs(roots)do mark(r)end
 local target=targetId and tree.by[targetId]
 assert(not targetId or target,'移動先のトラックがありません。')
 assert(not target or not target.master,'マスターは並べ替えできません。')
 assert(not target or not moving[target.id],'選択トラック自身や、その子には移動できません。')
 assert(mode=='before'or mode=='after'or mode=='inside'or mode=='end','移動先が無効です。')
 assert(mode~='inside'or(target and #target.children>0),'フォルダを移動先に指定してください。')
 local lists={};local ROOT={};local function key(r)return r and r.id or ROOT end
 lists[ROOT]={};for _,r in ipairs(tree.rows)do lists[r.id]={}end
 for _,r in ipairs(tree.rows)do if not moving[r.id]or(r.parent and moving[r.parent.id])then
  local list=lists[key(r.parent)];list[#list+1]=r
 end end
 local parent=mode=='inside'and target or(mode~='end'and target and target.parent or nil)
 local dest=lists[key(parent)];local at=#dest+1
 if target and mode~='inside'then for i,r in ipairs(dest)do if r.id==target.id then at=i+(mode=='after'and 1 or 0);break end end end
 for i,r in ipairs(roots)do table.insert(dest,at+i-1,r)end
 local result={};local function visit(r,depth)
  result[#result+1]={ptr=r.ptr,id=r.id,depth=depth};for _,child in ipairs(lists[r.id])do visit(child,depth+1)end
 end
 for _,r in ipairs(lists[ROOT])do visit(r,0)end
 assert(#result==#tree.rows,'トラック構造を確認できません。')
 for i,r in ipairs(result)do r.delta=(result[i+1]and result[i+1].depth or 0)-r.depth end
 return result
end
local function transaction(api,project,title,flags,fn)
 assert(api.EnumProjects(-1,'')==project,'プロジェクトが切り替わりました。')
 api.Undo_BeginBlock2(project);api.PreventUIRefresh(1)
 local ok,err=xpcall(fn,tostring)
 api.PreventUIRefresh(-1);api.Undo_EndBlock2(project,title,flags)
 if not ok then api.Undo_DoUndo2(project)end
 api.TrackList_AdjustWindows(false);api.UpdateArrange()
 assert(ok,err)
end
function Core.clipboardnames(text)
 assert(type(text)=='string'and #text<=16*1024*1024,'クリップボードのテキストが大きすぎます。')
 assert(utf8.len(text),'クリップボードの文字コードを読み取れません。')
 text=text:gsub('^\239\187\191',''):gsub('\r\n','\n'):gsub('\r','\n')
 if text==''then return {}end
 local rows,field={},{};local column=1;local quoted=false;local start=true;local i=1
 local function finishrow()
  local name=table.concat(field):gsub('[%z\1-\31\127]',' ')
  assert(#name<=4096,'トラック名は4096バイト以内にしてください。')
  rows[#rows+1]=name;field={};column=1;start=true
 end
 while i<=#text do
  local c=text:sub(i,i)
  if quoted then
   if c=='"'then
    if text:sub(i+1,i+1)=='"'then if column==1 then field[#field+1]='"'end;i=i+1
    else quoted=false end
   elseif column==1 then field[#field+1]=c end
  elseif c=='"'and start then quoted=true;start=false
  elseif c=='\t'then column=column+1;start=true
  elseif c=='\n' then finishrow()
  else if column==1 then field[#field+1]=c end;start=false end
  i=i+1
 end
 assert(not quoted,'クリップボードの引用符が閉じられていません。')
 if text:sub(-1)~='\n'or #field>0 or column>1 then finishrow()end
 return rows
end
function Core.copynames(api,ids)
 local tree=Core.snapshot(api);local names={}
 local function add(row)
  if not(ids and ids[row.id]or not ids and row.selected)then return end
  local name=row.name
  if name:find('["\t\r\n]')then name='"'..name:gsub('"','""')..'"'end
  names[#names+1]=name
 end
 add(tree.master);for _,row in ipairs(tree.rows)do add(row)end
 return table.concat(names,'\r\n'),#names
end
function Core.pastenames(api,text,ids)
 local names=Core.clipboardnames(text);if #names==0 then return 0 end
 local tree=Core.snapshot(api);local changes={};local index=1
 for _,row in ipairs(tree.rows)do if(ids and ids[row.id]or not ids and row.selected)and index<=#names then
  local ok,before=api.GetSetMediaTrackInfo_String(row.ptr,'P_NAME','',false);assert(ok,'トラック名を取得できません。')
  if before~=names[index]then changes[#changes+1]={ptr=row.ptr,name=names[index]}end
  index=index+1
 end end
 if #changes==0 then return 0 end
 transaction(api,tree.project,'BLT Track Tree: Paste track names',1,function()
  for _,change in ipairs(changes)do assert(api.GetSetMediaTrackInfo_String(change.ptr,'P_NAME',change.name,true),'トラック名を変更できません。')end
 end)
 return #changes
end
function Core.move(api,tree,selected,target,mode)
 local live=Core.snapshot(api)
 assert(live.project==tree.project and live.signature==tree.signature,'トラック構造が変更されました。もう一度ドラッグしてください。')
 local result=Core.plan(live,selected,target,mode);local changed=false
 for i,r in ipairs(result)do if r.id~=live.rows[i].id or r.delta~=live.rows[i].delta then changed=true;break end end
 if not changed then return end
 transaction(api,tree.project,'BLT Track Tree: Move tracks',-1,function()
  for _,r in ipairs(live.rows)do assert(api.SetMediaTrackInfo_Value(r.ptr,'I_FOLDERDEPTH',0))end
  for i,r in ipairs(result)do
   if api.GetTrack(tree.project,i-1)~=r.ptr then
    api.SetOnlyTrackSelected(r.ptr);assert(api.ReorderSelectedTracks(i-1,0),'トラックの移動に失敗しました。')
   end
  end
  for i,r in ipairs(result)do
   assert(api.GetTrack(tree.project,i-1)==r.ptr,'トラック順序を確認できません。')
   assert(api.SetMediaTrackInfo_Value(r.ptr,'I_FOLDERDEPTH',r.delta))
   api.SetTrackSelected(r.ptr,selected[r.id]==true)
  end
  api.SetTrackSelected(live.master.ptr,selected[live.master.id]==true)
 end)
end
function Core.visibility(api,tree,ids,on)
 local live=Core.snapshot(api);assert(live.project==tree.project,'プロジェクトが切り替わりました。')
 if not ids then
  ids={};if live.master.shown~=on or live.master.mixer~=on then ids[live.master.id]=true end
  for _,r in ipairs(live.rows)do if r.shown~=on or r.mixer~=on then ids[r.id]=true end end
 end
 if not next(ids)then return end
 transaction(api,tree.project,'BLT Track Tree: Track visibility',1|8,function()
  if ids[live.master.id]then
   local flags=api.GetMasterTrackVisibility();api.SetMasterTrackVisibility((flags&~3)|(on and 1 or 2))
  end
  for _,r in ipairs(live.rows)do if ids[r.id]then
   assert(api.SetMediaTrackInfo_Value(r.ptr,'B_SHOWINTCP',on and 1 or 0))
   assert(api.SetMediaTrackInfo_Value(r.ptr,'B_SHOWINMIXER',on and 1 or 0))
  end end
 end)
end
function Core.pin(api,tree,ids,on)
 local live=Core.snapshot(api);assert(live.project==tree.project,'プロジェクトが切り替わりました。')
 local targets={};if ids[live.master.id]and live.master.pinned~=on then targets[1]=live.master end
 for _,r in ipairs(live.rows)do if ids[r.id]and r.pinned~=on then targets[#targets+1]=r end end
 if #targets==0 then return end
 transaction(api,live.project,'BLT Track Tree: '..(on and 'Pin tracks'or'Unpin tracks'),1,function()
  for _,r in ipairs(targets)do assert(api.SetMediaTrackInfo_Value(r.ptr,'B_TCPPIN',on and 1 or 0),'トラックの固定状態を変更できません。')end
 end)
end
function Core.reveal(api,tree,id)
 local live=Core.snapshot(api);assert(live.project==tree.project,'プロジェクトが切り替わりました。')
 local row=live.by[id];if not row then return end
 local changes={};local node=row
 while node do
  if not node.shown then changes[#changes+1]={row=node,key='B_SHOWINTCP',value=1}end
  if node~=row and api.GetMediaTrackInfo_Value(node.ptr,'I_FOLDERCOMPACT')~=0 then
   changes[#changes+1]={row=node,key='I_FOLDERCOMPACT',value=0}
  end
  node=node.parent
 end
 if #changes>0 then transaction(api,live.project,'BLT Track Tree: Reveal track',1|8,function()
  for _,change in ipairs(changes)do
   if change.row.master then api.SetMasterTrackVisibility(api.GetMasterTrackVisibility()|1)
   else assert(api.SetMediaTrackInfo_Value(change.row.ptr,change.key,change.value))end
  end
 end)end
 api.TrackList_AdjustWindows(false);api.Main_OnCommandEx(40913,0,live.project);api.UpdateArrange()
end
function Core.allvisibility(api,on)
 Core.visibility(api,{project=api.EnumProjects(-1,'')},nil,on)
end
local A={rows={},closed={},offset=0,query='',message='',dirty=true,closing=false,down=false}
local S={query='',tr=true,it=false,fx=false,related=false,link=false}
local function status(text,bad)A.message=tostring(text);A.bad=bad;A.dirty=true end
local function extnum(key,default)local v=tonumber(R.GetExtState(SECTION,key));return finite(v)and v or default end
local W,H=400,694

local C={
  bg={0.018,0.030,0.055}, bg2={0.030,0.090,0.180}, panel={0.040,0.068,0.110}, panel2={0.055,0.125,0.205},
  ice={.65,.895,1},disabled={.43,.46,.51},
  field={0.018,0.040,0.080}, edge={0.145,0.285,0.445}, edge2={0.360,0.650,0.900},
  text={0.955,0.980,1.000}, muted={0.690,0.780,0.875}, faint={0.390,0.505,0.635},
  accent={0.120,0.490,0.980}, accent2={0.650,0.895,1.000}, accent3={0.045,0.235,0.520},
  focus={0.225,0.610,1.000}, focus2={0.690,0.900,1.000}, ink={0.018,0.075,0.160},
  hover={0.430,0.790,1.000}, warn={1.000,0.755,0.490}, red={1.000,0.180,0.260}, green={0.470,0.850,0.700}, quiet={0.300,0.360,0.440}
}
local fonts={"Yu Gothic UI","Segoe UI","Consolas"}
local os_name=R.GetOS()
if os_name:match("OSX") or os_name:match("macOS") then fonts={"Hiragino Sans","Helvetica Neue","Menlo"}
elseif not os_name:match("Win") then fonts={"sans-serif","sans-serif","monospace"} end

local scale,ox,oy=1,0,0

local function sx(x) return ox+x*scale end
local function sy(y) return oy+y*scale end
local function color(c,a) gfx.set(c[1],c[2],c[3],a or 1) end
local function rect(x,y,w,h,c,a) color(c,a); gfx.rect(sx(x),sy(y),w*scale,h*scale,1) end
local function line(x,y,xx,yy,c,a) color(c,a); gfx.line(sx(x),sy(y),sx(xx),sy(yy),1) end

local function font(size,kind,bold) BLT.font(size,kind,bold,scale,fonts) end
local function label(text,x,y,w,h,size,c,bold,flags,kind,literal)
  local shown=literal and tostring(text) or Language.message(text)
  font(size,kind,bold); color(c or C.text); gfx.x,gfx.y=sx(x),sy(y)
  if w then shown=BLT.ui.fit(shown,w*scale) end
  gfx.drawstr(BLT.cleanText(shown),flags or 0,sx(x+w),sy(y+h))
end

local Chameleon
local Chrome={window=nil,mouseDown=false,drag=nil,resize=nil,mouseActive=false,requestClose=false,requestReset=false,
  chameleonPressed=false,titleH=26,windowTitle='BLT TRACK TREE',titleText='T R A C K   T R E E',
  minW=360,minH=300,mint={0.38,0.88,0.72},ice={0.65,0.895,1.0},red={1.0,0.27,0.34},
  isWindows=R.GetOS():match("Win")~=nil,resizeEdge=6,resizeCornerBand=8,resizeCornerSpan=24,resizeTopLeftGuard=30,resizeTopRightGuard=110,
  tooltipHover=nil,tooltipSince=0,tooltipVisible=false,tooltipDelay=.70,
  cursorId={we=32644,ns=32645,nwse=32642,nesw=32643,arrow=32512}}
Chrome.font=Chrome.isWindows and "Segoe UI" or (BLT_MAC and "Helvetica Neue" or "sans-serif")
local function chameleon_notify(text)
  status(text,false)
end

local BLTTreeControls=(function()
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
local treeDensity=BLTTreeControls.compactScale
local TreeGraphics=(function()
 local G={}
 function G.setfont(_,face,size,flags)
  local kind=1;for i,name in ipairs(fonts)do if face==name then kind=i;break end end
  BLT.font(size,kind,flags==98,1,fonts)
 end
 return setmetatable(G,{__index=function(_,key)if key=='mouse_wheel'then return 0 end;return gfx[key]end,
  __newindex=function(_,key,value)if key~='mouse_wheel'then gfx[key]=value end end})
end)()
local TreeUI=BLTTreeControls.new(TreeGraphics,R.time_precise,C)
TreeUI.font,TreeUI.minFontSize=fonts[1],7
local tree_interaction=TreeUI.interaction
function TreeUI:interaction(...)
 local _,hot,held,state=tree_interaction(self,...)
 local x,_,w=select(2,...)
 local target=hot and math.max(.12,math.min(.88,(self.mx-x)/w)) or .18
 if math.abs(state.lightX-target)>.0001 then A.dirty=true end
 return false,hot,held,state
end
local function tree_animation()
 for _,s in pairs(TreeUI.states) do
  if s.hover and s.hover>0 and s.hover<1 or s.slide and s.slide>0 and s.slide<1
   or s.active and s.active>0 and s.active<1 or s.sparkAt or s.flashPending or s.flash then A.dirty=true;return end
 end
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


Chameleon=BLTChameleon.new(R,C,{
 section=SECTION,store=BLT.store,notify=chameleon_notify,chrome=Chrome,
 roles={ice='accent2',disabled='faint'},special=TreeUI.tones,
 applied=function(restored,palette) TreeUI.themeTones=not restored and palette.special or nil end,
 changed=function() A.dirty=true end
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


-- Shared BLT app restoration protocol. Each app owns one registry ID.
local BLTRestore={section='BLT_APP_RESTORE',id='BLT_TRACK_TREE'}
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

local Dock={state=math.floor(clamp(extnum('dock_state',0),0,3841))&0xF01}
if(Dock.state&1)~=0 then Dock.target=Dock.state;Dock.retryAt=R.time_precise()+.4 end
local IME={}
local editor=nil
local widgets={}
local clipboard_action
local TOP,ROW=136,27
local OPTION_KEYS={'tr','it','fx','related','link'}
local function guide(x,y,xx,yy,c,a,depth)
 if depth%2==1 then line(x,y,xx,yy,c,a);return end
 local vertical=x==xx;local start=vertical and y or x;local finish=vertical and yy or xx
 if finish<start then start,finish=finish,start end
 for pos=start,finish,6 do
  local ending=min(pos+2,finish)
  if vertical then line(x,pos,x,ending,c,a)else line(pos,y,ending,y,c,a)end
 end
end
local function docked()return(Dock.state&1)~=0 end
local toolbar,clearWidth,clearLanguage,clearDPI
local function clear_geometry()
 local dpi=gfx.ext_retina or 1
 if not clearWidth or clearLanguage~=Language.code or clearDPI~=dpi then
  font(11,1,false);clearWidth=math.ceil(gfx.measurestr(Language.text('クリア')))+8
  clearLanguage,clearDPI=Language.code,dpi
 end
 return gfx.w-13-clearWidth,clearWidth
end
local function toolbar_geometry()
 local dpi=gfx.ext_retina or 1
 if not toolbar or toolbar.width~=gfx.w or toolbar.language~=Language.code or toolbar.dpi~=dpi then
  font(12,1,false);local related=math.ceil(gfx.measurestr(Language.text('親・子も表示')))+40
  font(12,1,true);local linkW=math.ceil(gfx.measurestr('VIEW LINK'))+32
  local linkX=132+related+12;local split=linkX+linkW+16+102>gfx.w-12
  toolbar={width=gfx.w,language=Language.code,dpi=dpi,related=related,linkX=split and 12 or linkX,
   toolsX=gfx.w-114,toolsY=split and 105 or 75,linkY=split and 104 or 74,linkW=linkW,top=split and 136 or 106}
 end
 TOP=toolbar.top
 return toolbar.related,toolbar.linkX,toolbar.toolsX,toolbar.toolsY,toolbar.linkY,toolbar.linkW
end
local function capacity()return max(1,floor((gfx.h-TOP-28)/ROW))end
local function search_match(row,q)
 -- Cache both hits and misses for the current normalized query.
 if A.matchQuery~=q or not A.matches then A.matchQuery=q;A.matches={} end
 local found=A.matches[row.id];if found~=nil then return found end
 found=S.tr and(row.name:lower():find(q,1,true)~=nil or row.master and ('マスター'):find(q,1,true)~=nil)or false
 if not found and(S.it or S.fx)then
  A.search=A.search or{}
  local data=A.search[row.id]
  if not data then
   if not R.ValidatePtr2(A.tree.project,row.ptr,'MediaTrack*')then return false end
   data=Core.searchdata(R,row,S.it,S.fx);A.search[row.id]=data
  end
  for _,name in ipairs(data.items)do if name:find(q,1,true)then found=true;break end end
  if not found then for _,name in ipairs(data.fx)do if name:find(q,1,true)then found=true;break end end end
 end
 A.matches[row.id]=found;return found
end
local function update_view(relink,reuse)
 if not A.tree then return end
 A.viewPending=true;A.viewRetry=R.time_precise()+.25
 if not reuse then A.rows=Core.visible(A.tree,A.closed,A.query,search_match,S.related)end
 if relink then A.manualVisibility=nil end
 if A.manualVisibility then
  local saved=A.manualVisibility;local same=saved.project==A.tree.project and #saved.ids==#A.rows
  if same then for i,row in ipairs(A.rows)do if saved.ids[i]~=row.id then same=false;break end end end
  if not same then A.manualVisibility=nil end
 end
 if S.link and not A.manualVisibility then
  if not A.linkState then A.linkState={project=A.tree.project,tracks={},master=A.tree.master.shown}end
  Core.linkview(R,A.tree,A.rows,A.linkState);A.revision=R.GetProjectStateChangeCount(A.tree.project);A.masterVisibility=R.GetMasterTrackVisibility()end
 A.lastChild={};for _,row in ipairs(A.rows)do if row.parent then A.lastChild[row.parent.id]=row.id end end
 A.offset=clamp(A.offset,0,max(0,#A.rows-capacity()));A.dirty=true;A.viewPending=nil;A.viewRetry=nil
end
local function sync_selection(project)
 local selected=A.selectionScratch or{};for row in pairs(selected)do selected[row]=nil end
 local changed=false;local count=R.CountSelectedTracks2(project,true)
 for i=0,count-1 do
  local ptr=R.GetSelectedTrack2(project,i,true);local row=A.byPointer[ptr]
  if not row then return false end
  selected[row]=true
  if not row.selected then row.selected=true;changed=true end
 end
 for row in pairs(A.selectedRows)do if not selected[row]then row.selected=false;changed=true end end
 A.selectionScratch=A.selectedRows;A.selectedRows=selected;A.selectionCount=count
 if changed then A.dirty=true end
 return true
end
local function refresh(force)
 local now=R.time_precise()
 if not force and now<(A.nextCheck or 0)then return end
 A.nextCheck=now+.025
 local project=R.EnumProjects(-1,'')
 if A.linkState and A.linkState.project~=project then Core.restoreview(R,A.linkState);A.linkState=nil end
 local revision=R.GetProjectStateChangeCount(project)
 if not force and A.tree and A.tree.project==project and A.revision==revision
  and R.CountTracks(project)==#A.tree.rows and R.GetMasterTrackVisibility()==A.masterVisibility then
  if sync_selection(project)then if A.viewPending and now>=(A.viewRetry or 0)then update_view()end;return end
 end
 local searchChanged=A.revision~=revision or not A.tree or A.tree.project~=project
 if searchChanged then A.search=nil;if S.it or S.fx then A.matches=nil end end
 A.revision=revision
 local tree=Core.snapshot(R)
 if not A.tree or A.tree.project~=tree.project then A.closed={};A.offset=0;A.anchor=nil;A.drag=nil end
 local old=A.tree;local replaced=false
 local changed=not old or old.project~=tree.project or old.signature~=tree.signature
 local filterChanged=changed;local visibilityChanged=false
 local function compare(row,previous)
  if not previous then changed=true;return end
  if row.ptr~=previous.ptr then replaced=true end
  if row.name~=previous.name and S.tr then filterChanged=true end
  if row.shown~=previous.shown then visibilityChanged=true end
  if row.name~=previous.name or row.selected~=previous.selected or row.shown~=previous.shown
   or row.mixer~=previous.mixer or row.color~=previous.color or row.pinned~=previous.pinned then changed=true end
 end
 if old then
  compare(tree.master,old.master)
  for _,row in ipairs(tree.rows)do compare(row,old.by[row.id])end
 end
 if replaced or(old and old.signature~=tree.signature)then A.drag=nil;A.lastClick=nil end
 A.tree=tree;A.byPointer={};A.selectedRows={};A.selectionScratch={};A.selectionCount=0
 A.masterVisibility=R.GetMasterTrackVisibility()
 local function register(row)A.byPointer[row.ptr]=row;if row.selected then A.selectedRows[row]=true;A.selectionCount=A.selectionCount+1 end end
 register(tree.master);for _,row in ipairs(tree.rows)do register(row)end
 if replaced or filterChanged then A.matches=nil end
 if replaced then A.search=nil end
 local retryReady=not A.viewPending or now>=(A.viewRetry or 0)
 if retryReady and(A.viewPending or replaced or filterChanged or(searchChanged and(S.it or S.fx)and A.query:match('%S')))then update_view()
 else
  local count,total=0,#A.rows
  for i=1,total do local row=tree.by[A.rows[i].id];if row then count=count+1;A.rows[count]=row end end
  for i=total,count+1,-1 do A.rows[i]=nil end
  if changed then A.dirty=true end
  if visibilityChanged and S.link and retryReady then update_view(false,true)end
 end
end
local function selected_ids()
 local ids={};for row in pairs(A.selectedRows)do ids[row.id]=true end;return ids
end
local function select_row(row,ctrl,shift)
 local project=A.tree.project;local id=row.id;refresh(true)
 if project~=A.tree.project then return end
 row=A.tree.by[id];if not row then return end
 local ids=ctrl and selected_ids()or{}
 if shift and A.anchor then
  local a,b;for i,r in ipairs(A.rows)do if r.id==A.anchor then a=i end;if r.id==row.id then b=i end end
  if a and b then for i=min(a,b),max(a,b)do ids[A.rows[i].id]=true end else ids[row.id]=true end
 elseif ctrl then ids[row.id]=not ids[row.id]else ids[row.id]=true end
 for _,r in ipairs(A.tree.rows)do if r.selected~=(ids[r.id]==true)then R.SetTrackSelected(r.ptr,ids[r.id]==true)end end
 local master=A.tree.master;if master.selected~=(ids[master.id]==true)then R.SetTrackSelected(master.ptr,ids[master.id]==true)end
 if not shift then A.anchor=row.id end
 R.UpdateArrange();A.revision=R.GetProjectStateChangeCount(A.tree.project);sync_selection(A.tree.project)
end
local function set_option(key,value)
 if key=='link'and not value and A.linkState then Core.restoreview(R,A.linkState);A.linkState=nil end
 if not value and TreeUI.focus==key then TreeUI.focus=nil end
 S[key]=value;A.offset=0
 if key=='tr'or key=='it'or key=='fx'then A.matches=nil end
 if key=='it'or key=='fx'then A.search=nil end
 R.SetExtState(SECTION,key,value and '1'or'0',true)
 if key=='link'and not value then refresh(true)else update_view(true)end
end
local function all_visibility(on)
 if S.link then
  local ids={};for i,row in ipairs(A.rows)do ids[i]=row.id end
  A.manualVisibility={project=A.tree.project,ids=ids}
 end
 Core.allvisibility(R,on);refresh(true)
end
local function query(value)
 A.query=value;S.query=value;A.offset=0;update_view(true);R.SetExtState(SECTION,'query',value,true)
end
local function stop_edit(cancel)
 if not editor then return end
 if cancel then query(editor.original)end
 editor=nil;IME.ctx=nil;IME.font=nil;A.dirty=true
end
local function start_edit()
 IME.api,IME.ctx,IME.font=gfx.inputContext(fonts[1])
 editor={original=A.query,frames=0};A.dirty=true
end
local function rgba(c)return(floor(c[1]*255)<<24)|(floor(c[2]*255)<<16)|(floor(c[3]*255)<<8)|255 end
local function edit_frame()
 if not editor then return end
 local I,ctx,_,ox,oy=gfx.inputContext(fonts[1])
 local clearX=clear_geometry()
 I.PushStyleVar(ctx,I.StyleVar_FrameBorderSize,0);I.PushStyleVar(ctx,I.StyleVar_FrameRounding,0)
 I.PushStyleVar(ctx,I.StyleVar_FramePadding,6,5)
 I.PushStyleColor(ctx,I.Col_FrameBg,rgba(C.field));I.PushStyleColor(ctx,I.Col_Text,rgba(C.text))
 I.PushFont(ctx,IME.font,14)
 I.SetCursorScreenPos(ctx,ox+13,oy+39);I.SetNextItemWidth(ctx,clearX-15)
 if editor.frames==0 then I.SetKeyboardFocusHere(ctx)end
 local changed,text=I.InputText(ctx,'##tree_filter',A.query,I.InputTextFlags_AutoSelectAll)
 if changed then query(text)end
 local cancel=I.IsKeyPressed(ctx,I.Key_Escape,false)
 local done=I.IsItemDeactivated(ctx)or I.IsKeyPressed(ctx,I.Key_Enter,false)or I.IsKeyPressed(ctx,I.Key_KeypadEnter,false)
 local focused=I.IsWindowFocused(ctx)
 I.PopFont(ctx);I.PopStyleColor(ctx,2);I.PopStyleVar(ctx,3)
 editor.frames=editor.frames+1
 if cancel or editor.frames>1 and(done or not focused)then stop_edit(cancel)end
end
local function button(id,text,x,y,w,fn,icon)
 local hot=gfx.mouse_x>=x and gfx.mouse_x<x+w and gfx.mouse_y>=y and gfx.mouse_y<y+22
 TreeUI:button(id,'',x/treeDensity,y/treeDensity,w/treeDensity,22/treeDensity,{labelInset=0})
 local ink=hot and C.accent2 or C.muted
 if icon then
  local cx,cy=x+w/2,y+11
  if icon=='show'or icon=='hide'then
   line(cx-6,cy,cx,cy-5,ink);line(cx,cy-5,cx+6,cy,ink)
   line(cx+6,cy,cx,cy+5,ink);line(cx,cy+5,cx-6,cy,ink)
   color(C.accent2);gfx.circle(cx,cy,2,1,1)
   if icon=='hide'then line(cx-6,cy+6,cx+6,cy-6,C.warn)end
  else
   color(ink);gfx.rect(cx-5,cy-5,10,10,0)
   line(cx-2,cy-6,cx+6,cy-6,ink);line(cx+6,cy-6,cx+6,cy+2,ink)
   line(cx-3,cy,cx+3,cy,C.accent2)
   if icon=='open'then line(cx,cy-3,cx,cy+3,C.accent2)end
  end
 else label(text,x+4,y+4,w-8,20,12,ink,false,1)end
 widgets[#widgets+1]={id=id,x=x,y=y,w=w,h=22,fn=fn,tip=text}
end
local function filter_button(key,text,x,w,tip,y)
 y=y or 74
 local px,py,pw,ph=x/treeDensity,y/treeDensity,w/treeDensity,24/treeDensity
 local unit=24/(44*treeDensity)
 if key=='related' then
  local _,_,hitWidth=TreeUI:toggle(key,text,S[key],px,py,pw,ph,true,{background=false,showState=false,switchScale=unit,size=12/treeDensity})
  w=hitWidth*treeDensity
 elseif key=='link' then
  TreeUI:gold(key,text,S[key],px,py,pw,ph,{showState=false,size=12/treeDensity,bold=true,ledScale=unit})
 else
  TreeUI:button(key,text,px,py,pw,ph,{led='top',selected=S[key],size=12/treeDensity,bold=true,labelInset=4/treeDensity,ledScale=unit})
 end
 widgets[#widgets+1]={id=key,x=x,y=y,w=w,h=24,tip=tip,fn=function()set_option(key,not S[key])end}
end
local function row_at(y)
 local index=A.offset+floor((y-TOP)/ROW)+1
 if y<TOP or y>=TOP+capacity()*ROW then return nil end
 return A.rows[index],index
end
local function drop_at(y)
 local row=row_at(y)
 if not row then if y>=TOP and y<TOP+capacity()*ROW then return nil,'end' end;return nil,nil end
 if row.master then return nil,nil end
 local t=((y-TOP)%ROW)/ROW
 return row.id,(#row.children>0 and t>.3 and t<.7)and'inside'or(t<.5 and'before'or'after')
end
local function draw()
 gfx.beginDraw()
 if gfx.w<1 or gfx.h<1 then rect(0,0,1,1,C.bg);A.dirty=true;gfx.update();return end
 toolbar_geometry();widgets={};rect(0,0,gfx.w,gfx.h,C.bg)
 if #A.rows>capacity()then gfx.wheelRegion(0,0,gfx.w,gfx.h)end
 TreeUI:begin(treeDensity,0,0);TreeUI.themeEnabled=Chameleon.enabled;TreeUI.blocked=BLT.blocked() or editor~=nil
 local clearX,clearW=clear_geometry()
 TreeUI:fieldFrame('search',12/treeDensity,38/treeDensity,(gfx.w-24)/treeDensity,27/treeDensity,true,editor~=nil)
 if not editor then label(A.query~=''and A.query or Language.text('検索…'),19,44,clearX-24,21,14,A.query~=''and C.text or C.faint,false,0,1,true)end
 local clearEnabled=A.query~='' or A.offset>0
 if not clearEnabled then for _,closed in pairs(A.closed) do if closed then clearEnabled=true;break end end end
 TreeUI:button('clear',Language.text('クリア'),clearX/treeDensity,39/treeDensity,clearW/treeDensity,25/treeDensity,
  {variant='clear',enabled=clearEnabled,size=11/treeDensity,labelInset=3/treeDensity})
 widgets[#widgets+1]={id='clear',x=clearX,y=39,w=clearW,h=25,tip='フィルタークリア',fn=function()if clearEnabled then stop_edit(false);A.closed={};query('')end end}
 filter_button('tr','Tr',12,32,'トラック名を検索')
 filter_button('it','It',46,32,'アイテムのテイク名を検索')
 filter_button('fx','Fx',80,32,'トラックFX名を検索')
 local relatedW,linkX,toolsX,toolsY,linkY,linkW=toolbar_geometry()
 line(123,79,123,93,C.edge,.5)
 filter_button('related',Language.text('親・子も表示'),132,relatedW,'一致したトラックの親・子も表示')
 filter_button('link','VIEW LINK',linkX,linkW,'検索結果をアレンジの表示に連動',linkY)
 button('open','全オープン',toolsX+52,toolsY,24,function()A.closed={};update_view(true)end,'open')
 button('collapse','全クローズ',toolsX+78,toolsY,24,function()for _,r in ipairs(A.tree.rows)do if #r.children>0 then A.closed[r.id]=true end end;update_view(true)end,'collapse')
 button('showAll','全トラックを表示',toolsX,toolsY,24,function()all_visibility(true)end,'show')
 button('hideAll','全トラックを非表示',toolsX+26,toolsY,24,function()all_visibility(false)end,'hide')
 local maxIndent=max(0,gfx.w-160)
 local flat=A.query:match('%S')and not S.related
 for slot=0,capacity()-1 do
  local row=A.rows[A.offset+slot+1];if not row then break end
  local y=TOP+slot*ROW;local selected=row.selected
  rect(10,y,gfx.w-30,ROW,selected and C.panel2 or(slot%2==0 and C.panel or C.bg),selected and 1 or .7)
  if selected then rect(10,y,2,ROW,C.accent2)end
  local shown=row.shown and row.mixer
  rect(18,y+8,11,11,shown and C.accent2 or C.bg)
  color(C.edge2,.8);gfx.rect(18,y+8,11,11,0)
  if row.shown~=row.mixer then line(20,y+13,27,y+13,C.warn,1)end
  local x=40+(flat and 0 or min(row.depth*5,maxIndent))
  local cy=y+13;local branch=row;local parent=not flat and row.parent or nil
  while parent do
   local rail=46+min(parent.depth*5,maxIndent)
   local last=A.lastChild[parent.id]==branch.id
   if branch==row then
    guide(rail,y,rail,last and cy or y+ROW,C.edge2,.62,parent.depth)
    guide(rail,cy,x+(#row.children>0 and 1 or 14),cy,C.edge2,.62,parent.depth)
   elseif not last then guide(rail,y,rail,y+ROW,C.edge2,.38,parent.depth)end
   branch=parent;parent=parent.parent
  end
  if #row.children>0 then
   local expanded=A.query~=''or not A.closed[row.id]
   if expanded and not flat and A.lastChild[row.id]then guide(x+6,cy+5,x+6,y+ROW,C.edge2,.62,row.depth)end
   color(C.accent2)
   if expanded then gfx.triangle(x+2,cy-3,x+10,cy-3,x+6,cy+3)
   else gfx.triangle(x+3,cy-4,x+3,cy+4,x+9,cy)end
  end
  if row.color~=0 then local r,g,b=R.ColorFromNative(row.color);rect(x+17,y+6,3,15,{r/255,g/255,b/255})end
  if row.master then label('M',x+2,y+6,15,18,11,C.muted,true,0,1,true)end
  if row.pinned then
   local px=gfx.w-33
   rect(px-6,y+5,13,12,C.focus,.07);rect(px-4,y+6,9,9,C.focus,.14)
   rect(px-2,y+13,5,9,C.focus,.12)
   line(px-3,y+7,px+3,y+7,C.focus);line(px-2,y+8,px-2,y+12,C.focus);line(px+2,y+8,px+2,y+12,C.focus)
   line(px-4,y+13,px+4,y+13,C.focus);line(px,y+14,px,y+20,C.focus)
   line(px-1,y+8,px+1,y+8,C.focus2,.85)
  end
  label(row.name~=''and row.name or '('..(row.index+1)..')',x+25,y+5,gfx.w-x-53-((row.pinned)and 17 or 0),22,14,row.shown and C.text or C.faint,row.master,0,1,true)
 end
 if #A.rows==0 then
  if A.query:match('%S')and not(S.tr or S.it or S.fx)then
   label('最低1種、',20,TOP+20,gfx.w-40,22,13,C.warn)
   label('検索対象を選んでください',20,TOP+42,gfx.w-40,22,13,C.warn)
  else label('対象のトラックがありません。',20,TOP+20,gfx.w-40,30,13,C.muted)end
 end
 local total=#A.rows;local trackH=capacity()*ROW;local maxOff=max(0,total-capacity())
 rect(gfx.w-14,TOP,5,trackH,C.field)
 local thumb=max(20,trackH*min(1,capacity()/max(1,total)))
 rect(gfx.w-14,TOP+(maxOff>0 and(A.offset/maxOff)*(trackH-thumb)or 0),5,thumb,{.40,.42,.45},.75)
 if A.drag and A.drag.moved then
  local id,mode=drop_at(gfx.mouse_y);local row,index=row_at(gfx.mouse_y)
  if mode and row then
   local yy=TOP+(index-A.offset-1)*ROW
   if mode=='inside'then color(C.accent2);gfx.rect(36,yy,gfx.w-58,ROW,0)
   else
    if mode=='after'then
     local last=index;while A.rows[last+1]and A.rows[last+1].depth>row.depth do last=last+1 end
     yy=TOP+(last-A.offset)*ROW
    end
    yy=clamp(yy,TOP,TOP+capacity()*ROW)
    line(36,yy,gfx.w-22,yy,C.accent2)
   end
  elseif mode=='end'then local yy=TOP+min(#A.rows-A.offset,capacity())*ROW;line(36,yy,gfx.w-22,yy,C.accent2)end
 end
 line(12,gfx.h-24,gfx.w-12,gfx.h-24,C.edge,.7)
 local count=A.selectionCount
 local message=A.message~=''and A.message or string.format(Language.text('%dトラック / 選択 %d'),#A.rows,count)
 gfx.textRoute(true)
 label(message,12,gfx.h-19,gfx.w-72,18,8,A.bad and C.red or C.muted)
 label('v0.3.11',gfx.w-56,gfx.h-19,44,18,8,C.faint,false,2,3,true)
 gfx.textRoute(false)
 TreeUI:finish();tree_animation();BLT.bar();gfx.update()
end
local function save_float()
 if gfx.w<1 or gfx.h<1 then return end
 local ok,l,t,r,b=WindowGeometry.JS_Window_GetRect(gfx_window_handle())
 if not ok then return end
 A.floating={l,t,r-l,b-t}
 for i,k in ipairs({'x','y','w','h'})do R.SetExtState(SECTION,'float_'..k,tostring(A.floating[i]),true)end
 local _,x,y,w,h=gfx.dock(-1,0,0,0,0)
 for k,v in pairs({x=x,y=y,w=w,h=h})do R.SetExtState(SECTION,'window_'..k,tostring(v),true)end
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
  if state==Dock.state then A.dirty=true end
 elseif(Dock.state&1)~=0 and(state&1)==0 then
  if(gfx.getchar(65537)&4)==0 then Dock.undocked=nil;return end
  Dock.undocked=(Dock.undocked or 0)+1
  if Dock.undocked<2 then return end
 end
 Dock.undocked=nil

 if state~=Dock.state then
  local was=docked();Dock.state=state;Chrome.window=nil;Chrome.drag=nil;Chrome.resize=nil;BLT.lastRect=nil;A.drag=nil;A.scrollDrag=nil
  R.SetExtState(SECTION,'dock_state',tostring(state),true)
  if was and not docked()and A.floating then gfx.setWindowRect(table.unpack(A.floating))end
  A.dirty=true
 end
end
local function toggle_dock()
 if Dock.target~=nil then return end
 stop_edit(false)
 if not docked()then save_float()end
 BLT.presets.dismiss();set_resize_cursor(nil)
 Dock.target=Dock.state~1;Dock.retryAt=R.time_precise()+.4
 R.SetExtState(SECTION,'dock_state',tostring(Dock.target),true);gfx.dock(Dock.target)
 Chrome.window=nil;Chrome.drag=nil;Chrome.resize=nil;BLT.lastRect=nil;A.drag=nil;A.scrollDrag=nil;A.dirty=true
end
local function input()
 local x,y,cap=gfx.mouse_x,gfx.mouse_y,gfx.mouse_cap
 local right=(cap&2)~=0;local rightPressed=right and not A.rightDown;A.rightDown=right
 local down=(cap&1)~=0;local ctrl=(cap&4)~=0 or(BLT_MAC and(cap&32)~=0);local shift=(cap&8)~=0
 if not(BLT.host.active()or(gfx.getchar(65536)&8)~=0)then A.drag=nil;A.scrollDrag=nil;A.down=down;return end
 local clearX,clearW=clear_geometry()
 if editor and down and not A.down and x>=clearX and x<clearX+clearW and y>=39 and y<64 then
  stop_edit(false);A.closed={};query('');A.down=down;return
 end
 if BLT.blocked()or editor then A.drag=nil;A.down=down;return end
 if rightPressed and not down then
  A.drag=nil;A.lastClick=nil;A.scrollDrag=nil;refresh(true)
  local row=row_at(y)
  if row and x>=10 and x<gfx.w-20 then
   local tree=A.tree;local ids=row.selected and selected_ids()or{[row.id]=true}
   local on=not row.pinned
   gfx.x,gfx.y=x,y
   local caption=Language.text(on and 'トラックを固定' or 'トラックの固定を解除')
   local canPaste=false;for id,on in pairs(ids)do if on and id~=tree.master.id then canPaste=true;break end end
   caption=caption..'|'..Language.text('トラック名をコピー')..'|'..(canPaste and ''or'#')..Language.text('トラック名をペースト')
   local choice=gfx.showmenu(caption)
   if R.EnumProjects(-1,'')==tree.project then
    if choice==1 then Core.pin(R,tree,ids,on)
    elseif choice==2 then clipboard_action(true,ids)
    elseif choice==3 and canPaste then clipboard_action(false,ids)end
   end
   refresh(true);A.dirty=true
  end
 end
 if down and not A.down then
  refresh(true)
  local previousClick=A.lastClick;A.lastClick=nil
  A.message='';A.bad=false
  if x>=12 and x<clearX and y>=38 and y<65 then start_edit()
  elseif x>=gfx.w-20 and y>=TOP and y<TOP+capacity()*ROW then A.scrollDrag=true
  else
   local hit=false
   for _,w in ipairs(widgets)do if x>=w.x and x<w.x+w.w and y>=w.y and y<w.y+w.h then w.fn();hit=true;break end end
   if not hit then local row=row_at(y)
    if row and x>=10 and x<gfx.w-20 then
     if x<35 then if S.link then set_option('link',false)end;local ids=row.selected and selected_ids()or{[row.id]=true};Core.visibility(R,A.tree,ids,not(row.shown and row.mixer));refresh(true)
     elseif #row.children>0 and x<40+((A.query:match('%S')and not S.related)and 0 or min(row.depth*5,max(0,gfx.w-160)))+18 then A.closed[row.id]=not A.closed[row.id];update_view(true)
     else
      local now=R.time_precise()
      local double=not ctrl and not shift and previousClick and previousClick.id==row.id and previousClick.project==A.tree.project
       and now-previousClick.time<=.35 and abs(x-previousClick.x)<=5 and abs(y-previousClick.y)<=5
      if double then
       select_row(row,false,false);Core.reveal(R,A.tree,row.id);refresh(true);A.drag=nil
      else
       if not ctrl and not shift then A.lastClick={id=row.id,project=A.tree.project,time=now,x=x,y=y}end
      local was=row.selected
      if ctrl or shift or not was then select_row(row,ctrl,shift)end
      if row.master then
       if was and not ctrl and not shift then select_row(row,false,false)end
      else A.drag={id=row.id,x=x,y=y,tree=A.tree,ids=selected_ids(),collapse=was and not ctrl and not shift}end
      end
     end
    end
   end
  end
 end
 if down and A.scrollDrag then A.offset=floor(clamp((y-TOP)/(capacity()*ROW),0,1)*max(0,#A.rows-capacity())+.5);A.dirty=true end
 if down and A.drag then
  if abs(x-A.drag.x)+abs(y-A.drag.y)>5 then A.drag.moved=true;A.lastClick=nil end
  if A.drag.moved then
   local now=R.time_precise()
   if now>=(A.autoScroll or 0)then
    local delta=y<TOP+15 and -1 or(y>TOP+capacity()*ROW-15 and 1 or 0)
    A.offset=clamp(A.offset+delta,0,max(0,#A.rows-capacity()));A.autoScroll=now+.08
   end
   A.dirty=true
  end
 end
 if not down and A.down then
  A.scrollDrag=nil
  local d=A.drag;A.drag=nil
  if d then
   if d.moved then
    local target,mode=drop_at(y)
    if mode and x>=10 and x<gfx.w-20 then Core.move(R,d.tree,d.ids,target,mode);refresh(true)end
   elseif d.collapse then local row=A.tree.by[d.id];if row then select_row(row,false,false)end end
  end
 end
 if gfx.mouse_wheel~=0 then A.offset=clamp(A.offset+(gfx.mouse_wheel>0 and -3 or 3),0,max(0,#A.rows-capacity()));gfx.mouse_wheel=0;A.dirty=true end
 A.down=down
end
LanguageCatalog.en['自動復元の登録に失敗しました。']='Could not register automatic app restoration.'
LanguageCatalog.en['親・子も表示']='Parents / Children'
LanguageCatalog.en['一致したトラックの親・子も表示']='Include matching tracks’ parents and children'
LanguageCatalog.en['検索…']='Search…'
LanguageCatalog.en['トラック名を検索']='Search track names'
LanguageCatalog.en['アイテムのテイク名を検索']='Search item take names'
LanguageCatalog.en['トラックFX名を検索']='Search track FX names'
LanguageCatalog.en['検索結果をアレンジの表示に連動']='Link tree results to arrange visibility'
LanguageCatalog.en['コピー・貼り付けにはSWS Extensionが必要です。']='Copy and paste require SWS Extension.'
LanguageCatalog.en['%dトラック名をコピーしました。']='Copied %d track names.'
LanguageCatalog.en['%dトラック名を変更しました。']='Renamed %d tracks.'
LanguageCatalog.en['全オープン']='Expand all';LanguageCatalog.en['全クローズ']='Collapse all'
LanguageCatalog.en['全トラックを表示']='Show all tracks'
LanguageCatalog.en['全トラックを非表示']='Hide all tracks'
LanguageCatalog.en['クリア']='Clear'
LanguageCatalog.en['アレンジ上部に固定']='Pinned to top of arrange view'
LanguageCatalog.en['トラック名をコピー']='Copy track names'
LanguageCatalog.en['トラック名をペースト']='Paste track names'
LanguageCatalog.en['トラックを固定']='Pin tracks'
LanguageCatalog.en['トラックの固定を解除']='Unpin tracks'
LanguageCatalog.en['フィルタークリア']='Clear filter'
LanguageCatalog.en['対象のトラックがありません。']='No matching tracks.'
LanguageCatalog.en['最低1種、']='Select at least one'
LanguageCatalog.en['検索対象を選んでください']='search target: Tr, It or Fx.'
LanguageCatalog.en['%dトラック / 選択 %d']='%d tracks / %d selected'
local function valid(s)
 if type(s)~='table'or type(s.query)~='string'or #s.query>=4096 then return false end
 for _,key in ipairs(OPTION_KEYS)do if type(s[key])~='boolean'then return false end end
 return true
end
BLT.attach({R=R,C=C,Chrome=Chrome,Chameleon=Chameleon,section=SECTION,faces=fonts,font=font,
 docked=docked,fold=toggle_dock,transition=function()return Dock.target~=nil end,geometry=function()return 1,0,0 end,active=function()local f=gfx.getchar(65536);return(f&1)==0 or(f&2)~=0 end,
 wake=function()A.dirty=true end,defaults={query='',tr=true,it=false,fx=false,related=false,link=false},capture=function()return S end,valid=valid,apply=function(v)
 if S.link and not v.link and A.linkState then Core.restoreview(R,A.linkState);A.linkState=nil;S.link=false;refresh(true)end
 for _,key in ipairs(OPTION_KEYS)do S[key]=v[key];R.SetExtState(SECTION,key,v[key]and'1'or'0',true)end
 A.search=nil;A.matches=nil;query(v.query)end,
 busy=function()return A.drag~=nil end,commit=function()stop_edit(false);return true end,cancelEdit=function()stop_edit(true)end,
 editing=function()return editor~=nil end,modal=function()return false end,
 handle=gfx_window_handle,resizeHit=chrome_resize_hit,cursor=set_resize_cursor,beginResize=begin_window_resize,resize=update_window_resize,
 undoRefresh=function()refresh(true)end,
 tip=function(x,y)for _,w in ipairs(widgets)do if x>=w.x and x<w.x+w.w and y>=w.y and y<w.y+w.h then return Language.text(w.tip)end end;local row=row_at(y);if row and row.pinned and x>=gfx.w-46 then return Language.text('アレンジ上部に固定')end;if y>=TOP and x<35 then return Language.code=='JP'and'アレンジ・ミキサー表示（選択中なら一括切替）'or'TCP / mixer visibility (selected tracks together)'end end})
clipboard_action=function(copy,ids)
 local api=copy and 'CF_SetClipboard'or'CF_GetClipboard'
 if not R.APIExists(api)then status(Language.text('コピー・貼り付けにはSWS Extensionが必要です。'),true);return true end
 if copy then
  local text,count=Core.copynames(R,ids)
  if count>0 then R.CF_SetClipboard(text);status(string.format(Language.text('%dトラック名をコピーしました。'),count))end
 else
  local count=Core.pastenames(R,R.CF_GetClipboard(''),ids);A.search=nil;A.matches=nil;refresh(true)
  status(string.format(Language.text('%dトラック名を変更しました。'),count))
 end
 return true
end
local function clipboard_shortcut(key)
 if editor or BLT.blocked()or A.drag then return false end
 local cap=gfx.mouse_cap or 0
 if(cap&24)~=0 then return false end
 local ctrl=(cap&4)~=0 or(BLT_MAC and(cap&32)~=0)
 local copy=key==3 or ctrl and(key==67 or key==99)
 local paste=key==22 or ctrl and(key==86 or key==118)
 if not copy and not paste then return false end
 return clipboard_action(copy)
end

local function close()
 if A.closedWindow then return end;A.closedWindow=true
 Core.restoreview(R,A.linkState);A.linkState=nil
 BLTRestore.finish(R,A.manualClose or Chrome.requestClose)
 stop_edit(false)
 R.SetExtState(SECTION,'dock_state',tostring(Dock.target or Dock.state),true)
 if not docked()and Dock.target==nil then save_float()end
 TreeGraphics.release();titlebar_cleanup();clear_chrome_tooltip();gfx.quit()
end
local function recover_input(why)
 TreeGraphics.abort();A.drag=nil;A.down=false;stop_edit(true);status(BLT.publicError(why),true);BLT.logError(why)
end
local function overlay_frame()
 if gfx.w<1 or gfx.h<1 then return end
 edit_frame()
 if not IME.inputPending then return end
 IME.inputPending=nil;input()
 if Chrome.requestClose then A.closing=true end
 if Chrome.requestReset then Chrome.requestReset=false;reset_window_size();A.dirty=true end
end
gfx.setOverlay(function()
 local ok,why=xpcall(overlay_frame,debug.traceback);if not ok then recover_input(why)end
end)
local ok,err=titlebar_api_ready();if not ok then R.MB(err,'BLT TRACK TREE',0);return end
if R.set_action_options then R.set_action_options(2)end
local ww=clamp(extnum('window_w',W),360,1600);local hh=clamp(extnum('window_h',H+26),300,2000)
gfx.ext_retina=1
local wx,wy=extnum('window_x',100),extnum('window_y',100)
local fx,fy=extnum('float_x',0/0),extnum('float_y',0/0)
if finite(fx)and finite(fy)then A.floating={fx,fy,clamp(extnum('float_w',ww),360,1600),clamp(extnum('float_h',hh),300,2000)}end
gfx.init(Chrome.windowTitle,ww,hh,Dock.state,wx,wy)
if Chameleon.enabled then Chameleon.refresh(true)end
R.atexit(close)
local restoreOK,restoreError=pcall(BLTRestore.start,R)
if not restoreOK then R.MB(Language.text('自動復元の登録に失敗しました。')..'\n'..tostring(restoreError),'BLT TRACK TREE',0)end
for _,key in ipairs(OPTION_KEYS)do local value=R.GetExtState(SECTION,key);if value~=''then S[key]=value=='1'end end
A.query=R.GetExtState(SECTION,'query');S.query=A.query;refresh(true)
local function loop()
 local ok,why=xpcall(function()
  sync_dock()
  local k=gfx.getchar();if k<0 then A.manualClose=true;A.closing=true;return end
  if gfx.w<1 or gfx.h<1 then refresh(false);draw();return end
  if(gfx.getchar(65537)&4)==0 then refresh(false);A.dirty=true;return end
  k=BLT.key(k)
  if clipboard_shortcut(k)then k=0 end
  if not editor then
   if k==27 then A.manualClose=true;A.closing=true
   elseif k==1 then refresh(true);for _,r in ipairs(A.rows)do if not r.selected then R.SetTrackSelected(r.ptr,true)end end
    A.revision=R.GetProjectStateChangeCount(A.tree.project);sync_selection(A.tree.project)
   elseif k==6 then start_edit()end
  end
  local now=R.time_precise();BLT.tick(now);if Chameleon.tick(now)then A.dirty=true end
  refresh(false)
  if A.width~=gfx.w or A.height~=gfx.h then A.width,A.height=gfx.w,gfx.h;toolbar_geometry();A.offset=clamp(A.offset,0,max(0,#A.rows-capacity()));A.dirty=true end
  local x,y,cap=gfx.mouse_x,gfx.mouse_y,gfx.mouse_cap
  local inside=x>=0 and x<gfx.w and y>=0 and y<gfx.h
  local previous=A.mouseX and A.mouseX>=0 and A.mouseX<gfx.w and A.mouseY>=0 and A.mouseY<gfx.h
  local capture=A.drag or A.scrollDrag or Chrome.drag or Chrome.resize or Chrome.mouseDown and Chrome.mouseActive
   or TreeUI.capture and TreeUI.down
  local pointer=(inside or previous) and (cap~=0 or A.down or A.rightDown or gfx.mouse_wheel~=0 or A.mouseX~=x or A.mouseY~=y)
  if not inside and not capture and not editor and not BLT.presets.open then
   gfx.mouse_wheel=0;A.down=(cap&1)~=0;A.rightDown=(cap&2)~=0;Chrome.mouseDown=A.down
  end
  A.mouseX,A.mouseY=x,y
  if A.dirty or pointer or capture or editor then A.dirty=false;draw();IME.inputPending=true end
 end,debug.traceback)
 if not ok then recover_input(why)end
 if A.closing then close()else R.defer(loop)end
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

BLTShortcuts.install(R,gfx,{
 blocked=function() return BLT.presets.open or (BLT.host and (BLT.host.editing() or BLT.host.modal() or BLT.host.busy())) end,
 beforeGlobal=function(k) if BLT.host and BLT.host.beforeKey then BLT.host.beforeKey(k) end end,
 localKey=function(k,cap)
  return k==27 or ((cap&24)==0 and (k==26 or (cap&4)~=0 and (k==90 or k==122))) or (k==1 or k==6 or (cap&24)==0 and (k==3 or k==22 or (cap&4)~=0 and (k==67 or k==99 or k==86 or k==118)))
 end
})

loop()
