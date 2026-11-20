#!/usr/bin/env python3
"""ff_coverage.py [--game DIR] [--out DIR] [--only N-M | --tests N,N,...] [--burst] [--fx] [--report]

Every character, power, character state and effect of Freedom Force, drawn in the running game (test mode, muted, a
scratch data folder): the coverage test, as Diablo II's tests/coverage_test.py is for its classes and skills.

  1. The catalog comes from the player's own game (Data/characters.dat, powers.dat, fx.dat, res.dat): 150 character
     templates and the powers each one has, the named level effects scripts play, the power effects.
  2. A test driver (Python 1.5, the game's own) goes into the scratch overlay as Missions/01_begin/mission.py, the
     map the Danger Room opens with "Came a Hero!". For each test it spawns the character beside Minuteman (made
     unkillable), has it use each of its powers, puts it in each character state, or plays the effect, and asks the
     host for a screenshot at each step through DS_CMDFILE. Nothing of the game's is changed outside the scratch copy.
  3. The game runs in batches (the host takes 256 commands a run); a crash or a hang is recorded against the test
     that was running, and the next batch starts after it.
  4. Each screenshot is checked (tools/ff_covimg.m: drawn at all, not one colour, something visible where the test
     is) and the run log is searched for renderer and runtime trouble; contact sheets go to <out>/sheets for a look.

Outputs stay in recomp/work/coverage (they show the game's art). Needs the app built (tools/build_app.sh work/ff).
"""
import json, os, re, shutil, signal, subprocess, sys, time

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DANGER_ROOM = "@20:dimove:-170,0;@25:diclick:0,0;@32:dimove:-32,-100;@35:diclick:0,0;@40:dimove:394,316;@45:diclick:0,0;@55:diclick:0,0"
POWER_SHOTS_MAX = 230          # screenshots a batch asks for (the host keeps 256 commands)
STATES = ['freeze', 'stun', 'static', 'enrage', 'panic', 'hypnotize', 'energize', 'setBlankState']
SECONDARY = ['SCSTATE_IRRADIATED', 'SCSTATE_BLIND', 'SCSTATE_HEXED', 'SCSTATE_ACID_BURNT', 'SCSTATE_INVISIBLE',
             'SCSTATE_POWER_NULLIFICATION']
SELF_TYPES = ('active_defence', 'active_defense', 'transform')
WARN = re.compile(r'fault|unimplemented|unsupported|not implemented|unresolved|assert|abort|nan|invalid|failed|error',
                  re.I)
QUIET = re.compile(r'LoadLibraryA\(.*(asi|m3d|flt)\) -> not available|dropped 0/0/0/0|pipeline archive write disabled')


# ---------------------------------------------------------------- the catalog, from the player's game
def strings(path):
    return [m.decode('latin1') for m in re.findall(rb'[\x20-\x7e]{3,}', open(path, 'rb').read())]


def find(folder, rel):
    p = folder
    for part in rel.split('/'):
        hit = next((e for e in os.listdir(p) if e.lower() == part.lower()), None)
        if hit is None: return None
        p = os.path.join(p, hit)
    return p


def catalog(game):
    data = find(game, 'Data')
    ps = strings(os.path.join(data, 'powers.dat')); powers = {}
    for i in range(len(ps) - 3):     # a power: its name twice, its kind, its effect
        if ps[i] == ps[i + 1] and ' ' in ps[i] and re.match(r'^[a-z]+(_[a-z0-9]+)*$', ps[i + 2]):
            kind = ps[i + 2] if re.match(r'^(ranged|melee|special|area|direct|active_defen[cs]e|transform|throw)(_\d)?$', ps[i + 2]) else ''
            powers[ps[i]] = kind
    passive = sorted(set(ps[i] for i in range(len(ps) - 1) if ps[i] == ps[i + 1] and ' ' in ps[i] and ps[i] not in powers))
    cs = strings(os.path.join(data, 'characters.dat'))
    starts = [i for i in range(len(cs) - 3) if cs[i + 1] == 'HDR4' and cs[i + 2] == 'sCDef' and cs[i + 3] == cs[i]]
    chars, missing = [], {}
    for k, i in enumerate(starts):
        seg = cs[i:starts[k + 1] if k + 1 < len(starts) else len(cs)]
        own = [s for s in seg if s in powers and powers[s]]
        absent = [s for s in seg if re.match(r'^[a-z][a-z0-9 ]* [A-Z]', s) and s not in powers and s not in passive]
        if absent: missing[seg[0]] = absent
        chars.append((seg[0], own))
    effects = sorted(set(s for s in strings(os.path.join(data, 'res.dat')) if re.match(r'^effect_[a-z0-9_]+$', s)))
    fs = strings(os.path.join(data, 'fx.dat'))
    fx = sorted(set(fs[i] for i in range(len(fs) - 2) if fs[i] == fs[i + 1] and fs[i + 2].lower().startswith('library')))
    return dict(chars=chars, powers=powers, passive=passive, missing=missing, effects=effects, fx=fx)


