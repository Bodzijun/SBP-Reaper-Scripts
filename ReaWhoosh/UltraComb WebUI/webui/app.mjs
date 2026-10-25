import {syncDivisionIds,divisionValue,divisionPosition,divisionFromPosition} from './tempo-sync.mjs';
import {drawDisperser} from './disperser-view.mjs';
import {drawComb} from './core-view.mjs';
import {drawShift,ShiftMotion} from './shift-view.mjs';
import {randomizeEntries} from './bulk-model.mjs';
import {matrixRoutes,polarityNames,routeIsBipolar} from './matrix-model.mjs';
import {connectJSFX} from './jsfx-webui.mjs';
import {modules,coreGroups,modulationGroups,matrixTargets,matrixScales,matrixUnits,sharedLfoLabels,labels,units,formatControlLabel,toPosition as modelToPosition,fromPosition as modelFromPosition,decodeOrder,encodeOrder} from './model.mjs';
import {palettes} from './spectrogram.mjs';
import {AudioAnalysis,analysisModes,analysisStreamId} from './analysis-view.mjs';
import {ModulationFeedback,feedbackByParameter,paintModulationFeedback} from './modulation-feedback.mjs';
import {ModulationView,modulationShapeFor} from './modulation-view.mjs';
import {installTransportKeys} from './keyboard.mjs';
import {filterPlot,filterHeat} from './filter-model.mjs';
import {decodeDoubler,currentDoublerTelemetry,doublerModel,drawDoubler,DoublerMotion} from './doubler-view.mjs';
import {drawFreeze} from './freeze-view.mjs';
import {drawRing,drawMetal} from './ring-metal-view.mjs';
const $=id=>document.getElementById(id),el=(tag,cls,text)=>{const n=document.createElement(tag);if(cls)n.className=cls;if(text!==undefined)n.textContent=text;return n;};
const registry=await fetch('./parameters.json').then(r=>{if(!r.ok)throw Error('Parameter registry is missing');return r.json();});
const specs=new Map(registry.parameters.map(p=>[p.id,p])),values=new Map(registry.parameters.map(p=>[p.id,p.default])),widgets=new Map();
const lastAudioIndex=Math.max(...registry.parameters.map(p=>p.index));
Object.assign(labels,sharedLfoLabels);Object.assign(units,{114:'%',115:'°'});
Object.assign(labels,{42:'Decay',46:'Trigger Threshold',116:'Source',117:'Source'});
Object.assign(labels,{57:'Rate',58:'Depth',119:'Chorus',120:'Mix',121:'Width',122:'Delay'});Object.assign(units,{122:'ms'});
Object.assign(labels,{23:'Amount',124:'Feedback Sat',125:'SAT',126:'Drive',127:'Mix',128:'Tone',129:'Asymmetry',130:'Curve'});Object.assign(units,{126:'dB'});
let jsfx=null,active=false,preview=new URLSearchParams(location.search).get('preview')==='1',selected=6,coreTab='disperser',utilityTab='morph',gesture=null,tail=Promise.resolve(),routeKey='',disposed=false,streamEpoch=0;
let lastLfo=0,lastAdr=3;
function preference(key,fallback){try{return localStorage.getItem(key)||fallback;}catch{return fallback;}}
function remember(key,value){try{localStorage.setItem(key,value);}catch{}}
let shiftSensitivity=preference('ultracomb.shiftSensitivity','linear')==='fine'?'fine':'linear';
const toPosition=(p,value)=>syncDivisionIds.has(p.id)?divisionPosition(p.id,value,modFeedback.clock):modelToPosition(p,value,shiftSensitivity),fromPosition=(p,value)=>syncDivisionIds.has(p.id)?divisionFromPosition(p.id,value,modFeedback.clock):modelFromPosition(p,value,shiftSensitivity);
const analysisSlots={input:{token:0,stream:null},output:{token:0,stream:null}};
const streams=[],disposers=[];
disposers.push(installTransportKeys({finish,onError:report}));
let renderFrame=0,streamRecovery=null,lastPacket=0,retryAfter=0;
let recoveryTimer=0,transportValue;
let lastNativePacket=null,connectionError=null;
let doubleTelemetry=null,graphSampleRate=48000,schemaReady=preview;
const doubleMotion=new DoublerMotion();
const shiftMotion=new ShiftMotion();
const channelErrors=new Set(['DSP_UNAVAILABLE','STALE_SESSION','FX_STALE','FX_UNBOUND','CHANNEL_UNAVAILABLE']);
function updateConnection(){
 if(preview||disposed||!jsfx)return;
 const live=active&&lastNativePacket!==null&&performance.now()-lastNativePacket<2500;
 const text=!active?'HOST IDLE':live?'DSP LIVE':connectionError?'STREAM OFFLINE':lastNativePacket!==null?'STREAM IDLE':'HOST CONNECTED';
 if($('connection').textContent!==text)$('connection').textContent=text;
 $('connection').dataset.state=live?'live':connectionError?'offline':'idle';
 if(live&&connectionError){if($('status').textContent===connectionError.message)$('status').textContent='Native DSP stream restored';connectionError=null;}
}
function scheduleRender(){if(!renderFrame)renderFrame=requestAnimationFrame(()=>{renderFrame=0;if(!disposed)render();});}
const get=id=>Number(values.get(id)),spec=id=>specs.get(id);
const plots=Object.fromEntries(['input','output'].map(side=>[side,new AudioAnalysis($(`${side}-spectrogram`),$(`${side}-status`),preference(`ultracomb.analysis.${side}`,'spectrogram'))]));
const modFeedback=new ModulationFeedback();
const liveGet=id=>modFeedback.value(id,get(id));
const modView=new ModulationView($('mod-graph'),$('mod-live'));
const coreMotion=window.matchMedia('(prefers-reduced-motion: reduce)');
let modFrame=0,lastModPaint=0,coreWasModulated=false,moduleWasModulated=false;
function modulationShape(){return modulationShapeFor(modulationGroups[Number($('mod-source').value)||0],get);}
function modulationSettings(){
 const source=modulationGroups[Number($('mod-source').value)||0];

 if(source.adr){const a=source.adr,synced=get(a.sync)>.5;return {kind:'adr',mode:Math.round(get(a.mode)),threshold:get(a.threshold),external:get(a.source)>.5,sync:synced,clock:modFeedback.clock,attack:synced?divisionValue(a.divisionA,get(a.divisionA),modFeedback.clock):get(a.attack),decay:synced?divisionValue(a.divisionD,get(a.divisionD),modFeedback.clock):get(a.decay),level:get(a.level),release:synced?divisionValue(a.divisionR,get(a.divisionR),modFeedback.clock):get(a.release),attackCurve:get(a.attackCurve),decayCurve:get(a.decayCurve),releaseCurve:get(a.releaseCurve)};}
 return {};
}
function modulationTitle(){const s=modulationGroups[Number($('mod-source').value)||0];return s.adr?`${s.name} RAMP / MODEL + DSP`:s.key==='envelope'?'INPUT LEVEL / HISTORY':modulationShape()==='random'?'RANDOM OUTPUT / HISTORY':'WAVEFORM / MODEL + DSP';}

