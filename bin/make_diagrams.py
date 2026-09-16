#!/usr/bin/env python3
"""Generate the workflow diagrams and the step reference from the pipeline itself.

Nothing here is hand-drawn. The diagrams come from Nextflow's own DAG renderer
(`nextflow run -preview -with-dag <file>.mmd`), which builds the graph by
resolving the real `include` statements, `take:`/`emit:` wiring and channel
operators, and groups the nodes by subworkflow. The step descriptions come from
the comment above each `process` in `modules/`. So both halves of the output are
derived from the code and cannot drift away from it -- `--check` fails if they
have, which is what CI runs.

`-preview` builds the graph without launching a task, so this needs Nextflow and
a JVM but no tools, no databases and no cluster.

    bin/make_diagrams.py            # regenerate docs/diagrams/ and docs/workflow_reference.md
    bin/make_diagrams.py --check    # fail if what is committed is out of date
"""

import argparse
import filecmp
import os
import re
import shutil
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# One preview run per workflow. The paths are placeholders: -preview resolves
# params and builds the graph but never runs a task, so nothing here is read.
# They exist only because the input guards and the KneadData database check run
# during graph construction.
STUB_DBS = [
    "--host_genome", "/stub/hg38",
    "--host_transcriptome", "/stub/transcriptome",
    "--rrna_db", "/stub/rrna",
    "--metaphlan_db", "/stub/metaphlan",
    "--humann_db", "/stub/humann",
    "--phylophlan_path", "/stub/phylophlan",
]

WORKFLOWS = [
    ("mgx", "Whole metagenome shotgun", ["--workflow", "mgx", "--readsdir", "{reads}"]),
    ("mtx", "Whole metatranscriptome shotgun", ["--workflow", "mtx", "--readsdir", "{reads}"]),
    ("mgx_mtx", "Paired metagenome + metatranscriptome", [
        "--workflow", "mgx_mtx",
        "--input_metagenome", "{reads}",
        "--input_metatranscriptome", "{reads}",
    ]),
    ("assembly", "MAG assembly, binning and SGB clustering", [
        "--workflow", "assembly", "--readsdir", "{reads}",
    ]),
    ("vis", "Visualisation report", ["--workflow", "vis", "--vis_input", "{folder}"]),
    ("stats", "Statistical analysis report", [
        "--workflow", "stats", "--stats_input", "{folder}",
        "--input_metadata", "{folder}/metadata.tsv",
    ]),
]

# Toggles that are off by default but worth showing in the diagram, so the
# optional stages appear rather than being silently absent.
EXTRA_ON = {
    "mgx": ["--run_viral_profiling", "true", "--run_strain_profiling", "true"],
    "mtx": ["--run_strain_profiling", "true"],
    "mgx_mtx": ["--run_strain_profiling", "true"],
}


# ── The step catalog: process name → what it does ────────────────────────────

def process_catalog():
    """Map each process to (module file, one-line description, published path).

    The description is the first line of the comment block immediately above
    the `process` keyword, which is the convention every module already follows.
    Aliases introduced by `include { x as y }` are added as entries of their own,
    because that is the name the DAG shows.
    """
    catalog = {}
    for root, _dirs, files in os.walk(os.path.join(REPO, "modules")):
        for name in files:
            if name != "main.nf":
                continue
            path = os.path.join(root, name)
            rel = os.path.relpath(path, REPO)
            lines = open(path).read().split("\n")
            for i, line in enumerate(lines):
                match = re.match(r"^process\s+(\w+)\s*\{", line)
                if not match:
                    continue
                catalog[match.group(1)] = {
                    "module": rel,
                    "summary": _comment_above(lines, i),
                    "publish": _publish_dir(lines, i),
                }

    for source, alias in _aliases():
        if source in catalog and alias not in catalog:
            entry = dict(catalog[source])
            entry["summary"] = f"{entry['summary']} (`{source}`, run again as `{alias}`)"
            catalog[alias] = entry
    return catalog


def _aliases():
    """Every `include { source as alias }` in the workflow and subworkflow files."""
    found = []
    for folder in ("workflows", "subworkflows"):
        for name in sorted(os.listdir(os.path.join(REPO, folder))):
            if not name.endswith(".nf"):
                continue
            text = open(os.path.join(REPO, folder, name)).read()
            found += re.findall(r"include\s*\{\s*(\w+)\s+as\s+(\w+)\s*\}", text)
    return found


def _comment_above(lines, index):
    """First line of the `//` block directly above lines[index]."""
    block = []
    j = index - 1
    while j >= 0:
        stripped = lines[j].strip()
        if stripped.startswith("//"):
            block.append(stripped[2:].strip())
        elif stripped == "" and not block:
            pass  # allow one run of blank lines before the comment
        else:
            break
        j -= 1
    block.reverse()
    return block[0] if block else ""


