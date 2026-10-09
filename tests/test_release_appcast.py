import importlib.util
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "merge_release_appcast", Path(__file__).resolve().parents[1] / "scripts/merge_release_appcast.py"
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ReleaseAppcastTests(unittest.TestCase):
    def feed(self, version, url):
        return f'''<rss xmlns:sparkle="{module.SPARKLE[1:-1]}"><channel><item>
        <sparkle:version>{version}</sparkle:version>
        <enclosure url="{url}" sparkle:edSignature="signature"/>
        </item></channel></rss>'''

    def test_keeps_historical_urls_and_limits_new_release_to_arm64(self):
        with tempfile.TemporaryDirectory() as folder:
            output, history = Path(folder) / "new.xml", Path(folder) / "old.xml"
            output.write_text(self.feed("1.10.0", "https://new/zip"))
            history.write_text(self.feed("1.9.0", "https://old/zip"))
            module.merge(output, history)
            items = ET.parse(output).findall("./channel/item")
            self.assertEqual(len(items), 2)
            self.assertEqual(items[0].findtext(module.SPARKLE + "hardwareRequirements"), "arm64")
            self.assertEqual(items[1].find("enclosure").get("url"), "https://old/zip")
            self.assertEqual(items[1].find("enclosure").get(module.SPARKLE + "edSignature"), "signature")

    def test_rejects_reused_or_older_build_versions_without_writing(self):
        with tempfile.TemporaryDirectory() as folder:
            output, history = Path(folder) / "new.xml", Path(folder) / "old.xml"
            history.write_text(self.feed("1.9.0", "https://old/zip"))
            for version in ("1.8.1", "1.9.0"):
                original = self.feed(version, "https://new/zip")
                output.write_text(original)
                with self.assertRaises(ValueError):
                    module.merge(output, history)
                self.assertEqual(output.read_text(), original)
