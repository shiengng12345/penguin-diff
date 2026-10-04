#!/usr/bin/env python3
"""Exercise the actual entrypoint's routing without opening a GUI.

A small CompareUI boundary double keeps even the pre-fix GUI route harmless.
The packaged real-XPC self-test remains a separate integration check.
"""
import os
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
STUB = '''import Foundation
@MainActor public enum MCPRunner {
    public static func run() async -> Int32 { print("ROUTE_MCP"); return 0 }
}
@MainActor public enum PackagedSelfTest {
    public static func run() async -> Int32 { print("ROUTE_SELF_TEST"); return 0 }
}
@MainActor public struct ConfigCompareApp {
    public static func main() { print("ROUTE_GUI") }
}
'''


class CLIEntryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="config-compare-cli-route-")
        cls.folder = pathlib.Path(cls.temp.name)
        cls.environment = dict(os.environ, DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer")
        source = cls.folder / "CompareUI.swift"
        source.write_text(STUB)
        cls.binary = cls.folder / "EntryProbe"
        for arguments in [
            ["-swift-version", "6", "-emit-module", "-emit-library", "-module-name", "CompareUI", str(source),
             "-emit-module-path", str(cls.folder / "CompareUI.swiftmodule"), "-o", str(cls.folder / "libCompareUI.dylib")],
            ["-swift-version", "6", "-I", str(cls.folder), "-L", str(cls.folder), "-lCompareUI",
             "-Xlinker", "-rpath", "-Xlinker", str(cls.folder),
             str(ROOT / "apps/macos/Sources/AppEntry/main.swift"), "-o", str(cls.binary)],
        ]:
            result = subprocess.run(["rtk", "proxy", "xcrun", "swiftc", *arguments], env=cls.environment,
                                    text=True, capture_output=True, timeout=60)
            if result.returncode:
                raise RuntimeError("CLI routing probe did not compile: " + result.stderr)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def route(self, arguments):
        result = subprocess.run(["rtk", "proxy", str(self.binary), *arguments], env=self.environment,
                                text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        return [line for line in result.stdout.splitlines() if line.startswith("ROUTE_")]

    def test_self_test_uses_background_entry(self):
        self.assertEqual(self.route(["--self-test"]), ["ROUTE_SELF_TEST"])

    def test_default_gui_entry_is_preserved(self):
        self.assertEqual(self.route([]), ["ROUTE_GUI"])

    def test_mcp_keeps_precedence_over_self_test(self):
        self.assertEqual(self.route(["--mcp", "--self-test"]), ["ROUTE_MCP"])

if __name__ == "__main__":
    unittest.main(verbosity=2)
