#!/usr/bin/env python3
"""Real file-boundary regressions for third-party notice packaging."""
import hashlib
import contextlib
import importlib.util
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).with_name('check-licenses.py')
module = None
if SCRIPT.is_file():
    spec = importlib.util.spec_from_file_location('license_checker', SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

class LicenseBundleTests(unittest.TestCase):
    def checker(self):
        self.assertIsNotNone(module, 'A real license bundle consumer must enforce the packaging contract')
        return module

    def fixture(self, root):
        root.mkdir()
        body = b'upstream MIT license\r\nCopyright synthetic author\r\n'
        notice = b'upstream attribution, do not rewrite\n'
        files = []
        for name, value in [('LICENSE',body),('NOTICE.txt',notice)]:
            path = 'swift/example@1.0.0/'+name
            file = root/path;file.parent.mkdir(parents=True,exist_ok=True);file.write_bytes(value)
            files.append({'path':path,'sha256':hashlib.sha256(value).hexdigest(),'bytes':len(value),
                          'originPath':name,'originKind':'swiftCheckout'})
        inventory = {'schemaVersion':1,'cargoLockSHA256':'a'*64,'swiftResolvedSHA256':'b'*64,
                     'components':[{'ecosystem':'swift','name':'example','version':'1.0.0',
                                    'revision':'c'*40,'declaredLicense':None,'files':files}]}
        (root/'README.txt').write_text('Resolved sources include development-only packages.\n',encoding='utf-8')
        (root/'inventory.json').write_text(json.dumps(inventory),encoding='utf-8')
        return inventory, body, notice

    def save(self, root, inventory):
        (root/'inventory.json').write_text(json.dumps(inventory),encoding='utf-8')

    def test_copy_preserves_upstream_license_and_notice_bytes(self):
        checker = self.checker()
        with tempfile.TemporaryDirectory() as temporary:
            root=pathlib.Path(temporary);assets=root/'assets';_,body,notice=self.fixture(assets)
            checker.copy_bundle(assets,root/'output')
            self.assertEqual((root/'output/swift/example@1.0.0/LICENSE').read_bytes(),body)
            self.assertEqual((root/'output/swift/example@1.0.0/NOTICE.txt').read_bytes(),notice)

    def test_changed_or_missing_license_body_is_rejected(self):
        checker=self.checker()
        with tempfile.TemporaryDirectory() as temporary:
            root=pathlib.Path(temporary)/'assets';self.fixture(root);file=root/'swift/example@1.0.0/LICENSE'
            file.write_bytes(b'wrong')
            with self.assertRaises(RuntimeError):checker.read_bundle(root)
            file.unlink()
            with self.assertRaises(RuntimeError):checker.read_bundle(root)

    def test_paths_cannot_escape_assets_or_cross_a_symlink(self):
        checker=self.checker()
        with tempfile.TemporaryDirectory() as temporary:
            root=pathlib.Path(temporary);assets=root/'assets';inventory,_,_=self.fixture(assets)
            original=inventory['components'][0]['files'][0]['path']
            for path in ['../outside','/tmp/outside','swift/example@1.0.0/../../outside','swift\\outside']:
                inventory['components'][0]['files'][0]['path']=path;self.save(assets,inventory)
                with self.assertRaises(RuntimeError):checker.read_bundle(assets)
            inventory['components'][0]['files'][0]['path']=original;self.save(assets,inventory)
            file=assets/original;body=file.read_bytes();file.unlink();outside=root/'outside';outside.write_bytes(body);file.symlink_to(outside)
            with self.assertRaises(RuntimeError):checker.read_bundle(assets)

    def test_duplicate_component_or_file_identity_is_rejected(self):
        checker=self.checker()
        with tempfile.TemporaryDirectory() as temporary:
            root=pathlib.Path(temporary)/'assets';inventory,_,_=self.fixture(root)
            inventory['components'].append(inventory['components'][0]);self.save(root,inventory)
            with self.assertRaises(RuntimeError):checker.read_bundle(root)
            inventory['components'].pop();inventory['components'][0]['files'].append(inventory['components'][0]['files'][0]);self.save(root,inventory)
            with self.assertRaises(RuntimeError):checker.read_bundle(root)

    def test_empty_inventory_or_notice_only_component_is_rejected(self):
        checker=self.checker()
        with tempfile.TemporaryDirectory() as temporary:
            root=pathlib.Path(temporary)/'assets';inventory,_,_=self.fixture(root)
            saved=inventory['components'];inventory['components']=[];self.save(root,inventory)
            with self.assertRaises(RuntimeError):checker.read_bundle(root)
            inventory['components']=saved;inventory['components'][0]['files']=inventory['components'][0]['files'][1:];self.save(root,inventory)
            with self.assertRaises(RuntimeError):checker.read_bundle(root)

    def test_unindexed_stale_files_are_rejected(self):
        checker=self.checker()
        with tempfile.TemporaryDirectory() as temporary:
            root=pathlib.Path(temporary)/'assets';self.fixture(root);(root/'untracked.txt').write_text('stale')
            with self.assertRaises(RuntimeError):checker.read_bundle(root)

    def test_indexed_benchmark_or_source_files_are_not_license_notices(self):
        checker=self.checker()
        for name in ['MaxLogLevelWarning.notice_log.p90.json',
                     'test_1000_copying_bytebufferview_to_array.swift',
                     '.license_header_template']:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temporary:
                assets=pathlib.Path(temporary)/'assets';inventory,_,_=self.fixture(assets)
                path='swift/example@1.0.0/'+name;body=b'not a license or NOTICE document\n'
                (assets/path).write_bytes(body)
                inventory['components'][0]['files'].append({'path':path,'originPath':name,
                    'sha256':hashlib.sha256(body).hexdigest(),'bytes':len(body),'originKind':'swiftCheckout'})
                self.save(assets,inventory)
                with self.assertRaises(RuntimeError):checker.read_bundle(assets)

    def test_copy_refuses_existing_destination_and_preserves_its_files(self):
        checker=self.checker()
        with tempfile.TemporaryDirectory() as temporary:
            root=pathlib.Path(temporary);assets=root/'assets';self.fixture(assets);output=root/'output';output.mkdir();(output/'user.txt').write_text('keep')
            with self.assertRaises(RuntimeError):checker.copy_bundle(assets,output)
            self.assertEqual((output/'user.txt').read_text(),'keep')

    @contextlib.contextmanager
    def source_fixture(self):
        checker=self.checker()
        with tempfile.TemporaryDirectory() as temporary:
            root=pathlib.Path(temporary)
            for name in ['crates','vendor','apps/macos/Packaging']:
                shutil.copytree(checker.ROOT/name,root/name)
            for name in ['Cargo.toml','Cargo.lock','apps/macos/Package.resolved']:
                file=root/name;file.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(checker.ROOT/name,file)
            checkouts=root/'apps/macos/.build/checkouts';checkouts.parent.mkdir()
            # Read-only Git queries use our own frozen checkout copy. No source
            # cache, user checkout or actual package text is modified by tests.
            checkouts.symlink_to(checker.ROOT/'apps/macos/.build/checkouts',target_is_directory=True)
            yield checker,root,root/checker.ASSETS

    def test_rehashed_wrong_license_is_rejected_against_real_locked_archive(self):
        with self.source_fixture() as (checker,root,assets):
            inventory=checker.read_bundle(assets)
            component=next(c for c in inventory['components'] if c['ecosystem']=='rust' and c['name']=='serde')
            record=component['files'][0];body=b'Wrong upstream license, with a matching new inventory hash\n'
            (assets/record['path']).write_bytes(body);record.update(sha256=hashlib.sha256(body).hexdigest(),bytes=len(body));self.save(assets,inventory)
            # The bundle is internally self-consistent; the independent crate
            # archive, whose checksum comes from Cargo.lock, must still reject it.
            checker.read_bundle(assets)
            with self.assertRaises(RuntimeError):checker.validate_sources(root)

    def test_missing_component_cannot_hide_behind_consistent_bundle_inventory(self):
        with self.source_fixture() as (checker,root,assets):
            inventory=checker.read_bundle(assets);component=inventory['components'].pop(0)
            for record in component['files']:(assets/record['path']).unlink()
            self.save(assets,inventory);checker.read_bundle(assets)
            with self.assertRaises(RuntimeError):checker.validate_sources(root)

    def test_rehashed_upstream_fallback_text_is_rejected_against_origin_receipt(self):
        with self.source_fixture() as (checker,root,assets):
            inventory=checker.read_bundle(assets)
            component=next(c for c in inventory['components'] if c['name']=='pretty_yaml')
            record=component['files'][0];body=b'Wrong fallback license with a matching new hash and Git blob\n'
            (assets/record['path']).write_bytes(body)
            record.update(sha256=hashlib.sha256(body).hexdigest(),bytes=len(body),
                          gitBlobSHA1=hashlib.sha1(b'blob '+str(len(body)).encode()+b'\0'+body).hexdigest())
            self.save(assets,inventory);checker.read_bundle(assets)
            with self.assertRaises(RuntimeError):checker.validate_sources(root)

    def test_changed_swift_revision_is_rejected_even_after_refreshing_lock_hash(self):
        with self.source_fixture() as (checker,root,assets):
            pinfile=root/'apps/macos/Package.resolved';pins=json.loads(pinfile.read_text());pins['pins'][0]['state']['revision']='0'*40
            pinfile.write_text(json.dumps(pins));inventory=checker.read_bundle(assets)
            inventory['swiftResolvedSHA256']=hashlib.sha256(pinfile.read_bytes()).hexdigest();self.save(assets,inventory)
            with self.assertRaises(RuntimeError):checker.validate_sources(root)

    def test_cargo_archive_revision_mismatch_is_rejected(self):
        with self.source_fixture() as (checker,root,assets):
            inventory=checker.read_bundle(assets)
            next(c for c in inventory['components'] if c['name']=='serde')['revision']='0'*40
            self.save(assets,inventory);checker.read_bundle(assets)
            with self.assertRaises(RuntimeError):checker.validate_sources(root)

    def packaged_fixture_result(self, extra_file=False):
        checker=self.checker()
        with tempfile.TemporaryDirectory() as temporary:
            app=pathlib.Path(temporary)/'OwnedFixture.app';assets=app/'Contents/Resources/ThirdPartyNotices'
            shutil.copytree(checker.ROOT/checker.ASSETS,assets)
            if extra_file:
                (assets/'unindexed.txt').write_text('unindexed packaged file')
            else:
                inventory=checker.read_bundle(assets)
                record=next(c for c in inventory['components'] if c['name']=='serde')['files'][0]
                body=b'wrong packaged text with matching packaged inventory hash\n'
                (assets/record['path']).write_bytes(body)
                record.update(sha256=hashlib.sha256(body).hexdigest(),bytes=len(body))
                self.save(assets,inventory);checker.read_bundle(assets)
            return subprocess.run(['rtk','proxy',sys.executable,str(checker.ROOT/'scripts/test-packaged-notices.py'),str(app)],
                cwd=checker.ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=30)

    def test_packaged_consumer_rejects_simultaneously_changed_body_and_index(self):
        result=self.packaged_fixture_result()
        self.assertNotEqual(result.returncode,0,result.stdout)
        self.assertIn('Packaged notice inventory differs from source',result.stdout)

    def test_packaged_consumer_rejects_unindexed_extra_file(self):
        result=self.packaged_fixture_result(extra_file=True)
        self.assertNotEqual(result.returncode,0,result.stdout)
        self.assertIn('unindexed',result.stdout)

if __name__=='__main__':
    unittest.main()
