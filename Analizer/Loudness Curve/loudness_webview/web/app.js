(() => {
  'use strict';
  const $ = id => document.getElementById(id);
  const canvas = $('graph');
  const ctx = canvas.getContext('2d');
  const state = {report: null, points: [], calculated: [], tool: 'post', drag: false,
    upper: [], lower: [], pre: [], post: [], snapshots: [], revision: 0, previousTarget: -23, busy: false, regions: [], waveform: null, waveToken: 0, regionToken: 0, scenes:[], sceneRevision:0, sceneToken:0, sceneMeasurement:null, viewport: {start:0,end:1}, panning: null, customCenter: false, draggedPost: null, razor: null, razorDrag: null};
  const queuedChunks = [];
  const waveDetailCache=new Map();let waveDetailTimer=null,waveDetailDesired=null,waveDetailBusy=false;
  function clearWaveDetails(){clearTimeout(waveDetailTimer);waveDetailTimer=null;waveDetailDesired=null;waveDetailCache.clear();state.waveDetail=null;}
  function requestWaveDetail(width){
    const wave=state.waveform;
    if(!wave||!visible('waveform'))return;
    const start=state.viewport.start,finish=Math.min(state.viewport.end,wave.length),count=clamp(Math.round(width*2),256,4096);
    if(finish<=start||wave.step<=(finish-start)/count){state.waveDetail=null;return;}
    const key=`${state.waveToken}:${start.toFixed(3)}:${finish.toFixed(3)}:${count}`;
    if(waveDetailCache.has(key)){state.waveDetail=waveDetailCache.get(key);return;}
    state.waveDetail=null;
    if(waveDetailDesired?.key===key)return;
    waveDetailDesired={key,start,finish,count,token:state.waveToken};clearTimeout(waveDetailTimer);
    waveDetailTimer=setTimeout(fetchWaveDetail,180);
  }
  async function fetchWaveDetail(){
    if(waveDetailBusy||!waveDetailDesired)return;
    waveDetailBusy=true;const desired=waveDetailDesired;
    try{
      const meta=await bridge.request('waveform-detail',`${desired.start.toFixed(3)}~${desired.finish.toFixed(3)}~${desired.count}`),points=[];
      if(!Number.isInteger(meta.count)||meta.count<1||meta.count>4096)throw new Error('Detailed peaks unavailable');
      for(let offset=0;offset<meta.count;offset+=256){
        if(desired.token!==state.waveToken||desired.key!==waveDetailDesired?.key)return;
        const chunk=await bridge.request('waveform-detail-chunk',`${meta.revision}~${offset}`);points.push(...chunk.points);
      }
      if(desired.token!==state.waveToken||desired.key!==waveDetailDesired?.key)return;
      if(points.length!==meta.count)throw new Error('Incomplete detailed waveform');
      const detail={...meta,points};waveDetailCache.set(desired.key,detail);state.waveDetail=detail;
      while(waveDetailCache.size>8)waveDetailCache.delete(waveDetailCache.keys().next().value);
      $('show-waveform').title=`Detailed waveform · ${(meta.step*1000).toFixed(1)} ms per bin; amplitude is not LUFS.`;
    }catch(error){if(desired.token===state.waveToken&&desired.key===waveDetailDesired?.key){waveDetailCache.set(desired.key,null);$('show-waveform').title=error.message;}}
    finally{waveDetailBusy=false;if(desired.key!==waveDetailDesired?.key&&waveDetailDesired)waveDetailTimer=setTimeout(fetchWaveDetail,180);draw();}
  }
  let activeSource='master',activeStem=null,sourceEditors=new Map(),destinationTracks=[];
  const bridge = new ReaperBridge(message => {
    if (!state.report || message.revision !== state.revision) queuedChunks.push(message);
    else onPoints(message);
  });
  const pad = {left: 65, right: 13, top: 14, bottom: 26};
  const range = {min: -60, max: 0};
  const clamp = (value, min, max) => Math.max(min, Math.min(max, value));
  const number = (id, fallback) => {
    const value = Number($(id).value);
    return Number.isFinite(value) ? value : fallback;
  };
  const fmt = value => Number.isFinite(value) ? value.toFixed(1) : '—';
  const profiles={
    ebu:{name:'EBU R 128',target:-23,peak:-1,tolerance:.2,note:'Programme loudness preset.'},
    atsc:{name:'ATSC A/85 Short-form',target:-24,peak:-2,tolerance:2,note:'Full-program short-form preset; long-form dialogue/anchor delivery requires dialogue-gated measurement.'},
    apple:{name:'Apple Podcasts',target:-16,peak:-1,tolerance:1,note:'Overall loudness recommendation.'},
    spotify:{name:'Spotify Normal',target:-14,peak:-1,tolerance:.5,guidance:true,note:'Normal playback normalization reference, not an upload requirement.'}
  };
  function syncProfile(){
    let profile=profiles[$('standard').value];
    if(profile&&Math.abs(number('target',-23)-profile.target)>.001){$('standard').value='custom';profile=null;}
    $('standard').title=profile?`${profile.name} · Target ${profile.target} LUFS-I · I check ±${profile.tolerance} LU${profile.guidance?" (tool target guide)":""} · True Peak limit ${profile.peak} dBTP. ${profile.note} This preset does not apply a true-peak limiter.`:'Custom target. Select a profile to set Target; processing and Output trim remain as configured.';
  }
  const setStatus = (message, error = false) => {
    $('status').textContent = message;
    $('status').style.color = error ? '#ed8280' : '#68c8ad';
  };
  const visible = name => $('show-' + name).checked;
  try{$('corrected-ribbon').checked=localStorage.getItem('SBP.LoudnessCurve.correctedRibbon.v1')!=='false';}catch(_){}
  $('corrected-ribbon').addEventListener('change',()=>{try{localStorage.setItem('SBP.LoudnessCurve.correctedRibbon.v1',String($('corrected-ribbon').checked));}catch(_){}draw();});
  try{$('snap-level').checked=localStorage.getItem('SBP.LoudnessCurve.snap.v1')==='true';$('data-source').value=localStorage.getItem('SBP.LoudnessCurve.data.v1')||'report';}catch(_){}
  $('snap-level').addEventListener('change',()=>{try{localStorage.setItem('SBP.LoudnessCurve.snap.v1',String($('snap-level').checked));}catch(_){}syncRazorUI();if(state.razor&&$('mouse-mode').value==='razor')applyRazor();});
  try{$('snap-boundaries').checked=localStorage.getItem('SBP.LoudnessCurve.boundarySnap.v1')==='true';$('show-editor-scenes').checked=localStorage.getItem('SBP.LoudnessCurve.editorScenes.v1')==='true';}catch(_){}
  $('data-source').addEventListener('change',()=>{try{localStorage.setItem('SBP.LoudnessCurve.data.v1',$('data-source').value);}catch(_){}renderSourceTabs();});
  const scanTime=value=>{const s=Math.max(0,Math.floor(Number(value)||0));return `${Math.floor(s/60)}:${String(s%60).padStart(2,'0')}`;};
  function startScan(){state.measurementActive=true;state.measureCancel=false;$('cancel-measure').hidden=false;$('cancel-measure').disabled=false;$('measure-progress').hidden=false;$('measure-progress').value=0;}
  function scanProgress(result,label=''){
    $('measure-progress').value=clamp(Number(result.percent)||0,0,100);
    $('audio-estimate').textContent=`${label}${result.phase||'Preparing'} · ${Math.round(Number(result.percent)||0)}% · audio ${scanTime(result.processed)} · elapsed ${scanTime(result.elapsed)}`;
  }
  function endScan(){state.measurementActive=false;$('cancel-measure').hidden=true;$('measure-progress').hidden=true;}
  $('cancel-measure').addEventListener('click',async()=>{
    $('cancel-measure').disabled=true;
    try{
      if(state.measurementActive){state.measureCancel=true;await bridge.request('measure-cancel');setStatus('Cancelling measurement…');}
      else if(state.waveLoading){++state.waveToken;state.waveLoading=false;state.waveform=null;clearWaveDetails();await bridge.request('waveform-clear');endScan();state.busy=false;$('load').disabled=false;$('load-waveform').disabled=false;$('audio-estimate').textContent='Waveform build cancelled.';calculate();setStatus('Waveform build cancelled.');}
    }catch(error){$('cancel-measure').disabled=false;setStatus(error.message,true);}
  });
  const preview = new LoudnessPreview(bridge,()=>({report:state.report,viewport:state.viewport,canvas,pad,path:audioPath(),offset:number('offset',0),channels:audioEstimate?.channels,gainKey:state.report&&state.calculated.length?previewGainRequest():null,gainRequest:state.report&&state.calculated.length?previewGainRequest():null}),setStatus);
  preview.onWaveformChange=draw;
  const stems = typeof LoudnessStems==='function'?new LoudnessStems(()=>{
    const master=activeSource==='master'?null:sourceEditors.get('master');
    return {report:master?.state.report||state.report,points:master?.state.points||state.points,viewport:master?.state.viewport||state.viewport,target:master?Number(JSON.parse(master.edit).values.target):number('target',-23),busy:state.busy};
  },measureStems,row=>switchSource(row),{bridge,status:setStatus}):null;
  function sourceIdentity(row){return `${row.path}|${row.data?.size}|${row.data?.modified_ns}`;}
  function saveSourceEditor(){
    if(!state.report)return;
    const fields=['report','points','calculated','pre','post','upper','lower','tool','loadedSources','customCenter','viewport','scenes','sceneMeasurement','sceneDefinition','sceneRevision'];
    const record={state:Object.fromEntries(fields.map(key=>[key,state[key]])),edit:captureEdit(),view:Object.fromEntries(viewIds.map(id=>[id,$(id).value])),destination:$('destination-track').value,
      audio:audioEstimate,fresh:audioEstimate?.key===audioKey(),undo:[...undoStack],redo:[...redoStack],base:historyBase,url:$('url').value,path:audioPath(),dataMode:$('data-source').value,identity:activeStem?sourceIdentity(activeStem):null,payload:curvePayload(),sceneFresh:state.sceneMeasurement?.key===sceneAudioKey()};
    sourceEditors.set(activeSource,record);
    if(activeStem){activeStem.edit={identity:record.identity,working:workingData(),destination:record.destination};stems.persist();}
  }
  function renderSourceTabs(){
    syncRazorUI();
    const container=$('editor-sources');if(!container)return;container.replaceChildren();
    const picker=$('editor-source');picker.replaceChildren();picker.disabled=state.busy||!state.report;
    for(const row of [null,...(stems?.rows.filter(row=>row.data?.source_id)||[])]){
      const button=document.createElement('button'),id=row?.data.source_id||'master';button.className='tool'+(id===activeSource?' active':'');button.textContent=row?.name||'Master';button.disabled=state.busy||!state.report;
      button.setAttribute('aria-pressed',String(id===activeSource));button.addEventListener('click',()=>switchSource(row));container.append(button);
      button.title=id===activeSource?`Editing ${button.textContent}`:`Open ${button.textContent} in the curve editor; its settings are kept separately`;
      const option=document.createElement('option');option.value=id;option.textContent=button.textContent;picker.append(option);
    }
    picker.value=activeSource;
    $('destination-track').disabled=state.busy;$('refresh-tracks').disabled=state.busy;
    $('load').disabled=state.busy||activeSource!=='master';$('url').disabled=activeSource!=='master';$('audio-path').disabled=activeSource!=='master';
    for(const id of ['report-browse','report-paste'])$(id).disabled=state.busy||$('url').disabled;
    for(const id of ['audio-browse','audio-paste'])$(id).disabled=state.busy||$('audio-path').disabled;
    $('data-source').disabled=state.busy||activeSource!=='master';if($('data-source').value==='audio'){$('url').disabled=true;$('report-browse').disabled=true;$('report-paste').disabled=true;}
    $('report-path-label').textContent=activeSource==='master'?($('data-source').value==='audio'?'Render statistics · optional in audio mode':'Render statistics · required'):'Stem analysis · from WAV';
    $('audio-path-label').textContent=activeSource==='master'?'Matching original audio · required':'Original stem audio';
    const target=destinationTracks.find(track=>track.guid===$('destination-track').value);
    $('export').textContent=activeSource==='master'?`Export to ${target?.name||($('destination-track').value?'missing track':'PRINTMASTER')}`:`Export ${activeStem?.name||'stem'} → ${target?.name||'choose track'}`;
    updateAnalysisSources();
  }
  function updateAnalysisSources(){
    for(const panel of ['analysis','constellation','verify']){
      const select=$(panel+'-source'),linked=$(panel+'-linked').checked,chosen=linked?activeSource:select.value||activeSource;
      select.replaceChildren();
      for(const row of [null,...(stems?.rows.filter(row=>row.data?.source_id)||[])]){
        const option=document.createElement('option');option.value=row?.data.source_id||'master';option.textContent=row?.name||'Master';select.append(option);
      }
      select.value=chosen;select.disabled=linked||state.busy;
    }
  }
  function analysisModel(panel){
    const id=$(panel+'-linked').checked?activeSource:$(panel+'-source').value||activeSource;
    if(id===activeSource)return {id,state,values:Object.fromEntries(historyIds.map(key=>[key,$(key).value])),path:audioPath(),payload:state.calculated.length?curvePayload():null,sceneFresh:!!state.report&&state.calculated.length>0&&state.sceneMeasurement?.key===sceneAudioKey()};
    let record=sourceEditors.get(id);
    if(!record){
      const row=stems?.rows.find(row=>row.data?.source_id===id);if(!row)return null;
      const d=row.data,f=d.fingerprint,values={...Object.fromEntries(historyIds.map(key=>[key,$(key).value])),offset:String(Number(sourceEditors.get('master')?.edit?JSON.parse(sourceEditors.get('master').edit).values.offset:number('offset',0))+row.offset)};
      const points=d.points,report={name:row.name,length:d.duration,integrated:f.i,metadata:{true_peak:f.true_peak,peak:f.sample_peak,lra:f.lra},histogram:[]};
      record={analysisOnly:true,state:{report,points,calculated:points.map(p=>({time:p.time,loudness:p[values.metric],gain:0})),scenes:[],sceneMeasurement:null},edit:JSON.stringify({values}),path:row.path,payload:`${Number(values.offset).toFixed(3)}|${d.duration.toFixed(3)}|0.000,0.000;${d.duration.toFixed(3)},0.000`,sceneFresh:false};
      sourceEditors.set(id,record);
    }
    return {id,state:record.state,values:JSON.parse(record.edit).values,path:record.path,payload:record.payload,sceneFresh:record.sceneFresh,record};
  }
  function selectDestination(value){
    const select=$('destination-track');value=value||'';
    if(value&&!Array.from(select.children).some(option=>option.value===value)){const option=document.createElement('option');option.value=value;option.textContent='Missing track · refresh or choose another';select.append(option);}
    select.value=value;
  }
  async function refreshTracks(force=false){
    if(state.busy&&force!==true)return;
    try{
      const result=await bridge.request('track-list');destinationTracks=Array.isArray(result.tracks)?result.tracks:[];
      const select=$('destination-track'),selected=select.value;select.replaceChildren();
      const placeholder=document.createElement('option');placeholder.value='';placeholder.textContent=activeSource==='master'?'PRINTMASTER · default':'Choose destination track';select.append(placeholder);
      for(const track of destinationTracks){const option=document.createElement('option');option.value=track.guid;option.textContent=`${track.index} · ${track.name}`;select.append(option);}
      selectDestination(selected);renderSourceTabs();calculate();
    }catch(error){setStatus(error.message,true);}
  }
  async function changeDestination(){
    if(state.busy)return;
    const previous=sourceEditors.get(activeSource)?.destination||'';
    try{
      await bridge.request('source-target',$('destination-track').value);state.payloadCache=null;await preview.reset(false);
      audioEstimate=null;calculate();saveSourceEditor();saveWorking();
      setStatus(`Destination: ${destinationTracks.find(track=>track.guid===$('destination-track').value)?.name||'PRINTMASTER'}`);
    }catch(error){$('destination-track').value=previous;setStatus(error.message,true);calculate();}
  }
  async function switchSource(row){
    const id=row?.data?.source_id||'master';if(state.busy||id===activeSource)return;
    saveSourceEditor();const previous=activeSource;
    try{
      state.busy=true;renderSourceTabs();await preview.reset(false);
      const native=await bridge.request('source-select',id);
      activeSource=id;activeStem=row;state.sceneWindowDraft=false;const saved=sourceEditors.get(id);
      ++state.waveToken;++state.regionToken;++state.sceneToken;state.editorSceneToken=(state.editorSceneToken||0)+1;state.editorScenes=[];state.waveform=null;state.regions=[];state.scenes=[];state.sceneMeasurement=null;state.sceneDefinition=null;clearWaveDetails();clearRazor();state.revision=native.revision;
      if(saved&&!saved.analysisOnly&&(!row||saved.identity===sourceIdentity(row))){
        Object.assign(state,saved.state);$('url').value=saved.url;$('audio-path').value=saved.path;
        $('data-source').value=saved.dataMode||'report';
        selectDestination(saved.destination);restoreEdit(saved.edit);
        for(const key of viewIds)$(key).value=saved.view[key];
        undoStack=saved.undo;redoStack=saved.redo;historyBase=saved.base;audioEstimate=saved.audio;
        if(saved.fresh&&audioEstimate)audioEstimate={...audioEstimate,key:audioKey()};historyButtons();
      }else if(row){
        const d=row.data,f=d.fingerprint;
        state.report={name:row.path.split(/[\\/]/).pop(),length:d.duration,integrated:f.i,metadata:{true_peak:f.true_peak,peak:f.sample_peak,lra:f.lra},histogram:[],source_kind:'stem',source_identity:sourceIdentity(row)};
        state.points=d.points.map(point=>({...point}));
        $('metric').value=d.duration>=3?'short_term':'momentary';
        state.loadedSources={report:`stem:${row.path}`,audio:row.path};$('url').value='WAV stem · audio-derived M/S';$('audio-path').value=row.path;selectDestination(native.target);
        $('data-source').value='audio';
        $('normalize').value='off';$('standard').value='custom';$('high-ratio').value='1';$('low-ratio').value='1';state.tool='post';setOutputTrim(0);
        $('offset').value=Number(sourceEditors.get('master')?.edit?JSON.parse(sourceEditors.get('master').edit).values.offset:0)+row.offset;
        audioEstimate=null;resetViewport();resetCurves();resetHistory();
        if(row.edit?.identity===sourceIdentity(row)&&row.edit.working){
          try{applyWorking(row.edit.working);selectDestination(row.edit.destination);if($('destination-track').value)await bridge.request('source-target',$('destination-track').value);}
          catch(error){setStatus(`Saved stem settings could not be restored: ${error.message}`,true);}
        }
      }else throw new Error('Master editor state is unavailable; reload its report');
      state.payloadCache=null;state.previousTarget=number('target',-23);$('zoom-x').max=String(Math.max(100,Math.min(20000,Math.floor(state.report.length/2))));
      document.querySelectorAll('[data-tool]').forEach(button=>button.classList[button.dataset.tool===state.tool?'add':'remove']('active'));
      const first=$('destination-track').children[0];if(first)first.textContent=id==='master'?'PRINTMASTER · default':'Choose destination track';
      stems?.busy(id!=='master');state.busy=false;calculate();await refreshRegions();
      setStatus(`Editing ${row?.name||'Master'}${id!=='master'&&!$('destination-track').value?' · choose its destination track for export':''}`);
      await loadWaveform(false,false);if($('constellation-panel').open)await refreshScenes();saveWorking();
    }catch(error){setStatus(error.message,true);if(activeSource===previous)renderSourceTabs();}
    finally{state.busy=false;stems?.busy(activeSource!=='master');calculate();}
  }
  $('editor-source').addEventListener('change',()=>{
    const id=$('editor-source').value;return switchSource(id==='master'?null:stems?.rows.find(row=>row.data?.source_id===id));
  });
  $('refresh-tracks').addEventListener('click',refreshTracks);$('destination-track').addEventListener('change',changeDestination);
  async function measureStems(){
    if(!state.report||state.busy)return;
    if(activeSource!=='master'){setStatus('Switch to Master to change or measure stem files.',true);return;}
    let rows;
    try{rows=stems.configs();}catch(error){setStatus(error.message,true);return;}
    const revision=state.revision,results=[];
    try{
      state.busy=true;stems.busy(true);$('load').disabled=true;$('load-waveform').disabled=true;calculate();startScan();
      for(const [index,row] of rows.entries()){
        if(state.measureCancel)throw new Error('Measurement cancelled');
        const label=`Stem ${index+1}/${rows.length} · ${row.name} · `;
        scanProgress({phase:'Preparing',percent:0},label);
        await bridge.request('stem-measure',`${revision}~${row.path}`);
        let result;
        do{
          await new Promise(resolve=>setTimeout(resolve,500));result=await bridge.request('measure-poll');
          if(result.running)scanProgress(result,label);
        }while(result.running);
        if(result.cancelled||state.measureCancel)throw new Error('Measurement cancelled');
        if(state.revision!==revision)throw new Error('The render report changed; rescan stems');
        results.push({row,data:{...JSON.parse(result.stem_json),source_id:result.source_id}});
      }
      stems.accept(results);renderSourceTabs();setStatus(`Measured ${results.length} WAV stems.`);
    }catch(error){setStatus(error.message,!state.measureCancel);}
    finally{endScan();state.busy=false;stems.busy(false);$('load').disabled=false;$('load-waveform').disabled=false;calculate();renderAudioEstimate();}
  }
  try{$('waveform-follow-ab').checked=localStorage.getItem('SBP.LoudnessCurve.waveformAB.v1')==='true';}catch(_){}
  $('waveform-follow-ab').addEventListener('change',()=>{try{localStorage.setItem('SBP.LoudnessCurve.waveformAB.v1',String($('waveform-follow-ab').checked));}catch(_){}draw();});
  function waveformGain(time){
    const native=preview.gainPoints&&preview.gainKey===previewGainRequest();
    const points=native?preview.gainPoints:state.calculated;
    if(!points.length)return 1;
    let low=0,high=points.length-1;
    while(low+1<high){const mid=(low+high)>>1;if(points[mid].time<=time)low=mid;else high=mid;}
    const a=points[low],b=points[Math.min(low+1,points.length-1)],f=clamp((time-a.time)/Math.max(1e-9,b.time-a.time),0,1);
    return native?a.linear+(b.linear-a.linear)*f:10**((a.gain+(b.gain-a.gain)*f)/20);
  }

  const stepped = () => $('curve-mode').value === 'step';
  function interpolate(knots, time) {
    if (!knots.length) return 0;
    if (time <= knots[0].time) return knots[0].value;
    for (let index = 1; index < knots.length; index++) {
      if (time < knots[index].time || (!stepped() && time === knots[index].time)) {
        if (stepped() && !knots[index - 1].ramp) return knots[index - 1].value;
        const left = knots[index - 1], right = knots[index];
        const fraction = (time - left.time) / Math.max(.000001, right.time - left.time);
        return left.value + (right.value - left.value) * fraction;
      }
    }
    return knots[knots.length - 1].value;
  }
  function measured(point) {
    if(['stem','audio'].includes(state.report?.source_kind))return point[$('metric').value];
    return point[$('metric').value] ?? point.short_term ?? point.momentary;
  }
  function measuredAtMetric(time, metric = $('metric').value) {
    const points = state.points;
    const read = point => metric === $('metric').value ? measured(point) : point[metric];
    if (!points.length) return number('target', -23);
    if (time <= points[0].time) return read(points[0]);
    if(time>=points.at(-1).time)return read(points.at(-1));
    let low=0,high=points.length-1;
    while(low+1<high){const middle=(low+high)>>1;if(points[middle].time>=time)high=middle;else low=middle;}
    const a=points[low],b=points[high];
    if(time===a.time)return read(a);if(time===b.time)return read(b);
    if(!Number.isFinite(read(a))||!Number.isFinite(read(b)))return undefined;
    return read(a)+(read(b)-read(a))*(time-a.time)/Math.max(.000001,b.time-a.time);
  }
  const measuredAt = time => measuredAtMetric(time) ?? (['stem','audio'].includes(state.report?.source_kind)?-120:undefined);
  function calculationTimes(includePost = true) {
    const times = new Set(state.points.map(point => point.time));
    times.add(0); times.add(state.report.length);
    for (const key of (includePost ? ['pre','upper','lower','post'] : ['pre','upper','lower'])) for (const knot of state[key]) {
      times.add(knot.time);
      if (stepped() && knot.time > 0) times.add(Math.max(0, knot.time - .002));
    }
    return [...times].sort((a,b) => a-b);
  }
  const shaping = () => $('normalize').value !== 'only';
  const postGain = () => number('post-volume',0);
  function syncOutputTrim(){const input=$('post-volume'),value=postGain(),slider=input.parentElement.querySelector('input[type=range]');input.min=Math.min(-24,value);input.max=Math.max(24,value);if(slider){slider.min=input.min;slider.max=input.max;slider.value=input.value;}}
  function setOutputTrim(value){$('post-volume').value=value.toFixed(3);syncOutputTrim();}
  function baseGain() {
    return $('normalize').value !== 'off' && Number.isFinite(state.report?.integrated)
      ? number('target', -23) - state.report.integrated : 0;
  }
  const linkedPre = time => shaping() && $('link-limits').checked ? interpolate(state.pre,time) : 0;
  const limitAt = (key,time) => interpolate(state[key],time)+linkedPre(time);
  function automaticGain(time, loudness) {
    const upper = limitAt('upper',time);
    const lower = limitAt('lower',time);
    const highRatio = clamp(number('high-ratio', 1), .25, 8);
    const lowRatio = clamp(number('low-ratio', 1), .25, 8);
    let output = loudness;
    if (loudness > upper) output = upper + (loudness - upper) / highRatio;
    else if (loudness < lower) output = lower + (loudness - lower) / lowRatio;
    return output - loudness;
  }
  function calculate() {
    syncProfile();
    if (!state.report || !state.points.length) { draw(); return; }
    const maxCut = clamp(number('max-cut', 6), 0, 24);
    const maxBoost = clamp(number('max-boost', 6), 0, 24);
    const gate = number('silence', -55);
    const smooth = clamp(number('smooth', 15), 0, 120);
    const base = baseGain();
    const raw = calculationTimes().map(time => {
      const point = {time};
      const loudness = measuredAt(time);
      const pre = shaping() ? interpolate(state.pre, time) : 0;
      const post = shaping() ? interpolate(state.post, time) : 0;
      const input = loudness + base + pre;
      let gain = shaping() ? clamp(automaticGain(time, input), -maxCut, maxBoost) : 0;
      if (input < gate) gain = Math.min(0, gain);
      return {time, loudness, gain, pre, post};
    });
    if (shaping() && !stepped() && smooth > 0 && raw.length > 1) {
      const limiterTimes = new Set(calculationTimes(false));
      const smoothPoints = raw.filter(p=>limiterTimes.has(p.time));
      const forward = [smoothPoints[0].gain], backward = new Array(smoothPoints.length);
      backward[smoothPoints.length - 1] = smoothPoints[smoothPoints.length - 1].gain;
      for (let index = 1; index < smoothPoints.length; index++) {
        const dt = smoothPoints[index].time - smoothPoints[index - 1].time;
        const alpha = 1 - Math.exp(-dt / smooth);
        forward[index] = forward[index - 1] + alpha * (smoothPoints[index].gain - forward[index - 1]);
      }
      for (let index = smoothPoints.length - 2; index >= 0; index--) {
        const dt = smoothPoints[index + 1].time - smoothPoints[index].time;
        const alpha = 1 - Math.exp(-dt / smooth);
        backward[index] = backward[index + 1] + alpha * (smoothPoints[index].gain - backward[index + 1]);
      }
      smoothPoints.forEach((point, index) => {
        point.gain = clamp((forward[index] + backward[index]) / 2, -maxCut, maxBoost);
        if (point.loudness + base + point.pre < gate) point.gain = Math.min(0, point.gain);
      });
      let cursor=1;
      for (const point of raw) {
        if(limiterTimes.has(point.time))continue;
        while(cursor<smoothPoints.length-1 && smoothPoints[cursor].time<point.time)cursor++;
        const left=smoothPoints[cursor-1],right=smoothPoints[cursor];
        const fraction=(point.time-left.time)/Math.max(.000001,right.time-left.time);
        point.gain=left.gain+(right.gain-left.gain)*fraction;
        if(point.loudness+base+point.pre<gate)point.gain=Math.min(0,point.gain);
      }
    }
    raw.forEach(point => {point.dynamics = point.gain; point.gain += base + point.pre + point.post + postGain();});
    state.calculated = raw;
    state.payloadCache=null;
    const sourceTimes = new Set(state.points.map(point => point.time));
    const included = raw.filter(point => sourceTimes.has(point.time) && point.loudness >= gate);
    const corrected = included.map(point => point.loudness + point.gain).sort((a,b) => a-b);
    const median = corrected.length ? corrected[Math.floor(corrected.length / 2)] : NaN;
    const gains = raw.map(point => point.gain);
    const outside = included.filter(point => {
      const output = point.loudness + point.gain;
      return output > limitAt('upper',point.time) || output < limitAt('lower',point.time);
    }).length;
    const before = included.map(point => point.loudness).sort((a,b) => a-b);
    $('before-median').textContent = before.length ? fmt(before[Math.floor(before.length / 2)]) + ' LUFS' : '—';
    $('post-gain').textContent = fmt(postGain());
    $('base-gain').textContent = fmt(base);
    $('normalized-i').textContent = Number.isFinite(state.report.integrated) ? fmt(state.report.integrated + base + postGain()) : '—';
    const missingI = $('normalize').value !== 'off' && !Number.isFinite(state.report.integrated);
    const tooLarge = raw.some(point => !Number.isFinite(point.gain));
    $('normalization-note').textContent = missingI
      ? 'Measured LUFS-I is missing. Choose Shape only; normalization and export are unavailable.'
      : `Normalization: ${fmt(base)} dB. Output trim: ${fmt(postGain())} dB. Pre volume → limiters → Post volume. Normalize only bypasses curves, limiting and smoothing; Output trim remains active. Use audio preview for final LUFS-I after shaping.${tooLarge ? ' Export unavailable: nonfinite correction.' : ''}${shaping() && raw.length > 200000 ? ' Export unavailable: too many correction points; simplify the drawing.' : ''}`;
    $('normalization-note').hidden=!(missingI||tooLarge||(shaping()&&raw.length>200000));
    $('integrated').textContent = state.report.integrated == null ? '—' : fmt(state.report.integrated);
    $('median').textContent = fmt(median) + (Number.isFinite(median) ? ' LUFS' : '');
    $('gain-range').textContent = `${fmt(gains.reduce((a,b)=>Math.min(a,b),Infinity))} / +${fmt(gains.reduce((a,b)=>Math.max(a,b),0))} dB`;
    $('outside').textContent = `${outside} / ${included.length}`;
    $('link-limits').disabled=!shaping();
    for (const button of document.querySelectorAll('.tool[data-tool]')) button.disabled = !shaping();
    for (const id of ['upper','lower','high-ratio','low-ratio','max-cut','max-boost','silence','smooth']) {$(id).disabled = !shaping(); const slider = $(id).parentElement.querySelector('input[type=range]');if(slider)slider.disabled = !shaping();}
    $('edit-note').textContent = !shaping() ? 'Normalize only applies constant Target minus measured LUFS-I plus Output trim. Editing curves and dynamics are bypassed; drawings are retained.' : stepped() ? 'Step mode holds each correction until the next point. Smoothing is bypassed. Export preserves boundaries with 2 ms transitions; this is gain editing, not transient metering.' : 'Click adds a point at the existing curve level; hold and drag to change it. Right-click erases. Optional 3 points adds surrounding anchors. Zero gain is at Target. Reset affects only the selected curve. Linear mode smooths limiter correction.';
    $('export').disabled = state.busy || missingI || tooLarge || (shaping() && raw.length > 200000);
    if(activeSource!=='master'&&!$('destination-track').value)$('export').disabled=true;
    if($('destination-track').value&&!destinationTracks.some(track=>track.guid===$('destination-track').value))$('export').disabled=true;
    renderSourceTabs();
    $('fit-integrated').disabled=state.busy||missingI||tooLarge||(shaping()&&raw.length>200000)||!$('audio-path').value.trim()||!Number.isFinite(state.report.integrated);
    $('refine-audio').disabled=$('fit-integrated').disabled;
    preview.processingChanged();
    draw();renderAnalysis();renderConstellation();renderVerification();renderAudioEstimate();renderVerifiedStats();
    $('audio-estimate').title=$('audio-estimate').textContent;
    $('url').title=$('report-meta').textContent;
    $('audio-path').title=$('waveform-note').textContent+(audioEstimate?.channel_layout?` · ${audioEstimate.channel_layout} · ${audioEstimate.channels} channels${audioEstimate.sample_rate?` · ${audioEstimate.sample_rate} Hz`:''}. Embedded speaker layout is used for loudness weighting. Browser playback may downmix; use REAPER to check surround routing.`:'');
  }
  function renderAnalysis() {
    if($('analysis-panel').open){const model=analysisModel('analysis');if(model)LoudnessAnalysis.render({report:model.state.report,points:model.state.points,calculated:model.state.calculated,metric:model.values.metric,gate:Number(model.values.silence)});}
  }
  function sceneWindow(model={state}){
    const length=model?.state.report?.length||1,span=Math.min(length,Math.max(.001,number('scene-window-span',20)*60));
    const start=clamp(number('scene-window-start',0)*60,0,Math.max(0,length-span)),end=Math.min(length,start+span);
    return {start,end,suffix:$('scene-range').value==='window'?`~window:${start.toFixed(6)}:${end.toFixed(6)}`:''};
  }
  function sceneDefinitionKey(){return `${state.revision}|${number('offset',0)}|${$('scene-source').value}|${$('scene-track').value.trim()}|${$('scene-naming').value}|${sceneWindow().suffix}`;}
  function sceneAudioKey(){return `${sceneDefinitionKey()}|${JSON.stringify(state.scenes)}|${audioPath()}|${curvePayload()}`;}
  function sceneRows(model=null){
    if(model&&model.id!==activeSource){const s=model.state;if(!s.report)return [];return LoudnessConstellation.combine(LoudnessConstellation.overview(s.scenes||[],s.points,s.calculated,s.report.length),model.sceneFresh?s.sceneMeasurement?.rows:null);}
    if(!state.report||state.sceneDefinition!==sceneDefinitionKey())return [];
    const overview=LoudnessConstellation.overview(state.scenes,state.points,state.calculated,state.report.length);
    return LoudnessConstellation.combine(overview,state.sceneMeasurement?.key===sceneAudioKey()?state.sceneMeasurement.rows:null);
  }
  function focusScene(scene){
    const length=state.report.length,span=Math.min(length,Math.max(1,scene.finish-scene.start));
    const start=clamp(scene.start-(span-(scene.finish-scene.start))/2,0,length-span);
    $('zoom-x').value=String(Math.min(Number($('zoom-x').max),length/span));
    const actualSpan=length/number('zoom-x',1);
    $('pan-x').value=String(length===actualSpan?0:clamp(start/(length-actualSpan)*100,0,100));
    draw();preview.seek(scene.start);
  }
  function renderConstellation(){
    const model=analysisModel('constellation'),s=model?.state;
    renderSceneNavigator(model);
    $('scene-measure').disabled=state.busy||!s?.report||!s.scenes?.length||!model?.path||!Number.isFinite(s.report.integrated);
    $('scene-refresh').disabled=state.busy||!s?.report;
    if(!$('constellation-panel').open||state.sceneWindowDraft)return;
    LoudnessConstellation.render({rows:sceneRows(model),target:Number(model?.values.target??-23),stale:!!s?.sceneMeasurement&&!model.sceneFresh,onSelect:scene=>{if(model.id!==activeSource){setStatus('Open this source in the editor to navigate or play its scene.');return;}focusScene(scene);}});
  }
  function sceneNavTime(value){const seconds=Math.max(0,Math.round(value));return seconds>=3600?`${Math.floor(seconds/3600)}:${String(Math.floor(seconds/60)%60).padStart(2,'0')}:${String(seconds%60).padStart(2,'0')}`:scanTime(seconds);}
  function renderSceneNavigator(model=analysisModel('constellation')){
    const s=model?.state,length=s?.report?.length||1;
    const window=sceneWindow(model),enabled=$('scene-range').value==='window';
    for(const id of ['scene-window-start','scene-window-span','scene-window-position'])$(id).disabled=state.busy||!enabled||!s?.report;
    $('scene-range').disabled=state.busy||!s?.report;
    $('scene-window-position').max=String(Math.max(0,length-(window.end-window.start)));$('scene-window-position').value=String(window.start);
    $('scene-use-view').disabled=state.busy||model?.id!==activeSource||!s?.report;
    const from=enabled?window.start:0,to=enabled?window.end:length;
    const label=`${sceneNavTime(from)}–${sceneNavTime(to)}`;
    $('scene-window-note').textContent=enabled?`${label} · release to refresh · full intersecting scenes`:'Up to 2000 scenes · choose Time window for a smaller group';
    const track=$('scene-window-timeline'),box=$('scene-window-box');track.setAttribute('aria-disabled',String(!enabled||state.busy||!s?.report));
    track.setAttribute('aria-valuemin','0');track.setAttribute('aria-valuemax',$('scene-window-position').max);track.setAttribute('aria-valuenow',String(from));track.setAttribute('aria-valuetext',label);
    box.style.left=`${from/length*100}%`;box.style.width=`${(to-from)/length*100}%`;$('scene-window-label').textContent=label;box.title=label;
    const ticks=$('scene-window-ticks');ticks.replaceChildren();for(let i=0;i<=4;i++){const tick=document.createElement('span');tick.style.left=`${i*25}%`;tick.textContent=sceneNavTime(length*i/4);ticks.appendChild(tick);}
  }
  async function refreshScenes(){
    const model=analysisModel('constellation');if(!model?.state.report||state.busy)return;
    if(model.id!==activeSource){
      const suffix=sceneWindow(model).suffix;
      try{const value=await bridge.request('scene-list-source',`${model.id}~${model.values.offset}~${$('scene-source').value}~${$('scene-naming').value}~${$('scene-track').value.trim()}${suffix}`);
        if(analysisModel('constellation')?.id!==model.id||sceneWindow(model).suffix!==suffix)return;
        model.state.scenes=value.scenes;model.state.sceneRevision=value.revision;model.record.sceneFresh=false;state.sceneWindowDraft=false;$('scene-progress').textContent=`${value.scenes.length} scenes`;renderConstellation();
      }catch(error){state.sceneWindowDraft=false;$('scene-progress').textContent=error.message;}return;
    }
    const token=++state.sceneToken,definition=sceneDefinitionKey();
    try{
      const value=await bridge.request('scene-list',`${number('offset',0)}~${$('scene-source').value}~${$('scene-naming').value}~${$('scene-track').value.trim()}${sceneWindow(model).suffix}`);
      if(token!==state.sceneToken||definition!==sceneDefinitionKey())return;
      state.scenes=value.scenes;state.sceneRevision=value.revision;state.sceneDefinition=definition;state.sceneWindowDraft=false;
      $('scene-progress').textContent=`${state.scenes.length} scenes`;renderConstellation();
    }catch(error){if(token===state.sceneToken){state.sceneWindowDraft=false;state.scenes=[];$('scene-progress').textContent=error.message;renderConstellation();}}
  }
  async function measureScenes(){
    const selected=analysisModel('constellation');
    if(selected?.id!==activeSource){await measureBackgroundScenes(selected);return;}
    if(!state.report||state.busy)return;
    await refreshScenes();
    if(!state.scenes.length)return;
    const key=sceneAudioKey();
    try{
      state.busy=true;$('load').disabled=true;$('load-waveform').disabled=true;calculate();
      startScan();
      $('scene-progress').textContent='Measuring scene audio…';
      await bridge.request('scene-measure',`${state.revision}~${state.sceneRevision}~${curvePayload()}~${audioPath()}`);
      let result;
      do{
        await new Promise(resolve=>setTimeout(resolve,500));result=await bridge.request('measure-poll');
        if(result.running)$('scene-progress').textContent=`Measuring ${result.completed??0} / ${result.total??state.scenes.length} scenes…`;
        if(result.running)scanProgress(result);
      }while(result.running);
      if(result.cancelled||state.measureCancel){state.measureCancel=true;throw new Error('Measurement cancelled');}
      const rows=JSON.parse(result.scenes_json);
      if(!Array.isArray(rows)||rows.length!==state.scenes.length)throw new Error('Incomplete scene measurements');
      state.sceneMeasurement={key,rows};
      $('scene-progress').textContent=`Measured ${rows.length} scenes${key===sceneAudioKey()?'':' · settings changed, rescan required'}`;
      if($('scene-metric').value==='spread')$('scene-metric').value=rows.some(s=>Number.isFinite(s.before?.lra)||Number.isFinite(s.after?.lra))?'lra':'crest';
    }catch(error){$('scene-progress').textContent=error.message;$('audio-estimate').textContent=error.message;setStatus(error.message,!state.measureCancel);}
    finally{endScan();state.busy=false;$('load').disabled=false;$('load-waveform').disabled=false;calculate();renderAudioEstimate();}
  }
  async function measureBackgroundScenes(model){
    if(!model?.state.report||state.busy)return;
    await refreshScenes();if(analysisModel('constellation')?.id!==model.id||!model.state.scenes?.length)return;
    try{
      state.busy=true;startScan();calculate();
      await bridge.request('scene-measure-source',`${model.id}~${model.state.sceneRevision}~${model.payload}~${model.path}`);
      let result;do{await new Promise(resolve=>setTimeout(resolve,500));result=await bridge.request('measure-poll');if(result.running)scanProgress(result,'Analysis source · ');}while(result.running);
      if(result.cancelled||state.measureCancel)throw new Error('Measurement cancelled');
      const rows=JSON.parse(result.scenes_json);if(!Array.isArray(rows)||rows.length!==model.state.scenes.length)throw new Error('Incomplete scene measurements');
      model.state.sceneMeasurement={rows};model.record.sceneFresh=true;$('scene-progress').textContent=`Measured ${rows.length} scenes`;setStatus('Selected analysis source measured.');
    }catch(error){setStatus(error.message,!state.measureCancel);}
    finally{endScan();state.busy=false;calculate();}
  }
  function dimensions() {
    const rect = canvas.getBoundingClientRect();
    const dpr = window.devicePixelRatio || 1;
    const width = Math.max(1, rect.width), height = Math.max(1, rect.height);
    if (canvas.width !== Math.round(width*dpr) || canvas.height !== Math.round(height*dpr)) {
      canvas.width = Math.round(width*dpr); canvas.height = Math.round(height*dpr);
    }
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    return {width, height};
  }
  function updateRange() {
    const target = number('target', -23);
    const mode = $('view-range').value;
    let half = mode === 'wide' ? 30 : 12;
    if (mode === 'auto') {
      let distance = 9;

      const consider = value => {if (Number.isFinite(value)) distance = Math.max(distance, Math.abs(value-target));};
      if (visible('i')) consider(state.report?.integrated);
      for (const p of state.calculated) {
        const signal=!['stem','audio'].includes(state.report?.source_kind)||p.loudness>-70;
        if (visible('measured')&&signal) consider(p.loudness);
        if (visible('corrected')&&signal) consider(p.loudness+p.gain);
        if (visible('pre')&&signal) consider(p.loudness+baseGain()+p.pre);
        if (visible('post')) consider(number('target',-23)+p.post);
      }
      if (visible('upper')) state.calculated.forEach(p => consider(limitAt('upper',p.time)));
      if (visible('lower')) state.calculated.forEach(p => consider(limitAt('lower',p.time)));
      for (const snapshot of state.snapshots) if (snapshot.visible && visible('snapshots')) {
        for (const p of snapshot.points) {const value=p[$('metric').value];if(Number.isFinite(value)){consider(value);consider(value+p.gain);}}
      }
      half = Math.max(12, Math.ceil(distance / 3) * 3 + 3);
    }
    const center = state.customCenter ? number('center-y', target) : target;
    if (!state.customCenter) $('center-y').value = target.toFixed(1);
    half /= Math.max(1, number('zoom-y',1));
    range.min = center - half; range.max = center + half;
  }
  function draw() {
    updateRange();
    const {width, height} = dimensions();
    ctx.clearRect(0, 0, width, height);
    const graphWidth = width - pad.left - pad.right;
    const graphHeight = height - pad.top - pad.bottom;
    const length = state.report?.length || 1;
    const span = length / Math.max(1, number('zoom-x',1));
    const start = (length-span) * clamp(number('pan-x',0),0,100) / 100;
    state.viewport = {start, end:start+span};
    stems?.render();
    requestWaveDetail(graphWidth);
    preview.render();renderScanner();
    renderRegions();
    $('target-badge').textContent = `TARGET ${fmt(number('target',-23))} LUFS-I`;
    $('target-badge').hidden = !visible('target');
    const x = time => pad.left + (time-start) / span * graphWidth;
    const y = value => pad.top + (range.max - value) /
      (range.max - range.min) * graphHeight;
    if (visible('waveform') && state.waveform) {
      ctx.save();ctx.beginPath();ctx.rect(pad.left,pad.top,graphWidth,graphHeight);ctx.clip();
      const processedWave=$('waveform-follow-ab').checked&&preview.source==='file'&&preview.processed();
      ctx.fillStyle = processedWave?'#4ad0ad40':'#6c8e953a';
      const center = pad.top + graphHeight/2, amplitude = graphHeight*.43;
      const wave = state.waveDetail||state.waveform;
      for (const peak of wave.points) {
        if (peak.time + wave.step < start || peak.time > start+span) continue;
        const gain=processedWave?waveformGain(peak.time+wave.step/2):1;
        const high=Math.min(1,peak.high*gain),low=Math.max(-1,peak.low*gain);
        ctx.fillRect(x(peak.time), center - high*amplitude,
          Math.max(1, x(peak.time+wave.step)-x(peak.time)), Math.max(1,(high-low)*amplitude));
      }
      ctx.restore();
    }
    ctx.font = '10px Segoe UI';
    ctx.lineWidth = 1;
    const target = number('target', -23);
    const relative = $('scale-mode').value !== 'absolute';
    const step = range.max - range.min > 60 ? 10 : range.max - range.min > 30 ? 6 : 3;
    for (let offset = Math.ceil((range.min-target)/step)*step; offset <= range.max-target; offset += step) {
      const db = target + offset;
      if (visible('grid')) {
        ctx.strokeStyle = offset === 0 ? '#4b5554' : '#30393a';
        ctx.beginPath(); ctx.moveTo(pad.left, y(db)); ctx.lineTo(width-pad.right, y(db)); ctx.stroke();
      }
      if (visible('scale')) {
        ctx.fillStyle = offset === 0 ? '#4aefbc' : '#a7b5b5'; ctx.textAlign = 'right';
        ctx.fillText(relative ? (offset === 0 ? '0' : `${offset > 0 ? '+' : ''}${offset}`) : fmt(db), pad.left-7, y(db)+3);
      }
    }
    if (visible('scale')) {ctx.fillStyle='#a7b5b5';ctx.textAlign='left';ctx.fillText(relative ? 'Δ dB' : 'LUFS', 4, 11);}
    for (let tick = 0; tick <= 4; tick++) {
      const time = start + span * tick / 4;
      if (visible('time-grid')) {
        ctx.strokeStyle = '#30393a';ctx.beginPath();ctx.moveTo(x(time),pad.top);ctx.lineTo(x(time),height-pad.bottom);ctx.stroke();
      }
      const minute = Math.floor(time/60), second = span < 20 ? (time%60).toFixed(2).padStart(5,'0') : String(Math.floor(time%60)).padStart(2,'0');
      ctx.fillStyle = '#8e9e9e'; ctx.textAlign = 'center';
      ctx.fillText(`${minute}:${String(second).padStart(2,'0')}`, x(time), height-7);
    }
    if (!state.report || !state.calculated.length) {
      ctx.fillStyle = '#798888'; ctx.textAlign = 'center';
      ctx.fillText('Load a REAPER render report to view its loudness history', width/2, height/2);
      return;
    }
    ctx.save();ctx.beginPath();ctx.rect(pad.left,pad.top,graphWidth,graphHeight);ctx.clip();
    function line(points, color, accessor, weight = 1.5, dash = [], stairs = false) {
      ctx.beginPath(); ctx.strokeStyle = color; ctx.lineWidth = weight; ctx.setLineDash(dash);
      let connected = false, previousValue, previousPoint;
      // Only the visible interval and its interpolation anchors enter the path.
      let low=0,high=points.length;
      while(low<high){const mid=(low+high)>>1;if(points[mid].time<start)low=mid+1;else high=mid;}
      const first=Math.max(0,low-1);low=first;high=points.length;
      while(low<high){const mid=(low+high)>>1;if(points[mid].time<=start+span)low=mid+1;else high=mid;}
      points.slice(first,Math.min(points.length,low+1)).forEach(point => {
        const value = accessor(point);
        if (!Number.isFinite(value)) {connected = false; return;}
        if (connected) {if (stairs && !previousPoint.ramp) ctx.lineTo(x(point.time), y(previousValue)); ctx.lineTo(x(point.time), y(value));}
        else ctx.moveTo(x(point.time), y(value));
        connected = true; previousValue = value; previousPoint = point;
      });
      ctx.stroke(); ctx.setLineDash([]);
    }

    if (visible('i') && Number.isFinite(state.report.integrated)) line([{time:0},{time:length}], '#929c9d', () => state.report.integrated, 1, [2,5]);
    if(visible('i-history'))line(state.points,'#edc166',point=>point.integrated,1.5,[5,3]);
    const plotted=point=>['stem','audio'].includes(state.report?.source_kind)&&point.loudness<=-70?undefined:point.loudness;
    if (visible('measured')) line(state.calculated, '#a9b4b8', plotted, 2);
    ctx.save(); ctx.beginPath(); ctx.rect(pad.left, pad.top, graphWidth, graphHeight); ctx.clip();
    for (const snapshot of state.snapshots) {
      if (!visible('snapshots') || !snapshot.visible) continue;
      const metric = $('metric').value;
      line(snapshot.points, snapshot.color, point => point[metric], 1.4, [2,4]);
      line(snapshot.points, snapshot.color, point => Number.isFinite(point[metric])?point[metric]+point.gain:undefined, 1.8, [6,3]);
    }
    ctx.restore();
    if (visible('corrected')) {
      const corrected=point=>plotted(point)+point.gain;
      if($('corrected-ribbon').checked){
        // Vertical gradient follows actual LUFS, including interpolated crossings.
        // Its coordinates share the curve's transform under either zoom/scale mode.
        const ribbon=ctx.createLinearGradient(0,y(target+6),0,y(target-6));
        for(const [at,color] of [[0,'#ef7979'],[.25,'#efba60'],[.5,'#4aefbc'],[.75,'#58cee8'],[1,'#6596ee']])ribbon.addColorStop(at,color);
        ctx.save();ctx.lineJoin='round';ctx.lineCap='round';
        line(state.calculated,ribbon,corrected,3);
        ctx.restore();
      }else line(state.calculated,'#4aefbc',corrected,3);
    }
    function editLine(key, points, color, accessor, stairs = false) {
      if (!visible(key)) return;
      ctx.save();ctx.globalAlpha = !shaping() ? .15 : state.tool === key ? 1 : .3;
      line(points,color,accessor,state.tool === key ? 1.7 : 1.2,[],stairs);
      ctx.restore();
    }
    editLine('pre',state.calculated,'#ab9bff',p=>plotted(p)+baseGain()+p.pre);
    editLine('upper',state.calculated,'#e2a15d',p=>limitAt('upper',p.time));
    editLine('lower',state.calculated,'#65a6d5',p=>limitAt('lower',p.time));
    editLine('post',state.calculated,'#f28cdb',p=>number('target',-23)+p.post);
    if (visible('target')) {
      line([{time:0},{time:length}], '#4aefbc', () => target, 1);

    }
    for (const [knots,color,key] of [[state.upper,'#e2a15d','upper'],[state.lower,'#65a6d5','lower']]) {
      if (!visible(key)) continue;
      ctx.save();ctx.globalAlpha=!shaping()?.15:state.tool===key?1:.3;
      knots.forEach(point => {ctx.beginPath();ctx.arc(x(point.time),y(point.value+linkedPre(point.time)),3.5,0,Math.PI*2);
        ctx.fillStyle=color;ctx.fill();});
      ctx.restore();
    }
    for (const [key,color] of [['pre','#ab9bff'],['post','#f28cdb']]) {
      if (!visible(key)) continue;
      ctx.save();ctx.globalAlpha=!shaping()?.15:state.tool===key?1:.3;
      state[key].slice(1,-1).forEach(point => {
        const calculated = state.calculated.find(p=>p.time===point.time);
        if (!calculated) return;
        const value = key==='pre' ? calculated.loudness+baseGain()+calculated.pre : number('target',-23)+calculated.post;
        ctx.beginPath();ctx.arc(x(point.time),y(value),3.5,0,Math.PI*2);ctx.fillStyle=color;ctx.fill();
      });ctx.restore();
    }
    ctx.restore();
    drawRazor(x,y,width,height);
  }
  function drawRazor(x,y,width,height) {
    const r=state.razor;
    if(!r || $('mouse-mode').value!=='razor')return;
    r.bounds=null;r.handles=null;
    const left=Math.max(pad.left,x(Math.min(r.start,r.end))),right=Math.min(width-pad.right,x(Math.max(r.start,r.end)));
    if(right<=left)return;
    ctx.save();ctx.fillStyle='#67d6dc18';ctx.strokeStyle='#67d6dc';ctx.lineWidth=1;
    ctx.fillRect(left,pad.top,right-left,height-pad.top-pad.bottom);ctx.strokeRect(left,pad.top,right-left,height-pad.top-pad.bottom);
    const middle=(left+right)/2;
    const levelY=clamp(y(number('target',-23)+r.gain),pad.top+16,height-pad.bottom-40);
    const rampX=clamp(x(Math.min(r.start,r.end)-r.ramp),pad.left+8,width-pad.right-8);
    const rampY=height-pad.bottom-16;
    r.handles={level:{x:middle,y:levelY},ramp:{x:rampX,y:rampY}};
    r.bounds={left:x(Math.min(r.start,r.end)),right:x(Math.max(r.start,r.end)),top:pad.top,bottom:height-pad.bottom};
    ctx.fillStyle='#67d6dc';
    for(const edge of [r.bounds.left,r.bounds.right])if(edge>=pad.left&&edge<=width-pad.right)ctx.fillRect(edge-2,(pad.top+height-pad.bottom)/2-9,4,18);
    ctx.fillStyle='#67d6dc';ctx.beginPath();ctx.arc(middle,levelY,7,0,Math.PI*2);ctx.fill();
    ctx.beginPath();ctx.arc(rampX,rampY,7,0,Math.PI*2);ctx.fill();
    ctx.font='11px Segoe UI';ctx.textAlign='center';ctx.fillText(`Level ${$('snap-level').checked?String(r.gain):fmt(r.gain)} dB ↕`,middle,levelY-12);
    ctx.fillText(`Ramp ${r.ramp.toFixed(2)}s ↔`,Math.max(pad.left+50,rampX),rampY-12);
    ctx.restore();
  }
  function razorHit(px,py){
    const r=state.razor,b=r?.bounds;
    for(const name of ['level','ramp'])if(r?.handles?.[name]&&Math.hypot(px-r.handles[name].x,py-r.handles[name].y)<12)return name;
    if(!b||py<b.top||py>b.bottom||px<pad.left||px>canvas.getBoundingClientRect().width-pad.right)return null;
    if(Math.abs(px-b.left)<=8)return 'left';
    if(Math.abs(px-b.right)<=8)return 'right';
    return px>b.left&&px<b.right?'move':null;
  }
  function onPoints(message) {
    if (message.revision !== state.revision) return;
    if (message.offset === 0) state.points = [];
    state.points.push(...message.points);
    if (state.points.length === message.total) {
      $('report-meta').textContent = `${state.report.name} · ${state.points.length} samples · ${(state.report.length/60).toFixed(1)} min`;
      setStatus('Report loaded'); renderSnapshots(); calculate();
    }
  }
  function resetCurves() {
    if (!state.report) return;
    const length = state.report.length;
    state.upper = [{time:0,value:number('upper',-20)},{time:length,value:number('upper',-20)}];
    state.lower = [{time:0,value:number('lower',-26)},{time:length,value:number('lower',-26)}];
    state.pre = [{time:0,value:0},{time:length,value:0}];
    state.post = [{time:0,value:0},{time:length,value:0}];
    calculate();
  }
  function graphPosition(event) {
    const rect = canvas.getBoundingClientRect();
    const x = clamp(event.clientX - rect.left, pad.left, rect.width-pad.right);
    const y = clamp(event.clientY - rect.top, pad.top, rect.height-pad.bottom);
    return {time:state.viewport.start+(x-pad.left)/(rect.width-pad.left-pad.right)*(state.viewport.end-state.viewport.start),
      value:range.max-(y-pad.top)/(rect.height-pad.top-pad.bottom)*(range.max-range.min)};
  }
  function snapLevel(value){
    if(!$('snap-level').checked)return value;
    const origin=$('scale-mode').value==='absolute'?0:number('target',-23);
    return origin+Math.round(value-origin);
  }
  function pointReadout(point,level){
    const readout=$('point-readout');readout.hidden=false;
    const relative=$('scale-mode').value!=='absolute',display=relative?level-number('target',-23):level;
    readout.textContent=`${state.tool.toUpperCase()} · ${point.time.toFixed(3)} s · ${display.toFixed(2)} ${relative?'dB':'LUFS'} · ${point.value.toFixed(2)} ${['pre','post'].includes(state.tool)?'dB gain':'LUFS limit'}`;
  }
  function pointLevel(tool,time,value){return tool==='post'?number('target',-23)+value:tool==='pre'?measuredAt(time)+baseGain()+value:value+linkedPre(time);}
  function edit(event, erase = false) {
    if (state.busy || !state.report || !state.points.length || !shaping() || !visible(state.tool)) return;
    const position = graphPosition(event);
    const knots = state[state.tool];
    const span = state.viewport.end-state.viewport.start;
    let closest = -1, distance = Infinity;
    knots.forEach((point,index) => {
      if (index === 0 || index === knots.length-1) return;
      let current = Math.abs(point.time-position.time);
      if(erase) {
        const rect=canvas.getBoundingClientRect();
        const value=state.tool==='post' ? number('target',-23)+point.value : state.tool==='pre' ? measuredAt(point.time)+baseGain()+point.value : point.value+linkedPre(point.time);
        current=Math.hypot(current/span*(rect.width-pad.left-pad.right),(value-position.value)/(range.max-range.min)*(rect.height-pad.top-pad.bottom));
      }
      if (current < distance) {distance=current;closest=index;}
    });
    let near = erase ? distance < 12 : distance < span * 8 / Math.max(200,canvas.getBoundingClientRect().width-pad.left-pad.right);
    if (!erase && state.tool==='post' && state.draggedPost) {closest=knots.indexOf(state.draggedPost);near=closest>=0;}
    if (erase) {
      if (near) knots.splice(closest,1);
    } else {
      let value = snapLevel(position.value);
      if (state.tool === 'pre') {
        value = clamp(value - measuredAt(position.time) - baseGain(), -24, 24);
      } else if (state.tool === 'post') {
        value -= number('target',-23);
      } else {
        value -= linkedPre(position.time);
      }

      const point={time:position.time,value};
      if (near) knots[closest] = point;
      else knots.push(point);
      if(state.tool==='post'&&state.drag)state.draggedPost=point;
      pointReadout(point,pointLevel(state.tool,point.time,point.value));
      knots.sort((a,b) => a.time-b.time);
    }
    calculate();
  }
  function beginPointEdit(event){
    if(state.busy||!state.report||!state.points.length||!shaping()||!visible(state.tool))return;
    clearRazor();
    const position=graphPosition(event),knots=state[state.tool],rect=canvas.getBoundingClientRect();
    const xScale=(rect.width-pad.left-pad.right)/(state.viewport.end-state.viewport.start);
    const yScale=(rect.height-pad.top-pad.bottom)/(range.max-range.min);
    let point=null,distance=12;
    for(const candidate of knots.slice(1,-1)){
      const d=Math.hypot((candidate.time-position.time)*xScale,(pointLevel(state.tool,candidate.time,candidate.value)-position.value)*yScale);
      if(d<distance){point=candidate;distance=d;}
    }
    if(!point){
      const original=knots.map(p=>({...p})),time=position.time;
      const add=time=>{
        const existing=knots.find(p=>Math.abs(p.time-time)<.000001);if(existing)return existing;
        const left=original.filter(p=>p.time<=time).at(-1);
        const added={time,value:interpolate(original,time)};if(left?.ramp)added.ramp=true;
        knots.push(added);return added;
      };
      if($('edit-three-points').checked){
        const window=clamp(number('edit-point-window',1),.002,state.report.length);
        add(Math.max(0,time-window));add(Math.min(state.report.length,time+window));
      }
      point=add(time);knots.sort((a,b)=>a.time-b.time);
    }
    state.pointDrag={point,x:event.clientX,y:event.clientY,time:point.time,value:point.value,
      timeSpan:state.viewport.end-state.viewport.start,levelSpan:range.max-range.min};
    pointReadout(point,pointLevel(state.tool,point.time,point.value));calculate();
  }
  function dragPoint(event){
    const d=state.pointDrag;if(!d)return;
    const rect=canvas.getBoundingClientRect(),knots=state[state.tool],index=knots.indexOf(d.point);
    if(index<0)return;
    // Use motion relative to the press, so an off-curve click cannot jump levels.
    let time=d.time+(event.clientX-d.x)/(rect.width-pad.left-pad.right)*d.timeSpan;
    if(index===0||index===knots.length-1)time=d.point.time;
    else time=clamp(time,knots[index-1].time+.000001,knots[index+1].time-.000001);
    let value=d.value+(d.y-event.clientY)/(rect.height-pad.top-pad.bottom)*d.levelSpan;
    value+=snapLevel(pointLevel(state.tool,time,value))-pointLevel(state.tool,time,value);
    if(state.tool==='pre')value=clamp(value,-24,24);
    d.point.time=time;d.point.value=value;
    pointReadout(d.point,pointLevel(state.tool,time,value));calculate();
  }
  function resetActiveCurve() {
    if (!state.report) return;
    clearRazor();
    const key=state.tool;
    const value=key==='upper' ? number('upper',-20) : key==='lower' ? number('lower',-26) : 0;
    state[key]=[{time:0,value},{time:state.report.length,value}];
    calculate();
  }
  async function load(request={}) {
    if (state.busy) return;
    if(activeSource!=='master'){setStatus('Switch to Master before loading a render report.',true);return;}
    if(request.restore?.report.source_kind==='audio')$('data-source').value='audio';
    else if(request.restore)$('data-source').value='report';
    const builtin=$('data-source').value==='audio';
    if((!builtin&&!$('url').value.trim())||!$('audio-path').value.trim()){setStatus(builtin?'Enter the original audio path.':'Enter both the render statistics path and matching original audio path.',true);return;}
    let loaded=false;
    try {
      state.busy = true; $('load').disabled = true; setStatus('Loading…'); $('export').disabled=true;
      await preview.reset(false);
      let result,audioData;
      if(builtin){
        startScan();await bridge.request('audio-load',audioPath());let measured;
        do{await new Promise(resolve=>setTimeout(resolve,500));measured=await bridge.request('measure-poll');if(measured.running)scanProgress(measured,'Master history · ');}while(measured.running);
        if(measured.cancelled||state.measureCancel)throw new Error('Measurement cancelled');
        audioData=JSON.parse(measured.stem_json);
        if(!Array.isArray(audioData.points)||audioData.points.length>6000||!Number.isFinite(audioData.duration))throw new Error('Invalid audio history');
        const f=audioData.fingerprint;
        result={name:audioPath().split(/[\\/]/).pop(),length:audioData.duration,integrated:f.i,metadata:{true_peak:f.true_peak,peak:f.sample_peak,lra:f.lra},histogram:[],revision:measured.revision,source_kind:'audio',source_identity:`${audioPath()}|${audioData.size}|${audioData.modified_ns}`};
        $('cache-location').textContent=measured.cache_file?`Audio cache: ${measured.cache_file}${Number(measured.cached)?' · reused':''}`:measured.cache_error||$('cache-location').textContent;
      }else result=await bridge.request('load',$('url').value.trim());

      ++state.waveToken; ++state.regionToken; state.waveform=null; state.regions=[]; clearRazor(); resetViewport();
      clearWaveDetails();
      $('waveform-note').textContent = 'No rendered audio loaded.'; $('load-waveform').disabled=false;
      state.report = result; state.revision=result.revision; state.points=audioData?.points||[];state.calculated=[];
      if(builtin)$('metric').value=result.length>=3?'short_term':'momentary';
      sourceEditors.delete('master');$('destination-track').value='';
      $('zoom-x').max=String(Math.max(100,Math.min(20000,Math.floor(result.length/2))));
      state.loadedSources={report:builtin?`audio:${audioPath()}`:$('url').value.trim(),audio:$('audio-path').value.trim()};
      ++state.sceneToken;state.scenes=[];state.sceneRevision=0;state.sceneMeasurement=null;state.sceneDefinition=null;
      audioEstimate=null;$('audio-estimate').textContent=request.restore?'Estimate only · use Refine or Fit to target for an exact audio measurement.':'Preparing automatic audio loudness measurement…';resetCurves(); resetHistory();
      for (const chunk of queuedChunks.splice(0)) if (chunk.revision === state.revision) onPoints(chunk);
      if(request.restore){applyWorking(request.restore);if(request.restore.destination){await bridge.request('source-target',request.restore.destination);selectDestination(request.restore.destination);}}
      await refreshRegions();loaded=true;
    } catch(error) {setStatus(error.message,true);}
    finally {if(builtin)endScan();state.busy = false; $('load').disabled = false; calculate(); renderVerification();}
    if(loaded){await loadWaveform(false,!request.restore);if($('constellation-panel').open)await refreshScenes();}
    if(loaded)saveWorking();
    return loaded;
  }
  function previewGainRequest(){curvePayload();return state.payloadCache.request;}
  function curvePayload() {
    const offset=number('offset',NaN);
    if(state.payloadCache?.offset===offset)return state.payloadCache.value;
    const points = !shaping() ? [{time:0,gain:state.calculated[0].gain},{time:state.report.length,gain:state.calculated[0].gain}] : [{time:0,gain:state.calculated[0].gain},...state.calculated,
      {time:state.report.length,gain:state.calculated[state.calculated.length-1].gain}];
    const unique = [];
    for (const point of points) {
      const rounded={time:Number(point.time.toFixed(3)),gain:point.gain};
      if (unique.length && rounded.time <= unique[unique.length-1].time) continue;
      unique.push(rounded);
    }
    const value=`${offset.toFixed(3)}|${state.report.length.toFixed(3)}|`+
      unique.map(point => `${point.time.toFixed(3)},${point.gain.toFixed(3)}`).join(';');
    state.payloadCache={offset,value,request:`${state.revision}~${value}`};return value;
  }
  async function exportCurve() {
    if (!state.report || !state.calculated.length) return;
    if (state.busy || $('export').disabled) return;
    const exportedSnapshot = JSON.parse(JSON.stringify(makeSnapshot('Exported estimate')));
    const offset = number('offset',NaN);
    if (!Number.isFinite(offset) || offset < 0) {setStatus('Enter a valid render start.',true);return;}
    const payload = curvePayload();
    try {
      state.busy = true; $('export').disabled=true; $('load').disabled=true;setStatus('Exporting…');
      const result = await bridge.request('export',`${state.revision}~${$('replace-export').checked?'replace~':''}${payload}`);
      if($('snapshot-auto').checked)addSnapshot(exportedSnapshot);
      const reduction=Number.isFinite(result.original_points)&&result.original_points>result.points?` (reduced from ${result.original_points})`:'';
      setStatus(`${result.replaced?'Replaced curve with':'Exported'} ${result.points} points${reduction} to ${result.track}`);
    } catch(error) {setStatus(error.message,true);}
    finally {state.busy = false; $('load').disabled=false; calculate();}
  }
  let audioEstimate=null;
  function audioPath(){
    try{return LoudnessStems.normalizePath($('audio-path').value);}
    catch(_){return $('audio-path').value.trim();}
  }
  function audioKey(){
    const edit=JSON.parse(captureEdit());delete edit.values.standard;
    for(const [id,value] of Object.entries(edit.values))if(!['normalize','metric','curve-mode'].includes(id)&&Number.isFinite(Number(value)))edit.values[id]=Number(value);
    return `${state.revision}|${$('audio-path').value.trim()}|${curvePayload()}|${JSON.stringify(edit)}`;
  }
  function renderVerifiedStats(){
    const verified=audioEstimate&&audioEstimate.key===audioKey()&&Number.isFinite(audioEstimate.original_i)&&Number.isFinite(audioEstimate.predicted_i)&&Math.abs(audioEstimate.original_i-state.report.integrated)<=.3;
    $('before-stat-label').textContent=verified?'Before I · verified':'Before M/S · est.';
    $('after-stat-label').textContent=verified?'After I · verified':'After M/S · est.';
    const description=verified?'Verified offline audio measurement for the current gain curve; rerender to verify downstream processing.':'Estimate from sampled M/S history; median is not integrated LUFS-I. Refine or Fit to target refreshes the audio measurement.';
    for(const id of ['before-median','median']){$(id).title=description;$(id).setAttribute('data-quality',verified?'verified':'estimate');}
    for(const id of ['before-stat-label','after-stat-label'])$(id).title=description;
    if(verified){$('before-median').textContent=fmt(audioEstimate.original_i)+' LUFS';$('median').textContent=fmt(audioEstimate.predicted_i)+' LUFS';}
    const meta=state.report.metadata||{},sourceTP=Number.isFinite(meta.true_peak);
    const before=verified&&Number.isFinite(audioEstimate.original_peak)?audioEstimate.original_peak:sourceTP?meta.true_peak:meta.peak;
    let after=NaN;
    if(verified)after=audioEstimate.predicted_peak;
    else for(const p of state.calculated){const peak=measuredAtMetric(p.time,'peak');if(Number.isFinite(peak))after=Number.isFinite(after)?Math.max(after,peak+p.gain):peak+p.gain;}
    $('peak-stat').textContent=`${fmt(before)} → ${fmt(after)}`;
    $('peak-stat-label').textContent=verified?'TP · verified':`${sourceTP?'TP':'SP'} → SP · est.`;
    $('peak-stat').setAttribute('data-quality',verified?'verified':'estimate');
    $('peak-stat').title=verified?'Before → after measured True Peak, dBTP. Gain-model audio; downstream REAPER FX excluded.':`Before: report ${sourceTP?'True Peak, dBTP':'Sample Peak, dBFS'}. After: sampled peak plus current gain, dBFS; not a True Peak measurement. — means unavailable. Refine measures True Peak.`;
    $('peak-stat-label').title=$('peak-stat').title;
    renderScanner();renderProfileCheck(verified);
  }
  function renderProfileCheck(verified){
    const badge=$('profile-check'),profile=profiles[$('standard').value];badge.hidden=!profile;if(!profile)return;
    const name=profile.guidance?'Guide':'I/TP';
    if(!verified||audioEstimate.measurement_engine!=='ffmpeg-metadata-v2'){
      badge.textContent=`${name}: Refine`;badge.setAttribute('data-result','pending');
      badge.title='No fresh precise audio measurement for these settings. Refine or Fit to target before checking I/TP.';return;
    }
    const i=audioEstimate.predicted_i,tp=audioEstimate.predicted_peak,delta=i-profile.target;
    const iOK=Math.abs(delta)<=profile.tolerance+1e-9;
    const limit=profile.guidance&&i>profile.target? -2:profile.peak;
    const tpOK=Number.isFinite(tp)&&tp<=limit+1e-9;
    const scopeOK=!profile.guidance||audioEstimate.channels===2;
    const pass=iOK&&tpOK&&scopeOK;
    badge.textContent=scopeOK?`${name}: ${pass?'PASS':'FAIL'}`:'Guide: stereo only';
    badge.setAttribute('data-result',pass?'pass':'fail');
    badge.title=`${profile.name} · file gain preview; destination automation/FX excluded. I ${i.toFixed(3)} LUFS · Δ ${delta.toFixed(3)} LU · target ${profile.target} ±${profile.tolerance} LU: ${iOK?'PASS':'FAIL'}. TP ${Number.isFinite(tp)?tp.toFixed(4):'—'} dBTP · maximum ${limit}: ${tpOK?'PASS':Number.isFinite(tp)?'FAIL':'unavailable'}. ${profile.guidance?'Spotify is mastering guidance; ±0.5 LU is our editing goal, not a delivery requirement. Stereo master scope. ':''}${profile.note} This checks only I/TP, not complete delivery certification; downstream FX need a rerender. No peak limiting is applied.`;
  }
  function renderScanner(){
    const active=$('mouse-mode').value==='scan'&&state.report&&Number.isFinite(state.scanTime)&&state.scanTime>=state.viewport.start&&state.scanTime<=state.viewport.end;
    $('scan-readout').hidden=$('scan-line').hidden=!active;if(!active)return;
    const t=state.scanTime,points=state.calculated;
    let low=0,high=points.length-1;
    while(low+1<high){const mid=(low+high)>>1;if(points[mid].time<=t)low=mid;else high=mid;}
    const a=points[low],b=points[Math.min(low+1,points.length-1)];
    const gain=a?a.gain+(b.gain-a.gain)*clamp((t-a.time)/Math.max(1e-9,b.time-a.time),0,1):0;
    const m=measuredAtMetric(t,'momentary'),s=measuredAtMetric(t,'short_term'),peak=measuredAtMetric(t,'peak');
    $('scan-readout').textContent=`${Math.floor(t/60)}:${(t%60).toFixed(2).padStart(5,'0')} · M ${fmt(m)} → ${fmt(m+gain)} · S ${fmt(s)} → ${fmt(s+gain)} LUFS · Gain ${fmt(gain)} dB${Number.isFinite(peak)?` · SP ${fmt(peak)} → ${fmt(peak+gain)} dBFS`:''}`;
    $('scan-readout').title='Sampled report M/S before → estimated after current gain; interpolated at cursor time. SP is sample peak, not True Peak.';
    const width=canvas.getBoundingClientRect().width;
    $('scan-line').style.left=`${pad.left+(t-state.viewport.start)/(state.viewport.end-state.viewport.start)*(width-pad.left-pad.right)}px`;
  }
  function renderAudioEstimate(){
    if(!audioEstimate)return;
    $('audio-estimate').textContent=audioEstimate.key!==audioKey() ? 'Preview out of date · Refine or Fit to target to refresh.' : `${audioEstimate.channels>2?`${audioEstimate.channel_layout} · ${audioEstimate.channels} ch · `:''}File gain preview · Source I ${fmt(audioEstimate.original_i)} · Final I ${fmt(audioEstimate.predicted_i)} LUFS · Δ ${fmt(audioEstimate.predicted_i-number('target',-23))} LU · TP ${fmt(audioEstimate.predicted_peak)} dBTP. ${Math.abs(audioEstimate.original_i-state.report.integrated)>.3?'Source I differs from report: verify the audio and measurement settings.':''}`;
  }
  async function measureAudio(fit=false,automatic=false){
    if(state.busy||!state.report||!state.calculated.length)return;
    const audio=audioPath();
    if(!audio){setStatus('Enter the original rendered audio path in Source files.',true);return;}
    if(!Number.isFinite(state.report.integrated)){$('audio-estimate').textContent='Source LUFS-I is missing from the report. Load a complete matching report for audio preview.';return;}
    if(state.calculated.some(p=>!Number.isFinite(p.gain))||state.calculated.length>200000){$('audio-estimate').textContent='File gain preview requires a finite, supported gain curve.';return;}
    const initialTrim=postGain(),previousEstimate=audioEstimate;
    try{
      state.busy=true;$('fit-integrated').disabled=true;$('load').disabled=true;$('load-waveform').disabled=true;
      startScan();
      calculate();
      for(let attempt=0;attempt<(fit?3:1);attempt++){
        const key=audioKey();$('audio-estimate').textContent=`Measuring original audio and projected gain · pass ${attempt+1}…`;
        await bridge.request('measure-start',`${state.revision}~${curvePayload()}~${audio}`);
        let result;
        do{await new Promise(resolve=>setTimeout(resolve,500));result=await bridge.request('measure-poll');if(result.running)scanProgress(result,fit?`Fit ${attempt+1}/3 · `:'');}while(result.running);
        if(result.cancelled||state.measureCancel){state.measureCancel=true;throw new Error('Measurement cancelled');}
        if(audioKey()!==key)throw new Error('Audio or processing settings changed during measurement. Measure again.');
        if(!Number.isFinite(result.original_i)||!Number.isFinite(result.predicted_i))throw new Error('Invalid audio measurement result.');
        audioEstimate={...result,key};
        if(result.channel_layout)$('audio-path').title=`${result.channel_layout} · ${result.channels} channels. Embedded speaker layout is used for loudness weighting. For multichannel audition, use REAPER playback; browser routing may downmix.`;
        if(fit&&Math.abs(result.original_i-state.report.integrated)>.3)throw new Error('Original audio LUFS-I differs from the report by more than 0.3 LU. Verify the matching source before fitting.');
        const error=number('target',-23)-result.predicted_i;
        if(!fit||Math.abs(error)<=.2||attempt===2)break;
        setOutputTrim(postGain()+error);calculate();
      }
      renderAudioEstimate();
      setStatus(fit?(Math.abs(audioEstimate.predicted_i-number('target',-23))<=.5?'Projected final I is within ±0.5 LU of target. Verify the rerender.':'Fit did not converge within ±0.5 LU. Review the audio measurement.'):'File gain loudness measured. Destination automation and downstream FX are excluded; export checks conflicts separately.');
    }catch(error){
      if(state.measureCancel){setOutputTrim(initialTrim);audioEstimate=previousEstimate;}
      const overlap=/Existing PRINTMASTER points overlap this range/.test(error.message);
      const message=overlap?`${automatic?'Source data loaded. ':''}Final gain preview is blocked by existing Volume envelope points in the destination range. Choose a destination without conflicting automation, then use Refine. Existing points were not changed.`:error.message;
      if(overlap)audioEstimate=null;
      setStatus(message,!state.measureCancel&&!(automatic&&overlap));$('audio-estimate').textContent=message;renderAudioEstimate();
    }
    finally{endScan();state.busy=false;$('load').disabled=false;$('load-waveform').disabled=false;commitEdit();calculate();}
  }
  const historyIds=['post-volume','target','normalize','metric','upper','lower','high-ratio','low-ratio','max-cut','max-boost','silence','smooth','offset','curve-mode','standard'];
  let undoStack=[],redoStack=[],historyBase=null;
  function captureEdit(){return JSON.stringify({curves:Object.fromEntries(['pre','upper','lower','post'].map(k=>[k,state[k]])),values:Object.fromEntries(historyIds.map(k=>[k,$(k).value])),linked:$('link-limits').checked});}
  function historyButtons(){$('undo').disabled=!undoStack.length;$('redo').disabled=!redoStack.length;}
  function resetHistory(){undoStack=[];redoStack=[];historyBase=captureEdit();historyButtons();}
  function commitEdit(){if(!state.report||state.busy)return;const next=captureEdit();if(historyBase!==null&&next!==historyBase){undoStack.push(historyBase);if(undoStack.length>100)undoStack.shift();redoStack=[];}historyBase=next;historyButtons();saveWorking();}
  function restoreEdit(text){const saved=JSON.parse(text);Object.assign(state,saved.curves);for(const id of historyIds){$(id).value=saved.values[id]??(id==='standard'?'custom':'');const slider=$(id).parentElement.querySelector('input[type=range]');if(slider)slider.value=$(id).value;}syncOutputTrim();$('link-limits').checked=saved.linked;state.previousTarget=number('target',-23);clearRazor();historyBase=text;calculate();refreshRegions();historyButtons();saveWorking();}
  function undoEdit(){if(state.busy)return;commitEdit();if(!undoStack.length)return;redoStack.push(captureEdit());restoreEdit(undoStack.pop());}
  function redoEdit(){if(state.busy||!redoStack.length)return;undoStack.push(captureEdit());restoreEdit(redoStack.pop());}
  function renderVerification(){
    if(!$('verify-panel').open)return;
    const model=analysisModel('verify'),current=model?.state,metric=model?.values.metric;
    const snapshot=state.snapshots.find(s=>s.id===$('verify-snapshot').value);
    const c=$('verify-canvas'),box=c.getBoundingClientRect();c.width=Math.max(1,box.width);c.height=Math.max(1,box.height);
    const context=c.getContext('2d');context.clearRect(0,0,c.width,c.height);
    if(!snapshot||!current?.report){$('verify-summary').textContent='Save a prediction, then load the rerendered report.';return;}
    const shift=Number(snapshot.parameters.offset||0)-Number(model.values.offset)+number('verify-shift',0);
    const result=LoudnessAnalysis.compare(snapshot.points,current.points,metric,shift);
    const rows=result.errors;
    $('verify-summary').textContent=rows.length?`${rows.length} overlapping samples · bias ${fmt(result.bias)} · MAE ${fmt(result.mae)} · RMSE ${fmt(result.rmse)} · max error ${fmt(result.max)} LU · current measured I ${fmt(current.report.integrated)} LUFS · saved audio preview I ${fmt(snapshot.audio_preview?.predicted_i)} · I error ${fmt(Number.isFinite(snapshot.audio_preview?.predicted_i)?current.report.integrated-snapshot.audio_preview.predicted_i:NaN)} LU. ${snapshot.report.length!==current.report.length?'Different durations: verify alignment.':''}`:'No overlapping M/S samples. Check metric and alignment.';
    if(!rows.length)return;
    const magnitude=Math.max(1,result.max),rough=magnitude/3,power=10**Math.floor(Math.log10(rough));
    const step=([1,2,5,10].find(n=>n*power>=rough)||10)*power,bound=Math.ceil(magnitude/step)*step;
    const left=65,right=c.width-18,top=24,bottom=c.height-30;
    const x=t=>left+t/current.report.length*(right-left),y=v=>top+(bound-v)/(2*bound)*(bottom-top);
    context.font='11px Segoe UI';context.lineWidth=1;
    for(let value=-bound;value<=bound+step/2;value+=step){
      context.strokeStyle=value===0?'#839995':'#35403f';context.beginPath();context.moveTo(left,y(value));context.lineTo(right,y(value));context.stroke();
      context.fillStyle=value===0?'#c6dcd6':'#9cadaa';context.textAlign='right';context.fillText(`${value>0?'+':''}${Number(value.toFixed(2))}`,left-8,y(value)+4);
    }
    context.fillStyle='#9cadaa';context.textAlign='left';context.fillText('Δ LU',8,14);
    const divisions=Math.max(2,Math.min(6,Math.floor((right-left)/140)));
    for(let i=0;i<=divisions;i++){
      const time=current.report.length*i/divisions;
      context.strokeStyle='#2d3836';context.beginPath();context.moveTo(x(time),top);context.lineTo(x(time),bottom);context.stroke();
      const seconds=Math.floor(time),label=seconds>=3600?`${Math.floor(seconds/3600)}:${String(Math.floor(seconds/60)%60).padStart(2,'0')}:${String(seconds%60).padStart(2,'0')}`:`${Math.floor(seconds/60)}:${String(seconds%60).padStart(2,'0')}`;
      context.fillStyle='#9cadaa';context.textAlign='center';context.fillText(current.report.length<30?`${time.toFixed(1)} s`:label,x(time),c.height-9);
    }
    context.save();context.beginPath();context.rect(left,top,right-left,bottom-top);context.clip();
    context.strokeStyle='#4aefbc';context.lineWidth=1.5;context.beginPath();
    rows.forEach((p,i)=>context[i&&!p.break?'lineTo':'moveTo'](x(p.time),y(p.error)));context.stroke();
    // Single valid samples between gaps remain visible without connecting ramps.
    context.fillStyle='#4aefbc';rows.forEach((p,i)=>{if(p.break&&(i===rows.length-1||rows[i+1].break)){context.beginPath();context.arc(x(p.time),y(p.error),1.5,0,2*Math.PI);context.fill();}});
    context.restore();
  }
  const storageKey = 'SBP.LoudnessCurve.snapshots.v1';
  const workingKey='SBP.LoudnessCurve.session.v1';
  let savedWorking=null,restoringWorking=false;
  const viewIds=['mouse-mode','scale-mode','view-range','zoom-x','pan-x','zoom-y','center-y'];
  const sceneIds={source:'scene-source',track:'scene-track',naming:'scene-naming',metric:'scene-metric',tolerance:'scene-tolerance',dynamics_min:'scene-dyn-min',dynamics_max:'scene-dyn-max',range:'scene-range',window_start:'scene-window-start',window_span:'scene-window-span'};
  function workingData(){
    if(!state.report||!state.points.length||!state.loadedSources)return null;
    const edit=JSON.parse(captureEdit());
    return {version:1,created:new Date().toISOString(),report:{...state.report},source_files:{...state.loadedSources},destination:$('destination-track').value,
      parameters:{...edit.values,'link-limits':edit.linked},curves:edit.curves,tool:state.tool,
      view:Object.fromEntries(viewIds.map(id=>[id,$(id).value])),customCenter:state.customCenter,
      visibility:Object.fromEntries(['target','i','i-history','measured','corrected','pre','upper','lower','post','regions','editor-scenes','waveform','snapshots','grid','time-grid','scale'].filter(id=>$('show-'+id)).map(id=>[id,$('show-'+id).checked])),
      scene_profile:Object.fromEntries(Object.entries(sceneIds).map(([key,id])=>[key,$(id).value]))};
  }
  function saveWorking(){
    if(restoringWorking||state.busy)return;
    if(activeSource!=='master'){saveSourceEditor();return;}
    const data=workingData();if(!data)return;
    try{localStorage.setItem(workingKey,JSON.stringify(data));savedWorking=data;$('resume-session').disabled=false;$('download-session').disabled=false;}
    catch(_){setStatus('Session autosave unavailable. Download session to keep your work.',true);$('download-session').disabled=false;}
  }
  function validateWorking(data){
    if(!data||data.version!==1||typeof data.report?.name!=='string'||!Number.isFinite(data.report.length)||data.report.length<=0||!data.parameters||!data.curves)throw new Error('Invalid editing session');
    if(data.destination!=null&&(typeof data.destination!=='string'||data.destination.length>128||/[\x00\r\n\t]/.test(data.destination)))throw new Error('Invalid session destination track');
    const enums={normalize:['on','off','only'],metric:['short_term','momentary'], 'curve-mode':['linear','step'],standard:['custom',...Object.keys(profiles)]};
    for(const id of historyIds){
      const value=data.parameters[id]??(id==='standard'?'custom':undefined);
      if(enums[id]){if(!enums[id].includes(String(value)))throw new Error('Invalid session setting: '+id);}
      else{
        const n=Number(value),el=$(id);
        if(value==null||String(value).trim()===''||!Number.isFinite(n)||(id!=='post-volume'&&((el.min!==''&&n<Number(el.min))||(el.max!==''&&n>Number(el.max)))))throw new Error('Invalid session setting: '+id);
      }
    }
    for(const key of ['pre','upper','lower','post']){
      const points=data.curves[key];
      if(!Array.isArray(points)||points.length<2||points.length>20000)throw new Error('Invalid session curve: '+key);
      let previous=-1;
      for(const p of points){if(!Number.isFinite(p.time)||p.time<0||p.time<=previous||p.time>data.report.length||!Number.isFinite(p.value)||(p.ramp!=null&&typeof p.ramp!=='boolean'))throw new Error('Invalid session curve point');previous=p.time;}
      if(points[0].time!==0||Math.abs(points.at(-1).time-data.report.length)>1e-6)throw new Error('Session curves must cover the full render');
    }
    if(data.source_files&&(['report','audio'].some(k=>typeof data.source_files[k]!=='string'||!data.source_files[k].trim())))throw new Error('Session source paths are missing');
    if(data.view)for(const id of ['zoom-x','pan-x','zoom-y','center-y'])if(data.view[id]!=null){
      const n=Number(data.view[id]),el=$(id);
      const max=id==='zoom-x'?Math.max(100,Math.min(20000,Math.floor(data.report.length/2))):el.max;
      if(!Number.isFinite(n)||(el.min!==''&&n<Number(el.min))||(max!==''&&n>Number(max)))throw new Error('Invalid session view: '+id);
    }
    return JSON.parse(JSON.stringify(data));
  }
  function matchingWorking(data){return state.report&&state.report.source_kind===data.report.source_kind&&state.report.source_identity===data.report.source_identity&&state.report.name===data.report.name&&Math.abs(state.report.length-data.report.length)<.02&&((state.report.integrated==null&&data.report.integrated==null)||Math.abs(state.report.integrated-data.report.integrated)<.01);}
  function applyWorking(data){
    data=validateWorking(data);
    if(!matchingWorking(data))throw new Error('Saved source differs from the loaded report. Load the matching original report and audio.');
    Object.assign(state,data.curves);
    for(const id of historyIds){$(id).value=String(data.parameters[id]??(id==='standard'?'custom':''));const slider=$(id).parentElement.querySelector('input[type=range]');if(slider)slider.value=$(id).value;}
    syncOutputTrim();$('link-limits').checked=!!data.parameters['link-limits'];state.previousTarget=number('target',-23);
    clearRazor();audioEstimate=null;state.sceneMeasurement=null;
    if(data.tool&&['pre','upper','lower','post'].includes(data.tool)){
      state.tool=data.tool;document.querySelectorAll('[data-tool]').forEach(button=>button.classList[button.dataset.tool===state.tool?'add':'remove']('active'));
    }
    const views={'mouse-mode':['edit','pan','seek','razor','scan'],'scale-mode':['absolute','relative'],'view-range':['auto','focus','wide']};
    if(data.view)for(const id of viewIds){const value=data.view[id];if(views[id]?views[id].includes(value):Number.isFinite(Number(value)))$(id).value=String(value);}
    if(data.visibility)for(const [id,value] of Object.entries(data.visibility))if($('show-'+id)&&typeof value==='boolean')$('show-'+id).checked=value;
    state.customCenter=!!data.customCenter;$('razor-controls').hidden=$('mouse-mode').value!=='razor';
    if(data.scene_profile)for(const [key,id] of Object.entries(sceneIds))if(data.scene_profile[key]!=null)$(id).value=String(data.scene_profile[key]);
    calculate();renderRegions();refreshEditorScenes();
  }
  async function restoreWorking(raw){
    if(state.busy||restoringWorking)return;
    try{
      const data=validateWorking(raw);restoringWorking=true;
      if(data.report.source_kind==='stem'){
        const row=stems?.rows.find(row=>row.data&&sourceIdentity(row)===data.report.source_identity);
        if(!row)throw new Error('Measure the matching WAV stem before restoring its session or snapshot.');
        await switchSource(row);applyWorking(data);resetHistory();
        if(data.destination){await bridge.request('source-target',data.destination);selectDestination(data.destination);}
        calculate();
      }else if(data.source_files){
        if(activeSource!=='master')await switchSource(null);
        $('url').value=data.source_files.report;$('audio-path').value=data.source_files.audio;
        if(!await load({restore:data}))return;
        resetHistory();
      }else{
        applyWorking(data);commitEdit();await preview.reset(false);await refreshRegions();
      }
      restoringWorking=false;saveWorking();setStatus('Editing session restored without an audio rescan. Use Refine or Fit to target for exact loudness.');
    }catch(error){setStatus(error.message,true);}
    finally{restoringWorking=false;}
  }
  try{const stored=localStorage.getItem(workingKey);if(stored)savedWorking=validateWorking(JSON.parse(stored));}
  catch(_){setStatus('Saved session could not be read. Open a downloaded session backup.',true);}
  $('resume-session').disabled=!savedWorking;
  $('resume-session').addEventListener('click',()=>restoreWorking(savedWorking));
  $('download-session').addEventListener('click',()=>{
    const data=workingData();if(!data)return;
    const url=URL.createObjectURL(new Blob([JSON.stringify(data)],{type:'application/json'})),link=document.createElement('a');link.href=url;link.download='SBP-Loudness-Session.json';link.click();setTimeout(()=>URL.revokeObjectURL(url),10000);
  });
  $('open-session').addEventListener('click',()=>$('session-file').click());
  $('session-file').addEventListener('change',async()=>{
    try{const file=$('session-file').files[0];if(!file)return;if(file.size>16*1024*1024)throw new Error('Session exceeds 16 MB');await restoreWorking(JSON.parse(await file.text()));}
    catch(error){setStatus(error.message,true);}finally{$('session-file').value='';}
  });
  for(const id of [...viewIds,...Object.values(sceneIds)])$(id).addEventListener('change',saveWorking);
  const colors = ['#bf93e8','#f4c268','#73bbfa','#ee8cad','#a5ce78'];
  function summary(points, key, gain = false) {
    const values = points.filter(p => Number.isFinite(p[key])).map(p => p[key] + (gain ? p.gain : 0)).sort((a,b) => a-b);
    return values.length ? `${fmt(values[Math.floor(values.length/2)])} / ${fmt(values[values.length-1])}` : '—';
  }
  function snapshotFingerprint(snapshot){
    if(snapshot.fingerprint)return snapshot.fingerprint;
    const audio=snapshot.audio_preview||{},metadata=snapshot.report.metadata||{};
    const result={before:{},after:{}};
    for(const [side,prefix] of [['before','original'],['after','predicted']]){
      const dest=result[side];
      for(const key of ['i','lra','crest','rms','m_max','s_max'])dest[key]=audio[`${prefix}_${key}`]??null;
      dest.true_peak=audio[`${prefix}_peak`]??null;
    }
    result.before.i??=snapshot.report.integrated;
    result.before.lra??=metadata.lra;
    result.before.true_peak??=metadata.true_peak;
    for(const side of ['before','after']){
      const dest=result[side],after=side==='after';
      for(const [key,metric] of [['m','momentary'],['s','short_term']]){
        const text=snapshot.summaries?.[`${after?'predicted':'measured'}${key.toUpperCase()}`]||summary(snapshot.points,metric,after);
        const [median,max]=text.split('/').map(v=>Number(v.trim()));
        dest[`${key}_median`]=Number.isFinite(median)?median:null;
        dest[`${key}_max`]??=Number.isFinite(max)?max:null;
      }
      dest.plr=Number.isFinite(dest.true_peak)&&Number.isFinite(dest.i)?dest.true_peak-dest.i:null;
    }
    return result;
  }
  function makeSnapshot(label = 'Snapshot') {
    if (!state.report || !state.calculated.length) return null;
    const parameters = {};
    const gains = new Map(state.calculated.map(p => [p.time,p.gain]));
    const summaryPoints = state.points.map(p => ({...p, gain:gains.get(p.time)}));
    const verifiedAudio=audioEstimate?.key===audioKey()&&Number.isFinite(audioEstimate.original_i)&&Math.abs(audioEstimate.original_i-state.report.integrated)<=.3;
    for (const id of historyIds) parameters[id] = $(id).value;
    parameters['link-limits']=$('link-limits').checked;
    const snapshot={id: `${Date.now()}-${Math.random().toString(36).slice(2)}`,
      name: $('snapshot-name').value.trim() || label,
      created: new Date().toISOString(), report: {...state.report}, parameters,
      source_files:state.loadedSources?{...state.loadedSources}:null,destination:$('destination-track').value,
      curves: {pre: state.pre, upper: state.upper, lower: state.lower, post: state.post},
      audio_preview:verifiedAudio?Object.fromEntries(Object.entries(audioEstimate).filter(([key])=>(/^(original_|predicted_)/.test(key)||['channels','channel_layout','sample_rate','measurement_engine'].includes(key)))):null,
      scene_profile:{source:$('scene-source').value,track:$('scene-track').value,naming:$('scene-naming').value,metric:$('scene-metric').value,tolerance:number('scene-tolerance',3),dynamics_min:number('scene-dyn-min',0),dynamics_max:number('scene-dyn-max',18),scenes:sceneRows()},
      base: baseGain(), trim: postGain(), visible: true, color: colors[state.snapshots.length % colors.length],
      summaries: {measuredM: summary(state.points,'momentary'), measuredS: summary(state.points,'short_term'), predictedM: summary(summaryPoints,'momentary',true), predictedS: summary(summaryPoints,'short_term',true)},
      points: state.calculated.map(p => ({time:p.time, momentary: measuredAtMetric(p.time,'momentary'), short_term: measuredAtMetric(p.time,'short_term'), peak: measuredAtMetric(p.time,'peak'), gain:p.gain}))};
    if(snapshot.points.length>20000){
      snapshot.full_point_count=snapshot.points.length;
      const source=snapshot.points,kept=new Set([0,source.length-1]),size=Math.ceil(source.length/500);
      for(let start=0;start<source.length;start+=size)for(const key of ['momentary','short_term','peak','gain']){
        let low=start,high=start;
        for(let i=start;i<Math.min(source.length,start+size);i++){if(Number.isFinite(source[i][key])&&(!Number.isFinite(source[low][key])||source[i][key]<source[low][key]))low=i;if(Number.isFinite(source[i][key])&&(!Number.isFinite(source[high][key])||source[i][key]>source[high][key]))high=i;}
        kept.add(low);kept.add(high);
      }
      snapshot.points=[...kept].sort((a,b)=>a-b).map(i=>source[i]);
    }
    snapshot.fingerprint=snapshotFingerprint(snapshot);return snapshot;
  }
  function persistSnapshots() {
    try {localStorage.setItem(storageKey, JSON.stringify(state.snapshots));}
    catch (_) {setStatus('Local storage unavailable or full. Download the library to keep snapshots.', true);}
  }
  function addSnapshot(snapshot) {
    if (!snapshot) return;
    if (snapshot.points.length > 20000) {setStatus('Too many curve points for a snapshot. Simplify the drawing first.', true); return;}
    // Detach parameters, curves and points from the editable report.
    if (state.snapshots.length >= 100) {setStatus('Library full. Download a backup and delete unused snapshots.', true); return;}
    state.snapshots.push(JSON.parse(JSON.stringify(snapshot)));
    persistSnapshots(); renderSnapshots(); draw();
  }
  function snapshotTrim(snapshot){const trim=snapshot.trim??Number(snapshot.parameters['post-volume']||0),legacy=Number(snapshot.parameters['final-gain']||0);return trim+(Number.isFinite(legacy)?legacy:0);}
  function renderSnapshots() {
    const list = $('snapshot-list'); list.replaceChildren();
    for (const snapshot of state.snapshots) {
      const row = document.createElement('tr'); row.className = 'snapshot-fingerprint';
      const toggle = document.createElement('input'); toggle.type = 'checkbox'; toggle.checked = snapshot.visible;
      toggle.setAttribute('aria-label', `Overlay ${snapshot.name}`);
      toggle.addEventListener('change', () => {snapshot.visible = toggle.checked; persistSnapshots(); draw();});
      const cell=value=>{const td=document.createElement('td');td.textContent=value;row.appendChild(td);return td;};
      const overlay=cell('');overlay.appendChild(toggle);
      const detail = cell('');
      const title = document.createElement('strong'); title.textContent = snapshot.name; title.style.color = snapshot.color;
      const info = document.createElement('small');info.textContent=snapshot.report.name;
      detail.title=`${new Date(snapshot.created).toLocaleString()} · ${(snapshot.report.length/60).toFixed(1)} min · offset ${snapshot.parameters.offset}s · output trim ${fmt(snapshotTrim(snapshot))} dB. Overlay: dotted source / dashed estimate.${snapshot.full_point_count?' Reduced display history; full summaries and edit curves retained.':''}${state.report&&Math.abs(state.report.length-snapshot.report.length)>.1?' Different duration; check alignment.':''}`;
      detail.append(title, info);
      const fingerprint=snapshotFingerprint(snapshot),pair=key=>`${fmt(fingerprint.before[key])} → ${fmt(fingerprint.after[key])}`;
      for(const key of ['i','lra','true_peak','plr','crest','rms']){
        const td=cell(pair(key));td.title=key==='i'?'Before: report/audio I. After: offline audio preview; — if not measured.':'Before source / after gain-model audio measurement; — if unavailable.';
      }
      cell(`M ${pair('m_median')} · S ${pair('s_median')}`).title='Sampled medians, not integrated loudness';
      cell(`M ${pair('m_max')} · S ${pair('s_max')}`).title='Audio scanner maxima if measured; otherwise sampled report maxima';
      cell(`${snapshot.parameters.target} / ${fmt(snapshotTrim(snapshot))} dB`);
      const sceneCell=cell(''),scenes=snapshot.scene_profile?.scenes||[];
      if(scenes.length){
        const details=document.createElement('details'),heading=document.createElement('summary');heading.textContent=`${scenes.length} scenes`;
        const table=document.createElement('table');table.className='fingerprint-table';
        const header=document.createElement('tr');for(const text of ['Scene','I / S median','LRA','Crest','PLR']){const th=document.createElement('th');th.textContent=text;header.appendChild(th);}table.appendChild(header);
        for(const scene of scenes){const tr=document.createElement('tr');tr.title=scene.basis==='audio'?'Audio I before / gain-model I after':'Sampled S median before / estimate after';for(const text of [scene.name,...[scene.basis==='audio'?'i':'level','lra','crest','plr'].map(key=>`${fmt(scene.before[key])} → ${fmt(scene.after[key])}`)]){const td=document.createElement('td');td.textContent=text;tr.appendChild(td);}table.appendChild(tr);}
        details.append(heading,table);sceneCell.appendChild(details);
      }else sceneCell.textContent='—';
      const remove = document.createElement('button'); remove.textContent = 'Delete';
      remove.addEventListener('click', () => {state.snapshots = state.snapshots.filter(s => s.id !== snapshot.id); persistSnapshots(); renderSnapshots(); draw();});
      const restore=document.createElement('button');restore.textContent='Restore';restore.title='Restore these curves and settings for editing';
      restore.disabled=!snapshot.curves;
      restore.addEventListener('click',()=>restoreWorking({version:1,report:snapshot.report,source_files:snapshot.source_files,destination:snapshot.destination,parameters:{...snapshot.parameters,'post-volume':String(snapshotTrim(snapshot))},curves:snapshot.curves,scene_profile:snapshot.scene_profile}));
      cell('').append(restore,remove); list.appendChild(row);
    }
    if (!state.snapshots.length){const row=document.createElement('tr'),cell=document.createElement('td');cell.colSpan=13;cell.textContent='No saved snapshots.';row.appendChild(cell);list.appendChild(row);}
    const selected=$('verify-snapshot').value;
    $('verify-snapshot').replaceChildren();
    for(const snapshot of state.snapshots){const option=document.createElement('option');option.value=snapshot.id;option.textContent=snapshot.name;$('verify-snapshot').appendChild(option);}
    $('verify-snapshot').value=state.snapshots.some(s=>s.id===selected)?selected:(state.snapshots[0]?.id||'');
    renderVerification();
  }
  function validateLibrary(value) {
    if (!Array.isArray(value) || value.length > 100) throw new Error('Invalid snapshot library (maximum 100 snapshots).');
    const ids = new Set();
    for (const s of value) {
      if (!s || typeof s.id !== 'string' || ids.has(s.id) || typeof s.name !== 'string' || !Number.isFinite(s.report?.length) || s.report.length <= 0 || !s.parameters || !Array.isArray(s.points) || s.points.length < 2 || s.points.length > 20000 || !Number.isFinite(s.base) || !/^#[0-9a-f]{6}$/i.test(s.color) || !Number.isFinite(Date.parse(s.created))) throw new Error('Invalid snapshot data.');
      ids.add(s.id);
      if(s.fingerprint&&(!s.fingerprint.before||!s.fingerprint.after))throw new Error('Invalid loudness fingerprint');
      if(s.scene_profile){
        const scenes=s.scene_profile.scenes;
        if(!Array.isArray(scenes)||scenes.length>2000)throw new Error('Invalid scene fingerprint collection');
        for(const scene of scenes)if(typeof scene.name!=='string'||!Number.isFinite(scene.start)||!Number.isFinite(scene.finish)||scene.start<0||scene.finish<=scene.start||scene.finish>s.report.length+.1||!scene.before||!scene.after)throw new Error('Invalid scene fingerprint');
      }
      let previous = -1;
      for (const p of s.points) {
        if (!Number.isFinite(p.time) || p.time <= previous || p.time > s.report.length + .1 || !Number.isFinite(p.gain) || (p.short_term != null && !Number.isFinite(p.short_term)) || (p.momentary != null && !Number.isFinite(p.momentary)) || (!['stem','audio'].includes(s.report.source_kind)&&p.short_term == null && p.momentary == null)) throw new Error('Invalid snapshot points.');
        previous = p.time;
      }
    }
    return value;
  }
  $('capture').addEventListener('click', () => {
    if (state.snapshots.length >= 100) {setStatus('Library full. Download a backup and delete unused snapshots.', true); return;}
    if (!state.busy) addSnapshot(makeSnapshot());
  });
  $('backup').addEventListener('click', () => {
    const url = URL.createObjectURL(new Blob([JSON.stringify(state.snapshots)], {type:'application/json'}));
    const link = document.createElement('a'); link.href = url; link.download = 'SBP-Loudness-Snapshots.json'; link.click();
    setTimeout(() => URL.revokeObjectURL(url), 10000);
  });
  $('restore').addEventListener('click', () => $('snapshot-file').click());
  $('snapshot-file').addEventListener('change', async () => {
    try {
      const file = $('snapshot-file').files[0]; if (!file) return;
      if (file.size > 16 * 1024 * 1024) throw new Error('Library exceeds 16 MB.');
      const incoming = validateLibrary(JSON.parse(await file.text()));
      const merged = [...state.snapshots, ...incoming.filter(s => !state.snapshots.some(old => old.id === s.id))];
      state.snapshots = validateLibrary(merged); persistSnapshots(); renderSnapshots(); draw();
    } catch (error) {setStatus(error.message, true);}
    finally {$('snapshot-file').value = '';}
  });
  try {state.snapshots = validateLibrary(JSON.parse(localStorage.getItem(storageKey) || '[]'));}
  catch (_) {setStatus('Saved library could not be read. Import a downloaded backup.', true);}
  renderSnapshots();
  const snapshotPrefsKey='SBP.LoudnessCurve.snapshotAuto';
  try{$('snapshot-auto').checked=localStorage.getItem(snapshotPrefsKey)!=='false';}catch(_){}
  $('snapshot-auto').addEventListener('change',()=>{try{localStorage.setItem(snapshotPrefsKey,String($('snapshot-auto').checked));}catch(_){setStatus('The export autosave preference could not be stored.',true);}});
  for (const id of ['post-volume','target','upper','lower','high-ratio','low-ratio','max-cut','max-boost','silence','smooth']) {
    const input = $(id);
    const slider = document.createElement('input');
    slider.type = 'range'; slider.min = input.min; slider.max = input.max;
    slider.step = input.step; slider.value = input.value;
    slider.setAttribute('aria-label', input.parentElement.firstChild.textContent.trim() + ' slider');
    input.parentElement.appendChild(slider);
    slider.addEventListener('input', () => {
      input.value = slider.value;
      input.dispatchEvent(new Event('input', {bubbles: true}));
    });
    input.addEventListener('input', () => {if(id==='post-volume')syncOutputTrim();else slider.value = input.value;});
    // Target shifts both limits, so synchronize their sliders as well.
    if (id === 'target') input.addEventListener('input', () => {
      for (const key of ['upper','lower']) {
        const rangeInput = $(key).parentElement.querySelector('input[type=range]');
        if (rangeInput) rangeInput.value = $(key).value;
      }
    });
  }
  for (const id of ['target','i','i-history','measured','corrected','pre','post','upper','lower','snapshots','grid','time-grid','scale','regions','waveform']) $('show-' + id).addEventListener('change',()=>{draw();saveWorking();});
  $('scale-mode').addEventListener('change', draw);
  $('view-range').addEventListener('change', () => {$('zoom-y').value='1';state.customCenter=false;draw();});
  $('curve-mode').addEventListener('change', calculate);
  $('standard').addEventListener('change',()=>{
    const profile=profiles[$('standard').value];
    if(profile){clearRazor();$('target').value=String(profile.target);$('target').dispatchEvent(new Event('input',{bubbles:true}));}
    else calculate();
  });
  $('link-limits').addEventListener('change',()=>{clearRazor();if($('link-limits').checked)for(const key of ['pre','upper','lower'])$('show-'+key).checked=true;calculate();});
  $('load').addEventListener('click',load);
  $('url').addEventListener('keydown',event => {if(event.key==='Enter')load();});
  $('export').addEventListener('click',exportCurve);
  $('reset').addEventListener('click',resetActiveCurve);
  document.querySelectorAll('.tool[data-tool]').forEach(button => button.addEventListener('click',() => {
    document.querySelectorAll('.tool[data-tool]').forEach(other=>other.classList.remove('active'));
    button.classList.add('active');state.tool=button.dataset.tool;clearRazor();draw();saveWorking();
  }));
  for(const id of ['post-volume','normalize','metric','high-ratio','low-ratio','max-cut','max-boost','silence','smooth'])
    $(id).addEventListener('input',calculate);
  $('target').addEventListener('input',() => {
    const next = number('target', state.previousTarget);
    const shift = next - state.previousTarget;
    state.previousTarget = next;
    for (const key of ['upper','lower']) {
      const updated = clamp(number(key,key==='upper'?-20:-26)+shift,-60,0);
      $(key).value = updated.toFixed(1);
      state[key].forEach(point => {point.value = clamp(point.value+shift,-60,0);});
    }
    for (const key of ['upper','lower']) $(key).parentElement.querySelector('input[type=range]').value = $(key).value;
    calculate();
  });
  for(const [id,key] of [['upper','upper'],['lower','lower']]) $(id).addEventListener('input',() => {
    if(state.report) {const value=number(id,key==='upper'?-20:-26);state[key]=[
      {time:0,value},{time:state.report.length,value}];calculate();}
  });
  function clearRazor() {
    state.razor=null;state.razorDrag=null;
    $('razor-gain').value='0';$('razor-ramp').value='0';
    $('razor-gain-value').textContent=$('snap-level').checked?'0':'0.0';$('razor-ramp-value').textContent='0.00';
    $('razor-range').textContent='Drag across the graph to select a Razor area.';
  }
  function applyRazor() {
    const r=state.razor;
    if(!r || !shaping() || !visible(r.tool))return;
    const start=Math.min(r.start,r.end),end=Math.max(r.start,r.end);
    if(end-start<.001)return;
    r.gain=number('razor-gain',0);if($('snap-level').checked)r.gain=Math.round(r.gain);$('razor-gain').value=String(r.gain);r.ramp=number('razor-ramp',0);
    $('razor-gain-value').textContent=$('snap-level').checked?String(r.gain):fmt(r.gain);$('razor-ramp-value').textContent=r.ramp.toFixed(2);
    $('razor-range').textContent=`${r.tool.toUpperCase()} · ${start.toFixed(2)}–${end.toFixed(2)} s`;
    if(r.gain===0){state[r.tool]=r.original.map(p=>({...p}));calculate();return;}
    const ramp=Math.max(.002,r.ramp),left=Math.max(0,start-ramp),right=Math.min(state.report.length,end+ramp);
    const times=new Set([left,start,end,right,...r.original.filter(p=>p.time>=left&&p.time<=right).map(p=>p.time)]);
    const adjusted=[...times].sort((a,b)=>a-b).map(time=>{
      const weight=time<start ? (time-left)/Math.max(.000001,start-left) : time>end ? (right-time)/Math.max(.000001,right-end) : 1;
      const original=r.original.find(p=>p.time===time);
      const point={time,value:interpolate(r.original,time)+r.gain*clamp(weight,0,1)};
      if($('snap-level').checked&&weight>0){const level=pointLevel(r.tool,time,point.value);point.value+=snapLevel(level)-level;}
      if(r.tool!=='post')point.value=clamp(point.value,r.tool==='pre'?-24:-80,r.tool==='pre'?24:0);
      if(time<start || (time>=end && time<right))point.ramp=true;
      else if(original?.ramp)point.ramp=true;
      return point;
    });
    state[r.tool]=[...r.original.filter(p=>p.time<left).map(p=>({...p})),...adjusted,...r.original.filter(p=>p.time>right).map(p=>({...p}))];
    if(state.razorDrag?.mode==='level'){const point=adjusted.find(p=>p.time===start);if(point)pointReadout(point,pointLevel(r.tool,point.time,point.value));}
    calculate();
  }
  function syncRazorUI(){
    const razor=$('mouse-mode').value==='razor';$('edit-point-controls').hidden=$('mouse-mode').value!=='edit';$('edit-point-window-control').hidden=!$('edit-three-points').checked;$('razor-controls').hidden=!razor;$('snap-boundaries-control').hidden=!razor;
    $('razor-gain').step=$('snap-level').checked?'1':'0.1';
  }
  try{$('edit-three-points').checked=localStorage.getItem('SBP.LoudnessCurve.threePoints.v1')==='true';$('edit-point-window').value=localStorage.getItem('SBP.LoudnessCurve.pointWindow.v1')||'1';}catch(_){}
  for(const [id,key] of [['edit-three-points','SBP.LoudnessCurve.threePoints.v1'],['edit-point-window','SBP.LoudnessCurve.pointWindow.v1']])$(id).addEventListener('change',()=>{try{localStorage.setItem(key,id==='edit-three-points'?String($(id).checked):$(id).value);}catch(_){}syncRazorUI();});
  syncRazorUI();
  $('mouse-mode').addEventListener('change',()=>{syncRazorUI();state.drag=false;state.pointDrag=null;state.razorDrag=null;canvas.style.cursor='crosshair';state.scanTime=null;renderScanner();draw();});
  $('razor-gain').addEventListener('input',applyRazor);$('razor-ramp').addEventListener('input',applyRazor);
  $('clear-razor').addEventListener('click',()=>{clearRazor();draw();});
  function resetViewport() {
    $('zoom-x').value='1'; $('pan-x').value='0'; $('zoom-y').value='1';state.customCenter=false;
  }
  function renderRegions() {
    renderTimelineStrip($('region-strip'),state.regions,visible('regions'),'regions');
    renderTimelineStrip($('editor-scene-strip'),state.editorScenes||[],$('show-editor-scenes').checked,'scenes');
    const sceneHeight=parseFloat($('editor-scene-strip').style.height)||0;
    $('graph-frame').style.setProperty?.('--editor-scene-space',`${sceneHeight?sceneHeight+4:0}px`);
  }
  function renderTimelineStrip(strip,items,enabled,label){
    strip.replaceChildren();
    if (!enabled || !state.report) {strip.style.height='0px';return;}
    const {start,end} = state.viewport, lanes=[];
    // Assign lanes on the complete, sorted timeline so panning cannot change
    // a region's row. Ignore sub-microsecond boundary roundoff only.
    const regions=items.filter(r=>Number.isFinite(r.start)&&Number.isFinite(r.finish)&&r.finish>r.start)
      .slice().sort((a,b)=>a.start-b.start||b.finish-a.finish);
    for (const region of regions) {
      let lane=lanes.findIndex(finish => finish <= region.start+1e-6);if(lane<0)lane=lanes.length;
      lanes[lane]=Math.max(lanes[lane]??-Infinity,region.finish);
      if (region.finish <= start || region.start >= end) continue;
      const block=document.createElement('div');block.className='region-block';block.textContent=region.name;
      block.title=`${region.name} · project ${region.project_start.toFixed(3)}–${region.project_finish.toFixed(3)} s`;
      block.style.left=`${(Math.max(start,region.start)-start)/(end-start)*100}%`;
      block.style.width=`${(Math.min(end,region.finish)-Math.max(start,region.start))/(end-start)*100}%`;
      block.style.top=`${lane*24}px`;block.style.backgroundColor=region.color;
      strip.appendChild(block);
    }
    strip.style.height=`${Math.max(1,lanes.length)*24}px`;
    if (!lanes.length) {const note=document.createElement('div');note.className='muted';note.textContent=`No ${label} in this view`;strip.appendChild(note);}
  }
  async function refreshEditorScenes(){
    if(!state.report||!($('show-editor-scenes').checked||$('snap-boundaries').checked))return;
    const token=state.editorSceneToken=(state.editorSceneToken||0)+1,source=activeSource;
    try{
      const value=await bridge.request('editor-scenes',`${number('offset',0)}~${$('scene-source').value||'regions'}~${$('scene-naming').value||'auto'}~${$('scene-track').value.trim()}`);
      if(token!==state.editorSceneToken||source!==activeSource)return;
      if(!Array.isArray(value.scenes))throw new Error('Editor scenes are unavailable');
      state.editorScenes=value.scenes;renderRegions();
    }catch(error){if(token===state.editorSceneToken){state.editorScenes=[];renderRegions();setStatus(error.message,true);}}
  }
  async function refreshRegions() {
    if (!state.report) return;
    const token=++state.regionToken;
    try {
      const result=await bridge.request('regions',String(number('offset',0)));
      if(token!==state.regionToken)return;
      state.regions=result.regions;renderRegions();await refreshEditorScenes();
    } catch(error) {if(token===state.regionToken)setStatus(error.message,true);}
  }
  async function loadWaveform(dropCache=true,measure=true) {
    if (!state.report || state.busy) return;
    state.sceneMeasurement=null;
    await preview.reset(dropCache!==false);
    const token=++state.waveToken;state.waveform=null;$('load-waveform').disabled=true;
    clearWaveDetails();state.busy=true;$('load').disabled=true;calculate();
    state.waveLoading=true;$('cancel-measure').hidden=false;$('cancel-measure').disabled=false;$('measure-progress').hidden=false;$('measure-progress').removeAttribute('value');
    try {
      const path=audioPath();
      let result=await bridge.request('waveform-load',path);
      do {
        if(token!==state.waveToken)return;
        $('waveform-note').textContent='Building audio peaks…';
        $('audio-estimate').textContent='Building waveform peaks…';
        if(result.building) await new Promise(resolve=>setTimeout(resolve,100));
        if(token!==state.waveToken)return;
        result=await bridge.request('waveform-poll');
      } while(result.building);
      if(token!==state.waveToken)return;
      const wave={...result,points:[]};
      for(let offset=0;offset<result.count;offset+=128) {
        const chunk=await bridge.request('waveform-chunk',String(offset));
        if(token!==state.waveToken)return;
        wave.points.push(...chunk.points);
      }
      state.waveform=wave;
      $('waveform-note').textContent=`${wave.name} · waveform overview · ${(wave.length/60).toFixed(1)} min · amplitude is not LUFS.${Math.abs(wave.length-state.report.length)>.1 ? ' Duration differs from the report: verify the chosen file; no stretching is applied.' : ''}`;
      draw();
    } catch(error) {if(token===state.waveToken)$('waveform-note').textContent=error.message;}
    finally {if(token===state.waveToken){state.waveLoading=false;endScan();state.busy=false;$('load').disabled=false;$('load-waveform').disabled=false;calculate();}}
    if(token===state.waveToken&&measure)await measureAudio(false,true);
    else if(token===state.waveToken){$('audio-estimate').textContent='Refine or Fit to target to measure the active gain curve.';renderAudioEstimate();}
  }
  $('load-waveform').addEventListener('click',loadWaveform);
  $('clear-waveform').addEventListener('click',async()=>{
    if(state.measurementActive||(state.busy&&!state.waveLoading))return;
    ++state.waveToken;state.waveform=null;clearWaveDetails();state.waveLoading=false;state.busy=false;endScan();$('load').disabled=false;$('load-waveform').disabled=false;$('waveform-note').textContent='No rendered audio loaded.';draw();
    try {await bridge.request('waveform-clear');}catch(error){setStatus(error.message,true);}
  });
  $('refresh-regions').addEventListener('click',refreshRegions);
  $('offset').addEventListener('change',refreshRegions);
  $('offset').addEventListener('input',calculate);
  for(const id of ['zoom-x','pan-x','zoom-y']) $(id).addEventListener('input',draw);
  $('center-y').addEventListener('input',()=>{state.customCenter=true;draw();});
  $('fit-view').addEventListener('click',()=>{resetViewport();draw();});
  function zoomAt(event,vertical) {
    const rect=canvas.getBoundingClientRect();
    const control=$(vertical?'zoom-y':'zoom-x'), previous=Number(control.value);
    const next=clamp(previous*Math.exp(-event.deltaY*.002),1,Number(control.max));
    if(vertical) {
      const fraction=clamp((event.clientY-rect.top-pad.top)/(rect.height-pad.top-pad.bottom),0,1);
      const span=range.max-range.min, anchor=range.max-fraction*span, newSpan=span*previous/next;
      state.customCenter=true;$('center-y').value=String(anchor+(fraction-.5)*newSpan);
    } else {
      const length=state.report.length, fraction=clamp((event.clientX-rect.left-pad.left)/(rect.width-pad.left-pad.right),0,1);
      const anchor=state.viewport.start+fraction*(state.viewport.end-state.viewport.start), newSpan=length/next;
      $('pan-x').value=String(next===1?0:clamp((anchor-fraction*newSpan)/(length-newSpan)*100,0,100));
    }
    control.value=String(next);draw();
  }
  canvas.addEventListener('wheel',event=>{
    if(!state.report)return;event.preventDefault();
    if(event.shiftKey){$('pan-x').value=String(clamp(number('pan-x',0)+event.deltaY*.03,0,100));draw();}
    else zoomAt(event,event.ctrlKey || event.metaKey);
  },{passive:false});
  function nearestBoundary(time){
    if(!$('snap-boundaries').checked||!state.report)return null;
    const width=Math.max(1,canvas.getBoundingClientRect().width-pad.left-pad.right),tolerance=(state.viewport.end-state.viewport.start)*8/width;
    let nearest=null;
    for(const item of [...state.regions,...(state.editorScenes||[])])for(const edge of [item.start,item.finish]){
      const distance=Math.abs(edge-time);
      if(Number.isFinite(edge)&&edge>=0&&edge<=state.report.length&&distance<=tolerance&&(!nearest||distance<nearest.distance))nearest={time:edge,distance};
    }
    return nearest;
  }
  function snapBoundaryTime(time){return nearestBoundary(time)?.time??time;}
  canvas.addEventListener('pointerdown',event=>{
    if(!state.report || event.button===2)return;
    if(event.button===0&&(event.altKey||$('mouse-mode').value==='seek')){event.preventDefault();preview.seek(graphPosition(event).time);return;}
    if(event.button===0&&$('mouse-mode').value==='scan'){state.scanTime=graphPosition(event).time;renderScanner();return;}
    canvas.setPointerCapture(event.pointerId);
    if(event.button===1 || $('mouse-mode').value==='pan') {
      event.preventDefault();state.panning={x:event.clientX,y:event.clientY,start:state.viewport.start,
        span:state.viewport.end-state.viewport.start,min:range.min,max:range.max};return;
    }
    if($('mouse-mode').value==='razor') {
      if(state.busy || !shaping() || !visible(state.tool))return;
      const rect=canvas.getBoundingClientRect(),px=event.clientX-rect.left,py=event.clientY-rect.top;
      const r=state.razor;
      const mode=razorHit(px,py);
      if(mode)state.razorDrag={mode,x:event.clientX,y:event.clientY,gain:r.gain,ramp:r.ramp,start:Math.min(r.start,r.end),end:Math.max(r.start,r.end),
        levelSpan:range.max-range.min,timeSpan:state.viewport.end-state.viewport.start};
      else {
        const time=snapBoundaryTime(graphPosition(event).time);
        state.razor={start:time,end:time,tool:state.tool,gain:0,ramp:0,original:state[state.tool].map(p=>({...p}))};
        $('razor-gain').value='0';$('razor-ramp').value='0';
        const gainRange=state.tool==='post'?Math.max(120,range.max-range.min):24;
        $('razor-gain').min=String(-gainRange);$('razor-gain').max=String(gainRange);
        $('razor-ramp').max=String(state.report.length);
        state.razorDrag={mode:'select'};draw();
      }
      return;
    }
    state.draggedPost=null;state.drag=true;beginPointEdit(event);
  });
  canvas.addEventListener('pointerleave',()=>{state.scanTime=null;renderScanner();if(!state.drag&&!state.razorDrag)$('point-readout').hidden=true;});
  canvas.addEventListener('pointermove',event=>{
    if($('mouse-mode').value==='scan'&&!state.panning){state.scanTime=graphPosition(event).time;renderScanner();return;}
    if(state.razorDrag) {
      const d=state.razorDrag,rect=canvas.getBoundingClientRect();
      if(d.mode==='select') {state.razor.end=snapBoundaryTime(graphPosition(event).time);$('razor-range').textContent=`${state.tool.toUpperCase()} · ${Math.min(state.razor.start,state.razor.end).toFixed(2)}–${Math.max(state.razor.start,state.razor.end).toFixed(2)} s`;draw();}
      else if(['move','left','right'].includes(d.mode)){
        const delta=(event.clientX-d.x)/(rect.width-pad.left-pad.right)*d.timeSpan;
        if(d.mode==='move'){
          let shift=clamp(delta,-d.start,state.report.length-d.end);
          const left=nearestBoundary(d.start+shift),right=nearestBoundary(d.end+shift),snap=left&&right?(left.distance<=right.distance?{...left,edge:d.start+shift}:{...right,edge:d.end+shift}):left?{...left,edge:d.start+shift}:right?{...right,edge:d.end+shift}:null;
          if(snap)shift=clamp(shift+snap.time-snap.edge,-d.start,state.report.length-d.end);
          state.razor.start=d.start+shift;state.razor.end=d.end+shift;
        }else if(d.mode==='left'){
          state.razor.start=clamp(snapBoundaryTime(d.start+delta),0,d.end-.002);state.razor.end=d.end;
        }else{
          state.razor.start=d.start;state.razor.end=clamp(snapBoundaryTime(d.end+delta),d.start+.002,state.report.length);
        }
        applyRazor();
      }
      else {
        if(d.mode==='level')$('razor-gain').value=String(clamp(d.gain+(d.y-event.clientY)/(rect.height-pad.top-pad.bottom)*d.levelSpan,Number($('razor-gain').min),Number($('razor-gain').max)));
        else $('razor-ramp').value=String(clamp(d.ramp+(d.x-event.clientX)/(rect.width-pad.left-pad.right)*d.timeSpan,0,state.report.length));
        applyRazor();
      }
    } else if(state.panning) {
      const p=state.panning,rect=canvas.getBoundingClientRect(),length=state.report.length;
      const start=p.start-(event.clientX-p.x)/(rect.width-pad.left-pad.right)*p.span;
      $('pan-x').value=String(length===p.span?0:clamp(start/(length-p.span)*100,0,100));
      state.customCenter=true;$('center-y').value=String((p.min+p.max)/2+(event.clientY-p.y)/(rect.height-pad.top-pad.bottom)*(p.max-p.min));draw();
    } else if(state.drag)dragPoint(event);
    else if($('mouse-mode').value==='razor'){
      const rect=canvas.getBoundingClientRect(),mode=razorHit(event.clientX-rect.left,event.clientY-rect.top);
      canvas.style.cursor=['left','right','ramp'].includes(mode)?'ew-resize':mode==='level'?'ns-resize':mode==='move'?'grab':'crosshair';
    }
  });
  for(const type of ['pointerup','pointercancel'])canvas.addEventListener(type,()=>{state.drag=false;state.pointDrag=null;state.panning=null;state.draggedPost=null;state.razorDrag=null;$('point-readout').hidden=true;});
  canvas.addEventListener('contextmenu',event=>{event.preventDefault();if(event.altKey||['seek','scan'].includes($('mouse-mode').value))return;if($('mouse-mode').value==='razor'){clearRazor();draw();}else if($('mouse-mode').value!=='pan')edit(event,true);});
  canvas.addEventListener('dblclick',event=>{if($('mouse-mode').value==='edit' && !event.altKey)edit(event,true);});
  $('analysis-panel').addEventListener('toggle',renderAnalysis);
  $('constellation-panel').addEventListener('toggle',async()=>{if($('constellation-panel').open&&state.sceneDefinition!==sceneDefinitionKey())await refreshScenes();else renderConstellation();});
  $('scene-refresh').addEventListener('click',refreshScenes);$('scene-measure').addEventListener('click',measureScenes);
  for(const [id,key] of [['snap-boundaries','SBP.LoudnessCurve.boundarySnap.v1'],['show-editor-scenes','SBP.LoudnessCurve.editorScenes.v1']])$(id).addEventListener('change',()=>{try{localStorage.setItem(key,String($(id).checked));}catch(_){}renderRegions();return refreshEditorScenes();});
  for(const id of ['scene-source','scene-track','scene-naming'])$(id).addEventListener('change',refreshEditorScenes);
  for(const id of ['scene-range','scene-window-start','scene-window-span'])$(id).addEventListener('change',()=>{state.sceneWindowDraft=true;renderSceneNavigator();return refreshScenes();});
  $('scene-window-position').addEventListener('input',()=>{state.sceneWindowDraft=true;$('scene-window-start').value=String(number('scene-window-position',0)/60);renderSceneNavigator();});
  $('scene-window-position').addEventListener('change',refreshScenes);
  $('scene-use-view').addEventListener('click',()=>{state.sceneWindowDraft=true;$('scene-range').value='window';$('scene-window-start').value=String(state.viewport.start/60);$('scene-window-span').value=String((state.viewport.end-state.viewport.start)/60);renderSceneNavigator();return refreshScenes();});
  let sceneNavDrag=null;
  function moveSceneWindow(event){
    if(!sceneNavDrag)return;const rect=$('scene-window-timeline').getBoundingClientRect();
    const start=clamp((event.clientX-rect.left)/Math.max(1,rect.width)*sceneNavDrag.length-sceneNavDrag.grab,0,sceneNavDrag.max);
    state.sceneWindowDraft=true;$('scene-window-start').value=(start/60).toFixed(6);renderSceneNavigator();
  }
  $('scene-window-timeline').addEventListener('pointerdown',event=>{
    const model=analysisModel('constellation');if(state.busy||!model?.state.report||$('scene-range').value!=='window'||event.button>0)return;
    const length=model.state.report.length,window=sceneWindow(model),rect=$('scene-window-timeline').getBoundingClientRect(),time=(event.clientX-rect.left)/Math.max(1,rect.width)*length;
    sceneNavDrag={length,max:length-(window.end-window.start),original:window.start,grab:time>=window.start&&time<=window.end?time-window.start:(window.end-window.start)/2};
    $('scene-window-timeline').setPointerCapture(event.pointerId);moveSceneWindow(event);
  });
  $('scene-window-timeline').addEventListener('pointermove',moveSceneWindow);
  $('scene-window-timeline').addEventListener('pointerup',event=>{if(!sceneNavDrag)return;moveSceneWindow(event);sceneNavDrag=null;saveWorking();return refreshScenes();});
  $('scene-window-timeline').addEventListener('pointercancel',()=>{if(!sceneNavDrag)return;$('scene-window-start').value=(sceneNavDrag.original/60).toFixed(6);sceneNavDrag=null;state.sceneWindowDraft=false;renderSceneNavigator();});
  const sceneNavKeys=['ArrowLeft','ArrowRight','Home','End'];
  $('scene-window-timeline').addEventListener('keydown',event=>{
    if(state.busy||$('scene-range').value!=='window'||!sceneNavKeys.includes(event.key))return;event.preventDefault();
    const window=sceneWindow(analysisModel('constellation')),max=Number($('scene-window-position').max),step=event.shiftKey?60:10;
    state.sceneWindowDraft=true;$('scene-window-start').value=String((event.key==='Home'?0:event.key==='End'?max:clamp(window.start+(event.key==='ArrowLeft'?-step:step),0,max))/60);renderSceneNavigator();
  });
  $('scene-window-timeline').addEventListener('keyup',event=>{if(state.sceneWindowDraft&&sceneNavKeys.includes(event.key)){saveWorking();return refreshScenes();}});
  try{$('scene-table-panel').open=localStorage.getItem('SBP.LoudnessCurve.sceneTable.v1')==='true';}catch(_){}
  $('scene-table-panel').addEventListener('toggle',()=>{try{localStorage.setItem('SBP.LoudnessCurve.sceneTable.v1',String($('scene-table-panel').open));}catch(_){} });
  for(const id of ['scene-source','scene-track','scene-naming'])$(id).addEventListener('change',()=>{if($('constellation-panel').open)refreshScenes();});
  for(const id of ['scene-metric','scene-display','scene-tolerance','scene-dyn-min','scene-dyn-max'])$(id).addEventListener('change',renderConstellation);
  $('offset').addEventListener('change',()=>{if($('constellation-panel').open)refreshScenes();});
  new ResizeObserver(renderConstellation).observe($('constellation-canvas'));
  for(const id of ['analysis-view','histogram-source','analysis-gate','psr-guide'])$(id).addEventListener('change',renderAnalysis);
  for(const panel of ['analysis','constellation','verify'])for(const suffix of ['source','linked'])$(panel+'-'+suffix).addEventListener('change',()=>{updateAnalysisSources();renderAnalysis();renderConstellation();renderVerification();if(panel==='constellation'&&$('constellation-panel').open)refreshScenes();});
  if(document.addEventListener)document.addEventListener('keydown',event=>{
    const target=event.target;
    if(/^(INPUT|TEXTAREA|SELECT)$/.test(target?.tagName)||target?.isContentEditable||target?.closest?.('[contenteditable=true]'))return;
    if(event.code==='Space'||event.key===' '){
      if(event.ctrlKey||event.metaKey||event.altKey||!state.report)return;
      event.preventDefault();if(event.repeat||state.busy||$('preview-play').disabled)return;return preview.toggle();
    }
    if(!(event.ctrlKey||event.metaKey))return;const key=event.key.toLowerCase();if(key==='z'||key==='y'){event.preventDefault();if(key==='y'||event.shiftKey)redoEdit();else undoEdit();}
  });
  $('limiting-panel').open=!(window.innerHeight && window.innerHeight<950);
  $('fit-integrated').addEventListener('click',()=>measureAudio(true));
  $('refine-audio').addEventListener('click',()=>measureAudio(false));
  $('clear-trim').addEventListener('click',()=>{setOutputTrim(0);calculate();commitEdit();});
  for(const [kind,id,prefix] of [['report','url','report'],['audio','audio-path','audio']])LoudnessFileInput.bind({field:$(id),browse:$(prefix+'-browse'),paste:$(prefix+'-paste'),kind,bridge,status:setStatus,blocked:()=>state.busy||activeSource!=='master',changed:()=>$(id).dispatchEvent(new Event('input'))});
  $('audio-path').addEventListener('input',()=>{preview.reset();renderAudioEstimate();calculate();});
  $('audio-path').addEventListener('keydown',event=>{if(event.key==='Enter')load();});
  $('undo').addEventListener('click',undoEdit);$('redo').addEventListener('click',redoEdit);
  for(const id of [...historyIds,'link-limits','razor-gain','razor-ramp'])$(id).addEventListener('change',commitEdit);
  for(const id of historyIds){const slider=$(id).parentElement.querySelector('input[type=range]');if(slider)slider.addEventListener('change',commitEdit);}
  for(const type of ['pointerup','pointercancel','contextmenu','dblclick'])canvas.addEventListener(type,commitEdit);
  $('reset').addEventListener('click',commitEdit);
  $('verify-panel').addEventListener('toggle',renderVerification);
  for(const id of ['verify-snapshot','verify-shift','metric','offset'])$(id).addEventListener('change',renderVerification);
  $('load').addEventListener('click',renderVerification);
  new ResizeObserver(renderVerification).observe($('verify-canvas'));
  new ResizeObserver(renderAnalysis).observe($('analysis-canvas'));
  new ResizeObserver(draw).observe(canvas);
  bridge.connect().then(info=>{
    refreshTracks(true);renderSourceTabs();
    if (!$('url').value) $('url').value = info.suggested_report || '';
    if(info.location_track)$('scene-track').value=info.location_track;
    $('cache-location').textContent=info.cache_path?`Cache: ${info.cache_path}${info.project_cache?' · project folder':' · temporary; save the project to use its folder'}`:'Cache location unavailable.';
    setStatus(`Connected · ${info.printmaster}`);
  })
    .catch(error=>setStatus(error.message,true));
  draw();
  syncProfile();
})();
