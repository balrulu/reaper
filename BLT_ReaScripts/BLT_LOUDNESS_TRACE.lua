-- @description LOUDNESS TRACE
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

local Core = {}
local floor, min, max, sin, pi = math.floor, math.min, math.max, math.sin, math.pi
function Core.clamp(v, lo, hi) return max(lo, min(hi, v)) end
function Core.finite(v) return type(v)=="number" and v==v and v~=math.huge and v~=-math.huge end
function Core.round(v,digits)
  local factor=10^(digits or 0)
  return (v<0 and math.ceil(v*factor-.5) or floor(v*factor+.5))/factor
end

function Core.time_x(t, first, last, width) return (t-first)/(last-first)*width end
function Core.x_time(x, first, last, width) return first+x/width*(last-first) end
function Core.level_y(v, top, bottom, lo, hi)
  return top+(hi-Core.clamp(v,lo,hi))/(hi-lo)*(bottom-top)
end
function Core.clip_track(y,h,viewport)
  local top=max(0,y); local bottom=min(viewport,y+h)
  return top,max(0,bottom-top),top-y
end
function Core.tick_step(span,width)
  local raw=span/max(2,width/110)
  local power=10^floor(math.log(max(1e-9,raw),10))
  for _,n in ipairs({1,2,5,10}) do if n*power>=raw then return n*power end end
end
function Core.clock(t)
  local sign=t<0 and "-" or ""; t=math.abs(t)
  return string.format("%s%d:%06.3f",sign,floor(t/60),t%60)
end
-- Pure-Lua stereo BS.1770 K weighting, 100 ms hop, absolute/relative gating.
Core.SILENCE=-150
function Core.db(e) return e>0 and max(Core.SILENCE,10*math.log(e,10)) or Core.SILENCE end
function Core.lufs(e) return e>0 and max(Core.SILENCE,-.691+10*math.log(e,10)) or Core.SILENCE end
function Core.lower(a,v)
  local l,h=1,#a+1
  while l<h do local m=(l+h)//2; if a[m]<v then l=m+1 else h=m end end
  return l
