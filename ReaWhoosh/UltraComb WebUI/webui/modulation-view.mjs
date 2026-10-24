export function modulationShapeFor(source,get){
 if(source.on)return get(source.on)>.5?['sine','saw','square','random'][Math.round(get(source.shape))]||'sine':'none';
 if(source.key==='envelope')return 'envelope';
 if(source.key==='pitch')return get(45)>1.5?'attack':'none';
 return 'none';
}
export function wave(shape,phase){
 const p=phase-Math.floor(phase);
 if(shape==='saw')return 2*p-1;
 if(shape==='square')return p<.5?1:-1;
 if(shape==='triangle')return 1-4*Math.abs(p-.5);
 if(shape==='attack')return p<.02?p/.02:p<.05?1:Math.max(0,1-(p-.05)/.95);
 return Math.sin(2*Math.PI*p);
}
export function decodeTelemetry(packet){
 if(![21,29,32].includes(packet.data?.length)||!Array.from(packet.data).every(Number.isFinite))return null;
 return Array.from({length:packet.data.length===32?8:7},(_,i)=>{const offset=i===7?29:i*3;return {phase:Math.max(0,Math.min(1,packet.data[offset])),value:Math.max(-1,Math.min(1,packet.data[offset+1])),enabled:packet.data[offset+2]>.5};});
}
export class ModulationView{
 constructor(canvas,status){this.canvas=canvas;this.status=status;this.states=null;this.received=0;this.history=[];}
 accept(packet){const states=decodeTelemetry(packet);if(!states)return;this.states=states;this.received=performance.now();this.history.push(states.map(s=>s.value));if(this.history.length>180)this.history.shift();}
 draw(index,shape,depth=1){
  const c=this.canvas,dpr=Math.min(2,devicePixelRatio||1),w=c.clientWidth,h=c.clientHeight;
  if(c.width!==Math.round(w*dpr)||c.height!==Math.round(h*dpr)){c.width=Math.round(w*dpr);c.height=Math.round(h*dpr);}
  const ctx=c.getContext('2d');ctx.setTransform(dpr,0,0,dpr,0,0);ctx.fillStyle='#182326';ctx.fillRect(0,0,w,h);
  ctx.strokeStyle='#304245';ctx.lineWidth=.5;
  for(let i=1;i<8;i++){ctx.beginPath();ctx.moveTo(w*i/8,0);ctx.lineTo(w*i/8,h);ctx.stroke();}
  for(let i=1;i<4;i++){ctx.beginPath();ctx.moveTo(0,h*i/4);ctx.lineTo(w,h*i/4);ctx.stroke();}
  const live=this.states&&performance.now()-this.received<500,state=live?this.states[index]:null;
  const trace=shape==='random'||shape==='envelope',y=v=>h/2-v*(h/2-14);
  ctx.strokeStyle='#64d3c5';ctx.lineWidth=1.8;ctx.beginPath();
  if(trace){this.history.forEach((row,i)=>{const value=row[index]??0,x=w*i/179,v=shape==='envelope'?value*2-1:value;i?ctx.lineTo(x,y(v)):ctx.moveTo(x,y(v));});}
  else for(let x=0;x<=w;x++){const v=shape==='none'?0:wave(shape,x/w)*depth;x?ctx.lineTo(x,y(v)):ctx.moveTo(x,y(v));}
  ctx.stroke();
  if(state){const x=trace?w*Math.max(0,this.history.length-1)/179:w*state.phase,v=shape==='none'?0:shape==='envelope'?state.value*2-1:state.value;
   ctx.fillStyle=state.enabled?'#ffbd75':'#8d9a99';ctx.beginPath();ctx.arc(x,y(v),4,0,Math.PI*2);ctx.fill();
  }
  this.status.textContent=state?(state.enabled?'DSP LIVE':'DSP / INACTIVE'):'NO DSP DATA';
 }
}
