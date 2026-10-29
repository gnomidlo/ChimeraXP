"""Run Lua regressions in isolated runtimes on Windows or Unix.

Uses Lupa (Lua 5.1 and 5.4) when installed; CI can use its Lua executable.
Filesystem operations in the historical updater smoke are handled natively,
within this run's temporary directory, rather than composed across shells.
"""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT.parent / '.test-runtime'))


def run():
    os.chdir(ROOT)
    files = sys.argv[1:] or [str(p) for p in sorted((ROOT / 'tests').glob('*.lua')) if not p.name.startswith('support_')]
    try:
        from lupa import lua51, lua54
        runtimes = [lua51.LuaRuntime, lua54.LuaRuntime]
    except ImportError:
        executable = shutil.which('lua5.4') or shutil.which('lua')
        if not executable:
            raise SystemExit('Install lupa or Lua 5.4 to run the Lua regression suites.')
        for file in files:
            subprocess.run([executable, file], cwd=ROOT, check=True)
        return
    for runtime in runtimes:
        for file in files:
            print('RUN', runtime.__module__, Path(file).name, flush=True)
            with tempfile.TemporaryDirectory(prefix='chimeraxp-test-') as temp:
                base = Path(temp).resolve()
                lua = runtime(unpack_returned_tuples=True)
                lua.globals().TEST_TMP = base.as_posix()

                def checked(path):
                    resolved = Path(path).resolve()
                    if resolved != base and base not in resolved.parents:
                        raise ValueError('Test filesystem operation escapes temporary directory')
                    return resolved

                def execute(command):
                    if command.startswith('mkdir -p '):
                        path = re.fullmatch(r'mkdir -p "([^"]+)"', command)
                        checked(path[1]).mkdir(parents=True, exist_ok=True)
                    elif command.startswith('rm -rf '):
                        path = re.fullmatch(r'rm -rf "([^"]+)"', command)
                        target = checked(path[1])
                        if target.exists():
                            shutil.rmtree(target)
                    else:
                        raise ValueError('Unsupported test command: ' + command)
                    return True

                def popen(command):
                    path = re.search(r'"([^"]+)"', command)
                    if command.startswith('test -d '):
                        # mkdirs inspects existing ancestors of the temp path.
                        return 'yes' if Path(path[1]).is_dir() else ''
                    if command.startswith('find '):
                        files = sorted(p for p in checked(path[1]).rglob('*') if p.is_file())
                        return files[0].as_posix() + '\n' if files else ''
                    raise ValueError('Unsupported test pipe: ' + command)

                lua.globals().py_execute = execute
                lua.globals().py_popen = popen
                lua.execute('''os.execute=py_execute
                    io.popen=function(command)
                        local data=py_popen(command)
                        return {read=function(_,mode) if mode=='*l' then return data:match('([^\\r\\n]+)') else return data end end,
                            close=function() return true end}
                    end''')
                lua.execute('dofile(...)', file)


if __name__ == '__main__':
    run()
