#!/usr/bin/env python3
"""Prepare an original leftover recovery copy for manual UI validation; verify saved outputs."""
import argparse
import datetime
import hashlib
import json
import os
import subprocess
import uuid
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = root/'build/validation/session-recovery/acceptance'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--install',action='store_true',help='Place the original synthetic recovery copy in this user’s application recovery folder.')
parser.add_argument('--verify',action='store_true',help='Verify live-recovered.orrp and live-diagnostics.txt after the UI workflow.')
parser.add_argument('--check-cli',action='store_true',help='Verify a new recovered project and refusal to overwrite it using the built application.')
parser.add_argument('--archive-fixture',action='store_true',help='Archive only the installed synthetic fixture when UI validation is unavailable.')
args = parser.parse_args()
out.mkdir(parents=True,exist_ok=True)
manifest = out/'manifest.json'

if args.archive_fixture:
    state = json.loads(manifest.read_text())
    source = Path(state['installed']);fixture = Path(state['fixture'])
    if source.exists():
        assert source.read_bytes() == fixture.read_bytes()
        folder = source.parent/'Archived';folder.mkdir(exist_ok=True,mode=0o700)
        destination = folder/source.name
        assert not destination.exists()
        source.rename(destination)
    print('Archived the original synthetic fixture; it will not trigger a startup recovery prompt.')
elif args.check_cli:
    state = json.loads(manifest.read_text())
    source = Path(state['fixture']);output = out/('cli-recovered-'+str(uuid.uuid4())+'.orrp')
    exe = root/'build/OpenRaceRender.app/Contents/MacOS/OpenRaceRender'
    command = [str(exe),'recover-project',str(source),'--out',str(output)]
    subprocess.run(command,check=True,capture_output=True)
    expected = json.loads(Path(state['original']).read_text());saved = json.loads(output.read_text())
    for key in ['name','notes','rangeStart','rangeEnd','lastExport','objects']: assert saved[key] == expected[key],key
    before = output.read_bytes()
    assert subprocess.run(command,capture_output=True).returncode != 0
    assert output.read_bytes() == before
    assert hashlib.sha256(Path(state['original']).read_bytes()).hexdigest() == state['originalSHA256']
    print('Recovery CLI acceptance passed: prepared snapshot decoded, marks/settings retained, original unchanged, overwrite refused.')
elif args.verify:
    state = json.loads(manifest.read_text())
    original = Path(state['original'])
    assert hashlib.sha256(original.read_bytes()).hexdigest() == state['originalSHA256']
    saved = json.loads((out/'live-recovered.orrp').read_text())
    expected = json.loads(original.read_text())
    for key in ['name','notes','rangeStart','rangeEnd','lastExport','objects']:
        assert saved[key] == expected[key],key
    assert saved['notes'] == 'Original synthetic recovery validation notes'
    report = (out/'live-diagnostics.txt').read_text()
    assert 'recoveryRestored' in report and 'projectSaved' in report
    assert expected['name'] not in report and str(out) not in report
    assert not any(token in report for token in ['access_token','client_secret','latitude','longitude'])
    if state.get('installed'):
        installed = Path(state['installed'])
        assert not installed.exists()
        assert (installed.parent/'Archived'/installed.name).is_file()
    print('Recovery UI workflow passed: original hash unchanged, saved marks/output/widgets retained, old copy archived, diagnostic privacy checked.')
else:
    project = dict(formatVersion=1,name='Recovery validation fixture',width=640,height=360,fps=30,speedUnit='mph',warnings=[],inputs=[],objects=[],explicitDuration=20,rangeStart=3,rangeEnd=17,notes='Original synthetic recovery validation notes',lastExport=dict(path=str(out/'remembered-render.mp4'),start=3,duration=14))
    original = out/'source-original.orrp';original.write_text(json.dumps(project,indent=2))
    identifier = str(uuid.uuid4()).upper()
    envelope = dict(version=1,id=identifier,savedAt=datetime.datetime.now(datetime.timezone.utc).timestamp()-978307200,originalURL=original.as_uri(),playhead=7,project=project)
    fixture = out/(identifier+'.json');fixture.write_text(json.dumps(envelope,indent=2))
    state = dict(original=str(original),originalSHA256=hashlib.sha256(original.read_bytes()).hexdigest(),fixture=str(fixture))
    if args.install:
        directory = Path.home()/'Library/Application Support/OpenRaceRender/Recovery'
        directory.mkdir(parents=True,exist_ok=True,mode=0o700)
        destination = directory/fixture.name
        fd = os.open(destination,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
        with os.fdopen(fd,'wb') as output: output.write(fixture.read_bytes())
        state['installed'] = str(destination)
        print('Installed original synthetic recovery copy:',destination)
    manifest.write_text(json.dumps(state,indent=2))
    print('UI check: launch app, Restore copy, Save As',out/'live-recovered.orrp')
    print('Then Help → Show diagnostic log → Export report to',out/'live-diagnostics.txt')
