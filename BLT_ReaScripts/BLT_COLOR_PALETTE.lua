-- @description BLT COLOR PALETTE
-- @version 0.1.12
-- @author Balrulu
-- @provides
--   . > ../
-- @changelog
--   BLT SERIES Beta TEST UPLOAD
-- @about
--   BLT SERIES Beta TEST UPLOAD

local R=reaper
local SECTION='BLT_COLOR_PALETTE'
local VERSION='0.1.12'
local function dependencies()
 local osname=R.GetOS() or ''
 if not (osname:match('Win') or osname:match('OSX') or osname:match('macOS')) then return false,'WindowsまたはmacOSが必要です。' end
 for _,name in ipairs({'GetNumRegionsOrMarkers','GetRegionOrMarker','GetRegionOrMarkerInfo_Value','SetRegionOrMarkerInfo_Value','GetSetRegionOrMarkerInfo_String','GetCursorContext2','CountSelectedTracks2','GetSelectedTrack2','GetTrackGUID','GetSetMediaItemInfo_String'}) do
  if type(R[name])~='function' then return false,'REAPER 7.62以降が必要です。REAPERを更新してください。' end
 end
 for _,name in ipairs({'JS_Window_Find','JS_Window_IsWindow','JS_Window_GetRect','JS_Window_SetPosition','JS_Window_SetStyle','JS_Mouse_GetState','JS_Window_GetFocus','JS_Window_FromPoint','JS_Window_GetTitle','JS_Window_GetParent'}) do
  if type(R[name])~='function' then return false,'js_ReaScriptAPIが必要です。ReaPackで導入してください。' end
 end
 if osname:match('Win') and (type(R.JS_Mouse_LoadCursor)~='function' or type(R.JS_Mouse_SetCursor)~='function') then
  return false,'js_ReaScriptAPIが必要です。ReaPackで導入してください。'
 end
 for _,name in ipairs({'CF_GetCustomColor','CF_SetCustomColor'}) do
  if type(R[name])~='function' then return false,'SWS ExtensionのカスタムカラーAPIが必要です。SWSを最新版へ更新してください。' end
 end
 return true
end
local dependency_ok,dependency_error=dependencies()
if not dependency_ok then R.MB(dependency_error,'BLT COLOR PALETTE',0);return end