def tests(cat):
    t = []
    for name, own in cat['chars']:
        t.append(['char', name, [[p, cat['powers'][p] in SELF_TYPES] for p in own]])
    t.append(['states', 'thug_with_gun' if any(c[0] == 'thug_with_gun' for c in cat['chars']) else cat['chars'][0][0],
              STATES + SECONDARY])
    t += [['effect', e, []] for e in cat['effects']]
    if FX:     # (the engine plays these only through their powers: by name it answers "Effect resource not found")
        t += [['fx', f, []] for f in cat['fx']]
    return t


BURST = 0
FX = 0
# what the game itself answers for things it doesn't do: noted in the report, not flagged
EXPECTED = re.compile(r'attacking obj is a civilian|Effect NIF not found|Effect resource not found')


def shots_of(test):
    per = 4 if BURST else 1
    return {'char': 2 + per * len(test[2]), 'states': 1 + per * len(test[2]), 'effect': 2, 'fx': 2}[test[0]]


# ---------------------------------------------------------------- the driver, in the game's Python 1.5
DRIVER = r'''from cshelper import *
from js import *
import sys

# Freedom Force coverage test (tools/ff_coverage.py): scratch overlay only
CMD = 'ffcov_cmd.txt'
SHOTS = %(shots)s
TESTS = %(tests)s
START = %(start)d
END = %(end)d
BURST = %(burst)d
cov = {'idx': START - 1, 'sub': 0, 'name': '', 'hero': '', 'spot': (0, 0, 0)}
covkeep = []

def covpos():
    # The game's tuple-to-NiPoint3 converter (fforce.exe 0x40c759) releases the tuple it is given, a reference it
    # only borrowed (the original's bug; its scripts pass temporaries). Each call gets a new tuple kept alive here.
    s = cov['spot']
    t = (s[0], s[1], s[2])
    covkeep.append(t)
    return t

def covw(line):
    f = open(CMD, 'ab'); f.write(line + '\n'); f.close()

def coverr(where):
    t, v = sys.exc_info()[:2]
    covw('# error %%d %%s %%s %%s' %% (cov['idx'], where, str(t), str(v)))

def covshot(tag):
    covw('shot:%%s/%%04d-%%s.png' %% (SHOTS, cov['idx'], tag))

def covlook():
    try:
        Camera_LookAtPos(covpos(), -150, 0, -100, 0, CPM_SNAP, CA_MOVE)
    except:
        coverr('look')

def covhero():
    h = cov['hero']
    try:
        normalize(h); heal(h)
    except:
        coverr('hero')

def OnPostInit():
    covw('# postinit')
    try:
        cov['hero'] = getAllHeroes()[0]
        god()
        AI_SetEnabled(cov['hero'], 0)
    except:
        coverr('postinit')
    regTimer('CovNext', 3)

def CovNext(event):
    cov['idx'] = cov['idx'] + 1
    i = cov['idx']
    if i >= END or i >= len(TESTS):
        covw('# batch done %%d' %% i)
        return
    t = TESTS[i]
    covw('# begin %%d %%s %%s' %% (i, t[0], t[1]))
    # beside the hero, once he stands in the map (not yet at OnPostInit), and again when the powers fired at him have
    # knocked him away: the game hides characters the heroes cannot perceive (about 550 units off they vanish)
    try:
        p = Get_ObjectPos(cov['hero']); covkeep.append(p); s = cov['spot']
        far = (p[0] + 150.0 - s[0]) * (p[0] + 150.0 - s[0]) + (p[1] - s[1]) * (p[1] - s[1]) > 90000.0
    except:
        far = 0
    if cov['spot'] == (0, 0, 0) or far:
        try:
            p = Get_ObjectPos(cov['hero'])
            cov['spot'] = (float(p[0]) + 150.0, float(p[1]), float(p[2]))
            covkeep.append(p)      # (Get_ObjectPos's own tuple: kept too, in case)
            covw('# spot %%s' %% `cov['spot']`)
        except:
            coverr('spot')
    covlook()
    regTimer('CovBase', 0.6)

def CovBase(event):
    covshot('base')
    regTimer('CovStart', 0.4)      # (the host takes the shot on a later frame: spawning now could put the character in it)

def CovStart(event):
    t = TESTS[cov['idx']]
    cov['sub'] = 0
    try:
        if t[0] == 'char' or t[0] == 'states':
            cov['name'] = 'cov_%%d' %% cov['idx']
            try:
                Mission_PrecacheTemplateObj(t[1])     # (as the missions do for templates they spawn later)
            except:
                coverr('precache')
            Object_SpawnAt(t[1], covpos(), cov['name'])
            covw('# spawned %%d %%d' %% (cov['idx'], Object_Exists(cov['name'])))
            if Object_Exists(cov['name']):
                q = Get_ObjectPos(cov['name']); covkeep.append(q)
                covw('# at %%d %%.0f %%.0f %%.0f' %% (cov['idx'], q[0], q[1], q[2]))
            AI_SetEnabled(cov['name'], 0)
            Object_SetAttr(cov['name'], 'minHealth', 100)
        elif t[0] == 'effect' or t[0] == 'fx':
            Object_PlayEffect(cov['hero'], t[1], '')
            covw('# played %%d' %% cov['idx'])
    except:
        coverr('start')
    regTimer('CovShown', 1.6)

def CovShown(event):
    t = TESTS[cov['idx']]
    if t[0] == 'effect' or t[0] == 'fx':
        covshot('shown')
        try:
            Object_StopEffect(cov['hero'], t[1])
        except:
            pass
        regTimer('CovEnd', 0.8)
        return
    if t[0] == 'char':
        covshot('idle')
        try:
            q = Get_ObjectPos(cov['name']); covkeep.append(q); h = Get_ObjectPos(cov['hero']); covkeep.append(h)
            covw('# idle %%d %%.0f %%.0f %%.0f hero %%.0f %%.0f %%.0f objects %%d' %% (cov['idx'], q[0], q[1], q[2], h[0], h[1], h[2], len(Mission_GetDynamicObjects())))
        except:
            coverr('idle')
    regTimer('CovUse', 0.2)

def CovUse(event):
    t = TESTS[cov['idx']]
    k = cov['sub']
    if k >= len(t[2]):
        regTimer('CovEnd', 0.2)
        return
    try:
        if not Object_Exists(cov['name']):
            covw('# skipped %%d %%d: no character' %% (cov['idx'], k))
        elif t[0] == 'char':
            power, own = t[2][k]
            target = cov['hero']
            if own:
                target = cov['name']
            Trigger_Power(cov['name'], target, power, '')
        else:
            state = t[2][k]
            if state[:8] == 'SCSTATE_':
                Object_SetSecondaryState(cov['name'], eval(state), 20, 0)     # (20 seconds, as the scripts set them)
            else:
                eval(state)(cov['name'])
    except:
        coverr('use %%d' %% k)
    if BURST:
        cov['burst'] = 0
        regTimer('CovBurst', 0.3)
        return
    regTimer('CovUsed', 1.8)

def CovBurst(event):    # --burst: four screenshots while the power plays out
    b = cov['burst']
    covshot('%%02d-%%d' %% (cov['sub'], b))
    cov['burst'] = b + 1
    if b < 3:
        regTimer('CovBurst', 0.45)
    else:
        regTimer('CovUsed', 0.2)

def CovUsed(event):
    t = TESTS[cov['idx']]
    k = cov['sub']
    if not BURST:
        covshot('%%02d' %% k)
    try:
        if t[0] == 'states':
            normalize(cov['name'])
        covhero()
    except:
        coverr('after %%d' %% k)
    cov['sub'] = k + 1
    covlook()
    regTimer('CovUse', 0.6)

def CovEnd(event):
    try:
        if cov['name'] and Object_Exists(cov['name']):
            Object_Destroy(cov['name'])
        cov['name'] = ''
        covhero()
    except:
        coverr('end')
    covw('# end %%d' %% cov['idx'])
    regTimer('CovNext', 0.5)
'''


