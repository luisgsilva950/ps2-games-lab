"""Exercise packaging inputs with real temporary Git repositories, not emulator stubs."""

import json
import plistlib
import subprocess
import tempfile
import unittest
from pathlib import Path

from prepare import prepare


class PrepareTest(unittest.TestCase):
    def git(self, source, *args):
        return subprocess.check_output([
            "git", "-C", str(source), "-c", "user.name=Packaging test",
            "-c", "user.email=test@example.invalid", *args,
        ], stderr=subprocess.DEVNULL).decode().strip()

    def commit(self, source):
        self.git(source, "add", ".")
        self.git(source, "commit", "-qm", "Fixture")
        return self.git(source, "rev-parse", "HEAD")

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        root = Path(self.temporary.name)
        self.source = root / "upstream"
        self.project = root / "project"
        (self.source / "Source/ui_ios").mkdir(parents=True)
        (self.project / "ios").mkdir(parents=True)
        (self.project / "docs").mkdir()
        (self.project / "docs/ipad.md").write_text("Experimental. Signing and JIT required.")
        self.template = self.source / "Source/ui_ios/Info.plist.in"
        self.original_info = {
            "CFBundleIdentifier": "${MACOSX_BUNDLE_GUI_IDENTIFIER}",
            "CFBundleExecutable": "$(EXECUTABLE_NAME)",
            "UIRequiredDeviceCapabilities": ["armv7", "opengles-3"],
            "UIFileSharingEnabled": True,
            "LSSupportsOpeningDocumentsInPlace": True,
            "NSBonjourServices": ["_altserver._tcp"],
        }
        self.template.write_bytes(plistlib.dumps(self.original_info))
        (self.source / "License.txt").write_text("Upstream license fixture")
        self.iso = self.source / "original.iso"
        self.iso.write_bytes(b"immutable image fixture")
        self.git(self.source, "init", "-q")
        self.commit(self.source)

        dependency = root / "dependency"
        dependency.mkdir()
        self.git(dependency, "init", "-q")
        (dependency / "COPYING").write_text("Dependency license fixture")
        self.commit(dependency)
        self.git(self.source, "-c", "protocol.file.allow=always", "submodule", "add",
                 "-q", str(dependency), "deps/example")
        self.revision = self.commit(self.source)
        (self.project / "ios/play-revision.txt").write_text(self.revision + "\n")

    def test_bundle_keeps_file_import_and_jit_metadata_and_original_bytes(self):
        prepare(self.source, self.project)
        info = plistlib.loads(self.template.read_bytes())
        self.assertEqual(info["CFBundleIdentifier"], "com.luisgsilva950.ps2gameslab")
        self.assertEqual(info["UIRequiredDeviceCapabilities"], ["arm64", "opengles-3"])
        for key in ("CFBundleExecutable", "UIFileSharingEnabled",
                    "LSSupportsOpeningDocumentsInPlace", "NSBonjourServices"):
            self.assertEqual(info[key], self.original_info[key])
        self.assertEqual(self.iso.read_bytes(), b"immutable image fixture")
        notices = self.source / "PS2GamesLabNotices"
        self.assertEqual((notices / "licenses/License.txt").read_text(), "Upstream license fixture")
        self.assertEqual((notices / "licenses/deps/example/COPYING").read_text(),
                         "Dependency license fixture")
        metadata = json.loads((notices / "build-info.json").read_text())
        self.assertEqual(metadata["revision"], self.revision)
        self.assertIn("deps/example", metadata["submodules"])
        self.assertEqual(metadata["device_validation"], "not performed by this build")

    def test_wrong_revision_is_rejected_before_modifying_the_bundle(self):
        (self.project / "ios/play-revision.txt").write_text("0" * 40)
        before = self.template.read_bytes()
        with self.assertRaisesRegex(ValueError, "revision does not match"):
            prepare(self.source, self.project)
        self.assertEqual(self.template.read_bytes(), before)

    def test_missing_submodule_is_rejected(self):
        self.git(self.source, "submodule", "deinit", "-f", "--all")
        with self.assertRaisesRegex(ValueError, "submodules must be initialized"):
            prepare(self.source, self.project)

    def test_changed_submodule_revision_is_rejected(self):
        dependency = self.source / "deps/example"
        (dependency / "extra.txt").write_text("Changed dependency")
        self.commit(dependency)
        with self.assertRaisesRegex(ValueError, "submodules must be initialized"):
            prepare(self.source, self.project)


if __name__ == "__main__":
    unittest.main()
