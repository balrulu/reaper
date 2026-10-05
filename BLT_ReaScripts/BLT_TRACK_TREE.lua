-- @description TRACK TREE
-- @version 0.2.17
-- @author Balrulu
-- @provides
--   . > ../
-- @changelog
--   BLT SERIES Beta TEST UPLOAD
-- @about
--   BLT SERIES Beta TEST UPLOAD

-- BEGIN BLT RETINA 1.1.0 (generated from _shared/BLT_Retina.lua)
-- Layout and pointer coordinates stay in window points on macOS.
-- Drawing, font rasterization and generated image buffers use backing pixels.
local gfx=(function(api,native)
 local osname=api.GetOS() or ''
 if not osname:match('OSX') and not osname:match('macOS') then return native end
 local G={mac=true}
 local backing=1
 local fonts,selected={},nil
 local faces={['Hiragino Sans']={'HiraginoSans-W4','HiraginoSans-W6'},
  ['Helvetica Neue']={'HelveticaNeue-Medium','HelveticaNeue-Bold'},['Menlo']={'Menlo-Regular','Menlo-Bold'}}
 faces['Yu Gothic UI'],faces['Segoe UI'],faces.Consolas=faces['Hiragino Sans'],faces['Helvetica Neue'],faces.Menlo
 faces['sans-serif'],faces.monospace=faces['Helvetica Neue'],faces.Menlo
 local function font_style(face,flags)
  local family=faces[face];if not family then return face,flags end
  local bold,style,shift=false,0,0
  while flags>0 do
   local byte=flags&255;flags=flags>>8
   if byte==98 or byte==66 then bold=true else style=style|(byte<<shift);shift=shift+8 end
  end
  return family[bold and 2 or 1],style
 end
 local function refresh_scale()
  local dpi=tonumber(native.ext_retina) or 1
  if dpi~=dpi or dpi<1 or dpi==math.huge then dpi=1 end
  if dpi==backing then return end
  backing=dpi
  for slot,f in pairs(fonts) do native.setfont(slot,f.face,f.size*backing,f.flags) end
  if selected then native.setfont(selected) end
 end
 function G.init(...)
  local result=native.init(...);refresh_scale();return result
 end
 function G.getchar(...)
  local result,unicode=native.getchar(...);refresh_scale();return result,unicode
 end
 function G.update(...)
  local result=native.update(...);refresh_scale();return result
 end
 function G.setfont(slot,face,size,flags)
  selected=slot
  if face~=nil then
   size,flags=size or 10,flags or 0
   local current=fonts[slot]
   if current and current.input==face and current.size==size and current.style==flags then return native.setfont(slot) end
   local f=fonts[slot] or {};fonts[slot]=f
   f.input,f.size,f.style=face,size,flags
   f.face,f.flags=font_style(face,flags)
   return native.setfont(slot,f.face,f.size*backing,f.flags)
  end
  return native.setfont(slot)
 end
 function G.measurestr(text)
  local w,h=native.measurestr(text);return w/backing,h/backing
 end
 function G.drawstr(text,flags,right,bottom)
  if flags==nil then return native.drawstr(text) end
  return native.drawstr(text,flags,right and right*backing,bottom and bottom*backing)
 end
 function G.rect(x,y,w,h,filled)
  return native.rect(x*backing,y*backing,w*backing,h*backing,filled)
 end
 function G.line(x,y,xx,yy,aa)
  return native.line(x*backing,y*backing,xx*backing,yy*backing,aa)
 end
 function G.circle(x,y,r,filled,aa)
  return native.circle(x*backing,y*backing,r*backing,filled,aa)
 end
 function G.arc(x,y,r,start_angle,end_angle,aa)
  return native.arc(x*backing,y*backing,r*backing,start_angle,end_angle,aa)
 end
 function G.roundrect(x,y,w,h,r,aa)
  return native.roundrect(x*backing,y*backing,w*backing,h*backing,r*backing,aa)
 end
 function G.triangle(x,y,xx,yy,xxx,yyy)
  return native.triangle(x*backing,y*backing,xx*backing,yy*backing,xxx*backing,yyy*backing)
 end
 function G.gradrect(x,y,w,h,r,g,b,a,rx,gx,bx,ax,ry,gy,by,ay)
  return native.gradrect(x*backing,y*backing,w*backing,h*backing,r,g,b,a,
   (rx or 0)/backing,(gx or 0)/backing,(bx or 0)/backing,(ax or 0)/backing,
   (ry or 0)/backing,(gy or 0)/backing,(by or 0)/backing,(ay or 0)/backing)
 end
 function G.setimgdim(image,w,h)
  return native.setimgdim(image,w>0 and math.floor(w*backing+.5) or w,h>0 and math.floor(h*backing+.5) or h)
 end
 function G.getimgdim(image)
  local w,h=native.getimgdim(image);return w/backing,h/backing
 end
 function G.blit(image,...)
  local args=table.pack(...)
  for i=3,args.n do if args[i]~=nil then args[i]=args[i]*backing end end
  return native.blit(image,table.unpack(args,1,args.n))
 end
 -- init/dock/clienttoscreen/screentoclient use native window points.
 -- showmenu reads native x/y and handles Retina conversion in REAPER.
 return setmetatable(G,{
  __index=function(_,key)
   local value=native[key]
   if key=='w' or key=='h' or key=='x' or key=='y' or key=='mouse_x' or key=='mouse_y' or key=='texth' then
    return value and value/backing
   end
   return value
  end,
  __newindex=function(_,key,value)
   if key=='x' or key=='y' then native[key]=value*backing else native[key]=value end
  end})
end)(reaper,gfx)
-- END BLT RETINA

