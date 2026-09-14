-- @description Batch Rename - clipboard / Excel first column, track order, virtual preview
-- @version 0.5.0
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
 ["テイク名を取得できません。"]="Cannot read take name.",
 ["選択は20万アイテム以内にしてください。"]="Select at most 200,000 items.",
 ["選択が変更されました。読み直してください。"]="Selection changed. Reload it.",
 ["数値を入力してください。"]="Enter a number.",
 ["開始番号または桁数が無効です。"]="Invalid start number or digit count.",
 ["接頭詞・末尾詞を含む名前は4096バイト以内にしてください。"]="Names including prefix/suffix must fit in 4096 bytes.",
 ["選択またはプロジェクトが変わりました。一覧を自動更新します。もう一度対応関係を確認してください。"]="Selection or project changed. List refreshed; check mappings again.",
 ["対象の選択が変わりました。一覧を自動更新します。もう一度対応関係を確認してください。"]="Target selection changed. List refreshed; check mappings again.",
 ["対象の並び順が変わりました。一覧を自動更新します。もう一度対応関係を確認してください。"]="Target order changed. List refreshed; check mappings again.",
 ["アクティブテイクが変わりました。一覧を自動更新します。もう一度対応関係を確認してください。"]="Active take changed. List refreshed; check mappings again.",
 ["プレビュー後に名前が変わりました。一覧を自動更新します。もう一度対応関係を確認してください。"]="Names changed after preview. List refreshed; check mappings again.",
 ["変更予定がありません。"]="No changes planned.",
 ["名前の設定結果を確認できません（行 "]="Cannot verify renamed item (row ",
 ["）。"]=").",
 ["変更に失敗したため、元の名前に戻しました。"]="Rename failed. Original names restored.",
 ["復元に失敗した項目があります。REAPERのUndoで戻してください。"]="Some names could not be restored. Use REAPER Undo.",
 ["クリップボードを読み込んでください。"]="Load the clipboard.",
 ["接頭詞・末尾詞は改行なしの512バイト以内にしてください。"]="Prefix/suffix must be single-line text up to 512 bytes.",
 ["選択を自動反映しました。上のトラックから、開始位置順に対応します。"]="Selection synced. Mapped by track order, then start time.",
 ["テキストを解析しています。"]="Parsing text.",
 ["入力を取り消しました。"]="Input cancelled.",
 [" 元の値へ戻しました。"]=" Previous value restored.",
 ["取り込んだ名前をクリアしました。{name} や接頭詞・末尾詞だけでもリネームできます。"]="Imported names cleared. You can still rename with {name} or prefix/suffix.",
 ["直接入力できます。Enter：確定 ／ Esc：取消 ／ Ctrl+A：全選択 ／ Ctrl+V：欄に貼付"]="Type directly. Enter: confirm / Esc: cancel / Ctrl+A: select all / Ctrl+V: paste",
 ["入力欄には改行なしの512バイト以内の文字を貼り付けてください。"]="Paste single-line text up to 512 bytes into this field.",
 ["この欄には数字を入力してください。"]="Enter digits here.",
 ["入力は512バイト以内にしてください。"]="Keep input under 512 bytes.",
 ["接頭詞"]="Prefix",
 ["末尾詞"]="Suffix",
 ["をクリアしました。"]=" cleared.",
 ["〈空欄〉"]="<empty>",
 ["選択の変更を自動反映しました。対応関係を確認して実行してください。"]="Selection synced. Check mappings, then run.",
 ["%d件を変更しました。表示は実行前／実行後の記録です。"]="Renamed %d item(s). Showing before/after records.",
 ["同名の確認で処理を中止しました。"]="Stopped at duplicate-name confirmation.",
 ["同名になる変更先があります。内容を確認してください。"]="Some new names match. Review them before continuing.",
 ["1 増やします。"]="Increase by 1.",
 ["1 減らします。"]="Decrease by 1.",
 ["CHAMELEON  REAPERテーマに擬態"]="CHAMELEON  REAPER theme",
 ["CHAMELEON  オリジナル配色"]="CHAMELEON  Original colors",
 ["カスタムタイトルバーには js_ReaScriptAPI が必要です。\nReaPack から js_ReaScriptAPI をインストールしてください。"]="The app bar requires js_ReaScriptAPI.\nInstall js_ReaScriptAPI via ReaPack.",
 ["ReaImGui 0.10以降が必要です。ReaPackで導入・更新してください。"]="ReaImGui 0.10+ is required. Install/update via ReaPack.",
 ["日本語入力欄を初期化できません。\n"]="Cannot initialize the text input.\n",
 ["あいうえお漢字ABC012345"]="あいうえお漢字ABC012345",
 ["追加なし"]="None",
 ["クリック：直接入力 ／ 上下ドラッグ：1刻み"]="Click: type / Drag vertically: steps of 1",
 ["直接入力 ／ Ctrl+A：全選択 ／ Shift＋矢印：範囲選択 ／ Ctrl+V：この欄に貼付"]="Type / Ctrl+A: select all / Shift+arrow: select / Ctrl+V: paste here",
 ["をクリアします。"]=": clear",
 ["変更予定"]="Planned",
 ["無名にする"]="Clear name",
 ["空行・維持"]="Blank / Keep",
 ["接頭/末尾のみ"]="Affixes only",
 ["変更先なし・維持"]="No input / Keep",
 ["余り・未使用"]="Extra / Unused",
 ["同名・維持"]="Same / Keep",
 ["テイクなし"]="No take",
 ["入力待ち"]="Awaiting input",
 ["変更前"]="Before",
 ["変更後"]="After",
 ["状態"]="Status",
 ["変更済み"]="Renamed",
 ["重複注意"]="Duplicate",
 ["ダブルクリック：アイテムの開始位置へ再生カーソルを移動します。"]="Double-click: move the edit cursor to the item start.",
 ["移動先の行番号を入力し、Enterで確定します。"]="Enter a row number and press Enter.",
 ["行番号を入力できなかったため、現在行へ戻しました。"]="Invalid row number. Returned to current row.",
 ["行番号を1～%dへ補正しました。"]="Row number clamped to 1–%d.",
 ["行番号を直接入力 ／ 上下ドラッグ・ホイール：1行"]="Type row / Drag vertically or wheel: 1 row",
 ["リネームの結果重複するファイル名があります"]="Some renamed items will have duplicate names",
 ["必要であればキャンセルして、接頭詞・末尾詞や連番を調整してください。"]="Cancel to adjust prefix/suffix or numbering if needed.",
 ["ほか %d組"]="%d more groups",
 ["キャンセル"]="Cancel",
 ["Esc：キャンセル"]="Esc: cancel",
 ["このまま実行"]="Proceed",
 ["Enter：同名を許可して実行"]="Enter: allow duplicates and run",
 ["BATCH ITEM RENAME  選択アイテム名を一括変更"]="BATCH ITEM RENAME  Rename selected items",
 ["選択を自動反映"]="Sync selection",
 ["入力"]="INPUT",
 ["クリップボードの内容を反映"]="Load clipboard",
 ["クリップボード／Excelの先頭列を読み込み、プレビューへ反映します。上のトラックから開始位置順に対応し、途中の空行は詰めません。"]="Read clipboard / first Excel column into the preview. Map by track, then start time; retain blank rows.",
 ["クリア"]="Clear",
 ["このツールに取り込んだ名前だけをクリアします。クリップボード本体は変更しません。"]="Clear imported names in this tool only. Keep clipboard contents.",
 ["追加なし（入力があれば有効化します）"]="None (enabled when text is entered)",
 ["連番 {n}"]="No. {n}",
 ["開始"]="No.",
 ["桁数"]="Pad",
 ["{n} 挿入"]="{n}",
 ["接頭詞のカーソル位置へ、選択順の連番 {n} を挿入します。"]="Insert sequence number {n} at the prefix cursor.",
 ["{name} 元の名前"]="{name} Original",
 ["接頭詞のカーソル位置へ、現在のアクティブテイク名 {name} を挿入します。"]="Insert the active take name {name} at the prefix cursor.",
 ["末尾詞のカーソル位置へ、選択順の連番 {n} を挿入します。"]="Insert sequence number {n} at the suffix cursor.",
 ["末尾詞のカーソル位置へ、現在のアクティブテイク名 {name} を挿入します。"]="Insert the active take name {name} at the suffix cursor.",
 ["{n} = 選択順の連番    {name} = 現在のテイク名    貼付名は接頭詞と末尾詞の間に入ります。"]="{n} = sequence    {name} = current take    Pasted names go between prefix and suffix.",
 ["空行の扱い"]="BLANKS",
 ["接頭/末尾詞のみ反映"]="Affixes only",
 ["空行では貼付名を使わず、接頭詞・末尾詞だけを反映します。{n} と {name} も展開されます。"]="For blank rows, apply prefix/suffix only; expand {n} and {name}.",
 ["変更しない"]="Keep unchanged",
 ["貼付データの空行に対応するアイテムは、接頭詞・末尾詞も含めて変更しません。"]="Leave items mapped to blank rows unchanged, including prefix/suffix.",
 ["貼付データの空行に対応するテイク名を空にします。元ファイル名は変更しません。"]="Clear take names mapped to blank rows. Keep source file names.",
 ["空行は行位置を維持します。"]="Blank rows keep their positions.",
 ["貼付後に空行の扱いを選択できます。"]="Choose blank-row handling after pasting.",
 ["リネーム対象アイテム"]="RENAME TARGETS",
 ["入力行"]="Input rows",
 ["変更先なし"]="No input",
 ["空行維持 %d  /  無名化 %d  /  接頭末尾のみ %d  /  同名 %d  /  テイクなし %d"]="Blank kept %d / Cleared %d / Affixes %d / Same %d / No take %d",
 ["全件"]="All",
 ["変更分"]="Changes",
 ["維持分"]="Kept",
 ["余り"]="Extra",
 ["表示の絞り込みです。実行対象は変わりません。"]="Display filter only. Processing targets stay the same.",
 ["表示  %d–%d / %d 行"]="Rows %d–%d / %d",
 ["先頭"]="First",
 ["末尾"]="Last",
 ["行へ移動"]="Go to row",
 ["%d件をリネーム"]="Rename %d items",
 ["表示フィルターに関係なく、変更予定の全件を適用します。1回のUndoで戻せます。"]="Apply every planned change, regardless of the display filter. One Undo restores all edits.",
 ["テキスト解析  %d%%"]="Parsing text %d%%",
 ["注意：変更後に同名となる名前が %d組（%dアイテム）あります。実行時に確認します。"]="Warning: %d duplicate name groups (%d items). Confirmation required when running.",
 ["行移動を取り消しました。"]="Row jump cancelled.",
 ["Batch Rename | エラー"]="Batch Rename | Error",
 ["カスタムタイトルバーを初期化できません。"]="Cannot initialize the app bar.",
 ["%d行を読み込みました。%s%s"]="Loaded %d rows. %s%s",
 ["先頭列だけを使用。"]="First column only.",
 ["改行ごとに対応。"]="Mapped by line.",
 [" セル内改行・タブを%d行で空白に変換。"]=" Replaced in-cell line breaks/tabs with spaces in %d rows.",
 ["表示言語を切替（JP / EN）"]="Switch language (JP / EN)",
 ["プリセットを読み込みました: ファクトリーデフォルト"]="Loaded: Factory Default",
 ["選択中のトラック / バスを指定"]="Use selected track / bus",
},patterns={
 {"^「(.*)」を上書きしますか？$","Overwrite \"%s\"?"},
 {"^([%+%-]?[%d%.eE]+)–([%+%-]?[%d%.eE]+) / ([%+%-]?[%d%.eE]+)   スクロールで選択$","%d–%d / %d   Scroll to browse"},
 {"^解析中%.%.%.([%+%-]?[%d%.eE]+)%%$","Analyzing...%d%%"},
 {"^([%+%-]?[%d%.eE]+)件を変更しました。表示は実行前／実行後の記録です。$","Renamed %d item(s). Showing before/after records."},
 {"^行番号を1～([%+%-]?[%d%.eE]+)へ補正しました。$","Row number clamped to 1–%d."},
 {"^ほか ([%+%-]?[%d%.eE]+)組$","%d more groups"},
 {"^空行維持 ([%+%-]?[%d%.eE]+)  /  無名化 ([%+%-]?[%d%.eE]+)  /  接頭末尾のみ ([%+%-]?[%d%.eE]+)  /  同名 ([%+%-]?[%d%.eE]+)  /  テイクなし ([%+%-]?[%d%.eE]+)$","Blank kept %d / Cleared %d / Affixes %d / Same %d / No take %d"},
 {"^表示  ([%+%-]?[%d%.eE]+)–([%+%-]?[%d%.eE]+) / ([%+%-]?[%d%.eE]+) 行$","Rows %d–%d / %d"},
 {"^([%+%-]?[%d%.eE]+)件をリネーム$","Rename %d items"},
 {"^テキスト解析  ([%+%-]?[%d%.eE]+)%%$","Parsing text %d%%"},
 {"^注意：変更後に同名となる名前が ([%+%-]?[%d%.eE]+)組（([%+%-]?[%d%.eE]+)アイテム）あります。実行時に確認します。$","Warning: %d duplicate name groups (%d items). Confirmation required when running."},
 {"^([%+%-]?[%d%.eE]+)行を読み込みました。(.-)(.-)$","Loaded %d rows. %s%s",{2,3}},
 {"^ セル内改行・タブを([%+%-]?[%d%.eE]+)行で空白に変換。$"," Replaced in-cell line breaks/tabs with spaces in %d rows."},
 {"^「(.-)」を上書きしますか？$","\"%s\"?"},
 {"^(.-)」を上書きしますか？$","%s\"?"},
 {"^プリセットを保存しました: (.-)$","Saved: %s"},
 {"^プリセットを読み込みました: (.-)$","Loaded: %s"},
 {"^(.-)個インポートしました。$","%s preset(s) imported."},
 {"^現在: (.-)(.-)$","Current: %s%s"},
 {"^名前の設定結果を確認できません（行 (.-)）。$","Cannot verify renamed item (row %s)."},
 {"^(.-)）。$","%s)."},
 {"^(.-) 元の値へ戻しました。$","%s Previous value restored."},
 {"^(.-)をクリアしました。$","%s cleared."},
 {"^日本語入力欄を初期化できません。\n(.-)$","Cannot initialize the text input.\n%s"},
 {"^(.-)をクリアします。$","%s: clear"},
 {"^「(.*)」を上書きしますか？$","Overwrite \"%s\"?"},
 {"^(%d+)個インポートしました。$","Imported %s preset(s)."},
 {"^(%d+)件をノーマライズしました。選択を解除しました。$","Normalized %s items and deselected them."},
},prefixes={"日本語入力欄を初期化できません。\n","プリセットを読み込みました: ","プリセットを保存しました: ","現在: "}}

