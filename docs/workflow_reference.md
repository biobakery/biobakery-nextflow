# Workflow reference

**Generated — do not edit.** Regenerate with `bin/make_diagrams.py`;
CI checks this file with `bin/make_diagrams.py --check`.

Every diagram is Nextflow's own DAG for that workflow, taken from
`nextflow run -preview -with-dag`, with the value-channel and operator
nodes contracted away so only the steps remain. Each step's description
is the comment above its `process` in `modules/`.

How to read one:

* **Stages run left to right**, steps within a stage top to bottom. A
  dashed box is one subworkflow.
* **Colour is the stage**, and is the same in every diagram: quality
  control blue, taxonomy green, function purple, viral orange, strain
  teal, assembly amber, vis pink, stats indigo, and the workflow's own
  steps grey.
* **Shape marks the ends of the flow**: a rounded-end box starts a
  workflow, a square-cornered box finishes one, and everything between
  them has soft corners.
* **A darker arrow crosses between stages**; the pale ones are wiring
  inside a stage. Where each step publishes its output is in the table
  below the diagram, not in the picture.

Optional stages that are off by default (`--run_viral_profiling`,
`--run_strain_profiling`) are drawn as if enabled, so the diagram shows
everything a workflow can do.

## How the pieces fit

Four layers, each with one job:

| Layer | Lives in | What it is | What it may contain |
|---|---|---|---|
| 1 · Entry | `main.nf` | The router. Reads `--workflow` and calls exactly one workflow. | No steps of its own. |
| 2 · Workflow | `workflows/*.nf` | One complete pipeline per `--workflow` token — the thing a user runs. | Stages, and steps of its own. |
| 3 · Stage | `subworkflows/*.nf` | A reusable unit of pipeline, shared by several workflows. | Steps, and other stages. |
| 4 · Step | `modules/**/main.nf` | One tool invocation. **Every `process` is defined here and nowhere else.** | Nothing — it is the bottom. |

Two files under `subworkflows/` are not stages at all: `read_input.nf`
and `mtx_common.nf` hold plain Groovy functions, and the diagram marks
them as helpers.

The diagram below reads top to bottom, one row per layer. It draws
arrows for one relation only — which workflow each `--workflow` token
runs — because that is the only relation that is a tree. The rest is
many-to-many (three workflows share the same five stages; a module
such as `utils/version_log` is called by four workflows), so drawing
it as arrows produces a hairball. Instead each box names who calls it
and repeats that owner as its colour: the modules in row 4 are grouped
by the workflow or stage that pulls them in and take its colour, with
`×n` the number of steps that module contributes. The modules with
more than one caller have no single colour to take, so they share one
neutral box that names each one's callers.

Every box carries the comment written above its `workflow` block, so
the picture cannot drift from the code.

```mermaid
%%{init: {"flowchart": {"curve": "step", "nodeSpacing": 30,
                        "rankSpacing": 75, "padding": 12}}}%%
flowchart TB
    subgraph L1["<b>1 · ENTRY</b> — main.nf<br/><i>Picks the pipeline. Runs no step of its own.</i>"]
        direction LR
        main_nf(["<b>main.nf</b><br/>Reads <i>--workflow</i> and calls<br/>exactly one workflow below.<br/><br/>16s · assembly · mgx · mgx_mtx · mtx ·<br/>stats · vis"])
        howto["<b>How to read this</b><br/>Arrows are drawn for one relation only — which<br/>workflow a --workflow token runs. Layers 2 → 4 are<br/>composition, not flow: each box names who calls it,<br/>and repeats that owner as its colour. <i>×n</i> is the<br/>number of steps a module contributes to that owner."]
    end
    subgraph L2["<b>2 · WORKFLOWS</b> — workflows/*.nf<br/><i>One complete pipeline per --workflow token — the thing a user runs. Wires stages, and may run steps of its own.</i>"]
        direction LR
        SIXTEENS("<b>SIXTEENS</b><br/><i>--workflow 16s</i><br/>16S rRNA amplicon workflow — stub")
        ASSEMBLY("<b>ASSEMBLY</b><br/><i>--workflow assembly</i><br/>Full MAG assembly → binning → SGB<br/>clustering pipeline.<br/><i>wires 1 stage</i><br/>· QUALITY_CONTROL<br/><i>+ 17 steps of its own</i>")
        MGX("<b>MGX</b><br/><i>--workflow mgx</i><br/>Whole Metagenome Shotgun (MGX)<br/>workflow<br/><i>wires 6 stages</i><br/>· QUALITY_CONTROL<br/>· TAXONOMIC_PROFILING<br/>· FUNCTIONAL_PROFILING<br/>· VIRAL_PROFILING<br/>· STRAIN_PROFILING<br/>· REPORTING<br/><i>+ 3 steps of its own</i>")
        MGX_MTX("<b>MGX_MTX</b><br/><i>--workflow mgx_mtx</i><br/>Paired whole metagenome +<br/>metatranscriptome workflow.<br/><i>wires 5 stages</i><br/>· QUALITY_CONTROL<br/>· TAXONOMIC_PROFILING<br/>· FUNCTIONAL_PROFILING<br/>· STRAIN_PROFILING<br/>· REPORTING<br/><i>+ 5 steps of its own</i>")
        MTX("<b>MTX</b><br/><i>--workflow mtx</i><br/>Whole Metatranscriptome (MTX)<br/>workflow.<br/><i>wires 5 stages</i><br/>· QUALITY_CONTROL<br/>· TAXONOMIC_PROFILING<br/>· FUNCTIONAL_PROFILING<br/>· STRAIN_PROFILING<br/>· REPORTING<br/><i>+ 3 steps of its own</i>")
        STATS("<b>STATS</b><br/><i>--workflow stats</i><br/>Statistics workflow — the Nextflow<br/>port of biobakery_workflows stats.<br/><i>+ 14 steps of its own</i>")
        VIS("<b>VIS</b><br/><i>--workflow vis</i><br/>Visualization workflow — the<br/>Nextflow port of<br/>biobakery_workflows vis.<br/><i>+ 7 steps of its own</i>")
    end
    subgraph L3["<b>3 · STAGES</b> — subworkflows/*.nf<br/><i>A reusable unit of pipeline, shared by several workflows. Wires steps, and may chain another workflow.</i>"]
        direction LR
        QUALITY_CONTROL("<b>QUALITY_CONTROL</b><br/>Quality control subworkflow: host<br/>decontamination + trimming via<br/>KneadData<br/><i>called by</i><br/>· ASSEMBLY<br/>· MGX<br/>· MGX_MTX<br/>· MTX<br/><i>3 steps from 1 module</i>")
        TAXONOMIC_PROFILING("<b>TAXONOMIC_PROFILING</b><br/>Taxonomic profiling subworkflow:<br/>MetaPhlAn per sample + merged<br/>table<br/><i>called by</i><br/>· MGX<br/>· MGX_MTX<br/>· MTX<br/><i>4 steps from 1 module</i>")
        FUNCTIONAL_PROFILING("<b>FUNCTIONAL_PROFILING</b><br/>Functional profiling subworkflow:<br/>HUMAnN, then the three feature<br/>types<br/><i>called by</i><br/>· MGX<br/>· MGX_MTX<br/>· MTX<br/><i>10 steps from 5 modules</i>")
        VIRAL_PROFILING("<b>VIRAL_PROFILING</b><br/>Viral profiling subworkflow:<br/>BAQLaVa<br/><i>called by</i><br/>· MGX<br/><i>1 step from 1 module</i>")
        STRAIN_PROFILING("<b>STRAIN_PROFILING</b><br/>Strain profiling subworkflow:<br/>StrainPhlAn SGB-level<br/><i>called by</i><br/>· MGX<br/>· MGX_MTX<br/>· MTX<br/><i>2 steps from 1 module</i>")
        REPORTING("<b>REPORTING</b><br/>Run vis and/or stats at the end of<br/>a read-based workflow.<br/><i>called by</i><br/>· MGX<br/>· MGX_MTX<br/>· MTX<br/><i>chains STATS + VIS</i>")
        mtx_common["<b>mtx_common.nf</b><br/><i>Groovy helper, not a stage</i><br/>The KneadData reference database<br/>set for metatranscriptome reads.<br/><i>called by</i><br/>· MGX_MTX<br/>· MTX"]
        read_input["<b>read_input.nf</b><br/><i>Groovy helper, not a stage</i><br/>Build an input read channel,<br/>detecting library layout from the<br/>filenames<br/><i>called by</i><br/>· ASSEMBLY<br/>· MGX<br/>· MGX_MTX<br/>· MTX"]
    end
    subgraph L4["<b>4 · STEPS</b> — modules/**/main.nf<br/><i>One tool invocation each. Every process is defined here and nowhere else — grouped below by the workflow or stage that calls it.</i>"]
        direction LR
        mods0["<b>for ASSEMBLY</b><br/>assembly/megahit <i>×1</i><br/>binning/metabat2 <i>×1</i><br/>phylogenomics/phylophlan_metagenomic <i>×2</i><br/>qc/checkm2 <i>×4</i><br/>utils/abundance <i>×1</i><br/>utils/align_and_depth <i>×1</i><br/>utils/mash <i>×6</i>"]
        mods1["<b>for MGX_MTX</b><br/>utils/rna_dna_norm <i>×1</i>"]
        mods2["<b>for STATS</b><br/>stats/beta_diversity <i>×2</i><br/>stats/covariate_equation <i>×1</i><br/>stats/halla <i>×2</i><br/>stats/maaslin2 <i>×1</i><br/>stats/mantel <i>×1</i><br/>stats/report <i>×1</i><br/>stats/stratified_pathways <i>×2</i>"]
        mods3["<b>for VIS</b><br/>vis/add_ec_names <i>×1</i><br/>vis/alpha_diversity <i>×1</i><br/>vis/report <i>×1</i>"]
        mods4["<b>for QUALITY_CONTROL</b><br/>kneaddata <i>×3</i>"]
        mods5["<b>for TAXONOMIC_PROFILING</b><br/>metaphlan <i>×4</i>"]
        mods6["<b>for FUNCTIONAL_PROFILING</b><br/>humann <i>×1</i><br/>utils/humann_merge <i>×5</i><br/>utils/humann_regroup <i>×2</i><br/>utils/humann_rename <i>×1</i><br/>utils/humann_renorm <i>×1</i>"]
        mods7["<b>for VIRAL_PROFILING</b><br/>viral/baqlava <i>×1</i>"]
        mods8["<b>for STRAIN_PROFILING</b><br/>strainphlan <i>×2</i>"]
        mods_shared["<b>called by more than one</b><br/>stats/feature_table<br/>&nbsp;&nbsp;<i>STATS, VIS</i><br/>utils/archive<br/>&nbsp;&nbsp;<i>STATS, VIS</i><br/>utils/merge_pairs<br/>&nbsp;&nbsp;<i>MGX, MGX_MTX, MTX</i><br/>utils/report_input<br/>&nbsp;&nbsp;<i>MGX, MGX_MTX, MTX</i><br/>utils/version_log<br/>&nbsp;&nbsp;<i>ASSEMBLY, MGX, MGX_MTX, MTX</i><br/>vis/identify_inputs<br/>&nbsp;&nbsp;<i>STATS, VIS</i>"]
    end

    main_nf --> SIXTEENS
    main_nf --> ASSEMBLY
    main_nf --> MGX
    main_nf --> MGX_MTX
    main_nf --> MTX
    main_nf --> STATS
    main_nf --> VIS

    MGX_MTX ~~~ VIRAL_PROFILING
    VIRAL_PROFILING ~~~ mods0

    style L1 fill:#f8fafc00,stroke:#cbd5e1,stroke-width:1px,stroke-dasharray:6 4,color:#334155
    style L2 fill:#f8fafc00,stroke:#cbd5e1,stroke-width:1px,stroke-dasharray:6 4,color:#334155
    style L3 fill:#f8fafc00,stroke:#cbd5e1,stroke-width:1px,stroke-dasharray:6 4,color:#334155
    style L4 fill:#f8fafc00,stroke:#cbd5e1,stroke-width:1px,stroke-dasharray:6 4,color:#334155

    classDef router fill:#e2e8f0,stroke:#475569,stroke-width:2px,color:#0f172a
    class main_nf router
    classDef note fill:#ffffff,stroke:#cbd5e1,stroke-width:1px,color:#64748b,stroke-dasharray:3 3
    class howto note
    classDef arch0 fill:#f1f5f9,stroke:#94a3b8,stroke-width:1.5px,color:#334155
    class SIXTEENS arch0
    classDef arch1 fill:#fef3c7,stroke:#d97706,stroke-width:1.5px,color:#78350f
    class ASSEMBLY arch1
    classDef arch2 fill:#f1f5f9,stroke:#94a3b8,stroke-width:1.5px,color:#334155
    class MGX arch2
    classDef arch3 fill:#f1f5f9,stroke:#94a3b8,stroke-width:1.5px,color:#334155
    class MGX_MTX arch3
    classDef arch4 fill:#f1f5f9,stroke:#94a3b8,stroke-width:1.5px,color:#334155
    class MTX arch4
    classDef arch5 fill:#e0e7ff,stroke:#6366f1,stroke-width:1.5px,color:#312e81
    class STATS arch5
    classDef arch6 fill:#fce7f3,stroke:#ec4899,stroke-width:1.5px,color:#831843
    class VIS arch6
    classDef arch7 fill:#dbeafe,stroke:#3b82f6,stroke-width:1.5px,color:#1e3a8a
    class QUALITY_CONTROL arch7
    classDef arch8 fill:#dcfce7,stroke:#22c55e,stroke-width:1.5px,color:#14532d
    class TAXONOMIC_PROFILING arch8
    classDef arch9 fill:#ede9fe,stroke:#8b5cf6,stroke-width:1.5px,color:#4c1d95
    class FUNCTIONAL_PROFILING arch9
    classDef arch10 fill:#ffedd5,stroke:#f97316,stroke-width:1.5px,color:#7c2d12
    class VIRAL_PROFILING arch10
    classDef arch11 fill:#ccfbf1,stroke:#14b8a6,stroke-width:1.5px,color:#134e4a
    class STRAIN_PROFILING arch11
    classDef arch12 fill:#f1f5f9,stroke:#94a3b8,stroke-width:1.5px,color:#334155
    class REPORTING arch12
    classDef mod0 fill:#fef3c799,stroke:#d97706,stroke-width:1px,color:#78350f
    class mods0 mod0
    classDef mod1 fill:#f1f5f999,stroke:#94a3b8,stroke-width:1px,color:#334155
    class mods1 mod1
    classDef mod2 fill:#e0e7ff99,stroke:#6366f1,stroke-width:1px,color:#312e81
    class mods2 mod2
    classDef mod3 fill:#fce7f399,stroke:#ec4899,stroke-width:1px,color:#831843
    class mods3 mod3
    classDef mod4 fill:#dbeafe99,stroke:#3b82f6,stroke-width:1px,color:#1e3a8a
    class mods4 mod4
    classDef mod5 fill:#dcfce799,stroke:#22c55e,stroke-width:1px,color:#14532d
    class mods5 mod5
    classDef mod6 fill:#ede9fe99,stroke:#8b5cf6,stroke-width:1px,color:#4c1d95
    class mods6 mod6
    classDef mod7 fill:#ffedd599,stroke:#f97316,stroke-width:1px,color:#7c2d12
    class mods7 mod7
    classDef mod8 fill:#ccfbf199,stroke:#14b8a6,stroke-width:1px,color:#134e4a
    class mods8 mod8
    classDef modshared fill:#f8fafc,stroke:#94a3b8,stroke-width:1px,stroke-dasharray:4 3,color:#334155
    class mods_shared modshared
    classDef helper fill:#ffffff,stroke:#cbd5e1,stroke-width:1px,color:#475569
    class mtx_common,read_input helper

    linkStyle default stroke:#94a3b8,stroke-width:1.5px
    linkStyle 7,8 stroke-width:0px
```

