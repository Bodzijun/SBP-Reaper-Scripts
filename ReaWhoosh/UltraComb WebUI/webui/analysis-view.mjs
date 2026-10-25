import {Spectrogram} from './spectrogram.mjs';
const clamp=(v,a,b)=>Math.max(a,Math.min(b,v));
export const analysisModes=['spectrogram','spectrum','stereo'];
export const analysisStreamId=(side,mode)=>mode==='stereo'?side+'Stereo':side;
export function stereoStats(data,channels=2){
 if(channels!==2||!data||data.length<4||data.length%2)return null;
 let left=0,right=0,cross=0,peak=0,count=data.length/2;
 for(let i=0;i<data.length;i+=2){const l=data[i],r=data[i+1];if(!Number.isFinite(l)||!Number.isFinite(r))return null;left+=l*l;right+=r*r;cross+=l*r;peak=Math.max(peak,Math.hypot(l,r));}
 left/=count;right/=count;cross/=count;
 const correlation=left>1e-12&&right>1e-12?clamp(cross/Math.sqrt(left*right),-1,1):null;
 return {left,right,cross,peak,correlation,silent:left+right<1e-10};
}
export function spectrumBands(data,{channels=2,sampleRate},columns=256){
 channels=Number(channels);const bins=Math.floor((data?.length||0)/channels),rate=Number(sampleRate);if(!data||channels!==2||bins<16||!Number.isFinite(rate)||rate<8000)return null;
 const high=Math.min(20000,rate/2),left=[],right=[],db=v=>20*Math.log10(Math.max(1e-6,Math.abs(v))),raw=[[],[]],ratio=high/20,binHz=rate/2/(bins-1);
 for(let i=0;i<bins;i++)for(let channel=0;channel<2;channel++){const value=data[i*2+channel];if(!Number.isFinite(value))return null;raw[channel].push(db(value));}
 // Monotone Hermite interpolation joins FFT samples smoothly without overshoot.
 const sample=(values,bin)=>{
  const b=clamp(bin,0,bins-1),i=Math.min(bins-2,Math.floor(b)),t=b-i,y0=values[i],y1=values[i+1],before=y0-values[Math.max(0,i-1)],slope=y1-y0,after=values[Math.min(bins-1,i+2)]-y1;
  const m0=before*slope>0?2*before*slope/(before+slope):0,m1=slope*after>0?2*slope*after/(slope+after):0;
  return clamp((2*t*t*t-3*t*t+1)*y0+(t*t*t-2*t*t+t)*m0+(-2*t*t*t+3*t*t)*y1+(t*t*t-t*t)*m1,Math.min(y0,y1),Math.max(y0,y1));
 };
 const positions=Array.from({length:columns},(_,i)=>i/(columns-1));
 // Resolved bin centres remain exact anchors, preserving narrow low-end peaks.
 for(let i=1;i<bins;i++){const hz=i*binHz;if(hz<20||hz>high)continue;if((Math.log((i+1)/i)/Math.log(ratio))*(columns-1)>=1)positions.push(Math.log(hz/20)/Math.log(ratio));}
 const xs=[...new Set(positions)].sort((a,b)=>a-b);
 for(const x of xs){
  const bin=20*ratio**x/binHz,lo=clamp(20*ratio**(x-.5/(columns-1))/binHz,0,bins-1),hi=clamp(20*ratio**(x+.5/(columns-1))/binHz,0,bins-1),span=hi-lo;
  const t=clamp((span-.5)/.5,0,1),blend=t*t*(3-2*t);
  for(let channel=0;channel<2;channel++){const values=raw[channel],center=sample(values,bin);let peak=Math.max(sample(values,lo),sample(values,hi));for(let i=Math.ceil(lo);i<=Math.floor(hi);i++)peak=Math.max(peak,values[i]);(channel?right:left).push(center+(peak-center)*blend);}
 }
 return {left,right,high,positions:xs};
}
export function stereoPoint(left,right){return {side:(right-left)/Math.SQRT2,mid:(left+right)/Math.SQRT2};}
export class AudioAnalysis{
 constructor(canvas,status,mode='spectrogram'){
  this.canvas=canvas;this.status=status;this.spectrogram=new Spectrogram(canvas,status);this.mode=analysisModes.includes(mode)?mode:'spectrogram';this.lastSequence=null;this.epoch=null;this.lastTime=null;this.traces=[];this.smooth=null;this.spectrum=null;this.clear();
 }
 get seconds(){return this.spectrogram.seconds;}set seconds(v){this.spectrogram.seconds=v;}
 get palette(){return this.spectrogram.palette;}set palette(v){this.spectrogram.palette=v;}
 get paused(){return this.spectrogram.paused;}set paused(v){this.spectrogram.paused=v;}
 setMode(mode){if(!analysisModes.includes(mode))return;this.mode=mode;this.clear();}
 clear(){this.spectrogram.clear();this.lastSequence=null;this.epoch=null;this.lastTime=null;this.traces=[];this.smooth=null;this.spectrum=null;delete this.canvas.dataset.correlation;this.canvas.dataset.analysisMode=this.mode;if(this.mode!=='spectrogram'){this.canvas.width=Math.max(1,Math.round(this.canvas.clientWidth||360));this.canvas.height=Math.max(1,Math.round(this.canvas.clientHeight||135));this.paint();}}
 paint(){
  const c=this.canvas,ctx=c.getContext('2d'),w=c.width,h=c.height;ctx.fillStyle='#111c20';ctx.fillRect(0,0,w,h);ctx.font='9px Arial';
  if(this.mode==='stereo')this.paintStereo(ctx,w,h);else this.paintSpectrum(ctx,w,h);
 }
 accept(packet,info,kind='spectrum'){
  if(this.paused||kind!==(this.mode==='stereo'?'pcm':'spectrum'))return;
  if(this.mode==='spectrogram'){this.spectrogram.accept(packet,info);return;}
  if(packet.sequence!==undefined&&packet.sequence===this.lastSequence)return;
  const rate=Number(info.sampleRate);if(!Number.isFinite(rate)||rate<8000){this.status.textContent='INVALID STREAM';return;}
  const epoch=packet.timing?.clockEpoch;if(packet.timing?.discontinuity||epoch!==undefined&&this.epoch!==null&&epoch!==this.epoch)this.clear();this.epoch=epoch??this.epoch;
  const sample=Number(packet.timing?.firstSample??packet.firstSample),time=Number.isFinite(sample)?sample/rate:performance.now()/1000;
  if(this.lastTime!==null&&(time<this.lastTime||time-this.lastTime>1))this.clear();
  const dt=this.lastTime===null?1/30:clamp(time-this.lastTime,1/120,.5);this.lastTime=time;this.lastSequence=packet.sequence??null;
  if(this.mode==='spectrum'){
   const bands=spectrumBands(packet.data,info);if(!bands){this.status.textContent='INVALID STREAM';return;}
   if(this.spectrum&&this.spectrum.left.length===bands.left.length)for(const key of ['left','right'])for(let i=0;i<bands[key].length;i++){const old=this.spectrum[key][i],value=bands[key][i],weight=1-Math.exp(-dt/(value>old ? .025 : .18));bands[key][i]=old+(value-old)*weight;}
   this.spectrum=bands;
  }else{
   const stats=stereoStats(packet.data,Number(info.channels));if(!stats){this.status.textContent='INVALID PCM';return;}
   const weight=1-Math.exp(-dt/.25);if(!this.smooth)this.smooth={...stats};else for(const key of ['left','right','cross'])this.smooth[key]+=(stats[key]-this.smooth[key])*weight;
   const s=this.smooth;s.correlation=s.left>1e-12&&s.right>1e-12?clamp(s.cross/Math.sqrt(s.left*s.right),-1,1):null;s.silent=stats.silent;s.peak=stats.peak;
   if(stats.silent)this.traces=[];else{const points=[];for(let i=0;i<packet.data.length;i+=4)points.push(stereoPoint(packet.data[i],packet.data[i+1]));this.traces.push({points,peak:stats.peak});if(this.traces.length>5)this.traces.shift();}
   this.canvas.dataset.correlation=s.silent||s.correlation===null?'none':s.correlation.toFixed(4);
  }
  this.paint();this.status.textContent=`LIVE · ${Math.round(rate/100)/10} kHz`;
 }
 paintSpectrum(ctx,w,h){
  const top=12,bottom=h-16,y=db=>bottom-(clamp(db,-90,6)+90)/96*(bottom-top),x=i=>this.spectrum.positions[i]*w;
  ctx.lineWidth=.5;ctx.strokeStyle='#314547';ctx.fillStyle='#91a8a8';
  for(const db of [0,-30,-60,-90]){ctx.beginPath();ctx.moveTo(0,y(db));ctx.lineTo(w,y(db));ctx.stroke();ctx.fillText(`${db}`,4,y(db)-2);}
  const high=this.spectrum?.high||20000;for(const hz of [100,1000,10000])if(hz<high){const px=Math.log(hz/20)/Math.log(high/20)*w;ctx.beginPath();ctx.moveTo(px,top);ctx.lineTo(px,bottom);ctx.stroke();}
  if(this.spectrum)for(const [key,color]of [['left','#65d3c3'],['right','#f5ad70']]){
   ctx.beginPath();this.spectrum[key].forEach((db,i)=>i?ctx.lineTo(x(i),y(db)):ctx.moveTo(x(i),y(db)));ctx.strokeStyle=color;ctx.lineWidth=1.4;ctx.stroke();
  }
  ctx.fillStyle='#65d3c3';ctx.fillText('L',w-30,10);ctx.fillStyle='#f5ad70';ctx.fillText('R',w-14,10);
 }
 paintStereo(ctx,w,h){
  const radius=Math.min(w*.42,(h-46)*.5),cx=w/2,cy=12+radius,stats=this.smooth;
  ctx.lineWidth=.7;ctx.strokeStyle='#3c5657';ctx.beginPath();ctx.arc(cx,cy,radius,0,Math.PI*2);ctx.moveTo(cx-radius,cy);ctx.lineTo(cx+radius,cy);ctx.moveTo(cx,cy-radius);ctx.lineTo(cx,cy+radius);ctx.stroke();
  ctx.fillStyle='#91a8a8';ctx.fillText('L',cx-radius-11,cy);ctx.fillText('R',cx+radius+5,cy);ctx.fillText('MONO',cx-14,cy+radius+11);
  const peak=Math.max(.05,...this.traces.map(t=>t.peak)),gain=.88*radius/peak;
  this.traces.forEach((trace,i)=>{ctx.strokeStyle=`rgba(101,211,195,${.14+.7*(i+1)/this.traces.length})`;ctx.lineWidth=.8;ctx.beginPath();trace.points.forEach((p,n)=>{const x=cx+p.side*gain,y=cy-p.mid*gain;n?ctx.lineTo(x,y):ctx.moveTo(x,y);});ctx.stroke();});
  const left=16,right=w-16,bar=h-17;ctx.fillStyle='#253c3c';ctx.fillRect(left,bar,right-left,5);
  const correlation=stats&&!stats.silent?stats.correlation:null;if(correlation!==null){const x=left+(correlation+1)/2*(right-left);ctx.fillStyle=correlation<0?'#f19769':'#65d3c3';ctx.fillRect(x-2,bar-2,4,9);}
  ctx.fillStyle='#91a8a8';ctx.fillText('−1',left,h-2);ctx.fillText('0',w/2-3,h-2);ctx.fillText('+1',right-10,h-2);ctx.fillText('CORR '+(correlation===null?'—':(correlation>=0?'+':'')+correlation.toFixed(2)),6,11);
 }
}
