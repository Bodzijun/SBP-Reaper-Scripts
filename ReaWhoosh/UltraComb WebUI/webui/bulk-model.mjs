// Registry policy is generated from the native Morph/Randomize metadata.
export function interpolateParameter(meta,a,b,position){
 if(meta.MORPH_DISCRETE)return position<.5?a:b;
 return meta.MORPH_LOG&&a>0&&b>0?a*(b/a)**position:a+(b-a)*position;
}
export function randomizeEntries(policy,get,strength,scope,random=Math.random){
 strength=Math.max(0,Math.min(1,strength));scope=Math.max(0,Math.min(3,Math.round(scope)));
 const entries=[];
 for(const [key,meta]of Object.entries(policy)){
  const id=Number(key);
  if(!meta.RANDOM_ALLOWED||!(meta.RANDOM_GROUP&(2**scope)))continue;
  if(get(113)>.5&&meta.RANDOM_LEGACY)continue;
  if(id>=91&&id<=112){const route=Math.floor((id-89)/3);if(get(89+route*3)<.5||get(90+route*3)<.5)continue;}
  if(strength<.5&&meta.MORPH_DISCRETE)continue;
  let target=meta.MORPH_LOG&&meta.RANDOM_LO>0?meta.RANDOM_LO*(meta.RANDOM_HI/meta.RANDOM_LO)**random():meta.RANDOM_LO+random()*(meta.RANDOM_HI-meta.RANDOM_LO);
  if(meta.MORPH_DISCRETE)target=Math.floor(target+.5);
  if(id===45&&get(113)>.5)target=target<1?0:2;
  target=interpolateParameter(meta,get(id),target,strength);
  target=Math.max(meta.MORPH_LO,Math.min(meta.MORPH_HI,meta.MORPH_LO+Math.floor((target-meta.MORPH_LO)/meta.MORPH_STEP+.5)*meta.MORPH_STEP));
  entries.push([id,target]);
 }
 return entries;
}
