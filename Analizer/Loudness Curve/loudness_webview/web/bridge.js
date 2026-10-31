class ReaperBridge {
  constructor(onPoints) {
    this.onPoints = onPoints;
    this.session = globalThis.crypto?.randomUUID?.() || `sbp-${Date.now()}-${Math.floor(Math.random()*1e8)}`;
    this.pending = new Map();
    this.id = 0;
  }
  async connect() {
    if (!window.reaper?.host?.send || !window.reaper?.events?.on)
      throw new Error('Run SBP_Loudness_Curve.lua from REAPER Actions to connect.');
    this.unsubscribe = await window.reaper.events.on('message', text => {
      let message;
      try { message = JSON.parse(text); } catch { return; }
      if (message.session !== this.session) return;
      if (message.type === 'points') { this.onPoints(message); return; }
      if (message.type !== 'response') return;
      const pending = this.pending.get(message.id);
      if (!pending) return;
      clearTimeout(pending.timer);
      this.pending.delete(message.id);
      if (message.ok) pending.resolve(message.data);
      else pending.reject(new Error(message.error || 'REAPER command failed'));
    });
    return this.request('ready');
  }
  request(command, value = '') {
    const id = ++this.id;
    return new Promise((resolve, reject) => {
      const fail = error => {
        const pending = this.pending.get(id);
        if (!pending) return;
        clearTimeout(pending.timer);
        this.pending.delete(id);
        reject(error);
      };
      const timeout=command==='file-browse'?600000:10000;
      const timer = setTimeout(() => fail(new Error(command==='file-browse'?'File selection timed out. Try Browse again.':'REAPER did not respond within 10 seconds.')), timeout);
      this.pending.set(id, {resolve, reject, timer});
      Promise.resolve(window.reaper.host.send([this.session, id, command, value].join('\t')))
        .then(accepted => { if (!accepted) fail(new Error('ReaWebAPI rejected the message.')); })
        .catch(fail);
    });
  }
}