-- BEGIN BLT COMMON CHROME 1.0.0 (generated from _shared/BLT_Chrome.lua)
local BLTChrome=(function()
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
return M
end)()
-- END BLT COMMON CHROME

local BLTPresetLimits={bytes=16777216,stringBytes=2097152,nodes=262144,entries=8192}
function BLTPresetLimits.show(english)
 reaper.MB(english and 'Preset capacity limit exceeded. Export presets individually instead of as a bundle.' or '容量上限オーバーです。一括ではなく個別に保存してください。','BLT PRESET',0)
end
local function create_window_geometry(api,graphics)
 local osname=api.GetOS() or ''
 if not osname:match('OSX') and not osname:match('macOS') then return api end
 local G=setmetatable({}, {__index=api})
 function G.GetMousePosition()
  local x,y=api.GetMousePosition();return x,-y
 end
 function G.JS_Window_GetRect(hwnd)
  local ok,l,t,r,b=api.JS_Window_GetRect(hwnd)
  if not ok then return ok,l,t,r,b end
  return ok,l,-math.max(t,b),r,-math.min(t,b)
 end
 function G.JS_Window_SetPosition(hwnd,x,y,w,h,z,flags)
  if graphics and graphics.dock and (graphics.dock(-1)&1)~=0 then return false end
  return api.JS_Window_SetPosition(hwnd,x,-y-h,w,h,z,flags)
 end
 return G
end

