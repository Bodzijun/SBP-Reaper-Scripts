export const matrixRoutes=Array.from({length:16},(_,index)=>{
 const source=index<8?89+index*3:148+(index-8)*3;
 return {index,source,target:source+1,amount:source+2,polarity:172+index};
});
export const routeForParameter=id=>matrixRoutes.find(r=>[r.source,r.target,r.amount,r.polarity].includes(id));
export const polarityNames=['AUTO','UNI','BI'];
export function routeIsBipolar(source,polarity){return polarity===2||polarity===0&&(source===1||source===4);}
export function convertSource(value,nativeBipolar,polarity,depth=1,enabled=true){
 if(!enabled)return 0;let v=Math.max(nativeBipolar?-1:0,Math.min(1,value));
 if(polarity===1&&nativeBipolar)v=(v+1)/2;else if(polarity===2&&!nativeBipolar)v=2*v-1;
 return v*Math.max(-1,Math.min(1,depth));
}
export const scopeNames=['All','Pitch family','Tone','Modulation','Core','Comb','Disperser','Shift','Doubler','Ring','Metal','Saturation','Filter','Chorus','LFO 1','LFO 2','Envelope','ADR 1','Matrix','Pitch FX','Motion','ADR 2'];
