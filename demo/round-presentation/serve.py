"""Serve this preview folder on loopback, including byte ranges for video seeking."""
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import argparse, re
HERE=Path(__file__).resolve().parent
class Preview(SimpleHTTPRequestHandler):
    def __init__(self,*args,**kwargs):
        super().__init__(*args,directory=str(HERE),**kwargs)
    def send_head(self):
        self.byte_range=None
        path=Path(self.translate_path(self.path))
        requested=self.headers.get('Range','')
        if path.is_file() and requested:
            match=re.fullmatch(r'bytes=(\d+)-(\d*)',requested)
            if match:
                size=path.stat().st_size
                first=int(match[1]);last=min(int(match[2]) if match[2] else size-1,size-1)
                if first>last:
                    self.send_response(416);self.send_header('Content-Range',f'bytes */{size}');self.end_headers();return None
                stream=path.open('rb')
                self.send_response(206)
                self.send_header('Content-Type',self.guess_type(str(path)))
                self.send_header('Content-Length',str(last-first+1))
                self.send_header('Content-Range',f'bytes {first}-{last}/{size}')
                self.send_header('Accept-Ranges','bytes')
                self.end_headers()
                self.byte_range=(first,last)
                return stream
        return super().send_head()
    def copyfile(self,source,outputfile):
        if self.byte_range is None:return super().copyfile(source,outputfile)
        first,last=self.byte_range;source.seek(first);left=last-first+1
        while left:
            block=source.read(min(65536,left))
            if not block:break
            outputfile.write(block);left-=len(block)
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--port',type=int,default=8786);args=parser.parse_args()
    print(f'Preview: http://127.0.0.1:{args.port}/',flush=True)
    ThreadingHTTPServer(('127.0.0.1',args.port),Preview).serve_forever()
