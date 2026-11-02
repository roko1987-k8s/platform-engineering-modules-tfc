"""Execute the pure HCL naming module using console only, never plan/apply."""
from pathlib import Path
import copy
import json
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
POLICY = ROOT / 'naming/aws.json'
MODULE = ROOT / 'modules/naming'
BINARY = os.environ.get('TERRAFORM_BIN', 'terraform')


class AwsNaming(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='aws-naming-tests-')
        cls.work = Path(cls.temp.name)
        for source in MODULE.glob('*.tf'):
            shutil.copyfile(source, cls.work / source.name)
        cls.env = {k: v for k, v in os.environ.items() if not k.startswith(('AWS_', 'TF_VAR_', 'TF_CLI_ARGS', 'TF_DATA_DIR', 'TF_LOG'))}
        proc = subprocess.run([BINARY, f'-chdir={cls.work}', 'init', '-backend=false', '-input=false', '-no-color'], env=cls.env, text=True, capture_output=True, timeout=30)
        if proc.returncode:
            cls.temp.cleanup()
            raise AssertionError('Pure naming module initialization failed; use Terraform >=1.9: ' + proc.stderr)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def evaluate(self, changes=None, policy=None, negative=False):
        values = {'policy': policy if policy is not None else json.loads(POLICY.read_text()), 'region': 'us-east-1', 'environment': 'dev', 'team_id': 'D001', 'sequence': 1}
        values.update(changes or {})
        inputs = self.work / 'inputs.tfvars.json'
        inputs.write_text(json.dumps(values))
        # On invalid input, inspecting unavailable locals crashes Terraform 1.11.4.
        # A constant still triggers input validation; assert its diagnostics explicitly.
        expression = '1\n' if negative else 'jsonencode(local.names)\n'
        proc = subprocess.run([BINARY, f'-chdir={self.work}', 'console', '-no-color', f'-var-file={inputs}'], input=expression, text=True, capture_output=True, env=self.env, timeout=30)
        self.assertNotIn('TERRAFORM CRASH', proc.stderr)
        if negative:
            self.assertIn('Error: Invalid value for variable', proc.stderr)
            return None
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertNotIn('Error:', proc.stderr)
        return json.loads(json.loads(proc.stdout.strip()))

    def test_approved_d001_names(self):
        self.assertEqual(self.evaluate(), {'eks': 'eksue1d001dev01', 'vpc': 'vpcue1d001dev01', 'infra': 'infraue1d001dev01', 'user': 'userue1d001dev01'})

    def test_other_team_without_special_case(self):
        self.assertEqual(self.evaluate({'team_id': 'P001'})['eks'], 'eksue1p001dev01')
        self.assertEqual(self.evaluate({'team_id': 'D002'})['infra'], 'infraue1d002dev01')
        self.assertNotRegex((MODULE / 'main.tf').read_text(), r'D001|d001|P001|p001')

    def test_existing_environment_codes(self):
        for environment in ['cert', 'prod']:
            with self.subTest(environment=environment):
                self.assertEqual(self.evaluate({'environment': environment})['eks'], f'eksue1d001{environment}01')

    def test_padding_does_not_truncate_or_collide(self):
        names = [self.evaluate({'sequence': sequence})['eks'] for sequence in [1, 2, 10, 100]]
        self.assertEqual(names, ['eksue1d001dev01', 'eksue1d001dev02', 'eksue1d001dev10', 'eksue1d001dev100'])
        self.assertEqual(len(set(names)), 4)

    def test_unknown_codes_fail_closed(self):
        for delta in [{'region': 'unknown'}, {'region': 'ue1'}, {'environment': 'unknown'}, {'environment': 'DEV'}]:
            with self.subTest(delta=delta):
                self.evaluate(delta, negative=True)

    def test_invalid_team_rejected(self):
        for team in ['d001', ' D001', 'D001 ', 'D-001', 'D00', 'D001/', 'D001dev']:
            with self.subTest(team=team):
                self.evaluate({'team_id': team}, negative=True)

    def test_invalid_sequence_rejected(self):
        for sequence in [0, -1, 1.5]:
            with self.subTest(sequence=sequence):
                self.evaluate({'sequence': sequence}, negative=True)

    def test_invalid_or_ambiguous_policy_rejected(self):
        policy = json.loads(POLICY.read_text())
        mutations = [lambda p: p.update(schema_version=2), lambda p: p.update(sequence_width=0), lambda p: p['region_codes'].update({'synthetic-region': 'ue1'}), lambda p: p['resource_prefixes'].update(eks='UPPER'), lambda p: p['resource_prefixes'].pop('user'), lambda p: p['environment_codes'].update({'synthetic-env': 'dev'})]
        for mutate in mutations:
            data = copy.deepcopy(policy)
            mutate(data)
            with self.subTest(policy=data):
                self.evaluate(policy=data, negative=True)

    def test_no_providers_resources_or_data_sources(self):
        source = '\n'.join(p.read_text() for p in MODULE.glob('*.tf'))
        self.assertNotRegex(source, r'\b(resource|provider|data)\s+"')

    def test_draft_security_and_networking_unchanged(self):
        draft = (ROOT / 'templates/eks/D001-System-S-User-M.main.tf.example').read_text()
        self.assertRegex(draft, r'name\s*=\s*module.naming.names.eks')
        self.assertIn('NETWORKING_PENDING', draft)
        self.assertRegex(draft, r'conformity\s*=\s*"pending"')
        self.assertRegex(draft, r'vpc_id\s*=\s*null')
        self.assertIn('local.networking_ready ? 1 : 0', draft)


if __name__ == '__main__':
    unittest.main()
