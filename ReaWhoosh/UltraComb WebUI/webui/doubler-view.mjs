const clamp=(value,lo,hi)=>Math.max(lo,Math.min(hi,value));
export function decodeDoubler(packet){
 const data=packet.data;if(![29,32].includes(data?.length)||!Array.from(data).every(Number.isFinite))return null;
 return {delayL:clamp(data[21],0,300),delayR:clamp(data[22],0,300),semi:clamp(data[23],-24.8,24.8),mix:clamp(data[24],0,1),width:clamp(data[25],0,1),gain:clamp(data[26],0,4),polarity:clamp(data[27],-1,1),controlDelay:clamp(data[28],0,100)};
}
export function currentDoublerTelemetry(telemetry,delay,now,editing=false){
 if(editing||!telemetry||!Number.isFinite(telemetry.state.controlDelay)||now-telemetry.received>=500||Math.abs(telemetry.state.controlDelay-delay)>.2)return null;
 return telemetry.state;
}
export class DoublerMotion{
 constructor(){this.state=null;this.time=null;this.delay=null;}
 sample(target,now,delay){
  const elapsed=this.time===null?0:now-this.time;
  if(!this.state||elapsed>500||this.delay!==delay)this.state={...target};
  else{
   const blend=1-Math.exp(-Math.max(0,elapsed)/100),previous=this.state;
   this.state={...target};
   for(const key of ['delayL','delayR','width','voiceGain','dryGain','pitchRadius'])this.state[key]=previous[key]+(target[key]-previous[key])*blend;
  }
  this.time=now;this.delay=delay;return this.state;
 }
}
export function doublerModel(p,live=null){
 const semi=clamp(live?.semi??p.pitch+p.detune/100,-24.8,24.8),width=clamp(p.width,0,1),delay=clamp(p.delay,0,100);
 const mix=p.enabled?clamp(live?.mix??p.mix,0,1):0;
 const state={delayL:delay,delayR:delay,semi,mix,width,gain:live?.gain??10**(clamp(p.gain,-12,12)/20),polarity:live?.polarity??(p.invert?-1:1)};
 const normalization=1/Math.sqrt(1+state.mix**2);
 return {...state,live:!!live,pitchRadius:clamp(5*2**(semi/24),2.4,10.5),dryGain:normalization,voiceGain:state.mix*state.gain*normalization,lowCut:p.lowCut,highCut:p.highCut};
}
export function doublerPoints(w,h,state){
 const maxDelay=100,top=30,bottom=h-30,center=w/2;
 const y=delay=>top+clamp(delay/maxDelay,0,1)*Math.max(10,bottom-top);
 return {maxDelay,origin:[center,top],left:[center-state.width*(w/2-30),y(state.delayL)],right:[center+state.width*(w/2-30),y(state.delayR)],bottom};
}
export function drawDoubler(c,w,h,state){
 const g=doublerPoints(w,h,state),[cx,cy]=g.origin,active=state.voiceGain>.001;
 c.font='8px Arial';c.fillStyle='#b6c8c5';c.fillText(`PITCH ${state.semi>=0?'+':''}${state.semi.toFixed(2)} st`,7,12);
 c.textAlign='right';c.fillText('WIDTH: L ← 0 → R',w-7,12);c.textAlign='left';
 c.strokeStyle='#75b9e2';c.lineWidth=1;c.beginPath();c.moveTo(12,cy);c.lineTo(w-12,cy);c.stroke();
 c.strokeStyle='#516c70';c.beginPath();c.moveTo(cx,cy);c.lineTo(cx,g.bottom);c.stroke();
 c.fillStyle='#9dbac0';c.fillText('0 ms',5,cy-4);c.fillText(`${g.maxDelay} ms`,5,g.bottom+2);
 c.fillStyle='#75b9e2';c.beginPath();c.arc(cx,cy,4+state.dryGain*1.5,0,2*Math.PI);c.fill();
 c.fillText('DRY',cx+9,cy-7);
 c.strokeStyle=active?'#f7a65e':'#81918c';c.lineWidth=1.5;c.globalAlpha=active?clamp(.4+state.voiceGain*.6,.4,1):.4;
 if(state.polarity<0)c.setLineDash([3,3]);
 for(const point of [g.left,g.right]){c.beginPath();c.moveTo(cx,cy);c.lineTo(...point);c.stroke();}
 c.setLineDash([]);
 const merged=Math.abs(g.left[0]-g.right[0])<10&&Math.abs(g.left[1]-g.right[1])<7;
 for(const [i,point]of [g.left,g.right].entries()){
  if(merged&&i===1)continue;
  c.beginPath();c.arc(...point,state.pitchRadius,0,2*Math.PI);
  c.fillStyle=active?'#f7a65e':'#81918c';if(state.polarity<0)c.stroke();else c.fill();
  c.fillText(merged?'L/R':i===0?'L':'R',point[0]+state.pitchRadius+3,Math.min(h-24,point[1]+3));
 }
 c.globalAlpha=1;
 c.fillStyle='#75b9e2';c.beginPath();c.arc(cx,cy,3,0,2*Math.PI);c.fill();
 // Passband swatch refers to the added voice only, not the main signal.
 const railLeft=Math.max(75,w-112),railWidth=w-railLeft-8,railY=h-10;
 c.fillStyle='#52645f';c.fillRect(railLeft,railY,railWidth,3);
 const lo=clamp(Math.log(Math.max(20,state.lowCut)/20)/Math.log(1000),0,1),hi=clamp(Math.log(Math.max(20,state.highCut)/20)/Math.log(1000),0,1);
 c.fillStyle='#f7a65e';c.fillRect(railLeft+lo*railWidth,railY,Math.max(0,hi-lo)*railWidth,3);
 return g;
}
