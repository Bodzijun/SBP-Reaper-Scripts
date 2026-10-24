import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const source=fs.readFileSync(new URL('../sbp_ultraComb_webui.jsfx',import.meta.url),'utf8');
const marker='function uc_web_serialize() local(reading, valid) (',start=source.indexOf(marker)+marker.length;
const original=source.slice(start,source.indexOf('\n);',start));
assert(!original.includes('while('),'Stream-only serialization must never spin on a bank gate');
const translated=original.replace(/^(\s*)(.+?)\s+\?\s+\(\s*$/gm,'$1if ($2) {')
 .replace(/^\s*\) : \(\s*$/gm,'} else {').replace(/^\s*\);\s*$/gm,'}')
 .replace(/#uc_web_serial="";/g,'serial.bytes=Buffer.alloc(0);').replace(/#uc_web_serial/g,'serial')
 .replace(/atomic_add\(gmem\[reaweb_jsfx_base\+1\],1\)/g,'atomic_add(reaweb_jsfx_base+1,1)');
const program=new vm.Script(translated),header=Buffer.from('52574a310000000200000000','hex');
function run(reading,bytes=header,state=0,resources=0){
 let output=null,fallback=0;
 const ram=new Float64Array(8);ram[1]=50;
 const c=vm.createContext({Buffer,serial:{bytes:Buffer.alloc(0)},reaweb_jsfx_state_count:state,reaweb_jsfx_resource_count:resources,
  reaweb_jsfx_state_gate:2,reaweb_jsfx_base:0,reaweb_jsfx_epoch:50,reaweb_jsfx_reply_pending:1,
  file_avail:()=>reading?bytes.length:-1,
  file_string:(file,serial)=>{if(reading)serial.bytes=Buffer.from(bytes);else output=Buffer.from(serial.bytes);},
  str_setchar:(serial,offset,value)=>{if(serial.bytes.length<offset+4){const b=Buffer.alloc(offset+4);serial.bytes.copy(b);serial.bytes=b;}serial.bytes.writeUInt32BE(value,offset);},
  strlen:serial=>serial.bytes.length,str_getchar:(serial,offset)=>serial.bytes.length>=offset+4?serial.bytes.readUInt32BE(offset):0,
  atomic_add:(index,value)=>ram[index]+=value,reaweb_jsfx_serialize:()=>{fallback++;}});
 program.runInContext(c);return {c,output,fallback};
}
const saved=run(false);assert.deepEqual(saved.output,header);assert.equal(saved.c.reaweb_jsfx_epoch,50);assert.equal(saved.c.reaweb_jsfx_state_gate,2,'Serialization must not steal an occupied gate');
const loaded=run(true);assert.equal(loaded.c.reaweb_jsfx_epoch,51);assert.equal(loaded.c.reaweb_jsfx_reply_pending,0);assert.equal(loaded.c.reaweb_jsfx_serialize_error,false);
for(const bytes of [Buffer.alloc(0),Buffer.alloc(12),Buffer.from('52574a310000000200000001','hex')])assert.equal(run(true,bytes).c.reaweb_jsfx_serialize_error,true);
assert.equal(run(false,header,1,0).fallback,1);assert.equal(run(false,header,0,1).fallback,1);
console.log('PASS: actual stream-only serialization body, compatible 12-byte SDK header, occupied-gate completion, generation renewal, invalid input and registered-bank fallback. Native reset acceptance still required.');
