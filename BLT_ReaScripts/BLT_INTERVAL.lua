-- @description Interval - Align selected item spacing by seconds or project grid (Japanese GUI)
-- @version 3.0.1
-- @changelog
--   Animated glass HUD theme; all artwork is drawn with native gfx primitives.
-- @about
--   Select two or more items, enter a non-negative interval in seconds or grid units, then Align.
--   The earliest start stays fixed. Ties: track order, then item order.
--   Modes: start-to-start interval or end-to-next-start gap. Scope: all selected items or each track independently. Units: seconds or current project grid.
--   js_ReaScriptAPI is required for the custom title bar. REAPER 6+ / Lua.

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

local R = reaper
-- BLT PORTING CONFIGURATION: shared chrome metrics, app identity and title.
-- Keep this script self-contained; no external module loading is required.
local App={
  version="3.0.1",section="BLT_INTERVAL",windowTitle="BLT Interval",
  chromeTitle="I N T E R V A L",title="INTERVAL",
  subtitle="ITEM SPACING  アイテム間隔を整列",
}
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

-- INTERVAL English overrides. Japanese UI strings remain the lookup keys.
local LanguageCatalog={}
LanguageCatalog.en={
 ['ITEM SPACING  アイテム間隔を整列']='ITEM SPACING  Align item spacing',
 ['現在のグリッド設定を取得できません。']='Cannot read the current grid.',
 ['アイテムの長さを確認してください。']='Check item lengths.',
 ['間隔が大きすぎるか、小さすぎます。']='Spacing is out of range.',
 ['移動するアイテムのロックを解除してください。']='Unlock the items to move.',
 ['間隔のモードが無効です。']='Invalid spacing mode.',
 ['間隔の単位が無効です。']='Invalid spacing unit.',
 ['整列範囲のモードが無効です。']='Invalid alignment scope.',
 ['0以上のグリッド数を入力してください。']='Enter a grid count of 0 or more.',
 ['0以上の秒数を入力してください。']='Enter seconds of 0 or more.',
 ['アイテムを2つ以上選択してください。']='Select at least two items.',
 ['トラック毎の整列には、同一トラック上でアイテムを2つ以上選択してください。']='Select at least two items on one track.',
 ['すでに指定した間隔で整列しています。']='Items already have this spacing.',
 ['整列に失敗しました。元の位置に戻しました。']='Alignment failed. Positions restored.',
 ['整列に失敗しました。REAPERのUndoで戻してください。']='Alignment failed. Use REAPER Undo.',
 ['処理できませんでした。']='Could not process items.',
 ['BLT: Interval - 前回設定で処理']='BLT: Interval - Last settings',
 ['ファクトリーデフォルト']='Factory Default',
 ['ファクトリーデフォルトは変更できません。別の名前で保存してください。']='Factory Default is read-only. Save with a new name.',
 ['プリセットは200個まで保存できます。']='Up to 200 presets can be saved.',
 ['名前を付けて保存']='Save As', ['プリセット名:']='Preset name:',
 ['名前は1～120バイトで入力してください。改行と | < > ! # は使えません。']='Use 1-120 bytes. No line breaks or | < > ! #.',
 ['間隔の値を有効な範囲で入力してください。']='Enter valid spacing.',
 ['プリセットを保存しました: ']='Saved: ', ['プリセットを読み込みました: ']='Loaded: ',
 ['プリセットを読み込みました: ファクトリーデフォルト']='Loaded: Factory Default',
 ['現在のプリセットに未保存の変更があります。変更を破棄して読み込みますか？']='Discard unsaved changes and load the preset?',
 ['保存数が200個を超えるためインポートできません。']='Import would exceed 200 presets.',
 ['プリセットをインポート（個別／一覧）']='Import preset(s)',
 ['ファイルを開けません。']='Cannot open file.',
 ['INTERVAL用の有効なプリセットファイルではありません。']='Not a valid INTERVAL preset file.',
 ['プリセット一覧をエクスポート']='Export preset list', ['現在値をエクスポート']='Export current settings',
 ['現在値']='Current settings', ['保存先のフルパス:']='Full save path:',
 ['保存先のファイルを上書きしますか？']='Overwrite the existing file?',
 ['保存できません: ']='Cannot save: ', ['書き込みに失敗しました: ']='Write failed: ',
 ['現在値をエクスポートしました。']='Current settings exported.',
 ['CHAMELEON  REAPERテーマに擬態']='CHAMELEON  REAPER theme', ['CHAMELEON  オリジナル配色']='CHAMELEON  Original colors',
 ['カスタムタイトルバーには js_ReaScriptAPI が必要です。\nReaPack から js_ReaScriptAPI をインストールしてください。']='The app bar requires js_ReaScriptAPI.\nInstall js_ReaScriptAPI via ReaPack.',
 ['プリセット（読込・保存・インポート／エクスポート）']='Presets: load, save, import/export',
 ['前のプリセット']='Previous preset', ['次のプリセット']='Next preset', ['閉じる']='Close',
 ['ウィンドウサイズ初期化']='Reset window size', ['カメレオンモード（配色をテーマへ擬態）']='Chameleon: match REAPER colors',
 ['表示言語を切替（JP / EN）']='Switch language (JP / EN)',
 ['戻る']='Back', ['プリセット']='Presets', ['上書き保存']='Save', ['名前を付けて保存…']='Save As...', ['インポート…']='Import...',
 ['現在: ']='Current: ', ['未選択']='None',
 ['間隔モード']='SPACING', ['終了点 → 開始点']='End → Start', ['開始点 → 開始点']='Start → Start',
 ['全体']='All items', ['トラック毎']='By track', ['終了点 → 開始点の間隔']='End-to-start gap', ['開始点 → 開始点の間隔']='Start-to-start spacing',
 ['整列後にウィンドウを閉じる']='Close after align', ['最後に使ったモードを記憶']='Remember mode', ['整列を実行']='Align items',
 ['Interval | エラー']='Interval | Error', ['カスタムタイトルバーを初期化できません。']='Cannot initialize the app bar.',
}
LanguageCatalog.patterns={
 {'^(%d+)個のアイテムを整列しました。$','Aligned %s items.'},
 {'^同名のプリセットが(%d+)個あります。上書きしてインポートしますか？$','Overwrite %s preset(s) with matching names?'},
 {'^(%d+)個インポートしました。プリセット一覧から選択できます。$','Imported %s preset(s). Select from the list.'},
 {'^プリセット(%d+)個をエクスポートしました。$','Exported %s preset(s).'},
 {'^(%d+)–(%d+) / (%d+)   スクロールで選択$','%s–%s / %s   Scroll to browse'},
 {'^「(.*)」を上書きしますか？$','Overwrite "%s"?'},
}
LanguageCatalog.prefixes={'プリセットを保存しました: ','プリセットを読み込みました: ','保存できません: ','書き込みに失敗しました: '}

local Language=create_language(R,App.section,LanguageCatalog)
local Layout={
  width=468,height=508,minWidth=320,minHeight=382,maxWidth=1200,maxHeight=1426,
  bar={height=26,close=38,reset=34,theme=34,language=26,preset=84,arrow=20},
  title={x=24,y=8,size=35,subtitleX=26,subtitleY=44,subtitleSize=10,dividerY=62,
    iconX=366,iconY=9,iconScale=.78},
  footer={inset=24,bottom=13,height=11,size=9,versionSize=8,versionGap=14,dividerBottom=16},
  popup={width=286,rowHeight=29,headerHeight=34,visiblePresets=7,hoverDelay=1},
  controls={
    gap={30,150,198,44},start={240,150,198,44},
    scope_all={30,206,198,30},scope_track={240,206,198,30},input={30,266,408,82},
    unit_sec={76,358,154,32},unit_grid={238,358,154,32},
    close_after={30,408,202,28},remember_mode={238,408,200,28},apply={64,438,340,50},
  },
}
local UI={}

-- INTERVAL DOMAIN: normalization, selection planning and undo-safe execution.
local Core = {}
Core.value_specs={sec={min=0,max=3600000,step=1,digits=3},grid={min=0,max=1000000,step=1,digits=2}}

function Core.normalize(value,unit)
  local spec=Core.value_specs[unit or "sec"] or Core.value_specs.sec
  local s = tostring(value or ""):match("^%s*(.-)%s*$")
  if not s:match("^[%+%-]?%d*%.?%d*$") or not s:match("%d") then return nil,false end
  local n = tonumber(s)
  if not n or n ~= n or n == math.huge or n == -math.huge then return nil,false end
  local factor=10^spec.digits
  local value=math.max(spec.min,math.min(spec.max,n))
  value=math.floor(value*factor+.5)/factor
  return value,math.abs(value-n)>1e-12
end
function Core.parse(value,unit)
  return (Core.normalize(value,unit))
end
function Core.format(value,unit)
  local spec=Core.value_specs[unit or "sec"] or Core.value_specs.sec
  local n=Core.normalize(value,unit) or spec.min
  return string.format("%."..spec.digits.."f",n):gsub("0+$",""):gsub("%.$","")
end

function Core.collect(project)
  local items = {}
  for i = 0, R.CountSelectedMediaItems(project) - 1 do
    local item = R.GetSelectedMediaItem(project, i)
    if item and R.ValidatePtr2(project, item, "MediaItem*") then
      local track = R.GetMediaItemTrack(item)
      items[#items + 1] = {
        item = item, position = R.GetMediaItemInfo_Value(item, "D_POSITION"),
        length = R.GetMediaItemInfo_Value(item, "D_LENGTH"),
        locked = (math.floor(R.GetMediaItemInfo_Value(item, "C_LOCK")) & 1) ~= 0,
        track = R.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER"),
        index = R.GetMediaItemInfo_Value(item, "IP_ITEMNUMBER"),
      }
    end
  end
  table.sort(items, function(a, b)
    if a.position ~= b.position then return a.position < b.position end
    if a.track ~= b.track then return a.track < b.track end
    return a.index < b.index
  end)
  return items
end

function Core.grid_qn(project)
  local _, division = R.GetSetProjectGrid(project, false)
  if not division or division <= 0 or division ~= division or division == math.huge then
    return nil, "現在のグリッド設定を取得できません。"
  end
  -- GetSetProjectGrid uses whole-note units (0.25 = quarter note).
  -- TimeMap2_* uses quarter-note units, so multiply by four.
  return division * 4.0
end

local function advance_interval(project, reference, amount, unit, grid_qn)
  if unit == "grid" then
    local qn = R.TimeMap2_timeToQN(project, reference)
    if not qn or qn ~= qn or qn == math.huge then return nil end
    return R.TimeMap2_QNToTime(project, qn + amount * grid_qn)
  end
  return reference + amount
end