function animateModulation(time){
 if(disposed)return;
 if(!document.hidden&&time-lastModPaint>=30){lastModPaint=time;const source=modulationGroups[Number($('mod-source').value)||0];modView.draw(source.telemetry,modulationShape(),source.depth?get(source.depth)/100:1,modulationSettings());if(doubleTelemetry&&performance.now()-doubleTelemetry.received>=500)doubleTelemetry=null;if(modules[selected].key==='double')drawModuleGraph();paintModulationFeedback(widgets,specs,modFeedback,toPosition,fmt,time);
 const coreIds=[4,5,6,3,7,8,9,11,136,12,137,138,139];
 const coreModulated=coreIds.some(id=>modFeedback.active(id,time));if((coreTab==='comb'||coreTab==='shift')&&!coreMotion.matches||coreModulated||coreWasModulated)drawCoreGraph(time/1000);coreWasModulated=coreModulated;
 const m=modules[selected],moduleModulated=['filter','chorus'].includes(m.key)&&[...m.main,...m.extra].some(id=>modFeedback.active(id,time));if(moduleModulated||moduleWasModulated)drawModuleGraph();moduleWasModulated=moduleModulated;}
 modFrame=requestAnimationFrame(animateModulation);
}
function report(error){$('status').textContent=error?.message||String(error);if(channelErrors.has(error?.code)){connectionError={code:error.code,message:$('status').textContent};lastNativePacket=null;}if(jsfx)updateConnection();else $('connection').textContent=error?.code||'CHECK STATUS';}
function fmt(id,value){const p=spec(id);if(p.options)return p.options[Math.round(value-p.min)]||String(value);return value.toFixed(p.step>=1?0:p.step>=.1?1:p.step>=.01?2:3);}
function normalized(id,value){const p=spec(id);return Math.max(0,Math.min(1,(value-p.min)/(p.max-p.min)));}
function canEdit(){return preview||(schemaReady&&active&&jsfx?.params.snapshot);}
function start(id){
 if(!canEdit())return;
 if(gesture?.id===id)return;
 if(gesture)finish();
 const g={id,closed:false,started:false,last:null};gesture=g;
 g.ready=tail.then(async()=>{if(jsfx){await jsfx.params.beginEdit(id-1);g.started=true;}});
 g.ready.catch(report);
}
function write(id,value){
 if(!Number.isFinite(value)||!canEdit())return;
 if(gesture?.id!==id)start(id);
 const g=gesture;if(!g)return;g.last=value;
 if(id===69)doubleTelemetry=null;
 values.set(id,value);scheduleRender();
 if(preview)return;
 g.ready.then(()=>{if(!g.closed)return jsfx.params.set(id-1,normalized(id,value));}).catch(report);
}
function finish(){
 const g=gesture;if(!g)return tail;gesture=null;g.closed=true;
 tail=g.ready.then(async()=>{
  if(g.started){try{if(g.last!==null)await jsfx.params.set(g.id-1,normalized(g.id,g.last));}finally{await jsfx.params.endEdit();}}
  if(jsfx)applyState(jsfx.params.snapshot);else render();
 }).catch(report);return tail;
}
async function discrete(id,value){await finish();if(!canEdit())return;if(id===69){doubleTelemetry=null;values.set(id,value);scheduleRender();}if(preview){values.set(id,value);render();return;}try{await jsfx.params.set(id-1,normalized(id,value));}catch(e){if(id===69)applyState(jsfx.params.snapshot);report(e);}}
async function group(entries){await finish();if(!canEdit())return;
 if(preview){for(const [id,value]of entries)values.set(id,value);render();return;}
 try{await jsfx.params.beginEditGroup(entries.map(([id])=>id-1));try{await jsfx.params.setMany(entries.map(([id,value])=>({index:id-1,normalized:normalized(id,value)})));}finally{await jsfx.params.endEditGroup();}}catch(e){report(e);}
}
function control(id,compact=false){
 const p=spec(id),root=el('div','control'),label=el('label','label',formatControlLabel(p)),uid=`p${id}-${Math.random().toString(36).slice(2,8)}`;
 root.dataset.parameter=String(id);
 root.title=`${p.name} · parameter ${id}`;if(id===136)root.title='Spread Curve: negative = edge density; zero = original distribution; positive = centre density. Automatable and assignable in the matrix.';if(id===8)root.title='Q / Pinch: high Q narrows each all-pass phase transition and increases its group-delay peak; the graph shows delay, not gain.';if(id===54)root.title='Detune: the two independent Doubler voices are pitched below and above Voice Pitch by this amount.';if(id===137)root.title='Stereo Offset: Left = Shift minus Offset; Right = Shift plus Offset. A small offset creates stereo beating; large values create opposing metallic shifts.';if(id===138)root.title='Sideband: +1 = original signed Shift (MAIN); 0 = equal sidebands (RING); -1 = opposite Shift (OPP). Negative Shift reverses the physical upper/lower sidebands.';if(id===139)root.title='Shift Mix: blends the shifted signal with the signal immediately before Frequency Shift, inside Core and before Post Shift feedback capture.';root.append(label);let input,number;
 if(id===12){label.classList.add('shift-label');const modes=el('span','segments shift-sensitivity');modes.setAttribute('role','group');modes.setAttribute('aria-label','Shift slider sensitivity');for(const [key,name]of [['linear','LINEAR'],['fine','FINE']]){const b=el('button',shiftSensitivity===key?'active':'',name);b.type='button';b.dataset.sensitivity=key;b.title=key==='linear'?'Uniform Hz per slider movement':'Precise around zero; faster towards the ends';b.onclick=async e=>{e.preventDefault();await finish();shiftSensitivity=key;remember('ultracomb.shiftSensitivity',key);render();};modes.append(b);}label.append(modes);}
 if(p.options&&(p.options.length<=4||id===75||id===140||id===200)&&(id<89||id===116||id===117||id===130||id===140||id===141||id===191||[192,193,194,200,201,210,211].includes(id))){
  root.classList.add('mode-control');if(id===75)root.classList.add('filter-modes');input=el('div','segments mode-buttons');input.setAttribute('role','group');input.setAttribute('aria-label',p.name);
  p.options.forEach((name,i)=>{if(id===45&&i===1)return;const text=id===45?(i===0?'OFF':'ATTACK'):[140,200].includes(id)?name.toUpperCase():id===75?['LP','HP','BP','NOTCH','PEAK','VOWEL','COMB+','COMB−'][i]:name;const b=el('button',null,text);b.type='button';b.dataset.value=String(p.min+i*p.step);b.title=id===45?text:name;b.onclick=()=>discrete(id,Number(b.dataset.value));input.append(b);});root.append(input);
 }else if(p.options&&!syncDivisionIds.has(id)){
  input=el('select');input.id=uid;input.setAttribute('aria-label',p.name);label.htmlFor=uid;
  if(matrixRoutes.some(r=>r.target===id)){
   const groups=new Map();for(const target of matrixTargets){if(target.deprecated){const old=el('option',null,'Legacy saved destination');old.value=String(target.id);old.hidden=old.disabled=true;input.append(old);continue;}const option=el('option',null,target.label);option.value=String(target.id);if(!target.id){input.append(option);continue;}if(!groups.has(target.group)){const group=el('optgroup');group.label=target.group;groups.set(target.group,group);input.append(group);}groups.get(target.group).append(option);}
  }else (matrixRoutes.some(r=>r.source===id)?[0,1,4,3,5,6,2]:p.options.map((_,i)=>i)).forEach(i=>{const name=p.options[i],retired=matrixRoutes.some(r=>r.source===id)&&i===2||[67,188].includes(id)&&i===20;const o=el('option',null,name);o.value=String(p.min+i*p.step);o.hidden=o.disabled=retired;input.append(o);});
  input.addEventListener('change',()=>discrete(id,Number(input.value)));root.append(input);
 }else{
  const numberRow=el('div','number-unit');number=el(syncDivisionIds.has(id)?'output':'input','number');number.id=uid;if(!syncDivisionIds.has(id)){number.type='number';number.min=p.min;number.max=p.max;number.step=p.step;}number.setAttribute('aria-label',p.name);label.htmlFor=uid;
  if(!syncDivisionIds.has(id))number.addEventListener('change',()=>{const v=Number(number.value);if(Number.isFinite(v))discrete(id,fromPosition(p,toPosition(p,Math.max(p.min,Math.min(p.max,v)))));});
  numberRow.append(number);root.append(numberRow);
  input=el('input');input.type='range';input.min=0;input.max=1;input.step=syncDivisionIds.has(id)?1/21:id===12?.00001:.0001;input.setAttribute('aria-label',p.name);
  input.addEventListener('pointerdown',()=>start(id));
  input.addEventListener('keydown',e=>{if(['ArrowLeft','ArrowRight','ArrowUp','ArrowDown','Home','End','PageUp','PageDown'].includes(e.key))start(id);});
  input.addEventListener('input',()=>write(id,fromPosition(p,Number(input.value))));
  for(const event of ['change','keyup','blur'])input.addEventListener(event,finish);
  root.append(input);
 }
 root.addEventListener('contextmenu',e=>{e.preventDefault();discrete(id,p.default);});
 let overlay,band,marker;
 if((!p.options||syncDivisionIds.has(id))&&feedbackByParameter.has(id)){overlay=el('span','mod-indicator');overlay.hidden=true;overlay.setAttribute('aria-hidden','true');band=el('span','mod-range');marker=el('span','mod-now');overlay.append(band,marker);root.append(overlay);}
 const w={input,number,root,baseTitle:root.title,overlay,band,marker};if(!widgets.has(id))widgets.set(id,[]);widgets.get(id).push(w);return root;
}
function clearControls(container){for(const [id,list]of widgets)widgets.set(id,list.filter(w=>!container.contains(w.input)));container.replaceChildren();}
function fill(container,ids){clearControls(container);container.classList.toggle('vertical-faders',container.id==='module-controls'||container.id==='core-controls'&&(coreTab==='disperser'||coreTab==='shift'));ids.forEach(id=>container.append(control(id)));}
function toggle(id){const b=el('button','toggle');b.type='button';b.title=spec(id).name;b.setAttribute('aria-label',spec(id).name);b.dataset.toggle=String(id);b.addEventListener('click',()=>discrete(id,get(id)>.5?0:1));return b;}
function coreContent(){
 $('core').dataset.view=coreTab;
 $('core-graph').title=coreTab==='comb'?'Delay model: fixed 0–200 ms axis; cyan = Dry, orange = FX Feed. Animated waves illustrate the branch delays; they are not measured audio.':coreTab==='disperser'?'Base-parameter all-pass group delay before Phase Subtract. Continuous automatic vertical scale; the peak readout is in milliseconds. Orange ticks = section centres; Q controls peak width; Curve redistributes centres; cyan = Center.':'Base-parameter schematic, not a live spectrum. Cyan = reference input/dry; orange = left shifted output; pink = right when Stereo Offset is active. Solid = main sideband; dotted = opposite. Sideband collapses rotor motion to a line at RING and reverses it at OPP. Animation is scaled; negative/Nyquist frequencies fold.';
 $('core-tabs').replaceChildren();for(const key of Object.keys(coreGroups)){const b=el('button',key===coreTab?'active':'',key[0].toUpperCase()+key.slice(1));b.onclick=()=>{coreTab=key;coreContent();render();};$('core-tabs').append(b);}
 fill($('core-primary'),coreGroups[coreTab].primary||[]);
 fill($('core-controls'),coreGroups[coreTab].main);fill($('core-secondary'),coreGroups[coreTab].extra);
 $('core-graph-label').textContent=coreTab==='comb'?'PARALLEL DELAYS / SCHEMATIC':coreTab==='shift'?'SHIFT / SIDEBAND MODEL':'GROUP DELAY / SECTION CENTERS';
}
function modulationContent(){
 const group=modulationGroups[Number($('mod-source').value)||0];
 $('mod-controls').dataset.kind=group.adr?'adr':group.key;
 const syncId=group.sync||(group.key==='adr'?194:0),synced=syncId&&get(syncId)>.5;
 $('mod-controls').dataset.sync=String(!!synced);
 $('mod-graph').title=group.adr?'ADR: Attack to 1, Decay to Bend Level, Release to 0; no held sustain. The waveform is the parameter model; a live dot shows native ADR output. Attack mode adds the real selected input/threshold meter. Loop Ping-Pong follows the same complete shape forwards then backwards. MIDI mode retriggers once per incoming Note On; Manual mode uses TRIGGER. FREE segments extend to 30 seconds; SYNC segments follow project tempo and time signature.':'Modulation waveform model with a native live position/value when available.';
 const a=group.adr,aliases=a?{[a.attack]:a.divisionA,[a.decay]:a.divisionD,[a.release]:a.divisionR}:{};
 const ids=group.ids.map(id=>synced?(group.on&&id===(group.key==='lfo2'?132:15)?group.division:(aliases[id]||id)):id);
 fill($('mod-controls'),group.on?[syncId,...ids]:ids);
 if(group.on){
  const modes=el('div','segments lfo-modes');modes.setAttribute('role','group');modes.setAttribute('aria-label','LFO waveform');
  ['OFF','SIN','SAW','SQR','RND'].forEach((name,i)=>{const b=el('button',null,name);b.type='button';b.dataset.lfoShape=String(i-1);b.title=['Off','Sine','Saw','Square','Random'][i];b.onclick=()=>i===0?discrete(group.on,0):groupWriteLfo(i-1,group);modes.append(b);});$('mod-controls').prepend(modes);
 }
 $('mod-types').replaceChildren();
 const current=Number($('mod-source').value)||0;
 for(const [name,index]of [['LFO',lastLfo],['ENV',2],['ADR',lastAdr]]){const chosen=name==='LFO'?current<2:name==='ADR'?current>=3:current===index,b=el('button',chosen?'active':'',name);b.type='button';b.onclick=()=>selectModulation(index);$('mod-types').append(b);}
 if(current<2){const variants=el('div','segments lfo-selector');variants.setAttribute('aria-label','LFO selection');for(let i=0;i<2;i++){const b=el('button',current===i?'active':'',`LFO ${i+1}`);b.type='button';b.onclick=()=>selectModulation(i);variants.append(b);}$('mod-controls').append(variants);}
 $('mod-graph-label').textContent=modulationTitle();
 if(group.adr){
  const shapes=el('div','segments adr-shapes');shapes.id='adr-shapes';
  for(const [name,times]of [['RISE',[1000,1,0,1,0]],['FALL',[1,1,1,1000,0]],['TRI',[500,1,1,500,0]],['PULSE',[1,500,1,1,0]]]){const b=el('button',null,name);b.type='button';b.title=`Set ${name.toLowerCase()} ADR shape; preserves Mode and assignments`;b.onclick=()=>groupWriteAdr(times,name,group.adr);shapes.append(b);}
  const tools=el('div','adr-tools');tools.append(control(group.sync),shapes);$('mod-controls').children[0].after(tools);
  const b=el('button',null,'TRIGGER');b.id='adr-trigger';b.type='button';b.title='Retrigger the active ADR from its current value';b.onclick=()=>command(group.adr.command);$('mod-controls').append(b);
  const variants=el('div','segments adr-selector');for(const index of [3,4]){const button=el('button',current===index?'active':'',`ADR ${index-2}`);button.type='button';button.onclick=()=>selectModulation(index);variants.append(button);}$('mod-controls').append(variants);
 }
}
function selectModulation(index){finish();if(index<2)lastLfo=index;if(index>=3)lastAdr=index;$('mod-source').value=String(index);modulationContent();render();}
function groupWriteAdr(times,name,a){if(get(a.sync)>.5){const t={RISE:[18,0,0,0],FALL:[0,0,1,18],TRI:[13,0,1,13],PULSE:[0,13,1,0]}[name];return group([[a.divisionA,t[0]],[a.divisionD,t[1]],[a.level,t[2]],[a.divisionR,t[3]],[a.attackCurve,0],[a.decayCurve,0],[a.releaseCurve,0]]);}return group([a.attack,a.decay,a.level,a.release,a.attackCurve,a.decayCurve,a.releaseCurve].map((id,i)=>[id,times[i]??0]));}
function groupWriteLfo(shape,source){return group([[source.on,1],[source.shape,shape]]);}
function modulationAssignments(){
 for(const r of matrixRoutes){const source=Math.round(get(r.source)),target=Math.round(get(r.target)),polarity=Math.round(get(r.polarity)),row=$('mod-assignments').children[r.index];if(!row)continue;row.classList.toggle('route-disabled',source<.5||target===0||get(113)<.5);const button=row.querySelector('.matrix-polarity');button.textContent=polarityNames[polarity]||'AUTO';button.disabled=!canEdit();button.setAttribute('aria-label',`${spec(r.polarity).name}: ${button.textContent}`);button.dataset.mode=String(polarity);row.querySelector('.matrix-range').textContent=target?`${routeIsBipolar(source,polarity)?'±':'0→'}${matrixScales[target]} ${matrixUnits[target]}`:'—';}
}
function moduleContent(){
 const m=modules[selected];$('module-name').textContent=m.name;$('module-enable').replaceChildren();
 $('module').dataset.module=m.key;
 $('module-graph').title=m.key==='freeze'?'Control diagram: window width = Loop length on a fixed 0–500 ms scale; arrow = Forward/Reverse; fill brightness = Mix. This is not a captured waveform or live playback position.':m.key==='filter'?'Filter model: unresolved dense Comb teeth are shown as a shaded range. Audio and frequency spacing stay unchanged.':m.key==='double'?'Control diagram: X = Width, Y = Voice Delay, radius = Pitch, brightness = Mix/Gain. Blue: main signal; orange: added L/R voice. Internal pitch read-head latency is not plotted. Dashed: inverted polarity; bottom bar: voice passband.':'Parameter-based module model';
 if(m.key==='ring')$('module-graph').title='Gain model: Carrier changes cycles in the labelled time window. Depth and Mix control the blend between unity gain and bipolar sine multiplication. Off shows a muted preview; this is not the input waveform.';
 if(m.key==='metal')$('module-graph').title='Control model of six fundamental modal regions: Size moves centres; Decay narrows peaks; Tone changes damping/weights; Mix scales the wet preview. Comb overtones and the measured input spectrum are not drawn.';
 $('module').classList.toggle('double-editor',m.key==='double');
 const tools=el('div','route-tools');for(const [text,direction]of [['‹',-1],['›',1]]){const b=el('button',null,text);b.title=direction<0?'Move module left':'Move module right';b.onclick=()=>{const order=decodeOrder(get(73),get(83),get(118)),i=order.indexOf(selected),j=i+direction;if(j<0||j>=8)return;[order[i],order[j]]=[order[j],order[i]];const result=encodeOrder(order);group([[73,result.rank],[83,result.position],[118,result.chorusPosition]]);};tools.append(b);}
 if(m.on)tools.append(toggle(m.on));$('module-enable').append(tools);
 fill($('module-controls'),m.main);fill($('module-secondary'),m.extra);
 $('module-graph-label').textContent=m.key==='filter'?'FILTER RESPONSE / MODEL':m.key==='metal'?'MODAL MODEL':m.key==='ring'?'GAIN MODULATION':m.key==='pitch'?'PITCH SHIFT / CONTROL':m.key==='double'?'WIDTH / DELAY':m.key==='chorus'?'STEREO DELAY MOTION / MODEL':m.key==='sat'?'TRANSFER CURVE / MODEL':'LOOP LENGTH / MODEL';
}
function utilityContent(){
 $('utility-controls').dataset.view=utilityTab;
 clearControls($('utility-tabs'));for(const key of ['random','morph']){const b=el('button',key===utilityTab?'active':'',key[0].toUpperCase()+key.slice(1));b.onclick=()=>{utilityTab=key;utilityContent();render();};$('utility-tabs').append(b);}
 const scope=control(utilityTab==='random'?67:188);scope.classList.add('utility-scope');$('utility-tabs').append(scope);
 fill($('utility-controls'),utilityTab==='random'?[66]:[65]);
 const actions=el('div','morph-actions');
 if(utilityTab==='morph'){for(const [name,action]of [['A',()=>discrete(65,0)],['STORE A',()=>command('storeA')],['STORE B',()=>command('storeB')],['B',()=>discrete(65,1)]]){const b=el('button',null,name);b.onclick=action;actions.append(b);}}
 if(utilityTab==='random'){const b=el('button',null,'RANDOMIZE');b.onclick=randomize;actions.append(b);}
 $('utility-controls').append(actions);
}
const captures=[
 ['PRE FX',[0,0,0,0],null],['POST DISPERSER',[1,0,0,0],null],['POST SHIFT',[2,0,0,0],null],['POST FREEZE',[2,0,1,0],0],['POST PITCH',[2,1,0,0],1],['POST DOUBLE',[2,0,2,0],2],['POST RING',[2,2,0,0],3],['POST METAL',[2,3,0,0],4],['POST SAT',[2,4,0,0],5],['POST FILTER',[2,0,0,1],6],['POST CHORUS',[2,0,0,0,1],7]
];
function captureIndex(){if(get(123)>.5)return 10;if(get(84)>.5)return 9;if(get(59)>.5)return get(59)<1.5?3:5;if(get(47)>.5)return [4,6,7,8][Math.round(get(47))-1];return Math.round(get(22));}
captures.forEach(([label],i)=>{const option=el('option',null,label);option.value=i;$('capture').append(option);});
function renderRoute(){
 const order=decodeOrder(Math.round(get(73)),Math.round(get(83)),Math.round(get(118))),capture=captureIndex();
 const key=[...order,selected,capture,Number(get(6)>.0001),Number(!!canEdit()),...modules.map(m=>get(m.on))].join(':');if(key===routeKey)return;routeKey=key;
 $('route').replaceChildren();const core=el('button','fixed','CORE');core.title='Fixed parallel engine, always first';if(captures[capture]?.[2]===null){core.classList.add('capture');core.title+=` · Feedback: ${captures[capture][0]} → CORE INPUT`;}$('route').append(core);
 for(const id of order){const m=modules[id],on=get(m.on)>.5,b=el('div',`route-item ${selected===id?'active':''} ${!on?'off':''} ${captures[capture]?.[2]===id?'capture':''}`);
  if(captures[capture]?.[2]===id)b.title=`Feedback capture: ${captures[capture][0]} → CORE INPUT`;
  const choose=el('button','route-select',m.key.toUpperCase()),power=el('button','route-power');power.type='button';power.title=`${on?'Disable':'Enable'} ${m.name}`;power.setAttribute('aria-label',`Enable ${m.name}`);power.setAttribute('aria-pressed',String(on));power.disabled=!canEdit();
  power.append(el('span','dot'));power.onclick=e=>{e.stopPropagation();discrete(m.on,on?0:1);};
  power.addEventListener('pointerdown',e=>e.stopPropagation());power.draggable=false;
  b.append(power,choose);b.draggable=true;
  b.onclick=()=>{finish();selected=id;moduleContent();render();};
  b.addEventListener('dragstart',e=>e.dataTransfer.setData('text/plain',String(id)));
  b.addEventListener('dragover',e=>e.preventDefault());b.addEventListener('drop',e=>{e.preventDefault();const raw=e.dataTransfer.getData('text/plain');if(!/^\d$/.test(raw))return;const from=order.indexOf(Number(raw)),to=order.indexOf(id);if(from<0)return;const next=[...order];const [moved]=next.splice(from,1);next.splice(to,0,moved);const result=encodeOrder(next);group([[73,result.rank],[83,result.position],[118,result.chorusPosition]]);});
  $('route').append(b);
 }
 drawFeedbackRoute();
}
function drawFeedbackRoute(){
 const route=$('route'),capture=route.querySelector('.capture'),core=route.querySelector('.fixed');if(!capture||!core)return;
 const rect=route.getBoundingClientRect(),from=capture.getBoundingClientRect(),to=core.getBoundingClientRect(),local=capture===core;
 const start=from.left-rect.left+from.width*(local?.72:.5),end=to.left-rect.left+to.width*(local?.28:.5),ns='http://www.w3.org/2000/svg';
 route.querySelector('.feedback-route')?.remove();const svg=document.createElementNS(ns,'svg'),title=document.createElementNS(ns,'title'),line=document.createElementNS(ns,'path'),arrow=document.createElementNS(ns,'path');svg.classList.add('feedback-route');svg.setAttribute('preserveAspectRatio','none');svg.setAttribute('viewBox',`0 0 ${rect.width} 12`);svg.setAttribute('aria-label',`Feedback: ${captures[captureIndex()][0]} → CORE INPUT`);svg.setAttribute('role','img');svg.dataset.active=String(get(6)>.0001);title.textContent=svg.getAttribute('aria-label');line.setAttribute('d',`M ${start} 3 V 8 H ${end} V 2`);line.classList.add('feedback-route-line');arrow.setAttribute('d',`M ${end-3} 4 L ${end} 0 L ${end+3} 4 Z`);arrow.classList.add('feedback-route-arrow');svg.append(title,line,arrow);route.append(svg);
 const description=`Feedback: ${captures[captureIndex()][0]} → CORE INPUT`;for(const w of widgets.get(6)||[]){w.baseTitle=description;w.root.title=description;}$('capture').title=description;
}
function applyState(state){if(!state||disposed)return;const tail=state.parameters?.find(p=>p.index===lastAudioIndex);const wasReady=schemaReady;schemaReady=Boolean(tail)&&!/^:?(bypass|wet|delta)$/i.test(tail.ident||'')&&!/^-?(bypass|wet|delta)$/i.test(tail.name||'');if(!schemaReady)$('status').textContent='Reinsert UltraComb to load the updated DSP parameter list.';else if(!wasReady)$('status').textContent='Native parameters ready · 3.13.2';for(const p of state.parameters||[]){const id=p.index+1;if(p.index===87&&Number.isFinite(p.value)){if(transportValue!==undefined&&transportValue!==p.value)requestStreamRecovery();transportValue=p.value;}if(specs.has(id)&&Number.isFinite(p.value)&&gesture?.id!==id&&values.get(id)!==p.value)values.set(id,p.value);}scheduleRender();}
function render(){
 const source=modulationGroups[Number($('mod-source').value)||0],syncId=source.sync||(source.key==='adr'?194:0);if($('mod-controls').dataset.sync!==String(!!(syncId&&get(syncId)>.5)))modulationContent();
 document.querySelectorAll('[data-sensitivity]').forEach(b=>{const on=b.dataset.sensitivity===shiftSensitivity;b.classList.toggle('active',on);b.setAttribute('aria-pressed',String(on));});
 for(const [id,list]of widgets){const p=spec(id);for(const w of list){w.input.disabled=!canEdit();if(w.number)w.number.disabled=!canEdit();if(gesture?.id!==id)w.input.value=p.options&&!syncDivisionIds.has(id)?String(get(id)):String(toPosition(p,get(id)));if(!p.options||syncDivisionIds.has(id))w.input.style.setProperty('--fill',`${Number(w.input.value)*100}%`);if(w.input.classList.contains('mode-buttons'))for(const b of w.input.children){b.disabled=!canEdit();const on=Number(b.dataset.value)===(id===45?(get(id)>1.5?2:0):get(id));b.classList.toggle('active',on);b.setAttribute('aria-pressed',String(on));}if(w.number&&document.activeElement!==w.number){if(syncDivisionIds.has(id))w.number.textContent=fmt(id,get(id));else w.number.value=fmt(id,get(id));}}}
 document.querySelectorAll('[data-lfo-shape]').forEach(b=>{const source=modulationGroups[Number($('mod-source').value)||0],on=Number(b.dataset.lfoShape)===(get(source.on)>.5?Math.round(get(source.shape)):-1);b.disabled=!canEdit();b.classList.toggle('active',on);b.setAttribute('aria-pressed',String(on));});
 document.querySelectorAll('[data-toggle]').forEach(b=>{const on=get(Number(b.dataset.toggle))>.5;b.classList.toggle('on',on);b.textContent=on?'ON':'OFF';b.disabled=!canEdit();});
 $('feedback').disabled=$('capture').disabled=!canEdit();if(gesture?.id!==6)$('feedback').value=String(normalized(6,get(6)));$('feedback-value').textContent=get(6).toFixed(2);$('capture').value=String(captureIndex());
 $('feedback').style.setProperty('--fill',`${Number($('feedback').value)*100}%`);
 if($('motion-trigger')){$('motion-trigger').hidden=Math.round(get(45))!==2;$('motion-trigger').disabled=!canEdit();}
 if($('adr-trigger'))$('adr-trigger').disabled=!canEdit()||get(source.adr.mode)<.5;
 for(const b of $('adr-shapes')?.children||[])b.disabled=!canEdit();
 if($('mod-controls').dataset.kind==='adr'){
  for(const id of [source.adr.source,source.adr.threshold])$('mod-controls').querySelector(`[data-parameter="${id}"]`).hidden=Math.round(get(source.adr.mode))!==1;
  $('mod-controls').querySelector(`[data-parameter="${source.adr.direction}"]`).hidden=Math.round(get(source.adr.mode))!==3;
 }
 $('mod-graph-label').textContent=modulationTitle();
 renderRoute();modulationAssignments();drawGraphs();
}
async function command(id){
 await finish();if(!canEdit())return;if(preview){$('status').textContent='Local preview: native command not executed';return;}
 try{const operation=await jsfx.commands.invoke(id,[]);$('status').textContent=`${id}: ${operation.state||operation.status||'sent to DSP'}`;}catch(e){report(e);}
}
async function randomize(){await group(randomizeEntries(registry.random,get,get(66),get(67)));}