local Language=create_language(reaper,"BLT_BATCH_RENAME",LanguageCatalog)
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
 local ok,l,t,r,bt=R.JS_Window_GetRect(hwnd)
 if ok and l==x and t==y and r-l==w and bt-t==h then B.lastRect={hwnd,x,y,w,h};return true end
 local done=R.JS_Window_SetPosition(hwnd,x,y,w,h,a,b)
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

local Core={MAX_BYTES=16*1024*1024,MAX_ROWS=200000,MAX_NAME=4096}
local min,max,floor=math.min,math.max,math.floor
local function clamp(n,a,b) return max(a,min(b,n)) end
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
local function copy(t) local r={}; for k,v in pairs(t) do r[k]=v end; return r end

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
local function take_name(take)
  local ok,name=R.GetSetMediaItemTakeInfo_String(take,"P_NAME","",false)
  if not ok or type(name)~="string" then error("テイク名を取得できません。",0) end
  return name
end
function Core.collect(project)
  local result={}
  local n=R.CountSelectedMediaItems(project)
  if n>Core.MAX_ROWS then error("選択は20万アイテム以内にしてください。",0) end
  for i=0,n-1 do
    local item=R.GetSelectedMediaItem(project,i)
    if not item or not R.ValidatePtr2(project,item,"MediaItem*") then error("選択が変更されました。読み直してください。",0) end
    local track=R.GetMediaItemTrack(item); local take=R.GetActiveTake(item)
    local _,trackname=R.GetSetMediaTrackInfo_String(track,"P_NAME","",false)
    result[#result+1]={item=item,take=take,before=take and take_name(take) or "",track=track,
      tracknum=R.GetMediaTrackInfo_Value(track,"IP_TRACKNUMBER"),trackname=trackname or "",
      selection_index=i, pos=R.GetMediaItemInfo_Value(item,"D_POSITION"),index=R.GetMediaItemInfo_Value(item,"IP_ITEMNUMBER")}
  end
  table.sort(result,function(a,b)
    if a.tracknum~=b.tracknum then return a.tracknum<b.tracknum end
    if a.pos~=b.pos then return a.pos<b.pos end
    return a.index<b.index
  end)
  return result
end
function Core.affix(text,start,digits,index,current_name)
  local number=string.format("%0"..digits.."d",start+index-1)
  local out=text:gsub("{n}",function() return number end)
  if current_name~=nil then out=out:gsub("{name}",function() return current_name end) end
  return out