local function plan_sequence(project, items, interval, mode, unit, grid_qn, changes)
  if #items < 2 then return true end

  local anchor = items[1].position
  local previous = items[1].position
  for i = 2, #items do
    local reference = previous
    local target
    if mode == "gap" then
      local length = items[i - 1].length
      if not length or length < 0 or length ~= length or length == math.huge then
        return false, "アイテムの長さを確認してください。"
      end
      -- Use the preceding item's NEW end, not its original timeline position.
      reference = previous + length
      target = advance_interval(project, reference, interval, unit, grid_qn)
    else
      target = advance_interval(project, anchor, (i - 1) * interval, unit, grid_qn)
    end
    if not target or target ~= target or target == math.huge or target < reference then
      return false, "間隔が大きすぎるか、小さすぎます。"
    end
    previous = target
    if math.abs(items[i].position - target) > 1e-12 then
      if items[i].locked then return false, "移動するアイテムのロックを解除してください。" end
      changes[#changes + 1] = {item = items[i].item, before = items[i].position, after = target}
    end
  end
  return true
end

function Core.plan(project, items, interval, mode, unit, scope)
  mode = mode or "start"
  unit = unit or "sec"
  scope = scope or "all"
  if mode ~= "start" and mode ~= "gap" then return nil, "間隔のモードが無効です。" end
  if unit ~= "sec" and unit ~= "grid" then return nil, "間隔の単位が無効です。" end
  if scope ~= "all" and scope ~= "track" then return nil, "整列範囲のモードが無効です。" end
  if not interval or interval < 0 or interval ~= interval or interval == math.huge then
    return nil, unit == "grid" and "0以上のグリッド数を入力してください。" or "0以上の秒数を入力してください。"
  end
  if #items < 2 then return nil, "アイテムを2つ以上選択してください。" end

  local grid_qn = nil
  if unit == "grid" then
    local err
    grid_qn, err = Core.grid_qn(project)
    if not grid_qn then return nil, err end
  end

  local changes = {}
  if scope == "track" then
    local groups, order = {}, {}
    for _, item in ipairs(items) do
      local key = item.track
      if not groups[key] then
        groups[key] = {}
        order[#order + 1] = key
      end
      groups[key][#groups[key] + 1] = item
    end

    local eligible_tracks = 0
    for _, key in ipairs(order) do
      local group = groups[key]
      if #group >= 2 then
        eligible_tracks = eligible_tracks + 1
        local ok, err = plan_sequence(project, group, interval, mode, unit, grid_qn, changes)
        if not ok then return nil, err end
      end
    end
    if eligible_tracks == 0 then
      return nil, "トラック毎の整列には、同一トラック上でアイテムを2つ以上選択してください。"
    end
  else
    local ok, err = plan_sequence(project, items, interval, mode, unit, grid_qn, changes)
    if not ok then return nil, err end
  end

  return changes
end

function Core.apply(project, interval, mode, unit, scope)
  -- Re-read at click time: selection and active project may change while GUI is open.
  local items = Core.collect(project)
  local changes, err = Core.plan(project, items, interval, mode, unit, scope)
  if not changes then return false, err end
  if #changes == 0 then return true, "すでに指定した間隔で整列しています。" end
  R.Undo_BeginBlock2(project)
  R.PreventUIRefresh(1)
  local touched = {}
  local ok, detail = xpcall(function()
    for _, change in ipairs(changes) do
      touched[#touched + 1] = change
      if not R.SetMediaItemPosition(change.item, change.after, false) then
        error("SetMediaItemPosition failed")
      end
    end
  end, debug.traceback)
  local restored = true
  if not ok then
    for i = #touched, 1, -1 do
      local change = touched[i]
      local called, result = pcall(R.SetMediaItemPosition, change.item, change.before, false)
      if not called or not result then restored = false end
    end
  end
  R.PreventUIRefresh(-1)
  R.UpdateArrange()
  local unit_name = unit == "grid" and "grid" or "seconds"
  local scope_name = scope == "track" and "by track" or "all items"
  local undo_name = mode == "gap" and ("Interval: space selected items by end-to-start gap (" .. unit_name .. ", " .. scope_name .. ")")
    or ("Interval: align selected item starts (" .. unit_name .. ", " .. scope_name .. ")")
  R.Undo_EndBlock2(project, ok and undo_name or "Interval: failed alignment", 4)
  if not ok then
    R.ShowConsoleMsg("Interval error:\n" .. tostring(detail) .. "\n")
    return false, restored and "整列に失敗しました。元の位置に戻しました。"
      or "整列に失敗しました。REAPERのUndoで戻してください。"
  end
  return true, string.format("%d個のアイテムを整列しました。", #items)
end

-- HOST STATE: INTERVAL settings and persistence.
local SECTION = App.section
-- Persistent writes are coalesced by key while this window is alive.
-- Direct/headless processing still reads the latest stored values at invocation.
local State={written={}}
function State.set(key,value,persist)
  value=tostring(value)
  local previous=State.written[key]
  if previous==nil then previous=R.GetExtState(SECTION,key) end
  if previous~=value then R.SetExtState(SECTION,key,value,persist~=false) end
  State.written[key]=value
end
local saved_seconds = R.GetExtState(SECTION, "seconds")
local saved_grid_value = R.GetExtState(SECTION, "grid_value")
local seconds_value = Core.parse(saved_seconds,"sec") and Core.format(saved_seconds,"sec") or "1"
local grid_value = Core.parse(saved_grid_value,"grid") and Core.format(saved_grid_value,"grid") or "1"
local remember_mode = R.GetExtState(SECTION, "remember_mode") == "1"
local saved_mode = R.GetExtState(SECTION, "last_mode")
local saved_unit = R.GetExtState(SECTION, "last_unit")
local saved_scope = R.GetExtState(SECTION, "last_scope")
local mode = remember_mode and (saved_mode == "start" and "start" or "gap") or "gap"
local unit = remember_mode and (saved_unit == "grid" and "grid" or "sec") or "sec"
local scope = remember_mode and (saved_scope == "track" and "track" or "all") or "all"
local value = unit == "grid" and grid_value or seconds_value
local close_after = R.GetExtState(SECTION, "close_after") == "1"

-- This branch returns before any gfx/js_ReaScriptAPI window code is initialized.
if rawget(_G,"BLT_INTERVAL_INVOCATION")=="process_last" then
  local process_mode=R.GetExtState(SECTION,"process_mode")
  if process_mode~="start" and process_mode~="gap" then process_mode=mode end
  local process_unit=R.GetExtState(SECTION,"process_unit")
  if process_unit~="sec" and process_unit~="grid" then process_unit=unit end
  local process_scope=R.GetExtState(SECTION,"process_scope")
  if process_scope~="all" and process_scope~="track" then process_scope=scope end
  local process_seconds=R.GetExtState(SECTION,"process_seconds")
  if not Core.parse(process_seconds,"sec") then process_seconds=seconds_value end
  local process_grid=R.GetExtState(SECTION,"process_grid_value")
  if not Core.parse(process_grid,"grid") then process_grid=grid_value end
  local process_value=process_unit=="grid" and process_grid or process_seconds
  local interval=Core.parse(process_value,process_unit)
  local ok,message=Core.apply(R.EnumProjects(-1,""),interval,process_mode,process_unit,process_scope)
  if not ok then Language.mb(message or "処理できませんでした。","BLT: Interval - 前回設定で処理",0) end
  return
end
local saved_window_x = tonumber(R.GetExtState(SECTION, "window_x"))
local saved_window_y = tonumber(R.GetExtState(SECTION, "window_y"))
local saved_window_w = tonumber(R.GetExtState(SECTION, "window_w"))
local saved_window_h = tonumber(R.GetExtState(SECTION, "window_h"))
local last_window_x, last_window_y = saved_window_x, saved_window_y
local last_window_w, last_window_h = saved_window_w, saved_window_h
local closing = false
local caret, selected, focused = #value, true, true
local status, status_ok, status_until = "", false, 0
local Footer={message="",clipped=false}
local field_flash_at,field_drag=nil,nil
local last_down, pressed = false, nil
local scale, ox, oy = 1, 0, 0
local W, H = Layout.width,Layout.height

local C = {
  bg       = {0.018, 0.030, 0.055},
  bg2      = {0.030, 0.090, 0.180},
  panel    = {0.040, 0.068, 0.110},
  panel2   = {0.055, 0.125, 0.205},
  field    = {0.018, 0.040, 0.080},
  edge     = {0.145, 0.285, 0.445},
  edge2    = {0.360, 0.650, 0.900},
  text     = {0.955, 0.980, 1.000},
  muted    = {0.690, 0.780, 0.875},
  faint    = {0.390, 0.505, 0.635},
  accent   = {0.120, 0.490, 0.980},
  accent2  = {0.650, 0.895, 1.000},
  accent3  = {0.045, 0.235, 0.520},
  focus    = {0.225, 0.610, 1.000},
  focus2   = {0.690, 0.900, 1.000},
  ink      = {0.018, 0.075, 0.160},
  hover    = {0.430, 0.790, 1.000},
  warn     = {1.000, 0.755, 0.490},
  red      = {1.000, 0.230, 0.300},
}
local C_DEFAULT={}
for k,v in pairs(C) do C_DEFAULT[k]={v[1],v[2],v[3]} end
-- Chameleon runtime state.
-- The theme adapter itself is kept as one self-contained block below so it can
-- be transplanted to other BLT scripts with minimal changes.
local Chameleon={
  enabled=R.GetExtState(SECTION,"chameleon")=="1",
  signature=nil,
  poll_at=0,
  poll_interval=3.0,
}
local motion, frame_clock, frame_dt, anim_time = {}, R.time_precise(), 1/60, 0
local hud_particles = {}
local hud_particle_clock = 0
local hud_particle_serial = 0
local animations_active=true
local animation_speed=1
local EFFECT_IDLE_TAIL=2.5
local EFFECT_COAST=0.70
local effect_activity_until=R.time_precise()+EFFECT_IDLE_TAIL
local redraw_dirty=true
local next_draw_time=0
local next_display_update=0
local last_status_visible,last_caret_phase=nil,nil
local last_view_w,last_view_h,last_view_dpi=nil,nil,nil
local last_raw_mouse_x,last_raw_mouse_y,last_raw_mouse_cap=nil,nil,nil
local last_window_active=nil
local last_state_poll=0
local last_seen_state,last_seen_project=nil,nil
local function wake_visuals(now)
  now=now or R.time_precise(); redraw_dirty=true
  effect_activity_until=math.max(effect_activity_until,now+EFFECT_IDLE_TAIL)
  if next_draw_time==math.huge then next_draw_time=now end
end
local function visual_speed(now)
  local remain=effect_activity_until-(now or R.time_precise())
  if remain<=0 then return 0 end
  if remain>=EFFECT_COAST then return 1 end
  local t=math.max(0,math.min(1,remain/EFFECT_COAST))
  return t*t*(3-2*t)
end
local function particle_hash(n, salt)
  local v=math.sin(n*12.9898+salt*78.233)*43758.5453
  return v-math.floor(v)
end
local animation_blend=0
local function animate(key, target)
  local previous = motion[key]
  if previous == nil then previous = target end
  local v = previous + (target-previous)*animation_blend
  motion[key] = v
  return v
end

local fonts = {"Yu Gothic UI", "Segoe UI", "Consolas"}
if R.GetOS():match("OSX") then fonts = {"Hiragino Sans", "Helvetica Neue", "Menlo"} end
if R.GetOS():match("Linux") then fonts = {"sans-serif", "sans-serif", "monospace"} end
fonts[4]=R.GetOS():match("Win") and "Segoe UI" or (R.GetOS():match("OSX") and "Helvetica Neue" or "sans-serif")

local function sx(x) return ox + x * scale end
local function sy(y) return oy + y * scale end
local function color(c, alpha) gfx.set(c[1], c[2], c[3], alpha or 1) end
local function rect(x,y,w,h,c,alpha)
  color(c,alpha); gfx.rect(sx(x),sy(y),w*scale,h*scale,1)
end
local function line(x,y,x2,y2,c,alpha)
  color(c,alpha); gfx.line(sx(x),sy(y),sx(x2),sy(y2),1)
end
local function glow_line(x,y,x2,y2,c,strength)
  strength=strength or 1
  line(x,y-5,x2,y2-5,c,0.018*strength)
  line(x,y+5,x2,y2+5,c,0.018*strength)
  line(x,y-4,x2,y2-4,c,0.028*strength)
  line(x,y+4,x2,y2+4,c,0.028*strength)
  line(x,y-3,x2,y2-3,c,0.045*strength)
  line(x,y+3,x2,y2+3,c,0.045*strength)
  line(x,y-2,x2,y2-2,c,0.075*strength)
  line(x,y+2,x2,y2+2,c,0.075*strength)
  line(x,y-1,x2,y2-1,c,0.15*strength)
  line(x,y+1,x2,y2+1,c,0.15*strength)
  line(x,y,x2,y2,c,0.95*strength)
end
local function disc(x,y,r,c,alpha)
  color(c,alpha); gfx.circle(sx(x),sy(y),r*scale,1,1)
end

local function cut_panel(x,y,w,h,cut,c,alpha,edge,edge_alpha,top_left)
  local tl=top_left and cut or 0
  local pts = {
    {x+tl,y}, {x+w,y}, {x+w,y+h-cut},
    {x+w-cut,y+h}, {x,y+h}, {x,y+tl},
  }
  local cx,cy=x+w/2,y+h/2
  color(c,alpha)
  for i=1,#pts do
    local a,b=pts[i],pts[i%#pts+1]
    gfx.triangle(sx(cx),sy(cy),sx(a[1]),sy(a[2]),sx(b[1]),sy(b[2]))
  end
  if edge then
    for i=1,#pts do
      local a,b=pts[i],pts[i%#pts+1]
      line(a[1],a[2],b[1],b[2],edge,edge_alpha or 1)
    end
  end
end
local function finish_corners(x,y,w,h,cut,top_left,edge,alpha)
  color(C.bg)
  gfx.triangle(sx(x+w-cut-1),sy(y+h+1),sx(x+w+1),sy(y+h-cut-1),sx(x+w+1),sy(y+h+1))
  if top_left then
    gfx.triangle(sx(x-1),sy(y-1),sx(x+cut+1),sy(y-1),sx(x-1),sy(y+cut+1))
  end
  line(x+w,y+h-cut,x+w-cut,y+h,edge,alpha)
  if top_left then line(x,y+cut,x+cut,y,edge,alpha) end
end

-- BLT COMMON RENDERING: pixel-keyed fonts and text metrics.
local FONT_SLOT_IDS={}
for i=1,15 do if i~=7 then FONT_SLOT_IDS[#FONT_SLOT_IDS+1]=i end end
local FONT_FALLBACK_SLOT=16
local font_slot_map={}
local font_slot_next=1
local font_cache_key=nil
local fallback_font_key=nil
local text_measure_cache={}
local text_measure_cache_count=0
local font_specs={}
local fit_cache,fit_cache_count={},0
local function font_spec(size,kind,bold)
  kind=kind or 1
  local px=math.max(8,math.floor((size or 10)*scale+0.5));local weight=bold and 98 or 0
  local group=kind*2+(bold and 1 or 0)
  local sizes=font_specs[group]
  if not sizes then sizes={};font_specs[group]=sizes end
  local record=sizes[px]
  if not record then record={kind,px,weight,kind..":"..px..":"..weight};sizes[px]=record end
  return record[1],record[2],record[3],record[4]
end
-- Rebuild native slots only on a real viewport-scale/DPI change, never when
-- temporarily scaling the header illustration. REAPER supports slots 1..16.
function UI.fontViewport(viewScale,dpi)
  if UI.fontScale==viewScale and UI.fontDPI==dpi then return end
  font_slot_map={};font_slot_next=1;fallback_font_key=nil;font_cache_key=nil
  if UI.fontDPI~=dpi then text_measure_cache={};text_measure_cache_count=0;fit_cache={};fit_cache_count=0 end
  UI.fontScale,UI.fontDPI=viewScale,dpi
end
local function font(size,kind,bold)
  local fk,px,weight,key=font_spec(size,kind,bold)
  if key==font_cache_key then return end
  local slot=font_slot_map[key]
  if slot then
    gfx.setfont(slot)
  elseif font_slot_next<=#FONT_SLOT_IDS then
    slot=FONT_SLOT_IDS[font_slot_next]; font_slot_next=font_slot_next+1; font_slot_map[key]=slot
    gfx.setfont(slot,fonts[fk],px,weight)
  else
    if fallback_font_key==key then gfx.setfont(FONT_FALLBACK_SLOT)
    else gfx.setfont(FONT_FALLBACK_SLOT,fonts[fk],px,weight);fallback_font_key=key end
  end
  font_cache_key=key
end
local function label(text,x,y,size,c,kind,w,h,flags,bold)
  font(size,kind,bold); color(c or C.text); gfx.x,gfx.y=sx(x),sy(y)
  local translated=Language.text(text)
  if translated~=text and w then translated=UI.fit(translated,w*scale) end
  text=translated
  gfx.drawstr(text,flags or 0,sx(x+(w or 540)),sy(y+(h or size+8)))
end
function UI.textMetrics(text)
  local key=font_cache_key or "chrome"
  local bucket=text_measure_cache[key]
  local entry=bucket and bucket[text]
  if entry then return entry[1],entry[2] end
  local w,h=gfx.measurestr(text)
  if text_measure_cache_count>=2048 then text_measure_cache={};text_measure_cache_count=0;bucket=nil end
  if not bucket then bucket={};text_measure_cache[key]=bucket end
  bucket[text]={w,h};text_measure_cache_count=text_measure_cache_count+1
  return w,h
end
local function measure(text,size,kind,bold)
  font(size,kind,bold)
  return UI.textMetrics(Language.text(text))/scale
end
local function right_label(text,right,y,size,c,kind,bold)
  local tw=measure(text,size,kind,bold); label(text,right-tw,y,size,c,kind,tw+2,size+9,0,bold)
end
local function inside(x,y,w,h)
  local mx,my=(gfx.mouse_x-ox)/scale,(gfx.mouse_y-oy)/scale
  return mx>=x and mx<=x+w and my>=y and my<=y+h
end
local function notice(message,ok)
  status,status_ok,status_until=message,ok,R.time_precise()+4
  wake_visuals()
end

-- Native gradients: derivatives are per physical pixel, including at HiDPI sizes.
local function gradient(x,y,w,h,a,b,alpha1,alpha2,vertical)
  local aa1=alpha1 or 1; local aa2=alpha2==nil and 1 or alpha2
  local n=math.max(1,(vertical and h or w)*scale)
  if (a==b or (a[1]==b[1] and a[2]==b[2] and a[3]==b[3])) and aa1==aa2 then rect(x,y,w,h,a,aa1); return end
  if n<=1.01 then rect(x,y,w,h,a,aa1); return end
  local dr,dg,db=(b[1]-a[1])/n,(b[2]-a[2])/n,(b[3]-a[3])/n
  local da=(aa2-aa1)/n
  gfx.gradrect(sx(x),sy(y),w*scale,h*scale,a[1],a[2],a[3],aa1,
    vertical and 0 or dr,vertical and 0 or dg,vertical and 0 or db,vertical and 0 or da,
    vertical and dr or 0,vertical and dg or 0,vertical and db or 0,vertical and da or 0)
end

local HUD_WAVEFORM={4,8,6,10,7,5,8}
local function hud_icon(x,y,mode,window_active,particle_dt)
  local w,h=98,62
  local a_start,a_end=x+12,x+42
  local b_start=x+65
  local target_a=mode=="start" and a_start or a_end
  local edge_a=animate("icon_edge_a",target_a)
  local edge_b=b_start
  local item_y=y+36
  local measure_y=y+24
  local cx=(edge_a+edge_b)/2

  local breathe=0.5+0.5*math.sin(anim_time*0.72)
  for i=1,9 do
    local phase=anim_time*(0.16+(i%3)*0.035)+i*1.73
    local px=cx+math.sin(phase*1.37)*13+math.cos(phase*0.71+i)*5
    local py=y+34+math.cos(phase*0.91)*8-(i%3)*2
    local rr=10+(i%4)*4+breathe*2
    disc(px,py,rr+8,C.accent,0.006+0.004*breathe)
    disc(px,py,rr,C.accent3,0.010+0.006*breathe)
    disc(px+2,py-1,rr*0.55,C.accent2,0.007)
  end

  if window_active then
    hud_particle_clock=hud_particle_clock+frame_dt
    local spawn_interval=0.075
    while hud_particle_clock>=spawn_interval and #hud_particles<36 do
      hud_particle_clock=hud_particle_clock-spawn_interval
      hud_particle_serial=hud_particle_serial+1
      local n=hud_particle_serial
      local h1=particle_hash(n,21)
      local h2=particle_hash(n,22)
      local h3=particle_hash(n,23)
      local h4=particle_hash(n,24)
      local h5=particle_hash(n,25)
      local h6=particle_hash(n,26)
      local origin=(n%2==0) and edge_a or edge_b
      hud_particles[#hud_particles+1]={
        x=origin+(h1-0.5)*9.0,
        y=y+49+(h2-0.5)*4.0,
        vx=(h3-0.5)*5.5,
        vy=9.5+h4*8.0,
        sway=1.4+h5*3.2,
        freq=1.1+h6*1.5,
        phase=h1*math.pi*2,
        life=1.9+h2*1.35,
        age=0,
        r=0.45+h3*0.65,
        glint=(n%6==0),
      }
    end
  else
    hud_particle_clock=math.min(hud_particle_clock,0.03)
  end

  for i=#hud_particles,1,-1 do
    local p=hud_particles[i]
    p.age=p.age+(particle_dt or 0)
    if p.age>=p.life then
      table.remove(hud_particles,i)
    else
      local t=p.age/p.life
      local envelope=math.sin(math.pi*t)^2
      local px=p.x+p.vx*p.age+math.sin(p.age*p.freq+p.phase)*p.sway
      local py=p.y-p.vy*p.age
      disc(px,py,p.r+4.0,C.accent,0.020*envelope)
      disc(px,py,p.r+1.8,C.accent2,0.060*envelope)
      if p.glint then
        disc(px,py,p.r+0.35,C.text,0.50*envelope)
        rect(px-0.35,py-2.1,0.7,4.2,C.focus2,0.26*envelope)
        rect(px-2.1,py-0.35,4.2,0.7,C.focus2,0.20*envelope)
      else
        disc(px,py,p.r,C.focus2,0.62*envelope)
      end
    end
  end

  -- Two restrained media-item strips.
  for _,left in ipairs({a_start,b_start}) do
    gradient(left,item_y,30,15,C.panel2,C.panel,0.84,0.70)
    line(left,item_y,left+30,item_y,C.edge2,0.48)
    line(left,item_y+15,left+30,item_y+15,C.edge,0.38)
    for i,bh in ipairs(HUD_WAVEFORM) do
      rect(left+4+(i-1)*3.2,item_y+7.5-bh/2,1.1,bh,C.muted,0.78)
    end
  end

  -- The actual measured edges remain crisp above the atmospheric effect.
  glow_line(edge_a,measure_y,edge_b,measure_y,C.accent,0.28+0.08*breathe)
  line(edge_a,measure_y,edge_b,measure_y,C.accent2,0.92)
  for _,edge in ipairs({edge_a,edge_b}) do
    rect(edge-1,item_y-3,2,22,C.accent2,0.96)
    disc(edge,measure_y,5.8,C.accent,0.055+0.025*breathe)
    disc(edge,measure_y,1.5,C.text,0.92)
  end

  -- One slow spark crosses the interval, tying the haze to the measurement.
  local travel=(anim_time*0.28)%1
  local pulse_x=edge_a+(edge_b-edge_a)*travel
  disc(pulse_x,measure_y,6.5,C.accent,0.035)
  disc(pulse_x,measure_y,2.7,C.accent2,0.10)
  disc(pulse_x,measure_y,1.0,C.text,0.88)

  local caption=mode=="start" and "START / START" or "END / START"
  right_label(caption,x+w-2,y+2,7,C.muted,3,true)
end

local function stash_current_value()
  if unit == "grid" then grid_value = value else seconds_value = value end
end

-- The companion direct-processing action always follows the last GUI configuration,
-- independently of the GUI startup option "最後に使ったモードを記憶".
local function persist_process_settings()
  local current,clipped=Core.normalize(value,unit)
  if current and not clipped then stash_current_value() end
  State.set("process_mode",mode,true)
  State.set("process_unit",unit,true)
  State.set("process_scope",scope,true)
  local seconds=Core.normalize(seconds_value,"sec")
  local grids=Core.normalize(grid_value,"grid")
  if seconds then State.set("process_seconds",Core.format(seconds,"sec"),true) end
  if grids then State.set("process_grid_value",Core.format(grids,"grid"),true) end
end

-- PRESET DATA ADAPTER: encode/decode/capture/apply are INTERVAL-specific.
-- Portable presets: data only, never evaluate imported Lua/code.
local Presets={items={},current=nil,header=App.section.."_PRESET_V1"}
function Presets.name(s)
  s=tostring(s or ""):match("^%s*(.-)%s*$")
  if not utf8.len(s) or s=="" or #s>120 or s:find("[%c|<>!#]") then return nil end
  return s
end
function Presets.encode(p)
  return table.concat({Presets.header,p.name,p.mode,p.scope,p.unit,p.seconds,p.grid,p.close and "1" or "0",p.remember and "1" or "0"},"\n")
end
function Presets.decode(s)
  if type(s)~="string" or #s>4096 then return nil end
  s=s:gsub("\r\n","\n")
  local a={}; for line in (s.."\n"):gmatch("(.-)\n") do a[#a+1]=line end
  if #a~=9 or a[1]~=Presets.header or not Presets.name(a[2]) then return nil end
  if (a[3]~="gap" and a[3]~="start") or (a[4]~="all" and a[4]~="track") or (a[5]~="sec" and a[5]~="grid") then return nil end
  local sec,sc=Core.normalize(a[6],"sec"); local grid,gc=Core.normalize(a[7],"grid")
  if not sec or sc or not grid or gc or (a[8]~="0" and a[8]~="1") or (a[9]~="0" and a[9]~="1") then return nil end
  return {name=Presets.name(a[2]),mode=a[3],scope=a[4],unit=a[5],seconds=Core.format(sec,"sec"),grid=Core.format(grid,"grid"),close=a[8]=="1",remember=a[9]=="1"}
end
function Presets.capture(name)
  local n,clipped=Core.normalize(value,unit)
  if not n or clipped then return nil end
  local s=unit=="sec" and Core.format(n,"sec") or seconds_value
  local g=unit=="grid" and Core.format(n,"grid") or grid_value
  return Presets.decode(Presets.encode({name=name,mode=mode,scope=scope,unit=unit,seconds=s,grid=g,close=close_after,remember=remember_mode}))
end
function Presets.dirty()
  if not Presets.current then return false end
  local c=Presets.dirtyCache
  if c and c.current==Presets.current and c.value==value and c.seconds==seconds_value and c.grid==grid_value
    and c.mode==mode and c.scope==scope and c.unit==unit and c.close==close_after and c.remember==remember_mode then return c.result end
  local snapshot=Presets.capture(Presets.current.name)
  local result=not snapshot or Presets.encode(snapshot)~=Presets.encode(Presets.current)
  Presets.dirtyCache={current=Presets.current,value=value,seconds=seconds_value,grid=grid_value,
    mode=mode,scope=scope,unit=unit,close=close_after,remember=remember_mode,result=result}
  return result
end
function Presets.flush()
  Presets.revision=(Presets.revision or 0)+1
  State.set("preset_count",tostring(#Presets.items),true)
  for i,p in ipairs(Presets.items) do
    -- ExtState is INI-backed: encode all line breaks for persistence.
    State.set("preset_"..i,Presets.encode(p):gsub("%%","%%25"):gsub("\n","%%0A"),true)
  end
end
do
  local count=math.min(200,math.max(0,tonumber(R.GetExtState(SECTION,"preset_count")) or 0))
  for i=1,count do
    local s=R.GetExtState(SECTION,"preset_"..i):gsub("%%0A","\n"):gsub("%%25","%%")
    local p=Presets.decode(s); if p and p.name~="ファクトリーデフォルト" then Presets.items[#Presets.items+1]=p end
  end
end
function Presets.put(p)
  if Presets.isFactory(p) then notice("ファクトリーデフォルトは変更できません。別の名前で保存してください。",false);return false end
  for i,old in ipairs(Presets.items) do
    if old.name==p.name then
      if Language.mb('「'..p.name..'」を上書きしますか？',"PRESET",4)~=6 then return false end
      Presets.items[i]=p; Presets.flush(); return true
    end
  end
  if #Presets.items>=200 then notice("プリセットは200個まで保存できます。",false);return false end
  Presets.items[#Presets.items+1]=p
  table.sort(Presets.items,function(a,b) return a.name<b.name end)
  Presets.flush();return true
end
function Presets.save(as_new)
  if not as_new and Presets.isFactory(Presets.current) then return end
  local name=Presets.current and not Presets.isFactory(Presets.current) and Presets.current.name or ""
  if as_new or name=="" then
    local ok,s=Language.input("名前を付けて保存",1,"プリセット名:",name)
    if not ok then return end
    name=Presets.name(s)
    if not name then notice("名前は1～120バイトで入力してください。改行と | < > ! # は使えません。",false);return end
  end
  local p=Presets.capture(name)
  if not p then notice("間隔の値を有効な範囲で入力してください。",false);return end
  if Presets.put(p) then Presets.current=p;notice("プリセットを保存しました: "..name,true) end
end
function Presets.apply(p)
  if Presets.dirty() and Language.mb("現在のプリセットに未保存の変更があります。変更を破棄して読み込みますか？","PRESET",4)~=6 then return end
  mode,scope,unit=p.mode,p.scope,p.unit
  seconds_value,grid_value=p.seconds,p.grid
  close_after,remember_mode=p.close,p.remember
  value=unit=="grid" and grid_value or seconds_value
  caret=#value;selected=true;focused=false;field_drag=nil
  for k,v in pairs({seconds=seconds_value,grid_value=grid_value,last_mode=mode,last_unit=unit,last_scope=scope,close_after=close_after and "1" or "0",remember_mode=remember_mode and "1" or "0"}) do State.set(k,v,true) end
  persist_process_settings();Presets.current=p;wake_visuals()
  notice("プリセットを読み込みました: "..p.name,true)
end
Presets.bundleHeader=App.section.."_PRESET_BUNDLE_V1"
Presets.factory={name="ファクトリーデフォルト",mode="gap",scope="all",unit="sec",seconds="1",grid="1",close=false,remember=false,factory=true}
function Presets.isFactory(p)
  return p and (p.factory or p.name==Presets.factory.name)
end
-- Factory is always index 1; saved presets follow their existing sorted order.
function Presets.step(direction)
  local index=nil
  if Presets.isFactory(Presets.current) then index=1
  elseif Presets.current then
    for i,p in ipairs(Presets.items) do if p.name==Presets.current.name then index=i+1;break end end
  end
  local nextIndex=index and ((index-1+direction)%(#Presets.items+1)+1) or 1
  local target=nextIndex==1 and Presets.factory or Presets.items[nextIndex-1]
  Presets.apply(target)
end
function Presets.encodeBundle(items)
  local parts={Presets.bundleHeader,tostring(#items)}
  for _,p in ipairs(items) do parts[#parts+1]=Presets.encode(p) end
  return table.concat(parts,"\n")
end
function Presets.decodeTransfer(data)
  if type(data)~="string" or #data>1048576 then return nil end
  data=data:gsub("\r\n","\n")
  local single=Presets.decode(data)
  if single then return not Presets.isFactory(single) and {single} or nil end
  local a={};for line in (data.."\n"):gmatch("(.-)\n") do a[#a+1]=line end
  if a[1]~=Presets.bundleHeader then return nil end
  local n=tonumber(a[2]);if not n or n%1~=0 or n<1 or n>200 or #a~=2+n*9 then return nil end
  local items,names={},{}
  for i=1,n do
    local p=Presets.decode(table.concat(a,"\n",3+(i-1)*9,2+i*9))
    if not p or Presets.isFactory(p) or names[p.name] then return nil end
    names[p.name]=true;items[#items+1]=p
  end
  return items
end
function Presets.merge(items)
  local merged,index={},{}
  for i,p in ipairs(Presets.items) do merged[i]=p;index[p.name]=i end
  local conflicts=0
  for _,p in ipairs(items) do
    if Presets.isFactory(p) then return false end
    if index[p.name] then conflicts=conflicts+1;merged[index[p.name]]=p
    else merged[#merged+1]=p;index[p.name]=#merged end
  end
  if #merged>200 then notice("保存数が200個を超えるためインポートできません。",false);return false end
  if conflicts>0 and Language.mb(string.format("同名のプリセットが%d個あります。上書きしてインポートしますか？",conflicts),"PRESET",4)~=6 then return false end
  table.sort(merged,function(a,b) return a.name<b.name end)
  Presets.items=merged;Presets.flush();return true
end
function Presets.import()
  local ok,path=Language.open("","プリセットをインポート（個別／一覧）","bltpreset")
  if not ok then return end
  local f=io.open(path,"rb")
  if not f then notice("ファイルを開けません。",false);return end
  local data=f:read(1048577);f:close()
  local items=Presets.decodeTransfer(data)
  if not items then notice("INTERVAL用の有効なプリセットファイルではありません。",false);return end
  if Presets.merge(items) then notice(string.format("%d個インポートしました。プリセット一覧から選択できます。",#items),true) end
end
function Presets.export(all)
  local data,file,title
  if all then
    if #Presets.items==0 then return end
    data=Presets.encodeBundle(Presets.items);file="INTERVAL_presets.bltpreset";title="プリセット一覧をエクスポート"
  else
    if Presets.isFactory(Presets.current) then return end
    local p=Presets.capture(Presets.current and Presets.current.name or "現在値")
    if not p then notice("間隔の値を有効な範囲で入力してください。",false);return end
    data=Presets.encode(p);file=p.name:gsub('[\\/:*?"<>|]','_')..".bltpreset";title="現在値をエクスポート"
  end
  local ok,path
  if R.JS_Dialog_BrowseForSaveFile then
    ok,path=Language.save(title,"",file,"BLT Preset (*.bltpreset)\0*.bltpreset\0")
    if not ok or ok==0 or not path or path=="" then return end
  else
    ok,path=Language.input(title,1,"保存先のフルパス:",R.GetResourcePath().."/"..file)
    if not ok or path=="" then return end
  end
  if not path:lower():match("%.bltpreset$") then path=path..".bltpreset" end
  local existing=io.open(path,"rb")
  if existing then existing:close();if Language.mb("保存先のファイルを上書きしますか？","PRESET",4)~=6 then return end end
  local f,err=io.open(path,"wb")
  if not f then notice("保存できません: "..tostring(err),false);return end
  local written,werr=f:write(data);local closed,cerr=f:close()
  if not written or not closed then notice("書き込みに失敗しました: "..tostring(werr or cerr),false);return end
  notice(all and string.format("プリセット%d個をエクスポートしました。",#Presets.items) or "現在値をエクスポートしました。",true)
end

local function format_interval_value(n)
  return Core.format(n,unit)
end
local function flash_value()
  if not field_flash_at then return 0 end
  local age=R.time_precise()-field_flash_at
  if age>=1.15 then field_flash_at=nil;return 0 end
  local q=math.max(0,math.min(1,age/1.15));return 1-q*q*(3-2*q)
end
local function set_interval_number(n,flash)
  local normalized,clipped=Core.normalize(n,unit)
  if not normalized then
    if flash then field_flash_at=R.time_precise() end
    local fallback=unit=="grid" and grid_value or seconds_value
    normalized=Core.parse(fallback,unit) or 0
  end
  if clipped and flash then field_flash_at=R.time_precise() end
  value=format_interval_value(normalized);caret=#value;selected=false;focused=true;status_until=0
  persist_process_settings();return true
end
local function interval_adjustment_step(shift_down)
  local step=Core.value_specs[unit].step
  return unit=="sec" and shift_down and step*.1 or step
end
local function update_value_drag(py,shift_down)
  if not field_drag then return end
  local step=interval_adjustment_step(shift_down)
  -- Rebase when Shift changes mid-drag so the existing displacement is not rescaled.
  if field_drag.step and field_drag.step~=step then
    field_drag.start_y=py
    field_drag.start_value=Core.parse(value,unit) or field_drag.start_value
    field_drag.step=step
    return
  end
  field_drag.step=step
  local dy=field_drag.start_y-py
  if not field_drag.moved and math.abs(dy)<3 then return end
  field_drag.moved=true
  local q=dy/3;local ticks=(q<0 and -1 or 1)*math.floor(math.abs(q)+.5)
  local raw=field_drag.start_value+ticks*step
  local normalized,clipped=Core.normalize(raw,unit);if not normalized then return end
  if clipped and not field_drag.clipped then field_flash_at=R.time_precise();field_drag.clipped=true elseif not clipped then field_drag.clipped=false end
  local next_value=format_interval_value(normalized)
  if next_value~=value then value=next_value;caret=#value;selected=false;focused=true;status_until=0;persist_process_settings() end
end
local function select_unit(next_unit)
  if next_unit~="sec" and next_unit~="grid" then return end
  if set_interval_number(value,true) then stash_current_value() end
  unit=next_unit
  value=unit=="grid" and grid_value or seconds_value
  caret=#value;selected=true;focused=true;status_until=0
  if remember_mode then State.set("last_unit",unit,true) end
  persist_process_settings()
end
local function execute()
  local project=R.EnumProjects(-1,"")
  local interval,clipped=Core.normalize(value,unit)
  if not interval then set_interval_number(value,true);interval=Core.parse(value,unit)
  else
    if clipped then field_flash_at=R.time_precise() end
    value=format_interval_value(interval);caret=#value;persist_process_settings()
  end
  local ok,message=Core.apply(project,interval,mode,unit,scope)
  notice(message,ok)
  if ok then
    stash_current_value()
    if unit=="grid" then State.set("grid_value",grid_value,true)
    else State.set("seconds",seconds_value,true) end
    if close_after then closing=true end
  end
end
local function replace(s)
  local next_value=selected and s or (value:sub(1,caret)..s..value:sub(caret+1))
  if #next_value<=18 then
    value=next_value;caret=selected and #s or caret+#s;selected=false;status_until=0
  end
end
local function adjust_value_by_wheel(wheel,shift_down)
  if wheel==0 then return end
  local current,clipped=Core.normalize(value,unit);current=current or 0
  if clipped then field_flash_at=R.time_precise() end
  local step=interval_adjustment_step(shift_down)
  local notches=math.max(1,math.floor(math.abs(wheel)/120+.5))
  set_interval_number(current+(wheel>0 and 1 or -1)*step*notches,true)
end

local function keypress(k)
  if k==13 then execute(); return end
  if k==9 then
    if focused then set_interval_number(value,true);focused=false;selected=false
    else focused=true;selected=true;caret=#value end
    return
  end
  if not focused then return end
  local changed=false
  if k==1 then selected=true
  elseif k==8 then
    if selected then value=""; caret=0; changed=true
    elseif caret>0 then value=value:sub(1,caret-1)..value:sub(caret+1); caret=caret-1; changed=true end
    selected=false; status_until=0
  elseif k==6579564 then
    if selected then value=""; caret=0; changed=true
    elseif caret<#value then value=value:sub(1,caret)..value:sub(caret+2); changed=true end
    selected=false; status_until=0
  elseif k==1818584692 then caret=selected and 0 or math.max(0,caret-1); selected=false
  elseif k==1919379572 then caret=selected and #value or math.min(#value,caret+1); selected=false
  elseif k==1752132965 then caret=0; selected=false
  elseif k==6647396 then caret=#value; selected=false
  elseif k>=48 and k<=57 or k==46 or k==45 or k==43 then replace(string.char(k)); return end
  if changed then redraw_dirty=true end
end

local function draw_background()
  rect(0,0,W,H,C.bg)
  -- Low-contrast glass atmosphere: fixed, not distracting.
  disc(W-26,42,125,C.accent,0.018)
  disc(16,H-46,105,C.bg2,0.030)
  gradient(0,0,W,Layout.title.dividerY,C.bg2,C.bg,0.22,0,true)
  line(24,Layout.title.dividerY,W-24,Layout.title.dividerY,C.edge2,0.28)
  line(24,H-Layout.footer.dividerBottom,W-24,H-Layout.footer.dividerBottom,C.edge2,0.16)
  -- Sparse technical ticks on the left rail.
  line(20,128,20,380,C.edge2,0.18)
  for y=140,374,18 do line(20,y,25,y,C.edge2,0.14) end
end

local function draw_mode_card(key,x,y,w,title,code,active,hovered)
  local a=animate("mode_"..key,active and 1 or (hovered and 0.30 or 0))
  -- Keep the current glass treatment, but restore the clipped-corner silhouette.
  gradient(x,y,w,44,C.panel2,C.panel,0.28+0.26*a,0.70)
  if a>0.01 then
    gradient(x+3,y,w-3,44,C.accent3,C.accent3,0.18*a,0)
    rect(x,y+8,3,28,C.accent2,0.70*a)
    glow_line(x+8,y,x+60,y,C.accent2,0.32*a)
  end
  line(x,y,x+w,y,C.edge2,0.18+0.45*a)
  line(x,y+44,x+w,y+44,C.edge,0.32)
  finish_corners(x,y,w,44,8,true,C.edge2,0.26+0.38*a)
  label(title,x+14,y+13,14,active and C.text or C.muted,1,w-28,23,0,true)
  right_label(code,x+w-12,y+6,7,active and C.accent2 or C.faint,3,true)
end

local function draw_scope_segment(x,y,w,title,active,hovered,left_side)
  local key=left_side and "scope_all" or "scope_track"
  local a=animate(key,active and 1 or (hovered and 0.28 or 0))
  rect(x,y,w,30,C.panel,0.96)
  gradient(x,y,w,30,C.accent3,C.panel,0.18*a,0)
  line(x,y+29,x+w,y+29,C.edge2,0.18+0.40*a)
  if active then rect(left_side and x or x+w-2,y,2,30,C.accent2,0.80) end
  label(title,x,y+3,12,active and C.text or C.muted,1,w,24,5,true)
end

local function draw_unit_segment(x,y,w,label_text,active,hovered)
  local a=animate("unit_"..label_text,active and 1 or (hovered and 0.30 or 0))
  rect(x,y,w,32,C.panel,0.98)
  gradient(x,y,w,32,C.accent3,C.panel,0.22*a,0)
  line(x,y+31,x+w,y+31,C.edge2,0.22+0.55*a)
  if active then glow_line(x+10,y+31,x+w-10,y+31,C.accent2,0.28) end
  label(label_text,x,y+4,11,active and C.text or C.muted,3,w,24,5,true)
end

function UI.toggle(x,y,label_text,on,label_w)
  -- LOOP_RM_STUDIO slide-toggle design, fitted to INTERVAL's two-column row.
  local state=animate("toggle_state_"..label_text,on and 1 or 0)
  line(x+3,y+12,x+23,y+12,C.edge2,.45)
  local knob_x=x+7+12*state
  disc(knob_x,y+12,4.2,C.faint,.8)
  if state>.001 then
    disc(knob_x,y+12,7,C.accent,.06*state)
    disc(knob_x,y+12,4.2,C.accent2,.94*state)
  end
  label(label_text,x+34,y,11.5,C.text,1,label_w or 150,24,4,true)
end

local Chrome={window=nil,mouseDown=false,drag=nil,resize=nil,mouseActive=false,requestClose=false,requestReset=false,
  chameleonPressed=false,resizeCursors={},resizeCursorMode=nil,titleH=Layout.bar.height,windowTitle=App.windowTitle,titleText=App.chromeTitle,
  minW=Layout.minWidth,minH=Layout.minHeight,mint={0.38,0.88,0.72},ice={0.65,0.895,1.0},red={1.0,0.27,0.34},
  isWindows=R.GetOS():match("Win")~=nil,resizeEdge=6,resizeCornerBand=8,resizeCornerSpan=24,resizeTopLeftGuard=30,resizeTopRightGuard=110,
  tooltipHover=nil,tooltipSince=0,tooltipVisible=false,tooltipDelay=.70,
  cursorId={we=32644,ns=32645,nwse=32642,nesw=32643,arrow=32512}}
Chrome.font=fonts[4]

local CHROME_DEFAULT={
  mint={Chrome.mint[1],Chrome.mint[2],Chrome.mint[3]},
  ice={Chrome.ice[1],Chrome.ice[2],Chrome.ice[3]},
}
-- ============================================================================
-- CHAMELEON THEME ADAPTER
--
-- Porting contract for other BLT scripts:
--   Required palette tables : C, C_DEFAULT
--   Optional chrome colors   : Chrome, CHROME_DEFAULT
--   Persistence              : SECTION / ExtState key "chameleon"
--   Host hooks               : notice(), wake_visuals(), redraw_dirty
--   UI integration           : Chameleon.enabled / Chameleon.set(...)
--   Main-loop integration    : Chameleon.tick(now)
--
-- Keep this block intact when porting; normally only the title-bar button
-- placement and the host hooks need adapting in another BLT script.
-- ============================================================================
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

function Chameleon.restore()
  for k,v in pairs(C_DEFAULT) do C[k]=ccopy(v) end
  Chrome.mint=ccopy(CHROME_DEFAULT.mint)
  Chrome.ice=ccopy(CHROME_DEFAULT.ice)
end

function Chameleon.apply(palette)
  for k,v in pairs(palette) do C[k]=v end
  Chrome.mint=ccopy(C.accent2)
  Chrome.ice=ccopy(C.focus2)
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
  State.set("chameleon",Chameleon.enabled and "1" or "0",true)
  Chameleon.signature=nil

  if Chameleon.enabled then
    Chameleon.refresh(true)
    notice("CHAMELEON  REAPERテーマに擬態",true)
  else
    Chameleon.restore()
    redraw_dirty=true
    notice("CHAMELEON  オリジナル配色",true)
  end
  wake_visuals(R.time_precise())
end

function Chameleon.tick(now)
  if not Chameleon.enabled or now<Chameleon.poll_at then return false end
  Chameleon.poll_at=now+Chameleon.poll_interval
  return Chameleon.refresh(false)
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

function Chameleon.icon_colors()
  local cache=Chameleon.iconCache
  if cache and cache.enabled==Chameleon.enabled and cache.r==C.accent[1] and cache.g==C.accent[2] and cache.b==C.accent[3] then return cache[1],cache[2],cache[3] end
  if not Chameleon.enabled then
    cache={{0.59,0.66,0.64},{0.48,0.53,0.58},{0.56,0.63,0.63},enabled=false,r=C.accent[1],g=C.accent[2],b=C.accent[3]}
    Chameleon.iconCache=cache;return cache[1],cache[2],cache[3]
  end

  local h,s,v=rgb_to_hsv(C.accent)
  -- Only the icon gets a saturation floor; the actual BLT theme does not.
  s=math.max(s,.46)

  -- Preserve the theme's base hue, but fan the other two colors away from it.
  -- +/- 0.19 ~= 68 degrees: clearly different without turning into a rainbow badge.
  local c1=hsv_to_rgb(h,      s,                v)
  local c2=hsv_to_rgb(h+.19, math.max(.42,s*.90), v)
  local c3=hsv_to_rgb(h-.19, math.max(.42,s*.86), v)

  Chameleon.iconCache={c1,c2,c3,enabled=true,r=C.accent[1],g=C.accent[2],b=C.accent[3]}
  return c1,c2,c3
end

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
  local ok,l,t=R.JS_Window_GetRect(hwnd)
  if not R.JS_Window_SetStyle(hwnd,"POPUP") then return false end
  local after,x,y,r,b=R.JS_Window_GetRect(hwnd)
  if ok and (not after or x~=l or y~=t or r-x~=target_w or b-y~=target_h) then
    if not R.JS_Window_SetPosition(hwnd,l,t,target_w,target_h,"","") then return false end
  end
  return true
end

local function reset_window_size()
  local hwnd=gfx_window_handle()
  if not hwnd then return end
  local ok,l,t,r,b=R.JS_Window_GetRect(hwnd)
  if not ok then return end
  if r-l~=W or b-t~=H+Chrome.titleH then
    if not R.JS_Window_SetPosition(hwnd,l,t,W,H+Chrome.titleH,"","") then return end
    Chrome.geometryDirty=true
  end
  State.set("window_w",tostring(W),true)
  State.set("window_h",tostring(H+Chrome.titleH),true)
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
    if mx<Chrome.resizeTopLeftGuard or mx>=w-(Layout.bar.close+Layout.bar.reset+Layout.bar.theme+Layout.bar.language+Layout.bar.preset+2*Layout.bar.arrow) then return nil end
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
  local ok,l,t,r,b=R.JS_Window_GetRect(hwnd)
  if not ok then return false end
  local sx,sy=R.GetMousePosition()
  Chrome.resize={mode=mode,mouseX=sx,mouseY=sy,left=l,top=t,right=r,bottom=b,lastX=l,lastY=t,lastW=r-l,lastH=b-t}
  Chrome.drag=nil
  return true
end

local function update_window_resize()
  local d=Chrome.resize
  if not d then return end
  local hwnd=gfx_window_handle()
  if not hwnd then Chrome.resize=nil; return end
  local sx,sy=R.GetMousePosition()
  local dx,dy=sx-d.mouseX,sy-d.mouseY
  local l,t,r,b=d.left,d.top,d.right,d.bottom
  if d.mode:find("l",1,true) then l=math.min(d.left+dx,r-Chrome.minW) end
  if d.mode:find("r",1,true) then r=math.max(d.right+dx,l+Chrome.minW) end
  if d.mode:find("t",1,true) then t=math.min(d.top+dy,b-Chrome.minH) end
  if d.mode:find("b",1,true) then b=math.max(d.bottom+dy,t+Chrome.minH) end
  local width,height=math.max(Chrome.minW,math.floor(r-l+.5)),math.max(Chrome.minH,math.floor(b-t+.5))
  l,t=math.floor(l+.5),math.floor(t+.5)
  if d.lastX==l and d.lastY==t and d.lastW==width and d.lastH==height then return end
  if R.JS_Window_SetPosition(hwnd,l,t,width,height,"","") then
    d.lastX,d.lastY,d.lastW,d.lastH=l,t,width,height;Chrome.geometryDirty=true
  end
end

-- Shared app-bar geometry: drawing, tooltips and hit testing use one source.
function UI.bar(width)
  if UI.barCache and UI.barCache.width==width then return UI.barCache end
  local b=Layout.bar;local closeX=width-b.close;local resetX=closeX-b.reset;local themeX=resetX-b.theme
  local languageX=themeX-b.language;local nextX=languageX-b.arrow;local prevX=nextX-b.arrow;local presetX=prevX-b.preset
  UI.barCache={width=width,closeX=closeX,resetX=resetX,themeX=themeX,languageX=languageX,nextX=nextX,prevX=prevX,presetX=presetX}
  return UI.barCache
end

local CHROME_TOOLTIPS={
  language="表示言語を切替（JP / EN）",
  preset="プリセット（読込・保存・インポート／エクスポート）",
  presetPrev="前のプリセット",
  presetNext="次のプリセット",
  close="閉じる",
  reset="ウィンドウサイズ初期化",
  chameleon="カメレオンモード（配色をテーマへ擬態）",
}

local function chrome_tooltip_hit(mx,my)
  local w=gfx.w
  if Footer.clipped and Footer.x and mx>=Footer.x and mx<Footer.x+Footer.w and my>=Footer.y and my<Footer.y+Footer.h then return "footer" end
  if mx<0 or mx>=w or my<0 or my>=Chrome.titleH then return nil end
  local b=UI.bar(w)
  local closeW,resetW,chamW=Layout.bar.close,Layout.bar.reset,Layout.bar.theme
  local closeX,resetX,chamX=b.closeX,b.resetX,b.themeX
  if mx>=closeX then return "close" end
  if mx>=resetX then return "reset" end
  if mx>=chamX then return "chameleon" end
  if mx>=b.languageX then return "language" end
  if mx>=b.nextX then return "presetNext" end
  if mx>=b.prevX then return "presetPrev" end
  if mx>=b.presetX then return "preset" end
  return nil
end

local function clear_chrome_tooltip()
  if Chrome.tooltipVisible and type(R.TrackCtl_SetToolTip)=="function" then
    pcall(R.TrackCtl_SetToolTip,"",0,0,true)
  end
  Chrome.tooltipVisible=false
end

local function show_chrome_tooltip(id)
  local tip=id=="footer" and Footer.message or (id and CHROME_TOOLTIPS[id] or nil)
  if tip then tip=Language.message(tip) end
  if not tip or type(R.TrackCtl_SetToolTip)~="function" then return false end

  local w=gfx.w
  local b=UI.bar(w)
  local closeW,resetW,chamW=Layout.bar.close,Layout.bar.reset,Layout.bar.theme
  local anchorX
  if id=="footer" then
    anchorX=Footer.x
  elseif id=="preset" then
    anchorX=b.presetX+Layout.bar.preset*.5
  elseif id=="presetPrev" then
    anchorX=b.prevX+Layout.bar.arrow*.5
  elseif id=="presetNext" then
    anchorX=b.nextX+Layout.bar.arrow*.5
  elseif id=="language" then
    anchorX=b.languageX+Layout.bar.language*.5
  elseif id=="close" then
    anchorX=w-closeW*.5
  elseif id=="reset" then
    anchorX=w-closeW-resetW*.5
  elseif id=="chameleon" then
    anchorX=w-closeW-resetW-chamW*.5
  else
    return false
  end

  -- Convert the button position to screen coordinates so the native tooltip
  -- is not clipped by the gfx window bounds.
  local ok,sx,sy=pcall(gfx.clienttoscreen,math.floor(anchorX+0.5),id=="footer" and Footer.y-8 or Chrome.titleH+8)
  if not ok or type(sx)~="number" or type(sy)~="number" then return false end

  local shown=pcall(R.TrackCtl_SetToolTip,tip,math.floor(sx+0.5),math.floor(sy+0.5),true)
  if shown then
    Chrome.tooltipVisible=true
    return true
  end
  return false
end

-- BLT COMMON PRESET UI: data actions are supplied by the Presets adapter.
-- Modal popup in client coordinates (never scales with content).
function Presets.menu(x,y)
  Presets.open=true;Presets.page="main";Presets.offset=0;Presets.selected=1
  Presets.down=false;Presets.pressed=nil;Presets.mx=nil;Presets.my=nil;Presets.hoverSince=nil
  focused=false;pressed=nil;last_down=false;wake_visuals()
end
function Presets.dismiss()
  Presets.swallow=((gfx.mouse_cap or 0)&1)~=0
  Presets.open=false;Presets.hoverSince=nil;Presets.pressed=nil;focused=false;pressed=nil;last_down=false;wake_visuals()
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
  local key=font_cache_key or "chrome"
  local bucket=fit_cache[key];local cached=bucket and bucket[text]
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
  if fit_cache_count>=512 then fit_cache={};fit_cache_count=0;bucket=nil end
  if not bucket then bucket={};fit_cache[key]=bucket end
  if not bucket[text] then fit_cache_count=fit_cache_count+1 end
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
    gfx.drawstr(Language.message(string.format("%d–%d / %d   スクロールで選択",Presets.offset+1,math.min(Presets.offset+Layout.popup.visiblePresets,#Presets.items),#Presets.items)))
  end
end

-- BLT COMMON PRESENTERS. App-specific drawing enters through the icon callback.
function UI.title(window_active,particle_dt)
  local t=Layout.title
  label(App.title,t.x,t.y,t.size,C.text,2,300,42,0,true)
  label(App.subtitle,t.subtitleX,t.subtitleY,t.subtitleSize,C.accent2,1,320,16,0,false)
  local saved_scale,saved_ox,saved_oy=scale,ox,oy
  ox,oy=ox+t.iconX*scale,oy+t.iconY*scale;scale=scale*t.iconScale
  UI.titleIcon(window_active,particle_dt)
  scale,ox,oy=saved_scale,saved_ox,saved_oy
end
function UI.titleIcon(active,dt) hud_icon(0,0,mode,active,dt) end
function UI.footer(message,c)
  message=Language.message(message)
  local f=Layout.footer;local version="v"..App.version
  local y=H-f.bottom
  local width=W-f.inset*2-measure(version,f.versionSize,3,true)-f.versionGap
  font(f.size,1,false)
  local shown=UI.fit(message,width*scale)
  Footer.message=message;Footer.clipped=shown~=message
  Footer.x,Footer.y,Footer.w,Footer.h=sx(f.inset),sy(y),width*scale,f.height*scale
  label(shown,f.inset,y,f.size,c,1,width,f.height,0,false)
  right_label(version,W-f.inset,y,f.versionSize,C.faint,3,true)
end

function Language.toggle()
 Language.set(Language.code=='JP' and 'EN' or 'JP')
 clear_chrome_tooltip();Chrome.tooltipId=nil
 wake_visuals();redraw_dirty=true;next_draw_time=0
end
local function custom_titlebar(blocked)
  local w=gfx.w
  local mx,my=gfx.mouse_x,gfx.mouse_y
  local b=UI.bar(w)
  local closeW,resetW,chamW=Layout.bar.close,Layout.bar.reset,Layout.bar.theme
  local closeX,resetX,chamX=b.closeX,b.resetX,b.themeX
  local languageX=b.languageX
  local presetX=b.presetX
  local prevX,nextX=b.prevX,b.nextX
  local inWindow=mx>=0 and mx<w and my>=0 and my<gfx.h
  local inBar=not blocked and inWindow and my<Chrome.titleH
  local resizeMode=not blocked and chrome_resize_hit(mx,my) or nil
  local resizing=Chrome.resize~=nil
  local cursorMode=resizing and Chrome.resize.mode or resizeMode
  set_resize_cursor(cursorMode)
  local hoverClose=inBar and mx>=closeX and mx<w and not resizeMode and not resizing
  local hoverReset=inBar and mx>=resetX and mx<closeX and not resizeMode and not resizing
  local hoverCham=inBar and mx>=chamX and mx<resetX and not resizeMode and not resizing
  local hoverPreset=inBar and mx>=presetX and mx<prevX and not resizeMode and not resizing
  local hoverPrev=inBar and mx>=prevX and mx<nextX and not resizeMode and not resizing
  local hoverNext=inBar and mx>=nextX and mx<languageX and not resizeMode and not resizing
  local hoverLanguage=inBar and mx>=languageX and mx<chamX and not resizeMode and not resizing
  local down=not blocked and (gfx.mouse_cap&1)~=0
  Chrome.mouseActive=blocked or inBar or Chrome.drag~=nil or Chrome.resize~=nil or cursorMode~=nil
    or Chrome.languagePressed or Chrome.closePressed or Chrome.resetPressed or Chrome.chameleonPressed or Chrome.presetPressed or Chrome.presetPrevPressed or Chrome.presetNextPressed

  gfx.set(C.bg[1],C.bg[2],C.bg[3],1); gfx.rect(0,0,w,Chrome.titleH,1)
  gfx.gradrect(0,0,w,Chrome.titleH,C.field[1],C.field[2],C.field[3],.72,
    0,0,0,0,(C.bg[1]-C.field[1])/Chrome.titleH,(C.bg[2]-C.field[2])/Chrome.titleH,(C.bg[3]-C.field[3])/Chrome.titleH,.22/Chrome.titleH)
  gfx.set(C.edge[1],C.edge[2],C.edge[3],.42); gfx.line(0,Chrome.titleH-1,w,Chrome.titleH-1,1)

  if not Chrome.textFontsReady or Chrome.fontDPI~=(gfx.ext_retina or 1) then Chrome.fontDPI=gfx.ext_retina or 1;gfx.setfont(7,Chrome.font,10,0); Chrome.textFontsReady=true else gfx.setfont(7) end; font_cache_key="chrome"
  -- Center the unadorned title within the bar using the actual font height.
  local _,titleHeight=UI.textMetrics(Chrome.titleText)
  local ty=math.floor((Chrome.titleH-titleHeight)*.5)
  gfx.set(Chrome.mint[1],Chrome.mint[2],Chrome.mint[3],.88); gfx.x=14; gfx.y=ty; gfx.drawstr(UI.fit(Chrome.titleText,math.max(0,presetX-22)))

  -- One frame groups the preset menu and previous/next controls.
  if hoverPreset or Presets.open then
    gfx.set(C.accent[1],C.accent[2],C.accent[3],.10);gfx.rect(presetX+2,3,78,20,1)
  end
  gfx.set(C.edge[1],C.edge[2],C.edge[3],(hoverPreset or hoverPrev or hoverNext) and .9 or .5)
  gfx.roundrect(presetX+2,3,languageX-presetX-5,20,3,1)
  gfx.set(C.muted[1],C.muted[2],C.muted[3],.35);gfx.line(languageX-1,6,languageX-1,20)
  local pc=hoverPreset and Chrome.mint or C.muted
  gfx.set(pc[1],pc[2],pc[3],hoverPreset and .98 or .8)
  gfx.roundrect(presetX+10,7,7,8,1,1);gfx.roundrect(presetX+13,10,7,8,1,1)
  gfx.setfont(7);font_cache_key="chrome"
  gfx.x=presetX+26;gfx.y=7;gfx.drawstr("PRESET")
  gfx.line(presetX+67,11,presetX+70,14);gfx.line(presetX+70,14,presetX+73,11)
  if Presets.dirty() then gfx.set(C.warn[1],C.warn[2],C.warn[3],.9);gfx.circle(presetX+23,6,1.3,1,1) end

  -- Separate previous/next hit targets inside the shared preset frame.
  for _,arrow in ipairs({{prevX,hoverPrev,-1},{nextX,hoverNext,1}}) do
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

  -- JP / EN indicates the current language, independent of preset state.
  local lc=hoverLanguage and Chrome.mint or C.text
  gfx.set(lc[1],lc[2],lc[3],hoverLanguage and 1 or .95)
  -- A borderless 26 x 26 icon; use the existing cached bold font path.
  font(13/scale,2,true)
  local lw,lh=UI.textMetrics(Language.code)
  gfx.x=languageX+(Layout.bar.language-lw)/2;gfx.y=(Chrome.titleH-lh)/2
  gfx.drawstr(Language.code)

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

  if hoverReset then
    gfx.set(Chrome.mint[1],Chrome.mint[2],Chrome.mint[3],.050); gfx.rect(resetX,0,resetW,Chrome.titleH,1)
    gfx.set(Chrome.mint[1],Chrome.mint[2],Chrome.mint[3],.34); gfx.line(resetX,Chrome.titleH-1,closeX,Chrome.titleH-1,1)
  end
  local rcx,rcy=resetX+resetW*.5,Chrome.titleH*.5
  local rcol=hoverReset and Chrome.mint or C.muted

  -- Reference-style outlined window; arrow explicitly points LOWER LEFT.
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
        local ok,l,t,r,b=R.JS_Window_GetRect(hwnd)
        if ok then
          local sx,sy=R.GetMousePosition()
          Chrome.drag={mouseX=sx,mouseY=sy,left=l,top=t,width=r-l,height=b-t,lastX=l,lastY=t}
        end
      end
    end
  end

  if down and Chrome.resize then update_window_resize() end
  if down and Chrome.drag and not Chrome.resize then
    local d=Chrome.drag;local sx,sy=R.GetMousePosition()
    local x,y=d.left+(sx-d.mouseX),d.top+(sy-d.mouseY)
    local hwnd=(x~=d.lastX or y~=d.lastY) and gfx_window_handle() or nil
    if hwnd and R.JS_Window_SetPosition(hwnd,x,y,d.width,d.height,"","") then
      d.lastX,d.lastY=x,y;Chrome.geometryDirty=true
    end
  end

  if not down and Chrome.mouseDown then
    if Chrome.closePressed and hoverClose then Chrome.requestClose=true end
    if Chrome.resetPressed and hoverReset then Chrome.requestReset=true end
    if Chrome.languagePressed and hoverLanguage then Language.toggle() end
    Chrome.languagePressed=false
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

-- Cache selected-item metadata and the alignment plan. Rebuild only when
-- the project state changes or a UI setting that affects the plan changes.
local ui_cache = {project=nil, state_count=nil, settings_dirty=true, items=nil, plan=nil, reason=nil}
local function get_cached_ui_state(project,state_count)
  state_count=state_count or R.GetProjectStateChangeCount(project)
  local project_changed=ui_cache.project~=project
  local items_dirty=project_changed or ui_cache.state_count~=state_count or ui_cache.items==nil
  if items_dirty then
    ui_cache.project=project
    ui_cache.state_count=state_count
    ui_cache.items=Core.collect(project)
    ui_cache.settings_dirty=true
  end

  if ui_cache.settings_dirty or ui_cache.value~=value or ui_cache.mode~=mode or ui_cache.unit~=unit or ui_cache.scope~=scope then
    local interval=Core.parse(value,unit)
    ui_cache.plan,ui_cache.reason=Core.plan(project,ui_cache.items,interval,mode,unit,scope)
    ui_cache.value,ui_cache.mode,ui_cache.unit,ui_cache.scope=value,mode,unit,scope
    ui_cache.settings_dirty=false
  end
  return ui_cache.items,ui_cache.plan,ui_cache.reason
end

PrimaryButton.painter={C=C,gradient=gradient,line=line,rect=rect,corners=finish_corners,disc=disc,label=label}
PrimaryButton.painter.motion=function(now) return (gfx.mouse_x-ox)/scale,(gfx.mouse_y-oy)/scale,visual_speed(now) end
PrimaryButton.wake=function() redraw_dirty=true end
-- INTERVAL CONTENT: host-specific widgets; shared title/footer/chrome are delegated.
local function draw(window_active)
  local popup_blocked=Presets.open or Presets.swallow
  Presets.update(window_active)
  local contentH=math.max(1,gfx.h-Chrome.titleH)
  scale=math.max(0.2,math.min(gfx.w/W,contentH/H))
  ox,oy=(gfx.w-W*scale)/2,Chrome.titleH+(contentH-H*scale)/2
  UI.fontViewport(scale,gfx.ext_retina or 1)
  gfx.clear=-1
  gfx.set(3/255,8/255,14/255,1);gfx.rect(0,0,gfx.w,gfx.h,1)
  local now=R.time_precise()
  local real_dt=math.max(0,math.min(0.1,now-frame_clock)); frame_clock=now
  frame_dt=(window_active and animations_active) and real_dt*animation_speed or 0
  animation_blend=1-math.exp(-12*frame_dt)
  local particle_dt=real_dt
  anim_time=anim_time+frame_dt
  draw_background()
  custom_titlebar(popup_blocked or Presets.open)

  local project=UI.project or R.EnumProjects(-1,"")
  local project_state=UI.projectState or R.GetProjectStateChangeCount(project)
  local items,plan,reason=get_cached_ui_state(project,project_state)
  local enabled=plan~=nil
  local content_active=window_active and not Chrome.mouseActive
  local down=content_active and ((gfx.mouse_cap & 1)~=0) or false
  local hit=nil

  if content_active then
    if inside(table.unpack(Layout.controls.gap)) then hit="gap" end
    if inside(table.unpack(Layout.controls.start)) then hit="start" end
    if inside(table.unpack(Layout.controls.scope_all)) then hit="scope_all" end
    if inside(table.unpack(Layout.controls.scope_track)) then hit="scope_track" end
    if inside(table.unpack(Layout.controls.input)) then hit="input" end
    if inside(table.unpack(Layout.controls.unit_sec)) then hit="unit_sec" end
    if inside(table.unpack(Layout.controls.unit_grid)) then hit="unit_grid" end
    if inside(table.unpack(Layout.controls.close_after)) then hit="close_after" end
    if inside(table.unpack(Layout.controls.remember_mode)) then hit="remember_mode" end
    if inside(table.unpack(Layout.controls.apply)) then hit="apply" end

    local wheel=gfx.mouse_wheel or 0
    if wheel~=0 then
      local shift_down=(gfx.mouse_cap & 8)~=0
      if hit=="input" then adjust_value_by_wheel(wheel,shift_down) end
      gfx.mouse_wheel=0
    end
  else
    pressed=nil
    field_drag=nil
    last_down=false
  end

  if down and not last_down then
    pressed=hit
    if hit=="input" then
      focused=true;selected=true;caret=#value
      local current=Core.parse(value,unit) or 0
      field_drag={start_y=(gfx.mouse_y-oy)/scale,start_value=current,moved=false,clipped=false}
    else
      if focused then set_interval_number(value,true) end
      focused=false;selected=false
    end
  elseif down and field_drag then
    update_value_drag((gfx.mouse_y-oy)/scale,(gfx.mouse_cap&8)~=0)
  elseif not down and last_down then
    local was_drag=field_drag and field_drag.moved
    field_drag=nil
    if not was_drag and hit and hit==pressed then
      if hit=="apply" and enabled then execute()
      elseif hit=="start" or hit=="gap" then
        mode=hit; status_until=0
        if remember_mode then State.set("last_mode",mode,true) end
        persist_process_settings()
      elseif hit=="scope_all" or hit=="scope_track" then
        scope=hit=="scope_all" and "all" or "track";status_until=0
        if remember_mode then State.set("last_scope",scope,true) end
        persist_process_settings()
      elseif hit=="unit_sec" then select_unit("sec")
      elseif hit=="unit_grid" then select_unit("grid")
      elseif hit=="close_after" then
        close_after=not close_after
        State.set("close_after",close_after and "1" or "0",true)
        status_until=0
      elseif hit=="remember_mode" then
        remember_mode=not remember_mode
        State.set("remember_mode",remember_mode and "1" or "0",true)
        if remember_mode then
          State.set("last_mode",mode,true)
          State.set("last_unit",unit,true)
          State.set("last_scope",scope,true)
        end
        status_until=0
      end
    end
    pressed=nil
  end
  last_down=down
  if closing then return end

  items,plan,reason=get_cached_ui_state(project,project_state)
  enabled=plan~=nil

  UI.title(window_active,particle_dt)

  -- Selection summary: one clean glass strip.
  gradient(24,74,420,48,C.panel2,C.panel,0.42,0.12)
  finish_corners(24,74,420,48,8,false,C.edge2,0.26)
  label("SELECTED",38,82,8,C.muted,3,70,14,0,true)
  label(tostring(#items),105,74,26,#items>=2 and C.text or C.warn,3,52,48,4,true)
  local anchor_text=scope=="track" and "EACH TRACK"
    or (#items>0 and string.format("%.3f s",items[1].position) or "--")
  right_label("ANCHOR",425,82,7,C.faint,3,true)
  right_label(anchor_text,425,96,11,C.muted,3,true)

  label("間隔モード",30,130,10,C.accent2,1,105,16,0,true)
  line(103,138,438,138,C.edge2,0.22)
  draw_mode_card("gap",30,150,198,"終了点 → 開始点","END / START",mode=="gap",hit=="gap")
  draw_mode_card("start",240,150,198,"開始点 → 開始点","START / START",mode=="start",hit=="start")

  draw_scope_segment(30,206,198,"全体",scope=="all",hit=="scope_all",true)
  draw_scope_segment(240,206,198,"トラック毎",scope=="track",hit=="scope_track",false)
  line(228,210,228,232,C.edge2,0.18)

  local focus_light=animate("input_focus",focused and 1 or (hit=="input" and 0.28 or 0))
  local field_flash=flash_value()
  label(mode=="gap" and "終了点 → 開始点の間隔" or "開始点 → 開始点の間隔",30,247,10,C.muted,1,260,16,0,true)
  gradient(30,266,408,82,C.field,C.panel,0.98,0.62)
  if field_flash>0 then rect(25,261,418,92,C.red,.025*field_flash); gradient(30,266,408,82,C.red,C.field,.22*field_flash,.02*field_flash,true) end
  line(30,266,438,266,field_flash>0 and C.red or C.edge2,0.22+0.38*focus_light+0.42*field_flash)
  line(30,348,438,348,C.edge2,0.34+0.42*focus_light)
  line(30,266,30,348,field_flash>0 and C.red or C.accent2,0.18+0.54*focus_light+0.40*field_flash)
  if focus_light>0.02 then
    glow_line(30,348,180,348,C.accent2,0.42*focus_light)
    local glint=((anim_time*0.34)%1)
    local gx=42+glint*360
    glow_line(gx,266,math.min(gx+30,430),266,C.focus2,0.25*focus_light)
  end
  finish_corners(30,266,408,82,10,false,field_flash>0 and C.red or C.accent2,0.30+0.36*focus_light+0.36*field_flash)

  local unit_caption=unit=="grid" and "GRID UNITS" or "SECONDS"
  local unit_suffix=unit=="grid" and "GRID" or "SEC"
  label(unit_caption,46,280,8,C.muted,3,100,12,0,true)
  local value_size=42
  local tw=measure(value,value_size,3,true)
  local suffix_size=15
  local suffix_w=measure(unit_suffix,suffix_size,3,true)
  local suffix_right=420
  local suffix_x=suffix_right-suffix_w
  local value_right=suffix_x-8
  local available=value_right-145
  while tw>available and value_size>13 do value_size=value_size-1; tw=measure(value,value_size,3,true) end
  local text_x=math.max(145,value_right-tw)
  local base_y=282
  local base_h=52
  label(unit_suffix,suffix_x,base_y-4,suffix_size,C.muted,3,suffix_w+2,base_h,8,true)
  if focused and selected then rect(text_x-4,295,math.max(7,tw+8),38,C.accent3,0.40) end
  label(value,text_x,base_y,value_size,C.text,3,math.max(1,value_right-text_x+3),base_h,8,true)
  if focused and not selected and R.time_precise()%1<0.55 then
    font(value_size,3,true)
    local cw=UI.textMetrics(value:sub(1,caret))/scale
    line(text_x+cw,294,text_x+cw,334,C.accent2,1)
  end

  draw_unit_segment(76,358,154,"SEC",unit=="sec",hit=="unit_sec")
  draw_unit_segment(238,358,154,"GRID",unit=="grid",hit=="unit_grid")

  -- Settings switches.
  UI.toggle(30,408,"整列後にウィンドウを閉じる",close_after,166)
  UI.toggle(238,408,"最後に使ったモードを記憶",remember_mode,164)

  -- Shared LOUDNESS TRACE style; selection validation and click behavior remain local.
  local ax,ay,aw,ah=table.unpack(Layout.controls.apply)
  PrimaryButton.draw(PrimaryButton.painter,ax,ay,aw,ah,'整列を実行','EXECUTE',enabled,false,nil,hit=='apply',pressed=='apply' and down,R.time_precise(),window_active)
  local message,mc="",C.muted
  if R.time_precise()<status_until then message=status or "";mc=status_ok and C.accent2 or C.warn
  elseif not enabled then message=reason or "アイテムを2つ以上選択してください。";mc=C.warn end
  UI.footer(message,mc)
  Presets.draw()

end

local last_window_position_check=0
local function update_window_position(force)
  local now=R.time_precise()
  if not force and (not Chrome.geometryDirty or now-last_window_position_check<0.20) then return end
  last_window_position_check=now;Chrome.geometryDirty=false
  local _,x,y,w,h=gfx.dock(-1,0,0,0,0)
  if type(x)=="number" and type(y)=="number"
    and x==x and y==y and x~=math.huge and y~=math.huge then
    last_window_x,last_window_y=x,y
  end
  if type(w)=="number" and type(h)=="number"
    and w==w and h==h and w~=math.huge and h~=math.huge and w>0 and h>0 then
    last_window_w,last_window_h=w,h
  end
end

local function window_is_active()
  local info=gfx.getchar(65536)
  -- REAPER 6+ status mask: focus bit 2, visible bit 4.
  return (info & 2)~=0 and (info & 4)~=0
end

local function persist_window_position()
  if last_window_x and last_window_y then
    State.set("window_x",tostring(math.floor(last_window_x+0.5)),true)
    State.set("window_y",tostring(math.floor(last_window_y+0.5)),true)
  end
  if last_window_w and last_window_h then
    State.set("window_w",tostring(math.floor(last_window_w+0.5)),true)
    State.set("window_h",tostring(math.floor(last_window_h+0.5)),true)
  end
end

local window_finalized=false
local function close_window()
  if window_finalized then return end
  window_finalized=true
  clear_chrome_tooltip()
  update_window_position(true)
  persist_window_position()
  titlebar_cleanup()
  gfx.quit()
end

if Chameleon.enabled then Chameleon.refresh(true) end
local chrome_ok,chrome_err=titlebar_api_ready()
if not chrome_ok then Language.mb(chrome_err,"Interval | エラー",0); return end
gfx.ext_retina=1
local initial_w=(saved_window_w and saved_window_w==saved_window_w) and math.max(Layout.minWidth,math.min(Layout.maxWidth,saved_window_w)) or W
local initial_h=(saved_window_h and saved_window_h==saved_window_h) and math.max(Layout.minHeight,math.min(Layout.maxHeight,saved_window_h)) or (H+Chrome.titleH)
if saved_window_x and saved_window_y then
  gfx.init(Chrome.windowTitle,initial_w,initial_h,0,saved_window_x,saved_window_y)
else
  gfx.init(Chrome.windowTitle,initial_w,initial_h,0)
end
if not apply_custom_window_style(initial_w,initial_h) then gfx.quit(); Language.mb("カスタムタイトルバーを初期化できません。","Interval | エラー",0); return end
update_window_position(true)
R.atexit(close_window)

-- EVENT LOOP: input transitions wake drawing immediately; idle visuals coast to rest.
local function loop()
  local k=gfx.getchar()
  if k<0 then return end
  if k==27 then
    if Presets.open then Presets.dismiss();k=0 else close_window();return end
  end
  local now=R.time_precise()
  local active=window_is_active()
  if last_window_active==nil or active~=last_window_active then last_window_active=active; wake_visuals(now) end

  local key_activity=false; local count=0
  while k>0 and count<32 do
    key_activity=true
    if Presets.open then Presets.key(k) else keypress(k) end
    count=count+1;k=gfx.getchar()
    if k<0 then return end
    if k==27 then
      if Presets.open then Presets.dismiss();k=0 else close_window();return end
    end
  end
  if key_activity then wake_visuals(now) end
  if closing then close_window(); return end

  Chameleon.tick(now)

  if now-last_state_poll>=.35 then
    last_state_poll=now
    local project=R.EnumProjects(-1,""); local state=R.GetProjectStateChangeCount(project)
    UI.project,UI.projectState=project,state
    if last_seen_state~=state or last_seen_project~=project then
      last_seen_state,last_seen_project=state,project;redraw_dirty=true
    end
  end

  local dpi=gfx.ext_retina or 1
  if gfx.w~=last_view_w or gfx.h~=last_view_h or dpi~=last_view_dpi then
    last_view_w,last_view_h,last_view_dpi=gfx.w,gfx.h,dpi
    Chrome.geometryDirty=true;wake_visuals(now)
  end
  local raw_x,raw_y,raw_cap=gfx.mouse_x,gfx.mouse_y,gfx.mouse_cap
  local raw_wheel=gfx.mouse_wheel or 0

  -- Delayed native Chrome tooltips. Only transitions call the REAPER tooltip
  -- API; there is no extra gfx redraw or font work while hovering.
  local tooltip_hit=active and chrome_tooltip_hit(raw_x,raw_y) or nil
  if Presets.open or ((raw_cap or 0)&1)~=0 or Chrome.drag or Chrome.resize then tooltip_hit=nil end

  if tooltip_hit~=Chrome.tooltipHover then
    clear_chrome_tooltip()
    Chrome.tooltipHover=tooltip_hit
    Chrome.tooltipSince=now
  elseif tooltip_hit and not Chrome.tooltipVisible and now-Chrome.tooltipSince>=Chrome.tooltipDelay then
    show_chrome_tooltip(tooltip_hit)
  elseif not tooltip_hit and Chrome.tooltipVisible then
    clear_chrome_tooltip()
  end
  local cap_changed=raw_cap~=last_raw_mouse_cap
  local wheel_activity=raw_wheel~=0
  local pointer_activity=raw_x~=last_raw_mouse_x or raw_y~=last_raw_mouse_y or cap_changed or wheel_activity
  if pointer_activity then wake_visuals(now) end
  -- Button/wheel transitions are input events, not decoration. Render them on
  -- the current defer pass so short clicks cannot fall between capped frames.
  if cap_changed or wheel_activity then next_draw_time=now end
  last_raw_mouse_x,last_raw_mouse_y,last_raw_mouse_cap=raw_x,raw_y,raw_cap

  local dragging=field_drag~=nil or Chrome.drag~=nil or Chrome.resize~=nil or ((raw_cap or 0)&1)~=0
  if dragging then wake_visuals(now) end
  animation_speed=visual_speed(now)
  animations_active=active and animation_speed>0
  local particle_tail=#hud_particles>0
  PrimaryButton.tick(now,active,PrimaryButton.wake)
  local status_visible=status_until and now<status_until
  if last_status_visible~=status_visible then redraw_dirty=true;last_status_visible=status_visible end
  local caret_phase=focused and not selected and not Presets.open and (now%1<.55) or false
  if last_caret_phase~=caret_phase then redraw_dirty=true;last_caret_phase=caret_phase end
  if Presets.open and Presets.hoverSince and now>=Presets.hoverSince+Layout.popup.hoverDelay then redraw_dirty=true end
  local frame_interval
  if dragging then frame_interval=1/60
  elseif animations_active then frame_interval=1/(8+22*animation_speed)
  elseif particle_tail then frame_interval=1/20 end
  if frame_interval and next_draw_time==math.huge then next_draw_time=now end
  local frame_due=frame_interval and now>=next_draw_time or (not frame_interval and redraw_dirty)
  if frame_due then
    draw(active);gfx.update();next_display_update=now+.25;redraw_dirty=false
    next_draw_time=frame_interval and now+frame_interval or math.huge
    if Chrome.requestReset then Chrome.requestReset=false; reset_window_size(); wake_visuals(now) end
    if Chrome.requestClose then Chrome.requestClose=false; closing=true end
  end
  if now>=next_display_update then gfx.update();next_display_update=now+.25 end
  if pointer_activity or key_activity or dragging then redraw_dirty=true end
  if closing then close_window(); return end
  update_window_position(false)
  R.defer(loop)
end
loop()