-- Color and target transactions. All colors in saved tool settings are portable RGB.
local function create_color_core(api)
 local K={FLAG=0x1000000}
 local floor,abs=math.floor,math.abs
 function K.finite(v) return type(v)=='number' and v==v and abs(v)<math.huge end
 function K.rgb(r,g,b) return (r<<16)|(g<<8)|b end
 function K.channels(rgb) return (rgb>>16)&255,(rgb>>8)&255,rgb&255 end
 function K.native(rgb) return api.ColorToNative(K.channels(rgb))&0xFFFFFF end
 function K.portable(native) return K.rgb(api.ColorFromNative(native&0xFFFFFF)) end
 function K.hex(rgb) return string.format('#%06X',rgb&0xFFFFFF) end
 function K.hsv(h,s,v)
  local q=h%1*6;local i=floor(q);local f=q-i
  local a,b,c=v*(1-s),v*(1-s*f),v*(1-s*(1-f));local r,g,blue
  if i==0 then r,g,blue=v,c,a elseif i==1 then r,g,blue=b,v,a elseif i==2 then r,g,blue=a,v,c
  elseif i==3 then r,g,blue=a,b,v elseif i==4 then r,g,blue=c,a,v else r,g,blue=v,a,b end
  return K.rgb(floor(r*255+.5),floor(g*255+.5),floor(blue*255+.5))
 end
 -- Rows are saturation/value pairs. The Basic set retains its original RGBs.
 K.palette_specs={
  {id='basic',name='基本色',rows={{.30,1},{.55,.97},{.78,.90},{.90,.73},{.82,.51}}},
  {id='pastel',name='パステル',rows={{.14,1},{.22,.99},{.30,.97},{.38,.94},{.44,.90}}},
  {id='vivid',name='ビビット',rows={{.72,1},{.88,1},{1,.96},{.97,.87},{.91,.75}}},
  {id='deep',name='ディープ',rows={{.60,.62},{.70,.52},{.78,.43},{.84,.35},{.90,.27}}},
  -- Generated only when this tab is pressed. No theme read/poll is attached to drawing.
  {id='chameleon',name='カメレオン',dynamic=true},
 }
 function K.palette(kind)
  local spec=K.palette_specs[1]
  for _,candidate in ipairs(K.palette_specs) do if candidate.id==kind then spec=candidate;break end end
  if spec.dynamic or not spec.rows then return nil end
  local out={}
  for _,row in ipairs(spec.rows) do for col=0,11 do out[#out+1]=K.hsv(col/12,row[1],row[2]) end end
  for col=0,11 do local v=floor(255*(1-col/11)+.5);out[#out+1]=K.rgb(v,v,v) end
  return out
 end
 function K.encode_custom(values)
  assert(type(values)=='table' and #values==16,'Invalid custom palette')
  local bytes={}
  for i=1,16 do
   local c=values[i];assert(K.finite(c) and c%1==0 and c>=0 and c<=0xFFFFFFFF,'Invalid custom color')
   bytes[#bytes+1]=string.pack('<I4',c)
  end
  local payload=table.concat(bytes);local out={};local sum=0
  for i=1,#payload do local b=payload:byte(i);sum=sum+b;out[#out+1]=string.format('%02X',b) end
  out[#out+1]=string.format('%02X',sum%256);return table.concat(out)
 end
 function K.read_custom()
  -- SWS uses the platform's native palette (including macOS color storage).
  -- CF_GetCustomColor is zero-based and returns an OS-native 24-bit color.
  local values={}
  for i=1,16 do
   local ok,native=pcall(api.CF_GetCustomColor,i-1)
   if not ok or not K.finite(native) or native%1~=0 or native<0 or native>0xFFFFFF then return nil,'read' end
   values[i]=native
  end
  return values,nil,K.encode_custom(values)
 end
 function K.write_custom_slot(slot,rgb)
  if type(slot)~='number' or slot%1~=0 or slot<1 or slot>16 then return false,'slot' end
  if not K.finite(rgb) or rgb%1~=0 or rgb<0 or rgb>0xFFFFFF then return false,'color' end
  local values,err,old=K.read_custom();if not values then return false,err end
  local native=K.native(rgb);if values[slot]==native then return true end
  api.SetExtState('BLT_COLOR_PALETTE','custom_backup',old,true)
  -- A void setter: verify by rereading, rather than testing its return value.
  local ok=pcall(api.CF_SetCustomColor,slot-1,native)
  if not ok then return false,'write' end
  local check=K.read_custom()
  if not check or check[slot]~=native then return false,'verify' end
  return true
 end
 function K.collect(project,pause,only)
  local s={project=project,item={},track={},ruler={},signatures={}}
  local selected=(not only or only=='item') and api.CountSelectedMediaItems(project) or 0
  -- This read-only pass does not alter item order or invalidate enumeration.
  for i=0,selected-1 do
   if pause and i>0 then pause() end
   local p=api.GetSelectedMediaItem(project,i)
   if p then
    local ok,guid=api.GetSetMediaItemInfo_String(p,'GUID','',false)
    assert(ok and guid~='','Cannot identify a selected item')
    s.item[#s.item+1]={ptr=p,guid=guid}
   end
  end
  local n=(not only or only=='track') and api.CountSelectedTracks2(project,true) or 0
  for i=0,n-1 do
   if pause and i>0 then pause() end
   local p=api.GetSelectedTrack2(project,i,true)
   if p then
    local guid=api.GetTrackGUID(p);assert(guid and guid~='','Cannot identify a selected track')
    s.track[#s.track+1]={ptr=p,guid=guid}
   end
  end
  local rulers=(not only or only=='ruler') and api.GetNumRegionsOrMarkers(project) or 0
  for i=0,rulers-1 do
   if pause and i>0 then pause() end
   local p=api.GetRegionOrMarker(project,i,'')
   if p and api.GetRegionOrMarkerInfo_Value(project,p,'B_UISEL')~=0 then
    local ok,guid=api.GetSetRegionOrMarkerInfo_String(project,p,'GUID','',false)
    assert(ok and guid~='','Cannot identify a selected marker/region')
    s.ruler[#s.ruler+1]={ptr=p,guid=guid,isregion=api.GetRegionOrMarkerInfo_Value(project,p,'B_ISREGION')~=0}
   end
  end
  for _,kind in ipairs({'item','track','ruler'}) do
   local sig={};for _,r in ipairs(s[kind]) do sig[#sig+1]=r.guid or tostring(r.ptr) end
   table.sort(sig);s.signatures[kind]=table.concat(sig,';')
  end
  return s
 end
 function K.color(project,kind,row,set)
  local p=row.ptr
  if kind=='ruler' then
   p=api.GetRegionOrMarker(project,-1,row.guid)
   assert(p,'Target marker/region no longer exists')
   if set~=nil then api.SetRegionOrMarkerInfo_Value(project,p,'I_CUSTOMCOLOR',set) end
   return api.GetRegionOrMarkerInfo_Value(project,p,'I_CUSTOMCOLOR')
  elseif kind=='item' then
   assert(api.ValidatePtr2(project,p,'MediaItem*'),'Target item no longer exists')
   if set~=nil then assert(api.SetMediaItemInfo_Value(p,'I_CUSTOMCOLOR',set),'Could not set item color') end
   return api.GetMediaItemInfo_Value(p,'I_CUSTOMCOLOR')
  elseif kind=='track' then
   assert(api.ValidatePtr2(project,p,'MediaTrack*'),'Target track no longer exists')
   if set~=nil then assert(api.SetMediaTrackInfo_Value(p,'I_CUSTOMCOLOR',set),'Could not set track color') end
   return api.GetMediaTrackInfo_Value(p,'I_CUSTOMCOLOR')
  end
  error('Unsupported target type')
 end
 function K.apply(snapshot,kind,rgb)
  if not snapshot or not snapshot[kind] or #snapshot[kind]==0 then return false,'empty',0 end
  if api.EnumProjects(-1,'')~=snapshot.project then return false,'project',0 end
  if not K.finite(rgb) or rgb%1~=0 or rgb<0 or rgb>0xFFFFFF then return false,'color',0 end
  local ok,fresh=pcall(K.collect,snapshot.project,nil,kind)
  if not ok then return false,'read',0 end
  if fresh.signatures[kind]~=snapshot.signatures[kind] then return false,'selection',0 end
  local project=snapshot.project;local value=K.native(rgb)|K.FLAG;local changes={}
  local valid,why=pcall(function()
   for _,r in ipairs(fresh[kind]) do
    local old=K.color(project,kind,r)
    if old~=value then changes[#changes+1]={row=r,old=old} end
   end
  end)
  if not valid then return false,'read',0 end
  if #changes==0 then return true,'unchanged',#fresh[kind] end
  api.Undo_BeginBlock2(project);api.PreventUIRefresh(1)
  local touched=0
  local done,err=xpcall(function()
   for i,c in ipairs(changes) do
    touched=i
    assert(K.color(project,kind,c.row,value)==value,'Color verification failed')
   end
  end,debug.traceback)
  local restored=true
  if not done then
   for i=touched,1,-1 do local c=changes[i]
    local r,v=pcall(K.color,project,kind,c.row,c.old);if not r or v~=c.old then restored=false end
   end
  end
  api.PreventUIRefresh(-1)
  api.Undo_EndBlock2(project,done and 'BLT COLOR PALETTE: Set selected '..kind..' colors' or 'BLT COLOR PALETTE: Restore color transaction',-1)
  api.UpdateArrange();if kind=='ruler' then api.UpdateTimeline() end
  if not done then return false,restored and 'rollback' or 'restore_failed',0 end
  return true,'changed',#changes
 end
 return K
end

-- Observe real selection interactions, not mouse hover or fixed type priority.
-- A caller may publish the observation in session-only ExtState for later launches.
local function create_target_observer(api,core)
 local T={kind=nil,reason='unknown',serial=0,next_poll=0,last_buttons=0,scan_interval=.12}
 local TRACKER='BLT_COLOR_PALETTE_TRACKER'
 local kinds={'item','track','ruler'}
 local function valid_hwnd(w) return w and api.JS_Window_IsWindow(w) end
 local function title(w)
  if not valid_hwnd(w) then return '' end
  return (api.JS_Window_GetTitle(w) or ''):lower()
 end
 function T.window_kind(w)
  for _=1,24 do
   if not valid_hwnd(w) or w==api.GetMainHwnd() then return nil end
   local text=title(w)
   if text:find('blt color palette',1,true) then return 'self' end
   if text:find('region/marker',1,true) or text:find('marker/region',1,true)
    or text:find('marker region desk',1,true)
    or (text:find('マーカー',1,true) and text:find('リージョン',1,true)) then return 'ruler' end
   local p=api.JS_Window_GetParent(w);if p==w then return nil end;w=p
  end
 end
 function T.focus_kind()
  local w=api.JS_Window_GetFocus()
  if T.focus_cached and w==T.focus_hwnd then return T.focus_family end
  T.focus_hwnd=w;T.focus_family=T.window_kind(w);T.focus_cached=true
  return T.focus_family
 end
 function T.mouse_kind()
  local x,y=api.GetMousePosition();local w=api.JS_Window_FromPoint(x,y)
  local wk=T.window_kind(w)
  if wk=='self' then return nil,true end
  if wk=='ruler' then return 'ruler',false end
  local tr,info=api.GetThingFromPoint(x,y);info=info or ''
  if info:match('^tcp') or info:match('^mcp') then
   if info:find('env',1,true) then return 'unsupported',false end
   return tr and 'track' or nil,false
  end
  if info:match('^arrange') then
   -- Only the target family is needed; avoid detailed take/envelope hit testing.
   if api.GetCursorContext2(true)==2 then return 'unsupported',false end
   return api.GetItemFromPoint(x,y,true) and 'item' or nil,false
  end
  if info:match('^ruler') then return 'ruler',false end
  -- Native hit information can be empty over an item. Query the item directly.
  if api.GetItemFromPoint(x,y,true) then
   return api.GetCursorContext2(true)==2 and 'unsupported' or 'item',false
  end
  -- Unknown/empty areas are resolved from selection changes, not a deep hit test.
  return nil,false
 end
 function T.set(kind,reason,now)
  if kind=='unsupported' then kind=nil;reason='unsupported' end
  local changed=T.kind~=kind or T.reason~=reason
  T.kind,T.reason,T.event_at=kind,reason,now
  T.serial=T.serial+1;T.changed=true
  return changed
 end
 function T.seed(snapshot,evidence)
  local e=evidence or {};local now=e.now or api.time_precise()
  T.snapshot=snapshot;T.project=snapshot.project;T.last_context=e.context;T.last_focus=e.focus
  if e.tracked and snapshot[e.tracked] then T.set(e.tracked,'tracked',now);return end
  if e.focus=='ruler' then T.set('ruler','focus',now);return end
  -- A selected marker can outlive focus. CursorContext2 only distinguishes
  -- track/item/envelope and cannot date that marker selection. Never guess.
  if #snapshot.ruler>0 and (#snapshot.item>0 or #snapshot.track>0) then
   T.set(nil,'ambiguous',now);return
  end
  if #snapshot.ruler>0 then T.set('ruler','single',now);return end
  if e.context==0 then T.set('track','context',now);return end
  if e.context==1 then T.set('item','context',now);return end
  if e.context==2 then T.set(nil,'unsupported',now);return end
  local only,n=nil,0
  for _,kind in ipairs(kinds) do if #snapshot[kind]>0 then only=kind;n=n+1 end end
  T.set(n==1 and only or nil,n>1 and 'ambiguous' or 'unknown',now)
 end
 function T.read_tracker(snapshot,now)
  local beat=tonumber(api.GetExtState(TRACKER,'heartbeat'))
  if not beat or now-beat<0 or now-beat>.8 then return nil end
  if api.GetExtState(TRACKER,'project')~=tostring(snapshot.project) then return nil end
  local kind=api.GetExtState(TRACKER,'kind')
  if not snapshot[kind] then return nil end
  for _,family in ipairs(kinds) do
   if api.GetExtState(TRACKER,'signature_'..family)~=snapshot.signatures[family] then return nil end
  end
  if tonumber(api.GetExtState(TRACKER,'cursor_context'))~=api.GetCursorContext2(true) then return nil end
  return kind
 end
 function T.start(use_tracker)
  local now=api.time_precise();local project=api.EnumProjects(-1,'');local snap=core.collect(project)
  T.seed(snap,{context=api.GetCursorContext2(true),focus=T.focus_kind(),tracked=use_tracker and T.read_tracker(snap,now),now=now})
  T.last_buttons=api.JS_Mouse_GetState(3);T.next_poll=now+T.scan_interval
  T.revision=api.GetProjectStateChangeCount(project)
  return T
 end
 function T.accept(snapshot,event,context,focused,now)
  if T.project~=snapshot.project then
   T.pending=nil;T.seed(snapshot,{context=context,focus=focused,now=now});return
  end
  local previous=T.snapshot;T.snapshot=snapshot
  if event then
   T.set(event,'click',now);T.hold_until=now+.24
  else
   local changed={};local count=0;local one
   for _,kind in ipairs(kinds) do
    if previous and snapshot.signatures[kind]~=previous.signatures[kind] then changed[kind]=true;count=count+1;one=kind end
   end
   if now<(T.hold_until or 0) then
    -- Item clicks may also select their owning track. Keep the clicked type.
   elseif changed.ruler and #snapshot.ruler>0 then T.set('ruler','selection',now)
   elseif count==1 then
    -- Clearing another type does not steal ownership from an explicit click.
    if #snapshot[one]>0 or T.kind==one then T.set(one,'selection',now) end
   elseif count>1 then
    if context==1 and changed.item then T.set('item','context',now)
    elseif context==0 and changed.track then T.set('track','context',now)
    else T.set(nil,'ambiguous',now) end
   elseif focused=='ruler' and #snapshot.ruler>0 and T.last_focus~='ruler' then T.set('ruler','focus',now)
   elseif focused~='self' and context~=T.last_context then
    if context==0 then T.set('track','context',now)
    elseif context==1 then T.set('item','context',now)
    elseif context==2 then T.set(nil,'unsupported',now) end
   end
  end
  T.last_context=context;T.last_focus=focused
 end
 function T.tick(now,force)
  T.changed=false
  local buttons=api.JS_Mouse_GetState(3)
  if (buttons&(~T.last_buttons)&3)~=0 then
   T.scan=nil
   local kind,own=T.mouse_kind()
   if kind then T.pending=kind;T.pending_at=now;T.next_poll=0 end
  end
  local released=(T.last_buttons&(~buttons)&3)~=0
  if released then T.scan=nil end
  T.last_buttons=buttons
  local project=api.EnumProjects(-1,'')
  local context=api.GetCursorContext2(true)
  if force or T.scan or released or now>=T.next_poll or T.project~=project or context~=T.last_context then
   local revision=api.GetProjectStateChangeCount(project)
   local focused=T.focus_kind()
   -- Idle checks inspect revision/focus only. Enumerate after a host interaction.
   -- Color application independently validates the current target selection.
   local refresh=force or released or T.pending or not T.snapshot or T.project~=project
    or context~=T.last_context or focused~=T.last_focus or revision~=T.revision
   local snap=T.snapshot
   if force then T.scan=nil;snap=core.collect(project)
   elseif refresh or T.scan then
    local job=T.scan
    if not job or job.project~=project or job.revision~=revision then
     job={project=project,revision=revision}
     job.thread=coroutine.create(function() return core.collect(project,coroutine.yield) end)
     T.scan=job
    end
    local deadline=api.time_precise()+.002
    for _=1,512 do
     local ok,result=coroutine.resume(job.thread)
     if not ok then T.scan=nil;error(result,0) end
     if coroutine.status(job.thread)=='dead' then snap=result;T.scan=nil;refresh=true;break end
     if api.time_precise()>=deadline then break end
    end
    if T.scan then return false end
   end
   if refresh then
    T.revision=revision
   end
   local before=T.snapshot
   local event=T.pending;T.pending=nil
   T.accept(snap,event,context,focused,now)
   if not before or before.project~=project or (T.kind and before.signatures[T.kind]~=snap.signatures[T.kind]) then T.changed=true end
   T.next_poll=now+T.scan_interval
  end
  return T.changed
 end
 function T.publish(now)
  local snapshot=T.snapshot;if not snapshot then return end
  local signature=snapshot.signatures.item..'|'..snapshot.signatures.track..'|'..snapshot.signatures.ruler
  if T.published_serial~=T.serial or T.published_signature~=signature or T.published_context~=T.last_context then
   api.SetExtState(TRACKER,'project',tostring(snapshot.project),false)
   api.SetExtState(TRACKER,'kind',T.kind or '',false)
   for _,family in ipairs(kinds) do api.SetExtState(TRACKER,'signature_'..family,snapshot.signatures[family],false) end
   api.SetExtState(TRACKER,'cursor_context',tostring(T.last_context),false)
   T.published_serial,T.published_signature,T.published_context=T.serial,signature,T.last_context
  end
  if now>=(T.heartbeat_at or 0) then api.SetExtState(TRACKER,'heartbeat',tostring(now),false);T.heartbeat_at=now+.20 end
 end

 return T
end

local SelectionPerf={rows={}}
local selection_api=setmetatable({}, {__index=R})
for _,name in ipairs({'EnumProjects','JS_Mouse_GetState','GetCursorContext2','GetProjectStateChangeCount',
 'JS_Window_GetFocus','JS_Window_IsWindow','JS_Window_GetTitle','JS_Window_GetParent','GetMainHwnd',
 'GetMousePosition','JS_Window_FromPoint','GetThingFromPoint','GetItemFromPoint',
 'CountSelectedMediaItems','GetSelectedMediaItem','GetSetMediaItemInfo_String','CountSelectedTracks2',
 'GetSelectedTrack2','GetTrackGUID','GetNumRegionsOrMarkers','GetRegionOrMarker',
 'GetRegionOrMarkerInfo_Value','GetSetRegionOrMarkerInfo_String'}) do
 local row={name=name,total=0,count=0,maximum=0};SelectionPerf.rows[#SelectionPerf.rows+1]=row
 selection_api[name]=function(...)
  if not SelectionPerf.active then return R[name](...) end
  local started=R.time_precise()
  local a,b,c,d=R[name](...)
  local ms=(R.time_precise()-started)*1000
  row.total=row.total+ms;row.count=row.count+1;row.maximum=math.max(row.maximum,ms)
  return a,b,c,d
 end
end
function SelectionPerf.begin()
 for _,row in ipairs(SelectionPerf.rows) do row.total=0;row.count=0;row.maximum=0 end
 SelectionPerf.active=true
end
function SelectionPerf.report(elapsed)
 local rows={};local total=0
 for _,row in ipairs(SelectionPerf.rows) do
  total=total+row.total
  if row.count>0 then rows[#rows+1]=row end
 end
 table.sort(rows,function(a,b)return a.total>b.total end)
 local lines={}
 for i=1,math.min(10,#rows) do local row=rows[i]
  lines[#lines+1]=string.format('%s: 合計 %.2f ms / %d回 / 1回最大 %.2f ms',row.name,row.total,row.count,row.maximum)
 end
 lines[#lines+1]=string.format('Lua処理・その他: %.2f ms',math.max(0,elapsed-total))
 return table.concat(lines,'\n')
end
local Core=create_color_core(selection_api)
local Target=create_target_observer(selection_api,Core)
local target_ok=pcall(Target.start,true)
if not target_ok then R.MB('対象の選択状態を取得できません。選択を確認して再実行してください。','BLT COLOR PALETTE',0);return end
local min,max,floor,abs=math.min,math.max,math.floor,math.abs
local function clamp(v,a,b)return max(a,min(b,v))end
local finite=Core.finite
local saved_color=tonumber(R.GetExtState(SECTION,'color'))
local S={color=finite(saved_color) and math.floor(clamp(saved_color,0,0xFFFFFF)) or 0x80BFFF,close_after=R.GetExtState(SECTION,'close_after')=='1'}
local A={active=true,modal=false,busy=false,closing=false,closed=false,message='',bad=false,icon_pool={}}
local function notice(text,bad)
 A.message=tostring(text or '');A.bad=bad==true;A.message_until=R.time_precise()+6
end

-- BLT window geometry 1.0.0. Embedded; screen coordinates only.
local function create_window_geometry(api,graphics)
 local osname=api.GetOS() or ''
 if not osname:match('OSX') and not osname:match('macOS') then return api end
 local G=setmetatable({}, {__index=api})
 -- Internal screen Y points downward. Client coordinates remain untouched.
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
  -- SWELL SetWindowPos uses a bottom-left origin for floating macOS windows.
  return api.JS_Window_SetPosition(hwnd,x,-y-h,w,h,z,flags)
 end
 return G
end

local WindowGeometry=create_window_geometry(reaper,gfx)
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
 ["表示言語を切替（JP / EN）"]="Switch language (JP / EN)",
 ["CONTEXT COLOR  最後に選択した種類へ色を適用"]="CONTEXT COLOR  Apply to the last touched selection",
 ["対象"]="TARGET",
 ["対象の再選択が必要です"]="Reselect the target",
 ["この種類は対象外です"]="Unsupported selection type",
 ["対象を選択してください"]="Select a target",
 ["アイテム  %d個"]="ITEMS  %d",
 ["トラック  %d本"]="TRACKS  %d",
 ["マーカー %d個  /  リージョン %d個"]="MARKERS  %d  /  REGIONS  %d",
 ["カラーパレット"]="COLOR PALETTE",
 ["基本色"]="Basic",
 ["パステル"]="Pastel",
 ["ビビット"]="Vivid",
 ["ディープ"]="Deep",
 ["カメレオン"]="Chameleon",
 ["カメレオンは押した時だけREAPERテーマを読み取り、72色を生成します。再クリックで更新します。"]="Read the REAPER theme only when pressed, generate 72 colors, and click again to refresh.",
 ["パレットを切り替えます。選択色と対象は変更しません。"]="Switch palettes. Keep the selected color and targets.",
 ["REAPERテーマからカメレオンパレットを更新しました。"]="Chameleon palette refreshed from the REAPER theme.",
 ["適用色。ダブルクリックでREAPERのカラー選択を開きます。"]="Color to apply. Double-click to open the REAPER color chooser.",
 ["REAPERカスタムカラー"]="REAPER CUSTOM COLORS",
 ["実行後閉じる"]="Close after run",
 ["色を適用"]="Apply color",
 ["選択色をこの枠に登録"]="Store selected color here",
 ["REAPERのカラー設定を開く…"]="Open REAPER color settings...",
 ["右クリック：登録／設定"]="Right-click: store / settings",
 ["REAPERカスタムカラーへドラッグで登録"]="Drag to REAPER custom colors to store",
 ["未登録：クリックしてREAPERのカラー設定を開く"]="Uninitialized: click to open REAPER color settings",
 ["クリックしてREAPERのカラー設定を開いてください。"]="Click to initialize the native custom colors.",
 ["左クリック：色を選択  /  右クリック：選択色を登録  /  上の色をドラッグ＆ドロップ：登録"]="Left-click: select  /  Right-click: store selected color  /  Drag a palette color here to store",
 ["REAPERの標準カラー選択を開きます。"]="Open the native REAPER color chooser.",
 ["実行が成功したときだけウィンドウを閉じます。"]="Close the window only after successful execution.",
 ["表示中の対象すべてへ選択色を適用します。"]="Apply the selected color to all displayed targets.",
 ["選択履歴を確定できません。開いたまま対象を再クリックしてください。"]="Selection history is ambiguous. Re-click the target while this window stays open.",
 ["アイテム・トラック・マーカー／リージョンが対象です。"]="Supports items, tracks and markers/regions.",
 ["REAPERで対象を選択してください。"]="Select targets in REAPER.",
 ["対象の選択がありません。ほかの種類には適用しません。"]="No selection in this target type. Other types will not be changed.",
 ["色を選び、実行してください。Ctrl+Zで元に戻せます。"]="Choose a color, then run. Ctrl+Z to undo.",
 ["カラー選択を開けませんでした。"]="Could not open the color chooser.",
 ["REAPERカスタムカラー %02d に登録しました。"]="Stored in REAPER custom color %02d.",
 ["REAPERカスタムカラーを保存できませんでした。設定は再読み込みします。"]="Could not save REAPER custom colors. Reloading the settings.",
 ["すでに選択した色です。"]="Targets already have the selected color.",
 ["%d件の色を変更しました。"]="Changed colors for %d targets.",
 ["プロジェクトが変わったため中止しました。"]="Stopped because the project changed.",
 ["対象の選択が変わりました。表示を確認して再実行してください。"]="Selection changed. Check the preview and run again.",
 ["選択した色が不正です。"]="Invalid selected color.",
 ["対象を確認できません。選択し直してください。"]="Cannot verify targets. Reselect them.",
 ["色の変更に失敗したため、元の色へ戻しました。"]="Color update failed. Original colors restored.",
 ["元の色へ戻せない項目があります。REAPERのUndoで確認してください。"]="Some colors could not be restored. Check REAPER Undo.",
 ["色を変更できませんでした。"]="Could not change colors.",
 ["処理中にエラーが発生しました。対象を選択し直してください。"]="An error occurred. Reselect the target.",
 ["元に戻しました。"]="Undone.",
 ["元に戻せる操作がありません。"]="Nothing to undo.",
 ["Undoを実行できませんでした。"]="Undo failed.",
 ["処理中は元に戻せません。"]="Cannot undo during processing.",
},prefixes={'プリセットを保存しました: ','プリセットを読み込みました: ','現在: '},patterns={
 {'^「(.*)」を上書きしますか？$','Overwrite "%s"?'},
 {'^(%d+)個インポートしました。$','Imported %d preset(s).'},
 {'^(%d+)件の色を変更しました。$','Changed colors for %d targets.'}
}}
local Language=create_language(R,SECTION,LanguageCatalog)

-- BLT preset transfer limits 1.1.0. Embedded; no runtime dependency.
local BLTPresetLimits={bytes=16777216,stringBytes=2097152,nodes=262144,entries=8192}
function BLTPresetLimits.show(english)
 reaper.MB(english and 'Preset capacity limit exceeded. Export presets individually instead of as a bundle.' or '容量上限オーバーです。一括ではなく個別に保存してください。','BLT PRESET',0)
end


-- BLT primary button 1.0.0. Embedded; no runtime file dependency.
local PrimaryButton=(function()
 local P={state={hover=0},nextFrame=0}
 local sin,pi,min,max=math.sin,math.pi,math.min,math.max
 -- Same emitter, lifetime, trajectory, clipping and three glow layers as LOUDNESS TRACE.
 -- Reuse expired particle records without changing insertion or drawing order.
 function P.drawParticles(d,s,x,y,w,h,hover,analyzing,realDt,animationDt,mx,my)
  local C=d.C;local ice=C.accent2 or C.ice
  if not s.particles then s.particles={};s.pool={};s.serial=0;s.particleClock=0 end
  local particles,pool=s.particles,s.pool
  if hover or analyzing then
   s.particleClock=s.particleClock+(analyzing and realDt or animationDt)
   local interval=analyzing and .030 or .055
   local cap=analyzing and 66 or 44
   while s.particleClock>=interval and #particles<cap do
    s.particleClock=s.particleClock-interval;s.serial=s.serial+1
    local n=s.serial;local h1=(sin(n*12.9898)*43758.5453)%1
    local h2=(sin(n*78.233)*12345.6789)%1
    local px,py
    if analyzing then px=x+12+h1*(w-24);py=y+h-7-h2*8
    else px=mx+(h1-.5)*7;py=my+(h2-.5)*5 end
    local p=pool[#pool]
    if p then pool[#pool]=nil else p={} end
    p.x=px;p.y=py;p.age=0;p.life=analyzing and (.65+h1*.65) or (1.6+h1*1.2)
    p.vx=(h2-.5)*(analyzing and 15 or 7);p.vy=analyzing and (10+h1*14) or (6+h1*8);p.phase=h2*pi*2
    particles[#particles+1]=p
   end
  else s.particleClock=min(s.particleClock,.04) end
  for i=#particles,1,-1 do
   local p=particles[i];p.age=p.age+realDt
   if p.age>=p.life then table.remove(particles,i);pool[#pool+1]=p
   else
    local px=p.x+p.vx*p.age+sin(p.age*1.6+p.phase)*2;local py=p.y-p.vy*p.age
    local e=sin(pi*p.age/p.life)^2
    if px>x+3 and px<x+w-3 and py>y+3 and py<y+h-3 then
     d.disc(px,py,analyzing and 4.4 or 3.7,C.accent,(analyzing and .035 or .02)*e)
     d.disc(px,py,analyzing and 2.2 or 1.9,ice,(analyzing and .10 or .065)*e)
     d.disc(px,py,analyzing and .85 or .7,ice,(analyzing and .78 or .58)*e)
    end
   end
  end
 end
 -- All coordinates are host design units. Hit testing and actions stay with the host.
 function P.draw(d,x,y,w,h,title,caption,enabled,busy,progress,hover,pressed,now,active)
  local s=P.state;local C=d.C;local live=active~=false
  enabled=enabled~=false;busy=busy==true;hover=hover and enabled and live
  local dt=min(.1,max(0,now-(s.time or now)));s.time=now
  local target=(hover or busy) and 1 or 0
  s.hover=s.hover+(target-s.hover)*min(1,dt*14)
  if math.abs(target-s.hover)<.002 then s.hover=target end
  if s.busy and not busy then s.flashUntil=now+.45 end
  s.busy=busy;s.hot=hover;s.live=live
  local a=s.hover;local pulse=busy and live and (.5+.5*sin(now*5.2)) or 0
  local shift=pressed and enabled and 1.5 or 0;y=y+shift
  local deep=C.accent3 or C.deep;local ice=C.accent2 or C.ice
  local edge=(enabled or busy) and ice or C.muted
  -- LOUDNESS TRACE's glass face, lit top/left edges and diagonal corners.
  if enabled or busy then
   d.gradient(x,y,w,h,deep,C.field,.22+.12*a+(busy and .10*pulse or 0),.92)
   if a>.01 then d.gradient(x,y,w,h,C.accent,deep,busy and (.20+.10*pulse) or .13*a,.01,true) end
  else
   d.gradient(x,y,w,h,C.field,C.field,.92,.92)
  end
  d.gradient(x,y,w,busy and 2 or 1,edge,edge,(enabled or busy) and (.62+.28*a) or .18,.03)
  d.line(x,y+h,x+w,y+h,busy and ice or C.edge,busy and (.52+.20*pulse) or (enabled and .48 or .14))
  d.line(x,y,x,y+h,edge,(enabled or busy) and (.66+.18*pulse) or .13)
  d.corners(x,y,w,h,min(10,h/3),true,edge,(enabled or busy) and (.68+.18*pulse) or .18)
  local mx,my,speed=d.motion(now)
  s.emitting=busy or (hover and live and speed>0)
  P.drawParticles(d,s,x,y,w,h,hover,busy,dt,live and dt*speed or 0,mx,my)
  if s.flashUntil and now<s.flashUntil and live then
   local flash=((s.flashUntil-now)/.45)^2
   d.rect(x+1,y+1,w-2,h-2,ice,.07*flash)
   d.line(x,y,x+w,y,ice,.6*flash)
  end
  local top=caption or 'EXECUTE'
  if not enabled and not busy then top='WAIT' end
  if type(progress)=='number' then
   progress=max(0,min(1,progress))
   top=top..'  '..math.floor(progress*100+.5)..'%'
   d.rect(x+4,y+h-5,w-8,2,C.edge,.45)
   if progress>0 then d.rect(x+4,y+h-5,(w-8)*progress,2,ice,.8) end
  end
  -- Center the same two-line typography within each application's existing size.
  local topY=y+(h-42)/2+3
  d.label(top,x+10,topY,8,(enabled or busy) and ice or C.faint,3,w-20,12,5,false)
  d.label(title,x+10,topY+14,15,(enabled or busy) and C.text or C.muted,1,w-20,21,5,false)
 end
 function P.tick(now,active,wake)
  local s=P.state
  local tail=s.particles and #s.particles>0
  local fading=s.hover>.002 and s.hover<.998 or (not s.hot and not s.busy and s.hover>.002)
  if (tail or s.busy or (active and s.live and (s.emitting or fading or (s.flashUntil and now<s.flashUntil)))) and now>=P.nextFrame then
   P.nextFrame=now+(tail and not s.hot and not s.busy and 1/20 or 1/30);wake()
  end
 end
 return P
end)()


-- BLT shared shell 3.2.0. Embedded at build time; no runtime module dependency.
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
 -- Whitelisted views are reused; never serialize settings in the draw path.
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
 local compact=host.compactChrome and host.compactChrome() or false
 local c=B.barCache;if c and c.width==w and c.compact==compact then return c end
 local b={width=w,closeX=w-38,resetX=w-72,themeX=w-106}
 b.foldX=host.fold and b.themeX-34 or nil;b.languageX=(b.foldX or b.themeX)-26;b.nextX=b.languageX-20;b.prevX=b.nextX-20;b.presetX=b.prevX-84
 b.compact=compact
 if compact then b.resetX=b.closeX;b.themeX=w-72;b.foldX=w-106;b.languageX=w+500;b.nextX=w+500;b.prevX=w+500;b.presetX=w+500 end
 B.barCache=b;return b
end
local function gfx_window_handle() return host.handle() end
local function chrome_resize_hit(x,y) if y<26 and x>=UI.bar(gfx.w).presetX then return nil end;return host.resizeHit(x,y) end
local function set_resize_cursor(mode) host.cursor(mode) end
local function begin_window_resize(mode) host.beginResize(mode) end
local function update_window_resize() host.resize() end
local function clear_chrome_tooltip() B.popupUntil=nil;if R.TrackCtl_SetToolTip then R.TrackCtl_SetToolTip('',0,0,true) end end
B.clearTooltip=clear_chrome_tooltip
function B.switch(x,y,state,enabled)
 local s,bx,by=host.geometry();local cy=by+(y+12)*s;local cx=bx+(x+7+12*state)*s
 local c=C.edge2;gfx.set(c[1],c[2],c[3],enabled and .45 or .2);gfx.line(bx+(x+3)*s,cy,bx+(x+23)*s,cy,1)
 c=C.faint;gfx.set(c[1],c[2],c[3],enabled and .8 or .4);gfx.circle(cx,cy,4.2*s,1,1)
 if state>.001 and enabled then c=C.accent;gfx.set(c[1],c[2],c[3],.06*state);gfx.circle(cx,cy,7*s,1,1);c=C.accent2;gfx.set(c[1],c[2],c[3],.94*state);gfx.circle(cx,cy,4.2*s,1,1) end
end
function B.blend(dt)
 if B.blendDt~=dt then B.blendDt=dt;B.blendValue=1-math.exp(-12*dt) end
 return B.blendValue
end
function Presets.menu(x,y)
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
  -- Hover only opens the preset list, never applies a preset automatically.
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
  local inBar=host.active() and not blocked and inWindow and my<Chrome.titleH
  local resizeMode=not blocked and chrome_resize_hit(mx,my) or nil
  local resizing=Chrome.resize~=nil
  local cursorMode=resizing and Chrome.resize.mode or resizeMode
  set_resize_cursor(cursorMode)
  local hoverClose=inBar and mx>=closeX and mx<w and not resizeMode and not resizing
  local hoverReset=not (host.collapsed and host.collapsed()) and not (host.transition and host.transition()) and inBar and mx>=resetX and mx<closeX and not resizeMode and not resizing
  local hoverCham=inBar and mx>=chamX and mx<resetX and not resizeMode and not resizing
  local hoverPreset=inBar and mx>=presetX and mx<prevX and not resizeMode and not resizing
  local hoverPrev=inBar and mx>=prevX and mx<nextX and not resizeMode and not resizing
  local hoverNext=inBar and mx>=nextX and mx<languageX and not resizeMode and not resizing
  local hoverFold=foldX and not (host.transition and host.transition()) and inBar and mx>=foldX and mx<chamX and not resizeMode and not resizing
  local hoverLanguage=inBar and mx>=languageX and mx<(foldX or chamX) and not resizeMode and not resizing
  local down=not blocked and (gfx.mouse_cap&1)~=0
  -- A content modal disables chrome; it does not give chrome ownership of its input.
  Chrome.mouseActive=(Presets.open or Presets.swallow) or inBar or Chrome.drag~=nil or Chrome.resize~=nil or cursorMode~=nil
    or Chrome.languagePressed or Chrome.closePressed or Chrome.resetPressed or Chrome.chameleonPressed or Chrome.presetPressed or Chrome.presetPrevPressed or Chrome.presetNextPressed

  gfx.set(C.bg[1],C.bg[2],C.bg[3],1); gfx.rect(0,0,w,Chrome.titleH,1)
  gfx.gradrect(0,0,w,Chrome.titleH,C.field[1],C.field[2],C.field[3],.72,
    0,0,0,0,(C.bg[1]-C.field[1])/Chrome.titleH,(C.bg[2]-C.field[2])/Chrome.titleH,(C.bg[3]-C.field[3])/Chrome.titleH,.22/Chrome.titleH)
  gfx.set(C.edge[1],C.edge[2],C.edge[3],.42); gfx.line(0,Chrome.titleH-1,w,Chrome.titleH-1,1)

  if not Chrome.textFontsReady or Chrome.fontDPI~=(gfx.ext_retina or 1) then Chrome.fontDPI=gfx.ext_retina or 1;B.chromeFont(); Chrome.textFontsReady=true else B.chromeFont() end; B.fontKey="chrome"
  -- Center the unadorned title within the bar using the actual font height.
  local _,titleHeight=UI.textMetrics(Chrome.titleText)
  local ty=math.floor((Chrome.titleH-titleHeight)*.5)
  gfx.set(Chrome.mint[1],Chrome.mint[2],Chrome.mint[3],.88); gfx.x=14; gfx.y=ty; gfx.drawstr(UI.fit(Chrome.titleText,math.max(0,(b.compact and b.foldX or presetX)-22)))

  if not b.compact then
  if hoverPreset or Presets.open then
    gfx.set(C.accent[1],C.accent[2],C.accent[3],.10);gfx.rect(presetX+2,3,78,20,1)
  end
  gfx.set(C.edge[1],C.edge[2],C.edge[3],(hoverPreset or hoverPrev or hoverNext) and .9 or .5)
  gfx.roundrect(presetX+2,3,languageX-presetX-5,20,3,1)
  gfx.set(C.muted[1],C.muted[2],C.muted[3],.35);gfx.line(languageX-1,6,languageX-1,20)
  local pc=hoverPreset and Chrome.mint or C.muted
  gfx.set(pc[1],pc[2],pc[3],hoverPreset and .98 or .8)
  gfx.roundrect(presetX+10,7,7,8,1,1);gfx.roundrect(presetX+13,10,7,8,1,1)
  B.chromeFont();B.fontKey="chrome"
  gfx.x=presetX+26;gfx.y=7;gfx.drawstr("PRESET")
  gfx.line(presetX+67,11,presetX+70,14);gfx.line(presetX+70,14,presetX+73,11)
  if Presets.dirty() then gfx.set(C.warn[1],C.warn[2],C.warn[3],.9);gfx.circle(presetX+23,6,1.3,1,1) end

  B.arrows=B.arrows or {{},{}}
  local left,right=B.arrows[1],B.arrows[2]
  left[1],left[2],left[3]=prevX,hoverPrev,-1;right[1],right[2],right[3]=nextX,hoverNext,1
  for _,arrow in ipairs(B.arrows) do
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
  B.font(13,2,true,1,host.faces)
  local lw,lh=UI.textMetrics(Language.code)
  gfx.x=languageX+(26-lw)/2;gfx.y=(Chrome.titleH-lh)/2;gfx.drawstr(Language.code)
  end -- full-size preset and language controls
  if foldX then
    gfx.set(C.accent2[1],C.accent2[2],C.accent2[3],hoverFold and .98 or .8)
    local cx,cy=foldX+17,13;local d=host.collapsed() and 1 or -1
    gfx.line(cx-6,cy-5,cx+6,cy-5);gfx.line(cx-4,cy-d*3,cx,cy+d);gfx.line(cx,cy+d,cx+4,cy-d*3)
  end
  if hoverCham or Chameleon.enabled then
    local a=hoverCham and .095 or .045
    gfx.set(C.accent[1],C.accent[2],C.accent[3],a); gfx.rect(chamX,0,chamW,Chrome.titleH,1)
    gfx.set(C.accent2[1],C.accent2[2],C.accent2[3],hoverCham and .42 or .24)
    gfx.line(chamX,Chrome.titleH-1,resetX,Chrome.titleH-1,1)
  end
  local chx,chy=chamX+chamW*.5,Chrome.titleH*.5
  local active_a=hoverCham and 1 or (Chameleon.enabled and .96 or .85)

  -- Theme / mimicry icon:
  -- three overlapping color fields, visually reading as "take on / blend into
  -- surrounding colors" rather than as a literal animal.
  local c1,c2,c3=Chameleon.icon_colors()

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
 scale,ox,oy=host.geometry()
 local blocked=not B.recoveryMode and (Presets.open or Presets.swallow or host.modal())
 custom_titlebar(blocked)
 Presets.draw()
end

-- Preserve title-bar button edges across repeated application failures.
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
 gfx.dest=-1;gfx.mode=0;gfx.a=1
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
 pcall(B.footer,B.publicError(err),true,gfx.w,0,B.footerVersion or '')
 pcall(gfx.update)
 if Chrome.requestClose then state.closing=true end
 state.content_dirty=true
 B.cleanup(host.wake)
 B.logError(err)
end

function B.title(title,subtitle,width,divider)
 scale,ox,oy=host.geometry();local origin=oy+22*scale
 B.font(35,2,true,scale,host.faces);gfx.set(C.text[1],C.text[2],C.text[3],1);gfx.x=ox+24*scale;gfx.y=origin+8*scale;gfx.drawstr(UI.fit(title,(width-150)*scale))
 B.font(10,1,false,scale,host.faces);gfx.set(C.accent2[1],C.accent2[2],C.accent2[3],1);gfx.x=ox+26*scale;gfx.y=origin+44*scale;gfx.drawstr(UI.fit(Language.text(subtitle),(width-155)*scale))
 if divider~=false then gfx.set(C.edge2[1],C.edge2[2],C.edge2[3],.26);gfx.line(ox+24*scale,origin+62*scale,ox+(width-24)*scale,origin+62*scale,1) end
end
function B.footer(message,bad,width,height,version,progress)
 if version~='' then B.footerVersion=version end
 scale,ox,oy=host.geometry();message=Language.message(B.notice or tostring(message or ''))
 if B.notice then bad=B.noticeBad end
 local y=oy+(height-13)*scale
 B.font(8,3,true,scale,host.faces);local ver=version~='' and 'v'..version or '';local vw=UI.textMetrics(ver)
 local available=(width-48)*scale-vw-14*scale
 local progressing=type(progress)=='number'
 B.font(9,1,false,scale,host.faces);local shown=progressing and '' or UI.fit(message,available)
 B.footerText=progressing and '' or message;B.footerClipped=not progressing and shown~=message;B.footerBounds={ox+24*scale,y,ox+24*scale+available,y+14*scale}
 gfx.set(C.edge[1],C.edge[2],C.edge[3],.26);gfx.line(ox+24*scale,y-3*scale,ox+(width-24)*scale,y-3*scale)
 if progressing then
  local fraction=math.max(0,math.min(1,progress))
  -- Reserve the widest caption so the track stays still as the percentage changes.
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
end
return B
end)()


local W,H=527,475
local Layout={
 target={x=24,y=94,w=W-48,h=28},
 tabs={x=24,y=130,w=W-48,h=26,gap=4},
 palette={x=25,y=164,w=W-50,h=20,columns=12,gap_x=5,gap_y=5},
 custom_title_y=321,
 custom={x=25,y=345,w=W-50,h=23,columns=8,gap_x=5,gap_y=5},
 custom_hint_y=400,
 close_after={x=24,y=434,w=142,h=28},
 preview={x=178,y=423,w=130,h=50},
 apply={x=327,y=423,w=W-351,h=50},
}
local C={
  bg={0.018,0.030,0.055}, bg2={0.030,0.090,0.180},
  panel={0.040,0.068,0.110}, panel2={0.055,0.125,0.205},
  field={0.018,0.040,0.080}, edge={0.145,0.285,0.445}, edge2={0.360,0.650,0.900},
  text={0.955,0.980,1.000}, muted={0.690,0.780,0.875}, faint={0.390,0.505,0.635},
  accent={0.120,0.490,0.980}, accent2={0.650,0.895,1.000}, accent3={0.045,0.235,0.520},
  focus={0.225,0.610,1.000}, focus2={0.690,0.900,1.000}, ink={0.018,0.075,0.160},
  hover={0.430,0.790,1.000}, warn={1.000,0.755,0.490}, red={1.000,0.230,0.300}, quiet={0.300,0.360,0.440},
  green={0.510,0.860,0.740}
}
local fonts={"Yu Gothic UI","Segoe UI","Consolas"}
local os=R.GetOS()
if os:match("OSX") or os:match("macOS") then fonts={"Hiragino Sans","Helvetica Neue","Menlo"}
elseif not os:match("Win") then fonts={"sans-serif","sans-serif","monospace"} end

local scale,ox,oy=1,0,0
 BLT.viewport(scale,gfx.ext_retina or 1);local mx,my=-1,-1
local widgets,hover,last_down={},"",false
local frame_clock,frame_dt,particle_dt,anim_time=R.time_precise(),1/60,1/60,0
local animations_active=true
local animation_speed=1
local EFFECT_IDLE_TAIL=2.5
local EFFECT_COAST=0.70
local effect_activity_until=R.time_precise()+EFFECT_IDLE_TAIL
local redraw_dirty=true
local next_draw_time=0
local last_raw_mouse_x,last_raw_mouse_y,last_raw_mouse_cap=nil,nil,nil
local last_window_w,last_window_h=nil,nil
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
local motion={}
local icon_particles,icon_clock,icon_serial={},0,0

local function sx(x) return ox+x*scale end
local function sy(y) return oy+y*scale end
local function color(c,a) gfx.set(c[1],c[2],c[3],a or 1) end
local function rect(x,y,w,h,c,a) color(c,a); gfx.rect(sx(x),sy(y),w*scale,h*scale,1) end
local function line(x,y,x2,y2,c,a) color(c,a); gfx.line(sx(x),sy(y),sx(x2),sy(y2),1) end
local function disc(x,y,r,c,a) color(c,a); gfx.circle(sx(x),sy(y),r*scale,1,1) end

local function font(size,kind,bold) BLT.font(size,kind,bold,scale,fonts) end
local text_queue={buckets={},order={},count=0}
local function reset_text_queue()
 for i=1,text_queue.count do
  local b=text_queue.order[i]
  for j=1,b.count do b[j].text=nil;b[j].c=nil end
  b.count=0
 end
 text_queue.count=0
end
local function label(text,x,y,size,c,kind,w,h,flags,bold,literal)
 local shown=literal and tostring(text) or Language.message(text)
 local fk,_,_,key=BLT.spec(size,kind,bold,scale)
 local bucket=text_queue.buckets[key]
 if not bucket then bucket={count=0};text_queue.buckets[key]=bucket end
 if bucket.count==0 then text_queue.count=text_queue.count+1;text_queue.order[text_queue.count]=bucket end
 bucket.count=bucket.count+1
 local cmd=bucket[bucket.count] or {};bucket[bucket.count]=cmd
 cmd.text=shown;cmd.size=size;cmd.kind=fk;cmd.bold=bold;cmd.c=c or C.text
 cmd.x=sx(x);cmd.y=sy(y);cmd.right=sx(x+(w or 700));cmd.bottom=sy(y+(h or size+8))
 cmd.width=w and w*scale;cmd.flags=flags or 0
end
local function flush_text_queue()
 for i=1,text_queue.count do
  local b=text_queue.order[i];local first=b[1]
  font(first.size,first.kind,first.bold)
  for j=1,b.count do
   local cmd=b[j];color(cmd.c);gfx.x,gfx.y=cmd.x,cmd.y
   local shown=cmd.width and BLT.ui.fit(cmd.text,cmd.width) or cmd.text
   gfx.drawstr(shown,cmd.flags,cmd.right,cmd.bottom)
  end
 end
 reset_text_queue()
end
local function measure(text,size,kind,bold) font(size,kind,bold);return BLT.metricsFor(Language.message(text))/scale end
local function right_label(text,right,y,size,c,kind,bold)
  local tw=measure(text,size,kind,bold); label(text,right-tw,y,size,c,kind,tw+2,size+9,0,bold)
end
local function gradient(x,y,w,h,a,b,alpha1,alpha2,vertical)
  local aa1=alpha1 or 1; local aa2=alpha2==nil and aa1 or alpha2
  local n=max(1,(vertical and h or w)*scale)
  if (a==b or (a[1]==b[1] and a[2]==b[2] and a[3]==b[3])) and aa1==aa2 then rect(x,y,w,h,a,aa1); return end
  if n<=1.01 then rect(x,y,w,h,a,aa1); return end
  local dr,dg,db=(b[1]-a[1])/n,(b[2]-a[2])/n,(b[3]-a[3])/n
  local da=(aa2-aa1)/n
  gfx.gradrect(sx(x),sy(y),w*scale,h*scale,a[1],a[2],a[3],aa1,
    vertical and 0 or dr,vertical and 0 or dg,vertical and 0 or db,vertical and 0 or da,
    vertical and dr or 0,vertical and dg or 0,vertical and db or 0,vertical and da or 0)
end

local function cut_panel(x,y,w,h,cut,c,a,edge,edge_a,top_left)
  local tl=top_left and cut or 0
  local pts={{x+tl,y},{x+w,y},{x+w,y+h-cut},{x+w-cut,y+h},{x,y+h},{x,y+tl}}
  local cx,cy=x+w/2,y+h/2
  color(c,a)
  for i=1,#pts do local p,q=pts[i],pts[i%#pts+1]; gfx.triangle(sx(cx),sy(cy),sx(p[1]),sy(p[2]),sx(q[1]),sy(q[2])) end
  if edge then for i=1,#pts do local p,q=pts[i],pts[i%#pts+1]; line(p[1],p[2],q[1],q[2],edge,edge_a or 1) end end
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
local function particle_hash(n,salt)
  local v=math.sin(n*12.9898+salt*78.233)*43758.5453; return v-floor(v)
end
local function inside(x,y,w,h) return mx>=x and mx<=x+w and my>=y and my<=y+h end
local function widget(id,x,y,w,h,fn,hint,enabled)
  widgets[#widgets+1]={id=id,x=x,y=y,w=w,h=h,fn=fn,hint=hint,enabled=enabled~=false}
  if inside(x,y,w,h) and hint then hover=hint end
end


local chameleon_host_refresh=nil
local C_DEFAULT={}
for k,v in pairs(C) do
  if type(v)=="table" and type(v[1])=="number" and type(v[2])=="number" and type(v[3])=="number" then
    C_DEFAULT[k]={v[1],v[2],v[3]}
  end
end
local Chameleon={
  enabled=R.GetExtState(SECTION,"chameleon")=="1",
  signature=nil,poll_at=0,poll_interval=3.0,
}
local Chrome={window=nil,mouseDown=false,drag=nil,resize=nil,mouseActive=false,requestClose=false,requestReset=false,
  chameleonPressed=false,resizeCursors={},resizeCursorMode=nil,titleH=26,windowTitle='BLT Color Palette',titleText='C O L O R   P A L E T T E',
  minW=442,minH=425,mint={0.38,0.88,0.72},ice={0.65,0.895,1.0},red={1.0,0.27,0.34},
  isWindows=R.GetOS():match("Win")~=nil,resizeEdge=6,resizeCornerBand=8,resizeCornerSpan=24,resizeTopLeftGuard=30,resizeTopRightGuard=110,
  tooltipHover=nil,tooltipSince=0,tooltipVisible=false,tooltipDelay=.70,
  cursorId={we=32644,ns=32645,nwse=32642,nesw=32643,arrow=32512}}
Chrome.font=Chrome.isWindows and "Segoe UI" or (BLT_MAC and "Helvetica Neue" or "sans-serif")
local CHROME_DEFAULT={
  mint={Chrome.mint[1],Chrome.mint[2],Chrome.mint[3]},
  ice={Chrome.ice[1],Chrome.ice[2],Chrome.ice[3]},
}
local function chameleon_notify(text)
  notice(text,false)
end

do
-- CHAMELEON THEME ADAPTER
--
-- Theme adapter interface:
--   Required palette tables : C, C_DEFAULT
--   Optional chrome colors   : Chrome, CHROME_DEFAULT
--   Persistence              : SECTION / ExtState key "chameleon"
--   Host hooks               : notice(), wake_visuals(), redraw_dirty
--   UI integration           : Chameleon.enabled / Chameleon.set(...)
--   Main-loop integration    : Chameleon.tick(now)
--
Chameleon.keys={
  -- Main/surface colors
  "col_main_bg2","col_main_bg","col_arrangebg","col_tracklistbg","col_mixerbg",
  "genlist_bg","col_tl_bg","col_trans_bg","col_tr1_bg","col_tr2_bg",
  "col_main_editbk","col_transport_editbk","col_buttonbg",

  -- Text colors
  "col_main_text2","col_main_text","genlist_fg","col_tcp_text",
  "col_toolbar_text","col_toolbar_text_on","col_tl_fg","col_tl_fg2","col_trans_fg",

  -- Selection / active / accent colors
  "col_seltrack","col_seltrack2","genlist_selbg",
  "col_tl_bgsel","toolbararmed_color","col_main_resize2",
  "selitem_dot","selitem_tag","activetake_tag",
  "col_routinghl1","col_routinghl2","track_lanesolo_tabcol",

  -- REAPER's own highlight / shadow / separators
  "col_main_3dhl","col_main_3dsh","genlist_grid","col_toolbar_frame",
  "col_tr1_divline","col_tr2_divline","docker_shadow",
}
local function ccopy(c) return {c[1],c[2],c[3]} end
local function cmix(a,b,t)
  t=math.max(0,math.min(1,t or 0))
  return {a[1]+(b[1]-a[1])*t,a[2]+(b[2]-a[2])*t,a[3]+(b[3]-a[3])*t}
end
local function clum(c) return c[1]*0.2126+c[2]*0.7152+c[3]*0.0722 end
local function csat(c)
  local hi=math.max(c[1],c[2],c[3]); local lo=math.min(c[1],c[2],c[3])
  return hi-lo
end
local function cclamp(c)
  return {
    math.max(0,math.min(1,c[1])),
    math.max(0,math.min(1,c[2])),
    math.max(0,math.min(1,c[3])),
  }
end
local function cshift_luma(c,target)
  local l=clum(c)
  target=math.max(0,math.min(1,target))
  if math.abs(target-l)<1e-5 then return ccopy(c) end
  if target<l then
    local t=(l-target)/math.max(l,1e-9)
    return cmix(c,{0,0,0},t)
  end
  local t=(target-l)/math.max(1-l,1e-9)
  return cmix(c,{1,1,1},t)
end
local function cboost_sat(c,factor)
  local l=clum(c)
  return cclamp({
    l+(c[1]-l)*factor,
    l+(c[2]-l)*factor,
    l+(c[3]-l)*factor,
  })
end
local function dominant_surface(colors,fallback)
  local list={}
  for i=1,#colors do
    local c=colors[i]
    if c then list[#list+1]={c=c,l=clum(c)} end
  end
  if #list==0 then return ccopy(fallback) end
  table.sort(list,function(a,b) return a.l<b.l end)
  local median
  local n=#list
  if n%2==1 then median=list[(n+1)//2].l
  else median=(list[n//2].l+list[n//2+1].l)*.5 end
  local best,bestd=list[1],math.huge
  for i=1,n do
    local d=math.abs(list[i].l-median)
    if d<bestd then best,bestd=list[i],d end
  end
  return ccopy(best.c)
end
local function generated_text(bg)
  -- Text polarity follows the ACTUAL palette background, not a theme text slot.
  -- This guarantees black-ish text on light themes and white-ish text on dark themes.
  local l=clum(bg)
  if l>=0.56 then
    return {0.070,0.075,0.082},false
  elseif l<=0.44 then
    return {0.935,0.945,0.958},true
  end
  -- Mid-grey themes: choose the side with the larger luminance separation.
  if l>=0.50 then return {0.075,0.080,0.088},false end
  return {0.935,0.945,0.958},true
end
local function fit_accent_to_bg(accent,bg,text_is_light)
  local out=ccopy(accent)
  local delta=math.abs(clum(out)-clum(bg))
  if delta>=0.17 then return out end
  if text_is_light then
    -- Dark background: lift the accent without washing it toward full white.
    local target=math.min(.78,clum(bg)+.28)
    return cshift_luma(out,target)
  end
  -- Light background: darken the accent so controls remain visible.
  local target=math.max(.16,clum(bg)-.30)
  return cshift_luma(out,target)
end
local function contrast_anchor_bg(bg)
  local l=clum(bg)
  if l<0.50 then
    local target=math.max(.025,l-(.50-l)*.16-.018)
    return cshift_luma(bg,target)
  end
  local target=math.min(.975,l+(l-.50)*.10+.010)
  return cshift_luma(bg,target)
end
local function contrast_surface(c,old_bg,new_bg,factor,min_gap,max_gap)
  local delta=clum(c)-clum(old_bg)
  local sign=delta<0 and -1 or 1
  local mag=math.abs(delta)*factor
  if min_gap and mag<min_gap then mag=min_gap end
  if max_gap and mag>max_gap then mag=max_gap end
  return cshift_luma(c,math.max(.01,math.min(.99,clum(new_bg)+sign*mag)))
end
local function theme_color(key)
  local ok,native=pcall(R.GetThemeColor,key,0)
  if not ok or type(native)~="number" or native==-1 then return nil,native end
  local okc,r,g,b=pcall(R.ColorFromNative,native)
  if not okc or type(r)~="number" or type(g)~="number" or type(b)~="number" then return nil,native end
  return {r/255,g/255,b/255},native
end
local function first_near(map,bg,keys,max_delta)
  for i=1,#keys do
    local c=map[keys[i]]
    if c and math.abs(clum(c)-clum(bg))<=(max_delta or .18) then return ccopy(c) end
  end
  return nil
end
local function best_contrast_color(map,bg,keys,min_delta)
  local bg_l=clum(bg)
  local best,best_score=nil,-1
  for i=1,#keys do
    local c=map[keys[i]]
    if c then
      local delta=math.abs(clum(c)-bg_l)
      if delta>=(min_delta or 0) then
        local score=delta+csat(c)*.20
        if score>best_score then best,best_score=c,score end
      end
    end
  end
  return best and ccopy(best) or nil
end
local function theme_edge_role(map,bg,dark,highlight)
  local keys
  if highlight then
    keys={"col_main_3dhl","col_toolbar_frame","genlist_grid","col_tl_fg2","col_tr1_divline","col_tr2_divline"}
  else
    keys={"col_main_3dsh","docker_shadow","genlist_grid","col_tr1_divline","col_tr2_divline"}
  end
  local bg_l=clum(bg)
  local best,best_score=nil,-1
  for i=1,#keys do
    local c=map[keys[i]]
    if c then
      local delta=clum(c)-bg_l
      local wanted=highlight and (dark and delta>0 or (not dark and delta<0))
        or (dark and delta<0 or (not dark and delta>0))
      local score=math.abs(delta)+(wanted and .16 or 0)
      if score>best_score then best,best_score=c,score end
    end
  end
  return best and ccopy(best) or nil
end
local function usable_theme_text(map,bg,keys,generated)
  local c=best_contrast_color(map,bg,keys,.28)
  if not c then return ccopy(generated) end
  -- Never let a theme text slot invert into poor contrast after user transforms.
  if math.abs(clum(c)-clum(bg))<.28 then return ccopy(generated) end
  return c
end

local function best_theme_accent(map,bg)
  local keys={
    "genlist_selbg","col_seltrack","toolbararmed_color","col_tl_bgsel",
    "col_toolbar_text_on","col_main_resize2","selitem_dot","selitem_tag",
    "activetake_tag","col_routinghl1","col_routinghl2","track_lanesolo_tabcol",
    "col_tl_fg",
  }
  local bg_l=clum(bg)
  local best,best_score=nil,-1
  for i=1,#keys do
    local c=map[keys[i]]
    if c then
      local sat=csat(c)
      local delta=math.abs(clum(c)-bg_l)
      local score=sat*1.45+delta*.72
      if keys[i]=="genlist_selbg" or keys[i]=="col_seltrack" or keys[i]=="toolbararmed_color" then
        score=score+.12
      end
      -- Ignore almost-background colors unless no better candidate exists.
      if delta<.035 and sat<.035 then score=score-.35 end
      if score>best_score then best,best_score=c,score end
    end
  end
  return best and ccopy(best) or ccopy(C_DEFAULT.accent)
end
local function theme_snapshot()
  local map,raw={},{}
  for i=1,#Chameleon.keys do
    local key=Chameleon.keys[i]
    local c,native=theme_color(key)
    map[key]=c
    raw[#raw+1]=tostring(native or -1)
  end
  return map,table.concat(raw,":")
end
local function build_chameleon_palette(map)
  -- Derive a stable BLT palette from REAPER's current theme.
  -- Missing/unsupported keys are ignored and each semantic role has a safe
  -- fallback, which is important for custom and older themes.
  local sampled_bg=dominant_surface({
    map.col_main_bg2,
    map.col_main_bg,
    map.col_tracklistbg,
    map.genlist_bg,
    map.col_arrangebg,
  },C_DEFAULT.bg)

  local sampled_l=clum(sampled_bg)
  local dark=sampled_l<0.50

  local sampled_panel=
    first_near(map,sampled_bg,{
      "col_main_bg","col_tracklistbg","col_mixerbg","genlist_bg",
      "col_seltrack2","col_tl_bg","col_tr1_bg","col_tr2_bg",
    },.16)

  local sampled_field=
    first_near(map,sampled_bg,{
      "col_main_editbk","col_transport_editbk","genlist_bg","col_buttonbg",
      "col_trans_bg",
    },.14)

  if not sampled_panel then
    sampled_panel=cshift_luma(sampled_bg,dark and math.min(.92,sampled_l+.040) or math.max(.08,sampled_l-.040))
  end
  if not sampled_field then
    sampled_field=cshift_luma(sampled_bg,dark and math.min(.92,sampled_l+.018) or math.min(.96,sampled_l+.020))
  end
  local bg=contrast_anchor_bg(sampled_bg)
  local panel=contrast_surface(sampled_panel,sampled_bg,bg,1.48,.030,.105)
  local field=contrast_surface(sampled_field,sampled_bg,bg,1.38,.020,.085)

  if dark then
    if clum(panel)<=clum(bg)+.022 then panel=cshift_luma(panel,math.min(.94,clum(bg)+.038)) end
  else
    if clum(panel)>=clum(bg)-.022 then panel=cshift_luma(panel,math.max(.06,clum(bg)-.038)) end
  end

  -- Generated polarity remains the safety net; a readable theme text color can
  -- contribute some hue/temperature without sacrificing contrast.
  local generated,text_is_light=generated_text(bg)
  local theme_text=usable_theme_text(map,bg,{
    "col_main_text2","col_main_text","genlist_fg","col_tcp_text",
    "col_toolbar_text","col_tl_fg","col_trans_fg",
  },generated)
  local textcol=cmix(generated,theme_text,.18)
  local muted=cmix(textcol,bg,dark and .28 or .30)
  local faint=cmix(textcol,bg,dark and .50 or .52)

  local accent=best_theme_accent(map,bg)
  accent=cboost_sat(accent,dark and 1.18 or 1.14)
  accent=fit_accent_to_bg(accent,bg,text_is_light)
  local al=clum(accent)
  if dark and al<clum(bg)+.22 then
    accent=cshift_luma(accent,math.min(.82,clum(bg)+.26))
  elseif not dark and al>clum(bg)-.22 then
    accent=cshift_luma(accent,math.max(.12,clum(bg)-.28))
  end

  -- Use REAPER's own highlight/shadow roles when available, but only as a
  -- restrained contribution so an unusual theme cannot destroy readability.
  local theme_hi=theme_edge_role(map,bg,dark,true)
  local theme_sh=theme_edge_role(map,bg,dark,false)
  local edge_base=cmix(bg,textcol,dark and .20 or .18)
  local edge_active=cmix(accent,textcol,dark and .12 or .09)
  local edge=theme_sh and cmix(edge_base,theme_sh,.28) or edge_base
  local edge2=theme_hi and cmix(edge_active,theme_hi,.24) or edge_active

  local out={}
  out.bg=ccopy(bg)
  out.bg2=cmix(bg,accent,dark and .080 or .065)
  out.panel=panel
  out.panel2=cmix(panel,accent,dark and .105 or .085)
  out.field=field

  out.text=textcol
  out.muted=muted
  out.faint=faint

  out.edge=edge
  out.edge2=edge2

  out.accent=accent
  out.accent2=cmix(accent,textcol,dark and .14 or .09)
  out.accent3=cmix(accent,bg,dark and .48 or .46)
  out.focus=cmix(accent,textcol,dark and .06 or .04)
  out.focus2=cmix(accent,textcol,dark and .20 or .12)
  out.ink=cmix(bg,accent,dark and .16 or .12)
  out.hover=cmix(accent,textcol,dark and .15 or .10)

  out.warn=fit_accent_to_bg(C_DEFAULT.warn,bg,text_is_light)
  out.red=fit_accent_to_bg(C_DEFAULT.red,bg,text_is_light)
  return out
end

-- One-shot color-palette generator for the COLOR PALETTE tab named CHAMELEON.
-- It deliberately receives a snapshot instead of polling REAPER, so selecting any
-- other tab has zero additional theme-query cost.
local function rgb01_to_hsv(c)
  local r,g,b=c[1],c[2],c[3]
  local hi=math.max(r,g,b);local lo=math.min(r,g,b);local d=hi-lo
  local h=0
  if d>1e-9 then
    if hi==r then h=((g-b)/d)%6 elseif hi==g then h=(b-r)/d+2 else h=(r-g)/d+4 end
    h=(h/6)%1
  end
  return h,hi<=1e-9 and 0 or d/hi,hi
end
local function portable_theme_color(c)
  if not c then return nil end
  return Core.rgb(
    math.max(0,math.min(255,math.floor(c[1]*255+.5))),
    math.max(0,math.min(255,math.floor(c[2]*255+.5))),
    math.max(0,math.min(255,math.floor(c[3]*255+.5))))
end
local function build_theme_swatch_palette(map)
  -- Prefer colors that literally exist in the current REAPER theme. Generated
  -- colors are only used after those real theme colors, and are derived from the
  -- most characteristic theme accents rather than from an even hue wheel.
  local semantic=build_chameleon_palette(map)
  local out={}
  local seen={}
  local function rgb_tuple(rgb)
    return (rgb>>16)&255,(rgb>>8)&255,rgb&255
  end
  local function perceptual_gap(a,b)
    local ar,ag,ab=rgb_tuple(a);local br,bg,bb=rgb_tuple(b)
    local dr,dg,db=ar-br,ag-bg,ab-bb
    return math.sqrt(dr*dr*.30+dg*dg*.59+db*db*.11)
  end
  local function add(rgb,min_gap)
    if not rgb then return false end
    rgb=rgb&0xFFFFFF
    if seen[rgb] then return false end
    min_gap=min_gap or 0
    if min_gap>0 then
      for _,v in ipairs(out) do if perceptual_gap(rgb,v)<min_gap then return false end end
    end
    out[#out+1]=rgb;seen[rgb]=true;return true
  end
  local function add_color01(c,gap) return add(portable_theme_color(c),gap) end

  -- Semantic/selection roles first: these are the colors users actually notice
  -- as "the theme's colors" in normal REAPER use.
  local priority={
    'col_seltrack','col_seltrack2','genlist_selbg','col_tl_bgsel','toolbararmed_color',
    'selitem_dot','selitem_tag','activetake_tag','col_routinghl1','col_routinghl2',
    'track_lanesolo_tabcol','col_main_resize2','col_toolbar_text_on',
    'col_main_text2','col_main_text','genlist_fg','col_tcp_text','col_toolbar_text',
    'col_tl_fg','col_tl_fg2','col_trans_fg',
    'col_main_bg2','col_main_bg','col_arrangebg','col_tracklistbg','col_mixerbg',
    'genlist_bg','col_tl_bg','col_trans_bg','col_tr1_bg','col_tr2_bg',
    'col_main_editbk','col_transport_editbk','col_buttonbg',
    'col_main_3dhl','col_main_3dsh','genlist_grid','col_toolbar_frame',
    'col_tr1_divline','col_tr2_divline','docker_shadow',
  }
  for _,key in ipairs(priority) do add_color01(map[key],8) end

  -- Ensure BLT's semantic interpretation of the same theme is represented too.
  for _,c in ipairs({semantic.accent,semantic.accent2,semantic.focus2,semantic.hover,
    semantic.text,semantic.muted,semantic.bg,semantic.panel,semantic.field,semantic.edge2}) do
    add_color01(c,8)
  end

  -- Pick a small set of characteristic colorful anchors from the actual theme.
  -- Avoid manufacturing many tiny lightness steps of a single color.
  local anchors={}
  local function consider_anchor(c)
    if not c then return end
    local h,ss,v=rgb01_to_hsv(c)
    if ss<.12 or v<.10 then return end
    local rgb=portable_theme_color(c)
    for _,a in ipairs(anchors) do if perceptual_gap(rgb,a.rgb)<28 then return end end
    anchors[#anchors+1]={c=c,h=h,s=ss,v=v,rgb=rgb}
  end
  for _,key in ipairs(priority) do consider_anchor(map[key]) end
  consider_anchor(semantic.accent);consider_anchor(semantic.accent2);consider_anchor(semantic.focus2)
  table.sort(anchors,function(a,b) return a.s*a.v>b.s*b.v end)
  while #anchors>8 do table.remove(anchors) end

  -- Affinity colors: analogous neighbors and restrained saturation/value changes.
  -- They stay recognizably related to the actual theme instead of forcing hue balance.
  local recipes={
    {-.075,1.00,1.00},{.075,1.00,1.00},{-.035,.78,1.08},{.035,.78,1.08},
    {-.12,.72,.92},{.12,.72,.92},{.0,.58,1.10},{.0,1.05,.78},
  }
  for _,a in ipairs(anchors) do
    for _,q in ipairs(recipes) do
      if #out>=72 then break end
      add(Core.hsv((a.h+q[1])%1,math.max(.08,math.min(1,a.s*q[2])),math.max(.16,math.min(1,a.v*q[3]))),11)
    end
    if #out>=72 then break end
  end

  -- If a very monochrome theme still leaves empty slots, derive broader but still
  -- compatible relatives from the strongest semantic accent. This is a fallback,
  -- not the primary selection algorithm.
  local ah,as,av=rgb01_to_hsv(semantic.accent);as=math.max(.22,as)
  local fallback_offsets={-.18,-.14,-.10,-.06,-.03,.03,.06,.10,.14,.18,.24,-.24}
  local bands={{.86,1.0},{.62,.92},{.92,.72}}
  for _,band in ipairs(bands) do
    for _,dh in ipairs(fallback_offsets) do
      if #out>=72 then break end
      add(Core.hsv((ah+dh)%1,math.min(1,as*band[1]+.08),math.max(.24,math.min(1,av*band[2]))),9)
    end
    if #out>=72 then break end
  end

  -- Last-resort theme neutrals, spaced coarsely rather than as fine gradients.
  local neutral_steps={0,.16,.32,.48,.64,.80,1}
  for _,t in ipairs(neutral_steps) do
    if #out>=72 then break end
    add_color01(cmix(semantic.text,semantic.bg,t),7)
  end

  -- Guarantee the fixed 72-cell contract without querying REAPER again.
  local i=1
  while #out<72 do
    local a=anchors[((i-1)%math.max(1,#anchors))+1]
    local h,sat,val
    if a then h,sat,val=a.h,a.s,a.v else h,sat,val=ah,as,av end
    local ring=math.floor((i-1)/12)
    local dh=((i-1)%12-5.5)*.035
    add(Core.hsv((h+dh)%1,math.max(.14,math.min(1,sat*(.82+ring*.06))),math.max(.22,math.min(1,val*(1.04-ring*.055)))),0)
    i=i+1
    if i>300 then break end
  end
  while #out>72 do table.remove(out) end
  return out
end

function Chameleon.restore()
  for k,v in pairs(C_DEFAULT) do C[k]=ccopy(v) end
  Chrome.mint=ccopy(CHROME_DEFAULT.mint)
  Chrome.ice=ccopy(CHROME_DEFAULT.ice)
  if chameleon_host_refresh then chameleon_host_refresh() end
end

function Chameleon.apply(palette)
  for k,v in pairs(palette) do C[k]=v end
  Chrome.mint=ccopy(C.accent2)
  Chrome.ice=ccopy(C.focus2)
  if chameleon_host_refresh then chameleon_host_refresh() end
end

function Chameleon.refresh(force)
  if not Chameleon.enabled then return false end
  local map,sig=theme_snapshot()
  if not force and sig==Chameleon.signature then return false end
  Chameleon.signature=sig
  Chameleon.apply(build_chameleon_palette(map))
  redraw_dirty=true
  return true
end

function Chameleon.set(on)
  Chameleon.enabled=on and true or false
  BLT.store(SECTION,"chameleon",Chameleon.enabled and "1" or "0",true)
  Chameleon.signature=nil

  if Chameleon.enabled then
    Chameleon.refresh(true)
    chameleon_notify("CHAMELEON  REAPERテーマに擬態")
  else
    Chameleon.restore()
    redraw_dirty=true
    chameleon_notify("CHAMELEON  オリジナル配色")
  end
  wake_visuals(R.time_precise())
end

function Chameleon.tick(now)
  if not Chameleon.enabled or now<Chameleon.poll_at then return false end
  Chameleon.poll_at=now+Chameleon.poll_interval
  return Chameleon.refresh(false)
end

-- Explicit one-shot palette sampling for the COLOR PALETTE tab. This never
-- installs a poller and is called only from the tab press handler.
function Chameleon.sample_palette()
  local map=theme_snapshot()
  return build_theme_swatch_palette(map)
end

-- Icon-only color separation.
-- The main UI palette remains untouched; this only keeps the three overlapping
-- Chameleon circles visually distinct even when a REAPER theme is nearly mono-hued.
local function rgb_to_hsv(c)
  local r,g,b=c[1],c[2],c[3]
  local mx=math.max(r,g,b)
  local mn=math.min(r,g,b)
  local d=mx-mn
  local h=0

  if d>1e-6 then
    if mx==r then
      h=((g-b)/d)%6
    elseif mx==g then
      h=(b-r)/d+2
    else
      h=(r-g)/d+4
    end
    h=h/6
  end

  local s=(mx<=1e-6) and 0 or d/mx
  return h,s,mx
end

local function hsv_to_rgb(h,s,v)
  h=h%1
  local i=math.floor(h*6)
  local f=h*6-i
  local p=v*(1-s)
  local q=v*(1-f*s)
  local t=v*(1-(1-f)*s)
  i=i%6

  if i==0 then return {v,t,p}
  elseif i==1 then return {q,v,p}
  elseif i==2 then return {p,v,t}
  elseif i==3 then return {p,q,v}
  elseif i==4 then return {t,p,v}
  else return {v,p,q}
  end
end

function Chameleon.compute_icon_colors()
  if not Chameleon.enabled then
    return C.muted,C.faint,C.edge
  end

  local h,s,v=rgb_to_hsv(C.accent)
  -- Only the icon gets a saturation floor; the actual BLT theme does not.
  s=math.max(s,.46)

  -- Preserve the theme's base hue, but fan the other two colors away from it.
  -- +/- 0.19 ~= 68 degrees: clearly different without turning into a rainbow badge.
  local c1=hsv_to_rgb(h,      s,                v)
  local c2=hsv_to_rgb(h+.19, math.max(.42,s*.90), v)
  local c3=hsv_to_rgb(h-.19, math.max(.42,s*.86), v)

  return c1,c2,c3
end
function Chameleon.icon_colors()
 local c=Chameleon.bltIcon;local a=C.accent
 if c and c.on==Chameleon.enabled and c.r==a[1] and c.g==a[2] and c.b==a[3] then return c[1],c[2],c[3] end
 local x,y,z=Chameleon.compute_icon_colors()
 if not Chameleon.enabled then for _,v in ipairs({x,y,z}) do local gray=v[1]*.2126+v[2]*.7152+v[3]*.0722;for i=1,3 do v[i]=gray+(v[i]-gray)*.12 end end end
 Chameleon.bltIcon={x,y,z,on=Chameleon.enabled,r=a[1],g=a[2],b=a[3]};return x,y,z
end

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
  last_window_w,last_window_h=W,H+Chrome.titleH

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

local function custom_titlebar() BLT.bar() end


local UI={palettes={},swatch_cache={},double_click_seconds=.40,double_click_pixels=5}
for _,spec in ipairs(Core.palette_specs) do
 if not spec.dynamic then UI.palettes[spec.id]=Core.palette(spec.id) end
end
local function palette_spec(id) for _,spec in ipairs(Core.palette_specs) do if spec.id==id then return spec end end end
A.palette_tab=R.GetExtState(SECTION,'palette_tab')
-- CHAMELEON must be explicitly pressed before reading theme colors. Therefore a
-- previously saved dynamic tab never triggers a theme read during startup.
if A.palette_tab=='chameleon' or not UI.palettes[A.palette_tab] then A.palette_tab='basic' end
A.last_static_tab=A.palette_tab
UI.palette=UI.palettes[A.palette_tab]
function UI.generate_chameleon_palette()
 UI.palettes.chameleon=Chameleon.sample_palette() -- one-shot theme read; no palette polling
 return UI.palettes.chameleon
end
function UI.set_tab(id)
 local spec=palette_spec(id)
 if not spec or A.busy or A.modal then return end
 if spec.dynamic then
  UI.palette=UI.generate_chameleon_palette()
  A.palette_tab=id;A.preview_click=nil
  UI.save_settings();notice('REAPERテーマからカメレオンパレットを更新しました。',false);wake_visuals();return
 end
 if not UI.palettes[id] or A.palette_tab==id then return end
 A.palette_tab=id;A.last_static_tab=id;UI.palette=UI.palettes[id];A.preview_click=nil
 UI.save_settings();wake_visuals()
end
function UI.grid_cell(layout,index)
 local column=(index-1)%layout.columns;local row=(index-1)//layout.columns
 local step=(layout.w+layout.gap_x)/layout.columns
 local x=layout.x+floor(column*step+.5)
 local right=layout.x+floor((column+1)*step+.5)-layout.gap_x
 return x,layout.y+row*(layout.h+layout.gap_y),right-x,layout.h
end
function UI.startup_size(w,h)
 return finite(w) and clamp(w,Chrome.minW,1600) or W,
  finite(h) and clamp(h,Chrome.minH,1600) or H+Chrome.titleH
end
function UI.rgb_color(rgb)
 local c=UI.swatch_cache[rgb]
 if not c then local r,g,b=Core.channels(rgb);c={r/255,g/255,b/255};UI.swatch_cache[rgb]=c;UI.color_count=(UI.color_count or 0)+1
  if UI.color_count>512 then UI.swatch_cache={[rgb]=c};UI.color_count=1 end
 end
 return c
end
function UI.save_settings()
 BLT.store(SECTION,'color',S.color,true);BLT.store(SECTION,'close_after',S.close_after and '1' or '0',true)
 BLT.store(SECTION,'palette_tab',A.palette_tab=='chameleon' and (A.last_static_tab or 'basic') or A.palette_tab,true)
end
function UI.choose(rgb)
 if S.color~=rgb then S.color=rgb;UI.save_settings() end
 A.message='';A.bad=false;wake_visuals()
end
function UI.sync_custom(force)
 -- The native palette reader can reload persistent storage on each call.
 -- Refresh on activation/dialog completion, never poll it during arrange edits.
 local now=R.time_precise()
 if not force and (not A.active or not A.custom_refresh_at or now<A.custom_refresh_at) then return end
 A.custom_refresh_at=nil
 local values,err,raw=Core.read_custom()
 if raw~=A.custom_raw or err~=A.custom_error then
  A.custom_raw,A.custom_error,A.custom=raw,err,values;redraw_dirty=true
 end
end
function UI.counts()
 local snap=Target.snapshot;local kind=Target.kind
 return kind and snap and snap[kind] and #snap[kind] or 0
end
function UI.target_caption()
 local n=UI.counts();local kind=Target.kind
 if not kind then return Language.text(Target.reason=='ambiguous' and '対象の再選択が必要です' or Target.reason=='unsupported' and 'この種類は対象外です' or '対象を選択してください') end
 if kind=='item' then return string.format(Language.text('アイテム  %d個'),n)
 elseif kind=='track' then return string.format(Language.text('トラック  %d本'),n) end
 local m,r=0,0
 for _,v in ipairs(Target.snapshot.ruler) do if v.isregion then r=r+1 else m=m+1 end end
 return string.format(Language.text('マーカー %d個  /  リージョン %d個'),m,r)
end
function UI.base_status()
 if not Target.kind then
  if Target.reason=='ambiguous' then return '選択履歴を確定できません。開いたまま対象を再クリックしてください。',true end
  if Target.reason=='unsupported' then return 'アイテム・トラック・マーカー／リージョンが対象です。',false end
  return 'REAPERで対象を選択してください。',false
 end
 if UI.counts()==0 then return '対象の選択がありません。ほかの種類には適用しません。',false end
 return '色を選び、実行してください。Ctrl+Zで元に戻せます。',false
end
function UI.after_dialog()
 A.modal=false;A.pressed=nil;A.apply_request=nil;A.preview_click=nil;A.preview_press=nil;A.swallow_mouse=true;A.right_last=false;last_down=false
 Chrome.mouseDown=false;Chrome.closePressed=false;Chrome.resetPressed=false
 Target.last_buttons=R.JS_Mouse_GetState(3);Target.pending=nil
 Target.hold_until=R.time_precise()+.24
 gfx.mouse_wheel=0;UI.sync_custom(true);wake_visuals()
end
function UI.native_picker()
 A.modal=true;BLT.clearTooltip()
 local ok,accepted,native=pcall(R.GR_SelectColor,gfx_window_handle())
 UI.after_dialog()
 if not ok then notice('カラー選択を開けませんでした。',true)
 elseif accepted and accepted~=0 and type(native)=='number' then UI.choose(Core.portable(native)) end
end
function UI.custom_menu(index)
 A.modal=true;BLT.clearTooltip();gfx.x,gfx.y=gfx.mouse_x,gfx.mouse_y
 local menu=(A.custom and '' or '#')..Language.text('選択色をこの枠に登録')..'|'..Language.text('REAPERのカラー設定を開く…')
 local choice=gfx.showmenu(menu);A.modal=false
 if choice==1 and A.custom then
  local ok,err=Core.write_custom_slot(index,S.color)
  if ok then notice(string.format(Language.text('REAPERカスタムカラー %02d に登録しました。'),index),false)
  else notice('REAPERカスタムカラーを保存できませんでした。設定は再読み込みします。',true) end
  UI.after_dialog()
 elseif choice==2 then UI.native_picker()
 else UI.after_dialog() end
end
function UI.store_custom(index,rgb)
 if not index or not rgb then return false end
 local ok=Core.write_custom_slot(index,rgb)
 if ok then
  UI.sync_custom(true)
  notice(string.format(Language.text('REAPERカスタムカラー %02d に登録しました。'),index),false)
 else
  UI.sync_custom(true)
  notice('REAPERカスタムカラーを保存できませんでした。設定は再読み込みします。',true)
 end
 return ok
end
function UI.draw_color_drag()
 local d=A.color_drag;if not d or not d.moved then return end
 local hit=UI.hit();local target=hit and hit.custom or nil
 if target then
  local x,y,w,h=UI.grid_cell(Layout.custom,target)
  rect(x-3,y-3,w+6,h+6,C.accent,.055);color(C.accent2);gfx.rect(sx(x)-2,sy(y)-2,w*scale+4,h*scale+4,0)
 end
 local c=UI.rgb_color(d.rgb);local size=22
 rect(mx+12,my+12,size,size,c,.98);color(C.text);gfx.rect(sx(mx+12)-1,sy(my+12)-1,size*scale+2,size*scale+2,0)
end
function UI.apply(request)
 if A.busy then return end
 -- Freeze the previewed target before the last validation. A new selection may
 -- update the preview, but never changes what a press already requested.
 local snap=request and request.snapshot or Target.snapshot
 local kind=request and request.kind or Target.kind
 local picked=request and request.color or S.color
 if request and kind~=Target.kind then notice('対象の選択が変わりました。表示を確認して再実行してください。',true);return end
 if not kind or UI.counts()==0 then local text,bad=UI.base_status();notice(text,bad);return end
 A.busy=true
 local ok,why,count=Core.apply(snap,kind,picked)
 A.busy=false
 if ok then
  notice(why=='unchanged' and 'すでに選択した色です。' or string.format(Language.text('%d件の色を変更しました。'),count),false)
  PrimaryButton.state.flashUntil=R.time_precise()+.45
  if S.close_after then A.closing=true end
 else
  local errors={empty='対象の選択がありません。ほかの種類には適用しません。',project='プロジェクトが変わったため中止しました。',
   selection='対象の選択が変わりました。表示を確認して再実行してください。',color='選択した色が不正です。',
   read='対象を確認できません。選択し直してください。',rollback='色の変更に失敗したため、元の色へ戻しました。',
   restore_failed='元の色へ戻せない項目があります。REAPERのUndoで確認してください。'}
  notice(errors[why] or '色を変更できませんでした。',true)
 end
 Target.tick(R.time_precise(),true);wake_visuals()
end
function UI.palette_tab(spec,x,y,w,h)
 local selected=A.palette_tab==spec.id
 local hot=inside(x,y,w,h) and A.active and not BLT.blocked() and not A.modal
 local a=animate('tab_'..spec.id,hot and 1 or 0)
 gradient(x,y,w,h,C.panel2,C.field,(selected and .62 or .18)+.14*a,.92)
 if a>.001 then rect(x,y,w,h,C.hover,.07*a) end
 line(x,y+h,x+w,y+h,selected and C.accent2 or C.edge,selected and .95 or .40)
 if selected then line(x,y+h-1,x+w,y+h-1,C.accent,.55) end
 finish_corners(x,y,w,h,4,false,selected and C.accent2 or C.edge2,selected and .6 or .22+.2*a)
 label(spec.name,x+4,y,11,selected and C.text or C.muted,1,w-8,h,5,selected)
 widget('tab_'..spec.id,x,y,w,h,function() UI.set_tab(spec.id) end,
  spec.dynamic and 'カメレオンは押した時だけREAPERテーマを読み取り、72色を生成します。再クリックで更新します。'
   or 'パレットを切り替えます。選択色と対象は変更しません。',not A.busy)
end
function UI.preview_activate()
 local press=A.preview_press
 if not press or press.moved or R.time_precise()-press.time>UI.double_click_seconds then A.preview_click=nil;return end
 local previous=A.preview_click
 local x,y=gfx.mouse_x,gfx.mouse_y
 if previous and press.time-previous.time<=UI.double_click_seconds
  and press.time>=previous.time and abs(x-previous.x)<=UI.double_click_pixels and abs(y-previous.y)<=UI.double_click_pixels then
  A.preview_click=nil;UI.native_picker()
 else A.preview_click={time=press.time,x=x,y=y} end
end
function UI.apply_colors()
 local old=UI.apply_tint
 if old and old.rgb==S.color and old.text==C.text and old.field==C.field and old.edge==C.edge then return old.colors end
 local chosen=UI.rgb_color(S.color);local edge={}
 -- Only the execution accent follows the selected color. Swatches remain exact
 -- RGBs, and the light/dark theme still owns readable text and background colors.
 for i=1,3 do edge[i]=chosen[i]*.45+C.text[i]*.55 end
 local colors=setmetatable({accent=chosen,accent2=edge,accent3=chosen},{__index=C})
 UI.apply_tint={rgb=S.color,text=C.text,field=C.field,edge=C.edge,colors=colors}
 return colors
end
function UI.action_row(now,n)
 local t,p,a=Layout.close_after,Layout.preview,Layout.apply
 local hot=inside(t.x,t.y,t.w,t.h) and A.active and not BLT.blocked()
 if hot then rect(t.x,t.y,t.w,t.h,C.hover,.06) end
 local state=animate('close_after',S.close_after and 1 or 0)
 BLT.switch(t.x,t.y,state,true)
 label('実行後閉じる',t.x+31,t.y,11,C.text,1,t.w-31,t.h,4,false)
 widget('close_after',t.x,t.y,t.w,t.h,function() S.close_after=not S.close_after;UI.save_settings();wake_visuals() end,
  '実行が成功したときだけウィンドウを閉じます。')
 local colors=UI.apply_colors();local chosen=UI.rgb_color(S.color)
 local preview_hot=inside(p.x,p.y,p.w,p.h) and A.active and not BLT.blocked()
 local glow=animate('preview_hover',preview_hot and 1 or 0)
 cut_panel(p.x,p.y,p.w,p.h,6,C.field,.95,colors.accent2,.40+.30*glow)
 if glow>.001 then rect(p.x+1,p.y+1,p.w-3,p.h-3,C.hover,.04*glow) end
 local sw=30;local swx=p.x+7;local swy=p.y+(p.h-sw)/2
 rect(swx,swy,sw,sw,chosen,1)
 color(C.edge2);gfx.rect(sx(swx)-1,sy(swy)-1,sw*scale+2,sw*scale+2,0)
 label(Core.hex(S.color),p.x+44,p.y+7,14,C.text,3,p.w-51,22,0,true,true)
 local r,g,b=Core.channels(S.color)
 label(string.format('%d / %d / %d',r,g,b),p.x+44,p.y+29,8,C.muted,3,p.w-51,13,0,false,true)
 widget('selected_color',p.x,p.y,p.w,p.h,UI.preview_activate,
  '適用色。ダブルクリックでREAPERのカラー選択を開きます。',not A.busy)
 -- A short same-color arrow connects the preview to the tinted execution face.
 local left,right,cy=p.x+p.w+4,a.x-5,p.y+p.h/2
 line(left,cy,right,cy,colors.accent2,.72)
 line(right-3,cy-3,right,cy,colors.accent2,.85);line(right-3,cy+3,right,cy,colors.accent2,.85)
 PrimaryButton.painter.C=colors
 local enabled=n>0 and not A.busy
 PrimaryButton.draw(PrimaryButton.painter,a.x,a.y,a.w,a.h,'色を適用','APPLY COLOR',enabled,false,nil,
  inside(a.x,a.y,a.w,a.h) and not BLT.blocked(),A.pressed=='apply' and (gfx.mouse_cap&1)~=0,now,A.active)
 if enabled then
  local offset=A.pressed=='apply' and (gfx.mouse_cap&1)~=0 and 1.5 or 0
  rect(a.x+7,a.y+a.h-7+offset,a.w-19,3,chosen,1)
  line(a.x+7,a.y+a.h-8+offset,a.x+a.w-12,a.y+a.h-8+offset,colors.accent2,.35)
 end
 widget('apply',a.x,a.y,a.w,a.h,function() UI.apply(A.apply_request) end,
  '表示中の対象すべてへ選択色を適用します。',enabled)
end
function UI.tile(id,rgb,x,y,w,h,custom_index)
 local available=rgb~=nil;local chosen=available and rgb==S.color
 local hot=inside(x,y,w,h) and A.active and not BLT.blocked()
 -- The face is the literal color; theming and hover never tint it.
 local c=available and UI.rgb_color(rgb) or C.field
 rect(x,y,w,h,c,1)
 if not available then line(x+3,y+h-3,x+w-3,y+3,C.edge,.7) end
 color(chosen and C.text or hot and C.accent2 or C.edge)
 gfx.rect(sx(x)-1,sy(y)-1,w*scale+2,h*scale+2,0)
 if chosen then
  local r,g,b=Core.channels(rgb);local ink=(r*.2126+g*.7152+b*.0722)>145 and {0,0,0} or {1,1,1}
  line(x+w-13,y+h-9,x+w-10,y+h-6,ink,.92);line(x+w-10,y+h-6,x+w-5,y+h-12,ink,.92)
  color(C.accent2);gfx.rect(sx(x)-3,sy(y)-3,w*scale+6,h*scale+6,0)
 elseif hot then color(C.hover);gfx.rect(sx(x)-2,sy(y)-2,w*scale+4,h*scale+4,0) end
 if custom_index then
  local r,g,b=Core.channels(rgb or 0);local ink=(r*.2126+g*.7152+b*.0722)>145 and {0,0,0} or {1,1,1}
  label(string.format('%02d',custom_index),x+4,y+3,8,available and ink or C.faint,3,w-8,h-4,0,false,true)
 end
 widget(id,x,y,w,h,available and function() UI.choose(rgb) end or function() UI.native_picker() end,
  available and Core.hex(rgb)..(custom_index and '  ·  '..Language.text('右クリック：登録／設定') or '  ·  REAPERカスタムカラーへドラッグで登録') or Language.text('未登録：クリックしてREAPERのカラー設定を開く'))
 widgets[#widgets].custom=custom_index
end
function UI.icon()
 local x,y=W-101,35
 local local_colors={UI.rgb_color(Core.hsv(.57,.65,.93)),UI.rgb_color(Core.hsv(.78,.43,.93)),UI.rgb_color(Core.hsv(.10,.55,.99))}
 for i=1,5 do
  local p=anim_time*(.12+i*.01)+i*1.47
  disc(x+40+math.sin(p)*17,y+24+math.cos(p*.8)*8,18+i%3*4,C.accent,.007)
 end
 for i=1,3 do
  local xx,yy=x+8+(i-1)*15,y+18-(i-1)*5
  cut_panel(xx,yy,28,24,5,C.field,.95,C.edge2,.48)
  rect(xx+4,yy+4,19,14,local_colors[i],.62)
 end
 local c=UI.rgb_color(S.color)
 cut_panel(x+56,y+25,20,17,4,C.field,.95,C.edge2,.65);rect(x+60,y+29,11,7,c,.95)
 if animations_active then icon_clock=math.min(.4,icon_clock+frame_dt) end
 while animations_active and icon_clock>=.13 and #icon_particles<24 do
  icon_clock=icon_clock-.13;icon_serial=icon_serial+1
  local p=table.remove(A.icon_pool) or {};local n=icon_serial
  p.age=0;p.life=1.9+particle_hash(n,3);p.lane=n%3+1;p.phase=particle_hash(n,2)*6.283
  p.r=.45+particle_hash(n,4)*.65;icon_particles[#icon_particles+1]=p
 end
 for i=#icon_particles,1,-1 do
  local p=icon_particles[i];p.age=p.age+particle_dt
  if p.age>=p.life then table.remove(icon_particles,i);A.icon_pool[#A.icon_pool+1]=p
  else
   local t=p.age/p.life;local u=t*t*(3-2*t);local env=math.sin(t*math.pi)^2
   local px=x+25+40*u;local py=y+18-p.lane*3+18*u+math.sin(t*math.pi+p.phase)*5*(1-u)
   disc(px,py,p.r+5,C.accent,.012*env);disc(px,py,p.r+2,C.accent2,.065*env);disc(px,py,p.r,local_colors[p.lane],.75*env)
  end
 end
end
function UI.geometry()
 local content=max(1,gfx.h-Chrome.titleH)
 scale=max(.3,min(gfx.w/W,content/H));ox=(gfx.w-W*scale)/2;oy=Chrome.titleH+(content-H*scale)/2-22*scale
 BLT.viewport(scale,gfx.ext_retina or 1);mx,my=(gfx.mouse_x-ox)/scale,(gfx.mouse_y-oy)/scale
end
function UI.draw(now)
 reset_text_queue()
 UI.geometry();
 if text_queue.scale~=scale then text_queue.buckets={};text_queue.order={};text_queue.scale=scale end
particle_dt=math.max(0,math.min(.1,now-frame_clock));frame_clock=now
 animation_speed=A.active and visual_speed(now) or 0;animations_active=animation_speed>0
 -- Control easing must finish even when the decorative layer is asleep.
 frame_dt=particle_dt;anim_time=anim_time+particle_dt*animation_speed
 widgets={};hover='';gfx.dest=-1;gfx.mode=0;gfx.a=1;gfx.clear=-1
 color(C.bg);gfx.rect(0,0,gfx.w,gfx.h,1)
 gradient(0,22,W,82,C.bg2,C.bg,.21,0,true)
 BLT.title('COLOR PALETTE','CONTEXT COLOR  最後に選択した種類へ色を適用',W)
 UI.icon()
 local n=UI.counts();local tone=n>0 and C.accent2 or C.warn
 local t=Layout.target
 cut_panel(t.x,t.y,t.w,t.h,5,C.field,.9,C.edge,.5)
 disc(t.x+13,t.y+t.h/2,2,tone,.95)
 label('対象',t.x+25,t.y,9,C.muted,1,40,t.h,4,false)
 label(UI.target_caption(),t.x+70,t.y,13,tone,1,t.w-167,t.h,4,true,true)
 label('LAST TOUCHED',t.x+t.w-90,t.y,7,C.faint,3,79,t.h,6,false,true)
 local tab=Layout.tabs;local step=(tab.w+tab.gap)/#Core.palette_specs
 for i,spec in ipairs(Core.palette_specs) do
  local x=tab.x+floor((i-1)*step+.5);local right=tab.x+floor(i*step+.5)-tab.gap
  UI.palette_tab(spec,x,tab.y,right-x,tab.h)
 end
 for i,rgb in ipairs(UI.palette) do
  local x,y,w,h=UI.grid_cell(Layout.palette,i);UI.tile('palette_'..i,rgb,x,y,w,h)
 end
 label('REAPERカスタムカラー',24,Layout.custom_title_y,12,C.text,1,220,18,0,true)
 right_label('REAPER  /  16 COLORS',W-24,Layout.custom_title_y+2,8,C.faint,3,false)
 for i=1,16 do
  local native=A.custom and A.custom[i];local rgb=native and Core.portable(native) or nil
  local x,y,w,h=UI.grid_cell(Layout.custom,i);UI.tile('custom_'..i,rgb,x,y,w,h,i)
 end
 label(A.custom_error and 'クリックしてREAPERのカラー設定を開いてください。' or '左クリック：色を選択  /  右クリック：選択色を登録  /  上の色をドラッグ＆ドロップ：登録',
  25,Layout.custom_hint_y,9,A.custom_error and C.warn or C.faint,1,W-50,14)
 UI.action_row(now,n)
 flush_text_queue()
 UI.draw_color_drag()
 local message,bad=UI.base_status()
 if A.message~='' and now<(A.message_until or 0) then message,bad=A.message,A.bad end
 BLT.footer(message,bad,W,H+22,VERSION)
 BLT.bar();gfx.update()
end
function UI.hit()
 for i=#widgets,1,-1 do local w=widgets[i];if inside(w.x,w.y,w.w,w.h) then return w end end
end
function UI.interact()
 local cap=gfx.mouse_cap or 0;local down=(cap&1)~=0;local right=(cap&2)~=0
 if A.swallow_mouse then
  A.pressed=nil;A.apply_request=nil;A.color_drag=nil;last_down=down;A.right_last=right;gfx.mouse_wheel=0
  if not down and not right then A.swallow_mouse=nil end
  return
 end
 if BLT.blocked() or Chrome.mouseActive or A.modal or not A.active then
  A.pressed=nil;A.apply_request=nil;A.preview_click=nil;A.preview_press=nil;A.color_drag=nil
  last_down=down;A.right_last=right;gfx.mouse_wheel=0;return
 end
 local hit=UI.hit()
 if down and not last_down then
  A.pressed=hit and hit.id or nil
  A.apply_request=hit and hit.id=='apply' and hit.enabled and {snapshot=Target.snapshot,kind=Target.kind,color=S.color} or nil
  local palette_index=hit and hit.id and tonumber(hit.id:match('^palette_(%d+)$')) or nil
  if palette_index and hit.enabled and UI.palette[palette_index] then
   A.color_drag={rgb=UI.palette[palette_index],start_x=gfx.mouse_x,start_y=gfx.mouse_y,moved=false}
  end
  if hit and hit.id=='selected_color' and hit.enabled then
   A.preview_press={time=R.time_precise(),x=gfx.mouse_x,y=gfx.mouse_y}
  else A.preview_click=nil;A.preview_press=nil end
 elseif down then
  if A.color_drag and not A.color_drag.moved then
   local dx,dy=gfx.mouse_x-A.color_drag.start_x,gfx.mouse_y-A.color_drag.start_y
   if abs(dx)+abs(dy)>=6 then A.color_drag.moved=true;A.pressed=nil;A.preview_click=nil end
  end
  if A.preview_press then
   local p=A.preview_press
   if abs(gfx.mouse_x-p.x)>UI.double_click_pixels or abs(gfx.mouse_y-p.y)>UI.double_click_pixels then p.moved=true;A.preview_click=nil end
  end
 elseif not down and last_down then
  local drag=A.color_drag
  if drag and drag.moved then
   if hit and hit.custom then UI.store_custom(hit.custom,drag.rgb) end
   A.color_drag=nil;A.pressed=nil;A.apply_request=nil;A.preview_press=nil
  else
   local p=A.preview_press
   if p and (abs(gfx.mouse_x-p.x)>UI.double_click_pixels or abs(gfx.mouse_y-p.y)>UI.double_click_pixels) then p.moved=true end
   if hit and hit.enabled and hit.id==A.pressed then hit.fn() else A.preview_click=nil end
   A.pressed=nil;A.apply_request=nil;A.preview_press=nil;A.color_drag=nil
  end
 end
 if right and not A.right_last then
  A.preview_click=nil;A.preview_press=nil;A.color_drag=nil
  if hit and hit.custom then UI.custom_menu(hit.custom) end
 end
 last_down=down;A.right_last=right
 -- Wheel never changes the selected color or applies it implicitly.
 gfx.mouse_wheel=0
end

function UI.content_tooltip(now)
 if BLT.blocked() or A.modal or Chrome.mouseActive or not A.active or (gfx.mouse_cap&3)~=0 then
  if A.tip_visible then BLT.clearTooltip();A.tip_visible=false end;A.tip=nil;return
 end
 local hit=UI.hit();local tip=hit and hit.hint or nil
 if tip~=A.tip then
  if A.tip_visible then BLT.clearTooltip() end
  A.tip=tip;A.tip_time=now;A.tip_visible=false
 elseif tip and not A.tip_visible and now-(A.tip_time or now)>.7 then
  local x,y=gfx.clienttoscreen(gfx.mouse_x,gfx.mouse_y+18)
  R.TrackCtl_SetToolTip(Language.message(tip),x,y,true);A.tip_visible=true
 end
end
function UI.close()
 if A.closed then return end
 A.closed=true
 local ok,err=xpcall(function()
  UI.save_settings();BLT.clearTooltip();titlebar_cleanup()
  local _,x,y,w,h=gfx.dock(-1,0,0,0,0)
  if Core.finite(x) and Core.finite(y) then BLT.store(SECTION,'window_x',x,true);BLT.store(SECTION,'window_y',y,true) end
  BLT.store(SECTION,'window_w',gfx.w,true);BLT.store(SECTION,'window_h',gfx.h,true)
 end,debug.traceback)
 if R.SetToggleCommandState and A.command and A.command>0 then
  pcall(R.SetToggleCommandState,A.sectionID,A.command,0);pcall(R.RefreshToolbar2,A.sectionID,A.command)
 end
 pcall(gfx.quit)
 if not ok then BLT.logError(err) end
end

PrimaryButton.painter={C=C,gradient=gradient,line=line,rect=rect,corners=finish_corners,disc=disc,label=label,
 motion=function(now)return mx,my,visual_speed(now)end}
PrimaryButton.wake=function()redraw_dirty=true;next_draw_time=0 end
chameleon_host_refresh=function()redraw_dirty=true;wake_visuals()end
BLT.attach({R=R,C=C,Chrome=Chrome,Chameleon=Chameleon,section=SECTION,faces=fonts,font=font,
 geometry=function()return scale,ox,oy end,
 active=function()local f=gfx.getchar(65537);return (f&1)==0 or (f&2)~=0 end,
 wake=function()redraw_dirty=true;next_draw_time=0;wake_visuals()end,
 defaults={color=0x80BFFF,close_after=false},capture=function()return S end,
 valid=function(v)return Core.finite(v.color) and v.color%1==0 and v.color>=0 and v.color<=0xFFFFFF and type(v.close_after)=='boolean'end,
 apply=function(v)S.color=v.color;S.close_after=v.close_after;UI.save_settings();wake_visuals()end,
 busy=function()return A.busy end,commit=function()return true end,cancelEdit=function()A.pressed=nil;A.preview_click=nil;A.preview_press=nil end,
 editing=function()return false end,modal=function()return A.modal end,
 undoRefresh=function()Target.tick(R.time_precise(),true);wake_visuals()end,
 handle=gfx_window_handle,resizeHit=chrome_resize_hit,cursor=set_resize_cursor,beginResize=begin_window_resize,resize=update_window_resize})
if ...=='blt_test' then return {A=A,BLT=BLT,Core=Core,Target=Target,UI=UI,Geometry=WindowGeometry} end
-- Initial source/selection capture above deliberately precedes gfx.init.
local startup_x,startup_y=tonumber(R.GetExtState(SECTION,'window_x')),tonumber(R.GetExtState(SECTION,'window_y'))
local startup_w,startup_h=tonumber(R.GetExtState(SECTION,'window_w')),tonumber(R.GetExtState(SECTION,'window_h'))
startup_w,startup_h=UI.startup_size(startup_w,startup_h)
gfx.ext_retina=BLT_MAC and 0 or 1
if Core.finite(startup_x) and Core.finite(startup_y) then gfx.init(Chrome.windowTitle,startup_w,startup_h,0,startup_x,startup_y)
else gfx.init(Chrome.windowTitle,startup_w,startup_h,0) end
if not apply_custom_window_style(startup_w,startup_h) then gfx.quit();R.MB('カスタムアプリバーを初期化できません。','BLT COLOR PALETTE',0);return end
BLT.store(SECTION,'window_w',startup_w,true);BLT.store(SECTION,'window_h',startup_h,true)
if Chameleon.enabled then Chameleon.refresh(true) end
UI.sync_custom(true)
local _,_,section_id,command_id=R.get_action_context();A.sectionID,A.command=section_id,command_id
if command_id and command_id>0 then R.SetToggleCommandState(section_id,command_id,1);R.RefreshToolbar2(section_id,command_id) end
R.atexit(function()pcall(UI.close)end)
local performance={}
local performance_section='BLT_COLOR_PALETTE_PERF'
R.SetExtState(performance_section,'version',VERSION,false)
for _,name in ipairs({'selection','palette','theme','drawing','appbar'}) do R.SetExtState(performance_section,name,'',false) end
R.SetExtState(performance_section,'selection_details','',false)
local function record_phase(name,started)
 local ms=(R.time_precise()-started)*1000
 if ms>=20 and ms>(performance[name] or 0) then
  performance[name]=ms
  R.SetExtState(performance_section,name,string.format('%.2f',ms),false)
  if name=='selection' then R.SetExtState(performance_section,'selection_details',SelectionPerf.report(ms),false) end
 end
end
local function loop()
 if A.closed then return end
 local ok,err=xpcall(function()
  local now=R.time_precise();A.active=BLT.host.active()
  if A.message_until and now>=A.message_until then A.message_until=nil;A.message='';redraw_dirty=true end
  local started=R.time_precise()
  SelectionPerf.begin()
  if Target.tick(now,false) then redraw_dirty=true end
  SelectionPerf.active=false
  record_phase('selection',started)
  started=R.time_precise()
  if A.active then Chameleon.tick(now) end
  record_phase('theme',started)
  local cap=gfx.mouse_cap or 0
  local pointer=gfx.mouse_x~=last_raw_mouse_x or gfx.mouse_y~=last_raw_mouse_y
  local edge=cap~=last_raw_mouse_cap or (gfx.mouse_wheel or 0)~=0
  local own_input=A.active or Chrome.drag or Chrome.resize or A.color_drag
  if own_input and (pointer or edge) then wake_visuals(now) end
  if own_input and edge then next_draw_time=0 end
  if not A.active and Target.last_buttons~=0 then A.external_busy_until=now+.12 end
  last_raw_mouse_x,last_raw_mouse_y,last_raw_mouse_cap=gfx.mouse_x,gfx.mouse_y,cap
  if gfx.w~=last_window_w or gfx.h~=last_window_h or A.active~=last_window_active then
   if A.active and not last_window_active then A.custom_refresh_at=now+.15 end
   A.preview_click=nil;A.preview_press=nil
   last_window_w,last_window_h,last_window_active=gfx.w,gfx.h,A.active;wake_visuals(now);next_draw_time=0
  end
  started=R.time_precise();UI.sync_custom(false);record_phase('palette',started)
  local k=BLT.key(gfx.getchar());if k<0 then A.closing=true end
  local keys=0
  while k>0 and keys<32 do
   k=BLT.key(k)
   if k==27 then A.closing=true elseif k==13 and not A.modal then UI.apply() end
   keys=keys+1;k=BLT.key(gfx.getchar());wake_visuals(now)
  end
  if A.closing or Chrome.requestClose then UI.close();return end
  if Chrome.requestReset then Chrome.requestReset=false;reset_window_size();wake_visuals(now) end
  PrimaryButton.tick(now,A.active,PrimaryButton.wake)
  local moving=(A.active and (visual_speed(now)>0 or #icon_particles>0)) or Chrome.drag or Chrome.resize
  local draw_ready=A.active or now>=(A.external_busy_until or 0)
  if draw_ready and now>=next_draw_time and (redraw_dirty or moving) then
   started=R.time_precise()
   redraw_dirty=false;UI.draw(now);UI.interact();UI.content_tooltip(now)
   record_phase('drawing',started)
   next_draw_time=now+1/30;A.expose_at=now+.25
  elseif now>=(A.expose_at or 0) then
   gfx.update();A.expose_at=now+.25
  end
  started=R.time_precise();BLT.tick(now);record_phase('appbar',started)
 end,debug.traceback)
 if not ok then
  SelectionPerf.active=false
  A.busy=false;A.modal=false;Target.kind=nil;Target.reason='unknown'
  notice('処理中にエラーが発生しました。対象を選択し直してください。',true)
  BLT.recoverInput(A,err)
 end
 if not A.closed then R.defer(loop) end
end
loop()
