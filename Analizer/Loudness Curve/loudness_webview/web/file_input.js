// Path buttons use the host file picker; text-field keyboard focus is optional.
(function(root){
  class LoudnessFileInput {
    static bind({field,browse,paste,kind,bridge,status,changed,blocked=()=>false}){
      let pending=false;
      const run=async mode=>{
        if(pending||field.disabled||blocked())return;
        pending=true;browse.disabled=true;paste.disabled=true;
        try{
          let result;
          if(mode==='browse')result=await bridge.request('file-browse',`${kind}~${field.value}`);
          else{
            result=await bridge.request('file-clipboard',kind);
            if(result.available===false){
              if(!globalThis.navigator?.clipboard?.readText)throw new Error('Clipboard access is unavailable. Use Browse to select the file.');
              result={path:await globalThis.navigator.clipboard.readText()};
            }
          }
          if(result.cancelled||field.disabled||blocked())return;
          if(typeof result.path!=='string'||!result.path.trim())throw new Error('No file path received. Use Browse.');
          field.value=result.path;
          if(changed)await changed();
          status('Path selected. Press Load files or Measure stems when ready.');
        }catch(error){status(error.message,true);}
        finally{pending=false;browse.disabled=field.disabled||blocked();paste.disabled=field.disabled||blocked();}
      };
      browse.addEventListener('click',()=>run('browse'));
      paste.addEventListener('click',()=>run('paste'));
    }
  }
  root.LoudnessFileInput=LoudnessFileInput;
  if(typeof module==='object')module.exports=LoudnessFileInput;
})(typeof window==='object'?window:globalThis);