def py15(v):
    """a Python 1.5 literal (lists, strings, numbers): repr() of today's types reads back there, except True/False"""
    if isinstance(v, bool): return '1' if v else '0'
    if isinstance(v, (list, tuple)): return '[' + ', '.join(py15(x) for x in v) + ']'
    if isinstance(v, str): return "'" + v.replace('\\', '\\\\').replace("'", "\\'") + "'"
    return repr(v)


def batches(all_tests, first, last):
    b, n, start = [], 0, first
    for i in range(first, last):
        s = shots_of(all_tests[i])
        if n + s > POWER_SHOTS_MAX and i > start:
            b.append((start, i)); start, n = i, 0
        n += s
    if start < last: b.append((start, last))
    return b


# ---------------------------------------------------------------- running the game
def run_batch(game, out, all_tests, start, end, log):
    data = os.path.join(out, 'data-%04d' % start)
    if os.path.exists(data): shutil.move(data, os.path.join(os.path.expanduser('~/.Trash'), 'ffcov-%s-%d' % (os.path.basename(data), time.time())))
    os.makedirs(os.path.join(data, 'game', 'Data', 'Missions', '01_begin'))
    shots = os.path.join(out, 'shots'); os.makedirs(shots, exist_ok=True)
    src = DRIVER % dict(shots=py15(shots), tests=py15(all_tests), start=start, end=end, burst=BURST)
    open(os.path.join(data, 'game', 'Data', 'Missions', '01_begin', 'mission.py'), 'w', newline='\r\n').write(src)
    cmd = os.path.join(data, 'game', 'ffcov_cmd.txt'); open(cmd, 'w').close()
    env = dict(os.environ, DS_TEST='1', W32_AUDIO_MUTE='1', DS_SCRIPT=DANGER_ROOM, DS_CMDFILE=cmd)
    for k in ('DS_LAUNCHER_SHOT', 'FF_LAUNCHER_SETTINGS', 'DS_UPDATER'): env.pop(k, None)   # test mode only: never the launch window
    assert env['DS_TEST'] == '1' and env['W32_AUDIO_MUTE'] == '1'
    app = os.path.join(HERE, 'work', 'ff', 'app', 'FreedomForceNative')
    runlog = os.path.join(out, 'run-%04d.log' % start)
    with open(runlog, 'w') as lf:
        p = subprocess.Popen([app, '--exe', os.path.join(HERE, 'work', 'ff', 'fforce.exe'), '--game', game, '--data', data],
                             stdout=lf, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL, cwd=HERE, env=env)
    t0 = last = time.time(); seen = 0; begun = None; outcome = None; ended = set()
    try:
        while True:
            time.sleep(1)
            lines = open(cmd, 'rb').read().decode('latin1').splitlines()
            if len(lines) > seen:
                for line in lines[seen:]:
                    m = re.match(r'# begin (\d+)', line)
                    if m: begun = int(m.group(1))
                    m = re.match(r'# end (\d+)', line)
                    if m: ended.add(int(m.group(1)))
                    if line.startswith('# batch done'): outcome = 'done'
                seen = len(lines); last = time.time()
            if outcome: break
            if p.poll() is not None: outcome = 'exited %d' % p.returncode; break
            if time.time() - last > (150 if not seen else 60): outcome = 'hang'; break
    finally:                                    # Ctrl-C or an exception in the loop must not leave the game running
        if p.poll() is None:
            p.send_signal(signal.SIGTERM)
            try: p.wait(10)
            except subprocess.TimeoutExpired: p.kill(); p.wait()
    fix_names(shots)
    log.write('batch %d-%d: %s after %.0f s, last begun %s\n' % (start, end, outcome, time.time() - t0, begun)); log.flush()
    return outcome, begun, ended, lines, runlog


