#!/usr/bin/env python3
"""Offline validation of the S3 backend IAM modules (access + foundation).

Everything runs in a disposable copy created with the tempfile API:
- fmt, init (backend=false, readonly lock, filesystem mirror) and validate;
- `terraform test` with a mocked AWS provider (`command = plan`);
- extraction of the generated IAM documents with `terraform console` and an
  offline, SIMPLIFIED IAM evaluation (inline policy AND boundary, explicit deny
  wins, trust conditions) of cross-workspace / cross-team access.

No provider registry, backend, AWS credential chain, network or real apply: AWS
config/credentials are hidden, the provider block of the copy skips every AWS
call and HTTP(S) proxies point to a closed loopback port. The offline evaluation
never replaces a later authorized verification in AWS.
"""
import argparse
import copy
import fnmatch
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
ACCESS = Path('aws/dev/iam/modules/s3-backend-access')
FOUNDATION = Path('aws/dev/iam/modules/s3-backend-foundation')
ACCOUNT = '123456789012'  # synthetic, offline only
AGENT = f'arn:aws:iam::{ACCOUNT}:user/adp-agent-dev'
OPS = {'inspect': 'inspect', 'bootstrap': 'bootstrap', 'state_read': 'state-read', 'state_write': 'state-write'}
BOUNDARY = f'arn:aws:iam::{ACCOUNT}:policy/adp/s3-backend/boundary/adp-s3-backend-{{}}-boundary'
MATRIX = (('P001', 1), ('P001', 2), ('D001', 1))
OFFLINE_PROVIDER = '''provider "aws" {
  region                      = "us-east-1"
  access_key                  = "offline"
  secret_key                  = "offline"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}
'''


def bucket(team, seq):
    return f's3ue1{team.lower()}dev{seq:02d}'


def access_vars(team='P001', seq=1):
    wid = f'eks-{seq:02d}'
    return dict(
        authorized_team_id=team,
        workspace=dict(id=wid, team_id=team, application_code='adp-eks', environment='dev',
                       region='us-east-1', sequence=seq,
                       source=dict(repository='roko1987-k8s/platform-engineering-devs', commit='a' * 40,
                                   path=f'workspaces/{team}/terraform/aws/dev/{wid}/main.tf')),
        backend=dict(account_id=ACCOUNT, region='us-east-1', environment='dev',
                     assignment_revision='b' * 64, approval_reference='offline-only'),
        foundation=dict(agent_principal_arn=AGENT,
                        boundary_arns={k: BOUNDARY.format(op) for k, op in OPS.items()},
                        revision='c' * 64, approval_reference='offline-only'))


def foundation_vars():
    return dict(account_id=ACCOUNT, region='us-east-1', environment='dev', agent_principal_arn=AGENT,
                approval=dict(revision='d' * 64, reference='offline-only'))


# ---------------------------------------------------------------- terraform test files

def _run_block(name, variables, assertions=(), failures=()):
    parts = [f'run "{name}" {{\n command = plan\n variables {{']
    for key, value in variables.items():
        parts.append(f'{key} = jsondecode({json.dumps(json.dumps(value))})')
    parts.append('}')
    if failures:
        parts.append('expect_failures = [' + ','.join(failures) + ']')
    for expression in assertions:
        parts.append('assert {\ncondition = ' + expression + '\nerror_message = ' +
                     json.dumps(name + ': offline security invariant failed') + '\n}')
    parts.append('}')
    return '\n'.join(parts)


