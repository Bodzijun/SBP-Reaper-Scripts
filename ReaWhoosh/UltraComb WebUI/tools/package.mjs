import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const main='sbp_ultraComb_webui.jsfx';
function requireThat(condition,message){if(!condition)throw Error(message);}
function walk(directory,prefix=''){
 return fs.readdirSync(directory,{withFileTypes:true}).flatMap(entry=>{
  const relative=prefix+entry.name;
  requireThat(!entry.isSymbolicLink(),'Package must not use symlinks: '+relative);
  return entry.isDirectory()?walk(path.join(directory,entry.name),relative+'/'):[relative];
 });
}
const digest=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
export function validatePackage(){
 const source=fs.readFileSync(path.join(root,main),'utf8').replace(/\r\n/g,'\n');
 const version=source.match(/^\/\/ @version (\S+)$/m)?.[1];
 requireThat(version==='3.0.0','Release version must be 3.0.0');
 const section=source.match(/^\/\/ @provides\n((?:\/\/   [^\n]+\n)+)/m)?.[1];
 requireThat(section,'Missing @provides header');
 const available=walk(root),patterns=section.trimEnd().split('\n').map(line=>line.replace(/^\/\/   /,''));
 const included=new Set([main]);
 for(const pattern of patterns){
  requireThat(!pattern.includes('..')&&!pattern.startsWith('/')&&!pattern.includes('\\'),'Invalid package pattern: '+pattern);
  const regex=new RegExp('^'+pattern.split('*').map(part=>part.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')).join('[^/]*')+'$');
  const matches=available.filter(file=>regex.test(file));requireThat(matches.length,'Empty @provides pattern: '+pattern);
  for(const file of matches)included.add(file);
 }
 for(const file of available.filter(file=>file.startsWith('webui/')))requireThat(included.has(file),'WebUI asset missing from @provides: '+file);
 for(const file of ['sbp_ultraComb_webui.json','reaweb_jsfx.inc','README.md','THIRD_PARTY.md','licenses/ReaWebAPI-LICENSE.md','licenses/COPYING','licenses/COPYING.LESSER','licenses/Saike-MIT.txt','licenses/Bernsee-WOL.txt'])requireThat(included.has(file),'Required release file missing: '+file);
 requireThat(![...included].some(file=>/^(?:tools\/|DEVELOPMENT|PACKAGING)|\.(?:dll|so|dylib|zip)$/i.test(file)),'Developer files or extension binaries must not be installed by this package');
 const association=JSON.parse(fs.readFileSync(path.join(root,'sbp_ultraComb_webui.json'),'utf8')).JSFX_WebUI;
 requireThat(association.entry==='webui/index.html'&&included.has(association.entry),'Invalid WebUI association');
 function checkReference(owner,reference){
  requireThat(!/^(?:https?:|\/|[A-Za-z]:)/.test(reference),'Runtime resource must be local: '+reference);
  const target=path.posix.normalize(path.posix.join(path.posix.dirname(owner),reference));
  requireThat(included.has(target),'Missing/case-mismatched runtime dependency: '+owner+' -> '+target);
 }
 for(const file of included){
  const text=fs.readFileSync(path.join(root,file),'utf8');
  if(file.endsWith('.html'))for(const match of text.matchAll(/(?:src|href)="([^"]+)"/g))checkReference(file,match[1]);
  if(file.endsWith('.mjs'))for(const match of text.matchAll(/(?:\bfrom\s*|\bimport\s*|\bfetch\(\s*)['"](\.[^'"]+)['"]/g))checkReference(file,match[1]);
  if(file.endsWith('.css'))for(const match of text.matchAll(/url\(['"]?([^)'"\s]+)['"]?\)/g))checkReference(file,match[1]);
 }
 for(const [file,expected]of [['reaweb_jsfx.inc','37e0ba61957b9c6f9ea5fedfcd0158c3b068524b'],['webui/jsfx-webui.mjs','1122fcf6592f4e74e03417d3ce09dfaf43a676d9']]){
  const bytes=Buffer.from(fs.readFileSync(path.join(root,file),'utf8').replace(/\r\n/g,'\n'));
  const blob=crypto.createHash('sha1').update(Buffer.concat([Buffer.from(`blob ${bytes.length}\0`),bytes])).digest('hex');
  requireThat(blob===expected,'Vendored SDK differs from pinned upstream: '+file);
 }
 const files=[...included].sort().map(file=>{const bytes=fs.readFileSync(path.join(root,file));return {path:file,bytes:bytes.length,sha256:digest(bytes)};});
 return {name:'SBP UltraComb WebUI 3',version,repositoryPath:'ReaWhoosh/UltraComb WebUI',main,files};
}
export function stagePackage(output){
 const manifest=validatePackage(),destination=path.resolve(output);
 requireThat(!fs.existsSync(destination),'Use a new staging directory; refusing to overwrite '+destination);
 const effects=path.join(destination,'Effects','SBP UltraComb WebUI 3');
 for(const file of manifest.files){const target=path.join(effects,file.path);fs.mkdirSync(path.dirname(target),{recursive:true});fs.copyFileSync(path.join(root,file.path),target);requireThat(digest(fs.readFileSync(target))===file.sha256,'Staged file hash mismatch: '+file.path);}
 fs.writeFileSync(path.join(destination,'package-manifest.json'),JSON.stringify(manifest,null,2)+'\n');
 return manifest;
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 const output=process.argv.indexOf('--output'),manifest=output<0?validatePackage():stagePackage(process.argv[output+1]);
 console.log(`PASS: ${manifest.name} ${manifest.version}, ${manifest.files.length} runtime/documentation/license files; all local dependencies and pinned SDK hashes verified.`);
}
