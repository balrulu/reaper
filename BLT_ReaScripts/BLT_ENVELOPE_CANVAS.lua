-- @description ENVELOPE CANVAS
-- @version 0.5.10
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
 ["BLTフィルターのReaEQを確認できません。"]="Cannot identify the managed ReaEQ.",
 ["ReaEQの周波数範囲を取得できません。"]="Cannot read the ReaEQ frequency range.",
 ["BLTフィルターが重複しています。FXチェーンを確認してください。"]="Duplicate BLT filters. Check the FX chain.",
 ["ReaEQ (Cockos) を追加できません。"]="Cannot add ReaEQ (Cockos).",
 ["ReaEQの初期状態を設定できません。"]="Cannot initialize ReaEQ.",
 ["ReaEQのバンドを設定できません。"]="Cannot configure ReaEQ bands.",
 ["ReaEQのチャンネルを設定できません。"]="Cannot configure ReaEQ channels.",
 ["ReaEQの識別情報を保存できません。"]="Cannot store the ReaEQ identity.",
 ["旧BLTフィルターを置換できません。"]="Cannot replace the old BLT filter.",
 ["ReaEQの周波数を設定できません。"]="Cannot set the ReaEQ frequency.",
 [" ReaEQの周波数範囲に収めました。"]=" Clamped to the ReaEQ frequency range.",

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
 ["時間カーブが複雑すぎます。点を減らしてから適用してください。"]="Time curve too complex. Reduce points before applying.",
 ["対象の復元データを取得できません。"]="Cannot capture target restore data.",
 ["エンベロープを作成できません。"]="Cannot create envelope.",
 ["エンベロープを有効化できません。"]="Cannot enable envelope.",
 ["カーブが複雑すぎます。点を減らしてから適用してください。"]="Curve too complex. Reduce points before applying.",
 ["音量カーブが複雑すぎます。点を減らしてください。"]="Volume curve too complex. Reduce points.",
 ["専用フィルターの同名ファイルに異なる内容があります："]="Different filter content exists at: ",
 ["専用フィルターを保存できません："]="Cannot save dedicated filter: ",
 ["専用フィルターの保存に失敗しました："]="Failed to save dedicated filter: ",
 ["HPの有効状態を設定できません。"]="Cannot set HP enabled state.",
 ["LPの有効状態を設定できません。"]="Cannot set LP enabled state.",
 ["フィルターのカーブを作成できません。"]="Cannot create filter curves.",
 ["対象のテイクが変更されています。再読み込みしてください。"]="Target take changed. Reload it.",
 ["反転・セクション素材：グルー後に尺連動・速度カーブを適用してください。"]="Reversed/section source: glue before applying linked pitch/rate curves.",
 ["アイテムのロックを解除してから適用してください。"]="Unlock the item before applying.",
 ["全テイク同時再生をOFFにしてから適用してください。"]="Disable Play all takes before applying.",
 ["時間マーカーを置き換えられません。"]="Cannot replace time markers.",
 ["尺を変更できません。"]="Cannot change duration.",
 ["再生速度を変更できません。"]="Cannot change playback rate.",
 ["時間カーブを書き込めません。"]="Cannot write time curve.",
 ["\n復元に失敗しました。REAPERのUndoで戻してください。"]="\nRestore failed. Use REAPER Undo.",
 ["対象のテイクが変更されています。"]="Target take changed.",
 ["対象に外部変更があります。REAPERのUndoで確認してください。"]="Target was changed externally. Check REAPER Undo.",
 ["生成前の状態へ戻せません。"]="Cannot restore the state before generation.",
 ["生成元の音声を取得できません。"]="Cannot read source audio.",
 [" / 復元失敗：REAPERのUndoを使用してください。"]=" / Restore failed: use REAPER Undo.",
 ["CHAMELEON  REAPERテーマに擬態"]="CHAMELEON  REAPER theme",
 ["CHAMELEON  オリジナル配色"]="CHAMELEON  Original colors",
 ["カスタムタイトルバーには js_ReaScriptAPI が必要です。\nReaPack から js_ReaScriptAPI をインストールしてください。"]="The app bar requires js_ReaScriptAPI.\nInstall js_ReaScriptAPI via ReaPack.",
 ["ピッチ"]="Pitch",
 ["尺を保持"]="Keep length",
 ["ピッチ · 尺連動"]="Pitch · Rate",
 ["音程と尺を連動"]="Link pitch and length",
 ["再生速度"]="Rate",
 ["音程を保持"]="Keep pitch",
 ["ボリューム"]="Volume",
 ["ゲインを描画"]="Draw gain",
 ["ローパス"]="Low-pass",
 ["カットオフ · 中高域重視"]="Cutoff · Mid/high focus",
 ["ハイパス"]="High-pass",
 ["サイン波"]="Sine",
 ["ノコギリ波"]="Saw",
 ["矩形波"]="Square",
 ["三角波"]="Triangle",
 ["水平線"]="Flat",
 ["ランダムステップ"]="Random Step",
 ["周期：一定"]="Constant",
 ["アッチェレランド"]="Accelerando",
 ["リタルダンド"]="Ritardando",
 ["振幅：一定"]="Constant",
 ["クレッシェンド"]="Crescendo",
 ["デクレッシェンド"]="Decrescendo",
 ["左：直線 ／ 中央：従来の滑らかさ ／ 右：強いカーブ"]="Left: linear / Center: standard smoothing / Right: strong curve",
 ["現在のカーブをランダム生成しました。"]="Current curve randomized.",
 ["現在のカーブにラインを生成しました。"]="Line generated on current curve.",
 ["HP／LPリンク ON：次の編集から帯域幅を連動します。"]="HP/LP link ON: bandwidth follows future edits.",
 ["HP／LPリンク OFF：個別に編集できます。"]="HP/LP link OFF: edit independently.",
 ["帯域幅 / oct"]="Bandwidth / oct",
 ["波形を取得できません。音声ファイルがオンラインか確認してください。"]="Cannot read waveform. Check that the audio file is online.",
 ["音声の読み出しに失敗しました。"]="Audio read failed.",
 ["音声アイテムを選択すると自動で読み込みます。"]="Select an audio item to load it automatically.",
 ["音声アイテムを選択してください。"]="Select audio items.",
 ["対象のプロジェクトタブに戻ってください。"]="Return to the target project tab.",
 ["対象が削除されたか、テイクが変わっています。再読み込みしてください。"]="Target deleted or take changed. Reload it.",
 ["生成は再生・録音を停止してから行ってください。"]="Stop playback/recording before generating.",
 ["対象の音声アイテムを確認してください。"]="Check the target audio item.",
 ["カーブを読み込みました。一部の値は編集範囲の上限・下限に収めています。"]="Curves loaded. Some values were clamped to the editing range.",
 ["ピッチ・ボリューム・専用HP／LPを読み込みました。既存の速度設定は保持します。"]="Pitch, volume and dedicated HP/LP loaded. Existing rate settings retained.",
 ["生成済みのカーブを読み込みました。"]="Generated curves loaded.",
 ["波形の読み込み完了を待ってください。"]="Wait for waveform loading.",
 ["カーブを描いてから適用してください。"]="Draw a curve before applying.",
 ["適用条件を確認してください。"]="Check the conditions for applying.",
 ["生成完了：時間 %d点 / エンベロープ %d点%s。"]="Done: %d time points / %d envelope points%s.",
 ["（上限に合わせて近似）"]=" (approximated to point limit)",
 ["生成を更新"]="Update",
 ["カーブを生成"]="Generate",
 ["WAVEFORM CURVE DRAWING  波形へのカーブ描画ツール"]="WAVEFORM CURVE DRAWING  Draw curves on audio",
 ["ズーム率リセット"]="Reset zoom",
 ["補完処理"]="INTERPOLATION",
 ["直線"]="Linear",
 ["滑らか"]="Smooth",
 ["操作モード"]="EDIT MODE",
 ["範囲選択"]="Select",
 ["ペン"]="Pen",
 ["ライン生成"]="Generate line",
 ["方向："]="Direction: ",
 ["左"]="Left",
 ["両側"]="Both",
 ["右"]="Right",
 ["周期幅"]="Period",
 ["最大高さ"]="Max. height",
 ["Alt：位相反転"]="Alt: invert phase",
 ["波形の既存カーブ取得"]="Read existing curve",
 ["ランダム生成"]="Randomize",
 ["戻す"]="Undo",
 ["やり直す"]="Redo",
 ["現在のカーブを消去"]="Clear current curve",
 ["全カーブを消去"]="Clear all curves",
 ["EDITED / 生成で更新"]="EDITED / Generate to update",
 ["GENERATED / FX前の概形"]="GENERATED / Pre-FX outline",
 ["ドラッグ：範囲選択  ·  辺／角：変形  ·  枠内：移動  ·  Delete／枠内右クリック：削除"]="Drag: select · Edges/corners: reshape · Inside: move · Delete/right-click inside: delete",
 ["波形上をクリック：カーソル位置からライン生成"]="Click waveform: generate line from cursor",
 ["ドラッグ：描画／点移動  ·  Shift：直線  ·  Alt：点をつかまず描画  ·  右クリック：点削除"]="Drag: draw/move points · Shift: line · Alt: draw without grabbing points · Right-click: delete point",
 ["ホイール：ズーム  /  Shift＋ホイール：横移動"]="Wheel: zoom / Shift+wheel: pan",
 ["512点以上：処理が重くなる可能性があります"]="512+ points may increase processing load",
 ["波形を読み込み中  %d%%"]="Loading waveform %d%%",
 ["生成ポイント数上限（カーブ毎）"]="Point limit per curve",
 ["%d 点"]="%d pts",
 ["Envelope Canvas | 必要な拡張"]="Envelope Canvas | Required extension",
 ["カスタムアプリバーを初期化できません。"]="Cannot initialize the app bar.",
 ["表示言語を切替（JP / EN）"]="Switch language (JP / EN)",
 ["プリセットを読み込みました: ファクトリーデフォルト"]="Loaded: Factory Default",
 ["選択中のトラック / バスを指定"]="Use selected track / bus",
 ["方向：左"]="Direction: Left",
 ["方向：両側"]="Direction: Both",
 ["方向：右"]="Direction: Right",
},patterns={
 {"^「(.*)」を上書きしますか？$","Overwrite \"%s\"?"},
 {"^([%+%-]?[%d%.eE]+)–([%+%-]?[%d%.eE]+) / ([%+%-]?[%d%.eE]+)   スクロールで選択$","%d–%d / %d   Scroll to browse"},
 {"^解析中%.%.%.([%+%-]?[%d%.eE]+)%%$","Analyzing...%d%%"},
 {"^生成完了：時間 ([%+%-]?[%d%.eE]+)点 / エンベロープ ([%+%-]?[%d%.eE]+)点(.-)。$","Done: %d time points / %d envelope points%s.",{3}},
 {"^波形を読み込み中  ([%+%-]?[%d%.eE]+)%%$","Loading waveform %d%%"},
 {"^([%+%-]?[%d%.eE]+) 点$","%d pts"},
 {"^「(.-)」を上書きしますか？$","\"%s\"?"},
 {"^(.-)」を上書きしますか？$","%s\"?"},
 {"^プリセットを保存しました: (.-)$","Saved: %s"},
 {"^プリセットを読み込みました: (.-)$","Loaded: %s"},
 {"^(.-)個インポートしました。$","%s preset(s) imported."},
 {"^現在: (.-)(.-)$","Current: %s%s"},
 {"^(.-)エンベロープを作成できません。$","%sCannot create envelope."},
 {"^専用フィルターの同名ファイルに異なる内容があります：(.-)$","Different filter content exists at: %s"},
 {"^専用フィルターを保存できません：(.-)$","Cannot save dedicated filter: %s"},
 {"^専用フィルターの保存に失敗しました：(.-)$","Failed to save dedicated filter: %s"},
 {"^(.-)\n復元に失敗しました。REAPERのUndoで戻してください。$","%s\nRestore failed. Use REAPER Undo."},
 {"^(.-) / 復元失敗：REAPERのUndoを使用してください。$","%s / Restore failed: use REAPER Undo."},
 {"^方向：(.-)$","Direction: %s"},
 {"^「(.*)」を上書きしますか？$","Overwrite \"%s\"?"},
 {"^(%d+)個インポートしました。$","Imported %s preset(s)."},
 {"^(%d+)件をノーマライズしました。選択を解除しました。$","Normalized %s items and deselected them."},
},prefixes={"専用フィルターの同名ファイルに異なる内容があります：","専用フィルターの保存に失敗しました：","専用フィルターを保存できません：","プリセットを読み込みました: ","プリセットを保存しました: ","現在: ","方向："}}

local Language=create_language(reaper,"BLT_CURVE_CANVAS",LanguageCatalog)
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

local Core={VERSION='0.5.10',SECTION='BLT_CURVE_CANVAS',MAX_POINTS=1024}
local min,max,abs,floor,ceil=math.min,math.max,math.abs,math.floor,math.ceil
local function clamp(v,a,b) return max(a,min(b,v)) end
local function finite(v) return type(v)=='number' and v==v and abs(v)<math.huge end
function Core.copy(t)
 if type(t)~='table' then return t end
 local out={};for k,v in pairs(t) do out[k]=Core.copy(v) end;return out
end
Core.FILTER_MAX_VALUE=2*math.log(1200)/math.log(4800)-1
function Core.new_layers()
 local t={};for _,key in ipairs({'pitch','tape','speed','volume'}) do t[key]={points={{x=0,y=0},{x=1,y=0}},kind='linear',enabled=true,
  min_y=key=='pitch' and -2 or -1,max_y=(key=='pitch' or key=='volume') and 2 or 1} end
 for _,key in ipairs({'highpass','lowpass'}) do local y=key=='highpass' and -1 or Core.FILTER_MAX_VALUE
  t[key]={points={{x=0,y=y},{x=1,y=y}},kind='linear',enabled=false,filter=true,min_y=-1,max_y=Core.FILTER_MAX_VALUE,neutral=y}
 end;return t
end
function Core.frequency(y) return min(24000,20*4800^((clamp(y,-1,Core.FILTER_MAX_VALUE)+1)/2)) end
function Core.smoothness(c)
 if c.kind~='smooth' then return 0 end
 return finite(c.smoothness) and clamp(c.smoothness,0,2) or 1
end
-- Frequency drawings interpolate in the same offset-log coordinates as the graph.
Core.FILTER_AXIS_OFFSET=85
function Core.filter_axis(y)
 local hz=20*4800^((y+1)/2)
 return math.log((hz+Core.FILTER_AXIS_OFFSET)/(20+Core.FILTER_AXIS_OFFSET))
end
function Core.filter_value(axis)
 local hz=(20+Core.FILTER_AXIS_OFFSET)*math.exp(axis)-Core.FILTER_AXIS_OFFSET
 return 2*math.log(max(20,hz)/20)/math.log(4800)-1
