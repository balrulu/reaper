-- @description SIMPLE NORMALIZER
-- @version 0.5.2
-- @author Balrulu
-- @changelog
--   Unify Mac font and display scaling; fix floating TRACE collapse detection.
-- @about
--   BLT SERIES Beta TEST UPLOAD

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

-- Latest embedded application catalog.
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
 ["ゲート付きIntegrated Loudness。全体平均を基準にします。"]="Gated integrated loudness, based on the overall average.",
 ["有音・発話主体の区間だけを平均します。"]="Average only active, speech-dominant sections.",
 ["1秒窓の中央値。突出した一部に引っ張られにくい方式です。"]="Median of 1-second windows. Less affected by isolated loud sections.",
 ["1秒窓の中央60%だけをパワー平均。両端の外れ値を除外します。"]="Power average of the middle 60% of 1-second windows; excludes outliers at both ends.",
 ["1秒窓の80パーセンタイル。やや強い発話を基準にします。"]="80th percentile of 1-second windows; favors stronger speech.",
 ["1秒窓の95パーセンタイル。強い発話を重視します。"]="95th percentile of 1-second windows; emphasizes loud speech.",
 ["最も大きい1秒区間を基準にします。"]="Use the loudest 1-second section.",
 ["最も大きい400ms区間を基準にします。"]="Use the loudest 400 ms section.",
 ["Sample Peakを指定値へ一致させます。"]="Match sample peak to the target.",
 ["音声サンプルが不正です。"]="Invalid audio samples.",
 ["音声を取得できません"]="Cannot read audio",
 ["音声アイテムは1000件まで対応します。"]="Up to 1,000 audio items supported.",
 ["モノ／ステレオのみ対応"]="Mono/stereo only",
 ["再生速度1.0のみ対応"]="Playback rate 1.0 only",
 ["ミュート／音量0"]="Muted / zero volume",
 ["既存のTake Volumeカーブあり（対象外）"]="Existing take volume curve (skipped)",
 ["長さ0秒超〜30分に対応"]="Length must be >0 s and <=30 min",
 ["有効なTake FXあり（対象外）"]="Active take FX (skipped)",
 ["選択した音声の合計は2時間まで対応します。"]="Selected audio is limited to 2 hours total.",
 ["プロジェクトが切り替わりました。"]="Project switched.",
 ["音声アイテムの選択が変わりました。自動更新します。"]="Audio selection changed. Refreshing automatically.",
 ["対象アイテム自体が変更されています。"]="Target item was modified.",
 ["テイク設定が変更されています。自動更新します。"]="Take settings changed. Refreshing automatically.",
 ["音声アクセサーを作成できません。"]="Cannot create audio accessor.",
 ["取得できる音声範囲がアイテム長と一致しません。"]="Available audio range does not match item length.",
 ["音声解析用バッファを作成できません。"]="Cannot allocate audio analysis buffer.",
 ["ラウドネス解析器を作成できません。"]="Cannot create loudness analyzer.",
 ["解析中にアイテムが変更されました。"]="Item changed during analysis.",
 ["音声サンプルの取得に失敗しました。"]="Failed to read audio samples.",
 ["ピーク解析用バッファを作成できません。"]="Cannot allocate peak buffer.",
 ["Sample Peakを測定できません"]="Cannot measure sample peak",
 ["任意ファイルを基準にするため、そのファイルの解析完了を待っています。"]="Waiting for the reference file to finish analysis.",
 ["この方式で測定できません"]="Cannot measure with this method",
 ["適用する変更がありません。"]="No changes to apply.",
 ["アイテム音量を設定できません。"]="Cannot set item volume.",
 [" 元の音量へ戻せない項目があります。REAPERのUndoで確認してください。"]=" Some volumes could not be restored. Check REAPER Undo.",
 ["音声アイテムを選択すると自動解析します。"]="Select audio items for automatic analysis.",
 ["%s · %d件を処理できます。"]="%s · %d items ready.",
 ["%d件をバックグラウンド解析しています…"]="Analyzing %d items in the background...",
 ["ノーマライズする音声アイテムを選択してください。"]="Select audio items to normalize.",
 ["PEAK Fast Path：通常解析を停止し、未取得分のSample Peakだけを高速取得しています…"]="PEAK Fast Path: paused normal analysis; reading missing sample peaks...",
 ["プロジェクトが切り替わりました。自動更新します。"]="Project switched. Refreshing automatically.",
 ["選択が変わりました。自動更新します。"]="Selection changed. Refreshing automatically.",
 ["対象を固定して、残りを解析後そのままノーマライズします…"]="Targets locked. Finishing analysis, then normalizing...",
 ["件をノーマライズしました。選択を解除しました。"]=" items normalized and deselected.",
 ["PEAK高速実行をキャンセルしました。通常の自動解析へ戻ります。"]="PEAK fast run cancelled. Resuming automatic analysis.",
 ["ノーマライズ実行をキャンセルしました。自動解析は継続します。"]="Normalization cancelled. Automatic analysis continues.",
 ["CHAMELEON  REAPERテーマに擬態"]="CHAMELEON  REAPER theme",
 ["CHAMELEON  オリジナル配色"]="CHAMELEON  Original colors",
 ["カスタムタイトルバーには js_ReaScriptAPI が必要です。\nReaPack から js_ReaScriptAPI をインストールしてください。"]="The app bar requires js_ReaScriptAPI.\nInstall js_ReaScriptAPI via ReaPack.",
 ["数値を入力できなかったため、元の値へ戻しました。"]="Invalid input. Previous value restored.",
 ["クリック入力 ／ 上下ドラッグ：1刻み（Shift：0.1） ／ ホイール：0.1"]="Click: type / Drag vertically: 1 (Shift: 0.1) / Wheel: 0.1",
 ["選択アイテムの波形"]="SELECTED WAVEFORM",
 ["選択アイテムを自動解析しています"]="Analyzing selected items automatically",
 ["アイテム"]="Item",
 ["現在"]="Current",
 ["目標"]="Target",
 ["補正"]="Gain",
 ["Peak後"]="Peak after",
 ["状態"]="Status",
 ["指定基準"]="Reference",
 ["変更なし"]="Unchanged",
 ["解析中"]="Analyzing",
 ["解析待ち"]="Pending",
 ["任意ファイルモードでは、この行をReferenceとして使用します。"]="In reference-file mode, use this row as the reference.",
 ["表示 %d–%d / %d"]="Showing %d–%d / %d",
 ["SIMPLE NORMALIZER  シンプルなノーマライザー"]="SIMPLE NORMALIZER  Audio normalization",
 ["任意ファイル"]="Reference file",
 ["リストから指定"]="Select from list",
 ["数値指定"]="Numeric",
 ["指定した値へ揃えます。"]="Match the specified value.",
 ["右側のリストで選んだファイルを基準にします。"]="Use the file selected in the right-hand list as reference.",
 ["目標値"]="Target",
 ["右のリストでReferenceにするファイルを選択します。"]="Select the reference file in the right-hand list.",
 ["選択した方式の目標値です。"]="Target value for the selected method.",
 ["PEAK予測"]="PEAK FORECAST",
 ["対象  %d件"]="Targets %d",
 ["Peak取得  %d / %d"]="Peaks %d / %d",
 ["解析済み  %d / %d"]="Analyzed %d / %d",
 ["解析準備完了"]="Ready to analyze",
 ["実行をキャンセル"]="Cancel run",
 ["ノーマライズを実行"]="Normalize",
 ["クリックすると、予約中のノーマライズ実行をキャンセルします。自動解析は継続します。"]="Cancel the queued normalization. Automatic analysis continues.",
 ["解析途中でも実行できます。押した時点の対象を固定し、未解析分を完了してからItem Volumeへ適用します。"]="Run during analysis if needed. Lock current targets, finish remaining analysis, then apply item volume.",
 ["対象固定中 · 再クリックでキャンセル"]="Targets locked · Click again to cancel",
 ["バックグラウンド解析中"]="Background analysis",
 ["実行後は選択を解除"]="Deselect after run",
 ["Reference：リスト選択"]="Reference: list selection",
 ["目標値：数値指定"]="Target: numeric value",
 ["入力を取り消しました。"]="Input cancelled.",
 ["Simple Normalizer | エラー"]="Simple Normalizer | Error",
 ["カスタムタイトルバーを初期化できません。"]="Cannot initialize the app bar.",
 ["表示言語を切替（JP / EN）"]="Switch language (JP / EN)",
 ["プリセットを読み込みました: ファクトリーデフォルト"]="Loaded: Factory Default",
 ["選択中のトラック / バスを指定"]="Use selected track / bus",
},patterns={
 {"^「(.*)」を上書きしますか？$","Overwrite \"%s\"?"},
 {"^([%+%-]?[%d%.eE]+)–([%+%-]?[%d%.eE]+) / ([%+%-]?[%d%.eE]+)   スクロールで選択$","%d–%d / %d   Scroll to browse"},
 {"^解析中%.%.%.([%+%-]?[%d%.eE]+)%%$","Analyzing...%d%%"},
 {"^(.-) · ([%+%-]?[%d%.eE]+)件を処理できます。$","%s · %d items ready."},
 {"^([%+%-]?[%d%.eE]+)件をバックグラウンド解析しています…$","Analyzing %d items in the background..."},
 {"^表示 ([%+%-]?[%d%.eE]+)–([%+%-]?[%d%.eE]+) / ([%+%-]?[%d%.eE]+)$","Showing %d–%d / %d"},
 {"^対象  ([%+%-]?[%d%.eE]+)件$","Targets %d"},
 {"^Peak取得  ([%+%-]?[%d%.eE]+) / ([%+%-]?[%d%.eE]+)$","Peaks %d / %d"},
 {"^解析済み  ([%+%-]?[%d%.eE]+) / ([%+%-]?[%d%.eE]+)$","Analyzed %d / %d"},
 {"^「(.-)」を上書きしますか？$","\"%s\"?"},
 {"^(.-)」を上書きしますか？$","%s\"?"},
 {"^プリセットを保存しました: (.-)$","Saved: %s"},
 {"^プリセットを読み込みました: (.-)$","Loaded: %s"},
 {"^(.-)個インポートしました。$","%s preset(s) imported."},
 {"^現在: (.-)(.-)$","Current: %s%s"},
 {"^(.-) 元の音量へ戻せない項目があります。REAPERのUndoで確認してください。$","%s Some volumes could not be restored. Check REAPER Undo."},
 {"^(.-)件をノーマライズしました。選択を解除しました。$","%s items normalized and deselected."},
 {"^「(.*)」を上書きしますか？$","Overwrite \"%s\"?"},
 {"^(%d+)個インポートしました。$","Imported %s preset(s)."},
 {"^(%d+)件をノーマライズしました。選択を解除しました。$","Normalized %s items and deselected them."},
},prefixes={"プリセットを読み込みました: ","プリセットを保存しました: ","現在: "}}

LanguageCatalog.en["400msの最大LUFS-M。400ms未満は測定対象外です。"]="Maximum LUFS-M (400 ms). Shorter items are excluded."
LanguageCatalog.en["3秒の最大LUFS-S。3秒未満は測定対象外です。"]="Maximum LUFS-S (3 s). Shorter items are excluded."
LanguageCatalog.en["基準ファイルは選択方式で測定できません。尺と方式を確認してください。"]="Reference cannot use this method. Check its length or choose another method."
LanguageCatalog.en["LUFS-Mには0.4秒以上必要です"]="LUFS-M needs at least 0.4 s"
LanguageCatalog.en["LUFS-Sには3秒以上必要です"]="LUFS-S needs at least 3 s"

