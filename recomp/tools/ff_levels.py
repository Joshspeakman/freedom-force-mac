#!/usr/bin/env python3
"""ff_levels.py [--game DIR] [--out DIR] [--only NAME,NAME...] [--trace STOP] [--at X,Y,Z] [--report]

Every map of Freedom Force loaded and looked at in the running game (test mode, muted, scratch data): the level
half of the coverage test (tools/ff_coverage.py does the characters, powers and effects).

The Danger Room's "Came a Hero!" loads Missions/01_begin. For each map (each campaign mission, each mission's base
interlude, each multiplayer map) a scratch overlay puts that map's mission.dat, mission.mg and ambience.dat in
01_begin's place, with a Python 1.5 driver as its mission.py: the camera visits up to eight points spread over the
map's objects (farthest-point picks from Mission_GetDynamicObjects), and the host takes a screenshot at each through
DS_CMDFILE. One game run per map; a crash or hang is recorded against it. Each frame is checked (tools/ff_covimg.m)
and the logs are searched as in ff_coverage.py; contact sheets go to <out>/sheets. Outputs stay in recomp/work.
"""
import os, re, shutil, signal, subprocess, sys, time, zipfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ff_coverage as cov

HERE = cov.HERE
STOPS = 8
TRACE = -1
AT = '0'
DRIVER = r'''from cshelper import *
from js import *
import sys

# Freedom Force level coverage (tools/ff_levels.py): scratch overlay only
CMD = 'ffcov_cmd.txt'
SHOTS = %(shots)s
MAP = %(map)s
TRACE = %(trace)d
AT = %(at)s
keep = []
tour = {'k': 0, 'stops': []}

def covw(line):
    f = open(CMD, 'ab'); f.write(line + '\n'); f.close()

def coverr(where):
    t, v = sys.exc_info()[:2]
    covw('# error %%s %%s %%s' %% (where, str(t), str(v)))

def OnPostInit():
    covw('# postinit')
    regTimer('TourPlan', 3)

def TourPlan(event):
    pts = []
    try:
        heroes = getAllHeroes()
        covw('# heroes %%s' %% `heroes`)
        if heroes:
            god()
            p = Get_ObjectPos(heroes[0]); keep.append(p); pts.append((p[0], p[1], p[2]))
        objs = Mission_GetDynamicObjects()
        covw('# objects %%d' %% len(objs))
        for o in objs:
            try:
                p = Get_ObjectPos(o); keep.append(p); pts.append((p[0], p[1], p[2]))
            except:
                pass
    except:
        coverr('plan')
    stops = []
    if pts:
        stops.append(pts[0])
        while len(stops) < %(stops)d and len(stops) < len(pts):
            best = None; bestd = -1.0
            for p in pts:
                d = 1.0e30
                for s in stops:
                    e = (p[0] - s[0]) * (p[0] - s[0]) + (p[1] - s[1]) * (p[1] - s[1])
                    if e < d:
                        d = e
                if d > bestd:
                    bestd = d; best = p
            if bestd < 250000.0:      # (closer than 500 units to a stop already chosen: enough)
                break
            stops.append(best)
    if stops and len(stops) < 4:      # a map with few objects (the multiplayer maps): a ring round the start too
        c = stops[0]
        for dx, dy in ((1200.0, 0.0), (0.0, 1200.0), (-1200.0, 0.0), (0.0, -1200.0), (2400.0, 2400.0), (-2400.0, -2400.0)):
            if len(stops) < %(stops)d:
                stops.append((c[0] + dx, c[1] + dy, c[2]))
    if AT:
        stops = [AT]      # --at: one fixed point (for comparing runs)
    tour['stops'] = stops
    covw('# stops %%d' %% len(stops))
    for s in stops:
        covw('# stop %%.0f,%%.0f,%%.0f' %% (s[0], s[1], s[2]))
    regTimer('TourGo', 0.2)

def TourGo(event):
    k = tour['k']
    if k >= len(tour['stops']):
        covw('# end')
        return
    s = tour['stops'][k]
    t = (s[0], s[1], s[2]); keep.append(t)
    try:
        Camera_LookAtPos(t, -150, 0, -100, 0, CPM_SNAP, CA_MOVE)
    except:
        coverr('look %%d' %% k)
    regTimer('TourShot', 1.4)

def TourShot(event):
    covw('shot:%%s/%%s-%%d.png' %% (SHOTS, MAP, tour['k']))
    if tour['k'] == TRACE:      # --trace: a one-frame draw trace of this stop (D3D9_DRAWTRACE_ON)
        f = open('trace_on', 'w'); f.write('1'); f.close()
    tour['k'] = tour['k'] + 1
    regTimer('TourGo', 0.4)
'''


