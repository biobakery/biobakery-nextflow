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


# One colour per kind of stage, so the same stage is the same colour in every
# diagram. Aliased stages (QC_MGX, QC_MTX) share their family's colour; the
# subgraph label says which half they belong to. Fills are light and the text
# colour is set explicitly, so the diagrams stay legible in both GitHub themes.
STAGE_COLOURS = [
    (("QC", "QUALITY_CONTROL"),        ("#dbeafe", "#3b82f6", "#1e3a8a")),
    (("TAX", "TAXONOMIC_PROFILING"),   ("#dcfce7", "#22c55e", "#14532d")),
    (("FUNC", "FUNCTIONAL_PROFILING"), ("#ede9fe", "#8b5cf6", "#4c1d95")),
    (("VIRAL_PROFILING",),             ("#ffedd5", "#f97316", "#7c2d12")),
    (("STRAIN_PROFILING",),            ("#ccfbf1", "#14b8a6", "#134e4a")),
    (("ASSEMBLY",),                    ("#fef3c7", "#d97706", "#78350f")),
    (("VIS",),                         ("#fce7f3", "#ec4899", "#831843")),
    (("STATS",),                       ("#e0e7ff", "#6366f1", "#312e81")),
]
DEFAULT_COLOUR = ("#f1f5f9", "#94a3b8", "#334155")   # the workflow's own steps


def _stage_colour(stage):
    for prefixes, colour in STAGE_COLOURS:
        for prefix in prefixes:
            if stage == prefix or stage.startswith(prefix + "_"):
                return colour
    return DEFAULT_COLOUR


def _wrap(text, width=30, lines=2):
    """Break a description at word boundaries, never mid-word."""
    words, out, current = text.split(), [], ""
    for word in words:
        candidate = f"{current} {word}".strip()
        if len(candidate) <= width:
            current = candidate
            continue
        out.append(current)
        current = word
        if len(out) == lines:
            break
    if current and len(out) < lines:
        out.append(current)
    if len(out) == lines and len(" ".join(out)) < len(text):
        out[-1] = out[-1].rstrip(" ,;:.") + "…"
    return "<br/>".join(part for part in out if part)


def _node_ids(processes):
    """Readable, unique node ids: the process name rather than Nextflow's v12."""
    ids, used = {}, {}
    for node in sorted(processes, key=lambda n: int(n[1:])):
        base = re.sub(r"\W", "_", processes[node])
        used[base] = used.get(base, 0) + 1
        ids[node] = base if used[base] == 1 else f"{base}_{used[base]}"
    return ids


