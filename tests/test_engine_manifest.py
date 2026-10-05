import hashlib
import importlib.util
import pathlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('engine_verify', pathlib.Path(__file__).parents[1] / 'scripts/verify_engine.py')
engine = importlib.util.module_from_spec(spec)
spec.loader.exec_module(engine)


class EngineManifestTests(unittest.TestCase):
    def test_library_tampering_and_link_changes_are_detected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            app = root / 'mitmproxy.app'
            app.mkdir()
            binary = app / 'mitmdump'
            binary.write_bytes(b'pinned executable')
            library = app / 'library'
            library.write_bytes(b'pinned library')
            link = app / 'alias'
            link.symlink_to('library')
            metadata = {'filename': 'mitmproxy.app/mitmdump',
                        'sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
                        'bundleSHA256': engine.tree_digest(app)}
            engine.verify(root, metadata)
            library.write_bytes(b'tampered library')
            with self.assertRaises(SystemExit):
                engine.verify(root, metadata)
            library.write_bytes(b'pinned library')
            link.unlink()
            link.symlink_to('mitmdump')
            with self.assertRaises(SystemExit):
                engine.verify(root, metadata)


if __name__ == '__main__':
    unittest.main()