local Language=create_language(reaper,"BLT_SIMPLE_NORMALIZER",LanguageCatalog)
local R=reaper
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
 if type(data)~='string' or #data>1048576 then return nil end
 local at,nodes=1,0
 local function read(depth)
  nodes=nodes+1;assert(depth<14 and nodes<30000)
  local tag=data:sub(at,at);at=at+1
  if tag=='b' then local v=data:sub(at,at);at=at+1;assert(v=='0' or v=='1');return v=='1' end
  assert(tag=='s' or tag=='n' or tag=='t')
  local finish=data:find(':',at,true);assert(finish and finish-at<9)
  local raw=data:sub(at,finish-1);assert(raw:match('^%d+$'));local n=tonumber(raw);at=finish+1
  if tag=='t' then
   assert(n<=4096);local v={}
   for i=1,n do local k=read(depth+1);assert(type(k)=='string' or type(k)=='number');assert(v[k]==nil);v[k]=read(depth+1) end
   return v
  end
  assert(n<=65536 and at+n-1<=#data);local v=data:sub(at,at+n-1);at=at+n
  if tag=='n' then v=tonumber(v);assert(v and v==v and math.abs(v)<math.huge) end
  return v
 end
 local ok,v=pcall(read,0);if ok and at==#data+1 then return v end
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
 local rows={};for _,p in ipairs(items) do rows[#rows+1]=Presets.encode(p) end
 return host.section..'_PRESET_BUNDLE_V1\n'..B.pack(rows)
end
function Presets.decodeTransfer(data)
 if type(data)~='string' or #data>1048576 then return nil end
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
 local data=f:read(1048577);f:close();local items=Presets.decodeTransfer(data)
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
-- Non-modal dependency hint. Uses the existing tick, with no extra defer loop.
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

  -- Reference-style outlined window; arrow explicitly points LOWER LEFT.
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
 for _,key in ipairs({'drag','number_drag','pointer_capture','field_drag','fieldDrag','curve_drag','scroll_drag','seam_drag','seam_hold','pressed','popup','name_dialog','duplicate_modal'}) do state[key]=nil end
 if host.cancelEdit then B.cleanup(host.cancelEdit) end
 Presets.open=false;Presets.swallow=false
 B.recoveryMode=true
 local ok,why=pcall(B.bar)
 B.recoveryMode=nil
 if not ok then B.logError(why) end
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
function B.chaosButton(cx,cy,cw,ch,enabled,hot,pushed,time,glow)
 local d=host.chaosPainter
 local violet=Chameleon.enabled and C.accent2 or B.chaosViolet
 local ember=Chameleon.enabled and C.accent or B.chaosEmber
 local pale=Chameleon.enabled and C.text or B.chaosPale
 local surface=Chameleon.enabled and C.field or B.chaosSurface
 local alive=enabled and 1 or .25
 local breath=(.5+.5*math.sin(time*.85))*alive
 local y=cy+(pushed and 1 or 0);local center=ch/2
 -- Keep both the outer glow and the pressed face inside the registered bounds.
 d.cut(cx,cy,cw,ch,11,violet,.025*alive,violet,.10+.07*breath)
 d.cut(cx,y+2,cw,ch-4,9,surface,1,violet,(.45+.3*glow)*alive)
 d.gradient(cx+2,y+4,cw-4,ch-8,violet,C.bg,.12+.15*glow,.015,true)
 for i=1,6 do
  local phase=time*.3+i*1.7;local px=cx+12+(i-1)*(cw-29)/5
  local py=y+center+math.sin(phase)*(center-6)
  local alpha=(.18+.22*math.sin(phase*.7)^2)*alive
  if px<cx+36 or px>cx+cw-36 or math.abs(py-y-center)>11 then
   d.disc(px,py,3,violet,alpha*.08);d.disc(px,py,.7,i%2==0 and ember or pale,alpha)
  end
 end
 d.line(cx+cw*.335,y+ch-5,cx+cw*.665,y+ch-5,violet,(.18+.22*breath+.2*glow)*alive)
 d.label('C H A O S',cx+24,y+center-9,17,enabled and pale or C.faint,2,cw-48,22,1,true)
end
B.chaosViolet={.62,.23,.94};B.chaosEmber={.92,.27,.65};B.chaosPale={.87,.69,1};B.chaosSurface={.038,.014,.068}

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

local min,max,abs,floor,sqrt=math.min,math.max,math.abs,math.floor,math.sqrt
local function clamp(x,a,b) return max(a,min(b,x)) end
local function finite(x) return type(x)=="number" and x==x and abs(x)<math.huge end
local function dbp(x) return 10*math.log(max(x,1e-15),10) end
local function dba(x) return 20*math.log(max(abs(x),1e-15),10) end
local function amp(db) return 10^(db/20) end
local function quantile(values,q)
  if #values==0 then return nil end
  local a={}; for i,v in ipairs(values) do a[i]=v end; table.sort(a)
  return a[clamp(floor((#a-1)*q+1.5),1,#a)]
end
local function mean_power(blocks,gate)
  local sum,n=0,0
  for _,b in ipairs(blocks) do
    if not gate or b.level>=gate then sum=sum+b.power; n=n+1 end
  end
  return n>0 and sum/n or nil,n
end

local Core={SR=48000,HOP=960,DT=.02,READ_BLOCK=16384,PEAK_READ_BLOCK=131072,MAX_ITEMS=1000,MAX_SECONDS=7200,MAX_GAIN=60,WAVEFORM_BINS=1024}
Core.modes={
  {key="integrated",name="LUFS-I",code="I",unit="LUFS",default=-24,desc="ゲート付きIntegrated Loudness。全体平均を基準にします。"},
  {key="speech",name="SPEECH",code="VOICE",unit="LUFS",default=-24,desc="有音・発話主体の区間だけを平均します。"},
  {key="median",name="MEDIAN",code="P50",unit="LUFS",default=-24,desc="1秒窓の中央値。突出した一部に引っ張られにくい方式です。"},
  {key="robust",name="ROBUST",code="TRIM",unit="LUFS",default=-24,desc="1秒窓の中央60%だけをパワー平均。両端の外れ値を除外します。"},
  {key="p80",name="P80",code="P80",unit="LUFS",default=-20,desc="1秒窓の80パーセンタイル。やや強い発話を基準にします。"},
  {key="p95",name="P95",code="P95",unit="LUFS",default=-18,desc="1秒窓の95パーセンタイル。強い発話を重視します。"},
  {key="max1s",name="MAX 1s",code="MAX-ST",unit="LUFS",default=-18,desc="最も大きい1秒区間を基準にします。"},
  {key="max400",name="LUFS-M",code="M MAX",unit="LUFS",default=-16,desc="400msの最大LUFS-M。400ms未満は測定対象外です。"},
  {key="peak",name="PEAK",code="SP",unit="dBFS",default=-1,desc="Sample Peakを指定値へ一致させます。"},
  {key="shortterm",name="LUFS-S",code="S MAX",unit="LUFS",default=-18,desc="3秒の最大LUFS-S。3秒未満は測定対象外です。"},
}

-- Display order is independent of persisted mode IDs and per-mode targets.
Core.mode_order={9,1,8,10,2,3,4,5,6,7}

local function biquad(b0,b1,b2,a1,a2) return {b0,b1,b2,a1,a2,0,0} end
local function run(f,x)
  local y=f[1]*x+f[6]
  f[6]=f[2]*x-f[4]*y+f[7]
  f[7]=f[3]*x-f[5]*y
  return y
end

function Core.analyzer(ch,gain)
  local a={ch=ch,gain=gain or 1,frames={},n=0,k=0,peak=0,f={}}
  for c=1,ch do
    a.f[c]={
      shelf=biquad(1.53512485958697,-2.69169618940638,1.19839281085285,-1.69065929318241,.73248077421585),
      rlb=biquad(1,-2,1,-1.99004745483398,.99007225036621)
    }
  end
  return a
end
local function emit(a)
  if a.n<=0 then return end
  a.frames[#a.frames+1]={k=a.k/a.n,peak=a.peak,dt=a.n/Core.SR}
  a.n,a.k,a.peak=0,0,0
end
function Core.feed(a,samples,n)
  local p=1
  for _=1,n do
    for c=1,a.ch do
      local x=samples[p]; p=p+1
      if x~=x or abs(x)>=math.huge then error("音声サンプルが不正です。",0) end
      x=x*a.gain
      local f=a.f[c]
      local y=run(f.shelf,x)
      local k=run(f.rlb,y)
      a.k=a.k+k*k
      local pk=abs(x); if pk>a.peak then a.peak=pk end
    end
    a.n=a.n+1
    if a.n==Core.HOP then emit(a) end
  end
end
function Core.finish(a) emit(a); return a.frames end

local function rolling_blocks(frames,windowSec,hopSec)
  local n=#frames; if n==0 then return {} end
  local win=max(1,floor(windowSec/Core.DT+.5))
  local hop=max(1,floor(hopSec/Core.DT+.5))
  local pe,pd={0},{0}
  for i,f in ipairs(frames) do
    pe[i+1]=pe[i]+(f.k or 0)*(f.dt or Core.DT)
    pd[i+1]=pd[i]+(f.dt or Core.DT)
  end
  local out={}
  if n<win then
    local e=pe[n+1]-pe[1]; local d=pd[n+1]-pd[1]
    if d>0 and e>0 then local p=e/d; out[1]={power=p,level=-.691+dbp(p)} end
    return out
  end
  local i=1
  while i+win-1<=n do
    local j=i+win-1
    local e=pe[j+1]-pe[i]; local d=pd[j+1]-pd[i]
    if d>0 and e>0 then local p=e/d; out[#out+1]={power=p,level=-.691+dbp(p)} end
    i=i+hop
  end
  return out
end

function Core.integrated(frames)
  local blocks=rolling_blocks(frames,.400,.100)
  if #blocks==0 then return nil end
  local absBlocks={}
  for _,b in ipairs(blocks) do if b.level>=-70 then absBlocks[#absBlocks+1]=b end end
  if #absBlocks==0 then return nil end
  local p=mean_power(absBlocks)
  if not p then return nil end
  local prelim=-.691+dbp(p)
  local gate=max(-70,prelim-10)
  local fp=mean_power(blocks,gate)
  return fp and (-.691+dbp(fp)) or prelim
end

function Core.speech(frames)
  local blocks=rolling_blocks(frames,.200,.100)
  if #blocks==0 then return nil,nil end
  local levels={}; for _,b in ipairs(blocks) do levels[#levels+1]=b.level end
  local p90=quantile(levels,.90); if not p90 then return nil,nil end
  local gate=max(-55,p90-25)
  local p,n=mean_power(blocks,gate)
  if not p or n==0 then return nil,nil end
  return -.691+dbp(p),n/#blocks
end

local function robust_level(values)
  if not values or #values==0 then return nil end
  local a={}; for i,v in ipairs(values) do a[i]=v end; table.sort(a)
  local lo=clamp(floor((#a-1)*.20+1.5),1,#a)
  local hi=clamp(floor((#a-1)*.80+1.5),lo,#a)
  local sum,n=0,0
  for i=lo,hi do
    -- block level = -0.691 + 10log10(power)
    sum=sum+10^((a[i]+.691)/10); n=n+1
  end
  return n>0 and (-.691+dbp(sum/n)) or nil
end

function Core.short_stats(frames)
  local blocks=rolling_blocks(frames,1.000,.100)
  if #blocks==0 then return nil,nil,nil,nil,nil,nil end
  local levels={}; for _,b in ipairs(blocks) do levels[#levels+1]=b.level end
  local p90=quantile(levels,.90); if not p90 then return nil,nil,nil,nil,nil,nil end
  local gate=max(-60,p90-30)
  local active={}
  for _,b in ipairs(blocks) do if b.level>=gate then active[#active+1]=b.level end end
  if #active==0 then active=levels end
  local max1=-150; for _,v in ipairs(active) do if v>max1 then max1=v end end
  return quantile(active,.50),quantile(active,.80),quantile(active,.95),max1,robust_level(active),active
end

function Core.max_window(frames,seconds)
 local win=math.floor(seconds/Core.DT+.5);local hop=math.floor(.1/Core.DT+.5)
 if #frames<win then return nil end
 local energy,duration=0,0;local best=nil
 for i,f in ipairs(frames) do
  local dt=f.dt or Core.DT;energy=energy+(f.k or 0)*dt;duration=duration+dt
  if i>win then local old=frames[i-win];local d=old.dt or Core.DT;energy=energy-(old.k or 0)*d;duration=duration-d end
  if i>=win and (i-win)%hop==0 and duration>=seconds-1e-7 and energy>0 then
   local level=-.691+dbp(energy/duration);best=best and max(best,level) or level
  end
 end
 return best
end
function Core.max_momentary(frames) return Core.max_window(frames,.4) end

function Core.measure(frames)
  if not frames or #frames==0 then return {valid=false,reason="音声を取得できません"} end
  local peak=0; local energy,dt=0,0
  for _,f in ipairs(frames) do
    peak=max(peak,f.peak or 0)
    energy=energy+(f.k or 0)*(f.dt or Core.DT)
    dt=dt+(f.dt or Core.DT)
  end
  local integrated=Core.integrated(frames)
  local speech,activeRatio=Core.speech(frames)
  local median,p80,p95,max1s,robust=Core.short_stats(frames)
  local max400=Core.max_momentary(frames);local shortterm=Core.max_window(frames,3)
  local whole=(dt>0 and energy>0) and (-.691+dbp(energy/dt)) or nil
  return {
    valid=integrated~=nil or speech~=nil or median~=nil or peak>0,
    integrated=integrated,speech=speech,median=median,robust=robust,p80=p80,p95=p95,max1s=max1s,max400=max400,shortterm=shortterm,duration=dt,
    peak=dba(peak),whole=whole,activeRatio=activeRatio
  }
end

function Core.waveform_preview(frames,bins)
  local out={};local n=#(frames or {});bins=min(max(1,bins or Core.WAVEFORM_BINS),max(1,n))
  if n==0 then return out end
  for bin=1,bins do
    local first=max(1,floor((bin-1)*n/bins)+1)
    local last=min(n,max(first,floor(bin*n/bins)))
    local peak=0
    for i=first,last do peak=max(peak,frames[i].peak or 0) end
    out[bin]=peak
  end
  return out
end

function Core.metric(m,mode)
  if not m or not m.valid then return nil end
  local key=Core.modes[mode].key
  return m[key]
end

function Core.neutral(take)
  local env=R.GetTakeEnvelopeByName(take,"Volume")
  if not env then return true end
  if R.CountAutomationItems(env)>0 then return false end
  local mode=R.GetEnvelopeScalingMode(env)
  for i=0,R.CountEnvelopePoints(env)-1 do
    local ok,_,value=R.GetEnvelopePoint(env,i)
    if ok and abs(R.ScaleFromEnvelopeMode(mode,value)-1)>1e-6 then return false end
  end
  return true
end

local function audio_take(item)
  if not item then return nil end
  local take=R.GetActiveTake(item)
  if not take or R.TakeIsMIDI(take) then return nil end
  local source=R.GetMediaItemTake_Source(take)
  if not source then return nil end
  local sourceType=R.GetMediaSourceType(source)
  sourceType=type(sourceType)=="string" and sourceType:upper() or ""
  if sourceType=="EMPTY" or sourceType=="MIDI" or sourceType=="MIDIPOOL" then return nil end
  local sourceRate=R.GetMediaSourceSampleRate(source)
  if not finite(sourceRate) or sourceRate<=0 then return nil end
  local channels=R.GetMediaSourceNumChannels(source)
  if not finite(channels) or channels<1 then return nil end
  return take,source,channels
end
local function take_fx_state(take)
  local n=R.TakeFX_GetCount(take);local enabled={}
  for fx=0,n-1 do enabled[#enabled+1]=R.TakeFX_GetEnabled(take,fx) and "1" or "0" end
  return n,table.concat(enabled)
end
local function stable_num(x)
  return finite(x) and string.format("%.9f",x) or "nan"
end
local function pitch_envelope_state(take)
  local env=R.GetTakeEnvelopeByName(take,"Pitch")
  if not env then return "PITCH_ENV:none" end
  local ok,chunk=R.GetEnvelopeStateChunk(env,"",false)
  if ok and type(chunk)=="string" then return "PITCH_ENV:"..chunk end
  -- A failed chunk read must not silently look identical to an absent envelope.
  return "PITCH_ENV:unreadable:"..tostring(R.CountEnvelopePoints(env))..":"..tostring(R.CountAutomationItems(env))
end
local function take_transform_state(take)
  local parts={
    "PITCH="..stable_num(R.GetMediaItemTakeInfo_Value(take,"D_PITCH")),
    "PPITCH="..stable_num(R.GetMediaItemTakeInfo_Value(take,"B_PPITCH")),
    "PITCHMODE="..stable_num(R.GetMediaItemTakeInfo_Value(take,"I_PITCHMODE")),
    "PAN="..stable_num(R.GetMediaItemTakeInfo_Value(take,"D_PAN")),
    "PANLAW="..stable_num(R.GetMediaItemTakeInfo_Value(take,"D_PANLAW")),
    "STRETCHFLAGS="..stable_num(R.GetMediaItemTakeInfo_Value(take,"I_STRETCHFLAGS")),
    "STRETCHFADESIZE="..stable_num(R.GetMediaItemTakeInfo_Value(take,"F_STRETCHFADESIZE")),
  }
  local n=R.GetTakeNumStretchMarkers(take)
  parts[#parts+1]="STRETCH_COUNT="..tostring(n)
  for i=0,n-1 do
    local marker,pos,srcpos=R.GetTakeStretchMarker(take,i)
    parts[#parts+1]=table.concat({
      "SM",tostring(marker),stable_num(pos),stable_num(srcpos),stable_num(R.GetTakeStretchMarkerSlope(take,i))
    },":")
  end
  parts[#parts+1]=pitch_envelope_state(take)
  return table.concat(parts,"\30")
end

function Core.audio_selection_count(project)
  if not project then return 0 end
  local count=0
  for i=0,R.CountSelectedMediaItems(project)-1 do
    if audio_take(R.GetSelectedMediaItem(project,i)) then count=count+1 end
  end
  return count
end

function Core.collect(project)
  local n=R.CountSelectedMediaItems(project)
  local result,seconds={},0
  for i=0,n-1 do
    local item=R.GetSelectedMediaItem(project,i)
    local take,source,channels=audio_take(item)
    if take then
      if #result>=Core.MAX_ITEMS then error("音声アイテムは1000件まで対応します。",0) end
      local track=R.GetMediaItemTrack(item)
      local v={item=item,take=take,track=track,
        tracknum=R.GetMediaTrackInfo_Value(track,"IP_TRACKNUMBER"),
        pos=R.GetMediaItemInfo_Value(item,"D_POSITION"),len=R.GetMediaItemInfo_Value(item,"D_LENGTH"),
        volume=R.GetMediaItemInfo_Value(item,"D_VOL"),mute=R.GetMediaItemInfo_Value(item,"B_MUTE"),index=R.GetMediaItemInfo_Value(item,"IP_ITEMNUMBER"),
        ch=channels,source=source,sourceType=R.GetMediaSourceType(source),sourceRate=R.GetMediaSourceSampleRate(source),
        sourceChannels=R.GetMediaSourceNumChannels(source),startoffs=R.GetMediaItemTakeInfo_Value(take,"D_STARTOFFS"),
        chanmode=R.GetMediaItemTakeInfo_Value(take,"I_CHANMODE")}
      v.name=R.GetTakeName(take) or "Audio item"
      v.takevol=R.GetMediaItemTakeInfo_Value(take,"D_VOL")
      v.rate=R.GetMediaItemTakeInfo_Value(take,"D_PLAYRATE")
      v.fxCount,v.fxEnabled=take_fx_state(take)
      v.transformState=take_transform_state(take)
      if v.ch~=1 and v.ch~=2 then v.reason="モノ／ステレオのみ対応"
      elseif abs(v.rate-1)>1e-9 then v.reason="再生速度1.0のみ対応"
      elseif R.GetMediaItemInfo_Value(item,"B_MUTE")~=0 or v.volume<=0 or abs(v.takevol)<1e-12 then v.reason="ミュート／音量0"
      elseif not Core.neutral(take) then v.reason="既存のTake Volumeカーブあり（対象外）"
      elseif v.len<=0 or v.len>1800 then v.reason="長さ0秒超〜30分に対応"
      else
        for fx=0,R.TakeFX_GetCount(take)-1 do
          if R.TakeFX_GetEnabled(take,fx) then v.reason="有効なTake FXあり（対象外）"; break end
        end
      end
      if not v.reason then seconds=seconds+v.len end
      result[#result+1]=v
    end
  end
  if seconds>Core.MAX_SECONDS then error("選択した音声の合計は2時間まで対応します。",0) end
  table.sort(result,function(a,b)
    if a.tracknum~=b.tracknum then return a.tracknum<b.tracknum end
    if a.pos~=b.pos then return a.pos<b.pos end
    return a.index<b.index
  end)
  return result,seconds
end

function Core.selection_signature(project)
  if not project then return "no_project" end
  local rows={}
  for i=0,R.CountSelectedMediaItems(project)-1 do
    local item=R.GetSelectedMediaItem(project,i)
    local take=audio_take(item)
    if take then
      local _,iguid=R.GetSetMediaItemInfo_String(item,"GUID","",false)
      local parts={
        iguid or tostring(item),
        stable_num(R.GetMediaItemInfo_Value(item,"D_POSITION")),
        stable_num(R.GetMediaItemInfo_Value(item,"D_LENGTH")),
        stable_num(R.GetMediaItemInfo_Value(item,"D_VOL")),
        stable_num(R.GetMediaItemInfo_Value(item,"B_MUTE")),
      }
      local _,tguid=R.GetSetMediaItemTakeInfo_String(take,"GUID","",false)
      parts[#parts+1]=tguid or tostring(take)
      parts[#parts+1]=stable_num(R.GetMediaItemTakeInfo_Value(take,"D_VOL"))
      parts[#parts+1]=stable_num(R.GetMediaItemTakeInfo_Value(take,"D_PLAYRATE"))
      parts[#parts+1]=stable_num(R.GetMediaItemTakeInfo_Value(take,"D_STARTOFFS"))
      local source=R.GetMediaItemTake_Source(take)
      parts[#parts+1]=tostring(source)
      parts[#parts+1]=tostring(R.GetMediaSourceType(source) or "")
      parts[#parts+1]=stable_num(R.GetMediaSourceSampleRate(source))
      parts[#parts+1]=stable_num(R.GetMediaSourceNumChannels(source))
      parts[#parts+1]=stable_num(R.GetMediaItemTakeInfo_Value(take,"I_CHANMODE"))
      parts[#parts+1]=take_transform_state(take)
      local fxn=R.TakeFX_GetCount(take)
      parts[#parts+1]=tostring(fxn)
      for fx=0,fxn-1 do parts[#parts+1]=R.TakeFX_GetEnabled(take,fx) and "1" or "0" end
      local env=R.GetTakeEnvelopeByName(take,"Volume")
      if env then
        parts[#parts+1]="E"..tostring(R.CountEnvelopePoints(env))..":"..tostring(R.CountAutomationItems(env))
      else
        parts[#parts+1]="E0:0"
      end
      rows[#rows+1]=table.concat(parts,",")
    end
  end
  table.sort(rows)
  if #rows==0 then return "0" end
  return tostring(#rows).."|"..table.concat(rows,"|")
end

-- Cheap polling key used between full signatures. Project revision catches
-- edits; selected item/take pointers catch selection and active-take changes.
function Core.selection_watch_key(project)
  if not project then return "no_project" end
  local n=R.CountSelectedMediaItems(project);local parts={tostring(n)}
  for i=0,n-1 do
    local item=R.GetSelectedMediaItem(project,i)
    parts[#parts+1]=tostring(item)
    parts[#parts+1]=tostring(item and R.GetActiveTake(item) or nil)
  end
  return table.concat(parts,"|")
end

function Core.check(project,items,allowSelectionChange)
  if R.EnumProjects(-1,"")~=project then return nil,"プロジェクトが切り替わりました。" end
  if not allowSelectionChange and Core.audio_selection_count(project)~=#items then return nil,"音声アイテムの選択が変わりました。自動更新します。" end
  for _,v in ipairs(items) do
    if not R.ValidatePtr2(project,v.item,"MediaItem*")
      or (not allowSelectionChange and not R.IsMediaItemSelected(v.item)) then return nil,"音声アイテムの選択が変わりました。自動更新します。" end
    if not v.reason and (R.GetActiveTake(v.item)~=v.take or R.GetMediaItemTrack(v.item)~=v.track
      or R.GetMediaItemInfo_Value(v.item,"D_POSITION")~=v.pos or R.GetMediaItemInfo_Value(v.item,"D_LENGTH")~=v.len
      or R.GetMediaItemInfo_Value(v.item,"D_VOL")~=v.volume or R.GetMediaItemInfo_Value(v.item,"B_MUTE")~=v.mute) then return nil,"対象アイテム自体が変更されています。" end
    if v.take and not v.reason then
      local source=R.GetMediaItemTake_Source(v.take);local fxCount,fxEnabled=take_fx_state(v.take)
      if R.GetMediaItemTakeInfo_Value(v.take,"D_VOL")~=v.takevol or R.GetMediaItemTakeInfo_Value(v.take,"D_PLAYRATE")~=v.rate
        or R.GetMediaItemTakeInfo_Value(v.take,"D_STARTOFFS")~=v.startoffs or R.GetMediaItemTakeInfo_Value(v.take,"I_CHANMODE")~=v.chanmode
        or source~=v.source or not source or R.GetMediaSourceType(source)~=v.sourceType
        or R.GetMediaSourceSampleRate(source)~=v.sourceRate or R.GetMediaSourceNumChannels(source)~=v.sourceChannels
        or fxCount~=v.fxCount or fxEnabled~=v.fxEnabled
        or take_transform_state(v.take)~=v.transformState
        or not Core.neutral(v.take) then return nil,"テイク設定が変更されています。自動更新します。" end
    end
  end
  return true
end

function Core.reader(v)
  local aa=R.CreateTakeAudioAccessor(v.take)
  if not aa then error("音声アクセサーを作成できません。",0) end
  local start,finish=R.GetAudioAccessorStartTime(aa),R.GetAudioAccessorEndTime(aa)
  if not finite(start) or not finite(finish) or finish-start<v.len-1/Core.SR then
    pcall(R.DestroyAudioAccessor,aa); error("取得できる音声範囲がアイテム長と一致しません。",0)
  end
  local buffer_ok,buffer=pcall(R.new_array,Core.READ_BLOCK*v.ch)
  if not buffer_ok or not buffer then pcall(R.DestroyAudioAccessor,aa); error("音声解析用バッファを作成できません。",0) end
  local baseGain=v.volume*abs(v.takevol)
  local dsp_ok,dsp=pcall(Core.analyzer,v.ch,baseGain)
  if not dsp_ok or not dsp then pcall(R.DestroyAudioAccessor,aa); error("ラウドネス解析器を作成できません。",0) end
  return {aa=aa,v=v,start=start,n=0,total=floor(v.len*Core.SR+.5),
    buffer=buffer,dsp=dsp}
end
function Core.reader_progress(reader)
  return reader and reader.total>0 and clamp(reader.n/reader.total,0,1) or 0
end
function Core.dispose(reader)
  if reader and reader.aa then local aa=reader.aa;reader.aa=nil;pcall(R.DestroyAudioAccessor,aa) end
end
function Core.read_step(reader)
  local n=min(Core.READ_BLOCK,reader.total-reader.n)
  if n<=0 then return true end
  if R.AudioAccessorStateChanged(reader.aa) then error("解析中にアイテムが変更されました。",0) end
  reader.buffer.clear()
  local rv=R.GetAudioAccessorSamples(reader.aa,Core.SR,reader.v.ch,reader.start+reader.n/Core.SR,n,reader.buffer)
  if type(rv)~="number" or rv<0 then error("音声サンプルの取得に失敗しました。",0) end
  Core.feed(reader.dsp,reader.buffer.table(1,n*reader.v.ch),n)
  reader.n=reader.n+n
  return reader.n>=reader.total
end

-- PEAK mode fast path: scan only absolute sample peaks. This deliberately skips
-- K-weighting, rolling windows, gating and percentile statistics.
function Core.peak_reader(v)
  local aa=R.CreateTakeAudioAccessor(v.take)
  if not aa then error("音声アクセサーを作成できません。",0) end
  local start,finish=R.GetAudioAccessorStartTime(aa),R.GetAudioAccessorEndTime(aa)
  if not finite(start) or not finite(finish) or finish-start<v.len-1/Core.SR then
    pcall(R.DestroyAudioAccessor,aa); error("取得できる音声範囲がアイテム長と一致しません。",0)
  end
  local buffer_ok,buffer=pcall(R.new_array,Core.PEAK_READ_BLOCK*v.ch)
  if not buffer_ok or not buffer then pcall(R.DestroyAudioAccessor,aa); error("ピーク解析用バッファを作成できません。",0) end
  return {aa=aa,v=v,start=start,n=0,total=floor(v.len*Core.SR+.5),
    buffer=buffer,peak=0,gain=v.volume*abs(v.takevol)}
end
function Core.peak_read_step(reader)
  local n=min(Core.PEAK_READ_BLOCK,reader.total-reader.n)
  if n<=0 then return true end
  if R.AudioAccessorStateChanged(reader.aa) then error("解析中にアイテムが変更されました。",0) end
  reader.buffer.clear()
  local rv=R.GetAudioAccessorSamples(reader.aa,Core.SR,reader.v.ch,reader.start+reader.n/Core.SR,n,reader.buffer)
  if type(rv)~="number" or rv<0 then error("音声サンプルの取得に失敗しました。",0) end
  local samples=reader.buffer.table(1,n*reader.v.ch)
  local peak=reader.peak
  for i=1,#samples do
    local x=samples[i]
    if x~=x or abs(x)>=math.huge then error("音声サンプルが不正です。",0) end
    local p=abs(x)
    if p>peak then peak=p end
  end
  reader.peak=peak
  reader.n=reader.n+n
  return reader.n>=reader.total
end
function Core.finish_peak_reader(reader)
  local p=(reader.peak or 0)*(reader.gain or 1)
  if p<=0 then return {valid=false,reason="Sample Peakを測定できません",peak=nil,peakOnly=true} end
  return {valid=true,peak=dba(p),peakOnly=true,frames=nil}
end

function Core.plan(items,mode,targetMode,targetValue,referenceIndex)
  -- Unmeasurable is a completed result, not an unfinished analysis.
  for _,v in ipairs(items) do
    local reason=v.reason or (v.metrics and not v.metrics.valid and (v.metrics.reason or "この方式で測定できません"))
    v.plan=reason and {valid=false,reason=reason} or nil
  end
  local reference=nil
  local refIndex=clamp(floor((referenceIndex or 1)+.5),1,max(1,#items))
  if targetMode==2 then
    local ref=items[refIndex]
    reference=ref and ref.metrics and Core.metric(ref.metrics,mode) or nil
    if not reference then return nil,ref and (ref.metrics or ref.reason) and "基準ファイルは選択方式で測定できません。尺と方式を確認してください。" or "任意ファイルを基準にするため、そのファイルの解析完了を待っています。" end
  end
  local changed=0
  for i,v in ipairs(items) do
    if v.metrics and v.metrics.valid and not v.reason then
      local current=Core.metric(v.metrics,mode)
      if current then
        local target=(targetMode==2) and reference or targetValue
        local gain=target-current
        local refHold=(targetMode==2 and i==refIndex)
        if refHold then gain=0 end
        gain=clamp(gain,-Core.MAX_GAIN,Core.MAX_GAIN)
        local predicted=current+gain
        local peakAfter=finite(v.metrics.peak) and (v.metrics.peak+gain) or nil
        local doesChange=not refHold and abs(gain)>.005
        if doesChange then changed=changed+1 end
        v.plan={valid=true,current=current,target=target,gain=gain,predicted=predicted,peakAfter=peakAfter,reference=refHold,changed=doesChange}
      else
        local key=Core.modes[mode] and Core.modes[mode].key
        local short=v.metrics.duration and v.metrics.duration<(key=="max400" and .4 or key=="shortterm" and 3 or 0)-1e-7
        v.plan={valid=false,reason=short and (key=="max400" and "LUFS-Mには0.4秒以上必要です" or "LUFS-Sには3秒以上必要です") or "この方式で測定できません"}
      end
    end
  end
  return changed
end

function Core.apply(project,items,allowSelectionChange)
  local ok,err=Core.check(project,items,allowSelectionChange); if not ok then return nil,err end
  local targets={}
  for _,v in ipairs(items) do if v.plan and v.plan.valid and v.plan.changed then targets[#targets+1]=v end end
  if #targets==0 then return nil,"適用する変更がありません。" end
  R.Undo_BeginBlock2(project); R.PreventUIRefresh(1)
  local touched={}
  local success,detail=xpcall(function()
    for _,v in ipairs(targets) do
      local newVol=v.volume*amp(v.plan.gain)
      if not finite(newVol) or newVol<=0 then error("アイテム音量を設定できません。",0) end
      touched[#touched+1]=v
      if not R.SetMediaItemInfo_Value(v.item,"D_VOL",newVol) then error("アイテム音量を設定できません。",0) end
      R.UpdateItemInProject(v.item)
    end
  end,debug.traceback)
  local restored=true
  if not success then
    for i=#touched,1,-1 do
      local v=touched[i]
      local called,result=pcall(R.SetMediaItemInfo_Value,v.item,"D_VOL",v.volume)
      if not called or not result then restored=false else R.UpdateItemInProject(v.item) end
    end
  end
  R.PreventUIRefresh(-1)
  if not success then
    R.UpdateArrange();R.Undo_EndBlock2(project,restored and "Simple Normalizer: failed (restored)" or "Simple Normalizer: failed",4)
    local message=tostring(detail):match("^[^\n]+") or tostring(detail)
    return nil,restored and message or (message.." 元の音量へ戻せない項目があります。REAPERのUndoで確認してください。")
  end
  R.UpdateArrange()
  R.Undo_EndBlock2(project,"Simple Normalizer: normalize selected items",4)
  return #targets,targets
end

local SECTION="BLT_SIMPLE_NORMALIZER"
local function extnum(key,default)
  local n=tonumber(R.GetExtState(SECTION,key)); return finite(n) and n or default
end
local S={mode=clamp(floor(extnum("mode",1)+.5),1,#Core.modes),targetMode=clamp(floor(extnum("targetMode",1)+.5),1,2),targets={}}
local function field_round(n) return (n<0 and math.ceil(n*100-.5) or floor(n*100+.5))/100 end
local function field_text(n)
  local text=string.format('%.2f',field_round(n))
  return text:gsub('0+$',''):gsub('%.$','')
end
for i,m in ipairs(Core.modes) do S.targets[i]=field_round(clamp(extnum("target"..i,m.default),-80,6)) end
local A={items={},selected=1,offset=0,message="音声アイテムを選択すると自動解析します。",bad=false,needsAnalyze=true,dirty=true,changeCount=0,
  project=nil,selectionSig=nil,analysisSig=nil,pendingSig=nil,pendingSince=0,autoDelay=.12,applyWhenReady=false,executionLocked=false,forceFinish=false,analyzedCount=0,
  watchAt=0,watchInterval=.20,watchRevision=nil,watchSelectionKey=nil,
  fieldFlash={},fieldDrag=nil,scrollDrag=nil}
local E=nil
local function status(text,bad) A.message=bad and BLT.publicError(text) or tostring(text or ''); A.bad=bad or false end
local function save_settings()
  BLT.store(SECTION,"mode",tostring(S.mode),true)
  BLT.store(SECTION,"targetMode",tostring(S.targetMode),true)
  for i,v in ipairs(S.targets) do BLT.store(SECTION,"target"..i,tostring(v),true) end
end
local function target_value() return S.targets[S.mode] end
local function unit() return Core.modes[S.mode].unit end
local function eligible_count()
  local n=0; for _,v in ipairs(A.items) do if not v.reason then n=n+1 end end; return n
end
local function invalidate_snapshot(err)
  -- A failed eligibility check does not itself mean the source changed.
  -- Retry only after an actual selection/source change; otherwise retain the
  -- completed rows and error instead of scheduling the same batch indefinitely.
  local project=R.EnumProjects(-1,"")
  local changed=project~=A.project or Core.selection_signature(project)~=A.selectionSig
  A.changeCount=0;A.dirty=false;A.needsAnalyze=changed
  if changed then A.selectionSig=nil end
  status(err,true)
end
local function replan(partial)
  if #A.items==0 then A.changeCount=0; return end
  if not partial and not A.job then
    local ok,err=Core.check(A.project,A.items,A.executionLocked)
    if not ok then invalidate_snapshot(err); return end
  end
  local n,e=Core.plan(A.items,S.mode,S.targetMode,target_value(),A.selected)
  if not n then
    A.changeCount=0; A.dirty=false
    if not A.job then status(e,true) end
    return
  end
  A.changeCount=n; A.dirty=false
  if not A.job then status(string.format("%s · %d件を処理できます。",Core.modes[S.mode].name,n)) end
end
local function cancel_auto(message)
  if A.job then Core.dispose(A.job.reader); A.job=nil end
  A.needsAnalyze=true; A.dirty=true; A.changeCount=0; A.analysisSig=nil; A.applyWhenReady=false; A.executionLocked=false; A.forceFinish=false; A.analyzedCount=0
  if message then status(message,false) end
  collectgarbage("step",400)
end
local function begin_auto_analysis(sig)
  if A.job then return end
  A.project=R.EnumProjects(-1,"")
  local count=Core.audio_selection_count(A.project)
  if count<=0 then
    A.items={}; A.total=0; A.selected=1; A.offset=0; A.changeCount=0; A.analyzedCount=0
    A.needsAnalyze=true; A.dirty=true; A.selectionSig=sig or "0"; A.analysisSig=nil
    status("音声アイテムを選択すると自動解析します。",false)
    collectgarbage("collect")
    return
  end
  local ok,items,total=pcall(function() local a,b=Core.collect(A.project); return a,b end)
  if not ok then
    A.items={}; A.changeCount=0; A.needsAnalyze=true; A.dirty=true; A.selectionSig=sig; A.analyzedCount=0
    status(tostring(items),true); return
  end
  A.items,A.total=items,total
  A.selected=clamp(A.selected or 1,1,max(1,#A.items)); A.offset=0; A.analyzedCount=0
  A.needsAnalyze=true; A.dirty=true; A.changeCount=0
  A.analysisSig=sig or Core.selection_signature(A.project); A.selectionSig=A.analysisSig
  A.job={index=1,done=0,lastSig=A.analysisSig,validateAt=0}; replan(true)
  status(string.format("%d件をバックグラウンド解析しています…",#A.items),false)
end

local apply_ready -- forward declaration

local function begin_peak_fast_apply(sig)
  local project=R.EnumProjects(-1,"")
  if Core.audio_selection_count(project)<=0 then status("ノーマライズする音声アイテムを選択してください。",true); return false end

  -- Cancel the ordinary analyzer immediately. Fully completed rows keep their
  -- metrics; the unfinished reader is discarded and replaced by a peak-only scan.
  if A.job then Core.dispose(A.job.reader); A.job=nil end
  A.project=project

  -- If the REAPER selection changed before the click reached us, lock the selection
  -- that exists at the exact moment Execute was pressed.
  if #A.items==0 or A.selectionSig~=sig then
    local ok,items,total=pcall(function() local a,b=Core.collect(project); return a,b end)
    if not ok then status(tostring(items),true); return false end
    A.items,A.total=items,total
    A.selected=clamp(A.selected or 1,1,max(1,#A.items)); A.offset=0
  end

  A.analysisSig=sig; A.selectionSig=sig; A.pendingSig=nil
  A.needsAnalyze=true; A.dirty=true; A.changeCount=0; A.analyzedCount=0
  A.applyWhenReady=true; A.executionLocked=true; A.forceFinish=true

  local missing=false
  for _,v in ipairs(A.items) do
    if not v.reason and not (v.metrics and finite(v.metrics.peak)) then missing=true; break end
  end
  if not missing then
    A.needsAnalyze=false; A.applyWhenReady=false; A.forceFinish=false
    replan(false); apply_ready()
    return true
  end

  A.job={index=1,done=0,kind="peak_fast",lastSig=sig,validateAt=0}
  status("PEAK Fast Path：通常解析を停止し、未取得分のSample Peakだけを高速取得しています…",false)
  return true
end

local function advance()
  local job=A.job; if not job then return end
  if R.EnumProjects(-1,"")~=A.project then
    cancel_auto("プロジェクトが切り替わりました。自動更新します。"); A.selectionSig=nil; return
  end
  local currentSig=job.lastSig or A.analysisSig
  local now=R.time_precise()
  if not A.executionLocked and now>=(job.validateAt or 0) then
    currentSig=Core.selection_signature(A.project);job.lastSig=currentSig;job.validateAt=now+(A.watchInterval or .20)
    if currentSig~=A.analysisSig then
      cancel_auto("選択が変わりました。自動更新します。"); A.selectionSig=nil; A.pendingSig=currentSig; A.pendingSince=now; return
    end
  end
  local peakFast=job.kind=="peak_fast"
  local started=R.time_precise()
  local loops=peakFast and 256 or (A.forceFinish and 64 or 4)
  local budget=peakFast and .080 or (A.forceFinish and .050 or .012)
  for _=1,loops do
    local v=A.items[job.index]
    if not v then
      A.job=nil; A.needsAnalyze=false; A.analysisSig=nil
      if not A.executionLocked then A.selectionSig=currentSig end
      A.forceFinish=false
      replan(false)
      if A.applyWhenReady and apply_ready then A.applyWhenReady=false; apply_ready() end
      return
    end
    if v.reason then
      job.index=job.index+1; A.analyzedCount=A.analyzedCount+1; replan(true)
    elseif peakFast and v.metrics and finite(v.metrics.peak) then
      -- A completed ordinary analysis already contains the exact Sample Peak we need.
      job.index=job.index+1; job.done=job.done+v.len; A.analyzedCount=A.analyzedCount+1; replan(true)
    elseif peakFast then
      local ok,done=xpcall(function()
        if not job.reader then job.reader=Core.peak_reader(v) end
        return Core.peak_read_step(job.reader)
      end,debug.traceback)
      if not ok then
        Core.dispose(job.reader); job.reader=nil; v.reason=tostring(done):match("^[^\n]+")
        job.index=job.index+1; job.done=job.done+v.len; A.analyzedCount=A.analyzedCount+1; replan(true)
      elseif done then
        local reader=job.reader; v.waveform=nil; v.metrics=Core.finish_peak_reader(reader)
        Core.dispose(reader); job.reader=nil; job.index=job.index+1; job.done=job.done+v.len; A.analyzedCount=A.analyzedCount+1
        replan(true)
      end
    else
      local ok,done=xpcall(function()
        if not job.reader then job.reader=Core.reader(v) end
        return Core.read_step(job.reader)
      end,debug.traceback)
      if not ok then
        Core.dispose(job.reader); job.reader=nil; v.reason=tostring(done):match("^[^\n]+")
        job.index=job.index+1; job.done=job.done+v.len; A.analyzedCount=A.analyzedCount+1; replan(true)
      elseif done then
        local reader=job.reader;local frames=Core.finish(reader.dsp)
        v.waveform=Core.waveform_preview(frames);v.metrics=Core.measure(frames);frames=nil
        Core.dispose(reader); job.reader=nil; job.index=job.index+1; job.done=job.done+v.len; A.analyzedCount=A.analyzedCount+1
        collectgarbage("step",600)
        replan(true) -- finished rows become visible immediately
      end
    end
    if R.time_precise()-started>budget then return end
  end
end

local commit

apply_ready=function()
  if A.job then
    A.applyWhenReady=true; A.executionLocked=true; A.forceFinish=true
    status("対象を固定して、残りを解析後そのままノーマライズします…")
    return
  end
  if A.needsAnalyze or A.dirty then replan(false) end
  local ok,err=Core.check(A.project,A.items,A.executionLocked)
  if not ok then
    A.applyWhenReady=false; A.executionLocked=false; A.forceFinish=false
    invalidate_snapshot(err); return
  end
  local n,appliedOrErr=Core.apply(A.project,A.items,A.executionLocked)
  if not n then
    A.applyWhenReady=false; A.executionLocked=false; A.forceFinish=false
    status(appliedOrErr,true); return
  end
  -- Clear every audio item in this operation, including a reference item or an
  -- item whose required gain rounded to zero. Non-audio/note items are not in
  -- A.items and therefore keep their selection.
  for _,v in ipairs(A.items) do
    if v.item and R.ValidatePtr2(A.project,v.item,"MediaItem*") then R.SetMediaItemSelected(v.item,false) end
  end
  R.UpdateArrange()
  A.items={}; A.changeCount=0; A.analyzedCount=0; A.needsAnalyze=true; A.dirty=true; A.applyWhenReady=false; A.executionLocked=false; A.forceFinish=false
  A.selectionSig="0"; A.analysisSig=nil; A.pendingSig=nil; A.pendingSince=R.time_precise()
  collectgarbage("collect")
  status(n.."件をノーマライズしました。選択を解除しました。")
end

local function request_apply()
  if not commit() then return end

  if A.applyWhenReady and A.job then
    local wasPeakFast=A.job.kind=="peak_fast"
    if wasPeakFast then Core.dispose(A.job.reader); A.job=nil end
    A.applyWhenReady=false; A.executionLocked=false; A.forceFinish=false
    if wasPeakFast then
      A.needsAnalyze=true; A.analysisSig=nil; A.selectionSig=nil
      A.pendingSig=Core.selection_signature(R.EnumProjects(-1,"")); A.pendingSince=R.time_precise()
      status("PEAK高速実行をキャンセルしました。通常の自動解析へ戻ります。",false)
    else
      status("ノーマライズ実行をキャンセルしました。自動解析は継続します。",false)
    end
    return
  end

  local project=R.EnumProjects(-1,""); local sig=Core.selection_signature(project)
  if Core.audio_selection_count(project)<=0 then status("ノーマライズする音声アイテムを選択してください。",true); return end

  if Core.modes[S.mode].key=="peak" then
    begin_peak_fast_apply(sig)
    return
  end

  if A.job then
    A.applyWhenReady=true; A.executionLocked=true; A.forceFinish=true
    status("対象を固定して、残りを解析後そのままノーマライズします…")
    return
  end
  if #A.items==0 or A.selectionSig~=sig or A.needsAnalyze then
    begin_auto_analysis(sig)
    if A.job then
      A.applyWhenReady=true; A.executionLocked=true; A.forceFinish=true
      status("対象を固定して、残りを解析後そのままノーマライズします…")
      return
    end
  end
  A.executionLocked=true
  replan(false); apply_ready()
end

local function auto_watch()
  local project=R.EnumProjects(-1,"")
  if project~=A.project and not A.job then
    A.project=project; A.items={}; A.selected=1; A.offset=0; A.changeCount=0; A.analyzedCount=0
    A.needsAnalyze=true; A.dirty=true; A.selectionSig=nil; A.pendingSig=nil
    A.watchAt=0;A.watchRevision=nil;A.watchSelectionKey=nil
  end
  if A.job then return end
  local now=R.time_precise()
  if now<(A.watchAt or 0) then return end
  A.watchAt=now+(A.watchInterval or .20)
  local revision=R.GetProjectStateChangeCount(project)
  local watchKey=Core.selection_watch_key(project)
  if revision==A.watchRevision and watchKey==A.watchSelectionKey and A.selectionSig~=nil and not A.pendingSig then return end
  A.watchRevision=revision;A.watchSelectionKey=watchKey
  local sig=Core.selection_signature(project)
  if sig==A.selectionSig then A.pendingSig=nil; return end
  if sig~=A.pendingSig then A.pendingSig=sig; A.pendingSince=now; return end
  if now-A.pendingSince<A.autoDelay then return end
  A.pendingSig=nil; begin_auto_analysis(sig)
end

local W,H=1120,764
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

local scale,ox,oy,mx,my=1,0,0,-1,-1
local widgets,downLast,pressed={},false,nil
local hover_hint=""
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
local function line(x,y,xx,yy,c,a) color(c,a); gfx.line(sx(x),sy(y),sx(xx),sy(yy),1) end
local function disc(x,y,r,c,a) color(c,a); gfx.circle(sx(x),sy(y),r*scale,1,1) end

local function font(size,kind,bold) BLT.font(size,kind,bold,scale,fonts) end
local function label(text,x,y,w,h,size,c,bold,flags,kind,literal)
  local shown=literal and tostring(text) or Language.message(text)
  font(size,kind,bold); color(c or C.text); gfx.x,gfx.y=sx(x),sy(y)
  if shown~=tostring(text) and w then shown=BLT.ui.fit(shown,w*scale) end
  gfx.drawstr(BLT.cleanText(shown),flags or 0,sx(x+w),sy(y+h))
end
local function measure(text,size,kind,bold) font(size,kind,bold);return BLT.metricsFor(Language.message(text))/scale end
local function right_label(text,right,y,size,c,kind,bold)
  local tw=measure(text,size,kind,bold); label(text,right-tw,y,tw+2,size+9,size,c,bold,0,kind)
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
local function animate(key,target)
 if BLT.presetRevision and BLT.presetMotionSeen[key]~=BLT.presetRevision then
  BLT.presetMotionSeen[key]=BLT.presetRevision;motion[key]=target;return target
 end
  local p=motion[key]; if p==nil then p=target end
  local v=p+(target-p)*BLT.blend(frame_dt); motion[key]=v; return v
end
local function hash(n,salt) local v=math.sin(n*12.9898+salt*78.233)*43758.5453; return v-floor(v) end
local function inside(x,y,w,h) return mx>=x and my>=y and mx<=x+w and my<=y+h end
local function glow_line(x,y,x2,y2,c,strength)
  strength=strength or 1
  line(x,y-2,x2,y2-2,c,.035*strength); line(x,y+2,x2,y2+2,c,.035*strength)
  line(x,y-1,x2,y2-1,c,.10*strength); line(x,y+1,x2,y2+1,c,.10*strength)
  line(x,y,x2,y2,c,.92*strength)
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
local function register(id,x,y,w,h,fn,hint,enabled)
  widgets[#widgets+1]={id=id,x=x,y=y,w=w,h=h,fn=fn,hint=hint,enabled=enabled~=false}
  if inside(x,y,w,h) and hint then hover_hint=hint end
end
local function draw_background()
  rect(0,0,W,H+22,C.bg); disc(W-44,42,170,C.accent,.016); disc(4,H-80,145,C.bg2,.032)
  gradient(0,0,W,96,C.bg2,C.bg,.22,0,true);  
  line(17,116,17,H-65,C.edge2,.12); for y=126,H-68,18 do line(17,y,22,y,C.edge2,.10) end
end
local function segment_button(id,text,x,y,w,h,active,fn,hint,enabled)
  enabled=enabled~=false
  local hovered=inside(x,y,w,h) and enabled
  local a=animate("segment_"..id,active and 1 or (hovered and .24 or 0))
  local body=active and C.panel2 or C.panel
  local bodyAlpha=active and .98 or .82
  rect(x,y,w,h,body,bodyAlpha)
  gradient(x,y,w,h,C.accent3,C.panel,active and (.38+.10*a) or (.08+.08*a),active and .035 or 0)
  if active then
    line(x,y,x+w-5,y,C.accent2,.72)
    line(x,y,x,y+h-5,C.accent2,.66)
    glow_line(x+12,y+h-1,x+w-12,y+h-1,C.accent2,.27)
  else
    line(x,y+h-1,x+w,y+h-1,C.edge2,.16+.16*a)
  end
  finish_corners(x,y,w,h,6,false,active and C.accent2 or C.edge2,active and .62 or (.18+.18*a))
  local tc
  if not enabled then tc=C.faint
  elseif active then tc=C.text
  elseif hovered then tc=C.muted
  else tc={C.muted[1]*.82,C.muted[2]*.82,C.muted[3]*.82} end
  label(text,x,y+2,w,h-4,11,tc,true,5)
  register(id,x,y,w,h,fn,hint,enabled)
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
  chameleonPressed=false,resizeCursors={},resizeCursorMode=nil,titleH=26,windowTitle='BLT Simple Normalizer',titleText='S I M P L E   N O R M A L I Z E R',
  minW=560,minH=441,mint={0.38,0.88,0.72},ice={0.65,0.895,1.0},red={1.0,0.27,0.34},
  isWindows=R.GetOS():match("Win")~=nil,resizeEdge=6,resizeCornerBand=8,resizeCornerSpan=24,resizeTopLeftGuard=30,resizeTopRightGuard=110,
  tooltipHover=nil,tooltipSince=0,tooltipVisible=false,tooltipDelay=.70,
  cursorId={we=32644,ns=32645,nwse=32642,nesw=32643,arrow=32512}}
Chrome.font=Chrome.isWindows and "Segoe UI" or (BLT_MAC and "Helvetica Neue" or "sans-serif")
local CHROME_DEFAULT={
  mint={Chrome.mint[1],Chrome.mint[2],Chrome.mint[3]},
  ice={Chrome.ice[1],Chrome.ice[2],Chrome.ice[3]},
}
local function chameleon_notify(text)
  status(text,false)
end

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

local function section_title(text,x,y,line_end)
  label(text,x,y,150,16,9.5,C.accent2,true); gradient(x+92,y+8,line_end-(x+92),1,C.edge2,C.edge2,.28,.02)
end

local function balance_icon(x,y)
  local active=A.job~=nil
  local pulse=.5+.5*math.sin(anim_time*1.55)
  local w,h=108,54
  local targetY=y+27
  local xs={x+22,x+43,x+64,x+85}
  local offsets={0,-12,10,-8}

  disc(x+54,targetY,34,C.accent,.013+.008*pulse)
  gradient(x+2,y+3,w-4,h-6,C.panel2,C.panel,.13,.01)
  line(x+2,y+3,x+w-3,y+3,C.edge2,.15)
  line(x+2,y+h-3,x+w-9,y+h-3,C.edge,.14)
  glow_line(x+8,targetY,x+w-7,targetY,C.accent2,.13+.045*pulse)

  if animations_active then icon_clock=icon_clock+frame_dt end
  local interval=active and .076 or .11
  while animations_active and icon_clock>=interval and #icon_particles<36 do
    icon_clock=icon_clock-interval; icon_serial=icon_serial+1
    local lane=2+floor(hash(icon_serial,1)*3) -- non-reference blocks only
    local knobY=targetY+offsets[lane]
    local dir=(targetY-knobY)>=0 and 1 or -1
    local sx=xs[lane]+(hash(icon_serial,2)-.5)*6.8
    local sy=knobY+(hash(icon_serial,3)-.5)*3.8
    local cx=xs[lane]+(hash(icon_serial,4)-.5)*2.0
    local cy=targetY+(hash(icon_serial,5)-.5)*1.4
    local ex=xs[lane]+(hash(icon_serial,6)-.5)*1.2
    local ey=targetY+dir*(5.0+hash(icon_serial,7)*7.0)
    local life=(active and .90 or 1.12)+hash(icon_serial,8)*(active and .36 or .42)
    icon_particles[#icon_particles+1]={
      age=0,life=life,sx=sx,sy=sy,cx=cx,cy=cy,ex=ex,ey=ey,
      rBefore=.72+hash(icon_serial,9)*.82,
      rAfterGrow=1.55+hash(icon_serial,10)*1.55,
      rAfterShrink=.30+hash(icon_serial,11)*.40,
      trailBefore=7.5+hash(icon_serial,12)*7.0,
      trailAfterGrow=7.0+hash(icon_serial,13)*8.0,
      trailAfterShrink=2.6+hash(icon_serial,14)*3.4,
      bend=(hash(icon_serial,15)-.5)*7.0,
      drift=(hash(icon_serial,16)-.5)*8.5,
      phase=hash(icon_serial,17)*math.pi*2,
      preColor=(offsets[lane]>0) and C.warn or C.accent2,
      postColor=C.focus2,
      dir=dir
    }
  end

  for i=#icon_particles,1,-1 do
    local p=icon_particles[i]; p.age=p.age+particle_dt
    if p.age>=p.life then
      table.remove(icon_particles,i)
    else
      local t=p.age/p.life
      local growsAfter=p.dir<0 -- bottom -> top expands after crossing centre
      local split=growsAfter and .50 or .68
      local before=t<split
      local u=before and (t/split) or ((t-split)/(1-split))
      local ease
      if before then
        ease=1-(1-u)*(1-u)
      elseif growsAfter then
        ease=u*u*(3-2*u) -- slower departure from the centre
      else
        ease=1-(1-u)*(1-u)
      end
      local px,py
      if before then
        local sway=math.sin(math.pi*u)*p.bend*.28 + math.sin(u*math.pi*2+p.phase)*1.15
        px=p.sx+(p.cx-p.sx)*ease+sway
        py=p.sy+(p.cy-p.sy)*ease
      else
        local sway=math.sin(math.pi*u)*p.bend*.20 + math.sin(u*math.pi*1.6+p.phase)*1.35
        px=p.cx+(p.ex+p.drift-p.cx)*ease+sway
        py=p.cy+(p.ey-p.cy)*ease
      end

      local fadeIn=min(1,t/.11)
      local fadeOut=min(1,(1-t)/.16)
      local fade=min(fadeIn,fadeOut)
      local r=before and p.rBefore or (growsAfter and p.rAfterGrow or p.rAfterShrink)
      local trail=before and p.trailBefore or (growsAfter and p.trailAfterGrow or p.trailAfterShrink)
      local dx,dy
      if before then dx,dy=p.cx-p.sx,p.cy-p.sy else dx,dy=p.ex-p.cx,p.ey-p.cy end
      local dl=sqrt(dx*dx+dy*dy); if dl<1e-6 then dl=1 end
      local ux,uy=dx/dl,dy/dl

      local c=before and p.preColor or p.postColor
      local postGrow=(not before) and growsAfter
      line(px-ux*trail,py-uy*trail,px,py,c,(before and .17 or postGrow and .16 or .11)*fade)
      disc(px,py,r+(before and 3.7 or postGrow and 4.8 or 1.5),C.accent,(before and .026 or postGrow and .032 or .014)*fade)
      disc(px,py,r+(before and 1.45 or postGrow and 1.9 or .65),c,(before and .13 or postGrow and .16 or .10)*fade)
      disc(px,py,r,C.text,(before and .82 or postGrow and .90 or .72)*fade)

      local centreDist=abs(t-split)
      if centreDist<.06 then
        local flash=(1-centreDist/.06)*fade
        disc(p.cx,p.cy,5.2,C.accent,.050*flash)
        disc(p.cx,p.cy,2.2,C.focus2,.26*flash)
      end
    end
  end

  for i,xx in ipairs(xs) do
    local top,bottom=y+8,y+46
    local knobY=targetY+offsets[i]
    line(xx,top,xx,bottom,i==1 and C.accent2 or C.edge2,i==1 and .56 or .28)

    for k=-2,2 do
      local yy=targetY+k*4.3
      local span=1.8+2.4*abs(math.sin(i*1.31+k*.87))
      line(xx-span,yy,xx+span,yy,i==1 and C.accent2 or C.faint,i==1 and .30 or .16)
    end

    if i==1 then
      cut_panel(xx-6.2,targetY-3.35,12.4,6.7,1.5,C.panel2,.92,C.focus2,.72)
      disc(xx,targetY,1.45,C.focus2,.88)
    else
      local c=offsets[i]>0 and C.warn or C.accent2
      glow_line(xx,knobY,xx,targetY,c,.075)

      local cycle=(anim_time*.34+(i-2)*.055)%1
      local moveStart,moveEnd,fadeEnd=.12,.70,.82
      local gy,ga=knobY,1
      if cycle<moveStart then
        gy=knobY; ga=1
      elseif cycle<moveEnd then
        local u=(cycle-moveStart)/(moveEnd-moveStart)
        local q=1-u
        local ease=1-q*q*q
        gy=knobY+(targetY-knobY)*ease
        ga=1
      elseif cycle<fadeEnd then
        gy=targetY
        ga=1-(cycle-moveEnd)/(fadeEnd-moveEnd)
      else
        gy=targetY; ga=0
      end

      if ga>.001 then
        disc(xx,gy,8.0,C.accent,.018*ga)
        cut_panel(xx-6.2,gy-3.35,12.4,6.7,1.5,C.panel2,.92*ga,c,.72*ga)
        if abs(gy-targetY)<1.0 then
          disc(xx,targetY,2.6,C.accent,.050*ga)
          disc(xx,targetY,1.15,C.focus2,.70*ga)
        end
      end

      disc(xx,targetY,1.8,C.accent,.026+.012*pulse)
      disc(xx,targetY,1.1,C.focus2,.62)
    end
  end
end

local function value_for_edit(key)
  if key=="target" then return target_value() end
end
function A.flash_field(key) A.fieldFlash[key]=R.time_precise() end
function A.field_flash_value(key)
  local t=A.fieldFlash[key];if not t then return 0 end
  local age=R.time_precise()-t
  if age>=1.15 then A.fieldFlash[key]=nil;return 0 end
  local q=clamp(age/1.15,0,1);return 1-q*q*(3-2*q)
end
function A.normalize_field(key,n)
  if key=="target" then local v=field_round(clamp(n,-80,6));return v,abs(v-n)>1e-12 end
  return n,false
end
function A.apply_field(key,n,flash)
  if not finite(n) then return false end
  local value,clipped=A.normalize_field(key,n)
  if clipped and flash then A.flash_field(key) end
  local old=value_for_edit(key)
  if abs(value-old)<=1e-12 then return true end
  if key=="target" then S.targets[S.mode]=value end
  save_settings();A.dirty=true;replan(A.job~=nil);return true
end
function A.update_field_drag(py,fine)
  local d=A.fieldDrag;if not d then return end
  local dy=d.startY-py
  if not d.moved and abs(dy)<3 then return end
  d.moved=true;E=nil
  local inc=fine and .1 or 1;local pixels=fine and 8 or 3
  local q=dy/pixels;local ticks=(q<0 and -1 or 1)*floor(abs(q)+.5)
  local raw=d.startValue+ticks*inc;local value,clipped=A.normalize_field(d.key,raw)
  if clipped and not d.clipped then A.flash_field(d.key);d.clipped=true elseif not clipped then d.clipped=false end
  if abs(value-value_for_edit(d.key))>1e-12 then A.apply_field(d.key,value,false) end
end
local function edit(key)
  local v=value_for_edit(key);E={key=key,text=field_text(v),all=true}
end
commit=function()
  if not E then return true end
  local n=tonumber(E.text);if not finite(n) then local key=E.key;A.flash_field(key);E=nil;status("数値を入力できなかったため、元の値へ戻しました。",true);return true end
  local key=E.key;A.apply_field(key,n,true);E=nil;return true
end
local function number_field(id,title,unitText,x,y,w,enabled)
  enabled=enabled~=false
  local editing=E and E.key==id;local raw=editing and E.text or value_for_edit(id)
  local titleColor=enabled and C.muted or C.quiet
  label(title,x,y+6,w-116,22,11,titleColor,true)
  local fx,fw=x+w-114,72;local hovered=inside(fx,y,fw,31) and enabled;local a=animate("field_"..id,editing and 1 or (hovered and .25 or 0))
  local flash=A.field_flash_value(id)
  gradient(fx,y,fw,31,enabled and C.panel2 or C.bg,enabled and C.field or C.bg,.30+.20*a,enabled and .78 or .28)
  if flash>0 then rect(fx-4,y-4,fw+8,39,C.red,.025*flash);gradient(fx,y,fw,31,C.red,C.field,.22*flash,.02*flash,true) end
  line(fx,y,fx+fw,y,flash>0 and C.red or (enabled and C.edge2 or C.edge),.20+(enabled and .50*a or 0)+.42*flash);line(fx,y+31,fx+fw,y+31,C.edge,enabled and .42 or .16)
  finish_corners(fx,y,fw,31,6,false,flash>0 and C.red or (enabled and C.edge2 or C.edge),enabled and (.24+.38*a+.42*flash) or .12)
  local txt=editing and tostring(raw) or field_text(raw)
  if editing and E.all then local tw=min(fw-14,measure(txt,15,3,true)+8);rect(fx+7,y+6,tw,19,C.focus2,.88);label(txt,fx+9,y+4,fw-16,24,15,C.ink,true,0,3)
  else label(txt,fx+9,y+4,fw-16,24,15,enabled and C.text or C.quiet,true,0,3) end
  label(unitText,fx+fw+7,y+7,40,20,9,enabled and C.faint or C.quiet,true)
  register(id,fx,y,fw,31,function() edit(id) end,"クリック入力 ／ 上下ドラッグ：1刻み（Shift：0.1） ／ ホイール：0.1",enabled)
  local f=widgets[#widgets];f.field=true;f.key=id;f.get=function() return value_for_edit(id) end
end
local function fmt(n,d) return finite(n) and string.format("%."..(d or 1).."f",n) or "—" end
local function signed(n) return finite(n) and string.format("%+.1f",n) or "—" end

local function analysis_progress()
  if not A.job then return nil end
  local j=A.job; local current=j.reader and Core.reader_progress(j.reader)*j.reader.v.len or 0
  return clamp((j.done+current)/max(A.total,.001),0,1)
end
local function waveform(v)
  local x,y,w,h=360,121,738,202
  gradient(x,y,w,h,C.panel2,C.field,.24,.68); line(x,y,x+w,y,C.edge2,.34); line(x,y+h,x+w,y+h,C.edge,.38); finish_corners(x,y,w,h,9,false,C.edge2,.34)
  label(v and v.name or "選択アイテムの波形",x+15,y+10,w-30,23,12,C.text,true)
  right_label(v and string.format("%.2f s",v.len) or "WAVEFORM",x+w-15,y+11,8,C.faint,3,true)
  local progress=analysis_progress()
  if not v or not v.waveform then
    label(v and v.reason or "選択アイテムを自動解析しています",x+15,y+82,w-30,32,13,C.muted,false,5)
    if progress then local scan=x+15+(w-30)*progress; glow_line(scan,y+40,scan,y+h-28,C.accent2,.14) end
    return
  end
  local peak=.001; for _,p in ipairs(v.waveform) do peak=max(peak,p or 0) end
  local px,py,pw=x+15,y+48,w-30; local middle=py+48; line(px,middle,px+pw,middle,C.edge,.50)
  for col=0,floor(pw)-1 do
    local a=max(1,floor(col/pw*#v.waveform)+1); local b=min(#v.waveform,max(a,floor((col+1)/pw*#v.waveform)))
    local value=0; for i=a,b do value=max(value,v.waveform[i] or 0) end
    line(px+col,middle-value/peak*41,px+col,middle+value/peak*41,C.accent2,.60)
  end
  local p=v.plan; local m=v.metrics
  label(Core.modes[S.mode].name.."  "..fmt(p and p.current).." → "..fmt(p and p.predicted).."  /  Gain "..signed(p and p.gain).." dB",px,y+157,570,18,10,C.accent2,true)
  right_label("Peak "..fmt(m and m.peak).." → "..fmt(p and p.peakAfter).." dBFS",x+w-15,y+157,9,C.faint,3,true)
end
local function metric_card(title,value,x,y,w,accent)
  gradient(x,y,w,56,C.panel2,C.panel,.34,.82); line(x,y,x+w,y,C.edge2,.24); line(x,y+56,x+w,y+56,C.edge,.34); finish_corners(x,y,w,56,7,false,C.edge2,.26)
  label(title,x+11,y+8,w-22,16,9,C.muted,true); right_label(value,x+w-11,y+23,17,accent or C.text,3,true)
end

local rowsY,rowH,shown=425,26,9
local tableX,tableW=360,738
local function draw_table()
  local columns={{"#",368,34},{"アイテム",405,226},{"現在",635,68},{"目標",707,68},{"補正",779,62},{"Peak後",845,70},{"状態",919,164}}
  gradient(tableX,401,tableW,294,C.field,C.field,.98,.98); gradient(tableX,401,tableW,24,C.panel2,C.panel,.62,.88)
  line(tableX,401,tableX+tableW,401,C.edge2,.30); line(tableX,695,tableX+tableW,695,C.edge,.42); finish_corners(tableX,401,tableW,294,8,false,C.edge2,.28)
  for _,c in ipairs(columns) do label(c[1],c[2],405,c[3],16,9,C.muted,true) end
  A.offset=clamp(A.offset,0,max(0,#A.items-shown))
  for slot=1,shown do
    local i=A.offset+slot; local row=A.items[i]; local yy=rowsY+(slot-1)*rowH
    if row then
      local selected=(i==A.selected)
      if selected then
        if S.targetMode==2 then
          gradient(tableX,yy,tableW-14,rowH,C.accent3,C.panel2,.78,.28)
          rect(tableX,yy,4,rowH,C.accent2,.98)
          line(tableX+4,yy,tableX+tableW-18,yy,C.accent2,.58)
          line(tableX+4,yy+rowH-1,tableX+tableW-18,yy+rowH-1,C.edge2,.46)
        else
          gradient(tableX,yy,tableW-14,rowH,C.accent3,C.panel,.50,.20)
          rect(tableX,yy,2,rowH,C.accent2,.82)
        end
      elseif slot%2==0 then
        rect(tableX,yy,tableW-14,rowH,C.panel,.36)
      end
      local p=row.plan or {}; local reason=row.reason or p.reason
      local state=reason or p.reference and "指定基準" or p.changed and "NORMALIZE" or p.valid and "変更なし" or (A.job and i==A.job.index and "解析中") or "解析待ち"
      local vals={i,row.name,fmt(p.current),fmt(p.target),signed(p.gain),fmt(p.peakAfter),state}
      for ci,c in ipairs(columns) do
        local cc
        if reason then cc=C.warn
        elseif selected and S.targetMode==2 then cc=(ci==2 or ci==7) and C.text or C.focus2
        else cc=(ci>=3 and ci<=6 and C.accent2 or C.muted) end
        label(vals[ci],c[2],yy+3,c[3],18,10,cc,ci==5 or (selected and S.targetMode==2),nil,nil,ci==2)
      end
      register("row"..i,tableX,yy,tableW-14,rowH,function()
        if commit() then
          A.selected=i
          if S.targetMode==2 then A.dirty=true; replan(A.job~=nil) end
        end
      end,"任意ファイルモードでは、この行をReferenceとして使用します。",true)
    end
  end
  local bh=shown*rowH; local th=max(22,bh*min(1,shown/max(1,#A.items))); local ty=rowsY+(#A.items>shown and A.offset/(#A.items-shown)*(bh-th) or 0)
  rect(tableX+tableW-14,rowsY,14,bh,C.panel); rect(tableX+tableW-10,ty,6,th,C.edge2,.62); A.bar={x=tableX+tableW-14,y=rowsY,h=bh,thumb=th,top=ty}
  label(string.format("表示 %d–%d / %d",#A.items>0 and A.offset+1 or 0,min(#A.items,A.offset+shown),#A.items),tableX+4,670,280,18,9,C.faint,false)
end

local function primary_button(id,text,x,y,w,h,fn,hint,enabled,progress)
 enabled=enabled~=false
 PrimaryButton.draw(PrimaryButton.painter,x,y,w,h,text,A.applyWhenReady and 'WAITING / CANCEL' or 'NORMALIZE',enabled,A.applyWhenReady==true,nil,inside(x,y,w,h),pressed==id and (gfx.mouse_cap&1)~=0,R.time_precise(),BLT.host.active())
 register(id,x,y,w,h,fn,hint,enabled)
end

local function set_mode(i)
  if not commit() then return end
  S.mode=i; save_settings(); A.dirty=true; replan(A.job~=nil)
end
local function set_target_mode(i)
  if not commit() then return end
  S.targetMode=i; save_settings(); A.dirty=true; replan(A.job~=nil)
end

local function draw()
  local contentH=max(1,gfx.h-Chrome.titleH); scale=max(.32,min(gfx.w/W,contentH/H)); ox,oy=(gfx.w-W*scale)/2,Chrome.titleH+(contentH-H*scale)/2-22*scale; BLT.viewport(scale,gfx.ext_retina or 1); mx,my=(gfx.mouse_x-ox)/scale,(gfx.mouse_y-oy)/scale
  widgets={}; hover_hint=""; gfx.clear=-1;gfx.set(C.bg[1],C.bg[2],C.bg[3],1);gfx.rect(0,0,gfx.w,gfx.h,1)
  local now=R.time_precise(); particle_dt=max(0,min(.1,now-frame_clock)); frame_clock=now; frame_dt=animations_active and particle_dt*animation_speed or 0; anim_time=anim_time+frame_dt
  draw_background()
  BLT.title('SIMPLE NORMALIZER','SIMPLE NORMALIZER  シンプルなノーマライザー',W)
  BLT.drawIcon()

  local ref=A.items[A.selected]; local v=A.items[A.selected]; local mode=Core.modes[S.mode]
  gradient(360,96,738,24,C.panel2,C.panel,.38,.10); line(360,96,1098,96,C.edge2,.24); line(360,120,1098,120,C.edge,.30)
  label(S.targetMode==2 and "任意ファイル" or "TARGET",372,100,100,16,7.5,S.targetMode==2 and C.accent2 or C.faint,true,0,3)
  if S.targetMode==2 then label(ref and ref.name or "リストから指定",478,99,398,18,10,C.focus2,true,nil,nil,ref~=nil)
  else label(string.format("%s   %.1f %s",mode.name,target_value(),mode.unit),478,99,398,18,10,C.accent2,true) end
  right_label(v and string.format("ITEM %02d",A.selected) or "",1087,100,7.5,C.faint,3,true)

  gradient(22,112,318,585,C.panel2,C.panel,.30,.70); line(22,112,340,112,C.edge2,.32); line(22,697,340,697,C.edge,.38); finish_corners(22,112,318,585,9,false,C.edge2,.30)
  label("NORMALIZE METHOD",34,124,190,18,9,C.accent2,true,0,3)
  for row,i in ipairs(Core.mode_order) do
    local m=Core.modes[i]
    local yy=149+(row-1)*30
    segment_button("mode"..i,m.name,34,yy,294,26,S.mode==i,function() set_mode(i) end,m.desc,true)
    right_label(m.code,316,yy+5,7,S.mode==i and C.accent2 or C.faint,3,true)
  end
  label(mode.desc,35,459,290,38,9.0,C.muted,false)

  section_title("TARGET",35,505,326)
  segment_button("target_abs","数値指定",35,527,137,35,S.targetMode==1,function() set_target_mode(1) end,"指定した値へ揃えます。",true)
  segment_button("target_ref","任意ファイル",181,527,146,35,S.targetMode==2,function() set_target_mode(2) end,"右側のリストで選んだファイルを基準にします。",true)
  number_field("target","目標値",unit(),35,572,292,S.targetMode==1)
  label(S.targetMode==2 and "右のリストでReferenceにするファイルを選択します。" or "選択した方式の目標値です。",35,610,290,22,8.5,S.targetMode==2 and C.quiet or C.faint,false)

  waveform(v)
  local p=v and v.plan or {}
  metric_card(mode.name,fmt(p and p.current).." "..mode.unit,360,335,174,C.text)
  metric_card(S.targetMode==2 and "任意ファイル" or "TARGET",fmt(p and p.target).." "..mode.unit,540,335,174,S.targetMode==2 and C.focus2 or C.text)
  metric_card("GAIN",signed(p and p.gain).." dB",720,335,174,C.accent2)
  metric_card("PEAK予測",fmt(p and p.peakAfter).." dBFS",900,335,198,C.accent2)
  draw_table()

  local msg=A.message
  local prog=A.job and analysis_progress() or nil
  local selectedNow=Core.audio_selection_count(R.EnumProjects(-1,""))
  local count=(#A.items>0) and eligible_count() or selectedNow
  local applyEnabled=A.applyWhenReady or (selectedNow>0 and (A.job~=nil or (A.changeCount or 0)>0 or #A.items==0 or A.needsAnalyze))

  local ax,aw=390,340
  label(string.format("対象  %d件",count),258,720,120,18,10.5,C.accent2,true,2,3)
  label(A.job and string.format(A.job.kind=="peak_fast" and "Peak取得  %d / %d" or "解析済み  %d / %d",A.analyzedCount or 0,#A.items) or "解析準備完了",258,739,120,16,8.5,C.muted,true,2,3)
  local applyText=A.applyWhenReady and "実行をキャンセル" or "ノーマライズを実行"
  local applyHint=A.applyWhenReady
    and "クリックすると、予約中のノーマライズ実行をキャンセルします。自動解析は継続します。"
    or "解析途中でも実行できます。押した時点の対象を固定し、未解析分を完了してからItem Volumeへ適用します。"
  primary_button("apply",applyText,ax,714,aw,48,request_apply,applyHint,applyEnabled,nil)
  label(A.applyWhenReady and "対象固定中 · 再クリックでキャンセル" or (A.job and "バックグラウンド解析中" or "実行後は選択を解除"),
    742,720,230,18,9,A.applyWhenReady and C.accent2 or C.faint,true)
  label(S.targetMode==2 and "Reference：リスト選択" or "目標値：数値指定",
    742,739,190,16,8.5,S.targetMode==2 and C.focus2 or C.muted,false)
  BLT.footer(msg,A.bad,W,H+22,'0.5.2',prog)
  custom_titlebar()
end

local function interact()
 if BLT.blocked() then downLast=(gfx.mouse_cap&1)~=0;pressed=nil;gfx.mouse_wheel=0;return end

  if Chrome.mouseActive then downLast=(gfx.mouse_cap&1)~=0;pressed=nil;A.scrollDrag=nil;A.fieldDrag=nil;return end
  local down=(gfx.mouse_cap&1)~=0;local hit=nil
  for i=#widgets,1,-1 do local w=widgets[i];if inside(w.x,w.y,w.w,w.h) then hit=w;break end end
  if down and not downLast then
    local b=A.bar
    if b and inside(b.x,b.y,14,b.h) then
      if my>=b.top and my<=b.top+b.thumb then A.scrollDrag=my-b.top else A.offset=clamp(A.offset+(my<b.top and -shown or shown),0,max(0,#A.items-shown)) end
      pressed=nil
    else
      pressed=hit and hit.id
      if hit and hit.field and hit.enabled and commit() then A.fieldDrag={key=hit.key,startY=my,startValue=hit.get(),moved=false,clipped=false} end
    end
  elseif down and A.scrollDrag then
    local b=A.bar;if b.h>b.thumb then A.offset=floor(clamp((my-b.y-A.scrollDrag)/(b.h-b.thumb),0,1)*max(0,#A.items-shown)+.5) end
  elseif down and A.fieldDrag then
    A.update_field_drag(my,(gfx.mouse_cap&8)~=0)
  elseif not down and downLast then
    local wasFieldDrag=A.fieldDrag and A.fieldDrag.moved
    if not A.scrollDrag and not wasFieldDrag and hit and hit.id==pressed and hit.enabled then hit.fn() elseif not hit then commit() end
    A.scrollDrag=nil;A.fieldDrag=nil;pressed=nil
  end
  downLast=down
  if gfx.mouse_wheel~=0 then
    local wheel=gfx.mouse_wheel
    if hit and hit.field and hit.enabled then
      if not E or commit() then
        local steps=max(1,floor(abs(wheel)/120+.5));local dir=wheel>0 and 1 or -1
        A.apply_field(hit.key,hit.get()+dir*.1*steps,true)
      end
    elseif inside(tableX,401,tableW,294) then
      A.offset=clamp(A.offset+(wheel>0 and -3 or 3),0,max(0,#A.items-shown))
    end
    gfx.mouse_wheel=0
  end
end
local function key(k)
  k=BLT.key(k);if k==0 then return end
  if E then
    if k==13 then commit()
    elseif k==27 then E=nil; status("入力を取り消しました。")
    elseif k==1 then E.all=true
    elseif k==8 or k==6579564 then if E.all then E.text="" else E.text=E.text:sub(1,-2) end; E.all=false
    elseif k>=32 and k<=126 then local c=string.char(k); if c:match("[%d%.%-+]") and #E.text<16 then E.text=E.all and c or E.text..c; E.all=false end end
  else
    if k==27 then A.closing=true end
  end
end

local function close()
 -- Teardown errors must not leave a dead graphics window on screen.
 local ok,err=xpcall(function()
  if A.closed then return end
  Core.dispose(A.job and A.job.reader); save_settings(); clear_chrome_tooltip(); titlebar_cleanup()
  local _,x,y,w,h=gfx.dock(-1,0,0,0,0)
  if finite(x) and finite(y) then BLT.store(SECTION,"window_x",tostring(x),true); BLT.store(SECTION,"window_y",tostring(y),true) end
  BLT.store(SECTION,"window_w",tostring(gfx.w),true); BLT.store(SECTION,"window_h",tostring(gfx.h),true)
  A.closed=true; gfx.quit()
 end,debug.traceback)
 if not ok then
  A.closed=true
  pcall(gfx.quit)
  if R.TrackCtl_SetToolTip then pcall(R.TrackCtl_SetToolTip,'',0,0,true) end
  BLT.logError(err)
 end
end

function BLT.normalizerDefaults() local t={mode=1,targetMode=1,targets={}};for i,m in ipairs(Core.modes) do t.targets[i]=m.default end;return t end
function BLT.pick(obj,keys) local v=BLT.valueView or {};BLT.valueView=v;for k in pairs(keys) do v[k]=obj[k] end;return v end
PrimaryButton.painter={C=C,gradient=gradient,line=line,rect=rect,corners=finish_corners,disc=disc,label=function(text,x,y,size,c,kind,w,h,flags,bold) label(text,x,y,w,h,size,c,bold,flags,kind) end}
PrimaryButton.painter.motion=function(now) return (gfx.mouse_x-ox)/scale,(gfx.mouse_y-oy)/scale,visual_speed(now) end
PrimaryButton.wake=function() redraw_dirty=true;A.content_dirty=true;next_draw_time=0 end
BLT.attach({
 R=R,C=C,Chrome=Chrome,Chameleon=Chameleon,section=SECTION,faces=fonts,font=font,
 geometry=function() return scale,ox,oy end,active=function() local f=gfx.getchar(65536);return (f&1)==0 or (f&2)~=0 end,
 wake=function() A.content_dirty=true;redraw_dirty=true;next_draw_time=0;wake_visuals() end,
 defaults=BLT.normalizerDefaults(),capture=function() return S end,
 valid=function(v) if v.mode%1~=0 or not Core.modes[v.mode] or (v.targetMode~=1 and v.targetMode~=2) or #v.targets~=#Core.modes then return false end;for _,x in ipairs(v.targets) do if x < -80 or x>6 then return false end end;return true end,apply=function(v) for k,x in pairs(v) do S[k]=x end;save_settings();replan(false) end,
 undoBefore=function() cancel_auto(nil);A.selectionSig=nil;A.watchAt=0 end,undoRefresh=function() A.selectionSig=nil;A.watchAt=0 end,
 busy=function() return A.executionLocked or A.applyWhenReady end,commit=function() return commit() end,
 cancelEdit=function() E=nil;A.fieldDrag=nil end,editing=function() return E~=nil end,
 modal=function() return false end,
 handle=gfx_window_handle,resizeHit=function(x,y) if y<26 and x>=gfx.w-234 then return nil end;return chrome_resize_hit(x,y) end,
 cursor=set_resize_cursor,beginResize=begin_window_resize,resize=update_window_resize,

})
if ...=='blt_test' then function BLT.testDraw(now) draw(now or R.time_precise()) end end
function BLT.drawIcon()

 local bs,bx,by=scale,ox,oy;ox,oy=ox+(W-102)*scale,oy+31*scale;scale=scale*.78
 balance_icon(0,0)

 scale,ox,oy=bs,bx,by
end

if ...=='blt_test' then return {BLT=BLT,A=A,Core=Core,S=S} end
local chrome_ok,chrome_err=titlebar_api_ready()
if not chrome_ok then Language.mb(BLT.publicError(chrome_err),"Simple Normalizer | エラー",0); return end
local ww=clamp(floor(extnum("window_w",W)+.5),560,3000); local wh=clamp(floor(extnum("window_h",H+Chrome.titleH)+.5),415+Chrome.titleH,2200+Chrome.titleH)
local wx,wy=extnum("window_x",0/0),extnum("window_y",0/0)
-- Match native window/input coordinates in logical points on Mac.
gfx.ext_retina=BLT_MAC and 0 or 1
if finite(wx) and finite(wy) then gfx.init(Chrome.windowTitle,ww,wh,0,wx,wy)
else gfx.init(Chrome.windowTitle,ww,wh,0) end
if not apply_custom_window_style(ww,wh) then gfx.quit(); Language.mb("カスタムタイトルバーを初期化できません。","Simple Normalizer | エラー",0); return end
if Chameleon.enabled then Chameleon.refresh(true) end

local function loop()
 BLT.tick(R.time_precise());PrimaryButton.tick(R.time_precise(),BLT.host.active(),PrimaryButton.wake)

  local k=BLT.key(gfx.getchar()); if k<0 or A.closing then close(); return end
  local now=R.time_precise()
  Chameleon.tick(now)
  local flags=gfx.getchar(65537)
  local window_active=((flags & 1)==0) or ((flags & 2)~=0)
  if last_window_active==nil or window_active~=last_window_active then last_window_active=window_active; wake_visuals(now) end

  local key_activity=false; local n=0
  while k>0 and n<32 do key_activity=true; key(k); k=gfx.getchar(); n=n+1 end
  if key_activity then wake_visuals(now) end

  local before_project=A.project; local before_sig=A.selectionSig; local before_pending=A.pendingSig; local before_job=A.job
  auto_watch()
  if A.project~=before_project or A.selectionSig~=before_sig or A.pendingSig~=before_pending or A.job~=before_job then redraw_dirty=true end
  local work_active=A.job~=nil
  if A.job then advance() end
  if work_active~=(A.job~=nil) then redraw_dirty=true end
  work_active=A.job~=nil

  local raw_x,raw_y,raw_cap=gfx.mouse_x,gfx.mouse_y,gfx.mouse_cap
  local raw_wheel=gfx.mouse_wheel or 0

  local cap_changed=raw_cap~=last_raw_mouse_cap
  local wheel_activity=raw_wheel~=0
  local pointer_activity=raw_x~=last_raw_mouse_x or raw_y~=last_raw_mouse_y or cap_changed or wheel_activity
  if pointer_activity then wake_visuals(now) end
  -- Button/wheel transitions are input events, not decoration. Render them on
  -- the current defer pass so short clicks cannot fall between capped frames.
  if cap_changed or wheel_activity then next_draw_time=now end
  last_raw_mouse_x,last_raw_mouse_y,last_raw_mouse_cap=raw_x,raw_y,raw_cap
  if gfx.w~=last_window_w or gfx.h~=last_window_h then last_window_w,last_window_h=gfx.w,gfx.h; wake_visuals(now) end

  local dragging=A.scrollDrag~=nil or A.fieldDrag~=nil or Chrome.drag~=nil or Chrome.resize~=nil or ((raw_cap or 0)&1)~=0
  if dragging then wake_visuals(now) end
  animation_speed=work_active and 1 or visual_speed(now)
  animations_active=window_active and animation_speed>0
  local particle_tail=#icon_particles>0
  local frame_interval
  if dragging then frame_interval=1/60
  elseif work_active then frame_interval=1/30
  elseif animations_active then frame_interval=1/(8+22*animation_speed)
  elseif particle_tail then frame_interval=1/20 end
  if frame_interval and next_draw_time==math.huge then next_draw_time=now end
  local frame_due=frame_interval and now>=next_draw_time or (not frame_interval and (redraw_dirty))
  if frame_due then
    draw(); interact(); gfx.update(); redraw_dirty=false
    next_draw_time=frame_interval and now+frame_interval or math.huge

    if Chrome.requestReset then Chrome.requestReset=false; reset_window_size(); wake_visuals(now) end
    if Chrome.requestClose then Chrome.requestClose=false; A.closing=true end
  end
  if pointer_activity or key_activity or dragging then redraw_dirty=true end
  R.defer(loop)
end
R.atexit(close)
loop()
