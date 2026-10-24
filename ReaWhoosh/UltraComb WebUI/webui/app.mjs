import {randomizeEntries} from './bulk-model.mjs';
import {connectJSFX} from './jsfx-webui.mjs';
import {modules,coreGroups,modulationGroups,matrixTargets,matrixScales,matrixUnits,sharedLfoLabels,labels,units,toPosition,fromPosition,decodeOrder,encodeOrder} from './model.mjs';
import {Spectrogram,palettes} from './spectrogram.mjs';
import {ModulationView,modulationShapeFor} from './modulation-view.mjs';
import {installTransportKeys} from './keyboard.mjs';
import {filterPlot} from './filter-model.mjs';
import {decodeDoubler,currentDoublerTelemetry,doublerModel,drawDoubler,DoublerMotion} from './doubler-view.mjs';
import {drawFreeze} from './freeze-view.mjs';
import {drawRing,drawMetal} from './ring-metal-view.mjs';
const $=id=>document.getElementById(id),el=(tag,cls,text)=>{const n=document.createElement(tag);if(cls)n.className=cls;if(text!==undefined)n.textContent=text;return n;};
const registry=await fetch('./parameters.json').then(r=>{if(!r.ok)throw Error('Parameter registry is missing');return r.json();});
const specs=new Map(registry.parameters.map(p=>[p.id,p])),values=new Map(registry.parameters.map(p=>[p.id,p.default])),widgets=new Map();
Object.assign(labels,sharedLfoLabels);Object.assign(units,{114:'%',115:'deg'});
Object.assign(labels,{42:'Decay',46:'Trigger Threshold',116:'Source',117:'Source'});
Object.assign(labels,{57:'Rate',58:'Depth',119:'Chorus',120:'Mix',121:'Width',122:'Delay'});Object.assign(units,{122:'ms'});
Object.assign(labels,{23:'Amount',124:'Feedback Sat',125:'SAT',126:'Drive',127:'Mix',128:'Tone',129:'Asymmetry',130:'Curve'});Object.assign(units,{126:'dB'});
let jsfx=null,active=false,preview=new URLSearchParams(location.search).get('preview')==='1',selected=6,coreTab='disperser',utilityTab='morph',gesture=null,tail=Promise.resolve(),routeKey='',disposed=false,streamEpoch=0;
const streams=[],disposers=[];
disposers.push(installTransportKeys({finish,onError:report}));
let renderFrame=0,streamRecovery=null,lastPacket=0,retryAfter=0;
let recoveryTimer=0,transportValue;
let lastNativePacket=null,connectionError=null;
let doubleTelemetry=null;
const doubleMotion=new DoublerMotion();
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
const plots={input:new Spectrogram($('input-spectrogram'),$('input-status')),output:new Spectrogram($('output-spectrogram'),$('output-status'))};
const modView=new ModulationView($('mod-graph'),$('mod-live'));
let modFrame=0,lastModPaint=0;
function modulationShape(){return modulationShapeFor(modulationGroups[Number($('mod-source').value)||0],get);}

