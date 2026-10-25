import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {combGeometry,combWavePoints,CORE_DELAY_MAX_MS} from '../webui/core-view.mjs';
import {arithmeticBody,eelModulo} from './eel-arithmetic.mjs';
const source=fs.readFileSync(new URL('../sbp_ultraComb_webui.jsfx',import.meta.url),'utf8');
assert.equal(CORE_DELAY_MAX_MS,200);
for(const [width,height]of [[250,110],[340,110],[475,140],[600,140]]){
 const original=combGeometry(width,height,0,3),long=combGeometry(width,height,200,200);
 assert.equal(original.rows[0].x,original.left);assert.equal(long.rows[0].x,long.right);assert.equal(long.rows[1].x,long.right);
 assert.deepEqual(original.ticks.map(t=>t.ms),[0,50,100,150,200]);
 assert.deepEqual(combGeometry(width,height,0,3),original,'Returning delay must restore the exact geometry');
 for(const delay of [0,3,50,100,199.9,200]){
  const model=combGeometry(width,height,delay,delay),wave=combWavePoints(model,model.rows[1],0,.95,1);
  assert.equal(wave[0][0],model.rows[1].x);assert.equal(wave[0][1],model.rows[1].y);
  assert(wave.every(([x,y])=>x>=model.rows[1].x&&x<=model.right&&y>0&&y<model.axis),'Wave must remain after its delay marker and above the time axis');
  if(delay<200)assert.notDeepEqual(wave,combWavePoints(model,model.rows[1],1,.95,1),'Schematic must animate without changing delay geometry');
 }
}
// Evaluate actual allocation expressions, including the full dependency chain.
const names=['PITCH_BUFFER','PITCH_BUF_SIZE','DOUBLE_PITCH_SIZE','DOUBLE_BUFFER','FREEZE_BUFFER','FREEZE_SIZE','DOUBLE_WIDTH_BUFFER','DOUBLE_WIDTH_SIZE','SPECTRAL_BUFFER','WEB_MEMORY','WEB_INPUT','WEB_OUTPUT','WEB_REPLY','WEB_MOD','MATRIX','MATRIX_TARGET','VIS_IDS','VIS_LOW','VIS_HIGH','VIS_SCALE','VIS_KIND','CHORUS_MEMORY','CHORUS_SIZE','COMB_MEMORY','BUF_SIZE','BUF_L_START','BUF_R_START','FILTER_MEMORY','FILTER_SIZE','ADR_MIDI'];
const globalAllocations=source.split('\n').filter(line=>/^[A-Z_]+\s*=/.test(line)).join('\n');
const allocation=new vm.Script(names.map(name=>{const expression=globalAllocations.match(new RegExp('\\b'+name+'\\s*=([^;]+);'))?.[1];assert(expression,`Missing ${name} allocation`);return `${name}=${expression};`;}).join('\n'));
const init=arithmeticBody(source,'uc_comb_feed_init'),process=arithmeticBody(source,'uc_comb_feed_process'),read=arithmeticBody(source,'uc_comb_history_read_smooth_channel');
for(const rate of [44100,48000,96000,192000,384000,768000]){
 const c=vm.createContext({srate:rate,rate,max:Math.max,min:Math.min,ceil:Math.ceil,exp:Math.exp,floor:Math.floor,eelModulo});allocation.runInContext(c);
 const delay=rate*.2;assert(c.BUF_SIZE>=delay+4);assert(c.BUF_R_START>=c.BUF_L_START+c.BUF_SIZE);
 assert(c.DOUBLE_BUFFER+2*c.DOUBLE_PITCH_SIZE<=c.FREEZE_BUFFER-64,'Both independent Doubler pitch histories must fit the reserved bank');
 assert.equal(c.MATRIX_TARGET-c.MATRIX,128);assert(c.CHORUS_MEMORY>=c.MATRIX_TARGET+128,'Extended matrix destinations must not overlap the Chorus memory');
 assert(c.MATRIX>=c.WEB_MOD+542);assert(c.VIS_IDS>=c.MATRIX_TARGET+128);assert(c.CHORUS_MEMORY>=c.VIS_KIND+128,'Display feedback tables must not overlap either matrix bank or Chorus');
 assert(c.BUF_L_START>=c.CHORUS_MEMORY+c.CHORUS_SIZE*2+64);assert(c.BUF_R_START+c.BUF_SIZE<8388608);
 assert(c.FILTER_MEMORY>=c.BUF_R_START+c.BUF_SIZE+64);assert(c.FILTER_SIZE>=rate/20+4);assert(c.FILTER_MEMORY+c.FILTER_SIZE*2<8388608,'Filter Comb history must fit after every existing audio/SDK bank');
 assert(c.ADR_MIDI>=c.FILTER_MEMORY+c.FILTER_SIZE*2+64);assert(c.ADR_MIDI+65536<8388608,'MIDI event bins must fit after every audio/SDK bank');
 c.initial_delay=delay;init.runInContext(c);c.target=delay;assert.equal(process.runInContext(c),delay,'A 200 ms preset must initialize at its real delay');
 c.target=rate*.003;for(let i=0;i<1000;i++){const value=process.runInContext(c);assert(Number.isFinite(value)&&value>=rate*.003&&value<=delay);}
 Object.assign(c,{memory:new Float64Array(c.BUF_SIZE),size:c.BUF_SIZE,position:Math.round(delay),delay});c.memory[0]=1;
 assert(Math.abs(read.runInContext(c)-1)<1e-9,'200 ms impulse must read exactly, without clipping to the old range');
}
assert(source.includes('min(200,slider4+'));assert(source.includes('min(200,slider5+'));
console.log('PASS: 0–200 ms Comb model, reversible marker geometry, bounded schematic motion, actual native memory allocations and 200 ms reads at 44.1/48/96/192/384/768 kHz. Native host/audio acceptance remains separate.');