def access_tests():
    parts, counts = ['mock_provider "aws" {}'], [0, 0]
    for team, seq in (*MATRIX, ('P001', 99)):
        wid, b = f'eks-{seq:02d}', bucket(team, seq)
        state = f'states/{team}/aws/dev/{wid}/terraform.tfstate'
        arn = f'arn:aws:s3:::{b}'
        checks = [f'output.resolved.bucket == "{b}"', f'output.resolved.state_key == "{state}"',
                  f'output.resolved.lock_key == "{state}.tflock"', 'length(aws_iam_role.this) == 4',
                  'length(aws_iam_role_policy.this) == 4']
        for key, op in OPS.items():
            role, policy = f'aws_iam_role.this["{key}"]', f'jsondecode(output.policies["{key}"])'
            trust = f'jsondecode({role}.assume_role_policy).Statement[0]'
            tagst = f'[for s in jsondecode({role}.assume_role_policy).Statement : s if s.Sid == "TagWorkspaceSession"][0]'
            checks += [
                f'{role}.name == "{b}-s3backend-{op}"',
                f'{role}.path == "/adp/s3-backend/{op}/"',
                f'{role}.permissions_boundary == "{BOUNDARY.format(op)}"',
                f'{role}.max_session_duration == 3600',
                f'{role}.tags.Bucket == "{b}" && {role}.tags.Team == "{team}" && {role}.tags.Instance == "{wid}" && {role}.tags.Operation == "{op}"',
                f'{trust}.Principal.AWS == "{AGENT}"',
                f'{tagst}.Condition.StringEquals["aws:RequestTag/Instance"] == "{wid}"',
                f'{tagst}.Condition.StringEquals["aws:RequestTag/Team"] == "{team}"',
                f'{tagst}.Condition.StringEquals["aws:RequestTag/Operation"] == "{op}"',
                f'contains({trust}.Action, "sts:SetSourceIdentity") && !contains(flatten([{tagst}.Action]), "sts:SetSourceIdentity")',
                f'{trust}.Condition.Null["sts:SourceIdentity"] == "false"',
                f'[for s in jsondecode({role}.assume_role_policy).Statement : s if s.Sid == "RequireSessionName"][0].Condition.StringNotLike["sts:RoleSessionName"] == "adp-{team}-{wid}-{op}*"',
                f'keys({trust}.Condition) == ["Null"]',
                f'alltrue([for s in {policy}.Statement : length(regexall("\\\\*", jsonencode(s.Resource))) == 0 if s.Effect == "Allow"])',
                f'alltrue([for s in {policy}.Statement : alltrue([for a in flatten([s.Action]) : !strcontains(a, "*")]) if s.Effect == "Allow"])',
                f'anytrue([for s in {policy}.Statement : s.Effect == "Deny" && s.Action == "s3:*"])',
                f'alltrue([for s in {policy}.Statement : !contains(flatten([s.Action]), "s3:DeleteBucket") if s.Effect == "Allow"])',
            ]
        checks.append(f'jsondecode(output.policies["state_read"]).Statement[4].Resource == "{arn}/{state}"')
        checks.append(f'toset(jsondecode(output.policies["state_read"]).Statement[4].Action) == toset(["s3:GetObject"])')
        checks.append(f'toset(jsondecode(output.policies["state_write"]).Statement[4].Action) == toset(["s3:GetObject", "s3:PutObject"])')
        checks.append(f'jsondecode(output.policies["state_read"]).Statement[3].Condition.StringEquals["s3:if-none-match"] == "*"')
        checks.append(f'jsondecode(output.policies["state_write"]).Statement[2].Resource == "{arn}/{state}.tflock"')
        parts.append(_run_block(f'scope_{team.lower()}_{wid}', access_vars(team, seq), checks))
        counts[0] += 1
        counts[1] += len(checks)

    def reject(name, edit, failure):
        values = copy.deepcopy(access_vars())
        edit(values)
        parts.append(_run_block(name, values, failures=[failure]))
        counts[0] += 1

    reject('cross_team', lambda v: v['workspace'].update(team_id='D001'), 'aws_iam_role.this')
    reject('cross_path', lambda v: v['workspace']['source'].update(path='workspaces/D001/terraform/aws/dev/eks-01/main.tf'), 'aws_iam_role.this')
    reject('other_workspace_path', lambda v: v['workspace']['source'].update(path='workspaces/P001/terraform/aws/dev/eks-02/main.tf'), 'aws_iam_role.this')
    reject('wrong_sequence', lambda v: v['workspace'].update(sequence=2), 'aws_iam_role.this')
    reject('region_mismatch', lambda v: v['backend'].update(region='us-west-2'), 'aws_iam_role.this')
    reject('wrong_account', lambda v: v['foundation'].update(agent_principal_arn='arn:aws:iam::999999999999:user/adp-agent-dev'), 'aws_iam_role.this')
    reject('wrong_boundary', lambda v: v['foundation']['boundary_arns'].update(state_write='arn:aws:iam::123456789012:policy/AdministratorAccess'), 'aws_iam_role.this')
    reject('swapped_boundary', lambda v: v['foundation']['boundary_arns'].update(inspect=BOUNDARY.format('bootstrap')), 'aws_iam_role.this')
    reject('role_principal', lambda v: v['foundation'].update(agent_principal_arn=f'arn:aws:iam::{ACCOUNT}:role/adp-agent-dev'), 'var.foundation')
    reject('other_user', lambda v: v['foundation'].update(agent_principal_arn=f'arn:aws:iam::{ACCOUNT}:user/someone'), 'var.foundation')
    reject('root_trust', lambda v: v['foundation'].update(agent_principal_arn=f'arn:aws:iam::{ACCOUNT}:root'), 'var.foundation')
    reject('branch_not_commit', lambda v: v['workspace']['source'].update(commit='main'), 'var.workspace')
    reject('unapproved_repository', lambda v: v['workspace']['source'].update(repository='other/workspaces'), 'var.workspace')
    reject('bad_workspace_id', lambda v: v['workspace'].update(id='eks-1'), 'var.workspace')
    return '\n'.join(parts), counts


