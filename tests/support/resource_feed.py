"""Owned NuGet v2 feed for native prerelease dependency verification."""

import argparse
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
import selectors
import sys
from urllib.parse import parse_qs, unquote, urlsplit
import xml.etree.ElementTree as ET
import zipfile


ATOM = "http://www.w3.org/2005/Atom"
DATA = "http://schemas.microsoft.com/ado/2007/08/dataservices"
META = "http://schemas.microsoft.com/ado/2007/08/dataservices/metadata"
VERSION = "0.1.0-alpha2"
for prefix, namespace in (("", ATOM), ("d", DATA), ("m", META)):
    ET.register_namespace(prefix, namespace)


def read_packages(root):
    packages = {}
    for name in ("LibTmux", "LibTmux.Workspace"):
        path = root / f"{name}.{VERSION}.nupkg"
        with zipfile.ZipFile(path) as archive:
            document = ET.fromstring(archive.read(f"{name}.nuspec"))
        metadata = document.find("{*}metadata")
        fields = {child.tag.rsplit("}", 1)[-1]: child.text or "" for child in metadata}
        dependencies = metadata.findall("{*}dependencies/{*}dependency")
        expected = [("LibTmux", f"[{VERSION}]")] if name.endswith(".Workspace") else []
        actual = [(dependency.get("id"), dependency.get("version"))
                  for dependency in dependencies]
        if fields["id"] != name or fields["version"] != VERSION or actual != expected:
            raise ValueError("The fixture requires the exact tested alpha identities and dependency")
        packages[name.lower()] = (fields, actual, path.read_bytes())
    return packages


def feed(record):
    root = ET.Element(f"{{{ATOM}}}feed")
    ET.SubElement(root, f"{{{META}}}count").text = "1" if record else "0"
    if record:
        fields, dependencies, _payload = record
        entry = ET.SubElement(root, f"{{{ATOM}}}entry")
        properties = ET.SubElement(entry, f"{{{META}}}properties")
        values = {
            "Id": fields["id"], "Version": fields["version"],
            "NormalizedVersion": fields["version"], "IsPrerelease": "true",
            "Dependencies": "|".join(f"{name}:{version}:" for name, version in dependencies),
            "Tags": "PSModule " + fields.get("tags", ""),
            "Authors": fields.get("authors", ""),
            "Description": fields.get("description", ""),
            "Published": "2026-10-10T00:00:00Z",
        }
        for name, value in values.items():
            ET.SubElement(properties, f"{{{DATA}}}{name}").text = value
    return ET.tostring(root, encoding="utf-8", xml_declaration=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package-root", required=True, type=Path)
    arguments = parser.parse_args()
    packages = read_packages(arguments.package_root)

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            request = urlsplit(self.path)
            if request.path == "/api/v2/FindPackagesById()":
                name = parse_qs(request.query).get("id", [""])[0].strip("'").lower()
                body, content_type = feed(packages.get(name)), "application/atom+xml"
            elif request.path.lower().startswith("/api/v2/package/"):
                parts = unquote(request.path).split("/")
                if len(parts) != 6 or parts[5] != VERSION or parts[4].lower() not in packages:
                    self.send_error(404)
                    return
                body, content_type = packages[parts[4].lower()][2], "application/octet-stream"
            else:
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, _format, *args):
            pass

    with HTTPServer(("127.0.0.1", 0), Handler) as server:
        print(f"http://127.0.0.1:{server.server_port}/api/v2", flush=True)
        # The parent owns stdin; closing it wakes teardown without polling.
        with selectors.DefaultSelector() as events:
            events.register(sys.stdin.buffer, selectors.EVENT_READ)
            events.register(server, selectors.EVENT_READ)
            while True:
                for event, _mask in events.select():
                    if event.fileobj is sys.stdin.buffer:
                        return
                    server.handle_request()


if __name__ == "__main__":
    main()
