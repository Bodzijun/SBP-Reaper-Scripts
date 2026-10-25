import assert from 'node:assert/strict';
export function compileEnvelope(source,name){
 const at=source.indexOf(`function ${name}(`);assert(at>=0);
 const raw=source.slice(at,source.indexOf('\n);',at)+3),args=raw.match(/^function \w+\(([^)]*)\)/)[1];
 const instances=raw.match(/instance\(([^)]*)\)/s)[1].split(',').map(v=>v.trim()).filter(Boolean),locals=raw.match(/local\(([^)]*)\)/s)[1].split(',').map(v=>v.trim()).filter(Boolean);
 let body=raw.slice(raw.indexOf('\n(',raw.indexOf('global('))+2,raw.lastIndexOf('\n);')).replace(/\/\/[^\n]*/g,'');
 body=body.replace(/^\s*mode==0 \? \(([^\n]+)\) : \(\s*$/gm,'if(mode==0){$1} else {')
  .replace(/^(\s*)([^\n?]+?) \? \(([^\n]+)\);\s*$/gm,'$1if($2){$3}')
  .replace(/\) : stage==([23456]) \? \(/g,'} else if(stage==$1){')
  .replace(/^(\s*)([^\n?]+?) \? \(\s*$/gm,'$1if($2){')
  .replace(/^\s*\);\s*$/gm,'}')
  .replace('detector<threshold*0.5 ? armed=1;','if(detector<threshold*0.5) armed=1;');
 assert(!body.includes('%'));
 body=body.replace(/\$pi/g,'Math.PI').replace(/\b[a-z_]\w*\b/gi,(word,offset,text)=>{
  if(text[offset-1]==='.')return word;if(instances.includes(word))return `state.${word}`;
  if(['max','min','pow','sin','floor','abs','exp'].includes(word))return `Math.${word}`;return word;
 });
 const fn=new Function(args,`const state=this;${locals.length?'let '+locals.map(v=>v+'=0').join(',')+';':''}${body}`);
 return {instances,fn};
}
export function createAdr(source,rate=48000,settings={}){
 const init=compileEnvelope(source,'uc_adr_init'),process=compileEnvelope(source,'uc_adr_process'),c={};
 for(const key of [...init.instances,...process.instances])c[key]=0;
 const p={mode:0,threshold:-24,attack:20,decay:250,level:.5,release:400,curve:0,trigger:0,...settings};
 init.fn.call(c,rate,p.attack,p.decay,p.level,p.release,p.attackCurve??p.curve,p.decayCurve??p.curve,p.releaseCurve??p.curve,p.trigger);
 return {c,p,step(level=0){process.fn.call(c,level,p.mode,p.threshold,p.attack,p.decay,p.level,p.release,4**(p.attackCurve??p.curve),4**(p.decayCurve??p.curve),4**(p.releaseCurve??p.curve),p.loopDirection??0,p.trigger);return c.output;}};
}