def foundation_tests():
    parts, counts = ['mock_provider "aws" {}'], [0, 0]
    checks = ['length(aws_iam_policy.boundary) == 4', 'aws_iam_role.control.path == "/adp/control/"',
              'aws_iam_role.control.name == "adp-s3-backend-control"',
              f'jsondecode(aws_iam_role.control.assume_role_policy).Statement[0].Principal.AWS == "{AGENT}"',
              'jsondecode(aws_iam_role.control.assume_role_policy).Statement[0].Condition.Null["sts:SourceIdentity"] == "false"',
              'anytrue([for s in jsondecode(output.control.policy).Statement : s.Sid == "OnlyTheWorkspaceNamespace" && s.Effect == "Deny"])',
              'anytrue([for s in jsondecode(output.control.policy).Statement : s.Effect == "Deny" && contains(flatten([s.Action]), "iam:PassRole")])',
              'anytrue([for s in jsondecode(output.control.policy).Statement : s.Effect == "Deny" && contains(flatten([s.Action]), "iam:UpdateAssumeRolePolicy")])',
              'alltrue([for s in jsondecode(output.control.policy).Statement : !contains(flatten([s.Action]), "iam:*") if s.Effect == "Allow"])',
              f'jsondecode(output.agent_identity_policy).Statement[0].Resource[0] == "arn:aws:iam::{ACCOUNT}:role/adp/control/adp-s3-backend-control"']
    for key, op in OPS.items():
        checks += [f'aws_iam_policy.boundary["{key}"].name == "adp-s3-backend-{op}-boundary"',
                   f'aws_iam_policy.boundary["{key}"].path == "/adp/s3-backend/boundary/"',
                   f'output.boundaries["{key}"].arn == "{BOUNDARY.format(op)}"',
                   f'strcontains(output.boundaries["{key}"].document, "$${{aws:PrincipalTag/Bucket}}")',
                   f'anytrue([for s in jsondecode(output.boundaries["{key}"].document).Statement : s.Effect == "Deny" && s.Action == "s3:*"])']
    parts.append(_run_block('foundation', foundation_vars(), checks))
    counts[0] += 1
    counts[1] += len(checks)
    for name, edit, failure in (
        ('role_principal', lambda v: v.update(agent_principal_arn=f'arn:aws:iam::{ACCOUNT}:role/adp-agent-dev'), 'var.agent_principal_arn'),
        ('unknown_region', lambda v: v.update(region='eu-west-1'), 'aws_iam_policy.boundary'),
        ('account_mismatch', lambda v: v.update(account_id='999999999999'), 'aws_iam_policy.boundary'),
        ('no_approval', lambda v: v['approval'].update(revision='main'), 'var.approval'),
    ):
        values = copy.deepcopy(foundation_vars())
        edit(values)
        parts.append(_run_block(name, values, failures=[failure]))
        counts[0] += 1
    return '\n'.join(parts), counts


# ---------------------------------------------------------------- simplified IAM evaluation

def _as_list(value):
    return value if isinstance(value, list) else [value]


def _subst(pattern, tags):
    def repl(match):
        key = match.group(1)
        if key not in tags:
            raise KeyError(key)
        return tags[key]
    return re.sub(r'\$\{aws:PrincipalTag/([A-Za-z]+)\}', repl, pattern)


def _match(patterns, value, tags, case=False):
    for pattern in _as_list(patterns):
        try:
            pattern = _subst(pattern, tags)
        except KeyError:
            continue  # unresolved policy variable: never matches
        if fnmatch.fnmatchcase(value.lower() if case else value, pattern.lower() if case else pattern):
            return True
    return False


def _condition(block, ctx):
    for operator, entries in (block or {}).items():
        for key, expected in entries.items():
            present = key in ctx
            actual = ctx.get(key)
            if operator == 'Null':
                if (expected == 'true') != (not present):
                    return False
                continue
            if operator.endswith('IfExists') and not present:
                continue
            base = operator.replace('IfExists', '')
            if base.startswith('ForAllValues:'):
                if present and not set(_as_list(actual)) <= set(_as_list(expected)):
                    return False
                continue
            if base.startswith('ForAnyValue:'):
                if not present or not set(_as_list(actual)) & set(_as_list(expected)):
                    return False
                continue
            if base in ('StringNotEquals', 'StringNotLike'):
                # Negated operators match when the key is absent (IAM semantics).
                if present:
                    match = (lambda a, e: a == e) if base == 'StringNotEquals' else fnmatch.fnmatchcase
                    if any(match(a, e) for a in _as_list(actual) for e in _as_list(expected)):
                        return False
                continue
            if not present:
                return False
            if base in ('StringEquals', 'ArnEquals'):
                if not any(a in _as_list(expected) for a in _as_list(actual)):
                    return False
            elif base in ('StringLike', 'ArnLike'):
                if not any(fnmatch.fnmatchcase(a, e) for a in _as_list(actual) for e in _as_list(expected)):
                    return False
            else:
                raise ValueError(f'unsupported condition operator {operator}')
    return True


