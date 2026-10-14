import unittest
import zipfile
from pathlib import Path

from loguru import logger
logger.remove()
from androguard.core.axml import ARSCParser

from wx_patch import patch_arsc_typed

ROOT = Path(__file__).resolve().parents[1]
PKG = 'monet.com.tencent.mm'


def parse(data):
    arsc = ARSCParser(data)
    arsc._analyse()
    return arsc


class TypedResourcePatchTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with zipfile.ZipFile(ROOT / 'files' / 'MonetWeChat.apk') as apk:
            cls.original = apk.read('resources.arsc')
        cls.before = parse(cls.original)

    def patch(self, renames):
        patched, _, _ = patch_arsc_typed(self.original, {PKG: renames})
        return parse(patched)

    def test_shared_key_in_other_resource_type_is_preserved(self):
        after = self.patch({'color/b': 'color/test_renamed_b'})
        before_names = self.before.resource_keys[PKG]
        after_names = after.resource_keys[PKG]
        self.assertEqual(before_names['color']['b'], after_names['color']['test_renamed_b'])
        self.assertNotIn('b', after_names['color'])
        self.assertEqual(before_names['mipmap']['b'], after_names['mipmap']['b'])
        # Every configuration keeps its value and reference IDs.
        def values(arsc):
            return {(rid, str(cfg)): (entry.key.data_type, entry.key.data)
                    for rid, configs in arsc.resource_values.items()
                    for cfg, entry in configs.items()}
        self.assertEqual(values(self.before), values(after))

    def test_renames_can_swap_existing_keys(self):
        after = self.patch({'color/b': 'color/j', 'color/j': 'color/b'})
        names = after.resource_keys[PKG]['color']
        self.assertEqual(self.before.resource_keys[PKG]['color']['b'], names['j'])
        self.assertEqual(self.before.resource_keys[PKG]['color']['j'], names['b'])

    def test_duplicate_target_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'Duplicate mapped resource'):
            self.patch({'color/b': 'color/j'})


if __name__ == '__main__':
    unittest.main()
