import {syncAliases,syncDivisionIds,syncValuePosition} from './tempo-sync.mjs';
import {matrixTargets} from './model.mjs';
const ids=[4,5,7,12,39,25,34,53,76,6,2,15,114,132,134,1,3,13,124,8,9,11,26,27,35,36,37,44,43,54,55,56,68,69,57,58,121,120,122,77,78,79,126,23,128,129,127,50,136,137,138,139,143,144,145,146,147,115,135,42,46,61,62,63,64,142,70,71,189,190,203,204,205,206,207,202,208,209];
const octaves=new Set([3,7,9,12,14,20,25,35,53,54,56,60,64,65,68,71,72,74]);
export const feedbackTargets=ids.map((parameter,i)=>({destination:i+1,parameter,scale:matrixTargets[i+1].scale,octaves:octaves.has(i+1)}));
export const feedbackByParameter=new Map(feedbackTargets.map(t=>[t.parameter,t]));
for(const [alias,id]of syncAliases)feedbackByParameter.set(alias,feedbackByParameter.get(id));
export const FEEDBACK_LENGTH=542;
export function feedbackLimits(target,spec,rate=48000,clock={}){
 let low=spec.min,high=spec.max;
 if(target.destination===3){low=20;high=rate*.45;}
 if(target.destination===9||target.destination===6)high=Math.min(high,rate*.45);
 if(target.destination===11){low=-24;high=24;}
 if(target.destination===12&&clock.lfo1||target.destination===14&&clock.lfo2){low=1e-6;high=512;}
 if([53,54,56].includes(target.destination)&&clock.adr)high=3600000;
 if([71,72,74].includes(target.destination)&&clock.adr2)high=3600000;
 return {low,high};
}
export function feedbackValue(target,base,amount,spec,rate=48000,clock={}){
 const {low,high}=feedbackLimits(target,spec,rate,clock),value=target.octaves?base*2**(amount*target.scale):base+amount*target.scale;return Math.max(low,Math.min(high,value));
}
export function decodeFeedback(packet){
 const d=packet.data;if(!((d?.length===464&&d[42]===1)||(d?.length===481&&d[42]===2)||(d?.length===FEEDBACK_LENGTH&&d[42]===3))||!Array.from(d).every(Number.isFinite))return null;
 const values=new Map();for(const t of feedbackTargets){const i=t.destination-1;if(i>=70){if(d.length===542){const o=481+(i-70)*6;values.set(t.parameter,{target:t,current:d[o+1],base:d[o+4],amount:d[o],lowAmount:d[o+2],highAmount:d[o+3],assigned:d[o+5]>.5});}continue;}values.set(t.parameter,{target:t,current:d[114+i],base:d[324+i],amount:d[44+i],lowAmount:d[184+i],highAmount:d[254+i],assigned:d[394+i]>.5});}
 const clock=d.length>=481?{tempo:d[464],num:d[465],den:d[466],beat:d[467],lfo1:d[468]>.5,lfo2:d[469]>.5,adr:d[470]>.5,adr2:d.length===542&&d[535]>.5}:{};
 return {active:d[43]>.5,values,clock};
}
export class ModulationFeedback{
 constructor(){this.state=null;this.received=-Infinity;this.rate=48000;}
 accept(packet,info={},now=performance.now()){const state=decodeFeedback(packet);if(!state)return false;this.state=state;this.received=now;if(Number(info.sampleRate)>=8000)this.rate=Number(info.sampleRate);return true;}
 get clock(){return this.state?.clock||{};}
 current(parameter,now=performance.now()){return now-this.received<500&&this.state?.active?this.state.values.get(syncAliases.get(parameter)||parameter):null;}
 active(parameter,now=performance.now()){return !!this.current(parameter,now)?.assigned;}
 value(parameter,fallback,now=performance.now()){const state=this.current(parameter,now);return state?.assigned?state.current:fallback;}
 range(parameter,spec,now=performance.now()){const state=this.current(parameter,now);if(!state?.assigned)return null;return {...state,low:feedbackValue(state.target,state.base,state.lowAmount,spec,this.rate,this.clock),high:feedbackValue(state.target,state.base,state.highAmount,spec,this.rate)};}
 clear(){this.state=null;this.received=-Infinity;}
}
export function paintModulationFeedback(widgets,specs,feedback,toPosition,format,now=performance.now()){
 const records=[];
 for(const [id,list]of widgets){const spec=specs.get(id);if(!feedbackByParameter.has(id)||spec.options&&!syncDivisionIds.has(id))continue;
  for(const w of list){if(!w.overlay)continue;const state=feedback.range(id,specs.get(syncAliases.get(id)||id),now),visible=!!state&&w.input.isConnected&&w.input.getClientRects().length>0;
   if(!visible){w.overlay.hidden=true;w.root.removeAttribute('data-modulated');w.root.title=w.baseTitle;continue;}
   const r=w.input.getBoundingClientRect(),root=w.root.getBoundingClientRect(),vertical=!!w.input.closest('.vertical-faders');records.push({w,state,r,root,vertical,spec,id});
  }
 }
 for(const {w,state,r,root,vertical,spec,id}of records){
  const pos=v=>Math.max(0,Math.min(1,syncDivisionIds.has(id)?syncValuePosition(id,v,feedback.clock):toPosition(spec,v))),lo=pos(state.low),hi=pos(state.high),value=pos(state.current);
  w.overlay.hidden=false;w.overlay.dataset.axis=vertical?'vertical':'horizontal';w.root.dataset.modulated='true';
  Object.assign(w.overlay.style,vertical?{left:`${r.left-root.left+r.width/2+5}px`,top:`${r.top-root.top+7}px`,width:'3px',height:`${Math.max(1,r.height-14)}px`}:{left:`${r.left-root.left+7}px`,top:`${r.top-root.top+r.height/2+5}px`,width:`${Math.max(1,r.width-14)}px`,height:'3px'});
  w.band.style.cssText=vertical?`bottom:${lo*100}%;height:${Math.max(0,hi-lo)*100}%`:`left:${lo*100}%;width:${Math.max(0,hi-lo)*100}%`;
  w.marker.style.cssText=vertical?`bottom:${value*100}%`:`left:${value*100}%`;
  const bounds=feedbackLimits(state.target,specs.get(syncAliases.get(id)||id),feedback.rate,feedback.clock);w.marker.dataset.clipped=String(state.current<bounds.low||state.current>bounds.high);
  w.root.title=`${w.baseTitle}\nMOD: ${syncDivisionIds.has(id)?state.current.toFixed(3)+(id<=196?' Hz':' ms'):format(id,state.current)} · range ${syncDivisionIds.has(id)?state.low.toFixed(3):format(id,state.low)} … ${syncDivisionIds.has(id)?state.high.toFixed(3):format(id,state.high)}`;
 }
}
