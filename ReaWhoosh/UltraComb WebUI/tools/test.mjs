import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath}from'node:url';
import {modules,coreGroups,modulationGroups,formatControlLabel,toPosition,fromPosition,decodeOrder,encodeOrder}from'../webui/model.mjs';
import {color,palettes}from'../webui/spectrogram.mjs';
import {wave,decodeTelemetry}from'../webui/modulation-view.mjs';
import {filterPlot,filterDrive}from'../webui/filter-model.mjs';
import {doublerModel,doublerPoints,decodeDoubler,currentDoublerTelemetry,DoublerMotion}from'../webui/doubler-view.mjs';
import {freezeWindow}from'../webui/freeze-view.mjs';
import {ringModel,metalModes,metalModel}from'../webui/ring-metal-view.mjs';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const old=fs.readFileSync(path.join(root,'../sbp_ultraComb.jsfx'),'utf8'),source=fs.readFileSync(path.join(root,'sbp_ultraComb_webui.jsfx'),'utf8');
const {parameters}=JSON.parse(fs.readFileSync(path.join(root,'webui/parameters.json')));
const lines=s=>s.split(/\r?\n/).filter(l=>/^slider\d+:/.test(l));
const ranges=s=>lines(s).slice(0,87).map(l=>l.split('>-')[0].replace(/\{[^}]*\}/g,''));
assert.deepEqual(ranges(source).filter((_,i)=>![3,4,66,74].includes(i)),ranges(old).filter((_,i)=>![3,4,66,74].includes(i)),'Only explicitly expanded delay, scope and filter-mode ranges may change');
for(const id of [4,5])assert.equal(parameters.find(p=>p.id===id).max,200);
assert.equal(lines(source).length,214);assert.equal(parameters.length,213);
assert(old.includes('// @version 2.40'));assert(source.includes('// @version 3.14.0'));
assert.equal(formatControlLabel(parameters.find(p=>p.id===9)),'Spread, %');
assert.equal(formatControlLabel(parameters.find(p=>p.id===53)),'Voice Pitch, st');
assert.equal(formatControlLabel(parameters.find(p=>p.id===7)),'Center, Hz');
assert.equal(formatControlLabel(parameters.find(p=>p.id===50)),'Mix');
assert(!source.split(/\r?\n/).some(l=>/^\s*read_pos=/.test(l)&&l.includes('%')),'Fractional read addresses must not use EEL integer modulo');
for(const [w,h]of [[250,110],[350,140],[500,140]]){
 const settings={length:120,mix:1,enabled:true,reverse:false},base=freezeWindow(w,h,settings);
 const shortest=freezeWindow(w,h,{...settings,length:20}),longest=freezeWindow(w,h,{...settings,length:500});
 assert(shortest.end<base.end&&base.end<longest.end);assert.equal(longest.end,longest.right);
 assert(Math.abs((base.end-base.left)/(longest.end-longest.left)-120/500)<1e-12,'Loop width must use a fixed linear time scale');
 assert.deepEqual(freezeWindow(w,h,{...settings,length:500}),longest);
 assert.deepEqual(freezeWindow(w,h,settings),base,'Loop window must return to its original size');
 assert.equal(freezeWindow(w,h,{...settings,reverse:true,mix:0,enabled:false}).end,base.end,'Direction, Mix and Off must not resize the loop');
 assert(shortest.bottom>shortest.top);
}
assert.deepEqual(modules.find(m=>m.key==='pitch').main,[39,44,43]);
assert(!source.includes('pitch_grain = slider43'));
assert(!source.includes('grain_target = max(10, min(100, atomic_get(ui_pitch_grain)))'));
assert(!source.includes('update_pitch_controls('),'Removed Doubler/Pitch coupling must have no remaining calls');
const ringSettings={frequency:120,depth:1,mix:1,enabled:true};
for(const h of [110,140]){
 const neutral=ringModel(300,h,{...ringSettings,mix:0});assert(neutral.points.every(p=>p[1]===neutral.unity));
 assert.deepEqual(ringModel(300,h,{...ringSettings,depth:0}).points,neutral.points);
 const full=ringModel(300,h,ringSettings),high=ringModel(300,h,{...ringSettings,frequency:700});
 assert.notDeepEqual(high.points,full.points);assert(full.points.every(p=>p[1]>24&&p[1]<h-29));
 const metalSettings={size:1,decay:.6,tone:.65,mix:.35,enabled:true};
 const modes=metalModes(metalSettings),large=metalModes({...metalSettings,size:2}),long=metalModes({...metalSettings,decay:3}),bright=metalModes({...metalSettings,tone:1});
 modes.forEach((m,i)=>{assert.equal(large[i].hz,m.hz/2);assert(long[i].bandwidth<m.bandwidth);assert(bright[i].weight>=m.weight);});
 const dry=metalModel(300,h,{...metalSettings,mix:0});assert(dry.curves.every(c=>c.points.every(p=>p[1]===dry.bottom)));
 for(const size of [.25,4])for(const decay of [.03,3]){const m=metalModel(300,h,{...metalSettings,size,decay,mix:1});assert.equal(m.curves.length,6);assert(m.curves.every(c=>c.points.every(p=>Number.isFinite(p[1])&&p[1]>=m.top&&p[1]<=m.bottom)));}
}
assert(!parameters.some(p=>/\btap\b/i.test(p.name)||p.options?.some(o=>/\btaps?\b/i.test(o))));
for(const height of [110,140]){
 const flat=filterPlot(300,height,{mode:0,cutoff:682,resonance:1,mix:0});assert.equal(flat.zero,height/2);assert(flat.points.every(p=>p[1]===height/2));
 for(const mode of [0,1])for(const cutoff of [20,682,20000]){const plot=filterPlot(300,height,{mode,cutoff,resonance:1,mix:1});const peak=Math.min(...plot.points.map(p=>p[1]));assert(peak>6&&peak<height/2,'Maximum resonance must fit above zero without top clipping');}
 const bp=filterPlot(300,height,{mode:2,cutoff:682,resonance:1,mix:1});assert(Math.abs(Math.min(...bp.points.map(p=>p[1]))-height/2)<1e-8,'Native bandpass is normalized to unity, even at high Q');
}
for(const input of [-1,-.3,0,.3,1]){assert.equal(filterDrive(input,0),input);assert(Number.isFinite(filterDrive(input,24)));}
assert(!source.includes('ui_fb_saturation, slider23'));
assert(source.includes('fb_saturation = slider124'));
assert(source.includes('uc_sat_process(pre_disp_l,pre_disp_r,uc_mod_linear(slider23,44,1,0,1),slider125'));
assert.equal(Object.keys(palettes).length,4);
for(const palette of Object.keys(palettes))for(const db of [-120,-90,-60,-30,0,12])assert(color(db,palette).every(c=>Number.isFinite(c)&&c>=0&&c<=255));
// EEL variable names are case-insensitive, including pointer-valued variables.
for(const pointer of ['MATRIX','MATRIX_TARGET','WEB_MOD','WEB_REPLY','WEB_INPUT','WEB_OUTPUT','WEB_MEMORY']){
 const assignments=source.match(new RegExp('\\b'+pointer+'\\s*=(?!=)','gi'))||[];
 assert.equal(assignments.length,1,`${pointer} must only be assigned its buffer address`);
}
assert(source.includes('MATRIX_TARGET[matrix_destination]'));
const ids=new Set([...Object.values(coreGroups).flatMap(g=>[...(g.primary||[]),...g.main,...g.extra]),...modules.flatMap(m=>[m.on,...m.main,...m.extra].filter(Boolean)),1,2,3,6,13,22,47,59,60,61,62,63,64,65,66,67,73,83,84,85,86,87]);
for(const group of modulationGroups)for(const id of group.ids)ids.add(id);
const legacyIds=[16,17,18,19,21,28,29,30,31,32,40,41,42,45,46,57,58,80,81,82];
for(let id=1;id<=87;id++)assert(ids.has(id)||legacyIds.includes(id)||[14,20].includes(id),`Parameter ${id} missing from UI grouping`);
for(let id=89;id<=214;id++)assert(parameters.some(p=>p.id===id));
assert.equal(parameters.find(p=>p.id===67).max,21);assert.equal(parameters.find(p=>p.id===188).max,21);
assert.deepEqual(coreGroups.shift.primary,[12]);assert.deepEqual(coreGroups.shift.main,[137,138,139]);
for(const [id,value]of [[137,0],[138,1],[139,1]])assert.equal(parameters.find(p=>p.id===id).default,value);
assert.equal((source.match(/^in_pin:/gm)||[]).length,4);
assert.equal((source.match(/^out_pin:/gm)||[]).length,2);
assert(source.includes('motion_input=slider116>0.5 ? detector_external : detector_internal'));
assert(source.includes('env_input=slider117>0.5 ? detector_external : detector_internal'));
assert.equal(parameters.find(p=>p.id===114).default,100);
assert.equal(parameters.find(p=>p.id===115).max,360);
assert(source.includes('uc_matrix_convert(fs_rand_value,1,matrix_polarity,fs_shared_depth,slider14>0.5)'));
assert(Object.values(coreGroups).every(group=>group.extra.length===0),'Core must not contain local LFO controls');
assert.equal(modulationGroups.length,5);
assert(!modulationGroups.some(g=>g.key==='pitch'),'Motion must be retired from modulation families');
for(const id of [42,45,46,116])assert(parameters.find(p=>p.id===id).deprecated);
for(let route=0;route<8;route++){
 assert.equal(parameters.find(p=>p.id===89+route*3).max,6);
 assert.equal(parameters.find(p=>p.id===90+route*3).max,78);
 assert.equal(parameters.find(p=>p.id===91+route*3).min,-1);
}
for(const p of parameters)for(const t of [0,.001,.1,.25,.5,.75,.99,1]){const value=fromPosition(p,t);assert(value>=p.min-1e-9&&value<=p.max+1e-9);assert(Math.abs(fromPosition(p,toPosition(p,value))-value)<Math.max(1e-7,p.step*.01));}
for(let rank=0;rank<720;rank++)for(let position=0;position<7;position++)for(let chorusPosition=0;chorusPosition<8;chorusPosition++){const order=decodeOrder(rank,position,chorusPosition);assert.equal(new Set(order).size,8);assert.deepEqual(encodeOrder(order),{rank,position,chorusPosition});}
assert.equal(parameters.find(p=>p.id===119).default,0);
assert(source.includes('route_module==7 ? ('));
assert(source.includes('post_chorus_l*sm_tap_chorus'));
const association=JSON.parse(fs.readFileSync(path.join(root,'sbp_ultraComb_webui.json'))).JSFX_WebUI;
assert.equal(association.native.transportParam,87);assert.equal(association.native.streams.length,5);
assert(association.native.streams.slice(0,2).every(s=>s.kind==='spectrum'&&s.channels===2));
assert.equal(association.native.streams[2].channels,1);
const baseDouble={pitch:0,detune:0,width:0,delay:20,mix:.5,enabled:true,gain:0,invert:false,lowCut:0,highCut:20000};
const monoDouble=doublerModel(baseDouble);assert.equal(monoDouble.delayL,20);assert.equal(monoDouble.delayR,20);
const wideDouble=doublerModel({...baseDouble,width:1});assert.equal(wideDouble.delayR,wideDouble.delayL);
const geometry=doublerPoints(300,140,wideDouble);assert(geometry.left[0]<geometry.origin[0]&&geometry.right[0]>geometry.origin[0]);assert.equal(geometry.left[1],geometry.right[1]);
assert(doublerModel({...baseDouble,delay:50}).delayL>monoDouble.delayL);
const higherDouble=doublerModel({...baseDouble,pitch:12});assert.equal(higherDouble.delayL,monoDouble.delayL);assert(higherDouble.pitchRadius>monoDouble.pitchRadius);
assert.deepEqual(doublerModel({...baseDouble,pitch:12,detune:50}).voicePitches,[11.5,12.5]);
assert.equal(doublerModel({...baseDouble,pitch:12,detune:50}).semi,12,'Voice Pitch remains the centre of opposing detunes');
assert.equal(doublerModel({...baseDouble,gain:12,mix:1}).pitchRadius,monoDouble.pitchRadius,'Mix/Gain must not control pitch radius');
const livePositionA=doublerPoints(300,140,doublerModel(baseDouble,{...monoDouble,delayL:20,delayR:25,semi:12}));
const livePositionB=doublerPoints(300,140,doublerModel(baseDouble,{...monoDouble,delayL:180,delayR:190,semi:-12}));
assert.deepEqual(livePositionA,livePositionB,'Pitch/read-head changes must not move the control-diagram endpoints');
assert(doublerModel({...baseDouble,gain:6}).voiceGain>monoDouble.voiceGain);
assert.equal(doublerModel({...baseDouble,enabled:false}).voiceGain,0);
const liveDouble=new Float32Array(29);liveDouble[21]=60;liveDouble[22]=65;liveDouble[23]=.09;liveDouble[24]=.5;liveDouble[25]=.7;liveDouble[26]=1;liveDouble[27]=-1;
assert.equal(decodeDoubler({data:liveDouble}).delayR,65);assert.equal(decodeDoubler({data:liveDouble}).polarity,-1);
const cached={state:decodeDoubler({data:liveDouble}),received:100};
assert.equal(currentDoublerTelemetry(cached,100,110),null,'Old delay packets must not override a new target');
assert.equal(currentDoublerTelemetry(cached,0,110),cached.state);
assert.equal(currentDoublerTelemetry(cached,0,600),null,'Expired telemetry must fall back');
assert.equal(currentDoublerTelemetry(cached,0,110,true),null,'Dragging delay must own the graph');
assert.equal(doublerPoints(300,140,{...wideDouble,delayL:180,delayR:190}).maxDelay,geometry.maxDelay,'Delay axis must not auto-zoom');
const motion=new DoublerMotion();motion.sample(wideDouble,0,20);
const jump=motion.sample({...wideDouble,delayL:180,delayR:190},33,20);
assert(jump.delayL>wideDouble.delayL&&jump.delayL<80,'Read-head jumps must be visually smoothed');
const manual=motion.sample({...wideDouble,delayL:80,delayR:90},34,80);
assert.equal(manual.delayL,80,'Manual Delay changes must remain immediate');
for(let t=67;t<1000;t+=33)motion.sample({...wideDouble,delayL:100,delayR:110},t,80);
assert(Math.abs(motion.state.delayL-100)<.01,'Display smoothing must converge');
assert(decodeTelemetry({data:liveDouble}));assert.equal(decodeDoubler({data:new Float32Array(21)}),null);
assert.equal(decodeTelemetry({data:new Float32Array(20)}),null);
const telemetry=new Float32Array(21);telemetry[0]=.25;telemetry[1]=.5;telemetry[2]=1;
assert.deepEqual(decodeTelemetry({data:telemetry})[0],{phase:.25,value:.5,enabled:true});
telemetry[1]=NaN;assert.equal(decodeTelemetry({data:telemetry}),null);
assert(Math.abs(wave('sine',.25)-1)<1e-9);
assert.equal(wave('triangle',.5),1);assert.equal(wave('square',.75),-1);
assert(source.includes('WEB_MEMORY=ceil((SPECTRAL_BUFFER+262144)/65536)*65536;'));
assert(source.includes('reaweb_jsfx_publish(0,WEB_INPUT,1024,2,web_sample_clock-511);'));
assert(source.includes('reaweb_jsfx_publish(1,WEB_OUTPUT,1024,2,web_sample_clock-511);'));
for(const db of [-120,-90,-70,-30,0,12])assert(color(db).every(c=>Number.isInteger(c)&&c>=0&&c<=255));
for(const rate of [44100,48000,96000,192000]){const fft=Math.min(8192,Math.max(1024,2**Math.ceil(Math.log2(rate*.04))));assert(fft<=8192);}
console.log('PASS: old version retained, original IDs preserved, explicit delay/scope range changes, 213 registered native controls (four retired from WebUI), scales, 40320 routes and bounded native declarations. Native audio/host tests still required.');
