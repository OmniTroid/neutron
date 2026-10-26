import importlib.machinery
import importlib.util
import unittest
from pathlib import Path

loader = importlib.machinery.SourceFileLoader("neutron", str(Path(__file__).parent.parent / "neutron"))
neutron = importlib.util.module_from_spec(importlib.util.spec_from_loader("neutron", loader))
loader.exec_module(neutron)

APP_INFO = r'''Connecting anonymously to Steam Public...OK
AppID : 12345, change number : 1/0, last change : Thu Jan  1 00:00:00 1970
"12345"
{
	"common"
	{
		"name"		"Test \"Game\""
		"oslist"		"windows,macos"
	}
	"config"
	{
		"installdir"		"Test Game"
		"launch"
		{
			"0"
			{
				"executable"		"TestGame.app"
				"type"		"default"
				"config"
				{
					"oslist"		"macos"
				}
			}
			"1"
			{
				"executable"		"bin\\win32\\game.exe"
				"type"		"default"
				"config"
				{
					"oslist"		"windows"
					"osarch"		"32"
				}
			}
			"2"
			{
				"executable"		"editor.exe"
				"type"		"editor"
			}
			"3"
			{
				"executable"		"bin\\win64\\game.exe"
				"arguments"		"-dx11 \"-name=a b\""
				"workingdir"		"bin\\win64"
				"config"
				{
					"oslist"		"windows"
					"osarch"		"64"
				}
			}
			"4"
			{
				"executable"		"beta.exe"
				"config"
				{
					"oslist"		"windows"
					"osarch"		"64"
					"betakey"		"beta"
				}
			}
		}
	}
}
Unloading Steam API...OK
'''


class AppInfoTest(unittest.TestCase):
    def parse(self):
        start = APP_INFO.index('"12345"')
        return neutron.parse_vdf(APP_INFO[start:])["12345"]

    def test_parse_vdf(self):
        info = self.parse()
        self.assertEqual(info["common"]["name"], 'Test "Game"')
        self.assertEqual(info["config"]["launch"]["1"]["executable"], "bin\\win32\\game.exe")

    def test_launch_entry_prefers_windows_64bit_default(self):
        entry = neutron.launch_entry(self.parse())
        self.assertEqual(entry["executable"], "bin\\win64\\game.exe")
        self.assertEqual(entry["workingdir"], "bin\\win64")

    def test_launch_entry_none_without_windows(self):
        info = self.parse()
        info["config"]["launch"] = {"0": info["config"]["launch"]["0"]}
        self.assertIsNone(neutron.launch_entry(info))

    def test_resolve_launch(self):
        import json
        import tempfile

        with tempfile.TemporaryDirectory() as tmp:
            neutron.LIBRARY = Path(tmp)
            (Path(tmp) / "12345").mkdir()
            (Path(tmp) / "12345" / "neutron-appinfo.json").write_text(json.dumps(self.parse()))
            exe, workdir, args = neutron.resolve_launch(12345)
            self.assertEqual(exe, Path(tmp) / "12345/bin/win64/game.exe")
            self.assertEqual(workdir, Path(tmp) / "12345/bin/win64")
            self.assertEqual(args, ["-dx11", "-name=a b"])


if __name__ == "__main__":
    unittest.main()