def _render(processes, membership, edges, catalog):
    """Emit the simplified flowchart, one subgraph per subworkflow.

    Laid out like a hand-drawn diagram rather than a dump: the stages run left
    to right, the steps inside a stage run top to bottom, each stage has its own
    colour, and a step that publishes output is drawn with a doubled border. The
    node ids are the process names, so the .mmd file reads as well as it renders.
    """
    ids = _node_ids(processes)

    groups = {}
    for node, name in processes.items():
        # Group by the innermost subworkflow, which is what reads as a "stage".
        path = membership.get(node) or []
        groups.setdefault(path[-1] if path else "", []).append((node, name))

    def label(name):
        summary = re.sub(r'["<>]', "", catalog.get(name, {}).get("summary", ""))
        wrapped = _wrap(summary) if summary else ""
        return f"<b>{name}</b><br/>{wrapped}" if wrapped else f"<b>{name}</b>"

    # Where the flow starts and stops, which is the first thing you look for.
    # Nearly every process publishes something, so publishing is not a useful
    # distinction to draw; being an entry or an exit is.
    has_incoming = {dst for _src, dst in edges}
    has_outgoing = {src for src, _dst in edges}

    def shape(node, name):
        body = f'"{label(name)}"'
        if node not in has_incoming:
            return f"{ids[node]}([{body}])"      # entry: stadium
        if node not in has_outgoing:
            return f"{ids[node]}[{body}]"        # exit: square corners
        return f"{ids[node]}({body})"            # in the middle: rounded

    # Subworkflows in the order the pipeline reaches them, not alphabetically:
    # the node ids Nextflow assigns follow the order the graph was built in.
    def first_node(group):
        return min(int(node[1:]) for node, _name in groups[group])

    out = [
        '%%{init: {"flowchart": {"curve": "basis", "nodeSpacing": 40,',
        '                        "rankSpacing": 70, "padding": 8}}}%%',
        "flowchart LR",
    ]

    ordered = sorted(groups, key=first_node)
    for group in ordered:
        indent = "    "
        if group:
            out.append(f"    subgraph {group}")
            out.append("        direction TB")
            indent = "        "
        for node, name in sorted(groups[group], key=lambda p: int(p[0][1:])):
            out.append(f"{indent}{shape(node, name)}")
        if group:
            out.append("    end")

    stage_of = {}
    for group in ordered:
        for node, _name in groups[group]:
            stage_of[node] = group

    out.append("")
    crossing = []
    for index, (src, dst) in enumerate(edges):
        out.append(f"    {ids[src]} --> {ids[dst]}")
        if stage_of.get(src) != stage_of.get(dst):
            crossing.append(index)

    out.append("")
    for group in ordered:
        if not group:
            continue
        fill, stroke, _text = _stage_colour(group)
        out.append(f"    style {group} fill:{fill}22,stroke:{stroke},"
                   f"stroke-width:1px,stroke-dasharray:4 3,color:{stroke}")

    out.append("")
    for index, group in enumerate(ordered):
        fill, stroke, text = _stage_colour(group)
        klass = f"stage{index}"
        out.append(f"    classDef {klass} fill:{fill},stroke:{stroke},"
                   f"stroke-width:1.5px,color:{text}")
        members = ",".join(ids[node] for node, _name
                           in sorted(groups[group], key=lambda p: int(p[0][1:])))
        out.append(f"    class {members} {klass}")

    out.append("")
    out.append("    linkStyle default stroke:#cbd5e1,stroke-width:1.5px")
    if crossing:
        # A hand-off between stages is the edge worth following, so draw it
        # darker than the wiring inside a stage.
        out.append(f"    linkStyle {','.join(str(i) for i in crossing)} "
                   "stroke:#475569,stroke-width:2px")

    names = sorted({name for _node, name in processes.items()})
    return "\n".join(out) + "\n", names


# ── The overall architecture diagram ────────────────────────────────────────
#
# Not a DAG: this one is the shape of the code rather than of a run. It is read
# out of main.nf's router and the include statements, so it cannot drift either.
#
# The three layers -- workflows, subworkflows, modules -- form a dense
# many-to-many graph: seven workflows share six stages, and thirty-odd modules
# are pulled in by both. Drawn as arrows that is a hairball, so only the one
# relation that is a tree is drawn as arrows (the router choosing a workflow).
# Every other relation is written into the box that owns it and repeated as
# colour, which costs nothing to route and never crosses.

SHARED_COLOUR = ("#f8fafc", "#94a3b8", "#334155")   # a module more than one owner calls

ROUTER_CASE = re.compile(r"case\s+'([^']+)'\s*:\s*\n\s*(\w+)\s*\(", re.M)
INCLUDE = re.compile(r"include\s*\{\s*([\w\s;]+?)\s*\}\s*from\s*'([^']+)'")


def _declared(path):
    """Workflow names declared in one file, with the comment above each."""
    lines = open(path).read().split("\n")
    found = {}
    for index, line in enumerate(lines):
        match = re.match(r"^workflow\s+(\w+)\s*\{", line)
        if match:
            found[match.group(1)] = _comment_above(lines, index)
    return found


def _includes(path):
    """(source name, exported name, source file) for every include in a file.

    `include { a; b }` is two entries, and `include { X as Y }` is one entry
    whose source name is X and whose exported name is Y -- the distinction
    matters, because the source name says which stage is being reused and the
    exported name is how many steps that costs.
    """
    out = []
    for names, source in INCLUDE.findall(open(path).read()):
        for part in names.split(";"):
            part = part.strip()
            if not part:
                continue
            bits = re.split(r"\s+as\s+", part)
            out.append((bits[0].strip(), bits[-1].strip(), source))
    return out


