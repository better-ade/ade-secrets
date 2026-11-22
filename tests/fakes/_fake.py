"""Shared by the python fakes: every call is logged (argv and the whole environment) to $FAKE_LOG, so a test can prove
no value travelled in an argument or an environment variable. State lives under $FAKE_STATE."""
import os, sys

STATE = os.environ.get("FAKE_STATE") or sys.exit("fake: FAKE_STATE is not set")


def log(tool):
    with open(os.environ["FAKE_LOG"], "a", encoding="utf-8", errors="backslashreplace") as f:
        f.write("CALL %s argv=%r\n" % (tool, sys.argv[1:]))
        for k in sorted(os.environ):
            f.write("  env %s=%s\n" % (k, os.environ[k]))


def path(*parts):
    p = os.path.join(STATE, *parts)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    return p