def decide(document, action, resource, ctx, tags):
    allowed = False
    for s in document['Statement']:
        if not _match(s['Action'], action, tags, case=True):
            continue
        if 'Resource' in s and not _match(s['Resource'], resource, tags):
            continue
        if 'NotResource' in s and _match(s['NotResource'], resource, tags):
            continue
        if not _condition(s.get('Condition'), ctx):
            continue
        if s['Effect'] == 'Deny':
            return 'DENY'
        allowed = True
    return 'ALLOW' if allowed else 'IMPLICIT'


def effective(inline, boundary, action, resource, ctx, tags):
    a, b = decide(inline, action, resource, ctx, tags), decide(boundary, action, resource, ctx, tags)
    return a == 'ALLOW' and b == 'ALLOW'


def trust_allows(trust, principal, ctx):
    """One AssumeRole call is authorized per requested STS action: AssumeRole,
    plus TagSession when session tags are passed and SetSourceIdentity when a
    SourceIdentity is passed. Explicit Deny wins; otherwise an Allow is needed."""
    actions = ['sts:AssumeRole']
    if any(k.startswith('aws:RequestTag/') for k in ctx) or 'aws:TagKeys' in ctx:
        actions.append('sts:TagSession')
    if 'sts:SourceIdentity' in ctx:
        actions.append('sts:SetSourceIdentity')
    for action in actions:
        # Conservative per-action request context (found in a real AssumeRole test):
        # SetSourceIdentity carries only sts:SourceIdentity, TagSession only the tag
        # keys; AssumeRole carries everything.
        if action == 'sts:SetSourceIdentity':
            view = {k: v for k, v in ctx.items() if k == 'sts:SourceIdentity'}
        elif action == 'sts:TagSession':
            view = {k: v for k, v in ctx.items()
                    if k.startswith('aws:RequestTag/') or k in ('aws:TagKeys', 'sts:TransitiveTagKeys')}
        else:
            view = ctx
        relevant = [s for s in trust['Statement']
                    if s['Principal'].get('AWS') == principal and action in _as_list(s['Action'])
                    and _condition(s.get('Condition'), view)]
        if any(s['Effect'] == 'Deny' for s in relevant) or not any(s['Effect'] == 'Allow' for s in relevant):
            return False
    return True


INSPECT = ['s3:GetBucketLocation', 's3:GetBucketOwnershipControls', 's3:GetBucketPolicy',
           's3:GetBucketPublicAccessBlock', 's3:GetBucketTagging', 's3:GetBucketVersioning',
           's3:GetEncryptionConfiguration']
BUCKET_ACTIONS = INSPECT + ['s3:CreateBucket', 's3:DeleteBucket', 's3:PutBucketPolicy', 's3:PutBucketTagging',
                            's3:PutBucketVersioning', 's3:ListBucket', 's3:PutBucketAcl']
OBJECT_ACTIONS = ['s3:GetObject', 's3:PutObject', 's3:DeleteObject', 's3:DeleteObjectVersion']


def expected_allow(op, owner, target, action, key=None, prefix=None, region='us-east-1', conditional=True):
    (team, seq), (t_team, t_seq) = owner, target
    if (team, seq) != (t_team, t_seq):
        return False
    own_state = f'states/{team}/aws/dev/eks-{seq:02d}/terraform.tfstate'
    if key is None:  # bucket-level action
        if op == 'inspect':
            return action in INSPECT
        if op == 'bootstrap':
            return region == 'us-east-1' and action in BOOTSTRAP and action != 's3:DeleteBucket'
        if action == 's3:GetBucketLocation':
            return True
        if action == 's3:ListBucket':
            return prefix in (own_state, own_state + '.tflock')
        return False
    if op in ('inspect', 'bootstrap'):
        return False
    if key == own_state + '.tflock':
        return action in ('s3:GetObject', 's3:DeleteObject') or (action == 's3:PutObject' and conditional)
    if key == own_state:
        return action == 's3:GetObject' or (op == 'state-write' and action == 's3:PutObject')
    return False


BOOTSTRAP = ['s3:CreateBucket', 's3:GetAccelerateConfiguration', 's3:GetBucketAcl', 's3:GetBucketCORS',
             's3:GetBucketLocation', 's3:GetBucketLogging', 's3:GetBucketObjectLockConfiguration',
             's3:GetBucketOwnershipControls', 's3:GetBucketPolicy', 's3:GetBucketPublicAccessBlock',
             's3:GetBucketRequestPayment', 's3:GetBucketTagging', 's3:GetBucketVersioning', 's3:GetBucketWebsite',
             's3:GetEncryptionConfiguration', 's3:GetLifecycleConfiguration', 's3:GetReplicationConfiguration',
             's3:ListBucket', 's3:PutBucketOwnershipControls', 's3:PutBucketPolicy', 's3:PutBucketPublicAccessBlock',
             's3:PutBucketTagging', 's3:PutBucketVersioning', 's3:PutEncryptionConfiguration']


