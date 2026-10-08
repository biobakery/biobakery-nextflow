#!/usr/bin/env python3
"""Check raw FASTQ files for truncation and corruption before profiling them.

A FASTQ that ends early -- an interrupted copy or download, a gzip stream cut
off mid-member -- is not noticed until a tool reads to the end of it, which on a
large study is hours into the run, and the tool's error ("Compressed file ended
before the end-of-stream marker was reached") says nothing about which input it
was. This reads every file through once and reports, per file:

  * a missing file or broken symlink, an unreadable file, or an empty file
  * a compressed stream that does not decompress to its end (gzip or bzip2)
  * a FASTQ record that is cut short or malformed: a header that does not start
    with '@', a separator that does not start with '+', a quality string whose
    length differs from its sequence, or a final record with fewer than 4 lines
  * no reads at all
  * for paired input, mates that do not hold the same number of reads

Two ways to run it. Over a whole input folder, before starting a run:

    check_fastq_inputs.py --input /path/to/fastqs --threads 16

which prints one line per file, writes the table with --output, and exits 1 if
any file failed. --quick only tests that each compressed file decompresses to
its end, which is about twice as fast and is what catches a truncated file. And per sample, which is how the pipeline's check_reads step
calls it -- always exiting 0 so that a bad sample is reported and dropped
rather than failing the task:

    check_fastq_inputs.py --sample S1 --output S1.tsv --no-fail S1_R1.fastq.gz S1_R2.fastq.gz

The output is tab-separated: sample, file, status (PASS or FAIL), reads, problem.

Needs only Python 3.6+, gzip, bzip2 for .bz2 input, and awk.
"""

import argparse
import fnmatch
import os
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

HEADER = ["sample", "file", "status", "reads", "problem"]
FASTQ_EXT = re.compile(r"\.(fastq|fq)(\.gz|\.bz2)?$")

# Validates FASTQ structure on the decompressed stream and prints the read
# count, or the first problem and the line it was found on. A malformed record
# is reported as STOP and ends the read there: one is enough to drop the
# sample, and reading on through a broken file only costs time. A file that
# ends mid-record is reported as FAIL, from END.
AWK_FASTQ = r"""
NR % 4 == 1 {
    if (substr($0, 1, 1) != "@") { print "STOP\tline " NR ": header does not start with '@'"; bad = 1; exit }
    next
}
NR % 4 == 2 { seqlen = length($0); next }
NR % 4 == 3 {
    if (substr($0, 1, 1) != "+") { print "STOP\tline " NR ": separator does not start with '+'"; bad = 1; exit }
    next
}
NR % 4 == 0 {
    if (length($0) != seqlen) { print "STOP\tline " NR ": quality length " length($0) " differs from sequence length " seqlen; bad = 1; exit }
}
END {
    if (bad) exit
    if (NR % 4 != 0) { print "FAIL\tfile ends inside a record (" NR " lines, not a multiple of 4)"; exit }
    print "OK\t" NR / 4
}
"""


def decompressor(path):
    """The command that streams a file's FASTQ text to stdout."""
    # gzip rather than pigz: pigz decompresses on one thread anyway, and on a
    # truncated stream it can abort with "internal threads error" rather than
    # saying the file ended early.
    if path.endswith(".gz"):
        return ["gzip", "-dc", path]
    if path.endswith(".bz2"):
        return ["bzip2", "-dc", path]
    return ["cat", path]


