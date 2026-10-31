"""Measure a projected render with a validated speaker layout, without modifying the input or REAPER."""
import json
import hashlib
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import threading
import time

RATE = 48000
FLAGS = getattr(subprocess, "CREATE_NO_WINDOW", 0)
CONTROL = None

class JobControl:
    def __init__(self, request):
        self.cancel = Path(request['_cancel_path'])
        self.progress = Path(request['_progress_path'])
        self.started = time.monotonic()
        self.limit = max(1800, float(request['length']) * 2 + 300)
        self.lock = threading.RLock()
        self.processes = []
        self.stopped = threading.Event()
        self.reason = None
        self.state = {'phase':'Preparing','percent':0,'processed':0,'completed':0,'total':len(request.get('scenes',[]))}
        self.thread = threading.Thread(target=self.watch,daemon=True)
        self.thread.start()

    def check(self):
        if self.reason:
            raise ValueError(self.reason)
        if self.cancel.exists():
            raise ValueError('Measurement cancelled')

    def update(self, **values):
        with self.lock:
            self.state.update(values)
            fields = {**self.state,'elapsed':round(time.monotonic()-self.started,1)}
            temporary = Path(str(self.progress)+'.writing')
            temporary.write_text('\n'.join(f'{k}={v}' for k,v in fields.items()),encoding='utf-8')
            try:
                os.replace(temporary,self.progress)
            except PermissionError:
                # A brief reader lock on Windows must not abort an audio scan.
                pass

    def watch(self):
        while not self.stopped.wait(.2):
            if self.cancel.exists() or time.monotonic()-self.started>self.limit:
                with self.lock:
                    self.reason = 'Measurement cancelled' if self.cancel.exists() else 'Measurement timed out'
                    for process in self.processes:
                        if process.poll() is None:
                            try: process.kill()
                            except OSError: pass
                return
            self.update()

    def close(self):
        self.stopped.set();self.thread.join(timeout=2)
        with self.lock:
            for process in self.processes:
                if process.poll() is None:
                    process.kill();process.wait()

def launch(args, **kwargs):
    if CONTROL: CONTROL.check()
    process = subprocess.Popen(args,creationflags=FLAGS,**kwargs)
    if CONTROL:
        with CONTROL.lock:
            CONTROL.processes.append(process)
            if CONTROL.reason or CONTROL.cancel.exists():
                if process.poll() is None: process.kill();process.wait()
                CONTROL.check()
    return process

def progress(request, **values):
    if CONTROL:
        CONTROL.check();CONTROL.update(**values)
    elif request.get('_progress_path'):
        path=Path(request['_progress_path']);temporary=Path(str(path)+'.writing')
        temporary.write_text('\n'.join(f'{k}={v}' for k,v in values.items()),encoding='utf-8');os.replace(temporary,path)

def temporary_log(request):
    return tempfile.TemporaryFile(dir=request.get('cache_dir'))

def meter_filter():
    # Metadata avoids the rounded 0.1 LU summary. Measure TP in dB after the
    # same 192 kHz double-precision SWR oversampling used by FFmpeg ebur128.
    return ('ebur128=metadata=1:framelog=quiet,ametadata=print,'
            'aresample=192000:osf=dbl,'
            'astats=metadata=1:reset=0:measure_perchannel=none:measure_overall=Peak_level,'
            'ametadata=print:key=lavfi.astats.Overall.Peak_level')

