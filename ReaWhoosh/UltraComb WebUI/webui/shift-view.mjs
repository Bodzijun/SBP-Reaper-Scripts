const clamp=(v,lo,hi)=>Math.max(lo,Math.min(hi,v));
const fraction=v=>v-Math.floor(v);
const speedFor=hz=>Math.abs(hz)>1e-6 ? .18+Math.log2(1+Math.abs(hz))*.09 : 0;
export class ShiftMotion{
 constructor(){this.time=null;this.phases=[0,0];this.flights=[0,0];}
 apply(model,time,motion=true){
  const elapsed=this.time===null?0:clamp(time-this.time,0,.1);this.time=time;
  model.channels.forEach((ch,i)=>{
   if(motion&&model.active){const speed=speedFor(ch.hz);this.phases[i]=fraction(this.phases[i]+elapsed*speed*Math.sign(ch.hz));this.flights[i]=fraction(this.flights[i]+elapsed*(.32+speed*.35));}
   ch.phase=this.phases[i];ch.partials.forEach((p,j)=>{if(p.travel!==null)p.travel=fraction(this.flights[i]+j*.137);});
  });
  model.phase=model.channels[0].phase;return model;
 }
}
export function shiftModel(width,height,{shift=0,offset=0,sideband=1,mix=1,sampleRate=48000,time=0,motion=true}={}){
 const rate=Math.max(8000,sampleRate),limit=Math.min(20000,rate*.45),hz=clamp(shift,-Math.min(5000,limit),Math.min(5000,limit));
 const stereoOffset=clamp(offset,-1000,1000),side=clamp(sideband,-1,1),wet=clamp(mix,0,1);
 const left=78,right=width-12,maximum=Math.min(12000,rate*.5),inputY=height*.28,outputY=height-27;
 const channelHz=[clamp(hz-stereoOffset,-limit,limit),clamp(hz+stereoOffset,-limit,limit)],stereo=Math.abs(channelHz[0]-channelHz[1])>1e-6;
 const active=channelHz.some(f=>Math.abs(f)>1e-6)&&wet>1e-6;
 const xFor=f=>left+clamp(f/maximum,0,1)*(right-left);
 const fold=f=>Math.abs(f-Math.floor((f+rate/2)/rate)*rate);
 const channels=channelHz.map((frequency,channel)=>{
  const speed=speedFor(frequency);
  const phase=fraction((motion&&active?time:0)*speed*Math.sign(frequency)),bypass=Math.abs(frequency)<=1e-6;
  const weights={main:bypass?0:wet*(1+side)/2,opposite:bypass?0:wet*(1-side)/2,dry:bypass?1:1-wet};
  const partials=Array.from({length:6},(_,i)=>{
   const input=(i+1)*Math.min(700,rate*.08),signedOutput=input+frequency,output=fold(signedOutput);
   return {input,output,opposite:fold(input-frequency),folded:signedOutput<0||signedOutput>rate/2,xInput:xFor(input),xOutput:xFor(output),amplitude:.82**i,
    travel:motion&&active&&weights.main+weights.opposite>1e-6?fraction(time*(.32+speed*.35)+i*.137):null};
  });
  return {hz:frequency,phase,weights,partials,y:stereo?(channel===0?height*.58:outputY):outputY,color:channel===0?'#f3ac69':'#dda1c3',label:stereo?channel===0?'L':'R':'L/R'};
 });
 return {hz,active,stereo,sideband:side,mix:wet,mode:wet<1e-6?'DRY':side>.999?'MAIN':side<-.999?'OPP':Math.abs(side)<.001?'RING':'BLEND',left,right,maximum,inputY,outputY,xFor,channels,partials:channels[0].partials,phase:channels[0].phase,rotor:{x:30,y:height*.55,radius:17}};
}
export function drawShift(c,width,height,settings,movement=null){
 const m=shiftModel(width,height,settings);if(movement)movement.apply(m,settings.time,settings.motion);
 const {inputY,outputY,left,right,rotor}=m;
 const shown=m.stereo?m.channels:[m.channels[0]];
 c.font='8px Arial';c.fillStyle='#afc4be';c.textAlign='left';c.fillText('IN',left-19,inputY+3);
 for(const [y,label]of [[inputY,''],...shown.map(ch=>[ch.y,ch.label])]){c.strokeStyle='#415b5b';c.lineWidth=.7;c.beginPath();c.moveTo(left,y);c.lineTo(right,y);c.stroke();if(label)c.fillText(label,left-23,y+3);}
 for(const f of [0,1,2,3,4].map(i=>i*m.maximum/4)){
  const x=m.xFor(f);c.strokeStyle='#304547';c.beginPath();c.moveTo(x,15);c.lineTo(x,outputY+3);c.stroke();
  c.fillStyle='#a3bbb5';c.textAlign=f===0?'left':f===m.maximum?'right':'center';c.fillText(f===0?'0 Hz':`${f/1000}k`,x,height-7);
 }
 for(const p of m.partials){c.strokeStyle='#63cbd1';c.lineWidth=1.7;c.beginPath();c.moveTo(p.xInput,inputY);c.lineTo(p.xInput,inputY-14*p.amplitude);c.stroke();}
 for(const channel of shown)for(const p of channel.partials)for(const [key,frequency]of [['dry',p.input],['main',p.output],['opposite',p.opposite]]){
  const weight=channel.weights[key];if(weight<.001)continue;
  const x=m.xFor(frequency),y=channel.y,color=key==='dry'?'#63cbd1':channel.color,tip=y-14*p.amplitude*weight,startY=inputY+3,endY=tip-2;
  c.globalAlpha=.2+.8*weight;c.strokeStyle=color;c.lineWidth=key==='opposite'?1:1.8;
  if(key==='opposite')c.setLineDash([2,2]);
  c.beginPath();c.moveTo(p.xInput,startY);c.lineTo(x,endY);c.stroke();c.setLineDash([]);
  c.beginPath();c.moveTo(x,y);c.lineTo(x,tip);c.stroke();c.fillStyle=color;c.beginPath();c.arc(x,tip,1.7,0,2*Math.PI);c.fill();
  if(key!=='dry'&&p.travel!==null){const t=p.travel;c.beginPath();c.arc(p.xInput+(x-p.xInput)*t,startY+(endY-startY)*t,1.2,0,2*Math.PI);c.fill();}
  c.globalAlpha=1;
 }
 c.strokeStyle=m.active?'#74968f':'#526c68';c.lineWidth=1;c.beginPath();c.arc(rotor.x,rotor.y,rotor.radius,0,2*Math.PI);c.stroke();
 for(const channel of shown){
  const angle=channel.phase*2*Math.PI,x=rotor.x+Math.cos(angle)*rotor.radius,y=rotor.y+Math.sin(angle)*rotor.radius*m.sideband;
  c.strokeStyle=channel.color;c.lineWidth=1;c.beginPath();c.moveTo(rotor.x,rotor.y);c.lineTo(x,y);c.stroke();c.fillStyle=m.active?channel.color:'#63cbd1';c.beginPath();c.arc(x,y,2.6,0,2*Math.PI);c.fill();
 }
 c.font='8px Arial';c.fillStyle='#afc4be';c.textAlign='center';c.fillText(m.mode,rotor.x,rotor.y+rotor.radius+12);c.fillText('SCALED',rotor.x,rotor.y-rotor.radius-9);c.textAlign='left';
 return m;
}