def _module_of(source):
    """'../modules/utils/mash/main.nf' → 'utils/mash'."""
    return os.path.dirname(source).split("modules/", 1)[1]


def _stage_rank(name):
    """Pipeline order for a stage, so the stage column reads like a run."""
    for index, (prefixes, _colour) in enumerate(STAGE_COLOURS):
        for prefix in prefixes:
            if name == prefix or name.startswith(prefix + "_"):
                return index
    return len(STAGE_COLOURS)


def _router_map():
    """--workflow token → the workflow it calls, from main.nf's switch."""
    text = open(os.path.join(REPO, "main.nf")).read()
    return {token: name for token, name in ROUTER_CASE.findall(text)}


def _read_layer(folder):
    """Parse one of workflows/ or subworkflows/ into units and helper files."""
    units, helpers = {}, {}
    for name in sorted(os.listdir(os.path.join(REPO, folder))):
        if not name.endswith(".nf"):
            continue
        path = os.path.join(REPO, folder, name)
        includes = _includes(path)
        declared = _declared(path)
        for unit, summary in declared.items():
            modules = {}
            for _src, exported, source in includes:
                if "/modules/" in source:
                    modules.setdefault(_module_of(source), set()).add(exported)
            units[unit] = {
                "summary": summary,
                "includes": includes,
                "modules": modules,
            }
        if not declared:
            # A Groovy helper rather than a workflow -- read_input, mtx_common.
            lines = open(path).read().split("\n")
            for index, line in enumerate(lines):
                if re.match(r"^def\s+(\w+)\s*\(", line):
                    helpers[name] = _comment_above(lines, index)
                    break
    return units, helpers


def _module_groups(owners_of, order):
    """Collapse modules into one box per set of owners, in reading order.

    Thirty-four module directories in one column is a wall; the same modules
    grouped by who calls them is a dozen boxes that each answer "what is this
    for". Modules with one owner take that owner's colour, so the relation is
    visible without an arrow.
    """
    by_owners = {}
    for module, owners in owners_of.items():
        by_owners.setdefault(frozenset(owners), []).append(module)
    rank = {name: index for index, name in enumerate(order)}
    groups = []
    for owners, modules in by_owners.items():
        listed = sorted(owners, key=lambda o: rank.get(o, len(rank)))
        groups.append((listed, sorted(modules)))
    return sorted(groups, key=lambda g: (len(g[0]) > 1, rank.get(g[0][0], 99), g[1]))