local WindowGeometry=create_window_geometry(reaper,gfx)
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
local B={fitCache={},fitCount=0,metrics={},metricCount=0,slots={},nextSlot=1,specs={}}
local host,C,Chrome,Chameleon,scale,ox,oy
local R=reaper
local UI={}
local Layout={bar={height=26,close=38,reset=34,theme=34,language=26,preset=84,arrow=20},popup={width=292,headerHeight=36,rowHeight=29,visiblePresets=8,hoverDelay=1}}
local Presets={items={},revision=0}
local ids={1,2,3,4,5,6,8,9,10,11,12,13,14,15}
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
 B.slots={};B.nextSlot=1;B.fontKey=nil;B.scratch=nil
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
 local k,px,weight,key=B.spec(size,kind,bold,s)
 local face=faces[k] or faces[1]
 B.faceKeys=B.faceKeys or {};local family=B.faceKeys[face]
 if not family then family={};B.faceKeys[face]=family end
 local style=px*2+(bold and 1 or 0)
 key=family[style]
 if not key then key=face..':'..px..':'..weight;family[style]=key end
 if B.fontKey==key then return end
 local slot=B.slots[key]
 if slot then gfx.setfont(slot)
 elseif B.nextSlot<=#ids then slot=ids[B.nextSlot];B.nextSlot=B.nextSlot+1;B.slots[key]=slot;gfx.setfont(slot,face,px,weight)
 elseif B.scratch==key then gfx.setfont(16)
 else gfx.setfont(16,face,px,weight);B.scratch=key end
 B.fontKey=key
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
local function chrome_resize_hit(x,y) if host.docked() then return nil end;if y<26 and x>=UI.bar(gfx.w).presetX then return nil end;return host.resizeHit(x,y) end
local function set_resize_cursor(mode) host.cursor(mode) end
local function begin_window_resize(mode) host.beginResize(mode) end
local function update_window_resize() host.resize() end
local function clear_chrome_tooltip() B.popupUntil=nil;if R.TrackCtl_SetToolTip then R.TrackCtl_SetToolTip('',0,0,true) end end
B.clearTooltip=clear_chrome_tooltip
function B.inputNotice()
 local x,y=gfx.clienttoscreen(gfx.mouse_x,gfx.mouse_y+18)
 R.TrackCtl_SetToolTip(Language.message('ReaImGui 0.10以降が必要です。ReaPackで導入・更新してください。'),x,y,true)
 B.popupUntil=R.time_precise()+1;B.tip=nil;B.tipVisible=false
end
function B.requireInput(ime)
 if ime.api then return true end
 if type(R.ImGui_GetBuiltinPath)~='function' then B.inputNotice();return false end
 local ok,api=pcall(function() return dofile(R.ImGui_GetBuiltinPath()..'/imgui.lua')('0.10') end)
 if not ok or type(api)~='table' then B.inputNotice();return false end
 ime.api=api;return true
end

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
  add(p.name,function() Presets.apply(p) end)
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
  Presets.down=false;Presets.pressed=nil;Presets.mx=nil;Presets.my=nil;Presets.hoverSince=nil
  host.cancelEdit();wake_visuals()
end
function Presets.dismiss()
  Presets.swallow=((gfx.mouse_cap or 0)&1)~=0
  Presets.open=false;Presets.hoverSince=nil;Presets.pressed=nil;host.cancelEdit();wake_visuals()
