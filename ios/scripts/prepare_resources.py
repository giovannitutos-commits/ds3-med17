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