def architecture_diagram():
    """The four layers of the code, and what each one is for.

    Read out of main.nf's router and the include statements: which workflow
    each `--workflow` token reaches, which stages that workflow reuses, and
    which modules define the processes behind them.
    """
    router = _router_map()
    token_of = {name: token for token, name in router.items()}

    stages, helpers = _read_layer("subworkflows")
    workflows, _none = _read_layer("workflows")

    flow_order = sorted(workflows, key=lambda w: (w not in token_of, token_of.get(w, w)))
    stage_order = sorted(stages, key=lambda s: _stage_rank(s))
    order = flow_order + stage_order

    # Who calls what. A stage is named by its source name at the include, so an
    # aliased reuse (`QUALITY_CONTROL as QC_MGX`) still counts as that stage.
    callers = {name: [] for name in list(stages) + list(helpers)}
    for wf in flow_order:
        for src, _exported, source in workflows[wf]["includes"]:
            if "/subworkflows/" in source:
                key = src if src in stages else os.path.basename(source)
                if key in callers and wf not in callers[key]:
                    callers[key].append(wf)

    # And which workflows a stage chains back into -- REPORTING runs the
    # reporting workflows at the end of a read-based run.
    chains = {}
    for stage in stage_order:
        chained = [src for src, _e, source in stages[stage]["includes"]
                   if "/workflows/" in source]
        if chained:
            chains[stage] = sorted(set(chained))

    owners_of = {}
    for name in order:
        unit = workflows.get(name) or stages[name]
        for module in unit["modules"]:
            owners_of.setdefault(module, set()).add(name)
    groups = _module_groups(owners_of, order)

    out = [
        '%%{init: {"flowchart": {"curve": "step", "nodeSpacing": 26,',
        '                        "rankSpacing": 110, "padding": 10,',
        '                        "useMaxWidth": true}}}%%',
        "flowchart LR",
    ]

    # ── 1 · the router ──────────────────────────────────────────────────
    tokens = " · ".join(f"{t}" for t in sorted(router))
    out += [
        '    subgraph L1["1 · ENTRY — main.nf"]',
        "        direction TB",
        f'        main_nf(["<b>main.nf</b><br/><i>the only entry point</i><br/>'
        f'Reads --workflow and calls one<br/>workflow. Runs no step itself.'
        f'<br/><br/>{_wrap(tokens, 40, 2)}"])',
        '        howto["<b>How to read this</b><br/>'
        'Arrows are drawn for one relation only:<br/>'
        'which workflow a --workflow token runs.<br/>'
        'Layers 2 → 4 are composition, not flow —<br/>'
        'each box names who calls it, and repeats<br/>'
        'that owner as its colour."]',
        "    end",
        '    subgraph L2["2 · WORKFLOWS — workflows/*.nf"]',
        "        direction TB",
    ]

    # ── 2 · one workflow per --workflow ─────────────────────────────────
    for wf in flow_order:
        token = token_of.get(wf, "")
        summary = _wrap(re.sub(r'["<>`]', "", workflows[wf]["summary"]), 36, 3)
        used = sorted({s for s, _e, src in workflows[wf]["includes"]
                       if s in stages}, key=_stage_rank)
        direct = sum(len(v) for v in workflows[wf]["modules"].values())
        detail = []
        if used:
            # One stage per line: the names are long, and a wrapped run of them
            # makes the box wider than the whole rest of the column.
            detail.append(f"<i>wires {len(used)} stage{'s' if len(used) != 1 else ''}:</i>")
            detail += [f"· {stage}" for stage in used]
        if direct:
            detail.append(f"<i>+ {direct} step{'s' if direct != 1 else ''} of its own</i>")
        tail = ("<br/>" + "<br/>".join(detail)) if detail else ""
        flag = f'<br/><i>--workflow {token}</i>' if token else ""
        out.append(f'        {wf}("<b>{wf}</b>{flag}<br/>{summary}{tail}")')
    out += ["    end",
            '    subgraph L3["3 · STAGES — subworkflows/*.nf"]',
            "        direction TB"]

    # ── 3 · the reusable stages ─────────────────────────────────────────
    for stage in stage_order:
        summary = _wrap(re.sub(r'["<>`]', "", stages[stage]["summary"]), 36, 3)
        count = sum(len(v) for v in stages[stage]["modules"].values())
        detail = [f"<i>called by:</i> {', '.join(callers[stage]) or 'nothing yet'}"]
        if count:
            detail.append(f"<i>{count} step{'s' if count != 1 else ''} "
                          f"from {len(stages[stage]['modules'])} module"
                          f"{'s' if len(stages[stage]['modules']) != 1 else ''}</i>")
        if stage in chains:
            detail.append(f"<i>chains back into:</i> {' + '.join(chains[stage])}")
        body = "<br/>".join(_wrap(d, 44, 3) for d in detail)
        out.append(f'        {stage}("<b>{stage}</b><br/>{summary}<br/>{body}")')

    for name, summary in sorted(helpers.items()):
        ident = name.replace(".nf", "")
        out.append(f'        {ident}["<b>{name}</b> — <i>helper, not a stage</i><br/>'
                   f'{_wrap(re.sub(chr(34), "", summary), 40, 2)}<br/>'
                   f'<i>called by:</i> {", ".join(callers[name]) or "nothing"}"]')
    out += ["    end",
            '    subgraph L4["4 · STEPS — modules/**/main.nf"]',
            "        direction TB"]

    # ── 4 · the modules, grouped by who calls them ──────────────────────
    for index, (owners, modules) in enumerate(groups):
        lines = []
        for module in modules:
            names = set()
            for owner in owners:
                unit = workflows.get(owner) or stages[owner]
                names |= unit["modules"].get(module, set())
            lines.append(f"{module} <i>×{len(names)}</i>")
        head = (f"<b>for {owners[0]}</b>" if len(owners) == 1
                else f"<b>shared by {', '.join(owners)}</b>")
        out.append(f'        mods{index}["{head}<br/>{"<br/>".join(lines)}"]')
    out.append("    end")

    # ── the only arrows: the router's choice ────────────────────────────
    out.append("")
    for wf in flow_order:
        out.append(f"    main_nf --> {wf}")

    # Two invisible links pin the four layers left to right; nothing else
    # joins them, and without one the columns would stack rather than line up.
    out.append("")
    out.append(f"    {flow_order[-1]} ~~~ {stage_order[0]}")
    out.append(f"    {stage_order[-1]} ~~~ mods0")

    out.append("")
    for layer in ("L1", "L2", "L3", "L4"):
        out.append(f"    style {layer} fill:#f8fafc00,stroke:#cbd5e1,"
                   "stroke-width:1px,stroke-dasharray:6 4,color:#475569")

    out.append("")
    out.append("    classDef router fill:#e2e8f0,stroke:#475569,stroke-width:2px,color:#0f172a")
    out.append("    class main_nf router")
    out.append("    classDef note fill:#ffffff,stroke:#cbd5e1,stroke-width:1px,"
               "color:#64748b,stroke-dasharray:3 3")
    out.append("    class howto note")

    # Colour is the owner: a workflow, or the stage a module belongs to.
    for index, name in enumerate(order):
        fill, stroke, text = _stage_colour(name)
        out.append(f"    classDef arch{index} fill:{fill},stroke:{stroke},"
                   f"stroke-width:1.5px,color:{text}")
        out.append(f"    class {name} arch{index}")

    for index, (owners, _modules) in enumerate(groups):
        fill, stroke, text = (_stage_colour(owners[0]) if len(owners) == 1
                              else SHARED_COLOUR)
        out.append(f"    classDef mod{index} fill:{fill}99,stroke:{stroke},"
                   f"stroke-width:1px,stroke-dasharray:0,color:{text}")
        out.append(f"    class mods{index} mod{index}")

    if helpers:
        idents = ",".join(sorted(n.replace(".nf", "") for n in helpers))
        out.append("    classDef helper fill:#ffffff,stroke:#cbd5e1,"
                   "stroke-width:1px,color:#475569")
        out.append(f"    class {idents} helper")

    out.append("")
    out.append("    linkStyle default stroke:#94a3b8,stroke-width:1.5px")
    # The invisible layer pins are the last two links.
    first_pin = len(flow_order)
    out.append(f"    linkStyle {first_pin},{first_pin + 1} stroke-width:0px")
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

    architecture = architecture_diagram()
    with open(os.path.join(diagrams, "architecture.mmd"), "w") as handle:
        handle.write(architecture)

    rendered = {}
    for workflow, title, args in WORKFLOWS:
        raw = os.path.join(stubs["work"], f"{workflow}.raw.mmd")
        if os.path.exists(raw):
            os.remove(raw)
        mermaid, names = simplify(render_dag(workflow, args, raw, stubs), catalog)
        with open(os.path.join(diagrams, f"{workflow}.mmd"), "w") as handle:
            handle.write(mermaid)
        rendered[workflow] = (title, mermaid, names)

    with open(os.path.join(outdir, "workflow_reference.md"), "w") as handle:
        handle.write(reference_page(rendered, catalog, architecture))


