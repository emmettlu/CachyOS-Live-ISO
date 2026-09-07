import os
from pathlib import Path
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]
SCRIPT = REPO / "archiso/airootfs/usr/local/bin/agentos-prepare-offline-kernels"


class OfflineKernelsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.config = self.root / "etc/vconsole.conf"
        self.config.parent.mkdir()
        self.live_hook = self.root / "etc/mkinitcpio.conf.d/archiso.conf"
        self.live_hook.parent.mkdir()
        self.live_hook.write_text("HOOKS=(archiso)\n")
        module = self.root / "usr/lib/modules/test-kernel"
        module.mkdir(parents=True)
        (module / "vmlinuz").write_bytes(b"test kernel")
        (module / "pkgbase").write_text("linux-cachyos\n")

    def run_helper(self):
        return subprocess.run(
            ["bash", str(SCRIPT)],
            env={**os.environ, "AGENTOS_OFFLINE_ROOT": str(self.root)},
            capture_output=True,
            text=True,
        )

    def test_chinese_layout_is_fixed_before_kernel_preparation(self):
        self.config.write_text('KEYMAP="cn"\nXKBLAYOUT=cn\nXKBMODEL=pc105\n')
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.config.read_text(), "KEYMAP=us\nXKBLAYOUT=cn\nXKBMODEL=pc105\n"
        )
        self.assertFalse(self.live_hook.exists())
        self.assertEqual(
            (self.root / "boot/vmlinuz-linux-cachyos").read_bytes(), b"test kernel"
        )
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.config.read_text().count("KEYMAP="), 1)

    def test_valid_non_us_layout_is_preserved(self):
        content = "# Keep the selected German layout.\nKEYMAP=de\nXKBLAYOUT=de\n"
        self.config.write_text(content)
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.config.read_text(), content)

    def test_invalid_keymaps_fail_before_mutation(self):
        for content in (
            "KEYMAP=agentos-no-such-keymap\n",
            "KEYMAP=cn\nXKBVARIANT=tib\n",
            "KEYMAP=us\nKEYMAP_TOGGLE=agentos-no-such-keymap\n",
        ):
            with self.subTest(content=content):
                self.config.write_text(content)
                result = self.run_helper()
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.config.read_text(), content)
                self.assertTrue(self.live_hook.exists())
                self.assertFalse((self.root / "boot").exists())

    def test_missing_config_uses_default(self):
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.config.exists())

    def test_kernel_keymap_is_preserved(self):
        self.config.write_text("KEYMAP=@kernel\n")
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.config.read_text(), "KEYMAP=@kernel\n")


if __name__ == "__main__":
    unittest.main()
