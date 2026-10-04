#!/usr/bin/env python3
"""Offline notice integrity and pinned-source checks; no runtime/network capability."""
import argparse
import hashlib
import json
import pathlib
import re
import shutil
import subprocess
import tarfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
ASSETS = pathlib.Path('apps/macos/Packaging/ThirdPartyNotices')
NOTICE_DOCUMENT_NAME = re.compile(r'(?:(?:LICENSE|LICENCE|COPYING|UNLICENSE|COPYRIGHT|NOTICE)(?:[._-][A-Za-z0-9]+)*|(?:MIT|Apache)-LICENSE)', re.I)
LICENSE_NAME = re.compile(r'(?:^|[-_.])(LICENSE|LICENCE|COPYING|UNLICENSE)(?:$|[-_.])', re.I)

def require(condition, message):
    if not condition:
        raise RuntimeError(message)

def relative_path(value):
    require(isinstance(value,str) and value and '\\' not in value, 'Invalid notice path')
    path = pathlib.PurePosixPath(value)
    require(not path.is_absolute() and '..' not in path.parts and path.as_posix()==value and value!='.', 'Notice path escapes its bundle')
    return path

def digest(body):
    return hashlib.sha256(body).hexdigest()

def lock_checksums(text):
    # Cargo-generated lock v4 only. Avoid requiring Python 3.11/tomllib merely
    # to package licenses on the project's existing Python 3.9 build host.
    text = '\n'.join(text.splitlines())
    require(re.search(r'^version = 4$',text,re.M) is not None, 'Unsupported Cargo lock format')
    packages = text.split('[[package]]\n')[1:]
    require(packages, 'Cargo lock package inventory is empty')
    result = {}
    for package in packages:
        fields = {}
        for key in ['name','version','checksum']:
            matches = re.findall(r'^'+key+r' = ("[^"\n]*")$',package,re.M)
            require(len(matches)==1 if key!='checksum' else len(matches)<=1, 'Ambiguous Cargo lock identity or checksum')
            if matches:
                fields[key] = json.loads(matches[0])
        identity = (fields['name'],fields['version'])
        require(identity not in result, 'Ambiguous same-name/version Cargo lock entries')
        checksum = fields.get('checksum')
        require(checksum is None or re.fullmatch(r'[0-9a-f]{64}',checksum), 'Invalid Cargo lock checksum')
        result[identity] = checksum
    return result

def read_bundle(folder):
    folder = pathlib.Path(folder)
    require(folder.is_dir() and not folder.is_symlink(), 'Notice bundle is missing or symbolic')
    index = folder/'inventory.json'
    require(index.is_file() and not index.is_symlink(), 'Notice inventory is missing or symbolic')
    inventory = json.loads(index.read_text(encoding='utf-8'))
    require(type(inventory.get('schemaVersion')) is int and inventory['schemaVersion']==1, 'Unsupported notice schema')
    components = inventory.get('components')
    require(isinstance(components,list) and components, 'Notice component inventory is empty')
    expected = {'inventory.json','README.txt'}
    if 'originsFile' in inventory:
        require(inventory['originsFile']=='origins.json', 'Unsupported origin receipt path')
        expected.add('origins.json')
    identities = set()
    for component in components:
        require(isinstance(component,dict), 'Invalid notice component')
        identity = (component.get('ecosystem'),component.get('name'),component.get('version'))
        require(identity[0] in ['rust','swift'] and isinstance(identity[1],str) and re.fullmatch(r'[A-Za-z0-9_-]+',identity[1])
                and isinstance(identity[2],str) and re.fullmatch(r'[A-Za-z0-9._+-]+',identity[2]), 'Invalid component identity')
        require(identity not in identities, 'Duplicate component identity')
        identities.add(identity)
        files = component.get('files')
        require(isinstance(files,list) and files, 'Component has no supplied license text')
        has_license = False
        prefix = identity[0]+'/'+identity[1]+'@'+identity[2]+'/'
        for record in files:
            require(isinstance(record,dict), 'Invalid notice file record')
            path = relative_path(record.get('path'))
            require(NOTICE_DOCUMENT_NAME.fullmatch(path.name) is not None, 'Non-notice document in license bundle')
            relative_path(record.get('originPath'))
            require(str(path).startswith(prefix) and str(path) not in expected, 'Duplicate or misassigned notice path')
            expected.add(str(path))
            file = folder/path
            require(file.is_file() and all(not p.is_symlink() for p in [file,*file.parents] if p==folder or folder in p.parents), 'Notice text missing or symbolic')
            body = file.read_bytes()
            require(body and type(record.get('bytes')) is int and len(body)==record['bytes'] and digest(body)==record.get('sha256'), 'Notice text hash or size mismatch')
            has_license = has_license or bool(LICENSE_NAME.search(path.name))
        require(has_license, 'Attribution-only component lacks license text')
    files = set()
    for file in folder.rglob('*'):
        require(not file.is_symlink(), 'Symbolic notice entry')
        if file.is_file():
            files.add(str(file.relative_to(folder)))
    require(files==expected, 'Notice bundle contains missing or unindexed files')
    require((folder/'README.txt').stat().st_size>0, 'Notice scope description is empty')
    return inventory