def check_file(path, quick=False):
    """(status, reads, problem) for one file."""
    if not os.path.exists(path):
        return "FAIL", "", "file not found" + (" (broken symlink)" if os.path.islink(path) else "")
    if not os.access(path, os.R_OK):
        return "FAIL", "", "file is not readable (permission denied)"
    if os.path.getsize(path) == 0:
        return "FAIL", "0", "file is empty"

    if quick and path.endswith((".gz", ".bz2")):
        test = subprocess.run(decompressor(path)[:1] + ["-t", path],
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if test.returncode != 0:
            msg = test.stderr.decode(errors="replace").strip().splitlines()
            return "FAIL", "", "compressed stream is truncated or corrupt: " + (msg[-1] if msg else "exit %d" % test.returncode)
        return "PASS", "", ""

    env = dict(os.environ, LC_ALL="C")
    dec = subprocess.Popen(decompressor(path), stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    awk = subprocess.Popen(["awk", AWK_FASTQ], stdin=dec.stdout, stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, env=env)
    dec.stdout.close()  # so the decompressor sees SIGPIPE if awk stops early
    out, awk_err = awk.communicate()
    dec_err = dec.stderr.read()
    dec.wait()

    verdict = out.decode(errors="replace").strip().split("\t", 1)

    # Order matters. A malformed record awk stopped on comes first, since awk
    # stopping is itself what makes the decompressor fail, on a broken pipe.
    # Then a failed decompression, before a record cut short: a truncated gzip
    # also ends mid-record, but the truncation is the cause worth reporting.
    if verdict[0] == "STOP":
        return "FAIL", "", verdict[1]
    if dec.returncode != 0:
        msg = dec_err.decode(errors="replace").strip().splitlines()
        return "FAIL", "", "compressed stream is truncated or corrupt: " + (msg[-1] if msg else "exit %d" % dec.returncode)
    if verdict[0] == "FAIL":
        return "FAIL", "", verdict[1]
    if awk.returncode != 0 or verdict[0] != "OK":
        return "FAIL", "", "could not parse: " + awk_err.decode(errors="replace").strip()

    reads = verdict[1]
    if reads == "0":
        return "FAIL", "0", "no reads"
    return "PASS", reads, ""


def check_sample(sample, files, quick=False):
    """Rows for one sample's files, with a mate-count comparison for a pair."""
    rows = [[sample, f] + list(check_file(f, quick)) for f in files]
    if len(rows) == 2 and all(r[2] == "PASS" for r in rows) and rows[0][3] != rows[1][3]:
        problem = "mates hold different read counts (%s vs %s)" % (rows[0][3], rows[1][3])
        for r in rows:
            r[2], r[4] = "FAIL", problem
    return rows


def pair_regex(pair_identifier):
    """'_R{1,2}' -> regex capturing (prefix, mate, suffix) of a mate filename."""
    m = re.match(r"^(.*)\{(\w),(\w)\}(.*)$", pair_identifier)
    if not m:
        raise SystemExit("ERROR: --pair-identifier must look like '_R{1,2}', got '%s'" % pair_identifier)
    before, one, two, after = m.groups()
    return re.compile(r"^(.*?)%s(%s|%s)%s(.*)$" % (re.escape(before), re.escape(one),
                                                   re.escape(two), re.escape(after))), one, two


def samples_in_folder(folder, pattern, pair_identifier, single_end):
    """{sample: [files]} for a folder, pairing mates the way the pipeline does."""
    names = sorted(n for n in os.listdir(folder)
                   if fnmatch.fnmatch(n, pattern) and FASTQ_EXT.search(n))
    samples = {}
    regex, one, two = pair_regex(pair_identifier)
    mates = {}
    for n in names:
        m = None if single_end else regex.match(n)
        if m:
            mates.setdefault(m.group(1), {})[m.group(2)] = n
        else:
            samples[FASTQ_EXT.sub("", n)] = [n]
    for prefix, pair in mates.items():
        if one in pair and two in pair:
            samples[prefix] = [pair[one], pair[two]]
        else:
            # A mate without its partner: still worth checking, and named for
            # what it is so the report makes the naming problem visible.
            for n in pair.values():
                samples[FASTQ_EXT.sub("", n) + " (no mate)"] = [n]
    return {s: [os.path.join(folder, f) for f in fs] for s, fs in samples.items()}


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("files", nargs="*", help="one sample's read files (one, or the two mates)")
    p.add_argument("--input", help="check every FASTQ in this folder instead")
    p.add_argument("--sample", help="sample name for the files given (default: the first file's name)")
    p.add_argument("--pattern", default="*", help="with --input: only files matching this glob (default: all FASTQ)")
    p.add_argument("--pair-identifier", default="_R{1,2}",
                   help="with --input: how mates are named, as in the pipeline (default: _R{1,2})")
    p.add_argument("--single-end", action="store_true", help="with --input: do not pair mates")
    p.add_argument("--quick", action="store_true",
                   help="only test that compressed files decompress to the end: about twice as fast, "
                        "and catches truncation, but not malformed records or mismatched mates")
    p.add_argument("--threads", type=int, default=4, help="files checked at once (default: 4)")
    p.add_argument("--output", help="write the table here as well")
    p.add_argument("--no-fail", action="store_true", help="exit 0 even when a file fails")
    p.add_argument("--quiet", action="store_true", help="print only the failures and the summary")
    args = p.parse_args()

    if bool(args.input) == bool(args.files):
        p.error("give either --input FOLDER or the read files of one sample")

    if args.input:
        if not os.path.isdir(args.input):
            p.error("not a folder: %s" % args.input)
        samples = samples_in_folder(args.input, args.pattern, args.pair_identifier, args.single_end)
        if not samples:
            p.error("no FASTQ files matching '%s' in %s" % (args.pattern, args.input))
    else:
        if len(args.files) > 2:
            p.error("give at most two files (a pair) per sample")
        samples = {args.sample or FASTQ_EXT.sub("", os.path.basename(args.files[0])): args.files}

    rows = []
    total = len(samples)
    with ThreadPoolExecutor(max_workers=max(1, args.threads)) as pool:
        futures = [pool.submit(check_sample, s, fs, args.quick) for s, fs in sorted(samples.items())]
        for i, fut in enumerate(futures, 1):
            for r in fut.result():
                rows.append(r)
                if not args.quiet or r[2] != "PASS":
                    print("\t".join([r[2], r[1], r[3] or "-", r[4]]).rstrip("\t"), flush=True)
            if args.input and not args.quiet and i % 50 == 0:
                print("# %d of %d samples checked" % (i, total), file=sys.stderr, flush=True)

    if args.output:
        with open(args.output, "w") as fh:
            fh.write("\t".join(HEADER) + "\n")
            for r in rows:
                fh.write("\t".join(r) + "\n")

    bad = sorted({r[0] for r in rows if r[2] != "PASS"})
    if args.input:
        print("# %d of %d samples failed%s" % (len(bad), total, (": " + ", ".join(bad)) if bad else ""),
              file=sys.stderr)
    return 1 if bad and not args.no_fail else 0


if __name__ == "__main__":
    sys.exit(main())
