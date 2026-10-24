export const palettes={
 aurora:[[0,14,25,34],[.25,31,64,98],[.5,30,139,149],[.72,98,192,134],[.88,237,195,74],[1,255,246,205]],
 ember:[[0,15,10,24],[.25,70,28,105],[.5,175,43,70],[.75,239,114,36],[1,255,247,189]],
 ice:[[0,8,18,27],[.25,18,47,91],[.5,29,117,175],[.75,74,204,217],[1,235,255,255]],
 mono:[[0,10,15,19],[1,250,252,253]]
};
export function color(db,palette='aurora'){
 const stops=palettes[palette]||palettes.aurora;
 const t=Math.max(0,Math.min(1,(db+90)/90));let i=1;while(i<stops.length-1&&t>stops[i][0])i++;
 const a=stops[i-1],b=stops[i],f=(t-a[0])/(b[0]-a[0]);return [1,2,3].map(k=>Math.round(a[k]+(b[k]-a[k])*f));
}
export class Spectrogram {
 constructor(canvas,status){this.canvas=canvas;this.status=status;this.seconds=8;this.palette='aurora';this.paused=false;this.lastTime=null;this.epoch=null;this.lastSequence=null;this.clear();}
 clear(){const c=this.canvas;c.width=Math.max(240,Math.round(c.clientWidth||360));c.height=180;this.ctx=c.getContext('2d');this.ctx.fillStyle='#111c20';this.ctx.fillRect(0,0,c.width,c.height);this.lastTime=null;this.lastSequence=null;this.status.textContent='WAITING FOR AUDIO';}
 accept(packet,info){
  if(this.paused)return;
  if(packet.sequence!==undefined&&packet.sequence===this.lastSequence)return;
  this.lastSequence=packet.sequence;
  const data=packet.data,channels=Number(info.channels||2),rate=Number(info.sampleRate),bins=Math.floor((data?.length||0)/channels);
  if(!data||bins<16||!Number.isFinite(rate)||rate<8000){this.status.textContent='INVALID STREAM';return;}
  const timing=packet.timing||{},epoch=timing.clockEpoch;
  if(timing.discontinuity||(epoch!==undefined&&this.epoch!==null&&epoch!==this.epoch))this.clear();
  this.epoch=epoch??this.epoch;
  const sample=Number(timing.firstSample??packet.firstSample),time=Number.isFinite(sample)?sample/rate:performance.now()/1000;
  const dt=this.lastTime===null?1/30:time-this.lastTime;
  if(dt<0||dt>this.seconds){this.clear();}
  this.lastTime=time;
  const {canvas:c,ctx}=this,w=c.width,h=c.height,step=Math.min(w,Math.max(1,Math.round(w*Math.max(1/120,Math.min(.5,dt))/this.seconds)));
  ctx.drawImage(c,step,0,w-step,h,0,0,w-step,h);
  const column=ctx.createImageData(step,h),high=Math.min(20000,rate/2);
  for(let y=0;y<h;y++){
   const lowHz=20*(high/20)**(1-(y+.5)/(h-1)),highHz=20*(high/20)**(1-(y-.5)/(h-1));
   const lo=Math.max(0,Math.min(bins-1,Math.floor(lowHz/(rate/2)*(bins-1)))),hi=Math.max(lo,Math.min(bins-1,Math.ceil(highHz/(rate/2)*(bins-1))));
   let energy=0;
   for(let bin=lo;bin<=hi;bin++){let power=0;for(let channel=0;channel<channels;channel++){const a=data[bin*channels+channel];power+=Number.isFinite(a)?a*a:0;}energy=Math.max(energy,power);}
   const rgb=color(10*Math.log10(Math.max(1e-12,energy/channels)),this.palette);
   for(let x=0;x<step;x++){const p=(y*step+x)*4;column.data[p]=rgb[0];column.data[p+1]=rgb[1];column.data[p+2]=rgb[2];column.data[p+3]=255;}
  }
  ctx.putImageData(column,w-step,0);this.status.textContent=`LIVE · ${Math.round(rate/100)/10} kHz`;
 }
}
