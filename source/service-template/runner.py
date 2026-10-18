#!/usr/bin/python3.9
"""실습용 HTTP 프로세스. 실제 Loki/Alloy/Scouter/node exporter가 아닙니다."""
import http.server
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time
import urllib.request

ROOT = Path(__file__).resolve().parent
CONFIG = json.loads((ROOT / 'service.json').read_text())
PID = ROOT / 'logs' / 'service.pid'
URL = 'http://127.0.0.1:{}/health'.format(CONFIG['port'])


def healthy():
    try:
        with urllib.request.urlopen(URL, timeout=1) as response:
            return json.load(response) == CONFIG
    except (OSError, ValueError):
        return False


def own_process(pid):
    try:
        args = Path('/proc/{}/cmdline'.format(pid)).read_bytes().split(b'\0')
        return str(Path(__file__).resolve()).encode() in args and b'serve' in args
    except OSError:
        return False


def main():
    action = sys.argv[1]
    if action == 'serve':
        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                if self.path != '/health':
                    self.send_error(404)
                    return
                body = json.dumps(CONFIG).encode()
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                self.wfile.write(body)
        http.server.HTTPServer(('127.0.0.1', CONFIG['port']), Handler).serve_forever()
    elif action == 'start':
        if PID.exists() and own_process(int(PID.read_text())) and healthy():
            print(CONFIG['name'], 'already running')
            return
        PID.parent.mkdir(exist_ok=True)
        with (PID.parent / 'service.log').open('ab') as log:
            process = subprocess.Popen(
                [sys.executable, str(Path(__file__).resolve()), 'serve'],
                cwd=ROOT, stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                start_new_session=True,
            )
        PID.write_text(str(process.pid))
        for _ in range(30):
            if process.poll() is not None:
                raise RuntimeError('시작 실패: logs/service.log를 확인하세요.')
            if healthy():
                print(CONFIG['name'], 'started:', URL)
                return
            time.sleep(0.1)
        process.terminate()
        raise RuntimeError('시작 시간 초과')
    elif action == 'stop':
        if PID.exists():
            pid = int(PID.read_text())
            # PID 재사용으로 다른 프로세스를 종료하지 않도록 실행 파일까지 검사합니다.
            if own_process(pid):
                os.kill(pid, signal.SIGTERM)
                for _ in range(50):
                    if not own_process(pid):
                        break
                    time.sleep(0.1)
                else:
                    raise RuntimeError('종료 시간 초과')
            PID.unlink()
        print(CONFIG['name'], 'stopped')
    elif action == 'check':
        if not PID.exists() or not own_process(int(PID.read_text())) or not healthy():
            raise RuntimeError('정상 응답하는 실습 프로세스가 없습니다.')
        print(CONFIG['name'], 'healthy:', URL)
    else:
        raise ValueError('start, stop, check, serve 중 하나를 지정하세요.')


if __name__ == '__main__':
    main()
