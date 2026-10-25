const notes=[];
for(const denominator of [64,32,16,8,4,2])for(const [suffix,multiplier]of [['T',2/3],['',1],['D',1.5]])notes.push({label:`1/${denominator}${suffix}`,beats:4/denominator*multiplier});
export const divisions=[...notes.sort((a,b)=>a.beats-b.beats),...[1,2,4,8].map(bars=>({label:`${bars} ${bars===1?'bar':'bars'}`,bars}))];
export const syncDivisionIds=new Set([195,196,197,198,199,212,213,214]);
export const syncAliases=new Map([[195,15],[196,132],[197,143],[198,144],[199,146],[212,203],[213,204],[214,206]]);
export function clockInfo(clock={}){return {tempo:Number(clock.tempo)>0?Number(clock.tempo):120,num:Number(clock.num)>0?Number(clock.num):4,den:Number(clock.den)>0?Number(clock.den):4};}
export function divisionBeats(index,clock={}){const c=clockInfo(clock),d=divisions[Math.max(0,Math.min(divisions.length-1,Math.round(index)))];return d.bars?d.bars*c.num*4/c.den:d.beats;}
export function divisionValue(id,index,clock={}){const c=clockInfo(clock),beats=divisionBeats(index,c);return id<=196?c.tempo/(60*beats):60000*beats/c.tempo;}
function ordered(id,clock){return divisions.map((_,index)=>({index,value:divisionValue(id,index,clock)})).sort((a,b)=>a.value-b.value||a.index-b.index);}
export function divisionPosition(id,index,clock={}){const order=ordered(id,clock),rank=order.findIndex(d=>d.index===Math.round(index));return Math.max(0,rank)/(order.length-1);}
export function divisionFromPosition(id,position,clock={}){const order=ordered(id,clock);return order[Math.max(0,Math.min(order.length-1,Math.round(position*(order.length-1))))].index;}
export function syncValuePosition(id,value,clock={}){const order=ordered(id,clock),v=Math.max(1e-9,value);if(v<=order[0].value)return 0;if(v>=order.at(-1).value)return 1;for(let i=0;i<order.length-1;i++){const a=order[i].value,b=order[i+1].value;if(v>=a&&v<=b)return (i+(b===a?0:Math.log(v/a)/Math.log(b/a)))/(order.length-1);}return 0;}
