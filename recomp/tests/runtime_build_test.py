"""An incremental runtime build must preserve its last good output on failure."""
import os
from pathlib import Path
import subprocess
import tempfile
import shutil
ROOT = Path(__file__).resolve().parents[2]
scratch = ROOT / "build/macos-checks"
scratch.mkdir(parents=True, exist_ok=True)
tmp = tempfile.mkdtemp(prefix="runtime-build-test-", dir=scratch)
try:
    out = Path(tmp)
    (out / "obj/rt").mkdir(parents=True)
    (out / "obj/rt/old.o").write_text("last good object")
    (out / "libgame.dylib").write_text("last good library")
    (out / "fforce.exe").touch()
    compiler = out / "compiler"
    compiler.write_text("""#!/bin/bash
for arg in "$@"; do
  case "$arg" in */core.c) exit 42;; -shared) echo 'link attempted after failure' >&2; exit 99;; esac
done
while [ $# -gt 0 ]; do if [ "$1" = -o ]; then shift; touch "$1"; fi; shift; done
""")
    compiler.chmod(0o755)
    for jobs in (1, 4):
        env = dict(os.environ, CC=str(compiler), FF_BUILD_JOBS=str(jobs))
        p = subprocess.run([str(ROOT / "recomp/tools/build_runtime.sh"), str(out)], env=env, capture_output=True, text=True, timeout=60)
        assert p.returncode != 0, p.stdout + p.stderr
        assert "link attempted" not in p.stderr
        assert (out / "obj/rt/old.o").read_text() == "last good object"
        assert (out / "libgame.dylib").read_text() == "last good library"
        assert not (out / ".runtime-build.lock").exists()
finally:
    trash = Path.home() / ".Trash"
    trash.mkdir(exist_ok=True)
    shutil.move(tmp, tempfile.mkdtemp(prefix="freedom-force-", dir=trash))
print("Runtime build: failed children stop linking and preserve previous artifacts")