end
function Core.interpolate(c,x)
 local p=c.points;if #p==0 then return 0 end
 local function value(i) return c.filter and Core.filter_axis(p[i].y) or p[i].y end
 if x<=p[1].x then return value(1) elseif x>=p[#p].x then return value(#p) end
 local lo,hi=1,#p
 while hi-lo>1 do local m=floor((lo+hi)/2);if p[m].x<=x then lo=m else hi=m end end
 local a,b=p[lo],p[hi];local h=b.x-a.x;local u=(x-a.x)/h
 local ay,by=value(lo),value(hi)
 local linear=ay+(by-ay)*u;local amount=Core.smoothness(c)
 if amount==0 then return linear end
 -- Shape-preserving cubic Hermite interpolation. No overshoot beyond node values.
 local d=(by-ay)/h
 local function tangent(i)
  if i==1 then return (value(2)-value(1))/(p[2].x-p[1].x) end
  if i==#p then return (value(i)-value(i-1))/(p[i].x-p[i-1].x) end
  local h0,h1=p[i].x-p[i-1].x,p[i+1].x-p[i].x
  local d0,d1=(value(i)-value(i-1))/h0,(value(i+1)-value(i))/h1
  if d0*d1<=0 then return 0 end
  local w0,w1=2*h1+h0,h1+2*h0
  return (w0+w1)/(w0/d0+w1/d1)
 end
 if abs(d)<1e-12 then return ay end
 local m0,m1=tangent(lo),tangent(hi)
 local aa,bb=m0/d,m1/d;local r=aa*aa+bb*bb
 if r>9 then local s=3/math.sqrt(r);m0=s*aa*d;m1=s*bb*d end
 local curved=clamp((2*u^3-3*u*u+1)*ay+(u^3-2*u*u+u)*h*m0+(-2*u^3+3*u*u)*by+(u^3-u*u)*h*m1,min(ay,by),max(ay,by))
 if amount<=1 then return linear+(curved-linear)*amount end
 -- Beyond the original interpolation, ease into flatter endpoints and a steeper middle.
 local eased=ay+(by-ay)*(u*u*u*(10+u*(-15+6*u)))
 return curved+(eased-curved)*(amount-1)
end
function Core.value(c,x)
 if c.link_source then
  return clamp(Core.value(c.link_source,x)+c.link_offset,c.min_y,c.max_y)
 end
 if #c.points==0 then return 0 end
 local value=Core.interpolate(c,x)
 return c.filter and Core.filter_value(value) or value
end
function Core.at(layers,key,x)
 local c=layers[key];if not c or not c.enabled then return 0 end;return Core.value(c,clamp(x,0,1))
end
function Core.db(y) return y>=0 and y*12 or y*60 end
function Core.changed(c)
 if not c.enabled then return false end
 if c.filter then return true end
 for _,p in ipairs(c.points) do if abs(p.y)>1e-7 then return true end end;return false
end
function Core.limit_points(points,limit)
 if not limit or #points<=limit then return points,false end
 limit=max(2,floor(limit));local keep={[1]=true,[#points]=true};local heap={}
 local function push(a,b)
  if b-a<2 then return end
  local worst,idx=-1,a+1;local p,q=points[a],points[b]
  for i=a+1,b-1 do local r=points[i];local f=(r.x-p.x)/max(1e-20,q.x-p.x)
   local e=abs(r.y-(p.y+(q.y-p.y)*f));if e>worst then worst,idx=e,i end
  end
  local entry={a=a,b=b,i=idx,e=worst};local n=#heap+1
  while n>1 and heap[floor(n/2)].e<entry.e do heap[n]=heap[floor(n/2)];n=floor(n/2) end;heap[n]=entry
 end
 local function pop()
  local top=heap[1];local last=table.remove(heap)
  if #heap>0 then local n=1
   while n*2<=#heap do local c=n*2;if c<#heap and heap[c+1].e>heap[c].e then c=c+1 end
    if heap[c].e<=last.e then break end;heap[n]=heap[c];n=c
   end;heap[n]=last
  end;return top
 end
 push(1,#points)
 for _=3,limit do if #heap==0 then break end;local p=pop();keep[p.i]=true;push(p.a,p.i);push(p.i,p.b) end
 local out={};for i,p in ipairs(points) do if keep[i] then out[#out+1]=p end end
 return out,true
end
function Core.any(layers) for _,c in pairs(layers) do if Core.changed(c) then return true end end;return false end
function Core.add(c,x,y)
 x,y=clamp(x,0,1),clamp(y,c.min_y or -1,c.max_y or 1)
 for i,p in ipairs(c.points) do
  if abs(x-p.x)<1e-6 then p.y=y;return i end
  if x<p.x then table.insert(c.points,i,{x=x,y=y});return i end
 end
 c.points[#c.points+1]={x=x,y=y};return #c.points
end
function Core.stroke(c,x0,y0,x1,y1)
 if x1<x0 then x0,x1,y0,y1=x1,x0,y1,y0 end
 local keep={};for _,p in ipairs(c.points) do if p.x<x0-1e-6 or p.x>x1+1e-6 then keep[#keep+1]=p end end
 c.points=keep;Core.add(c,x0,y0);Core.add(c,x1,y1)
end
function Core.chaos(limit)
 local n=math.random(8,min(128,limit));local exponent=.2+math.random()*4;local center=math.random()
 local pts={{x=0,y=math.random()*2-1},{x=1,y=math.random()*2-1}}
 for _=3,n do local x
  if math.random()<.55 then x=clamp(center+(math.random()-.5)*math.random(),.00001,.99999) else x=math.random()^exponent end
  pts[#pts+1]={x=clamp(x,.00001,.99999),y=(math.random()*2-1)*(math.random()<.3 and .15 or 1)}
 end
 table.sort(pts,function(a,b)return a.x<b.x end)
 for i=#pts,2,-1 do if pts[i].x-pts[i-1].x<1e-6 then table.remove(pts,i-1) end end
 return pts
end
function Core.compact_pattern(points)
 local c={points=points};Core.simplify(c,.0015);return c.points
end
function Core.pattern(kind,cycles,height,envelope,random_levels,tempo)
 if tempo and tempo~=1 then
  local points=Core.pattern(kind,cycles,height,1,random_levels)
  for _,p in ipairs(points) do
   local phase=p.x
   -- Invert integrated speed: 0.5 -> 1.5 (or 1.5 -> 0.5), mean 1.
   local x=tempo==2 and 2*phase/(.5+math.sqrt(.25+2*phase)) or 2*phase/(1.5+math.sqrt(2.25-2*phase))
   p.x=x;p.y=p.y*(envelope==2 and x or envelope==3 and 1-x or 1)
  end
  return points
 end
 if kind=='random_step' then
  local count=max(1,ceil(cycles-1e-12));local levels={}
  for i=1,count do
   local v=random_levels and random_levels[i]
   levels[i]=finite(v) and clamp(v,-1,1) or math.random()*2-1
  end
  local function value(i)
   local a=(i-1)/cycles;local b=min(i/cycles,1);local center=(a+b)/2
   local gain=envelope==2 and center or envelope==3 and 1-center or 1
   return levels[i]*height*gain
  end
  local out={{x=0,y=value(1)}}
  for i=1,count-1 do
   local x=i/cycles
   if x<1 then
    out[#out+1]={x=max(0,x-min(1e-5,.01/cycles)),y=value(i)}
    out[#out+1]={x=x,y=value(i+1)}
   end
  end
  out[#out+1]={x=1,y=value(count)}
  return Core.compact_pattern(out)
 end
 if kind=='horizontal' then return {{x=0,y=0},{x=1,y=0}} end
 -- Piecewise-linear waves need only extrema or the two sides of a jump.
 if kind=='triangle' or kind=='saw' or kind=='square' then
  local xs={0,1}
  if kind=='triangle' then
   for i=0,ceil(cycles*2) do local x=(.25+i*.5)/cycles;if x>0 and x<1 then xs[#xs+1]=x end end
  elseif kind=='square' then
   for i=1,floor(cycles*2) do local x=i/(cycles*2)
    if x<=1 then xs[#xs+1]=max(0,x-min(1e-5,.01/cycles));xs[#xs+1]=x end
   end
  else
   for i=0,ceil(cycles) do local x=(.5+i)/cycles
    if x>0 and x<=1 then xs[#xs+1]=max(0,x-min(1e-5,.01/cycles));xs[#xs+1]=x end
   end
  end
  table.sort(xs)
  local function value(x)
   local phase=(x*cycles+(kind=='saw' and .5 or kind=='triangle' and .25 or 0)+1e-12)%1
   local y=kind=='saw' and 2*phase-1 or kind=='square' and (phase<.5 and 1 or -1) or 1-4*abs(phase-.5)
   return y*height*(envelope==2 and x or envelope==3 and 1-x or 1)
  end
  -- Scale only the defining corners: envelope modes change vertex heights,
  -- never tessellate the spans between them into extra control points.
  local out={}
  for _,x in ipairs(xs) do
   if #out==0 or x-out[#out].x>1e-10 then out[#out+1]={x=x,y=value(x)} end
  end
  if #out>Core.MAX_POINTS then out=Core.limit_points(out,Core.MAX_POINTS) end
  return Core.compact_pattern(out)
 end
 local xs={};local n=min(768,max(1,ceil(cycles*48)))
 for i=0,n do xs[#xs+1]=i/n end
 if kind=='saw' or kind=='square' then
  local edges=cycles*(kind=='square' and 2 or 1);local total=floor(edges+(kind=='saw' and .5 or 0));local count=min(120,total)
  for j=1,count do local i=ceil(j*total/count);local x=(i-(kind=='saw' and .5 or 0))/edges
   if x<=1 then xs[#xs+1]=max(0,x-min(1e-5,.01/edges));xs[#xs+1]=x end
  end
 end
 table.sort(xs);local points={}
 for _,x in ipairs(xs) do
  if #points==0 or x-points[#points].x>1e-10 then
  local phase=(x*cycles+(kind=='saw' and .5 or kind=='triangle' and .25 or 0))%1;local y
  if kind=='sine' then y=math.sin(x*cycles*2*math.pi)
  elseif kind=='saw' then y=2*phase-1
  elseif kind=='square' then y=phase<.5 and 1 or -1
  elseif kind=='triangle' then y=1-4*abs(phase-.5)
  else y=math.random()*2-1 end
  local gain=envelope==2 and x or envelope==3 and 1-x or 1
  points[#points+1]={x=x,y=y*height*gain}
 end end;return Core.compact_pattern(points)
end
function Core.simplify(c,tolerance)
 local pts=c.points;if #pts<3 then return end
 local keep={[1]=true,[#pts]=true};local stack={{1,#pts}}
 while #stack>0 do
  local pair=table.remove(stack);local a,b=pair[1],pair[2];local worst,index=0,nil
  for i=a+1,b-1 do
   local u=(pts[i].x-pts[a].x)/max(1e-12,pts[b].x-pts[a].x)
   local e=abs(pts[i].y-(pts[a].y+(pts[b].y-pts[a].y)*u))
   if e>worst then worst,index=e,i end
  end
  if index and worst>tolerance then keep[index]=true;stack[#stack+1]={a,index};stack[#stack+1]={index,b} end
 end
 local out={};for i,p in ipairs(pts) do if keep[i] then out[#out+1]=p end end;c.points=out
end
function Core.constant(c)
 if not c.enabled then return 0 end
 if c.link_source and Core.constant(c.link_source)==nil then return nil end
 local y=c.points[1].y
 for _,p in ipairs(c.points) do if abs(p.y-y)>1e-10 then return nil end end
 return y
end
function Core.knots(layers,keys)
 local xs={0,1}
 for _,key in ipairs(keys) do local c=layers[key]
  if c.enabled then for _,p in ipairs(c.points) do xs[#xs+1]=p.x end end
 end
 table.sort(xs);local out={}
 for _,x in ipairs(xs) do if #out==0 or x-out[#out]>1e-10 then out[#out+1]=x end end
 return out
end
function Core.map(layers,len,limit)
 -- Curves are anchored to the ORIGINAL item timeline. Both timing layers compose
 -- multiplicatively; independent pitch is applied on the mapped output timeline.
 local timing=Core.changed(layers.tape) or Core.changed(layers.speed)
 local tape,speed=Core.constant(layers.tape),Core.constant(layers.speed)
 if tape and speed then
  local factor=2^(2*(tape+speed));local duration=len/factor
  return {{u=0,t=0},{u=1,t=duration}},duration,timing,factor
 end
 local unique=Core.knots(layers,{'tape','speed'})
 local variation=0
 for i=2,#unique do for _,key in ipairs({'tape','speed'}) do
  variation=variation+24*abs(Core.at(layers,key,unique[i])-Core.at(layers,key,unique[i-1]))
 end end
 local pitch_tolerance=limit and max(.05,variation/(limit*4)) or .05
 local time_tolerance=limit and max(.0001,len/(limit*16)) or .0001
 local m={{u=0,t=0}};local t=0
 local function inv(u) return 2^(-2*Core.at(layers,'tape',u)-2*Core.at(layers,'speed',u)) end
 local function integral(a,b,depth)
  local mid=(a+b)/2;local fa,fm,fb=inv(a),inv(mid),inv(b)
  local whole=(b-a)*(fa+4*fm+fb)/6
  local split=(b-a)*(fa+4*inv((a+mid)/2)+2*fm+4*inv((mid+b)/2)+fb)/12
  if depth<16 and abs(split-whole)>1e-8*(b-a) then return integral(a,mid,depth+1)+integral(mid,b,depth+1) end
  return len*(split+(split-whole)/15)
 end
 local function segment(a,b,depth)
  local mid=(a+b)/2;local f0,f1,f2,f3,f4=inv(a),inv((a+mid)/2),inv(mid),inv((mid+b)/2),inv(b)
  local left=len*(b-a)*(f0+4*f1+f2)/12
  local right=len*(b-a)*(f2+4*f3+f4)/12
  -- Bound local varispeed changes to 0.05 semitone and midpoint timing error
  -- to 0.1 ms. Flat regions need only their boundaries, regardless of duration.
  local span=12*math.log(max(f0,f1,f2,f3,f4)/min(f0,f1,f2,f3,f4),2)
  if span>pitch_tolerance or abs(left-right)/2>time_tolerance then
   if depth>=24 or #m>32768 then error('時間カーブが複雑すぎます。点を減らしてから適用してください。',0) end
   segment(a,mid,depth+1);segment(mid,b,depth+1)
  else t=t+(limit and integral(a,b,0) or left+right);m[#m+1]={u=b,t=t} end
 end
 for i=2,#unique do segment(unique[i-1],unique[i],0) end
 local reduced={points={}}
 for _,p in ipairs(m) do reduced.points[#reduced.points+1]={x=p.u,y=p.t} end
 Core.simplify(reduced,1e-12);m={}
 for _,p in ipairs(reduced.points) do m[#m+1]={u=p.x,t=p.y} end
 return m,t,timing
end
function Core.lookup(map,x,from,to)
 if x<=map[1][from] then return map[1][to] end
 if x>=map[#map][from] then return map[#map][to] end
 local a,b=1,#map;while b-a>1 do local j=floor((a+b)/2);if map[j][from]<=x then a=j else b=j end end
 local u=(x-map[a][from])/(map[b][from]-map[a][from]);return map[a][to]+(map[b][to]-map[a][to])*u
end
function Core.valid(project,item,take)
 return item and take and R.ValidatePtr2(project,item,'MediaItem*') and R.ValidatePtr2(project,take,'MediaItem_Take*') and R.GetActiveTake(item)==take
end
function Core.info(project,item)
 if not item or not R.ValidatePtr2(project,item,'MediaItem*') then return nil end
 local take=R.GetActiveTake(item);if not take or R.TakeIsMIDI(take) then return nil end
 local source=R.GetMediaItemTake_Source(take);if not source then return nil end
 local file=R.GetMediaSourceFileName(source,'');local len=R.GetMediaItemInfo_Value(item,'D_LENGTH')
 local rate=R.GetMediaItemTakeInfo_Value(take,'D_PLAYRATE');local channels=R.GetMediaSourceNumChannels(source)
 if not file or file=='' or not finite(len) or len<=0 or not finite(rate) or rate<=0 or channels<1 then return nil end
 local _,guid=R.GetSetMediaItemInfo_String(item,'GUID','',false)
 return {project=project,item=item,take=take,source=source,file=file,guid=guid,name=R.GetTakeName(take) or '',len=len,rate=rate,
  pos=R.GetMediaItemInfo_Value(item,'D_POSITION'),offset=R.GetMediaItemTakeInfo_Value(take,'D_STARTOFFS'),channels=channels}
end
function Core.first(project)
 for i=0,R.CountSelectedMediaItems(project)-1 do local v=Core.info(project,R.GetSelectedMediaItem(project,i));if v then return v end end
end
function Core.chunk(item)
 local ok,s=R.GetItemStateChunk(item,'',false);if not ok or not s or s=='' then error('対象の復元データを取得できません。',0) end;return s
end
function Core.signature(s)
 local out,stack={},{}
 for line in (s:gsub('\r\n','\n')..'\n'):gmatch('(.-)\n') do
  local token=line:match('^%s*(%S+)');local parent=stack[#stack]
  local ui_only=(parent=='ITEM' and token=='SEL') or
   (parent=='TAKEFX' and (token=='SHOW' or token=='LASTSEL' or token=='DOCKED' or token=='FLOATPOS'))
  if not ui_only then out[#out+1]=line end
  if token and token:sub(1,1)=='<' then stack[#stack+1]=token:sub(2)
  elseif token=='>' then stack[#stack]=nil end
 end
 return table.concat(out,'\n')
end
function Core.selected(project)
 local t={};for i=0,R.CountSelectedMediaItems(project)-1 do t[#t+1]=R.GetSelectedMediaItem(project,i) end;return t
end
function Core.restore_selection(project,items)
 R.SelectAllMediaItems(project,false);for _,item in ipairs(items) do if R.ValidatePtr2(project,item,'MediaItem*') then R.SetMediaItemSelected(item,true) end end
end
function Core.envelope(take,name)
 local env=R.GetTakeEnvelopeByName(take,name)
 if not env then return nil end
 local ok,s=R.GetEnvelopeStateChunk(env,'',false)
 if ok and s:match('\nACT%s+0') then return nil end
 return env
end
function Core.ensure_env(project,item,take,name,command)
 local env=R.GetTakeEnvelopeByName(take,name)
 if not env then R.SelectAllMediaItems(project,false);R.SetMediaItemSelected(item,true);R.Main_OnCommand(command,0);env=R.GetTakeEnvelopeByName(take,name) end
 if not env then error(name..'エンベロープを作成できません。',0) end
 local ok,s=R.GetEnvelopeStateChunk(env,'',false)
 if ok then assert(R.SetEnvelopeStateChunk(env,s:gsub('ACT%s+0','ACT 1',1),false),'エンベロープを有効化できません。') end
 return env
end
function Core.evaluate(env,t,default)
 if not env then return default end
 local _,v=R.Envelope_Evaluate(env,t,48000,1);return finite(v) and v or default
end
function Core.sample_curve(layers,keys,map,v,rate,env,fn,relative,limit)
 local xs=Core.knots(layers,keys)
 for _,p in ipairs(map) do xs[#xs+1]=p.u end
 if env then
  for i=0,R.CountEnvelopePoints(env)-1 do
   local ok,t=R.GetEnvelopePoint(env,i);local u=t/(v.len*v.rate)
   if ok and u>0 and u<1 then
    xs[#xs+1]=u
    -- Keep the left side of square/discontinuous existing envelope segments.
    xs[#xs+1]=max(0,u-1e-9)
   end
  end
 end
 table.sort(xs);local unique={}
 for _,x in ipairs(xs) do if #unique==0 or x-unique[#unique]>1e-12 then unique[#unique+1]=x end end
 local sample_depth=limit and max(1,floor(math.log(max(1,limit*8/#unique),2))) or 24
 local function sample(u) return {x=Core.lookup(map,u,'u','t')*rate,y=fn(u)} end
 local pts={sample(0)}
 local function segment(a,b,pa,pb,depth)
  local bad=false
  for _,q in ipairs({.25,.5,.75}) do
   local p=sample(a+(b-a)*q);local f=(p.x-pa.x)/max(1e-20,pb.x-pa.x)
   local predicted=pa.y+(pb.y-pa.y)*f
   local tolerance=type(relative)=='number' and relative or relative and max(1e-9,abs(p.y)*.0002) or .002
   if abs(predicted-p.y)>tolerance then bad=true;break end
  end
  if bad and depth<sample_depth then
   if depth>=24 or #pts>32768 then error('カーブが複雑すぎます。点を減らしてから適用してください。',0) end
   local mid=(a+b)/2;local pm=sample(mid)
   segment(a,mid,pa,pm,depth+1);segment(mid,b,pm,pb,depth+1)
  else pts[#pts+1]=pb end
 end
 for i=2,#unique do local a,b=unique[i-1],unique[i];segment(a,b,pts[#pts],sample(b),0) end
 -- Remove only numerically collinear points after adaptive sampling. This does
 -- not spend a second approximation budget or flatten retained sharp corners.
 local c={points=pts};Core.simplify(c,1e-10);return c.points
end
function Core.volume_points(points,mode,limit)
 -- A newly enabled volume envelope may use REAPER's fader scaling. Refine in
 -- that actual interpolation domain so sparse points do not change the gain.
 local out={{x=points[1].x,y=R.ScaleToEnvelopeMode(mode,points[1].y)}}
 local maxdepth=limit and max(1,floor(math.log(max(1,limit*8/#points),2))) or 24
 local function segment(a,b,depth)
  local va,vb=R.ScaleToEnvelopeMode(mode,a.y),R.ScaleToEnvelopeMode(mode,b.y)
  local bad=false
  for _,q in ipairs({.25,.5,.75}) do
   local target=a.y+(b.y-a.y)*q
   if abs(R.ScaleFromEnvelopeMode(mode,va+(vb-va)*q)-target)>max(1e-9,abs(target)*.0002) then bad=true;break end
  end
  if bad and depth<maxdepth then
   if depth>=24 or #out>32768 then error('音量カーブが複雑すぎます。点を減らしてください。',0) end
   local mid={x=(a.x+b.x)/2,y=(a.y+b.y)/2};segment(a,mid,depth+1);segment(mid,b,depth+1)
  else out[#out+1]={x=b.x,y=vb} end
 end
 for i=2,#points do segment(points[i-1],points[i],0) end
 return out
end
function Core.hide_take_fx(take,fx)
 if type(R.TakeFX_SetOpen)=='function' then pcall(R.TakeFX_SetOpen,take,fx,false) end
 if type(R.TakeFX_Show)=='function' then pcall(R.TakeFX_Show,take,fx,2);pcall(R.TakeFX_Show,take,fx,0) end
end
Core.FILTER_TAG='BLT Envelope Canvas HP / LP [ReaEQ]'
Core.FILTER_OWNER='P_EXT:BLT_EC_FILTER_GUIDS'
function Core.find_filters(take)
 local _,saved=R.GetSetMediaItemTakeInfo_String(take,Core.FILTER_OWNER,'',false)
 local owned={};for id in tostring(saved or ''):gmatch('[^|]+') do owned[id]=true end
 local found={}
 for fx=0,R.TakeFX_GetCount(take)-1 do
  local ok,id=R.TakeFX_GetNamedConfigParm(take,fx,'fx_ident')
  id=ok and tostring(id):gsub('\\','/'):lower():gsub('^js:%s*','') or ''
  local legacy=('/'..id):match('/blt/blt_envelope_canvas_filter%.jsfx$') or ('/'..id):match('/blt/blt_curve_canvas_filter%.jsfx$')
  local _,name=R.TakeFX_GetNamedConfigParm(take,fx,'renamed_name')
  local guid=R.TakeFX_GetFXGUID(take,fx)
  local ours=owned[guid] or name==Core.FILTER_TAG
  if legacy then found[#found+1]={fx=fx,legacy=true}
  elseif ours then
   local eq=R.TakeFX_GetNamedConfigParm(take,fx,'BANDTYPE0')
   assert(eq,'BLTフィルターのReaEQを確認できません。')
   found[#found+1]={fx=fx,guid=guid}
  end
 end
 return found
end
-- Calibrate against the installed ReaEQ; no parameter writes or file I/O.
-- The lookup is built only when applying/reading curves, never during drawing.
function Core.filter_mapping(take,fx,param)
 local values={}
 for i=0,512 do
  local ok,text=R.TakeFX_FormatParamValueNormalized(take,fx,param,i/512)
  local hz=ok and tonumber(tostring(text):match('[-+]?%d+%.?%d*'))
  if hz and tostring(text):lower():find('khz',1,true) then hz=hz*1000 end
  assert(finite(hz) and hz>=0 and (i==0 or hz>=values[i]),'ReaEQの周波数範囲を取得できません。')
  values[i+1]=hz
 end
 assert(values[513]>values[1],'ReaEQの周波数範囲を取得できません。')
 local function hz(n)
  local x=clamp(n,0,1)*512;local i=min(511,floor(x));local f=x-i
  return values[i+1]+(values[i+2]-values[i+1])*f
 end
 local function normalized(freq)
  if freq<=values[1] then return 0 end;if freq>=values[513] then return 1 end
  local lo,hi=1,513
  while hi-lo>1 do local mid=floor((lo+hi)/2);if values[mid]<freq then lo=mid else hi=mid end end
  return ((lo-1)+(freq-values[lo])/(values[hi]-values[lo]))/512
 end
 return {hz=hz,normalized=normalized,low=values[1],high=values[513]}
end
-- ReaEQ can apply a named setting while returning false from the setter.
-- Verify the actual value instead of treating that return value as failure.
function Core.set_filter_band(take,fx,key,value)
 R.TakeFX_SetNamedConfigParm(take,fx,key,tostring(value))
 local ok,actual=R.TakeFX_GetNamedConfigParm(take,fx,key)
 assert(ok and tonumber(actual)==value,'ReaEQのバンドを設定できません。')
end
function Core.create_filter_eq(v,layers,existing)
 existing=existing or Core.find_filters(v.take)
 local legacy,managed={},{}
 for _,f in ipairs(existing) do if f.legacy then legacy[#legacy+1]=f else managed[#managed+1]=f end end
 -- A mixture or duplicate legacy insert has no unambiguous curve to replace.
 assert(#legacy<=1 and (#legacy==0 or #managed==0),'BLTフィルターが重複しています。FXチェーンを確認してください。')
 local channels=v.channels or 2
 local mode=R.GetMediaItemTakeInfo_Value(v.take,'I_CHANMODE')
 if mode>=2 then channels=mode>=67 and 2 or 1 end
 local count=math.ceil(min(64,channels)/2)
 local nch=R.GetMediaItemTakeInfo_Value(v.take,'I_TAKEFX_NCH')
 if count*2>nch then assert(R.SetMediaItemTakeInfo_Value(v.take,'I_TAKEFX_NCH',count*2),'ReaEQのチャンネルを設定できません。') end
 local result={}
 for i=1,count do
  local fx=managed[i] and managed[i].fx or R.TakeFX_AddByName(v.take,'ReaEQ (Cockos)',-1)
  assert(fx and fx>=0,'ReaEQ (Cockos) を追加できません。')
  Core.hide_take_fx(v.take,fx)
  -- Discard automation only on this tool's managed EQ before rebuilding it.
  for param=0,R.TakeFX_GetNumParams(v.take,fx)-1 do
   local env=R.TakeFX_GetEnvelope(v.take,fx,param,false)
   if env then R.DeleteEnvelopePointRange(env,-1e20,1e20);R.Envelope_SortPoints(env) end
   for _,kind in ipairs({'lfo','acs','plink'}) do
    R.TakeFX_SetNamedConfigParm(v.take,fx,'param.'..param..'.'..kind..'.active','0')
   end
  end
  assert(R.TakeFX_SetPresetByIndex(v.take,fx,-2),'ReaEQの初期状態を設定できません。')
  -- BANDTYPE uses ReaEQ's native enum, not TrackFX_GetEQParam's enum.
  Core.set_filter_band(v.take,fx,'BANDTYPE0',4)
  Core.set_filter_band(v.take,fx,'BANDTYPE1',3)
  -- Current ReaEQ defaults include a fifth band. Disable every unused band.
  for band=0,63 do
   local exists=R.TakeFX_GetNamedConfigParm(v.take,fx,'BANDTYPE'..band)
   if not exists then break end
   local enabled=(band==0 and layers.highpass.enabled) or (band==1 and layers.lowpass.enabled)
   Core.set_filter_band(v.take,fx,'BANDENABLED'..band,enabled and 1 or 0)
  end
  R.TakeFX_SetOffline(v.take,fx,false);R.TakeFX_SetEnabled(v.take,fx,true)
  for pin=0,1 do
   local channel=(i-1)*2+pin
   local low=channel<32 and (1<<channel) or 0;local high=channel>=32 and (1<<(channel-32)) or 0
   assert(R.TakeFX_SetPinMappings(v.take,fx,0,pin,low,high),'ReaEQのチャンネルを設定できません。')
   assert(R.TakeFX_SetPinMappings(v.take,fx,1,pin,low,high),'ReaEQのチャンネルを設定できません。')
  end
  assert(R.TakeFX_SetNamedConfigParm(v.take,fx,'renamed_name',Core.FILTER_TAG),'ReaEQの識別情報を保存できません。')
  result[#result+1]={fx=fx,guid=R.TakeFX_GetFXGUID(v.take,fx)}
 end
 -- Replace legacy FX at its original chain position; unrelated FX retain order.
 if #legacy==1 then
  local dest=legacy[1].fx
  for i,f in ipairs(result) do
   R.TakeFX_CopyToTake(v.take,f.fx,v.take,dest+i-1,true)
  end
  assert(R.TakeFX_Delete(v.take,dest+#result),'旧BLTフィルターを置換できません。')
 end
 -- Disable excess managed pairs rather than deleting user-visible instances.
 for i=count+1,#managed do R.TakeFX_SetEnabled(v.take,managed[i].fx,false) end
 local ids={};for _,f in ipairs(result) do assert(f.guid and f.guid~='','ReaEQの識別情報を保存できません。');ids[#ids+1]=f.guid end
 for i=count+1,#managed do ids[#ids+1]=managed[i].guid end
 assert(R.GetSetMediaItemTakeInfo_String(v.take,Core.FILTER_OWNER,table.concat(ids,'|'),true),'ReaEQの識別情報を保存できません。')
 -- Resolve indices again after moving/removing FX.
 local byid={};for fx=0,R.TakeFX_GetCount(v.take)-1 do byid[R.TakeFX_GetFXGUID(v.take,fx)]=fx end
 for _,f in ipairs(result) do f.fx=assert(byid[f.guid]) end
 return result
end
function Core.add_filters(v,layers,map,rate,limit,stats)
 local existing=Core.find_filters(v.take)
 if not (layers.highpass.enabled or layers.lowpass.enabled) and #existing==0 then return end
 local effects=Core.create_filter_eq(v,layers,existing)
 for band,key in ipairs({'highpass','lowpass'}) do
  local c=layers[key];local param=(band-1)*3
  if c.enabled then
   local mapping=Core.filter_mapping(v.take,effects[1].fx,param)
   local function normalized(u)
    local hz=Core.frequency(Core.at(layers,key,u))
    if hz<mapping.low or hz>mapping.high then stats.filter_clipped=true end
    return mapping.normalized(hz)
   end
   local initial=normalized(0);local points
   if Core.constant(c)==nil then
    points=Core.sample_curve(layers,{key},map,v,rate,nil,normalized,.0002,limit)
    local reduced;points,reduced=Core.limit_points(points,limit);stats.reduced=stats.reduced or reduced;stats[key]=#points
   end
   for _,f in ipairs(effects) do
    assert(R.TakeFX_SetParamNormalized(v.take,f.fx,param,initial),'ReaEQの周波数を設定できません。')
    if points then
     local env=R.TakeFX_GetEnvelope(v.take,f.fx,param,true);assert(env,'フィルターのカーブを作成できません。')
     for _,p in ipairs(points) do assert(R.InsertEnvelopePoint(env,p.x,p.y,0,0,false,true)) end
     R.Envelope_SortPoints(env)
    end
   end
  end
 end
end

function Core.apply(v,layers,limit,joined)
 if not Core.valid(v.project,v.item,v.take) then error('対象のテイクが変更されています。再読み込みしてください。',0) end
 local map,len,timing,factor=Core.map(layers,v.len,limit)
 local stats={markers=0,pitch=0,volume=0,highpass=0,lowpass=0,reduced=false,limit=limit}
 if limit and not factor then
  local pts={};for _,p in ipairs(map) do pts[#pts+1]={x=p.u,y=p.t} end
  pts,stats.reduced=Core.limit_points(pts,limit);map={}
  for _,p in ipairs(pts) do map[#map+1]={u=p.x,t=p.y} end
 end
 local fixed_timing=timing and factor~=nil
 local rate=fixed_timing and v.rate*factor or v.rate
 -- Expected input restrictions are UI notices, not execution failures. Leave the
 -- item untouched and the drawing editable; reserve exceptions for actual faults.
 if timing and R.GetMediaSourceParent(v.source) then return nil,'反転・セクション素材：グルー後に尺連動・速度カーブを適用してください。' end
 if R.GetMediaItemInfo_Value(v.item,'C_LOCK')~=0 then return nil,'アイテムのロックを解除してから適用してください。' end
 if R.GetMediaItemInfo_Value(v.item,'B_ALLTAKESPLAY')~=0 then return nil,'全テイク同時再生をOFFにしてから適用してください。' end
 local before=Core.chunk(v.item);local selection=Core.selected(v.project)
 local pitch=Core.changed(layers.pitch) or (timing and Core.changed(layers.speed))
 local volume=Core.changed(layers.volume)
 local pc,sc,vc=Core.constant(layers.pitch),Core.constant(layers.speed),Core.constant(layers.volume)
 local fixed_pitch=pc~=nil and (not timing or sc~=nil)
 local pitch_offset=fixed_pitch and 24*(pc-(timing and sc or 0)) or 0
 -- Capture values before rewriting. Original pitch adds; original volume multiplies.
 local pe=Core.envelope(v.take,'Pitch');local ve=Core.envelope(v.take,'Volume')
 local vm=ve and R.GetEnvelopeScalingMode(ve) or 0
 local pitch_samples,volume_samples
 if pitch and not fixed_pitch then
  pitch_samples=Core.sample_curve(layers,{'pitch','speed'},map,v,rate,pe,function(u)
   return Core.evaluate(pe,u*v.len*v.rate,0)+24*(Core.at(layers,'pitch',u)-(timing and Core.at(layers,'speed',u) or 0))
  end,false,limit)
  local reduced;pitch_samples,reduced=Core.limit_points(pitch_samples,limit);stats.reduced=stats.reduced or reduced;stats.pitch=#pitch_samples
 end
 if volume and vc==nil then
  volume_samples=Core.sample_curve(layers,{'volume'},map,v,rate,ve,function(u)
   return R.ScaleFromEnvelopeMode(vm,Core.evaluate(ve,u*v.len*v.rate,R.ScaleToEnvelopeMode(vm,1)))*10^(Core.db(Core.at(layers,'volume',u))/20)
  end,true,limit)
 end
 -- Preserve every pre-existing take envelope when timing changes (including FX).
 local originals={}
 if timing and not fixed_timing then
  for i=0,R.CountTakeEnvelopes(v.take)-1 do
   local env=R.GetTakeEnvelope(v.take,i);local pts={}
   for j=0,R.CountEnvelopePoints(env)-1 do
    local ok,t,value,shape,tension,sel=R.GetEnvelopePoint(env,j)
    if ok then pts[#pts+1]={t=t,value=value,shape=shape,tension=tension,selected=sel} end
   end
   originals[#originals+1]={env=env,points=pts}
  end
 end
 if not joined then R.Undo_BeginBlock2(v.project) end;R.PreventUIRefresh(1)
 local ok,err=xpcall(function()
  if timing then
   local count=R.GetTakeNumStretchMarkers(v.take)
   if count>0 then R.DeleteTakeStretchMarkers(v.take,0,count);assert(R.GetTakeNumStretchMarkers(v.take)==0,'時間マーカーを置き換えられません。') end
   assert(R.SetMediaItemInfo_Value(v.item,'D_LENGTH',len),'尺を変更できません。')
   if R.GetMediaItemTakeInfo_Value(v.take,'B_PPITCH')>=.5 then
    assert(R.SetMediaItemTakeInfo_Value(v.take,'D_PITCH',R.GetMediaItemTakeInfo_Value(v.take,'D_PITCH')-12*math.log(v.rate,2)))
   end
   assert(R.SetMediaItemTakeInfo_Value(v.take,'B_PPITCH',0))
   if fixed_timing then
    assert(R.SetMediaItemTakeInfo_Value(v.take,'D_PLAYRATE',rate),'再生速度を変更できません。')
   else for _,p in ipairs(map) do
    local idx=R.SetTakeStretchMarker(v.take,-1,p.t*v.rate,v.offset+p.u*v.len*v.rate)
    if idx<0 and p.t>1e-8 then error('時間カーブを書き込めません。',0) end
    if idx>=0 then R.SetTakeStretchMarkerSlope(v.take,idx,0);stats.markers=stats.markers+1 end
   end end
   for _,e in ipairs(originals) do
    R.DeleteEnvelopePointRange(e.env,-1e20,1e20)
    for _,p in ipairs(e.points) do
     local t=p.t
     if t>=0 and t<=v.len*v.rate then t=Core.lookup(map,t/(v.len*v.rate),'u','t')*v.rate
     elseif t>v.len*v.rate then t=t+(len-v.len)*v.rate end
     assert(R.InsertEnvelopePoint(e.env,t,p.value,p.shape,p.tension,p.selected,true))
    end
    R.Envelope_SortPoints(e.env)
   end
   for _,key in ipairs({'D_FADEINLEN','D_FADEOUTLEN','D_FADEINLEN_AUTO','D_FADEOUTLEN_AUTO'}) do
    local f=R.GetMediaItemInfo_Value(v.item,key)
    if f>0 then
     local out=key:find('OUT')~=nil
     local mapped=out and len-Core.lookup(map,clamp(1-f/v.len,0,1),'u','t') or Core.lookup(map,clamp(f/v.len,0,1),'u','t')
     R.SetMediaItemInfo_Value(v.item,key,max(0,mapped))
    end
   end
  end
  if pitch then
   if fixed_pitch then
    assert(R.SetMediaItemTakeInfo_Value(v.take,'D_PITCH',R.GetMediaItemTakeInfo_Value(v.take,'D_PITCH')+pitch_offset))
   else
   local env=Core.ensure_env(v.project,v.item,v.take,'Pitch',41612);R.DeleteEnvelopePointRange(env,-1e20,1e20)
   for _,p in ipairs(pitch_samples) do assert(R.InsertEnvelopePoint(env,p.x,p.y,0,0,false,true)) end;R.Envelope_SortPoints(env)
   end
  end
  if volume then
   if vc~=nil then
    assert(R.SetMediaItemTakeInfo_Value(v.take,'D_VOL',R.GetMediaItemTakeInfo_Value(v.take,'D_VOL')*10^(Core.db(vc)/20)))
   else
   local env=Core.ensure_env(v.project,v.item,v.take,'Volume',40693);local mode=R.GetEnvelopeScalingMode(env)
   local points=Core.volume_points(volume_samples,mode,limit)
   local reduced;points,reduced=Core.limit_points(points,limit);stats.reduced=stats.reduced or reduced;stats.volume=#points
   R.DeleteEnvelopePointRange(env,-1e20,1e20)
   for _,p in ipairs(points) do assert(R.InsertEnvelopePoint(env,p.x,p.y,0,0,false,true)) end;R.Envelope_SortPoints(env)
   end
  end
  Core.add_filters(v,layers,map,rate,limit,stats)
  R.UpdateItemInProject(v.item)
 end,debug.traceback)
 if not ok then
  local restored=R.SetItemStateChunk(v.item,before,false)
  if not restored then err=tostring(err)..'\n復元に失敗しました。REAPERのUndoで戻してください。' end
 end
 Core.restore_selection(v.project,selection);R.PreventUIRefresh(-1)
 if not joined then R.Undo_EndBlock2(v.project,ok and 'BLT Envelope Canvas: Apply curves' or 'BLT Envelope Canvas: Apply failed',-1) end;R.UpdateArrange()
 if not ok then error(err,0) end
 return {before=before,after=Core.chunk(v.item),map=map,len=len,original=v,stats=stats}
end
-- Read active take processing without changing the item or transport.
function Core.read_curves(v,limit)
 assert(Core.valid(v.project,v.item,v.take),'対象のテイクが変更されています。')
 limit=math.min(limit or 256,Core.MAX_POINTS)
 local layers=Core.new_layers();local map={{u=0,t=0},{u=1,t=v.len}}
 local clipped=false
 local function read(key,env,fn)
  local c=layers[key]
  local pts=Core.sample_curve(layers,{},map,v,v.rate,env,function(u)
   local y=fn(u*v.len*v.rate)
   if y<c.min_y or y>c.max_y then clipped=true end
   return clamp(y,c.min_y,c.max_y)
  end,.0002,limit)
  pts=Core.limit_points(pts,limit)
  for _,p in ipairs(pts) do p.x=p.x/(v.len*v.rate) end
  c.points=pts
 end
 local pe=Core.envelope(v.take,'Pitch');local ve=Core.envelope(v.take,'Volume')
 local pitch=R.GetMediaItemTakeInfo_Value(v.take,'D_PITCH')
 local volume=R.GetMediaItemTakeInfo_Value(v.take,'D_VOL')
 local mode=ve and R.GetEnvelopeScalingMode(ve) or 0
 read('pitch',pe,function(t) return (pitch+Core.evaluate(pe,t,0))/24 end)
 read('volume',ve,function(t)
  local gain=volume*R.ScaleFromEnvelopeMode(mode,Core.evaluate(ve,t,R.ScaleToEnvelopeMode(mode,1)))
  local db=20*math.log(max(1e-12,gain),10);return db/(db>=0 and 12 or 60)
 end)
 local filters=Core.find_filters(v.take)
 if #filters>0 then
  local f=filters[1];local active=R.TakeFX_GetEnabled(v.take,f.fx) and not R.TakeFX_GetOffline(v.take,f.fx)
  for i,key in ipairs({'highpass','lowpass'}) do
   local param=f.legacy and i-1 or (i-1)*3
   local env=R.TakeFX_GetEnvelope(v.take,f.fx,param,false)
   local fixed=R.TakeFX_GetParamNormalized(v.take,f.fx,param)
   local enabled
   if f.legacy then enabled=R.TakeFX_GetParamNormalized(v.take,f.fx,i+1)>=.5
   else local ok,text=R.TakeFX_GetNamedConfigParm(v.take,f.fx,'BANDENABLED'..(i-1));enabled=ok and tonumber(text)==1 end
   layers[key].enabled=active and enabled
   local mapping=not f.legacy and Core.filter_mapping(v.take,f.fx,param)
   read(key,env,function(t)
    local n=Core.evaluate(env,t,fixed)
    return f.legacy and 2*n-1 or 2*math.log(max(20,mapping.hz(n))/20)/math.log(4800)-1
   end)
  end
 end
 local chunk=Core.chunk(v.item)
 return layers,{before=chunk,after=chunk,original=v,map=map,len=v.len,imported=true,layers=Core.copy(layers)},clipped
end
function Core.regenerate(v,layers,limit,record)
 if not record then return Core.apply(v,layers,limit) end
 if Core.signature(Core.chunk(v.item))~=Core.signature(record.after) then return nil,'対象に外部変更があります。REAPERのUndoで確認してください。' end
 local current=Core.chunk(v.item);local selection=Core.selected(v.project)
 R.Undo_BeginBlock2(v.project);R.PreventUIRefresh(1)
 local result,reason
 local ok,err=xpcall(function()
  assert(R.SetItemStateChunk(v.item,record.before,false),'生成前の状態へ戻せません。')
  local original=Core.info(v.project,v.item);assert(original,'生成元の音声を取得できません。')
  if record.imported then
   -- Imported pitch and volume describe the total take settings, not an offset.
   assert(R.SetMediaItemTakeInfo_Value(original.take,'D_PITCH',0))
   assert(R.SetMediaItemTakeInfo_Value(original.take,'D_VOL',1))
   for _,name in ipairs({'Pitch','Volume'}) do
    local env=Core.envelope(original.take,name)
    if env then
     R.DeleteEnvelopePointRange(env,-1e20,1e20)
     local value=name=='Volume' and R.ScaleToEnvelopeMode(R.GetEnvelopeScalingMode(env),1) or 0
     assert(R.InsertEnvelopePoint(env,0,value,0,0,false,true));R.Envelope_SortPoints(env)
    end
   end
  end
  result,reason=Core.apply(original,layers,limit,true)
  if result and record.imported then result.before=record.before;result.imported=true end
 end,debug.traceback)
 if not ok or not result then
  local restored=R.SetItemStateChunk(v.item,current,false)
  if not restored then ok=false;err=tostring(err or reason)..' / 復元失敗：REAPERのUndoを使用してください。' end
 end
 Core.restore_selection(v.project,selection);R.PreventUIRefresh(-1)
 R.Undo_EndBlock2(v.project,'BLT Envelope Canvas: Regenerate',-1);R.UpdateArrange()
 if not ok then error(err,0) end
 return result,reason
end
-- Pure functions can be loaded for headless mathematical checks, without UI/API calls.
if ...=='core_test' then return Core end

local SECTION=Core.SECTION
local W,H=1120,838
local A={layers=Core.new_layers(),layer='pitch',tool='free',direction=3,pattern=1,period_percent=100,period_shape=1,height=100,shape_envelope=1,history={},redo={},sessions={},
 status='',warning=false,content_dirty=true,wave_dirty=true,view=0,span=1,wave={},wave_max=1,
 busy=false,closed=false,poll_at=0,active=true,selection_poll=0,point_limit=128,filter_link=false,
 ranges={pitch=48,tape=24,speed=4,volume=24,highpass=24000,lowpass=24000},session_order={}}
for _,curve in pairs(A.layers) do curve.enabled=false;curve.kind="smooth" end
local UI={}

local C={
  bg={0.018,0.030,0.055}, bg2={0.030,0.090,0.180},
  panel={0.040,0.068,0.110}, panel2={0.055,0.125,0.205},
  field={0.018,0.040,0.080}, edge={0.145,0.285,0.445}, edge2={0.360,0.650,0.900},
  text={0.955,0.980,1.000}, muted={0.690,0.780,0.875}, faint={0.390,0.505,0.635},
  accent={0.120,0.490,0.980}, accent2={0.650,0.895,1.000}, accent3={0.045,0.235,0.520},
  focus={0.225,0.610,1.000}, focus2={0.690,0.900,1.000}, ink={0.018,0.075,0.160},
  hover={0.430,0.790,1.000}, warn={1.000,0.755,0.490}, red={1.000,0.230,0.300}, quiet={0.300,0.360,0.440}
}
local fonts={"Yu Gothic UI","Segoe UI","Consolas"}
if BLT_MAC then fonts={"Hiragino Sans","Helvetica Neue","Menlo"} end
if R.GetOS():match("Linux") then fonts={"sans-serif","sans-serif","monospace"} end

local scale,ox,oy=1,0,0
 BLT.viewport(scale,gfx.ext_retina or 1);local frame_clock,frame_dt,particle_dt,anim_time=R.time_precise(),1/60,1/60,0
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
  if next_draw_time>now+1/20 then next_draw_time=now end
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
local widgets={}
local edit=nil
local down_last,pressed=false,nil
local mouse_x,mouse_y=-1,-1
local hover_hint=""

local function sx(x) return ox+x*scale end
local function sy(y) return oy+y*scale end
local function color(c,a) gfx.set(c[1],c[2],c[3],a or 1) end
local function rect(x,y,w,h,c,a) color(c,a); gfx.rect(sx(x),sy(y),w*scale,h*scale,1) end
local function line(x,y,x2,y2,c,a) color(c,a); gfx.line(sx(x),sy(y),sx(x2),sy(y2),1) end
local function disc(x,y,r,c,a) color(c,a); gfx.circle(sx(x),sy(y),r*scale,1,1) end
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
local function glow_line(x,y,x2,y2,c,strength)
  strength=strength or 1
  line(x,y-3,x2,y2-3,c,0.025*strength); line(x,y+3,x2,y2+3,c,0.025*strength)
  line(x,y-2,x2,y2-2,c,0.055*strength); line(x,y+2,x2,y2+2,c,0.055*strength)
  line(x,y-1,x2,y2-1,c,0.13*strength); line(x,y+1,x2,y2+1,c,0.13*strength)
  line(x,y,x2,y2,c,0.95*strength)
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
local function inside(x,y,w,h) return mouse_x>=x and mouse_x<=x+w and mouse_y>=y and mouse_y<=y+h end
local function register(id,x,y,w,h,fn,hint,enabled)
  widgets[#widgets+1]={id=id,x=x,y=y,w=w,h=h,fn=fn,hint=hint,enabled=enabled~=false}
  if inside(x,y,w,h) and hint then hover_hint=hint end
end

local function notice(s,warn) A.status=warn and BLT.publicError(s) or tostring(s or '');A.warning=warn or false;A.status_until=R.time_precise()+7;A.content_dirty=true;wake_visuals() end
local function invalidate_wave_surface() A.wave_dirty=true;A.content_dirty=true;wake_visuals() end

local text_queue={}
local function font_spec(size,kind,bold) return BLT.spec(size,kind,bold,scale) end

local function font(size,kind,bold) BLT.font(size,kind,bold,scale,fonts) end
local function queue_text(t,x,y,right,bottom,flags,size,c,kind,bold,translated)
  local fk,_,_,key=font_spec(size,kind,bold)
  local bucket=text_queue[key]
  if not bucket then bucket={};text_queue[key]=bucket;text_queue[#text_queue+1]=bucket end
  bucket[#bucket+1]={text=t,x=x,y=y,right=right,bottom=bottom,flags=flags or 0,size=size,kind=fk,bold=bold and true or false,fontkey=key,c=c or C.text}
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

local function flush_text_queue()
  if #text_queue==0 then return end
  for _,b in ipairs(text_queue) do
    local first=b[1]
    font(first.size,first.kind,first.bold)
    for _,cmd in ipairs(b) do
      color(cmd.c);gfx.x,gfx.y=cmd.x,cmd.y
      gfx.drawstr(cmd.translated and BLT.ui.fit(cmd.text,cmd.right-cmd.x) or cmd.text,cmd.flags,cmd.right,cmd.bottom)
    end
  end
  text_queue={}
end

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
  chameleonPressed=false,resizeCursors={},resizeCursorMode=nil,titleH=26,windowTitle='BLT Envelope Canvas',titleText='E N V E L O P E   C A N V A S',
  minW=1000,minH=740,mint={0.38,0.88,0.72},ice={0.65,0.895,1.0},red={1.0,0.27,0.34},
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
  redraw_dirty=true; A.content_dirty=true; A.wave_dirty=true
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
    redraw_dirty=true; A.content_dirty=true; A.wave_dirty=true
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
  invalidate_wave_surface(true)
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

UI.defs={
 {key='pitch',name='ピッチ',code='PITCH',sub='尺を保持',color={.46,.82,1}},
 {key='tape',name='ピッチ · 尺連動',code='TAPE PITCH',sub='音程と尺を連動',color={.78,.56,1}},
 {key='speed',name='再生速度',code='SPEED',sub='音程を保持',color={1,.73,.36}},
 {key='volume',name='ボリューム',code='VOLUME',sub='ゲインを描画',color={.38,.91,.72}},
 {key='lowpass',name='ローパス',code='LOW PASS',sub='カットオフ · 中高域重視',color={.89,.75,.36}},
 {key='highpass',name='ハイパス',code='HIGH PASS',sub='カットオフ · 中高域重視',color={1,.52,.42}}
}
function UI.theme_color(original,role)
 if not Chameleon.enabled then return original end
 if role then return C[role] end
 return fit_accent_to_bg(original,C.bg,clum(C.text)>clum(C.bg))
end
function UI.theme_sync()
 local signature=tostring(Chameleon.enabled)..tostring(C.bg)..tostring(C.text)
 if UI.theme_signature==signature then return end
 UI.theme_signature=signature
 for _,d in ipairs(UI.defs) do
  d.original_color=d.original_color or d.color
  d.color=UI.theme_color(d.original_color)
 end
end
UI.pattern_names={'サイン波','ノコギリ波','矩形波','三角波','水平線','ランダムステップ'}
UI.pattern_kinds={'sine','saw','square','triangle','horizontal','random_step'}
UI.period_names={'周期：一定','アッチェレランド','リタルダンド'}
UI.envelope_names={'振幅：一定','クレッシェンド','デクレッシェンド'}
-- Keep one lottery while the preview moves, then retire it after stamping.
function UI.reset_line_preview(reset_random)
 UI.preview_key=nil;UI.preview_points=nil;UI.preview_ua=nil;UI.preview_ub=nil
 if reset_random then UI.random_step_state=nil end
end
function UI.random_step_levels(slot)
 local target=tostring(A.v and A.v.item)
 local state=UI.random_step_state
 if not state or state.target~=target then state={target=target};UI.random_step_state=state end
 local levels=state[slot]
 if not levels then levels={};state[slot]=levels end
 local count=max(1,ceil(100/A.period_percent-1e-12))
 for i=#levels+1,count do levels[i]=math.random()*2-1 end
 return levels
end
function UI.next_pattern()
 A.pattern=A.pattern%#UI.pattern_names+1
 UI.reset_line_preview(true);UI.dirty()
end
function UI.set_smoothness(amount,drag)
 if A.busy then return end
 local c=A.layers[A.layer];amount=clamp(amount,0,2)
 if Core.smoothness(c)==amount then return end
 if not drag or not drag.changed then UI.history();if drag then drag.changed=true end end
 c.smoothness=amount;c.kind=amount==0 and 'linear' or 'smooth';UI.dirty()
end
function UI.set_interpolation(kind) UI.set_smoothness(kind=='linear' and 0 or 1) end
function UI.smoothness_slider()
 local x,y,w,h=24,205,164,16;local amount=Core.smoothness(A.layers[A.layer]);local tone=UI.def().color
 local left,right=x+6,x+w-6;local cy=y+h/2;local knob=left+(right-left)*amount/2
 rect(left,cy-2,right-left,4,C.edge,.65)
 rect(left,cy-2,knob-left,4,tone,A.busy and .25 or .70)
 disc(knob,cy,6,C.field,1);disc(knob,cy,4,tone,A.busy and .35 or .95)
 register('smoothness',x,y,w,h,function() end,'左：直線 ／ 中央：従来の滑らかさ ／ 右：強いカーブ',not A.busy)
end
function UI.smoothness_input(id,down)
 local drag=A.drag and A.drag.mode=='smoothness' and A.drag
 if not drag and id=='smoothness' and down and not down_last and not A.busy then
  drag={mode='smoothness'};A.drag=drag;A.pointer_capture=true
 end
 if not drag then return false end
 if down or down_last then UI.set_smoothness((mouse_x-30)/76,drag) end
 if not down then A.drag=nil;A.pointer_capture=nil;UI.dirty() end
 return true
end
function UI.clear_curves(all)
 if A.busy then return end;UI.history()
 for key,c in pairs(A.layers) do if all or key==A.layer then
  local y=c.neutral or 0;c.points={{x=0,y=y},{x=1,y=y}};if all or c.filter then c.enabled=false end
 end end;A.selection=nil;A.hover_node=nil;if all then UI.link_prime() end;UI.dirty()
end
function UI.generate_line(chaos)
 if A.busy then return end
 UI.history();local c=A.layers[A.layer]
 local points
 local kind=UI.pattern_kinds[A.pattern]
 if chaos then points=Core.chaos(128) else points=Core.pattern(kind,100/A.period_percent,A.height/100,A.shape_envelope,kind=='random_step' and UI.random_step_levels('whole') or nil,A.period_shape) end
 for _,p in ipairs(points) do p.y=UI.from_axis(A.layer,p.y) end
 c.points=points;c.enabled=true;A.selection=nil;A.hover_node=nil
 if kind=='random_step' then UI.reset_line_preview(true) end
 notice(chaos and '現在のカーブをランダム生成しました。' or '現在のカーブにラインを生成しました。');UI.dirty()
end
UI.graph={x=212,y=166,w=784,h=372}
UI.range_steps={pitch={3,6,12,24,48},tape={3,6,12,24},speed={1.25,1.5,2,4},volume={6,12,24},highpass={24000},lowpass={24000}}
function UI.from_axis(key,y)
 local r=A.ranges[key]
 if key=='highpass' or key=='lowpass' then
  return Core.filter_value((y+1)/2*math.log((r+Core.FILTER_AXIS_OFFSET)/(20+Core.FILTER_AXIS_OFFSET)))
 end
 if key=='speed' then return y*math.log(r,2)/2 end
 if key=='volume' then return y>=0 and y*r/12 or y end
 return y*r/24
end
function UI.to_axis(key,y)
 local r=A.ranges[key]
 if key=='highpass' or key=='lowpass' then
  return 2*Core.filter_axis(y)/math.log((r+Core.FILTER_AXIS_OFFSET)/(20+Core.FILTER_AXIS_OFFSET))-1
 end
 if key=='speed' then return y*2/math.log(r,2) end
 if key=='volume' then return y>=0 and y*12/r or y end
 return y*24/r
end
function UI.cycle_range(key,delta)
 if key=='highpass' or key=='lowpass' then return end
 local steps=UI.range_steps[key];local i=1
 for j,v in ipairs(steps) do if v==A.ranges[key] then i=j;break end end
 A.ranges[key]=steps[clamp(i+(delta or 1),1,#steps)];A.selection=nil;UI.dirty()
end
UI.FRAME=60;UI.WAVE=61;UI.frame_w=0;UI.frame_h=0
function UI.def() for _,d in ipairs(UI.defs) do if d.key==A.layer then return d end end end
-- The linked partner follows edits, while toggling link alone preserves both drawings.
function UI.link_prime()
 A.link_snapshot={highpass=Core.copy(A.layers.highpass),lowpass=Core.copy(A.layers.lowpass)}
end
function UI.link_write(key)
 local other=key=='highpass' and 'lowpass' or 'highpass'
 local src,dest=A.layers[key],A.layers[other]
 -- An edited partner becomes the new driver; snapshots never reference each other.
 src.link_source=nil;src.link_offset=nil
 local delta=2*(A.link_width or 1)*math.log(2)/math.log(4800)*(key=='highpass' and 1 or -1)
 local points={}
 for _,p in ipairs(src.points) do points[#points+1]={x=p.x,y=clamp(p.y+delta,dest.min_y,dest.max_y)} end
 dest.points=points;dest.kind=src.kind;dest.smoothness=src.smoothness;dest.enabled=src.enabled
 -- Evaluate the driver's interpolated frequency first, then offset in octaves.
 dest.link_source=Core.copy(src);dest.link_offset=delta
end
function UI.link_sync()
 if not A.link_snapshot then UI.link_prime();return end
 local function changed(key)
  local a,b=A.layers[key],A.link_snapshot[key]
  if a.enabled~=b.enabled or a.kind~=b.kind or Core.smoothness(a)~=Core.smoothness(b) or #a.points~=#b.points then return true end
  for i,p in ipairs(a.points) do local q=b.points[i];if p.x~=q.x or p.y~=q.y then return true end end
  return false
 end
 local hp,lp=changed('highpass'),changed('lowpass')
 if not hp and not lp then return end
 if not A.filter_link then
  for _,key in ipairs({'highpass','lowpass'}) do if (key=='highpass' and hp) or (key=='lowpass' and lp) then
   A.layers[key].link_source=nil;A.layers[key].link_offset=nil
  end end
 else
  local key=hp and lp and (A.layer=='lowpass' and 'lowpass' or 'highpass') or hp and 'highpass' or 'lowpass'
  UI.link_write(key)
 end
 UI.link_prime()
end
function UI.link_toggle()
 if A.busy or A.drag then return end
 A.filter_link=not A.filter_link;UI.link_prime();UI.dirty()
 notice(A.filter_link and 'HP／LPリンク ON：次の編集から帯域幅を連動します。' or 'HP／LPリンク OFF：個別に編集できます。')
end
function UI.link_width_step(delta)
 if A.busy or A.drag then return end
 local width=clamp((A.link_width or 1)+delta*.25,.25,8)
 if width==(A.link_width or 1) then return end
 if A.filter_link then UI.history() end
 A.link_width=width
 if A.filter_link then UI.link_write(A.layer=='lowpass' and 'lowpass' or 'highpass');UI.link_prime() end
 UI.dirty()
end
function UI.card_geometry(i)
 local x=212+((i-1)%3)*294;local y=619+floor((i-1)/3)*69;local w=282
 if i==5 then w=228 elseif i==6 then x=854;w=228 end
 return x,y,w
end
function UI.link_button()
 local x,y,w,h=744,688,100,61;local active=A.filter_link;local enabled=not A.busy and not A.drag
 local hovered=A.hit=='filter_link' and enabled
 local a=animate('filter_link_gold',active and 1 or (hovered and .20 or 0))
 local gold=UI.theme_color({1,.885,.440})
 local light=Chameleon.enabled and cmix(gold,C.text,.6) or {1,.965,.745}
 local dark=Chameleon.enabled and cmix(C.panel,gold,.12) or {.280,.210,.075}
 if active then
  for spread=6,1,-1 do
   cut_panel(x-spread,y-spread,w+2*spread,h+2*spread,8+spread,gold,.006+.003*(7-spread),nil,nil,true)
  end
 end
 cut_panel(x,y,w,h,8,C.panel,.98,active and gold or C.edge2,active and .95 or .30,true)
 gradient(x+2,y+2,w-4,h-4,gold,dark,.46*a,.75*a,true)
 if active then glow_line(x+9,y,x+w-9,y,gold,.85);glow_line(x+9,y+h,x+w-9,y+h,gold,.65) end
 label(active and 'LINK ON' or 'LINK OFF',x,y+1,14,active and light or C.muted,3,w,23,5,true)
 register('filter_link',x,y,w,24,UI.link_toggle,'',enabled)
 line(x+8,y+24,x+w-8,y+24,active and gold or C.edge2,.3)
 label('帯域幅 / oct',x,y+24,12,active and light or C.muted,1,w,15,5,false)
 label(string.format('%.2f',A.link_width or 1),x+24,y+38,18,C.text,1,w-48,23,5,false)
 for _,q in ipairs({{-1,x+2,'<'},{1,x+w-24,'>'}}) do
  local delta,ax=q[1],q[2];local id='link_width_'..delta
  if A.hit==id and enabled then rect(ax,y+37,22,24,gold,.16) end
  label(q[3],ax,y+37,18,active and light or C.accent2,1,22,24,5,false)
  register(id,ax,y+36,22,25,function() UI.link_width_step(delta) end,'',enabled)
 end
end
function UI.dirty(wave) UI.link_sync();A.content_dirty=true;if wave then A.wave_dirty=true end;wake_visuals() end
function UI.safe(fn)
 local ok,err=xpcall(fn,debug.traceback)
 if not ok then
  A.busy=false
  BLT.cleanup(UI.stop_wave)
  if A.v then
   local refreshed,value=pcall(function() if R.ValidatePtr2(A.v.project,A.v.item,'MediaItem*') then return Core.info(A.v.project,A.v.item) end end)
   A.v=refreshed and value or nil;A.revision=nil
  end
  notice(err,true)
  BLT.recoverInput(A,err)
 end
 return ok
end
function UI.history()
 A.history[#A.history+1]=Core.copy(A.layers);if #A.history>40 then table.remove(A.history,1) end;A.redo={}
end
function UI.undo_draw(redo)
 if A.busy then return end
 local from,to=redo and A.redo or A.history,redo and A.history or A.redo
 if #from==0 then return end
 to[#to+1]=Core.copy(A.layers);A.layers=table.remove(from);A.selection=nil;UI.link_prime();UI.dirty()
end
function UI.stop_wave()
 if A.wave_job and A.wave_job.accessor then R.DestroyAudioAccessor(A.wave_job.accessor) end;A.wave_job=nil
end
function UI.start_wave()
 UI.stop_wave();A.wave={};A.wave_max=1
 if not A.v then return end
 local v=A.v;local total=4096;local channels=min(64,v.channels)
 A.wave_job={v=v,total=total,index=0,rate=total/v.len,channels=channels,buffer=R.new_array(1024*channels),max=0}
 UI.dirty(true)
end
function UI.wave_step()
 local j=A.wave_job;if not j then return end
 if not Core.valid(j.v.project,j.v.item,j.v.take) then UI.stop_wave();return end
 local now=R.time_precise();local budget=now+.006
 repeat
  if not j.accessor then
   local count=min(512,j.total-j.index);j.buffer.clear()
   local rv=R.GetMediaItemTake_Peaks(j.v.take,j.rate,j.v.pos+j.index/j.rate,j.channels,count,0,j.buffer)
   local got=type(rv)=='number' and (rv&0xfffff) or 0
   if got>0 then
    local values=j.buffer.table(1,got*j.channels*2)
    for i=0,got-1 do
     local peak=0;for c=1,j.channels do local z=i*j.channels+c;peak=max(peak,abs(values[z] or 0),abs(values[got*j.channels+z] or 0)) end
     A.wave[j.index+i+1]=peak;j.max=max(j.max,peak)
    end
    j.index=j.index+got
   else
    j.accessor=R.CreateTakeAudioAccessor(j.v.take)
    if not j.accessor then error('波形を取得できません。音声ファイルがオンラインか確認してください。',0) end
    j.sample=floor(j.index/j.rate*48000);j.samples=ceil(j.v.len*48000)
    j.block=max(64,floor(32768/j.channels));j.buffer=R.new_array(j.block*j.channels)
   end
  else
   local count=min(j.block,j.samples-j.sample)
   if count<=0 then j.index=j.total else
    j.buffer.clear();local rv=R.GetAudioAccessorSamples(j.accessor,48000,j.channels,j.sample/48000,count,j.buffer)
    if rv<0 then error('音声の読み出しに失敗しました。',0) end
    local values=j.buffer.table(1,count*j.channels)
    for i=0,count-1 do
     local idx=min(j.total,floor((j.sample+i)/j.samples*j.total)+1);local peak=A.wave[idx] or 0
     for c=1,j.channels do peak=max(peak,abs(values[i*j.channels+c] or 0)) end
     A.wave[idx]=peak;j.max=max(j.max,peak)
    end
    j.sample=j.sample+count;j.index=min(j.total,floor(j.sample/j.samples*j.total))
   end
  end
 until j.index>=j.total or R.time_precise()>=budget
 if j.index>=j.total then
  for i=1,j.total do A.wave[i]=A.wave[i] or 0 end
  A.wave_max=max(.001,j.max);UI.stop_wave();UI.dirty(true)
 elseif now>(A.wave_present_at or 0) then A.wave_present_at=now+.15;A.wave_max=max(.001,j.max);UI.dirty(true) end
end
function UI.session_key(v) return tostring(v.project)..':'..v.guid end
function UI.stash()
 if not A.v then return end
 local key=UI.session_key(A.v)
 if not A.sessions[key] then A.session_order[#A.session_order+1]=key end
 A.sessions[key]={record=A.record,wave=not A.wave_job and A.wave or nil,wave_max=A.wave_max,baseline=A.baseline,
  signature=Core.signature(A.record and A.record.after or A.baseline)}
 while #A.session_order>16 do A.sessions[table.remove(A.session_order,1)]=nil end
end
function UI.load_selection(force,selected)
 if A.busy then return end
 local project=R.EnumProjects(-1,'');local v=selected or Core.first(project)
 if not v and A.v and A.v.project==project then v=Core.info(project,A.v.item) end
 local same=v and A.v and A.v.project==project and A.v.item==v.item and A.v.take==v.take
 if same and not force then return end
 if same and A.record then UI.dirty();return end
 UI.stash();UI.stop_wave()
 if A.drag and A.drag.mode=='free' then Core.simplify(A.layers[A.layer],.0015) end
 A.drag=nil;A.selection=nil;pressed=nil;A.pointer_capture=nil;A.center_snap=nil
 A.v=v;A.record=nil;A.conflict=false;A.revision=nil
 if not v then
  A.baseline=nil;A.wave={};A.wave_max=1;A.status='音声アイテムを選択すると自動で読み込みます。';UI.dirty(true);return
 end
 local current=Core.chunk(v.item);local session=A.sessions[UI.session_key(v)]
 if session and session.signature~=Core.signature(current) then session=nil end
 A.record=session and session.record or nil;A.baseline=A.record and A.record.before or current
 -- Drawing and its history are global, relative to the selected source. Never
 -- swap them with a per-item draft; only apply/undo records and waveforms vary.
 if session and session.wave then A.wave=session.wave;A.wave_max=session.wave_max else UI.start_wave() end
 A.status='';A.warning=false;UI.dirty(true)
end
function UI.adopt_current()
 if not A.v then return end
 local v=Core.info(A.v.project,A.v.item);if not v then return end
 A.v=v;A.record=nil;A.baseline=Core.chunk(v.item);A.conflict=false;A.warning=false;A.status='';A.selection=nil
 UI.start_wave();UI.dirty(true)
end
function UI.check_current()
 local reason
 if not A.v then reason='音声アイテムを選択してください。'
 elseif R.EnumProjects(-1,'')~=A.v.project then reason='対象のプロジェクトタブに戻ってください。'
 elseif not Core.valid(A.v.project,A.v.item,A.v.take) then reason='対象が削除されたか、テイクが変わっています。再読み込みしてください。'
 elseif (R.GetPlayStateEx(A.v.project)&5)~=0 then reason='生成は再生・録音を停止してから行ってください。' end
 if reason then notice(reason,true);UI.dirty();return false end
 return true
end
function UI.read_curves()
 if A.busy or A.drag or A.wave_job or not A.v then return end
 if R.EnumProjects(-1,'')~=A.v.project or not Core.valid(A.v.project,A.v.item,A.v.take) then
  notice('対象の音声アイテムを確認してください。',true);return
 end
 local current=Core.chunk(A.v.item);local layers,record,clipped
 if A.record and A.record.layers and Core.signature(current)==Core.signature(A.record.after) then
  layers=Core.copy(A.record.layers);record=A.record
 else
  A.v=Core.info(A.v.project,A.v.item)
  layers,record,clipped=Core.read_curves(A.v,A.point_limit)
 end
 UI.history();A.layers=layers;UI.link_prime();A.record=record;A.baseline=record.before;A.conflict=false
 A.selection=nil;A.hover_node=nil;A.line_preview=nil
 for key,steps in pairs(UI.range_steps) do
  if key~='highpass' and key~='lowpass' then
  for _,p in ipairs(layers[key].points) do
   while math.abs(UI.to_axis(key,p.y))>1.00001 and A.ranges[key]<steps[#steps] do
    for _,r in ipairs(steps) do if r>A.ranges[key] then A.ranges[key]=r;break end end
   end
  end
 end end
 notice(clipped and 'カーブを読み込みました。一部の値は編集範囲の上限・下限に収めています。' or
  record.imported and 'ピッチ・ボリューム・専用HP／LPを読み込みました。既存の速度設定は保持します。' or '生成済みのカーブを読み込みました。',clipped)
 UI.dirty(true)
end
function UI.apply()
 if A.busy or A.drag or not UI.check_current() then return end
 UI.number_commit();UI.link_sync()
 if A.wave_job then notice('波形の読み込み完了を待ってください。',true);return end
 if not A.record and not Core.any(A.layers) and #Core.find_filters(A.v.take)==0 then notice('カーブを描いてから適用してください。',true);return end
 if Core.signature(Core.chunk(A.v.item))~=Core.signature(A.record and A.record.after or A.baseline) then
  -- Adopt genuine external edits and continue this click using the same drawing.
  UI.adopt_current()
  if not UI.check_current() then return end
 end
 A.busy=true;UI.stop_wave()
 local old=A.record
 local record,reason=Core.regenerate(A.v,A.layers,A.point_limit,old)
 A.v=Core.info(A.v.project,A.v.item)
 A.busy=false
 if not record then notice(reason or '適用条件を確認してください。',true);return end
 A.record=record;A.record.layers=Core.copy(A.layers);A.v=Core.info(A.v.project,A.v.item)
 if old and old.source_wave then A.wave=old.source_wave;A.wave_max=old.source_wave_max end
 local st=record.stats;local total=st.markers+st.pitch+st.volume+st.highpass+st.lowpass
 notice(string.format('生成完了：時間 %d点 / エンベロープ %d点%s。',st.markers,total-st.markers,st.reduced and '（上限に合わせて近似）' or '')..(st.filter_clipped and ' ReaEQの周波数範囲に収めました。' or ''),st.filter_clipped);UI.dirty(true)
end
function UI.draft_changed()
 if not A.record or not A.record.layers then return false end
 if A.record.stats and A.record.stats.limit~=A.point_limit then return true end
 for key,c in pairs(A.layers) do local prev=A.record.layers[key]
  if prev and (c.link_offset~=prev.link_offset or not BLT.same(c.link_source,prev.link_source)) then return true end
  if not prev or c.enabled~=prev.enabled or c.kind~=prev.kind or Core.smoothness(c)~=Core.smoothness(prev) or #c.points~=#prev.points then return true end
  for i,p in ipairs(c.points) do local q=prev.points[i];if p.x~=q.x or p.y~=q.y then return true end end
 end;return false
end
function UI.format(key,y)
 if key=='highpass' or key=='lowpass' then local f=Core.frequency(y);return f>=1000 and string.format('%.2f kHz',f/1000) or string.format('%.0f Hz',f) end
 if key=='volume' then return string.format('%+.1f dB',Core.db(y)) end
 if key=='speed' then return string.format('%.2f x',2^(2*y)) end
 return string.format('%+.1f st',24*y)
end
function UI.axis_label(key,y) return UI.format(key,UI.from_axis(key,y)) end
function UI.available(id)
 local editing=not A.busy
 if id=='readcurves' then return editing and A.v~=nil and not A.wave_job and not A.drag end
 if id=='apply' then return editing and not A.drag and A.v~=nil and not A.wave_job and not A.conflict and (A.record~=nil or Core.any(A.layers) or #Core.find_filters(A.v.take)>0) end
 if id=='drawundo' then return editing and #A.history>0 end
 if id=='drawredo' then return editing and #A.redo>0 end
 if id=='clear' or id:match('^tool_') or id:match('^enable_') then return editing end
 return true
end
function UI.fit_text(t,width,size,kind) font(size,kind,false);return BLT.ui.fit(tostring(t),width*scale) end
function UI.generate_chaos() UI.generate_line(true) end
function UI.button(id,title,sub,x,y,w,h,fn,enabled,selected,tone)
 enabled=enabled~=false;local hover=A.hit==id and enabled;local c=tone or C.accent2
 local key=id:match('^range_(.+)$');local child=id=='pattern' or id=='direction' or id=='shape_envelope' or id=='period_shape'
 local dim=(key and not A.layers[key].enabled) or (child and A.tool~='line');if dim then c=C.muted end
 local dy=pressed==id and (gfx.mouse_cap&1)~=0 and 1.5 or 0;y=y+dy
 local a=animate('button_'..id,hover and 1 or 0)
 if id:match('^enable_') and selected then
  gradient(x,y,w,h,UI.theme_color({.15,.45,.8},'accent'),C.panel,.72+.16*a,.75);rect(x,y,w,2,UI.theme_color({.45,.8,1},'focus2'),.9);finish_corners(x,y,w,h,5,false,UI.theme_color({.4,.75,1},'accent2'),.85)

 else
  gradient(x,y,w,h,dim and UI.theme_color({.16,.16,.17},'panel2') or C.panel2,dim and UI.theme_color({.09,.09,.10},'panel') or C.panel,dim and .95 or (.34+.16*a),.92)
  gradient(x,y,w,1,c,c,selected and .68 or (.16+.50*a),.02)
  line(x,y+h,x+w,y+h,C.edge,.46)
  if hover or selected then rect(x,y,id:match('^mode_') and 4 or 2,h,c,selected and .55 or .65) end
  finish_corners(x,y,w,h,6,false,selected and c or C.edge2,enabled and (.28+.35*a) or .16)
 end
 if selected and enabled and id:match('^mode_') then
  rect(x+1,y+1,w-2,h-2,c,.10)
  finish_corners(x,y,w,h,6,false,c,.85)
 end
 if sub then
  label(sub,x+12,y+6,11,enabled and c or C.faint,3,w-24,16,0,true)
  label(title,x+12,y+25,16,enabled and C.text or C.faint,1,w-24,26,0,true)
 else label(title,x,y+2,id=='readcurves' and 16 or 14,dim and C.muted or enabled and ((hover or selected) and C.text or C.muted) or C.faint,1,w,h-3,5,id~='readcurves') end
 register(id,x,y-dy,w,h,fn,'',enabled)
end
function UI.primary()
 local x,y,w,h=482,767,266,52;local enabled=UI.available('apply')
 PrimaryButton.draw(PrimaryButton.painter,x,y,w,h,A.record and '生成を更新' or 'カーブを生成',A.record and 'UPDATE CURVES' or 'GENERATE CURVES',enabled,false,nil,A.hit=='apply',pressed=='apply' and (gfx.mouse_cap&1)~=0,R.time_precise(),BLT.host.active())
 register('apply',x,y,w,h,UI.apply,'',enabled)
end
function UI.canvas_surface()
 local g=UI.graph
 if A.wave_dirty then
  local saveDest=gfx.dest;local oldscale,oldox,oldoy=scale,ox,oy
  gfx.setimgdim(UI.WAVE,g.w,g.h);gfx.dest=UI.WAVE;scale,ox,oy=1,-g.x,-g.y
 BLT.viewport(scale,gfx.ext_retina or 1);  rect(g.x,g.y,g.w,g.h,C.field,1)
  for i=0,8 do local x=g.x+g.w*i/8;line(x,g.y,x,g.y+g.h,C.edge,i%2==0 and .35 or .18) end
  for i=0,8 do local y=g.y+g.h*i/8;line(g.x,y,g.x+g.w,y,C.edge,(i==4 and not A.layers[A.layer].filter) and .56 or .21) end
  local n=#A.wave;local original=A.record and not A.record.imported
  if n>0 then
   for px=0,g.w-1 do
    local u=A.view+px/g.w*A.span;local u2=A.view+(px+1)/g.w*A.span
    local a,b=clamp(floor(u*n)+1,1,n),clamp(ceil(u2*n),1,n);local pk=0
    for j=a,max(a,b) do pk=max(pk,A.wave[j] or 0) end
    local gain=original and 10^(Core.db(Core.at(A.record.layers or A.layers,'volume',u))/20) or 1
    local amplitude=min(.47*g.h,pk/max(.001,A.wave_max)*g.h*.38*gain)
    local c=original and C.accent2 or C.muted
    line(g.x+px,g.y+g.h/2-amplitude,g.x+px,g.y+g.h/2+amplitude,c,original and .40 or .28)
   end
  end
  scale,ox,oy=oldscale,oldox,oldoy; BLT.viewport(scale,gfx.ext_retina or 1);gfx.dest=saveDest;A.wave_dirty=false
 end
 gfx.mode=0;gfx.a=1;gfx.blit(UI.WAVE,1,0,0,0,g.w,g.h,sx(g.x),sy(g.y),g.w*scale,g.h*scale)
end
function UI.output_time(u)
 return A.record and Core.lookup(A.record.map,u,'u','t') or u*(A.v and A.v.len or 0)
end
function UI.curve_screen_u(u)
 -- Keep the editor on the source timeline; generation only maps output audio.
 return u
end
function UI.display_curve(key)
 local c=A.layers[key];local d=A.drag
 if key~=A.layer or not d or d.mode~='transform' or not d.overwritten then return c end
 -- Keep the original points available until release. Both the visible nodes
 -- and the interpolated line use the same reversible deletion preview.
 local points={}
 for _,p in ipairs(c.points) do if not d.overwritten[p] then points[#points+1]=p end end
 return {points=points,kind=c.kind,smoothness=c.smoothness,filter=c.filter,enabled=c.enabled}
end
function UI.curves()
 local g=UI.graph
 for pass=1,2 do for _,d in ipairs(UI.defs) do
  local active=d.key==A.layer
  if (pass==2)==active and (active or A.layers[d.key].enabled) then
   local c=UI.display_curve(d.key);local prev
   for px=0,g.w,2 do
    local u=A.view+px/g.w*A.span
    local y=g.y+g.h*(1-clamp(UI.to_axis(d.key,Core.value(c,u)),-1,1))/2
    if prev then
     if active then UI.thick_line(prev.x,prev.y,g.x+px,y,d.color,c.enabled and .94 or .32,3) end
     line(prev.x,prev.y,g.x+px,y,d.color,c.enabled and (active and .98 or .50) or .19)
    end
    prev={x=g.x+px,y=y}
   end
   if active then
    for _,p in ipairs(c.points) do
     local screen_u=UI.curve_screen_u(p.x)
     if screen_u>=A.view and screen_u<=A.view+A.span then
      local ay=UI.to_axis(d.key,p.y);local x,y=g.x+(screen_u-A.view)/A.span*g.w,g.y+(1-ay)*g.h/2
      if abs(ay)<=1.000001 then disc(x,y,3.5,C.field,1);disc(x,y,2.4,d.color,.95) end
     end
    end
   end
  end
 end end
end
function UI.static()
 UI.theme_sync()
 widgets={};text_queue={};rect(0,0,W,H+22,C.bg)
 gradient(0,0,W,90,C.bg2,C.bg,.22,0,true);
 BLT.title('ENVELOPE CANVAS','WAVEFORM CURVE DRAWING  波形へのカーブ描画ツール',W)
 UI.button('fit','ズーム率リセット',nil,914,101,184,34,function() A.view=0;A.span=1;UI.dirty(true) end,true)
 label(A.v and UI.fit_text(A.v.name,760,16,1) or '',24,105,16,C.text,1,770,27,0,true)
 label('補完処理',24,145,14,C.muted,1,164,22)
 for i,q in ipairs({{'linear','直線'},{'smooth','滑らか'}}) do
  UI.button('interp_'..q[1],q[2],nil,24+(i-1)*84,171,80,30,function() UI.set_interpolation(q[1]) end,not A.busy,Core.smoothness(A.layers[A.layer])==(q[1]=='linear' and 0 or 1),UI.def().color)
 end
 UI.smoothness_slider()
 label('操作モード',24,229,14,C.muted,1,164,22)
 for i,q in ipairs({{'select','範囲選択'},{'free','ペン'}}) do
  UI.button('mode_'..q[1],q[2],nil,24,256+(i-1)*38,164,32,function() UI.set_mode(q[1]) end,not A.busy,A.tool==q[1],UI.def().color)
 end
 -- One aligned enclosure joins the mode header and its indented controls.
 local tone=UI.def().color;local selected=A.tool=='line'
 gradient(24,332,164,252,C.panel2,C.panel,.55,.95)
 rect(24,332,164,252,tone,selected and .065 or .022)
 line(24,332,24,584,tone,selected and .7 or .32);line(188,332,188,584,tone,selected and .55 or .25)
 line(24,584,188,584,tone,selected and .55 or .25)
 UI.button('mode_line','ライン生成',nil,24,332,164,32,function() UI.set_mode('line') end,not A.busy,selected,tone)
 local child_tone=selected and tone or C.muted
 line(32,364,32,544,child_tone,.3)
 for _,y in ipairs({384,416,448,480,512,544}) do line(32,y,39,y,child_tone,.3) end
 UI.button('pattern',UI.pattern_names[A.pattern],nil,40,370,140,28,UI.next_pattern,not A.busy)
 UI.button('direction','方向：'..({'左','両側','右'})[A.direction],nil,40,402,140,28,function() A.direction=A.direction%3+1;UI.dirty() end,not A.busy)
 UI.number_field('period_percent','周期幅',40,434,140,'%')
 UI.button('period_shape',UI.period_names[A.period_shape],nil,40,466,140,28,function() A.period_shape=A.period_shape%3+1;UI.dirty() end,not A.busy)
 UI.number_field('height','最大高さ',40,498,140,'%')
 UI.button('shape_envelope',UI.envelope_names[A.shape_envelope],nil,40,530,140,28,function() A.shape_envelope=A.shape_envelope%3+1;UI.dirty() end,not A.busy)
 label('Alt：位相反転',40,561,12,C.muted,1,140,20,0,false)
 UI.button('readcurves','波形の既存カーブ取得',nil,24,596,164,32,UI.read_curves,UI.available('readcurves'))
 local chaos_hot=A.hit=='chaos' and not A.busy
 BLT.chaosButton(24,640,164,50,not A.busy,chaos_hot,pressed=='chaos' and (gfx.mouse_cap&1)~=0,anim_time,animate('chaos_glow',chaos_hot and 1 or 0))
 register('chaos',24,640,164,50,UI.generate_chaos,'ランダム生成',not A.busy)
 UI.button('drawundo','戻す',nil,24,695,80,30,function() UI.undo_draw(false) end,not A.busy and #A.history>0)
 UI.button('drawredo','やり直す',nil,108,695,80,30,function() UI.undo_draw(true) end,not A.busy and #A.redo>0)
 UI.button('clear','現在のカーブを消去',nil,24,736,164,32,function() UI.clear_curves(false) end,not A.busy)
 UI.button('clear_all','全カーブを消去',nil,24,780,164,32,function() UI.clear_curves(true) end,not A.busy)
 local d=UI.def();label(d.code,212,141,12,d.color,3,130,21,0,true)
 label(d.sub,350,141,12,C.muted,1,230,21)
 right_label(UI.draft_changed() and 'EDITED / 生成で更新' or A.record and 'GENERATED / FX前の概形' or 'SOURCE / DRAW',996,141,11,C.muted,3,true)
 UI.canvas_surface();UI.curves()

 local g=UI.graph
 for i=0,4 do
  local y=1-i*.5;right_label(UI.axis_label(A.layer,y),1100,g.y+i*g.h/4-7,13,d.color,3,false)
 end
 for i=0,4 do label(string.format('%.3f s',UI.output_time(A.view+A.span*i/4)),g.x+g.w*i/4-(i==4 and 90 or 0),548,12,C.muted,3,120,20) end
 label(A.tool=='select' and 'ドラッグ：範囲選択  ·  辺／角：変形  ·  枠内：移動  ·  Delete／枠内右クリック：削除' or A.tool=='line' and '波形上をクリック：カーソル位置からライン生成' or 'ドラッグ：描画／点移動  ·  Shift：直線  ·  Alt：点をつかまず描画  ·  右クリック：点削除',212,573,13,C.muted,1,866,23)
 label('ホイール：ズーム  /  Shift＋ホイール：横移動',212,595,11,C.muted,1,800,18)
 for i,q in ipairs(UI.defs) do
  local x,cy,cw=UI.card_geometry(i);local enabled=A.layers[q.key].enabled
  local tint=enabled and q.color or C.muted
  local hover=A.hit=='layer_'..q.key
  local glow=animate('card_'..q.key,hover and 1 or 0)
  gradient(x,cy,cw,61,enabled and C.panel2 or UI.theme_color({.15,.15,.16},'panel2'),enabled and C.panel or UI.theme_color({.085,.085,.09},'panel'),enabled and (.22+.22*glow) or .95,.92)
  if hover then gradient(x,cy,cw,30,tint,C.panel,.16,.03) end
  rect(x,cy,cw,2,tint,hover and .95 or A.layer==q.key and .65 or .25);finish_corners(x,cy,cw,61,8,false,C.edge2,.3)
  label(q.name,x+8,cy+5,16,enabled and (A.layer==q.key and C.text or C.muted) or C.muted,1,cw-84,24,5,true)
  register('layer_'..q.key,x,cy,cw-74,30,function() A.layer=q.key;A.selection=nil;UI.dirty(true) end,'',true)
  UI.button('copy_'..q.key,'COPY',nil,x+cw-70,cy+4,62,23,function() UI.copy_curve(q.key) end,not A.busy and A.layer~=q.key,false,tint)
  local range=A.ranges[q.key];local range_text=q.key=='highpass' or q.key=='lowpass'
  range_text=range_text and string.format('20Hz–%gkHz',range/1000) or q.key=='speed' and string.format('MAX %.2fx',range) or q.key=='volume' and string.format('MAX +%d dB',range) or string.format('±%d st',range)
  UI.button('range_'..q.key,range_text,nil,x+8,cy+32,cw-70,26,function() end,true,false,tint)
  if q.key~='highpass' and q.key~='lowpass' then
  for _,arrow in ipairs({{-1,x+8},{1,x+cw-86}}) do
   local ax=arrow[2];local delta=arrow[1];local hot=A.hit=='range_arrow_'..q.key..delta
   if hot then rect(ax,cy+32,24,26,tint,.14) end
   local cx=ax+12;local yy=cy+45
   line(cx+delta*3,yy,cx-delta*3,yy-4,tint,.85);line(cx+delta*3,yy,cx-delta*3,yy+4,tint,.85)
   register('range_arrow_'..q.key..delta,ax,cy+32,24,26,function() UI.cycle_range(q.key,delta) end,'',not A.busy)
  end
  end
  UI.button('enable_'..q.key,enabled and 'ON' or 'OFF',nil,x+cw-52,cy+32,44,26,function() if not A.busy then UI.history();A.layers[q.key].enabled=not enabled;UI.dirty() end end,not A.busy,enabled,enabled and UI.theme_color({.35,.70,1},'accent2') or C.muted)
 end
 UI.link_button()
 UI.primary()
 UI.quality_panel()
 if A.point_limit>=512 then label('512点以上：処理が重くなる可能性があります',758,824,12,C.warn,1,340,19) end
 local status=A.status
 if A.wave_job then status=string.format('波形を読み込み中  %d%%',floor(A.wave_job.index/A.wave_job.total*100))

 elseif status=='' then status=A.v and '' or '音声アイテムを選択してください。' end

 BLT.footer(status,A.warning or A.conflict,W,H+22,Core.VERSION)
 flush_text_queue()
end
function UI.thick_line(x,y,x2,y2,c,a,width)
 local dx,dy=x2-x,y2-y;local length=math.sqrt(dx*dx+dy*dy)
 if length<1e-9 then return end
 local nx,ny=-dy/length,dx/length
 for i=0,width-1 do local offset=i-(width-1)/2;line(x+nx*offset,y+ny*offset,x2+nx*offset,y2+ny*offset,c,a) end
end
function UI.icon()
 local bs,bx,by=scale,ox,oy;ox,oy=ox+(W-102)*scale,oy+31*scale;scale=scale*.78

 local x,y=0,0;local colors={UI.defs[1].color,UI.defs[2].color,UI.defs[4].color}
 local breathe=.5+.5*math.sin(anim_time*.55)
 for i=1,6 do
  local phase=anim_time*(.10+(i%3)*.018)+i*1.47
  local px=x+46+math.sin(phase*1.09)*(20+(i%2)*6);local py=y+33+math.cos(phase*.79)*(7+(i%3)*2)
  local rr=10+(i%4)*3+breathe*1.6
  disc(px,py,rr+10,C.accent,.004+.003*breathe);disc(px,py,rr+3,C.accent3,.008+.004*breathe)
 end
 for lane=1,3 do
  local c=colors[lane];local last
  for i=0,24 do local u=i/24;local py=y+16+lane*8+math.sin(u*5+lane*.8)*9
   if last then UI.thick_line(last.x,last.y,x+u*93,py,c,.4,2) end;last={x=x+u*93,y=py}
  end
 end
 if animations_active then icon_clock=icon_clock+frame_dt end
 while icon_clock>.16 and #icon_particles<24 do
  icon_clock=icon_clock-.16;icon_serial=icon_serial+1;local n=icon_serial;local lane=n%3+1
  local a,b,c,d=particle_hash(n,21),particle_hash(n,22),particle_hash(n,23),particle_hash(n,24)
  local u=.10+.80*a
  icon_particles[#icon_particles+1]={x=x+u*93,y=y+16+lane*8+math.sin(u*5+lane*.8)*9,
   age=0,life=2.8+b*1.55,r=.65+a*.75,phase=c*math.pi*2,sway=2+d*3,vy=4+b*4,vx=(c-.5)*4}
 end
 for i=#icon_particles,1,-1 do
  local p=icon_particles[i];p.age=p.age+particle_dt
  if p.age>p.life then table.remove(icon_particles,i) else
   local a=math.sin(math.pi*p.age/p.life)^1.85
   local xx=p.x+p.vx*p.age+math.sin(p.age*.63+p.phase)*p.sway;local yy=p.y-p.vy*p.age
   disc(xx,yy,p.r+8,C.accent,.008*a);disc(xx,yy,p.r+4,C.accent3,.016*a)
   disc(xx,yy,p.r+1.8,C.accent2,.060*a);disc(xx,yy,p.r,C.focus2,.46*a)
  end
 end

 scale,ox,oy=bs,bx,by
end
function UI.soft_lights()
 local glow=UI.theme_color({.28,.64,1},'accent2')
 for i,q in ipairs(UI.defs) do if A.layers[q.key].enabled then
  local cx,cy,cw=UI.card_geometry(i);local x,y=cx+cw-52,cy+32
  for r=1,5 do rect(x-r,y-r,44+2*r,26+2*r,glow,.010*(6-r)) end
 end end
 if A.span<1 or A.view>0 then
  local pulse=.5+.5*math.sin(R.time_precise()*2.5)
  for r=1,8 do rect(914-r,101-r,184+2*r,34+2*r,glow,.018+.035*pulse) end
 end
end
function UI.effects()
 UI.icon();UI.point_highlight();UI.mode_overlay();UI.soft_lights();UI.number_lights()
end
function UI.geometry()
 local content=max(1,gfx.h-Chrome.titleH);local newscale=max(.25,min(gfx.w/W,content/H))
 if newscale~=scale then A.content_dirty=true;A.wave_dirty=true end
 scale=newscale;ox,oy=(gfx.w-W*scale)/2,Chrome.titleH+(content-H*scale)/2-22*scale
 BLT.viewport(scale,gfx.ext_retina or 1); mouse_x,mouse_y=(gfx.mouse_x-ox)/scale,(gfx.mouse_y-oy)/scale
end
function UI.render(now)
 UI.geometry()
 particle_dt=clamp(now-frame_clock,0,.1);frame_clock=now
 animation_speed=A.active and visual_speed(now) or 0;animations_active=animation_speed>0
 frame_dt=particle_dt*animation_speed;anim_time=anim_time+frame_dt
 if now<(A.hover_until or 0) or now<(A.number_flash_until or 0) then A.content_dirty=true end
 if UI.frame_w~=gfx.w or UI.frame_h~=gfx.h then
  UI.frame_w,UI.frame_h=gfx.w,gfx.h;gfx.setimgdim(UI.FRAME,gfx.w,gfx.h);A.content_dirty=true
 end
 if A.content_dirty then
  gfx.dest=UI.FRAME;gfx.mode=0;gfx.set(C.bg[1],C.bg[2],C.bg[3],1);gfx.rect(0,0,gfx.w,gfx.h,1)
  UI.static();gfx.dest=-1;A.content_dirty=false
 end
 -- Never inherit gfx.x/y here: text drawing leaves the cursor near the footer.
 -- An implicit destination shifts the entire cached UI outside the window,
 -- while the separately drawn icon/titlebar still appear in their normal places.
 gfx.dest=-1;gfx.mode=0;gfx.a=1
 gfx.blit(UI.FRAME,1,0,0,0,UI.frame_w,UI.frame_h,0,0,gfx.w,gfx.h)
 UI.effects()
 if inside(UI.graph.x,UI.graph.y,UI.graph.w,UI.graph.h) and A.v and A.active then
  local g=UI.graph;local u=A.view+(mouse_x-g.x)/g.w*A.span;local value=clamp(1-2*(mouse_y-g.y)/g.h,-1,1)
  line(mouse_x,g.y,mouse_x,g.y+g.h,C.accent2,.23);line(g.x,mouse_y,g.x+g.w,mouse_y,C.accent2,.12)
  local s=string.format('%.3fs  /  %s',UI.output_time(u),UI.axis_label(A.layer,value))
  local xx=mouse_x-112;local yy=mouse_y+18
  label(s,xx+7,yy+3,13,UI.def().color,3,210,21,1);flush_text_queue()
 end
 custom_titlebar();gfx.update()
end
function UI.pointer_value(dx,dy)
 local g=UI.graph;local mx,my=mouse_x-(dx or 0),mouse_y-(dy or 0)
 local x=clamp(A.view+(mx-g.x)/g.w*A.span,0,1)
 local y=clamp(1-2*(my-g.y)/g.h,-1,1)
 -- Small, physical-pixel magnet with hysteresis: easy neutral values without
 -- oscillating between snapped/unsnapped positions on adjacent input samples.
 local distance=abs(my-(g.y+g.h/2))*scale
 if not A.layers[A.layer].filter and distance<=(A.center_snap and 9 or 5) then y=0;A.center_snap=true else A.center_snap=false end
 y=UI.from_axis(A.layer,y)
 if (gfx.mouse_cap&8)~=0 and A.tool~='free' then
  if A.layer=='highpass' or A.layer=='lowpass' then y=floor(y*48+.5)/48
  elseif A.layer=='volume' then local d=Core.db(y);d=floor(d+.5);y=d>=0 and d/12 or d/60
  elseif A.layer=='speed' then local rate=floor(2^(2*y)*20+.5)/20;y=math.log(max(.25,rate),2)/2
  else y=floor(y*24+.5)/24 end
 end
 local c=A.layers[A.layer];return x,clamp(y,c.min_y or -1,c.max_y or 1)
end
function UI.point_position(p)
 local g=UI.graph;local u=UI.curve_screen_u(p.x);local ay=UI.to_axis(A.layer,p.y)
 return g.x+(u-A.view)/A.span*g.w,g.y+(1-ay)*g.h/2,u>=A.view-1e-9 and u<=A.view+A.span+1e-9 and abs(ay)<=1
end
function UI.nearest()
 local best,dist=nil,14*14
 for i,p in ipairs(A.layers[A.layer].points) do
  local x,y,visible=UI.point_position(p)
  local dd=((mouse_x-x)*scale)^2+((mouse_y-y)*scale)^2
  if visible and dd<=dist then best,dist=i,dd end
 end;return best
end
function UI.hover_point(index)
 local key=index and A.layer..':'..index or nil
 if key~=A.hover_point_key then
  A.hover_point_key=key;A.hover_node=index;A.point_flash=R.time_precise();UI.dirty()
 end
end
function UI.point_highlight()
 local i=A.hover_node;local p=i and A.layers[A.layer].points[i]
 if not p or not A.active or A.busy then return end
 local x,y,visible=UI.point_position(p);if not visible then return end
 local flash=max(0,1-(R.time_precise()-(A.point_flash or 0))/.22)
 disc(x,y,6/scale,C.field,.95);disc(x,y,4.3/scale,UI.def().color,1)
 if flash>0 then disc(x,y,(4.3+2*flash)/scale,C.focus2,flash*.85) end
end
function UI.activation_press(down)
 if not down or type(gfx.screentoclient)~='function' then return false end
 local sx0,sy0=R.GetMousePosition();local px,py=gfx.screentoclient(sx0,sy0)
 return px and py and px>=0 and px<gfx.w and py>=0 and py<gfx.h
end
function UI.set_mode(mode)
 if A.busy or A.drag then return end
 A.tool=mode;A.selection=nil;A.hover_node=nil;UI.dirty()
end
function UI.copy_curve(target)
 if A.busy or target==A.layer then return end
 UI.history();local src=A.layers[A.layer];local dest=A.layers[target];local pts={}
 for _,p in ipairs(src.points) do pts[#pts+1]={x=p.x,y=clamp(UI.from_axis(target,UI.to_axis(A.layer,p.y)),dest.min_y,dest.max_y)} end
 dest.points=pts;dest.kind=src.kind;dest.smoothness=src.smoothness;dest.enabled=true;UI.dirty()
end
function UI.line_anchor()
 local g=UI.graph;local x,y=mouse_x,mouse_y
 for _,px in ipairs({g.x,g.x+g.w}) do if abs(x-px)*scale<=9 then x=px end end
 for _,py in ipairs({g.y,g.y+g.h/2,g.y+g.h}) do if abs(y-py)*scale<=9 then y=py end end
 return clamp(x,g.x,g.x+g.w),clamp(y,g.y,g.y+g.h)
end
function UI.screen_to_point(x,y)
 local g=UI.graph;local u=A.view+(x-g.x)/g.w*A.span
 return {x=u,y=UI.from_axis(A.layer,1-2*(y-g.y)/g.h)}
end
UI.number_limits={period_percent={1,200,1,0},height={0,200,1,0}}
function UI.number_text(key,value)
 local digits=UI.number_limits[key][4] or 0
 local text=string.format('%.'..digits..'f',value)
 return digits>0 and text:gsub('0+$',''):gsub('%.$','') or text
end
function UI.quality_step(delta)
 if A.busy then return end
 local steps={128,256,512,1024};local index=2
 for i,n in ipairs(steps) do if n==A.point_limit then index=i;break end end
 A.point_limit=steps[clamp(index+delta,1,#steps)]
 UI.dirty()
end
function UI.quality_panel()
 gradient(758,767,280,52,C.panel2,C.panel,.45,.95);finish_corners(758,767,280,52,6,false,C.edge2,.4)
 label('生成ポイント数上限（カーブ毎）',764,770,15,C.muted,1,268,21,1,false)
 label(string.format('%d 点',A.point_limit),802,791,22,C.text,1,192,27,5,false)
 for _,q in ipairs({{-1,768,'<'},{1,998,'>'}}) do
  local delta,x=q[1],q[2];local id='quality_arrow_'..delta
  if A.hit==id then rect(x,790,30,28,C.accent2,.18) end
  label(q[3],x,790,22,C.accent2,1,30,28,5,false)
  register(id,x,790,30,28,function() UI.quality_step(delta) end,'',not A.busy)
 end
end
function UI.number_set(key,raw,flash)
 local spec=UI.number_limits[key];local n=tonumber(raw)
 local invalid=not finite(n)
 if invalid then n=A[key] end
 local factor=10^(spec[4] or 0)
 local v=clamp(n,spec[1],spec[2]);v=floor(v*factor+.5)/factor
 if flash~=false and (invalid or abs(v-n)>1e-8) then
  A.number_flash=A.number_flash or {};A.number_flash[key]=R.time_precise();A.number_flash_until=R.time_precise()+1.35
 end
 A[key]=v;UI.dirty()
end
function UI.number_commit()
 if not A.number_edit then return end
 local e=A.number_edit;A.number_edit=nil;UI.number_set(e.key,e.text)
end
function UI.number_field(key,title,x,y,w,unit)
 local e=A.number_edit;local active=e and e.key==key;local dim=A.tool~='line'
 gradient(x,y,w,28,dim and UI.theme_color({.12,.12,.13},'field') or C.field,dim and UI.theme_color({.085,.085,.095},'panel') or C.panel,.98,.60)
 local hot=A.hit=='number_'..key
 line(x,y,x,y+28,dim and C.muted or UI.def().color,hot and .8 or .35);finish_corners(x,y,w,28,5,false,C.edge2,hot and .65 or .3)
 label(title,x+6,y+5,12,C.muted,1,60,20,0,false)
 if active and e.selected then rect(x+65,y+3,w-83,22,C.focus2,.8) end
 local value=active and e.text or UI.number_text(key,A[key])
 right_label(value,x+w-24,y+5,15,active and e.selected and C.ink or dim and C.muted or C.text,3,true)
 right_label(unit,x+w-4,y+9,10,C.muted,1,false)
 register('number_'..key,x,y,w,28,function() end,'',not A.busy)
end
function UI.number_input(id,down,wheel)
 local key=id and id:match('^number_(.+)$')
 if key and wheel~=0 and not A.busy then
  UI.number_commit();local step=UI.number_limits[key][3]
  local notches=max(1,floor(abs(wheel)/120+.5))
  UI.number_set(key,A[key]+(wheel>0 and 1 or -1)*notches*step);gfx.mouse_wheel=0;return true
 end
 if down and not down_last then
  if A.number_edit then UI.number_commit() end
  if key and not A.busy then A.number_drag={key=key,y=mouse_y,value=A[key]};A.pointer_capture=true end
 end
 local d=A.number_drag
 if not d then return false end
 if down then
  local dy=(d.y-mouse_y)*scale
  if abs(dy)>=3 or d.moved then
   d.moved=true
   local step=UI.number_limits[d.key][3]
   local ticks=dy/3;ticks=(ticks<0 and -1 or 1)*floor(abs(ticks)+.5)
   local raw=d.value+ticks*step;local limits=UI.number_limits[d.key];local clipped=raw<limits[1] or raw>limits[2]
   UI.number_set(d.key,raw,not d.clipped);d.clipped=clipped
  end
 else
  if not d.moved and key==d.key then A.number_edit={key=d.key,text=UI.number_text(d.key,A[d.key]),selected=true} end
  A.number_drag=nil;A.pointer_capture=nil;UI.dirty()
 end
 return true
end
function UI.number_key(k)
 local e=A.number_edit;if not e then return false end
 if k==13 then UI.number_commit()
 elseif k==27 then A.number_edit=nil;UI.dirty()
 elseif k==1 then e.selected=true;UI.dirty()
 elseif k==8 or k==6579564 then e.text=e.selected and '' or e.text:sub(1,-2);e.selected=false;UI.dirty()
 elseif (k>=48 and k<=57) or k==46 or k==45 then
  if e.selected then e.text='';e.selected=false end
  if #e.text<12 then e.text=e.text..string.char(k);UI.dirty() end
 end
 return true
end
function UI.number_lights()
 for key,t in pairs(A.number_flash or {}) do
  local age=R.time_precise()-t;local q=clamp(age/1.35,0,1);local a=1-q*q*(3-2*q)
  if a>0 then local y=key=='period_percent' and 434 or 498
   rect(35,y-5,150,38,UI.theme_color({1,.19,.16},'red'),.06*a);rect(40,y,140,28,UI.theme_color({1,.26,.20},'red'),.28*a)
  end
 end
end
function UI.line_points()
 local g=UI.graph;local x,y=UI.line_anchor();local c=A.layers[A.layer]
 local invert=(gfx.mouse_cap&16)~=0 and -1 or 1
 local cachekey=table.concat({x,y,A.pattern,A.period_percent,A.period_shape,A.height,A.shape_envelope,A.direction,A.layer,A.ranges[A.layer],A.view,A.span,invert,tostring(A.v and A.v.item),tostring(A.record)},':')
 if UI.preview_key==cachekey then return UI.preview_points,UI.preview_ua,UI.preview_ub end
 local full_left=g.x-A.view/A.span*g.w
 local full_right=g.x+(1-A.view)/A.span*g.w
 local left=A.direction==3 and x or full_left;local right=A.direction==1 and x or full_right
 if right-left<1e-7 then return {},0,0 end
 local out={}
 local joined=A.direction==2 and x>full_left+1e-7 and x<full_right-1e-7
 local omit_origin=joined and (A.pattern==2 or A.pattern==4 or (A.pattern==3 and A.shape_envelope==2))
 local origin_jump=joined and ((A.pattern==3 and not omit_origin) or A.pattern==6)
 local single_jump=(A.pattern==3 or A.pattern==6) and A.direction~=2
 if single_jump then out[#out+1]=UI.screen_to_point(x,y) end
 local function side(edge,sign,skip_origin,slot)
  local width=abs(edge-x);if width<1e-7 then return end
  local cycles=100/A.period_percent*width/(full_right-full_left)
  local levels=A.pattern==6 and UI.random_step_levels(slot) or nil
  local pts=Core.pattern(UI.pattern_kinds[A.pattern],cycles,A.height/100,A.shape_envelope,levels,A.period_shape)
  for _,p in ipairs(pts) do if not (skip_origin and p.x==0) and not (single_jump and p.x==0 and abs(p.y)<1e-10) then
   local u=p.x
   -- Preserve both sides of a central step. A left endpoint
   -- at exactly the same x would otherwise be discarded by clean_points.
   if u==0 and ((origin_jump and edge<x) or single_jump) then u=min(1e-5,.01/cycles) end
   local q=UI.screen_to_point(x+(edge-x)*u,y-p.y*sign*invert*g.h/2)
   q.y=clamp(q.y,c.min_y,c.max_y);out[#out+1]=q
  end end
 end
 if A.direction~=3 then side(left,A.direction==2 and -1 or 1,omit_origin or (joined and not origin_jump),'left') end
 if A.direction~=1 then side(right,1,omit_origin,'right') end
 local ua=UI.screen_to_point(left,y).x;local ub=UI.screen_to_point(right,y).x
 -- Remove collinear nodes introduced by clipping or envelope endpoints.
 local generated={points=UI.clean_points(out)};Core.simplify(generated,1e-8)
 UI.preview_key=cachekey;UI.preview_points=generated.points;UI.preview_ua=ua;UI.preview_ub=ub
 return UI.preview_points,ua,ub
end
function UI.stamp_line()
 local pts,ua,ub=UI.line_points();if #pts==0 then return end
 UI.history();local c=A.layers[A.layer];local out={}
 for _,p in ipairs(c.points) do if p.x<ua-1e-8 or p.x>ub+1e-8 then out[#out+1]=p end end
 for _,p in ipairs(pts) do out[#out+1]={x=p.x,y=p.y} end
 c.points=UI.clean_points(out);c.enabled=true;A.selection=nil;UI.dirty()
 UI.reset_line_preview(A.pattern==6)
end
function UI.line_preview()
 if A.tool~='line' or not A.v or not A.active or A.busy then return end
 local g=UI.graph;if not inside(g.x,g.y,g.w,g.h) then return end
 local pts,ua,ub=UI.line_points();if #pts==0 then return end
 local curve={points=pts,kind=A.layers[A.layer].kind,smoothness=A.layers[A.layer].smoothness,filter=A.layers[A.layer].filter};local prev
 for px=0,g.w,2 do
  local p=UI.screen_to_point(g.x+px,g.y)
  if p.x>=ua and p.x<=ub then
   local y=g.y+(1-clamp(UI.to_axis(A.layer,Core.value(curve,p.x)),-1,1))*g.h/2
   if prev then line(prev.x,prev.y,g.x+px,y,UI.def().color,.42) end
   prev={x=g.x+px,y=y}
  else prev=nil end
 end
end

function UI.clean_points(pts)
 table.sort(pts,function(a,b)return a.x<b.x end)
 for i=#pts,2,-1 do if pts[i].x-pts[i-1].x<1e-8 then table.remove(pts,i-1) end end
 if #pts>Core.MAX_POINTS then pts=Core.limit_points(pts,Core.MAX_POINTS) end
 return pts
end
function UI.selection_bounds()
 if not A.selection then return end
 local b={x=math.huge,y=math.huge,r=-math.huge,b=-math.huge};local count=0
 for _,p in ipairs(A.layers[A.layer].points) do if A.selection[p] then
  local x,y=UI.point_position(p);b.x=min(b.x,x);b.r=max(b.r,x);b.y=min(b.y,y);b.b=max(b.b,y);count=count+1
 end end
 if count==0 then A.selection=nil;return end
 if b.r-b.x<8/scale then b.x=b.x-4/scale;b.r=b.r+4/scale end
 if b.b-b.y<8/scale then b.y=b.y-4/scale;b.b=b.b+4/scale end
 return b
end
function UI.box_hit()
 local b=UI.selection_bounds();if not b then return end
 local pad=9/scale;local hx,hy
 if abs(mouse_x-b.x)<=pad then hx='l' elseif abs(mouse_x-b.r)<=pad then hx='r' end
 if abs(mouse_y-b.y)<=pad then hy='t' elseif abs(mouse_y-b.b)<=pad then hy='b' end
 if mouse_x>=b.x-pad and mouse_x<=b.r+pad and mouse_y>=b.y-pad and mouse_y<=b.b+pad then return (hx or '')..(hy or ''),b end
end
function UI.delete_selected()
 if A.tool~='select' or A.busy or A.drag or not A.selection then return end
 local c=A.layers[A.layer];local out={};local count=0
 for _,p in ipairs(c.points) do
  if A.selection[p] then count=count+1 else out[#out+1]=p end
 end
 if count==0 then return end
 if #out==0 then UI.clear_curves(false) else
  UI.history();c.points=out;A.selection=nil;A.hover_node=nil;UI.dirty()
 end
end
function UI.selection_input(down,pressed_now,released_now,in_graph)
 if pressed_now and (in_graph or UI.box_hit()) then
  A.pointer_capture=true
  local handle,b=UI.box_hit()
  if handle~=nil then
   UI.history();local originals={}
   for _,p in ipairs(A.layers[A.layer].points) do if A.selection[p] then local x,y=UI.point_position(p);originals[#originals+1]={p=p,x=x,y=y,u=p.x} end end
   A.drag={mode='transform',handle=handle,box=b,mx=mouse_x,my=mouse_y,originals=originals}
  else local g=UI.graph;local x=clamp(mouse_x,g.x,g.x+g.w);local y=clamp(mouse_y,g.y,g.y+g.h);A.selection=nil;A.drag={mode='marquee',x=x,y=y,r=x,b=y} end
 end
 local d=A.drag
 if down and d then
  if d.mode=='marquee' then local g=UI.graph;d.r=clamp(mouse_x,g.x,g.x+g.w);d.b=clamp(mouse_y,g.y,g.y+g.h)
  elseif d.mode=='transform' then
   local b=d.box;local dx,dy=mouse_x-d.mx,mouse_y-d.my;local l,r,t,bot=b.x,b.r,b.y,b.b
   if d.handle=='' then l=l+dx;r=r+dx;t=t+dy;bot=bot+dy else
    if d.handle:find('l') then l=l+dx elseif d.handle:find('r') then r=r+dx end
    if d.handle:find('t') then t=t+dy elseif d.handle:find('b') then bot=bot+dy end
   end
   for _,o in ipairs(d.originals) do local q=UI.screen_to_point(l+(o.x-b.x)/(b.r-b.x)*(r-l),t+(o.y-b.y)/(b.b-b.y)*(bot-t));o.p.x=q.x;o.p.y=q.y end
   d.overwritten={}
   if d.handle=='' or d.handle:find('[lr]') then
    for _,p in ipairs(A.layers[A.layer].points) do if not A.selection[p] then
     for _,o in ipairs(d.originals) do
      if abs(o.u-o.p.x)>1e-10 and p.x>=min(o.u,o.p.x)-1e-10 and p.x<=max(o.u,o.p.x)+1e-10 then d.overwritten[p]=true;break end
     end
    end end
   end
   table.sort(A.layers[A.layer].points,function(a,b)return a.x<b.x end)
  end;UI.dirty()
 end
 if released_now and d then
  if d.mode=='marquee' then
   A.selection={}
   for _,p in ipairs(A.layers[A.layer].points) do local x,y=UI.point_position(p)
    if x>=min(d.x,d.r) and x<=max(d.x,d.r) and y>=min(d.y,d.b) and y<=max(d.y,d.b) then A.selection[p]=true end
   end
  elseif d.mode=='transform' then
   local g=UI.graph;local out={}
   for _,p in ipairs(A.layers[A.layer].points) do local x,y=UI.point_position(p)
    if not (d.overwritten and d.overwritten[p]) and (not A.selection[p] or (p.x>=0 and p.x<=1 and x>=g.x-1e-7 and x<=g.x+g.w+1e-7 and y>=g.y-1e-7 and y<=g.y+g.h+1e-7)) then out[#out+1]=p end
   end
   if #out==0 then local y=A.layers[A.layer].neutral or 0;out={{x=0,y=y},{x=1,y=y}};A.selection=nil end
   A.layers[A.layer].points=UI.clean_points(out)
  end
  A.drag=nil;A.pointer_capture=nil;UI.dirty()
 end
end
function UI.mode_overlay()
 UI.line_preview()
 local g=UI.graph;local d=A.drag;local b
 if d and d.mode=='marquee' then b={x=min(d.x,d.r),y=min(d.y,d.b),r=max(d.x,d.r),b=max(d.y,d.b)}
 elseif A.tool=='select' then b=UI.selection_bounds() end
 if b then
  rect(b.x,b.y,b.r-b.x,b.b-b.y,C.accent2,.055)
  line(b.x,b.y,b.r,b.y,C.accent2,.9);line(b.x,b.b,b.r,b.b,C.accent2,.9);line(b.x,b.y,b.x,b.b,C.accent2,.9);line(b.r,b.y,b.r,b.b,C.accent2,.9)
  if not d or d.mode~='marquee' then for _,x in ipairs({b.x,(b.x+b.r)/2,b.r}) do for _,y in ipairs({b.y,(b.y+b.b)/2,b.b}) do
   if x~=(b.x+b.r)/2 or y~=(b.y+b.b)/2 then rect(x-3/scale,y-3/scale,6/scale,6/scale,C.accent2,.9) end
  end end end
 end
 if inside(g.x,g.y,g.w,g.h) and A.active then
  if A.tool=='line' then local x,y=UI.line_anchor();for i=1,16 do line(x+(i-1)-8,y+math.sin((i-1)*.55)*4,x+i-8,y+math.sin(i*.55)*4,C.focus2,.95) end
   line(x-4,y-9,x+4,y-9,C.focus2,.8)
  end
 end
end

function UI.interact()
 if BLT.blocked() then down_last=(gfx.mouse_cap&1)~=0;pressed=nil;gfx.mouse_wheel=0;return end

 UI.geometry()
 if gfx.setcursor then
  local mode=A.active and inside(UI.graph.x,UI.graph.y,UI.graph.w,UI.graph.h) and A.tool or 'select'
  if mode=='free' then gfx.setcursor(32512,'env_pencil') elseif mode=='line' then gfx.setcursor(32515) else gfx.setcursor(32512) end
 end
 local down=(gfx.mouse_cap&1)~=0;local right=(gfx.mouse_cap&2)~=0;local wheel=gfx.mouse_wheel or 0
 local hit=nil;for i=#widgets,1,-1 do local w=widgets[i];if inside(w.x,w.y,w.w,w.h) then hit=w;break end end
 local id=hit and hit.id or nil
 if id~=A.hit then A.hit=id;A.content_dirty=true;A.hover_until=R.time_precise()+.35;wake_visuals() end
 local g=UI.graph;local in_graph=inside(g.x,g.y,g.w,g.h)
 local chrome_now=gfx.mouse_y<Chrome.titleH or chrome_resize_hit(gfx.mouse_x,gfx.mouse_y)~=nil or Chrome.drag or Chrome.resize or Chrome.closePressed or Chrome.resetPressed or Chrome.chameleonPressed
 local input_active=A.active or A.pointer_capture or UI.activation_press(down)
 if not input_active or (chrome_now and not A.drag) then
  UI.hover_point(nil)
  if A.drag then A.drag=nil;UI.dirty() end
  down_last=down;A.right_last=right;return
 end
 if UI.smoothness_input(id,down) then down_last=down;A.right_last=right;return end
 if UI.number_input(id,down,wheel) then down_last=down;A.right_last=right;return end
 local nearest=A.tool=='free' and (gfx.mouse_cap&24)==0 and A.v and not A.busy and not A.conflict and UI.nearest() or nil
 UI.hover_point(nearest)
 local graph_hit=in_graph or nearest~=nil
 if wheel~=0 then
  gfx.mouse_wheel=0
  if in_graph and A.v and not A.drag then
   local step=wheel/120
   if (gfx.mouse_cap&8)~=0 then A.view=clamp(A.view-step*A.span*.08,0,1-A.span)
   else
    local anchor=clamp((mouse_x-g.x)/g.w,0,1);local u=A.view+anchor*A.span
    A.span=clamp(A.span*1.25^(-step),1/32,1);A.view=clamp(u-anchor*A.span,0,1-A.span)
   end;UI.dirty(true)
  end
 end
 local select_hit=in_graph or (not hit and inside(g.x-14/scale,g.y-14/scale,g.w+28/scale,g.h+28/scale))
 if A.tool=='select' and A.v and not A.busy and (select_hit or A.drag or UI.box_hit()) then
  if right and not A.right_last and not A.drag then
   local b=UI.selection_bounds()
   if b and inside(b.x,b.y,b.r-b.x,b.b-b.y) then UI.delete_selected() end
  end
  UI.selection_input(down,down and not down_last,not down and down_last,select_hit)
  down_last=down;A.right_last=right;return
 end
 if A.tool=='line' and A.v and not A.busy and in_graph and down and not down_last then
  UI.stamp_line();down_last=down;A.right_last=right;return
 end
 if right and not A.right_last and graph_hit and A.v and not A.busy then
  local i=UI.nearest();if i then UI.history();local c=A.layers[A.layer]
   if i==1 or i==#c.points then c.points[i].y=c.neutral or 0 else table.remove(c.points,i) end;UI.dirty()
  end
 end
 if down and not down_last then
  A.pointer_capture=true;A.center_snap=false
  pressed=hit and UI.available(id) and id or nil;A.content_dirty=true;next_draw_time=0
  if A.tool=='free' and graph_hit and A.v and not A.busy and not A.conflict then
   UI.history();local x,y=UI.pointer_value();local c=A.layers[A.layer]
   c.enabled=true
   if (gfx.mouse_cap&8)~=0 then
    A.drag={mode='straight',x=x,y=y,original=Core.copy(c.points)}
    c.kind='linear';Core.stroke(c,x,y,x,y)
   elseif nearest then
    local px,py=UI.point_position(c.points[nearest]);local u=c.points[nearest].x
    A.drag={mode='node',index=nearest,anchor=(u==0 or u==1) and u or nil,dx=mouse_x-px,dy=mouse_y-py,start_x=mouse_x,start_y=mouse_y}
   else Core.stroke(c,x,y,x,y);A.drag={mode='free',x=x,y=y}
   end;UI.dirty()
  end
 end
 if down and A.drag then
  local d=A.drag;local x,y=UI.pointer_value(d.dx,d.dy);local c=A.layers[A.layer]
  if d.mode=='straight' then
   c.points=Core.copy(d.original);Core.stroke(c,d.x,d.y,x,y);UI.dirty()
  elseif d.mode=='free' then
   if abs(x-d.x)>A.span/g.w*.5 or abs(y-d.y)>.002 then
    Core.stroke(c,d.x,d.y,x,y);d.x,d.y=x,y
    if #c.points>Core.MAX_POINTS then
     local tolerance=.003
     repeat Core.simplify(c,tolerance);tolerance=tolerance*2 until #c.points<=Core.MAX_POINTS
    end;UI.dirty()
   end
  else
   local i=d.index;local p=c.points[i]
   if d.anchor~=nil then x=d.anchor else x=clamp(x,i>1 and c.points[i-1].x+1e-6 or 0,i<#c.points and c.points[i+1].x-1e-6 or 1) end
   if ((mouse_x-d.start_x)*scale)^2+((mouse_y-d.start_y)*scale)^2>4 then d.moved=true end
   if d.moved and (p.x~=x or p.y~=y) then p.x,p.y=x,y;UI.dirty() end
  end
 end
 if not down and down_last then
  if A.drag then
   if A.drag.mode=='straight' then
    local d=A.drag;local x,y=UI.pointer_value();local c=A.layers[A.layer]
    c.points=Core.copy(d.original);Core.stroke(c,d.x,d.y,x,y)
   end
   if A.drag.mode=='free' then Core.simplify(A.layers[A.layer],.0015) end
   A.drag=nil;UI.dirty()
  elseif hit and hit.id==pressed and UI.available(hit.id) then UI.safe(hit.fn);UI.dirty() end
  pressed=nil;A.pointer_capture=nil;A.center_snap=nil;A.content_dirty=true;next_draw_time=0
 end
 down_last=down;A.right_last=right
end
function UI.key(k)
 k=BLT.key(k);if k==0 then return end

 if UI.number_key(k) then return end
 local ctrl=(gfx.mouse_cap&4)~=0;local shift=(gfx.mouse_cap&8)~=0
 if k==27 then
  if A.drag then if A.drag.mode~='marquee' and (A.drag.mode~='smoothness' or A.drag.changed) then A.layers=table.remove(A.history) or A.layers end;A.drag=nil;A.pointer_capture=nil;A.selection=nil;UI.link_prime();UI.dirty() else A.closing=true end
 elseif k==26 or (ctrl and (k==122 or k==90)) then UI.undo_draw(shift)
 elseif k==25 or (ctrl and (k==121 or k==89)) then UI.undo_draw(true)
 elseif k==6579564 or k==127 then UI.delete_selected()
 elseif k==13 then UI.apply()
 elseif k==32 then if A.v and R.EnumProjects(-1,'')==A.v.project then R.Main_OnCommand(40044,0) end
 elseif k>=49 and k<=51 then UI.set_mode(({'select','free','line'})[k-48])
 end
end
function UI.poll(now)
 if now<A.poll_at or A.busy then return end;A.poll_at=now+.05
 local project=R.EnumProjects(-1,'');local selected=Core.first(project)
 if not selected then
  -- Keep the last valid audio target through empty/MIDI-only selection, while
  -- still polling external edits and undo on that target.
  if A.v and A.v.project==project then selected=Core.info(project,A.v.item) end
  if not selected then if A.v then UI.load_selection(false) end;return end
 end
 if not A.v or project~=A.v.project or selected.item~=A.v.item or selected.take~=A.v.take then
  -- Recognize host undo before switching to a different take.
  if A.v and project==A.v.project and selected.item==A.v.item and A.record and Core.signature(A.record.before)~=Core.signature(A.record.after) and Core.signature(Core.chunk(selected.item))==Core.signature(A.record.before) then
   A.v=selected;A.record=nil;A.baseline=Core.chunk(selected.item);A.conflict=false;UI.start_wave()
  else UI.load_selection(false,selected) end
  return
 end
 local revision=R.GetProjectStateChangeCount(A.v.project)
 if revision~=A.revision then
  A.revision=revision;local current=Core.signature(Core.chunk(A.v.item));local expected=Core.signature(A.record and A.record.after or A.baseline)
  if A.record and current==Core.signature(A.record.before) and current~=Core.signature(A.record.after) then
   A.v=Core.info(A.v.project,A.v.item);A.record=nil;A.baseline=Core.chunk(A.v.item);A.conflict=false;UI.start_wave()
  elseif not A.record and current~=expected then
   A.v=selected;A.baseline=Core.chunk(selected.item);A.conflict=false;UI.start_wave()
  elseif current~=expected then UI.adopt_current() end
 end
end
-- Store preferences only: drawing points and audio targets belong to the session.
function UI.settings_schema()
 if UI.preference_schema then return UI.preference_schema end
 local schema={
  tool={values={'select','free','line'}},layer={values={'pitch','tape','speed','volume','highpass','lowpass'}},
  direction={values={1,2,3}},pattern={values={1,2,3,4,5,6}},period_percent={min=1,max=200},height={min=0,max=200},
  period_shape={values={1,2,3}},shape_envelope={values={1,2,3}},point_limit={values={128,256,512,1024}},filter_link={boolean=true},link_width={min=.25,max=8}}
 for key,steps in pairs(UI.range_steps) do
  schema['ranges.'..key]={values=steps}
  schema['layers.'..key..'.enabled']={boolean=true}
  schema['layers.'..key..'.kind']={values={'linear','smooth'}}
  schema['layers.'..key..'.smoothness']={min=0,max=2}
 end
 UI.preference_schema=schema;return schema
end
function UI.settings_slot(path)
 local obj=A;local last
 for part in path:gmatch('[^.]+') do if last then obj=obj[last] end;last=part end
 return obj,last
end
function UI.save_settings()
 local rows={'version=1'}
 for path in pairs(UI.settings_schema()) do
  local obj,key=UI.settings_slot(path);local value=obj[key]
  if value~=nil then rows[#rows+1]=path..'='..tostring(value) end
 end
 BLT.store(SECTION,'preferences_v1',table.concat(rows,'\n'),true)
end
function UI.load_settings()
 local data=R.GetExtState(SECTION,'preferences_v1')
 if not data or not data:match('^version=1\n') then return end
 local schema=UI.settings_schema()
 for path,raw in data:gmatch('([^=\n]+)=([^\n]*)') do
  local spec=schema[path]
  if spec then
   local value,valid
   if spec.boolean then value=raw=='true';valid=raw=='true' or raw=='false'
   elseif spec.values then
    for _,v in ipairs(spec.values) do if tostring(v)==raw then value=v;valid=true;break end end
   else value=tonumber(raw);valid=finite(value) and value>=spec.min and value<=spec.max end
   if valid then local obj,key=UI.settings_slot(path);obj[key]=value end
  end
 end
 for key in pairs(UI.number_limits) do UI.number_set(key,A[key],false) end
 UI.link_prime()
end
function UI.close()
 -- Teardown errors must not leave a dead graphics window on screen.
 local ok,err=xpcall(function()
 if A.closed then return end;UI.save_settings();A.closed=true;UI.stop_wave();clear_chrome_tooltip();titlebar_cleanup()
 local _,x,y,w,h=gfx.dock(-1,0,0,0,0)
 for key,v in pairs({window_x=x,window_y=y,window_w=w,window_h=h}) do if finite(v) then BLT.store(SECTION,key,tostring(floor(v+.5)),true) end end
 gfx.quit()
 end,debug.traceback)
 if not ok then
  A.closed=true
  pcall(gfx.quit)
  if R.TrackCtl_SetToolTip then pcall(R.TrackCtl_SetToolTip,'',0,0,true) end
  BLT.logError(err)
 end
end
function UI.loop()
 BLT.tick(R.time_precise());PrimaryButton.tick(R.time_precise(),BLT.host.active(),PrimaryButton.wake)

 if A.closing then UI.close();return end
 local k=BLT.key(gfx.getchar());if k<0 then UI.close();return end
 local now=R.time_precise()
 UI.safe(function()
  local flags=gfx.getchar(65537);local active=(flags&1)==0 or (flags&2)~=0
  if active~=A.active then A.active=active;A.content_dirty=true;wake_visuals(now);next_draw_time=0;A.revision=nil end
  local button_changed=gfx.mouse_cap~=last_raw_mouse_cap
  local changed=gfx.mouse_x~=last_raw_mouse_x or gfx.mouse_y~=last_raw_mouse_y or gfx.mouse_cap~=last_raw_mouse_cap or (gfx.mouse_wheel or 0)~=0
  if changed or k>0 then wake_visuals(now) end
  -- The app bar consumes input during render; never drop a press/release
  -- merely because it arrived between animation frames.
  if button_changed then next_draw_time=0 end
  last_raw_mouse_x,last_raw_mouse_y,last_raw_mouse_cap=gfx.mouse_x,gfx.mouse_y,gfx.mouse_cap
  local count=0;while k>0 and count<32 do UI.key(k);count=count+1;k=gfx.getchar() end
  if k<0 then A.closing=true;return end
  UI.poll(now)
  if Chameleon.tick(now) then UI.dirty(true) end

  if gfx.w~=last_window_w or gfx.h~=last_window_h then last_window_w,last_window_h=gfx.w,gfx.h;UI.dirty(true) end
  -- Input runs on each defer tick; animated presentation is capped independently.
  UI.geometry()
  UI.interact()
  -- Work is budgeted after input, so a new click never waits for waveform IO.
  if A.wave_job and R.EnumProjects(-1,'')==A.wave_job.v.project then
   local ok,err=pcall(UI.wave_step);if not ok then UI.stop_wave();notice(tostring(err),true) end
  end
  local speed=A.active and visual_speed(now) or 0
  local motion_active=A.drag or A.number_drag or now<(A.number_flash_until or 0) or Chrome.drag or Chrome.resize
  local interval=motion_active and 1/60 or speed>0 and 1/30 or (#icon_particles>0) and 1/20 or nil
  if ((redraw_dirty or A.content_dirty or interval) and now>=next_draw_time) or (not interval and (redraw_dirty or A.content_dirty)) then
   UI.render(now);next_draw_time=now+(interval or 4);redraw_dirty=false
  end
  if Chrome.requestReset then Chrome.requestReset=false;reset_window_size();UI.dirty(true) end
  if Chrome.requestClose then A.closing=true end
 end)
 if A.closing then UI.close() else R.defer(UI.loop) end
end
function BLT.preferences() local p=BLT.preferenceView or {};BLT.preferenceView=p;for path in pairs(UI.settings_schema()) do local obj,k=UI.settings_slot(path);p[path]=obj[k];if p[path]==nil then p[path]=path=='link_width' and 1 or path:match('smoothness$') and 1 or nil end end;return p end;BLT.factoryPreferences=BLT.copy(BLT.preferences())
function BLT.captureEnvelope()
 local c=BLT.curveView or {};BLT.curveView=c
 for k,layer in pairs(A.layers) do c[k]=layer.points end
 if not BLT.linkView then
  BLT.emptyLinkPoints={{x=0,y=0}}
  BLT.linkView={highpass={},lowpass={}}
 end
 for key,view in pairs(BLT.linkView) do
  local layer=A.layers[key];local source=layer.link_source
  view.active=source~=nil;view.offset=layer.link_offset or 0
  view.points=source and source.points or BLT.emptyLinkPoints
  view.kind=source and source.kind or 'linear';view.smoothness=source and Core.smoothness(source) or 0
 end
 BLT.envelopeView=BLT.envelopeView or {}
 BLT.envelopeView.settings=BLT.preferences();BLT.envelopeView.curves=c;BLT.envelopeView.linked=BLT.linkView
 return BLT.envelopeView
end
BLT.envelopeDefaults=BLT.copy(BLT.captureEnvelope())
function BLT.validEnvelopeLinks(v)
 for key,link in pairs(v.linked) do
  if (key~='highpass' and key~='lowpass') or (link.kind~='linear' and link.kind~='smooth') or link.smoothness<0 or link.smoothness>2 then return false end
  if math.abs(link.offset)>16*math.log(2)/math.log(4800) or (key=='highpass' and link.offset>0) or (key=='lowpass' and link.offset<0) then return false end
  if link.active then
   if #link.points<2 or #link.points>Core.MAX_POINTS then return false end
   local last=-1
   for _,p in ipairs(link.points) do
    if p.x<0 or p.x>1 or p.x<=last or p.y< -1 or p.y>Core.FILTER_MAX_VALUE then return false end
    last=p.x
   end
  end
 end
 return true
end
function BLT.restoreEnvelopeLinks(v)
 for key,link in pairs(v.linked) do
  local layer=A.layers[key];layer.link_source=nil;layer.link_offset=nil
  if link.active then
   layer.link_source={points=Core.copy(link.points),kind=link.kind,smoothness=link.smoothness,filter=true,enabled=true}
   layer.link_offset=link.offset
  end
 end
end


function BLT.pick(obj,keys) local v=BLT.valueView or {};BLT.valueView=v;for k in pairs(keys) do v[k]=obj[k] end;return v end
PrimaryButton.painter={C=C,gradient=gradient,line=line,rect=rect,corners=finish_corners,disc=disc,label=label}
PrimaryButton.painter.motion=function(now) return (gfx.mouse_x-ox)/scale,(gfx.mouse_y-oy)/scale,visual_speed(now) end
PrimaryButton.wake=function() redraw_dirty=true;A.content_dirty=true;next_draw_time=0 end
BLT.attach({
 chaosPainter={cut=cut_panel,gradient=gradient,disc=disc,line=line,label=label},
 R=R,C=C,Chrome=Chrome,Chameleon=Chameleon,section=SECTION,faces=fonts,font=font,
 geometry=function() return scale,ox,oy end,active=function() local f=gfx.getchar(65536);return (f&1)==0 or (f&2)~=0 end,
 wake=function() A.content_dirty=true;redraw_dirty=true;next_draw_time=0;wake_visuals() end,
 defaults=BLT.envelopeDefaults,capture=function() return BLT.captureEnvelope() end,
 valid=function(v) if not BLT.validEnvelopeLinks(v) then return false end;local schema=UI.settings_schema();for path,x in pairs(v.settings) do local r=schema[path];if not r then return false end;if r.values then local found=false;for _,a in ipairs(r.values) do if a==x then found=true end end;if not found then return false end elseif not r.boolean and (x<r.min or x>r.max) then return false end end;for k,pts in pairs(v.curves) do local def=A.layers[k];if not def or #pts<2 or #pts>Core.MAX_POINTS then return false end;local last=-1;for _,p in ipairs(pts) do if p.x<0 or p.x>1 or p.x<=last or p.y<def.min_y or p.y>def.max_y then return false end;last=p.x end end;return true end,apply=function(v) UI.history();for path,x in pairs(v.settings) do local obj,k=UI.settings_slot(path);obj[k]=x end;for k,pts in pairs(v.curves) do A.layers[k].points=pts end;BLT.restoreEnvelopeLinks(v);UI.link_prime();UI.save_settings();UI.dirty(true) end,
 localUndo=true,
 busy=function() return A.busy end,commit=function() UI.number_commit();return true end,
 cancelEdit=function() A.number_edit=nil;A.number_drag=nil;A.selection=nil end,editing=function() return A.number_edit~=nil end,
 modal=function() return false end,
 handle=gfx_window_handle,resizeHit=function(x,y) if y<26 and x>=gfx.w-234 then return nil end;return chrome_resize_hit(x,y) end,
 cursor=set_resize_cursor,beginResize=begin_window_resize,resize=update_window_resize,

})
-- Earlier presets contain independent curves and no linked interpolation snapshot.
-- Add only the missing snapshot field; the normal decoder still validates all data.
local decodeEnvelopePreset=BLT.presets.decode
function BLT.presets.decode(data)
 local preset=decodeEnvelopePreset(data);if preset then return preset end
 local prefix=SECTION..'_PRESET_V1\n'
 if type(data)~='string' or data:sub(1,#prefix)~=prefix then return nil end
 local old=BLT.unpack(data:sub(#prefix+1))
 if type(old)~='table' or type(old.values)~='table' or old.values.linked~=nil then return nil end
 old.values.linked=BLT.copy(BLT.envelopeDefaults.linked)
 return decodeEnvelopePreset(prefix..BLT.pack(old))
end

do
 local presets=BLT.presets
 local count=min(200,max(0,tonumber(R.GetExtState(SECTION,'preset_count')) or 0))
 if count>#presets.items then
  local names={};for _,p in ipairs(presets.items) do names[p.name]=true end
  for i=1,count do
   local raw=R.GetExtState(SECTION,'preset_'..i):gsub('%%0A','\n'):gsub('%%0D','\r'):gsub('%%25','%%')
   local p=presets.decode(raw)
   if p and not presets.isFactory(p) and not names[p.name] then presets.items[#presets.items+1]=p;names[p.name]=true end
  end
  table.sort(presets.items,function(a,b)return a.name<b.name end)
 end
end
if ...=='blt_test' then function BLT.testDraw(now) UI.static(now or R.time_precise()) end end
function BLT.drawIcon()
 flush_text_queue();
 local bs,bx,by=scale,ox,oy;ox,oy=ox+(W-102)*scale,oy+31*scale;scale=scale*.78
 UI.icon()
 flush_text_queue();
 scale,ox,oy=bs,bx,by
end

if ...=='blt_test' then return {BLT=BLT,A=A,Core=Core ,UI=UI} end
UI.load_settings()
if ...=='ui_test' then return {Core=Core,A=A,UI=UI,Chameleon=Chameleon,palette=C} end
local chrome_ok,chrome_err=titlebar_api_ready()
if not chrome_ok then Language.mb(BLT.publicError(chrome_err),'Envelope Canvas | 必要な拡張',0);return end
local ww=tonumber(R.GetExtState(SECTION,'window_w')) or W;local wh=tonumber(R.GetExtState(SECTION,'window_h')) or H+Chrome.titleH
ww=clamp(ww,Chrome.minW,2200);wh=clamp(wh,Chrome.minH,1800)
local wx,wy=tonumber(R.GetExtState(SECTION,'window_x')),tonumber(R.GetExtState(SECTION,'window_y'))
-- Match native window/input coordinates in logical points on Mac.
gfx.ext_retina=BLT_MAC and 0 or 1
if finite(wx) and finite(wy) then gfx.init(Chrome.windowTitle,ww,wh,0,wx,wy) else gfx.init(Chrome.windowTitle,ww,wh,0) end
if not apply_custom_window_style(ww,wh) then gfx.quit();Language.mb('カスタムアプリバーを初期化できません。','Envelope Canvas',0);return end
if Chameleon.enabled then Chameleon.refresh(true) end
R.atexit(UI.close);UI.safe(function() UI.load_selection(false) end);UI.loop()