function animateModulation(time){
 if(disposed)return;
 if(!document.hidden&&time-lastModPaint>=30){lastModPaint=time;const source=modulationGroups[Number($('mod-source').value)||0];modView.draw(source.telemetry,modulationShape(),source.depth?get(source.depth)/100:1);if(doubleTelemetry&&performance.now()-doubleTelemetry.received>=500)doubleTelemetry=null;if(modules[selected].key==='double')drawModuleGraph();}
 modFrame=requestAnimationFrame(animateModulation);
}
function report(error){$('status').textContent=error?.message||String(error);if(channelErrors.has(error?.code)){connectionError={code:error.code,message:$('status').textContent};lastNativePacket=null;}if(jsfx)updateConnection();else $('connection').textContent=error?.code||'CHECK STATUS';}
function fmt(id,value){const p=spec(id);if(p.options)return p.options[Math.round(value-p.min)]||String(value);return value.toFixed(p.step>=1?0:p.step>=.1?1:p.step>=.01?2:3);}
function normalized(id,value){const p=spec(id);return Math.max(0,Math.min(1,(value-p.min)/(p.max-p.min)));}
function canEdit(){return preview||(active&&jsfx?.params.snapshot);}
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
 const p=spec(id),root=el('div','control'),label=el('label','label',labels[id]||p.name),uid=`p${id}-${Math.random().toString(36).slice(2,8)}`;
 root.title=`${p.name} · parameter ${id}`;root.append(label);let input,number;
 if(p.options&&p.options.length<=4&&(id<89||id===116||id===117||id===130)){
  root.classList.add('mode-control');input=el('div','segments mode-buttons');input.setAttribute('role','group');input.setAttribute('aria-label',p.name);
  p.options.forEach((name,i)=>{if(id===45&&i===1)return;const text=id===45?(i===0?'OFF':'ATTACK'):id===75?['LP','HP','BP','NOTCH'][i]:name;const b=el('button',null,text);b.type='button';b.dataset.value=String(p.min+i*p.step);b.title=id===45?text:name;b.onclick=()=>discrete(id,Number(b.dataset.value));input.append(b);});root.append(input);
 }else if(p.options){
  input=el('select');input.id=uid;label.htmlFor=uid;
  if(id>=90&&id<=111&&(id-90)%3===0){
   const groups=new Map();for(const target of matrixTargets){const option=el('option',null,target.label);option.value=String(target.id);if(!target.id){input.append(option);continue;}if(!groups.has(target.group)){const group=el('optgroup');group.label=target.group;groups.set(target.group,group);input.append(group);}groups.get(target.group).append(option);}
  }else p.options.forEach((name,i)=>{const o=el('option',null,name);o.value=String(p.min+i*p.step);input.append(o);});
  input.addEventListener('change',()=>discrete(id,Number(input.value)));root.append(input);
 }else{
  const numberRow=el('div','number-unit');number=el('input','number');number.id=uid;number.type='number';number.min=p.min;number.max=p.max;number.step=p.step;number.setAttribute('aria-label',p.name);label.htmlFor=uid;
  number.addEventListener('change',()=>{const v=Number(number.value);if(Number.isFinite(v))discrete(id,fromPosition(p,toPosition(p,Math.max(p.min,Math.min(p.max,v)))));});
  numberRow.append(number,el('span','unit',units[id]||''));root.append(numberRow);
  input=el('input');input.type='range';input.min=0;input.max=1;input.step=.0001;input.setAttribute('aria-label',p.name);
  input.addEventListener('pointerdown',()=>start(id));
  input.addEventListener('keydown',e=>{if(['ArrowLeft','ArrowRight','ArrowUp','ArrowDown','Home','End','PageUp','PageDown'].includes(e.key))start(id);});
  input.addEventListener('input',()=>write(id,fromPosition(p,Number(input.value))));
  for(const event of ['change','keyup','blur'])input.addEventListener(event,finish);
  root.append(input);
 }
 root.addEventListener('contextmenu',e=>{e.preventDefault();discrete(id,p.default);});
 const w={input,number};if(!widgets.has(id))widgets.set(id,[]);widgets.get(id).push(w);return root;
}
function clearControls(container){for(const [id,list]of widgets)widgets.set(id,list.filter(w=>!container.contains(w.input)));container.replaceChildren();}
function fill(container,ids){clearControls(container);container.classList.toggle('vertical-faders',container.id==='module-controls'||container.id==='core-controls'&&coreTab==='disperser');ids.forEach(id=>container.append(control(id)));}
function toggle(id){const b=el('button','toggle');b.type='button';b.title=spec(id).name;b.setAttribute('aria-label',spec(id).name);b.dataset.toggle=String(id);b.addEventListener('click',()=>discrete(id,get(id)>.5?0:1));return b;}
function coreContent(){
 $('core').dataset.view=coreTab;
 $('core-tabs').replaceChildren();for(const key of Object.keys(coreGroups)){const b=el('button',key===coreTab?'active':'',key[0].toUpperCase()+key.slice(1));b.onclick=()=>{coreTab=key;coreContent();render();};$('core-tabs').append(b);}
 fill($('core-controls'),coreGroups[coreTab].main);fill($('core-secondary'),coreGroups[coreTab].extra);
 $('core-graph-label').textContent=coreTab==='comb'?'PARALLEL DELAYS / MODEL':coreTab==='shift'?'SIGNED FREQUENCY SHIFT / CONTROL':'SECTION CENTERS / MODEL';
}
function modulationContent(){
 const group=modulationGroups[Number($('mod-source').value)||0];
 fill($('mod-controls'),group.ids);
 if(group.on){
  const modes=el('div','segments lfo-modes');modes.setAttribute('role','group');modes.setAttribute('aria-label','LFO waveform');
  ['OFF','SIN','SAW','SQR','RND'].forEach((name,i)=>{const b=el('button',null,name);b.type='button';b.dataset.lfoShape=String(i-1);b.title=['Off','Sine','Saw','Square','Random'][i];b.onclick=()=>i===0?discrete(group.on,0):groupWriteLfo(i-1,group);modes.append(b);});$('mod-controls').prepend(modes);
 }
 $('mod-types').replaceChildren();
 modulationGroups.forEach((g,i)=>{const b=el('button',g===group?'active':'',g.key==='envelope'?'ENV':g.name);b.title=g.name;b.onclick=()=>{finish();$('mod-source').value=String(i);modulationContent();render();};$('mod-types').append(b);});
 $('mod-graph-label').textContent=group.key==='envelope'?'INPUT LEVEL / HISTORY':modulationShape()==='random'?'RANDOM OUTPUT / HISTORY':'WAVEFORM / MODEL + DSP';
 if(group.key==='pitch'){const b=el('button',null,'TRIGGER');b.id='motion-trigger';b.title='Trigger the Motion source. Assign Motion to a destination in the matrix.';b.onclick=()=>command('pitchTrigger');$('mod-controls').append(b);}
}
function groupWriteLfo(shape,source){return group([[source.on,1],[source.shape,shape]]);}
function modulationAssignments(){
 for(let i=0;i<8;i++){const target=Math.round(get(90+i*3)),row=$('mod-assignments').children[i];if(!row)continue;row.classList.toggle('route-disabled',get(89+i*3)<.5||target===0||get(113)<.5);row.querySelector('.matrix-range').textContent=target?`±${matrixScales[target]} ${matrixUnits[target]}`:'—';}
}
function moduleContent(){
 const m=modules[selected];$('module-name').textContent=m.name;$('module-enable').replaceChildren();
 $('module').dataset.module=m.key;
 $('module-graph').title=m.key==='freeze'?'Control diagram: window width = Loop length on a fixed 0–500 ms scale; arrow = Forward/Reverse; fill brightness = Mix. This is not a captured waveform or live playback position.':m.key==='double'?'Control diagram: X = Width, Y = Voice Delay, radius = Pitch, brightness = Mix/Gain. Blue: main signal; orange: added L/R voice. Internal pitch read-head latency is not plotted. Dashed: inverted polarity; bottom bar: voice passband.':'Parameter-based module model';
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
 $('utility-tabs').replaceChildren();for(const key of ['random','morph']){const b=el('button',key===utilityTab?'active':'',key[0].toUpperCase()+key.slice(1));b.onclick=()=>{utilityTab=key;utilityContent();render();};$('utility-tabs').append(b);}
 fill($('utility-controls'),utilityTab==='envelope'?[60,61,62,63,64]:utilityTab==='random'?[66,67]:[65]);
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
 const key=[...order,selected,capture,Number(!!canEdit()),...modules.map(m=>get(m.on))].join(':');if(key===routeKey)return;routeKey=key;
 $('route').replaceChildren();const core=el('button','fixed','CORE');core.title='Fixed parallel engine, always first';$('route').append(core);
 for(const id of order){const m=modules[id],on=get(m.on)>.5,b=el('div',`route-item ${selected===id?'active':''} ${!on?'off':''} ${captures[capture]?.[2]===id?'capture':''}`);
  const choose=el('button','route-select',m.key.toUpperCase()),power=el('button','route-power');power.type='button';power.title=`${on?'Disable':'Enable'} ${m.name}`;power.setAttribute('aria-label',`Enable ${m.name}`);power.setAttribute('aria-pressed',String(on));power.disabled=!canEdit();
  power.append(el('span','dot'));power.onclick=e=>{e.stopPropagation();discrete(m.on,on?0:1);};
  power.addEventListener('pointerdown',e=>e.stopPropagation());power.draggable=false;
  b.append(power,choose);b.draggable=true;
  b.onclick=()=>{finish();selected=id;moduleContent();render();};
  b.addEventListener('dragstart',e=>e.dataTransfer.setData('text/plain',String(id)));
  b.addEventListener('dragover',e=>e.preventDefault());b.addEventListener('drop',e=>{e.preventDefault();const raw=e.dataTransfer.getData('text/plain');if(!/^\d$/.test(raw))return;const from=order.indexOf(Number(raw)),to=order.indexOf(id);if(from<0)return;const next=[...order];const [moved]=next.splice(from,1);next.splice(to,0,moved);const result=encodeOrder(next);group([[73,result.rank],[83,result.position],[118,result.chorusPosition]]);});
  $('route').append(b);
 }
}
function applyState(state){if(!state||disposed)return;for(const p of state.parameters||[]){const id=p.index+1;if(p.index===87&&Number.isFinite(p.value)){if(transportValue!==undefined&&transportValue!==p.value)requestStreamRecovery();transportValue=p.value;}if(specs.has(id)&&Number.isFinite(p.value)&&gesture?.id!==id&&values.get(id)!==p.value)values.set(id,p.value);}scheduleRender();}
function render(){
 for(const [id,list]of widgets){const p=spec(id);for(const w of list){w.input.disabled=!canEdit();if(w.number)w.number.disabled=!canEdit();if(gesture?.id!==id)w.input.value=p.options?String(get(id)):String(toPosition(p,get(id)));if(!p.options)w.input.style.setProperty('--fill',`${Number(w.input.value)*100}%`);if(w.input.classList.contains('mode-buttons'))for(const b of w.input.children){b.disabled=!canEdit();const on=Number(b.dataset.value)===(id===45?(get(id)>1.5?2:0):get(id));b.classList.toggle('active',on);b.setAttribute('aria-pressed',String(on));}if(w.number&&document.activeElement!==w.number)w.number.value=fmt(id,get(id));}}
 document.querySelectorAll('[data-lfo-shape]').forEach(b=>{const source=modulationGroups[Number($('mod-source').value)||0],on=Number(b.dataset.lfoShape)===(get(source.on)>.5?Math.round(get(source.shape)):-1);b.disabled=!canEdit();b.classList.toggle('active',on);b.setAttribute('aria-pressed',String(on));});
 document.querySelectorAll('[data-toggle]').forEach(b=>{const on=get(Number(b.dataset.toggle))>.5;b.classList.toggle('on',on);b.textContent=on?'ON':'OFF';b.disabled=!canEdit();});
 $('feedback').disabled=$('capture').disabled=!canEdit();if(gesture?.id!==6)$('feedback').value=String(normalized(6,get(6)));$('feedback-value').textContent=get(6).toFixed(2);$('capture').value=String(captureIndex());
 $('feedback').style.setProperty('--fill',`${Number($('feedback').value)*100}%`);
 if($('motion-trigger')){$('motion-trigger').hidden=Math.round(get(45))!==2;$('motion-trigger').disabled=!canEdit();}
 $('mod-graph-label').textContent=modulationShape()==='envelope'?'INPUT LEVEL / HISTORY':modulationShape()==='random'?'RANDOM OUTPUT / HISTORY':'WAVEFORM / MODEL + DSP';
 renderRoute();modulationAssignments();drawGraphs();
}
async function command(id){
 await finish();if(preview){$('status').textContent='Local preview: native command not executed';return;}
 try{const operation=await jsfx.commands.invoke(id,[]);$('status').textContent=`${id}: ${operation.state||operation.status||'sent to DSP'}`;}catch(e){report(e);}
}
async function randomize(){await group(randomizeEntries(registry.random,get,get(66),get(67)));}

