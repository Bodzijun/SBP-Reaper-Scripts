(function(root){
  'use strict';
  const finite=Number.isFinite, fmt=v=>finite(v)?v.toFixed(1):'—';
  const colors={ok:'#68d9b4',low:'#70baf2',high:'#f08083',dynamic:'#edc166',missing:'#849395'};
  function overview(scenes,points,calculated,length){
    const gains=new Map(calculated.map(p=>[p.time,p.gain]));
    return scenes.map(scene=>{
      // Skip unrelated history instead of cloning the full film per scene.
      let lo=0,hi=points.length;
      while(lo<hi){const mid=(lo+hi)>>>1;if(points[mid].time<scene.start)lo=mid+1;else hi=mid;}
      const rows=[];
      for(let i=lo;i<points.length&&points[i].time<=scene.finish;i++){
        const p=points[i];
        const a=i?(points[i-1].time+p.time)/2:0,b=i+1<points.length?(p.time+points[i+1].time)/2:length;
        const weight=Math.max(0,Math.min(scene.finish,b)-Math.max(scene.start,a));
        if(weight>0)rows.push({...p,gain:gains.get(p.time)??0,weight});
      }
      function stats(after){
        const data=rows.filter(p=>finite(p.short_term)&&p.short_term>-70).map(p=>({...p,level:p.short_term+(after?p.gain:0)}));
        const percentile=q=>root.LoudnessAnalysis.percentile(data,'level',q);
        const lo=percentile(.1),hi=percentile(.95);
        const max=key=>{const v=rows.filter(p=>finite(p[key])&&p[key]>-70).map(p=>p[key]+(after?p.gain:0));return v.length?v.reduce((a,b)=>Math.max(a,b),-Infinity):null;};
        return {level:percentile(.5),spread:finite(lo)&&finite(hi)?hi-lo:null,m_max:max('momentary'),s_max:max('short_term'),sample_peak:max('peak')};
      }
      return {...scene,before:stats(false),after:stats(true),basis:'overview',short_scene:scene.finish-scene.start<60};
    });
  }
  function combine(estimated,measured){
    return estimated.map((scene,i)=>{
      const value=measured?.[i];
      if(!value||Math.abs(value.start-scene.start)>.001||Math.abs(value.finish-scene.finish)>.001||value.name!==scene.name)return scene;
      return {...scene,...value,before:{...value.before,spread:scene.before.spread},after:{...value.after,spread:scene.after.spread}};
    });
  }
  function level(scene,side){return scene.basis==='audio'?scene[side].i:scene[side].level;}
  function classify(scene,side,target,tolerance,metric,min,max){
    const value=level(scene,side),dynamic=scene[side][metric], reasons=[];
    if(!finite(value))return {kind:'missing',color:colors.missing,text:'No gated loudness data'};
    const delta=value-target;
    if(delta < -tolerance)reasons.push('Quieter');else if(delta>tolerance)reasons.push('Louder');
    if(finite(dynamic)&&(dynamic<min||dynamic>max))reasons.push('Dynamics outside guide');
    if(!finite(dynamic))reasons.push('Dynamics unavailable');
    if(scene.short_scene&&metric==='lra')reasons.push(finite(dynamic)?'Short scene · LRA unstable':'Short scene · no LRA');
    const kind=delta < -tolerance?'low':delta>tolerance?'high':!finite(dynamic)?'missing':dynamic<min||dynamic>max?'dynamic':'ok';
    return {kind,color:colors[kind],text:reasons.join(' · ')||'Within guides',delta};
  }
  function render(model){
    const $=id=>document.getElementById(id),rows=model.rows,metric=$('scene-metric').value||'spread',display=$('scene-display').value||'both';
    const tolerance=Math.max(0,Number($('scene-tolerance').value)||0),low=Math.max(0,Number($('scene-dyn-min').value)||0),high=Math.max(low,Number($('scene-dyn-max').value)||0);
    const audio=rows.length>0&&rows.every(s=>s.basis==='audio'),sides=display==='both'?['before','after']:[display];
    const labels={spread:'S spread · P95−P10 · LU (sampled)',lra:'LRA · LU',crest:'Crest factor · dB',plr:'PLR · dB'};
    $('scene-track').disabled=$('scene-source').value!=='track';$('scene-naming').disabled=$('scene-source').value!=='track';
    $('scene-level-heading').textContent=audio?'I · before → after':'S median · before → after';
    $('constellation-note').textContent=!rows.length?'No scenes yet. Choose regions or a track and Refresh scenes.':`${rows.length} scenes · ${audio?'Audio measured at each scene boundary.':'Overview: sampled S medians; audio I/LRA/crest/PLR are not inferred.'} ${model.stale?'Curves or source changed: previous scene measurement is stale. Measure again.':''} Click a point or scene name to show its time range. Guides are personal scene references.`;
    const canvas=$('constellation-canvas'),rect=canvas.getBoundingClientRect(),dpr=window.devicePixelRatio||1;
    canvas.width=Math.max(1,Math.round(rect.width*dpr));canvas.height=Math.max(1,Math.round(rect.height*dpr));
    const ctx=canvas.getContext('2d'),w=rect.width,h=rect.height,left=62,right=w-20,top=28,bottom=h-38;
    ctx.setTransform(dpr,0,0,dpr,0,0);ctx.clearRect(0,0,w,h);ctx.font='11px Segoe UI';
    let minX=-Math.max(6,tolerance+1),maxX=-minX,minY=0,maxY=Math.max(6,high+2);
    const dots=[];
    for(const scene of rows)for(const side of sides){
      const value=level(scene,side),dynamic=scene[side][metric];
      if(finite(value)&&finite(dynamic)){minX=Math.min(minX,value-model.target-1);maxX=Math.max(maxX,value-model.target+1);minY=Math.min(minY,dynamic-1);maxY=Math.max(maxY,dynamic+1);dots.push({scene,side,value,dynamic});}
    }
    const x=v=>left+(v-minX)/(maxX-minX)*(right-left),y=v=>bottom-(v-minY)/(maxY-minY)*(bottom-top);
    ctx.fillStyle='#68d9b412';ctx.fillRect(x(-tolerance),y(high),x(tolerance)-x(-tolerance),y(low)-y(high));
    ctx.strokeStyle='#fff19a';ctx.setLineDash([4,4]);ctx.beginPath();ctx.moveTo(x(0),top);ctx.lineTo(x(0),bottom);ctx.stroke();ctx.setLineDash([]);
    for(let i=0;i<=4;i++){
      const vx=minX+(maxX-minX)*i/4,vy=minY+(maxY-minY)*i/4;
      ctx.strokeStyle='#344041';ctx.beginPath();ctx.moveTo(left,y(vy));ctx.lineTo(right,y(vy));ctx.stroke();
      ctx.fillStyle='#aabcbc';ctx.textAlign='right';ctx.fillText(fmt(vy),left-8,y(vy)+3);ctx.textAlign='center';ctx.fillText(fmt(vx),x(vx),h-17);
    }
    ctx.textAlign='left';ctx.fillStyle='#bdcccc';ctx.fillText(labels[metric],left,14);
    ctx.textAlign='right';ctx.fillText(`${audio?'Scene I':'Scene S median'} − Target ${fmt(model.target)} · LU`,right,h-3);
    if(display==='both')for(const scene of rows){
      const a=dots.find(d=>d.scene===scene&&d.side==='before'),b=dots.find(d=>d.scene===scene&&d.side==='after');
      if(a&&b){ctx.strokeStyle='#768a8a66';ctx.beginPath();ctx.moveTo(x(a.value-model.target),y(a.dynamic));ctx.lineTo(x(b.value-model.target),y(b.dynamic));ctx.stroke();}
    }
    const hits=[];
    for(const d of dots){
      const status=classify(d.scene,d.side,model.target,tolerance,metric,low,high),px=x(d.value-model.target),py=y(d.dynamic),radius=Math.max(4,Math.min(13,Math.sqrt(d.scene.finish-d.scene.start)));
      ctx.beginPath();ctx.arc(px,py,radius,0,Math.PI*2);ctx.strokeStyle=status.color;ctx.lineWidth=2;
      if(d.side==='after'){ctx.fillStyle=status.color+'b0';ctx.fill();}ctx.stroke();
      if(rows.length<=20&&(d.side==='after'||display==='before')){ctx.fillStyle='#c9dada';ctx.textAlign='left';ctx.fillText(d.scene.name.slice(0,35),px+radius+4,py-3);}
      hits.push({...d,x:px,y:py,radius,status});
    }
    if(rows.length&&!dots.length){
      const message=!audio?'Measure scene audio for this dynamics metric, or choose sampled S spread.':metric==='lra'?'LRA requires enough audible short-term data. Choose crest factor or PLR for short scenes.':'No gated scene loudness / dynamics data for this metric.';
      ctx.fillStyle='#edc166';ctx.textAlign='left';ctx.fillText(message,left,top+30);
    }
    const hit=event=>{const r=canvas.getBoundingClientRect(),px=event.clientX-r.left,py=event.clientY-r.top;return hits.slice().reverse().find(p=>Math.hypot(p.x-px,p.y-py)<=p.radius+5);};
    canvas.onpointermove=event=>{const p=hit(event);canvas.title=p?`${p.scene.name} · ${p.side} · ${fmt(p.value)} ${audio?'LUFS-I':'S median'} · ${fmt(p.dynamic)} ${labels[metric]} · ${p.status.text}`:'';};
    canvas.onclick=event=>{const p=hit(event);if(p)model.onSelect(p.scene);};
    const table=$('scene-table');table.replaceChildren();
    const pair=(scene,key)=>`${fmt(scene.before[key])} → ${fmt(scene.after[key])}`;
    for(const scene of rows){
      const tr=document.createElement('tr'),name=document.createElement('td'),button=document.createElement('button');
      button.className='scene-jump';button.textContent=scene.name;button.title=`${scene.start.toFixed(2)}–${scene.finish.toFixed(2)} s`;button.addEventListener('click',()=>model.onSelect(scene));name.appendChild(button);tr.appendChild(name);
      const side=display==='before'?'before':'after',status=classify(scene,side,model.target,tolerance,metric,low,high);
      const values=[(scene.finish-scene.start).toFixed(1)+' s',pair(scene,scene.basis==='audio'?'i':'level'),fmt(status.delta),pair(scene,'lra'),pair(scene,'crest'),pair(scene,'plr'),pair(scene,'true_peak'),pair(scene,'rms'),status.text];
      for(const value of values){const td=document.createElement('td');td.textContent=value;tr.appendChild(td);}tr.style.borderLeft=`3px solid ${status.color}`;table.appendChild(tr);
    }
  }
  const api={overview,combine,level,classify,render};root.LoudnessConstellation=api;
  if(typeof module!=='undefined')module.exports=api;
})(typeof globalThis!=='undefined'?globalThis:this);
