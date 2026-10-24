import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import {arithmeticBody} from './eel-arithmetic.mjs';
import {matrixTargets,modulationGroups} from '../webui/model.mjs';
import {decodeTelemetry} from '../webui/modulation-view.mjs';
import {decodeDoubler} from '../webui/doubler-view.mjs';
const source=fs.readFileSync(new URL('../sbp_ultraComb_webui.jsfx',import.meta.url),'utf8');
const init=arithmeticBody(source,'uc_matrix_lfo_init'),process=arithmeticBody(source,'uc_matrix_lfo_process');
function create(sr,rate){const c=vm.createContext({rate,sample_rate:sr,max:Math.max,min:Math.min,exp:Math.exp,floor:Math.floor,sin:Math.sin,$pi:Math.PI,rand:n=>n*.7});init.runInContext(c);Object.assign(c,{enabled:1,target_rate:rate,target_depth:100,degrees:0,shape:0,interval:32});return c;}
function step(c,n=1){for(let i=0;i<n;i++)process.runInContext(c);}
for(const sr of [44100,48000,96000]){
 const a=create(sr,1),b=create(sr,2);step(a,200);step(b,200);
 assert(Math.abs(b.phase-2*a.phase)<1e-10,'Each LFO must own an independent rate/phase');
 const phase=a.phase;step(b,10);assert.equal(a.phase,phase,'Processing LFO 2 must not modify LFO 1');
 a.degrees=90;step(a,1000);assert(Math.abs(a.offset-.25)<1e-8);
 a.target_depth=0;step(a,1000);assert(Math.abs(a.output)<1e-8);
 a.target_depth=100;a.enabled=0;const stopped=a.phase;step(a,1000);assert.equal(a.phase,stopped);assert(Math.abs(a.output)<1e-8,'Off must settle to zero');
 for(const shape of [0,1,2,3]){a.shape=shape;a.enabled=1;a.target_rate=100;a.target_depth=1000;a.degrees=360;for(let i=0;i<1000;i++){step(a);assert(Number.isFinite(a.output)&&Math.abs(a.output)<=1.000001);assert(a.phase>=0&&a.phase<1);assert(a.rate_hz<=12&&a.depth<=1);}}
 // Both sources read a snapshot before the next route sum, matching the DSP order.
 const x=create(sr,.5),y=create(sr,2);let previousX=0,previousY=0;
 for(let tick=0;tick<3000;tick++){
  x.target_rate=Math.max(.02,Math.min(12,.5*2**(previousY*4)));x.target_depth=Math.max(0,Math.min(100,50+previousY*100));
  y.target_rate=Math.max(.02,Math.min(12,2*2**(previousX*4)));y.target_depth=Math.max(0,Math.min(100,50+previousX*100));
  step(x);step(y);previousX=x.output;previousY=y.output;
  assert(Number.isFinite(previousX)&&Number.isFinite(previousY));assert(Math.abs(previousX)<=1&&Math.abs(previousY)<=1);
 }
}
assert.equal(matrixTargets.length,49);assert.equal(modulationGroups.length,4);
assert.deepEqual(matrixTargets.slice(12,16).map(t=>t.label),['LFO 1 / Rate','LFO 1 / Depth','LFO 2 / Rate','LFO 2 / Depth']);
for(let id=12;id<=48;id++)assert(new RegExp(`uc_mod_(?:linear|octaves)\\([^,]+,${id},`).test(source),`Target ${id} must reach DSP`);
assert(source.includes('MATRIX_TARGET=MATRIX+64'));
assert(source.includes('matrix_source<=4 && matrix_destination>0 && matrix_destination<=48'));
assert(source.indexOf('ultra_lfo2.uc_matrix_lfo_process(',source.indexOf('@sample'))<source.indexOf('loop(48,MATRIX_TARGET',source.indexOf('@sample')),'Both LFOs must read previous targets');
const begin=source.indexOf('matrix_i=1;loop(48,MATRIX_TARGET',source.indexOf('@sample'));
let routeCode=source.slice(begin,source.indexOf('\n  );',begin));
routeCode=routeCode.replace(/loop\((48|8),/g,'for(let iteration=0;iteration<$1;iteration++){').replace(/;\);/g,';}').replace(/^\s*\);$/gm,'}');
routeCode=routeCode.replace(/(matrix_source>0[^?]+)\? (MATRIX_TARGET\[matrix_destination\]\+=.*);/,'if($1){$2;}');
const sliders=new Float64Array(136),targets=new Float64Array(64);
const routes=vm.createContext({MATRIX_TARGET:targets,slider:id=>sliders[id],floor:Math.floor,max:Math.max,min:Math.min,fs_rand_value:.5,fs_shared_depth:1,ultra_motion:{visual_motion:.25},env_amount:.75,ultra_lfo2:{output:-.8}});
const router=new vm.Script(routeCode);
router.runInContext(routes);assert(targets.every(v=>v===0),'All sources Off must produce neutral destinations');
for(let i=0;i<8;i++){sliders[89+i*3]=4;sliders[90+i*3]=12;sliders[91+i*3]=1;}
router.runInContext(routes);assert.equal(targets[12],-1,'Multiple LFO 2 routes must sum and clamp');
sliders.fill(0);sliders[89]=1;sliders[90]=14;sliders[91]=1;sliders[92]=4;sliders[93]=13;sliders[94]=-.5;
router.runInContext(routes);assert.equal(targets[14],.5);assert.equal(targets[13],.4);assert.equal(targets[12],0,'Removed routes must clear old modulation');
const packet=new Float32Array(32);packet[29]=.25;packet[30]=-.75;packet[31]=1;packet[26]=1;
assert.deepEqual(decodeTelemetry({data:packet})[7],{phase:.25,value:-.75,enabled:true});assert(decodeDoubler({data:packet}));
console.log('PASS: actual LFO EEL bodies at 44.1/48/96 kHz, independent phase/rate, Off/depth/phase, every shape, bounded cross modulation, 48 wired targets and 32-channel telemetry. Native host/audio checks remain separate.');