function chart(canvas,paint,stamp='PARAMETER MODEL'){
 const dpr=Math.min(2,window.devicePixelRatio||1),w=Math.max(100,canvas.clientWidth),h=Math.max(80,canvas.clientHeight);canvas.width=w*dpr;canvas.height=h*dpr;const c=canvas.getContext('2d');c.scale(dpr,dpr);c.fillStyle='#182326';c.fillRect(0,0,w,h);c.strokeStyle='#304245';c.lineWidth=.5;
 for(let i=1;i<8;i++){c.beginPath();c.moveTo(w*i/8,0);c.lineTo(w*i/8,h);c.stroke();}for(let i=1;i<4;i++){c.beginPath();c.moveTo(0,h*i/4);c.lineTo(w,h*i/4);c.stroke();}
 paint(c,w,h);c.fillStyle='#9caead';c.font='8px Arial';c.fillText(stamp,8,h-7);
}
function line(c,points,color){c.strokeStyle=color;c.lineWidth=1.8;c.beginPath();points.forEach(([x,y],i)=>i?c.lineTo(x,y):c.moveTo(x,y));c.stroke();}
function drawCoreGraph(time=performance.now()/1000){
 chart($('core-graph'),(c,w,h)=>{
  if(coreTab==='disperser'){drawDisperser(c,w,h,{center:liveGet(7),spread:liveGet(9),q:liveGet(8),stages:liveGet(10),curve:liveGet(136),sampleRate:graphSampleRate});$('core-summary').textContent=`${Math.round(liveGet(10))} sections · Q ${liveGet(8).toFixed(2)}`;}

  else if(coreTab==='comb'){drawComb(c,w,h,{dry:liveGet(4),feed:liveGet(5),feedback:liveGet(6),mix:liveGet(3),time:coreMotion.matches?0:time});$('core-summary').textContent=`Dry ${liveGet(4).toFixed(1)} / Feed ${liveGet(5).toFixed(1)} ms`;}

  else{const model=drawShift(c,w,h,{shift:liveGet(12),offset:liveGet(137),sideband:liveGet(138),mix:liveGet(139),sampleRate:graphSampleRate,time,motion:!coreMotion.matches},shiftMotion);const hz=v=>`${v>0?'+':''}${v.toFixed(1)}`;$('core-summary').textContent=model.stereo?`L ${hz(model.channels[0].hz)} / R ${hz(model.channels[1].hz)} Hz`:`${hz(model.hz)} Hz · ${model.mode}`;}
 },'');
}
function drawGraphs(){drawCoreGraph();drawModuleGraph();}
function drawModuleGraph(){
 const doubleLive=currentDoublerTelemetry(doubleTelemetry,get(69),performance.now(),gesture?.id===69);
 chart($('module-graph'),(c,w,h)=>{
  const key=modules[selected].key;let summary='';
  if(key==='filter'){const mode=Math.round(liveGet(75)),{points,zero,dense}=filterPlot(w,h,{mode,cutoff:liveGet(76),resonance:liveGet(77),mix:liveGet(79),sampleRate:graphSampleRate}),heat=filterHeat(liveGet(78)),fill=c.createLinearGradient(0,0,0,h);fill.addColorStop(0,heat+'55');fill.addColorStop(1,heat+'05');c.fillStyle=fill;c.beginPath();c.moveTo(0,h-18);for(const [x,y]of points)c.lineTo(x,y);c.lineTo(points.at(-1)[0],h-18);c.closePath();c.fill();if(dense){c.fillStyle=heat+'22';c.beginPath();dense.upper.forEach(([x,y],i)=>i?c.lineTo(x,y):c.moveTo(x,y));for(const [x,y]of [...dense.lower].reverse())c.lineTo(x,y);c.closePath();c.fill();line(c,dense.upper,heat+'88');line(c,dense.lower,heat+'66');if(w-dense.from>65){c.fillStyle='#a3bdb3';c.font='8px Arial';c.fillText('DENSE TEETH',dense.from+5,h-25);}}$('module-graph').dataset.combDense=String(!!dense);line(c,[[0,zero],[w,zero]],'#78978e');line(c,points,heat);$('module-graph').dataset.heat=heat;c.fillStyle='#a3bdb3';c.font='8px Arial';c.fillText('0 dB',5,zero-4);summary=`${spec(75).options[mode]} · ${Math.round(liveGet(76))} Hz · ${liveGet(78).toFixed(1)} dB`;}
  else if(key==='metal'){drawMetal(c,w,h,{size:get(34),decay:get(35),tone:get(36),mix:get(37),enabled:get(33)>.5});summary=`Size ${get(34).toFixed(2)} · ${get(35).toFixed(2)} s`;}
  else if(key==='sat'){const points=[],drive=10**((get(23)*30+get(126))/20),bias=get(129)*.35,mode=Math.round(get(130));const transfer=v=>mode===1?1.5*Math.max(-1,Math.min(1,v))-.5*Math.max(-1,Math.min(1,v))**3:mode===2?v/(1+Math.abs(v)):mode===3?Math.max(-1,Math.min(1,v)):Math.tanh(v);for(let x=0;x<w;x++){const input=2*x/w-1,shaped=transfer(input*drive+bias)-transfer(bias),y=input+(shaped-input)*get(23)*get(127);points.push([x,Math.max(5,Math.min(h-15,h/2-y*h*.3))]);}line(c,points,'#eaae70');summary=`${spec(130).options[mode]} · ${get(126).toFixed(1)} dB`;}
  else if(key==='pitch'){const points=[];for(let x=0;x<w;x++){const v=get(39)+(get(113)<.5&&Math.round(get(45))===1?Math.sin(x/w*Math.PI*4)*get(40):0);points.push([x,h/2-v/48*(h-30)]);}line(c,points,'#e3a18a');summary=`Base ${get(39).toFixed(1)} st · CONTROL MODEL`;}
  else if(key==='double'){const model=doublerModel({pitch:get(53),detune:get(54),width:get(56),delay:get(69),mix:get(55),enabled:get(52)>.5,gain:get(68),invert:get(72)>.5,lowCut:get(70),highCut:get(71)},doubleLive);drawDoubler(c,w,h,doubleMotion.sample(model,performance.now(),get(69)));summary=`±${Math.abs(get(54)).toFixed(1)} ct · Delay ${get(69).toFixed(1)} ms`;}
  else if(key==='chorus'){const rate=liveGet(57),base=liveGet(122),center=h*.65-base/50*h*.3;line(c,[[0,center],[w,center]],'#6c8581');c.globalAlpha=.15+.85*liveGet(120);for(let channel=0;channel<2;channel++){const points=[];for(let x=0;x<w;x++)points.push([x,center+Math.sin(x/w*2*Math.PI*rate*2+channel*liveGet(121)*Math.PI)*liveGet(58)/30*h*.22]);line(c,points,channel?'#f3b774':'#65d59d');}c.globalAlpha=1;c.fillStyle='#9caead';c.font='9px Arial';c.fillText('2 s / DELAY OFFSET / SCHEMATIC',8,12);summary=`${rate.toFixed(2)} Hz · ${base.toFixed(1)} ms`;}
  else if(key==='ring'){drawRing(c,w,h,{frequency:get(25),depth:get(26),mix:get(27),enabled:get(24)>.5});summary=`Carrier ${get(25).toFixed(1)} Hz`;}
  else{drawFreeze(c,w,h,{length:liveGet(49),mix:liveGet(50),enabled:liveGet(48)>.5,reverse:liveGet(51)>.5});summary=`Loop ${liveGet(49).toFixed(0)} ms · ${liveGet(51)>.5?'REV':'FWD'}`;}
  $('module-summary').textContent=summary;
 },['double','freeze','ring','metal'].includes(modules[selected].key)?'CONTROL MODEL':'PARAMETER MODEL');
}
async function closeStreams(){
 streamEpoch++;doubleTelemetry=null;modFeedback.clear();for(const slot of Object.values(analysisSlots)){slot.token++;slot.stream=null;}
 const old=streams.splice(0);await Promise.allSettled(old.map(s=>s.close()));for(const id of ['input','output'])$(`${id}-status`).textContent='STREAM PAUSED';
}
async function openAnalysisStream(side,epoch=streamEpoch){
 if(!jsfx||!active||disposed)return;const slot=analysisSlots[side],token=++slot.token,previous=slot.stream;slot.stream=null;
 if(previous){const index=streams.indexOf(previous);if(index>=0)streams.splice(index,1);await previous.close();}
 const id=analysisStreamId(side,plots[side].mode),kind=plots[side].mode==='stereo'?'pcm':'spectrum';
 try{
  const s=await jsfx.streams.open(id,{updateRate:30});if(epoch!==streamEpoch||token!==slot.token||!active||disposed){await s.close();return;}
  slot.stream=s;streams.push(s);plots[side].clear();
  const current=()=>epoch===streamEpoch&&token===slot.token&&!disposed;
  s.on('data',packet=>{if(!current())return;lastPacket=performance.now();plots[side].accept(packet,s.info||{},kind);const rate=Number(s.info?.sampleRate);if(Number.isFinite(rate)&&rate>=8000&&rate!==graphSampleRate){graphSampleRate=rate;scheduleRender();}if(packet.data?.length>=32&&rate>=8000){lastNativePacket=performance.now();updateConnection();}});
  s.on('close',()=>{if(current()){lastPacket=0;lastNativePacket=null;updateConnection();requestStreamRecovery();}});
  s.on('error',error=>{if(!current())return;lastPacket=0;plots[side].status.textContent='STREAM ERROR';report(error);requestStreamRecovery();});
 }catch(e){if(epoch===streamEpoch&&token===slot.token){$(`${side}-status`).textContent='NO DSP STREAM';report(e);}}
}
async function openStreams(){
 if(!jsfx||!active||disposed)return;const epoch=++streamEpoch;lastPacket=performance.now();
 try{const s=await jsfx.streams.open('modulation',{updateRate:30});if(epoch!==streamEpoch||!active){await s.close();return;}streams.push(s);s.on('data',packet=>{if(epoch===streamEpoch){modView.accept(packet);const oldClock=modFeedback.clock;modFeedback.accept(packet,s.info||{});const clock=modFeedback.clock;if(['tempo','num','den'].some(k=>clock[k]!==oldClock[k]))scheduleRender();const state=decodeDoubler(packet);if(state)doubleTelemetry={state,received:performance.now()};}});s.on('close',()=>{if(epoch===streamEpoch)requestStreamRecovery();});s.on('error',()=>{if(epoch===streamEpoch)requestStreamRecovery();});}catch(e){report(e);}
 for(const side of ['input','output'])await openAnalysisStream(side,epoch);
}
function syncAnalysisUi(){
 for(const side of ['input','output']){const section=$(`${side}-spectrogram`).closest('.analysis'),mode=plots[side].mode;section.querySelectorAll('[data-analysis]').forEach(b=>{const on=b.dataset.analysis===mode;b.classList.toggle('active',on);b.setAttribute('aria-pressed',String(on));});const axis=section.querySelector('.axis');axis.firstElementChild.textContent=mode==='stereo'?'L/R · SIDE ↔ MID ↑':mode==='spectrum'?'20 Hz → 20 kHz':'20 Hz → 20 kHz ↑';axis.lastElementChild.textContent=mode==='stereo'?'CORRELATION −1…+1':mode==='spectrum'?'LEVEL, dB':'TIME →';$(`${side}-spectrogram`).setAttribute('aria-label',`Live ${side} ${mode}`);}
 const gram=Object.values(plots).some(p=>p.mode==='spectrogram');$('history').disabled=$('palette').disabled=!gram;document.querySelector('.analysis-settings .scale').hidden=!gram;
}
function chooseAnalysis(side,mode){
 if(!analysisModes.includes(mode)||plots[side].mode===mode)return;const old=analysisStreamId(side,plots[side].mode);plots[side].setMode(mode);remember(`ultracomb.analysis.${side}`,mode);syncAnalysisUi();if(old!==analysisStreamId(side,mode))openAnalysisStream(side).catch(report);
}
function recoverStreams(){
 if(streamRecovery||!jsfx||!active||disposed)return streamRecovery;
 streamRecovery=(async()=>{await closeStreams();if(active&&!disposed){await jsfx.getCapabilities?.();if(jsfx.params.getState)applyState(await jsfx.params.getState());if(!disposed)await openStreams();}})()
  .catch(report).finally(()=>{retryAfter=performance.now()+5000;streamRecovery=null;});
 return streamRecovery;
}
// Coalesce reset notifications, but do not wait for the stalled-stream timeout.
function requestStreamRecovery(){
 if(recoveryTimer||streamRecovery||!jsfx||!active||disposed)return;
 recoveryTimer=setTimeout(()=>{recoveryTimer=0;recoverStreams();},100);
}
// Older runtimes may not send a channel-change notification after preset reset.
const streamWatchdog=setInterval(()=>{
 updateConnection();
 if(preview||disposed||!active||document.hidden||streamRecovery||performance.now()<retryAfter||performance.now()-lastPacket<2500)return;
 recoverStreams();
},1000);
modulationGroups.forEach((group,i)=>{
 const option=el('option',null,group.name);option.value=String(i);$('mod-source').append(option);
});
for(const r of matrixRoutes){
 const {index:i,source,target,amount,polarity}=r,row=el('div','matrix-row');
 labels[source]='Source';labels[target]='Target';labels[amount]='Amount';
 const sourceControl=control(source),targetControl=control(target),amountControl=control(amount),mode=el('button','matrix-polarity','AUTO');
 sourceControl.classList.add('matrix-source');targetControl.classList.add('matrix-target');amountControl.classList.add('matrix-amount');
 mode.type='button';mode.dataset.polarityId=String(polarity);mode.title='AUTO: native source range. UNI: 0..1. BI: -1..+1. Off/depth-zero sources remain neutral. Active unipolar sources at zero become -1 in BI. Right click resets AUTO.';mode.onclick=()=>discrete(polarity,(Math.round(get(polarity))+1)%3);mode.oncontextmenu=e=>{e.preventDefault();discrete(polarity,0);};
 row.append(el('span','matrix-index',String(i+1)),sourceControl,targetControl,mode,amountControl,el('output','matrix-range'));
 const clear=el('button','matrix-clear','×');clear.title=`Clear route ${i+1}`;clear.onclick=()=>group([[source,0],[target,0],[amount,0],[polarity,0]]);row.append(clear);$('mod-assignments').append(row);
}
labels[113]='Routing';$('matrix-mode').append(control(113));
$('mod-source').onchange=()=>selectModulation(Number($('mod-source').value)||0);
modulationContent();
$('open-matrix').onclick=()=>$('matrix-dialog').showModal();$('close-matrix').onclick=()=>$('matrix-dialog').close();
modFrame=requestAnimationFrame(animateModulation);
for(const id of [2,85,86,87])$('globals').append(id===85?toggle(id):control(id));
fill($('core-mix'),[1,3,13,124]);coreContent();moduleContent();utilityContent();
const feedbackRoot=$('feedback').parentElement;feedbackRoot.classList.add('mod-control-anchor');const feedbackOverlay=el('span','mod-indicator'),feedbackBand=el('span','mod-range'),feedbackMarker=el('span','mod-now');feedbackOverlay.hidden=true;feedbackOverlay.setAttribute('aria-hidden','true');feedbackOverlay.append(feedbackBand,feedbackMarker);feedbackRoot.append(feedbackOverlay);widgets.set(6,[...(widgets.get(6)||[]),{input:$('feedback'),root:feedbackRoot,baseTitle:'Core Feedback',overlay:feedbackOverlay,band:feedbackBand,marker:feedbackMarker}]);
$('feedback').addEventListener('pointerdown',()=>start(6));$('feedback').addEventListener('input',()=>write(6,fromPosition(spec(6),Number($('feedback').value))));$('feedback').addEventListener('change',finish);$('feedback').addEventListener('contextmenu',e=>{e.preventDefault();discrete(6,.3);});
 $('capture').onchange=()=>group([22,47,59,84,123].map((id,i)=>[id,captures[Number($('capture').value)][1][i]??0]));
