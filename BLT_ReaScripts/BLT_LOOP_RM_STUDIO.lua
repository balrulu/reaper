-- @description LOOP RM STUDIO
-- @version 0.5.5
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
 ["サステイン"]="Sustain",
 ["リージョン"]="Region",
 ["マーカー"]="Marker",
 ["REAPERで選択するリージョンは1つにしてください。"]="Select just one region in REAPER.",
 ["現在のグリッド設定を取得できません。"]="Cannot read current grid settings.",
 ["基準幅／間隔補正が不正です。"]="Invalid base width / gap offset.",
 ["グリッド位置を取得できません。"]="Cannot read grid position.",
 ["単位が不正です。"]="Invalid unit.",
 ["間隔により挿入位置がプロジェクト先頭より前になります。"]="Spacing would place content before project start.",
 ["基準幅は0より大きい値で指定してください。秒は mm:ss または hh:mm:ss も使えます。"]="Base width must be positive. Seconds also accept mm:ss or hh:mm:ss.",
 ["間隔補正は-864000〜864000秒で指定してください。秒は -mm:ss または -hh:mm:ss も使えます。"]="Gap offset must be -864000 to 864000 seconds. -mm:ss or -hh:mm:ss is also accepted.",
 ["個数は1〜1000の整数で指定してください。"]="Count must be an integer from 1 to 1000.",
 ["基準幅の単位が不正です。"]="Invalid base width unit.",
 ["基準幅の値が不正です。"]="Invalid base width value.",
 ["間隔補正の単位が不正です。"]="Invalid gap offset unit.",
 ["間隔補正の値が不正です。"]="Invalid gap offset value.",
 ["アイテムを選択してください。"]="Select items.",
 ["選択アイテムは1000個までにしてください。"]="Select at most 1000 items.",
 ["長さが不正なアイテムがあります。"]="Some items have invalid lengths.",
 ["追加方法が不正です。"]="Invalid insertion mode.",
 ["先にREAPERで時間選択を作ってください。"]="Create a time selection in REAPER first.",
 ["追加する範囲が不正です。"]="Invalid insertion range.",
 ["名前にNUL文字は使用できません。"]="Names cannot contain NUL.",
 ["名前が正しいUTF-8ではありません。"]="Name is not valid UTF-8.",
 ["CP932に変換できない文字があります: "]="Character cannot be encoded in CP932: ",
 [" — 名前を変更するかUTF-8を選んでください。"]=" — Rename it or choose UTF-8.",
 ["書き出し範囲を指定してください。"]="Specify an export range.",
 ["サンプルレートが不正です。"]="Invalid sample rate.",
 ["書き出し範囲がWAVの上限を超えています。"]="Export range exceeds WAV limits.",
 ["リージョン位置が不正です。"]="Invalid region position.",
 ["不明なBLT接頭辞: "]="Unknown BLT prefix: ",
 ["未対応の区間種類です。"]="Unsupported section type.",
 ["ループが書き出し範囲をまたいでいます: "]="Loop crosses the export boundary: ",
 ["サステインループは1ファイルにつき1つまでです。"]="Only one sustain loop per file.",
 ["1サンプル未満のリージョンがあります: "]="Region shorter than one sample: ",
 ["名前が長すぎます。"]="Name too long.",
 ["REAPERから出力先を取得できません。"]="Cannot read output path from REAPER.",
 ["REAPER本体の設定からWAV出力先を取得できません。出力形式をWAVにしてください。"]="Cannot read WAV output path. Set REAPER output format to WAV.",
 ["REAPER本体の設定から複数のWAV出力先が返されました。セカンダリ出力やステム出力を無効にしてください。"]="REAPER returned multiple WAV paths. Disable secondary/stem output.",
 ["一括出力名の指定が不正です。"]="Invalid batch output name.",
 ["リージョン情報が大きすぎます。"]="Region metadata too large.",
 ["WAVが途中で切れています。"]="Truncated WAV file.",
 ["通常のRIFF/WAVのみ対応しています（RF64/Wave64非対応）。"]="Standard RIFF/WAV only; RF64/Wave64 unsupported.",
 ["WAVサイズが一致しません。レンダー未完了または破損ファイルです。"]="WAV size mismatch. Render incomplete or file damaged.",
 ["WAVチャンクヘッダーが不正です。"]="Invalid WAV chunk header.",
 ["WAVチャンク長が不正です。音声データが途中で切れている可能性があります。"]="Invalid WAV chunk length. Audio data may be truncated.",
 ["WAV fmtが不正です。"]="Invalid WAV fmt chunk.",
 ["WAVEFORMATEXTENSIBLEが不正です。"]="Invalid WAVEFORMATEXTENSIBLE.",
 ["未対応のWAVサブフォーマットです。"]="Unsupported WAV subformat.",
 ["PCM / IEEE float WAVのみ対応しています。"]="PCM / IEEE float WAV only.",
 ["WAV音声フォーマットが不正です。"]="Invalid WAV audio format.",
 ["複数dataチャンクには対応していません。"]="Multiple data chunks are unsupported.",
 ["既存のWAVメタデータが大きすぎます。"]="Existing WAV metadata too large.",
 ["音声データがありません、またはサンプル境界が不正です。"]="No audio data or invalid sample alignment.",
 ["出力ファイル名を確保できません。"]="Cannot reserve output filename.",
 ["出力先は新しいWAVファイルを指定してください。"]="Choose a new WAV file as the destination.",
 ["レンダーのサンプルレートが一致しません。"]="Render sample rate mismatch.",
 ["レンダーの長さが一致しません。\n指定範囲: %.9f ～ %.9f 秒\n予定: %d samples (%.9f 秒)\n実際: %d samples (%.9f 秒)\n差: %+d samples / %+.6f ms\nサンプルレート: %d Hz"]="Render duration mismatch.\nRange: %.9f to %.9f s\nExpected: %d samples (%.9f s)\nActual: %d samples (%.9f s)\nDifference: %+d samples / %+.6f ms\nSample rate: %d Hz",
 ["メタデータが実際のWAV終端を超えています。"]="Metadata exceeds the actual WAV end.",
 ["BWF時刻が上限を超えています。"]="BWF time exceeds limit.",
 ["4 GiBを超えるWAVには対応していません。"]="WAV files over 4 GiB are unsupported.",
 ["作業ファイルが存在します: "]="Work file exists: ",
 ["書き込み検証に失敗しました。"]="Write verification failed.",
 ["出力先が別の処理で作成されました。再実行してください。"]="Another process created the output file. Run again.",
 ["REAPERのリージョン選択APIを利用できません。REAPERを更新してください。"]="Region selection API unavailable. Update REAPER.",
 ["レンダー対象リージョンの選択を変更できません。"]="Cannot change render region selection.",
 ["レンダー対象リージョンが見つかりません: "]="Render region not found: ",
 ["レンダー設定を取得できません: "]="Cannot read render setting: ",
 ["ビット深度が不正です。"]="Invalid bit depth.",
 ["チャンネル数が不正です。"]="Invalid channel count.",
 ["レンダー対象リージョンが不正です。"]="Invalid render region.",
 ["レンダー用の時間選択をサンプル精度で設定できません。時間選択のロックなどを確認してください。"]="Cannot set sample-accurate render selection. Check time-selection locking.",
 ["レンダー設定を変更できません: "]="Cannot change render setting: ",
 ["REAPER本体の出力形式を取得できません。"]="Cannot read REAPER output format.",
 ["REAPER本体の出力形式をWAVに設定してください。"]="Set REAPER output format to WAV.",
 ["対応形式はWAV 16/24 bit PCM・32 bit floatです。"]="WAV 16/24-bit PCM and 32-bit float supported.",
 ["標準サンプルレートを解決できません。REAPER本体で明示指定してください。"]="Cannot resolve default sample rate. Set it explicitly in REAPER.",
 ["REAPER本体のチャンネル数が不正です。"]="Invalid REAPER channel count.",
 ["追加する区間種類が不正です。"]="Invalid section type to add.",
 ["開始番号は1〜12桁の数字で指定してください。"]="Start number must contain 1 to 12 digits.",
 ["開始番号が大きすぎます。"]="Start number too large.",
 ["音声アイテムを1〜1000個選択してください。"]="Select 1 to 1000 audio items.",
 ["クロスフェードに必要な仮想トラック素材が足りません。"]="Not enough virtual-track audio for crossfade.",
 ["クロスフェードに必要な素材尺が足りません。"]="Source too short for crossfade.",
 ["クロスフェード置換範囲が不正です。"]="Invalid crossfade replacement range.",
 ["クロスフェード置換範囲を確定できません。"]="Cannot determine crossfade replacement range.",
 ["クロスフェード置換範囲の音声アイテムがありません。"]="No audio items in crossfade replacement range.",
 ["クロスフェード置換範囲をサンプル境界へ整列できません。"]="Cannot align crossfade range to sample boundaries.",
 ["クロスフェード時間を指定してください。"]="Specify crossfade duration.",
 ["サステイン区間が2サンプル未満のため、クロスフェードできません。"]="Sustain is shorter than two samples; cannot crossfade.",
 ["ループポイント直前にクロスフェード用の音声が2サンプル以上必要です。"]="At least two samples of audio are needed before the loop point.",
 ["ループ尺が足りません。クロスフェード時間はループ長以下、2サンプル以上にしてください。"]="Crossfade must be at least two samples and no longer than the loop.",
 ["クロスフェード置換範囲が不足しています。"]="Insufficient crossfade replacement range.",
 ["クロスフェード置換範囲の音声アイテムがロックされています。"]="Audio items in crossfade range are locked.",
 ["アイテムの復元情報を取得できません。"]="Cannot read item restore data.",
 ["固定レーンをまたぐクロスフェード重複は、通常の音声アイテムへまとめてから実行してください。"]="Merge overlapping crossfades across fixed lanes into regular audio items first.",
 ["4 GiBを超える加工素材には対応していません。"]="Processed audio over 4 GiB is unsupported.",
 ["作業ファイルが存在します。"]="Work file exists.",
 ["トラック合成音声を取得できません。"]="Cannot read mixed track audio.",
 ["仮想トラック素材の音声範囲を取得できません。"]="Cannot read virtual-track audio range.",
 ["元WAVを開けません。"]="Cannot open source WAV.",
 ["音声アクセサーを作成できません。"]="Cannot create audio accessor.",
 ["素材尺が足りません。必要な音声範囲を取得できません。"]="Source too short for the required audio range.",
 ["元WAVの読み取り範囲が不正です。"]="Invalid source WAV read range.",
 ["元WAVの音声読み取りに失敗しました。"]="Failed to read source WAV audio.",
 ["素材の音声取得に失敗しました。"]="Failed to read source audio.",
 ["処理中にプロジェクトが変更されました。やり直してください。"]="Project changed during processing. Retry.",
 ["素材に不正な音声値があります。"]="Source contains invalid audio values.",
 ["加工音声の検証に失敗しました。"]="Processed audio validation failed.",
 ["ループ音声を保存できません。"]="Cannot save loop audio.",
 ["プロジェクトが変更されました。"]="Project changed.",
 ["クロスフェード対象のアイテムが変更されました。"]="Crossfade target items changed.",
 ["アイテムが変更されました。"]="Item changed.",
 ["安全なクロスフェード置換に必要なUndo APIを利用できません。"]="Undo API required for safe crossfade replacement is unavailable.",
 ["アイテムの分割に失敗しました。"]="Item split failed.",
 ["分割端のフェードを更新できません。"]="Cannot update split-edge fades.",
 ["加工素材を読み込めません。"]="Cannot load processed audio.",
 ["加工音声用のアイテムを作成できません。"]="Cannot create item for processed audio.",
 ["加工アイテムの位置を設定できません。"]="Cannot set processed item position.",
 ["加工アイテムの長さを設定できません。"]="Cannot set processed item length.",
 ["加工アイテムの音量を設定できません。"]="Cannot set processed item volume.",
 ["加工素材のループ設定を更新できません。"]="Cannot update processed source loop setting.",
 ["加工アイテムの固定レーンを設定できません。"]="Cannot set processed item fixed lane.",
 ["加工音声用のテイクを作成できません。"]="Cannot create take for processed audio.",
 ["加工素材を適用できません。"]="Cannot apply processed audio.",
 ["加工テイクの再生設定を更新できません。"]="Cannot update processed take playback settings.",
 ["置換前の重複音声を取り除けません。"]="Cannot remove overlapping original audio.",
 ["加工区間のテイクを取得できません。"]="Cannot read take in processed section.",
 ["加工素材の開始位置を更新できません。"]="Cannot update processed source offset.",
 ["サステインのサンプル位置を更新できません。"]="Cannot update sustain sample position.",
 ["\n一部のアイテムを復元できませんでした。REAPERのUndoで処理を戻してください。"]="\nSome items could not be restored. Use REAPER Undo.",
 ["BLT LOOP RM STUDIO: クロスフェードループ"]="BLT LOOP RM STUDIO: Crossfade loop",
 ["\n処理前のアイテムを自動復元できませんでした。REAPERのUndoを実行してください。"]="\nCould not automatically restore original items. Use REAPER Undo.",
 ["クロスフェード素材がまだ適用されていません。"]="Crossfade audio has not been applied yet.",
 ["生成素材の波形ピークを構築できません。"]="Cannot build peaks for generated audio.",
 ["音声に不正な値があります。"]="Audio contains invalid values.",
 ["ゼロクロスを判定できません。対象付近が無音です。"]="Cannot detect zero crossing; nearby audio is silent.",
 ["指定方向の100 ms以内に次のゼロクロスが見つかりませんでした。"]="No next zero crossing within 100 ms in that direction.",
 ["前後20 ms以内にゼロクロスが見つかりませんでした。"]="No zero crossing within 20 ms either side.",
 ["周期解析範囲が不正です。"]="Invalid period analysis range.",
 ["100秒を超えるサステインは周期解析できません。"]="Cannot analyze periods for sustains over 100 seconds.",
 ["周期解析には少なくとも0.6秒程度の音声が必要です。"]="Period analysis needs at least about 0.6 seconds of audio.",
 ["明確なリズム周期を検出できませんでした。"]="No clear rhythmic period detected.",
 ["安定した周期を検出できませんでした。"]="No stable period detected.",
 ["周期候補を絞り込めませんでした。"]="Cannot narrow down period candidates.",
 ["周期に合わせると区間がなくなります。長めのサステインを指定してください。"]="Period alignment leaves no range. Use a longer sustain.",
 ["解析方法が不正です。"]="Invalid analysis method.",
 ["移動方向が不正です。"]="Invalid move direction.",
 ["音声アイテムを選択してください。"]="Select audio items.",
 ["選択アイテムの位置または長さが不正です。"]="Invalid selected item position or length.",
 ["選択アイテムに複数のサステインが重なっています。対象を分けて選択してください。"]="Multiple sustains overlap selected items. Select targets separately.",
 ["選択アイテムと重なるサステインがありません。"]="No sustain overlaps selected items.",
 ["同じループを構成する音声アイテムは同じトラックから選択してください。"]="Select audio for one loop from the same track.",
 ["サステイン上の選択アイテム間に隙間があります。連続するアイテムを選択してください。"]="Gaps between selected items over sustain. Select contiguous items.",
 ["サステイン開始を覆う音声アイテムも選択してください。"]="Also select audio covering sustain start.",
 ["サステイン終了を覆う音声アイテムも選択してください。"]="Also select audio covering sustain end.",
 ["境界付近にゼロクロス解析用の音声が足りません。"]="Not enough audio near boundaries for zero-crossing analysis.",
 ["プレビュー範囲が仮想トラック素材の外です。"]="Preview range is outside virtual-track audio.",
 ["周期解析範囲を選択アイテムで覆えていません。"]="Selected items do not cover period analysis range.",
 ["周期解析範囲が100秒を超えています。"]="Period analysis range exceeds 100 seconds.",
 ["調整後のサステイン区間が短すぎます。"]="Adjusted sustain is too short.",
 ["移動先を探す基準トラックを取得できません。"]="Cannot read reference track for destination search.",
 ["移動先のアイテムが多すぎます。"]="Too many items at destination.",
 ["移動先の音声範囲を延長できません。"]="Cannot extend destination audio range.",
 ["選択アイテム内に有効なループ範囲を確保できません。"]="No valid loop range within selected items.",
 ["解析中にプロジェクトが変更されました。やり直してください。"]="Project changed during analysis. Retry.",
 ["仮想トラック素材の解析範囲を取得できません。"]="Cannot read virtual-track analysis range.",
 ["音声を取得できません。"]="Cannot read audio.",
 ["解析範囲の音声を取得できません。"]="Cannot read audio in analysis range.",
 ["解析したアイテムが削除されました。"]="Analyzed item was deleted.",
 ["解析したアイテムのアクティブテイクが変更されました。"]="Analyzed item's active take changed.",
 ["解析したアイテムの位置または素材範囲が変更されました。"]="Analyzed item position or source range changed.",
 ["サステインの更新に失敗しました。"]="Failed to update sustain.",
 ["\n一部を復元できませんでした。REAPERのUndoで戻してください。"]="\nSome data could not be restored. Use REAPER Undo.",
 ["ゼロクロスへ調整"]="Align to zero crossing",
 ["周期へ調整"]="Align to period",
 ["アイテムが選択されていません"]="No items selected",
 ["操作中のループリージョンが見つかりません。"]="Active loop region not found.",
 ["選択アイテム範囲に収まるループリージョンがありません"]="No loop region fits within selected items",
 ["選択アイテム範囲にループリージョンが複数存在しています！"]="Multiple loop regions within selected items!",
 ["対象のサステインリージョンが不正です。"]="Invalid target sustain region.",
 ["波形を見る音声アイテムを選択してください。"]="Select audio items to view the waveform.",
 ["対象リージョンと重なる音声アイテムは同じトラックから選択してください。"]="Select audio overlapping the target region from one track.",
 ["選択したサステインと重なる音声アイテムを選択してください。"]="Select audio overlapping the selected sustain.",
 ["選択アイテムが離れた複数の素材群に分かれています。対象を分けて選択してください。"]="Selected items form separate groups. Select targets separately.",
 ["選択アイテムを対象トラック上で確認できませんでした。"]="Cannot find selected items on target track.",
 ["サステイン全体を覆う、隙間のない連続音声アイテムを同じトラックに配置してください。"]="Place contiguous audio covering the full sustain on one track.",
 ["仮想素材として扱える連続アイテムは1000個までです。"]="Virtual source supports at most 1000 contiguous items.",
 ["仮想トラック素材に音声アイテムがありません。"]="No audio items in virtual track source.",
 ["MIDIではなく音声アイテムを選択してください。"]="Select audio items, not MIDI.",
 ["仮想素材として扱う音声アイテムは同じトラックから選択してください。"]="Select virtual source audio from one track.",
 ["音声アイテムの位置または長さが不正です。"]="Invalid audio item position or length.",
 ["仮想トラック素材のサンプルレートを取得できません。"]="Cannot read virtual-track sample rate.",
 ["仮想トラック素材のチャンネル数を取得できません。"]="Cannot read virtual-track channel count.",
 ["仮想トラック素材から音声範囲を取得できません。"]="Cannot read audio range from virtual track.",
 ["移動する境界が不正です。"]="Invalid boundary to move.",
 ["ドラッグ移動量が不正です。"]="Invalid drag distance.",
 ["ループ調整に使う音声アイテムは同じトラックから選択してください。"]="Select loop adjustment audio from one track.",
 ["ループ調整に使う音声アイテム間に隙間があります。"]="Gaps between audio items used for loop adjustment.",
 ["開始側と終了側の音声アイテムを両方選択してください。"]="Select audio items at both start and end.",
 ["波形ドラッグ量が不正です。"]="Invalid waveform drag distance.",
 ["波形表示位置が不正です。"]="Invalid waveform display position.",
 ["サステイン範囲が不正です。"]="Invalid sustain range.",
 ["波形表示幅が不正です。"]="Invalid waveform display width.",
 ["調整したサステイン範囲がありません。"]="No adjusted sustain range.",
 ["調整後のサステイン範囲が不正です。"]="Invalid adjusted sustain range.",
 ["自動再生範囲を取得できません。"]="Cannot read auto-playback range.",
 ["時間選択から区間を追加し、WAVへ書き出します。"]="Add sections from the time selection and export WAV.",
 ["CHAMELEON  REAPERテーマに擬態"]="CHAMELEON  REAPER theme",
 ["CHAMELEON  オリジナル配色"]="CHAMELEON  Original colors",
 ["カスタムタイトルバーには js_ReaScriptAPI が必要です。\nReaPack から js_ReaScriptAPI をインストールしてください。"]="The app bar requires js_ReaScriptAPI.\nInstall js_ReaScriptAPI via ReaPack.",
 ["ReaImGui 0.10以降が必要です。ReaPackで導入・更新してください。"]="ReaImGui 0.10+ is required. Install/update via ReaPack.",
 ["日本語入力欄を初期化できません。\n"]="Cannot initialize the text input.\n",
 ["あいうえお漢字ABC012345"]="あいうえお漢字ABC012345",
 ["\n\nレンダー音声は保持しています:\n"]="\n\nRendered audio retained:\n",
 ["配置元が不正です。"]="Invalid placement source.",
 ["保存先フォルダーを開き、「保存」で選択"]="Open the destination folder and choose Save",
 ["このフォルダーを選択.folder"]="Select this folder.folder",
 ["フォルダー選択用 (*.folder)\0*.folder\0"]="Folder selector (*.folder)\0*.folder\0",
 ["保存先のディレクトリパスを取得できません。"]="Cannot read destination directory path.",
 ["プロジェクトが変わりました。"]="Project changed.",
 ["処理中は元に戻せません。処理を完了または中止してください。"]="Cannot undo during processing. Finish or stop first.",
 ["元に戻せる操作がありません。"]="Nothing to undo.",
 ["REAPERのUndo APIを利用できません。"]="REAPER Undo API unavailable.",
 ["元に戻しました。"]="Undone.",
 ["プロジェクトが変わりました。追加をやり直してください。"]="Project changed. Add again.",
 ["を追加"]=": add",
 ["追加できませんでした。"]="Could not add.",
 ["録音中は繋ぎ目を自動再生できません。"]="Cannot auto-play seam while recording.",
 ["プロジェクトの再生速度を取得できません。"]="Cannot read project playback rate.",
 ["繋ぎ目の自動再生を開始できませんでした。"]="Cannot start seam auto-playback.",
 ["録音中は調整できません。録音を停止してください。"]="Stop recording before adjusting.",
 ["再生を停止できませんでした。"]="Cannot stop playback.",
 ["プロジェクトの再生速度を1.0にしてください。"]="Set project playback rate to 1.0.",
 ["クロスフェード用のループ素材を作成中…"]="Creating loop audio for crossfade...",
 ["生成したループ素材の波形を準備中…"]="Preparing generated loop waveform...",
 ["サステイン区間をクロスフェード処理しました。時間選択を追従しました。Undoで戻せます。"]="Sustain crossfade applied. Time selection followed. Undo available.",
 ["開始・終了付近のゼロクロスを解析中…"]="Analyzing zero crossings near start/end...",
 ["サステイン周辺の周期を解析中…"]="Analyzing periods around sustain...",
 ["周期を検出できませんでした・・・！"]="No period detected!",
 ["周期解析を終了しました。リージョンは変更していません。"]="Period analysis finished. Regions unchanged.",
 ["（周期 %.3f 秒 / 一致度 %.0f%%）"]=" (period %.3f s / match %.0f%%)",
 [" 移動先の音声アイテムを選択へ追加: "]=" Added destination audio items to selection: ",
 ["件。"]=" items.",
 ["ゼロクロスへ移動しました。"]="Moved to zero crossing.",
 ["周期に合わせて移動しました。"]="Moved to match period.",
 ["時間選択を追従しました。Undoで戻せます。"]="Time selection followed. Undo available.",
 ["選択アイテム内でこれ以上移動できません"]="Cannot move further within selected items",
 ["出力フォルダーが不正です。"]="Invalid output folder.",
 ["出力フォルダーは絶対パスで指定してください。"]="Use an absolute output folder path.",
 ["ファイル名に使用できない文字があります。"]="Filename contains invalid characters.",
 ["予約されたファイル名です。"]="Reserved filename.",
 ["REAPER本体の保存フォルダーを解決できません。"]="Cannot resolve REAPER save folder.",
 ["出力先のフォルダーを解決できません。"]="Cannot resolve output folder.",
 ["リージョン情報を埋め込んでいます…"]="Embedding region metadata...",
 ["書き出し中にプロジェクトが切り替わりました。"]="Project switched during export.",
 ["一時ファイル名が衝突しました。"]="Temporary filename collision.",
 ["出力先に同名ファイルが作成されました。再実行してください。"]="Output file already created. Run again.",
 ["REAPERでミックスダウン中… %d / %d"]="Mixing down in REAPER... %d / %d",
 ["REAPERでミックスダウン中…"]="Mixing down in REAPER...",
 ["REAPERが予期しないWAV出力先を返しました: "]="REAPER returned an unexpected WAV path: ",
 ["レンダーがキャンセルされたか、WAVが作成されませんでした。"]="Render cancelled or WAV not created.",
 ["レンダー音声を一時保存名へ変更できませんでした。"]="Cannot rename rendered audio to temporary filename.",
 ["レンダーされたWAVのチャンネル数／ビット深度が設定と一致しません。"]="Rendered WAV channel count / bit depth does not match settings.",
 ["リージョンを選択されていません"]="No regions selected",
 ["選択したリージョンからレンダー範囲を取得できませんでした"]="Cannot read render range from selected regions",
 ["再生・録音を停止してから書き出してください。"]="Stop playback/recording before exporting.",
 ["4 GiBを超える出力には対応していません。"]="Output over 4 GiB is unsupported.",
 ["解析を中止しました。リージョンは変更していません。"]="Analysis stopped. Regions unchanged.",
 ["クロスフェード処理を中止しました。"]="Crossfade processing stopped.",
 ["一括書き出しを中止しました。完了済み: "]="Batch export stopped. Completed: ",
 ["件。現在のレンダー音声は保持されています。"]=" items. Current rendered audio retained.",
 ["埋め込みを中止しました。元の音声は保持されています。"]="Embedding stopped. Original audio retained.",
 ["完了。一時WAVが残っています: "]="Done. Temporary WAV remains: ",
 ["書き出し完了: "]="Export complete: ",
 ["件"]=" items",
 ["選択範囲"]="Time range",
 ["選択アイテム（個別）"]="Each item",
 ["選択アイテム全体"]="All items",
 ["カーソル位置"]="Cursor",
 ["秒"]="sec",
 ["拍"]="beats",
 ["小節"]="bars",
 ["グリッド"]="grid",
 ["原則UTF-8を推奨\nSoundForgeで日本語を文字化けさせたくない場合のみCP932を選択してください。\nただし他の大多数アプリケーションで文字化けします。※英語圏には無関係な機能です"]="UTF-8 recommended.\nUse CP932 only for Japanese names in SoundForge.\nMost other applications will misread CP932; irrelevant for English-only names.",
 ["相対保持"]="Link ends",
 ["ONでは開始と終了を同じ量だけ移動し、ループ尺を保持"]="ON: move start and end equally to keep loop length",
 ["入力できない制御文字、または長すぎる文字列です。"]="Invalid control character or text too long.",
 ["保存フォルダーを入力してください。"]="Enter a save folder.",
 ["数値を入力できなかったため、元の値へ戻しました。"]="Invalid input. Previous value restored.",
 ["クリック入力 / 上下ドラッグ / ホイール"]="Click to type / Drag vertically / Wheel",
 ["クリックして直接入力"]="Click to type",
 [" / REAPERワイルドカード使用可"]=" / REAPER wildcards supported",
 [" / Shiftで微調整"]=" / Shift: fine adjust",
 ["名前と番号を設定"]="NAME & NUMBER",
 ["名前"]="Name",
 ["番号を付与"]="Add numbers",
 ["OFFではすべて同じ名前で追加"]="OFF: add all with the same name",
 ["開始番号"]="Start number",
 ["キャンセル"]="Cancel",
 ["追加を取り消す"]="Cancel insertion",
 ["追加"]="Add",
 ["指定した名前で追加"]="Add with this name",
 ["ドラッグ中にプロジェクトが変わりました。やり直してください。"]="Project switched during drag. Retry.",
 ["ドラッグ中にプロジェクトが変更されました。やり直してください。"]="Project changed during drag. Retry.",
 ["波形ドラッグでループ範囲を移動"]="Move loop range by dragging waveform",
 ["終了位置"]="End",
 ["開始位置"]="Start",
 ["を波形ドラッグで移動しました。"]=" moved by waveform drag.",
 [" 時間選択を追従しました。Undoで戻せます。"]=" Time selection followed. Undo available.",
 ["選択アイテム範囲に収まる\nループリージョンがありません"]="No loop region fits\nwithin selected items",
 ["選択アイテム範囲に\nループリージョンが\n複数存在しています！"]="Multiple loop regions\nwithin selected\nitems!",
 ["継ぎ目を読み取り中…"]="Reading seam...",
 ["終了 −6 ms  /  DRAG"]="End -6 ms / DRAG",
 ["開始 ＋6 ms  /  DRAG"]="Start +6 ms / DRAG",
 [" / クリックで更新"]=" / Click to refresh",
 ["更新中…"]="Updating...",
 ["終了 "]="End ",
 ["開始 "]="Start ",
 ["  /  相対保持"]=" / Linked ends",
 ["波形を右へドラッグ＝時間位置を前へ / 左へドラッグ＝後ろへ / クリックで更新"]="Drag right: move earlier / Drag left: move later / Click: refresh",
 ["LOOP / REGION / MARKER MANAGER  ループ・リージョン・マーカー管理ツール"]="LOOP / REGION / MARKER MANAGER  Manage loops, regions and markers",
 ["ループ・リージョン・マーカーを追加"]="ADD LOOP / REGION / MARKER",
 ["ループ（サステイン）"]="Loop (sustain)",
 ["を配置元にする"]=": placement source",
 ["個数"]="Qty",
 ["基準幅"]="Width",
 ["リージョンの長さ／マーカーの配置基準幅"]="Region length / marker placement base width",
 ["間隔補正"]="Gap",
 ["次の配置位置＝現在位置＋基準幅＋間隔補正。-基準幅で同位置、さらに小さい負値で左方向"]="Next position = current + base width + gap. Negative base width repeats position; smaller values move left.",
 ["名前入力を省略"]="Skip name input",
 ["ONでは追加時の名前入力を省略します"]="ON: add without asking for a name",
 ["ループ調整"]="LOOP ADJUSTMENT",
 ["クロスフェードを適用"]="Apply crossfade",
 ["レベル突出を抑える滑らかなカーブで指定時間分だけ加工。時間は2サンプル〜ループ長に自動補正"]="Smooth curve limits level buildup. Duration is clamped to 2 samples through loop length.",
 ["時間"]="Time",
 ["開始・終了の両方を近い位置へ調整"]="Adjust both start and end to nearby positions",
 ["終了"]="End",
 ["開始"]="In",
 ["と反対端を同じ量だけ移動（ループ尺を保持）"]=" and opposite end move equally (keep loop length)",
 ["だけを"]=" only to ",
 ["前"]="previous",
 ["次"]="next",
 ["の"]=" ",
 ["ゼロクロス"]="zero crossing",
 ["周期"]="period",
 ["へ移動"]=": move",
 ["最寄りゼロクロスへ補正"]="Snap to nearest zero crossing",
 ["周期を検出し補正"]="Detect and align to period",
 ["調整後、繋ぎ目を自動再生"]="Auto-play seam after adjustment",
 ["通常はループ末端の0.75秒前から再生。クロスフェード時はその開始点（最低0.75秒前）から再生し、1回ループした約1秒後に停止"]="Usually play from 0.75 s before loop end. With crossfade, start at its beginning (at least 0.75 s early); stop about 1 s after one loop.",
 ["レンダリング設定"]="RENDER SETTINGS",
 ["対象"]="Source",
 ["マスターミックス"]="Master mix",
 ["マスターミックス\n現状マスターミックスのみ対応としています。"]="Master mix\nOnly master mix is currently supported.",
 ["選択リージョン"]="Selected regions",
 ["選択リージョン\n現状選択リージョンの書き出しのみ対応しています。\nREAPER本体や、BLT MARKER REGION DESK等でリージョンを選択してください。"]="Selected regions\nOnly selected region export is supported.\nSelect regions in REAPER or BLT MARKER REGION DESK.",
 ["Master mix  /  REAPERで選択した各リージョンを個別のWAVとしてレンダリングします"]="Master mix / Render each selected REAPER region to a separate WAV",
 ["フォーマット"]="FORMAT",
 ["REAPER本体の設定を使用"]="Use REAPER settings",
 ["WAVのビット深度・サンプルレート・チャンネル数をREAPER本体から参照"]="Read WAV bit depth, sample rate and channels from REAPER",
 ["形式"]="Format",
 ["ビット深度"]="Bit depth",
 ["サンプルレート"]="Sample rate",
 ["チャンネル"]="Channels",
 ["WAV\n現状WAVのみ対応としています。\nOGG等への対応はしていません。"]="WAV\nOnly WAV is supported.\nOGG and other formats are unsupported.",
 ["WAVのビット深度"]="WAV bit depth",
 ["出力サンプルレート"]="Output sample rate",
 ["出力チャンネル数"]="Output channel count",
 ["出力先"]="OUTPUT",
 ["（プロジェクトの標準保存先）"]="(Project default folder)",
 ["（REAPERの既定名）"]="(REAPER default name)",
 ["保存フォルダー"]="Folder",
 ["REAPER設定を使用"]="Use REAPER",
 ["保存フォルダーのみREAPER本体の設定を使用"]="Use REAPER settings for save folder only",
 ["参照"]="Browse",
 ["保存フォルダーを選択"]="Choose save folder",
 ["ファイル名"]="Filename",
 ["ファイル名のみREAPER本体の設定を使用。ワイルドカードもREAPERで解決"]="Use REAPER filename settings; REAPER also resolves wildcards",
 ["埋め込むマーカー/リージョンを設定"]="EMBED MARKERS / REGIONS",
 ["レンダー範囲内のマーカーをWAVへ埋め込み"]="Embed markers within the render range into WAV",
 ["レンダー範囲内の通常リージョンをWAVへ埋め込み"]="Embed regular regions within the render range into WAV",
 ["ループリージョン"]="Loop regions",
 ["レンダー範囲内のサステインをWAVのループ情報として埋め込み"]="Embed sustains within the render range as WAV loop data",
 ["選択中のリージョンを除外"]="Exclude selected regions",
 ["書き出し範囲として選択しているリージョンは埋め込まないようにします。\nただし、ループリージョン自体を選択して書き出した場合に、ループリージョンは除外しません。"]="Do not embed regions selected as export ranges.\nSelected loop regions are still embedded when exported themselves.",
 ["マーカー文字コード設定"]="MARKER ENCODING",
 ["出力 "]="Output ",
 ["件 / 埋め込み "]=" / Embedded ",
 ["件 / 除外 "]=" / Excluded ",
 ["件 / 範囲外 "]=" / Outside ",
 ["件 / 切詰め "]=" / Trimmed ",
 ["処理中"]="Processing",
 ["レンダリング実行"]="Render",
 ["Master mixをレンダーして区間情報を埋め込む"]="Render master mix and embed section metadata",
 ["中止"]="Stop",
 ["埋め込みを中止。元のWAVは保持"]="Stop embedding; keep original WAV",
 ["BLT LOOP RM STUDIO | 必要な拡張"]="BLT LOOP RM STUDIO | Required extension",
 ["カスタムアプリバーを初期化できません。"]="Cannot initialize the app bar.",
 ["表示言語を切替（JP / EN）"]="Switch language (JP / EN)",
 ["プリセットを読み込みました: ファクトリーデフォルト"]="Loaded: Factory Default",
 ["選択中のトラック / バスを指定"]="Use selected track / bus",
},patterns={
 {"^「(.*)」を上書きしますか？$","Overwrite \"%s\"?"},
 {"^([%+%-]?[%d%.eE]+)–([%+%-]?[%d%.eE]+) / ([%+%-]?[%d%.eE]+)   スクロールで選択$","%d–%d / %d   Scroll to browse"},
 {"^解析中%.%.%.([%+%-]?[%d%.eE]+)%%$","Analyzing...%d%%"},
 {"^レンダーの長さが一致しません。\n指定範囲: ([%+%-]?[%d%.eE]+) ～ ([%+%-]?[%d%.eE]+) 秒\n予定: ([%+%-]?[%d%.eE]+) samples %(([%+%-]?[%d%.eE]+) 秒%)\n実際: ([%+%-]?[%d%.eE]+) samples %(([%+%-]?[%d%.eE]+) 秒%)\n差: ([%+%-]?[%d%.eE]+) samples / ([%+%-]?[%d%.eE]+) ms\nサンプルレート: ([%+%-]?[%d%.eE]+) Hz$","Render duration mismatch.\nRange: %.9f to %.9f s\nExpected: %d samples (%.9f s)\nActual: %d samples (%.9f s)\nDifference: %+d samples / %+.6f ms\nSample rate: %d Hz"},
 {"^（周期 ([%+%-]?[%d%.eE]+) 秒 / 一致度 ([%+%-]?[%d%.eE]+)%%）$"," (period %.3f s / match %.0f%%)"},
 {"^REAPERでミックスダウン中… ([%+%-]?[%d%.eE]+) / ([%+%-]?[%d%.eE]+)$","Mixing down in REAPER... %d / %d"},
 {"^「(.-)」を上書きしますか？$","\"%s\"?"},
 {"^(.-)」を上書きしますか？$","%s\"?"},
 {"^プリセットを保存しました: (.-)$","Saved: %s"},
 {"^プリセットを読み込みました: (.-)$","Loaded: %s"},
 {"^(.-)個インポートしました。$","%s preset(s) imported."},
 {"^現在: (.-)(.-)$","Current: %s%s"},
 {"^CP932に変換できない文字があります: (.-) — 名前を変更するかUTF%-8を選んでください。$","Character cannot be encoded in CP932: %s — Rename it or choose UTF-8."},
 {"^(.-) — 名前を変更するかUTF%-8を選んでください。$","%s — Rename it or choose UTF-8."},
 {"^不明なBLT接頭辞: (.-)$","Unknown BLT prefix: %s"},
 {"^ループが書き出し範囲をまたいでいます: (.-)$","Loop crosses the export boundary: %s"},
 {"^1サンプル未満のリージョンがあります: (.-)$","Region shorter than one sample: %s"},
 {"^作業ファイルが存在します: (.-)$","Work file exists: %s"},
 {"^レンダー対象リージョンが見つかりません: (.-)$","Render region not found: %s"},
 {"^レンダー設定を取得できません: (.-)$","Cannot read render setting: %s"},
 {"^レンダー設定を変更できません: (.-)$","Cannot change render setting: %s"},
 {"^(.-)\n一部のアイテムを復元できませんでした。REAPERのUndoで処理を戻してください。$","%s\nSome items could not be restored. Use REAPER Undo."},
 {"^(.-)\n処理前のアイテムを自動復元できませんでした。REAPERのUndoを実行してください。$","%s\nCould not automatically restore original items. Use REAPER Undo."},
 {"^(.-)周期解析には少なくとも0%.6秒程度の音声が必要です。$","%sPeriod analysis needs at least about 0.6 seconds of audio."},
 {"^(.-)明確なリズム周期を検出できませんでした。$","%sNo clear rhythmic period detected."},
 {"^(.-)安定した周期を検出できませんでした。$","%sNo stable period detected."},
 {"^(.-)周期候補を絞り込めませんでした。$","%sCannot narrow down period candidates."},
 {"^(.-)周期に合わせると区間がなくなります。長めのサステインを指定してください。$","%sPeriod alignment leaves no range. Use a longer sustain."},
 {"^(.-)\n一部を復元できませんでした。REAPERのUndoで戻してください。$","%s\nSome data could not be restored. Use REAPER Undo."},
 {"^日本語入力欄を初期化できません。\n(.-)$","Cannot initialize the text input.\n%s"},
 {"^\n\nレンダー音声は保持しています:\n(.-)$","\n\nRendered audio retained:\n%s"},
 {"^元に戻しました。(.-)$","Undone.%s"},
 {"^(.-)を追加$","%s: add"},
 {"^ 移動先の音声アイテムを選択へ追加: (.-)件。$"," Added destination audio items to selection: %s items."},
 {"^(.-)件。$","%s items."},
 {"^(.-)(.-)(.-)時間選択を追従しました。Undoで戻せます。$","%s%s%sTime selection followed. Undo available."},
 {"^(.-)(.-)時間選択を追従しました。Undoで戻せます。$","%s%sTime selection followed. Undo available."},
 {"^(.-)時間選択を追従しました。Undoで戻せます。$","%sTime selection followed. Undo available."},
 {"^REAPERが予期しないWAV出力先を返しました: (.-)$","REAPER returned an unexpected WAV path: %s"},
 {"^一括書き出しを中止しました。完了済み: (.-)件。現在のレンダー音声は保持されています。$","Batch export stopped. Completed: %s items. Current rendered audio retained."},
 {"^(.-)件。現在のレンダー音声は保持されています。$","%s items. Current rendered audio retained."},
 {"^完了。一時WAVが残っています: (.-)$","Done. Temporary WAV remains: %s"},
 {"^書き出し完了: (.-)件$","Export complete: %s items"},
 {"^(.-)件$","%s items"},
 {"^書き出し完了: (.-)$","Export complete: %s"},
 {"^(.-) / REAPERワイルドカード使用可$","%s / REAPER wildcards supported"},
 {"^(.-) / Shiftで微調整$","%s / Shift: fine adjust"},
 {"^(.-)を波形ドラッグで移動しました。(.-) 時間選択を追従しました。Undoで戻せます。$","%s moved by waveform drag.%s Time selection followed. Undo available."},
 {"^を波形ドラッグで移動しました。(.-) 時間選択を追従しました。Undoで戻せます。$"," moved by waveform drag.%s Time selection followed. Undo available."},
 {"^(.-) 時間選択を追従しました。Undoで戻せます。$","%s Time selection followed. Undo available."},
 {"^(.-) / クリックで更新$","%s / Click to refresh"},
 {"^(.-)を配置元にする$","%s: placement source"},
 {"^(.-)と反対端を同じ量だけ移動（ループ尺を保持）$","%s and opposite end move equally (keep loop length)"},
 {"^(.-)だけを(.-)の(.-)へ移動$","%s only to %s %s: move"},
 {"^だけを(.-)の(.-)へ移動$"," only to %s %s: move"},
 {"^(.-)の(.-)へ移動$","%s %s: move"},
 {"^の(.-)へ移動$"," %s: move"},
 {"^(.-)へ移動$","%s: move"},
 {"^出力 (.-)$","Output %s"},
 {"^(.-)件 / 埋め込み (.-)件 / 除外 (.-)件 / 範囲外 (.-)件 / 切詰め (.-)件$","%s / Embedded %s / Excluded %s / Outside %s / Trimmed %s items"},
 {"^件 / 埋め込み (.-)件 / 除外 (.-)件 / 範囲外 (.-)件 / 切詰め (.-)件$"," / Embedded %s / Excluded %s / Outside %s / Trimmed %s items"},
 {"^(.-)件 / 除外 (.-)件 / 範囲外 (.-)件 / 切詰め (.-)件$","%s / Excluded %s / Outside %s / Trimmed %s items"},
 {"^件 / 除外 (.-)件 / 範囲外 (.-)件 / 切詰め (.-)件$"," / Excluded %s / Outside %s / Trimmed %s items"},
 {"^(.-)件 / 範囲外 (.-)件 / 切詰め (.-)件$","%s / Outside %s / Trimmed %s items"},
 {"^件 / 範囲外 (.-)件 / 切詰め (.-)件$"," / Outside %s / Trimmed %s items"},
 {"^(.-)件 / 切詰め (.-)件$","%s / Trimmed %s items"},
 {"^件 / 切詰め (.-)件$"," / Trimmed %s items"},
 {"^処理中(.-)$","Processing%s"},
 {"^「(.*)」を上書きしますか？$","Overwrite \"%s\"?"},
 {"^(%d+)個インポートしました。$","Imported %s preset(s)."},
 {"^(%d+)件をノーマライズしました。選択を解除しました。$","Normalized %s items and deselected them."},
},prefixes={"REAPERが予期しないWAV出力先を返しました: ","CP932に変換できない文字があります: ","レンダー対象リージョンが見つかりません: ","ループが書き出し範囲をまたいでいます: ","1サンプル未満のリージョンがあります: ","一括書き出しを中止しました。完了済み: "," 移動先の音声アイテムを選択へ追加: ","\n\nレンダー音声は保持しています:\n","日本語入力欄を初期化できません。\n","完了。一時WAVが残っています: ","レンダー設定を取得できません: ","レンダー設定を変更できません: ","プリセットを読み込みました: ","プリセットを保存しました: ","作業ファイルが存在します: ","不明なBLT接頭辞: ","書き出し完了: ","現在: "}}

LanguageCatalog.en["選択アイテム"]="Selected items"
LanguageCatalog.en["個別"]="Each"
LanguageCatalog.en["グループ"]="Groups"
LanguageCatalog.en["全体"]="All"
LanguageCatalog.en["選択アイテム（グループ）"]="Selected item groups"
LanguageCatalog.en["選択アイテムから配置範囲を作成"]="Build ranges from selected items"

local Language=create_language(reaper,"BLT_REGION_FORGE",LanguageCatalog)
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

local min,max,abs,floor=math.min,math.max,math.abs,math.floor
local function clamp(x,a,b) return max(a,min(b,x)) end
local function finite(x) return type(x)=='number' and x==x and abs(x)<math.huge end
local function optional_number(fn,...)
 if type(fn)~='function' then return nil end
 local ok,value=pcall(fn,...)
 return ok and finite(value) and value or nil
end
local Core={VERSION='0.5.5',SECTION='BLT_REGION_FORGE',MAX_METADATA=16*1024*1024,SEAM_SECONDS=.006,SEAM_DRAG_SECONDS=.250,
 PERIOD_ANALYSIS_MIN=7,PERIOD_ANALYSIS_MAX=100,CROSSFADE_GUARD_FRAMES=1024}
Core.PERIOD_FAILURE='[BLT:PERIOD_FAILURE]'
-- REAPER's stock rate list (also verified in the installed executable).
Core.sample_rates={8000,11025,16000,22050,32000,44100,48000,88200,96000,176400,192000}
Core.channel_options={1,2,4,6,8}
Core.length_specs={
 seconds={.001,864000,false,1,3,1},
 beats={.001,100000,false,1,3,1},bars={1,10000,true,1,0,1},grid={1,100000,true,1,0,1}
}
Core.interval_specs={}
for unit,spec in pairs(Core.length_specs) do Core.interval_specs[unit]={-spec[2],spec[2],spec[3],spec[4],spec[5],0} end
function Core.normalize_spec_number(value,spec)
 local n=clamp(value,spec[1],spec[2])
 if spec[3] then return floor(n+.5) end
 local digits=spec[8] or spec[5] or 2;local factor=10^digits
 return (n<0 and math.ceil(n*factor-.5) or floor(n*factor+.5))/factor
end
function Core.interactive_floor(key,unit,fine)
 if key=='length' and (unit=='seconds' or unit=='beats') then return fine and .1 or 1 end
 if key=='xfade_seconds' then return fine and .1 or 1 end
 return nil
end
function Core.field_allows_fine(key,spec)
 return key=='xfade_seconds' or not spec[3] and (spec[4] or 1)<1
end
Core.tags={sustain='[BLT:SUSTAIN]',region='[BLT:REGION]'}
Core.names={sustain='サステイン',region='リージョン',marker='マーカー'}
function Core.classify(isr,name)
 name=name or ''
 if not isr then return 'marker',name end
 for _,kind in ipairs({'sustain','region'}) do
  local tag=Core.tags[kind]
  if name:sub(1,#tag):upper()==tag then return kind,(name:sub(#tag+1):gsub('^%s+','')) end
 end
 if name:upper():match('^%[BLT:') then return 'invalid',name end
 return 'region',name
end
function Core.project_rows(project)
 local rows={};local i=0
 while true do
  local ok,isr,pos,ending,name,id,col=R.EnumProjectMarkers3(project,i)
  if ok==0 then break end
  local kind,clean=Core.classify(isr,name)
  rows[#rows+1]={id=id,isr=isr,start=pos,finish=isr and ending or pos,name=clean,raw=name,kind=kind,color=col,key=(isr and 'r' or 'm')..id}
  i=i+1
 end
 return rows
end
function Core.selected_project_regions(project,rows)
 local selected={}
 if type(R.GetNumRegionsOrMarkers)=='function' and type(R.GetRegionOrMarker)=='function' and type(R.GetRegionOrMarkerInfo_Value)=='function' then
  for i=0,R.GetNumRegionsOrMarkers(project)-1 do
   local ptr=R.GetRegionOrMarker(project,i,'')
   if ptr and R.GetRegionOrMarkerInfo_Value(project,ptr,'B_ISREGION')~=0
    and R.GetRegionOrMarkerInfo_Value(project,ptr,'B_UISEL')~=0 then
    local id=R.GetRegionOrMarkerInfo_Value(project,ptr,'I_NUMBER')
    if finite(id) then selected[#selected+1]='r'..floor(id+.5) end
   end
  end
 else
  -- Compatibility fallback: an exact REAPER time selection identifies a
  -- region only when the native region-selection API is unavailable.
  local s,e=R.GetSet_LoopTimeRange2(project,false,false,0,0,false)
  if e>s then for _,row in ipairs(rows or {}) do
   if row.isr and abs(row.start-s)<=1e-8 and abs(row.finish-e)<=1e-8 then selected[#selected+1]=row.key end
  end end
 end
 local order={};for i,row in ipairs(rows or {}) do order[row.key]=i end
 table.sort(selected,function(a,b) return (order[a] or math.huge)<(order[b] or math.huge) end)
 return selected,table.concat(selected,':')
end
function Core.selected_project_region(project,rows)
 local selected,signature=Core.selected_project_regions(project,rows)
 if #selected==1 then return selected[1],nil,signature end
 if #selected>1 then return nil,'REAPERで選択するリージョンは1つにしてください。',signature end
 return nil,nil,signature
end
function Core.grid_qn(project)
 local _,division=R.GetSetProjectGrid(project,false)
 assert(finite(division) and division>0,'現在のグリッド設定を取得できません。')
 -- GetSetProjectGrid uses whole-note units; TimeMap2_* uses quarter notes.
 return division*4
end
function Core.advance(project,origin,amount,unit,grid_qn)
 assert(finite(origin) and finite(amount),'基準幅／間隔補正が不正です。')
 if unit=='seconds' then return origin+amount end
 if unit=='grid' then
  local qn=R.TimeMap2_timeToQN(project,origin)
  assert(finite(qn),'グリッド位置を取得できません。')
  return R.TimeMap2_QNToTime(project,qn+amount*(grid_qn or Core.grid_qn(project)))
 end
 if amount==0 then return origin end
 local beat,measure,numerator,fullbeats=R.TimeMap2_timeToBeats(project,origin)
 if unit=='beats' then return R.TimeMap2_beatsToTime(project,fullbeats+amount) end
 assert(unit=='bars','単位が不正です。')
 -- Maintain fractional position within a measure across time signatures.
 local position=measure+beat/numerator+amount
 local target=floor(position+1e-10);local fraction=max(0,position-target)
 assert(target>=0,'間隔により挿入位置がプロジェクト先頭より前になります。')
 local _,qn_start,qn_end=R.TimeMap_GetMeasureInfo(project,target)
 return R.TimeMap2_QNToTime(project,qn_start+(qn_end-qn_start)*fraction)
end
local function time_number(text,unit)
 local v=tonumber(text)
 if v or unit~='seconds' then return v end
 local raw=tostring(text or ''):match('^%s*(.-)%s*$');local sign=1
 if raw:sub(1,1)=='-' then sign=-1;raw=raw:sub(2)
 elseif raw:sub(1,1)=='+' then raw=raw:sub(2) end
 if raw:match('^%s*:') or raw:match(':%s*$') or raw:match(':%s*:') then return nil end
 local parts={};for part in raw:gmatch('[^:]+') do parts[#parts+1]=tonumber(part) or -1 end
 if #parts~=2 and #parts~=3 then return nil end
 v=0
 for i,n in ipairs(parts) do
  if n<0 or (i>1 and n>=60) or (i<#parts and n%1~=0) then return nil end
  v=v*60+n
 end
 return sign*v
end
function Core.duration(text,unit)
 local v=time_number(text,unit)
 assert(finite(v) and v>0 and v<=864000,'基準幅は0より大きい値で指定してください。秒は mm:ss または hh:mm:ss も使えます。')
 return v
end
function Core.interval_duration(text,unit)
 local v=time_number(text,unit)
 assert(finite(v) and abs(v)<=864000,'間隔補正は-864000〜864000秒で指定してください。秒は -mm:ss または -hh:mm:ss も使えます。')
 return v
end
-- Shared overlap grouping: positive overlap, transitive across all tracks.
function Core.overlap_groups(ranges)
 local sorted={};for i,r in ipairs(ranges) do sorted[i]=r end
 table.sort(sorted,function(a,b) return a.start==b.start and a.finish<b.finish or a.start<b.start end)
 local groups={}
 for _,r in ipairs(sorted) do
  local g=groups[#groups]
  if not g or r.start>=g.finish then g={start=r.start,finish=r.finish,members={}};groups[#groups+1]=g end
  g.finish=math.max(g.finish,r.finish);g.members[#g.members+1]=r
 end
 return groups
end

function Core.add_ranges(project,mode,kind,length,unit,count,interval,interval_unit)
 local ranges={}
 if mode=='cursor' then
  assert(finite(count) and count>=1 and count<=1000 and count%1==0,'個数は1〜1000の整数で指定してください。')
  local spec=Core.length_specs[unit];assert(spec,'基準幅の単位が不正です。')
  assert(finite(length) and length>=spec[1] and length<=spec[2] and (not spec[3] or length%1==0),'基準幅の値が不正です。')
  interval=interval or 0;interval_unit=interval_unit or unit
  local interval_spec=Core.interval_specs[interval_unit];assert(interval_spec,'間隔補正の単位が不正です。')
  assert(finite(interval) and interval>=interval_spec[1] and interval<=interval_spec[2]
   and (not interval_spec[3] or interval%1==0),'間隔補正の値が不正です。')
  local length_grid=unit=='grid' and Core.grid_qn(project) or nil
  local interval_grid=interval_unit=='grid' and Core.grid_qn(project) or nil
  local cursor=R.GetCursorPositionEx(project);local s=cursor
  for i=0,count-1 do
   -- Markers remain points, but their next-position pitch keeps the same
   -- notional length used before interval support was added.
   local nominal_end=Core.advance(project,s,length,unit,length_grid)
   local e=kind=='marker' and s or nominal_end
   ranges[#ranges+1]={start=s,finish=e}
   if i<count-1 then s=Core.advance(project,nominal_end,interval,interval_unit,interval_grid) end
  end
 elseif mode=='items' or mode=='itemspan' or mode=='itemgroups' then
  local n=R.CountSelectedMediaItems(project);assert(n>0,'アイテムを選択してください。');assert(n<=1000,'選択アイテムは1000個までにしてください。')
  for i=0,n-1 do
   local item=R.GetSelectedMediaItem(project,i)
   local s=R.GetMediaItemInfo_Value(item,'D_POSITION');local len=R.GetMediaItemInfo_Value(item,'D_LENGTH')
   assert(finite(s) and finite(len) and len>0,'長さが不正なアイテムがあります。')
   ranges[#ranges+1]={start=s,finish=s+len}
  end
  table.sort(ranges,function(a,b) return a.start==b.start and a.finish<b.finish or a.start<b.start end)
  if mode=='itemgroups' then ranges=Core.overlap_groups(ranges)
  elseif mode=='itemspan' then
   local finish=ranges[1].finish;for _,r in ipairs(ranges) do finish=max(finish,r.finish) end
   ranges={{start=ranges[1].start,finish=finish}}
  end
 else
  assert(mode=='selection','追加方法が不正です。')
  local s,e=R.GetSet_LoopTimeRange2(project,false,false,0,0,false)
  assert(e>s,'先にREAPERで時間選択を作ってください。');ranges={{start=s,finish=e}}
 end
 for _,r in ipairs(ranges) do
  if kind=='marker' then r.finish=r.start end
  assert(r.start>=0 and r.finish>=0,'間隔により挿入位置がプロジェクト先頭より前になります。')
  assert(finite(r.start) and finite(r.finish) and (kind=='marker' or r.finish>r.start),'追加する範囲が不正です。')
 end
 return ranges
end
function Core.base64(data)
 local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
 local out={}
 for i=1,#data,3 do
  local a,c,d=data:byte(i,i+2);local n=a*65536+(c or 0)*256+(d or 0)
  out[#out+1]=b:sub((n>>18)+1,(n>>18)+1)..b:sub(((n>>12)&63)+1,((n>>12)&63)+1)..(c and b:sub(((n>>6)&63)+1,((n>>6)&63)+1) or '=')..(d and b:sub((n&63)+1,(n&63)+1) or '=')
 end
 return table.concat(out)
end
function Core.unbase64(data)
 local alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
 local map={};for i=1,64 do map[alphabet:byte(i)]=i-1 end
 local out={};local n,bits=0,0
 for i=1,#data do local v=map[data:byte(i)];if v then
  n=(n<<6)|v;bits=bits+6
  if bits>=8 then bits=bits-8;out[#out+1]=string.char((n>>bits)&255);n=n&((1<<bits)-1) end
 end end
 return table.concat(out)
end
-- CP932_TABLE is generated from Python's Windows-31J codec, loaded lazily.
local CP932_TABLE='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UzCxglQwsoJVMLOCVjC0glcwtYJYMLaCWTC3glowuIJbMLmCXDC6gl0wu4JeMLyCXzC9gmAwvoJhML+CYjDAgmMwwYJkMMKCZTDDgmYwxIJnMMWCaDDGgmkwx4JqMMiCazDJgmwwyoJtMMuCbjDMgm8wzYJwMM6CcTDPgnIw0IJzMNGCdDDSgnUw04J2MNSCdzDVgngw1oJ5MNeCejDYgnsw2YJ8MNqCfTDbgn4w3IJ/MN2CgDDegoEw34KCMOCCgzDhgoQw4oKFMOOChjDkgocw5YKIMOaCiTDngoow6IKLMOmCjDDqgo0w64KOMOyCjzDtgpAw7oKRMO+CkjDwgpMw8YKbMEqBnDBLgZ0wVIGeMFWBoTBAg6IwQYOjMEKDpDBDg6UwRIOmMEWDpzBGg6gwR4OpMEiDqjBJg6swSoOsMEuDrTBMg64wTYOvME6DsDBPg7EwUIOyMFGDszBSg7QwU4O1MFSDtjBVg7cwVoO4MFeDuTBYg7owWYO7MFqDvDBbg70wXIO+MF2DvzBeg8AwX4PBMGCDwjBhg8MwYoPEMGODxTBkg8YwZYPHMGaDyDBng8kwaIPKMGmDyzBqg8wwa4PNMGyDzjBtg88wboPQMG+D0TBwg9IwcYPTMHKD1DBzg9UwdIPWMHWD1zB2g9gwd4PZMHiD2jB5g9sweoPcMHuD3TB8g94wfYPfMH6D4DCAg+EwgYPiMIKD4zCDg+QwhIPlMIWD5jCGg+cwh4PoMIiD6TCJg+owioPrMIuD7DCMg+0wjYPuMI6D7zCPg/AwkIPxMJGD8jCSg/Mwk4P0MJSD9TCVg/YwloP7MEWB/DBbgf0wUoH+MFOBMTKKhzIyi4c5MoyHpDKFh6UyhoemMoeHpzKIh6gyiYcDM2WHDTNphxQzYIcYM2OHIjNhhyMza4cmM2qHJzNkhyszbIc2M2aHOzNuh0kzX4dKM22HTTNih1EzZ4dXM2iHezN+h3wzj4d9M46HfjONh44zcoePM3OHnDNvh50zcIeeM3GHoTN1h8QzdIfNM4OHAE7qiAFOmpIDTrWOB06clghO5I8JTk+OCk7jjwtOuokNTnOVDk5elxBOoJgRTk6JFE6OihVOoZgWTqKQF07AmRhOdYsZTriVHk7ljyFOvJcmTsCVKE5M7SpOopgtToaSMU6jmDJO+Is2TqSYOE7bijlOT5I7TuWOPE6lmD9OpphCTqeYQ05UlEVOdotLTlaUTU7hk05OwYxPTlKWVU5o5VZOqJhXTuaPWE6pmFlOs4ldTuOLXk7ujF9O55ZiTqSbcU6Ql3NO+5N+TqOKgE5Ui4JOqpiFTquYhk65l4hOXJeJToiRik6tmItOlo6MTvGTjk6wmJFOXYmSTt2MlE7cjJVO5IiYTmqYmU5pmJtOsY2cTp+Ink6xmJ9OspigTrOYoU5TlqJOtJikTvCMpU7liKZOkpaoTpyLq06di6xOnoutTuCSrk66l7BOtZizTraYtk63mLpObJDATlmPwU5tkMJOvJjETrqYxk67mMdOd4vKTqGNy07uic1OuZjOTriYz06nldROZY7VTmSO1k68kddOvZjYTnSV2U7lkN1OV4HeTr6Y307AmOFOTe3jTuOR5E7fl+VOyIjtTr+Y7k68ifBOwovyToeS9k6PjPdOwZj7TkOU/E5O7QBPT+0BT+mKA09Q7QlPwpgKT8mIDU/ejA5P6ooPT5qVEE+wlBFPeIsaT++JHE/lmB1PYJMvT4yUME/EmDRPupQ2T+CXOE9MkDlPUe06T2aOPE+Xjj1PvolDT8+SRk9BkkdPyJhNT8qITk/hkk9PWo9QT7KNUU9Dl1NPzJFVT72JVk9S7VdPx5hZT12XWk/DmFtPxZhcT+yNXU/GmF5PQ5tpT86Yb0/RmHBPz5hzT8CJdU+5lXZPyZh7T82YfE/xjH9PZ46DT6SKhk/SmIhPypiKT1Tti0/hl41PmI6PT8uYkU/QmJJPU+2UT1btlk/TmJhPzJiaT1Xtm0+fi51Py4igT6CLoU+/iatPRJutT5mWrk+Ola9P8oy1T06Qtk+1l79P1pXCT1eMw0+jkcRP4onJT0Xtyk9yj81PV+3OT9eY0E/cmNFP2pjUT9WY10+tkdhP2JjaT9uY20/ZmN1P25XfT9aY4U9NkONPk5bkT92Y5U/emO5PQ4/vT+uY809vlPVPVZX2T+aY+E/ulfpPtIn+T+qY/09a7QVQ5JgGUO2YCVBxkQtQwowNUHuUD1DF4BFQ7JgSUHyTFFDhmBZQ9IwZUPOMGlDfmB5QW+0fUNiOIVDnmCJQWe0jUO2VJFBskiVQ45gmUJGMKFDgmClQ6JgqUOKYK1DPlyxQ6ZgtUGCYNlDkizlQkIxAUFjtQlBe7UNQ7phGUFztR1DvmEhQ85hJUMyIT1DOlVBQ8phVUPGYVlD1mFpQ9JhcUOKSZVCSjGxQ9phwUF3tclDDjnRQpJF1UOOSdlD0i3hQ95h9UFWLgFD4mIVQ+piNUFSWkVCGjJRQX+2YUFCOmVD1lJpQ+ZisUMONrVBil7JQ/JizUEKZtFD7mLVQwo23UJ2PvlBYjMJQQ5nFUM2LyVBAmcpQQZnNUK2Tz1CckdFQoYvVUGyW1lBEmdhQYe3aULuX3lBFmeNQSJnlUEaZ51Btke1QR5nuUEmZ9FBg7fVQS5n5UEqZ+1DGlQBRVosBUU2ZAlFOmQRRrYkJUUyZElHyjhRRUZkVUVCZFlFPmRhR1JgaUVKZH1GejyFRU5kqUUSXMlHXljdRVZk6UVSZO1FXmTxRVpk/UViZQFFZmUFR8ohDUbOMRFFajEVRW49GUZuSR1Gii0hR5pBJUfWMSlFi7UtRjo1MUVuZTVHGlk5RZZNQUZmOUlFamVRRXJlaUX2TXFGVimJRXZlkUWPtZVH8k2hRU5FpUV+ZalFgmWtRqpRsUfaMbVFamG5RYZlxUaSLdVG6lXZRtJF3Ue+LeFFUk3xRk4yAUWKZglFjmYVR4JOGUX6JiVFmmYpR+42MUWWZjVHEjY9RZ5mQUezjkVFomZJRYJaTUWmZlVFqmZZRa5mXUeePmVHKjp1RZO2gUaWKolFumaRRbJmlUbuWplFtmahReZWpUW+ZqlFwmatRcZmsUX6TsFF1mbFRc5myUXSZs1FymbRR4Y21UXaZtlHolrdR4pe9UXeZvlFl7cRRppDFUXiZxlF5j8lReZnLUZySzFG9l81RgJPWUcOZ21F6mdxRo+rdUcOL4FF7meFRfZbmUYiP51H6kelRfZnqUeKT7FFm7e1RfpnwUYCZ8VFNivVRgZn2UaWL+FHKk/lRmon6UW+P/VGflP5RgpkAUoGTA1JukARSg5kGUqqVB1LYkAhSoIoKUqeKC1KEmQ5ShpkRUlmMFFKFmRVSZ+0XUvGXHVKJjyRSu5QlUsqVJ1KHmSlSmJcqUoiZLlKJmTBSnpMzUoqZNlKnkDdS/I04UpSMOVKLmTpSaI47Uo+NQ1LkkkRSjZlHUqWRSlLtjUtSjplMUo+ZTVJPkU9SjJlUUpGZVlJVlltShI1eUpCZY1KVjGRS3I1lUo2UaVKUmWpSkplvUpuVcFLoj3FSm5lyUoSKc1KVmXRSk5l1Um6RfVKXmX9SlpmDUmOKh1KAjIhSnJmJUquXjVKYmZFSnZmSUpqZlFKZmZtSzZecUmjtn1L3jKBSwYmjUvKXplJp7alSlY+qUneTq1KFjaxSoJmtUqGZr1Jb7rFS45e0UkqYtVKjmblS+Iy8UqKZvlJOisBSau3BUqSZw1J1lsVSupLHUkWXyVLXlc1SpZnSUtPo1VKuk9dSppnYUqiK2VKxlttSa+3dUp+P3lKnmd9S5ZXgUquZ4lKokONSqJnkUs6L5lKpmedSqYryUk2M81KsmfVSrZn4Uq6Z+VKvmfpS2Y7+UvmM/1LclgBTbO0BU+aWAlP1kwVT75UGU7CZB1Nt7QhTsZkNU7OZD1O1mRBTtJkVU7aZFlO7iRdTa5YZU/qNGlO3mR1TeJEgU6CPIVOniyNTuJkkU27tKlPZlC9TuZkxU7qZM1O7mThTvJk5U0OVOlPmiztT44g/U72TQFO9mUFTXI9DU+eQRVO/mUZTvplHU6GPSFPfjElTwZlKU7yUTVPCmVFT2pRSU7KRU1PskVRTpotXU+yTWFNQklpTjpRcU22WXlPEmWBT6JBmU1SMaVPFmW5TxplvU0uJcFPziHFT64pyU2/tc1OmkXRTcIt1U5GXd1PJmXhTtYl7U8iZf1Ooi4JTypmEU++Wk1Nw7ZZTy5mYU9CXmlP6jJ9TtIygU8yZpVPOmaZTzZmoU36QqVNYia1TfYmuU8+ZsFPQmbJTce2zU7WMtlPRmbtTjovCU1GOw1PSmchTlJbJU7ONylN5i8tTRpfMU2+RzVO9lM5T+47UU2aP1lPmjtdT847ZU5aP21O+lN1Tcu3fU9WZ4VNiieJTcJHjU/uM5FPDjOVT5YvoU9mZ6VNAkupT/JHrU6mL7FOij+1T2pnuU9iZ71PCifBT5JHxU7aO8lNqjvNTRYn2U5CK91OGjfhTaY76U9uZAVTcmQNUaIsEVGWKCFSHjQlUZ4sKVN2SC1REiQxUr5MNVLyWDlRAjQ9UmZcQVGaTEVT8jBtUTowdVOWZH1ThiyBUaZYmVNuUKVTkmStU3IosVN+ZLVTgmS5U4pk2VOOZOFR6izlUgZA7VKuVPFThmT1U3Zk+VOGMQFTemUJUQ5hGVPCVSFTmkklU4IxKVJCNTlTmmVFU25NfVOqZaFT8jmpU9I5wVO2ZcVTrmXNUoZZ1VOiZdlTxmXdU7Jl7VO+ZfFTEjH1UvZaAVPCZhFTymYZU9JmKVHXti1TujYxUYZiOVOmZj1TnmZBU85mSVO6ZnFR07aJU9pmkVEKapVT4mahU/JmpVHbtq1RAmqxU+ZmvVF2aslTnjbNUUIq4VPeZvFREmr1U9Ii+VEOawFSjiMFUaZXCVEGaxFT6mcdU9ZnIVPuZyVTGjdhURZrhVPWI4lROmuVURprmVEea6FSjj+lUiZbtVEya7lRLmvJUTpP6VE2a/VRKmv9Ud+0EVVOJBlW0jQdVT5APVUiaEFWCkxRVSZoWVaCILlVTmi9VQpcxVaWPM1VZmjhVWJo5VU+aPlXBkUBVUJpEVe2RRVVVmkZVpI9MVVKaT1XillNVW4xWVVaaV1VXmlxVVJpdVVqaY1VRmntVYJp8VWWaflVhmoBVXJqDVWaahFVQkYZVeO2HVWiaiVVBjYpVXpqLVZ2SmFVimplVW5qaVauKnFXsip1VhYqeVWOan1VfmqdVloyoVWmaqVVnmqpVcpGrVWmLrFWqi65VZJqwVfKLtlVjicRVbZrFVWuax1WlmtRVcJraVWqa3FVumt9VbJrjVWuO5FVvmvdVcpr5VXea/VV1mv5VdJoGVlGSCVbDiRRWcZoWVnOaF1amjxhWUokbVnaaKVbciS9WgpoxVvqPMlZ9mjRWe5o2VnyaOFZ+mkJWXIlMVliRTlZ4mlBWeZpbVpqKZFaBmmhW7YpqVoSaa1aAmmxWg5p0VqyVeFbTk3pWtpSAVoaahlaFmodWZIqKVoeaj1aKmpRWiZqgVoiaolZYlKVWi5quVoyatFaOmrZWjZq8VpCawFaTmsFWkZrCVo+aw1aSmshWlJrOVpWa0VaWmtNWl5rXVpia2FZkmdpW+o7bVmyO3lbxieBW9ojjVmOS7laZmvBWoo3yVs2I81Z9kPlWmpr6VsWM/VaRjf9WnJoAV5uaA1felQRXnZoIV5+aCVeemgtXoJoNV6GaD1eXjBJXgIkTV6KaFlekmhhXo5ocV6aaH1d5kyZXp5onV7OIKFfdjS1XXIwwV26SN1eomjhXqZo7V6uaQFesmkJX4o1HV8+LSldWlk5XqppPV62aUFe/jVFXQo1ZV3ntYVexmmRXo41lV3rtZldSkmlXrppqV9iSf1eymoJXgpCIV7CaiVezmotXXoyTV7SaoFe1mqJXQ42jV1+KpFe3mqpXuJqsV3vtsFe5mrNXtprAV6+aw1e6msZXu5rHV33tyFd87ctXhJbOV+mP0le9mtNXvprUV7ya1lfAmtxXV5TfV+aI4Fd1leNXwZr0V/uP91e3jvlXfJT6V+6K/FfpjQBYeJYCWLCTBViYjAZYzZEKWL+aC1jCmhVYwpEZWMOaHVjEmiFYxpokWOeSKlisii9Yn+owWIGJMVjxlTRY6o81WGeTOljkjT1YzJpAWLuVQVjbl0pY8olLWMiaUVhZkVJYy5pUWIOTV1hok1hYhJNZWLeUWljLkl5Yx41iWMeaaViWiWtYVZNwWMmacljFmnVYb5B5WM2aflhtj4NYq4uFWM6ak1jmlZdYnZGcWMSSnliB7Z9Y0JqoWG6Wq1jRmq5Y1pqyWILts1itlbhY1Zq5WM+auljSmrtY1Jq+WKSNwVjHlcVY15rHWGSSyljzicxY64/RWNma01jYmtVYiI3XWNqa2FjcmtlY25rcWN6a3ljTmt9Y4JrkWN+a5VjdmutYbY7sWHCQ7lhzke9Y4ZrwWLqQ8VjriPJYhJT3WNmS+VjjmvpY4pr7WOSa/Fjlmv1Y5poCWeeaCVnPlQpZ6JoLWYPtD1nEiRBZ6ZoVWVuXFllPihhZx5kZWWePGlm9kRtZ6pocWemWIlmyliVZ7JonWeWRKVlWkypZvpErWXaVLFntmi1Z7pouWZuJMVm4jjJZ75o3Wc6IOFnwmj5Z8ZpEWYKJR1nvikhZ3pNJWfKVTln1mk9ZdJFQWfSaUVlfjFNZhO1UWXqWVVnzmldZhZNYWfeaWln2mltZhe1dWYbtYFn5mmJZ+JpjWYftZVmciWdZ+ppoWaePaVn8mmpZRJJsWfuablmxlXNZl490WXqTeFlAm31ZRI2BWUGbgllAlINZ3JSEWc+WillElI1ZSpuTWVeLlllkl5lZrZabWaqbnVlCm6NZRZukWYjtpVnDkahZV5asWWmTsllGm7lZhZa6WYntu1nIjb5ZqI/GWUebyVlvjstZbo7QWbeI0VnGjNNZqZDUWc+I2VlLm9pZTJvcWUmb5VlXieZZrYroWUib6lnDlutZUJX2WaaI+1n3iP9ZcI4BWtCIA1qhiAlaUZsRWk+bGFq6lhpaUpscWlCbH1pOmyBaUJAlWk2bKVrYlS9a4ow1WlabNlpXmzxaqY9AWlObQVpLmEZaa5RJWlWbWlqljWJaWJtmWneValpZm2xaVJt/WrmWklp9lJpaWpubWlGVvFpbm71aX5u+WlybwVrFicJaXpvJWrmOy1pdm8xamYzQWmub1lpkm9daYZvhWoSS41pgm+ZaYpvpWmOb+lplm/taZpsJW/CKC1tomwxbZ5sWW2mbIlvsjypbbJssW9qSMFtkiTJbaps2W22bPltum0BbcZtDW2+bRVtwm1BbcY5RW3KbVFtFjVVbc5tWW4rtV1uajlhbtpFaW3SbW1t1m1xbeY5dW0aNX1vQlmNbR4tkW8eMZVt2m2Zbd4ppW3eba1u3kXBbeJtxW6Gbc1t5m3Vbept4W3ubelt9m4BbfpuDW4CbhVvukYdbRomIW+eOiVvAiItbdpGMW66KjVuzjo9bR42VW4aTl1tAj5hbr4qZW4iSmlvokptbtoicW1iLnVvzlZ9bwI6iW3GLo1vpkKRbuo6lW0eXpluBm65be4uwW8mNs1tRirRbg4m1W6qPtlvGibhbgpu5W2WXv1toj8Bbi+3CW+KOw1uDm8Rb8YrFW9CTxlunlsdbhJvJW4WbzFt4ldBbh5vSW6aK01v1i9RbhpvYW43t21uwit1bUZDeW4ub31tAjuFbx4niW4qb5FuIm+VbjJvmW4mb51tKlOhby57pW1KQ61uNm+xbju3uW76X8FuOm/NbkJv1W56S9luPm/hboZD6W5uO/lvOkf9b9Y4BXJWVAlzqkARcy44FXJGbBlyrjwdckpsIXJObCVzRiApcuJELXHGQDVyUmw5csZMPXKyPEVytjxNclZsWXOuQGlyujx5cj+0gXJabIlyXmyRc3pYoXJibLVzEizFcQY84XJmbOVyamzpc2o47XEuQPFzykz1cc5A+XPaUP1xBlEBcx4tBXJubRVyPi0ZcnJtIXPyLSlzNk0tcrolNXHKOTlydm09coJtQXJ+bUVz7i1NcnptVXFeTXlyukWBcapNhXMaOZFx3kWVcmpdsXKKbblyjm29c1JNxXFKOdlylm3lcppuMXKebkFzyipFcqJuUXKmboVyqiaZckO2oXFqRqVziiqtcq5usXKaWsVzQkbNceIq2XK2bt1yvm7hc3Yq6XJHtu1ysm7xcrpu+XLGbxVywm8dcspvZXLOb4Fy7k+FcrIvoXOOJ6Vy0m+pcuZvtXLeb71z1lfBc9JX1XJLt9lyHk/pctpv7XHOP/Vy1mwddkpALXbqbDl3ojRFdwJsUXcGbFV27mxZdUooXXbybGF3FmxldxJsaXcObG12/mx9dvpsiXcKbJ12T7Sld9pVCXZbtS13Jm0xdxptOXcibUF2Sl1Jdx5tTXZTtXF29m2ldk5BsXcqbbV2X7W9dtY1zXcubdl3Mm4Jdz5uEXc6bh13Nm4tdiJOMXbibkF3Vm51d0ZuiXdCbrF3Sm65d05u3XdabuF2Y7bldme26XeSXvF3Xm71d1JvJXdibzF3eis1d2ZvQXZrt0l3bm9Nd2pvWXdyb213dm91d7JDeXUKP4V2Ej+Ndg5HlXUiN5l22jeddSY3oXZCL613em+5dt43xXciM8l3fm/NdpJb0XWKU9V3gm/ddSo37XaqK/V1Gkv5d0IsCXnOOA156lQZev5QLXuGbDF7zihFe5JsWXp+SGV7jmxpe4psbXuWbHV7pkiVeg5ArXnSOLV7IkC9e0ZEwXkGLM16gkjZe5ps3XuebOF7tjz1eWJZAXuqbQ17pm0Re6JtFXp2VR17xm0xeeZZOXuubVF7tm1Vei5ZXXuybX17um2FeppRiXu+bY168lWRe8JtyXrGKc169lXReTpR1XvKbdl7zm3heS415XrKKel70m3tetox8XmOXfV5Il35e9Ip/XvabgV6hkoNeTI2EXq+Ph17dlIpesI+PXpiPlV7qkpZe95WXXliTml5NjZxee5WgXvebpl54k6dewI2rXsmMrV7rkrVewYi2Xo6Pt15OjbheZpfBXvibwl75m8NecJTIXvqbyV71l8peTJjPXvyb0F77m9NeZorWXkCc2l5DnNteRJzdXkKc315fleBesY/hXkac4l5FnONeQZzoXkec6V5InOxeSZzwXkyc8V5KnPNeS5z0Xk2c9l6Eifde7JL4Xk6c+l6ajPte9In8XlWU/l5PnP9e+ZMBX9mVA19QnARfTZgJX1GcCl++lQtfVJwMX5+YDV+vmA9fro4QX/OTEV9VnBNffIsUX6KSFV/4iBZfVpwXX6SVGF9PjRtfb5IfX+2SIV+b7SVf7ZYmX7eMJ1/KjClfV5wtX1icL19enDFf4440X5ztNV+jkjdfrYs4X1mcPF9KlT5fZZJBX1qcRV9L7UhfW5xKX66LTF9cnE5fXZxRX1+cU1+Wk1ZfYJxXX2GcWV9inFxfU5xdX1KcYV9jnGJfYIxmX0aVZ1+d7Wlfyo1qX1aVa1+kkmxfapVtX2SccF+yj3FfZYlzX2Wcd19mnHlf8JZ8X96Uf19pnIBfnYmBX6qQgl9onINfZ5yEX2GMhV/SkYdfbZyIX2ucil9qnItfpZeMX+OMkF+Zj5FfbJySX2uTk19dj5dfvpOYX3CcmV9vnJ5fbpygX3GcoV/kjKhfcpypX5yVql96j61fc5yuX/eUs1+/k7RfpZK3X57tuV9Pk7xfdJy9X0qLw19TkMVfS5XMX/WKzV9FlNZfdZzXX3WO2F9ZltlfWpbcX56J3V96nN5fn+3gX4mS5F93nOtf9YnwX6uc8V95nPVfT5T4X3ic+192nP1fmo3/X3ycDmCDnA9giZwQYIGcEmB7kxVghpwWYHyVGWCAnBtghZwcYOWXHWB2jiBg05EhYH2cJWB9iyZgiJwnYKuQKGCFiSlggpwqYPaJK2CHnC9gr4sxYIScOmCKnEFgjJxCYJacQ2CUnEZgkZxKYJCcS2D2l01gkpxQYLCLUmBQjVVgmo9ZYJmcWmCLnF1goO1fYI+cYGB+nGJg+IljYJOcZGCVnGVgcJJoYKaNaWC2iWpgjZxrYJicbGCXnG1gsYtvYKeRcGCGinVgYox3YI6cgWCanINgnZyEYJ+chWCh7Ylgu46KYKLti2ClnIxg7pKNYJuckmCjnJRg94mWYKGcl2CinJpgnpybYKCcn2DljKBgSZejYLOKpmB4iadgpJypYFmUqmCriLJg35SzYHuctGCqnLVgrpy2YOOWuGCnnLxgiZO9YKycxWDuj8ZgrZzHYNWT0WBmmNNgqZzVYKTt2GCvnNpgm43cYMmQ3mCj7d9g0ojgYKic4WCmnONgeZHnYJyc6GBTjvBgxJHxYLuc8mCm7fNgepH0YLac9mCznPdgtJz5YOSO+mC3nPtgupwAYbWcAWFEjwNhuJwGYbKcCGH6lglh+ZYNYbycDmG9nA9h04gRYaftFWGxnBph8IsbYaSIH2G0iiBhpe0hYbmcJ2HBnChhwJwsYcWcMGGp7TRhxpw3YajtPGHEnD1hx5w+Yb+cP2HDnEJhyJxEYcmcR2G+nEhhnI5KYcKcS2HUkUxhUY1NYbCcTmFUkFNh1pxVYeeVWGHMnFlhzZxaYc6cXWHVnF9h1JxiYZ2WY2G1imVh0pxnYWSMaGFTimthz5xuYbaXb2HRnHBh1IhxYdOcc2HKnHRh0Jx1YdecdmFjjHdhy5x+YXyXgmFKl4dh2pyKYd6cjmGekZBh95eRYd+clGHcnJZh2ZyYYartmWHYnJph3ZykYa6Vp2Gyk6lhZYyrYeCcrGHbnK5h4ZyyYZuMtmGvibph6Zy+YbaKw2HnnMZh6JzHYaeNyGHmnMlh5JzKYeOcy2HqnMxh4pzNYeyc0GH5ieNh7pzmYe2c8mGmkvRh8Zz2Ye+c92HlnPhhnIz6YfCc/GH0nP1h85z+YfWc/2HynABi9pwIYvecCWL4nApi6JUMYvqcDWL5nA5iXo8QYqyQEWLkiRJi+okTYqvtFGL7nBZivYgaYsqQG2L8nB1iweYeYkCdH2KBjCFiQZ0mYu2QKmJCnS5iQ50vYlmLMGJEnTJiRZ0zYkadNGLVkThiy4w7Yt+WP2JblkBiio9BYkedR2LukEhiu+dJYuCUS2Lojk1iy41OYkidU2LFkVVipZVYYu+RW2JLnV5iSZ1gYkydY2JKnWhiTZ1uYq+VcWK1iHZifZV5YuGUfGJOnX5iUZ1/YrOPgGJai4JiT52DYladhGK0j4liUJ2KYmOUkWJ9l5JiUp2TYlOdlGJXnZViipOWYlSdl2JSjZhi3JCbYmWdnGKylJ5i8JGmYqztq2LilKxiq52xYviVtWLvkrlilZa7YlqdvGKfib1iipLCYmOdxWJTksZiXZ3HYmSdyGJfncliZp3KYmKdzGJhnc1ij5TPYlud0GL7idFiWZ3SYpGL02LxkdRiVZ3XYlid2GJTjdli2ZDbYrWP3GJgnd1icZTgYpKL4WJniuxih4rtYkCQ7mJone9ibZ3xYmmd82KdjPVibp32YkGO92KJjf5iRY//YlydAWOdjgJja50HY3eOCGNsnQljwogMY2edEWOnkhljk4sfY7KLJ2NqnShjpYgrY8GNL2NVkDpj8JI9Y9KUPmNwnT9jfZFJY6iRTGNKjk1jcZ1PY3OdUGNvnVVj35VXY7uSXGN7kWdj+ZVoY8yOaWOAnWtjfp1uY5iQcmOejHZjeJ13Y7ePemPmk3tjUJSAY3adg2N8kYhj9o6JY3udjGO2j45jdZ2PY3qdkmNylJZjdJ2YY0CMm2N8ip9jfJ2gY6mXoWPMjaJjVJKjY3mdpWPakKdjVI2oY4SQqWOGiapjW5GrY3edrGNki7JjZoy0Y82StWN9nbtjfpG+Y4GdwGODncNjtZHEY4mdxmOEncljhp3PY2CV0GPxktJjh53WY0uX2mNnl9tjt4rhY6yI42OFneljgp3uY/aK9GOHifVjre32Y4id+mNolwZkjJ0NZLmRD2STnRNkjZ0WZIqdF2SRnRxkcp0mZI6dKGSSnSxkwJQtZIuTNGSLnTZkj506ZGeMPmTvjUJk25BOZJedWGRFk2Bkru1nZJSdaWSAlm9klZ12ZJadeGTMlnpkoJCDZIKMiGSdnZJkVI6TZJqdlWSZnZpkUZSdZK/tnmSzk6RkUJOlZJudqWScnatkj5WtZGSUrmRCjrBk75CyZG+WuWRoirtko528ZJ6dwWRpl8JkpZ3FZKGdx2Sinc1kgJHOZLDt0mSgndRkXp3YZKSd2mSfneBkqZ3hZKqd4mRGk+NkrJ3mZEOO52SnnexkW4vvZK2d8WSmnfJksZ30ZLCd9mSvnfpksp39ZLSd/mTvjwBls50FZbedGGW1nRxltp0dZZCdI2W5nSRluJ0qZZidK2W6nSxlrp0vZXiONGW7nTVlvJ02Zb6dN2W9nThlv505ZfyJO2VVjT5l+pU/Za2QRWXMjEhlwZ1NZcSdTmWx7U9lcZVRZX6LVWXDnVZlwp1XZXOUWGXFnVlls4tdZcedXmXGnWJluIpjZVWOZmXWk2xlaIxwZZSQcmXInXRlrpB1ZUeTd2V+lXhlyZ2CZcqdg2XLnYdltpWIZXybiWXEkIxla5WOZdaNkGXjlJFlwZSXZWyTmWW/l5tlzZ2cZc6On2XOnaFltIikZdKLpWXLkKdlgJWrZc+drGVhjq1lZpKvZXqOsGVWkLdl0J25ZfuVvGWXib1le47BZdOdw2XRncRl1J3FZbeXxmXSnctl+ZDMZdWdz2WwkdJl1p3XZfiK2WXYndtl153gZdmd4WXaneJl+YrlZfqT5mVVkudljIvoZXyO6WWBkexle4/tZa6I8WXbnfploIn7Zd+dAGay7QJmVo0DZt6dBmapjQdmuI8JZrXtCmbdnQxmuY8OZr6WD2aojRNm1YgUZsyQFWaz7Rxm5J0eZrftH2avkCBmZokkZrjtJWZ0jydmhpYoZvCNLWa6jy5mtu0vZqWQMWZH7TRm4501ZuGdNmbinTtmtO08ZouSP2ZFnkFm6J1CZp6OQ2ZXjURm5p1JZuedS2ZXkE9m5Z1SZk6OV2a67Vlmu+1dZuqdXmbpnV9m7p1iZu+dZGbrnWVmue1mZkGKZ2bsnWhm7Z1pZtOUbmaBlW9maYxwZvCdc2a97XRmsJB2ZruPemZxkoFmxYuDZvGdhGb1nYdmyYmIZvKdiWb0nY5m852RZouPlmZnkpdmw4iYZvadmWa+7Z1m952gZr/tomaokqZm75erZmKOrmbplbJmwO20ZlyWuGZBnrlm+Z28Zvydvmb7nb9mwe3BZvidxGZAnsdm3JPJZvqd1mZCntlmjI/aZkOe3GZql91mmJTgZkSe5mZGnulmR57wZkie8mbIi/NmZ4n0ZliN9WZJnvdmSp74ZpGP+WaCkfpmwu37Zkrt/GbWmf1mXZH+ZlyR/2bWkQBnxY0DZ/CYCGeOjAlnTJcLZ/yVDWeelQ5nw+0PZ0ueFGfxjRVnvZIWZ0yeF2dOmBtnXZYdZ6mSHmdNnh9n+oomZ06eJ2dPnihn2JYqZ6KWK2eWlixne5YtZ0SOLmdRnjFn6Y40Z3CWNmdTnjdnVp44Z1WeOmf3ij1ngIs/Z1KeQWdUnkZnV55JZ5mQTmebl09nx4hQZ96NUWe6kVNn245WZ/GPWWdanlxnbZNeZ1ieX2epkWBnWZ5hZ/CPYmfblmNnW55kZ1yeZWeIl2Znxe1qZ2GebWdZjW9ndJRwZ16ecWeMk3Jn3J1zZ+CddWdui3dnZpR8Z2Cefme8j39nwpSFZ2aeh2f4lIlnXZ6LZ2OejGdinpBnzZCVZ42Wl2fRl5pnh5acZ8qJnWd9jqBnZ5ihZ2WeomeVkKZnZJ6pZ1+er2fNjLNna560Z2metmfLibdnZ564Z22euWdznrtnxu3AZ8jtwWfGkcRnv5XGZ3WeymdBlc5ndJ7PZ5CU0GdeltFnuYrTZ/WQ1Gdfj9hn0ZLaZ02X3Wdwnt5nb57iZ3Ge5Gdunudndp7pZ2ye7Gdqnu5ncp7vZ2ie8WeMkvNn9pb0Z8SO9WfyjftnuI3+Z4+W/2dgigFoye0CaMySA2jIkwRoaIkTaPCQFmiykBdoSYweaHieIWhajSJonIopaHqeKmiUiitogZ4yaH2eNGjxkDhoaoo5aKqNPGhpij1ozY1AaHueQWiFjEJoaoxDaI2TRGjK7UZoeZ5IaMSITWh8nk5ofp5QaMuLUWhLjFJox+1TaLqKVGhqi1logp5caPeNXWiRll9oVo5jaIOeZ2hPlXRoj552aLGJd2iEnn5olZ5/aIWegWjAl4NojJ6FaH6UjWiUno9oh56TaLKIlGiJnpdoW42baIuenWiKnp9ohp6gaJGeomi9j6Zo65qnaOaMqGicl61oiJ6vaPKSsGhCirFoq42zaICetWiQnrZogYq5aI6eumiSnrxojpPEaPyKxmiwnshoSO3JaMeWymiXnsto+4rNaJ6ez2jL7dJoX5bUaJ+e1WihntdopZ7YaJme2mhJkt9oj5PgaKme4WicnuNopp7naKCe7mhYkO9oqp7yaLGQ+Wionvpou4oAaW+YAWmWngRppJ4FadaICGmYngtpuJYMaZ2eDWlBkA5pxZIPaZOeEmmjnhlpmpAaaa2eG2mRihxpn4whaa+eImmaniNprp4laaeeJmmbnihpq54qaayeMGm9njRpzJM2aaKeOWm5nj1pu54/adaSSmlrl1NplpVUabaeVWnIkVlpvJ5aaV6RXGmznl1pwJ5eab+eYGntk2Fpvp5iaeiTaGnN7Wppwp5rabWebWnGi25puJ5vaXyPc2mAlHRpup51acmLd2mynnhptJ55abGefGlPmH1peYp+abeegWnBnoJpVIqKaeWNjml8iZFp0p6UaVCYlWnVnphpz+2baVmQnGnUnqBp056nadCermnEnrFp4Z6yacOetGnWnrtpzp6+acmev2nGnsFpx57Dac+ex2mg6sppzJ7LaVyNzGnGks1phJHOacqe0GnFntNpyJ7YaWyX2WmKlt1pzZ7eadee4mnQ7edp357oadie62nlnu1p457yad6e+WndnvtpzpL9aYWR/2nbngJq2Z4FauCeCmrmngtq85QMauyeEmrnnhNq6p4UauSeF2qUkhlqV5UbatqeHmrinh9qvo8has2WImr2niNq6Z4paqCMKmqhiStqfoouatGeMGrR7TVqv482au6eOGr1njlq9446apKKPWpNkkRq655GatPtR2rwnkhq9J5LarSLWGpri1lq8p5fakCLYWrJk2Jq8Z5mavOea2rS7XJq7Z5zatTteGrvnn5q1e1/aoCKgGpokoRq+p6NaviejmrnjJBq956XakCfnGp3nqBq+Z6iavueo2r8nqpqS5+sakefrmqNnrNqRp+4akWfu2pCn8Fq6J7CakSfw2pDn9FqSZ/TakWY2mpMn9tq+Yveakif32pKn+Jq1u3katft6GqllOpqTZ/6alGf+2pOnwRrk5cFa0+fCmvcnhJrUp8Wa1OfHWtUiR9rVZ8ga4eMIWufjiNr04sna6KJMmt+lzdrV584a1afOWtZnzprXIs9a9SLPmu8ikNrXJ9Ha1ufSWtdn0xrzIlOa1aSUGten1NrvYpUa2CfWWtfn1trYZ9fa2KfYWtjn2Jrfo5ja7OQZGufjWZrkJVpa+CVamtjmG9rlY5za86NdGvwl3hrZJ95a2Wfe2uAjn9rZp+Aa2efg2tpn4RraJ+Ga3eWiWt9j4pr6o6La2OOjWtqn5VrbJ+Wa0KQmGtrn55rbZ+ka26fqmtvn6trcJ+va3GfsWtzn7Jrcp+za3SftGujibVraZK3a3WfumtFjrtra4q8a3afv2thk8BryprFa0KLxmt3n8treJ/Na+qVzmuIltJrxZPTa3mf1GvklNZr2O3Ya/mU22vRlt9rep/ra3yf7Gt7n+9rfp/za32fCGyBnw9sgY4RbK+WE2yCnxRsg58XbEOLG2yEnyNshp8kbIWfNGyFkDdsWJU4bGmJPmzDlD9s2e1AbPOSQWxgj0JsgYtObMSUUGysjlVsiJ9XbL6KWmyYiVxs2u1dbPCTXmyHn19sXY1gbHKSYmyJn2hskZ9qbIqfb2zc7XBsv5FybIKLc2ySn3psiIx9bESLfmyQn4Fsjp+CbIufg2yAl4Zs2+2IbL6SjGzXk41sjJ+QbJSfkmyTn5NsQoyWbKuJmWy5jZpsjZ+bbI+foWx2lqJs8pGrbJeWrmycn7FsnZ+zbM2JuGymlbls+5a6bJ+fu2yhjrxswI+9bJifvmyen79siInBbLWLxGyVn8Vsmp/JbPKQymyRlMxs5ZTTbJef1WxAltdsmZ/ZbKKf2mzd7dtsoJ/dbJuf4WxBluJsZ5TjbIOL5WxEk+hsjZLqbKOf72yhn/Bs15HxbJaf82xqiQRt3u0LbW2XDG2unxJtrZ8XbfSQGW2qnxttjJcebbSTH22knyVtw5IpbWuJKm1ejSttp58ybUaPM22snzVtq582baafOG2pnzttiIo9baifPm1olEFtrJdEbfKPRW3zkFlttJ9abbKfXG1slWNtr59kbbGfZm1ZiWltX41qbVGYbG1cim5tgpVvbeDtdG2Bl3dtQ4p4bVqQeW2zn4VtuJ+Hbd/tiG3Bj4xtT5eObbWfk22wn5Vttp+WbeHtmW3cl5ttk5OcbcCTrG3i7a9tVYqybXSJ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B43U5giNoZEKjdPmC43kig2N1uYPjdXmEI3X5hKNk+4TjdnmFI3b5haN3OZkjdSQZo3NjmeN3eZrjXGKbY3e5nCNlpFxjd/mc43g5nSNi5V2jZTud41Oi4GN4eaFjbSSio16iZmN4uajje+OqI2WkLONq5G6jeXmvo3k5sKN4+bLjevmzI3p5s+N5ubWjejm2o3n5tuN6ubdjZeL343u5uGN1ZDjje/m6I3XjOqN7Obrje3m741ImPONtZL1jUiR/I3w5v+N8+YIjvHmCY7y5gqOeJcPjqWTEI725h2O9OYejvXmH4735iqOSOcwjvrmNI775jWO+eZCjvjmRI77kkeOQOdIjkTnSY5B50qO/OZMjkLnUI5D51WOSudZjkXnX47WkGCOR+djjknnZI5G53KOTOd0jlKPdo5L53yOTeeBjk7nhI5R54WOUOeHjk/nio5T54uOUueNjvSWkY5V55OOVOeUjlbnmY5X56GOWeeqjljnq45nkKyOWuevjuuLsI5b57GOXee+jl7nxY5f58aOXOfIjmDnyo7UjsuOYefMjk+LzY5SjM+Olu7SjqyM245i59+O7pPijl2T445j5+uOZuf4jrKO+45l5/yOZOf9jnmM/o5n5wOPcooFj2nnCY/ajQqPaOcMj3HnEo9r5xOPbecUj+OVFY9q5xmPbOcbj3DnHI9u5x2PUIsfj2/nJo9y5ymPeZQqj9aXL49TjzOPc+c4j0GXOY915zuPdOc+j3jnP49gl0KPd+dEj42KRY9250aPe+dJj3rnTI95502PUZNOj3znV49951yPfudfj4yNYY9EjGKPgOdjj4HnZI+C55uPaJCcj4Pnno+rjp+PhOejj4Xnp4+fmaiPnpmtj4bnro+Q46+Ph+ewj0OSsY9KkLKPX5S3j4jnuo/TlbuP0pK8j56Nv49IksKPSYnEj5iWxY92kM6PfYzRj9+L1I/UldqPiefij4vn5Y+K5+aP3onpj/ST6o+M5+uPl5Ttj1KT74+N5/CPcY/0j4/n94/AlviPnuf5j5Hn+o+S5/2Px5IAkN6RAZCXkQOQppMFkJDnBpB0iwuQmecNkJbnDpCj5w+Qp5MQkICSEZCT5xOQ/JIUkHKTFZCU5xaQmOcXkICQGZCHlBqQypIdkMCQHpCX5x+QrJEgkKKRIZCV5yKQp4gjkEGYJ5Ca5y6Q35ExkFSPMpBpkDWQnOc2kJvnOJDtiDmQnec8kE6VPpCl50GQ2ZNCkIuQRZB4kkeQ9otJkKTnSpBWl0uQXolNkNWVTpDfiU+Qn+dQkKDnUZCh51KQoudTkLmTVJBCklWQ4YhWkKbnWJCn51mQoepckLuRXpCo52CQk4lhkGuRY5CtjGWQeZdnkJnuaJCp52mQS5NtkJiRbpDVjm+QqudykK3ndZCFj3aQq+d3kEqReJBJkXqQ4oh8kMmXfZCv53+Q8JSAkLHngZCw54KQrueDkITihJDSioeQjueJkLPnipCy54+QtOeRkFeXo5Dfk6aQTZaokLXnqpDXjq+QtuexkLfntZC457iQQJPBkOiIypB4jc6QWZjbkLzn3pCa7uGQU4zikLnn5JC65+iQlJXtkHOK9ZBYl/eQvYv9kHOTApG95xKRvucVkZzuGZG/5yeRne4tkUGTMJHB5zKRwOdJkdGTSpHC50uRVY9Mkd6OTZF6lE6RkZJSkfCOVJGMkFaRw+dYkcTnYpF8kGORxedlkcbnaZHH52qRj5dskVaPcpHJ53ORyOd1kXmNd5GTjXiRX46Ckcznh5GGj4mRy+eLkcrnjZHnkZCR7YySkcGQl5GulJyRWI+ikc3npJHdj6qR0Oerkc7nr5HP57SR0ue1kdHnuJH4j7qR0+fAkdTnwZHV58aRzpTHkdGNyJHfjsmR1ufLkdfnzJGil82RZI/OkeyWz5HKl9CR2OfRkeCL1pHZ59eRn+7YkUKT2pGe7tuR3OfckZiK3ZFqkN6RoO7fkdrn4ZHb5+OR3pLkkaPu5ZGk7uaRdJbnkfqL7ZGh7u6Rou71kd7n9pHf5/yR3ef/keHnBpKl7gqSp+4Nkt2TDpJiihCSpu4RkuXnFJLi5xWS5OcekuDnKZJu6CyS4+c0kumXN5LYjDmSru46kqjuPJKq7j+S7edAkqnuRJJTk0WS6OdIkuvnSZLp50uS7udOkqvuUJLv51GSre5XkufnWZKs7lqS9OdbkpSJXpLm52KSq5RkkurnZpLej2eSr+5xknqNd5Kx7niSsu5+kmeWgJLii4OSZY+FkrqTiJJD7ZGSTJGTkvLnlZLs55aS8eeYksGWmpK2kpuS8+eckvDnp5Kw7q2SS5G3kvfnuZL258+S9efQkrbu0pJOltOSuu7Vkrju15K07tmSte7gkrnu5JKbj+eSs+7pkvjn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vJlo6cGZnZTEmcqRxZl3icaZ7IvIme2L0JmTktGZbenSme6L1ZntidiZbOnbmWrp3Zlr6d+ZaenimXfp7Zlu6e6Zb+nxmXDp8plx6fiZc+n7mXLp/5l4jwGadOkFmnbpDppSiw+adekSmpuRE5qxjBmaeOkomsuRK5p56TCaq5M3mnrpPpqA6UCafelCmnzpQ5p+6UWae+lNmoLpTprf7lWagelXmoTpWprBi1uag+lfmoXpYpqG6WSaiOllmofpaZqJ6Wqai+lrmorpqJqcja2ajOmwmo3puJpbiryajunAmo/pxJqRkM+akOnRmpHp05qS6dSak+nYmoKN2Zrg7tya4e7empTp35qV6eKalunjmpfp5pqY6eqar5Trmprp7ZpFle6am+nvmpnp8Zqd6fSanOn3mp7p+5qf6QaboOkYm6HpGpui6R+bo+kim6TpI5ul6SWbpuknm6fpKJuo6Smbqekqm6rpLpur6S+brOkxm1SfMput6Tub9uI8m1OLQZtAikKbsI1Dm6/pRJuu6UWbo5ZNm7HpTpuy6U+bsOlRm7PpVJuCllibtOlam5uLb5tEmHKb4+50m7XpdZvi7oObt+mOm7yIj5vk7pGbuOmSm6mVk5u26ZabuemXm7rpn5u76aCbvOmom73pqpuOlqubTI6tm/iNrptOkbGb5e60m77puZvB6bub5u7Am7/pxpvC6cmb74zKm8Dpz5vD6dGbxOnSm8Xp1JvJ6dabSY7bm+KR4ZvK6eKbx+njm8bp5JvI6eibfozwm87p8ZvN6fKbzOn1m7GIAJzn7gSc2OkGnNTpCJzV6Qmc0ekKnNfpDJzT6Q2cgooQnGuYEpzW6ROc0ukUnNDpFZzP6Ruc2ukhnN3pJJzc6SWc2+ktnGiVLpzZ6S+c8YgwnN7pMpzg6Tmcj4o6nMvpO5xWiT6c4ulGnOHpR5zf6UicTJJSnJCWV5zYl1qc4+lgnOTpZ5zl6Xac5ul4nOfp5Zy5kuec6OnpnLWU65zt6eyc6enwnOrp85xQlvScwpb2nM6TA53u6Qad7+kHnbyTCJ3s6Qmd6+kOnaiJEp336RWd9ukbnZWJH5306SOd8+kmnfHpKJ2biiqd8OkrnbCOLJ2niTudg40+nfrpP5356UGd+OlEnfXpRp376Uid/OlQnUTqUZ1D6lmdRepcnUyJXZ1A6l6dQepgnZSNYZ23lmSdQuprnenubJ1Rlm+dSupwnejucp1G6nqdS+qHnUjqiZ1H6o+de4yanUzqpJ1N6qmdTuqrnUnqr53y6bKdT+q0nd+SuJ1T6rqdVOq7nVLqwZ1R6sKdV+rEnVDqxp1V6s+dVurTnVnq2Z1Y6uadW+rtnVzq751d6vKdaJj4nVrq+Z3pkfqd6439nV7qGZ7r7hqeX+obnmDqHp5h6nWeYup4nrKMeZ5j6n2eZOp/nq2OgZ5l6oieZuqLnmfqjJ5o6pGea+qSnmnqk55bmJWeauqXnu2XnZ5s6p+e2Zelnm3qpp6elKmebuqqnnDqrZ5x6rieb+q5no2Nup7Llrueg5a8nvWbvp6An7+em5bEnqmJzJ5z6s2eb4vOnnTqz5516tCedurRnuzu0p6VjdSed+rYntLg2Z7Zltue4ZHcnnjq3Z566t6eeergnnvq5Z586uiefervnn7q9J6A6vaeger3noLq+Z6D6vuehOr8noXq/Z6G6gefh+oIn4jqDp9DkxOf24wVn4rqIJ9skSGfi+osn4zqO59AlT6fjepKn47qS59W4k6f2OZPn+voUp+P6lSfkOpfn5LqYJ+T6mGflOpin+6XY5+R6maflepnn5bqap+Y6myfl+pyn5rqdp+b6nefmeqNn7SXlZ+c6pyfneqdn3PioJ+e6gDgQPAB4EHwAuBC8APgQ/AE4ETwBeBF8AbgRvAH4EfwCOBI8AngSfAK4ErwC+BL8AzgTPAN4E3wDuBO8A/gT/AQ4FDwEeBR8BLgUvAT4FPwFOBU8BXgVfAW4FbwF+BX8BjgWPAZ4FnwGuBa8BvgW/Ac4FzwHeBd8B7gXvAf4F/wIOBg8CHgYfAi4GLwI+Bj8CTgZPAl4GXwJuBm8CfgZ/Ao4GjwKeBp8CrgavAr4GvwLOBs8C3gbfAu4G7wL+Bv8DDgcPAx4HHwMuBy8DPgc/A04HTwNeB18DbgdvA34HfwOOB48DngefA64HrwO+B78DzgfPA94H3wPuB+8D/ggPBA4IHwQeCC8ELgg/BD4ITwROCF8EXghvBG4IfwR+CI8EjgifBJ4IrwSuCL8EvgjPBM4I3wTeCO8E7gj/BP4JDwUOCR8FHgkvBS4JPwU+CU8FTglfBV4JbwVuCX8FfgmPBY4JnwWeCa8Frgm/Bb4JzwXOCd8F3gnvBe4J/wX+Cg8GDgofBh4KLwYuCj8GPgpPBk4KXwZeCm8Gbgp/Bn4KjwaOCp8GngqvBq4Kvwa+Cs8GzgrfBt4K7wbuCv8G/gsPBw4LHwceCy8HLgs/Bz4LTwdOC18HXgtvB24Lfwd+C48HjgufB54LrweuC78HvgvPB84L3wfeC+8H7gv/B/4MDwgODB8IHgwvCC4MPwg+DE8ITgxfCF4MbwhuDH8IfgyPCI4MnwieDK8Irgy/CL4MzwjODN8I3gzvCO4M/wj+DQ8JDg0fCR4NLwkuDT8JPg1PCU4NXwleDW8Jbg1/CX4NjwmODZ8Jng2vCa4Nvwm+Dc8Jzg3fCd4N7wnuDf8J/g4PCg4OHwoeDi8KLg4/Cj4OTwpODl8KXg5vCm4Ofwp+Do8Kjg6fCp4OrwquDr8Kvg7PCs4O3wreDu8K7g7/Cv4PDwsODx8LHg8vCy4PPws+D08LTg9fC14PbwtuD38Lfg+PC44PnwueD68Lrg+/C74PzwvOBA8b3gQfG+4ELxv+BD8cDgRPHB4EXxwuBG8cPgR/HE4EjxxeBJ8cbgSvHH4EvxyOBM8cngTfHK4E7xy+BP8czgUPHN4FHxzuBS8c/gU/HQ4FTx0eBV8dLgVvHT4Ffx1OBY8dXgWfHW4Frx1+Bb8djgXPHZ4F3x2uBe8dvgX/Hc4GDx3eBh8d7gYvHf4GPx4OBk8eHgZfHi4Gbx4+Bn8eTgaPHl4Gnx5uBq8efga/Ho4Gzx6eBt8ergbvHr4G/x7OBw8e3gcfHu4HLx7+Bz8fDgdPHx4HXx8uB28fPgd/H04Hjx9eB58fbgevH34Hvx+OB88fngffH64H7x++CA8fzggfH94ILx/uCD8f/ghPEA4YXxAeGG8QLhh/ED4YjxBOGJ8QXhivEG4YvxB+GM8QjhjfEJ4Y7xCuGP8QvhkPEM4ZHxDeGS8Q7hk/EP4ZTxEOGV8RHhlvES4ZfxE+GY8RThmfEV4ZrxFuGb8RfhnPEY4Z3xGeGe8Rrhn/Eb4aDxHOGh8R3hovEe4aPxH+Gk8SDhpfEh4abxIuGn8SPhqPEk4anxJeGq8Sbhq/En4azxKOGt8SnhrvEq4a/xK+Gw8SzhsfEt4bLxLuGz8S/htPEw4bXxMeG28TLht/Ez4bjxNOG58TXhuvE24bvxN+G88TjhvfE54b7xOuG/8TvhwPE84cHxPeHC8T7hw/E/4cTxQOHF8UHhxvFC4cfxQ+HI8UThyfFF4crxRuHL8UfhzPFI4c3xSeHO8Urhz/FL4dDxTOHR8U3h0vFO4dPxT+HU8VDh1fFR4dbxUuHX8VPh2PFU4dnxVeHa8Vbh2/FX4dzxWOHd8Vnh3vFa4d/xW+Hg8Vzh4fFd4eLxXuHj8V/h5PFg4eXxYeHm8WLh5/Fj4ejxZOHp8WXh6vFm4evxZ+Hs8Wjh7fFp4e7xauHv8Wvh8PFs4fHxbeHy8W7h8/Fv4fTxcOH18XHh9vFy4ffxc+H48XTh+fF14frxduH78Xfh/PF44UDyeeFB8nrhQvJ74UPyfOFE8n3hRfJ+4Ubyf+FH8oDhSPKB4UnyguFK8oPhS/KE4UzyheFN8obhTvKH4U/yiOFQ8onhUfKK4VLyi+FT8ozhVPKN4VXyjuFW8o/hV/KQ4VjykeFZ8pLhWvKT4VvylOFc8pXhXfKW4V7yl+Ff8pjhYPKZ4WHymuFi8pvhY/Kc4WTyneFl8p7hZvKf4WfyoOFo8qHhafKi4Wryo+Fr8qThbPKl4W3ypuFu8qfhb/Ko4XDyqeFx8qrhcvKr4XPyrOF08q3hdfKu4Xbyr+F38rDhePKx4XnysuF68rPhe/K04XzyteF98rbhfvK34YDyuOGB8rnhgvK64YPyu+GE8rzhhfK94YbyvuGH8r/hiPLA4YnyweGK8sLhi/LD4YzyxOGN8sXhjvLG4Y/yx+GQ8sjhkfLJ4ZLyyuGT8svhlPLM4ZXyzeGW8s7hl/LP4Zjy0OGZ8tHhmvLS4Zvy0+Gc8tThnfLV4Z7y1uGf8tfhoPLY4aHy2eGi8trho/Lb4aTy3OGl8t3hpvLe4afy3+Go8uDhqfLh4ary4uGr8uPhrPLk4a3y5eGu8ubhr/Ln4bDy6OGx8unhsvLq4bPy6+G08uzhtfLt4bby7uG38u/huPLw4bny8eG68vLhu/Lz4bzy9OG98vXhvvL24b/y9+HA8vjhwfL54cLy+uHD8vvhxPL84cXy/eHG8v7hx/L/4cjyAOLJ8gHiyvIC4svyA+LM8gTizfIF4s7yBuLP8gfi0PII4tHyCeLS8gri0/IL4tTyDOLV8g3i1vIO4tfyD+LY8hDi2fIR4tryEuLb8hPi3PIU4t3yFeLe8hbi3/IX4uDyGOLh8hni4vIa4uPyG+Lk8hzi5fId4ubyHuLn8h/i6PIg4unyIeLq8iLi6/Ij4uzyJOLt8iXi7vIm4u/yJ+Lw8iji8fIp4vLyKuLz8ivi9PIs4vXyLeL28i7i9/Iv4vjyMOL58jHi+vIy4vvyM+L88jTiQPM14kHzNuJC8zfiQ/M44kTzOeJF8zriRvM74kfzPOJI8z3iSfM+4krzP+JL80DiTPNB4k3zQuJO80PiT/NE4lDzReJR80biUvNH4lPzSOJU80niVfNK4lbzS+JX80ziWPNN4lnzTuJa80/iW/NQ4lzzUeJd81LiXvNT4l/zVOJg81XiYfNW4mLzV+Jj81jiZPNZ4mXzWuJm81viZ/Nc4mjzXeJp817iavNf4mvzYOJs82HibfNi4m7zY+Jv82TicPNl4nHzZuJy82fic/No4nTzaeJ182ridvNr4nfzbOJ4823iefNu4nrzb+J783DifPNx4n3zcuJ+83PigPN04oHzdeKC83big/N34oTzeOKF83nihvN64ofze+KI83ziifN94orzfuKL83/ijPOA4o3zgeKO84Lij/OD4pDzhOKR84XikvOG4pPzh+KU84jilfOJ4pbziuKX84vimPOM4pnzjeKa847im/OP4pzzkOKd85HinvOS4p/zk+Kg85TiofOV4qLzluKj85fipPOY4qXzmeKm85rip/Ob4qjznOKp853iqvOe4qvzn+Ks86DirfOh4q7zouKv86PisPOk4rHzpeKy86bis/On4rTzqOK186nitvOq4rfzq+K486ziufOt4rrzruK786/ivPOw4r3zseK+87Liv/Oz4sDztOLB87XiwvO24sPzt+LE87jixfO54sbzuuLH87viyPO84snzveLK877iy/O/4szzwOLN88HizvPC4s/zw+LQ88Ti0fPF4tLzxuLT88fi1PPI4tXzyeLW88ri1/PL4tjzzOLZ883i2vPO4tvzz+Lc89Di3fPR4t7z0uLf89Pi4PPU4uHz1eLi89bi4/PX4uTz2OLl89ni5vPa4ufz2+Lo89zi6fPd4urz3uLr89/i7PPg4u3z4eLu8+Li7/Pj4vDz5OLx8+Xi8vPm4vPz5+L08+ji9fPp4vbz6uL38+vi+PPs4vnz7eL68+7i+/Pv4vzz8OJA9PHiQfTy4kL08+JD9PTiRPT14kX09uJG9PfiR/T44kj0+eJJ9PriSvT74kv0/OJM9P3iTfT+4k70/+JP9ADjUPQB41H0AuNS9APjU/QE41T0BeNV9AbjVvQH41f0CONY9AnjWfQK41r0C+Nb9AzjXPQN4130DuNe9A/jX/QQ42D0EeNh9BLjYvQT42P0FONk9BXjZfQW42b0F+Nn9BjjaPQZ42n0GuNq9Bvja/Qc42z0HeNt9B7jbvQf42/0IONw9CHjcfQi43L0I+Nz9CTjdPQl43X0JuN29Cfjd/Qo43j0KeN59CrjevQr43v0LON89C3jffQu4370L+OA9DDjgfQx44L0MuOD9DPjhPQ044X0NeOG9Dbjh/Q344j0OOOJ9DnjivQ644v0O+OM9DzjjfQ94470PuOP9D/jkPRA45H0QeOS9ELjk/RD45T0ROOV9EXjlvRG45f0R+OY9EjjmfRJ45r0SuOb9EvjnPRM4530TeOe9E7jn/RP46D0UOOh9FHjovRS46P0U+Ok9FTjpfRV46b0VuOn9FfjqPRY46n0WeOq9Frjq/Rb46z0XOOt9F3jrvRe46/0X+Ow9GDjsfRh47L0YuOz9GPjtPRk47X0ZeO29Gbjt/Rn47j0aOO59GnjuvRq47v0a+O89GzjvfRt4770buO/9G/jwPRw48H0cePC9HLjw/Rz48T0dOPF9HXjxvR248f0d+PI9HjjyfR548r0euPL9HvjzPR84830fePO9H7jz/R/49D0gOPR9IHj0vSC49P0g+PU9ITj1fSF49b0huPX9Ifj2PSI49n0iePa9Irj2/SL49z0jOPd9I3j3vSO49/0j+Pg9JDj4fSR4+L0kuPj9JPj5PSU4+X0lePm9Jbj5/SX4+j0mOPp9Jnj6vSa4+v0m+Ps9Jzj7fSd4+70nuPv9J/j8PSg4/H0oePy9KLj8/Sj4/T0pOP19KXj9vSm4/f0p+P49Kjj+fSp4/r0quP79Kvj/PSs40D1reNB9a7jQvWv40P1sONE9bHjRfWy40b1s+NH9bTjSPW140n1tuNK9bfjS/W440z1ueNN9brjTvW740/1vONQ9b3jUfW+41L1v+NT9cDjVPXB41X1wuNW9cPjV/XE41j1xeNZ9cbjWvXH41v1yONc9cnjXfXK4171y+Nf9czjYPXN42H1zuNi9c/jY/XQ42T10eNl9dLjZvXT42f11ONo9dXjafXW42r11+Nr9djjbPXZ42312uNu9dvjb/Xc43D13eNx9d7jcvXf43P14ON09eHjdfXi43b14+N39eTjePXl43n15uN69efje/Xo43z16eN99erjfvXr44D17OOB9e3jgvXu44P17+OE9fDjhfXx44b18uOH9fPjiPX044n19eOK9fbji/X344z1+OON9fnjjvX644/1++OQ9fzjkfX945L1/uOT9f/jlPUA5JX1AeSW9QLkl/UD5Jj1BOSZ9QXkmvUG5Jv1B+Sc9QjknfUJ5J71CuSf9QvkoPUM5KH1DeSi9Q7ko/UP5KT1EOSl9RHkpvUS5Kf1E+So9RTkqfUV5Kr1FuSr9RfkrPUY5K31GeSu9Rrkr/Ub5LD1HOSx9R3ksvUe5LP1H+S09SDktfUh5Lb1IuS39SPkuPUk5Ln1JeS69Sbku/Un5Lz1KOS99SnkvvUq5L/1K+TA9SzkwfUt5ML1LuTD9S/kxPUw5MX1MeTG9TLkx/Uz5Mj1NOTJ9TXkyvU25Mv1N+TM9TjkzfU55M71OuTP9Tvk0PU85NH1PeTS9T7k0/U/5NT1QOTV9UHk1vVC5Nf1Q+TY9UTk2fVF5Nr1RuTb9Ufk3PVI5N31SeTe9Urk3/VL5OD1TOTh9U3k4vVO5OP1T+Tk9VDk5fVR5Ob1UuTn9VPk6PVU5On1VeTq9Vbk6/VX5Oz1WOTt9Vnk7vVa5O/1W+Tw9Vzk8fVd5PL1XuTz9V/k9PVg5PX1YeT29WLk9/Vj5Pj1ZOT59WXk+vVm5Pv1Z+T89WjkQPZp5EH2auRC9mvkQ/Zs5ET2beRF9m7kRvZv5Ef2cORI9nHkSfZy5Er2c+RL9nTkTPZ15E32duRO9nfkT/Z45FD2eeRR9nrkUvZ75FP2fORU9n3kVfZ+5Fb2f+RX9oDkWPaB5Fn2guRa9oPkW/aE5Fz2heRd9obkXvaH5F/2iORg9onkYfaK5GL2i+Rj9ozkZPaN5GX2juRm9o/kZ/aQ5Gj2keRp9pLkavaT5Gv2lORs9pXkbfaW5G72l+Rv9pjkcPaZ5HH2muRy9pvkc/ac5HT2neR19p7kdvaf5Hf2oOR49qHkefai5Hr2o+R79qTkfPal5H32puR+9qfkgPao5IH2qeSC9qrkg/ar5IT2rOSF9q3khvau5If2r+SI9rDkifax5Ir2suSL9rPkjPa05I32teSO9rbkj/a35JD2uOSR9rnkkva65JP2u+SU9rzklfa95Jb2vuSX9r/kmPbA5Jn2weSa9sLkm/bD5Jz2xOSd9sXknvbG5J/2x+Sg9sjkofbJ5KL2yuSj9svkpPbM5KX2zeSm9s7kp/bP5Kj20OSp9tHkqvbS5Kv20+Ss9tTkrfbV5K721uSv9tfksPbY5LH22eSy9trks/bb5LT23OS19t3ktvbe5Lf23+S49uDkufbh5Lr24uS79uPkvPbk5L325eS+9ubkv/bn5MD26OTB9unkwvbq5MP26+TE9uzkxfbt5Mb27uTH9u/kyPbw5Mn28eTK9vLky/bz5Mz29OTN9vXkzvb25M/29+TQ9vjk0fb55NL2+uTT9vvk1Pb85NX2/eTW9v7k1/b/5Nj2AOXZ9gHl2vYC5dv2A+Xc9gTl3fYF5d72BuXf9gfl4PYI5eH2CeXi9grl4/YL5eT2DOXl9g3l5vYO5ef2D+Xo9hDl6fYR5er2EuXr9hPl7PYU5e32FeXu9hbl7/YX5fD2GOXx9hnl8vYa5fP2G+X09hzl9fYd5fb2HuX39h/l+PYg5fn2IeX69iLl+/Yj5fz2JOVA9yXlQfcm5UL3J+VD9yjlRPcp5UX3KuVG9yvlR/cs5Uj3LeVJ9y7lSvcv5Uv3MOVM9zHlTfcy5U73M+VP9zTlUPc15VH3NuVS9zflU/c45VT3OeVV9zrlVvc75Vf3POVY9z3lWfc+5Vr3P+Vb90DlXPdB5V33QuVe90PlX/dE5WD3ReVh90blYvdH5WP3SOVk90nlZfdK5Wb3S+Vn90zlaPdN5Wn3TuVq90/la/dQ5Wz3UeVt91LlbvdT5W/3VOVw91XlcfdW5XL3V+Vz91jldPdZ5XX3WuV291vld/dc5Xj3XeV5917levdf5Xv3YOV892Hlffdi5X73Y+WA92Tlgfdl5YL3ZuWD92flhPdo5YX3aeWG92rlh/dr5Yj3bOWJ923livdu5Yv3b+WM93Dljfdx5Y73cuWP93PlkPd05ZH3deWS93blk/d35ZT3eOWV93nllvd65Zf3e+WY93zlmfd95Zr3fuWb93/lnPeA5Z33geWe94Lln/eD5aD3hOWh94XloveG5aP3h+Wk94jlpfeJ5ab3iuWn94vlqPeM5an3jeWq947lq/eP5az3kOWt95HlrveS5a/3k+Ww95TlsfeV5bL3luWz95fltPeY5bX3meW295rlt/eb5bj3nOW5953luvee5bv3n+W896Dlvfeh5b73ouW/96PlwPek5cH3peXC96blw/en5cT3qOXF96nlxveq5cf3q+XI96zlyfet5cr3ruXL96/lzPew5c33seXO97Llz/ez5dD3tOXR97Xl0ve25dP3t+XU97jl1fe55db3uuXX97vl2Pe85dn3veXa977l2/e/5dz3wOXd98Hl3vfC5d/3w+Xg98Tl4ffF5eL3xuXj98fl5PfI5eX3yeXm98rl5/fL5ej3zOXp983l6vfO5ev3z+Xs99Dl7ffR5e730uXv99Pl8PfU5fH31eXy99bl8/fX5fT32OX199nl9vfa5ff32+X499zl+ffd5fr33uX799/l/Pfg5UD44eVB+OLlQvjj5UP45OVE+OXlRfjm5Ub45+VH+OjlSPjp5Un46uVK+OvlS/js5Uz47eVN+O7lTvjv5U/48OVQ+PHlUfjy5VL48+VT+PTlVPj15VX49uVW+PflV/j45Vj4+eVZ+PrlWvj75Vv4/OVc+P3lXfj+5V74/+Vf+ADmYPgB5mH4AuZi+APmY/gE5mT4BeZl+AbmZvgH5mf4COZo+AnmafgK5mr4C+Zr+AzmbPgN5m34DuZu+A/mb/gQ5nD4EeZx+BLmcvgT5nP4FOZ0+BXmdfgW5nb4F+Z3+BjmePgZ5nn4GuZ6+Bvme/gc5nz4HeZ9+B7mfvgf5oD4IOaB+CHmgvgi5oP4I+aE+CTmhfgl5ob4JuaH+CfmiPgo5on4KeaK+Crmi/gr5oz4LOaN+C3mjvgu5o/4L+aQ+DDmkfgx5pL4MuaT+DPmlPg05pX4NeaW+Dbml/g35pj4OOaZ+Dnmmvg65pv4O+ac+Dzmnfg95p74Puaf+D/moPhA5qH4Qeai+ELmo/hD5qT4ROal+EXmpvhG5qf4R+ao+EjmqfhJ5qr4Suar+EvmrPhM5q34Teau+E7mr/hP5rD4UOax+FHmsvhS5rP4U+a0+FTmtfhV5rb4Vua3+FfmuPhY5rn4Wea6+Frmu/hb5rz4XOa9+F3mvvhe5r/4X+bA+GDmwfhh5sL4YubD+GPmxPhk5sX4ZebG+Gbmx/hn5sj4aObJ+Gnmyvhq5sv4a+bM+Gzmzfht5s74bubP+G/m0Phw5tH4cebS+HLm0/hz5tT4dObV+HXm1vh25tf4d+bY+Hjm2fh55tr4eubb+Hvm3Ph85t34febe+H7m3/h/5uD4gObh+IHm4viC5uP4g+bk+ITm5fiF5ub4hubn+Ifm6PiI5un4iebq+Irm6/iL5uz4jObt+I3m7viO5u/4j+bw+JDm8fiR5vL4kubz+JPm9PiU5vX4leb2+Jbm9/iX5vj4mOb5+Jnm+via5vv4m+b8+JzmQPmd5kH5nuZC+Z/mQ/mg5kT5oeZF+aLmRvmj5kf5pOZI+aXmSfmm5kr5p+ZL+ajmTPmp5k35quZO+avmT/ms5lD5reZR+a7mUvmv5lP5sOZU+bHmVfmy5lb5s+ZX+bTmWPm15ln5tuZa+bfmW/m45lz5ueZd+brmXvm75l/5vOZg+b3mYfm+5mL5v+Zj+cDmZPnB5mX5wuZm+cPmZ/nE5mj5xeZp+cbmavnH5mv5yOZs+cnmbfnK5m75y+Zv+czmcPnN5nH5zuZy+c/mc/nQ5nT50eZ1+dLmdvnT5nf51OZ4+dXmefnW5nr51+Z7+djmfPnZ5n352uZ++dvmgPnc5oH53eaC+d7mg/nf5oT54OaF+eHmhvni5of54+aI+eTmifnl5or55uaL+efmjPno5o356eaO+ermj/nr5pD57OaR+e3mkvnu5pP57+aU+fDmlfnx5pb58uaX+fPmmPn05pn59eaa+fbmm/n35pz5+Oad+fnmnvn65p/5++ag+fzmofn95qL5/uaj+f/mpPkA56X5Aeem+QLnp/kD56j5BOep+QXnqvkG56v5B+es+QjnrfkJ5675Cuev+QvnsPkM57H5Deey+Q7ns/kP57T5EOe1+RHntvkS57f5E+e4+RTnufkV57r5Fue7+RfnvPkY5735Gee++Rrnv/kb58D5HOfB+R3nwvke58P5H+fE+SDnxfkh58b5IufH+SPnyPkk58n5JefK+Sbny/kn58z5KOfN+Snnzvkq58/5K+fQ+Szn0fkt59L5LufT+S/n1Pkw59X5MefW+TLn1/kz59j5NOfZ+TXn2vk259v5N+fc+Tjn3fk55975Ouff+Tvn4Pk85+H5Pefi+T7n4/k/5+T5QOfl+UHn5vlC5+f5Q+fo+UTn6flF5+r5Rufr+Ufn7PlI5+35Sefu+Urn7/lL5/D5TOfx+U3n8vlO5/P5T+f0+VDn9flR5/b5Uuf3+VPn+PlU5/n5Vef6+Vbn+/lX5/z58PigAPH4/QDy+P4A8/j/ACn5xO3c+c3uDvpz7Q/6fu0Q+oDtEfqV7RL6vO0T+sztFPrO7RX6+e0W+kLuF/pZ7hj6Ye4Z+mLuGvpj7hv6Ze4c+mnuHfps7h76de4f+oHuIPqD7iH6hO4i+o3uI/qV7iT6l+4l+pjuJvqb7if6t+4o+r7uKfrO7ir62u4r+tvuLPrd7i366u4B/0mBAv/87gP/lIEE/5CBBf+TgQb/lYEH//vuCP9pgQn/aoEK/5aBC/97gQz/Q4EN/3yBDv9EgQ//XoEQ/0+CEf9QghL/UYIT/1KCFP9TghX/VIIW/1WCF/9Wghj/V4IZ/1iCGv9GgRv/R4Ec/4OBHf+BgR7/hIEf/0iBIP+XgSH/YIIi/2GCI/9igiT/Y4Il/2SCJv9lgif/ZoIo/2eCKf9ogir/aYIr/2qCLP9rgi3/bIIu/22CL/9ugjD/b4Ix/3CCMv9xgjP/coI0/3OCNf90gjb/dYI3/3aCOP93gjn/eII6/3mCO/9tgTz/X4E9/26BPv9PgT//UYFA/02BQf+BgkL/goJD/4OCRP+EgkX/hYJG/4aCR/+Hgkj/iIJJ/4mCSv+Kgkv/i4JM/4yCTf+Ngk7/joJP/4+CUP+QglH/kYJS/5KCU/+TglT/lIJV/5WCVv+Wglf/l4JY/5iCWf+Zglr/moJb/2+BXP9igV3/cIFe/2CBYf+hAGL/ogBj/6MAZP+kAGX/pQBm/6YAZ/+nAGj/qABp/6kAav+qAGv/qwBs/6wAbf+tAG7/rgBv/68AcP+wAHH/sQBy/7IAc/+zAHT/tAB1/7UAdv+2AHf/twB4/7gAef+5AHr/ugB7/7sAfP+8AH3/vQB+/74Af/+/AID/wACB/8EAgv/CAIP/wwCE/8QAhf/FAIb/xgCH/8cAiP/IAIn/yQCK/8oAi//LAIz/zACN/80Ajv/OAI//zwCQ/9AAkf/RAJL/0gCT/9MAlP/UAJX/1QCW/9YAl//XAJj/2ACZ/9kAmv/aAJv/2wCc/9wAnf/dAJ7/3gCf/98A4P+RgeH/koHi/8qB4/9QgeT/+u7l/4+B'
local cp932
function Core.encode_name(name,encoding)
 if name:find('%z') then error('名前にNUL文字は使用できません。',0) end
 if encoding=='UTF-8' then
  if not utf8.len(name) then error('名前が正しいUTF-8ではありません。',0) end
  return name
 end
 if not cp932 then
  cp932={};local raw=Core.unbase64(CP932_TABLE)
  for i=1,#raw,4 do local u,v=string.unpack('<I2I2',raw,i);cp932[u]=v<256 and string.char(v) or string.char(v>>8,v&255) end
 end
 local out={}
 for _,u in utf8.codes(name) do
  if not cp932[u] then error('CP932に変換できない文字があります: '..utf8.char(u)..' — 名前を変更するかUTF-8を選んでください。',0) end
  out[#out+1]=cp932[u]
 end
 return table.concat(out)
end
local function u32(n) assert(finite(n) and n>=0 and n<=0xffffffff and n%1==0,'Invalid uint32');return string.pack('<I4',n) end
function Core.chunk(id,data) return id..u32(#data)..data..(#data%2==1 and '\0' or '') end
function Core.plan(rows,start,ending,sr,options)
 options=options or {};assert(finite(start) and finite(ending) and ending>start,'書き出し範囲を指定してください。')
 assert(finite(sr) and sr>=8000 and sr<=384000 and sr%1==0,'サンプルレートが不正です。')
 local first,last=floor(start*sr+.5),floor(ending*sr+.5)
 local p={start=first/sr,finish=last/sr,requested_start=start,requested_finish=ending,sr=sr,frames=last-first,entries={},outside=0,clipped=0,omitted=0,encoding=options.encoding or 'UTF-8'}
 assert(p.frames>0 and p.frames<=0xffffffff,'書き出し範囲がWAVの上限を超えています。')
 local function sample(t) return floor(t*sr+.5)-first end
 for _,row in ipairs(rows) do
  assert(finite(row.start) and finite(row.finish),'リージョン位置が不正です。')
  local isr=row.isr;local included=isr and row.finish>start and row.start<ending or not isr and row.start>=start and row.start<=ending
  if included then
   assert(row.kind~='invalid','不明なBLT接頭辞: '..row.raw)
   assert(row.kind=='marker' or row.kind=='region' or row.kind=='sustain','未対応の区間種類です。')
   local enabled=row.kind=='marker' and options.embed_markers~=false
    or row.kind=='region' and options.embed_regions~=false
    or row.kind=='sustain' and options.embed_loop_region~=false
   if options.exclude_selected_region and row.kind=='region' and row.key==options.selected_key then enabled=false end
   if not enabled then p.omitted=p.omitted+1;goto continue end
   local s,e=sample(row.start),sample(row.finish)
   if row.kind=='sustain' then
    assert(row.start>=start and row.finish<=ending,'ループが書き出し範囲をまたいでいます: '..row.name)
    assert(not p.sustain,'サステインループは1ファイルにつき1つまでです。')
   elseif isr and (s<0 or e>p.frames) then p.clipped=p.clipped+1 end
   s=clamp(s,0,p.frames);e=clamp(e,0,p.frames)
   assert(not isr or e>s,'1サンプル未満のリージョンがあります: '..row.name)
   local encoded=row.kind=='sustain' and '' or Core.encode_name(row.name,p.encoding)
   local entry={kind=row.kind,name=row.name,start=s,finish=e,encoded=encoded,id=row.id,key=row.key}
   assert(#entry.encoded<=65535,'名前が長すぎます。')
   p.entries[#p.entries+1]=entry
   if row.kind=='sustain' then p.sustain=entry end
  else p.outside=p.outside+1 end
  ::continue::
 end
 return p
end
function Core.single_render_wav_target(got,targets)
 assert(got,'REAPERから出力先を取得できません。')
 local wavs={}
 for path in tostring(targets or ''):gmatch('[^;]+') do
  path=path:match('^%s*(.-)%s*$')
  if path:lower():match('%.wav$') then wavs[#wavs+1]=path end
 end
 assert(#wavs>0,'REAPER本体の設定からWAV出力先を取得できません。出力形式をWAVにしてください。')
 assert(#wavs==1,'REAPER本体の設定から複数のWAV出力先が返されました。セカンダリ出力やステム出力を無効にしてください。')
 return wavs[1]
end
function Core.batch_output_name(name,index,count)
 assert(type(name)=='string' and name~='' and finite(index) and finite(count) and index>=1 and index<=count,'一括出力名の指定が不正です。')
 return count>1 and (name..string.format('_%03d',index)) or name
end
function Core.manual_render_pattern(value)
 local name=tostring(value or ''):gsub('%.[Ww][Aa][Vv]$','')
 if name=='' or name=='.' or name=='..' or name:find('[<>:"/\\|?*%c;]') or name:match('[%. ]$') then return nil end
 return name
end
function Core.reserved_filename(name)
 local stem=(tostring(name or ''):match('^[^.]+') or ''):upper()
 return stem=='CON' or stem=='PRN' or stem=='AUX' or stem=='NUL' or stem:match('^COM[1-9]$') or stem:match('^LPT[1-9]$')
end
function Core.metadata(p)
 local cues,adtl,loops={},{},{}
 local cueid=1
 for _,e in ipairs(p.entries) do
  if e.kind=='marker' or e.kind=='region' then
   -- Avoid a label consisting solely of its NUL terminator.
   local name=e.encoded~='' and e.encoded or ((e.kind=='marker' and 'Marker_' or 'Region_')..cueid)
   cues[#cues+1]=u32(cueid)..u32(e.start)..'data'..u32(0)..u32(0)..u32(e.start)
   adtl[#adtl+1]=Core.chunk('labl',u32(cueid)..name..'\0')
   if e.kind=='region' then
    -- Sound Forge's ordinary region: cue start + ltxt length, purpose "rgn ".
    adtl[#adtl+1]=Core.chunk('ltxt',u32(cueid)..u32(e.finish-e.start)..'rgn '..string.pack('<I2I2I2I2',0,0,0,p.encoding=='UTF-8' and 65001 or 932)..name..'\0')
   end
   cueid=cueid+1
  end
 end
 -- A play count of 0 means infinite repetition in the WAV smpl chunk.
 local e=p.sustain
 if e then loops[1]=u32(0)..u32(0)..u32(e.start)..u32(e.finish-1)..u32(0)..u32(0) end
 local out={}
 if #cues>0 then out[#out+1]=Core.chunk('cue ',u32(#cues)..table.concat(cues));out[#out+1]=Core.chunk('LIST','adtl'..table.concat(adtl)) end
 if #loops>0 then out[#out+1]=Core.chunk('smpl',u32(0)..u32(0)..u32(floor(1e9/p.sr+.5))..u32(60)..u32(0)..u32(0)..u32(0)..u32(#loops)..u32(0)..table.concat(loops)) end
 local blob=table.concat(out);assert(#blob<=Core.MAX_METADATA,'リージョン情報が大きすぎます。');return blob
end
local function read_exact(f,n) local s=f:read(n);assert(s and #s==n,'WAVが途中で切れています。');return s end
function Core.scan(path,options)
 local audio_only=options and options.audio_only
 local f,err=io.open(path,'rb');assert(f,err)
 local ok,result=xpcall(function()
  local size=assert(f:seek('end'));assert(f:seek('set',0));local header=read_exact(f,12)
  assert(header:sub(1,4)=='RIFF' and header:sub(9,12)=='WAVE','通常のRIFF/WAVのみ対応しています（RF64/Wave64非対応）。')
  local declared_size=string.unpack('<I4',header,5)+8
  assert(audio_only or declared_size==size,'WAVサイズが一致しません。レンダー未完了または破損ファイルです。')
  local w={size=size,declared_size=declared_size,chunks={},metadata={}};local offset=12
  while offset<size do
   assert(offset+8<=size,'WAVチャンクヘッダーが不正です。');assert(f:seek('set',offset))
   local h=read_exact(f,8);local id=h:sub(1,4);local n=string.unpack('<I4',h,5)
   -- Source-audio reading needs a complete payload, not the optional final pad.
   local pad=audio_only and id=='data' and 0 or n%2
   assert(offset+8+n+pad<=size,'WAVチャンク長が不正です。音声データが途中で切れている可能性があります。')
   local c={id=id,offset=offset,size=n,total=8+n+n%2}
   if id=='LIST' and n>=4 then c.list=read_exact(f,4) end
   if id=='fmt ' then
    assert(not w.sr and n>=16 and n<=4096,'WAV fmtが不正です。');assert(f:seek('set',offset+8))
    local fmt=read_exact(f,n);local tag,ch,sr,rate,align,bits=string.unpack('<I2I2I4I4I2I2',fmt)
    if tag==65534 then
     assert(n>=40 and string.unpack('<I2',fmt,17)>=22,'WAVEFORMATEXTENSIBLEが不正です。')
     assert(fmt:sub(29,40)=='\0\0\16\0\128\0\0\170\0\56\155\113','未対応のWAVサブフォーマットです。')
     tag=string.unpack('<I4',fmt,25)
    end
    assert((tag==1 and (bits==16 or bits==24 or bits==32)) or (tag==3 and (bits==32 or bits==64)),'PCM / IEEE float WAVのみ対応しています。')
    assert(ch>=1 and ch<=64 and sr>0 and align==ch*bits//8 and rate==sr*align,'WAV音声フォーマットが不正です。')
    w.sr,w.channels,w.bits,w.align,w.tag,w.fmt=sr,ch,bits,align,tag,fmt
   elseif id=='data' then assert(not w.data,'複数dataチャンクには対応していません。');w.data=c end
   c.remove=id=='cue ' or id=='smpl' or id=='plst' or (id=='LIST' and c.list=='adtl')
   if c.remove and not audio_only then
    assert(n<=Core.MAX_METADATA,'既存のWAVメタデータが大きすぎます。');assert(f:seek('set',offset));w.metadata[#w.metadata+1]=read_exact(f,c.total)
   end
   w.chunks[#w.chunks+1]=c;offset=offset+c.total
   -- Existing files may contain trailing application data or stale RIFF sizes.
   -- Do not interpret that tail when only the verified audio payload is needed.
   if audio_only and w.sr and w.data then break end
  end
  assert(w.sr and w.data and w.data.size%w.align==0,'音声データがありません、またはサンプル境界が不正です。')
  w.frames=w.data.size//w.align;return w
 end,debug.traceback)
 f:close();if not ok then error(result,0) end;return result
end
function Core.exists(path) local f=io.open(path,'rb');if f then f:close();return true end;return false end
Core.PENDING_FILE_DELETE={};Core.PENDING_FILE_DELETE_LIMIT=32;Core.pending_file_retry_at=0
function Core.queue_file_delete(path)
 if not path or not Core.exists(path) or Core.PENDING_FILE_DELETE[path] then return end
 local count,oldest_path,oldest_time=0,nil,math.huge
 for pending_path,queued_at in pairs(Core.PENDING_FILE_DELETE) do
  count=count+1
  if queued_at<oldest_time then oldest_path,oldest_time=pending_path,queued_at end
 end
 if count>=Core.PENDING_FILE_DELETE_LIMIT and oldest_path then Core.PENDING_FILE_DELETE[oldest_path]=nil end
 Core.PENDING_FILE_DELETE[path]=R.time_precise()
end
function Core.retry_file_deletes(force)
 local now=R.time_precise()
 if not force and now<Core.pending_file_retry_at then return end
 Core.pending_file_retry_at=now+2
 for path in pairs(Core.PENDING_FILE_DELETE) do
  local called,removed=pcall(os.remove,path)
  if not Core.exists(path) or (called and removed) then Core.PENDING_FILE_DELETE[path]=nil end
 end
end
function Core.unique(path)
 if not Core.exists(path) then return path end
 local base=path:gsub('%.[Ww][Aa][Vv]$','')
 for i=1,9999 do local p=base..string.format('_%03d.wav',i);if not Core.exists(p) then return p end end
 error('出力ファイル名を確保できません。',0)
end
function Core.render_window(p)
 local first=floor(p.start*p.sr+.5);local guard=math.ceil(.05*p.sr)
 local pre=min(guard,max(0,first))
 return {start=(first-pre)/p.sr,finish=(first+p.frames+guard)/p.sr,
  frames=pre+p.frames+guard,pre=pre}
end
function Core.copy_start(source,target,p)
 assert(source~=target and not Core.exists(target),'出力先は新しいWAVファイルを指定してください。')
 local wav=Core.scan(source)
 assert(wav.sr==p.sr,'レンダーのサンプルレートが一致しません。')
 local window=p.render_window or {frames=p.frames,pre=0}
 assert(wav.frames==window.frames,string.format('レンダーの長さが一致しません。\n指定範囲: %.9f ～ %.9f 秒\n予定: %d samples (%.9f 秒)\n実際: %d samples (%.9f 秒)\n差: %+d samples / %+.6f ms\nサンプルレート: %d Hz',window.start or p.start,window.finish or p.finish,window.frames,window.frames/p.sr,wav.frames,wav.frames/wav.sr,wav.frames-window.frames,(wav.frames-window.frames)*1000/p.sr,p.sr))
 -- Never publish a WAV whose audio length differs from its sample-based plan.
 for _,e in ipairs(p.entries) do assert(e.start<=wav.frames and e.finish<=wav.frames,'メタデータが実際のWAV終端を超えています。') end
 local blob=Core.metadata(p);local keep={};local size=12+#blob
 local function add(c) keep[#keep+1]=c;size=size+c.total end
 local function bytes(data) add({bytes=data,total=#data}) end
 for _,c in ipairs(wav.chunks) do
  if c.id=='data' then
   local n=p.frames*wav.align
   bytes('data'..u32(n))
   add({offset=c.offset+8+window.pre*wav.align,total=n})
   if n%2==1 then bytes('\0') end
  elseif not c.remove and c.id~='PEAK' then
   if c.id=='fact' or (c.id=='bext' and window.pre>0) then
    local f=assert(io.open(source,'rb'));assert(f:seek('set',c.offset));local raw=read_exact(f,c.total);f:close()
    if c.id=='fact' and c.size>=4 then raw=raw:sub(1,8)..u32(p.frames)..raw:sub(13)
    elseif c.id=='bext' and c.size>=346 then
     local lo,hi=string.unpack('<I4I4',raw,347)
     local sum=lo+window.pre;local carry=sum//4294967296
     assert(hi+carry<=0xffffffff,'BWF時刻が上限を超えています。')
     raw=raw:sub(1,346)..u32(sum%4294967296)..u32(hi+carry)..raw:sub(355)
    end
    bytes(raw)
   else add(c) end
  end
 end
 assert(size-8<=0xffffffff,'4 GiBを超えるWAVには対応していません。')
 local temp=target..'.blt-part';assert(not Core.exists(temp),'作業ファイルが存在します: '..temp)
 local input=assert(io.open(source,'rb'));local output,err=io.open(temp,'wb')
 if not output then input:close();error(err,0) end
 local j={input=input,output=output,source=source,target=target,temp=temp,wav=wav,blob=blob,chunks=keep,index=1,within=0,copied=0,size=size,plan=p}
 local ok,msg=output:write('RIFF'..u32(size-8)..'WAVE')
 if not ok then Core.copy_abort(j);error(msg,0) end
 return j
end
function Core.copy_abort(j)
 if not j then return end
 if j.input then j.input:close();j.input=nil end
 if j.output then j.output:close();j.output=nil end
 if j.temp then
  local path=j.temp;j.temp=nil
  local called,removed=pcall(os.remove,path)
  if Core.exists(path) and not (called and removed) then Core.queue_file_delete(path) end
 end
end
function Core.copy_step(j)
 local c=j.chunks[j.index]
 if c then
  local n=min(1024*1024,c.total-j.within)
  if c.bytes then assert(j.output:write(c.bytes:sub(j.within+1,j.within+n)))
  else assert(j.input:seek('set',c.offset+j.within));assert(j.output:write(read_exact(j.input,n))) end
  j.within=j.within+n;j.copied=j.copied+n
  if j.within==c.total then j.index=j.index+1;j.within=0 end
  return false
 end
 assert(j.output:write(j.blob));assert(j.output:flush());assert(j.output:close());j.output=nil;j.input:close();j.input=nil
 local check=Core.scan(j.temp)
 assert(check.frames==j.plan.frames and check.sr==j.plan.sr and table.concat(check.metadata)==j.blob,'書き込み検証に失敗しました。')
 assert(not Core.exists(j.target),'出力先が別の処理で作成されました。再実行してください。')
 assert(os.rename(j.temp,j.target));j.temp=nil;return true
end
-- No hard-coded project format preferences are left behind after rendering.
Core.render_numbers={'RENDER_SETTINGS','RENDER_BOUNDSFLAG','RENDER_STARTPOS','RENDER_ENDPOS','RENDER_TAILFLAG','RENDER_ADDTOPROJ','RENDER_SRATE','RENDER_CHANNELS','RENDER_NORMALIZE','RENDER_DITHER'}
Core.render_strings={'RENDER_FILE','RENDER_PATTERN','RENDER_FORMAT','RENDER_FORMAT2'}
function Core.project_region_selection(project)
 assert(type(R.GetNumRegionsOrMarkers)=='function' and type(R.GetRegionOrMarker)=='function'
  and type(R.GetRegionOrMarkerInfo_Value)=='function','REAPERのリージョン選択APIを利用できません。REAPERを更新してください。')
 local selected={}
 for i=0,R.GetNumRegionsOrMarkers(project)-1 do
  local ptr=R.GetRegionOrMarker(project,i,'')
  if ptr and R.GetRegionOrMarkerInfo_Value(project,ptr,'B_ISREGION')~=0 then
   local id=R.GetRegionOrMarkerInfo_Value(project,ptr,'I_NUMBER')
   if finite(id) and R.GetRegionOrMarkerInfo_Value(project,ptr,'B_UISEL')~=0 then selected[floor(id+.5)]=true end
  end
 end
 return selected
end
function Core.set_project_region_selection(project,selected)
 assert(type(R.SetRegionOrMarkerInfo_Value)=='function','REAPERのリージョン選択APIを利用できません。REAPERを更新してください。')
 local found={}
 for i=0,R.GetNumRegionsOrMarkers(project)-1 do
  local ptr=R.GetRegionOrMarker(project,i,'')
  if ptr and R.GetRegionOrMarkerInfo_Value(project,ptr,'B_ISREGION')~=0 then
   local value=R.GetRegionOrMarkerInfo_Value(project,ptr,'I_NUMBER')
   if finite(value) then
    local id=floor(value+.5);local wanted=selected[id] and 1 or 0
    R.SetRegionOrMarkerInfo_Value(project,ptr,'B_UISEL',wanted)
    assert((R.GetRegionOrMarkerInfo_Value(project,ptr,'B_UISEL')~=0)==(wanted~=0),'レンダー対象リージョンの選択を変更できません。')
    if selected[id] then found[id]=true end
   end
  end
 end
 for id in pairs(selected) do assert(found[id],'レンダー対象リージョンが見つかりません: '..id) end
 if type(R.UpdateArrange)=='function' then R.UpdateArrange() end
end
function Core.snapshot_render(project)
 local s={project=project,n={},s={}}
 s.selection={R.GetSet_LoopTimeRange2(project,false,false,0,0,false)}
 s.loop={R.GetSet_LoopTimeRange2(project,false,true,0,0,false)}
 s.regions=Core.project_region_selection(project)
 for _,key in ipairs(Core.render_numbers) do s.n[key]=R.GetSetProjectInfo(project,key,0,false) end
 for _,key in ipairs(Core.render_strings) do local ok,v=R.GetSetProjectInfo_String(project,key,'',false);assert(ok,'レンダー設定を取得できません: '..key);s.s[key]=v end
 return s
end
function Core.restore_render(s)
 if not s then return end
 if R.ValidatePtr and not R.ValidatePtr(s.project,'ReaProject*') then return end
 for _,key in ipairs(Core.render_numbers) do R.GetSetProjectInfo(s.project,key,s.n[key],true) end
 for _,key in ipairs(Core.render_strings) do R.GetSetProjectInfo_String(s.project,key,s.s[key],true) end
 -- Work around REAPER sink configuration order sensitivity.
 R.GetSetProjectInfo_String(s.project,'RENDER_FORMAT',s.s.RENDER_FORMAT,true)
 if s.regions then Core.set_project_region_selection(s.project,s.regions) end
 if s.selection_changed then
  R.GetSet_LoopTimeRange2(s.project,true,false,s.selection[1],s.selection[2],false)
  R.GetSet_LoopTimeRange2(s.project,true,true,s.loop[1],s.loop[2],false)
 end
end
function Core.configure_render(project,p,dir,pattern,bits,channels,resolve_region_name)
 assert(bits==16 or bits==24 or bits==32,'ビット深度が不正です。')
 assert(finite(channels) and channels>=1 and channels<=64 and channels%1==0,'チャンネル数が不正です。')
 assert(p.target_row and p.target_row.isr and finite(p.target_row.id),'レンダー対象リージョンが不正です。')
 Core.set_project_region_selection(project,{[floor(p.target_row.id+.5)]=true})
 -- Follow REAPER's native "include project metadata" switch. Other render
 -- mode bits stay under this script's control so the output remains one WAV.
 local native_settings=R.GetSetProjectInfo(project,'RENDER_SETTINGS',0,false)
 -- Region bounds are used only to resolve native region filename wildcards.
 -- Use time selection for audio to bypass custom-bound time text conversion.
 local n={RENDER_SETTINGS=native_settings&512,RENDER_BOUNDSFLAG=resolve_region_name and 5 or 2,RENDER_TAILFLAG=0,RENDER_ADDTOPROJ=0,RENDER_SRATE=p.sr,RENDER_CHANNELS=channels,RENDER_NORMALIZE=0,RENDER_DITHER=0}
 for k,v in pairs(n) do R.GetSetProjectInfo(project,k,v,true) end
 if not resolve_region_name then
  p.render_window=Core.render_window(p);local window=p.render_window
  R.GetSet_LoopTimeRange2(project,true,false,window.start,window.finish,false)
  local first,last=R.GetSet_LoopTimeRange2(project,false,false,0,0,false)
  assert(abs(first-window.start)*p.sr<.01 and abs(last-window.finish)*p.sr<.01,
   'レンダー用の時間選択をサンプル精度で設定できません。時間選択のロックなどを確認してください。')
 end
 -- evaw + depth + flags (force RIFF, no project region embedding) + large-file mode.
 local s={RENDER_FILE=dir,RENDER_PATTERN=pattern,RENDER_FORMAT=Core.base64('evaw'..string.char(bits,2,0)),RENDER_FORMAT2=''}
 for _,k in ipairs(Core.render_strings) do assert(R.GetSetProjectInfo_String(project,k,s[k],true),'レンダー設定を変更できません: '..k) end
 R.GetSetProjectInfo_String(project,'RENDER_FORMAT',s.RENDER_FORMAT,true)
end
function Core.native_format(project)
 local ok,encoded=R.GetSetProjectInfo_String(project,'RENDER_FORMAT','',false)
 assert(ok,'REAPER本体の出力形式を取得できません。')
 local sink=Core.unbase64(encoded or '')
 assert(sink:sub(1,4)=='evaw','REAPER本体の出力形式をWAVに設定してください。')
 local bits=sink:byte(5)
 assert(bits==16 or bits==24 or bits==32,'対応形式はWAV 16/24 bit PCM・32 bit floatです。')
 local sr=R.GetSetProjectInfo(project,'RENDER_SRATE',0,false)
 if sr==0 then
  if R.GetSetProjectInfo(project,'PROJECT_SRATE_USE',0,false)~=0 then sr=R.GetSetProjectInfo(project,'PROJECT_SRATE',0,false)
  elseif R.GetAudioDeviceInfo then local got,value=R.GetAudioDeviceInfo('SRATE');sr=got and tonumber(value) or 0 end
 end
 assert(finite(sr) and sr>=8000 and sr<=384000 and sr%1==0,'標準サンプルレートを解決できません。REAPER本体で明示指定してください。')
 local channels=R.GetSetProjectInfo(project,'RENDER_CHANNELS',0,false)
 assert(finite(channels) and channels>=1 and channels<=64 and channels%1==0,'REAPER本体のチャンネル数が不正です。')
 return {sr=sr,bits=bits,channels=channels}
end
function Core.add_names(kind,name,count,numbering,start)
 assert(Core.names[kind],'追加する区間種類が不正です。')
 local first,width=1,1
 if numbering then
  assert(type(start)=='string' and start:match('^%d+$') and #start<=12,'開始番号は1〜12桁の数字で指定してください。')
  first=tonumber(start);width=#start;assert(first+count-1<=999999999999,'開始番号が大きすぎます。')
 end
 local names={}
 for i=1,count do
  local text=name
  if numbering then text=text..(text~='' and '_' or '')..string.format('%0'..width..'d',first+i-1) end
  local raw=(Core.tags[kind] and kind~='region') and (Core.tags[kind]..(text~='' and ' '..text or '')) or text
  if kind=='region' then local k=Core.classify(true,text);if k~='region' then raw=Core.tags.region..' '..text end end
  names[i]=raw
 end
 return names
end
function Core.crossfade_mix(dry,handle,index,count)
 if count<=1 or index>=count-1 then return handle end
 if index<=0 then return dry end
 local theta=math.pi*.5*index/(count-1)
 return dry*math.cos(theta)+handle*math.sin(theta)
end
function Core.crossfade_split_tolerance(sr)
 sr=finite(sr) and sr>0 and sr or 48000
 return max(1e-12,1e-7/sr)
end
function Core.item_effective_channels(item)
 local take=R.GetActiveTake(item);if not take or R.TakeIsMIDI(take) then return nil end
 local source=R.GetMediaItemTake_Source(take);if not source then return nil end
 local channels=optional_number(R.GetMediaSourceNumChannels,source)
 if not channels or channels<1 then return nil end
 local mode=optional_number(R.GetMediaItemTakeInfo_Value,take,'I_CHANMODE') or 0
 if mode==2 or mode==3 or mode==4 then channels=1 end
 return clamp(floor(channels+.5),1,64)
end
function Core.crossfade_channel_count(items,windows,track_channels)
 local cap=finite(track_channels) and clamp(floor(track_channels+.5),1,64) or nil
 local channels=0
 for _,item in ipairs(items or {}) do
  local pos=R.GetMediaItemInfo_Value(item,'D_POSITION');local ending=pos+R.GetMediaItemInfo_Value(item,'D_LENGTH')
  local involved=false
  for _,window in ipairs(windows or {}) do
   if ending>window[1]+1e-9 and pos<window[2]-1e-9 then involved=true;break end
  end
  if involved then channels=max(channels,Core.item_effective_channels(item) or 0) end
 end
 channels=channels>0 and channels or cap or 2
 return cap and min(channels,cap) or channels
end
function Core.crossfade_context(project,rows,items_override)
 local items={}
 if items_override then for _,item in ipairs(items_override) do items[#items+1]=item end
 else for i=0,R.CountSelectedMediaItems(project)-1 do items[#items+1]=R.GetSelectedMediaItem(project,i) end end
 assert(#items>0 and #items<=1000,'音声アイテムを1〜1000個選択してください。')
 local row=Core.loop_target(project,rows,nil,items)
 return row,Core.virtual_loop_items(project,row,items,0)
end
function Core.crossfade_source_range(source,start,frames)
 local first=floor((start-source.s)*source.sr+.5);local last=first+frames-1
 local sample_finish=start+max(0,frames-1)/source.sr
 if source.track_mix then
  assert(start>=source.pos-1e-8 and sample_finish<=source.ending+1e-8,'クロスフェードに必要な仮想トラック素材が足りません。')
  return first
 end
 local available=source.wav and source.wav.frames or floor(source.source_length*source.sr+.5)
 assert(start>=source.pos-1e-8 and sample_finish<=source.ending+1e-8 and first>=0 and last<available,'クロスフェードに必要な素材尺が足りません。')
 return first
end
function Core.crossfade_patch_range(items,start,finish)
 assert(type(items)=='table' and #items>0 and finite(start) and finite(finish) and finish>start,'クロスフェード置換範囲が不正です。')
 local a,b=start,finish;local guard=0
 while true do
  local changed=false;guard=guard+1;assert(guard<=#items*4+4,'クロスフェード置換範囲を確定できません。')
  for _,item in ipairs(items) do
   local pos=R.GetMediaItemInfo_Value(item,'D_POSITION');local ending=pos+R.GetMediaItemInfo_Value(item,'D_LENGTH')
   if ending>a+1e-9 and pos<b-1e-9 then
    local fi=max(0,R.GetMediaItemInfo_Value(item,'D_FADEINLEN') or 0,R.GetMediaItemInfo_Value(item,'D_FADEINLEN_AUTO') or 0)
    local fo=max(0,R.GetMediaItemInfo_Value(item,'D_FADEOUTLEN') or 0,R.GetMediaItemInfo_Value(item,'D_FADEOUTLEN_AUTO') or 0)
    local ranges={{pos,min(ending,pos+fi)},{max(pos,ending-fo),ending}}
    for _,fade in ipairs(ranges) do
     if fade[2]>fade[1]+1e-10 then
      if a>fade[1]+1e-9 and a<fade[2]-1e-9 then a=fade[1];changed=true end
      if b>fade[1]+1e-9 and b<fade[2]-1e-9 then b=fade[2];changed=true end
     end
    end
   end
  end
  if not changed then break end
 end
 local affected={}
 for _,item in ipairs(items) do
  local pos=R.GetMediaItemInfo_Value(item,'D_POSITION');local ending=pos+R.GetMediaItemInfo_Value(item,'D_LENGTH')
  if ending>a+1e-9 and pos<b-1e-9 then affected[#affected+1]=item end
 end
 assert(#affected>0,'クロスフェード置換範囲の音声アイテムがありません。')
 return a,b,affected
end
function Core.crossfade_aligned_patch(items,start,finish,anchor,sr)
 local a,b=start,finish
 for _=1,#items*4+8 do
  local expanded_start,expanded_end,affected=Core.crossfade_patch_range(items,a,b)
  local left_frames=max(1,math.ceil((anchor-expanded_start)*sr-1e-7))
  local aligned_start=anchor-left_frames/sr
  -- Only the start must share the loop-end sample grid. Keep the expanded
  -- right boundary exact; the WAV may contain one trimmed guard frame there.
  if abs(aligned_start-a)<=1e-12 and abs(expanded_end-b)<=1e-12 then return aligned_start,expanded_end,affected end
  a,b=aligned_start,expanded_end
 end
 error('クロスフェード置換範囲をサンプル境界へ整列できません。',0)
end
function Core.crossfade_grid_row(row,sr)
 local aligned={};for k,v in pairs(row) do aligned[k]=v end
 aligned.start=floor(row.start*sr+.5)/sr
 aligned.finish=floor(row.finish*sr+.5)/sr
 return aligned
end
function Core.crossfade_fit(project,rows,seconds,items_override)
 assert(finite(seconds) and seconds>0,'クロスフェード時間を指定してください。')
 local row,items=Core.crossfade_context(project,rows,items_override)
 local source=Core.track_mix_source(project,items)
 row=Core.crossfade_grid_row(row,source.sr)
 local frames=floor((row.finish-row.start)*source.sr+.5);assert(frames>=2,'サステイン区間が2サンプル未満のため、クロスフェードできません。')
 local lower=2/source.sr;local upper=min(frames/source.sr,row.finish-source.pos,row.start-source.pos)
 assert(upper>=lower-1e-12,'ループポイント直前にクロスフェード用の音声が2サンプル以上必要です。')
 return clamp(seconds,lower,upper)
end
function Core.crossfade_plan(project,rows,seconds,items_override)
 assert(finite(seconds) and seconds>0,'クロスフェード時間を指定してください。')
 local row,items=Core.crossfade_context(project,rows,items_override)
 local dry=Core.track_mix_source(project,items);local handle=Core.track_mix_source(project,items)
 local original_row=row;row=Core.crossfade_grid_row(row,dry.sr)
 local sr=dry.sr;local frames=floor((row.finish-row.start)*sr+.5);local fade=floor(seconds*sr+.5)
 assert(fade>=2 and frames>=fade,'ループ尺が足りません。クロスフェード時間はループ長以下、2サンプル以上にしてください。')
 local t=fade/sr;local output_start=row.finish-t;local handle_start=row.start-t
 -- Move the item edge beyond the loop and return smoothly to untouched audio.
 local extension=min(64,max(0,floor((dry.ending-row.finish)*sr+1e-7)),max(0,frames-1))
 local patch_start,patch_end,patch_items=Core.crossfade_aligned_patch(items,output_start,row.finish+extension/sr,row.finish,sr)
 local ch=Core.crossfade_channel_count(items,{{handle_start,row.start},{patch_start,patch_end}},dry.ch)
 dry.ch=ch;handle.ch=ch
 local output_frames=math.ceil((patch_end-patch_start)*sr-1e-7);assert(output_frames>=fade,'クロスフェード置換範囲が不足しています。')
 -- Keep inaudible source padding around the visible replacement. REAPER may
 -- need neighbouring source samples when an item/region boundary falls
 -- between project samples. Without this padding, the resampler can see the
 -- physical beginning/end of the generated WAV and create a one-sample edge.
 local guard_cap=min(Core.CROSSFADE_GUARD_FRAMES,max(0,frames-1))
 local pre_guard=min(guard_cap,max(0,floor((patch_start-dry.pos)*sr+1e-7)))
 local post_role,post_start,post_guard
 if abs(patch_end-row.finish)<=Core.crossfade_split_tolerance(sr) then
  post_role='handle';post_start=row.start
  post_guard=min(guard_cap,max(0,floor((handle.ending-post_start)*sr+1e-7)))
 else
  -- The visible patch contains original audio beyond the loop: continue that audio.
  post_role='dry';post_start=patch_start+output_frames/sr
  post_guard=min(guard_cap,max(0,floor((dry.ending-post_start)*sr+1e-7)))
 end
 local file_frames=pre_guard+output_frames+post_guard
 Core.crossfade_source_range(dry,patch_start-pre_guard/sr,pre_guard+output_frames)
 Core.crossfade_source_range(handle,handle_start,fade)
 if post_guard>0 then Core.crossfade_source_range(post_role=='dry' and dry or handle,post_start,post_guard) end
 local blend_first=floor((output_start-patch_start)*sr+.5)
 local snapshots={};local sources={};local track=dry.track;local fixed_lane,lanes_differ
 for _,item in ipairs(patch_items) do
  assert(R.GetMediaItemInfo_Value(item,'C_LOCK')==0,'クロスフェード置換範囲の音声アイテムがロックされています。')
  local ok,chunk=R.GetItemStateChunk(item,'',false);assert(ok,'アイテムの復元情報を取得できません。')
  snapshots[#snapshots+1]={item=item,track=track,chunk=chunk}
  local lane=optional_number(R.GetMediaItemInfo_Value,item,'I_FIXEDLANE')
  if lane then if fixed_lane~=nil and lane~=fixed_lane then lanes_differ=true else fixed_lane=fixed_lane or lane end end
 end
 local lane_mode=optional_number(R.GetMediaTrackInfo_Value,track,'I_FREEMODE')
 assert(not (lane_mode==2 and lanes_differ),'固定レーンをまたぐクロスフェード重複は、通常の音声アイテムへまとめてから実行してください。')
 for _,item in ipairs(items) do sources[#sources+1]={item=item,track=track,pos=R.GetMediaItemInfo_Value(item,'D_POSITION'),ending=R.GetMediaItemInfo_Value(item,'D_POSITION')+R.GetMediaItemInfo_Value(item,'D_LENGTH')} end
 local fmt=string.pack('<I2I2I4I4I2I2',3,ch,sr,sr*ch*4,ch*4,32);local fmt_chunk=Core.chunk('fmt ',fmt)
 local data_bytes=file_frames*ch*4;assert(4+#fmt_chunk+8+data_bytes+data_bytes%2<=0xffffffff,'4 GiBを超える加工素材には対応していません。')
 return {{item=patch_items[1],track=track,patch_items=patch_items,snapshots=snapshots,sources=sources,dry=dry,handle=handle,s=row.start,e=row.finish,
  loop_start=row.start,loop_finish=row.finish,frames=frames,fade=fade,sr=sr,ch=ch,mode='pre',output_frames=output_frames,
  pre_guard=pre_guard,post_guard=post_guard,file_frames=file_frames,post_role=post_role,post_start=post_start,region=original_row,
  output_start=output_start,handle_start=handle_start,blend_first=blend_first,extension=extension,
  patch_start=patch_start,patch_end=patch_end,fmt_chunk=fmt_chunk,data_bytes=data_bytes,mixed_commit=true,fixed_lane=lane_mode==2 and fixed_lane or nil}}
end
local function cf_close(j)
 for _,role in ipairs({'dry','handle'}) do
  local file=role..'_file';if j[file] then j[file]:close();j[file]=nil end
  local accessor=role..'_accessor';if j[accessor] then R.DestroyAudioAccessor(j[accessor]);j[accessor]=nil end
 end
 if j.source_file then j.source_file:close();j.source_file=nil end
 if j.accessor then R.DestroyAudioAccessor(j.accessor);j.accessor=nil end
 if j.file then j.file:close();j.file=nil end
 j.open_source=nil
end
function Core.crossfade_abort(j)
 if not j then return end
 cf_close(j)
 for _,p in ipairs(j.plans or {}) do
  if p.peak_pending and p.peak_source and R.PCM_Source_BuildPeaks then
   pcall(R.PCM_Source_BuildPeaks,p.peak_source,2)
   p.peak_pending=false
   if p.peak_item and R.UpdateItemInProject then R.UpdateItemInProject(p.peak_item) end
  end
 end
 if not j.committed and not j.commit_started then
  for _,p in ipairs(j.plans) do if p.path then os.remove(p.path) end;if p.temp then os.remove(p.temp) end end
 end
end
function Core.crossfade_start(project,plans,dir)
 local j={project=project,plans=plans,index=1,at=0,done=0,total=0,progress=0,revision=R.GetProjectStateChangeCount(project)}
 for i,p in ipairs(plans) do
  local token=R.genGuid():gsub('[^%w]','');p.path=Core.unique(dir..'/LRM_Loop_'..token..'_'..i..'.wav');p.temp=p.path..'.blt-part'
  assert(not Core.exists(p.temp),'作業ファイルが存在します。');j.total=j.total+(p.file_frames or p.output_frames)
 end
 return j
end
local function cf_open(j,source,role,start,ending)
 if source.track_mix then
  local accessor=assert(R.CreateTrackAudioAccessor(source.track),'トラック合成音声を取得できません。');j[role..'_accessor']=accessor
  assert(R.GetAudioAccessorStartTime(accessor)<=start+1e-8 and R.GetAudioAccessorEndTime(accessor)>=ending-1e-8,'仮想トラック素材の音声範囲を取得できません。')
 elseif source.wav then j[role..'_file']=assert(io.open(source.source_path,'rb'),'元WAVを開けません。')
 else
  local accessor=assert(R.CreateTakeAudioAccessor(source.take),'音声アクセサーを作成できません。');j[role..'_accessor']=accessor
  assert(R.GetAudioAccessorStartTime(accessor)<=start+1e-8 and R.GetAudioAccessorEndTime(accessor)>=ending-1e-8,'素材尺が足りません。必要な音声範囲を取得できません。')
 end
end
local function cf_read(j,source,role,start,n,buffer)
 if source.wav then
  local w=source.wav;local first=floor((start-source.s)*source.sr+.5)
  assert(first>=0 and first+n<=w.frames,'元WAVの読み取り範囲が不正です。')
  local file=j[role..'_file'];assert(file:seek('set',w.data.offset+8+first*w.align))
  local raw=file:read(n*w.align);assert(raw and #raw==n*w.align,'元WAVの音声読み取りに失敗しました。')
  local out={};local bytes=w.bits//8
  local fmt=w.tag==3 and (w.bits==32 and '<f' or '<d') or ('<i'..bytes)
  local scale=w.tag==3 and 1 or 2^(w.bits-1)
  for i=1,n*source.ch do out[i]=string.unpack(fmt,raw,1+(i-1)*bytes)/scale end
  return out
 end
 buffer.clear()
 local accessor=role=='source' and j.accessor or j[role..'_accessor']
 local rc=R.GetAudioAccessorSamples(accessor,source.sr,source.ch,start,n,buffer)
 assert(rc==0 or rc==1,'素材の音声取得に失敗しました。')
 return buffer.table(1,n*source.ch)
end
function Core.crossfade_step(j)
 assert(R.EnumProjects(-1,'')==j.project and R.GetProjectStateChangeCount(j.project)==j.revision,'処理中にプロジェクトが変更されました。やり直してください。')
 local p=j.plans[j.index];if not p then return true end
 local pre_guard=p.pre_guard or 0;local post_guard=p.post_guard or 0
 local file_frames=p.file_frames or (pre_guard+p.output_frames+post_guard)
 if not j.file then
  local patch_start=p.patch_start or p.output_start
  local dry_end=p.patch_end or p.loop_finish
  if p.post_role=='dry' and post_guard>0 then dry_end=max(dry_end,p.post_start+(post_guard-1)/p.sr) end
  cf_open(j,p.dry,'dry',patch_start-pre_guard/p.sr,dry_end)
  cf_open(j,p.handle,'handle',p.handle_start,p.loop_start+max(p.extension or 0,p.post_role=='dry' and 0 or post_guard)/p.sr)
  j.buf=R.new_array(8192*p.ch);j.handle_buf=R.new_array(8192*p.ch)
  j.file=assert(io.open(p.temp,'wb'))
  local bytes=p.data_bytes
  assert(j.file:write('RIFF'..string.pack('<I4',4+#p.fmt_chunk+8+bytes+bytes%2)..'WAVE'..p.fmt_chunk..'data'..string.pack('<I4',bytes)))
 end
 local patch_start=p.patch_start or p.output_start;local n,audio
 if j.at<pre_guard then
  n=min(8192,pre_guard-j.at)
  audio=cf_read(j,p.dry,'dry',patch_start-pre_guard/p.sr+j.at/p.sr,n,j.buf)
 elseif j.at<pre_guard+p.output_frames then
  local visible_at=j.at-pre_guard
  n=min(8192,pre_guard+p.output_frames-j.at)
  audio=cf_read(j,p.dry,'dry',patch_start+visible_at/p.sr,n,j.buf)
  local blend_first=p.blend_first or 0;local local_first=max(0,blend_first-visible_at)
  local local_last=min(n,blend_first+p.fade-visible_at)
  if local_last>local_first then
   local blend_index=visible_at+local_first-blend_first
   local extra=cf_read(j,p.handle,'handle',p.loop_start+(blend_index-p.fade)/p.sr,local_last-local_first,j.handle_buf)
   for frame=local_first,local_last-1 do for ch=1,p.ch do
    local i=frame*p.ch+ch;local extra_i=(frame-local_first)*p.ch+ch
    audio[i]=Core.crossfade_mix(audio[i],extra[extra_i],visible_at+frame-blend_first,p.fade)
   end end
  end
  local ext=p.extension or 0
  if ext>0 then
   local ext_first=blend_first+p.fade
   local a=max(0,ext_first-visible_at);local b=min(n,ext_first+ext-visible_at)
   if b>a then
    local index=visible_at+a-ext_first
    local extra=cf_read(j,p.handle,'handle',p.loop_start+index/p.sr,b-a,j.handle_buf)
    local hold=math.floor(ext/2)
    for frame=a,b-1 do
     local k=visible_at+frame-ext_first
     local weight=k<hold and 1 or (ext-hold<=1 and 0 or .5+.5*math.cos(math.pi*(k-hold)/(ext-hold-1)))
     for ch=1,p.ch do local i=frame*p.ch+ch
      audio[i]=audio[i]*(1-weight)+extra[(frame-a)*p.ch+ch]*weight
     end
    end
   end
  end
 else
  local post_at=j.at-pre_guard-p.output_frames
  n=min(8192,file_frames-j.at)
  local role=p.post_role or 'handle'
  audio=cf_read(j,role=='dry' and p.dry or p.handle,role,(p.post_start or p.loop_start)+post_at/p.sr,n,role=='dry' and j.buf or j.handle_buf)
 end
 local fmt='<f';local scale=nil
 local packed={}
 for i,v in ipairs(audio) do
  assert(finite(v),'素材に不正な音声値があります。')
  if scale then v=clamp(floor(v*scale+.5),-scale,scale-1) end
  packed[i]=string.pack(fmt,v)
 end
 assert(j.file:write(table.concat(packed)));j.at=j.at+n;j.done=j.done+n;j.progress=j.done/j.total
 if j.at==file_frames then
  if p.data_bytes%2==1 then assert(j.file:write('\0')) end
  assert(j.file:flush());cf_close(j)
  local check=Core.scan(p.temp);assert(check.frames==file_frames and check.channels==p.ch and check.sr==p.sr,'加工音声の検証に失敗しました。')
  assert(not Core.exists(p.path) and os.rename(p.temp,p.path),'ループ音声を保存できません。');p.temp=nil
  j.index=j.index+1;j.at=0
 end
 return j.index>#j.plans
end
function Core.crossfade_commit(j)
 assert(R.EnumProjects(-1,'')==j.project and R.GetProjectStateChangeCount(j.project)==j.revision,'プロジェクトが変更されました。')
 local has_mixed=false
 for _,p in ipairs(j.plans) do
  if p.mixed_commit then
   has_mixed=true
   for _,snapshot in ipairs(p.snapshots or {}) do
    local ok,chunk=R.GetItemStateChunk(snapshot.item,'',false);assert(ok and chunk==snapshot.chunk,'クロスフェード対象のアイテムが変更されました。')
   end
  else
   local ok,chunk=R.GetItemStateChunk(p.item,'',false);assert(ok and chunk==p.chunk,'アイテムが変更されました。')
  end
 end
 if has_mixed then assert(type(R.Undo_DoUndo2)=='function','安全なクロスフェード置換に必要なUndo APIを利用できません。') end
 j.commit_started=true;R.Undo_BeginBlock2(j.project)
 local created={}
 local function split(item,at)
  local right=assert(R.SplitMediaItem(item,at),'アイテムの分割に失敗しました。')
  created[#created+1]={item=right,track=R.GetMediaItemTrack(right)}
  return right
 end
 local function clear_edge(item,edge)
  for _,k in ipairs({'D_FADE'..edge..'LEN','D_FADE'..edge..'LEN_AUTO'}) do
   assert(R.SetMediaItemInfo_Value(item,k,0),'分割端のフェードを更新できません。')
  end
 end
 local ok,err=xpcall(function()
 for _,p in ipairs(j.plans) do
  local split_tolerance=Core.crossfade_split_tolerance(p.sr)
  local source=assert(R.PCM_Source_CreateFromFile(p.path),'加工素材を読み込めません。')
   local middle
   if p.mixed_commit then
    local remove={};p.result_items={};j.commit_mutated=true
    for _,snapshot in ipairs(p.snapshots) do
     local item=snapshot.item;local pos=R.GetMediaItemInfo_Value(item,'D_POSITION')
     local ending=pos+R.GetMediaItemInfo_Value(item,'D_LENGTH');middle=item
     if p.patch_end<ending-split_tolerance then
      local right=split(middle,p.patch_end);p.result_items[#p.result_items+1]=right
      clear_edge(right,'IN')
     end
     if p.patch_start>pos+split_tolerance then
      middle=split(middle,p.patch_start);p.result_items[#p.result_items+1]=item
      clear_edge(item,'OUT');clear_edge(middle,'IN')
     end
     remove[#remove+1]=middle
    end
    middle=assert(R.AddMediaItemToTrack(p.track),'加工音声用のアイテムを作成できません。')
    created[#created+1]={item=middle,track=p.track};p.result_items[#p.result_items+1]=middle
    assert(R.SetMediaItemInfo_Value(middle,'D_POSITION',p.patch_start),'加工アイテムの位置を設定できません。')
    assert(R.SetMediaItemInfo_Value(middle,'D_LENGTH',p.patch_end-p.patch_start),'加工アイテムの長さを設定できません。')
    assert(R.SetMediaItemInfo_Value(middle,'D_VOL',1),'加工アイテムの音量を設定できません。')
    assert(R.SetMediaItemInfo_Value(middle,'B_LOOPSRC',0),'加工素材のループ設定を更新できません。')
    if p.fixed_lane~=nil then assert(R.SetMediaItemInfo_Value(middle,'I_FIXEDLANE',p.fixed_lane),'加工アイテムの固定レーンを設定できません。') end
    clear_edge(middle,'IN');clear_edge(middle,'OUT')
    local take=assert(R.AddTakeToMediaItem(middle),'加工音声用のテイクを作成できません。')
    R.SetMediaItemTake_Source(take,source);assert(R.GetMediaItemTake_Source(take)==source,'加工素材を適用できません。')
    for key,value in pairs({D_STARTOFFS=(p.pre_guard or 0)/p.sr,D_VOL=1,D_PAN=0,D_PLAYRATE=1,D_PITCH=0}) do
     assert(R.SetMediaItemTakeInfo_Value(take,key,value),'加工テイクの再生設定を更新できません。')
    end
    for _,item in ipairs(remove) do assert(R.DeleteTrackMediaItem(p.track,item),'置換前の重複音声を取り除けません。') end
    if R.SetMediaItemSelected then R.SetMediaItemSelected(middle,true) end
   else
    middle=p.item;p.result_items={p.item}
    if p.patch_end<p.ending-split_tolerance then
     local right=split(middle,p.patch_end);p.result_items[#p.result_items+1]=right
     clear_edge(middle,'OUT');clear_edge(right,'IN')
    end
    if p.patch_start>p.pos+split_tolerance then
     middle=split(middle,p.patch_start);p.result_items[#p.result_items+1]=middle
     clear_edge(p.item,'OUT');clear_edge(middle,'IN')
    end
    local take=assert(R.GetActiveTake(middle),'加工区間のテイクを取得できません。')
    R.SetMediaItemTake_Source(take,source);assert(R.GetMediaItemTake_Source(take)==source,'加工素材を適用できません。')
    assert(R.SetMediaItemTakeInfo_Value(take,'D_STARTOFFS',(p.pre_guard or 0)/p.sr),'加工素材の開始位置を更新できません。')
    assert(R.SetMediaItemInfo_Value(middle,'B_LOOPSRC',0),'加工素材のループ設定を更新できません。')
   end
   if p.region and (p.region.start~=p.loop_start or p.region.finish~=p.loop_finish) then
    assert(R.SetProjectMarker3(j.project,p.region.id,true,p.loop_start,p.loop_finish,p.region.raw,p.region.color),'サステインのサンプル位置を更新できません。')
   end
   p.peak_source=source;p.peak_item=middle
   p.peak_pending=R.PCM_Source_BuildPeaks and R.PCM_Source_BuildPeaks(source,0)~=0 or false
   if R.UpdateItemInProject then R.UpdateItemInProject(middle) end
 end
 end,debug.traceback)
 local rollback_complete=false
 if not ok then
  -- Finish any peak-builder begun for a source before restoring/deleting the
  -- take that owns it; the source pointer may no longer be valid afterwards.
  for _,p in ipairs(j.plans) do if p.peak_pending and p.peak_source then
   pcall(R.PCM_Source_BuildPeaks,p.peak_source,2);p.peak_pending=false
  end end
  if not has_mixed then
   local failed=false
   for i=#created,1,-1 do
    local c=created[i];if not R.DeleteTrackMediaItem(c.track,c.item) then failed=true end
   end
   for _,p in ipairs(j.plans) do if not R.SetItemStateChunk(p.item,p.chunk,false) then failed=true end end
   if failed then err=err..'\n一部のアイテムを復元できませんでした。REAPERのUndoで処理を戻してください。' end
   rollback_complete=not failed
  end
 end
 R.Undo_EndBlock2(j.project,'BLT LOOP RM STUDIO: クロスフェードループ',-1)
 if not ok and has_mixed and j.commit_mutated then
  local called,result=pcall(R.Undo_DoUndo2,j.project);local restored=called and result~=0
  if not restored then err=err..'\n処理前のアイテムを自動復元できませんでした。REAPERのUndoを実行してください。' end
  rollback_complete=restored
 end
 if not ok and has_mixed and not j.commit_mutated then rollback_complete=true end
 R.UpdateArrange()
 if not ok then if rollback_complete then j.commit_started=false end;error(err,0) end
 j.committed=true
end
function Core.crossfade_peaks_step(j)
 assert(j and j.committed,'クロスフェード素材がまだ適用されていません。')
 j.peak_index=j.peak_index or 1
 while j.peak_index<=#j.plans do
  local p=j.plans[j.peak_index]
  if p.peak_pending then
   local remaining=R.PCM_Source_BuildPeaks(p.peak_source,1)
   assert(type(remaining)=='number' and remaining>=0,'生成素材の波形ピークを構築できません。')
   if remaining~=0 then return false end
   R.PCM_Source_BuildPeaks(p.peak_source,2);p.peak_pending=false
   if p.peak_item and R.UpdateItemInProject then R.UpdateItemInProject(p.peak_item) end
  end
  j.peak_index=j.peak_index+1
 end
 R.UpdateArrange()
 return true
end

-- Shared bounded audio reader for non-destructive loop analysis.
function Core.loop_audio_read(j,source,start,n,buffer)
 return cf_read(j,source,'source',start,n,buffer)
end
Core.loop_audio_close=cf_close

-- Non-destructive region adjustment. Read only endpoint windows (zero crossing)
-- or the loop plus a short margin (rhythmic period), never the whole source.
function Core.near_zero(audio,ch,first,target,sr,direction)
 local n=#audio//ch;local energy=0
 for _,v in ipairs(audio) do assert(finite(v),'音声に不正な値があります。');energy=energy+v*v end
 energy=energy/max(1,#audio)
 assert(energy>1e-14,'ゼロクロスを判定できません。対象付近が無音です。')
 local best,bestscore
 for f=1,n-1 do
  local crossing=false;local before,after=0,0
  for c=1,ch do
   local a,b=audio[(f-1)*ch+c],audio[f*ch+c]
   if a*b<=0 and abs(a-b)>1e-10 then crossing=true end
   before=before+a*a;after=after+b*b
  end
  if crossing then
   local k=after<before and f or f-1
   local distance=abs(first+k-target)
   -- All channels share one boundary. Other-channel residual energy matters,
   -- so antiphase stereo cannot falsely look like silence through mono summing.
   local allowed=not direction or direction*(first+k-target)>0
   local score=direction and (distance+min(before,after)/(ch*energy)*.001) or (min(before,after)/(ch*energy)+.15*distance/max(1,.020*sr))
   if allowed and (not bestscore or score<bestscore) then best,bestscore=first+k,score end
  end
 end
 assert(best,direction and '指定方向の100 ms以内に次のゼロクロスが見つかりませんでした。' or '前後20 ms以内にゼロクロスが見つかりませんでした。')
 return best
end

function Core.period_analysis_window(start,finish,available_start,available_end)
 assert(finite(start) and finite(finish) and finite(available_start) and finite(available_end)
  and available_start<=start+1e-7 and finish<=available_end+1e-7 and finish>start,'周期解析範囲が不正です。')
 local duration=finish-start
 assert(duration<=Core.PERIOD_ANALYSIS_MAX+1e-9,'100秒を超えるサステインは周期解析できません。')
 local target=clamp(duration*3,Core.PERIOD_ANALYSIS_MIN,Core.PERIOD_ANALYSIS_MAX)
 local margin=(target-duration)/2
 local wanted_start,wanted_end=start-margin,finish+margin
 if wanted_start<available_start then
  wanted_end=min(available_end,wanted_end+available_start-wanted_start);wanted_start=available_start
 end
 if wanted_end>available_end then
  wanted_start=max(available_start,wanted_start-(wanted_end-available_end));wanted_end=available_end
 end
 return wanted_start,wanted_end,target
end

function Core.period_fit(features,rate,start,finish,lo,hi,allow_empty)
 local n=#features;if n<60 then error(Core.PERIOD_FAILURE..'周期解析には少なくとも0.6秒程度の音声が必要です。',0) end
 local channels={}
 for field=1,2 do
  local mean,var=0,0
  for _,v in ipairs(features) do mean=mean+v[field] end;mean=mean/n
  for _,v in ipairs(features) do var=var+(v[field]-mean)^2 end
  local sd=math.sqrt(var/n)
  if sd>1e-7 and sd/max(abs(mean),1e-9)>.05 then
   local values={};for i,v in ipairs(features) do values[i]=(v[field]-mean)/sd end
   local smooth={}
   for i=1,n do smooth[i]=(values[max(1,i-1)]+values[i]+values[min(n,i+1)])/3 end
   channels[#channels+1]=smooth
  end
 end
 if #channels==0 then error(Core.PERIOD_FAILURE..'明確なリズム周期を検出できませんでした。',0) end
 local minlag=max(3,floor(.12*rate));local maxlag=min(floor(5*rate),floor(n/3))
 local correlation={};local peak=-1
 for lag=minlag-1,maxlag+1 do
  local ab,aa,bb=0,0,0
  for _,values in ipairs(channels) do for i=1,n-lag do
   local a,b=values[i],values[i+lag];ab=ab+a*b;aa=aa+a*a;bb=bb+b*b
  end end
  correlation[lag]=ab/math.sqrt(max(1e-20,aa*bb))
 end
 for lag=minlag,maxlag do
  if correlation[lag]>=correlation[lag-1] and correlation[lag]>correlation[lag+1] then peak=max(peak,correlation[lag]) end
 end
 if peak<.65 then error(Core.PERIOD_FAILURE..'安定した周期を検出できませんでした。',0) end
 local lag
 for i=minlag,maxlag do
  if correlation[i]>=max(.65,peak-.04) and correlation[i]>=correlation[i-1] and correlation[i]>correlation[i+1] then lag=i;break end
 end
 if not lag then error(Core.PERIOD_FAILURE..'周期候補を絞り込めませんでした。',0) end
 -- Fold the strongest repeating feature over a cycle; its averaged maximum
 -- provides a consistent phase for both region edges.
 local bestvalue,bestphase=-math.huge,0
 for _,values in ipairs(channels) do for phase=0,lag-1 do
  local sum,count=0,0
  for i=phase+1,n,lag do sum=sum+values[i];count=count+1 end
  if sum/count>bestvalue then bestvalue,bestphase=sum/count,phase end
 end end
 local period=lag/rate;local anchor=lo+(bestphase+.5)/rate
 local function snap(t)
  local k=floor((t-anchor)/period+.5)
  k=clamp(k,math.ceil((lo-anchor)/period),floor((hi-anchor)/period))
  return anchor+k*period
 end
 local s,e=snap(start),snap(finish)
 if not allow_empty and e<=s then error(Core.PERIOD_FAILURE..'周期に合わせると区間がなくなります。長めのサステインを指定してください。',0) end
 return s,e,period,correlation[lag],anchor
end

function Core.loop_adjust_start(project,rows,mode,edge,direction,items_override,relative)
 assert(mode=='zero' or mode=='period' or mode=='preview','解析方法が不正です。')
 assert(not edge or (edge=='start' or edge=='finish') and (direction==1 or direction==-1),'移動方向が不正です。')
 local count=items_override and #items_override or R.CountSelectedMediaItems(project)
 assert(count>0 and count<=1000,'音声アイテムを選択してください。')
 local j={project=project,revision=R.GetProjectStateChangeCount(project),plans={},index=1,window=1,at=0,done=0,total=0,mode=mode,edge=edge,direction=direction,relative=relative==true and edge~=nil}
 local target_row=#rows==1 and rows[1].kind=='sustain' and rows[1] or nil
 local groups,by_row={},{}
 for i=0,count-1 do
  local item=items_override and items_override[i+1] or R.GetSelectedMediaItem(project,i)
  local pos=R.GetMediaItemInfo_Value(item,'D_POSITION');local length=R.GetMediaItemInfo_Value(item,'D_LENGTH')
  assert(finite(pos) and finite(length) and length>0,'選択アイテムの位置または長さが不正です。')
  local ending=pos+length;local row=target_row
  if not row then for _,r in ipairs(rows) do if r.kind=='sustain' and r.start<ending and r.finish>pos then
   assert(not row,'選択アイテムに複数のサステインが重なっています。対象を分けて選択してください。');row=r
  end end end
  assert(row,'選択アイテムと重なるサステインがありません。')
  local key=row.key or tostring(row);local g=by_row[key]
  if not g then g={row=row,items={}};by_row[key]=g;groups[#groups+1]=g end
  g.items[#g.items+1]={item=item,pos=pos,ending=ending}
 end
 table.sort(groups,function(a,b) return a.row.start==b.row.start and a.row.finish<b.row.finish or a.row.start<b.row.start end)
 local function plan_for(group)
  local sources,source_items,track={},{},nil
  for _,entry in ipairs(group.items) do
   local take=R.GetActiveTake(entry.item);assert(take and not R.TakeIsMIDI(take),'音声アイテムを選択してください。')
   local item_track=R.GetMediaItem_Track(entry.item)
   assert(not track or track==item_track,'同じループを構成する音声アイテムは同じトラックから選択してください。')
   track=track or item_track
   sources[#sources+1]={item=entry.item,take=take,track=item_track,pos=entry.pos,ending=entry.ending}
   source_items[#source_items+1]=entry.item
  end
  table.sort(sources,function(a,b) return a.pos==b.pos and a.ending>b.ending or a.pos<b.pos end)
  local min_time,max_time=sources[1].pos,sources[1].ending;local right_source=sources[1]
  for i=2,#sources do
   local source=sources[i]
   assert(source.pos<=max_time+1e-7,'サステイン上の選択アイテム間に隙間があります。連続するアイテムを選択してください。')
   if source.ending>max_time then max_time=source.ending;right_source=source end
  end
  local mix=Core.track_mix_source(project,source_items);local first=sources[1];local row=group.row
  local p={item=first.item,take=first.take,row=row,s=mix.s,sr=mix.sr,ch=mix.ch,lo=mix.lo,hi=mix.hi,audio_source=mix,
   sources=sources,left_source=first,right_source=right_source,snapshots={},windows={},features={},bin_sum=0,bin_cross=0,bin_count=0,previous={},min_time=min_time,max_time=max_time}
  for _,source in ipairs(sources) do
   p.snapshots[#p.snapshots+1]={item=source.item,take=source.take,pos=source.pos,ending=source.ending,startoffs=R.GetMediaItemTakeInfo_Value(source.take,'D_STARTOFFS')}
  end
  assert(row.start>=p.min_time-1e-7,'サステイン開始を覆う音声アイテムも選択してください。')
  assert(row.finish<=p.max_time+1e-7,'サステイン終了を覆う音声アイテムも選択してください。')
  return p
 end
 for _,group in ipairs(groups) do
  local p=plan_for(group);local row=p.row
  if mode=='zero' then
   for _,which in ipairs(edge and {edge} or {'start','finish'}) do
    local t=which=='start' and row.start or row.finish;local source=p.audio_source
    local target=floor((t-source.s)*source.sr+.5);target=clamp(target,source.lo,source.hi)
    local radius=floor((direction and .1 or .02)*source.sr)
    local first=max(source.lo,target-radius);local last=min(source.hi,target+radius+2)
    assert(last-first>=2,'境界付近にゼロクロス解析用の音声が足りません。')
    p.windows[#p.windows+1]={first=first,last=last,target=target,edge=which,audio={},source=source}
   end
  elseif mode=='preview' then
   local source=p.audio_source
   local sf=floor((row.start-source.s)*source.sr+.5);local ef=floor((row.finish-source.s)*source.sr+.5)
   assert(sf>=source.lo-1 and ef<=source.hi+1,'プレビュー範囲が仮想トラック素材の外です。')
   sf,ef=clamp(sf,source.lo,source.hi),clamp(ef,source.lo,source.hi)
   -- Cache the full drag range once; drawing still visits only visible samples.
   local view=math.ceil(Core.SEAM_SECONDS*source.sr)
   local guard=math.ceil(Core.SEAM_DRAG_SECONDS*source.sr)+1
   p.windows={{first=max(source.lo,ef-view-guard),last=min(source.hi,ef+guard),audio={},edge='finish',source=source},
    {first=max(source.lo,sf-guard),last=min(source.hi,sf+view+guard),audio={},edge='start',source=source}}
  else
   local source=p.audio_source
   local wanted_start,wanted_end=Core.period_analysis_window(row.start,row.finish,p.min_time,p.max_time)
   local first=max(source.lo,floor((wanted_start-source.s)*source.sr+.5))
   local last=min(source.hi,floor((wanted_end-source.s)*source.sr+.5))
   if last>first then
    p.windows[1]={first=first,last=last,source=source}
    p.analysis_start=source.s+first/source.sr;p.analysis_end=source.s+last/source.sr
   end
   assert(#p.windows>0 and p.analysis_start<=row.start+1/p.sr and p.analysis_end>=row.finish-1/p.sr,'周期解析範囲を選択アイテムで覆えていません。')
   assert(p.analysis_end-p.analysis_start<=Core.PERIOD_ANALYSIS_MAX+2/p.sr,'周期解析範囲が100秒を超えています。')
   p.bin_size=max(1,floor(p.sr/100+.5));p.feature_rate=p.sr/p.bin_size
  end
  for _,w in ipairs(p.windows) do j.total=j.total+w.last-w.first end
  j.plans[#j.plans+1]=p
 end
 return j
end

function Core.loop_align_time(p,t,which)
 if p.audio_source and p.audio_source.track_mix then
  local source=p.audio_source
  return source.s+floor((t-source.s)*source.sr+.5)/source.sr
 end
 local chosen,closest,distance
 for _,source in ipairs(p.sources or {p}) do
  local contains=which=='start' and t>=source.pos-1e-8 and t<source.ending-1e-8 or which=='finish' and t>source.pos+1e-8 and t<=source.ending+1e-8
  local d=t<source.pos and source.pos-t or t>source.ending and t-source.ending or 0
  if contains then chosen=source;break end
  if not distance or d<distance then closest,distance=source,d end
 end
 chosen=chosen or closest or p
 return chosen.s+floor((t-chosen.s)*chosen.sr+.5)/chosen.sr
end

function Core.loop_extension_items(project,p,new_start,new_end,relative)
 assert(finite(new_start) and finite(new_end) and new_end>new_start,'調整後のサステイン区間が短すぎます。')
 local additions,seen={},{}
 local function add(item)
  if not seen[item] then seen[item]=true;additions[#additions+1]=item end
 end
 for _,source in ipairs(p.sources or {}) do if source.item then seen[source.item]=true end end
 local function extend(side,target)
  local left=side=='left';local cursor=left and p.min_time or p.max_time
  if (left and target>=cursor-1e-9) or ((not left) and target<=cursor+1e-9) then return cursor,true end
  local sources=p.sources or {}
  local boundary=left and (p.left_source or sources[1]) or (p.right_source or sources[#sources])
  local track=boundary and (boundary.track or boundary.item and R.GetMediaItem_Track(boundary.item))
  assert(track,'移動先を探す基準トラックを取得できません。')
  local guard=0
  while (left and target<cursor-1e-9) or ((not left) and target>cursor+1e-9) do
   local found={};local next_cursor=cursor
   for i=0,R.CountTrackMediaItems(track)-1 do
    local item=R.GetTrackMediaItem(track,i);local pos=R.GetMediaItemInfo_Value(item,'D_POSITION')
    local ending=pos+R.GetMediaItemInfo_Value(item,'D_LENGTH')
    local connected=not seen[item] and ((left and ending>=cursor-1e-7 and pos<cursor-1e-9)
      or ((not left) and pos<=cursor+1e-7 and ending>cursor+1e-9))
    if connected then
     local take=R.GetActiveTake(item)
     if take and not R.TakeIsMIDI(take) then
      found[#found+1]={item=item,pos=pos,ending=ending}
      next_cursor=left and min(next_cursor,pos) or max(next_cursor,ending)
     end
    end
   end
   if #found==0 then return cursor,false end
   for _,entry in ipairs(found) do add(entry.item) end
   guard=guard+#found;assert(guard<=1000,'移動先のアイテムが多すぎます。')
   assert(left and next_cursor<cursor-1e-9 or not left and next_cursor>cursor+1e-9,'移動先の音声範囲を延長できません。')
   cursor=next_cursor
  end
  return cursor,true
 end
 local left_limit,left_complete=extend('left',new_start)
 local right_limit,right_complete=extend('right',new_end)
 local limited=not left_complete or not right_complete
 if relative then
  local shift=new_start-p.row.start
  if shift<0 and not left_complete then shift=left_limit-p.row.start
  elseif shift>0 and not right_complete then shift=right_limit-p.row.finish end
  new_start=p.row.start+shift;new_end=p.row.finish+shift
 else
  if not left_complete then new_start=left_limit end
  if not right_complete then new_end=right_limit end
 end
 assert(new_end>new_start+1e-10,'選択アイテム内に有効なループ範囲を確保できません。')
 return additions,new_start,new_end,limited
end

function Core.loop_adjust_step(j)
 assert(R.EnumProjects(-1,'')==j.project and R.GetProjectStateChangeCount(j.project)==j.revision,'解析中にプロジェクトが変更されました。やり直してください。')
 local p=j.plans[j.index];if not p then return true end
 local w=p.windows[j.window];local source=w.source or p
 if j.open_source~=source then
  Core.loop_audio_close(j);j.open_source=source
  if source.track_mix then
   j.accessor=assert(R.CreateTrackAudioAccessor(source.track),'トラック合成音声を取得できません。');j.buf=R.new_array(8192*source.ch)
   local a,b=R.GetAudioAccessorStartTime(j.accessor),R.GetAudioAccessorEndTime(j.accessor)
   assert(source.s+w.first/source.sr>=a-1e-8 and source.s+w.last/source.sr<=b+1e-8,'仮想トラック素材の解析範囲を取得できません。')
  elseif source.wav then j.source_file=assert(io.open(source.source_path,'rb'),'元WAVを開けません。')
  else
   j.accessor=assert(R.CreateTakeAudioAccessor(source.take),'音声を取得できません。');j.buf=R.new_array(8192*source.ch)
   local a,b=R.GetAudioAccessorStartTime(j.accessor),R.GetAudioAccessorEndTime(j.accessor)
   assert(source.s+w.first/source.sr>=a-1e-8 and source.s+w.last/source.sr<=b+1e-8,'解析範囲の音声を取得できません。')
  end
 end
 local n=min(8192,w.last-w.first-j.at)
 local audio=Core.loop_audio_read(j,source,source.s+(w.first+j.at)/source.sr,n,j.buf)
 if j.mode=='zero' then
  for _,v in ipairs(audio) do assert(finite(v),'音声に不正な値があります。');w.audio[#w.audio+1]=v end
 elseif j.mode=='preview' then
  local draw_ch=min(2,source.ch);w.draw_ch=draw_ch
  for f=0,n-1 do for c=1,draw_ch do
   local v=audio[f*source.ch+c]
   assert(finite(v),'音声に不正な値があります。');w.audio[#w.audio+1]=v
  end end
 else
  for f=0,n-1 do
   for c=1,p.ch do
    local v=audio[f*p.ch+c];assert(finite(v),'音声に不正な値があります。')
    p.bin_sum=p.bin_sum+v*v
    if p.previous[c] and p.previous[c]*v<0 then p.bin_cross=p.bin_cross+1 end
    p.previous[c]=v
   end
   p.bin_count=p.bin_count+1
   if p.bin_count==p.bin_size then
    p.features[#p.features+1]={math.sqrt(p.bin_sum/(p.bin_count*p.ch)),p.bin_cross/(p.bin_count*p.ch)}
    p.bin_sum,p.bin_cross,p.bin_count=0,0,0
   end
  end
 end
 j.at=j.at+n;j.done=j.done+n;j.progress=j.done/max(1,j.total)
 if j.at==w.last-w.first then
  if j.mode=='zero' then w.result=Core.near_zero(w.audio,source.ch,w.first,w.target,source.sr,j.direction);w.audio=nil end
  j.at=0;j.window=j.window+1
  if j.window>#p.windows then
   if j.mode=='zero' then
    p.new_start,p.new_end=p.row.start,p.row.finish
    for _,window in ipairs(p.windows) do
     local src=window.source or p;local result_time=src.s+window.result/src.sr
     if window.edge=='start' then p.new_start=result_time else p.new_end=result_time end
    end
    if j.relative then
     local duration=p.row.finish-p.row.start
     if j.edge=='start' then p.new_end=p.new_start+duration else p.new_start=p.new_end-duration end
    end
   elseif j.mode=='period' then
    local a,b,period,confidence,anchor=Core.period_fit(p.features,p.feature_rate,p.row.start,p.row.finish,p.analysis_start,p.analysis_end,j.edge~=nil)
    if j.edge then
     local t=j.edge=='start' and p.row.start or p.row.finish
     local phase=(t-anchor)/period;local nearest=floor(phase+.5)
     local tolerance=max(1/p.sr,2/p.feature_rate)/period
     local k
     if abs(phase-nearest)<=tolerance then k=nearest+j.direction
     else k=j.direction==1 and floor(phase)+1 or math.ceil(phase)-1 end
     a,b=p.row.start,p.row.finish
     if j.edge=='start' then a=anchor+k*period else b=anchor+k*period end
    end
    p.new_start=Core.loop_align_time(p,a,'start');p.new_end=Core.loop_align_time(p,b,'finish')
    if j.edge then
     if j.relative then
      local duration=p.row.finish-p.row.start
      if j.edge=='start' then p.new_end=p.new_start+duration else p.new_start=p.new_end-duration end
     elseif j.edge=='start' then p.new_end=p.row.finish else p.new_start=p.row.start end
    end
    p.period,p.confidence=period,confidence;p.features=nil
   end
   if j.mode~='preview' then
    p.auto_select,p.new_start,p.new_end,p.limited=Core.loop_extension_items(j.project,p,p.new_start,p.new_end,j.relative)
   end
   Core.loop_audio_close(j);j.index=j.index+1;j.window=1
  end
 end
 return j.index>#j.plans
end

function Core.loop_adjust_commit(j)
 assert(R.EnumProjects(-1,'')==j.project and R.GetProjectStateChangeCount(j.project)==j.revision,'プロジェクトが変更されました。')
 for _,p in ipairs(j.plans) do
  for _,snapshot in ipairs(p.snapshots or {{item=p.item,take=p.take}}) do
   if R.ValidatePtr2 then assert(R.ValidatePtr2(j.project,snapshot.item,'MediaItem*'),'解析したアイテムが削除されました。') end
   assert(R.GetActiveTake(snapshot.item)==snapshot.take,'解析したアイテムのアクティブテイクが変更されました。')
   if snapshot.pos then
    local pos=R.GetMediaItemInfo_Value(snapshot.item,'D_POSITION');local ending=pos+R.GetMediaItemInfo_Value(snapshot.item,'D_LENGTH')
    assert(abs(pos-snapshot.pos)<1e-12 and abs(ending-snapshot.ending)<1e-12 and abs(R.GetMediaItemTakeInfo_Value(snapshot.take,'D_STARTOFFS')-snapshot.startoffs)<1e-12,'解析したアイテムの位置または素材範囲が変更されました。')
   end
  end
 end
 R.Undo_BeginBlock2(j.project)
 local ok,err=xpcall(function()
  for _,p in ipairs(j.plans) do local r=p.row
   assert(R.SetProjectMarker3(j.project,r.id,true,p.new_start,p.new_end,r.raw,r.color),'サステインの更新に失敗しました。')
  end
  local selected={};j.auto_selected_count=0
  for _,p in ipairs(j.plans) do for _,item in ipairs(p.auto_select or {}) do if not selected[item] then
   selected[item]=true
   if not R.IsMediaItemSelected or not R.IsMediaItemSelected(item) then j.auto_selected_count=j.auto_selected_count+1 end
   R.SetMediaItemSelected(item,true)
  end end end
 end,debug.traceback)
 if not ok then
  local restored=true
  for _,p in ipairs(j.plans) do local r=p.row
   if not R.SetProjectMarker3(j.project,r.id,true,r.start,r.finish,r.raw,r.color) then restored=false end
  end
  if not restored then err=err..'\n一部を復元できませんでした。REAPERのUndoで戻してください。' end
 end
 R.Undo_EndBlock2(j.project,'BLT LOOP RM STUDIO: '..(j.mode=='zero' and 'ゼロクロスへ調整' or '周期へ調整'),-1);R.UpdateArrange()
 if not ok then error(err,0) end
end

function Core.wave_selection_memory(current,signature,remembered,last_signature)
 current=current or {};remembered=remembered or {}
 if #current>0 and signature~=last_signature then return current,signature end
 return remembered,last_signature
end
function Core.wave_plan_memory_items(plans)
 local items={}
 for _,p in ipairs(plans or {}) do
  for _,item in ipairs(p.auto_select or {}) do items[#items+1]=item end
  for _,item in ipairs(p.result_items or {}) do items[#items+1]=item end
 end
 return items
end
function Core.undo_shortcut(key,modifiers)
 modifiers=modifiers or 0
 if (modifiers&8)~=0 then return false end
 return key==26 or (modifiers&4)~=0 and (key==90 or key==122)
end

function Core.loop_target(project,rows,selected_key,items_override)
 local items={}
 if items_override then for _,item in ipairs(items_override) do items[#items+1]=item end
 else for i=0,R.CountSelectedMediaItems(project)-1 do items[#items+1]=R.GetSelectedMediaItem(project,i) end end
 assert(#items>0,'アイテムが選択されていません')
 local row
 if selected_key then
  for _,r in ipairs(rows) do if r.key==selected_key and r.kind=='sustain' then row=r;break end end
  assert(row,'操作中のループリージョンが見つかりません。')
 else
  -- Treat only genuinely covered item spans as candidates. A global minimum /
  -- maximum would turn gaps and separate tracks into imaginary audio, allowing
  -- unrelated nearby sustain regions to be counted.
  local by_track={}
  for _,item in ipairs(items) do
   local a=R.GetMediaItemInfo_Value(item,'D_POSITION');local b=a+R.GetMediaItemInfo_Value(item,'D_LENGTH')
   local track=R.GetMediaItem_Track(item)
   if track and finite(a) and finite(b) and b>a then
    local spans=by_track[track];if not spans then spans={};by_track[track]=spans end
    spans[#spans+1]={start=a,finish=b}
   end
  end
  local components={}
  for _,spans in pairs(by_track) do
   table.sort(spans,function(a,b) return a.start==b.start and a.finish>b.finish or a.start<b.start end)
   local component
   for _,span in ipairs(spans) do
    if not component or span.start>component.finish+1e-7 then
     component={start=span.start,finish=span.finish};components[#components+1]=component
    else component.finish=max(component.finish,span.finish) end
   end
  end
  local matches={}
  for _,r in ipairs(rows) do
   if r.kind=='sustain' then for _,component in ipairs(components) do
    if r.start>=component.start-1e-8 and r.finish<=component.finish+1e-8 then matches[#matches+1]=r;break end
   end end
  end
  assert(#matches>0,'選択アイテム範囲に収まるループリージョンがありません')
  assert(#matches==1,'選択アイテム範囲にループリージョンが複数存在しています！')
  row=matches[1]
 end
 return row,items
end

function Core.virtual_loop_items(project,row,seeds,margin)
 assert(row and row.kind=='sustain' and row.finish>row.start,'対象のサステインリージョンが不正です。')
 assert(type(seeds)=='table' and #seeds>0,'波形を見る音声アイテムを選択してください。')
 margin=max(0,finite(margin) and margin or 0)
 local seed_set,track={}
 for _,item in ipairs(seeds) do
  if not R.ValidatePtr2 or R.ValidatePtr2(project,item,'MediaItem*') then
   local take=R.GetActiveTake(item);local pos=R.GetMediaItemInfo_Value(item,'D_POSITION')
   local ending=pos+R.GetMediaItemInfo_Value(item,'D_LENGTH')
   if take and not R.TakeIsMIDI(take) and row.start<ending-1e-9 and row.finish>pos+1e-9 then
    local item_track=R.GetMediaItem_Track(item)
    assert(not track or track==item_track,'対象リージョンと重なる音声アイテムは同じトラックから選択してください。')
    track=item_track;seed_set[item]=true
   end
  end
 end
 assert(track,'選択したサステインと重なる音声アイテムを選択してください。')
 local all={}
 for i=0,R.CountTrackMediaItems(track)-1 do
  local item=R.GetTrackMediaItem(track,i);local take=R.GetActiveTake(item)
  if take and not R.TakeIsMIDI(take) then
   local pos=R.GetMediaItemInfo_Value(item,'D_POSITION');local length=R.GetMediaItemInfo_Value(item,'D_LENGTH')
   if finite(pos) and finite(length) and length>0 then all[#all+1]={item=item,pos=pos,ending=pos+length} end
  end
 end
 table.sort(all,function(a,b) return a.pos==b.pos and a.ending>b.ending or a.pos<b.pos end)
 local components={};local component
 for _,entry in ipairs(all) do
  if not component or entry.pos>component.ending+1e-7 then
   component={start=entry.pos,ending=entry.ending,items={entry},has_seed=seed_set[entry.item]==true}
   components[#components+1]=component
  else
   component.items[#component.items+1]=entry
   component.ending=max(component.ending,entry.ending)
   component.has_seed=component.has_seed or seed_set[entry.item]==true
  end
 end
 local chosen
 for _,candidate in ipairs(components) do if candidate.has_seed then
  assert(not chosen,'選択アイテムが離れた複数の素材群に分かれています。対象を分けて選択してください。')
  chosen=candidate
 end end
 assert(chosen,'選択アイテムを対象トラック上で確認できませんでした。')
 local wanted_start=max(0,row.start-margin);local wanted_end=row.finish+margin
 assert(chosen.start<=wanted_start+1e-7 and chosen.ending>=wanted_end-1e-7,
  'サステイン全体を覆う、隙間のない連続音声アイテムを同じトラックに配置してください。')
 local items={};for _,entry in ipairs(chosen.items) do items[#items+1]=entry.item end
 assert(#items<=1000,'仮想素材として扱える連続アイテムは1000個までです。')
 return items
end

function Core.track_mix_source(project,items)
 assert(type(items)=='table' and #items>0,'仮想トラック素材に音声アイテムがありません。')
 local track,sr_hint,ch_hint,min_time,max_time
 min_time,max_time=math.huge,-math.huge
 for _,item in ipairs(items) do
  local take=R.GetActiveTake(item)
  assert(take and not R.TakeIsMIDI(take),'MIDIではなく音声アイテムを選択してください。')
  local item_track=R.GetMediaItem_Track(item)
  assert(not track or track==item_track,'仮想素材として扱う音声アイテムは同じトラックから選択してください。')
  track=track or item_track
  local pos=R.GetMediaItemInfo_Value(item,'D_POSITION');local ending=pos+R.GetMediaItemInfo_Value(item,'D_LENGTH')
  assert(finite(pos) and finite(ending) and ending>pos,'音声アイテムの位置または長さが不正です。')
  min_time=min(min_time,pos);max_time=max(max_time,ending)
  local source=R.GetMediaItemTake_Source(take)
  if source then
   local source_sr=optional_number(R.GetMediaSourceSampleRate,source)
   local source_ch=optional_number(R.GetMediaSourceNumChannels,source)
   if source_sr and source_sr>0 then sr_hint=sr_hint or source_sr end
   if source_ch and source_ch>=1 then ch_hint=max(ch_hint or 1,source_ch) end
  end
 end
 local sr
 if type(R.GetSetProjectInfo)=='function' then
  local use=optional_number(R.GetSetProjectInfo,project,'PROJECT_SRATE_USE',0,false)
  if use and use~=0 then sr=optional_number(R.GetSetProjectInfo,project,'PROJECT_SRATE',0,false) end
 end
 if not sr and type(R.GetAudioDeviceInfo)=='function' then
  local ok,got,value=pcall(R.GetAudioDeviceInfo,'SRATE')
  if ok and got then sr=tonumber(value) end
 end
 sr=finite(sr) and sr>0 and sr or sr_hint or 48000
 assert(sr>=8000 and sr<=384000,'仮想トラック素材のサンプルレートを取得できません。')
 local ch=optional_number(R.GetMediaTrackInfo_Value,track,'I_NCHAN')
 ch=finite(ch) and ch>=1 and ch or ch_hint or 2
 ch=floor(ch+.5);assert(ch>=1 and ch<=64,'仮想トラック素材のチャンネル数を取得できません。')
 local lo=math.ceil(min_time*sr-1e-7);local hi=floor(max_time*sr+1e-7)
 assert(hi>lo,'仮想トラック素材から音声範囲を取得できません。')
 return {track_mix=true,track=track,s=0,sr=sr,ch=ch,pos=min_time,ending=max_time,lo=lo,hi=hi}
end

function Core.loop_move_plan(project,rows,selected_key,edge,delta,relative,items_override)
 assert(edge=='start' or edge=='finish','移動する境界が不正です。')
 assert(finite(delta),'ドラッグ移動量が不正です。')
 local row,items=Core.loop_target(project,rows,selected_key,items_override)
 local sources={};local track
 for _,item in ipairs(items) do
  local take=R.GetActiveTake(item);assert(take and not R.TakeIsMIDI(take),'音声アイテムを選択してください。')
  local item_track=R.GetMediaItem_Track(item)
  assert(not track or track==item_track,'ループ調整に使う音声アイテムは同じトラックから選択してください。')
  track=track or item_track
  local pos=R.GetMediaItemInfo_Value(item,'D_POSITION');local ending=pos+R.GetMediaItemInfo_Value(item,'D_LENGTH')
  sources[#sources+1]={item=item,take=take,track=item_track,pos=pos,ending=ending}
 end
 table.sort(sources,function(a,b) return a.pos==b.pos and a.ending>b.ending or a.pos<b.pos end)
 local min_time,max_time=sources[1].pos,sources[1].ending;local right=sources[1]
 for i=2,#sources do
  local source=sources[i]
  assert(source.pos<=max_time+1e-7,'ループ調整に使う音声アイテム間に隙間があります。')
  if source.ending>max_time then max_time=source.ending;right=source end
 end
 assert(row.start>=min_time-1e-7 and row.finish<=max_time+1e-7,'開始側と終了側の音声アイテムを両方選択してください。')
 local p={row=row,left_source=sources[1],right_source=right,sources=sources,min_time=min_time,max_time=max_time}
 p.new_start,p.new_end=row.start,row.finish
 if relative then p.new_start=row.start+delta;p.new_end=row.finish+delta
 elseif edge=='start' then p.new_start=row.start+delta else p.new_end=row.finish+delta end
 p.auto_select,p.new_start,p.new_end,p.limited=Core.loop_extension_items(project,p,p.new_start,p.new_end,relative)
 return p
end

function Core.seam_drag_delta(dx,seconds_per_px)
 assert(finite(dx) and finite(seconds_per_px) and seconds_per_px>0,'波形ドラッグ量が不正です。')
 return clamp(-dx*seconds_per_px,-Core.SEAM_DRAG_SECONDS,Core.SEAM_DRAG_SECONDS)
end

function Core.seam_wave_shift(delta,half_width)
 assert(finite(delta) and finite(half_width) and half_width>0,'波形表示位置が不正です。')
 return -delta/Core.SEAM_SECONDS*half_width
end

function Core.seam_boundary_delta(delta,edge,start,finish,relative)
 assert(finite(delta) and finite(start) and finite(finish) and finish>start,'サステイン範囲が不正です。')
 if relative then return delta end
 local limit=finish-start-1e-6
 return edge=='finish' and max(delta,-limit) or edge=='start' and min(delta,limit) or error('移動する境界が不正です。',0)
end

function Core.seam_geometry(x,width)
 assert(finite(x) and finite(width) and width>12,'波形表示幅が不正です。')
 local left=x+6;local right=x+width-6;local middle=(left+right)/2
 return left,middle,right,(right-left)/2
end

function Core.adjusted_loop_bounds(plans)
 assert(type(plans)=='table' and #plans>0,'調整したサステイン範囲がありません。')
 local first,last
 for _,p in ipairs(plans) do
  local start=p.new_start or p.loop_start or p.s or p.row and p.row.start
  local finish=p.new_end or p.loop_finish or p.e or p.row and p.row.finish
  assert(finite(start) and finite(finish) and finish>start,'調整後のサステイン範囲が不正です。')
  first=first and min(first,start) or start;last=last and max(last,finish) or finish
 end
 return first,last
end
function Core.loop_audition_timing(start,finish,rate,lead_seconds)
 assert(finite(start) and finite(finish) and finish>start and finite(rate) and rate>0,'自動再生範囲を取得できません。')
 lead_seconds=finite(lead_seconds) and max(.75,lead_seconds) or .75
 local play_start=max(start,finish-lead_seconds)
 return play_start,(finish-play_start)/rate+.15,1
end
function Core.crossfade_audition_lead(plans)
 local lead=.75
 for _,p in ipairs(plans or {}) do
  local finish=p.loop_finish or p.e or p.row and p.row.finish
  local crossfade_start=p.output_start
  if finite(finish) and finite(crossfade_start) and crossfade_start<finish then lead=max(lead,finish-crossfade_start) end
 end
 return lead
end

function Core.seam_start(project,rows,selected_key,items_override)
 local row,items=Core.loop_target(project,rows,selected_key,items_override)
 local j=Core.loop_adjust_start(project,{row},'preview',nil,nil,items,false)
 local base=j.plans[1];local plans={};j.total=0
 for _,window in ipairs(base.windows) do
  local p={}
  for key,value in pairs(base) do if key~='windows' then p[key]=value end end
  p.windows={window};p.preview_side=window.edge
  p.preview_origin=window.edge=='finish' and row.finish or row.start
  plans[#plans+1]=p;j.total=j.total+window.last-window.first
 end
 j.plans=plans;j.index=1;j.window=1;j.at=0;j.done=0
 return j
end

if ...=='core_test' then return Core end

local SECTION=Core.SECTION
local W,H=980,926
local A={status='時間選択から区間を追加し、WAVへ書き出します。',warning=false,content_dirty=true,wave_dirty=true,closed=false,
 rows={},selected=nil,selected_regions={},poll_at=0,active=true,sr=48000,bits=24,channels=2,encoding='UTF-8',
 directory='',filename='Mix',busy=false,progress=0,use_default_directory=false,use_default_filename=false,use_format=false,
 embed_markers=true,embed_regions=true,exclude_selected_region=false,embed_loop_region=true,
 add_mode='selection',length=1,length_values={seconds=1,beats=1,bars=1,grid=1},unit='seconds',
 interval=0,interval_values={seconds=0,beats=0,bars=0,grid=0},interval_unit='seconds',count=1,omit_name=true,
 xfade_seconds=.020,relative_lock=false,auto_audition=false,wave_items={},audition=nil,period_notice=nil,
 loop_enable={crossfade=false,zero=false,period=false}}
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
local widget_count=0
local IME={active=false,bounds={}}
local down_last,pressed=false,nil
local mouse_x,mouse_y=-1,-1
local hover_hint=""
local hover_detail_text,hover_detail_since=nil,0

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
  widget_count=widget_count+1
  local widget=widgets[widget_count]
  if not widget then widget={};widgets[widget_count]=widget end
  widget.id=id;widget.x=x;widget.y=y;widget.w=w;widget.h=h
  widget.fn=fn;widget.hint=hint;widget.enabled=enabled~=false;widget.field=nil
  if inside(x,y,w,h) and hint then hover_hint=hint end
end
local function fmt(n)
  if abs(n-floor(n+0.5))<1e-8 then return tostring(floor(n+0.5)) end
  return string.format("%.3f",n):gsub("0+$",""):gsub("%.$","")
end

local function notice(s,warn) A.status=warn and BLT.publicError(s) or tostring(s or '');A.warning=warn or false;A.status_until=R.time_precise()+7;A.content_dirty=true;wake_visuals() end
local function invalidate_wave_surface() A.wave_dirty=true;A.content_dirty=true;wake_visuals() end

-- Reuse text commands and font buckets. The UI contains many labels, so
-- rebuilding these short-lived tables on every animated frame is needlessly
-- expensive in the same way as the older BLT text renderer.
local text_queue={count=0,buckets={},order={},order_count=0,specs={},spec_scale=nil}
local function font_spec(size,kind,bold) return BLT.spec(size,kind,bold,scale) end

local function font(size,kind,bold) BLT.font(size,kind,bold,scale,fonts) end
local function queue_text(t,x,y,right,bottom,flags,size,c,kind,bold,translated)
  local fk,_,_,key=font_spec(size,kind,bold)
  local bucket=text_queue.buckets[key]
  if not bucket then bucket={count=0};text_queue.buckets[key]=bucket end
  if bucket.count==0 then
    text_queue.order_count=text_queue.order_count+1
    text_queue.order[text_queue.order_count]=key
  end
  bucket.count=bucket.count+1
  local cmd=bucket[bucket.count]
  if not cmd then cmd={};bucket[bucket.count]=cmd end
  cmd.text=t;cmd.translated=translated;cmd.x=x;cmd.y=y;cmd.right=right;cmd.bottom=bottom
  cmd.flags=flags or 0;cmd.size=size;cmd.kind=fk;cmd.bold=bold and true or false;cmd.c=c or C.text
  text_queue.count=text_queue.count+1
end
local function label(text,x,y,size,c,kind,w,h,flags,bold,literal)
  local t=literal and tostring(text) or Language.message(text)
  queue_text(t,sx(x),sy(y),sx(x+(w or 700)),sy(y+(h or size+8)),flags or 0,size,c,kind,bold,t~=tostring(text))
end

local function measure(text,size,kind,bold) font(size,kind,bold);return BLT.metricsFor(Language.message(text))/scale end

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
local function draw_hover_tooltip(text)
 if type(text)~='string' or not text:find('\n',1,true) then hover_detail_text=nil;return end
 local now=R.time_precise()
 if hover_detail_text~=text then hover_detail_text=text;hover_detail_since=now;wake_visuals(now);return end
 if now-hover_detail_since<.7 then wake_visuals(now);return end
 local lines={};local widest=0
 for s in (text..'\n'):gmatch('(.-)\n') do
  lines[#lines+1]=s;widest=max(widest,measure(s,16.5,1,false))
 end
 local w=min(920,widest+32);local h=22+#lines*27
 local x=clamp(mouse_x+14,10,W-w-10);local y=mouse_y-h-12
 if y<92 then y=min(H-h-10,mouse_y+18) end
 flush_text_queue()
 rect(x-5,y-5,w+10,h+10,C.bg,.42);cut_panel(x,y,w,h,7,C.field,.98,C.edge2,.88,true)
 line(x+10,y,x+w-12,y,C.accent2,.78)
 for i,s in ipairs(lines) do label(s,x+16,y+10+(i-1)*27,16.5,i==1 and C.accent2 or C.text,1,w-32,24,0,i==1) end
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
  chameleonPressed=false,resizeCursors={},resizeCursorMode=nil,contentCursorMode=nil,titleH=26,windowTitle='BLT LOOP RM STUDIO',titleText='L O O P   R M   S T U D I O',
  minW=784,minH=790,mint={0.38,0.88,0.72},ice={0.65,0.895,1.0},red={1.0,0.27,0.34},
  isWindows=R.GetOS():match("Win")~=nil,resizeEdge=6,resizeCornerBand=8,resizeCornerSpan=24,resizeTopLeftGuard=30,resizeTopRightGuard=110,
  tooltipHover=nil,tooltipSince=0,tooltipVisible=false,tooltipDelay=.70,resetFont=nil,resetArrowW=nil,resetArrowH=nil,
  cursorId={we=32644,ns=32645,nwse=32642,nesw=32643,arrow=32512,hand=32649}}
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

local function ime_color(c,alpha)
 return (floor(c[1]*255+.5)<<24)|(floor(c[2]*255+.5)<<16)|(floor(c[3]*255+.5)<<8)|floor((alpha or 1)*255+.5)
end
function IME.stop(restore)
 IME.active=false;IME.ctx=nil;IME.font=nil;IME.id=nil;IME.metrics=nil
 UI.dirty();next_draw_time=0
 if restore and type(R.JS_Window_SetFocus)=='function' then local hwnd=gfx_window_handle();if hwnd then R.JS_Window_SetFocus(hwnd) end end
end
function IME.open(id)
 if not BLT.requireInput(IME) then return false end
 local ok,err=pcall(function()
  local I=IME.api
  IME.ctx=I.CreateContext('BLT LOOP RM STUDIO input')
  IME.font=I.CreateFont(fonts[1]);I.Attach(IME.ctx,IME.font)
  IME.active=true;IME.frames=0;IME.id=id;IME.metrics=nil;UI.dirty();next_draw_time=0
 end)
 if not ok then IME.stop(false);notice('日本語入力欄を初期化できません。\n'..tostring(err),true) end
 return ok
end
function IME.frame()
 if not IME.active then return end
 local e=A.edit
 if not e or e.id~=IME.id or e.spec then IME.stop(false);return end
 local b=IME.bounds[IME.id];if not b then return end
 local I,ctx=IME.api,IME.ctx
 local nx,ny=gfx.clienttoscreen(sx(b.x),sy(b.y));local ex,ey=gfx.clienttoscreen(sx(b.x+b.w),sy(b.y+b.h))
 local x,y=I.PointConvertNative(ctx,nx,ny);local x2,y2=I.PointConvertNative(ctx,ex,ey)
 local w,h=abs(x2-x),abs(y2-y);x,y=min(x,x2),min(y,y2)
 local unit=w/b.w;local size=max(8,13*unit);local focus_now=IME.frames==1
 I.SetNextWindowPos(ctx,x,y,I.Cond_Always);I.SetNextWindowSize(ctx,w,h,I.Cond_Always)
 if focus_now then I.SetNextWindowFocus(ctx) end
 I.PushStyleVar(ctx,I.StyleVar_WindowPadding,0,0);I.PushStyleVar(ctx,I.StyleVar_WindowMinSize,1,1)
 I.PushStyleVar(ctx,I.StyleVar_WindowRounding,0);I.PushStyleVar(ctx,I.StyleVar_WindowBorderSize,0)
 I.PushStyleVar(ctx,I.StyleVar_FrameRounding,0);I.PushStyleVar(ctx,I.StyleVar_FrameBorderSize,0)
 I.PushStyleVar(ctx,I.StyleVar_FramePadding,max(2,10*unit),max(0,(h-size)/2))
 I.PushStyleColor(ctx,I.Col_WindowBg,ime_color(C.field));I.PushStyleColor(ctx,I.Col_FrameBg,ime_color(C.field))
 I.PushStyleColor(ctx,I.Col_Text,ime_color(C.text));I.PushStyleColor(ctx,I.Col_TextDisabled,ime_color(C.faint))
 I.PushStyleColor(ctx,I.Col_TextSelectedBg,ime_color(C.accent3));I.PushFont(ctx,IME.font,size)
 local flags=I.WindowFlags_NoDecoration|I.WindowFlags_NoMove|I.WindowFlags_NoSavedSettings|I.WindowFlags_NoDocking
 local shown=I.Begin(ctx,'BLT Text##'..IME.id,nil,flags);local finish,cancel,focused=false,false,true
 if shown then
  local dpi=I.GetWindowDpiScale(ctx);local m=IME.metrics
  if not m or m.scale~=scale or m.unit~=unit or m.dpi~=dpi then
   local sample='あいうえお漢字ABC012345';local target=measure(sample,13,1,false)*unit;local measured=I.CalcTextSize(ctx,sample)
   m={scale=scale,unit=unit,dpi=dpi,size=measured>0 and clamp(size*target/measured,1,96) or size};IME.metrics=m
  end
  I.PopFont(ctx);I.PushFont(ctx,IME.font,m.size);I.PushStyleVar(ctx,I.StyleVar_FramePadding,max(2,10*unit),max(0,(h-I.GetTextLineHeight(ctx))/2))
  I.SetNextItemWidth(ctx,w);if focus_now then I.SetKeyboardFocusHere(ctx) end
  local _,text=I.InputTextWithHint(ctx,'##text','',e.text,0)
  finish=I.IsItemDeactivated(ctx)
  cancel=finish and I.IsKeyPressed(ctx,I.Key_Escape,false)
  if text~=e.text then
   if #text<=4096 and utf8.len(text) and not text:find('[%z\1-\31\127]') then e.text=text;UI.dirty()
   else UI.flash(e.id);notice('入力できない制御文字、または長すぎる文字列です。元の値へ戻しました。',true) end
  end
  local list=I.GetWindowDrawList(ctx);local lx,ly=I.GetItemRectMin(ctx);local rx,ry=I.GetItemRectMax(ctx)
  I.DrawList_AddRectFilled(list,lx,ry-max(.5,unit),rx,ry,ime_color(C.accent2,.65));focused=I.IsWindowFocused(ctx)
  I.PopStyleVar(ctx);I.End(ctx)
 end
 I.PopFont(ctx);I.PopStyleColor(ctx,5);I.PopStyleVar(ctx,7);IME.frames=IME.frames+1
 if cancel then A.edit=nil;IME.stop(true)
 elseif finish then if UI.commit_edit() then IME.stop(true) end
 elseif IME.frames>2 and not focused then UI.commit_edit() end
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
    Chrome.resizeCursorMode=kind;Chrome.contentCursorMode=nil
  elseif Chrome.resizeCursorMode then
    local cursor=Chrome.resizeCursors.arrow
    if not cursor then cursor=R.JS_Mouse_LoadCursor(Chrome.cursorId.arrow); Chrome.resizeCursors.arrow=cursor end
    if cursor then R.JS_Mouse_SetCursor(cursor) end
    Chrome.resizeCursorMode=nil
  end
end
local function set_content_cursor(hand)
  if not Chrome.isWindows or Chrome.resizeCursorMode then return end
  local kind=hand and 'hand' or 'arrow'
  local changed=Chrome.contentCursorMode~=kind
  -- gfx windows restore their default cursor during the message loop. Keep the
  -- hand cursor asserted on every hover/drag frame; restore the arrow once when
  -- leaving the waveform. JS_Mouse_SetCursor remains as a Windows fallback.
  if hand or changed then gfx.setcursor(Chrome.cursorId[kind]) end
  local cursor=Chrome.resizeCursors[kind]
  if not cursor then cursor=R.JS_Mouse_LoadCursor(Chrome.cursorId[kind]);Chrome.resizeCursors[kind]=cursor end
  if cursor and (hand or changed) then R.JS_Mouse_SetCursor(cursor) end
  Chrome.contentCursorMode=kind
end
local function titlebar_cleanup() set_resize_cursor(nil);set_content_cursor(false) end

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

local function kind_color(kind)
 return kind=='sustain' and C.accent2 or kind=='marker' and C.muted or kind=='invalid' and C.red or C.focus
end
function UI.cleanup_raw()
 if not A.own_raw or not A.raw then A.raw=nil;A.own_raw=false;A.raw_delete_at=nil;return true end
 local path=A.raw
 if type(R.reduce_open_files)=='function' then pcall(R.reduce_open_files,2) end
 local called,removed=pcall(os.remove,path)
 if not Core.exists(path) or (called and removed) then
  A.raw=nil;A.own_raw=false;A.raw_delete_at=nil
  return true
 end
 A.raw_delete_at=R.time_precise()+2
 return false
end
function UI.safe(fn)
 local ok,err=xpcall(fn,debug.traceback)
 if not ok then
  if A.render_snapshot and BLT.cleanup(Core.restore_render,A.render_snapshot) then A.render_snapshot=nil end
  if A.job and BLT.cleanup(Core.copy_abort,A.job) then A.job=nil end
  if A.xjob and BLT.cleanup(Core.crossfade_abort,A.xjob) then A.xjob=nil end
  if A.ajob and BLT.cleanup(Core.loop_audio_close,A.ajob) then A.ajob=nil end
  if A.pjob and BLT.cleanup(Core.loop_audio_close,A.pjob) then A.pjob=nil end
  if A.audition and UI.stop_loop_audition then BLT.cleanup(UI.stop_loop_audition,true) end
  BLT.cleanup(Core.retry_file_deletes,true)
  A.busy=false;A.seam_hold=nil;A.render_batch=nil
  local cleanup_ok,cleaned=BLT.cleanup(UI.cleanup_raw)
  cleaned=cleanup_ok and cleaned
  local msg=BLT.publicError(err)
  if not cleaned then msg=msg..'\n\n一時WAVを削除できませんでした。終了前に再試行します。' end
  notice(msg,true);BLT.recoverInput(A,msg)
 end
 return ok
end
function UI.dirty() A.content_dirty=true;wake_visuals() end
function UI.geometry()
 scale=min(gfx.w/W,(gfx.h-Chrome.titleH)/H);ox=(gfx.w-W*scale)/2;oy=Chrome.titleH+(gfx.h-Chrome.titleH-H*scale)/2-22*scale;BLT.viewport(scale,gfx.ext_retina or 1)
 mouse_x=(gfx.mouse_x-ox)/scale;mouse_y=(gfx.mouse_y-oy)/scale
end
function UI.selected()
 for _,row in ipairs(A.rows) do if row.key==A.selected then return row end end
end
function UI.selected_rows()
 local wanted={};for _,key in ipairs(A.selected_regions or {}) do wanted[key]=true end
 local rows={};for _,row in ipairs(A.rows) do if wanted[row.key] and row.isr and row.finish>row.start then rows[#rows+1]=row end end
 return rows
end
local function valid_audio_item(project,item)
 if not item or R.ValidatePtr2 and not R.ValidatePtr2(project,item,'MediaItem*') then return false end
 local take=R.GetActiveTake(item)
 return take~=nil and not R.TakeIsMIDI(take)
end
local function selected_audio_items(project)
 local current={}
 for i=0,R.CountSelectedMediaItems(project)-1 do
  local item=R.GetSelectedMediaItem(project,i)
  if valid_audio_item(project,item) then current[#current+1]=item end
 end
 local keys={};for _,item in ipairs(current) do keys[#keys+1]=tostring(item) end
 return current,table.concat(keys,':')
end
function UI.wave_target_items(project,allow_empty)
 project=project or A.project
 local current,signature=selected_audio_items(project)
 A.wave_items,A.last_wave_selection=Core.wave_selection_memory(current,signature,A.wave_items,A.last_wave_selection)
 local valid={}
 for _,item in ipairs(A.wave_items or {}) do if valid_audio_item(project,item) then valid[#valid+1]=item end end
 A.wave_items=valid
 if not allow_empty then assert(#valid>0,'波形を見る音声アイテムを選択してください。') end
 return valid
end
function UI.remember_wave_items(items)
 local remembered,seen={},{}
 local function add(item)
  if not seen[item] and valid_audio_item(A.project,item) then seen[item]=true;remembered[#remembered+1]=item end
 end
 for _,item in ipairs(A.wave_items or {}) do add(item) end
 for _,item in ipairs(items or {}) do add(item) end
 A.wave_items=remembered
end
function UI.remember_plan_items(plans)
 UI.remember_wave_items(Core.wave_plan_memory_items(plans))
 local current,signature=selected_audio_items(A.project)
 if #current>0 then A.last_wave_selection=signature end
end
function UI.loop_target_items(project,mode,allow_empty,selected_key)
 local seeds=UI.wave_target_items(project,allow_empty)
 if #seeds==0 then return seeds end
 local row=Core.loop_target(project,A.rows,selected_key,seeds)
 local margin=mode=='zero' and .1 or mode=='drag' and Core.SEAM_DRAG_SECONDS or 0
 local items=Core.virtual_loop_items(project,row,seeds,margin)
 return items,row
end
function UI.refresh_loop_enable()
 local state={crossfade=false,zero=false,period=false}
 local seeds=UI.wave_target_items(A.project,true)
 if #seeds==0 then A.loop_enable=state;return end
 local ok,row=pcall(Core.loop_target,A.project,A.rows,nil,seeds)
 if not ok then A.loop_enable=state;return end
 local function validate_adjust(mode)
  local margin=mode=='period' and 0 or .1
  local items=Core.virtual_loop_items(A.project,row,seeds,margin)
  Core.loop_adjust_start(A.project,{row},mode,nil,nil,items,false)
  return true
 end
 state.zero=pcall(validate_adjust,'zero')
 state.period=pcall(validate_adjust,'period')
 state.crossfade=pcall(function()
  local seconds=Core.crossfade_fit(A.project,{row},A.xfade_seconds,seeds)
  Core.crossfade_plan(A.project,{row},seconds,seeds)
 end)
 A.loop_enable=state
end
function UI.bounds()
 local first,last
 for _,row in ipairs(UI.selected_rows()) do first=first and min(first,row.start) or row.start;last=last and max(last,row.finish) or row.finish end
 return first or 0,last or 0
end
function UI.options(selected_key)
 return {encoding=A.encoding,selected_key=selected_key,embed_markers=A.embed_markers,embed_regions=A.embed_regions,
  exclude_selected_region=A.exclude_selected_region,embed_loop_region=A.embed_loop_region}
end
function UI.preflight()
 local selected=UI.selected_rows();local start,ending=UI.bounds()
 A.start,A.finish=start,ending;A.plans={}
 if #selected==0 or not finite(start) or not finite(ending) or ending<=start then
  A.plan=nil
  A.problem=nil
  return
 end
 if A.format_problem then A.plan=nil;A.problem=A.format_problem;return end
 local ok,result=pcall(function()
  local plans={}
  for _,row in ipairs(selected) do
   local p=Core.plan(A.rows,row.start,row.finish,A.format.sr,UI.options(row.key));p.target_row=row;plans[#plans+1]=p
  end
  return plans
 end)
 A.plans=ok and result or {};A.plan=A.plans[1];A.problem=not ok and BLT.publicError(result) or nil
end
function UI.load_project(project)
 if A.project~=project then
  if A.audition and UI.stop_loop_audition then UI.stop_loop_audition(true) end
  if A.pjob then Core.loop_audio_close(A.pjob);A.pjob=nil end
  A.seam=nil;A.seam_problem=nil;A.seam_refreshing=false;A.preview_signature=nil;A.seam_drag=nil;A.seam_hold=nil;A.wave_items={};A.last_wave_selection=nil
  A.loop_enable={crossfade=false,zero=false,period=false}
 end
 A.project=project;A.selected=nil;A.selected_regions={};A.region_selection_signature=nil;A.region_selection_problem=nil
 local function get(key,default) local _,v=R.GetProjExtState(project,SECTION,key);return v~='' and v or default end
 A.filename=get('filename','Mix');A.directory=get('directory','')
 if A.directory=='' then A.directory=R.GetProjectPathEx(project,'')..'/BLT Renders' end
 A.encoding=get('encoding','UTF-8');if A.encoding~='UTF-8' and A.encoding~='CP932' then A.encoding='UTF-8' end
 for k,default in pairs({sr=48000,bits=24,channels=2}) do A[k]=tonumber(get(k,tostring(default))) or default end
 if A.sr<8000 or A.sr>384000 or A.sr%1~=0 then A.sr=48000 end
 if A.bits~=16 and A.bits~=24 and A.bits~=32 then A.bits=24 end
 local channel_ok=false;for _,v in ipairs(Core.channel_options) do if A.channels==v then channel_ok=true end end
 if not channel_ok then A.channels=2 end
 A.use_default_directory=get('use_default_directory','false')=='true'
 A.use_default_filename=get('use_default_filename','false')=='true'
 A.embed_markers=get('embed_markers','true')=='true'
 A.embed_regions=get('embed_regions','true')=='true'
 A.exclude_selected_region=get('exclude_selected_region','false')=='true'
 A.embed_loop_region=get('embed_loop_region','true')=='true'
 A.omit_name=get('omit_name','true')=='true'
 A.auto_audition=get('auto_audition','false')=='true'
 A.xfade_seconds=tonumber(get('xfade_seconds','.020'))
 if not finite(A.xfade_seconds) or A.xfade_seconds<.000001 or A.xfade_seconds>10 then A.xfade_seconds=.020 end
 A.xfade_seconds=Core.normalize_spec_number(A.xfade_seconds,{.000001,10,false,1,6,nil,false,6})
 A.edit=nil;A.name_dialog=nil
 A.use_format=get('use_format','false')=='true';A.popup=nil
 A.add_mode=get('add_mode','selection');if not ({selection=true,items=true,itemgroups=true,itemspan=true,cursor=true})[A.add_mode] then A.add_mode='selection' end
 A.unit=get('unit','seconds');if not Core.length_specs[A.unit] then A.unit='seconds' end
 A.length_values={}
 for unit,spec in pairs(Core.length_specs) do
  local value=tonumber(get('length_'..unit,''))
  if not finite(value) or value<spec[1] or value>spec[2] or spec[3] and value%1~=0 then value=spec[6] end
  A.length_values[unit]=Core.normalize_spec_number(value,spec)
 end
 A.length=A.length_values[A.unit]
 A.interval_unit=get('interval_unit','seconds');if not Core.interval_specs[A.interval_unit] then A.interval_unit='seconds' end
 A.interval_values={}
 for unit,spec in pairs(Core.interval_specs) do
  local value=tonumber(get('interval_'..unit,''))
  if not finite(value) or value<spec[1] or value>spec[2] or spec[3] and value%1~=0 then value=0 end
  A.interval_values[unit]=Core.normalize_spec_number(value,spec)
 end
 A.interval=A.interval_values[A.interval_unit]
 A.count=tonumber(get('count','1')) or 1;if not finite(A.count) or A.count<1 or A.count>1000 or A.count%1~=0 then A.count=1 end
 A.relative_lock=get('relative_lock','false')=='true'
 A.revision=nil
end
function UI.save_settings()
 if not A.project or (R.ValidatePtr and not R.ValidatePtr(A.project,'ReaProject*')) then return end
 A.length_values[A.unit]=A.length
 A.interval_values[A.interval_unit]=A.interval
 for _,k in ipairs({'filename','directory','sr','bits','channels','encoding','use_default_directory','use_default_filename','use_format','embed_markers','embed_regions','exclude_selected_region','embed_loop_region','omit_name','xfade_seconds','add_mode','unit','interval_unit','count','relative_lock','auto_audition'}) do
  local val=tostring(A[k]);local _,old=R.GetProjExtState(A.project,SECTION,k)
  if old~=val then R.SetProjExtState(A.project,SECTION,k,val) end
 end
 for unit,value in pairs(A.length_values) do
  local key='length_'..unit;local val=tostring(value);local _,old=R.GetProjExtState(A.project,SECTION,key)
  if old~=val then R.SetProjExtState(A.project,SECTION,key,val) end
 end
 for unit,value in pairs(A.interval_values) do
  local key='interval_'..unit;local val=tostring(value);local _,old=R.GetProjExtState(A.project,SECTION,key)
  if old~=val then R.SetProjExtState(A.project,SECTION,key,val) end
 end
end
function UI.set_unit(unit)
 assert(Core.length_specs[unit],'基準幅の単位が不正です。')
 A.length_values[A.unit]=A.length;A.unit=unit;A.length=A.length_values[unit]
end
function UI.set_interval_unit(unit)
 assert(Core.interval_specs[unit],'間隔補正の単位が不正です。')
 A.interval_values[A.interval_unit]=A.interval;A.interval_unit=unit;A.interval=A.interval_values[unit]
end
function UI.set_add_mode(mode)
 assert(mode=='selection' or mode=='items' or mode=='itemspan' or mode=='itemgroups' or mode=='cursor','配置元が不正です。')
 A.add_mode=mode;A.add_kind_flash=R.time_precise();UI.refresh()
end
function UI.poll(now,force)
 if A.busy or (not force and now<A.poll_at) then return end;A.poll_at=now+.12
 local project=R.EnumProjects(-1,'')
 if project~=A.project then UI.load_project(project);force=true end
 local _,dir=R.GetSetProjectInfo_String(project,'RENDER_FILE','',false)
 local _,pattern=R.GetSetProjectInfo_String(project,'RENDER_PATTERN','',false)
 if dir~=A.default_directory or pattern~=A.default_pattern then A.default_directory=dir;A.default_pattern=pattern;UI.dirty() end
 local native_ok,native=pcall(Core.native_format,project)
 local format
 if A.use_format then format=native_ok and native or nil else format={sr=A.sr,bits=A.bits,channels=A.channels} end
 local problem=A.use_format and not native_ok and BLT.publicError(native) or nil
 local signature=problem or (format.sr..':'..format.bits..':'..format.channels)
 if signature~=A.format_signature then A.popup=nil;A.format_signature=signature;force=true;UI.dirty() end
 A.format=format;A.format_problem=problem
 local rev=R.GetProjectStateChangeCount(project)
 if force or rev~=A.revision then A.rows=Core.project_rows(project);A.revision=rev;UI.dirty() end
 local selected,selection_signature=Core.selected_project_regions(project,A.rows)
 if selection_signature~=A.region_selection_signature then
  A.selected_regions=selected;A.selected=selected[1];A.region_selection_problem=nil;A.region_selection_signature=selection_signature;force=true;UI.dirty()
 end
 local s,e=UI.bounds()
 if force or rev~=A.plan_revision or s~=A.start or e~=A.finish then UI.preflight();A.plan_revision=rev;UI.dirty() end
end
function UI.refresh() UI.save_settings();UI.poll(R.time_precise(),true) end
function UI.choose_directory()
 if R.JS_Dialog_BrowseForSaveFile then
  local ok,path=Language.save('保存先フォルダーを開き、「保存」で選択',A.directory,'このフォルダーを選択.folder','フォルダー選択用 (*.folder)\0*.folder\0')
  if (ok==1 or ok==true) and type(path)=='string' and path~='' then
   local dir=path:match('^(.*)[/\\][^/\\]*$')
   assert(dir and dir~='','保存先のディレクトリパスを取得できません。')
   if dir:match('^%a:$') then dir=dir..'\\' end
   A.directory=dir;UI.refresh()
  end
 else UI.begin_edit('field_directory',A,'directory',nil) end
end
function UI.undo(label,fn)
 assert(R.EnumProjects(-1,'')==A.project,'プロジェクトが変わりました。')
 R.Undo_BeginBlock2(A.project)
 local ok,err=xpcall(fn,debug.traceback)
 R.Undo_EndBlock2(A.project,'BLT LOOP RM STUDIO: '..label,-1);R.UpdateArrange();UI.poll(R.time_precise(),true)
 if not ok then error(err,0) end
end
function UI.project_undo()
 if A.busy then notice('処理中は元に戻せません。処理を完了または中止してください。',true);return end
 local project=R.EnumProjects(-1,'')
 if project~=A.project then UI.load_project(project) end
 local description=type(R.Undo_CanUndo2)=='function' and R.Undo_CanUndo2(project) or nil
 if type(R.Undo_CanUndo2)=='function' and (not description or description=='') then notice('元に戻せる操作がありません。',false);return end
 if A.audition then UI.stop_loop_audition(true) end
 if A.pjob then Core.loop_audio_close(A.pjob);A.pjob=nil end
 assert(type(R.Undo_DoUndo2)=='function','REAPERのUndo APIを利用できません。')
 local result=R.Undo_DoUndo2(project)
 if result==0 then notice('元に戻せる操作がありません。',false);return end
 A.preview_signature=nil;A.preview_at=0;A.seam=nil;A.seam_hold=nil;A.seam_drag=nil;A.last_wave_selection=nil
 R.UpdateArrange();UI.poll(R.time_precise(),true)
 notice('元に戻しました。'..(description and description~='' and ' '..description or ''),false)
end
function UI.add_commit(kind,ranges,names,project)
 assert(project==R.EnumProjects(-1,''),'プロジェクトが変わりました。追加をやり直してください。')
 UI.undo(Core.names[kind]..'を追加',function()
  local c=kind_color(kind);local native=R.ColorToNative(floor(c[1]*255),floor(c[2]*255),floor(c[3]*255))|0x1000000
  local added={}
  local ok,err=xpcall(function()
   for i,r in ipairs(ranges) do
    local id=R.AddProjectMarker2(project,kind~='marker',r.start,kind=='marker' and 0 or r.finish,names[i],-1,native)
    assert(id>=0,'追加できませんでした。');added[#added+1]=id
   end
  end,debug.traceback)
  if not ok then for _,id in ipairs(added) do R.DeleteProjectMarker(project,id,kind~='marker') end;error(err,0) end
 end)
end
function UI.add(kind)
 if not UI.commit_edit() then return end
 UI.poll(R.time_precise(),true)
 local project=A.project;local ranges=Core.add_ranges(project,A.add_mode,kind,A.length,A.unit,A.count,A.interval,A.interval_unit)
 if A.omit_name then UI.add_commit(kind,ranges,Core.add_names(kind,'',#ranges,false,'1'),project)
 else
  A.popup=nil;A.name_dialog={project=project,kind=kind,ranges=ranges,name=Core.names[kind],numbering=#ranges>1,serial_start='001'};UI.dirty()
 end
end
local function repeat_state(project,value)
 if R.GetSetRepeatEx then return R.GetSetRepeatEx(project,value) end
 return R.GetSetRepeat(value)
end
function UI.stop_loop_audition(stop_playback)
 local d=A.audition;if not d then return end
 local valid=not R.ValidatePtr or R.ValidatePtr(d.project,'ReaProject*')
 if valid and stop_playback and R.GetPlayStateEx(d.project)~=0 then
  if R.OnStopButtonEx then R.OnStopButtonEx(d.project) else R.OnStopButton() end
 end
 if valid and d.forced_repeat and repeat_state(d.project,-1)==1 then repeat_state(d.project,0) end
 A.audition=nil;UI.dirty()
end
function UI.start_loop_audition(plans,lead_seconds)
 if not A.auto_audition then return end
 UI.stop_loop_audition(true)
 local project=A.project;local start,finish=Core.adjusted_loop_bounds(plans)
 assert((R.GetPlayStateEx(project)&4)==0,'録音中は繋ぎ目を自動再生できません。')
 local rate=R.Master_GetPlayRate(project);assert(finite(rate) and rate>0,'プロジェクトの再生速度を取得できません。')
 local play_start,wrap_after,stop_after=Core.loop_audition_timing(start,finish,rate,lead_seconds)
 local previous_repeat=repeat_state(project,-1)
 local now=R.time_precise()
 A.audition={project=project,loop_start=start,loop_finish=finish,
  expected_wrap=now+wrap_after,stop_after=stop_after,forced_repeat=previous_repeat~=1}
 R.GetSet_LoopTimeRange2(project,true,true,start,finish,false)
 repeat_state(project,1)
 R.SetEditCurPos2(project,play_start,false,false)
 if R.OnPlayButtonEx then R.OnPlayButtonEx(project) else R.OnPlayButton() end
 assert((R.GetPlayStateEx(project)&1)~=0,'繋ぎ目の自動再生を開始できませんでした。')
end
function UI.loop_audition_tick(now)
 local d=A.audition;if not d then return end
 if R.EnumProjects(-1,'')~=d.project or (R.GetPlayStateEx(d.project)&1)==0 then UI.stop_loop_audition(false);return end
 local position=R.GetPlayPositionEx(d.project);local duration=d.loop_finish-d.loop_start
 if not d.looped_at then
  if d.last_position and position<d.last_position-max(.005,duration*.25) then d.looped_at=now
  elseif now>=d.expected_wrap then d.looped_at=d.expected_wrap end
 end
 d.last_position=position
 if d.looped_at and now-d.looped_at>=d.stop_after then UI.stop_loop_audition(true) end
end
function UI.stop_for_adjustment(project)
 if A.audition then UI.stop_loop_audition(true) end
 local state=R.GetPlayStateEx(project)
 assert((state&4)==0,'録音中は調整できません。録音を停止してください。')
 if state~=0 then
  if R.OnStopButtonEx then R.OnStopButtonEx(project) else R.OnStopButton() end
  assert(R.GetPlayStateEx(project)==0,'再生を停止できませんでした。')
 end
end
function UI.follow_loop_selection(project,plans)
 assert(project==A.project,'プロジェクトが変わりました。')
 local start,finish=Core.adjusted_loop_bounds(plans)
 R.GetSet_LoopTimeRange2(project,true,false,start,finish,false)
 if R.UpdateTimeline then R.UpdateTimeline() else R.UpdateArrange() end
end
function UI.crossfade()
 if not UI.commit_edit() then return end
 local project=R.EnumProjects(-1,'')
 if project~=A.project then UI.load_project(project) end
 A.rows=Core.project_rows(project)
 A.revision=R.GetProjectStateChangeCount(project)
 UI.stop_for_adjustment(A.project)
 assert(abs(R.Master_GetPlayRate(A.project)-1)<1e-9,'プロジェクトの再生速度を1.0にしてください。')
 local items,row=UI.loop_target_items(project,'crossfade')
 local seconds=Core.crossfade_fit(A.project,{row},A.xfade_seconds,items)
 if abs(seconds-A.xfade_seconds)>1e-12 then
  A.xfade_seconds=seconds;UI.flash('field_xfade_seconds');UI.save_settings()
 end
 local plans=Core.crossfade_plan(A.project,{row},seconds,items)
 local dir=R.GetProjectPathEx(A.project,'')..'/LRM Loops';R.RecursiveCreateDirectory(dir,0)
 A.xjob=Core.crossfade_start(A.project,plans,dir);A.busy=true;A.progress=0
 notice('クロスフェード用のループ素材を作成中…',false)
end
function UI.crossfade_step()
 local j=A.xjob;if not j then return end
 if not j.committed then
  if not Core.crossfade_step(j) then A.progress=j.progress;UI.dirty();return end
  Core.crossfade_commit(j)
  UI.remember_plan_items(j.plans)
  UI.follow_loop_selection(A.project,j.plans)
  UI.poll(R.time_precise(),true)
 end
 if not Core.crossfade_peaks_step(j) then
  A.progress=1
  if not j.peak_notice then j.peak_notice=true;notice('生成したループ素材の波形を準備中…',false) end
  return
 end
 A.xjob=nil;A.busy=false;A.progress=1
 UI.start_loop_audition(j.plans,Core.crossfade_audition_lead(j.plans))
 A.preview_signature=nil;A.preview_at=R.time_precise()+.35;A.seam=nil;A.seam_hold=nil
 UI.preview_refresh(UI.preview_signature_now())
 notice('サステイン区間をクロスフェード処理しました。時間選択を追従しました。Undoで戻せます。',false)
end

function UI.adjust_loop(mode,edge,direction)
 if not UI.commit_edit() then return end
 A.period_notice=nil
 local project=R.EnumProjects(-1,'')
 if project~=A.project then UI.load_project(project) end
 UI.stop_for_adjustment(project)
 assert(abs(R.Master_GetPlayRate(project)-1)<1e-9,'プロジェクトの再生速度を1.0にしてください。')
 A.rows=Core.project_rows(project)
 local items,row=UI.loop_target_items(project,mode)
 A.ajob=Core.loop_adjust_start(project,{row},mode,edge,direction,items,edge and A.relative_lock);A.busy=true;A.progress=0
 notice(mode=='zero' and '開始・終了付近のゼロクロスを解析中…' or 'サステイン周辺の周期を解析中…',false)
end
function UI.show_transient_notice(text)
 local now=R.time_precise()
 A.period_notice={text=text,born=now,fade_at=now+2.2,finish=now+3}
 UI.dirty()
end
function UI.show_period_failure()
 UI.show_transient_notice('周期を検出できませんでした・・・！')
 A.status='周期解析を終了しました。リージョンは変更していません。';A.warning=false;UI.dirty()
end
function UI.adjust_loop_step()
 local j=A.ajob;if not j then return end
 local ok,done=xpcall(function() return Core.loop_adjust_step(j) end,debug.traceback)
 if not ok then
  if j.mode=='period' and tostring(done):find(Core.PERIOD_FAILURE,1,true) then
   Core.loop_audio_close(j);A.ajob=nil;A.busy=false;A.progress=0;A.preview_signature=nil;A.preview_at=0
   UI.show_period_failure();return
  end
  error(done,0)
 end
 if done then
  Core.loop_adjust_commit(j);A.ajob=nil;A.busy=false;A.progress=1
  UI.remember_plan_items(j.plans)
  UI.follow_loop_selection(A.project,j.plans)
  local detail=''
  if j.mode=='period' and #j.plans==1 then detail=string.format('（周期 %.3f 秒 / 一致度 %.0f%%）',j.plans[1].period,j.plans[1].confidence*100) end
  UI.poll(R.time_precise(),true);A.preview_signature=nil;A.preview_at=0;UI.start_loop_audition(j.plans)
  local selected=j.auto_selected_count and j.auto_selected_count>0 and (' 移動先の音声アイテムを選択へ追加: '..j.auto_selected_count..'件。') or ' '
  notice((j.mode=='zero' and 'ゼロクロスへ移動しました。' or '周期に合わせて移動しました。')..detail..selected..'時間選択を追従しました。Undoで戻せます。',false)
  for _,p in ipairs(j.plans) do if p.limited then UI.show_transient_notice('選択アイテム内でこれ以上移動できません');break end end
 else A.progress=j.progress;UI.dirty() end
end

function UI.output_path(p,batch_index,batch_count)
 p=p or A.plan;assert(p,A.problem)
 local directory,name,manual_pattern
 if not A.use_default_directory then
  directory=A.directory
  assert(directory~='' and not directory:find('[%c;$]'),'出力フォルダーが不正です。')
  assert(directory:match('^%a:[/\\]') or directory:match('^[/\\]'),'出力フォルダーは絶対パスで指定してください。')
 end
 if not A.use_default_filename then
  name=Core.manual_render_pattern(A.filename)
  assert(name,'ファイル名に使用できない文字があります。')
  if name:find('$',1,true) then manual_pattern=name
  else
   assert(not Core.reserved_filename(name),'予約されたファイル名です。')
   name=Core.batch_output_name(name,batch_index or 1,batch_count or 1)..'.wav'
  end
 end
 local target
 if A.use_default_directory or A.use_default_filename or manual_pattern then
  local snapshot=Core.snapshot_render(A.project);A.render_snapshot=snapshot
  local ok,result=xpcall(function()
   snapshot.selection_changed=true
   if A.use_default_directory then
    local probe='__BLT_DIRECTORY_'..R.genGuid():gsub('[^%w]','')
    Core.configure_render(A.project,p,snapshot.s.RENDER_FILE,probe,A.format.bits,A.format.channels,false)
    local got,paths=R.GetSetProjectInfo_String(A.project,'RENDER_TARGETS','',false)
    local resolved=Core.single_render_wav_target(got,paths)
    directory=resolved:match('^(.*)[/\\][^/\\]+$')
    assert(directory and directory~='','REAPER本体の保存フォルダーを解決できません。')
   end
   if A.use_default_filename or manual_pattern then
    Core.configure_render(A.project,p,directory,A.use_default_filename and snapshot.s.RENDER_PATTERN or manual_pattern,A.format.bits,A.format.channels,true)
    local got,paths=R.GetSetProjectInfo_String(A.project,'RENDER_TARGETS','',false)
    return Core.single_render_wav_target(got,paths)
   end
   return directory..'/'..name
  end,debug.traceback)
  Core.restore_render(snapshot);A.render_snapshot=nil
  if not ok then error(result,0) end
  target=result
 else target=directory..'/'..name end
 local target_directory=target:match('^(.*)[/\\][^/\\]+$')
 assert(target_directory and target_directory~='','出力先のフォルダーを解決できません。')
 R.RecursiveCreateDirectory(target_directory,0)
 return Core.unique(target)
end
function UI.start_copy(source,p,target)
 A.job=Core.copy_start(source,target,p);A.busy=true
 local batch=A.render_batch;A.progress=batch and (batch.index-1)/batch.count or 0
 notice('リージョン情報を埋め込んでいます…',false)
end
function UI.render_one(p,batch_index,batch_count)
 assert(R.EnumProjects(-1,'')==A.project,'書き出し中にプロジェクトが切り替わりました。')
 local target=UI.output_path(p,batch_index,batch_count)
 local token=R.genGuid():gsub('[^%w]','')
 -- Render under the final name so native metadata wildcards such as
 -- $filename and $directory resolve against the actual deliverable.
 local pattern=assert(target:match('[/\\]([^/\\]+)$')):sub(1,-5)
 local outputdir=assert(target:match('^(.*)[/\\][^/\\]+$'))
 local raw=outputdir..'/_BLT_RENDER_'..token..'.wav';assert(not Core.exists(raw),'一時ファイル名が衝突しました。')
 assert(not Core.exists(target),'出力先に同名ファイルが作成されました。再実行してください。')
 A.busy=true;A.raw=target;A.own_raw=true
 notice((batch_count or 1)>1 and string.format('REAPERでミックスダウン中… %d / %d',batch_index,batch_count) or 'REAPERでミックスダウン中…',false)
 local snapshot=Core.snapshot_render(A.project);A.render_snapshot=snapshot
 local ok,err=xpcall(function()
  snapshot.selection_changed=true
  Core.configure_render(A.project,p,outputdir,pattern,A.format.bits,A.format.channels)
  local got,targets=R.GetSetProjectInfo_String(A.project,'RENDER_TARGETS','',false)
  local wav_target=Core.single_render_wav_target(got,targets)
  local function norm(s) return s:gsub('\\','/'):lower() end
  assert(norm(wav_target)==norm(target),'REAPERが予期しないWAV出力先を返しました: '..targets)
  R.Main_OnCommand(41824,0) -- Synchronous native render; never automate overwrite dialogs.
 end,debug.traceback)
 Core.restore_render(snapshot);A.render_snapshot=nil;A.busy=false
 if not ok then error(err,0) end
 assert(Core.exists(target),'レンダーがキャンセルされたか、WAVが作成されませんでした。')
 assert(os.rename(target,raw),'レンダー音声を一時保存名へ変更できませんでした。')
 A.raw=raw
 local audio=Core.scan(raw)
 assert(audio.channels==A.format.channels and audio.bits==A.format.bits and (A.format.bits~=32 or audio.tag==3),'レンダーされたWAVのチャンネル数／ビット深度が設定と一致しません。')
 UI.start_copy(raw,p,target)
end
function UI.render_mix()
 UI.poll(R.time_precise(),true)
 if #(A.selected_regions or {})==0 then UI.show_transient_notice('リージョンを選択されていません');return end
 local planned,problem=pcall(UI.preflight)
 if not planned then A.plan=nil;A.plans={};A.problem=BLT.publicError(problem) end
 if not A.plans or #A.plans==0 then
  UI.show_transient_notice(A.problem or '選択したリージョンからレンダー範囲を取得できませんでした');return
 end
 assert(R.GetPlayStateEx(A.project)==0,'再生・録音を停止してから書き出してください。')
 assert(abs(R.Master_GetPlayRate(A.project)-1)<1e-9,'プロジェクトの再生速度を1.0にしてください。')
 for _,p in ipairs(A.plans) do
  assert(p.frames*A.format.channels*(A.format.bits//8)<0xffffffff-32*1024*1024,'4 GiBを超える出力には対応していません。')
 end
 UI.save_settings();A.render_batch={plans=A.plans,index=1,count=#A.plans,outputs={}}
 UI.render_one(A.plans[1],1,#A.plans)
end
function UI.cancel()
 if A.ajob then Core.loop_audio_close(A.ajob);A.ajob=nil;A.busy=false;notice('解析を中止しました。リージョンは変更していません。',false) end
 if A.xjob then Core.crossfade_abort(A.xjob);A.xjob=nil;A.busy=false;notice('クロスフェード処理を中止しました。',false) end
 if A.job then
  Core.copy_abort(A.job);A.job=nil;A.busy=false;local done=A.render_batch and #A.render_batch.outputs or 0;A.render_batch=nil
  local cleaned=UI.cleanup_raw()
  notice(cleaned and (done>0 and ('一括書き出しを中止しました。完了済み: '..done..'件。') or '埋め込みを中止しました。') or '処理を中止しました。一時WAVを削除できませんでした。終了前に再試行します。',not cleaned)
 end
end
function UI.step()
 if not A.job then return end
 local j=A.job
 if Core.copy_step(j) then
  A.job=nil;A.busy=false;A.last_output=j.target
  local raw_problem=not UI.cleanup_raw()
  if raw_problem then notice('書き出しは完了しましたが、一時WAVを削除できませんでした。終了前に再試行します。',true) end
  local batch=A.render_batch
  if batch then
   batch.outputs[#batch.outputs+1]=j.target
   if not raw_problem and batch.index<batch.count then
    batch.index=batch.index+1;A.progress=(batch.index-1)/batch.count
    UI.render_one(batch.plans[batch.index],batch.index,batch.count);return
   end
   A.render_batch=nil;A.progress=1;A.last_outputs=batch.outputs
   if not raw_problem then notice(batch.count>1 and ('書き出し完了: '..batch.count..'件') or '書き出し完了。',false) end
  elseif not raw_problem then A.progress=1;notice('書き出し完了。',false) end
 else
  local batch=A.render_batch
  A.progress=batch and ((batch.index-1)+j.copied/j.size)/batch.count or j.copied/j.size;A.content_dirty=true
 end
end
local function button(id,x,y,w,h,title,fn,hint,enabled,accent,content_pad,prominent,text_size,no_topline,full_hover,text_flags,text_right_pad,text_y_offset,selected)
 enabled=enabled~=false and not A.busy
 local hot=enabled and inside(x,y,w,h) and not Chrome.mouseActive
 local hover=animate(id,hot and 1 or 0)
 local push=pressed==id and (gfx.mouse_cap&1)~=0 and 1.5 or 0;y=y+push
 local glow_color=full_hover and C.accent2 or accent or C.accent
 if hot then rect(x-3,y-3,w+6,h+6,glow_color,(full_hover and .025 or .018)+(full_hover and .035 or .018)*hover) end
 if prominent then rect(x+2,y+2,w-5,h,C.bg,.38) end
 cut_panel(x,y,w,h,6,selected and C.accent3 or prominent and C.panel2 or C.field,enabled and (prominent and .82 or 1) or .45,selected and C.accent2 or prominent and C.edge2 or C.edge,enabled and (selected and .95 or prominent and .58 or .7) or .2)
 gradient(x+1,y+1,w-2,h-2,C.accent3,C.bg,(prominent and .14 or .12)+hover*.2,prominent and .045 or .05,true)
 if full_hover and hover>.001 then rect(x+1,y+1,w-2,h-2,C.accent2,.085*hover) end
 if not no_topline then line(x+5,y,x+w,y,C.accent2,(prominent and .26 or .15)+hover*.4) end
 line(x,y+1,x,y+h-1,C.edge2,(prominent and .28 or .18)+hover*.32)
 if prominent then
  line(x+5,y+h-2,x+w-9,y+h-2,C.edge,.42);rect(x+5,y+7,2,max(4,h-14),glow_color,.42+hover*.25)
 end
 if accent then line(x+8,y+h-3,x+w-10,y+h-3,accent,.7) end
 local pad=content_pad or 0
 label(title,x+7+pad,y+(h-17)/2-1+(text_y_offset or 0),text_size or 13,enabled and ((selected or hot) and C.text or C.muted) or C.faint,1,w-14-pad-(text_right_pad or 0),18,text_flags or 1|4,prominent)
 register(id,x,y-push,w,h,fn,hint,enabled)
end
local function insert_button(id,x,y,w,h,title,fn,hint,accent)
 button(id,x,y,w,h,title,fn,hint,true,accent,27,nil,nil,true,true)
 y=y+(pressed==id and (gfx.mouse_cap&1)~=0 and 1.5 or 0)
 local cx,cy=x+15,y+h*.5
 -- Bold insert arrow and a short landing bar; no boxed plus decoration.
 for offset=-1,1 do
  line(cx+offset,cy-7,cx+offset,cy+2,accent,.98)
  line(cx-5,cy-2+offset,cx,cy+3+offset,accent,.98)
  line(cx,cy+3+offset,cx+5,cy-2+offset,accent,.98)
 end
 rect(cx-6,cy+7,12,2,accent,.95)
end
local function panel(x,y,w,h,title,code)
 cut_panel(x,y,w,h,10,C.panel,1,C.edge,.5)
 gradient(x+1,y+1,w-2,58,C.bg2,C.panel,.20,.015,true)
 line(x+10,y,x+w-12,y,C.edge2,.36)
 line(x+16,y+58,x+w-16,y+58,C.edge,.22)
 label(code or '',x+16,y+13,10,C.faint,2,w-30,16,0,true)
 label(title,x+16,y+31,16,C.text,1,w-30,26,0,true)
end

local ADD_LABELS={selection='選択範囲',items='選択アイテム（個別）',itemgroups='選択アイテム（グループ）',itemspan='選択アイテム全体',cursor='カーソル位置'}
local UNIT_LABELS={seconds='秒',beats='拍',bars='小節',grid='グリッド'}
local ENCODING_HINT='原則UTF-8を推奨\nSoundForgeで日本語を文字化けさせたくない場合のみCP932を選択してください。\nただし他の大多数アプリケーションで文字化けします。※英語圏には無関係な機能です'
function UI.menu(values,current,display,fn)
 local a=assert(UI.menu_anchor,'Dropdown anchor missing')
 if A.popup and A.popup.id==a.id then A.popup=nil;UI.dirty();return end
 local selected=1;for i,v in ipairs(values) do if v==current then selected=i end end
 local rows=max(1,min(8,#values,floor((H-24-a.y-a.h-4)/28)))
 A.popup={id=a.id,x=a.x,y=a.y+a.h+4,w=a.w,h=rows*28+4,rows=rows,scroll=clamp(selected-rows,0,max(0,#values-rows)),selected=selected,values=values,current=current,display=display,fn=fn}
 UI.dirty()
end
local function dropdown(id,x,y,w,h,text,fn,hint,enabled,text_size,text_y_offset)
 button(id,x,y,w,h,text,function()
  UI.menu_anchor={id=id,x=x,y=y,w=w,h=h};fn()
 end,hint,enabled,nil,nil,nil,text_size,nil,nil,4,7,text_y_offset)
 line(x+w-13,y+h/2-2,x+w-9,y+h/2+2,C.muted,.8)
 line(x+w-9,y+h/2+2,x+w-5,y+h/2-2,C.muted,.8)
end
function UI.popup_pick(index)
 local p=A.popup;if not p or not p.values[index] then return end
 A.popup=nil;pressed=nil;p.fn(p.values[index]);UI.refresh()
end
function UI.popup_key(k)
 local p=A.popup;if not p then return end
 if k==27 then A.popup=nil;pressed=nil;UI.dirty()
 elseif k==13 then UI.popup_pick(p.selected)
 elseif k==30064 or k==1685026670 then
  p.selected=clamp(p.selected+(k==30064 and -1 or 1),1,#p.values)
  p.scroll=clamp(p.scroll,max(0,p.selected-p.rows),p.selected-1);UI.dirty()
 end
end
function UI.popup_input()
 local p=A.popup;local down=(gfx.mouse_cap&1)~=0
 local within=not Chrome.mouseActive and inside(p.x,p.y+2,p.w,p.rows*28)
 local index=within and p.scroll+floor((mouse_y-p.y-2)/28)+1 or nil
 if down and not down_last then
  if index then p.pressed=index else A.popup=nil end
  pressed=nil;UI.dirty()
 elseif not down and down_last then
  if index and index==p.pressed then UI.safe(function() UI.popup_pick(index) end) end
  p.pressed=nil;UI.dirty()
 end
 down_last=down
 if gfx.mouse_wheel~=0 then
  p.scroll=clamp(p.scroll-floor(gfx.mouse_wheel/120),0,max(0,#p.values-p.rows))
  gfx.mouse_wheel=0;UI.dirty()
 end
end
function UI.draw_popup()
 local p=A.popup;if not p then return end
 -- Flush underlying text before the opaque overlay, preventing bleed-through.
 flush_text_queue()
 rect(p.x,p.y,p.w,p.h,C.field,1)
 for row=1,p.rows do
  local index=p.scroll+row;local value=p.values[index];local y=p.y+2+(row-1)*28
  local hot=inside(p.x,y,p.w,28)
  if hot or index==p.selected then rect(p.x+1,y,p.w-2,28,C.accent3,.85) end
  if value==p.current then rect(p.x+5,y+9,3,10,C.accent2,1) end
  label(p.display and p.display(value) or tostring(value),p.x+15,y+4,12,hot and C.text or C.muted,1,p.w-28,22)
 end
 if #p.values>p.rows then
  local h=p.h*p.rows/#p.values;local y=p.y+(p.h-h)*p.scroll/(#p.values-p.rows)
  rect(p.x+p.w-5,y,3,h,C.accent2,.65)
 end
end

function UI.draw_period_notice(now)
 local d=A.period_notice;if not d then return end
 local alpha=now<d.fade_at and 1 or clamp((d.finish-now)/(d.finish-d.fade_at),0,1)
 if alpha<=0 then return end
 flush_text_queue()
 local w,h=430,72;local x,y=(W-w)/2,360
 rect(x-12,y-10,w+24,h+20,C.warn,.025*alpha)
 rect(x-6,y-5,w+12,h+10,C.warn,.045*alpha)
 cut_panel(x,y,w,h,10,C.panel,.97*alpha,C.warn,.88*alpha,true)
 line(x+18,y+1,x+w-22,y+1,C.warn,.72*alpha)
 font(18,1,true);color(C.warn,alpha);gfx.x,gfx.y=sx(x+18),sy(y+8)
 gfx.drawstr(Language.message(d.text),1|4,sx(x+w-18),sy(y+h-8))
end
function UI.period_notice_tick(now)
 if A.period_notice and now>=A.period_notice.finish then A.period_notice=nil;UI.dirty() end
end

local function checkbox(id,x,y,w,text,checked,fn,hint,enabled,text_size,centered)
 enabled=enabled~=false and not A.busy
 local hot=enabled and inside(x,y,w,26)
 local by=y+(centered and 5 or 4)
 rect(x,by,16,16,C.field,1)
 line(x,by,x+16,by,hot and C.accent2 or C.edge,.8)
 line(x,by,x,by+16,C.edge,.8);line(x+16,by,x+16,by+16,C.edge,.8);line(x,by+16,x+16,by+16,C.edge,.8)
 if checked then
  line(x+3,by+8,x+7,by+12,C.accent2,.9);line(x+7,by+12,x+13,by+4,C.accent2,.9)
 end
 label(text,x+25,centered and y or y+4,text_size or 12,enabled and (hot and C.text or C.muted) or C.faint,1,w-25,centered and 26 or 22,centered and 4 or nil)
 register(id,x,y,w,26,fn,hint,enabled)
end

local function slide_toggle(id,x,y,w,text,checked,fn,hint,enabled)
 enabled=enabled~=false and not A.busy;local state=animate('toggle_'..id,checked and 1 or 0)
 line(x+3,y+12,x+23,y+12,C.edge2,.45);disc(x+7+12*state,y+12,4.2,C.faint,.8)
 if state>.001 then disc(x+7+12*state,y+12,7,C.accent,.06*state);disc(x+7+12*state,y+12,4.2,C.accent2,.94*state) end
 label(text,x+34,y,14.5,enabled and C.text or C.muted,1,w-34,28,4,true)
 register(id,x,y,w,24,fn,hint,enabled)
end
local function relative_toggle(x,y,w,h)
 local id='relative_lock';local checked=A.relative_lock
 local enabled=not A.busy;local hot=enabled and inside(x,y,w,h)
 cut_panel(x,y,w,h,5,checked and C.panel2 or C.field,1,checked and C.edge or hot and C.edge2 or C.edge,checked and .48 or hot and .78 or .5)
 gradient(x+1,y+1,w-2,h-2,C.accent3,C.bg,checked and .12 or .08,.02,true)
 label('相対保持',x+4,y+(h-16)/2,9.5,checked and C.warn or hot and C.text or C.muted,1,w-8,16,1|4,checked)
 register(id,x,y,w,h,function() A.relative_lock=not A.relative_lock;UI.refresh() end,'ONでは開始と終了を同じ量だけ移動し、ループ尺を保持',enabled)
end
local field_specs={count={1,1000,true,1,0},serial_start={0,999999999999,true,1,0},
 xfade_seconds={.000001,10,false,1,6,nil,false,6}}
local function field_spec(key)
 if key=='length' then return Core.length_specs[A.unit] end
 if key=='interval' then return Core.interval_specs[A.interval_unit] end
 return field_specs[key]
end
local function field_text(value,spec)
 if not spec then return tostring(value or '') end
 value=tonumber(value) or spec[1]
 if spec[3] then return tostring(floor(value+.5)) end
 local digits=spec[5] or 3
 local text=string.format('%.'..digits..'f',value)
 return spec[7] and text or text:gsub('0+$',''):gsub('%.$','')
end
local function parse_field(e,text)
 if e.key=='length' and A.unit=='seconds' then return time_number(text,A.unit) end
 if e.key=='interval' and A.interval_unit=='seconds' then return time_number(text,A.interval_unit) end
 return tonumber(text)
end
local function normalize_field_number(value,spec)
 return Core.normalize_spec_number(value,spec)
end
local function field_numeric_value(field)
 return tonumber(field.owner[field.key]) or field.spec[1]
end
local function normalized_text_value(key,value)
 value=tostring(value or '')
 if not utf8.len(value) or #value>4096 or value:find('[%z\1-\31\127]') then return nil,'入力できない制御文字、または長すぎる文字列です。' end
 if key=='filename' then
  value=Core.manual_render_pattern(value)
  if not value then return nil,'ファイル名に使用できない文字があります。' end
 elseif key=='directory' and value=='' then return nil,'保存フォルダーを入力してください。' end
 return value
end

function UI.flash(id)
 A.field_flash=A.field_flash or {};A.field_flash[id]=R.time_precise();UI.dirty()
end
function UI.commit_edit()
 local e=A.edit;if not e then return true end
 local value=e.text
 if e.spec then
  local ok,n=pcall(parse_field,e,value)
  local s=e.spec
  if not ok or not finite(n) then UI.flash(e.id);A.edit=nil;notice('数値を入力できなかったため、元の値へ戻しました。',true);return true end
  value=normalize_field_number(n,s)
  if abs(value-n)>1e-12 then UI.flash(e.id) end
  if e.key=='serial_start' then
   local serial_text=tostring(e.text):match('^%s*(.-)%s*$');local width=clamp(#serial_text,1,12)
   value=string.format('%0'..width..'d',value)
  end
 else
  local normalized,err=normalized_text_value(e.key,value)
  if not normalized then
   UI.flash(e.id);e.text=tostring(e.owner[e.key] or '');A.edit=nil
   if IME.active then IME.stop(false) end
   notice(err,true);UI.refresh();return true
  end
  value=normalized
 end
 e.owner[e.key]=value;A.edit=nil;if IME.active then IME.stop(false) end;UI.refresh();return true
end
function UI.begin_edit(id,owner,key,spec)
 if not UI.commit_edit() then return end
 local text=key=='serial_start' and tostring(owner[key]) or field_text(owner[key],spec)
 if spec and spec[8] then text=string.format('%.'..spec[8]..'f',owner[key]):gsub('0+$',''):gsub('%.$','') end
 A.edit={id=id,owner=owner,key=key,spec=spec,text=text,selected=true}
 if not spec and not IME.open(id) then A.edit=nil end
 UI.dirty()
end
function UI.edit_key(k)
 k=BLT.key(k);if k==0 then return end

 local e=A.edit;if not e then return end
 if k==27 then A.edit=nil;UI.dirty();return end
 if k==13 or k==9 then UI.commit_edit();return end
 if k==1 then e.selected=true
 elseif k==8 or k==6579564 then
  local pos=utf8.offset(e.text,-1);e.text=e.selected and '' or (pos and e.text:sub(1,pos-1) or '');e.selected=false
 elseif k>=32 and k<=126 or (k&0xff000000)==0x75000000 then
  local cp=k>=0x75000000 and (k&0xffffff) or k
  if cp>0x10ffff or cp>=0xd800 and cp<=0xdfff then return end
  if e.spec and not (cp>=48 and cp<=57 or cp==46 or cp==45 or cp==58) then UI.flash(e.id);return end
  if #e.text<512 then e.text=(e.selected and '' or e.text)..utf8.char(cp);e.selected=false end
 end
 if e.spec then
  local ok,n=pcall(parse_field,e,e.text)
  if not ok or not finite(n) or n<e.spec[1] or n>e.spec[2] or (e.spec[3] and n%1~=0) then UI.flash(e.id) end
 end
 UI.dirty()
end
function UI.field(key,x,y,w,enabled,owner,textonly)
 owner=owner or A;local spec=not textonly and field_spec(key) or nil
 local id='field_'..key;local active=A.edit and A.edit.id==id
 enabled=enabled~=false and not A.busy
 local fh=textonly and 32 or 36
 if textonly then IME.bounds[id]={x=x,y=y,w=w,h=fh} end
 local hot=enabled and inside(x,y,w,fh)
 local focus=animate(id..'_focus',active and 1 or hot and .24 or 0)
 gradient(x,y,w,fh,enabled and C.field or C.bg,C.panel,enabled and .98 or .55,.52,true)
 local stamp=A.field_flash and A.field_flash[id];local glow=stamp and max(0,1-(R.time_precise()-stamp)/1.35) or 0
 if glow>0 then
  rect(x-5,y-4,w+10,fh+8,C.red,.035*glow);rect(x-2,y-2,w+4,fh+4,C.red,.075*glow)
  gradient(x,y,w,fh,C.red,C.field,.20*glow,.02*glow,true)
 end
 line(x,y,x+w,y,glow>0 and C.red or C.edge2,.18+.35*focus+.45*glow)
 line(x,y+fh-1,x+w,y+fh-1,glow>0 and C.red or C.edge,.38+.25*focus)
 line(x,y,x,y+fh,glow>0 and C.red or enabled and C.accent2 or C.edge,.22+.48*focus+.42*glow)
 finish_corners(x,y,w,fh,6,false,glow>0 and C.red or C.edge2,.28+.38*focus+.42*glow)
 local str=active and A.edit.text or (textonly or key=='serial_start') and tostring(owner[key]) or field_text(owner[key],spec)
 local value_size=20.5
 if not textonly then
  local measured=measure(str,value_size,3,true);local available=max(1,w-16)
  if measured>available then value_size=max(11.5,value_size*available/measured) end
 end
 if active and textonly and IME.active and IME.id==id then
  -- ReaImGui is drawn exactly over this field so IME composition stays in place.
 elseif active and A.edit.selected then
  if textonly then rect(x+5,y+4,w-10,fh-8,C.focus2,.9)
  else
   local tw=measure(str,value_size,3,true);local sw=min(w-12,tw+8)
   rect(x+w-7-sw,y+5,sw,fh-10,C.focus2,.9)
  end
  label(str,x+8,y,textonly and 13 or value_size,C.ink,textonly and 1 or 3,w-16,fh,textonly and 4 or 6,not textonly,true)
 else
  label(str,x+8,y,textonly and 13 or value_size,enabled and C.text or C.faint,textonly and 1 or 3,w-16,fh,textonly and 4 or 6,not textonly,true)
 end
 local hint=spec and 'クリック入力 / 上下ドラッグ / ホイール' or 'クリックして直接入力'
 if key=='filename' then hint=hint..' / REAPERワイルドカード使用可' end
 if spec and Core.field_allows_fine(key,spec) then hint=hint..' / Shiftで微調整' end
 register(id,x,y,w,fh,function() UI.begin_edit(id,owner,key,spec) end,hint,enabled)
 local widget=widgets[widget_count];widget.field={id=id,owner=owner,key=key,spec=spec}
end
function UI.field_adjust(f,raw,interaction_floor)
 local s=f.spec;if not s then return end
 local requested=raw
 if interaction_floor and raw<interaction_floor then raw=interaction_floor end
 local n=normalize_field_number(raw,s)
 if abs(n-requested)>1e-7 then UI.flash(f.id) end
 if f.key=='serial_start' then
  local width=clamp(#tostring(f.owner[f.key]),1,12);f.owner[f.key]=string.format('%0'..width..'d',n)
 else f.owner[f.key]=n end
 UI.refresh()
end
function UI.field_input(hit,down)
 local f=hit and hit.field
 if gfx.mouse_wheel~=0 and f and f.spec and hit.enabled then
  local fine=(gfx.mouse_cap&8)~=0 and Core.field_allows_fine(f.key,f.spec)
  local unit=f.key=='length' and A.unit or f.key=='interval' and A.interval_unit or nil
  if UI.commit_edit() then UI.field_adjust(f,field_numeric_value(f)+(gfx.mouse_wheel>0 and 1 or -1)*f.spec[4]*(fine and .1 or 1),Core.interactive_floor(f.key,unit,fine)) end
  gfx.mouse_wheel=0;return false
 end
 if down and not down_last then
  if not UI.commit_edit() then down_last=down;return true end
  if f and f.spec then A.field_drag={f=f,y=mouse_y,value=field_numeric_value(f),moved=false} end
 end
 local d=A.field_drag
 if d and down and abs(mouse_y-d.y)>=3 then
  d.moved=true;A.edit=nil
  local fine=(gfx.mouse_cap&8)~=0 and Core.field_allows_fine(d.f.key,d.f.spec)
  local unit=d.f.key=='length' and A.unit or d.f.key=='interval' and A.interval_unit or nil
  UI.field_adjust(d.f,d.value+floor((d.y-mouse_y)/(fine and 8 or 3)+.5)*d.f.spec[4]*(fine and .1 or 1),Core.interactive_floor(d.f.key,unit,fine))
 end
 if d and not down then A.field_drag=nil;if d.moved then pressed=nil;down_last=false;return true end end
 return false
end
function UI.confirm_name()
 local d=A.name_dialog;if not d or not UI.commit_edit() then return end
 local ok,names=pcall(Core.add_names,d.kind,d.name,#d.ranges,d.numbering,d.serial_start)
 if not ok then UI.flash('field_serial_start');notice(tostring(names),true);return end
 A.name_dialog=nil;UI.add_commit(d.kind,d.ranges,names,d.project)
end
function UI.draw_name_dialog()
 local d=A.name_dialog;if not d then return end
 flush_text_queue();rect(0,0,W,H,C.bg,.87);widget_count=0
 local x,y=240,370
 rect(x,y,500,247,C.panel,1)
 label('名前と番号を設定',x+22,y+18,19,C.text,1,456,30)
 label('名前',x+22,y+63,12,C.muted,1,80,23)
 UI.field('name',x+112,y+57,364,true,d,true)
 checkbox('serial',x+22,y+112,205,'番号を付与',d.numbering,function() d.numbering=not d.numbering;UI.dirty() end,'OFFではすべて同じ名前で追加')
 label('開始番号',x+254,y+117,12,C.muted,1,80,22)
 UI.field('serial_start',x+342,y+108,134,d.numbering,d,false)
 label('1 → 1, 2, 3    /    001 → 001, 002, 003',x+22,y+157,12,C.faint,1,456,22)
 button('name_cancel',x+220,y+198,112,30,'キャンセル',function() A.edit=nil;A.name_dialog=nil;UI.dirty() end,'追加を取り消す')
 button('name_ok',x+344,y+198,132,30,'追加',UI.confirm_name,'指定した名前で追加')
end

function UI.preview_signature_now()
 local keys={tostring(A.project),tostring(R.GetProjectStateChangeCount(A.project))}
 for _,item in ipairs(UI.wave_target_items(A.project,true)) do keys[#keys+1]=tostring(item) end
 return table.concat(keys,':')
end
function UI.preview_refresh(signature)
 if A.pjob then Core.loop_audio_close(A.pjob);A.pjob=nil end
 if signature then A.preview_signature=signature end;A.seam_problem=nil;A.seam_refreshing=true
 local enabled=pcall(UI.refresh_loop_enable)
 if not enabled then A.loop_enable={crossfade=false,zero=false,period=false} end
 local ok,j=pcall(function()
  local items,row=UI.loop_target_items(A.project,'preview',true)
  assert(row,'アイテムが選択されていません')
  return Core.seam_start(A.project,{row},row.key,items)
 end)
 if ok then A.pjob=j
 else A.seam=nil;A.seam_hold=nil;A.seam_refreshing=false;A.seam_problem=tostring(j):gsub('^.-:%d+: ','') end
 UI.dirty()
end
function UI.preview_tick(now)
 if A.busy or now<(A.preview_at or 0) then return end
 A.preview_at=now+.35
 local signature=UI.preview_signature_now()
 if signature~=A.preview_signature then UI.preview_refresh(signature) end
end
function UI.preview_step()
 local j=A.pjob;if not j then return end
 local ok,done=pcall(Core.loop_adjust_step,j)
 if not ok then
  Core.loop_audio_close(j);A.pjob=nil;A.seam=nil;A.seam_hold=nil;A.seam_refreshing=false
  A.seam_problem=tostring(done):gsub('^.-:%d+: ','');UI.dirty()
 elseif done then
  A.pjob=nil;A.seam=j.plans;A.seam_hold=nil;A.seam_refreshing=false
  UI.dirty()
 end
end

function UI.move_loop_drag(d)
 assert(R.EnumProjects(-1,'')==A.project,'ドラッグ中にプロジェクトが変わりました。やり直してください。')
 UI.stop_for_adjustment(A.project)
 assert(R.GetProjectStateChangeCount(A.project)==d.revision,'ドラッグ中にプロジェクトが変更されました。やり直してください。')
 A.rows=Core.project_rows(A.project)
 local items=UI.loop_target_items(A.project,'drag',false,d.selected)
 local p=Core.loop_move_plan(A.project,A.rows,d.selected,d.edge,d.delta,d.relative,items)
 local added=0
 UI.undo('波形ドラッグでループ範囲を移動',function()
  local r=p.row
  assert(R.SetProjectMarker3(A.project,r.id,true,p.new_start,p.new_end,r.raw,r.color),'サステインの更新に失敗しました。')
  for _,item in ipairs(p.auto_select) do
   if not R.IsMediaItemSelected or not R.IsMediaItemSelected(item) then added=added+1 end
   R.SetMediaItemSelected(item,true)
  end
 end)
 UI.remember_plan_items({p})
 UI.follow_loop_selection(A.project,{p})
 A.preview_at=R.time_precise()+.35
 UI.start_loop_audition({p});UI.preview_refresh(UI.preview_signature_now())
 local extra=added>0 and (' 移動先の音声アイテムを選択へ追加: '..added..'件。') or ''
 notice((d.edge=='finish' and '終了位置' or '開始位置')..'を波形ドラッグで移動しました。'..extra..' 時間選択を追従しました。Undoで戻せます。',false)
 if p.limited then UI.show_transient_notice('選択アイテム内でこれ以上移動できません') end
end

function UI.seam_input(hit,down)
 local seam=hit and hit.seam
 if down and not down_last and seam then
 local started=false
 UI.safe(function()
   local items,row=UI.loop_target_items(A.project,'drag')
   A.seam_drag={x=mouse_x,delta=0,edge=mouse_x<seam.mid and 'finish' or 'start',seconds_per_px=seam.seconds_per_px,
    revision=R.GetProjectStateChangeCount(A.project),selected=row.key,relative=A.relative_lock,row_start=row.start,row_finish=row.finish,moved=false}
   started=true
  end)
  down_last=down;pressed=started and 'seam_drag' or nil;UI.dirty();return true
 end
 local d=A.seam_drag
 if d and down then
  local dx=mouse_x-d.x
  if abs(dx)>=2 then
   d.moved=true;d.delta=Core.seam_boundary_delta(Core.seam_drag_delta(dx,d.seconds_per_px),d.edge,d.row_start,d.row_finish,d.relative)
  end
  down_last=down;UI.dirty();return true
 end
 if d and not down then
  A.seam_drag=nil;pressed=nil;down_last=false
  if d.moved and abs(d.delta)>1e-10 then
   A.seam_hold=d
   if not UI.safe(function() UI.move_loop_drag(d) end) then A.seam_hold=nil end
  else A.seam_hold=nil;UI.preview_refresh() end
  UI.dirty();return true
 end
 return false
end

function UI.draw_wave_hint(hint,x,y,w,h)
 local text,size=hint,15
 if hint=='アイテムが選択されていません' then
  size=19
 elseif hint=='選択アイテム範囲に収まるループリージョンがありません' then
  text='選択アイテム範囲に収まる\nループリージョンがありません';size=18
 elseif hint=='選択アイテム範囲にループリージョンが複数存在しています！' then
  text='選択アイテム範囲に\nループリージョンが\n複数存在しています！';size=17.5
 elseif hint=='継ぎ目を読み取り中…' then size=18 end

 local content_top,content_bottom=y+28,y+h-12
 local max_width,max_height=w-48,content_bottom-content_top
 local gap=5
 local function layout(at_size)
  local lines={}
  local function add_wrapped(raw)
   if raw=='' then lines[#lines+1]='';return end
   local current=''
   for ch in raw:gmatch(utf8.charpattern) do
    local candidate=current..ch
    if current~='' and measure(candidate,at_size,1,true)>max_width then
     lines[#lines+1]=current;current=ch
    else current=candidate end
   end
   lines[#lines+1]=current
  end
  for raw in (text..'\n'):gmatch('(.-)\n') do add_wrapped(raw) end
  local _,pixels=font_spec(at_size,1,true)
  local line_height=pixels/scale+gap
  return lines,line_height,#lines*line_height-gap
 end

 local lines,line_height,block_height
 while true do
  lines,line_height,block_height=layout(size)
  if block_height<=max_height or size<=12 then break end
  size=size-.5
 end
 if block_height>max_height then
  local count=max(1,floor((max_height+gap)/line_height))
  while #lines>count do lines[#lines]=nil end
  lines[count]='…';block_height=#lines*line_height-gap
 end

 flush_text_queue();font(size,1,true)
 local top=content_top+(max_height-block_height)/2
 local function draw_line(line_text,line_y,dx,dy)
  local width=measure(line_text,size,1,true)
  gfx.x,gfx.y=sx(x+(w-width)/2+dx),sy(line_y+dy)
  gfx.drawstr(Language.message(line_text))
 end
 for dx=-2,2 do for dy=-2,2 do
  if dx~=0 or dy~=0 then
   local inner=abs(dx)<=1 and abs(dy)<=1
   color(inner and C.accent2 or C.focus,inner and .060 or .026)
   for i,line_text in ipairs(lines) do draw_line(line_text,top+(i-1)*line_height,dx,dy) end
  end
 end end
 color(C.focus2,.98)
 for i,line_text in ipairs(lines) do draw_line(line_text,top+(i-1)*line_height,0,0) end
end

function UI.wave_hover_tick(blocked)
 local b=A.wave_hover_bounds;local side
 if b and inside(b.x,b.y,b.w,b.h) then side=mouse_x<b.mid and 'left' or 'right' end
 local entered=side and side~=A.wave_hover_side
 -- Track entry even while dragging/refreshing. Releasing in the other pane
 -- must not turn that suppressed entry into a delayed flash.
 A.wave_hover_side=side
 if entered and not blocked and A.active~=false and not A.popup and not A.name_dialog
  and A.seam and not A.busy and not A.seam_refreshing and not A.seam_drag and (gfx.mouse_cap&3)==0 then
  A.wave_entry_flash=A.wave_entry_flash or {};A.wave_entry_flash[side]=R.time_precise();UI.dirty()
 end
end
function UI.draw_wave_entry_flash(x,y,w,h,mid)
 local flashes=A.wave_entry_flash;if not flashes then return end
 local now=R.time_precise()
 for side,start in pairs(flashes) do
  local remaining=1-(now-start)/.30
  if remaining<=0 then flashes[side]=nil
  else
   local left=side=='left' and x+1 or mid+1;local right=side=='left' and mid-1 or x+w-1
   rect(left,y+1,right-left,h-2,C.hover,.28*remaining*remaining)
  end
 end
end
function UI.draw_seam(x,y,w,h)
 rect(x,y,w,h,C.field,1)
 local inner_left,mid,inner_right,half=Core.seam_geometry(x,w)
 local bounds=A.wave_hover_bounds or {};A.wave_hover_bounds=bounds
 bounds.x,bounds.y,bounds.w,bounds.h,bounds.mid=x,y,w,h,mid
 UI.draw_wave_entry_flash(x,y,w,h,mid)
 local function center_line(color_value,alpha,glow)
  for yy=y+20,y+h-5,8 do local ending=min(yy+4,y+h-5)
   if glow then line(mid-1,yy,mid-1,ending,color_value,.10);line(mid+1,yy,mid+1,ending,color_value,.10) end
   line(mid,yy,mid,ending,color_value,alpha)
  end
 end
 label('終了 −6 ms  /  DRAG',inner_left+2,y+3,10,C.muted,1,half-4,17)
 label('開始 ＋6 ms  /  DRAG',mid+2,y+3,10,C.muted,1,half-4,17)
 center_line(C.accent2,.65,false)
 local a=A.seam
 if not a then
  local hint=A.pjob and '継ぎ目を読み取り中…' or A.seam_problem or 'アイテムが選択されていません'
  UI.draw_wave_hint(hint,x,y,w,h)
  register('seam_refresh',x,y,w,h,function() UI.preview_refresh() end,hint..' / クリックで更新',not A.busy)
  return
 end
 local drag=A.seam_drag;local d=drag or A.seam_hold
 local function visible(p)
  local window=p.windows[1];local data=window.audio;local draw_ch=window.draw_ch or min(2,p.ch);local frames=#data//draw_ch
  local left=p.preview_side=='finish'
  local start=p.preview_origin and (mid+(p.s+window.first/p.sr-p.preview_origin)/Core.SEAM_SECONDS*half) or (left and (mid-frames/p.sr/Core.SEAM_SECONDS*half) or mid)
  local follows=d and (d.relative or (d.edge=='finish' and left) or (d.edge=='start' and not left))
  if follows then start=start+Core.seam_wave_shift(d.delta,half) end
  local clip_left,clip_right=left and inner_left or mid,left and mid or inner_right
  local pixels_per_frame=half/(Core.SEAM_SECONDS*p.sr)
  local first=max(0,floor((clip_left-start)/pixels_per_frame)-1)
  local last=min(frames-1,math.ceil((clip_right-start)/pixels_per_frame)+1)
  local v=p._draw_view or {};p._draw_view=v
  v.data,v.draw_ch,v.start,v.clip_left,v.clip_right,v.pixels_per_frame,v.first,v.last=data,draw_ch,start,clip_left,clip_right,pixels_per_frame,first,last
  return v
 end
 local channels=1;local visible_peak=.001
 for _,p in ipairs(a) do
  local v=visible(p);channels=max(channels,v.draw_ch)
  if v.last>=v.first then for f=v.first,v.last do for c=1,v.draw_ch do
   visible_peak=max(visible_peak,abs(v.data[f*v.draw_ch+c]))
  end end end
 end
 local lane=(h-26)/channels
 for c=1,channels do
  local cy=y+23+(c-.5)*lane
  line(inner_left,cy,inner_right,cy,C.edge,.4)
  label(channels==1 and 'M' or c==1 and 'L' or 'R',x+4,cy-lane/2+1,8,C.faint,3,12,12)
  for _,p in ipairs(a) do local v=p._draw_view
   if c<=v.draw_ch and v.last>=v.first then
    -- Preserve the minimum and maximum sample in every screen column. Picking
    -- one sample per stride can alias a periodic/high-frequency waveform into
    -- an apparently empty horizontal line.
    local color_value=c==1 and C.accent2 or C.focus
    local column,column_min,column_max,previous_x,previous_y
    local function flush_column()
     if not column then return end
     local upper=cy-column_max/visible_peak*(lane*.4)
     local lower=cy-column_min/visible_peak*(lane*.4)
     local center=(upper+lower)/2
     if previous_x then line(previous_x,previous_y,column,center,color_value,.72) end
     if lower-upper>=.5 then line(column,upper,column,lower,color_value,.92)
     else line(column-.5,center,column+.5,center,color_value,.92) end
     previous_x,previous_y=column,center
    end
    for f=v.first,v.last do
     local px=v.start+f*v.pixels_per_frame
     if px>=v.clip_left and px<=v.clip_right then
      local xcol=floor(px+.5);local sample=v.data[f*v.draw_ch+c]
      if column~=xcol then
       flush_column();column=xcol;column_min=sample;column_max=sample
      else column_min=min(column_min,sample);column_max=max(column_max,sample) end
     else
      flush_column();column,column_min,column_max,previous_x,previous_y=nil,nil,nil,nil,nil
     end
    end
    flush_column()
   end
  end
 end
 if A.seam_refreshing then
  rect(x+w-66,y+h-21,58,16,C.bg,.82);label('更新中…',x+w-63,y+h-21,9,C.warn,1,52,15,1,true)
 end
 if drag then
  local left=drag.edge=='finish';local shade_x=drag.relative and inner_left or (left and inner_left or mid)
  rect(shade_x,y,drag.relative and inner_right-inner_left or half,h,drag.relative and C.warn or C.accent,.055)
  center_line(drag.relative and C.warn or C.focus,.95,true)
  local text=(left and '終了 ' or '開始 ')..string.format('%+.4f s',drag.delta)..(drag.relative and '  /  相対保持' or '')
  local tw=min(w-24,measure(text,11,1,true)+18);local tx=clamp(mouse_x-tw/2,x+8,x+w-tw-8)
  rect(tx,y+h-25,tw,19,C.bg,.88);label(text,tx+8,y+h-24,11,drag.relative and C.warn or C.focus2,1,tw-16,18,1,true)
 end
 register('seam_drag',x,y,w,h,function() UI.preview_refresh() end,'波形を右へドラッグ＝時間位置を前へ / 左へドラッグ＝後ろへ / クリックで更新',not A.busy and not A.seam_refreshing)
 widgets[widget_count].seam={mid=mid,seconds_per_px=Core.SEAM_SECONDS/half}
end

function UI.icon()
 local bs,bx,by=scale,ox,oy;ox,oy=ox+(W-102)*scale,oy+31*scale;scale=scale*.78

 -- A compact sample-loop capsule: waveform, returning loop rail, a region
 -- bracket and cue pin. AUTO TRIM glow styling with LRM travel directions.
 local x,y=0,0;local w,h=132,100
 -- Scale the full icon and its soft particles together into the compact header.
 local factor,tx,ty=.7,0,0
 local base_line,base_disc,base_panel=line,disc,cut_panel
 local function line(a,b,c,d,...) base_line(tx+(a-x)*factor,ty+(b-y)*factor,tx+(c-x)*factor,ty+(d-y)*factor,...) end
 local function disc(a,b,r,...) base_disc(tx+(a-x)*factor,ty+(b-y)*factor,r*factor,...) end
 local function cut_panel(a,b,c,d,r,...) base_panel(tx+(a-x)*factor,ty+(b-y)*factor,c*factor,d*factor,r*factor,...) end
 local left,right,mid=x+12,x+w-12,y+50
 -- AUTO TRIM's seven slowly drifting, low-alpha background lights.
 for i=1,7 do
  local phase=anim_time*(.15+(i%3)*.035)+i*1.41
  local px=x+w/2+math.sin(phase*1.22)*19/factor
  local py=mid+math.cos(phase*.87)*8/factor
  local rr=9+(i%4)*3
  disc(px,py,(rr+7)/factor,C.accent,.006)
  disc(px,py,rr/factor,C.accent3,.010)
 end
 cut_panel(x+1,y+3,w-2,h-6,9,C.field,.5,C.edge,.26)
 for i=0,38 do
  local px=left+i*(right-left)/38
  local amp=(math.sin(i*.78)*math.sin(i*.23+1)*.5+.5)*12+2
  line(px,mid-amp,px,mid+amp,C.accent2,.18+abs(math.sin(i*.45))*.16)
 end
 line(left+10,y+20,right-10,y+20,C.focus,.7)
 line(left+10,y+20,left+10,y+28,C.focus,.6)
 line(right-10,y+20,right-10,mid-9,C.focus,.6)
 line(left+18,y+20,left+23,y+16,C.accent2,.7);line(left+18,y+20,left+23,y+24,C.accent2,.7)
 line(left+7,y+81,right-17,y+81,C.edge2,.6)
 line(left+7,y+75,left+7,y+84,C.edge2,.6);line(right-17,y+75,right-17,y+84,C.edge2,.6)
 local now=R.time_precise();local speed=A.active and visual_speed(now) or 0
 if speed>0 then icon_clock=icon_clock+frame_dt*speed end
 while speed>0 and icon_clock>=.085 and #icon_particles<30 do
  icon_clock=icon_clock-.085;icon_serial=icon_serial+1
  local n=icon_serial
  local h1,h2,h3,h4=particle_hash(n,31),particle_hash(n,32),particle_hash(n,33),particle_hash(n,34)
  local lane=n%3;local direction=lane==0 and -1 or 1
  icon_particles[#icon_particles+1]={x=direction<0 and right-5-h1*12 or left+5+h1*12,
   y=lane==0 and y+20 or lane==1 and y+81 or mid,
   direction=direction,speed=(8+h4*8)/factor,drift=(h3-.5)*7/factor,
   life=1.8+h2*1.2,age=0,r=(.45+h1*.55)/factor,phase=h3*6.28}
 end
 for i=#icon_particles,1,-1 do
  local p=icon_particles[i];p.age=p.age+frame_dt
  if p.age>=p.life then table.remove(icon_particles,i) else
   local e=math.sin(math.pi*p.age/p.life)^2
   local px=p.x+p.direction*p.speed*p.age
   local py=p.y+p.drift*p.age+math.sin(p.age*1.4+p.phase)*2.3/factor
   disc(px,py,p.r+3.2/factor,C.accent,.022*e)
   disc(px,py,p.r+1.3/factor,C.accent2,.070*e)
   disc(px,py,p.r,C.focus2,.56*e)
  end
 end

 scale,ox,oy=bs,bx,by
end
function UI.draw(now)
 UI.geometry();frame_dt=min(.1,now-frame_clock);frame_clock=now;anim_time=anim_time+frame_dt*visual_speed(now)
 reset_text_queue();widget_count=0;hover_hint='';gfx.dest=-1;gfx.mode=0;gfx.a=1;gfx.clear=-1
 color(C.bg);gfx.rect(0,0,gfx.w,gfx.h,1)
 gradient(0,0,W,84,C.bg2,C.bg,.24,0,true)
 disc(W-50,40,148,C.accent,.014)

 BLT.title('LOOP RM STUDIO','LOOP / REGION / MARKER MANAGER  ループ・リージョン・マーカー管理ツール',W,false)
 UI.icon()
 panel(20,92,940,156,'ループ・リージョン・マーカーを追加','01  /  AUTHOR')
 local kinds={{'marker',36,178,'マーカー'},{'region',222,178,'リージョン'},{'sustain',408,390,'ループ（サステイン）'}}
 local item_mode=A.add_mode=='items' or A.add_mode=='itemgroups' or A.add_mode=='itemspan'
 if item_mode then A.last_item_mode=A.add_mode end
 local function mode_button(mode,x,y,w,h,text)
  local selected=A.add_mode==mode
  button('mode_'..mode,x,y,w,h,text,function() UI.set_add_mode(mode) end,ADD_LABELS[mode]..'を配置元にする',true,nil,nil,nil,nil,nil,nil,nil,nil,nil,selected)
  rect(x+w/2-10,y-1,20,3,selected and C.accent2 or C.edge,selected and .98 or .45)
 end
 mode_button('selection',36,159,96,32,ADD_LABELS.selection)
 button('mode_items_parent',138,153,282,18,'選択アイテム',function() UI.set_add_mode(A.last_item_mode or 'items') end,'選択アイテムから配置範囲を作成',true,nil,nil,nil,11.5,nil,nil,nil,nil,nil,item_mode)
 line(148,172,410,172,item_mode and C.accent2 or C.edge,.5)
 mode_button('items',138,176,88,20,'個別')
 mode_button('itemgroups',232,176,88,20,'グループ')
 mode_button('itemspan',326,176,94,20,'全体')
 mode_button('cursor',426,159,92,32,ADD_LABELS.cursor)
 local cursor=A.add_mode=='cursor'
 label('個数',526,163,12.5,cursor and C.text or C.faint,1,30,26,2|4,true)
 UI.field('count',562,157,42,cursor)
 label('基準幅',610,163,12.5,cursor and C.text or C.faint,1,42,26,2|4,true)
 UI.field('length',658,157,48,cursor)
 dropdown('unit',709,157,68,36,UNIT_LABELS[A.unit],function()
  UI.menu({'seconds','beats','bars','grid'},A.unit,function(v) return UNIT_LABELS[v] end,UI.set_unit)
 end,'リージョンの長さ／マーカーの配置基準幅',cursor,11.5)
 label('間隔補正',781,163,12.5,cursor and C.text or C.faint,1,50,26,2|4,true)
 UI.field('interval',837,157,49,cursor)
 dropdown('interval_unit',889,157,67,36,UNIT_LABELS[A.interval_unit],function()
  UI.menu({'seconds','beats','bars','grid'},A.interval_unit,function(v) return UNIT_LABELS[v] end,UI.set_interval_unit)
 end,'次の配置位置＝現在位置＋基準幅＋間隔補正。-基準幅で同位置、さらに小さい負値で左方向',cursor,11.5)
 local add_flash=A.add_kind_flash and clamp(1-(now-A.add_kind_flash)/.65,0,1) or 0
 for _,k in ipairs(kinds) do
  insert_button('add_'..k[1],k[2],207,k[3],30,k[4],function() UI.add(k[1]) end,ADD_LABELS[A.add_mode]..' → '..k[4],kind_color(k[1]))
  if add_flash>0 then
   local pulse=add_flash*add_flash
   rect(k[2]-5,202,k[3]+10,40,C.focus,.045*pulse)
   rect(k[2]-2,205,k[3]+4,34,C.focus,.090*pulse)
   rect(k[2]+1,208,k[3]-2,28,C.accent2,.105*pulse)
  end
 end
 checkbox('omit_name',803,210,153,'名前入力を省略',A.omit_name,function() A.omit_name=not A.omit_name;UI.refresh() end,'ONでは追加時の名前入力を省略します',nil,14)
 panel(20,262,940,238,'ループ調整','02  /  LOOP ADJUSTMENT')
 local loop_state=A.loop_enable or {};local transport_ready=(R.GetPlayStateEx(A.project)&4)==0 and abs(R.Master_GetPlayRate(A.project)-1)<1e-9
 button('crossfade',36,321,228,28,'クロスフェードを適用',UI.crossfade,'レベル突出を抑える滑らかなカーブで指定時間分だけ加工。時間は2サンプル〜ループ長に自動補正',loop_state.crossfade and transport_ready,nil,nil,true,12.5)
 label('時間',276,322,13,C.text,1,38,27,2|4,true)
 UI.field('xfade_seconds',317,317,110,true);label('s',435,325,12,C.faint,3,28,22,4,true)
 local function adjust_row(mode,y,text)
  local mode_ready=loop_state[mode] and transport_ready
  button(mode=='zero' and 'zero_cross' or 'period',36,y,228,28,text,function() UI.adjust_loop(mode) end,'開始・終了の両方を近い位置へ調整',mode_ready,nil,nil,true,12.5)
  local locked=A.relative_lock
  for _,edge in ipairs({{'finish',276,'終了'},{'start',382,'開始'}}) do
   label(edge[3],edge[2],y,10,not mode_ready and C.faint or locked and C.warn or C.muted,1,28,28,2|4,locked and mode_ready)
   for i,d in ipairs({-1,1}) do
    local x=edge[2]+31+(i-1)*28
    local hint=locked and edge[3]..'と反対端を同じ量だけ移動（ループ尺を保持）' or edge[3]..'だけを'..(d<0 and '前' or '次')..'の'..(mode=='zero' and 'ゼロクロス' or '周期')..'へ移動'
    button(mode..'_'..edge[1]..'_'..d,x,y+2,24,24,d<0 and '◀' or '▶',function() UI.adjust_loop(mode,edge[1],d) end,hint,mode_ready,locked and C.warn or nil)
   end
  end
  if locked and mode_ready then glow_line(307,y+27,465,y+27,C.warn,.30) end
 end
 adjust_row('zero',365,'最寄りゼロクロスへ補正')
 adjust_row('period',409,'周期を検出し補正')
 relative_toggle(342,393,76,16)
 slide_toggle('auto_audition',36,455,428,'調整後、繋ぎ目を自動再生',A.auto_audition,function()
  A.auto_audition=not A.auto_audition;if not A.auto_audition then UI.stop_loop_audition(true) end;UI.refresh()
 end,'通常はループ末端の0.75秒前から再生。クロスフェード時はその開始点（最低0.75秒前）から再生し、1回ループした約1秒後に停止',not A.busy)
 UI.draw_seam(488,278,456,207)
 panel(20,514,940,329,'レンダリング設定','03  /  RENDER SETTINGS')
 label('対象',36,584,13,C.text,1,138,22,4,true)
 button('master_mix',185,579,169,31,'マスターミックス',function() end,'マスターミックス\n現状マスターミックスのみ対応としています。',false)
 button('range_fixed',368,579,218,31,'選択リージョン',function() end,'選択リージョン\n現状選択リージョンの書き出しのみ対応しています。\nREAPER本体や、BLT MARKER REGION DESK等でリージョンを選択してください。',false)
 label('Master mix  /  REAPERで選択した各リージョンを個別のWAVとしてレンダリングします',36,621,11,C.faint,1,905,20)
 line(36,651,607,651,C.edge,.28)

 label('フォーマット',36,658,13,C.text,1,102,26,4,true)
 checkbox('format_defaults',145,658,439,'REAPER本体の設定を使用',A.use_format,function() A.use_format=not A.use_format;UI.refresh() end,'WAVのビット深度・サンプルレート・チャンネル数をREAPER本体から参照',true,12,true)
 local f=A.format or {};local manual=not A.use_format
 label('形式',36,696,11,C.faint,1,92,20)
 label('ビット深度',146,696,11,C.faint,1,122,20)
 label('サンプルレート',284,696,11,C.faint,1,137,20)
 label('チャンネル',439,696,11,C.faint,1,140,20)
 button('format',36,718,96,31,'WAV',function() end,'WAV\n現状WAVのみ対応としています。\nOGG等への対応はしていません。',false)
 dropdown('bits',146,718,124,31,f.bits and (f.bits..(f.bits==32 and ' bit float' or ' bit PCM')) or '—',function()
  UI.menu({16,24,32},A.bits,function(v) return v..(v==32 and ' bit float' or ' bit PCM') end,function(v) A.bits=v end)
 end,'WAVのビット深度',manual)
 dropdown('sr',284,718,141,31,f.sr and (f.sr..' Hz') or '—',function()
  UI.menu(Core.sample_rates,A.sr,function(v) return v..' Hz' end,function(v) A.sr=v end)
 end,'出力サンプルレート',manual)
 dropdown('ch',439,718,145,31,f.channels and (f.channels==1 and 'Mono' or f.channels==2 and 'Stereo' or f.channels..' ch') or '—',function()
  UI.menu(Core.channel_options,A.channels,function(v) return v==1 and 'Mono' or v==2 and 'Stereo' or v..' ch' end,function(v) A.channels=v end)
 end,'出力チャンネル数',manual)
 line(607,579,607,749,C.edge,.28)
 label('出力先',624,584,13,C.text,1,70,22,4,true)
 local dir=A.use_default_directory and (A.default_directory~='' and A.default_directory or '（プロジェクトの標準保存先）') or A.directory
 local name=A.use_default_filename and (A.default_pattern~='' and A.default_pattern or '（REAPERの既定名）') or (A.filename..'.wav')
 label('保存フォルダー',624,610,11,C.faint,1,58,26,4)
 checkbox('directory_defaults',686,610,258,'REAPER設定を使用',A.use_default_directory,function()
 A.use_default_directory=not A.use_default_directory;UI.refresh()
end,'保存フォルダーのみREAPER本体の設定を使用',true,11,true)
 if A.use_default_directory then button('dir_default',624,637,320,31,dir,function() end,dir,false)
 else
  UI.field('directory',624,637,250,true,A,true)
  button('dir_browse',882,637,62,31,'参照',UI.choose_directory,'保存フォルダーを選択',true,nil,nil,true,11)
 end
 label('ファイル名',624,674,11,C.faint,1,58,26,4)
 checkbox('filename_defaults',686,674,258,'REAPER設定を使用',A.use_default_filename,function()
 A.use_default_filename=not A.use_default_filename;UI.refresh()
end,'ファイル名のみREAPER本体の設定を使用。ワイルドカードもREAPERで解決',true,11,true)
 if A.use_default_filename then button('name_default',624,701,320,31,name,function() end,name,false)
 else UI.field('filename',624,701,320,true,A,true) end

 line(36,758,944,758,C.edge,.28)
 label('埋め込むマーカー/リージョンを設定',36,766,13,C.text,1,355,22,4,true)
 slide_toggle('embed_markers',36,794,110,'マーカー',A.embed_markers,function()
  A.embed_markers=not A.embed_markers;UI.refresh()
 end,'レンダー範囲内のマーカーをWAVへ埋め込み',not A.busy)
 slide_toggle('embed_regions',150,794,122,'リージョン',A.embed_regions,function()
  A.embed_regions=not A.embed_regions;UI.refresh()
 end,'レンダー範囲内の通常リージョンをWAVへ埋め込み',not A.busy)
 slide_toggle('embed_loop_region',276,794,176,'ループリージョン',A.embed_loop_region,function()
  A.embed_loop_region=not A.embed_loop_region;UI.refresh()
 end,'レンダー範囲内のサステインをWAVのループ情報として埋め込み',not A.busy)
 slide_toggle('exclude_selected_region',456,794,246,'選択中のリージョンを除外',A.exclude_selected_region,function()
  A.exclude_selected_region=not A.exclude_selected_region;UI.refresh()
 end,'書き出し範囲として選択しているリージョンは埋め込まないようにします。\nただし、ループリージョン自体を選択して書き出した場合に、ループリージョンは除外しません。',not A.busy)
 label('マーカー文字コード設定',706,793,11.5,C.faint,1,132,26,2|4)
 dropdown('encoding',842,793,102,26,A.encoding,function()
  UI.menu({'UTF-8','CP932'},A.encoding,nil,function(v) A.encoding=v end)
 end,ENCODING_HINT,true,11.5,.5)

 local entry_count,outside_count,clipped_count,omitted_count=0,0,0,0
 for _,p in ipairs(A.plans or {}) do
  entry_count=entry_count+#p.entries;outside_count=outside_count+p.outside;clipped_count=clipped_count+p.clipped;omitted_count=omitted_count+(p.omitted or 0)
 end
 local message=A.problem and BLT.publicError(A.problem) or (A.plan and ('出力 '..#A.plans..'件 / 埋め込み '..entry_count..'件 / 除外 '..omitted_count..'件 / 範囲外 '..outside_count..'件 / 切詰め '..clipped_count..'件') or '')
 local w,h=310,52;local x,y=(W-w)/2,864;local execute_y=y
 local ready=not A.busy;local hot=ready and inside(x,y,w,h) and not Chrome.mouseActive
 local batch_progress=A.render_batch and string.format('  %d/%d',A.render_batch.index,A.render_batch.count) or ''
 PrimaryButton.draw(PrimaryButton.painter,x,y,w,h,A.busy and ('処理中'..batch_progress) or 'レンダリング実行',A.ajob and 'ANALYZING' or A.busy and 'WRITING WAV' or 'RENDER',ready,A.busy,A.busy and A.progress or nil,hot,pressed=='execute' and (gfx.mouse_cap&1)~=0,R.time_precise(),BLT.host.active())
 register('execute',x,execute_y,w,h,UI.render_mix,'Master mixをレンダーして区間情報を埋め込む',ready)
 if A.busy and (A.job or A.xjob or A.ajob) then
  rect(678,877,92,29,C.field,1);label('中止',680,880,13,C.warn,1,86,23,1)
  register('cancel',678,877,92,29,UI.cancel,'埋め込みを中止。元のWAVは保持',true)
 end

 BLT.footer(A.warning and A.status or (message~='' and message or A.status),A.warning or A.problem,W,H+22,'0.5.5')
 draw_hover_tooltip(hover_hint);UI.draw_name_dialog();UI.draw_popup();UI.draw_period_notice(now);flush_text_queue();custom_titlebar();gfx.update();A.content_dirty=false;redraw_dirty=false
end

function UI.interact()
 local blocked=BLT.blocked();UI.wave_hover_tick(blocked)
 if blocked then down_last=(gfx.mouse_cap&1)~=0;pressed=nil;gfx.mouse_wheel=0;return end

 if A.popup then set_content_cursor(false);UI.popup_input();return end
 local hit
 if not Chrome.mouseActive then for i=widget_count,1,-1 do local w=widgets[i];if w.enabled and (not A.busy or w.id=='cancel') and inside(w.x,w.y,w.w,w.h) then hit=w;break end end end
 set_content_cursor((hit and hit.seam~=nil) or A.seam_drag~=nil)
 local down=(gfx.mouse_cap&1)~=0
 if UI.seam_input(hit,down) then return end
 if UI.field_input(hit,down) then return end
 if down and not down_last then pressed=hit and hit.id or nil;UI.dirty() end
 if not down and down_last then
  local fn=hit and hit.id==pressed and hit.fn;pressed=nil
  if fn then UI.safe(fn) end;UI.dirty()
 end
 down_last=down
 if gfx.mouse_wheel~=0 then gfx.mouse_wheel=0 end
end
function UI.close()
 -- Teardown errors must not leave a dead graphics window on screen.
 local ok,err=xpcall(function()
 if A.closed then return end;A.closed=true
 if IME.active then IME.stop(false) end
 if A.audition then UI.stop_loop_audition(true) end
 if A.render_snapshot then Core.restore_render(A.render_snapshot);A.render_snapshot=nil end
 Core.copy_abort(A.job);A.job=nil
 Core.retry_file_deletes(true)
 UI.cleanup_raw()
 A.render_batch=nil
 if A.xjob then Core.crossfade_abort(A.xjob);A.xjob=nil end
 if A.ajob then Core.loop_audio_close(A.ajob);A.ajob=nil end
 if A.pjob then Core.loop_audio_close(A.pjob);A.pjob=nil end
 A.seam_drag=nil;A.seam_hold=nil
 clear_chrome_tooltip();titlebar_cleanup()
 local _,x,y,w,h=gfx.dock(-1,0,0,0,0)
 for k,v in pairs({window_x=x,window_y=y,window_w=w,window_h=h}) do if finite(v) then BLT.store(SECTION,k,tostring(floor(v+.5)),true) end end
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

 local k=BLT.key(gfx.getchar());if k<0 or A.closed then UI.close();return end
 local now=R.time_precise()
 UI.safe(function()
  local flags=gfx.getchar(65537)
  A.active=((flags&1)==0) or ((flags&2)~=0)
 local changed=gfx.mouse_x~=last_raw_mouse_x or gfx.mouse_y~=last_raw_mouse_y or gfx.mouse_cap~=last_raw_mouse_cap or gfx.mouse_wheel~=0
  if changed or k>0 then wake_visuals(now) end
  -- App-bar input is consumed during drawing: preserve every button edge.
  if gfx.mouse_cap~=last_raw_mouse_cap or gfx.mouse_wheel~=0 then next_draw_time=now end
  last_raw_mouse_x,last_raw_mouse_y,last_raw_mouse_cap=gfx.mouse_x,gfx.mouse_y,gfx.mouse_cap
  local ime_was_active=IME.active;IME.frame()
  if ime_was_active or IME.active then k=0 end
  if Core.undo_shortcut(k,gfx.mouse_cap) and not A.name_dialog and not A.popup then A.edit=nil;UI.project_undo();k=0
  elseif A.edit then UI.edit_key(k);k=0
  elseif A.name_dialog and k==27 then A.name_dialog=nil;UI.dirty();k=0
  elseif A.popup then UI.popup_key(k);k=0 end
  if not A.active then A.popup=nil end
  if k==27 then if A.busy then UI.cancel() elseif A.audition then UI.stop_loop_audition(true) else A.closing=true end end
  UI.poll(now);Chameleon.tick(now)
  Core.retry_file_deletes(false)
  if not A.busy and A.raw_delete_at and now>=A.raw_delete_at then UI.cleanup_raw() end
  UI.preview_tick(now)
  if not A.busy then UI.preview_step() elseif A.pjob then Core.loop_audio_close(A.pjob);A.pjob=nil;A.preview_signature=nil;A.seam_hold=nil;A.seam_refreshing=false end
  UI.loop_audition_tick(now)
  UI.period_notice_tick(now)
  if gfx.w~=last_window_w or gfx.h~=last_window_h then last_window_w,last_window_h=gfx.w,gfx.h;UI.dirty() end
  UI.geometry();UI.interact()
  if A.job then UI.step() end
  if A.xjob then UI.crossfade_step() end
  if A.ajob then UI.adjust_loop_step() end
  local moving=IME.active or (A.active and visual_speed(now)>0) or #icon_particles>0 or Chrome.drag or Chrome.resize or A.period_notice~=nil
  local interval=(A.busy or moving) and 1/30 or 4
  if (A.content_dirty or redraw_dirty or moving or A.busy) and now>=next_draw_time then
   UI.draw(now);next_draw_time=now+interval;
  end
  if Chrome.requestReset then Chrome.requestReset=false;reset_window_size();UI.dirty() end
  if Chrome.requestClose then A.closing=true end
 end)
 if A.closing then UI.close() else R.defer(UI.loop) end
end
BLT.factorySettings={};for k in ('filename directory sr bits channels encoding use_default_directory use_default_filename use_format embed_markers embed_regions exclude_selected_region embed_loop_region omit_name xfade_seconds add_mode unit interval_unit count relative_lock auto_audition length length_values interval interval_values'):gmatch('%S+') do BLT.factorySettings[k]=BLT.copy(A[k]) end
function BLT.pick(obj,keys) local v=BLT.valueView or {};BLT.valueView=v;for k in pairs(keys) do v[k]=obj[k] end;return v end
PrimaryButton.painter={C=C,gradient=gradient,line=line,rect=rect,corners=finish_corners,disc=disc,label=label}
PrimaryButton.painter.motion=function(now) return (gfx.mouse_x-ox)/scale,(gfx.mouse_y-oy)/scale,visual_speed(now) end
PrimaryButton.wake=function() redraw_dirty=true;A.content_dirty=true;next_draw_time=0 end
BLT.attach({
 R=R,C=C,Chrome=Chrome,Chameleon=Chameleon,section=SECTION,faces=fonts,font=font,
 geometry=function() return scale,ox,oy end,active=function() local f=gfx.getchar(65536);return (f&1)==0 or (f&2)~=0 end,
 wake=function() A.content_dirty=true;redraw_dirty=true;next_draw_time=0;wake_visuals() end,
 defaults=BLT.factorySettings,capture=function() return BLT.pick(A,BLT.factorySettings) end,
 valid=function(v) local function valid(n,r) return type(n)=='number' and n>=r[1] and n<=r[2] and (not r[3] or n%1==0) end;if not Core.length_specs[v.unit] or not Core.interval_specs[v.interval_unit] then return false end;if not valid(v.count,{1,1000,true}) or not valid(v.xfade_seconds,{.000001,10}) or not valid(v.sr,{8000,384000,true}) then return false end;for k,n in pairs(v.length_values) do local r=Core.length_specs[k];if not r or not valid(n,r) then return false end end;for k,n in pairs(v.interval_values) do local r=Core.interval_specs[k];if not r or not valid(n,r) then return false end end;if not valid(v.length,Core.length_specs[v.unit]) or not valid(v.interval,Core.interval_specs[v.interval_unit]) then return false end;local channel=false;for _,x in ipairs(Core.channel_options) do if v.channels==x then channel=true end end;return channel and (v.encoding=='UTF-8' or v.encoding=='CP932') and (v.add_mode=='selection' or v.add_mode=='items' or v.add_mode=='itemgroups' or v.add_mode=='itemspan' or v.add_mode=='cursor') and (v.bits==16 or v.bits==24 or v.bits==32) end,apply=function(v) for k,x in pairs(v) do A[k]=x end;UI.refresh() end,
 undoAction=UI.project_undo,
 busy=function() return A.busy end,commit=function() return UI.commit_edit() end,
 cancelEdit=function() IME.stop(false);A.edit=nil;A.field_drag=nil;A.popup=nil end,editing=function() return A.edit~=nil end,
 modal=function() return A.popup~=nil or A.name_dialog~=nil end,
 handle=gfx_window_handle,resizeHit=function(x,y) if y<26 and x>=gfx.w-234 then return nil end;return chrome_resize_hit(x,y) end,
 cursor=set_resize_cursor,beginResize=begin_window_resize,resize=update_window_resize,

})
if ...=='blt_test' then function BLT.testDraw(now) UI.draw(now or R.time_precise()) end end
function BLT.drawIcon()
 flush_text_queue();
 local bs,bx,by=scale,ox,oy;ox,oy=ox+(W-102)*scale,oy+31*scale;scale=scale*.78
 UI.icon()
 flush_text_queue();
 scale,ox,oy=bs,bx,by
end

if ...=='blt_test' then return {BLT=BLT,A=A,Core=Core ,UI=UI} end
if ...=='ui_test' then return {Core=Core,A=A,UI=UI,Chameleon=Chameleon,palette=C,Chrome=Chrome,set_content_cursor=set_content_cursor} end
local chrome_ok,chrome_err=titlebar_api_ready()
if not chrome_ok then Language.mb(BLT.publicError(chrome_err),'BLT LOOP RM STUDIO | 必要な拡張',0);return end
local ww=tonumber(R.GetExtState(SECTION,'window_w')) or W;local wh=tonumber(R.GetExtState(SECTION,'window_h')) or H+Chrome.titleH
if R.GetExtState(SECTION,'render_button_balance_206')~='true' then
 if tonumber(R.GetExtState(SECTION,'window_h')) then wh=wh+16 end
 BLT.store(SECTION,'render_button_balance_206','true',true)
end
ww=clamp(ww,Chrome.minW,2200);wh=clamp(wh,Chrome.minH,1800)
local wx,wy=tonumber(R.GetExtState(SECTION,'window_x')),tonumber(R.GetExtState(SECTION,'window_y'))
-- Match native window/input coordinates in logical points on Mac.
gfx.ext_retina=BLT_MAC and 0 or 1
if finite(wx) and finite(wy) then gfx.init(Chrome.windowTitle,ww,wh,0,wx,wy) else gfx.init(Chrome.windowTitle,ww,wh,0) end
if not apply_custom_window_style(ww,wh) then gfx.quit();Language.mb('カスタムアプリバーを初期化できません。','BLT LOOP RM STUDIO',0);return end
if Chameleon.enabled then Chameleon.refresh(true) end
R.atexit(UI.close);UI.safe(function() UI.poll(R.time_precise(),true) end);UI.loop()
