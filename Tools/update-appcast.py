#!/usr/bin/env python3
"""Adds (or replaces) a release in the beardfm.app appcast, newest first.

Usage: Tools/update-appcast.py <appcast> <short-version> <build> <min-macos> <url> <sign_update output> [notes.html]
The sign_update output is the `sparkle:edSignature="…" length="…"` attribute string.
"""
import re
import sys
from datetime import datetime, timezone
from email.utils import format_datetime
from html import escape

appcast, short_version, build, min_macos, url, signature_attrs = sys.argv[1:7]
notes_path = sys.argv[7] if len(sys.argv) > 7 else None

if not re.fullmatch(r'sparkle:edSignature="[^"]+" length="\d+"', signature_attrs.strip()):
    sys.exit(f"Unexpected sign_update output: {signature_attrs!r}")

notes = ""
if notes_path:
    with open(notes_path, encoding="utf-8") as f:
        notes = f"\n      <description><![CDATA[\n{f.read().strip()}\n      ]]></description>"

item = f"""    <item>
      <title>Version {escape(short_version)}</title>
      <pubDate>{format_datetime(datetime.now(timezone.utc))}</pubDate>
      <sparkle:version>{escape(build)}</sparkle:version>
      <sparkle:shortVersionString>{escape(short_version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{escape(min_macos)}</sparkle:minimumSystemVersion>{notes}
      <enclosure url="{escape(url)}" type="application/octet-stream" {signature_attrs.strip()}/>
    </item>
"""

import os

# A brand-new app has no appcast yet: start one, named after the folder it lives in (…/transcriber/appcast.xml).
if not os.path.exists(appcast):
    app_slug = os.path.basename(os.path.dirname(os.path.abspath(appcast)))
    os.makedirs(os.path.dirname(os.path.abspath(appcast)), exist_ok=True)
    with open(appcast, "w", encoding="utf-8") as f:
        f.write(f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>{escape(app_slug.capitalize())}</title>
    <link>https://beardfm.app/{escape(app_slug)}/appcast.xml</link>
    <description>{escape(app_slug.capitalize())} updates. Maintained by Tools/release.sh; newest release first.</description>
    <language>en</language>
  </channel>
</rss>
""")

with open(appcast, encoding="utf-8") as f:
    xml = f.read()

# Re-releasing the same build replaces its entry instead of duplicating it.
xml = re.sub(
    r"    <item>\n(?:(?!    </item>).)*?<sparkle:version>" + re.escape(build) + r"</sparkle:version>.*?    </item>\n",
    "",
    xml,
    flags=re.S,
)
anchor = "    <language>en</language>\n"
if anchor not in xml:
    sys.exit("appcast.xml is missing its <language> line")
xml = xml.replace(anchor, anchor + item, 1)

with open(appcast, "w", encoding="utf-8") as f:
    f.write(xml)
print(f"appcast: added {short_version} ({build})")
