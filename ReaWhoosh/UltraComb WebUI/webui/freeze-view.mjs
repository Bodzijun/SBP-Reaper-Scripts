// Fixed time scale: changing Loop must resize the window, not zoom the axis.
export function freezeWindow(w,h,{length,mix,enabled,reverse}){
 const duration=Math.max(20,Math.min(500,length)),left=18,right=w-18;
 return {left,right,end:left+(right-left)*duration/500,top:27,bottom:h-38,
  duration,mix:Math.max(0,Math.min(1,mix)),enabled:!!enabled,reverse:!!reverse};
}
export function drawFreeze(c,w,h,parameters){
 const p=freezeWindow(w,h,parameters),color=p.enabled?'#f3a46a':'#8fa5a4';
 c.font='9px Arial';c.fillStyle='#b9d0cb';c.fillText(`LOOP WINDOW · ${p.duration.toFixed(0)} ms`,10,14);
 const fill=c.createLinearGradient(0,p.top,0,p.bottom);
 const opacity=p.enabled ? .1+p.mix*.25 : .07;
 fill.addColorStop(0,`rgba(243,164,106,${opacity})`);fill.addColorStop(1,`rgba(243,164,106,${opacity*.25})`);
 c.fillStyle=fill;c.fillRect(p.left,p.top,p.end-p.left,p.bottom-p.top);
 c.strokeStyle='#567575';c.lineWidth=1;c.beginPath();c.moveTo(p.left,p.bottom);c.lineTo(p.right,p.bottom);c.stroke();
 c.strokeStyle=color;c.lineWidth=1.8;c.beginPath();
 c.moveTo(p.left,p.bottom);c.lineTo(p.left,p.top);c.lineTo(p.end,p.top);c.lineTo(p.end,p.bottom);c.stroke();
 const y=(p.top+p.bottom)/2,span=p.end-p.left;
 if(span>25){
  const start=p.reverse?p.end-7:p.left+7,end=p.reverse?p.left+7:p.end-7,direction=p.reverse?-1:1;
  c.beginPath();c.moveTo(start,y);c.lineTo(end,y);c.moveTo(end-direction*4,y-4);c.lineTo(end,y);c.lineTo(end-direction*4,y+4);c.stroke();
 }else{
  const x=(p.left+p.end)/2,d=p.reverse?-1:1;
  c.beginPath();c.moveTo(x-d*2,y-4);c.lineTo(x+d*2,y);c.lineTo(x-d*2,y+4);c.stroke();
 }
 c.font='8px Arial';c.fillStyle='#9caead';
 for(const ms of [0,250,500]){
  const x=p.left+(p.right-p.left)*ms/500;c.textAlign=ms===0?'left':ms===500?'right':'center';
  c.fillText(`${ms} ms`,x,h-24);
 }
 c.textAlign='left';
}
