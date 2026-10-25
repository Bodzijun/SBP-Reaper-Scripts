import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import {interpolateParameter,randomizeEntries} from '../webui/bulk-model.mjs';
import {modulationShapeFor} from '../webui/modulation-view.mjs';
import {modulationGroups} from '../webui/model.mjs';
import {matrixRoutes,scopeNames} from '../webui/matrix-model.mjs';
import {matrixHelpers} from './matrix-fixture.mjs';
const source=fs.readFileSync(new URL('../sbp_ultraComb_webui.jsfx',import.meta.url),'utf8');
const {parameters,random:policy}=JSON.parse(fs.readFileSync(new URL('../webui/parameters.json',import.meta.url),'utf8'));
const banks=[...source.matchAll(/^(MORPH_\w+|RANDOM_\w+|UI_DEFAULT)=(\d+);$/gm)].map(m=>[m[1],+m[2]]).filter(([key])=>key!=='MORPH_COUNT');
const total=214;
assert.equal(Object.keys(policy).length,total);
const protectedIds=[1,2,3,22,42,45,46,47,48,49,51,59,65,66,67,73,83,84,85,86,87,88,113,116,118,123,188];
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
 code=code.replace(/2\^(random_scope|64|slider188)/g,'pow(2,$1)').replace(/\bslider(\d+)\b/g,'sliders[$1]').replace(/\bslider\(([^()]*)\)/g,'sliders[$1]');
 for(const name of [...banks.map(b=>b[0]),'destination','endpoint'])code=code.replace(new RegExp('\\b'+name+'\\[([^\\]]+)\\]','g'),`ram[${name}+($1)]`);
 return code;
}
const ram=new Float64Array(263000),sliders=new Float64Array(total+1),c=vm.createContext({ram,sliders,MORPH_COUNT:total,Math,max:Math.max,min:Math.min,abs:Math.abs,floor:Math.floor,pow:Math.pow,rand:()=>.73,sliderchange:()=>{},slider_automate:()=>{},notify_ui_slider:()=>{}});
Object.assign(c,Object.fromEntries(banks));for(const p of parameters)sliders[p.id]=p.default;
Object.assign(c,matrixHelpers(source));
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
sliders[136]=-1;sliders[132]=.1;sliders[134]=10;sliders[135]=15;sliders[130]=0;sliders[122]=2;sliders[69]=5;sliders[89]=1;sliders[90]=9;sliders[91]=.8;
sliders[137]=-20;sliders[138]=-1;sliders[139]=.2;
sliders[140]=1;sliders[141]=0;sliders[142]=-40;sliders[143]=10;sliders[144]=100;sliders[145]=.1;sliders[146]=50;sliders[147]=-1;sliders[189]=.8;sliders[190]=-.6;sliders[191]=0;
c.store_morph_snapshot(c.MORPH_A);
sliders[136]=1;sliders[132]=10;sliders[134]=90;sliders[135]=300;sliders[130]=3;sliders[122]=30;sliders[69]=45;sliders[89]=4;sliders[90]=12;sliders[91]=-.6;
sliders[137]=30;sliders[138]=1;sliders[139]=.9;
sliders[140]=3;sliders[141]=1;sliders[142]=-10;sliders[143]=1000;sliders[144]=2000;sliders[145]=.9;sliders[146]=1000;sliders[147]=1;sliders[189]=-.4;sliders[190]=.9;sliders[191]=1;
c.store_morph_snapshot(c.MORPH_B);
for(const position of [0,.25,.49,.5,.51,.75,1,0]){
 const before=sliders[88];c.apply_morph(position,0);assert.equal(sliders[88],before,'Morph must never touch the SDK transport');
 assert(Math.abs(sliders[132]-(.1*100**position))<.011);assert(Math.abs(sliders[134]-(10+80*position))<.051);
 assert(Math.abs(sliders[136]-(-1+2*position))<.0051);
 assert(Math.abs(sliders[137]-(-20+50*position))<.051);
 assert(Math.abs(sliders[138]-(-1+2*position))<.0051);
 assert(Math.abs(sliders[139]-(.2+.7*position))<.0051);
 assert.equal(sliders[140],position<.5?1:3);assert.equal(sliders[141],position<.5?0:1);
 assert(Math.abs(sliders[143]-10*100**position)<=.51);assert(Math.abs(sliders[145]-(.1+.8*position))<.0051);assert(Math.abs(sliders[147]-(-1+2*position))<.0051);
 assert(Math.abs(sliders[189]-(.8-1.2*position))<.0051);assert(Math.abs(sliders[190]-(-.6+1.5*position))<.0051);
 assert.equal(sliders[191],position<.5?0:1,'Loop direction must switch as a discrete ADR parameter');
 assert.equal(sliders[130],position<.5?0:3,'Curve must switch directly, without intermediate modes');
 assert.equal(sliders[89],position<.5?1:4);assert.equal(sliders[90],position<.5?9:12);
 const amount=position<.5?.8*(1-2*position):-.6*(2*position-1);assert(Math.abs(sliders[91]-amount)<.0051);
 assert(Math.abs(sliders[69]-(5+40*position))<.051);assert(Math.abs(sliders[122]-(2+28*position))<.051);
}
for(const id of [192,193,194,211])assert(!policy[id].RANDOM_ALLOWED&&policy[id].MORPH_ALLOWED);
for(const [free,sync,owner]of [[15,195,192],[132,196,193],[143,197,194],[144,198,194],[146,199,194],[203,212,211],[204,213,211],[206,214,211]]){assert.equal(policy[free].RANDOM_SYNC,-owner);assert.equal(policy[sync].RANDOM_SYNC,owner);assert(policy[sync].MORPH_ALLOWED&&policy[sync].RANDOM_ALLOWED);}
// Same matrix link: signed depth interpolates directly through zero.
ram[c.MORPH_B+88]=1;ram[c.MORPH_B+89]=9;c.apply_morph(.5,0);assert(Math.abs(sliders[91]-.1)<1e-10);
// Frontend and actual native randomizer must agree, including scope/enum rules.
for(const timing of [0,1])for(const mode of [0,1])for(let scope=0;scope<scopeNames.length;scope++)for(const strength of [0,.35,.5,1]){
 for(const p of parameters)sliders[p.id]=p.default;sliders[192]=sliders[193]=sliders[194]=sliders[211]=timing;sliders[113]=mode;sliders[89]=1;sliders[90]=9;sliders[91]=.3;sliders[66]=strength;sliders[67]=scope;
 const before=sliders.slice(),expected=randomizeEntries(policy,get,strength,scope,()=>.73);c.randomize_parameters();
 for(const [id,value]of expected)assert(Math.abs(sliders[id]-value)<1e-8,`Native/Web random mismatch at ${id}`);
 const touched=new Set(expected.map(e=>e[0]));for(let id=1;id<=total;id++)if(!touched.has(id))assert.equal(sliders[id],before[id],`Unexpected random change at ${id}`);
 for(const p of parameters)assert(sliders[p.id]>=p.min&&sliders[p.id]<=p.max);
}
for(const id of [68,69,70,71,72,114,115,119,120,121,122,124,125,126,127,128,129,130,131,132,133,134,135,136,137,138,139,140,142,143,144,145,146,147])assert(policy[id].MORPH_ALLOWED&&policy[id].RANDOM_ALLOWED,`New control ${id} missing from bulk edits`);
assert.equal(policy[141].RANDOM_ALLOWED,0);assert.equal(policy[141].MORPH_ALLOWED,1);
assert.equal(interpolateParameter(policy[130],0,3,.49),0);assert.equal(interpolateParameter(policy[130],0,3,.5),3);
const migrationStart=source.indexOf('morph_snapshot_size==64 || morph_snapshot_size==84');
const migrationCode=translate(source.slice(migrationStart,source.indexOf('// One typed policy row',migrationStart)));
const migrate=new vm.Script(migrationCode);c.memcpy=(destination,origin,count)=>ram.copyWithin(destination,origin,origin+count);c.memset=(destination,value,count)=>ram.fill(value,destination,destination+count);
for(const count of [64,84]){
 for(let i=0;i<count;i++){ram[240000+i]=i+.1;ram[240128+i]=i+.2;}
 c.morph_snapshot_size=count;c.morph_storage_initialized=1;migrate.runInContext(c);
 for(let i=0;i<total;i++){assert.equal(ram[c.MORPH_A+i],i<count?i+.1:sliders[i+1]);assert.equal(ram[c.MORPH_B+i],i<count?i+.2:sliders[i+1]);}
 ram[c.MORPH_A+134]=123;sliders[135]=321;migrate.runInContext(c);assert.equal(ram[c.MORPH_A+134],123,'Playback reinitialization must retain stored endpoints');
}
// Exercise the actual versioned A/B serialization, including old 64/84-value records.
const serialStart=source.indexOf('file_avail(0) != 0 ?',source.indexOf('@serialize'));
let serialize=translate(source.slice(serialStart,source.indexOf('hide_native_sliders();',serialStart)));
serialize=serialize.replace(/file_var\(0,\s*(\w+)\)/g,'$1=file_var(0,$1)');
const program=new vm.Script(serialize);
c.ui_native_visible=0;
function file(read,values=[]){let position=0;const output=[];c.file_avail=()=>read?values.length-position:-1;c.file_var=(index,value)=>read?values[position++]:(output.push(value),value);c.file_mem=(index,address,count)=>{for(let i=0;i<count;i++)read?ram[address+i]=values[position++] : output.push(ram[address+i]);};program.runInContext(c);return {position,output};}
for(const [version,count]of [[1,64],[2,84],[3,135],[4,136],[5,139],[6,147],[7,188],[8,190],[9,191],[10,199],[11,total]]){
 const a=Array.from({length:count},(_,i)=>i+.1),b=a.map(x=>x+.1),scope=version===7?17:0,values=[1,version,1,1,.25,.35,scope,...a,...b];
 const read=file(true,values);assert.equal(read.position,values.length);assert.equal(c.morph_snapshot_size,total);assert.equal(c.ui_native_visible,0);assert.equal(c.random_scope,scope);
 for(let i=0;i<total;i++){const legacyCurve=version<8&&i>=188&&i<=189,legacyDirection=version<9&&i===190;assert.equal(ram[c.MORPH_A+i],legacyDirection?0:legacyCurve?(146<count?a[146]:sliders[147]):i<count?a[i]:sliders[i+1]);assert.equal(ram[c.MORPH_B+i],legacyDirection?0:legacyCurve?(146<count?b[146]:sliders[147]):i<count?b[i]:sliders[i+1]);}
}
const saved=file(false).output;assert.equal(saved[1],11);assert.equal(saved.length,7+total*2);assert.equal(file(true,saved).position,saved.length);
// Scoped Morph must leave other modules/routes untouched.
for(const p of parameters)sliders[p.id]=p.default;
sliders[147]=-1;sliders[137]=-100;c.store_morph_snapshot(c.MORPH_A);sliders[147]=1;sliders[137]=100;c.store_morph_snapshot(c.MORPH_B);
sliders[188]=17;sliders[147]=0;sliders[137]=42;c.apply_morph(1,0);assert.equal(sliders[147],1);assert.equal(sliders[137],42);assert.equal(sliders[188],17);
// All 16 route identities include polarity; changing it fades depth through zero.
for(const r of matrixRoutes){
 for(const p of parameters)sliders[p.id]=p.default;
 sliders[r.source]=5;sliders[r.target]=57;sliders[r.amount]=.8;sliders[r.polarity]=0;c.store_morph_snapshot(c.MORPH_A);
 sliders[r.amount]=.6;sliders[r.polarity]=2;c.store_morph_snapshot(c.MORPH_B);
 sliders[188]=18;c.apply_morph(.5,0);assert.equal(sliders[r.amount],0);assert.equal(sliders[r.polarity],2);c.apply_morph(1,0);assert(Math.abs(sliders[r.amount]-.6)<1e-10);
 sliders[188]=17;sliders[r.amount]=.23;c.apply_morph(0,0);assert.equal(sliders[r.amount],.23,'ADR-only Morph must not alter Matrix routes');
}
for(const id of [147,189,190]){assert(policy[id].RANDOM_ALLOWED&&policy[id].MORPH_ALLOWED);assert(policy[id].RANDOM_GROUP&2**17,'Every ADR curve must belong to ADR scope');}
for(const id of [42,45,46,116])assert(!policy[id].RANDOM_ALLOWED&&!policy[id].MORPH_ALLOWED,'Retired Motion must not be changed by Random or Morph');
// ADR 2 scope must not alter ADR 1, routes, or its independent timing bank.
for(const p of parameters)sliders[p.id]=p.default;sliders[200]=2;sliders[203]=10;sliders[207]=-1;sliders[211]=0;sliders[212]=1;c.store_morph_snapshot(c.MORPH_A);sliders[200]=3;sliders[203]=1000;sliders[207]=1;sliders[211]=1;sliders[212]=21;c.store_morph_snapshot(c.MORPH_B);sliders[143]=333;sliders[188]=21;c.apply_morph(.5,0);assert.equal(sliders[200],3);assert.equal(sliders[211],1);assert.equal(sliders[212],21);assert(Math.abs(sliders[203]-100)<=1);assert.equal(sliders[207],0);assert.equal(sliders[143],333);
console.log('PASS: 214 typed rows, independent segment-curve Morph/Random policies, retired Motion protection, 16 polarity-aware routes and v1–v11 snapshot migration. Native REAPER acceptance remains separate.');
