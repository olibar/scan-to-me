"""Stand-in LEDM printer for App Store screenshots.

Answers the requests Scan to Me makes while connecting and listening
(discovery tree, scan caps, status, destination registration, event-table
long-poll) so the app shows a printer as Ready in the simulator. It never
starts a scan and names no printer brand.

Usage: python3 fake_printer.py [port]   (default 8080; Ctrl-C to stop)
"""
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DEST = "/WalkupScanToComp/WalkupScanToCompDestinations/screenshot-1"

DISCOVERY = (
    '<ledm:DiscoveryTree xmlns:ledm="x" xmlns:dd="y">'
    '<ledm:SupportedIfc><ledm:ManifestURI>/WalkupScanToComp/WalkupScanToCompManifest.xml</ledm:ManifestURI></ledm:SupportedIfc>'
    '<ledm:SupportedIfc><ledm:ManifestURI>/EventMgmt/EventMgmtManifest.xml</ledm:ManifestURI></ledm:SupportedIfc>'
    '<ledm:SupportedIfc><ledm:ManifestURI>/Scan/ScanManifest.xml</ledm:ManifestURI></ledm:SupportedIfc>'
    '</ledm:DiscoveryTree>'
)
CAPS = (
    '<ScanCaps><Platen><InputSourceCaps><MaxWidth>2550</MaxWidth><MaxHeight>3508</MaxHeight>'
    '<MaxResolution>1200</MaxResolution></InputSourceCaps></Platen></ScanCaps>'
)
STATUS = '<ScanStatus><ScannerState>Idle</ScannerState><AdfState>Empty</AdfState></ScanStatus>'
EVENTS = '<ev:EventTable xmlns:ev="x" xmlns:dd="y"></ev:EventTable>'
ETAG = "screenshot-1"


class Printer(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def reply(self, status, body="", headers=None):
        data = body.encode()
        self.send_response(status)
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/DevMgmt/DiscoveryTree.xml":
            return self.reply(200, DISCOVERY)
        if path == "/Scan/ScanCaps":
            return self.reply(200, CAPS)
        if path == "/Scan/Status":
            return self.reply(200, STATUS)
        if path == "/EventMgmt/EventTable":
            if self.headers.get("If-None-Match") == ETAG:
                time.sleep(15)  # long-poll: nothing happens on this printer
                return self.reply(304)
            return self.reply(200, EVENTS, {"ETag": ETAG})
        return self.reply(404, "not found")

    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        if self.path == "/WalkupScanToComp/WalkupScanToCompDestinations":
            return self.reply(201, "", {"Location": DEST})
        return self.reply(404, "not found")

    def do_DELETE(self):
        return self.reply(200)

    def log_message(self, fmt, *args):
        sys.stderr.write("fake-printer: " + fmt % args + "\n")


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    print(f"fake-printer: listening on port {port}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", port), Printer).serve_forever()
