import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import {arithmeticBody} from './eel-arithmetic.mjs';
import {matrixTargets,modulationGroups} from '../webui/model.mjs';
import {decodeTelemetry} from '../webui/modulation-view.mjs';
import {decodeDoubler} from '../webui/doubler-view.mjs';
import {matrixRoutes,convertSource} from '../webui/matrix-model.mjs';
import {matrixHelpers} from './matrix-fixture.mjs';
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
 for(const shape of [0,1,2,3]){a.shape=shape;a.enabled=1;a.target_rate=100;a.target_depth=1000;a.degrees=360;for(let i=0;i<1000;i++){step(a);assert(Number.isFinite(a.output)&&Math.abs(a.output)<=1.000001);assert(a.phase>=0&&a.phase<1);assert(a.rate_hz<=512&&a.depth<=1);}}
 // Both sources read a snapshot before the next route sum, matching the DSP order.
 const x=create(sr,.5),y=create(sr,2);let previousX=0,previousY=0;
 for(let tick=0;tick<3000;tick++){
  x.target_rate=Math.max(.02,Math.min(12,.5*2**(previousY*4)));x.target_depth=Math.max(0,Math.min(100,50+previousY*100));
  y.target_rate=Math.max(.02,Math.min(12,2*2**(previousX*4)));y.target_depth=Math.max(0,Math.min(100,50+previousX*100));
  step(x);step(y);previousX=x.output;previousY=y.output;
  assert(Number.isFinite(previousX)&&Number.isFinite(previousY));assert(Math.abs(previousX)<=1&&Math.abs(previousY)<=1);
 }
}
assert.equal(matrixTargets.length,79);assert.equal(modulationGroups.length,5);
assert.deepEqual(matrixTargets.slice(12,16).map(t=>t.label),['LFO 1 / Rate','LFO 1 / Depth','LFO 2 / Rate','LFO 2 / Depth']);
for(let id=12;id<=78;id++)if(![12,14,53,54,56,71,72,74].includes(id))assert(new RegExp(`uc_mod_(?:linear|octaves)\\([^,]+,${id},`).test(source),`Target ${id} must reach DSP`);
assert(source.includes('MATRIX_TARGET=MATRIX+128'));
assert(source.includes('matrix_source<=6 && matrix_destination>0 && matrix_destination<=78'));
assert(source.indexOf('ultra_lfo2.uc_matrix_lfo_timing(',source.indexOf('@sample'))<source.indexOf('loop(78,MATRIX_TARGET',source.indexOf('@sample')),'Both LFOs must read previous targets');
const begin=source.indexOf('matrix_i=1;loop(78,MATRIX_TARGET',source.indexOf('@sample'));
let routeCode=source.slice(begin,source.indexOf('\n  );',begin));
routeCode=routeCode.replace(/loop\((78|16),/g,'for(let iteration=0;iteration<$1;iteration++){').replace(/;\);/g,';}').replace(/^\s*\);$/gm,'}');
routeCode=routeCode.replace(/(matrix_source>0[^?]+)\? (MATRIX_TARGET\[matrix_destination\]\+=.*);/,'if($1){$2;}');
routeCode=routeCode.replace(/\bslider(\d+)\b/g,'slider($1)');
const sliders=new Float64Array(215),targets=new Float64Array(128),helpers=matrixHelpers(source);
for(const r of matrixRoutes){assert.equal(helpers.matrix_source_id(r.index),r.source);for(const id of [r.source,r.target,r.amount,r.polarity])assert.equal(helpers.matrix_route_index(id),r.index);}
for(const native of [0,1])for(const polarity of [0,1,2])for(const value of [0,.25,.5,1,-.5])for(const depth of [-1,0,.5,1])for(const enabled of [0,1])assert.equal(helpers.uc_matrix_convert(value,native,polarity,depth,enabled),convertSource(value,native,polarity,depth,enabled));
const routes=vm.createContext({MATRIX_TARGET:targets,slider:id=>sliders[id],floor:Math.floor,max:Math.max,min:Math.min,...helpers,fs_rand_value:.5,fs_shared_depth:1,ultra_motion:{visual_motion:.25},env_level:.75,env_sensitivity:1,env_depth:1,ultra_lfo2:{value:-.8,depth:1},ultra_adr:{output:.6},ultra_adr2:{output:.35}});
function reset(){sliders.fill(0);sliders[14]=sliders[131]=sliders[140]=1;sliders[45]=2;}
const router=new vm.Script(routeCode);
router.runInContext(routes);assert(targets.every(v=>v===0),'All sources Off must produce neutral destinations');
reset();for(const r of matrixRoutes){sliders[r.source]=4;sliders[r.target]=12;sliders[r.amount]=1;}
router.runInContext(routes);assert.equal(targets[12],-1,'Multiple LFO 2 routes must sum and clamp');
reset();sliders[89]=1;sliders[90]=14;sliders[91]=1;sliders[92]=4;sliders[93]=13;sliders[94]=-.5;
router.runInContext(routes);assert.equal(targets[14],.5);assert.equal(targets[13],.4);assert.equal(targets[12],0,'Removed routes must clear old modulation');
reset();for(const r of matrixRoutes){sliders[r.source]=4;sliders[r.target]=55+r.index;sliders[r.amount]=.5;}
router.runInContext(routes);for(let id=55;id<=70;id++)assert.equal(targets[id],-.4,'All extended targets must receive route sums without memory overlap');
reset();sliders[89]=5;sliders[90]=57;sliders[91]=.5;router.runInContext(routes);assert.equal(targets[57],.3,'ADR source must reach arbitrary assigned targets');
for(const r of matrixRoutes){reset();sliders[r.source]=5;sliders[r.target]=68;sliders[r.amount]=1;sliders[r.polarity]=2;routes.ultra_adr.output=.25;router.runInContext(routes);assert.equal(targets[68],-.5);sliders[140]=0;router.runInContext(routes);assert.equal(targets[68],0,'Off ADR must remain neutral in BI, avoiding a startup DC offset');}
for(const destination of [4,53,71,72,73,74,75,76,77,78])for(const polarity of [0,1,2]){reset();sliders[200]=2;sliders[89]=6;sliders[90]=destination;sliders[91]=.8;sliders[172]=polarity;router.runInContext(routes);assert(Math.abs(targets[destination]-convertSource(.35,0,polarity,1,true)*.8)<1e-10);sliders[200]=0;router.runInContext(routes);assert.equal(targets[destination],0,'ADR 2 Off must be neutral in all polarities');}
sliders.fill(0);router.runInContext(routes);for(let id=1;id<=78;id++)assert.equal(targets[id],0,'Removed routes must clear all destinations');
const packet=new Float32Array(32);packet[29]=.25;packet[30]=-.75;packet[31]=1;packet[26]=1;
assert.deepEqual(decodeTelemetry({data:packet})[7],{phase:.25,value:-.75,enabled:true});assert(decodeDoubler({data:packet}));
console.log('PASS: actual LFOs, 16 native route descriptors, polarity/depth/off safety, 78 destinations (two legacy slots) and 128-cell banks. Native host/audio checks remain separate.');
