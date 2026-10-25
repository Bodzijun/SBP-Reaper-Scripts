import assert from 'node:assert/strict';
import {connectJSFX} from '../webui/jsfx-webui.mjs';
for(const failures of [0,1,2,3]){
 let session='session-0',reads=0,capabilities=0,listeners=0;const methods=[],errors=[];
 const service={async on(){listeners++;return async()=>{listeners--;};},async invoke(method){
  methods.push(method);
  let data;
  if(method==='getCapabilities'){capabilities++;data={protocolVersion:1,sessionId:session,capabilityRevision:'1',features:{editorSize:true},commands:[]};}
  else if(method==='getEditorSize')data={width:1280,height:860,customized:false,revision:'1'};
  else if(method==='getParamState'){
   reads++;if(reads<=failures){session='session-'+reads;return {ok:false,error:{code:'STALE_SESSION',message:'DSP generation changed'}};}
   data={sessionId:session,activation:1,active:true,revision:'1',count:1,parameters:[{index:0,value:.25,normalized:.25,defaultNormalized:0}]};
  }else if(method==='present')data={presented:true};else throw Error('Unexpected host operation: '+method);
  return {ok:true,sessionId:session,data};
 }};
 const host={lifecycle:{ready:Promise.resolve({runtime:{jsfx:{protocolVersion:1}}})},host:{service:()=>service}};
 if(failures<=2){const jsfx=await connectJSFX(host,error=>errors.push(error));assert.equal(jsfx.params.snapshot.parameters[0].value,.25);assert.equal(jsfx.active,true);assert.equal(reads,failures+1);await jsfx.dispose();}
 else{await assert.rejects(()=>connectJSFX(host),error=>error.code==='STALE_SESSION');assert.equal(reads,3,'Initial reads must stop after two retries');}
 assert.equal(capabilities,Math.min(failures+1,3));assert.equal(listeners,0,'Success disposal/failure must release subscriptions');assert.equal(methods.filter(m=>/setParam|beginParam/.test(m)).length,0,'Recovery must never write defaults or retry parameter edits');assert.deepEqual(errors,[]);
}
console.log('PASS: actual updated SDK handles zero/one/two startup session changes, bounds retries, activates the initial snapshot, never writes parameters and cleans subscriptions. Native runtime acceptance remains separate.');
