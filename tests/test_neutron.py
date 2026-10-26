import importlib.machinery
import importlib.util
import json
import struct
import tempfile
import unittest
from pathlib import Path

loader = importlib.machinery.SourceFileLoader("neutron", str(Path(__file__).parent.parent / "neutron"))
neutron = importlib.util.module_from_spec(importlib.util.spec_from_loader("neutron", loader))
loader.exec_module(neutron)

APP_INFO = {
    "appid": 12345,
    "common": {"name": "Test Game", "oslist": "windows,macos"},
    "config": {
        "installdir": "Test Game",
        "launch": {
            "0": {"executable": "TestGame.app", "type": "default", "config": {"oslist": "macos"}},
            "1": {"executable": "bin\\win32\\game.exe", "type": "default", "config": {"oslist": "windows", "osarch": "32"}},
            "2": {"executable": "editor.exe", "type": "editor"},
            "3": {
                "executable": "bin\\win64\\game.exe",
                "arguments": '-dx11 "-name=a b"',
                "workingdir": "bin\\win64",
                "config": {"oslist": "windows", "osarch": 64},
            },
            "4": {"executable": "beta.exe", "config": {"oslist": "windows", "osarch": "64", "betakey": "beta"}},
        },
    },
}


def encode_appinfo_v29(apps):
    strings = []

    def key(name):
        if name not in strings:
            strings.append(name)
        return struct.pack("<I", strings.index(name))

    def kv(obj):
        out = b""
        for k, v in obj.items():
            if isinstance(v, dict):
                out += b"\x00" + key(k) + kv(v)
            elif isinstance(v, int):
                out += b"\x02" + key(k) + struct.pack("<i", v)
            else:
                out += b"\x01" + key(k) + v.encode() + b"\0"
        return out + b"\x08"

    body = b""
    for appid, info in apps.items():
        data = b"\0" * 60 + kv({"appinfo": info})
        body += struct.pack("<II", appid, len(data)) + data
    body += struct.pack("<I", 0)
    table = struct.pack("<I", len(strings)) + b"".join(s.encode() + b"\0" for s in strings)
    return struct.pack("<IIq", 0x07564429, 1, 16 + len(body)) + body + table


class AppInfoTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / "appinfo.vdf"
        self.path.write_bytes(encode_appinfo_v29({10: {"appid": 10, "common": {"name": "Other"}}, 12345: APP_INFO}))

    def tearDown(self):
        self.tmp.cleanup()

    def test_read_appinfo(self):
        info = neutron.read_appinfo(12345, self.path)
        self.assertEqual(info, APP_INFO)
        self.assertIsNone(neutron.read_appinfo(999, self.path))

    def test_launch_entry_prefers_windows_64bit_default(self):
        entry = neutron.launch_entry(neutron.read_appinfo(12345, self.path))
        self.assertEqual(entry["executable"], "bin\\win64\\game.exe")

    def test_launch_entry_none_without_windows(self):
        info = neutron.read_appinfo(12345, self.path)
        info["config"]["launch"] = {"0": info["config"]["launch"]["0"]}
        self.assertIsNone(neutron.launch_entry(info))

    def test_resolve_launch(self):
        neutron.LIBRARY = Path(self.tmp.name)
        (Path(self.tmp.name) / "12345").mkdir()
        (Path(self.tmp.name) / "12345" / "neutron-appinfo.json").write_text(json.dumps(APP_INFO))
        exe, workdir, args = neutron.resolve_launch(12345)
        self.assertEqual(exe, Path(self.tmp.name) / "12345/bin/win64/game.exe")
        self.assertEqual(workdir, Path(self.tmp.name) / "12345/bin/win64")
        self.assertEqual(args, ["-dx11", "-name=a b"])


if __name__ == "__main__":
    unittest.main()