def meter_values(file, history_duration=None, sample_peaks=None, peak_step=.1):
    values={};maxima={'M':None,'S':None}
    buckets={};frame=None
    def retain():
        if frame is None or history_duration is None:return
        point={'time':min(history_duration,frame['time']+.1),
               'momentary':frame.get('M') if frame['time']+.1>=.399 else None,
               'short_term':frame.get('S') if frame['time']+.1>=2.999 else None,
               'integrated':frame.get('I') if frame.get('I',-70)>-70 else None}
        if sample_peaks is not None:
            index=min(len(sample_peaks)-1,max(0,round(frame['time']/peak_step)))
            amplitude=sample_peaks[index] if index>=0 else 0
            point['peak']=20*math.log10(amplitude) if amplitude>0 else None
        bucket=min(599,int(point['time']/history_duration*600))
        group=buckets.setdefault(bucket,{'first':point})
        group['last']=point
        for key in ('momentary','short_term','integrated','peak'):
            if point.get(key) is None:continue
            for extreme,compare in (('min',lambda a,b:a<b),('max',lambda a,b:a>b)):
                name=key+extreme
                if name not in group or compare(point[key],group[name][key]):group[name]=point
    file.seek(0)
    for raw in file:
        line=raw.decode('utf-8','replace') if isinstance(raw,bytes) else raw
        if history_duration is not None:
            timestamp=re.search(r'Parsed_ametadata_1\b.*pts_time:([-+\d.eE]+)',line)
            if timestamp:
                retain();frame={'time':float(timestamp[1])}
        m=re.search(r'lavfi\.r128\.(M|S|I|LRA)=([-+\d.eE]+)',line)
        if m:
            key,value=m[1],float(m[2]);values[key]=value
            if frame is not None:frame[key]=value
            if key in maxima and value>-70:maxima[key]=value if maxima[key] is None else max(maxima[key],value)
        m=re.search(r'(?:lavfi\.astats\.Overall\.Peak_level=|Peak level dB: )([^\s]+)',line)
        if m:
            value=float(m[1]);values['TP']=value if math.isfinite(value) else None
    # A scene shorter than the 100ms metadata frame has no integrated window.
    values.setdefault('I',-70.0)
    if 'TP' not in values:raise ValueError('Precise oversampled peak metadata unavailable')
    values.update({'m_max':maxima['M'],'s_max':maxima['S']})
    if history_duration is not None:
        retain()
        points={p['time']:p for group in buckets.values() for p in group.values()}
        values['history']=[points[t] for t in sorted(points)]
    return values

def scan_original(request, end_percent):
    progress(request,phase='Original audio',percent=0,processed=0)
    with temporary_log(request) as log:
        process=launch([request['ffmpeg'],'-hide_banner','-nostats','-nostdin','-progress','pipe:1','-stats_period','0.5',
            '-i',request['audio'],'-map','0:a:0','-af',meter_filter(),'-f','null','-'],stdout=subprocess.PIPE,stderr=log)
        try:
            for line in process.stdout:
                if line.startswith(b'out_time_us='):
                    try: seconds=max(0,float(line.split(b'=',1)[1])/1000000)
                    except ValueError: continue
                    progress(request,phase='Original audio',percent=round(min(1,seconds/request['length'])*end_percent,1),processed=round(seconds,1))
            if process.wait(timeout=600):
                if CONTROL: CONTROL.check()
                raise ValueError('Original audio scanner failed')
            if CONTROL: CONTROL.check()
            return meter_values(log)
        finally:
            process.stdout.close()
            if process.poll() is None: process.kill();process.wait()


