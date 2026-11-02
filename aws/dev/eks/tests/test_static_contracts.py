"""Offline source checks; all deployment values remain outside these synthetic tests."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SourceBoundaries(unittest.TestCase):
    def test_resource_ownership(self):
        expected = {
            'eks': {'aws_eks_cluster', 'aws_cloudwatch_log_group'},
            'nodegroups': {'aws_eks_node_group', 'aws_launch_template'},
            'security-groups': {'aws_security_group', 'aws_vpc_security_group_ingress_rule', 'aws_vpc_security_group_egress_rule'},
            'networking': {'terraform_data'},
            'iam': {'aws_iam_role', 'aws_iam_role_policy', 'aws_iam_role_policy_attachment'},
            'addons': {'aws_eks_addon'},
            'observability': {'terraform_data'},
        }
        for module, allowed in expected.items():
            text = '\n'.join(p.read_text() for p in (ROOT / 'modules/aws' / module).glob('*.tf'))
            self.assertEqual(set(re.findall(r'resource\s+"([^"]+)"', text)), allowed, module)
        for p in (ROOT / 'examples/composition').glob('*.tf'):
            self.assertLessEqual(set(re.findall(r'resource\s+"([^"]+)"', p.read_text())), {'terraform_data'})

    def test_no_execution_or_open_network(self):
        for p in ROOT.rglob('*.tf'):
            if '.terraform' in p.parts:
                continue
            text = p.read_text()
            for pattern in [r'provisioner\s+"', r'0\.0\.0\.0/0', r'::/0', r'ip_protocol\s*=\s*"-1"', r'provider\s+"kubernetes"', r'resource\s+"aws_(vpc|subnet|route|nat_gateway|internet_gateway)"']:
                self.assertNotRegex(text, pattern, str(p))
        sg = (ROOT / 'modules/aws/security-groups/main.tf').read_text()
        self.assertNotRegex(sg, r'\b(ingress|egress)\s*\{')

    def test_single_source_and_separate_ami_owner(self):
        for p in (ROOT / 'modules').rglob('*.tf'):
            text = p.read_text()
            self.assertNotRegex(text, r'"1\.36"|"us-east-1"|"m7i\.(large|xlarge|2xlarge)"')
        lt = (ROOT / 'modules/aws/nodegroups/launch-templates.tf').read_text()
        self.assertNotRegex(lt, re.compile(r'^\s*(image_id|user_data|iam_instance_profile|instance_type|subnet_id)\s*=', re.MULTILINE), '')
        self.assertIn('http_tokens', lt)
        self.assertIn('encrypted', lt)

    def test_only_mock_plan_runs(self):
        files = list((ROOT / 'tests').glob('*.tftest.hcl'))
        self.assertGreaterEqual(len(files), 8)
        for p in files:
            text = p.read_text()
            runs = len(re.findall(r'\brun\s+"', text))
            self.assertEqual(len(re.findall(r'command\s*=\s*plan\b', text)), runs, p.name)
            self.assertNotRegex(text, r'command\s*=\s*apply')
            if p.name != 'observability.tftest.hcl':
                self.assertIn('mock_provider "aws"', text, p.name)
        for p in (ROOT / 'tests/fixtures').glob('*.yaml'):
            self.assertIn('SYNTHETIC TEST ONLY', p.read_text())

    def test_documented_and_disabled(self):
        for module in (ROOT / 'modules/aws').iterdir():
            for filename in ['README.md', 'versions.tf', 'variables.tf', 'outputs.tf']:
                self.assertTrue((module / filename).is_file(), (module.name, filename))
        for p in ROOT.rglob('versions.tf'):
            if '.terraform' not in p.parts:
                self.assertIn('6.20.0', p.read_text())
        main = (ROOT / 'examples/composition/main.tf').read_text()
        self.assertIn('networking.conformity == "approved"', main)
        self.assertIn('filesha256(var.catalog_path) == var.catalog_sha256', main)
        self.assertIn('var.approvals.provisioning', main)


if __name__ == '__main__':
    unittest.main()