end
function Presets.buildRows()
  if Presets.page=="load" then
    local rows={{text="戻る",icon="back",action=function() Presets.page="main";Presets.selected=1 end}}
    local count=math.min(Layout.popup.visiblePresets,#Presets.items-Presets.offset)
    for i=1,count do
      local p=Presets.items[i+Presets.offset]
      rows[#rows+1]={text=p.name,literal=true,icon=Presets.current and Presets.current.name==p.name and "check" or "cards",action=function() Presets.dismiss();Presets.apply(p) end}
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
  if Presets.swallow and ((gfx.mouse_cap or 0)&1)==0 then Presets.swallow=false end
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
  local inBar=host.active() and not blocked and inWindow and UI.barHit(mx,my)
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
 scale,ox,oy=host.geometry()
 local blocked=not B.recoveryMode and (Presets.open or Presets.swallow or host.modal())
 custom_titlebar(blocked)
 Presets.draw()
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
  if (visible or expanded[row.id])and #row.children>0 and api.GetMediaTrackInfo_Value(row.ptr,'I_FOLDERCOMPACT')~=0 then changes[#changes+1]={row=row,key='I_FOLDERCOMPACT',value=0}end
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
local function transaction(api,project,title,fn)
 assert(api.EnumProjects(-1,'')==project,'プロジェクトが切り替わりました。')
 api.Undo_BeginBlock2(project);api.PreventUIRefresh(1)
 local ok,err=xpcall(fn,tostring)
 api.PreventUIRefresh(-1);api.Undo_EndBlock2(project,title,-1)
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
 transaction(api,tree.project,'BLT Track Tree: Paste track names',function()
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
 transaction(api,tree.project,'BLT Track Tree: Move tracks',function()
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
 transaction(api,tree.project,'BLT Track Tree: Track visibility',function()
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
 transaction(api,live.project,'BLT Track Tree: '..(on and 'Pin tracks'or'Unpin tracks'),function()
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
 if #changes>0 then transaction(api,live.project,'BLT Track Tree: Reveal track',function()
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
  field={0.018,0.040,0.080}, edge={0.145,0.285,0.445}, edge2={0.360,0.650,0.900},
  text={0.955,0.980,1.000}, muted={0.690,0.780,0.875}, faint={0.390,0.505,0.635},
  accent={0.120,0.490,0.980}, accent2={0.650,0.895,1.000}, accent3={0.045,0.235,0.520},
  focus={0.225,0.610,1.000}, focus2={0.690,0.900,1.000}, ink={0.018,0.075,0.160},
  hover={0.430,0.790,1.000}, warn={1.000,0.755,0.490}, red={1.000,0.230,0.300}, green={0.470,0.850,0.700}, quiet={0.300,0.360,0.440}
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

local panelPoints={{0,0},{0,0},{0,0},{0,0},{0,0},{0,0}}
local function cut_panel(x,y,w,h,cut,c,a,edge,edge_a,top_left)
  local tl=top_left and cut or 0
  local pts=panelPoints
  pts[1][1],pts[1][2]=x+tl,y;pts[2][1],pts[2][2]=x+w,y
  pts[3][1],pts[3][2]=x+w,y+h-cut;pts[4][1],pts[4][2]=x+w-cut,y+h
  pts[5][1],pts[5][2]=x,y+h;pts[6][1],pts[6][2]=x,y+tl
  local cx,cy=x+w/2,y+h/2
  color(c,a)
  for i=1,#pts do local p,q=pts[i],pts[i%#pts+1]; gfx.triangle(sx(cx),sy(cy),sx(p[1]),sy(p[2]),sx(q[1]),sy(q[2])) end
  if edge then for i=1,#pts do local p,q=pts[i],pts[i%#pts+1]; line(p[1],p[2],q[1],q[2],edge,edge_a or 1) end end
end

local Chameleon
local Chrome={window=nil,mouseDown=false,drag=nil,resize=nil,mouseActive=false,requestClose=false,requestReset=false,
  chameleonPressed=false,resizeCursors={},resizeCursorMode=nil,titleH=26,windowTitle='BLT TRACK TREE',titleText='T R A C K   T R E E',
  minW=360,minH=300,mint={0.38,0.88,0.72},ice={0.65,0.895,1.0},red={1.0,0.27,0.34},
  isWindows=R.GetOS():match("Win")~=nil,resizeEdge=6,resizeCornerBand=8,resizeCornerSpan=24,resizeTopLeftGuard=30,resizeTopRightGuard=110,
  tooltipHover=nil,tooltipSince=0,tooltipVisible=false,tooltipDelay=.70,
  cursorId={we=32644,ns=32645,nwse=32642,nesw=32643,arrow=32512}}
Chrome.font=Chrome.isWindows and "Segoe UI" or (BLT_MAC and "Helvetica Neue" or "sans-serif")
local function chameleon_notify(text)
  status(text,false)
end

-- BEGIN BLT CHAMELEON 1.0.0 (generated from _shared/BLT_Chameleon.lua)
-- Standalone embedded factory. Hosts supply persistence and redraw hooks.
local BLTChameleon=(function()
-- BEGIN BLT THEME COLORS 1.0.0 (generated from _shared/BLT_ThemeColors.lua)
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
 function M.read(api,key,fallback) return M.decode(api,M.native(api,key)) or fallback end
 local function linear(v) return v<=.04045 and v/12.92 or ((v+.055)/1.055)^2.4 end
 function M.luminance(c) return linear(c[1])*.2126+linear(c[2])*.7152+linear(c[3])*.0722 end
 function M.contrast(a,b)
  local x,y=M.luminance(a),M.luminance(b)
  return (math.max(x,y)+.05)/(math.min(x,y)+.05)
 end
 return M
end)()
-- END BLT THEME COLORS
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
 -- Cache native values and decode only changed slots. Failed decoding is retried.
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
  -- Keep the main window/toolbar RGB unchanged; images may override the visible toolbar.
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
  local theme={enabled=api.GetExtState(options.section,'chameleon')=='1',poll_at=0,poll_interval=3,keys=M.keys}
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
  function theme.sample() local map=M.snapshot(api);return map,M.palette(map,defaults) end
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
-- END BLT CHAMELEON

Chameleon=BLTChameleon.new(R,C,{
 section=SECTION,
 store=BLT.store,
 notify=chameleon_notify,
 chrome=Chrome,
 changed=function() A.dirty=true end
})


local function titlebar_api_ready()
  local required={"JS_Window_Find","JS_Window_IsWindow","JS_Window_GetRect","JS_Window_SetPosition","JS_Window_SetStyle"}
  if Chrome.isWindows then
    required[#required+1]="JS_Mouse_LoadCursor"
    required[#required+1]="JS_Mouse_SetCursor"
  end
  for _,name in ipairs(required) do
    if type(R[name])~="function" then
      return false,"カスタムタイトルバーには js_ReaScriptAPI が必要です。\nReaPack から js_ReaScriptAPI をインストールしてください。"
    end
  end
  return true
end

local function gfx_window_handle()
  if Chrome.window and R.JS_Window_IsWindow(Chrome.window) then return Chrome.window end
  Chrome.window=R.JS_Window_Find(Chrome.windowTitle,true)
  return Chrome.window
end

local function apply_custom_window_style(target_w,target_h)
  local hwnd=gfx_window_handle()
  if not hwnd then return false end
  local ok,l,t=WindowGeometry.JS_Window_GetRect(hwnd)
  if not R.JS_Window_SetStyle(hwnd,"POPUP") then return false end
  if ok then BLT.position(hwnd,l,t,target_w,target_h,"","") end
  return true
end

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
local function set_resize_cursor(mode)
  if not Chrome.isWindows then return end
  local kind=resize_cursor_kind(mode)
  if kind then
    local cursor=Chrome.resizeCursors[kind]
    if not cursor then cursor=R.JS_Mouse_LoadCursor(Chrome.cursorId[kind]); Chrome.resizeCursors[kind]=cursor end
    if cursor then R.JS_Mouse_SetCursor(cursor) end
    Chrome.resizeCursorMode=kind
  elseif Chrome.resizeCursorMode then
    local cursor=Chrome.resizeCursors.arrow
    if not cursor then cursor=R.JS_Mouse_LoadCursor(Chrome.cursorId.arrow); Chrome.resizeCursors.arrow=cursor end
    if cursor then R.JS_Mouse_SetCursor(cursor) end
    Chrome.resizeCursorMode=nil
  end
end
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

local Dock={state=extnum('dock_state',0)}
local IME={}
local editor=nil
local widgets={}
local clipboard_action
local TOP,ROW=136,27
local LINK_GOLD={1,.885,.44}
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
local function docked()return(gfx.dock(-1)&1)~=0 end
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
  font(12,1,true);local linkW=math.ceil(gfx.measurestr('VIEW LINK'))+22
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
 if key=='related'and S.related~=value then A.relatedMotion={from=A.relatedPosition or(S.related and 1 or 0),at=R.time_precise()}end
 if key=='link'and not value and A.linkState then Core.restoreview(R,A.linkState);A.linkState=nil end
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
 if not BLT.requireInput(IME)then return end
 local I=IME.api;IME.ctx=I.CreateContext('BLT Track Tree filter');IME.font=I.CreateFont(fonts[1]);I.Attach(IME.ctx,IME.font)
 editor={original=A.query,frames=0,fontSize=nil};A.dirty=true
end
local function rgba(c)return(floor(c[1]*255)<<24)|(floor(c[2]*255)<<16)|(floor(c[3]*255)<<8)|255 end
local function edit_frame()
 if not editor then return end
 local I,ctx=IME.api,IME.ctx
 local clearX=clear_geometry()
 local nx,ny=gfx.clienttoscreen(13,39);local ex,ey=gfx.clienttoscreen(clearX-2,64)
 local x,y=I.PointConvertNative(ctx,nx,ny);local xx,yy=I.PointConvertNative(ctx,ex,ey)
 local unit=abs(xx-x)/(clearX-15)
 I.SetNextWindowPos(ctx,x,y,I.Cond_Always);I.SetNextWindowSize(ctx,abs(xx-x),abs(yy-y),I.Cond_Always)
 if editor.frames==1 then I.SetNextWindowFocus(ctx)end
 I.PushStyleVar(ctx,I.StyleVar_WindowPadding,0,0);I.PushStyleVar(ctx,I.StyleVar_WindowMinSize,1,1)
 I.PushStyleVar(ctx,I.StyleVar_WindowBorderSize,0);I.PushStyleVar(ctx,I.StyleVar_FramePadding,6*unit,5*unit)
 I.PushStyleColor(ctx,I.Col_WindowBg,rgba(C.field));I.PushStyleColor(ctx,I.Col_FrameBg,rgba(C.field));I.PushStyleColor(ctx,I.Col_Text,rgba(C.text))
 I.PushFont(ctx,IME.font,14*unit)
 local shown=I.Begin(ctx,'##filter',nil,I.WindowFlags_NoDecoration|I.WindowFlags_NoMove|I.WindowFlags_NoSavedSettings|I.WindowFlags_NoDocking)
 local done,cancel=false,false
 if shown then
  if not editor.fontSize or editor.unit~=unit then
   local sample='あいうえお漢字ABC012345';font(14,1,false)
   local target=gfx.measurestr(sample)*unit;local measured=I.CalcTextSize(ctx,sample)
   editor.fontSize=measured>0 and clamp(14*unit*target/measured*1.04,1,96)or 14*unit;editor.unit=unit
  end
  I.PopFont(ctx);I.PushFont(ctx,IME.font,editor.fontSize)
  I.SetNextItemWidth(ctx,abs(xx-x));if editor.frames==1 then I.SetKeyboardFocusHere(ctx)end
  local changed,text=I.InputText(ctx,'##text',A.query,I.InputTextFlags_AutoSelectAll)
  if changed then query(text)end
  cancel=I.IsKeyPressed(ctx,I.Key_Escape,false)
  done=I.IsKeyPressed(ctx,I.Key_Enter,false)or(editor.frames>2 and not I.IsWindowFocused(ctx))
  I.End(ctx)
 end
 I.PopFont(ctx);I.PopStyleColor(ctx,3);I.PopStyleVar(ctx,4)
 editor.frames=editor.frames+1
 if cancel or done then stop_edit(cancel)end
end
local function button(id,text,x,y,w,fn,icon)
 local hot=gfx.mouse_x>=x and gfx.mouse_x<x+w and gfx.mouse_y>=y and gfx.mouse_y<y+22
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
 local on=S[key];local hot=gfx.mouse_x>=x and gfx.mouse_x<x+w and gfx.mouse_y>=y and gfx.mouse_y<y+24
 local hue=key=='link'and LINK_GOLD or C.accent2
 if key=='related'then
  local position=on and 1 or 0
  if A.relatedMotion then
   local t=clamp((R.time_precise()-A.relatedMotion.at)/.16,0,1)
   position=A.relatedMotion.from+(position-A.relatedMotion.from)*(t*t*(3-2*t))
   if t<1 then A.dirty=true else A.relatedMotion=nil end
  end
  A.relatedPosition=position
  local cx,cy=sx(x+11+12*position),sy(y+12)
  line(x+7,y+12,x+27,y+12,C.edge2,.45)
  color(C.faint,.8);gfx.circle(cx,cy,4.2*scale,1,1)
  if position>.001 then
   color(C.accent,.06*position);gfx.circle(cx,cy,7*scale,1,1)
   color(C.accent2,.94*position);gfx.circle(cx,cy,4.2*scale,1,1)
  end
 elseif key=='link'then
  cut_panel(x,y,w,24,3,on and C.panel2 or C.field,1,on and hue or C.edge,on and .8 or .6)
  if on then
   for i=2,1,-1 do color(hue,.045*(3-i));gfx.rect(x-i,y-i,w+2*i,24+2*i,0)end
   rect(x+2,y+2,w-4,20,hue,.09)
  elseif hot then rect(x+2,y+2,w-4,20,C.panel2,.7)end
  color(on and hue or C.faint);gfx.circle(x+8,y+12,2,1,1)
  if on then color(hue,.13);gfx.circle(x+8,y+12,5,1,1)end
 else
  rect(x,y,w,24,on and C.panel2 or(hot and C.panel or C.field))
  if on then
   rect(x+1,y+1,w-2,22,hue,.09)
   line(x+7,y+23,x+w-7,y+23,hue,.9)
   line(x+7,y+22,x+w-7,y+22,hue,.18)
  end
 end
 font(12,1,key~='related');local tw,th=BLT.metricsFor(text)
 color(on and hue or C.muted)
 gfx.x=key=='related'and x+36 or key=='link'and x+15 or x+(w-tw)/2
 gfx.y=y+(24-th)/2;gfx.drawstr(text)
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
 toolbar_geometry();refresh(false);widgets={};rect(0,0,gfx.w,gfx.h,C.bg)
 local clearX,clearW=clear_geometry()
 cut_panel(12,38,gfx.w-24,27,4,C.field,1,C.edge2,.6)
 if not editor then label(A.query~=''and A.query or Language.text('検索…'),19,44,clearX-24,21,14,A.query~=''and C.text or C.faint,false,0,1,true)end
 local hot=gfx.mouse_x>=clearX and gfx.mouse_x<clearX+clearW and gfx.mouse_y>=39 and gfx.mouse_y<64
 if hot then rect(clearX,39,clearW,25,C.panel2,.8)end
 label('クリア',clearX+4,45,clearW-8,18,11,hot and C.text or C.muted,false,0)
 widgets[#widgets+1]={id='clear',x=clearX,y=39,w=clearW,h=25,tip='フィルタークリア',fn=function()stop_edit(false);A.closed={};query('')end}
 rect(11,73,103,26,C.edge,.6)
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
 label(message,12,gfx.h-19,gfx.w-24,18,11,A.bad and C.red or C.muted)
 BLT.bar();gfx.update()
end
local function toggle_dock()
 stop_edit(false)
 if not docked()then local _,x,y,w,h=gfx.dock(-1,0,0,0,0);A.floating={x,y,w,h}end
 Dock.state=gfx.dock(-1)~1;gfx.dock(Dock.state);Chrome.window=nil;BLT.lastRect=nil
 R.SetExtState(SECTION,'dock_state',tostring(Dock.state),true)
 if not docked()then
  local f=A.floating;apply_custom_window_style(f and f[3]or W,f and f[4]or H+26)
  if f then BLT.position(gfx_window_handle(),f[1],f[2],f[3],f[4],'','')end
 end
 A.dirty=true
end
local function input()
 refresh(false)
 local x,y,cap=gfx.mouse_x,gfx.mouse_y,gfx.mouse_cap
 local right=(cap&2)~=0;local rightPressed=right and not A.rightDown;A.rightDown=right
 local down=(cap&1)~=0;local ctrl=(cap&4)~=0 or(BLT_MAC and(cap&32)~=0);local shift=(cap&8)~=0
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
 docked=docked,fold=toggle_dock,geometry=function()return 1,0,0 end,active=function()local f=gfx.getchar(65536);return(f&1)==0 or(f&2)~=0 end,
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
 local dock,x,y,w,h=gfx.dock(-1,0,0,0,0)
 R.SetExtState(SECTION,'dock_state',tostring(dock),true)
 if(dock&1)==0 then for k,v in pairs({window_x=x,window_y=y,window_w=w,window_h=h})do R.SetExtState(SECTION,k,tostring(v),true)end end
 titlebar_cleanup();clear_chrome_tooltip();gfx.quit()
end
local ok,err=titlebar_api_ready();if not ok then R.MB(err,'BLT TRACK TREE',0);return end
if R.set_action_options then R.set_action_options(2)end
local ww=clamp(extnum('window_w',W),360,1600);local hh=clamp(extnum('window_h',H+26),300,2000)
gfx.ext_retina=1
gfx.init(Chrome.windowTitle,ww,hh,Dock.state,extnum('window_x',100),extnum('window_y',100))
if not docked()then apply_custom_window_style(ww,hh)end
if Chameleon.enabled then Chameleon.refresh(true)end
R.atexit(close)
local restoreOK,restoreError=pcall(BLTRestore.start,R)
if not restoreOK then R.MB(Language.text('自動復元の登録に失敗しました。')..'\n'..tostring(restoreError),'BLT TRACK TREE',0)end
for _,key in ipairs(OPTION_KEYS)do local value=R.GetExtState(SECTION,key);if value~=''then S[key]=value=='1'end end
A.query=R.GetExtState(SECTION,'query');S.query=A.query;refresh(true)
local function loop()
 local ok,why=xpcall(function()
  local k=gfx.getchar();if k<0 then A.manualClose=true;A.closing=true;return end
  k=BLT.key(k)
  if clipboard_shortcut(k)then k=0 end
  if not editor then
   if k==27 then A.manualClose=true;A.closing=true
   elseif k==1 then refresh(true);for _,r in ipairs(A.rows)do if not r.selected then R.SetTrackSelected(r.ptr,true)end end
    A.revision=R.GetProjectStateChangeCount(A.tree.project);sync_selection(A.tree.project)
   elseif k==6 then start_edit()end
  end
  local now=R.time_precise();BLT.tick(now);if Chameleon.tick(now)then A.dirty=true end
  refresh(false);edit_frame()
  if A.width~=gfx.w or A.height~=gfx.h then A.width,A.height=gfx.w,gfx.h;toolbar_geometry();A.offset=clamp(A.offset,0,max(0,#A.rows-capacity()));A.dirty=true end
  if A.dirty or gfx.mouse_cap~=0 or gfx.mouse_wheel~=0 or A.down or A.rightDown or A.drag or A.mouseX~=gfx.mouse_x or A.mouseY~=gfx.mouse_y then
   A.mouseX,A.mouseY=gfx.mouse_x,gfx.mouse_y;A.dirty=false;draw();input()
  end
  if Chrome.requestClose then A.closing=true end
  if Chrome.requestReset then Chrome.requestReset=false;reset_window_size();A.dirty=true end
 end,debug.traceback)
 if not ok then A.drag=nil;A.down=false;status(BLT.publicError(why),true);BLT.logError(why)end
 if A.closing then close()else R.defer(loop)end
end
loop()
