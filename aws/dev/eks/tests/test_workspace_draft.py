"""Offline checks for the non-executable draft, without changing any base module."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
DRAFT = ROOT / 'templates/eks/D001-System-S-User-M.main.tf.example'


class WorkspaceDraft(unittest.TestCase):
    def test_all_module_instances_remain_gated(self):
        source = DRAFT.read_text()
        calls = re.findall(r'^module "([^"]+)" \{(.*?)^\}', source, re.S | re.M)
        self.assertEqual(len(calls), 8)
        for name, body in calls:
            if name == 'naming':
                self.assertNotIn('count', body)
                continue
            self.assertRegex(body, r'count\s*=\s*local.networking_ready \? 1 : 0', name)
            relative = re.search(r'source\s*=\s*"([^"]+)"', body).group(1)
            module_path = relative.split('//aws/dev/eks/')[1].split('?')[0]
            self.assertTrue((ROOT / module_path).is_dir(), name)
        self.assertEqual(re.findall(r'resource "([^"]+)"', source), ['terraform_data'])
        self.assertIn('NETWORKING_PENDING', source)
        self.assertNotRegex(source, r'\b(ingress|egress)\s*\{|\brules\s*=')

    def test_no_fake_segments_or_sizing(self):
        source = DRAFT.read_text()
        self.assertNotRegex(source, r'vpc-[0-9a-f]{8}|subnet-[0-9a-f]{8}|[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+')
        self.assertNotRegex(source, r'm7i\.|"1\.36"|"us-east-1"')
        self.assertRegex(source, r'requested_profiles\s*=\s*\{ "system" : "S", "user" : "M" \}')
        self.assertIn('networking.conformity == "approved"', source)
        self.assertIn('jsondecode(file(local.catalog_path))', source)


if __name__ == '__main__':
    unittest.main()
