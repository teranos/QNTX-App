import importlib.util
from pathlib import Path
import tempfile
import unittest
import yaml
import plistlib

spec = importlib.util.spec_from_file_location('share_project', Path(__file__).with_name('ios-share-project.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class ShareProjectTests(unittest.TestCase):
    def test_embed_signing_versions_and_existing_entitlements(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'original.entitlements').write_bytes(plistlib.dumps({'other': True}))
            path = root / 'project.yml'
            path.write_text(yaml.safe_dump({'targets': {'qntx_iOS': {'type': 'application', 'platform': 'iOS', 'settings': {'base': {'CODE_SIGN_ENTITLEMENTS': 'original.entitlements'}}, 'dependencies': [{'sdk': 'UIKit.framework'}]}}}))
            module.configure(path, '1.2.3', '1.2.3.42', 'TEAM', 'Share Profile')
            module.configure(path, '1.2.3', '1.2.3.42', 'TEAM', 'Share Profile')
            doc = yaml.safe_load(path.read_text())
            app = doc['targets']['qntx_iOS']
            self.assertTrue(app['entitlements']['properties']['other'])
            self.assertEqual(app['entitlements']['properties']['com.apple.security.application-groups'], [module.GROUP])
            self.assertEqual(len(app['dependencies']), 2)
            ext = doc['targets']['QNTXShare']
            self.assertEqual(ext['settings']['base']['CURRENT_PROJECT_VERSION'], '1.2.3.42')
            self.assertEqual(ext['settings']['base']['PROVISIONING_PROFILE_SPECIFIER'], 'Share Profile')
            self.assertEqual(ext['settings']['base']['PRODUCT_BUNDLE_IDENTIFIER'], module.BUNDLE)
            self.assertTrue((root / ext['sources'][0]['path']).exists())

    def test_missing_signing_fails_without_changing_project(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'project.yml'
            original = 'targets:\n  app:\n    type: application\n    platform: iOS\n'
            path.write_text(original)
            with self.assertRaises(ValueError):
                module.configure(path, '1', '1')
            self.assertEqual(path.read_text(), original)
            module.configure(path, '1', '1', unsigned=True)
            ext = yaml.safe_load(path.read_text())['targets']['QNTXShare']
            self.assertEqual(ext['settings']['base']['CODE_SIGNING_ALLOWED'], 'NO')

    def test_wrong_template_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'project.yml'
            path.write_text('targets: {}\n')
            with self.assertRaises(ValueError):
                module.configure(path, '1', '1', unsigned=True)

if __name__ == '__main__':
    unittest.main()
