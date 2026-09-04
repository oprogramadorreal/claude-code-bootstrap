"""Integration tests for the SessionStart command in hooks/hooks.json."""

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
HOOKS_PATH = REPO_ROOT / "hooks" / "hooks.json"


def _session_start_command():
    config = json.loads(HOOKS_PATH.read_text(encoding="utf-8"))
    return config["hooks"]["SessionStart"][0]["hooks"][0]["command"]


@pytest.mark.skipif(sys.platform != "win32", reason="Windows cmd.exe behavior")
def test_windows_launcher_uses_git_bash_when_bash_is_not_on_path(tmp_path):
    git = shutil.which("git")
    if git is None:
        pytest.skip("git is not installed")
    git_exec_path = subprocess.run(
        [git, "--exec-path"],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=True,
    ).stdout.strip()
    git_from_cmd = Path(git_exec_path).parents[2] / "cmd" / "git.exe"
    if not git_from_cmd.is_file():
        pytest.skip("git on PATH is not a Git for Windows install")

    env = os.environ.copy()
    windows_root = Path(env.get("SystemRoot", "C:/Windows"))
    env["PATH"] = os.pathsep.join(
        [str(git_from_cmd.parent), str(windows_root / "System32")]
    )
    assert shutil.which("git", path=env["PATH"]) is not None
    # System32 may hold WSL's bash.exe, which cannot open C:/ paths. The
    # launcher must recover from that too, so its presence is not asserted away.

    plugin_root = str(REPO_ROOT)
    env["PLUGIN_ROOT"] = plugin_root
    env["CLAUDE_PLUGIN_ROOT"] = plugin_root
    command = _session_start_command().replace(
        "${CLAUDE_PLUGIN_ROOT}", plugin_root.replace("\\", "/")
    )
    result = subprocess.run(
        command,
        shell=True,
        cwd=tmp_path,
        env=env,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=30,
    )

    assert result.returncode == 0, result.stderr
    assert "$optimus:init" in result.stdout
    assert "/optimus:<skill>" in result.stdout
    assert "$optimus:<skill>" in result.stdout
