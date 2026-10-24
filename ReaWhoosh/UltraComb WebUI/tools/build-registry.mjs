import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const source=fs.readFileSync(path.join(root,'sbp_ultraComb_webui.jsfx'),'utf8');
const parameters=[...source.matchAll(/^slider(\d+):([^<]+)<([^>]+)>-?([^\r\n]+)$/gm)]
  .filter(m=>Number(m[1])!==88).map(m=>{
    const r=m[3].match(/^([^,]+),([^,]+),([^,{]+)(?:\{(.*)\})?$/);
    if(!r)throw Error('Unsupported range '+m[1]);
    return {id:+m[1],index:+m[1]-1,default:+m[2],min:+r[1],max:+r[2],step:+r[3],name:m[4],options:r[4]?.split(',')||null};
  });
if(parameters.length!==134)throw Error('Expected 134 audio/control parameters');
const lines=source.split('\n').filter(l=>/^MORPH_LO\[/.test(l));
const random={};
for(const line of lines){
  const fields={};for(const m of line.matchAll(/(\w+)\[(\d+)\]=([^;]+);/g))fields[m[1]]=Number(m[3]);
  const id=Number(line.match(/\[(\d+)\]/)[1])+1;random[id]=fields;
}
const count=Number(source.match(/^MORPH_COUNT=(\d+);/m)?.[1]);
if(count!==Math.max(...parameters.map(p=>p.id))||Object.keys(random).length!==count)throw Error('Bulk policy does not cover the native slider range');
for(const p of parameters){const m=random[p.id];if(!m||m.MORPH_LO!==p.min||m.MORPH_HI!==p.max||m.MORPH_STEP!==p.step||m.MORPH_DISCRETE!==Number(Boolean(p.options))||![0,1].includes(m.RANDOM_ALLOWED))throw Error('Missing/stale bulk policy for parameter '+p.id);}
fs.writeFileSync(path.join(root,'webui','parameters.json'),JSON.stringify({parameters,random},null,2)+'\n');
console.log('Generated registry: '+parameters.length+' stable native parameters');
