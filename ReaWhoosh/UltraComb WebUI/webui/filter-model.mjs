export function filterDrive(input,db){const gain=10**(db/20),shaped=input*gain/Math.sqrt(1+input*input*gain*gain);return input+(shaped-input)*Math.min(1,db/3);}
export function filterPlot(width,height,{mode,cutoff,resonance,mix}){
 const q=.5*40**resonance,zero=height*.5,scale=(zero-8)/36;
 const center=Math.log(Math.max(20,Math.min(20000,cutoff))/20)/Math.log(1000)*width;
 const xs=[...new Set([...Array.from({length:Math.ceil(width)+1},(_,i)=>Math.min(width,i)),center])].sort((a,b)=>a-b);
 const points=xs.map(x=>{const hz=20*1000**(x/width),r=hz/cutoff,den=Math.sqrt((1-r*r)**2+(r/q)**2);
  const a=mode===0?1/den:mode===1?r*r/den:mode===2?r/den:Math.abs(1-r*r)/den;
  const db=20*Math.log10(Math.max(1e-6,(1-mix)+mix*a));return [x,Math.max(6,Math.min(height-18,zero-db*scale))];
 });return {zero,points};
}
