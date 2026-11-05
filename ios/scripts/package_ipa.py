import pathlib,shutil,subprocess,zipfile,hashlib,json,plistlib
root=pathlib.Path(__file__).resolve().parents[1]
source=root/'build-device/Build/Products/Release-iphoneos/FrenchDiag.app'
assert source.is_dir(), 'Device app was not built'
info=plistlib.loads((source/'Info.plist').read_bytes())
binary=source/info['CFBundleExecutable']
arches=subprocess.check_output(['lipo','-archs',str(binary)],text=True).strip()
assert 'arm64' in arches,arches
platform=info.get('DTPlatformName')
assert platform=='iphoneos',f'Not an iPhone device build: {platform}'
# Sideloadly will create a personal provisioning profile and sign the app locally.
result=root/'dist';result.mkdir(exist_ok=True)
payload=result/'Payload';payload.mkdir(exist_ok=True)
target=payload/'FrenchDiag.app'
if target.exists():shutil.rmtree(target)
shutil.copytree(source,target,symlinks=True)
signature=target/'_CodeSignature'
if signature.exists():shutil.rmtree(signature)
profile=target/'embedded.mobileprovision'
if profile.exists():profile.unlink()
ipa=result/'FrenchDiag-iOS-Unsigned.ipa'
# ditto preserves executable permissions in the ZIP.
subprocess.run(['ditto','-c','-k','--keepParent',str(payload),str(ipa)],check=True)
with zipfile.ZipFile(ipa) as z:
    assert 'Payload/FrenchDiag.app/FrenchDiag' in z.namelist()
    meta=plistlib.loads(z.read('Payload/FrenchDiag.app/Info.plist'))
    assert meta['CFBundleIdentifier']=='br.com.frenchdiag.ios.test'
digest=hashlib.sha256(ipa.read_bytes()).hexdigest()
(ipa.with_suffix('.ipa.sha256')).write_text(digest+'  '+ipa.name+'\n')
(root/'validation.json').write_text(json.dumps({'device_architectures':arches,'platform':platform,'bundle_id':info['CFBundleIdentifier'],'signed':False,'installation':'Sideloadly with free Apple account; renew personal signature every 7 days','ipa_sha256':digest,'hardware_validation':False},indent=2))
print(ipa.name,ipa.stat().st_size,digest)
