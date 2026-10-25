import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const read=f=>fs.readFileSync(path.join(root,f),'utf8');
const escapeHTML=s=>s.replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;');
const json=s=>JSON.stringify(s).replaceAll('<','\\u003c').replaceAll('\u2028','\\u2028').replaceAll('\u2029','\\u2029');
// Our modules use immutable named exports and named imports, with no cycles.
// Keep scopes and names intact; fail on unsupported syntax instead of guessing.
export function buildWebUI(){
 const built=new Set(),visiting=new Set(),chunks=[],sources={};
 function module(file,entry=false){
  if(built.has(file))return;if(visiting.has(file))throw Error('Circular module: '+file);visiting.add(file);
  if(!/^webui\/[\w-]+\.mjs$/.test(file))throw Error('Unsupported module path: '+file);
  const original=read(file);sources[file]=original;let code=original;
  code=code.replace(/^import\s*\{([^}]+)\}\s*from\s*['"]([^'"]+)['"];?\s*$/gm,(_,names,ref)=>{
   if(!ref.startsWith('./'))throw Error('Nonlocal module: '+ref);const dependency=path.posix.normalize(path.posix.join(path.posix.dirname(file),ref));module(dependency);
   const bindings=names.split(',').map(n=>{n=n.trim();if(!/^\w+(?:\s+as\s+\w+)?$/.test(n))throw Error('Unsupported import: '+n);return n.replace(/\s+as\s+/,':');}).join(',');
   return `const {${bindings}}=__uc_modules[${json(dependency)}];`;
  });
  const exports=[];code=code.replace(/^export\s+((?:async\s+)?function|class|const)\s+(\w+)/gm,(_,kind,name)=>{exports.push(name);return `${kind} ${name}`;});
  if(/^\s*(?:import|export)\s|\bimport\s*\(|import\.meta/m.test(code))throw Error('Unsupported module syntax: '+file);
  if(entry){const registry="const registry=await fetch('./parameters.json').then(r=>{if(!r.ok)throw Error('Parameter registry is missing');return r.json();});";if(!code.includes(registry))throw Error('Registry loader changed');code=code.replace(registry,"const registry=JSON.parse(document.getElementById('ultracomb-parameters').textContent);");}
  chunks.push(`// ${file}\n__uc_modules[${json(file)}]=${entry?'await (async':'('}()=>{\n${code}\nreturn {${exports.join(',')}};\n})();`);
  visiting.delete(file);built.add(file);
 }
 module('webui/app.mjs',true);
 const notices=['THIRD_PARTY.md','licenses/ReaWebAPI-LICENSE.md','licenses/COPYING','licenses/COPYING.LESSER','licenses/Saike-MIT.txt','licenses/Bernsee-WOL.txt'];
 const text=notices.map(file=>`<details><summary>${escapeHTML(file)}</summary><pre>${escapeHTML(read(file))}</pre></details>`).join('\n');
 const archive={...sources,'webui/style.css':read('webui/style.css'),'webui/index.html':read('webui/index.html'),'webui/parameters.json':read('webui/parameters.json')};
 let html=read('webui/index.html').replace('<link rel="stylesheet" href="style.css">',`<style>\n${read('webui/style.css')}\n.package-actions{display:flex;justify-content:center;gap:12px}.package-actions button{font-size:8px}#package-notices{width:min(900px,92vw);max-height:85vh}#package-notices pre{white-space:pre-wrap;overflow-wrap:anywhere;font:11px/1.5 monospace}#package-notices summary{cursor:pointer;padding:8px 0}\n</style>`);
 html=html.replace(/(<button[^>]*id="all-parameters"[^>]*>[^<]*<\/button>)/,'<span class="package-actions">$1<button type="button" id="open-package-notices">LICENSES</button></span>');
 const runtime=`const __uc_modules=Object.create(null);\n${chunks.join('\n')}\ndocument.getElementById('open-package-notices').onclick=()=>document.getElementById('package-notices').showModal();document.getElementById('close-package-notices').onclick=()=>document.getElementById('package-notices').close();`;
 html=html.replace('<script type="module" src="app.mjs"></script>',`<dialog id="package-notices"><div class="dialog-title"><h2>THIRD-PARTY NOTICES / SOURCE</h2><button id="close-package-notices" type="button">×</button></div>${text}<p>Editable module sources are embedded in this HTML in the ultracomb-sources JSON block. Build tools and the complete source project are available in the linked repository.</p></dialog>\n<script type="application/json" id="ultracomb-parameters">${json(JSON.parse(read('webui/parameters.json')))}</script>\n<script type="application/json" id="ultracomb-sources">${json(archive)}</script>\n<script type="module">\n${runtime.replace(/<\/script/gi,'<\\/script')}\n</script>`);
 if(/(?:src|href)="(?:app\.mjs|style\.css)"/.test(html))throw Error('External resources remain');
 return html;
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 const html=buildWebUI(),target=path.join(root,'webui/packed.html');if(process.argv.includes('--check')){if(read('webui/packed.html')!==html)throw Error('webui/packed.html is stale; run node tools/build-webui.mjs');console.log('PASS: deterministic self-contained WebUI is current');}else{fs.writeFileSync(target,html);console.log('Built self-contained webui/packed.html: '+Buffer.byteLength(html)+' bytes');}
}
