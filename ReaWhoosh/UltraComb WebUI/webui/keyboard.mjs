export function installTransportKeys({host=()=>globalThis.reaper,finish,onError=()=>{}}){
 let queue=Promise.resolve();
 const isSpace=e=>(e.code==='Space'||e.key===' ')&&!e.ctrlKey&&!e.altKey&&!e.metaKey&&!e.shiftKey;
 const isTextEntry=node=>node?.isContentEditable||node?.closest?.('textarea,input[type="text"],input[type="search"],input[type="email"],input[type="url"],input[type="password"],input:not([type])');
 const down=e=>{
  if(!isSpace(e)||isTextEntry(e.target))return;
  e.preventDefault();e.stopImmediatePropagation();if(e.repeat)return;
  if(document.activeElement?.matches('input[type="number"]'))document.activeElement.blur();
  const edits=finish(),r=host();
  if(!r?.GetPlayState||!r?.OnPlayButton||!r?.OnStopButton)return;
  queue=queue.then(async()=>{await edits;const state=await r.GetPlayState();if(state&5)await r.OnStopButton();else await r.OnPlayButton();}).catch(onError);
 };
 const up=e=>{if(isSpace(e)&&!isTextEntry(e.target)){e.preventDefault();e.stopImmediatePropagation();}};
 document.addEventListener('keydown',down,true);document.addEventListener('keyup',up,true);
 return ()=>{document.removeEventListener('keydown',down,true);document.removeEventListener('keyup',up,true);};
}
