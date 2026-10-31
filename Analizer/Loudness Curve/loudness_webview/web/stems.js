(function(root){
  'use strict';
  const colors=['#68d9b4','#70baf2','#f28cdb','#edc166','#ab9bff','#ee9272','#8dcc70','#c8d8dc'];
  const storage='SBP.LoudnessCurve.stems.v1',finite=Number.isFinite,fmt=v=>finite(v)?v.toFixed(1):'—';
  function normalizePath(value){
    let path=String(value??'').trim().replace(/^"(.*)"$/,'$1');
    if(/^file:\/\//i.test(path)){
      const match=path.match(/^file:\/\/([^/]*)(\/.*)$/i);
      if(!match||(match[1]&&match[1].toLowerCase()!=='localhost'))throw new Error('Use a local file URL (remote hosts are not supported)');
      try{path=decodeURIComponent(match[2]);}catch(_){throw new Error('Invalid file URL encoding');}
      if(/^\/[a-z]:[\\/]/i.test(path))path=path.slice(1);
    }
    return /^[a-z]:[\\/]/i.test(path)?path.replace(/\//g,'\\'):path;
  }
  function validPath(value){let path;try{path=normalizePath(value);}catch(_){return false;}return (/^[a-z]:[\\/]/i.test(path)||/^\/(?!\/)/.test(path))&&/\.wave?$/i.test(path)&&!/[\x00\r\n\t]/.test(path);}
  function validate(data){
    if(!data||!finite(data.duration)||data.duration<=0||data.duration>21600||!Array.isArray(data.points)||data.points.length>6000||!data.fingerprint)throw new Error('Invalid stem measurement');
    let previous=-Infinity;
    for(const p of data.points){
      if(!finite(p.time)||p.time<=previous||p.time<0||p.time>data.duration+.001)throw new Error('Invalid stem history');
      for(const key of ['momentary','short_term'])if(p[key]!==null&&!finite(p[key]))throw new Error('Invalid stem level');
      previous=p.time;
    }
    return data;
  }
  class LoudnessStems{
    constructor(context,onMeasure,onEdit,{bridge,status}={}){
      this.bridge=bridge;this.status=status;
      this.context=context;this.rows=[];this.locked=false;
      this.onEdit=onEdit;
      this.$=id=>document.getElementById(id);
      let saved;
      try{saved=JSON.parse(localStorage.getItem(storage));}catch(_){}
      if(Array.isArray(saved))saved=saved.filter(row=>row&&typeof row==='object');
      if(!Array.isArray(saved)||!saved.length)saved=['Dialogue','Music','SFX'].map(name=>({name,path:'',offset:0,visible:true}));
      for(const row of saved.slice(0,8))this.add(row,false);
      this.$('stem-add').addEventListener('click',()=>this.add());
      this.$('stem-measure').addEventListener('click',onMeasure);
      for(const id of ['stem-metric','stem-master'])this.$(id).addEventListener('change',()=>this.render());
      this.$('stems-panel').addEventListener('toggle',()=>this.render());
      this.$('stem-canvas').addEventListener('mousemove',event=>this.scan(event));
      this.$('stem-canvas').addEventListener('mouseleave',()=>this.note());
      this.render();
    }
    persist(){try{localStorage.setItem(storage,JSON.stringify(this.rows.map(({name,path,offset,visible,edit})=>({name,path,offset,visible,edit}))));}catch(_){} }
    add(config={},save=true){
      if(this.locked||this.rows.length>=8)return;
      const row={name:typeof config.name==='string'?config.name:`Stem ${this.rows.length+1}`,path:typeof config.path==='string'?config.path:'',offset:finite(config.offset)?config.offset:0,visible:config.visible!==false,data:null,edit:config.edit||null};
      this.rows.push(row);this.editor();if(save)this.persist();
    }
    editor(){
      const list=this.$('stem-files');list.replaceChildren();
      this.rows.forEach((row,index)=>{
        const line=document.createElement('div');line.className='stem-file-row';
        const input=(type,value,label)=>{const el=document.createElement('input');el.type=type;if(type==='checkbox')el.checked=value;else el.value=value;el.setAttribute('aria-label',label);el.disabled=this.locked;return el;};
        const visible=input('checkbox',row.visible,'Show stem');visible.style.accentColor=colors[index];
        visible.addEventListener('change',()=>{row.visible=visible.checked;this.persist();this.render();});
        const name=input('text',row.name,'Stem name');name.style.color=colors[index];name.placeholder='Stem name';
        name.addEventListener('change',()=>{row.name=name.value.trim()||`Stem ${index+1}`;this.persist();this.render();});
        const path=input('text',row.path,'Absolute WAV stem path');path.placeholder='/Users/name/renders/Stem.wav or C:\\renders\\Stem.wav';path.spellcheck=false;
        path.addEventListener('change',()=>{try{row.path=normalizePath(path.value);}catch(_){row.path=path.value.trim();}row.data=null;this.persist();this.render();});
        const offset=input('number',row.offset,'Stem start relative to master, seconds');offset.step='0.001';offset.title='Positive: stem starts later than master render. Metrics measure the whole file.';
        offset.addEventListener('change',()=>{const value=Number(offset.value);if(finite(value)&&Math.abs(value)<=21600)row.offset=value;offset.value=row.offset;this.persist();this.render();});
        const edit=document.createElement('button');edit.textContent='Edit';edit.title='Open this stem in the shared curve editor';edit.disabled=this.locked||!row.data?.source_id;
        edit.addEventListener('click',()=>this.onEdit?.(row));
        const remove=document.createElement('button');remove.textContent='×';remove.title='Remove stem';remove.disabled=this.locked;
        remove.addEventListener('click',()=>{this.rows.splice(index,1);this.persist();this.editor();this.render();});
        const pathEntry=document.createElement('div');pathEntry.className='path-entry';
        const browse=document.createElement('button'),paste=document.createElement('button');browse.textContent='Browse…';paste.textContent='Paste path';
        for(const button of [browse,paste]){button.type='button';button.className='tool';button.disabled=this.locked;}
        root.LoudnessFileInput.bind({field:path,browse,paste,kind:'stem',bridge:this.bridge,status:this.status,blocked:()=>this.locked,changed:()=>path.dispatchEvent(new Event('change'))});
        pathEntry.append(path,browse,paste);
        line.append(visible,name,pathEntry,offset,remove,edit);list.append(line);
      });
      this.$('stem-add').disabled=this.locked||this.rows.length>=8;
    }
    configs(){
      const rows=this.rows.filter(row=>row.path.trim());
      if(!rows.length)throw new Error('Enter at least one absolute WAV stem path');
      for(const row of rows)if(!validPath(row.path))throw new Error(`Invalid WAV path: ${row.name}`);
      return rows;
    }
    busy(value){this.locked=value;this.editor();this.render();}
    accept(results){for(const {data} of results)validate(data);for(const {row,data} of results)row.data=data;this.editor();this.render();}
    note(){
      const measured=this.rows.filter(r=>r.data).length;
      this.$('stem-note').textContent=measured?`${measured} measured stems · whole-file fingerprints · shared master time view · display history keeps M/S extrema (up to 6,000 points per stem).`:'Enter WAV paths, then Measure stems. Matching render start is recommended; use Start offset for alignment.';
    }
    render(){
      const state=this.context();this.$('stem-measure').disabled=this.locked||state.busy||!state.report;
      if(!this.$('stems-panel').open)return;
      const tbody=this.$('stem-table');tbody.replaceChildren();
      for(const [index,row] of this.rows.entries()){
        if(!row.data)continue;
        const d=row.data,f=d.fingerprint,tr=document.createElement('tr');
        const values=[row.name,`${d.duration.toFixed(1)} s`,`${d.channel_layout} · ${d.sample_rate/1000} kHz`,fmt(f.i),fmt(f.lra),fmt(f.true_peak),fmt(f.sample_peak),fmt(f.plr),fmt(f.crest),fmt(f.rms),`${fmt(f.m_max)} / ${fmt(f.s_max)}`];
        values.forEach((value,i)=>{const td=document.createElement('td');td.textContent=value;if(i===0){td.style.color=colors[index];td.title=d.path;}if(i===4&&d.duration<60)td.title='LRA is less stable for short material; unavailable below 3 seconds.';tr.append(td);});tbody.append(tr);
      }
      this.note();this.graph(state);
    }
    graph(state){
      const canvas=this.$('stem-canvas'),ctx=canvas.getContext('2d'),rect=canvas.getBoundingClientRect(),dpr=root.devicePixelRatio||1;
      const width=Math.max(1,rect.width),height=Math.max(1,rect.height);canvas.width=Math.round(width*dpr);canvas.height=Math.round(height*dpr);ctx.setTransform(dpr,0,0,dpr,0,0);ctx.clearRect(0,0,width,height);
      const start=state.viewport?.start||0,end=state.viewport?.end||state.report?.length||1,span=Math.max(.001,end-start),keys=this.$('stem-metric').value==='both'?['momentary','short_term']:[this.$('stem-metric').value==='m'?'momentary':'short_term'];
      let minimum=-40,maximum=-10;
      const active=this.rows.filter(row=>row.visible&&row.data);
      const levels=[state.target];for(const row of active)for(const point of row.data.points)if(point.time+row.offset>=start&&point.time+row.offset<=end)for(const key of keys)if(finite(point[key])&&point[key]>-70)levels.push(point[key]);
      if(this.$('stem-master').checked)for(const point of state.points||[])if(point.time>=start&&point.time<=end)for(const key of keys)if(finite(point[key])&&point[key]>-70)levels.push(point[key]);
      if(levels.length){minimum=Math.max(-70,Math.floor(levels.reduce((a,b)=>Math.min(a,b),Infinity)/5)*5-5);maximum=Math.ceil(levels.reduce((a,b)=>Math.max(a,b),-Infinity)/5)*5+5;}
      const x=t=>54+(t-start)/span*(width-68),y=v=>14+(maximum-v)/(maximum-minimum)*(height-40);
      this.view={start,end,width,x,y};ctx.font='10px Segoe UI';ctx.lineWidth=1;
      for(let level=minimum;level<=maximum;level+=5){ctx.strokeStyle='#30393a';ctx.beginPath();ctx.moveTo(54,y(level));ctx.lineTo(width-14,y(level));ctx.stroke();ctx.fillStyle='#a7b5b5';ctx.textAlign='right';ctx.fillText(String(level),47,y(level)+3);}
      ctx.textAlign='left';ctx.fillStyle='#a7b5b5';ctx.fillText('LUFS',4,11);
      for(let i=0;i<=4;i++){const time=start+span*i/4,second=span<20?(time%60).toFixed(2).padStart(5,'0'):String(Math.floor(time%60)).padStart(2,'0');ctx.fillStyle='#a7b5b5';ctx.textAlign='center';ctx.fillText(`${Math.floor(time/60)}:${second}`,x(time),height-7);}
      ctx.save();ctx.beginPath();ctx.rect(54,14,width-68,height-40);ctx.clip();
      const path=(points,key,color,offset=0,dash=[])=>{ctx.beginPath();ctx.strokeStyle=color;ctx.lineWidth=1.8;ctx.setLineDash(dash);let connected=false;for(let i=0;i<points.length;i++){const p=points[i],t=p.time+offset;if(t<start&&i+1<points.length&&points[i+1].time+offset<start)continue;if(t>end&&i&&points[i-1].time+offset>end)break;const level=p[key];if(!finite(level)||level<=-70){connected=false;continue;}if(connected)ctx.lineTo(x(t),y(level));else ctx.moveTo(x(t),y(level));connected=true;}ctx.stroke();ctx.setLineDash([]);};
      for(const row of active)for(const key of keys)path(row.data.points,key,colors[this.rows.indexOf(row)],row.offset,key==='momentary'&&keys.length===2?[3,3]:[]);
      if(this.$('stem-master').checked)for(const key of keys)path(state.points||[],key,'#a9b4b8',0,[6,4]);
      ctx.strokeStyle='#fff19a80';ctx.lineWidth=1;ctx.beginPath();ctx.moveTo(54,y(state.target));ctx.lineTo(width-14,y(state.target));ctx.stroke();ctx.restore();
      ctx.textAlign='right';ctx.fillStyle='#fff19a';ctx.fillText(`MASTER TARGET ${fmt(state.target)} LUFS-I`,width-18,12);
      if(!active.length){ctx.textAlign='center';ctx.fillStyle='#8e9e9e';ctx.fillText('No visible measured stems',width/2,height/2);}
    }
    scan(event){
      if(!this.view)return;const rect=this.$('stem-canvas').getBoundingClientRect(),v=this.view,t=v.start+(event.clientX-rect.left-54)/(v.width-68)*(v.end-v.start);
      if(t<v.start||t>v.end)return;
      const values=[];
      for(const row of this.rows){if(!row.visible||!row.data)continue;const time=t-row.offset;if(time<0||time>row.data.duration)continue;
        const points=row.data.points;let low=0,high=points.length;while(low<high){const mid=(low+high)>>1;if(points[mid].time<time)low=mid+1;else high=mid;}
        const a=points[Math.max(0,low-1)],b=points[Math.min(points.length-1,low)],p=a&&b?(Math.abs(a.time-time)<Math.abs(b.time-time)?a:b):null;
        if(p)values.push(`${row.name}: M ${fmt(p.momentary)} / S ${fmt(p.short_term)}`);
      }
      this.$('stem-note').textContent=`${t.toFixed(2)} s · nearest displayed sample · ${values.join(' · ')||'No stem here'}`;
    }
  }
  LoudnessStems.normalizePath=normalizePath;
  root.LoudnessStems=LoudnessStems;
  if(typeof module==='object')module.exports={LoudnessStems,validPath,normalizePath,validate};
})(typeof window==='object'?window:globalThis);
