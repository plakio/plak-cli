#!/usr/bin/env python3
"""Run a command inside a pseudo terminal and report what the screen shows.

The command is attached to a real pty, so interactive programs take their
interactive code path. The output is replayed through a small terminal
emulator, so the assertions can look at the visible screen instead of at a
capture with the ANSI sequences stripped.

Usage:
  pty-run.py [--rows N] [--cols N] [--send KEY]... [--raw-out FILE] -- CMD [ARG...]

KEY is a key name (up, down, left, right, enter, esc, tab, space, ctrl-c,
home, end) or a literal string with escapes (\\r, \\e, \\t, \\x1b).

The report is written to stdout:

  === INITIAL SCREEN ===
  |first line of the screen|
  ...
  === FINAL SCREEN ===
  |...|
  === EXIT: <status> ===
"""

import argparse
import errno
import fcntl
import os
import pty
import select
import signal
import struct
import sys
import termios
import time

KEYS = {
    "up": "\x1b[A",
    "down": "\x1b[B",
    "right": "\x1b[C",
    "left": "\x1b[D",
    "home": "\x1b[H",
    "end": "\x1b[F",
    "enter": "\r",
    "esc": "\x1b",
    "tab": "\t",
    "space": " ",
    "ctrl-c": "\x03",
}

ESCAPES = {"r": "\r", "n": "\n", "e": "\x1b", "t": "\t", "s": " ", "\\": "\\"}