| Workflow | `--workflow` | What it does | Steps |
|---|---|---|---|
| [mgx](#mgx) | `mgx` | Whole metagenome shotgun | 28 |
| [mtx](#mtx) | `mtx` | Whole metatranscriptome shotgun | 27 |
| [mgx_mtx](#mgx_mtx) | `mgx_mtx` | Paired metagenome + metatranscriptome | 28 |
| [assembly](#assembly) | `assembly` | MAG assembly, binning and SGB clustering | 20 |
| [vis](#vis) | `vis` | Visualisation report | 6 |
| [stats](#stats) | `stats` | Statistical analysis report | 13 |

## mgx

Whole metagenome shotgun.

```mermaid
%%{init: {"flowchart": {"curve": "basis", "nodeSpacing": 40,
                        "rankSpacing": 70, "padding": 8}}}%%
flowchart LR
    subgraph QUALITY_CONTROL
        direction TB
        paired_end_kneaddata(["<b>paired_end_kneaddata</b><br/>KneadData QC — paired-end<br/>reads"])
        single_end_kneaddata(["<b>single_end_kneaddata</b><br/>KneadData QC — single-end<br/>reads"])
        kneaddata_read_counts("<b>kneaddata_read_counts</b><br/>Compile the per-sample<br/>KneadData logs into one read…")
    end
    subgraph TAXONOMIC_PROFILING
        direction TB
        metaphlan("<b>metaphlan</b><br/>MetaPhlAn — taxonomic<br/>profiling")
        metaphlan_bzip("<b>metaphlan_bzip</b><br/>Compress MetaPhlAn SAM file<br/>(saves significant disk space)")
        metaphlan_merge("<b>metaphlan_merge</b><br/>Merge per-sample MetaPhlAn<br/>profiles into a single table")
        metaphlan_species_counts("<b>metaphlan_species_counts</b><br/>Count the species called in<br/>each sample, from the merged…")
    end
    subgraph FUNCTIONAL_PROFILING
        direction TB
        humann("<b>humann</b><br/>HUMAnN — functional profiling")
        humann_regroup_ecs("<b>humann_regroup_ecs</b><br/>Regroup UniRef gene families<br/>to level-4 enzyme commission…")
        humann_regroup("<b>humann_regroup</b><br/>Regroup HUMAnN gene families<br/>to a different annotation…")
        humann_rename["<b>humann_rename</b><br/>Rename HUMAnN output features<br/>to human-readable names"]
        humann_join("<b>humann_join</b><br/>Join per-sample HUMAnN tables<br/>of one feature type into a…")
        humann_renorm("<b>humann_renorm</b><br/>Renormalise a per-sample<br/>HUMAnN table from RPK to…")
        humann_join_relab("<b>humann_join_relab</b><br/>Join per-sample HUMAnN tables<br/>of one feature type into a…")
        humann_count_features("<b>humann_count_features</b><br/>Count how many features each<br/>sample has above zero, per…")
        humann_feature_counts_merge("<b>humann_feature_counts_merge</b><br/>Merge the three<br/>per-feature-type count tables…")
        humann_log_counts("<b>humann_log_counts</b><br/>Read and species counts, taken<br/>from the per-sample HUMAnN…")
    end
    subgraph VIRAL_PROFILING
        direction TB
        baqlava["<b>baqlava</b><br/>BAQLaVa — viral profiling"]
    end
    subgraph STRAIN_PROFILING
        direction TB
        sample2markers("<b>sample2markers</b><br/>StrainPhlAn step 1: extract<br/>per-sample strain markers from…")
        strainphlan["<b>strainphlan</b><br/>StrainPhlAn step 2: build<br/>strain phylogeny per clade"]
    end
    subgraph MGX
        direction TB
        stage_report_input("<b>stage_report_input</b><br/>Build a bioBakery-standard<br/>output folder for vis and…")
        version_log(["<b>version_log</b><br/>Capture tool versions,<br/>database paths, and workflow…"])
    end
    subgraph VIS
        direction TB
        identify_inputs("<b>identify_inputs</b><br/>Identify the bioBakery data<br/>files in an input folder.")
        feature_table["<b>feature_table</b><br/>Build one feature table<br/>(taxonomy, pathways or any…"]
        trim_taxonomy["<b>trim_taxonomy</b><br/>Reformat a 16s taxonomy<br/>profile into a feature table."]
        add_ec_names("<b>add_ec_names</b><br/>Add EC names to the EC<br/>abundance table when they are…")
        vis_report("<b>vis_report</b><br/>Render the visualization<br/>report.")
        archive_output["<b>archive_output</b><br/>Archive a report folder."]
    end

    paired_end_kneaddata --> kneaddata_read_counts
    paired_end_kneaddata --> metaphlan
    paired_end_kneaddata --> humann
    paired_end_kneaddata --> baqlava
    single_end_kneaddata --> kneaddata_read_counts
    single_end_kneaddata --> metaphlan
    single_end_kneaddata --> humann
    single_end_kneaddata --> baqlava
    kneaddata_read_counts --> stage_report_input
    metaphlan --> metaphlan_bzip
    metaphlan --> metaphlan_merge
    metaphlan --> humann
    metaphlan --> baqlava
    metaphlan_bzip --> sample2markers
    metaphlan_merge --> metaphlan_species_counts
    metaphlan_merge --> stage_report_input
    metaphlan_species_counts --> stage_report_input
    humann --> humann_regroup_ecs
    humann --> humann_regroup
    humann --> humann_join
    humann --> humann_renorm
    humann --> humann_log_counts
    humann_regroup_ecs --> humann_join
    humann_regroup_ecs --> humann_renorm
    humann_regroup --> humann_rename
    humann_join --> stage_report_input
    humann_renorm --> humann_join_relab
    humann_join_relab --> humann_count_features
    humann_join_relab --> stage_report_input
    humann_count_features --> humann_feature_counts_merge
    humann_count_features --> stage_report_input
    humann_feature_counts_merge --> stage_report_input
    humann_log_counts --> stage_report_input
    sample2markers --> strainphlan
    stage_report_input --> identify_inputs
    stage_report_input --> feature_table
    stage_report_input --> trim_taxonomy
    stage_report_input --> add_ec_names
    stage_report_input --> vis_report
    identify_inputs --> feature_table
    identify_inputs --> trim_taxonomy
    identify_inputs --> add_ec_names
    identify_inputs --> vis_report
    add_ec_names --> vis_report
    vis_report --> archive_output

    style QUALITY_CONTROL fill:#dbeafe22,stroke:#3b82f6,stroke-width:1px,stroke-dasharray:4 3,color:#3b82f6
    style TAXONOMIC_PROFILING fill:#dcfce722,stroke:#22c55e,stroke-width:1px,stroke-dasharray:4 3,color:#22c55e
    style FUNCTIONAL_PROFILING fill:#ede9fe22,stroke:#8b5cf6,stroke-width:1px,stroke-dasharray:4 3,color:#8b5cf6
    style VIRAL_PROFILING fill:#ffedd522,stroke:#f97316,stroke-width:1px,stroke-dasharray:4 3,color:#f97316
    style STRAIN_PROFILING fill:#ccfbf122,stroke:#14b8a6,stroke-width:1px,stroke-dasharray:4 3,color:#14b8a6
    style MGX fill:#f1f5f922,stroke:#94a3b8,stroke-width:1px,stroke-dasharray:4 3,color:#94a3b8
    style VIS fill:#fce7f322,stroke:#ec4899,stroke-width:1px,stroke-dasharray:4 3,color:#ec4899

    classDef stage0 fill:#dbeafe,stroke:#3b82f6,stroke-width:1.5px,color:#1e3a8a
    class paired_end_kneaddata,single_end_kneaddata,kneaddata_read_counts stage0
    classDef stage1 fill:#dcfce7,stroke:#22c55e,stroke-width:1.5px,color:#14532d
    class metaphlan,metaphlan_bzip,metaphlan_merge,metaphlan_species_counts stage1
    classDef stage2 fill:#ede9fe,stroke:#8b5cf6,stroke-width:1.5px,color:#4c1d95
    class humann,humann_regroup_ecs,humann_regroup,humann_rename,humann_join,humann_renorm,humann_join_relab,humann_count_features,humann_feature_counts_merge,humann_log_counts stage2
    classDef stage3 fill:#ffedd5,stroke:#f97316,stroke-width:1.5px,color:#7c2d12
    class baqlava stage3
    classDef stage4 fill:#ccfbf1,stroke:#14b8a6,stroke-width:1.5px,color:#134e4a
    class sample2markers,strainphlan stage4
    classDef stage5 fill:#f1f5f9,stroke:#94a3b8,stroke-width:1.5px,color:#334155
    class stage_report_input,version_log stage5
    classDef stage6 fill:#fce7f3,stroke:#ec4899,stroke-width:1.5px,color:#831843
    class identify_inputs,feature_table,trim_taxonomy,add_ec_names,vis_report,archive_output stage6

    linkStyle default stroke:#cbd5e1,stroke-width:1.5px
    linkStyle 1,2,3,5,6,7,8,11,12,13,15,16,25,28,30,31,32,34,35,36,37,38 stroke:#475569,stroke-width:2px
```

| Step | What it does | Defined in | Publishes to |
|---|---|---|---|
| `add_ec_names` | Add EC names to the EC abundance table when they are missing. | `modules/vis/add_ec_names/main.nf` | `<outdir>/vis/ecs` |
| `archive_output` | Archive a report folder. | `modules/utils/archive/main.nf` | `<outdir>` |
| `baqlava` | BAQLaVa — viral profiling | `modules/viral/baqlava/main.nf` | `<outdir>/baqlava` |
| `feature_table` | Build one feature table (taxonomy, pathways or any other data file). | `modules/stats/feature_table/main.nf` | `<outdir>/stats/features` |
| `humann` | HUMAnN — functional profiling | `modules/humann/main.nf` | `<outdir>/<subdir>humann/<params.humann_version>/main` |
| `humann_count_features` | Count how many features each sample has above zero, per feature type. | `modules/utils/humann_merge/main.nf` | `<outdir>/<subdir>humann/<params.humann_version>/counts` |
| `humann_feature_counts_merge` | Merge the three per-feature-type count tables into one | `modules/utils/humann_merge/main.nf` | `<outdir>/<subdir>humann/<params.humann_version>/counts` |
| `humann_join` | Join per-sample HUMAnN tables of one feature type into a single matrix. | `modules/utils/humann_merge/main.nf` | `<outdir>/<subdir>humann/<params.humann_version>/merged` |
| `humann_join_relab` | Join per-sample HUMAnN tables of one feature type into a single matrix. (`humann_join`, run again as `humann_join_relab`) | `modules/utils/humann_merge/main.nf` | `<outdir>/<subdir>humann/<params.humann_version>/merged` |
| `humann_log_counts` | Read and species counts, taken from the per-sample HUMAnN logs. | `modules/utils/humann_merge/main.nf` | `<outdir>/<subdir>humann/<params.humann_version>/counts` |
| `humann_regroup` | Regroup HUMAnN gene families to a different annotation scheme. | `modules/utils/humann_regroup/main.nf` | `<outdir>/<subdir>humann/<params.humann_version>/regrouped` |
| `humann_regroup_ecs` | Regroup UniRef gene families to level-4 enzyme commission numbers. | `modules/utils/humann_regroup/main.nf` | `<outdir>/<subdir>humann/<params.humann_version>/regrouped` |
| `humann_rename` | Rename HUMAnN output features to human-readable names | `modules/utils/humann_rename/main.nf` | `<outdir>/<subdir>humann/<params.humann_version>/renamed` |
| `humann_renorm` | Renormalise a per-sample HUMAnN table from RPK to relative abundance. | `modules/utils/humann_renorm/main.nf` | `<outdir>/<subdir>humann/<params.humann_version>/relab/<feature>` |
| `identify_inputs` | Identify the bioBakery data files in an input folder. | `modules/vis/identify_inputs/main.nf` | `<outdir>/<report_type>` |
| `kneaddata_read_counts` | Compile the per-sample KneadData logs into one read count table. | `modules/kneaddata/main.nf` | `<outdir>/<subdir>kneaddata/merged` |
| `metaphlan` | MetaPhlAn — taxonomic profiling | `modules/metaphlan/main.nf` | `<outdir>/<subdir>metaphlan/<params.metaphlan_index>` |
| `metaphlan_bzip` | Compress MetaPhlAn SAM file (saves significant disk space) | `modules/metaphlan/main.nf` | `<outdir>/<subdir>metaphlan/bzip` |
| `metaphlan_merge` | Merge per-sample MetaPhlAn profiles into a single table | `modules/metaphlan/main.nf` | `<outdir>/<subdir>metaphlan` |
| `metaphlan_species_counts` | Count the species called in each sample, from the merged profile. | `modules/metaphlan/main.nf` | `<outdir>/<subdir>metaphlan/merged` |
| `paired_end_kneaddata` | KneadData QC — paired-end reads | `modules/kneaddata/main.nf` | `<outdir>/<subdir>kneaddata` |
| `sample2markers` | StrainPhlAn step 1: extract per-sample strain markers from MetaPhlAn SAM output | `modules/strainphlan/main.nf` | `<outdir>/strainphlan/markers` |
| `single_end_kneaddata` | KneadData QC — single-end reads | `modules/kneaddata/main.nf` | `<outdir>/<subdir>kneaddata` |
| `stage_report_input` | Build a bioBakery-standard output folder for vis and stats to read. | `modules/utils/report_input/main.nf` | `<outdir>` |
| `strainphlan` | StrainPhlAn step 2: build strain phylogeny per clade | `modules/strainphlan/main.nf` | `<outdir>/strainphlan/<clade>` |
| `trim_taxonomy` | Reformat a 16s taxonomy profile into a feature table. | `modules/stats/feature_table/main.nf` | `<outdir>/stats/features` |
| `version_log` | Capture tool versions, database paths, and workflow parameters for reproducibility | `modules/utils/version_log/main.nf` | `<outdir>/pipeline_info` |
| `vis_report` | Render the visualization report. | `modules/vis/report/main.nf` | `<outdir>` |

## mtx

Whole metatranscriptome shotgun.

```mermaid
%%{init: {"flowchart": {"curve": "basis", "nodeSpacing": 40,
                        "rankSpacing": 70, "padding": 8}}}%%
flowchart LR
    subgraph QUALITY_CONTROL
        direction TB
        paired_end_kneaddata(["<b>paired_end_kneaddata</b><br/>KneadData QC — paired-end<br/>reads"])
        single_end_kneaddata(["<b>single_end_kneaddata</b><br/>KneadData QC — single-end<br/>reads"])
        kneaddata_read_counts("<b>kneaddata_read_counts</b><br/>Compile the per-sample<br/>KneadData logs into one read…")
    end
    subgraph TAXONOMIC_PROFILING
        direction TB
        metaphlan("<b>metaphlan</b><br/>MetaPhlAn — taxonomic<br/>profiling")
        metaphlan_bzip("<b>metaphlan_bzip</b><br/>Compress MetaPhlAn SAM file<br/>(saves significant disk space)")
        metaphlan_merge("<b>metaphlan_merge</b><br/>Merge per-sample MetaPhlAn<br/>profiles into a single table")
        metaphlan_species_counts("<b>metaphlan_species_counts</b><br/>Count the species called in<br/>each sample, from the merged…")
    end
    subgraph FUNCTIONAL_PROFILING
        direction TB
        humann("<b>humann</b><br/>HUMAnN — functional profiling")
        humann_regroup_ecs("<b>humann_regroup_ecs</b><br/>Regroup UniRef gene families<br/>to level-4 enzyme commission…")
        humann_regroup("<b>humann_regroup</b><br/>Regroup HUMAnN gene families<br/>to a different annotation…")
        humann_rename["<b>humann_rename</b><br/>Rename HUMAnN output features<br/>to human-readable names"]
        humann_join("<b>humann_join</b><br/>Join per-sample HUMAnN tables<br/>of one feature type into a…")
        humann_renorm("<b>humann_renorm</b><br/>Renormalise a per-sample<br/>HUMAnN table from RPK to…")
        humann_join_relab("<b>humann_join_relab</b><br/>Join per-sample HUMAnN tables<br/>of one feature type into a…")
        humann_count_features("<b>humann_count_features</b><br/>Count how many features each<br/>sample has above zero, per…")
        humann_feature_counts_merge("<b>humann_feature_counts_merge</b><br/>Merge the three<br/>per-feature-type count tables…")
        humann_log_counts("<b>humann_log_counts</b><br/>Read and species counts, taken<br/>from the per-sample HUMAnN…")
    end
    subgraph STRAIN_PROFILING
        direction TB
        sample2markers("<b>sample2markers</b><br/>StrainPhlAn step 1: extract<br/>per-sample strain markers from…")
        strainphlan["<b>strainphlan</b><br/>StrainPhlAn step 2: build<br/>strain phylogeny per clade"]
    end
    subgraph MTX
        direction TB
        stage_report_input("<b>stage_report_input</b><br/>Build a bioBakery-standard<br/>output folder for vis and…")
        version_log(["<b>version_log</b><br/>Capture tool versions,<br/>database paths, and workflow…"])
    end
    subgraph VIS
        direction TB
        identify_inputs("<b>identify_inputs</b><br/>Identify the bioBakery data<br/>files in an input folder.")
        feature_table["<b>feature_table</b><br/>Build one feature table<br/>(taxonomy, pathways or any…"]
        trim_taxonomy["<b>trim_taxonomy</b><br/>Reformat a 16s taxonomy<br/>profile into a feature table."]
        add_ec_names("<b>add_ec_names</b><br/>Add EC names to the EC<br/>abundance table when they are…")
        vis_report("<b>vis_report</b><br/>Render the visualization<br/>report.")
        archive_output["<b>archive_output</b><br/>Archive a report folder."]
    end

    paired_end_kneaddata --> kneaddata_read_counts
    paired_end_kneaddata --> metaphlan
    paired_end_kneaddata --> humann
    single_end_kneaddata --> kneaddata_read_counts
    single_end_kneaddata --> metaphlan
    single_end_kneaddata --> humann
    kneaddata_read_counts --> stage_report_input
    metaphlan --> metaphlan_bzip
    metaphlan --> metaphlan_merge
    metaphlan --> humann
    metaphlan_bzip --> sample2markers
    metaphlan_merge --> metaphlan_species_counts
    metaphlan_merge --> stage_report_input
    metaphlan_species_counts --> stage_report_input
    humann --> humann_regroup_ecs
    humann --> humann_regroup
    humann --> humann_join
    humann --> humann_renorm
    humann --> humann_log_counts
    humann_regroup_ecs --> humann_join
    humann_regroup_ecs --> humann_renorm
    humann_regroup --> humann_rename
    humann_join --> stage_report_input
    humann_renorm --> humann_join_relab
    humann_join_relab --> humann_count_features
    humann_join_relab --> stage_report_input
    humann_count_features --> humann_feature_counts_merge
    humann_count_features --> stage_report_input
    humann_feature_counts_merge --> stage_report_input
    humann_log_counts --> stage_report_input
    sample2markers --> strainphlan
    stage_report_input --> identify_inputs
    stage_report_input --> feature_table
    stage_report_input --> trim_taxonomy
    stage_report_input --> add_ec_names
    stage_report_input --> vis_report
    identify_inputs --> feature_table
    identify_inputs --> trim_taxonomy
    identify_inputs --> add_ec_names
    identify_inputs --> vis_report
    add_ec_names --> vis_report
    vis_report --> archive_output

    style QUALITY_CONTROL fill:#dbeafe22,stroke:#3b82f6,stroke-width:1px,stroke-dasharray:4 3,color:#3b82f6
    style TAXONOMIC_PROFILING fill:#dcfce722,stroke:#22c55e,stroke-width:1px,stroke-dasharray:4 3,color:#22c55e
    style FUNCTIONAL_PROFILING fill:#ede9fe22,stroke:#8b5cf6,stroke-width:1px,stroke-dasharray:4 3,color:#8b5cf6
    style STRAIN_PROFILING fill:#ccfbf122,stroke:#14b8a6,stroke-width:1px,stroke-dasharray:4 3,color:#14b8a6
    style MTX fill:#f1f5f922,stroke:#94a3b8,stroke-width:1px,stroke-dasharray:4 3,color:#94a3b8
    style VIS fill:#fce7f322,stroke:#ec4899,stroke-width:1px,stroke-dasharray:4 3,color:#ec4899

    classDef stage0 fill:#dbeafe,stroke:#3b82f6,stroke-width:1.5px,color:#1e3a8a
    class paired_end_kneaddata,single_end_kneaddata,kneaddata_read_counts stage0
    classDef stage1 fill:#dcfce7,stroke:#22c55e,stroke-width:1.5px,color:#14532d
    class metaphlan,metaphlan_bzip,metaphlan_merge,metaphlan_species_counts stage1
    classDef stage2 fill:#ede9fe,stroke:#8b5cf6,stroke-width:1.5px,color:#4c1d95
    class humann,humann_regroup_ecs,humann_regroup,humann_rename,humann_join,humann_renorm,humann_join_relab,humann_count_features,humann_feature_counts_merge,humann_log_counts stage2
    classDef stage3 fill:#ccfbf1,stroke:#14b8a6,stroke-width:1.5px,color:#134e4a
    class sample2markers,strainphlan stage3
    classDef stage4 fill:#f1f5f9,stroke:#94a3b8,stroke-width:1.5px,color:#334155
    class stage_report_input,version_log stage4
    classDef stage5 fill:#fce7f3,stroke:#ec4899,stroke-width:1.5px,color:#831843
    class identify_inputs,feature_table,trim_taxonomy,add_ec_names,vis_report,archive_output stage5

    linkStyle default stroke:#cbd5e1,stroke-width:1.5px
    linkStyle 1,2,4,5,6,9,10,12,13,22,25,27,28,29,31,32,33,34,35 stroke:#475569,stroke-width:2px
```

| Step | What it does | Defined in | Publishes to |
|---|---|---|---|
| `add_ec_names` | Add EC names to the EC abundance table when they are missing. | `modules/vis/add_ec_names/main.nf` | `<outdir>/vis/ecs` |
| `archive_output` | Archive a report folder. | `modules/utils/archive/main.nf` | `<outdir>` |
| `feature_table` | Build one feature table (taxonomy, pathways or any other data file). | `modules/stats/feature_table/main.nf` | `<outdir>/stats/features` |
| `humann` | HUMAnN — functional profiling | `modules/humann/main.nf` | `<outdir>/<subdir>humann/<params.humann_version>/main` |
| `humann_count_features` | Count how many features each sample has above zero, per feature type. | `modules/utils/humann_merge/main.nf` | `<outdir>/<subdir>humann/<params.humann_version>/counts` |
| `humann_feature_counts_merge` | Merge the three per-feature-type count tables into one | `modules/utils/humann_merge/main.nf` | `<outdir>/<subdir>humann/<params.humann_version>/counts` |
| `humann_join` | Join per-sample HUMAnN tables of one feature type into a single matrix. | `modules/utils/humann_merge/main.nf` | `<outdir>/<subdir>humann/<params.humann_version>/merged` |
| `humann_join_relab` | Join per-sample HUMAnN tables of one feature type into a single matrix. (`humann_join`, run again as `humann_join_relab`) | `modules/utils/humann_merge/main.nf` | `<outdir>/<subdir>humann/<params.humann_version>/merged` |
| `humann_log_counts` | Read and species counts, taken from the per-sample HUMAnN logs. | `modules/utils/humann_merge/main.nf` | `<outdir>/<subdir>humann/<params.humann_version>/counts` |
| `humann_regroup` | Regroup HUMAnN gene families to a different annotation scheme. | `modules/utils/humann_regroup/main.nf` | `<outdir>/<subdir>humann/<params.humann_version>/regrouped` |
| `humann_regroup_ecs` | Regroup UniRef gene families to level-4 enzyme commission numbers. | `modules/utils/humann_regroup/main.nf` | `<outdir>/<subdir>humann/<params.humann_version>/regrouped` |
| `humann_rename` | Rename HUMAnN output features to human-readable names | `modules/utils/humann_rename/main.nf` | `<outdir>/<subdir>humann/<params.humann_version>/renamed` |
| `humann_renorm` | Renormalise a per-sample HUMAnN table from RPK to relative abundance. | `modules/utils/humann_renorm/main.nf` | `<outdir>/<subdir>humann/<params.humann_version>/relab/<feature>` |
| `identify_inputs` | Identify the bioBakery data files in an input folder. | `modules/vis/identify_inputs/main.nf` | `<outdir>/<report_type>` |
| `kneaddata_read_counts` | Compile the per-sample KneadData logs into one read count table. | `modules/kneaddata/main.nf` | `<outdir>/<subdir>kneaddata/merged` |
| `metaphlan` | MetaPhlAn — taxonomic profiling | `modules/metaphlan/main.nf` | `<outdir>/<subdir>metaphlan/<params.metaphlan_index>` |
| `metaphlan_bzip` | Compress MetaPhlAn SAM file (saves significant disk space) | `modules/metaphlan/main.nf` | `<outdir>/<subdir>metaphlan/bzip` |
| `metaphlan_merge` | Merge per-sample MetaPhlAn profiles into a single table | `modules/metaphlan/main.nf` | `<outdir>/<subdir>metaphlan` |
| `metaphlan_species_counts` | Count the species called in each sample, from the merged profile. | `modules/metaphlan/main.nf` | `<outdir>/<subdir>metaphlan/merged` |
| `paired_end_kneaddata` | KneadData QC — paired-end reads | `modules/kneaddata/main.nf` | `<outdir>/<subdir>kneaddata` |
| `sample2markers` | StrainPhlAn step 1: extract per-sample strain markers from MetaPhlAn SAM output | `modules/strainphlan/main.nf` | `<outdir>/strainphlan/markers` |
| `single_end_kneaddata` | KneadData QC — single-end reads | `modules/kneaddata/main.nf` | `<outdir>/<subdir>kneaddata` |
| `stage_report_input` | Build a bioBakery-standard output folder for vis and stats to read. | `modules/utils/report_input/main.nf` | `<outdir>` |
| `strainphlan` | StrainPhlAn step 2: build strain phylogeny per clade | `modules/strainphlan/main.nf` | `<outdir>/strainphlan/<clade>` |
| `trim_taxonomy` | Reformat a 16s taxonomy profile into a feature table. | `modules/stats/feature_table/main.nf` | `<outdir>/stats/features` |
| `version_log` | Capture tool versions, database paths, and workflow parameters for reproducibility | `modules/utils/version_log/main.nf` | `<outdir>/pipeline_info` |
| `vis_report` | Render the visualization report. | `modules/vis/report/main.nf` | `<outdir>` |

## mgx_mtx

Paired metagenome + metatranscriptome.

```mermaid
%%{init: {"flowchart": {"curve": "basis", "nodeSpacing": 40,
                        "rankSpacing": 70, "padding": 8}}}%%
flowchart LR
    subgraph QC_MGX
        direction TB
        paired_end_kneaddata(["<b>paired_end_kneaddata</b><br/>KneadData QC — paired-end<br/>reads"])
        single_end_kneaddata(["<b>single_end_kneaddata</b><br/>KneadData QC — single-end<br/>reads"])
        kneaddata_read_counts("<b>kneaddata_read_counts</b><br/>Compile the per-sample<br/>KneadData logs into one read…")
    end
    subgraph QC_MTX
        direction TB
        paired_end_kneaddata_2(["<b>paired_end_kneaddata</b><br/>KneadData QC — paired-end<br/>reads"])
        single_end_kneaddata_2(["<b>single_end_kneaddata</b><br/>KneadData QC — single-end<br/>reads"])
        kneaddata_read_counts_2["<b>kneaddata_read_counts</b><br/>Compile the per-sample<br/>KneadData logs into one read…"]
    end
    subgraph TAX_MGX
        direction TB
        metaphlan("<b>metaphlan</b><br/>MetaPhlAn — taxonomic<br/>profiling")
        metaphlan_bzip("<b>metaphlan_bzip</b><br/>Compress MetaPhlAn SAM file<br/>(saves significant disk space)")
        metaphlan_merge("<b>metaphlan_merge</b><br/>Merge per-sample MetaPhlAn<br/>profiles into a single table")
        metaphlan_species_counts("<b>metaphlan_species_counts</b><br/>Count the species called in<br/>each sample, from the merged…")
    end
    subgraph TAX_MTX
        direction TB
        metaphlan_2("<b>metaphlan</b><br/>MetaPhlAn — taxonomic<br/>profiling")
        metaphlan_bzip_2["<b>metaphlan_bzip</b><br/>Compress MetaPhlAn SAM file<br/>(saves significant disk space)"]
        metaphlan_merge_2("<b>metaphlan_merge</b><br/>Merge per-sample MetaPhlAn<br/>profiles into a single table")
        metaphlan_species_counts_2["<b>metaphlan_species_counts</b><br/>Count the species called in<br/>each sample, from the merged…"]
    end
    subgraph FUNC_MGX
        direction TB
        humann("<b>humann</b><br/>HUMAnN — functional profiling")
        humann_regroup_ecs("<b>humann_regroup_ecs</b><br/>Regroup UniRef gene families<br/>to level-4 enzyme commission…")
        humann_regroup("<b>humann_regroup</b><br/>Regroup HUMAnN gene families<br/>to a different annotation…")
        humann_rename["<b>humann_rename</b><br/>Rename HUMAnN output features<br/>to human-readable names"]
        humann_join("<b>humann_join</b><br/>Join per-sample HUMAnN tables<br/>of one feature type into a…")
        humann_renorm("<b>humann_renorm</b><br/>Renormalise a per-sample<br/>HUMAnN table from RPK to…")
        humann_join_relab("<b>humann_join_relab</b><br/>Join per-sample HUMAnN tables<br/>of one feature type into a…")
        humann_count_features("<b>humann_count_features</b><br/>Count how many features each<br/>sample has above zero, per…")
        humann_feature_counts_merge("<b>humann_feature_counts_merge</b><br/>Merge the three<br/>per-feature-type count tables…")
        humann_log_counts("<b>humann_log_counts</b><br/>Read and species counts, taken<br/>from the per-sample HUMAnN…")
    end
    subgraph FUNC_MTX
        direction TB
        humann_2("<b>humann</b><br/>HUMAnN — functional profiling")
        humann_regroup_ecs_2("<b>humann_regroup_ecs</b><br/>Regroup UniRef gene families<br/>to level-4 enzyme commission…")
        humann_regroup_2("<b>humann_regroup</b><br/>Regroup HUMAnN gene families<br/>to a different annotation…")
        humann_rename_2["<b>humann_rename</b><br/>Rename HUMAnN output features<br/>to human-readable names"]
        humann_join_2("<b>humann_join</b><br/>Join per-sample HUMAnN tables<br/>of one feature type into a…")
        humann_renorm_2("<b>humann_renorm</b><br/>Renormalise a per-sample<br/>HUMAnN table from RPK to…")
        humann_join_relab_2("<b>humann_join_relab</b><br/>Join per-sample HUMAnN tables<br/>of one feature type into a…")
        humann_count_features_2("<b>humann_count_features</b><br/>Count how many features each<br/>sample has above zero, per…")
        humann_feature_counts_merge_2["<b>humann_feature_counts_merge</b><br/>Merge the three<br/>per-feature-type count tables…"]
        humann_log_counts_2["<b>humann_log_counts</b><br/>Read and species counts, taken<br/>from the per-sample HUMAnN…"]
    end
    subgraph MGX_MTX
        direction TB
        rna_dna_norm["<b>rna_dna_norm</b><br/>RNA/DNA relative expression<br/>ratio for one feature type."]
        stage_report_input("<b>stage_report_input</b><br/>Build a bioBakery-standard<br/>output folder for vis and…")
        version_log(["<b>version_log</b><br/>Capture tool versions,<br/>database paths, and workflow…"])
    end
    subgraph STRAIN_PROFILING
        direction TB
        sample2markers("<b>sample2markers</b><br/>StrainPhlAn step 1: extract<br/>per-sample strain markers from…")
        strainphlan["<b>strainphlan</b><br/>StrainPhlAn step 2: build<br/>strain phylogeny per clade"]
    end
    subgraph VIS
        direction TB
        identify_inputs("<b>identify_inputs</b><br/>Identify the bioBakery data<br/>files in an input folder.")
        feature_table["<b>feature_table</b><br/>Build one feature table<br/>(taxonomy, pathways or any…"]
        trim_taxonomy["<b>trim_taxonomy</b><br/>Reformat a 16s taxonomy<br/>profile into a feature table."]
        add_ec_names("<b>add_ec_names</b><br/>Add EC names to the EC<br/>abundance table when they are…")
        vis_report("<b>vis_report</b><br/>Render the visualization<br/>report.")
        archive_output["<b>archive_output</b><br/>Archive a report folder."]
    end

    paired_end_kneaddata --> kneaddata_read_counts
    paired_end_kneaddata --> metaphlan
    paired_end_kneaddata --> humann
    single_end_kneaddata --> kneaddata_read_counts
    single_end_kneaddata --> metaphlan
    single_end_kneaddata --> humann
    kneaddata_read_counts --> stage_report_input
    paired_end_kneaddata_2 --> kneaddata_read_counts_2
    paired_end_kneaddata_2 --> metaphlan_2
    paired_end_kneaddata_2 --> humann_2
    single_end_kneaddata_2 --> kneaddata_read_counts_2
    single_end_kneaddata_2 --> metaphlan_2
    single_end_kneaddata_2 --> humann_2
    metaphlan --> metaphlan_bzip
    metaphlan --> metaphlan_merge
    metaphlan --> humann
    metaphlan_bzip --> sample2markers
    metaphlan_merge --> metaphlan_species_counts
    metaphlan_merge --> stage_report_input
    metaphlan_species_counts --> stage_report_input
    metaphlan_2 --> metaphlan_bzip_2
    metaphlan_2 --> metaphlan_merge_2
    metaphlan_2 --> humann_2
    metaphlan_merge_2 --> metaphlan_species_counts_2
    humann --> humann_regroup_ecs
    humann --> humann_regroup
    humann --> humann_join
    humann --> humann_renorm
    humann --> humann_log_counts
    humann_regroup_ecs --> humann_join
    humann_regroup_ecs --> humann_renorm
    humann_regroup --> humann_rename
    humann_join --> rna_dna_norm
    humann_join --> stage_report_input
    humann_renorm --> humann_join_relab
    humann_join_relab --> humann_count_features
    humann_join_relab --> stage_report_input
    humann_count_features --> humann_feature_counts_merge
    humann_count_features --> stage_report_input
    humann_feature_counts_merge --> stage_report_input
    humann_log_counts --> stage_report_input
    humann_2 --> humann_regroup_ecs_2
    humann_2 --> humann_regroup_2
    humann_2 --> humann_join_2
    humann_2 --> humann_renorm_2
    humann_2 --> humann_log_counts_2
    humann_regroup_ecs_2 --> humann_join_2
    humann_regroup_ecs_2 --> humann_renorm_2
    humann_regroup_2 --> humann_rename_2
    humann_join_2 --> rna_dna_norm
    humann_renorm_2 --> humann_join_relab_2
    humann_join_relab_2 --> humann_count_features_2
    humann_count_features_2 --> humann_feature_counts_merge_2
    sample2markers --> strainphlan
    stage_report_input --> identify_inputs
    stage_report_input --> feature_table
    stage_report_input --> trim_taxonomy
    stage_report_input --> add_ec_names
    stage_report_input --> vis_report
    identify_inputs --> feature_table
    identify_inputs --> trim_taxonomy
    identify_inputs --> add_ec_names
    identify_inputs --> vis_report
    add_ec_names --> vis_report
    vis_report --> archive_output

    style QC_MGX fill:#dbeafe22,stroke:#3b82f6,stroke-width:1px,stroke-dasharray:4 3,color:#3b82f6
    style QC_MTX fill:#dbeafe22,stroke:#3b82f6,stroke-width:1px,stroke-dasharray:4 3,color:#3b82f6
    style TAX_MGX fill:#dcfce722,stroke:#22c55e,stroke-width:1px,stroke-dasharray:4 3,color:#22c55e
    style TAX_MTX fill:#dcfce722,stroke:#22c55e,stroke-width:1px,stroke-dasharray:4 3,color:#22c55e
    style FUNC_MGX fill:#ede9fe22,stroke:#8b5cf6,stroke-width:1px,stroke-dasharray:4 3,color:#8b5cf6
    style FUNC_MTX fill:#ede9fe22,stroke:#8b5cf6,stroke-width:1px,stroke-dasharray:4 3,color:#8b5cf6
    style MGX_MTX fill:#f1f5f922,stroke:#94a3b8,stroke-width:1px,stroke-dasharray:4 3,color:#94a3b8
    style STRAIN_PROFILING fill:#ccfbf122,stroke:#14b8a6,stroke-width:1px,stroke-dasharray:4 3,color:#14b8a6
    style VIS fill:#fce7f322,stroke:#ec4899,stroke-width:1px,stroke-dasharray:4 3,color:#ec4899

    classDef stage0 fill:#dbeafe,stroke:#3b82f6,stroke-width:1.5px,color:#1e3a8a
    class paired_end_kneaddata,single_end_kneaddata,kneaddata_read_counts stage0
    classDef stage1 fill:#dbeafe,stroke:#3b82f6,stroke-width:1.5px,color:#1e3a8a
    class paired_end_kneaddata_2,single_end_kneaddata_2,kneaddata_read_counts_2 stage1
    classDef stage2 fill:#dcfce7,stroke:#22c55e,stroke-width:1.5px,color:#14532d
    class metaphlan,metaphlan_bzip,metaphlan_merge,metaphlan_species_counts stage2
    classDef stage3 fill:#dcfce7,stroke:#22c55e,stroke-width:1.5px,color:#14532d
    class metaphlan_2,metaphlan_bzip_2,metaphlan_merge_2,metaphlan_species_counts_2 stage3
    classDef stage4 fill:#ede9fe,stroke:#8b5cf6,stroke-width:1.5px,color:#4c1d95
    class humann,humann_regroup_ecs,humann_regroup,humann_rename,humann_join,humann_renorm,humann_join_relab,humann_count_features,humann_feature_counts_merge,humann_log_counts stage4
    classDef stage5 fill:#ede9fe,stroke:#8b5cf6,stroke-width:1.5px,color:#4c1d95
    class humann_2,humann_regroup_ecs_2,humann_regroup_2,humann_rename_2,humann_join_2,humann_renorm_2,humann_join_relab_2,humann_count_features_2,humann_feature_counts_merge_2,humann_log_counts_2 stage5
    classDef stage6 fill:#f1f5f9,stroke:#94a3b8,stroke-width:1.5px,color:#334155
    class rna_dna_norm,stage_report_input,version_log stage6
    classDef stage7 fill:#ccfbf1,stroke:#14b8a6,stroke-width:1.5px,color:#134e4a
    class sample2markers,strainphlan stage7
    classDef stage8 fill:#fce7f3,stroke:#ec4899,stroke-width:1.5px,color:#831843
    class identify_inputs,feature_table,trim_taxonomy,add_ec_names,vis_report,archive_output stage8

    linkStyle default stroke:#cbd5e1,stroke-width:1.5px
    linkStyle 1,2,4,5,6,8,9,11,12,15,16,18,19,22,32,33,36,38,39,40,49,54,55,56,57,58 stroke:#475569,stroke-width:2px
```

| Step | What it does | Defined in | Publishes to |
|---|---|---|---|
| `add_ec_names` | Add EC names to the EC abundance table when they are missing. | `modules/vis/add_ec_names/main.nf` | `<outdir>/vis/ecs` |
| `archive_output` | Archive a report folder. | `modules/utils/archive/main.nf` | `<outdir>` |
| `feature_table` | Build one feature table (taxonomy, pathways or any other data file). | `modules/stats/feature_table/main.nf` | `<outdir>/stats/features` |
| `humann` | HUMAnN — functional profiling | `modules/humann/main.nf` | `<outdir>/<subdir>humann/<params.humann_version>/main` |
| `humann_count_features` | Count how many features each sample has above zero, per feature type. | `modules/utils/humann_merge/main.nf` | `<outdir>/<subdir>humann/<params.humann_version>/counts` |
| `humann_feature_counts_merge` | Merge the three per-feature-type count tables into one | `modules/utils/humann_merge/main.nf` | `<outdir>/<subdir>humann/<params.humann_version>/counts` |
| `humann_join` | Join per-sample HUMAnN tables of one feature type into a single matrix. | `modules/utils/humann_merge/main.nf` | `<outdir>/<subdir>humann/<params.humann_version>/merged` |
| `humann_join_relab` | Join per-sample HUMAnN tables of one feature type into a single matrix. (`humann_join`, run again as `humann_join_relab`) | `modules/utils/humann_merge/main.nf` | `<outdir>/<subdir>humann/<params.humann_version>/merged` |
| `humann_log_counts` | Read and species counts, taken from the per-sample HUMAnN logs. | `modules/utils/humann_merge/main.nf` | `<outdir>/<subdir>humann/<params.humann_version>/counts` |
| `humann_regroup` | Regroup HUMAnN gene families to a different annotation scheme. | `modules/utils/humann_regroup/main.nf` | `<outdir>/<subdir>humann/<params.humann_version>/regrouped` |
| `humann_regroup_ecs` | Regroup UniRef gene families to level-4 enzyme commission numbers. | `modules/utils/humann_regroup/main.nf` | `<outdir>/<subdir>humann/<params.humann_version>/regrouped` |
| `humann_rename` | Rename HUMAnN output features to human-readable names | `modules/utils/humann_rename/main.nf` | `<outdir>/<subdir>humann/<params.humann_version>/renamed` |
| `humann_renorm` | Renormalise a per-sample HUMAnN table from RPK to relative abundance. | `modules/utils/humann_renorm/main.nf` | `<outdir>/<subdir>humann/<params.humann_version>/relab/<feature>` |
| `identify_inputs` | Identify the bioBakery data files in an input folder. | `modules/vis/identify_inputs/main.nf` | `<outdir>/<report_type>` |
| `kneaddata_read_counts` | Compile the per-sample KneadData logs into one read count table. | `modules/kneaddata/main.nf` | `<outdir>/<subdir>kneaddata/merged` |
| `metaphlan` | MetaPhlAn — taxonomic profiling | `modules/metaphlan/main.nf` | `<outdir>/<subdir>metaphlan/<params.metaphlan_index>` |
| `metaphlan_bzip` | Compress MetaPhlAn SAM file (saves significant disk space) | `modules/metaphlan/main.nf` | `<outdir>/<subdir>metaphlan/bzip` |
| `metaphlan_merge` | Merge per-sample MetaPhlAn profiles into a single table | `modules/metaphlan/main.nf` | `<outdir>/<subdir>metaphlan` |
| `metaphlan_species_counts` | Count the species called in each sample, from the merged profile. | `modules/metaphlan/main.nf` | `<outdir>/<subdir>metaphlan/merged` |
| `paired_end_kneaddata` | KneadData QC — paired-end reads | `modules/kneaddata/main.nf` | `<outdir>/<subdir>kneaddata` |
| `rna_dna_norm` | RNA/DNA relative expression ratio for one feature type. | `modules/utils/rna_dna_norm/main.nf` | `<outdir>/humann/rna_dna_norm` |
| `sample2markers` | StrainPhlAn step 1: extract per-sample strain markers from MetaPhlAn SAM output | `modules/strainphlan/main.nf` | `<outdir>/strainphlan/markers` |
| `single_end_kneaddata` | KneadData QC — single-end reads | `modules/kneaddata/main.nf` | `<outdir>/<subdir>kneaddata` |
| `stage_report_input` | Build a bioBakery-standard output folder for vis and stats to read. | `modules/utils/report_input/main.nf` | `<outdir>` |
| `strainphlan` | StrainPhlAn step 2: build strain phylogeny per clade | `modules/strainphlan/main.nf` | `<outdir>/strainphlan/<clade>` |
| `trim_taxonomy` | Reformat a 16s taxonomy profile into a feature table. | `modules/stats/feature_table/main.nf` | `<outdir>/stats/features` |
| `version_log` | Capture tool versions, database paths, and workflow parameters for reproducibility | `modules/utils/version_log/main.nf` | `<outdir>/pipeline_info` |
| `vis_report` | Render the visualization report. | `modules/vis/report/main.nf` | `<outdir>` |

## assembly

MAG assembly, binning and SGB clustering.

```mermaid
%%{init: {"flowchart": {"curve": "basis", "nodeSpacing": 40,
                        "rankSpacing": 70, "padding": 8}}}%%
flowchart LR
    subgraph QUALITY_CONTROL
        direction TB
        paired_end_kneaddata(["<b>paired_end_kneaddata</b><br/>KneadData QC — paired-end<br/>reads"])
        single_end_kneaddata(["<b>single_end_kneaddata</b><br/>KneadData QC — single-end<br/>reads"])
        kneaddata_read_counts["<b>kneaddata_read_counts</b><br/>Compile the per-sample<br/>KneadData logs into one read…"]
    end
    subgraph ASSEMBLY
        direction TB
        megahit("<b>megahit</b><br/>MEGAHIT — de novo metagenome<br/>assembly")
        align_and_depth("<b>align_and_depth</b><br/>Align reads to assembled<br/>contigs and compute contig…")
        metabat2("<b>metabat2</b><br/>MetaBAT2 — bin contigs into<br/>Metagenome-Assembled Genomes…")
        checkm2("<b>checkm2</b><br/>CheckM2 — assess MAG quality<br/>(completeness & contamination)")
        mag_n50("<b>mag_n50</b><br/>Compute N50 for each MAG bin")
        checkm2_merge("<b>checkm2_merge</b><br/>Merge per-sample CheckM2<br/>quality reports into one table")
        checkm2_wrangling("<b>checkm2_wrangling</b><br/>Merge CheckM2 QA with N50<br/>stats and filter by…")
        phylophlan_metagenomic("<b>phylophlan_metagenomic</b><br/>PhyloPhlAn metagenomic —<br/>phylogenetic placement of MAGs…")
        phylophlan_merge("<b>phylophlan_merge</b><br/>Merge per-sample PhyloPhlAn<br/>placements and add taxonomic…")
        mash_list_inputs("<b>mash_list_inputs</b><br/>List qualifying MAG FASTA<br/>paths to feed into Mash")
        mash_sketch("<b>mash_sketch</b><br/>Sketch each qualifying MAG,<br/>the first step of the Mash…")
        mash_paste("<b>mash_paste</b><br/>Paste the per-MAG Mash<br/>sketches into one reference…")
        mash_dist("<b>mash_dist</b><br/>Pairwise Mash distances<br/>between every MAG and the…")
        sgb_cluster("<b>sgb_cluster</b><br/>Cluster MAGs into SGBs using<br/>Mash distances +…")
        abundance("<b>abundance</b><br/>Per-sample MAG abundance,<br/>mirroring the Calculate…")
        merge_tax_abundance["<b>merge_tax_abundance</b><br/>Merge abundance data with<br/>taxonomy and SGB assignments…"]
        version_log(["<b>version_log</b><br/>Capture tool versions,<br/>database paths, and workflow…"])
    end

    paired_end_kneaddata --> kneaddata_read_counts
    paired_end_kneaddata --> megahit
    paired_end_kneaddata --> align_and_depth
    paired_end_kneaddata --> abundance
    single_end_kneaddata --> kneaddata_read_counts
    single_end_kneaddata --> megahit
    single_end_kneaddata --> align_and_depth
    single_end_kneaddata --> abundance
    megahit --> align_and_depth
    megahit --> metabat2
    megahit --> abundance
    align_and_depth --> metabat2
    align_and_depth --> abundance
    metabat2 --> checkm2
    metabat2 --> mag_n50
    metabat2 --> phylophlan_metagenomic
    metabat2 --> mash_list_inputs
    metabat2 --> abundance
    checkm2 --> checkm2_merge
    mag_n50 --> checkm2_wrangling
    checkm2_merge --> checkm2_wrangling
    checkm2_wrangling --> mash_list_inputs
    checkm2_wrangling --> sgb_cluster
    checkm2_wrangling --> merge_tax_abundance
    phylophlan_metagenomic --> phylophlan_merge
    phylophlan_merge --> mash_list_inputs
    phylophlan_merge --> sgb_cluster
    phylophlan_merge --> merge_tax_abundance
    mash_list_inputs --> mash_sketch
    mash_list_inputs --> sgb_cluster
    mash_sketch --> mash_paste
    mash_sketch --> mash_dist
    mash_paste --> mash_dist
    mash_dist --> sgb_cluster
    sgb_cluster --> merge_tax_abundance
    abundance --> merge_tax_abundance

    style QUALITY_CONTROL fill:#dbeafe22,stroke:#3b82f6,stroke-width:1px,stroke-dasharray:4 3,color:#3b82f6
    style ASSEMBLY fill:#fef3c722,stroke:#d97706,stroke-width:1px,stroke-dasharray:4 3,color:#d97706

    classDef stage0 fill:#dbeafe,stroke:#3b82f6,stroke-width:1.5px,color:#1e3a8a
    class paired_end_kneaddata,single_end_kneaddata,kneaddata_read_counts stage0
    classDef stage1 fill:#fef3c7,stroke:#d97706,stroke-width:1.5px,color:#78350f
    class megahit,align_and_depth,metabat2,checkm2,mag_n50,checkm2_merge,checkm2_wrangling,phylophlan_metagenomic,phylophlan_merge,mash_list_inputs,mash_sketch,mash_paste,mash_dist,sgb_cluster,abundance,merge_tax_abundance,version_log stage1

    linkStyle default stroke:#cbd5e1,stroke-width:1.5px
    linkStyle 1,2,3,5,6,7 stroke:#475569,stroke-width:2px
```

| Step | What it does | Defined in | Publishes to |
|---|---|---|---|
| `abundance` | Per-sample MAG abundance, mirroring the "Calculate by-sample abundance" task of | `modules/utils/abundance/main.nf` | `<outdir>/abundance_<params.sgb_abundance_type>` |
| `align_and_depth` | Align reads to assembled contigs and compute contig depth with jgi_summarize_bam_contig_depths | `modules/utils/align_and_depth/main.nf` | `<outdir>/assembly/contig_depths` |
| `checkm2` | CheckM2 — assess MAG quality (completeness & contamination) | `modules/qc/checkm2/main.nf` | `<outdir>/checkm/<sample>` |
| `checkm2_merge` | Merge per-sample CheckM2 quality reports into one table | `modules/qc/checkm2/main.nf` | `<outdir>/checkm` |
| `checkm2_wrangling` | Merge CheckM2 QA with N50 stats and filter by completeness/contamination thresholds | `modules/qc/checkm2/main.nf` | `<outdir>/checkm/qa` |
| `kneaddata_read_counts` | Compile the per-sample KneadData logs into one read count table. | `modules/kneaddata/main.nf` | `<outdir>/<subdir>kneaddata/merged` |
| `mag_n50` | Compute N50 for each MAG bin | `modules/qc/checkm2/main.nf` | `<outdir>/checkm/n50` |
| `mash_dist` | Pairwise Mash distances between every MAG and the reference sketch. | `modules/utils/mash/main.nf` | `<outdir>/sgbs/mash` |
| `mash_list_inputs` | List qualifying MAG FASTA paths to feed into Mash | `modules/utils/mash/main.nf` | `<outdir>/sgbs/mash` |
| `mash_paste` | Paste the per-MAG Mash sketches into one reference sketch. | `modules/utils/mash/main.nf` | `<outdir>/sgbs/mash` |
| `mash_sketch` | Sketch each qualifying MAG, the first step of the Mash distance pipeline. | `modules/utils/mash/main.nf` | `<outdir>/sgbs/mash` |
| `megahit` | MEGAHIT — de novo metagenome assembly | `modules/assembly/megahit/main.nf` | `<outdir>/assembly/main/<sample>` |
| `merge_tax_abundance` | Merge abundance data with taxonomy and SGB assignments into the final profile | `modules/utils/mash/main.nf` | `<outdir>` |
| `metabat2` | MetaBAT2 — bin contigs into Metagenome-Assembled Genomes (MAGs) | `modules/binning/metabat2/main.nf` | `<outdir>/bins/<sample>` |
| `paired_end_kneaddata` | KneadData QC — paired-end reads | `modules/kneaddata/main.nf` | `<outdir>/<subdir>kneaddata` |
| `phylophlan_merge` | Merge per-sample PhyloPhlAn placements and add taxonomic labels | `modules/phylogenomics/phylophlan_metagenomic/main.nf` | `<outdir>/phylophlan` |
| `phylophlan_metagenomic` | PhyloPhlAn metagenomic — phylogenetic placement of MAGs to nearest SGBs/GGBs/FGBs | `modules/phylogenomics/phylophlan_metagenomic/main.nf` | `<outdir>/phylophlan/<sample>` |
| `sgb_cluster` | Cluster MAGs into SGBs using Mash distances + CheckM/PhyloPhlAn metadata | `modules/utils/mash/main.nf` | `<outdir>/sgbs/sgbs` |
| `single_end_kneaddata` | KneadData QC — single-end reads | `modules/kneaddata/main.nf` | `<outdir>/<subdir>kneaddata` |
| `version_log` | Capture tool versions, database paths, and workflow parameters for reproducibility | `modules/utils/version_log/main.nf` | `<outdir>/pipeline_info` |

## vis

Visualisation report.

```mermaid
%%{init: {"flowchart": {"curve": "basis", "nodeSpacing": 40,
                        "rankSpacing": 70, "padding": 8}}}%%
flowchart LR
    subgraph VIS
        direction TB
        identify_inputs(["<b>identify_inputs</b><br/>Identify the bioBakery data<br/>files in an input folder."])
        feature_table["<b>feature_table</b><br/>Build one feature table<br/>(taxonomy, pathways or any…"]
        trim_taxonomy["<b>trim_taxonomy</b><br/>Reformat a 16s taxonomy<br/>profile into a feature table."]
        add_ec_names("<b>add_ec_names</b><br/>Add EC names to the EC<br/>abundance table when they are…")
        vis_report("<b>vis_report</b><br/>Render the visualization<br/>report.")
        archive_output["<b>archive_output</b><br/>Archive a report folder."]
    end

    identify_inputs --> feature_table
    identify_inputs --> trim_taxonomy
    identify_inputs --> add_ec_names
    identify_inputs --> vis_report
    add_ec_names --> vis_report
    vis_report --> archive_output

    style VIS fill:#fce7f322,stroke:#ec4899,stroke-width:1px,stroke-dasharray:4 3,color:#ec4899

    classDef stage0 fill:#fce7f3,stroke:#ec4899,stroke-width:1.5px,color:#831843
    class identify_inputs,feature_table,trim_taxonomy,add_ec_names,vis_report,archive_output stage0

    linkStyle default stroke:#cbd5e1,stroke-width:1.5px
```

| Step | What it does | Defined in | Publishes to |
|---|---|---|---|
| `add_ec_names` | Add EC names to the EC abundance table when they are missing. | `modules/vis/add_ec_names/main.nf` | `<outdir>/vis/ecs` |
| `archive_output` | Archive a report folder. | `modules/utils/archive/main.nf` | `<outdir>` |
| `feature_table` | Build one feature table (taxonomy, pathways or any other data file). | `modules/stats/feature_table/main.nf` | `<outdir>/stats/features` |
| `identify_inputs` | Identify the bioBakery data files in an input folder. | `modules/vis/identify_inputs/main.nf` | `<outdir>/<report_type>` |
| `trim_taxonomy` | Reformat a 16s taxonomy profile into a feature table. | `modules/stats/feature_table/main.nf` | `<outdir>/stats/features` |
| `vis_report` | Render the visualization report. | `modules/vis/report/main.nf` | `<outdir>` |

## stats

Statistical analysis report.

```mermaid
%%{init: {"flowchart": {"curve": "basis", "nodeSpacing": 40,
                        "rankSpacing": 70, "padding": 8}}}%%
flowchart LR
    subgraph STATS
        direction TB
        identify_inputs(["<b>identify_inputs</b><br/>Identify the bioBakery data<br/>files in an input folder."])
        feature_table("<b>feature_table</b><br/>Build one feature table<br/>(taxonomy, pathways or any…")
        trim_taxonomy("<b>trim_taxonomy</b><br/>Reformat a 16s taxonomy<br/>profile into a feature table.")
        mantel_test("<b>mantel_test</b><br/>Mantel test across all pairs<br/>of feature tables.")
        maaslin2("<b>maaslin2</b><br/>MaAsLin2 per feature table,<br/>plus the figure tiles shown in…")
        halla_transpose_metadata("<b>halla_transpose_metadata</b><br/>HAllA needs the metadata with<br/>samples as columns.")
        halla("<b>halla</b><br/>HAllA — hierarchical<br/>all-against-all association…")
        stratified_metadata("<b>stratified_metadata</b><br/>Merge the pathway abundances<br/>with the metadata and work out…")
        stratified_barplot("<b>stratified_barplot</b><br/>One barplot per (pathway rank,<br/>metadata variable).")
        covariate_equation("<b>covariate_equation</b><br/>Work out the multivariate<br/>covariate equation for the…")
        beta_diversity("<b>beta_diversity</b><br/>One beta diversity analysis<br/>for one feature table.")
        stats_report("<b>stats_report</b><br/>Render the stats report.")
        archive_output["<b>archive_output</b><br/>Archive a report folder."]
    end

    identify_inputs --> feature_table
    identify_inputs --> trim_taxonomy
    identify_inputs --> halla_transpose_metadata
    identify_inputs --> halla
    identify_inputs --> stratified_metadata
    identify_inputs --> covariate_equation
    identify_inputs --> stats_report
    feature_table --> mantel_test
    feature_table --> maaslin2
    feature_table --> halla
    feature_table --> beta_diversity
    feature_table --> stats_report
    trim_taxonomy --> mantel_test
    trim_taxonomy --> maaslin2
    trim_taxonomy --> halla
    trim_taxonomy --> beta_diversity
    trim_taxonomy --> stats_report
    mantel_test --> stats_report
    maaslin2 --> stratified_barplot
    maaslin2 --> stats_report
    halla_transpose_metadata --> feature_table
    halla_transpose_metadata --> trim_taxonomy
    halla_transpose_metadata --> halla
    halla_transpose_metadata --> stratified_metadata
    halla_transpose_metadata --> stats_report
    halla --> stats_report
    stratified_metadata --> stratified_barplot
    stratified_barplot --> stats_report
    covariate_equation --> mantel_test
    covariate_equation --> maaslin2
    covariate_equation --> halla
    covariate_equation --> beta_diversity
    covariate_equation --> stats_report
    beta_diversity --> stats_report
    stats_report --> archive_output

    style STATS fill:#e0e7ff22,stroke:#6366f1,stroke-width:1px,stroke-dasharray:4 3,color:#6366f1

    classDef stage0 fill:#e0e7ff,stroke:#6366f1,stroke-width:1.5px,color:#312e81
    class identify_inputs,feature_table,trim_taxonomy,mantel_test,maaslin2,halla_transpose_metadata,halla,stratified_metadata,stratified_barplot,covariate_equation,beta_diversity,stats_report,archive_output stage0

    linkStyle default stroke:#cbd5e1,stroke-width:1.5px
```

| Step | What it does | Defined in | Publishes to |
|---|---|---|---|
| `archive_output` | Archive a report folder. | `modules/utils/archive/main.nf` | `<outdir>` |
| `beta_diversity` | One beta diversity analysis for one feature table. | `modules/stats/beta_diversity/main.nf` | `<outdir>/stats/beta_diversity` |
| `covariate_equation` | Work out the multivariate covariate equation for the beta diversity models. | `modules/stats/covariate_equation/main.nf` | `<outdir>/stats` |
| `feature_table` | Build one feature table (taxonomy, pathways or any other data file). | `modules/stats/feature_table/main.nf` | `<outdir>/stats/features` |
| `halla` | HAllA — hierarchical all-against-all association between features and metadata. | `modules/stats/halla/main.nf` | `<outdir>/stats` |
| `halla_transpose_metadata` | HAllA needs the metadata with samples as columns. | `modules/stats/halla/main.nf` | `` |
| `identify_inputs` | Identify the bioBakery data files in an input folder. | `modules/vis/identify_inputs/main.nf` | `<outdir>/<report_type>` |
| `maaslin2` | MaAsLin2 per feature table, plus the figure tiles shown in the report. | `modules/stats/maaslin2/main.nf` | `<outdir>/stats` |
| `mantel_test` | Mantel test across all pairs of feature tables. | `modules/stats/mantel/main.nf` | `<outdir>/stats/mantel_test` |
| `stats_report` | Render the stats report. | `modules/stats/report/main.nf` | `<outdir>` |
| `stratified_barplot` | One barplot per (pathway rank, metadata variable). | `modules/stats/stratified_pathways/main.nf` | `<outdir>/stats/stratified_pathways` |
| `stratified_metadata` | Merge the pathway abundances with the metadata and work out which | `modules/stats/stratified_pathways/main.nf` | `<outdir>/stats/stratified_pathways` |
| `trim_taxonomy` | Reformat a 16s taxonomy profile into a feature table. | `modules/stats/feature_table/main.nf` | `<outdir>/stats/features` |
