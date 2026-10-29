#!/usr/bin/env python3
"""Actual production runtime + Foundation fixtures, NOT Substrate/UIKit/device.

macOS compiles the baseline and each named semantic mutant, then runs fresh
processes. Only WCKRuntime.m gets the narrow dlsym identifier substitution.
Non-macOS writes truthful UNSUPPORTED_ENV evidence and exits 77, never PASS.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

CASES = [
    'missing-targets', 'invalid-arguments', 'signatures', 'block-object',
    'qualifiers', 'signature-retry', 'api-missing-retry', 'install-original',
    'install-trampoline', 'backend-noop', 'backend-noop-empty', 'backend-no-touch',
    'backend-null-original', 'backend-null-inflight', 'backend-recursive-original',
    'backend-exception', 'idempotent-owner', 'owner-conflict',
    'preexisting-replacement', 'quarantine-repeat', 'reentrant-owner',
    'threaded-owner', 'cross-thread-owner', 'fresh-method-signature',
    'inherited-instance', 'inherited-class',
    'inherited-quarantine', 'inherited-parent-chain', 'class-target-distinction',
    'foreign-postcondition', 'confirmed-outer-chain', 'status-snapshot',
    'module-ready', 'module-unverified',
]
MUTANT_NAMES = [
    'mutant-ignore-arity', 'mutant-ignore-return', 'mutant-ignore-argument',
    'mutant-block-as-object', 'mutant-assume-postcondition',
    'mutant-raw-duplicate-original', 'mutant-discard-backend-trampoline',
    'mutant-alias-live-original', 'mutant-repeat-quarantined-target',
    'mutant-late-target-reservation', 'mutant-rollback-foreign-hook',
    'mutant-backend-under-monitor', 'mutant-stale-method-signature',
]
LEVEL = 'Foundation actual production runtime + void stub Substrate; NOT real Substrate/UIKit/WeChat/device/PAC'


def replace_once(source, old, new):
    if source.count(old) != 1:
        raise ValueError('mutation anchor missing or ambiguous: ' + old)
    result = source.replace(old, new)
    if result == source:
        raise ValueError('unchanged mutation: ' + old)
    return result


def variants(runtime, policy):
    """Each compiled mutation must fail its specific behavioral assertion ID."""
    result = {'baseline': (runtime, policy, None, None)}

    def runtime_mutant(name, old, new, case, assertion):
        result[name] = (replace_once(runtime, old, new), policy, case, assertion)

    runtime_mutant('mutant-ignore-arity',
                   'if (actualCount < 2 || count != actualCount - 2) return NO;',
                   '(void)actualCount;', 'signatures', 'signature.arity')
    runtime_mutant('mutant-ignore-return',
                   'BOOL matches = WCKTypeMatches(type, returnType);',
                   'BOOL matches = (WCKTypeMatches(type, returnType), YES);',
                   'signatures', 'signature.return')
    runtime_mutant('mutant-ignore-argument',
                   'matches = WCKTypeMatches(type, arguments[i]);',
                   'matches = (WCKTypeMatches(type, arguments[i]), YES);',
                   'signatures', 'signature.argument')
    result['mutant-block-as-object'] = (
        runtime, replace_once(policy, 'return strcmp(actual, "@") == 0 ||',
                              "return actual[0] == '@' ||"),
        'block-object', 'signature.block-argument')
    runtime_mutant('mutant-assume-postcondition',
                   'BOOL directReplacement = WCKSameImplementation(current, replacement);',
                   'BOOL directReplacement = (WCKSameImplementation(current, replacement), YES);',
                   'backend-noop', 'postcondition.noop-rejected')
    runtime_mutant('mutant-raw-duplicate-original',
                   '*original = existing.nextImplementation;',
                   '*original = method_getImplementation(class_getInstanceMethod(cls, selector));',
                   'idempotent-owner', 'idempotent.saved-next')
    runtime_mutant('mutant-discard-backend-trampoline',
                   'record.nextImplementation = candidate;\n            *original = candidate;',
                   'record.nextImplementation = fallback;\n            *original = fallback;',
                   'install-trampoline', 'original.trampoline-retained')
    runtime_mutant('mutant-alias-live-original', '&record->backendOriginal', 'original',
                   'backend-null-inflight', 'original.callable')
    runtime_mutant('mutant-repeat-quarantined-target', 'return existing.verified;',
                   '''if (!existing.verified) {
                WCKHookFunction retry = (WCKHookFunction)dlsym(RTLD_DEFAULT, "MSHookMessageEx");
                IMP ignored = NULL;
                if (retry) retry(cls, selector, replacement, &ignored);
            }
            return existing.verified;''',
                   'quarantine-repeat', 'quarantine.no-rehook')
    late = replace_once(runtime, 'sInstalled[key] = record;',
                        '// mutant: target is not reserved before entering foreign code')
    late = replace_once(late,
                        '@catch (__unused NSException *exception) { hookException = YES; }',
                        '@catch (__unused NSException *exception) { hookException = YES; }\n        sInstalled[key] = record;')
    result['mutant-late-target-reservation'] = (late, policy, 'reentrant-owner', 'reentry.backend-once')
    runtime_mutant('mutant-rollback-foreign-hook',
                   'BOOL directReplacement = WCKSameImplementation(current, replacement);',
                   '''BOOL directReplacement = WCKSameImplementation(current, replacement);
        if (!directReplacement && installedMethod) method_setImplementation(installedMethod, fallback);''',
                   'foreign-postcondition', 'foreign.outer-retained')
    runtime_mutant('mutant-backend-under-monitor',
                   'hook(cls, selector, replacement, &record->backendOriginal);',
                   '@synchronized(sInstalled) { hook(cls, selector, replacement, &record->backendOriginal); }',
                   'cross-thread-owner', 'cross-thread.no-deadlock')
    runtime_mutant('mutant-stale-method-signature',
                   '''if (!WCKSignatureMatches(method, returnType, arguments, count))
            return WCKReportHookStatus(cls, selector, @"install_failed.signature_mismatch");''',
                   '// mutant: trust signature from before symbol resolution',
                   'fresh-method-signature', 'signature.fresh-method-check')
    if set(result) != {'baseline', *MUTANT_NAMES}:
        raise ValueError('incomplete mutant definitions')
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, help='JSON evidence, saved even on failure/skip')
    parser.add_argument('--source', type=Path, help='Runtime source candidate; defaults to actual src/WCKRuntime.m')
    parser.add_argument('--variant', choices=['baseline', *MUTANT_NAMES], help='Bounded one-variant run')
    parser.add_argument('--case', choices=CASES, help='One baseline case; incompatible with mutants')
    args = parser.parse_args(argv)
    if args.case and args.variant != 'baseline':
        parser.error('--case requires --variant baseline')
    root = Path(__file__).resolve().parents[1]
    output = args.output or root / 'evidence/native-runtime-installer-tests.json'
    source = (args.source or root / 'src/WCKRuntime.m').resolve()
    report = {
        'level': LEVEL, 'status': 'pending', 'complete': False,
        'executed': False, 'source': str(source), 'results': [],
        'selected_variant': args.variant, 'selected_case': args.case,
    }

    def save():
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')

    def fail(status, detail, code=1):
        report.update(status=status, detail=detail)
        save()
        print(status + ': ' + detail, file=sys.stderr, flush=True)
        return code

    if sys.platform != 'darwin':
        return fail('UNSUPPORTED_ENV', 'SKIP: requires macOS Foundation; no native case executed, NOT a passed test', 77)

    current = 'source loading'
    try:
        runtime = source.read_text(encoding='utf-8')
        policy = (root / 'src/WCKPolicy.c').read_text(encoding='utf-8')
        fixture = root / 'tests/WCKRuntimeInstallerRegression.m'
        report['source_sha256'] = hashlib.sha256(source.read_bytes()).hexdigest()
        report['policy_sha256'] = hashlib.sha256((root / 'src/WCKPolicy.c').read_bytes()).hexdigest()
        report['fixture_sha256'] = hashlib.sha256(fixture.read_bytes()).hexdigest()
        # Generate only requested mutations for a bounded baseline smoke run.
        selected = {'baseline': (runtime, policy, None, None)} if args.variant == 'baseline' else variants(runtime, policy)
        if args.variant:
            selected = {args.variant: selected[args.variant]}
        save()
        with tempfile.TemporaryDirectory(prefix='wck-runtime-installer-') as temporary:
            td = Path(temporary)
            common = ['xcrun', '--sdk', 'macosx', 'clang', '-Wall', '-Wextra', '-Werror',
                      '-Wno-unused-parameter', '-I' + str(root / 'src')]
            report['compilations'] = []

            def compile_unit(unit, obj, extra=()):
                nonlocal current
                current = 'compile ' + unit.name
                cmd = common + list(extra)
                cmd += ['-fobjc-arc', '-fblocks'] if unit.suffix == '.m' else ['-std=c11']
                cmd += ['-c', str(unit), '-o', str(obj)]
                run = subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=90)
                report['compilations'].append({'unit':unit.name, 'command':cmd, 'exit':run.returncode, 'stderr':run.stderr})
                save()
                if run.returncode:
                    raise RuntimeError('COMPILE_FAILURE (not a caught mutant) ' + unit.name + '\n' + run.stderr)

            dependencies = []
            for name in ['WCKHostIdentity.m', 'WCKSettings.m', 'WCKSVGPalette.m', 'WCKAlbumSheet.m']:
                obj = td / (name + '.o')
                compile_unit(root / 'src' / name, obj)
                dependencies.append(obj)
            fixture_obj = td / 'fixture.o'
            compile_unit(fixture, fixture_obj, ['-Wno-nonnull'])
            dependencies.append(fixture_obj)

            for name, (runtime_body, policy_body, killer_case, assertion) in selected.items():
                folder = td / name
                folder.mkdir()
                runtime_path, policy_path = folder / 'WCKRuntime.m', folder / 'WCKPolicy.c'
                runtime_path.write_text(runtime_body, encoding='utf-8')
                policy_path.write_text(policy_body, encoding='utf-8')
                runtime_obj, policy_obj = folder / 'runtime.o', folder / 'policy.o'
                row = {'variant':name, 'compiled':False, 'executed':False, 'killer':killer_case,
                       'assertion':assertion, 'cases':[], 'expected':False}
                report['results'].append(row)
                save()
                compile_unit(runtime_path, runtime_obj, ['-Ddlsym=WCKRuntimeTestDlsym'])
                compile_unit(policy_path, policy_obj)
                exe = folder / 'runtime-regression'
                cmd = common + [str(runtime_obj), str(policy_obj), *map(str, dependencies), '-framework', 'Foundation', '-o', str(exe)]
                current = 'link ' + name
                link = subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=90)
                report['compilations'].append({'unit':name + ' link', 'command':cmd, 'exit':link.returncode, 'stderr':link.stderr})
                save()
                if link.returncode:
                    raise RuntimeError('LINK_FAILURE (not a caught mutant) ' + name + '\n' + link.stderr)
                row['compiled'] = True
                save()
                cases = [killer_case] if killer_case else [args.case] if args.case else CASES
                for case in cases:
                    current = name + '/' + case
                    home = folder / ('runtime-' + case)
                    home.mkdir()
                    env = dict(os.environ, HOME=str(home))
                    run = subprocess.run([str(exe), case], env=env, capture_output=True, text=True,
                                         encoding='utf-8', errors='replace', timeout=25)
                    expected_marker = 'RUNTIME ASSERT[' + assertion + ']' if assertion else 'RUNTIME CASE ' + case + ' PASS'
                    good = (run.returncode == 86 and expected_marker in run.stderr) if assertion else (
                        run.returncode == 0 and expected_marker in run.stdout)
                    row['cases'].append({'case':case, 'exit':run.returncode, 'expected':good,
                                         'stdout':run.stdout, 'stderr':run.stderr})
                    report['executed'] = True
                    save()
                    print(name, case, 'NAMED ASSERTION CAUGHT' if good and assertion else 'PASS' if good else 'FAIL', flush=True)
                    if not good:
                        raise RuntimeError('ASSERTION_MISMATCH ' + current + '\n' + run.stdout + '\n' + run.stderr)
                row['executed'] = True
                row['expected'] = True
                save()
            report.update(status='PASS_FOUNDATION_RUNTIME_STUB_SUBSTRATE', complete=True)
            save()
            print(report['status'] + ' (' + str(len(report['results'])) + ' compiled variants)', flush=True)
            return 0
    except subprocess.TimeoutExpired:
        return fail('TIMEOUT', current + '; no arbitrary failure counted as a caught mutant', 124)
    except (OSError, ValueError, RuntimeError) as error:
        return fail('FAILED', current + ': ' + str(error), 1)


if __name__ == '__main__':
    raise SystemExit(main())