def reference_page(rendered, catalog, architecture):
    """The generated markdown: one diagram plus one step table per workflow."""
    out = [
        "# Workflow reference",
        "",
        "**Generated — do not edit.** Regenerate with `bin/make_diagrams.py`;",
        "CI checks this file with `bin/make_diagrams.py --check`.",
        "",
        "Every diagram is Nextflow's own DAG for that workflow, taken from",
        "`nextflow run -preview -with-dag`, with the value-channel and operator",
        "nodes contracted away so only the steps remain. Each step's description",
        "is the comment above its `process` in `modules/`.",
        "",
        "How to read one:",
        "",
        "* **Stages run left to right**, steps within a stage top to bottom. A",
        "  dashed box is one subworkflow.",
        "* **Colour is the stage**, and is the same in every diagram: quality",
        "  control blue, taxonomy green, function purple, viral orange, strain",
        "  teal, assembly amber, vis pink, stats indigo, and the workflow's own",
        "  steps grey.",
        "* **Shape marks the ends of the flow**: a rounded-end box starts a",
        "  workflow, a square-cornered box finishes one, and everything between",
        "  them has soft corners.",
        "* **A darker arrow crosses between stages**; the pale ones are wiring",
        "  inside a stage. Where each step publishes its output is in the table",
        "  below the diagram, not in the picture.",
        "",
        "Optional stages that are off by default (`--run_viral_profiling`,",
        "`--run_strain_profiling`) are drawn as if enabled, so the diagram shows",
        "everything a workflow can do.",
        "",
    ]

    out += [
        "## How the pieces fit",
        "",
        "Four layers, each with one job:",
        "",
        "| Layer | Lives in | What it is | What it may contain |",
        "|---|---|---|---|",
        "| 1 · Entry | `main.nf` | The router. Reads `--workflow` and calls "
        "exactly one workflow. | No steps of its own. |",
        "| 2 · Workflow | `workflows/*.nf` | One complete pipeline per "
        "`--workflow` token — the thing a user runs. | Stages, and steps of "
        "its own. |",
        "| 3 · Stage | `subworkflows/*.nf` | A reusable unit of pipeline, "
        "shared by several workflows. | Steps, and other stages. |",
        "| 4 · Step | `modules/**/main.nf` | One tool invocation. **Every "
        "`process` is defined here and nowhere else.** | Nothing — it is the "
        "bottom. |",
        "",
        "Two files under `subworkflows/` are not stages at all: `read_input.nf`",
        "and `mtx_common.nf` hold plain Groovy functions, and the diagram marks",
        "them as helpers.",
        "",
        "The diagram below draws arrows for one relation only — which workflow",
        "each `--workflow` token runs — because that is the only relation that",
        "is a tree. The rest is many-to-many (three workflows share the same",
        "five stages; a module such as `utils/version_log` is called by four",
        "workflows), so drawing it as arrows produces a hairball. Instead each",
        "box names who calls it, and repeats that owner as its colour: the",
        "modules in layer 4 are grouped by which workflow or stage pulls them",
        "in, and take that owner's colour. `×n` is how many processes that",
        "module contributes.",
        "",
        "Every box carries the comment written above its `workflow` block, so",
        "the picture cannot drift from the code.",
        "",
        "```mermaid",
        architecture.rstrip(),
        "```",
        "",
        "| Workflow | `--workflow` | What it does | Steps |",
        "|---|---|---|---|",
    ]
    for workflow, _title, _args in WORKFLOWS:
        title, _mermaid, names = rendered[workflow]
        out.append(f"| [{workflow}](#{workflow}) | `{workflow}` | {title} | {len(names)} |")
    out.append("")

    for workflow, _title, _args in WORKFLOWS:
        title, mermaid, names = rendered[workflow]
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
            print(f"Wrote {len(WORKFLOWS) + 1} diagrams to "
                  f"{os.path.join(docs, 'diagrams')} (one per workflow, plus architecture)")
            return

        stale = []
        for name in ["workflow_reference.md",
                     os.path.join("diagrams", "architecture.mmd")] + [
            os.path.join("diagrams", f"{w}.mmd") for w, _t, _a in WORKFLOWS
        ]:
            new, old = os.path.join(target, name), os.path.join(docs, name)
            if not os.path.exists(old) or not filecmp.cmp(new, old, shallow=False):
                stale.append(os.path.join("docs", name))
        if stale:
            sys.exit("ERROR: these are out of date with the pipeline:\n  " +
                     "\n  ".join(stale) +
                     "\nRegenerate with: bin/make_diagrams.py")
        print(f"Up to date: docs/workflow_reference.md, the architecture diagram "
              f"and {len(WORKFLOWS)} workflow diagrams.")


if __name__ == "__main__":
    main()