function chart(canvas,paint,stamp='PARAMETER MODEL'){
 const dpr=Math.min(2,window.devicePixelRatio||1),w=Math.max(100,canvas.clientWidth),h=Math.max(80,canvas.clientHeight);canvas.width=w*dpr;canvas.height=h*dpr;const c=canvas.getContext('2d');c.scale(dpr,dpr);c.fillStyle='#182326';c.fillRect(0,0,w,h);c.strokeStyle='#304245';c.lineWidth=.5;
 for(let i=1;i<8;i++){c.beginPath();c.moveTo(w*i/8,0);c.lineTo(w*i/8,h);c.stroke();}for(let i=1;i<4;i++){c.beginPath();c.moveTo(0,h*i/4);c.lineTo(w,h*i/4);c.stroke();}
 paint(c,w,h);c.fillStyle='#9caead';c.font='8px Arial';c.fillText(stamp,8,h-7);
}
function line(c,points,color){c.strokeStyle=color;c.lineWidth=1.8;c.beginPath();points.forEach(([x,y],i)=>i?c.lineTo(x,y):c.moveTo(x,y));c.stroke();}
function drawGraphs(){
 chart($('core-graph'),(c,w,h)=>{
  if(coreTab==='disperser'){const stages=Math.round(get(10)),span=Math.log(20000/20);c.strokeStyle='#ed9a4b';c.fillStyle='#ed9a4b';for(let i=0;i<stages;i++){const hz=Math.max(20,Math.min(20000,get(7)*2**((stages>1?2*i/(stages-1)-1:0)*get(9)/100))),x=Math.log(hz/20)/span*w;c.beginPath();c.moveTo(x,h-22);c.lineTo(x,22);c.stroke();c.beginPath();c.arc(x,22,2,0,Math.PI*2);c.fill();}$('core-summary').textContent=`${stages} sections · ${Math.round(get(7))} Hz`;}
  else if(coreTab==='comb'){c.font='11px Arial';for(const [i,id]of [4,5].entries()){const y=32+i*40;c.fillStyle='#b9d0cb';c.fillText(id===4?'DRY':'FX FEED',10,y);const x=90+get(id)/50*(w-110);line(c,[[90,y+5],[w-12,y+5]],'#507374');line(c,[[x,y-8],[x,y+15]],'#ef9b4a');}$('core-summary').textContent=`Dry ${get(4).toFixed(1)} / Feed ${get(5).toFixed(1)} ms`;}
  else{const x=w/2+get(12)/5000*w*.45;line(c,[[w/2,18],[w/2,h-22]],'#789492');line(c,[[x,25],[x,h-25]],'#e7a15c');$('core-summary').textContent=`${get(12)>0?'+':''}${get(12).toFixed(1)} Hz`;}
 });
 drawModuleGraph();
}
function drawModuleGraph(){
 const doubleLive=currentDoublerTelemetry(doubleTelemetry,get(69),performance.now(),gesture?.id===69);
 chart($('module-graph'),(c,w,h)=>{
  const key=modules[selected].key;let summary='';
  if(key==='filter'){const mode=Math.round(get(75)),{points,zero}=filterPlot(w,h,{mode,cutoff:get(76),resonance:get(77),mix:get(79)}),fill=c.createLinearGradient(0,0,0,h);fill.addColorStop(0,'#65d59d44');fill.addColorStop(1,'#65d59d05');c.fillStyle=fill;c.beginPath();c.moveTo(0,h-18);for(const [x,y]of points)c.lineTo(x,y);c.lineTo(w,h-18);c.closePath();c.fill();line(c,[[0,zero],[w,zero]],'#78978e');line(c,points,'#65d59d');c.fillStyle='#a3bdb3';c.font='8px Arial';c.fillText('0 dB',5,zero-4);summary=`${spec(75).options[mode]} · ${Math.round(get(76))} Hz`;}
  else if(key==='metal'){drawMetal(c,w,h,{size:get(34),decay:get(35),tone:get(36),mix:get(37),enabled:get(33)>.5});summary=`Size ${get(34).toFixed(2)} · ${get(35).toFixed(2)} s`;}
  else if(key==='sat'){const points=[],drive=10**((get(23)*30+get(126))/20),bias=get(129)*.35,mode=Math.round(get(130));const transfer=v=>mode===1?1.5*Math.max(-1,Math.min(1,v))-.5*Math.max(-1,Math.min(1,v))**3:mode===2?v/(1+Math.abs(v)):mode===3?Math.max(-1,Math.min(1,v)):Math.tanh(v);for(let x=0;x<w;x++){const input=2*x/w-1,shaped=transfer(input*drive+bias)-transfer(bias),y=input+(shaped-input)*get(23)*get(127);points.push([x,Math.max(5,Math.min(h-15,h/2-y*h*.3))]);}line(c,points,'#eaae70');summary=`${spec(130).options[mode]} · ${get(126).toFixed(1)} dB`;}
  else if(key==='pitch'){const points=[];for(let x=0;x<w;x++){const v=get(39)+(get(113)<.5&&Math.round(get(45))===1?Math.sin(x/w*Math.PI*4)*get(40):0);points.push([x,h/2-v/48*(h-30)]);}line(c,points,'#e3a18a');summary=`Base ${get(39).toFixed(1)} st · CONTROL MODEL`;}
  else if(key==='double'){const model=doublerModel({pitch:get(53),detune:get(54),width:get(56),delay:get(69),mix:get(55),enabled:get(52)>.5,gain:get(68),invert:get(72)>.5,lowCut:get(70),highCut:get(71)},doubleLive);drawDoubler(c,w,h,doubleMotion.sample(model,performance.now(),get(69)));summary=`Delay ${get(69).toFixed(1)} ms`;}
  else if(key==='chorus'){const rate=get(57),base=get(122),center=h*.65-base/50*h*.3;line(c,[[0,center],[w,center]],'#6c8581');for(let channel=0;channel<2;channel++){const points=[];for(let x=0;x<w;x++)points.push([x,center+Math.sin(x/w*2*Math.PI*rate*2+channel*get(121)*Math.PI)*get(58)/30*h*.22]);line(c,points,channel?'#f3b774':'#65d59d');}c.fillStyle='#9caead';c.font='9px Arial';c.fillText('2 s / DELAY OFFSET / SCHEMATIC',8,12);summary=`${rate.toFixed(2)} Hz · ${base.toFixed(1)} ms`;}
  else if(key==='ring'){drawRing(c,w,h,{frequency:get(25),depth:get(26),mix:get(27),enabled:get(24)>.5});summary=`Carrier ${get(25).toFixed(1)} Hz`;}
  else{drawFreeze(c,w,h,{length:get(49),mix:get(50),enabled:get(48)>.5,reverse:get(51)>.5});summary=`Loop ${get(49).toFixed(0)} ms · ${get(51)>.5?'REV':'FWD'}`;}
  $('module-summary').textContent=summary;
 },['double','freeze','ring','metal'].includes(modules[selected].key)?'CONTROL MODEL':'PARAMETER MODEL');
}
async function closeStreams(){streamEpoch++;doubleTelemetry=null;const old=streams.splice(0);await Promise.allSettled(old.map(s=>s.close()));for(const id of ['input','output'])$(`${id}-status`).textContent='STREAM PAUSED';}
async function openStreams(){
 if(!jsfx||!active||disposed)return;const epoch=++streamEpoch;
 lastPacket=performance.now();
 for(const id of ['input','output','modulation']){
  if(id==='modulation'){
   try{const s=await jsfx.streams.open(id,{updateRate:30});if(epoch!==streamEpoch||!active){await s.close();return;}streams.push(s);s.on('data',packet=>{if(epoch===streamEpoch){modView.accept(packet);const state=decodeDoubler(packet);if(state)doubleTelemetry={state,received:performance.now()};}});s.on('close',()=>{if(epoch===streamEpoch)requestStreamRecovery();});s.on('error',()=>{if(epoch===streamEpoch)requestStreamRecovery();});}catch(e){report(e);}
   continue;
  }
  try{const s=await jsfx.streams.open(id,{updateRate:30});if(epoch!==streamEpoch||!active){await s.close();return;}streams.push(s);plots[id].clear();s.on('data',packet=>{if(epoch===streamEpoch){lastPacket=performance.now();plots[id].accept(packet,s.info||{});if(packet.data?.length>=32&&Number(s.info?.sampleRate)>=8000){lastNativePacket=performance.now();updateConnection();}}});s.on('close',()=>{if(epoch===streamEpoch){lastPacket=0;lastNativePacket=null;updateConnection();requestStreamRecovery();}});s.on('error',error=>{if(epoch!==streamEpoch)return;lastPacket=0;plots[id].status.textContent='STREAM ERROR';report(error);requestStreamRecovery();});}
  catch(e){$(`${id}-status`).textContent='NO DSP STREAM';report(e);}
 }
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
for(let i=0;i<8;i++){
 const row=el('div','matrix-row'),source=89+i*3,target=source+1,amount=source+2;
 labels[source]='Source';labels[target]='Target';labels[amount]='Amount';
 row.append(el('span','matrix-index',String(i+1)),control(source),control(target),control(amount),el('output','matrix-range'));
 const clear=el('button',null,'×');clear.title=`Clear route ${i+1}`;clear.onclick=()=>group([[source,0],[target,0],[amount,0]]);row.append(clear);$('mod-assignments').append(row);
}
labels[113]='Routing';$('matrix-mode').append(control(113));
$('mod-source').onchange=()=>{finish();modulationContent();render();};
modulationContent();
$('open-matrix').onclick=()=>$('matrix-dialog').showModal();$('close-matrix').onclick=()=>$('matrix-dialog').close();
modFrame=requestAnimationFrame(animateModulation);
for(const id of [2,85,86,87])$('globals').append(id===85?toggle(id):control(id));
fill($('core-mix'),[1,3,13,124]);coreContent();moduleContent();utilityContent();
$('feedback').addEventListener('pointerdown',()=>start(6));$('feedback').addEventListener('input',()=>write(6,fromPosition(spec(6),Number($('feedback').value))));$('feedback').addEventListener('change',finish);$('feedback').addEventListener('contextmenu',e=>{e.preventDefault();discrete(6,.3);});
 $('capture').onchange=()=>group([22,47,59,84,123].map((id,i)=>[id,captures[Number($('capture').value)][1][i]??0]));
for(const event of ['pointerup','pointercancel','blur'])window.addEventListener(event,finish);
$('history').onchange=()=>{for(const plot of Object.values(plots)){plot.seconds=Number($('history').value);plot.clear();}};
$('freeze-display').onclick=()=>{const paused=!plots.input.paused;for(const plot of Object.values(plots))plot.paused=paused;$('freeze-display').textContent=paused?'▶':'Ⅱ';$('freeze-display').title=paused?'Resume spectrogram display':'Pause spectrogram display only';};
$('clear-display').onclick=()=>Object.values(plots).forEach(plot=>plot.clear());
function setPalette(name){const selected=palettes[name]?name:'aurora';$('palette').value=selected;for(const plot of Object.values(plots)){plot.palette=selected;plot.clear();}$('palette-scale').style.background=`linear-gradient(90deg,${palettes[selected].map(([p,r,g,b])=>`rgb(${r},${g},${b}) ${p*100}%`).join(',')})`;}
let savedPalette='aurora';try{savedPalette=localStorage.getItem('ultracomb.spectrogramPalette')||savedPalette;}catch{}
setPalette(savedPalette);$('palette').onchange=()=>{setPalette($('palette').value);try{localStorage.setItem('ultracomb.spectrogramPalette',$('palette').value);}catch{}};
$('all-parameters').onclick=()=>{fill($('parameter-list'),registry.parameters.map(p=>p.id));$('parameter-dialog').showModal();render();};$('close-dialog').onclick=()=>$('parameter-dialog').close();
$('search').oninput=()=>{const q=$('search').value.toLowerCase();for(const node of $('parameter-list').children)node.hidden=!node.title.toLowerCase().includes(q);};
window.addEventListener('resize',()=>{drawGraphs();Object.values(plots).forEach(plot=>plot.clear());});
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
