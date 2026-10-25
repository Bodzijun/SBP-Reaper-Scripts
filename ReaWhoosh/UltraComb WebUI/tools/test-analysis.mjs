import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import {stereoStats,stereoPoint,spectrumBands,analysisStreamId} from '../webui/analysis-view.mjs';
import {toPosition,fromPosition} from '../webui/model.mjs';
const registry=JSON.parse(fs.readFileSync(new URL('../webui/parameters.json',import.meta.url),'utf8')),shift=registry.parameters.find(p=>p.id===12);
for(const mode of ['linear','fine'])for(const value of [-5000,-1234.5,-10,0,10,1234.5,5000])assert(Math.abs(fromPosition(shift,toPosition(shift,value,mode),mode)-value)<.00001);
assert.equal(fromPosition(shift,.25),-2500);assert.equal(fromPosition(shift,.75),2500);assert.equal(fromPosition(shift,.75,'fine'),625);assert.equal(toPosition(shift,0),.5);
for(let i=1;i<20;i++)assert(Math.abs(fromPosition(shift,i/20)-fromPosition(shift,(i-1)/20)-500)<1e-8,'Linear mode must move by uniform Hz');
function signal(right){return Float32Array.from({length:2048},(_,i)=>{const n=Math.floor(i/2);return i%2?right(n):.5*Math.sin(2*Math.PI*n/64);});}
const mono=signal(n=>.5*Math.sin(2*Math.PI*n/64)),anti=signal(n=>-.5*Math.sin(2*Math.PI*n/64)),quadrature=signal(n=>.5*Math.cos(2*Math.PI*n/64));
assert(Math.abs(stereoStats(mono).correlation-1)<1e-12);assert(Math.abs(stereoStats(anti).correlation+1)<1e-12);assert(Math.abs(stereoStats(quadrature).correlation)<1e-10);
assert.equal(stereoStats(signal(()=>0)).correlation,null);assert.equal(stereoStats(new Float32Array(1024)).correlation,null);assert(stereoStats(new Float32Array(1024)).silent);assert.equal(stereoStats([NaN,0,0,0]),null);
for(let i=0;i<mono.length;i+=2){assert.equal(stereoPoint(mono[i],mono[i+1]).side,0);assert.equal(stereoPoint(anti[i],anti[i+1]).mid,0);}
const fft=new Float32Array(2050);fft[2*43]=.5;fft[2*86+1]=.25;
const bands=spectrumBands(fft,{channels:2,sampleRate:48000});assert(bands.left.every(Number.isFinite));assert(Math.abs(Math.max(...bands.left)+6.0206)<1e-4);assert(Math.abs(Math.max(...bands.right)+12.0412)<1e-4);assert.notDeepEqual(bands.left,bands.right);assert.equal(spectrumBands(fft,{channels:1,sampleRate:48000}),null);
// Low FFT bins must interpolate continuously, instead of repeating max-bin steps.
const descending=Float32Array.from({length:2050},(_,i)=>10**(-3*Math.floor(i/2)/20)),smooth=spectrumBands(descending,{channels:2,sampleRate:48000});
const low=smooth.positions.map((x,i)=>({hz:20*1000**x,db:smooth.left[i]})).filter(p=>p.hz>=30&&p.hz<=200);
assert(low.length>30);for(let i=1;i<low.length;i++)assert(low[i].db<low[i-1].db-1e-8,'Resolved low-end ramp must not produce horizontal stair steps');
for(let bin=2;bin<=8;bin++){const hz=bin*48000/2/1024,index=smooth.positions.findIndex(x=>Math.abs(20*1000**x-hz)<1e-8);assert(index>=0);assert(Math.abs(smooth.left[index]+3*bin)<1e-5,'Resolved FFT bin anchors must keep their exact measured levels');}
assert(smooth.left.every(v=>v<=0&&v>=-120),'Monotone interpolation must not overshoot the input bounds');
assert.equal(analysisStreamId('input','spectrogram'),'input');assert.equal(analysisStreamId('output','spectrum'),'output');assert.equal(analysisStreamId('input','stereo'),'inputStereo');
// Execute the actual native capture/publish statements to verify PCM phase and
// channel ordering; source/spectrum streams share raw capture but not UI parsing.
const source=fs.readFileSync(new URL('../sbp_ultraComb_webui.jsfx',import.meta.url),'utf8'),at=source.indexOf('@sample');
const begin=source.indexOf('web_capture ? (',at),input=source.slice(begin,source.indexOf('\n);',begin)+4);
const end=source.lastIndexOf('web_capture ? (',source.indexOf('@serialize')),output=source.slice(end,source.indexOf('web_sample_clock+=1;',end));
function translate(code){return code.replace(/^(\s*)(web_capture|web_capture_pos>=512) \? \(/gm,'$1if($2){').replace(/^\s*\);\s*$/gm,'}').replace(/WEB_(INPUT|OUTPUT)\[([^\]]+)\]/g,'ram[WEB_$1+($2)]');}
const inputCode=new vm.Script(translate(input)),outputCode=new vm.Script(translate(output));
const captureLine=source.split('\n').find(l=>l.startsWith('web_capture=reaweb_jsfx_stream_active(')),capture=new vm.Script(captureLine),ram=new Float64Array(2048),packets=[];
let mask=0;const c=vm.createContext({ram,WEB_INPUT:0,WEB_OUTPUT:1024,web_capture_pos:0,web_sample_clock:0,reaweb_jsfx_stream_active:id=>mask&(2**id),reaweb_jsfx_publish(id,p,length,channels,first){if(mask&(2**id))packets.push({id,channels,first,data:Float32Array.from(ram.slice(p,p+length))});}});
for(const selected of [3,4,0,1]){mask=2**selected;packets.length=0;c.web_capture_pos=0;capture.runInContext(c);assert(c.web_capture);
 for(let n=0;n<1024;n++){const value=.5*Math.sin(2*Math.PI*n/64);Object.assign(c,{spl0:value,spl1:value,web_sample_clock:n});inputCode.runInContext(c);c.spl1=-value;outputCode.runInContext(c);}
 assert.equal(packets.length,2);assert.deepEqual(packets.map(p=>p.first),[0,512]);assert(packets.every(p=>p.id===selected&&p.channels===2&&p.data.length===1024));assert(Math.abs(stereoStats(packets[0].data).correlation-(selected===0||selected===3?1:-1))<1e-12);
}
mask=0;capture.runInContext(c);assert.equal(c.web_capture,0,'Closed analysis streams must disable audio capture');
const streams=JSON.parse(fs.readFileSync(new URL('../sbp_ultraComb_webui.json',import.meta.url),'utf8')).JSFX_WebUI.native.streams;assert.equal(streams.length,5);assert(streams.slice(3).every(s=>s.kind==='audio'&&s.channels===2));
console.log('PASS: Linear/Fine Shift inverse/spacing, real PCM mono/antiphase/decorrelation, spectrum levels, native input/output PCM capture, inactive gating and preserved channel/timestamp ordering. Native host acceptance remains separate.');
