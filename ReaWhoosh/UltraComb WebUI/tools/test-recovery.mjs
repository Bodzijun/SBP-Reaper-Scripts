import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const source=fs.readFileSync(new URL('../webui/app.mjs',import.meta.url),'utf8');
const functions=source.slice(source.indexOf('function recoverStreams(){'),source.indexOf('// Older runtimes'));
let pending,closes=0,opens=0,capabilities=0,refreshes=0;
const context=vm.createContext({
 jsfx:{async getCapabilities(){capabilities++;},params:{async getState(){refreshes++;return {};}}},applyState(){},active:true,disposed:false,streamRecovery:null,recoveryTimer:0,retryAfter:0,
 performance:{now:()=>100},report:error=>{throw error;},
 setTimeout(fn,delay){assert.equal(delay,100);pending=fn;return 1;},
 async closeStreams(){closes++;},async openStreams(){opens++;}
});
vm.runInContext(functions,context);
context.requestStreamRecovery();context.requestStreamRecovery();
assert.equal(closes,0,'Notifications must be coalesced');
pending();await context.streamRecovery;
assert.equal(closes,1);assert.equal(opens,1);
assert.equal(capabilities,1);assert.equal(refreshes,1);
context.active=false;context.requestStreamRecovery();await context.recoverStreams();
assert.equal(opens,1,'Inactive editors must not reopen streams');
context.active=true;context.disposed=true;await context.recoverStreams();
assert.equal(opens,1,'Disposed editors must not reopen streams');
console.log('PASS: reset events coalesce into one reconnect; inactive/disposed editors stay closed.');