def run(args):
    process=launch(args,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    try:
        stdout,stderr=process.communicate(timeout=600)
        if CONTROL: CONTROL.check()
        if process.returncode: raise ValueError(stderr.decode('utf-8','replace')[-1500:])
        return subprocess.CompletedProcess(args,process.returncode,stdout,stderr)
    finally:
        if process.poll() is None: process.kill();process.wait()


def summary(log):
    if isinstance(log,dict):
        if log['I']<=-70:raise ValueError('Audio is silent or below the integrated loudness gate')
        return log['I'],log['TP']
    tail = log.rsplit("Integrated loudness:", 1)[-1]
    integrated = re.search(r"I:\s*([-\d.]+) LUFS", tail)
    peak = re.search(r"Peak:\s*([-\d.]+) dBFS", tail)
    if not integrated:
        raise ValueError("The loudness scanner returned no integrated measurement")
    value = float(integrated[1])
    if value <= -70:
        raise ValueError("Audio is silent or below the integrated loudness gate")
    return value, float(peak[1]) if peak else None


def fingerprint(log, energy, count, sample_peak, duration):
    """Crest = maximum sample peak minus RMS averaged across all channels."""
    if isinstance(log,dict):
        integrated=log['I'] if log['I']>-70 else None
        rms=10*math.log10(energy/count) if energy>0 and count else None
        peak=20*math.log10(sample_peak) if sample_peak>0 else None
        tp=log['TP']
        return {'i':integrated,'lra':log.get('LRA') if duration>=3 and integrated is not None else None,
                'true_peak':tp,'rms':rms,'sample_peak':peak,
                'crest':peak-rms if peak is not None and rms is not None else None,
                'plr':tp-integrated if tp is not None and integrated is not None else None,
                'm_max':log['m_max'] if duration>=.4 else None,'s_max':log['s_max'] if duration>=3 else None}
    tail = log.rsplit('Integrated loudness:', 1)[-1]
    def value(pattern):
        match = re.search(pattern, tail)
        if not match:
            return None
        number = float(match[1])
        return number if math.isfinite(number) else None
    integrated = value(r'I:\s*([-\d.]+) LUFS')
    if integrated is not None and integrated <= -70:
        integrated = None
    true_peak = value(r'Peak:\s*([-\d.]+) dBFS')
    rms = 10 * math.log10(energy / count) if energy > 0 and count else None
    peak = 20 * math.log10(sample_peak) if sample_peak > 0 else None
    frames = re.findall(r'\bM:\s*([-\d.]+)\s+S:\s*([-\d.]+)', log)
    momentary = [float(m) for m, _ in frames if float(m) > -70]
    short = [float(s) for _, s in frames if float(s) > -70]
    return {'i': integrated, 'lra': value(r'LRA:\s*([-\d.]+) LU') if duration >= 3 and integrated is not None else None,
            'true_peak': true_peak, 'rms': rms, 'sample_peak': peak,
            'crest': peak - rms if peak is not None and rms is not None else None,
            'plr': true_peak - integrated if true_peak is not None and integrated is not None else None,
            'm_max': max(momentary) if momentary and duration >= .4 else None,
            's_max': max(short) if short and duration >= 3 else None}


# Explicit speaker layouts only: raw PCM does not carry channel identities.
LAYOUTS={'mono':1,'stereo':2,'2.1':3,'3.0':3,'3.0(back)':3,'4.0':4,'quad':4,'quad(side)':4,
         '5.0':5,'5.0(side)':5,'5.1':6,'5.1(side)':6,'6.1':7,'6.1(back)':7,'7.1':8,'7.1(wide)':8,'7.1(wide-side)':8}
def audio_metadata(request):
    if request.get('expected_identity'):
        identity=Path(request['audio']).stat()
        if f'{identity.st_size}:{identity.st_mtime_ns}' != request['expected_identity']:
            raise ValueError('Stem file changed since analysis. Switch to Master and measure stems again.')
    probe=str(Path(request['ffmpeg']).with_name('ffprobe.exe' if os.name == 'nt' else 'ffprobe'))
    if not Path(probe).exists():probe='ffprobe'
    metadata=json.loads(run([probe,'-v','error','-select_streams','a:0','-show_entries',
                            'stream=channels,channel_layout,sample_rate:format=duration','-of','json',request['audio']]).stdout)
    stream=metadata['streams'][0];channels=stream['channels']
    layout=stream.get('channel_layout') or ({1:'mono',2:'stereo'}.get(channels))
    if layout not in LAYOUTS or LAYOUTS[layout]!=channels:
        raise ValueError('Unknown or unsupported speaker layout. Export audio with an explicit mono/stereo/quad/5.1/7.1 channel layout; channel count alone is insufficient. Ambisonics/object audio requires a speaker render.')
    rate=int(stream['sample_rate'])
    if not 8000<=rate<=192000:raise ValueError('Precise audio measurement supports sample rates from 8 to 192 kHz')
    request['_rate']=rate
    request['_layout']=layout
    return channels,float(metadata['format']['duration']),layout

def measure(request):
    import numpy as np
    audio, ffmpeg = request["audio"], request["ffmpeg"]
    channels,duration,layout=audio_metadata(request)
    rate=request['_rate']
    if abs(duration - request["length"]) > .02:
        raise ValueError("Audio duration differs from the report. Choose the original render matching this report.")
    original_log = scan_original(request,40)
    original, original_peak = summary(original_log)
    knots = np.array([(p["time"], p["linear"]) for p in request["points"]], dtype=np.float64)
    if len(knots) < 2 or not np.isfinite(knots).all() or np.any(np.diff(knots[:, 0]) <= 0) or np.any(knots[:, 1] <= 0):
        raise ValueError("Invalid projected gain envelope")
    decode = None
    scanner = None
    with temporary_log(request) as decode_log, temporary_log(request) as scan_log:
        try:
            decode = launch([ffmpeg, "-v", "error", "-nostdin", "-i", audio, "-map", "0:a:0",
                "-ar", str(rate), "-f", "f64le", "-acodec", "pcm_f64le", "-"], stdout=subprocess.PIPE,
                stderr=decode_log)
            scanner = launch([ffmpeg, "-hide_banner", "-nostats", "-f", "f64le", "-ar", str(rate),
                "-ac", str(channels), "-channel_layout", layout, "-i", "pipe:0", "-af", meter_filter(), "-f", "null", "-"],
                stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=scan_log)
            count = 0
            original_energy = predicted_energy = original_sample_peak = predicted_sample_peak = 0.
            while True:
                data = decode.stdout.read(rate * channels * 8)
                if not data:
                    break
                samples = np.frombuffer(data, dtype="<f8").reshape(-1, channels)
                times = (count + np.arange(len(samples))) / rate
                gains = np.interp(times, knots[:, 0], knots[:, 1])
                corrected = (samples * gains[:, None]).astype("<f8")
                if not np.isfinite(corrected).all():
                    raise ValueError("Projected audio exceeds numeric range")
                scanner.stdin.write(corrected.tobytes())
                original_energy += float(np.sum(np.square(samples, dtype=np.float64)))
                predicted_energy += float(np.sum(np.square(corrected, dtype=np.float64)))
                original_sample_peak = max(original_sample_peak, float(np.max(np.abs(samples))))
                predicted_sample_peak = max(predicted_sample_peak, float(np.max(np.abs(corrected))))
                count += len(samples)
                progress(request,phase='Processed audio',percent=round(40+60*min(1,count/rate/request['length']),1),processed=round(count/rate,1))
            scanner.stdin.close()
            if decode.wait(timeout=600) or scanner.wait(timeout=600):
                if CONTROL: CONTROL.check()
                raise ValueError("Audio decoder / loudness scanner failed")
            if abs(count / rate - request["length"]) > .02:
                raise ValueError("Decoded sample duration differs from the report")
            predicted_log = meter_values(scan_log)
            after, peak = summary(predicted_log)
        finally:
            for process in (decode, scanner):
                if process is not None and process.poll() is None:
                    process.kill()
                    process.wait()
    result = {"original_i": original, "predicted_i": after, "original_peak": original_peak,
              "predicted_peak": peak, "duration": duration,"channels":channels,"channel_layout":layout,"sample_rate":rate,"measurement_engine":"ffmpeg-metadata-v2"}
    for prefix, log, energy, sample_peak in [('original', original_log, original_energy, original_sample_peak),
                                            ('predicted', predicted_log, predicted_energy, predicted_sample_peak)]:
        for key, value in fingerprint(log, energy, count * channels, sample_peak, duration).items():
            if key not in ('i', 'true_peak'):
                result[prefix + '_' + key] = value
    return result


def scan_scene(request, scene, channels, knots):
    import numpy as np
    length = scene['finish'] - scene['start']
    rate=request['_rate']
    ffmpeg = request['ffmpeg']
    processes = []
    with temporary_log(request) as decode_log, temporary_log(request) as before_log, temporary_log(request) as after_log:
        try:
            decode = launch([ffmpeg, '-v', 'error', '-nostdin', '-ss', str(scene['start']), '-i', request['audio'],
                '-t', str(length), '-map', '0:a:0', '-ar', str(rate), '-f', 'f64le', '-acodec', 'pcm_f64le', '-'],
                stdout=subprocess.PIPE, stderr=decode_log)
            processes.append(decode)
            for log in (before_log, after_log):
                processes.append(launch([ffmpeg, '-hide_banner', '-nostats', '-f', 'f64le', '-ar', str(rate),
                    '-ac', str(channels), '-channel_layout', request['_layout'], '-i', 'pipe:0', '-af', meter_filter(), '-f', 'null', '-'],
                    stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=log))
            before, after = processes[1:]
            count = 0
            energies, peaks = [0., 0.], [0., 0.]
            while True:
                data = decode.stdout.read(rate * channels * 8)
                if not data:
                    break
                samples = np.frombuffer(data, dtype='<f8').reshape(-1, channels)
                times = scene['start'] + (count + np.arange(len(samples))) / rate
                gains = np.interp(times, knots[:, 0], knots[:, 1])
                corrected = (samples * gains[:, None]).astype('<f8')
                if not np.isfinite(corrected).all():
                    raise ValueError('Projected scene audio exceeds numeric range')
                before.stdin.write(data); after.stdin.write(corrected.tobytes())
                for i, block in enumerate((samples, corrected)):
                    energies[i] += float(np.sum(np.square(block, dtype=np.float64)))
                    peaks[i] = max(peaks[i], float(np.max(np.abs(block))))
                count += len(samples)
                if '_scene_work_total' in request:
                    progress(request,phase='Scene audio',percent=round(20+80*min(1,(request['_scene_work_done']+count/rate)/request['_scene_work_total']),1),processed=round(count/rate,1),completed=request['_scene_completed'],total=len(request['scenes']))
            before.stdin.close(); after.stdin.close()
            codes = [process.wait(timeout=600) for process in processes]
            if any(codes) or abs(count / rate - length) > .02:
                raise ValueError('Scene decoder/scanner failed or its duration differs')
            results = []
            for i, log in enumerate((before_log, after_log)):
                results.append(fingerprint(meter_values(log), energies[i], count * channels, peaks[i], length))
            return {**scene, 'before': results[0], 'after': results[1], 'short_scene': length < 60, 'basis': 'audio'}
        finally:
            for process in processes:
                if process.poll() is None:
                    process.kill(); process.wait()


def measure_scenes(request):
    import numpy as np
    scenes = request['scenes']
    if not 0 < len(scenes) <= 2000:
        raise ValueError('Scene analysis supports 1–2000 scenes; select a smaller time window')
    for scene in scenes:
        if not (0 <= scene['start'] < scene['finish'] <= request['length'] + .001):
            raise ValueError('Invalid scene boundaries')
    channels,duration,layout=audio_metadata(request)
    rate=request['_rate']
    if abs(duration-request['length'])>.02:
        raise ValueError('Scene measurement needs original audio matching the report duration')
    original_i, _ = summary(scan_original(request,20))
    if request.get('source_i') is not None and abs(original_i - request['source_i']) > .3:
        raise ValueError('Original audio I differs from the report by more than 0.3 LU')
    knots = np.array([(p['time'], p['linear']) for p in request['points']], dtype=np.float64)
    if len(knots) < 2 or not np.isfinite(knots).all() or np.any(np.diff(knots[:, 0]) <= 0) or np.any(knots[:, 1] <= 0):
        raise ValueError('Invalid projected scene gain envelope')
    results = []
    request['_scene_work_total']=sum(s['finish']-s['start'] for s in scenes)
    request['_scene_work_done']=0
    for scene in scenes:
        request['_scene_completed']=len(results)
        results.append(scan_scene(request, scene, channels, knots))
        request['_scene_work_done']+=scene['finish']-scene['start']
    progress(request,phase='Completed',percent=100,completed=len(results),total=len(scenes))
    return {'original_i': original_i,'channels':channels,'channel_layout':layout,'sample_rate':rate,'measurement_engine':'ffmpeg-metadata-v2', 'scenes_json': json.dumps(results, ensure_ascii=False, allow_nan=False, separators=(',', ':'))}


def scan_audio_history(request):
    """One unprocessed stem: one decode and one meter, no master gain applied."""
    import numpy as np
    source=Path(request['audio']);identity=source.stat()
    if request.get('mode')!='audio' and source.suffix.lower() not in ('.wav','.wave'):raise ValueError('Choose a WAV stem')
    channels,duration,layout=audio_metadata(request);rate=request['_rate']
    if not math.isfinite(duration) or not 0<duration<=21600:raise ValueError('Stem duration must be between 0 and 6 hours')
    if CONTROL:CONTROL.limit=max(CONTROL.limit,duration*2+300)
    count=0;energy=0.;peak=0.;processes=[]
    frame_size=rate//10;pending=np.empty(0,dtype=np.float64);sample_peaks=[]
    with temporary_log(request) as errors, temporary_log(request) as log:
        try:
            decode=launch([request['ffmpeg'],'-v','error','-nostdin','-i',str(source),'-map','0:a:0',
                           '-ar',str(rate),'-f','f64le','-acodec','pcm_f64le','-'],stdout=subprocess.PIPE,stderr=errors)
            processes.append(decode)
            scanner=launch([request['ffmpeg'],'-hide_banner','-nostats','-f','f64le','-ar',str(rate),
                            '-ac',str(channels),'-channel_layout',layout,'-i','pipe:0','-af',meter_filter(),'-f','null','-'],
                           stdin=subprocess.PIPE,stdout=subprocess.DEVNULL,stderr=log)
            processes.append(scanner)
            while True:
                data=decode.stdout.read(rate*channels*8)
                if not data:break
                samples=np.frombuffer(data,dtype='<f8')
                if not np.isfinite(samples).all():raise ValueError('Stem contains non-finite samples')
                scanner.stdin.write(data)
                energy+=float(np.sum(np.square(samples)));peak=max(peak,float(np.max(np.abs(samples))))
                mono=np.max(np.abs(samples.reshape(-1,channels)),axis=1)
                merged=np.concatenate((pending,mono));frames=len(merged)//frame_size
                if frames:sample_peaks.extend(np.max(merged[:frames*frame_size].reshape(frames,frame_size),axis=1).tolist())
                pending=merged[frames*frame_size:].copy()
                count+=len(samples)//channels
                progress(request,phase='Stem audio',percent=round(min(99,count/rate/duration*100),1),processed=round(count/rate,1))
            scanner.stdin.close()
            if any(p.wait(timeout=600) for p in processes) or abs(count/rate-duration)>.02:
                if CONTROL:CONTROL.check()
                raise ValueError('Stem decoder/scanner failed or its duration differs')
            if len(pending):sample_peaks.append(float(np.max(pending)))
            meter=meter_values(log,duration,sample_peaks,frame_size/rate)
            if not meter['history'] and duration>=.1:raise ValueError('Stem loudness history unavailable')
            current=source.stat()
            if (current.st_size,current.st_mtime_ns)!=(identity.st_size,identity.st_mtime_ns):raise ValueError('Stem changed during analysis; rescan it')
            result={'path':str(source),'duration':duration,'channels':channels,'channel_layout':layout,'sample_rate':rate,
                    'size':identity.st_size,'modified_ns':str(identity.st_mtime_ns),'measurement_engine':'ffmpeg-metadata-v2',
                    'fingerprint':fingerprint(meter,energy,count*channels,peak,duration),'points':meter['history']}
            progress(request,phase='Completed',percent=100,processed=round(duration,1))
            return result
        finally:
            for p in processes:
                if p.poll() is None:p.kill();p.wait()
            if processes and processes[0].stdout:processes[0].stdout.close()

def measure_stem(request):
    source=Path(request['audio']);identity=source.stat();cache=None;cached=False;warning=None
    if request.get('cache_dir'):
        executable=Path(request['ffmpeg']);engine=executable.stat().st_mtime_ns if executable.exists() else 0
        key=hashlib.sha256(f'history-v4|{source.resolve()}|{identity.st_size}|{identity.st_mtime_ns}|{engine}'.encode()).hexdigest()
        cache=Path(request['cache_dir'])/f'audio-{key}.json'
        try:
            if cache.exists() and cache.stat().st_size<2*1024*1024:
                result=json.loads(cache.read_text(encoding='utf-8'))
                cached=(result.get('size')==identity.st_size and result.get('modified_ns')==str(identity.st_mtime_ns)
                        and result.get('measurement_engine')=='ffmpeg-metadata-v2'
                        and isinstance(result.get('duration'),(int,float)) and math.isfinite(result['duration']) and result['duration']>0
                        and isinstance(result.get('fingerprint'),dict) and 'i' in result['fingerprint']
                        and isinstance(result.get('points'),list) and len(result['points'])<=6000
                        and all(isinstance(p,dict) and isinstance(p.get('time'),(int,float)) and math.isfinite(p['time'])
                                and 0<=p['time']<=result['duration']
                                and all(p.get(k) is None or isinstance(p[k],(int,float)) and math.isfinite(p[k]) for k in ('momentary','short_term','integrated','peak'))
                                for p in result['points'])
                        and all(a['time']<b['time'] for a,b in zip(result['points'],result['points'][1:])))
        except (OSError,ValueError,KeyError,TypeError):cached=False
    if not cached:
        result=scan_audio_history(request)
        if cache:
            try:
                temporary=cache.with_suffix('.writing');temporary.write_text(json.dumps(result,ensure_ascii=False,allow_nan=False,separators=(',',':')),encoding='utf-8');os.replace(temporary,cache)
            except OSError as error:warning=str(error)
    current=source.stat()
    if (current.st_size,current.st_mtime_ns)!=(identity.st_size,identity.st_mtime_ns):raise ValueError('Audio changed during analysis; rescan it')
    progress(request,phase='Cached audio' if cached else 'Completed',percent=100,processed=round(result['duration'],1))
    return {'stem_json':json.dumps(result,ensure_ascii=False,allow_nan=False,separators=(',',':')),
            'stem_length':result['duration'],'stem_i':result['fingerprint']['i'],'stem_path':request['audio'],
            'stem_identity':f'{identity.st_size}:{identity.st_mtime_ns}','cached':int(cached),'cache_file':str(cache) if cache and not warning else None,'cache_error':warning}


def main():
    global CONTROL
    request_file = Path(sys.argv[1])
    output = request_file.with_suffix(".result")
    try:
        request = json.loads(request_file.read_text(encoding="utf-8"))
        request['_progress_path'] = str(request_file.with_suffix('.progress'))
        request['_cancel_path'] = str(request_file.with_suffix('.cancel'))
        CONTROL=JobControl(request);CONTROL.update()
        result = measure_stem(request) if request.get('mode') in ('stem','audio') else measure_scenes(request) if request.get('mode') == 'scenes' else measure(request)
        text = "status=ok\n" + "\n".join(f"{key}={value}" for key, value in result.items() if value is not None)
    except Exception as error:
        reason=CONTROL.reason if CONTROL and CONTROL.reason else str(error)
        text = ('status=cancelled' if request_file.with_suffix('.cancel').exists() else 'status=error')+'\nerror='+reason.replace('\n',' ').replace('\r',' ')
    finally:
        if CONTROL: CONTROL.close();CONTROL=None
    if request_file.with_suffix('.abandon').exists():
        for suffix in ('.json','.result','.cancel','.progress','.abandon'):
            request_file.with_suffix(suffix).unlink(missing_ok=True)
        return
    temporary = output.with_suffix(".writing")
    temporary.write_text(text, encoding="utf-8")
    os.replace(temporary, output)


if __name__ == "__main__":
    main()
