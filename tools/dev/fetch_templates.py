"""Extrait uniquement les templates Windows du .tpz Godot via des requêtes HTTP Range (évite 1,2 Go de téléchargement)."""
import io
import os
import sys
import urllib.request
import zipfile

URL = sys.argv[1]
OUT = sys.argv[2]
WANTED = ("windows_release_x86_64.exe", "windows_debug_x86_64.exe", "version.txt")


class HttpRangeFile(io.RawIOBase):
    def __init__(self, url):
        req = urllib.request.Request(url, method="HEAD", headers={"User-Agent": "curl/8"})
        with urllib.request.urlopen(req) as r:
            self.url = r.geturl()
            self.size = int(r.headers["Content-Length"])
        self.pos = 0

    def seekable(self):
        return True

    def readable(self):
        return True

    def tell(self):
        return self.pos

    def seek(self, off, whence=0):
        if whence == 0:
            self.pos = off
        elif whence == 1:
            self.pos += off
        else:
            self.pos = self.size + off
        return self.pos

    def read(self, n=-1):
        if n is None or n < 0:
            n = self.size - self.pos
        if n == 0 or self.pos >= self.size:
            return b""
        end = min(self.pos + n, self.size) - 1
        req = urllib.request.Request(self.url, headers={"Range": f"bytes={self.pos}-{end}", "User-Agent": "curl/8"})
        with urllib.request.urlopen(req) as r:
            data = r.read()
        self.pos += len(data)
        return data

    def readinto(self, b):
        data = self.read(len(b))
        b[: len(data)] = data
        return len(data)


f = io.BufferedReader(HttpRangeFile(URL), buffer_size=1 << 20)
z = zipfile.ZipFile(f)
os.makedirs(OUT, exist_ok=True)
for info in z.infolist():
    name = info.filename.split("/")[-1]
    if name in WANTED:
        print("extract", info.filename, info.file_size, flush=True)
        with z.open(info) as src, open(os.path.join(OUT, name), "wb") as dst:
            while True:
                chunk = src.read(1 << 22)
                if not chunk:
                    break
                dst.write(chunk)
print("done")
