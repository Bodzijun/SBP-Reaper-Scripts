import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import {syncFunctions} from './tempo-fixture.mjs';
import {matrixHelpers} from './matrix-fixture.mjs';
import {feedbackTargets,feedbackValue,decodeFeedback,ModulationFeedback,FEEDBACK_LENGTH} from '../webui/modulation-feedback.mjs';
import {decodeTelemetry} from '../webui/modulation-view.mjs';
import {decodeDoubler} from '../webui/doubler-view.mjs';
const source=fs.readFileSync(new URL('../sbp_ultraComb_webui.jsfx',import.meta.url),'utf8'),registry=JSON.parse(fs.readFileSync(new URL('../webui/parameters.json',import.meta.url),'utf8')),specs=new Map(registry.parameters.map(p=>[p.id,p]));
assert(source.indexOf('function uc_visual_snapshot(')<source.indexOf('\n@slider'),'Shared feedback functions must be declared in @init');
let loopId=0;
function loops(code){const start=code.indexOf('loop(');if(start<0)return code;let depth=1,comma=-1,end=start+5;for(;end<code.length;end++){if(code[end]==='(')depth++;if(code[end]===')'&&!--depth)break;if(code[end]===','&&depth===1&&comma<0)comma=end;}assert(comma>start&&depth===0);const n=loopId++;return code.slice(0,start)+`for(let count${n}=${code.slice(start+5,comma)},iteration${n}=0;iteration${n}<count${n};iteration${n}++){${loops(code.slice(comma+1,end))}}`+loops(code.slice(end+1));}
const pointers=['WEB_MOD','MATRIX','VIS_IDS','VIS_LOW','VIS_HIGH','VIS_SCALE','VIS_KIND'];
function translate(code){code=loops(code.replace(/\/\/[^\n]*/g,''));code=code.replace(/^\s*\) : \(\s*$/gm,'} else {');code=code.replace(/^(\s*)([^\n?]+) \? \(\s*$/gm,'$1if($2){').replace(/^\s*\);\s*$/gm,'}').replace(/^(\s*)(destination==\d+(?: && slider\d+>0\.5)?) \? ([^\n]+);/gm,'$1if($2){$3;}');for(const name of pointers)code=code.replace(new RegExp('\\b'+name+'\\[([^\\]]+)\\]','g'),`ram[${name}+($1)]`);return code.replace(/\bslider(\d+)\b/g,'slider($1)').replace(/\$pi/g,'Math.PI');}
const ram=new Float64Array(2000),sliders=new Float64Array(215),c=vm.createContext({ram,sliders,WEB_MOD:0,MATRIX:640,VIS_IDS:768,VIS_LOW:896,VIS_HIGH:1024,VIS_SCALE:1152,VIS_KIND:1280,srate:48000,Math,max:Math.max,min:Math.min,floor:Math.floor,abs:Math.abs,pow:Math.pow,log:Math.log,slider:id=>sliders[id],...matrixHelpers(source),sync_bpm:120,sync_num:4,sync_den:4,sync_bars:4,sync_beat:0,web_adr2_peak:0,adr2_threshold_target:-24,adr_threshold_target:-24,fs_shared_depth:.75,env_depth:-.5,env_sensitivity:1,env_attack_coeff:.002,env_release_coeff:.0001,sm_out:1,sm_drive:1,sm_fb:.3,sm_mix:.5,sm_level:1,sm_sat:0,sm_ring_freq:120,sm_ring_depth:1});
for(const p of registry.parameters)sliders[p.id]=p.default;
Object.assign(c,syncFunctions(source));
const tables=source.split('\n').filter(l=>/^VIS_IDS\[\d+\]=/.test(l)).join('\n');vm.runInContext(translate(tables),c);
for(const name of ['uc_sync_base','uc_visual_value','uc_visual_current','uc_visual_snapshot']){
 const start=source.indexOf(`function ${name}(`),begin=source.indexOf('\n(',start)+2,end=source.indexOf('\n);',begin),header=source.slice(start,begin),args=header.match(/^function \w+\(([^)]*)\)/)[1],locals=header.match(/local\(([^)]*)\)/)[1];let code=translate(source.slice(begin,end));
 if(name==='uc_sync_base')code=code.replace(/\n value;/,'\n return value;');
 if(name==='uc_visual_value')code=code.replace(/\n max\(ram\[VIS_LOW[^\n]+;/,m=>'\n return '+m.trim().slice(0,-1)+';');
 if(name==='uc_visual_current')code=code.replace(/\n max\(ram\[VIS_LOW[^\n]+;/,m=>'\n return '+m.trim().slice(0,-1)+';');
 for(const match of code.matchAll(/\b(ultra_\w+)\.(\w+)/g)){c[match[1]]??={};c[match[1]][match[2]]??=0;}
 vm.runInContext(`${name}=function(${args}){let ${locals.split(',').map(x=>x.trim()+'=0').join(',')};${code}}`,c);
}
// Current values really come from the module trajectories, not a UI LFO model.
c.ultra_comb_history.tap_delay=480;c.delay2_samps=960;c.ultra_disp.config_center=800;c.ultra_disp.config_q=3;c.ultra_shift.current_hz=525;c.ultra_filter.active_hz=4400;c.ultra_filter.res=.6;c.ultra_filter.drive=12;c.ultra_chorus.rate_hz=1.2;c.ultra_chorus.base=480;c.ultra_chorus.width=.8;
for(const t of feedbackTargets){assert.equal(ram[c.VIS_IDS+t.destination],t.parameter);for(const amount of [-1,-.25,0,.25,1])assert(Math.abs(c.uc_visual_value(t.destination,specs.get(t.parameter).default,amount)-feedbackValue(t,specs.get(t.parameter).default,amount,specs.get(t.parameter),48000))<1e-8);}
sliders[113]=1;sliders[14]=1;sliders[89]=1;sliders[90]=9;sliders[91]=.6;sliders[92]=3;sliders[93]=9;sliders[94]=-.8;
ram[c.MATRIX+9]=.2;const beforeRam=ram.slice(640),beforeSliders=sliders.slice();c.uc_visual_snapshot();
assert.deepEqual(ram.slice(640),beforeRam,'Snapshot must not modify matrix/table/audio memory');assert.deepEqual(sliders,beforeSliders,'Display feedback must never write host parameters');
assert(Math.abs(ram[184+8]+.45)<1e-10);assert(Math.abs(ram[254+8]-.85)<1e-10);assert.equal(ram[394+8],1);assert.equal(ram[114+8],4400);assert.equal(ram[114+3],525);assert.equal(ram[114+1],20);
const packet={data:Float32Array.from(ram.slice(0,FEEDBACK_LENGTH))};assert(decodeTelemetry(packet));assert(decodeDoubler(packet));assert(decodeFeedback(packet));
const view=new ModulationFeedback();assert(view.accept(packet,{sampleRate:48000},100));assert.equal(view.value(76,2000,200),4400);assert.equal(view.value(76,2000,601),2000,'Stale feedback must fall back to base');assert(view.range(76,specs.get(76),200).low<2000);view.clear();assert.equal(view.current(76,200),null);
sliders[113]=0;c.uc_visual_snapshot();assert.equal(ram[43],0);assert(ram.slice(394,464).every(x=>x===0));
sliders[113]=1;sliders[14]=0;sliders[92]=0;c.uc_visual_snapshot();assert.equal(ram[184+8],0);assert.equal(ram[254+8],0);assert.equal(ram[394+8],1,'Assigned but disabled sources must remain identifiable without a fake range');
sliders[192]=sliders[193]=sliders[194]=1;sliders[195]=21;sliders[196]=13;sliders[197]=21;sliders[198]=13;sliders[199]=18;
c.sync_bpm=60;c.sync_num=7;c.sync_den=8;c.sync_bars=3.5;c.sync_beat=7.25;
for(const destination of [12,14]){ram[c.VIS_LOW+destination]=1e-6;ram[c.VIS_HIGH+destination]=512;}
for(const destination of [53,54,56])ram[c.VIS_HIGH+destination]=3600000;
c.uc_visual_snapshot();const syncPacket={data:Float32Array.from(ram.slice(0,FEEDBACK_LENGTH))};assert(view.accept(syncPacket,{},1000));assert.equal(view.clock.tempo,60);assert.equal(view.clock.num,7);assert.equal(view.clock.den,8);assert.equal(view.current(195,1001)?.target.destination,12);assert.equal(ram[324+11],1/28);assert.equal(ram[324+52],28000);assert.equal(ram[478],28000);
const old=Float32Array.from(syncPacket.data.slice(0,464));old[42]=1;assert(decodeFeedback({data:old}));
sliders[211]=1;sliders[212]=21;sliders[213]=13;sliders[214]=18;sliders[200]=3;sliders[89]=6;sliders[90]=71;sliders[91]=.5;sliders[172]=2;for(const destination of [71,72,74])ram[c.VIS_HIGH+destination]=3600000;c.ultra_adr2.attack=28;c.ultra_adr2.phase=.25;c.ultra_adr2.output=.4;
c.uc_visual_snapshot();const dualPacket={data:Float32Array.from(ram.slice(0,FEEDBACK_LENGTH))};assert(view.accept(dualPacket,{},1100));assert(view.clock.adr2);assert.equal(view.current(212,1101).base,28000);assert.equal(view.current(212,1101).current,28000);assert.equal(view.current(212,1101).assigned,true);assert.equal(ram[483],-.5);assert.equal(ram[484],.5);assert.equal(decodeTelemetry(dualPacket)[9].phase,.25);sliders[200]=0;c.uc_visual_snapshot();assert.equal(ram[483],0);assert.equal(ram[484],0);
console.log('PASS: actual read-only snapshot, all 78 typed mappings, native smoothed trajectories, summed bipolar/signed-depth domains, old prefix decoders, stale/clear/off behaviour and memory/slider immutability. Native REAPER acceptance remains separate.');
