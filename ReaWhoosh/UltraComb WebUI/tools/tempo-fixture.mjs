import assert from 'node:assert/strict';
export function syncFunctions(source){
 const dep={};
 for(const name of ['uc_sync_beats','uc_sync_rate','uc_sync_ms','uc_matrix_lfo_process','uc_matrix_lfo_timing']){
  const start=source.indexOf(`function ${name}(`),begin=source.indexOf('\n(',start)+2,end=source.indexOf('\n);',begin),head=source.slice(start,begin),args=head.match(/^function \w+\(([^)]*)\)/)[1],locals=head.match(/local\(([^)]*)\)/)?.[1]||'',instances=(head.match(/instance\(([^)]*)\)/)?.[1]||'').split(',').map(v=>v.trim());assert(start>=0&&end>begin);
  let code=source.slice(begin,end).replace(/\/\/[^\n]*/g,'').replace(/^(\s*)(synced && running[^?]+)\? \(\s*$/gm,'$1if($2){').replace(/^\s*\);\s*$/gm,'}').replace(/\$pi/g,'Math.PI');
  if(name.startsWith('uc_sync_'))code=code.replace(/\n (max\([^\n]+|value);\s*$/,(_,v)=>'\n return '+v+';');
  code=code.replace(/\b[a-z_]\w*\b/gi,(word,offset,text)=>text[offset-1]==='.'?word:instances.includes(word)?`this.${word}`:['max','min','pow','exp','sin','floor','abs'].includes(word)?`Math.${word}`:word);
  dep[name]=new Function(...Object.keys(dep),`return function(${args}){${locals?'let '+locals.split(',').map(v=>v.trim()+'=0').join(',')+';':''}${code}}`)(...Object.values(dep));
 }
 return dep;
}
