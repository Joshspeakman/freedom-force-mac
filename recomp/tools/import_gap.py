"""import_gap.py <image>... : each image's imports that no IMPL(dll, name) in runtime/win32 implements (names
canonicalised as loader.c does: lower-case DLL, no stdcall decoration, ordinals as ordN)."""
import sys, os, re, glob, collections
sys.path.insert(0, os.path.dirname(__file__)); from pe import PE
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
impl = set()
for f in glob.glob(os.path.join(HERE, 'runtime', 'win32', '*.c')):
    for d, n in re.findall(r'^IMPL\((\w+),\s*(\w+)\)', open(f, errors='replace').read(), re.M): impl.add('%s!%s' % (d.lower(), n))
def canon(dll, fn):
    d = dll.split('.')[0].lower()
    if d.startswith('d3dx9_'): d = 'd3dx9_29'                  # loader.c: one D3DX9 for every version
    if d == 'ws2_32': d = 'wsock32'                             # loader.c: Winsock 2 by WSOCK32's ordinals
    if fn.startswith('#'): return '%s!ord%s' % (d, fn[1:])
    if fn.startswith('_') and '@' in fn: fn = fn[1:]
    return '%s!%s' % (d, fn.split('@')[0])
skip = set(a.lower() for a in os.environ.get('GAP_SKIP_DLLS', '').split(',') if a)
# the images named on the command line form one recompiled set: imports one of them exports are served by it
# (a rebased copy keeps its DLL's name)
served = set(os.path.basename(p).lower() for p in sys.argv[1:])
for p in sys.argv[1:]:
    pe = PE(p); by = collections.defaultdict(list); nset = 0
    for va, name in pe.imports.items():
        dll, fn = name.split('!', 1)
        if dll.lower() in skip: continue
        if dll.lower() in served: nset += 1; continue
        if canon(dll, fn) not in impl: by[dll].append(fn)
    print('== %s: %d imports, %d from the recompiled set, %d not implemented' % (os.path.basename(p), len(pe.imports), nset, sum(map(len, by.values()))))
    for d in sorted(by): print('  %-18s %3d  %s' % (d, len(by[d]), ' '.join(sorted(by[d]))))
