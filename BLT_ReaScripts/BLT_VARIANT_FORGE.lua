-- @description VARIANT FORGE
-- @version 0.6.6
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
   gradientNext=gradientNext%192+1
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
   if not e then serial=serial%192+1;local old=slots[serial];if old then gradients[old]=nil end;slots[serial]=key end
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
if type(reaper.ImGui_GetBuiltinPath)~='function'then reaper.MB('ReaImGui 0.10以降が必要です。 / ReaImGui 0.10 or later is required.','BLT Variant Forge',0);return end
local reaper,gfx=AppCanvas.install(reaper,gfx,AppCanvasHost,{section='BLT_VARIANT_FORGE',title='BLT Variant Forge',width=900,height=910,minWidth=780,minHeight=800},AppShellText,AppChromeRaster,AppCanvasDraw)
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

local function create_external_storage(api,section,source,state_keys)
 local P=setmetatable({}, {__index=api})
 local wanted={};for _,key in ipairs(state_keys) do wanted[key]='state' end
 wanted.preset_count='presets';for i=1,200 do wanted['preset_'..i]='presets' end
 local path=source:match('^@(.+)$')
 if not path and api.get_action_context then local _,p=api.get_action_context();if p and p~='' then path=p end end
 local base=path and path:match('^(.*)[.]lua$')
 local stores={};local warned={};local cap=268435456
 local function report(kind,detail)
  if warned[kind] then return end;warned[kind]=true
  local en=api.GetExtState(section,'ui_language')=='EN'
  api.MB((en and 'BLT could not save/load its data file. Check folder permissions and free disk space.\n\n' or 'BLTのデータファイルを保存・読み込みできません。フォルダの書き込み権限と空き容量を確認してください。\n\n')..tostring(detail),'BLT DATA',0)
 end
 local function exists(p)
  if api.file_exists then return api.file_exists(p) end
  local f=io.open(p,'rb');if f then f:close();return true end
  return os.rename(p,p) and true or false
 end
 local function value_limit(key)
  if key=='preset_count' then return 3 end
  if key=='curve_guide_data' then return 131072 end
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
   local key=raw:sub(b+1,b+klen);local value=raw:sub(b+klen+1,b+klen+vlen)
   if wanted[key] then
    if vlen>value_limit(key) then return nil,'Invalid data key/size: '..p end
    if values[key]~=nil then return nil,'Duplicate data record: '..p end
    if key=='preset_count' and (not value:match('^%d+$') or tonumber(value)>200) then return nil,'Invalid preset count: '..p end
    values[key]=value
   end
   pos=b+klen+vlen+1;count=count+1
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
  local raw,err=encode(values);local temp=s.path..'.tmp';local ok=false
  if raw then
   local f;f,err=io.open(temp,'wb')
   if f then
    local success,wrote,werr=pcall(f.write,f,raw);local closing,closed,cerr=pcall(f.close,f);if not closing then cerr=closed;closed=nil end
    if not success then werr=wrote;wrote=nil end
    if wrote and closed then
     local check;check,err=read(temp)
     if check then ok=true;for k,v in pairs(values) do if check[k]~=v then ok=false;err='Data verification failed';break end end end
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

local reaper=create_external_storage(reaper,'BLT_VARIANT_FORGE',debug.getinfo(1,'S').source,{'curve_guide_data'})

local BLTPresetLimits={bytes=16777216,stringBytes=2097152,nodes=262144,entries=8192}
function BLTPresetLimits.show(english)
 reaper.MB(english and 'Preset capacity limit exceeded. Export presets individually instead of as a bundle.' or '容量上限オーバーです。一括ではなく個別に保存してください。','BLT PRESET',0)
end

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
local Media,reaper=create_media_gate(reaper,gfx)

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
 ["選択素材を解析"]="Analyze items",
 ["GLOBAL APPLY / 一括"]="GLOBAL APPLY",
 ["RANDOM SYNC / 共通化"]="RANDOM SYNC",
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
 ["下限は上限以下にしてください："]="Minimum must not exceed maximum: ",
 ["STARTはEND以下にしてください："]="START must not exceed END: ",
 ["対象アイテムが無効です。"]="Invalid target item.",
 ["音声またはMIDIアイテムを選択してください。"]="Select audio or MIDI items.",
 ["MIDIアイテムはSOURCE解析の対象外です。"]="MIDI items do not support SOURCE analysis.",
 ["MIDIでは使用できません。"]="Unavailable for MIDI items.",
 ["MIDIでは全体ピッチ・タイミング・音量のみ使用できます。"]="MIDI supports Global Pitch, Timing, and Volume only.",
 ["MIDIの音量はベロシティ倍率として適用します。"]="MIDI volume is applied as a velocity multiplier.",
 ["MIDIの全体ピッチは半音単位へ丸めます。"]="MIDI global pitch is rounded to whole semitones.",
 ["MIDIでは疑似発音数を使用できません。"]="Voice limit is unavailable for MIDI items.",
 ["MIDIアイテム"]="MIDI item",
 ["音声ソースまたは長さを確認してください。"]="Check audio source and length.",
 ["音声を持たないアイテムは対象外です。"]="Items without audio are unsupported.",
 ["対象トラックを取得できません。"]="Cannot read target track.",
 ["元になる音声またはMIDIアイテムを選択してください。"]="Select source audio or MIDI items.",
 ["アイテムの状態を取得できません（大きなFX状態を含む場合は先に整理してください）。"]="Cannot read item state (reduce large FX state first if present).",
 ["音声アイテム参照がありません"]="Missing audio item reference",
 ["音声アイテム参照が無効です"]="Invalid audio item reference",
 ["音声Takeを取得できません"]="Cannot read audio take",
 ["音声ソースを取得できません"]="Cannot read audio source",
 ["音声ソース参照を更新できません"]="Cannot update audio source reference",
 ["音声ソース情報を取得できません"]="Cannot read audio source information",
 ["通常の音声ファイル以外"]="Not a regular audio file",
 ["反転・セクション・ストレッチ素材"]="Reversed / section / stretched source",
 ["ループまたはソース外の区間"]="Looped or outside source range",
 ["LUFS検出はモノ／ステレオのみ"]="LUFS detection: mono/stereo only",
 ["ソースが60分を超えています"]="Source exceeds 60 minutes",
 ["素材解析用の音声ソースを作成できません。"]="Cannot create source for analysis.",
 ["素材解析用の一時アイテムを作成できません。"]="Cannot create temporary analysis item.",
 ["素材解析用の一時アイテムを識別できません。"]="Cannot identify temporary analysis item.",
 ["素材解析用Takeを作成できません。"]="Cannot create analysis take.",
 ["素材解析用Takeへソースを設定できません。"]="Cannot assign source to analysis take.",
 ["素材解析用バッファを作成できません。"]="Cannot allocate source analysis buffer.",
 ["素材全体の音声アクセサを作成できません。"]="Cannot create full-source audio accessor.",
 ["素材全体を読み出せません。"]="Cannot read full source.",
 ["解析中にプロジェクトが切り替わりました。"]="Project switched during analysis.",
 ["解析中に元アイテムが削除されました。"]="Source item deleted during analysis.",
 ["解析中にプロジェクトが変更されました。"]="Project changed during analysis.",
 ["解析中に音声が変更されました。"]="Audio changed during analysis.",
 ["素材全体の音声取得に失敗しました。"]="Failed to read full-source audio.",
 ["検出区間 0：バリエーションなし"]="0 sections detected: no variations",
 ["元の使用区間が検出区間に含まれません"]="Original range is outside detected sections",
 ["山より前"]="Before peak",
 ["山より後"]="After peak",
 ["区間相対 %s %.1f%%"]="Section-relative %s %.1f%%",
 ["山オフセット %.1f ms"]="Peak offset %.1f ms",
 ["候補 %d（同一素材 %d / 同一トラック %d） / %s"]="Candidates %d (same source %d / same track %d) / %s",
 ["同一波形"]="Same waveform",
 ["同一トラック"]="Same track",
 ["候補数をクリック：同一波形 / 同一トラックを切替"]="Click candidate count: switch Same waveform / Same track",
 ["同一トラック候補は選択アイテムより前に終了する音声アイテムだけです。"]="Same-track candidates are audio items ending before the selected item.",
 ["SOURCE検出区間を削除しました。"]="SOURCE section deleted.",
 ["SOURCE検出区間を調整しました。"]="SOURCE section adjusted.",
 ["SOURCE検出区間を追加しました。"]="SOURCE section added.",
 ["既存区間と重なるため追加しませんでした。"]="Section was not added because it overlaps an existing section.",
 ["ズーム率リセット"]="Reset zoom",
 ["波形の時間軸ズームを全体表示へ戻します。"]="Reset waveform time zoom to full view.",
 ["再解析"]="Reanalyze",
 ["手動編集したSOURCE区間を破棄し、素材全体を再解析します。"]="Discard manual SOURCE edits and reanalyze the full source.",
 ["SOURCEを再解析しています。"]="Reanalyzing SOURCE.",
 ["Ctrl＋ホイール：時間軸ズーム / Shift＋ホイール：左右スクロール"]="Ctrl+wheel: time zoom / Shift+wheel: horizontal scroll",
 ["再生成のUndoを統合できません。生成後に別のUndo操作があります。"]="Cannot merge regeneration undo because another undoable edit occurred after generation.",
 ["クリック：区間選択 / 内側ドラッグ：区間移動 / 右クリック：削除"]="Click: select / Drag inside: move / Right-click: delete",
 ["ドラッグして時間を左右にスクロール"]="Drag to scroll horizontally",
 ["音声アイテム参照が無効です。"]="Invalid audio item reference.",
 ["音声Takeを取得できません。"]="Cannot read audio take.",
 ["スペクトル解析APIを利用できません。"]="Spectrum analysis API unavailable.",
 ["スペクトル解析用AudioAccessorを作成できません。"]="Cannot create spectrum audio accessor.",
 ["音声範囲を読み出せません。"]="Cannot read audio range.",
 ["解析する音声範囲が短すぎます。"]="Audio range too short for analysis.",
 ["解析範囲が無音です。"]="Analysis range is silent.",
 ["ラウドネスゲート内に解析可能な音声がありません。"]="No analyzable audio within the loudness gate.",
 ["スペクトルを取得できません。"]="Cannot read spectrum.",
 ["対象がありません。"]="No targets.",
 ["1回の生成は合計2000アイテムまでです。"]="Up to 2000 generated items per run.",
 ["ピッチカーブの尺連動は既存ストレッチマーカー付き素材には適用できません。"]="Linked pitch-curve duration cannot be applied to sources with stretch markers.",
 ["EQの表示値を読み取れません："]="Cannot read EQ display value: ",
 ["EQ値を設定できません。"]="Cannot set EQ value.",
 ["EQのパラメーター単位を取得できません。"]="Cannot read EQ parameter unit.",
 ["EQパラメーターを設定できません。"]="Cannot set EQ parameter.",
 ["ReaEQ (Cockos) を追加できません。"]="Cannot add ReaEQ (Cockos).",
 ["ReaEQ設定を読み取れません。"]="Cannot read ReaEQ state.",
 ["未対応のReaEQ設定形式です。"]="Unsupported ReaEQ state format.",
 ["ReaEQのバンド数を設定できません。"]="Cannot configure ReaEQ bands.",
 ["ReaEQの初期状態を設定できません。"]="Cannot initialize ReaEQ.",
 ["TEXTURE EQの焼き込みに必要なREAPER APIを利用できません。"]="REAPER API required to bake TEXTURE EQ is unavailable.",
 ["TEXTURE EQのFX位置を確認できません。"]="Cannot identify TEXTURE EQ FX position.",
 ["TEXTURE EQの焼き込みに失敗しました。\n"]="TEXTURE EQ bake failed.\n",
 ["TEXTURE EQの焼き込み結果を取得できません。"]="Cannot read TEXTURE EQ bake result.",
 ["焼き込みTakeのFXを整理できません。"]="Cannot clean up baked take FX.",
 ["TEXTURE EQの一時FXを削除できません。"]="Cannot remove temporary TEXTURE EQ FX.",
 ["焼き込みTakeを確定できません。"]="Cannot finalize baked take.",
 ["エンベロープを作成できません。"]="Cannot create envelope.",
 ["尺連動用ストレッチマーカーを書き込めません。"]="Cannot write rate-linked stretch markers.",
 ["ピッチ"]="Pitch",
 ["ピッチ変調を書き込めません。"]="Cannot write pitch modulation.",
 ["音量"]="Volume",
 ["自由配置モードを有効化できません。"]="Cannot enable free item positioning.",
 ["元アイテムの停止フェードを設定できません。"]="Cannot set source item stop fade.",
 ["複製アイテムを作成できません。"]="Cannot create duplicate item.",
 ["アイテムを複製できません。"]="Cannot duplicate item.",
 ["複製Takeを取得できません。"]="Cannot read duplicated take.",
 ["位置または長さを設定できません。"]="Cannot set position or length.",
 ["生成アイテムの停止フェードを設定できません。"]="Cannot set generated item stop fade.",
 ["Take設定に失敗しました："]="Take setting failed: ",
 ["MIDI音量を設定できません。"]="Cannot set MIDI velocity multiplier.",
 ["同一トラック候補の元アイテムが見つかりません。"]="Same-track candidate source item not found.",
 ["同一トラック候補の音声Takeを取得できません。"]="Cannot read same-track candidate take.",
 ["同一トラック候補の音声ソースを取得できません。"]="Cannot read same-track candidate source.",
 ["同一トラック候補へ音声ソースを切り替えられません。"]="Cannot switch to same-track candidate source.",
 ["同一トラック候補の音声ソースを確認できません。"]="Cannot verify same-track candidate source.",
 ["同一トラック候補の音声ソース切替を確認できません。"]="Cannot verify source switch for same-track candidate.",
 ["素材バリエーションの音声ソースを作成できません。"]="Cannot create source variation audio.",
 ["素材バリエーションへ音声ソースを切り替えられません。"]="Cannot switch to source variation audio.",
 ["作成を中止し、今回のコピーを削除しました。\n"]="Generation stopped; copies from this run deleted.\n",
 ["処理を中止しました。コピーの削除に失敗したためUndoで戻してください。"]="Stopped, but copy deletion failed. Use Undo.",
 ["CHAMELEON  REAPERテーマに擬態"]="CHAMELEON  REAPER theme",
 ["CHAMELEON  オリジナル配色"]="CHAMELEON  Original colors",
 ["カスタムタイトルバーには js_ReaScriptAPI が必要です。\nReaPack から js_ReaScriptAPI をインストールしてください。"]="The app bar requires js_ReaScriptAPI.\nInstall js_ReaScriptAPI via ReaPack.",
 ["素材を解析中..."]="Analyzing sources...",
 ["全体ピッチ"]="Global pitch",
 ["ピッチ曲線"]="Pitch curve",
 ["ビブラート"]="Vibrato",
 ["トレモロ"]="TREMOLO",
 ["タイミング"]="Timing",
 ["定位"]="Pan",
 ["質感EQ"]="Texture EQ",
 ["トーンEQ"]="Tone EQ",
 ["素材"]="Source",
 ["解析待ち"]="Pending",
 ["入力できなかったため、元の疑似発音数へ戻しました。"]="Invalid input. Previous voice limit restored.",
 ["：入力できなかったため、元の値へ戻しました。"]=": invalid input; previous value restored.",
 ["：設定値を確定できません。"]=": cannot confirm setting.",
 ["：クリック入力 / 上下ドラッグ / ホイール変更"]=": click to type / Drag vertically / Wheel",
 [" / Shiftで微調整"]=" / Shift: fine adjust",
 ["ドラッグでDRAWモードへ"]="Drag to enter DRAW mode",
 ["ALT+CLICKでもう1点"]="ALT+CLICK to add a point",
 ["点をドラッグ=移動 / Alt+クリック=追加 / Ctrl+クリック=削除 / 空所ドラッグ=線を追加 / 中央=0 st"]="Drag point: move / Alt+click: add / Ctrl+click: delete / Drag empty area: draw / Center: 0 st",
 [" タブ"]=" tab",
 ["疑似発音数"]="Voice limit",
 ["疑似発音数：∞ = 制限なし / 1～"]="Voice limit: ∞ = unlimited / 1–",
 ["。クリック入力 / 上下ドラッグ / ホイール変更"]=". Click to type / Drag vertically / Wheel",
 ["疑似発音数を1段階増やす（∞ → 1）"]="Increase voice limit one step (∞ → 1)",
 ["疑似発音数を1段階減らす（1 → ∞）"]="Decrease voice limit one step (1 → ∞)",
 ["全アイテムの疑似発音数を相対的に1段階増やす"]="Increase all voice limits one step relatively",
 ["全アイテムの疑似発音数を相対的に1段階減らす"]="Decrease all voice limits one step relatively",
 ["未解析・更新された素材を解析しています。完了後に自動で生成します。"]="Analyzing new or updated sources. Generation starts automatically afterward.",
 ["%dバリエーション / %dアイテムを作成 · SEED %d%s"]="Created %d variations / %d items · SEED %d%s",
 [" · 素材 %d"]=" · Sources %d",
 ["素材バリエーションの事前解析が完了していません。"]="Source variation pre-analysis is incomplete.",
 ["バリエーションなし"]="No variations",
 ["実行前の素材再解析を中止しました。"]="Pre-generation source analysis stopped.",
 ["合計2000アイテム以下にしてください。"]="Keep total at 2000 items or fewer.",
 ["素材バリエーションの事前解析中です。"]="Source variation pre-analysis in progress.",
 ["焼き込める直前の生成結果がありません。"]="No recent generated result to bake.",
 ["焼き込み待ちのTEXTURE FXはありません。"]="No TEXTURE FX waiting to be baked.",
 ["焼き込み対象が変更されました。"]="Bake targets changed.",
 ["FX焼込に失敗しました。Undoで焼き込み前へ戻してください。生成途中のWAVは参照が外れた後に自動回収します。"]="FX bake failed. Use Undo to restore. Incomplete WAVs are cleaned up when no longer referenced.",
 ["TEXTURE FXを%dアイテムへ焼き込みました。再生成は引き続き使用できます。"]="Baked TEXTURE FX into %d items. Regeneration remains available.",
 ["再生成できる直前の生成結果がありません。"]="No recent result to regenerate.",
 ["再生成元のアイテム情報がありません。生成し直してください。"]="Missing source item information. Generate again.",
 ["元アイテムが削除されているため再生成できません。現在の生成結果は残しました。"]="Source items deleted. Cannot regenerate; existing result retained.",
 ["素材の再解析中に対象またはプロジェクトが変わったため、実行を中止しました。"]="Targets or project changed during source reanalysis. Stopped.",
 ["：再解析後に素材バリエーションを使用できません。"]=": source variations unavailable after reanalysis.",
 ["解析中にプロジェクトが変更"]="Project changed during analysis",
 ["解析中にプロジェクトが切り替わり"]="Project switched during analysis",
 ["解析中に元アイテムが削除"]="Source item deleted during analysis",
 ["解析中に音声が変更"]="Audio changed during analysis",
 ["TEXTURE EQ参照の解析に失敗しました。"]="TEXTURE EQ reference analysis failed.",
 ["TEXTURE EQの参照にする音声アイテムを1～10個選択してください。"]="Select 1 to 10 audio items as TEXTURE EQ references.",
 ["TEXTURE EQの参照素材は最大%d個です。\n現在 %d個 選択されています。"]="TEXTURE EQ supports at most %d references.\nCurrently selected: %d.",
 ["%d番目の選択アイテムを解析できません。\n%s"]="Cannot analyze selected item %d.\n%s",
 ["音声アイテムを選択してください。"]="Select audio items.",
 ["%d番目の選択アイテムはMIDIです。\nTEXTURE EQ参照には音声アイテムを使用してください。"]="Selected item %d is MIDI.\nUse audio items for TEXTURE EQ references.",
 ["TEXTURE EQ参照には長すぎる素材があります。\n\n%s\n%.2f 秒\n\n1素材あたり最大 %d 秒です。"]="TEXTURE EQ reference is too long.\n\n%s\n%.2f s\n\nMaximum per source: %d s.",
 ["%s のスペクトルを解析できません。\n%s"]="Cannot analyze spectrum of %s.\n%s",
 ["素材 "]="Source ",
 ["周波数情報を取得できません。"]="Cannot read frequency information.",
 ["TEXTURE EQ：%d素材を解析・登録しました。"]="TEXTURE EQ: analyzed and registered %d sources.",
 ["TEXTURE EQの参照素材をクリアしました。"]="TEXTURE EQ references cleared.",
 ["未設定 · AUTO TEXTURE"]="Not set · AUTO TEXTURE",
 ["TEXTURE素材"]="TEXTURE SOURCE",
 ["未設定時はAUTO TEXTUREを使用。参照を使う場合は1～10個の音声アイテムを選択して解析・設定します。"]="Without references, use AUTO TEXTURE. To add references, select and analyze 1 to 10 audio items.",
 ["トラック / アイテム名"]="TRACK / ITEM NAME",
 ["GLOBAL APPLY   /   一括 ON / OFF"]="GLOBAL APPLY / All ON / OFF",
 ["全項目をまとめてON/OFF"]="Toggle all features",
 ["使用可能な素材バリエーションがあるアイテムだけを一括ON/OFF"]="Toggle only items with usable source variations",
 ["この機能を使用できる選択アイテムだけを一括ON/OFF"]="Toggle this feature only for compatible selected items",
 ["クリック選択 / Ctrl(Cmd)で追加・解除 / Shiftで範囲選択"]="Click: select / Ctrl(Cmd): toggle / Shift: range",
 ["素材バリエーション"]="Source variations",
 ["解析"]="Analyze",
 ["解析中"]="Scan…",
 ["待機中"]="Queued",
 ["解析完了後、使用可能ならSOURCEがONになります。"]="SOURCE turns on after analysis if variations are available.",
 ["クリックで素材全体を解析し、使用可能ならSOURCEをONにします。"]="Click to analyze the full source and enable available variations.",
 ["SOURCE欄の「解析」を押すと素材解析を開始します。"]="Click Analyze in the SOURCE column to scan the source.",
 ["使用可能 1（元のみ）：追加候補がありません"]="1 usable (original only): no alternatives",
 ["使用可能 1（元のみ）：他候補は対象外の素材です"]="1 usable (original only): other sources are unsupported",
 ["素材全体をラウドネス解析中…"]="Analyzing full-source loudness...",
 ["選択中の全アイテムへ同じON/OFFを適用"]="Apply the same ON/OFF to all selected items",
 ["このアイテムへ適用"]="Apply to this item",
 ["クリックでスクロール位置を移動"]="Click to jump scroll position",
 ["ドラッグしてスクロール"]="Drag to scroll",
 ["RANDOM SYNC   /   Variation内のランダム値を共通化"]="RANDOM SYNC / Per variation",
 ["ON：この列のランダム値をVariation内で共通化"]="ON: share this column's random value within each variation",
 ["一定"]="Flat",
 ["強く"]="Stronger",
 ["弱く"]="Weaker",
 ["深さL"]="D.L",
 ["深さH"]="D.H",
 ["速度L"]="R.L",
 ["速度H"]="R.H",
 ["ポイント数"]="Points",
 ["SOURCE VARIATIONS  素材から様々なバリエーションを生成"]="SOURCE VARIATIONS  Generate variations from audio",
 ["選択"]="Selected",
 ["生成数"]="Count",
 ["組"]=" sets",
 ["間隔"]="Spacing",
 ["末尾→先頭"]="End → Start",
 ["先頭→先頭"]="Start → Start",
 ["停止フェード"]="Stop fade",
 ["乱数シード"]="Random seed",
 ["シード固定"]="Lock seed",
 ["下限"]="Min",
 ["上限"]="Max",
 ["尺固定"]="Keep",
 ["尺連動"]="Link",
 ["選出"]="Pick",
 ["シャッフル"]="Shuffle",
 ["順次"]="In order",
 ["位置"]="Pos",
 ["区間相対"]="Relative",
 ["絶対"]="Absolute",
 ["変調コントロール"]="MODULATION",
 ["クリア"]="Clear",
 ["描いたガイドを消してRNDモードへ戻す"]="Clear drawn guide and return to RND mode",
 ["−側下限"]="Min. -",
 ["＋側上限"]="Max. +",
 ["カーブポイント数（ランダム時）"]="Curve points (random)",
 ["テクスチャEQ"]="TEXTURE EQ",
 ["選択素材を解析・設定"]="Analyze sources",
 ["REAPERで現在選択中の音声素材の周波数特性を解析・登録。最大10素材 / 各60秒"]="Analyze/register frequency profiles of selected REAPER audio. Up to 10 sources, 60 s each.",
 ["登録済みTEXTURE参照素材をすべてクリア"]="Clear all TEXTURE references",
 ["前のTEXTURE参照素材"]="Previous TEXTURE reference",
 ["次のTEXTURE参照素材"]="Next TEXTURE reference",
 ["強度"]="Strength",
 ["トーン補正"]="Tone correction",
 ["強さ 下限"]="Min. strength",
 ["素材全体をラウドネス解析中… %d%%"]="Full-source loudness analysis... %d%%",
 ["対象をロック"]="Lock targets",
 ["ロック解除"]="Unlock targets",
 ["現在選択中のアイテムを対象として固定。選択が変わっても対象を維持します。"]="Lock the currently selected items as targets even if selection changes.",
 ["対象ロックを解除して、現在の選択へ戻します。"]="Unlock targets and follow the current selection again.",
 ["対象をロックしました。"]="Targets locked.",
 ["対象ロックを解除しました。"]="Targets unlocked.",
 ["ロック対象が変更または削除されたため、対象ロックを解除しました。"]="Target lock released because a locked item changed or was deleted.",
 ["ロックするアイテムを選択してください。"]="Select items to lock.",
 ["バリエーションを再生成"]="Regenerate variations",
 ["処理を中止"]="Stop",
 ["%d バリエーションを生成"]="Generate %d variations",
 ["Enter：生成。SOURCEの事前解析中は完了後に実行できます。"]="Enter: generate. Wait for SOURCE pre-analysis to finish.",
 ["直前生成のTEXTURE EQだけを音声へ焼き込み、FX負荷を軽減"]="Bake only the latest TEXTURE EQ into audio to reduce FX load",
 ["素材の事前解析を中止しました。"]="Source pre-analysis stopped.",
 ["BLT Variant Forge | エラー"]="BLT Variant Forge | Error",
 ["カスタム枠を初期化できません。"]="Cannot initialize the custom frame.",
 ["表示言語を切替（JP / EN）"]="Switch language (JP / EN)",
 ["プリセットを読み込みました: ファクトリーデフォルト"]="Loaded: Factory Default",
},patterns={
 {"^「(.*)」を上書きしますか？$","Overwrite \"%s\"?"},
 {"^([%+%-]?[%d%.eE]+)–([%+%-]?[%d%.eE]+) / ([%+%-]?[%d%.eE]+)   スクロールで選択$","%d–%d / %d   Scroll to browse"},
 {"^解析中%.%.%.([%+%-]?[%d%.eE]+)%%$","Analyzing...%d%%"},
 {"^検出区間 ([%+%-]?[%d%.eE]+) / 使用可能 1：バリエーションなし$","Detected %d / Usable 1: no variations"},
 {"^区間相対 (.-) ([%+%-]?[%d%.eE]+)%%$","Section-relative %s %.1f%%",{1}},
 {"^山オフセット ([%+%-]?[%d%.eE]+) ms$","Peak offset %.1f ms"},
 {"^候補 ([%+%-]?[%d%.eE]+)（同一素材 ([%+%-]?[%d%.eE]+) / 同一トラック ([%+%-]?[%d%.eE]+)） / (.-)$","Candidates %d (same source %d / same track %d) / %s",{4}},
 {"^([%+%-]?[%d%.eE]+)バリエーション / ([%+%-]?[%d%.eE]+)アイテムを作成 · SEED ([%+%-]?[%d%.eE]+)(.-)$","Created %d variations / %d items · SEED %d%s",{4}},
 {"^ · 素材 ([%+%-]?[%d%.eE]+)$"," · Sources %d"},
 {"^TEXTURE FXを([%+%-]?[%d%.eE]+)アイテムへ焼き込みました。再生成は引き続き使用できます。$","Baked TEXTURE FX into %d items. Regeneration remains available."},
 {"^TEXTURE EQの参照素材は最大([%+%-]?[%d%.eE]+)個です。\n現在 ([%+%-]?[%d%.eE]+)個 選択されています。$","TEXTURE EQ supports at most %d references.\nCurrently selected: %d."},
 {"^([%+%-]?[%d%.eE]+)番目の選択アイテムを解析できません。\n(.-)$","Cannot analyze selected item %d.\n%s",{2}},
 {"^TEXTURE EQ参照には長すぎる素材があります。\n\n(.-)\n([%+%-]?[%d%.eE]+) 秒\n\n1素材あたり最大 ([%+%-]?[%d%.eE]+) 秒です。$","TEXTURE EQ reference is too long.\n\n%s\n%.2f s\n\nMaximum per source: %d s."},
 {"^(.-) のスペクトルを解析できません。\n(.-)$","Cannot analyze spectrum of %s.\n%s",{2}},
 {"^TEXTURE EQ：([%+%-]?[%d%.eE]+)素材を解析・登録しました。$","TEXTURE EQ: analyzed and registered %d sources."},
 {"^区間 ([%+%-]?[%d%.eE]+)/([%+%-]?[%d%.eE]+)$","Section %d/%d"},
 {"^素材全体をラウドネス解析中… ([%+%-]?[%d%.eE]+)%%$","Full-source loudness analysis... %d%%"},
 {"^([%+%-]?[%d%.eE]+) バリエーションを生成$","Generate %d variations"},
 {"^「(.-)」を上書きしますか？$","\"%s\"?"},
 {"^(.-)」を上書きしますか？$","%s\"?"},
 {"^プリセットを保存しました: (.-)$","Saved: %s"},
 {"^プリセットを読み込みました: (.-)$","Loaded: %s"},
 {"^(.-)個インポートしました。$","%s preset(s) imported."},
 {"^現在: (.-)(.-)$","Current: %s%s"},
 {"^設定値が範囲外です：(.-)$","Setting out of range: %s"},
 {"^下限は上限以下にしてください：(.-)$","Minimum must not exceed maximum: %s"},
 {"^STARTはEND以下にしてください：(.-)$","START must not exceed END: %s"},
 {"^EQの表示値を読み取れません：(.-)$","Cannot read EQ display value: %s"},
 {"^TEXTURE EQの焼き込みに失敗しました。\n(.-)$","TEXTURE EQ bake failed.\n%s"},
 {"^Take (.-)エンベロープを作成できません。$","Take %sCannot create envelope."},
 {"^(.-)エンベロープを作成できません。$","%sCannot create envelope."},
 {"^Take設定に失敗しました：(.-)$","Take setting failed: %s"},
 {"^作成を中止し、今回のコピーを削除しました。\n(.-)$","Generation stopped; copies from this run deleted.\n%s"},
 {"^(.-)：入力できなかったため、元の値へ戻しました。$","%s: invalid input; previous value restored."},
 {"^(.-)：設定値を確定できません。$","%s: cannot confirm setting."},
 {"^(.-)：クリック入力 / 上下ドラッグ / ホイール変更$","%s: click to type / Drag vertically / Wheel"},
 {"^(.-) / Shiftで微調整$","%s / Shift: fine adjust"},
 {"^(.-) タブ$","%s tab"},
 {"^疑似発音数：∞ = 制限なし / 1～(.-)。クリック入力 / 上下ドラッグ / ホイール変更$","Voice limit: ∞ = unlimited / 1–%s. Click to type / Drag vertically / Wheel"},
 {"^(.-)。クリック入力 / 上下ドラッグ / ホイール変更$","%s. Click to type / Drag vertically / Wheel"},
 {"^(.-)：再解析後に素材バリエーションを使用できません。$","%s: source variations unavailable after reanalysis."},
 {"^素材 (.-)$","Source %s"},
 {"^「(.*)」を上書きしますか？$","Overwrite \"%s\"?"},
 {"^(%d+)個インポートしました。$","Imported %s preset(s)."},
 {"^(%d+)件をノーマライズしました。選択を解除しました。$","Normalized %s items and deselected them."},
},prefixes={"TEXTURE EQの焼き込みに失敗しました。\n","作成を中止し、今回のコピーを削除しました。\n","STARTはEND以下にしてください：","プリセットを読み込みました: ","下限は上限以下にしてください：","EQの表示値を読み取れません：","プリセットを保存しました: ","Take設定に失敗しました：","設定値が範囲外です：","現在: "}}

LanguageCatalog.en['生成を中止しました。']='Generation cancelled.'
LanguageCatalog.en['生成を中止し、今回のコピーを削除しました。']='Cancelled. This generation’s copies were removed.'
LanguageCatalog.en['生成対象が変更されたため中止しました。']='Cancelled because the generation targets changed.'

local Language=create_language(reaper,"BLT_VARIANT_FORGE",LanguageCatalog)
local R=reaper
local CanvasGraphics={}
function CanvasGraphics.new(gfx,font)
 local G={}
 function G.setfont(_,face,size,flags)font(face,size,flags)end
 return setmetatable(G,{__index=function(_,key)if key=='mouse_wheel'then return 0 end;return gfx[key]end,
  __newindex=function(_,key,value)if key~='mouse_wheel'then gfx[key]=value end end})
end

local VariantControls=(function()
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
 function U:lockFrame(id,value,x,y,w,h,opt)
  opt=opt or empty;local s=self:state(id);local enabled=opt.enabled~=false
  if enabled and value and s.lockValue==false then s.sparkAt=self.now end
  s.lockValue=not not value
  if not value or not enabled then s.sparkAt=nil;return false end
  local P=self.themeEnabled and self.themeTones and self.themeTones.gold or gold
  local k=min(10,floor(min(w,h)*.21))
  if opt.fill~=0 then self:shape(x,y,w,h,k,P.accent,opt.fill or .035,true)end
  self:shape(x,y,w,h,k,P.rim or P.ice,opt.alpha or .48,false)
  self:electricFlash(s,x,y,w,h,true,P)
  return s.sparkAt~=nil
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

local VariantHeaderIcon=(function()
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

local VariantIconDefinition=(function()
local M={width=94,height=70,modes={'variations'}}
local sin,cos,pi=math.sin,math.cos,math.pi
local bars={3,7,11,6,4,9,5,8,3}
local function hash(n,salt)return (sin(n*12.9898+salt*78.233)*43758.5453)%1 end
function M.update()end
local function box(p,x,y,w,h)
 local C=p.C;local k=3
 p:rect(x,y,w,h,C.field,.65)
 p:line(x,y,x+w-k,y,C.edge2,.45);p:line(x+w-k,y,x+w,y+k,C.edge2,.45)
 p:line(x+w,y+k,x+w,y+h,C.edge2,.35);p:line(x+w,y+h,x+k,y+h,C.edge2,.35)
 p:line(x+k,y+h,x,y+h-k,C.edge2,.35);p:line(x,y+h-k,x,y,C.edge2,.45)
end
function M.draw(p,s,_,time)
 local C=p.C
 for i=1,8 do
  local phase=time*(.10+(i%3)*.018)+i*1.47
  local x,y=49+sin(phase*1.09)*(20+(i%2)*6),31+cos(phase*.79)*(9+(i%3)*2)
  local r=10+(i%4)*3
  p:disc(x,y,r+10,C.accent,.009);p:disc(x,y,r+3,C.accent3,.014)
  p:disc(x+1.5,y-1,r*.48,C.ice,.012)
 end
 box(p,1,21,22,20)
 p:line(23,31,45,31,C.edge2,.24)
 for lane=0,2 do
  local y=5+lane*24
  p:line(45,31,52,y+7,C.edge2,.25)
  box(p,53,y,40,15)
  for i=1,#bars do local h=bars[(i+lane*3-1)%#bars+1]*.34
   p:line(58+(i-1)*3.2,y+7-h,58+(i-1)*3.2,y+7+h,C.ice,.62)
  end
 end
 p:line(8,31,17,31,C.ice,.65);p:line(12,27,12,35,C.ice,.65)
end
function M.emit(_,n,p)
 local a,b,c,d=hash(n,21),hash(n,22),hash(n,23),hash(n,24)
 p.lane=(n-1)%3;p.startY=31+(a-.5)*9;p.arch=(d-.5)*15
 p.phase,p.life,p.r,p.glint=c*pi*2,2.4+b*1.1,.45+a*.65,n%5==0
end
function M.sample(_,p,age)
 local t=math.min(1,age/p.life);local u=t*t*(3-2*t)
 return 18+64*u+sin(age*.63+p.phase)*2*(1-u),p.startY+(12+p.lane*24-p.startY)*u+sin(pi*u)*p.arch
end
return M
end)()

local BLT=(function()
local B={fitCache={},fitCount=0,metrics={},metricCount=0,specs={}}
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

function B.spec(size,kind,bold,s)
 kind=kind or 1;local px=math.max(8,math.floor((size or 10)*s+.5));local weight=bold and 98 or 0
 local g=kind*2+(bold and 1 or 0);local sizes=B.specs[g]
 if not sizes then sizes={};B.specs[g]=sizes end
 local r=sizes[px];if not r then r={kind,px,weight,kind..':'..px..':'..weight};sizes[px]=r end
 return r[1],r[2],r[3],r[4]
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
function UI.bar(w) return BLTChrome.layout(w,host.fold~=nil,host.compactChrome and host.compactChrome() or false) end
local function gfx_window_handle() return host.handle() end
local function chrome_resize_hit(x,y) if y<26 and x>=UI.bar(gfx.w).presetX then return nil end;return host.resizeHit(x,y) end
local function set_resize_cursor(mode) host.cursor(mode) end
local function begin_window_resize(mode) host.beginResize(mode) end
local function update_window_resize() host.resize() end
local function clear_chrome_tooltip() B.popupUntil=nil;if R.TrackCtl_SetToolTip then R.TrackCtl_SetToolTip('',0,0,true) end end
B.clearTooltip=clear_chrome_tooltip
function B.blend(dt)
 if B.blendDt~=dt then B.blendDt=dt;B.blendValue=1-math.exp(-12*dt) end
 return B.blendValue
end
function Presets.menu(x,y)
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
  local inBar=(host.active() or (gfx.getchar(65536)&8)~=0) and not blocked and inWindow and my<Chrome.titleH
  local resizeMode=not blocked and chrome_resize_hit(mx,my) or nil
  local resizing=Chrome.resize~=nil
  local cursorMode=resizing and Chrome.resize.mode or resizeMode
  set_resize_cursor(cursorMode)
  local control=inBar and not resizeMode and not resizing and BLTChrome.hit(b,mx,my,w,Chrome.titleH) or nil
  local hoverClose=control=='close'
  local hoverReset=not (host.collapsed and host.collapsed()) and not (host.transition and host.transition()) and control=='reset'
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
    elseif inBar and not (host.transition and host.transition()) then
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
 return Presets.open or Presets.swallow or (gfx.mouse_y>=0 and gfx.mouse_y<26)
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
  if my>=0 and my<26 then
   local b=UI.bar(gfx.w)
   tip=mx>=b.closeX and '閉じる' or mx>=b.resetX and 'ウィンドウサイズ初期化' or mx>=b.themeX and 'カメレオンモード' or b.foldX and mx>=b.foldX and '縮小／展開' or mx>=b.languageX and '表示言語を切替（JP / EN）' or mx>=b.nextX and '次のプリセット' or mx>=b.prevX and '前のプリセット' or mx>=b.presetX and 'プリセット（読込・保存・インポート／エクスポート）' or nil
  elseif B.footerBounds and B.footerClipped then local r=B.footerBounds;if mx>=r[1] and mx<=r[3] and my>=r[2] and my<=r[4] then tip=B.footerText end end
 end
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
  if R.ShowConsoleMsg then pcall(R.ShowConsoleMsg,message..'\n') end
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
  local down=((gfx.mouse_cap or 0)&1)~=0
  local hit=gfx.mouse_y>=0 and gfx.mouse_y<26 and gfx.mouse_x>=gfx.w-38 and gfx.mouse_x<gfx.w
  if down and not B.emergencyDown then B.emergencyClose=hit end
  if not down and B.emergencyDown then
   if B.emergencyClose and hit then Chrome.requestClose=true end
   B.emergencyClose=nil
  end
  B.emergencyDown=down
 else B.emergencyDown=nil;B.emergencyClose=nil end
 pcall(B.footer,B.publicError(err),true,gfx.w,0,B.footerVersion or '')
 pcall(gfx.update)
 if Chrome.requestClose then state.closing=true end
 state.content_dirty=true
 B.cleanup(host.wake)
 B.logError(err)
end

function B.title(title,subtitle,width,divider)
 gfx.textRoute(true)
 scale,ox,oy=host.geometry();local origin=oy+22*scale
 local layout=B.titleLayout;local dpi=gfx.ext_retina or 1
 if not layout or layout.width~=width or layout.scale~=scale or layout.dpi~=dpi or layout.title~=title or layout.face~=host.faces[2]then
  local size=35;B.font(size,2,true,scale,host.faces)
  while size>26 and gfx.measurestr(title)>(width-150)*scale do size=size-1;B.font(size,2,true,scale,host.faces)end
  layout={width=width,scale=scale,dpi=dpi,title=title,face=host.faces[2],size=size};B.titleLayout=layout
 else B.font(layout.size,2,true,scale,host.faces)end
 gfx.set(C.text[1],C.text[2],C.text[3],1);gfx.x=ox+24*scale;gfx.y=origin+8*scale;gfx.drawstr(UI.fit(title,(width-150)*scale))
 B.font(10,1,false,scale,host.faces);gfx.set(C.accent2[1],C.accent2[2],C.accent2[3],1);gfx.x=math.floor(ox+26*scale+.5);gfx.y=math.floor(origin+44*scale+.5);gfx.drawstr(UI.fit(Language.text(subtitle),(width-155)*scale))
 if divider~=false then gfx.set(C.edge2[1],C.edge2[2],C.edge2[3],.26);gfx.line(ox+24*scale,origin+62*scale,ox+(width-24)*scale,origin+62*scale,1) end
 gfx.textRoute(false)
end

function B.footer(message,bad,width,height,version,progress)
 gfx.textRoute(true)
 if Media.waiting then message=Media.message(host.section);bad=false;progress=nil end
 if version~='' then B.footerVersion=version end
 scale,ox,oy=host.geometry();message=Language.message(B.notice or tostring(message or ''))
 if B.notice then bad=B.noticeBad end
 local y=math.floor(oy+(height-13)*scale+.5)
 B.font(8,3,true,scale,host.faces);local ver=version~='' and 'v'..version or '';local vw=UI.textMetrics(ver)
 local available=(width-48)*scale-vw-14*scale-(host.footerReserve and host.footerReserve()or 0)*scale
 local progressing=type(progress)=='number'
 B.font(8,1,false,scale,host.faces);local shown=progressing and '' or UI.fit(message,available)
 B.footerText=progressing and '' or message;B.footerClipped=not progressing and shown~=message;B.footerBounds={ox+24*scale,y,ox+24*scale+available,y+14*scale}
 gfx.set(C.edge[1],C.edge[2],C.edge[3],.26);gfx.line(ox+24*scale,y-3*scale,ox+(width-24)*scale,y-3*scale)
 if progressing then
  local fraction=math.max(0,math.min(1,progress))
  local caption=string.format(Language.text('解析中...%d%%'),math.floor(fraction*100+.5))
  local captionWidth=UI.textMetrics(Language.text('解析中...100%'))
  gfx.set(C.muted[1],C.muted[2],C.muted[3],1);gfx.x=ox+24*scale;gfx.y=y;gfx.drawstr(caption)
  local x=ox+24*scale+captionWidth+10*scale;local barY=y+3*scale;local barH=6*scale
  local barW=math.max(0,math.min(available,(width-48)*scale*.45)-captionWidth-10*scale)
  gfx.set(C.field[1],C.field[2],C.field[3],1);gfx.rect(x,barY,barW,barH,1)
  gfx.set(C.accent2[1],C.accent2[2],C.accent2[3],.95);gfx.rect(x,barY,barW*fraction,barH,1)
  gfx.set(C.muted[1],C.muted[2],C.muted[3],.5);gfx.rect(x,barY,barW,barH,0)
 else
  local c=bad and C.warn or C.muted;gfx.set(c[1],c[2],c[3],1);gfx.x=ox+24*scale;gfx.y=y;gfx.drawstr(shown)
 end
 B.font(8,3,true,scale,host.faces);gfx.set(C.faint[1],C.faint[2],C.faint[3],1);gfx.x=ox+(width-24)*scale-vw;gfx.y=y;gfx.drawstr(ver)
 gfx.textRoute(false)
end
return B
end)()

local Core={VERSION='0.6.6',SOURCE_SR=48000,SOURCE_HOP=48,SOURCE_BLOCK=12000,SOURCE_PREVIEW_BINS=1400,SOURCE_MAX_REGIONS=16384,
 GENERATED_TAG='P_EXT:BLT_VARIANT_FORGE',TEMP_TAG='P_EXT:BLT_VARIANT_FORGE_TEMP',SECTION='BLT_VARIANT_FORGE',EQ_FIXED_CACHE={}}
Core.STALE_TEMP_PROJECTS={};Core.RUN_ID='';Core.TEMP_HEARTBEAT_TTL=8;Core.TEMP_HEARTBEAT_KEY='temp_live_registry_v1';Core.temp_heartbeat_at=0
local abs,min,max,floor,ceil=math.abs,math.min,math.max,math.floor,math.ceil
local function finite(n) return type(n)=='number' and n==n and abs(n)<math.huge end
local function clamp(n,a,b) return max(a,min(b,n)) end
local function db(x) return x>1e-12 and 20*math.log(x,10) or -240 end
local function copy(t) local o={};for k,v in pairs(t) do o[k]=v end;return o end
local function tcopy(t) local o={};for k,v in pairs(t or {}) do o[k]=type(v)=='table' and tcopy(v) or v end;return o end
Core.FEATURES={'pitch_global','pitch_curve','vibrato','tremolo','timing','volume','pan','eq_texture','eq_tone','source'}
Core.MIDI_FEATURES={pitch_global=true,timing=true,volume=true}
function Core.feature_supported(v,key) return not (v and v.is_midi) or Core.MIDI_FEATURES[key]==true end
local function midi_semitone(v) return v>=0 and floor(v+.5) or ceil(v-.5) end
Core.defaults={
 count=5,interval_mode=1,interval=0.1,voice_fade_ms=30,seed=18273,seed_lock=false,
 pitch_lo=-1,pitch_hi=1,pitch_length_mode=1,
 curve_lo=-1,curve_hi=1,curve_points=5,curve_length_mode=1,curve_start_pct=0,curve_end_pct=100,
 curve_guide_enabled=false,curve_guide_start=0,curve_guide_end=0,curve_guide_data='',curve_tab=1,
 vibrato_depth_lo=.15,vibrato_depth_hi=.45,vibrato_rate_lo=4.5,vibrato_rate_hi=7.5,vibrato_start_pct=0,vibrato_end_pct=100,vibrato_shape=1,
 tremolo_depth_lo=2,tremolo_depth_hi=6,tremolo_rate_lo=3,tremolo_rate_hi=7,tremolo_start_pct=0,tremolo_end_pct=100,tremolo_shape=1,
 timing_lo=-20,timing_hi=20,
 volume_lo=-2,volume_hi=0,pan_lo=-15,pan_hi=15,
 texture_strength=100,
 tone_lo=-2,tone_hi=2,tone_bright=true,tone_dark=true,tone_forward=true,tone_recessed=true,
 source_order=1,source_timing_mode=2}
Core.ranges={
 count={1,128,1},interval_mode={1,2,1},interval={0,60},voice_fade_ms={0,2000},seed={1,2147483646,1},
 pitch_lo={-48,48},pitch_hi={-48,48},pitch_length_mode={1,2,1},
 curve_lo={-24,0},curve_hi={0,24},curve_points={2,24,1},curve_length_mode={1,2,1},curve_start_pct={0,100,1},curve_end_pct={0,100,1},
 curve_guide_start={-1,1},curve_guide_end={-1,1},curve_tab={1,3,1},
 vibrato_depth_lo={0,12},vibrato_depth_hi={0,12},vibrato_rate_lo={.1,20},vibrato_rate_hi={.1,20},vibrato_start_pct={0,100,1},vibrato_end_pct={0,100,1},vibrato_shape={1,3,1},
 tremolo_depth_lo={0,24},tremolo_depth_hi={0,24},tremolo_rate_lo={.1,20},tremolo_rate_hi={.1,20},tremolo_start_pct={0,100,1},tremolo_end_pct={0,100,1},tremolo_shape={1,3,1},
 timing_lo={-2000,2000},timing_hi={-2000,2000},volume_lo={-24,12},volume_hi={-24,12},
 pan_lo={-100,100},pan_hi={-100,100},texture_strength={1,200,1},
 tone_lo={-18,18},tone_hi={-18,18},source_order={1,2,1},source_timing_mode={1,2,1}}
Core.precision={}
for key,range in pairs(Core.ranges) do Core.precision[key]=range[3] and 0 or 2 end
for _,key in ipairs({'voice_fade_ms','timing_lo','timing_hi','pan_lo','pan_hi'}) do Core.precision[key]=0 end
Core.precision.curve_guide_start=6;Core.precision.curve_guide_end=6
function Core.quantize_setting(key,n)
 local digits=Core.precision[key]
 if digits==nil then return n end
 local factor=10^digits
 return (n<0 and math.ceil(n*factor-.5) or floor(n*factor+.5))/factor
end
function Core.validate(s)
 for k,r in pairs(Core.ranges) do
  if not finite(s[k]) or s[k]<r[1] or s[k]>r[2] or (r[3] and s[k]~=floor(s[k])) then return nil,'設定値が範囲外です：'..k end
 end
 for _,k in ipairs({'pitch','curve','timing','volume','pan','tone','vibrato_depth','vibrato_rate','tremolo_depth','tremolo_rate'}) do
  if s[k..'_lo']>s[k..'_hi'] then return nil,'下限は上限以下にしてください：'..k end
 end
 for _,k in ipairs({'curve','vibrato','tremolo'}) do
  if s[k..'_start_pct']>s[k..'_end_pct'] then return nil,'STARTはEND以下にしてください：'..k end
 end
 return true
end
function Core.rng(seed)
 local state=floor(seed)%2147483647;if state<=0 then state=1 end
 return function(a,b) state=(state*16807)%2147483647;local u=(state-1)/2147483646;if a then return a+(b-a)*u end;return u end
end
function Core.random_seed()
 local t=R.time_precise and R.time_precise() or os.clock()
 local wall=os.time and os.time() or 1
 local v=floor((t*1000003 + wall*48271)%2147483646)+1
 return clamp(v,1,2147483646)
end
function Core.item_tags(item)
 local _,generated=R.GetSetMediaItemInfo_String(item,Core.GENERATED_TAG,'',false)
 local _,temp=R.GetSetMediaItemInfo_String(item,Core.TEMP_TAG,'',false)
 return generated or '',temp or ''
end
function Core.read_temp_heartbeats(now)
 now=now or R.time_precise();local live={}
 for line in tostring(R.GetExtState(Core.SECTION,Core.TEMP_HEARTBEAT_KEY) or ''):gmatch('[^\n]+') do
  local id,stamp_raw=line:match('^([%w]+):(.+)$');local stamp=tonumber(stamp_raw)
  if id and finite(stamp) and now-stamp>=-1 and now-stamp<=Core.TEMP_HEARTBEAT_TTL then live[id]=stamp end
 end
 return live
end
function Core.write_temp_heartbeats(live)
 local ids={};for id in pairs(live or {}) do ids[#ids+1]=id end;table.sort(ids)
 if #ids==0 then R.DeleteExtState(Core.SECTION,Core.TEMP_HEARTBEAT_KEY,false);return end
 local lines={};for _,id in ipairs(ids) do lines[#lines+1]=id..':'..tostring(live[id]) end
 BLT.store(Core.SECTION,Core.TEMP_HEARTBEAT_KEY,table.concat(lines,'\n'),false)
end
function Core.cleanup_stale_temp_items(project)
 if not project then return 0,0 end
 local stale={}
 local now=R.time_precise();local live=Core.read_temp_heartbeats(now)
 for i=R.CountMediaItems(project)-1,0,-1 do
  local item=R.GetMediaItem(project,i)
  local _,tag=R.GetSetMediaItemInfo_String(item,Core.TEMP_TAG,'',false)
  if tag and tag~='' then
   local foreign_live=false
   if tag~='1' and tag~=Core.RUN_ID then
    foreign_live=live[tag]~=nil
   end
   if not foreign_live then stale[#stale+1]={item=item,track=R.GetMediaItemTrack(item)} end
  end
 end
 if #stale==0 then return 0,0 end
 R.PreventUIRefresh(1)
 local removed=0
 for _,v in ipairs(stale) do
  if v.track and R.ValidatePtr2(project,v.item,'MediaItem*') then
   local ok,result=pcall(R.DeleteTrackMediaItem,v.track,v.item)
   if ok and result then removed=removed+1 end
  end
 end
 R.PreventUIRefresh(-1);R.UpdateArrange()
 return removed,#stale-removed
end
function Core.touch_temp_heartbeat(force)
 if Core.RUN_ID=='' then return end
 local now=R.time_precise();if not force and now<(Core.temp_heartbeat_at or 0) then return end
 Core.temp_heartbeat_at=now+2;local live=Core.read_temp_heartbeats(now);live[Core.RUN_ID]=now;Core.write_temp_heartbeats(live)
end
function Core.clear_temp_heartbeat()
 if Core.RUN_ID=='' then return end
 local live=Core.read_temp_heartbeats();live[Core.RUN_ID]=nil;Core.write_temp_heartbeats(live)
end
function Core.project_is_open(project)
 if not project then return false end
 local i=0
 while true do local current=R.EnumProjects(i,'');if not current then break end;if current==project then return true end;i=i+1 end
 return false
end
function Core.item_info(project,item)
 if not item or not R.ValidatePtr2(project,item,'MediaItem*') then return nil,'対象アイテムが無効です。' end
 local take=R.GetActiveTake(item)
 if not take then return nil,'音声またはMIDIアイテムを選択してください。' end
 local is_midi=R.TakeIsMIDI(take)==true
 local source=R.GetMediaItemTake_Source(take)
 local pos,len=R.GetMediaItemInfo_Value(item,'D_POSITION'),R.GetMediaItemInfo_Value(item,'D_LENGTH')
 local rate=R.GetMediaItemTakeInfo_Value(take,'D_PLAYRATE')
 if not finite(len) or len<=0 or not finite(rate) or rate<=0 then return nil,'音声ソースまたは長さを確認してください。' end
 local track=R.GetMediaItemTrack(item);if not track then return nil,'対象トラックを取得できません。' end
 local source_type='';local source_rate=0;local source_channels=0;local slen,isqn=0,false;local file=''
 if source then
  source_type=R.GetMediaSourceType(source);source_type=type(source_type)=='string' and source_type:upper() or ''
  slen,isqn=R.GetMediaSourceLength(source)
  source_rate=R.GetMediaSourceSampleRate(source) or 0;source_channels=R.GetMediaSourceNumChannels(source) or 0
  file=R.GetMediaSourceFileName(source,'') or ''
 end
 if not is_midi then
  if not source or source_type=='EMPTY' or source_type=='MIDI' or source_type=='MIDIPOOL'
   or not finite(source_rate) or source_rate<=0 or not finite(source_channels) or source_channels<1 then
   return nil,'音声を持たないアイテムは対象外です。'
  end
 end
 local _,guid=R.GetSetMediaItemInfo_String(item,'GUID','',false)
 local channel_mode=R.GetMediaItemTakeInfo_Value(take,'I_CHANMODE')
 local analysis_channels=not is_midi and ((channel_mode==2 or channel_mode==3 or channel_mode==4) and 1 or source_channels) or 0
 local item_gain=R.GetMediaItemInfo_Value(item,'D_VOL');local take_gain=R.GetMediaItemTakeInfo_Value(take,'D_VOL')
 local generated,temp=Core.item_tags(item)
 return {item=item,take=take,track=track,pos=pos,len=len,rate=rate,source=source,is_midi=is_midi,
  source_len=slen,source_qn=isqn,source_type=source_type,source_rate=source_rate,channels=source_channels,analysis_channels=analysis_channels,channel_mode=channel_mode,file=file,
  offset=R.GetMediaItemTakeInfo_Value(take,'D_STARTOFFS'),pitch=R.GetMediaItemTakeInfo_Value(take,'D_PITCH'),
  ppitch=R.GetMediaItemTakeInfo_Value(take,'B_PPITCH'),pan=R.GetMediaItemTakeInfo_Value(take,'D_PAN'),
  gain=is_midi and item_gain or take_gain,item_gain=item_gain,take_gain=take_gain,analysis_gain=abs(item_gain*take_gain),name=R.GetTakeName(take) or (is_midi and 'MIDI' or 'Audio'),guid=guid,
  tracknum=R.GetMediaTrackInfo_Value(track,'IP_TRACKNUMBER'),takeindex=R.GetMediaItemTakeInfo_Value(take,'IP_TAKENUMBER'),
  generated=generated or '',temp=temp or ''}
end
function Core.items_from_refs(project,refs,skip_unsupported)
 local list={};local rejected
 for _,item in ipairs(refs or {}) do
  local info,err=Core.item_info(project,item)
  if info then list[#list+1]=info
  elseif not skip_unsupported then return nil,err
  else rejected=rejected or err end
 end
 table.sort(list,function(a,b) if a.tracknum~=b.tracknum then return a.tracknum<b.tracknum end;if a.pos~=b.pos then return a.pos<b.pos end;return a.guid<b.guid end)
 if #list==0 then return nil,rejected or '元になる音声またはMIDIアイテムを選択してください。' end
 return list
end
function Core.selection(project)
 local refs={}
 for i=0,R.CountSelectedMediaItems(project)-1 do refs[#refs+1]=R.GetSelectedMediaItem(project,i) end
 return Core.items_from_refs(project,refs,true)
end
function Core.target_fingerprint(project,item)
 if not item or not R.ValidatePtr2(project,item,'MediaItem*') then return nil end
 local track=R.GetMediaItemTrack(item);local take=R.GetActiveTake(item)
 if not track or not take or not R.ValidatePtr2(project,track,'MediaTrack*') or not R.ValidatePtr2(project,take,'MediaItem_Take*') then return nil end
 local _,guid=R.GetSetMediaItemInfo_String(item,'GUID','',false)
 local _,name=R.GetSetMediaItemTakeInfo_String(take,'P_NAME','',false)
 local parts={tostring(guid or ''),tostring(track),tostring(take),tostring(name or '')}
 for _,key in ipairs({'D_POSITION','D_LENGTH','D_SNAPOFFSET','D_VOL','D_FADEINLEN','D_FADEINLEN_AUTO','D_FADEOUTLEN','D_FADEOUTLEN_AUTO','F_FREEMODE_Y','F_FREEMODE_H','B_MUTE','B_LOOPSRC','C_LOCK','I_GROUPID'}) do
  local v=R.GetMediaItemInfo_Value(item,key);parts[#parts+1]=finite(v) and string.format('%.17g',v) or '?'
 end
 for _,key in ipairs({'D_STARTOFFS','D_VOL','D_PAN','D_PLAYRATE','D_PITCH','B_PPITCH','I_CHANMODE'}) do
  local v=R.GetMediaItemTakeInfo_Value(take,key);parts[#parts+1]=finite(v) and string.format('%.17g',v) or '?'
 end
 local source=R.GetMediaItemTake_Source(take);parts[#parts+1]=tostring(source)
 if source then
  local typ=R.GetMediaSourceType(source);local len,isqn=R.GetMediaSourceLength(source);local file=R.GetMediaSourceFileName(source,'')
  parts[#parts+1]=tostring(typ or '');parts[#parts+1]=tostring(file or '')
  parts[#parts+1]=finite(len) and string.format('%.17g',len) or '?';parts[#parts+1]=isqn and 'Q' or 'S'
 end
 return table.concat(parts,'\30')
end
function Core.collect_track_pool(project,track)
 local out={};if not track then return out end
 for i=0,R.CountTrackMediaItems(track)-1 do
  local item=R.GetTrackMediaItem(track,i)
  if item then
   local generated,temp=Core.item_tags(item)
   if (generated or '')=='' and (temp or '')=='' then
    local info=Core.item_info(project,item);if info and not info.is_midi then out[#out+1]=info end
   end
  end
 end
 table.sort(out,function(a,b) if a.pos~=b.pos then return a.pos<b.pos end return a.guid<b.guid end)
 return out
end
function Core.selection_signature(project)
 local n=R.CountSelectedMediaItems(project);local parts={tostring(n)}
 for i=0,n-1 do parts[#parts+1]=tostring(R.GetSelectedMediaItem(project,i)) end
 return table.concat(parts,'|')
end

function Core.find_item_by_guid(project,guid)
 if not guid or guid=='' then return nil end
 for i=0,R.CountMediaItems(project)-1 do
  local item=R.GetMediaItem(project,i)
  local _,g=R.GetSetMediaItemInfo_String(item,'GUID','',false)
  if g==guid then return item end
 end
 return nil
end
function Core.snapshot(project,list)
 for _,v in ipairs(list) do
  local ok,chunk=R.GetItemStateChunk(v.item,'',false)
  if not ok or not chunk or #chunk==0 or #chunk>=4194300 then error('アイテムの状態を取得できません（大きなFX状態を含む場合は先に整理してください）。',0) end
  v.chunk=chunk
 end
 return {project=project,revision=R.GetProjectStateChangeCount(project),items=list}
end
function Core.clone_chunk(chunk,guidfn)
 local ids={}
 for key,id in chunk:gmatch('([%w_]+)%s+({[%x%-]+})') do if key=='GUID' or key=='IGUID' or key=='FXID' or key=='EGUID' then ids[id]=ids[id] or guidfn() end end
 chunk=chunk:gsub('{[%x%-]+}',function(id)return ids[id] or id end)
 chunk=chunk:gsub('(\n%s*GROUPID%s+)%d+','%10');chunk=chunk:gsub('(\n%s*SEL%s+)[^\n]+','%10')
 return chunk
end
Core.SOURCE_DETECT={open=-34,close=-34,min_open=100,min_close=50,pre=1,post=15}
function Core.refresh_source_ref(v)
 if v and v.is_midi then return nil,'MIDIアイテムはSOURCE解析の対象外です。' end
 if not v or not v.item then return nil,'音声アイテム参照がありません' end
 if type(R.ValidatePtr)=='function' and not R.ValidatePtr(v.item,'MediaItem*') then return nil,'音声アイテム参照が無効です' end
 local take=R.GetActiveTake(v.item)
 if not take or R.TakeIsMIDI(take) then return nil,'音声Takeを取得できません' end
 local source=R.GetMediaItemTake_Source(take)
 if not source then return nil,'音声ソースを取得できません' end
 local ok_parent,parent=pcall(R.GetMediaSourceParent,source)
 if not ok_parent then return nil,'音声ソース参照を更新できません' end
 local ok_len,slen,isqn=pcall(R.GetMediaSourceLength,source)
 local ok_chan,source_channels=pcall(R.GetMediaSourceNumChannels,source)
 local ok_file,file=pcall(R.GetMediaSourceFileName,source)
 local ok_type,source_type=pcall(R.GetMediaSourceType,source)
 local ok_rate,source_rate=pcall(R.GetMediaSourceSampleRate,source)
 source_type=ok_type and type(source_type)=='string' and source_type:upper() or ''
 if not ok_len or not finite(slen) or not ok_chan or not finite(source_channels) or source_channels<1 or not ok_file
  or not ok_rate or not finite(source_rate) or source_rate<=0
  or source_type=='EMPTY' or source_type=='MIDI' or source_type=='MIDIPOOL' then return nil,'音声ソース情報を取得できません' end
 local channel_mode=R.GetMediaItemTakeInfo_Value(take,'I_CHANMODE')
 v.take=take;v.source=source;v.source_len=slen;v.source_qn=isqn;v.source_type=source_type;v.source_rate=source_rate;v.channels=source_channels;v.channel_mode=channel_mode;v.file=file or ''
 v.analysis_channels=(channel_mode==2 or channel_mode==3 or channel_mode==4) and 1 or source_channels
 v.takeindex=R.GetMediaItemTakeInfo_Value(take,'IP_TAKENUMBER')
 return source,parent
end
function Core.source_eligible(v)
 if v and v.is_midi then return false,'MIDIアイテムはSOURCE解析の対象外です。' end
 local source,parent_or_reason=Core.refresh_source_ref(v)
 if not source then return false,parent_or_reason end
 if v.source_qn or not finite(v.source_len) or v.source_len<=0 or not v.file or v.file=='' then return false,'通常の音声ファイル以外' end
 if parent_or_reason or R.GetTakeNumStretchMarkers(v.take)>0 then return false,'反転・セクション・ストレッチ素材' end
 if v.offset<0 or v.offset+v.len*v.rate>v.source_len+1e-6 then return false,'ループまたはソース外の区間' end
 if not finite(v.analysis_channels) or v.analysis_channels<1 or v.analysis_channels>2 then return false,'LUFS検出はモノ／ステレオのみ' end
 if v.source_len>3600 then return false,'ソースが60分を超えています' end
 return true
end
function Core.source_file_stamp(path)
 if type(R.JS_File_Stat)~='function' or not path or path=='' then return nil end
 local ok,rv,size,accessed,modified,created,device,special,inode=pcall(R.JS_File_Stat,path)
 if not ok or rv~=0 or not finite(size) or type(modified)~='string' or modified=='' then return nil end
 return table.concat({tostring(size),modified,tostring(created),tostring(device),tostring(inode)},'|')
end
function Core.source_cache_reusable(cached,stamp)
 return cached and (cached.manual_regions or (not cached.error and stamp~=nil and cached.file_stamp==stamp))
end
function Core.source_cache_key(v)
 return table.concat({v.file or '',string.format('%.6f',v.source_len or 0),tostring(v.analysis_channels or 0),tostring(v.channel_mode or 0),string.format('%.9f',v.analysis_gain or 1)},'|')
end
function Core.source_cleanup(j)
 if not j then return end
 local cleaned=not j.cleanup_failed
 if j.accessor then pcall(R.DestroyAudioAccessor,j.accessor);j.accessor=nil end
 if j.temp_item and j.project and R.ValidatePtr2(j.project,j.temp_item,'MediaItem*') then
  R.PreventUIRefresh(1);local ok,result=pcall(R.DeleteTrackMediaItem,j.track,j.temp_item);R.PreventUIRefresh(-1);R.UpdateArrange()
  if not ok or not result then cleaned=false end
 end
 j.temp_item=nil;j.temp_take=nil;j.cleanup_failed=not cleaned
 if not cleaned and j.project then Core.STALE_TEMP_PROJECTS[j.project]=true end
 return cleaned
end
local function source_finish_region(j,a,b,anchor)
 local s=Core.SOURCE_DETECT
 if not a or not b or b<=a or b-a+1e-10<s.min_close/1000 then return end
 local ra,rb=a,b
 a=clamp(a-s.pre/1000,0,j.info.source_len);b=clamp(b+s.post/1000,0,j.info.source_len)
 if b-a<1/Core.SOURCE_SR then return end
 anchor=anchor or {time=(ra+rb)*.5,score=-math.huge,peak_db=-240,loud=-240}
 local region={start=a,finish=b,raw_start=ra,raw_finish=rb,anchor=clamp(anchor.time,ra,rb),anchor_score=anchor.score,peak_db=anchor.peak_db,loud=anchor.loud}
 local last=j.regions[#j.regions]
 if last and region.start<=last.finish+1e-10 then
  last.finish=max(last.finish,region.finish);last.raw_finish=max(last.raw_finish,region.raw_finish)
  if region.anchor_score>(last.anchor_score or -math.huge) then last.anchor,last.anchor_score,last.peak_db,last.loud=region.anchor,region.anchor_score,region.peak_db,region.loud end
 else
  if #j.regions>=Core.SOURCE_MAX_REGIONS then error('素材の検出区間が安全上限を超えました。素材を短くするかSOURCEを無効にしてください。',0) end
  j.regions[#j.regions+1]=region
 end
end
local function source_consume_bin(j,pk,lufs,fast)
 local s=Core.SOURCE_DETECT;local i=j.bin_index+1;j.bin_index=i
 local t=(i-1)*.001;local ending=min(i*.001,j.info.source_len)
 if j.opened then
  local peak_db=db(pk);local loud=.65*(fast or -240)+.35*(lufs or -240)
  local score=.72*peak_db+.18*(fast or -240)+.10*(lufs or -240)
  if not j.anchor or score>j.anchor.score then j.anchor={time=t,score=score,peak_db=peak_db,loud=loud} end
  if (fast or -240)<s.close then
   j.quiet=j.quiet or t
   if ending-j.quiet+1e-10>=s.min_open/1000 then
    source_finish_region(j,j.opened,j.quiet,j.anchor);j.opened=nil;j.quiet=nil;j.anchor=nil
   end
  else j.quiet=nil end
 elseif (lufs or -240)>s.open then
  j.opened=t;j.quiet=nil
  local peak_db=db(pk);local loud=.65*(fast or -240)+.35*(lufs or -240)
  j.anchor={time=t,score=.72*peak_db+.18*(fast or -240)+.10*(lufs or -240),peak_db=peak_db,loud=loud}
 end
end
local function source_finish_bin(j)
 local ri=j.ring_index;j.ring_sum=max(0,j.ring_sum-(j.ring[ri] or 0)+j.bin_energy);j.ring[ri]=j.bin_energy;j.ring_index=ri%400+1
 local power=j.ring_sum/(Core.SOURCE_SR*.4);local lufs=power>1e-24 and -.691+10*math.log(power,10) or -240
 local fi=j.fast_index;j.fast_sum=max(0,j.fast_sum-(j.fast_ring[fi] or 0)+j.bin_energy);j.fast_ring[fi]=j.bin_energy;j.fast_index=fi%100+1
 local fast=-240
 if j.opened or lufs>Core.SOURCE_DETECT.open then local fast_power=j.fast_sum/(Core.SOURCE_SR*.1);fast=fast_power>1e-24 and -.691+10*math.log(fast_power,10) or -240 end
 local pk=j.bin_peak
 source_consume_bin(j,pk,lufs,fast)
 local pi=clamp(floor((j.bin_index-1)*(j.preview_scale or 1))+1,1,Core.SOURCE_PREVIEW_BINS)
 if pk>(j.preview[pi] or 0) then j.preview[pi]=pk end
 j.preview_max=max(j.preview_max or 0,pk)
 j.bin_samples,j.bin_peak,j.bin_energy=0,0,0
end
function Core.source_scan_start(project,v)
 local eligible,reason=Core.source_eligible(v);if not eligible then error(reason,0) end
 local far=max((R.GetProjectLength and R.GetProjectLength(project) or 0)+60,v.pos+v.len+60)
 local scan_source=R.PCM_Source_CreateFromFile(v.file)
 if not scan_source then error('素材解析用の音声ソースを作成できません。',0) end
 R.PreventUIRefresh(1)
 local item=R.AddMediaItemToTrack(v.track)
 if not item then R.PreventUIRefresh(-1);pcall(R.PCM_Source_Destroy,scan_source);error('素材解析用の一時アイテムを作成できません。',0) end
 if not R.GetSetMediaItemInfo_String(item,Core.TEMP_TAG,Core.RUN_ID,true) then
  R.PreventUIRefresh(-1);Core.source_cleanup({project=project,track=v.track,temp_item=item});pcall(R.PCM_Source_Destroy,scan_source);error('素材解析用の一時アイテムを識別できません。',0)
 end
 local take=R.AddTakeToMediaItem(item)
 if not take then R.PreventUIRefresh(-1);Core.source_cleanup({project=project,track=v.track,temp_item=item});pcall(R.PCM_Source_Destroy,scan_source);error('素材解析用Takeを作成できません。',0) end
 R.SetMediaItemInfo_Value(item,'D_POSITION',far);R.SetMediaItemInfo_Value(item,'D_LENGTH',v.source_len);R.SetMediaItemInfo_Value(item,'B_MUTE',0);R.SetMediaItemInfo_Value(item,'B_LOOPSRC',0);R.SetMediaItemSelected(item,false)
 local old_source=R.GetMediaItemTake_Source(take)
 if not R.SetMediaItemTake_Source(take,scan_source) then R.PreventUIRefresh(-1);Core.source_cleanup({project=project,track=v.track,temp_item=item,temp_take=take});pcall(R.PCM_Source_Destroy,scan_source);error('素材解析用Takeへソースを設定できません。',0) end
 if old_source and old_source~=scan_source then pcall(R.PCM_Source_Destroy,old_source) end
 R.SetMediaItemTakeInfo_Value(take,'D_STARTOFFS',0);R.SetMediaItemTakeInfo_Value(take,'D_PLAYRATE',1);R.SetMediaItemTakeInfo_Value(take,'D_PITCH',0);R.SetMediaItemTakeInfo_Value(take,'B_PPITCH',0);R.SetMediaItemTakeInfo_Value(take,'I_CHANMODE',v.channel_mode or 0);R.SetMediaItemTakeInfo_Value(take,'D_VOL',1)
 R.UpdateItemInProject(item);R.PreventUIRefresh(-1)
 local j={project=project,track=v.track,temp_item=item,temp_take=take,info=v,file_stamp=Core.source_file_stamp(v.file),offset=0,total=ceil(v.source_len*Core.SOURCE_SR),regions={},ring={},ring_index=1,ring_sum=0,fast_ring={},fast_index=1,fast_sum=0,bin_energy=0,bin_peak=0,bin_samples=0,bin_index=0,states={},opened=nil,quiet=nil,anchor=nil,preview={},preview_max=0,preview_scale=Core.SOURCE_PREVIEW_BINS/max(1,ceil(v.source_len*1000))}
 for c=1,v.analysis_channels do j.states[c]={0,0,0,0} end
 local buffer_ok,buffer=pcall(R.new_array,Core.SOURCE_BLOCK*v.analysis_channels)
 if not buffer_ok or not buffer then Core.source_cleanup(j);error('素材解析用バッファを作成できません。',0) end
 j.buffer=buffer
 local accessor_ok,accessor=pcall(R.CreateTakeAudioAccessor,take);if accessor_ok then j.accessor=accessor end
 if not j.accessor then Core.source_cleanup(j);error('素材全体の音声アクセサを作成できません。',0) end
 local a,b=R.GetAudioAccessorStartTime(j.accessor),R.GetAudioAccessorEndTime(j.accessor)
 if not finite(a) or not finite(b) or b<=a then Core.source_cleanup(j);error('素材全体を読み出せません。',0) end
 j.revision=R.GetProjectStateChangeCount(project);return j
end
function Core.source_scan_step(j)
 if not j or not j.accessor then return true end
 if R.EnumProjects(-1,'')~=j.project then Core.source_cleanup(j);error('解析中にプロジェクトが切り替わりました。',0) end
 if not R.ValidatePtr2(j.project,j.info.item,'MediaItem*') then Core.source_cleanup(j);error('解析中に元アイテムが削除されました。',0) end
 if R.GetProjectStateChangeCount(j.project)~=j.revision then Core.source_cleanup(j);error('解析中にプロジェクトが変更されました。',0) end
 if R.AudioAccessorStateChanged(j.accessor) then Core.source_cleanup(j);error('解析中に音声が変更されました。',0) end
 local count=min(Core.SOURCE_BLOCK,j.total-j.offset);if count<=0 then return true end
 j.buffer.clear();local rc=R.GetAudioAccessorSamples(j.accessor,Core.SOURCE_SR,j.info.analysis_channels,j.offset/Core.SOURCE_SR,count,j.buffer)
 if type(rc)~='number' or (rc~=0 and rc~=1) then Core.source_cleanup(j);error('素材全体の音声取得に失敗しました。',0) end
 local values=j.buffer.table(1,count*j.info.analysis_channels);local nchan,gain=j.info.analysis_channels,j.info.analysis_gain or 1
 local zero=rc==0;local pos=0
 if nchan==1 then
  local st=j.states[1];local a1,a2,a3,a4=st[1],st[2],st[3],st[4]
  while pos<count do
   local take=min(Core.SOURCE_HOP-j.bin_samples,count-pos);local pk,energy=j.bin_peak,j.bin_energy
   for k=1,take do
    local raw=values[pos+k] or 0
    local sample=(zero and 0 or raw)*gain;pk=max(pk,abs(sample))
    local vv=1.53512485958697*sample+a1;a1=-2.69169618940638*sample+1.69065929318241*vv+a2;a2=1.19839281085285*sample-0.73248077421585*vv
    local z=vv+a3;a3=-2*vv+1.99004745483398*z+a4;a4=vv-0.99007225036621*z;energy=energy+z*z
   end
   pos=pos+take;j.bin_peak=pk;j.bin_energy=energy;j.bin_samples=j.bin_samples+take
   if j.bin_samples==Core.SOURCE_HOP then source_finish_bin(j) end
  end
  st[1],st[2],st[3],st[4]=a1,a2,a3,a4
 else
  local s1,s2=j.states[1],j.states[2]
  local a1,a2,a3,a4=s1[1],s1[2],s1[3],s1[4];local b1,b2,b3,b4=s2[1],s2[2],s2[3],s2[4]
  while pos<count do
   local take=min(Core.SOURCE_HOP-j.bin_samples,count-pos);local pk,energy=j.bin_peak,j.bin_energy
   for k=0,take-1 do
    local base=(pos+k)*2;local r1,r2=values[base+1],values[base+2]
    local x1=(zero and 0 or (r1 or 0))*gain;local x2=(zero and 0 or (r2 or 0))*gain;pk=max(pk,abs(x1),abs(x2))
    local v1=1.53512485958697*x1+a1;a1=-2.69169618940638*x1+1.69065929318241*v1+a2;a2=1.19839281085285*x1-0.73248077421585*v1
    local z1=v1+a3;a3=-2*v1+1.99004745483398*z1+a4;a4=v1-0.99007225036621*z1
    local v2=1.53512485958697*x2+b1;b1=-2.69169618940638*x2+1.69065929318241*v2+b2;b2=1.19839281085285*x2-0.73248077421585*v2
    local z2=v2+b3;b3=-2*v2+1.99004745483398*z2+b4;b4=v2-0.99007225036621*z2
    energy=energy+z1*z1+z2*z2
   end
   pos=pos+take;j.bin_peak=pk;j.bin_energy=energy;j.bin_samples=j.bin_samples+take
   if j.bin_samples==Core.SOURCE_HOP then source_finish_bin(j) end
  end
  s1[1],s1[2],s1[3],s1[4]=a1,a2,a3,a4;s2[1],s2[2],s2[3],s2[4]=b1,b2,b3,b4
 end
 j.offset=j.offset+count
 if j.offset>=j.total then
  if j.file_stamp and Core.source_file_stamp(j.info.file)~=j.file_stamp then
   Core.source_cleanup(j);error('解析中に音声が変更されました。',0)
  end
  if j.bin_samples>0 then source_finish_bin(j) end
  if j.opened then source_finish_region(j,j.opened,j.info.source_len,j.anchor);j.opened=nil end
  local result={regions=j.regions,detected=#j.regions,settings=tcopy(Core.SOURCE_DETECT),preview=j.preview,preview_max=j.preview_max or 0,source_len=j.info.source_len,file_stamp=j.file_stamp};Core.source_cleanup(j);j.done=true;return true,result
 end
 return false
end
function Core.source_context(v,analysis)
 local regions=analysis and analysis.regions or {}
 if #regions==0 then return nil,'検出区間 0：バリエーションなし' end
 local start,duration=v.offset,v.len*v.rate;local finish=start+duration;local oi=nil;local best_overlap=-1;local best_dist=math.huge
 for i,r in ipairs(regions) do
  local overlap=max(0,min(finish,r.finish)-max(start,r.start));local mid=(start+finish)*.5;local clamped=clamp(mid,r.start,r.finish);local dist=abs(mid-clamped)
  if overlap>best_overlap+1e-10 or (abs(overlap-best_overlap)<=1e-10 and dist<best_dist) then oi,best_overlap,best_dist=i,overlap,dist end
 end
 if not oi or best_overlap<=0 then return nil,'元の使用区間が検出区間に含まれません' end
 local orig=regions[oi];local orig_anchor=orig.anchor or (orig.start+orig.finish)/2
 local anchor_rel=orig_anchor-start;local side,ratio
 if start<=orig_anchor then side=-1;ratio=(orig_anchor-start)/max(orig_anchor-orig.start,1/Core.SOURCE_SR)
 else side=1;ratio=(start-orig_anchor)/max(orig.finish-orig_anchor,1/Core.SOURCE_SR) end
 return {regions=regions,index=oi,region=orig,start=start,duration=duration,anchor=orig_anchor,anchor_rel=anchor_rel,side=side,ratio=ratio}
end
function Core.track_anchor_key(v)
 return table.concat({v.guid or '',v.file or '',string.format('%.9f',v.offset or 0),string.format('%.9f',v.len or 0),
  string.format('%.9f',v.rate or 1),tostring(v.channel_mode or 0)},'|')
end
function Core.quick_track_anchor(v,cache)
 local key=Core.track_anchor_key(v)
 if cache and cache[key] then cache[key]._used=R.time_precise();return cache[key].anchor,cache[key].method end
 local source=Core.refresh_source_ref(v)
 local duration=(v.len or 0)*(v.rate or 1)
 if not source or duration<=0 then
  local fallback=(v.offset or 0)+max(0,duration)*.5
  if cache then cache[key]={anchor=fallback,method='midpoint',_used=R.time_precise()} end
  return fallback,'midpoint'
 end
 local rate=1000;local total=max(1,ceil(duration*rate));local done=0
 local channels=clamp(floor(v.channels or 1),1,32);local block=4096
 local buffer=R.new_array(block*channels*2)
 local fast_ring,slow_ring={},{};local fi,si,fsum,ssum=1,1,0,0
 local best_score,best_time=-math.huge,(v.offset or 0)+duration*.5
 while done<total do
  local want=min(block,total-done);buffer.clear()
  local rv=R.PCM_Source_GetPeaks(source,rate,(v.offset or 0)+done/rate,channels,want,0,buffer)
  local got=type(rv)=='number' and (rv&0xFFFFF) or 0
  if got<=0 then break end
  local data=buffer.table(1,got*channels*2)
  for i=0,got-1 do
   local pk=0
   if (v.channel_mode or 0)==3 then
    pk=max(abs(data[i*channels+1] or 0),abs(data[got*channels+i*channels+1] or 0))
   elseif (v.channel_mode or 0)==4 then
    local c=min(2,channels)
    pk=max(abs(data[i*channels+c] or 0),abs(data[got*channels+i*channels+c] or 0))
   else
    for c=1,channels do pk=max(pk,abs(data[i*channels+c] or 0),abs(data[got*channels+i*channels+c] or 0)) end
   end
   local e=pk*pk
   fsum=max(0,fsum-(fast_ring[fi] or 0)+e);fast_ring[fi]=e;fi=fi%100+1
   ssum=max(0,ssum-(slow_ring[si] or 0)+e);slow_ring[si]=e;si=si%400+1
   local fast=fsum>1e-24 and 10*math.log(fsum/100,10) or -240
   local slow=ssum>1e-24 and 10*math.log(ssum/400,10) or -240
   local score=.72*db(pk)+.18*fast+.10*slow
   if score>best_score then best_score=score;best_time=(v.offset or 0)+(done+i)/rate end
  end
  done=done+got
  if got<want then break end
 end
 if cache then cache[key]={anchor=best_time,method='item-envelope',_used=R.time_precise()} end
 return best_time,'item-envelope'
end
function Core.aligned_source_variant(v,ctx,target_info,target_region,timing_mode,id,sort_key,track_item)
 local target_anchor=target_region.anchor or (target_region.start+target_region.finish)/2;local off
 if timing_mode==2 then
  if ctx.side<0 then off=target_anchor-ctx.ratio*max(target_anchor-target_region.start,0)
  else off=target_anchor+ctx.ratio*max(target_region.finish-target_anchor,0) end
 else off=target_anchor-ctx.anchor_rel end
 return {offset=off,original=false,region=target_region._index or 0,anchor=target_region.anchor,file=target_info.file,
  id=id,sort_key=sort_key or 0,track_item=track_item and true or false,track_guid=track_item and target_info.guid or nil,
  track_ref=track_item and target_info.item or nil,source_name=track_item and target_info.name or nil,channel_mode=target_info.channel_mode or 0}
end
function Core.source_variants(v,analysis,timing_mode,track_candidates,track_anchor_cache,source_mode)
 local ctx,why=Core.source_context(v,analysis);v.variants=nil;v.source_same_variants=nil;v.source_track_variants=nil;timing_mode=timing_mode or 2
 if not ctx then return nil,why,nil,0,0 end
 local orig_id='orig:'..tostring(v.guid)
 local original={offset=v.offset,original=true,region=ctx.index,anchor=ctx.region.anchor,file=v.file,id=orig_id,sort_key=ctx.index}
 local same={original}
 for i,r in ipairs(ctx.regions) do
  r._index=i
  if i~=ctx.index then same[#same+1]=Core.aligned_source_variant(v,ctx,v,r,timing_mode,'segment:'..tostring(v.guid)..':'..i,i,false) end
 end
 local track={original};local rejected_format=false
 for ti,cand in ipairs(track_candidates or {}) do
  local eligible=Core.source_eligible(cand);local used_duration=(cand.len or 0)*(cand.rate or 1)
  if eligible then
   local anchor=Core.quick_track_anchor(cand,track_anchor_cache)
   local region={start=cand.offset,finish=cand.offset+used_duration,raw_start=cand.offset,raw_finish=cand.offset+used_duration,
    anchor=clamp(anchor,cand.offset,cand.offset+used_duration),_index=1}
   track[#track+1]=Core.aligned_source_variant(v,ctx,cand,region,timing_mode,'track:'..tostring(cand.guid),100000+ti,true)
  else rejected_format=true end
 end
 local function unique(list)
  local seen,out={},{}
  for _,c in ipairs(list) do
   local k=c.id or ((c.file or '')..'|'..tostring(c.region or 0)..'|'..tostring(c.track_guid or ''))
   if not seen[k] then seen[k]=true;out[#out+1]=c end
  end
  table.sort(out,function(a,b)return (a.sort_key or 0)<(b.sort_key or 0) end)
  return out
 end
 same,track=unique(same),unique(track);v.source_same_variants=same;v.source_track_variants=track
 local function inclusive_count(list)
  local n=1
  for _,c in ipairs(list or {}) do if not c.original then n=n+1 end end
  return n
 end
 local same_count,track_count=inclusive_count(same),inclusive_count(track)
 source_mode=source_mode==2 and 2 or 1
 local out=source_mode==2 and track or same;local out_count=source_mode==2 and track_count or same_count;v.variants=out
 local base
 if timing_mode==2 then local side_name=ctx.side<0 and '山より前' or '山より後';base=string.format('区間相対 %s %.1f%%',side_name,ctx.ratio*100)
 else base=string.format('山オフセット %.1f ms',ctx.anchor_rel*1000) end
 if out_count<=1 then
  local reason='使用可能 1（元のみ）：追加候補がありません'
  if source_mode==2 and rejected_format then reason='使用可能 1（元のみ）：他候補は対象外の素材です' end
  return nil,reason,ctx,same_count,track_count
 end
 return out,string.format('候補 %d（同一素材 %d / 同一トラック %d） / %s',out_count,same_count,track_count,base),ctx,same_count,track_count
end
function Core.build_variants(v)
 if v.variants and #v.variants>0 then return v.variants end
 return {{offset=v.offset,original=true,region=1,file=v.file,id='orig:'..tostring(v.guid),sort_key=1}}
end
function Core.pick_candidate(v,pools,rng,order)
 local variants=Core.build_variants(v);if #variants<=1 then return variants[1] end
 local p=pools[v.guid]
 if not p then
  local oi=1;for i,c in ipairs(variants) do if c.original then oi=i;break end end
  p={original=oi,last=nil};pools[v.guid]=p;if order==2 then p.index=oi%#variants+1 end
 end
 if order==2 then local c=variants[p.index];p.index=p.index%#variants+1;p.last=c.id;return c end
 local function refill(first)
  local bag={};for _,c in ipairs(variants) do if not (first and c.original) then bag[#bag+1]=c end end
  for i=#bag,2,-1 do local jj=1+floor(rng()*i);bag[i],bag[jj]=bag[jj],bag[i] end
  if first then local orig=variants[p.original];if orig then bag[#bag+1]=orig end elseif #bag>1 and p.last and bag[1].id==p.last then bag[1],bag[2]=bag[2],bag[1] end
  p.bag=bag;p.bag_i=1;p.first_cycle=false
 end
 if not p.bag or p.bag_i>#p.bag then refill(p.first_cycle~=false) end
 local c=p.bag[p.bag_i];p.bag_i=p.bag_i+1;p.last=c.id;return c
end
function Core.occupancy(project,list,ignore_item)
 local tracks,ignore={},{}
 for _,v in ipairs(list) do tracks[v.track]=true;if v.item then ignore[v.item]=true end end
 if ignore_item then ignore[ignore_item]=true end
 local blocks={}
 for track in pairs(tracks) do for i=0,R.CountTrackMediaItems(track)-1 do
  local it=R.GetTrackMediaItem(track,i)
  if not ignore[it] then local p=R.GetMediaItemInfo_Value(it,'D_POSITION');blocks[#blocks+1]={a=p,b=p+R.GetMediaItemInfo_Value(it,'D_LENGTH')} end
 end end
 table.sort(blocks,function(a,b)return a.a<b.a end)
 local merged={}
 for _,b in ipairs(blocks) do
  local last=merged[#merged]
  if last and b.a<=last.b+1e-9 then last.b=max(last.b,b.b) else merged[#merged+1]=b end
 end
 return merged
end
function Core.curve_guide_decode(text,start_pct,end_pct,start_norm,end_norm,enabled)
 local pts={}
 for token in tostring(text or ''):gmatch('[^;]+') do
  local a,b=token:match('^%s*([%+%-]?[%d%.]+)%s*,%s*([%+%-]?[%d%.]+)%s*$')
  a,b=tonumber(a),tonumber(b)
  if finite(a) and finite(b) then pts[#pts+1]={pct=clamp(a,0,100),norm=clamp(b,-1,1)} end
 end
 if #pts<2 and enabled then
  pts={{pct=clamp(tonumber(start_pct) or 0,0,100),norm=clamp(tonumber(start_norm) or 0,-1,1)},
       {pct=clamp(tonumber(end_pct) or 100,0,100),norm=clamp(tonumber(end_norm) or 0,-1,1)}}
 end
 table.sort(pts,function(a,b) return a.pct<b.pct end)
 return pts
end
function Core.curve_guide_encode(pts)
 local out={}
 for _,p in ipairs(pts or {}) do out[#out+1]=string.format('%.3f,%.5f',clamp(p.pct or 0,0,100),clamp(p.norm or 0,-1,1)) end
 return table.concat(out,';')
end
function Core.curve_guide_add(pts,pct,norm)
 pct,norm=clamp(tonumber(pct) or 0,0,100),clamp(tonumber(norm) or 0,-1,1)
 local hit=nil
 for i,p in ipairs(pts or {}) do if abs((p.pct or 0)-pct)<.75 then hit=i;break end end
 if hit then pts[hit]={pct=pct,norm=norm} else pts[#pts+1]={pct=pct,norm=norm} end
 table.sort(pts,function(a,b) return a.pct<b.pct end)
 return pts
end
function Core.curve_guide_auto_points(pts)
 local n=#(pts or {})
 if n<2 then return 2 end
 local bends=0
 for i=2,n-1 do
  local a,b,c=pts[i-1],pts[i],pts[i+1]
  local s1=((b.norm or 0)-(a.norm or 0))/max(1e-9,(b.pct or 0)-(a.pct or 0))
  local s2=((c.norm or 0)-(b.norm or 0))/max(1e-9,(c.pct or 0)-(b.pct or 0))
  if abs(s2-s1)>.004 then bends=bends+1 end
 end
 return clamp(max(4,n*2+bends),4,24)
end
function Core.rand_curve(rng,lo,hi,n,guide_enabled,guide_data,guide_start,guide_end,range_start,range_end)
 local t={}
 lo=min(0,tonumber(lo) or 0);hi=max(0,tonumber(hi) or 0)
 if not guide_enabled then for i=1,n do t[i]=rng(lo,hi) end;return t end
 local pts=Core.curve_guide_decode(guide_data,range_start,range_end,guide_start,guide_end,true)
 if #pts<2 then for i=1,n do t[i]=rng(lo,hi) end;return t end
 n=Core.curve_guide_auto_points(pts)
 local span=max(1e-9,hi-lo)
 local neg_scale=rng(.55,.92);local pos_scale=rng(.55,.92)
 local function norm_to_semitone(norm)
  norm=clamp(tonumber(norm) or 0,-1,1)
  if norm<0 then return clamp((-norm)*lo*neg_scale,lo,0) end
  if norm>0 then return clamp(norm*hi*pos_scale,0,hi) end
  return 0
 end
 local anchors={}
 for i,p in ipairs(pts) do anchors[i]=norm_to_semitone(p.norm) end
 local gammas={};for i=1,#pts-1 do gammas[i]=rng(.58,1.72) end
 local p0,p1=pts[1].pct or 0,pts[#pts].pct or 100;local seg=1;local last_seg=0;local last_prog=0
 for i=1,n do
  local u=(i-1)/max(1,n-1);local pct=p0+(p1-p0)*u
  while seg<#pts-1 and pct>(pts[seg+1].pct or 100) do seg=seg+1 end
  local a,b=pts[seg],pts[seg+1] or pts[seg];local pa,pb=a.pct or p0,b.pct or p1
  local su=clamp((pct-pa)/max(1e-9,pb-pa),0,1)
  if seg~=last_seg then last_seg=seg;last_prog=0 end
  local anchor=anchors[seg] or 0;local delta=(anchors[seg+1] or anchor)-anchor
  if abs(delta)<=span*.008 then
   if abs(anchor)<=1e-12 then
    t[i]=0
   else
    local side_span=anchor<0 and abs(lo) or hi
    local jitter=rng(-side_span*.035,side_span*.035)
    t[i]=anchor<0 and clamp(anchor+jitter,lo,0) or clamp(anchor+jitter,0,hi)
   end
  else
   local base=su^(gammas[seg] or 1);local wiggle=rng(-.075,.075)*math.sin(math.pi*su)
   local prog=clamp(base+wiggle,last_prog,1);if i==n or su>.995 then prog=1 end;last_prog=prog
   t[i]=clamp(anchor+delta*prog,lo,hi)
  end
 end
 return t
end
function Core.curve_value(values,u)
 values=values or {};local n=#values;if n==0 then return 0 elseif n==1 then return values[1] or 0 end
 u=clamp(tonumber(u) or 0,0,1);local z=u*(n-1);local i=min(n-1,floor(z)+1);local f=z-(i-1)
 return (values[i] or 0)+((values[i+1] or values[i] or 0)-(values[i] or 0))*f
end
function Core.curve_link_map(base_len,playrate,values,start_pct,end_pct)
 base_len=max(1e-6,tonumber(base_len) or 1e-6);playrate=max(1e-6,tonumber(playrate) or 1)
 local total=base_len*playrate;local a=clamp((tonumber(start_pct) or 0)/100,0,1);local b=clamp((tonumber(end_pct) or 100)/100,a,1)
 local active=total*(b-a)
 if active<=1e-12 or not values or #values==0 then return base_len,{{pos=0,src=0,slope=0},{pos=total,src=total}} end
 local q0,q1=total*a,total*b;local markers={{pos=0,src=0,slope=0}};local out=q0
 if q0>0 then markers[#markers+1]={pos=q0,src=q0,slope=0} end
 local edge=min(.020*playrate/active,.5/max(1,#values-1))
 local attack=q0>0 and abs(values[1])>1e-10
 local release=q1<total and abs(values[#values])>1e-10
 local function semitone(u)
  local v=Core.curve_value(values,u)
  if attack then v=v*min(1,u/edge) end
  if release then v=v*min(1,(1-u)/edge) end
  return v
 end
 local knots={0,1}
 for i=2,#values-1 do knots[#knots+1]=(i-1)/(#values-1) end
 if attack then knots[#knots+1]=edge end;if release then knots[#knots+1]=1-edge end
 table.sort(knots)
 local function segment(u0,u1,r0,r1,depth)
  local mid=(u0+u1)/2;local rm=2^(semitone(mid)/12)
  local predicted=math.sqrt((r0*r0+r1*r1)/2)
  if depth<10 and abs(12*math.log(predicted/rm,2))>.01 then
   segment(u0,mid,r0,rm,depth+1);segment(mid,u1,rm,r1,depth+1);return
  end
  local sum=r0+r1
  markers[#markers].slope=(r1-r0)/sum
  out=out+2*active*(u1-u0)/sum
  markers[#markers+1]={pos=out,src=q0+active*u1,slope=0}
 end
 local previous=0;local rate=2^(semitone(0)/12)
 for _,u in ipairs(knots) do if u>previous then
  local next_rate=2^(semitone(u)/12);segment(previous,u,rate,next_rate,0);previous=u;rate=next_rate
 end end
 if q1<total then out=out+total-q1;markers[#markers+1]={pos=out,src=total,slope=0} end
 return max(1e-6,out/playrate),markers
end
function Core.rand_modulation(rng,s,prefix)
 return {depth=rng(s[prefix..'_depth_lo'],s[prefix..'_depth_hi']),rate=rng(s[prefix..'_rate_lo'],s[prefix..'_rate_hi']),
  start_pct=s[prefix..'_start_pct'],end_pct=s[prefix..'_end_pct'],shape=s[prefix..'_shape'],phase_dir=rng()<.5 and -1 or 1}
end
function Core.mod_shape(shape,q)
 q=clamp(tonumber(q) or 0,0,1);if shape==2 then return q elseif shape==3 then return 1-q end;return 1
end
function Core.mod_edge(rate,elapsed,remaining,release)
 rate=max(.1,tonumber(rate) or 1)
 local attack=elapsed*rate*2
 if not release then return clamp(min(attack,1),0,1) end
 return clamp(min(attack,remaining*rate*2,1),0,1)
end
function Core.mod_window(row,m)
 local playrate=max(1e-6,tonumber(row.playrate) or 1)
 local duration=max(1e-9,(tonumber(row.len) or 0)*playrate)
 local a=duration*clamp((m.start_pct or 0)/100,0,1)
 local b=duration*clamp((m.end_pct or 100)/100,0,1)
 return duration,playrate,a,b,b<duration-1e-8
end
function Core.mod_point_count(m,a,b,playrate)
 local sec=max(0,(b-a)/max(1e-9,playrate))
 return clamp(ceil(sec*max(.1,m.rate or 1)*14),8,4096)
end

Core.TEXTURE_SR=48000
Core.TEXTURE_FFT_SIZE=8192
Core.TEXTURE_SPECTRUM_BINS=192
Core.TEXTURE_SPECTRUM_FRAMES=32
Core.TEXTURE_FREQ_MIN=45
Core.TEXTURE_FREQ_MAX=19000
Core.TEXTURE_LOW_MAX=250
Core.TEXTURE_MID_MAX=4000
Core.TEXTURE_TARGET_LUFS=-18
Core.TEXTURE_FRAME_GATE_DB=36
Core.TEXTURE_NORM_GAIN_DB=72
function Core.texture_percentile(sorted,q)
 if not sorted or #sorted==0 then return 0 end
 q=clamp(q or .5,0,1);local x=1+(#sorted-1)*q;local i=clamp(floor(x),1,#sorted);local f=x-i
 return (sorted[i] or 0)*(1-f)+(sorted[min(#sorted,i+1)] or sorted[i] or 0)*f
end
function Core.texture_frame_loudness_power(values,N,nchan)
 local energy=0
 for ch=1,nchan do
  local a1,a2,a3,a4=0,0,0,0
  for n=0,N-1 do
   local x=values[n*nchan+ch] or 0
   local vv=1.53512485958697*x+a1;a1=-2.69169618940638*x+1.69065929318241*vv+a2;a2=1.19839281085285*x-0.73248077421585*vv
   local z=vv+a3;a3=-2*vv+1.99004745483398*z+a4;a4=vv-0.99007225036621*z
   energy=energy+z*z
  end
 end
 return energy/max(1,N)
end
function Core.capture_texture_spectrum(v)
 if v and v.is_midi then return nil,'MIDIでは使用できません。' end
 if not v or not v.item or (type(R.ValidatePtr)=='function' and not R.ValidatePtr(v.item,'MediaItem*')) then return nil,'音声アイテム参照が無効です。' end
 local take=R.GetActiveTake(v.item)
 if not take or R.TakeIsMIDI(take) then return nil,'音声Takeを取得できません。' end
 if type(R.CreateTakeAudioAccessor)~='function' or type(R.GetAudioAccessorSamples)~='function' or type(R.new_array)~='function' then return nil,'スペクトル解析APIを利用できません。' end
 local accessor=R.CreateTakeAudioAccessor(take);if not accessor then return nil,'スペクトル解析用AudioAccessorを作成できません。' end
 local ok,result,reason=xpcall(function()
  local a=R.GetAudioAccessorStartTime(accessor);local b=R.GetAudioAccessorEndTime(accessor)
  if not finite(a) or not finite(b) or b<=a then return nil,'音声範囲を読み出せません。' end
  local duration=min(max(0,v.len or 0),b-a)
  if duration<=1e-5 then return nil,'解析する音声範囲が短すぎます。' end
  local sr,N=Core.TEXTURE_SR,Core.TEXTURE_FFT_SIZE;local frame_sec=N/sr
  local nchan=clamp(floor(tonumber(v.analysis_channels) or tonumber(v.channels) or 1),1,2)
  local frames=min(Core.TEXTURE_SPECTRUM_FRAMES,max(1,ceil(duration/max(frame_sec,.08))))
  local maxpos=max(0,duration-frame_sec);local frame_meta={};local max_lufs=-math.huge
  local samplebuf=R.new_array(N*nchan)
  for fi=1,frames do
   local frac=frames<=1 and .5 or (fi-1)/(frames-1);local pos=maxpos*frac
   samplebuf.clear();local rc=R.GetAudioAccessorSamples(accessor,sr,nchan,a+pos,N,samplebuf)
   if type(rc)=='number' and rc>=0 then
    local values=samplebuf.table(1,N*nchan);local pwr=Core.texture_frame_loudness_power(values,N,nchan)
    if pwr>1e-24 then
     local lufs=-.691+10*math.log(pwr,10)
     frame_meta[#frame_meta+1]={pos=pos,power=pwr,lufs=lufs}
     if lufs>max_lufs then max_lufs=lufs end
    end
   end
  end
  if #frame_meta==0 or not finite(max_lufs) then return nil,'解析範囲が無音です。' end
  local gate_lufs=max_lufs-Core.TEXTURE_FRAME_GATE_DB
  local target_power=10^((Core.TEXTURE_TARGET_LUFS+.691)/10)
  local gain_min=10^(-Core.TEXTURE_NORM_GAIN_DB/20);local gain_max=10^(Core.TEXTURE_NORM_GAIN_DB/20)
  local bins=Core.TEXTURE_SPECTRUM_BINS;local mean_power,activity,active_hits,active_run,max_run={},{},{},{},{}
  local freqs,fft_index={},{};local denom=math.log(Core.TEXTURE_FREQ_MAX/Core.TEXTURE_FREQ_MIN)
  for i=1,bins do
   mean_power[i]=0;activity[i]=0;active_hits[i]=0;active_run[i]=0;max_run[i]=0
   local xx=(i-1)/max(1,bins-1);local f=Core.TEXTURE_FREQ_MIN*math.exp(denom*xx)
   freqs[i]=f;fft_index[i]=clamp(floor(f*N/sr+.5),1,N/2-1)
  end
  local used_frames=0
  for _,meta in ipairs(frame_meta) do if meta.lufs>=gate_lufs then
   samplebuf.clear();local rc=R.GetAudioAccessorSamples(accessor,sr,nchan,a+meta.pos,N,samplebuf)
   if type(rc)=='number' and rc>=0 then
    local values=samplebuf.table(1,N*nchan)
    local norm_gain=clamp(math.sqrt(target_power/max(meta.power,1e-30)),gain_min,gain_max)
    local band_power={};for i=1,bins do band_power[i]=0 end
    local channels_used=0
    for ch=1,nchan do
     local samples={};local energy=0
     for n=0,N-1 do
      local x=(values[n*nchan+ch] or 0)*norm_gain
      local w=.5-.5*math.cos(2*math.pi*n/max(1,N-1));x=x*w;samples[n+1]=x;energy=energy+x*x
     end
     if energy>1e-18 then
      local fftbuf=R.new_array(samples,N);fftbuf.fft_real(N,true);local fft=fftbuf.table(1,N)
      for i=1,bins do
       local k=fft_index[i];local re=fft[2*k+1] or 0;local im=fft[2*k+2] or 0
       band_power[i]=band_power[i]+re*re+im*im
      end
      channels_used=channels_used+1
     end
    end
    if channels_used>0 then
     local frame_db={};local sorted={};local frame_max=-math.huge
     for i=1,bins do
      local pp=band_power[i]/channels_used;mean_power[i]=mean_power[i]+pp
      local d=10*math.log(max(pp,1e-30),10);frame_db[i]=d;if d>frame_max then frame_max=d end
     end
     if finite(frame_max) then
      for i=1,bins do local rel=clamp(frame_db[i]-frame_max,-120,0);frame_db[i]=rel;sorted[i]=rel end
      table.sort(sorted)
      local activity_floor=max(-30,Core.texture_percentile(sorted,.70)-3.0)
      local activity_span=max(3,-activity_floor)
      for i=1,bins do
       local rel=frame_db[i];local soft=clamp((rel-activity_floor)/activity_span,0,1)^.72
       activity[i]=activity[i]+soft
       if soft>=.22 then
        active_hits[i]=active_hits[i]+1;active_run[i]=active_run[i]+1;max_run[i]=max(max_run[i],active_run[i])
       else active_run[i]=0 end
      end
      used_frames=used_frames+1
     end
    end
   end
  else
   for i=1,bins do active_run[i]=0 end
  end end
  if used_frames==0 then return nil,'ラウドネスゲート内に解析可能な音声がありません。' end
  local spec={freq=freqs,db={},persistence={}}
  local maxdb=-math.huge
  for i=1,bins do
   local d=10*math.log(max(mean_power[i]/used_frames,1e-30),10);spec.db[i]=d;if d>maxdb then maxdb=d end
   local hard=active_hits[i]/used_frames;local soft=activity[i]/used_frames;local continuous=max_run[i]/max(1,#frame_meta)
   spec.persistence[i]=clamp(.58*hard+.24*soft+.18*continuous,0,1)
  end
  if not finite(maxdb) then return nil,'スペクトルを取得できません。' end
  for i=1,bins do spec.db[i]=clamp(spec.db[i]-maxdb,-120,0) end
  local ps={}
  for i=1,bins do
   local a0=spec.persistence[max(1,i-1)] or 0;local a1=spec.persistence[i] or 0;local a2=spec.persistence[min(bins,i+1)] or 0
   ps[i]=clamp(.18*a0+.64*a1+.18*a2,0,1)
  end
  spec.persistence=ps
  return spec,nil
 end,debug.traceback)
 pcall(R.DestroyAudioAccessor,accessor)
 if not ok then return nil,tostring(result):match('^[^\n]+') or tostring(result) end
 return result,reason
end
function Core.rand_texture_shape(rng)
 return {detail=clamp(floor(rng(20,31)),20,30),depth=rng(.92,1.18),sharp=rng(.88,1.16),jitter_oct=rng(.001,.014),freq_scale=math.exp(rng(math.log(.965),math.log(1.037)))}
end
function Core.texture_shuffle_next(bank,state,rng)
 if not bank or #bank==0 then return nil,nil end
 state=state or {};local n=#bank
 if state.bank_size~=n or type(state.order)~='table' then state.order={};state.pos=n+1;state.last=nil;state.bank_size=n end
 if (state.pos or n+1)>#state.order then
  local order={};for i=1,n do order[i]=i end
  for i=n,2,-1 do local j=clamp(1+floor(rng()*i),1,i);order[i],order[j]=order[j],order[i] end
  if n>1 and state.last and order[1]==state.last then order[1],order[2]=order[2],order[1] end
  state.order=order;state.pos=1
 end
 local idx=state.order[state.pos];state.pos=state.pos+1;state.last=idx
 return bank[idx],idx,state
end
function Core.texture_eq_from_spectrum(spec,p)
 if not spec or type(spec)~='table' or type(spec.db)~='table' or type(spec.freq)~='table' or #spec.db<8 then return {} end
 p=p or {};local n=#spec.db;local want=min(p.detail or 25,max(4,n-2))
 local persist=type(spec.persistence)=='table' and #spec.persistence==n and spec.persistence or nil
 if not persist then return {} end
  local profile,broad={},{};local pmin,pmax=1,0
  for i=1,n do
   local occ=clamp(tonumber(persist[i]) or 0,0,1)
   local energy=clamp(((spec.db[i] or -120)+72)/72,0,1)
   profile[i]=clamp(.84*occ+.16*energy,0,1);pmin=min(pmin,profile[i]);pmax=max(pmax,profile[i])
  end
  local radius=clamp(floor(n/22),5,11)
  for i=1,n do
   local sum,ws=0,0
   for k=max(1,i-radius),min(n,i+radius) do local w=1-abs(k-i)/(radius+1);sum=sum+profile[k]*w;ws=ws+w end
   broad[i]=ws>0 and sum/ws or profile[i]
  end
  local peaks,cuts={},{};local range=max(.06,pmax-pmin);local peak_floor=max(.055,pmax*.30)
  local global_i=1;for i=2,n do if profile[i]>profile[global_i] then global_i=i end end
  for i=2,n-1 do
   local v=profile[i];local prev,nextv=profile[i-1],profile[i+1];local energy=clamp(((spec.db[i] or -120)+72)/72,0,1)
   if v>=peak_floor and v>=prev and v>=nextv then
    local prom=max(0,v-(broad[i] or v));local rank=clamp((v-pmin)/range,0,1)
    local strength=clamp((.58*rank+.42*(v/max(.08,pmax)))^.68,0,1)
    peaks[#peaks+1]={i=i,sign=1,strength=strength,score=v*(1+.9*prom)*(.55+.45*energy)}
   end
   local drop=(broad[i] or v)-v
   if drop>.055 and v<=prev and v<=nextv and (spec.db[i] or -120)>-78 and (broad[i] or 0)>.10 then
    local strength=clamp((drop/max(.10,range))^.68,0,1)
    cuts[#cuts+1]={i=i,sign=-1,strength=strength,score=drop*(.55+.45*energy)}
   end
  end
  if #peaks==0 then peaks[1]={i=global_i,sign=1,strength=1,score=profile[global_i]} end
  table.sort(peaks,function(a,b)return a.score>b.score end);table.sort(cuts,function(a,b)return a.score>b.score end)
  local selected={};local minsep=3;local boost_target=min(want,max(1,ceil(want*.68)))
  local function add_separated(c)
   for _,q in ipairs(selected) do if abs(q.i-c.i)<minsep then return false end end
   selected[#selected+1]=c;return true
  end
  local region_best={nil,nil,nil};local region_floor=max(.065,pmax*.28)
  for i=2,n-1 do
   local f=spec.freq[i] or 1000;local ri=(f<Core.TEXTURE_LOW_MAX) and 1 or ((f<Core.TEXTURE_MID_MAX) and 2 or 3)
   local v=profile[i] or 0;local energy=clamp(((spec.db[i] or -120)+72)/72,0,1)
   if v>=region_floor and energy>=.055 and (spec.db[i] or -120)>-84 then
    local score=v*(.58+.42*energy)
    if not region_best[ri] or score>region_best[ri].score then
     local rank=clamp((v-pmin)/range,0,1);local strength=clamp((.58*rank+.42*(v/max(.08,pmax)))^.68,0,1)
     region_best[ri]={i=i,sign=1,strength=strength,score=score,region_seed=true}
    end
   end
  end
  for ri=1,3 do local c=region_best[ri];if c then add_separated(c) end end
  for _,c in ipairs(peaks) do if #selected>=boost_target then break end;add_separated(c) end
  local cut_target=max(0,want-#selected);local cut_added=0
  for _,c in ipairs(cuts) do
   if cut_added>=cut_target then break end
   if add_separated(c) then cut_added=cut_added+1 end
  end
  local bands={};local scale=tonumber(p.depth) or 1;local qscale=tonumber(p.sharp) or 1;local fscale=tonumber(p.freq_scale) or 1;local jitter=tonumber(p.jitter_oct) or 0
  local step_oct=math.log(Core.TEXTURE_FREQ_MAX/Core.TEXTURE_FREQ_MIN,2)/max(1,n-1)
  for _,c in ipairs(selected) do
   local freq=(spec.freq[c.i] or 1000)*fscale*2^(jitter*(((c.i*37)%101)/50-1));freq=clamp(freq,Core.TEXTURE_FREQ_MIN,Core.TEXTURE_FREQ_MAX)
   local v=profile[c.i] or 0;local support_level=max(.05,v*.55);local lo,hi=c.i,c.i
   while lo>1 and c.i-lo<5 and profile[lo-1]>=support_level do lo=lo-1 end
   while hi<n and hi-c.i<5 and profile[hi+1]>=support_level do hi=hi+1 end
   local support_oct=max(step_oct,(hi-lo+1)*step_oct);local gain,bw
   if c.sign<0 then
    gain=-clamp((10+14*c.strength)*scale,7,24)
    bw=clamp((.098+.46*support_oct+.040*c.strength)*qscale,.085,.255)
   else
    gain=clamp((12+12*c.strength)*scale,8,24)
    bw=clamp((.040+.38*support_oct+.022*v)*qscale,.040,.145)
   end
   bands[#bands+1]={freq=freq,gain=gain,bw=bw}
  end
 table.sort(bands,function(a,b)return a.freq<b.freq end);return bands
end

function Core.scale_texture_bands(bands,percent)
 local scale=clamp(tonumber(percent) or 100,1,200)/100
 if abs(scale-1)<1e-12 then return bands or {} end
 local out={}
 for _,b in ipairs(bands or {}) do
  local target=(tonumber(b.gain) or 0)*scale
  local sign=target<0 and -1 or 1;local remain=abs(target)
  if remain<1e-9 then
   out[#out+1]={freq=b.freq,gain=0,bw=b.bw}
  else
   while remain>1e-9 do
    local chunk=min(24,remain)
    out[#out+1]={freq=b.freq,gain=sign*chunk,bw=b.bw}
    remain=remain-chunk
   end
  end
 end
 return out
end

function Core.auto_texture_eq(rng)
 local family=floor(rng()*4)+1
 local target_count=floor(rng(12,17))
 local bands={}
 local function add(freq,gain,bw)
  if freq>=45 and freq<=19000 then
   gain=clamp(gain,-24,24)
   if gain<0 then
    gain=max(gain,-24)
    bw=clamp((bw or .04)*2.7,.060,.17)
   else
    bw=clamp((bw or .04)*1.42,.028,.090)
   end
   bands[#bands+1]={freq=clamp(freq,45,19000),gain=gain,bw=bw}
  end
 end
 if family==1 then
  local base=math.exp(rng(math.log(70),math.log(330)))
  local stretch=rng(-.003,.010)
  for n=1,target_count+5 do
   local f=base*n*(1+stretch*(n-1))*rng(.995,1.006)
   local decay=clamp(1-(n-1)/(target_count+8),.38,1)
   local cut=(n>3 and n%6==0 and rng()<.55)
   add(f,cut and -rng(17,24) or rng(17,24)*decay+rng(1.5,4.0),rng(.018,.055))
   if #bands>=target_count then break end
  end
 elseif family==2 then
  local base=math.exp(rng(math.log(65),math.log(290)))
  local warp=rng(.990,1.022)
  for n=1,target_count+6 do
   local f=base*n*(warp^((n-1)*.28))*rng(.994,1.008)
   local peak=(n%2)==1
   add(f,peak and rng(16,24) or -rng(17,24),rng(.018,.060))
   if #bands>=target_count then break end
  end
 elseif family==3 then
  local center=math.exp(rng(math.log(220),math.log(1700)))
  local spread=rng(1.11,1.22)
  for i=1,target_count+4 do
   local k=i-(target_count+1)/2
   local f=center*(spread^k)*rng(.992,1.010)
   local peak=(i%3)~=0
   add(f,peak and rng(14,24) or -rng(18,24),rng(.020,.070))
   if #bands>=target_count then break end
  end
 else
  local base=math.exp(rng(math.log(250),math.log(900)))
  for n=1,target_count+6 do
   local harmonic=n+rng(-.07,.10)
   local f=base*harmonic*rng(.994,1.008)
   local cut=(n%5==0 or n%7==0) and rng()<.78
   add(f,cut and -rng(18,24) or rng(15,24),rng(.018,.050))
   if #bands>=target_count then break end
  end
 end
 while #bands<target_count do
  local f=math.exp(rng(math.log(120),math.log(17500)))
  add(f,(#bands%4==2) and -rng(17,24) or rng(14,24),rng(.018,.065))
 end
 table.sort(bands,function(a,b)return a.freq<b.freq end)
 return bands
end

function Core.rand_tone(rng,s)
 local function axis(positive,negative)
  positive=positive~=false;negative=negative~=false
  if not positive and not negative then return 0 end
  local lo,hi=s.tone_lo,s.tone_hi
  local crosses=lo<=0 and hi>=0
  local mag_lo=crosses and 0 or min(abs(lo),abs(hi))
  local mag_hi=max(abs(lo),abs(hi))
  if mag_hi<=1e-12 then return 0 end
  local mag=rng(mag_lo,mag_hi)
  if positive and negative then return mag*rng(-1,1) end
  return positive and mag or -mag
 end
 local bright=axis(s.tone_bright,s.tone_dark)
 local forward=axis(s.tone_forward,s.tone_recessed)
 local low=(-bright*rng(.38,.58))-(forward*rng(.04,.12))
 local presence=(bright*rng(.06,.16))+(forward*rng(.84,1.00))
 local high=(bright*rng(.88,1.00))+(forward*rng(.02,.10))
 local band_cap=24
 return {low=clamp(low,-band_cap,band_cap),presence=clamp(presence,-band_cap,band_cap),
  high=clamp(high,-band_cap,band_cap),bright=bright,forward=forward}
end
function Core.any_item_feature(a,list,key)
 for _,v in ipairs(list) do if Core.feature_supported(v,key) and ((a.items or {})[v.guid] or {})[key] then return true end end
 return false
end
function Core.item_feature(a,v,key) return Core.feature_supported(v,key) and ((a.items or {})[v.guid] or {})[key]==true end
function Core.avoid_blocks(anchor,low,high,blocks,gap_after)
 gap_after=gap_after or 0
 for _,b in ipairs(blocks or {}) do
  if anchor+high>b.a+1e-9 and anchor+low<b.b-1e-9 then anchor=b.b+gap_after-low end
 end
 return anchor
end
function Core.apply_voice_policy(groups,s)
 local by_source,by_track={},{}
 for _,g in ipairs(groups) do
  for _,row in ipairs(g.rows) do
   row.render_len=row.len;row.voice_fade=nil;row.voice_stolen=false;row.is_original=false
   if not (row.info and row.info.is_midi) then
    local guid=row.info and row.info.guid or ''
    local bucket=by_source[guid];if not bucket then bucket={};by_source[guid]=bucket end;bucket[#bucket+1]=row
    local track=row.info and row.info.track
    if track then local tb=by_track[track];if not tb then tb={};by_track[track]=tb end;tb[#tb+1]=row end
   end
  end
 end
 local originals={}
 for guid,rows in pairs(by_source) do
  local first=rows[1];local info=first and first.info
  if info and info.item then
   local root={info=info,item_ref=info.item,pos=info.pos,len=info.len,render_len=info.len,
    voice_limit=max(0,floor(tonumber(first.voice_limit) or 0)),voice_fade=nil,voice_stolen=false,is_original=true}
   table.insert(rows,1,root);originals[#originals+1]=root
   local track=info.track
   if track then local tb=by_track[track];if not tb then tb={};by_track[track]=tb end;tb[#tb+1]=root end
  end
 end
 local function row_less(a,b)
  if a.pos~=b.pos then return a.pos<b.pos end
  if a.is_original~=b.is_original then return a.is_original end
  return ((a.info and a.info.guid) or '')<((b.info and b.info.guid) or '')
 end
 local fade=max(0,(tonumber(s.voice_fade_ms) or 0)/1000)
 for _,rows in pairs(by_source) do
  table.sort(rows,row_less)
  local limit=rows[1] and max(0,floor(tonumber(rows[1].voice_limit) or 0)) or 0
  if limit>0 then
   local active={}
   for _,row in ipairs(rows) do
    local t=row.pos
    for i=#active,1,-1 do
     local r=active[i]
     if r.pos+(r.render_len or r.len)<=t+1e-9 then table.remove(active,i) end
    end
    while #active>=limit do
     local oldest_i=1
     for i=2,#active do
      if active[i].pos<active[oldest_i].pos or (active[i].pos==active[oldest_i].pos and active[i].is_original) then oldest_i=i end
     end
     local victim=table.remove(active,oldest_i)
     local rel=max(0,t-victim.pos);local current_len=victim.render_len or victim.len
     if rel<current_len-1e-9 then
      local f=min(fade,max(0,current_len-rel))
      victim.render_len=max(1e-6,rel+f);victim.voice_fade=f;victim.voice_stolen=true
     end
    end
    active[#active+1]=row
   end
  end
 end
 for _,rows in pairs(by_track) do
  table.sort(rows,row_less)
  local lane_ends={};local lane_count=0
  for _,row in ipairs(rows) do
   local lane=nil
   for i=1,lane_count do if lane_ends[i]<=row.pos+1e-9 then lane=i;break end end
   if not lane then lane_count=lane_count+1;lane=lane_count end
   row.free_lane=lane;lane_ends[lane]=row.pos+(row.render_len or row.len)
  end
  if lane_count>1 then
   for _,row in ipairs(rows) do row.free_mode=true;row.free_lane_count=lane_count end
  end
 end
 groups._voice_originals=originals
end
function Core.plan(list,s,a,blocks)
 local ok,err=Core.validate(s);if not ok then return nil,err end
 if #list==0 then return nil,'対象がありません。' end;if #list*s.count>2000 then return nil,'1回の生成は合計2000アイテムまでです。' end
 a=a or {lock={},items={}};a.lock=a.lock or {}
 local rng=Core.rng(s.seed);local pools={};local texture_track_pools={};local groups={};local first=list[1].pos;local original_end=first
 for _,v in ipairs(list) do original_end=max(original_end,v.pos+v.len) end
 local feature_any={}
 for _,key in ipairs(Core.FEATURES) do feature_any[key]=Core.any_item_feature(a,list,key) end
 if feature_any.pitch_curve and s.curve_length_mode==2 then
  for _,v in ipairs(list) do if Core.item_feature(a,v,'pitch_curve') and R.GetTakeNumStretchMarkers(v.take)>0 then return nil,'ピッチカーブの尺連動は既存ストレッチマーカー付き素材には適用できません。' end end
 end
 local texture_has_bank=false
 if feature_any.eq_texture then for _,v in ipairs(list) do if v.texture_bank and #v.texture_bank>0 then texture_has_bank=true;break end end end
 local prev_high=original_end;local head_first=nil
 for n=1,s.count do
  local shared={};local texture_choice={}
  if a.lock.pitch_global and feature_any.pitch_global then shared.pitch=rng(s.pitch_lo,s.pitch_hi) end
  if a.lock.pitch_curve and feature_any.pitch_curve then shared.curve=Core.rand_curve(rng,s.curve_lo,s.curve_hi,s.curve_points,s.curve_guide_enabled,s.curve_guide_data,s.curve_guide_start,s.curve_guide_end,s.curve_start_pct,s.curve_end_pct) end
  if a.lock.vibrato and feature_any.vibrato then shared.vibrato=Core.rand_modulation(rng,s,'vibrato') end
  if a.lock.tremolo and feature_any.tremolo then shared.tremolo=Core.rand_modulation(rng,s,'tremolo') end
  if a.lock.timing and feature_any.timing then shared.timing=rng(s.timing_lo,s.timing_hi)/1000 end
  if a.lock.volume and feature_any.volume then shared.volume=rng(s.volume_lo,s.volume_hi) end
  if a.lock.pan and feature_any.pan then shared.pan=rng(s.pan_lo,s.pan_hi) end
  if a.lock.eq_texture and feature_any.eq_texture then if texture_has_bank then shared.texture_shape=Core.rand_texture_shape(rng) else shared.texture_auto=Core.auto_texture_eq(rng) end end
  if a.lock.eq_tone and feature_any.eq_tone then shared.tone=Core.rand_tone(rng,s) end
  local g={rows={},index=n};local low,high=math.huge,-math.huge
  for _,v in ipairs(list) do
   local ia=(a.items or {})[v.guid] or {};local jitter=0
   if Core.item_feature(a,v,'timing') then jitter=a.lock.timing and shared.timing or rng(s.timing_lo,s.timing_hi)/1000 end
   local row={info=v,rel=v.pos-first,timing=jitter,offset=v.offset,pitch=v.pitch,playrate=v.rate,ppitch=v.ppitch,len=v.len,voice_limit=v.is_midi and 0 or max(0,floor(tonumber(ia.voice_limit) or 0))}
   if Core.item_feature(a,v,'pitch_global') then
    local pd=a.lock.pitch_global and shared.pitch or rng(s.pitch_lo,s.pitch_hi)
    if v.is_midi then
     pd=midi_semitone(pd);row.pitch=v.pitch+pd
     if s.pitch_length_mode==2 then local f=2^(pd/12);row.playrate=v.rate*f;row.len=v.len/f;row.ppitch=0 end
    elseif s.pitch_length_mode==1 then row.pitch=v.pitch+pd
    else local f=2^(pd/12);row.playrate=v.rate*f;row.len=v.len/f;row.ppitch=0;row.pitch=v.pitch end
   end
   if Core.item_feature(a,v,'pitch_curve') then
    row.curve=a.lock.pitch_curve and shared.curve or Core.rand_curve(rng,s.curve_lo,s.curve_hi,s.curve_points,s.curve_guide_enabled,s.curve_guide_data,s.curve_guide_start,s.curve_guide_end,s.curve_start_pct,s.curve_end_pct)
    row.curve_start_pct=s.curve_start_pct;row.curve_end_pct=s.curve_end_pct;row.curve_length_mode=s.curve_length_mode
    if s.curve_length_mode==2 then row.curve_base_len=row.len;row.len,row.curve_link_markers=Core.curve_link_map(row.curve_base_len,row.playrate,row.curve,row.curve_start_pct,row.curve_end_pct);row.ppitch=0 end
   end
   if Core.item_feature(a,v,'vibrato') then row.vibrato=a.lock.vibrato and shared.vibrato or Core.rand_modulation(rng,s,'vibrato') end
   if Core.item_feature(a,v,'tremolo') then row.tremolo=a.lock.tremolo and shared.tremolo or Core.rand_modulation(rng,s,'tremolo') end
   if Core.item_feature(a,v,'volume') then local vd=a.lock.volume and shared.volume or rng(s.volume_lo,s.volume_hi);row.volume=v.gain*10^(vd/20) end
   if Core.item_feature(a,v,'pan') then local pv=a.lock.pan and shared.pan or rng(s.pan_lo,s.pan_hi);row.pan=pv/100 end
   if Core.item_feature(a,v,'eq_texture') then
    if v.texture_bank and #v.texture_bank>0 then
     local shape=a.lock.eq_texture and shared.texture_shape or Core.rand_texture_shape(rng)
     local track_key=v.track or v.tracknum or v.guid;local tex_i=texture_choice[track_key];local tex=nil
     if not tex_i then
      local state=texture_track_pools[track_key] or {};tex,tex_i,state=Core.texture_shuffle_next(v.texture_bank,state,rng);texture_track_pools[track_key]=state;texture_choice[track_key]=tex_i
     else tex=v.texture_bank[tex_i] end
     row.eq=Core.scale_texture_bands(Core.texture_eq_from_spectrum(tex and tex.spectrum or nil,shape),s.texture_strength);row.texture_shape=shape;row.texture_source_index=tex_i;row.texture_source_name=tex and tex.name or nil
    else
     row.eq=Core.scale_texture_bands(a.lock.eq_texture and shared.texture_auto or Core.auto_texture_eq(rng),s.texture_strength);row.texture_source_name='AUTO TEXTURE'
    end
   end
   if Core.item_feature(a,v,'eq_tone') then row.tone=a.lock.eq_tone and shared.tone or Core.rand_tone(rng,s) end
   if Core.item_feature(a,v,'source') then local sv=Core.pick_candidate(v,pools,rng,s.source_order);if sv then row.offset=sv.offset or v.offset;row.source_file=sv.file;row.source_name=sv.source_name;row.source_variant_id=sv.id;row.source_track_item=sv.track_item==true;row.source_track_guid=sv.track_guid;row.source_track_ref=sv.track_ref;row.source_channel_mode=sv.channel_mode;row.substituted=(not sv.original) or abs(row.offset-v.offset)>1e-9 end end
   low=min(low,row.rel);high=max(high,row.rel+row.len);g.rows[#g.rows+1]=row
  end
  local anchor
  if s.interval_mode==1 then
   anchor=prev_high+s.interval-low
   anchor=Core.avoid_blocks(anchor,low,high,blocks,s.interval)
  else
   if not head_first then local first_anchor=Core.avoid_blocks(first+s.interval-low,low,high,blocks,0);head_first=first_anchor+low end
   anchor=head_first+(n-1)*s.interval-low
  end
  prev_high=anchor+high;g.anchor=anchor;g.first=math.huge;g.last=-math.huge
  for _,row in ipairs(g.rows) do
   row.pos=max(0,anchor+row.rel+row.timing)
   if row.timing~=0 then row.pos=Core.avoid_blocks(row.pos,0,row.len,blocks,s.interval_mode==1 and s.interval or 0) end
   g.first=min(g.first,row.pos);g.last=max(g.last,row.pos+row.len)
  end
  groups[#groups+1]=g
 end
 Core.apply_voice_policy(groups,s)
 return groups
end
function Core.set_fx_param(take,fx,param,value)
 local ok=R.TakeFX_SetParamNormalized(take,fx,param,value)
 R.TakeFX_EndParamEdit(take,fx,param)
 return ok
end
function Core.eq_normalized(take,fx,param,target,kind)
 local function parse(text)
  text=tostring(text or '');local v=tonumber(text:match('[-+]?%d+%.?%d*'))
  if not v and text:lower():find('inf',1,true) then return text:find('-',1,true) and -math.huge or math.huge end
  if not finite(v) then error('EQの表示値を読み取れません：'..text,0) end
  if kind=='freq' and text:lower():find('khz',1,true) then v=v*1000 end;return v
 end
 local function value(n)
  if type(R.TakeFX_FormatParamValueNormalized)=='function' then local ok,text=R.TakeFX_FormatParamValueNormalized(take,fx,param,n);if ok then return parse(text) end end
  if not Core.set_fx_param(take,fx,param,n) then error('EQ値を設定できません。',0) end
  local ok,text=R.TakeFX_GetFormattedParamValue(take,fx,param);if not ok then error('EQのパラメーター単位を取得できません。',0) end;return parse(text)
 end
 local lo,hi=0,1;local av,bv=value(lo),value(hi);local low,high=min(av,bv),max(av,bv)
 target=clamp(target,low,high)
 local ascending=bv>=av;for _=1,20 do local mid=(lo+hi)/2;local v=value(mid);if (ascending and v<target) or (not ascending and v>target) then lo=mid else hi=mid end end
 return (lo+hi)/2
end
function Core.hide_take_fx(take,fx)
 if type(R.TakeFX_SetOpen)=='function' then pcall(R.TakeFX_SetOpen,take,fx,false) end
 if type(R.TakeFX_Show)=='function' then pcall(R.TakeFX_Show,take,fx,2);pcall(R.TakeFX_Show,take,fx,0) end
end
function Core.suppress_new_fx_windows()
 if type(R.get_config_var_string)~='function' or type(R.set_config_var_string)~='function' then return nil end
 local ok,text=R.get_config_var_string('fxfloat_focus');local value=ok and tonumber(text) or nil;if not value then return nil end
 value=floor(value);if (value&4)==0 then return nil end;local muted=value&(~4)
 if R.set_config_var_string('fxfloat_focus',tostring(muted),0)==0 then return nil end;return text
end
function Core.restore_new_fx_windows(saved) if saved and type(R.set_config_var_string)=='function' then R.set_config_var_string('fxfloat_focus',saved,0) end end
function Core.reaeq_gain_normalized(target)
 target=clamp(tonumber(target) or 0,-24,24)
 return (target+24)/48
end
function Core.set_eq_value(take,fx,param,target,kind)
 local n
 if kind=='gain' then n=Core.reaeq_gain_normalized(target)
 else n=Core.eq_normalized(take,fx,param,target,kind) end
 if not Core.set_fx_param(take,fx,param,n) then error('EQパラメーターを設定できません。',0) end
end
function Core.set_eq_fixed(take,fx,param,target,kind)
 local key=param..'|'..tostring(target)..'|'..tostring(kind or '')
 local n=Core.EQ_FIXED_CACHE[key]
 if n==nil then n=Core.eq_normalized(take,fx,param,target,kind);Core.EQ_FIXED_CACHE[key]=n end
 if not Core.set_fx_param(take,fx,param,n) then error('EQパラメーターを設定できません。',0) end
end
function Core.add_reaeq(take)
 local fx=R.TakeFX_AddByName(take,'ReaEQ (Cockos)',-1);if fx<0 then error('ReaEQ (Cockos) を追加できません。',0) end
 Core.hide_take_fx(take,fx)
 if not R.TakeFX_SetPresetByIndex(take,fx,-2) then error('ReaEQの初期状態を設定できません。',0) end
 return fx
end
local EQ_BASE64='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function eq_decode(text)
 local out,word,bits={},0,0
 for c in text:gmatch('.') do
  if c~='=' and not c:match('%s') then
   local index=EQ_BASE64:find(c,1,true);assert(index,'ReaEQ設定を読み取れません。')
   word=(word<<6)|(index-1);bits=bits+6
   if bits>=8 then bits=bits-8;out[#out+1]=string.char((word>>bits)&255);word=word&((1<<bits)-1) end
  end
 end
 return table.concat(out)
end
local function eq_encode(raw)
 local out={}
 for i=1,#raw,3 do
  local a,b,c=raw:byte(i,i+2);local n=(a<<16)|((b or 0)<<8)|(c or 0)
  out[#out+1]=EQ_BASE64:sub((n>>18)+1,(n>>18)+1)..EQ_BASE64:sub(((n>>12)&63)+1,((n>>12)&63)+1)
   ..(b and EQ_BASE64:sub(((n>>6)&63)+1,((n>>6)&63)+1)or '=')..(c and EQ_BASE64:sub((n&63)+1,(n&63)+1)or '=')
 end
 return table.concat(out)
end
function Core.configure_texture_bands(take,fx,count)
 local ok,text=R.TakeFX_GetNamedConfigParm(take,fx,'vst_chunk')
 assert(ok and type(text)=='string','ReaEQ設定を読み取れません。')
 local raw=eq_decode(text)
 assert(#raw>=8,'未対応のReaEQ設定形式です。')
 local version,original=string.unpack('<I4I4',raw)
 assert(version==33 and original>=2 and original<=256 and #raw>=8+original*33+24,'未対応のReaEQ設定形式です。')
 local bell=raw:sub(42,74);local kind,enabled=string.unpack('<I4I4',bell)
 assert(kind==8 and enabled==1,'未対応のReaEQ設定形式です。')
 local expanded=string.pack('<I4I4',version,count)..bell:rep(count)..raw:sub(9+original*33)
 assert(R.TakeFX_SetNamedConfigParm(take,fx,'vst_chunk',eq_encode(expanded)),'ReaEQのバンド数を設定できません。')
 assert(R.TakeFX_GetNumParams(take,fx)==count*3+4,'ReaEQのバンド数を設定できません。')
 local valid,saved=R.TakeFX_GetNamedConfigParm(take,fx,'vst_chunk')
 assert(valid,'ReaEQのバンド数を設定できません。')
 local check=eq_decode(saved)
 assert(#check>=8 and select(2,string.unpack('<I4I4',check))==count,'ReaEQのバンド数を設定できません。')
end
function Core.add_texture_eq(take,bands,checkpoint)
 bands=bands or {};if #bands==0 then return 0 end
 local fx=Core.add_reaeq(take)
 Core.configure_texture_bands(take,fx,#bands)
 for i,band in ipairs(bands)do
  local param=(i-1)*3
  Core.set_eq_value(take,fx,param,band.freq,'freq')
  Core.set_eq_value(take,fx,param+1,band.gain,'gain')
  Core.set_eq_value(take,fx,param+2,band.bw,'bw')
  if checkpoint then checkpoint(i/#bands)end
 end
 pcall(R.TakeFX_SetNamedConfigParm,take,fx,'renamed_name','BLT Variant Forge Texture EQ')
 Core.hide_take_fx(take,fx)
 return 1
end
local function media_path_key(path)
 if type(path)~='string' or path=='' then return nil end
 local key=path:gsub('\\','/'):gsub('/+','/')
 local osname=type(R.GetOS)=='function' and (R.GetOS() or '') or ''
 if osname:match('Win') or osname:match('OSX') or osname:match('macOS') then key=key:lower() end
 return key
end
local function media_source_path(source)
 local current=source
 for _=1,8 do
  if not current then break end
  local path=R.GetMediaSourceFileName(current,'')
  if type(path)=='string' and path~='' then return path end
  if type(R.GetMediaSourceParent)~='function' then break end
  local ok,parent=pcall(R.GetMediaSourceParent,current)
  if not ok or not parent or parent==current then break end
  current=parent
 end
 return ''
end
function Core.project_media_references(project,refs)
 refs=refs or {}
 if not project then return refs end
 for i=0,R.CountMediaItems(project)-1 do
  local item=R.GetMediaItem(project,i)
  for ti=0,R.CountTakes(item)-1 do
   local take=R.GetTake(item,ti)
   if take and not R.TakeIsMIDI(take) then
    local source=R.GetMediaItemTake_Source(take)
    if source then
     local key=media_path_key(media_source_path(source))
     if key then refs[key]=true end
    end
   end
  end
 end
 return refs
end
function Core.all_open_project_media_references()
 local refs={};local i=0
 while true do
  local project=R.EnumProjects(i,'');if not project then break end
  Core.project_media_references(project,refs);i=i+1
 end
 return refs
end
function Core.cleanup_bake_files(paths,project)
 local failed,retained={},{}
 if type(R.reduce_open_files)=='function' then pcall(R.reduce_open_files,2) end
 local seen={};local refs=Core.all_open_project_media_references()
 for _,path in ipairs(paths or {}) do
  local path_key=media_path_key(path)
  if path_key and not seen[path_key] then
   seen[path_key]=true
   if refs[path_key] then retained[#retained+1]=path
   else
    local peak=nil
    if type(R.GetPeakFileName)=='function' then local ok,v=pcall(R.GetPeakFileName,path);if ok then peak=v end end
    local ok=true
    if type(R.file_exists)~='function' or R.file_exists(path) then ok=os.remove(path) and true or false end
    if ok then
     if type(peak)=='string' and peak~='' and (type(R.file_exists)~='function' or R.file_exists(peak)) then
      local peak_ok,peak_result=pcall(os.remove,peak)
      if not peak_ok or not peak_result then failed[#failed+1]=peak end
     end
    else failed[#failed+1]=path end
   end
  end
 end
 return failed,retained
end
local function hex_encode(value)
 return (tostring(value or ''):gsub('.',function(c)return string.format('%02X',string.byte(c)) end))
end
local function hex_decode(value)
 if type(value)~='string' or #value%2~=0 or value:find('[^%x]') then return nil end
 local out={};for i=1,#value,2 do out[#out+1]=string.char(tonumber(value:sub(i,i+1),16)) end
 return table.concat(out)
end
function Core.project_guid(project)
 if not project or type(R.GetProjectGUID)~='function' then return '' end
 local ok,guid=pcall(R.GetProjectGUID,project);return ok and tostring(guid or '') or ''
end
function Core.open_project_by_guid(guid,hint)
 if guid=='' then return Core.project_is_open(hint) and hint or nil end
 if hint and Core.project_is_open(hint) and Core.project_guid(hint)==guid then return hint end
 local i=0
 while true do local project=R.EnumProjects(i,'');if not project then break end;if Core.project_guid(project)==guid then return project end;i=i+1 end
 return nil
end
function Core.load_pending_bake_deletes()
 local raw=R.GetExtState(Core.SECTION,'pending_bake_delete_v1');local out={}
 for line in tostring(raw or ''):gmatch('[^\n]+') do
  local guid_hex,watch,path_hex=line:match('^([%x]*):([01]):([%x]+)$')
  if not guid_hex then guid_hex,path_hex=line:match('^([%x]*):([%x]+)$');watch='0' end
  local guid,path=hex_decode(guid_hex),hex_decode(path_hex)
  if guid and path and path~='' then out[#out+1]={project_guid=guid,path=path,watch_referenced=watch=='1'} end
 end
 return out
end
function Core.save_pending_bake_deletes(records)
 local lines={}
 for _,record in ipairs(records or {}) do
  if record.path and record.path~='' then lines[#lines+1]=hex_encode(record.project_guid or '')..':'..(record.watch_referenced and '1' or '0')..':'..hex_encode(record.path) end
 end
 BLT.store(Core.SECTION,'pending_bake_delete_v1',table.concat(lines,'\n'),true)
end
function Core.queue_pending_bake_deletes(records,paths,project,watch_referenced)
 records=records or Core.load_pending_bake_deletes();local guid=Core.project_guid(project);local seen={}
 for i,record in ipairs(records) do
  if type(record)=='string' then record={path=record,project=project,project_guid=guid};records[i]=record end
  local key=media_path_key(record.path)
  if key then seen[tostring(record.project_guid or '')..'\0'..key]=record end
 end
 for _,path in ipairs(paths or {}) do
  local key=media_path_key(path);local record_key=guid..'\0'..tostring(key or '')
  if key and not seen[record_key] then
   local record={path=path,project=project,project_guid=guid,watch_referenced=watch_referenced and true or false}
   records[#records+1]=record;seen[record_key]=record
  elseif key and watch_referenced then
   seen[record_key].watch_referenced=true
  end
 end
 Core.save_pending_bake_deletes(records);return records
end
function Core.is_texture_fx(take,fx)
 if not take then return false end
 local name=''
 if type(R.TakeFX_GetNamedConfigParm)=='function' then
  local ok,v=R.TakeFX_GetNamedConfigParm(take,fx,'renamed_name');if ok and type(v)=='string' then name=v end
 end
 if name=='' and type(R.TakeFX_GetFXName)=='function' then
  local ok,v=R.TakeFX_GetFXName(take,fx,'');if ok and type(v)=='string' then name=v end
 end
 return name:find('BLT Variant Forge Texture EQ',1,true)~=nil
end
function Core.texture_fx_count(take)
 if not take or type(R.TakeFX_GetCount)~='function' then return 0 end
 local n=0;for i=0,R.TakeFX_GetCount(take)-1 do if Core.is_texture_fx(take,i) then n=n+1 end end;return n
end
function Core.bake_texture_eq(project,item,take,texture_count,created_entry)
 texture_count=floor(tonumber(texture_count) or Core.texture_fx_count(take));if texture_count<=0 then return take end
 if type(R.TakeFX_CopyToTake)~='function' or type(R.TakeFX_GetCount)~='function'
    or type(R.TakeFX_GetEnabled)~='function' or type(R.TakeFX_SetEnabled)~='function'
    or type(R.TrackFX_GetCount)~='function' or type(R.TrackFX_GetEnabled)~='function'
    or type(R.TrackFX_SetEnabled)~='function' then
  error('TEXTURE EQの焼き込みに必要なREAPER APIを利用できません。',0)
 end
 if Core.texture_fx_count(take)<texture_count then texture_count=Core.texture_fx_count(take) end
 if texture_count<=0 then return take end
 for moved=0,texture_count-1 do
  local src=nil
  for i=R.TakeFX_GetCount(take)-1,moved,-1 do if Core.is_texture_fx(take,i) then src=i;break end end
  if src==nil then error('TEXTURE EQのFX位置を確認できません。',0) end
  if src~=0 then R.TakeFX_CopyToTake(take,src,take,0,true) end
 end
 local old_paths={}
 for i=0,R.GetMediaItemNumTakes(item)-1 do
  local tk=R.GetTake(item,i)
  if tk then local src=R.GetMediaItemTake_Source(tk);if src then local fn=R.GetMediaSourceFileName(src,'');local key=media_path_key(fn);if key then old_paths[key]=true end end end
 end
 local take_states={}
 for i=texture_count,R.TakeFX_GetCount(take)-1 do
  local enabled=R.TakeFX_GetEnabled(take,i);take_states[#take_states+1]={i=i,enabled=enabled}
  if enabled then R.TakeFX_SetEnabled(take,i,false) end
 end
 local track=R.GetMediaItemTrack(item);local track_states={}
 if track then
  for i=0,R.TrackFX_GetCount(track)-1 do
   local enabled=R.TrackFX_GetEnabled(track,i);track_states[#track_states+1]={i=i,enabled=enabled}
   if enabled then R.TrackFX_SetEnabled(track,i,false) end
  end
 end
 local before_takes=R.GetMediaItemNumTakes(item)
 local action_ok,action_err=xpcall(function()
  R.SelectAllMediaItems(project,false);R.SetMediaItemSelected(item,true)
  if type(R.UpdateItemInProject)=='function' then R.UpdateItemInProject(item) end
  R.Main_OnCommand(40209,0)
 end,debug.traceback)
 for _,st in ipairs(track_states) do pcall(R.TrackFX_SetEnabled,track,st.i,st.enabled) end
 for _,st in ipairs(take_states) do pcall(R.TakeFX_SetEnabled,take,st.i,st.enabled) end
 local after_takes=R.GetMediaItemNumTakes(item);local baked=R.GetActiveTake(item)
 local recorded={};created_entry.bake_files=created_entry.bake_files or {}
 for _,path in ipairs(created_entry.bake_files) do local key=media_path_key(path);if key then recorded[key]=true end end
 for i=0,after_takes-1 do
  local tk=R.GetTake(item,i);local src=tk and R.GetMediaItemTake_Source(tk);local path=src and R.GetMediaSourceFileName(src,'') or ''
  local key=media_path_key(path)
  if key and not old_paths[key] and not recorded[key] then created_entry.bake_files[#created_entry.bake_files+1]=path;recorded[key]=true end
 end
 if not action_ok then error('TEXTURE EQの焼き込みに失敗しました。\n'..tostring(action_err),0) end
 if after_takes<=before_takes or not baked or baked==take or R.TakeIsMIDI(baked) then error('TEXTURE EQの焼き込み結果を取得できません。',0) end
 while R.TakeFX_GetCount(baked)>0 do if not R.TakeFX_Delete(baked,0) then error('焼き込みTakeのFXを整理できません。',0) end end
 for _=1,texture_count do if not R.TakeFX_Delete(take,0) then error('TEXTURE EQの一時FXを削除できません。',0) end end
 for i=0,R.TakeFX_GetCount(take)-1 do R.TakeFX_CopyToTake(take,i,baked,R.TakeFX_GetCount(baked),false) end
 R.SetActiveTake(take);R.SelectAllMediaItems(project,false);R.SetMediaItemSelected(item,true);R.Main_OnCommand(40129,0)
 if not R.ValidatePtr2(project,baked,'MediaItem_Take*') then error('焼き込みTakeを確定できません。',0) end
 R.SetActiveTake(baked)
 return baked
end
function Core.add_tone_eq(take,p)
 local fx=Core.add_reaeq(take)
 Core.set_eq_fixed(take,fx,0,180,'freq');Core.set_eq_value(take,fx,1,p.low,'gain')
 Core.set_eq_fixed(take,fx,3,1800,'freq');Core.set_eq_value(take,fx,4,p.presence or 0,'gain');Core.set_eq_fixed(take,fx,5,2.2,'bw')
 Core.set_eq_fixed(take,fx,9,6500,'freq');Core.set_eq_value(take,fx,10,p.high,'gain')
 pcall(R.TakeFX_SetNamedConfigParm,take,fx,'renamed_name','BLT Variant Forge EQ Tone');Core.hide_take_fx(take,fx)
end
function Core.ensure_take_envelope(project,item,take,name,command,label_text)
 local env=R.GetTakeEnvelopeByName(take,name)
 if not env then R.SelectAllMediaItems(project,false);R.SetMediaItemSelected(item,true);R.Main_OnCommand(command,0);env=R.GetTakeEnvelopeByName(take,name) end
 if not env then error('Take '..label_text..'エンベロープを作成できません。',0) end
 local ok,state=R.GetEnvelopeStateChunk(env,'',false)
 if ok and state then R.SetEnvelopeStateChunk(env,state:gsub('ACT%s+0','ACT 1',1),false) end
 return env
end
function Core.reset_take_envelope(project,item,take,name,command,label_text)
 local env=Core.ensure_take_envelope(project,item,take,name,command,label_text)
 R.DeleteEnvelopePointRange(env,-1e20,1e20)
 return env
end
function Core.apply_linked_pitch_curve(take,row)
 local markers=row.curve_link_markers;if not markers or #markers<2 then return end
 R.DeleteTakeStretchMarkers(take,0,R.GetTakeNumStretchMarkers(take))
 local indices={}
 for i,m in ipairs(markers) do
  local idx=R.SetTakeStretchMarker(take,-1,m.pos,(row.offset or 0)+(m.src or 0))
  if idx<0 then error('尺連動用ストレッチマーカーを書き込めません。',0) end
  indices[i]=idx
 end
 for i=1,#markers-1 do
  if not R.SetTakeStretchMarkerSlope(take,indices[i],markers[i].slope or 0) then error('尺連動のピッチ遷移を設定できません。',0) end
 end
 R.SetMediaItemTakeInfo_Value(take,'B_PPITCH',0)
end
function Core.fixed_curve_value(row,t,a,b)
 if not row.curve or row.curve_length_mode==2 then return 0 end
 if not a then
  local duration=max(1e-9,row.len*row.playrate)
  a=duration*clamp((row.curve_start_pct or 0)/100,0,1);b=duration*clamp((row.curve_end_pct or 100)/100,0,1)
 end
 if t<a-1e-9 or t>b+1e-9 or b<=a then return 0 end
 return Core.curve_value(row.curve,(t-a)/max(1e-9,b-a))
end
function Core.vibrato_value(row,t,a,b,playrate,release)
 local m=row.vibrato;if not m or (m.depth or 0)<=0 then return 0 end
 if not a then local _;_,playrate,a,b,release=Core.mod_window(row,m) end
 if t<a or t>b or b<=a then return 0 end
 local elapsed=(t-a)/playrate;local remaining=(b-t)/playrate;local q=(t-a)/max(1e-9,b-a)
 local amp=(m.depth or 0)*Core.mod_shape(m.shape,q)*Core.mod_edge(m.rate,elapsed,remaining,release)
 return math.sin(elapsed*(m.rate or 1)*math.pi*2)*(m.phase_dir or 1)*amp
end
function Core.simplify_pitch_points(points,tolerance)
 if #points<3 then return points end
 local keep={[1]=true,[#points]=true};local stack={{1,#points}}
 while #stack>0 do
  local pair=table.remove(stack);local a,b=pair[1],pair[2];local p,q=points[a],points[b]
  local worst,index=tolerance,nil;local span=max(1e-12,q.t-p.t)
  for i=a+1,b-1 do local v=points[i];local expected=p.value+(q.value-p.value)*(v.t-p.t)/span;local error=abs(v.value-expected);if error>worst then worst,index=error,i end end
  if index then keep[index]=true;stack[#stack+1]={a,index};stack[#stack+1]={index,b} end
 end
 local result={};for i,p in ipairs(points) do if keep[i] then result[#result+1]=p end end
 return result
end

function Core.apply_pitch_envelope(project,item,take,row)
 local need_curve=row.curve and row.curve_length_mode~=2;local need_vib=row.vibrato and (row.vibrato.depth or 0)>0
 if not need_curve and not need_vib then return end
 local env=Core.reset_take_envelope(project,item,take,'Pitch',41612,'ピッチ')
 local duration=max(1e-9,row.len*row.playrate);local times={0,duration};local playrate=max(1e-6,row.playrate or 1)
 local curve_a,curve_b,curve_first,curve_last=nil,nil,0,0
 local vib_a,vib_b,vib_playrate,vib_release=nil,nil,nil,nil
 if need_curve then
  curve_a=duration*clamp((row.curve_start_pct or 0)/100,0,1);curve_b=duration*clamp((row.curve_end_pct or 100)/100,0,1)
  curve_first=Core.curve_value(row.curve,0);curve_last=Core.curve_value(row.curve,1)
  local transition=max(1e-6,.020*playrate)
  if curve_a>1e-8 and abs(curve_first)>1e-7 then times[#times+1]=max(0,curve_a-transition) end
  local active=max(0,curve_b-curve_a);local desired=max(2,#row.curve);local min_curve_gap=.010*playrate
  local curve_count=min(desired,max(2,floor(active/max(1e-9,min_curve_gap)+1)))
  for i=0,curve_count-1 do times[#times+1]=curve_a+active*i/max(1,curve_count-1) end
  if curve_b<duration-1e-8 and abs(curve_last)>1e-7 then times[#times+1]=min(duration,curve_b+transition) end
 end
 if need_vib then
  local m=row.vibrato;local _
  _,vib_playrate,vib_a,vib_b,vib_release=Core.mod_window(row,m)
  local count=Core.mod_point_count(m,vib_a,vib_b,vib_playrate)
  for i=0,count do times[#times+1]=vib_a+(vib_b-vib_a)*i/count end
 end
 table.sort(times)
 local pts={};local last_t=nil
 for _,t in ipairs(times) do
  if not last_t or abs(t-last_t)>1e-8 then
   pts[#pts+1]={t=t,value=Core.fixed_curve_value(row,t,curve_a,curve_b)+Core.vibrato_value(row,t,vib_a,vib_b,vib_playrate,vib_release),shape=0};last_t=t
  end
 end
 pts=Core.simplify_pitch_points(pts,.01)
 if need_curve and not need_vib then
  for i=1,#pts-1 do
   local v0,v1=pts[i].value,pts[i+1].value
   if (abs(v0)<=1e-7 and abs(v1)>1e-7) or (abs(v1)<=1e-7 and abs(v0)>1e-7) then pts[i].shape=2 end
  end
 end
 for _,p in ipairs(pts) do
  if not R.InsertEnvelopePoint(env,p.t,p.value,p.shape or 0,0,false,true) then error('ピッチ変調を書き込めません。',0) end
 end
 R.Envelope_SortPoints(env)
end
function Core.apply_tremolo(project,item,take,row)
 local m=row.tremolo;if not m or (m.depth or 0)<=0 then return end
 local duration,playrate,a,b,release=Core.mod_window(row,m);if b<=a+1e-9 then return end
 local env=Core.reset_take_envelope(project,item,take,'Volume',40693,'音量')
 local count=Core.mod_point_count(m,a,b,playrate);local mode=R.GetEnvelopeScalingMode(env)
 local function env_value(amp) return type(R.ScaleToEnvelopeMode)=='function' and R.ScaleToEnvelopeMode(mode,amp) or amp end
 if a>1e-8 then R.InsertEnvelopePoint(env,0,env_value(1),0,0,false,true) end
 for i=0,count do
  local t=a+(b-a)*i/count;local elapsed=(t-a)/playrate;local remaining=(b-t)/playrate;local q=i/count
  local shape=Core.mod_shape(m.shape,q)*Core.mod_edge(m.rate,elapsed,remaining,release);local wave=.5-.5*math.cos(elapsed*(m.rate or 1)*math.pi*2)
  local atten=-(m.depth or 0)*shape*wave;R.InsertEnvelopePoint(env,t,env_value(10^(atten/20)),0,0,false,true)
 end
 if release then R.InsertEnvelopePoint(env,duration,env_value(1),0,0,false,true) end
 R.Envelope_SortPoints(env)
end
function Core.pitch_curve(project,item,take,row)
 if row.curve and row.curve_length_mode==2 then Core.apply_linked_pitch_curve(take,row) end
 Core.apply_pitch_envelope(project,item,take,row)
end

function Core.apply_voice_fade(item,row)
 local new_len=max(1e-6,tonumber(row.render_len or row.len) or 1e-6)
 local fade_out=clamp(tonumber(row.voice_fade) or 0,0,new_len)
 local fade_start=max(0,new_len-fade_out)
 local manual_in=max(0,R.GetMediaItemInfo_Value(item,'D_FADEINLEN') or 0)
 local auto_in=max(0,R.GetMediaItemInfo_Value(item,'D_FADEINLEN_AUTO') or 0)
 local fade_in=min(max(manual_in,auto_in),fade_start)
 if not R.SetMediaItemInfo_Value(item,'D_LENGTH',new_len) then return false end
 R.SetMediaItemInfo_Value(item,'D_FADEINLEN_AUTO',0)
 R.SetMediaItemInfo_Value(item,'D_FADEOUTLEN_AUTO',0)
 R.SetMediaItemInfo_Value(item,'D_FADEINLEN',fade_in)
 R.SetMediaItemInfo_Value(item,'D_FADEOUTLEN',fade_out)
 return true
end
local ORIGINAL_ITEM_FIELDS={
 {'len','D_LENGTH'},{'fade_in','D_FADEINLEN'},{'fade_in_auto','D_FADEINLEN_AUTO'},
 {'fade','D_FADEOUTLEN'},{'fade_auto','D_FADEOUTLEN_AUTO'},
 {'free_y','F_FREEMODE_Y'},{'free_h','F_FREEMODE_H'}}
function Core.capture_original_item(item)
 local state={item=item}
 for _,field in ipairs(ORIGINAL_ITEM_FIELDS) do state[field[1]]=R.GetMediaItemInfo_Value(item,field[2]) end
 return state
end
function Core.restore_original_item(project,b,guard_after)
 if not b or not b.item or not R.ValidatePtr2(project,b.item,'MediaItem*') then return false,false end
 local restored,conflict=true,false
 for _,field in ipairs(ORIGINAL_ITEM_FIELDS) do
  local name,key=field[1],field[2];local current=R.GetMediaItemInfo_Value(b.item,key)
  local expected=b.after and b.after[name]
  if guard_after and finite(expected) and abs(current-expected)>1e-9 then conflict=true
  else
   local called,result=pcall(R.SetMediaItemInfo_Value,b.item,key,b[name] or 0)
   if not called or not result then restored=false end
  end
 end
 return restored,conflict
end
function Core.generation_targets_valid(snapshot)
 if R.EnumProjects(-1,'')~=snapshot.project then return false end
 for _,v in ipairs(snapshot.items) do
  if not R.ValidatePtr2(snapshot.project,v.item,'MediaItem*')
   or not R.ValidatePtr2(snapshot.project,v.track,'MediaTrack*')
   or R.GetMediaItemTrack(v.item)~=v.track
   or (v.take and R.GetActiveTake(v.item)~=v.take)
   or abs((R.GetMediaItemInfo_Value(v.item,'D_POSITION') or 0)-(v.pos or 0))>1e-9 then return false end
 end
 return true
end
function Core.apply(snapshot,groups,s,checkpoint,restore_selection)
 local project=snapshot.project
 if not Core.generation_targets_valid(snapshot) then return nil,'生成対象が変更されたため中止しました。' end
 local originalSelection=restore_selection
 if not originalSelection then
  originalSelection={};for i=0,R.CountSelectedMediaItems(project)-1 do originalSelection[#originalSelection+1]=R.GetSelectedMediaItem(project,i) end
 end
 local created={};local free_tracks,free_before={},{};local original_before={};local cleanup_failed={}
 for _,g in ipairs(groups) do for _,row in ipairs(g.rows) do if row.free_mode and row.info and row.info.track then free_tracks[row.info.track]=true end end end
 for _,row in ipairs(groups._voice_originals or {}) do if row.free_mode and row.info and row.info.track then free_tracks[row.info.track]=true end end
 for track in pairs(free_tracks) do local mode=R.GetMediaTrackInfo_Value(track,'I_FREEMODE');if mode~=1 then free_before[track]=mode end end
 R.Undo_BeginBlock2(project);R.PreventUIRefresh(1);local fx_ui_setting=Core.suppress_new_fx_windows()
 local total,done=0,0;for _,g in ipairs(groups) do total=total+#g.rows end
 local pause_at=0
 local function pause(partial)
  if not checkpoint or (done<total and R.time_precise()<pause_at) then return end
  R.PreventUIRefresh(-1)
  local called,continue,reason=pcall(checkpoint,min(1,(done+(partial or 0))/max(1,total)))
  R.PreventUIRefresh(1)
  if not called then error(continue,0) end
  if not continue then error(reason or '生成を中止しました。',0) end
  pause_at=R.time_precise()+.1
 end
 local ok,err=xpcall(function()
  pause()
  for track in pairs(free_tracks) do
   if not R.SetMediaTrackInfo_Value(track,'I_FREEMODE',1) then error('自由配置モードを有効化できません。',0) end
  end
  for _,row in ipairs(groups._voice_originals or {}) do
   local item=row.item_ref
   if item and R.ValidatePtr2(project,item,'MediaItem*') and (row.free_mode or row.voice_stolen) then
    local original_state=Core.capture_original_item(item);original_before[#original_before+1]=original_state
    if row.free_mode then
     local lanes=max(1,row.free_lane_count or 1);local lane=clamp(row.free_lane or 1,1,lanes)
     R.SetMediaItemInfo_Value(item,'F_FREEMODE_Y',(lane-1)/lanes);R.SetMediaItemInfo_Value(item,'F_FREEMODE_H',1/lanes)
    end
    if row.voice_stolen and not Core.apply_voice_fade(item,row) then error('元アイテムの停止フェードを設定できません。',0) end
    original_state.after=Core.capture_original_item(item)
   end
  end
  for _,g in ipairs(groups) do for _,row in ipairs(g.rows) do
   local v=row.info;local item=R.AddMediaItemToTrack(v.track);if not item then error('複製アイテムを作成できません。',0) end
   local created_entry={item=item,track=v.track,bake_files={}};created[#created+1]=created_entry
   if not R.SetItemStateChunk(item,Core.clone_chunk(v.chunk,R.genGuid),false) then error('アイテムを複製できません。',0) end
   local take=R.GetTake(item,v.takeindex);if not take then error('複製Takeを取得できません。',0) end;R.SetActiveTake(take)
   pause(.1)
   local output_len=row.render_len or row.len
   if not R.SetMediaItemInfo_Value(item,'D_POSITION',row.pos) or not R.SetMediaItemInfo_Value(item,'D_LENGTH',output_len) then error('位置または長さを設定できません。',0) end
   R.SetMediaItemInfo_Value(item,'I_GROUPID',0);R.SetMediaItemInfo_Value(item,'C_LOCK',0)
   if row.free_mode then
    local lanes=max(1,row.free_lane_count or 1);local lane=clamp(row.free_lane or 1,1,lanes)
    R.SetMediaItemInfo_Value(item,'F_FREEMODE_Y',(lane-1)/lanes);R.SetMediaItemInfo_Value(item,'F_FREEMODE_H',1/lanes)
    R.SetMediaItemInfo_Value(item,'D_FADEINLEN_AUTO',0);R.SetMediaItemInfo_Value(item,'D_FADEOUTLEN_AUTO',0)
   end
   if row.voice_stolen and not Core.apply_voice_fade(item,row) then error('生成アイテムの停止フェードを設定できません。',0) end
   local function set_take(key,value) if not R.SetMediaItemTakeInfo_Value(take,key,value) then error('Take設定に失敗しました：'..key,0) end end
   if row.substituted then
    R.SetMediaItemInfo_Value(item,'B_LOOPSRC',0)
    if row.source_track_item and row.source_track_guid then
     local candidate_item=row.source_track_ref;if not candidate_item or not R.ValidatePtr2(project,candidate_item,'MediaItem*') then candidate_item=Core.find_item_by_guid(project,row.source_track_guid) end
     if not candidate_item or not R.ValidatePtr2(project,candidate_item,'MediaItem*') then error('同一トラック候補の元アイテムが見つかりません。',0) end
     local candidate_take=R.GetActiveTake(candidate_item)
     if not candidate_take or R.TakeIsMIDI(candidate_take) then error('同一トラック候補の音声Takeを取得できません。',0) end
     local candidate_source=R.GetMediaItemTake_Source(candidate_take)
     if not candidate_source then error('同一トラック候補の音声ソースを取得できません。',0) end
     local old_source=R.GetMediaItemTake_Source(take)
     if not R.SetMediaItemTake_Source(take,candidate_source) then error('同一トラック候補へ音声ソースを切り替えられません。',0) end
     if old_source and old_source~=candidate_source then pcall(R.PCM_Source_Destroy,old_source) end
     local rebound=R.GetMediaItemTake_Source(take)
     if not rebound then error('同一トラック候補の音声ソースを確認できません。',0) end
     local rebound_file=R.GetMediaSourceFileName(rebound,'')
     local candidate_file=R.GetMediaSourceFileName(candidate_source,'')
     if type(candidate_file)=='string' and candidate_file~='' and type(rebound_file)=='string' and rebound_file~='' then
      local a,b=candidate_file:gsub('\\','/'):lower(),rebound_file:gsub('\\','/'):lower()
      if a~=b then error('同一トラック候補の音声ソース切替を確認できません。',0) end
     end
     local live_mode=R.GetMediaItemTakeInfo_Value(candidate_take,'I_CHANMODE')
     if finite(live_mode) then set_take('I_CHANMODE',live_mode)
     elseif finite(row.source_channel_mode) then set_take('I_CHANMODE',row.source_channel_mode) end
    elseif row.source_file and row.source_file~='' and row.source_file~=v.file then
     local new_source=R.PCM_Source_CreateFromFile(row.source_file);if not new_source then error('素材バリエーションの音声ソースを作成できません。',0) end
     local old_source=R.GetMediaItemTake_Source(take)
     if not R.SetMediaItemTake_Source(take,new_source) then pcall(R.PCM_Source_Destroy,new_source);error('素材バリエーションへ音声ソースを切り替えられません。',0) end
     if old_source and old_source~=new_source then pcall(R.PCM_Source_Destroy,old_source) end
    end
    set_take('D_STARTOFFS',row.offset)
   end
   set_take('D_PLAYRATE',row.playrate);set_take('B_PPITCH',row.ppitch);set_take('D_PITCH',row.pitch)
   if row.curve or row.vibrato then Core.pitch_curve(project,item,take,row) end
   pause(.4)
   if row.volume then
    if v.is_midi then if not R.SetMediaItemInfo_Value(item,'D_VOL',row.volume) then error('MIDI音量を設定できません。',0) end else set_take('D_VOL',row.volume) end
   end
   if row.tremolo then Core.apply_tremolo(project,item,take,row) end
   if row.eq and #row.eq>0 then
    created_entry.texture_fx_count=Core.add_texture_eq(take,row.eq,function(fraction)pause(.5+.35*fraction)end)
   end
   if row.tone then Core.add_tone_eq(take,row.tone) end
   pause(.9)
   if row.pan then set_take('D_PAN',row.pan) end
   local generated_name=(row.source_track_item and row.source_name and row.source_name~='') and row.source_name or v.name
   R.GetSetMediaItemTakeInfo_String(take,'P_NAME',string.format('%s · VAR %02d',generated_name,g.index),true)
   R.GetSetMediaItemInfo_String(item,Core.GENERATED_TAG,string.format('seed=%d;variation=%d;source=%s;offset=%.9f',s.seed,g.index,v.guid,row.offset),true)
   done=done+1;pause()
  end end
 end,debug.traceback)
 Core.restore_new_fx_windows(fx_ui_setting);local restored=true
 if not ok then
  local cleanup_files={}
  for i=#created,1,-1 do local v=created[i];if R.ValidatePtr2(project,v.item,'MediaItem*') then
   local called,result=pcall(R.DeleteTrackMediaItem,v.track,v.item)
   if not called or not result then restored=false else for _,fn in ipairs(v.bake_files or {}) do cleanup_files[#cleanup_files+1]=fn end end
  else for _,fn in ipairs(v.bake_files or {}) do cleanup_files[#cleanup_files+1]=fn end end end
  cleanup_failed=Core.cleanup_bake_files(cleanup_files,project)
  for i=#original_before,1,-1 do local restored_item=Core.restore_original_item(project,original_before[i],false);if not restored_item then restored=false end end
  for track,mode in pairs(free_before) do local called,result=pcall(R.SetMediaTrackInfo_Value,track,'I_FREEMODE',mode);if not called or not result then restored=false end end
 end
 R.SelectAllMediaItems(project,false);for _,it in ipairs(originalSelection) do if R.ValidatePtr2(project,it,'MediaItem*') then R.SetMediaItemSelected(it,true) end end
 R.PreventUIRefresh(-1);if next(free_tracks) then R.UpdateTimeline() end;R.UpdateArrange();R.Undo_EndBlock2(project,ok and ('BLT Variant Forge: '..#groups..' variations') or 'BLT Variant Forge: failed (copies removed)',next(free_tracks) and (1|4) or 4)
 if not ok then R.ShowConsoleMsg('BLT Variant Forge:\n'..BLT.publicError(err)..'\n');return nil,restored and ('作成を中止し、今回のコピーを削除しました。\n'..BLT.publicError(err)) or '処理を中止しました。コピーの削除に失敗したためUndoで戻してください。',nil,nil,cleanup_failed,restored end
 return #created,created,free_before,original_before
end
function Core.load_settings(section)
 local s=copy(Core.defaults)
 for k,v in pairs(s) do
  local saved=R.GetExtState(section,k)
  if saved~='' then
   if type(v)=='boolean' then s[k]=saved=='1'
   elseif type(v)=='number' then local n=tonumber(saved);if finite(n) then s[k]=n end
   else s[k]=saved end
  end
 end
 for key in pairs(Core.ranges) do s[key]=Core.quantize_setting(key,s[key]) end
 if not Core.validate(s) then s=copy(Core.defaults) end
 local locks={}
 for _,f in ipairs(Core.FEATURES) do locks[f]=f~='source' and R.GetExtState(section,'lock_'..f)=='1' end
 return s,locks
end
function Core.save_settings(section,s,locks)
 for k,v in pairs(s) do BLT.store(section,k,type(v)=='boolean' and (v and '1' or '0') or tostring(v),true) end
 for _,f in ipairs(Core.FEATURES) do BLT.store(section,'lock_'..f,(f~='source' and locks[f]) and '1' or '0',true) end
end
if ...=='test' then return Core end

Core.RUN_ID=R.genGuid():gsub('[^%w]','');Core.touch_temp_heartbeat(true)

local S,lock_apply=Core.load_settings(Core.SECTION)
local SOURCE_CACHE_LIMIT=24
local ITEM_STATE_LIMIT=512
local TRACK_ANCHOR_LIMIT=512
local A={project=R.EnumProjects(-1,''),items={},poll=0,status='',warning=false,job=nil,progress=0,closed=false,closing=false,last_created=nil,item_scroll=0,matrix_selected={},matrix_anchor=nil,wave_guid=nil,wave_region_key=nil,wave_region_index=nil,wave_region_selection={},source_wave_drag=nil,source_wave_geom=nil,source_wave_view={key=nil,zoom=1,start=0},source_wave_scroll_drag=nil,target_lock=nil,target_lock_poll=0,texture_bank={},texture_preview_index=1,scroll_drag=nil,field_drag=nil,source_cache={},track_anchor_cache={},source_queue={},source_queue_i=1,source_queue_done=false,source_job=nil,source_progress=0,source_execute_pending=nil,source_auto={},selection_signature='',track_candidate_pools={},item_by_guid={},persist_dirty=false,persist_at=0,pending_bake_delete=Core.load_pending_bake_deletes(),pending_bake_delete_at=0,pending_bake_retry_delay=2,stale_temp_projects=Core.STALE_TEMP_PROJECTS,stale_temp_retry_at=0,bake_scan_record=nil,bake_scan_revision=nil,bake_scan_count=0,apply={lock=lock_apply,items={}}}
A.source_cache_serial=0;A.item_state_serial=0;A.item_state_used={}
local W,H=900,884
local C={
  bg={0.018,0.030,0.055}, bg2={0.030,0.090,0.180},
  panel={0.040,0.068,0.110}, panel2={0.055,0.125,0.205},
  field={0.018,0.040,0.080}, edge={0.145,0.285,0.445}, edge2={0.360,0.650,0.900},
  text={0.955,0.980,1.000}, muted={0.690,0.780,0.875}, faint={0.390,0.505,0.635},
  accent={0.120,0.490,0.980}, accent2={0.650,0.895,1.000}, accent3={0.045,0.235,0.520},
  focus={0.225,0.610,1.000}, focus2={0.690,0.900,1.000}, ink={0.018,0.075,0.160},
  hover={0.430,0.790,1.000}, warn={1.000,0.755,0.490}, correct={1.000,0.180,0.260}, correct2={1.000,0.650,0.700}, lock={1.000,0.790,0.260}, lock2={1.000,0.920,0.600}, quiet={0.300,0.360,0.440}, source_alt={0.300,0.930,0.700}, source_alt2={0.730,1.000,0.880}
}
C.ice,C.disabled,C.red=C.accent2,C.faint,C.correct
local fonts={"Yu Gothic UI","Segoe UI","Consolas"}
if BLT_MAC then fonts={"Hiragino Sans","Helvetica Neue","Menlo"} end
if R.GetOS():match("Linux") then fonts={"sans-serif","sans-serif","monospace"} end

local scale,ox,oy=1,0,0
 BLT.viewport(scale,gfx.ext_retina or 1);local frame_clock,frame_dt=R.time_precise(),1/60
local animations_active=true
local effects_active=true
local motion={}
local density=VariantControls.compactScale
local VariantUI,VariantGraphics,VariantIcon
local widgets={}
local widget_count=0
local edit=nil
local field_flash={}
local voice_flash={}
local down_last,right_down_last,pressed=false,false,nil
local pressed_mods=0
local mouse_x,mouse_y=-1,-1
local hover_hint=""

local Chrome
local UI={}
local next_draw_time=0
local redraw_dirty=true
local last_raw_mouse_x,last_raw_mouse_y,last_raw_mouse_cap=nil,nil,nil
local last_window_w,last_window_h=nil,nil
local last_input_active=nil
local last_hover_key=nil
local hover_anim_until=R.time_precise()+.35
local EFFECT_IDLE_TAIL=2.5
local effect_activity_until=R.time_precise()+.20
local frame_cache_valid=false
local next_scroll_hint_time=0
local SCROLL_HINT_INTERVAL=1/15
local SCROLL_HINT_SPEED=.68
local SCROLL_HINT_COAST=1.65
local scroll_anim_phase=0
local scroll_anim_speed=SCROLL_HINT_SPEED
local scroll_anim_last=R.time_precise()
local scroll_anim_coast_start=nil
local scroll_anim_coast_speed=SCROLL_HINT_SPEED
local scroll_motion_alive=true
local visual_tail_active=true

local function update_scroll_hint_motion(now,active)
 now=now or R.time_precise()
 local dt=clamp(now-scroll_anim_last,0,.10);scroll_anim_last=now
 if active then
  scroll_anim_coast_start=nil
  if scroll_anim_speed<=0 then scroll_anim_speed=SCROLL_HINT_SPEED*.16 end
  local a=1-math.exp(-10*dt)
  scroll_anim_speed=scroll_anim_speed+(SCROLL_HINT_SPEED-scroll_anim_speed)*a
 else
  if not scroll_anim_coast_start then
   scroll_anim_coast_start=now;scroll_anim_coast_speed=scroll_anim_speed
  end
  local t=clamp((now-scroll_anim_coast_start)/SCROLL_HINT_COAST,0,1)
  scroll_anim_speed=scroll_anim_coast_speed*(1-t)*(1-t)
  if t>=1 then scroll_anim_speed=0 end
 end
 scroll_anim_phase=(scroll_anim_phase+scroll_anim_speed*dt)%1
 scroll_motion_alive=active or scroll_anim_speed>1e-5
 return scroll_motion_alive
end

local function request_redraw(now,animate_for)
 now=now or R.time_precise();redraw_dirty=true
 if animate_for and animate_for>0 then
  hover_anim_until=max(hover_anim_until,now+animate_for)
 end
end
local function request_effect_activity(now,duration)
 now=now or R.time_precise();effect_activity_until=max(effect_activity_until,now+(duration or .18))
end
local function wake_visuals(now,animate_for,effect_for)
 request_redraw(now,animate_for)
 request_effect_activity(now,effect_for or EFFECT_IDLE_TAIL)
end

function UI.update_pointer_geometry()
 local contentH=max(1,gfx.h-Chrome.title_h)
 local new_scale=max(.25,min(gfx.w/W,contentH/H))
 if new_scale~=scale then scale=new_scale; end
 ox,oy=(gfx.w-W*scale)/2,Chrome.title_h+(contentH-H*scale)/2-22*scale
 BLT.viewport(scale,gfx.ext_retina or 1); mouse_x,mouse_y=(gfx.mouse_x-ox)/scale,(gfx.mouse_y-oy)/scale
 if not animations_active then mouse_x,mouse_y=-1000,-1000 end
end

local function sx(x) return ox+x*scale end
local function sy(y) return oy+y*scale end
local function color(c,a) gfx.set(c[1],c[2],c[3],a or 1) end
local function rect(x,y,w,h,c,a) color(c,a); gfx.rect(sx(x),sy(y),w*scale,h*scale,1) end
local function line(x,y,x2,y2,c,a) color(c,a); gfx.line(sx(x),sy(y),sx(x2),sy(y2),1) end
local function disc(x,y,r,c,a) color(c,a); gfx.circle(sx(x),sy(y),r*scale,1,1) end
local Chameleon
local function chameleon_notify(text)
  if UI.notice then UI.notice(text,false) else A.status=text;A.warning=false end
end

VariantGraphics=CanvasGraphics.new(gfx,function(face,size,flags)
 local kind=1;for i,name in ipairs(fonts)do if face==name then kind=i;break end end
 BLT.font(size,kind,flags==98,1,fonts)
end)
VariantUI=VariantControls.new(VariantGraphics,R.time_precise,C)
VariantUI.font,VariantUI.minFontSize=fonts[1],7
C.lock,C.lock2=VariantUI.tones.gold.accent,VariantUI.tones.gold.ice
local native_interaction=VariantUI.interaction
local options={}
local function row_control(id)
 return id~='voice_all'and (id:match('^voice')or id:match('^item_')or id:match('^source_count_')or id:match('^source_analyze_'))~=nil
end
function VariantUI:interaction(...)
 local _,hot,held,s=native_interaction(self,...)
 local x,_,w=select(2,...)
 s.variantSeen=self.frameSerial;s.variantHot=hot and 1 or 0
 if s.variantRow==nil then s.variantRow=row_control((...))end
 s.variantLight=hot and max(.12,min(.88,(self.mx-x)/w))or .18
 if self.released then self.focus=nil end
 return false,hot,held,s
end
local function variant_options(id)
 local opt=options[id];if not opt then opt={};options[id]=opt end;return opt
end
local function variant_finish()
 VariantUI:finish()
 for id,s in pairs(VariantUI.states)do
  if s.variantRow and s.variantSeen~=VariantUI.frameSerial then VariantUI.states[id]=nil;options[id]=nil end
 end
end
local function variant_animating(now)
 local animated=VariantUI:attentionAnimating()or VariantUI:executeAnimating('execute')
 local moving=false
 for _,s in pairs(VariantUI.states)do
  if s.variantSeen==VariantUI.frameSerial then
   if s.hover and s.hover~=s.variantHot or s.lightX and s.variantLight and abs(s.lightX-s.variantLight)>.0001
    or s.slide and s.slide>0 and s.slide<1 or s.active and s.goldValue~=nil and abs(s.active-(s.goldValue and 1 or 0))>.0001 then moving=true end
   if s.flash or s.flashPending or s.sparkAt then animated=true end
  elseif s.sparkAt then animated=true end
 end
 return animated or moving,moving
end
local function variant_begin()
 local now=R.time_precise()
 if VariantUI.now and now-VariantUI.now>.05 then VariantUI.now=now-1/60 end
 VariantUI:begin(density*scale,ox,oy)
 VariantUI.themeEnabled=Chameleon.enabled
 VariantUI.blocked=BLT.blocked()or edit~=nil or Chrome.mouseActive or not animations_active
 VariantUI.focused=animations_active
 VariantUI.active=animations_active and effects_active
end
VariantIcon=VariantHeaderIcon.new({faces=fonts,g=VariantGraphics},VariantUI,VariantIconDefinition)

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
 section=Core.SECTION,
 store=BLT.store,
 notify=chameleon_notify,
 chrome=function() return Chrome end,
 roles={ice='accent2',disabled='faint',red='red'},special=VariantUI.tones,
 applied=function(restored,palette)
  VariantUI.themeTones=not restored and palette.special or nil
  local gold=VariantUI.themeTones and VariantUI.themeTones.gold or VariantUI.tones.gold
  C.lock,C.lock2=gold.accent,gold.ice
 end,
 changed=function() VariantIcon.dirty=true;frame_cache_valid=false;wake_visuals() end
})

local text_queue={count=0,buckets={},order={},order_count=0}
local function font_spec(size,kind,bold) return BLT.spec(size,kind,bold,scale) end

local function font(size,kind,bold) BLT.font(size,kind,bold,scale,fonts) end
local function queue_text(t,x,y,right,bottom,flags,size,c,kind,bold,translated)
  local fk,_,_,key=font_spec(size,kind,bold)
  local b=text_queue.buckets[key]
  if not b then b={count=0};text_queue.buckets[key]=b end
  if b.count==0 then
    text_queue.order_count=text_queue.order_count+1
    text_queue.order[text_queue.order_count]=key
  end
  b.count=b.count+1
  local cmd=b[b.count]
  if not cmd then cmd={};b[b.count]=cmd end
  cmd.text=t;cmd.translated=translated;cmd.x=x;cmd.y=y;cmd.right=right;cmd.bottom=bottom
  cmd.flags=flags or 0;cmd.size=size;cmd.kind=fk;cmd.bold=bold and true or false;cmd.c=c or C.text
  text_queue.count=text_queue.count+1
end
local function label(text,x,y,size,c,kind,w,h,flags,bold,literal)
  local t=literal and tostring(text) or Language.message(text)
  queue_text(t,sx(x),sy(y),sx(x+(w or 700)),sy(y+(h or size+8)),flags or 0,size,c,kind,bold,t~=tostring(text))
end

local function measure(text,size,kind,bold) font(size,kind,bold);return BLT.metricsFor(Language.message(text))/scale end
local function right_label(text,right,y,size,c,kind,bold)
  local t=Language.message(text);local tw=measure(t,size,kind,bold)
  queue_text(t,sx(right-tw),sy(y),sx(right+2),sy(y+size+9),0,size,c,kind,bold)
end

local function reset_text_queue()
  for i=1,text_queue.order_count do
    local b=text_queue.buckets[text_queue.order[i]]
    for j=1,b.count do b[j].text=nil;b[j].c=nil end
    b.count=0
  end
  text_queue.count=0;text_queue.order_count=0
end
local function flush_text_queue()
  if text_queue.count==0 then return end
  for i=1,text_queue.order_count do
    local b=text_queue.buckets[text_queue.order[i]];local first=b[1]
    font(first.size,first.kind,first.bold)
    for j=1,b.count do
      local cmd=b[j]
      color(cmd.c);gfx.x,gfx.y=cmd.x,cmd.y
      gfx.drawstr(cmd.translated and BLT.ui.fit(cmd.text,cmd.right-cmd.x) or cmd.text,cmd.flags,cmd.right,cmd.bottom)
    end
  end
  reset_text_queue()
end
local function gradient(x,y,w,h,a,b,alpha1,alpha2,vertical)
  local aa1=alpha1 or 1;local aa2=alpha2 or aa1
  local n=max(1,(vertical and h or w)*scale)
  if (a==b or (a[1]==b[1] and a[2]==b[2] and a[3]==b[3])) and aa1==aa2 then rect(x,y,w,h,a,aa1);return end
  if n<=1.01 then rect(x,y,w,h,a,aa1);return end
  local dr,dg,db=(b[1]-a[1])/n,(b[2]-a[2])/n,(b[3]-a[3])/n
  local da=(aa2-aa1)/n
  gfx.gradrect(sx(x),sy(y),w*scale,h*scale,a[1],a[2],a[3],aa1,
    vertical and 0 or dr,vertical and 0 or dg,vertical and 0 or db,vertical and 0 or da,
    vertical and dr or 0,vertical and dg or 0,vertical and db or 0,vertical and da or 0)
end
local function glow_line(x,y,x2,y2,c,strength)
  strength=strength or 1
  line(x,y-3,x2,y2-3,c,0.025*strength); line(x,y+3,x2,y2+3,c,0.025*strength)
  line(x,y-2,x2,y2-2,c,0.055*strength); line(x,y+2,x2,y2+2,c,0.055*strength)
  line(x,y-1,x2,y2-1,c,0.13*strength); line(x,y+1,x2,y2+1,c,0.13*strength)
  line(x,y,x2,y2,c,0.95*strength)
end
local function finish_corners(x,y,w,h,cut,top_left,edge,a)
  color(C.bg)
  gfx.triangle(sx(x+w-cut-1),sy(y+h+1),sx(x+w+1),sy(y+h-cut-1),sx(x+w+1),sy(y+h+1))
  if top_left then gfx.triangle(sx(x-1),sy(y-1),sx(x+cut+1),sy(y-1),sx(x-1),sy(y+cut+1)) end
  line(x+w,y+h-cut,x+w-cut,y+h,edge,a)
  if top_left then line(x,y+cut,x+cut,y,edge,a) end
end
local function animate(key,target)
 if BLT.presetRevision and BLT.presetMotionSeen[key]~=BLT.presetRevision then
  BLT.presetMotionSeen[key]=BLT.presetRevision;motion[key]=target;return target
 end
  local p=motion[key]; if p==nil then p=target end
  local v=p+(target-p)*BLT.blend(frame_dt); motion[key]=v; return v
end
local function inside(x,y,w,h) return mouse_x>=x and mouse_x<=x+w and mouse_y>=y and mouse_y<=y+h end
local function register(id,x,y,w,h,fn,hint,enabled)
  widget_count=widget_count+1;local item=widgets[widget_count]
  if not item then item={};widgets[widget_count]=item end
  item.id,item.x,item.y,item.w,item.h,item.fn,item.hint,item.enabled=id,x,y,w,h,fn,hint,enabled~=false
  if inside(x,y,w,h) and hint then hover_hint=hint end
end
local function fmt(n)
  if abs(n-floor(n+0.5))<1e-8 then return tostring(floor(n+0.5)) end
  return string.format("%.2f",n):gsub("0+$",""):gsub("%.$","")
end

Chrome={
 title_h=26,title='BLT Variant Forge',title_text='V A R I A N T   F O R G E',min_w=780,
 window=nil,mouseDown=false,drag=nil,resize=nil,mouseActive=false,requestClose=false,requestReset=false,chameleonPressed=false,
  mint={0.38,0.88,0.72},ice={0.65,0.895,1.0},red={1.0,0.27,0.34},
 is_windows=R.GetOS():match("Win")~=nil,resize_edge=6,resize_corner_band=8,resize_corner_span=24,resize_top_left_guard=30,resize_top_right_guard=110,tooltipHover=nil,tooltipSince=0,tooltipVisible=false,tooltipDelay=.70,
 }
Chrome.min_h=800
Chrome.font=Chrome.is_windows and "Segoe UI" or (BLT_MAC and "Helvetica Neue" or "sans-serif")

function UI.titlebar_api_ready()
 for _,name in ipairs({'JS_Window_Find','JS_Window_IsWindow','JS_Mouse_GetState','JS_VKeys_GetDown'})do
  if type(R[name])~='function'then return false,'js_ReaScriptAPI が必要です。 / js_ReaScriptAPI is required.'end
 end
 return true
end
function UI.gfx_window_handle()return gfx.windowHandle()end
function UI.reset_window_size()
  local hwnd=UI.gfx_window_handle()
  if not hwnd then return end
  local ok,l,t=WindowGeometry.JS_Window_GetRect(hwnd)
  if ok then BLT.position(hwnd,l,t,W,H+Chrome.title_h,"","") end
  BLT.store(Core.SECTION,"window_w",tostring(W),true)
  BLT.store(Core.SECTION,"window_h",tostring(H+Chrome.title_h),true)
end

function UI.chrome_resize_hit(mx,my)
  local w,h=gfx.w,gfx.h
  if not w or not h or w<=0 or h<=0 then return nil end
  if mx<0 or mx>=w or my<0 or my>=h then return nil end

  local edge=Chrome.resize_edge
  local band=Chrome.resize_corner_band
  local span=Chrome.resize_corner_span

  local bottomBand=my>=h-band
  local bottomSpan=my>=h-span
  local leftBand=mx<band
  local rightBand=mx>=w-band
  local leftSpan=mx<span
  local rightSpan=mx>=w-span
  if (bottomBand and leftSpan) or (leftBand and bottomSpan) then return "lb" end
  if (bottomBand and rightSpan) or (rightBand and bottomSpan) then return "rb" end

  if my<Chrome.title_h then
    if mx<Chrome.resize_top_left_guard or mx>=w-Chrome.resize_top_right_guard then return nil end
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

function UI.resize_cursor_kind(mode)
  if mode=="l" or mode=="r" then return "we" end
  if mode=="t" or mode=="b" then return "ns" end
  if mode=="lt" or mode=="rb" then return "nwse" end
  if mode=="rt" or mode=="lb" then return "nesw" end
  return nil
end
function UI.set_resize_cursor(mode)gfx.setCursor(UI.resize_cursor_kind(mode))end
function UI.titlebar_cleanup()UI.set_resize_cursor(nil)end
function UI.begin_window_resize(mode)
  local hwnd=UI.gfx_window_handle()
  if not hwnd or not mode then return false end
  local ok,l,t,r,b=WindowGeometry.JS_Window_GetRect(hwnd)
  if not ok then return false end
  local sx,sy=WindowGeometry.GetMousePosition()
  Chrome.resize={mode=mode,mouseX=sx,mouseY=sy,left=l,top=t,right=r,bottom=b}
  Chrome.drag=nil
  return true
end

function UI.update_window_resize()
  local d=Chrome.resize
  if not d then return end
  local hwnd=UI.gfx_window_handle()
  if not hwnd then Chrome.resize=nil; return end
  local sx,sy=WindowGeometry.GetMousePosition()
  local dx,dy=sx-d.mouseX,sy-d.mouseY
  local l,t,r,b=d.left,d.top,d.right,d.bottom
  if d.mode:find("l",1,true) then l=math.min(d.left+dx,r-Chrome.min_w) end
  if d.mode:find("r",1,true) then r=math.max(d.right+dx,l+Chrome.min_w) end
  if d.mode:find("t",1,true) then t=math.min(d.top+dy,b-Chrome.min_h) end
  if d.mode:find("b",1,true) then b=math.max(d.bottom+dy,t+Chrome.min_h) end
  BLT.position(hwnd,math.floor(l+.5),math.floor(t+.5),math.max(Chrome.min_w,math.floor(r-l+.5)),math.max(Chrome.min_h,math.floor(b-t+.5)),"","")
end

function UI.clear_chrome_tooltip() BLT.clearTooltip() end

function UI.custom_titlebar() BLT.bar() end

local FEATURE_COLUMNS={
 {key='pitch_global',label='G.PITCH',sub='全体ピッチ',lockable=true},
 {key='pitch_curve',label='P.CURVE',sub='ピッチ曲線',lockable=true},
 {key='vibrato',label='VIB',sub='ビブラート',lockable=true},
 {key='tremolo',label='TREM',sub='トレモロ',lockable=true},
 {key='timing',label='TIME',sub='タイミング',lockable=true},
 {key='volume',label='VOL',sub='音量',lockable=true},
 {key='pan',label='PAN',sub='定位',lockable=true},
 {key='eq_texture',label='TEXTURE',sub='質感EQ',lockable=true},
 {key='eq_tone',label='TONE',sub='トーンEQ',lockable=true},
 {key='source',label='SOURCE',sub='素材',lockable=false}
}
local VOICE_MAX=128
local ITEM_DEFAULT={voice_limit=0,source_mode=1,pitch_global=false,pitch_curve=false,vibrato=false,tremolo=false,timing=false,volume=false,pan=false,eq_texture=false,eq_tone=false,source=false}
local WAVE_X,WAVE_Y,WAVE_W,WAVE_H=12,422,876,168
local MATRIX_X,MATRIX_Y,MATRIX_W,MATRIX_H=12,598,876,232
local MATRIX_NAME_W=252
local MATRIX_HEADER_H,MATRIX_ALL_H,MATRIX_LOCK_H,MATRIX_ROW_H=28,28,30,28
local MATRIX_VISIBLE=5
local MATRIX_SCROLL_W=13
local click_mods=0

function UI.persist_now()
 Core.save_settings(Core.SECTION,S,A.apply.lock);A.persist_dirty=false
end
function UI.persist_later()
 A.persist_dirty=true;A.persist_at=R.time_precise()+.45
end
function UI.flush_persist(force)
 if A.persist_dirty and (force or R.time_precise()>=(A.persist_at or 0)) then UI.persist_now() end
end
function UI.notice(text,warn) A.status=warn and BLT.publicError(text) or tostring(text or '');A.warning=warn or false end
local function prune_used_cache(cache,limit,protected)
 local count,removed=0,0;for _ in pairs(cache or {}) do count=count+1 end
 while count>limit do
  local victim,oldest=nil,math.huge
  for key,value in pairs(cache) do
   if not (protected and protected[key]) then
    local used=type(value)=='table' and (value._used or 0) or 0
    if used<oldest then victim,oldest=key,used end
   end
  end
  if not victim then break end
  cache[victim]=nil;count=count-1;removed=removed+1
 end
 return removed
end
function UI.source_cache_get(key)
 local value=key and A.source_cache[key] or nil
 if value then A.source_cache_serial=A.source_cache_serial+1;value._used=A.source_cache_serial end
 return value
end
function UI.prune_source_cache()
 local protected={}
 for _,v in ipairs(A.items or {}) do if v.source_key then protected[v.source_key]=true end end
 local removed=prune_used_cache(A.source_cache,SOURCE_CACHE_LIMIT,protected)
 if removed>0 then collectgarbage('step',300) end
end
function UI.source_cache_set(key,value)
 if not key then return end
 A.source_cache_serial=A.source_cache_serial+1;value=value or {regions={}};value._used=A.source_cache_serial
 A.source_cache[key]=value;UI.prune_source_cache()
end
function UI.ensure_apply_rows(list)
 A.feature_summary=nil
 local present={};A.item_by_guid={}
 for _,v in ipairs(list or {}) do
  present[v.guid]=true;A.item_by_guid[v.guid]=v;A.item_state_serial=A.item_state_serial+1;A.item_state_used[v.guid]=A.item_state_serial
  if not A.apply.items[v.guid] then A.apply.items[v.guid]=tcopy(ITEM_DEFAULT);A.source_auto[v.guid]=false elseif A.source_auto[v.guid]==nil then A.source_auto[v.guid]=false end
  if v.is_midi then
   local row=A.apply.items[v.guid];row.voice_limit=0;A.source_auto[v.guid]=false
   for _,key in ipairs(Core.FEATURES) do if not Core.MIDI_FEATURES[key] then row[key]=false end end
  end
 end
 local state_count=0;for _ in pairs(A.apply.items) do state_count=state_count+1 end
 while state_count>ITEM_STATE_LIMIT do
  local victim,oldest=nil,math.huge
  for guid in pairs(A.apply.items) do
   if not present[guid] and (A.item_state_used[guid] or 0)<oldest then victim,oldest=guid,A.item_state_used[guid] or 0 end
  end
  if not victim then break end
  A.apply.items[victim]=nil;A.source_auto[victim]=nil;A.item_state_used[victim]=nil;voice_flash[victim]=nil
  for key in pairs(motion) do if tostring(key):find(victim,1,true) then motion[key]=nil end end
  state_count=state_count-1
 end
 for guid in pairs(A.matrix_selected or {}) do if not present[guid] then A.matrix_selected[guid]=nil end end
 if A.matrix_anchor and (not list or not list[A.matrix_anchor] or not present[list[A.matrix_anchor].guid]) then A.matrix_anchor=nil end
 if not A.wave_guid or not present[A.wave_guid] then A.wave_guid=list and list[1] and list[1].guid or nil end
 A.item_scroll=clamp(A.item_scroll or 0,0,max(0,#(list or {})-MATRIX_VISIBLE))
 A.apply.lock.source=false
end
function UI.source_available(v) return v and v.source_ready and v.source_available==true end
function A.matrix_display_name(name)
 name=tostring(name or 'Audio')
 local lower=name:lower()
 for _,ext in ipairs({'.wav','.wave','.aif','.aiff','.flac','.mp3','.ogg','.opus','.m4a','.w64','.caf'}) do
  if lower:sub(-#ext)==ext then return name:sub(1,#name-#ext) end
 end
 return name
end
function UI.sync_source_checkbox(v)
 A.feature_summary=nil
 local row=v and A.apply.items[v.guid];if not row then return end
 if v.source_ready and not UI.source_available(v) then row.source=false end
end
function UI.prepare_source_info(v)
 local eligible,reason=Core.source_eligible(v);v._source_checked=true;v._source_eligible=eligible;v._source_eligibility_reason=reason
 v.source_key=eligible and Core.source_cache_key(v) or nil
 return eligible,reason
end
function UI.track_candidates_for(v)
 if not v or not v.track then return {} end
 local key=tostring(v.track);local pool=A.track_candidate_pools[key]
 if not pool then pool=Core.collect_track_pool(A.project,v.track);A.track_candidate_pools[key]=pool end
 local out={};local boundary=(v.pos or 0)+1e-9
 for _,cand in ipairs(pool) do
  local finish=(cand.pos or 0)+max(0,cand.len or 0)
  if cand.item~=v.item and finish<=boundary then out[#out+1]=cand end
 end
 return out
end
function UI.source_status_from_cache(v)
 v.source_same_count=0;v.source_track_count=0
 local eligible,reason
 if v._source_checked then eligible,reason=v._source_eligible,v._source_eligibility_reason else eligible,reason=UI.prepare_source_info(v) end
 v.source_origin=nil
 if not eligible then v.source_ready=true;v.source_available=false;v.source_reason=reason;v.source_detected=0;v.source_candidate_count=0;v.variants=nil;v.source_context=nil;v.texture_preview=nil;UI.sync_source_checkbox(v);return end
 local cached=UI.source_cache_get(v.source_key)
 if not cached then v.source_ready=false;v.source_available=false;v.source_reason='解析待ち';v.source_detected=nil;v.source_candidate_count=nil;v.variants=nil;v.source_context=nil;v.texture_preview=nil;UI.sync_source_checkbox(v);return end
 if cached.error then v.source_ready=true;v.source_available=false;v.source_reason=cached.error;v.source_detected=0;v.source_candidate_count=0;v.variants=nil;v.source_context=nil;v.texture_preview=nil;UI.sync_source_checkbox(v);return end
 local regions=cached.regions or {}
 v.texture_preview=cached.preview;v.texture_preview_max=cached.preview_max;v.texture_source_len=cached.source_len
 v.track_candidates=UI.track_candidates_for(v)
 local row=A.apply.items[v.guid] or ITEM_DEFAULT;local mode=row.source_mode==2 and 2 or 1
 local variants,why,ctx,same_count,track_count=Core.source_variants(v,cached,S.source_timing_mode,v.track_candidates,A.track_anchor_cache,mode)
 if mode==1 and same_count<=1 and track_count>1 then
  mode=2;row.source_mode=2;variants,why,ctx,same_count,track_count=Core.source_variants(v,cached,S.source_timing_mode,v.track_candidates,A.track_anchor_cache,mode)
 elseif mode==2 and track_count<=1 and same_count>1 then
  mode=1;row.source_mode=1;variants,why,ctx,same_count,track_count=Core.source_variants(v,cached,S.source_timing_mode,v.track_candidates,A.track_anchor_cache,mode)
 end
 v.source_context=ctx;v.source_mode=mode;v.source_same_count=same_count or 0;v.source_track_count=track_count or 0
 v.source_ready=true;v.source_detected=#regions
 v.source_candidate_count=mode==2 and (v.source_track_count or 1) or (v.source_same_count or 1)
 v.source_available=variants~=nil and v.source_candidate_count>1;v.source_reason=why;v.source_origin=mode==2 and 'track' or 'source'
 UI.sync_source_checkbox(v)
end
function UI.toggle_source_mode(guid)
 local v=A.item_by_guid and A.item_by_guid[guid];local row=A.apply.items[guid]
 if not v or not row or not v.source_ready then return end
 local same,track=v.source_same_count or 0,v.source_track_count or 0
 if same<=1 or track<=1 then return end
 row.source_mode=row.source_mode==2 and 1 or 2;A.source_auto[guid]=false;UI.source_status_from_cache(v);A.status='';A.warning=false
end
function UI.source_mode_switchable(v)
 return v and v.source_ready and (v.source_same_count or 0)>1 and (v.source_track_count or 0)>1
end
function UI.stop_source_job()
 if A.source_job then
  local job=A.source_job
  if not Core.source_cleanup(job) and job.project then A.stale_temp_projects[job.project]=true end
  A.source_job=nil
 end
 A.source_progress=0
end
function UI.retry_stale_temp_items(force)
 local now=R.time_precise();if not force and now<(A.stale_temp_retry_at or 0) then return end
 A.stale_temp_retry_at=now+5
 for project in pairs(A.stale_temp_projects or {}) do
  if not Core.project_is_open(project) then A.stale_temp_projects[project]=nil
  else local _,remaining=Core.cleanup_stale_temp_items(project);if remaining==0 then A.stale_temp_projects[project]=nil end end
 end
end
function UI.queue_bake_deletes(paths,project,watch_referenced)
 if not paths or #paths==0 then return end
 A.pending_bake_delete=Core.queue_pending_bake_deletes(A.pending_bake_delete,paths,project,watch_referenced)
 A.pending_bake_retry_delay=2;A.pending_bake_delete_at=R.time_precise()+.25
end
function UI.retry_pending_bake_deletes(force)
 local records=A.pending_bake_delete or {};if #records==0 then return end
 local now=R.time_precise();if not force and now<(A.pending_bake_delete_at or 0) then return end
 local before=#records;local unresolved,groups={},{}
 for _,record in ipairs(records) do
  if type(record)=='string' then record={path=record,project=A.project,project_guid=Core.project_guid(A.project)} end
  local project=Core.open_project_by_guid(record.project_guid or '',record.project)
  if not project then unresolved[#unresolved+1]=record
  else
   local group=groups[project];if not group then group={guid=Core.project_guid(project),paths={},records={}};groups[project]=group end
   group.paths[#group.paths+1]=record.path;group.records[#group.records+1]=record
  end
 end
 local next_records={};local seen={}
 local function keep(path,project,guid,watch_referenced)
  local key=media_path_key(path);local record_key=tostring(guid or '')..'\0'..tostring(key or '')
  if key and not seen[record_key] then
   next_records[#next_records+1]={path=path,project=project,project_guid=guid or '',watch_referenced=watch_referenced and true or false};seen[record_key]=next_records[#next_records]
  elseif key and watch_referenced then
   seen[record_key].watch_referenced=true
  end
 end
 for _,record in ipairs(unresolved) do keep(record.path,record.project,record.project_guid,record.watch_referenced) end
 for project,group in pairs(groups) do
  local failed,retained=Core.cleanup_bake_files(group.paths,project);local watches={}
  for _,record in ipairs(group.records) do local key=media_path_key(record.path);if key and record.watch_referenced then watches[key]=true end end
  for _,path in ipairs(failed) do keep(path,project,group.guid,watches[media_path_key(path)]) end
  for _,path in ipairs(retained) do if watches[media_path_key(path)] then keep(path,project,group.guid,true) end end
 end
 A.pending_bake_delete=next_records
 if #next_records==0 then A.pending_bake_retry_delay=2
 elseif #next_records<before then A.pending_bake_retry_delay=2
 else A.pending_bake_retry_delay=min(60,max(2,(A.pending_bake_retry_delay or 2)*2)) end
 A.pending_bake_delete_at=now+(A.pending_bake_retry_delay or 2)
 Core.save_pending_bake_deletes(next_records)
end
function UI.rebuild_source_queue()
 local seen={};A.source_queue={};A.source_queue_i=1;A.source_queue_done=false;A.track_candidate_pools={}
 for _,v in ipairs(A.items or {}) do
  local eligible=UI.prepare_source_info(v)
  if eligible and UI.source_requested(A.apply,v) and v.source_key and not A.source_cache[v.source_key] and not seen[v.source_key] then seen[v.source_key]=true;A.source_queue[#A.source_queue+1]=v end
 end
 for _,v in ipairs(A.items or {}) do UI.source_status_from_cache(v) end
end
function UI.source_queue_start_next()
 if not Media.ready() then return end
 if A.source_job or A.job or A.source_queue_done then return end
 while A.source_queue_i<=#A.source_queue do
  local v=A.source_queue[A.source_queue_i];A.source_queue_i=A.source_queue_i+1
  if v and v.source_key and not A.source_cache[v.source_key] then
   local ok,j=pcall(Core.source_scan_start,A.project,v)
   if ok then A.source_job=j;A.source_progress=0;return
   else UI.source_cache_set(v.source_key,{error=tostring(j):match('^[^\\n]+') or tostring(j)}) end
  end
 end
 A.source_queue_done=true
 for _,v in ipairs(A.items or {}) do UI.source_status_from_cache(v) end
 A.source_progress=0;A.revision=R.GetProjectStateChangeCount(A.project)
end
function UI.target_lock_capture(lock)
 lock=lock or A.target_lock;if not lock or R.EnumProjects(-1,'')~=lock.project then return false end
 local fingerprints,guids={},{}
 for i,item in ipairs(lock.refs or {}) do
  local fp=Core.target_fingerprint(lock.project,item);if not fp then return false end
  local ok,guid=R.GetSetMediaItemInfo_String(item,'GUID','',false);if not ok or not guid or guid=='' then return false end
  fingerprints[item]=fp;guids[i]=guid
 end
 if #lock.refs==0 then return false end
 lock.fingerprints=fingerprints;lock.guids=guids;lock.revision=R.GetProjectStateChangeCount(lock.project);return true
end
function UI.target_lock_generation_was_undone(project,lock)
 local rec=A.last_created
 if not rec or rec.project~=project or not rec.undo_desc or type(R.Undo_CanRedo2)~='function' or R.Undo_CanRedo2(project)~=rec.undo_desc then return false end
 local source_refs=rec.source_refs or {};local locked=lock.refs or {}
 if #source_refs==0 or #source_refs~=#locked then return false end
 local refs={}
 for _,item in ipairs(source_refs) do refs[item]=(refs[item] or 0)+1 end
 for _,item in ipairs(locked) do
  local n=refs[item];if not n then return false end
  if n==1 then refs[item]=nil else refs[item]=n-1 end
 end
 if next(refs) then return false end
 for _,entry in ipairs(rec.items or {}) do if entry.item and R.ValidatePtr2(project,entry.item,'MediaItem*') then return false end end
 return true
end
function UI.target_lock_restore_refs(project,lock)
 local guids=lock and lock.guids or nil;if not guids or #guids==0 then return false end
 local refs={}
 for i,guid in ipairs(guids) do
  local item=Core.find_item_by_guid(project,guid);if not item then return false end
  refs[i]=item
 end
 lock.refs=refs
 return UI.target_lock_capture(lock)
end
function UI.target_lock_valid(project)
 local lock=A.target_lock;if not lock then return true end
 project=project or R.EnumProjects(-1,'')
 if project~=lock.project then return false end
 local revision=R.GetProjectStateChangeCount(project)
 if lock.revision==revision then return true end
 for _,item in ipairs(lock.refs or {}) do
  local fp=Core.target_fingerprint(project,item)
  if not fp or fp~=(lock.fingerprints or {})[item] then
   if UI.target_lock_generation_was_undone(project,lock) and UI.target_lock_restore_refs(project,lock) then return true end
   return false
  end
 end
 lock.revision=revision;return true
end
function UI.target_lock_release(message,refresh_after)
 if not A.target_lock then return false end
 A.target_lock=nil;A.target_lock_poll=0
 local restore=A.source_execute_pending and A.source_execute_pending.restore_selection
 if A.source_job then UI.stop_source_job() end
 A.source_execute_pending=nil;A.source_queue={};A.source_queue_i=1;A.source_queue_done=true
 if restore then UI.restore_item_selection(A.project,restore,false) end
 if refresh_after then UI.refresh() end
 if message then UI.notice(message,false) end
 return true
end
function UI.target_lock_rebase()
 if not A.target_lock then return true end
 if UI.target_lock_capture(A.target_lock) or UI.target_lock_restore_refs(A.target_lock.project,A.target_lock) then return true end
 UI.target_lock_release('ロック対象が変更または削除されたため、対象ロックを解除しました。',false);return false
end
function UI.toggle_target_lock()
 if A.job or A.source_job or A.source_execute_pending or not Media.ready() then return end
 if A.target_lock then UI.target_lock_release('対象ロックを解除しました。',true);return end
 UI.refresh()
 if #A.items==0 then UI.notice('ロックするアイテムを選択してください。',true);return end
 local refs={};for _,v in ipairs(A.items) do refs[#refs+1]=v.item end
 local lock={project=A.project,refs=refs}
 if not UI.target_lock_capture(lock) then UI.notice('ロックするアイテムを選択してください。',true);return end
 A.target_lock=lock;A.target_lock_poll=0;UI.refresh();UI.notice('対象をロックしました。',false)
end
function UI.poll_target_lock(now)
 local lock=A.target_lock;if not lock or A.job or now<(A.target_lock_poll or 0) then return end
 A.target_lock_poll=now+.20
 if not UI.target_lock_valid(R.EnumProjects(-1,'')) then
  UI.target_lock_release('ロック対象が変更または削除されたため、対象ロックを解除しました。',true)
 end
end
function UI.activation_press(down)
 if down and (gfx.getchar(65536)&8)~=0 then UI.activationHeld=true end
 local active=UI.activationHeld
 if not down then UI.activationHeld=nil end
 return active==true
end
function UI.refresh()
 if not Media.ready() then return end
 local project=R.EnumProjects(-1,'')
 local project_changed=project~=A.project
 local lock_released=false
 if project_changed then
  if A.target_lock then A.target_lock=nil;A.target_lock_poll=0 end
  UI.stop_source_job();A.source_execute_pending=nil;Core.cleanup_stale_temp_items(project)
  A.source_cache={};A.track_anchor_cache={};A.source_cache_serial=0
  A.apply.items={};A.source_auto={};A.item_state_used={};A.item_state_serial=0
  A.matrix_selected={};A.last_created=nil;A.wave_region_key=nil;A.wave_region_index=nil;A.wave_region_selection={};A.source_wave_drag=nil;A.source_wave_scroll_drag=nil;A.source_wave_view={key=nil,zoom=1,start=0};motion={};voice_flash={};field_flash={}
  collectgarbage('collect')
 end
 A.project=project
 local list,err
 if A.target_lock then
  if UI.target_lock_valid(project) then
   list,err=Core.items_from_refs(project,A.target_lock.refs)
   if not list then A.target_lock=nil;A.target_lock_poll=0;lock_released=true;list,err=Core.selection(project) end
  else A.target_lock=nil;A.target_lock_poll=0;lock_released=true;list,err=Core.selection(project) end
 else list,err=Core.selection(project) end
 A.items=list or {};A.selection_error=err
 UI.ensure_apply_rows(A.items);A.selection_signature=Core.selection_signature(A.project)
 UI.rebuild_source_queue();UI.prune_source_cache();prune_used_cache(A.track_anchor_cache,TRACK_ANCHOR_LIMIT);A.revision=R.GetProjectStateChangeCount(A.project)
 UI.source_queue_start_next()
 if lock_released then UI.notice('ロック対象が変更または削除されたため、対象ロックを解除しました。',false) end
end
function UI.changed(key)
 UI.persist_later();A.status='';A.warning=false
 if key=='source_timing_mode' then for _,v in ipairs(A.items or {}) do UI.source_status_from_cache(v) end end
end
function UI.assignment_changed()
 A.feature_summary=nil
 UI.persist_later();A.status='';A.warning=false
 local restore=A.source_execute_pending and A.source_execute_pending.restore_selection
 A.source_execute_pending=nil;if restore and UI.restore_item_selection then UI.restore_item_selection(A.project,restore,true) end
 if A.source_job and not UI.source_requested(A.apply,A.source_job.info) then UI.stop_source_job() end
 UI.rebuild_source_queue();UI.source_queue_start_next()
end
function UI.feature_available(v,key)
 if v and v.is_midi then return Core.MIDI_FEATURES[key]==true end
 if key~='source' then return true end
 if not v._source_checked then UI.prepare_source_info(v) end
 return v._source_eligible==true and (not v.source_ready or v.source_available==true)
end
function UI.feature_summary()
 local summary=A.feature_summary
 if summary and summary.items==A.items then return summary end
 summary={items=A.items,audio=0}
 for _,key in ipairs(Core.FEATURES)do summary[key]={false,false,0}end
 for _,v in ipairs(A.items)do
  if not v.is_midi then summary.audio=summary.audio+1 end
  local row=A.apply.items[v.guid]
  for _,key in ipairs(Core.FEATURES)do
   if UI.feature_available(v,key)then
    local s=summary[key];local on=row and row[key]==true or false
    s[1],s[2],s[3]=(s[3]==0 or s[1])and on,s[2]or on,s[3]+1
   end
  end
 end
 A.feature_summary=summary;return summary
end
function UI.all_feature_state(key)
 local s=UI.feature_summary()[key];return s[1],s[2],s[3]
end
local FEATURE_BOUNDS={pitch_global={20,152,170,100},volume={198,152,160,100},timing={366,152,170,100},pan={544,152,150,100},source={702,152,178,100},pitch_curve={20,260,430,154},vibrato={20,260,430,154},tremolo={20,260,430,154},eq_texture={458,260,198,154},eq_tone={664,260,216,154}}
local FEATURE_TABS={pitch_curve={166,86},vibrato={256,86},tremolo={346,86}}
local FEATURE_FLASH_COLOR={1,.83,.18}
function UI.flash_feature(key)
 local now=R.time_precise();A.feature_flash=A.feature_flash or {};A.feature_flash[key]=now
 wake_visuals(now,.6,.6)
end
function UI.draw_feature_flashes()
 if not A.feature_flash then return end
 local yellow=FEATURE_FLASH_COLOR;local now=R.time_precise()
 for key,started in pairs(A.feature_flash) do
  local age=now-started;local r=FEATURE_BOUNDS[key]
  if age>=.55 then A.feature_flash[key]=nil
  elseif r then
   local a=(1-age/.55)^2;rect(r[1]+1,r[2]+1,r[3]-2,r[4]-2,yellow,.16*a)
   for n=0,1 do line(r[1]+n,r[2]+n,r[1]+r[3]-n,r[2]+n,yellow,.9*a) end
   local tab=FEATURE_TABS[key]
   if tab then rect(tab[1],266,tab[2],22,yellow,.32*a);rect(tab[1],287,tab[2],2,yellow,.95*a) end
  end
 end
 if not next(A.feature_flash) then A.feature_flash=nil end
end

function UI.set_feature_all(key,value)
 if value then UI.flash_feature(key) end
 for _,v in ipairs(A.items) do
  if UI.feature_available(v,key) then
   A.apply.items[v.guid][key]=value
   if key=='source' then A.source_auto[v.guid]=false end
  else A.apply.items[v.guid][key]=false end
 end
 UI.assignment_changed()
end
function UI.set_all_features(value)
 if value then
  for _,c in ipairs(FEATURE_COLUMNS) do local _,_,available=UI.all_feature_state(c.key);if available>0 then UI.flash_feature(c.key) end end
 end
 for _,v in ipairs(A.items) do
  local row=A.apply.items[v.guid]
  for _,c in ipairs(FEATURE_COLUMNS) do
   if UI.feature_available(v,c.key) then row[c.key]=value;if c.key=='source' then A.source_auto[v.guid]=false end
   else row[c.key]=false end
  end
 end
 UI.assignment_changed()
end
function UI.toggle_item_feature(guid,key)
 local row=A.apply.items[guid];if not row then return end
 local target=not row[key]
 if A.matrix_selected and A.matrix_selected[guid] then
  for _,v in ipairs(A.items) do if A.matrix_selected[v.guid] and UI.feature_available(v,key) then A.apply.items[v.guid][key]=target;if key=='source' then A.source_auto[v.guid]=false end end end
 else
  for _,v in ipairs(A.items) do if v.guid==guid and UI.feature_available(v,key) then row[key]=target;if key=='source' then A.source_auto[v.guid]=false end end end
 end
 if target then UI.flash_feature(key) end
 UI.assignment_changed()
end
function UI.select_matrix_item(idx,guid)
 if not idx or not guid then return end
 if A.wave_guid~=guid then A.wave_region_key=nil;A.wave_region_index=nil;A.wave_region_selection={};A.source_wave_drag=nil;A.source_wave_scroll_drag=nil;A.source_wave_view={key=nil,zoom=1,start=0} end
 A.wave_guid=guid
 local shift=(click_mods&8)~=0;local ctrl=(click_mods&4)~=0 or (click_mods&32)~=0
 if shift and A.matrix_anchor and A.items[A.matrix_anchor] then
  if not ctrl then A.matrix_selected={} end
  local a,b=min(A.matrix_anchor,idx),max(A.matrix_anchor,idx)
  for i=a,b do if A.items[i] then A.matrix_selected[A.items[i].guid]=true end end
 elseif ctrl then
  A.matrix_selected[guid]=not A.matrix_selected[guid];if not A.matrix_selected[guid] then A.matrix_selected[guid]=nil end;A.matrix_anchor=idx
 else
  A.matrix_selected={[guid]=true};A.matrix_anchor=idx
 end
end
function UI.set_voice_limit(guid,value)
 value=max(0,floor(tonumber(value) or 0))
 if value>VOICE_MAX then value=VOICE_MAX end
 local selected=A.matrix_selected and A.matrix_selected[guid]
 if selected then
  for _,v in ipairs(A.items) do
   if not v.is_midi and A.matrix_selected[v.guid] and A.apply.items[v.guid] then A.apply.items[v.guid].voice_limit=value end
  end
 elseif A.apply.items[guid] then
  local v=A.item_by_guid and A.item_by_guid[guid];if not (v and v.is_midi) then A.apply.items[guid].voice_limit=value end
 end
 UI.assignment_changed()
end
function UI.voice_step_value(value,dir)
 value=max(0,min(VOICE_MAX,floor(tonumber(value) or 0)))
 if dir>0 then return value==0 and 1 or min(VOICE_MAX,value+1) end
 if value<=1 then return 0 end
 return value-1
end
function UI.adjust_all_voice_limits(dir)
 for _,v in ipairs(A.items or {}) do local row=A.apply.items[v.guid];if row and not v.is_midi then row.voice_limit=UI.voice_step_value(row.voice_limit,dir) end end
 UI.assignment_changed()
end
function UI.audio_item_count() return UI.feature_summary().audio end

function UI.nearest_setting_value(key,n)
 local range=Core.ranges[key]
 if not range or not finite(n) then return nil end
 n=clamp(n,range[1],range[2])
 if range[3] then
  local step=range[3]
  n=floor((n-range[1])/step+.5)*step+range[1]
  n=clamp(n,range[1],range[2])
 end
 n=Core.quantize_setting(key,n)
 local base=key:match('^(.-)_lo$')
 if base then
  local hi=S[base..'_hi'];if finite(hi) then n=min(n,hi) end
 else
  base=key:match('^(.-)_hi$')
  if base then local lo=S[base..'_lo'];if finite(lo) then n=max(n,lo) end
  else
   base=key:match('^(.-)_start_pct$')
   if base then local finish=S[base..'_end_pct'];if finite(finish) then n=min(n,finish) end
   else
    base=key:match('^(.-)_end_pct$')
    if base then local start=S[base..'_start_pct'];if finite(start) then n=max(n,start) end end
   end
  end
 end
 return n
end
function UI.commit_edit()
 if not edit then return true end
 if edit.kind=='voice' then
  local text=tostring(edit.text or '');local raw=(text=='∞' or text:lower()=='inf' or text:lower()=='infinity') and 0 or tonumber(text)
  if not finite(raw) then local guid=edit.guid;voice_flash[guid]=R.time_precise();edit=nil;UI.notice('入力できなかったため、元の疑似発音数へ戻しました。',true);return true end
  local n=raw<=0 and 0 or clamp(floor(raw+.5),1,VOICE_MAX)
  if (raw~=0 and abs(n-raw)>1e-9) or raw>VOICE_MAX or raw<0 then voice_flash[edit.guid]=R.time_precise() end
  local guid=edit.guid;edit=nil;UI.set_voice_limit(guid,n);return true
 end
 local raw=tonumber(edit.text);local key=edit.key
 if not finite(raw) then
  field_flash[key]=R.time_precise();UI.notice(edit.title..'：入力できなかったため、元の値へ戻しました。',true);edit=nil;return true
 end
 local n=UI.nearest_setting_value(key,raw)
 if n==nil then UI.notice(edit.title..'：設定値を確定できません。',true);return false end
 if abs(n-raw)>1e-9 then field_flash[key]=R.time_precise() end
 S[key]=n;edit=nil;UI.changed(key);return true
end
local function begin_field_edit(key,title)
 edit={key=key,title=title,text=fmt(S[key]),selected=true}
end

function A.setting_drag_step(key)
 local r=Core.ranges[key];if not r then return nil end
 if key=='seed' then return 100 end
 if key=='interval' then return .1 end
 if key:find('_rate_') or key:find('_depth_') then return .1 end
 return 1
end
function A.setting_allows_fine(key)
 local step=A.setting_drag_step(key)
 return step and step<1 and (Core.precision[key] or 0)>0
end
function A.setting_effective_bounds(key)
 local r=Core.ranges[key];if not r then return nil,nil end
 local lo,hi=r[1],r[2];local base=key:match('^(.-)_lo$')
 if base and finite(S[base..'_hi']) then hi=min(hi,S[base..'_hi']) else
  base=key:match('^(.-)_hi$');if base and finite(S[base..'_lo']) then lo=max(lo,S[base..'_lo']) else
   base=key:match('^(.-)_start_pct$');if base and finite(S[base..'_end_pct']) then hi=min(hi,S[base..'_end_pct']) else
    base=key:match('^(.-)_end_pct$');if base and finite(S[base..'_start_pct']) then lo=max(lo,S[base..'_start_pct']) end
   end
  end
 end
 return lo,hi
end
function A.update_field_drag(py,fine)
 local d=A.field_drag;if not d then return end
 local dy=d.start_y-py
 if not d.moved and abs(dy)<3 then return end
 d.moved=true;edit=nil
 if d.kind=='voice' then
  local q=dy/3;local ticks=(q<0 and -1 or 1)*floor(abs(q)+.5)
  local raw=d.start_value+ticks;local n=clamp(raw,0,VOICE_MAX)
  if n~=raw and not d.clipped then voice_flash[d.guid]=R.time_precise();d.clipped=true elseif n==raw then d.clipped=false end
  local row=A.apply.items[d.guid]
  if row and max(0,floor(tonumber(row.voice_limit) or 0))~=n then UI.set_voice_limit(d.guid,n) end
  return
 end
 if not Core.ranges[d.key] then return end
 local base=A.setting_drag_step(d.key) or 1
 fine=fine and A.setting_allows_fine(d.key)
 local inc=base*(fine and .1 or 1)
 local pixels=fine and 8 or 3
 local q=dy/pixels;local ticks=(q<0 and -1 or 1)*floor(abs(q)+.5)
 local raw=d.start_value+ticks*inc;local lo,hi=A.setting_effective_bounds(d.key)
 local clipped=(lo and raw<lo-1e-9) or (hi and raw>hi+1e-9)
 local n=UI.nearest_setting_value(d.key,raw);if n==nil then return end
 if clipped and not d.clipped then field_flash[d.key]=R.time_precise();d.clipped=true elseif not clipped then d.clipped=false end
 if abs((S[d.key] or 0)-n)>1e-12 then S[d.key]=n;UI.changed(d.key) end
end

function A.curve_guide_points()
 return Core.curve_guide_decode(S.curve_guide_data,S.curve_start_pct,S.curve_end_pct,S.curve_guide_start,S.curve_guide_end,S.curve_guide_enabled)
end

A.CURVE_CENTER_SNAP_PX=8
A.CURVE_POINT_HIT_PX=10
A.CURVE_POINT_MIN_GAP_PX=5

function A.pitch_curve_pointer_value(px,py)
 local g=A.curve_graph_geom;if not g then return 0,0 end
 local pct=clamp((px-g.x)/max(1,g.w),0,1)*100
 local dy=g.cy-py;local norm=clamp(dy/max(1,g.amp),-1,1)
 if abs(dy)<=A.CURVE_CENTER_SNAP_PX then norm=0 end
 return pct,norm
end

function A.commit_pitch_curve_points(pts)
 pts=pts or {};table.sort(pts,function(a,b)return (a.pct or 0)<(b.pct or 0) end)
 if #pts<2 then
  A.curve_pending_point=pts[1] and {pct=clamp(pts[1].pct or 0,0,100),norm=clamp(pts[1].norm or 0,-1,1)} or nil
  S.curve_guide_enabled=false;S.curve_guide_data='';S.curve_start_pct=0;S.curve_end_pct=100;S.curve_guide_start=0;S.curve_guide_end=0
 else
  A.curve_pending_point=nil
  S.curve_guide_data=Core.curve_guide_encode(pts);S.curve_guide_enabled=true
  S.curve_start_pct=floor(clamp(pts[1].pct or 0,0,100)+.5);S.curve_end_pct=floor(clamp(pts[#pts].pct or 100,0,100)+.5)
  S.curve_guide_start=pts[1].norm or 0;S.curve_guide_end=pts[#pts].norm or 0
 end
 UI.changed('curve_guide_data')
end

function A.pitch_curve_point_at(px,py)
 local g=A.curve_graph_geom;if not g then return nil end
 local pts=S.curve_guide_enabled and A.curve_guide_points() or nil
 local pending=false
 if not pts or #pts==0 then
  if A.curve_pending_point then pts={A.curve_pending_point};pending=true else return nil end
 end
 local best_i,best_d=nil,A.CURVE_POINT_HIT_PX
 for i,p in ipairs(pts) do
  local x=g.x+g.w*(p.pct or 0)/100;local y=g.cy-clamp(p.norm or 0,-1,1)*g.amp
  local dx,dy=px-x,py-y;local d=math.sqrt(dx*dx+dy*dy)
  if d<=best_d then best_i,best_d=i,d end
 end
 return best_i,pts,pending
end

function A.add_pitch_curve_point(px,py)
 local pct,norm=A.pitch_curve_pointer_value(px,py)
 if S.curve_guide_enabled then
  local pts=A.curve_guide_points();pts=Core.curve_guide_add(pts,pct,norm);A.commit_pitch_curve_points(pts)
 elseif A.curve_pending_point then
  local pts={{pct=A.curve_pending_point.pct,norm=A.curve_pending_point.norm}}
  pts=Core.curve_guide_add(pts,pct,norm)
  if #pts>=2 then A.commit_pitch_curve_points(pts) else A.curve_pending_point={pct=pct,norm=norm} end
 else
  A.curve_pending_point={pct=pct,norm=norm}
 end
end

function A.delete_pitch_curve_point(index,pts,pending)
 if not index then return end
 if pending then A.curve_pending_point=nil;return end
 pts=pts or A.curve_guide_points();table.remove(pts,index);A.commit_pitch_curve_points(pts)
end

function A.begin_pitch_curve_move(index,pts,pending,px,py)
 if not index then return end
 local cp={};for i,p in ipairs(pts or {}) do cp[i]={pct=p.pct or 0,norm=p.norm or 0} end
 A.curve_drag={mode='move',index=index,points=cp,pending=pending,start_x=px,start_y=py,moved=false}
end

function A.update_pitch_curve_guide(px,py,begin_drag)
 local g=A.curve_graph_geom;if not g then return end
 local pct,norm=A.pitch_curve_pointer_value(px,py)
 if begin_drag or not A.curve_drag then
  A.curve_drag={mode='draw',pct=pct,norm=norm,current_pct=pct,current_norm=norm,start_x=px,start_y=py,moved=false}
  return
 end
 local d=A.curve_drag
 if d.mode=='action' then return end
 if d.mode=='move' then
  local dx,dy=px-d.start_x,py-d.start_y;if math.sqrt(dx*dx+dy*dy)>=3 then d.moved=true end
  if not d.moved then return end
  local pts=d.points;local i=d.index;if not pts or not pts[i] then return end
  if not d.pending then
   local gap=max(.75,A.CURVE_POINT_MIN_GAP_PX/max(1,g.w)*100)
   local lo=i>1 and (pts[i-1].pct or 0)+gap or 0
   local hi=i<#pts and (pts[i+1].pct or 100)-gap or 100
   if hi<lo then pct=(lo+hi)*.5 else pct=clamp(pct,lo,hi) end
  end
  pts[i].pct=pct;pts[i].norm=norm
  if d.pending then A.curve_pending_point={pct=pct,norm=norm} else A.commit_pitch_curve_points(pts) end
  return
 end
 d.current_pct=pct;d.current_norm=norm
 local dx=(pct-d.pct)*g.w/100;local dy=(norm-d.norm)*g.amp
 if math.sqrt(dx*dx+dy*dy)>=3 then d.moved=true end
end

function A.finish_pitch_curve_guide()
 local d=A.curve_drag;if not d or d.mode~='draw' or not d.moved then return end
 local pts=A.curve_guide_points()
 if (not S.curve_guide_enabled or #pts==0) and A.curve_pending_point then pts={{pct=A.curve_pending_point.pct,norm=A.curve_pending_point.norm}} end
 pts=Core.curve_guide_add(pts,d.pct,d.norm);pts=Core.curve_guide_add(pts,d.current_pct,d.current_norm)
 if #pts<2 then return end
 A.commit_pitch_curve_points(pts)
end
function A.clear_pitch_curve_guide()
 A.curve_pending_point=nil
 S.curve_guide_enabled=false;S.curve_guide_data='';S.curve_start_pct=0;S.curve_end_pct=100;S.curve_guide_start=0;S.curve_guide_end=0
 UI.changed('curve_guide_data')
end

function A.draw_pitch_curve_editor(x,y,w,h)
 local cy=y+h*.50;local amp=h*.35
 A.curve_graph_geom={x=x,y=y,w=w,h=h,cy=cy,amp=amp}
 gradient(x,y,w,h,C.field,C.panel,.82,.72);finish_corners(x,y,w,h,6,false,C.edge2,.26)
 line(x+1,cy,x+w-1,cy,C.edge2,.36)
 for i=1,4 do local xx=x+w*i/5;line(xx,y+5,xx,y+h-5,C.edge,.10) end
 local hi=clamp(tonumber(S.curve_hi) or 0,0,24);local lo=clamp(tonumber(S.curve_lo) or 0,-24,0)
 right_label(string.format('%+.1f st',hi),x+w-6,y+5,8,C.muted,3,true)
 right_label('0 st',x+w-6,cy-6,8,C.focus2,3,true)
 right_label(string.format('%.1f st',lo),x+w-6,y+h-28,8,C.muted,3,true)

 local pts=A.curve_guide_points()
 if S.curve_guide_enabled and #pts>=2 then
  local p0,p1=pts[1].pct or 0,pts[#pts].pct or 100
  if p0>0 then rect(x,y,w*p0/100,h,C.ink,.58) end
  if p1<100 then rect(x+w*p1/100,y,w*(1-p1/100),h,C.ink,.58) end
  for i=2,#pts do
   local a,b=pts[i-1],pts[i]
   local x1=x+w*(a.pct or 0)/100;local y1=cy-clamp(a.norm or 0,-1,1)*amp
   local x2=x+w*(b.pct or 0)/100;local y2=cy-clamp(b.norm or 0,-1,1)*amp
   line(x1,y1,x2,y2,C.focus2,.94);line(x1,y1+1,x2,y2+1,C.accent,.34)
  end
  for _,p in ipairs(pts) do disc(x+w*(p.pct or 0)/100,cy-clamp(p.norm or 0,-1,1)*amp,3.8,C.focus2,.92) end
  label(string.format('GUIDE / %d LINE',max(1,#pts-1)),x+10,y+6,9.5,C.focus2,2,112,15,0,true)
 else
  local n=clamp(floor(tonumber(S.curve_points) or 5),2,24);local lx,ly=nil,nil
  for i=1,n do
   local u=(i-1)/max(1,n-1);local yy=cy+(math.sin(i*2.17)+math.sin(i*.83+.7))*.16*amp
   local xx=x+12+u*(w-24)
   if lx then line(lx,ly,xx,yy,C.lock,.34) end;lx,ly=xx,yy
  end
  label('RND MODE',x+8,y+6,17,C.lock2,2,w-16,24,0,true)
  label('ドラッグでDRAWモードへ',x+8,y+32,14,C.muted,1,w-16,22,0,true)
  if A.curve_pending_point then
   local p=A.curve_pending_point;disc(x+w*(p.pct or 0)/100,cy-clamp(p.norm or 0,-1,1)*amp,4.2,C.focus2,.96)
   label('ALT+CLICKでもう1点',x+10,y+72,9.5,C.focus2,1,w-20,15,0,true)
  end
 end

 if A.curve_drag and A.curve_drag.mode=='draw' then
  local d=A.curve_drag;local x1=x+w*d.pct/100;local y1=cy-clamp(d.norm,-1,1)*amp
  local x2=x+w*d.current_pct/100;local y2=cy-clamp(d.current_norm,-1,1)*amp
  line(x1,y1,x2,y2,C.focus2,.96);disc(x1,y1,3.6,C.focus2,.95);disc(x2,y2,3.6,C.focus2,.95)
 elseif A.curve_drag and A.curve_drag.mode=='move' then
  local d=A.curve_drag;local p=d.points and d.points[d.index]
  if p then disc(x+w*(p.pct or 0)/100,cy-clamp(p.norm or 0,-1,1)*amp,6.0,C.accent2,.20) end
 end
 local show_pts=S.curve_guide_enabled and pts or nil
 local p0=show_pts and show_pts[1] and show_pts[1].pct or 0;local p1=show_pts and show_pts[#show_pts] and show_pts[#show_pts].pct or 100
 label(string.format('%d%%',floor(p0+.5)),x+5,y+h-17,8.5,C.muted,3,40,12,0,true)
 right_label(string.format('%d%%',floor(p1+.5)),x+w-5,y+h-17,8.5,C.muted,3,true)
 register('pitch_curve_graph',x,y,w,h,function()end,'点をドラッグ=移動 / Alt+クリック=追加 / Ctrl+クリック=削除 / 空所ドラッグ=線を追加 / 中央=0 st',not A.job)
end

function A.draw_mod_preview(kind,x,y,w,h)
 local vib=kind=='vibrato';local prefix=vib and 'vibrato' or 'tremolo'
 local a=clamp((S[prefix..'_start_pct'] or 0)/100,0,1);local b=clamp((S[prefix..'_end_pct'] or 100)/100,a,1)
 local shape=S[prefix..'_shape'] or 1;local rate=((S[prefix..'_rate_lo'] or 1)+(S[prefix..'_rate_hi'] or 1))*.5
 gradient(x,y,w,h,C.field,C.panel,.82,.72);finish_corners(x,y,w,h,6,false,C.edge2,.26)
 local cy=y+h*.46;line(x+1,cy,x+w-1,cy,C.edge2,.20)
 if a>0 then rect(x,y,w*a,h,C.ink,.60) end;if b<1 then rect(x+w*b,y,w*(1-b),h,C.ink,.60) end
 A.mod_draw_cache=A.mod_draw_cache or {};local cache=A.mod_draw_cache[kind]
 if not cache or cache.a~=a or cache.b~=b or cache.shape~=shape or cache.rate~=rate then
  cache={a=a,b=b,shape=shape,rate=rate,points={}};A.mod_draw_cache[kind]=cache
  local cycles=clamp(rate,1,12)*.55
  for i=0,80 do
   local u=i/80;local value=0
   if u>=a and u<=b and b>a then
    local q=(u-a)/(b-a);local env=shape==2 and q or (shape==3 and (1-q)or 1)
    value=math.sin(q*math.pi*2*cycles)*.30*env
   end
   cache.points[i+1]=value
  end
 end
 local lastx,lasty=x,cy-cache.points[1]*h
 for i=1,80 do
  local xx,yy=x+w*i/80,cy-cache.points[i+1]*h
  line(lastx,lasty,xx,yy,C.focus2,.72);lastx,lasty=xx,yy
 end
 label(string.format('%d%% — %d%%',floor(a*100+.5),floor(b*100+.5)),x+7,y+5,8,C.muted,3,w-14,12,0,true)
end

function UI.voice_control(v,x,y,w)
 if v.is_midi then
  local h=22;UI.field_frame('voice_'..v.guid,x,y,w,h,false,false);label('—',x,y,13,C.disabled,3,w,h,5,true)
  register('voice_'..v.guid,x,y,w,h,function()end,'MIDIでは疑似発音数を使用できません。',false);return
 end
 local row=A.apply.items[v.guid] or {};local value=max(0,floor(tonumber(row.voice_limit) or 0))
 local h=22;local arrowW=18;local valueW=w-arrowW
 local active=edit and edit.kind=='voice' and edit.guid==v.guid
  UI.field_frame('voice_'..v.guid,x,y,valueW,h,not A.job,active,voice_flash[v.guid])
  gfx.wheelRegion(sx(x),sy(y),valueW*scale,h*scale)
 local shown=active and edit.text or (value==0 and '∞' or tostring(value))
 local fsize=(not active and value==0) and 18 or 16
 label(shown,x,y,fsize,active and C.text or (value==0 and C.accent2 or C.text),value==0 and 1 or 3,valueW,h,5,true)
 register('voice_'..v.guid,x,y,valueW,h,function()
  edit={kind='voice',guid=v.guid,title='疑似発音数',text=value==0 and '∞' or tostring(value),selected=true}
 end,'疑似発音数：∞ = 制限なし / 1～'..VOICE_MAX..'。クリック入力 / 上下ドラッグ / ホイール変更',not A.job)
 local ax=x+valueW;local half=h/2
 UI.voice_arrows(ax,y,arrowW,h,not A.job,'voiceup_'..v.guid,'voicedown_'..v.guid)
 register('voiceup_'..v.guid,ax,y,arrowW,half,function() UI.set_voice_limit(v.guid,UI.voice_step_value(value,1)) end,'疑似発音数を1段階増やす（∞ → 1）',not A.job)
 register('voicedown_'..v.guid,ax,y+half,arrowW,half,function() UI.set_voice_limit(v.guid,UI.voice_step_value(value,-1)) end,'疑似発音数を1段階減らす（1 → ∞）',not A.job)
end
function UI.voice_global_control(x,y,w)
 local h=22;local arrowW=20;local valueW=w-arrowW
 UI.field_frame('voice_all',x,y,valueW,h,not A.job and UI.audio_item_count()>0,false)
 label('ALL',x,y+1,11,C.accent2,3,valueW,h-2,5,true)
 local ax=x+valueW;local half=h/2
 UI.voice_arrows(ax,y,arrowW,h,not A.job and UI.audio_item_count()>0,'vglobal_up','vglobal_down')
 local voice_enabled=not A.job and UI.audio_item_count()>0
 register('vglobal_up',ax,y,arrowW,half,function() UI.adjust_all_voice_limits(1) end,'全アイテムの疑似発音数を相対的に1段階増やす',voice_enabled)
 register('vglobal_down',ax,y+half,arrowW,half,function() UI.adjust_all_voice_limits(-1) end,'全アイテムの疑似発音数を相対的に1段階減らす',voice_enabled)
end
function UI.source_requested(apply,v)
 return ((apply.items[v.guid] or {}).source==true)
end
function UI.restore_item_selection(project,items,do_refresh)
 if not project or not items or R.EnumProjects(-1,'')~=project then return end
 local wanted={};local count=0
 for _,item in ipairs(items) do if not wanted[item] and R.ValidatePtr2(project,item,'MediaItem*') then wanted[item]=true;count=count+1 end end
 local unchanged=count==R.CountSelectedMediaItems(project)
 if unchanged then for i=0,count-1 do if not wanted[R.GetSelectedMediaItem(project,i)] then unchanged=false;break end end end
 if unchanged then if do_refresh then UI.refresh() end;return end
 R.SelectAllMediaItems(project,false)
 for _,item in ipairs(items or {}) do if R.ValidatePtr2(project,item,'MediaItem*') then R.SetMediaItemSelected(item,true) end end
 R.UpdateArrange();if do_refresh then UI.refresh() end
end
function UI.begin_source_execute(restore_selection)
 local requested,stamps,invalidated={},{},{};local count,scan_count=0,0
 UI.stop_source_job()
 for _,v in ipairs(A.items or {}) do
  if UI.source_requested(A.apply,v) then
   UI.prepare_source_info(v)
   local cached=v.source_key and A.source_cache[v.source_key] or nil
   local stamp=stamps[v.file]
   if stamp==nil then stamp=Core.source_file_stamp(v.file)or false;stamps[v.file]=stamp end
   if v.source_key and not invalidated[v.source_key] and not Core.source_cache_reusable(cached,stamp or nil) then
    A.source_cache[v.source_key]=nil;invalidated[v.source_key]=true;scan_count=scan_count+1
   end
   requested[v.guid]=true;count=count+1
  end
 end
 if count==0 or scan_count==0 then return false end
 A.source_execute_pending={project=A.project,selection_signature=A.selection_signature,target_locked=A.target_lock~=nil,requested=requested,restore_selection=restore_selection}
 UI.rebuild_source_queue();UI.source_queue_start_next()
 UI.notice('未解析・更新された素材を解析しています。完了後に自動で生成します。')
 return true
end
function UI.frozen_apply() return tcopy(A.apply) end
function UI.resume_generation(j)
 local thread=j.thread
 local ok,err=coroutine.resume(thread)
 if not ok then
  local detail=debug.traceback(thread,tostring(err));j.running=false;j.thread=nil
  A.job=nil;A.progress=0;UI.notice(detail,true);R.ShowConsoleMsg(BLT.publicError(detail)..'\n')
 elseif coroutine.status(thread)=='dead'then j.running=false;j.thread=nil end
end
function UI.cancel_job()
 local j=A.job;if not j then return end
 j.cancelled=true
 if j.running then
  if j.thread and coroutine.running()~=j.thread then UI.resume_generation(j)end
  return
 end
 A.job=nil;A.progress=0;UI.restore_item_selection(j.snapshot.project,j.restore_selection,false)
 UI.notice('生成を中止しました。');UI.refresh()
end
function UI.step_generation()
 if not Media.ready()then return end
 local j=A.job;if not j then return end
 if not j.thread then
  j.running=true
  j.thread=coroutine.create(function()
   UI.finish_generation(j)
   UI.restore_item_selection(j.snapshot.project,j.restore_selection,true)
  end)
 end
 UI.resume_generation(j)
end
function UI.generation_input(j)
 if A.closing then j.cancelled=true end
 if not j.cancelled and not j.committing and coroutine.running()==j.thread then coroutine.yield()end
end
function UI.finish_generation(j)
 local groups,err=Core.plan(j.snapshot.items,j.settings,j.apply,Core.occupancy(j.snapshot.project,j.snapshot.items))
 if not groups then A.job=nil;A.progress=0;UI.refresh();UI.notice(err,true);return nil end
 UI.generation_input(j)
 if j.cancelled then A.job=nil;A.progress=0;UI.notice('生成を中止しました。');return nil end
 j.committing=true
 local count,created_or_err,free_before,original_before,cleanup_failed,rollback_ok=Core.apply(j.snapshot,groups,j.settings,function(progress)
  A.progress=progress
  if j.cancelled then return false,'生成を中止しました。' end
  local revision=R.GetProjectStateChangeCount(j.snapshot.project)
  UI.generation_input(j,progress)
  if j.cancelled then return false,'生成を中止しました。' end
  if R.EnumProjects(-1,'')~=j.snapshot.project or
   (R.GetProjectStateChangeCount(j.snapshot.project)~=revision and not Core.generation_targets_valid(j.snapshot)) then
   return false,'生成対象が変更されたため中止しました。'
  end
  return true
 end,j.restore_selection)
 j.committing=nil
 if not count then UI.queue_bake_deletes(cleanup_failed,j.snapshot.project);A.job=nil;A.progress=0;UI.refresh();UI.notice(j.cancelled and rollback_ok and '生成を中止し、今回のコピーを削除しました。' or created_or_err,not (j.cancelled and rollback_ok));return nil end
 A.job=nil;A.progress=0;local refs={};for _,v in ipairs(j.snapshot.items) do refs[#refs+1]=v.item end;A.last_created={project=j.snapshot.project,items=created_or_err or {},count=count,seed=j.settings.seed,source_refs=refs,free_before=free_before or {},original_before=original_before or {},undo_desc='BLT Variant Forge: '..#groups..' variations'}
 UI.target_lock_rebase()
 UI.restore_item_selection(j.snapshot.project,j.restore_selection or refs,false)
 local src_on=0;for _,v in ipairs(j.snapshot.items) do if UI.source_requested(j.apply,v) then src_on=src_on+1 end end
  VariantUI.now=R.time_precise();VariantUI:complete('execute',320/density,38/density);request_redraw(nil,.9)
  UI.notice(string.format('%dバリエーション / %dアイテムを作成 · SEED %d%s',#groups,count,j.settings.seed,src_on>0 and string.format(' · 素材 %d',src_on) or ''),false)
 return true
end
function UI.source_preflight_message()
 for _,v in ipairs(A.items or {}) do if UI.source_requested(A.apply,v) then
  if not v.source_ready then return '素材バリエーションの事前解析が完了していません。' end
  if not v.source_available then return (v.name or '素材')..'：'..tostring(v.source_reason or 'バリエーションなし') end
 end end
 return nil
end
function UI.prepare_texture_waves(list,app)
 local any=false
 for _,v in ipairs(list or {}) do
  local ia=((app or {}).items or {})[v.guid] or {}
  if ia.eq_texture then any=true;break end
 end
 if not any then
  for _,v in ipairs(list or {}) do v.texture_bank=nil end
  return true
 end
 local bank=A.texture_bank or {}
 for _,v in ipairs(list or {}) do
  local ia=((app or {}).items or {})[v.guid] or {}
  v.texture_bank=(ia.eq_texture and #bank>0) and bank or nil
 end
 return true
end
function UI.execute(source_refresh_done)
 if not A.job and not A.busy and not A.batch and not Media.ready() then return end
 if A.job then UI.cancel_job();return end;if not UI.commit_edit() then return end
 if A.source_execute_pending and not source_refresh_done then
  local restore=A.source_execute_pending.restore_selection
  UI.stop_source_job();A.source_execute_pending=nil;A.source_queue={};A.source_queue_i=1;A.source_queue_done=true
  if restore then UI.restore_item_selection(A.project,restore,true) end
  UI.notice('実行前の素材再解析を中止しました。');return
 end
 local ok,err=Core.validate(S);if not ok then UI.notice(err,true);return end
 UI.refresh();if #A.items==0 then UI.notice(A.selection_error,true);return end;if #A.items*S.count>2000 then UI.notice('合計2000アイテム以下にしてください。',true);return end
 local visible_selection={};for i=0,R.CountSelectedMediaItems(A.project)-1 do visible_selection[#visible_selection+1]=R.GetSelectedMediaItem(A.project,i) end
 if not source_refresh_done and UI.begin_source_execute(visible_selection) then return end
 local pending=UI.source_preflight_message();if pending then UI.notice(pending,true);return end
 if A.source_job then UI.notice('素材バリエーションの事前解析中です。',true);return end
 if not S.seed_lock then S.seed=Core.random_seed();UI.persist_later() end
 local worked,why=xpcall(function()
  local app=UI.frozen_apply();local tex_ok,tex_err=UI.prepare_texture_waves(A.items,app);if not tex_ok then error(tex_err,0) end
  local j={snapshot=Core.snapshot(A.project,A.items),settings=copy(S),apply=app,restore_selection=visible_selection}
  A.job=j;A.progress=0
 end,debug.traceback)
 if not worked then A.job=nil;UI.notice(why,true);R.ShowConsoleMsg(BLT.publicError(why)..'\n') end
end
function UI.last_created_count()
 local rec=A.last_created;local project=R.EnumProjects(-1,'')
 if not rec or rec.project~=project then
  A.last_count_record,A.last_count_revision,A.last_count_value=nil,nil,0
  return 0
 end
 local revision=R.GetProjectStateChangeCount(project)
 if A.last_count_record==rec and A.last_count_revision==revision then return A.last_count_value or 0 end
 local n=0
 for _,v in ipairs(rec.items or {}) do if v.item and R.ValidatePtr2(rec.project,v.item,'MediaItem*') then n=n+1 end end
 A.last_count_record,A.last_count_revision,A.last_count_value=rec,revision,n
 return n
end
function A.pending_texture_count()
 local rec=A.last_created;local project=R.EnumProjects(-1,'')
 if not rec or rec.project~=project then return 0 end
 local revision=R.GetProjectStateChangeCount(project)
 if A.bake_scan_record==rec and A.bake_scan_revision==revision then return A.bake_scan_count or 0 end
 local n=0
 for _,entry in ipairs(rec.items or {}) do
  if entry.item and R.ValidatePtr2(project,entry.item,'MediaItem*') then
   local take=R.GetActiveTake(entry.item);if take and not R.TakeIsMIDI(take) then n=n+Core.texture_fx_count(take) end
  end
 end
 A.bake_scan_record,A.bake_scan_revision,A.bake_scan_count=rec,revision,n
 return n
end
function A.bake_last_texture_fx()
 if A.job or A.source_job then return end
 local rec=A.last_created;local project=R.EnumProjects(-1,'')
 if not rec or rec.project~=project then UI.notice('焼き込める直前の生成結果がありません。',true);return end
 local targets={}
 for _,entry in ipairs(rec.items or {}) do
  if entry.item and R.ValidatePtr2(project,entry.item,'MediaItem*') then
   local take=R.GetActiveTake(entry.item)
   if take and not R.TakeIsMIDI(take) then local count=Core.texture_fx_count(take);if count>0 then targets[#targets+1]={entry=entry,item=entry.item,take=take,count=count} end end
  end
 end
 if #targets==0 then UI.notice('焼き込み待ちのTEXTURE FXはありません。');return end
 local bake_file_counts={};for _,t in ipairs(targets) do bake_file_counts[t.entry]=#(t.entry.bake_files or {}) end
 local selection={};for i=0,R.CountSelectedMediaItems(project)-1 do selection[#selection+1]=R.GetSelectedMediaItem(project,i) end
 R.Undo_BeginBlock2(project);R.PreventUIRefresh(1);local fx_ui_setting=Core.suppress_new_fx_windows()
 local ok,err=xpcall(function()
  for _,t in ipairs(targets) do
   local item,take=t.item,t.take
   if not R.ValidatePtr2(project,item,'MediaItem*') or not R.ValidatePtr2(project,take,'MediaItem_Take*') then error('焼き込み対象が変更されました。',0) end
   local state={
    pos=R.GetMediaItemInfo_Value(item,'D_POSITION'),len=R.GetMediaItemInfo_Value(item,'D_LENGTH'),
    fade_in=R.GetMediaItemInfo_Value(item,'D_FADEINLEN'),fade_in_auto=R.GetMediaItemInfo_Value(item,'D_FADEINLEN_AUTO'),
    fade_out=R.GetMediaItemInfo_Value(item,'D_FADEOUTLEN'),fade_out_auto=R.GetMediaItemInfo_Value(item,'D_FADEOUTLEN_AUTO'),
    free_y=R.GetMediaItemInfo_Value(item,'F_FREEMODE_Y'),free_h=R.GetMediaItemInfo_Value(item,'F_FREEMODE_H')}
   local _,name=R.GetSetMediaItemTakeInfo_String(take,'P_NAME','',false)
   local baked=Core.bake_texture_eq(project,item,take,t.count,t.entry)
   R.SetMediaItemInfo_Value(item,'D_POSITION',state.pos);R.SetMediaItemInfo_Value(item,'D_LENGTH',state.len)
   R.SetMediaItemInfo_Value(item,'D_FADEINLEN',state.fade_in);R.SetMediaItemInfo_Value(item,'D_FADEINLEN_AUTO',state.fade_in_auto)
   R.SetMediaItemInfo_Value(item,'D_FADEOUTLEN',state.fade_out);R.SetMediaItemInfo_Value(item,'D_FADEOUTLEN_AUTO',state.fade_out_auto)
   R.SetMediaItemInfo_Value(item,'F_FREEMODE_Y',state.free_y);R.SetMediaItemInfo_Value(item,'F_FREEMODE_H',state.free_h)
   if type(name)=='string' then R.GetSetMediaItemTakeInfo_String(baked,'P_NAME',name,true) end
   t.entry.texture_fx_count=0
  end
 end,debug.traceback)
 Core.restore_new_fx_windows(fx_ui_setting)
 R.SelectAllMediaItems(project,false);for _,it in ipairs(selection) do if R.ValidatePtr2(project,it,'MediaItem*') then R.SetMediaItemSelected(it,true) end end
 R.PreventUIRefresh(-1);R.UpdateTimeline();R.UpdateArrange()
 R.Undo_EndBlock2(project,ok and ('BLT Variant Forge: bake texture FX ('..#targets..' items)') or 'BLT Variant Forge: texture FX bake failed',4)
 A.bake_scan_record=nil;A.bake_scan_revision=nil;A.bake_scan_count=0
 if not ok then
  local additions={}
  for _,t in ipairs(targets) do local files=t.entry.bake_files or {};for i=(bake_file_counts[t.entry] or 0)+1,#files do additions[#additions+1]=files[i] end end
  UI.queue_bake_deletes(additions,project,true)
  R.ShowConsoleMsg('BLT Variant Forge:\n'..BLT.publicError(err)..'\n');UI.notice('FX焼込に失敗しました。Undoで焼き込み前へ戻してください。生成途中のWAVは参照が外れた後に自動回収します。',true);return
 end
 UI.notice(string.format('TEXTURE FXを%dアイテムへ焼き込みました。再生成は引き続き使用できます。',#targets))
end
function UI.regeneration_ready()
 if A.job or A.source_job or UI.last_created_count()<=0 then return false end
 if A.target_lock and not UI.target_lock_valid(A.project) then return false end
 local rec=A.last_created;if not rec or rec.project~=A.project then return false end
 if type(R.Undo_CanUndo2)~='function' or type(R.Undo_DoUndo2)~='function' or not rec.undo_desc or R.Undo_CanUndo2(rec.project)~=rec.undo_desc then return false end
 local refs=rec.source_refs or {};if #refs~=#A.items or #refs==0 then return false end
 local current={};for _,v in ipairs(A.items or {}) do current[v.item]=true end
 for _,item in ipairs(refs) do if not current[item] or not R.ValidatePtr2(rec.project,item,'MediaItem*') then return false end end
 return true
end
function UI.primary_action()
 if A.job then UI.cancel_job();return end
 if A.target_lock and not UI.target_lock_valid(A.project) then UI.target_lock_release('ロック対象が変更または削除されたため、対象ロックを解除しました。',true);return end
 if UI.regeneration_ready() then UI.regenerate() else UI.execute() end
end
function UI.regenerate()
 if A.job or A.source_job then return end
 if UI.last_created_count()<=0 then UI.notice('再生成できる直前の生成結果がありません。',true);return end
 local rec=A.last_created;local refs=rec and rec.source_refs or nil
 if not refs or #refs==0 then UI.notice('再生成元のアイテム情報がありません。生成し直してください。',true);return end
 for _,it in ipairs(refs) do if not R.ValidatePtr2(rec.project,it,'MediaItem*') then UI.notice('元アイテムが削除されているため再生成できません。現在の生成結果は残しました。',true);return end end
 if type(R.Undo_CanUndo2)~='function' or type(R.Undo_DoUndo2)~='function' or not rec.undo_desc or R.Undo_CanUndo2(rec.project)~=rec.undo_desc then
  UI.notice('再生成のUndoを統合できません。生成後に別のUndo操作があります。',true);return
 end
 local user_selection={};for i=0,R.CountSelectedMediaItems(rec.project)-1 do user_selection[#user_selection+1]=R.GetSelectedMediaItem(rec.project,i) end
 local function restore_user_selection(do_refresh)
  R.SelectAllMediaItems(rec.project,false)
  for _,it in ipairs(user_selection) do if R.ValidatePtr2(rec.project,it,'MediaItem*') then R.SetMediaItemSelected(it,true) end end
  R.UpdateArrange();if do_refresh then UI.refresh() end
 end
 A.last_created=nil
 local undone=R.Undo_DoUndo2(rec.project)
 if not undone or undone==0 then A.last_created=rec;UI.notice('再生成のUndoを統合できません。生成後に別のUndo操作があります。',true);return end
 UI.target_lock_rebase()
 if not A.target_lock then R.SelectAllMediaItems(rec.project,false);for _,it in ipairs(refs) do if R.ValidatePtr2(rec.project,it,'MediaItem*') then R.SetMediaItemSelected(it,true) end end;R.UpdateArrange() end
 UI.refresh()
 UI.execute()
 if A.target_lock then
  if not A.job and not A.source_execute_pending then restore_user_selection(true) end
 else
  if A.job then A.job.restore_selection=user_selection elseif A.source_execute_pending then A.source_execute_pending.restore_selection=user_selection else restore_user_selection(true) end
 end
end
function UI.work_step()
 if not Media.ready() then return end
 if A.job then UI.step_generation();return end
 Core.touch_temp_heartbeat(false)
 UI.retry_stale_temp_items(false)
 UI.retry_pending_bake_deletes(false)
 if not A.source_job then
  if not A.source_queue_done then UI.source_queue_start_next() end
  if A.source_queue_done and A.source_execute_pending then
   local pending=A.source_execute_pending;A.source_execute_pending=nil
   local target_changed=pending.target_locked and (not A.target_lock or not UI.target_lock_valid(pending.project))
    or (not pending.target_locked and Core.selection_signature(pending.project)~=pending.selection_signature)
   if R.EnumProjects(-1,'')~=pending.project or target_changed then
    UI.restore_item_selection(pending.project,pending.restore_selection,true);UI.refresh();UI.notice('素材の再解析中に対象またはプロジェクトが変わったため、実行を中止しました。',true);return
   end
   for guid in pairs(pending.requested or {}) do
    local v=A.item_by_guid[guid]
    if not v or not UI.source_requested(A.apply,v) or not UI.source_available(v) then
     UI.restore_item_selection(pending.project,pending.restore_selection,true);UI.notice((v and v.name or '素材')..'：再解析後に素材バリエーションを使用できません。',true);return
    end
   end
   UI.execute(true)
   if A.job then A.job.restore_selection=pending.restore_selection elseif pending.restore_selection then UI.restore_item_selection(pending.project,pending.restore_selection,true) end
  end
  return
 end
 local deadline=R.time_precise()+.012
 repeat
  local j=A.source_job;if not j then return end
  local ok,done,result=pcall(Core.source_scan_step,j)
  if not ok then
   local key=j.info and (j.info.source_key or Core.source_cache_key(j.info));local message=tostring(done):match('^[^\n]+') or tostring(done);Core.source_cleanup(j);if j.cleanup_failed and j.project then A.stale_temp_projects[j.project]=true end;A.source_job=nil
   A.revision=R.GetProjectStateChangeCount(A.project)
   if message:find('解析中にプロジェクトが変更',1,true) or message:find('解析中にプロジェクトが切り替わり',1,true) or message:find('解析中に元アイテムが削除',1,true) or message:find('解析中に音声が変更',1,true) then
    local restore=A.source_execute_pending and A.source_execute_pending.restore_selection
    A.source_execute_pending=nil;A.source_queue={};A.source_queue_i=1;UI.restore_item_selection(A.project,restore,true);UI.refresh();return
   end
   if key then UI.source_cache_set(key,{error=message}) end
   UI.rebuild_source_queue();UI.source_queue_start_next();return
  end
  A.source_progress=j.total>0 and clamp(j.offset/j.total,0,1) or 0
  if done then
   local key=j.info.source_key or Core.source_cache_key(j.info);UI.source_cache_set(key,result or {regions={}});if j.cleanup_failed and j.project then A.stale_temp_projects[j.project]=true end;A.source_job=nil;A.source_progress=0;A.revision=R.GetProjectStateChangeCount(A.project)
   for _,v in ipairs(A.items or {}) do if v.source_key==key then UI.source_status_from_cache(v) end end
   UI.source_queue_start_next();return
  end
 until R.time_precise()>=deadline
end

function UI.draw_scroll_hint(cx,y,dir)
 local phase=scroll_anim_phase
 for i=0,2 do
  local u=(phase+i*.29)%1
  local env=math.sin(math.pi*clamp(u,0,1))^1.05
  local travel=(u-.45)*12*dir
  local open=8.5+2.8*(.5+.5*math.sin((u*1.35+i*.37)*math.pi*2))
  local ay=y+travel-dir*(i-1)*2.0;local tip=ay+dir*(5.5+1.5*env);local shoulder=ay-dir*(2.7+1.1*env)
  local alpha=.30+.58*env
  glow_line(cx-open-1.8,shoulder,cx,tip,C.accent2,alpha*.48)
  glow_line(cx+open+1.8,shoulder,cx,tip,C.accent2,alpha*.48)
  glow_line(cx-open,shoulder,cx-3.1,ay+dir*.3,C.focus2,alpha*.86)
  glow_line(cx-3.1,ay+dir*.3,cx,tip,C.focus2,alpha*.94)
  glow_line(cx+open,shoulder,cx+3.1,ay+dir*.3,C.focus2,alpha*.86)
  glow_line(cx+3.1,ay+dir*.3,cx,tip,C.focus2,alpha*.94)
 end
end

Core.TEXTURE_MAX_REFERENCES=10
Core.TEXTURE_MAX_SECONDS=60
function A.texture_popup(message)
 message=tostring(message or 'TEXTURE EQ参照の解析に失敗しました。')
 UI.notice(message,true)
 if type(R.ShowMessageBox)=='function' then R.ShowMessageBox(message,'BLT Variant Forge · TEXTURE EQ',0) end
end
function A.capture_texture_bank_from_selection()
 if not Media.ready() then return end
 if A.job then return end
 local project=R.EnumProjects(-1,'');local count=R.CountSelectedMediaItems(project)
 if count<1 then A.texture_popup('TEXTURE EQの参照にする音声アイテムを1～10個選択してください。');return end
 if count>Core.TEXTURE_MAX_REFERENCES then A.texture_popup(string.format('TEXTURE EQの参照素材は最大%d個です。\n現在 %d個 選択されています。',Core.TEXTURE_MAX_REFERENCES,count));return end
 local infos={}
 for i=0,count-1 do
  local item=R.GetSelectedMediaItem(project,i);local info,why=Core.item_info(project,item)
  if not info then A.texture_popup(string.format('%d番目の選択アイテムを解析できません。\n%s',i+1,tostring(why or '音声アイテムを選択してください。')));return end
  if info.is_midi then A.texture_popup(string.format('%d番目の選択アイテムはMIDIです。\nTEXTURE EQ参照には音声アイテムを使用してください。',i+1));return end
  if (info.len or 0)>Core.TEXTURE_MAX_SECONDS+1e-9 then
   A.texture_popup(string.format('TEXTURE EQ参照には長すぎる素材があります。\n\n%s\n%.2f 秒\n\n1素材あたり最大 %d 秒です。',info.name or '素材',info.len or 0,Core.TEXTURE_MAX_SECONDS));return
  end
  infos[#infos+1]=info
 end
 local bank={}
 for i,info in ipairs(infos) do
  local spectrum,why=Core.capture_texture_spectrum(info)
  if not spectrum or not spectrum.db or #spectrum.db<8 then A.texture_popup(string.format('%s のスペクトルを解析できません。\n%s',info.name or ('素材 '..i),tostring(why or '周波数情報を取得できません。')));return end
  bank[#bank+1]={name=info.name or ('TEXTURE '..i),guid=info.guid,file=info.file,length=info.len,spectrum=spectrum}
 end
 A.texture_bank=bank;A.texture_preview_index=1
 UI.notice(string.format('TEXTURE EQ：%d素材を解析・登録しました。',#bank),false)
end
function A.clear_texture_bank()
 A.texture_bank={};A.texture_preview_index=1
 UI.notice('TEXTURE EQの参照素材をクリアしました。',false)
end
function A.texture_preview_current()
 local bank=A.texture_bank or {};local n=#bank
 if n==0 then A.texture_preview_index=1;return nil,0,0 end
 local i=clamp(floor(tonumber(A.texture_preview_index) or 1),1,n);A.texture_preview_index=i
 return bank[i],i,n
end
function A.texture_preview_step(dir)
 local bank=A.texture_bank or {};local n=#bank;if n<2 then return end
 local i=clamp(floor(tonumber(A.texture_preview_index) or 1),1,n);i=((i-1+(dir<0 and -1 or 1))%n)+1;A.texture_preview_index=i
end
function A.texture_bank_label()
 local item=A.texture_preview_current()
 if not item then return '未設定 · AUTO TEXTURE' end
 return item.name or 'TEXTURE素材'
end
function A.texture_bank_hint()
 local bank=A.texture_bank or {};if #bank==0 then return '未設定時はAUTO TEXTUREを使用。参照を使う場合は1～10個の音声アイテムを選択して解析・設定します。' end
 local names={};for i,v in ipairs(bank) do names[#names+1]=string.format('%d. %s',i,v.name or '素材') end
 return table.concat(names,' / ')
end

function Core.texture_preview_bands(bank,index)
 local i=clamp(floor(tonumber(index) or 1),1,max(1,#(bank or {})))
 if bank and #bank>0 and bank[i] and bank[i].spectrum then
  return Core.texture_eq_from_spectrum(bank[i].spectrum,{detail=27,depth=1.06,sharp=1.0,jitter_oct=0,freq_scale=1})
 end
 return Core.auto_texture_eq(Core.rng(230031))
end
function A.texture_preview_geometry(w)
 local width=max(1,floor(w))
 local key=table.concat({tostring(A.texture_bank),tostring(A.texture_preview_index or 1),tostring(S.texture_strength or 100),tostring(width)},'|')
 local cached=A.texture_draw_cache
 if cached and cached.key==key then return cached.bands,cached.responses end
 local bands=Core.scale_texture_bands(Core.texture_preview_bands(A.texture_bank or {},A.texture_preview_index or 1),S.texture_strength)
 local responses={}
 if bands and #bands>0 then
  local ln2=math.log(2)
  for px=0,width do
   local t=px/max(1,w)
   local freq=45*((19000/45)^t)
   local response=0
   for _,b in ipairs(bands) do
    local bw=max(.012,tonumber(b.bw) or .05)
    local oct=math.log(freq/max(1,tonumber(b.freq) or 1000))/ln2
    local sigma=max(.018,bw*.60)
    response=response+(tonumber(b.gain) or 0)*math.exp(-.5*(oct/sigma)^2)
   end
   responses[px+1]=clamp(response,-24,24)
  end
 end
 A.texture_draw_cache={key=key,bands=bands or {},responses=responses}
 return A.texture_draw_cache.bands,A.texture_draw_cache.responses
end
function A.draw_texture_eq_preview(x,y,w,h)
 local bands,responses=A.texture_preview_geometry(w)
 local mid=y+h*.5
 line(x,mid,x+w,mid,C.edge2,.20)
 for i=1,3 do
  local gx=x+w*i/4
  line(gx,y+2,gx,y+h-2,C.edge,.08)
 end
 if not bands or #bands==0 then return end
 local prevx,prevy=nil,nil
 local step=max(1,floor(w/82+.5))
 local last_px=floor(w)
 for px=0,last_px,step do
  local response=responses[px+1] or 0
  local py=mid-response/24*(h*.43)
  local xx=x+px
  if prevx then
   line(prevx,prevy-1,xx,py-1,C.accent2,.055)
   line(prevx,prevy+1,xx,py+1,C.accent2,.055)
   line(prevx,prevy,xx,py,C.accent2,.82)
  end
  prevx,prevy=xx,py
 end
 if last_px%step~=0 then
  local response=responses[last_px+1] or 0;local py=mid-response/24*(h*.43);local xx=x+last_px
  if prevx then line(prevx,prevy-1,xx,py-1,C.accent2,.055);line(prevx,prevy+1,xx,py+1,C.accent2,.055);line(prevx,prevy,xx,py,C.accent2,.82) end
 end
 for _,b in ipairs(bands) do
  local f=clamp(tonumber(b.freq) or 1000,45,19000)
  local t=math.log(f/45)/math.log(19000/45)
  local yy=mid-clamp(tonumber(b.gain) or 0,-24,24)/24*(h*.43)
  disc(x+t*w,yy,1.35,C.focus2,.80)
 end
end
function UI.waveform_item()
 return (A.wave_guid and A.item_by_guid[A.wave_guid]) or (A.items and A.items[1]) or nil
end
function UI.source_wave_data(v)
 if not Media.ready() then return end
 if not v then return nil,false end
 local key=v.source_key
 if key then
 local cached=UI.source_cache_get(key)
  if cached and not cached.error then return cached,false end
  local j=A.source_job
  if j and j.info and (j.info.source_key or Core.source_cache_key(j.info))==key then return j,true end
 end
 return nil,false
end
function UI.source_analysis_action(v)
 local row=A.apply.items[v.guid] or {}
 if row.source and A.source_job then
  local active=A.source_job.info and A.source_job.info.source_key==v.source_key
  return active and '解析中' or '待機中','解析完了後、使用可能ならSOURCEがONになります。',false
 end
 return '解析','クリックで素材全体を解析し、使用可能ならSOURCEをONにします。',not A.job
end
function UI.start_source_analysis(v)
 if A.job or v.source_ready or not UI.feature_available(v,'source') then return end
 local row=A.apply.items[v.guid];if not row then return end
 A.wave_guid=v.guid;row.source=false;UI.toggle_item_feature(v.guid,'source')
end
function UI.source_regions_changed(key,message)
 local data=key and A.source_cache[key] or nil;if not data or data.error then return end
 data.detected=#(data.regions or {});data.manual_regions=true
 for _,v in ipairs(A.items or {}) do if v.source_key==key then UI.source_status_from_cache(v) end end
 if message then UI.notice(message,false) end
end
function UI.clear_source_region_selection()
 A.wave_region_key=nil;A.wave_region_index=nil;A.wave_region_selection={}
end
function UI.source_region_selected(key,index)
 return A.wave_region_key==key and A.wave_region_selection and A.wave_region_selection[index]==true
end
function UI.source_selected_indices(data,key,fallback)
 local out={};local seen={}
 if data and A.wave_region_key==key then
  for i,on in pairs(A.wave_region_selection or {}) do
   if on and type(i)=='number' and data.regions and data.regions[i] and not seen[i] then seen[i]=true;out[#out+1]=i end
  end
 end
 if #out==0 and fallback and data and data.regions and data.regions[fallback] then out[1]=fallback end
 table.sort(out);return out
end
function UI.select_source_region(v,index)
 if not v or not v.source_key then return end
 local data=A.source_cache[v.source_key];if not data or data.error or not data.regions[index] then return end
 A.wave_region_key=v.source_key;A.wave_region_index=index;A.wave_region_selection={[index]=true}
end
function UI.select_source_range(key,a,b)
 local data=key and A.source_cache[key] or nil;if not data or data.error then return end
 if b<a then a,b=b,a end
 local selected={};local first
 for i,r in ipairs(data.regions or {}) do
  if (r.finish or 0)>=a-1e-10 and (r.start or 0)<=b+1e-10 then selected[i]=true;first=first or i end
 end
 if first then A.wave_region_key=key;A.wave_region_index=first;A.wave_region_selection=selected else UI.clear_source_region_selection() end
end
function UI.delete_selected_source_region()
 if A.job or A.source_job then return false end
 local v=UI.waveform_item();if not v or not v.source_key or A.wave_region_key~=v.source_key then return false end
 local data=A.source_cache[v.source_key];if not data or data.error then return false end
 local indices=UI.source_selected_indices(data,v.source_key,A.wave_region_index);if #indices==0 then return false end
 local first=indices[1]
 for i=#indices,1,-1 do table.remove(data.regions,indices[i]) end
 A.wave_region_selection={}
 if #data.regions>0 then local nexti=min(first,#data.regions);A.wave_region_key=v.source_key;A.wave_region_index=nexti;A.wave_region_selection[nexti]=true
 else A.wave_region_key=nil;A.wave_region_index=nil end
 UI.source_regions_changed(v.source_key,'SOURCE検出区間を削除しました。');return true
end
function UI.source_wave_view_state(key,source_len)
 local view=A.source_wave_view
 if not view or view.key~=key then view={key=key,zoom=1,start=0};A.source_wave_view=view end
 view.zoom=clamp(finite(view.zoom) and view.zoom or 1,1,64)
 local span=source_len/view.zoom
 view.start=clamp(finite(view.start) and view.start or 0,0,max(0,source_len-span))
 return view,span
end
function UI.source_wave_reset_zoom(key)
 local g=A.source_wave_geom;if not g or (key and g.key~=key) then return end
 local view=A.source_wave_view;if not view or view.key~=g.key then return end
 view.zoom=1;view.start=0;A.source_wave_scroll_drag=nil
end
function UI.source_wave_zoom(wheel,px)
 local g=A.source_wave_geom;if not g or g.partial or g.source_len<=0 then return false end
 local view=A.source_wave_view;if not view or view.key~=g.key then return false end
 local old_zoom=view.zoom or 1;local factor=wheel>0 and 1.25 or .8;local new_zoom=clamp(old_zoom*factor,1,64)
 if abs(new_zoom-old_zoom)<1e-9 then return true end
 if new_zoom<1.000001 then new_zoom=1 end
 local frac=clamp((px-g.px)/max(1,g.pw),0,1);local old_span=g.view_span or g.source_len/old_zoom
 local anchor=(view.start or 0)+frac*old_span;local new_span=g.source_len/new_zoom
 view.zoom=new_zoom;view.start=clamp(anchor-frac*new_span,0,max(0,g.source_len-new_span))
 return true
end
function UI.source_wave_scroll(wheel)
 local g=A.source_wave_geom;if not g or g.partial or (g.zoom or 1)<=1.000001 then return false end
 local view=A.source_wave_view;if not view or view.key~=g.key then return false end
 local span=g.view_span or g.source_len/(view.zoom or 1);local max_start=max(0,g.source_len-span)
 view.start=clamp((view.start or 0)+(wheel>0 and 1 or -1)*span*.12,0,max_start)
 return true
end
function UI.begin_source_wave_scroll_drag(px)
 local g=A.source_wave_geom;local bar=g and g.scroll
 if not g or not bar or (g.zoom or 1)<=1.000001 then return end
 A.source_wave_scroll_drag={key=g.key,start_px=px,start=bar.view_start or 0}
end
function UI.update_source_wave_scroll_drag(px)
 local d=A.source_wave_scroll_drag;local g=A.source_wave_geom;local bar=g and g.scroll
 if not d or not g or d.key~=g.key or not bar then return end
 local travel=max(1e-9,bar.w-bar.thumb_w);local max_start=max(0,g.source_len-g.view_span)
 A.source_wave_view.start=clamp(d.start+(px-d.start_px)/travel*max_start,0,max_start)
end
function UI.source_wave_time(g,px)
 local span=g.view_span or g.source_len;local first=g.view_start or 0
 return clamp(first+(px-g.px)/max(1,g.pw)*span,first,min(g.source_len,first+span))
end
function UI.source_region_at(px,py)
 local g=A.source_wave_geom;if not g or not g.editable or not g.data or not UI.point_inside(px,py,g.px,g.py,g.pw,g.ph) then return nil end
 local t=UI.source_wave_time(g,px)
 for i,r in ipairs(g.data.regions or {}) do if t>=(r.start or 0)-1e-10 and t<=(r.finish or 0)+1e-10 then return i end end
 return nil
end
function UI.source_add_overlaps(data,a,b)
 if not data then return true end
 if b<a then a,b=b,a end
 for _,r in ipairs(data.regions or {}) do
  if b>(r.start or 0)+1e-10 and a<(r.finish or 0)-1e-10 then return true end
 end
 return false
end
function UI.begin_source_wave_drag(kind,index,px)
 if A.job or A.source_job then return end
 local g=A.source_wave_geom;if not g or g.partial or not g.editable or not g.key or not g.data then return end
 local data=g.data;local regions=data.regions or {}
 local t=UI.source_wave_time(g,px)
 if kind=='select' or kind=='add' then
  A.source_wave_drag={kind=kind,key=g.key,start_px=px,start_t=t,current_t=t,moved=false,invalid=false}
  return
 end
 if not index or not regions[index] then return end
 if not UI.source_region_selected(g.key,index) then
  A.wave_region_key=g.key;A.wave_region_index=index;A.wave_region_selection={[index]=true}
 else A.wave_region_index=index end
 local indices=UI.source_selected_indices(data,g.key,index);local selected={};for _,i in ipairs(indices) do selected[i]=true end
 local snap,all={},{ }
 for i,r in ipairs(regions) do
  local a={start=r.start or 0,finish=r.finish or 0,anchor=finite(r.anchor) and r.anchor or ((r.start or 0)+(r.finish or 0))*.5,
   raw_start=r.raw_start,raw_finish=r.raw_finish}
  all[i]=a;if selected[i] then snap[i]=a end
 end
 A.source_wave_drag={kind=kind,index=index,key=g.key,start_px=px,start_t=t,current_t=t,moved=false,indices=indices,selected=selected,snap=snap,all=all}
end
function UI.update_source_wave_drag(px)
 local d,g=A.source_wave_drag,A.source_wave_geom;if not d or not g or d.key~=g.key or g.partial or not g.data then return end
 local data=g.data;local t=UI.source_wave_time(g,px);d.current_t=t
 local threshold=max(1/Core.SOURCE_SR,(g.view_span or g.source_len)/max(1,g.pw)*1.25)
 if not d.moved and abs(t-d.start_t)<threshold then return end
 d.moved=true
 if d.kind=='select' then return end
 if d.kind=='add' then
  local a,b=min(d.start_t,t),max(d.start_t,t);d.invalid=(b-a<1/Core.SOURCE_SR) or UI.source_add_overlaps(data,a,b);return
 end
 local primary=d.snap and d.snap[d.index];if not primary then return end
 local desired=t-d.start_t;local eps=1/Core.SOURCE_SR;local lo,hi=-math.huge,math.huge
 if d.kind=='move' then
  for _,i in ipairs(d.indices) do
   local q=d.snap[i];local prev=d.all[i-1];local nxt=d.all[i+1]
   if not d.selected[i-1] then lo=max(lo,(prev and prev.finish+eps or 0)-q.start) end
   if not d.selected[i+1] then hi=min(hi,(nxt and nxt.start-eps or g.source_len)-q.finish) end
  end
 elseif d.kind=='left' then
  for _,i in ipairs(d.indices) do
   local q=d.snap[i];local prev=d.all[i-1]
   lo=max(lo,(prev and prev.finish+eps or 0)-q.start)
   hi=min(hi,min(q.finish-eps,q.anchor)-q.start)
  end
 elseif d.kind=='right' then
  for _,i in ipairs(d.indices) do
   local q=d.snap[i];local nxt=d.all[i+1]
   lo=max(lo,max(q.start+eps,q.anchor)-q.finish)
   hi=min(hi,(nxt and nxt.start-eps or g.source_len)-q.finish)
  end
 elseif d.kind=='anchor' then
  for _,i in ipairs(d.indices) do local q=d.snap[i];lo=max(lo,q.start-q.anchor);hi=min(hi,q.finish-q.anchor) end
 end
 local delta=clamp(desired,lo,hi)
 for _,i in ipairs(d.indices) do
  local q=d.snap[i];local r=data.regions[i]
  if r then
   if d.kind=='move' then
    r.start=q.start+delta;r.finish=q.finish+delta;r.anchor=q.anchor+delta
    r.raw_start=finite(q.raw_start) and q.raw_start+delta or r.start;r.raw_finish=finite(q.raw_finish) and q.raw_finish+delta or r.finish
   elseif d.kind=='left' then r.start=q.start+delta;r.raw_start=r.start;r.anchor=q.anchor
   elseif d.kind=='right' then r.finish=q.finish+delta;r.raw_finish=r.finish;r.anchor=q.anchor
   elseif d.kind=='anchor' then r.anchor=q.anchor+delta end
  end
 end
 data.manual_regions=true
end
function UI.finish_source_wave_drag()
 local d=A.source_wave_drag;A.source_wave_drag=nil;if not d then return end
 local data=d.key and A.source_cache[d.key] or nil;if not data or data.error then return end
 if d.kind=='select' then
  if d.moved then UI.select_source_range(d.key,d.start_t,d.current_t) else UI.clear_source_region_selection() end
  return
 end
 if d.kind=='add' then
  if not d.moved then return end
  local a,b=min(d.start_t,d.current_t),max(d.start_t,d.current_t);local eps=1/Core.SOURCE_SR
  if d.invalid or b-a<eps or UI.source_add_overlaps(data,a,b) then UI.notice('既存区間と重なるため追加しませんでした。',true);return end
  local region={start=a,finish=b,raw_start=a,raw_finish=b,anchor=(a+b)*.5,anchor_score=-math.huge,peak_db=-240,loud=-240}
  local at=#data.regions+1;for i,r in ipairs(data.regions) do if a<(r.start or 0) then at=i;break end end
  table.insert(data.regions,at,region);A.wave_region_key=d.key;A.wave_region_index=at;A.wave_region_selection={[at]=true}
  UI.source_regions_changed(d.key,'SOURCE検出区間を追加しました。');return
 end
 if d.moved then UI.source_regions_changed(d.key,'SOURCE検出区間を調整しました。') end
end
function UI.reanalyze_source_wave(v)
 if A.job or A.source_job or not v or v.is_midi or not v.source_key then return end
 A.source_cache[v.source_key]=nil;UI.clear_source_region_selection();UI.source_wave_reset_zoom(v.source_key)
 for _,item in ipairs(A.items or {}) do if item.source_key==v.source_key then UI.source_status_from_cache(item) end end
 UI.rebuild_source_queue()
 local forced={v};for _,item in ipairs(A.source_queue or {}) do if item~=v and item.source_key~=v.source_key then forced[#forced+1]=item end end
 A.source_queue=forced;A.source_queue_i=1;A.source_queue_done=false;UI.source_queue_start_next();UI.notice('SOURCEを再解析しています。',false)
end
function UI.source_visible_regions(regions,first,last)
 local lo,hi=1,#regions
 while lo<=hi do
  local mid=(lo+hi)//2
  if (regions[mid].finish or 0)<first then lo=mid+1 else hi=mid-1 end
 end
 local start=lo;hi=#regions
 while lo<=hi do
  local mid=(lo+hi)//2
  if (regions[mid].start or 0)<=last then lo=mid+1 else hi=mid-1 end
 end
 return start,hi
end
function UI.draw_source_waveform()
 local x,y,w,h=WAVE_X,WAVE_Y,WAVE_W,WAVE_H
 UI.panel_frame(x,y,w,h)
 label('SOURCE ANALYSIS',x+13,y+7,9,C.muted,3,150,13,0,true)
 local v=UI.waveform_item()
 if not v then A.source_wave_geom=nil;return end
 label(v.name,x+145,y+4,12,C.text,1,w-470,20,0,true,true)
 if v.is_midi then
  right_label('MIDI',x+w-14,y+7,8,C.accent2,3,true)
  local px,py,pw,ph=x+15,y+31,w-30,104;gradient(px,py,pw,ph,C.field,C.panel,.96,.72);finish_corners(px,py,pw,ph,5,false,C.edge,.34)
  label('MIDIでは全体ピッチ・タイミング・音量のみ使用できます。',px+12,py+31,12,C.muted,1,pw-24,24,5,false)
  label('G.PITCH  /  TIME  /  VOL',px+12,py+59,10,C.accent2,3,pw-24,18,5,true)
  A.source_wave_geom=nil;register('source_wave',px,py,pw,ph,function()end,'MIDIアイテムはSOURCE解析の対象外です。',false);return
 end
 local data,partial=UI.source_wave_data(v)
 local count=v.source_candidate_count or 0
 local mode_name=v.source_origin=='track' and 'TRACK' or 'WAVE'
 right_label(partial and string.format('ANALYZING %d%%',floor((A.source_progress or 0)*100+.5)) or string.format('%s · VARIANTS %d',mode_name,count),x+w-14,y+7,8,partial and C.accent2 or C.muted,3,true)
 local px,py,pw,ph=x+15,y+31,w-30,104;local cy=py+ph*.52
 gradient(px,py,pw,ph,C.field,C.panel,.96,.72);finish_corners(px,py,pw,ph,5,false,C.edge,.34)
 line(px,cy,px+pw,cy,C.edge,.34)
 local source_len=max(1e-9,v.source_len or (data and data.source_len) or 0)
 local view,view_span=UI.source_wave_view_state(v.source_key,source_len);local view_start=view.start;local view_end=min(source_len,view_start+view_span)
 local function tx(t) return px+(t-view_start)/max(1e-12,view_span)*pw end
 local regions=data and data.regions or {}
 local ctx=not partial and v.source_context or nil
 local editable=not partial and data and not data.error and not A.job and not A.source_job
 A.source_wave_geom={key=v.source_key,data=data,partial=partial,editable=editable,px=px,py=py,pw=pw,ph=ph,source_len=source_len,view_start=view_start,view_span=view_span,view_end=view_end,zoom=view.zoom}
 gfx.wheelRegion(sx(px),sy(py),pw*scale,ph*scale)
 register('source_wave',px,py,pw,ph,function()end,'Ctrl＋ホイール：時間軸ズーム / Shift＋ホイール：左右スクロール',false)
 if A.wave_region_key~=v.source_key then UI.clear_source_region_selection()
 elseif A.wave_region_key then
  local cleaned={};for i,on in pairs(A.wave_region_selection or {}) do if on and regions[i] then cleaned[i]=true end end
  if next(cleaned)==nil and regions[A.wave_region_index or 0] then cleaned[A.wave_region_index]=true end
  A.wave_region_selection=cleaned
  if next(cleaned)==nil then UI.clear_source_region_selection()
  elseif not cleaned[A.wave_region_index or 0] then for i in pairs(cleaned) do A.wave_region_index=i;break end end
 end
 if partial and data and #regions>0 then local ok,res=pcall(Core.source_context,v,data);if ok and type(res)=='table' then ctx=res end end
 local region_first,region_last=UI.source_visible_regions(regions,view_start,view_end)
 for i=region_first,region_last do
  local r=regions[i]
  local ra,rb=tx(r.start or 0),tx(r.finish or 0);local a,b=max(px,ra),min(px+pw,rb);local selected=UI.source_region_selected(v.source_key,i)
  if b>a then
   rect(a,py,b-a,ph,selected and C.focus2 or C.accent,selected and .14 or ((ctx and i==ctx.index) and .17 or .085))
   local edge_col=selected and C.focus2 or C.edge2;local edge_alpha=selected and .92 or ((ctx and i==ctx.index) and .70 or .30)
   local function edge_handle(side,xx)
    if xx<px or xx>px+pw then return end
    local hot=editable and inside(xx-6,py,12,ph);local hover=animate('source_'..side..'_hover_'..tostring(v.source_key)..'_'..i,hot and 1 or 0)
    if hover>.01 then rect(xx-2-hover,py+1,4+hover*2,ph-2,C.focus2,.055+.085*hover) end
    line(xx,py,xx,py+ph,hover>.04 and C.focus2 or edge_col,max(edge_alpha,.30+.62*hover))
    if hover>.04 then line(xx-1-hover*.55,py+3,xx-1-hover*.55,py+ph-3,C.focus2,.22+.38*hover);line(xx+1+hover*.55,py+3,xx+1+hover*.55,py+ph-3,C.focus2,.22+.38*hover) end
    if editable then register('source_'..side..'_'..i,xx-6,py,12,ph,function()end,side=='left' and '区間開始をドラッグ。複数選択時は全開始点を相対移動' or '区間終了をドラッグ。複数選択時は全終了点を相対移動',true) end
   end
   edge_handle('left',ra);edge_handle('right',rb)
   register('source_region_'..i,a,py,max(1,b-a),ph,function() UI.select_source_region(v,i) end,'クリック：区間選択 / 内側ドラッグ：区間移動 / 右クリック：削除',editable)
  end
 end
 local preview=data and data.preview or nil;local norm=max((data and data.preview_max) or 0,1e-12)
 if preview then
  local n=Core.SOURCE_PREVIEW_BINS;local i0=max(1,floor(view_start/source_len*n)+1);local i1=min(n,ceil(view_end/source_len*n));local visible=max(1,i1-i0+1)
  local columns=min(420,max(1,floor(pw/2.5)));local step=max(1,ceil(visible/columns));local peaks=nil
  if not partial and data then
   local cache=data._blt_wave_draw_cache;local cache_key=tostring(preview)..'|'..i0..'|'..i1..'|'..step..'|'..tostring(norm)
   if cache and cache.key==cache_key then peaks=cache.peaks else
    peaks={}
    for i=i0,i1,step do local pk=0;for k=i,min(i1,i+step-1) do pk=max(pk,preview[k] or 0) end;peaks[#peaks+1]={i=i,amp=clamp(math.sqrt(pk/norm),0,1)} end
    data._blt_wave_draw_cache={key=cache_key,peaks=peaks}
   end
  end
  local function draw_peak(i,amp)
   if amp>0 then amp=amp*ph*.44;local tt=(i-.5)/n*source_len;local xx=tx(tt);if xx>=px and xx<=px+pw then line(xx,cy-amp,xx,cy+amp,C.accent2,.64) end end
  end
  if peaks then for _,q in ipairs(peaks) do draw_peak(q.i,q.amp) end else
   for i=i0,i1,step do local pk=0;for k=i,min(i1,i+step-1) do pk=max(pk,preview[k] or 0) end;draw_peak(i,clamp(math.sqrt(pk/norm),0,1)) end
  end
 end
 local drag=A.source_wave_drag
 if drag and drag.key==v.source_key and (drag.kind=='select' or drag.kind=='add') then
  local da,db=max(px,tx(min(drag.start_t,drag.current_t))),min(px+pw,tx(max(drag.start_t,drag.current_t)));local add=drag.kind=='add'
  local dc=add and (drag.invalid and C.warn or C.accent2) or C.focus2
  if db>da then rect(da,py,db-da,ph,dc,add and .10 or .075);line(da,py,da,py+ph,dc,.86);line(db,py,db,py+ph,dc,.86) end
  if add and db>da then local ax=(da+db)*.5;disc(ax,cy,2.5,dc,.95) end
 end
 for i=region_first,region_last do
  local r=regions[i]
  if finite(r.anchor) then
   local selected=UI.source_region_selected(v.source_key,i);local ax=tx(r.anchor)
   if ax>=px and ax<=px+pw then
    local anchor_hot=editable and inside(ax-7,py,14,ph)
    local anchor_hover=animate('source_anchor_hover_'..tostring(v.source_key)..'_'..i,anchor_hot and 1 or 0)
    local anchor_col=selected and C.lock2 or ((ctx and i==ctx.index) and C.lock2 or C.lock)
    if anchor_hover>.01 then disc(ax,cy,(selected and 4.7 or 4.1)+anchor_hover*1.7,C.lock2,.035+.075*anchor_hover) end
    line(ax,py+2-anchor_hover,ax,py+ph-2+anchor_hover,anchor_hover>.04 and C.lock2 or (selected and C.lock2 or C.lock),max((selected or (ctx and i==ctx.index)) and .92 or .67,.68+.30*anchor_hover))
    disc(ax,cy,(selected and 2.8 or 2.1)+anchor_hover*1.45,anchor_hover>.04 and C.lock2 or anchor_col,.92)
    if editable then register('source_anchor_'..i,ax-7,py,14,ph,function()end,'基準点をドラッグ。複数選択時は全基準点を相対移動',true) end
   end
  end
 end
 local rua,rub=tx(v.offset or 0),tx((v.offset or 0)+(v.len or 0)*(v.rate or 1));local ua,ub=max(px,rua),min(px+pw,rub)
 if ub>ua then
  rect(ua,py,ub-ua,ph,C.source_alt,.050);line(ua,py,ub,py,C.source_alt2,.94);line(ua,py+ph,ub,py+ph,C.source_alt2,.94)
  if rua>=px and rua<=px+pw then line(rua,py,rua,py+ph,C.source_alt,.88) end;if rub>=px and rub<=px+pw then line(rub,py,rub,py+ph,C.source_alt,.88) end
 end
 if partial then
  local pr=clamp(A.source_progress or 0,0,1);rect(px,py+ph-3,pw,3,C.ink,.75);if pr>0 then gradient(px,py+ph-3,pw*pr,3,C.accent,C.accent2,.80,.98) end
 elseif not data then
  label(not v.source_ready and 'SOURCE欄の「解析」を押すと素材解析を開始します。' or v.source_reason or '解析待ち',px,py+37,12,C.muted,1,pw,28,5,false)
 end
 local by,bh=y+141,22;local reset_x,reset_w=x+15,124;local re_w=88;local re_x=x+w-15-re_w
 local can_reset=(view.zoom or 1)>1.000001
 UI.small_button('source_zoom_reset','ズーム率リセット',reset_x,by,reset_w,bh,function() UI.source_wave_reset_zoom(v.source_key) end,'波形の時間軸ズームを全体表示へ戻します。',can_reset,true,false)
 local can_reanalyze=not partial and data and not data.error and not A.job and not A.source_job
 UI.small_button('source_reanalyze','再解析',re_x,by,re_w,bh,function() UI.reanalyze_source_wave(v) end,'手動編集したSOURCE区間を破棄し、素材全体を再解析します。',can_reanalyze,true,false)
 if can_reset then
  local sx,sw=reset_x+reset_w+18,re_x-(reset_x+reset_w+18)-18;local sy=by+8
  if sw>24 then
   rect(sx,sy,sw,6,C.field,.95);line(sx,sy+3,sx+sw,sy+3,C.edge2,.32)
   local thumb_w=max(20,sw/(view.zoom or 1));local max_start=max(1e-12,source_len-view_span);local thumb_x=sx+(sw-thumb_w)*clamp(view_start/max_start,0,1)
   rect(thumb_x,sy-2,thumb_w,10,C.accent,.16);finish_corners(thumb_x,sy-2,thumb_w,10,4,false,C.accent2,.72)
   A.source_wave_geom.scroll={x=sx,w=sw,thumb_x=thumb_x,thumb_w=thumb_w,view_start=view_start}
   register('source_scroll_thumb',thumb_x,sy-5,thumb_w,16,function()end,'ドラッグして時間を左右にスクロール',true)
  end
 end
end
function UI.draw_assignment_matrix()
 local x,y,w,h=MATRIX_X,MATRIX_Y,MATRIX_W,MATRIX_H;UI.panel_frame(x,y,w,h)
 local contentRight=x+w-MATRIX_SCROLL_W-8;local colsX=x+MATRIX_NAME_W
 local voiceW,sourceW=54,64;local featureX=colsX+voiceW;local cw=(contentRight-featureX-sourceW)/(#FEATURE_COLUMNS-1)
 local function checkbox_x(ci,c)return featureX+(ci-1)*cw+(c.key=='source'and sourceW-56 or(cw-16)/2)end
 for ci,c in ipairs(FEATURE_COLUMNS) do
  if c.lockable and A.apply.lock[c.key]then local cx=featureX+(ci-1)*cw;rect(cx,y+1,cw,h-2,C.lock,.035)end
 end
 label('TRACK / ITEM',x+13,y+2,9,C.accent2,3,MATRIX_NAME_W-24,12,0,true);label('トラック / アイテム名',x+13,y+14,8.5,C.muted,1,MATRIX_NAME_W-24,12,0,true)
 label('VOICE',colsX,y+2,9,C.accent2,3,voiceW,12,5,true);label('疑似発音数',colsX,y+14,8.5,C.muted,1,voiceW,12,5,true)
 for ci,c in ipairs(FEATURE_COLUMNS) do
  local cx=featureX+(ci-1)*cw;local locked=c.lockable and A.apply.lock[c.key]
  local width=c.key=='source'and sourceW or cw
  label(c.label,cx,y+2,9,locked and C.lock2 or C.accent2,3,width,12,5,true);label(c.sub,cx,y+14,9,locked and C.lock or C.muted,1,width,12,5,true)
 end
 local ay=y+MATRIX_HEADER_H
 gradient(x+8,ay,contentRight-x-8,MATRIX_ALL_H,C.accent3,C.panel2,.46,.84)
 rect(x+8,ay,4,MATRIX_ALL_H,C.accent2,.48);line(x+8,ay,contentRight,ay,C.accent2,.34);line(x+8,ay+MATRIX_ALL_H,contentRight,ay+MATRIX_ALL_H,C.edge2,.38)
 local column_state={};local global_all=true;local state_count=0
 for _,c in ipairs(FEATURE_COLUMNS) do local all,any,available=UI.all_feature_state(c.key);column_state[c.key]={all,any,available};if available>0 then state_count=state_count+available;global_all=global_all and all end end
 global_all=state_count>0 and global_all
 UI.global_apply_button(x+8,ay,MATRIX_NAME_W-8,MATRIX_ALL_H,global_all,#A.items>0 and not A.job)
 label('GLOBAL APPLY / 一括',x+32,ay,11,#A.items>0 and not A.job and C.text or C.disabled,1,MATRIX_NAME_W-42,MATRIX_ALL_H,4,true)
 register('global_apply_all',x+8,ay,MATRIX_NAME_W-8,MATRIX_ALL_H,function() UI.set_all_features(not global_all) end,'全項目をまとめてON/OFF',#A.items>0)
 UI.voice_global_control(colsX+2,ay+3,voiceW-4)
 for ci,c in ipairs(FEATURE_COLUMNS) do
  local cx=checkbox_x(ci,c);local st=column_state[c.key];local all,any,available=st[1],st[2],st[3]
  local hint=c.key=='source' and '使用可能な素材バリエーションがあるアイテムだけを一括ON/OFF' or 'この機能を使用できる選択アイテムだけを一括ON/OFF'
  UI.checkbox('all_'..c.key,all,cx,ay+6,function() UI.set_feature_all(c.key,not all) end,hint,available>0,nil,any and not all)
 end
 local listY=ay+MATRIX_ALL_H;local listH=MATRIX_VISIBLE*MATRIX_ROW_H;local maxscroll=max(0,#A.items-MATRIX_VISIBLE);A.item_scroll=clamp(A.item_scroll or 0,0,maxscroll)
 gfx.wheelRegion(sx(x),sy(listY),(contentRight-x)*scale,listH*scale)
 register('matrix_list',x,listY,contentRight-x,listH,function()end,'アイテム名：Ctrl/Shiftで複数選択 / ホイールでスクロール',true)
 for r=1,MATRIX_VISIBLE do
  local idx=A.item_scroll+r;local v=A.items[idx];local ry=listY+(r-1)*MATRIX_ROW_H
  if r%2==0 then rect(x+8,ry,contentRight-x-8,MATRIX_ROW_H,C.field,.20) end
  if v then
   local selected=A.matrix_selected[v.guid]==true
   if selected then rect(x+8,ry,contentRight-x-8,MATRIX_ROW_H,C.accent,.105);rect(x+8,ry,3,MATRIX_ROW_H,C.focus2,.72) end
   label(string.format('T%02d',floor((tonumber(v.tracknum) or 0)+.5)),x+15,ry+4,9,selected and C.focus2 or C.faint,3,30,20,4,true)
   if v._display_name_source~=v.name or v._display_name==nil then
    v._display_name_source=v.name;v._display_name=A.matrix_display_name(v.name)
   end
   label(v._display_name,x+48,ry+4,11,selected and C.text or C.muted,1,MATRIX_NAME_W-58,MATRIX_ROW_H-8,4,selected,true)
   register('rowname_'..v.guid,x,ry,contentRight-x,MATRIX_ROW_H,function() UI.select_matrix_item(idx,v.guid) end,'クリック選択 / Ctrl(Cmd)で追加・解除 / Shiftで範囲選択',not A.job)
   UI.voice_control(v,colsX+2,ry+3,voiceW-4)
   local row=A.apply.items[v.guid]
   for ci,c in ipairs(FEATURE_COLUMNS) do
    local cx=checkbox_x(ci,c);local available=UI.feature_available(v,c.key)
    local hint
    if v.is_midi and not available then hint='MIDIでは使用できません。'
    elseif v.is_midi and c.key=='volume' then hint='MIDIの音量はベロシティ倍率として適用します。'
    elseif v.is_midi and c.key=='pitch_global' then hint='MIDIの全体ピッチは半音単位へ丸めます。'
    elseif c.key=='source' then hint=v.source_ready and tostring(v.source_reason or '素材バリエーション') or '素材全体をラウドネス解析中…'
    else hint=selected and '選択中の全アイテムへ同じON/OFFを適用' or 'このアイテムへ適用' end
    local unscanned=c.key=='source' and not v.source_ready and available
    if unscanned then
     local text,tip,enabled=UI.source_analysis_action(v)
     UI.small_button('source_analyze_'..v.guid,text,cx,ry+4,51,20,function() UI.start_source_analysis(v) end,tip,enabled,true)
    else
     UI.checkbox('item_'..v.guid..'_'..c.key,row[c.key],cx,ry+6,function() UI.toggle_item_feature(v.guid,c.key) end,hint,available)
    end
    if c.key=='source' and not unscanned then
     local tag=not v.source_ready and '…' or tostring(v.source_candidate_count or 0)
     local bx,by,bw,bh=cx+19,ry+4,32,20;local switchable=UI.source_mode_switchable(v)
     local mode_hint=switchable and '候補数をクリック：同一波形 / 同一トラックを切替' or (v.source_origin=='track' and '同一トラック' or '同一波形')
     if v.source_origin=='track' then mode_hint=mode_hint..'\n同一トラック候補は選択アイテムより前に終了する音声アイテムだけです。' end
     register('source_count_'..v.guid,bx,by,bw,bh,function() UI.toggle_source_mode(v.guid) end,mode_hint,switchable)
     local from_track=v.source_origin=='track';local badge_on=available and row.source==true
     UI.source_badge('source_count_'..v.guid,tag,bx,by,bw,bh,from_track,badge_on,switchable)
    end
   end
  end
  line(x+8,ry+MATRIX_ROW_H,contentRight,ry+MATRIX_ROW_H,C.edge,.22)
 end
 A.scroll_hint_top=nil;A.scroll_hint_bottom=nil
 if maxscroll>0 then
  local tx=x+w-MATRIX_SCROLL_W-3;local ty=listY+3;local th=listH-6;local thumbH=max(28,th*MATRIX_VISIBLE/#A.items)
  local thumbY=ty+(th-thumbH)*(A.item_scroll/maxscroll)
  rect(tx,ty,MATRIX_SCROLL_W-3,th,C.field,.68);finish_corners(tx,ty,MATRIX_SCROLL_W-3,th,3,false,C.edge,.34)
  gradient(tx+1,thumbY,MATRIX_SCROLL_W-5,thumbH,C.edge2,C.accent3,.62,.78);finish_corners(tx+1,thumbY,MATRIX_SCROLL_W-5,thumbH,3,false,C.accent2,.46)
  A.scroll_geom={trackX=tx,trackY=ty,trackH=th,thumbY=thumbY,thumbH=thumbH,maxscroll=maxscroll}
  register('matrix_scroll_track',tx,ty,MATRIX_SCROLL_W-3,th,function()
   local g=A.scroll_geom;if not g then return end;local q=clamp((mouse_y-g.trackY-g.thumbH/2)/max(1,g.trackH-g.thumbH),0,1);A.item_scroll=floor(q*g.maxscroll+.5)
  end,'クリックでスクロール位置を移動',true)
  register('matrix_scroll_thumb',tx+1,thumbY,MATRIX_SCROLL_W-5,thumbH,function()end,'ドラッグしてスクロール',true)
  local hc=x+(contentRight-x)/2
  if A.item_scroll>0 then
   A.scroll_hint_top={cx=hc,y=listY+8,dir=-1}
   UI.draw_scroll_hint(hc,listY+8,-1)
  end
  if A.item_scroll<maxscroll then
   A.scroll_hint_bottom={cx=hc,y=listY+listH-8,dir=1}
   UI.draw_scroll_hint(hc,listY+listH-8,1)
  end
 else A.scroll_geom=nil end
 local ly=listY+listH
 gradient(x+8,ly,contentRight-x-8,MATRIX_LOCK_H,C.lock,C.field,.085,.88)
 rect(x+8,ly,4,MATRIX_LOCK_H,C.lock,.50);line(x+8,ly,contentRight,ly,C.lock,.52);line(x+8,ly+MATRIX_LOCK_H,contentRight,ly+MATRIX_LOCK_H,C.lock,.24)
 label('RANDOM SYNC / 共通化',x+32,ly,11,C.text,1,MATRIX_NAME_W-42,MATRIX_LOCK_H,4,true)
 label('—',colsX,ly+5,13,C.faint,3,voiceW,22,5,true)
 for ci,c in ipairs(FEATURE_COLUMNS) do
  local cx=checkbox_x(ci,c)
  if c.lockable then
   UI.checkbox('lock_'..c.key,A.apply.lock[c.key],cx,ly+7,function() A.apply.lock[c.key]=not A.apply.lock[c.key];UI.assignment_changed() end,'ON：この列のランダム値をVariation内で共通化',true,'sync')
  else
   label('—',cx-2,ly+5,13,C.faint,3,20,22,5,true)
  end
 end
 UI.column_locks(y,h,featureX,cw)
end
function UI.draw_modulation_controls(kind,depth_unit)
 A.draw_mod_preview(kind,30,296,230,78)
 UI.segment(kind..'_shape',1,'一定',30,382,72);UI.segment(kind..'_shape',2,'強く',110,382,72);UI.segment(kind..'_shape',3,'弱く',190,382,70)
 A.compact_field(kind..'_depth_lo','深さL',268,296,84,depth_unit);A.compact_field(kind..'_depth_hi','深さH',356,296,84,depth_unit)
 A.compact_field(kind..'_rate_lo','速度L',268,332,84,'Hz');A.compact_field(kind..'_rate_hi','速度H',356,332,84,'Hz')
 A.compact_field(kind..'_start_pct','START',268,368,84,'%');A.compact_field(kind..'_end_pct','END',356,368,84,'%')
end
function UI.draw()
 gfx.beginDraw()
 UI.update_pointer_geometry()
 reset_text_queue()
 variant_begin()
 widget_count=0;hover_hint='';gfx.clear=-1;gfx.set(C.bg[1],C.bg[2],C.bg[3],1);gfx.rect(0,0,gfx.w,gfx.h,1);local now=R.time_precise();frame_dt=visual_tail_active and max(0,min(.1,now-frame_clock))or 0;frame_clock=now
 rect(0,0,W,H+22,C.bg);gradient(0,0,W,78,C.bg2,C.bg,.22,0,true);disc(W-38,42,150,C.accent,.016);
 BLT.title('VARIANT FORGE','SOURCE VARIATIONS  素材から様々なバリエーションを生成',W);BLT.drawIcon()
 UI.panel_frame(20,90,860,54)
 label('選択',30,92,10,C.muted,1,50,14);label(tostring(#A.items),30,108,20,#A.items>0 and C.text or C.warn,3,50,28,4,true)
 UI.field('count','生成数',96,108,72,'組');UI.field('interval','間隔',180,108,84,'sec');UI.segment('interval_mode',1,'末尾→先頭',276,112,90);UI.segment('interval_mode',2,'先頭→先頭',374,112,90)
 UI.field('voice_fade_ms','停止フェード',476,108,88,'ms');UI.field('seed','乱数シード',576,108,126,'');UI.toggle('seed_lock','シード固定',714,110,154,true,11)
 UI.panel('全体ピッチ',20,152,170,100);UI.field('pitch_lo','下限',30,196,72,'st');UI.field('pitch_hi','上限',110,196,70,'st');UI.segment('pitch_length_mode',1,'尺固定',30,228,72);UI.segment('pitch_length_mode',2,'尺連動',110,228,70)
 UI.panel('音量',198,152,160,100);UI.field('volume_lo','下限',204,196,70,'dB');UI.field('volume_hi','上限',282,196,70,'dB')
 UI.panel('タイミング',366,152,170,100);UI.field('timing_lo','下限',376,196,72,'ms');UI.field('timing_hi','上限',456,196,70,'ms')
 UI.panel('PAN',544,152,150,100);UI.field('pan_lo','L',554,196,60,'%');UI.field('pan_hi','R',622,196,62,'%')
 UI.panel('素材バリエーション',702,152,178,100)
 label('選出',712,184,8.5,C.muted,1,20,22,4,true);UI.segment('source_order',1,'シャッフル',736,184,68,nil,9);UI.segment('source_order',2,'順次',810,184,60,nil,9)
 label('位置',712,220,8.5,C.muted,1,20,22,4,true);UI.segment('source_timing_mode',2,'区間相対',736,220,68,nil,9);UI.segment('source_timing_mode',1,'絶対',810,220,60,nil,9)

 UI.panel('変調コントロール',20,260,430,154,130)
 A.curve_tab('curve_tab',1,'PITCH CURVE',166,266,86);A.curve_tab('curve_tab',2,'VIBRATO',256,266,86);A.curve_tab('curve_tab',3,'TREMOLO',346,266,86)
 if S.curve_tab==1 then
  A.draw_pitch_curve_editor(30,296,230,104)
  if S.curve_guide_enabled then UI.small_button('curve_guide_clear','クリア',164,300,48,18,A.clear_pitch_curve_guide,'描いたガイドを消してRNDモードへ戻す',not A.job,false,false) end
  A.compact_field('curve_lo','下限',268,296,84,'st');A.compact_field('curve_hi','上限',356,296,84,'st')
  A.compact_field('curve_points','ポイント数',268,332,172,'',not S.curve_guide_enabled)
  UI.segment('curve_length_mode',1,'尺固定',268,368,84);UI.segment('curve_length_mode',2,'尺連動',356,368,84)
 elseif S.curve_tab==2 then UI.draw_modulation_controls('vibrato','st')
 elseif S.curve_tab==3 then UI.draw_modulation_controls('tremolo','dB')end

 UI.panel('テクスチャEQ',458,260,198,154)
 UI.small_button('texture_bank_capture','選択素材を解析',468,294,122,24,A.capture_texture_bank_from_selection,'REAPERで現在選択中の音声素材の周波数特性を解析・登録。最大10素材 / 各60秒',not A.job,true)
 UI.small_button('texture_bank_clear','クリア',596,294,50,24,A.clear_texture_bank,'登録済みTEXTURE参照素材をすべてクリア',not A.job and #(A.texture_bank or {})>0,true)
 local texture_n=#(A.texture_bank or {});local _,texture_i=A.texture_preview_current();local texture_label_w=texture_n>1 and 100 or 178
 label(A.texture_bank_label(),468,324,9.5,texture_n>0 and C.focus2 or C.muted,1,texture_label_w,18,0,true)
 register('texture_bank_info',468,322,texture_label_w,20,function()end,A.texture_bank_hint(),false)
 if texture_n>1 then
  UI.small_button('texture_prev','‹',572,322,18,20,function() A.texture_preview_step(-1) end,'前のTEXTURE参照素材',not A.job,false,false)
  label(string.format('%d/%d',texture_i,texture_n),594,325,8.5,C.muted,2,26,14,0,true)
  UI.small_button('texture_next','›',628,322,18,20,function() A.texture_preview_step(1) end,'次のTEXTURE参照素材',not A.job,false,false)
 end
 A.draw_texture_eq_preview(468,350,116,40)
 UI.field('texture_strength','強度',594,366,52,'%')
 label(texture_n>0 and 'PERSISTENCE FFT' or 'AUTO TEXTURE',468,398,8,C.muted,1,178,12)
 UI.panel('トーン補正',664,260,216,154);UI.field('tone_lo','強さ 下限',674,312,92,'dB');UI.field('tone_hi','上限',774,312,96,'dB');UI.toggle('tone_bright','BRIGHT',674,350,92,true,9.5);UI.toggle('tone_dark','DARK',774,350,96,true,9.5);UI.toggle('tone_forward','FORWARD',674,382,92,true,9);UI.toggle('tone_recessed','RECESSED',774,382,96,true,9)
 UI.draw_feature_flashes()
 UI.draw_source_waveform()
 A.scroll_hint_top=nil;A.scroll_hint_bottom=nil
 UI.draw_assignment_matrix()
 local valid,err=Core.validate(S);local auto_status=A.source_job and string.format('素材全体をラウドネス解析中… %d%%',floor((A.source_progress or 0)*100+.5)) or nil
 local status=A.status~='' and A.status or (not valid and err or A.selection_error or auto_status or (#A.items==0 and '音声またはMIDIアイテムを選択してください。' or ''))
 local enabled=A.job~=nil or A.source_execute_pending~=nil or (not A.source_job and #A.items>0 and valid~=nil and #A.items*S.count<=2000)
 local can_regen=UI.regeneration_ready();local pending_texture=not A.job and not A.source_job and A.pending_texture_count()or 0;local can_bake=pending_texture>0
 local lock_on=A.target_lock~=nil;local lock_enabled=not A.job and not A.source_job and not A.source_execute_pending and (lock_on or #A.items>0)
 UI.small_button('target_lock',lock_on and 'ロック解除' or '対象をロック',144,848,120,30,UI.toggle_target_lock,lock_on and '対象ロックを解除して、現在の選択へ戻します。' or '現在選択中のアイテムを対象として固定。選択が変わっても対象を維持します。',lock_enabled,true,false)
 local primary_text=A.job and '処理を中止' or (can_regen and 'バリエーションを再生成' or string.format('%d バリエーションを生成',S.count))
 UI.draw_primary_button('execute',primary_text,284,844,320,38,UI.primary_action,'Enter：生成。SOURCEの事前解析中は完了後に実行できます。',enabled)
 UI.small_button('bake_fx','FX FIX',624,848,80,30,A.bake_last_texture_fx,'直前生成のTEXTURE EQだけを音声へ焼き込み、FX負荷を軽減',can_bake,false,can_bake)
 BLT.footer(status,A.warning or not valid,W,H+22,Core.VERSION);flush_text_queue();UI.custom_titlebar();variant_finish()
end

function UI.render_full_frame()
 UI.draw();frame_cache_valid=true;gfx.update()
end
function UI.draw_scroll_hints_only()UI.render_full_frame()end

function UI.point_inside(px,py,x,y,w,h) return px>=x and px<=x+w and py>=y and py<=y+h end
function UI.widget_at(px,py)
 for i=widget_count,1,-1 do local w=widgets[i];if UI.point_inside(px,py,w.x,w.y,w.w,w.h) then return w end end
 return nil
end
function UI.hover_key_at(raw_x,raw_y)
 if not animations_active then return nil end
 local resize=UI.chrome_resize_hit(raw_x,raw_y)
 if resize then return 'chrome_resize_'..resize end
 if raw_y>=0 and raw_y<Chrome.title_h then
  local closeW,resetW=38,34;local closeX=gfx.w-closeW;local resetX=closeX-resetW
  if raw_x>=closeX then return 'chrome_close' end
  if raw_x>=resetX and raw_x<closeX then return 'chrome_reset' end
  return 'chrome_bar'
 end
 local hit=UI.widget_at(mouse_x,mouse_y)
 return hit and ('widget:'..tostring(hit.id)) or 'canvas'
end
function UI.apply_wheel(wheel,px,py,shift,ctrl,hit)
 if wheel==0 then return end
 local g=A.source_wave_geom
 if g and UI.point_inside(px,py,g.px,g.py,g.pw,g.ph) and not A.job then
  if ctrl and UI.source_wave_zoom(wheel,px) then return end
  if shift and UI.source_wave_scroll(wheel) then return end
 end
 local voice_guid=nil
 if hit and hit.enabled then
  voice_guid=hit.id:match('^voice_(.+)$') or hit.id:match('^voiceup_(.+)$') or hit.id:match('^voicedown_(.+)$')
 end
 if voice_guid and UI.commit_edit() then
  local row=A.apply.items[voice_guid]
  if row then
   local cur=max(0,floor(tonumber(row.voice_limit) or 0))
   UI.set_voice_limit(voice_guid,UI.voice_step_value(cur,wheel>0 and 1 or -1))
  end
  return
 end
 local listY=MATRIX_Y+MATRIX_HEADER_H+MATRIX_ALL_H;local listH=MATRIX_VISIBLE*MATRIX_ROW_H
 if not A.job and UI.point_inside(px,py,MATRIX_X,listY,MATRIX_W,listH) then
  A.item_scroll=clamp((A.item_scroll or 0)+(wheel>0 and -1 or 1),0,max(0,#A.items-MATRIX_VISIBLE));return
 end
 if hit and hit.enabled and hit.id:match('^field_') and UI.commit_edit() then
  local key=hit.id:sub(7);local r=Core.ranges[key]
  local step=A.setting_drag_step(key) or 1
  if shift and A.setting_allows_fine(key) then step=step*.1 end
  local raw=S[key]+(wheel>0 and step or -step);local n=UI.nearest_setting_value(key,raw)
  if n~=nil then if abs(n-raw)>1e-9 then field_flash[key]=R.time_precise() end;S[key]=n;UI.changed(key) end
 end
end
function UI.interact()
 if BLT.blocked() then down_last=(gfx.mouse_cap&1)~=0;right_down_last=(gfx.mouse_cap&2)~=0;pressed=nil;gfx.mouse_wheel=0;return end

 if Chrome.mouseActive then down_last=(gfx.mouse_cap&1)~=0;right_down_last=(gfx.mouse_cap&2)~=0;pressed=nil;A.scroll_drag=nil;A.source_wave_scroll_drag=nil;A.field_drag=nil;return end
 if not animations_active then
  local wheel=gfx.mouse_wheel or 0;gfx.mouse_wheel=0
   if wheel~=0 and (gfx.getchar(65536)&8)~=0 then
    local px,py=(gfx.mouse_x-ox)/scale,(gfx.mouse_y-oy)/scale
    UI.apply_wheel(wheel,px,py,(gfx.mouse_cap&8)~=0,(gfx.mouse_cap&4)~=0 or (gfx.mouse_cap&32)~=0,UI.widget_at(px,py))
   end
  down_last=false;right_down_last=false;pressed=nil;A.scroll_drag=nil;A.source_wave_scroll_drag=nil;A.curve_drag=nil;A.field_drag=nil;return
 end
 local hit=UI.widget_at(mouse_x,mouse_y)
 if A.job then
  local down=(gfx.mouse_cap&1)~=0;gfx.mouse_wheel=0
  if down and not down_last then pressed=hit and hit.id=='execute' and 'execute' or nil end
  if not down and down_last then if pressed=='execute' and hit and hit.id=='execute' then UI.cancel_job() end;pressed=nil end
  down_last=down;right_down_last=(gfx.mouse_cap&2)~=0;return
 end
 local wheel=gfx.mouse_wheel or 0;gfx.mouse_wheel=0;UI.apply_wheel(wheel,mouse_x,mouse_y,(gfx.mouse_cap&8)~=0,(gfx.mouse_cap&4)~=0 or (gfx.mouse_cap&32)~=0,hit)
 local down=(gfx.mouse_cap&1)~=0;local rdown=(gfx.mouse_cap&2)~=0
 if rdown and not right_down_last then
  local ri=UI.source_region_at(mouse_x,mouse_y)
  if ri then
   local v=UI.waveform_item();if v and v.source_key then if not UI.source_region_selected(v.source_key,ri) then UI.select_source_region(v,ri) end;UI.delete_selected_source_region() end
  end
 end
 if down and not down_last then
  pressed=hit and hit.id or nil;pressed_mods=gfx.mouse_cap&60
  if hit and hit.id=='matrix_scroll_thumb' and A.scroll_geom then A.scroll_drag={startY=mouse_y,startScroll=A.item_scroll} end
  if hit and hit.id=='source_scroll_thumb' then UI.begin_source_wave_scroll_drag(mouse_x) end
  if hit and hit.enabled and hit.id:match('^source_left_%d+$') then UI.begin_source_wave_drag('left',tonumber(hit.id:match('(%d+)$')),mouse_x)
  elseif hit and hit.enabled and hit.id:match('^source_right_%d+$') then UI.begin_source_wave_drag('right',tonumber(hit.id:match('(%d+)$')),mouse_x)
  elseif hit and hit.enabled and hit.id:match('^source_anchor_%d+$') then UI.begin_source_wave_drag('anchor',tonumber(hit.id:match('(%d+)$')),mouse_x)
  elseif hit and hit.enabled and hit.id:match('^source_region_%d+$') then UI.begin_source_wave_drag('move',tonumber(hit.id:match('(%d+)$')),mouse_x)
  elseif hit and hit.id=='source_wave' and A.source_wave_geom and A.source_wave_geom.editable then
   UI.begin_source_wave_drag((gfx.mouse_cap&16)~=0 and 'add' or 'select',nil,mouse_x)
  end
  if hit and hit.id=='pitch_curve_graph' and A.curve_graph_geom then
   local mods=gfx.mouse_cap&60;local alt=(mods&16)~=0;local ctrl=(mods&4)~=0 or (mods&32)~=0
   local pi,pts,pending=A.pitch_curve_point_at(mouse_x,mouse_y)
   if ctrl and pi then
    A.delete_pitch_curve_point(pi,pts,pending);A.curve_drag={mode='action',moved=true}
   elseif alt then
    A.add_pitch_curve_point(mouse_x,mouse_y);A.curve_drag={mode='action',moved=true}
   elseif pi then
    A.begin_pitch_curve_move(pi,pts,pending,mouse_x,mouse_y)
   else
    A.update_pitch_curve_guide(mouse_x,mouse_y,true)
   end
  end
  if hit and hit.enabled and hit.id:match('^field_') and UI.commit_edit() then
   local key=hit.id:sub(7);if Core.ranges[key] then A.field_drag={key=key,start_y=mouse_y,start_value=S[key],moved=false,clipped=false} end
  elseif hit and hit.enabled and hit.id:match('^voice_') and UI.commit_edit() then
   local guid=hit.id:sub(7);local row=A.apply.items[guid]
   if row then A.field_drag={kind='voice',guid=guid,start_y=mouse_y,start_value=max(0,floor(tonumber(row.voice_limit) or 0)),moved=false,clipped=false} end
  end
 end
 if down and A.scroll_drag and A.scroll_geom then
  local g=A.scroll_geom;local span=max(1,g.trackH-g.thumbH);local delta=(mouse_y-A.scroll_drag.startY)/span*g.maxscroll
  A.item_scroll=clamp(floor(A.scroll_drag.startScroll+delta+.5),0,g.maxscroll)
 end
 if down and A.source_wave_scroll_drag then UI.update_source_wave_scroll_drag(mouse_x) end
 if down and A.curve_drag and A.curve_graph_geom then A.update_pitch_curve_guide(mouse_x,mouse_y,false) end
 if down and A.source_wave_drag then UI.update_source_wave_drag(mouse_x) end
 if down and A.field_drag then A.update_field_drag(mouse_y,(gfx.mouse_cap&8)~=0) end
 if not down and down_last then
  local curve_was_drag=A.curve_drag and A.curve_drag.moved
  if curve_was_drag then A.finish_pitch_curve_guide() end
  local source_was_drag=A.source_wave_drag and A.source_wave_drag.moved;if A.source_wave_drag then UI.finish_source_wave_drag() end
  local field_was_drag=A.field_drag and A.field_drag.moved;local wave_scroll_was_drag=A.source_wave_scroll_drag~=nil;local was_drag=A.scroll_drag~=nil or wave_scroll_was_drag or curve_was_drag or source_was_drag or field_was_drag
  A.scroll_drag=nil;A.source_wave_scroll_drag=nil;A.curve_drag=nil;A.field_drag=nil;click_mods=pressed_mods
  if not was_drag then
   if hit and hit.enabled and pressed==hit.id then if UI.commit_edit() then hit.fn() end
   elseif edit then UI.commit_edit() end
  end
  pressed=nil;pressed_mods=0;click_mods=0
 end
 down_last=down;right_down_last=rdown
end
function UI.keypress(k)
 k=BLT.key(k);if k==0 then return end
 if k==32 and not edit and not A.job and not A.source_job and not A.source_execute_pending then R.Main_OnCommand(40044,0);return end

 if k==27 then if edit then edit=nil elseif A.job then UI.cancel_job() elseif A.source_job then local restore=A.source_execute_pending and A.source_execute_pending.restore_selection;UI.stop_source_job();A.source_execute_pending=nil;A.source_queue={};A.source_queue_i=1;UI.restore_item_selection(A.project,restore,true);UI.notice('素材の事前解析を中止しました。') else A.closing=true end;return end;if A.job then if k==13 then UI.cancel_job() end;return end
 if k==6579564 and not edit then if UI.delete_selected_source_region() then return end end
 if k==13 then if edit then UI.commit_edit() else UI.primary_action() end;return end;if not edit then return end
 if k==9 then UI.commit_edit() elseif k==1 then edit.selected=true elseif k==8 or k==6579564 then edit.text=edit.selected and '' or edit.text:sub(1,-2);edit.selected=false
 elseif k>=48 and k<=57 or k==45 or k==46 then local c=string.char(k);if edit.selected then edit.text=c elseif #edit.text<14 then edit.text=edit.text..c end;edit.selected=false end
end
function UI.close()
 local ok,err=xpcall(function()
 if A.closed then return end;gfx.release();if A.job then UI.cancel_job() end;A.closed=true;A.job=nil;local restore=A.source_execute_pending and A.source_execute_pending.restore_selection;A.source_execute_pending=nil;UI.stop_source_job();UI.restore_item_selection(A.project,restore,false)
 UI.retry_stale_temp_items(true)
 UI.retry_pending_bake_deletes(true);Core.save_pending_bake_deletes(A.pending_bake_delete)
 Core.clear_temp_heartbeat()
 UI.flush_persist(true);local _,x,y,w,h=gfx.dock(-1,0,0,0,0)
 for key,v in pairs({window_x=x,window_y=y,window_w=w,window_h=h}) do if finite(v) then BLT.store(Core.SECTION,key,tostring(floor(v+.5)),true) end end;UI.clear_chrome_tooltip();UI.titlebar_cleanup();gfx.quit()
 end,debug.traceback)
 if not ok then
  A.closed=true
  pcall(gfx.quit)
  if R.TrackCtl_SetToolTip then pcall(R.TrackCtl_SetToolTip,'',0,0,true) end
  BLT.logError(err)
 end
end
function BLT.emptyTexturePreset()
 local v={format=1,count=0,refs={}}
 for i=1,10 do v.refs[i]={name='',data=''} end
 return v
end
function BLT.captureTexture()
 local bank=A.texture_bank
 if BLT.texturePresetBank==bank and BLT.texturePresetCache then return BLT.texturePresetCache end
 local v=BLT.emptyTexturePreset();v.count=#(bank or {})
 for i,entry in ipairs(bank or {}) do
  local parts={};local spec=entry.spectrum
  for j=1,Core.TEXTURE_SPECTRUM_BINS do parts[j]=string.pack('<dd',spec.db[j],spec.persistence[j]) end
  local name=BLT.cleanText(entry.name or ('TEXTURE '..i))
  while #name>512 do name=name:sub(1,(utf8.offset(name,-1) or #name)-1) end
  v.refs[i]={name=name,data=(table.concat(parts):gsub('.',function(c)return string.format('%02x',c:byte())end))}
 end
 BLT.texturePresetBank=bank;BLT.texturePresetCache=v;return v
end
function BLT.decodeTexture(v)
 if type(v)~='table' or v.format~=1 or type(v.count)~='number' or v.count%1~=0 or v.count<0 or v.count>10 or type(v.refs)~='table' or #v.refs~=10 then return end
 local bank={};local bins=Core.TEXTURE_SPECTRUM_BINS
 for i,ref in ipairs(v.refs) do
  if type(ref.name)~='string' or #ref.name>512 or not utf8.len(ref.name) or type(ref.data)~='string' then return end
  if i>v.count then if ref.name~='' or ref.data~='' then return end
  else
   if #ref.data~=bins*32 or ref.data:find('[^0-9a-f]') then return end
   local bytes=ref.data:gsub('..',function(pair)return string.char(tonumber(pair,16))end)
   local spec={freq={},db={},persistence={}};local pos=1
   for j=1,bins do
    local db,persist;db,persist,pos=string.unpack('<dd',bytes,pos)
    if not finite(db) or db< -120 or db>0 or not finite(persist) or persist<0 or persist>1 then return end
    spec.db[j]=db;spec.persistence[j]=persist
    spec.freq[j]=Core.TEXTURE_FREQ_MIN*math.exp((j-1)/max(1,bins-1)*math.log(Core.TEXTURE_FREQ_MAX/Core.TEXTURE_FREQ_MIN))
   end
   bank[i]={name=ref.name,spectrum=spec}
  end
 end
 return bank
end
function BLT.restoreTexture(v)
 local bank=assert(BLT.decodeTexture(v),'Invalid texture reference data')
 A.texture_bank=bank;A.texture_preview_index=1;A.texture_draw_cache=nil
 BLT.texturePresetBank=bank;BLT.texturePresetCache=BLT.copy(v)
end

BLT.variantDefaults={settings=BLT.copy(Core.defaults),locks={},texture=BLT.emptyTexturePreset()};for _,k in ipairs(Core.FEATURES) do BLT.variantDefaults.locks[k]=false end;function BLT.captureVariant() BLT.variantView=BLT.variantView or {};BLT.variantView.settings=S;BLT.variantView.locks=A.apply.lock;BLT.variantView.texture=BLT.captureTexture();return BLT.variantView end
Chrome.titleH=Chrome.title_h;Chrome.titleText=Chrome.title_text or "V A R I A N T   F O R G E";Chrome.windowTitle=Chrome.title
local panel_options={glow=false,panel=true}
local function panel_frame(x,y,w,h)
 panel_options.palette=C;VariantUI:frame(x/density,y/density,w/density,h/density,panel_options)
end
UI.panel_frame=panel_frame
function UI.small_button(id,text,x,y,w,h,fn,hint,enabled,strong_edge,pulse)
 enabled=enabled~=false
 local opt=variant_options(id)
 opt.enabled,opt.size,opt.bold=enabled,(h<22 and 10 or 12)/density,true
 opt.labelInset=6/density
 if id=='target_lock'then
  opt.showState,opt.ledScale=false,h/(44*density)
  VariantUI:gold(id,Language.text(text),A.target_lock~=nil,x/density,y/density,w/density,h/density,opt)
 else
  opt.variant=(id=='texture_bank_clear'or id=='curve_guide_clear')and 'clear'or nil
  opt.attention=pulse==true
  VariantUI:button(id,Language.text(text),x/density,y/density,w/density,h/density,opt)
 end
 register(id,x,y,w,h,fn,hint,enabled)
end
function UI.draw_primary_button(id,text,x,y,w,h,fn,hint,enabled)
 enabled=enabled~=false
 local cancelling=A.job~=nil or A.source_execute_pending~=nil
 if cancelling then text='処理を中止';enabled=true elseif A.source_job then text='素材を解析中...'end
 local opt=variant_options(id)
 opt.enabled,opt.busy=enabled,A.job~=nil or A.source_job~=nil
 opt.cancelable,opt.autoComplete,opt.finishWhenDisabled=true,false,true
 opt.progress=A.source_job and A.source_progress or A.job and A.progress or 0
 opt.caption=cancelling and 'CANCEL'or A.source_job and 'SOURCE ANALYSIS'or 'EXECUTE'
 opt.captionY,opt.captionHeight,opt.captionSize=3/density,12/density,8/density
 opt.labelY,opt.labelHeight,opt.size=11/density,24/density,15/density
 VariantUI:execute(id,Language.message(text),x/density,y/density,w/density,h/density,opt)
 register(id,x,y,w,h,fn,hint,enabled)
end
local function field_frame(id,x,y,w,h,enabled,active,flash)
 local s=VariantUI:state(id)
 s.variantSeen=VariantUI.frameSerial
 if s.variantRow==nil then s.variantRow=row_control(id)end
 if flash then s.flash=flash end
 VariantUI:fieldFrame(id,x/density,y/density,w/density,h/density,enabled,active)
end
UI.field_frame=field_frame
local function draw_field(key,title,x,y,w,unit,enabled,compact)
 enabled=enabled~=false and not A.job
 local h=28;local active=edit and edit.key==key
 field_frame('field_'..key,x,y,w,h,enabled,active,field_flash[key])
 local t=active and edit.text or fmt(S[key]);local size=13
 local unit_size=compact and 8.5 or 8
 local uw=unit and unit~=''and measure(unit,unit_size,3,false)+(compact and 7 or 4)or 0
 local title_w=compact and min(w*.55,measure(title,9,1,true)+8,max(0,w-uw-38))or 0
 local inset=compact and max(5,title_w)or 5
 if compact then label(title,x+4,y,9,enabled and C.muted or C.disabled,1,max(0,title_w-4),h,4,true)
 else label(title,x,y-18,11,enabled and C.muted or C.disabled,1,w,17)end
 if active and edit.selected then rect(x+max(5,title_w),y+5,max(5,w-title_w-uw-12),h-10,C.focus2,.85)end
 label(t,x+inset,y,size,active and edit.selected and C.ink or enabled and C.text or C.disabled,3,w-inset-uw-(compact and 6 or 4),h,6,true)
 if uw>0 then label(unit,x+w-uw,y,unit_size,enabled and C.muted or C.disabled,3,uw-3,h,6)end
 local hint=title..'：クリック入力 / 上下ドラッグ / ホイール変更'
 if A.setting_allows_fine and A.setting_allows_fine(key)then hint=hint..' / Shiftで微調整'end
 gfx.wheelRegion(sx(x),sy(y),w*scale,h*scale)
 register('field_'..key,x,y,w,h,function()begin_field_edit(key,title)end,hint,enabled)
end
function UI.field(key,title,x,y,w,unit,enabled)draw_field(key,title,x,y,w,unit,enabled,false)end
function A.compact_field(key,title,x,y,w,unit,enabled)draw_field(key,title,x,y,w,unit,enabled,true)end
function UI.toggle(key,text,x,y,w,enabled,size)
 enabled=enabled~=false and not A.job
 local id='toggle_'..key;local opt=variant_options(id)
 opt.background,opt.showState,opt.bold=false,false,true
 opt.switchScale,opt.labelOffset,opt.size=24/(44*density),34/density,(size or 13)/density
 local _,_,hitWidth=VariantUI:toggle(id,Language.text(text),S[key],x/density,y/density,w/density,24/density,enabled,opt)
 register(id,x,y,hitWidth*density,24,function()S[key]=not S[key];UI.changed(key)end,text,enabled)
end
local function segment(id,key,value,text,x,y,w,size,led,enabled)
 enabled=enabled~=false and not A.job;local opt=variant_options(id)
 opt.enabled,opt.selected,opt.led=enabled,S[key]==value,led
 opt.ledScale,opt.size,opt.bold=22/(44*density),size/density,true
 opt.labelInset=6/density
 VariantUI:button(id,Language.text(text),x/density,y/density,w/density,22/density,opt)
 register(id,x,y,w,22,function()S[key]=value;UI.changed(key)end,text,enabled)
end
function UI.segment(key,value,text,x,y,w,enabled,size)
 segment(key..value,key,value,text,x,y,w,size or 10,'left',enabled)
end
function A.curve_tab(key,value,text,x,y,w)segment('curve_tab_'..value,key,value,text,x,y,w,9,'top')end
function UI.panel(title,x,y,w,h,title_w)
 panel_frame(x,y,w,h)
 label(title,x+10,y+3,15,C.text,1,title_w or w-20,22,0,true)
end
function UI.checkbox(id,state,x,y,fn,hint,enabled,theme,mixed)
 enabled=enabled~=false and not A.job
 local sync=theme=='sync';local P=sync and (VariantUI.themeTones and VariantUI.themeTones.gold or VariantUI.tones.gold)or C
 local _,hot,held,s=VariantUI:interaction(id,x/density,y/density,16/density,16/density,enabled)
 local frame=s.frame or {};s.frame=frame
 frame.palette,frame.hot,frame.selected,frame.disabled,frame.pressed=P,hot and .7 or s.hover,state,not enabled,held
 frame.glow=false
 VariantUI:frame(x/density,y/density,16/density,16/density,frame)
 local ink=not enabled and C.disabled or state and (P.ice or C.ice)or C.muted
 if state then
  line(x+4,y+8,x+7,y+11,ink,enabled and 1 or .35)
  line(x+7,y+11,x+12,y+4,ink,enabled and 1 or .35)
 elseif mixed then line(x+4,y+8,x+12,y+8,ink,enabled and .9 or .3)end
 register(id,x,y,16,16,fn,hint,enabled)
end
local column_options={fill=0,alpha=.43}
function UI.column_locks(y,h,featureX,cw)
 for i,c in ipairs(FEATURE_COLUMNS)do
  if c.lockable then
   local cx=featureX+(i-1)*cw
   VariantUI:lockFrame('column_'..c.key,A.apply.lock[c.key],cx/density,(y+1)/density,cw/density,(h-2)/density,column_options)
  end
 end
end
local function arrow_button(id,x,y,w,h,enabled)
 local opt=variant_options(id);opt.enabled,opt.labelInset=enabled,0
 VariantUI:button(id,'',x/density,y/density,w/density,h/density,opt)
end
function UI.voice_arrows(x,y,w,h,enabled,up,down)
 local half=h/2
 arrow_button(up,x,y,w,half,enabled);arrow_button(down,x,y+half,w,half,enabled)
 local c=enabled and C.muted or C.disabled
 color(c,enabled and .85 or .35)
 gfx.triangle(sx(x+5),sy(y+7),sx(x+w-5),sy(y+7),sx(x+w/2),sy(y+3))
 gfx.triangle(sx(x+5),sy(y+half+4),sx(x+w-5),sy(y+half+4),sx(x+w/2),sy(y+h-3))
end
local track_palette={}
local badge_led={{},{},{},{}}
function UI.source_badge(id,text,x,y,w,h,track,selected,enabled)
 local _,_,held,s=VariantUI:interaction(id,x/density,y/density,w/density,h/density,enabled)
 local frame=s.frame or {};s.frame=frame
 track_palette.field,track_palette.edge,track_palette.panel,track_palette.text=C.field,C.edge,C.panel,C.text
 track_palette.accent,track_palette.ice=C.source_alt,C.source_alt2
 frame.palette,frame.hot,frame.selected,frame.pressed=track and track_palette or C,s.hover,selected,held
 frame.disabled,frame.glow=false,false
 VariantUI:frame(x/density,y/density,w/density,h/density,frame)
 local cut=min(10,floor(h/density*.21))*density
 badge_led[1][1],badge_led[1][2]=sx(x),sy(y)
 badge_led[2][1],badge_led[2][2]=sx(x+cut),sy(y)
 badge_led[3][1],badge_led[3][2]=sx(x+cut),sy(y+h-density)
 badge_led[4][1],badge_led[4][2]=sx(x),sy(y+h-density-cut)
 color(track and C.source_alt or C.accent,selected and 1 or .40);gfx.polygon(badge_led)
 label(text,x+cut,y,9,selected and (track and C.source_alt2 or C.ice)or C.faint,3,w-cut,h,5,true)
end
function UI.global_apply_button(x,y,w,h,selected,enabled)
 local opt=variant_options('global_apply_all')
 opt.enabled,opt.selected,opt.led=enabled,selected,'left'
 opt.ledScale=h/(44*density)
 VariantUI:button('global_apply_all','',x/density,y/density,w/density,h/density,opt)
end
function BLT.drawIcon()
 flush_text_queue()
 VariantIcon:draw(sx(W-102),sy(27),scale*.78)
end

Media.state=A;Media.onchange=function() if BLT.host and BLT.host.wake then BLT.host.wake() end end
BLT.attach({
 R=R,C=C,Chrome=Chrome,Chameleon=Chameleon,section=Core.SECTION,faces=fonts,font=font,
 geometry=function() return scale,ox,oy end,active=function() local f=gfx.getchar(65536);return (f&1)==0 or (f&2)~=0 end,
 wake=function() A.content_dirty=true;redraw_dirty=true;next_draw_time=0;wake_visuals() end,
 defaults=BLT.variantDefaults,capture=function() return BLT.captureVariant() end,
 valid=function(v) return Core.validate(v.settings)~=nil and BLT.decodeTexture(v.texture)~=nil end,apply=function(v) for k,x in pairs(v.settings) do S[k]=x end;A.apply.lock=v.locks;BLT.restoreTexture(v.texture);UI.changed();UI.persist_now() end,
 undoRefresh=function() UI.refresh() end,
 busy=function() return A.job~=nil or A.source_job~=nil end,commit=function() return UI.commit_edit() end,
 cancelEdit=function() edit=nil;A.field_drag=nil;A.curve_drag=nil end,editing=function() return edit~=nil end,
 modal=function() return false end,
 handle=UI.gfx_window_handle,resizeHit=function(x,y) if y<26 and x>=gfx.w-234 then return nil end;return UI.chrome_resize_hit(x,y) end,
 cursor=UI.set_resize_cursor,beginResize=UI.begin_window_resize,resize=UI.update_window_resize,

})
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
  return k==27 or ((cap&24)==0 and (k==26 or (cap&4)~=0 and (k==90 or k==122))) or (k==13 or k==32 or k==6579564)
 end
})

do
 local chrome_ok,chrome_err=UI.titlebar_api_ready();if not chrome_ok then Language.mb(BLT.publicError(chrome_err),'BLT Variant Forge | エラー',0);return end
 local wx,wy=tonumber(R.GetExtState(Core.SECTION,'window_x')),tonumber(R.GetExtState(Core.SECTION,'window_y'))
 local ww,wh=tonumber(R.GetExtState(Core.SECTION,'window_w')),tonumber(R.GetExtState(Core.SECTION,'window_h'))
 if R.GetExtState(Core.SECTION,'window_layout')~='compact1'then
  if finite(ww)then ww=floor(ww*900/1180+.5)end
  if finite(wh)then wh=floor(wh*910/1070+.5)end
  BLT.store(Core.SECTION,'window_layout','compact1',true)
 end
 ww=finite(ww) and clamp(ww,780,2100) or W;wh=finite(wh) and clamp(wh,800,1900) or H+Chrome.title_h
gfx.ext_retina=1;if finite(wx) and finite(wy) then gfx.init(Chrome.title,ww,wh,0,wx,wy) else gfx.init(Chrome.title,ww,wh,0) end
 if Chameleon.enabled then Chameleon.refresh(true) end
 R.atexit(UI.close)
end
function UI.loop()
 local ok,err=xpcall(function()
 local now=R.time_precise();BLT.tick(now)

 if A.closing then A.closing=true;return end
 local k=BLT.key(gfx.getchar());if k<0 then A.closing=true;return end
    Chameleon.tick(now)
  local flags=gfx.getchar(65536);local activation_down=(gfx.mouse_cap&1)~=0
  local activating=UI.activation_press(activation_down)
  local input_active=(flags&1)==0 or ((flags&2)~=0 and (flags&4)~=0) or activating
  if last_input_active==nil or input_active~=last_input_active then
   last_input_active=input_active;request_redraw(now,.28)
  end
  animations_active=input_active

  local key_activity=false;local n=0
  while k>0 and n<32 do
   key_activity=true
   if animations_active then UI.keypress(k) end
   n=n+1;k=BLT.key(gfx.getchar())
  end
  if key_activity then wake_visuals(now,.40) end
  if A.closing then return end

  UI.flush_persist(false)
  UI.poll_target_lock(now)

  if Media.ready() and not A.job and not A.source_job and now>A.poll then
   A.poll=now+.35
   local project=R.EnumProjects(-1,'');local revision=R.GetProjectStateChangeCount(project);local selection_signature=Core.selection_signature(project)
   if project~=A.project or selection_signature~=A.selection_signature or revision~=A.revision then
    UI.refresh();request_redraw(now,.40)

   end
  end

  local had_job=A.job~=nil;local had_source=A.source_job~=nil
  local old_progress=A.progress;local old_source_progress=A.source_progress
  UI.work_step()
  if had_job or had_source or A.job or A.source_job or old_progress~=A.progress or old_source_progress~=A.source_progress then
   request_redraw(now,.20)
  end

  UI.update_pointer_geometry()
  local raw_x,raw_y,raw_cap=gfx.mouse_x,gfx.mouse_y,gfx.mouse_cap
  local raw_wheel=gfx.mouse_wheel or 0

  local pointer_pos_changed=raw_x~=last_raw_mouse_x or raw_y~=last_raw_mouse_y
  local cap_changed=raw_cap~=last_raw_mouse_cap
  local hover_key=UI.hover_key_at(raw_x,raw_y)
  local hover_changed=hover_key~=last_hover_key
  local pointer_changed=pointer_pos_changed or hover_changed or cap_changed or raw_wheel~=0

  if hover_changed then
   last_hover_key=hover_key;wake_visuals(now,.44)
  end
  if pointer_pos_changed then
   wake_visuals(now,.46)
  end
  if cap_changed or raw_wheel~=0 then
   next_draw_time=now -- Never defer app-bar press/release to the next animation frame.
   wake_visuals(now,.38)
  end
  last_raw_mouse_x,last_raw_mouse_y,last_raw_mouse_cap=raw_x,raw_y,raw_cap

  if gfx.w~=last_window_w or gfx.h~=last_window_h then
   last_window_w,last_window_h=gfx.w,gfx.h;wake_visuals(now,.45,.20)
  end

  local dragging=A.scroll_drag or A.curve_drag or A.source_wave_drag or A.field_drag or Chrome.drag or Chrome.resize or ((raw_cap or 0)&1)~=0
  if dragging then request_effect_activity(now,.12) end
  local hover_animating=animations_active and now<hover_anim_until
  local effects_were_active=effects_active
  effects_active=animations_active and (dragging or A.job~=nil or A.source_job~=nil or now<effect_activity_until)
  if effects_active and not effects_were_active then next_draw_time=0 end

  local flash_alive=false
  for key,t in pairs(field_flash) do if now-t<.9 then flash_alive=true else field_flash[key]=nil end end
  for key,t in pairs(voice_flash) do if now-t<.9 then flash_alive=true else voice_flash[key]=nil end end
  VariantIcon:tick(now,animations_active,dragging or A.job~=nil or A.source_job~=nil or pointer_changed or key_activity)
  local control_tail,control_motion=variant_animating(now)
  local particle_tail=VariantIcon:animating(now)or control_tail
  visual_tail_active=effects_active or hover_animating or particle_tail or flash_alive
  update_scroll_hint_motion(now,visual_tail_active)

  local frame_interval
  if dragging or control_motion then frame_interval=1/60
  elseif A.job or A.source_job then frame_interval=1/30
  elseif effects_active or particle_tail or flash_alive then frame_interval=1/30
  elseif hover_animating then frame_interval=1/20
  else frame_interval=nil end

  local frame_due
  if frame_interval then
   frame_due=now>=next_draw_time
  else
   frame_due=redraw_dirty
  end
  if frame_due then
   UI.render_full_frame();redraw_dirty=false
   next_draw_time=frame_interval and (now+frame_interval) or math.huge
   next_scroll_hint_time=now+SCROLL_HINT_INTERVAL
  elseif frame_interval==nil and scroll_motion_alive and frame_cache_valid and (A.scroll_hint_top or A.scroll_hint_bottom) and now>=next_scroll_hint_time then
   UI.draw_scroll_hints_only();next_scroll_hint_time=now+SCROLL_HINT_INTERVAL
  end

  UI.interact()

  if pointer_changed or key_activity or dragging then redraw_dirty=true end

  if Chrome.requestReset then Chrome.requestReset=false;UI.reset_window_size();request_redraw(now,.45) end
  if Chrome.requestClose then Chrome.requestClose=false;A.closing=true end
 end,debug.traceback)
 if not ok then gfx.abort();BLT.cleanup(UI.cancel_job);A.job=nil;BLT.cleanup(UI.stop_source_job);A.source_queue={};A.source_queue_i=1;UI.notice(err,true);BLT.recoverInput(A,err) end
 if A.closing then UI.close() else R.defer(UI.loop) end
end
Core.cleanup_stale_temp_items(A.project);UI.refresh();UI.loop()
