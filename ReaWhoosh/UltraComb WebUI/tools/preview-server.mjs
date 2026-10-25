import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const release=process.argv.includes('--release');
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),release?'..':'../webui');
const types={'.html':'text/html','.css':'text/css','.mjs':'text/javascript','.js':'text/javascript','.json':'application/json'};
const server=http.createServer((req,res)=>{
 try{const url=new URL(req.url,'http://localhost'),relative=decodeURIComponent(url.pathname==='/'?(release?'webui/packed.html':'index.html'):url.pathname.slice(1)),file=path.resolve(root,relative);
 if(file!==root&&!file.startsWith(root+path.sep)){res.writeHead(403).end();return;}
 const stat=fs.statSync(file);if(!stat.isFile())throw Error('Not a file');res.setHeader('Content-Type',types[path.extname(file)]||'application/octet-stream');res.setHeader('Cache-Control','no-store');fs.createReadStream(file).pipe(res);
 }catch{res.writeHead(404).end('Not found');}
});
let port=8793;server.on('error',e=>{if(e.code==='EADDRINUSE'&&port<8803){port++;server.listen(port,'127.0.0.1');}else throw e;});server.listen(port,'127.0.0.1',()=>console.log(`http://127.0.0.1:${port}/?preview=1`));
