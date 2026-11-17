#!/usr/bin/env python3
"""Generate and sign Chuu's public GitHub Releases appcast."""
import argparse
import datetime
import pathlib
import plistlib
import re
import subprocess
import xml.etree.ElementTree as ET
import zipfile
from urllib.parse import urlsplit

NAMESPACE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", NAMESPACE)


def make_feed(info, download_url, length, signature, notes, published_at):
    version = info["CFBundleShortVersionString"]
    build = info["CFBundleVersion"]
    if not re.fullmatch(r"[0-9]{8}\.[0-9]+", build):
        raise ValueError("Use a unique YYYYMMDD.N build number")
    if info["CFBundleIdentifier"] != "moe.khan.MouseControl":
        raise ValueError("Not a Chuu archive")
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        raise ValueError("Invalid marketing version")
    expected = f"https://github.com/Imyukehan/Chuu/releases/download/v{version}/Chuu-{version}-{build}-arm64.zip"
    if download_url != expected or urlsplit(download_url).query:
        raise ValueError("Download URL must be the matching public Chuu release archive")
    rss = ET.Element("rss", version="2.0")
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = "Chuu Updates"
    item = ET.SubElement(channel, "item")
    ET.SubElement(item, "title").text = "Chuu " + version
    ET.SubElement(item, "pubDate").text = published_at
    ET.SubElement(item, "description").text = notes
    ET.SubElement(item, f"{{{NAMESPACE}}}minimumSystemVersion").text = info.get("LSMinimumSystemVersion", "14.0")
    ET.SubElement(item, "enclosure", {
        "url": download_url,
        "length": str(length), "type": "application/octet-stream",
        f"{{{NAMESPACE}}}version": build,
        f"{{{NAMESPACE}}}shortVersionString": version,
        f"{{{NAMESPACE}}}edSignature": signature,
    })
    return ET.ElementTree(rss)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=pathlib.Path)
    parser.add_argument("notes", type=pathlib.Path, help="Reviewed release notes in HTML")
    parser.add_argument("output", type=pathlib.Path, help="Staging XML; copy to release/chuu-appcast.xml only after review")
    args = parser.parse_args()
    root = pathlib.Path(__file__).resolve().parents[2]
    sign = root / "build/Chuu/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
    with zipfile.ZipFile(args.archive) as archive:
        if any(pathlib.PurePosixPath(name).name.startswith("._") for name in archive.namelist()):
            raise ValueError("AppleDouble entries found in archive")
        info = plistlib.loads(archive.read("Chuu.app/Contents/Info.plist"))
    signature = subprocess.check_output([str(sign), "--account", "moe.khan.MouseControl", "-p", str(args.archive)], text=True).strip()
    version, build = info["CFBundleShortVersionString"], info["CFBundleVersion"]
    filename = f"Chuu-{version}-{build}-arm64.zip"
    if args.archive.name != filename:
        raise ValueError("Archive filename does not match its version/build")
    download_url = f"https://github.com/Imyukehan/Chuu/releases/download/v{version}/{filename}"
    feed = make_feed(info, download_url, args.archive.stat().st_size, signature,
                     args.notes.read_text(), datetime.datetime.now(datetime.timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000"))
    if args.output.exists():
        raise ValueError("Output already exists; choose a new staging path")
    ET.indent(feed, space="  ")
    feed.write(args.output, encoding="utf-8", xml_declaration=True)
    subprocess.run([str(sign), "--account", "moe.khan.MouseControl", str(args.output)], check=True)
    subprocess.run([str(sign), "--account", "moe.khan.MouseControl", "--verify", str(args.output)], check=True)
    print(f"Signed staging appcast: {args.output}. Nothing was pushed or published.")


if __name__ == "__main__":
    main()