end
function Core.integrate(rows,tick)
  local sorted={}
  local gate=10^((-70+.691)/10)
  local nrows=#rows
  for i=1,nrows do local e=rows[i].energy; if e and e>gate then sorted[#sorted+1]=e end end
  table.sort(sorted)
  local sums,counts={},{}
  local sum,count=0,0
  local nsorted=#sorted
  local lower,lufs=Core.lower,Core.lufs
  local function prefix(i)
    local s,c=0,0
    while i>0 do s=s+(sums[i] or 0); c=c+(counts[i] or 0); i=i-(i&-i) end
    return s,c
  end
  for n=1,nrows do
    local r=rows[n]
    local e=r.energy
    if e and e>gate then
      sum=sum+e; count=count+1
      local i=lower(sorted,e)
      while i<=nsorted do sums[i]=(sums[i] or 0)+e; counts[i]=(counts[i] or 0)+1; i=i+(i&-i) end
    end
    if e then
      if count==0 then r.i=Core.SILENCE
      else
        local threshold=max(gate,sum/count*.1)
        local j=lower(sorted,threshold)
        -- BS.1770 uses strictly greater than the gate.
        while j<=nsorted and sorted[j]<=threshold do j=j+1 end
        local s,c=prefix(j-1)
        r.i=count>c and lufs((sum-s)/(count-c)) or Core.SILENCE
      end
    end
    r.energy=nil
    if tick and n%1000==0 then tick(.91+.04*n/nrows) end
  end
  return nrows>0 and rows[nrows].i or Core.SILENCE
end

-- EBU Tech 3342 Loudness Range (LRA): 3 s Short-Term loudness, absolute
-- gate at -70 LUFS, relative gate at -20 LU, then P95 - P10. The existing
-- Short-Term series has 100 ms hops, comfortably exceeding the required overlap.
function Core.lra(rows)
  local absGated={}
  local powerSum=0
  for _,r in ipairs(rows or {}) do
    local v=r.s
    if Core.finite(v) and v>=-70 then
      absGated[#absGated+1]=v
      powerSum=powerSum+10^(v/10)
    end
  end
  local n=#absGated
  if n==0 then return nil end
  local absIntegrated=10*math.log(powerSum/n,10)
  local relThreshold=absIntegrated-20
  local gated={}
  for i=1,n do
    local v=absGated[i]
    if v>=relThreshold then gated[#gated+1]=v end
  end
  n=#gated
  if n==0 then return nil end
  table.sort(gated)
  local function ebu_percentile(p)
    -- EBU reference MATLAB: round((n-1)*p/100 + 1)
    local idx=floor((n-1)*p/100+1+.5)
    idx=max(1,min(n,idx))
    return gated[idx]
  end
  return max(0,ebu_percentile(95)-ebu_percentile(10))
end

function Core.wav(file)
  local size=assert(file:seek('end')); file:seek('set',0)
  local h=assert(file:read(12),'WAVヘッダーがありません。')
  assert(#h==12 and (h:sub(1,4)=='RIFF' or h:sub(1,4)=='RF64') and h:sub(9,12)=='WAVE','WAV形式を確認できません。')
  local format,channels,rate,align,bits,offset,bytes,rfbytes
  while file:seek()+8<=size do
    local chunk=file:read(8); local id,n=string.unpack('<c4I4',chunk)
    local pos=file:seek()
    if id=='ds64' then
      assert(n>=28 and n<1048576,'不正なRF64ヘッダーです。')
      local data=assert(file:read(n)); rfbytes=string.unpack('<I8',data,9)
    elseif id=='fmt ' then
      assert(n>=16 and n<1048576,'不正なWAVフォーマットです。')
      local data=assert(file:read(n)); local byteRate
      format,channels,rate,byteRate,align,bits=string.unpack('<I2I2I4I4I2I2',data)
      if format==65534 and #data>=40 then format=string.unpack('<I2',data,25) end
    elseif id=='data' then
      offset=pos; bytes=n==0xffffffff and rfbytes or n; break
    end
    assert(pos+n+n%2<=size,'WAVが途中で終了しています。')
    file:seek('set',pos+n+n%2)
  end
  assert(format==3 and channels==2 and rate==48000 and align==8 and bits==32,'解析には48 kHz / stereo / float32 WAVが必要です。')
  assert(offset and bytes and bytes>0 and bytes%8==0 and offset+bytes<=size,'レンダーが未完了、またはWAVが破損しています。')
  file:seek('set',offset)
  return bytes//8,rate
end
function Core.analyze(file,expected,tick)
  local frames,sr=Core.wav(file)
  if expected then
    -- REAPER renders time bounds on the audio sample grid. Comparing floating-point
    -- seconds with a two-sample tolerance was unnecessarily strict on some projects.
    -- Allow only a tiny (5 ms max) sample-grid discrepancy; a genuinely interrupted
    -- render is still rejected, and the error reports both lengths for diagnosis.
    local expectedFrames=floor(expected*sr+.5)
    local diffFrames=math.abs(frames-expectedFrames)
    local toleranceFrames=max(8,floor(sr*.005+.5))
    assert(diffFrames<=toleranceFrames,
      string.format('レンダーが中断されたか、測定範囲と音声の長さが一致しません。\n予定: %.6f 秒 / 実際: %.6f 秒 / 差: %.3f ms',
        expected,frames/sr,diffFrames/sr*1000))
  end
  -- Keep the exact BS.1770 math/windowing, but make the sample loop cheaper:
  -- larger buffered reads, localized hot functions, and scalar biquad state.
  local unpack,abs,finite,lufs,db=string.unpack,math.abs,Core.finite,Core.lufs,Core.db
  local rows,kbins,rbins={}, {}, {}
  local z1,z2,z3,z4,z5,z6,z7,z8=0,0,0,0,0,0,0,0
  local ks,raw,peak,n,processed=0,0,0,0,0
  local km,ks3,rm=0,0,0
  local rowCount=0
  while processed<frames do
    local count=min(16384,frames-processed)
    local data=assert(file:read(count*8),'音声を読み取れません。')
    assert(#data==count*8,'音声が途中で終了しています。')
    local pos=1
    for _=1,count do
      local l,r; l,r,pos=unpack('<ff',data,pos)
      assert(finite(l) and finite(r),'音声にNaNまたは無限大が含まれています。')
      peak=max(peak,abs(l),abs(r)); raw=raw+(l*l+r*r)*.5
      -- Two biquads per channel, direct form II transposed, 48 kHz coefficients.
      local yl=1.53512485958697*l+z1
      z1=-2.69169618940638*l+1.69065929318241*yl+z2; z2=1.19839281085285*l-.73248077421585*yl
      local kl=yl+z3; z3=-2*yl+1.99004745483398*kl+z4; z4=yl-.99007225036621*kl
      local yr=1.53512485958697*r+z5
      z5=-2.69169618940638*r+1.69065929318241*yr+z6; z6=1.19839281085285*r-.73248077421585*yr
      local kr=yr+z7; z7=-2*yr+1.99004745483398*kr+z8; z8=yr-.99007225036621*kr
      ks=ks+kl*kl+kr*kr; n=n+1
      if n==4800 then
        rowCount=rowCount+1
        local i=rowCount; local e=ks/n; local re=raw/n
        kbins[i],rbins[i]=e,re
        km=km+e-(kbins[i-4] or 0); ks3=ks3+e-(kbins[i-30] or 0); rm=rm+re-(rbins[i-4] or 0)
        local me=i>=4 and max(0,km/4) or nil
        rows[i]={t=i*.1,energy=me,
          m=me and lufs(me) or nil,s=i>=30 and lufs(max(0,ks3/30)) or nil,
          rms=i>=4 and db(max(0,rm/4)) or nil,peak=db(peak*peak)}
        -- Keep only the sliding window; the measurement rows retain all results.
        kbins[i-30]=nil; rbins[i-4]=nil
        ks,raw,peak,n=0,0,0,0
      end
    end
    processed=processed+count
    if tick then tick(.90*processed/frames) end
  end
  assert(rowCount>=4,'400 ms以上の時間範囲を選択してください。')
  if n>0 then rows[rowCount].peak=max(rows[rowCount].peak,db(peak*peak)) end
  local result={rows=rows,duration=frames/sr,srate=sr}
  result.integrated=Core.integrate(rows,tick)
  if tick then tick(.96) end
  return result
end
Core.metrics={'s','m','i','rms','peak'}
local function build_lod(data,tick)
  data.lod={}
  for _,key in ipairs(Core.metrics) do
    -- Each level is an interleaved {low,high,...} numeric array. The previous
    -- representation allocated one Lua table per bucket (over a million tables
    -- at maximum history), despite every bucket containing only two numbers.
    local first={}
    for _,r in ipairs(data.rows) do
      local value=r[key];if value==nil then value=false end
      first[#first+1]=value;first[#first+1]=value
    end
    local levels={first}
    local n=#data.rows
    while n>1 do
      local prev,nextlevel=levels[#levels],{}
      for i=1,n,2 do
        local ai=(i-1)*2+1;local lo,hi=prev[ai],prev[ai+1]
        if lo==false then lo=nil end;if hi==false then hi=nil end
        if i<n then
          local bi=i*2+1;local blo,bhi=prev[bi],prev[bi+1]
          if blo==false then blo=nil end;if bhi==false then bhi=nil end
          if blo then lo=lo and min(lo,blo) or blo;hi=hi and max(hi,bhi) or bhi end
        end
        nextlevel[#nextlevel+1]=lo==nil and false or lo;nextlevel[#nextlevel+1]=hi==nil and false or hi
      end
      levels[#levels+1]=nextlevel;n=(n+1)//2
      if tick then tick(.98) end
    end
    data.lod[key]=levels
  end
end
-- Render transaction: every temporary setting and track selection is restored on error too.
function Core.render(R,project,source,first,last,directory,basename)
  basename=basename or 'trace'
  -- Track mode uses REAPER's "selected tracks via master" source. Unlike a master
  -- render, this carries only the selected track contribution through its parent/
  -- master processing path and explicitly excludes unselected project tracks.
  -- The measurement source is the user's current time selection, so ask REAPER to
  -- render that exact native bound mode rather than reconstructing it as custom bounds.
  local nums={RENDER_SETTINGS=source and 128 or 0,RENDER_BOUNDSFLAG=2,RENDER_CHANNELS=2,RENDER_SRATE=48000,
    RENDER_STARTPOS=first,RENDER_ENDPOS=last,RENDER_TAILFLAG=0,RENDER_TAILMS=0,RENDER_ADDTOPROJ=0,
    RENDER_DITHER=16,RENDER_NORMALIZE=4<<16}
  local strs={RENDER_FILE=directory,RENDER_PATTERN=basename,RENDER_FORMAT='ZXZhdyADAA==',RENDER_FORMAT2=''}
  local oldn,olds,oldcfg,selected={},{},{},{}
  for k in pairs(nums) do oldn[k]=R.GetSetProjectInfo(project,k,0,false) end
  for k in pairs(strs) do local ok,s=R.GetSetProjectInfo_String(project,k,'',false); assert(ok,'レンダー設定を読み取れません: '..k); olds[k]=s end
  for _,k in ipairs({'renderclosewhendone','autosaveonrender','autosaveonrender2'}) do
    local v=R.SNM_GetIntConfigVar(k,-2147483647)
    if v~=-2147483647 then oldcfg[k]=v end
  end
  assert(oldcfg.renderclosewhendone,'SWSからレンダー設定を取得できません。')
  for i=0,R.CountSelectedTracks(project)-1 do selected[#selected+1]=R.GetSelectedTrack(project,i) end
  local master=R.GetMasterTrack(project)
  local masterSelected=master and R.GetMediaTrackInfo_Value(master,'I_SELECTED')>0.5 or false
  local function restore()
    for k,v in pairs(oldn) do R.GetSetProjectInfo(project,k,v,true) end
    for k,v in pairs(olds) do R.GetSetProjectInfo_String(project,k,v,true) end
    for k,v in pairs(oldcfg) do R.SNM_SetIntConfigVar(k,v) end
    if source then
      for i=0,R.CountTracks(project)-1 do R.SetTrackSelected(R.GetTrack(project,i),false) end
      if master then R.SetTrackSelected(master,masterSelected) end
      for _,tr in ipairs(selected) do if R.ValidatePtr2(project,tr,'MediaTrack*') then R.SetTrackSelected(tr,true) end end
    end
  end
  local ok,result=pcall(function()
    for k,v in pairs(nums) do R.GetSetProjectInfo(project,k,v,true) end
    for k,v in pairs(strs) do assert(R.GetSetProjectInfo_String(project,k,v,true),'レンダー設定を変更できません: '..k) end
    R.SNM_SetIntConfigVar('renderclosewhendone',(oldcfg.renderclosewhendone|1)&~(16|16384|32768))
    for _,k in ipairs({'autosaveonrender','autosaveonrender2'}) do if oldcfg[k] then R.SNM_SetIntConfigVar(k,0) end end
    if source then
      -- Make the render selection unambiguous, including the master-track selection state.
      for i=0,R.CountTracks(project)-1 do R.SetTrackSelected(R.GetTrack(project,i),false) end
      if master then R.SetTrackSelected(master,false) end
      R.SetTrackSelected(source,true)
    end
    local function prefix_wavs()
      local found={}; local i=0
      while true do
        local name=R.EnumerateFiles(directory,i); if not name then break end
        if name:sub(1,#basename)==basename and name:lower():match('%.wav$') then found[#found+1]=directory..'/'..name end
        i=i+1
      end
      return found
    end
    local before={}
    for _,p in ipairs(prefix_wavs()) do before[p:gsub('\\','/'):lower()]=true end
    R.Main_OnCommandEx(41824,0,project)
    local created={}
    for _,p in ipairs(prefix_wavs()) do if not before[p:gsub('\\','/'):lower()] then created[#created+1]=p end end
    assert(#created>0,'一時レンダーのWAVを確認できません。レンダーがキャンセルされた可能性があります。')
    -- A one-track measurement must resolve to exactly one temporary WAV.
    assert(#created==1,'一時レンダーが複数ファイルになりました。解析ソースのトラックを1つだけ指定してください。')
    return created[1]
  end)
  local restored,err=pcall(restore)
  if not restored then error('レンダー設定の復元に失敗: '..tostring(err)) end
  if not ok then error(result,0) end
  return result
end

-- Normalize fresh analysis into the segmented history representation.
function Core.segmented(data)
  if not data or data.segments then return data end
  for _,r in ipairs(data.rows) do r.time=data.first+r.t end
  return {source=data.source,name=data.name,segments={{first=data.first,last=data.last,rows=data.rows}}}
end
local function copy_row(r)
  local n={}; for k,v in pairs(r) do n[k]=v end; return n
end
function Core.replace_range(previous,fresh)
  fresh=Core.segmented(fresh); previous=Core.segmented(previous)
  local incoming=fresh.segments[1]
  incoming.stamp=os.time()
  local result={source=fresh.source,name=fresh.name,segments={}}
  local function keep(seg,a,b,stale)
    if b-a<1e-8 then return end
    local out={first=a,last=b,rows={},stale=stale and true or false,stamp=seg.stamp or 0}
    for _,r in ipairs(seg.rows) do
      if r.time>a+1e-8 and r.time<=b+1e-8 then out.rows[#out.rows+1]=copy_row(r) end
    end
    if #out.rows>0 then result.segments[#result.segments+1]=out end
  end
  if previous and previous.source==fresh.source then
    for _,seg in ipairs(previous.segments) do
      -- Retained ranges keep age metadata only for bounded-history pruning; visuals stay identical.
      if seg.last<=incoming.first or seg.first>=incoming.last then keep(seg,seg.first,seg.last,true)
      else
        keep(seg,seg.first,min(seg.last,incoming.first),true)
        keep(seg,max(seg.first,incoming.last),seg.last,true)
      end
    end
  end
  -- The newly measured range receives the newest history stamp; no visual distinction is applied.
  keep(incoming,incoming.first,incoming.last,false)
  table.sort(result.segments,function(a,b) return a.first<b.first end)
  return result
end
function Core.trim_history(data,maxrows)
  local total=0
  for _,seg in ipairs(data.segments) do total=total+#seg.rows end
  local removed=0
  while total>maxrows and #data.segments>1 do
    local victimIndex,victimStamp=nil,math.huge
    for i,seg in ipairs(data.segments) do
      if seg.stale and (seg.stamp or 0)<victimStamp then victimIndex=i;victimStamp=seg.stamp or 0 end
    end
    if not victimIndex then break end
    local seg=data.segments[victimIndex]
    local excess=total-maxrows
    if #seg.rows<=excess then
      removed=removed+#seg.rows;total=total-#seg.rows;table.remove(data.segments,victimIndex)
    else
      for _=1,excess do table.remove(seg.rows,1) end
      removed=removed+excess;total=total-excess
      seg.first=seg.rows[1].time-.1
    end
  end
  return removed
end
function Core.recompute(data,tick)
  data.rows={}
  local total=0
  for _,seg in ipairs(data.segments) do
    assert(seg.last>seg.first and #seg.rows>0,'保存区間が不正です。')
    seg.origin=seg.rows[1].time-.1
    for _,r in ipairs(seg.rows) do
      r.i=nil
      -- Exclude a 400 ms block crossing a replaced/deleted boundary.
      -- S/M themselves stay as originally measured outside the replacement.
      r.energy=(r.m and r.time-.4>=seg.first-1e-7) and (r.m<=-150 and 0 or 10^((r.m+.691)/10)) or nil
      data.rows[#data.rows+1]=r; total=total+1
      if tick and total%1000==0 then tick(.94) end
    end
  end
  assert(total>0 and total<=432000,'保持できる測定量（12時間）を超えました。')
  Core.integrate(data.rows,tick)
  local cumulative
  for _,r in ipairs(data.rows) do if r.i then cumulative=r.i else r.i=cumulative end end
  data.integrated=cumulative or Core.SILENCE
  data.lra=Core.lra(data.rows)
  data.first=data.segments[1].first;data.last=data.segments[#data.segments].last
  for _,seg in ipairs(data.segments) do build_lod(seg,tick) end
end
function Core.row(data,time)
  if not data or not data.segments then return nil end
  local l,h=1,#data.segments;local found
  while l<=h do
    local m=(l+h)//2;local seg=data.segments[m]
    if time>=seg.first then found=seg;l=m+1 else h=m-1 end
  end
  if not found or time>found.last+1e-8 then return nil end
  l,h=1,#found.rows;local row
  while l<=h do
    local m=(l+h)//2
    if found.rows[m].time<=time+1e-8 then row=found.rows[m];l=m+1 else h=m-1 end
  end
  return row
end
function Core.pack(data)
  local chunks,lines={},{}
  local function add(s)
    lines[#lines+1]=s
    if #lines>=512 then chunks[#chunks+1]=table.concat(lines,'\n');lines={} end
  end
  local function number(n) return n and string.format('%.12g',n) or 'x' end
  for _,seg in ipairs(data.segments) do
    add('G,'..string.format('%.9f,%.9f,%d,%.6f',seg.first,seg.last,seg.stale and 1 or 0,seg.stamp or 0))
    for _,r in ipairs(seg.rows) do
      local f={'R',string.format('%.9f',r.time)}
      for _,k in ipairs({'s','m','rms','peak'}) do f[#f+1]=number(r[k]) end
      add(table.concat(f,','))
    end
  end
  if #lines>0 then chunks[#chunks+1]=table.concat(lines,'\n') end
  return chunks
end
function Core.unpack(chunks)
  local data={segments={}};local current;local total=0
  for _,chunk in ipairs(chunks) do
    for line in chunk:gmatch('[^\n]+') do
      local f={};for v in (line..','):gmatch('(.-),') do f[#f+1]=v end
      if f[1]=='G' then
        local a,b=tonumber(f[2]),tonumber(f[3])
        assert(#f==5 and Core.finite(a) and Core.finite(b) and b>a,'保存範囲が不正です。')
        assert(not current or a>=current.last-1e-8,'保存範囲が重複しています。')
        local stamp=tonumber(f[5]);assert(Core.finite(stamp),'保存時刻情報が不正です。')
        current={first=a,last=b,rows={},stale=f[4]=='1',stamp=stamp};data.segments[#data.segments+1]=current
      elseif f[1]=='R' then
        assert(current and #f==6,'保存データが不正です。')
        local r={time=tonumber(f[2])}
        assert(Core.finite(r.time) and r.time>current.first and r.time<=current.last+1e-7,'保存時刻が範囲外です。')
        local prev=current.rows[#current.rows]
        assert(not prev or math.abs(r.time-prev.time-.1)<1e-6,'保存カーブが途切れています。')
        for j,k in ipairs({'s','m','rms','peak'}) do
          local v=tonumber(f[j+2]);assert(f[j+2]=='x' or Core.finite(v),'保存数値が不正です。');r[k]=v
        end
        current.rows[#current.rows+1]=r;total=total+1;assert(total<=432000,'保存データが上限を超えています。')
      else error('不明な保存データ形式です。') end
    end
  end
  assert(#data.segments>0,'保存データが空です。')
  return data
end
-- A slow, broad loudness-style history line moving continuously right-to-left.
-- The shape is analytic rather than frame-randomized, so the icon remains temporally stable.
function Core.loudness_line(seconds)
  local out={}
  local width,step,speed=76,2,4.6
  local travel=seconds*speed
  for x=0,width,step do
    local world=x+travel
    -- Long wavelengths keep the motion closer to a loudness trace than an audio waveform.
    local y=7.2*sin(world*.105+.35)+3.8*sin(world*.047+1.55)+1.8*sin(world*.021+.4)
    local edge=min(1,x/8,(width-x)/8)
    out[#out+1]={x=x,y=y,a=max(0,edge)}
  end
  return out
end
function Core.axis_ticks(lo,hi,pixels)
  local step=Core.tick_step(hi-lo,pixels*3)
  local start=math.ceil(lo/step)*step;local out={};local previous
  -- Bounded iteration also handles magnitudes where adding a step rounds to itself.
  for i=0,64 do
    local v=start+i*step
    if v>hi then break end
    if v>=lo and v~=previous then out[#out+1]=v;previous=v end
  end
  return out
end

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
 ["WAVヘッダーがありません。"]="Missing WAV header.",
 ["WAV形式を確認できません。"]="Cannot identify WAV format.",
 ["不正なRF64ヘッダーです。"]="Invalid RF64 header.",
 ["不正なWAVフォーマットです。"]="Invalid WAV format.",
 ["WAVが途中で終了しています。"]="Truncated WAV.",
 ["解析には48 kHz / stereo / float32 WAVが必要です。"]="Analysis requires 48 kHz / stereo / float32 WAV.",
 ["レンダーが未完了、またはWAVが破損しています。"]="Render incomplete or WAV damaged.",
 ["レンダーが中断されたか、測定範囲と音声の長さが一致しません。\n予定: %.6f 秒 / 実際: %.6f 秒 / 差: %.3f ms"]="Render interrupted or duration mismatch.\nExpected: %.6f s / Actual: %.6f s / Difference: %.3f ms",
 ["音声を読み取れません。"]="Cannot read audio.",
 ["音声が途中で終了しています。"]="Truncated audio.",
 ["音声にNaNまたは無限大が含まれています。"]="Audio contains NaN or infinity.",
 ["400 ms以上の時間範囲を選択してください。"]="Select a time range of at least 400 ms.",
 ["レンダー設定を読み取れません: "]="Cannot read render setting: ",
 ["SWSからレンダー設定を取得できません。"]="Cannot read render settings from SWS.",
 ["レンダー設定を変更できません: "]="Cannot change render setting: ",
 ["一時レンダーのWAVを確認できません。レンダーがキャンセルされた可能性があります。"]="Cannot find temporary render WAV. Render may have been cancelled.",
 ["一時レンダーが複数ファイルになりました。解析ソースのトラックを1つだけ指定してください。"]="Temporary render produced multiple files. Select only one source track.",
 ["レンダー設定の復元に失敗: "]="Cannot restore render setting: ",
 ["保存区間が不正です。"]="Invalid saved section.",
 ["保持できる測定量（12時間）を超えました。"]="Measurement limit exceeded (12 hours).",
 ["保存範囲が不正です。"]="Invalid saved range.",
 ["保存範囲が重複しています。"]="Saved ranges overlap.",
 ["保存時刻情報が不正です。"]="Invalid saved time information.",
 ["保存データが不正です。"]="Invalid saved data.",
 ["保存時刻が範囲外です。"]="Saved time is out of range.",
 ["保存カーブが途切れています。"]="Saved curve has gaps.",
 ["保存数値が不正です。"]="Invalid saved number.",
 ["保存データが上限を超えています。"]="Saved data exceeds limit.",
 ["不明な保存データ形式です。"]="Unknown saved data format.",
 ["保存データが空です。"]="Saved data is empty.",
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
 ["不明なエラー"]="Unknown error",
 ["処理中にエラーが発生しました。"]="An error occurred during processing.",
 ["LOUDNESS TRACEにはSWSとjs_ReaScriptAPIが必要です。\nSWS: https://www.sws-extension.org/\njs_ReaScriptAPI: ReaPackからインストール\n\n不足: "]="LOUDNESS TRACE requires SWS and js_ReaScriptAPI.\nSWS: https://www.sws-extension.org/\njs_ReaScriptAPI: install via ReaPack\n\nMissing: ",
 ["LOUDNESS TRACE | 必要な拡張"]="LOUDNESS TRACE | Required extensions",
 ["LOUDNESS TRACEはWindows用です。"]="LOUDNESS TRACE requires Windows.",
 ["保存できる履歴は解析ソースごとに最大3.5時間です。古い履歴を整理してから再試行してください。"]="History is limited to 3.5 hours per source. Remove old history, then retry.",
 ["保存データが12 MiBの安全上限を超えました。測定範囲を短くしてください。"]="Saved data exceeds the 12 MiB safety limit. Shorten the measurement range.",
 ["カーブを保存できません。"]="Cannot save curve.",
 ["結果を保存できません。"]="Cannot save results.",
 ["保存情報が不正です。"]="Invalid saved information.",
 ["保存カーブが不足しています。"]="Missing saved curve data.",
 ["指定トラックが見つかりません"]="Source track not found",
 ["LOUDNESS TRACE: 表示トラックを作成"]="LOUDNESS TRACE: Create display track",
 ["描画用ビットマップを作成できません。"]="Cannot create drawing bitmap.",
 ["CHAMELEON  REAPERテーマに擬態"]="CHAMELEON  REAPER theme",
 ["CHAMELEON  オリジナル配色"]="CHAMELEON  Original colors",
 ["解析ソース"]="Source",
 ["前回の解析で残った可能性がある一時ファイルを%d件検出しました（合計 %s）。\n\n削除してよろしいですか？\n別のLOUDNESS TRACEが現在解析中の場合だけキャンセルしてください。"]="Found %d temporary files possibly left by an earlier analysis (total %s).\n\nDelete them?\nCancel if another LOUDNESS TRACE is currently analyzing.",
 ["LOUDNESS TRACE | 一時ファイル回収"]="LOUDNESS TRACE | Temporary files",
 ["長い範囲を解析するため、一時WAVを約 %s 作成します。\n解析中は同程度の空き容量が必要です。続行しますか？\n\n範囲：%.1f分"]="This range creates about %s of temporary WAV data.\nKeep this much disk space free during analysis. Continue?\n\nRange: %.1f min",
 ["LOUDNESS TRACE | 長尺解析"]="LOUDNESS TRACE | Long analysis",
 ["測定開始前にプロジェクトが切り替わりました。"]="Project changed before measurement started.",
 ["測定元トラックが削除されました。"]="Source track was deleted.",
 ["測定開始前に時間選択が変更されました。"]="Time selection changed before measurement started.",
 ["レンダーがキャンセルされたか、一時音声を開けません。"]="Render cancelled or temporary audio unavailable.",
 ["LOUDNESS TRACE | 解析"]="LOUDNESS TRACE | Analysis",
 ["LOUDNESS TRACE | 保存"]="LOUDNESS TRACE | Save",
 ["MASTER OUT 1/2|選択中のトラック / バスを指定"]="MASTER OUT 1/2|Use selected track / bus",
 ["目標"]="Aim",
 ["カメレオンモード（配色をテーマへ擬態）"]="Chameleon: match REAPER colors",
 ["折りたたむ"]="Collapse",
 ["ドッキング中はウィンドウを縮小できません。\nフローティング表示で使用してください。"]="Cannot collapse while docked.\nUse a floating window.",
 ["中止"]="Stop",
 ["解析"]="Analyze",
 ["ARRANGE LOUDNESS ANALYSIS  アレンジビュー上でラウドネスを解析・表示"]="ARRANGE LOUDNESS ANALYSIS  Analyze and display loudness",
 ["保存済み："]="Saved: ",
 ["区間  ·  選択範囲だけ置換"]=" sections · Replace selected range only",
 ["時間範囲を選択して解析。範囲外の解析結果は保持します。"]="Select a time range to analyze. Keep results outside that range.",
 ["グラフ "]="Graph ",
 ["警告表示"]="WARNINGS",
 ["補助表示"]="GUIDES",
 ["上限"]="Upper",
 ["超過"]="Above",
 ["下限"]="Lower",
 ["未満"]="Below",
 ["ピーク"]="Peak",
 ["グラフ設定"]="GRAPH",
 ["グラフ幅："]="Width:",
 ["解析結果へ最適化"]="Fit to results",
 ["グラフを非表示"]="Hide graph",
 ["グラフを表示"]="Show graph",
 ["グラフをクリア"]="Clear graph",
 ["解析を中止  "]="Stop analysis  ",
 ["選択範囲を解析"]="Analyze selection",
 ["解析中 %d%%"]="Analyzing %d%%",
 ["プロジェクトが変更されています。再解析してください。"]="Project changed. Analyze again.",
 ["解析結果を表示しています。"]="Showing analysis results.",
 ["時間範囲を選択してください。"]="Select a time range.",
 ["グラフ用フォントを作成できません。"]="Cannot create graph font.",
 ["LOUDNESS TRACE | エラー"]="LOUDNESS TRACE | Error",
 ["表示言語を切替（JP / EN）"]="Switch language (JP / EN)",
 ["プリセットを読み込みました: ファクトリーデフォルト"]="Loaded: Factory Default",
 ["選択中のトラック / バスを指定"]="Use selected track / bus",
 ["グラフ ON"]="Graph ON",
 ["グラフ OFF"]="Graph OFF",
},patterns={
 {"^「(.*)」を上書きしますか？$","Overwrite \"%s\"?"},
 {"^レンダーが中断されたか、測定範囲と音声の長さが一致しません。\n予定: ([%+%-]?[%d%.eE]+) 秒 / 実際: ([%+%-]?[%d%.eE]+) 秒 / 差: ([%+%-]?[%d%.eE]+) ms$","Render interrupted or duration mismatch.\nExpected: %.6f s / Actual: %.6f s / Difference: %.3f ms"},
 {"^([%+%-]?[%d%.eE]+)–([%+%-]?[%d%.eE]+) / ([%+%-]?[%d%.eE]+)   スクロールで選択$","%d–%d / %d   Scroll to browse"},
 {"^解析中%.%.%.([%+%-]?[%d%.eE]+)%%$","Analyzing...%d%%"},
 {"^前回の解析で残った可能性がある一時ファイルを([%+%-]?[%d%.eE]+)件検出しました（合計 (.-)）。\n\n削除してよろしいですか？\n別のLOUDNESS TRACEが現在解析中の場合だけキャンセルしてください。$","Found %d temporary files possibly left by an earlier analysis (total %s).\n\nDelete them?\nCancel if another LOUDNESS TRACE is currently analyzing."},
 {"^長い範囲を解析するため、一時WAVを約 (.-) 作成します。\n解析中は同程度の空き容量が必要です。続行しますか？\n\n範囲：([%+%-]?[%d%.eE]+)分$","This range creates about %s of temporary WAV data.\nKeep this much disk space free during analysis. Continue?\n\nRange: %.1f min"},
 {"^解析中 ([%+%-]?[%d%.eE]+)%%$","Analyzing %d%%"},
 {"^レンダー設定を読み取れません: (.-)$","Cannot read render setting: %s"},
 {"^レンダー設定を変更できません: (.-)$","Cannot change render setting: %s"},
 {"^レンダー設定の復元に失敗: (.-)$","Cannot restore render setting: %s"},
 {"^「(.-)」を上書きしますか？$","\"%s\"?"},
 {"^(.-)」を上書きしますか？$","%s\"?"},
 {"^プリセットを保存しました: (.-)$","Saved: %s"},
 {"^プリセットを読み込みました: (.-)$","Loaded: %s"},
 {"^(.-)個インポートしました。$","%s preset(s) imported."},
 {"^現在: (.-)(.-)$","Current: %s%s"},
 {"^LOUDNESS TRACEにはSWSとjs_ReaScriptAPIが必要です。\nSWS: https://www%.sws%-extension%.org/\njs_ReaScriptAPI: ReaPackからインストール\n\n不足: (.-)$","LOUDNESS TRACE requires SWS and js_ReaScriptAPI.\nSWS: https://www.sws-extension.org/\njs_ReaScriptAPI: install via ReaPack\n\nMissing: %s"},
 {"^(.-)MASTER OUT 1/2|選択中のトラック / バスを指定$","%sMASTER OUT 1/2|Use selected track / bus"},
 {"^保存済み：(.-)  /  (.-)$","Saved: %s  /  %s"},
 {"^(.-)区間  ·  選択範囲だけ置換$","%s sections · Replace selected range only"},
 {"^グラフ (.-)$","Graph %s"},
 {"^グラフ幅：(.-)$","Width:%s"},
 {"^解析を中止  (.-)%%$","Stop analysis  %s%%"},
 {"^「(.*)」を上書きしますか？$","Overwrite \"%s\"?"},
 {"^(%d+)個インポートしました。$","Imported %s preset(s)."},
 {"^(%d+)件をノーマライズしました。選択を解除しました。$","Normalized %s items and deselected them."},
},prefixes={"LOUDNESS TRACEにはSWSとjs_ReaScriptAPIが必要です。\nSWS: https://www.sws-extension.org/\njs_ReaScriptAPI: ReaPackからインストール\n\n不足: ","レンダー設定を読み取れません: ","レンダー設定を変更できません: ","プリセットを読み込みました: ","レンダー設定の復元に失敗: ","プリセットを保存しました: ","保存済み：","グラフ幅：","現在: "}}

LanguageCatalog.en["LOUDNESS TRACEはWindows／macOS用です。"]="LOUDNESS TRACE requires Windows or macOS."
LanguageCatalog.en["現在のMetal設定ではグラフを重ね描画できません。REAPERの高度なUI設定でMetalを無効にするか、描画互換モードを選び、必要に応じてREAPERを再起動してください。"]="The current Metal mode cannot display the graph overlay. Disable Metal or enable drawing compatibility in REAPER's advanced UI settings, then restart REAPER if needed."

local Language=create_language(reaper,"LOUDNESS_TRACE",LanguageCatalog)
-- LOUDNESS TRACE platform adapter 1.0.1. Embedded; no runtime file dependency.
local function create_trace_platform(api,graphics)
 local osname=api.GetOS()
 local P={mac=osname:match('OSX')~=nil or osname:match('macOS')~=nil,windows=osname:match('Win')~=nil}
 P.api=api
 P.chromeFont=P.mac and 'Helvetica Neue' or 'Segoe UI'
 P.graphFont=P.chromeFont
 P.faces=P.mac and {'Hiragino Sans','Helvetica Neue','Menlo','Hiragino Sans'} or {'Yu Gothic UI','Segoe UI','Consolas','Yu Gothic UI'}
 P.bodyFaces=P.mac and {'Hiragino Sans','Menlo','Helvetica Neue','Hiragino Sans'} or {'Yu Gothic UI','Consolas','Segoe UI','Yu Gothic UI'}
 function P.tempDirectory()
  if P.mac then
   local directory=os.getenv('TMPDIR')
   return directory and directory~='' and directory or '/tmp'
  end
  return os.getenv('TEMP') or api.GetResourcePath()
 end
 -- Windows keeps the original API table and every existing call unchanged.
 if not P.mac then return P end
 local R=setmetatable({}, {__index=api});P.api=R
 -- Async layered drawing can still reference the last published bitmap after
 -- unlink. Retire whole bitmaps for two defer turns instead of resizing/reusing
 -- their storage immediately. This queue exists only on macOS.
 local retired,epoch={},0
 function R.JS_LICE_DestroyBitmap(bitmap)
  if bitmap then retired[#retired+1]={bitmap=bitmap,epoch=epoch+2} end
 end
 function P.advance()
  epoch=epoch+1
  for i=#retired,1,-1 do
   if retired[i].epoch<=epoch then api.JS_LICE_DestroyBitmap(retired[i].bitmap);table.remove(retired,i) end
  end
 end
 function P.finish()
  if #retired==0 or P.draining then return end
  P.draining=true
  local function drain()
   P.advance()
   if #retired>0 then api.defer(drain) else P.draining=false end
  end
  api.defer(drain)
 end
 -- Internal screen Y points downward. Native macOS screen Y points upward.
 -- Client coordinates already point downward and must never be flipped.
 function R.GetMousePosition()
  local x,y=api.GetMousePosition();return x,-y
 end
 function R.JS_Window_GetRect(hwnd)
  local ok,l,t,r,b=api.JS_Window_GetRect(hwnd)
  if not ok then return ok,l,t,r,b end
  return ok,l,-math.max(t,b),r,-math.min(t,b)
 end
 function R.JS_Window_SetPosition(hwnd,x,y,w,h,z,flags)
  -- A docked controller is a child view whose geometry belongs to REAPER.
  -- Screen-to-window conversion below is valid only while floating.
  if graphics and graphics.dock and (graphics.dock(-1)&1)~=0 then return false end
  -- Used only for the floating controller. SWELL positions top-level windows
  -- by their bottom-left corner; preserve our top edge while resizing.
  return api.JS_Window_SetPosition(hwnd,x,-y-h,w,h,z,flags)
 end
 function R.JS_Window_ClientToScreen(hwnd,x,y)
  local sx,sy=api.JS_Window_ClientToScreen(hwnd,x,y);return sx,-sy
 end
 function R.JS_Window_ScreenToClient(hwnd,x,y)
  return api.JS_Window_ScreenToClient(hwnd,x,-y)
 end
 function R.JS_Window_FromPoint(x,y) return api.JS_Window_FromPoint(x,-y) end
 return P
end

local Platform=create_trace_platform(reaper,gfx)
local R=Platform.api
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

local SECTION="LOUDNESS_TRACE"
local TAG="P_EXT:"..SECTION
local TRACK_CACHE_LIMIT=3
local MAX_HISTORY_ROWS=126000 -- 3.5 hours at 100 ms resolution per measurement target.
local MAX_SAVE_BYTES=12*1024*1024
local TEMP_WARNING_SECONDS=25*60
local TEMP_BYTES_PER_SECOND=48000*2*4 -- stereo float32 WAV, excluding its tiny header.
local W,H=646,616
local COLLAPSED_W,COLLAPSED_H=350,58
local COMPACT_MEASURE_X,COMPACT_MEASURE_Y,COMPACT_MEASURE_W,COMPACT_MEASURE_H=256,12,78,34
local C={bg={.018,.030,.055},panel={.040,.068,.110},field={.018,.040,.080},
  edge={.145,.285,.445},text={.955,.980,1},muted={.690,.780,.875},
  faint={.390,.505,.635},accent={.120,.490,.980},ice={.650,.895,1},
  deep={.045,.235,.520},warn={1,.65,.35},mint={.38,.88,.72},red={1,.27,.34},purple={.77,.64,1},gold={1,.80,.39}}
local S={lo=-60,hi=0,visible=true,height=280,
  show={s=true,m=true,i=true,rms=false,peak=false},
  targets={s={-23,3},m={-23,3},i={-23,1}},source="master",
  alertUpper=true,alertLower=true,alertPeak=false}
local function target_alert(v,target)
  if not v or not target then return false end
  if S.alertUpper and v>target[1]+target[2] then return true end
  if S.alertLower and v<target[1]-target[2] then return true end
  return false
end
local function bucket_alert(low,high,target)
  if not target then return false end
  if S.alertUpper and high and high>target[1]+target[2] then return true end
  if S.alertLower and low and low<target[1]-target[2] then return true end
  return false
end
local function peak_bucket_alert(low,high)
  return S.alertPeak and high and high>=0 or false
end

-- Warning durations use the local S/M curves; overlapping warnings count once.
local function warning_durations(data)
  local upper,lower,peak=0,0,0
  if not data then return upper,lower,peak end
  for _,r in ipairs(data.rows or {}) do
    local up,down=false,false
    if r.s then
      local t=S.targets.s
      up=up or r.s>t[1]+t[2]
      down=down or r.s<t[1]-t[2]
    end
    if r.m then
      local t=S.targets.m
      up=up or r.m>t[1]+t[2]
      down=down or r.m<t[1]-t[2]
    end
    if up then upper=upper+.1 end
    if down then lower=lower+.1 end
    if r.peak and r.peak>=0 then peak=peak+.1 end
  end
  return upper,lower,peak
end
local function warning_time_text(seconds)
  seconds=max(0,floor((seconds or 0)+.5))
  if seconds>=3600 then
    return string.format('%d:%02d:%02d',seconds//3600,(seconds%3600)//60,seconds%60)
  end
  return string.format('%d:%02d',seconds//60,seconds%60)
end
local A={data=nil,job=nil,stale=false,project=nil,track=nil,bitmap=nil,arrange=nil,
  linked=false,revision=0,lastPaint=0,compositeDelayWindow=nil,compositeDelayPrev=nil,lastArrangeMouseX=nil,mouseRepairQueue={},mouseSweepMin=nil,mouseSweepMax=nil,lastMouseMoveAt=nil,cache="",hover=nil,
  closed=false,down=false,pressed=nil,particles={},serial=0,particleClock=0,
  iconParticles={},iconClock=0,iconSerial=0,motion={},dt=0,anim=0,active=true,
  analysisButtonSerial=0,analysisBurst=nil,analysisBurstParticles={},
  backBitmap=nil,drawBitmap=nil,collapsed=false,gfxWindow=nil,normalWindow=nil,normalDock=nil,foldAnim=0,windowTransition=nil,
  titleMouseDown=false,titleDrag=nil,titleClosePressed=false,titleFoldPressed=false,titleResetPressed=false,titleChameleonPressed=false,titleMouseActive=false,
  resizeDrag=nil,resizeMouseActive=false,resizeCursorMode=nil,resizeCursors={},requestClose=false,requestFold=false,requestReset=false,
  tempDeletePending={},tempDeleteRetryAt=0,
  tooltipHover=nil,tooltipSince=0,tooltipVisible=false,tooltipDelay=.70,
  fieldFlash={},fieldDrag=nil,titleH=26,resizeEdge=6,resizeCornerBand=8,resizeCornerSpan=24,resizeTopLeftGuard=30,resizeTopRightGuard=144,minWindowW=520,minWindowH=327,
  resizeCursorId={we=32644,ns=32645,nwse=32642,nesw=32643,arrow=32512}}
local function extnum(key,default)
  local n=tonumber(R.GetExtState(SECTION,key)); return Core.finite(n) and n or default
end
local function public_error(err)
  return BLT.publicError(err,'処理中にエラーが発生しました。')
end
local required={"SNM_GetIntConfigVar","SNM_SetIntConfigVar","JS_Window_FindChildByID","JS_Window_Find","JS_Window_IsWindow","JS_Window_GetRect","JS_Window_GetClientSize","JS_Window_SetPosition",
  "JS_Window_ClientToScreen","JS_Window_ScreenToClient","JS_Window_FromPoint","JS_Window_SetStyle",
  "JS_Mouse_LoadCursor","JS_Mouse_SetCursor",
  "JS_Composite","JS_Composite_Unlink","JS_Window_InvalidateRect","JS_LICE_CreateBitmap","JS_LICE_DestroyBitmap",
  "JS_LICE_Clear","JS_LICE_Blit","JS_LICE_FillRect","JS_LICE_Line","JS_LICE_CreateFont",
  "JS_LICE_DestroyFont","JS_LICE_SetFontFromGDI","JS_LICE_SetFontColor",
  "JS_LICE_SetFontBkColor","JS_LICE_DrawText","JS_GDI_CreateFont","JS_GDI_DeleteObject"}
if Platform.windows then required[#required+1]="JS_Composite_Delay" end
if Platform.mac then required[#required+1]="JS_Window_EnableMetal" end
local missing={}
for _,name in ipairs(required) do if not R.APIExists(name) then missing[#missing+1]=name end end
if #missing>0 then
  Language.mb("LOUDNESS TRACEにはSWSとjs_ReaScriptAPIが必要です。\nSWS: https://www.sws-extension.org/\njs_ReaScriptAPI: ReaPackからインストール\n\n不足: "..table.concat(missing,", "), "LOUDNESS TRACE | 必要な拡張",0)

  return
end
if not Platform.windows and not Platform.mac then
  Language.mb("LOUDNESS TRACEはWindows／macOS用です。", "LOUDNESS TRACE",0); return
end

local function restore_composite_delay()
  if not Platform.windows then return end
  if A.compositeDelayWindow and A.compositeDelayPrev and R.JS_Window_IsWindow(A.compositeDelayWindow) then
    local p=A.compositeDelayPrev
    pcall(R.JS_Composite_Delay,A.compositeDelayWindow,p.min,p.max,p.bitmaps)
  end
  A.compositeDelayWindow=nil;A.compositeDelayPrev=nil
end
local function configure_composite_delay(hwnd)
  if not Platform.windows then return end
  if A.compositeDelayWindow==hwnd and A.compositeDelayPrev then return end
  restore_composite_delay()
  -- JS_Composite_Delay was added specifically on Windows to reduce composite flicker.
  -- Preserve the previous per-window values so other scripts/REAPER are not left altered.
  local _,pmin,pmax,pbitmaps=R.JS_Composite_Delay(hwnd,-1,-1,-1)
  A.compositeDelayWindow=hwnd
  A.compositeDelayPrev={min=pmin or -1,max=pmax or -1,bitmaps=pbitmaps or -1}
  R.JS_Composite_Delay(hwnd,.040,.040,2)
end
local function unlink()
  if A.linked and A.arrange and A.bitmap then
    if R.JS_Window_IsWindow(A.arrange) then R.JS_Composite_Unlink(A.arrange,A.bitmap,true) end
  end
  restore_composite_delay()
  A.linked=false; A.cache=""; A.hover=nil; A.lastArrangeMouseX=nil; A.mouseRepairQueue={}; A.mouseSweepMin=nil; A.mouseSweepMax=nil; A.lastMouseMoveAt=nil
end
local function dispose_bitmap()
  unlink()
  A.drawBitmap=nil
  if A.backBitmap then R.JS_LICE_DestroyBitmap(A.backBitmap); A.backBitmap=nil end
  if A.bitmap then R.JS_LICE_DestroyBitmap(A.bitmap); A.bitmap=nil end
end
local function valid_track()
  return A.track and A.project and R.ValidatePtr2(A.project,A.track,"MediaTrack*")
end
local function find_track()
  for i=0,R.CountTracks(A.project)-1 do
    local tr=R.GetTrack(A.project,i)
    local _,tag=R.GetSetMediaTrackInfo_String(tr,TAG,"",false)
    if tag=="display" then return tr end
  end
end
local function save_settings()
  local fields={S.source,tostring(S.height),tostring(S.lo),tostring(S.hi)}
  for _,v in ipairs({S.show.s,S.show.m,S.show.i,S.show.rms,S.show.peak}) do fields[#fields+1]=v and '1' or '0' end
  for _,k in ipairs({'s','m','i'}) do fields[#fields+1]=tostring(S.targets[k][1]);fields[#fields+1]=tostring(S.targets[k][2]) end
  fields[#fields+1]=S.alertUpper and '1' or '0'
  fields[#fields+1]=S.alertLower and '1' or '0'
  fields[#fields+1]=S.alertPeak and '1' or '0'
  R.SetProjExtState(A.project,SECTION,'settings',table.concat(fields,';'))
end
local function load_settings()
  S.source='master';S.height=280;S.lo=-60;S.hi=0
  S.show={s=true,m=true,i=true,rms=false,peak=false}
  S.targets={s={-23,3},m={-23,3},i={-23,1}}
  S.alertUpper=true;S.alertLower=true;S.alertPeak=false
  local _,raw=R.GetProjExtState(A.project,SECTION,'settings')
  local f={};for v in raw:gmatch('[^;]+') do f[#f+1]=v end
  if #f<18 then return end
  S.source=f[1];S.height=Core.clamp(tonumber(f[2]) or 280,180,800)
  local lo,hi=tonumber(f[3]),tonumber(f[4])
  if Core.finite(lo) and Core.finite(hi) and Core.finite(hi-lo) and hi-lo>1e-6 then
    lo=Core.round(Core.clamp(lo,-120,18),2)
    hi=Core.round(Core.clamp(hi,max(-118,lo+.1),24),2)
    if hi>lo then S.lo,S.hi=lo,hi end
  end
  S.show.s=f[5]=='1';S.show.m=f[6]=='1';S.show.i=f[7]=='1';S.show.rms=f[8]=='1';S.show.peak=f[9]=='1'
  for j,k in ipairs({'s','m','i'}) do
    local base=8+j*2
    local t,e=tonumber(f[base]),tonumber(f[base+1])
    if Core.finite(t) and Core.finite(e) and e>=0 then
      S.targets[k]={Core.round(Core.clamp(t,-150,24),2),Core.round(Core.clamp(e,0,60),2)}
    end
  end
  S.alertUpper=f[16]=='1';S.alertLower=f[17]=='1';S.alertPeak=f[18]=='1'
end
local function clear_saved_result(key,raw)
  local id,n=raw:match('^([^;]+);(%d+);'); n=tonumber(n)
  if id and n and n<=2000 then
    for i=1,n do R.SetProjExtState(A.project,SECTION,id..'_'..i,'') end
    R.SetProjExtState(A.project,SECTION,id..'_name','')
  end
  R.SetProjExtState(A.project,SECTION,key,'')
end
local function cleanup_orphaned_saved_chunks()
  if not A.project then return 0 end
  local referenced,keys={},{};local i=0
  while true do
    local ok,key,val=R.EnumProjExtState(A.project,SECTION,i)
    if not ok or ok==0 then break end
    keys[#keys+1]=key
    if key:match('^result@') then
      local id=val:match('^([^;]+);%d+;')
      if id then referenced[id]=true end
    end
    i=i+1
  end
  local removed=0
  for _,key in ipairs(keys) do
    local id=key:match('^([%x]+)_%d+$') or key:match('^([%x]+)_name$')
    if id and #id>=16 and not referenced[id] then
      R.SetProjExtState(A.project,SECTION,key,'');removed=removed+1
    end
  end
  return removed
end
local function enforce_track_cache()
  local tracks={}; local i=0
  while true do
    local ok,key,val=R.EnumProjExtState(A.project,SECTION,i)
    if not ok or ok==0 then break end
    local source=key:match('^result@(.+)$')
    if source and source~='master' and val~='' then
      local stamp=tonumber(val:match('^[^;]+;%d+;([^;]+)$')) or 0
      tracks[#tracks+1]={key=key,raw=val,stamp=stamp,source=source}
    end
    i=i+1
  end
  if #tracks<=TRACK_CACHE_LIMIT then return end
  table.sort(tracks,function(a,b)
    if a.stamp==b.stamp then return a.key<b.key end
    return a.stamp<b.stamp
  end)
  for n=1,#tracks-TRACK_CACHE_LIMIT do clear_saved_result(tracks[n].key,tracks[n].raw) end
end
local function save_data(data)
  local chunks=Core.pack(data);local key='result@'..data.source
  local bytes=0;for _,chunk in ipairs(chunks) do bytes=bytes+#chunk end
  assert(#data.rows<=MAX_HISTORY_ROWS,'保存できる履歴は解析ソースごとに最大3.5時間です。古い履歴を整理してから再試行してください。')
  assert(bytes<=MAX_SAVE_BYTES,'保存データが12 MiBの安全上限を超えました。測定範囲を短くしてください。')
  local _,old=R.GetProjExtState(A.project,SECTION,key)
  local oldid,oldn=old:match('^([^;]+);(%d+);')
  local id=R.genGuid():gsub('[^%w]','')
  local stamp=os.time()+(R.time_precise()%1)
  local written={}
  local ok,why=pcall(function()
    for i,chunk in ipairs(chunks) do
      local chunkKey=id..'_'..i
      assert(R.SetProjExtState(A.project,SECTION,chunkKey,chunk)>0,'カーブを保存できません。')
      written[#written+1]=chunkKey
    end
    local nameKey=id..'_name';R.SetProjExtState(A.project,SECTION,nameKey,data.name or '');written[#written+1]=nameKey
    assert(R.SetProjExtState(A.project,SECTION,key,string.format('%s;%d;%.6f',id,#chunks,stamp))>0,'結果を保存できません。')
  end)
  if not ok then
    for _,writtenKey in ipairs(written) do R.SetProjExtState(A.project,SECTION,writtenKey,'') end
    error(why,0)
  end
  if oldid and tonumber(oldn) and tonumber(oldn)<=2000 then
    for i=1,tonumber(oldn) do R.SetProjExtState(A.project,SECTION,oldid..'_'..i,'') end
    R.SetProjExtState(A.project,SECTION,oldid..'_name','')
  end
  if data.source~='master' then enforce_track_cache() end
  cleanup_orphaned_saved_chunks()
end
local function load_data()
  A.data=nil
  local _,raw=R.GetProjExtState(A.project,SECTION,'result@'..S.source)
  if raw=='' then return end
  local ok,result=pcall(function()
    local id,n,stamp=raw:match('^([^;]+);(%d+);([^;]+)$');n=tonumber(n);stamp=tonumber(stamp)
    assert(id and n and n>=1 and n<=2000 and Core.finite(stamp),'保存情報が不正です。')
    local chunks={}
    for i=1,n do
      local _,v=R.GetProjExtState(A.project,SECTION,id..'_'..i)
      assert(v~='','保存カーブが不足しています。')
      chunks[i]=v
    end
    local data=Core.unpack(chunks)
    data.source=S.source
    local _,name=R.GetProjExtState(A.project,SECTION,id..'_name')
    data.name=name
    Core.recompute(data)
    return data
  end)
  if ok and result then A.data=result;A.stale=true end
end

local function clear_measurement()
  if A.job then return end
  -- Snapshot result keys first because deleting while enumerating would shift indices.
  local results={}; local i=0
  while true do
    local ok,key,val=R.EnumProjExtState(A.project,SECTION,i)
    if not ok or ok==0 then break end
    if key:match('^result@') then results[#results+1]={key,val} end
    i=i+1
  end
  for _,m in ipairs(results) do clear_saved_result(m[1],m[2]) end
  cleanup_orphaned_saved_chunks()
  A.data=nil; A.stale=false
  A.revision=A.revision+1; A.cache=''; A.hover=nil
  A.baseline=R.GetProjectStateChangeCount(A.project)
end

local function source_track()
  if S.source=='master' then return nil,'MASTER OUT · stereo 1/2' end
  for i=0,R.CountTracks(A.project)-1 do
    local tr=R.GetTrack(A.project,i)
    if R.GetTrackGUID(tr)==S.source then local _,name=R.GetTrackName(tr); return tr,name..' · selected via master 1/2' end
  end
  return nil,'指定トラックが見つかりません'
end

local function ensure_track()
  A.track=find_track()
  if A.track then return end
  R.Undo_BeginBlock2(A.project)
  -- Index zero is outside existing folders. No existing routing or folder flags change.
  R.InsertTrackAtIndex(0,false)
  A.track=R.GetTrack(A.project,0)
  R.GetSetMediaTrackInfo_String(A.track,TAG,"display",true)
  R.GetSetMediaTrackInfo_String(A.track,"P_NAME","LOUDNESS TRACE",true)
  R.SetMediaTrackInfo_Value(A.track,"B_MAINSEND",0)
  R.SetMediaTrackInfo_Value(A.track,"B_SHOWINMIXER",0)
  R.SetMediaTrackInfo_Value(A.track,"B_SHOWINTCP",1)
  R.SetMediaTrackInfo_Value(A.track,"I_RECARM",0)
  R.SetMediaTrackInfo_Value(A.track,"I_HEIGHTOVERRIDE",S.height)
  R.SetMediaTrackInfo_Value(A.track,"I_CUSTOMCOLOR",R.ColorToNative(23,67,106)|0x1000000)
  R.TrackList_AdjustWindows(false)
  R.Undo_EndBlock2(A.project,"LOUDNESS TRACE: 表示トラックを作成",1)
end
local function graph_track_is_visible()
  return valid_track() and R.GetMediaTrackInfo_Value(A.track,"B_SHOWINTCP")~=0
end
local function set_graph_track_visible(visible)
  S.visible=visible and true or false
  if S.visible then
    ensure_track()
    if valid_track() then
      R.SetMediaTrackInfo_Value(A.track,"B_SHOWINTCP",1)
      R.SetMediaTrackInfo_Value(A.track,"I_HEIGHTOVERRIDE",S.height)
      R.TrackList_AdjustWindows(false)
      A.cache=""
    end
  else
    unlink()
    if valid_track() then
      R.SetMediaTrackInfo_Value(A.track,"B_SHOWINTCP",0)
      R.TrackList_AdjustWindows(false)
    end
  end
end
local function adopt_project(create)
  unlink(); A.edit=nil; A.project=R.EnumProjects(-1,""); A.track=find_track()
  cleanup_orphaned_saved_chunks();load_settings(); load_data()
  if create then ensure_track() end
  -- The track's TCP visibility is project state, so use it as the authoritative
  -- visibility state when reopening the script.
  if valid_track() then S.visible=graph_track_is_visible() end
  A.revision=A.revision+1; A.baseline=R.GetProjectStateChangeCount(A.project)
end

local function value(v) return not v and '—' or (v<=-149 and '-inf' or string.format('%.1f',v)) end

local function argb(c) return 0xff000000 | (floor(c[1]*255)<<16) | (floor(c[2]*255)<<8) | floor(c[3]*255) end
local function draw_bitmap() return A.drawBitmap or A.bitmap end
local function lrect(x,y,w,h,c,a)
  if w>0 and h>0 then R.JS_LICE_FillRect(draw_bitmap(),floor(x),floor(y),floor(w),floor(h),argb(c),a or 1,"COPY") end
end
local function lline(x,y,x2,y2,c,a)
  R.JS_LICE_Line(draw_bitmap(),x,y,x2,y2,argb(c),a or 1,"COPY",true)
end
local function ltext(s,x,y,w,c)
  R.JS_LICE_SetFontColor(A.font,argb(c or C.muted))
  R.JS_LICE_DrawText(draw_bitmap(),A.font,s,#s,floor(x),floor(y),floor(x+w),floor(y+20))
end
local function chart(width,height,first,last,mx)
  R.JS_LICE_Clear(draw_bitmap(),argb(C.bg))
  local top,bottom=48,height-30
  if bottom-top<18 then ltext('LOUDNESS TRACE - increase track height',12,6,width-24,C.ice); return end
  local function yy(v) return Core.level_y(v,top,bottom,S.lo,S.hi) end
  local function xx(t) return Core.time_x(t,first,last,width) end
  local step=Core.tick_step(last-first,width)
  for t=math.ceil(first/step)*step,last,step do lline(xx(t),top,xx(t),bottom,C.edge,.42) end
  local ticks=Core.axis_ticks(S.lo,S.hi,bottom-top)
  for _,v in ipairs(ticks) do lline(0,yy(v),width,yy(v),C.edge,.6) end
  local colors={s=C.ice,m=C.mint,i=C.purple,rms=C.gold,peak=C.faint}
  local data=A.data
  if data then
   local whole=data
   for _,data in ipairs(whole.segments) do
    local ax,bx=max(0,xx(data.first)),min(width,xx(data.last))
    if bx>ax then
      -- Retained and newly measured ranges use the same visual treatment.
      lrect(ax,top,bx-ax,bottom-top,C.accent,.035)
      for _,key in ipairs({'s','m','i'}) do
        if S.show[key] then
          local target=S.targets[key]
          for _,v in ipairs({target[1]-target[2],target[1]+target[2]}) do
            if v>=S.lo and v<=S.hi then
              for x=ax,bx,14 do lline(x,yy(v),min(bx,x+5),yy(v),colors[key],.23) end
            end
          end
        end
      end
      -- Peak-preserving min/max pyramid limits redraw cost to roughly the pixel width.
      local spp=(last-first)*10/width
      local lev,span=1,1
      while span*2<=spp and span*2<#data.rows do lev=lev+1; span=span*2 end
      for _,key in ipairs(Core.metrics) do
        if S.show[key] then
          local buckets=data.lod[key][lev]
          local from=max(1,floor((first-data.origin)*10/span))
          local to=min(#buckets//2,math.ceil((last-data.origin)*10/span)+1)
          local px,py,pbad
          for i=from,to do
            local bi=(i-1)*2+1;local low,high=buckets[bi],buckets[bi+1]
            if low==false then low=nil end;if high==false then high=nil end
            local time=data.origin+((i-1)*span+min(span,#data.rows-(i-1)*span)*.5+.5)*.1
            local x=xx(time)
            if low and x>=ax and x<=bx then
              local bad
              if key=='peak' then bad=peak_bucket_alert(low,high)
              elseif S.targets[key] then bad=bucket_alert(low,high,S.targets[key])
              else bad=false end
              local y=yy((low+high)*.5); local color=bad and C.red or colors[key]
              local pathColor=(bad or pbad) and C.red or colors[key]
              local pathAlpha=(key=='s' and .98 or .78)
              if px then lline(px,py,x,y,pathColor,pathAlpha) end
              lline(x,yy(low),x,yy(high),color,.85)
              px,py,pbad=x,y,bad
            else px=nil end
          end
        end
      end
    end
   end
  else ltext('Select a time range, then MEASURE.',65,top+24,width-90,C.muted) end
  for _,v in ipairs(ticks) do
    lrect(5,yy(v)-8,35,17,C.bg,.94); ltext(string.format('%.5g',v),8,yy(v)-8,30,C.muted)
  end
  lrect(0,0,width,28,C.panel)
  local measuredName=data and data.name or select(2,source_track())
  ltext('LOUDNESS TRACE  ·  '..tostring(measuredName or 'NO TARGET'),12,5,max(165,width-390),C.ice)
  if width>680 then
    local tags={}
    for _,q in ipairs({{'s','S'},{'m','M'},{'i','I RUN'},{'rms','RMS'},{'peak','PEAK'}}) do if S.show[q[1]] then tags[#tags+1]=q[2] end end
    ltext(table.concat(tags,'  /  '),max(300,width-365),5,180,C.muted)
  end
  if width>370 then ltext(data and (A.stale and 'SAVED / RE-MEASURE' or 'MEASURED') or 'NO MEASUREMENT',width-185,5,180,A.stale and C.gold or C.faint) end
  ltext((S.show.rms or S.show.peak) and 'LUFS / dBFS' or 'LUFS',7,height-20,110,C.faint)
  for t=math.ceil(first/step)*step,last,step do
    local x=xx(t); if x>115 and x<width-64 then ltext(Core.clock(t),x+3,height-20,85,C.faint) end
  end
  local cursor=R.GetCursorPositionEx(A.project)
  if (R.GetPlayStateEx(A.project)&1)==1 then cursor=R.GetPlayPositionEx(A.project) end
  local cx=xx(cursor)
  if cx>=0 and cx<=width then lline(cx,28,cx,height,C.text,.60) end
  A.hover=nil
  if mx and data then
    local t=Core.x_time(mx,first,last,width); local r=Core.row(data,t)
    if r then
      A.hover={time=t,s=r.s,m=r.m,i=r.i,rms=r.rms,peak=r.peak}
      lline(mx,28,mx,bottom,C.text,.4)
      local label=Core.clock(t)..'   S '..value(r.s)..'   M '..value(r.m)..'   I RUN '..value(r.i)..' LUFS'
      local boxw=min(555,width-16); local bx=Core.clamp(mx+14,8,max(8,width-boxw-8))
      lrect(bx,29,boxw,19,C.panel); ltext(label,bx+7,29,boxw-12,C.text)
    end
  end
end

local function overlay(now)
  if not S.visible then unlink(); return end
  if not valid_track() then unlink(); return end
  if R.CountTrackMediaItems(A.track)>0 or R.TrackFX_GetCount(A.track)>0 then
    unlink(); return
  end
  local hwnd=R.JS_Window_FindChildByID(R.GetMainHwnd(),1000)
  if not hwnd then unlink(); return end
  if Platform.mac and A.macCheckedArrange~=hwnd then
    if A.macMetalRetryAt and now<A.macMetalRetryAt then return end
    local mode=R.JS_Window_EnableMetal(hwnd)
    if mode==1 then
      A.macMetalRetryAt=now+1
      if A.macMetalNotice~=hwnd then
        A.macMetalNotice=hwnd
        Language.mb("現在のMetal設定ではグラフを重ね描画できません。REAPERの高度なUI設定でMetalを無効にするか、描画互換モードを選び、必要に応じてREAPERを再起動してください。", "LOUDNESS TRACE",0)
      end
      unlink();return
    end
    A.macCheckedArrange=hwnd;A.macMetalNotice=nil;A.macMetalRetryAt=nil
  end
  if A.arrange~=hwnd then dispose_bitmap(); A.arrange=hwnd end
  configure_composite_delay(hwnd)
  local ok,width,vh=R.JS_Window_GetClientSize(hwnd)
  if not ok or width<100 or vh<30 then unlink(); return end
  local y=floor(R.GetMediaTrackInfo_Value(A.track,"I_TCPY"))
  local height=floor(R.GetMediaTrackInfo_Value(A.track,"I_TCPH"))
  local destY,visible,sourceY=Core.clip_track(y,height,vh)
  if visible<1 or height<1 or R.GetMediaTrackInfo_Value(A.track,"B_SHOWINTCP")==0 then unlink(); return end
  if width>12000 or height>4000 then unlink(); return end
  if A.bw~=width or A.bh~=height or not A.bitmap or not A.backBitmap then
    dispose_bitmap(); A.arrange=hwnd; configure_composite_delay(hwnd)
    A.bitmap=R.JS_LICE_CreateBitmap(true,width,height)
    A.backBitmap=R.JS_LICE_CreateBitmap(true,width,height)
    if not A.bitmap or not A.backBitmap then error("描画用ビットマップを作成できません。") end
    -- The linked front bitmap is never cleared while visible.  All expensive drawing
    -- happens in the hidden back buffer, then one native blit publishes a complete frame.
    R.JS_LICE_Clear(A.bitmap,argb(C.bg))
    R.JS_LICE_Clear(A.backBitmap,argb(C.bg))
    A.bw,A.bh=width,height
  end
  local screenX=R.JS_Window_ClientToScreen(hwnd,0,0)
  local first,last=R.GetSet_ArrangeView2(A.project,false,screenX,screenX+width,0,0)
  if last<=first then unlink(); return end
  local mouseX,mouseY=R.GetMousePosition()
  local clientMouseX,clientMouseY=R.JS_Window_ScreenToClient(hwnd,mouseX,mouseY)
  local hovering=clientMouseX>=0 and clientMouseX<width and clientMouseY>=destY and clientMouseY<destY+visible and R.JS_Window_FromPoint(mouseX,mouseY)==hwnd
  local mx=hovering and floor(clientMouseX) or nil
  local cursor=R.GetCursorPositionEx(A.project)
  if (R.GetPlayStateEx(A.project)&1)==1 then cursor=R.GetPlayPositionEx(A.project) end
  local cursorPixel=floor(Core.time_x(cursor,first,last,width))

  -- REAPER can draw a native vertical guide that follows the *mouse pointer* in the
  -- arrange view.  Lua does not necessarily observe every intermediate pointer position:
  -- during fast motion the sampled X coordinate may jump tens or hundreds of pixels.
  -- Repairing only the previous guide stripe therefore leaves holes at skipped positions.
  --
  -- Keep the non-flickering static composite, but repair the entire swept X range between
  -- the previous and current samples.  A second delayed pass covers REAPER's later erase,
  -- and one final merged sweep is repaired shortly after motion stops.
  local pointerInArrange=clientMouseX>=0 and clientMouseX<width and clientMouseY>=0 and clientMouseY<vh and R.JS_Window_FromPoint(mouseX,mouseY)==hwnd
  local arrangeMouseX=pointerInArrange and floor(clientMouseX) or nil
  local function queue_mouse_repair(x1,x2,delay)
    if x1==nil or x2==nil then return end
    if x2<x1 then x1,x2=x2,x1 end
    local q=A.mouseRepairQueue
    -- A swept range already covers all skipped native-guide positions.  Keep enough
    -- delayed work for very fast motion without allowing an unbounded repaint backlog.
    while #q>=128 do table.remove(q,1) end
    q[#q+1]={due=now+(delay or .030),x1=x1,x2=x2}
  end
  local function extend_mouse_sweep(a,b)
    if b<a then a,b=b,a end
    A.mouseSweepMin=A.mouseSweepMin and min(A.mouseSweepMin,a) or a
    A.mouseSweepMax=A.mouseSweepMax and max(A.mouseSweepMax,b) or b
    A.lastMouseMoveAt=now
  end
  if arrangeMouseX then
    if A.lastArrangeMouseX~=nil and arrangeMouseX~=A.lastArrangeMouseX then
      local a=min(A.lastArrangeMouseX,arrangeMouseX)-7
      local b=max(A.lastArrangeMouseX,arrangeMouseX)+8
      -- Fast first repair plus a delayed pass after REAPER has erased the old guide.
      queue_mouse_repair(a,b,.020)
      queue_mouse_repair(a,b,.075)
      extend_mouse_sweep(a,b)
    end
    A.lastArrangeMouseX=arrangeMouseX
  elseif A.lastArrangeMouseX~=nil then
    local a=A.lastArrangeMouseX-7; local b=A.lastArrangeMouseX+8
    queue_mouse_repair(a,b,.025)
    queue_mouse_repair(a,b,.095)
    extend_mouse_sweep(a,b)
    A.lastArrangeMouseX=nil
  end
  -- After the pointer has been still for a moment, repair the union of the complete
  -- recent path once more.  This catches native guide positions that were drawn between
  -- two Lua defer samples during very fast motion.
  if A.mouseSweepMin and A.lastMouseMoveAt and now-A.lastMouseMoveAt>=.050 then
    local a=A.mouseSweepMin-4
    local b=A.mouseSweepMax+4
    -- Fast pointer motion can make REAPER draw/erase guide positions between Lua defer
    -- samples.  The merged sweep therefore gets several *post-motion* repairs.
    -- These are event-driven rather than periodic, so idle-time flicker does not return.
    queue_mouse_repair(a,b,.005)
    queue_mouse_repair(a,b,.085)
    queue_mouse_repair(a,b,.180)
    queue_mouse_repair(a,b,.320)
    A.mouseSweepMin=nil; A.mouseSweepMax=nil; A.lastMouseMoveAt=nil
  end

  local key=table.concat({width,height,y,visible,first,last,A.revision,tostring(A.stale),mx or -1,cursorPixel},":")
  local redraw=key~=A.cache
  if redraw then
    if now-A.lastPaint<.05 then return end
    A.drawBitmap=A.backBitmap
    chart(width,height,first,last,mx)
    A.drawBitmap=nil
    R.JS_LICE_Blit(A.bitmap,0,0,A.backBitmap,0,0,width,height,1,"COPY")
    A.cache=key; A.lastPaint=now
    -- Keep the composite static unless graph content or geometry changes.
    local code=R.JS_Composite(hwnd,0,destY,width,visible,A.bitmap,0,sourceY,width,visible,true)
    if code~=1 then error("JS_Composite failed: "..tostring(code)) end
    A.linked=true
    if Platform.mac then R.JS_Window_InvalidateRect(hwnd,0,destY,width,destY+visible,false) end
  elseif not A.linked then
    local code=R.JS_Composite(hwnd,0,destY,width,visible,A.bitmap,0,sourceY,width,visible,true)
    if code~=1 then error("JS_Composite failed: "..tostring(code)) end
    A.linked=true
  end

  -- Repair due swept ranges.  Do not assume the queue is sorted: delayed second passes
  -- are interleaved with newer first passes during continuous motion.
  if A.linked and A.mouseRepairQueue and #A.mouseRepairQueue>0 then
    local processed=0
    local i=1
    while i<=#A.mouseRepairQueue and processed<24 do
      local r=A.mouseRepairQueue[i]
      if r.due<=now then
        table.remove(A.mouseRepairQueue,i)
        local x1=max(0,floor(r.x1)); local x2=min(width,math.ceil(r.x2))
        if x2>x1 then R.JS_Window_InvalidateRect(hwnd,x1,destY,x2,destY+visible,false) end
        processed=processed+1
      else
        i=i+1
      end
    end
  end
end

local scale,ox,oy=1,0,0
 BLT.viewport(scale,gfx.ext_retina or 1);local EFFECT_IDLE_TAIL=2.5
local EFFECT_COAST=.70
local effect_activity_until=R.time_precise()+EFFECT_IDLE_TAIL
local redraw_dirty=true
local next_draw_time=0
local last_raw_mouse_x,last_raw_mouse_y,last_raw_mouse_cap=nil,nil,nil
local last_window_w,last_window_h=nil,nil
local last_active_state=nil
local function wake_visuals(now)
  now=now or R.time_precise(); redraw_dirty=true
  effect_activity_until=max(effect_activity_until,now+EFFECT_IDLE_TAIL)
  if next_draw_time==math.huge then next_draw_time=now end
end
local function visual_speed(now)
  local remain=effect_activity_until-(now or R.time_precise())
  if remain<=0 then return 0 end
  if remain>=EFFECT_COAST then return 1 end
  local u=Core.clamp(remain/EFFECT_COAST,0,1)
  return u*u*(3-2*u)
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
  C.accent2=C.ice;C.edge2=C.edge
  A.cache=""
end

function Chameleon.apply(palette)
  C.bg=ccopy(palette.bg)
  C.panel=ccopy(palette.panel)
  C.field=ccopy(palette.field)
  C.edge=ccopy(palette.edge)
  C.text=ccopy(palette.text)
  C.muted=ccopy(palette.muted)
  C.faint=ccopy(palette.faint)
  C.accent=ccopy(palette.accent)
  C.ice=ccopy(palette.accent2)
  C.deep=ccopy(palette.accent3)
  C.mint=ccopy(palette.focus2)
  C.warn=ccopy(palette.warn)
  C.red=ccopy(palette.red)
  C.accent2=C.ice;C.edge2=C.edge
  A.cache=""
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

local function color(c,a) gfx.set(c[1],c[2],c[3],a or 1) end
local function rect(x,y,w,h,c,a) color(c,a); gfx.rect(ox+x*scale,oy+y*scale,w*scale,h*scale,1) end
local function line(x,y,x2,y2,c,a) color(c,a); gfx.line(ox+x*scale,oy+y*scale,ox+x2*scale,oy+y2*scale,1) end
local function disc(x,y,r,c,a) color(c,a); gfx.circle(ox+x*scale,oy+y*scale,r*scale,1,1) end

local function set_font(size,kind,bold) BLT.font(size,kind,bold,scale,Platform.bodyFaces) end
local function measure_text(text,size,kind,bold) set_font(size,kind,bold);local w,h=BLT.metricsFor(Language.message(text));return w/scale,h/scale end
local function text(s,x,y,size,c,w,kind,bold,literal)
  local original=s;s=literal and tostring(s) or Language.message(s)
  set_font(size,kind,bold)
  if s~=original and w then s=BLT.ui.fit(s,w*scale) end
  color(c or C.text); gfx.x,gfx.y=ox+x*scale,oy+y*scale
  gfx.drawstr(s,0,ox+(x+(w or W-x-20))*scale,oy+(y+size+8)*scale)
end

local function inside(x,y,w,h)
  local mx,my=(gfx.mouse_x-ox)/scale,(gfx.mouse_y-oy)/scale
  return mx>=x and mx<x+w and my>=y and my<y+h
end
local function gradient(x,y,w,h,a,b,alpha1,alpha2,vertical)
  if vertical==nil then vertical=true end
  local aa1=alpha1 or 1; local aa2=alpha2==nil and aa1 or alpha2
  local n=max(1,(vertical and h or w)*scale)
  if (a==b or (a[1]==b[1] and a[2]==b[2] and a[3]==b[3])) and aa1==aa2 then rect(x,y,w,h,a,aa1); return end
  if n<=1.01 then rect(x,y,w,h,a,aa1); return end
  local dr,dg,db=(b[1]-a[1])/n,(b[2]-a[2])/n,(b[3]-a[3])/n
  local da=(aa2-aa1)/n
  gfx.gradrect(ox+x*scale,oy+y*scale,w*scale,h*scale,a[1],a[2],a[3],aa1,
    vertical and 0 or dr,vertical and 0 or dg,vertical and 0 or db,vertical and 0 or da,
    vertical and dr or 0,vertical and dg or 0,vertical and db or 0,vertical and da or 0)
end
local function animate(key,target)
 if BLT.presetRevision and BLT.presetMotionSeen[key]~=BLT.presetRevision then
  BLT.presetMotionSeen[key]=BLT.presetRevision;A.motion[key]=target;return target
 end
  local v=A.motion[key] or 0; v=v+(target-v)*min(1,A.dt*12); A.motion[key]=v; return v
end
local widgets={}
local function finish_corners(x,y,w,h,cut,top_left,edge,alpha)
  color(C.bg)
  gfx.triangle(ox+(x+w-cut-1)*scale,oy+(y+h+1)*scale,ox+(x+w+1)*scale,oy+(y+h-cut-1)*scale,ox+(x+w+1)*scale,oy+(y+h+1)*scale)
  if top_left then
    gfx.triangle(ox+(x-1)*scale,oy+(y-1)*scale,ox+(x+cut+1)*scale,oy+(y-1)*scale,ox+(x-1)*scale,oy+(y+cut+1)*scale)
  end
  line(x+w,y+h-cut,x+w-cut,y+h,edge,alpha)
  if top_left then line(x,y+cut,x+cut,y,edge,alpha) end
end
local function button(id,label,x,y,w,h,fn,primary,selected,eyebrow,tone)
  local hover=A.active and inside(x,y,w,h)
  local analyzing=(primary and id=='measure' and A.job~=nil)
  local pulse=analyzing and (.5+.5*sin(A.anim*5.2)) or 0
  local a=animate(id,(hover or analyzing) and 1 or (selected and .50 or 0))
  local shift=A.pressed==id and 1.5 or 0; y=y+shift
  if primary then
    gradient(x,y,w,h,C.deep,C.field,.22+.12*a+(analyzing and .10*pulse or 0),.92)
    if a>.01 then gradient(x,y,w,h,C.accent,C.deep,(analyzing and (.20+.10*pulse) or .13*a),.01,true) end
    if analyzing then
      rect(x-2,y-2,w+4,h+4,C.accent,.030+.025*pulse)
      rect(x-1,y-1,w+2,h+2,C.ice,.018+.022*pulse)
    end
    gradient(x,y,w,analyzing and 2 or 1,C.ice,C.ice,.62+.28*a+(analyzing and .15*pulse or 0),.03)
    line(x,y+h,x+w,y+h,analyzing and C.ice or C.edge,analyzing and (.52+.20*pulse) or .48)
    line(x,y,x,y+h,C.ice,.66+(analyzing and .18*pulse or 0))
    finish_corners(x,y,w,h,10,true,C.ice,.68+(analyzing and .18*pulse or 0))
  else
    local toneColor=tone=='gold' and C.gold or C.accent
    local edgeColor=tone=='gold' and C.gold or C.edge
    gradient(x,y,w,h,C.panel,C.field,.74,.96)
    if selected then
      rect(x+1,y+1,w-2,h-2,toneColor,.055)
      line(x,y,x+w,y,tone=='gold' and C.gold or C.ice,.42+.18*a)
    elseif hover then
      rect(x+1,y+1,w-2,h-2,toneColor,tone=='gold' and (.035+.025*a) or (.045*a))
      line(x,y,x+w,y,tone=='gold' and C.gold or C.ice,.24+.20*a)
    else
      line(x,y,x+w,y,edgeColor,tone=='gold' and .44 or .26)
    end
    line(x,y+h,x+w-6,y+h,edgeColor,tone=='gold' and .42 or .58)
    finish_corners(x,y,w,h,7,false,edgeColor,tone=='gold' and (.40+.16*a) or (.34+.22*a))
  end
  if primary then
    if hover or analyzing then
      A.particleClock=A.particleClock+(analyzing and A.realDt or A.dt)
      local interval=analyzing and .030 or .055
      local cap=analyzing and 66 or 44
      while A.particleClock>=interval and #A.particles<cap do
        A.particleClock=A.particleClock-interval; A.serial=A.serial+1
        local n=A.serial; local h1=(sin(n*12.9898)*43758.5453)%1
        local h2=(sin(n*78.233)*12345.6789)%1
        local px,py
        if analyzing then
          px=x+12+h1*(w-24); py=y+h-7-h2*8
        else
          px=(gfx.mouse_x-ox)/scale+(h1-.5)*7; py=(gfx.mouse_y-oy)/scale+(h2-.5)*5
        end
        A.particles[#A.particles+1]={x=px,y=py,age=0,life=(analyzing and (.65+h1*.65) or (1.6+h1*1.2)),
          vx=(h2-.5)*(analyzing and 15 or 7),vy=(analyzing and (10+h1*14) or (6+h1*8)),phase=h2*pi*2}
      end
    else A.particleClock=min(A.particleClock,.04) end
    for i=#A.particles,1,-1 do
      local p=A.particles[i]; p.age=p.age+A.realDt
      if p.age>=p.life then table.remove(A.particles,i)
      else
        local px=p.x+p.vx*p.age+sin(p.age*1.6+p.phase)*2; local py=p.y-p.vy*p.age
        local e=sin(pi*p.age/p.life)^2
        if px>x+3 and px<x+w-3 and py>y+3 and py<y+h-3 then
          disc(px,py,analyzing and 4.4 or 3.7,C.accent,(analyzing and .035 or .02)*e)
          disc(px,py,analyzing and 2.2 or 1.9,C.ice,(analyzing and .10 or .065)*e)
          disc(px,py,analyzing and .85 or .7,C.ice,(analyzing and .78 or .58)*e)
        end
      end
    end
    if A.collapsed and id=='measure' then
      -- Compact controller: the state line already shows ANALYZING + progress.
      -- Keep the button to one font state so it does not reintroduce the
      -- SETFONT-heavy path that was previously optimized out.
      local tw,th=measure_text(label,12.5,1,true)
      text(label,x+(w-tw)/2,y+(h-th)/2,12.5,C.text,tw+2,1,true)
    else
      local small=analyzing and 'ANALYZING' or (eyebrow or 'MEASURE')
      local sw=measure_text(small,8,2,false)
      text(small,x+(w-sw)/2,y+3,8,C.ice,w,2)
      local tw=measure_text(label,15,1,false)
      text(label,x+max(10,(w-tw)/2),y+17,15,C.text,w-20)
    end

    if id=='measure' and A.analysisBurst then
      local b=A.analysisBurst
      b.age=b.age+A.realDt
      local u=min(1,b.age/b.life)
      local flash=(1-u)^2
      local expand=3+18*u
      if flash>.001 then
        line(b.x-expand,b.y-expand,b.x+b.w+expand,b.y-expand,C.ice,.42*flash)
        line(b.x-expand,b.y+b.h+expand,b.x+b.w+expand,b.y+b.h+expand,C.accent,.30*flash)
        rect(b.x-expand*.35,b.y-expand*.22,b.w+expand*.7,b.h+expand*.44,C.ice,.028*flash)
      end
      for i=#A.analysisBurstParticles,1,-1 do
        local p=A.analysisBurstParticles[i]
        p.age=p.age+A.realDt
        if p.age>=p.life then table.remove(A.analysisBurstParticles,i)
        else
          local q=p.age/p.life
          local px=p.x+p.vx*p.age+sin(p.phase+p.age*7)*1.2
          local py=p.y+p.vy*p.age
          local e=(1-q)^2
          disc(px,py,3.6,C.accent,.035*e)
          disc(px,py,1.7,C.ice,.12*e)
          disc(px,py,.7,C.ice,.82*e)
        end
      end
      if b.age>=b.life and #A.analysisBurstParticles==0 then A.analysisBurst=nil end
    end
  else
    local tw=measure_text(label,13,1,false)
    local inset=w<60 and 4 or 8
    text(label,x+max(inset,(w-tw)/2),y+(h-13)/2-1,13,selected and C.text or C.muted,w-inset*2)
  end
  widgets[#widgets+1]={id=id,x=x,y=y-shift,w=w,h=h,fn=fn}
end

local function source_selector(name,x,y,w,h,fn)
  local id='source'
  local hover=A.active and inside(x,y,w,h)
  local a=animate('source_selector',hover and 1 or .32)
  local shift=A.pressed==id and 1.5 or 0;y=y+shift
  gradient(x,y,w,h,C.deep,C.field,.56+.10*a,.98)
  rect(x+2,y+2,w-4,h-4,C.accent,.035+.025*a)
  line(x+10,y,x+w-12,y,C.ice,.58+.22*a)
  line(x+12,y+h,x+w-10,y+h,C.edge,.82)
  finish_corners(x,y,w,h,10,true,C.ice,.52+.18*a)
  local cy=y+h*.5
  rect(x+15,cy-10,3,20,C.ice,.72)
  rect(x+21,cy-6,3,12,C.accent,.66)
  line(x+24,cy,x+34,cy,C.ice,.48)
  line(x+31,cy-4,x+35,cy,C.ice,.48);line(x+31,cy+4,x+35,cy,C.ice,.48)
  text('解析ソース',x+45,y+(h-15)/2-1,15,C.ice,92,1,true)
  text(name,x+140,y+(h-16)/2-1,16,C.text,w-188,1,true,true)
  text('CHANGE',x+w-57,y+(h-8)/2-1,8,C.faint,48,2,true)
  widgets[#widgets+1]={id=id,x=x,y=y-shift,w=w,h=h,fn=fn}
end

local function temp_file_exists(path)
  if type(path)~='string' or path=='' then return false end
  if type(R.file_exists)=='function' then return R.file_exists(path) end
  local file=io.open(path,'rb');if file then file:close();return true end
  return false
end
local function remove_temp_file(path)
  if not temp_file_exists(path) then return true end
  local ok,result=pcall(os.remove,path)
  return ok and result and true or false
end
local TEMP_DELETE_QUEUE_LIMIT=128
local function queue_temp_delete(path)
  if not temp_file_exists(path) or A.tempDeletePending[path] then return end
  local count,oldest_path,oldest_time=0,nil,math.huge
  for pending_path,queued_at in pairs(A.tempDeletePending) do
    count=count+1;queued_at=type(queued_at)=='number' and queued_at or 0
    if queued_at<oldest_time then oldest_path,oldest_time=pending_path,queued_at end
  end
  if count>=TEMP_DELETE_QUEUE_LIMIT and oldest_path then A.tempDeletePending[oldest_path]=nil end
  A.tempDeletePending[path]=R.time_precise()
end
local function retry_temp_deletes(force)
  local now=R.time_precise()
  if not force and now<(A.tempDeleteRetryAt or 0) then return end
  A.tempDeleteRetryAt=now+5
  for path in pairs(A.tempDeletePending or {}) do
    if remove_temp_file(path) then A.tempDeletePending[path]=nil end
  end
end
local function prefix_temp_files(directory,prefix)
  local files={};local i=0
  while true do
    local name=R.EnumerateFiles(directory,i);if not name then break end
    if name:sub(1,#prefix)==prefix and not name:find('[/\\]') then files[#files+1]=directory..'/'..name end
    i=i+1
  end
  return files
end
local function clean_temp(job)
  if not job then return end
  if job.file then pcall(function() job.file:close() end);job.file=nil end
  local paths,seen={},{}
  local function add(path) if path and path~='' and not seen[path] then seen[path]=true;paths[#paths+1]=path end end
  add(job.path)
  -- Only files bearing this job's unique GUID; never remove the temp directory.
  if job.dir and job.prefix then for _,path in ipairs(prefix_temp_files(job.dir,job.prefix)) do add(path) end end
  for _,path in ipairs(paths) do if not remove_temp_file(path) then queue_temp_delete(path) end end
  retry_temp_deletes(true)
end
local function human_bytes(bytes)
  if bytes>=1024^3 then return string.format('%.2f GiB',bytes/1024^3) end
  return string.format('%.0f MiB',bytes/1024^2)
end
local function recover_stale_temp_files(directory)
  local files={};local bytes=0;local i=0
  while true do
    local name=R.EnumerateFiles(directory,i);if not name then break end
    if name:match('^LoudnessTrace_[%w]+') and not name:find('[/\\]') then
      local path=directory..'/'..name;files[#files+1]=path
      local file=io.open(path,'rb')
      if file then local size=file:seek('end');file:close();if type(size)=='number' then bytes=bytes+size end end
    end
    i=i+1
  end
  if #files==0 then return end
  local message=string.format('前回の解析で残った可能性がある一時ファイルを%d件検出しました（合計 %s）。\n\n削除してよろしいですか？\n別のLOUDNESS TRACEが現在解析中の場合だけキャンセルしてください。',#files,human_bytes(bytes))
  if Language.mb(message,'LOUDNESS TRACE | 一時ファイル回収',1)==1 then
    for _,path in ipairs(files) do if not remove_temp_file(path) then queue_temp_delete(path) end end
    retry_temp_deletes(true)
  end
end
local function trigger_analysis_finish_burst()
  local x,y,w,h
  if A.collapsed then
    x,y,w,h=COMPACT_MEASURE_X,COMPACT_MEASURE_Y,COMPACT_MEASURE_W,COMPACT_MEASURE_H
  else
    x,y,w,h=250,550,276,42
  end
  A.analysisBurst={age=0,life=.82,x=x,y=y,w=w,h=h}
  A.analysisBurstParticles={}
  for i=1,34 do
    A.analysisButtonSerial=A.analysisButtonSerial+1
    local n=A.analysisButtonSerial
    local r1=(sin(n*12.9898)*43758.5453)%1
    local r2=(sin(n*78.233)*12345.6789)%1
    local side=i%4
    local px,py
    if side==0 then px=x+r1*w; py=y+2
    elseif side==1 then px=x+w-2; py=y+r1*h
    elseif side==2 then px=x+r1*w; py=y+h-2
    else px=x+2; py=y+r1*h end
    local cx,cy=x+w*.5,y+h*.5
    local dx,dy=px-cx,py-cy
    local len=max(1,math.sqrt(dx*dx+dy*dy))
    local speed=28+r2*62
    A.analysisBurstParticles[#A.analysisBurstParticles+1]={
      x=px,y=py,vx=dx/len*speed+(r2-.5)*16,vy=dy/len*speed+(r1-.5)*16,
      age=0,life=.42+r1*.48,phase=r2*pi*2
    }
  end
end

local function cancel_job()
  if not A.job then return end
  local job=A.job; A.job=nil; clean_temp(job)
end
local function measure()
  if A.job then return end
  if R.GetPlayStateEx(A.project)~=0 then return end
  if math.abs(R.Master_GetPlayRate(A.project)-1)>.000001 then return end
  local first,last=R.GetSet_LoopTimeRange2(A.project,false,false,0,0,false)
  if last-first<.4 then return end
  if last-first>12600 then return end
  local source,name=source_track()
  if S.source~='master' and not source then return end
  if source and source==A.track then return end
  local duration=last-first
  if duration>TEMP_WARNING_SECONDS then
    local estimate=duration*TEMP_BYTES_PER_SECOND
    local message=string.format('長い範囲を解析するため、一時WAVを約 %s 作成します。\n解析中は同程度の空き容量が必要です。続行しますか？\n\n範囲：%.1f分',human_bytes(estimate),duration/60)
    if Language.mb(message,'LOUDNESS TRACE | 長尺解析',1)~=1 then return end
  end
  set_graph_track_visible(true)
  local job={project=A.project,first=first,last=last,source=S.source,name=name,progress=0,phase='prepare'}
  A.job=job
  job.co=coroutine.create(function()
    -- Let the controller paint before opening REAPER's synchronous render window.
    coroutine.yield()
    assert(R.EnumProjects(-1,'')==job.project,'測定開始前にプロジェクトが切り替わりました。')
    if source then assert(R.ValidatePtr2(job.project,source,'MediaTrack*'),'測定元トラックが削除されました。') end
    local current_first,current_last=R.GetSet_LoopTimeRange2(job.project,false,false,0,0,false)
    assert(math.abs(current_first-first)<=1e-9 and math.abs(current_last-last)<=1e-9,'測定開始前に時間選択が変更されました。')
    local base=Platform.tempDirectory()
    job.dir=base:gsub('[/\\]+$','')
    job.prefix='LoudnessTrace_'..R.genGuid():gsub('[^%w]','')
    job.phase='render'
    job.path=Core.render(R,job.project,source,first,last,job.dir,job.prefix)
    job.renderState=R.GetProjectStateChangeCount(job.project)
    job.file=assert(io.open(job.path,'rb'),'レンダーがキャンセルされたか、一時音声を開けません。')
    job.phase='analyze'
    local deadline=R.time_precise()+.008
    local function tick(p)
      job.progress=p
      if R.time_precise()>=deadline then coroutine.yield(); deadline=R.time_precise()+.008 end
    end
    local data=Core.analyze(job.file,last-first,tick)
    data.first,data.last,data.source,data.name=first,last,job.source,name
    job.file:close(); job.file=nil
    -- Audio analysis no longer needs the rendered WAV. Delete the GUID-scoped temp
    -- files immediately; normal completion/error/close cleanup retries harmlessly.
    clean_temp(job)
    data=Core.replace_range(A.data,data)
    job.prunedRows=Core.trim_history(data,MAX_HISTORY_ROWS)
    Core.recompute(data,tick)
    job.result=data; job.progress=1
  end)
end
local function step_job()
  local job=A.job
  if not job then return end
  local ok,err=coroutine.resume(job.co)
  if not ok then
    clean_temp(job); A.job=nil
    Language.mb(public_error(err),'LOUDNESS TRACE | 解析',0); return
  end
  if coroutine.status(job.co)=='dead' then
    clean_temp(job); A.job=nil
    if R.EnumProjects(-1,'')~=job.project then return end
    trigger_analysis_finish_burst()
    local changed=R.GetProjectStateChangeCount(A.project)~=job.renderState
    local saved,why=pcall(save_data,job.result)
    A.data=job.result
    collectgarbage('step',800)
    A.stale=changed; A.revision=A.revision+1; A.baseline=R.GetProjectStateChangeCount(A.project)
    if not saved then Language.mb(public_error(why),'LOUDNESS TRACE | 保存',0) end
  end
end
local function choose_source()
  if A.job then return end
  gfx.x,gfx.y=gfx.mouse_x,gfx.mouse_y
  local menu=(S.source=='master' and '!' or '')..'MASTER OUT 1/2|選択中のトラック / バスを指定'
  local n=gfx.showmenu(Language.menu(menu))
  if n==1 then S.source='master'
  elseif n==2 then
    if R.CountSelectedTracks(A.project)~=1 then return end
    local tr=R.GetSelectedTrack(A.project,0)
    if tr==A.track then return end
    S.source=R.GetTrackGUID(tr)
  else return end
  save_settings();load_data();A.revision=A.revision+1;A.cache=''
end

local function icon(x,y)
  local analyzing=A.job~=nil
  local points=Core.loudness_line(A.anim)
  local cy=y+26

  local fx,fy,fw,fh=x-5,y+4,86,44
  local corner=8
  line(fx,fy,fx+corner,fy,C.ice,.26)
  line(fx,fy,fx,fy+corner,C.ice,.22)
  line(fx+fw-corner,fy,fx+fw,fy,C.ice,.26)
  line(fx+fw,fy,fx+fw,fy+corner,C.ice,.22)
  line(fx,fy+fh-corner,fx,fy+fh,C.edge,.24)
  line(fx,fy+fh,fx+corner,fy+fh,C.edge,.26)
  line(fx+fw,fy+fh-corner,fx+fw,fy+fh,C.edge,.24)
  line(fx+fw-corner,fy+fh,fx+fw,fy+fh,C.edge,.26)

  for _,dy in ipairs({11,22,33}) do
    local a=dy==22 and .24 or .14
    line(fx+1,fy+dy,fx+4,fy+dy,C.ice,a)
    line(fx+fw-4,fy+dy,fx+fw-1,fy+dy,C.ice,a)
  end

  disc(fx+8,fy+7,1.25,C.accent,.22)
  disc(fx+8,fy+7,.55,C.ice,.68)
  disc(fx+14,fy+7,.85,C.ice,.24)

  local activity=analyzing and (.78+.22*sin(A.anim*5.6)^2) or 1
  line(x,cy,x+76,cy,C.edge,analyzing and .30 or .20)
  for i=2,#points do
    local a,b=points[i-1],points[i]
    local alpha=min(a.a,b.a)
    local x1,y1=x+a.x,cy-a.y
    local x2,y2=x+b.x,cy-b.y
    if analyzing then
      line(x1,y1+1,x2,y2+1,C.accent,.12*alpha*activity)
      line(x1,y1-2,x2,y2-2,C.accent,.10*alpha*activity)
    end
    line(x1,y1,x2,y2,C.accent,(analyzing and .25 or .16)*alpha*activity)
    line(x1,y1-1,x2,y2-1,C.accent,(analyzing and .14 or .08)*alpha*activity)
    line(x1,y1,x2,y2,C.ice,(analyzing and .96 or .80)*alpha)
  end

  A.iconClock=A.iconClock+A.dt
  local emitEvery=analyzing and .065 or .16
  local particleLimit=analyzing and 36 or 20
  while A.iconClock>=emitEvery and #A.iconParticles<particleLimit and #points>4 do
    A.iconClock=A.iconClock-emitEvery
    A.iconSerial=A.iconSerial+1
    local n=A.iconSerial
    local h1=(sin(n*12.9898)*43758.5453)%1
    local h2=(sin(n*78.233)*12345.6789)%1
    local first=3
    local last=#points-2
    local pick=points[first+floor(h1*(last-first+1))]
    if pick and pick.a>.45 then
      A.iconParticles[#A.iconParticles+1]={
        x=x+pick.x,y=cy-pick.y,age=0,life=(analyzing and .65 or .8)+h2*(analyzing and .70 or .75),
        vx=(analyzing and -3.5 or -2)-h1*(analyzing and 5 or 3),
        vy=(analyzing and -5.5 or -3.5)-h2*(analyzing and 8 or 5.5),phase=h1*pi*2,
        hot=analyzing
      }
    end
  end
  for i=#A.iconParticles,1,-1 do
    local p=A.iconParticles[i]
    p.age=p.age+A.realDt
    if p.age>=p.life then
      table.remove(A.iconParticles,i)
    else
      local e=sin(pi*p.age/p.life)^2
      local px=p.x+p.vx*p.age+sin(p.phase+p.age*1.8)*.65
      local py=p.y+p.vy*p.age
      if px>=x and px<=x+76 and py>=y and py<=y+52 then
        local hot=p.hot
        disc(px,py,hot and 3.3 or 2.6,C.accent,(hot and .038 or .022)*e)
        disc(px,py,hot and 1.5 or 1.2,C.ice,(hot and .16 or .10)*e)
        disc(px,py,hot and .58 or .48,C.ice,(hot and .86 or .70)*e)
      end
    end
  end
end
local function change_height(h)
  S.height=h
  if valid_track() then
    R.SetMediaTrackInfo_Value(A.track,"I_HEIGHTOVERRIDE",h); R.TrackList_AdjustWindows(false)
  end
  A.cache=""
end
local function edited()
  A.revision=A.revision+1;save_settings()
end
function A.flash_field(id) A.fieldFlash[id]=R.time_precise() end
function A.field_flash_value(id)
  local t=A.fieldFlash[id];if not t then return 0 end
  local age=R.time_precise()-t
  if age>=1.15 then A.fieldFlash[id]=nil;return 0 end
  local q=Core.clamp(age/1.15,0,1);return 1-q*q*(3-2*q)
end
function A.apply_number_field(field,raw,save)
  if not field or not Core.finite(raw) then return false end
  local value,clipped=raw,false
  if field.normalize then value,clipped=field.normalize(raw) end
  if not Core.finite(value) then return false end
  local rounded=Core.round(value,field.digits or 2)
  clipped=clipped or math.abs(rounded-raw)>1e-12;value=rounded
  local old=field.get and field.get() or nil
  if old==nil or math.abs(value-old)>1e-12 then
    if not field.set(value) then return false end
    if save then edited() end
  end
  if clipped then A.flash_field(field.id) end
  return true
end
function A.update_field_drag(py,fine)
  local d=A.fieldDrag;if not d then return end
  local dy=d.startY-py
  if not d.moved and math.abs(dy)<3 then return end
  d.moved=true;A.edit=nil
  fine=fine and (d.field.step or 1)<1
  local inc=(d.field.step or 1)*(fine and .1 or 1)
  local pixels=fine and 8 or 3
  local q=dy/pixels;local ticks=(q<0 and -1 or 1)*floor(math.abs(q)+.5)
  local raw=d.startValue+ticks*inc
  local value,clipped=raw,false
  if d.field.normalize then value,clipped=d.field.normalize(raw) end
  value=Core.round(value,d.field.digits or 2);clipped=clipped or math.abs(value-raw)>1e-12
  if clipped and not d.clipped then A.flash_field(d.field.id);d.clipped=true elseif not clipped then d.clipped=false end
  if Core.finite(value) and math.abs(value-d.field.get())>1e-12 and d.field.set(value) then edited() end
end
local function commit_edit(cancel)
  local e=A.edit
  if not e then return true end
  if cancel then A.edit=nil;return true end
  local raw=tonumber(e.buffer)
  if not Core.finite(raw) then A.flash_field(e.id);A.edit=nil;return true end
  local field={id=e.id,get=e.get,set=e.set,normalize=e.normalize,digits=e.digits}
  if not A.apply_number_field(field,raw,true) then return false end
  A.edit=nil;return true
end
local function edit_key(k)
 k=BLT.key(k);if k==0 then return end

  local e=A.edit;if not e then return false end
  if k==13 then commit_edit();return true end
  if k==27 then commit_edit(true);return true end
  if k==1 then e.all=true;return true end
  if k==8 then
    if e.all then e.buffer='';e.cursor=0
    elseif e.cursor>0 then e.buffer=e.buffer:sub(1,e.cursor-1)..e.buffer:sub(e.cursor+1);e.cursor=e.cursor-1 end
    e.all=false;return true
  end
  if k==6579564 then
    if e.all then e.buffer='';e.cursor=0 else e.buffer=e.buffer:sub(1,e.cursor)..e.buffer:sub(e.cursor+2) end
    e.all=false;return true
  end
  if k==1818584692 then e.cursor=max(0,e.cursor-1);e.all=false;return true end
  if k==1919379572 then e.cursor=min(#e.buffer,e.cursor+1);e.all=false;return true end
  if k==1752132965 then e.cursor=0;e.all=false;return true end
  if k==6647396 then e.cursor=#e.buffer;e.all=false;return true end
  if k>=32 and k<=127 then
    local char=string.char(k)
    if char:match('[%d%.%+%-eE]') then
      if e.all then e.buffer='';e.cursor=0;e.all=false end
      if #e.buffer<24 then e.buffer=e.buffer:sub(1,e.cursor)..char..e.buffer:sub(e.cursor+1);e.cursor=e.cursor+1 end
    end
    return true
  end
  return k~=0
end
local function number_text(value,digits)
  digits=digits or 2
  local text=string.format('%.'..digits..'f',Core.round(value,digits))
  return digits>0 and text:gsub('0+$',''):gsub('%.$','') or text
end
local function number_field(id,label,x,y,w,get,set,step,h,normalize,digits)
  h=h or 28
  local hover=A.active and inside(x,y,w,h);local e=A.edit and A.edit.id==id and A.edit or nil
  local flash=A.field_flash_value(id)
  rect(x,y,w,h,C.field)
  if flash>0 then rect(x-4,y-4,w+8,h+8,C.red,.025*flash);rect(x,y,w,h,C.red,.10*flash) end
  line(x,y+h,x+w,y+h,flash>0 and C.red or (e and C.ice or C.edge),max(hover and .95 or .65,.55+.40*flash))
  local labelY=y+(h-16)/2
  local valueY=y+(h-20)/2
  text(label,x+5,labelY,11,C.faint,30)
  local shown=e and e.buffer or number_text(get(),digits)
  if e and e.all then rect(x+34,y+4,w-39,h-8,C.accent,.3) end
  text(shown,x+35,valueY,14,C.text,w-39,2)
  if e and not e.all then
    local tw=measure_text(e.buffer:sub(1,e.cursor),14,2,false)
    if tw<w-40 then line(x+35+tw,y+6,x+35+tw,y+h-6,C.ice,.8) end
  end
  local field={id=id,x=x,y=y,w=w,h=h,get=get,set=set,step=step or 1,normalize=normalize,digits=digits or 2,field=true}
  field.fn=function() local str=number_text(get(),digits);A.edit={id=id,buffer=str,cursor=#str,all=true,get=get,set=set,normalize=normalize,digits=digits or 2} end
  widgets[#widgets+1]=field
end
local function target_fields(key,x,y,w)
  local half=(w-6)/2
  number_field('goal_'..key,'目標',x,y,half,function() return S.targets[key][1] end,function(v) S.targets[key][1]=v;return true end,1,nil,
    function(v) local n=Core.clamp(v,-150,24);return n,n~=v end,2)
  number_field('tol_'..key,'±LU',x+half+6,y,half,function() return S.targets[key][2] end,function(v) S.targets[key][2]=v;return true end,1,nil,
    function(v) local n=Core.clamp(v,0,60);return n,n~=v end,2)
end
local function toggle(key,label,x,y,w,h)
  local on=S.show[key]
  button('toggle_'..key,label,x,y,w,h,function()
    local nextState=not S.show[key]
    S.show[key]=nextState
    if nextState and not graph_track_is_visible() then set_graph_track_visible(true) end
    edited()
  end,false,on)
  if on then
    rect(x+1,y+3,9,h-6,C.accent,.075)
    rect(x+2,y+4,4,h-8,C.ice,.90)
    rect(x+6,y+6,2,h-12,C.accent,.28)
    line(x+2,y+3,x+2,y+h-3,C.ice,.34)
  else
    rect(x+1,y+1,w-2,h-2,{.18,.22,.28},.13)
  end
end
local function option_switch(id,labelTop,labelBottom,x,y,w,checked,fn)
 local hot=A.active and inside(x,y,w,38)
 BLT.switch(x,y+7,animate('option_state_'..id,checked and 1 or 0),true)
 local c=hot and C.text or C.muted
 text(labelTop,x+34,y+1,12.8,c,w-34,nil,true);text(labelBottom,x+34,y+17,12.8,c,w-34,nil,true)
 widgets[#widgets+1]={id=id,x=x,y=y,w=w,h=38,fn=fn}
end
local function auto_axis_range()
  local data=A.data
  if not data then return end
  local values={}
  local function push(v)
    if Core.finite(v) and v>-120 and v<24 then values[#values+1]=v end
  end
  local enabled={}
  for _,k in ipairs({'s','m','i','rms','peak'}) do if S.show[k] then enabled[#enabled+1]=k end end
  for _,seg in ipairs(data.segments) do
    local duration=seg.last-seg.first
    -- Ignore the unstable opening portion. For long ranges allow up to 3 s to
    -- settle; for short ranges preserve enough data to still derive a range.
    local settle=min(3.0,max(.5,duration*.16))
    local stableStart=seg.first+settle
    local added=0
    for _,r in ipairs(seg.rows) do
      if r.time>=stableStart then
        for _,k in ipairs(enabled) do
          local n=#values; push(r[k]); if #values>n then added=added+1 end
        end
      end
    end
    -- Very short measurements may have no post-settle values; fall back to all
    -- finite non-silence values rather than treating -inf as a graph boundary.
    if added==0 then
      for _,r in ipairs(seg.rows) do
        for _,k in ipairs(enabled) do push(r[k]) end
      end
    end
  end
  if #values==0 then return end
  table.sort(values)
  local function percentile(p)
    if #values==1 then return values[1] end
    local pos=1+(#values-1)*p
    local i=floor(pos); local f=pos-i
    return values[i]+((values[min(#values,i+1)]-values[i])*f)
  end
  local lo=#values>=12 and percentile(.02) or values[1]
  local hi=#values>=12 and percentile(.98) or values[#values]
  if hi-lo<4 then local mid=(hi+lo)*.5;lo,hi=mid-2,mid+2 end
  local pad=max(2,(hi-lo)*.09)
  lo=floor((lo-pad)/2)*2
  hi=math.ceil((hi+pad)/2)*2
  if hi-lo<12 then local mid=(hi+lo)*.5;lo=floor((mid-6)/2)*2;hi=math.ceil((mid+6)/2)*2 end
  S.lo=Core.clamp(lo,-120,18); S.hi=Core.clamp(hi,S.lo+2,24)
  edited(); A.cache=''
end

local function inputs_mouse()
 if BLT.blocked() then A.down=(gfx.mouse_cap&1)~=0;A.pressed=nil;gfx.mouse_wheel=0;return end

  if A.titleMouseActive or A.windowTransition then
    A.pressed=nil;A.fieldDrag=nil;A.down=(gfx.mouse_cap&1)==1
    return
  end
  local hovered
  for _,b in ipairs(widgets) do if inside(b.x,b.y,b.w,b.h) then hovered=b end end
  local wheel=gfx.mouse_wheel or 0
  local delta=wheel-(A.lastWheel or 0);A.lastWheel=wheel
  if delta~=0 and hovered and hovered.field and A.active and commit_edit() then
    local multiplier=(gfx.mouse_cap&8)~=0 and hovered.step<1 and .1 or ((gfx.mouse_cap&4)~=0 and 10 or 1)
    local notches=max(1,floor(math.abs(delta)/120+.5));local direction=delta>0 and 1 or -1
    A.apply_number_field(hovered,hovered.get()+direction*notches*hovered.step*multiplier,true)
  end
  local down=(gfx.mouse_cap&1)==1
  if down and not A.down then
    if commit_edit() then
      A.pressed=hovered and hovered.id or nil
      if hovered and hovered.field then A.fieldDrag={field=hovered,startY=(gfx.mouse_y-oy)/scale,startValue=hovered.get(),moved=false,clipped=false} end
    else A.pressed=nil end
  elseif down and A.fieldDrag then
    A.update_field_drag((gfx.mouse_y-oy)/scale,(gfx.mouse_cap&8)~=0)
  elseif not down and A.down then
    local wasDrag=A.fieldDrag and A.fieldDrag.moved
    A.fieldDrag=nil
    if not wasDrag and hovered and hovered.id==A.pressed then hovered.fn() end
    A.pressed=nil
  end
  A.down=down
end

local function gfx_window_handle()
  if A.gfxWindow and R.JS_Window_IsWindow(A.gfxWindow) then return A.gfxWindow end
  A.gfxWindow=R.JS_Window_Find("LOUDNESS TRACE",true)
  return A.gfxWindow
end

local function reset_window_size()
  if A.collapsed or A.windowTransition then return end
  local hwnd=gfx_window_handle()
  if not hwnd then return end
  local ok,l,t=WindowGeometry.JS_Window_GetRect(hwnd)
  if ok then BLT.position(hwnd,l,t,W,H+A.titleH,'','') end
end

-- The POPUP style removes Windows' native resize frame together with the caption.
-- Re-create a thin resize hit area inside the client rectangle so the custom
-- title bar keeps its clean look. Bottom corners and straight edges remain draggable;
-- upper corners stay reserved for title-bar controls.
local function resize_hit(mx,my)
  if A.collapsed or A.windowTransition then return nil end
  local w,h=gfx.w,gfx.h
  if not w or not h or w<=0 or h<=0 then return nil end
  if mx<0 or mx>=w or my<0 or my>=h then return nil end
  local edge=A.resizeEdge; local band=A.resizeCornerBand; local span=A.resizeCornerSpan
  local bottomBand=my>=h-band; local bottomSpan=my>=h-span
  local leftBand=mx<band; local rightBand=mx>=w-band
  local leftSpan=mx<span; local rightSpan=mx>=w-span
  if (bottomBand and leftSpan) or (leftBand and bottomSpan) then return 'lb' end
  if (bottomBand and rightSpan) or (rightBand and bottomSpan) then return 'rb' end
  if my<A.titleH then
    if mx<A.resizeTopLeftGuard or mx>=w-A.resizeTopRightGuard then return nil end
  end
  local nearL=mx<edge; local nearR=mx>=w-edge; local nearT=my<edge; local nearB=my>=h-edge
  if nearL then return 'l' end
  if nearR then return 'r' end
  if nearT then return 't' end
  if nearB then return 'b' end
  return nil
end
-- Match Windows' native resize feedback even though the standard frame is hidden.
-- Cursor IDs are the standard Windows IDC resize cursors loaded through js_ReaScriptAPI.
local function resize_cursor_kind(mode)
  if not mode then return nil end
  if mode=='l' or mode=='r' then return 'we' end
  if mode=='t' or mode=='b' then return 'ns' end
  if mode=='lt' or mode=='rb' then return 'nwse' end
  if mode=='rt' or mode=='lb' then return 'nesw' end
  return nil
end
local function set_resize_cursor(mode)
  local kind=resize_cursor_kind(mode)
  if kind then
    local cursor=A.resizeCursors[kind]
    if not cursor then
      cursor=R.JS_Mouse_LoadCursor(A.resizeCursorId[kind])
      A.resizeCursors[kind]=cursor
    end
    if cursor then R.JS_Mouse_SetCursor(cursor) end
    A.resizeCursorMode=kind
  elseif A.resizeCursorMode then
    local cursor=A.resizeCursors.arrow
    if not cursor then
      cursor=R.JS_Mouse_LoadCursor(A.resizeCursorId.arrow)
      A.resizeCursors.arrow=cursor
    end
    if cursor then R.JS_Mouse_SetCursor(cursor) end
    A.resizeCursorMode=nil
  end
end

local function begin_resize(mode)
  local hwnd=gfx_window_handle()
  if not hwnd or not mode then return false end
  local ok,l,t,r,b=WindowGeometry.JS_Window_GetRect(hwnd)
  if not ok then return false end
  local sx,sy=WindowGeometry.GetMousePosition()
  A.resizeDrag={mode=mode,mouseX=sx,mouseY=sy,left=l,top=t,right=r,bottom=b}
  A.titleDrag=nil
  A.pressed=nil
  return true
end
local function update_resize()
  local d=A.resizeDrag
  if not d then return end
  local hwnd=gfx_window_handle()
  if not hwnd then A.resizeDrag=nil; return end
  local sx,sy=WindowGeometry.GetMousePosition()
  local dx,dy=sx-d.mouseX,sy-d.mouseY
  local l,t,r,b=d.left,d.top,d.right,d.bottom
  if d.mode:find('l',1,true) then l=min(d.left+dx,r-A.minWindowW) end
  if d.mode:find('r',1,true) then r=max(d.right+dx,l+A.minWindowW) end
  if d.mode:find('t',1,true) then t=min(d.top+dy,b-A.minWindowH) end
  if d.mode:find('b',1,true) then b=max(d.bottom+dy,t+A.minWindowH) end
  BLT.position(hwnd,floor(l+.5),floor(t+.5),max(A.minWindowW,floor(r-l+.5)),max(A.minWindowH,floor(b-t+.5)),'','')
end

local LOUDNESS_TOOLTIPS={
  close="閉じる",
  reset="ウィンドウサイズ初期化",
  chameleon="カメレオンモード（配色をテーマへ擬態）",
  fold="折りたたむ",
}

local function clear_loudness_tooltip() BLT.clearTooltip() end

local function custom_titlebar() BLT.bar() end

local function fold_control(id,x,y,w,h,upward,fn)
  local hover=A.active and inside(x,y,w,h)
  local glow=animate('fold_hover_'..id,hover and 1 or 0)
  rect(x,y,w,h,C.field,.88)
  rect(x+1,y+1,w-2,h-2,C.accent,.018+.035*glow)
  line(x,y,x+w,y,C.ice,.18+.24*glow)
  line(x,y+h,x+w-5,y+h,C.edge,.34+.16*glow)
  finish_corners(x,y,w,h,5,false,C.edge,.34+.18*glow)

  A.foldAnim=(A.foldAnim or 0)+A.dt
  local period=hover and 1.30 or 1.65
  local p=(A.foldAnim%period)/period
  local eased=1-(1-p)^3
  local fade=sin(pi*p)^1.65
  local cx=x+w*.5
  local dir=upward and -1 or 1
  local slotY=upward and (y+4.0) or (y+h-4.0)
  local startY=upward and (y+h-4.5) or (y+4.5)
  local yy=startY+(slotY-startY)*eased
  local a=(.10+.86*fade)*(.72+.28*glow)

  local slotA=.28+.28*glow+.14*fade
  line(cx-9.5,slotY,cx+9.5,slotY,C.edge,slotA*.58)
  line(cx-7.0,slotY,cx+7.0,slotY,C.ice,slotA)
  line(cx-10.5,slotY-dir*.8,cx-8.7,slotY,C.accent,slotA*.48)
  line(cx+10.5,slotY-dir*.8,cx+8.7,slotY,C.accent,slotA*.48)

  local compress=1-.44*eased
  local half=12.0*compress
  disc(cx,yy,5.8,C.accent,.014*a)
  line(cx-half,yy,cx+half,yy,C.ice,a*.82)
  line(cx-half+1.8,yy-dir*.9,cx+half-1.8,yy-dir*.9,C.accent,a*.30)
  line(cx-half,yy,cx-half+2.2,yy-dir*1.2,C.ice,a*.34)
  line(cx+half,yy,cx+half-2.2,yy-dir*1.2,C.ice,a*.34)

  for i=1,2 do
    local lag=i*(2.2+1.0*eased)
    local ty=yy-dir*lag
    local thalf=half+(i*2.4)
    local ta=a*(i==1 and .22 or .09)*(1-.35*eased)
    line(cx-thalf,ty,cx+thalf,ty,C.accent,ta)
  end

  local gap=max(.4,2.0*(1-eased))
  line(cx-gap-2.8,yy+dir*1.8,cx-gap,yy+dir*1.8,C.muted,a*.28)
  line(cx+gap,yy+dir*1.8,cx+gap+2.8,yy+dir*1.8,C.muted,a*.28)

  widgets[#widgets+1]={id=id,x=x,y=y,w=w,h=h,fn=fn}
end

local function ease_fold(t)
  t=Core.clamp(t,0,1)
  if t<.5 then return 4*t*t*t end
  return 1-((-2*t+2)^3)/2
end

local function begin_window_transition(mode,fromRect,toRect,duration)
  A.windowTransition={mode=mode,started=R.time_precise(),duration=duration or .30,
    from=fromRect,to=toRect}
  A.edit=nil; A.pressed=nil; A.down=false; widgets={}
end

local function step_window_transition(now)
  local tr=A.windowTransition
  if not tr then return end
  local hwnd=gfx_window_handle()
  if not hwnd then A.windowTransition=nil; return end
  local p=Core.clamp((now-tr.started)/tr.duration,0,1)
  local q=ease_fold(p)
  local f,t=tr.from,tr.to
  local left=floor(f.left+(t.left-f.left)*q+.5)
  local top=floor(f.top+(t.top-f.top)*q+.5)
  local width=max(1,floor(f.width+(t.width-f.width)*q+.5))
  local height=max(1,floor(f.height+(t.height-f.height)*q+.5))
  BLT.position(hwnd,left,top,width,height,'','')
  if p>=1 then
    local mode=tr.mode
    A.windowTransition=nil
    A.collapsed=(mode=='collapse')
    A.pressed=nil; A.down=false; widgets={}
  end
end

local function collapse_window()
  if A.collapsed or A.windowTransition then return end
  if not commit_edit() then return end
  local hwnd=gfx_window_handle()
  if not hwnd then return end
  local dock,dx,dy,dw,dh=gfx.dock(-1,0,0,0,0)
  -- A docked gfx window is owned by REAPER's docker and cannot be reduced to a
  -- free compact bar without changing the user's docking layout.
  if dock and (dock&1)~=0 then
    Language.mb('ドッキング中はウィンドウを縮小できません。\nフローティング表示で使用してください。','LOUDNESS TRACE',0)
    return
  end
  local ok,l,t,r,b=WindowGeometry.JS_Window_GetRect(hwnd)
  local okc,cw,ch=R.JS_Window_GetClientSize(hwnd)
  if not ok or not okc or not l or not r or not cw then return end
  local outerW,outerH=r-l,b-t
  local frameW,frameH=max(0,outerW-cw),max(0,outerH-ch)
  A.normalWindow={left=l,top=t,width=outerW,height=outerH}
  A.normalDock={x=dx,y=dy,w=dw,h=max(1,dh-A.titleH)}
  local compactW,compactH=COLLAPSED_W+frameW,COLLAPSED_H+A.titleH+frameH
  local left=floor((l+r-compactW)*.5+.5)
  local target={left=left,top=t,width=compactW,height=compactH}
  begin_window_transition('collapse',A.normalWindow,target,.32)
end

local function expand_window()
  if not A.collapsed or A.windowTransition then return end
  local hwnd=gfx_window_handle()
  local g=A.normalWindow
  if not hwnd or not g then return end
  local ok,l,t,r,b=WindowGeometry.JS_Window_GetRect(hwnd)
  if not ok then return end
  local from={left=l,top=t,width=r-l,height=b-t}

  local center=(l+r)*.5
  local target={
    left=floor(center-g.width*.5+.5),
    top=t,
    width=g.width,
    height=g.height
  }
  A.collapsed=false
  begin_window_transition('expand',from,target,.30)
end

local function collapsed_controller()
  local contentH=max(1,gfx.h-A.titleH)
  scale=min(gfx.w/COLLAPSED_W,contentH/COLLAPSED_H);ox=(gfx.w-COLLAPSED_W*scale)/2;oy=A.titleH+(contentH-COLLAPSED_H*scale)/2
  gfx.clear=-1;gfx.set(C.bg[1],C.bg[2],C.bg[3],1);gfx.rect(0,0,gfx.w,gfx.h,1)
  custom_titlebar()
  rect(0,0,COLLAPSED_W,COLLAPSED_H,C.bg);gradient(0,0,COLLAPSED_W,COLLAPSED_H,C.field,C.bg,.72,.98)
  widgets={}
  local pulse=A.job and (.55+.45*sin(A.anim*5.2)^2) or .45
  disc(15,16,A.job and 4.2 or 3.4,C.accent,.055+.045*pulse)
  disc(15,16,1.7,A.job and C.ice or C.mint,A.job and .92 or .72)
  text('LOUDNESS TRACE',28,7,12.2,C.text,190,3,true)
  local state=A.job and ('ANALYZING  '..floor(A.job.progress*100)..'%') or 'TRACE ACTIVE'
  text(state,29,25,7.7,A.job and C.ice or C.faint,178,3,true)
  fold_control('expand',(COLLAPSED_W-48)*.5,39,48,16,false,expand_window)

  button('measure',A.job and '中止' or '解析',
    COMPACT_MEASURE_X,COMPACT_MEASURE_Y,COMPACT_MEASURE_W,COMPACT_MEASURE_H,
    function() if A.job then cancel_job() else measure() end end,
    true,false,A.job and 'CANCEL' or 'ANALYZE')
  if A.job then
    rect(COMPACT_MEASURE_X,COMPACT_MEASURE_Y+COMPACT_MEASURE_H+2,
      COMPACT_MEASURE_W*A.job.progress,2,C.ice,.86)
  end
  inputs_mouse()
end

-- Optional TCP child control. All native coordinates deliberately bypass the
-- floating-window platform adapter; SWELL child positions use client coordinates.
local TCP={width=88,height=24}
local function tcp_dispose()
 if TCP.window then
  pcall(reaper.JS_Composite_Unlink,TCP.window,TCP.bitmap,true)
  pcall(reaper.JS_Window_Destroy,TCP.window);TCP.window=nil
 end
 if TCP.bitmap then R.JS_LICE_DestroyBitmap(TCP.bitmap);TCP.bitmap=nil end
 TCP.parent=nil;TCP.signature=nil;TCP.position=nil;TCP.down=nil
end
local function tcp_button(now)
 if TCP.supported==nil then
  TCP.supported=true
  for _,name in ipairs({'GetThingFromPoint','JS_Window_Create','JS_Window_SetParent','JS_Window_Destroy','JS_Window_Show','JS_WindowMessage_Intercept','JS_WindowMessage_Peek'}) do
   if type(reaper[name])~='function' then TCP.supported=false;break end
  end
 end
 if not TCP.supported then return end
 if not valid_track() or R.GetMediaTrackInfo_Value(A.track,'B_SHOWINTCP')==0 then tcp_dispose();return end
 if not TCP.geometryAt or now>=TCP.geometryAt then
  TCP.geometryAt=now+.1
  local arrange=R.JS_Window_FindChildByID(R.GetMainHwnd(),1000)
  if not arrange then tcp_dispose();return end
  local ax,ay=R.JS_Window_ClientToScreen(arrange,0,0)
  local ok,aw,ah=R.JS_Window_GetClientSize(arrange)
  local ty=R.GetMediaTrackInfo_Value(A.track,'I_TCPY');local th=R.GetMediaTrackInfo_Value(A.track,'I_TCPH')
  if not ok or th<48 or ty<0 or ty+th>ah then tcp_dispose();return end
  local sy=ay+ty+th-TCP.height-8;local nativeY=Platform.mac and -sy or sy
  local track,where=reaper.GetThingFromPoint(ax-4,Platform.mac and -(sy+12) or sy+12)
  if track~=A.track or not tostring(where):find('tcp',1,true) then tcp_dispose();return end
  local parent=reaper.JS_Window_FromPoint(ax-4,Platform.mac and -(sy+12) or sy+12)
  if not parent then tcp_dispose();return end
  local x,y=reaper.JS_Window_ScreenToClient(parent,ax-TCP.width-12,nativeY)
  local valid,cw,ch=reaper.JS_Window_GetClientSize(parent)
  if not valid or x<0 or y<0 or x+TCP.width>cw or y+TCP.height>ch then tcp_dispose();return end
  if Platform.mac and reaper.JS_Window_EnableMetal(parent)==1 then tcp_dispose();return end
  if TCP.parent~=parent or not TCP.window or not R.JS_Window_IsWindow(TCP.window) then
   tcp_dispose();TCP.parent=parent
   TCP.window=reaper.JS_Window_Create('BLT TRACE Analyze','BLT_TRACE_TCP',x,y,TCP.width,TCP.height,'CHILD,VISIBLE',parent)
   if not TCP.window then TCP.supported=false;return end
   reaper.JS_Window_SetParent(TCP.window,parent)
   reaper.JS_Window_SetPosition(TCP.window,x,y,TCP.width,TCP.height,'TOP','NOACTIVATE');TCP.position=x..':'..y
   for _,msg in ipairs({'WM_LBUTTONDOWN','WM_LBUTTONUP'}) do
    if reaper.JS_WindowMessage_Intercept(TCP.window,msg,false)~=1 then tcp_dispose();TCP.supported=false;return end
   end
   TCP.bitmap=R.JS_LICE_CreateBitmap(true,TCP.width,TCP.height)
   if not TCP.bitmap then tcp_dispose();return end
  end
  local position=x..':'..y
  if TCP.position~=position then reaper.JS_Window_SetPosition(TCP.window,x,y,TCP.width,TCP.height,'TOP','NOACTIVATE');TCP.position=position end
 end
 if not TCP.window then return end
 local down,_,dt=reaper.JS_WindowMessage_Peek(TCP.window,'WM_LBUTTONDOWN')
 if down and dt~=TCP.lastDown then TCP.lastDown=dt;TCP.down=dt end
 local up,_,ut,_,_,x,y=reaper.JS_WindowMessage_Peek(TCP.window,'WM_LBUTTONUP')
 if up and ut~=TCP.lastUp then
  TCP.lastUp=ut
  if TCP.down and ut>=TCP.down and x>=0 and y>=0 and x<TCP.width and y<TCP.height then
   TCP.down=nil;if A.job then cancel_job() else measure() end
  end
  TCP.down=nil
 end
 local label=A.job and Language.text('中止') or Language.text('解析')
 local signature=label..table.concat(C.accent2,':')..table.concat(C.field,':')..table.concat(C.text,':')
 if signature~=TCP.signature then
  R.JS_LICE_Clear(TCP.bitmap,argb(C.field))
  R.JS_LICE_FillRect(TCP.bitmap,0,TCP.height-2,TCP.width,2,argb(C.accent2),1,'COPY')
  R.JS_LICE_SetFontColor(A.font,argb(C.text))
  R.JS_LICE_DrawText(TCP.bitmap,A.font,label,#label,10,3,TCP.width-4,TCP.height)
  local code=R.JS_Composite(TCP.window,0,0,TCP.width,TCP.height,TCP.bitmap,0,0,TCP.width,TCP.height,true)
  if code~=1 then tcp_dispose();return end
  R.JS_Window_InvalidateRect(TCP.window,0,0,TCP.width,TCP.height,false);TCP.signature=signature
 end
end

local function controller()
  local contentH=max(1,gfx.h-A.titleH)
  scale=min(gfx.w/W,contentH/H);ox=(gfx.w-W*scale)/2;oy=A.titleH+(contentH-H*scale)/2-22*scale;BLT.viewport(scale,gfx.ext_retina or 1)
  gfx.clear=-1;gfx.set(C.bg[1],C.bg[2],C.bg[3],1);gfx.rect(0,0,gfx.w,gfx.h,1)

  rect(0,0,W,H+22,C.bg);gradient(0,0,W,100,C.field,C.bg)

  BLT.title('LOUDNESS TRACE','ARRANGE LOUDNESS ANALYSIS  アレンジビュー上でラウドネスを解析・表示',W)
  BLT.drawIcon();widgets={}

  local _,name=source_track()
  source_selector(name,24,107,598,44,choose_source)
  local data=A.data
  local savedText=data and ('保存済み：'..data.name..'  /  '..#data.segments..'区間  ·  選択範囲だけ置換') or '時間範囲を選択して解析。範囲外の解析結果は保持します。'
  text(savedText,25,158,11.5,C.muted,596)

  local pos=R.GetCursorPositionEx(A.project)
  if (R.GetPlayStateEx(A.project)&1)==1 then pos=R.GetPlayPositionEx(A.project) end
  local sample=A.hover or Core.row(data,pos)
  local cardW=190
  for j,q in ipairs({{'s','LUFS-S  /  3 sec',C.ice},{'m','LUFS-M  /  400 ms',C.mint},{'i','Integrated',C.purple}}) do
    local x=24+(j-1)*204;local key,label,c=q[1],q[2],q[3]
    rect(x,181,cardW,169,C.panel);rect(x,181,cardW,3,c,.58)
    local v=key=='i' and (data and data.integrated) or (sample and sample[key])
    text(value(v),x+11,190,32,target_alert(v,S.targets[key]) and C.red or c,cardW-20,2)
    text(label,x+11,237,11.3,C.muted,cardW-18)
    if key=='i' then
      local lraText=data and data.lra and string.format('LRA %.1f LU',data.lra) or 'LRA —'
      text(lraText,x+91,237,10.3,C.gold,cardW-101,2)
    end
    target_fields(key,x+8,265,cardW-16)
    toggle(key,'グラフ '..(S.show[key] and 'ON' or 'OFF'),x+8,310,cardW-16,30)
  end
  rect(24,360,598,86,C.panel);line(24,360,622,360,C.edge,.55)
  local warnUp,warnDown,warnPeak=warning_durations(data)
  text('警告表示',36,371,12.5,C.muted,110)
  text('補助表示',346,371,12.5,C.muted,110)
  option_switch('alert_upper','上限','超過',36,390,92,S.alertUpper,function()
    S.alertUpper=not S.alertUpper;edited()
  end)
  option_switch('alert_lower','下限','未満',132,390,92,S.alertLower,function()
    S.alertLower=not S.alertLower;edited()
  end)
  option_switch('alert_peak','ピーク','超過',228,390,98,S.alertPeak,function()
    S.alertPeak=not S.alertPeak;edited()
  end)
  text(warning_time_text(warnUp),36,429,9.4,C.faint,92,2,true)
  text(warning_time_text(warnDown),132,429,9.4,C.faint,92,2,true)
  text(warning_time_text(warnPeak),228,429,9.4,C.faint,98,2,true)
  line(334,390,334,435,C.edge,.30)
  toggle('rms','RMS '..(S.show.rms and 'ON' or 'OFF'),346,399,126,30)
  rect(346,399,126,2,C.gold,.68)
  toggle('peak','Peak '..(S.show.peak and 'ON' or 'OFF'),484,399,126,30)
  rect(484,399,126,2,C.faint,.72)

  rect(24,452,598,76,C.panel);line(24,452,622,452,C.edge,.62)
  text('グラフ設定',36,459,12.2,C.muted,95)
  button('height','グラフ幅：'..S.height,36,479,100,40,function()
    local heights={200,280,380,520};local nextheight=200
    for i,h in ipairs(heights) do if S.height==h then nextheight=heights[i%#heights+1] end end
    change_height(nextheight);edited()
  end)
  number_field('axis_lo','下限',144,479,80,function() return S.lo end,function(v) S.lo=v;return true end,1,40,
    function(v) local n=Core.clamp(v,-120,min(18,S.hi-.1));return n,n~=v end)
  number_field('axis_hi','上限',232,479,80,function() return S.hi end,function(v) S.hi=v;return true end,1,40,
    function(v) local n=Core.clamp(v,max(-118,S.lo+.1),24);return n,n~=v end)
  button('auto_axis','解析結果へ最適化',320,479,132,40,auto_axis_range)
  local graphVisible=graph_track_is_visible()
  S.visible=graphVisible
  button('visible',graphVisible and 'グラフを非表示' or 'グラフを表示',460,479,150,40,function()
    set_graph_track_visible(not graph_track_is_visible())
  end)

  button('clear','グラフをクリア',108,560,126,32,function() clear_measurement() end,false,false,nil,'gold')
  button('measure',A.job and ('解析を中止  '..floor(A.job.progress*100)..'%') or '選択範囲を解析',250,550,276,42,function()
    if A.job then cancel_job() else measure() end
  end,true,false,A.job and 'CANCEL' or 'ANALYZE')
  if A.job then rect(250,594,276*A.job.progress,2,C.ice,.8) end
  fold_control('collapse',(W-64)*.5,603,64,18,true,function() A.requestFold=true end)

  BLT.footer(A.job and string.format('解析中 %d%%',math.floor(A.job.progress*100)) or (A.stale and 'プロジェクトが変更されています。再解析してください。' or (A.data and '解析結果を表示しています。' or '時間範囲を選択してください。')),A.stale,W,H+22,'0.5.2')
  inputs_mouse();custom_titlebar()
end

BLT.factorySettings={lo=-60,hi=0,visible=true,height=280,show={s=true,m=true,i=true,rms=false,peak=false},targets={s={-23,3},m={-23,3},i={-23,1}},source="master",alertUpper=true,alertLower=true,alertPeak=false}
BLT.warningCompute=warning_durations;warning_durations=function(data) local c=BLT.warningCache;local a,b=S.targets.s,S.targets.m;if c and c.data==data and c.rows==(data and data.rows) and c.count==(data and #data.rows or 0) and c.a==a[1] and c.b==a[2] and c.c==b[1] and c.d==b[2] then return c[1],c[2],c[3] end;local x,y,z=BLT.warningCompute(data);BLT.warningCache={x,y,z,data=data,rows=data and data.rows,count=data and #data.rows or 0,a=a[1],b=a[2],c=b[1],d=b[2]};return x,y,z end
function BLT.pick(obj,keys) local v=BLT.valueView or {};BLT.valueView=v;for k in pairs(keys) do v[k]=obj[k] end;return v end
BLT.chrome=setmetatable({font=Platform.chromeFont,mint=C.mint,red=C.red,titleText='L O U D N E S S   T R A C E'}, {
 __index=function(_,k) local m={titleH='titleH',mouseDown='titleMouseDown',drag='titleDrag',resize='resizeDrag',mouseActive='titleMouseActive',closePressed='titleClosePressed',resetPressed='titleResetPressed',chameleonPressed='titleChameleonPressed',requestClose='requestClose',requestReset='requestReset'};return A[m[k] or k] end,
 __newindex=function(t,k,v) local m={mouseDown='titleMouseDown',drag='titleDrag',resize='resizeDrag',mouseActive='titleMouseActive',closePressed='titleClosePressed',resetPressed='titleResetPressed',chameleonPressed='titleChameleonPressed',requestClose='requestClose',requestReset='requestReset'};A[m[k] or k]=v end})
 C.accent2=C.ice;C.edge2=C.edge

BLT.attach({
 R=R,C=C,Chrome=BLT.chrome,Chameleon=Chameleon,section=SECTION,faces=Platform.faces,font=function(sz,k,b) BLT.font(sz,k,b,scale,Platform.faces) end,
 geometry=function() return scale,ox,oy end,active=function() local f=gfx.getchar(65536);return (f&1)==0 or (f&2)~=0 end,
 wake=function() A.content_dirty=true;redraw_dirty=true;next_draw_time=0;wake_visuals() end,
 defaults=BLT.factorySettings,capture=function() return S end,
 valid=function(v) if v.lo< -120 or v.hi>24 or v.lo>=v.hi or v.height<100 or v.height>1000 or (v.source~='master' and not v.source:match('^%{[%x%-]+%}$')) then return false end;for _,t in pairs(v.targets) do if #t~=2 or t[1]< -120 or t[1]>24 or t[2]<0 or t[2]>120 then return false end end;return true end,apply=function(v) local hc,vc=S.height~=v.height,S.visible~=v.visible;for k,x in pairs(v) do S[k]=x end;if hc then change_height(S.height) end;if vc then set_graph_track_visible(S.visible) end;edited() end,
 undoRefresh=function() A.revision=A.revision+1;A.cache='';A.stale=A.data~=nil end,
 busy=function() return A.job~=nil or A.windowTransition~=nil end,commit=function() return commit_edit() end,
 cancelEdit=function() A.edit=nil;A.fieldDrag=nil end,editing=function() return A.edit~=nil end,
 modal=function() return false end,
 handle=gfx_window_handle,resizeHit=function(x,y) if y<26 and x>=gfx.w-268 then return nil end;return resize_hit(x,y) end,
 cursor=set_resize_cursor,beginResize=begin_resize,resize=update_resize,
 compactChrome=function() return A.collapsed end,transition=function() return A.windowTransition~=nil end,fold=function() A.requestFold=true end,collapsed=function() return A.collapsed end,prepareMenu=function() if A.collapsed then A.requestFold=true;BLT.openAfterExpand=true;return false end;return not A.windowTransition end,
})
if ...=='blt_test' then function BLT.testDraw(now) controller(now or R.time_precise()) end end
function BLT.drawIcon()

 local bs,bx,by=scale,ox,oy;ox,oy=ox+(W-102)*scale,oy+31*scale;scale=scale*.78
 icon(0,0)

 scale,ox,oy=bs,bx,by
end

if ...=='blt_test' then return {BLT=BLT,A=A,Core=Core,S=S} end
local _,_,sectionID,commandID=R.get_action_context()
local function close()
 -- Teardown errors must not leave a dead graphics window on screen.
 local ok,err=xpcall(function()
  if A.closed then return end; A.closed=true
  clear_loudness_tooltip()
  set_resize_cursor(nil)
  cancel_job()
  retry_temp_deletes(true)
  tcp_dispose()
  dispose_bitmap()
  if A.font then R.JS_LICE_DestroyFont(A.font); A.font=nil end
  if A.gdiFont then R.JS_GDI_DeleteObject(A.gdiFont); A.gdiFont=nil end
  if A.uiReady then
    local dock,x,y,w,h=gfx.dock(-1,0,0,0,0)
    if (A.collapsed or A.windowTransition) and A.normalDock then
      x,y,w,h=A.normalDock.x,A.normalDock.y,A.normalDock.w,A.normalDock.h
    else
      h=max(1,h-A.titleH)
    end
    for key,value in pairs({window_x=x,window_y=y,window_w=w,window_h=h}) do
      if Core.finite(value) then BLT.store(SECTION,key,tostring(value),true) end
    end
    gfx.quit()
  end
  if Platform.mac then Platform.finish() end
  if commandID and commandID>0 then R.SetToggleCommandState(sectionID,commandID,0); R.RefreshToolbar2(sectionID,commandID) end
 end,debug.traceback)
 if not ok then
  A.closed=true
  pcall(gfx.quit)
  if R.TrackCtl_SetToolTip then pcall(R.TrackCtl_SetToolTip,'',0,0,true) end
  BLT.logError(err)
  if Platform.mac then pcall(Platform.finish) end
 end
end
R.atexit(close)
local function startup()
  local tempDirectory=(Platform.tempDirectory()):gsub('[/\\]+$','')
  recover_stale_temp_files(tempDirectory)
  A.gdiFont=R.JS_GDI_CreateFont(14,400,0,false,false,false,Platform.graphFont)
  A.font=R.JS_LICE_CreateFont()
  if not A.gdiFont or not A.font then error("グラフ用フォントを作成できません。") end
  R.JS_LICE_SetFontFromGDI(A.font,A.gdiFont,"")
  R.JS_LICE_SetFontBkColor(A.font,0)
  adopt_project(true)
  local ww=Core.clamp(extnum("window_w",W),520,1200)
  local hh=Core.clamp(extnum("window_h",H),300,1000)
  -- Mac controller uses logical points, matching SWELL window sizes and hit targets.
  -- The OS scales the backing surface; Windows keeps its original HiDPI path.
  gfx.ext_retina=Platform.mac and 0 or 1
  local wx,wy=extnum("window_x",100),extnum("window_y",100)
  gfx.init("LOUDNESS TRACE",ww,hh+A.titleH,0,wx,wy)
  A.uiReady=true; A.gfxWindow=R.JS_Window_Find("LOUDNESS TRACE",true)
  if A.gfxWindow then
    -- Replace the operating-system caption with the controller's own title bar.
    R.JS_Window_SetStyle(A.gfxWindow,"POPUP")
    if Platform.mac then
      local ok,l,t=WindowGeometry.JS_Window_GetRect(A.gfxWindow)
      if ok then BLT.position(A.gfxWindow,l,t,ww,hh+A.titleH,'','') end
    else BLT.position(A.gfxWindow,wx,wy,ww,hh+A.titleH,'','') end
  end
  if Chameleon.enabled then Chameleon.refresh(true) end
  A.clock=R.time_precise()
  if commandID and commandID>0 then R.SetToggleCommandState(sectionID,commandID,1); R.RefreshToolbar2(sectionID,commandID) end
end
local function frame()
 if Platform.mac then Platform.advance() end
 BLT.tick(R.time_precise())

  local k=BLT.key(gfx.getchar())
  if k<0 or (k==27 and not A.edit and not BLT.presets.open) then close(); return end
  local now=R.time_precise(); Chameleon.tick(now); A.realDt=Core.clamp(now-A.clock,0,.1); A.clock=now
  retry_temp_deletes(false)
  local active=(gfx.getchar(65536)&2)==2
  if last_active_state==nil or active~=last_active_state then last_active_state=active; wake_visuals(now) end
  A.active=active

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

  local key_activity=k>0
  if key_activity then wake_visuals(now) end
  local project_changed=R.EnumProjects(-1,"")~=A.project
  if project_changed then cancel_job(); adopt_project(false); redraw_dirty=true end
  local was_stale=A.stale
  if A.data and R.GetProjectStateChangeCount(A.project)~=A.baseline then A.stale=true end
  if A.stale~=was_stale then redraw_dirty=true end

  local consumed=edit_key(k)
  if k==13 and not consumed then if A.job then cancel_job() else measure() end; redraw_dirty=true end
  local had_job=A.job~=nil
  step_job()
  if had_job~=(A.job~=nil) then redraw_dirty=true end
  local transition_active=A.windowTransition~=nil
  step_window_transition(now)
  if transition_active~=(A.windowTransition~=nil) then redraw_dirty=true end
  overlay(now)
  local tcp_ok,tcp_err=pcall(tcp_button,now)
  if not tcp_ok then tcp_dispose();TCP.supported=false;BLT.logError(tcp_err) end
  if A.data and not A.collapsed and now>=(BLT.meterAt or 0) then
    BLT.meterAt=now+.067;local pos=(R.GetPlayStateEx(A.project)&1)~=0 and R.GetPlayPositionEx(A.project) or R.GetCursorPositionEx(A.project)
    if BLT.meterPos~=pos or BLT.meterHover~=A.hover then BLT.meterPos=pos;BLT.meterHover=A.hover;redraw_dirty=true end
  end

  local dragging=A.resizeDrag~=nil or A.titleDrag~=nil or A.fieldDrag~=nil or ((raw_cap or 0)&1)~=0
  if dragging then wake_visuals(now) end
  local forced=A.job~=nil or A.windowTransition~=nil
  local speed=forced and 1 or visual_speed(now)
  local animateNow=forced or (A.active and speed>0)
  A.dt=animateNow and A.realDt*(forced and 1 or speed) or 0
  A.anim=A.anim+A.dt*(A.job and 1.85 or 1)

  local particle_tail=#A.particles>0 or #A.iconParticles>0 or #A.analysisBurstParticles>0 or A.analysisBurst~=nil
  local frame_interval
  if dragging then frame_interval=1/60
  elseif forced then frame_interval=1/30
  elseif animateNow then frame_interval=1/(8+22*speed)
  elseif particle_tail then frame_interval=1/20 end
  if frame_interval and next_draw_time==math.huge then next_draw_time=now end
  local frame_due=frame_interval and now>=next_draw_time or (not frame_interval and (redraw_dirty))
  if frame_due then
    if A.collapsed then collapsed_controller() else controller() end
    gfx.update(); redraw_dirty=false
    next_draw_time=frame_interval and now+frame_interval or math.huge

    if A.requestClose then close(); return end
    if A.requestFold then
      A.requestFold=false
      if A.collapsed then expand_window() else collapse_window() end
      wake_visuals(now)
    end
    if A.requestReset then A.requestReset=false; reset_window_size(); wake_visuals(now) end
  end
  if pointer_activity or key_activity or dragging then redraw_dirty=true end
end
local function fail(err)
  close(); Language.mb(public_error(err),"LOUDNESS TRACE | エラー",0)
end
local function loop()
  local ok,err=xpcall(frame,public_error)
  if not ok then fail(err); return end
  if not A.closed then R.defer(loop) end
end
local ok,err=xpcall(startup,public_error)
if ok then loop() else fail(err) end