end
-- Cursor and selection offsets are Unicode codepoints, never UTF-8 byte offsets.
Core.Edit={}
function Core.Edit.new(value)
  local chars={}; for _,cp in utf8.codes(value) do chars[#chars+1]=utf8.char(cp) end
  return {chars=chars,cursor=#chars,anchor=#chars,view=0}
end
function Core.Edit.value(e) return table.concat(e.chars) end
function Core.Edit.insert(e,text)
  local a,b=min(e.cursor,e.anchor),max(e.cursor,e.anchor)
  local chars={}
  for i=1,a do chars[#chars+1]=e.chars[i] end
  for _,cp in utf8.codes(text) do chars[#chars+1]=utf8.char(cp) end
  local cursor=#chars
  for i=b+1,#e.chars do chars[#chars+1]=e.chars[i] end
  e.chars=chars; e.cursor=cursor; e.anchor=cursor
end
function Core.Edit.move(e,pos,shift)
  e.cursor=clamp(pos,0,#e.chars); if not shift then e.anchor=e.cursor end
end
function Core.Edit.delete(e,back)
  if e.cursor==e.anchor then
    if back then e.anchor=max(0,e.cursor-1) else e.anchor=min(#e.chars,e.cursor+1) end
  end
  Core.Edit.insert(e,"")
end
function Core.numeric_bounds(key)
  return key:match("_digits$") and 1 or 0,key:match("_digits$") and 12 or 999999999
end
function Core.normalize_numeric(key,value)
  local n=tonumber(tostring(value or ""):match("^%s*(.-)%s*$"))
  if not finite(n) then return nil,false,"数値を入力してください。" end
  local lo,hi=Core.numeric_bounds(key)
  local rounded=n>=0 and floor(n+.5) or math.ceil(n-.5)
  local clipped=rounded<lo or rounded>hi or rounded~=n
  return tostring(clamp(rounded,lo,hi)),clipped
end
function Core.preview(items,names,s,loaded)
  local rows,stats={},{selected=#items,input=#names,change=0,blank=0,empty_skip=0,empty_affix=0,missing=0,extra=0,same=0,unsupported=0,idle=0,
    duplicate_groups=0,duplicate_items=0}
  local mapped_inputs={};local mapped_count=0
  if loaded then
    for i,item in ipairs(items) do
      if item.take then mapped_count=mapped_count+1;mapped_inputs[i]=names[mapped_count] end
    end
  end
  local count=#items+(loaded and max(0,#names-mapped_count) or 0)
  local has_template=(s.prefix or "")~="" or (s.suffix or "")~=""
  local ps,pd,ss,sd=tonumber(s.prefix_start),tonumber(s.prefix_digits),tonumber(s.suffix_start),tonumber(s.suffix_digits)
  if not finite(ps) or not finite(pd) or not finite(ss) or not finite(sd)
    or ps<0 or ps>999999999 or ss<0 or ss>999999999 or pd<1 or pd>12 or sd<1 or sd>12
    or ps~=floor(ps) or ss~=floor(ss) or pd~=floor(pd) or sd~=floor(sd) then
    error("開始番号または桁数が無効です。",0)
  end
  for i=1,count do
    local item=items[i]
    local input
    if item then input=mapped_inputs[i] else input=names[mapped_count+i-#items] end
    local row={number=i,info=item,before=item and item.before or "",input=input}
    if not item then row.kind="extra"; row.after=input
    elseif not item.take then row.kind="unsupported"; row.after=row.before
    elseif loaded and input==nil then row.kind="missing"; row.after=row.before
    elseif loaded and input=="" then
      if s.empty=="clear" then
        row.kind="blank"; row.after=""
      elseif s.empty=="affix" then
        row.kind="empty_affix"
        row.after=Core.affix(s.prefix,ps,pd,i,row.before)
          ..Core.affix(s.suffix,ss,sd,i,row.before)
      else
        row.kind="empty_skip"; row.after=row.before
      end
    elseif not loaded and not has_template then
      row.kind="idle"; row.after=row.before
    else
      local base=loaded and (input or "") or ""
      row.after=Core.affix(s.prefix,ps,pd,i,row.before)
        ..base
        ..Core.affix(s.suffix,ss,sd,i,row.before)
      row.kind="rename"
    end
    if #row.after>Core.MAX_NAME then error("接頭詞・末尾詞を含む名前は4096バイト以内にしてください。",0) end
    row.change=item and item.take and (row.kind=="rename" or row.kind=="blank" or row.kind=="empty_affix") and row.after~=row.before or false
    if (row.kind=="rename" or row.kind=="blank" or row.kind=="empty_affix") and not row.change then row.kind="same" end
    if row.change then stats.change=stats.change+1 end
    if stats[row.kind]~=nil then stats[row.kind]=stats[row.kind]+1 end
    rows[#rows+1]=row
  end

  -- Detect duplicate final take names without changing the rename result.
  -- Existing duplicates that remain completely untouched are ignored; the warning
  -- is only raised when this operation creates or participates in the collision.
  local groups={}
  for _,row in ipairs(rows) do
    if row.info and row.info.take and row.after~=nil then
      local g=groups[row.after]
      if not g then g={name=row.after,rows={}}; groups[row.after]=g end
      g.rows[#g.rows+1]=row
    end
  end
  local duplicates={}
  for _,g in pairs(groups) do
    if #g.rows>1 then
      local involved=false
      for _,row in ipairs(g.rows) do if row.change then involved=true; break end end
      if involved then
        duplicates[#duplicates+1]=g
        stats.duplicate_groups=stats.duplicate_groups+1
        stats.duplicate_items=stats.duplicate_items+#g.rows
        for _,row in ipairs(g.rows) do row.duplicate=true end
      end
    end
  end
  table.sort(duplicates,function(a,b) return a.rows[1].number<b.rows[1].number end)
  stats.duplicates=duplicates
  return rows,stats
end
function Core.preflight(project,items)
  if R.EnumProjects(-1,"")~=project or R.CountSelectedMediaItems(project)~=#items then return nil,"選択またはプロジェクトが変わりました。一覧を自動更新します。もう一度対応関係を確認してください。" end
  for _,v in ipairs(items) do
    if not R.ValidatePtr2(project,v.item,"MediaItem*") or not R.IsMediaItemSelected(v.item) then return nil,"対象の選択が変わりました。一覧を自動更新します。もう一度対応関係を確認してください。" end
    if R.GetMediaItemTrack(v.item)~=v.track or R.GetMediaTrackInfo_Value(v.track,"IP_TRACKNUMBER")~=v.tracknum
      or R.GetMediaItemInfo_Value(v.item,"D_POSITION")~=v.pos or R.GetMediaItemInfo_Value(v.item,"IP_ITEMNUMBER")~=v.index then
      return nil,"対象の並び順が変わりました。一覧を自動更新します。もう一度対応関係を確認してください。"
    end
    if R.GetActiveTake(v.item)~=v.take then return nil,"アクティブテイクが変わりました。一覧を自動更新します。もう一度対応関係を確認してください。" end
    if v.take and take_name(v.take)~=v.before then return nil,"プレビュー後に名前が変わりました。一覧を自動更新します。もう一度対応関係を確認してください。" end
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
      local set=R.GetSetMediaItemTakeInfo_String(row.info.take,"P_NAME",row.after,true)
      if not set or take_name(row.info.take)~=row.after then error("名前の設定結果を確認できません（行 "..row.number.."）。",0) end
    end
  end,debug.traceback)
  local restored=true
  if not success then
    for i=#touched,1,-1 do
      local row=touched[i]
      local call,result=pcall(function()
        local set=R.GetSetMediaItemTakeInfo_String(row.info.take,"P_NAME",row.before,true)
        return set and take_name(row.info.take)==row.before
      end)
      if not call or not result then restored=false end
    end
  end
  R.PreventUIRefresh(-1); R.UpdateArrange()
  R.Undo_EndBlock2(project,success and "Batch Rename: active take names" or "Batch Rename: restored after failure",4)
  if not success then
    R.ShowConsoleMsg("Batch Rename:\n"..BLT.publicError(detail).."\n")
    return nil,restored and "変更に失敗したため、元の名前に戻しました。" or "復元に失敗した項目があります。REAPERのUndoで戻してください。"
  end
  return #changes
end
local SECTION="BLT_BATCH_RENAME"
local saved_empty=R.GetExtState(SECTION,"empty")
local S={prefix=R.GetExtState(SECTION,"prefix"),suffix=R.GetExtState(SECTION,"suffix"),
  empty=(saved_empty=="clear" or saved_empty=="skip" or saved_empty=="affix") and saved_empty or "affix"}
local A={project=R.EnumProjects(-1,""),items={},names={},rows={},stats={},filtered={},filter="all",
  loaded=false,offset=0,focus=nil,message="クリップボードを読み込んでください。",bad=false,poll=0,stale=false,
  duplicate_modal=false,field_flash={},field_drag=nil,pressed=nil}
for _,side in ipairs({"prefix","suffix"}) do
  local start=tonumber(R.GetExtState(SECTION,side.."_start"))
  local digits=tonumber(R.GetExtState(SECTION,side.."_digits"))
  S[side.."_start"]=tostring(finite(start) and floor(clamp(start,0,999999999)) or 0)
  S[side.."_digits"]=tostring(finite(digits) and floor(clamp(digits,1,12)) or 3)
end
local E=nil
local IME={active=false,bounds={}}
local function edit_value(e)
  local value=Core.Edit.value(e)
  if e.key=="prefix" or e.key=="suffix" then
    if #value>512 or value:find("[%z\1-\31\127]") or not utf8.len(value) then return nil,"接頭詞・末尾詞は改行なしの512バイト以内にしてください。" end
  else
    local normalized,_,err=Core.normalize_numeric(e.key,value)
    if not normalized then return nil,err end
    value=normalized
  end
  return value
end
local function notice(text,bad) A.message=bad and BLT.publicError(text) or tostring(text or ''); A.bad=bad or false end
local function persist()
  for _,k in ipairs({"prefix","suffix","empty","prefix_start","prefix_digits","suffix_start","suffix_digits"}) do BLT.store(SECTION,k,S[k],true) end
end
local function filter_rows()
  A.filtered={}
  for i,row in ipairs(A.rows) do
    local show=A.filter=="all" or (A.filter=="changes" and row.change)
      or (A.filter=="unchanged" and row.info and not row.change) or (A.filter=="extra" and row.kind=="extra")
    if show then A.filtered[#A.filtered+1]=i end
  end
  A.offset=0; A.focus=nil
end
local function rebuild()
  local options=copy(S)
  if E then local value=edit_value(E); if value then options[E.key]=value end end
  A.rows,A.stats=Core.preview(A.items,A.names,options,A.loaded); filter_rows()
  A.invalid=A.input_error or false
end
local function refresh()
  A.duplicate_modal=false
  A.project=R.EnumProjects(-1,""); A.items=Core.collect(A.project)
  A.revision=R.GetProjectStateChangeCount(A.project); A.stale=false; A.applied=false
  A.live=nil; A.generation=(A.generation or 0)+1
  rebuild(); notice("選択を自動反映しました。上のトラックから、開始位置順に対応します。")
end
local function load_text(text,origin)
  local parser=Core.parser(text)
  if A.applied then refresh() end
  A.parser=parser; A.origin=origin; A.loaded=false; A.applied=false; A.invalid=true; A.names={}
  rebuild()
  notice("テキストを解析しています。")
end
local function read_clipboard()
  A.input_error=true
  local text,origin=Core.clipboard(); load_text(text,origin)
end
function A.numeric_field(key) return key=="prefix_start" or key=="prefix_digits" or key=="suffix_start" or key=="suffix_digits" end
function A.flash_field(key) A.field_flash[key]=R.time_precise() end
function A.field_flash_value(key)
  local t=A.field_flash[key]; if not t then return 0 end
  local age=R.time_precise()-t
  if age>=1.15 then A.field_flash[key]=nil; return 0 end
  local q=clamp(age/1.15,0,1); return 1-q*q*(3-2*q)
end
function A.update_field_drag(py)
  local d=A.field_drag; if not d then return end
  local dy=d.start_y-py
  if not d.moved and math.abs(dy)<3 then return end
  d.moved=true; E=nil; A.edit_dirty=nil
  local q=dy/3; local ticks=(q<0 and -1 or 1)*floor(math.abs(q)+.5)
  local raw=d.start_value+ticks
  local lo,hi=Core.numeric_bounds(d.key); local clipped=raw<lo or raw>hi
  local v=clamp(floor(raw+.5),lo,hi)
  if clipped and not d.clipped then A.flash_field(d.key); d.clipped=true elseif not clipped then d.clipped=false end
  if tonumber(S[d.key])~=v then S[d.key]=tostring(v); persist(); A.applied=false; rebuild() end
end
local function commit_edit(cancel)
  if not E then return true end
  if cancel then IME.stop(false); E=nil; A.edit_dirty=nil; rebuild(); notice("入力を取り消しました。"); return true end
  local key=E.key
  if A.numeric_field(key) then
    local raw=Core.Edit.value(E); local value,clipped,err=Core.normalize_numeric(key,raw)
    if not value then A.flash_field(key);E=nil;A.edit_dirty=nil;rebuild();notice(err.." 元の値へ戻しました。",true);return true end
    if clipped then A.flash_field(key) end
    S[key]=value
  else
    local value,err=edit_value(E)
    if not value then
      A.flash_field(key);IME.stop(false);E=nil;A.edit_dirty=nil;rebuild()
      notice(err.." 元の値へ戻しました。",true);return true
    end
    S[key]=value
  end
  IME.stop(false); E=nil; A.edit_dirty=nil; persist(); rebuild(); return true
end
local function clear_paste()
  if not commit_edit() then return end
  if A.applied then refresh() end
  A.parser=nil; A.names={}; A.loaded=false; A.input_error=false; A.invalid=false
  rebuild(); notice("取り込んだ名前をクリアしました。{name} や接頭詞・末尾詞だけでもリネームできます。")
end
local function change_setting(k,v)
  if not commit_edit() then return end
  if A.applied then refresh() end
  S[k]=v; persist(); A.applied=false; rebuild()
end
local function begin_edit(key)
  if E and E.key==key then return true end
  if not commit_edit() then return false end
  if A.applied then refresh() end
  E=Core.Edit.new(S[key]); E.key=key
  if key=="prefix" or key=="suffix" then
    if not IME.open(key) then E=nil;return false end
  end
  notice("直接入力できます。Enter：確定 ／ Esc：取消 ／ Ctrl+A：全選択 ／ Ctrl+V：欄に貼付")
  return true
end
local function edit_insert(text)
  if not E then return end
  if #text>512 or not utf8.len(text) or text:find("[%z\1-\31\127]") then A.flash_field(E.key);notice("入力欄には改行なしの512バイト以内の文字を貼り付けてください。",true); return end
  if E.key~="prefix" and E.key~="suffix" and text:find("[^0-9]") then A.flash_field(E.key);notice("この欄には数字を入力してください。",true); return end
  local trial=Core.Edit.new(Core.Edit.value(E)); trial.cursor=E.cursor; trial.anchor=E.anchor
  Core.Edit.insert(trial,text)
  if #Core.Edit.value(trial)>512 then A.flash_field(E.key);notice("入力は512バイト以内にしてください。",true); return end
  Core.Edit.insert(E,text); A.edit_dirty=R.time_precise()+.15
end
local function insert_token(key,token)
  if begin_edit(key) then edit_insert(token) end
end
local function insert_number(key) insert_token(key,"{n}") end
local function insert_current_name(key) insert_token(key,"{name}") end
local function clear_text_field(key)
  if key~="prefix" and key~="suffix" then return end
  if E and E.key==key then IME.stop(false);E=nil; A.edit_dirty=nil end
  if A.applied then refresh() end
  S[key]=""; persist(); A.applied=false; rebuild()
  notice((key=="prefix" and "接頭詞" or "末尾詞").."をクリアしました。")
end
local function duplicate_display_name(name,limit)
  if name=="" then return "〈空欄〉" end
  name=tostring(name):gsub("[\r\n\t]"," ")
  limit=limit or 52
  local n=utf8.len(name)
  if not n or n<=limit then return name end
  local cut=utf8.offset(name,limit+1)
  return cut and (name:sub(1,cut-1).."…") or name
end
local function sync_selection()
  local project=R.EnumProjects(-1,"")
  local live=A.live or A.items
  local changed=project~=A.project or R.CountSelectedMediaItems(project)~=#live
  if not changed then
    for _,v in ipairs(live) do
      if R.GetSelectedMediaItem(project,v.selection_index)~=v.item then changed=true; break end
    end
  end
  local revision=R.GetProjectStateChangeCount(project)
  if not changed and revision~=A.revision then changed=not Core.preflight(project,live) end
  if changed then refresh() else A.revision=revision end
  return changed
end
local function perform_execute()
  local valid=Core.preflight(A.project,A.items)
  if not valid then refresh(); notice("選択の変更を自動反映しました。対応関係を確認して実行してください。",true); return end
  local n,err=Core.apply(A.project,A.items,A.rows)
  if not n then notice(err,true); return end
  A.revision=R.GetProjectStateChangeCount(A.project); A.applied=true; A.live=Core.collect(A.project)
  notice(string.format("%d件を変更しました。表示は実行前／実行後の記録です。",n))
end
local function cancel_duplicate_modal()
  A.duplicate_modal=false
  notice("同名の確認で処理を中止しました。")
end
local function confirm_duplicate_modal()
  A.duplicate_modal=false
  perform_execute()
end
local function execute()
  if not commit_edit() then return end
  if A.parser or A.applied or A.invalid then return end
  local valid=Core.preflight(A.project,A.items)
  if not valid then refresh(); notice("選択の変更を自動反映しました。対応関係を確認して実行してください。",true); return end
  if (A.stats.duplicate_groups or 0)>0 then
    A.duplicate_modal=true
    A.pressed=nil
    notice("同名になる変更先があります。内容を確認してください。",true)
    return
  end
  perform_execute()
end
local function guarded(fn)
  local ok,err=xpcall(fn,debug.traceback)
  if not ok then A.parser=nil; A.invalid=true; notice(err,true); BLT.recoverInput(A,err) end
end

local W,H=1040,828
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
local icon_particles,icon_clock,icon_serial={},0,0
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
local function glow_line(x,y,x2,y2,c,strength)
  strength=strength or 1
  line(x,y-2,x2,y2-2,c,.05*strength); line(x,y+2,x2,y2+2,c,.05*strength)
  line(x,y-1,x2,y2-1,c,.12*strength); line(x,y+1,x2,y2+1,c,.12*strength)
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

local function draw_background()
  rect(0,0,W,H+22,C.bg)
  disc(W-45,42,180,C.accent,.016)
  disc(5,H-85,150,C.bg2,.030)
  gradient(0,0,W,92,C.bg2,C.bg,.22,0,true)

  line(17,104,17,H-46,C.edge2,.12)
  for y=115,H-52,20 do line(17,y,22,y,C.edge2,.10) end
end

local function small_button(id,text,x,y,w,h,fn,hint,enabled,strong_edge)
  enabled=enabled~=false
  local hovered=inside(x,y,w,h) and enabled
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
  local affix_action=id:match("^number_") or id:match("^name_")
  local text_size=affix_action and 13 or 10
  if affix_action then
    while text_size>10 and measure(text,text_size,1,true)>w-8 do text_size=text_size-.5 end
  end
  label(text,x,y+2,text_size,enabled and (affix_action and C.text or (hovered and C.text or C.muted)) or C.faint,1,w,h-3,5,true)
  widget(id,x,y,w,h,fn,hint,enabled)
end

local function numeric_stepper(id,key,x,y,w,h)
  local half=h/2
  local can=not A.parser
  local up=inside(x,y,w,half) and can
  local dn=inside(x,y+half,w,h-half) and can
  local au=animate("step_up_"..id,up and 1 or 0)
  local ad=animate("step_dn_"..id,dn and 1 or 0)
  gradient(x,y,w,h,C.panel2,C.panel,.30,.82)
  if au>.01 then rect(x+1,y+1,w-2,half-1,C.accent3,.18*au) end
  if ad>.01 then rect(x+1,y+half,w-2,h-half-1,C.accent3,.18*ad) end
  line(x,y+half,x+w,y+half,C.edge2,.34)
  finish_corners(x,y,w,h,4,false,C.edge2,.34+max(au,ad)*.34)
  local c1=up and C.accent2 or C.muted
  local c2=dn and C.accent2 or C.muted
  local cx=x+w/2
  local uy=y+half/2+.5
  line(cx-3,uy+2,cx,uy-1,c1,.50+.42*au); line(cx,uy-1,cx+3,uy+2,c1,.50+.42*au)
  local dy=y+half+half/2-.5
  line(cx-3,dy-2,cx,dy+1,c2,.50+.42*ad); line(cx,dy+1,cx+3,dy-2,c2,.50+.42*ad)
  widget("step_up_"..id,x,y,w,half,function()
    if A.applied then refresh() end
    local digits=key:match("_digits$")~=nil
    local lo,hi=digits and 1 or 0,digits and 12 or 999999999
    local n=clamp((tonumber(S[key]) or lo)+1,lo,hi)
    S[key]=tostring(floor(n)); persist(); A.applied=false; rebuild()
  end,"1 増やします。",can)
  widget("step_dn_"..id,x,y+half,w,h-half,function()
    if A.applied then refresh() end
    local digits=key:match("_digits$")~=nil
    local lo,hi=digits and 1 or 0,digits and 12 or 999999999
    local n=clamp((tonumber(S[key]) or lo)-1,lo,hi)
    S[key]=tostring(floor(n)); persist(); A.applied=false; rebuild()
  end,"1 減らします。",can)
end

local function segment_button(id,text,x,y,w,h,active,fn,hint,enabled)
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
  label(text,x,y+3,11,enabled and (active and C.text or C.muted) or C.faint,1,w,h-5,5,true)
  widget(id,x,y,w,h,fn,hint,enabled)
end

local function choice_card(id,title,code,x,y,w,h,active,fn,hint,enabled)
  enabled=enabled~=false
  local hovered=inside(x,y,w,h) and enabled
  local pressed_now=A.pressed==id and (gfx.mouse_cap&1)~=0 and enabled
  local dy=pressed_now and 1.6 or 0
  local main_action=id=="read" or id=="clear_paste"
  local awaiting=id=="read" and not A.loaded and not A.parser
  local reflected=id=="read" and A.loaded and not A.parser
  local parsing=id=="read" and A.parser~=nil
  local target=active and 1 or (hovered and .30 or 0)
  local a=animate("choice_"..id,target)

  gradient(x,y+dy,w,h,C.panel2,C.panel,.28+.28*a,.72)
  if a>.01 then
    gradient(x+3,y+dy,w-3,h,C.accent3,C.accent3,.18*a,0)
    rect(x,y+8+dy,3,h-16,C.accent2,.75*a)
    glow_line(x+8,y+dy,x+62,y+dy,C.accent2,.28*a)
  end
  if pressed_now then
    gradient(x+2,y+2+dy,w-5,h-5,C.accent,C.accent3,.24,.035,true)
    rect(x+2,y+2+dy,w-4,h-4,C.accent3,.08)
  end

  line(x,y+dy,x+w,y+dy,C.edge2,.20+.43*a)
  line(x,y+h+dy,x+w,y+h+dy,C.edge,.33)
  finish_corners(x,y+dy,w,h,8,true,pressed_now and C.focus2 or C.edge2,pressed_now and .82 or (.26+.38*a))

  if main_action then
    gradient(x+2,y+2+dy,w-5,h-5,C.accent3,C.panel,.14+.18*a,.01)
    glow_line(x+10,y+1+dy,x+min(w-12,150),y+1+dy,C.accent2,.24+.18*a)
  end

  if id=="read" then
    if awaiting then
      -- Keep the call-to-action inside the button; no animated outer frame.
      local u=(anim_time*.46)%1
      local scan_x=x+18+u*(w-36)
      gradient(scan_x-15,y+6+dy,30,h-12,C.accent3,C.accent3,0,.12*(1-math.abs(u-.5)*1.4))
      line(scan_x,y+7+dy,scan_x,y+h-7+dy,C.focus2,.15+.24*math.sin(math.pi*u)^2)
    elseif parsing then
      local u=(anim_time*.58)%1
      local scan_x=x+14+u*(w-28)
      line(scan_x,y+5+dy,scan_x,y+h-5+dy,C.focus2,.34)
    elseif reflected then
      -- Quiet confirmation mark after reflection; no continuous attention animation.
      local cx,cy=x+w-30,y+h/2+dy
      line(cx-5,cy,cx-1,cy+4,C.focus2,.68)
      line(cx-1,cy+4,cx+6,cy-5,C.focus2,.68)
    end
  end

  local title_size=main_action and 17 or 15
  if id=="read" then
    label(title,x+14,y+dy,title_size,enabled and C.text or C.faint,1,w-28,h,5,true)
  else
    local title_y=main_action and (y+10+dy) or (y+9+dy)
    label(title,x+14,title_y,title_size,enabled and ((active or main_action) and C.text or C.muted) or C.faint,1,w-28,29,0,true)
  end
  right_label(code,x+w-12,y+6+dy,7,(active or main_action) and C.accent2 or C.faint,3,true)
  widget(id,x,y,w,h,fn,hint,enabled)
end

local function draw_glass_group(x,y,w,h,title)
  gradient(x,y,w,h,C.panel2,C.panel,.22,.58)
  line(x,y,x+w,y,C.edge2,.22); line(x,y+h,x+w,y+h,C.edge,.34)
  finish_corners(x,y,w,h,8,false,C.edge2,.30)
  label(title,x+12,y+6,7.5,C.faint,3,w-24,12,0,true)
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
  chameleonPressed=false,resizeCursors={},resizeCursorMode=nil,titleH=26,windowTitle='BLT Batch Rename',titleText='B A T C H   R E N A M E',
  minW=780,minH=656,mint={0.38,0.88,0.72},ice={0.65,0.895,1.0},red={1.0,0.27,0.34},
  isWindows=R.GetOS():match("Win")~=nil,resizeEdge=6,resizeCornerBand=8,resizeCornerSpan=24,resizeTopLeftGuard=30,resizeTopRightGuard=110,
  tooltipHover=nil,tooltipSince=0,tooltipVisible=false,tooltipDelay=.70,
  cursorId={we=32644,ns=32645,nwse=32642,nesw=32643,arrow=32512}}
Chrome.font=Chrome.isWindows and "Segoe UI" or (R.GetOS():match("OSX") and "Helvetica Neue" or "sans-serif")
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
  local ok,l,t=R.JS_Window_GetRect(hwnd)
  if not R.JS_Window_SetStyle(hwnd,"POPUP") then return false end
  if ok then BLT.position(hwnd,l,t,target_w,target_h,"","") end
  return true
end

local function reset_window_size()
  local hwnd=gfx_window_handle()
  if not hwnd then return end
  local ok,l,t=R.JS_Window_GetRect(hwnd)
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
  local ok,l,t,r,b=R.JS_Window_GetRect(hwnd)
  if not ok then return false end
  local sx,sy=R.GetMousePosition()
  Chrome.resize={mode=mode,mouseX=sx,mouseY=sy,left=l,top=t,right=r,bottom=b}
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
  BLT.position(hwnd,math.floor(l+.5),math.floor(t+.5),math.max(Chrome.minW,math.floor(r-l+.5)),math.max(Chrome.minH,math.floor(b-t+.5)),"","")
end

local function clear_chrome_tooltip() BLT.clearTooltip() end

local function custom_titlebar() BLT.bar() end

local function rename_icon(x,y)
  for i=1,6 do
    local phase=anim_time*(.11+(i%3)*.028)+i*1.37
    local px=x+53+math.sin(phase*1.13)*(23+(i%2)*4)
    local py=y+35+math.cos(phase*.87)*(7+(i%3))
    local rr=8+(i%4)*3
    disc(px,py,rr+7,C.accent,.005); disc(px,py,rr,C.accent3,.009)
  end

  if animations_active then icon_clock=icon_clock+frame_dt end
  while animations_active and icon_clock>=.085 and #icon_particles<30 do
    icon_clock=icon_clock-.085; icon_serial=icon_serial+1
    local n=icon_serial
    local a,b,c,d=particle_hash(n,21),particle_hash(n,22),particle_hash(n,23),particle_hash(n,24)
    icon_particles[#icon_particles+1]={x=x+35+a*5,y=y+25+b*24,vx=14+c*13,vy=(d-.5)*2.6,life=1.05+b*.75,age=0,r=.40+a*.45,phase=c*6.28}
  end
  for i=#icon_particles,1,-1 do
    local p=icon_particles[i]; p.age=p.age+particle_dt
    if p.age>=p.life then table.remove(icon_particles,i) else
      local t=p.age/p.life; local e=math.sin(math.pi*t)^2
      local px=p.x+p.vx*p.age
      local py=p.y+p.vy*p.age+math.sin(p.age*2.0+p.phase)*1.1
      disc(px,py,p.r+2.5,C.accent,.018*e); disc(px,py,p.r+1,C.accent2,.055*e); disc(px,py,p.r,C.focus2,.54*e)
    end
  end

  cut_panel(x+7,y+14,33,42,6,C.field,.95,C.edge2,.62,true)
  cut_panel(x+10,y+17,27,36,4,C.panel2,.62,C.edge,.36,false)
  glow_line(x+16,y+17,x+31,y+17,C.accent2,.30)
  line(x+13,y+24,x+34,y+24,C.muted,.58)
  line(x+13,y+31,x+31,y+31,C.faint,.55)
  line(x+13,y+38,x+34,y+38,C.faint,.47)
  line(x+13,y+45,x+28,y+45,C.faint,.38)
  line(x+35,y+18,x+35,y+27,C.accent2,.42)
  disc(x+34.5,y+49.5,1.1,C.focus2,.78)

  line(x+42,y+29,x+62,y+29,C.edge2,.22)
  line(x+42,y+39,x+62,y+39,C.edge2,.15)
  local travel=(anim_time*.42)%1
  for k=0,2 do
    local u=(travel+k/3)%1
    local px=x+42+u*20
    local alpha=.20+.72*math.sin(math.pi*u)^2
    line(px-4,y+34,px+1,y+34,C.accent2,alpha)
    line(px-1,y+30.5,px+3,y+34,C.accent2,alpha)
    line(px-1,y+37.5,px+3,y+34,C.accent2,alpha)
    disc(px-4,y+34,.65,C.focus2,.44*alpha)
  end

  for i=0,2 do
    local yy=y+15+i*14
    local xx=x+65+i*2
    local ww=36-i*2
    cut_panel(xx,yy,ww,11,4,C.panel2,.94,C.edge2,.42+.10*(2-i),i==0)
    gradient(xx+3,yy+2,ww-7,2,C.accent3,C.accent2,.16+.07*(2-i),.03)
    line(xx+6,yy+6,xx+ww-7,yy+6,i==1 and C.accent2 or C.muted,i==1 and .90 or .56)
    line(xx+ww-5,yy+2,xx+ww-5,yy+8,C.focus2,.22+.12*(2-i))
  end
  glow_line(x+66,y+58,x+96,y+58,C.accent2,.22)
  line(x+62,y+12,x+70,y+12,C.edge2,.24)
  line(x+96,y+55,x+101,y+50,C.edge2,.28)
end
local function ime_color(c,alpha)
  return (floor(c[1]*255+.5)<<24)|(floor(c[2]*255+.5)<<16)|(floor(c[3]*255+.5)<<8)|floor((alpha or 1)*255+.5)
end

function IME.stop(restore)
  IME.active=false;IME.ctx=nil;IME.font=nil;IME.key=nil;IME.metrics=nil
  wake_visuals();next_draw_time=0
  if restore then local hwnd=gfx_window_handle();if hwnd then R.JS_Window_SetFocus(hwnd) end end
end
function IME.open(key)
 if not BLT.requireInput(IME) then return false end
  local ok,err=pcall(function()
    local I=IME.api
    IME.ctx=I.CreateContext("BLT Batch Rename input")
    IME.font=I.CreateFont(fonts[1]);I.Attach(IME.ctx,IME.font)
    IME.active=true;IME.frames=0;IME.key=key;IME.metrics=nil
    wake_visuals();next_draw_time=0
  end)
  if not ok then IME.stop(false);notice("日本語入力欄を初期化できません。\n"..tostring(err),true) end
  return ok
end
function IME.frame()
  if not IME.active then return end
  if not E or E.key~=IME.key then IME.stop(false);return end
  local b=IME.bounds[IME.key];if not b then return end
  local I,ctx=IME.api,IME.ctx
  local nx,ny=gfx.clienttoscreen(sx(b.x),sy(b.y))
  local ex,ey=gfx.clienttoscreen(sx(b.x+b.w),sy(b.y+b.h))
  local x,y=I.PointConvertNative(ctx,nx,ny)
  local x2,y2=I.PointConvertNative(ctx,ex,ey)
  local w,h=math.abs(x2-x),math.abs(y2-y)
  x,y=min(x,x2),min(y,y2)
  local unit=w/b.w;local size=max(8,15*unit)
  -- Focus after the native input window exists and gfx has released the mouse.
  local focus_now=IME.frames==1
  I.SetNextWindowPos(ctx,x,y,I.Cond_Always);I.SetNextWindowSize(ctx,w,h,I.Cond_Always)
  if focus_now then I.SetNextWindowFocus(ctx) end
  I.PushStyleVar(ctx,I.StyleVar_WindowPadding,0,0)
  I.PushStyleVar(ctx,I.StyleVar_WindowMinSize,1,1)
  I.PushStyleVar(ctx,I.StyleVar_WindowRounding,0)
  I.PushStyleVar(ctx,I.StyleVar_WindowBorderSize,0)
  I.PushStyleVar(ctx,I.StyleVar_FrameRounding,0)
  I.PushStyleVar(ctx,I.StyleVar_FrameBorderSize,0)
  I.PushStyleVar(ctx,I.StyleVar_FramePadding,max(2,12*unit),max(0,(h-size)/2))
  I.PushStyleColor(ctx,I.Col_WindowBg,ime_color(C.field))
  I.PushStyleColor(ctx,I.Col_FrameBg,ime_color(C.field))
  I.PushStyleColor(ctx,I.Col_Text,ime_color(C.text))
  I.PushStyleColor(ctx,I.Col_TextDisabled,ime_color(C.faint))
  I.PushStyleColor(ctx,I.Col_TextSelectedBg,ime_color(C.accent3))
  I.PushFont(ctx,IME.font,size)
  local flags=I.WindowFlags_NoDecoration|I.WindowFlags_NoMove|I.WindowFlags_NoSavedSettings|I.WindowFlags_NoDocking
  local shown=I.Begin(ctx,"BLT Affix##"..IME.key,nil,flags)
  local finish,cancel,focused=false,false,true
  if shown then
    local dpi=I.GetWindowDpiScale(ctx);local m=IME.metrics
    if not m or m.scale~=scale or m.unit~=unit or m.dpi~=dpi then
      local sample="あいうえお漢字ABC012345"
      local target=measure(sample,15,1,false)*unit;local measured=I.CalcTextSize(ctx,sample)
      m={scale=scale,unit=unit,dpi=dpi,size=measured>0 and clamp(size*target/measured,1,96) or size};IME.metrics=m
    end
    I.PopFont(ctx);I.PushFont(ctx,IME.font,m.size)
    I.PushStyleVar(ctx,I.StyleVar_FramePadding,max(2,12*unit),max(0,(h-I.GetTextLineHeight(ctx))/2))
    I.SetNextItemWidth(ctx,w)
    if focus_now then I.SetKeyboardFocusHere(ctx) end
    local text
    finish,text=I.InputTextWithHint(ctx,"##affix",Language.text("追加なし"),Core.Edit.value(E),I.InputTextFlags_EnterReturnsTrue)
    cancel=I.IsItemDeactivated(ctx) and I.IsKeyPressed(ctx,I.Key_Escape,false)
    if text~=Core.Edit.value(E) then
      local trial=Core.Edit.new(text);trial.key=E.key
      local value,err=edit_value(trial)
      if value then E=trial;A.edit_dirty=R.time_precise()+.15;A.applied=false;wake_visuals()
      else A.flash_field(E.key);notice(err.." 元の値へ戻しました。",true) end
    end
    local list=I.GetWindowDrawList(ctx);local lx,ly=I.GetItemRectMin(ctx);local rx,ry=I.GetItemRectMax(ctx)
    I.DrawList_AddRectFilled(list,lx,ry-max(.5,unit),rx,ry,ime_color(C.accent2,.65))
    focused=I.IsWindowFocused(ctx)
    I.PopStyleVar(ctx);I.End(ctx)
  end
  I.PopFont(ctx);I.PopStyleColor(ctx,5);I.PopStyleVar(ctx,7)
  IME.frames=IME.frames+1
  if cancel then commit_edit(true);IME.stop(true)
  elseif finish then if commit_edit() then IME.stop(true) end
  elseif IME.frames>2 and not focused then commit_edit() end
end

local function begin_input_draw(key,x,y,w,h,placeholder)
  IME.bounds[key]={x=x,y=y,w=w-31,h=h}
  local editing=E and E.key==key
  local clearable=key=="prefix" or key=="suffix"
  local clear_w=clearable and 31 or 0
  local text_right=w-24-clear_w
  local hovered=inside(x,y,w,h) and not A.parser
  local a=animate("input_"..key,editing and 1 or (hovered and .22 or 0))
  local flash=A.field_flash_value(key)
  gradient(x,y,w,h,C.field,C.panel,.98,.56)
  if flash>0 then rect(x-4,y-4,w+8,h+8,C.red,.025*flash); gradient(x,y,w,h,C.red,C.field,.22*flash,.02*flash,true) end
  line(x,y,x+w,y,flash>0 and C.red or C.edge2,.18+.35*a+.45*flash); line(x,y+h-1,x+w,y+h-1,C.edge,.38+.25*a)
  line(x,y,x,y+h,flash>0 and C.red or C.accent2,.20+.48*a+.42*flash)
  if a>.01 then glow_line(x+1,y+h-1,x+min(76,w-8),y+h-1,C.accent2,.23*a) end
  finish_corners(x,y,w,h,6,false,flash>0 and C.red or C.edge2,.28+.38*a+.42*flash)

  local value=editing and Core.Edit.value(E) or S[key]
  local filled=clearable and value~=""
  if filled then
    local phase=anim_time*1.35+(key=="prefix" and 0 or 1.43)
    local pulse=.5+.5*math.sin(phase)
    local core=.68+.22*pulse

    for d=9,1,-1 do
      local fall=(10-d)/9
      local alpha=(.010+.020*fall)*(.72+.28*pulse)
      local c=d>5 and C.accent or (d>2 and C.accent3 or C.accent2)
      line(x+4-d,y-d,x+w-10+d,y-d,c,alpha)
      line(x+4-d,y+h-1+d,x+w-12+d,y+h-1+d,c,alpha*.92)
      line(x-d,y+6-d*.22,x-d,y+h-8+d*.22,c,alpha*.96)
      line(x+w-1+d,y+6-d*.22,x+w-1+d,y+h-10+d*.22,c,alpha*.78)
    end

    local bloom=.010+.010*pulse
    for _,b in ipairs({
      {x+18,y+2,18},{x+w*.33,y+1,15},{x+w*.67,y+1,15},{x+w-20,y+3,18},
      {x+15,y+h-2,16},{x+w*.40,y+h-1,14},{x+w*.72,y+h-1,14},{x+w-18,y+h-3,16},
      {x+1,y+h*.35,15},{x+1,y+h*.68,15},{x+w-1,y+h*.38,14},{x+w-1,y+h*.66,14}
    }) do
      disc(b[1],b[2],b[3],C.accent,bloom)
      disc(b[1],b[2],b[3]*.58,C.accent3,bloom*1.55)
      disc(b[1],b[2],b[3]*.28,C.accent2,bloom*2.15)
    end

    glow_line(x+3,y+1,x+w-9,y+1,C.accent2,core)
    glow_line(x+4,y+h-1,x+w-11,y+h-1,C.focus2,.78*core)
    glow_line(x+1,y+6,x+1,y+h-8,C.accent2,.84*core)
    glow_line(x+w-1,y+6,x+w-1,y+h-10,C.accent2,.54*core)
    line(x+3,y+2,x+w-9,y+2,C.accent2,.56+.16*pulse)
    line(x+4,y+h-2,x+w-11,y+h-2,C.focus2,.48+.14*pulse)
    line(x+2,y+6,x+2,y+h-8,C.accent2,.52+.15*pulse)
    line(x+w-2,y+6,x+w-2,y+h-10,C.accent2,.38+.12*pulse)
    finish_corners(x,y,w,h,6,false,C.focus2,.72+.18*pulse)

    disc(x+4,y+4,10,C.accent,.018+.014*pulse)
    disc(x+4,y+4,5,C.accent2,.040+.026*pulse)
    disc(x+w-7,y+h-7,10,C.accent,.016+.012*pulse)
    disc(x+w-7,y+h-7,4.8,C.focus2,.036+.024*pulse)
  end
  local positions=nil
  if not (clearable and IME.active and IME.key==key) then
  font(15,1,false)
  local function width(a1,b1)
    if not editing or b1<a1 then return 0 end
    return BLT.metricsFor(table.concat(E.chars,"",a1,b1))/scale
  end
  if editing then
    E.view=clamp(E.view,0,#E.chars)
    if E.cursor<E.view then E.view=E.cursor end
    while E.view<E.cursor and width(E.view+1,E.cursor)>w-30-clear_w do E.view=E.view+1 end
    positions={{index=E.view,x=x+12}}
    for i=E.view+1,#E.chars do
      local tx=x+12+width(E.view+1,i)
      positions[#positions+1]={index=i,x=tx}
      if tx>x+w-12-clear_w then break end
    end
    local a1,b1=min(E.cursor,E.anchor),max(E.cursor,E.anchor)
    local left=x+12+width(E.view+1,max(E.view,a1))
    local right=x+12+width(E.view+1,max(E.view,b1))
    if b1>E.view then rect(left,y+5,max(0,min(x+w-12-clear_w,right)-left),h-10,C.focus2,.90) end
    value=table.concat(E.chars,"",E.view+1)
  end
  local has_selection=editing and E.cursor~=E.anchor
  label(value=="" and (placeholder or "") or value,x+12,y,15,value=="" and C.faint or (has_selection and C.ink or C.text),1,text_right,h,4,false,value~="")
  if editing and E.cursor==E.anchor and R.time_precise()%1<.65 then
    local cx=x+12+width(E.view+1,E.cursor)
    line(cx,y+5,cx,y+h-6,C.accent2,.86)
  end
  end
  widget(key,x,y,w-clear_w,h,function()
    if not begin_edit(key) then return end
    if positions then
      local near=positions[1]
      for _,p in ipairs(positions) do if math.abs(mx-p.x)<math.abs(mx-near.x) then near=p end end
      Core.Edit.move(E,near.index,(gfx.mouse_cap&8)~=0)
    end
  end,A.numeric_field(key) and "クリック：直接入力 ／ 上下ドラッグ：1刻み" or "直接入力 ／ Ctrl+A：全選択 ／ Shift＋矢印：範囲選択 ／ Ctrl+V：この欄に貼付",not A.parser)

  if clearable then
    local cx,cy=x+w-28,y+4
    local cw,ch=24,h-8
    local can_clear=not A.parser and ((editing and Core.Edit.value(E)~="") or (not editing and S[key]~=""))
    local hov=inside(cx,cy,cw,ch) and can_clear
    local ca=animate("input_clear_"..key,hov and 1 or 0)
    local pressed=can_clear and A.pressed=="clear_field_"..key and (gfx.mouse_cap&1)~=0
    local cc=can_clear and C.accent2 or C.edge2
    cut_panel(cx,cy,cw,ch,3,can_clear and C.accent3 or C.panel2,
      can_clear and (pressed and .62 or .22+.18*ca) or .12,cc,can_clear and (.60+.30*ca) or .25)
    local al=can_clear and (.86+.14*ca) or .30
    local dy=pressed and 1 or 0
    for offset=0,1 do
      line(cx+7+offset,cy+7+dy,cx+16+offset,cy+ch-7+dy,cc,al)
      line(cx+16+offset,cy+7+dy,cx+7+offset,cy+ch-7+dy,cc,al)
    end
    widget("clear_field_"..key,cx,cy,cw,ch,function() clear_text_field(key) end,
      (key=="prefix" and "接頭詞" or "末尾詞").."をクリアします。",can_clear)
  end
end
local function input(key,x,y,w,h,placeholder) begin_input_draw(key,x,y,w,h,placeholder) end

local function display_name(s) return s=="" and "〈空欄〉" or s:gsub("[\r\n\t]"," ") end
local T={x=24,y=462,w=992,h=282,row=23,header=28,bar=16}
local function visible() return floor((T.h-T.header)/T.row) end
local function max_offset() return max(0,#A.filtered-visible()) end
local function scroll(delta) A.offset=clamp(A.offset+delta,0,max_offset()) end
local kind_text={rename="変更予定",blank="無名にする",empty_skip="空行・維持",empty_affix="接頭/末尾のみ",missing="変更先なし・維持",
  extra="余り・未使用",same="同名・維持",unsupported="テイクなし",idle="入力待ち"}
local function seek_item(row)
  local info=row and row.info
  if not info or R.EnumProjects(-1,"")~=A.project then return end
  if not R.ValidatePtr2(A.project,info.item,"MediaItem*") then return end
  local position=R.GetMediaItemInfo_Value(info.item,"D_POSITION")
  if finite(position) then R.SetEditCurPos2(A.project,position,true,true) end
end
local function row_color(row)
  if row.duplicate then return C.warn end
  if row.kind=="missing" or row.kind=="extra" then return C.warn end
  if row.kind=="blank" then return C.focus2 end
  return row.change and C.accent2 or C.faint
end
local function draw_table()
  A.offset=clamp(A.offset,0,max_offset())
  gradient(T.x,T.y,T.w,T.h,C.field,C.panel,.98,.20,true)
  rect(T.x,T.y,T.w,T.header,C.panel2,.92)
  line(T.x,T.y,T.x+T.w,T.y,C.edge2,.55)
  line(T.x,T.y+T.header,T.x+T.w,T.y+T.header,C.edge,.44)
  finish_corners(T.x,T.y,T.w,T.h,9,false,C.edge2,.34)
  local cols={T.x+8,T.x+58,T.x+106,T.x+485,T.x+864}
  local widths={50,48,379,379,112}
  label("#",cols[1],T.y+7,10,C.faint,3,widths[1],17,0,true)
  label("TRACK",cols[2],T.y+7,9,C.faint,3,widths[2],17,0,true)
  label("変更前",cols[3],T.y+5,11,C.muted,1,widths[3],20,0,true)
  label("変更後",cols[4],T.y+5,11,C.muted,1,widths[4],20,0,true)
  label("状態",cols[5],T.y+5,11,C.muted,1,widths[5],20,0,true)
  for slot=1,visible() do
    local fi=A.offset+slot; local ri=A.filtered[fi]; local row=ri and A.rows[ri]
    if row then
      local y=T.y+T.header+(slot-1)*T.row
      if A.focus==ri then
        gradient(T.x+1,y,T.w-T.bar-2,T.row,C.accent3,C.panel2,.45,.12)
        rect(T.x+1,y,2,T.row,C.accent2,.82)
      elseif fi%2==0 then rect(T.x+1,y,T.w-T.bar-2,T.row,C.panel,.42) end
      local c=row_color(row)
      label(row.number,cols[1],y+3,10,C.faint,3,widths[1]-4,18,0,false)
      label(row.info and string.format("%02d",row.info.tracknum) or "—",cols[2],y+3,11,C.muted,3,widths[2]-4,18,0,false)
      label(row.info and display_name(row.before) or "—",cols[3],y+2,12,C.muted,1,widths[3]-8,20,0,false,true)
      label(display_name(row.after),cols[4],y+2,12,c,1,widths[4]-8,20,0,row.change,true)
      local status=A.applied and row.change and "変更済み" or (row.duplicate and "重複注意" or kind_text[row.kind])
      label(status,cols[5],y+3,10,c,1,widths[5]-8,18,0,true)
      widget("row_"..ri,T.x,y,T.w-T.bar,T.row,function()
        local now=R.time_precise()
        if A.focus==ri and A.last_row_click and now-A.last_row_click<.4 then seek_item(row) end
        A.focus=ri; A.last_row_click=now
      end,"ダブルクリック：アイテムの開始位置へ再生カーソルを移動します。",true)
    end
  end

  local bx,by,bh=T.x+T.w-T.bar,T.y+T.header,T.h-T.header
  rect(bx,by,T.bar,bh,C.panel,.92)
  local thumb_h=#A.filtered>0 and max(26,bh*min(1,visible()/#A.filtered)) or bh
  local thumb_y=by+(max_offset()>0 and A.offset/max_offset()*(bh-thumb_h) or 0)
  rect(bx+4,thumb_y+1,T.bar-8,thumb_h-2,scroll_drag and C.accent2 or C.edge2,scroll_drag and .88 or .54)
  A.scrollbar={x=bx,y=by,w=T.bar,h=bh,thumb_y=thumb_y,thumb_h=thumb_h}
end

local function jump()
  if not commit_edit() then return end
  A.jump={text=tostring(A.offset+1),selected=true}
  notice("移動先の行番号を入力し、Enterで確定します。")
end
local function commit_jump()
  local j=A.jump;if not j then return true end
  local raw=tonumber(j.text);local hi=max(1,#A.filtered)
  if not finite(raw) then A.flash_field("jump_row");j.text=tostring(A.offset+1);j.selected=true;notice("行番号を入力できなかったため、現在行へ戻しました。",true);return false end
  local n=clamp(floor(raw+.5),1,hi);local clipped=n~=raw
  A.offset=clamp(n-1,0,max_offset());j.text=tostring(n);j.selected=true
  if clipped then A.flash_field("jump_row");notice(string.format("行番号を1～%dへ補正しました。",hi),true);return false end
  A.jump=nil;return true
end
local function draw_jump_field(x,y,w,h)
  local flash=A.field_flash_value("jump_row");local hot=inside(x,y,w,h)
  gradient(x,y,w,h,C.field,C.panel,.98,.56)
  if flash>0 then rect(x-4,y-4,w+8,h+8,C.red,.025*flash);gradient(x,y,w,h,C.red,C.field,.22*flash,.02*flash,true) end
  line(x,y,x+w,y,flash>0 and C.red or C.edge2,hot and .75 or .35);line(x,y+h,x+w,y+h,C.edge,.45)
  finish_corners(x,y,w,h,5,false,flash>0 and C.red or C.edge2,.35+.45*flash)
  local value=A.jump.text
  if A.jump.selected then rect(x+7,y+4,w-14,h-8,C.focus2,.84) end
  label(value,x+8,y,14,A.jump.selected and C.ink or C.text,3,w-16,h,5,true)
  widget("jump_row",x,y,w,h,function() A.jump.selected=true end,"行番号を直接入力 ／ 上下ドラッグ・ホイール：1行",true)
end
local function stat(title,n,x,w,c)
  local y=370
  gradient(x,y,w,48,C.panel2,C.panel,.25,.65)
  line(x,y,x+w,y,C.edge2,.24); line(x,y+48,x+w,y+48,C.edge,.30)
  finish_corners(x,y,w,48,7,false,C.edge2,.28)
  label(title,x+11,y+6,9.5,C.muted,1,w-22,16,0,true)
  label(n or 0,x+11,y+20,21,c or C.text,3,w-22,24,2,true)
end

local function draw_primary_button(id,text,x,y,w,h,fn,hint,enabled)
 enabled=enabled~=false
 PrimaryButton.draw(PrimaryButton.painter,x,y,w,h,text,'EXECUTE',enabled,false,nil,inside(x,y,w,h),A.pressed==id and (gfx.mouse_cap&1)~=0,R.time_precise(),BLT.host.active())
 widget(id,x,y,w,h,fn,hint,enabled)
end

local function modal_button(id,text,x,y,w,h,fn,hint,primary)
  local hovered=inside(x,y,w,h)
  local a=animate("modal_button_"..id,hovered and 1 or 0)
  gradient(x,y,w,h,primary and C.accent3 or C.panel2,C.panel,.48+.16*a,.90)
  gradient(x,y,w,1,C.accent2,C.accent2,.22+.54*a,.02)
  line(x,y+h,x+w,y+h,C.edge,.58)
  if hovered then rect(x,y,2,h,C.accent2,.74*a) end
  finish_corners(x,y,w,h,7,true,primary and C.accent2 or C.edge2,(primary and .66 or .40)+.24*a)
  if primary then
    line(x+8,y,x+w-12,y,C.accent2,.44+.24*a)
    line(x,y+7,x,y+h-9,C.accent2,.30+.24*a)
  end
  label(text,x,y+1,13,hovered and C.text or C.muted,1,w,h-2,5,true)
  widget(id,x,y,w,h,fn,hint,true)
end

local function draw_duplicate_modal()
  if not A.duplicate_modal then return end

  -- Modal owns all input while open; the underlying preview remains visible but inert.
  widgets={}
  hover=""
  rect(0,0,W,H,C.bg,.74)
  gradient(0,0,W,H,C.bg2,C.bg,.08,.28,true)

  local x,y,w,h=220,222,600,438
  disc(x+w*.50,y+h*.42,250,C.accent,.010)
  cut_panel(x,y,w,h,12,C.panel,.985,C.edge2,.58,true)
  gradient(x+2,y+2,w-5,70,C.panel2,C.panel,.52,.04,true)
  glow_line(x+18,y+1,x+174,y+1,C.accent2,.46)
  line(x+18,y+70,x+w-18,y+70,C.edge2,.22)

  label("DUPLICATE NAME",x+24,y+16,8,C.warn,3,220,14,0,true)
  label("リネームの結果重複するファイル名があります",x+24,y+31,22,C.text,1,w-48,34,0,true)
  right_label(string.format("%d GROUPS / %d ITEMS",A.stats.duplicate_groups or 0,A.stats.duplicate_items or 0),x+w-24,y+20,8,C.muted,3,true)

  label("必要であればキャンセルして、接頭詞・末尾詞や連番を調整してください。",x+24,y+88,11,C.faint,1,w-48,20,0,false)

  local groups=A.stats.duplicates or {}
  local shown=min(#groups,6)
  local row_y=y+126
  for i=1,shown do
    local g=groups[i]
    local ry=row_y+(i-1)*35
    if i%2==0 then rect(x+22,ry-3,w-44,30,C.field,.34) end
    rect(x+26,ry+5,3,13,C.warn,.78)
    label(duplicate_display_name(g.name,45),x+40,ry-1,12.5,C.text,1,w-145,25,0,i==1,true)
    right_label(string.format("× %d",#g.rows),x+w-34,ry+1,11.5,C.warn,3,true)
  end
  if #groups>shown then
    label(string.format("ほか %d組",#groups-shown),x+40,row_y+shown*35+1,10.5,C.faint,1,w-80,19,0,false)
  end

  line(x+22,y+h-72,x+w-22,y+h-72,C.edge2,.20)
  modal_button("modal_cancel","キャンセル",x+50,y+h-59,218,43,cancel_duplicate_modal,"Esc：キャンセル",false)
  modal_button("modal_confirm","このまま実行",x+w-268,y+h-59,218,43,confirm_duplicate_modal,"Enter：同名を許可して実行",true)
end

local function draw()
  local contentH=max(1,gfx.h-Chrome.titleH); scale=max(.30,min(gfx.w/W,contentH/H)); ox,oy=(gfx.w-W*scale)/2,Chrome.titleH+(contentH-H*scale)/2-22*scale
 BLT.viewport(scale,gfx.ext_retina or 1);  mx,my=(gfx.mouse_x-ox)/scale,(gfx.mouse_y-oy)/scale
  widgets={}; hover=""; gfx.clear=-1;gfx.set(C.bg[1],C.bg[2],C.bg[3],1);gfx.rect(0,0,gfx.w,gfx.h,1)
  local now=R.time_precise(); particle_dt=max(0,min(.10,now-frame_clock)); frame_clock=now
  frame_dt=animations_active and particle_dt*animation_speed or 0; anim_time=anim_time+frame_dt
  draw_background()

  BLT.title('BATCH RENAME','BATCH ITEM RENAME  選択アイテム名を一括変更',W)
  right_label("選択を自動反映",884,66,8,C.faint,1,true)
  BLT.drawIcon()

  label("入力",22,101,9.5,C.accent2,1,70,16,0,true)
  gradient(58,109,958,1,C.edge2,C.edge2,.28,.02)
  choice_card("read","クリップボードの内容を反映","APPLY",22,114,770,50,not A.loaded,function() if commit_edit() then read_clipboard() end end,
    "クリップボード／Excelの先頭列を読み込み、プレビューへ反映します。上のトラックから開始位置順に対応し、途中の空行は詰めません。",not A.parser)
  choice_card("clear_paste","クリア","CLEAR",808,114,208,50,A.loaded or A.input_error,clear_paste,
    "このツールに取り込んだ名前だけをクリアします。クリップボード本体は変更しません。",not A.parser and (A.loaded or A.input_error),true)

  draw_glass_group(22,173,490,126,"PREFIX")
  label("接頭詞",34,190,16,C.text,1,220,22,0,true)
  input("prefix",34,216,466,36,"追加なし（入力があれば有効化します）")
  rect(32,258,344,34,C.field,.36)
  line(32,258,376,258,C.edge2,.22); line(32,292,376,292,C.edge,.20)
  label("連番 {n}",40,264,12,C.accent2,1,58,20,4,true)
  label("開始",91,264,12,C.muted,1,27,20,6,true)
  input("prefix_start",125,260,72,30,"0")
  numeric_stepper("prefix_start","prefix_start",197,260,20,30)
  label("桁数",218,264,12,C.muted,1,27,20,6,true)
  input("prefix_digits",252,260,38,30,"3")
  numeric_stepper("prefix_digits","prefix_digits",290,260,20,30)
  small_button("number_prefix","{n} 挿入",316,260,56,30,function() insert_number("prefix") end,
    "接頭詞のカーソル位置へ、選択順の連番 {n} を挿入します。",not A.parser)
  line(386,261,386,289,C.edge2,.22)
  small_button("name_prefix","{name} 元の名前",396,260,104,30,function() insert_current_name("prefix") end,
    "接頭詞のカーソル位置へ、現在のアクティブテイク名 {name} を挿入します。",not A.parser)

  draw_glass_group(528,173,488,126,"SUFFIX")
  label("末尾詞",540,190,16,C.text,1,220,22,0,true)
  input("suffix",540,216,464,36,"追加なし（入力があれば有効化します）")
  rect(538,258,344,34,C.field,.36)
  line(538,258,882,258,C.edge2,.22); line(538,292,882,292,C.edge,.20)
  label("連番 {n}",546,264,12,C.accent2,1,58,20,4,true)
  label("開始",597,264,12,C.muted,1,27,20,6,true)
  input("suffix_start",631,260,72,30,"0")
  numeric_stepper("suffix_start","suffix_start",703,260,20,30)
  label("桁数",724,264,12,C.muted,1,27,20,6,true)
  input("suffix_digits",758,260,38,30,"3")
  numeric_stepper("suffix_digits","suffix_digits",796,260,20,30)
  small_button("number_suffix","{n} 挿入",822,260,56,30,function() insert_number("suffix") end,
    "末尾詞のカーソル位置へ、選択順の連番 {n} を挿入します。",not A.parser)
  line(892,261,892,289,C.edge2,.22)
  small_button("name_suffix","{name} 元の名前",902,260,102,30,function() insert_current_name("suffix") end,
    "末尾詞のカーソル位置へ、現在のアクティブテイク名 {name} を挿入します。",not A.parser)

  label("{n} = 選択順の連番    {name} = 現在のテイク名    貼付名は接頭詞と末尾詞の間に入ります。",24,309,10.5,C.muted,1,992,16,0,false)

  label("空行の扱い",24,335,12.5,C.text,1,86,18,2,true)
  glow_line(112,341,126,341,C.accent2,.42)
  glow_line(118,356,556,356,C.edge2,.18)
  glow_line(218,352,218,356,C.edge2,.16)
  glow_line(370,352,370,356,C.edge2,.16)
  glow_line(490,352,490,356,C.edge2,.16)
  rect(120,339,3,3,C.accent2,.70)
  segment_button("affix_only","接頭/末尾詞のみ反映",130,328,176,27,S.empty=="affix",function() change_setting("empty","affix") end,
    "空行では貼付名を使わず、接頭詞・末尾詞だけを反映します。{n} と {name} も展開されます。",A.loaded and not A.parser)
  segment_button("skip","変更しない",314,328,112,27,S.empty=="skip",function() change_setting("empty","skip") end,
    "貼付データの空行に対応するアイテムは、接頭詞・末尾詞も含めて変更しません。",A.loaded and not A.parser)
  segment_button("clear","無名にする",434,328,112,27,S.empty=="clear",function() change_setting("empty","clear") end,
    "貼付データの空行に対応するテイク名を空にします。元ファイル名は変更しません。",A.loaded and not A.parser)
  label(A.loaded and "空行は行位置を維持します。" or "貼付後に空行の扱いを選択できます。",564,333,9,C.faint,1,246,18,0,false)
  local st=A.stats
  stat("リネーム対象アイテム",st.selected,24,184)
  stat("入力行",st.input,224,184)
  stat(A.applied and "変更済み" or "変更予定",st.change,424,184,C.accent2)
  stat("変更先なし",st.missing,624,184,(st.missing or 0)>0 and C.warn or C.text)
  stat("余り・未使用",st.extra,824,192,(st.extra or 0)>0 and C.warn or C.text)
  label(string.format("空行維持 %d  /  無名化 %d  /  接頭末尾のみ %d  /  同名 %d  /  テイクなし %d",
    st.empty_skip or 0,st.blank or 0,st.empty_affix or 0,st.same or 0,st.unsupported or 0),27,429,8.5,C.muted,1,590,18,0,false)
  for i,entry in ipairs({{"all","全件"},{"changes","変更分"},{"unchanged","維持分"},{"extra","余り"}}) do
    local key,text=entry[1],entry[2]
    segment_button("filter_"..key,text,638+(i-1)*96,424,90,27,A.filter==key,function() A.filter=key; filter_rows() end,
      "表示の絞り込みです。実行対象は変わりません。",true)
  end

  draw_table()
  local first=#A.filtered>0 and A.offset+1 or 0
  label(string.format("表示  %d–%d / %d 行",first,min(#A.filtered,A.offset+visible()),#A.filtered),28,752,9,C.faint,1,300,18,0,false)
  small_button("top","先頭",760,749,70,25,function() A.offset=0 end,nil,true)
  small_button("bottom","末尾",840,749,70,25,function() A.offset=max_offset() end,nil,true)
  if A.jump then draw_jump_field(920,749,96,25) else small_button("jump","行へ移動",920,749,96,25,jump,nil,true) end

  local exec_enabled=not A.parser and not A.invalid and not A.applied and not A.edit_dirty and (not E or edit_value(E)~=nil) and (st.change or 0)>0
  draw_primary_button("execute",A.applied and "変更済み" or string.format("%d件をリネーム",st.change or 0),350,784,340,46,execute,
    "表示フィルターに関係なく、変更予定の全件を適用します。1回のUndoで戻せます。",exec_enabled)

  local message=A.message
  local message_bad=A.bad or false
  if A.parser then
    message=string.format("テキスト解析  %d%%",floor(100*(A.parser.p-1)/max(1,#A.parser.text)))
  elseif E then
    local _,err=edit_value(E); if err then message=err; message_bad=true end
  elseif not A.applied and not A.bad and (st.duplicate_groups or 0)>0 then
    message=string.format("注意：変更後に同名となる名前が %d組（%dアイテム）あります。実行時に確認します。",st.duplicate_groups,st.duplicate_items or 0)
    message_bad=true
  end
  BLT.footer(message,message_bad,W,H+22,'0.5.0')
  draw_duplicate_modal()
  custom_titlebar()
end

local function interact()
 if BLT.blocked() then down_last=(gfx.mouse_cap&1)~=0;pressed=nil;gfx.mouse_wheel=0;return end

  if Chrome.mouseActive then last_down=(gfx.mouse_cap&1)~=0; A.pressed=nil; scroll_drag=nil; A.field_drag=nil; return end
  local bar=A.duplicate_modal and nil or A.scrollbar; local down=(gfx.mouse_cap&1)~=0
  local hit=nil
  for i=#widgets,1,-1 do local w=widgets[i]; if inside(w.x,w.y,w.w,w.h) then hit=w; break end end
  if down and not last_down and A.jump and (not hit or hit.id~="jump_row") then
    if not commit_jump() then A.pressed=nil;last_down=down;return end
  end
  if down and not last_down then
    pressed_generation=A.generation
    if bar and inside(bar.x,bar.y,bar.w,bar.h) then
      if my>=bar.thumb_y and my<=bar.thumb_y+bar.thumb_h then scroll_drag=my-bar.thumb_y
      else scroll(my<bar.thumb_y and -visible() or visible()) end
      A.pressed=nil
    else
      A.pressed=hit and hit.id or nil
      if A.jump and hit and hit.id=="jump_row" then
        A.jump.selected=true;A.jump.drag={start_y=my,start_value=tonumber(A.jump.text) or A.offset+1,moved=false,clipped=false}
      elseif hit and hit.enabled and A.numeric_field(hit.id) and commit_edit() then
        if A.applied then refresh() end
        A.field_drag={key=hit.id,start_y=my,start_value=tonumber(S[hit.id]) or 0,moved=false,clipped=false}
      end
    end
  elseif down and scroll_drag and bar then
    local travel=bar.h-bar.thumb_h
    if travel>0 then A.offset=floor(clamp((my-bar.y-scroll_drag)/travel,0,1)*max_offset()+.5) end
  elseif down and A.jump and A.jump.drag then
    local d=A.jump.drag;local dy=d.start_y-my
    if not d.moved and math.abs(dy)>=3 then d.moved=true end
    if d.moved then
      local q=dy/3;local ticks=(q<0 and -1 or 1)*floor(math.abs(q)+.5);local hi=max(1,#A.filtered)
      local raw=d.start_value+ticks;local value=clamp(raw,1,hi)
      if value~=raw and not d.clipped then A.flash_field("jump_row");d.clipped=true elseif value==raw then d.clipped=false end
      A.jump.text=tostring(value);A.jump.selected=false;A.offset=clamp(value-1,0,max_offset())
    end
  elseif down and A.field_drag then
    A.update_field_drag(my)
  elseif not down and last_down then
    local was_field_drag=A.field_drag and A.field_drag.moved
    local was_jump_drag=A.jump and A.jump.drag and A.jump.drag.moved
    if A.jump then A.jump.drag=nil end
    A.field_drag=nil
    if not scroll_drag and not was_field_drag and not was_jump_drag and hit and hit.enabled and hit.id==A.pressed and pressed_generation==A.generation then
      local keep=E and (hit.id==E.key or hit.id=="number_"..E.key or hit.id=="name_"..E.key)
      if keep or commit_edit() then hit.fn() end
    elseif not hit then if A.jump then commit_jump() else commit_edit() end end
    scroll_drag=nil; A.pressed=nil
  end
  last_down=down
  local wheel=gfx.mouse_wheel or 0
  if wheel~=0 then
    gfx.mouse_wheel=0
    if not A.duplicate_modal and A.jump and hit and hit.id=="jump_row" then
      local hi=max(1,#A.filtered);local current=tonumber(A.jump.text) or A.offset+1
      local notches=max(1,floor(math.abs(wheel)/120+.5));local raw=current+(wheel>0 and 1 or -1)*notches
      local value=clamp(raw,1,hi);if value~=raw then A.flash_field("jump_row") end
      A.jump.text=tostring(value);A.jump.selected=false;A.offset=clamp(value-1,0,max_offset())
    elseif not A.duplicate_modal and hit and hit.enabled and A.numeric_field(hit.id) and commit_edit() then
      if A.applied then refresh() end
      local lo,hi=Core.numeric_bounds(hit.id)
      local current=tonumber(S[hit.id]) or lo
      local notches=max(1,floor(math.abs(wheel)/120+.5))
      local raw=current+(wheel>0 and 1 or -1)*notches
      local value=clamp(raw,lo,hi)
      if value~=raw then A.flash_field(hit.id) end
      if value~=current then S[hit.id]=tostring(value);persist();A.applied=false;rebuild() end
    elseif not A.duplicate_modal and inside(T.x,T.y,T.w,T.h) then
      scroll((wheel>0 and -1 or 1)*((gfx.mouse_cap&8)~=0 and visible() or 3))
    end
  end
end

local function keypress(k)
 k=BLT.key(k);if k==0 then return end

  if IME.active then return end
  if A.duplicate_modal then
    if k==27 then cancel_duplicate_modal()
    elseif k==13 then confirm_duplicate_modal() end
    return
  end
  if A.jump then
    local j=A.jump
    if k==27 then A.jump=nil;notice("行移動を取り消しました。")
    elseif k==13 then commit_jump()
    elseif k==1 then j.selected=true
    elseif k==8 or k==6579564 then j.text=j.selected and "" or j.text:sub(1,-2);j.selected=false
    elseif k>=48 and k<=57 then
      local c=string.char(k);j.text=j.selected and c or (#j.text<9 and j.text..c or j.text);j.selected=false
    end
    return
  end
  if E then
    local shift=(gfx.mouse_cap&8)~=0
    if k==27 then commit_edit(true)
    elseif k==13 then commit_edit()
    elseif k==9 then
      local keys={"prefix","prefix_start","prefix_digits","suffix","suffix_start","suffix_digits"}
      local index=1; for i,key in ipairs(keys) do if E.key==key then index=i end end
      local target=keys[(index-1+(shift and -1 or 1))%#keys+1]
      if commit_edit() then begin_edit(target) end
    elseif k==1 then E.anchor=0; E.cursor=#E.chars
    elseif k==22 then local text=Core.clipboard(); edit_insert(Core.text(text))
    elseif k==8 or k==6579564 then Core.Edit.delete(E,k==8); A.edit_dirty=R.time_precise()+.15
    elseif k==1818584692 or k==1919379572 then
      local left=k==1818584692
      local pos=E.cursor+(left and -1 or 1)
      if not shift and E.cursor~=E.anchor then pos=left and min(E.cursor,E.anchor) or max(E.cursor,E.anchor) end
      Core.Edit.move(E,pos,shift)
    elseif k==1752132965 then Core.Edit.move(E,0,shift)
    elseif k==6647396 then Core.Edit.move(E,#E.chars,shift)
    elseif (gfx.mouse_cap&20)==0 then
      local cp=k
      if (k>>24)==117 then cp=k&0xFFFFFF end
      if (k<=255 or (k>>24)==117) and cp>=32 and cp~=127 and cp<=0x10FFFF and not (cp>=0xD800 and cp<=0xDFFF) then edit_insert(utf8.char(cp)) end
    end
    return
  end
  if k==27 then A.closing=true
  elseif k==22 and not A.parser then read_clipboard()
  elseif k==1752132965 then A.offset=0
  elseif k==6647396 then A.offset=max_offset()
  elseif k==1885828464 then scroll(-visible())
  elseif k==1885824110 then scroll(visible())
  elseif k==30064 then scroll(-1)
  elseif k==1685026670 then scroll(1) end
end

local function save_window()
  local _,x,y,w,h=gfx.dock(-1,0,0,0,0)
  for key,v in pairs({window_x=x,window_y=y,window_w=w,window_h=h}) do
    if finite(v) then BLT.store(SECTION,key,tostring(floor(v+.5)),true) end
  end
end
local function close()
 -- Teardown errors must not leave a dead graphics window on screen.
 local ok,err=xpcall(function()
  if A.closed then return end
  if E then local value=edit_value(E); if value then S[E.key]=value end end
  IME.stop(false);persist(); save_window(); clear_chrome_tooltip(); titlebar_cleanup(); A.closed=true; gfx.quit()
 end,debug.traceback)
 if not ok then
  A.closed=true
  pcall(gfx.quit)
  if R.TrackCtl_SetToolTip then pcall(R.TrackCtl_SetToolTip,'',0,0,true) end
  BLT.logError(err)
 end
end
function BLT.pick(obj,keys) local v=BLT.valueView or {};BLT.valueView=v;for k in pairs(keys) do v[k]=obj[k] end;return v end
PrimaryButton.painter={C=C,gradient=gradient,line=line,rect=rect,corners=finish_corners,disc=disc,label=label}
PrimaryButton.painter.motion=function(now) return (gfx.mouse_x-ox)/scale,(gfx.mouse_y-oy)/scale,visual_speed(now) end
PrimaryButton.wake=function() redraw_dirty=true;A.content_dirty=true;next_draw_time=0 end
BLT.attach({
 R=R,C=C,Chrome=Chrome,Chameleon=Chameleon,section=SECTION,faces=fonts,font=font,
 geometry=function() return scale,ox,oy end,active=function() local f=gfx.getchar(65536);return (f&1)==0 or (f&2)~=0 end,
 wake=function() A.content_dirty=true;redraw_dirty=true;next_draw_time=0;wake_visuals() end,
 defaults={prefix='',suffix='',empty='affix',prefix_start='0',suffix_start='0',prefix_digits='3',suffix_digits='3'},capture=function() return S end,
 valid=function(v) if v.empty~='affix' and v.empty~='clear' and v.empty~='skip' then return false end;for _,k in ipairs({'prefix','suffix'}) do if #v[k]>512 or v[k]:find('[%z\1-\31\127]') then return false end;for _,tail in ipairs({'_start','_digits'}) do local n=Core.normalize_numeric(k..tail,v[k..tail]);if not n or n~=v[k..tail] then return false end end end;return true end,apply=function(v) for k,x in pairs(v) do S[k]=x end;persist();rebuild() end,
 undoRefresh=function() refresh() end,
 busy=function() return A.parser~=nil end,commit=function() return commit_edit() end,
 cancelEdit=function() IME.stop(false);E=nil;A.field_drag=nil end,editing=function() return E~=nil end,
 modal=function() return A.duplicate_modal end,
 handle=gfx_window_handle,resizeHit=function(x,y) if y<26 and x>=gfx.w-234 then return nil end;return chrome_resize_hit(x,y) end,
 cursor=set_resize_cursor,beginResize=begin_window_resize,resize=update_window_resize,

})
if ...=='blt_test' then function BLT.testDraw(now) draw(now or R.time_precise()) end end
function BLT.drawIcon()

 local bs,bx,by=scale,ox,oy;ox,oy=ox+(W-102)*scale,oy+31*scale;scale=scale*.78
 rename_icon(0,0)

 scale,ox,oy=bs,bx,by
end

if ...=='blt_test' then return {BLT=BLT,A=A,Core=Core,S=S} end
local chrome_ok,chrome_err=titlebar_api_ready()
if not chrome_ok then Language.mb(BLT.publicError(chrome_err),"Batch Rename | エラー",0); return end
local x,y=tonumber(R.GetExtState(SECTION,"window_x")),tonumber(R.GetExtState(SECTION,"window_y"))
local w,h=tonumber(R.GetExtState(SECTION,"window_w")),tonumber(R.GetExtState(SECTION,"window_h"))
if h==900+Chrome.titleH then h=H+Chrome.titleH end
w=finite(w) and clamp(w,780,1900) or W; h=finite(h) and clamp(h,630+Chrome.titleH,1400+Chrome.titleH) or (H+Chrome.titleH)
gfx.ext_retina=1
if finite(x) and finite(y) then gfx.init(Chrome.windowTitle,w,h,0,x,y)
else gfx.init(Chrome.windowTitle,w,h,0) end
if not apply_custom_window_style(w,h) then gfx.quit(); Language.mb("カスタムタイトルバーを初期化できません。","Batch Rename | エラー",0); return end
if Chameleon.enabled then Chameleon.refresh(true) end
R.atexit(close)
guarded(refresh)
local function loop()
 BLT.tick(R.time_precise());PrimaryButton.tick(R.time_precise(),BLT.host.active(),PrimaryButton.wake)

  local k=BLT.key(gfx.getchar()); if k<0 or A.closing then close(); return end
  guarded(function()
    local now=R.time_precise()
    Chameleon.tick(now)
    local flags=gfx.getchar(65537)
    local window_active=((flags & 1)==0) or ((flags & 2)~=0)
    if last_window_active==nil or window_active~=last_window_active then last_window_active=window_active; wake_visuals(now) end

    local ime_was_active=IME.active
    IME.frame()
    local key_activity=false; local count=0
    while k>0 and count<32 do key_activity=true; if not ime_was_active and not IME.active then keypress(k) end; count=count+1; k=gfx.getchar() end
    if key_activity then wake_visuals(now) end
    if A.closing then return end

    local parser_active=A.parser~=nil
    if A.parser and Core.parse_step(A.parser) then
      local parser=A.parser; A.names=parser.rows; A.parser=nil; A.loaded=true; A.applied=false; A.invalid=false; A.input_error=false
      rebuild()
      notice(string.format("%d行を読み込みました。%s%s",#A.names,parser.columns and "先頭列だけを使用。" or "改行ごとに対応。",
        parser.flattened>0 and string.format(" セル内改行・タブを%d行で空白に変換。",parser.flattened) or ""))
      redraw_dirty=true
    end
    parser_active=A.parser~=nil
    if now>=A.poll then A.poll=now+.35; if sync_selection() then wake_visuals(now) end end
    if A.edit_dirty and now>=A.edit_dirty then A.edit_dirty=nil; rebuild(); redraw_dirty=true end
    if now>=window_poll_at then window_poll_at=now+.25; save_window() end

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

    local dragging=A.field_drag~=nil or Chrome.drag~=nil or Chrome.resize~=nil or ((raw_cap or 0)&1)~=0
    if dragging then wake_visuals(now) end
    animation_speed=parser_active and 1 or visual_speed(now)
    animations_active=window_active and animation_speed>0
    local particle_tail=#icon_particles>0
    local frame_interval
    if IME.active then frame_interval=1/30
    elseif dragging then frame_interval=1/60
    elseif parser_active then frame_interval=1/30
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
  end)
  if A.closing then close(); return end
  R.defer(loop)
end

loop()
