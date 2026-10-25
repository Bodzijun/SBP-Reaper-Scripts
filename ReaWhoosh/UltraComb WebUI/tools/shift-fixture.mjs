// Source-executed EEL arithmetic, not a substitute for native compilation.
import assert from 'node:assert/strict';
const legacyInit=`function uc_shift_init(rate, initial_hz, enabled)
instance(sample_rate, phase, current_hz, current_mix, slew, limit_hz, out_l, out_r)
local() global()
(
 sample_rate=max(1,rate);limit_hz=min(20000,sample_rate*0.45);
 slew=1-exp(-1/(0.01*sample_rate));phase=out_l=out_r=0;
 current_hz=max(-limit_hz,min(limit_hz,initial_hz));
 current_mix=max(0,min(1,enabled))*(abs(current_hz)>0.000001);
 this.left.uc_shift_channel_reset();this.right.uc_shift_channel_reset();
);`;
const legacyProcess=`function uc_shift_process(input_l, input_r, target_hz, enabled)
instance(sample_rate, phase, current_hz, current_mix, slew, limit_hz, out_l, out_r)
local(target, cosine, sine, shifted_l, shifted_r) global()
(
 target=max(-limit_hz,min(limit_hz,target_hz));
 current_hz+=(target-current_hz)*slew;
 current_mix+=(max(0,min(1,enabled))*(abs(target)>0.000001)-current_mix)*slew;
 phase+=current_hz/sample_rate;phase-=floor(phase);
 cosine=cos(2*$pi*phase);sine=sin(2*$pi*phase);
 this.left.uc_shift_channel_process(input_l);this.right.uc_shift_channel_process(input_r);
 shifted_l=this.left.real*cosine-this.left.imag*sine;
 shifted_r=this.right.real*cosine-this.right.imag*sine;
 out_l=input_l+(shifted_l-input_l)*current_mix;
 out_r=input_r+(shifted_r-input_r)*current_mix;
);`;
export function compileShift(source,{legacy=false}={}){
 const names=['uc_shift_ap2_reset','uc_shift_ap2','uc_shift_channel_reset','uc_shift_channel_process','uc_shift_init','uc_shift_process'];
 const definitions=names.map(name=>{
  const start=source.indexOf(`function ${name}(`);assert(start>=0);
  const raw=legacy&&name==='uc_shift_init'?legacyInit:legacy&&name==='uc_shift_process'?legacyProcess:source.slice(start,source.indexOf('\n);',start)+3);
  const args=raw.match(/^function \w+\(([^)]*)\)/)[1],instances=new Set(raw.match(/instance\(([^)]*)\)/s)[1].split(',').map(x=>x.trim()).filter(Boolean));
  const locals=raw.match(/local\(([^)]*)\)/s)[1].split(',').map(x=>x.trim()).filter(Boolean);
  let body=raw.slice(raw.indexOf('\n(',raw.indexOf('global('))+2,raw.lastIndexOf('\n);')).replace(/\/\/[^\n]*/g,'').replaceAll('^','**');
  if(name==='uc_shift_ap2')body=body.replace(/output;\s*$/,'return output;');
  body=body.replace(/\$pi/g,'Math.PI').replace(/\b[a-z_]\w*\b/gi,(word,offset,text)=>{
   if(text[offset-1]==='.')return word;if(word==='this')return 'state';if(instances.has(word))return `state.${word}`;
   if(['max','min','sin','cos','floor','abs','exp'].includes(word))return `Math.${word}`;return word;
  });
  return {name,instances,fn:new Function(args,`const state=this;${locals.length?'let '+locals.map(x=>`${x}=0`).join(',')+';':''}${body}`)};
 });
 function instance(){const o={};for(const {name,instances,fn}of definitions){for(const key of instances)o[key]=0;o[name]=fn;}return o;}
 return function create(rate=48000,hz=0,offset=0,sideband=1,mix=1,enabled=1){
  const c=instance();c.left=instance();c.right=instance();for(const ch of [c.left,c.right])for(const prefix of ['a','b'])for(let i=0;i<4;i++)ch[prefix+i]=instance();
  c.uc_shift_init(rate,hz,enabled,offset,sideband,mix);const p={hz,offset,sideband,mix,enabled};
  return {c,p,step(l,r=l){c.uc_shift_process(l,r,p.hz,p.enabled,p.offset,p.sideband,p.mix);return [c.out_l,c.out_r];}};
 };
}