def _publish_dir(lines, index):
    """The publishDir path of the process starting at lines[index], if any."""
    for line in lines[index:index + 12]:
        if "publishDir" not in line:
            continue
        match = re.search(r'"([^"]*\$\{?params\.outdir\}?[^"]*)"', line)
        if match:
            path = match.group(1)
            path = re.sub(r"\$\{?params\.outdir\}?", "<outdir>", path)
            return re.sub(r"\$\{([^}]*)\}", r"<\1>", path)
        return "<outdir>/..."
    return ""


# ── Mermaid post-processing ──────────────────────────────────────────────────

NODE_PROCESS = re.compile(r"^\s*(v\d+)\(\[(.+)\]\)\s*$")
NODE_OTHER = re.compile(r"^\s*(v\d+)[\[\(]")
EDGE = re.compile(r"^\s*(v\d+)\s*-->\s*(v\d+)\s*$")
SUBGRAPH = re.compile(r"^\s*subgraph\s+(.*?)\s*$")


def simplify(mermaid, catalog):
    """Reduce Nextflow's raw DAG to a process-only flowchart.

    The raw graph carries a node for every value channel and every channel
    operator -- a dozen `subdir` inputs and a row of anonymous junctions -- which
    swamps the actual steps. Those nodes are contracted away: an edge is kept
    between two processes when a path of dropped nodes joins them. Each surviving
    node is labelled with its process name and what that process does.
    """
    processes = {}   # node id → process name
    dropped = set()
    edges = []
    # node id → subworkflow path, e.g. ['MGX', 'QUALITY_CONTROL']
    membership = {}
    stack = []

    for line in mermaid.split("\n"):
        if SUBGRAPH.match(line) and "-->" not in line:
            name = SUBGRAPH.match(line).group(1).strip().strip('"')
            stack.append(name)
            continue
        if line.strip() == "end":
            if stack:
                stack.pop()
            continue

        match = NODE_PROCESS.match(line)
        if match:
            processes[match.group(1)] = match.group(2)
            membership[match.group(1)] = [s for s in stack if s.strip()]
            continue
        match = NODE_OTHER.match(line)
        if match:
            dropped.add(match.group(1))
            continue
        match = EDGE.match(line)
        if match:
            edges.append((match.group(1), match.group(2)))

    # Contract the dropped nodes: walk forward from each process through
    # non-process nodes until the next process is reached.
    forward = {}
    for src, dst in edges:
        forward.setdefault(src, []).append(dst)

    kept = set()
    for start in processes:
        seen = set()
        queue = list(forward.get(start, []))
        while queue:
            node = queue.pop()
            if node in seen:
                continue
            seen.add(node)
            if node in processes:
                if node != start:
                    kept.add((start, node))
            elif node in dropped:
                queue.extend(forward.get(node, []))

    # Order edges by the position of their endpoints in the graph, so the file
    # reads top to bottom and a regenerated diagram diffs cleanly.
    order = sorted(kept, key=lambda e: (int(e[0][1:]), int(e[1][1:])))
    return _render(processes, membership, order, catalog)


def _render(processes, membership, edges, catalog):
    """Emit the simplified flowchart, one subgraph per subworkflow."""
    out = ["flowchart TB"]

    groups = {}
    for node, name in processes.items():
        # Group by the innermost subworkflow, which is what reads as a "stage".
        path = membership.get(node) or []
        groups.setdefault(path[-1] if path else "", []).append((node, name))

    def label(name):
        summary = catalog.get(name, {}).get("summary", "")
        summary = re.sub(r'["<>]', "", summary)
        if len(summary) > 46:
            summary = summary[:45].rstrip() + "…"
        return f'{name}<br/><i>{summary}</i>' if summary else name

    # Subworkflows in the order the pipeline reaches them, not alphabetically:
    # the node ids Nextflow assigns follow the order the graph was built in.
    def first_node(group):
        return min(int(node[1:]) for node, _name in groups[group])

    for group in sorted(groups, key=first_node):
        indent = "    "
        if group:
            out.append(f"    subgraph {group}")
            indent = "        "
        for node, name in sorted(groups[group], key=lambda p: int(p[0][1:])):
            out.append(f'{indent}{node}(["{label(name)}"])')
        if group:
            out.append("    end")

    out.append("")
    for src, dst in edges:
        out.append(f"    {src} --> {dst}")
    return "\n".join(out) + "\n"


# ── Running the previews ─────────────────────────────────────────────────────

def render_dag(workflow, args, outfile, stubs):
    """Run one `-preview -with-dag` and write the raw Mermaid to outfile."""
    filled = [a.format(reads=stubs["reads"], folder=stubs["folder"]) for a in args]
    command = [
        "nextflow", "-quiet", "run", os.path.join(REPO, "main.nf"),
        "-preview", "-with-dag", outfile,
        "-profile", "local",
        "--outdir", os.path.join(stubs["work"], f"out_{workflow}"),
        "--log_versions", "true",
    ] + STUB_DBS + filled + EXTRA_ON.get(workflow, [])

    env = dict(os.environ, NXF_OFFLINE="true", NXF_ANSI_LOG="false")
    result = subprocess.run(
        command, cwd=stubs["work"], env=env,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
    )
    if result.returncode != 0 or not os.path.exists(outfile):
        sys.exit(f"ERROR: preview failed for --workflow {workflow}\n{result.stdout}")
    return open(outfile).read()


