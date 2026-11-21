#!/usr/bin/env python3
"""pty_run.py: run a command detached from the caller's process tree, like a user's own terminal would.

  pty_run.py [--no-pty] [--steps FILE] [--stdin FILE] [--out FILE] [--err FILE] [--timeout S] [--cols N] [--rows N] -- CMD...

The command's parent is a small reaper that has been re-parented to init, so whatever runs the tests (a CI runner,
or a Claude Code session) is never among the command's ancestors. With a pty (the default) the command gets a new
session whose controlling terminal is the pty; --out receives everything it ever wrote to the screen (the raw stream).
Steps, one per line: `expect REGEX` (wait for it in the output since the last match), `send TEXT` (backslash escapes
such as \\n, \\r, \\x1b), `sleep SECONDS`, `snap FILE` (write the output so far to FILE). Without a pty (--no-pty)
there is no controlling terminal at all; stdin is --stdin (default /dev/null) and stdout/stderr go to --out/--err.
Exit status: the command's, 124 on a timeout.
"""
import fcntl, os, re, select, signal, struct, sys, termios, time


def parse(argv):
    o = {"pty": True, "steps": None, "stdin": "/dev/null", "out": None, "err": None, "timeout": 30.0, "cols": 100, "rows": 30}
    i = 0
    while i < len(argv) and argv[i] != "--":
        a = argv[i]
        if a == "--no-pty":
            o["pty"] = False; i += 1; continue
        key = a[2:]
        if key not in o:
            sys.exit("pty_run: unknown option " + a)
        o[key] = argv[i + 1]; i += 2
    o["cmd"] = argv[i + 1:]
    if not o["cmd"]:
        sys.exit("pty_run: no command")
    return o


def load_steps(path):
    steps = []
    if not path:
        return steps
    for line in open(path, encoding="utf-8").read().splitlines():
        if not line.strip():
            continue
        verb, _, arg = line.partition(" ")
        if verb == "send":
            arg = arg.encode("latin-1", "backslashreplace").decode("unicode_escape").encode("utf-8")
        steps.append((verb, arg))
    return steps


def main():
    o = parse(sys.argv[1:])
    steps = load_steps(o["steps"])
    master = slave = None
    if o["pty"]:
        master, slave = os.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", int(o["rows"]), int(o["cols"]), 0, 0))
    st_r, st_w = os.pipe()
    first = os.fork()
    if first == 0:
        # A: fork the reaper B and exit, so B is re-parented away from this process tree
        a_pid = os.getpid()
        if os.fork():
            os._exit(0)
        while os.getppid() == a_pid:
            time.sleep(0.005)
        os.setsid()
        if slave is not None:
            os.close(master)
            fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
        child = os.fork()
        if child == 0:
            if slave is not None:
                for fd in (0, 1, 2):
                    os.dup2(slave, fd)
            else:
                os.dup2(os.open(o["stdin"], os.O_RDONLY), 0)
                os.dup2(os.open(o["out"] or "/dev/null", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), 1)
                os.dup2(os.open(o["err"] or "/dev/null", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), 2)
            os.closerange(3, 256)
            try:
                os.execvp(o["cmd"][0], o["cmd"])
            except OSError as e:
                os.write(2, ("pty_run: %s\n" % e).encode()); os._exit(127)
        if slave is not None:
            os.close(slave)
        os.write(st_w, ("pid %d\n" % child).encode())
        _, status = os.waitpid(child, 0)
        os.write(st_w, ("rc %d\n" % os.waitstatus_to_exitcode(status)).encode())
        os._exit(0)
    os.waitpid(first, 0)
    os.close(st_w)
    if slave is not None:
        os.close(slave)
    out = open(o["out"], "wb") if (o["out"] and master is not None) else None
    buf, pos, status_txt, rc, child = b"", 0, b"", None, None
    deadline = time.time() + float(o["timeout"])
    step_until = None
    master_open = master is not None
    drain_until = None
    while True:
        now = time.time()
        if now > deadline:
            if child:
                try: os.kill(child, signal.SIGKILL)
                except OSError: pass
            sys.stderr.write("pty_run: timed out%s\n" % (" at step %r" % (steps[0],) if steps else ""))
            if out: out.write(buf); out.close()
            sys.exit(124)
        # run the steps that are ready
        while steps and master_open:
            verb, arg = steps[0]
            if verb == "expect":
                m = re.compile(arg.encode()).search(buf, pos)
                if not m: break
                pos = m.end(); steps.pop(0)
            elif verb == "send":
                os.write(master, arg); steps.pop(0)
            elif verb == "snap":
                open(arg, "wb").write(buf); steps.pop(0)
            elif verb == "sleep":
                if step_until is None: step_until = now + float(arg)
                if now < step_until: break
                step_until = None; steps.pop(0)
            else:
                sys.exit("pty_run: unknown step " + verb)
        if rc is not None and (not master_open or (drain_until and now > drain_until)):
            break
        fds = [st_r] if status_txt is not None else []
        if master_open: fds.append(master)
        if not fds: break
        r, _, _ = select.select(fds, [], [], 0.05)
        if master_open and master in r:
            try:
                data = os.read(master, 65536)
            except OSError:
                data = b""
            if data: buf += data
            else: master_open = False
        if st_r in r:
            data = os.read(st_r, 4096)
            status_txt += data
            for line in status_txt.decode().splitlines():
                k, _, v = line.partition(" ")
                if k == "pid": child = int(v)
                if k == "rc": rc = int(v)
            if rc is not None and drain_until is None: drain_until = time.time() + 0.3
            if not data: status_txt = None if rc is not None else status_txt
    if out:
        out.write(buf); out.close()
    if steps:
        sys.stderr.write("pty_run: the command ended before step %r\n" % (steps[0],))
    sys.exit(rc if rc is not None else 125)


if __name__ == "__main__":
    main()
