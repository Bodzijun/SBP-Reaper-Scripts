// Execute the actual EEL filter arithmetic after bounded syntax translation.
import assert from 'node:assert/strict';
import {eelModulo} from './eel-arithmetic.mjs';
const names=['uc_filter_channel_reset','uc_filter_channel','uc_filter_init','uc_filter_comb_init','uc_filter_comb_read','uc_filter_comb_process','uc_filter_process','uc_comb_feed_init','uc_comb_feed_process'];
function compile(source,name){
 const start=source.indexOf(`function ${name}(`);assert(start>=0);
 const raw=source.slice(start,source.indexOf('\n);',start)+3),args=raw.match(/^function \w+\(([^)]*)\)/)[1];
 const list=kind=>raw.match(new RegExp(kind+'\\(([^)]*)\\)'))[1].split(',').map(x=>x.trim()).filter(Boolean),instances=list('instance'),locals=list('local');
 const header=raw.match(/^function[^\n]*\n(?:\s*(?:local|global|instance)\([^)]*\)\s*){3}\(/);assert(header,name);
 let code=raw.slice(header[0].length,raw.lastIndexOf('\n);')).replace(/\/\/[^\n]*/g,'');
 code=code.replace('write_pos>=buffer_size ? write_pos=0;','if(write_pos>=buffer_size) write_pos=0;').replace('read_pos>=size ? read_pos=0;','if(read_pos>=size) read_pos=0;')
  .replace(/^(\s*)(phase>=1) \? \(([^\n]+)\);\s*$/gm,'$1if($2){$3}')
  .replace(/^(\s*)(abs\(ic[12]\)<0\.000000000001|lfo_shape==[1-5]) \? ([^\n]+);/gm,'$1if($2){$3;}');
 code=code.replace(/\(index\+1\)%size/g,'eelModulo(index+1,size)');assert(!code.includes('%'));
 code=code.replace(/\b([a-z_]\w*)\[([^\]]*)\]/gi,(_,ptr,index)=>`ram[${ptr}+(${index||0})]`);
 if(name==='uc_filter_comb_read')code=code.replace(/output;\s*$/,'return output;');
 if(name==='uc_comb_feed_process')code=code.replace(/position;\s*$/,'return position;');
 code=code.replace(/\$pi/g,'math.pi').replace(/\b[a-z_]\w*\b/gi,(word,offset,text)=>{
  if(text[offset-1]==='.')return word;if(word==='this')return 'state';if(instances.includes(word))return 'state.'+word;
  if(['max','min','floor','pow','sin','cos','tan','log','sqrt','abs','exp','memset','rand','eelModulo'].includes(word))return 'math.'+word;return word;
 });
 return {instances,build:new Function('math','ram',`return function(${args}){const state=this;${locals.length?'let '+locals.map(x=>x+'=0').join(',')+';':''}${code}}`)};
}
export function compileFilter(source){
 const definitions=Object.fromEntries(names.map(n=>[n,compile(source,n)]));
 return function create(rate=48000,mode=0,cutoff=2000,resonance=.2){
  const size=Math.ceil(rate/20)+4,ram=new Float64Array(2*size);
  const math={...Object.fromEntries(['max','min','floor','pow','sin','cos','tan','log','sqrt','abs','exp'].map(k=>[k,Math[k]])),pi:Math.PI,eelModulo,rand:()=>.25,memset:(p,v,n)=>ram.fill(v,p,p+n)};
  function instance(){const state={};for(const [name,d]of Object.entries(definitions)){for(const key of d.instances)state[key]??=0;state[name]=d.build(math,ram);}return state;}
  const c=instance();for(const key of ['left','right','vowel_left','vowel_right','comb_motion'])c[key]=instance();
  c.uc_filter_init(rate,cutoff,resonance,mode);c.uc_filter_comb_init(0,size);
  const p={enabled:1,mode,cutoff,resonance,drive:0,mix:1,rate:.5,depth:0,shape:0};
  return {c,p,ram,size,step(l,r=l){c.uc_filter_process(l,r,p.enabled,p.mode,p.cutoff,p.resonance,p.drive,p.mix,p.rate,p.depth,p.shape);return [c.out_l,c.out_r];}};
 };
}
