#!/usr/bin/env python3
"""Validate operational Terraform modules in temporary copies, without cloud access or downloads.

AWS (--lockfile, AWS 6.20.0) and Azure (--azure-lockfile, azurerm 4.81.0) are validated
independently; at least one must be selected. Each uses only the given local mirrors.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
IGNORE = shutil.ignore_patterns('.terraform', '*.tfstate*', '*.tfvars*', '*.tfplan', '*.log', '.env*', '__pycache__')

# cloud -> (top folder, lockfile pattern, provider label, targets, provider-free targets)
CLOUDS = {
    'aws': (
        'aws',
        rb'provider\s+"registry.terraform.io/hashicorp/aws"\s*\{\s*version\s*=\s*"6\.20\.0"',
        'AWS 6.20.0',
        lambda: sorted(p for p in (ROOT / 'aws/dev/eks/modules/aws').iterdir() if p.is_dir())
        + [ROOT / 'aws/dev/eks', ROOT / 'aws/dev/eks/modules/naming', ROOT / 'aws/dev/s3/modules/s3', ROOT / 'aws/dev/s3/bootstrap', ROOT / 'aws/dev/iam/modules/github-oidc'],
        {ROOT / 'aws/dev/eks/modules/naming'},
    ),
    'azure': (
        'azure',
        rb'provider\s+"registry.terraform.io/hashicorp/azurerm"\s*\{\s*version\s*=\s*"4\.81\.0"',
        'azurerm 4.81.0',
        lambda: sorted(p for p in (ROOT / 'azure/dev/aks/modules/azure').iterdir() if p.is_dir())
        + [ROOT / 'azure/dev/aks', ROOT / 'azure/dev/aks/modules/naming'],
        {ROOT / 'azure/dev/aks/modules/naming'},
    ),
}


def validate(cloud, binary, mirror, lock_bytes):
    folder, _pattern, _label, targets, provider_free = CLOUDS[cloud]
    with tempfile.TemporaryDirectory(prefix='platform-offline-validation-') as temporary:
        work = Path(temporary)
        shutil.copytree(ROOT / folder, work / folder, ignore=IGNORE)
        config = work / 'offline.tfrc'
        config.write_text('provider_installation {\n filesystem_mirror { path = ' + json.dumps(str(mirror)) + ' }\n}\ndisable_checkpoint = true\n')
        env = {k: v for k, v in os.environ.items() if not k.startswith(('AWS_', 'TF_', 'ARM_', 'AZURE_'))}
        env.update(TF_CLI_CONFIG_FILE=str(config), CHECKPOINT_DISABLE='1', AWS_EC2_METADATA_DISABLED='true', AWS_CONFIG_FILE=str(work / 'absent-config'), AWS_SHARED_CREDENTIALS_FILE=str(work / 'absent-credentials'), AZURE_CONFIG_DIR=str(work / 'absent-azure-config'))
        for target in targets():
            relative = target.relative_to(ROOT)
            directory = work / relative
            uses_provider = target not in provider_free
            copied_lock = directory / '.terraform.lock.hcl'
            if uses_provider:
                copied_lock.write_bytes(lock_bytes)
            for command in (['init', '-backend=false', '-input=false', '-lockfile=readonly', '-no-color'], ['validate', '-json']):
                result = subprocess.run([binary, f'-chdir={directory}', *command], env=env, text=True, capture_output=True, timeout=120)
                if result.returncode:
                    raise RuntimeError(f'{relative}: ' + result.stdout + result.stderr)
                if command[0] == 'validate':
                    status = json.loads(result.stdout)
                    if not status['valid']:
                        raise RuntimeError(f'{relative}: ' + result.stdout)
                    print(f'VALIDATE OK {relative}: {status["error_count"]} errors, {status["warning_count"]} warnings', flush=True)
            if uses_provider and copied_lock.read_bytes() != lock_bytes:
                raise RuntimeError('Validation unexpectedly changed a temporary dependency lockfile.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--terraform-bin', default=os.environ.get('TERRAFORM_BIN', 'terraform'))
    parser.add_argument('--provider-mirror', required=True, help='Existing local filesystem mirror; no registry fallback.')
    parser.add_argument('--lockfile', help='Existing reviewed lockfile selecting AWS 6.20.0; never updated.')
    parser.add_argument('--azure-provider-mirror', help='Existing local mirror for azurerm; defaults to --provider-mirror.')
    parser.add_argument('--azure-lockfile', help='Existing reviewed lockfile selecting azurerm 4.81.0; never updated.')
    args = parser.parse_args()
    if not args.lockfile and not args.azure_lockfile:
        parser.error('Select at least one cloud: --lockfile (AWS) and/or --azure-lockfile (Azure).')
    binary = shutil.which(args.terraform_bin)
    if not binary:
        parser.error('Terraform executable not found; select an already installed compatible binary.')
    selected = []
    for cloud, lockfile, mirror in (
        ('aws', args.lockfile, args.provider_mirror),
        ('azure', args.azure_lockfile, args.azure_provider_mirror or args.provider_mirror),
    ):
        if not lockfile:
            continue
        lock = Path(lockfile).resolve(strict=True)
        lock_bytes = lock.read_bytes()
        _folder, pattern, label, _targets, _free = CLOUDS[cloud]
        if not re.search(pattern, lock_bytes):
            parser.error(f'The existing reviewed lockfile must select {label}.')
        selected.append((cloud, Path(mirror).resolve(strict=True), lock, lock_bytes))
    for cloud, mirror, lock, lock_bytes in selected:
        validate(cloud, binary, mirror, lock_bytes)
        if hashlib.sha256(lock.read_bytes()).digest() != hashlib.sha256(lock_bytes).digest():
            raise RuntimeError('The input lockfile changed during validation.')


if __name__ == '__main__':
    main()
