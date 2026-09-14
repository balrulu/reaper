-- @description BLT: Variant Forge - create randomized audio-item variations (JP/EN GUI)
-- @version 0.5.0
-- @about
--   BLT blue-black glass HUD. Native gfx + js_ReaScriptAPI.
--   Copies retain all takes/FX; randomization targets the active take. Finite VOICE limits may fade the selected source item.
--   Per-item apply matrix with variation-local random-value locks and multi-row editing.
--   Pitch Curve supports random directional guides plus fixed-length or tape-style linked-length processing; Vibrato/Tremolo write take envelopes.
--   Source variation uses source-wide Auto Trim/Split-style loudness segmentation, visual analysis, and cut-item candidates.
--   Texture EQ uses a 1-10 item reference spectral library when registered; otherwise AUTO TEXTURE is generated procedurally.
--   Texture ReaEQ stays live after generation and can be baked on demand; pre-existing take/track FX stay live.
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
 ["設定値が範囲外です："]="Setting out of range: ",
 ["下限は上限以下にしてください："]="Minimum must not exceed maximum: ",
 ["STARTはEND以下にしてください："]="START must not exceed END: ",
 ["対象アイテムが無効です。"]="Invalid target item.",
 ["音声アイテムだけが対象です。"]="Audio items only.",
 ["音声ソースまたは長さを確認してください。"]="Check audio source and length.",
 ["音声を持たないアイテムは対象外です。"]="Items without audio are unsupported.",
 ["対象トラックを取得できません。"]="Cannot read target track.",
 ["元になる音声アイテムを選択してください。"]="Select source audio items.",
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
 ["検出区間 %d / 使用可能 1：バリエーションなし"]="Detected %d / Usable 1: no variations",
 ["山より前"]="Before peak",
 ["山より後"]="After peak",
 ["区間相対 %s %.1f%%"]="Section-relative %s %.1f%%",
 ["山オフセット %.1f ms"]="Peak offset %.1f ms",
 ["候補 %d（同一素材 %d / 同一トラック %d） / %s"]="Candidates %d (same source %d / same track %d) / %s",
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
 ["解析後にプロジェクトが変更されました。再度実行してください。"]="Project changed after analysis. Run again.",
 ["対象が削除されました。"]="Target was deleted.",
 ["自由配置モードを有効化できません。"]="Cannot enable free item positioning.",
 ["元アイテムの発音フェードを設定できません。"]="Cannot set source item attack fade.",
 ["複製アイテムを作成できません。"]="Cannot create duplicate item.",
 ["アイテムを複製できません。"]="Cannot duplicate item.",
 ["複製Takeを取得できません。"]="Cannot read duplicated take.",
 ["位置または長さを設定できません。"]="Cannot set position or length.",
 ["生成アイテムの発音フェードを設定できません。"]="Cannot set generated item attack fade.",
 ["Take設定に失敗しました："]="Take setting failed: ",
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
 ["カメレオンモード（配色をテーマへ擬態）"]="Chameleon: match REAPER colors",
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
 ["使用する素材を完全再解析しています。完了後に自動で生成します。"]="Reanalyzing all sources. Generation starts automatically afterward.",
 ["処理を中止しました。コピーはまだ作成していません。"]="Stopped. No copies created yet.",
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
 ["TEXTURE FXを%dアイテムへ焼き込みました。生成取消は引き続き使用できます。"]="Baked TEXTURE FX into %d items. Undo generation remains available.",
 ["このセッションで取り消せる生成結果がありません。"]="No generated result to undo in this session.",
 ["生成結果は削除済みです。ほかのテイクが使用中の焼き込みWAVは残しました。"]="Generated results already deleted. Retained baked WAVs used by other takes.",
 ["直前の生成結果はすでに存在しません。"]="Most recent generated result no longer exists.",
 ["一部の生成アイテムを削除できませんでした。Undoで確認してください。"]="Could not delete some generated items. Check Undo.",
 [" 生成後に編集された元アイテム%d件は、その編集を保持しました。"]=" Kept later edits to %d source items.",
 [" 使用中の焼き込みWAVは%d件残しました。"]=" Retained %d baked WAVs still in use.",
 ["直前に生成した%dアイテムを取り消しました。%s"]="Undid %d recently generated items. %s",
 ["再生成できる直前の生成結果がありません。"]="No recent result to regenerate.",
 ["再生成元のアイテム情報がありません。生成し直してください。"]="Missing source item information. Generate again.",
 ["元アイテムが削除されているため再生成できません。現在の生成結果は残しました。"]="Source items deleted. Cannot regenerate; existing result retained.",
 ["再生成元の素材情報を準備できませんでした。SOURCEを確認してから再実行してください。"]="Cannot prepare regeneration sources. Check SOURCE, then retry.",
 ["素材の再解析中に選択またはプロジェクトが変わったため、実行を中止しました。"]="Selection or project changed during source reanalysis. Stopped.",
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
 ["TEXTURE EQ参照には長すぎる素材があります。\n\n%s\n%.2f 秒\n\n1素材あたり最大 %d 秒です。"]="TEXTURE EQ reference is too long.\n\n%s\n%.2f s\n\nMaximum per source: %d s.",
 ["%s のスペクトルを解析できません。\n%s"]="Cannot analyze spectrum of %s.\n%s",
 ["素材 "]="Source ",
 ["周波数情報を取得できません。"]="Cannot read frequency information.",
 ["TEXTURE EQ：%d素材を解析・登録しました。"]="TEXTURE EQ: analyzed and registered %d sources.",
 ["TEXTURE EQの参照素材をクリアしました。"]="TEXTURE EQ references cleared.",
 ["未設定 · AUTO TEXTURE"]="Not set · AUTO TEXTURE",
 ["TEXTURE素材"]="TEXTURE SOURCE",
 ["未設定時はAUTO TEXTUREを使用。参照を使う場合は1～10個の音声アイテムを選択して解析・設定します。"]="Without references, use AUTO TEXTURE. To add references, select and analyze 1 to 10 audio items.",
 ["青: 検出区間   黄: 基準点   明枠: 使用中    %.2f s"]="Blue: sections  Yellow: anchor  Bright border: active    %.2f s",
 ["区間 %d/%d"]="Section %d/%d",
 ["リストで最後にクリックしたアイテムの素材全体。青=検出区間 / 黄=基準点 / 明枠=現在の使用範囲"]="Full source of the last clicked list item. Blue: sections / Yellow: anchor / Bright border: active range",
 ["トラック / ファイル名"]="TRACK / FILENAME",
 ["GLOBAL APPLY   /   一括 ON / OFF"]="GLOBAL APPLY / All ON / OFF",
 ["全項目をまとめてON/OFF"]="Toggle all features",
 ["使用可能な素材バリエーションがあるアイテムだけを一括ON/OFF"]="Toggle only items with usable source variations",
 ["全選択アイテムのこの機能を一括ON/OFF"]="Toggle this feature for all selected items",
 ["ファイル名：Ctrl/Shiftで複数選択 / ホイールでスクロール"]="Filename: Ctrl/Shift for multi-select / Wheel to scroll",
 ["クリック選択 / Ctrl(Cmd)で追加・解除 / Shiftで範囲選択"]="Click: select / Ctrl(Cmd): toggle / Shift: range",
 ["素材バリエーション"]="Source variations",
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
 ["深さL"]="Depth L",
 ["深さH"]="Depth H",
 ["速度L"]="Rate L",
 ["速度H"]="Rate H",
 ["SOURCE VARIATIONS  素材から様々なバリエーションを生成"]="SOURCE VARIATIONS  Generate variations from audio",
 ["選択"]="Selected",
 ["生成数"]="Count",
 ["組"]=" sets",
 ["間隔"]="Spacing",
 ["末尾→先頭"]="End → Start",
 ["先頭→先頭"]="Start → Start",
 ["発音フェード"]="Attack fade",
 ["乱数シード"]="Random seed",
 ["シード固定"]="Lock seed",
 ["下限"]="Lower",
 ["上限"]="Upper",
 ["尺固定"]="Keep length",
 ["尺連動"]="Link length",
 ["選出"]="Selection",
 ["シャッフル"]="Shuffle",
 ["順番"]="In order",
 ["位置"]="Position",
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
 ["生成取消"]="Undo generation",
 ["このセッションで直前に生成したアイテムを削除"]="Delete the most recently generated items in this session",
 ["再生成"]="Regenerate",
 ["直前の生成結果を削除して現在の設定で生成し直す"]="Replace the latest result using current settings",
 ["処理を中止"]="Stop",
 ["%d バリエーションを生成"]="Generate %d variations",
 ["Enter：生成。SOURCEの事前解析中は完了後に実行できます。"]="Enter: generate. Wait for SOURCE pre-analysis to finish.",
 ["直前生成のTEXTURE EQだけを音声へ焼き込み、FX負荷を軽減"]="Bake only the latest TEXTURE EQ into audio to reduce FX load",
 ["素材の事前解析を中止しました。"]="Source pre-analysis stopped.",
 ["BLT Variant Forge | エラー"]="BLT Variant Forge | Error",
 ["カスタム枠を初期化できません。"]="Cannot initialize the custom frame.",
 ["表示言語を切替（JP / EN）"]="Switch language (JP / EN)",
 ["プリセットを読み込みました: ファクトリーデフォルト"]="Loaded: Factory Default",
 ["選択中のトラック / バスを指定"]="Use selected track / bus",
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
 {"^TEXTURE FXを([%+%-]?[%d%.eE]+)アイテムへ焼き込みました。生成取消は引き続き使用できます。$","Baked TEXTURE FX into %d items. Undo generation remains available."},
 {"^ 生成後に編集された元アイテム([%+%-]?[%d%.eE]+)件は、その編集を保持しました。$"," Kept later edits to %d source items."},
 {"^ 使用中の焼き込みWAVは([%+%-]?[%d%.eE]+)件残しました。$"," Retained %d baked WAVs still in use."},
 {"^直前に生成した([%+%-]?[%d%.eE]+)アイテムを取り消しました。(.-)$","Undid %d recently generated items. %s",{2}},
 {"^TEXTURE EQの参照素材は最大([%+%-]?[%d%.eE]+)個です。\n現在 ([%+%-]?[%d%.eE]+)個 選択されています。$","TEXTURE EQ supports at most %d references.\nCurrently selected: %d."},
 {"^([%+%-]?[%d%.eE]+)番目の選択アイテムを解析できません。\n(.-)$","Cannot analyze selected item %d.\n%s",{2}},
 {"^TEXTURE EQ参照には長すぎる素材があります。\n\n(.-)\n([%+%-]?[%d%.eE]+) 秒\n\n1素材あたり最大 ([%+%-]?[%d%.eE]+) 秒です。$","TEXTURE EQ reference is too long.\n\n%s\n%.2f s\n\nMaximum per source: %d s."},
 {"^(.-) のスペクトルを解析できません。\n(.-)$","Cannot analyze spectrum of %s.\n%s",{2}},
 {"^TEXTURE EQ：([%+%-]?[%d%.eE]+)素材を解析・登録しました。$","TEXTURE EQ: analyzed and registered %d sources."},
 {"^青: 検出区間   黄: 基準点   明枠: 使用中    ([%+%-]?[%d%.eE]+) s$","Blue: sections  Yellow: anchor  Bright border: active    %.2f s"},
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

local Core={VERSION='0.5.0',SOURCE_SR=48000,SOURCE_HOP=48,SOURCE_BLOCK=12000,SOURCE_PREVIEW_BINS=1400,SOURCE_MAX_REGIONS=16384,
 GENERATED_TAG='P_EXT:BLT_VARIANT_FORGE',TEMP_TAG='P_EXT:BLT_VARIANT_FORGE_TEMP',SECTION='BLT_VARIANT_FORGE',EQ_FIXED_CACHE={}}
