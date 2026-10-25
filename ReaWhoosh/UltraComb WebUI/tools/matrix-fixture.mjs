import assert from 'node:assert/strict';
export function matrixHelpers(source){
 return Object.fromEntries(['matrix_source_id','matrix_route_index','uc_matrix_convert'].map(name=>{
  const at=source.indexOf(`function ${name}(`),begin=source.indexOf('\n(',at)+2,end=source.indexOf('\n);',begin);assert(at>=0&&begin>at&&end>begin);
  const header=source.slice(at,begin),args=header.match(/function \w+\(([^)]*)\)/)[1],locals=header.match(/local\(([^)]*)\)/)[1];
  let code=source.slice(begin,end).replace(/\/\/[^\n]*/g,'').trim();
  const previous=code.lastIndexOf(';',code.lastIndexOf(';')-1);code=code.slice(0,previous+1)+'return '+code.slice(previous+1).trimStart();
  const fn=new Function(args,`const floor=Math.floor,max=Math.max,min=Math.min;${locals?'let '+locals+';':''}${code}`);return [name,fn];
 }));
}
