const clamp=(v,lo,hi)=>Math.max(lo,Math.min(hi,v));
export const MOTION_WINDOW_MS=1100;
export function motionValue(time,decay){
 const duration=clamp(decay,5,1000);
 return time<0?0:time<2?time/2:time<5?1:Math.max(0,1-(time-5)/duration);
}
export function adrValue(time,{attack=20,decay=250,level=.5,release=400,curve=0,attackCurve=curve,decayCurve=curve,releaseCurve=curve,sync=false}){
 const limit=sync?3600000:30000,a=clamp(attack,1,limit),d=clamp(decay,1,limit),r=clamp(release,1,limit),knee=clamp(level,0,1),aPower=4**clamp(attackCurve,-1,1),dPower=4**clamp(decayCurve,-1,1),rPower=4**clamp(releaseCurve,-1,1);
 if(time<0)return 0;if(time<a)return (time/a)**aPower;
 if(time<a+d)return 1+(knee-1)*((time-a)/d)**dPower;
 if(time<a+d+r)return knee*(1-((time-a-d)/r)**rPower);return 0;
}
export function envelopeModel(width,height,settings){
 const adr=settings.kind==='adr',meter=!adr||settings.mode===1,left=8,right=width-(meter?70:10),top=12,bottom=height-24;
 const limit=settings.sync?3600000:30000;
 const total=adr?clamp(settings.attack,1,limit)+clamp(settings.decay,1,limit)+clamp(settings.release,1,limit):5+clamp(settings.decay,5,1000);
 const window=adr?Math.max(1000,total*1.05):MOTION_WINDOW_MS;
 const xFor=t=>left+clamp(t/window,0,1)*(right-left),yFor=v=>bottom-clamp(v,0,1)*(bottom-top);
 const stops=adr?[0,settings.attack,settings.attack+settings.decay,total]:[0,2,5,total,window];
 const times=[...new Set([...Array.from({length:201},(_,i)=>i*(adr?total:window)/200),...stops])].sort((a,b)=>a-b);
 const points=times.map(time=>({time,value:adr?adrValue(time,settings):settings.enabled?motionValue(time,settings.decay):0}));
 return {adr,meter,left,right,top,bottom,total,window,xFor,yFor,points};
}
export function detectorMeter(height,threshold,level=null,peak=null){
 const top=14,bottom=height-24,yFor=db=>bottom-(clamp(db,-60,0)+60)/60*(bottom-top);
 const db=v=>v===null||!Number.isFinite(v)?null:Math.max(-60,20*Math.log10(Math.max(1e-12,v)));
 return {top,bottom,yFor,thresholdY:yFor(threshold),levelDb:db(level),peakDb:db(peak)};
}
export function drawEnvelope(ctx,width,height,settings,state=null){
 const m=envelopeModel(width,height,settings);ctx.font='8px Arial';
 ctx.strokeStyle='#415a58';ctx.lineWidth=.7;ctx.beginPath();ctx.moveTo(m.left,m.bottom);ctx.lineTo(m.right,m.bottom);ctx.stroke();
 const ticks=m.adr?[0,m.window/2,m.window]:[0,500,1000];
 for(const t of ticks){const x=m.xFor(t);ctx.fillStyle='#a6bdb8';ctx.textAlign=t===0?'left':t===ticks.at(-1)?'right':'center';const musical=settings.sync&&settings.clock,barMs=musical?60000*(settings.clock.num||4)*4/((settings.clock.den||4)*(settings.clock.tempo||120)):0;ctx.fillText(musical?`${(t/barMs).toFixed(2)}${t===0?' bars':''}`:`${m.adr&&m.window>=10000?(t/1000).toFixed(1):Math.round(t)}${t===0?(m.adr&&m.window>=10000?' s':' ms'):''}`,x,height-7);}
 ctx.globalAlpha=m.adr&&settings.mode===0?.5:1;ctx.strokeStyle='#64d3c5';ctx.lineWidth=1.8;ctx.beginPath();m.points.forEach((p,i)=>i?ctx.lineTo(m.xFor(p.time),m.yFor(p.value)):ctx.moveTo(m.xFor(p.time),m.yFor(p.value)));ctx.stroke();ctx.globalAlpha=1;
 if(m.adr){
  const knots=[];
  for(const [time,value,label]of [[settings.attack,1,'A'],[settings.attack+settings.decay,settings.level,'D'],[m.total,0,'R']]){const x=m.xFor(time),y=m.yFor(value),last=knots.at(-1);if(last&&Math.hypot(last.x-x,last.y-y)<10)last.label+='/'+label;else knots.push({x,y,label});}
  for(const {x,y,label}of knots){ctx.fillStyle='#eeb575';ctx.beginPath();ctx.arc(x,y,2.5,0,2*Math.PI);ctx.fill();ctx.textAlign='left';ctx.fillText(label,Math.min(m.right-label.length*5,x+4),Math.max(9,y-5));}
 }
 if(state?.enabled){
  const age=m.adr?state.phase*m.total:Number.isFinite(state.age)?state.age*1000:state.phase*m.total;
  if(age<=m.window&&(state.value>.0001||age<m.total)){ctx.fillStyle='#ffbd75';ctx.beginPath();ctx.arc(m.xFor(age),m.yFor(state.value),3.5,0,2*Math.PI);ctx.fill();}
 }
 if(m.meter){
  const threshold=state?.threshold??settings.threshold,barX=width-18,barWidth=8,meter=detectorMeter(height,threshold,state?.level??null,state?.peak??null);
  ctx.fillStyle='#293e3e';ctx.fillRect(barX,meter.top,barWidth,meter.bottom-meter.top);
  if(meter.levelDb!==null){const y=meter.yFor(meter.levelDb);ctx.fillStyle=meter.levelDb>=threshold?'#f3ac69':'#64d3c5';ctx.fillRect(barX,y,barWidth,meter.bottom-y);}
  if(meter.peakDb!==null){ctx.strokeStyle='#d1ddd5';const y=meter.yFor(meter.peakDb);ctx.beginPath();ctx.moveTo(barX,y);ctx.lineTo(barX+barWidth,y);ctx.stroke();}
  ctx.strokeStyle='#f3ac69';ctx.lineWidth=1;ctx.beginPath();ctx.moveTo(barX-3,meter.thresholdY);ctx.lineTo(barX+barWidth+3,meter.thresholdY);ctx.stroke();
  ctx.fillStyle='#f3ac69';ctx.textAlign='right';ctx.fillText(`${threshold.toFixed(0)}`,barX-5,meter.thresholdY+3);
  ctx.fillStyle='#a6bdb8';ctx.textAlign='center';ctx.fillText(settings.external?'EXT':'IN',barX+4,9);
  ctx.textAlign='right';ctx.fillText(meter.levelDb===null?'— dB':`${meter.levelDb.toFixed(1)} dB`,width-4,height-7);
 }
 ctx.textAlign='left';return m;
}
