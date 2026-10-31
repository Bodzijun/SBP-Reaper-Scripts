"""Serve one authorized local audio file with byte ranges; no directory browsing."""
import os
from pathlib import Path
import secrets
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MIMES = {'wav':'audio/wav','wave':'audio/wav','mp3':'audio/mpeg','flac':'audio/flac',
         'ogg':'audio/ogg','m4a':'audio/mp4','aac':'audio/aac','webm':'audio/webm'}


def serve(request_path):
    request_path = Path(request_path)
    ready, stop, lease = [request_path.with_suffix(s) for s in ('.ready','.stop','.lease')]
    server = None
    try:
        fields = dict(line.split('=',1) for line in request_path.read_text(encoding='utf-8').splitlines())
        audio = Path(fields['audio'])
        stat = audio.stat()
        if not audio.is_file() or not stat.st_size:
            raise ValueError('Audio file is empty or missing')
        mime = MIMES.get(audio.suffix.lower()[1:])
        if not mime:
            raise ValueError('Unsupported preview format')
        route = '/audio/' + secrets.token_urlsafe(32)
        fingerprint = (stat.st_size, stat.st_mtime_ns)
        size = stat.st_size

        class Handler(BaseHTTPRequestHandler):
            protocol_version = 'HTTP/1.1'

            def end_headers(self):
                self.send_header('Access-Control-Allow-Origin','*')
                super().end_headers()

            def log_message(self, *_):
                pass

            def do_HEAD(self):
                self.send_audio(False)

            def do_GET(self):
                self.send_audio(True)

            def send_audio(self, body):
                if self.path != route:
                    self.send_error(404); return
                try:
                    current = audio.stat()
                    if (current.st_size, current.st_mtime_ns) != fingerprint:
                        self.send_error(410, 'Audio changed; reload audio'); return
                    start, end, partial = 0, size-1, False
                    requested = self.headers.get('Range')
                    if requested:
                        if not requested.startswith('bytes=') or ',' in requested:
                            self.send_error(416); return
                        import re
                        if not re.fullmatch(r'\d*-\d*',requested[6:]) or requested[6:] == '-':
                            self.send_error(416); return
                        a, b = requested[6:].split('-',1)
                        if a:
                            start = int(a); end = min(size-1,int(b)) if b else size-1
                        else:
                            suffix = int(b)
                            if suffix <= 0:
                                self.send_error(416); return
                            start = max(0,size-suffix)
                        if start < 0 or start >= size or end < start:
                            self.send_response(416);self.send_header('Content-Range',f'bytes */{size}')
                            self.send_header('Content-Length','0');self.end_headers();return
                        partial = True
                    self.send_response(206 if partial else 200)
                    self.send_header('Content-Type',mime)
                    self.send_header('Content-Length',str(end-start+1))
                    self.send_header('Accept-Ranges','bytes')
                    self.send_header('Cache-Control','private, max-age=3600, immutable')
                    self.send_header('X-Content-Type-Options','nosniff')
                    if partial:
                        self.send_header('Content-Range',f'bytes {start}-{end}/{size}')
                    self.end_headers()
                    if body:
                        with audio.open('rb') as source:
                            source.seek(start); remaining = end-start+1
                            while remaining:
                                data = source.read(min(262144,remaining))
                                if not data:
                                    break
                                self.wfile.write(data);remaining -= len(data)
                except (ValueError, OSError, BrokenPipeError, ConnectionResetError):
                    self.close_connection = True

        server = ThreadingHTTPServer(('127.0.0.1',0),Handler)
        server.daemon_threads = True
        lease.touch()
        ready.with_suffix('.writing').write_text(f'status=ok\nurl=http://127.0.0.1:{server.server_port}{route}\nsize={size}\nmime={mime}\n',encoding='utf-8')
        os.replace(ready.with_suffix('.writing'),ready)

        def watch():
            while not stop.exists():
                try:
                    if time.time()-lease.stat().st_mtime > 180:
                        break
                except OSError:
                    break
                time.sleep(.5)
            server.shutdown()

        threading.Thread(target=watch,daemon=True).start()
        server.serve_forever(poll_interval=.2)
    except Exception as error:
        ready.write_text('status=error\nerror='+str(error).replace('\r',' ').replace('\n',' '),encoding='utf-8')
    finally:
        if server:
            server.server_close()
            for path in (request_path,ready,stop,lease):
                try:
                    path.unlink(missing_ok=True)
                except OSError:
                    pass


if __name__ == '__main__':
    serve(sys.argv[1])
