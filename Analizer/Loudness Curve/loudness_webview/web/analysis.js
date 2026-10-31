(function(root) {
  'use strict';
  const finite = Number.isFinite;
  const fmt = value => finite(value) ? value.toFixed(1) : '—';
  function rows(points, calculated, length, metric, gate = -Infinity) {
    const gain = new Map(calculated.map(p=>[p.time,p.gain]));
    return points.map((p,i)=>({time:p.time, before:p[metric], short:p.short_term, peak:p.peak,
      gain:gain.get(p.time) ?? 0,
      weight:Math.max(0,(i===points.length-1?length:(p.time+points[i+1].time)/2)-(i===0?0:(points[i-1].time+p.time)/2))
    })).filter(p=>finite(p.before) && p.before>=gate).map(p=>({...p,after:p.before+p.gain}));
  }
  function percentile(data,key,q) {
    const sorted=data.filter(p=>finite(p[key])).slice().sort((a,b)=>a[key]-b[key]);
    const total=sorted.reduce((n,p)=>n+p.weight,0);if(!total)return null;
    let sum=0;for(const p of sorted){sum+=p.weight;if(sum>=total*q)return p[key];}
    return sorted.at(-1)[key];
  }
  function distribution(data,bins,key) {
    const counts=bins.map(()=>0);let total=0;
    for(const p of data) {
      if(!finite(p[key]))continue;total+=p.weight;
      const index=bins.findIndex(b=>p[key]<(b.upper??Infinity)&&p[key]>=(b.lower??-Infinity));
      if(index>=0)counts[index]+=p.weight;
    }
    return counts.map(weight=>total?weight/total:0);
  }
  function psrProxy(points,calculated,gate=-Infinity) {
    const gain=new Map(calculated.map(p=>[p.time,p.gain])),output=[];
    const before=[],after=[];let beforeHead=0,afterHead=0;
    for(let i=0;i<points.length;i++) {
      const p=points[i];
      while(beforeHead<before.length && points[before[beforeHead]].time<p.time-3)beforeHead++;
      while(afterHead<after.length && points[after[afterHead]].time<p.time-3)afterHead++;
      const corrected=k=>points[k].peak+(gain.get(points[k].time)??0);
      if(finite(p.peak)) {
        while(before.length>beforeHead && points[before.at(-1)].peak<=p.peak)before.pop();before.push(i);
        while(after.length>afterHead && corrected(after.at(-1))<=corrected(i))after.pop();after.push(i);
      }
      if(p.time<3 || !finite(p.short_term)||p.short_term<gate || beforeHead>=before.length)continue;
      const peak=points[before[beforeHead]].peak,correctedPeak=corrected(after[afterHead]);
      output.push({time:p.time,before:peak-p.short_term,after:correctedPeak-p.short_term-(gain.get(p.time)??0),
        short:p.short_term,correctedShort:p.short_term+(gain.get(p.time)??0),peak,weight:i?Math.max(0,p.time-points[i-1].time):0});
    }
    return output;
  }
  function plr(report) {
    if(!finite(report?.integrated))return {value:null,basis:'Unavailable'};
    if(finite(report.metadata?.true_peak))return {value:report.metadata.true_peak-report.integrated,basis:'True Peak − measured I'};
    if(finite(report.metadata?.peak))return {value:report.metadata.peak-report.integrated,basis:'Sample Peak − measured I'};
    return {value:null,basis:'Overall peak missing'};
  }
  function bins(data) {
    let low=-60,high=0;
    for(const p of data){for(const key of ['before','after'])if(finite(p[key])){low=Math.min(low,Math.floor(p[key]/3)*3);high=Math.max(high,Math.ceil(p[key]/3)*3+3);}}
    const step=Math.max(3,Math.ceil((high-low)/30/3)*3),output=[];
    for(let lower=low;lower<high;lower+=step)output.push({lower,upper:lower+step});return output.reverse();
  }
  function render(model) {
    const $=id=>document.getElementById(id),report=model.report;
    if(!report || !model.points.length)return;
    const gate=$('analysis-gate').checked?model.gate:-Infinity;
    const data=rows(model.points,model.calculated,report.length,model.metric,gate);
    const proxy=psrProxy(model.points,model.calculated,gate),ratio=plr(report);
    $('analysis-plr').textContent=fmt(ratio.value)+' dB';$('analysis-plr').title=ratio.basis;
    $('analysis-tp').textContent=fmt(report.metadata?.true_peak)+' dBTP';
    $('analysis-lra').textContent=fmt(report.metadata?.lra)+' LU';
    const spread=key=>{const high=percentile(data,key,.95),low=percentile(data,key,.1);return finite(high)&&finite(low)?high-low:null;};
    $('analysis-spread').textContent=`${fmt(spread('before'))} → ${fmt(spread('after'))} LU`;
    $('analysis-psr').textContent=`${fmt(percentile(proxy,'before',.5))} → ${fmt(percentile(proxy,'after',.5))} dB`;
    const differences=model.points.slice(1).map((p,i)=>p.time-model.points[i].time).sort((a,b)=>a-b);
    const spacing=differences[Math.floor(differences.length/2)];
    const mode=$('analysis-view').value||'distribution',native=$('histogram-source').value==='report';
    const guide=Number($('psr-guide').value)||12;
    $('analysis-note').textContent=`${model.metric==='momentary'?'LUFS-M':'LUFS-S'} · original interval ~${fmt(spacing)} s. ${$('analysis-gate').checked?'Sampled analysis excludes source levels below '+model.gate+' LUFS.':'Sampled analysis includes silence.'} Gray: measured/source-derived; green: gain-model estimate. PSR proxy uses sampled peaks from the preceding 3 seconds and cannot replace a meter; sparse reports miss micro-dynamics. PLR/LRA are original report values, not corrected predictions. P95−P10 is a sampled spread, not measured LRA.`;
    const canvas=$('analysis-canvas'),rect=canvas.getBoundingClientRect(),dpr=window.devicePixelRatio||1;
    canvas.width=Math.max(1,Math.round(rect.width*dpr));canvas.height=Math.max(1,Math.round(rect.height*dpr));
    const ctx=canvas.getContext('2d');ctx.setTransform(dpr,0,0,dpr,0,0);const w=rect.width,h=rect.height;
    ctx.clearRect(0,0,w,h);ctx.font='11px Segoe UI';
    const left=110,right=w-20,top=18,bottom=h-32;
    const text=(label,x,y,align='left',color='#bac8c8')=>{ctx.fillStyle=color;ctx.textAlign=align;ctx.fillText(label,x,y);};
    const line=(values,key,x,y,color,dash=[])=>{ctx.beginPath();ctx.strokeStyle=color;ctx.lineWidth=2;ctx.setLineDash(dash);let connected=false;for(const p of values){if(!finite(p[key])){connected=false;continue;}if(connected)ctx.lineTo(x(p),y(p[key]));else ctx.moveTo(x(p),y(p[key]));connected=true;}ctx.stroke();ctx.setLineDash([]);};
    const grid=(min,max,label)=>{const y=value=>bottom-(value-min)/(max-min)*(bottom-top);for(let i=0;i<=4;i++){const v=min+(max-min)*i/4;ctx.strokeStyle='#344041';ctx.beginPath();ctx.moveTo(left,y(v));ctx.lineTo(right,y(v));ctx.stroke();text(fmt(v),left-8,y(v)+3,'right');}text(label,left,12);return y;};
    const table=$('analysis-table');table.replaceChildren();
    if(mode==='distribution') {
      const ranges=native?(report.histogram||[]):bins(data);
      if(!ranges.length){text('This report has no native histogram.',left,50);return;}
      const before=native?ranges.map(b=>b.fraction):distribution(data,ranges,'before');
      const after=native?null:distribution(data,ranges,'after');
      const maximum=Math.max(.01,...before,...(after||[])),row=(bottom-top)/ranges.length;
      text(native?'REAPER histogram · original percentages':'Time-weighted sampled distribution · before / estimated after',left,12);
      ranges.forEach((b,i)=>{
        const y=top+i*row,label=`${b.lower??'−∞'}..${b.upper} LUFS`;
        text(label,left-6,y+row*.55,'right');
        ctx.fillStyle='#97a6aa';ctx.fillRect(left,y+2,before[i]/maximum*(right-left-95),Math.max(2,row*.35));
        if(after){ctx.fillStyle='#4aefbc';ctx.fillRect(left,y+row*.45,after[i]/maximum*(right-left-95),Math.max(2,row*.35));}
        text(`${fmt(before[i]*100)}%${after?' / '+fmt(after[i]*100)+'%':''}`,right,y+row*.6,'right');
        const tr=document.createElement('tr');for(const value of [label,fmt(before[i]*100)+'%',after?fmt(after[i]*100)+'%':'—']){const td=document.createElement('td');td.textContent=value;tr.appendChild(td);}table.appendChild(tr);
      });
      if(native)$('analysis-note').textContent+=' Native histogram keeps REAPER’s original bins/percentages, including its own gating rules; no corrected histogram is inferred from those percentages.';
    } else if(mode==='map') {
      const y=grid(0,Math.max(24,guide,...proxy.map(p=>p.before),...proxy.map(p=>p.after)), 'PSR proxy · dB');
      let min=-60,max=0;for(const p of proxy){min=Math.min(min,p.short,p.correctedShort);max=Math.max(max,p.short,p.correctedShort);}
      const x=value=>left+(value-min)/(max-min)*(right-left);
      ctx.strokeStyle='#d6bd68';ctx.setLineDash([4,4]);ctx.beginPath();ctx.moveTo(left,y(guide));ctx.lineTo(right,y(guide));ctx.stroke();ctx.setLineDash([]);
      for(const p of proxy){ctx.fillStyle='#97a6aa88';ctx.beginPath();ctx.arc(x(p.short),y(p.before),2,0,Math.PI*2);ctx.fill();ctx.fillStyle='#4aefbc88';ctx.beginPath();ctx.arc(x(p.correctedShort),y(p.after),2,0,Math.PI*2);ctx.fill();}
      for(let i=0;i<=4;i++)text(fmt(min+(max-min)*i/4),left+(right-left)*i/4,h-10,'center');text('LUFS-S',right,bottom-5,'right');
    } else {
      const values=mode==='gain'?data:proxy,keys=mode==='gain'?['gain']:['before','after'];
      let min=mode==='gain'?-3:0,max=mode==='gain'?3:Math.max(24,guide,ratio.value??0);
      for(const p of values)for(const key of keys)if(finite(p[key])){min=Math.min(min,p[key]);max=Math.max(max,p[key]);}
      const y=grid(min,max,mode==='gain'?'Applied gain · dB':'PSR proxy · dB'),x=p=>left+p.time/report.length*(right-left);
      if(mode==='gain')line(values,'gain',x,y,'#4aefbc');
      else {line(values,'before',x,y,'#97a6aa');line(values,'after',x,y,'#4aefbc',[5,3]);
        ctx.strokeStyle='#d6bd68';ctx.setLineDash([4,4]);ctx.beginPath();ctx.moveTo(left,y(guide));ctx.lineTo(right,y(guide));ctx.stroke();ctx.setLineDash([]);
        if(finite(ratio.value)){ctx.strokeStyle='#ba91eb';ctx.setLineDash([2,5]);ctx.beginPath();ctx.moveTo(left,y(ratio.value));ctx.lineTo(right,y(ratio.value));ctx.stroke();ctx.setLineDash([]);text(`PLR ${fmt(ratio.value)} dB · original`,right,top+12,'right','#ba91eb');}}
      for(let i=0;i<=4;i++){const t=report.length*i/4;text(`${Math.floor(t/60)}:${String(Math.floor(t%60)).padStart(2,'0')}`,left+(right-left)*i/4,h-10,'center');}
    }
    if(mode!=='distribution'&&mode!=='gain'&&!proxy.length)text('Peak / short-term history unavailable or too short for a PSR proxy.',left,60);
  }
  function compare(prediction,current,metric,shift=0) {
    // Keep invalid/silent samples in the timeline: removing them invents ramps.
    const active=value=>Number.isFinite(value)&&value>-70;
    const cadence=points=>{const steps=points.slice(1).map((p,i)=>p.time-points[i].time).filter(dt=>dt>0).sort((a,b)=>a-b);return steps.length?steps[Math.floor(steps.length/2)]*3:Infinity;};
    const source=prediction.map(p=>({time:p.time+shift,value:active(p[metric])&&Number.isFinite(p.gain)&&active(p[metric]+p.gain)?p[metric]+p.gain:null}));
    const sourceGap=cadence(source),currentGap=cadence(current);
    let segment=0;
    source.forEach((p,i)=>{if(i&&(!active(p.value)||!active(source[i-1].value)||p.time-source[i-1].time>sourceGap))segment++;p.segment=segment;});
    const errors=[];let j=0,broken=true,previous=null,previousSegment=null;
    for(const p of current) {
      if(!active(p[metric])||!source.length||p.time<source[0].time||p.time>source[source.length-1].time){broken=true;continue;}
      while(j<source.length-1&&source[j+1].time<=p.time)j++;
      const a=source[j],b=source[j+1];let value=null;
      if(Math.abs(p.time-a.time)<1e-7&&active(a.value))value=a.value;
      else if(b&&active(a.value)&&active(b.value)&&a.segment===b.segment&&b.time>a.time)value=a.value+(b.value-a.value)*(p.time-a.time)/(b.time-a.time);
      if(!Number.isFinite(value)){broken=true;continue;}
      errors.push({time:p.time,error:p[metric]-value,break:broken||previousSegment!==a.segment||(previous!==null&&p.time-previous>currentGap)});
      broken=false;previous=p.time;previousSegment=a.segment;
    }
    const n=errors.length;
    return {errors,bias:n?errors.reduce((s,p)=>s+p.error,0)/n:NaN,mae:n?errors.reduce((s,p)=>s+Math.abs(p.error),0)/n:NaN,rmse:n?Math.sqrt(errors.reduce((s,p)=>s+p.error*p.error,0)/n):NaN,max:n?errors.reduce((m,p)=>Math.max(m,Math.abs(p.error)),0):NaN};
  }
  const api={rows,percentile,distribution,psrProxy,plr,render,compare};
  root.LoudnessAnalysis=api;if(typeof module!=='undefined')module.exports=api;
})(typeof globalThis!=='undefined'?globalThis:this);
