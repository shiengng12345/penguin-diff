import hashlib
import importlib.util
import json
import pathlib
import sys
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP = pathlib.Path(sys.argv.pop(1))

class PackagedNoticesTests(unittest.TestCase):
    def test_packaged_app_includes_all_locked_third_party_texts(self):
        notices = APP / 'Contents/Resources/ThirdPartyNotices'
        index = notices / 'inventory.json'
        self.assertTrue(index.is_file(), 'The App must carry the complete dependency notice inventory')
        spec = importlib.util.spec_from_file_location('license_checker', ROOT/'scripts/check-licenses.py')
        checker = importlib.util.module_from_spec(spec);spec.loader.exec_module(checker)
        inventory = checker.read_bundle(notices)
        source = checker.read_bundle(ROOT/checker.ASSETS)
        self.assertEqual(inventory,source,'Packaged notice inventory differs from source')
        for relative in ['inventory.json','origins.json','README.txt']:
            self.assertEqual((notices/relative).read_bytes(),(ROOT/checker.ASSETS/relative).read_bytes())
        self.assertEqual(inventory['schemaVersion'], 1)
        metadata=json.loads(subprocess.check_output(['rtk','proxy','cargo','metadata','--locked','--offline','--format-version=1'],cwd=ROOT,text=True))
        expected={('rust',p['name'],p['version']) for p in metadata['packages'] if p['id'] not in metadata['workspace_members']}
        pins=json.loads((ROOT/'apps/macos/Package.resolved').read_text())['pins']
        expected.update(('swift',p['identity'],p['state']['version']) for p in pins)
        actual={(c['ecosystem'],c['name'],c['version']) for c in inventory['components']}
        self.assertEqual(actual,expected)
        self.assertEqual(len(inventory['components']),len(expected))
        swift = {c['name'] for c in inventory['components'] if c['ecosystem'] == 'swift'}
        self.assertEqual(swift,{p['identity'] for p in pins})
        self.assertNotIn('compare-core', {c['name'] for c in inventory['components']})
        for component in inventory['components']:
            self.assertTrue(component['files'], 'Every dependency must provide license text, not only an SPDX label')
            for record in component['files']:
                file = notices / record['path']
                self.assertTrue(file.is_file(), record['path'])
                self.assertEqual(hashlib.sha256(file.read_bytes()).hexdigest(), record['sha256'])
                self.assertEqual(file.read_bytes(),(ROOT/checker.ASSETS/record['path']).read_bytes())
        log = next(c for c in inventory['components'] if c['name']=='swift-log')
        self.assertTrue(any(p['path'].endswith('NOTICE.txt') for p in log['files']))
        nio = next(c for c in inventory['components'] if c['name']=='swift-nio')
        self.assertTrue(any(p['path'].endswith('Sources/CNIOLLHTTP/LICENSE') for p in nio['files']))
        self.assertTrue((notices/'README.txt').is_file())
        # No development machine absolute paths or mutable upstream branch refs.
        self.assertNotIn('/Users/', index.read_text())
        self.assertNotIn('/main/', index.read_text())

if __name__ == '__main__':
    unittest.main()
