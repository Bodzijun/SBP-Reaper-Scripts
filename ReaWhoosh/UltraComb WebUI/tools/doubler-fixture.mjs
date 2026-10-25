// Execute the actual Doubler / non-ACF pitch-library arithmetic after explicit
// EEL syntax translation. This checks DSP behaviour, not native compilation.
import assert from 'node:assert/strict';
import {eelModulo} from './eel-arithmetic.mjs';
const names=['pitchlibInitBuffer','pitchlibReadBufferAt','pitchlibUpdateBuffer2','pitchShifter','pitchlibPrepFall','pitchShifterUpdate','uc_double_filter_init','uc_double_filter','uc_double_voice_reset','uc_double_voice_init','uc_double_voice_process','uc_double_init','uc_double_read','uc_double_process'];
function extract(source,name){
 const start=source.indexOf(`function ${name}(`);assert(start>=0,`Missing ${name}`);
 const raw=source.slice(start).replace(/\/\*[\s\S]*?\*\//g,'').replace(/\/\/[^\n]*/g,'');
 const header=raw.match(/^function[^\n]*\n(?:\s*(?:local|global|instance)\([^)]*\)\s*){3}\(/);assert(header,`Header ${name}`);
 const list=kind=>(header[0].match(new RegExp(`${kind}\\(([^)]*)\\)`,'s'))?.[1]??'').split(',').map(x=>x.trim()).filter(Boolean);
 const open=header[0].length-1;let depth=1,end=open+1;
 while(depth&&end<raw.length){if(raw[end]==='(')depth++;if(raw[end]===')')depth--;end++;}assert.equal(depth,0);
 return {args:raw.match(/^function \w+\(([^)]*)\)/)[1],instances:new Set(list('instance')),locals:list('local'),body:raw.slice(open+1,end-1)};
}
function translate(source,name){
 const d=extract(source,name);let b=d.body;
 if(name==='pitchlibInitBuffer')b=b.replace(/scopeptr < scopebuffer \? \([\s\S]*?scopebuffer\s*$/,'if(scopeptr < scopebuffer) scopeptr=scopebuffer; else if(scopeptr>=scopebuffermax) scopebuffer;');
 if(name==='pitchShifterUpdate'){
  b=b.replace(/cmax_position = acf \? \([\s\S]*?\) : 0;/,'if(acf) throw Error("ACF branch not modelled"); cmax_position=0;');
  for(const condition of ['fadeCount <= 0','fade','readHeadSpeed <= 0','crit'])b=b.replace(`${condition} ? (`,`if (${condition}) {`);
 }
 if(name==='uc_double_voice_process')b=b.replace('(was_fading && fade) ? (','if (was_fading && fade) {');
 if(name==='uc_double_process')b=b.replace('max(abs(input_l),abs(input_r))>0.0000316227766 ? (','if (max(abs(input_l),abs(input_r))>0.0000316227766) {').replace('armed ? (','if (armed) {');
 b=b.replace(/^\s*\) : \(\s*$/gm,'} else {').replace(/^\s*\);\s*$/gm,'}');
 b=b.replace(/^(\s*)(readptr < scopebuffer|readptr >= scopebuffermax|scopeptr >= scopebuffermax|quiet_count>=quiet_needed) \? ([^;]+);/gm,'$1if ($2) $3;');
 b=b.replace(/\((index\+1)\)%size/g,'eelModulo($1,size)').replace(/\(write_pos\+1\)%width_length/g,'eelModulo(write_pos+1,width_length)');assert(!b.includes('%'),`Unmodelled modulo ${name}`);
 b=b.replace(/\b([a-z_]\w*)\[([^\]]*)\]/gi,(_,ptr,index)=>`ram[${ptr}+(${index||0})]`);
 if(name==='uc_double_read')b=b.replace(/output;\s*$/,'return output;');
 b=b.replace(/\$pi/g,'math.pi').replace(/\b[a-z_]\w*\b/gi,(word,offset,text)=>{
  if(text[offset-1]==='.')return word;
  if(word==='this')return 'state';
  if(d.instances.has(word))return `state.${word}`;
  if(['max','min','ceil','floor','pow','sin','cos','sqrt','abs','exp','memset','eelModulo'].includes(word))return `math.${word}`;
  return word;
 });
 const locals=d.locals.length?`let ${d.locals.map(x=>`${x}=0`).join(',')};`:'';
 return {...d,build:new Function('math','ram',`return function(${d.args}){const state=this;${locals}\n${b}\n}`)};
}
export function compileDoubler(source){
 const definitions=Object.fromEntries(names.map(name=>[name,translate(source,name)]));
 return function create(rate=48000,semi=0,cents=9,width=.7){
  const size=Math.max(1024,Math.ceil(rate*.16/64)*64),length=Math.ceil(rate*.15)+4,widthMemory=2*size+64;
  const ram=new Float64Array(widthMemory+2*length+64);
  const math={...Object.fromEntries(['max','min','ceil','floor','pow','sin','cos','sqrt','abs','exp'].map(k=>[k,Math[k]])),pi:Math.PI,eelModulo,memset:(p,v,n)=>ram.fill(v,p,p+n)};
  function instance(){const obj={};for(const [name,d]of Object.entries(definitions)){for(const key of d.instances)if(!(key in obj))obj[key]=0;obj[name]=d.build(math,ram);}return obj;}
  const c=instance();c.left_voice=instance();c.right_voice=instance();c.left_voice.buffer=instance();c.right_voice.buffer=instance();c.left_filter=instance();c.right_filter=instance();
  c.uc_double_init(0,size,widthMemory,length,rate,50,semi,cents,width);
  const params={enabled:1,mix:.35,semi,cents,width,envelope:0,gain:0,delay:0,low:0,high:20000,invert:0};
  return {c,params,ram,size,length,step(l,r=l){c.uc_double_process(l,r,params.enabled,params.mix,params.semi,params.cents,params.width,params.envelope,params.gain,params.delay,params.low,params.high,params.invert);return [c.out_l,c.out_r];}};
 };
}
