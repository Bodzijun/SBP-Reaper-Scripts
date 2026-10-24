import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import {interpolateParameter,randomizeEntries} from '../webui/bulk-model.mjs';
import {modulationShapeFor} from '../webui/modulation-view.mjs';
import {modulationGroups} from '../webui/model.mjs';
const source=fs.readFileSync(new URL('../sbp_ultraComb_webui.jsfx',import.meta.url),'utf8');
const {parameters,random:policy}=JSON.parse(fs.readFileSync(new URL('../webui/parameters.json',import.meta.url),'utf8'));
const banks=[...source.matchAll(/^(MORPH_\w+|RANDOM_\w+|UI_DEFAULT)=(\d+);$/gm)].map(m=>[m[1],+m[2]]).filter(([key])=>key!=='MORPH_COUNT');
assert.equal(Object.keys(policy).length,135);
const protectedIds=[1,2,3,22,47,48,49,51,59,65,66,67,73,83,84,85,86,87,88,113,118,123];
for(const p of parameters){const m=policy[p.id];assert.deepEqual([m.MORPH_LO,m.MORPH_HI,m.MORPH_STEP],[p.min,p.max,p.step]);assert.equal(m.MORPH_DISCRETE,+Boolean(p.options));assert.equal(m.MORPH_ALLOWED,+!protectedIds.includes(p.id));}
const ranges=banks.map(([name,address])=>({name,start:address,end:address+256}));
for(const a of ranges){assert(a.start>=244000&&a.end<262144);for(const b of ranges)if(a!==b)assert(a.end<=b.start||b.end<=a.start,`${a.name} overlaps ${b.name}`);}
// Translate only the EEL control-flow syntax in the actual bulk-edit bodies.
// This is an arithmetic/control-policy test, not a native compiler substitute.
let loopId=0;
function loops(code){
 const start=code.indexOf('loop(');if(start<0)return code;
 let depth=1,comma=-1,end=start+5;
 for(;end<code.length;end++){const ch=code[end];if(ch==='(')depth++;if(ch===')'&&!--depth)break;if(ch===','&&depth===1&&comma<0)comma=end;}
 assert(comma>start&&depth===0);const id=loopId++,count=code.slice(start+5,comma),body=loops(code.slice(comma+1,end));
 return code.slice(0,start)+`for(let loop${id}=0,count${id}=${count};loop${id}<count${id};loop${id}++){${body}}`+loops(code.slice(end+1));
}
function translate(code){
 code=loops(code.replace(/\/\/[^\n]*/g,''));
 code=code.replace(/^(\s*)([^\n]+?)\s*\?\s*\(\s*$/gm,'$1if ($2) {').replace(/^\s*\) : \(\s*$/gm,'} else {').replace(/^\s*\);\s*$/gm,'}');
 code=code.replace(/^(\s*)([^\n?=]+(?:==[^\n?]+)?)\s+\?\s+([^\n:]+);\s*$/gm,'$1if ($2) { $3; }');
 code=code.replace(/i==44 && slider113>0.5 \? (value=.*);/g,'if(i==44 && slider113>0.5){$1;}');
 code=code.replace(/2\^(random_scope|64)/g,'pow(2,$1)').replace(/\bslider(\d+)\b/g,'sliders[$1]').replace(/\bslider\(([^()]*)\)/g,'sliders[$1]');
 for(const name of [...banks.map(b=>b[0]),'destination','endpoint'])code=code.replace(new RegExp('\\b'+name+'\\[([^\\]]+)\\]','g'),`ram[${name}+($1)]`);
 return code;
}
const ram=new Float64Array(263000),sliders=new Float64Array(136),c=vm.createContext({ram,sliders,MORPH_COUNT:135,Math,max:Math.max,min:Math.min,abs:Math.abs,floor:Math.floor,pow:Math.pow,rand:()=>.73,sliderchange:()=>{},slider_automate:()=>{},notify_ui_slider:()=>{}});
Object.assign(c,Object.fromEntries(banks));for(const p of parameters)sliders[p.id]=p.default;
for(const [id,meta]of Object.entries(policy))for(const [key,value]of Object.entries(meta))ram[c[key]+Number(id)-1]=value;
for(const name of ['finish_bulk_touch','store_morph_snapshot','set_bulk_slider','interpolate_parameter','morph_matrix_route','apply_morph','randomize_parameters']){
 const at=source.indexOf(`function ${name}(`),firstLine=source.slice(at,source.indexOf('\n',at)),inline=firstLine.endsWith('(');
 const begin=inline?at+firstLine.length:source.indexOf('\n(',at)+2,header=source.slice(at,begin),body=source.slice(begin,source.indexOf('\n);',begin));
 const args=header.match(/function \w+\(([^)]*)\)/)[1],locals=header.match(/local\(([^)]*)\)/)?.[1];
 let code=translate(body);if(name==='interpolate_parameter')code='return '+code.trim();
 vm.runInContext(`${name}=function(${args}){${locals?'let '+locals+';':''}${code}}`,c);
}
const get=id=>sliders[id];
for(const source of modulationGroups.slice(0,2)){
 for(const shape of [0,1,2,3]){sliders[source.shape]=shape;sliders[source.on]=0;assert.equal(modulationShapeFor(source,get),'none');sliders[source.on]=1;assert.equal(modulationShapeFor(source,get),['sine','saw','square','random'][shape]);}
}
// Store full A/B snapshots, including the last slider, through the real function.
sliders[132]=.1;sliders[134]=10;sliders[135]=15;sliders[130]=0;sliders[122]=2;sliders[69]=5;sliders[89]=1;sliders[90]=9;sliders[91]=.8;
c.store_morph_snapshot(c.MORPH_A);
sliders[132]=10;sliders[134]=90;sliders[135]=300;sliders[130]=3;sliders[122]=30;sliders[69]=45;sliders[89]=4;sliders[90]=12;sliders[91]=-.6;
c.store_morph_snapshot(c.MORPH_B);
for(const position of [0,.25,.49,.5,.51,.75,1,0]){
 const before=sliders[88];c.apply_morph(position,0);assert.equal(sliders[88],before,'Morph must never touch the SDK transport');
 assert(Math.abs(sliders[132]-(.1*100**position))<.011);assert(Math.abs(sliders[134]-(10+80*position))<.051);
 assert.equal(sliders[130],position<.5?0:3,'Curve must switch directly, without intermediate modes');
 assert.equal(sliders[89],position<.5?1:4);assert.equal(sliders[90],position<.5?9:12);
 const amount=position<.5?.8*(1-2*position):-.6*(2*position-1);assert(Math.abs(sliders[91]-amount)<.0051);
 assert(Math.abs(sliders[69]-(5+40*position))<.051);assert(Math.abs(sliders[122]-(2+28*position))<.051);
}
// Same matrix link: signed depth interpolates directly through zero.
ram[c.MORPH_B+88]=1;ram[c.MORPH_B+89]=9;c.apply_morph(.5,0);assert(Math.abs(sliders[91]-.1)<1e-10);
// Frontend and actual native randomizer must agree, including scope/enum rules.
for(const mode of [0,1])for(const scope of [0,1,2,3])for(const strength of [0,.35,.5,1]){
 for(const p of parameters)sliders[p.id]=p.default;sliders[113]=mode;sliders[89]=1;sliders[90]=9;sliders[91]=.3;sliders[66]=strength;sliders[67]=scope;
 const before=sliders.slice(),expected=randomizeEntries(policy,get,strength,scope,()=>.73);c.randomize_parameters();
 for(const [id,value]of expected)assert(Math.abs(sliders[id]-value)<1e-8,`Native/Web random mismatch at ${id}`);
 const touched=new Set(expected.map(e=>e[0]));for(let id=1;id<=135;id++)if(!touched.has(id))assert.equal(sliders[id],before[id],`Unexpected random change at ${id}`);
 for(const p of parameters)assert(sliders[p.id]>=p.min&&sliders[p.id]<=p.max);
}
for(const id of [68,69,70,71,72,114,115,119,120,121,122,124,125,126,127,128,129,130,131,132,133,134,135])assert(policy[id].MORPH_ALLOWED&&policy[id].RANDOM_ALLOWED,`New control ${id} missing from bulk edits`);
assert.equal(interpolateParameter(policy[130],0,3,.49),0);assert.equal(interpolateParameter(policy[130],0,3,.5),3);
const migrationStart=source.indexOf('morph_snapshot_size==64 || morph_snapshot_size==84');
const migrationCode=translate(source.slice(migrationStart,source.indexOf('// One typed policy row',migrationStart)));
const migrate=new vm.Script(migrationCode);c.memcpy=(destination,origin,count)=>ram.copyWithin(destination,origin,origin+count);c.memset=(destination,value,count)=>ram.fill(value,destination,destination+count);
for(const count of [64,84]){
 for(let i=0;i<count;i++){ram[240000+i]=i+.1;ram[240128+i]=i+.2;}
 c.morph_snapshot_size=count;c.morph_storage_initialized=1;migrate.runInContext(c);
 for(let i=0;i<135;i++){assert.equal(ram[c.MORPH_A+i],i<count?i+.1:sliders[i+1]);assert.equal(ram[c.MORPH_B+i],i<count?i+.2:sliders[i+1]);}
 ram[c.MORPH_A+134]=123;sliders[135]=321;migrate.runInContext(c);assert.equal(ram[c.MORPH_A+134],123,'Playback reinitialization must retain stored endpoints');
}
// Exercise the actual versioned A/B serialization, including old 64/84-value records.
const serialStart=source.indexOf('file_avail(0) != 0 ?',source.indexOf('@serialize'));
let serialize=translate(source.slice(serialStart,source.indexOf('hide_native_sliders();',serialStart)));
serialize=serialize.replace(/file_var\(0,\s*(\w+)\)/g,'$1=file_var(0,$1)');
const program=new vm.Script(serialize);
c.ui_native_visible=0;
function file(read,values=[]){let position=0;const output=[];c.file_avail=()=>read?values.length-position:-1;c.file_var=(index,value)=>read?values[position++]:(output.push(value),value);c.file_mem=(index,address,count)=>{for(let i=0;i<count;i++)read?ram[address+i]=values[position++] : output.push(ram[address+i]);};program.runInContext(c);return {position,output};}
for(const [version,count]of [[1,64],[2,84],[3,135]]){
 const a=Array.from({length:count},(_,i)=>i+.1),b=a.map(x=>x+.1),values=[1,version,1,1,.25,.35,0,...a,...b];
 const read=file(true,values);assert.equal(read.position,values.length);assert.equal(c.morph_snapshot_size,135);assert.equal(c.ui_native_visible,0);
 for(let i=0;i<135;i++){assert.equal(ram[c.MORPH_A+i],i<count?a[i]:sliders[i+1]);assert.equal(ram[c.MORPH_B+i],i<count?b[i]:sliders[i+1]);}
}
const saved=file(false).output;assert.equal(saved[1],3);assert.equal(saved.length,7+135*2);assert.equal(file(true,saved).position,saved.length);
console.log('PASS: 135 typed policy rows, nonoverlapping storage, identical Off LFO models, actual native full A/B/route morph, native/Web random parity across scopes, exclusions and v1/v2/v3 serialization. Native REAPER acceptance remains separate.');
