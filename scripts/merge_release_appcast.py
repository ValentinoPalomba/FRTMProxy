"""Preserve update history and restrict new releases to the bundled engine's CPU."""
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


def version(item):
    enclosure = item.find("enclosure")
    return item.findtext(SPARKLE + "version") or (
        enclosure.get(SPARKLE + "version") if enclosure is not None else None
    )


def merge(output, history):
    ET.register_namespace("sparkle", SPARKLE[1:-1])
    ET.register_namespace("dc", "http://purl.org/dc/elements/1.1/")
    tree = ET.parse(output)
    channel = tree.getroot().find("channel")
    if channel is None or len(channel.findall("item")) != 1:
        raise ValueError("Expected exactly one new release")
    item = channel.find("item")
    new_version = version(item)
    if not new_version:
        raise ValueError("New release has no build version")
    enclosure = item.find("enclosure")
    if enclosure is None or not enclosure.get(SPARKLE + "edSignature"):
        raise ValueError("New release is missing its Sparkle signature")
    hardware = item.find(SPARKLE + "hardwareRequirements")
    if hardware is None:
        hardware = ET.SubElement(item, SPARKLE + "hardwareRequirements")
    hardware.text = "arm64"
    if history.exists():
        for old in ET.parse(history).findall("./channel/item"):
            old_version = version(old)
            if not old_version:
                raise ValueError("Historical release has no build version")
            if tuple(map(int, new_version.split("."))) <= tuple(map(int, old_version.split("."))):
                raise ValueError("New build version must exceed all published versions")
            channel.append(old)
    tree.write(output, encoding="utf-8", xml_declaration=True)


if __name__ == "__main__":
    merge(Path(sys.argv[1]), Path(sys.argv[2]))