def evaluate(access_docs, foundation_docs):
    """Cross-workspace / cross-team matrix. Returns (checks, failures)."""
    boundaries = {k: json.loads(v['document']) for k, v in foundation_docs['boundaries'].items()}
    checks, failures = 0, []
    keys = [f'states/{t}/aws/dev/eks-{s:02d}/terraform.tfstate' for t, s in MATRIX]
    for owner in MATRIX:
        docs = access_docs[owner]
        team, seq = owner
        wid = f'eks-{seq:02d}'
        for k, op in OPS.items():
            inline = json.loads(docs['p'][k])
            trust = json.loads(docs['t'][k])
            tags = {'Team': team, 'Instance': wid, 'Bucket': bucket(team, seq), 'Operation': op}
            for target in MATRIX:
                b = bucket(*target)
                for region in ('us-east-1', 'us-west-2'):
                    for action in sorted(set(BUCKET_ACTIONS + BOOTSTRAP)):
                        prefixes = keys + [k2 + '.tflock' for k2 in keys] + [''] if action == 's3:ListBucket' else [None]
                        for prefix in prefixes:
                            ctx = {'aws:RequestedRegion': region, 'aws:SourceIdentity': '10001'}
                            if prefix is not None:
                                ctx['s3:prefix'] = prefix
                            got = effective(inline, boundaries[k], action, f'arn:aws:s3:::{b}', ctx, tags)
                            want = expected_allow(op, owner, target, action, prefix=prefix, region=region)
                            checks += 1
                            if got != want:
                                failures.append((owner, op, action, b, prefix, region, got))
                for key in keys + [k2 + '.tflock' for k2 in keys] + ['states/other/object']:
                    for action in OBJECT_ACTIONS:
                        for conditional in (True, False):
                            ctx = {'aws:RequestedRegion': 'us-east-1', 'aws:SourceIdentity': '10001'}
                            if conditional:
                                ctx['s3:if-none-match'] = '*'
                            got = effective(inline, boundaries[k], action, f'arn:aws:s3:::{b}/{key}', ctx, tags)
                            want = expected_allow(op, owner, target, action, key=key, conditional=conditional)
                            checks += 1
                            if got != want:
                                failures.append((owner, op, action, b, key, conditional, got))
            # No SourceIdentity: the boundary denies everything, even own resources.
            own = bucket(team, seq)
            for action, resource in (('s3:GetBucketTagging', f'arn:aws:s3:::{own}'),
                                     ('s3:GetObject', f'arn:aws:s3:::{own}/states/{team}/aws/dev/{wid}/terraform.tfstate')):
                checks += 1
                if effective(inline, boundaries[k], action, resource, {'aws:RequestedRegion': 'us-east-1'}, tags):
                    failures.append((owner, op, 'no-source-identity', action))
            for action, resource in (('iam:CreateRole', f'arn:aws:iam::{ACCOUNT}:role/x'), ('sts:AssumeRole', f'arn:aws:iam::{ACCOUNT}:role/x'),
                                     ('ec2:CreateVpc', '*'), ('kms:Decrypt', '*')):
                checks += 1
                if effective(inline, boundaries[k], action, resource, {}, tags):
                    failures.append((owner, op, action))
            # Trust: only adp-agent-dev with this exact workspace context.
            good = {'aws:RequestTag/Team': team, 'aws:RequestTag/Instance': wid, 'aws:RequestTag/Operation': op,
                    'aws:TagKeys': ['Team', 'Instance', 'Operation'], 'sts:SourceIdentity': '10001',
                    'sts:RoleSessionName': f'adp-{team}-{wid}-{op}'}
            cases = [(AGENT, good, True)]
            other_wid = 'eks-02' if wid == 'eks-01' else 'eks-01'
            for change in ({'aws:RequestTag/Instance': other_wid}, {'aws:RequestTag/Team': 'D002'},
                           {'aws:RequestTag/Operation': 'state-write' if op != 'state-write' else 'inspect'},
                           {'aws:TagKeys': ['Team', 'Instance', 'Operation', 'Extra']},
                           {'sts:RoleSessionName': f'adp-{team}-{other_wid}-{op}'},
                           {'sts:RoleSessionName': f'adp-{team}-{wid}-other'},
                           {'sts:TransitiveTagKeys': ['Team']}):
                cases.append((AGENT, {**good, **change}, False))
            cases.append((AGENT, {k2: v for k2, v in good.items() if k2 != 'sts:SourceIdentity'}, False))
            # No session tags at all: explicit Deny (tags are mandatory).
            cases.append((AGENT, {k2: v for k2, v in good.items() if not k2.startswith(('aws:RequestTag/', 'aws:TagKeys'))}, False))
            # One tag missing.
            cases.append((AGENT, {k2: v for k2, v in good.items() if k2 != 'aws:RequestTag/Operation'}, False))
            cases.append((f'arn:aws:iam::{ACCOUNT}:role/adp-agent-dev', good, False))
            cases.append((f'arn:aws:iam::{ACCOUNT}:user/someone', good, False))
            for principal, ctx, want in cases:
                checks += 1
                if trust_allows(trust, principal, ctx) != want:
                    failures.append((owner, op, 'trust', principal, sorted(ctx.items()), want))
    # Boundary alone (no inline): a role tagged for bucket A never reaches bucket B.
    for k, op in OPS.items():
        tags = {'Team': 'P001', 'Instance': 'eks-01', 'Bucket': 's3ue1p001dev01', 'Operation': op}
        for target in ('s3ue1p001dev02', 's3ue1d001dev01', 'unrelated-bucket'):
            for action in ('s3:GetBucketTagging', 's3:CreateBucket', 's3:ListBucket'):
                checks += 1
                if decide(boundaries[k], action, f'arn:aws:s3:::{target}', {'aws:RequestedRegion': 'us-east-1', 'aws:SourceIdentity': '10001'}, tags) == 'ALLOW':
                    failures.append(('boundary', op, action, target))
        checks += 1  # untagged role: nothing allowed
        if decide(boundaries[k], 's3:GetBucketLocation', 'arn:aws:s3:::s3ue1p001dev01', {'aws:SourceIdentity': '10001'}, {}) == 'ALLOW':
            failures.append(('boundary-untagged', op))
    # Control role.
    control = json.loads(foundation_docs['control']['policy'])
    ns = f'arn:aws:iam::{ACCOUNT}:role/adp/s3-backend'
    create_tags = {'aws:RequestTag/ManagedBy': 'Terraform', 'aws:RequestTag/Ownership': 's3-backend-access',
                   'aws:RequestTag/Team': 'P001', 'aws:RequestTag/Instance': 'eks-02', 'aws:RequestTag/Bucket': 's3ue1p001dev02',
                   'aws:TagKeys': ['ManagedBy', 'Ownership', 'Team', 'Instance', 'Bucket', 'Environment', 'Operation']}
    control_cases = []
    for k, op in OPS.items():
        role = f'{ns}/{op}/s3ue1p001dev02-s3backend-{op}'
        ok = {**create_tags, 'aws:RequestTag/Operation': op, 'iam:PermissionsBoundary': BOUNDARY.format(op)}
        other = 'bootstrap' if op != 'bootstrap' else 'inspect'
        control_cases += [
            ('iam:CreateRole', role, ok, True),
            ('iam:CreateRole', role, {**ok, 'iam:PermissionsBoundary': BOUNDARY.format(other)}, False),
            ('iam:CreateRole', role, {k2: v for k2, v in ok.items() if k2 != 'iam:PermissionsBoundary'}, False),
            ('iam:CreateRole', role, {k2: v for k2, v in ok.items() if k2 != 'aws:RequestTag/Bucket'}, False),
            ('iam:CreateRole', f'{ns}/{op}/s3ue1p001dev02-s3backend-{other}', ok, False),
            ('iam:CreateRole', role, {**ok, 'aws:RequestTag/Bucket': 'unrelated-bucket'}, False),
            ('iam:CreateRole', role, {**ok, 'aws:RequestTag/Team': 'X001'}, False),
            ('iam:CreateRole', role, {**ok, 'aws:RequestTag/Instance': 'aks-01'}, False),
            ('iam:PutRolePolicy', role, {}, True),
            ('iam:TagRole', role, {'aws:TagKeys': ['Bucket'], 'aws:ResourceTag/Bucket': 's3ue1p001dev02'}, False),
            ('iam:UntagRole', role, {'aws:TagKeys': ['Bucket']}, False),
            ('iam:UpdateAssumeRolePolicy', role, {}, False),
            ('iam:DeleteRole', role, {}, False),
            ('iam:PassRole', role, {}, False),
        ]
    control_cases += [
        ('iam:CreateRole', f'arn:aws:iam::{ACCOUNT}:role/adp/executor/eksue1p001dev01-tf-apply',
         {**create_tags, 'aws:RequestTag/Operation': 'inspect', 'iam:PermissionsBoundary': BOUNDARY.format('inspect')}, False),
        ('iam:PutRolePolicy', f'arn:aws:iam::{ACCOUNT}:role/adp/control/adp-s3-backend-control', {}, False),
        ('iam:CreatePolicyVersion', BOUNDARY.format('inspect'), {}, False),
        ('iam:GetPolicy', BOUNDARY.format('inspect'), {}, True),
        ('iam:CreateUser', f'arn:aws:iam::{ACCOUNT}:user/x', {}, False),
        ('iam:CreateAccessKey', AGENT, {}, False),
        ('s3:GetObject', 'arn:aws:s3:::s3ue1p001dev01/x', {}, False),
        ('sts:AssumeRole', f'{ns}/inspect/s3ue1p001dev01-s3backend-inspect', {}, False),
    ]
    for action, resource, ctx, want in control_cases:
        checks += 1
        if (decide(control, action, resource, ctx, {}) == 'ALLOW') != want:
            failures.append(('control', action, resource, want))
    # Known residual (TD-022): IAM cannot bind the Bucket tag to the role name nor
    # inspect the trust JSON at CreateRole. Reported, not hidden.
    residual = {**create_tags, 'aws:RequestTag/Operation': 'state-read', 'aws:RequestTag/Bucket': 's3ue1d001dev01',
                'iam:PermissionsBoundary': BOUNDARY.format('state-read')}
    if decide(control, 'iam:CreateRole', f'{ns}/state-read/s3ue1p001dev02-s3backend-state-read', residual, {}) == 'ALLOW':
        print('RESIDUAL (TD-022): control may create a correctly named role tagged for ANOTHER bucket, with any trust.')
    control_trust = json.loads(foundation_docs['control']['trust'])
    good = {'aws:RequestTag/Operation': 's3-backend-control', 'aws:TagKeys': ['Operation'],
            'sts:SourceIdentity': '10001', 'sts:RoleSessionName': 'adp-s3-backend-control'}
    for ctx, want in ((good, True),
                      ({k: v for k, v in good.items() if k != 'sts:SourceIdentity'}, False),
                      ({k: v for k, v in good.items() if not k.startswith(('aws:RequestTag/', 'aws:TagKeys'))}, False),
                      ({**good, 'aws:RequestTag/Operation': 'inspect'}, False),
                      ({**good, 'aws:TagKeys': ['Operation', 'Team']}, False),
                      ({**good, 'sts:RoleSessionName': 'adp-other'}, False),
                      ({**good, 'sts:TransitiveTagKeys': ['Operation']}, False)):
        checks += 1
        if trust_allows(control_trust, AGENT, ctx) != want:
            failures.append(('control-trust', sorted(ctx), want))
    checks += 1
    if trust_allows(control_trust, f'arn:aws:iam::{ACCOUNT}:user/someone', good):
        failures.append(('control-trust', 'other principal'))
    agent = json.loads(foundation_docs['agent'])
    for resource, want in ((f'{ns}/state-read/s3ue1p001dev02-s3backend-state-read', True),
                           (f'arn:aws:iam::{ACCOUNT}:role/adp/control/adp-s3-backend-control', True),
                           (f'arn:aws:iam::{ACCOUNT}:role/adp/executor/eksue1p001dev01-tf-apply', False),
                           (f'arn:aws:iam::{ACCOUNT}:role/OrganizationAccountAccessRole', False)):
        checks += 1
        if (decide(agent, 'sts:AssumeRole', resource, {}, {}) == 'ALLOW') != want:
            failures.append(('agent', resource, want))
    return checks, failures


