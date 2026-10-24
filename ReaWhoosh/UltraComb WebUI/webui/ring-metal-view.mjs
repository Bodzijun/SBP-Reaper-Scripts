const clamp=(v,lo,hi)=>Math.max(lo,Math.min(hi,v));
function stroke(c,points,color,width=1.6){c.strokeStyle=color;c.lineWidth=width;c.beginPath();points.forEach(([x,y],i)=>i?c.lineTo(x,y):c.moveTo(x,y));c.stroke();}
export function ringModel(w,h,{frequency,depth,mix,enabled}){
 const hz=clamp(frequency,1,20000),seconds=hz<=40?.25:hz<=1000?.01:.0005;
 const amount=clamp(depth,0,1)*clamp(mix,0,1),top=25,bottom=h-30,zero=(top+bottom)/2,scale=(bottom-top)/2.2;
 const points=Array.from({length:Math.ceil(w)+1},(_,i)=>[i,zero-(1+amount*(Math.sin(2*Math.PI*hz*seconds*i/w)-1))*scale]);
 return {hz,seconds,amount,points,zero,unity:zero-scale,scale,enabled:!!enabled};
}
export function drawRing(c,w,h,p){
 const m=ringModel(w,h,p),color=m.enabled?'#f3aa70':'#8fa5a4';
 stroke(c,[[0,m.zero],[w,m.zero]],'#54716f',1);
 c.setLineDash([3,4]);stroke(c,[[0,m.unity],[w,m.unity]],'#536a69',1);c.setLineDash([]);
 const fill=c.createLinearGradient(0,25,0,h-30);fill.addColorStop(0,m.enabled?'#f3aa7044':'#8fa5a41b');fill.addColorStop(1,'#f3aa7003');
 c.fillStyle=fill;c.beginPath();c.moveTo(0,m.zero);for(const [x,y]of m.points)c.lineTo(x,y);c.lineTo(w,m.zero);c.closePath();c.fill();stroke(c,m.points,color);
 c.font='8px Arial';c.fillStyle='#a7bfba';c.fillText(`GAIN · ${(m.seconds*1000).toFixed(m.seconds<.001?1:0)} ms WINDOW`,8,13);
 c.fillText('+1',4,m.unity-4);c.fillText('0',4,m.zero-4);
 c.textAlign='right';c.fillText(`DRY ${Math.round((1-m.amount)*100)}% · RING ${Math.round(m.amount*100)}%`,w-8,13);c.textAlign='left';
}
export const metalRatios=[1,1.37,1.91,2.63,3.79,5.17];
export function metalModes({size,decay,tone}){
 const brightness=clamp(tone,0,1);
 return metalRatios.map((ratio,i)=>{
  const hz=1/(.0015*clamp(size,.25,4)*ratio),seconds=clamp(decay,.03,3)/(1+i*.08);
  return {hz,decay:seconds,bandwidth:Math.log(1000)/(Math.PI*seconds),weight:Math.exp(-i*(1-brightness)*.25),cutoff:500*32**brightness};
 });
}
export function metalModel(w,h,p){
 const left=14,right=w-14,top=25,bottom=h-32,span=Math.log(1000),modes=metalModes(p),mix=clamp(p.mix,0,1);
 const xFor=hz=>left+Math.log(clamp(hz,20,20000)/20)/span*(right-left);
 const frequencies=[...new Set([...Array.from({length:Math.ceil(right-left)+1},(_,i)=>20*1000**(i/(right-left))),...modes.map(m=>m.hz)])].sort((a,b)=>a-b);
 // Each mode is a damped comb, not a single biquad. These peaks illustrate the
 // fundamental regions only; they are deliberately labelled as a control model.
 const curves=modes.map(m=>({ ...m,x:xFor(m.hz),points:frequencies.map(hz=>{
  const peak=1/Math.sqrt(1+((hz-m.hz)/(m.bandwidth*.5))**2),damping=1/Math.sqrt(1+(hz/m.cutoff)**2);
  return [xFor(hz),bottom-(bottom-top)*.86*peak*m.weight*damping*mix];
 })}));
 return {left,right,top,bottom,curves,dry:1-mix,xFor};
}
export function drawMetal(c,w,h,p){
 const m=metalModel(w,h,p),color=p.enabled?'#e5bb58':'#8fa5a4';
 for(const curve of m.curves){
  const fill=c.createLinearGradient(0,m.top,0,m.bottom);fill.addColorStop(0,p.enabled?'#e5bb5833':'#8fa5a417');fill.addColorStop(1,'#e5bb5802');
  c.fillStyle=fill;c.beginPath();c.moveTo(m.left,m.bottom);for(const [x,y]of curve.points)c.lineTo(x,y);c.lineTo(m.right,m.bottom);c.closePath();c.fill();stroke(c,curve.points,color,1.2);
  c.fillStyle=color;c.beginPath();const y=curve.points.reduce((nearest,point)=>Math.abs(point[0]-curve.x)<Math.abs(nearest[0]-curve.x)?point:nearest,curve.points[0])[1];c.arc(curve.x,y,2,0,2*Math.PI);c.fill();
 }
 stroke(c,[[m.left,m.bottom],[m.right,m.bottom]],'#536e69',1);
 c.font='8px Arial';c.fillStyle='#a7bfba';c.fillText('6 MODES · LOG Hz',8,13);
 c.textAlign='right';c.fillText(`${p.decay.toFixed(2)} s · WET ${Math.round(p.mix*100)}%`,w-8,13);
 for(const hz of [20,200,2000,20000]){c.textAlign=hz===20?'left':hz===20000?'right':'center';c.fillText(hz>=1000?`${hz/1000}k`:`${hz}`,m.xFor(hz),h-20);}c.textAlign='left';
}
