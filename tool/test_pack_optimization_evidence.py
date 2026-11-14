"""Check exact recovery and fail-before-output behavior of compact transport."""
import gzip
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

import pack_optimization_evidence as transport


class EvidenceTransportTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        source = self.root / "source"
        source.mkdir()
        raw = b'{"coordinate": [1.25, 2.75]}\n' * 60
        binary = io.BytesIO()
        with gzip.GzipFile(filename="sample.jsonl", fileobj=binary,
                           mode="wb", mtime=123) as stream:
            stream.write(raw)
        text = io.BytesIO()
        with gzip.GzipFile(filename="checked.jsonl", fileobj=text,
                           mode="wb", mtime=456) as stream:
            with io.TextIOWrapper(stream) as wrapper:
                wrapper.write(raw.decode())
        (source / "stdout.jsonl.gz").write_bytes(binary.getvalue())
        (source / "checked.jsonl.gz").write_bytes(text.getvalue())
        (source / "literal.gz").write_bytes(b"not actually compressed")
        (source / "empty").write_bytes(b"")
        self.original = {p.name: p.read_bytes() for p in source.iterdir()}
        self.saved = self.root / "saved"
        transport.pack(source, self.saved, "round")
        self.manifest = self.saved / "round-evidence.json"

    def edit_manifest(self, update):
        data = json.loads(self.manifest.read_text())
        update(data)
        self.manifest.write_text(json.dumps(data))

    def rejected_without_output(self):
        output = self.root / "output"
        with self.assertRaises(ValueError):
            transport.restore(self.manifest, output)
        self.assertFalse(output.exists())

    def test_exact_gzip_binary_and_text_round_trip(self):
        output = self.root / "restored"
        transport.restore(self.manifest, output)
        self.assertEqual(self.original, {p.name: p.read_bytes() for p in output.iterdir()})
        manifest = json.loads(self.manifest.read_text())
        self.assertEqual({False, True}, {e["sync_flush"] for e in manifest["files"].values()
                                      if e["encoding"] == "gzip-deflate-9"})

    def test_tampered_archive_rejected(self):
        data = json.loads(self.manifest.read_text())
        part = self.saved / data["archive_parts"][0]["file"]
        part.write_bytes(part.read_bytes()[:-1] + b"x")
        self.rejected_without_output()

    def test_tampered_final_file_rejected_before_any_output(self):
        self.edit_manifest(lambda m: m["files"]["stdout.jsonl.gz"].update(sha256="0" * 64))
        self.rejected_without_output()

    def test_traversal_rejected(self):
        self.edit_manifest(lambda m: m["files"].update({"../escape": m["files"].pop("empty")}))
        self.rejected_without_output()
        self.assertFalse((self.root / "escape").exists())

    def test_part_traversal_rejected(self):
        self.edit_manifest(lambda m: m["archive_parts"][0].update(file="../escape"))
        self.rejected_without_output()

    def test_payloads_recover_without_any_recompression(self):
        output = self.root / "raw"
        with mock.patch.object(transport, "decode", side_effect=AssertionError("must not decode")):
            transport.restore(self.manifest, output, payloads_only=True)
        manifest = json.loads((output / "recovery-manifest.json").read_text())
        for name, entry in manifest["files"].items():
            payload = (output / "payloads" / entry["payload"]).read_bytes()
            expected = self.original[name]
            if entry["encoding"] != "literal":
                expected = gzip.decompress(expected)
            self.assertEqual(expected, payload)

    def test_existing_destination_is_untouched(self):
        output = self.root / "output"
        output.mkdir()
        marker = output / "marker"
        marker.write_text("keep")
        with self.assertRaises(ValueError):
            transport.restore(self.manifest, output)
        self.assertEqual("keep", marker.read_text())

    def test_runner_sidecars_allowed_but_checkpoint_collision_refused(self):
        for suffix in (".log", "-status.json", "-summary.json"):
            (self.saved / ("another" + suffix)).write_text("preserve")
        transport.pack(self.root / "source", self.saved, "another")
        for suffix in (".log", "-status.json", "-summary.json"):
            self.assertEqual("preserve", (self.saved / ("another" + suffix)).read_text())
        with self.assertRaises(ValueError):
            transport.pack(self.root / "source", self.saved, "another")
        part = self.saved / "partial.payloads.tar.xz.part000"
        part.write_bytes(b"preserve partial evidence")
        with self.assertRaises(ValueError):
            transport.pack(self.root / "source", self.saved, "partial")
        self.assertEqual(b"preserve partial evidence", part.read_bytes())


if __name__ == "__main__":
    unittest.main()
