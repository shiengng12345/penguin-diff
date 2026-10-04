#!/usr/bin/env python3
"""Verify the packaged App uses the direct user-supplied icon and no mascot bundle."""
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest

APP = pathlib.Path(sys.argv.pop(1)).resolve()
ROOT = pathlib.Path(__file__).resolve().parent.parent
ICON = "ConfigCompare.icns"
SOURCE_ICON = ROOT / "assets" / "config-compare-icon.png"


class PackagedAssetTests(unittest.TestCase):
    def test_direct_icon_is_shipped_without_old_mascot_resources(self):
        resources = APP / "Contents/Resources"
        icon = resources / ICON
        self.assertTrue(icon.is_file())
        self.assertGreater(icon.stat().st_size, 0)
        self.assertTrue(SOURCE_ICON.is_file())
        self.assertGreater(SOURCE_ICON.stat().st_size, 0)
        self.assertFalse((resources / "ConfigCompare_CompareUI.bundle").exists())
        with tempfile.TemporaryDirectory(prefix="packaged-icon-") as temporary:
            broken = pathlib.Path(temporary) / "MissingIcon.app"
            shutil.copytree(APP, broken)
            signature = subprocess.run(["rtk", "proxy", "codesign", "--verify", "--deep", "--strict", str(broken)],
                                       capture_output=True, timeout=30)
            self.assertEqual(signature.returncode, 0, "Intact copied App must have a valid signature")
            broken_icon = broken / "Contents/Resources" / ICON
            broken_icon.unlink()
            self.assertFalse(broken_icon.exists())


if __name__ == "__main__":
    unittest.main()
