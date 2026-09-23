-- @description LOUDNESS TRACE
-- @version 0.5.18
-- @author Balrulu
-- @provides
--   . > ../
-- @changelog
--   BLT SERIES Beta TEST UPLOAD
-- @about
--   BLT SERIES Beta TEST UPLOAD

local BLTPresetLimits={bytes=16777216,stringBytes=2097152,nodes=262144,entries=8192}
function BLTPresetLimits.show(english)
 reaper.MB(english and 'Preset capacity limit exceeded. Export presets individually instead of as a bundle.' or '容量上限オーバーです。一括ではなく個別に保存してください。','BLT PRESET',0)
end

-- Media availability
local function create_media_gate(api,graphics)
 local M={waiting=false}
 local next_check=0;local ready=true;local settle=0;local last_active
 local function application_active()
  if graphics and graphics.getchar then
   local flags=graphics.getchar(65537)
   if flags>=0 and ((flags&1)==0 or (flags&2)~=0) then return true end
  end
  if not (api.JS_Window_GetForeground and api.GetMainHwnd and api.JS_Window_GetParent) then return nil end
  local foreground=api.JS_Window_GetForeground();local main=api.GetMainHwnd()
  for _=1,32 do
   if not foreground then return false end
   if foreground==main then return true end
   local parent=api.JS_Window_GetParent(foreground)
   if parent==foreground then return nil end;foreground=parent
  end
  return nil
 end
 local function offline(project,take)
  -- targets() resolves or validates each pointer in this same defer pass.
  if not take then return false end
  if api.TakeIsMIDI and api.TakeIsMIDI(take) then return false end
  if not api.GetMediaItemTake_Source then return false end
  local source=api.GetMediaItemTake_Source(take);local seen={}
  for _=1,32 do
   if not source or seen[source] then break end;seen[source]=true
   local is_offline=false
   if api.CF_GetMediaSourceOnline then
    is_offline=not api.CF_GetMediaSourceOnline(source)
   elseif api.GetMediaSourceSampleRate and api.GetMediaSourceNumChannels then
    is_offline=api.GetMediaSourceSampleRate(source)<=0 or api.GetMediaSourceNumChannels(source)<=0
   end
   if is_offline then
    local file=api.GetMediaSourceFileName and api.GetMediaSourceFileName(source,'') or ''
    if file~='' and (not api.file_exists or api.file_exists(file)) then return true end
   end
   source=api.GetMediaSourceParent and api.GetMediaSourceParent(source) or nil
  end
  return false
 end
 local function targets(project,all_items)
  local takes={};local invalid=false
  local all=all_items or (M.all_items and M.state and M.state.job)
  local count=all and api.CountMediaItems(project) or api.CountSelectedMediaItems(project)
  for i=0,count-1 do
   local item=all and api.GetMediaItem(project,i) or api.GetSelectedMediaItem(project,i)
   if not item then invalid=true
   else local take=api.GetActiveTake(item);if take then takes[take]=true end end
  end
  return takes,invalid
 end
 function M.ready(force,all_items)
  local now=api.time_precise()
  if not force and now<next_check then return ready end
  next_check=now+.10
  local project=api.EnumProjects(-1,'')
  local takes,invalid=targets(project,all_items);local blocked=false
  if M.state and M.state.project and M.state.project~=project then invalid=true end
  if not invalid then
   if next(takes) and not api.CF_GetMediaSourceOnline and application_active()==false then blocked=true
   else for take in pairs(takes) do if offline(project,take) then blocked=true;break end end end
  end
  if invalid or not next(takes) then settle=0 end
  if blocked then settle=now+.25 end
  local waiting=not invalid and (blocked or now<settle)
  ready=not waiting
  if waiting~=M.waiting then
   M.waiting=waiting
   if M.onchange then M.onchange() end
  end
  return ready
 end
 function M.tick()
  local active=application_active()
  if active~=last_active then next_check=0;last_active=active end
  return M.ready()
 end
 function M.message(section)
  return api.GetExtState(section,'ui_language')=='EN' and 'Waiting for media to come online…' or 'メディアのオンライン復帰を待っています…'
 end
 return M
end
local Media=create_media_gate(reaper,gfx)

-- Window coordinates
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