def copy_bundle(source, destination):
    inventory = read_bundle(source)
    destination = pathlib.Path(destination)
    require(not destination.exists() and not destination.is_symlink(), 'Notice destination already exists')
    shutil.copytree(source,destination)
    require(read_bundle(destination)==inventory, 'Copied notice inventory differs')

def validate_sources(root=ROOT):
    root = pathlib.Path(root)
    assets = root/ASSETS
    inventory = read_bundle(assets)
    require(digest((root/'Cargo.lock').read_bytes())==inventory.get('cargoLockSHA256'), 'Cargo lock changed; refresh notices')
    require(digest((root/'apps/macos/Package.resolved').read_bytes())==inventory.get('swiftResolvedSHA256'), 'Swift pins changed; refresh notices')
    metadata = json.loads(subprocess.check_output(['rtk','proxy','cargo','metadata','--locked','--offline','--format-version=1'],cwd=root,text=True))
    packages = {(p['name'],p['version']):p for p in metadata['packages'] if p['id'] not in metadata['workspace_members']}
    pins = {p['identity']:p for p in json.loads((root/'apps/macos/Package.resolved').read_text())['pins']}
    rust = {(c['name'],c['version']) for c in inventory['components'] if c['ecosystem']=='rust'}
    swift = {c['name'] for c in inventory['components'] if c['ecosystem']=='swift'}
    require(rust==set(packages) and swift==set(pins), 'Locked dependency notice coverage differs')
    fallback_origins = {(c['repository'],c['revision'],r['originPath']) for c in inventory['components']
                        for r in c['files'] if r['originKind']=='upstreamRevision'}
    origins = {}
    if fallback_origins:
        require(inventory.get('originsFile')=='origins.json', 'Pinned upstream origin receipts are missing')
        receipts = json.loads((assets/'origins.json').read_text(encoding='utf-8'))
        require(type(receipts.get('schemaVersion')) is int and receipts['schemaVersion']==1, 'Unsupported origin receipt schema')
        for receipt in receipts['upstreamOrigins']:
            identity = (receipt['repository'],receipt['revision'],receipt['path'])
            require(identity not in origins, 'Duplicate upstream origin receipt')
            origins[identity] = receipt
        require(set(origins)==fallback_origins, 'Upstream origin receipt coverage differs')
    checksums = lock_checksums((root/'Cargo.lock').read_text())
    checked_files = 0
    for component in inventory['components']:
        name,version = component['name'],component['version']
        if component['ecosystem']=='swift':
            pin = pins[name]
            require(component['version']==pin['state']['version'] and component['revision']==pin['state']['revision']
                    and component['repository']==pin['location'], 'Swift notice source identity differs')
            checkout = root/'apps/macos/.build/checkouts'/name
            revision = subprocess.check_output(['rtk','proxy','git','-C',str(checkout),'rev-parse','HEAD'],text=True).strip()
            require(revision==component['revision'], 'Swift checkout differs from pin')
            for record in component['files']:
                require(record['originKind']=='swiftCheckout', 'Unsupported Swift notice provenance')
                original = subprocess.check_output(['rtk','proxy','git','-C',str(checkout),'show',revision+':'+record['originPath']])
                require(original==(assets/record['path']).read_bytes(), 'Swift license differs from pinned Git source')
                checked_files+=1
            continue
        package = packages[(name,version)]
        require(component['declaredLicense']==package['license'] and component['repository']==package['repository'], 'Cargo declaration differs')
        directory = pathlib.Path(package['manifest_path']).parent
        if package['source'] is None:
            upstream = json.loads((directory/'UPSTREAM.json').read_text())
            require(component['revision']==upstream['upstreamCommit'], 'Vendored notice revision differs')
            for record in component['files']:
                require(record['originKind']=='vendoredSource' and (directory/record['originPath']).read_bytes()==(assets/record['path']).read_bytes(), 'Vendored license differs')
                checked_files+=1
            continue
        archive = directory.parents[2]/'cache'/directory.parent.name/(name+'-'+version+'.crate')
        require(archive.is_file() and digest(archive.read_bytes())==checksums[(name,version)], 'Cargo archive differs from lock checksum')
        with tarfile.open(archive,'r:gz') as tar:
            prefix = name+'-'+version+'/'
            vcs = json.load(tar.extractfile(prefix+'.cargo_vcs_info.json'))
            require(component['revision']==vcs['git']['sha1'], 'Cargo archive revision differs from notice inventory')
            for record in component['files']:
                if record['originKind']=='cargoArchive':
                    member = tar.getmember(prefix+record['originPath'])
                    require(member.isfile(), 'Cargo notice is not a regular archive member')
                    original = tar.extractfile(member).read()
                    require(original==(assets/record['path']).read_bytes(), 'Cargo license differs from locked archive')
                elif record['originKind']=='upstreamRevision':
                    vcs = json.load(tar.extractfile(prefix+'.cargo_vcs_info.json'))
                    revision = vcs['git']['sha1']
                    require(revision==component['revision'], 'Upstream notice revision differs from crate')
                    require(record['url']==package['repository'].replace('https://github.com/','https://raw.githubusercontent.com/')+'/'+revision+'/'+record['originPath'], 'Upstream license URL is not pinned')
                    origin = origins[(component['repository'],revision,record['originPath'])]
                    body = (assets/record['path']).read_bytes()
                    blob = hashlib.sha1(b'blob '+str(len(body)).encode()+b'\0'+body).hexdigest()
                    require(origin['url']==record['url'] and origin['sha256']==digest(body)
                            and origin['bytes']==len(body) and origin['gitBlobSHA1']==record.get('gitBlobSHA1')==blob,
                            'Upstream license differs from its pinned Git blob receipt')
                    # OXC's workspace-root license is already independently
                    # pinned and verified by the vendored-source provenance gate.
                    if package['repository']=='https://github.com/oxc-project/oxc':
                        require((assets/record['path']).read_bytes()==(root/'vendor/oxc_parser/LICENSE').read_bytes(), 'OXC workspace license differs')
                else:
                    raise RuntimeError('Unsupported Cargo notice provenance')
                checked_files+=1
    return {'passed':True,'components':len(inventory['components']),'rustComponents':len(rust),
            'swiftComponents':len(swift),'licenseNoticeFiles':checked_files,'offline':True,
            'scope':inventory.get('scope'),'formalReleasePassed':False,'legalCompatibilityAssessed':False}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--copy-to',type=pathlib.Path)
    arguments = parser.parse_args()
    report = validate_sources()
    if arguments.copy_to is not None:
        copy_bundle(ROOT/ASSETS,arguments.copy_to)
        report['copied']=True
    (ROOT/'build').mkdir(exist_ok=True)
    (ROOT/'build/license-check.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(report))

if __name__=='__main__':
    main()
