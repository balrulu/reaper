-- @description MARKER REGION DESK
-- @version 0.5.9
-- @author Balrulu
-- @provides
--   . > ../
-- @changelog
--   BLT SERIES Beta TEST UPLOAD
-- @about
--   BLT SERIES Beta TEST UPLOAD

-- BLT preset transfer limits 1.1.0. Embedded; no runtime dependency.
local BLTPresetLimits={bytes=16777216,stringBytes=2097152,nodes=262144,entries=8192}
function BLTPresetLimits.show(english)
 reaper.MB(english and 'Preset capacity limit exceeded. Export presets individually instead of as a bundle.' or '容量上限オーバーです。一括ではなく個別に保存してください。','BLT PRESET',0)
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

local NAME="MARKER REGION DESK"
local APP_NAME="BLT "..NAME
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

local Language=create_language(reaper,"BLT_MARKER_REGION_DESK",LanguageCatalog)
local R=reaper
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

local Core={MAX_BYTES=16*1024*1024,MAX_ROWS=200000,MAX_NAME=4096}
local min,max,floor=math.min,math.max,math.floor
local function clamp(n,a,b) return max(a,min(b,n)) end
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end

function Core.text(s)
  if type(s)~="string" then error("テキストを取得できません。",0) end
  if #s>Core.MAX_BYTES then error("テキストは16 MiB以内にしてください。",0) end
  if s:sub(1,2)=="\255\254" or s:sub(1,2)=="\254\255" then
    local le=s:byte(1)==255
    if #s%2~=0 then error("UTF-16テキストが途中で切れています。",0) end
    local out={}; local i=3
    local function unit(p) local a,b=s:byte(p,p+1); return le and a+b*256 or b+a*256 end
    while i<=#s do
      local u=unit(i); i=i+2
      if u>=0xD800 and u<=0xDBFF then
        if i>#s then error("UTF-16の文字が不完全です。",0) end
        local low=unit(i); i=i+2
        if low<0xDC00 or low>0xDFFF then error("UTF-16の文字が不正です。",0) end
        u=0x10000+(u-0xD800)*1024+low-0xDC00
      elseif u>=0xDC00 and u<=0xDFFF then error("UTF-16の文字が不正です。",0) end
      out[#out+1]=utf8.char(u)
    end
    s=table.concat(out)
  end
  if s:sub(1,3)=="\239\187\191" then s=s:sub(4) end
  if s:find("\0",1,true) or not utf8.len(s) then error("UTF-8またはBOM付きUTF-16のテキストを使用してください。",0) end
  return s:gsub("\r\n","\n"):gsub("\r","\n")
end
function Core.parser(text)
  text=Core.text(text)
  return {text=text,p=1,rows={},field={},col=1,at_start=true,quoted=false,after_quote=false,
    row_started=false,columns=false,flattened=0,done=false}
end
local function finish_row(j)
  local value=table.concat(j.field)
  if #value>Core.MAX_NAME then error("名前は1行4096バイト以内にしてください。",0) end
  local clean,n=value:gsub("[\n\t]"," ")
  if clean:find("[%z\1-\8\11\12\14-\31\127]") then error("名前に使用できない制御文字があります。",0) end
  if n>0 then j.flattened=j.flattened+1 end
  j.rows[#j.rows+1]=clean
  if #j.rows>Core.MAX_ROWS then error("入力は20万行以内にしてください。",0) end
  j.field={}; j.col=1; j.at_start=true; j.after_quote=false; j.row_started=false
end
function Core.parse_step(j,budget)
  if j.done then return true end
  local last=min(#j.text,j.p+(budget or 65536)-1)
  while j.p<=last do
    local ch=j.text:sub(j.p,j.p); local nextch=j.text:sub(j.p+1,j.p+1)
    if j.quoted then
      if ch=='"' then
        if nextch=='"' then if j.col==1 then j.field[#j.field+1]='"' end; j.p=j.p+1
        else j.quoted=false; j.after_quote=true end
      elseif j.col==1 then j.field[#j.field+1]=ch end
      j.row_started=true
    elseif ch=='\n' then
      finish_row(j)
    elseif ch=='\t' then
      j.col=j.col+1; j.columns=true; j.at_start=true; j.after_quote=false; j.row_started=true
    elseif ch=='"' and j.at_start then
      j.quoted=true; j.at_start=false; j.row_started=true
    else
      if j.after_quote then error("引用符の後に区切り以外の文字があります。入力形式を確認してください。",0) end
      if j.col==1 then j.field[#j.field+1]=ch end
      j.at_start=false; j.row_started=true
    end
    j.p=j.p+1
  end
  if j.p>#j.text then
    if j.quoted then error("閉じられていない引用符があります。テキストの末尾を確認してください。",0) end
    if j.row_started then finish_row(j) end
    j.done=true
  end
  return j.done
end
function Core.parse(text)
  local j=Core.parser(text); while not Core.parse_step(j) do end; return j.rows,j
end

Core.WINDOWS_COMMAND=[[powershell.exe -NoLogo -NoProfile -NonInteractive -STA -WindowStyle Hidden -Command "$ErrorActionPreference='Stop'; [Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false); $text=[string](Get-Clipboard -Raw); [Console]::Write(('RN1 '+[Text.Encoding]::UTF8.GetByteCount($text)+[char]10+$text))"]]
function Core.process_output(output,framed)
  if type(output)~="string" then error("クリップボードを読み込めません。",0) end
  local code,body=output:match("^([%-]?%d+)\r?\n(.*)$")
  if tonumber(code)~=0 then error("クリップボード取得に失敗しました。もう一度コピーして貼り付けてください。",0) end
  if framed then
    local size,payload=body:match("^RN1 (%d+)\r?\n(.*)$")
    if not size or tonumber(size)~=#payload then error("クリップボードの読み込みが不完全です。件数を減らして貼り付けてください。",0) end
    body=payload
  end
  return body
end
function Core.clipboard()
  if type(R.CF_GetClipboard)=="function" then
    local ok,text=pcall(R.CF_GetClipboard,"")
    if ok and type(text)=="string" then return text,"SWS" end
  end
  local os=R.GetOS()
  if os:match("Win") then return Core.process_output(R.ExecProcess(Core.WINDOWS_COMMAND,5000),true),"Windows"
  elseif os:match("OSX") or os:match("macOS") then return Core.process_output(R.ExecProcess("/usr/bin/pbpaste",5000),false),"macOS" end
  error("この環境での貼り付けにはSWSのクリップボード機能が必要です。",0)
end

Core.scope={kind="all",query="",sort=nil,desc=false,exclude_loop=false}
function Core.require_api()
  for _,name in ipairs({"GetNumRegionsOrMarkers","GetRegionOrMarker","GetRegionOrMarkerInfo_Value",
    "SetRegionOrMarkerInfo_Value","GetSetRegionOrMarkerInfo_String","DeleteProjectMarkerByIndex"}) do
    if type(R[name])~="function" then error("選択・表示の連動にはREAPER 7.62以降が必要です。",0) end
  end
end
function Core.collect(project)
  local out={}
  for i=0,R.GetNumRegionsOrMarkers(project)-1 do
    local ptr=R.GetRegionOrMarker(project,i,"")
    if not ptr then error("マーカー／リージョンを取得できません。",0) end
    local function value(key) return R.GetRegionOrMarkerInfo_Value(project,ptr,key) end
    local ok,guid=R.GetSetRegionOrMarkerInfo_String(project,ptr,"GUID","",false)
    local named,name=R.GetSetRegionOrMarkerInfo_String(project,ptr,"P_NAME","",false)
    if not ok or not named or guid=="" then error("マーカー／リージョン情報の取得に失敗しました。",0) end
    local isrgn=value("B_ISREGION")~=0;local pos=value("D_STARTPOS");local ending=value("D_ENDPOS")
    out[#out+1]={index=i,guid=guid,isrgn=isrgn,pos=pos,ending=ending,before=name,id=value("I_NUMBER"),
      color=value("I_CUSTOMCOLOR"),length=isrgn and ending-pos or 0,selected=value("B_UISEL")~=0,
      hidden=value("B_HIDDEN")~=0,visible=value("B_VISIBLE")~=0}
  end
  return out
end
function Core.targets(items)
  local s=Core.scope;local out={};local query=s.query:lower()
  for _,v in ipairs(items) do
    local kind=s.kind=="all" or (s.kind=="region" and v.isrgn) or (s.kind=="marker" and not v.isrgn)
    local loop=s.exclude_loop and v.isrgn and v.before:sub(1,13):upper()=="[BLT:SUSTAIN]"
    if kind and not (s.exclude_loop and loop) and (query=="" or v.before:lower():find(query,1,true)) then out[#out+1]=v end
  end
  do
    local key=s.sort or "pos"
    local descending=s.sort~=nil and s.desc
    local function value(v)
      if key=="isrgn" then return v.isrgn and 1 or 0 end
      return v[key]
    end
    table.sort(out,function(a,b)
      local av,bv=value(a),value(b)
      if av==bv then return a.index<b.index end
      if descending then return av>bv end;return av<bv
    end)
  end
  return out
end
function Core.same(a,b)
  return a and b and a.guid==b.guid and a.id==b.id and a.isrgn==b.isrgn and a.pos==b.pos
    and a.ending==b.ending and a.before==b.before and a.color==b.color
end
function Core.content_matches(project,snapshot)
  for i,v in ipairs(snapshot) do
    local ptr=R.GetRegionOrMarker(project,i-1,"")
    if not ptr then return false end
    local ok,guid=R.GetSetRegionOrMarkerInfo_String(project,ptr,"GUID","",false)
    local named,name=R.GetSetRegionOrMarkerInfo_String(project,ptr,"P_NAME","",false)
    if not ok or not named or guid~=v.guid or name~=v.before
      or (R.GetRegionOrMarkerInfo_Value(project,ptr,"B_ISREGION")~=0)~=v.isrgn
      or R.GetRegionOrMarkerInfo_Value(project,ptr,"D_STARTPOS")~=v.pos
      or R.GetRegionOrMarkerInfo_Value(project,ptr,"D_ENDPOS")~=v.ending
      or R.GetRegionOrMarkerInfo_Value(project,ptr,"I_NUMBER")~=v.id
      or R.GetRegionOrMarkerInfo_Value(project,ptr,"I_CUSTOMCOLOR")~=v.color then return false end
  end
  return true
end
function Core.resolve(project,guid)
  local ptr=R.GetRegionOrMarker(project,-1,guid)
  if not ptr then error("対象が変更されました。一覧を確認してください。",0) end
  return ptr
end
function Core.set_name(project,v,name)
  local ptr=Core.resolve(project,v.guid)
  local ok=R.GetSetRegionOrMarkerInfo_String(project,ptr,"P_NAME",name,true)
  local read,current=R.GetSetRegionOrMarkerInfo_String(project,ptr,"P_NAME","",false)
  return ok and read and current==name
end
function Core.set_flag(project,guid,key,on)
  local ptr=Core.resolve(project,guid)
  R.SetRegionOrMarkerInfo_Value(project,ptr,key,on and 1 or 0)
  if (R.GetRegionOrMarkerInfo_Value(project,ptr,key)~=0)~=on then error("選択／表示状態を変更できませんでした。",0) end
end
function Core.select(project,wanted,defer_redraw)
  local changed={}
  local ok,err=xpcall(function()
    for i=0,R.GetNumRegionsOrMarkers(project)-1 do
      local ptr=R.GetRegionOrMarker(project,i,"")
      if not ptr then error("マーカー／リージョンを取得できません。",0) end
      local read,guid=R.GetSetRegionOrMarkerInfo_String(project,ptr,"GUID","",false)
      if not read or guid=="" then error("マーカー／リージョン情報の取得に失敗しました。",0) end
      local selected=R.GetRegionOrMarkerInfo_Value(project,ptr,"B_UISEL")~=0
      if selected~=(wanted[guid]==true) then
        changed[#changed+1]={guid=guid,selected=selected}
        Core.set_flag(project,guid,"B_UISEL",wanted[guid]==true)
      end
    end
  end,debug.traceback)
  if not ok then for _,v in ipairs(changed) do pcall(Core.set_flag,project,v.guid,"B_UISEL",v.selected) end end
  if #changed>0 then
    if defer_redraw then Core.selection_redraw=true
    else R.UpdateTimeline();R.UpdateArrange() end
  end
  if not ok then error(err,0) end
end
function Core.delete(project,items)
  if R.EnumProjects(-1,"")~=project then return nil,"プロジェクトが変わりました。" end
  local current={};for _,v in ipairs(Core.collect(project)) do current[v.guid]=v end
  local target={}
  for _,v in ipairs(items) do
    if not Core.same(v,current[v.guid]) or not current[v.guid].selected then return nil,"対象が変更されました。選択を確認してください。" end
    target[#target+1]=current[v.guid]
  end
  if #target==0 then return nil,"削除する行を選択してください。" end
  table.sort(target,function(a,b) return a.index>b.index end)
  R.Undo_BeginBlock2(project);R.PreventUIRefresh(1)
  local count=0
  local ok,err=xpcall(function()
    for _,v in ipairs(target) do
      local ptr=Core.resolve(project,v.guid)
      local index=R.GetRegionOrMarkerInfo_Value(project,ptr,"I_INDEX")
      if not R.DeleteProjectMarkerByIndex(project,index) then error("削除に失敗しました。",0) end
      count=count+1
      if R.GetRegionOrMarker(project,-1,v.guid) then error("削除結果を確認できません。",0) end
    end
  end,debug.traceback)
  R.PreventUIRefresh(-1);R.UpdateTimeline();R.UpdateArrange();R.Undo_EndBlock2(project,APP_NAME..": delete markers/regions",-1)
  if not ok then
    if count==0 then return nil,"削除できませんでした。一覧を確認してください。\n"..tostring(err) end
    R.Undo_DoUndo2(project)
    local restored={};for _,v in ipairs(Core.collect(project)) do restored[v.guid]=v end
    for _,v in ipairs(target) do
      if not Core.same(v,restored[v.guid]) then return nil,"削除を中止しましたが復元を確認できません。REAPERのUndo履歴を確認してください。" end
    end
    return nil,"削除を中止し、変更をUndoで復元しました。\n"..tostring(err)
  end
  return count
end
function Core.rename_rows(items,name_map)
  local rows,changes={},0
  for i,v in ipairs(items) do
    local name=name_map[v.guid]
    if name==nil then name=v.before end
    if #name>Core.MAX_NAME then error("名前は4096バイト以内にしてください。",0) end
    local changed=name~=v.before
    rows[i]={info=v,before=v.before,after=name,change=changed}
    if changed then changes=changes+1 end
  end
  return rows,changes
end

function Core.tsv_cell(value)
  local s=tostring(value)
  if s:find('[\t\r\n"]') or s=="" then return '"'..s:gsub('"','""')..'"' end
  return s
end
function Core.export(items,names_only)
  local lines={}
  if not names_only then lines[1]="種類\tID\t名前\t開始（秒）\t終了（秒）\t長さ（秒）\t色（RGB）" end
  for _,v in ipairs(items) do
    if names_only then lines[#lines+1]=Core.tsv_cell(v.before)
    else
      local color="標準"
      if v.color~=0 then local r,g,b=R.ColorFromNative(v.color);color=string.format("#%02X%02X%02X",r,g,b) end
      local fields={v.isrgn and "Region" or "Marker",string.format("%.0f",v.id),v.before,string.format("%.6f",v.pos),
        v.isrgn and string.format("%.6f",v.ending) or "",v.isrgn and string.format("%.6f",v.length) or "",color}
      for i,f in ipairs(fields) do fields[i]=Core.tsv_cell(f) end
      lines[#lines+1]=table.concat(fields,"\t")
    end
  end
  return table.concat(lines,"\r\n")..(#lines>0 and "\r\n" or "")
end
function Core.write_clipboard(text)
  if #text>Core.MAX_BYTES then error("コピーは16 MiB以内にしてください。対象を絞り込んでください。",0) end
  if type(R.CF_SetClipboard)=="function" then
    R.CF_SetClipboard(text)
    if type(R.CF_GetClipboard)=="function" and Core.text(R.CF_GetClipboard(""))~=Core.text(text) then
      error("クリップボードへの書き込みを確認できませんでした。もう一度コピーしてください。",0)
    end
    return
  end
  if not R.GetOS():match("Win") then error("情報のコピーにはSWSのクリップボード機能が必要です。",0) end
  local path=os.tmpname()
  local ok,err=xpcall(function()
    local f,msg=io.open(path,"wb");if not f then error(msg,0) end
    local written,why=f:write(text);local closed,close_err=f:close()
    if not written or not closed then error(why or close_err or "一時ファイルの作成に失敗しました。",0) end
    local quoted=path:gsub("'","''")
    if quoted:find('["\r\n]') then error("一時ファイルのパスが無効です。",0) end
    local command=[[powershell.exe -NoLogo -NoProfile -NonInteractive -STA -WindowStyle Hidden -Command "$ErrorActionPreference='Stop'; $t=[IO.File]::ReadAllText(']]..quoted..[[',[Text.Encoding]::UTF8); Set-Clipboard -Value $t; if ((Get-Clipboard -Raw) -cne $t) { throw 'Clipboard verification failed' }"]]
    Core.process_output(R.ExecProcess(command,5000),false)
  end,debug.traceback)
  local removed=os.remove(path)
  if not removed then
    local check=io.open(path,'rb')
    if check then
      check:close()
      if ok then error('クリップボード用一時ファイルを削除できませんでした。',0) end
    end
  end
  if not ok then error(err,0) end
end

function Core.preflight(project,items)
  if R.EnumProjects(-1,"")~=project then return nil,"プロジェクトが変わりました。対応関係を確認してください。" end
  local current=Core.targets(Core.collect(project),project)
  if #current~=#items then return nil,"対象が変わりました。対応関係を確認してください。" end
  for i,v in ipairs(items) do
    if not Core.same(v,current[i]) then return nil,"マーカー／リージョンが変更されました。対応関係を確認してください。" end
  end
  return true
end
function Core.apply(project,items,rows)
  local ok,err=Core.preflight(project,items); if not ok then return nil,err end
  local changes={}; for _,row in ipairs(rows) do if row.change then changes[#changes+1]=row end end
  if #changes==0 then return nil,"変更予定がありません。" end
  local touched={}
  R.Undo_BeginBlock2(project); R.PreventUIRefresh(1)
  local success,detail=xpcall(function()
    for _,row in ipairs(changes) do
      touched[#touched+1]=row
      local set=Core.set_name(project,row.info,row.after)
      if not set then error(string.format("名前の設定結果を確認できません（%s ID %.0f）。",row.info.isrgn and "リージョン" or "マーカー",row.info.id),0) end
    end
  end,debug.traceback)
  local restored=true
  if not success then
    for i=#touched,1,-1 do
      local row=touched[i]
      local call,result=pcall(function()
        return Core.set_name(project,row.info,row.before)
      end)
      if not call or not result then restored=false end
    end
  end
  R.PreventUIRefresh(-1); R.UpdateArrange()
  R.Undo_EndBlock2(project,success and APP_NAME..": marker and region names" or APP_NAME..": restored after failure",8)
  if not success then
    R.ShowConsoleMsg(APP_NAME..":\n"..BLT.publicError(detail).."\n")
    return nil,restored and "変更に失敗したため、元の名前に戻しました。" or "復元に失敗した項目があります。REAPERのUndoで戻してください。"
  end
  return #changes
end
local LIST_ROWS=21
local SECTION="BLT_MARKER_REGION_DESK"
Core.scope.exclude_loop=R.GetExtState(SECTION,"exclude_loop")~="0"

local S={seek=R.GetExtState(SECTION,"seek")=="1",move=R.GetExtState(SECTION,"move")=="1"}
local A={project=R.EnumProjects(-1,""),items={},rows={},
  offset=0,focus=nil,pressed=nil,flashes={},selected={},anchor_guid=nil,focus_guid=nil}
local function report_error(text)
  A.blt_status=BLT.publicError(text);A.blt_bad=true;BLT.host.wake()
end
local function persist()
  BLT.store(SECTION,"seek",S.seek and "1" or "0",true);BLT.store(SECTION,"move",S.move and "1" or "0",true)
end
local function rebuild_selection()
  A.focus=nil;A.selected={};A.selected_count=0
  for _,v in ipairs(A.snapshot or {}) do if v.selected then A.selected[v.guid]=true end end
  for i,v in ipairs(A.items) do
    if v.guid==A.focus_guid then A.focus=i end
    if v.selected then A.selected_count=A.selected_count+1 end
  end
end
local function rebuild()
  A.rows={};for i,v in ipairs(A.items) do A.rows[i]={info=v} end
  rebuild_selection()
  local s=Core.scope;A.scope_state={s.kind,s.query,s.sort,s.desc,s.exclude_loop}
end
local function refresh(project,snapshot)
  A.project=project or R.EnumProjects(-1,"");A.snapshot=snapshot or Core.collect(A.project);A.items=Core.targets(A.snapshot)
  A.revision=R.GetProjectStateChangeCount(A.project)
  A.offset=0;A.focus=nil;A.generation=(A.generation or 0)+1
  rebuild()
end
local function scope_change(key,value)
  Core.scope[key]=value
  refresh()
end

local function follow_selection(guid)
  if not guid then return end
  for i,v in ipairs(A.items) do if v.guid==guid then
    A.focus_guid=v.guid;A.focus=i
    if i<=A.offset or i>A.offset+LIST_ROWS then A.offset=max(0,i-1) end
    return
  end end
end
local function sync_selection()
  local project=R.EnumProjects(-1,"")
  local current=Core.collect(project)
  local s=Core.scope;local previous=A.scope_state or {}
  local changed=project~=A.project or #current~=#(A.snapshot or {})
    or s.kind~=previous[1] or s.query~=previous[2] or s.sort~=previous[3]
    or s.desc~=previous[4] or s.exclude_loop~=previous[5]
  local state_changed=false;local newly_selected=nil
  for i,v in ipairs(current) do
    local old=A.snapshot and A.snapshot[i]
    if not Core.same(v,old) then changed=true end
    if not old or v.guid~=old.guid or old.selected~=v.selected or old.hidden~=v.hidden or old.visible~=v.visible then state_changed=true end
    if v.selected and (not old or old.guid~=v.guid or not old.selected) then newly_selected=newly_selected or v.guid end
  end
  if changed then
    if project~=A.project then A.anchor_guid=nil;A.focus_guid=nil end
    refresh(project,current)
  elseif state_changed then
    local by_guid={};for _,v in ipairs(current) do by_guid[v.guid]=v end
    for i,v in ipairs(A.items) do A.items[i]=by_guid[v.guid] end
    A.snapshot=current;rebuild()
  end
  follow_selection(newly_selected)
  return changed or state_changed
end
-- Between full content checks, read only UI flags. Reacquire each handle so no
-- native marker pointer survives deletion, insertion or project switching.
local function poll_selection(now)
  local project=R.EnumProjects(-1,"")
  local revision=R.GetProjectStateChangeCount(project)
  if project~=A.project or revision~=A.revision
    or R.GetNumRegionsOrMarkers(project)~=#A.snapshot then
    local changed=sync_selection()
    A.revision=revision;A.content_poll=now+.12;A.content_deferred=false
    return changed
  end
  local changed,newly_selected=false,nil
  for i,v in ipairs(A.snapshot) do
    local ptr=R.GetRegionOrMarker(project,i-1,"")
    if not ptr then return sync_selection() end
    local selected=R.GetRegionOrMarkerInfo_Value(project,ptr,"B_UISEL")~=0
    local hidden=R.GetRegionOrMarkerInfo_Value(project,ptr,"B_HIDDEN")~=0
    local visible=R.GetRegionOrMarkerInfo_Value(project,ptr,"B_VISIBLE")~=0
    if selected and not v.selected then newly_selected=newly_selected or v.guid end
    if selected~=v.selected or hidden~=v.hidden or visible~=v.visible then changed=true end
    v.selected=selected;v.hidden=hidden;v.visible=visible
  end
  if changed then
    rebuild_selection()
    follow_selection(newly_selected)
  end
  -- Give selection one priority frame, but do not starve content/sort updates
  -- when UI flags keep changing during a drag or another script's operation.
  if now>=(A.content_poll or 0) then
    if changed and not A.content_deferred then
      A.content_deferred=true
    else
      A.content_poll=now+.12;A.content_deferred=false
      if not Core.content_matches(project,A.snapshot) then return sync_selection() or changed end
    end
  end
  return changed
end
local function select_row(guid,mods,no_navigation)
  poll_selection(R.time_precise())
  local index=nil;for i,v in ipairs(A.items) do if v.guid==guid then index=i;break end end
  if not index then return end
  local ctrl=(mods&4)~=0;local shift=(mods&8)~=0;local wanted={}
  if ctrl then for k,v in pairs(A.selected) do wanted[k]=v end end
  if shift then
    local anchor=index;for i,v in ipairs(A.items) do if v.guid==A.anchor_guid then anchor=i end end
    for i=min(anchor,index),max(anchor,index) do wanted[A.items[i].guid]=true end
  elseif ctrl then wanted[guid]=not wanted[guid];A.anchor_guid=guid
  else wanted[guid]=true;A.anchor_guid=guid end
  Core.select(A.project,wanted,true);A.focus_guid=guid
  poll_selection(R.time_precise())
  if not no_navigation and (S.move or S.seek) then
    for _,v in ipairs(A.items) do if v.selected then
      R.SetEditCurPos2(A.project,v.pos,S.move,S.seek)
      if S.seek and (R.GetPlayStateEx(A.project)&1)==0 then R.OnPlayButtonEx(A.project) end
      break
    end end
  end
end
local function select_all_rows()
  sync_selection()
  if #A.items==0 then return end
  A.anchor_guid=A.items[1].guid
  select_row(A.items[#A.items].guid,8)
end
local function clear_row_selection()
  sync_selection()
  Core.select(A.project,{})
  A.anchor_guid=nil;A.focus_guid=nil;A.focus=nil
  sync_selection()
end
local function toggle_visibility(guid)
  sync_selection()
  local target=nil;for _,v in ipairs(A.items) do if v.guid==guid then target=v;break end end
  if not target then return end
  R.Undo_BeginBlock2(A.project)
  local ok,err=pcall(Core.set_flag,A.project,guid,"B_HIDDEN",target.visible)
  R.UpdateTimeline();R.UpdateArrange();R.Undo_EndBlock2(A.project,APP_NAME..": visibility",-1)
  sync_selection()
  if not ok then report_error(tostring(err));return end
  local ptr=Core.resolve(A.project,guid)
  if not target.visible and R.GetRegionOrMarkerInfo_Value(A.project,ptr,"B_VISIBLE")==0 then
    report_error("個別の非表示は解除しました。レーンやREAPERの表示設定も確認してください。")
  end
end
local function delete_selected()
  sync_selection();local items={}
  for _,v in ipairs(A.items) do if v.selected then items[#items+1]=v end end
  if #items==0 then return end
  local n,err=Core.delete(A.project,items)
  refresh();if not n then report_error(err) end
end

local function undo_project()
  local project=R.EnumProjects(-1,"")
  local entry=R.Undo_CanUndo2(project)
  if not entry or entry=="" then return end
  local ok=R.Undo_DoUndo2(project)
  if not ok or ok==0 then report_error("Undoを実行できませんでした。");return end
  refresh()
end
local function sort_column(key)
  sync_selection()
  local s=Core.scope
  if s.sort~=key then s.sort=key;s.desc=false
  elseif not s.desc then s.desc=true
  else s.sort=nil;s.desc=false end
  A.items=Core.targets(A.snapshot);A.offset=0;A.generation=(A.generation or 0)+1;rebuild()
  A.column_flash={key=key,time=R.time_precise()}
end
local function copy_information(names_only,selected_only)
  sync_selection()
  local items={}
  for _,v in ipairs(A.items) do if not selected_only or v.selected then items[#items+1]=v end end
  if #items==0 then return end
  Core.write_clipboard(Core.export(items,names_only))
  A.flashes[names_only and "copy_names" or "copy_info"]=R.time_precise()

end

local function paste_names(selected_only)
  sync_selection()
  local items=A.items;local project=A.project;local selected={}
  for _,v in ipairs(items) do if not selected_only or v.selected then selected[#selected+1]=v end end
  if #selected==0 then return end
  local text=Core.clipboard();local names=Core.parse(text)
  local map={};for i,v in ipairs(selected) do map[v.guid]=names[i] end
  local rows,changes=Core.rename_rows(items,map)
  if selected_only then
    local selected_now={}
    for _,v in ipairs(Core.collect(project)) do if v.selected then selected_now[v.guid]=true end end
    for _,v in ipairs(items) do
      if v.selected~=(selected_now[v.guid]==true) then report_error("選択が変わりました。対象を確認して貼り付け直してください。");return end
    end
  end
  local n,err=0,nil
  if changes>0 then n,err=Core.apply(project,items,rows) end
  refresh()
  if not n then report_error(err) end
end
local function paste_selected() paste_names(true) end
local function context_menu(guid)
  sync_selection()
  local target=nil;for _,v in ipairs(A.items) do if v.guid==guid then target=v;break end end
  if not target then return end
  if not target.selected then select_row(guid,0,true) end
  gfx.x=gfx.mouse_x;gfx.y=gfx.mouse_y
  local action=gfx.showmenu(Language.menu("コピー|一覧情報をコピー|名前を貼り付け"))
  if action==1 then copy_information(true,true)
  elseif action==2 then copy_information(false,true)
  elseif action==3 then paste_selected() end
end
local function guarded(fn)
  local ok,err=xpcall(fn,debug.traceback)
  if not ok then report_error(err); BLT.recoverInput(A,err) end
end

local BASE_W,BASE_H=540,962
local H=BASE_H
local W=BASE_W
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
local widgets,last_down={},false
local drawn_layout=nil
local scroll_drag=nil
local pressed_generation=nil
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

local window_poll_at=0

local function sx(x) return ox+x*scale end
local function sy(y) return oy+y*scale end
local function color(c,a) gfx.set(c[1],c[2],c[3],a or 1) end
local function rect(x,y,w,h,c,a) color(c,a); gfx.rect(sx(x),sy(y),w*scale,h*scale,1) end
local function line(x,y,x2,y2,c,a) color(c,a); gfx.line(sx(x),sy(y),sx(x2),sy(y2),1) end
local function disc(x,y,r,c,a) color(c,a); gfx.circle(sx(x),sy(y),r*scale,1,1) end

local function font(size,kind,bold) BLT.font(size,kind,bold,scale,fonts) end
local function label(text,x,y,size,c,kind,w,h,flags,bold,literal)
  local shown=literal and tostring(text) or Language.message(text)
  font(size,kind,bold); color(c or C.text); gfx.x,gfx.y=sx(x),sy(y)
  if shown~=tostring(text) and w then shown=BLT.ui.fit(shown,w*scale) end
  gfx.drawstr(shown,flags or 0,sx(x+(w or 700)),sy(y+(h or size+8)))
end
local function measure(text,size,kind,bold) font(size,kind,bold);return BLT.metricsFor(Language.message(text))/scale end

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
  line(x,y-2,x2,y2-2,c,.05*strength); line(x,y+2,x2,y2+2,c,.05*strength)
  line(x,y-1,x2,y2-1,c,.12*strength); line(x,y+1,x2,y2+1,c,.12*strength)
  line(x,y,x2,y2,c,.92*strength)
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
local function widget(id,x,y,w,h,fn,enabled)
  widgets[#widgets+1]={id=id,x=x,y=y,w=w,h=h,fn=fn,enabled=enabled~=false}
end

local function draw_background()
  rect(0,0,W,H+22,C.bg)
  disc(W-45,42,180,C.accent,.016)
  disc(5,H-85,150,C.bg2,.030)
  gradient(0,0,W,92,C.bg2,C.bg,.22,0,true)

  line(17,104,17,H-46,C.edge2,.12)
  for y=115,H-52,20 do line(17,y,22,y,C.edge2,.10) end
end
local BACKGROUND_IMAGE=900
local background_cache={}
local function cached_background()
  local cache=background_cache
  if cache.w~=gfx.w or cache.h~=gfx.h or cache.scale~=scale
    or cache.ox~=ox or cache.oy~=oy or cache.width~=W
    or cache.bg~=C.bg or cache.bg2~=C.bg2 or cache.accent~=C.accent or cache.edge2~=C.edge2 then
    gfx.setimgdim(BACKGROUND_IMAGE,gfx.w,gfx.h)
    local dest=gfx.dest
    gfx.dest=BACKGROUND_IMAGE
    gfx.set(C.bg[1],C.bg[2],C.bg[3],1);gfx.rect(0,0,gfx.w,gfx.h,1)
    draw_background()
    gfx.dest=dest
    cache.w=gfx.w;cache.h=gfx.h;cache.scale=scale;cache.ox=ox;cache.oy=oy;cache.width=W
    cache.bg=C.bg;cache.bg2=C.bg2;cache.accent=C.accent;cache.edge2=C.edge2
  end
  local mode=gfx.mode
  gfx.mode=2;gfx.a=1
  gfx.blit(BACKGROUND_IMAGE,1,0,0,0,gfx.w,gfx.h,0,0,gfx.w,gfx.h)
  gfx.mode=mode
end

local function small_button(id,text,x,y,w,h,fn,enabled,strong_edge)
  enabled=enabled~=false
  local hovered=inside(x,y,w,h) and enabled
  local pressed=A.pressed==id and (gfx.mouse_cap&1)~=0 and enabled
  local stamp=A.flashes[id];local flash=stamp and max(0,1-(R.time_precise()-stamp)/.65) or 0
  if pressed then y=y+2 end
  local a=animate("small_"..id,hovered and 1 or 0)
  gradient(x,y,w,h,C.panel2,C.panel,.34+.16*a,.88)
  gradient(x,y,w,1,C.accent2,C.accent2,.16+.50*a,.02)
  line(x,y+h,x+w,y+h,C.edge,.46)
  if a>.01 then rect(x,y,2,h,C.accent2,.65*a) end
  local ea=(strong_edge and .58 or .28)+(strong_edge and .26 or .35)*a
  finish_corners(x,y,w,h,6,false,strong_edge and C.accent2 or C.edge2,ea)
  if strong_edge then
    line(x+5,y,x+w-8,y,C.accent2,.34+.26*a)
    line(x,y+4,x,y+h-6,C.accent2,.24+.24*a)
  end
  if id=="reset" then rect(x+1,y+1,w-2,h-2,C.accent3,.40) end
  if pressed or flash>0 then
    rect(x+1,y+1,w-2,h-2,C.accent2,pressed and .44 or .50*flash)
    line(x+1,y+1,x+w-1,y+1,C.focus2,pressed and 1 or flash)
    line(x+1,y+h-1,x+w-1,y+h-1,C.focus2,pressed and 1 or flash)
  end
  if flash>0 and (id=="copy_names" or id=="copy_info") then text="コピーしました" end
  label(text,x,y+2,14,enabled and C.text or C.muted,1,w,h-3,5,true)
  widget(id,x,pressed and y-2 or y,w,h,fn,enabled)
end

local function scroll_button(id,text,x,y,w,fn,enabled)
  local hovered=enabled and inside(x,y,w,30)
  local pressed=hovered and A.pressed==id and (gfx.mouse_cap&1)~=0
  if hovered then rect(x,y+3,w,24,C.panel2,pressed and .85 or .55) end
  label(text,x,y+(pressed and 1 or 0),13,hovered and C.text or C.muted,1,w,30,5,false)
  widget(id,x,y,w,30,fn,enabled)
end

local function segment_button(id,text,x,y,w,h,active,fn,enabled)
  enabled=enabled~=false
  local hovered=inside(x,y,w,h) and enabled
  local a=animate("segment_"..id,active and 1 or (hovered and .28 or 0))
  rect(x,y,w,h,C.panel,.98)
  gradient(x,y,w,h,C.accent3,C.panel,(active and .38 or .22)*a,0)
  if active then
    gradient(x+2,y+2,w-5,h-5,C.accent,C.accent3,.16,.015,true)
    rect(x+1,y+5,2,h-10,C.accent2,.82)
    glow_line(x+10,y+1,x+w-12,y+1,C.accent2,.30)
  end
  line(x,y+h-1,x+w,y+h-1,C.edge2,.20+.58*a)
  if active then glow_line(x+12,y+h-1,x+w-12,y+h-1,C.accent2,.34) end
  finish_corners(x,y,w,h,6,false,active and C.accent2 or C.edge2,active and .66 or (.22+.42*a))
  label(text,x,y+3,14,enabled and C.text or C.muted,1,w,h-5,5,true)
  widget(id,x,y,w,h,fn,enabled)
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
  chameleonPressed=false,resizeCursors={},resizeCursorMode=nil,titleH=26,windowTitle=APP_NAME,titleText='M A R K E R   R E G I O N   D E S K',
  minW=486,minH=500,mint={0.38,0.88,0.72},ice={0.65,0.895,1.0},red={1.0,0.27,0.34},
  isWindows=R.GetOS():match("Win")~=nil,resizeEdge=6,resizeCornerBand=8,resizeCornerSpan=24,resizeTopLeftGuard=30,resizeTopRightGuard=110,
  tooltipHover=nil,tooltipSince=0,tooltipVisible=false,tooltipDelay=.70,
  cursorId={we=32644,ns=32645,nwse=32642,nesw=32643,arrow=32512}}
Chrome.font=Chrome.isWindows and "Segoe UI" or (BLT_MAC and "Helvetica Neue" or "sans-serif")
local CHROME_DEFAULT={
  mint={Chrome.mint[1],Chrome.mint[2],Chrome.mint[3]},
  ice={Chrome.ice[1],Chrome.ice[2],Chrome.ice[3]},
}

Chameleon.keys={
  "col_main_bg2","col_main_bg","col_arrangebg","col_tracklistbg","col_mixerbg",
  "genlist_bg","col_tl_bg","col_trans_bg","col_tr1_bg","col_tr2_bg",
  "col_main_editbk","col_transport_editbk","col_buttonbg",

  "col_main_text2","col_main_text","genlist_fg","col_tcp_text",
  "col_toolbar_text","col_toolbar_text_on","col_tl_fg","col_tl_fg2","col_trans_fg",

  "col_seltrack","col_seltrack2","genlist_selbg",
  "col_tl_bgsel","toolbararmed_color","col_main_resize2",
  "selitem_dot","selitem_tag","activetake_tag",
  "col_routinghl1","col_routinghl2","track_lanesolo_tabcol",

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
  local l=clum(bg)
  if l>=0.56 then
    return {0.070,0.075,0.082},false
  elseif l<=0.44 then
    return {0.935,0.945,0.958},true
  end
  if l>=0.50 then return {0.075,0.080,0.088},false end
  return {0.935,0.945,0.958},true
end
local function fit_accent_to_bg(accent,bg,text_is_light)
  local out=ccopy(accent)
  local delta=math.abs(clum(out)-clum(bg))
  if delta>=0.17 then return out end
  if text_is_light then
    local target=math.min(.78,clum(bg)+.28)
    return cshift_luma(out,target)
  end
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
  BLT.store(SECTION,"chameleon",Chameleon.enabled and "1" or "0",true)
  Chameleon.signature=nil

  if Chameleon.enabled then
    Chameleon.refresh(true)
  else
    Chameleon.restore()
    redraw_dirty=true
  end
  wake_visuals(R.time_precise())
end

function Chameleon.tick(now)
  if not Chameleon.enabled or now<Chameleon.poll_at then return false end
  Chameleon.poll_at=now+Chameleon.poll_interval
  return Chameleon.refresh(false)
end

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
  s=math.max(s,.46)

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
  if ok then BLT.position(hwnd,l,t,BASE_W,BASE_H+Chrome.titleH,"","") end
  BLT.store(SECTION,"window_w",tostring(BASE_W),true)
  BLT.store(SECTION,"window_h",tostring(BASE_H+Chrome.titleH),true)
  last_window_w,last_window_h=BASE_W,BASE_H+Chrome.titleH

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

local function custom_titlebar() BLT.bar() end

local marker_particles,marker_clock,marker_serial={},0,0
local particle_source_x={66,67,65}
local particle_source_y={21,38.5,52.5}
local particle_line_y={{21,25},{37,41},{53,57}}
local particle_line_end_x={{99,91},{99,95},{96,88}}
local function list_energy_path(t,lane,subline,slot,spread)
  local u=1-t
  local sx0=particle_source_x[lane];local sy0=particle_source_y[lane]
  local ey=particle_line_y[lane][subline]
  local ex=75+(particle_line_end_x[lane][subline]-75)*slot
  return u*u*u*sx0+3*u*u*t*(sx0+7)+3*u*t*t*(ex-6)+t*t*t*ex,
    u*u*u*sy0+3*u*u*t*(sy0+spread)+3*u*t*t*(ey+spread*.16)+t*t*t*ey
end
local function marker_icon(x,y)
  local ice=C.focus2;local blue=C.accent;local tint=C.accent2
  local breath=.85+.15*math.sin(anim_time*.72)
  for i=7,1,-1 do
    disc(x+64,y+34,3+i*3.3,blue,(.002+(7-i)*.0018)*breath)
    disc(x+75,y+24,2+i*1.7,tint,.0025*breath)
  end
  if animations_active then marker_clock=marker_clock+frame_dt end
  while animations_active and marker_clock>=.060 and #marker_particles<34 do
    marker_clock=marker_clock-.060;marker_serial=marker_serial+1
    local n=marker_serial;local z=particle_hash(n,75)
    marker_particles[#marker_particles+1]={age=0,life=1.05+particle_hash(n,71)*.70,
      lane=1+(n-1)%3,subline=particle_hash(n,69)>.68 and 2 or 1,
      slot=.22+particle_hash(n,70)*.78,spread=(particle_hash(n,72)-.5)*5.5,
      phase=particle_hash(n,73)*6.28,
      radius=.28+z*.77,depth=z,spark=particle_hash(n,74)>.90}
  end
  for i=#marker_particles,1,-1 do
    local p=marker_particles[i];p.age=p.age+particle_dt
    if p.age>=p.life then table.remove(marker_particles,i) end
  end
  local function particles()
    for _,p in ipairs(marker_particles) do
      local t=p.age/p.life;local fade=math.sin(math.pi*t)^2
      local px,py=list_energy_path(t,p.lane,p.subline,p.slot,p.spread)
      py=py+math.sin(t*8+p.phase)*(1-t)*(1-t)*(.7+p.depth*1.1)
      local light=fade*(.25+.55*p.depth)
      local trail=p.spark and .085 or .040
      for j=1,3 do
        local tx,ty=list_energy_path(max(0,t-trail*j/3),p.lane,p.subline,p.slot,p.spread)
        local ex,ey=list_energy_path(max(0,t-trail*(j-1)/3),p.lane,p.subline,p.slot,p.spread)
        line(x+tx,y+ty,x+ex,y+ey,tint,light*(4-j)*.07)
      end
      local settle=clamp((t-.46)/.54,0,1)
      line(x+px-2.6*settle,y+py,x+px+1.1*settle,y+py,tint,.18*light*settle)
      disc(x+px,y+py,p.radius+3.0,blue,.028*fade)
      disc(x+px,y+py,p.radius+1.0,tint,.11*light)
      disc(x+px,y+py,p.radius,ice,.90*light)
      if p.spark then
        local flash=math.sin(math.pi*t)^8*.24
        line(x+px-3,y+py,x+px+3,y+py,ice,flash)
        line(x+px,y+py-1.7,x+px,y+py+1.7,ice,flash*.7)
      end
    end
  end
  local function polygon(points,c,a)
    local cx,cy=0,0
    for _,p in ipairs(points) do cx=cx+p[1];cy=cy+p[2] end
    cx,cy=cx/#points,cy/#points;color(c,a)
    for i=1,#points do
      local p,q=points[i],points[i%#points+1]
      gfx.triangle(sx(x+cx),sy(y+cy),sx(x+p[1]),sy(y+p[2]),sx(x+q[1]),sy(y+q[2]))
    end
  end
  local card={{44,12},{102,12},{110,20},{110,57},{103,64},{44,64},{39,59},{39,17}}
  polygon(card,C.bg,.97)
  polygon({{45,14},{101,14},{108,21},{108,56},{101,62},{45,62},{41,58},{41,18}},C.panel2,.82)

  rect(x+46,y+17,57,11,C.field,.48)
  rect(x+46,y+33,57,11,C.field,.37)
  rect(x+46,y+49,57,10,C.field,.48)
  line(x+44,y+30,x+105,y+30,C.edge2,.22)
  line(x+44,y+46,x+105,y+46,C.edge2,.22)

  glow_line(x+53,y+18,x+53,y+27,tint,.44)
  polygon({{54,18},{66,21},{54,24}},blue,.72)
  line(x+54,y+18,x+66,y+21,ice,.70)
  line(x+66,y+21,x+54,y+24,tint,.48)
  line(x+66,y+21,x+72,y+21,tint,.28)

  rect(x+54,y+36,12,5,blue,.30)
  glow_line(x+53,y+38.5,x+67,y+38.5,tint,.48)
  line(x+53,y+34.5,x+53,y+42.5,ice,.76)
  line(x+67,y+34.5,x+67,y+42.5,ice,.76)
  disc(x+60,y+38.5,1.05,ice,.82)
  line(x+67,y+38.5,x+72,y+38.5,tint,.28)

  line(x+55,y+50,x+55,y+59,tint,.68)
  polygon({{55,50},{65,52.5},{55,55}},tint,.54)
  line(x+55,y+50,x+65,y+52.5,ice,.52)
  line(x+65,y+52.5,x+72,y+52.5,tint,.28)

  glow_line(x+73,y+21,x+99,y+21,tint,.28)
  line(x+73,y+25,x+91,y+25,C.edge2,.40)
  glow_line(x+73,y+37,x+99,y+37,tint,.25)
  line(x+73,y+41,x+95,y+41,C.edge2,.40)
  glow_line(x+73,y+53,x+96,y+53,tint,.26)
  line(x+73,y+57,x+88,y+57,C.edge2,.40)

  glow_line(x+44,y+12,x+102,y+12,ice,.30)
  line(x+102,y+12,x+110,y+20,tint,.64)
  line(x+110,y+20,x+110,y+57,C.edge2,.36)
  glow_line(x+110,y+57,x+103,y+64,tint,.25)
  line(x+103,y+64,x+44,y+64,C.edge2,.28)
  line(x+39,y+59,x+39,y+17,tint,.42)
  disc(x+102,y+12,3.6,tint,.035);disc(x+102,y+12,.65,ice,.92)
  particles()
end

local function display_name(s) return s=="" and "〈空欄〉" or s:gsub("[\r\n\t]"," ") end

local T={x=24,y=180,w=492,h=32+32*LIST_ROWS,row=32,header=32,bar=14}
local function visible() return floor((T.h-T.header)/T.row) end
local function max_offset() return max(0,#A.rows-visible()) end
local function scroll(delta) A.offset=clamp(A.offset+delta,0,max_offset()) end
local open_rename
-- Native project-default formatting follows the active project's primary ruler,
-- including its tempo map, time offset, sample rate and frame-rate settings.
local function update_row_time(row)
  local v=row.info
  local first=R.format_timestr_pos(v.pos,"",-1)
  local last=v.isrgn and R.format_timestr_pos(v.ending,"",-1) or "—"
  local text=row.text
  if not text then
    row.text={string.format("%.0f",v.id),first,last,display_name(v.before)}
    return true
  end
  if text[2]==first and text[3]==last then return false end
  text[2],text[3]=first,last
  return true
end
-- Check only the visible rows, even when idle. A ruler-only change need not
-- alter marker data or the project revision, so content polling is not enough.
local function poll_time_display(now)
  if now<(A.time_display_poll or 0) then return false end
  A.time_display_poll=now+.12
  if R.EnumProjects(-1,"")~=A.project then return false end
  local first=clamp(A.offset,0,max_offset())+1
  local changed=false
  for i=first,min(#A.rows,first+visible()-1) do
    if update_row_time(A.rows[i]) then changed=true end
  end
  return changed
end
local function table_columns()
  local width=clamp(T.time_width or 75,75,max(75,(W-289)/2))
  return {T.x+34,T.x+78,T.x+115,T.x+117+width,T.x+119+2*width},
    {42,35,width,width,W-189-2*width}
end
local fitted_labels,fitted_count={},0
local function fit_label(text,x,y,size,c,w,bold) font(size,1,bold);label(BLT.ui.fit(tostring(text),w*scale),x,y,size,c,1,w,size+8,0,bold,true) end
local function time_label(text,x,y,c,w)
  local size=13.5
  local measured=measure(text,size,1,false)
  if measured>w then size=max(9,size*w/measured) end
  fit_label(text,x,y+(13.5-size)/2,size,c,w,false)
end

local function checkbox(id,text,x,y,w,checked,fn)
  rect(x,y+6,15,15,C.field,.95)
  line(x,y+6,x+15,y+6,C.edge2,.85);line(x,y+21,x+15,y+21,C.edge2,.85)
  line(x,y+6,x,y+21,C.edge2,.85);line(x+15,y+6,x+15,y+21,C.edge2,.85)
  if checked then
    rect(x+1,y+7,13,13,C.accent3,.80)
    line(x+3,y+13,x+6,y+17,C.focus2,1);line(x+6,y+17,x+12,y+10,C.focus2,1)
  end
  if text~="" then label(text,x+23,y+6,11,C.text,1,w-23,23,0,false) end
  widget(id,x,y,w,28,fn,true)
end

local function slide_switch(id,text,x,y,w,on,fn)
 BLT.switch(x,y+3,animate('switch_'..id,on and 1 or 0),true)
 label(text,x+34,y,14,C.text,1,w-34,30,4,true);widget(id,x,y,w,30,fn,true)
end
local IME={active=false}
local function valid_input_text(text,limit)
  return type(text)=='string' and #text<=limit and utf8.len(text)~=nil
    and not text:find('[%z\1-\8\11\12\14-\31\127]')
end
local function flash_input(rename,target)
  local now=R.time_precise()
  if rename and target then A.name_flash={guid=target.guid,time=now} else A.query_flash=now end
  wake_visuals(now);next_draw_time=0
end
local function ime_color(c,alpha)
  return (floor(c[1]*255+.5)<<24)|(floor(c[2]*255+.5)<<16)|(floor(c[3]*255+.5)<<8)|floor((alpha or 1)*255+.5)
end
local function draw_ime_focus(I,ctx,unit)
  local list=I.GetWindowDrawList(ctx)
  local x,y=I.GetItemRectMin(ctx)
  local right,bottom=I.GetItemRectMax(ctx)
  local px=max(.5,unit)
  -- Constant light while editing: no extra timer or animation frames.
  I.DrawList_AddRect(list,x+px*.5,y+px*.5,right-px*.5,bottom-px*.5,ime_color(C.accent2,.90),0,0,px)
  I.DrawList_AddRect(list,x+px*1.5,y+px*1.5,right-px*1.5,bottom-px*1.5,ime_color(C.accent2,.20),0,0,px)
  I.DrawList_AddRect(list,x+px*2.5,y+px*2.5,right-px*2.5,bottom-px*2.5,ime_color(C.accent2,.07),0,0,px)
  I.DrawList_AddRectFilled(list,x+px,y+px,x+px*7,bottom-px,ime_color(C.accent2,.10))
  I.DrawList_AddRectFilled(list,x+px,y+px,x+px*3,bottom-px,ime_color(C.focus2,.95))
end
local function match_name_font(I,ctx,unit,base_size)
  local dpi=I.GetWindowDpiScale(ctx)
  local cached=IME.name_font
  if cached and cached.scale==scale and cached.unit==unit and cached.dpi==dpi then return cached.size end
  -- gfx and ImGui interpret the nominal font size differently. Match measured
  -- glyph advances using the same font family, rather than copying "18".
  local sample="あいうえお漢字ABC012345"
  local target=measure(sample,18,1,false)*unit
  local measured=I.CalcTextSize(ctx,sample)
  local size=measured>0 and clamp(base_size*target/measured,1,96) or base_size
  IME.name_font={scale=scale,unit=unit,dpi=dpi,size=size}
  return size
end
local function draw_name_edit_hint(I,ctx,unit)
  local list=I.GetWindowDrawList(ctx)
  local x,y=I.GetItemRectMin(ctx)
  local right,bottom=I.GetItemRectMax(ctx)
  I.DrawList_AddRectFilled(list,x,bottom-max(.5,unit),right,bottom,ime_color(C.accent2,.48))
end
function IME.stop(restore_focus)
  IME.active=false;IME.ctx=nil;IME.font=nil;IME.target=nil;IME.text=nil;IME.valid_text=nil;IME.mode=nil;IME.name_font=nil;IME.refocus=nil;IME.flash_until=nil;IME.reset_serial=nil
  wake_visuals();next_draw_time=0
  if restore_focus then
    local hwnd=gfx_window_handle()
    if hwnd then R.JS_Window_SetFocus(hwnd) end
  end
end
function IME.finish(commit,restore_focus)
  local target,text=IME.target,IME.text
  IME.stop(restore_focus)
  if not commit or not target or text==target.before then return true end
  if not valid_input_text(text,Core.MAX_NAME) then
    flash_input(true,target)
    report_error("名前が長すぎるか、使用できない制御文字があります。");return false
  end
  local rows,changes=Core.rename_rows(target.items,{[target.guid]=text})
  if changes>0 then
    local n,err=Core.apply(target.project,target.items,rows)
    if not n then report_error(err);sync_selection();return false end
  end
  local offset=A.offset;sync_selection();A.offset=clamp(offset,0,max_offset())
  return true
end
function IME.open(mode,target)
 if not BLT.requireInput(IME) then return false end
  if IME.active then return end
  local ok,err=pcall(function()
    local I=IME.api
    IME.ctx=I.CreateContext(APP_NAME.." input")
    IME.font=I.CreateFont(fonts[1]);I.Attach(IME.ctx,IME.font)
    IME.active=true;IME.frames=0;IME.first=true;IME.mode=mode or "filter"
    IME.target=target;IME.text=target and target.before or Core.scope.query;IME.valid_text=IME.text
  end)
  if not ok then IME.stop(false);report_error("日本語入力欄を初期化できません。\n"..tostring(err)) end
end
function IME.frame()
  if not IME.active then return end
  local I,ctx=IME.api,IME.ctx
  local rename=IME.mode=="rename"
  local left,top,width,height=24,140,W-144,30
  if rename then
    if R.EnumProjects(-1,"")~=IME.target.project then IME.stop(false);return end
    local index
    for i,v in ipairs(A.items) do if v.guid==IME.target.guid then index=i;break end end
    if not index then IME.stop(false);return end
    if index<=A.offset or index>A.offset+visible() then IME.finish(true,false);return end
    local cols,widths=table_columns()
    left,top,width,height=cols[5],T.y+T.header+(index-A.offset-1)*T.row,widths[5]-8,T.row
  end
  local nx,ny=gfx.clienttoscreen(sx(left),sy(top))
  local ex,ey=gfx.clienttoscreen(sx(left+width),sy(top+height))
  local x,y=I.PointConvertNative(ctx,nx,ny)
  local x2,y2=I.PointConvertNative(ctx,ex,ey)
  local w,h=math.abs(x2-x),math.abs(y2-y)
  x,y=min(x,x2),min(y,y2)
  local unit=w/width
  local size=max(8,(rename and 18 or 13)*unit)
  -- A newly submitted ImGui window has no native HWND until the frame ends.
  -- For cell editing, focus on the following frame, after gfx releases capture.
  local focus_now=IME.refocus or rename and IME.frames==1 or (not rename and IME.first)
  IME.refocus=false
  I.SetNextWindowPos(ctx,x,y,I.Cond_Always)
  I.SetNextWindowSize(ctx,w,h,I.Cond_Always)
  if focus_now then I.SetNextWindowFocus(ctx) end
  I.PushStyleVar(ctx,I.StyleVar_WindowPadding,0,0)
  I.PushStyleVar(ctx,I.StyleVar_WindowMinSize,1,1)
  I.PushStyleVar(ctx,I.StyleVar_WindowRounding,0)
  I.PushStyleVar(ctx,I.StyleVar_WindowBorderSize,0)
  I.PushStyleVar(ctx,I.StyleVar_FrameRounding,0)
  I.PushStyleVar(ctx,I.StyleVar_FrameBorderSize,0)
  I.PushStyleVar(ctx,I.StyleVar_FramePadding,rename and max(2,2*unit) or 10*unit,max(0,(h-size)/2))
  I.PushStyleColor(ctx,I.Col_WindowBg,ime_color(C.field))
  local input_flash=IME.flash_until and R.time_precise()<IME.flash_until
  I.PushStyleColor(ctx,I.Col_FrameBg,ime_color(input_flash and {0.65,0.07,0.08} or C.field))
  I.PushStyleColor(ctx,I.Col_Text,ime_color(C.text))
  I.PushStyleColor(ctx,I.Col_TextDisabled,ime_color(C.faint))
  I.PushStyleColor(ctx,I.Col_TextSelectedBg,ime_color(C.accent3))
  I.PushFont(ctx,IME.font,size)
  local flags=I.WindowFlags_NoDecoration|I.WindowFlags_NoMove|I.WindowFlags_NoSavedSettings|I.WindowFlags_NoDocking
  local shown=I.Begin(ctx,rename and "BLT Name IME##BLT_Name_IME" or "BLT Filter IME##BLT_Filter_IME",nil,flags)
  local finish,focused,cancel=false,true,false
  if shown then
    if rename then
      local matched=match_name_font(I,ctx,unit,size)
      I.PopFont(ctx);I.PushFont(ctx,IME.font,matched)
      I.PushStyleVar(ctx,I.StyleVar_FramePadding,max(2,2*unit),max(0,(h-I.GetTextLineHeight(ctx))/2))
    end
    I.SetNextItemWidth(ctx,w)
    if focus_now then I.SetKeyboardFocusHere(ctx) end
    local input_flags=0
    if rename then input_flags=input_flags|I.InputTextFlags_AutoSelectAll end
    local _,text=I.InputTextWithHint(ctx,(rename and "##name" or "##query")..tostring(IME.reset_serial or 0),rename and "" or Language.text("文字列でフィルター…"),rename and IME.text or Core.scope.query,input_flags)
    finish=I.IsItemDeactivated(ctx)
    if rename then
      cancel=finish and I.IsKeyPressed(ctx,I.Key_Escape,false)
      draw_name_edit_hint(I,ctx,unit)
    else draw_ime_focus(I,ctx,unit) end
    -- Invalid backend text never reaches the project or filter. Keep the last
    -- valid value so composition errors revert visibly instead of lingering.
    local limit=rename and Core.MAX_NAME or 1024
    if not valid_input_text(text,limit) then
      flash_input(rename,IME.target)
      IME.flash_until=R.time_precise()+.25;IME.reset_serial=(IME.reset_serial or 0)+1;IME.refocus=true
      report_error(rename and "名前が長すぎるか、使用できない制御文字があります。" or "検索文字列が長すぎるか、使用できない制御文字があります。")
      text=IME.valid_text or (rename and IME.target.before or Core.scope.query);IME.text=text
    else
      IME.valid_text=text;IME.text=text
      if not rename and text~=Core.scope.query then scope_change("query",text);wake_visuals();next_draw_time=0 end
    end
    focused=I.IsWindowFocused(ctx)
    if rename then I.PopStyleVar(ctx) end
    I.End(ctx)
  end
  I.PopFont(ctx);I.PopStyleColor(ctx,5);I.PopStyleVar(ctx,7)
  IME.first=false;IME.frames=IME.frames+1
  if cancel then IME.finish(false,true)
  elseif finish then IME.finish(true,true)
  elseif IME.frames>2 then
    local mx,my=R.GetMousePosition()
    local outside=mx<min(nx,ex) or mx>max(nx,ex) or my<min(ny,ey) or my>max(ny,ey)
    local clicked=(gfx.mouse_cap&1)~=0 or I.IsMouseClicked(ctx,0)
    if not focused or (clicked and outside) then IME.finish(true,false) end
  end
end
open_rename=function(row)
  if not row then return end
  if (gfx.mouse_cap&1)~=0 then
    A.pending_rename={guid=row.info.guid,project=A.project,x=gfx.mouse_x,y=gfx.mouse_y}
    A.last_row_click=nil
    return
  end
  if IME.active and not IME.finish(true,false) then return end
  local guid=row.info.guid
  sync_selection()
  for _,v in ipairs(A.items) do if v.guid==guid then
    A.last_row_click=nil
    IME.open("rename",{guid=guid,before=v.before,project=A.project,items=A.items})
    return
  end end
end
local function release_pending_rename()
  local pending=A.pending_rename
  if not pending then return end
  if R.EnumProjects(-1,"")~=pending.project or math.abs(gfx.mouse_x-pending.x)>6 or math.abs(gfx.mouse_y-pending.y)>6 then
    A.pending_rename=nil;return
  end
  if (gfx.mouse_cap&1)~=0 then return end
  A.pending_rename=nil
  for _,row in ipairs(A.rows) do if row.info.guid==pending.guid then open_rename(row);return end end
end
local function draw_filter()
  local x,y,w,h=24,140,W-144,30
  rect(x,y,w,h,C.field,.98)
  local editing=IME.active and IME.mode=="filter"
  local flash=A.query_flash and max(0,1-(R.time_precise()-A.query_flash)/.85) or 0
  if flash>0 then rect(x-4,y-4,w+8,h+8,C.red,.04*flash);rect(x,y,w,h,C.red,.18*flash) end
  line(x,y+h,x+w,y+h,flash>0 and C.red or (editing and C.accent2 or C.edge2),flash>0 and .95 or (editing and .92 or .40))
  local text=Core.scope.query
  label(text=="" and "文字列でフィルター…" or text,x+10,y+6,13,text=="" and C.faint or C.text,1,w-20,23,0,false,text~="")
  widget("query",x,y,w,h,IME.open,true)
end

local function draw_table()
  A.offset=clamp(A.offset,0,max_offset())
  gradient(T.x,T.y,T.w,T.h,C.field,C.panel,1,.30,true)
  rect(T.x,T.y,T.w,T.header,C.panel2,.94)
  line(T.x,T.y,T.x+T.w,T.y,C.edge2,.65)
  local time_width=75
  for i=A.offset+1,min(#A.rows,A.offset+visible()) do
    local row=A.rows[i];update_row_time(row)
    time_width=max(time_width,math.ceil(measure(row.text[2],13.5,1,false))+4,
      math.ceil(measure(row.text[3],13.5,1,false))+4)
  end
  -- Make room for timecode/samples without moving a live name editor.
  if not (IME.active and IME.mode=="rename") then T.time_width=time_width end
  local cols,widths=table_columns()
  local heads={"種別","ID","開始","終了","名前"}

  label("表示",T.x+2,T.y+7,13,C.text,1,30,20,0,true)
  local keys={"isrgn","id","pos","ending","before"}
  for i=1,5 do
    local key=keys[i];local active=Core.scope.sort==key
    local title=heads[i]..(active and (Core.scope.desc and " ↓" or " ↑") or "")
    if active then rect(cols[i]-2,T.y,widths[i]+2,T.header,C.accent3,.50) end
    local flash=A.column_flash
    if flash and flash.key==key then
      local alpha=max(0,1-(R.time_precise()-flash.time)/.55)
      rect(cols[i]-2,T.y,widths[i]+2,T.h,C.accent2,.22*alpha)
    end
    label(title,cols[i],T.y+7,14,C.text,1,widths[i],20,0,true)
    widget("sort_"..key,cols[i]-2,T.y,widths[i]+2,T.header,function() sort_column(key) end,true)
  end
  for slot=1,visible() do
    local ri=A.offset+slot;local row=A.rows[ri]
    if row then
      local v=row.info;local y=T.y+T.header+(slot-1)*T.row
      local text=row.text
      if v.selected then
        local x,w=T.x+1,T.w-T.bar-1
        gradient(x,y,w,T.row,C.accent3,C.panel,.54,.88)
        gradient(x,y,w,T.row/2,C.accent2,C.accent2,.10,0,true)
        gradient(x,y+T.row/2,w,T.row/2,C.accent2,C.accent2,0,.05,true)
        gradient(x,y,3,T.row,C.focus2,C.accent2,.90,.38,true)
        gradient(x+3,y,13,T.row,C.accent2,C.accent2,.18,0)
        gradient(x+3,y,w-3,1,C.focus2,C.accent2,.50,.05)
        gradient(x+3,y+T.row-1,w-3,1,C.accent2,C.accent2,.27,.02)
      elseif slot%2==0 then rect(T.x+1,y,T.w-T.bar-1,T.row,C.panel,.50) end
      local input_flash=A.name_flash and A.name_flash.guid==v.guid and max(0,1-(R.time_precise()-A.name_flash.time)/.85) or 0
      if input_flash>0 then rect(cols[5]-4,y+2,widths[5],T.row-4,C.red,.22*input_flash) end
      line(T.x+4,y+T.row,T.x+T.w-T.bar,y+T.row,C.edge,.16)
      if v.color~=0 then local r,g,b=R.ColorFromNative(v.color);rect(T.x+3,y+9,3,14,{r/255,g/255,b/255}) end
      label(v.isrgn and "R" or "M",cols[1],y+6,16,v.isrgn and C.accent2 or C.text,3,widths[1],24,0,true)
      fit_label(text[1],cols[2],y+6,16,C.text,widths[2]-2,false)
      time_label(text[2],cols[3],y+7,C.text,widths[3]-2)
      time_label(text[3],cols[4],y+7,v.isrgn and C.text or C.faint,widths[4]-2)
      fit_label(text[4],cols[5],y+4,18,C.text,widths[5]-8,false)
      widget("row_"..ri,T.x+30,y,T.w-T.bar-30,T.row,function()
        local now=R.time_precise()
        local double=A.last_row_guid==v.guid and A.last_row_click and now-A.last_row_click<.4
        local mods=A.click_mods or 0
        local name_click=A.selected[v.guid] and mx>=cols[5] and mx<cols[5]+widths[5]
        if mods==0 and (double or name_click) then
          open_rename(row)
        else
          select_row(v.guid,mods);A.last_row_click=now;A.last_row_guid=v.guid
        end
      end,true)
      checkbox("visible_"..ri,"",T.x+8,y+2,20,v.visible,function() toggle_visibility(v.guid) end)
    end
  end
  local blank_y=T.y+T.header+min(visible(),max(0,#A.rows-A.offset))*T.row
  if blank_y<T.y+T.h then
    widget("list_blank",T.x,blank_y,T.w-T.bar,T.y+T.h-blank_y,clear_row_selection,true)
  end
  if #A.rows==0 then
    local project_empty=#(A.snapshot or {})==0
    local message=project_empty and "プロジェクトにマーカー/リージョンがありません" or "該当するマーカー/リージョンはありません"

  end
  local bx,by,bh=T.x+T.w-T.bar,T.y+T.header,T.h-T.header
  rect(bx,by,T.bar,bh,C.panel,.95)
  local th=#A.rows>0 and max(26,bh*min(1,visible()/#A.rows)) or bh
  local ty=by+(max_offset()>0 and A.offset/max_offset()*(bh-th) or 0)
  rect(bx+4,ty+1,T.bar-8,th-2,scroll_drag and C.accent2 or C.edge2,.70)
  A.scrollbar={x=bx,y=by,w=T.bar,h=bh,thumb_y=ty,thumb_h=th}
end

local function draw()
  local contentH=max(1,gfx.h-Chrome.titleH)
  scale=max(.30,min(gfx.w/BASE_W,1))
  H=contentH/scale
  T.h=max(T.header+T.row,H-258)
  LIST_ROWS=visible();A.offset=clamp(A.offset,0,max_offset())
  W=gfx.w/scale;T.w=W-48
  ox,oy=0,Chrome.titleH-22*scale
 BLT.viewport(scale,gfx.ext_retina or 1);  mx,my=(gfx.mouse_x-ox)/scale,(gfx.mouse_y-oy)/scale
  widgets={};gfx.clear=-1;gfx.set(C.bg[1],C.bg[2],C.bg[3],1);gfx.rect(0,0,gfx.w,gfx.h,1)
  local now=R.time_precise();particle_dt=max(0,min(.10,now-frame_clock));frame_clock=now
  frame_dt=animations_active and particle_dt*animation_speed or 0;anim_time=anim_time+frame_dt
  cached_background()
  BLT.title(NAME,'MARKER / REGION / LOOP LIST  マーカー・リージョン・ループのリスト',W)
  BLT.drawIcon()
  local s=Core.scope
  for i,v in ipairs({{"all","すべて"},{"marker","マーカー"},{"region","リージョン"}}) do
    segment_button("scope_"..v[1],v[2],24+(i-1)*90,102,84,28,s.kind==v[1],function() scope_change("kind",v[1]) end,true)
  end

  slide_switch("exclude_loop","ループリージョンを除外",302,102,212,s.exclude_loop,function()
    scope_change("exclude_loop",not Core.scope.exclude_loop)
    BLT.store(SECTION,"exclude_loop",Core.scope.exclude_loop and "1" or "0",true)
  end)
  draw_filter()
  small_button("reset","クリア",W-108,140,84,30,function()
    Core.scope.kind="all";Core.scope.query=""
    refresh();A.flashes.reset=R.time_precise()
  end,true,true)
  draw_table()

  slide_switch("seek","シーク再生",24,H-72,138,S.seek,function() S.seek=not S.seek;persist() end)
  slide_switch("move","選択位置へ移動",172,H-72,176,S.move,function() S.move=not S.move;persist() end)
  scroll_button("top","↑ 先頭",W-180,H-72,72,function() A.offset=0 end,#A.rows>0)
  scroll_button("bottom","↓ 末尾",W-96,H-72,72,function() A.offset=max_offset() end,#A.rows>0)
  small_button("copy_names","全名前をコピー",24,H-32,142,30,function() copy_information(true) end,#A.items>0,true)
  small_button("copy_info","全情報をコピー",178,H-32,142,30,function() copy_information(false) end,#A.items>0,true)
  small_button("paste_all","名前を貼付（先頭から）",332,H-32,W-356,30,function() paste_names(false) end,#A.items>0,true)

  BLT.footer(A.blt_status or (#A.items==0 and 'マーカー／リージョンがありません。' or string.format('%d件  選択 %d件',#A.items,A.selected_count)),A.blt_bad,W,H+22,'0.5.9')
  custom_titlebar()
  drawn_layout={w=gfx.w,h=gfx.h,generation=A.generation,offset=A.offset}
end
local function interact()
 if BLT.blocked() then last_down=(gfx.mouse_cap&1)~=0;A.pressed=nil;gfx.mouse_wheel=0;return end

  if Chrome.mouseActive then last_down=(gfx.mouse_cap&1)~=0;A.pressed=nil;scroll_drag=nil;return end
  local bar=A.scrollbar;local down=(gfx.mouse_cap&1)~=0
  local right=(gfx.mouse_cap&2)~=0
  do
    local row_id=nil
    for _,w in ipairs(widgets) do
      if w.id:match("^row_%d+$") and inside(w.x,w.y,w.w,w.h) then row_id=tonumber(w.id:match("%d+"));break end
    end
    local guid=row_id and A.rows[row_id] and A.rows[row_id].info.guid
    if right and not A.right_down then A.context_guid=guid end
    if not right and A.right_down then
      local captured=A.context_guid;A.context_guid=nil;A.right_down=false
      if guid and guid==captured then context_menu(guid);A.pressed=nil;return end
    end
  end
  A.right_down=right
  local hit=nil
  for i=#widgets,1,-1 do local w=widgets[i];if inside(w.x,w.y,w.w,w.h) then hit=w;break end end
  if down and not last_down then
    pressed_generation=A.generation;A.click_mods=gfx.mouse_cap&28
    if IME.active and (IME.mode=="rename" or not hit or hit.id~="query") then IME.finish(true,false) end
    if bar and inside(bar.x,bar.y,bar.w,bar.h) then
      if my>=bar.thumb_y and my<=bar.thumb_y+bar.thumb_h then scroll_drag=my-bar.thumb_y
      else scroll(my<bar.thumb_y and -visible() or visible()) end
      A.pressed=nil
    else
      A.pressed=hit and hit.id or nil
      if hit and hit.enabled and hit.id:match("^row_%d+$") then
        hit.fn();A.pressed=nil -- Select on mouse-down; do not repeat on release.
      end
    end
  elseif down and scroll_drag and bar then
    local travel=bar.h-bar.thumb_h
    if travel>0 then A.offset=floor(clamp((my-bar.y-scroll_drag)/travel,0,1)*max_offset()+.5) end
  elseif not down and last_down then
    if not scroll_drag and hit and hit.enabled and hit.id==A.pressed and pressed_generation==A.generation then hit.fn() end
    scroll_drag=nil;A.pressed=nil
  end
  last_down=down
  local wheel=gfx.mouse_wheel or 0
  if wheel~=0 then
    gfx.mouse_wheel=0
    if inside(T.x,T.y,T.w,T.h) then scroll((wheel>0 and -1 or 1)*((gfx.mouse_cap&8)~=0 and visible() or 3)) end
  end
end
local function keypress(k)
 k=BLT.key(k);if k==0 then return end

  if IME.active then return end
  if k==27 then A.manualClose=true;A.closing=true
  elseif k==1 then select_all_rows()
  elseif k==6579564 then delete_selected()
  elseif k==3 then copy_information(true,true)
  elseif k==22 then paste_selected()
  elseif k==13 and A.focus then open_rename(A.rows[A.focus])
  elseif k==1752132965 then A.offset=0
  elseif k==6647396 then A.offset=max_offset()
  elseif k==1885828464 then scroll(-visible())
  elseif k==1885824110 then scroll(visible())
  elseif k==30064 then scroll(-1)
  elseif k==1685026670 then scroll(1) end
end

-- Shared BLT app restoration protocol. Each app owns one registry ID.
local BLTRestore={section='BLT_APP_RESTORE',id='BLT_MARKER_REGION_DESK'}
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
 api.RecursiveCreateDirectory(root..'/BLT',0)
 restore_write(root..'/BLT/BLT_Restore_Open_Apps.lua',BLTRestoreLauncher)
 local startup=root..'/__startup.lua';local original=restore_read(startup)or''
 local marker='-- BLT_APP_RESTORE_STARTUP'
 if not original:find(marker,1,true)then
  local block=marker..'\ndo\n local path=reaper.GetResourcePath().."/Scripts/BLT/BLT_Restore_Open_Apps.lua"\n local fn=loadfile(path)\n if fn then local ok,err=pcall(fn);if not ok then reaper.ShowConsoleMsg(tostring(err).."\\n")end end\nend\n'
  restore_write(startup,block..original:gsub('^\239\187\191',''))
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

local saved_window={}
local function save_window()
  local _,x,y,w,h=gfx.dock(-1,0,0,0,0)
  for key,v in pairs({window_x=x,window_y=y,window_w=w,window_h=h}) do
    if finite(v) then
      local value=tostring(floor(v+.5))
      if saved_window[key]~=value then BLT.store(SECTION,key,value,true);saved_window[key]=value end
    end
  end
end
local function close()
 -- Teardown errors must not leave a dead graphics window on screen.
 BLTRestore.finish(R,A.manualClose or Chrome.requestClose)
 local ok,err=xpcall(function()
  IME.active=false;IME.ctx=nil;IME.font=nil
  if A.closed then return end
  persist(); save_window(); clear_chrome_tooltip(); titlebar_cleanup()
  gfx.setimgdim(BACKGROUND_IMAGE,0,0);A.closed=true;gfx.quit()
 end,debug.traceback)
 if not ok then
  A.closed=true
  pcall(gfx.quit)
  if R.TrackCtl_SetToolTip then pcall(R.TrackCtl_SetToolTip,'',0,0,true) end
  BLT.logError(err)
 end
end
function BLT.captureScope() local v=BLT.scopeView or {};BLT.scopeView=v;v.seek=S.seek;v.move=S.move;v.kind=Core.scope.kind;v.query=Core.scope.query;v.exclude_loop=Core.scope.exclude_loop;return v end

BLT.attach({
 R=R,C=C,Chrome=Chrome,Chameleon=Chameleon,section=SECTION,faces=fonts,font=font,
 geometry=function() return scale,ox,oy end,active=function() local f=gfx.getchar(65536);return (f&1)==0 or (f&2)~=0 end,
 wake=function() A.content_dirty=true;redraw_dirty=true;next_draw_time=0;wake_visuals() end,
 defaults={seek=false,move=false,kind='all',query='',exclude_loop=true},capture=function() return BLT.captureScope() end,
 valid=function(v) return (v.kind=='all' or v.kind=='marker' or v.kind=='region') and #v.query<=1024 end,apply=function(v) S.seek=v.seek;S.move=v.move;Core.scope.kind=v.kind;Core.scope.query=v.query;Core.scope.exclude_loop=v.exclude_loop;persist();BLT.store(SECTION,"exclude_loop",v.exclude_loop and "1" or "0",true);refresh() end,
 undoAction=undo_project,
 busy=function() return false end,commit=function() return not IME.active or IME.finish(true,false) end,
 cancelEdit=function() if IME.active then IME.finish(false,false) end end,editing=function() return IME.active end,
 modal=function() return false end,
 handle=gfx_window_handle,resizeHit=function(x,y) if y<26 and x>=gfx.w-234 then return nil end;return chrome_resize_hit(x,y) end,
 cursor=set_resize_cursor,beginResize=begin_window_resize,resize=update_window_resize,

})
if ...=='blt_test' then function BLT.testDraw(now) draw(now or R.time_precise()) end end
function BLT.drawIcon()

 local bs,bx,by=scale,ox,oy;ox,oy=ox+(W-102)*scale,oy+(53-38*.78)*scale;scale=scale*.78
 marker_icon(0,0)

 scale,ox,oy=bs,bx,by
end

if ...=='blt_test' then return {BLT=BLT,A=A,Core=Core,S=S} end
local api_ok,api_err=pcall(Core.require_api)
if not api_ok then Language.mb(BLT.publicError(api_err),APP_NAME,0);return end
local chrome_ok,chrome_err=titlebar_api_ready()
if not chrome_ok then Language.mb(BLT.publicError(chrome_err),APP_NAME,0); return end
local x,y=tonumber(R.GetExtState(SECTION,"window_x")),tonumber(R.GetExtState(SECTION,"window_y"))
local w,h=tonumber(R.GetExtState(SECTION,"window_w")),tonumber(R.GetExtState(SECTION,"window_h"))
w=finite(w) and clamp(w,486,1600) or BASE_W; h=finite(h) and clamp(h,Chrome.minH,1400+Chrome.titleH) or (BASE_H+Chrome.titleH)
-- Match native window/input coordinates in logical points on Mac.
gfx.ext_retina=BLT_MAC and 0 or 1
if finite(x) and finite(y) then gfx.init(Chrome.windowTitle,w,h,0,x,y)
else gfx.init(Chrome.windowTitle,w,h,0) end
if not apply_custom_window_style(w,h) then gfx.quit(); Language.mb("カスタムタイトルバーを初期化できません。",APP_NAME,0); return end
if Chameleon.enabled then Chameleon.refresh(true) end
R.atexit(close)
if R.set_action_options then R.set_action_options(2)end
local restoreOK,restoreError=pcall(BLTRestore.start,R)
if not restoreOK then Language.mb('自動復元の登録に失敗しました。\n'..tostring(restoreError),APP_NAME,0)end
guarded(refresh)
local function loop()
  guarded(function()
 BLT.tick(R.time_precise())

  local k=BLT.key(gfx.getchar()); if k<0 or A.closing then A.closing=true; return end
    local now=R.time_precise()
    release_pending_rename()
    local ime_was_active=IME.active
    if IME.active then
      local ok,err=pcall(IME.frame)
      if not ok then IME.stop(false);report_error("日本語入力欄でエラーが発生しました。\n"..tostring(err)) end
    end
    Chameleon.tick(now)
    local flags=gfx.getchar(65537)
    local window_active=((flags & 1)==0) or ((flags & 2)~=0)
    if last_window_active==nil or window_active~=last_window_active then last_window_active=window_active; wake_visuals(now) end

    local key_activity=false; local count=0
    while k>0 and count<32 do key_activity=true; if not ime_was_active then keypress(k) end; count=count+1; k=BLT.key(gfx.getchar()) end
    if key_activity then wake_visuals(now) end
    if A.closing then return end

    local selection_changed=poll_selection(now)
    local time_changed=poll_time_display(now)
    if selection_changed or time_changed then wake_visuals(now);next_draw_time=now end
    if now>=window_poll_at then window_poll_at=now+.25; save_window() end

    local raw_x,raw_y,raw_cap=gfx.mouse_x,gfx.mouse_y,gfx.mouse_cap
    local raw_wheel=gfx.mouse_wheel or 0

    local cap_changed=raw_cap~=last_raw_mouse_cap
    local wheel_activity=raw_wheel~=0
    local pointer_activity=raw_x~=last_raw_mouse_x or raw_y~=last_raw_mouse_y or cap_changed or wheel_activity
    if pointer_activity then wake_visuals(now) end
    if cap_changed or wheel_activity then next_draw_time=now end
    last_raw_mouse_x,last_raw_mouse_y,last_raw_mouse_cap=raw_x,raw_y,raw_cap
    if gfx.w~=last_window_w or gfx.h~=last_window_h then last_window_w,last_window_h=gfx.w,gfx.h; wake_visuals(now) end

    local dragging=Chrome.drag~=nil or Chrome.resize~=nil or ((raw_cap or 0)&1)~=0
    if dragging then wake_visuals(now) end
    animation_speed=visual_speed(now)
    animations_active=window_active and animation_speed>0
    local particle_tail=window_active and #marker_particles>0
    local input_flash=false
    if A.query_flash then if now-A.query_flash<.85 then input_flash=true else A.query_flash=nil end end
    if A.name_flash then if now-A.name_flash.time<.85 then input_flash=true else A.name_flash=nil end end
    local frame_interval
    if dragging then frame_interval=1/60
    elseif animations_active then frame_interval=1/(8+22*animation_speed)
    elseif input_flash then frame_interval=1/30
    elseif particle_tail then frame_interval=1/20 end
    if frame_interval and next_draw_time==math.huge then next_draw_time=now end
    local frame_due=frame_interval and now>=next_draw_time or (not frame_interval and (redraw_dirty))
    if frame_due then
      local layout=drawn_layout
      local content_input=layout and layout.w==gfx.w and layout.h==gfx.h
        and layout.generation==A.generation and layout.offset==A.offset
        and not Chrome.drag and not Chrome.resize
        and not Chrome.closePressed and not Chrome.resetPressed and not Chrome.chameleonPressed
        and raw_x>8 and raw_x<gfx.w-8 and raw_y>Chrome.titleH+8 and raw_y<gfx.h-8
      if content_input then
        mx,my=(raw_x-ox)/scale,(raw_y-oy)/scale
        Chrome.mouseActive=false
        interact();draw()
      else
        draw();interact()
        if cap_changed or wheel_activity then draw() end
      end
      gfx.update(); redraw_dirty=false
      next_draw_time=frame_interval and now+frame_interval or math.huge

      if Chrome.requestReset then Chrome.requestReset=false; reset_window_size(); wake_visuals(now) end
      if Chrome.requestClose then Chrome.requestClose=false; A.manualClose=true;A.closing=true end
    end
    if not frame_due and (pointer_activity or key_activity or dragging) then redraw_dirty=true end
    -- Native timeline redraws may be expensive in a large project. Present our
    -- verified selection first, then refresh REAPER within this same defer pass.
    if Core.selection_redraw then
      Core.selection_redraw=nil;R.UpdateTimeline();R.UpdateArrange()
    end
  end)
  if A.closing then close(); return end
  R.defer(loop)
end

loop()
