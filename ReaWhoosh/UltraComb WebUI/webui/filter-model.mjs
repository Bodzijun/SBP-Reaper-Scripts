const clamp=(v,lo,hi)=>Math.max(lo,Math.min(hi,v));
export function filterDrive(input,db){const gain=10**(db/20),shaped=input*gain/Math.sqrt(1+input*input*gain*gain);return input+(shaped-input)*Math.min(1,db/3);}
export function filterHeat(db){
 const t=clamp(db,0,24)/12,colors=[[101,213,157],[255,157,69],[255,78,64]],i=Math.min(1,Math.floor(t)),f=t-i;
 return '#'+colors[i].map((v,k)=>Math.round(v+(colors[i+1][k]-v)*f).toString(16).padStart(2,'0')).join('');
}
export function filterResponse(hz,{mode=0,cutoff=2000,resonance=.2,mix=1,sampleRate=48000}){
 const sr=Math.max(8000,sampleRate),frequency=clamp(hz,0,sr*.4999),fc=clamp(cutoff,20,Math.min(20000,sr*.45)),res=clamp(resonance,0,1),k=2/40**res,blend=clamp(mix,0,1);
 const svf=center=>{const r=Math.tan(Math.PI*frequency/sr)/Math.tan(Math.PI*center/sr),real=1-r*r,imag=k*r,den=real*real+imag*imag,divide=(a,b)=>[(a*real+b*imag)/den,(b*real-a*imag)/den];return {lp:divide(1,0),hp:divide(-r*r,0),bp:divide(0,k*r),notch:divide(real,0)};};
 const h=svf(fc);let wet;
 if(mode===4)wet=[1+3*res*h.bp[0],3*res*h.bp[1]];
 else if(mode===5){const second=svf(Math.min(sr*.45,fc*2.4));wet=[1.2*(h.bp[0]+.7*second.bp[0]),1.2*(h.bp[1]+.7*second.bp[1])];}
 else if(mode===6||mode===7){const delay=sr/fc,n=Math.floor(delay),f=delay-n,w=2*Math.PI*frequency/sr,g=.98*res,sign=mode===6?1:-1;
  const real=(1-f)*Math.cos(w*n)+f*Math.cos(w*(n+1)),imag=-(1-f)*Math.sin(w*n)-f*Math.sin(w*(n+1));wet=[(1+sign*g*real)/(1+g),sign*g*imag/(1+g)];
 }else wet=[h.lp,h.hp,h.bp,h.notch][mode]||h.lp;
 const real=1-blend+blend*wet[0],imag=blend*wet[1];return {real,imag,magnitude:Math.hypot(real,imag)};
}
export function combBandBounds(hz,{cutoff,resonance,mix,sampleRate=48000}){
 const sr=Math.max(8000,sampleRate),fc=clamp(cutoff,20,Math.min(20000,sr*.45)),delay=sr/fc,fraction=delay-Math.floor(delay),g=.98*clamp(resonance,0,1),blend=clamp(mix,0,1);
 const attenuation=Math.sqrt(Math.max(0,(1-fraction)**2+fraction**2+2*fraction*(1-fraction)*Math.cos(2*Math.PI*hz/sr)));
 const a=1-blend+blend/(1+g),b=blend*g*attenuation/(1+g);return {low:Math.abs(a-b),high:a+b};
}
export function filterPlot(width,height,settings){
 const zero=height*.5,scale=(zero-8)/36,upper=Math.min(20000,(settings.sampleRate||48000)*.49),fc=clamp(settings.cutoff,20,Math.min(upper,(settings.sampleRate||48000)*.45)),ratio=upper/20;
 const xFor=hz=>Math.log(hz/20)/Math.log(ratio)*width,yFor=value=>clamp(zero-20*Math.log10(Math.max(1e-6,value))*scale,6,height-18);
 const comb=(settings.mode===6||settings.mode===7)&&settings.mix>0&&settings.resonance>0;
 // Stop before neighbouring extrema become less than 4 px apart; never invent
 // fewer teeth on the same frequency scale. Unresolved teeth become a bound band.
 const detailLimit=comb?Math.min(upper,fc*12,fc/(2*(ratio**(4/width)-1))):upper;
 const end=detailLimit<upper?Math.max(0,xFor(detailLimit)):width;
 const center=Math.log(fc/20)/Math.log(ratio)*width,second=Math.log(clamp(fc*2.4,20,upper)/20)/Math.log(ratio)*width;
 const teeth=comb?Array.from({length:25},(_,i)=>fc*i/2).filter(hz=>hz>=20&&hz<=detailLimit).map(xFor):[];
 const xs=[...new Set([...Array.from({length:Math.ceil(end*3)+1},(_,i)=>Math.min(end,i/3)),end,center,...teeth,...(settings.mode===5?[second]:[])])].filter(x=>x>=0&&x<=end).sort((a,b)=>a-b);
 const points=xs.map(x=>[x,yFor(filterResponse(20*ratio**(x/width),settings).magnitude)]);
 const dense=end<width?{from:end,limit:detailLimit,upper:[],lower:[]}:null;
 if(dense)for(let i=0;i<=128;i++){const x=end+(width-end)*i/128,bounds=combBandBounds(20*ratio**(x/width),settings);dense.upper.push([x,yFor(bounds.high)]);dense.lower.push([x,yFor(bounds.low)]);}
 return {zero,points,dense};
}
