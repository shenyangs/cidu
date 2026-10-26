#!/usr/bin/env python3
"""Live-target plan smoke. Only refusal cases invoke apply; no eligible plan is installed."""
import hashlib, json, pathlib, subprocess, tempfile, shutil, uuid
repo = pathlib.Path(__file__).resolve().parents[1]
cli = repo / 'build/词渡.app/Contents/MacOS/cidu-cli'
def call(*args, expected=0):
    p = subprocess.run([str(cli), *args], capture_output=True, text=True, timeout=90)
    assert p.returncode == expected, (args[0], p.returncode)
    value = json.loads(p.stdout)
    assert '词渡验证词渡' not in p.stdout and not p.stderr, 'private output or diagnostics leaked'
    return value
assert call('help')['version'] == (repo/'VERSION').read_text().strip()
assert not call('apply',str(uuid.uuid4()),expected=1)['ok']
assert not call('restore','../anything','--confirm',expected=1)['ok']
assert not call('unknown',expected=1)['ok']
with tempfile.TemporaryDirectory(prefix='cidu-cli-test-') as folder:
    source = pathlib.Path(folder)/'sample.txt'
    source.write_text('词渡验证词渡(ci|du|yan|zheng|ci|du) 1',encoding='utf-8')
    missing = str(pathlib.Path(folder)/'missing.txt')
    assert not call('status','--file',missing,expected=2)['ready']
    assert call('plan','--file',missing,expected=2)['code'] == 'preflight_failed'
    status = subprocess.run([str(cli),'status','--file',str(source)],capture_output=True,text=True,timeout=30)
    report = json.loads(status.stdout)
    if not report['ready']:
        print('PASS CLI parsing/refusals; native plan SKIPPED (environment not ready)')
        raise SystemExit(0)
    base = pathlib.Path.home()/'Library/Application Support/DoubaoIme'
    targets = list((base/'EngineUserDictAccounts').glob('*/usr.dat'))
    targets += [p for p in (base/'EngineUserDict/usr.dat',base/'usr.dat') if p.exists()]
    assert len(targets)==1
    before = hashlib.sha256(targets[0].read_bytes()).hexdigest()
    result = call('plan','--file',str(source))
    plan = result['plan']; ident = str(uuid.UUID(plan['id']))
    assert plan['state']=='prepared' and not result['installed']
    assert hashlib.sha256(targets[0].read_bytes()).hexdigest()==before
    assert any(r['id'].lower()==ident for r in call('history')['receipts'])
    directory = pathlib.Path.home()/'Library/Application Support/Cidu/Transactions'/plan['id']
    assert directory.name.lower()==ident
    shutil.rmtree(directory)  # Only this synthetic test's newly generated plan and private copies.
    for text, added in [('词渡验证词渡(ci|du|yan|zheng|ci|du) 1\n待适配验证词(invalid-syllable) 1',1),('待适配验证词(invalid-syllable) 1',0)]:
        source.write_text(text,encoding='utf-8')
        partial = call('plan','--file',str(source))['plan']
        directory = pathlib.Path.home()/'Library/Application Support/Cidu/Transactions'/partial['id']
        try:
            assert partial['state']=='prepared' and partial['unmigrated']==1 and partial['added']==added
            assert partial['partialConfirmationRequired']
            assert not call('apply',partial['id'],'--confirm',expected=1)['ok']
            if added==0:
                assert not call('apply',partial['id'],'--confirm','--allow-partial',expected=1)['ok']
            assert (directory/'source.original').read_bytes()==source.read_bytes()
            archived = json.loads((directory/'unmigrated.json').read_text())
            assert len(archived['entries'])==1 and archived['schema']=='cidu.archive.v1'
            assert hashlib.sha256(targets[0].read_bytes()).hexdigest()==before
        finally:
            shutil.rmtree(directory)
print('PASS CLI JSON, partial opt-in refusal, all-blocked refusal, retained archives, native plans, history; live dictionary unchanged')
