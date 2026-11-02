"""Offline regression checks for the deliberately inactive deployment templates."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class SafetyTests(unittest.TestCase):
    def test_state_scope_and_deletion(self):
        policy = json.loads((ROOT / 'iam/state-D001-dev-eks-01.json').read_text())
        statements = policy['Statement']
        for statement in statements:
            self.assertNotIn('*', statement['Resource'])
            if 's3:DeleteObject' in statement['Action']:
                self.assertTrue(statement['Resource'].endswith('.tflock'))
        self.assertNotIn('s3:DeleteBucket', str(policy))

    def test_bootstrap_is_independent_and_protected(self):
        source = (ROOT / 'bootstrap/main.tf').read_text()
        self.assertIn('backend "local"', source)
        self.assertNotIn('backend "s3"', source)
        for requirement in ['prevent_destroy = true', 'force_destroy = false', 'AES256', 'Enabled', 'BucketOwnerEnforced', 'aws:SecureTransport']:
            self.assertIn(requirement, source)
        self.assertEqual(source.count('= "s3ue1p001dev01"'), 1)

    def test_no_untrusted_execution(self):
        for op in ['apply', 'destroy']:
            source = (ROOT / f'templates/{op}.yml.template').read_text()
            self.assertNotIn('pull_request', source)
            self.assertIn('exit 1', source)
            self.assertLess(source.index('exit 1'), source.index('aws-actions/configure'))
            self.assertIn('NETWORKING_APPROVED', source)
            self.assertIn('sha256sum -c approved.sha256', source)
            self.assertIn('test "$(cat approved.commit)" = "$GITHUB_SHA"', source)
            self.assertIn('needs: plan', source)
            self.assertIn(f'environment: D001-dev-eks-01-{op}', source)
            self.assertIn('terraform apply -input=false -lock-timeout=5m approved.tfplan', source)
        destroy = (ROOT / 'templates/destroy.yml.template').read_text()
        self.assertIn('terraform plan -destroy', destroy)
        self.assertIn('test "$CONFIRMATION"', destroy)
        validate = (ROOT / 'templates/validate.yml.template').read_text()
        self.assertNotIn('id-token:', validate)
        self.assertNotIn('configure-aws-credentials', validate)

    def test_validate_stays_static(self):
        source = (ROOT / 'templates/validate.yml.template').read_text()
        commands = [line.strip() for line in source.splitlines()]
        self.assertNotIn('terraform test', commands)
        self.assertIn('set -euo pipefail', commands)
        self.assertIn('terraform init -backend=false -input=false -lockfile=readonly', commands)
        self.assertFalse(any('NETWORKING_APPROVED' in line for line in commands))

    def test_backend_and_trust(self):
        backend = (ROOT / 'templates/backend.hcl').read_text()
        self.assertIn('use_lockfile         = true', backend)
        self.assertIn('states/D001/aws/dev/eks-01/terraform.tfstate', backend)
        trust = json.loads((ROOT / 'iam/trust.json.template').read_text())
        conditions = trust['Statement'][0]['Condition']['StringEquals']
        self.assertEqual(conditions['token.actions.githubusercontent.com:aud'], 'sts.amazonaws.com')
        self.assertEqual(conditions['token.actions.githubusercontent.com:sub'], '<EXACT_VERIFIED_ENVIRONMENT_SUBJECT>')

if __name__ == '__main__':
    unittest.main()
