"""Developer-only: pin official Python and Apple Silicon wheel downloads."""
import hashlib,json,pathlib,urllib.request,subprocess
from packaging.tags import sys_tags
from packaging.utils import parse_wheel_filename

urllib.request.install_opener(urllib.request.build_opener(urllib.request.ProxyHandler({})))
root=pathlib.Path(__file__).resolve().parents[1]
tags=list(sys_tags()); rank={tag:i for i,tag in enumerate(tags)}
python_url='https://releases.astral.sh/github/python-build-standalone/releases/download/20260211/cpython-3.12.12%2B20260211-aarch64-apple-darwin-install_only_stripped.tar.gz'
archive=root/'build/python-runtime.tar.gz'
subprocess.run(['curl','-fL','--silent','--show-error',python_url,'-o',str(archive)],check=True)
assets=[{'name':'Python 3.12.12','kind':'python','url':python_url,'sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),'bytes':archive.stat().st_size}]
excluded={'torch','sympy','networkx','setuptools'}
for line in (root/'requirements.lock').read_text().splitlines():
 name,version=line.split('==')
 if name in excluded: continue
 with urllib.request.urlopen(f'https://pypi.org/pypi/{name}/{version}/json') as response: metadata=json.load(response)
 candidates=[]
 for file in metadata['urls']:
  if file['packagetype']!='bdist_wheel': continue
  wheel_tags=parse_wheel_filename(file['filename'])[3]
  matches=[rank[tag] for tag in wheel_tags if tag in rank]
  if matches: candidates.append((min(matches),file))
 if not candidates: raise RuntimeError('No compatible wheel for '+name)
 file=min(candidates,key=lambda item:item[0])[1]
 assets.append({'name':name+' '+version,'kind':'wheel','url':file['url'],'sha256':file['digests']['sha256'],'bytes':file['size']})
manifest={'version':'cpython312-phonon027-mlx-v2','assets':assets}
(root/'Resources/runtime-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('Pinned assets:',len(assets),'compressed download MB:',round(sum(x['bytes'] for x in assets)/1e6,1))
