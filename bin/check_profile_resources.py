#!/usr/bin/env python3
"""Fail if a site profile has deleted a process's resource request.

A `withName:` block in a profile *replaces* the block conf/base.config gives the
same selector string; it does not merge into it. So a profile block that sets
only `beforeScript` silently drops that process's cpus, memory and time, and the
process runs at the bare `process {}` default instead -- which is how a 32 GB
HUMAnN task came to be OOM-killed three times at 4, 8 and 12 GB.

This resolves each profile with `nextflow config -profile <name>` and checks the
result rather than the source, so it catches the mistake however it is spelled:
every selector base.config gives a directive must still carry that directive
once the profile is merged in. It needs Nextflow and a JVM, no tools.

    bin/check_profile_resources.py
"""

import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROFILES = ["local", "harvard_rc", "tufts_hpc", "amazon"]
DIRECTIVES = ("cpus", "memory", "time")


def blocks(text):
    """{selector: {directive: value}} for every withName block in a config dump."""
    out = {}
    selector = None
    for line in text.splitlines():
        header = re.match(r"\s*withName:\s*'?([^'{]+?)'?\s*\{", line)
        if header:
            selector = header.group(1)
            out.setdefault(selector, {})
            continue
        if selector is None:
            continue
        if re.match(r"\s*\}", line):
            selector = None
            continue
        assign = re.match(r"\s*(\w+)\s*=\s*(.+?)\s*$", line)
        if assign:
            out[selector][assign.group(1)] = assign.group(2)
    return out


def resolve(profile=None):
    cmd = ["nextflow", "config"]
    if profile:
        cmd += ["-profile", profile]
    proc = subprocess.run(cmd, cwd=REPO, capture_output=True, text=True)
    if proc.returncode != 0:
        sys.exit(f"ERROR: {' '.join(cmd)} failed:\n{proc.stderr.strip()}")
    return blocks(proc.stdout)


def main():
    if not any(
        os.access(os.path.join(d, "nextflow"), os.X_OK)
        for d in os.environ.get("PATH", "").split(os.pathsep)
        if d
    ):
        sys.exit("ERROR: nextflow is not on PATH.")

    # No profile: base.config alone, which is the reference for what each
    # process is entitled to.
    base = resolve()
    failures = []

    for profile in PROFILES:
        merged = resolve(profile)
        for selector, directives in base.items():
            for directive in DIRECTIVES:
                if directive not in directives:
                    continue
                if directive in merged.get(selector, {}):
                    continue
                failures.append(
                    f"-profile {profile}: process '{selector}' lost `{directive}` "
                    f"(base.config sets {directive} = {directives[directive]})"
                )

    if failures:
        print("Site profiles have deleted resource requests:\n", file=sys.stderr)
        for line in failures:
            print(f"  {line}", file=sys.stderr)
        print(
            "\nA profile block replaces base.config's block for the same selector.\n"
            "Either use a selector string base.config does not use, or restate\n"
            "cpus, memory and time in the profile block. See the rules at the top\n"
            "of conf/profiles/harvard_rc.config.",
            file=sys.stderr,
        )
        return 1

    print(f"Every profile keeps base.config's resource requests ({len(PROFILES)} checked).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