# ---------------------------------------------------------------- orchestration

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--terraform-bin', required=True)
    parser.add_argument('--provider-mirror', required=True)
    parser.add_argument('--lockfile', required=True)
    parser.add_argument('--dump-documents', type=Path,
                        help='Optional directory to write the generated IAM documents (synthetic account) '
                             'for an external review such as IAM Access Analyzer.')
    args = parser.parse_args()
    binary = shutil.which(args.terraform_bin)
    if not binary:
        parser.error('Select an installed Terraform executable; nothing will be downloaded.')
    mirror = Path(args.provider_mirror).resolve(strict=True)
    lock = Path(args.lockfile).resolve(strict=True)
    lock_bytes = lock.read_bytes()
    if not re.search(rb'provider\s+"registry.terraform.io/hashicorp/aws"\s*\{\s*version\s*=\s*"6\.20\.0"', lock_bytes):
        parser.error('Supply an existing reviewed AWS 6.20.0 lockfile.')
    with tempfile.TemporaryDirectory(prefix='s3-backend-iam-offline-') as temporary:
        work = Path(temporary)
        shutil.copytree(ROOT / 'aws', work / 'aws', ignore=shutil.ignore_patterns(
            '.terraform', '*.tfstate*', '*.tfvars*', '*.tfplan', '*.log', '.env*', '__pycache__'))
        config = work / 'offline.tfrc'
        config.write_text('provider_installation {\n filesystem_mirror { path = ' + json.dumps(str(mirror)) +
                          ' }\n}\ndisable_checkpoint = true\n')
        env = {k: v for k, v in os.environ.items() if not k.startswith(('AWS_', 'TF_')) and 'PROXY' not in k.upper()}
        closed = 'http://127.0.0.1:9'  # any accidental network call fails locally
        env.update(HOME=str(work), TF_CLI_CONFIG_FILE=str(config), CHECKPOINT_DISABLE='1',
                   AWS_EC2_METADATA_DISABLED='true', AWS_CONFIG_FILE=str(work / 'absent-config'),
                   AWS_SHARED_CREDENTIALS_FILE=str(work / 'absent-credentials'),
                   HTTP_PROXY=closed, HTTPS_PROXY=closed, http_proxy=closed, https_proxy=closed, NO_PROXY='')

        def tf(directory, *command, stdin=None):
            result = subprocess.run([binary, f'-chdir={directory}', *command], env=env, input=stdin,
                                    capture_output=True, text=True, timeout=300)
            if result.returncode:
                raise RuntimeError(result.stdout + result.stderr)
            return result.stdout

        totals = [0, 0]
        for module, generate in ((ACCESS, access_tests), (FOUNDATION, foundation_tests)):
            directory = work / module
            (directory / '.terraform.lock.hcl').write_bytes(lock_bytes)
            tf(directory, 'fmt', '-check', '-recursive')
            tests = directory / 'tests'
            tests.mkdir()
            contents, counts = generate()
            (tests / 'security.tftest.hcl').write_text(contents)
            subprocess.run([binary, f'-chdir={tests}', 'fmt'], env=env, check=True, capture_output=True)
            tf(directory, 'init', '-backend=false', '-input=false', '-lockfile=readonly', '-no-color')
            tf(directory, 'validate', '-no-color')
            print(tf(directory, 'test', '-no-color').strip().splitlines()[-1], f'({module.name})', flush=True)
            totals[0] += counts[0]
            totals[1] += counts[1]
            example = directory / 'examples/offline'
            (example / '.terraform.lock.hcl').write_bytes(lock_bytes)
            tf(example, 'init', '-backend=false', '-input=false', '-lockfile=readonly', '-no-color')
            tf(example, 'validate', '-no-color')
            shutil.rmtree(tests)
            if (directory / '.terraform.lock.hcl').read_bytes() != lock_bytes:
                raise RuntimeError('Temporary dependency lock changed unexpectedly.')
            # Offline provider for console extraction only (copy, never the repository).
            (directory / 'zz_offline_provider_override.tf').write_text(OFFLINE_PROVIDER)
        print('EXAMPLES VALIDATE OK')

        def console(directory, variables, expression):
            path = directory / 'offline.auto.tfvars.json'
            path.write_text(json.dumps(variables))
            out = tf(directory, 'console', '-no-color', stdin=f'jsonencode({expression})\n')
            path.unlink()
            return json.loads(json.loads(out.strip()))

        access_docs = {owner: console(work / ACCESS, access_vars(*owner),
                                      '{p = local.policy_documents, t = local.trust_documents, n = local.role_names, b = local.bucket}')
                       for owner in MATRIX}
        names = [n for docs in access_docs.values() for n in docs['n'].values()]
        expected_buckets = {owner: bucket(*owner) for owner in MATRIX}
        if any(access_docs[o]['b'] != b for o, b in expected_buckets.items()) or len(set(names)) != 4 * len(MATRIX) \
                or any(not all(n.startswith(access_docs[o]['b'] + '-s3backend-') for n in access_docs[o]['n'].values()) for o in MATRIX):
            raise RuntimeError('Bucket per workspace / four exclusive roles per bucket violated.')
        print('COMPATIBILITY OK: ' + ', '.join(f'{t}/eks-{q:02d} -> {b}' for (t, q), b in expected_buckets.items())
              + f'; {len(set(names))} exclusive roles (4 per bucket).')
        foundation_docs = console(work / FOUNDATION, foundation_vars(),
                                  '{boundaries = {for k, v in local.boundary_documents : k => {document = v}}, '
                                  'control = {policy = local.control_policy, trust = local.control_trust}, '
                                  'agent = local.agent_identity_policy}')
        if args.dump_documents:
            out = args.dump_documents
            out.mkdir(parents=True, exist_ok=True)
            for (team, seq), docs in access_docs.items():
                for k in OPS:
                    (out / f'access-{team}-eks-{seq:02d}-{k}-trust.json').write_text(docs['t'][k])
                    (out / f'access-{team}-eks-{seq:02d}-{k}-policy.json').write_text(docs['p'][k])
            for k, v in foundation_docs['boundaries'].items():
                (out / f'foundation-boundary-{k}.json').write_text(v['document'])
            (out / 'foundation-control-trust.json').write_text(foundation_docs['control']['trust'])
            (out / 'foundation-control-policy.json').write_text(foundation_docs['control']['policy'])
            print(f'DOCUMENTS WRITTEN: {len(list(out.glob("*.json")))}')
        checks, failures = evaluate(access_docs, foundation_docs)
        if failures:
            for failure in failures[:20]:
                print('IAM EVALUATION FAILURE:', failure)
            raise RuntimeError(f'{len(failures)} offline IAM evaluation failures')
        print(f'OFFLINE IAM EVALUATION OK: {checks} decisions (simplified model; not a substitute for AWS).')
        print(f'OFFLINE OK: {totals[0]} mock plan runs, {totals[1]} assertions; no apply or AWS operations.')
    if hashlib.sha256(lock.read_bytes()).digest() != hashlib.sha256(lock_bytes).digest():
        raise RuntimeError('Input lockfile changed during validation.')


if __name__ == '__main__':
    main()
