#!/usr/bin/env python3
"""Local development packaging. Does not publish or notarize the application."""
import os
import pathlib
import plistlib
import shutil
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parent.parent
debug = "--debug" in sys.argv
profile = "debug" if debug else "release"
environment = dict(os.environ, DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer", CC_CORE_PROFILE=profile)

def run(*args, capture=False, timeout=None):
    return subprocess.run(["rtk", "proxy", *args], cwd=root, env=environment, check=True,
                          capture_output=capture, text=capture, timeout=timeout)

run("cargo", "build", "--locked", "-p", "compare-core", *([] if debug else ["--release"]))
# SwiftPM does not track a Rust archive outside its target graph as a build input.
# Force relinking so a successful Swift cache hit cannot ship an earlier core.
run("swift", "package", "--package-path", "apps/macos", "clean")
run("swift", "build", "--package-path", "apps/macos", "-c", profile)
binary_path = pathlib.Path(run("swift", "build", "--package-path", "apps/macos", "-c", profile,
                               "--show-bin-path", capture=True).stdout.strip())
app = root / "build" / "Config Compare.app"
if app.exists():
    shutil.rmtree(app)
contents = app / "Contents"
worker = contents / "XPCServices" / "CompareWorker.xpc" / "Contents"
for directory in [contents / "MacOS", contents / "Resources", worker / "MacOS"]:
    directory.mkdir(parents=True, exist_ok=True)
shutil.copy2(binary_path / "ConfigCompare", contents / "MacOS" / "ConfigCompare")
shutil.copy2(binary_path / "CompareWorker", worker / "MacOS" / "CompareWorker")
shutil.copy2(root / "vendor/oxc_parser/LICENSE", contents / "Resources" / "OXC-LICENSE.txt")
run(sys.executable, str(root / "scripts/check-licenses.py"), "--copy-to",
    str(contents / "Resources" / "ThirdPartyNotices"))
iconset = root / "build" / "ConfigCompare.iconset"
if iconset.exists():
    shutil.rmtree(iconset)
iconset.mkdir(parents=True, exist_ok=True)
icon_source = root / "assets" / "config-compare-icon.png"
if not icon_source.is_file():
    raise RuntimeError("The direct App icon source is missing")
for size in [16, 32, 128, 256, 512]:
    for scale in [1, 2]:
        destination = iconset / f"icon_{size}x{size}{'@2x' if scale == 2 else ''}.png"
        run("sips", "-z", str(size * scale), str(size * scale), str(icon_source), "--out", str(destination), capture=True)
run("iconutil", "-c", "icns", str(iconset), "-o", str(contents / "Resources" / "ConfigCompare.icns"))


def plist(path, data):
    with path.open("wb") as output:
        plistlib.dump(data, output)

common = {"CFBundleInfoDictionaryVersion": "6.0", "CFBundleVersion": "1", "CFBundleShortVersionString": "0.1.0"}
plist(contents / "Info.plist", dict(common, CFBundleName="Config Compare", CFBundleDisplayName="Config Compare",
      CFBundleIdentifier="com.penguin.configcompare", CFBundleExecutable="ConfigCompare", CFBundlePackageType="APPL",
      CFBundleIconFile="ConfigCompare.icns", NSPrincipalClass="NSApplication", LSMinimumSystemVersion="14.0", NSHighResolutionCapable=True,
      NSHumanReadableCopyright="Local offline configuration helper",
      # Vault endpoints may be internal HTTP services. This permits cleartext
      # HTTP at the transport layer; URLSession still validates HTTPS
      # certificates, and Vault scope checks remain enforced in the reader.
      NSAppTransportSecurity={"NSAllowsArbitraryLoads": True}))
plist(worker / "Info.plist", dict(common, CFBundleName="CompareWorker", CFBundleIdentifier="com.penguin.configcompare.worker",
      CFBundleExecutable="CompareWorker", CFBundlePackageType="XPC!",
      XPCService={"ServiceType":"Application", "RunLoopType":"dispatch_main"}))
main_entitlements = root / "apps/macos/Packaging/App.entitlements"
worker_entitlements = root / "apps/macos/Packaging/Worker.entitlements"
run("codesign", "--force", "--sign", "-", "--options", "runtime", "--timestamp=none", "--entitlements",
    str(worker_entitlements), str(worker.parent))
run("codesign", "--force", "--sign", "-", "--options", "runtime", "--timestamp=none", "--entitlements",
    str(main_entitlements), str(app))
run("codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app))
run(str(contents / "MacOS" / "ConfigCompare"), "--self-test", timeout=90)
run(sys.executable, str(root / "scripts/test-packaged-notices.py"), str(app), timeout=30)
run(sys.executable, str(root / "scripts/test-packaged-assets.py"), str(app), timeout=90)
print(f"LOCAL_TEST_BUILD ({profile}, ad-hoc signed): {app}")