Core.STALE_TEMP_PROJECTS={};Core.RUN_ID='';Core.TEMP_HEARTBEAT_TTL=8;Core.TEMP_HEARTBEAT_KEY='temp_live_registry_v1';Core.temp_heartbeat_at=0
local abs,min,max,floor,ceil=math.abs,math.min,math.max,math.floor,math.ceil
local function finite(n) return type(n)=='number' and n==n and abs(n)<math.huge end
local function clamp(n,a,b) return max(a,min(b,n)) end
local function db(x) return x>1e-12 and 20*math.log(x,10) or -240 end
local function copy(t) local o={};for k,v in pairs(t) do o[k]=v end;return o end
local function tcopy(t) local o={};for k,v in pairs(t or {}) do o[k]=type(v)=='table' and tcopy(v) or v end;return o end
Core.FEATURES={'pitch_global','pitch_curve','vibrato','tremolo','timing','volume','pan','eq_texture','eq_tone','source'}
Core.defaults={
 count=8,interval_mode=1,interval=0.0,voice_fade_ms=30,seed=18273,seed_lock=false,
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
 if not take or R.TakeIsMIDI(take) then return nil,'音声アイテムだけが対象です。' end
 local source=R.GetMediaItemTake_Source(take)
 local pos,len=R.GetMediaItemInfo_Value(item,'D_POSITION'),R.GetMediaItemInfo_Value(item,'D_LENGTH')
 local rate=R.GetMediaItemTakeInfo_Value(take,'D_PLAYRATE')
 if not source or not finite(len) or len<=0 or not finite(rate) or rate<=0 then return nil,'音声ソースまたは長さを確認してください。' end
 local source_type=R.GetMediaSourceType(source);source_type=type(source_type)=='string' and source_type:upper() or ''
 local source_rate=R.GetMediaSourceSampleRate(source);local source_channels=R.GetMediaSourceNumChannels(source)
 if source_type=='EMPTY' or source_type=='MIDI' or source_type=='MIDIPOOL'
  or not finite(source_rate) or source_rate<=0 or not finite(source_channels) or source_channels<1 then
  return nil,'音声を持たないアイテムは対象外です。'
 end
 local track=R.GetMediaItemTrack(item);if not track then return nil,'対象トラックを取得できません。' end
 local slen,isqn=R.GetMediaSourceLength(source)
 local _,guid=R.GetSetMediaItemInfo_String(item,'GUID','',false);local file=R.GetMediaSourceFileName(source,'')
 local channel_mode=R.GetMediaItemTakeInfo_Value(take,'I_CHANMODE')
 local analysis_channels=(channel_mode==2 or channel_mode==3 or channel_mode==4) and 1 or source_channels
 local item_gain=R.GetMediaItemInfo_Value(item,'D_VOL');local take_gain=R.GetMediaItemTakeInfo_Value(take,'D_VOL')
 local generated,temp=Core.item_tags(item)
 return {item=item,take=take,track=track,pos=pos,len=len,rate=rate,source=source,
  source_len=slen,source_qn=isqn,source_type=source_type,source_rate=source_rate,channels=source_channels,analysis_channels=analysis_channels,channel_mode=channel_mode,file=file,
  offset=R.GetMediaItemTakeInfo_Value(take,'D_STARTOFFS'),pitch=R.GetMediaItemTakeInfo_Value(take,'D_PITCH'),
  ppitch=R.GetMediaItemTakeInfo_Value(take,'B_PPITCH'),pan=R.GetMediaItemTakeInfo_Value(take,'D_PAN'),
  gain=take_gain,item_gain=item_gain,analysis_gain=abs(item_gain*take_gain),name=R.GetTakeName(take) or 'Audio',guid=guid,
  tracknum=R.GetMediaTrackInfo_Value(track,'IP_TRACKNUMBER'),takeindex=R.GetMediaItemTakeInfo_Value(take,'IP_TAKENUMBER'),
  generated=generated or '',temp=temp or ''}
end
function Core.selection(project)
 local list={}
 for i=0,R.CountSelectedMediaItems(project)-1 do
  local item=R.GetSelectedMediaItem(project,i);local info,err=Core.item_info(project,item)
  if not info then return nil,err end
  list[#list+1]=info
 end
 table.sort(list,function(a,b) if a.tracknum~=b.tracknum then return a.tracknum<b.tracknum end;if a.pos~=b.pos then return a.pos<b.pos end;return a.guid<b.guid end)
 if #list==0 then return nil,'元になる音声アイテムを選択してください。' end
 return list
end
function Core.collect_track_pool(project,track)
 local out={};if not track then return out end
 for i=0,R.CountTrackMediaItems(track)-1 do
  local item=R.GetTrackMediaItem(track,i)
  if item then
   local generated,temp=Core.item_tags(item)
   if (generated or '')=='' and (temp or '')=='' then
    local info=Core.item_info(project,item);if info then out[#out+1]=info end
   end
  end
 end
 table.sort(out,function(a,b) if a.pos~=b.pos then return a.pos<b.pos end return a.guid<b.guid end)
 return out
end
-- Idle polling stays intentionally cheap. Selection changes and add/remove operations
-- are detected from item pointers; ordinary edits are covered by ProjectStateChangeCount.
-- Expensive source/file metadata is only rebuilt after one of those cheap signals changes.
function Core.selection_signature(project)
 local n=R.CountSelectedMediaItems(project);local parts={tostring(n)}
 for i=0,n-1 do parts[#parts+1]=tostring(R.GetSelectedMediaItem(project,i)) end
 return table.concat(parts,'|')
end
function Core.track_topology_signature(list)
 local tracks={};local ordered={}
 for _,v in ipairs(list or {}) do if v.track and not tracks[v.track] then tracks[v.track]=true;ordered[#ordered+1]={track=v.track,num=v.tracknum or 0} end end
 table.sort(ordered,function(a,b)return a.num<b.num end)
 local parts={}
 for _,entry in ipairs(ordered) do
  local track=entry.track;local n=R.CountTrackMediaItems(track);parts[#parts+1]='T'..tostring(entry.num)..':'..tostring(n)
  for i=0,n-1 do parts[#parts+1]=tostring(R.GetTrackMediaItem(track,i)) end
 end
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
 if not v or not v.item then return nil,'音声アイテム参照がありません' end
 if type(R.ValidatePtr)=='function' and not R.ValidatePtr(v.item,'MediaItem*') then return nil,'音声アイテム参照が無効です' end
 local take=R.GetActiveTake(v.item)
 if not take or R.TakeIsMIDI(take) then return nil,'音声Takeを取得できません' end
 local source=R.GetMediaItemTake_Source(take)
 if not source then return nil,'音声ソースを取得できません' end
 -- PCM_source pointers are owned by REAPER and can be replaced when project state
 -- changes. Never trust the pointer cached by a previous selection poll: reacquire
 -- it from the live take immediately before every source-level API call.
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
 local source,parent_or_reason=Core.refresh_source_ref(v)
 if not source then return false,parent_or_reason end
 if v.source_qn or not finite(v.source_len) or v.source_len<=0 or not v.file or v.file=='' then return false,'通常の音声ファイル以外' end
 if parent_or_reason or R.GetTakeNumStretchMarkers(v.take)>0 then return false,'反転・セクション・ストレッチ素材' end
 if v.offset<0 or v.offset+v.len*v.rate>v.source_len+1e-6 then return false,'ループまたはソース外の区間' end
 if not finite(v.analysis_channels) or v.analysis_channels<1 or v.analysis_channels>2 then return false,'LUFS検出はモノ／ステレオのみ' end
 if v.source_len>3600 then return false,'ソースが60分を超えています' end
 return true
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
 -- Build an independent PCM_source for the temporary analysis take. Passing the
 -- project-owned source pointer around between deferred frames is fragile because
 -- REAPER may replace that pointer as item/take state changes.
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
 local j={project=project,track=v.track,temp_item=item,temp_take=take,info=v,offset=0,total=ceil(v.source_len*Core.SOURCE_SR),regions={},ring={},ring_index=1,ring_sum=0,fast_ring={},fast_index=1,fast_sum=0,bin_energy=0,bin_peak=0,bin_samples=0,bin_index=0,states={},opened=nil,quiet=nil,anchor=nil,preview={},preview_max=0,preview_scale=Core.SOURCE_PREVIEW_BINS/max(1,ceil(v.source_len*1000))}
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
  if j.bin_samples>0 then source_finish_bin(j) end
  if j.opened then source_finish_region(j,j.opened,j.info.source_len,j.anchor);j.opened=nil end
  local result={regions=j.regions,detected=#j.regions,settings=tcopy(Core.SOURCE_DETECT),preview=j.preview,preview_max=j.preview_max or 0,source_len=j.info.source_len};Core.source_cleanup(j);j.done=true;return true,result
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
 -- Track-item candidates are already user-cut variations. Do not scan their
 -- entire files again. A 1 kHz peak-envelope pass over only the used span is
 -- enough to find the representative summit cheaply; 100/400 ms smoothed
 -- peak-energy terms keep the anchor from chasing a single-sample spike.
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
 local duration=ctx.duration
 local source_len=target_info.source_len or 0
 -- Candidate identity belongs to the detected region (or the cut track item),
 -- not to the aligned offset.  First decide whether THIS candidate has any
 -- legal start position that can hold the requested duration.  These bounds do
 -- not depend on absolute-vs-relative timing, so candidate counts stay stable.
 -- Then clamp only inside that candidate's own start range.  Never push a later
 -- region backwards into an earlier region merely to make the source duration
 -- fit -- that used to make e.g. region 2 audibly play region 1 in relative mode.
 local lo=max(0,target_region.start or 0)
 local hi=min(source_len-duration,target_region.finish or source_len)
 if track_item then
  -- A separately cut track item is one candidate.  Its used source span is the
  -- hard boundary for the generated start position.
  local a=target_info.offset;local b=target_info.offset+target_info.len*target_info.rate
  lo=max(lo,a);hi=min(hi,b-duration)
 end
 if hi<lo-1e-9 then return nil end
 off=clamp(off,lo,max(lo,hi))
 return {offset=off,original=false,region=target_region._index or 0,anchor=target_region.anchor,file=target_info.file,
  id=id,sort_key=sort_key or 0,track_item=track_item and true or false,track_guid=track_item and target_info.guid or nil,
  track_ref=track_item and target_info.item or nil,source_name=track_item and target_info.name or nil,channel_mode=target_info.channel_mode or 0}
end
function Core.source_variants(v,analysis,timing_mode,track_candidates,track_anchor_cache)
 local ctx,why=Core.source_context(v,analysis);v.variants=nil;timing_mode=timing_mode or 2
 if not ctx then return nil,why,nil end
 local out={};local orig_id='orig:'..tostring(v.guid)
 out[#out+1]={offset=v.offset,original=true,region=ctx.index,anchor=ctx.region.anchor,file=v.file,id=orig_id,sort_key=ctx.index}
 for i,r in ipairs(ctx.regions) do
  r._index=i
  if i~=ctx.index then
   local c=Core.aligned_source_variant(v,ctx,v,r,timing_mode,'segment:'..tostring(v.guid)..':'..i,i,false)
   if c then out[#out+1]=c end
  end
 end
 local track_added=0
 -- Same-track cut items are a fallback source only. If the selected source
 -- already contains multiple detected regions, those regions alone form the
 -- variation set. Track items are considered only for a single-region source.
 if #ctx.regions==1 then
  for ti,cand in ipairs(track_candidates or {}) do
   local eligible=Core.source_eligible(cand)
   local used_duration=(cand.len or 0)*(cand.rate or 1)
   -- A cut item is itself one variation. It does not need source-wide
   -- segmentation; only its representative summit is measured.
   if eligible and used_duration+1e-9>=ctx.duration then
    local anchor=Core.quick_track_anchor(cand,track_anchor_cache)
    local region={start=cand.offset,finish=cand.offset+used_duration,raw_start=cand.offset,raw_finish=cand.offset+used_duration,
     anchor=clamp(anchor,cand.offset,cand.offset+used_duration),_index=1}
    local c=Core.aligned_source_variant(v,ctx,cand,region,timing_mode,'track:'..tostring(cand.guid),100000+ti,true)
    if c then out[#out+1]=c;track_added=track_added+1 end
   end
  end
 end
 -- Do not deduplicate by the ALIGNED file+offset pair.  Edge clamping can make
 -- two different detected regions land on the same start in one timing mode but
 -- not the other, which previously changed the displayed candidate count.  The
 -- stable candidate id represents the detected variation itself.
 local seen,unique={},{}
 for _,c in ipairs(out) do
  local k=c.id or ((c.file or '')..'|'..tostring(c.region or 0)..'|'..tostring(c.track_guid or ''))
  if not seen[k] then seen[k]=true;unique[#unique+1]=c end
 end
 out=unique;table.sort(out,function(a,b) return (a.sort_key or 0)<(b.sort_key or 0) end);v.variants=out
 if #out<=1 then return nil,string.format('検出区間 %d / 使用可能 1：バリエーションなし',#ctx.regions),ctx end
 local base
 if timing_mode==2 then local side_name=ctx.side<0 and '山より前' or '山より後';base=string.format('区間相対 %s %.1f%%',side_name,ctx.ratio*100)
 else base=string.format('山オフセット %.1f ms',ctx.anchor_rel*1000) end
 return out,string.format('候補 %d（同一素材 %d / 同一トラック %d） / %s',#out,#ctx.regions,track_added,base),ctx
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
 -- Pitch Curve is zero-referenced: the graph center is always exactly 0 st.
 -- The lower/upper settings define the available negative/positive excursion from zero.
 lo=min(0,tonumber(lo) or 0);hi=max(0,tonumber(hi) or 0)
 if not guide_enabled then for i=1,n do t[i]=rng(lo,hi) end;return t end
 local pts=Core.curve_guide_decode(guide_data,range_start,range_end,guide_start,guide_end,true)
 if #pts<2 then for i=1,n do t[i]=rng(lo,hi) end;return t end
 n=Core.curve_guide_auto_points(pts)
 local span=max(1e-9,hi-lo)
 -- Randomize the amount separately on each side while preserving the 0-st axis.
 -- A guide point on the center line therefore remains exactly 0 st in every variation.
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
 local q0,q1=total*a,total*b;local active=max(0,q1-q0);local markers={{pos=0,src=0}}
 local out=q0
 if q0>1e-9 then markers[#markers+1]={pos=out,src=q0} end
 if active>1e-9 and values and #values>0 then
  local steps=clamp(max(8,(#values-1)*8),8,192);local prevq=q0
  for j=1,steps do
   local q=q0+active*j/steps;local mid=(j-.5)/steps;local semi=Core.curve_value(values,mid);local factor=2^(semi/12)
   out=out+(q-prevq)/max(1e-6,factor);prevq=q;markers[#markers+1]={pos=out,src=q}
  end
 end
 if q1<total-1e-9 then out=out+(total-q1);markers[#markers+1]={pos=out,src=total}
 elseif markers[#markers].src<total-1e-9 then markers[#markers+1]={pos=out,src=total} end
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

-- Reference TEXTURE analysis is spectral, not time-waveform based.
-- We average several pre-FX FFT frames from the selected take, then keep a compact
-- logarithmic spectrum. A pure sine therefore produces one concentrated spectral
-- feature instead of painting its time-domain oscillation across the whole EQ range.
Core.TEXTURE_SR=48000
Core.TEXTURE_FFT_SIZE=8192
Core.TEXTURE_SPECTRUM_BINS=192
Core.TEXTURE_SPECTRUM_FRAMES=32
Core.TEXTURE_FREQ_MIN=45
Core.TEXTURE_FREQ_MAX=19000
-- Three broad spectral regions are used only as a diversity assist. A region is
-- seeded only when it contains meaningful reference energy; empty regions are
-- never invented (e.g. a pure 1 kHz sine seeds MID only).
Core.TEXTURE_LOW_MAX=250
Core.TEXTURE_MID_MAX=4000
-- Reference spectra are averaged after loudness-normalizing every active FFT
-- frame. This measures spectral character instead of letting a louder file or
-- a single loud transient dominate the texture profile.
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
      -- Per-frame activity floor: at least the top spectral region, but never
      -- more than 30 dB below that frame's strongest component. Each active
      -- frame casts a vote for the bands that are actually present.
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
   -- A gated-out frame breaks continuous spectral residence.
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
  -- Tiny frequency smoothing removes FFT-bin jitter without smearing tonal
  -- material across the spectrum. Adjacent persistent bins also become a useful
  -- width estimate for the EQ stage.
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
 -- Per-track shuffle bag: every registered reference is used once before any
 -- reference can repeat. Different tracks own independent bags.
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
  -- Persistence mode: frequency bands are ranked by how often they remain a
  -- dominant component across time. There is no fixed prominence gate, so a
  -- valid reference always yields at least its longest-lived spectral band.
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
  -- Diversity assist: reserve at most one meaningful positive feature from LOW,
  -- MID and HIGH before continuing the normal score order. This prevents a rich
  -- reference from collapsing into one spectral area, while silence/absent bands
  -- are skipped rather than fabricated.
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
 -- ReaEQ is limited to +/-24 dB per band. Above 100%, split excess gain
 -- into coincident bands so 200% remains a real 2x texture intensity.
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
 -- Two independent perceptual axes. Each pair is a permission range rather
 -- than a binary mode, so both enabled still allows neutral/intermediate results.
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
 for _,v in ipairs(list) do if ((a.items or {})[v.guid] or {})[key] then return true end end
 return false
end
function Core.avoid_blocks(anchor,low,high,blocks,gap_after)
 gap_after=gap_after or 0
 -- blocks are sorted and anchor only moves forward, so one pass is sufficient.
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
   local guid=row.info and row.info.guid or ''
   local bucket=by_source[guid];if not bucket then bucket={};by_source[guid]=bucket end;bucket[#bucket+1]=row
   local track=row.info and row.info.track
   if track then local tb=by_track[track];if not tb then tb={};by_track[track]=tb end;tb[#tb+1]=row end
  end
 end
 -- The selected source item is voice #1. This matters both for finite voice
 -- stealing and for free-item-positioning when the first generated variation
 -- overlaps the source itself.
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
 -- Arrange all sounding items, including the selected originals, in free-item
 -- positioning lanes whenever they actually overlap.
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
  for _,v in ipairs(list) do local ia=(a.items or {})[v.guid] or {};if ia.pitch_curve and R.GetTakeNumStretchMarkers(v.take)>0 then return nil,'ピッチカーブの尺連動は既存ストレッチマーカー付き素材には適用できません。' end end
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
   if ia.timing then jitter=a.lock.timing and shared.timing or rng(s.timing_lo,s.timing_hi)/1000 end
   local row={info=v,rel=v.pos-first+jitter,offset=v.offset,pitch=v.pitch,playrate=v.rate,ppitch=v.ppitch,len=v.len,voice_limit=max(0,floor(tonumber(ia.voice_limit) or 0))}
   if ia.pitch_global then
    local pd=a.lock.pitch_global and shared.pitch or rng(s.pitch_lo,s.pitch_hi)
    if s.pitch_length_mode==1 then row.pitch=v.pitch+pd
    else local f=2^(pd/12);row.playrate=v.rate*f;row.len=v.len/f;row.ppitch=0;row.pitch=v.pitch end
   end
   if ia.pitch_curve then
    row.curve=a.lock.pitch_curve and shared.curve or Core.rand_curve(rng,s.curve_lo,s.curve_hi,s.curve_points,s.curve_guide_enabled,s.curve_guide_data,s.curve_guide_start,s.curve_guide_end,s.curve_start_pct,s.curve_end_pct)
    row.curve_start_pct=s.curve_start_pct;row.curve_end_pct=s.curve_end_pct;row.curve_length_mode=s.curve_length_mode
    if s.curve_length_mode==2 then row.curve_base_len=row.len;row.len,row.curve_link_markers=Core.curve_link_map(row.curve_base_len,row.playrate,row.curve,row.curve_start_pct,row.curve_end_pct);row.ppitch=0 end
   end
   if ia.vibrato then row.vibrato=a.lock.vibrato and shared.vibrato or Core.rand_modulation(rng,s,'vibrato') end
   if ia.tremolo then row.tremolo=a.lock.tremolo and shared.tremolo or Core.rand_modulation(rng,s,'tremolo') end
   if ia.volume then local vd=a.lock.volume and shared.volume or rng(s.volume_lo,s.volume_hi);row.volume=v.gain*10^(vd/20) end
   if ia.pan then local pv=a.lock.pan and shared.pan or rng(s.pan_lo,s.pan_hi);row.pan=pv/100 end
   if ia.eq_texture then
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
   if ia.eq_tone then row.tone=a.lock.eq_tone and shared.tone or Core.rand_tone(rng,s) end
   if ia.source then local sv=Core.pick_candidate(v,pools,rng,s.source_order);if sv then row.offset=sv.offset or v.offset;row.source_file=sv.file;row.source_name=sv.source_name;row.source_variant_id=sv.id;row.source_track_item=sv.track_item==true;row.source_track_guid=sv.track_guid;row.source_track_ref=sv.track_ref;row.source_channel_mode=sv.channel_mode;row.substituted=(not sv.original) or abs(row.offset-v.offset)>1e-9 end end
   low=min(low,row.rel);high=max(high,row.rel+row.len);g.rows[#g.rows+1]=row
  end
  local anchor
  if s.interval_mode==1 then
   anchor=prev_high+s.interval-low
   anchor=Core.avoid_blocks(anchor,low,high,blocks,s.interval)
  else
   -- Treat the selected source as variation 0: the first generated head is one
   -- interval after the original head, so short intervals can intentionally overlap it.
   if not head_first then local first_anchor=Core.avoid_blocks(first+s.interval-low,low,high,blocks,0);head_first=first_anchor+low end
   anchor=head_first+(n-1)*s.interval-low
  end
  g.first=anchor+low;g.last=anchor+high;g.anchor=anchor
  for _,row in ipairs(g.rows) do row.pos=anchor+row.rel end
  prev_high=g.last;groups[#groups+1]=g
 end
 Core.apply_voice_policy(groups,s)
 return groups
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
  if not R.TakeFX_SetParamNormalized(take,fx,param,n) then error('EQ値を設定できません。',0) end
  local ok,text=R.TakeFX_GetFormattedParamValue(take,fx,param);if not ok then error('EQのパラメーター単位を取得できません。',0) end;return parse(text)
 end
 local lo,hi=0,1;local av,bv=value(lo),value(hi);local low,high=min(av,bv),max(av,bv)
 -- Internal texture recipes may intentionally request values beyond a particular
 -- ReaEQ build's range. Clamp to the nearest supported value instead of aborting.
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
 -- ReaEQ band gain is a linear -24..+24 dB parameter. Do not use
 -- TakeFX_FormatParamValueNormalized() here: older REAPER builds can return
 -- incorrect formatted values for ReaEQ gain and make range probing fail.
 target=clamp(tonumber(target) or 0,-24,24)
 return (target+24)/48
end
function Core.set_eq_value(take,fx,param,target,kind)
 local n
 if kind=='gain' then n=Core.reaeq_gain_normalized(target)
 else n=Core.eq_normalized(take,fx,param,target,kind) end
 if not R.TakeFX_SetParamNormalized(take,fx,param,n) then error('EQパラメーターを設定できません。',0) end
end
function Core.set_eq_fixed(take,fx,param,target,kind)
 local key=param..'|'..tostring(target)..'|'..tostring(kind or '')
 local n=Core.EQ_FIXED_CACHE[key]
 if n==nil then n=Core.eq_normalized(take,fx,param,target,kind);Core.EQ_FIXED_CACHE[key]=n end
 if not R.TakeFX_SetParamNormalized(take,fx,param,n) then error('EQパラメーターを設定できません。',0) end
end
function Core.add_reaeq(take)
 local fx=R.TakeFX_AddByName(take,'ReaEQ (Cockos)',-1);if fx<0 then error('ReaEQ (Cockos) を追加できません。',0) end
 Core.hide_take_fx(take,fx)
 if not R.TakeFX_SetPresetByIndex(take,fx,-2) then error('ReaEQの初期状態を設定できません。',0) end
 return fx
end
function Core.add_texture_eq(take,bands)
 bands=bands or {};local added=0
 for base=1,#bands,2 do
  local fx=Core.add_reaeq(take);added=added+1
  local a=bands[base];local b=bands[base+1]
  if a then
   Core.set_eq_value(take,fx,3,a.freq,'freq');Core.set_eq_value(take,fx,4,a.gain,'gain');Core.set_eq_value(take,fx,5,a.bw,'bw')
  end
  if b then
   Core.set_eq_value(take,fx,6,b.freq,'freq');Core.set_eq_value(take,fx,7,b.gain,'gain');Core.set_eq_value(take,fx,8,b.bw,'bw')
  end
  pcall(R.TakeFX_SetNamedConfigParm,take,fx,'renamed_name',#bands>2 and ('BLT Variant Forge Texture EQ '..ceil(base/2)) or 'BLT Variant Forge Texture EQ')
  Core.hide_take_fx(take,fx)
 end
 return added
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
 -- Move only Variant Forge Texture EQ instances to the front. This is done at bake
 -- time because Tone/original take FX may have been added after generation.
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
  -- Built-in: Item: Apply track/take FX to items (stereo output).
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
 -- BRIGHT/DARK uses a broad low/high tilt; FORWARD/RECESSED acts around presence.
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
 for _,m in ipairs(markers) do
  local idx=R.SetTakeStretchMarker(take,-1,m.pos,(row.offset or 0)+(m.src or 0))
  if idx<0 and m.pos>1e-8 then error('尺連動用ストレッチマーカーを書き込めません。',0) end
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
-- Iterative Douglas-Peucker simplification, bounded in semitones at every input point.
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
  -- Only create an outside 0-st guard when the curve edge is actually non-zero.
  -- A zero-referenced curve already supplies its own 0-st edge point; adding a
  -- second nearby 0-st point serves no purpose and can aggravate Elastique pops.
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
 -- First collapse exact duplicates, then remove only redundant near-neighbours.
 -- This keeps real corners, while short SFX no longer accumulate visually stacked
 -- points that describe essentially the same straight segment.
 local pts={};local last_t=nil
 for _,t in ipairs(times) do
  if not last_t or abs(t-last_t)>1e-8 then
   pts[#pts+1]={t=t,value=Core.fixed_curve_value(row,t,curve_a,curve_b)+Core.vibrato_value(row,t,vib_a,vib_b,vib_playrate,vib_release),shape=0};last_t=t
  end
 end
 pts=Core.simplify_pitch_points(pts,.01)
 -- Ease only the segments that leave or return to the 0-st axis. This preserves
 -- the rest of the randomized curve as linear while making the pitch shifter see
 -- a gentler derivative at the most click-prone boundary.
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
 -- Voice stealing ends the item after the requested release. Disable auto fades
 -- on BOTH sides, then clamp the existing fade-in so it can never overlap the
 -- new fade-out. Convert any positive auto fade-in into an equivalent manual fade.
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
-- Generation uses a frozen settings/item snapshot. The global project revision
-- also advances for our own deferred item/FX updates, so it is not a conflict token.
function Core.generation_targets_valid(snapshot)
 if R.EnumProjects(-1,'')~=snapshot.project then return false end
 for _,v in ipairs(snapshot.items) do
  if not R.ValidatePtr2(snapshot.project,v.item,'MediaItem*')
   or not R.ValidatePtr2(snapshot.project,v.track,'MediaTrack*')
   or R.GetMediaItemTrack(v.item)~=v.track
   or (v.take and R.GetActiveTake(v.item)~=v.take) then return false end
 end
 return true
end
function Core.apply(snapshot,groups,s,checkpoint)
 local project=snapshot.project
 if not Core.generation_targets_valid(snapshot) then return nil,'生成対象が変更されたため中止しました。' end
 local originalSelection={};for i=0,R.CountSelectedMediaItems(project)-1 do originalSelection[#originalSelection+1]=R.GetSelectedMediaItem(project,i) end
 local created={};local free_tracks,free_before={},{};local original_before={};local cleanup_failed={}
 for _,g in ipairs(groups) do for _,row in ipairs(g.rows) do if row.free_mode and row.info and row.info.track then free_tracks[row.info.track]=true end end end
 for _,row in ipairs(groups._voice_originals or {}) do if row.free_mode and row.info and row.info.track then free_tracks[row.info.track]=true end end
 for track in pairs(free_tracks) do local mode=R.GetMediaTrackInfo_Value(track,'I_FREEMODE');if mode~=1 then free_before[track]=mode end end
 R.Undo_BeginBlock2(project);R.PreventUIRefresh(1);local fx_ui_setting=Core.suppress_new_fx_windows()
 local total,done=0,0;for _,g in ipairs(groups) do total=total+#g.rows end
 local pause_at=0
 local function pause()
  if not checkpoint or (done>0 and done<total and R.time_precise()<pause_at) then return end
  Core.restore_new_fx_windows(fx_ui_setting);R.PreventUIRefresh(-1)
  local called,continue,reason=pcall(checkpoint,done/max(1,total))
  R.PreventUIRefresh(1);fx_ui_setting=Core.suppress_new_fx_windows()
  if not called then error(continue,0) end
  if not continue then error(reason or '生成を中止しました。',0) end
  pause_at=R.time_precise()+.008
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
    if row.voice_stolen and not Core.apply_voice_fade(item,row) then error('元アイテムの発音フェードを設定できません。',0) end
    original_state.after=Core.capture_original_item(item)
   end
  end
  for _,g in ipairs(groups) do for _,row in ipairs(g.rows) do
   local v=row.info;local item=R.AddMediaItemToTrack(v.track);if not item then error('複製アイテムを作成できません。',0) end
   local created_entry={item=item,track=v.track,bake_files={}};created[#created+1]=created_entry
   if not R.SetItemStateChunk(item,Core.clone_chunk(v.chunk,R.genGuid),false) then error('アイテムを複製できません。',0) end
   local take=R.GetTake(item,v.takeindex);if not take then error('複製Takeを取得できません。',0) end;R.SetActiveTake(take)
   local output_len=row.render_len or row.len
   if not R.SetMediaItemInfo_Value(item,'D_POSITION',row.pos) or not R.SetMediaItemInfo_Value(item,'D_LENGTH',output_len) then error('位置または長さを設定できません。',0) end
   R.SetMediaItemInfo_Value(item,'I_GROUPID',0);R.SetMediaItemInfo_Value(item,'C_LOCK',0)
   if row.free_mode then
    local lanes=max(1,row.free_lane_count or 1);local lane=clamp(row.free_lane or 1,1,lanes)
    R.SetMediaItemInfo_Value(item,'F_FREEMODE_Y',(lane-1)/lanes);R.SetMediaItemInfo_Value(item,'F_FREEMODE_H',1/lanes)
    -- Keep overlaps layered. Disable automatic overlap fades, but preserve ordinary
    -- manual source fades unless this item is explicitly voice-stolen below.
    R.SetMediaItemInfo_Value(item,'D_FADEINLEN_AUTO',0);R.SetMediaItemInfo_Value(item,'D_FADEOUTLEN_AUTO',0)
   end
   if row.voice_stolen and not Core.apply_voice_fade(item,row) then error('生成アイテムの発音フェードを設定できません。',0) end
   local function set_take(key,value) if not R.SetMediaItemTakeInfo_Value(take,key,value) then error('Take設定に失敗しました：'..key,0) end end
   if row.substituted then
    R.SetMediaItemInfo_Value(item,'B_LOOPSRC',0)
    -- A track-item candidate is an explicit source choice. Always rebind the
    -- active take to that candidate's file (even when the path equals the
    -- original) so a separately-cut item can never silently fall back to the
    -- cloned source state.
    if row.source_track_item and row.source_track_guid then
     -- Use the candidate item's live project-owned PCM_source as the authority.
     -- REAPER duplicates a source that already belongs to a project when it is
     -- assigned with SetMediaItemTake_Source(), so the candidate item itself is
     -- untouched while its exact media source is carried into this variation.
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
   if row.curve or row.vibrato then Core.pitch_curve(project,item,take,row) end;if row.volume then set_take('D_VOL',row.volume) end;if row.tremolo then Core.apply_tremolo(project,item,take,row) end
   if row.eq and #row.eq>0 then
    created_entry.texture_fx_count=Core.add_texture_eq(take,row.eq)
   end
   if row.tone then Core.add_tone_eq(take,row.tone) end
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
 R.PreventUIRefresh(-1);if next(free_tracks) then R.UpdateTimeline() end;R.UpdateArrange();R.Undo_EndBlock2(project,ok and ('BLT Variant Forge: '..#groups..' variations') or 'BLT Variant Forge: failed (copies removed)',4)
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
local A={project=R.EnumProjects(-1,''),items={},poll=0,status='',warning=false,job=nil,progress=0,closed=false,closing=false,last_created=nil,item_scroll=0,matrix_selected={},matrix_anchor=nil,wave_guid=nil,texture_bank={},texture_preview_index=1,scroll_drag=nil,field_drag=nil,source_cache={},track_anchor_cache={},source_queue={},source_queue_i=1,source_queue_done=false,source_job=nil,source_progress=0,source_execute_pending=nil,source_auto={},track_signature='',selection_signature='',track_candidate_pools={},item_by_guid={},persist_dirty=false,persist_at=0,pending_bake_delete=Core.load_pending_bake_deletes(),pending_bake_delete_at=0,pending_bake_retry_delay=2,stale_temp_projects=Core.STALE_TEMP_PROJECTS,stale_temp_retry_at=0,bake_scan_record=nil,bake_scan_revision=nil,bake_scan_count=0,apply={lock=lock_apply,items={}}}
A.source_cache_serial=0;A.item_state_serial=0;A.item_state_used={}
local W,H=1180,1098
local C={
  bg={0.018,0.030,0.055}, bg2={0.030,0.090,0.180},
  panel={0.040,0.068,0.110}, panel2={0.055,0.125,0.205},
  field={0.018,0.040,0.080}, edge={0.145,0.285,0.445}, edge2={0.360,0.650,0.900},
  text={0.955,0.980,1.000}, muted={0.690,0.780,0.875}, faint={0.390,0.505,0.635},
  accent={0.120,0.490,0.980}, accent2={0.650,0.895,1.000}, accent3={0.045,0.235,0.520},
  focus={0.225,0.610,1.000}, focus2={0.690,0.900,1.000}, ink={0.018,0.075,0.160},
  hover={0.430,0.790,1.000}, warn={1.000,0.755,0.490}, correct={1.000,0.180,0.260}, correct2={1.000,0.650,0.700}, lock={1.000,0.790,0.260}, lock2={1.000,0.920,0.600}, quiet={0.300,0.360,0.440}, source_alt={0.300,0.930,0.700}, source_alt2={0.730,1.000,0.880}
}
local fonts={"Yu Gothic UI","Segoe UI","Consolas"}
if R.GetOS():match("OSX") then fonts={"Hiragino Sans","Helvetica Neue","Menlo"} end
if R.GetOS():match("Linux") then fonts={"sans-serif","sans-serif","monospace"} end

local scale,ox,oy=1,0,0
 BLT.viewport(scale,gfx.ext_retina or 1);local frame_clock,frame_dt,particle_dt=R.time_precise(),1/60,1/60
local animations_active=true
-- Visual effects run only around real activity.  Keeping this separate from
-- window/input activity lets the deferred loop stay responsive without forcing
-- a full redraw while the UI is simply sitting open.
local effects_active=true
local ui_anim_time,ambient_anim_time=0,0
local motion={}
local icon_particles,icon_clock,icon_serial={},0,0
local widgets={}
local widget_count=0
local edit=nil
local field_flash={}
local voice_flash={}
local down_last,pressed=false,nil
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
-- Hover identity is still tracked for state transitions, but pointer movement itself
-- is again allowed to keep the visual layer alive.  Font batching now makes those
-- active frames cheap enough that we can favor the original, more fluid BLT feel.
local last_hover_key=nil
local hover_anim_until=R.time_precise()+.35
local EFFECT_IDLE_TAIL=2.5
local effect_activity_until=R.time_precise()+.20
-- The full UI is cached without the two matrix scroll-hint overlays. During
-- idle we PRESENT that cached frame with a single blit, then redraw only the
-- animated hints. gfx.update() swaps/clears the window backbuffer, so updating
-- only a tiny rectangle would make the untouched area disappear on the next
-- frame (especially after deactivation/expose). A full cached blit is cheap and
-- keeps the expensive native-gfx UI itself asleep.
local FRAME_CACHE=127
local frame_cache_w,frame_cache_h=0,0
local frame_cache_valid=false
local suppress_scroll_hints=false
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
  -- Restart gently, then settle back to the normal cue speed.  The important
  -- part is the other direction: when activity ends we coast to a real stop.
  if scroll_anim_speed<=0 then scroll_anim_speed=SCROLL_HINT_SPEED*.16 end
  local a=1-math.exp(-10*dt)
  scroll_anim_speed=scroll_anim_speed+(SCROLL_HINT_SPEED-scroll_anim_speed)*a
 else
  if not scroll_anim_coast_start then
   scroll_anim_coast_start=now;scroll_anim_coast_speed=scroll_anim_speed
  end
  local t=clamp((now-scroll_anim_coast_start)/SCROLL_HINT_COAST,0,1)
  -- Quadratic ease-out in velocity: movement visibly slows instead of snapping
  -- to a halt, and reaches an exact stop after SCROLL_HINT_COAST seconds.
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
-- Native font configuration was the largest measured render cost.  Keep the
-- exact typography/layout, but avoid rebuilding the same native fonts for every
-- label: persistent font slots + batched text submission reduce setfont churn.
local C_DEFAULT={}
for k,val in pairs(C) do
  if type(val)=="table" and type(val[1])=="number" and type(val[2])=="number" and type(val[3])=="number" then C_DEFAULT[k]={val[1],val[2],val[3]} end
end
local CHROME_DEFAULT
local Chameleon={enabled=R.GetExtState(Core.SECTION,"chameleon")=="1",signature=nil,poll_at=0,poll_interval=3.0}
local function chameleon_notify(text)
  if UI.notice then UI.notice(text,false) else A.status=text;A.warning=false end
end
local function chameleon_host_refresh()
  frame_cache_valid=false;redraw_dirty=true
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
  -- Some BLT hosts have a red role; Variant Forge uses correct/correct2 instead.
  if C_DEFAULT.red then out.red=fit_accent_to_bg(C_DEFAULT.red,bg,text_is_light) end
  return out
end

function Chameleon.restore()
  for k,v in pairs(C_DEFAULT) do C[k]=ccopy(v) end
  Chrome.mint=ccopy(CHROME_DEFAULT.mint)
  Chrome.ice=ccopy(CHROME_DEFAULT.ice)
  chameleon_host_refresh()
end

function Chameleon.apply(palette)
  for k,v in pairs(palette) do C[k]=v end
  Chrome.mint=ccopy(C.accent2)
  Chrome.ice=ccopy(C.focus2)
  chameleon_host_refresh()
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
  BLT.store(Core.SECTION,"chameleon",Chameleon.enabled and "1" or "0",true)
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

-- Reuse command records and font buckets across frames; counts delimit live data.
local text_queue={count=0,buckets={},order={},order_count=0,specs={},spec_scale=nil}
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
    -- Release dynamic strings/colors even when a frame was interrupted.
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
  -- Exact/near-exact fast paths only; the normal gradient appearance is kept.
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
function Core.draw_fx_fix_shape(x,y,w,h,cut,rad,c,a,edge,edge_a)
  cut=cut or 7;rad=rad or 7
  local pts={{x+cut,y},{x+w-rad,y}}
  local cx,cy=x+w-rad,y+rad
  for i=1,4 do local ang=(-math.pi/2)+(math.pi/2)*(i/4);pts[#pts+1]={cx+math.cos(ang)*rad,cy+math.sin(ang)*rad} end
  pts[#pts+1]={x+w,y+h-cut};pts[#pts+1]={x+w-cut,y+h};pts[#pts+1]={x+rad,y+h}
  cx,cy=x+rad,y+h-rad
  for i=1,4 do local ang=(math.pi/2)+(math.pi/2)*(i/4);pts[#pts+1]={cx+math.cos(ang)*rad,cy+math.sin(ang)*rad} end
  pts[#pts+1]={x,y+cut}
  cx,cy=x+w/2,y+h/2;color(c,a)
  for i=1,#pts do local q=pts[i%#pts+1];local r=pts[i];gfx.triangle(sx(cx),sy(cy),sx(r[1]),sy(r[2]),sx(q[1]),sy(q[2])) end
  if edge then for i=1,#pts do local r,q=pts[i],pts[i%#pts+1];line(r[1],r[2],q[1],q[2],edge,edge_a or 1) end end
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
  widget_count=widget_count+1;local item=widgets[widget_count]
  if not item then item={};widgets[widget_count]=item end
  item.id,item.x,item.y,item.w,item.h,item.fn,item.hint,item.enabled=id,x,y,w,h,fn,hint,enabled~=false
  if inside(x,y,w,h) and hint then hover_hint=hint end
end
local function fmt(n)
  if abs(n-floor(n+0.5))<1e-8 then return tostring(floor(n+0.5)) end
  return string.format("%.2f",n):gsub("0+$",""):gsub("%.$","")
end

function UI.small_button(id,text,x,y,w,h,fn,hint,enabled,strong_edge,pulse)
  enabled=enabled~=false
  local hovered=inside(x,y,w,h) and enabled
  local a=animate("small_"..id,hovered and 1 or 0)
  local pa=0
  if pulse and enabled then
    local u=.5-.5*math.cos(ambient_anim_time*1.35)
    pa=.10+.90*(u*u*(3-2*u))
  end
  if id=='bake_fx' then
    if pa>0.001 then
      Core.draw_fx_fix_shape(x-8,y-7,w+16,h+14,9,9,C.focus,.008+.020*pa)
      Core.draw_fx_fix_shape(x-6.5,y-5.5,w+13,h+11,8.5,8.5,C.focus,.011+.028*pa)
      Core.draw_fx_fix_shape(x-5,y-4.5,w+10,h+9,8,8,C.accent2,.015+.038*pa)
      Core.draw_fx_fix_shape(x-3.5,y-3,w+7,h+6,7.5,7.5,C.focus2,.021+.052*pa)
      Core.draw_fx_fix_shape(x-2,y-1.5,w+4,h+3,7,7,C.accent,.030+.070*pa)
    end
    local ea=.38+.30*a+.36*pa
    Core.draw_fx_fix_shape(x,y,w,h,7,7,C.panel2,.96,C.accent2,ea)
    Core.draw_fx_fix_shape(x+1,y+1,w-2,h-2,6,6,C.panel,.50+.12*a+.10*pa,C.focus,.20+.16*pa)
    if pa>0.001 then Core.draw_fx_fix_shape(x+2,y+2,w-4,h-4,5,5,C.accent3,.035+.080*pa) end
    if hovered then line(x+7,y+1,x+w-9,y+1,C.focus2,.72) end
    label(text,x,y+2,13,enabled and C.text or C.faint,1,w,h-3,5,true)
    register(id,x,y,w,h,fn,hint,enabled)
    return
  end
  if pa>0.001 then
    rect(x-9,y-7,w+18,h+14,C.focus,0.010+0.022*pa)
    rect(x-6,y-5,w+12,h+10,C.accent,0.018+0.032*pa)
    rect(x-3,y-3,w+6,h+6,C.accent2,0.025+0.052*pa)
    line(x-4,y-3,x+w+4,y-3,C.focus2,0.10+0.34*pa)
    line(x-4,y+h+3,x+w+4,y+h+3,C.focus,0.07+0.25*pa)
  end
  local danger=id=='undo_gen' and enabled
  gradient(x,y,w,h,C.panel2,C.panel,0.34+0.16*a+0.055*pa,0.88)
  if danger then gradient(x,y,w,h,C.correct,C.field,.028+.026*a,.006,true)
  elseif pa>0.001 then gradient(x,y,w,h,C.accent3,C.field,0.05+0.075*pa,0.01,true) end
  local edge_main=danger and C.correct2 or C.accent2;local edge_soft=danger and C.correct or C.edge2
  gradient(x,y,w,1,edge_main,edge_main,0.16+0.50*a+0.25*pa,0.02)
  line(x,y+h,x+w,y+h,danger and C.correct or C.edge,0.46+0.10*pa)
  if a>0.01 or pa>0.01 or danger then rect(x,y,2,h,edge_main,danger and (.45+.20*a) or 0.65*max(a,.62*pa)) end
  local edge_alpha=(strong_edge and 0.58 or 0.28)+(strong_edge and 0.26 or 0.35)*a+0.28*pa
  finish_corners(x,y,w,h,6,false,strong_edge and edge_main or edge_soft,edge_alpha)
  if strong_edge then
    line(x+5,y,x+w-8,y,edge_main,0.34+0.26*a+0.26*pa)
    line(x,y+4,x,y+h-6,edge_main,0.24+0.24*a+0.22*pa)
  end
  local text_color=enabled and ((hovered or pulse) and C.text or C.muted) or C.faint
  label(text,x,y+2,13,text_color,1,w,h-3,5,true)
  register(id,x,y,w,h,fn,hint,enabled)
end
Chrome={
 title_h=26,title='BLT Variant Forge',title_text='V A R I A N T   F O R G E',min_w=860,
 window=nil,mouseDown=false,drag=nil,resize=nil,mouseActive=false,requestClose=false,requestReset=false,chameleonPressed=false,
 resizeCursors={},resizeCursorMode=nil,wheel={installed=false,last_time=nil},
 mint={0.38,0.88,0.72},ice={0.65,0.895,1.0},red={1.0,0.27,0.34},
 is_windows=R.GetOS():match("Win")~=nil,resize_edge=6,resize_corner_band=8,resize_corner_span=24,resize_top_left_guard=30,resize_top_right_guard=110,tooltipHover=nil,tooltipSince=0,tooltipVisible=false,tooltipDelay=.70,
 resize_cursor_id={we=32644,ns=32645,nwse=32642,nesw=32643,arrow=32512}
}
Chrome.min_h=820+Chrome.title_h
Chrome.font=Chrome.is_windows and "Segoe UI" or (R.GetOS():match("OSX") and "Helvetica Neue" or "sans-serif")
CHROME_DEFAULT={mint={Chrome.mint[1],Chrome.mint[2],Chrome.mint[3]},ice={Chrome.ice[1],Chrome.ice[2],Chrome.ice[3]}}

function UI.titlebar_api_ready()
  local required={"JS_Window_Find","JS_Window_IsWindow","JS_Window_GetRect","JS_Window_SetPosition","JS_Window_SetStyle"}
  if Chrome.is_windows then
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

function UI.gfx_window_handle()
  if Chrome.window and R.JS_Window_IsWindow(Chrome.window) then return Chrome.window end
  Chrome.window=R.JS_Window_Find(Chrome.title,true)
  return Chrome.window
end

function UI.wheel_hook_install()
 if not Chrome.is_windows or type(R.JS_WindowMessage_Intercept)~='function' or type(R.JS_WindowMessage_Peek)~='function' or type(R.JS_Window_ScreenToClient)~='function' then return false end
 local hwnd=UI.gfx_window_handle();if not hwnd then return false end
 local ok,rv=pcall(R.JS_WindowMessage_Intercept,hwnd,'WM_MOUSEWHEEL',true)
 Chrome.wheel.installed=ok and rv~=false;return Chrome.wheel.installed
end
function UI.wheel_hook_poll(return_event)
 if not Chrome.wheel.installed then return nil end
 local hwnd=UI.gfx_window_handle();if not hwnd then return nil end
 local ok,peek,pass,time,keys,delta=pcall(R.JS_WindowMessage_Peek,hwnd,'WM_MOUSEWHEEL')
 if not ok or not peek or not time then return nil end
 if Chrome.wheel.last_time and time<=Chrome.wheel.last_time then return nil end
 Chrome.wheel.last_time=time
 if not return_event then return nil end
 delta=tonumber(delta) or 0;if delta>32767 then delta=delta-65536 end;if delta==0 then return nil end
 local sx0,sy0=R.GetMousePosition();local okc,cx,cy=pcall(R.JS_Window_ScreenToClient,hwnd,sx0,sy0)
 if not okc or not finite(cx) or not finite(cy) then return nil end
 return {wheel=delta,x=(cx-ox)/scale,y=(cy-oy)/scale,shift=((tonumber(keys) or 0)&4)~=0}
end

function UI.apply_custom_window_style(target_w,target_h)
  local hwnd=UI.gfx_window_handle()
  if not hwnd then return false end
  local ok,l,t=R.JS_Window_GetRect(hwnd)
  if not R.JS_Window_SetStyle(hwnd,"POPUP") then return false end
  if ok then BLT.position(hwnd,l,t,target_w,target_h,"","") end
  return true
end

function UI.reset_window_size()
  local hwnd=UI.gfx_window_handle()
  if not hwnd then return end
  local ok,l,t=R.JS_Window_GetRect(hwnd)
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

  -- Bottom corners use an L-shaped hit zone instead of requiring the pointer to
  -- sit inside a tiny square. This makes the diagonal cursor much easier to hit
  -- without stealing the ordinary horizontal/vertical edge areas farther away.
  local bottomBand=my>=h-band
  local bottomSpan=my>=h-span
  local leftBand=mx<band
  local rightBand=mx>=w-band
  local leftSpan=mx<span
  local rightSpan=mx>=w-span
  if (bottomBand and leftSpan) or (leftBand and bottomSpan) then return "lb" end
  if (bottomBand and rightSpan) or (rightBand and bottomSpan) then return "rb" end

  -- Never expose resize cursors in the upper-left corner or over the title-bar
  -- controls at upper-right. In particular, the close/reset controls must always
  -- remain clickable right up to the window edge.
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
function UI.set_resize_cursor(mode)
  if not Chrome.is_windows then return end
  local kind=UI.resize_cursor_kind(mode)
  if kind then
    local cursor=Chrome.resizeCursors[kind]
    if not cursor then cursor=R.JS_Mouse_LoadCursor(Chrome.resize_cursor_id[kind]); Chrome.resizeCursors[kind]=cursor end
    if cursor then R.JS_Mouse_SetCursor(cursor) end
    Chrome.resizeCursorMode=kind
  elseif Chrome.resizeCursorMode then
    local cursor=Chrome.resizeCursors.arrow
    if not cursor then cursor=R.JS_Mouse_LoadCursor(Chrome.resize_cursor_id.arrow); Chrome.resizeCursors.arrow=cursor end
    if cursor then R.JS_Mouse_SetCursor(cursor) end
    Chrome.resizeCursorMode=nil
  end
end
function UI.titlebar_cleanup() UI.set_resize_cursor(nil);if Chrome.wheel.installed and Chrome.window and type(R.JS_WindowMessage_Release)=='function' then pcall(R.JS_WindowMessage_Release,Chrome.window,'WM_MOUSEWHEEL') end;Chrome.wheel.installed=false end

function UI.begin_window_resize(mode)
  local hwnd=UI.gfx_window_handle()
  if not hwnd or not mode then return false end
  local ok,l,t,r,b=R.JS_Window_GetRect(hwnd)
  if not ok then return false end
  local sx,sy=R.GetMousePosition()
  Chrome.resize={mode=mode,mouseX=sx,mouseY=sy,left=l,top=t,right=r,bottom=b}
  Chrome.drag=nil
  return true
end

function UI.update_window_resize()
  local d=Chrome.resize
  if not d then return end
  local hwnd=UI.gfx_window_handle()
  if not hwnd then Chrome.resize=nil; return end
  local sx,sy=R.GetMousePosition()
  local dx,dy=sx-d.mouseX,sy-d.mouseY
  local l,t,r,b=d.left,d.top,d.right,d.bottom
  if d.mode:find("l",1,true) then l=math.min(d.left+dx,r-Chrome.min_w) end
  if d.mode:find("r",1,true) then r=math.max(d.right+dx,l+Chrome.min_w) end
  if d.mode:find("t",1,true) then t=math.min(d.top+dy,b-Chrome.min_h) end
  if d.mode:find("b",1,true) then b=math.max(d.bottom+dy,t+Chrome.min_h) end
  BLT.position(hwnd,math.floor(l+.5),math.floor(t+.5),math.max(Chrome.min_w,math.floor(r-l+.5)),math.max(Chrome.min_h,math.floor(b-t+.5)),"","")
end

local VARIANT_TOOLTIPS={close="閉じる",reset="ウィンドウサイズ初期化",chameleon="カメレオンモード（配色をテーマへ擬態）"}

function UI.clear_chrome_tooltip() BLT.clearTooltip() end

function UI.custom_titlebar() BLT.bar() end

function UI.draw_primary_button(id,text,x,y,w,h,fn,hint,enabled)
 enabled=enabled~=false
 local cancelling=A.job~=nil or A.source_execute_pending~=nil
 if cancelling then text='処理を中止';enabled=true elseif A.source_job then text='素材を解析中...' end
 PrimaryButton.draw(PrimaryButton.painter,x,y,w,h,text,cancelling and 'CANCEL' or A.source_job and 'SOURCE ANALYSIS' or 'EXECUTE',enabled,A.job~=nil or A.source_job~=nil,A.source_job and A.source_progress or A.job and A.progress or nil,inside(x,y,w,h),pressed==id and (gfx.mouse_cap&1)~=0,R.time_precise(),BLT.host.active())
 register(id,x,y,w,h,fn,hint,enabled)
end

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
local ITEM_DEFAULT={voice_limit=0,pitch_global=false,pitch_curve=false,vibrato=false,tremolo=false,timing=false,volume=false,pan=false,eq_texture=false,eq_tone=false,source=false}
local WAVE_X,WAVE_Y,WAVE_W,WAVE_H=20,538,1140,168
local MATRIX_X,MATRIX_Y,MATRIX_W,MATRIX_H=20,716,1140,286
local MATRIX_NAME_W=352
local MATRIX_HEADER_H,MATRIX_ALL_H,MATRIX_LOCK_H,MATRIX_ROW_H=31,32,34,34
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
 local present={};A.item_by_guid={}
 for _,v in ipairs(list or {}) do
  present[v.guid]=true;A.item_by_guid[v.guid]=v;A.item_state_serial=A.item_state_serial+1;A.item_state_used[v.guid]=A.item_state_serial
  if not A.apply.items[v.guid] then A.apply.items[v.guid]=tcopy(ITEM_DEFAULT);A.source_auto[v.guid]=false elseif A.source_auto[v.guid]==nil then A.source_auto[v.guid]=false end
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
 local out={}
 for _,cand in ipairs(pool) do if cand.item~=v.item then out[#out+1]=cand end end
 return out
end
function UI.source_status_from_cache(v)
 local eligible,reason
 if v._source_checked then eligible,reason=v._source_eligible,v._source_eligibility_reason else eligible,reason=UI.prepare_source_info(v) end
 v.source_origin=nil
 if not eligible then v.source_ready=true;v.source_available=false;v.source_reason=reason;v.source_detected=0;v.source_candidate_count=0;v.source_display_count=0;v.variants=nil;v.source_context=nil;v.texture_preview=nil;UI.sync_source_checkbox(v);return end
 local cached=UI.source_cache_get(v.source_key)
 if not cached then v.source_ready=false;v.source_available=false;v.source_reason='解析待ち';v.source_detected=nil;v.source_candidate_count=nil;v.source_display_count=nil;v.variants=nil;v.source_context=nil;v.texture_preview=nil;UI.sync_source_checkbox(v);return end
 if cached.error then v.source_ready=true;v.source_available=false;v.source_reason=cached.error;v.source_detected=0;v.source_candidate_count=0;v.source_display_count=0;v.variants=nil;v.source_context=nil;v.texture_preview=nil;UI.sync_source_checkbox(v);return end
 local regions=cached.regions or {}
 v.texture_preview=cached.preview;v.texture_preview_max=cached.preview_max;v.texture_source_len=cached.source_len
 v.track_candidates=#regions==1 and UI.track_candidates_for(v) or nil
 local variants,why,ctx=Core.source_variants(v,cached,S.source_timing_mode,v.track_candidates,A.track_anchor_cache);v.source_context=ctx
 v.source_ready=true;v.source_detected=#regions;v.source_candidate_count=variants and #variants or 1
 v.source_display_count=(#regions>1) and #regions or ((#regions==1) and (1+#(v.track_candidates or {})) or 0)
 v.source_available=variants~=nil and #variants>1;v.source_reason=why
 if #regions==1 and #(v.track_candidates or {})>0 then v.source_origin='track' else v.source_origin='source' end
 UI.sync_source_checkbox(v)
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
 if A.source_job or A.job or A.source_queue_done then return end
 while A.source_queue_i<=#A.source_queue do
  local v=A.source_queue[A.source_queue_i];A.source_queue_i=A.source_queue_i+1
  if v and v.source_key and not A.source_cache[v.source_key] then
   local ok,j=pcall(Core.source_scan_start,A.project,v)
   if ok then A.source_job=j;A.source_progress=0;return
   else UI.source_cache_set(v.source_key,{error=tostring(j):match('^[^\\n]+') or tostring(j)}) end
  end
 end
 -- Finalize the queue exactly once. Previously this block ran on every defer
 -- while idle, repeatedly rebuilding source candidates and dominating idle load.
 A.source_queue_done=true
 for _,v in ipairs(A.items or {}) do UI.source_status_from_cache(v) end
 A.source_progress=0;A.revision=R.GetProjectStateChangeCount(A.project)
end
function UI.refresh()
 local project=R.EnumProjects(-1,'')
 local project_changed=project~=A.project
 if project_changed then
  UI.stop_source_job();A.source_execute_pending=nil;Core.cleanup_stale_temp_items(project)
  A.source_cache={};A.track_anchor_cache={};A.source_cache_serial=0
  A.apply.items={};A.source_auto={};A.item_state_used={};A.item_state_serial=0
  A.matrix_selected={};A.last_created=nil;motion={};voice_flash={};field_flash={}
  collectgarbage('collect')
 end
 A.project=project;local list,err=Core.selection(A.project);A.items=list or {};A.selection_error=err
 UI.ensure_apply_rows(A.items);A.selection_signature=Core.selection_signature(A.project);A.track_signature=Core.track_topology_signature(A.items)
 UI.rebuild_source_queue();UI.prune_source_cache();prune_used_cache(A.track_anchor_cache,TRACK_ANCHOR_LIMIT);A.revision=R.GetProjectStateChangeCount(A.project)
 UI.source_queue_start_next()
end
function UI.changed(key)
 UI.persist_later();A.status='';A.warning=false
 -- Only source timing changes alter the already-detected candidate offsets.
 if key=='source_timing_mode' then for _,v in ipairs(A.items or {}) do UI.source_status_from_cache(v) end end
end
function UI.assignment_changed()
 UI.persist_later();A.status='';A.warning=false
 local restore=A.source_execute_pending and A.source_execute_pending.restore_selection
 A.source_execute_pending=nil;if restore and UI.restore_item_selection then UI.restore_item_selection(A.project,restore,true) end
 if A.source_job and not UI.source_requested(A.apply,A.source_job.info) then UI.stop_source_job() end
 UI.rebuild_source_queue();UI.source_queue_start_next()
end
function UI.feature_available(v,key)
 if key~='source' then return true end
 if not v._source_checked then UI.prepare_source_info(v) end
 return v._source_eligible==true
end
function UI.all_feature_state(key)
 local any,all,count=false,true,0
 for _,v in ipairs(A.items) do if UI.feature_available(v,key) then count=count+1;local on=(A.apply.items[v.guid] or {})[key]==true;any=any or on;all=all and on end end
 return count>0 and all,any,count
end
local FEATURE_BOUNDS={pitch_global={20,166,220,150},volume={250,166,220,150},timing={480,166,220,150},pan={710,166,220,150},source={940,166,220,150},pitch_curve={20,326,560,200},vibrato={20,326,560,200},tremolo={20,326,560,200},eq_texture={590,326,275,200},eq_tone={875,326,285,200}}
local FEATURE_TABS={pitch_curve={205,114},vibrato={323,108},tremolo={435,125}}
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
   if tab then rect(tab[1],344,tab[2],22,yellow,.32*a);rect(tab[1],365,tab[2],2,yellow,.95*a) end
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
  elseif key=='source' then A.apply.items[v.guid][key]=false end
 end
 UI.assignment_changed()
end
function UI.set_all_features(value)
 if value then for _,c in ipairs(FEATURE_COLUMNS) do UI.flash_feature(c.key) end end
 for _,v in ipairs(A.items) do
  local row=A.apply.items[v.guid]
  for _,c in ipairs(FEATURE_COLUMNS) do
   if UI.feature_available(v,c.key) then row[c.key]=value;if c.key=='source' then A.source_auto[v.guid]=false end
   elseif c.key=='source' then row[c.key]=false end
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
   if A.matrix_selected[v.guid] and A.apply.items[v.guid] then A.apply.items[v.guid].voice_limit=value end
  end
 elseif A.apply.items[guid] then
  A.apply.items[guid].voice_limit=value
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
 for _,v in ipairs(A.items or {}) do local row=A.apply.items[v.guid];if row then row.voice_limit=UI.voice_step_value(row.voice_limit,dir) end end
 UI.assignment_changed()
end

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
local function field_flash_value(key)
 local ft=field_flash[key];if not ft then return 0 end
 local age=R.time_precise()-ft
 if age>=1.35 then field_flash[key]=nil;return 0 end
 local q=clamp(age/1.35,0,1);return 1-(q*q*(3-2*q))
end
local function begin_field_edit(key,title)
 edit={key=key,title=title,text=fmt(S[key]),selected=true}
end
function UI.field(key,title,x,y,w,unit,enabled)
 enabled=enabled~=false and not A.job
 local h=32;local active=edit and edit.key==key;local a=animate('field_'..key,active and 1 or ((inside(x,y,w,h) and enabled) and .3 or 0))
 local flash=field_flash_value(key)
 label(title,x,y-18,11,enabled and C.muted or C.faint,1,w,17,0,false);gradient(x,y,w,h,C.field,C.panel,.98,.56)
 if flash>0 then
  rect(x-5,y-5,w+10,h+10,C.correct,.024*flash);rect(x-2,y-2,w+4,h+4,C.correct2,.048*flash)
  gradient(x,y,w,h,C.correct,C.field,.22*flash,.02*flash,true)
 end
 line(x,y,x+w,y,flash>0 and C.correct2 or C.edge2,.18+.35*a+.42*flash);line(x,y+h,x+w,y+h,C.edge,.38+.25*a+.22*flash);line(x,y,x,y+h,flash>0 and C.correct or C.accent2,.22+.48*a+.48*flash)
 finish_corners(x,y,w,h,6,false,flash>0 and C.correct2 or C.edge2,.28+.38*a+.52*flash)
 local t=active and edit.text or fmt(S[key]);local uw=unit=='' and 0 or measure(unit,10,3,false)+10
 if active and edit.selected then rect(x+5,y+5,max(5,w-uw-12),h-10,C.focus2,.85) end
 label(t,x+7,y,18,active and edit.selected and C.ink or (enabled and C.text or C.faint),3,w-uw-13,h,6,true)
 if unit~='' then right_label(unit,x+w-7,y+10,10,C.muted,3,false) end
 local hint=title..'：クリック入力 / 上下ドラッグ / ホイール変更'
 if A.setting_allows_fine and A.setting_allows_fine(key) then hint=hint..' / Shiftで微調整' end
 register('field_'..key,x,y,w,h,function() begin_field_edit(key,title) end,hint,enabled)
end
function A.compact_field(key,title,x,y,w,unit,enabled)
 enabled=enabled~=false and not A.job
 local h=32;local active=edit and edit.key==key;local hot=inside(x,y,w,h) and enabled
 local aa=animate('cfield_'..key,active and 1 or (hot and .32 or 0))
 local flash=field_flash_value(key)
 gradient(x,y,w,h,C.field,C.panel,.98,.60)
 if flash>0 then
  rect(x-5,y-5,w+10,h+10,C.correct,.024*flash);rect(x-2,y-2,w+4,h+4,C.correct2,.052*flash)
  gradient(x,y,w,h,C.correct,C.field,.22*flash,.02*flash,true)
 end
 line(x,y+h,x+w,y+h,C.edge,.34+.22*aa+.18*flash);line(x,y,x,y+h,flash>0 and C.correct or C.accent2,.20+.44*aa+.42*flash)
 finish_corners(x,y,w,h,5,false,flash>0 and C.correct2 or C.edge2,.24+.34*aa+.50*flash)
 local title_w=w>150 and w*.72 or w*.54
 label(title,x+7,y+2,11,enabled and C.muted or C.faint,1,title_w,h-4,4,true)
 local t=active and edit.text or fmt(S[key]);local uw=(unit and unit~='') and measure(unit,9.5,3,false)+8 or 0
 if active and edit.selected then rect(x+title_w,y+5,max(8,w-title_w-uw-7),h-10,C.focus2,.82) end
 right_label(t,x+w-uw-7,y+7,16,active and edit.selected and C.ink or (enabled and C.text or C.faint),3,true)
 if unit and unit~='' then right_label(unit,x+w-4,y+11,9.5,enabled and C.muted or C.faint,3,false) end
 local hint=title..'：クリック入力 / 上下ドラッグ / ホイール変更'
 if A.setting_allows_fine and A.setting_allows_fine(key) then hint=hint..' / Shiftで微調整' end
 register('field_'..key,x,y,w,h,function() begin_field_edit(key,title) end,hint,enabled)
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
 -- Strong center magnet: the 0-st line now has an 8 px snap band.
 if abs(dy)<=A.CURVE_CENTER_SNAP_PX then norm=0 end
 return pct,norm
end

function A.commit_pitch_curve_points(pts)
 pts=pts or {};table.sort(pts,function(a,b)return (a.pct or 0)<(b.pct or 0) end)
 if #pts<2 then
  -- One remaining point cannot define a guide. Keep it as a temporary edit point,
  -- while the actual generator safely returns to full-range RND mode.
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
 -- Fixed pitch reference: top=positive limit, center=0 st, bottom=negative limit.
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
  label(string.format('GUIDE MODE · RANDOM  ·  %d LINE',max(1,#pts-1)),x+10,y+6,10.5,C.focus2,2,230,15,0,true)
 else
  local n=clamp(floor(tonumber(S.curve_points) or 5),2,24);local lx,ly=nil,nil
  for i=1,n do
   local u=(i-1)/max(1,n-1);local yy=cy+(math.sin(i*2.17)+math.sin(i*.83+.7))*.16*amp
   local xx=x+12+u*(w-24)
   if lx then line(lx,ly,xx,yy,C.lock,.34) end;lx,ly=xx,yy
  end
  label('RND MODE',x+8,y+6,21,C.lock2,2,w-16,28,0,true)
  label('ドラッグでDRAWモードへ',x+8,y+34,19.5,C.muted,1,w-16,26,0,true)
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
 local lastx,lasty=nil,nil
 for i=0,80 do
  local u=i/80;local xx=x+w*u;local yy=cy
  if u>=a and u<=b and b>a then
   local q=(u-a)/(b-a);local env=shape==2 and q or (shape==3 and (1-q) or 1)
   local cycles=clamp(rate,1,12)*.55;yy=cy-math.sin(q*math.pi*2*cycles)*h*.30*env
  end
  if lastx then line(lastx,lasty,xx,yy,C.focus2,.72) end;lastx,lasty=xx,yy
 end
 label(string.format('%d%% — %d%%',floor(a*100+.5),floor(b*100+.5)),x+7,y+5,8,C.muted,3,w-14,12,0,true)
end

function UI.toggle(key,text,x,y,w,enabled,size)
 enabled=enabled~=false and not A.job;local state=animate('toggle_'..key,S[key] and 1 or 0)
 line(x+3,y+12,x+23,y+12,C.edge2,.45);disc(x+7+12*state,y+12,4.2,C.faint,.8)
 if state>.001 then disc(x+7+12*state,y+12,7,C.accent,.06*state);disc(x+7+12*state,y+12,4.2,C.accent2,.94*state) end
 label(text,x+34,y,size or 13,enabled and C.text or C.muted,1,w-34,28,4,true)
 register('toggle_'..key,x,y,w,24,function() S[key]=not S[key];UI.changed(key) end,text,enabled)
end
function UI.segment(key,value,text,x,y,w,enabled)
 enabled=enabled~=false and not A.job;local active=S[key]==value;local a=animate(key..value,active and 1 or (inside(x,y,w,25) and .3 or 0))
 gradient(x,y,w,25,C.panel2,C.panel,.25+.3*a,.8);line(x,y+25,x+w,y+25,C.edge2,.2+.5*a);if active then rect(x,y,2,25,C.accent2,.7) end
 finish_corners(x,y,w,25,6,false,C.edge2,.25+.4*a);label(text,x,y+2,12,enabled and (active and C.text or C.muted) or C.faint,1,w,22,5,true)
 register(key..value,x,y,w,25,function() S[key]=value;UI.changed(key) end,text,enabled)
end
function A.curve_tab(key,value,text,x,y,w)
 local enabled=not A.job;local active=S[key]==value;local hot=inside(x,y,w,25) and enabled
 local a=animate('ctab_'..tostring(value),active and 1 or (hot and .20 or 0))
 local top=active and C.panel2 or C.field;local bottom=active and C.panel or C.bg
 gradient(x+5,y,w-10,25,top,bottom,active and .72 or (.34+.08*a),active and .90 or .72)
 rect(x+2,y+5,w-4,20,active and C.panel2 or C.field,active and .54 or .26)
 local edge=active and C.focus2 or C.edge
 line(x+6,y,x+w-6,y,edge,active and .78 or (.18+.10*a))
 line(x,y+6,x+6,y,edge,active and .56 or (.16+.08*a))
 line(x+w-6,y,x+w,y+6,edge,active and .56 or (.16+.08*a))
 line(x,y+6,x,y+25,active and C.accent2 or C.edge,active and .58 or .16)
 line(x+w,y+6,x+w,y+25,active and C.accent2 or C.edge,active and .58 or .16)
 if active then
  rect(x+2,y+22,w-4,4,C.panel2,.98);line(x+8,y+1,x+w-8,y+1,C.accent2,.72)
 else line(x+2,y+24,x+w-2,y+24,C.edge,.22+.08*a) end
 label(text,x,y+3,10.5,enabled and (active and C.text or (hot and C.muted or C.faint)) or C.faint,1,w,20,5,true)
 register('curve_tab_'..value,x,y,w,25,function() S[key]=value;UI.changed(key) end,text..' タブ',enabled)
end

function UI.panel(title,caption,x,y,w,h)
 gradient(x,y,w,h,C.panel2,C.panel,.22,.58);line(x,y,x+w,y,C.edge2,.25);finish_corners(x,y,w,h,8,false,C.edge2,.3)
 label(caption,x+13,y+6,9,C.muted,3,w-26,13,0,true);label(title,x+13,y+22,18,C.text,1,w-26,27,0,true)
end
function UI.checkbox(id,state,x,y,fn,hint,enabled,theme,mixed)
 enabled=enabled~=false and not A.job;local sz=16;local hovered=inside(x,y,sz,sz) and enabled
 local sync=theme=='sync';local base=sync and C.lock or C.accent2;local fill=sync and C.lock or C.accent
 local a=animate('check_'..id,state and 1 or (hovered and .22 or 0))
 gradient(x,y,sz,sz,C.field,C.panel2,.94,.72);line(x,y+sz,x+sz,y+sz,base,.28+.35*a);finish_corners(x,y,sz,sz,4,false,state and base or C.edge2,.30+.42*a)
 if sync then
  local c=state and C.lock2 or C.muted;local aa=state and .96 or .48
  line(x+3.4,y+5.0,x+6.8,y+5.0,c,aa);line(x+3.4,y+5.0,x+3.4,y+11.0,c,aa);line(x+3.4,y+11.0,x+6.8,y+11.0,c,aa)
  line(x+9.2,y+5.0,x+12.6,y+5.0,c,aa);line(x+12.6,y+5.0,x+12.6,y+11.0,c,aa);line(x+9.2,y+11.0,x+12.6,y+11.0,c,aa)
  if state then
   line(x+6.2,y+8.0,x+9.8,y+8.0,C.lock2,.98)
   line(x+7.1,y+6.6,x+8.9,y+9.4,C.lock,.72);line(x+7.1,y+9.4,x+8.9,y+6.6,C.lock,.72)
  elseif mixed then line(x+6.2,y+8.0,x+9.8,y+8.0,C.lock,.58) end
 else
  if state then
   rect(x+3,y+3,sz-6,sz-6,fill,.32);local cy=y+sz*.54
   line(x+sz*.25,cy,x+sz*.43,y+sz*.72,C.focus2,.98);line(x+sz*.43,y+sz*.72,x+sz*.76,y+sz*.28,C.focus2,.98)
  elseif mixed then line(x+4,y+sz*.5,x+sz-4,y+sz*.5,base,.90) end
 end
 register(id,x,y,sz,sz,fn,hint,enabled)
end
function UI.voice_control(v,x,y,w)
 local row=A.apply.items[v.guid] or {};local value=max(0,floor(tonumber(row.voice_limit) or 0))
 local h=22;local arrowW=18;local valueW=w-arrowW
 local active=edit and edit.kind=='voice' and edit.guid==v.guid
 local hovered=inside(x,y,valueW,h) and not A.job
 local a=animate('voice_'..v.guid,active and 1 or (hovered and .28 or 0))
 local flash=0;local ft=voice_flash[v.guid]
 if ft then
  local age=R.time_precise()-ft
  if age<1.35 then local q=clamp(age/1.35,0,1);flash=1-(q*q*(3-2*q)) else voice_flash[v.guid]=nil end
 end
 gradient(x,y,valueW,h,C.field,C.panel,.92,.70)
 if flash>0 then gradient(x,y,valueW,h,C.correct,C.field,.22*flash,.02*flash,true) end
 finish_corners(x,y,valueW,h,5,false,flash>0 and C.correct2 or (active and C.accent2 or C.edge2),.28+.34*a+.45*flash)
 local shown=active and edit.text or (value==0 and '∞' or tostring(value))
 local fsize=(not active and value==0) and 18 or 16
 label(shown,x,y-1,fsize,active and C.text or (value==0 and C.accent2 or C.text),value==0 and 1 or 3,valueW,h+1,5,true)
 register('voice_'..v.guid,x,y,valueW,h,function()
  edit={kind='voice',guid=v.guid,title='疑似発音数',text=value==0 and '∞' or tostring(value),selected=true}
 end,'疑似発音数：∞ = 制限なし / 1～'..VOICE_MAX..'。クリック入力 / 上下ドラッグ / ホイール変更',not A.job)
 local ax=x+valueW;local half=h/2
 gradient(ax,y,arrowW,h,C.panel2,C.field,.55,.88);line(ax,y,ax,y+h,C.edge2,.32);line(ax,y+half,ax+arrowW,y+half,C.edge,.36)
 local up_hover=inside(ax,y,arrowW,half) and not A.job;local dn_hover=inside(ax,y+half,arrowW,half) and not A.job
 if up_hover then rect(ax,y,arrowW,half,C.accent,.14) end;if dn_hover then rect(ax,y+half,arrowW,half,C.accent,.14) end
 local uc=up_hover and C.focus2 or C.muted;local dc=dn_hover and C.focus2 or C.muted
 color(uc,up_hover and .98 or .78);gfx.triangle(sx(ax+5),sy(y+7),sx(ax+arrowW-5),sy(y+7),sx(ax+arrowW/2),sy(y+3))
 color(dc,dn_hover and .98 or .78);gfx.triangle(sx(ax+5),sy(y+half+4),sx(ax+arrowW-5),sy(y+half+4),sx(ax+arrowW/2),sy(y+h-3))
 register('voiceup_'..v.guid,ax,y,arrowW,half,function() UI.set_voice_limit(v.guid,UI.voice_step_value(value,1)) end,'疑似発音数を1段階増やす（∞ → 1）',not A.job)
 register('voicedown_'..v.guid,ax,y+half,arrowW,half,function() UI.set_voice_limit(v.guid,UI.voice_step_value(value,-1)) end,'疑似発音数を1段階減らす（1 → ∞）',not A.job)
end
function UI.voice_global_control(x,y,w)
 local h=22;local arrowW=20;local valueW=w-arrowW
 gradient(x,y,valueW,h,C.field,C.panel,.88,.70);finish_corners(x,y,valueW,h,5,false,C.edge2,.36)
 label('ALL',x,y+1,11,C.accent2,3,valueW,h-2,5,true)
 local ax=x+valueW;local half=h/2
 gradient(ax,y,arrowW,h,C.panel2,C.field,.55,.88);line(ax,y,ax,y+h,C.edge2,.34);line(ax,y+half,ax+arrowW,y+half,C.edge,.38)
 local up_hover=inside(ax,y,arrowW,half) and not A.job;local dn_hover=inside(ax,y+half,arrowW,half) and not A.job
 if up_hover then rect(ax,y,arrowW,half,C.accent,.16) end;if dn_hover then rect(ax,y+half,arrowW,half,C.accent,.16) end
 color(up_hover and C.focus2 or C.muted,up_hover and .98 or .80);gfx.triangle(sx(ax+5),sy(y+7),sx(ax+arrowW-5),sy(y+7),sx(ax+arrowW/2),sy(y+3))
 color(dn_hover and C.focus2 or C.muted,dn_hover and .98 or .80);gfx.triangle(sx(ax+5),sy(y+half+4),sx(ax+arrowW-5),sy(y+half+4),sx(ax+arrowW/2),sy(y+h-3))
 register('vglobal_up',ax,y,arrowW,half,function() UI.adjust_all_voice_limits(1) end,'全アイテムの疑似発音数を相対的に1段階増やす',not A.job and #A.items>0)
 register('vglobal_down',ax,y+half,arrowW,half,function() UI.adjust_all_voice_limits(-1) end,'全アイテムの疑似発音数を相対的に1段階減らす',not A.job and #A.items>0)
end
function UI.source_requested(apply,v)
 return ((apply.items[v.guid] or {}).source==true)
end
function UI.restore_item_selection(project,items,do_refresh)
 if not project or not items or R.EnumProjects(-1,'')~=project then return end
 R.SelectAllMediaItems(project,false)
 for _,item in ipairs(items or {}) do if R.ValidatePtr2(project,item,'MediaItem*') then R.SetMediaItemSelected(item,true) end end
 R.UpdateArrange();if do_refresh then UI.refresh() end
end
function UI.begin_fresh_source_execute()
 local requested={};local count=0
 UI.stop_source_job()
 for _,v in ipairs(A.items or {}) do
  if UI.source_requested(A.apply,v) then
   UI.prepare_source_info(v)
   if v.source_key then A.source_cache[v.source_key]=nil end
   requested[v.guid]=true;count=count+1
  end
 end
 if count==0 then return false end
 A.source_execute_pending={project=A.project,selection_signature=A.selection_signature,requested=requested}
 UI.rebuild_source_queue();UI.source_queue_start_next()
 UI.notice('使用する素材を完全再解析しています。完了後に自動で生成します。')
 return true
end
function UI.frozen_apply() return tcopy(A.apply) end
function UI.cancel_job()
 local j=A.job;if not j then return end
 j.cancelled=true
 if j.thread and coroutine.status(j.thread)=='suspended' and j.started then UI.step_generation()
 else A.job=nil;A.progress=0;UI.restore_item_selection(j.snapshot.project,j.restore_selection,false);UI.notice('生成を中止しました。');UI.refresh() end
end
function UI.step_generation()
 local j=A.job;if not j then return end
 j.started=true;j.deadline=R.time_precise()+.008
 local ok,err=coroutine.resume(j.thread)
 if not ok then A.job=nil;A.progress=0;UI.notice(err,true);R.ShowConsoleMsg(BLT.publicError(err)..'\n') end
end

function UI.finish_generation(j)
 local groups,err=Core.plan(j.snapshot.items,j.settings,j.apply,Core.occupancy(j.snapshot.project,j.snapshot.items))
 if not groups then A.job=nil;A.progress=0;UI.refresh();UI.notice(err,true);return nil end
 local count,created_or_err,free_before,original_before,cleanup_failed,rollback_ok=Core.apply(j.snapshot,groups,j.settings,function(progress)
  A.progress=progress
  if j.cancelled then return false,'生成を中止しました。' end
  if progress==0 or progress==1 or R.time_precise()>=j.deadline then
   local revision=R.GetProjectStateChangeCount(j.snapshot.project)
   coroutine.yield()
   if j.cancelled then return false,'生成を中止しました。' end
   if R.EnumProjects(-1,'')~=j.snapshot.project or
    (R.GetProjectStateChangeCount(j.snapshot.project)~=revision and not Core.generation_targets_valid(j.snapshot)) then
    return false,'生成対象が変更されたため中止しました。'
   end
  end
  return true
 end)
 if not count then UI.queue_bake_deletes(cleanup_failed,j.snapshot.project);A.job=nil;A.progress=0;UI.refresh();UI.notice(j.cancelled and rollback_ok and '生成を中止し、今回のコピーを削除しました。' or created_or_err,not (j.cancelled and rollback_ok));return nil end
 A.job=nil;A.progress=0;local refs={};for _,v in ipairs(j.snapshot.items) do refs[#refs+1]=v.item end;A.last_created={project=j.snapshot.project,items=created_or_err or {},count=count,seed=j.settings.seed,source_refs=refs,free_before=free_before or {},original_before=original_before or {}}
 UI.refresh()
 local src_on=0;for _,v in ipairs(j.snapshot.items) do if UI.source_requested(j.apply,v) then src_on=src_on+1 end end
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
 if A.job then UI.cancel_job();return end;if not UI.commit_edit() then return end
 if A.source_execute_pending and not source_refresh_done then
  local restore=A.source_execute_pending.restore_selection
  UI.stop_source_job();A.source_execute_pending=nil;A.source_queue={};A.source_queue_i=1;A.source_queue_done=true
  if restore then UI.restore_item_selection(A.project,restore,true) end
  UI.notice('実行前の素材再解析を中止しました。');return
 end
 local ok,err=Core.validate(S);if not ok then UI.notice(err,true);return end
 UI.refresh();if #A.items==0 then UI.notice(A.selection_error,true);return end;if #A.items*S.count>2000 then UI.notice('合計2000アイテム以下にしてください。',true);return end
 if not source_refresh_done and UI.begin_fresh_source_execute() then return end
 local pending=UI.source_preflight_message();if pending then UI.notice(pending,true);return end
 if A.source_job then UI.notice('素材バリエーションの事前解析中です。',true);return end
 if not S.seed_lock then S.seed=Core.random_seed();UI.persist_later() end
 local worked,why=xpcall(function()
  local app=UI.frozen_apply();local tex_ok,tex_err=UI.prepare_texture_waves(A.items,app);if not tex_ok then error(tex_err,0) end
  local j={snapshot=Core.snapshot(A.project,A.items),settings=copy(S),apply=app}
  j.thread=coroutine.create(function() UI.finish_generation(j);UI.restore_item_selection(j.snapshot.project,j.restore_selection,true) end);A.job=j;A.progress=0
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
 UI.notice(string.format('TEXTURE FXを%dアイテムへ焼き込みました。生成取消は引き続き使用できます。',#targets))
end
function UI.remove_last_generation(silent)
 if A.job then return false end
 local rec=A.last_created;if not rec or rec.project~=R.EnumProjects(-1,'') then if not silent then UI.notice('このセッションで取り消せる生成結果がありません。',true) end;return false end
 local valid={};for _,v in ipairs(rec.items or {}) do if v.item and R.ValidatePtr2(rec.project,v.item,'MediaItem*') then valid[#valid+1]=v end end
 local project=rec.project;local cleanup_files={}
 for _,v in ipairs(rec.items or {}) do for _,fn in ipairs(v.bake_files or {}) do cleanup_files[#cleanup_files+1]=fn end end
 if #valid==0 then
  local failed_files,retained_files=Core.cleanup_bake_files(cleanup_files,project)
  UI.queue_bake_deletes(failed_files,project)
  A.last_created=nil
  if not silent then UI.notice(#retained_files>0 and '生成結果は削除済みです。ほかのテイクが使用中の焼き込みWAVは残しました。' or '直前の生成結果はすでに存在しません。',false) end
  return false
 end
 R.Undo_BeginBlock2(project);R.PreventUIRefresh(1);local ok=true
 for i=#valid,1,-1 do local v=valid[i];local track=R.GetMediaItemTrack(v.item) or v.track;local called,result=pcall(R.DeleteTrackMediaItem,track,v.item)
  if not called or not result then ok=false end
 end
 local original_conflicts=0;local conflict_tracks={}
 for i=#(rec.original_before or {}),1,-1 do
  local b=rec.original_before[i];local restored_item,conflict=Core.restore_original_item(project,b,true)
  if not restored_item then ok=false end;if conflict then original_conflicts=original_conflicts+1;local track=b.item and R.GetMediaItemTrack(b.item);if track then conflict_tracks[track]=true end end
 end
 for track,mode in pairs(rec.free_before or {}) do
  if not conflict_tracks[track] and R.ValidatePtr2(project,track,'MediaTrack*') and R.GetMediaTrackInfo_Value(track,'I_FREEMODE')==1 then
   local called,result=pcall(R.SetMediaTrackInfo_Value,track,'I_FREEMODE',mode);if not called or not result then ok=false end
  end
 end
 R.PreventUIRefresh(-1);if next(rec.free_before or {}) then R.UpdateTimeline() end;R.UpdateArrange();R.Undo_EndBlock2(project,'BLT Variant Forge: remove last generation',4)
 local failed_files,retained_files=Core.cleanup_bake_files(cleanup_files,project)
 UI.queue_bake_deletes(failed_files,project)
 if not ok then if not silent then UI.notice('一部の生成アイテムを削除できませんでした。Undoで確認してください。',true) end;return false end
 local removed=#valid;A.last_created=nil;UI.refresh();if not silent then
  local extra=''
  if original_conflicts>0 then extra=extra..string.format(' 生成後に編集された元アイテム%d件は、その編集を保持しました。',original_conflicts) end
  if #retained_files>0 then extra=extra..string.format(' 使用中の焼き込みWAVは%d件残しました。',#retained_files) end
  UI.notice(string.format('直前に生成した%dアイテムを取り消しました。%s',removed,extra))
 end;return true
end
function UI.regenerate()
 if A.job or A.source_job then return end
 if UI.last_created_count()<=0 then UI.notice('再生成できる直前の生成結果がありません。',true);return end
 local rec=A.last_created;local refs=rec and rec.source_refs or nil
 if not refs or #refs==0 then UI.notice('再生成元のアイテム情報がありません。生成し直してください。',true);return end
 for _,it in ipairs(refs) do if not R.ValidatePtr2(rec.project,it,'MediaItem*') then UI.notice('元アイテムが削除されているため再生成できません。現在の生成結果は残しました。',true);return end end
 local user_selection={};for i=0,R.CountSelectedMediaItems(rec.project)-1 do user_selection[#user_selection+1]=R.GetSelectedMediaItem(rec.project,i) end
 local function restore_user_selection(do_refresh)
  R.SelectAllMediaItems(rec.project,false)
  for _,it in ipairs(user_selection) do if R.ValidatePtr2(rec.project,it,'MediaItem*') then R.SetMediaItemSelected(it,true) end end
  R.UpdateArrange();if do_refresh then UI.refresh() end
 end
 -- Re-select the original source items internally before deleting the generated
 -- batch. The user's visible selection is restored afterwards, so Regenerate is
 -- independent of selection without unexpectedly changing the edit context.
 R.SelectAllMediaItems(rec.project,false);for _,it in ipairs(refs) do R.SetMediaItemSelected(it,true) end;R.UpdateArrange();UI.refresh()
 if A.source_job then UI.stop_source_job();restore_user_selection(true);UI.notice('再生成元の素材情報を準備できませんでした。SOURCEを確認してから再実行してください。',true);return end
 local pending=UI.source_preflight_message();if pending then restore_user_selection(true);UI.notice(pending,true);return end
 if UI.remove_last_generation(true) then UI.execute() end
 if A.job then A.job.restore_selection=user_selection elseif A.source_execute_pending then A.source_execute_pending.restore_selection=user_selection else restore_user_selection(true) end
end
function UI.work_step()
 if A.job then UI.step_generation();return end
 Core.touch_temp_heartbeat(false)
 UI.retry_stale_temp_items(false)
 UI.retry_pending_bake_deletes(false)
 if not A.source_job then
  if not A.source_queue_done then UI.source_queue_start_next() end
  if A.source_queue_done and A.source_execute_pending then
   local pending=A.source_execute_pending;A.source_execute_pending=nil
   if R.EnumProjects(-1,'')~=pending.project or Core.selection_signature(pending.project)~=pending.selection_signature then
    UI.restore_item_selection(pending.project,pending.restore_selection,true);UI.refresh();UI.notice('素材の再解析中に選択またはプロジェクトが変わったため、実行を中止しました。',true);return
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
   for _,v in ipairs(A.items or {}) do UI.source_status_from_cache(v) end
   UI.source_queue_start_next();return
  end
 until R.time_precise()>=deadline
end

UI.ICON_BARS={3,7,11,6,4,9,5,8,3}
function UI.variation_icon(x,y)
 local cy=y+31
 local breathe=.5+.5*math.sin(ui_anim_time*.55)
 for i=1,8 do
  local phase=ui_anim_time*(.10+(i%3)*.018)+i*1.47
  local px=x+49+math.sin(phase*1.09)*(20+(i%2)*6)
  local py=y+31+math.cos(phase*.79)*(9+(i%3)*2)
  local rr=10+(i%4)*3+breathe*1.6
  disc(px,py,rr+10,C.accent,.004+.003*breathe)
  disc(px,py,rr+3,C.accent3,.008+.004*breathe)
  disc(px+1.5,py-1,rr*.48,C.accent2,.005)
 end
 if effects_active then
  icon_clock=icon_clock+particle_dt
  while icon_clock>=.22 and #icon_particles<24 do
   icon_clock=icon_clock-.22;icon_serial=icon_serial+1
   local n=icon_serial
   local a,b,c,d,e=particle_hash(n,21),particle_hash(n,22),particle_hash(n,23),particle_hash(n,24),particle_hash(n,25)
   icon_particles[#icon_particles+1]={
    lane=(n-1)%3,age=0,life=2.8+b*1.55,r=.85+a*.95,phase=c*math.pi*2,
    sway=4.0+d*6.5,start_y=cy+(a-.5)*11,arch=(e-.5)*15,glint=(n%5==0)
   }
  end
 else icon_clock=min(icon_clock,.10) end
 for i=#icon_particles,1,-1 do
  local p=icon_particles[i];p.age=p.age+particle_dt
  if p.age>=p.life then table.remove(icon_particles,i) else
   local t=clamp(p.age/p.life,0,1)
   local u=t*t*(3-2*t)
   local env=math.sin(math.pi*t)^1.85
   local target_y=y+12+p.lane*24
   local px=x+18+64*u+math.sin(p.age*.63+p.phase)*p.sway*(1-.45*u)
   local py=p.start_y+(target_y-p.start_y)*u+math.sin(math.pi*u)*p.arch+
    math.cos(p.age*.51+p.phase*.73)*p.sway*.65
   disc(px,py,p.r+8.0,C.accent,.008*env)
   disc(px,py,p.r+4.0,C.accent3,.016*env)
   disc(px,py,p.r+1.8,C.accent2,.060*env)
   disc(px,py,p.r,C.focus2,.46*env)
   if p.glint then
    disc(px,py,max(.35,p.r*.42),C.text,.46*env)
    line(px-2.8,py,px+2.8,py,C.focus2,.12*env)
    line(px,py-2.8,px,py+2.8,C.focus2,.10*env)
   end
  end
 end
 disc(x+55,cy,36,C.accent,.009)
 cut_panel(x+1,cy-10,22,20,4,C.panel2,.76,C.edge2,.62,true)
 line(x+23,cy,x+45,cy,C.edge2,.24)
 for lane=0,2 do
  local yy=y+5+lane*24
  line(x+45,cy,x+52,yy+7,C.edge2,.19)
  cut_panel(x+53,yy,40,15,4,C.field,.90,C.edge2,.52,false)
  for i=1,#UI.ICON_BARS do local hh=UI.ICON_BARS[((i+lane*3-1)%#UI.ICON_BARS)+1]*.34;line(x+58+(i-1)*3.2,yy+7-hh,x+58+(i-1)*3.2,yy+7+hh,C.accent2,.58) end
 end
 line(x+8,cy,x+17,cy,C.focus2,.55);line(x+12,cy-4,x+12,cy+4,C.focus2,.55)
end
function UI.draw_scroll_hint(cx,y,dir)
 -- Phase is advanced by the main loop.  Once visual activity ends the speed is
 -- eased down to zero, leaving this as a static 'scrollable' cue while idle.
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
 if A.job then return end
 local project=R.EnumProjects(-1,'');local count=R.CountSelectedMediaItems(project)
 if count<1 then A.texture_popup('TEXTURE EQの参照にする音声アイテムを1～10個選択してください。');return end
 if count>Core.TEXTURE_MAX_REFERENCES then A.texture_popup(string.format('TEXTURE EQの参照素材は最大%d個です。\n現在 %d個 選択されています。',Core.TEXTURE_MAX_REFERENCES,count));return end
 local infos={}
 for i=0,count-1 do
  local item=R.GetSelectedMediaItem(project,i);local info,why=Core.item_info(project,item)
  if not info then A.texture_popup(string.format('%d番目の選択アイテムを解析できません。\n%s',i+1,tostring(why or '音声アイテムを選択してください。')));return end
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
 -- Atomic replacement: validation/capture must finish for every selected item before
 -- the active texture library is replaced.
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
function UI.draw_source_waveform()
 local x,y,w,h=WAVE_X,WAVE_Y,WAVE_W,WAVE_H
 gradient(x,y,w,h,C.panel2,C.panel,.22,.60);line(x,y,x+w,y,C.edge2,.25);finish_corners(x,y,w,h,8,false,C.edge2,.32)
 label('SOURCE ANALYSIS',x+13,y+7,9,C.muted,3,150,13,0,true)
 local v=UI.waveform_item()
 if not v then return end
 label(v.name,x+145,y+4,12,C.text,1,w-470,20,0,true,true)
 local data,partial=UI.source_wave_data(v)
 local count=v.source_candidate_count or 0
 right_label(partial and string.format('ANALYZING %d%%',floor((A.source_progress or 0)*100+.5)) or string.format('VARIANTS %d',count),x+w-14,y+7,8,partial and C.accent2 or C.muted,3,true)
 local px,py,pw,ph=x+15,y+31,w-30,104;local cy=py+ph*.52
 gradient(px,py,pw,ph,C.field,C.panel,.96,.72);finish_corners(px,py,pw,ph,5,false,C.edge,.34)
 line(px,cy,px+pw,cy,C.edge,.34)
 local source_len=max(1e-9,v.source_len or (data and data.source_len) or 0)
 local function tx(t) return px+clamp(t/source_len,0,1)*pw end
 local regions=data and data.regions or {}
 local ctx=not partial and v.source_context or nil
 if partial and data and #regions>0 then local ok,res=pcall(Core.source_context,v,data);if ok and type(res)=='table' then ctx=res end end
 for i,r in ipairs(regions) do
  local a,b=tx(r.start or 0),tx(r.finish or 0)
  if b>a then
   rect(a,py,b-a,ph,C.accent,(ctx and i==ctx.index) and .17 or .085)
   line(a,py,a,py+ph,C.edge2,(ctx and i==ctx.index) and .70 or .30)
   line(b,py,b,py+ph,C.edge2,(ctx and i==ctx.index) and .70 or .30)
  end
 end
 local preview=data and data.preview or nil;local norm=max((data and data.preview_max) or 0,1e-12)
 if preview then
  local n=Core.SOURCE_PREVIEW_BINS;local columns=min(420,max(1,floor(pw/2.5)));local step=max(1,ceil(n/columns))
  local peaks=nil
  if not partial and data then
   local cache=data._blt_wave_draw_cache
   local key=tostring(preview)..'|'..tostring(step)..'|'..tostring(norm)
   if cache and cache.key==key then
    peaks=cache.peaks
   else
    peaks={}
    for i=1,n,step do
     local pk=0
     for k=i,min(n,i+step-1) do pk=max(pk,preview[k] or 0) end
     peaks[#peaks+1]={i=i,pk=pk}
    end
    data._blt_wave_draw_cache={key=key,peaks=peaks}
   end
  end
  if peaks then
   for _,p in ipairs(peaks) do
    if p.pk>0 then local amp=clamp(math.sqrt(p.pk/norm),0,1)*ph*.44;local xx=px+(p.i-.5)/n*pw;line(xx,cy-amp,xx,cy+amp,C.accent2,.64) end
   end
  else
   for i=1,n,step do
    local pk=0
    for k=i,min(n,i+step-1) do pk=max(pk,preview[k] or 0) end
    if pk>0 then local amp=clamp(math.sqrt(pk/norm),0,1)*ph*.44;local xx=px+(i-.5)/n*pw;line(xx,cy-amp,xx,cy+amp,C.accent2,.64) end
   end
  end
 end
 for i,r in ipairs(regions) do
  if finite(r.anchor) then
   local ax=tx(r.anchor);line(ax,py+2,ax,py+ph-2,C.lock,(ctx and i==ctx.index) and .92 or .67)
   disc(ax,cy,2.1,(ctx and i==ctx.index) and C.lock2 or C.lock,.92)
  end
 end
 local ua,ub=tx(v.offset or 0),tx((v.offset or 0)+(v.len or 0)*(v.rate or 1))
 if ub>ua then
  rect(ua,py,ub-ua,ph,C.focus2,.035);line(ua,py,ub,py,C.focus2,.92);line(ua,py+ph,ub,py+ph,C.focus2,.92)
  line(ua,py,ua,py+ph,C.focus2,.82);line(ub,py,ub,py+ph,C.focus2,.82)
 end
 if partial then
  local pr=clamp(A.source_progress or 0,0,1);rect(px,py+ph-3,pw,3,C.ink,.75);if pr>0 then gradient(px,py+ph-3,pw*pr,3,C.accent,C.accent2,.80,.98) end
 elseif not data then
  label(v.source_reason or '解析待ち',px,py+37,12,C.muted,1,pw,28,5,false)
 end
 label(string.format('青: 検出区間   黄: 基準点   明枠: 使用中    %.2f s',v.source_len or 0),x+15,y+142,9,C.muted,1,510,15)
 if ctx and ctx.region then label(string.format('区間 %d/%d',ctx.index,#regions),x+535,y+142,8.5,C.muted,3,86,15,5,true) end
 register('source_wave',px,py,pw,ph,function()end,'リストで最後にクリックしたアイテムの素材全体。青=検出区間 / 黄=基準点 / 明枠=現在の使用範囲',false)
end

function UI.draw_assignment_matrix()
 local x,y,w,h=MATRIX_X,MATRIX_Y,MATRIX_W,MATRIX_H;gradient(x,y,w,h,C.panel2,C.panel,.24,.62);finish_corners(x,y,w,h,8,false,C.edge2,.32)
 local contentRight=x+w-MATRIX_SCROLL_W-8;local colsX=x+MATRIX_NAME_W
 local voiceW=66;local featureX=colsX+voiceW;local cw=(contentRight-featureX)/#FEATURE_COLUMNS
 for ci,c in ipairs(FEATURE_COLUMNS) do
  if c.lockable and A.apply.lock[c.key] then local cx=featureX+(ci-1)*cw;rect(cx,y+1,cw,h-2,C.lock,.045);line(cx,y+1,cx+cw,y+1,C.lock,.42) end
 end
 label('TRACK / FILE',x+13,y+4,9,C.accent2,3,MATRIX_NAME_W-24,13,0,true);label('トラック / ファイル名',x+13,y+16,9,C.muted,1,MATRIX_NAME_W-24,13,0,true)
 label('VOICE',colsX,y+4,9,C.accent2,3,voiceW,13,5,true);label('疑似発音数',colsX,y+16,9,C.muted,1,voiceW,13,5,true)
 for ci,c in ipairs(FEATURE_COLUMNS) do
  local cx=featureX+(ci-1)*cw;local locked=c.lockable and A.apply.lock[c.key]
  label(c.label,cx,y+4,9,locked and C.lock2 or C.accent2,3,cw,13,5,true);label(c.sub,cx,y+16,10,locked and C.lock or C.muted,1,cw,13,5,true)
 end
 local ay=y+MATRIX_HEADER_H
 gradient(x+8,ay,contentRight-x-8,MATRIX_ALL_H,C.accent3,C.panel2,.46,.84)
 rect(x+8,ay,4,MATRIX_ALL_H,C.accent2,.48);line(x+8,ay,contentRight,ay,C.accent2,.34);line(x+8,ay+MATRIX_ALL_H,contentRight,ay+MATRIX_ALL_H,C.edge2,.38)
 local column_state={};local global_all=true;local state_count=0
 for _,c in ipairs(FEATURE_COLUMNS) do local all,any,available=UI.all_feature_state(c.key);column_state[c.key]={all,any,available};if available>0 then state_count=state_count+available;global_all=global_all and all end end
 global_all=state_count>0 and global_all
 label('GLOBAL APPLY   /   一括 ON / OFF',x+50,ay+5,11,C.text,1,MATRIX_NAME_W-62,21,0,true)
 register('global_apply_all',x+8,ay,MATRIX_NAME_W-8,MATRIX_ALL_H,function() UI.set_all_features(not global_all) end,'全項目をまとめてON/OFF',#A.items>0)
 UI.voice_global_control(colsX+2,ay+6,voiceW-4)
 for ci,c in ipairs(FEATURE_COLUMNS) do
  local cx=featureX+(ci-1)*cw+(cw-16)/2;local st=column_state[c.key];local all,any,available=st[1],st[2],st[3]
  local hint=c.key=='source' and '使用可能な素材バリエーションがあるアイテムだけを一括ON/OFF' or '全選択アイテムのこの機能を一括ON/OFF'
  UI.checkbox('all_'..c.key,all,cx,ay+8,function() UI.set_feature_all(c.key,not all) end,hint,available>0,nil,any and not all)
 end
 local listY=ay+MATRIX_ALL_H;local listH=MATRIX_VISIBLE*MATRIX_ROW_H;local maxscroll=max(0,#A.items-MATRIX_VISIBLE);A.item_scroll=clamp(A.item_scroll or 0,0,maxscroll)
 register('matrix_list',x,listY,contentRight-x,listH,function()end,'ファイル名：Ctrl/Shiftで複数選択 / ホイールでスクロール',true)
 for r=1,MATRIX_VISIBLE do
  local idx=A.item_scroll+r;local v=A.items[idx];local ry=listY+(r-1)*MATRIX_ROW_H
  if r%2==0 then rect(x+8,ry,contentRight-x-8,MATRIX_ROW_H,C.field,.20) end
  if v then
   local selected=A.matrix_selected[v.guid]==true
   if selected then rect(x+8,ry,contentRight-x-8,MATRIX_ROW_H,C.accent,.105);rect(x+8,ry,3,MATRIX_ROW_H,C.focus2,.72) end
   label(string.format('T%02d',floor((tonumber(v.tracknum) or 0)+.5)),x+15,ry+7,10,selected and C.focus2 or C.faint,3,36,18,0,true)
   if v._display_name_source~=v.name or v._display_name==nil then
    v._display_name_source=v.name;v._display_name=A.matrix_display_name(v.name)
   end
   label(v._display_name,x+56,ry+5,12,selected and C.text or C.muted,1,MATRIX_NAME_W-68,MATRIX_ROW_H-8,0,selected,true)
   register('rowname_'..v.guid,x+8,ry,MATRIX_NAME_W-12,MATRIX_ROW_H,function() UI.select_matrix_item(idx,v.guid) end,'クリック選択 / Ctrl(Cmd)で追加・解除 / Shiftで範囲選択',not A.job)
   UI.voice_control(v,colsX+2,ry+6,voiceW-4)
   local row=A.apply.items[v.guid]
   for ci,c in ipairs(FEATURE_COLUMNS) do
    local cx=featureX+(ci-1)*cw+(cw-16)/2;local available=UI.feature_available(v,c.key)
    local hint
    if c.key=='source' then hint=v.source_ready and tostring(v.source_reason or '素材バリエーション') or '素材全体をラウドネス解析中…'
    else hint=selected and '選択中の全アイテムへ同じON/OFFを適用' or 'このアイテムへ適用' end
    UI.checkbox('item_'..v.guid..'_'..c.key,row[c.key],cx,ry+9,function() UI.toggle_item_feature(v.guid,c.key) end,hint,available)
    if c.key=='source' then
     local tag=not v.source_ready and '…' or tostring(v.source_display_count or v.source_candidate_count or v.source_detected or '—')
     local bx,by,bw,bh=cx+19,ry+7,32,20;local from_track=v.source_origin=='track';local badge_on=available and row.source==true
     if from_track then
      gradient(bx,by,bw,bh,C.field,C.panel,.82,.94)
      local c1=badge_on and C.source_alt or C.faint;local c2=badge_on and C.source_alt2 or C.muted
      line(bx,by+3,bx,by+bh-3,c1,badge_on and .82 or .34);line(bx+bw,by+3,bx+bw,by+bh-3,c1,badge_on and .82 or .34)
      line(bx+4,by+bh-2,bx+bw-4,by+bh-2,c1,badge_on and .72 or .28);line(bx+8,by+bh-5,bx+bw-8,by+bh-5,c2,badge_on and .34 or .16)
      label(tag,bx,by+1,11,badge_on and C.source_alt2 or C.faint,3,bw,bh-2,5,true)
     else
      gradient(bx,by,bw,bh,badge_on and C.accent3 or C.field,C.panel,badge_on and .72 or .84,.90)
      finish_corners(bx,by,bw,bh,5,false,badge_on and C.accent2 or C.edge,badge_on and .58 or .26)
      if badge_on then line(bx+5,by+1,bx+bw-7,by+1,C.focus2,.72) end
      label(tag,bx,by+1,11,badge_on and C.focus2 or C.faint,3,bw,bh-2,5,true)
     end
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
   if not suppress_scroll_hints then UI.draw_scroll_hint(hc,listY+8,-1) end
  end
  if A.item_scroll<maxscroll then
   A.scroll_hint_bottom={cx=hc,y=listY+listH-8,dir=1}
   if not suppress_scroll_hints then UI.draw_scroll_hint(hc,listY+listH-8,1) end
  end
 else A.scroll_geom=nil end
 local ly=listY+listH
 gradient(x+8,ly,contentRight-x-8,MATRIX_LOCK_H,C.lock,C.field,.085,.88)
 rect(x+8,ly,4,MATRIX_LOCK_H,C.lock,.50);line(x+8,ly,contentRight,ly,C.lock,.52);line(x+8,ly+MATRIX_LOCK_H,contentRight,ly+MATRIX_LOCK_H,C.lock,.24)
 label('RANDOM SYNC   /   Variation内のランダム値を共通化',x+50,ly+5,11,C.text,1,MATRIX_NAME_W-62,22,0,true)
 label('—',colsX,ly+5,13,C.faint,3,voiceW,22,5,true)
 for ci,c in ipairs(FEATURE_COLUMNS) do
  local cx=featureX+(ci-1)*cw+(cw-16)/2
  if c.lockable then
   UI.checkbox('lock_'..c.key,A.apply.lock[c.key],cx,ly+9,function() A.apply.lock[c.key]=not A.apply.lock[c.key];UI.assignment_changed() end,'ON：この列のランダム値をVariation内で共通化',true,'sync')
  else
   label('—',cx-2,ly+5,13,C.faint,3,20,22,5,true)
  end
 end
end
function UI.draw_modulation_controls(kind,depth_unit)
 A.draw_mod_preview(kind,34,376,310,100)
 UI.segment(kind..'_shape',1,'一定',34,486,94);UI.segment(kind..'_shape',2,'強く',138,486,94);UI.segment(kind..'_shape',3,'弱く',242,486,102)
 A.compact_field(kind..'_depth_lo','深さL',358,376,96,depth_unit);A.compact_field(kind..'_depth_hi','深さH',464,376,96,depth_unit)
 A.compact_field(kind..'_rate_lo','速度L',358,414,96,'Hz');A.compact_field(kind..'_rate_hi','速度H',464,414,96,'Hz')
 A.compact_field(kind..'_start_pct','START',358,452,96,'%');A.compact_field(kind..'_end_pct','END',464,452,96,'%')
end
function UI.draw()
 UI.update_pointer_geometry()
 reset_text_queue()
 widget_count=0;hover_hint='';gfx.clear=-1;gfx.set(C.bg[1],C.bg[2],C.bg[3],1);gfx.rect(0,0,gfx.w,gfx.h,1);local now=R.time_precise();particle_dt=max(0,min(.1,now-frame_clock));frame_clock=now;frame_dt=visual_tail_active and particle_dt or 0;ui_anim_time=ui_anim_time+frame_dt;ambient_anim_time=ambient_anim_time+(effects_active and particle_dt or 0)
 rect(0,0,W,H+22,C.bg);gradient(0,0,W,78,C.bg2,C.bg,.22,0,true);disc(W-38,42,150,C.accent,.016);
 BLT.title('VARIANT FORGE','SOURCE VARIATIONS  素材から様々なバリエーションを生成',W);BLT.drawIcon()
 gradient(20,86,1140,68,C.panel2,C.panel,.3,.60);finish_corners(20,86,1140,68,8,false,C.edge2,.3)
 label('選択',32,92,11,C.muted,1,60,15);label(tostring(#A.items),32,111,24,#A.items>0 and C.text or C.warn,3,62,30,0,true)
 UI.field('count','生成数',110,111,88,'組');UI.field('interval','間隔',216,111,95,'sec');UI.segment('interval_mode',1,'末尾→先頭',323,114,104);UI.segment('interval_mode',2,'先頭→先頭',436,114,104)
 UI.field('voice_fade_ms','発音フェード',560,111,105,'ms');UI.field('seed','乱数シード',680,111,130,'');UI.toggle('seed_lock','シード固定',825,114,150,true,12)
 UI.panel('全体ピッチ','01 / GLOBAL PITCH',20,166,220,150);UI.field('pitch_lo','下限',34,239,91,'st');UI.field('pitch_hi','上限',135,239,91,'st');UI.segment('pitch_length_mode',1,'尺固定',34,283,88);UI.segment('pitch_length_mode',2,'尺連動',132,283,94)
 UI.panel('音量','02 / VOLUME',250,166,220,150);UI.field('volume_lo','下限',264,239,91,'dB');UI.field('volume_hi','上限',365,239,91,'dB')
 UI.panel('タイミング','03 / TIMING',480,166,220,150);UI.field('timing_lo','下限',494,239,91,'ms');UI.field('timing_hi','上限',595,239,91,'ms')
 UI.panel('PAN','04 / PAN',710,166,220,150);UI.field('pan_lo','L',724,239,91,'%');UI.field('pan_hi','R',825,239,91,'%')
 UI.panel('素材バリエーション','05 / SOURCE VARIANTS',940,166,220,150)
 label('選出',954,226,8.5,C.muted,1,60,12,0,true);UI.segment('source_order',1,'シャッフル',954,240,90);UI.segment('source_order',2,'順番',1054,240,92)
 label('位置',954,276,8.5,C.muted,1,60,12,0,true);UI.segment('source_timing_mode',2,'区間相対',954,290,90);UI.segment('source_timing_mode',1,'絶対',1054,290,92)

 UI.panel('変調コントロール','06 / MODULATION',20,326,560,200)
 A.curve_tab('curve_tab',1,'PITCH CURVE',205,344,114);A.curve_tab('curve_tab',2,'VIBRATO',323,344,108);A.curve_tab('curve_tab',3,'TREMOLO',435,344,125)
 if S.curve_tab==1 then
  A.draw_pitch_curve_editor(34,376,310,136)
  if S.curve_guide_enabled then UI.small_button('curve_guide_clear','クリア',276,380,58,20,A.clear_pitch_curve_guide,'描いたガイドを消してRNDモードへ戻す',not A.job,false,false) end
  A.compact_field('curve_lo','−側下限',358,376,96,'st');A.compact_field('curve_hi','＋側上限',464,376,96,'st')
  A.compact_field('curve_points','カーブポイント数（ランダム時）',358,416,202,'',not S.curve_guide_enabled)
  UI.segment('curve_length_mode',1,'尺固定',358,460,96);UI.segment('curve_length_mode',2,'尺連動',464,460,96)
 elseif S.curve_tab==2 then
  UI.draw_modulation_controls('vibrato','st')
 elseif S.curve_tab==3 then
  UI.draw_modulation_controls('tremolo','dB')
 end

 UI.panel('テクスチャEQ','07 / EQ · TEXTURE',590,326,275,200)
 label('REFERENCE LIBRARY',604,373,8,C.muted,3,245,12,0,true)
 UI.small_button('texture_bank_capture','選択素材を解析・設定',604,392,166,27,A.capture_texture_bank_from_selection,'REAPERで現在選択中の音声素材の周波数特性を解析・登録。最大10素材 / 各60秒',not A.job,true)
 UI.small_button('texture_bank_clear','クリア',778,392,71,27,A.clear_texture_bank,'登録済みTEXTURE参照素材をすべてクリア',not A.job and #(A.texture_bank or {})>0,true)
 local texture_n=#(A.texture_bank or {});local _,texture_i=A.texture_preview_current();local texture_label_w=texture_n>1 and 164 or 245
 label(A.texture_bank_label(),604,426,10,texture_n>0 and C.focus2 or C.muted,1,texture_label_w,18,0,true)
 register('texture_bank_info',604,424,texture_label_w,20,function()end,A.texture_bank_hint(),false)
 if texture_n>1 then
  UI.small_button('texture_prev','‹',772,424,20,21,function() A.texture_preview_step(-1) end,'前のTEXTURE参照素材',not A.job,false,false)
  label(string.format('%d/%d',texture_i,texture_n),794,428,9,C.muted,2,31,14,0,true)
  UI.small_button('texture_next','›',828,424,20,21,function() A.texture_preview_step(1) end,'次のTEXTURE参照素材',not A.job,false,false)
 end
 A.draw_texture_eq_preview(604,451,164,43)
 UI.field('texture_strength','強度',778,470,71,'%')
 label(texture_n>0 and 'PERSISTENCE FFT' or 'AUTO TEXTURE',604,503,8.2,C.muted,1,164,14)
 UI.panel('トーン補正','08 / EQ · TONE',875,326,285,200);UI.field('tone_lo','強さ 下限',889,399,118,'dB');UI.field('tone_hi','上限',1020,399,126,'dB');UI.toggle('tone_bright','BRIGHT',889,449,124,true,10.5);UI.toggle('tone_dark','DARK',1022,449,124,true,10.5);UI.toggle('tone_forward','FORWARD',889,486,124,true,9.5);UI.toggle('tone_recessed','RECESSED',1022,486,124,true,9.5)
 UI.draw_feature_flashes()
 UI.draw_source_waveform()
 A.scroll_hint_top=nil;A.scroll_hint_bottom=nil
 UI.draw_assignment_matrix()
 local valid,err=Core.validate(S);local auto_status=A.source_job and string.format('素材全体をラウドネス解析中… %d%%',floor((A.source_progress or 0)*100+.5)) or nil
 local status=A.status~='' and A.status or (not valid and err or A.selection_error or auto_status or (#A.items==0 and '音声アイテムを選択してください。' or ''))
 local enabled=A.job~=nil or A.source_execute_pending~=nil or (not A.source_job and #A.items>0 and valid~=nil and #A.items*S.count<=2000);local can_last=UI.last_created_count()>0 and not A.job and not A.source_job
 local pending_texture=A.pending_texture_count();local can_bake=pending_texture>0 and not A.job and not A.source_job
 UI.small_button('undo_gen','生成取消',100,1050,132,31,function() UI.remove_last_generation(false) end,'このセッションで直前に生成したアイテムを削除',can_last,true)
 UI.small_button('regen','再生成',250,1050,132,31,UI.regenerate,'直前の生成結果を削除して現在の設定で生成し直す',can_last,true)
 UI.draw_primary_button('execute',A.job and '処理を中止' or string.format('%d バリエーションを生成',S.count),400,1042,380,46,UI.execute,'Enter：生成。SOURCEの事前解析中は完了後に実行できます。',enabled)
 UI.small_button('bake_fx','FX FIX',798,1050,92,31,A.bake_last_texture_fx,'直前生成のTEXTURE EQだけを音声へ焼き込み、FX負荷を軽減',can_bake,false,can_bake)
 BLT.footer(status,A.warning or not valid,W,H+22,'0.5.0');flush_text_queue();UI.custom_titlebar()
end

local function ensure_frame_cache()
 local w,h=max(1,floor(gfx.w+.5)),max(1,floor(gfx.h+.5))
 if w~=frame_cache_w or h~=frame_cache_h then
  gfx.setimgdim(FRAME_CACHE,-1,-1)
  gfx.setimgdim(FRAME_CACHE,w,h)
  frame_cache_w,frame_cache_h=w,h;frame_cache_valid=false
 end
 return w,h
end

function UI.draw_scroll_hints_only()
 if not frame_cache_valid then return false end
 local top,bottom=A.scroll_hint_top,A.scroll_hint_bottom
 if not top and not bottom then return false end
 -- gfx.update() presents a new framebuffer. Repaint the whole *cached* static
 -- frame first, otherwise every untouched pixel can be cleared/invalidated and
 -- the window appears black except for the animated hint rectangle.
 gfx.dest=-1;gfx.mode=0;gfx.a=1
 gfx.blit(FRAME_CACHE,1,0,0,0,frame_cache_w,frame_cache_h,0,0,frame_cache_w,frame_cache_h)
 if top then UI.draw_scroll_hint(top.cx,top.y,top.dir) end
 if bottom then UI.draw_scroll_hint(bottom.cx,bottom.y,bottom.dir) end
 gfx.update()
 return true
end

function UI.render_full_frame()
 local w,h=ensure_frame_cache()
 local ok,err
 gfx.dest=FRAME_CACHE
 -- Fill the complete pixel buffer as well as the scaled logical UI so resized
 -- letterbox margins never retain stale pixels.
 gfx.set(C.bg[1],C.bg[2],C.bg[3],1);gfx.rect(0,0,w,h,1)
 suppress_scroll_hints=true
 ok,err=xpcall(UI.draw,debug.traceback)
 suppress_scroll_hints=false
 gfx.dest=-1
 if not ok then error(err,0) end
 -- UI.draw() intentionally leaves gfx.a at whatever alpha the final primitive
 -- used. gfx.blit() inherits that alpha, which made the entire cached interface
 -- permanently dim. Always present the cache fully opaque with normal blending.
 gfx.mode=0;gfx.a=1
 gfx.blit(FRAME_CACHE,1,0,0,0,w,h,0,0,w,h)
 frame_cache_valid=true
 if A.scroll_hint_top then UI.draw_scroll_hint(A.scroll_hint_top.cx,A.scroll_hint_top.y,A.scroll_hint_top.dir) end
 if A.scroll_hint_bottom then UI.draw_scroll_hint(A.scroll_hint_bottom.cx,A.scroll_hint_bottom.y,A.scroll_hint_bottom.dir) end
 gfx.update()
end

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
function UI.apply_wheel(wheel,px,py,shift,hit)
 if wheel==0 then return end
 local listY=MATRIX_Y+MATRIX_HEADER_H+MATRIX_ALL_H;local listH=MATRIX_VISIBLE*MATRIX_ROW_H
 if not A.job and UI.point_inside(px,py,MATRIX_X,listY,MATRIX_W,listH) then
  A.item_scroll=clamp((A.item_scroll or 0)+(wheel>0 and -1 or 1),0,max(0,#A.items-MATRIX_VISIBLE));return
 end
 if hit and hit.enabled and hit.id:match('^voice_') and UI.commit_edit() then
  local guid=hit.id:sub(7);local row=A.apply.items[guid]
  if row then
   local cur=max(0,floor(tonumber(row.voice_limit) or 0))
   UI.set_voice_limit(guid,UI.voice_step_value(cur,wheel>0 and 1 or -1))
  end
  return
 end
 if hit and hit.enabled and hit.id:match('^field_') and UI.commit_edit() then
  local key=hit.id:sub(7);local r=Core.ranges[key]
  local step=A.setting_drag_step(key) or 1
  if shift and A.setting_allows_fine(key) then step=step*.1 end
  local raw=S[key]+(wheel>0 and step or -step);local n=UI.nearest_setting_value(key,raw)
  if n~=nil then if abs(n-raw)>1e-9 then field_flash[key]=R.time_precise() end;S[key]=n;UI.changed(key) end
 end
end
function UI.interact(external_wheel)
 if BLT.blocked() then down_last=(gfx.mouse_cap&1)~=0;pressed=nil;gfx.mouse_wheel=0;return end

 if Chrome.mouseActive then down_last=(gfx.mouse_cap&1)~=0;pressed=nil;A.scroll_drag=nil;A.field_drag=nil;return end
 if not animations_active then
  if external_wheel then local hit=UI.widget_at(external_wheel.x,external_wheel.y);UI.apply_wheel(external_wheel.wheel,external_wheel.x,external_wheel.y,external_wheel.shift,hit) end
  down_last=false;pressed=nil;A.scroll_drag=nil;A.curve_drag=nil;A.field_drag=nil;return
 end
 local hit=UI.widget_at(mouse_x,mouse_y)
 if A.job then
  local down=(gfx.mouse_cap&1)~=0;gfx.mouse_wheel=0
  if down and not down_last then pressed=hit and hit.id=='execute' and 'execute' or nil end
  if not down and down_last then if pressed=='execute' and hit and hit.id=='execute' then UI.cancel_job() end;pressed=nil end
  down_last=down;return
 end
 local wheel=gfx.mouse_wheel or 0;gfx.mouse_wheel=0;UI.apply_wheel(wheel,mouse_x,mouse_y,(gfx.mouse_cap&8)~=0,hit)
 local down=(gfx.mouse_cap&1)~=0
 if down and not down_last then
  pressed=hit and hit.id or nil;pressed_mods=gfx.mouse_cap&60
  if hit and hit.id=='matrix_scroll_thumb' and A.scroll_geom then A.scroll_drag={startY=mouse_y,startScroll=A.item_scroll} end
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
 if down and A.curve_drag and A.curve_graph_geom then A.update_pitch_curve_guide(mouse_x,mouse_y,false) end
 if down and A.field_drag then A.update_field_drag(mouse_y,(gfx.mouse_cap&8)~=0) end
 if not down and down_last then
  local curve_was_drag=A.curve_drag and A.curve_drag.moved
  if curve_was_drag then A.finish_pitch_curve_guide() end
  local field_was_drag=A.field_drag and A.field_drag.moved;local was_drag=A.scroll_drag~=nil or curve_was_drag or field_was_drag
  A.scroll_drag=nil;A.curve_drag=nil;A.field_drag=nil;click_mods=pressed_mods
  if not was_drag then
   if hit and hit.enabled and pressed==hit.id then if UI.commit_edit() then hit.fn() end
   elseif edit then UI.commit_edit() end
  end
  pressed=nil;pressed_mods=0;click_mods=0
 end
 down_last=down
end
function UI.keypress(k)
 k=BLT.key(k);if k==0 then return end

 if k==27 then if edit then edit=nil elseif A.job then UI.cancel_job() elseif A.source_job then local restore=A.source_execute_pending and A.source_execute_pending.restore_selection;UI.stop_source_job();A.source_execute_pending=nil;A.source_queue={};A.source_queue_i=1;UI.restore_item_selection(A.project,restore,true);UI.notice('素材の事前解析を中止しました。') else A.closing=true end;return end;if A.job then if k==13 then UI.cancel_job() end;return end
 if k==13 then if edit then UI.commit_edit() else UI.execute() end;return end;if not edit then return end
 if k==9 then UI.commit_edit() elseif k==1 then edit.selected=true elseif k==8 or k==6579564 then edit.text=edit.selected and '' or edit.text:sub(1,-2);edit.selected=false
 elseif k>=48 and k<=57 or k==45 or k==46 then local c=string.char(k);if edit.selected then edit.text=c elseif #edit.text<14 then edit.text=edit.text..c end;edit.selected=false end
end
function UI.close()
 -- Teardown errors must not leave a dead graphics window on screen.
 local ok,err=xpcall(function()
 if A.closed then return end;if A.job then UI.cancel_job() end;A.closed=true;A.job=nil;local restore=A.source_execute_pending and A.source_execute_pending.restore_selection;A.source_execute_pending=nil;UI.stop_source_job();UI.restore_item_selection(A.project,restore,false)
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
BLT.variantDefaults={settings=BLT.copy(Core.defaults),locks={}};for _,k in ipairs(Core.FEATURES) do BLT.variantDefaults.locks[k]=false end;function BLT.captureVariant() BLT.variantView=BLT.variantView or {};BLT.variantView.settings=S;BLT.variantView.locks=A.apply.lock;return BLT.variantView end
function BLT.pick(obj,keys) local v=BLT.valueView or {};BLT.valueView=v;for k in pairs(keys) do v[k]=obj[k] end;return v end
Chrome.titleH=Chrome.title_h;Chrome.titleText=Chrome.title_text or "V A R I A N T   F O R G E";Chrome.windowTitle=Chrome.title
PrimaryButton.painter={C=C,gradient=gradient,line=line,rect=rect,corners=finish_corners,disc=disc,label=label}
PrimaryButton.painter.motion=function(now) return (gfx.mouse_x-ox)/scale,(gfx.mouse_y-oy)/scale,effects_active and 1 or 0 end
PrimaryButton.wake=function() redraw_dirty=true;A.content_dirty=true;next_draw_time=0 end
BLT.attach({
 R=R,C=C,Chrome=Chrome,Chameleon=Chameleon,section=Core.SECTION,faces=fonts,font=font,
 geometry=function() return scale,ox,oy end,active=function() local f=gfx.getchar(65536);return (f&1)==0 or (f&2)~=0 end,
 wake=function() A.content_dirty=true;redraw_dirty=true;next_draw_time=0;wake_visuals() end,
 defaults=BLT.variantDefaults,capture=function() return BLT.captureVariant() end,
 valid=function(v) return Core.validate(v.settings)~=nil end,apply=function(v) for k,x in pairs(v.settings) do S[k]=x end;A.apply.lock=v.locks;UI.changed();UI.persist_now() end,
 undoRefresh=function() UI.refresh() end,
 busy=function() return A.job~=nil or A.source_job~=nil end,commit=function() return UI.commit_edit() end,
 cancelEdit=function() edit=nil;A.field_drag=nil;A.curve_drag=nil end,editing=function() return edit~=nil end,
 modal=function() return false end,
 handle=UI.gfx_window_handle,resizeHit=function(x,y) if y<26 and x>=gfx.w-234 then return nil end;return UI.chrome_resize_hit(x,y) end,
 cursor=UI.set_resize_cursor,beginResize=UI.begin_window_resize,resize=UI.update_window_resize,

})
if ...=='blt_test' then function BLT.testDraw(now) UI.draw(now or R.time_precise()) end end
function BLT.drawIcon()
 flush_text_queue();
 local bs,bx,by=scale,ox,oy;ox,oy=ox+(W-102)*scale,oy+31*scale;scale=scale*.78
 UI.variation_icon(0,0)
 flush_text_queue();
 scale,ox,oy=bs,bx,by
end

if ...=='blt_test' then return {BLT=BLT,A=A,Core=Core,S=S ,UI=UI} end
if ...=='ui_test' then return {draw=UI.draw,state=A,settings=S,refresh=UI.refresh,execute=UI.execute,work=UI.work_step,interact=UI.interact,key=UI.keypress,reset=UI.reset_window_size} end
do
 local chrome_ok,chrome_err=UI.titlebar_api_ready();if not chrome_ok then Language.mb(BLT.publicError(chrome_err),'BLT Variant Forge | エラー',0);return end
 local wx,wy=tonumber(R.GetExtState(Core.SECTION,'window_x')),tonumber(R.GetExtState(Core.SECTION,'window_y'))
 local ww,wh=tonumber(R.GetExtState(Core.SECTION,'window_w')),tonumber(R.GetExtState(Core.SECTION,'window_h'))
 ww=finite(ww) and clamp(ww,860,2100) or W;wh=finite(wh) and clamp(wh,720+Chrome.title_h,1900) or H+Chrome.title_h
 gfx.ext_retina=1;if finite(wx) and finite(wy) then gfx.init(Chrome.title,ww,wh,0,wx,wy) else gfx.init(Chrome.title,ww,wh,0) end
 if not UI.apply_custom_window_style(ww,wh) then gfx.quit();Language.mb('カスタム枠を初期化できません。','BLT Variant Forge',0);return end
 if Chameleon.enabled then Chameleon.refresh(true) end
 UI.wheel_hook_install()
 R.atexit(UI.close)
end
function UI.loop()
 BLT.tick(R.time_precise());PrimaryButton.tick(R.time_precise(),BLT.host.active(),PrimaryButton.wake)

 if A.closing then UI.close();return end
 local k=BLT.key(gfx.getchar());if k<0 then UI.close();return end
 local ok,err=xpcall(function()
  local now=R.time_precise()
  Chameleon.tick(now)
  local flags=gfx.getchar(65536)
  local input_active=(flags&1)==0 or ((flags&2)~=0 and (flags&4)~=0)
  if last_input_active==nil or input_active~=last_input_active then
   last_input_active=input_active;request_redraw(now,.28)
  end
  animations_active=input_active

  local key_activity=false;local n=0
  while k>0 and n<32 do
   key_activity=true
   if animations_active then UI.keypress(k) end
   n=n+1;k=gfx.getchar()
  end
  if key_activity then wake_visuals(now,.40) end
  if A.closing then return end

  UI.flush_persist(false)

  -- Project/selection observation stays alive at its cheap polling cadence.  A
  -- detected change invalidates the cached frame, but an unchanged project does
  -- not redraw anything.
  if not A.job and not A.source_job and now>A.poll then
   A.poll=now+.35
   local project=R.EnumProjects(-1,'');local revision=R.GetProjectStateChangeCount(project);local selection_signature=Core.selection_signature(project)
   if project~=A.project or selection_signature~=A.selection_signature or revision~=A.revision then
    UI.refresh();request_redraw(now,.40)
   else
    local track_signature=Core.track_topology_signature(A.items)
    if track_signature~=A.track_signature then UI.refresh();request_redraw(now,.40) end
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

  -- Pointer activity wakes the visual layer, but actual paints remain capped below.
  -- Activity also arms a four-second particle tail before existing particles finish naturally.
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

  local dragging=A.scroll_drag or A.curve_drag or A.field_drag or Chrome.drag or Chrome.resize or ((raw_cap or 0)&1)~=0
  if dragging then request_effect_activity(now,.12) end
  local hover_animating=animations_active and now<hover_anim_until
  local effects_were_active=effects_active
  effects_active=animations_active and (dragging or A.job~=nil or A.source_job~=nil or now<effect_activity_until)
  if effects_active and not effects_were_active then next_draw_time=0 end

  -- Stop SPAWNING effects as soon as activity ends, but keep painting until every
  -- particle/flash has naturally completed.  This avoids the abrupt disappearance
  -- that the first dirty-redraw implementation caused.
  local flash_alive=false
  for key,t in pairs(field_flash) do if now-t<1.35 then flash_alive=true else field_flash[key]=nil end end
  for key,t in pairs(voice_flash) do if now-t<1.35 then flash_alive=true else voice_flash[key]=nil end end
  local particle_tail=(#icon_particles>0)
  visual_tail_active=effects_active or hover_animating or particle_tail or flash_alive
  -- Keep the scroll cue at normal speed while the rest of the visual tail is
  -- alive.  After that tail finishes, let only this cue coast down smoothly.
  update_scroll_hint_motion(now,visual_tail_active)

  local frame_interval
  if dragging then frame_interval=1/60
  elseif A.job or A.source_job then frame_interval=1/30
  elseif effects_active or particle_tail or flash_alive then frame_interval=1/30
  elseif hover_animating then frame_interval=1/20
  else frame_interval=nil end

  -- custom_titlebar() owns window dragging/resizing and therefore needs a paint
  -- before input dispatch whenever a frame is due.  Static widgets remain valid
  -- between paints, so normal interaction can use the previous frame's hit map.
  local frame_due
  if frame_interval then
   -- During motion/processing, cap paints to the requested frame rate even when
   -- mouse events arrive hundreds of times per second.
   frame_due=now>=next_draw_time
  else
   frame_due=redraw_dirty
  end
  if frame_due then
   UI.render_full_frame();redraw_dirty=false
   next_draw_time=frame_interval and (now+frame_interval) or math.huge
   next_scroll_hint_time=now+SCROLL_HINT_INTERVAL
  elseif frame_interval==nil and scroll_motion_alive and frame_cache_valid and (A.scroll_hint_top or A.scroll_hint_bottom) and now>=next_scroll_hint_time then
   -- Only the scroll cue keeps repainting during its short coast-down.  Once
   -- velocity reaches zero, even this cached-frame blit stops completely.
   UI.draw_scroll_hints_only();next_scroll_hint_time=now+SCROLL_HINT_INTERVAL
  end

  local external_wheel=UI.wheel_hook_poll(not animations_active)
  UI.interact(external_wheel)
  if external_wheel then wake_visuals(now,.30) end

  -- Input handlers run after the current frame.  Queue one following frame so a
  -- click/drag/key result is always visible even if the pointer stops immediately.
  if pointer_changed or key_activity or dragging then redraw_dirty=true end

  if Chrome.requestReset then Chrome.requestReset=false;UI.reset_window_size();request_redraw(now,.45) end
  if Chrome.requestClose then Chrome.requestClose=false;A.closing=true end
 end,debug.traceback)
 if not ok then BLT.cleanup(UI.cancel_job);A.job=nil;BLT.cleanup(UI.stop_source_job);A.source_queue={};A.source_queue_i=1;UI.notice(err,true);BLT.recoverInput(A,err) end
 if A.closing then UI.close() else R.defer(UI.loop) end
end
Core.cleanup_stale_temp_items(A.project);UI.refresh();UI.loop()
