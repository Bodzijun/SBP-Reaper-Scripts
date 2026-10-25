import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import {createAdr} from './envelope-fixture.mjs';
const source=fs.readFileSync(new URL('../sbp_ultraComb_webui.jsfx',import.meta.url),'utf8');
const noteStart=source.indexOf('function uc_adr_midi_note('),noteRaw=source.slice(noteStart,source.indexOf('\n);',noteStart)),noteBody=noteRaw.slice(noteRaw.lastIndexOf('\n(')+2).trim().replace(/;$/,'').replace(/\$x/g,'0x');
const note=new Function('status','velocity','return '+noteBody);
for(let channel=0;channel<16;channel++)for(const velocity of [0,1,64,127]){assert.equal(+note(0x90+channel,velocity),+(velocity>0));assert.equal(+note(0x80+channel,velocity),0);assert.equal(+note(0xB0+channel,velocity),0);}
function section(start,end){return source.slice(source.indexOf(start)+start.length,source.indexOf(end)).replace(/\/\/[^\n]*/g,'').replace(/ADR_MIDI\[([^\]]+)\]/g,'ram[ADR_MIDI+($1)]');}
const capture=section('// ADR MIDI capture:','// End ADR MIDI capture.');
// The marker contains explanatory text up to the first line break.
const blockCode=capture.slice(capture.indexOf('\n')).replace(/while\(midirecv\([^)]*\)\) \(/,'while(midirecv()) {').replace(/^(\s*)([^\n?]+) \? \(/gm,'$1if($2){').replace(/^\s*\);\s*$/gm,'}');
const sample=section('// ADR MIDI sample:','// End ADR MIDI sample.');
const sampleCode=sample.slice(sample.indexOf('\n')).replace(/^(\s*)(adr_midi_position<adr_midi_span) \? \(/gm,'$1if($2){').replace(/^(\s*)(slider(?:140|200)==4[^\n?]+) \? atomic_add\((ui_adr2?_fire),([^;]+)\);/gm,'$1if($2){$3+=$4;}').replace(/^\s*\);\s*$/gm,'}');
const block=new vm.Script(blockCode),tick=new vm.Script(sampleCode);
function setup(mode=4,mode2=0){
 const ram=new Float64Array(512),forwarded=[];let events=[],i=0;
 const c=vm.createContext({ram,ADR_MIDI:0,slider140:mode,slider200:mode2,slider113:1,samplesblock:64,ui_adr_fire:0,ui_adr2_fire:0,max:Math.max,min:Math.min,floor:Math.floor,uc_adr_midi_note:note,memset:(p,v,n)=>ram.fill(v,p,p+n),
  midirecv(){const e=events[i++];if(!e)return 0;[c.adr_midi_offset,c.adr_midi_msg1,c.adr_midi_msg2,c.adr_midi_msg3,c.midi_bus]=e;return 1;},
  midisend(offset,status,data1,data2){forwarded.push([offset,status,data1,data2,c.midi_bus]);}});
 const adr=createAdr(source,48000,{mode,attack:5,decay:10,level:.4,release:15}),adr2=createAdr(source,48000,{mode:mode2,attack:30,decay:20,level:.7,release:50});
 return {c,ram,forwarded,adr,adr2,block(next=[]){events=next;i=0;block.runInContext(c);},step(){tick.runInContext(c);adr.p.trigger=c.ui_adr_fire;adr2.p.trigger=c.ui_adr2_fire;adr2.step();return adr.step();}};
}
const events=[[0,0xB0,1,64,0],[10,0x90,60,100,0],[10,0x9F,72,70,15],[20,0x90,60,0,0],[30,0x80,72,0,15],[40,0x95,65,100,3],[50,0xC0,2,0,1]];
const test=setup();test.block(events);assert.deepEqual(test.forwarded,events,'MIDI must preserve offsets, data and buses, including Note Off and non-note messages');
let before=0;
for(let n=0;n<64;n++){const value=test.step();assert.equal(test.c.ui_adr_fire,n<10?0:n<40?2:3,'Note On must trigger at its sample offset, not the block boundary');if(n===40)assert.equal(value,before,'Note retrigger must start at the current level');before=value;}
for(let b=0;b<30;b++){test.block();for(let n=0;n<64;n++)test.step();}
assert.equal(test.c.ui_adr_fire,3);assert.equal(test.adr.c.stage,0);assert.equal(test.adr.c.output,0,'Held notes must not loop or hold the one-shot ADR');
const manual=setup(2);manual.block(events);for(let n=0;n<64;n++)assert.equal(manual.step(),0,'Manual mode must ignore incoming notes');assert.equal(manual.c.ui_adr_fire,0);manual.c.ui_adr_fire++;manual.step();assert.equal(manual.adr.c.stage,1,'Manual button counter must still work');
const disabled=setup();disabled.c.slider113=0;disabled.block(events);for(let n=0;n<64;n++)disabled.step();assert.equal(disabled.c.ui_adr_fire,0,'No MIDI triggers may queue while matrix routing is off');
const edge=setup();edge.block([[0,0x90,60,100,0],[63,0x90,62,100,0]]);for(let n=0;n<64;n++){edge.step();assert.equal(edge.c.ui_adr_fire,n===63?2:1);}edge.block();for(let n=0;n<64;n++)edge.step();assert.equal(edge.c.ui_adr_fire,2,'Block-edge notes must not replay from stale event bins');
for(const [mode,mode2]of [[4,4],[2,4],[4,2],[0,4]]){const dual=setup(mode,mode2);dual.block(events);for(let n=0;n<64;n++){dual.step();const count=n<10?0:n<40?2:3;assert.equal(dual.c.ui_adr_fire,mode===4?count:0);assert.equal(dual.c.ui_adr2_fire,mode2===4?count:0);}assert.deepEqual(dual.forwarded,events);if(mode===4&&mode2===4)assert.notEqual(dual.adr.c.output,dual.adr2.c.output,'Independent ADR timings must produce independent trajectories');}
assert(source.includes('ext_midi_bus=1;'));assert(!source.includes('midirecv_buf('),'Short-message receive retains REAPER automatic SysEx passthrough');
console.log('PASS: actual MIDI block/sample code, 16 channels, Note On one-shots, chords, exact offsets, continuous retrigger, no held-note repeat, Manual isolation, bus/data passthrough and disabled routing. Native MIDI hardware acceptance remains separate.');
