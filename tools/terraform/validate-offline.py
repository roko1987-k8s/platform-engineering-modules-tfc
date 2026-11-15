#!/usr/bin/env python3
"""Validate operational Terraform modules in temporary copies, without AWS or downloads."""
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--terraform-bin', default=os.environ.get('TERRAFORM_BIN', 'terraform'))
    parser.add_argument('--provider-mirror', required=True, help='Existing local filesystem mirror; no registry fallback.')
    parser.add_argument('--lockfile', required=True, help='Existing reviewed lockfile selecting AWS 6.20.0; never updated.')
    args = parser.parse_args()
    binary = shutil.which(args.terraform_bin)
    if not binary:
        parser.error('Terraform executable not found; select an already installed compatible binary.')
    mirror = Path(args.provider_mirror).resolve(strict=True)
    lock = Path(args.lockfile).resolve(strict=True)
    lock_bytes = lock.read_bytes()
    if not re.search(rb'provider\s+"registry.terraform.io/hashicorp/aws"\s*\{\s*version\s*=\s*"6\.20\.0"', lock_bytes):
        parser.error('The existing reviewed lockfile must select AWS 6.20.0.')
    targets = sorted(p for p in (ROOT / 'aws/dev/eks/modules/aws').iterdir() if p.is_dir())
    targets += [ROOT / 'aws/dev/eks', ROOT / 'aws/dev/eks/modules/naming', ROOT / 'aws/dev/s3/modules/s3', ROOT / 'aws/dev/s3/bootstrap', ROOT / 'aws/dev/iam/modules/github-oidc']
    with tempfile.TemporaryDirectory(prefix='platform-offline-validation-') as temporary:
        work = Path(temporary)
        shutil.copytree(ROOT / 'aws', work / 'aws', ignore=shutil.ignore_patterns('.terraform', '*.tfstate*', '*.tfvars*', '*.tfplan', '*.log', '.env*', '__pycache__'))
        config = work / 'offline.tfrc'
        config.write_text('provider_installation {\n filesystem_mirror { path = ' + json.dumps(str(mirror)) + ' }\n}\ndisable_checkpoint = true\n')
        env = {k: v for k, v in os.environ.items() if not k.startswith(('AWS_', 'TF_'))}
        env.update(TF_CLI_CONFIG_FILE=str(config), CHECKPOINT_DISABLE='1', AWS_EC2_METADATA_DISABLED='true', AWS_CONFIG_FILE=str(work / 'absent-config'), AWS_SHARED_CREDENTIALS_FILE=str(work / 'absent-credentials'))
        for target in targets:
            relative = target.relative_to(ROOT)
            directory = work / relative
            uses_aws = target != ROOT / 'aws/dev/eks/modules/naming'
            copied_lock = directory / '.terraform.lock.hcl'
            if uses_aws:
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
            if uses_aws and copied_lock.read_bytes() != lock_bytes:
                raise RuntimeError('Validation unexpectedly changed a temporary dependency lockfile.')
    if hashlib.sha256(lock.read_bytes()).digest() != hashlib.sha256(lock_bytes).digest():
        raise RuntimeError('The input lockfile changed during validation.')


if __name__ == '__main__':
    main()
