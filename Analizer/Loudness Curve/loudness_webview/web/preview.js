class LoudnessPreview {
  constructor(bridge, context, status) {
    this.bridge=bridge;this.context=context;this.status=status;this.$=id=>document.getElementById(id);
    this.audio=this.$('preview-audio');this.position=0;this.playing=false;this.source='file';this.token=0;
    this.$('preview-play').addEventListener('click',()=>this.toggle());
    this.$('preview-stop').addEventListener('click',()=>this.stop());
    this.ab='original';
    this.$('preview-a').addEventListener('click',()=>this.chooseAB('original'));
    this.$('preview-b').addEventListener('click',()=>this.chooseAB('processed'));
    this.$('preview-source').addEventListener('change',async()=>{await this.stop(false);this.source=this.$('preview-source').value;this.monitorFailed=false;this.render();this.onWaveformChange?.();if(this.source==='timeline')this.tick(this.token);});
    this.audio.addEventListener('timeupdate',()=>{if(this.source==='file'){this.position=this.audio.currentTime;this.render();}});
    this.audio.addEventListener('ended',()=>{this.playing=false;this.render();});
    this.audio.addEventListener('error',()=>{if(this.url&&!this.loading){this.playing=false;clearTimeout(this.timer);this.render();this.status('Audio playback failed. Choose REAPER playback or reload the matching audio.',true);}});
    window.addEventListener?.('beforeunload',()=>{this.audio.pause();clearTimeout(this.timer);});
  }
  render() {
    const c=this.context(), ready=!!c.report, line=this.$('playhead'), view=c.viewport, rect=c.canvas.getBoundingClientRect();
    this.$('preview-play').disabled=!ready||this.loading||this.recording;this.$('preview-stop').disabled=!ready||this.recording;
    for(const [id,mode] of [['preview-a','original'],['preview-b','processed']]){
      const button=this.$(id);button.disabled=!ready||this.loading||this.source!=='file';
      button.classList.toggle('active',this.ab===mode);button.setAttribute?.('aria-pressed',String(this.ab===mode));
    }
    this.$('preview-play').textContent=this.loading?'◌':this.playing?'❚❚':'▶';
    this.$('preview-play').title=this.loading?'Loading audio…':this.playing?'Pause':'Play';
    this.$('preview-play').setAttribute?.('aria-label',this.$('preview-play').title);
    this.$('preview-time').textContent=`${Math.floor(Math.max(0,this.position)/60)}:${(Math.max(0,this.position)%60).toFixed(2).padStart(5,'0')}`;
    line.hidden=!ready||!view||this.position<view.start||this.position>view.end;
    if(!line.hidden)line.style.left=`${c.pad.left+(this.position-view.start)/(view.end-view.start)*(rect.width-c.pad.left-c.pad.right)}px`;
    this.$('preview-source').title=c.channels>2?'Multichannel measurement preserves the speaker layout. Browser playback may downmix; use REAPER to check surround routing.':'File A/B or current REAPER project playback.';
    this.$('preview-note').textContent=this.source==='file'&&c.channels>2?'Multichannel · browser routing may downmix; use REAPER to audition all channels.':this.source==='file'?(this.processed()?'Processed · gain curves; REAPER FX are heard in timeline playback.':'Original audio · A/B uses the same file and playback position.'):'Current REAPER project · export edits before listening.';
  }
  processed(){return this.ab==='processed';}
  async chooseAB(mode){
    if(this.loading||this.source!=='file'||!this.context().report||mode===this.ab)return;
    this.ab=mode;await this.switchAB();
  }
  ensureGraph(){
    if(this.audioContext)return;
    const Context=window.AudioContext||window.webkitAudioContext;
    if(!Context)throw new Error('A/B preview requires Web Audio support.');
    this.audioContext=new Context();this.gainNode=this.audioContext.createGain();
    this.mediaNode=this.audioContext.createMediaElementSource(this.audio);
    this.mediaNode.connect(this.gainNode);this.gainNode.connect(this.audioContext.destination);
  }
  async prepareGain(token){
    const c=this.context();
    if(this.gainKey===c.gainKey&&this.gainPoints)return;
    if(!c.gainRequest)throw new Error('Load a valid gain curve for Processed preview.');
    const info=await this.bridge.request('preview-gain-start',c.gainRequest),points=[];
    if(!Number.isInteger(info.count)||info.count<2||info.count>2200000||Math.abs(info.length-c.report.length)>.02)throw new Error('Invalid preview gain curve');
    for(let offset=0;offset<info.count;offset+=256){
      if(token!==this.token)return;
      const chunk=await this.bridge.request('preview-gain-chunk',`${info.revision}~${offset}`);
      points.push(...chunk.points);
    }
    if(token!==this.token)return;
    if(this.context().gainKey!==c.gainKey)throw new Error('Curves changed while preparing Processed preview. Press Play again.');
    if(points.length!==info.count||points.some((p,i)=>!Number.isFinite(p.time)||!Number.isFinite(p.linear)||p.linear<=0||(i&&p.time<=points[i-1].time)))throw new Error('Invalid preview gain points');
    this.gainPoints=points;this.gainKey=c.gainKey;
  }
  scheduleGain(){
    if(!this.gainNode)return;
    const param=this.gainNode.gain,now=this.audioContext.currentTime;
    param.cancelScheduledValues(now);
    if(this.source!=='file'||!this.processed()){param.setValueAtTime(1,now);return;}
    const points=this.gainPoints;
    if(!points||this.gainKey!==this.context().gainKey){param.setValueAtTime(1,now);return;}
    const time=this.audio.currentTime,end=Math.min(this.audio.duration,time+2);
    let low=0,high=points.length-1;
    while(low+1<high){const mid=(low+high)>>1;if(points[mid].time<=time)low=mid;else high=mid;}
    const value=t=>{
      while(low+1<points.length&&points[low+1].time<=t)low++;
      const a=points[low],b=points[Math.min(low+1,points.length-1)];
      return a.linear+(b.linear-a.linear)*Math.max(0,Math.min(1,(t-a.time)/Math.max(1e-9,b.time-a.time)));
    };
    param.setValueAtTime(value(time),now);
    for(let i=low+1;i<points.length&&points[i].time<end;i++)param.linearRampToValueAtTime(points[i].linear,now+points[i].time-time);
    if(end>time)param.linearRampToValueAtTime(value(end),now+end-time);
  }
  processingChanged(){
    if(this.gainKey&&this.gainKey!==this.context().gainKey){
      this.gainKey=null;this.gainPoints=null;
      if(this.source==='file'&&this.processed()&&this.playing){
        this.audio.pause();this.position=this.audio.currentTime;this.playing=false;clearTimeout(this.timer);
        this.status('Curves changed · press Play to refresh Processed preview.');
      }
      this.scheduleGain();this.render();
    }
  }
  async switchAB(){
    const token=++this.token,resume=this.playing;
    if(this.source!=='file')return;
    this.audio.pause();this.position=this.audio.currentTime||this.position;this.playing=false;clearTimeout(this.timer);
    try{
      if(this.processed()){
        this.ensureGraph();await this.audioContext.resume();this.loading=true;this.render();
        await this.prepareGain(token);if(token!==this.token)return;
      }
      this.loading=false;this.scheduleGain();
      if(resume){await this.audio.play();this.playing=true;this.tick(token);}
    }catch(error){if(token!==this.token)return;this.loading=false;this.ab='original';this.scheduleGain();this.status(error.message,true);}
    this.render();this.onWaveformChange?.();
  }
  async reset(dropCache=true) {
    await this.stop(false);
    this.gainKey=null;this.gainPoints=null;
    if(dropCache||this.path!==this.context().path){
      this.path=null;this.url=null;this.audio.removeAttribute('src');this.audio.load();
      await this.bridge.request('preview-stream-clear').catch(()=>{});
    }
  }
  async stop(explicit=true) {
    const wasLoading=this.loading;
    ++this.token;clearTimeout(this.timer);this.loading=false;this.audio.pause();
    if(wasLoading)this.bridge.request('preview-stream-clear').catch(()=>{});
    if(this.cancelMetadata)this.cancelMetadata();
    if(this.source==='timeline'&&(explicit||this.owned)){try{await this.bridge.request('transport-stop');}catch(e){this.monitorFailed=true;this.status(e.message,true);}}
    this.playing=false;this.owned=false;this.recording=false;this.position=0;if(this.audio.readyState)this.audio.currentTime=0;this.render();
    if(this.source==='timeline'&&!this.monitorFailed&&this.context().report)this.tick(this.token);
  }
  async loadFile(token) {
    const c=this.context();
    if(this.path===c.path&&this.url){
      let valid=false;
      try{valid=(await fetch(this.url,{method:'HEAD',cache:'no-store'})).ok;}catch{}
      if(token!==this.token)return;
      if(valid){this.validateDuration(c);return;}
      await this.bridge.request('preview-stream-clear');this.path=null;this.url=null;
    }
    if(!c.path)throw new Error('Enter the matching original audio path first.');
    this.loading=true;this.render();
    let info=await this.bridge.request('preview-stream',c.path);
    while(info.starting){
      if(token!==this.token)return;
      await new Promise(resolve=>setTimeout(resolve,100));
      if(token!==this.token)return;
      info=await this.bridge.request('preview-stream-poll');
    }
    if(token!==this.token)return;
    if(!/^http:\/\/127\.0\.0\.1:\d+\/audio\/[\w-]+$/.test(info.url))throw new Error('Invalid local audio stream');
    this.path=null;this.url=info.url;
    await new Promise((resolve,reject)=>{
      const finish=error=>{clearTimeout(timer);this.cancelMetadata=null;this.audio.onloadedmetadata=null;this.audio.onerror=null;error?reject(error):resolve();};
      const timer=setTimeout(()=>finish(new Error('Audio decoding timed out. Choose REAPER playback.')),15000);
      this.cancelMetadata=()=>finish(new Error('Playback loading cancelled'));
      this.audio.onloadedmetadata=()=>finish();
      this.audio.onerror=()=>finish(new Error('This format cannot be played in the browser. Choose REAPER playback.'));
      this.audio.src=this.url;this.audio.load();
    });
    if(token!==this.token)return;
    this.validateDuration(c);
    this.path=c.path;this.loading=false;
  }
  validateDuration(c){
    if(!Number.isFinite(this.audio.duration)||Math.abs(this.audio.duration-c.report.length)>.1){
      this.path=null;this.url=null;throw new Error('Audio duration differs from the report. Choose matching original audio.');
    }
  }
  async toggle() {
    if(!this.context().report||this.loading)return;const token=++this.token;
    try{
      if(this.playing){
        if(this.source==='file'){this.audio.pause();this.position=this.audio.currentTime;}
        else{const v=await this.bridge.request('transport-pause');this.position=v.position-this.context().offset;}
        this.playing=false;clearTimeout(this.timer);
        if(this.source==='timeline')this.tick(token);
      }else{
        if(this.position>=this.context().report.length)this.position=0;
        if(this.source==='file'){
          if(this.processed()){this.ensureGraph();await this.audioContext.resume();}
          await this.loadFile(token);if(token!==this.token)return;
          if(this.processed()){this.loading=true;this.render();await this.prepareGain(token);if(token!==this.token)return;this.loading=false;}
          if(this.audioContext)await this.audioContext.resume();
          this.audio.currentTime=Math.min(this.position,this.audio.duration);this.scheduleGain();await this.audio.play();
        }else{const c=this.context();await this.bridge.request('transport-play',String(c.offset+Math.max(0,this.position)));this.owned=true;}
        if(token!==this.token){this.audio.pause();return;}this.playing=true;this.tick(token);
      }
    }catch(e){if(token!==this.token)return;this.loading=false;this.playing=false;this.status(e.name==='NotAllowedError'?'Audio is ready. Press Play again to allow playback.':e.message,true);}
    this.render();
  }
  async poll() {
    const token=this.token;
    try{const v=await this.bridge.request('transport-state');if(token!==this.token||this.source!=='timeline')return;
      this.playing=v.playing;this.recording=v.recording;this.position=v.position-this.context().offset;
      if(!v.playing&&!v.paused)this.owned=false;
      this.render();
    }catch(e){this.playing=false;this.monitorFailed=true;this.status(e.message,true);}
  }
  tick(token) {
    clearTimeout(this.timer);this.timer=setTimeout(async()=>{
      if(token!==this.token||!this.context().report||(!this.playing&&this.source==='file')||(this.source==='timeline'&&this.monitorFailed))return;
      if(this.source==='file'){this.position=this.audio.currentTime;this.scheduleGain();}else await this.poll();
      if(token!==this.token)return;
      if(this.source==='timeline'&&this.owned&&this.playing&&this.position>=this.context().report.length){await this.stop();return;}
      this.render();if(this.playing||(this.source==='timeline'&&!this.monitorFailed))this.tick(token);
    },100);
  }
  async seek(time) {
    const c=this.context();if(!c.report||this.loading)return;this.position=Math.max(0,Math.min(c.report.length,time));
    if(this.source==='file'){if(this.audio.readyState){this.audio.currentTime=this.position;this.scheduleGain();}}
    else{try{await this.bridge.request('transport-seek',String(c.offset+this.position));}catch(e){this.status(e.message,true);}}
    this.render();
  }
}