def build(outdir, stubs):
    """Write docs/diagrams/*.mmd and the workflow reference into outdir."""
    catalog = process_catalog()
    diagrams = os.path.join(outdir, "diagrams")
    os.makedirs(diagrams, exist_ok=True)

    rendered = {}
    for workflow, title, args in WORKFLOWS:
        raw = os.path.join(stubs["work"], f"{workflow}.raw.mmd")
        if os.path.exists(raw):
            os.remove(raw)
        mermaid = simplify(render_dag(workflow, args, raw, stubs), catalog)
        with open(os.path.join(diagrams, f"{workflow}.mmd"), "w") as handle:
            handle.write(mermaid)
        rendered[workflow] = (title, mermaid)

    with open(os.path.join(outdir, "workflow_reference.md"), "w") as handle:
        handle.write(reference_page(rendered, catalog))


def reference_page(rendered, catalog):
    """The generated markdown: one diagram plus one step table per workflow."""
    out = [
        "# Workflow reference",
        "",
        "**Generated — do not edit.** Regenerate with `bin/make_diagrams.py`;",
        "CI checks this file with `bin/make_diagrams.py --check`.",
        "",
        "Every diagram is Nextflow's own DAG for that workflow, taken from",
        "`nextflow run -preview -with-dag`, with the value-channel and operator",
        "nodes contracted away so only the steps remain. Boxes are grouped by the",
        "subworkflow they live in. Each step's description is the comment above its",
        "`process` in `modules/`.",
        "",
        "Optional stages that are off by default (`--run_viral_profiling`,",
        "`--run_strain_profiling`) are drawn as if enabled, so the diagram shows",
        "everything a workflow can do.",
        "",
        "| Workflow | `--workflow` | What it does | Steps |",
        "|---|---|---|---|",
    ]
    for workflow, _title, _args in WORKFLOWS:
        title, mermaid = rendered[workflow]
        count = len(set(re.findall(r'v\d+\(\["(\w+)', mermaid)))
        out.append(f"| [{workflow}](#{workflow}) | `{workflow}` | {title} | {count} |")
    out.append("")

    for workflow, _title, _args in WORKFLOWS:
        title, mermaid = rendered[workflow]
        names = sorted(set(re.findall(r'v\d+\(\["(\w+)', mermaid)))
        out += [
            f"## {workflow}",
            "",
            f"{title}.",
            "",
            "```mermaid",
            mermaid.rstrip(),
            "```",
            "",
            "| Step | What it does | Defined in | Publishes to |",
            "|---|---|---|---|",
        ]
        for name in names:
            entry = catalog.get(name, {})
            out.append(
                f"| `{name}` | {entry.get('summary', '')} "
                f"| `{entry.get('module', '')}` "
                f"| `{entry.get('publish', '')}` |"
            )
        out.append("")

    return "\n".join(out)


def make_stubs(work):
    """Placeholder input paths, so the preview's input guards are satisfied."""
    reads = os.path.join(work, "reads")
    folder = os.path.join(work, "report_input")
    os.makedirs(reads, exist_ok=True)
    os.makedirs(folder, exist_ok=True)
    for name in ("STUB_S1_R1.fastq.gz", "STUB_S1_R2.fastq.gz"):
        open(os.path.join(reads, name), "a").close()
    open(os.path.join(folder, "metadata.tsv"), "a").close()
    return {"work": work, "reads": reads, "folder": folder}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true",
                        help="fail if the committed output is out of date")
    options = parser.parse_args()

    if not shutil.which("nextflow"):
        sys.exit("ERROR: nextflow is not on PATH. On FASRC:\n"
                 "  hutlab load rocky8/biobakery-workflows-nextflow/0.0.4")

    docs = os.path.join(REPO, "docs")
    with tempfile.TemporaryDirectory(prefix="biobakery_nf_dag_") as tmp:
        stubs = make_stubs(os.path.join(tmp, "work"))
        target = os.path.join(tmp, "docs") if options.check else docs
        build(target, stubs)

        if not options.check:
            print(f"Wrote {os.path.join(docs, 'workflow_reference.md')}")
            print(f"Wrote {len(WORKFLOWS)} diagrams to {os.path.join(docs, 'diagrams')}")
            return

        stale = []
        for name in ["workflow_reference.md"] + [
            os.path.join("diagrams", f"{w}.mmd") for w, _t, _a in WORKFLOWS
        ]:
            new, old = os.path.join(target, name), os.path.join(docs, name)
            if not os.path.exists(old) or not filecmp.cmp(new, old, shallow=False):
                stale.append(os.path.join("docs", name))
        if stale:
            sys.exit("ERROR: these are out of date with the pipeline:\n  " +
                     "\n  ".join(stale) +
                     "\nRegenerate with: bin/make_diagrams.py")
        print(f"Up to date: docs/workflow_reference.md and {len(WORKFLOWS)} diagrams.")


if __name__ == "__main__":
    main()
