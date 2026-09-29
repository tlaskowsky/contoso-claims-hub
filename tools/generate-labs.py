#!/usr/bin/env python3
"""Generate every lab's start and solution versions from the single annotated
source in infra/ (which is itself the complete, deployable final solution).

Markers (all are Bicep comments, so infra/ stays valid Bicep):
  <code>  // @from X             line exists from lab X onwards
  // @from X begin ... // @end   block exists from lab X onwards
  // @until X: <code>            earlier form of a line, used before lab X
  // LAB-BLANK(X): <hint>        TODO hint, shown only in lab X's start version
  <code>  // @blank X            removed in lab X's start version (the learner writes it)
  Tags can be combined: <code>  // @from X @blank X

Output:  labs/lab-<X>/start/infra/   and   labs/lab-<X>/solution/infra/
Checks:  every solution compiles; lab 3.3's solution equals the final infra/.

Usage:   python3 tools/generate-labs.py [--bicep <path to bicep CLI>]
"""
import json, re, shutil, subprocess, sys, tempfile
from pathlib import Path

LABS = ['1.1', '1.2', '1.3', '2.1', '2.2', '2.3', '2.4', '3.1', '3.2', '3.3']
ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / 'infra'
OUT = ROOT / 'labs'

def v(x): return tuple(int(p) for p in x.split('.'))

BLOCK_BEGIN = re.compile(r'^\s*// @from (\d\.\d) begin\s*$')
BLOCK_END = re.compile(r'^\s*// @end\s*$')
UNTIL = re.compile(r'^(\s*)// @until (\d\.\d): (.*)$')
HINT = re.compile(r'^(\s*)// LAB-BLANK\((\d\.\d)\): (.*)$')
TAGS = re.compile(r'\s*//((?:\s*@(?:from|blank) \d\.\d)+)\s*$')

def process(text, lab, mode):
    out, stack = [], []
    for line in text.split('\n'):
        m = BLOCK_BEGIN.match(line)
        if m: stack.append(v(lab) >= v(m.group(1))); continue
        if BLOCK_END.match(line): stack.pop(); continue
        if not all(stack): continue
        m = UNTIL.match(line)
        if m:
            if v(lab) < v(m.group(2)): out.append(m.group(1) + m.group(3))
            continue
        m = HINT.match(line)
        if m:
            if mode == 'start' and lab == m.group(2):
                out.append(f'{m.group(1)}// TODO (Lab {lab}): {m.group(3)}')
            continue
        m = TAGS.search(line)
        if m:
            code = line[:m.start()]
            tags = dict(re.findall(r'@(from|blank) (\d\.\d)', m.group(1)))
            if 'from' in tags and v(lab) < v(tags['from']): continue
            if 'blank' in tags and mode == 'start' and lab == tags['blank']: continue
            out.append(code); continue
        out.append(line)
    assert not stack, 'unbalanced @from begin / @end'
    return '\n'.join(out)

def compile_params(bicep, main_path):
    res = subprocess.run([bicep, 'build', str(main_path), '--stdout'], capture_output=True, text=True)
    if res.returncode != 0:
        raise SystemExit(f'Compile failed: {main_path}\n{res.stderr}')
    return json.loads(res.stdout)

def write_tree(dest, lab, mode):
    if dest.exists(): shutil.rmtree(dest)
    (dest / 'modules').mkdir(parents=True)
    (dest / 'parameters').mkdir()
    for f in [SRC / 'main.bicep', *sorted((SRC / 'modules').glob('*.bicep'))]:
        rel = f.relative_to(SRC)
        (dest / rel).write_text(process(f.read_text(), lab, mode))
    shutil.copy(SRC / 'bicepconfig.json', dest / 'bicepconfig.json')

def write_params(dest, template_params, lab, mode):
    for env in ('dev', 'test'):
        if env == 'test' and not (lab == '3.3' and mode == 'solution'):
            continue  # learners write test.parameters.json themselves in Lab 3.3
        src = json.loads((SRC / 'parameters' / f'{env}.parameters.json').read_text())
        src['parameters'] = {k: val for k, val in src['parameters'].items() if k in template_params}
        (dest / 'parameters' / f'{env}.parameters.json').write_text(json.dumps(src, indent=2) + '\n')

def main():
    bicep = sys.argv[sys.argv.index('--bicep') + 1] if '--bicep' in sys.argv else 'bicep'
    final = compile_params(bicep, SRC / 'main.bicep')
    for lab in LABS:
        sol = OUT / f'lab-{lab}' / 'solution' / 'infra'
        start = OUT / f'lab-{lab}' / 'start' / 'infra'
        write_tree(sol, lab, 'solution')
        tpl = compile_params(bicep, sol / 'main.bicep')
        write_params(sol, tpl['parameters'].keys(), lab, 'solution')
        write_tree(start, lab, 'start')
        write_params(start, tpl['parameters'].keys(), lab, 'start')
        todos = sum(p.read_text().count(f'TODO (Lab {lab})') for p in start.rglob('*.bicep'))
        print(f'lab {lab}: {len(tpl["parameters"]):2} params, {len(tpl["resources"]):2} resources, '
              f'{len(tpl["outputs"]):2} outputs, {todos} TODOs in start')
        if lab == LABS[-1]:
            for key in ('parameters', 'resources', 'outputs'):
                if json.dumps(tpl[key], sort_keys=True) != json.dumps(final[key], sort_keys=True):
                    raise SystemExit(f'Lab {lab} solution differs from final infra/ in {key}')
            print('final check: lab 3.3 solution == infra/ (parameters, resources, outputs)')

if __name__ == '__main__':
    main()
