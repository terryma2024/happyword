"""Unit tests for Android parity_scout adapter helpers."""

from unittest.mock import patch

from parity_scout.adapters.android import _adb_cmd, _parse_adb_devices, _single_online_serial


def test_parse_adb_devices_filters_offline_and_header():
    raw = """List of devices attached
emulator-5554\toffline
emulator-5556\tdevice
"""
    assert _parse_adb_devices(raw) == ["emulator-5556"]


def test_parse_adb_devices_multiple_online():
    raw = """List of devices attached
emulator-5554\tdevice
emulator-5556\tdevice
"""
    assert _parse_adb_devices(raw) == ["emulator-5554", "emulator-5556"]


def test_single_online_serial_returns_none_for_zero_or_many():
    adb = "/fake/adb"
    with patch("parity_scout.adapters.android.subprocess.run") as run:
        run.return_value.returncode = 0
        run.return_value.stdout = "List of devices attached\n\n"
        assert _single_online_serial(adb) is None

    with patch("parity_scout.adapters.android.subprocess.run") as run:
        run.return_value.returncode = 0
        run.return_value.stdout = (
            "List of devices attached\n"
            "a\tdevice\n"
            "b\tdevice\n"
        )
        assert _single_online_serial(adb) is None


def test_single_online_serial_one_device():
    adb = "/fake/adb"
    with patch("parity_scout.adapters.android.subprocess.run") as run:
        run.return_value.returncode = 0
        run.return_value.stdout = (
            "List of devices attached\n"
            "emulator-5554\toffline\n"
            "emulator-5556\tdevice\n"
        )
        assert _single_online_serial(adb) == "emulator-5556"


def test_adb_cmd_prefers_android_serial(monkeypatch):
    monkeypatch.setenv("ANDROID_SERIAL", "from-env")
    cmd = _adb_cmd()
    assert cmd[:3] == [cmd[0], "-s", "from-env"]


def test_adb_cmd_uses_single_discovered_device(monkeypatch):
    monkeypatch.delenv("ANDROID_SERIAL", raising=False)
    with patch(
        "parity_scout.adapters.android._single_online_serial",
        return_value="emu-1",
    ):
        cmd = _adb_cmd()
    assert cmd[:3] == [cmd[0], "-s", "emu-1"]
