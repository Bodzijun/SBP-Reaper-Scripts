import fs from 'node:fs';
import assert from 'node:assert/strict';
import {syncFunctions} from './tempo-fixture.mjs';
import {divisions,divisionBeats,divisionValue,divisionPosition,divisionFromPosition,syncValuePosition} from '../webui/tempo-sync.mjs';
import {createAdr} from './envelope-fixture.mjs';
import {adrValue,envelopeModel} from '../webui/envelope-view.mjs';
const source=fs.readFileSync(new URL('../sbp_ultraComb_webui.jsfx',import.meta.url),'utf8'),h=syncFunctions(source);
const near=(a,b)=>assert(Math.abs(a-b)<1e-9,`${a} != ${b}`);
assert.equal(divisions.length,22);
for(const tempo of [30,60,120,180,300])for(const [num,den]of [[4,4],[3,4],[7,8]])for(let i=0;i<22;i++){
 const clock={tempo,num,den},bars=num*4/den;near(h.uc_sync_beats(i,bars),divisionBeats(i,clock));near(h.uc_sync_rate(i,tempo,bars),divisionValue(195,i,clock));near(h.uc_sync_ms(i,tempo,bars),divisionValue(197,i,clock));
 for(const id of [195,196,197,198,199]){near(divisionFromPosition(id,divisionPosition(id,i,clock),clock),i);assert(Number.isFinite(syncValuePosition(id,divisionValue(id,i,clock),clock)));}
}
function state(sr,rate=.35){return {sr,phase:0,offset:0,rate_hz:rate,depth:1,value:0,output:0,effective_phase:0,previous_phase:0,active:0,random_value:0,uc_matrix_lfo_process:h.uc_matrix_lfo_process};}
// Use the actual native processing body and wrapper. Free must remain bit-identical.
const old=h.uc_matrix_lfo_process;
const originalRand=globalThis.rand;globalThis.rand=n=>n*.7;
for(const sr of [44100,48000,96000]){
 const a=state(sr),b=state(sr);
 for(let tick=0;tick<1000;tick++){const mod=Math.sin(tick*.02),rate=Math.max(.02,Math.min(12,.35*2**(mod*4)));old.call(a,1,rate,75,90,0,32);h.uc_matrix_lfo_timing.call(b,1,.35,75,90,0,32,0,18,mod,120,4,0,1);assert.deepEqual(a,b);}
 for(const [bpm,bars,division]of [[120,4,18],[60,3,21],[180,3.5,0]])for(const beat of [0,.25,5.75,100,-2]){
  const s=state(sr),period=h.uc_sync_beats(division,bars);h.uc_matrix_lfo_timing.call(s,1,.35,100,0,0,32,1,division,0,bpm,bars,beat,1);near(s.phase,(beat/period-Math.floor(beat/period)+1)%1);
 }
 const s=state(sr);for(let i=0;i<2000;i++){h.uc_matrix_lfo_timing.call(s,1,.35,100,0,0,32,1,0,Math.sin(i*.01),300,4,i*32/sr*5,1);assert(Number.isFinite(s.output)&&Math.abs(s.output)<=1.000001);assert(s.phase>=0&&s.phase<1&&s.rate_hz<=512);}
}
globalThis.rand=originalRand;
const duration=h.uc_sync_ms(21,30,4);assert.equal(duration,64000);
const adr=createAdr(source,1000,{mode:2,attack:duration,decay:duration,level:.5,release:duration});adr.step();adr.p.trigger++;
for(let i=0;i<64000;i++)adr.step();assert(Math.abs(adr.c.output-1)<.001);near(adrValue(32000,{attack:duration,decay:duration,release:duration,sync:true}),.5);assert.equal(envelopeModel(350,140,{kind:'adr',sync:true,attack:duration,decay:duration,release:duration,level:.5}).total,192000);
assert(source.includes('sync_bpm=tempo>0 ? tempo : 120;'));assert(source.includes('sync_beat=beat_position;'));assert(source.includes('sync_bars=sync_num*4/sync_den;'));
console.log('PASS: actual tempo helpers/wrapper, 22 divisions, 30–300 BPM, 4/4–3/4–7/8, Free identity, transport seek/negative beat phase lock, cross-modulation bounds and 64-second ADR segments. Native host acceptance remains separate.');