-- Application / analysis
local VERSION="0.5.18"
local MAX_HISTORY_ROWS=126000
local MAX_SAVE_BYTES=12*1024*1024
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

    local expectedFrames=floor(expected*sr+.5)
    local diffFrames=math.abs(frames-expectedFrames)
    local toleranceFrames=max(8,floor(sr*.005+.5))
    assert(diffFrames<=toleranceFrames,
      string.format('レンダーが中断されたか、測定範囲と音声の長さが一致しません。\n予定: %.6f 秒 / 実際: %.6f 秒 / 差: %.3f ms',
        expected,frames/sr,diffFrames/sr*1000))
  end

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
        nextlevel[#nextlevel+1]=lo~=nil and lo or false;nextlevel[#nextlevel+1]=hi~=nil and hi or false
      end
      levels[#levels+1]=nextlevel;n=(n+1)//2
      if tick then tick(.98) end
    end
    data.lod[key]=levels
  end
end

function Core.live_tree()
  local T={v={},n={},sum={},count={},left={},right={},priority={},free={},root=0,serial=0,seed=17}
  local function update(i)
    local a,b=T.left[i],T.right[i]
    T.count[i]=T.n[i]+(T.count[a] or 0)+(T.count[b] or 0)
    T.sum[i]=T.v[i]*T.n[i]+(T.sum[a] or 0)+(T.sum[b] or 0)
    return i
  end
  local function rotate(i,left)
    local j=left and T.right[i] or T.left[i]
    if left then T.right[i]=T.left[j];T.left[j]=i else T.left[i]=T.right[j];T.right[j]=i end
    update(i);return update(j)
  end
  local function insert(i,v)
    if i==0 then
      i=table.remove(T.free)
      if not i then T.serial=T.serial+1;i=T.serial end
      T.seed=T.seed*48271%2147483647
      T.v[i]=v;T.n[i]=1;T.sum[i]=v;T.count[i]=1;T.left[i]=0;T.right[i]=0;T.priority[i]=T.seed
      return i
    end
    if v==T.v[i] then T.n[i]=T.n[i]+1
    elseif v<T.v[i] then T.left[i]=insert(T.left[i],v);if T.priority[T.left[i]]<T.priority[i] then return rotate(i,false) end
    else T.right[i]=insert(T.right[i],v);if T.priority[T.right[i]]<T.priority[i] then return rotate(i,true) end end
    return update(i)
  end
  local function merge(a,b)
    if a==0 then return b end;if b==0 then return a end
    if T.priority[a]<T.priority[b] then T.right[a]=merge(T.right[a],b);return update(a) end
    T.left[b]=merge(a,T.left[b]);return update(b)
  end
  local function remove(i,v)
    assert(i~=0,'集計データの対応が失われました。')
    if v<T.v[i] then T.left[i]=remove(T.left[i],v)
    elseif v>T.v[i] then T.right[i]=remove(T.right[i],v)
    elseif T.n[i]>1 then T.n[i]=T.n[i]-1
    else
      local root=merge(T.left[i],T.right[i]);T.v[i]=nil;T.n[i]=nil;T.sum[i]=nil;T.count[i]=nil
      T.left[i]=nil;T.right[i]=nil;T.priority[i]=nil;T.free[#T.free+1]=i;return root
    end
    return update(i)
  end
  function T.add(v) T.root=insert(T.root,v) end
  function T.remove(v) T.root=remove(T.root,v) end
  function T.above(v,inclusive)
    local i=T.root;local sum,count=0,0
    while i~=0 do
      if T.v[i]>v or (inclusive and T.v[i]==v) then
        local r=T.right[i];sum=sum+T.v[i]*T.n[i]+(T.sum[r] or 0);count=count+T.n[i]+(T.count[r] or 0);i=T.left[i]
      else i=T.right[i] end
    end
    return sum,count
  end
  function T.rank(n)
    local i=T.root
    while i~=0 do
      local before=T.count[T.left[i]] or 0
      if n<=before then i=T.left[i] elseif n<=before+T.n[i] then return T.v[i] else n=n-before-T.n[i];i=T.right[i] end
    end
  end
  return T
end
function Core.live_meter()
  local M={count=0,k={},r={},km=0,ks=0,rm=0}
  function M.feed(time,k,raw,peak)
    local i=M.count+1;M.count=i
    local slot=(i-1)%30+1;local rmsSlot=(i-1)%4+1
    M.km=max(0,M.km+k-(i>4 and (M.k[(i-5)%30+1] or 0) or 0))
    M.ks=max(0,M.ks+k-(M.k[slot] or 0));M.rm=max(0,M.rm+raw-(M.r[rmsSlot] or 0))
    M.k[slot]=k;M.r[rmsSlot]=raw
    return {time=time,peak=Core.db(peak*peak),m=i>=4 and Core.lufs(M.km/4) or nil,
      rms=i>=4 and Core.db(M.rm/4) or nil,s=i>=30 and Core.lufs(M.ks/30) or nil}
  end
  return M
end

-- Update only the affected min/max path, rather than rebuilding the full graph.
function Core.live_lod_append(seg,row)
  local count=#seg.rows;seg.lod=seg.lod or {}
  for _,key in ipairs(Core.metrics) do
    local levels=seg.lod[key] or {{}};seg.lod[key]=levels
    local index=count;local value=row[key];if value==nil then value=false end
    levels[1][index*2-1]=value;levels[1][index*2]=value
    local level,n=1,count
    while n>1 do
      local parent=(index+1)//2;local left=(parent-1)*4+1
      local prev=levels[level];local lo,hi=prev[left],prev[left+1]
      if lo==false then lo=nil;hi=nil end
      local blo,bhi=prev[left+2],prev[left+3]
      if blo~=nil and blo~=false then lo=lo and min(lo,blo) or blo;hi=hi and max(hi,bhi) or bhi end
      levels[level+1]=levels[level+1] or {};local dst=levels[level+1]
      dst[parent*2-1]=lo~=nil and lo or false;dst[parent*2]=hi~=nil and hi or false
      index=parent;n=(n+1)//2;level=level+1
    end
  end
end
function Core.live_after(rows,t)
  local lo,hi=1,#rows+1
  while lo<hi do local mid=(lo+hi)//2;if rows[mid].time<=t+1e-8 then lo=mid+1 else hi=mid end end
  return lo
end
function Core.live_view(previous,active,source,name)
  local out={source=source,name=name,segments={},rows=active.rows,integrated=active.integrated or Core.SILENCE,lra=active.lra}
  local total=0
  local function keep(seg,a,b)
    if b<=a+1e-8 then return end
    local first,last=Core.live_after(seg.rows,a),Core.live_after(seg.rows,b)-1
    if last<first then return end
    total=total+last-first+1
    out.segments[#out.segments+1]={first=a,last=b,rows=seg.rows,origin=seg.origin,lod=seg.lod,stamp=seg.stamp or 0,stale=seg.stale}
  end
  if previous then for _,seg in ipairs(previous.segments) do
    if seg.last<=active.first or seg.first>=active.last then keep(seg,seg.first,seg.last)
    else keep(seg,seg.first,min(seg.last,active.first));keep(seg,max(seg.first,active.last),seg.last) end
  end end
  keep(active,active.first,active.last)
  table.sort(out.segments,function(a,b)return a.first<b.first end)
  out.first=out.segments[1].first;out.last=out.segments[#out.segments].last;out.liveCount=total
  return out
end
-- Exact aggregate shared by offline and live histories. Each retained 400 ms / 3 s
-- window must lie within its surviving segment; boundary-crossing windows are excluded.
function Core.history_energy(row,key,first)
  local window=key=='m' and .4 or 3
  local v=row[key]
  if not Core.finite(v) or row.time-window<first-1e-7 then return nil end
  if key=='m' then return v> -70 and 10^((v+.691)/10) or nil end
  return v>=-70 and 10^(v/10) or nil
end
function Core.tree_integrated(tree)
  local n=tree.count[tree.root] or 0;if n==0 then return Core.SILENCE end
  local sum,count=tree.above(max(10^((-70+.691)/10),tree.sum[tree.root]/n*.1),false)
  return count>0 and Core.lufs(sum/count) or Core.SILENCE
end
function Core.tree_lra(tree)
  local n=tree.count[tree.root] or 0;if n==0 then return nil end
  local _,count=tree.above(max(1e-7,tree.sum[tree.root]/n*.01),true)
  if count==0 then return nil end
  local a=n-count+max(1,min(count,floor((count-1)*.10+1.5)))
  local b=n-count+max(1,min(count,floor((count-1)*.95+1.5)))
  return max(0,10*math.log(tree.rank(b)/tree.rank(a),10))
end
function Core.row_warning(row,targets)
  local a,b=targets.s,targets.m
  return ((row.s and row.s>a[1]+a[2]) or (row.m and row.m>b[1]+b[2])) and 1 or 0,
    ((row.s and row.s<a[1]-a[2]) or (row.m and row.m<b[1]-b[2])) and 1 or 0,
    row.peak and row.peak>=0 and 1 or 0
end
function Core.history_summary(previous,first,targets)
  local H={m=Core.live_tree(),s=Core.live_tree(),prefix=Core.live_tree(),parts={},first=first,last=first,
    warning={0,0,0},targets={s={targets.s[1],targets.s[2]},m={targets.m[1],targets.m[2]}}}
  local function warning(row,delta)
    local a,b,c=Core.row_warning(row,H.targets)
    H.warning[1]=H.warning[1]+a*delta;H.warning[2]=H.warning[2]+b*delta;H.warning[3]=H.warning[3]+c*delta
  end
  H.warning_row=warning
  for _,seg in ipairs(previous and previous.segments or {}) do
    local q={seg=seg,last=Core.live_after(seg.rows,seg.last)-1}
    local a=Core.live_after(seg.rows,seg.first)
    q.w=max(a,Core.live_after(seg.rows,first))
    q.m=max(q.w,Core.live_after(seg.rows,seg.first+.4-1e-7))
    q.s=max(q.w,Core.live_after(seg.rows,seg.first+3-1e-7))
    H.parts[#H.parts+1]=q
    for i=a,q.last do
      local row=seg.rows[i];warning(row,1)
      if row.m and row.time-.4>=seg.first-1e-7 and row.time<=first+1e-8 then H.prefixValid=true end
      for _,key in ipairs({'m','s'}) do
        local e=Core.history_energy(row,key,seg.first)
        if e then H[key].add(e);if key=='m' and row.time<=first+1e-8 then H.prefix.add(e) end end
      end
    end
  end
  function H.feed(row)
    local last=row.time
    assert(last>H.last,'測定時刻が逆転しています。')
    for _,q in ipairs(H.parts) do
      local seg=q.seg
      if last>seg.first+1e-8 and seg.last>first then
        for _,key in ipairs({'m','s','w'}) do
          local window=key=='m' and .4 or key=='s' and 3 or 0
          local edge=window==0 and last or last+window-1e-7
          local stop=min(q.last,Core.live_after(seg.rows,edge)-1)
          for i=q[key],stop do
            local r=seg.rows[i]
            if key=='w' then warning(r,-1) else local e=Core.history_energy(r,key,seg.first);if e then H[key].remove(e) end end
          end
          q[key]=max(q[key],stop+1)
        end
      end
    end
    for _,key in ipairs({'m','s'}) do
      local e=Core.history_energy(row,key,first)
      if e then H[key].add(e);if key=='m' then H.prefix.add(e) end end
    end
    warning(row,1);H.last=last
    if row.m and row.time-.4>=first-1e-7 then H.prefixValid=true end
    row.i=H.prefixValid and Core.tree_integrated(H.prefix) or nil
    return Core.tree_integrated(H.m),Core.tree_lra(H.s)
  end
  return H
end

function Core.render(R,project,first,last,directory,basename)
  basename=basename or 'trace'

  local nums={RENDER_SETTINGS=0,RENDER_BOUNDSFLAG=2,RENDER_CHANNELS=2,RENDER_SRATE=48000,
    RENDER_STARTPOS=first,RENDER_ENDPOS=last,RENDER_TAILFLAG=0,RENDER_TAILMS=0,RENDER_ADDTOPROJ=0,
    RENDER_DITHER=16,RENDER_NORMALIZE=4<<16}
  local strs={RENDER_FILE=directory,RENDER_PATTERN=basename,RENDER_FORMAT='ZXZhdyADAA==',RENDER_FORMAT2=''}
  local oldn,olds,oldcfg={},{},{}
  for k in pairs(nums) do oldn[k]=R.GetSetProjectInfo(project,k,0,false) end
  for k in pairs(strs) do local ok,s=R.GetSetProjectInfo_String(project,k,'',false); assert(ok,'レンダー設定を読み取れません: '..k); olds[k]=s end
  for _,k in ipairs({'renderclosewhendone','autosaveonrender','autosaveonrender2'}) do
    local v=R.SNM_GetIntConfigVar(k,-2147483647)
    if v~=-2147483647 then oldcfg[k]=v end
  end
  assert(oldcfg.renderclosewhendone,'SWSからレンダー設定を取得できません。')
  local function restore()
    for k,v in pairs(oldn) do R.GetSetProjectInfo(project,k,v,true) end
    for k,v in pairs(olds) do R.GetSetProjectInfo_String(project,k,v,true) end
    for k,v in pairs(oldcfg) do R.SNM_SetIntConfigVar(k,v) end
  end
  local ok,result=pcall(function()
    for k,v in pairs(nums) do R.GetSetProjectInfo(project,k,v,true) end
    for k,v in pairs(strs) do assert(R.GetSetProjectInfo_String(project,k,v,true),'レンダー設定を変更できません: '..k) end
    R.SNM_SetIntConfigVar('renderclosewhendone',(oldcfg.renderclosewhendone|1)&~(16|16384|32768))
    for _,k in ipairs({'autosaveonrender','autosaveonrender2'}) do if oldcfg[k] then R.SNM_SetIntConfigVar(k,0) end end
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
    assert(#created==1,'マスターミックスの一時レンダーが複数ファイルになりました。')
    return created[1]
  end)
  local restored,err=pcall(restore)
  if not restored then error('レンダー設定の復元に失敗: '..tostring(err)) end
  if not ok then error(result,0) end
  return result
end

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

      if seg.last<=incoming.first or seg.first>=incoming.last then keep(seg,seg.first,seg.last,true)
      else
        keep(seg,seg.first,min(seg.last,incoming.first),true)
        keep(seg,max(seg.first,incoming.last),seg.last,true)
      end
    end
  end

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
  local segments,all={},{};local range=Core.live_tree()
  for _,seg in ipairs(data.segments) do
    assert(seg.last>seg.first and #seg.rows>0,'保存区間が不正です。')
    local rows={}
    local a,b=Core.live_after(seg.rows,seg.first),Core.live_after(seg.rows,seg.last)-1
    for i=a,b do
      local row=copy_row(seg.rows[i]);row.i=nil
      row.energy=(row.m and row.time-.4>=seg.first-1e-7) and (row.m<=-150 and 0 or 10^((row.m+.691)/10)) or nil
      local e=Core.history_energy(row,'s',seg.first);if e then range.add(e) end
      rows[#rows+1]=row;all[#all+1]=row
      if tick and #all%1000==0 then tick(.94) end
    end
    if #rows>0 then segments[#segments+1]={first=seg.first,last=seg.last,rows=rows,origin=rows[1].time-.1,stamp=seg.stamp or 0,stale=seg.stale} end
  end
  assert(#all>0 and #all<=MAX_HISTORY_ROWS,'保存できる共通履歴は最大3.5時間です。古い履歴を整理してから再試行してください。')
  Core.integrate(all,tick);local cumulative
  for _,r in ipairs(all) do if r.i then cumulative=r.i else r.i=cumulative end end
  data.live=nil;data.source='master';data.name='MASTER MIX · stereo 1/2';data.rows=all;data.segments=segments
  data.integrated=cumulative or Core.SILENCE;data.lra=Core.tree_lra(range)
  data.first=segments[1].first;data.last=segments[#segments].last;data.liveCount=#all
  for _,seg in ipairs(segments) do build_lod(seg,tick) end
end

function Core.row(data,time)
  if not data or not data.segments then return nil end
  local l,h=1,#data.segments;local found,foundIndex
  while l<=h do
    local m=(l+h)//2;local seg=data.segments[m]
    if time>=seg.first then found=seg;foundIndex=m;l=m+1 else h=m-1 end
  end
  if not found or time>found.last+1e-8 then return nil end
  l,h=1,#found.rows;local row
  while l<=h do
    local m=(l+h)//2
    if found.rows[m].time<=time+1e-8 then row=found.rows[m];l=m+1 else h=m-1 end
  end
  if row and row.time<=found.first+1e-8 then row=nil end
  if not row and foundIndex>1 and math.abs(time-found.first)<1e-8 then
    local previous=data.segments[foundIndex-1];local last=previous.rows[#previous.rows]
    if last and math.abs(last.time-time)<1e-8 and last.time<=previous.last+1e-8 then row=last end
  end
  return row
end
-- Byte-bounded BLT2 records; current writer and reader use the same format.

function Core.pack(data)
  local chunks,lines,bytes={}, {},22
  local function flush()
    if #lines>0 then
      local body=table.concat(lines,'|')
      chunks[#chunks+1]='BLT2|'..Core.history_hash({body})..'|'..body;lines={};bytes=22
    end
  end
  local function add(line)
    if bytes+#line+1>8000 then flush() end
    lines[#lines+1]=line;bytes=bytes+#line+1
  end
  local function number(n) return n~=nil and string.format('%.12g',n) or 'x' end
  for _,seg in ipairs(data.segments) do
    local a,b=Core.live_after(seg.rows,seg.first),Core.live_after(seg.rows,seg.last)-1
    -- A LIVE view can retain a shared row array with clipped first/last bounds.
    -- Persist only the visible rows, not the full backing array.
    if a<=b then
      local groups={};local first=a
      for i=a+1,b do
        if math.abs(seg.rows[i].time-seg.rows[i-1].time-.1)>=1e-6 then groups[#groups+1]={first,i-1};first=i end
      end
      groups[#groups+1]={first,b}
      for gi,g in ipairs(groups) do
        local start=gi==1 and seg.first or max(seg.rows[g[1]-1].time,seg.rows[g[1]].time-.1)
        local finish=gi==#groups and seg.last or seg.rows[g[2]].time
        add('G,'..string.format('%.17g,%.17g,%d,%.6f',start,finish,seg.stale and 1 or 0,seg.stamp or 0))
        for i=g[1],g[2] do
          local r=seg.rows[i];local f={'R',string.format('%.17g',r.time)}
          for _,k in ipairs({'s','m','rms','peak'}) do f[#f+1]=number(r[k]) end
          add(table.concat(f,','))
        end
      end
    end
  end
  flush();return chunks
end
function Core.history_hash(chunks)
  local h=0xcbf29ce484222325;local bytes=0
  for _,chunk in ipairs(chunks) do
    bytes=bytes+#chunk
    for i=1,#chunk do h=(h~chunk:byte(i))*0x100000001b3 end
    h=(h~10)*0x100000001b3
  end
  return string.format('%016x',h),bytes
end
function Core.unpack(chunks,recover)
  local data={segments={}};local current;local total=0
  local info={skipped=0,split=0}
  local function bad(message,header)
    if not recover then error(message,0) end
    info.skipped=info.skipped+1
    if header then current=nil end
  end
  for _,chunk in ipairs(chunks) do
    assert(type(chunk)=='string','保存データが不正です。')
    local wire=chunk
    if wire:sub(1,5)=='BLT2|' then
      local hash,body=wire:match('^BLT2|([%x]+)|(.*)$')
      if not hash or #hash~=16 or Core.history_hash({body})~=hash then
        bad('保存グラフの整合性検証に失敗しました。',true);wire=''
      else wire=body:gsub('|','\n') end
    elseif wire=='' then
      if recover then info.skipped=info.skipped+1 end
    else bad('不明な保存データ形式です。',true);wire='' end
    for line in wire:gmatch('[^\r\n]+') do
      line=line:match('^%s*(.-)%s*$')
      if line~='' then
        local f={};for v in (line..','):gmatch('(.-),') do f[#f+1]=v:match('^%s*(.-)%s*$') end
        if f[1]=='G' then
          local a,b,stamp=tonumber(f[2]),tonumber(f[3]),tonumber(f[5])
          if #f~=5 or not Core.finite(a) or not Core.finite(b) or b<=a or not Core.finite(stamp) or (f[4]~='0' and f[4]~='1') then
            bad('保存範囲が不正です。',true)
          elseif data.segments[#data.segments] and a<data.segments[#data.segments].last-1e-8 then
            bad('保存範囲が重複しています。',true)
          else
            current={first=a,last=b,rows={},stale=f[4]=='1',stamp=stamp}
            data.segments[#data.segments+1]=current
          end
        elseif f[1]=='R' then
          local r={time=tonumber(f[2])};local valid=current and #f==6
          local problem='保存データが不正です。'
          if valid then
            valid=Core.finite(r.time) and r.time>current.first and r.time<=current.last+1e-7
            problem='保存時刻が範囲外です。'
          end
          if valid then
            for j,k in ipairs({'s','m','rms','peak'}) do
              local v=tonumber(f[j+2])
              if f[j+2]~='x' and not Core.finite(v) then valid=false;problem='保存数値が不正です。';break end
              r[k]=v
            end
          end
          local prev=current and current.rows[#current.rows]
          if valid and prev and r.time<=prev.time+1e-9 then valid=false;problem='保存時刻が逆転または重複しています。' end
          if valid and prev and math.abs(r.time-prev.time-.1)>=1e-6 then
            if not recover then error('保存カーブが途切れています。',0) end
            -- Keep a genuine missing span as a gap. Never interpolate measurements.
            local stop=current.last;current.last=prev.time
            local first=max(prev.time,r.time-.1)
            current={first=first,last=stop,rows={},stale=current.stale,stamp=current.stamp}
            data.segments[#data.segments+1]=current;info.split=info.split+1
          end
          if valid then
            current.rows[#current.rows+1]=r;total=total+1;assert(total<=MAX_HISTORY_ROWS,'保存データが上限を超えています。')
          else bad(problem,false) end
        else bad('不明な保存データ形式です。',false) end
      end
    end
  end
  local kept={}
  for _,seg in ipairs(data.segments) do
    if #seg.rows>0 then kept[#kept+1]=seg elseif not recover then error('保存区間に測定点がありません。',0) end
  end
  data.segments=kept
  assert(#kept>0,'保存データに復元できる測定点がありません。')
  return data,info
end

function Core.loudness_line(seconds)
  local out={}
  local width,step,speed=76,2,4.6
  local travel=seconds*speed
  for x=0,width,step do
    local world=x+travel

    local y=7.2*sin(world*.105+.35)+3.8*sin(world*.047+1.55)+1.8*sin(world*.021+.4)
    local edge=min(1,x/8,(width-x)/8)
    out[#out+1]={x=x,y=y,a=max(0,edge)}
  end
  return out
end
function Core.axis_ticks(lo,hi,pixels)
  local step=Core.tick_step(hi-lo,pixels*3)
  local start=math.ceil(lo/step)*step;local out={};local previous

  for i=0,64 do
    local v=start+i*step
    if v>hi then break end
    if v>=lo and v~=previous then out[#out+1]=v;previous=v end
  end
  return out
end

-- Localization
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
 ["レンダー設定の復元に失敗: "]="Cannot restore render setting: ",
 ["保存区間が不正です。"]="Invalid saved section.",
 ["保存できる共通履歴は最大3.5時間です。古い履歴を整理してから再試行してください。"]="Shared history is limited to 3.5 hours. Remove old history, then retry.",
 ["保存範囲が不正です。"]="Invalid saved range.",
 ["保存範囲が重複しています。"]="Saved ranges overlap.",
 ["保存データが不正です。"]="Invalid saved data.",
 ["保存時刻が範囲外です。"]="Saved time is out of range.",
 ["保存カーブが途切れています。"]="Saved curve has gaps.",
 ["保存数値が不正です。"]="Invalid saved number.",
 ["保存データが上限を超えています。"]="Saved data exceeds limit.",
 ["不明な保存データ形式です。"]="Unknown saved data format.",
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
 ["処理中にエラーが発生しました。"]="An error occurred during processing.",
 ["LOUDNESS TRACEにはSWSとjs_ReaScriptAPIが必要です。\nSWS: https://www.sws-extension.org/\njs_ReaScriptAPI: ReaPackからインストール\n\n不足: "]="LOUDNESS TRACE requires SWS and js_ReaScriptAPI.\nSWS: https://www.sws-extension.org/\njs_ReaScriptAPI: install via ReaPack\n\nMissing: ",
 ["LOUDNESS TRACE | 必要な拡張"]="LOUDNESS TRACE | Required extensions",
 ["保存データが12 MiBの安全上限を超えました。測定範囲を短くしてください。"]="Saved data exceeds the 12 MiB safety limit. Shorten the measurement range.",
 ["保存情報が不正です。"]="Invalid saved information.",
 ["保存カーブが不足しています。"]="Missing saved curve data.",
 ["LOUDNESS TRACE: 表示トラックを作成"]="LOUDNESS TRACE: Create display track",
 ["描画用ビットマップを作成できません。"]="Cannot create drawing bitmap.",
 ["解析ソース"]="Source",
 ["前回の解析で残った可能性がある一時ファイルを%d件検出しました（合計 %s）。\n\n削除してよろしいですか？\n別のLOUDNESS TRACEが現在解析中の場合だけキャンセルしてください。"]="Found %d temporary files possibly left by an earlier analysis (total %s).\n\nDelete them?\nCancel if another LOUDNESS TRACE is currently analyzing.",
 ["LOUDNESS TRACE | 一時ファイル回収"]="LOUDNESS TRACE | Temporary files",
 ["長い範囲を解析するため、一時WAVを約 %s 作成します。\n解析中は同程度の空き容量が必要です。続行しますか？\n\n範囲：%.1f分"]="This range creates about %s of temporary WAV data.\nKeep this much disk space free during analysis. Continue?\n\nRange: %.1f min",
 ["LOUDNESS TRACE | 長尺解析"]="LOUDNESS TRACE | Long analysis",
 ["測定開始前にプロジェクトが切り替わりました。"]="Project changed before measurement started.",
 ["測定開始前に時間選択が変更されました。"]="Time selection changed before measurement started.",
 ["レンダーがキャンセルされたか、一時音声を開けません。"]="Render cancelled or temporary audio unavailable.",
 ["LOUDNESS TRACE | 解析"]="LOUDNESS TRACE | Analysis",
 ["LOUDNESS TRACE | 保存"]="LOUDNESS TRACE | Save",
 ["目標"]="Aim",
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
 ["グラフ ON"]="Graph ON",
 ["グラフ OFF"]="Graph OFF",
 ["LOUDNESS TRACEはWindows／macOS用です。"]="LOUDNESS TRACE requires Windows or macOS.",
 ["現在のMetal設定ではグラフを重ね描画できません。REAPERの高度なUI設定でMetalを無効にするか、描画互換モードを選び、必要に応じてREAPERを再起動してください。"]="The current Metal mode cannot display the graph overlay. Disable Metal or enable drawing compatibility in REAPER's advanced UI settings, then restart REAPER if needed.",
 ["リアルタイム"]="Real-time",
 ["リアルタイム測定をOFFにしました。グラフは保持します。"]="Real-time recording is OFF. Recorded graph retained.",
 ["リアルタイムOFF：記録したグラフを表示しています。"]="Real-time OFF: showing recorded graph.",
 ["リアルタイムON：再生するとグラフを記録します。"]="Real-time ON: play to record the graph.",
 ["リアルタイム描画中：100 ms単位で追記しています。"]="Recording the live graph in 100 ms steps.",
 ["リアルタイム待機：プロジェクトの再生速度を1.0にしてください。"]="Live standby: set project play rate to 1.0.",
 ["リアルタイム待機：音声のオンライン復帰を待っています。"]="Live standby: waiting for media to come online.",
 ["測定信号を待っています。音声デバイス・モニターFXを確認してください。"]="Waiting for meter data. Check audio device and monitoring FX.",
 ["リアルタイム履歴の上限に達しました。グラフを保持して測定をOFFにしました。"]="Live history limit reached. Graph retained; recording switched OFF.",
 ["リアルタイム結果を保存できませんでした。メモリ内のグラフは保持しています。"]="Cannot save live results. The graph remains in memory.",
 ["測定データの受信が遅れた区間は空白として保持します。"]="Late meter data: missing intervals are left blank.",
 ["リアルタイム測定の共有メモリを確保できません。ほかの測定をOFFにしてください。"]="Cannot reserve live meter memory. Switch other live meters OFF.",
 ["リアルタイム測定JSFXを保存できません。"]="Cannot save the live metering JSFX.",
 ["測定用トラックまたはFXが変更されているため、自動削除できませんでした。確認してください。"]="Meter track or FX was changed and could not be removed safely. Please inspect it.",
 ["リアルタイム測定JSFXを追加できません。FX一覧を再スキャンしてください。"]="Cannot add the metering JSFX. Rescan the FX list.",
 ["リアルタイム測定JSFXを確認できません。"]="Cannot identify the live metering JSFX.",
 ["測定用JSFXの設定に失敗しました。"]="Cannot configure the metering JSFX.",
 ["リアルタイム測定の接続が失われました。"]="Live metering connection was lost.",
 ["リアルタイム測定データが不正です。"]="Invalid live metering data.",
 ["リアルタイム測定に必要なREAPER APIがありません。REAPERを更新してください。"]="Required live metering API is unavailable. Update REAPER.",
 ["リアルタイム測定用FXが削除または移動されました。"]="Live metering FX was removed or moved.",
 ["モニターFXの順序が変更されたため、測定をOFFにしました。"]="Monitoring FX order changed. Live recording switched OFF.",
 ["リアルタイム測定用FXが無効です。"]="Live metering FX is disabled or offline.",
 ["測定先が変更されたため、リアルタイム測定をOFFにしました。"]="Measurement source changed. Live recording switched OFF.",
 ["音声に不正な値があるため、リアルタイム測定をOFFにしました。"]="Invalid audio values. Live recording switched OFF.",
 ["リアルタイム測定では標準的な8～384 kHzのサンプルレートを使用してください。"]="Use a standard sample rate from 8 to 384 kHz for live metering.",
 ["リアルタイム測定JSFXの内容が不正です。"]="Invalid embedded live meter JSFX.",
 ["既存のリアルタイム測定JSFXを読み取れません。権限を確認してください。"]="Cannot read an existing live meter JSFX. Check file permissions.",
 ["リアルタイム測定JSFXの書き込み検証に失敗しました。"]="Live meter JSFX write verification failed.",
 ["リアルタイム測定JSFXの通信形式が一致しません。測定をOFFにしました。"]="Live meter JSFX protocol mismatch. Live measurement was turned OFF.",
 ["マスターミックスの一時レンダーが複数ファイルになりました。"]="The master mix produced multiple temporary WAVs.",
 ["測定データのソースがマスターミックスではありません。"]="Measurement source is not the master mix.",
 ["集計データの対応が失われました。"]="History aggregation is inconsistent.",
 ["測定時刻が逆転しています。"]="Measurement time moved backwards.",
 ["共通グラフ：再生・解析した範囲を更新し、範囲外は保持します。"]="Shared graph: playback and analysis replace only the measured range.",
 ["マスタートラックを取得できません。"]="Cannot access the master track.",
 ["マスターのミュート／ソロ／モノ設定を解除するとLIVE測定できます。"]="Disable master mute/solo/mono monitoring to enable LIVE measurement.",
 ["モニターFXがバイパス中のためLIVE測定を待機しています。"]="LIVE is waiting because Monitoring FX are bypassed.",
 ["別プロジェクトを停止するとLIVE測定できます。"]="Stop other projects before LIVE measurement.",
 ["LIVE測定には、マスター1/2を音量・パンロー0 dB、PAN中央のステレオで単独出力する経路が必要です。"]="LIVE needs an isolated stereo post-fader hardware route from master 1/2 at unity gain/pan law and centered pan.",
 ["ハードウェア出力のエンベロープ状態を確認できないため、LIVE測定できません。"]="Cannot verify hardware-output envelopes; LIVE measurement is unavailable.",
 ["ハードウェア出力の音量エンベロープが使用中のため、LIVE測定できません。"]="The hardware-output volume envelope is in use; LIVE measurement is unavailable.",
 ["ハードウェア出力のPANエンベロープが使用中のため、LIVE測定できません。"]="The hardware-output pan envelope is in use; LIVE measurement is unavailable.",
 ["ハードウェア出力のミュートエンベロープが使用中のため、LIVE測定できません。"]="The hardware-output mute envelope is in use; LIVE measurement is unavailable.",
 ["測定用JSFXのチャンネルを設定できません。"]="Cannot set meter JSFX channel mappings.",
 ["測定用JSFXのチャンネルを確認できません。"]="Cannot verify meter JSFX channel mappings.",
 ["FXウィンドウの自動表示設定を取得できません。"]="Cannot read automatic FX window preferences.",
 ["FXウィンドウの自動表示を抑制できません。"]="Cannot suppress automatic FX windows.",
 ["FXウィンドウの自動表示設定を復元できません。終了時に再試行します。"]="Cannot restore FX window preferences. Will retry before exit.",
 ["測定用JSFXのチャンネルが変更されたため、測定をOFFにしました。"]="Meter channel mappings changed; LIVE stopped.",
 ["ハードウェア出力の経路が変わりました。LIVEをOFFにして再度ONにしてください。"]="Hardware output routing changed. Switch LIVE off, then on again.",
 ['リアルタイム測定JSFXの更新用ファイルを読み取れません。']='Cannot read the meter update files.',
 ['リアルタイム測定JSFXの前回更新を復元できません。']='Cannot restore the previous meter installation.',
 ['リアルタイム測定JSFXの作業ファイルを削除できません。']='Cannot remove the meter temporary file.',
 ['リアルタイム測定JSFXの更新用ファイルを削除できません。']='Cannot remove the meter update backup.',
 ['リアルタイム測定JSFXを更新できません。']='Cannot update the meter JSFX.',
 ['起動済みの測定用JSFXを終了できません。']='Cannot remove the running BLT monitoring meter.',
 ['保存時刻が逆転または重複しています。']='Saved measurement times are reversed or duplicated.',
 ['保存区間に測定点がありません。']='A saved segment has no measurements.',
 ['保存データに復元できる測定点がありません。']='No recoverable measurements in the saved data.',
 ['保存情報を取得できません。']='Cannot read the history metadata.',
 ['グラフ保存の読み戻し検証に失敗しました。']='Saved graph read-back validation failed.',
 ['保存グラフの整合性検証に失敗しました。']='Saved graph integrity validation failed.',
 ['グラフ保存先を確保できません。']='Cannot allocate the graph snapshot.',
 ['前回の正常な保存からグラフを復元しました。直近の一部は再測定してください。']='Restored the previous valid snapshot. Remeasure the latest missing section.',
 ['保存グラフの正常な測定点を復元しました。欠けた区間だけ再測定してください。']='Recovered valid measurements. Remeasure only the missing sections.',
 ['保存グラフの形式を修復しました。測定値は保持しています。']='Repaired the saved graph format. Measurements were preserved.',
 ['グラフをメモリ内へ復元しましたが、保存できません。元の保存データは保持しています。']='Recovered graph in memory but could not save. Original stored data retained.',
 ['保存グラフを復元できません。元のデータは保持しています。']='Cannot recover the graph. Original stored data retained.',
 ['保存グラフの欠損データを退避しました。グラフをクリアせず再測定できます。']='Damaged graph data retained separately. You can measure again without clearing the graph.',
},patterns={
 {"^「(.*)」を上書きしますか？$","Overwrite \"%s\"?"},
 {"^レンダーが中断されたか、測定範囲と音声の長さが一致しません。\n予定: ([%+%-]?[%d%.eE]+) 秒 / 実際: ([%+%-]?[%d%.eE]+) 秒 / 差: ([%+%-]?[%d%.eE]+) ms$","Render interrupted or duration mismatch.\nExpected: %.6f s / Actual: %.6f s / Difference: %.3f ms"},
 {"^([%+%-]?[%d%.eE]+)–([%+%-]?[%d%.eE]+) / ([%+%-]?[%d%.eE]+)   スクロールで選択$","%d–%d / %d   Scroll to browse"},
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
 {"^保存済み：(.-)  /  (.-)$","Saved: %s  /  %s"},
 {"^(.-)区間  ·  選択範囲だけ置換$","%s sections · Replace selected range only"},
 {"^グラフ (.-)$","Graph %s"},
 {"^グラフ幅：(.-)$","Width:%s"},
 {"^解析を中止  (.-)%%$","Stop analysis  %s%%"},
 {"^(%d+)個インポートしました。$","Imported %s preset(s)."},
},prefixes={"LOUDNESS TRACEにはSWSとjs_ReaScriptAPIが必要です。\nSWS: https://www.sws-extension.org/\njs_ReaScriptAPI: ReaPackからインストール\n\n不足: ","レンダー設定を読み取れません: ","レンダー設定を変更できません: ","プリセットを読み込みました: ","レンダー設定の復元に失敗: ","プリセットを保存しました: ","保存済み：","グラフ幅：","現在: "}}

local Language=create_language(reaper,"LOUDNESS_TRACE",LanguageCatalog)

-- Platform drawing adapter
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

 if not P.mac then return P end
 local R=setmetatable({}, {__index=WindowGeometry});P.api=R
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

-- Shared UI / presets
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
  line=line:gsub('%s/[^%s:\r\n"<>|][^:\r\n"<>|]*','')

  line=line:gsub('[^%s:"<>|/]+/[^%s:"<>|]+',function(part)
   return part:match('%.[%a][%w%-]*$') and '' or part
  end)
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
local function clear_chrome_tooltip() if R.TrackCtl_SetToolTip then R.TrackCtl_SetToolTip('',0,0,true) end end
B.clearTooltip=clear_chrome_tooltip

function B.switch(x,y,state,enabled)
 local s,bx,by=host.geometry();local cy=by+(y+12)*s;local cx=bx+(x+7+12*state)*s
 local c=C.edge2;gfx.set(c[1],c[2],c[3],enabled and .45 or .2);gfx.line(bx+(x+3)*s,cy,bx+(x+23)*s,cy,1)
 c=C.faint;gfx.set(c[1],c[2],c[3],enabled and .8 or .4);gfx.circle(cx,cy,4.2*s,1,1)
 if state>.001 and enabled then c=C.accent;gfx.set(c[1],c[2],c[3],.06*state);gfx.circle(cx,cy,7*s,1,1);c=C.accent2;gfx.set(c[1],c[2],c[3],.94*state);gfx.circle(cx,cy,4.2*s,1,1) end
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

  Chrome.mouseActive=(Presets.open or Presets.swallow) or inBar or Chrome.drag~=nil or Chrome.resize~=nil or cursorMode~=nil
    or Chrome.languagePressed or Chrome.closePressed or Chrome.resetPressed or Chrome.chameleonPressed or Chrome.presetPressed or Chrome.presetPrevPressed or Chrome.presetNextPressed

  gfx.set(C.bg[1],C.bg[2],C.bg[3],1); gfx.rect(0,0,w,Chrome.titleH,1)
  gfx.gradrect(0,0,w,Chrome.titleH,C.field[1],C.field[2],C.field[3],.72,
    0,0,0,0,(C.bg[1]-C.field[1])/Chrome.titleH,(C.bg[2]-C.field[2])/Chrome.titleH,(C.bg[3]-C.field[3])/Chrome.titleH,.22/Chrome.titleH)
  gfx.set(C.edge[1],C.edge[2],C.edge[3],.42); gfx.line(0,Chrome.titleH-1,w,Chrome.titleH-1,1)

  if not Chrome.textFontsReady or Chrome.fontDPI~=(gfx.ext_retina or 1) then Chrome.fontDPI=gfx.ext_retina or 1;B.chromeFont(); Chrome.textFontsReady=true else B.chromeFont() end; B.fontKey="chrome"

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
  end
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
  end
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

function B.key(k)
 if k<0 then return k end
 if Presets.open then Presets.key(k);return 0 end
 local cap=gfx.mouse_cap or 0
 if (cap&24)~=0 or not (k==26 or ((cap&4)~=0 and (k==90 or k==122))) then return k end
 if host.editing() or host.modal() then return 0 end
 local function message(jp,en,ok) notice(Language.code=='EN' and en or jp,ok) end
 if host.busy() then message('処理中は元に戻せません。','Cannot undo during processing.',false);return 0 end
 local project=R.EnumProjects(-1,'');local entry=R.Undo_CanUndo2(project)
 if not entry or entry=='' then message('元に戻せる操作がありません。','Nothing to undo.',true);return 0 end
 local result=R.Undo_DoUndo2(project)
 if result==nil or result==false or result==0 then message('Undoを実行できませんでした。','Undo failed.',false);return 0 end
 R.UpdateArrange();host.undoRefresh(project);wake_visuals();message('元に戻しました。','Undone.',true)
 return 0
end
function B.tick(now)
 Media.tick()
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
 local blocked=Presets.open or Presets.swallow or host.modal()
 custom_titlebar(blocked)
 Presets.draw()
end

function B.logError(err)
 local message=B.publicError(err)
 if message~=B.lastLoggedError then
  B.lastLoggedError=message
  if R.ShowConsoleMsg then pcall(R.ShowConsoleMsg,message..'\n') end
 end
end

function B.title(title,subtitle,width,divider)
 scale,ox,oy=host.geometry();local origin=oy+22*scale
 B.font(35,2,true,scale,host.faces);gfx.set(C.text[1],C.text[2],C.text[3],1);gfx.x=ox+24*scale;gfx.y=origin+8*scale;gfx.drawstr(UI.fit(title,(width-150)*scale))
 B.font(10,1,false,scale,host.faces);gfx.set(C.accent2[1],C.accent2[2],C.accent2[3],1);gfx.x=ox+26*scale;gfx.y=origin+44*scale;gfx.drawstr(UI.fit(Language.text(subtitle),(width-155)*scale))
 if divider~=false then gfx.set(C.edge2[1],C.edge2[2],C.edge2[3],.26);gfx.line(ox+24*scale,origin+62*scale,ox+(width-24)*scale,origin+62*scale,1) end
end

function B.footer(message,bad,width,height,version)
 if Media.waiting then message=Media.message(host.section);bad=false end
 scale,ox,oy=host.geometry();message=Language.message(B.notice or tostring(message or ''))
 if B.notice then bad=B.noticeBad end
 local y=oy+(height-13)*scale
 B.font(8,3,true,scale,host.faces);local ver=version~='' and 'v'..version or '';local vw=UI.textMetrics(ver)
 local available=(width-48)*scale-vw-14*scale
 B.font(9,1,false,scale,host.faces);local shown=UI.fit(message,available)
 B.footerText=message;B.footerClipped=shown~=message;B.footerBounds={ox+24*scale,y,ox+24*scale+available,y+14*scale}
 gfx.set(C.edge[1],C.edge[2],C.edge[3],.26);gfx.line(ox+24*scale,y-3*scale,ox+(width-24)*scale,y-3*scale)
 local c=bad and C.warn or C.muted;gfx.set(c[1],c[2],c[3],1);gfx.x=ox+24*scale;gfx.y=y;gfx.drawstr(shown)
 B.font(8,3,true,scale,host.faces);gfx.set(C.faint[1],C.faint[2],C.faint[3],1);gfx.x=ox+(width-24)*scale-vw;gfx.y=y;gfx.drawstr(ver)
end
return B
end)()

local SECTION="LOUDNESS_TRACE"
local TAG="P_EXT:"..SECTION
local TEMP_WARNING_SECONDS=25*60
local TEMP_BYTES_PER_SECOND=48000*2*4
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
  alertUpper=false,alertLower=false,alertPeak=false}
-- LIVE meter / embedded JSFX
local Live={enabled=false,protocol=1,memory='BLT_LOUDNESS_TRACE_RT_V1',fx_relative='BLT/BLT_Loudness_Trace_Live.jsfx'}
Live.jsfx=[==[
desc:BLT Loudness Trace Live
// BLT managed LIVE meter; source revision 1.1.0.
// Measurement only: all audio and MIDI pass through unchanged.
// Private, bounded 100 ms energy queue shared with BLT_LOUDNESS_TRACE.lua.
options:gmem=BLT_LOUDNESS_TRACE_RT_V1
slider1:0<0,15,1>-BLT memory slot
slider2:0<0,16777215,1>-BLT owner token

@init
ext_noinit=1;
ext_nodenorm=1;
pdc_delay=0;
last_owner=0;
was_running=0;
seq=0;
epoch=0;

@block
base=floor(slider1)*8192;
owned=slider2>0 && gmem[base]===slider2;
owned ? (
  owner_changed=last_owner!==slider2;
  owner_changed ? (seq=0; epoch=0; was_running=0; last_owner=slider2;);
  placement=get_host_placement(chain_position,host_flags);
  active=placement==-2 && chain_position==0 && !(host_flags&4) && gmem[base+2]>0 && gmem[base+7]==0 && (play_state==1 || play_state==5);
  reset=owner_changed || last_reset!==gmem[base+4] || last_sr!==srate;
  last_reset=gmem[base+4];
  last_sr!==srate ? (
    last_sr=srate;
    // BS.1770 K weighting. At 48 kHz these match the offline analyzer.
    kk=tan($pi*1681.974450955533/srate);
    q=.7071752369554196;
    vh=10^(3.999843853973347/20);
    vb=vh^.4996667741545416;
    aa=1+kk/q+kk*kk;
    b0=(vh+vb*kk/q+kk*kk)/aa;
    b1=2*(kk*kk-vh)/aa;
    b2=(vh-vb*kk/q+kk*kk)/aa;
    a1=2*(kk*kk-1)/aa;
    a2=(1-kk/q+kk*kk)/aa;
    kk=tan($pi*38.13547087602444/srate);
    aa=1+kk/.5003270373238773+kk*kk;
    h1=2*(kk*kk-1)/aa;
    h2=(1-kk/.5003270373238773+kk*kk)/aa;
    hop=max(1,floor(srate*.1+.5));
    inv_sr=1/srate;
    reset=1;
  );
  active && (!was_running || abs(play_position-expected)>max(4/srate,.00005)) ? reset=1;
  reset ? (
    z1=0;z2=0;z3=0;z4=0;z5=0;z6=0;z7=0;z8=0;
    energy=0;raw=0;pk=0;n=0;
    epoch+=1;
    last_reset=gmem[base+4];
  );
  active && (srate<8000 || srate>384000 || abs(hop/srate-.1)>.0000001) ? (
    gmem[base+7]=2;active=0;
  );
  block_pos=play_position;
  block_i=0;
  expected=play_position+samplesblock/srate;
  was_running=active;
  gmem[base+5]=epoch;
  gmem[base+6]=srate;
  gmem[base+9]=1; // Protocol acknowledgment; only the current slot owner may publish.
  gmem[base+8]+=1;
) : (active=0;was_running=0;);

@sample
(active && gmem[base]===slider2) ? (
  ll=spl0;rr=spl1;
  !(ll===ll) || !(rr===rr) || abs(ll)>1000000000 || abs(rr)>1000000000 ? (
    gmem[base+7]=1;active=0;
  ) : (
    yl=b0*ll+z1;
    z1=b1*ll-a1*yl+z2;z2=b2*ll-a2*yl;
    kl=yl+z3;z3=-2*yl-h1*kl+z4;z4=yl-h2*kl;
    yr=b0*rr+z5;
    z5=b1*rr-a1*yr+z6;z6=b2*rr-a2*yr;
    kr=yr+z7;z7=-2*yr-h1*kr+z8;z8=yr-h2*kr;
    energy+=kl*kl+kr*kr;
    raw+=(ll*ll+rr*rr)*.5;
    pk=max(pk,max(abs(ll),abs(rr)));
    n+=1;
    n>=hop ? (
      seq+=1;
      addr=base+64+((seq-1)%512)*8;
      gmem[addr]=-seq;
      gmem[addr+1]=epoch;
      gmem[addr+2]=block_pos+(block_i+1)*inv_sr;
      gmem[addr+3]=energy/n;
      gmem[addr+4]=raw/n;
      gmem[addr+5]=pk;
      gmem[addr+6]=srate;
      gmem[addr+7]=slider2;
      gmem[addr]=seq;
      gmem[base+3]=seq;
      energy=0;raw=0;pk=0;n=0;
    );
  );
  block_i+=1;
);
]==]
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

local function warning_durations(data)
  if Live.run and data then return Live.warnings(data) end
  local c=BLT.warningCache;local a,b=S.targets.s,S.targets.m
  if c and c.data==data and c.a==a[1] and c.b==a[2] and c.c==b[1] and c.d==b[2] then return c[1],c[2],c[3] end
  local upper,lower,peak=0,0,0
  for _,row in ipairs(data and data.rows or {}) do
    local u,l,p=Core.row_warning(row,S.targets)
    upper=upper+u*.1;lower=lower+l*.1;peak=peak+p*.1
  end
  BLT.warningCache={upper,lower,peak,data=data,a=a[1],b=a[2],c=b[1],d=b[2]}
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
  A.graphContentKey=nil;A.graphCursorPixel=nil
  A.linked=false; A.cache=""; A.layoutCache=nil; A.paintRect=nil; A.hover=nil; A.lastArrangeMouseX=nil; A.mouseRepairQueue={}; A.mouseSweepMin=nil; A.mouseSweepMax=nil; A.lastMouseMoveAt=nil
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
  S.alertUpper=false;S.alertLower=false;S.alertPeak=false
  local _,raw=R.GetProjExtState(A.project,SECTION,'settings')
  local f={};for v in raw:gmatch('[^;]+') do f[#f+1]=v end
  if #f~=18 or f[1]~='master' then return end
  S.source='master';S.height=Core.clamp(tonumber(f[2]) or 280,180,800)
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
-- Snapshot ownership is explicit. Never delete by subtracting an enumeration
-- from the reference set: enumeration output/case is not an ownership proof.
-- Current graph storage
local History={key='result@master',backup='result_backup@master',recovery='result_recovery@master',failed='result_failed@master',failedBackup='result_failed_backup@master'}
History.references={History.key,History.backup,History.recovery,History.failed,History.failedBackup}
function History.manifest(raw)
  assert(type(raw)=='string' and #raw<=512,'保存情報が不正です。')
  local f={};for v in (raw..';'):gmatch('(.-);') do f[#f+1]=v end
  local n,stamp,bytes=tonumber(f[2]),tonumber(f[3]),tonumber(f[5])
  assert(#f==6 and f[1]:match('^[%x]+$') and #f[1]<=128 and n and n>=1 and n<=4096 and n%1==0
    and Core.finite(stamp) and f[4]=='2' and bytes and bytes>0 and bytes<=MAX_SAVE_BYTES
    and f[6]:match('^[%x]+$') and #f[6]==16,'保存情報が不正です。')
  return f[1]:lower(),n,stamp,bytes,f[6]:lower()
end
function History.raw(key)
  local _,value=R.GetProjExtState(A.project,SECTION,key:lower())
  assert(type(value)=='string','保存情報を取得できません。')
  return value
end
function History.put(key,value)
  local canonical=key:lower()
  R.SetProjExtState(A.project,SECTION,canonical,value)
  local _,check=R.GetProjExtState(A.project,SECTION,canonical)
  assert(check==value,'グラフ保存の読み戻し検証に失敗しました。')
end
function History.erase(key)
  if History.raw(key)~='' then History.put(key,'') end
end
function History.retire(raw)
  -- Retire known snapshots only after verified publication or clearing their references.
  if raw=='' then return end
  local parsed,id,n=pcall(History.manifest,raw);if not parsed then return end
  if not id:match('^[%x]+$') or #id<16 then return end
  local canonical=id:lower()
  for _,key in ipairs(History.references) do
    local value=History.raw(key)
    if value~='' then
      local owner=value:match('^([%w]+);')
      if owner and owner:lower()==canonical then return end

      if not owner and value:lower():find(canonical,1,true) then return end
    end
  end
  for i=1,n do History.erase(id..'_'..i) end
  History.erase(id..'_name')
end
function History.read(raw,recover,verifyOnly)
  if raw=='' then return nil end
  local id,n,_,expectedBytes,expectedHash=History.manifest(raw)
  local chunks,bytes={},0
  for i=1,n do
    local v=History.raw(id..'_'..i)
    if not recover then assert(v~='','保存カーブが不足しています。') end
    bytes=bytes+#v;assert(bytes<=MAX_SAVE_BYTES,'保存データが12 MiBの安全上限を超えました。測定範囲を短くしてください。')
    chunks[i]=v
  end
  if not recover then
    local hash,actualBytes=Core.history_hash(chunks)
    assert(actualBytes==expectedBytes and hash==expectedHash,'保存グラフの整合性検証に失敗しました。')
  end

  if verifyOnly and not recover then return true end
  local data,info=Core.unpack(chunks,recover)
  data.source='master';data.name='MASTER MIX · stereo 1/2'
  if not verifyOnly then Core.recompute(data) end
  return data,info
end
local function save_data(data,recovered)
  assert(data.source=='master','測定データのソースがマスターミックスではありません。')
  local chunks=Core.pack(data)
  local verified=Core.unpack(chunks);local rows=0
  for _,seg in ipairs(verified.segments) do rows=rows+#seg.rows end
  assert(rows<=MAX_HISTORY_ROWS,'保存できる共通履歴は最大3.5時間です。古い履歴を整理してから再試行してください。')
  local hash,bytes=Core.history_hash(chunks)
  assert(bytes<=MAX_SAVE_BYTES,'保存データが12 MiBの安全上限を超えました。測定範囲を短くしてください。')
  local old=History.raw(History.key)
  local snapshotKey=recovered and History.recovery or History.backup
  local previousSnapshot=History.raw(snapshotKey)
  local id=R.genGuid():gsub('[^%w]',''):lower()
  assert(id~='' and old:sub(1,#id):lower()~=id and History.raw(id..'_1')=='','グラフ保存先を確保できません。')
  local stamp=os.time()+(R.time_precise()%1)
  local manifest=string.format('%s;%d;%.6f;2;%d;%s',id,#chunks,stamp,bytes,hash)
  local written={};local switching=false
  local ok,why=xpcall(function()
    for i,chunk in ipairs(chunks) do
      local key=id..'_'..i;written[#written+1]=key;History.put(key,chunk)
    end
    local nameKey=id..'_name';written[#written+1]=nameKey;History.put(nameKey,data.name or '')
    History.read(manifest,false,true)
    if old~='' then History.put(snapshotKey,old) end
    switching=true;History.put(History.key,manifest)

    History.read(History.raw(History.key),false,true)
  end,debug.traceback)
  if not ok then
    if switching then pcall(History.put,History.key,old) end
    local read,current=pcall(History.raw,History.key)
    if read and current==old then
      pcall(History.put,snapshotKey,previousSnapshot)
      for _,key in ipairs(written) do pcall(History.erase,key) end
    end
    -- On an uncertain rollback, keep the new chunks rather than delete a possible owner.
    error(why,0)
  end
  A.historyBlocked=false;A.historyProblem=nil
  local cleaned,err=pcall(History.retire,previousSnapshot);if not cleaned then BLT.logError(err) end
  -- Retirement cannot turn a successful save into a missing-curve snapshot.
  History.read(History.raw(History.key),false,true)
end
function History.clear()
  local snapshots={}
  for _,key in ipairs(History.references) do
    snapshots[#snapshots+1]=History.raw(key);History.erase(key)
  end
  for _,raw in ipairs(snapshots) do History.retire(raw) end
end
local function load_data()
  A.data=nil;A.stale=false;A.historyBlocked=false;A.historyProblem=nil;A.historyRecovery=nil
  local raw=History.raw(History.key)
  local ok,result=pcall(History.read,raw)
  if ok then A.data=result;A.stale=result~=nil;return end
  -- Invalid persisted history starts a new measurement without a recovery prompt.
  History.clear()
  Live.run=nil;Live.previous=nil;Live.dirty=false;Live.notice=nil;Live.noticeBad=false
end

local function clear_measurement()
  if A.job then return end
  if Live.enabled then Live.stop() end
  Live.run=nil;Live.previous=nil;Live.dirty=false;Live.notice=nil;Live.noticeBad=false
  History.clear()
  A.historyBlocked=false;A.historyProblem=nil;A.historyRecovery=nil
  A.data=nil;A.stale=false
  A.revision=A.revision+1;A.cache='';A.hover=nil
  A.baseline=R.GetProjectStateChangeCount(A.project)
end

local function source_name() return 'MASTER MIX · stereo 1/2' end

local function ensure_track()
  A.track=find_track()
  if A.track then return end
  R.Undo_BeginBlock2(A.project)

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
  if Live.enabled or Live.dirty then Live.stop() end
  Live.project=nil;Live.run=nil;Live.previous=nil;Live.dirty=false;Live.notice=nil;Live.noticeBad=false
  unlink(); A.edit=nil; A.project=R.EnumProjects(-1,""); A.track=find_track()
  -- Validate stored history before displaying it; invalid history is cleared.
  load_settings();load_data()
  if create then ensure_track() end

  if valid_track() then S.visible=graph_track_is_visible() end
  A.revision=A.revision+1; A.baseline=R.GetProjectStateChangeCount(A.project)
end

-- LIVE acquisition
function Live.wake()
  A.revision=A.revision+1;A.cache='';A.hover=nil
  if BLT.host then BLT.host.wake() end
end
function Live.message(text,bad)
  Live.notice=text;Live.noticeBad=bad==true;Live.wake()
end
function Live.valid_project(project)
  if not project then return false end
  local i=0
  while true do local p=R.EnumProjects(i,'');if not p then return false end;if p==project then return true end;i=i+1 end
end
function Live.select_memory() R.gmem_attach(Live.memory) end
function Live.release_slot()
  if Live.base then
    Live.select_memory()
    if R.gmem_read(Live.base)==Live.token then
      R.gmem_write(Live.base+2,0);R.gmem_write(Live.base,0);R.gmem_write(Live.base+1,0)
    end
  end
  Live.base=nil;Live.slot=nil
end
function Live.reserve_slot()
  Live.select_memory();local now=R.time_precise()
  for slot=0,15 do
    local b=slot*8192;local owner,stamp=R.gmem_read(b),R.gmem_read(b+1)
    if owner==0 or now-stamp>30 or stamp>now+1 then
      local token=tonumber(R.genGuid():gsub('[^%x]',''):sub(1,6),16) or 1
      token=max(1,token)
      R.gmem_write(b+2,0);R.gmem_write(b,token);R.gmem_write(b+1,now)
      for i=3,9 do R.gmem_write(b+i,0) end
      Live.slot,Live.base,Live.token=slot,b,token;Live.readSeq=0
      return
    end
  end
  error('リアルタイム測定の共有メモリを確保できません。ほかの測定をOFFにしてください。',0)
end

function Live.file_contents(path)
  local f,err,code=io.open(path,'rb')
  if not f then
    -- Only ENOENT means missing. Access errors must never become permission to write.
    if code==2 then return nil,'missing' end
    return nil,'unreadable',err
  end
  local ok,body=pcall(f.read,f,131073)
  local closed,result=pcall(f.close,f)
  if not ok or not closed or not result then return nil,'unreadable',body end
  if not body then body='' end
  return body,#body>131072 and 'oversized' or 'read'
end
function Live.discard_install_temp(path)
  local ok,removed=pcall(os.remove,path)
  if ok and removed then return true end
  local _,state=Live.file_contents(path);if state=='missing' then return true end

  A.tempDeletePending[path]=R.time_precise()
  return false
end
function Live.meter_file()
  assert(type(Live.jsfx)=='string' and #Live.jsfx>0 and #Live.jsfx<=131072,'リアルタイム測定JSFXの内容が不正です。')
  local root=R.GetResourcePath()..'/Effects/'
  local path=root..Live.fx_relative
  local body,state=Live.file_contents(path)
  if state=='read' and body==Live.jsfx then
    Live.discard_install_temp(path..'.tmp');Live.discard_install_temp(path..'.bak');return path
  end
  assert(state~='unreadable','既存のリアルタイム測定JSFXを読み取れません。権限を確認してください。')
  -- Never replace the source of a running meter, even if called outside startup.
  Live.remove_monitor_meters()
  R.RecursiveCreateDirectory(root..'BLT',0)
  local temp,backup=path..'.tmp',path..'.bak'
  local _,backupState=Live.file_contents(backup)
  assert(backupState~='unreadable','リアルタイム測定JSFXの更新用ファイルを読み取れません。')
  if state=='missing' and backupState~='missing' then
    assert(os.rename(backup,path),'リアルタイム測定JSFXの前回更新を復元できません。')
    body,state=Live.file_contents(path)
    if state=='read' and body==Live.jsfx then Live.discard_install_temp(temp);return path end
  end
  local moved=false
  local ok,why=xpcall(function()
    -- A single temporary file and backup keep failed updates bounded as well.
    local _,temporaryState=Live.file_contents(temp)
    assert(temporaryState~='unreadable','リアルタイム測定JSFXの更新用ファイルを読み取れません。')
    if temporaryState~='missing' then assert(os.remove(temp),'リアルタイム測定JSFXの作業ファイルを削除できません。') end
    local f,err=io.open(temp,'wb');assert(f,err or 'リアルタイム測定JSFXを保存できません。')
    local called,written,werr=pcall(f.write,f,Live.jsfx)
    local closed,result=pcall(f.close,f)
    assert(called and written and closed and result,werr or 'リアルタイム測定JSFXを保存できません。')
    assert(Live.file_contents(temp)==Live.jsfx,'リアルタイム測定JSFXの書き込み検証に失敗しました。')
    local _,oldBackup=Live.file_contents(backup)
    if oldBackup~='missing' then assert(os.remove(backup),'リアルタイム測定JSFXの更新用ファイルを削除できません。') end
    local _,current=Live.file_contents(path)
    assert(current~='unreadable','既存のリアルタイム測定JSFXを読み取れません。権限を確認してください。')
    if current~='missing' then assert(os.rename(path,backup),'リアルタイム測定JSFXを更新できません。');moved=true end
    assert(os.rename(temp,path),'リアルタイム測定JSFXを保存できません。')
    assert(Live.file_contents(path)==Live.jsfx,'リアルタイム測定JSFXの書き込み検証に失敗しました。')
  end,debug.traceback)
  if not ok then
    if moved then
      -- Restore the last complete source on failure; do not discard a failed rollback.
      local _,current=Live.file_contents(path)
      if current~='missing' then os.remove(path) end
      local restored=os.rename(backup,path)
      if not restored then why=tostring(why)..'\nリアルタイム測定JSFXの前回更新を復元できません。' end
    end
    Live.discard_install_temp(temp)
    error(why,0)
  end
  if moved then Live.discard_install_temp(backup) end
  return path
end

function Live.relative_fx_name(name)
  name=tostring(name or ''):gsub('^JS:%s*',''):gsub('\\','/')
  local root=(R.GetResourcePath()..'/Effects/'):gsub('\\','/')
  local compare,base=name,root
  if Platform.windows then compare,base=compare:lower(),base:lower() end
  if compare:sub(1,#base)==base then name=name:sub(#root+1) end
  return name
end
function Live.find_fx(host,guid)
  if not host or not guid then return end
  for i=0,R.TrackFX_GetRecCount(host)-1 do
    local index=0x1000000+i
    if R.TrackFX_GetFXGUID(host,index)==guid then return index end
  end
end
function Live.is_meter(host,index)
  local ok,name=R.TrackFX_GetNamedConfigParm(host,index,'fx_ident')
  if not ok then return false end
  name=Live.relative_fx_name(name)
  if Platform.windows then return name:lower()==Live.fx_relative:lower() end
  return name==Live.fx_relative
end
-- Startup owns only BLT's dedicated monitoring meters, never other monitor FX.
function Live.remove_monitor_meters()
  local project=R.EnumProjects(-1,'');local host=R.GetMasterTrack(project)
  if not host then return end
  for i=R.TrackFX_GetRecCount(host)-1,0,-1 do
    local index=0x1000000+i
    if Live.is_meter(host,index) then
      local guid=R.TrackFX_GetFXGUID(host,index)
      local slot,token=R.TrackFX_GetParam(host,index,0),R.TrackFX_GetParam(host,index,1)
      if Core.finite(slot) and slot%1==0 and slot>=0 and slot<=15 and Core.finite(token) and token>0 then
        Live.select_memory();local base=slot*8192
        if R.gmem_read(base)==token then
          R.gmem_write(base+2,0);R.gmem_write(base,0);R.gmem_write(base+1,0)
        end
      end
      if R.TrackFX_Show then R.TrackFX_Show(host,index,2) end
      assert(R.TrackFX_Delete(host,index)~=false and not Live.find_fx(host,guid),'起動済みの測定用JSFXを終了できません。')
    end
  end
end
function Live.prepare_install()
  Live.remove_monitor_meters()
  Live.meter_file()
end
function Live.slot_alive(host,index)
  local slot=R.TrackFX_GetParam(host,index,0);local token=R.TrackFX_GetParam(host,index,1)
  if not Core.finite(slot) or slot%1~=0 or not Core.finite(token) or token%1~=0 or token<=0 or slot<0 or slot>15 then return false end
  Live.select_memory();local b=floor(slot+.5)*8192;local age=R.time_precise()-R.gmem_read(b+1)
  return R.gmem_read(b)==token and age>=-1 and age<=30
end
function Live.recover_orphans(project)
  local master=R.GetMasterTrack(project)
  for i=R.TrackFX_GetRecCount(master)-1,0,-1 do
    local index=0x1000000+i
    if Live.is_meter(master,index) and R.TrackFX_GetParam(master,index,1)>0 and not Live.slot_alive(master,index) then
      R.TrackFX_Delete(master,index)
    end
  end
end
function Live.disconnect()
  if Live.base then Live.select_memory();if R.gmem_read(Live.base)==Live.token then R.gmem_write(Live.base+2,0) end end
  local host=R.GetMasterTrack(R.EnumProjects(-1,''));local clean=true
  local idx=Live.find_fx(host,Live.guid)
  if idx then clean=R.TrackFX_Delete(host,idx)~=false and Live.find_fx(host,Live.guid)==nil end
  Live.release_slot();Live.host=nil;Live.guid=nil;Live.fxIndex=nil;Live.connecting=nil;Live.route=nil
  Live.restore_fx_preference()
  if not clean then Live.message('測定用トラックまたはFXが変更されているため、自動削除できませんでした。確認してください。',true) end
  return clean
end

-- P_ENV may return an allocated envelope even when no automation is in use.

function Live.hardware_envelopes_unused(project,track,index)
  local unknown='ハードウェア出力のエンベロープ状態を確認できないため、LIVE測定できません。'
  local entries={
    {'VOLENV','ハードウェア出力の音量エンベロープが使用中のため、LIVE測定できません。'},
    {'PANENV','ハードウェア出力のPANエンベロープが使用中のため、LIVE測定できません。'},
    {'MUTEENV','ハードウェア出力のミュートエンベロープが使用中のため、LIVE測定できません。'},
  }
  local function integer(v) return Core.finite(v) and v>=0 and v%1==0 end
  for _,entry in ipairs(entries) do
    local got,env=pcall(R.GetTrackSendInfo_Value,track,1,index,'P_ENV:<'..entry[1])
    if not got then return false,unknown end
    if env and env~=0 then
      local valid,exists=pcall(R.ValidatePtr2,project,env,'TrackEnvelope*')
      if not valid or exists~=true then return false,unknown end
      local counted,points=pcall(R.CountEnvelopePoints,env)
      local listed,items=pcall(R.CountAutomationItems,env)
      local read,state=pcall(R.GetEnvelopeUIState,env)
      if not counted or not listed or not read or not integer(points) or not integer(items) or not integer(state) or state>7 then
        return false,unknown
      end
      -- Stored points/automation items remain conservatively unsupported, even
      -- when currently bypassed. Empty envelopes that are playing or writing
      -- automation are not safe either. Visibility alone is irrelevant.
      if points>0 or items>0 or (state&3)~=0 then return false,entry[2] end
    end
  end
  return true
end

-- Monitoring FX receive hardware-output audio, not an unconditional master tap.
-- Accept only an unmixed unity stereo post-fader route from master channels 1/2.
-- Never alter the user's sends, hardware levels, master fader, pan, or monitor FX.
function Live.route_for_master(project)
  local master=R.GetMasterTrack(project)
  if not master or not R.ValidatePtr2(project,master,'MediaTrack*') then return nil,'マスタートラックを取得できません。' end
  if (R.GetMasterMuteSoloFlags()&7)~=0 then return nil,'マスターのミュート／ソロ／モノ設定を解除するとLIVE測定できます。' end
  if R.SNM_GetIntConfigVar('hwoutfx_bypass',0)~=0 then return nil,'モニターFXがバイパス中のためLIVE測定を待機しています。' end
  for i=0,1023 do
    local p=R.EnumProjects(i,'');if not p then break end
    if p~=project and (R.GetPlayStateEx(p)&1)~=0 then return nil,'別プロジェクトを停止するとLIVE測定できます。' end
  end
  local function value(track,i,key) return R.GetTrackSendInfo_Value(track,1,i,key) end
  local function unity_panlaw(index)
    local law=value(master,index,'D_PANLAW')
    if law==-1 then
      if type(R.get_config_var_string)=='function' then
        local ok,raw=R.get_config_var_string('panlaw');law=ok and tonumber(raw) or nil
      elseif type(R.SNM_GetDoubleConfigVar)=='function' then law=R.SNM_GetDoubleConfigVar('panlaw',-1) end
    end
    return Core.finite(law) and math.abs(law-1)<1e-12
  end
  local function overlap(track,i,channel)
    if value(track,i,'B_MUTE')~=0 then return false end
    local src,dst=value(track,i,'I_SRCCHAN'),value(track,i,'I_DSTCHAN')
    if not Core.finite(src) or not Core.finite(dst) then return true end
    src,dst=floor(src),floor(dst)
    if src<0 then return false end
    local start=dst&1023;local mode=src>>10
    local count=(dst&1024)~=0 and 1 or mode==0 and 2 or mode==1 and 1 or mode*2
    return start<channel+2 and start+count>channel
  end
  local count=R.GetTrackNumSends(master,1)
  local outputs=R.GetNumAudioOutputs();local envelopeProblem
  for index=0,count-1 do
    local dst=value(master,index,'I_DSTCHAN')
    if Core.finite(dst) and dst%1==0 and dst>=0 and dst<=62 and dst+2<=outputs
      and value(master,index,'I_SRCCHAN')==0 and value(master,index,'I_SENDMODE')==0
      and value(master,index,'B_MUTE')==0 and value(master,index,'B_PHASE')==0 and value(master,index,'B_MONO')==0
      and math.abs(value(master,index,'D_VOL')-1)<1e-12 and math.abs(value(master,index,'D_PAN'))<1e-12
      and unity_panlaw(index) then
      local unused,why=Live.hardware_envelopes_unused(project,master,index)
      if not unused then envelopeProblem=envelopeProblem or why end
      local isolated=unused
      if isolated then
        for i=0,count-1 do if i~=index and overlap(master,i,dst) then isolated=false;break end end
      end
      if isolated then
        for ti=0,R.CountTracks(project)-1 do
          local tr=R.GetTrack(project,ti)
          for si=0,R.GetTrackNumSends(tr,1)-1 do if overlap(tr,si,dst) then isolated=false;break end end
          if not isolated then break end
        end
      end
      if isolated then return {index=index,channel=dst,master=master} end
    end
  end
  return nil,envelopeProblem or 'LIVE測定には、マスター1/2を音量・パンロー0 dB、PAN中央のステレオで単独出力する経路が必要です。'
end
function Live.pin_mask(channel)
  return channel<32 and (1<<channel) or 0,channel>=32 and (1<<(channel-32)) or 0
end
function Live.map_meter(host,index,channel)
  for output=0,1 do for pin=0,1 do
    local lo,hi=Live.pin_mask(channel+pin)
    assert(R.TrackFX_SetPinMappings(host,index,output,pin,lo,hi),'測定用JSFXのチャンネルを設定できません。')
    local a,b=R.TrackFX_GetPinMappings(host,index,output,pin)
    assert((a&0xffffffff)==lo and (b&0xffffffff)==hi,'測定用JSFXのチャンネルを確認できません。')
  end end
end
function Live.add_meter_quiet(host)
  local previous=R.SNM_GetIntConfigVar('fxfloat_focus',-2147483647)
  assert(previous~=-2147483647,'FXウィンドウの自動表示設定を取得できません。')
  local visible=R.TrackFX_GetRecChainVisible(host)
  local selected=visible>=0 and R.TrackFX_GetFXGUID(host,0x1000000|(visible&0xffffff)) or nil
  local focus=R.JS_Window_GetFocus and R.JS_Window_GetFocus()
  local idx;local before={}
  for i=0,R.TrackFX_GetRecCount(host)-1 do local id=R.TrackFX_GetFXGUID(host,0x1000000+i);if id then before[id]=true end end
  local ok,why=xpcall(function()
    -- &4 auto-float; !&128 auto-open quick-add. Also prevent focus/chain replacement.
    local quiet=(previous&(~(1|2|4|16|32|64)))|8|128|65536
    Live.restoreFXPreference=previous
    assert(R.SNM_SetIntConfigVar('fxfloat_focus',quiet)~=false,'FXウィンドウの自動表示を抑制できません。')
    assert(R.SNM_GetIntConfigVar('fxfloat_focus',-1)==quiet,'FXウィンドウの自動表示を抑制できません。')
    idx=R.TrackFX_AddByName(host,'JS: '..Live.fx_relative,true,-1000)
    assert(idx and idx>=0,'リアルタイム測定JSFXを追加できません。FX一覧を再スキャンしてください。')
    idx=0x1000000|(idx&0xffffff);Live.fxIndex=idx
    Live.guid=assert(R.TrackFX_GetFXGUID(host,idx))
  end,debug.traceback)
  if not ok and not Live.guid then
    for i=0,R.TrackFX_GetRecCount(host)-1 do
      local n=0x1000000+i;local id=R.TrackFX_GetFXGUID(host,n)
      if id and not before[id] and Live.is_meter(host,n) then Live.guid=id;idx=n;Live.fxIndex=n;break end
    end
  end
  -- All cleanup is attempted independently; a failed add must not leave preferences changed.
  local shown,showerr=pcall(function()
    if idx and idx>=0 then R.TrackFX_Show(host,idx,2) end
    if visible==-1 then R.TrackFX_Show(host,0x1000000,0)
    elseif selected then
      local old=Live.find_fx(host,selected)
      if old then R.TrackFX_Show(host,old,1) end
    end
  end)
  local restored,result=pcall(R.SNM_SetIntConfigVar,'fxfloat_focus',previous)
  if not restored or result==false or R.SNM_GetIntConfigVar('fxfloat_focus',-1)~=previous then
    Live.restoreFXPreference=previous
    error('FXウィンドウの自動表示設定を復元できません。終了時に再試行します。',0)
  end
  Live.restoreFXPreference=nil
  if focus and R.JS_Window_IsWindow(focus) and R.JS_Window_SetFocus then pcall(R.JS_Window_SetFocus,focus) end
  if not ok then error(why,0) end
  if not shown then error(showerr,0) end
  return idx
end
function Live.restore_fx_preference()
  if Live.restoreFXPreference==nil then return end
  local old=Live.restoreFXPreference
  if R.SNM_SetIntConfigVar('fxfloat_focus',old)~=false and R.SNM_GetIntConfigVar('fxfloat_focus',-1)==old then Live.restoreFXPreference=nil end
end
function Live.connect()
  local project=A.project
  assert(project==R.EnumProjects(-1,''),'プロジェクトが切り替わりました。')
  Live.project=project;Live.source='master';Live.host=R.GetMasterTrack(project)
  local route,why=Live.route_for_master(project);assert(route,why)
  Live.route=route;Live.routeAt=0;Live.routeRevision=nil;Live.checkedRoute=nil
  Live.recover_orphans(project);Live.meter_file();Live.reserve_slot()
  local idx=Live.add_meter_quiet(Live.host)
  assert(Live.is_meter(Live.host,idx),'リアルタイム測定JSFXを確認できません。')
  Live.map_meter(Live.host,idx,route.channel)
  assert(R.TrackFX_SetParam(Live.host,idx,0,Live.slot)~=false and R.TrackFX_SetParam(Live.host,idx,1,Live.token)~=false,'測定用JSFXの設定に失敗しました。')
  assert(R.TrackFX_GetParam(Live.host,idx,0)==Live.slot and R.TrackFX_GetParam(Live.host,idx,1)==Live.token,'測定用JSFXの設定に失敗しました。')
  R.TrackFX_SetNamedConfigParm(Live.host,idx,'renamed_name','BLT LOUDNESS TRACE [LIVE]')
  Live.startedAt=R.time_precise();Live.checkAt=0;Live.readSeq=0;Live.epoch=nil;Live.wasPlaying=false;Live.prevPos=nil
  A.baseline=R.GetProjectStateChangeCount(project)
end

function Live.finish_run()
  if not Live.run then return end
  if A.data then Core.recompute(A.data) end
  Live.run=nil;Live.previous=nil;Live.warningCache=nil;Live.wake()
end
function Live.save()
  if not Live.dirty or not A.data then return true end
  if not Live.valid_project(Live.project or A.project) then return false end

  local ok,err=pcall(save_data,A.data)
  if ok then Live.dirty=false;A.baseline=R.GetProjectStateChangeCount(A.project)
  else Live.message('リアルタイム結果を保存できませんでした。メモリ内のグラフは保持しています。',true);BLT.logError(err) end
  return ok
end
function Live.accept(packet)
  local run=Live.run;local time=packet.time
  if run and (packet.epoch~=run.epoch or math.abs(time-run.last-.1)>1e-6 or packet.srate~=run.srate) then Live.finish_run();run=nil end
  if not run then
    Live.previous=A.data
    Live.stamp=max(os.time()+(R.time_precise()%1),(Live.stamp or 0)+.000001)
    run={first=time-.1,last=time-.1,origin=time-.1,rows={},stamp=Live.stamp,epoch=packet.epoch,srate=packet.srate,meter=Core.live_meter(),summary=Core.history_summary(Live.previous,time-.1,S.targets)}
    Live.run=run
  end
  local row=run.meter.feed(time,packet.energy,packet.raw,packet.peak)
  run.integrated,run.lra=run.summary.feed(row)
  run.rows[#run.rows+1]=row;run.last=time
  Core.live_lod_append(run,row)
  local data=Core.live_view(Live.previous,run,'master',source_name())
  if data.liveCount>MAX_HISTORY_ROWS or #data.segments>2048 then
    -- Refuse the overflowing row, keeping the previous valid graph intact.
    run.rows[#run.rows]=nil;Live.run=nil;Live.previous=nil
    if A.data then Core.recompute(A.data) end
    error('リアルタイム履歴の上限に達しました。グラフを保持して測定をOFFにしました。',0)
  end
  A.data=data;A.stale=false;Live.dirty=true;Live.latest=row;Live.lastPacketAt=R.time_precise();Live.phase='writing';Live.wake()
end
function Live.pull(limit,final)
  if not Live.base then return end
  Live.select_memory();local base=Live.base
  assert(R.gmem_read(base)==Live.token,'リアルタイム測定の接続が失われました。')
  if R.gmem_read(base+8)>0 then
    assert(R.gmem_read(base+9)==Live.protocol,'リアルタイム測定JSFXの通信形式が一致しません。測定をOFFにしました。')
  end
  local head=R.gmem_read(base+3);local epoch=R.gmem_read(base+5)
  assert(Core.finite(head) and head>=0 and head%1==0 and head<2^45,'リアルタイム測定データが不正です。')
  if head<Live.readSeq then Live.readSeq=0;Live.finish_run() end
  if head-Live.readSeq>512 then Live.readSeq=head-512;Live.finish_run();Live.message('測定データの受信が遅れた区間は空白として保持します。',true) end
  local stop=min(head,Live.readSeq+512)
  for seq=Live.readSeq+1,stop do
    local at=base+64+((seq-1)%512)*8
    if R.gmem_read(at)~=seq then break end
    local p={epoch=R.gmem_read(at+1),time=R.gmem_read(at+2),energy=R.gmem_read(at+3),raw=R.gmem_read(at+4),peak=R.gmem_read(at+5),srate=R.gmem_read(at+6)}
    if R.gmem_read(at)~=seq or R.gmem_read(at+7)~=Live.token then break end
    if p.epoch==epoch or final then
      assert(Core.finite(p.time) and Core.finite(p.energy) and p.energy>=0 and Core.finite(p.raw) and p.raw>=0
        and Core.finite(p.peak) and p.peak>=0 and Core.finite(p.srate) and p.srate>=8000 and p.srate<=384000,'リアルタイム測定データが不正です。')
      if not final and p.time>limit+.005 then break end
      if not limit or p.time<=limit+.005 then Live.accept(p) end
    end
    Live.readSeq=seq
  end
end
function Live.stop(message)
  Live.enabled=false
  if Live.base then
    Live.select_memory();if R.gmem_read(Live.base)==Live.token then R.gmem_write(Live.base+2,0) end
    if Live.project==R.EnumProjects(-1,'') then
      local route=Live.route_for_master(Live.project)
      if route and Live.route and route.index==Live.route.index and route.channel==Live.route.channel then
        local ok,err=pcall(Live.pull,Live.lastPos,true);if not ok then BLT.logError(err) end
      end
    end
  end
  local ok,err=pcall(Live.finish_run);if not ok then Live.run=nil;Live.previous=nil;BLT.logError(err) end
  local disconnected,why=pcall(Live.disconnect);if not disconnected then BLT.logError(why);Live.release_slot() end
  local saved=Live.save();Live.phase='off';Live.wasPlaying=false;Live.latest=nil
  if message and saved and not Live.noticeBad then Live.message(message,false) else Live.wake() end
  return saved
end
function Live.toggle()
  if Live.enabled then Live.stop('リアルタイム測定をOFFにしました。グラフは保持します。');return end
  if A.job then return end
  Live.notice=nil;Live.noticeBad=false
  local ok,err=xpcall(function()
    local required={'gmem_attach','gmem_read','gmem_write','TrackFX_AddByName','TrackFX_GetFXGUID','TrackFX_GetNamedConfigParm','TrackFX_GetRecCount',
      'TrackFX_SetParam','TrackFX_GetParam','TrackFX_Delete','GetTrackNumSends','GetTrackSendInfo_Value',
      'TrackFX_GetRecChainVisible','TrackFX_Show','TrackFX_SetPinMappings','TrackFX_GetPinMappings','GetNumAudioOutputs','GetMasterMuteSoloFlags'}
    for _,name in ipairs(required) do assert(type(R[name])=='function','リアルタイム測定に必要なREAPER APIがありません。REAPERを更新してください。') end
    assert(not A.historyBlocked,A.historyProblem or '保存グラフを復元できません。元のデータは保持しています。')
    set_graph_track_visible(true)
    R.PreventUIRefresh(1)
    Live.connecting=true
    local connected,why=xpcall(Live.connect,debug.traceback)
    R.PreventUIRefresh(-1)
    if not connected then error(why,0) end
    Live.connecting=nil;Live.enabled=true;Live.phase='waiting';Live.lastPacketAt=nil;Live.lastPos=nil
    Live.wake()
  end,debug.traceback)
  if not ok then Live.stop();Live.message(public_error(err),true) end
end
function Live.check_connection()
  local host=R.GetMasterTrack(A.project)
  assert(host and R.ValidatePtr2(A.project,host,'MediaTrack*'),'マスタートラックを取得できません。')
  local idx=Live.find_fx(host,Live.guid)
  assert(idx and Live.is_meter(host,idx),'リアルタイム測定用FXが削除または移動されました。')
  assert(idx==0x1000000,'モニターFXの順序が変更されたため、測定をOFFにしました。')
  assert(R.TrackFX_GetEnabled(host,idx) and not R.TrackFX_GetOffline(host,idx),'リアルタイム測定用FXが無効です。')
  assert(R.TrackFX_GetParam(host,idx,0)==Live.slot and R.TrackFX_GetParam(host,idx,1)==Live.token,'測定用JSFXの設定に失敗しました。')
  for output=0,1 do for pin=0,1 do
    local lo,hi=Live.pin_mask(Live.route.channel+pin);local a,b=R.TrackFX_GetPinMappings(host,idx,output,pin)
    assert((a&0xffffffff)==lo and (b&0xffffffff)==hi,'測定用JSFXのチャンネルが変更されたため、測定をOFFにしました。')
  end end
end

function Live.tick(now)
  if not Live.enabled then return end
  local ok,err=xpcall(function()
    assert(A.project==Live.project and S.source==Live.source,'測定先が変更されたため、リアルタイム測定をOFFにしました。')
    Live.select_memory();assert(R.gmem_read(Live.base)==Live.token,'リアルタイム測定の接続が失われました。')
    R.gmem_write(Live.base+1,now)
    if now>=(Live.checkAt or 0) then Live.check_connection();Live.checkAt=now+.5 end
    if R.gmem_read(Live.base+8)>0 then
      assert(R.gmem_read(Live.base+9)==Live.protocol,'リアルタイム測定JSFXの通信形式が一致しません。測定をOFFにしました。')
    end
    local errorCode=R.gmem_read(Live.base+7)
    assert(errorCode~=1,'音声に不正な値があるため、リアルタイム測定をOFFにしました。')
    assert(errorCode~=2,'リアルタイム測定では標準的な8～384 kHzのサンプルレートを使用してください。')
    local playing=(R.GetPlayStateEx(A.project)&1)~=0
    local ready=Media.ready();local rate=R.Master_GetPlayRate(A.project)
    local revision=R.GetProjectStateChangeCount(A.project)
    local route,routeWhy
    if revision~=Live.routeRevision or now>=(Live.routeAt or 0) then
      route,routeWhy=Live.route_for_master(A.project)
      Live.routeRevision=revision;Live.routeAt=now+.1;Live.checkedRoute=route;Live.checkedRouteProblem=routeWhy
    else route,routeWhy=Live.checkedRoute,Live.checkedRouteProblem end
    local routeOK=route and route.channel==Live.route.channel and route.index==Live.route.index
    if not routeOK then
      R.gmem_write(Live.base+2,0)
      Live.readSeq=R.gmem_read(Live.base+3)
      Live.finish_run();Live.save()
      if Live.phase~='routing' then R.gmem_write(Live.base+4,R.gmem_read(Live.base+4)+1) end
      Live.wasPlaying=false;Live.routeProblem=routeWhy or 'ハードウェア出力の経路が変わりました。LIVEをOFFにして再度ONにしてください。'
      if Live.phase~='routing' then Live.phase='routing';Live.wake() end
      return
    end
    Live.routeProblem=nil
    local allowed=playing and ready and math.abs(rate-1)<1e-6
    R.gmem_write(Live.base+2,allowed and 1 or 0)
    if allowed then
      local pos=R.GetPlayPositionEx(A.project)
      Live.lastPos=pos;Live.pull(pos,false)
      if not Live.wasPlaying then Live.startedAt=now end
      local phase=now-(Live.lastPacketAt or Live.startedAt)>2 and 'signal' or (Live.run and 'writing' or 'waiting')
      if phase~=Live.phase then Live.phase=phase;Live.wake() end
    else
      if Live.wasPlaying then
        Live.pull(Live.lastPos,true);Live.finish_run();Live.save()
        Live.select_memory();R.gmem_write(Live.base+4,R.gmem_read(Live.base+4)+1)
        Live.readSeq=R.gmem_read(Live.base+3)
      end
      local phase=not ready and 'offline' or math.abs(rate-1)>=1e-6 and 'rate' or 'waiting'
      if phase~=Live.phase then Live.phase=phase;Live.wake() end
    end
    Live.wasPlaying=allowed
  end,debug.traceback)
  if not ok then Live.stop();Live.message(public_error(err),true) end
end
function Live.status()
  if Live.noticeBad then return Live.notice,true end
  if Live.enabled then
    if Live.phase=='routing' then return Live.routeProblem,true end
    if Live.phase=='rate' then return 'リアルタイム待機：プロジェクトの再生速度を1.0にしてください。',true end
    if Live.phase=='offline' then return 'リアルタイム待機：音声のオンライン復帰を待っています。',false end
    if Live.phase=='signal' then return '測定信号を待っています。音声デバイス・モニターFXを確認してください。',true end
    return Live.phase=='writing' and 'リアルタイム描画中：100 ms単位で追記しています。' or 'リアルタイムON：再生するとグラフを記録します。',false
  end
  return Live.notice or 'リアルタイムOFF：記録したグラフを表示しています。',false
end
function Live.prepare_offline()
  if Live.enabled then if not Live.stop() then return false end
  else Live.finish_run();if not Live.save() then return false end end
  Live.notice=nil;Live.noticeBad=false
  return true
end
function Live.restore_after_measure(job)
  local resume=job.resumeLive;job.resumeLive=nil
  if not resume or Live.enabled or A.job or A.closed or A.requestClose
    or A.project~=job.project or R.EnumProjects(-1,'')~=job.project then return end
  local message,bad=Live.notice,Live.noticeBad
  Live.toggle()
  if Live.enabled and bad then Live.message(message,true) end
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
-- Arrange graph
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
   local whole=data;local ranges={}
   -- Adjacent history segments share one guide layer; their moving borders do not restart dashes.
   for _,seg in ipairs(whole.segments) do
     local ax,bx=max(0,xx(seg.first)),min(width,xx(seg.last))
     if bx>ax then
       local previous=ranges[#ranges]
       if previous and ax<=previous[2]+1e-6 then previous[2]=max(previous[2],bx)
       else ranges[#ranges+1]={ax,bx} end
     end
   end
   for _,range in ipairs(ranges) do
     local ax,bx=range[1],range[2]
     lrect(ax,top,bx-ax,bottom-top,C.accent,.035)
     for _,key in ipairs({'s','m','i'}) do
       if S.show[key] then
         local target=S.targets[key]
         for j,v in ipairs({target[1]-target[2],target[1]+target[2]}) do
           if v>=S.lo and v<=S.hi and (j==1 or target[2]~=0) then
             local y=yy(v)
             for x=floor(ax/14)*14,bx,14 do
               local left,right=max(ax,x),min(bx,x+5)
               if right>left then lline(left,y,right,y,colors[key],.23) end
             end
           end
         end
       end
     end
   end
   for _,data in ipairs(whole.segments) do
    local ax,bx=max(0,xx(data.first)),min(width,xx(data.last))
    if bx>ax then
      local spp=(last-first)*10/width
      local lev,span=1,1
      while span*2<=spp and span*2<#data.rows do lev=lev+1; span=span*2 end
      for _,key in ipairs(Core.metrics) do
        if S.show[key] then
          local buckets=data.lod[key][lev]
          if key=='i' and Live.run and data.first>=Live.run.last-1e-8 then buckets={} end
          local from=max(1,floor((first-data.origin)*10/span))
          local to=min(#buckets//2,math.ceil((last-data.origin)*10/span)+1)
          local px,py,pbad
          for i=from,to do
            local bi=(i-1)*2+1;local low,high=buckets[bi],buckets[bi+1]
            if low==false then low=nil end;if high==false then high=nil end
            local time=data.origin+((i-1)*span+min(span,#data.rows-(i-1)*span)*.5+.5)*.1
            local x=xx(time)
            if low then
              local bad
              if key=='peak' then bad=peak_bucket_alert(low,high)
              elseif S.targets[key] then bad=bucket_alert(low,high,S.targets[key])
              else bad=false end
              local y=yy((low+high)*.5); local color=bad and C.red or colors[key]
              local pathColor=(bad or pbad) and C.red or colors[key]
              local pathAlpha=(key=='s' and .98 or .78)

              if px and x>=ax and px<=bx and x>px then
                local left,right=max(ax,px),min(bx,x)
                if right>left then
                  local slope=(y-py)/(x-px)
                  lline(left,py+(left-px)*slope,right,py+(right-px)*slope,pathColor,pathAlpha)
                end
              end
              if x>=ax and x<=bx then lline(x,yy(low),x,yy(high),color,.85) end
              px,py,pbad=x,y,bad
            else px=nil end
          end
        end
      end
    end
   end
  else ltext(Live.enabled and 'Press PLAY to record live loudness.' or 'Select a time range, or enable REAL-TIME.',65,top+24,width-90,C.muted) end
  for _,v in ipairs(ticks) do
    lrect(5,yy(v)-8,35,17,C.bg,.94); ltext(string.format('%.5g',v),8,yy(v)-8,30,C.muted)
  end
  lrect(0,0,width,28,C.panel)
  local measuredName=source_name()
  ltext('LOUDNESS TRACE  ·  '..tostring(measuredName or 'NO TARGET'),12,5,max(165,width-390),C.ice)
  if width>680 then
    local tags={}
    for _,q in ipairs({{'s','S'},{'m','M'},{'i','I RUN'},{'rms','RMS'},{'peak','PEAK'}}) do if S.show[q[1]] then tags[#tags+1]=q[2] end end
    ltext(table.concat(tags,'  /  '),max(300,width-365),5,180,C.muted)
  end
  if width>370 then ltext(Live.enabled and (Live.phase=='writing' and 'LIVE / RECORDING' or 'LIVE / WAIT') or (data and (A.stale and 'SAVED / RE-MEASURE' or 'MEASURED') or 'NO MEASUREMENT'),width-185,5,180,Live.enabled and C.mint or A.stale and C.gold or C.faint) end
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
      local iv=not (Live.run and t>Live.run.last+1e-8) and r.i or nil
      A.hover={time=t,s=r.s,m=r.m,i=iv,rms=r.rms,peak=r.peak}
      lline(mx,28,mx,bottom,C.text,.4)
      local label=Core.clock(t)..'   S '..value(r.s)..'   M '..value(r.m)..'   I RUN '..value(iv)..' LUFS'
      local boxw=min(555,width-16); local bx=Core.clamp(mx+14,8,max(8,width-boxw-8))
      lrect(bx,29,boxw,19,C.panel); ltext(label,bx+7,29,boxw-12,C.text)
    end
  end
end

function Core.present_graph(hwnd,bitmap,x1,x2,destY,sourceY,height)
  if x2<=x1 or height<=0 then return end
  if Platform.windows and R.JS_GDI_GetClientDC and R.JS_GDI_ReleaseDC and R.JS_LICE_GetDC and R.JS_GDI_Blit then
    local dc=R.JS_GDI_GetClientDC(hwnd)
    if dc then
      local ok,err=pcall(function()
        local source=R.JS_LICE_GetDC(bitmap);assert(source,'Graph bitmap DC unavailable')
        R.JS_GDI_Blit(dc,x1,destY,source,x1,sourceY,x2-x1,height,'SRCCOPY')
      end)
      R.JS_GDI_ReleaseDC(dc,hwnd)
      if ok then return end
      BLT.logError(err)
    end
  end
  R.JS_Window_InvalidateRect(hwnd,x1,destY,x2,destY+height,false)
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

  local pointerInArrange=clientMouseX>=0 and clientMouseX<width and clientMouseY>=0 and clientMouseY<vh and R.JS_Window_FromPoint(mouseX,mouseY)==hwnd
  local arrangeMouseX=pointerInArrange and floor(clientMouseX) or nil
  local function queue_mouse_repair(x1,x2,delay)
    if x1==nil or x2==nil then return end
    if x2<x1 then x1,x2=x2,x1 end
    local q=A.mouseRepairQueue

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

  if A.mouseSweepMin and A.lastMouseMoveAt and now-A.lastMouseMoveAt>=.050 then
    local a=A.mouseSweepMin-4
    local b=A.mouseSweepMax+4

    queue_mouse_repair(a,b,.005)
    queue_mouse_repair(a,b,.085)
    queue_mouse_repair(a,b,.180)
    queue_mouse_repair(a,b,.320)
    A.mouseSweepMin=nil; A.mouseSweepMax=nil; A.lastMouseMoveAt=nil
  end

  local contentKey=table.concat({width,height,first,last,A.revision,tostring(A.stale),mx or -1},":")
  local key=contentKey..":"..cursorPixel
  local layout=table.concat({width,height,destY,visible,sourceY},":")

  local redraw=key~=A.cache and (A.cache=="" or now-A.lastPaint>=.05)
  local cursorOnly=Platform.mac and redraw and A.cache~="" and A.linked and layout==A.layoutCache and A.graphContentKey==contentKey
  local previousCursor=A.graphCursorPixel
  local dirtyLeft,dirtyRight
  local function present(left,right)
    if right<=left then return end
    if Platform.mac then
      dirtyLeft=dirtyLeft and min(dirtyLeft,left) or left;dirtyRight=dirtyRight and max(dirtyRight,right) or right
    else Core.present_graph(hwnd,A.bitmap,left,right,destY,sourceY,visible) end
  end
  if redraw then
    A.drawBitmap=A.backBitmap
    chart(width,height,first,last,mx)
    A.drawBitmap=nil
    R.JS_LICE_Blit(A.bitmap,0,0,A.backBitmap,0,0,width,height,1,"COPY")
    A.cache=key;A.lastPaint=now;A.graphContentKey=contentKey;A.graphCursorPixel=cursorPixel
  end
  local moved=not A.linked or layout~=A.layoutCache
  if moved then
    local old=A.paintRect
    local code=R.JS_Composite(hwnd,0,destY,width,visible,A.bitmap,0,sourceY,width,visible,false)
    if code~=1 then error("JS_Composite failed: "..tostring(code)) end
    A.linked=true;A.layoutCache=layout;A.paintRect={top=destY,bottom=destY+visible,width=width}

    if old then
      if old.top<destY then R.JS_Window_InvalidateRect(hwnd,0,old.top,old.width,min(old.bottom,destY),false) end
      if old.bottom>destY+visible then R.JS_Window_InvalidateRect(hwnd,0,max(old.top,destY+visible),old.width,old.bottom,false) end
    end
  end
  if redraw or moved then
    if cursorOnly and not moved and previousCursor then

      present(max(0,min(previousCursor,cursorPixel)-3),min(width,max(previousCursor,cursorPixel)+4))
    else present(0,width) end
  end

  if A.linked and A.mouseRepairQueue and #A.mouseRepairQueue>0 then
    local processed=0
    local i=1
    while i<=#A.mouseRepairQueue and processed<24 do
      local r=A.mouseRepairQueue[i]
      if r.due<=now then
        table.remove(A.mouseRepairQueue,i)
        local x1=max(0,floor(r.x1)); local x2=min(width,math.ceil(r.x2))
        if x2>x1 then present(x1,x2) end
        processed=processed+1
      else
        i=i+1
      end
    end
  end

  if dirtyLeft then Core.present_graph(hwnd,A.bitmap,dirtyLeft,dirtyRight,destY,sourceY,visible) end
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
-- Chameleon palette
local Chameleon={
  enabled=R.GetExtState(SECTION,"chameleon")=="1",
  signature=nil,poll_at=0,poll_interval=3.0,
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
  out.gold=fit_accent_to_bg(C_DEFAULT.gold,bg,text_is_light)
  out.purple=fit_accent_to_bg(C_DEFAULT.purple,bg,text_is_light)
  return out
end

function Chameleon.restore()
  for k,v in pairs(C_DEFAULT) do C[k]=ccopy(v) end
  C.accent2=C.ice;C.edge2=C.edge
  if BLT.chrome then BLT.chrome.mint=C.mint;BLT.chrome.red=C.red end
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
  C.gold=ccopy(palette.gold);C.purple=ccopy(palette.purple)
  C.accent2=C.ice;C.edge2=C.edge
  if BLT.chrome then BLT.chrome.mint=C.mint;BLT.chrome.red=C.red end
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

-- Controller widgets
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

local function source_display(name,x,y,w,h)
  local a=.32
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
  text(name,x+140,y+(h-16)/2-1,16,C.text,w-156,1,true,true)
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

local function cancel_job(restoreLive)
  if not A.job then return end
  local job=A.job; A.job=nil; clean_temp(job)
  if restoreLive~=false then Live.restore_after_measure(job) end
end
local function measure()
 if not Media.ready(true,true) then return end
  if A.job then return end
  if R.GetPlayStateEx(A.project)~=0 then return end
  if math.abs(R.Master_GetPlayRate(A.project)-1)>.000001 then return end
  local first,last=R.GetSet_LoopTimeRange2(A.project,false,false,0,0,false)
  if last-first<.4 then return end
  if last-first>12600 then return end
  if A.historyBlocked then Live.message(A.historyProblem or '保存グラフを復元できません。元のデータは保持しています。',true);return end
  local name=source_name()
  local duration=last-first
  if duration>TEMP_WARNING_SECONDS then
    local estimate=duration*TEMP_BYTES_PER_SECOND
    local message=string.format('長い範囲を解析するため、一時WAVを約 %s 作成します。\n解析中は同程度の空き容量が必要です。続行しますか？\n\n範囲：%.1f分',human_bytes(estimate),duration/60)
    if Language.mb(message,'LOUDNESS TRACE | 長尺解析',1)~=1 then return end
  end
  set_graph_track_visible(true)
  local job={project=A.project,first=first,last=last,source=S.source,name=name,progress=0,phase='prepare',resumeLive=Live.enabled}
  A.job=job
  local prepared,ready=xpcall(Live.prepare_offline,debug.traceback)
  if not prepared or not ready then
    cancel_job()
    if not prepared then Live.message(public_error(ready),true) end
    return
  end
  job.co=coroutine.create(function()

    coroutine.yield()
    assert(R.EnumProjects(-1,'')==job.project,'測定開始前にプロジェクトが切り替わりました。')
    local current_first,current_last=R.GetSet_LoopTimeRange2(job.project,false,false,0,0,false)
    assert(math.abs(current_first-first)<=1e-9 and math.abs(current_last-last)<=1e-9,'測定開始前に時間選択が変更されました。')
    local base=Platform.tempDirectory()
    job.dir=base:gsub('[/\\]+$','')
    job.prefix='LoudnessTrace_'..R.genGuid():gsub('[^%w]','')
    job.phase='render'
    job.path=Core.render(R,job.project,first,last,job.dir,job.prefix)
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
  if not Media.ready() then return end
  local ok,err=coroutine.resume(job.co)
  if not ok then
    cancel_job()
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
    if not saved then Live.dirty=true;Language.mb(public_error(why),'LOUDNESS TRACE | 保存',0) end
    Live.restore_after_measure(job)
  end
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

function Live.button_motion(now)
  local target=Live.enabled and 1 or 0
  local u=Live.buttonState
  if not u then u={value=target,target=target};Live.buttonState=u end
  local previous=u.value
  if u.started then
    local t=Core.clamp((now-u.started)/.18,0,1);local ease=t*t*(3-2*t)
    u.value=u.from+(u.target-u.from)*ease
    if t>=1 then u.value=u.target;u.started=nil end
  end
  if target~=u.target then u.from=u.value;u.target=target;u.started=now;redraw_dirty=true end

  if previous~=u.value then
    redraw_dirty=true;if not u.started then next_draw_time=now end
  end
  return u.value,u.started~=nil
end
function Live.draw_button(x,y,w,h,compact)
  local enabled=not A.job or Live.enabled
  local hot=enabled and A.active and not BLT.blocked() and not A.titleMouseActive and inside(x,y,w,h)
  local state=Live.button_motion(R.time_precise())
  local accent=C.accent2 or C.ice
  local shift=hot and A.pressed=='live' and (gfx.mouse_cap&1)~=0 and 1 or 0
  local yy=y+shift
  gradient(x,yy,w,h,C.panel,C.field,.74,.96)
  if enabled and state>0 then rect(x+1,yy+1,w-2,h-2,C.accent,.055*state) end
  if hot then rect(x+1,yy+1,w-2,h-2,C.accent,.065) end
  line(x,yy,x+w,yy,enabled and accent or C.edge,enabled and (.25+.42*state) or .22)
  line(x,yy+h,x+w-7,yy+h,C.edge,.52)
  finish_corners(x,yy,w,h,7,false,enabled and accent or C.edge,enabled and (.34+.26*state) or .22)
  BLT.switch(x+(compact and 2 or 5),yy+(h-24)*.5,state,enabled)
  local tx=x+(compact and 30 or 36);local tw=w-(compact and 34 or 42)
  local ty=yy+(h-(compact and 24 or 30))*.5
  if compact then
    text('LIVE',tx,ty,8.5,enabled and C.text or C.faint,tw,nil,true)
    text(Live.enabled and 'ON' or 'OFF',tx,ty+13,8,enabled and (Live.enabled and accent or C.muted) or C.faint,tw,nil,true)
  else
    text('リアルタイム',tx,ty,12.5,enabled and C.text or C.muted,tw,nil,true)
    local caption=Live.enabled and (Live.phase=='writing' and 'ON / RECORDING' or 'ON / WAIT') or 'OFF'
    text(caption,tx,ty+18,8.5,enabled and (Live.enabled and accent or C.faint) or C.faint,tw,nil,true)
  end
  if enabled then widgets[#widgets+1]={id='live',x=x,y=y,w=w,h=h,fn=function() if commit_edit() then Live.toggle() end end} end
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
  text('LOUDNESS TRACE',28,7,12.2,C.text,145,3,true)
  local state=A.job and ('ANALYZING  '..floor(A.job.progress*100)..'%') or (Live.enabled and 'LIVE / '..(Live.phase=='writing' and 'RECORDING' or 'WAIT') or 'TRACE ACTIVE')
  text(state,29,25,7.7,(A.job or Live.enabled) and C.ice or C.faint,140,3,true)
  fold_control('expand',78,39,48,16,false,expand_window)
  Live.draw_button(183,15,60,28,true)

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

  source_display(source_name(),24,107,598,44)
  local data=A.data
  local savedText=data and ('保存済み：'..data.name..'  /  '..#data.segments..'区間  ·  選択範囲だけ置換') or '時間範囲を選択して解析。範囲外の解析結果は保持します。'
  if Live.enabled then savedText='共通グラフ：再生・解析した範囲を更新し、範囲外は保持します。' end
  text(savedText,25,158,11.5,C.muted,596)

  local pos=R.GetCursorPositionEx(A.project)
  if (R.GetPlayStateEx(A.project)&1)==1 then pos=R.GetPlayPositionEx(A.project) end
  local sample=A.hover or ((Live.enabled and Live.wasPlaying) and Live.latest) or Core.row(data,pos)
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

  button('clear','グラフをクリア',24,555,126,32,function() clear_measurement() end,false,false,nil,'gold')
  Live.draw_button(180,554,146,34,false)
  button('measure',A.job and ('解析を中止  '..floor(A.job.progress*100)..'%') or '選択範囲を解析',356,550,266,42,function()
    if A.job then cancel_job() else measure() end
  end,true,false,A.job and 'CANCEL' or 'ANALYZE')
  if A.job then rect(356,594,266*A.job.progress,2,C.ice,.8) end
  fold_control('collapse',(W-64)*.5,603,64,18,true,function() A.requestFold=true end)

  local status,bad
  if not A.job and (Live.enabled or Live.noticeBad) then status,bad=Live.status() else status=A.job and string.format('解析中 %d%%',math.floor(A.job.progress*100)) or (A.stale and 'プロジェクトが変更されています。再解析してください。' or (A.data and '解析結果を表示しています。' or '時間範囲を選択してください。'));bad=A.stale end
  BLT.footer(status,bad,W,H+22,VERSION)
  inputs_mouse();custom_titlebar()
end

BLT.factorySettings={lo=-60,hi=0,visible=true,height=280,show={s=true,m=true,i=true,rms=false,peak=false},targets={s={-23,3},m={-23,3},i={-23,1}},source="master",alertUpper=false,alertLower=false,alertPeak=false}
function Live.warnings(data)
  local run=Live.run;local h=run.summary;local a,b=S.targets.s,S.targets.m
  if h.targets.s[1]~=a[1] or h.targets.s[2]~=a[2] or h.targets.m[1]~=b[1] or h.targets.m[2]~=b[2] then
    h=Core.history_summary(Live.previous,run.first,S.targets)
    for _,row in ipairs(run.rows) do run.integrated,run.lra=h.feed(row) end
    run.summary=h
  end
  return h.warning[1]*.1,h.warning[2]*.1,h.warning[3]*.1
end
local chromeKeys={mouseDown='titleMouseDown',drag='titleDrag',resize='resizeDrag',mouseActive='titleMouseActive',
 closePressed='titleClosePressed',resetPressed='titleResetPressed',chameleonPressed='titleChameleonPressed',
 requestClose='requestClose',requestReset='requestReset'}
BLT.chrome=setmetatable({font=Platform.chromeFont,mint=C.mint,red=C.red,titleText='L O U D N E S S   T R A C E'}, {
 __index=function(_,k) return A[chromeKeys[k] or k] end,
 __newindex=function(_,k,v) A[chromeKeys[k] or k]=v end})
 C.accent2=C.ice;C.edge2=C.edge

Media.state=A;Media.onchange=function() if BLT.host and BLT.host.wake then BLT.host.wake() end end
Media.all_items=true
BLT.attach({
 R=R,C=C,Chrome=BLT.chrome,Chameleon=Chameleon,section=SECTION,faces=Platform.faces,font=function(sz,k,b) BLT.font(sz,k,b,scale,Platform.faces) end,
 geometry=function() return scale,ox,oy end,active=function() local f=gfx.getchar(65536);return (f&1)==0 or (f&2)~=0 end,
 wake=function() A.content_dirty=true;redraw_dirty=true;next_draw_time=0;wake_visuals() end,
 defaults=BLT.factorySettings,capture=function() return S end,
 valid=function(v) if v.lo< -120 or v.hi>24 or v.lo>=v.hi or v.height<100 or v.height>1000 or v.source~='master' then return false end;for _,t in pairs(v.targets) do if #t~=2 or t[1]< -120 or t[1]>24 or t[2]<0 or t[2]>120 then return false end end;return true end,apply=function(v) local hc,vc=S.height~=v.height,S.visible~=v.visible;for k,x in pairs(v) do S[k]=x end;if hc then change_height(S.height) end;if vc then set_graph_track_visible(S.visible) end;edited() end,
 undoRefresh=function() A.revision=A.revision+1;A.cache='';A.stale=A.data~=nil end,
 busy=function() return A.job~=nil or A.windowTransition~=nil end,commit=function() return commit_edit() end,
 cancelEdit=function() A.edit=nil;A.fieldDrag=nil end,editing=function() return A.edit~=nil end,
 modal=function() return false end,
 handle=gfx_window_handle,resizeHit=function(x,y) if y<26 and x>=gfx.w-268 then return nil end;return resize_hit(x,y) end,
 cursor=set_resize_cursor,beginResize=begin_resize,resize=update_resize,
 compactChrome=function() return A.collapsed end,transition=function() return A.windowTransition~=nil end,fold=function() A.requestFold=true end,collapsed=function() return A.collapsed end,prepareMenu=function() if A.collapsed then A.requestFold=true;BLT.openAfterExpand=true;return false end;return not A.windowTransition end,
})
function BLT.drawIcon()
 local bs,bx,by=scale,ox,oy;ox,oy=ox+(W-102)*scale,oy+31*scale;scale=scale*.78
 icon(0,0)

 scale,ox,oy=bs,bx,by
end

local _,_,sectionID,commandID=R.get_action_context()
local function close()
 local ok,err=xpcall(function()
  if A.closed then return end; A.closed=true
  clear_loudness_tooltip()
  set_resize_cursor(nil)
  Live.stop()
  cancel_job(false)
  retry_temp_deletes(true)
  Live.restore_fx_preference()
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
-- Application lifecycle
local function startup()
  Live.prepare_install()
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

  gfx.ext_retina=Platform.mac and 0 or 1
  local wx,wy=extnum("window_x",100),extnum("window_y",100)
  gfx.init("LOUDNESS TRACE",ww,hh+A.titleH,0,wx,wy)
  A.uiReady=true; A.gfxWindow=R.JS_Window_Find("LOUDNESS TRACE",true)
  if A.gfxWindow then

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
  Live.restore_fx_preference()
  local active=(gfx.getchar(65536)&2)==2
  if last_active_state==nil or active~=last_active_state then last_active_state=active; wake_visuals(now) end
  A.active=active

  local raw_x,raw_y,raw_cap=gfx.mouse_x,gfx.mouse_y,gfx.mouse_cap
  local raw_wheel=gfx.mouse_wheel or 0

  local cap_changed=raw_cap~=last_raw_mouse_cap
  local wheel_activity=raw_wheel~=0
  local pointer_activity=raw_x~=last_raw_mouse_x or raw_y~=last_raw_mouse_y or cap_changed or wheel_activity
  if pointer_activity then wake_visuals(now) end

  if cap_changed or wheel_activity then next_draw_time=now end
  last_raw_mouse_x,last_raw_mouse_y,last_raw_mouse_cap=raw_x,raw_y,raw_cap
  if gfx.w~=last_window_w or gfx.h~=last_window_h then last_window_w,last_window_h=gfx.w,gfx.h; wake_visuals(now) end

  local key_activity=k>0
  if key_activity then wake_visuals(now) end
  local project_changed=R.EnumProjects(-1,"")~=A.project
  if project_changed then cancel_job(false); adopt_project(false); redraw_dirty=true end
  local was_stale=A.stale
  if A.data and not Live.enabled and R.GetProjectStateChangeCount(A.project)~=A.baseline then A.stale=true end
  if A.stale~=was_stale then redraw_dirty=true end

  local consumed=edit_key(k)
  if k==13 and not consumed then if A.job then cancel_job() else measure() end; redraw_dirty=true end
  local had_job=A.job~=nil
  step_job()
  if had_job~=(A.job~=nil) then redraw_dirty=true end
  Live.tick(now)
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
  local _,live_motion=Live.button_motion(now)
  local forced=A.job~=nil or A.windowTransition~=nil or live_motion
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
