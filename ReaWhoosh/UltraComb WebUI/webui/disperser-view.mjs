const clamp=(value,low,high)=>Math.max(low,Math.min(high,value));
export function spreadPosition(position,curve=0){
 const p=clamp(position,-1,1),amount=clamp(curve,-1,1);
 return amount===0?p:Math.sign(p)*Math.abs(p)**(4**amount);
}
export function sectionFrequencies({center,spread,stages,curve=0,sampleRate=48000}){
 const count=Math.round(clamp(stages,0,128)),base=clamp(center,20,sampleRate*.49);
 return Array.from({length:count},(_,i)=>clamp(base*2**(spreadPosition(count<=1?0:2*i/(count-1)-1,curve)*clamp(spread,0,200)/100),20,sampleRate*.49));
}
export function allpassCoefficients(frequency,q,sampleRate=48000){
 const omega=2*Math.PI*frequency/sampleRate,alpha=Math.sin(omega)/(2*Math.max(.1,q));
 return {a1:-2*Math.cos(omega)/(1+alpha),a2:(1-alpha)/(1+alpha)};
}
// H(z) = z^-2 D*(z) / D(z), so group delay = 2 - 2 Re(S/D).
// This evaluates the same all-pass coefficients used by the native DSP.
function delayAt({c1,s1,c2,s2},{a1,a2}){
 const dr=1+a1*c1+a2*c2,di=-a1*s1-a2*s2;
 const sr=a1*c1+2*a2*c2,si=-a1*s1-2*a2*s2;
 return Math.max(0,2-2*(sr*dr+si*di)/Math.max(1e-30,dr*dr+di*di));
}
const trigAt=omega=>({c1:Math.cos(omega),s1:Math.sin(omega),c2:Math.cos(2*omega),s2:Math.sin(2*omega)});
export function sectionGroupDelay(omega,coefficients){return delayAt(trigAt(omega),coefficients);}
export function disperserModel(width,settings){
 const sampleRate=Math.max(8000,settings.sampleRate||48000),low=20,high=Math.min(20000,sampleRate*.49),span=Math.log(high/low);
 const frequencies=sectionFrequencies({...settings,sampleRate}),coefficients=frequencies.map(f=>allpassCoefficients(f,settings.q,sampleRate));
 const left=10,right=width-10,xFor=f=>left+clamp(Math.log(Math.max(low,f)/low)/span,0,1)*(right-left);
 const count=Math.max(80,Math.ceil((right-left)/2)),samples=[...new Set([...Array.from({length:count+1},(_,i)=>low*Math.exp(i/count*span)),...frequencies.filter(f=>f>=low&&f<=high)])].sort((a,b)=>a-b);
 const profile=samples.map(frequency=>{
  const trig=trigAt(2*Math.PI*frequency/sampleRate);
  const delay=coefficients.reduce((sum,c)=>sum+delayAt(trig,c),0)*1000/sampleRate;
  return {x:xFor(frequency),frequency,delay};
 });
 // Keep automatic scaling continuous: rounding to the next significant digit
 // made a smooth Center sweep repeatedly grow then snap down at scale changes.
 const peak=Math.max(0,...profile.map(p=>p.delay)),ceiling=peak>0?peak*1.15:1;
 return {frequencies,profile,peak,ceiling,left,right,xFor,centerX:xFor(clamp(settings.center,low,high)),low,high};
}
export function drawDisperser(ctx,width,height,settings){
 const model=disperserModel(width,settings),top=31,bottom=height-20;
 ctx.fillStyle='#182326';ctx.fillRect(0,0,width,height);
 ctx.font='8px Arial';ctx.fillStyle='#acbfba';ctx.textAlign='left';ctx.fillText('GROUP DELAY · AUTO SCALE',10,10);
 ctx.textAlign='right';ctx.fillText(`PEAK ${model.peak.toFixed(model.peak<10?2:1)} ms`,width-10,10);
 for(const frequency of [20,100,1000,10000,20000].filter(f=>f<=model.high)){
  const x=model.xFor(frequency);ctx.strokeStyle='#2e4243';ctx.lineWidth=.6;ctx.beginPath();ctx.moveTo(x,top);ctx.lineTo(x,bottom);ctx.stroke();
  ctx.textAlign=frequency===20?'left':frequency===20000?'right':'center';ctx.fillStyle='#9fb5b1';ctx.fillText(frequency===20?'20 Hz':frequency>=1000?frequency/1000+'k':String(frequency),x,height-5);
 }
 for(let i=0;i<=2;i++){const y=top+(bottom-top)*i/2;ctx.strokeStyle='#2e4243';ctx.beginPath();ctx.moveTo(model.left,y);ctx.lineTo(model.right,y);ctx.stroke();}
 // The marker strip remains separate from the aggregate group-delay profile.
 ctx.strokeStyle='#f3ac69aa';ctx.lineWidth=1;
 for(const frequency of model.frequencies){const x=model.xFor(frequency);ctx.beginPath();ctx.moveTo(x,17);ctx.lineTo(x,25);ctx.stroke();}
 const points=model.profile.map(p=>[p.x,bottom-p.delay/model.ceiling*(bottom-top)]),fill=ctx.createLinearGradient(0,top,0,bottom);fill.addColorStop(0,'#f3ac6966');fill.addColorStop(1,'#f3ac6908');
 ctx.fillStyle=fill;ctx.beginPath();ctx.moveTo(model.left,bottom);for(const [x,y]of points)ctx.lineTo(x,y);ctx.lineTo(model.right,bottom);ctx.closePath();ctx.fill();
 ctx.strokeStyle='#f3ac69';ctx.lineWidth=1.5;ctx.beginPath();points.forEach(([x,y],i)=>i?ctx.lineTo(x,y):ctx.moveTo(x,y));ctx.stroke();
 ctx.strokeStyle='#63cbd1aa';ctx.lineWidth=.8;ctx.setLineDash([3,3]);ctx.beginPath();ctx.moveTo(model.centerX,27);ctx.lineTo(model.centerX,bottom);ctx.stroke();ctx.setLineDash([]);
 ctx.fillStyle='#63cbd1';ctx.beginPath();ctx.moveTo(model.centerX,29);ctx.lineTo(model.centerX-3,25);ctx.lineTo(model.centerX+3,25);ctx.closePath();ctx.fill();ctx.textAlign='left';
 return model;
}