def maps(game):
    """(name, {file: bytes source}) for each map: the archive's files, a loose copy in the game folder winning"""
    data = cov.find(game, 'Data')
    z = zipfile.ZipFile(cov.find(data, 'missions.ff'))
    names = {}
    for n in z.namelist():
        p = n.split('\\')
        if len(p) == 3 and p[0].lower() == 'missions': names.setdefault(p[1], {})[p[2].lower()] = ('zip', n)
    loose = cov.find(data, 'Missions')
    for d in sorted(os.listdir(loose)) if loose else []:
        full = os.path.join(loose, d)
        if os.path.isdir(full):
            for f in os.listdir(full): names.setdefault(d, {})[f.lower()] = ('file', os.path.join(full, f))
    out = []
    for m in sorted(names, key=str.lower):
        files = names[m]
        if 'mission.dat' in files and 'mission.mg' in files:
            out.append((m, {'mission.dat': files['mission.dat'], 'mission.mg': files['mission.mg'], 'ambience.dat': files.get('ambience.dat')}))
        if 'base.dat' in files and 'base.mg' in files:
            out.append((m + '_base', {'mission.dat': files['base.dat'], 'mission.mg': files['base.mg'], 'ambience.dat': files.get('ambience.dat')}))
    return z, out


def run_map(game, out, z, name, files, log):
    data = os.path.join(out, 'data-' + name)
    if os.path.exists(data): shutil.move(data, os.path.join(os.path.expanduser('~/.Trash'), 'fflev-%s-%d' % (name, time.time())))
    slot = os.path.join(data, 'game', 'Data', 'Missions', '01_begin'); os.makedirs(slot)
    for f, src in files.items():
        if not src: continue
        blob = z.read(src[1]) if src[0] == 'zip' else open(src[1], 'rb').read()
        open(os.path.join(slot, f), 'wb').write(blob)
    shots = os.path.join(out, 'shots'); os.makedirs(shots, exist_ok=True)
    open(os.path.join(slot, 'mission.py'), 'w', newline='\r\n').write(DRIVER % dict(shots=cov.py15(shots), map=cov.py15(name), stops=STOPS, trace=TRACE, at=AT))
    cmd = os.path.join(data, 'game', 'ffcov_cmd.txt'); open(cmd, 'w').close()
    env = dict(os.environ, DS_TEST='1', W32_AUDIO_MUTE='1', DS_SCRIPT=cov.DANGER_ROOM, DS_CMDFILE=cmd,
               D3D9_STATELOG='1')   # each render/texture-stage state the game uses, once: the inventory for the renderer
    if TRACE >= 0: env['D3D9_DRAWTRACE_ON'] = os.path.join(data, 'game', 'trace_on')
    for k in ('DS_LAUNCHER_SHOT', 'FF_LAUNCHER_SETTINGS', 'DS_UPDATER'): env.pop(k, None)
    assert env['DS_TEST'] == '1' and env['W32_AUDIO_MUTE'] == '1'
    runlog = os.path.join(out, 'run-%s.log' % name)
    with open(runlog, 'w') as lf:
        p = subprocess.Popen([os.path.join(HERE, 'work', 'ff', 'app', 'FreedomForceNative'), '--exe', os.path.join(HERE, 'work', 'ff', 'fforce.exe'),
                              '--game', game, '--data', data], stdout=lf, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL, cwd=HERE, env=env)
    t0 = last = time.time(); seen = 0; outcome = None; lines = []
    try:
        while True:
            time.sleep(1)
            lines = open(cmd, 'rb').read().decode('latin1').splitlines()
            if len(lines) > seen: seen, last = len(lines), time.time()
            if any(l.startswith('# end') for l in lines): outcome = 'done'; time.sleep(2); break
            if p.poll() is not None: outcome = 'exited %d' % p.returncode; break
            if time.time() - last > (150 if not seen else 60): outcome = 'hang' if seen else 'never reached the map'; break
    finally:                                    # Ctrl-C or an exception in the loop must not leave the game running
        if p.poll() is None:
            p.send_signal(signal.SIGTERM)
            try: p.wait(10)
            except subprocess.TimeoutExpired: p.kill(); p.wait()
    cov.fix_names(shots)
    log.write('%-28s %s after %.0f s (%s)\n' % (name, outcome, time.time() - t0, '; '.join(l[2:] for l in lines if l.startswith('# ') and not l.startswith('# end'))[:300]))
    log.flush()
    return outcome