for(const event of ['pointerup','pointercancel','blur'])window.addEventListener(event,finish);
$('history').onchange=()=>{for(const plot of Object.values(plots)){plot.seconds=Number($('history').value);plot.clear();}};
$('freeze-display').onclick=()=>{const paused=!plots.input.paused;for(const plot of Object.values(plots))plot.paused=paused;$('freeze-display').textContent=paused?'▶':'Ⅱ';$('freeze-display').title=paused?'Resume analyzer display':'Pause analyzer display only';};
$('clear-display').onclick=()=>Object.values(plots).forEach(plot=>plot.clear());
function setPalette(name){const selected=palettes[name]?name:'aurora';$('palette').value=selected;for(const plot of Object.values(plots)){plot.palette=selected;plot.clear();}$('palette-scale').style.background=`linear-gradient(90deg,${palettes[selected].map(([p,r,g,b])=>`rgb(${r},${g},${b}) ${p*100}%`).join(',')})`;}
let savedPalette='aurora';try{savedPalette=localStorage.getItem('ultracomb.spectrogramPalette')||savedPalette;}catch{}
for(const side of ['input','output']){const header=$(`${side}-spectrogram`).closest('.analysis').querySelector('.analysis-title'),tabs=el('div','segments analysis-tabs');tabs.setAttribute('role','group');tabs.setAttribute('aria-label',`${side} analyzer type`);for(const mode of analysisModes){const b=el('button',null,{spectrogram:'Spectrogram',spectrum:'Spectrum',stereo:'Stereo'}[mode]);b.type='button';b.dataset.analysis=mode;b.onclick=()=>chooseAnalysis(side,mode);tabs.append(b);}header.insertBefore(tabs,$(`${side}-status`));}syncAnalysisUi();
setPalette(savedPalette);$('palette').onchange=()=>{setPalette($('palette').value);try{localStorage.setItem('ultracomb.spectrogramPalette',$('palette').value);}catch{}};
$('all-parameters').onclick=()=>{fill($('parameter-list'),registry.parameters.filter(p=>!p.deprecated).map(p=>p.id));$('parameter-dialog').showModal();render();};$('close-dialog').onclick=()=>$('parameter-dialog').close();
$('search').oninput=()=>{const q=$('search').value.toLowerCase();for(const node of $('parameter-list').children)node.hidden=!node.title.toLowerCase().includes(q);};
window.addEventListener('resize',()=>{drawFeedbackRoute();drawGraphs();Object.values(plots).forEach(plot=>plot.clear());});
render();
if(preview){active=true;$('connection').textContent='LOCAL PREVIEW';$('status').textContent='Local layout preview · no REAPER writes · spectrograms have no audio source';render();}
else try{
 if(!globalThis.reaper?.lifecycle)throw Error('Open this effect in REAPER with ReaWebAPI');
 await reaper.lifecycle.ready;jsfx=await connectJSFX(reaper,report);active=jsfx.active;applyState(jsfx.params.snapshot);updateConnection();
 disposers.push(await jsfx.params.onChange(applyState));
 disposers.push(await jsfx.onCapabilitiesChange(()=>requestStreamRecovery()));
 disposers.push(await jsfx.onVisibilityChange(async visible=>{active=visible;updateConnection();if(active){applyState(jsfx.params.snapshot);await recoverStreams();render();}else{await finish();await closeStreams();render();}}));
 await openStreams();
}catch(e){report(e);}
window.addEventListener('pagehide',()=>{disposed=true;clearInterval(streamWatchdog);clearTimeout(recoveryTimer);cancelAnimationFrame(renderFrame);cancelAnimationFrame(modFrame);finish().then(closeStreams).then(async()=>{for(const dispose of disposers)await dispose();await jsfx?.dispose();}).catch(report);},{once:true});