def fix_names(shots):          # (in case a line ever reaches the host with Windows' \r)
    for f in os.listdir(shots):
        if '\r' in f: os.replace(os.path.join(shots, f), os.path.join(shots, f.replace('\r', '')))


# ---------------------------------------------------------------- checking
def tool(name):
    exe = os.path.join(HERE, 'work', name)
    src = os.path.join(HERE, 'tools', name + '.m')
    if not os.path.exists(exe) or os.path.getmtime(exe) < os.path.getmtime(src):
        subprocess.check_call(['clang', '-O2', '-fobjc-arc', '-framework', 'AppKit', src, '-o', exe])
    return exe


def log_trouble(runlog):
    """renderer/runtime warnings in a run's log, each against the last screenshot asked for before it"""
    out, current = {}, 'startup'
    for line in open(runlog, errors='replace'):
        m = re.search(r'command shot:.*/(\d{4})-', line)
        if m: current = int(m.group(1)); continue
        if 'dropped' in line and 'dropped 0/0/0/0' not in line: out.setdefault(current, []).append(line.strip()[:200])
        elif WARN.search(line) and not QUIET.search(line) and 'command' not in line: out.setdefault(current, []).append(line.strip()[:200])
    return out


def main():
    a = sys.argv[1:]
    game = os.path.expanduser(a[a.index('--game') + 1]) if '--game' in a else os.path.expanduser('~/Games/FreedomForce')
    out = os.path.abspath(a[a.index('--out') + 1]) if '--out' in a else os.path.join(HERE, 'work', 'coverage')
    os.makedirs(out, exist_ok=True)
    global BURST
    global FX
    BURST = 1 if '--burst' in a else 0
    FX = 1 if '--fx' in a else 0
    cat = catalog(game); all_tests = tests(cat); picked = None
    if '--tests' in a:     # a hand-picked list (by the full run's numbers): numbered 0.. in this output folder
        picked = [int(x) for x in a[a.index('--tests') + 1].split(',')]; all_tests = [all_tests[i] for i in picked]
    json.dump(dict(cat, tests=all_tests, picked=picked), open(os.path.join(out, 'catalog.json'), 'w'), indent=1)
    first, last = 0, len(all_tests)
    if '--only' in a: first, last = [int(x) for x in a[a.index('--only') + 1].split('-')]; last = min(last + 1, len(all_tests))
    status = {}
    stfile = os.path.join(out, 'status.json')
    if '--report' not in a:
        log = open(os.path.join(out, 'coverage.log'), 'a')
        log.write('== %s: %d characters, %d powers used by them, %d states, %d effects, %d power effects; tests %d-%d\n' % (
            time.strftime('%Y-%m-%d %H:%M'), len(cat['chars']), sum(len(c[1]) for c in cat['chars']), len(STATES + SECONDARY),
            len(cat['effects']), len(cat['fx']), first, last - 1))
        todo = batches(all_tests, first, last)
        tries = {}
        while todo:
            s, e = todo.pop(0)
            outcome, begun, ended, lines, runlog = run_batch(game, out, all_tests, s, e, log)
            errors = [l for l in lines if l.startswith('# error')]
            for i in range(s, e):
                if i in ended: status[i] = dict(result='ok', runlog=runlog)
            for l in errors:
                i = int(l.split()[2]); status.setdefault(i, dict(result='ok', runlog=runlog)).setdefault('script', []).append(l[2:])
            if outcome != 'done':
                bad = begun if begun is not None and begun not in ended else None
                if bad is None:     # it never got to a test: the game didn't reach the mission (the menu clicks are timed)
                    tries[s] = tries.get(s, 0) + 1
                    if tries[s] < 3 and not ended:
                        log.write('   batch %d-%d stopped before any test (%s): trying again\n' % (s, e, outcome))
                        todo.insert(0, (s, e)); continue
                    log.write('   batch %d-%d stopped before any test (%s): not retried\n' % (s, e, outcome))
                    for i in range(s, e): status.setdefault(i, dict(result='not run: ' + outcome, runlog=runlog))
                    continue
                status[bad] = dict(result='crash' if outcome.startswith('exited') else outcome, detail=outcome, runlog=runlog)
                log.write('   test %d (%s %s): %s\n' % (bad, all_tests[bad][0], all_tests[bad][1], outcome))
                if bad + 1 < e: todo.insert(0, (bad + 1, e))
            json.dump(status, open(stfile, 'w'), indent=1)
    else:
        status = {int(k): v for k, v in json.load(open(stfile)).items()}
    report(out, cat, all_tests, status, first, last)