def main():
    a = sys.argv[1:]
    game = os.path.expanduser(a[a.index('--game') + 1]) if '--game' in a else os.path.expanduser('~/Games/FreedomForce')
    out = os.path.abspath(a[a.index('--out') + 1]) if '--out' in a else os.path.join(HERE, 'work', 'levels')
    os.makedirs(out, exist_ok=True)
    global TRACE
    global AT
    if '--trace' in a: TRACE = int(a[a.index('--trace') + 1])
    if '--at' in a: AT = '(%s)' % ', '.join('%s.0' % v.split('.')[0] for v in a[a.index('--at') + 1].split(','))
    z, all_maps = maps(game)
    if '--only' in a:
        want = set(a[a.index('--only') + 1].split(',')); all_maps = [m for m in all_maps if m[0] in want]
    if '--report' not in a:
        log = open(os.path.join(out, 'levels.log'), 'a')
        log.write('== %s: %d maps\n' % (time.strftime('%Y-%m-%d %H:%M'), len(all_maps)))
        for name, files in all_maps: run_map(game, out, z, name, files, log)
    report(out, all_maps)


def report(out, all_maps):
    covimg = cov.tool('ff_covimg'); shots = os.path.join(out, 'shots')
    results = {}
    for line in open(os.path.join(out, 'levels.log')):
        m = re.match(r'(\S+)\s+(done|exited -?\d+|hang|never reached the map) after', line)
        if m: results[m.group(1)] = m.group(2)
    lines, items = [], []
    for name, _ in all_maps:
        res = results.get(name, 'not run'); frames = sorted(f for f in os.listdir(shots) if f.startswith(name + '-')) if os.path.isdir(shots) else []
        flags = []
        for f in frames:
            o = subprocess.run([covimg, 'stats', '-', os.path.join(shots, f)], capture_output=True, text=True).stdout.split()
            o = ['path'] + o[-3:] if len(o) >= 4 else o          # "<path> mean diff flat": the path may hold spaces
            if len(o) >= 4 and float(o[1]) < 6: flags.append('%s black' % f)
            elif len(o) >= 4 and float(o[3]) > 0.9: flags.append('%s one colour' % f)
            items.append('%s=%s' % (f[:-4], os.path.join(shots, f)))
        log = os.path.join(out, 'run-%s.log' % name)
        trouble = [l for v in cov.log_trouble(log).values() for l in v] if os.path.exists(log) else []
        lines.append((name, res, len(frames), flags, trouble[:3]))
    sheets = os.path.join(out, 'sheets'); os.makedirs(sheets, exist_ok=True)
    for n in range(0, len(items), 24):
        subprocess.run([covimg, 'sheet', os.path.join(sheets, 'levels-%02d.png' % (n // 24)), '6'] + items[n:n + 24])
    with open(os.path.join(out, 'REPORT.md'), 'w') as f:
        ok = sum(1 for l in lines if l[1] == 'done')
        f.write('# Freedom Force levels: %d maps, %d toured to the end\n\n' % (len(lines), ok))
        for name, res, nf, flags, trouble in lines:
            f.write('- %s: %s, %d frames%s%s\n' % (name, res, nf, ('; ' + ', '.join(flags)) if flags else '', ('; log: ' + ' | '.join(trouble)) if trouble else ''))
    print(open(os.path.join(out, 'REPORT.md')).read())


if __name__ == '__main__':
    main()