class Screen:
    """A very small terminal emulator: enough to replay what gum draws."""

    def __init__(self, cols, rows):
        self.cols = cols
        self.rows = rows
        self.lines = [[" "] * cols for _ in range(rows)]
        self.cx = 0
        self.cy = 0

    def _scroll(self):
        while self.cy >= self.rows:
            self.lines.pop(0)
            self.lines.append([" "] * self.cols)
            self.cy -= 1

    def _put(self, char):
        if self.cx >= self.cols:
            self.cx = 0
            self.cy += 1
            self._scroll()
        self.lines[self.cy][self.cx] = char
        self.cx += 1

    def _erase_line(self, mode):
        if mode == 0:
            span = range(self.cx, self.cols)
        elif mode == 1:
            span = range(0, min(self.cx + 1, self.cols))
        else:
            span = range(0, self.cols)
        for x in span:
            self.lines[self.cy][x] = " "

    def _erase_display(self, mode):
        if mode == 2 or mode == 3:
            for row in self.lines:
                for x in range(self.cols):
                    row[x] = " "
            self.cx = 0
            self.cy = 0
            return
        if mode == 0:
            self._erase_line(0)
            for row in range(self.cy + 1, self.rows):
                for x in range(self.cols):
                    self.lines[row][x] = " "
        elif mode == 1:
            self._erase_line(1)
            for row in range(0, self.cy):
                for x in range(self.cols):
                    self.lines[row][x] = " "

    def _erase_chars(self, count):
        for x in range(self.cx, min(self.cx + count, self.cols)):
            self.lines[self.cy][x] = " "

    def feed(self, data):
        index = 0
        length = len(data)
        while index < length:
            char = data[index]
            index += 1
            if char == "\x1b":
                if index >= length:
                    break
                nxt = data[index]
                index += 1
                if nxt == "[":
                    params = ""
                    # A CSI sequence ends with a final byte in the 0x40-0x7e
                    # range; parameter and intermediate bytes come before it.
                    while index < length and not ("@" <= data[index] <= "~"):
                        params += data[index]
                        index += 1
                    if index >= length:
                        break
                    final = data[index]
                    index += 1
                    self._csi(params, final)
                elif nxt == "]":
                    # OSC: consume until BEL or ST.
                    while index < length:
                        if data[index] == "\x07":
                            index += 1
                            break
                        if data[index] == "\x1b" and index + 1 < length and data[index + 1] == "\\":
                            index += 2
                            break
                        index += 1
                elif nxt == "P" or nxt == "_" or nxt == "^":
                    while index < length and data[index] != "\x07":
                        index += 1
                    index += 1
                continue
            if char == "\r":
                self.cx = 0
            elif char == "\n":
                self.cy += 1
                self._scroll()
            elif char == "\b":
                self.cx = max(0, self.cx - 1)
            elif char == "\t":
                self.cx = min(self.cols - 1, (self.cx // 8 + 1) * 8)
            elif char == "\x07":
                continue
            else:
                self._put(char)

    def _csi(self, params, final):
        numbers = [int(part) if part.isdigit() else 0 for part in params.split(";") if part != ""]
        first = numbers[0] if numbers else 0
        if final == "A":
            self.cy = max(0, self.cy - max(1, first))
        elif final == "B":
            self.cy = min(self.rows - 1, self.cy + max(1, first))
        elif final == "C":
            self.cx = min(self.cols - 1, self.cx + max(1, first))
        elif final == "D":
            self.cx = max(0, self.cx - max(1, first))
        elif final in ("H", "f"):
            row = numbers[0] if len(numbers) > 0 and numbers[0] else 1
            col = numbers[1] if len(numbers) > 1 and numbers[1] else 1
            self.cy = max(0, min(self.rows - 1, row - 1))
            self.cx = max(0, min(self.cols - 1, col - 1))
        elif final == "J":
            self._erase_display(first)
        elif final == "K":
            self._erase_line(first)
        elif final == "X":
            self._erase_chars(max(1, first))

    def display(self):
        return ["".join(row).rstrip() for row in self.lines]


def decode(spec):
    if spec in KEYS:
        return KEYS[spec]
    out = []
    index = 0
    while index < len(spec):
        char = spec[index]
        if char == "\\" and index + 1 < len(spec):
            nxt = spec[index + 1]
            if nxt in ESCAPES:
                out.append(ESCAPES[nxt])
                index += 2
                continue
            if nxt == "x" and index + 3 < len(spec):
                out.append(chr(int(spec[index + 2:index + 4], 16)))
                index += 4
                continue
        out.append(char)
        index += 1
    return "".join(out)


def answer_queries(chunk, fd):
    """Reply to the terminal capability queries gum asks for."""
    reply = b""
    if b"\x1b]11;?" in chunk:
        reply += b"\x1b]11;rgb:0000/0000/0000\x1b\\"
    if b"\x1b]10;?" in chunk:
        reply += b"\x1b]10;rgb:ffff/ffff/ffff\x1b\\"
    if b"\x1b[6n" in chunk:
        reply += b"\x1b[1;1R"
    if reply:
        try:
            os.write(fd, reply)
        except OSError:
            pass


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--rows", type=int, default=24)
    parser.add_argument("--cols", type=int, default=100)
    parser.add_argument("--send", action="append", default=[])
    parser.add_argument("--settle", type=float, default=0.8)
    parser.add_argument("--raw-out", default=None)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()

    command = args.command[1:] if args.command and args.command[0] == "--" else args.command
    if not command:
        sys.stderr.write("pty-run.py: no command given\n")
        return 2

    pid, fd = pty.fork()
    if pid == 0:
        os.environ["TERM"] = os.environ.get("TERM", "xterm-256color")
        os.environ["COLUMNS"] = str(args.cols)
        os.environ["LINES"] = str(args.rows)
        try:
            os.execvp(command[0], command)
        finally:
            os._exit(127)

    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", args.rows, args.cols, 0, 0))

    screen = Screen(args.cols, args.rows)
    raw = bytearray()
    exited = [None]

    def drain(timeout):
        """Read what is pending. Returns (got_data, still_open)."""
        got = False
        while True:
            try:
                ready, _, _ = select.select([fd], [], [], timeout)
            except OSError:
                return got, False
            if not ready:
                return got, True
            try:
                chunk = os.read(fd, 65536)
            except OSError as error:
                if error.errno == errno.EIO:
                    return got, False
                raise
            if not chunk:
                return got, False
            raw.extend(chunk)
            answer_queries(chunk, fd)
            screen.feed(chunk.decode("utf-8", "replace"))
            got = True
            timeout = 0.2

    # Wait for the first paint to settle.
    deadline = time.time() + 10
    while time.time() < deadline:
        got, still_open = drain(0.2)
        if not still_open:
            break
        if got:
            deadline = time.time() + 2
        elif raw:
            break
    initial = screen.display()

    for spec in args.send:
        try:
            os.write(fd, decode(spec).encode())
        except OSError:
            break
        # Wait until the program settled after the key.
        settle_deadline = time.time() + 3
        while time.time() < settle_deadline:
            got, still_open = drain(0.15)
            if not still_open:
                break
            if got:
                settle_deadline = time.time() + 1
            elif raw:
                break
        time.sleep(args.settle)

    if not args.send:
        # The command waits for input, so stop it after the first paint.
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        try:
            os.waitpid(pid, 0)
        except ChildProcessError:
            pass
        status_text = "stopped"
    else:
        # Wait for the command to finish and collect its exit status.
        deadline = time.time() + 10
        while time.time() < deadline:
            got, still_open = drain(0.2)
            if not still_open:
                break
            done, raw_status = os.waitpid(pid, os.WNOHANG)
            if done == pid:
                exited[0] = raw_status
                break

        if exited[0] is None:
            try:
                done, raw_status = os.waitpid(pid, os.WNOHANG)
                if done == pid:
                    exited[0] = raw_status
            except ChildProcessError:
                exited[0] = 0

        if exited[0] is None:
            # The command is still running: stop it and report the failure.
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            try:
                _, exited[0] = os.waitpid(pid, 0)
            except ChildProcessError:
                exited[0] = 0
        status_text = str(os.waitstatus_to_exitcode(exited[0]))
    drain(0.3)

    try:
        os.close(fd)
    except OSError:
        pass

    if args.raw_out:
        with open(args.raw_out, "wb") as handle:
            handle.write(bytes(raw))

    print("=== INITIAL SCREEN ===")
    for line in initial:
        print("|%s|" % line)
    print("=== FINAL SCREEN ===")
    for line in screen.display():
        print("|%s|" % line)
    print("=== RAW BYTES: %d ===" % len(raw))
    print("=== EXIT: %s ===" % status_text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
