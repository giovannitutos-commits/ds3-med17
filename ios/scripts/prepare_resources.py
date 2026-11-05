import base64,hashlib,json,pathlib,zipfile,io
root=pathlib.Path(__file__).resolve().parents[1]
parts=sorted((root/'resource-parts').glob('*.b64'))
assert parts, 'Resource parts are missing'
data=base64.b64decode(''.join(p.read_text().strip() for p in parts),validate=True)
manifest=json.loads((root/'resource-manifest.json').read_text())
assert hashlib.sha256(data).hexdigest()==manifest['bundle_sha256'],'Resource archive checksum mismatch'
out=root/'Resources';out.mkdir(exist_ok=True)
with zipfile.ZipFile(io.BytesIO(data)) as z:
 for name in z.namelist():
  assert pathlib.PurePosixPath(name).name==name,'Unexpected path'
  content=z.read(name)
  assert hashlib.sha256(content).hexdigest()==manifest['files'][name],name
  (out/name).write_bytes(content)
print(f"Verified {len(manifest['files'])} resources, {manifest['profiles']} PSA profiles, {manifest['actions']} routines")

audio_manifest=json.loads((root/'audio-manifest.json').read_text())
audio=base64.b64decode(''.join(p.read_text().strip() for p in sorted((root/'audio-parts').glob('*.b64'))),validate=True)
assert hashlib.sha256(audio).hexdigest()==audio_manifest['bundle_sha256']
with zipfile.ZipFile(io.BytesIO(audio)) as z:
 for name in z.namelist():
  assert pathlib.PurePosixPath(name).name==name
  content=z.read(name)
  assert hashlib.sha256(content).hexdigest()==audio_manifest['files'][name]
  (out/name).write_bytes(content)
print('Verified audio resources:',len(audio_manifest['files']))
