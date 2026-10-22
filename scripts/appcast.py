import html
import sys
import xml.etree.ElementTree as ET
from email.utils import formatdate

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ENTRIES_PER_CHANNEL = 10
ET.register_namespace("sparkle", SPARKLE)


def qualified(name):
    return f"{{{SPARKLE}}}{name}"


def channel_of(item):
    return item.findtext(qualified("channel")) or "stable"


def load(path):
    try:
        return ET.parse(path).getroot()
    except FileNotFoundError:
        rss = ET.Element("rss", {"version": "2.0"})
        channel = ET.SubElement(rss, "channel")
        ET.SubElement(channel, "title").text = "voz"
        return rss


def notes_html(path):
    with open(path) as notes:
        bullets = [line.removeprefix("- ").strip() for line in notes if line.strip()]
    return "<ul>" + "".join(f"<li>{html.escape(bullet)}</li>" for bullet in bullets) + "</ul>"


def build_item(version, build, channel, url, signature, length, release_page, notes):
    item = ET.Element("item")
    ET.SubElement(item, "title").text = f"voz {version}"
    ET.SubElement(item, "description").text = notes_html(notes)
    ET.SubElement(item, "link").text = release_page
    ET.SubElement(item, "pubDate").text = formatdate(usegmt=True)
    ET.SubElement(item, qualified("version")).text = build
    ET.SubElement(item, qualified("shortVersionString")).text = version
    ET.SubElement(item, qualified("minimumSystemVersion")).text = "26.0"
    if channel != "stable":
        ET.SubElement(item, qualified("channel")).text = channel
    ET.SubElement(item, "enclosure", {
        "url": url,
        "length": length,
        qualified("edSignature"): signature,
        "type": "application/octet-stream",
    })
    return item


def main(path, version, build, channel, url, signature, length, release_page, notes):
    rss = load(path)
    channel_element = rss.find("channel")
    items = [i for i in channel_element.findall("item") if i.findtext(qualified("version")) != build]
    items.insert(0, build_item(version, build, channel, url, signature, length, release_page, notes))
    for item in channel_element.findall("item"):
        channel_element.remove(item)
    kept = {}
    for item in sorted(items, key=lambda i: int(i.findtext(qualified("version"))), reverse=True):
        group = kept.setdefault(channel_of(item), [])
        if len(group) < ENTRIES_PER_CHANNEL:
            group.append(item)
    for item in sorted((i for group in kept.values() for i in group), key=lambda i: int(i.findtext(qualified("version"))), reverse=True):
        channel_element.append(item)
    ET.indent(rss)
    ET.ElementTree(rss).write(path, encoding="utf-8", xml_declaration=True)


if __name__ == "__main__":
    main(*sys.argv[1:])
