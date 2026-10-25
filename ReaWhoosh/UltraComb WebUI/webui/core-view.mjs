export const CORE_DELAY_MAX_MS=200;
const clamp=(value,low,high)=>Math.max(low,Math.min(high,value));
// A parameter model, deliberately independent of input audio/telemetry.
export function combGeometry(width,height,dry,feed){
 const left=width<360?62:70,right=width-14,span=Math.max(1,right-left);
 const rows=[dry,feed].map((delay,i)=>({delay:clamp(delay,0,CORE_DELAY_MAX_MS),x:left+clamp(delay,0,CORE_DELAY_MAX_MS)/CORE_DELAY_MAX_MS*span,y:height*(i?.62:.30),name:i?'FX FEED':'DRY',color:i?'#f7aa61':'#63cbd1'}));
 return {left,right,span,axis:height-20,rows,ticks:[0,50,100,150,200].map(ms=>({ms,x:left+ms/CORE_DELAY_MAX_MS*span}))};
}
export function combWavePoints(geometry,row,time,feedback=0,mix=.5){
 const amplitude=10*(row.name==='DRY'?.35+.65*(1-clamp(mix,0,1)):.35+.65*clamp(mix,0,1));
 const points=[],steps=Math.max(1,Math.ceil((geometry.right-row.x)/2));
 for(let i=0;i<=steps;i++){
  const x=row.x+(geometry.right-row.x)*i/steps,offset=(x-row.x)/geometry.span*CORE_DELAY_MAX_MS;
  const phase=offset/24*2*Math.PI-time*1.7;
  const attack=1-Math.exp(-(x-row.x)/8),decay=Math.exp(-offset/(row.name==='DRY'?130:80+260*clamp(feedback,0,.95)));
  const wave=.65*Math.sin(phase)+.24*Math.sin(phase*1.83+.8)+.11*Math.sin(phase*3.17+2);
  points.push([x,row.y-wave*amplitude*attack*decay]);
 }
 return points;
}
export function drawComb(ctx,width,height,{dry,feed,feedback,mix,time=0}){
 const model=combGeometry(width,height,dry,feed);
 ctx.fillStyle='#182326';ctx.fillRect(0,0,width,height);
 for(let ms=0;ms<=CORE_DELAY_MAX_MS;ms+=25){const x=model.left+ms/CORE_DELAY_MAX_MS*model.span;ctx.strokeStyle=ms%50===0?'#344a4c':'#253739';ctx.lineWidth=.6;ctx.beginPath();ctx.moveTo(x,12);ctx.lineTo(x,model.axis);ctx.stroke();}
 for(const row of model.rows){
  ctx.strokeStyle='#466264';ctx.lineWidth=.7;ctx.beginPath();ctx.moveTo(model.left,row.y);ctx.lineTo(model.right,row.y);ctx.stroke();
  const points=combWavePoints(model,row,time,feedback,mix);
  if(row.x<model.right){
   const gradient=ctx.createLinearGradient(row.x,0,model.right,0);gradient.addColorStop(0,row.color+'38');gradient.addColorStop(1,row.color+'03');
   ctx.fillStyle=gradient;ctx.beginPath();ctx.moveTo(row.x,row.y);for(const [x,y]of points)ctx.lineTo(x,y);ctx.lineTo(model.right,row.y);ctx.closePath();ctx.fill();
   ctx.strokeStyle=row.color;ctx.lineWidth=1.35;ctx.beginPath();points.forEach(([x,y],i)=>i?ctx.lineTo(x,y):ctx.moveTo(x,y));ctx.stroke();
  }
  ctx.fillStyle=row.color;ctx.fillRect(row.x-1,row.y-12,2,24);ctx.beginPath();ctx.arc(row.x,row.y,2.5,0,Math.PI*2);ctx.fill();
  ctx.font='bold 8px Arial';ctx.textAlign='left';ctx.fillText(row.name,8,row.y+3);
  ctx.font='8px Arial';ctx.textAlign=row.x>model.right-45?'right':'left';ctx.fillText(row.delay.toFixed(1)+' ms',row.x>model.right-45?row.x-4:row.x+4,row.y-12);
 }
 ctx.strokeStyle='#627c7c';ctx.lineWidth=.7;ctx.beginPath();ctx.moveTo(model.left,model.axis);ctx.lineTo(model.right,model.axis);ctx.stroke();
 ctx.font='8px Arial';ctx.fillStyle='#a5b9b6';
 for(const tick of model.ticks){ctx.beginPath();ctx.moveTo(tick.x,model.axis);ctx.lineTo(tick.x,model.axis+3);ctx.stroke();ctx.textAlign=tick.ms===0?'left':tick.ms===CORE_DELAY_MAX_MS?'right':'center';ctx.fillText(String(tick.ms)+(tick.ms===CORE_DELAY_MAX_MS?' ms':''),tick.x,height-5);}
 ctx.textAlign='left';
}