def report(out, cat, all_tests, status, first, last):
    shots = os.path.join(out, 'shots'); covimg = tool('ff_covimg')
    files = sorted(os.listdir(shots)) if os.path.isdir(shots) else []
    by = {}
    for f in files:
        m = re.match(r'(\d{4})-(.*)\.png$', f)
        if m: by.setdefault(int(m.group(1)), {})[m.group(2)] = os.path.join(shots, f)
    trouble = {}
    for f in sorted(os.listdir(out)):
        if f.startswith('run-') and f.endswith('.log'):
            for k, v in log_trouble(os.path.join(out, f)).items(): trouble.setdefault(k, []).extend(v)
    rows, flags = [], []
    for i in range(first, last):
        t = all_tests[i]; st = status.get(i, dict(result='not run')); s = by.get(i, {})
        script = st.get('script', [])
        row = dict(i=i, kind=t[0], name=t[1], result=st['result'], script=[x for x in script if not EXPECTED.search(x)],
                   notes=[x for x in script if EXPECTED.search(x)], log=trouble.get(i, []), checks=[])
        base = s.get('base')
        for tag in sorted(k for k in s if k != 'base'):
            ref = s.get('base') if tag in ('idle', 'shown') else s.get('idle', base)
            o = subprocess.run([covimg, 'stats', ref or '-', s[tag]], capture_output=True, text=True).stdout.split()
            if len(o) < 4: continue
            mean, diff, flat = float(o[1]), float(o[2]), float(o[3])
            label = tag if not tag.isdigit() else (t[2][int(tag)][0] if t[0] == 'char' else t[2][int(tag)])
            c = dict(tag=tag, what=label, mean=mean, diff=diff, flat=flat)
            if mean < 6: c['flag'] = 'black frame'
            elif flat > 0.9: c['flag'] = 'one colour'
            elif tag == 'idle' and 0 <= diff < 0.0015: c['flag'] = 'character not visible'
            row['checks'].append(c)
        if row['result'] != 'ok' or row['script'] or row['log'] or any('flag' in c for c in row['checks']): flags.append(row)
        rows.append(row)
    json.dump(rows, open(os.path.join(out, 'results.json'), 'w'), indent=1)
    sheets = os.path.join(out, 'sheets'); os.makedirs(sheets, exist_ok=True)
    groups = {}
    for i in sorted(by):
        if first <= i < last: groups.setdefault(all_tests[i][0], []).append(i)
    made = 0
    for kind, ids in groups.items():
        items = []
        for i in ids:
            for tag in sorted(by[i]):
                if tag == 'base': continue
                what = tag if not tag.isdigit() else (all_tests[i][2][int(tag)][0] if kind == 'char' else all_tests[i][2][int(tag)])
                items.append('%d %s: %s=%s' % (i, all_tests[i][1], what, by[i][tag]))
        for n in range(0, len(items), 24):
            subprocess.run([covimg, 'sheet', os.path.join(sheets, '%s-%03d.png' % (kind, n // 24)), '6'] + items[n:n + 24]); made += 1
    n = len(rows); ok = sum(1 for r in rows if r['result'] == 'ok')
    with open(os.path.join(out, 'REPORT.md'), 'w') as f:
        f.write('# Freedom Force coverage: %d tests, %d ran to the end\n\n' % (n, ok))
        f.write('- %d characters (%d powers fired), one character through %d states, %d level effects, %d power effects by name.\n' % (
            sum(1 for r in rows if r['kind'] == 'char'), sum(len(all_tests[r['i']][2]) for r in rows if r['kind'] == 'char'),
            len(STATES + SECONDARY), sum(1 for r in rows if r['kind'] == 'effect'), sum(1 for r in rows if r['kind'] == 'fx')))
        f.write('- Passive powers (nothing to fire): %d. Powers characters list but powers.dat lacks: %s\n' % (
            len(cat['passive']), ', '.join('%s: %s' % (k, ', '.join(v)) for k, v in sorted(cat['missing'].items())) or 'none'))
        f.write('- Expected answers from the game (civilians cannot attack, effects whose files the game lacks): %d\n' % sum(len(r['notes']) for r in rows))
        f.write('- Contact sheets: %d in %s\n\n## Flagged (%d)\n\n' % (made, sheets, len(flags)))
        for r in flags:
            f.write('- %d %s %s: %s' % (r['i'], r['kind'], r['name'], r['result']))
            for c in r['checks']:
                if 'flag' in c: f.write('; %s: %s' % (c['what'], c['flag']))
            for s in r['script'][:3]: f.write('; script: %s' % s)
            for l in r['log'][:3]: f.write('; log: %s' % l)
            f.write('\n')
    print(open(os.path.join(out, 'REPORT.md')).read())


if __name__ == '__main__':
    main()
